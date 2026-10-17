if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_CastBar.lua
--
--  The cast bar: build, channel ticks, timer text, update, latency overlay
--  and the cast, channel and empower handlers.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local PP = EllesmereUI.PP
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local IsPlayerSpell, GetInventoryItemID = IsPlayerSpell, GetInventoryItemID

local CHANNEL_TICK_DATA, CLASS_COLORS, ERB = I.CHANNEL_TICK_DATA, I.CLASS_COLORS, I.ERB
local GetRBFont, SetRBFont, SnapXY = I.GetRBFont, I.SetRBFont, I.SnapXY
local empowerColorA, empowerColorB = I.empowerColorA, I.empowerColorB
local GetCurrentEmpowerStage = I.GetCurrentEmpowerStage
local GetEmpowerStageColor, SmoothBarAnimate = I.GetEmpowerStageColor, I.SmoothBarAnimate
local CAST_BAR_TEXTURES, SPARK_TEX = I.CAST_BAR_TEXTURES, I.SPARK_TEX
local SetCastBarFrame, SetUpdateCastBar = I.SetCastBarFrame, I.SetUpdateCastBar
local SetStageThresholds = I.SetStageThresholds

local castBarFrame
I.castBarFrameSetters[#I.castBarFrameSetters + 1] = function(v) castBarFrame = v end
local cachedClass
I.cachedClassSetters[#I.cachedClassSetters + 1] = function(v) cachedClass = v end
local cachedStageThresholds
I.stageThresholdsSetters[#I.stageThresholdsSetters + 1] = function(v) cachedStageThresholds = v end

-- Forward declarations
local BuildCastBar
local OnCastStart, OnChannelStart, OnChannelUpdate, OnCastStop, OnEmpowerStart, OnEmpowerUpdate
local ShowChannelTicks, HideChannelTicks

BuildCastBar = function()
    local cb = ERB.db.profile.castBar
    -- blizz = a stock style dictates the geometry (both stock styles);
    -- blizzKit = the 12.1 kit (atlas fill, background, pip and text box);
    -- classic keeps the user's fill under the vanilla frame and spark.
    local blizz = ns.ERB_CastBlizz()
    local classic = ns.ERB_CastClassic()
    local blizzKit = blizz and not classic

    -- ResourceBars only claims Blizzard's player cast bar while its own
    -- replacement bar is active. The shared helper arbitrates ownership
    -- across EUI modules and releases control cleanly for other addons.
    ns.RB_SyncBlizzCastSuppress()

    if not cb.enabled then
        if castBarFrame then EllesmereUI.SetElementVisibility(castBarFrame, false) end
        return
    end

    if not castBarFrame then
        SetCastBarFrame(CreateFrame("Frame", "ERB_CastBarFrame", UIParent))
        castBarFrame:SetFrameStrata(cb.frameStrata or "MEDIUM")
        castBarFrame:SetFrameLevel(15)

        local bg = castBarFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        castBarFrame._bg = bg

        -- Border frame: child that covers the full cast bar (bar + icon)
        local bdrFrame = CreateFrame("Frame", nil, castBarFrame)
        bdrFrame:SetAllPoints(castBarFrame)
        bdrFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 5)
        castBarFrame._border = bdrFrame
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then PP.CreateBorder(bdrFrame, 0, 0, 0, 1, 1) end

        -- Clip frame to prevent bar fill from bleeding past the border
        local clipFrame = CreateFrame("Frame", nil, castBarFrame)
        clipFrame:SetClipsChildren(true)
        castBarFrame._barClip = clipFrame

        -- Status bar (inside clip frame)
        local bar = CreateFrame("StatusBar", "ERB_CastBar", clipFrame)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        castBarFrame._bar = bar
        -- NO native interpolation on this fill: the value is recomputed from
        -- GetTime() every frame and is already smooth. Easing toward a per-frame
        -- moving target makes the fill trail real progress (worst on short casts),
        -- so the bar hides on cast stop before it ever looks complete.

        -- Spark (in its own child frame inside clip so it gets clipped)
        local sparkFrame = CreateFrame("Frame", nil, clipFrame)
        sparkFrame:SetAllPoints(bar)
        sparkFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
        local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(SPARK_TEX)
        spark:SetBlendMode("ADD")
        castBarFrame._spark = spark

        -- Latency overlay (on clipFrame: below the bar's fill, so a cast's
        -- completing fill sweeps over the end-side zone)
        local latOverlay = clipFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        latOverlay:Hide()
        castBarFrame._latencyOverlay = latOverlay

        -- Channel twin on the bar frame: a channel starts FULL, so the
        -- drain-side zone spends the whole channel under the fill unless it
        -- draws above it (OVERLAY 0: over the fill, under ticks and spark).
        local latOverlayFront = bar:CreateTexture(nil, "OVERLAY", nil, 0)
        latOverlayFront:Hide()
        castBarFrame._latencyOverlayFront = latOverlayFront

        -- Spell icon
        local iconFrame = CreateFrame("Frame", nil, castBarFrame)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castBarFrame._iconFrame = iconFrame
        castBarFrame._icon = icon

        -- Optional 1px divider at the icon/bar seam (opt-in: "Show Icon Divider").
        -- That seam is otherwise interior with no border by design (see the clip-inset
        -- comment below). Parented to the border frame (pl+5), not castBarFrame itself
        -- (pl+15): a texture drawn directly on castBarFrame renders at castBarFrame's
        -- own frame level, which sits BELOW the icon and bar/clip child frames -- it
        -- would be invisible under them regardless of draw layer, since draw layer only
        -- orders content within the SAME frame, not across frames.
        local iconDivider = castBarFrame._border:CreateTexture(nil, "OVERLAY", nil, 7)
        iconDivider:Hide()
        if iconDivider.SetSnapToPixelGrid then
            iconDivider:SetSnapToPixelGrid(false)
            iconDivider:SetTexelSnappingBias(0)
        end
        castBarFrame._iconDivider = iconDivider

        -- Text overlay frame (above all bar borders)
        local textFrame = CreateFrame("Frame", nil, castBarFrame)
        textFrame:SetAllPoints(bar)
        textFrame:SetFrameLevel(25)
        castBarFrame._textFrame = textFrame

        -- Spell name text
        local nameText = textFrame:CreateFontString(nil, "OVERLAY")
        SetRBFont(nameText, GetRBFont(), 11)
        nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(false)
        castBarFrame._nameText = nameText

        -- Timer text
        local timerText = textFrame:CreateFontString(nil, "OVERLAY")
        SetRBFont(timerText, GetRBFont(), 11)
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        timerText:SetJustifyH("RIGHT")
        timerText:SetWordWrap(false)
        timerText:SetNonSpaceWrap(false)
        castBarFrame._timerText = timerText

        castBarFrame._casting = false
        castBarFrame._channeling = false
        castBarFrame._empowering = false
        castBarFrame._castID = nil
        castBarFrame._startTime = 0
        castBarFrame._endTime = 0
        castBarFrame._spellName = ""
        castBarFrame._pips = {}
        castBarFrame._numStages = 0
        castBarFrame._ticks = {}
        castBarFrame._numTicks = 0
    end
    -- Read by the per-cast fill swap (ns.ERB_SetBlizzCastFill): one field, no
    -- profile lookup. Blizzard Style only: the classic fill is the user's.
    castBarFrame._blizzFill = blizzKit or nil

    local w, h = cb.width, cb.height
    local hasIcon = cb.showIcon ~= false
    -- Total frame width includes the icon only when it is shown (a square of
    -- the bar height; under the style it also spans the text box, so the
    -- bar keeps its configured width beside it).
    local iconW = ns.ERB_CastIconW(cb)
    local totalW = w + iconW
    if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_CastBar", castBarFrame) then
        -- Override anchor owns position; just set size directly
        castBarFrame:SetSize(totalW, h)
    elseif cb.unlockPos and cb.unlockPos.point then
        -- Position managed by unlock mode -- only animate size changes.
        -- Skip reposition during unlock mode so resize does not snap the bar.
        local rp = cb.unlockPos.relPoint or cb.unlockPos.point
        local px, py = cb.unlockPos.x or 0, cb.unlockPos.y or 0
        local anchored = EllesmereUI.IsUnlockAnchored("ERB_CastBar")
        if EllesmereUI._unlockActive then
            castBarFrame:SetSize(totalW, h)
        elseif anchored and castBarFrame:GetLeft() then
            -- Anchor system owns position; just set size directly
            castBarFrame:SetSize(totalW, h)
        else
            local function ApplyCastUnlockTransform()
                local aw = castBarFrame["_barAnim_w"] or totalW
                local ah = castBarFrame["_barAnim_h"] or h
                castBarFrame:SetSize(aw, ah)
                castBarFrame:ClearAllPoints()
                -- Snap the stored CENTER/CENTER position to the pixel grid, dimension-
                -- aware (SnapXY -> SnapCenterForDim): an odd-pixel-height frame needs a
                -- +0.5px center offset for BOTH top and bottom edges to land on whole
                -- pixels. The unlock-mode drag path (castApply, near ERB_CastBar's MK()
                -- registration above) already does this; this normal-build path never
                -- did, so a raw stored position landed the center off-grid, and the
                -- border rendered thicker on one edge and missing on the opposite one.
                local sx, sy = SnapXY(px, py, castBarFrame, cb.unlockPos)
                castBarFrame:SetPoint(cb.unlockPos.point, UIParent, rp, sx, sy)
            end
            SmoothBarAnimate(castBarFrame, "w", totalW, function() ApplyCastUnlockTransform() end)
            SmoothBarAnimate(castBarFrame, "h", h, function() ApplyCastUnlockTransform() end)
        end
    else
        castBarFrame:SetSize(totalW, h)
        if not EllesmereUI._unlockActive then
            castBarFrame:ClearAllPoints()
            castBarFrame:SetPoint("CENTER", UIParent, "CENTER", cb.anchorX, cb.anchorY)
        end
    end

    -- Border: update the dedicated child border frame (PP or textured)
    if castBarFrame._border then
        -- Blizzard Style: no EUI border; the stock frame art draws on this child instead.
        local bs = blizz and 0 or (cb.borderSize or 0)
        local texKey = cb.borderTexture or "solid"
        -- "Show Behind": +5 in front of the bar, level-1 behind it.
        local pl = castBarFrame:GetFrameLevel()
        castBarFrame._border:SetFrameLevel((cb.borderBehind and not blizz) and math.max(0, pl - 1) or (pl + 5))
        -- Same lost-rect recovery as MakePixelBorder:ApplyStyle -- re-anchoring the bar
        -- stops this child's rect from resolving and the border silently vanishes.
        -- Extend Top / Extend Bottom seat it past the bar; none under a stock
        -- style, whose frame art rides this child.
        ns.ERB_AnchorBorderHost(castBarFrame._border, castBarFrame, ns.ERB_BorderExtents((not blizz) and cb or nil))
        -- Exact size only for the bar's own step: the forced 0 under the style is a substitute.
        local bpx = (not blizz) and EllesmereUI.BorderPx(cb.borderSizePx, bs, texKey) or nil
        EllesmereUI.ApplyBorderStyle(castBarFrame._border, bs,
            cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1,
            texKey, cb.borderTextureOffset, cb.borderTextureOffsetY,
            cb.borderTextureShiftX, cb.borderTextureShiftY, "resourcebars", bs, nil, bpx)
    end
    -- Bottom Separator: across the whole bar (icon included), above its border;
    -- none under a stock style or a Solid border (inert unless it was ever on).
    if cb.edgeSep or castBarFrame._erbSep then
        ns.ERB_Separators(castBarFrame, cb, (cb.edgeSep and not blizz and ns.ERB_Textured(cb)) and true or false,
            castBarFrame:GetFrameLevel() + 7)
    end

    -- Icon: left or right side (iconOnRight), full height, no inset
    local iconFrame = castBarFrame._iconFrame
    local iconOnRight = hasIcon and cb.iconOnRight
    local iconFree = ns.ERB_CastIconFree(cb)
    ns.ERB_LayoutFreeCastIcon(iconFrame, castBarFrame, cb, iconFree)
    if iconFree then
        iconFrame:Show()
    elseif hasIcon then
        -- A square of the bar height; under the style it also spans the stock
        -- text box under the bar (see ns.ERB_CastIconW), hung from the same
        -- top corner, as the unit frame cast bars do.
        iconFrame:SetSize(iconW, iconW)
        iconFrame:ClearAllPoints()
        if iconOnRight then
            iconFrame:SetPoint("TOPRIGHT", castBarFrame, "TOPRIGHT", 0, 0)
        else
            iconFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", 0, 0)
        end
        -- Blizzard Style shows the full spell art, as the stock bar does.
        if blizz then castBarFrame._icon:SetTexCoord(0, 1, 0, 1) end
        -- Classic WoW UI seats the icon inside the frame's window beside the
        -- fill, under the art child (+5) like the fill, so the frame's rim
        -- overlaps its edges as it does the bar's.
        if classic then iconFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 1) end
        iconFrame:Show()
    else
        iconFrame:Hide()
    end

    -- Optional icon/bar seam divider (opt-in "Show Icon Divider"). Same
    -- onePixel math as the perimeter border (SnapBorderTextures) so it reads
    -- as the same thickness. Anchored to iconFrame's inner edge and given
    -- only a width (both vertical anchor points already match iconFrame's
    -- own top/bottom, so it inherits the full bar height automatically).
    local iconDivider = castBarFrame._iconDivider
    -- Border Art Divider: the border style's vertical companion art in place of
    -- the solid line below (ns.ERB_CastDividerArt; inert unless it was ever on).
    local showDivider = hasIcon and not iconFree and cb.showIconDivider
    if ns.ERB_CastDividerArt(iconDivider, showDivider, iconFrame, iconOnRight, cb, blizz) then
        iconDivider:Show()
    elseif showDivider then
        local des = castBarFrame:GetEffectiveScale()
        local onePixel = des > 0 and (PP.perfect / des) or PP.mult
        local dbs = cb.borderSize or 1
        -- An exact SOLID size drives the divider too; a textured one keeps the step.
        local dtex = cb.borderTexture
        if not blizz and (not dtex or dtex == "" or dtex == "solid") then
            dbs = EllesmereUI.BorderPx(cb.borderSizePx, cb.borderSize or 0, dtex) or dbs
        end
        iconDivider:ClearAllPoints()
        iconDivider:SetWidth(math.max(onePixel, math.floor(dbs + 0.5) * onePixel))
        if iconOnRight then
            iconDivider:SetPoint("TOPRIGHT", iconFrame, "TOPLEFT", 0, 0)
            iconDivider:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMLEFT", 0, 0)
        else
            iconDivider:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 0, 0)
            iconDivider:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 0, 0)
        end
        iconDivider:SetColorTexture(cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1)
        iconDivider:Show()
    else
        iconDivider:Hide()
    end

    -- Clip frame + bar: beside the icon (or full width), full height
    local clipFrame = castBarFrame._barClip
    local bar = castBarFrame._bar
    -- No border, no inset: the bg spans the frame, so an inset with no border
    -- over it reads as a 1px background ring around the fill.
    local bdrInset = (not blizz and (cb.borderSize or 0) > 0 and PP and PP.mult) or 0
    clipFrame:ClearAllPoints()
    -- The icon-adjacent side sits FLUSH against the icon (no inset): that seam is
    -- interior with no border, and insetting it exposes a 1px background column
    -- next to the icon. Outer edges keep the inset so the fill never bleeds out.
    local clipLeft  = (iconW > 0 and not iconOnRight) and iconW or bdrInset
    local clipRight = (iconW > 0 and iconOnRight) and iconW or bdrInset
    clipFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", clipLeft, -bdrInset)
    clipFrame:SetPoint("BOTTOMRIGHT", castBarFrame, "BOTTOMRIGHT", -clipRight, bdrInset)
    clipFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 1)
    bar:ClearAllPoints()
    bar:SetAllPoints(clipFrame)

    local texKey = cb.texture
    local isBlizzard = (texKey == "blizzard")
    -- Textured Background: back to the plain background before a branch repaints it.
    if castBarFrame._bg._erbBgTex then ns.ERB_BgTexture(castBarFrame._bg, nil) end
    if blizzKit then
        -- Blizzard Style: the stock fill art follows the cast kind
        -- (ns.ERB_SetBlizzCastFill) and the background hugs the bar the way
        -- the stock frame anchors it.
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        castBarFrame._blizzFillKind = nil
        ns.ERB_SetBlizzCastFill(castBarFrame._channeling and "channel" or "cast")
        -- A bar texture, not frame chrome: the retail background under
        -- Blizzard Style, WoW Forever included.
        local bgAtlas = ns.ERB_BlizzAtlas("bg")
        if bgAtlas then
            EllesmereUI.StockAtlas(castBarFrame._bg, bgAtlas)
        else
            castBarFrame._bg:SetTexture(nil)
            castBarFrame._bg:SetColorTexture(0, 0, 0, 0.7)
        end
        castBarFrame._bg:ClearAllPoints()
        castBarFrame._bg:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", -1, 1)
        castBarFrame._bg:SetPoint("BOTTOMRIGHT", clipFrame, "BOTTOMRIGHT", 1, -1)
    elseif isBlizzard then
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        -- Classic WoW UI's seeded fill: the retail background on WoW Forever
        -- too (the EllesmereUI look keeps the client's).
        if classic then
            ns.ERB_StockAtlas(castBarFrame._bg, "UI-CastingBar-Background", true)
        else
            castBarFrame._bg:SetAtlas("UI-CastingBar-Background", true)
        end
        castBarFrame._bg:ClearAllPoints()
        castBarFrame._bg:SetAllPoints(castBarFrame)
    else
        local texPath = EllesmereUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, "Interface\\Buttons\\WHITE8x8")
        bar:SetStatusBarTexture(texPath)
        castBarFrame._bg:SetTexture(nil)
        castBarFrame._bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
        -- Textured Background: flat while Fill Color is below 100.
        if cb.textureBg and (cb.fillOpacity or 100) >= 100 then
            ns.ERB_BgTexture(castBarFrame._bg, EllesmereUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, nil),
                cb.bgR, cb.bgG, cb.bgB, cb.bgA)
        end
        ns.ApplyCastBgAnchor()
    end

    -- Bar color / gradient. Fill Opacity multiplies into the fill alpha (solid
    -- color and both gradient endpoints), so the fill turns translucent without
    -- double-dimming through a separate region alpha.
local fillTex = bar:GetStatusBarTexture()
local fillOp = (cb.fillOpacity or 100) / 100

if blizzKit then
    -- Blizzard Style: the fill atlas carries its own colour; only Fill Opacity applies.
    fillTex:SetVertexColor(1, 1, 1, fillOp)
    if castBarFrame._gradClip then castBarFrame._gradClip:Hide() end
    castBarFrame._gradientFullBar = nil
    castBarFrame._nameText:SetParent(castBarFrame._textFrame)
    castBarFrame._timerText:SetParent(castBarFrame._textFrame)
elseif cb.gradientEnabled then
    local dir = cb.gradientDir or "HORIZONTAL"

    local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, 1
    if cb.classColored then
        local cc = CLASS_COLORS[cachedClass]
        if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
    end
    fillTex:SetVertexColor(1, 1, 1, 1)
    fillTex:SetGradient(dir,
        CreateColor(fR, fG, fB, fA * fillOp),
        CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA * fillOp)
    )

    -- Hide the old clip-frame gradient if it exists from a prior session
    if castBarFrame._gradClip then castBarFrame._gradClip:Hide() end
    castBarFrame._gradientFullBar = nil

    castBarFrame._nameText:SetParent(castBarFrame._textFrame)
    castBarFrame._timerText:SetParent(castBarFrame._textFrame)
else
    if castBarFrame._gradClip then
        castBarFrame._gradClip:Hide()
    end
    castBarFrame._gradientFullBar = nil

    castBarFrame._nameText:SetParent(castBarFrame._textFrame)
    castBarFrame._timerText:SetParent(castBarFrame._textFrame)

    do
        local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, 1
        if cb.classColored then
            local cc = CLASS_COLORS[cachedClass]
            if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
        end
        fillTex:SetVertexColor(fR, fG, fB, fA * fillOp)
    end
end
    -- The fill was just repainted from the settings: a live cast re-resolves its
    -- cached settings on the next tick and re-reads the Out of Range Gray.
    castBarFrame._rangeOut = nil
    castBarFrame._cstKey = nil

    local spark = castBarFrame._spark
    -- Blizzard Style: the stock pip replaces the spark art (once; the swap is
    -- reload-gated so it never needs undoing).
    if blizzKit and not castBarFrame._blizzSpark then
        local pip = ns.ERB_BlizzAtlas("spark")
        if pip then
            castBarFrame._blizzSpark = true
            spark:SetAtlas(pip)
            -- The stock pip is drawn plain (the EUI spark art is additive).
            spark:SetBlendMode("BLEND")
        end
    end
    -- Classic WoW UI: the vanilla spark file (additive, like the EUI art) once.
    -- It stands taller than the bar and draws over the frame art, so its
    -- host leaves the clip frame for the bar frame itself (anchors kept).
    if classic and not castBarFrame._classicSpark then
        castBarFrame._classicSpark = true
        spark:SetTexture(ns.ERB_CLASSIC.spark)
        local sf = spark:GetParent()
        sf:SetParent(castBarFrame)
        sf:ClearAllPoints()
        sf:SetAllPoints(bar)
    end
    -- Above the frame art (+5) and the icon (+6), under the texts (25);
    -- re-asserted like the art frame's level.
    if classic then spark:GetParent():SetFrameLevel(castBarFrame:GetFrameLevel() + 7) end
    if cb.showSpark then
        -- The vanilla spark is a square scaled with the bar, its centre a
        -- little above the bar's centre line.
        local sparkY = 0
        if classic then
            local C = ns.ERB_CLASSIC
            local ss = C.sparkSize * h / C.barH
            spark:SetSize(ss, ss)
            sparkY = C.sparkY * h / C.barH
        else
            spark:SetSize(8, h)
        end
        spark:ClearAllPoints()

        if cb.gradientEnabled and castBarFrame._gradClip then
            spark:SetPoint("CENTER", castBarFrame._gradClip, "RIGHT", 0, sparkY)
        else
            spark:SetPoint("CENTER", fillTex, "RIGHT", 0, sparkY)
        end

        spark:Show()
    else
        spark:Hide()
    end

    -- Latency overlay style. Width is computed per cast from GetNetStats (live network
    -- latency), so no event timing is involved and spell-queueing cannot break it.
    if cb.latencyEnabled then
        local lR, lG, lB, lA = cb.latencyR or 0.835, cb.latencyG or 0.290, cb.latencyB or 0.290, cb.latencyA or 1
        local texKey = cb.texture
        local texPath
        if texKey and texKey ~= "none" and texKey ~= "blizzard" then
            texPath = EllesmereUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, nil)
        end
        -- Style both overlays; ShowLatencyOverlay picks one per cast kind
        -- (channels use the front twin so the zone survives the full fill).
        for i = 1, 2 do
            local lo = (i == 1) and castBarFrame._latencyOverlay
                or castBarFrame._latencyOverlayFront
            if lo then
                if texPath then
                    lo:SetTexture(texPath)
                    lo:SetVertexColor(lR, lG, lB, lA)
                else
                    lo:SetColorTexture(lR, lG, lB, lA)
                end
            end
        end
    else
        if castBarFrame._latencyOverlay then castBarFrame._latencyOverlay:Hide() end
        if castBarFrame._latencyOverlayFront then castBarFrame._latencyOverlayFront:Hide() end
        castBarFrame._latencySuffix = nil
    end
    -- Text width cap from the bar's RENDERED width, so width-matching and border
    -- insets are accounted for. Falls back to cb.width before first layout.
    local barW = bar:GetWidth()
    if not barW or barW < 10 then barW = cb.width end

    -- Cast text side-aware layout (mirrors nameplates / unit frames): the duration
    -- reserves a slot on its side and pushes the spell text inward when they share
    -- one; center is never pushed. Visibility stays governed by showTimer /
    -- showSpellText (the dropdown "None" sets those flags false).
    local timerW   = (cb.timerSize or 11) * 2.2
    local durSide   = cb.timerSide or "right"
    local spellSide = cb.spellTextSide or "left"

    -- Timer / duration text (auto-sized, anchored to its side)
    local timerText = castBarFrame._timerText
    if cb.showTimer then
        SetRBFont(timerText, GetRBFont(), cb.timerSize or 11)
        local pt, xb, jh = ns.GetCastTextAnchor(durSide, false, timerW)
        timerText:ClearAllPoints()
        timerText:SetJustifyH(jh)
        timerText:SetPoint(pt, bar, pt, xb + (cb.timerX or 0), cb.timerY or 0)
        timerText:Show()
        ns.ERB_CastTextColor(timerText, cb.timerR, cb.timerG, cb.timerB, cb.timerA)
    else
        timerText:Hide()
    end

    -- Spell name text
    local nameText = castBarFrame._nameText
    if cb.showSpellText then
        SetRBFont(nameText, GetRBFont(), cb.spellTextSize or 11)
        local pt, xb, jh = ns.GetCastTextAnchor(spellSide, cb.showTimer and durSide == spellSide, timerW)
        nameText:ClearAllPoints()
        nameText:SetJustifyH(jh)
        nameText:SetPoint(pt, bar, pt, xb + (cb.spellTextX or 0), cb.spellTextY or 0)
        if spellSide == "center" then
            nameText:SetWidth(barW - 8 - (cb.showTimer and 2 * timerW or 0))
        else
            nameText:SetWidth(barW - 8 - (cb.showTimer and timerW or 0))
        end
        nameText:Show()
        ns.ERB_CastTextColor(nameText, cb.spellTextR, cb.spellTextG, cb.spellTextB, cb.spellTextA)
    else
        nameText:Hide()
    end
    -- Re-flow so a live JustifyH change takes effect on already-rendered text.
    ns.ReflowFontString(timerText)
    ns.ReflowFontString(nameText)
    -- Blizzard Style chrome: frame art + text box (moves the spell name under the bar).
    if blizz then ns.ERB_ApplyBlizzCastChrome(cb, barW) end

    -- Hide pips (build reset), then RE-LAY them for an in-flight empower:
    -- same wipe-sticks class as the channel ticks below (field: Evokers
    -- randomly losing all stage marks for one empowered cast whenever a
    -- width-match/anchor re-apply landed mid-cast). Geometry is final here,
    -- so the pips re-anchor against the rebuilt bar.
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end
    if castBarFrame._empowering and castBarFrame._empStages then
        ns.ERB_LayoutEmpowerPips(castBarFrame._empStages)
    end

    -- Hide channel ticks (build reset), then RE-SHOW them for an in-flight
    -- channel: ApplyAll can run mid-channel (unlock rebuilds, width-match and
    -- anchor-link re-applies, options edits, spec-override/profile refreshes --
    -- field: Arcane Missiles marks vanishing when a Bloodlust buff arrived
    -- mid-channel), and without the re-show the wipe sticks until the NEXT
    -- channel starts: a channel whose reported window never changes gets no
    -- further CHANNEL_UPDATE to redraw them. Geometry is final here, so the
    -- marks re-anchor against the rebuilt bar.
    HideChannelTicks()
    if castBarFrame._channeling and castBarFrame._tickSpellID then
        ShowChannelTicks(castBarFrame._tickSpellID)
    end

    -- Idle when not casting (empty bar with "Always Show", else hidden). Runs LAST
    -- on purpose: the idle state re-suppresses the spark and icon the style pass
    -- above just re-showed.
    if not castBarFrame._casting and not castBarFrame._channeling and not castBarFrame._empowering then
        ns.ShowIdleCastBar()
    else
        ns.ActivateCastBar()
    end
end

-- Some set bonuses never register via IsPlayerSpell or a player aura.
-- Count equipped items whose set-bonus data lists this spellID; two or
-- more equipped means the 2pc bonus is up.
local function IsSetBonusSpellActive(spellID)
    if not (C_Item and C_Item.GetSetBonusesForSpecializationByItemID) then
        return false
    end
    local specID = _G._ERB_ResolveSpecIDCached and _G._ERB_ResolveSpecIDCached()
    if not specID then return false end
    local matches = 0
    for slot = 1, 19 do
        local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
        if itemID then
            local ok, bonusSpellIDs = pcall(C_Item.GetSetBonusesForSpecializationByItemID, specID, itemID)
            if ok and type(bonusSpellIDs) == "table" then
                for _, id in ipairs(bonusSpellIDs) do
                    if id == spellID then
                        matches = matches + 1
                        break
                    end
                end
            end
        end
    end
    return matches >= 2
end

-- Channel tick marks: vertical marks on the cast bar for channeled spells
-- listed in CHANNEL_TICK_DATA. The penultimate tick (last safe chain/clip
-- point) draws slightly wider in gold. Layout mirrors the empower pip code above.
ShowChannelTicks = function(spellID)
    if not castBarFrame then return end
    -- Stashed so a mid-channel bar rebuild can re-show this channel's marks
    -- (see the BuildCastBar tail). Stale values are inert: the re-show gates
    -- on _channeling, and every channel start restores the stash.
    castBarFrame._tickSpellID = spellID
    local cb = ERB.db.profile.castBar
    if not cb.showChannelTicks then return end

    local tickData = CHANNEL_TICK_DATA[spellID]
    local wantTicks = tickData and (cb.showTickMarks or cb.showLastTick)

    -- Nothing to draw: hide stale marks and bail
    if not wantTicks then
        for i = 1, #castBarFrame._ticks do
            castBarFrame._ticks[i]:Hide()
        end
        castBarFrame._numTicks = 0
        if castBarFrame._gcdMark then castBarFrame._gcdMark:Hide() end
        return
    end

    local bar = castBarFrame._bar
    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then return end

    -- Physical-pixel helpers (same approach as empower pips): PP.perfect /
    -- effectiveScale is one PHYSICAL pixel in the bar's local units, so mark
    -- widths are exact physical pixel counts at every UI scale. The old
    -- effectiveScale rounding treated the target as UI units and drifted
    -- between 1 and 3 physical pixels depending on scale.
    local effectiveScale = bar:GetEffectiveScale()
    local PPc = EllesmereUI and EllesmereUI.PP
    local onePx = ((PPc and PPc.perfect) or 1) / effectiveScale
    local tickWidth = 2 * onePx
    local highlightWidth = 3 * onePx
    local snappedHeight = (PPc and PPc.SnapForES)
        and PPc.SnapForES(barHeight, effectiveScale) or barHeight

    -- Tick marks
    if wantTicks then
        -- Interior mark positions as fractions of elapsed channel time
        -- (ascending; the LAST entry is the gold last-safe-clip mark).
        -- Three cadence models:
        --   ticks = N         : N evenly spaced damage events ending at the
        --                       channel end -> marks at i/N
        --   tickInterval = s  : fixed short cadence -> floor(duration/s) segments
        --   intervalCount = N : damage lands AT channel start, then once every
        --                       duration/N. Marks sit on each later event, and
        --                       a recast begun BEFORE the old channel ended
        --                       (proc-driven chaining) inherits the outgoing
        --                       cast's rhythm: its first mark lands where the
        --                       old cadence's next tick was due, and the
        --                       channel runs carry + N intervals, so the
        --                       interval is the window AFTER the carry over N
        --                       (dividing the whole window stretches every
        --                       later mark late by carry/N). Haste and
        --                       whole-cast talents are absorbed by working in
        --                       fractions of the ACTUAL duration; only
        --                       interval-only modifiers change N.
        local positions
        if tickData.intervalCount then
            local dur = castBarFrame._endTime - castBarFrame._startTime
            if dur > 0 then
                local N = tickData.intervalCount
                if tickData.modSpell and IsPlayerSpell(tickData.modSpell) then
                    N = tickData.modIntervalCount or N
                end
                local startT = castBarFrame._startTime
                -- Chain carry is computed ONCE per cast and cached: duration
                -- updates re-enter here for the same cast, and re-starts
                -- within 0.5s are duplicate events for the SAME channel
                -- (hover-style refires), never a chain.
                local tracked = castBarFrame._cadStart
                if not tracked or (startT - tracked) >= 0.5 then
                    local carry = 0
                    local pEnd = castBarFrame._cadPrevEnd
                    local pInt = castBarFrame._cadPrevInterval
                    if pEnd and pInt and pInt > 0 and startT < pEnd - 0.01 then
                        carry = math.fmod(pEnd - startT, pInt)
                        if carry < 0.01 then carry = 0 end
                    end
                    castBarFrame._cadCarry = carry
                    castBarFrame._cadStart = startT
                end
                local carry = castBarFrame._cadCarry or 0
                local interval = (dur - carry) / N
                if interval <= 0.01 then
                    carry = 0
                    interval = dur / N
                end
                -- Bank this cast's TRUE cadence for a possible chain into the
                -- next: a chained cast's whole window over N is not its
                -- interval, and banking it would misplace a chain of chains.
                castBarFrame._cadPrevEnd = castBarFrame._endTime
                castBarFrame._cadPrevInterval = interval
                positions = {}
                local t = carry
                if t < 0.01 then t = interval end
                while t < dur - interval * 0.05 and #positions < 12 do
                    positions[#positions + 1] = t / dur
                    t = t + interval
                end
            end
        elseif tickData.missiles then
            -- Fencepost cadence: the first missile fires AT channel start and
            -- the last AT channel end, so M missiles span M-1 intervals and
            -- interior marks sit at i/(M-1). A recast begun while the
            -- previous channel of the SAME spell was still running fires one
            -- missile immediately (at the bar start, no mark) and then keeps
            -- the OUTGOING cast's schedule: its first mark lands where the
            -- old cadence's next missile was due, and the channel runs that
            -- much longer -- one more interior mark than a fresh cast.
            local M = tickData.missiles
            if tickData.addMissiles then
                for id, extra in pairs(tickData.addMissiles) do
                    -- Talent, player aura, or item set bonus -- any counts.
                    if IsPlayerSpell(id)
                        or (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
                            and C_UnitAuras.GetPlayerAuraBySpellID(id))
                        or IsSetBonusSpellActive(id) then
                        M = M + extra
                    end
                end
            end
            local dur = castBarFrame._endTime - castBarFrame._startTime
            local startT = castBarFrame._startTime
            -- Chain carry is computed ONCE per cast, keyed on the channel
            -- castID: a mid-cast CHANNEL_UPDATE can re-time the reported
            -- window while the live channel keeps its snapshotted cadence
            -- (observed with Bloodlust landing mid-channel), and hover
            -- refires duplicate events -- both re-enter here for the SAME
            -- cast and must not chain the cast onto itself. The 0.5s start
            -- window is the fallback when no castID is available.
            local castID = castBarFrame._castID
            local sameCast
            if castID and castBarFrame._mslCastID then
                sameCast = (castID == castBarFrame._mslCastID)
            else
                sameCast = castBarFrame._mslStart
                    and (startT - castBarFrame._mslStart) < 0.5
            end
            if not sameCast then
                local carry = 0
                local pEnd = castBarFrame._mslPrevEnd
                local pInt = castBarFrame._mslPrevInterval
                if castBarFrame._mslPrevSpell == spellID
                    and pEnd and pInt and pInt > 0 and startT < pEnd - 0.01 then
                    -- The missile grid is anchored at the channel END, so
                    -- time-to-next-missile is (pEnd - startT) mod pInt.
                    carry = math.fmod(pEnd - startT, pInt)
                    -- Near-zero carry is grid-aligned, and a recast right
                    -- after a missile (carry ~= a full interval) has been
                    -- observed to LOSE the bonus missile: both lay out
                    -- like a fresh cast.
                    if carry < 0.01 or carry > pInt - 0.05 then carry = 0 end
                end
                castBarFrame._mslCarry = carry
                castBarFrame._mslCastID = castID
                castBarFrame._mslStart = startT
            end
            local carry = castBarFrame._mslCarry or 0
            -- Chained layout: the reported duration is carry plus M-1
            -- intervals, so marks sit at carry + k*interval as fractions of
            -- the reported window.
            local chained = false
            if carry > 0 and dur > 0 then
                local interval = (dur - carry) / (M - 1)
                if interval > 0.01 then
                    positions = {}
                    local t = carry
                    while t < dur - interval * 0.05 and #positions < 12 do
                        positions[#positions + 1] = t / dur
                        t = t + interval
                    end
                    if #positions > 0 then chained = true else positions = nil end
                end
            end
            -- Fresh layout: pure fractions, independent of the reported
            -- window. Also the fallback when the chained math degenerates
            -- (carry at or past the reported end, non-positive duration), so
            -- a mid-channel re-report can never blank the marks outright.
            if not positions then
                positions = {}
                for i = 1, min(M - 2, 12) do
                    positions[i] = i / (M - 1)
                end
            end
            -- Bank this cast's cadence for a possible chain into the next.
            if dur > 0 then
                castBarFrame._mslPrevEnd = castBarFrame._endTime
                castBarFrame._mslPrevInterval = (chained and (dur - carry) or dur) / (M - 1)
                castBarFrame._mslPrevSpell = spellID
            end
        else
            local numTicks
            if tickData.tickInterval then
                local channelDuration = castBarFrame._endTime - castBarFrame._startTime
                if channelDuration > 0 then
                    numTicks = floor(channelDuration / tickData.tickInterval)
                else
                    numTicks = 0
                end
            else
                numTicks = tickData.ticks
                if tickData.modSpell and IsPlayerSpell(tickData.modSpell) then
                    numTicks = tickData.modTicks
                end
            end
            if numTicks and numTicks > 1 then
                positions = {}
                for i = 1, numTicks - 1 do
                    positions[i] = i / numTicks
                end
            end
        end

        local count = positions and #positions or 0

        -- Pre-read colors once outside the loop
        local showTickMarks = cb.showTickMarks
        local showLastTick = cb.showLastTick
        local tmR, tmG, tmB, tmA = cb.tickMarksR or 1.0, cb.tickMarksG or 1.0, cb.tickMarksB or 1.0, cb.tickMarksA or 0.7
        local ltR, ltG, ltB, ltA = cb.lastTickR or 1.0, cb.lastTickG or 0.82, cb.lastTickB or 0.0, cb.lastTickA or 0.95

        for i = 1, count do
            local isLastTick = (i == count)

            -- Every index is filled, including the ones this pass hides: _ticks
            -- is walked with # (the stale-mark trims below, HideChannelTicks),
            -- so a hole at [1] would make the length 0 and end every sweep.
            local tick = castBarFrame._ticks[i]
            if not tick then
                tick = bar:CreateTexture(nil, "OVERLAY", nil, 3)
                -- Exact-width 1px-class art: keep the engine's texel
                -- snapping out of it or it re-rounds our aligned edges.
                if tick.SetSnapToPixelGrid then
                    tick:SetSnapToPixelGrid(false)
                    tick:SetTexelSnappingBias(0)
                end
                castBarFrame._ticks[i] = tick
            end

            if not showTickMarks and not isLastTick then
                tick:Hide()
            else
                local isGold = isLastTick and showLastTick
                local w = isGold and highlightWidth or tickWidth
                -- The bar drains, so a mark at time-fraction f draws at
                -- (1 - f) of the width from the left. The center is snapped
                -- WIDTH-AWARE so both edges land on the physical grid -- an
                -- odd-pixel mark centered on a plain grid point straddles it
                -- and blurs.
                local rawOffset = barWidth * (1 - positions[i])
                local snappedOffset = (PPc and PPc.SnapCenterForDim)
                    and PPc.SnapCenterForDim(rawOffset, w, effectiveScale)
                    or (floor(rawOffset * effectiveScale + 0.5) / effectiveScale)

                if isGold then
                    tick:SetColorTexture(ltR, ltG, ltB, ltA)
                else
                    tick:SetColorTexture(tmR, tmG, tmB, tmA)
                end
                tick:SetSize(w, snappedHeight)

                tick:ClearAllPoints()
                tick:SetPoint("CENTER", bar, "LEFT", snappedOffset, 0)
                tick:Show()
            end
        end

        -- Hide extras from a previous channel that had more marks
        for i = count + 1, #castBarFrame._ticks do
            castBarFrame._ticks[i]:Hide()
        end

        castBarFrame._numTicks = count + 1
    else
        for i = 1, #castBarFrame._ticks do
            castBarFrame._ticks[i]:Hide()
        end
        castBarFrame._numTicks = 0
    end

    -- GCD boundary mark removed (UnitSpellHaste returns secret values in combat)
    if castBarFrame._gcdMark then castBarFrame._gcdMark:Hide() end
end

HideChannelTicks = function()
    if not castBarFrame or not castBarFrame._ticks then return end
    for i = 1, #castBarFrame._ticks do
        castBarFrame._ticks[i]:Hide()
    end
    castBarFrame._numTicks = 0
    if castBarFrame._gcdMark then
        castBarFrame._gcdMark:Hide()
    end
end


-- Cast/channel timer label. It shows one decimal, changing ~10x/sec while this runs
-- every frame: unconditional formatting would rebuild an identical string five of every
-- six frames (format+concat allocations plus SetText). Only touch the FontString when
-- the displayed tenth actually changes. On ns, not a file local.
function ns.SetCastTimerText(f, now, totalDurMode, totalSuffix, latSuffix)
    local remaining = f._endTime - now
    if remaining > 0 then
        local shown = totalDurMode and (now - f._startTime) or remaining
        local tenths = floor(shown * 10)
        if tenths ~= f._timerTenths then
            f._timerTenths = tenths
            if totalDurMode then
                f._timerText:SetText(format("%.1f", shown) .. (totalSuffix or ""))
            elseif latSuffix then
                f._timerText:SetText(format("%.1f", shown) .. latSuffix)
            else
                f._timerText:SetText(format("%.1f", shown))
            end
        end
    elseif f._timerTenths ~= -1 then
        -- -1 marks "already blanked" so the empty case skips the re-SetText too.
        f._timerTenths = -1
        f._timerText:SetText("")
    end
end

-- Engine-driven cast fill, same plumbing as nameplate cast bars: hand the cast's
-- duration object to the inner StatusBar and the C engine animates the fill with
-- zero Lua per frame (pushback, haste, stage changes included). Falls back to
-- the Lua fill in UpdateCastBar when the duration API is unavailable or returns
-- nil. Re-called from DELAYED/CHANNEL_UPDATE/EMPOWER_UPDATE so a mid-cast time
-- change retargets the engine timer. Returns true when the timer is armed.
ns.ApplyCastTimer = function(kind)
    if not castBarFrame then return end
    castBarFrame._nativeFill = nil
    local bar = castBarFrame._bar
    local sb = bar and bar._sb
    if not (sb and sb.SetTimerDuration and Enum and Enum.StatusBarTimerDirection) then
        return
    end
    local durObj, dir
    if kind == "channel" then
        durObj = UnitChannelDuration and UnitChannelDuration("player")
        dir = Enum.StatusBarTimerDirection.RemainingTime
    elseif kind == "empower" then
        -- true = include the hold-at-max window, matching the event mirrors
        durObj = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration("player", true)
        dir = Enum.StatusBarTimerDirection.ElapsedTime
    else
        durObj = UnitCastingDuration and UnitCastingDuration("player")
        dir = Enum.StatusBarTimerDirection.ElapsedTime
    end
    if not durObj then return end
    sb:SetTimerDuration(durObj, nil, dir)
    -- Snap to the timer's current position or the fill sweeps in from whatever
    -- value the previous cast left behind.
    if sb.SetToTargetValue then sb:SetToTargetValue() end
    castBarFrame._nativeFill = true
    return true
end

SetUpdateCastBar(function(dt)
    if not castBarFrame then return end
    -- NEVER gate this on IsShown(): SetElementVisibility fades an idle cast bar to
    -- alpha 0 instead of calling Hide(), so IsShown() is constant-true for the
    -- whole session and the entire body would run every frame with no cast in
    -- flight. The cast-state gate below is the real guard.
    if not (castBarFrame._casting or castBarFrame._empowering or castBarFrame._channeling) then
        return
    end


    local now = GetTime()
    local bar = castBarFrame._bar

    -- Per-cast constants: none can change while a cast is in flight, so resolving
    -- them per frame is a three-deep config walk plus field reads 60x/sec.
    -- Resolved once per cast, keyed on start time (changes on every new cast and
    -- each channel update, so no stale cache is possible).
    if castBarFrame._cstKey ~= castBarFrame._startTime then
        castBarFrame._cstKey = castBarFrame._startTime
        local cb = ERB.db.profile.castBar
        castBarFrame._cstShowTimer  = cb.showTimer
        castBarFrame._cstTotalMode  = cb.showTimer and cb.showTotalDuration
        castBarFrame._cstEmpStages  = cb.coloredEmpowerStages
        castBarFrame._cstFillAlpha  = (cb.fillOpacity or 100) / 100
        -- The fill texture only changes on rebuild, so caching it here removes a
        -- GetStatusBarTexture call from the spark path below.
        castBarFrame._cstFillTex    = bar:GetStatusBarTexture()
        -- bar:SetValue is NOT the widget method: BuildBar replaces it with a Lua
        -- vararg wrapper forwarding to the inner clipped StatusBar, for the
        -- optional "Smooth Bars" interpolation the cast bar never uses. Hold the
        -- inner bar and drive it directly instead of paying that call per frame.
        castBarFrame._cstSB         = bar._sb
        -- Native easing between redraws (same mechanism as the GCD bar): the
        -- engine renders intermediate positions every frame, so the redraw rate
        -- can drop without visible stepping.
        -- Smooth Bar Animation off: plain SetValue at true progress, and no
        -- fill lead -- there is no ease to trail the timeline.
        local smooth = cb.smoothFill ~= false
        castBarFrame._cstInterp     = smooth and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        castBarFrame._cstLead       = smooth and 0.08 or 0
        -- Raw mode hands the fill to the per-frame writer (below the cast
        -- tick): plain 20Hz SetValues visibly step, and the engine has no
        -- linear interpolation mode to carry them between redraws.
        castBarFrame._rawFill = not smooth
        if castBarFrame._rawFill and not castBarFrame._nativeFill and ns._rawFillDriver then
            ns._rawFillDriver:Show()
        end
        -- Out of Range Gray: armed for this cast only while the option is on and
        -- the spell has a range (self casts, crafting and mounts never read it).
        local sid = castBarFrame._spellID
        castBarFrame._cstRangeSpell = (cb.outOfRangeGray and sid and C_Spell.SpellHasRange(sid)) and sid or nil
        castBarFrame._cstRangeAt = 0
    end
    -- Out of Range Gray: at most five target range reads a second, on this tick,
    -- during an armed cast; the fill repaints only when the answer flips.
    local rangeSpell = castBarFrame._cstRangeSpell
    if rangeSpell and now >= castBarFrame._cstRangeAt then
        castBarFrame._cstRangeAt = now + 0.2
        ns.ERB_CastRangeTint(C_Spell.IsSpellInRange(rangeSpell, "target") == false)
    end
    local showTimer = castBarFrame._cstShowTimer

    local latSuffix = castBarFrame._latencySuffix
    local totalDurMode = castBarFrame._cstTotalMode
    -- Cache the " / X.X" suffix once per cast (total duration is constant)
    local totalSuffix = totalDurMode and castBarFrame._totalDurSuffix

    if castBarFrame._casting or castBarFrame._empowering then
        -- Safety: if cast/empower ran 1s past expected end, force stop.
        -- Catches missed EMPOWER_STOP events under network desync.
        if castBarFrame._endTime and now > castBarFrame._endTime + 1 then
            OnCastStop()
            return
        end
        local castDur = castBarFrame._endTime - castBarFrame._startTime
        local progress = (castDur > 0) and ((now - castBarFrame._startTime) / castDur) or 0
        progress = min(max(progress, 0), 1)
        -- The eased SetValue chases a target computed at the LAST 20Hz tick,
        -- so the drawn fill trails true time by roughly one tick plus the
        -- ease-out's convergence residue and dies ~4% short when the stop
        -- lands (measured: rendered 0.96 at dtEnd 0). Lead the fill target by
        -- tick + residue (user-calibrated; 0 when smoothing is off) so the
        -- ease converges ON the true timeline; stages and text below keep
        -- using true progress.
        local fillProgress = (castDur > 0) and ((now + castBarFrame._cstLead - castBarFrame._startTime) / castDur) or 0
        fillProgress = min(max(fillProgress, 0), 1)
        -- Fill: only the fallback path draws from Lua. Progress is still computed
        -- above when the engine timer owns the fill (ns.ApplyCastTimer), because
        -- the empower stage coloring below derives its stage from it.
        -- Raw mode: the per-frame writer owns the fill instead.
        if not (castBarFrame._nativeFill or castBarFrame._rawFill) then
            if castBarFrame._cstSB then
                castBarFrame._cstSB:SetValue(fillProgress, castBarFrame._cstInterp)
            else
                bar:SetValue(fillProgress, castBarFrame._cstInterp)
            end
            -- Size the gradient clip frame to match the fill width
            if castBarFrame._gradientFullBar and castBarFrame._gradClip then
                castBarFrame._gradClip:SetWidth(max(0.01, bar:GetWidth() * fillProgress))
            end
        end

        -- Apply empowered stage coloring if enabled
        if castBarFrame._empowering and castBarFrame._cstEmpStages and not castBarFrame._rangeOut then
            local numStages = castBarFrame._numStages or 0
            local stage = GetCurrentEmpowerStage(progress, numStages)
            local r, g, b = GetEmpowerStageColor(stage, numStages)

            -- Apply color to bar or gradient (fill alpha keeps Fill Opacity)
            if castBarFrame._gradientFullBar and castBarFrame._gradTex then
                empowerColorA:SetRGBA(r, g, b, 1)
                empowerColorB:SetRGBA(r, g, b, 1)
                castBarFrame._gradTex:SetGradient("HORIZONTAL", empowerColorA, empowerColorB)
            else
                castBarFrame._cstFillTex:SetVertexColor(r, g, b, castBarFrame._cstFillAlpha)
            end
            castBarFrame._empowerColorApplied = true
        end

        if showTimer then
            ns.SetCastTimerText(castBarFrame, now, totalDurMode, totalSuffix, latSuffix)
        end
    elseif castBarFrame._channeling then
        -- Same 1s overrun safety the cast branch has. CHANNEL_UPDATE keeps
        -- _endTime current for every legitimate extension, so a channel still
        -- running a second past its end has lost its stop event -- and without
        -- this the bar has no way back to idle.
        if castBarFrame._endTime and now > castBarFrame._endTime + 1 then
            OnCastStop()
            return
        end
        if not (castBarFrame._nativeFill or castBarFrame._rawFill) then
            local chanDur = castBarFrame._endTime - castBarFrame._startTime
            -- Same lead as the cast branch, mirrored for the drain
            -- (measured: channels ended rendered at 0.018 instead of 0).
            local progress = (chanDur > 0) and ((castBarFrame._endTime - now - castBarFrame._cstLead) / chanDur) or 0
            progress = min(max(progress, 0), 1)
            if castBarFrame._cstSB then
                castBarFrame._cstSB:SetValue(progress, castBarFrame._cstInterp)
            else
                bar:SetValue(progress, castBarFrame._cstInterp)
            end
            -- Size the gradient clip frame to match the fill width
            if castBarFrame._gradientFullBar and castBarFrame._gradClip then
                castBarFrame._gradClip:SetWidth(max(0.01, bar:GetWidth() * progress))
            end
        end
        if showTimer then
            ns.SetCastTimerText(castBarFrame, now, totalDurMode, totalSuffix, latSuffix)
        end
    end

    -- Spark position. The spark anchors to the RIGHT edge of the fill and the
    -- engine already moves it as the fill grows, so re-anchoring to the same target
    -- costs two API calls for nothing. The target changes only on a gradient toggle.
    if castBarFrame._spark:IsShown() then
        local target
        if castBarFrame._gradientFullBar and castBarFrame._gradClip and castBarFrame._gradClip:IsShown() then
            target = castBarFrame._gradClip
        else
            target = castBarFrame._cstFillTex
        end
        if castBarFrame._sparkAnchor ~= target then
            castBarFrame._sparkAnchor = target
            castBarFrame._spark:ClearAllPoints()
            castBarFrame._spark:SetPoint("CENTER", target, "RIGHT", 0, 0)
        end
    end
end)

-- Latency overlay helper. Called once per cast/channel start: measures actual
-- per-spell latency (button press to server confirmation) and sizes the
-- overlay as that fraction of the total cast duration.
local function ShowLatencyOverlay(castType)
    if not castBarFrame then return end
    -- Channels use the front twin: the bar starts full, so the drain-side
    -- zone must draw above the fill to be visible at all. Casts keep the
    -- behind texture -- the fill sweeps over the zone as it completes.
    local behind = castBarFrame._latencyOverlay
    local front  = castBarFrame._latencyOverlayFront
    local overlay = (castType == "channel") and (front or behind) or behind
    local other   = (overlay == front) and behind or front
    if other then other:Hide() end
    if not overlay then return end

    local cb = ERB.db.profile.castBar
    if not cb.latencyEnabled then
        overlay:Hide(); castBarFrame._latencySuffix = nil; return
    end

    -- Read live network latency straight from the engine: queue-proof, since it
    -- doesn't depend on timing between cast events (spell-queueing and
    -- frame-coherent GetTime() both make that unreliable). Casts round-trip
    -- through the world server, so its latency is the relevant one; fall back to
    -- home/realm value only while world latency hasn't been measured yet.
    local _, _, latencyHome, latencyWorld = GetNetStats()
    local latencyMs = latencyWorld
    if latencyMs <= 0 then latencyMs = latencyHome end
    local latencySec = latencyMs / 1000
    local castDur = castBarFrame._endTime - castBarFrame._startTime
    local barWidth = castBarFrame._bar:GetWidth()

    if latencySec <= 0 or castDur <= 0 or barWidth <= 0 then
        overlay:Hide(); castBarFrame._latencySuffix = nil; return
    end

    -- Build the suffix string once; reused every frame by UpdateCastBar
    if cb.latencyShowText then
        castBarFrame._latencySuffix = " (" .. floor(latencySec * 1000 + 0.5) .. "ms)"
    else
        castBarFrame._latencySuffix = nil
    end

    -- Size as a fraction of the cast, clamped to [1px, full bar] so it always
    -- renders something and never overruns the bar on a lag spike.
    local width = barWidth * (latencySec / castDur)
    if width < 1 then width = 1 elseif width > barWidth then width = barWidth end

    local clip = castBarFrame._barClip
    overlay:ClearAllPoints()
    if castType == "channel" then
        overlay:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
    else
        overlay:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    end
    overlay:SetWidth(width)
    overlay:Show()
end

local function HideLatencyOverlay()
    if not castBarFrame then return end
    if castBarFrame._latencyOverlay then castBarFrame._latencyOverlay:Hide() end
    if castBarFrame._latencyOverlayFront then castBarFrame._latencyOverlayFront:Hide() end
    castBarFrame._latencySuffix = nil
end

-- Cast bar background anchoring. At Fill Opacity 100 the background spans the
-- whole frame. Below 100 it anchors to the fill texture's moving right edge so
-- the translucent fill reveals the world behind it -- the anchor is
-- relational, so it tracks cast progress on its own. An idle bar has no fill to
-- trail and that anchoring would leave the spell icon's slot uncovered, so the
-- idle state always spans the frame.
function ns.ApplyCastBgAnchor()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    -- The Blizzard texture draws an atlas background that always spans the
    -- frame; BuildCastBar anchors that one itself. Same for Blizzard Style
    -- (the build stamp, never the profile: the style is latched per session).
    if cb.texture == "blizzard" or castBarFrame._blizzFill then return end
    local bar = castBarFrame._bar
    local casting = castBarFrame._casting or castBarFrame._channeling or castBarFrame._empowering
    castBarFrame._bg:ClearAllPoints()
    if casting and (cb.fillOpacity or 100) < 100 then
        castBarFrame._bg:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        castBarFrame._bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    else
        castBarFrame._bg:SetAllPoints(castBarFrame)
    end
end

-- Idle / active cast bar state. Every path that ends a cast routes through
-- ns.ShowIdleCastBar, so the idle look never depends on how the cast finished.
-- With "Always Show" off it fades to alpha 0; with it on the frame stays on
-- screen showing just background and border. ns.ActivateCastBar is the mirror
-- image: undoes whatever the idle state suppressed for a live cast.
function ns.ShowIdleCastBar()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar

    -- Empty the fill. A plain SetValue also cancels the engine-driven cast
    -- timer armed by ns.ApplyCastTimer, which would otherwise keep animating
    -- the fill from the finished cast's duration object.
    castBarFrame._bar:SetValue(0)
    castBarFrame._nativeFill = nil
    castBarFrame._cstKey = nil
    if ns._rawFillDriver then ns._rawFillDriver:Hide() end
    if castBarFrame._rangeOut then ns.ERB_CastRangeTint(false) end

    -- Cast decoration has nothing to show without a cast. The spark in
    -- particular is anchored to the RIGHT edge of the fill, so at value 0 it
    -- would sit as a sliver on the empty bar's left edge.
    castBarFrame._nameText:SetText("")
    castBarFrame._timerText:SetText("")
    castBarFrame._timerTenths = -1  -- "already blanked" (see ns.SetCastTimerText)
    if castBarFrame._iconFrame then castBarFrame._iconFrame:Hide() end
    if castBarFrame._spark then castBarFrame._spark:Hide() end
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0
    HideChannelTicks()
    HideLatencyOverlay()
    ns.ApplyCastBgAnchor()

    if cb.alwaysShow and cb.enabled and not ns._erbCastPadHidden then
        castBarFrame:Show()
        EllesmereUI.SetElementVisibility(castBarFrame, true)
    else
        EllesmereUI.SetElementVisibility(castBarFrame, false)
    end
end

function ns.ActivateCastBar()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    -- The idle state hides the spark unconditionally; a live cast brings it
    -- back if the user wants one. The icon is owned by the per-cast code,
    -- which knows whether the spell actually has one.
    if castBarFrame._spark then
        castBarFrame._spark:SetShown(cb.showSpark and true or false)
    end
    ns.ApplyCastBgAnchor()
    castBarFrame:Show()
    EllesmereUI.SetElementVisibility(castBarFrame, true)
end

-- Spell name plus its rank subtext ("Name (Rank 2)") when Show Spell Rank is on.
-- Spell ranks exist only on WoW Forever (retail's subtext is "Racial" and the
-- like), so the option and this read are Forever-only.
function ns.CastDisplayName(cb, name, spellID)
    if cb.showSpellRank and spellID and EllesmereUI.IS_FOREVER then
        local rank = C_Spell.GetSpellSubtext(spellID)
        if rank and rank ~= "" then return name .. " (" .. rank .. ")" end
    end
    return name
end

OnCastStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled or ns._erbCastPadHidden then return end

    local name, _, _, startTimeMS, endTimeMS, _, _, notInterruptible, spellID, barID = UnitCastingInfo("player")
    if not name then return end

    castBarFrame._casting = true
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = barID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._spellID = spellID
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    castBarFrame._nameText:SetText(ns.CastDisplayName(cb, name, spellID))
    ns.ERB_SetBlizzCastFill("cast")
    if not ns.ApplyCastTimer("cast") then
        local castDur = endTimeMS - startTimeMS
        local initProgress = (castDur > 0) and ((GetTime() - startTimeMS / 1000) / (castDur / 1000)) or 0
        castBarFrame._bar:SetValue(min(max(initProgress, 0), 1))
    end

    -- Hide empower pips
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0
    HideChannelTicks()

    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    ShowLatencyOverlay("cast")

    ns.ActivateCastBar()
end

OnChannelStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled or ns._erbCastPadHidden then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, _, _, channelCastID = UnitChannelInfo("player")
    if not name then
        -- UnitChannelInfo can be empty on rapid channel restarts (e.g. SCK spam).
        -- Single retry on the next frame; if still nil the channel was cancelled.
        if not castBarFrame._channelRetry then
            castBarFrame._channelRetry = true
            C_Timer.After(0, function()
                castBarFrame._channelRetry = nil
                OnChannelStart()
            end)
        end
        return
    end

    castBarFrame._casting = false
    castBarFrame._channeling = true
    castBarFrame._empowering = false
    castBarFrame._castID = channelCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._spellID = spellID
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    castBarFrame._nameText:SetText(ns.CastDisplayName(cb, name, spellID))
    ns.ERB_SetBlizzCastFill("channel")
    if not ns.ApplyCastTimer("channel") then
        local chanDur = endTimeMS - startTimeMS
        local initProgress = (chanDur > 0) and ((endTimeMS / 1000 - GetTime()) / (chanDur / 1000)) or 1
        castBarFrame._bar:SetValue(min(max(initProgress, 0), 1))
    end

    -- Hide empower pips
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0

    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Channel tick marks
    ShowChannelTicks(spellID)

    ShowLatencyOverlay("channel")

    ns.ActivateCastBar()
end

OnChannelUpdate = function()
    if not castBarFrame then return end
    if not castBarFrame._channeling then return end

    local name, _, _, startTimeMS, endTimeMS, _, _, spellID = UnitChannelInfo("player")
    if not name then return end

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    ns.ApplyCastTimer("channel")

    -- Recompute tick mark and GCD boundary positions for new duration
    if spellID then ShowChannelTicks(spellID) end
end

-- Called for UNIT_SPELLCAST_STOP only (normal cast completion).
-- Ignores the event if the castID doesn't match the active cast -- this
-- prevents hiding the bar when a new cast has already started.
local function OnCastComplete(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._casting then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    ns.ShowIdleCastBar()
end

-- Called for UNIT_SPELLCAST_FAILED / INTERRUPTED. These fire for the spell that FAILED,
-- which may be a completely different spell than the one currently being cast (e.g.
-- pressing an instant while casting). Only hide if the castID matches our active cast.
local function OnCastFailed(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._casting then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    ns.ShowIdleCastBar()
end

-- Called for UNIT_SPELLCAST_CHANNEL_STOP. Deliberately matches no ID: castBarID
-- is documented Nilable on BOTH UnitChannelInfo and this event's payload, so an
-- equality test rejects real stops. Blizzard's own CastingBarFrame matches a
-- castID for plain casts only and accepts any channel/empower stop, which is
-- what OnEmpowerStop below already does. Instead the live channel is re-queried:
-- an instantly restarted channel (Clearcasting Arcane Missiles) can deliver the
-- OLD channel's STOP after the NEW channel's START, and that late stop must not
-- tear down the bar that is still channeling. The opposite order happens too:
-- a channel re-issued mid-flight (Hover cast during Disintegrate) can deliver
-- its STOP in a frame where UnitChannelInfo is already empty and the re-issuing
-- START has not landed, so going idle here blanks the bar for that frame and
-- the retry in OnChannelStart rebuilds it from scratch. Re-check next frame;
-- a real channel end reads empty both times.
local function OnChannelStop()
    if not castBarFrame then return end
    if not castBarFrame._channeling then return end
    if UnitChannelInfo("player") then return end
    if castBarFrame._channelStopPending then return end
    castBarFrame._channelStopPending = true
    C_Timer.After(0, function()
        castBarFrame._channelStopPending = nil
        if not castBarFrame._channeling then return end
        local name, _, _, _, _, _, _, _, empowering = UnitChannelInfo("player")
        if name then
            -- An empower dispatched in the emptied frame was declined by
            -- OnEmpowerStart, which has no retry; pick it up here.
            if empowering then OnEmpowerStart() end
            return
        end
        castBarFrame._channeling = false
        castBarFrame._castID = nil
        ns.ShowIdleCastBar()
    end)
end

-- Put the configured fill back after a tint (empower stages, Out of Range
-- Gray): Blizzard Style white, the gradient re-issued, or the solid colour.
-- On ns.
ns.ERB_RestoreCastFill = function()
    local cb = ERB.db.profile.castBar
    -- Blizzard Style (build stamp): the fill atlas is its own colour; restore plain white.
    if castBarFrame._blizzFill then
        castBarFrame._bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, (cb.fillOpacity or 100) / 100)
        return
    end
    local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, 1
    if cb.classColored then
        local cc = CLASS_COLORS[cachedClass]
        if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
    end
    if castBarFrame._gradientFullBar and castBarFrame._gradTex then
        empowerColorA:SetRGBA(fR, fG, fB, fA)
        empowerColorB:SetRGBA(cb.gradientR or fR, cb.gradientG or fG, cb.gradientB or fB, cb.gradientA or fA)
        castBarFrame._gradTex:SetGradient(cb.gradientDir or "HORIZONTAL", empowerColorA, empowerColorB)
    elseif cb.gradientEnabled then
        -- Re-ISSUE the gradient, do not just neutralise the vertex color.
        -- SetVertexColor REPLACES a texture's gradient rather than
        -- multiplying it, so the per-stage empower tint (which paints this
        -- exact texture with SetVertexColor) already destroyed the configured
        -- gradient. Whitening the vertex color therefore left a plain WHITE
        -- fill, and nothing restored it: the gradient is issued only where the
        -- bar is built, so every later cast in the session stayed white until a
        -- config edit or reload rebuilt the bar. The full-bar branch above
        -- already re-issues for the same reason. Fill Opacity is baked into
        -- both endpoint alphas, matching the build path.
        local fillTex = castBarFrame._bar:GetStatusBarTexture()
        local fillOp = (cb.fillOpacity or 100) / 100
        fillTex:SetVertexColor(1, 1, 1, 1)
        empowerColorA:SetRGBA(fR, fG, fB, fA * fillOp)
        empowerColorB:SetRGBA(cb.gradientR or fR, cb.gradientG or fG,
            cb.gradientB or fB, (cb.gradientA or fA) * fillOp)
        fillTex:SetGradient(cb.gradientDir or "HORIZONTAL",
            empowerColorA, empowerColorB)
    else
        local fillTex = castBarFrame._bar:GetStatusBarTexture()
        fillTex:SetVertexColor(fR, fG, fB, fA * ((cb.fillOpacity or 100) / 100))
    end
end

-- Undo the per-stage empower tint. Shared by OnEmpowerStop and OnCastStop: the
-- 1s-overrun safety path routes a missed EMPOWER_STOP through OnCastStop, which
-- clears _empowering, and OnEmpowerStop then early-returns on that very flag --
-- so without this call there the stage tint stayed painted for the rest of the
-- session, the same stuck-fill symptom by a second route.
ns.ResetEmpowerFillColor = function()
    if not (castBarFrame and castBarFrame._empowerColorApplied) then return end
    castBarFrame._empowerColorApplied = false
    ns.ERB_RestoreCastFill()
end

-- Out of Range Gray (castBar.outOfRangeGray): the fill turns gray while the
-- target is out of the cast's range and takes its configured paint back when it
-- returns or the cast ends. Writes only on a flip.
ns.ERB_CastRangeTint = function(out)
    if (castBarFrame._rangeOut or false) == out then return end
    castBarFrame._rangeOut = out or nil
    if out then
        castBarFrame._bar:GetStatusBarTexture():SetVertexColor(0.4, 0.4, 0.4, castBarFrame._cstFillAlpha or 1)
    else
        ns.ERB_RestoreCastFill()
    end
end

-- Called for UNIT_SPELLCAST_EMPOWER_STOP.
local function OnEmpowerStop(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._empowering then return end
    -- Accept any empower stop while we're empowering. Strict castID
    -- matching can reject valid stops due to event desync under load.
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end
    castBarFrame._numStages = 0

    -- Reset empower stage coloring if it was applied
    ns.ResetEmpowerFillColor()

    SetStageThresholds(nil)

    ns.ShowIdleCastBar()
end

OnCastStop = function()
    if not castBarFrame then return end
    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    -- The overrun safety path forces a stop here on a missed EMPOWER_STOP, and
    -- clearing _empowering above is exactly what makes OnEmpowerStop early-return
    -- later, so this is the only chance to undo the stage tint.
    ns.ResetEmpowerFillColor()
    -- Pip textures, channel ticks and the latency overlay are all cleared by
    -- the idle pass below.
    ns.ShowIdleCastBar()
end

-- Blizzard's player cast bar is ours to hide while our cast bar is on, except
-- while ours stands down for the controller under WoW Forever's Gamepad
-- interface style: from build 70425 that style draws the cast on Blizzard's
-- player bar itself.
function ns.RB_SyncBlizzCastSuppress()
    local cb = ERB.db and ERB.db.profile and ERB.db.profile.castBar
    local on = cb and cb.enabled and not (ns._erbCastPadHidden and EllesmereUI.PadGamepadUI())
    EllesmereUI.SetPlayerCastBarSuppressed("ResourceBars", on and true or false)
end

-- Hide While Using Gamepad (Global Settings > Gamepad): Blizzard's gamepad UI
-- draws its own player cast bar, so this one stands down while a controller is
-- connected. A runtime flag (ns._erbCastPadHidden) gates the cast starts and
-- the idle pass the way `enabled` does; the saved `enabled` is never written,
-- Blizzard's bar stays suppressed (handed back under WoW Forever's Gamepad
-- interface style, ns.RB_SyncBlizzCastSuppress) and the frame keeps its
-- layout. The pad edges are watched only while the option and the bar are
-- both on. padOn is the watcher's verdict; ApplyAll and the options page pass
-- nothing and it is read live. On ns.
function ns.RB_ApplyGamepadCastbar(padOn)
    local cb = ERB.db and ERB.db.profile and ERB.db.profile.castBar
    local want = (cb and cb.enabled and cb.gamepadHide == true) and true or false
    if want ~= (ns._erbCastPadWatched == true) then
        ns._erbCastPadWatched = want
        if want then
            EllesmereUI.WatchPad("ERB_CastBar", ns.RB_ApplyGamepadCastbar)
        else
            EllesmereUI.UnwatchPad("ERB_CastBar")
        end
    end
    local hide = false
    if want then
        if padOn == nil then padOn = EllesmereUI.PadConnected() end
        hide = padOn and true or false
    end
    if hide == (ns._erbCastPadHidden == true) then return end
    ns._erbCastPadHidden = hide
    ns.RB_SyncBlizzCastSuppress()
    if not castBarFrame then return end
    if hide then
        -- Drop the live cast: the idle pass hides the bar and the cast tick
        -- stops itself on its next loop.
        OnCastStop()
        return
    end
    -- Back on, mid-cast included: re-derive the live cast (the starts refuse
    -- a disabled bar), else settle into the idle state.
    if UnitCastingInfo("player") then
        OnCastStart()
    else
        local name, _, _, _, _, _, _, _, empowering = UnitChannelInfo("player")
        if name then
            if empowering then OnEmpowerStart() else OnChannelStart() end
        end
    end
    if castBarFrame._casting or castBarFrame._channeling or castBarFrame._empowering then
        ns.StartCastTick()
    else
        ns.ShowIdleCastBar()
    end
end


OnEmpowerStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled or ns._erbCastPadHidden then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, empowering, _, empowerCastID = UnitChannelInfo("player")
    if not name or not empowering then return end

    -- Add hold-at-max time to the end
    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = true
    castBarFrame._castID = empowerCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._spellID = spellID
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    HideLatencyOverlay()
    castBarFrame._nameText:SetText(ns.CastDisplayName(cb, name, spellID))
    ns.ERB_SetBlizzCastFill("cast")
    if not ns.ApplyCastTimer("empower") then
        local empDur = endTimeMS - startTimeMS
        local empProgress = (empDur > 0) and ((GetTime() - startTimeMS / 1000) / (empDur / 1000)) or 0
        castBarFrame._bar:SetValue(min(max(empProgress, 0), 1))
    end
    HideChannelTicks()

    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Stage pips (hash marks) -- pixel-perfect positioning
    local stages = UnitEmpoweredStagePercentages("player")
    -- Cache cumulative thresholds for per-frame stage color lookup
    if stages then
        SetStageThresholds({})
        local cum = 0
        for i = 1, #stages do
            cum = cum + stages[i]
            cachedStageThresholds[i] = cum
        end
    else
        SetStageThresholds(nil)
    end
    if stages then
        -- Stashed so a mid-empower bar rebuild can re-lay this cast's stage
        -- pips (see the BuildCastBar tail; the channel ticks' stash twin).
        -- Stale values are inert: the re-lay gates on _empowering, and every
        -- empower start restores the stash.
        castBarFrame._empStages = stages
        ns.ERB_LayoutEmpowerPips(stages)
    end

    ns.ActivateCastBar()
end

-- Stage pip layout for an empowered cast, shared by OnEmpowerStart and the
-- BuildCastBar tail (a mid-empower rebuild must re-lay the marks against
-- the rebuilt bar, exactly like the channel-tick re-show -- without it the
-- build reset's pip wipe sticks for the rest of that cast; field: Evokers
-- randomly losing all stage ticks for one cast). On ns.
function ns.ERB_LayoutEmpowerPips(stages)
    if not (castBarFrame and stages) then return end
    local bar = castBarFrame._bar
    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    local numStages = #stages
    castBarFrame._numStages = numStages

    -- Physical-pixel sizing: PP.perfect / effectiveScale = one PHYSICAL
    -- pixel in the bar's local units, so the pip is exactly 2 physical
    -- pixels wide at every UI scale (the old effectiveScale rounding
    -- treated 2 as UI units and drifted between 1 and 3 physical pixels).
    local effectiveScale = bar:GetEffectiveScale()
    local PPc = EllesmereUI and EllesmereUI.PP
    local onePx = ((PPc and PPc.perfect) or 1) / effectiveScale
    local pipWidth = 2 * onePx
    local snappedHeight = (PPc and PPc.SnapForES)
        and PPc.SnapForES(barHeight, effectiveScale) or barHeight

    -- Position a pip at each stage boundary (skip the last -- it's the bar end)
    local lastOffset = 0
    for i = 1, numStages - 1 do
        local pip = castBarFrame._pips[i]
        if not pip then
            pip = bar:CreateTexture(nil, "OVERLAY", nil, 2)
            pip:SetColorTexture(1, 1, 1, 0.85)
            if pip.SetSnapToPixelGrid then
                pip:SetSnapToPixelGrid(false)
                pip:SetTexelSnappingBias(0)
            end
            castBarFrame._pips[i] = pip
        end
        local rawOffset = lastOffset + (barWidth * stages[i])
        lastOffset = rawOffset
        -- Width-aware center snap: both pip edges land on the physical
        -- grid (a centered even-width mark on a grid point is exact).
        local snappedOffset = (PPc and PPc.SnapCenterForDim)
            and PPc.SnapCenterForDim(rawOffset, pipWidth, effectiveScale)
            or (floor(rawOffset * effectiveScale + 0.5) / effectiveScale)
        pip:SetSize(pipWidth, snappedHeight)
        pip:ClearAllPoints()
        pip:SetPoint("CENTER", bar, "LEFT", snappedOffset, 0)
        pip:Show()
    end

    -- Hide any extra pips from a previous cast with more stages
    for i = numStages, #castBarFrame._pips do
        castBarFrame._pips[i]:Hide()
    end
end

OnEmpowerUpdate = function()
    if not castBarFrame then return end
    if not castBarFrame._empowering then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, empowering = UnitChannelInfo("player")
    if not name or not empowering then return end

    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    ns.ApplyCastTimer("empower")
end

I.BuildCastBar, I.OnCastComplete, I.OnCastFailed = BuildCastBar, OnCastComplete, OnCastFailed
I.OnCastStart, I.OnChannelStart, I.OnChannelStop = OnCastStart, OnChannelStart, OnChannelStop
I.OnChannelUpdate, I.OnEmpowerStart = OnChannelUpdate, OnEmpowerStart
I.OnEmpowerStop, I.OnEmpowerUpdate = OnEmpowerStop, OnEmpowerUpdate
I.broken = false
