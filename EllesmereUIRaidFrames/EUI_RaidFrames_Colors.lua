if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Colors.lua
--
--  Health percent and the class, health, name and power colors, the display
--  name, the top name bar, power text and level text.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs        = pairs
local wipe         = wipe
local type         = type
local tostring     = tostring
local UnitHealth            = UnitHealth
local UnitPower             = UnitPower
local UnitPowerType         = UnitPowerType
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsConnected       = UnitIsConnected
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local InCombatLockdown      = InCombatLockdown
local issecretvalue         = issecretvalue

local AbbreviateNumbers, ApplyFont, defaults = I.AbbreviateNumbers, I.ApplyFont, I.defaults
local DISPEL_COLORS, GetFFD, PixelSnap = I.DISPEL_COLORS, I.GetFFD, I.PixelSnap
local unitToButton = I.unitToButton

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Color helpers
-------------------------------------------------------------------------------
-- Safe health percent: returns 0-100, no secret value arithmetic. inv: the
-- missing-health percent instead (100-0, the reversed curve), for a bar under
-- Inverted Fill.
local function GetSafeHealthPercent(unit, inv)
    if inv then return UnitHealthPercent(unit, true, CurveConstants.ReverseTo100) end
    return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
end

-- Classic health color curve: red (dead) -> yellow (mid) -> green (full). Built
-- once via C_CurveUtil and passed to UnitHealthPercent, which handles secret
-- values internally and returns a clean ColorMixin.
local classicHealthCurve
local function GetClassicHealthCurve()
    if classicHealthCurve then return classicHealthCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0, CreateColor(1, 0, 0, 1))     -- red at 0%
    curve:AddPoint(0.5, CreateColor(1, 1, 0, 1))   -- yellow at 50%
    curve:AddPoint(1, CreateColor(0, 1, 0, 1))     -- green at 100%
    classicHealthCurve = curve
    return curve
end

-- Custom Dynamic Colors: the Classic path with user-chosen stops. Live frames feed a C_CurveUtil
-- curve to UnitHealthPercent (secret-value safe); cached, rebuilt only when one of the three
-- colors changes. do-block keeps the cache state off the main-chunk local budget.
do
    local DEF100 = { r = 0, g = 1, b = 0 }
    local DEF50  = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }
    local DEF0   = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }
    local dynCurve
    local r0, g0, b0, r50, g50, b50, r100, g100, b100
    function ns.GetCustomDynamicCurve(s)
        s = s or db.profile
        local c0   = s.dynamicColor0   or DEF0
        local c50  = s.dynamicColor50  or DEF50
        local c100 = s.dynamicColor100 or DEF100
        if not (dynCurve
            and r0   == c0.r   and g0   == c0.g   and b0   == c0.b
            and r50  == c50.r  and g50  == c50.g  and b50  == c50.b
            and r100 == c100.r and g100 == c100.g and b100 == c100.b) then
            dynCurve = C_CurveUtil.CreateColorCurve()
            dynCurve:SetType(Enum.LuaCurveType.Linear)
            dynCurve:AddPoint(0,   CreateColor(c0.r,   c0.g,   c0.b,   1))
            dynCurve:AddPoint(0.5, CreateColor(c50.r,  c50.g,  c50.b,  1))
            dynCurve:AddPoint(1,   CreateColor(c100.r, c100.g, c100.b, 1))
            r0, g0, b0       = c0.r, c0.g, c0.b
            r50, g50, b50    = c50.r, c50.g, c50.b
            r100, g100, b100 = c100.r, c100.g, c100.b
        end
        return dynCurve
    end

    -- Clean-number interpolation matching the curve, for previews where the
    -- percent is a known fake (0-1): linear 0/50 below half, 50/100 above.
    function ns.ResolveDynamicColor(s, pct01)
        s = s or db.profile
        local c0   = s.dynamicColor0   or DEF0
        local c50  = s.dynamicColor50  or DEF50
        local c100 = s.dynamicColor100 or DEF100
        if pct01 >= 0.5 then
            local t = (pct01 - 0.5) * 2
            return c50.r + (c100.r - c50.r) * t,
                   c50.g + (c100.g - c50.g) * t,
                   c50.b + (c100.b - c50.b) * t
        end
        local t = pct01 * 2
        return c0.r + (c50.r - c0.r) * t,
               c0.g + (c50.g - c0.g) * t,
               c0.b + (c50.b - c0.b) * t
    end
end

-- Class Color Reactive: the Custom Dynamic gradient whose 100% stop is the
-- unit's CLASS color -- full health reads as class identity, wounds bleed
-- into the reactive palette, fully reactive by 40%. One engine curve cached
-- per class token; the fingerprint names every input (0%/50% stops + the
-- class color, so Custom Class Colors edits rebuild too). Secret-safe: the
-- curve is evaluated inside UnitHealthPercent exactly like Classic/Dynamic.
do
    local DEF50 = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }
    local DEF0  = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }
    local GRAY  = { r = 0.5, g = 0.5, b = 0.5 }
    local curves = {}   -- classToken -> { curve, r, g, b (class color used) }
    local r0, g0, b0, r50, g50, b50
    function ns.GetClassReactiveCurve(s, classToken)
        local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see the taint note at the top of EllesmereUIRaidFrames.lua)
        s = s or db.profile
        local c0  = s.dynamicColor0  or DEF0
        local c50 = s.dynamicColor50 or DEF50
        if not (r0 == c0.r and g0 == c0.g and b0 == c0.b
            and r50 == c50.r and g50 == c50.g and b50 == c50.b) then
            wipe(curves)
            r0, g0, b0    = c0.r, c0.g, c0.b
            r50, g50, b50 = c50.r, c50.g, c50.b
        end
        local cc = EllesmereUI.GetClassColor(classToken) or GRAY
        local e = curves[classToken]
        if not (e and e.r == cc.r and e.g == cc.g and e.b == cc.b) then
            local curve = C_CurveUtil.CreateColorCurve()
            curve:SetType(Enum.LuaCurveType.Linear)
            -- Front-loaded class return: full reactive at 40% health, and the
            -- 0.75 stop carries 75% class weight, so identity snaps back
            -- quickly (40->75% climbs 0->75% class, 75->100% eases the rest).
            curve:AddPoint(0,    CreateColor(c0.r,  c0.g,  c0.b,  1))
            curve:AddPoint(0.4,  CreateColor(c50.r, c50.g, c50.b, 1))
            curve:AddPoint(0.75, CreateColor(
                c50.r + (cc.r - c50.r) * 0.75,
                c50.g + (cc.g - c50.g) * 0.75,
                c50.b + (cc.b - c50.b) * 0.75, 1))
            curve:AddPoint(1,    CreateColor(cc.r,  cc.g,  cc.b,  1))
            e = { curve = curve, r = cc.r, g = cc.g, b = cc.b }
            curves[classToken] = e
        end
        return e.curve
    end

    -- Clean-number twin for previews (fake 0-1 percents), mirroring the curve
    -- above: reactive 0-stop -> mid-stop below 40% health, front-loaded class
    -- weight above (75% class by 75% health, easing in the rest to 100%).
    function ns.ResolveClassReactiveColor(s, classToken, pct01)
        local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see the taint note at the top of EllesmereUIRaidFrames.lua)
        s = s or db.profile
        local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or GRAY
        local c0  = s.dynamicColor0  or DEF0
        local c50 = s.dynamicColor50 or DEF50
        if pct01 >= 0.4 then
            local w
            if pct01 >= 0.75 then
                w = 0.75 + (pct01 - 0.75)
            else
                w = (pct01 - 0.4) / 0.35 * 0.75
            end
            return c50.r + (cc.r - c50.r) * w,
                   c50.g + (cc.g - c50.g) * w,
                   c50.b + (cc.b - c50.b) * w
        end
        local t = pct01 / 0.4
        return c0.r + (c50.r - c0.r) * t,
               c0.g + (c50.g - c0.g) * t,
               c0.b + (c50.b - c0.b) * t
    end
end

-- Textured Background (Health Bar Fill cog; off by default): the bar texture on the
-- bar backgrounds, tinted by the colour each is painted. A tinted background's own
-- SetColorTexture tints the texture, so every existing paint keeps it: paint these
-- backgrounds only through SetColorTexture. The health background follows the fill
-- edge, so there the texture is a fixed full-size layer on the health bar, shown
-- while the fill is opaque, with the flat background under it painted clear.
do
    local SetColor  -- the stock SetColorTexture
    local function PaintTinted(self, r, g, b, a) self:SetVertexColor(r, g, b, a) end
    local function PaintLayer(self, r, g, b, a)
        SetColor(self, r, g, b, 0)
        self._rfTexBgLayer:SetVertexColor(r, g, b, a)
    end
    -- The background texture path in settings s (nil = flat); the previews share it.
    function ns.RF_TexBgPath(s)
        if not (s and s.textureBg) then return nil end
        local key = s.healthBarTexture or "atrocity"
        if key == "none" then return nil end
        return ns.EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key, nil)
    end
    -- Whether a health fill painted from s is opaque (dark: the Dark Mode Fill).
    function ns.RF_TexBgOpaque(s, dark)
        if dark then
            local _, _, _, a = ns.EllesmereUI.GetDarkModeFill()
            return a >= 1
        end
        return (s.healthBarOpacity or 100) >= 100
    end
    -- A background that never moves: swapped to the texture at path, tinted by its
    -- paints (vertical: turned with a vertical bar); nil puts the flat colour back at
    -- the next paint.
    function ns.RF_TexBgTint(bg, path, vertical)
        if path then
            SetColor = SetColor or bg.SetColorTexture
            if bg._rfTexBgPath ~= path then
                bg:SetTexture(path)
                bg._rfTexBgPath = path
            end
            if vertical then bg:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) else bg:SetTexCoord(0, 1, 0, 1) end
            bg.SetColorTexture = PaintTinted
        elseif bg._rfTexBgPath then
            bg._rfTexBgPath = nil
            bg.SetColorTexture = nil
            bg:SetVertexColor(1, 1, 1, 1)
            bg:SetTexCoord(0, 1, 0, 1)
        end
    end
    -- The health background's fixed layer (built once, turned as the fill is), shown
    -- while path is set; the next paint of bg tints it.
    function ns.RF_TexBgLayer(health, bg, path)
        if path then
            SetColor = SetColor or bg.SetColorTexture
            local layer = bg._rfTexBgLayer
            if not layer then
                layer = health:CreateTexture(nil, "BACKGROUND", nil, 2)
                layer:SetAllPoints(health)
                bg._rfTexBgLayer = layer
            end
            if layer._rfTexBgPath ~= path then
                layer:SetTexture(path)
                layer._rfTexBgPath = path
            end
            if health:GetRotatesTexture() then
                layer:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
            else
                layer:SetTexCoord(0, 1, 0, 1)
            end
            layer:Show()
            bg.SetColorTexture = PaintLayer
        elseif bg.SetColorTexture == PaintLayer then
            bg.SetColorTexture = nil
            bg._rfTexBgLayer:Hide()
        end
    end
    -- Buttons with a health layer, re-checked by every colour push before
    -- ERF:UpdateAllFrames repaints (a Dark Mode Fill edit can cross 100 with no
    -- reload). Nil until the option is first on.
    local watched
    function ns.RF_TexBgRecheck()
        if not watched then return end
        for button, health in pairs(watched) do
            local d = GetFFD(button)
            local s = d._isParty and ns._scaledPartyProxy
                or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
            local path = ns.RF_TexBgPath(s)
            path = path and not d.kit and ns.RF_TexBgOpaque(s, s.healthColorMode == "dark") and path or nil
            if (path ~= nil) ~= (d.bg.SetColorTexture == PaintLayer) then
                ns.RF_TexBgLayer(health, d.bg, path)
                d._bgSt, d._bgA = nil, nil
                local u = button:GetAttribute("unit")
                if u and UnitExists(u) then ns._ApplyHealthBg(d, health, s, u) end
            end
        end
        if ns._PT_TexBgRecheck then ns._PT_TexBgRecheck() end
    end
    function ns.RF_TexBgWatch()
        if not watched then watched = setmetatable({}, { __mode = "k" }) end
        return watched
    end
    -- The raid, party and Extra Frames buttons (ReanchorAbsorbToFill: built, and
    -- every settings reload before both backgrounds repaint). s: the button's view.
    function ns.RF_TexBgApply(button, d, health, s)
        local path = ns.RF_TexBgPath(s)
        if not (path or d._rfTexBg) then return end
        d._rfTexBg = path and true or nil
        local hp = path and not d.kit and ns.RF_TexBgOpaque(s, s.healthColorMode == "dark") and path or nil
        if d.bg then ns.RF_TexBgLayer(health, d.bg, hp) end
        if d.powerBg then ns.RF_TexBgTint(d.powerBg, path) end
        if hp then
            ns.RF_TexBgWatch()[button] = health
        elseif watched then
            watched[button] = nil
        end
    end
end

-- Dark mode colors come from the global per-profile palette via GetDarkModeFill()/GetDarkModeBg(),
-- fetched live at each use so settings changes show on the next refresh. Opacity honored here
-- (RF + UF); only Resource Bars keep their own alpha.

-- Paints the health-bar background (and dims the fill) for life/connection state. Dead/offline:
-- bg covers the FULL bar (tint reads even at full last-known health), fill dims. Alive: bg covers
-- only the missing-health portion so it never bleeds behind the fill during the OOR fade.
-- Centralized so the full update and the lightweight UNIT_HEALTH update (which owns
-- death/resurrect transitions) stay in lockstep -- else a resurrect arriving only via UNIT_HEALTH
-- strands the tint. Colors overridable via the Status Colors swatch in Extras; inline fallbacks
-- allocate only when the DB key is missing.
function ns._ApplyHealthBg(d, health, s, unit, connected, deadOrGhost)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see the taint note at the top of EllesmereUIRaidFrames.lua)
    local bg = d.bg
    if connected == nil then connected = UnitIsConnected(unit) end
    if deadOrGhost == nil then deadOrGhost = UnitIsDeadOrGhost(unit) end
    -- Party Frames kit: the portrait greys out while offline, as stock does
    -- (every connection edge passes through here).
    local kp = d.kitPortrait
    if kp then
        local off = not connected
        if d._kitDesat ~= off then d._kitDesat = off; kp:SetDesaturated(off) end
    end
    -- Party portrait (EUI_RaidFrames_Portrait.lua): the same grey.
    local pt = d.pt
    if pt and pt._on and pt._desat ~= (not connected) then ns.RF_PtOffline(d, unit, connected) end
    -- Dead/offline: bg covers the FULL bar, fill dims. State+color stamped so
    -- a repeated tick in the same state re-applies nothing; entering either
    -- state clears the alive-path anchor/color stamps AND the fill-color
    -- stamp in _UpdateButtonHealth (the tint here overwrote its work).
    if not connected or deadOrGhost then
        local c = (not connected) and (s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 })
            or (s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 })
        local st = (not connected) and 3 or 2
        -- Under Inverted Fill a corpse paints a full missing-health bar (UpdateButton):
        -- its own state, so that fill is hidden and the status colour shows undimmed.
        local hideFill = deadOrGhost and health and health._euiInv
        if hideFill then st = st + 2 end
        if d._bgSt ~= st or d._bgR ~= c.r or d._bgG ~= c.g or d._bgB ~= c.b then
            d._bgSt, d._bgR, d._bgG, d._bgB = st, c.r, c.g, c.b
            d._bgTex, d._bgA = nil, nil
            d._hcR = nil
            if bg then
                bg:ClearAllPoints(); bg:SetAllPoints(health)
                bg:SetColorTexture(c.r, c.g, c.b, 1)
            end
            if health then
                if hideFill then health:SetStatusBarColor(0.3, 0.3, 0.3, 0)
                elseif not connected then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3)
                else health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5) end
            end
        end
        return
    end
    if not bg then return end
    -- Alive: the bg covers exactly the half of the bar the fill texture does NOT
    -- paint, so it hangs off the fill's leading edge -- the fill's right edge
    -- normally, its top edge on a vertical bar, and the opposite edge under
    -- Inverted Fill (where the fill paints missing health and the bg becomes the
    -- current-health surface). The anchor set changes only when the fill texture
    -- object, the axis, or the inversion does; all three change only in the
    -- restyle passes (ReloadFrames / ReloadPartyFrames), which clear d._bgSt right
    -- after, so the steady-state tick skips the reads and the anchor pass entirely.
    if d._bgSt ~= 1 then
        -- Axis and inversion both read off the bar, never the settings, so the
        -- bg follows the direction the fill actually paints.
        local vert = health.GetOrientation and health:GetOrientation() == "VERTICAL"
        local invert = health:GetReverseFill()
        local tex = health:GetStatusBarTexture()
        d._bgSt, d._bgTex, d._bgVert = 1, tex, vert
        d._bgA = nil
        bg:ClearAllPoints()
        if vert then
            if invert then
                bg:SetPoint("TOPLEFT", tex, "BOTTOMLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            else
                bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT", 0, 0)
            end
        else
            if invert then
                bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT", 0, 0)
            else
                bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
    local br, bgr, bb, ba
    if s.healthColorMode == "dark" then
        br, bgr, bb, ba = EllesmereUI.GetDarkModeBg()
    else
        -- Class-colored when bgClassColored, else custom (GetBgColor handles the secret-value
        -- guard + alpha = bgDarkness). MUST match the layout-pass and preview paths or this
        -- refresh clobbers the class-colored bg.
        br, bgr, bb, ba = ns.GetBgColor(unit, s)
    end
    if d._bgR ~= br or d._bgG ~= bgr or d._bgB ~= bb or d._bgA ~= ba then
        d._bgR, d._bgG, d._bgB, d._bgA = br, bgr, bb, ba
        bg:SetColorTexture(br, bgr, bb, ba)
    end
end

local function GetHealthColor(unit, s)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see the taint note at the top of EllesmereUIRaidFrames.lua)
    s = s or db.profile
    local mode = s.healthColorMode or "class"

    if mode == "dark" then
        local dfr, dfg, dfb = EllesmereUI.GetDarkModeFill()
        return dfr, dfg, dfb
    elseif mode == "classic" then
        -- Native WoW health gradient via Blizzard's curve system (secret-value safe)
        local color = UnitHealthPercent(unit, true, GetClassicHealthCurve())
        if color and color.GetRGB then
            return color:GetRGB()
        end
        return 0, 1, 0
    elseif mode == "customDynamic" then
        -- User-customizable gradient via the same secret-safe curve path as Classic
        local color = UnitHealthPercent(unit, true, ns.GetCustomDynamicCurve(s))
        if color and color.GetRGB then
            return color:GetRGB()
        end
        return 0, 1, 0
    elseif mode == "classReactive" then
        -- Class color at full health bleeding into the reactive palette as the
        -- unit takes damage (fully reactive by 40%); engine-evaluated per-class
        -- curve, so secret health never touches Lua.
        local _, classToken = UnitClass(unit)
        if classToken and not issecretvalue(classToken) then
            local color = UnitHealthPercent(unit, true, ns.GetClassReactiveCurve(s, classToken))
            if color and color.GetRGB then
                return color:GetRGB()
            end
        end
        return 0.5, 0.5, 0.5
    elseif mode == "custom" then
        local c = s.customFillColor
        return c.r, c.g, c.b
    else -- "class"
        local _, classToken = UnitClass(unit)
        -- Secret-safe: a secret classToken would throw on GetClassColor's table index.
        if classToken and not issecretvalue(classToken) then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b end
        end
        return 0.5, 0.5, 0.5
    end
end

-- UTF-8 aware character-count cap for an in-frame display name. Shared by the
-- live frames (via ResolveDisplayName) and every preview surface. Skips secret
-- strings entirely (#, string.byte and string.sub all throw on secrets), so a
-- secret name shows verbatim and uncapped. nameMaxLength 0 = off.
-- Takes the caller's settings table `s` so a party override applies correctly.
function ns.CapName(display, s)
    if type(display) ~= "string" then return display end
    if issecretvalue and issecretvalue(display) then return display end
    if display == "" then return display end
    s = s or (db and db.profile)
    local maxLen = s and s.nameMaxLength or 15
    if not maxLen or maxLen <= 0 then return display end
    return EllesmereUI.Utf8Prefix(display, maxLen)
end

-- The Name Format (Text Display, nameFormat): the character name shaped by
-- EllesmereUI.ShortName; unset or "full" shows it whole. Nicknames are never
-- shortened. fmt (a tag's own modifier, [name:abbr]) takes the setting's place.
function ns.RF_FormatName(display, s, fmt)
    local mode = fmt or (s and s.nameFormat)
    if not mode or mode == "full" then return display end
    return EllesmereUI.ShortName(display, mode)
end

-- Fraction of the frame width the NAME text may fill before auto-truncating
-- (1.0 = full width). Every name-width SetWidth routes through this knob;
-- health text keeps its own inline budget.
ns.RF_NAME_WIDTH_FRACTION = 1.0

-- Display name for a unit. Nickname sources in order: Northern Sky Raid Tools (NSAPI), MethodInternal
-- (EasyNicknameAPI), TimelineReminders, the Liquid addon (LiquidAPI), RakGaming Aliases
-- (RG_UnitName), then CustomNames; falls back to the short character name. NSAPI
-- gets our addon key "EUI" (it has a dedicated per-addon setting + EUI_NICKNAME_TOGGLE callback):
-- NSAPI:GetName self-gates on its global nicknames toggle AND that checkbox and returns the short
-- name when unset, falling through to the next source. Every source gates itself entirely (no
-- EUI-side toggle); pcall keeps a misbehaving external API from breaking name rendering.
-- fmt: a tag's Name Format modifier in place of the setting (ns.RF_FormatName).
local function ResolveDisplayName(unit, applyCap, s, fmt)
    local name, surname = UnitName(unit)
    name = name or ""
    local display
    if NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    -- MethodInternal nicknames (EasyNicknameAPI), second source.
    if not display and EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnitForSurface then
        local ok, dn, handled = pcall(
            EasyNicknameAPI.GetNicknameForUnitForSurface, unit, "raidFrames")
        if ok and handled == true then
            if type(dn) == "string"
               and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                display = dn
            else
                display = ns.RF_FormatName(EllesmereUI.WithSurname(name, surname), s, fmt)
            end
        end
    end
    -- TimelineReminders, gated by its own EllesmereUI checkbox. GetNickname falls back to the
    -- plain unit name when none is set, so HasNickname is checked first to keep the Ambiguate path.
    if not display then
        local TR = TimelineReminders
        if TR and TR.GetNickname and TR.HasNickname and TR.NicknamesEnabledForAddOn then
            local okGate, enabled = pcall(TR.NicknamesEnabledForAddOn, TR, ns.NICK_ADDON)
            if okGate and enabled then
                local okHas, has = pcall(TR.HasNickname, TR, unit)
                if okHas and has then
                    local ok, dn = pcall(TR.GetNickname, TR, unit)
                    if ok and type(dn) == "string"
                       and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                        display = dn
                    end
                end
            end
        end
    end
    -- The Liquid addon's LiquidAPI.GetNicknameForEllesmereUI takes the raw UnitName string and returns a nickname or
    -- nil (unset / disabled provider-side / secret or empty name) -- it gates itself. pcall-wrapped
    -- (dot call, single arg, not a method); result re-checked as a clean non-empty string.
    if not display and LiquidAPI and LiquidAPI.GetNicknameForEllesmereUI then
        local ok, dn = pcall(LiquidAPI.GetNicknameForEllesmereUI, name)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    -- RakGaming Aliases (RGA), gated on ns._rgaNick (maintained by
    -- RegisterRGALIASNicknames + RGA's module callbacks: true only while RGA is present AND its
    -- "ellesmereui" module is enabled), so this hot path costs one flag read and never dereferences
    -- RGA's settings shape. dn ~= name keeps the Ambiguate path for unaliased units.
    if not display and ns._rgaNick then
        local ok, dn = pcall(RG_UnitName, unit)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    -- CustomNames (LibStub library), set by RegisterCustomNames once it has loaded.
    -- UnitName returns the raw name when none is set, so dn ~= name keeps the
    -- Ambiguate path; a secret name is never compared.
    if not display and ns._customNames and not (issecretvalue and issecretvalue(name)) then
        local ok, dn = pcall(ns._customNames.UnitName, unit)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    if not display then
        if Ambiguate then name = Ambiguate(name, "short") end
        display = ns.RF_FormatName(EllesmereUI.WithSurname(name, surname), s, fmt)
    end
    -- Cap only the in-frame name (applyCap), not the top name bar banner.
    if applyCap then display = ns.CapName(display, s) end
    return display
end

-- Background color: class color when bgClassColored, else the custom bg color.
-- Returns r, g, b, a (alpha = bgDarkness). Mirrors the health-fill class option.
function ns.GetBgColor(unit, s)
    s = s or db.profile
    local a = (s.bgDarkness or 50) / 100
    if s.bgClassColored and unit and UnitExists(unit) then
        local _, classToken = UnitClass(unit)
        -- classToken can be secret (out-of-range/uninspectable units) and indexing GetClassColor's
        -- tables with one throws "table index is secret"; fall back to custom bg when secret/nil.
        if classToken and not issecretvalue(classToken) then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b, a end
        end
    end
    -- Partial/imported profiles can lack the key (field report 2026-08-16).
    local c = s.customBgColor or defaults.customBgColor
    return c.r, c.g, c.b, a
end

-- Class/custom color resolution for the Top Name Bar text (no accent mode).
local function GetTopNameBarColor(unit, s)
    s = s or db.profile
    if (s.topNameBarTextColorMode or "class") == "custom" then
        local c = s.topNameBarTextColor or { r = 1, g = 1, b = 1 }
        return c.r, c.g, c.b
    end
    local _, classToken = UnitClass(unit)
    if classToken and not issecretvalue(classToken) then
        local cc = EllesmereUI.GetClassColor(classToken)
        if cc then return cc.r, cc.g, cc.b end
    end
    return 1, 1, 1
end

-- Reserve the Top Name Bar's height from the TOP of a frame and style it. Shared by real buttons
-- and every preview so they never drift. Layout + appearance only; the caller sets name text +
-- color. Returns the reserved height (0 when disabled; health re-anchors flush to the top).
-- Show on Bottom (topNameBarBottom): the bar takes the frame's BOTTOM edge instead. Health starts
-- flush at the top (same height), and the power bar and the uniform anchor region (health +
-- power) end on the bar. Those two, and the bar's own edge, are re-anchored only while the option
-- is or just was on, so the top layout never touches them.
local function LayoutTopNameBar(s, baseH, powerH, healthBar, tnb, tnbBg, tnbText, powerBar, preview)
    local enabled = s.topNameBarEnabled
    local topBarH = enabled and PixelSnap(s.topNameBarHeight or 20) or 0
    local bottomY = (enabled and s.topNameBarBottom == true) and topBarH or 0
    local parent
    if healthBar then
        -- A party portrait's bars' area (EUI_RaidFrames_Portrait.lua), else the frame.
        parent = healthBar._euiBarArea or healthBar:GetParent()
        local topY = (bottomY > 0) and 0 or -topBarH
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topY)
        healthBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, topY)
        healthBar:SetHeight(PixelSnap(baseH - ns.RF_HealthPowerInset(s, powerH) - topBarH))
        if bottomY > 0 or (healthBar._euiTnbBottomY or 0) > 0 then
            local uref = healthBar._euiUniformRef
            -- Aura containers protect these once anchored: a combat pass leaves
            -- them for the next one (the stamp stays unchanged).
            if not (InCombatLockdown() and ((powerBar and powerBar:IsProtected())
                or (uref and uref:IsProtected()))) then
                if uref then
                    uref:ClearAllPoints()
                    uref:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    uref:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomY)
                end
                if powerBar then
                    powerBar:ClearAllPoints()
                    powerBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, bottomY)
                    powerBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomY)
                end
                healthBar._euiTnbBottomY = bottomY
            end
        end
    end
    if not tnb then return topBarH end
    if not enabled then
        if tnb._divider then ns.RF_ApplyTopNameDivider(tnb, s, preview) end
        tnb:Hide()
        return topBarH
    end
    if parent and (bottomY > 0 or tnb._euiTnbBottom) then
        tnb:ClearAllPoints()
        if bottomY > 0 then
            tnb:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
            tnb:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        else
            tnb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        end
        tnb._euiTnbBottom = (bottomY > 0) or nil
    end
    tnb:SetHeight(topBarH)
    if tnbBg then
        local bgc = s.topNameBarBgColor or {}
        tnbBg:SetColorTexture(bgc.r or 17/255, bgc.g or 17/255, bgc.b or 17/255, (s.topNameBarBgOpacity or 80) / 100)
    end
    if tnbText then
        ApplyFont(tnbText, s.topNameBarTextSize or 11)
        local align = s.topNameBarTextAlign or "center"
        local ox = s.topNameBarTextOffsetX or 0
        local oy = s.topNameBarTextOffsetY or 0
        tnbText:ClearAllPoints()
        if align == "left" then
            tnbText:SetPoint("LEFT", tnb, "LEFT", 4 + ox, oy); tnbText:SetJustifyH("LEFT")
        elseif align == "right" then
            tnbText:SetPoint("RIGHT", tnb, "RIGHT", -4 + ox, oy); tnbText:SetJustifyH("RIGHT")
        else
            tnbText:SetPoint("CENTER", tnb, "CENTER", ox, oy); tnbText:SetJustifyH("CENTER")
        end
        tnbText:SetJustifyV("MIDDLE")
        -- Force re-layout on a JustifyH change (WoW doesn't relayout otherwise)
        local cur = tnbText:GetText()
        if cur then tnbText:SetText(""); tnbText:SetText(cur) end
    end
    tnb:Show()
    if s.topNameBarDivider == true or tnb._divider then ns.RF_ApplyTopNameDivider(tnb, s, preview) end
    return topBarH
end

-- Live name refresh for every raid + party button. Fired by the external
-- nickname-provider callbacks so changes apply instantly without a /reload.
function ns.RefreshAllNames()
    local s = db and db.profile
    if not s then return end
    local function refresh(unit, btn)
        local d = GetFFD(btn)
        -- Party buttons read through the party proxy so a per-party cap applies.
        local bs = (d and d._isParty) and (ns._scaledPartyProxy or s) or s
        if d then ns.RF_TextNames(d, unit) end
        -- The Top Name Bar keeps the level in front of the name as the name does.
        local attach = ns.RF_TextNameAttach(bs)
        if d and d.topNameBarText and bs.topNameBarEnabled then
            if attach then
                ns._RFNameWithLevel(d.topNameBarText, ResolveDisplayName(unit, false, bs), unit, attach)
            else
                d.topNameBarText:SetText(ResolveDisplayName(unit, false, bs))
            end
            local tr, tg, tb = GetTopNameBarColor(unit, bs)
            d.topNameBarText:SetTextColor(tr, tg, tb)
        end
    end
    for unit, btn in pairs(unitToButton) do refresh(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do refresh(unit, btn) end
end

-- A preview text's colour for its colour mode: accent, class (classToken: the sample member's
-- class; none, as for a pet, reads white), power (pToken: the sample member's power type) or
-- custom (custom: the colour). r, g, b: the colour without one.
function ns.RF_PreviewTextColor(mode, custom, classToken, r, g, b, pToken)
    if mode == "accent" then
        local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
        if ar then return ar, ag, ab end
    elseif mode == "class" then
        local cc = EllesmereUI.GetClassColor(classToken)
        return cc.r, cc.g, cc.b
    elseif mode == "power" then
        local pc = EllesmereUI.GetPowerColor(pToken or "MANA")
        if pc then return pc.r, pc.g, pc.b end
    elseif custom then
        return custom.r, custom.g, custom.b
    end
    return r, g, b
end

-- Anchor a FontString to the health bar using the shared position scheme of the texts.
-- Optional width clamps long values like health text.
function ns.AnchorRFText(fs, health, pos, ox, oy, width)
    if not fs or not health then return end
    fs:ClearAllPoints()
    if width then fs:SetWidth(width); fs:SetHeight(0) end
    ox = ox or 0; oy = oy or 0
    if pos == "topleft" then
        fs:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    elseif pos == "top" then
        fs:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    elseif pos == "topright" then
        fs:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("TOP")
    elseif pos == "left" then
        fs:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "right" then
        fs:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "bottomleft" then
        fs:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottom" then
        fs:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottomright" then
        fs:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("BOTTOM")
    else -- "center"
        fs:SetPoint("CENTER", health, "CENTER", ox, oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    end
    -- Force re-render after a JustifyH change (mirrors the name/health text fns).
    local txt = fs:GetText()
    fs:SetText(""); fs:SetText(txt or "")
end

-------------------------------------------------------------------------------
--  Custom Health / Power Text: one EllesmereUI.TextTags catalog for both. A
--  piece is (unit, s, pv); unit nil is a preview (pv's made-up values, else the
--  schema sample). Values only reach a format setter, never a comparison. Dead
--  or offline keeps the text: [hp] names the status, [hp:pct] reads 0 (as UF).
-------------------------------------------------------------------------------
do
    local TextTags = EllesmereUI.TextTags
    local sformat, sfind, ssub, unpack = string.format, string.find, string.sub, unpack
    local UnitHealthMax, UnitPowerMax = UnitHealthMax, UnitPowerMax
    local UnitPowerPercent, UnitGetTotalAbsorbs = UnitPowerPercent, UnitGetTotalAbsorbs
    local UnitInRaid, GetRaidRosterInfo, IsInRaid = UnitInRaid, GetRaidRosterInfo, IsInRaid
    local SCHEMA = TextTags.UNIT.keys

    -- OFFLINE / DEAD, nil while alive and connected (clean booleans for group units).
    local function Status(unit, pv)
        if unit then
            if not UnitIsConnected(unit) then return EllesmereUI.L("OFFLINE") end
            if UnitIsDeadOrGhost(unit) then return EllesmereUI.L("DEAD") end
        elseif pv then
            if pv.offline then return EllesmereUI.L("OFFLINE") end
            if pv.dead then return EllesmereUI.L("DEAD") end
        end
    end

    local function GetHealth(unit, max)
        if max then return UnitHealthMax(unit) or 0 end
        return UnitHealth(unit, true) or 0
    end
    local function GetPower(unit, max)
        local pType = UnitPowerType(unit)
        if max then return UnitPowerMax(unit, pType) or 0 end
        return UnitPower(unit, pType) or 0
    end

    -- [hp], [pp] and their :max / :abr keys. Current health names the status, so
    -- Health / Max names it once ("DEAD / 150 K").
    local function Amount(key)
        local kind = ssub(key, 1, 2)
        local get = kind == "hp" and GetHealth or GetPower
        local max, abr = sfind(key, ":max", 1, true) ~= nil, sfind(key, ":abr", 1, true) ~= nil
        local status = kind == "hp" and not max
        local pctKey, perKey, sample = kind .. "Pct", kind .. "Per", SCHEMA[key].sample
        return function(unit, s, pv)
            local st = status and Status(unit, pv)
            if st then return st end
            local v
            if unit then
                v = get(unit, max)
            elseif pv and pv[perKey] then
                v = max and 100 * pv[perKey] or (pv[pctKey] or 0) * pv[perKey]
            else
                return sample
            end
            if abr then return AbbreviateNumbers(v) end
            return sformat("%d", v)
        end
    end

    local function HealthPct(unit, s, pv)
        if unit then
            if UnitIsDeadOrGhost(unit) then return "0" end
            return sformat("%.0f", GetSafeHealthPercent(unit) or 0)
        end
        if pv and pv.hpPct then return sformat("%.0f", pv.dead and 0 or pv.hpPct) end
        return SCHEMA["hp:pct"].sample
    end
    local function PowerPct(unit, s, pv)
        if unit then
            return sformat("%.0f", UnitPowerPercent(unit, UnitPowerType(unit), true, CurveConstants.ScaleTo100) or 0)
        end
        if pv and pv.ppPct then return sformat("%.0f", pv.ppPct) end
        return SCHEMA["pp:pct"].sample
    end

    -- Full amounts blank at zero, abbreviated ones read 0, as in the Unit Frames.
    local function Absorb(key, get)
        local abr, sample = sfind(key, ":abr", 1, true) ~= nil, SCHEMA[key].sample
        return function(unit)
            if not unit then return sample end
            local v = get(unit) or 0
            if abr then return AbbreviateNumbers(v) end
            return C_StringUtil.TruncateWhenZero(v)
        end
    end

    -- [name] and [target], plain or with a Name Format modifier ([name:abbr]):
    -- fmt, when given, takes the place of the text's Name Format, so the cap
    -- still comes last and nicknames stay whole.
    local function NamePiece(key, fmt)
        local sample = SCHEMA[key].sample
        return function(unit, s, pv)
            if unit then return ResolveDisplayName(unit, true, s, fmt) end
            -- A preview member's name as its name text would show it.
            if fmt and pv and pv.rawName then
                return ns.CapName(ns.RF_FormatName(pv.rawName, s, fmt), s)
            end
            return pv and pv.name or sample
        end
    end
    -- The target's name through the same resolver, uncapped (Name Max Length is the
    -- unit's own name, and only a clean name could be capped); a secret one passes raw.
    local targetOf = setmetatable({}, { __index = function(t, unit)
        local v = unit .. "target"
        t[unit] = v
        return v
    end })
    local function TargetPiece(key, fmt)
        local sample = SCHEMA[key].sample
        return function(unit, s)
            if not unit then return sample end
            local tunit = targetOf[unit]
            if not UnitExists(tunit) then return "" end
            local name = UnitName(tunit)
            if issecretvalue(name) then return name end
            return ResolveDisplayName(tunit, false, s, fmt)
        end
    end
    local function Group(unit)
        if not unit then return SCHEMA.group.sample end
        if not IsInRaid() then return "" end
        local idx = UnitInRaid(unit)
        if idx and not issecretvalue(idx) then
            local _, _, subgroup = GetRaidRosterInfo(idx)
            return subgroup or ""
        end
        return ""
    end

    local CATALOG = TextTags.Bind(TextTags.UNIT, {
        ["hp"] = Amount("hp"), ["hp:abr"] = Amount("hp:abr"), ["hp:max"] = Amount("hp:max"),
        ["hp:max:abr"] = Amount("hp:max:abr"), ["hp:pct"] = HealthPct,
        ["pp"] = Amount("pp"), ["pp:abr"] = Amount("pp:abr"), ["pp:max"] = Amount("pp:max"),
        ["pp:max:abr"] = Amount("pp:max:abr"), ["pp:pct"] = PowerPct,
        ["absorb"] = Absorb("absorb", UnitGetTotalAbsorbs),
        ["absorb:abr"] = Absorb("absorb:abr", UnitGetTotalAbsorbs),
        ["healabsorb"] = Absorb("healabsorb", UnitGetTotalHealAbsorbs),
        ["healabsorb:abr"] = Absorb("healabsorb:abr", UnitGetTotalHealAbsorbs),
        ["name"] = NamePiece("name"), ["name:first"] = NamePiece("name:first", "first"),
        ["name:last"] = NamePiece("name:last", "last"), ["name:abbr"] = NamePiece("name:abbr", "abbr"),
        ["target"] = TargetPiece("target"), ["target:first"] = TargetPiece("target:first", "first"),
        ["target:last"] = TargetPiece("target:last", "last"), ["target:abbr"] = TargetPiece("target:abbr", "abbr"),
        ["group"] = Group,
    })
    ns.RF_TextTags = CATALOG

    -- Compiled once per parse (the engine caches parses per template): fmt, the
    -- pieces in tag order, each piece's value class (cls), their count and the value
    -- classes the template reads.
    local compiled = setmetatable({}, { __mode = "k" })
    function ns.RF_CustomCompile(template)
        local parsed = TextTags.Parse(CATALOG, template)
        if not parsed then return nil end
        local cc = compiled[parsed]
        if cc then return cc end
        local keys, map, pieces, cls = parsed.keys, CATALOG.map, {}, {}
        for i = 1, #keys do pieces[i], cls[i] = map[keys[i]], SCHEMA[keys[i]].reads end
        cc = { fmt = parsed.fmt, pieces = pieces, cls = cls, n = #keys, reads = parsed.reads }
        compiled[parsed] = cc
        return cc
    end
    local Compile = ns.RF_CustomCompile

    -- Paints a template; returns the value classes it reads (TextTags' reads set),
    -- or false (blank) for a missing or empty one. args: a button's values for this
    -- text, kept between paints; a / b: only the pieces reading those classes are
    -- read again, the rest keep their values (a nil, a new template or no args:
    -- every piece, as on the previews).
    local scratch = {}
    local function CustomTextInto(fs, template, unit, s, pv, args, a, b)
        local cc = Compile(template)
        if not cc then
            fs:SetText("")
            return false
        end
        if not args then
            args, a = scratch, nil
        elseif args.cc ~= cc then
            args.cc, a = cc, nil
        end
        local pieces, cls, n = cc.pieces, cc.cls, cc.n
        for k = 1, n do
            if not a or cls[k] == a or cls[k] == b then args[k] = pieces[k](unit, s, pv) end
        end
        fs:SetFormattedText(cc.fmt, unpack(args, 1, n))
        return cc.reads
    end
    ns.RF_CustomTextInto = CustomTextInto
end

-- Health text in one of the health text modes (Custom texts paint through RF_CustomTextInto). A
-- unit's values are read only in the modes that show them; a preview (unit nil) shows made-up
-- ones, perPct per percent. Returns false for None or an unknown mode, which blank the text;
-- otherwise true.
function ns.RF_HealthTextInto(fs, mode, pct, unit, perPct)
    local v
    if mode == "percent" then
        fs:SetFormattedText("%.0f%%", pct)
    elseif mode == "percentNoSign" then
        fs:SetFormattedText("%.0f", pct)
    elseif mode == "number" then
        if unit then v = UnitHealth(unit, true) else v = pct * perPct end
        if v and AbbreviateNumbers then
            fs:SetText(AbbreviateNumbers(v))
        elseif v then
            fs:SetFormattedText("%s", v)
        end
    elseif mode == "numberPercent" or mode == "percentNumber" then
        if unit then v = UnitHealth(unit, true) else v = pct * perPct end
        local numStr = (v and AbbreviateNumbers) and AbbreviateNumbers(v) or tostring(v or 0)
        if mode == "numberPercent" then
            fs:SetFormattedText("%s | %.0f%%", numStr, pct)
        else
            fs:SetFormattedText("%.0f%% | %s", pct, numStr)
        end
    elseif mode == "missing" then
        if unit then v = UnitHealthMissing(unit, true) else v = (100 - pct) * perPct end
        fs:SetText(C_StringUtil.TruncateWhenZero(v))
        if fs:GetText() then
            if v and AbbreviateNumbers then
                fs:SetText(AbbreviateNumbers(v))
            elseif v then
                fs:SetFormattedText("%s", v)
            end
        end
    else
        fs:SetText("")
        return false
    end
    return true
end

-- Format a heal-absorb amount into a FontString. mode: "amount" (full), "short" (abbreviated like
-- 240k), "none"/nil (blank). C_StringUtil.TruncateWhenZero blanks at zero; its result (and GetText
-- after) is a SECRET string for a secret absorb, so ONLY feed it to SetText or test truthiness --
-- never compare it (== "" taints). "short" gates on GetText truthiness alone (non-nil exactly when
-- non-zero) before abbreviating.
function ns.FormatHealAbsorbInto(fs, amt, mode)
    if not fs then return end
    if not mode or mode == "none" then fs:SetText(""); return end
    fs:SetText(C_StringUtil.TruncateWhenZero(amt or 0))
    if mode == "short" and AbbreviateNumbers and fs:GetText() then
        fs:SetText(AbbreviateNumbers(amt or 0))
    end
end

-- Update one button's Heal Absorb Texts. Called from the absorb-only event path
-- (UNIT_HEAL_ABSORB_AMOUNT_CHANGED), which runs no full button update.
function ns.UpdateHealAbsorbTextFor(button, unit)
    ns.RF_TextHealAbsorb(GetFFD(button), unit)
end

-- Maps a dispel type to its saved-color key. The "" type (Bleed/physical) is
-- stored under dispelColorBleed.
local DISPEL_COLOR_KEYS = {
    Magic   = "dispelColorMagic",
    Curse   = "dispelColorCurse",
    Disease = "dispelColorDisease",
    Poison  = "dispelColorPoison",
    [""]    = "dispelColorBleed",
}

-- Resolve a dispel type's color: user value (via the proxy `s`) falling back to the DISPEL_COLORS
-- default. Returns nil for an unknown/nil type so callers keep their own fallback behavior.
local function GetDispelColor(dtype, s)
    s = s or db.profile
    local key = DISPEL_COLOR_KEYS[dtype]
    if key then
        local c = s[key]
        if c then return c end
    end
    return DISPEL_COLORS[dtype]
end

local function GetPowerColor(unit)
    local _, pToken = UnitPowerType(unit)
    if pToken and EllesmereUI.GetPowerColor then
        local info = EllesmereUI.GetPowerColor(pToken)
        if info then return info.r, info.g, info.b end
    end
    local pType = UnitPowerType(unit) or 0
    local info = PowerBarColor[pType]
    if info then return info.r, info.g, info.b end
    return 0.5, 0.5, 0.5
end

-- Power type + color + bounds (+ the opt-in power-colored bg) for a button's
-- power bar: identity-class state that only moves on UNIT_DISPLAYPOWER, an
-- occupant change or a full paint -- Blizzard's CompactUnitFrame recolors
-- power on exactly those edges -- so the per-tick UNIT_POWER_UPDATE path pushes
-- the value alone. Stamps d._pwType (nil = not derived for this occupant).
-- force = full paint: settings may have changed, so the bg re-tints even when
-- the type/darken stamps still match.
ns._RFPowerTypeEdge = function(d, unit, force)
    local pType = UnitPowerType(unit) or 0
    local pr, pg, pb = GetPowerColor(unit)
    d._pwType = pType
    d.power:SetMinMaxValues(0, 100)
    d.power:SetStatusBarColor(pr, pg, pb, 1)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    if s.powerBgPowerColored and d.powerBg then
        local f = ns.EllesmereUI.GetPowerBgDarkenFactor()
        if force or d._pwBgTintType ~= pType or d._pwBgTintF ~= f then
            d.powerBg:SetColorTexture(pr * f, pg * f, pb * f, (s.powerBgDarkness or 70) / 100)
            d._pwBgTintType = pType
            d._pwBgTintF = f
        end
    end
    -- Power Text's colour is identity-class state too (its Power mode is this type's colour).
    if d._pwtOn then ns.RF_TextPowerColor(d, unit, s, pr, pg, pb) end
end

-------------------------------------------------------------------------------
--  Power Text formatting. The texts, their visibility (only while the power bar
--  shows) and the event paths live in EUI_RaidFrames_TextPaint.lua.
-------------------------------------------------------------------------------

-- Power text in one of its modes (Health Text's minus Missing). pct: the bar's percent
-- (UnitPowerPercent, which can be secret in combat: it only ever reaches a format setter).
-- unit + pType: the live unit, blank while dead or offline like Health Text (both checks return
-- clean booleans for group units); its amount is read only in the modes that show it and goes
-- straight through AbbreviateNumbers into the setter, never compared. A preview (unit nil)
-- shows made-up amounts, perPct per percent. Returns false when it blanks the text (dead,
-- offline, None or an unknown mode), otherwise true.
function ns.RF_PowerTextInto(fs, mode, pct, unit, pType, perPct)
    if unit and (UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)) then
        fs:SetText("")
        return false
    end
    if mode == "percent" then
        fs:SetFormattedText("%.0f%%", pct)
    elseif mode == "percentNoSign" then
        fs:SetFormattedText("%.0f", pct)
    elseif mode == "number" or mode == "numberPercent" or mode == "percentNumber" then
        local num
        if unit then num = AbbreviateNumbers(UnitPower(unit, pType)) else num = AbbreviateNumbers(pct * perPct) end
        if mode == "number" then
            fs:SetText(num)
        elseif mode == "numberPercent" then
            fs:SetFormattedText("%s | %.0f%%", num, pct)
        else
            fs:SetFormattedText("%.0f%% | %s", pct, num)
        end
    else
        fs:SetText("")
        return false
    end
    return true
end

-------------------------------------------------------------------------------
--  Level formatting: the unit's level in front of the name ("60 Name", the WoW
--  Forever default, or "60 | Name") or on its own spot. UNIT_LEVEL (a level-only
--  repaint, ns._RFRepaintLevel) is registered only while some view shows the level.
--  The level is the effective one (scaled content), like the suite's other level
--  texts.
-------------------------------------------------------------------------------

-- The attached positions and their formats: known level, unknown ("??") level.
ns.RF_LEVEL_ATTACH = {
    name    = { "%d %s", "?? %s" },
    nameDiv = { "%d | %s", "?? | %s" },
}

-- The level as text: a secret level goes straight to the setter (never compared),
-- "??" for a unit too far above to read, blank while it is not known yet.
ns._RFLevelInto = function(fs, unit)
    local lvl = UnitEffectiveLevel(unit)
    if issecretvalue(lvl) then
        fs:SetFormattedText("%d", lvl)
    elseif not lvl or lvl == 0 then
        fs:SetText("")
    elseif lvl < 0 then
        fs:SetText("??")
    else
        fs:SetFormattedText("%d", lvl)
    end
end

-- The level the previews show on every sample member: the player's own.
ns._RFPreviewLevel = function()
    local lvl = UnitEffectiveLevel("player")
    if issecretvalue(lvl) or not lvl or lvl <= 0 then return 60 end
    return lvl
end

-- Attach to Name: the name text in an attached position's format (fmt, from
-- RF_LEVEL_ATTACH). The name (possibly secret) and the level only ever reach the
-- format setter; an unknown level, or a name not known yet (empty), leaves the
-- name alone.
ns._RFNameWithLevel = function(fs, name, unit, fmt)
    local lvl = UnitEffectiveLevel(unit)
    local nameKnown = issecretvalue(name) or (name ~= nil and name ~= "")
    if not nameKnown then
        fs:SetText(name)
    elseif issecretvalue(lvl) then
        fs:SetFormattedText(fmt[1], lvl, name)
    elseif not lvl or lvl == 0 then
        fs:SetText(name)
    elseif lvl < 0 then
        fs:SetFormattedText(fmt[2], name)
    else
        fs:SetFormattedText(fmt[1], lvl, name)
    end
end

I.GetClassicHealthCurve, I.GetDispelColor = GetClassicHealthCurve, GetDispelColor
I.GetHealthColor, I.GetPowerColor = GetHealthColor, GetPowerColor
I.GetSafeHealthPercent, I.GetTopNameBarColor = GetSafeHealthPercent, GetTopNameBarColor
I.LayoutTopNameBar, I.ResolveDisplayName = LayoutTopNameBar, ResolveDisplayName
I.broken = false
