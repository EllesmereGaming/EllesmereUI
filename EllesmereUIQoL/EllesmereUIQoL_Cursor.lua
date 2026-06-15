local ADDON_NAME = ...

local ECL = EllesmereUI.Lite.NewAddon("EllesmereUICursor")

local TEX_CUSTOM = "Interface\\AddOns\\EllesmereUIQoL\\Media\\ellesmere_cursor.tga"

local RING_TEXTURES = {
    thin   = "Interface\\AddOns\\EllesmereUIQoL\\Media\\ring_thin.tga",
    light  = "Interface\\AddOns\\EllesmereUIQoL\\Media\\ring_light.tga",
    normal = "Interface\\AddOns\\EllesmereUIQoL\\Media\\ring_normal.tga",
    heavy  = "Interface\\AddOns\\EllesmereUIQoL\\Media\\ring_heavy.tga",
    thick  = "Interface\\AddOns\\EllesmereUIQoL\\Media\\ring_thick.tga",
}

local DEF_BASESIZE = 28
local DEF_SCALE    = 1
local DEF_HEX      = "0CD29D"
local DEF_TEX      = "ring_normal"
local DEF_INSTANCE_ONLY = false

local floor, tonumber, strupper, strsub, strgsub, strmatch =
    math.floor, tonumber, string.upper, string.sub, string.gsub, string.match
local min, max = math.min, math.max
local sin, cos = _G.sin or math.sin, _G.cos or math.cos  -- WoW globals are degree-based
local GetTime = GetTime
local GetCursorPosition = GetCursorPosition
local GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown
local UnitCastingInfo = UnitCastingInfo or CastingInfo
local UnitChannelInfo = UnitChannelInfo or ChannelInfo

local f, t
local lastX, lastY

local lastScale, lastHex, lastTex, lastAlpha
local isVisible = true

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function HexToRGB(hex)
    return tonumber(strsub(hex, 1, 2), 16) / 255,
           tonumber(strsub(hex, 3, 4), 16) / 255,
           tonumber(strsub(hex, 5, 6), 16) / 255
end

local function ParseHex(raw)
    if not raw then return 12/255, 210/255, 157/255 end
    raw = strupper(strgsub(raw, "#", ""))
    if not strmatch(raw, "^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then
        return 1, 1, 1
    end
    return HexToRGB(raw)
end

-------------------------------------------------------------------------------
--  Color resolution: accent > class > custom hex. Shared by all three
--  cursor modules (Circle, GCD, Cast). Mutually exclusive: useAccentColor
--  wins over useClassColor which wins over the stored hex.
-------------------------------------------------------------------------------
local function ResolveColor(cfg)
    if not cfg then return 1, 1, 1 end
    if cfg.useAccentColor and EllesmereUI.GetAccentColor then
        return EllesmereUI.GetAccentColor()
    end
    if cfg.useClassColor then
        local _, engClass = UnitClass("player")
        local cc = engClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[engClass]
        if cc then return cc.r, cc.g, cc.b end
    end
    return ParseHex(cfg.hex or DEF_HEX)
end

local function InRealInstancedContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    if difficultyID == 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    return instanceType == "party" or instanceType == "raid"
end

-------------------------------------------------------------------------------
--  Cursor visibility (forward declaration — defined after trail/GCD/cast locals)
-------------------------------------------------------------------------------
local UpdateVisibility

local lastUseClassColor

local function Apply()
    if not f or not t then return end
    local p = ECL.db.profile

    local scale = p.scale or DEF_SCALE
    if scale ~= lastScale then
        lastScale = scale
        local size = floor((p.baseSize or DEF_BASESIZE) * scale + 0.5)
        if size < 8 then size = 8 elseif size > 512 then size = 512 end
        f:SetSize(size, size)
    end

    local hex = p.hex or DEF_HEX
    local colorModeChanged = (p.useClassColor ~= lastUseClassColor)
    lastUseClassColor = p.useClassColor
    -- Recompute whenever hex, class mode, accent mode, or the mode flag
    -- changed. Accent mode also needs per-frame re-read since ELLESMERE_GREEN
    -- mutates in place when the user changes their accent color mid-session.
    local a = (p.alpha or 100) / 100
    if hex ~= lastHex or p.useClassColor or p.useAccentColor or colorModeChanged or a ~= lastAlpha then
        lastHex = hex
        lastAlpha = a
        local r, g, b = ResolveColor(p)
        t:SetVertexColor(r, g, b, a)
    end

    local tex = p.texture or DEF_TEX
    if tex ~= lastTex then
        lastTex = tex
        -- Map dropdown keys (ring_thin, etc.) to RING_TEXTURES keys (thin, etc.)
        local ringKey = tex:match("^ring_(.+)$")
        local path = (ringKey and RING_TEXTURES[ringKey]) or RING_TEXTURES[tex] or TEX_CUSTOM
        t:SetTexture(path)
    end

    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  Cursor Trail Engine (simple dot trail)
-------------------------------------------------------------------------------
local trailDots = {}   -- texture pool
local trailActive = {} -- active dot entries { tex, life, maxLife }
local trailEntryPool = {} -- recycled entry tables to avoid GC churn
local trailTimer = 0
local trailLastCX, trailLastCY = 0, 0
local trailEnabled = false

local TRAIL_POOL_SIZE = 150
local TRAIL_DOT_DURATION = 0.5
local TRAIL_DOT_DENSITY = 0.004
local TRAIL_DOT_BASE_SIZE = 40

local trailContainer  -- high-strata parent for trail dots

local function InitTrailDotPool()
    if not trailContainer then
        trailContainer = CreateFrame("Frame", "ECL_TrailContainer", UIParent)
        trailContainer:SetAllPoints(UIParent)
        trailContainer:SetFrameStrata("TOOLTIP")
        trailContainer:SetFrameLevel(9998)
        trailContainer:EnableMouse(false)
    end
    for i = 1, TRAIL_POOL_SIZE do
        local dot = trailContainer:CreateTexture(nil, "ARTWORK")
        dot:SetTexture("Interface\\AddOns\\EllesmereUIQoL\\Media\\ring_normal.tga")
        dot:SetBlendMode("ADD")
        dot:Hide()
        trailDots[i] = dot
    end
end

local function GetTrailColor()
    local p = ECL.db and ECL.db.profile
    return ResolveColor(p)
end

local function SpawnTrailDot(cx, cy)
    if #trailDots == 0 then return end
    local dot = trailDots[#trailDots]
    trailDots[#trailDots] = nil
    local s = UIParent:GetEffectiveScale()
    local r, g, b = GetTrailColor()
    local baseSize = TRAIL_DOT_BASE_SIZE * 0.8
    dot:SetVertexColor(r, g, b, 1)
    dot:SetSize(baseSize, baseSize)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", trailContainer, "BOTTOMLEFT", cx / s, cy / s)
    dot:SetAlpha(1)
    dot:Show()
    local entry = table.remove(trailEntryPool) or {}
    entry.tex = dot; entry.life = TRAIL_DOT_DURATION; entry.maxLife = TRAIL_DOT_DURATION
    trailActive[#trailActive + 1] = entry
end

local function UpdateTrailDots(elapsed)
    for i = #trailActive, 1, -1 do
        local e = trailActive[i]
        e.life = e.life - elapsed
        if e.life <= 0 then
            e.tex:Hide()
            trailDots[#trailDots + 1] = e.tex
            e.tex = nil
            trailEntryPool[#trailEntryPool + 1] = e
            trailActive[i] = trailActive[#trailActive]
            trailActive[#trailActive] = nil
        else
            local pct = e.life / e.maxLife
            local sz = max(2, TRAIL_DOT_BASE_SIZE * 0.8 * pct)
            e.tex:SetSize(sz, sz)
            e.tex:SetAlpha(pct)
        end
    end
end

local function HideTrailDots()
    for i = #trailActive, 1, -1 do
        local e = trailActive[i]
        e.tex:Hide()
        trailDots[#trailDots + 1] = e.tex
        e.tex = nil
        trailEntryPool[#trailEntryPool + 1] = e
        trailActive[i] = nil
    end
end

local function ApplyTrail()
    local p = ECL.db and ECL.db.profile
    trailEnabled = p and p.trail or false

    if not trailEnabled then
        HideTrailDots()
        if trailContainer then trailContainer:SetScript("OnUpdate", nil) end
        return
    end

    if #trailDots == 0 and #trailActive == 0 then
        InitTrailDotPool()
    end

    -- Trail runs on trailContainer (always visible) so it keeps ticking
    -- even when the cursor circle frame is hidden (disabled or instance-only).
    if trailContainer and not trailContainer:GetScript("OnUpdate") then
        trailContainer:SetScript("OnUpdate", function(_, elapsed)
            if not trailEnabled then return end

            local p = ECL.db and ECL.db.profile
            local circleEnabled = p and p.enabled ~= false
            local inInstance = not (p and p.instanceOnly) or InRealInstancedContent()

            -- Only spawn new dots when the cursor circle would be visible
            if circleEnabled and inInstance then
                local cx, cy = GetCursorPosition()
                trailTimer = trailTimer + elapsed
                local dx = cx - trailLastCX
                local dy = cy - trailLastCY
                local moved = (dx * dx + dy * dy) ^ 0.5
                if trailTimer >= TRAIL_DOT_DENSITY and moved >= 0.5 then
                    trailTimer = 0
                    SpawnTrailDot(cx, cy)
                    trailLastCX, trailLastCY = cx, cy
                end
            end

            -- Always update (fade/shrink) active dots so they finish animating
            UpdateTrailDots(elapsed)
        end)
    end
end

local _unlockHidGCD, _unlockHidCast
local function OnUpdate(_, elapsed)
    local s = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = floor(x / s + 0.5), floor(y / s + 0.5)
    if x ~= lastX or y ~= lastY then
        lastX, lastY = x, y
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
    -- Hide attached GCD/Cast circles during unlock mode
    if EllesmereUI._unlockActive then
        if gcdAttached and gcdRoot and gcdRoot:IsShown() then
            gcdRoot:Hide(); _unlockHidGCD = true
        end
        if castAttached and castRoot and castRoot:IsShown() then
            castRoot:Hide(); _unlockHidCast = true
        end
    else
        if _unlockHidGCD and gcdRoot then gcdRoot:Show(); _unlockHidGCD = nil end
        if _unlockHidCast and castRoot then castRoot:Show(); _unlockHidCast = nil end
    end
end

-------------------------------------------------------------------------------
--  Ring rendering engine (Cooldown-swipe based)
--  Uses CooldownFrameTemplate for smooth circular sweep.
--  Ring thickness is controlled by swapping pre-baked ring textures
--  (ring_thin, ring_light, ring_normal, ring_heavy, ring_thick).
-------------------------------------------------------------------------------

--- Create a ring frame using cooldown swipe for smooth circular fill.
--- @param parent Frame   parent frame
--- @param radius number  half-size of the ring frame
--- @param ringTex string  ring texture key (thin/light/normal/heavy/thick)
--- @param r number  red
--- @param g number  green
--- @param b number  blue
--- @param a number  alpha
--- @return Frame  the ring frame with :StartRing / :StopRing / :SetRingColor / :SetRingTexture
local function CreateRing(parent, radius, ringTex, r, g, b, a)
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(radius * 2, radius * 2)
    ring:SetPoint("CENTER", parent, "CENTER", 0, 0)
    ring:SetFrameLevel(parent:GetFrameLevel() + 1)

    ring.radius = radius
    ring.dur = 0
    ring.maxDur = 0
    ring._r, ring._g, ring._b, ring._a = r, g, b, a

    local texPath = RING_TEXTURES[ringTex] or RING_TEXTURES.normal

    -- Ring texture: static full ring for non-animated display
    ring._fg = ring:CreateTexture(nil, "ARTWORK")
    ring._fg:SetAllPoints(ring)
    ring._fg:SetTexture(texPath)
    ring._fg:SetVertexColor(r, g, b, a)
    ring._fg:Hide()

    -- Cooldown swipe for smooth progress using the ring texture directly.
    ring._cd = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
    ring._cd:SetAllPoints(ring)
    ring._cd:SetFrameLevel(ring:GetFrameLevel() + 1)
    ring._cd:SetHideCountdownNumbers(true)
    ring._cd:SetDrawEdge(false)
    ring._cd:SetDrawBling(false)
    ring._cd:SetReverse(true)
    ring._cd:SetSwipeTexture(texPath)
    ring._cd:SetSwipeColor(r, g, b, a)
    ring._cd:Hide()

    function ring:SetRingColor(nr, ng, nb, na)
        self._r, self._g, self._b, self._a = nr, ng, nb, na
        self._fg:SetVertexColor(nr, ng, nb, na)
        self._cd:SetSwipeColor(nr, ng, nb, na)
    end

    function ring:SetRingRadius(newRadius)
        self.radius = newRadius
        self:SetSize(newRadius * 2, newRadius * 2)
    end

    function ring:SetRingTexture(newKey)
        local tp = RING_TEXTURES[newKey] or RING_TEXTURES.normal
        self._fg:SetTexture(tp)
        self._cd:SetSwipeTexture(tp)
    end

    function ring:StartRing(elapsed, maxDur)
        self.dur = max(elapsed, 0)
        self.maxDur = maxDur
        self._fg:Hide()
        local now = GetTime()
        self._cd:SetCooldown(now - elapsed, maxDur)
        self._cd:Show()
        self:Show()
    end

    function ring:StopRing()
        self._cd:Hide()
        self._fg:Hide()
        self.dur = 0
        self.maxDur = 0
        self:Hide()
    end

    ring:SetScript("OnUpdate", function(self, dt)
        if self.maxDur <= 0 then return end
        self.dur = self.dur + dt
        if self.dur >= self.maxDur then
            self:StopRing()
        end
    end)

    ring:Hide()
    return ring
end

-------------------------------------------------------------------------------
--  GCD Circle
-------------------------------------------------------------------------------
local gcdRoot, gcdRing
local gcdAttached = true  -- follows cursor by default

local function GCD_DB()
    local p = ECL.db and ECL.db.profile
    return p and p.gcd or {}
end

local function CreateGCDCircle()
    if gcdRoot then return end
    local g = GCD_DB()
    local radius = (g.radius or 30)
    local r, ng, b = ParseHex(g.hex)
    local a = (g.alpha or 100) / 100

    gcdRoot = CreateFrame("Frame", "ECL_GCDRoot", UIParent)
    gcdRoot:SetSize(radius * 2, radius * 2)
    gcdRoot:SetFrameStrata("TOOLTIP")
    gcdRoot:SetFrameLevel(9990)
    gcdRoot:EnableMouse(false)
    gcdRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    gcdRing = CreateRing(gcdRoot, radius, g.ringTex or "normal", r, ng, b, a)

    -- GCD event handling
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    gcdRoot:SetScript("OnEvent", function(self, event, unit, _, spellID)
        if unit ~= "player" then return end
        local g2 = GCD_DB()
        if not g2.enabled then return end
        if g2.instanceOnly and not InRealInstancedContent() then return end
        -- On cancelled/failed/interrupted casts the GCD resets stop the ring
        if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_STOP" then
            local cdData = GetSpellCooldown(61304)
            if not cdData or not cdData.duration or cdData.duration <= 0 or not cdData.startTime or cdData.startTime <= 0 then
                gcdRing:StopRing()
            end
            return
        end
        -- Query GCD via the reference spell; duration may be a secret number
        -- so wrap the comparison in pcall to avoid taint errors
        local cdData = GetSpellCooldown(61304)
        if not cdData or not cdData.startTime then return end
        local ok, elapsed, dur = pcall(function()
            local d = cdData.duration
            local s = cdData.startTime
            if d and d > 0 and d <= 1.6 and s and s > 0 then
                return GetTime() - s, d
            end
        end)
        if ok and elapsed then
            gcdRing:StartRing(elapsed, dur)
        end
    end)

    gcdRoot:Hide()
end

local function ApplyGCDCircle()
    local g = GCD_DB()
    local enabled = g.enabled
    if not enabled then
        if gcdRoot then
            gcdRoot:Hide()
            gcdRoot:SetScript("OnUpdate", nil)
            gcdRoot:UnregisterAllEvents()
        end
        return
    end
    if not gcdRoot then CreateGCDCircle() end
    -- Re-register events in case they were unregistered when disabled
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    local attached = g.attached ~= false  -- default true
    local radius = g.radius or 30
    local scale = (g.scale or 100) / 100
    -- ResolveColor picks accent > class > custom hex automatically
    local r, ng, b = ResolveColor(g)
    local a = (g.alpha or 100) / 100

    gcdAttached = attached
    gcdRoot:SetScale(scale)
    gcdRing:SetRingColor(r, ng, b, a)
    gcdRing:SetRingRadius(radius)
    gcdRing:SetRingTexture(g.ringTex or "normal")
    gcdRoot:SetSize(radius * 2, radius * 2)

    gcdRoot:Show()
    -- Respect instance-only: hide if not in instance
    if g.instanceOnly and not InRealInstancedContent() then
        gcdRoot:Hide()
    end
    if attached and not EllesmereUI._unlockActive then
        -- When the cursor circle is visible, anchor directly to it.
        -- When the cursor circle is hidden (e.g. instance-only outside an instance),
        -- the cursor frame's OnUpdate stops firing so it no longer tracks the mouse.
        -- In that case we give the GCD circle its own cursor-tracking OnUpdate.
        local cursorVisible = f and f:IsShown()
        if cursorVisible then
            gcdRoot:SetScript("OnUpdate", nil)
            gcdRoot:ClearAllPoints()
            gcdRoot:SetPoint("CENTER", f, "CENTER", 0, 0)
        else
            gcdRoot:ClearAllPoints()
            gcdRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            gcdRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", floor(cx / s + 0.5), floor(cy / s + 0.5))
            gcdRoot:SetScript("OnUpdate", function()
                local sc = UIParent:GetEffectiveScale()
                local mx, my = GetCursorPosition()
                gcdRoot:ClearAllPoints()
                gcdRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", floor(mx / sc + 0.5), floor(my / sc + 0.5))
            end)
        end
    else
        gcdRoot:SetScript("OnUpdate", nil)
        -- Skip repositioning during unlock mode (mover owns position)
        if not EllesmereUI._unlockActive then
            _G._ECL_ApplyGCDPosition()
        end
    end
end

-------------------------------------------------------------------------------
--  Cast Bar Circle
-------------------------------------------------------------------------------
local castRoot, castRing
local castAttached = true

local function Cast_DB()
    local p = ECL.db and ECL.db.profile
    return p and p.castCircle or {}
end

-- Defined here so it closes over the real trailEnabled, HideTrailDots,
-- gcdRoot, GCD_DB, castRoot, and Cast_DB locals declared above.
UpdateVisibility = function()
    if not f then return end
    local p = ECL.db.profile
    local shouldShow = (p.enabled ~= false)
    if shouldShow and p.instanceOnly then
        shouldShow = InRealInstancedContent()
    end
    -- Standard visibility options (returns true if should HIDE)
    if shouldShow and EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(p) then
        shouldShow = false
    end
    -- Standard visibility mode (mouseover treated as always for cursor)
    if shouldShow then
        local mode = p.visibility or "always"
        if mode == "never" then
            shouldShow = false
        elseif mode == "in_combat" then
            shouldShow = _G._EBS_InCombat and _G._EBS_InCombat() or false
        elseif mode == "out_of_combat" then
            shouldShow = not (_G._EBS_InCombat and _G._EBS_InCombat())
        elseif mode == "in_raid" then
            shouldShow = IsInRaid()
        elseif mode == "in_party" then
            shouldShow = IsInGroup() and not IsInRaid()
        elseif mode == "solo" then
            shouldShow = not IsInGroup()
        -- "always" and "mouseover" both show (cursor is always at mouse)
        end
    end
    if shouldShow and not isVisible then
        isVisible = true
        f:Show()
    elseif not shouldShow and isVisible then
        isVisible = false
        f:Hide()
    end

    -- Trail: hide dots and suppress spawning when circle is hidden
    if not shouldShow and trailEnabled then
        HideTrailDots()
    end

    -- GCD circle instance-only check
    if gcdRoot then
        local g = GCD_DB()
        if g.enabled then
            if g.instanceOnly and not InRealInstancedContent() then
                gcdRoot:Hide()
                gcdRoot:SetScript("OnUpdate", nil)
            else
                gcdRoot:Show()
                -- Re-apply cursor tracking since cursor visibility may have changed
                if g.attached ~= false then
                    local cursorVisible = f and f:IsShown()
                    if cursorVisible then
                        gcdRoot:SetScript("OnUpdate", nil)
                        gcdRoot:ClearAllPoints()
                        gcdRoot:SetPoint("CENTER", f, "CENTER", 0, 0)
                    else
                        gcdRoot:SetScript("OnUpdate", function()
                            local sc = UIParent:GetEffectiveScale()
                            local mx, my = GetCursorPosition()
                            gcdRoot:ClearAllPoints()
                            gcdRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", floor(mx / sc + 0.5), floor(my / sc + 0.5))
                        end)
                    end
                end
            end
        end
    end

    -- Cast circle instance-only check
    if castRoot then
        local c = Cast_DB()
        if c.enabled then
            if c.instanceOnly and not InRealInstancedContent() then
                castRoot:Hide()
                castRoot:SetScript("OnUpdate", nil)
            else
                castRoot:Show()
                -- Re-apply cursor tracking since cursor visibility may have changed
                if c.attached ~= false then
                    local cursorVisible = f and f:IsShown()
                    if cursorVisible then
                        castRoot:SetScript("OnUpdate", nil)
                        castRoot:ClearAllPoints()
                        castRoot:SetPoint("CENTER", f, "CENTER", 0, 0)
                    else
                        castRoot:SetScript("OnUpdate", function()
                            local sc = UIParent:GetEffectiveScale()
                            local mx, my = GetCursorPosition()
                            castRoot:ClearAllPoints()
                            castRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", floor(mx / sc + 0.5), floor(my / sc + 0.5))
                        end)
                    end
                end
            end
        end
    end
end

local function CreateCastCircle()
    if castRoot then return end
    local c = Cast_DB()
    local radius = (c.radius or 36)
    local r, ng, b = ParseHex(c.hex)
    local a = (c.alpha or 100) / 100

    castRoot = CreateFrame("Frame", "ECL_CastRoot", UIParent)
    castRoot:SetSize(radius * 2, radius * 2)
    castRoot:SetFrameStrata("TOOLTIP")
    castRoot:SetFrameLevel(9988)
    castRoot:EnableMouse(false)
    castRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    castRing = CreateRing(castRoot, radius, c.ringTex or "normal", r, ng, b, a)

    -- Spark textures: main spark + glow layer for vibrancy
    local sparkOverlay = CreateFrame("Frame", nil, castRoot)
    sparkOverlay:SetAllPoints(castRoot)
    sparkOverlay:SetFrameLevel(castRoot:GetFrameLevel() + 3)

    -- Primary spark
    castRoot._spark = sparkOverlay:CreateTexture(nil, "OVERLAY")
    castRoot._spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castRoot._spark:SetBlendMode("ADD")
    castRoot._spark:SetSize(radius * 0.6, radius * 0.6)
    castRoot._spark:Hide()

    -- Glow layer: a second additive spark, slightly larger and softer, for bloom
    castRoot._sparkGlow = sparkOverlay:CreateTexture(nil, "OVERLAY", nil, -1)
    castRoot._sparkGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castRoot._sparkGlow:SetBlendMode("ADD")
    castRoot._sparkGlow:SetSize(radius * 0.9, radius * 0.9)
    castRoot._sparkGlow:SetAlpha(0.5)
    castRoot._sparkGlow:Hide()

    -- Spark position updater: orbits the ring centerline each frame
    sparkOverlay:SetScript("OnUpdate", function()
        local spark = castRoot._spark
        local glow = castRoot._sparkGlow
        if not spark or not spark:IsShown() then return end
        local dur, maxDur = castRing.dur, castRing.maxDur
        if not dur or not maxDur or maxDur <= 0 then spark:Hide(); if glow then glow:Hide() end; return end
        local pct = dur / maxDur
        if pct <= 0 or pct >= 1 then spark:Hide(); if glow then glow:Hide() end; return end

        local c2 = Cast_DB()
        local ringRadius = c2.radius or 36
        -- Approximate inner radius ratio per ring texture for spark orbit
        local RING_INNER = { thin = 0.92, light = 0.85, normal = 0.78, heavy = 0.68, thick = 0.58 }
        local innerRatio = RING_INNER[c2.ringTex or "normal"] or 0.78
        local sparkOrbitR = ringRadius * (1 + innerRatio) * 0.5

        local angleDeg = 90 - (pct * 360)
        local sx = cos(angleDeg) * sparkOrbitR
        local sy = sin(angleDeg) * sparkOrbitR

        spark:ClearAllPoints()
        spark:SetPoint("CENTER", castRoot, "CENTER", sx, sy)
        spark:SetRotation(math.rad(angleDeg - 90))

        if glow then
            glow:ClearAllPoints()
            glow:SetPoint("CENTER", castRoot, "CENTER", sx, sy)
            glow:SetRotation(math.rad(angleDeg - 90))
        end
    end)

    -- Cast event handling
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    if UnitChannelInfo and GetUnitEmpowerHoldAtMaxTime then
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    end

    castRoot._castID = nil

    castRoot:SetScript("OnEvent", function(self, event, unit, castID)
        if unit ~= "player" then return end
        local c2 = Cast_DB()
        if not c2.enabled then return end
        if c2.instanceOnly and not InRealInstancedContent() then return end

        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            local name, _, _, startMS, endMS, _, cID = UnitCastingInfo("player")
            if name then
                self._castID = cID
                local elapsed = GetTime() - startMS * 0.001
                local total = (endMS - startMS) * 0.001
                castRing:StartRing(elapsed, total)
                if c2.sparkEnabled then
                    if self._spark then self._spark:Show() end
                    if self._sparkGlow then self._sparkGlow:Show() end
                end
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            or event == "UNIT_SPELLCAST_EMPOWER_START"
            or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
            local name, _, _, startMS, endMS, _, _, _, _, numStages = UnitChannelInfo("player")
            if name then
                self._castID = nil
                if numStages and numStages > 0 and GetUnitEmpowerHoldAtMaxTime then
                    endMS = endMS + GetUnitEmpowerHoldAtMaxTime("player")
                end
                local elapsed = GetTime() - startMS * 0.001
                local total = (endMS - startMS) * 0.001
                castRing:StartRing(elapsed, total)
                if c2.sparkEnabled then
                    if self._spark then self._spark:Show() end
                    if self._sparkGlow then self._sparkGlow:Show() end
                end
            end

        elseif event == "UNIT_SPELLCAST_STOP" then
            if castID == self._castID then
                self._castID = nil
                castRing:StopRing()
                if self._spark then self._spark:Hide() end
                if self._sparkGlow then self._sparkGlow:Hide() end
            end

        else  -- FAILED, INTERRUPTED, CHANNEL_STOP, EMPOWER_STOP
            if not castID or castID == self._castID then
                self._castID = nil
                castRing:StopRing()
                if self._spark then self._spark:Hide() end
                if self._sparkGlow then self._sparkGlow:Hide() end
            end
        end
    end)

    castRoot:Hide()
end

local function ApplyCastCircle()
    local c = Cast_DB()
    local enabled = c.enabled
    if not enabled then
        if castRoot then
            castRoot:Hide()
            castRoot:SetScript("OnUpdate", nil)
            castRoot:UnregisterAllEvents()
        end
        return
    end
    if not castRoot then CreateCastCircle() end
    -- Re-register events in case they were unregistered when disabled
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    if UnitChannelInfo and GetUnitEmpowerHoldAtMaxTime then
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    end
    local attached = c.attached ~= false  -- default true
    local radius = c.radius or 36
    local scale = (c.scale or 100) / 100
    -- ResolveColor picks accent > class > custom hex automatically
    local r, ng, b = ResolveColor(c)
    local a = (c.alpha or 100) / 100

    castAttached = attached
    castRoot:SetScale(scale)
    castRing:SetRingColor(r, ng, b, a)
    castRing:SetRingRadius(radius)
    castRing:SetRingTexture(c.ringTex or "normal")
    castRoot:SetSize(radius * 2, radius * 2)

    -- Spark settings
    if castRoot._spark then
        local sparkSize = radius * 0.6
        castRoot._spark:SetSize(sparkSize, sparkSize)
        if c.sparkEnabled then
            local sr, sg, sb
            -- In accent or class mode, the spark inherits the ring color.
            -- In custom mode, the spark uses its own sparkHex (or falls
            -- back to the ring hex if sparkHex isn't set).
            if c.useAccentColor or c.useClassColor then
                sr, sg, sb = r, ng, b
            else
                sr, sg, sb = ParseHex(c.sparkHex or c.hex)
            end
            castRoot._spark:SetVertexColor(sr, sg, sb, 1)
            -- Glow layer: same color, slightly transparent for bloom
            if castRoot._sparkGlow then
                castRoot._sparkGlow:SetVertexColor(sr, sg, sb, 1)
                castRoot._sparkGlow:SetSize(radius * 0.9, radius * 0.9)
                castRoot._sparkGlow:SetAlpha(0.5)
            end
        end
    end

    castRoot:Show()
    -- Respect instance-only: hide if not in instance
    if c.instanceOnly and not InRealInstancedContent() then
        castRoot:Hide()
    end
    if attached and not EllesmereUI._unlockActive then
        -- When the cursor circle is visible, anchor directly to it.
        -- When the cursor circle is hidden (e.g. instance-only outside an instance),
        -- the cursor frame's OnUpdate stops firing so it no longer tracks the mouse.
        -- In that case we give the cast circle its own cursor-tracking OnUpdate.
        local cursorVisible = f and f:IsShown()
        if cursorVisible then
            castRoot:SetScript("OnUpdate", nil)
            castRoot:ClearAllPoints()
            castRoot:SetPoint("CENTER", f, "CENTER", 0, 0)
        else
            castRoot:ClearAllPoints()
            castRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            castRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", floor(cx / s + 0.5), floor(cy / s + 0.5))
            castRoot:SetScript("OnUpdate", function()
                local sc = UIParent:GetEffectiveScale()
                local mx, my = GetCursorPosition()
                castRoot:ClearAllPoints()
                castRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", floor(mx / sc + 0.5), floor(my / sc + 0.5))
            end)
        end
    else
        castRoot:SetScript("OnUpdate", nil)
        -- Skip repositioning during unlock mode (mover owns position)
        if not EllesmereUI._unlockActive then
            _G._ECL_ApplyCastPosition()
        end
    end
end

-------------------------------------------------------------------------------
--  Unlock Mode registration (for detached GCD / Cast circles)
-------------------------------------------------------------------------------
local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    local elements = {}

    local g = GCD_DB()
    if g.enabled and g.attached == false then
        elements[#elements + 1] = MK({
            key = "ECL_GCD",
            label = "GCD Circle",
            group = "Cursor Lite",
            order = 500,
            getFrame = function() return gcdRoot end,
            getSize = function()
                local g2 = GCD_DB()
                local r = g2.radius or 30
                return r * 2, r * 2
            end,
            setWidth = function(_, w)
                local p = ECL.db and ECL.db.profile
                if not p or not p.gcd then return end
                local PPg = EllesmereUI and EllesmereUI.PP
                p.gcd.radius = math.max(PPg and PPg.Snap(w / 2) or math.floor(w / 2 + 0.5), 5)
                ApplyGCDCircle()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("ECL_GCD")
                end
            end,
            setHeight = function(_, h)
                local p = ECL.db and ECL.db.profile
                if not p or not p.gcd then return end
                local PPg = EllesmereUI and EllesmereUI.PP
                p.gcd.radius = math.max(PPg and PPg.Snap(h / 2) or math.floor(h / 2 + 0.5), 5)
                ApplyGCDCircle()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("ECL_GCD")
                end
            end,
            savePos = function(key, point, relPoint, x, y)
                local p = ECL.db and ECL.db.profile
                if not p then return end
                if not p.gcd then p.gcd = {} end
                p.gcd.pos = { point = point, relPoint = relPoint, x = x, y = y }
                if not EllesmereUI._unlockActive then
                    ApplyGCDCircle()
                end
            end,
            loadPos = function()
                local g2 = GCD_DB()
                return g2.pos
            end,
            clearPos = function()
                local p = ECL.db and ECL.db.profile
                if p and p.gcd then p.gcd.pos = nil end
            end,
            applyPos = function()
                _G._ECL_ApplyGCDPosition()
            end,
        })
    end

    local c = Cast_DB()
    if c.enabled and c.attached == false then
        elements[#elements + 1] = MK({
            key = "ECL_Cast",
            label = "Cast Bar Circle",
            group = "Cursor Lite",
            order = 501,
            getFrame = function() return castRoot end,
            getSize = function()
                local c2 = Cast_DB()
                local r = c2.radius or 36
                return r * 2, r * 2
            end,
            setWidth = function(_, w)
                local p = ECL.db and ECL.db.profile
                if not p or not p.castCircle then return end
                local PPc = EllesmereUI and EllesmereUI.PP
                p.castCircle.radius = math.max(PPc and PPc.Snap(w / 2) or math.floor(w / 2 + 0.5), 5)
                ApplyCastCircle()
                EllesmereUI.RepositionBarToMover("ECL_Cast")
            end,
            setHeight = function(_, h)
                local p = ECL.db and ECL.db.profile
                if not p or not p.castCircle then return end
                local PPc = EllesmereUI and EllesmereUI.PP
                p.castCircle.radius = math.max(PPc and PPc.Snap(h / 2) or math.floor(h / 2 + 0.5), 5)
                ApplyCastCircle()
                EllesmereUI.RepositionBarToMover("ECL_Cast")
            end,
            savePos = function(key, point, relPoint, x, y)
                local p = ECL.db and ECL.db.profile
                if not p then return end
                if not p.castCircle then p.castCircle = {} end
                p.castCircle.pos = { point = point, relPoint = relPoint, x = x, y = y }
                if not EllesmereUI._unlockActive then
                    ApplyCastCircle()
                end
            end,
            loadPos = function()
                local c2 = Cast_DB()
                return c2.pos
            end,
            clearPos = function()
                local p = ECL.db and ECL.db.profile
                if p and p.castCircle then p.castCircle.pos = nil end
            end,
            applyPos = function()
                _G._ECL_ApplyCastPosition()
            end,
        })
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIQoL")
    end
end

-- Position apply helpers (called from unlock mode and from ApplyGCDCircle/ApplyCastCircle)
_G._ECL_ApplyGCDPosition = function()
    if not gcdRoot then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("ECL_GCD")
    if anchored and gcdRoot:GetLeft() then return end
    local g = GCD_DB()
    local pos = g.pos
    if pos and pos.point then
        local px, py = pos.x or 0, pos.y or 0
        local PPa = EllesmereUI and EllesmereUI.PP
        if PPa then
            local es = gcdRoot:GetEffectiveScale()
            local isCenterAnchor = (pos.point == "CENTER")
                and (pos.relPoint == "CENTER" or pos.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                px = PPa.SnapCenterForDim(px, gcdRoot:GetWidth() or 0, es)
                py = PPa.SnapCenterForDim(py, gcdRoot:GetHeight() or 0, es)
            elseif PPa.SnapForES then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
        gcdRoot:ClearAllPoints()
        gcdRoot:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
    else
        -- Default: screen center
        gcdRoot:ClearAllPoints()
        gcdRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

_G._ECL_ApplyCastPosition = function()
    if not castRoot then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("ECL_Cast")
    if anchored and castRoot:GetLeft() then return end
    local c = Cast_DB()
    local pos = c.pos
    if pos and pos.point then
        local px, py = pos.x or 0, pos.y or 0
        local PPa = EllesmereUI and EllesmereUI.PP
        if PPa then
            local es = castRoot:GetEffectiveScale()
            local isCenterAnchor = (pos.point == "CENTER")
                and (pos.relPoint == "CENTER" or pos.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                px = PPa.SnapCenterForDim(px, castRoot:GetWidth() or 0, es)
                py = PPa.SnapCenterForDim(py, castRoot:GetHeight() or 0, es)
            elseif PPa.SnapForES then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
        castRoot:ClearAllPoints()
        castRoot:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
    else
        -- Default: screen center
        castRoot:ClearAllPoints()
        castRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function ECL:OnInitialize()
    -- Cursor owns its own slice of EllesmereUIQoLDB at profile.cursor
    local cursorDefaults = {
        profile = {
            cursor = {
                enabled = true,
                instanceOnly = false,
                useClassColor = true,
                hex = "0CD29D",
                texture = "ring_normal",
                scale = 1,
                alpha = 100,
                gcd = {
                    enabled = false,
                    attached = true,
                    radius = 21,
                    ringTex = "light",
                    scale = 100,
                    hex = "FFFFFF",
                    alpha = 80,
                    useClassColor = false,
                    instanceOnly = false,
                },
                castCircle = {
                    enabled = false,
                    attached = true,
                    radius = 30,
                    ringTex = "normal",
                    scale = 100,
                    hex = "3FA7FF",
                    alpha = 80,
                    sparkEnabled = true,
                    sparkHex = nil,
                    useClassColor = true,
                    instanceOnly = false,
                },
                trail = false,
                visibility       = "always",
                visOnlyInstances = false,
                visHideHousing   = false,
                visHideMounted   = false,
                visHideNoTarget  = false,
                visHideNoEnemy   = false,
            },
        },
    }
    local sharedDB = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", cursorDefaults)
    -- Narrow view onto the cursor sub-table so legacy code using
    -- self.db.profile.<key> keeps working without rewrites.
    -- profile is resolved DYNAMICALLY so it follows profile swaps. The profile
    -- system repoints the registered sharedDB.profile in place (RepointAllDBs);
    -- a frozen `profile = sharedDB.profile.cursor` reference would go stale after
    -- a swap and the cursor would keep applying the old profile's settings.
    self.db = setmetatable({ _shared = sharedDB }, {
        __index = function(t, k)
            if k == "profile" then
                local p = t._shared.profile
                if not p.cursor then p.cursor = {} end
                return p.cursor
            end
        end,
    })
    self.db.ResetProfile = function(dbSelf)
        local defaults = cursorDefaults.profile.cursor
        wipe(dbSelf.profile)
        for k, v in pairs(defaults) do
            if type(v) == "table" then
                dbSelf.profile[k] = {}
                for k2, v2 in pairs(v) do dbSelf.profile[k][k2] = v2 end
            else
                dbSelf.profile[k] = v
            end
        end
    end

    -- Expose for EUI_QoL_Cursor_Options.lua
    _G._ECL_AceDB = self.db
    _G._ECL_Apply = Apply
    _G._ECL_UpdateVisibility = UpdateVisibility
    if EllesmereUI and EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(UpdateVisibility)
    end
    _G._ECL_ApplyGCDCircle = ApplyGCDCircle
    _G._ECL_ApplyCastCircle = ApplyCastCircle
    _G._ECL_RegisterUnlock = RegisterUnlockElements
    _G._ECL_RING_TEXTURES = RING_TEXTURES
    _G._ECL_ApplyTrail = ApplyTrail
end

function ECL:OnEnable()
    if _G._EBS_TEMP_DISABLED and _G._EBS_TEMP_DISABLED.cursor then return end
    f = CreateFrame("Frame", "EllesmereUICursorFrame", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9999)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:SetPoint("CENTER")

    t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetTexture(TEX_CUSTOM)

    f:SetScript("OnUpdate", OnUpdate)

    Apply()

    -- Apply GCD / Cast circles (creates on demand only when enabled)
    C_Timer.After(0.5, function()
        ApplyGCDCircle()
        ApplyCastCircle()
        ApplyTrail()
        RegisterUnlockElements()
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD", UpdateVisibility)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", UpdateVisibility)
end
