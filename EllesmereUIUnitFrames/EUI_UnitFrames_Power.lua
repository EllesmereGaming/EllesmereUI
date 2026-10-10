if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Power.lua
--
--  The power bar seam, portrait separator and power border, spell cost
--  prediction and CreatePowerBar, published as I.CreatePowerBar for the files
--  that load after this one. Reads earlier files through ns and
--  ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local GetSettingsForUnit, UnitToSettingsKey, SetFSFont = I.GetSettingsForUnit, I.UnitToSettingsKey, I.SetFSFont
local UnsnapTex, healthBarTextures = I.UnsnapTex, I.healthBarTextures
local ApplyBarGradient, ApplyPowerBarAlpha = I.ApplyBarGradient, I.ApplyPowerBarAlpha
local EUI_IsSmartPowerPercent = I.EUI_IsSmartPowerPercent
local PLAYER_POWER_DEFAULT, PLAYER_POWER_ALT = I.PLAYER_POWER_DEFAULT, I.PLAYER_POWER_ALT
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Power bar border: detached bars use the selected full border style; attached bars
-- use a solid divider only along the edge shared with the health bar. Lazy creation
-- lets a newly detached/attached bar (or Border Size raised from 0) gain its border
-- live. Shared by the creation path and player/target/focus refresh branches. On ns
-- for the Lua 5.1 200-local ceiling.
--
-- Power Bar Seam (s.borderPowerSeam, opt-in; player / target / focus / boss): the frame
-- Border Style's separator strip (EllesmereUI.GetBorderCompanion "sepH") along the
-- health / power join while the power bar is attached with a height, the frame
-- border is above 0 and its style has seam art; flipped for a bar above health.
-- It rides power._pbSeam, our own frame anchored to the power bar, built on first
-- enable and parented outside the bar clip so its ends can overlap the border,
-- tinted with the frame border colour, which FrameBorderEnter / Leave recolour
-- with the border. Thickness follows the border's edge (exact size, else the
-- step's), height and offsets snapped at the bar's effective scale; re-laid on
-- every pass (a pass on a zero-height bar leaves no resolved rect) and, for an
-- exact size, on a UI scale change (EllesmereUI.RegisterPxReapply). Returns true
-- while it shows, so the power border drops its solid shared-edge strip. Off,
-- under a stock style or a style without the art: nothing is built or run past
-- the first tests. stock = nil reads the session's style; preview = true (the
-- options preview, which repaints itself on a scale change) skips the UI-scale
-- registration.
function ns.UpdatePowerSeam(power, s, stock, preview)
    local seam = power._pbSeam
    local b = s
    local sizeOverride
    local path
    if s and s.borderPowerSeam == true then
        if s == db.profile.boss then
            b = ns.UF_BossBorderSettings()
            sizeOverride = s.borderSizeOverride
        end
        if stock == nil then stock = ns.UF_Blizz() end
        local pos = s.powerPosition or "below"
        if not stock and (pos == "above" or pos == "below") and (s.powerHeight or 6) > 0
           and (sizeOverride or b.borderSize or 1) > 0 and power:IsShown() then
            path = EllesmereUI.GetBorderCompanion(b.borderTexture or "solid", "sepH")
        end
    end
    if not path then
        if seam and seam:IsShown() then
            seam:Hide()
            EllesmereUI.RegisterPxReapply(seam, nil)
        end
        return false
    end
    -- Live power bars sit inside _barClip; a higher level alone cannot escape
    -- that clipping. Keep the seam on the unit frame, as in the preview.
    local owner = power:GetParent()
    while owner and not (owner.unifiedBorder or owner._border) do owner = owner:GetParent() end
    local border = owner and (owner.unifiedBorder or owner._border)
    local parent = owner or power
    if not seam then
        seam = CreateFrame("Frame", nil, parent)
        seam._tex = seam:CreateTexture(nil, "ARTWORK")
        power._pbSeam = seam
    elseif seam:GetParent() ~= parent then
        seam:SetParent(parent)
    end
    seam._power = power
    seam:ClearAllPoints()
    seam:SetAllPoints(power)
    -- Above the fills and the unit frame border, on the border's strata; capped
    -- at frame +11 so a border lifted for an inside 3D portrait (frame +20)
    -- does not carry the seam over the portrait and text layers.
    seam:SetFrameStrata((border or power):GetFrameStrata())
    seam:SetFrameLevel(math.max(power:GetFrameLevel() + 1,
        border and math.min(border:GetFrameLevel() + 1, owner:GetFrameLevel() + 11) or 0))
    local key, size = b.borderTexture, sizeOverride or b.borderSize or 1
    local px
    if not sizeOverride then px = EllesmereUI.BorderPx(b.borderSizePx, size, key) end
    seam._key, seam._step, seam._px, seam._path = key, size, px, path
    seam._above = (s.powerPosition == "above")
    local c = b.borderColor
    seam._tex:SetVertexColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, b.borderAlpha or 1)
    seam:Show()
    ns.UF_LayoutPowerSeam(seam)
    EllesmereUI.RegisterPxReapply(seam, (px and not preview) and ns.UF_LayoutPowerSeam or nil)
    return true
end

-- Lays the seam strip from the values UpdatePowerSeam stamped (also the
-- UI-scale re-derive for an exact size). The art's line sits in its top
-- texels (its soft edge spans texels 0-9 of 32, centred on texel 5): raising
-- the strip 5/32 of its thickness centres the line on the join.
function ns.UF_LayoutPowerSeam(seam)
    local power, t = seam._power, seam._tex
    local es = power:GetEffectiveScale()
    if not (es and es > 0.01) then es = UIParent:GetEffectiveScale() end
    local thick = EllesmereUI.BorderCompanionThickness(seam._key, seam._step, seam._px, es)
    if not thick or thick <= 0 then
        t:Hide()
        return
    end
    if t._path ~= seam._path then
        t:SetTexture(seam._path)
        t._path = seam._path
    end
    local raise = PP.SnapForES(thick * 5 / 32, es)
    local portraitSeam = seam:GetParent()._portraitSeparator
    local leftInset, rightInset = 0, 0
    if portraitSeam and portraitSeam:IsShown() then
        -- Leave one physical pixel clear where the portrait divider meets the seam.
        if portraitSeam._right then rightInset = PP.perfect / es
        else leftInset = PP.perfect / es end
    end
    t:ClearAllPoints()
    if seam._above then
        -- Power above health: the join is the bar's bottom edge.
        t:SetTexCoord(0, 1, 1, 0)
        t:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", leftInset, -raise)
        t:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", -rightInset, -raise)
    else
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", power, "TOPLEFT", leftInset, raise)
        t:SetPoint("TOPRIGHT", power, "TOPRIGHT", -rightInset, raise)
    end
    t:SetHeight(thick)
    t:Show()
end

-- Attached portrait divider: reuse the border style's vertical companion art.
-- A sibling of the portrait avoids clipping the strip where it crosses into the
-- bars. Built only on opt-in; layout and colour updates use existing passes.
function ns.UpdatePortraitSeparator(frame, portrait, s, side, attached, stock, preview, borderSettings)
    local seam = frame._portraitSeparator
    local power = frame.Power or frame._power
    local powerSeam = power and power._pbSeam
    local sizeOverride = borderSettings and s.borderSizeOverride
    local b = borderSettings or s
    local size = sizeOverride or b.borderSize or 1
    local path
    if s.portraitSeparator and attached and portrait and portrait:IsShown()
       and not stock and size > 0 then
        path = EllesmereUI.GetBorderCompanion(b.borderTexture or "solid", "sepV")
    end
    if not path then
        if seam then
            seam:Hide()
            EllesmereUI.RegisterPxReapply(seam, nil)
            if powerSeam and powerSeam:IsShown() then ns.UF_LayoutPowerSeam(powerSeam) end
        end
        return
    end
    if not seam then
        seam = CreateFrame("Frame", nil, frame)
        seam._tex = seam:CreateTexture(nil, "ARTWORK")
        frame._portraitSeparator = seam
    end
    seam:SetAllPoints(portrait)
    -- Above portrait/bar fills and the outer border, on the same strata.
    local border = frame.unifiedBorder or frame._border
    seam:SetFrameLevel(math.max(frame:GetFrameLevel() + (preview and 4 or 9),
        border and border:GetFrameLevel() + 1 or 0))
    seam._key, seam._step = b.borderTexture, size
    seam._px = nil
    if not sizeOverride then seam._px = EllesmereUI.BorderPx(b.borderSizePx, size, seam._key) end
    seam._right = side == "right"
    local c = b.borderColor
    seam._tex:SetVertexColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, b.borderAlpha or 1)
    ns.UF_LayoutPortraitSeparator(seam)
    seam:Show()
    if powerSeam and powerSeam:IsShown() then ns.UF_LayoutPowerSeam(powerSeam) end
    EllesmereUI.RegisterPxReapply(seam, (seam._px and not preview) and ns.UF_LayoutPortraitSeparator or nil)
end

-- Lays the divider from the values UpdatePortraitSeparator stamped (also the
-- UI-scale re-layout): the shared placement on the portrait's inner edge,
-- the art's lead over the portrait, as on cast icons.
function ns.UF_LayoutPortraitSeparator(seam)
    EllesmereUI.PlaceBorderDividerV(seam._tex, seam, seam._right, true, seam._key, seam._step, seam._px,
        seam:GetEffectiveScale())
end

function ns.UpdatePowerBorder(power, settings)
    if not power or not settings then return end
    -- Before the lazy return below: the seam has its own host.
    local seamOn = ns.UpdatePowerSeam(power, settings)
    local pos = settings.powerPosition or "below"
    local isDet = (pos == "detached_top" or pos == "detached_bottom")
    local isAttached = (pos == "above" or pos == "below")
    local size = settings.powerBorderSize or 0
    local border = power._pbBorder
    if not border then
        -- Nothing to render and nothing to hide: stay lazy.
        if not ((isDet or isAttached) and size > 0) then return end
        border = CreateFrame("Frame", nil, power)
        power._pbBorder = border
    end
    -- Re-anchored every pass: a pass that lands while the power bar is zero-height
    -- (Power Bar Height 0 before a Spec Override raises it) leaves the anchors set but
    -- no resolved rect, and nothing recomputes it; re-setting both points restores it.
    border:ClearAllPoints()
    PP.Point(border, "TOPLEFT", power, "TOPLEFT", 0, 0)
    PP.Point(border, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    local c = settings.powerBorderColor or { r = 0, g = 0, b = 0 }
    local alpha = settings.powerBorderAlpha or 1
    -- Attached bars are always Solid; their unused edges are hidden below so only
    -- the health/power seam stays visible.
    local style = isAttached and "solid" or (settings.powerBorderStyle or "solid")
    -- Exact size (nil = the legacy path), resolved against the style actually
    -- painted: an attached bar is forced Solid, so a value paired with a textured
    -- style stands down there.
    local px = EllesmereUI.BorderPx(settings.powerBorderSizePx, size, style)
    EllesmereUI.ApplyBorderStyle(border, size, c.r, c.g, c.b, alpha, style,
        settings.powerBorderOffsetX, settings.powerBorderOffsetY,
        settings.powerBorderShiftX, settings.powerBorderShiftY, "unitframes", size, nil, px)
    local edges = PP.GetBorders(border)
    if edges then
        edges._hideLeft = isAttached or nil
        edges._hideRight = isAttached or nil
        edges._hideTop = (isAttached and pos == "above") or nil
        edges._hideBottom = (isAttached and pos == "below") or nil
        PP.SetBorderSize(border, px or size)
    end
    local borderLevel = settings.powerBorderBehind
        and math.max(0, power:GetFrameLevel() - 1) or (power:GetFrameLevel() + 5)
    border:SetFrameLevel(borderLevel)
    -- An attached bar's only strip is the shared edge, which a shown seam replaces.
    local showBorder = (isDet or isAttached) and size > 0 and not (isAttached and seamOn)
    if showBorder then border:Show() else border:Hide() end

    -- The power text overlay must clear the border: the border shares the bar's strata
    -- and can outrank the overlay's default level, so match strata and lift past it.
    local ovr = power._ppTextOvr
    if ovr then
        ovr:SetFrameStrata(power:GetFrameStrata())
        if showBorder then
            ovr:SetFrameLevel(borderLevel + 5)
        else
            local pf = power:GetParent()
            ovr:SetFrameLevel((pf and pf:GetFrameLevel() or power:GetFrameLevel()) + 15)
        end
    end
end

-------------------------------------------------------------------------------
--  Spell Cost Prediction (WoW Forever only; player, opt-in
--  s.powerCostPrediction): while a spell with a cast time is cast, the mana it
--  will spend is drawn on the power bar in a lighter color, like Blizzard's
--  player frame. The shared engine (EllesmereUI_SpellCostPrediction.lua, nil
--  off Forever) draws it; the bar attaches while the option is on and the bar
--  can show (position not None, height above 0) and detaches otherwise, so
--  nothing is built or registered while it is off.
--  On ns: this chunk sits at the Lua 5.1 local ceiling.
-------------------------------------------------------------------------------
-- Custom color, else Blizzard's mana prediction color: the engine's rule, read
-- here by the options row and its preview (both built only with the engine).
function ns.UF_PowerCostColor(s)
    return EllesmereUI.SpellCostPrediction.Color(s)
end

-- True while the player power bar draws: a position other than None, and a
-- height above 0 in the EUI look (a stock style draws the attached bar at its
-- own height). Spell Cost Prediction and the mana regen spark gate on it.
function ns.UF_PowerBarDraws(settings)
    local pos = settings.powerPosition or "below"
    return pos ~= "none" and ((settings.powerHeight or 6) > 0
        or (ns.UF_Blizz() and (pos == "below" or pos == "above")))
end

-- The player bar as an engine host: the power type PaintPower resolved (the
-- Power Type override first), the color at Power Bar Opacity, and the
-- Blizzard Style mask while the stock art masks the bar. The segment sits one
-- level above the bar (no inBar); the power border draws at power + 5.
if EllesmereUI.SpellCostPrediction then
    ns.UF_POWER_COST_HOST = {
        PowerType = function(power)
            return power.displayType or UnitPowerType("player")
        end,
        -- Power Bar Opacity, normalized as ApplyPowerBarAlpha does: the fill's
        -- own alpha stays at 1 while a gradient carries the opacity.
        Color = function()
            local s = GetSettingsForUnit("player")
            local r, g, b = ns.UF_PowerCostColor(s)
            local op = (s and s.powerBarOpacity) or 100
            if op <= 1.0 then op = op * 100 end
            return r, g, b, op / 100
        end,
        Mask = function(power)
            return power._blizzMasked and power._blizzMask or nil
        end,
    }
end

function ns.UF_SetupPowerCost(power, settings)
    local SCP = EllesmereUI.SpellCostPrediction
    if not SCP then return end
    if power and settings and settings.powerCostPrediction == true
       and ns.UF_PowerBarDraws(settings) then
        SCP.Attach("uf", power, ns.UF_POWER_COST_HOST)
    else
        SCP.Detach("uf")
    end
end

-- The player's power value channel (engine "powerval", UNIT_POWER_FREQUENT)
-- is live while the player frame is visible, paints power, and shows the
-- value: the bar draws or a text zone reads power. Otherwise the event is
-- unregistered (a hidden frame, the UI hidden, a pet battle). Run on attach,
-- on the frame's show and hide, on each settings reload, on text zone changes
-- and on the Power element toggles; other frames return at once.
function ns.UF_PowerValSync(frame)
    if frame._euiBaseUnit ~= "player" then return end
    local on = false
    if frame.Power and frame:IsVisible() and ns.Engine.ElementOn(frame, "Power") then
        local s = GetSettingsForUnit("player")
        on = (s and ns.UF_PowerBarDraws(s)) or false
        local zones = frame._euiTextZones
        if not on and zones then
            for i = 1, #zones do
                if zones[i].power then on = true break end
            end
        end
    end
    ns.Engine.SetChannelOn(frame, "powerval", on)
end

-- Gray-out classification for the power bar's PostUpdate: true for a generic
-- melee NPC (no real power). One function, run through pcall with the unit.
function ns.UF_PowerShouldGray(u)
    if u == "player" or not UnitExists(u) then return false end
    if not UnitCanAttack("player", u) or UnitIsPlayer(u) then return false end
    local cls = UnitClassification(u)
    if cls == "worldboss" then return false end
    local isElite = (cls == "elite" or cls == "rareelite")
    local lvl = UnitLevel(u)
    local pLvl = UnitLevel("player")
    local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
    local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
    if isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1)) then return false end
    local uCls = UnitClassBase and UnitClassBase(u)
    if issecretvalue(uCls) then uCls = nil end
    if uCls == "PALADIN" then return false end
    return true
end

local function CreatePowerBar(frame, unit, settings)
    local powerPos = settings.powerPosition or "below"

    local power = CreateFrame("StatusBar", nil, frame)
    local isDetached = (powerPos == "detached_top" or powerPos == "detached_bottom")
    if isDetached then
        -- Custom strata when enabled, otherwise MEDIUM.
        if db.profile.enableCustomBarStratas then
            power:SetFrameStrata(db.profile.detachedPowerStrata or "HIGH")
        else
            power:SetFrameStrata("MEDIUM")
        end
    else
        power:SetFrameStrata(frame:GetFrameStrata())
    end
    power:SetFrameLevel(frame:GetFrameLevel() + (isDetached and 12 or 3))
    local pw = settings.frameWidth
    if isDetached and (settings.powerWidth or 0) > 0 then
        pw = settings.powerWidth
    end
    PP.Size(power, pw, settings.powerHeight)

    if powerPos == "none" then
        power:Hide()
    elseif powerPos == "above" then
        PP.Point(power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
        PP.Point(power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
    elseif powerPos == "detached_top" then
        power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
    elseif powerPos == "detached_bottom" then
        power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
    else -- "below" (default)
        PP.Point(power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
        PP.Point(power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
    end

    -- Same bar texture as health; WHITE8X8 when none is configured.
    local texKey = (settings and settings.healthBarTexture) or (db.profile.healthBarTexture) or "none"
    local texPath = EllesmereUI.ResolveTexturePath(healthBarTextures, texKey, "Interface\\Buttons\\WHITE8X8")
    power:SetStatusBarTexture(texPath)
    power:GetStatusBarTexture():SetHorizTile(false)
    do
        local pFill = power:GetStatusBarTexture()
        if pFill then UnsnapTex(pFill) end
    end

    local bg = power:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", power, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    local initBg = settings.customPowerBgColor
    if initBg then
        bg:SetColorTexture(initBg.r, initBg.g, initBg.b, 1)
    else
        bg:SetColorTexture(17/255, 17/255, 17/255, 1)
    end
    UnsnapTex(bg)
    power.bg = bg

    -- Fill color is driven by the powerPercentPowerColor toggle; the gradient
    -- layers additively on top of the resolved custom/power-type color.
    local usePowerColor = settings.powerPercentPowerColor ~= false
    power.colorPower = usePowerColor
    if not usePowerColor then
        local customFill = settings.customPowerFillColor
        if customFill then
            power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
        else
            power:SetStatusBarColor(0, 0, 1)
        end
    end
    power.PostUpdateColor = function(self)
        local s2 = GetSettingsForUnit(unit)
        if not s2 then return end
        local useP = s2.powerPercentPowerColor ~= false
        local bR, bG, bB
        if not useP then
            local cf = s2.customPowerFillColor
            if cf then bR, bG, bB = cf.r, cf.g, cf.b else bR, bG, bB = 0, 0, 1 end
        else
            -- Secret-safe: player via the clean token, non-player via the clean integer
            -- power type, so the custom color applies on EVERY unit without depending
            -- on oUF's colors.power sync. Unmapped power types return nil (keep oUF's).
            bR, bG, bB = EllesmereUI.ResolveUnitPowerColor(unit)
        end
        if s2.powerGradientEnabled and bR then
            local gc = s2.powerGradientColor
            -- Bake Bar Opacity into the gradient endpoint alphas (a gradient
            -- overrides region alpha).
            local ga = s2.powerBarOpacity or 100
            if ga > 1.0 then ga = ga / 100 end
            ApplyBarGradient(self:GetStatusBarTexture(), s2.powerGradientDir or "HORIZONTAL",
                bR, bG, bB, ga,
                gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
        elseif not useP then
            local cf = s2.customPowerFillColor
            if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) else self:SetStatusBarColor(0, 0, 1) end
        elseif bR then
            -- Power-color mode without gradient: apply EUI's GLOBAL power color.
            -- oUF.colors.power is not overridden, so oUF would otherwise leave the
            -- bar on its built-in default instead of the user's.
            self:SetStatusBarColor(bR, bG, bB)
        end
        -- Power-colored bg tracks this unit's power color each update, following
        -- target/power-type changes (mirrors the fill). Opacity stays on
        -- customPowerBgAlpha; gated off = zero cost (custom/dark bg stands unchanged).
        if s2.powerBgPowerColored and self.bg then
            local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(unit)
            if pr then
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
            end
        end
        -- Keep power-percent text color in sync with THIS unit (fires on target/focus
        -- change + UNIT_DISPLAYPOWER, following the unit rather than creation-time
        -- color). Gated on power-colored AND text shown: no cost on other frames.
        if s2.powerPercentTextPowerColor and (s2.powerPercentText or "none") ~= "none" and self._applyPowerTextColor then
            self._applyPowerTextColor(s2)
        end
        -- Same for the Bottom Text Bar's power-colored text (per-slot early-out
        -- keeps it ~free when no slot uses power color).
        local btb = frame.BottomTextBar
        if btb and btb._applyBTBPowerColors then btb._applyBTBPowerColors(s2) end
    end

    local customBg = settings.customPowerBgColor
    if customBg then
        bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
    end

    power:SetReverseFill(settings.powerReverseFill and true or false)

    -- Power percent text overlay, parented to the frame (not power) so the bar
    -- clip container cannot clip it.
    local ppTextOvr = CreateFrame("Frame", nil, frame)
    ppTextOvr:SetAllPoints(power)
    ppTextOvr:SetFrameLevel(frame:GetFrameLevel() + 15)
    local ppFS = ppTextOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(ppFS, settings.powerPercentSize or 9)
    ppFS:Hide()
    power._ppFS = ppFS
    power._ppTextOvr = ppTextOvr

    -- Power-percent text color for the CURRENT unit, so target/focus follow the unit
    -- rather than the player. Power-color mode resolves the unit's own power type;
    -- enemies returning a secret token that can't map to a color fall back to white.
    -- No-power units are NOT special-cased and keep showing 0%.
    local function ApplyPowerTextColor(s)
        if s.powerPercentTextPowerColor then
            -- Secret-safe per-unit color: player keeps the exact token color,
            -- non-player recovers it from the clean integer power type.
            local r, g, b = EllesmereUI.ResolveUnitPowerColor(unit)
            if r then ppFS:SetTextColor(r, g, b)
            else ppFS:SetTextColor(1, 1, 1) end
        elseif s.powerTextColor then
            local tc = s.powerTextColor
            ppFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        else
            ppFS:SetTextColor(1, 1, 1)
        end
    end
    power._applyPowerTextColor = ApplyPowerTextColor

    local function ApplyPowerPercentText(s)
        local pos = s.powerPercentText or "none"
        local sz  = s.powerPercentSize or 9
        local ox  = s.powerPercentX or 0
        local oy  = s.powerPercentY or 0

        -- Power Bar Height 0 collapses the bar to a ZERO-HEIGHT frame, and WoW does not
        -- resolve a zero-height frame's rect (GetLeft() returns nil), so any overlay
        -- anchored to it becomes a 0-width unpositioned strip and text never renders.
        -- Anchor the text overlay to the HEALTH bar instead (always resolved), giving
        -- it real height in the row the power bar would occupy. _euiHeight0 leaves
        -- frames that never hit height 0 untouched; a positive height restores SetAllPoints.
        if (s.powerHeight or 6) <= 0 then
            local pPos = s.powerPosition or "below"
            local anchorTo = frame.Health or power
            ppTextOvr:ClearAllPoints()
            if pPos == "above" or pPos == "detached_top" then
                -- Power row above health: text strip sits above the health bar.
                ppTextOvr:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 0)
                ppTextOvr:SetPoint("BOTTOMRIGHT", anchorTo, "TOPRIGHT", 0, 0)
            else
                -- "below"/"detached_bottom": strip sits below the health bar.
                ppTextOvr:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, 0)
                ppTextOvr:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
            end
            ppTextOvr:SetHeight(sz + 6)
            ppTextOvr._euiHeight0 = true
        elseif ppTextOvr._euiHeight0 then
            ppTextOvr:ClearAllPoints()
            ppTextOvr:SetAllPoints(power)
            ppTextOvr._euiHeight0 = nil
        end

        SetFSFont(ppFS, sz)
        ppFS:ClearAllPoints()

        if pos == "none" then
            ppFS:Hide()
            ns.SetTextZoneRaw(frame, ppFS, nil)
            return
        end

        if pos == "left" then
            ppFS:SetJustifyH("LEFT")
            PP.Point(ppFS, "LEFT", ppTextOvr, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            ppFS:SetJustifyH("RIGHT")
            PP.Point(ppFS, "RIGHT", ppTextOvr, "RIGHT", -2 + ox, oy)
        else
            ppFS:SetJustifyH("CENTER")
            PP.Point(ppFS, "CENTER", ppTextOvr, "CENTER", ox, oy)
        end

        local showPct = s.powerShowPercent ~= false
        local pctSuffix = showPct and "%%" or ""
        local fmt = s.powerTextFormat or "perpp"
        local TP = ns.TextPieces
        if fmt == "curpp" then
            ns.SetTextZoneRaw(frame, ppFS, "%s", { TP.curpp })
        elseif fmt == "curmaxpp" then
            ns.SetTextZoneRaw(frame, ppFS, "%s / %s", { TP.curpp, TP.maxpp })
        elseif fmt == "both" then
            ns.SetTextZoneRaw(frame, ppFS, "%s | %s" .. pctSuffix, { TP.curpp, TP.perpp })
        elseif fmt == "smart" then
            -- Percent for mana-based specs, numeric otherwise; resolved at apply
            -- time and re-applied on spec change via ReloadAndUpdate. WoW Forever
            -- passes the player's forced power (druid Mana) so it follows the bar.
            local isPercent = EUI_IsSmartPowerPercent(unit == "player" and EllesmereUI.IS_FOREVER == true
                and EllesmereUI.GetPlayerPowerOverride() or nil)
            if isPercent then
                ns.SetTextZoneRaw(frame, ppFS, "%s" .. pctSuffix, { TP.perpp })
            else
                ns.SetTextZoneRaw(frame, ppFS, "%s", { TP.curpp })
            end
        else -- "perpp" default
            ns.SetTextZoneRaw(frame, ppFS, "%s" .. pctSuffix, { TP.perpp })
        end
        ns.UF_PaintText(frame, frame._euiUnit or unit)

        -- Priority: power-colored (per-unit) > custom color > white.
        ApplyPowerTextColor(s)
        ppFS:Show()
    end

    ApplyPowerPercentText(settings)
    power._applyPowerPercentText = ApplyPowerPercentText

    ApplyPowerBarAlpha(power, UnitToSettingsKey(unit))

    -- Gray out the power bar for enemy NPCs with no real power (melee mobs); keep
    -- it for player, friendly units, enemy players, bosses, minibosses, casters.
    power._grayedOut = false
    power.PostUpdate = function(self, u, cur, min, max)
        local s = GetSettingsForUnit(u)
        if not s then return end

        local pp = s.powerPosition or "below"
        if pp == "none" or pp == "detached_top" or pp == "detached_bottom" then return end

        -- Classification check: generic melee NPCs get the gray bar.
        local ok, shouldGray = pcall(ns.UF_PowerShouldGray, u)
        if not ok then return end

        if shouldGray and not self._grayedOut then
            self._grayedOut = true
            if self.bg then
                self.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                self.bg:SetAlpha(1)
            end
        elseif not shouldGray and self._grayedOut then
            self._grayedOut = false
            if s.powerBgPowerColored and self.bg then
                -- Restore this unit's power color (mirrors the fill); the next
                -- PostUpdateColor keeps it tracking thereafter.
                local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(u)
                if pr then
                    local f = EllesmereUI.GetPowerBgDarkenFactor()
                    self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
                else self.bg:SetColorTexture(17/255, 17/255, 17/255, 1) end
            else
                local customBg = s.customPowerBgColor
                if customBg then
                    if self.bg then self.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1) end
                else
                    if self.bg then self.bg:SetColorTexture(17/255, 17/255, 17/255, 1) end
                end
            end
            -- Bg alpha comes from customPowerBgAlpha (matching ApplyPowerBarAlpha),
            -- NOT powerBarOpacity, which is the FILL opacity.
            if self.bg then
                self.bg:SetAlpha((s and (s.customPowerBgAlpha or 100) or 100) / 100)
            end
        end
    end

    -- Per-spec power type override: an alternate power type on the player power bar
    -- (e.g. Balance Druid: Astral Power vs Mana). Shadow Priest and Mistweaver Monk
    -- default to Mana; other specs default to UnitPowerType.
    if unit == "player" then
        local _, classFile = UnitClass("player")
        if PLAYER_POWER_DEFAULT[classFile] or PLAYER_POWER_ALT[classFile] then
            power.displayAltPower = true
            power.GetDisplayPower = function(self, u)
                local resolved = EllesmereUI.GetPlayerPowerOverride()
                -- Publish for tags so the text matches the bar.
                _G._EUI_ResolvedPowerType[u or "player"] = resolved
                return resolved
            end
        end
    end

    -- Power bar border: full when detached, divider when attached; lazy.
    ns.UpdatePowerBorder(power, settings)

    if unit == "player" then ns.UF_SetupPowerCost(power, settings) end
    -- WoW Forever druids: Mana + Form Power (EUI_UnitFrames_ForeverFormBar.lua).
    if unit == "player" and ns.UF_ForeverFormBar then ns.UF_ForeverFormBar(frame, power, settings) end

    return power
end

-------------------------------------------------------------------------------
--  Player Power Bar: Boss Health Pacing Marker
-------------------------------------------------------------------------------
do
    local _ufBossPacingFrame = nil

    function ns.UpdatePlayerBossPacing()
        local pf = I.frames and I.frames.player
        local power = pf and pf.Power
        local pCfg = db and db.profile and db.profile.player
        if not pCfg or not pCfg.bossPacingEnabled or not power or not power:IsShown() then
            if power and power._bossPacingBar then
                power._bossPacingBar:Hide()
            end
            return
        end

        if not UnitExists("boss1") or UnitIsDead("boss1") then
            if power._bossPacingBar then
                power._bossPacingBar:Hide()
            end
            return
        end

        local bp = power._bossPacingBar
        if not bp then
            bp = CreateFrame("StatusBar", "EUF_PlayerBossPacingBar", power)
            bp:SetAllPoints(power)
            bp:SetFrameLevel(power:GetFrameLevel() + 6)
            bp:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
            local tex = bp:GetStatusBarTexture()
            if tex then
                tex:SetColorTexture(0, 0, 0, 0)
            end

            local spark = bp:CreateTexture(nil, "OVERLAY", nil, 7)
            spark:SetColorTexture(1, 0.25, 0.25, 0.95)
            spark:SetSize(2, power:GetHeight() or 6)
            spark:SetPoint("CENTER", bp:GetStatusBarTexture(), "RIGHT", 0, 0)
            bp._spark = spark

            power._bossPacingBar = bp
        end

        bp:SetReverseFill(power:GetReverseFill() and true or false)
        bp:SetOrientation(power:GetOrientation() or "HORIZONTAL")
        if bp._spark then
            bp._spark:SetSize(2, power:GetHeight() or 6)
            bp._spark:ClearAllPoints()
            bp._spark:SetPoint("CENTER", bp:GetStatusBarTexture(), "RIGHT", 0, 0)
        end

        bp:SetMinMaxValues(0, UnitHealthMax("boss1"))
        bp:SetValue(UnitHealth("boss1"))
        bp:Show()
    end

    function ns.UpdatePlayerBossPacingEventRegistration()
        local pCfg = db and db.profile and db.profile.player
        local enabled = pCfg and (pCfg.bossPacingEnabled == true)
        if enabled then
            if not _ufBossPacingFrame then
                _ufBossPacingFrame = CreateFrame("Frame")
                _ufBossPacingFrame:SetScript("OnEvent", function(self, event, unit)
                    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                        if unit == "boss1" then ns.UpdatePlayerBossPacing() end
                    else
                        ns.UpdatePlayerBossPacing()
                    end
                end)
            end
            _ufBossPacingFrame:RegisterUnitEvent("UNIT_HEALTH", "boss1")
            _ufBossPacingFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "boss1")
            _ufBossPacingFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            _ufBossPacingFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            _ufBossPacingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            ns.UpdatePlayerBossPacing()
        else
            if _ufBossPacingFrame then
                _ufBossPacingFrame:UnregisterAllEvents()
            end
            local pf = I.frames and I.frames.player
            if pf and pf.Power and pf.Power._bossPacingBar then
                pf.Power._bossPacingBar:Hide()
            end
        end
    end
end

I.CreatePowerBar = CreatePowerBar
