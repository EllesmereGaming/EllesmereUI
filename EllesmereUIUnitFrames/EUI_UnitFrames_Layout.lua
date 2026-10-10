if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Layout.lua
--
--  Mini frame donor and boss getters, text slot widths, the bottom text bar,
--  frame position, bar clip, border layout, frame dimensions and the health
--  bar, published through I for the files that load after this one. Reads
--  earlier files through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local GetSettingsForUnit, UnitToSettingsKey, unitSettingsKey = I.GetSettingsForUnit, I.UnitToSettingsKey, I.unitSettingsKey
local SetFSFont, ApplyDarkTheme, SpecHasClassPower = I.SetFSFont, I.ApplyDarkTheme, I.SpecHasClassPower
local ApplyHealthBarTexture, ApplyHealthBarAlpha = I.ApplyHealthBarTexture, I.ApplyHealthBarAlpha
local ApplyClassIconTexture, ResolveRestrictedClassColor = I.ApplyClassIconTexture, I.ResolveRestrictedClassColor
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Donor settings table for a mini frame, the source of its inherited border,
-- bar texture and hover highlight: the main frame its Copy Look From picks
-- (lookSource "target" / "focus" / "player"), else Automatic (focus > target >
-- player; boss frames always). A frame that is disabled, or that Visibility
-- keeps off screen entirely, is not a donor (a pick of one falls back to
-- Automatic) -- before Visibility and enabledFrames were split, "never"
-- cleared that flag and fell out here for free.
function ns.GetMiniDonorSettings(unitKey)
    local p = db.profile
    local ef = p.enabledFrames
    local own = unitKey and p[unitKey]
    local pick = own and own.lookSource
    if pick == "player" then return p.player end
    if pick == "target" or pick == "focus" then
        local s = p[pick]
        if ef[pick] ~= false and s and ns.VisEffective(s) ~= "never" then return s end
    end
    local focus = p.focus
    if ef.focus ~= false and focus and ns.VisEffective(focus) ~= "never" then return focus end
    local target = p.target
    if ef.target ~= false and target and ns.VisEffective(target) ~= "never" then return target end
    return p.player
end
local GetMiniDonorSettings = ns.GetMiniDonorSettings

-- The settings whose border keys paint the boss frames' unified border (and
-- its normal colour between hover / target recolours): the boss table's own
-- once its Border Style leaves "Inherit (Main Frames)" (borderCustom), else the
-- mini frame donor's. Boss1-5 share the one boss table.
function ns.UF_BossBorderSettings()
    local s = db.profile.boss
    if s and s.borderCustom == true then return s end
    return GetMiniDonorSettings()
end

function ns.UF_BossAuraBorderAboveEffects(s)
    return s.auraBorderAboveEffects == true and not ns.UF_Blizz()
        and not s.auraBorderBehind and not s.auraBorderBehindUnitFrame
        and (s.auraBorderSize or 1) > 0
        and s.auraBorderTexture ~= nil and s.auraBorderTexture ~= "solid" and s.auraBorderTexture ~= ""
end

-- Boss "Simple Debuff Display" mode: "none"|"left"|"right". Tolerates legacy booleans
-- (true/nil="left", false="none") so existing/imported profiles read correctly with no
-- migration pass. "left"/"right" both force the frame-height-matched single column;
-- only the side differs.
function ns.GetBossSimpleDebuffMode(s)
    local v = s and s.simpleDebuffs
    if v == "none" or v == "left" or v == "right" then return v end
    if v == false then return "none" end
    return "left"  -- nil or legacy true
end

-- Boss Simple Debuff Display X/Y offsets: dedicated simpleDebuffOffsetX/Y if set, else
-- the regular debuff offsets, so existing offsets carry over as simple-mode defaults
-- (zero-migration view; import-safe). Once the cog is edited, dedicated keys take over.
function ns.GetBossSimpleDebuffOffset(s)
    if not s then return 0, 0 end
    local x = s.simpleDebuffOffsetX
    if x == nil then x = s.debuffOffsetX or 0 end
    local y = s.simpleDebuffOffsetY
    if y == nil then y = s.debuffOffsetY or 0 end
    return x, y
end

-- Boss "Simple Buff Display" mode: "none"|"left"|"right". Defaults OFF
-- (nil/false/unknown -> "none"); a stray boolean true reads as "left" (symmetry with the debuff resolver).
function ns.GetBossSimpleBuffMode(s)
    local v = s and s.simpleBuffs
    if v == "none" or v == "left" or v == "right" then return v end
    if v == true then return "left" end
    return "none"
end

-- Boss Simple Buff Display X/Y offsets. Mirrors ns.GetBossSimpleDebuffOffset
-- (simpleBuffOffsetX/Y if set, else regular buff offsets; zero-migration, import-safe).
function ns.GetBossSimpleBuffOffset(s)
    if not s then return 0, 0 end
    local x = s.simpleBuffOffsetX
    if x == nil then x = s.buffOffsetX or 0 end
    local y = s.simpleBuffOffsetY
    if y == nil then y = s.buffOffsetY or 0 end
    return x, y
end

-- Boss aura icon spacing, in PHYSICAL pixels. Simple modes use dedicated keys
-- (simpleBuffSpacing/simpleDebuffSpacing); regular auras use buffSpacing/debuffSpacing.
-- No legacy equivalent, so every variant defaults to 1 independently. Callers convert
-- to coordinate space with PP.FromPixels for physical-pixel-perfect gaps at any scale.
-- (0 and negatives are truthy in Lua, so `or 1` only fills nil.)
function ns.GetBossBuffSpacing(s, simpleOn)
    if simpleOn then return (s and s.simpleBuffSpacing) or 1 end
    return (s and s.buffSpacing) or 1
end
function ns.GetBossDebuffSpacing(s, simpleOn)
    if simpleOn then return (s and s.simpleDebuffSpacing) or 1 end
    return (s and s.debuffSpacing) or 1
end

-- Per-slot Width % of the slot's computed clamp width (100 = normal truncation,
-- above 100 grants extra room). Applied by the position code to the slot
-- FontString's width box.
local function SlotWidthMul(settings, prefix)
    return (settings[prefix .. "WidthPct"] or 100) / 100
end

-- Build the per-slot "Name > Target" indicator tag. The separator is hex-encoded
-- per byte so any user-typed character (commas, parens, multibyte symbols)
-- survives the tag brackets; color rides as "class" or rrggbb hex (default white).
-- (The old content-key -> tag-string mapping lived here; text zones now
-- resolve through ns.ContentToZone and the engine text painter.)

-- Estimated pixel width per text content type, for name truncation. Flat
-- assumptions matching the nameplate system.
local UF_TEXT_PADDING = 10
local ufTextWidths = {
    both        = 75,  -- "132 K | 86%"
    bothdash    = 75,  -- "132 K - 86%"
    perhpnum    = 75,  -- "86% | 132 K"
    perhpnumdash = 75, -- "86% - 132 K"
    curhpshort  = 38,  -- "132 K"
    curmaxhp    = 75,  -- "132 K / 150 K"
    curmaxpp    = 75,  -- "132 K / 150 K"
    perhp       = 38,  -- "86%"
    perhpnosign = 30,  -- "86"
    perpp       = 38,  -- "86%"
    curpp       = 38,  -- "132"
    curhp_curpp = 75,  -- "132 K | 132"
    perhp_perpp = 75,  -- "86% | 86%"
    absorb      = 38,  -- "12.3 K"
    level       = 24,  -- "80" / "??"
}
local function EstimateUFTextWidth(content)
    return (ufTextWidths[content] or 0) + UF_TEXT_PADDING
end

-- Apply class color to a FontString based on the unit.
local function ApplyClassColor(fs, unit, useClassColor, customR, customG, customB)
    if not fs then return end
    if useClassColor and unit then
        -- Class color for players (and AI party members), reaction color for NPCs,
        -- matching the health bar and the custom Enemy Colors override. Shared
        -- with the eui-tgtname tag via ns.ResolveUnitNameColor.
        local r, g, b = ns.ResolveUnitNameColor(unit)
        if r then fs:SetTextColor(r, g, b); return end
        -- ResolveUnitNameColor returns nil for a SECRET class token (identity-restricted
        -- units: focus-target, ToT) since it can't be used as a table key; the
        -- [eui-tgtcol] hex-escape tag it also feeds recovers a secret hex on its own
        -- and passes it through SetFormattedText. SetTextColor accepts secrets
        -- directly, so recover the real color here the same way the health bar does:
        -- the user's custom color when the unit matches a group member, else Blizzard's.
        if UnitIsPlayer(unit) or (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
            local _, class = UnitClass(unit)
            if issecretvalue(class) then
                local ok, sr, sg, sb = ResolveRestrictedClassColor(unit, class)
                if ok then fs:SetTextColor(sr, sg, sb); return end
            end
        end
    end
    fs:SetTextColor(customR or 1, customG or 1, customB or 1)
end

-- Recolours every text slot on a frame from its settings: the four text
-- positions, then the bottom text bar with its power colour re-applied last so
-- power-coloured slots win (class -> power, same order as ApplyBTBTextPositions).
-- Shared by the target/focus-changed updater and the text painter's UNIT_FACTION
-- branch (the painter only renders strings; colour lives here). `s` optional:
-- resolved strictly from the unit token, so an unmapped token recolours nothing.
-- On ns for the 200-locals cap.
function ns.UF_RecolorTexts(frame, unit, s)
    if not frame or not unit then return end
    if not s then
        local k = unitSettingsKey[unit]
        s = k and db.profile[k]
    end
    if not s then return end
    if frame.LeftText and s.leftTextClassColor ~= nil then
        ApplyClassColor(frame.LeftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
    end
    if frame.RightText and s.rightTextClassColor ~= nil then
        ApplyClassColor(frame.RightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
    end
    if frame.CenterText and s.centerTextClassColor ~= nil then
        ApplyClassColor(frame.CenterText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
    end
    if frame.ExtraText and s.extraTextClassColor ~= nil then
        ApplyClassColor(frame.ExtraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
    end
    local btb = frame._btb
    if btb then
        if btb.LeftText then ApplyClassColor(btb.LeftText, unit, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB) end
        if btb.RightText then ApplyClassColor(btb.RightText, unit, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB) end
        if btb.CenterText then ApplyClassColor(btb.CenterText, unit, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB) end
        if btb._applyBTBPowerColors then btb._applyBTBPowerColors(s) end
    end
end

-- Bottom text bar frame: below the health+power area, above the castbar.
local function CreateBottomTextBar(frame, unit, settings, anchorFrame, xOffset, overrideWidth)
    local btbH = settings.bottomTextBarHeight or 16
    local btbPos = settings.btbPosition or "bottom"
    local isDetached = (btbPos == "detached_top" or btbPos == "detached_bottom")
    local btbW = isDetached and (settings.btbWidth or 0) or 0
    local totalWidth = (btbW > 0 and isDetached) and btbW or (overrideWidth or settings.frameWidth)

    local btb = CreateFrame("Frame", nil, frame)
    PP.Size(btb, totalWidth, btbH)
    btb._isDetached = isDetached

    if btbPos == "top" then
        PP.Point(btb, "BOTTOMLEFT", frame.Health or anchorFrame, "TOPLEFT", xOffset or 0, 0)
    elseif btbPos == "detached_top" then
        btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
    elseif btbPos == "detached_bottom" then
        btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
    else -- "bottom"
        PP.Point(btb, "TOPLEFT", anchorFrame, "BOTTOMLEFT", xOffset or 0, 0)
    end

    local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
    local bga = settings.btbBgOpacity or 1.0
    local bg = btb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
    btb.bg = bg

    -- Text overlay, above the unified border at frame+10.
    local textOvr = CreateFrame("Frame", nil, btb)
    textOvr:SetAllPoints()
    textOvr:SetFrameLevel(frame:GetFrameLevel() + 15)

    local leftFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftFS, settings.btbLeftSize or 11)
    leftFS:SetWordWrap(false)
    leftFS:SetTextColor(1, 1, 1)
    btb.LeftText = leftFS

    local rightFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightFS, settings.btbRightSize or 11)
    rightFS:SetWordWrap(false)
    rightFS:SetTextColor(1, 1, 1)
    btb.RightText = rightFS

    local centerFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerFS, settings.btbCenterSize or 11)
    centerFS:SetWordWrap(false)
    centerFS:SetTextColor(1, 1, 1)
    btb.CenterText = centerFS

    btb._textOverlay = textOvr

    local function ApplyBTBTextTags(lc, rc, cc)
        ns.SetTextZone(frame, leftFS, lc, "btbLeft", settings)
        ns.SetTextZone(frame, rightFS, rc, "btbRight", settings)
        ns.SetTextZone(frame, centerFS, cc, "btbCenter", settings)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end

    -- Power-color override for power-content text. Mirrors the power bar text
    -- logic: the unit's own power type, white when the token cannot resolve.
    -- ApplyBTBPowerColors re-applies all three slots; it runs at layout time AND
    -- continuously from the power element's PostUpdateColor, so the color survives
    -- tag updates and power-type changes. The per-slot early-out (no power-color
    -- flag) keeps it ~free when unused.
    local function ApplyBTBPowerColor(fs, contentKey, usePowerColor)
        if not fs or not usePowerColor then return end
        if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curmaxpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
            -- Secret-safe per-unit power color: player resolves via the clean
            -- string token; non-player units recover it from the clean integer
            -- power type instead of falling back to white.
            local r, g, b = EllesmereUI.ResolveUnitPowerColor(unit)
            if r then fs:SetTextColor(r, g, b)
            else fs:SetTextColor(1, 1, 1) end
        end
    end
    local function ApplyBTBPowerColors(s)
        ApplyBTBPowerColor(leftFS, s.btbLeftContent or "none", s.btbLeftPowerColor)
        ApplyBTBPowerColor(rightFS, s.btbRightContent or "none", s.btbRightPowerColor)
        ApplyBTBPowerColor(centerFS, s.btbCenterContent or "none", s.btbCenterPowerColor)
    end

    local function ApplyBTBTextPositions(s)
        local lc = s.btbLeftContent or "none"
        local rc = s.btbRightContent or "none"
        local cc = s.btbCenterContent or "none"
        local lsz = s.btbLeftSize or 11
        local rsz = s.btbRightSize or 11
        local csz = s.btbCenterSize or 11

        SetFSFont(leftFS, lsz)
        leftFS:ClearAllPoints()
        if lc ~= "none" then
            leftFS:SetJustifyH("LEFT")
            PP.Point(leftFS, "LEFT", textOvr, "LEFT", 5 + (s.btbLeftX or 0), s.btbLeftY or 0)
            PP.Width(leftFS, totalWidth * 0.9 * SlotWidthMul(s, "btbLeft"))
            leftFS:Show()
        else leftFS:Hide() end

        SetFSFont(rightFS, rsz)
        rightFS:ClearAllPoints()
        if rc ~= "none" then
            rightFS:SetJustifyH("RIGHT")
            PP.Point(rightFS, "RIGHT", textOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
            PP.Width(rightFS, totalWidth * 0.9 * SlotWidthMul(s, "btbRight"))
            rightFS:Show()
        else rightFS:Hide() end

        SetFSFont(centerFS, csz)
        centerFS:ClearAllPoints()
        if cc ~= "none" then
            centerFS:SetJustifyH("CENTER")
            PP.Point(centerFS, "CENTER", textOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
            PP.Width(centerFS, totalWidth * 0.9 * SlotWidthMul(s, "btbCenter"))
            centerFS:Show()
        else centerFS:Hide() end

        ApplyClassColor(leftFS, unit, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB)
        ApplyClassColor(rightFS, unit, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB)
        ApplyClassColor(centerFS, unit, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB)
        -- Power color: after class color, and re-applied continuously from the
        -- power element's PostUpdateColor (btb._applyBTBPowerColors).
        ApplyBTBPowerColors(s)
    end

    ApplyBTBTextTags(
        settings.btbLeftContent or "none",
        settings.btbRightContent or "none",
        settings.btbCenterContent or "none"
    )
    ApplyBTBTextPositions(settings)

    btb._applyBTBTextTags = ApplyBTBTextTags
    btb._applyBTBTextPositions = ApplyBTBTextPositions
    btb._applyBTBPowerColors = ApplyBTBPowerColors

    -- Class icon overlay on a high-level frame so it renders above the border.
    local classIconHolder = CreateFrame("Frame", nil, frame)
    classIconHolder:SetAllPoints(textOvr)
    classIconHolder:SetFrameLevel(frame:GetFrameLevel() + 12)
    local classIconTex = classIconHolder:CreateTexture(nil, "ARTWORK")
    classIconTex:SetTexCoord(0, 1, 0, 1)
    classIconTex:Hide()
    btb.ClassIcon = classIconTex

    local function ApplyBTBClassIcon(s)
        local style = s.btbClassIcon or "none"
        if style == "none" then classIconTex:Hide(); return end
        local _, classToken = UnitClass(unit)
        if issecretvalue(classToken) or not classToken then classIconTex:Hide(); return end
        if not ApplyClassIconTexture(classIconTex, classToken, style) then classIconTex:Hide(); return end
        local sz = s.btbClassIconSize or 14
        PP.Size(classIconTex, sz, sz)
        classIconTex:ClearAllPoints()
        local loc = s.btbClassIconLocation or "left"
        local ox = s.btbClassIconX or 0
        local oy = s.btbClassIconY or 0
        if loc == "center" then
            PP.Point(classIconTex, "CENTER", textOvr, "CENTER", ox, oy)
        elseif loc == "right" then
            PP.Point(classIconTex, "RIGHT", textOvr, "RIGHT", -3 + ox, oy)
        else
            PP.Point(classIconTex, "LEFT", textOvr, "LEFT", 3 + ox, oy)
        end
        classIconTex:Show()
    end

    ApplyBTBClassIcon(settings)
    btb._applyBTBClassIcon = ApplyBTBClassIcon

    return btb
end

-- Positioning is handled by Unlock Mode.

local function ApplyFramePosition(frame, unit)
    if not frame or not db.profile.positions[unit] then return end
    local pos = db.profile.positions[unit]
    -- UIParent offsets read in the frame's own scale (identity outside Frame Scale).
    local x, y = ns.UF_ScaledOffsets(frame, pos.x, pos.y)
    -- Snap to the physical pixel grid for deterministic positions across reloads.
    -- CENTER-anchored frames use SnapCenterForDim with actual width/height (preserves
    -- the +0.5 center offset odd-pixel-dimension frames need for whole-pixel edges);
    -- plain SnapForES rounds the center to whole pixels, forcing edges to half pixels
    -- and causing 1px drift on save/exit, spec swap, or profile change.
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and x and y then
        local es = frame:GetEffectiveScale()
        local isCenterAnchor = (pos.point == "CENTER" or pos.point == nil)
            and (pos.relPoint == "CENTER" or pos.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            local fw = frame:GetWidth() or 0
            local fh = frame:GetHeight() or 0
            x = PPa.SnapCenterForDim(x, fw, es)
            y = PPa.SnapCenterForDim(y, fh, es)
        elseif PPa.SnapForES then
            x = PPa.SnapForES(x, es)
            y = PPa.SnapForES(y, es)
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
end

-- Clip container for health + power bars: prevents sub-pixel overflow at UI scales
-- where independent pixel-snapping pushes edges 1px out. Inset by the border
-- thickness so the GPU cannot render bar pixels outside the border.
local function EnsureBarClip(frame)
    if frame._barClip then return frame._barClip end
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetAllPoints(frame)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(frame:GetFrameLevel())
    clip:EnableMouse(false)
    frame._barClip = clip
    return clip
end

local function ReparentBarsToClip(frame, powerPosition, settings)
    local clip = EnsureBarClip(frame)
    if frame.Health and frame.Health:GetParent() ~= clip then
        frame.Health:SetParent(clip)
    end
    if frame.Power then
        local detached = (powerPosition == "detached_top" or powerPosition == "detached_bottom")
        if detached then
            if frame.Power:GetParent() == clip then
                frame.Power:SetParent(frame)
            end
        else
            if frame.Power:GetParent() ~= clip then
                frame.Power:SetParent(clip)
            end
        end
        -- SetParent resets frame level, so re-assert after every reparent.
        if detached then
            -- Detached bars reparent onto `frame` itself (not the bar clip), which also
            -- holds the border at frame:GetFrameLevel()+10 (CreateUnifiedBorder/
            -- UpdatePowerBorder). hpLevel+2 would sit under that and let the border
            -- render over a detached power bar dragged onto its edge, so match
            -- CreatePowerBar's detached offset instead.
            frame.Power:SetFrameLevel(frame:GetFrameLevel() + 12)
        else
            -- Power bar must render above the absorb overlay (health level + 1).
            local hpLevel = frame.Health and frame.Health:GetFrameLevel() or clip:GetFrameLevel()
            frame.Power:SetFrameLevel(hpLevel + 2)
        end
        -- Reparent/SetFrameLevel leave the border and text overlay at stale
        -- absolute levels; re-apply after the final level is set.
        if settings then
            ns.UpdatePowerBorder(frame.Power, settings)
        end
    end
end


-- Recalculate every element size after a frame scale change so the stack stays
-- pixel-perfect inside the border. PixelUtil rounds each element independently, so
-- their sum can exceed the frame's snapped total by 1px at some scales; overflow is
-- trimmed off the last element after re-snapping.
local function UpdateBordersForScale(frame, unit)
    if not frame then return end
    local settings = GetSettingsForUnit(unit)
    if not settings then return end
    local borderSize = settings.borderSize or 1

    -- 1) Main frame border textures.
    if frame.unifiedBorder then
        local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
        local textureKey = settings.borderTexture or "solid"
        EllesmereUI.ApplyBorderStyle(frame.unifiedBorder, borderSize, bc.r, bc.g, bc.b, settings.borderAlpha or 1, textureKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", borderSize, nil,
            EllesmereUI.BorderPx(settings.borderSizePx, borderSize, textureKey))
    end

    -- 2) Gather layout info.
    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local ppIsDet = (ppPos == "detached_top" or ppPos == "detached_bottom")
    local ph = settings.powerHeight or 6
    -- Mini frames (pet/tot/focustarget) have no power bar: no power height.
    -- The exception is a WoW Forever pet off Blizzard Style, which has its own.
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local miniNoPower = isMini and not (unit == "pet" and ns.UF_PetHasPower and not ns.UF_Blizz())
    local powerH = (ppIsAtt and not miniNoPower) and ph or 0

    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbH = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0

    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if isMini and pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    -- Use the side the frame was actually built with, so frames like the pet that
    -- hard-code "left" are not treated as "right".
    local pSide = EllesmereUI._ufPortraitSide[frame] or settings.portraitSide or "right"
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end

    -- Class power above adds height (player only, only if the spec has a resource).
    local cpAboveH = 0
    if unit == "player" and SpecHasClassPower() then
        local cpSt = settings.classPowerStyle or "none"
        if ns.UF_ForeverCPStyle then cpSt = ns.UF_ForeverCPStyle(cpSt) end
        local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
        if cpSt == "modern" and cpPo == "above" then
            local cpSizeAdj = settings.classPowerSize or 8
            cpAboveH = math.max(3, math.floor(cpSizeAdj * 0.375))
        end
    end

    local barHeight = settings.healthHeight + powerH + cpAboveH
    local expectedFrameH = barHeight + btbH
    local pSideSnap = settings.portraitSide or "left"
    local isInsideSnap = pSideSnap == "insideleft" or pSideSnap == "insideright" or pSideSnap == "insidecenter"
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached and not isInsideSnap then pSizeAdj = pSizeAdj + 10 end
    local adjPortraitH = barHeight + pSizeAdj
    if adjPortraitH < 8 then adjPortraitH = 8 end

    local expectedFrameW
    if not showPortrait or not isAttached then
        expectedFrameW = settings.frameWidth
    else
        expectedFrameW = adjPortraitH + settings.frameWidth
    end

    -- 3) Re-snap the frame itself.
    PP.Size(frame, expectedFrameW, expectedFrameH)
    local snappedFrameW = frame:GetWidth()
    local snappedFrameH = frame:GetHeight()

    -- 4) Re-snap portrait and health bar (width axis).
    local healthTargetW = settings.frameWidth
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and not isInsideSnap then
        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local snappedPortH = frame.Portrait.backdrop:GetHeight()
        -- Trim portrait width if it + health would exceed the frame.
        if snappedPortW + healthTargetW > snappedFrameW + 0.01 then
            PP.Width(frame.Portrait.backdrop, snappedFrameW - healthTargetW)
            snappedPortW = frame.Portrait.backdrop:GetWidth()
        end
        -- Trim portrait height to frame height on overflow.
        if snappedPortH > snappedFrameH + 0.01 then
            PP.Height(frame.Portrait.backdrop, snappedFrameH)
        end
    end

    -- 5) Re-snap health bar height and re-anchor to the snapped portrait width.
    if frame.Health then
        PP.Height(frame.Health, settings.healthHeight)
        -- Keep the health bar flush against the snapped portrait edge.
        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRightInset = (effectiveSide == "right") and snappedPortW or 0
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRightInset
        end
    end

    -- 6) Re-snap power bar.
    if frame.Power and ppPos ~= "none" then
        local pw = settings.frameWidth
        if ppIsDet and (settings.powerWidth or 0) > 0 then
            pw = settings.powerWidth
        end
        PP.Size(frame.Power, pw, ph)
        if ppIsAtt and frame.Health then
            -- Height: health + power must not exceed the bar area.
            local snappedHealthH = frame.Health:GetHeight()
            local snappedPowerH = frame.Power:GetHeight()
            local expectedBarH = settings.healthHeight + ph
            if snappedHealthH + snappedPowerH > expectedBarH + 0.01 then
                PP.Height(frame.Power, snappedPowerH - (snappedHealthH + snappedPowerH - expectedBarH))
            end
            -- Width: match the health bar exactly.
            local snappedHealthW = frame.Health:GetWidth()
            local snappedPowerW = frame.Power:GetWidth()
            if math.abs(snappedPowerW - snappedHealthW) > 0.01 then
                PP.Width(frame.Power, snappedHealthW)
            end
        elseif not ppIsDet then
            -- Non-attached non-detached should not happen; trim width to frame.
            local snappedPowerW = frame.Power:GetWidth()
            if snappedPowerW > snappedFrameW + 0.01 then
                PP.Width(frame.Power, snappedFrameW)
            end
        end
    end

    -- 7) Re-snap BTB.
    if frame.BottomTextBar and settings.bottomTextBar and btbIsAtt then
        PP.Size(frame.BottomTextBar, expectedFrameW, settings.bottomTextBarHeight or 16)
        local snappedBtbW = frame.BottomTextBar:GetWidth()
        local snappedBtbH = frame.BottomTextBar:GetHeight()
        -- Width: trim to frame width.
        if snappedBtbW > snappedFrameW + 0.01 then
            PP.Width(frame.BottomTextBar, snappedFrameW)
        end
        -- Height: the full stack must fit inside the frame height.
        local usedH = cpAboveH
        if frame.Health then usedH = usedH + frame.Health:GetHeight() end
        if frame.Power and ppIsAtt then usedH = usedH + frame.Power:GetHeight() end
        if usedH + snappedBtbH > snappedFrameH + 0.01 then
            PP.Height(frame.BottomTextBar, snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
        end
    end

    -- 8) Castbar: re-snap background width + border textures.
    if frame.Castbar then
        local castbarBg = frame.Castbar:GetParent()
        if castbarBg then
            -- Trim castbar bg width to the frame width, only when the user has no
            -- custom width (castbarWidth > 0 = custom). Use the settings resolved
            -- from this function's unit parameter, NOT frame._euiUnit: boss preview
            -- swaps frame._euiUnit to "player", which has no castbarWidth, and the
            -- trim would eat the boss castbar's custom width while previewing.
            local cbW = castbarBg:GetWidth()
            local hasCustomW = (settings.castbarWidth or 0) > 0
            -- (A holder on the Blizzard Style aura block reads back secret: no trim.)
            if not hasCustomW and not issecretvalue(cbW) and cbW > snappedFrameW + 0.01 then
                PP.Width(castbarBg, snappedFrameW)
            end
            -- Re-snap border textures.
            if PP.GetBorders(castbarBg) then
                PP.SetBorderSize(castbarBg, 1)
                frame.Castbar:ClearAllPoints()
                PP.Point(frame.Castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
                PP.Point(frame.Castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- 9) Inset the clip container by a quarter of a physical pixel (sub-pixel, invisible),
    -- guaranteeing the GPU clips any StatusBar texture rounding past the frame edge.
    -- A quarter, not a half: an edge exactly on a pixel centre hits the rasteriser's
    -- tie rule and the bar covers one more column/row on one side than the other,
    -- which shows as an uneven border wherever the bar sits over it (Show Behind).
    -- Skip the inset on the portrait side so the health bar stays flush with the
    -- portrait (which anchors to the frame, not _barClip).
    if frame._barClip and frame.Health then
        local es = frame:GetEffectiveScale()
        local clipInset = es > 0 and (PP.perfect / es) * 0.25 or PP.mult * 0.25
        local clipL, clipR = clipInset, clipInset
        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
            if effectiveSide == "left" then clipL = 0
            elseif effectiveSide == "right" then clipR = 0 end
        end
        frame._barClip:ClearAllPoints()
        frame._barClip:SetPoint("TOPLEFT", frame, "TOPLEFT", clipL, -clipInset)
        frame._barClip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -clipR, clipInset)
        -- Preserve the health bar's logical top while the clip trims its edges.
        -- Cancel the clip's Y inset after snapping; the bar keeps its full height,
        -- so inheriting that inset would move centered text down by the inset.
        local xOff = frame.Health._xOffset or 0
        local rInset = frame.Health._rightInset or 0
        local topOff = frame.Health._topOffset or 0
        frame.Health:ClearAllPoints()
        frame.Health:SetPoint("TOPLEFT", frame._barClip, "TOPLEFT", xOff, PP.Scale(-topOff) + clipInset)
        frame.Health:SetPoint("RIGHT", frame._barClip, "RIGHT", -rInset, 0)
        PP.Height(frame.Health, settings.healthHeight)
    end

    -- Blizzard Style: the stock geometry is re-asserted over everything above
    -- (a reload runs its own sweep after the per-unit re-anchors instead).
    if ns.UF_Blizz() and not ns._ufReloadSweep then ns.UF_ApplyBlizzardLayout(frame, unit) end
    if settings.portraitSeparator or frame._portraitSeparator then
        ns.UpdatePortraitSeparator(frame, frame.Portrait and frame.Portrait.backdrop,
            settings, effectiveSide, showPortrait and isAttached, ns.UF_Blizz(), nil,
            unit:match("^boss%d$") and ns.UF_BossBorderSettings()
                or (unit == "targettarget" and GetMiniDonorSettings(unit) or nil))
    end
end

-- All sizing is width/height based; positioning is owned by Unlock Mode.

local function GetFrameDimensions(unit, settingsOnly)
    -- Blizzard Style frames are the stock size (settingsOnly: the size the
    -- EllesmereUI look builds from the unit's settings, whatever the style).
    if not settingsOnly and ns.UF_Blizz() then
        local G = ns.UF_BLIZZ[ns.UF_BlizzKind(unit)]
        if G then return G.w, G.h end
    end
    local settings = GetSettingsForUnit(unit)
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    local miniUnit = unit == "pet" or unit == "targettarget" or unit == "focustarget" or (unit and unit:match("^boss%d$"))
    if miniUnit and pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    local pSizeAdj = settings.portraitSize or 0
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
    local powerPos = settings.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and (settings.powerHeight or 6) or 0

    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    -- Snap returned dimensions to the physical pixel grid so width-matching and
    -- the cog display agree with the rendered frame size.
    local snap = PP.Snap
    if unit == "player" or unit == "target" then
        local ptH = settings.healthHeight + powerExtra
        local adjPH = ptH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
        if isAttached and pSide == "top" then pSide = (unit == "player") and "left" or "right" end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return snap(w), snap(ptH + btbExtra)
    elseif unit == "focus" then
        local pH = powerIsAtt and (settings.powerHeight or 6) or 0
        local barH = settings.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return snap(w), snap(barH + btbExtra)
    elseif unit == "pet" or unit == "targettarget" or unit == "focustarget" then
        -- A WoW Forever pet stacks its attached power bar with the health bar.
        local miniPowerH = (unit == "pet" and ns.UF_PetHasPower) and powerExtra or 0
        return snap(settings.frameWidth), snap(settings.healthHeight + miniPowerH)
    elseif unit:match("^boss") then
        local pH = powerIsAtt and (settings.powerHeight or 6) or 0
        local barH = settings.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return snap(w), snap(barH)
    end
    return 150, 30
end

-- Fill-texture rotation, DERIVED -- never set on its own, so it cannot go stale against
-- the bar's axis or a texture swap. Two texture families need opposite treatment on a
-- vertical bar: stretch textures (shield.tga, striped3, blizzard, WHITE8X8, every
-- health texture) are one image scaled to the fill rect, authored wide-and-short, so on
-- a tall bar they must be ROTATED or they smear; tiled textures (stripedReversed, the
-- large* stripe sets, striped-maxhp, modern absorb) repeat at native pixel size on both
-- axes and already read correctly at any bar shape, so rotating them fights the tiling
-- and must NOT happen. Tiling is read back off the live fill texture rather than passed
-- in, so this stays correct no matter which style function last touched the bar.
function ns.ApplyFillRotation(bar)
    if not (bar and bar.SetRotatesTexture) then return end
    local vert = bar.GetOrientation and bar:GetOrientation() == "VERTICAL"
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local tiled = fill and ((fill.GetHorizTile and fill:GetHorizTile())
                         or (fill.GetVertTile and fill:GetVertTile()))
    bar:SetRotatesTexture((vert and not tiled) and true or false)
end

-- Vertical health fill. SetOrientation drives the fill AXIS; healthReverseFill still
-- flips direction WITHIN that axis (horizontal: left-right/right-left; vertical:
-- bottom-top/top-bottom). On ns so the options preview paints the same way.
function ns.ApplyHealthOrientation(bar, settings)
    if not bar then return end
    local vert = (settings and settings.healthVerticalFill) and true or false
    bar:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    ns.ApplyFillRotation(bar)
    return vert
end

local function CreateHealthBar(frame, unit, height, xOffset, settings, rightInset)
    height = height or settings.healthHeight
    xOffset = xOffset or 0
    rightInset = rightInset or 0

    -- Power bar "above" pushes the health bar down by the power bar height.
    local ppPos = settings.powerPosition or "below"
    local powerAboveOff = (ppPos == "above") and (settings.powerHeight or 0) or 0

    local health = CreateFrame("StatusBar", nil, frame)
    health:SetFrameStrata(frame:GetFrameStrata())
    health:SetFrameLevel(frame:GetFrameLevel() + 2)
    -- Two-point horizontal anchoring: width derives from the frame, so it can
    -- never exceed the frame boundary regardless of pixel-snapping rounding.
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", xOffset, -powerAboveOff)
    PP.Point(health, "RIGHT", frame, "RIGHT", -rightInset, 0)
    PP.Height(health, height)
    health._xOffset = xOffset  -- class power repositioning
    health._rightInset = rightInset  -- class power repositioning
    health._topOffset = powerAboveOff  -- SnapLayout re-anchoring
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    ApplyHealthBarTexture(health, UnitToSettingsKey(unit))
    ApplyHealthBarAlpha(health, UnitToSettingsKey(unit))
    health:SetReverseFill(settings.healthReverseFill and true or false)
    ns.ApplyHealthOrientation(health, settings)
    ApplyDarkTheme(health, unit)

    -- Smooth bar interpolation (opt-in).
    if settings.smoothBars then
        health.smoothing = Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
    end

    return health
end

I.SlotWidthMul, I.EstimateUFTextWidth, I.ApplyClassColor = SlotWidthMul, EstimateUFTextWidth, ApplyClassColor
I.CreateBottomTextBar, I.ApplyFramePosition = CreateBottomTextBar, ApplyFramePosition
I.ReparentBarsToClip, I.UpdateBordersForScale = ReparentBarsToClip, UpdateBordersForScale
I.GetFrameDimensions, I.CreateHealthBar = GetFrameDimensions, CreateHealthBar
