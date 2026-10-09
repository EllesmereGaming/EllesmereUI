if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Style.lua
--
--  The debuff grid layout, right-click camera movement, StyleButton and the
--  secure half of the button setup.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local floor        = math.floor
local max          = math.max
local min          = math.min
local abs          = math.abs
local pairs        = pairs
local ipairs       = ipairs
local UnitExists            = UnitExists
local IsInRaid              = IsInRaid
local GetNumGroupMembers    = GetNumGroupMembers
local C_Timer               = C_Timer
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame

local ApplyFont, defaults, GetFFD, PixelSnap = I.ApplyFont, I.defaults, I.GetFFD, I.PixelSnap
local ResolveHealthTexture, unitToButton = I.ResolveHealthTexture, I.unitToButton
local CreateAbsorbBar, UpdateAbsorb = I.CreateAbsorbBar, I.UpdateAbsorb

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local PP
I.PPSetters[#I.PPSetters + 1] = function(v) PP = v end

-------------------------------------------------------------------------------
--  Debuff grid layout (shared by the live render and the options preview)
-------------------------------------------------------------------------------
-- Absorb paint coalescer (Blizzard's own CompactUnitFrame model: absorb /
-- heal-prediction repaints are "frequent and expensive, update once per frame
-- at most"). Event branches MARK; the flush paints each dirty button once,
-- at most a budget of them per render frame -- server batches land several
-- absorb-family events per button in one frame at raid scale, and only the
-- last paint renders. The budget is the backstop for a genuine event storm
-- (a raid-wide shield landing on everyone in one frame); the belt below
-- spreads its own marks across ticks so it never fills the budget itself.
-- The flush frame is hidden whenever the set is empty.
ns._abDirty = {}
ns._abFlushBudget = 20
ns._abFlush = CreateFrame("Frame")
ns._abFlush:Hide()
ns._abFlush:SetScript("OnUpdate", function(self)
    local dirty = ns._abDirty
    local left = ns._abFlushBudget
    local now = GetTime()
    for button in pairs(dirty) do
        dirty[button] = nil
        -- The button's CURRENT occupant, never the token captured at mark
        -- time: a header reassignment between mark and flush would paint the
        -- old occupant's absorb onto the new one.
        local unit = button:GetAttribute("unit")
        if unit then UpdateAbsorb(button, unit, now) end
        left = left - 1
        if left <= 0 then break end
    end
    -- Leftovers past the budget keep the frame shown for the next frame.
    if next(dirty) == nil then self:Hide() end
end)
function ns._MarkAbsorbDirty(button, unit)
    -- unit is kept for the callers' convenience; the flush re-reads the
    -- button's current occupant itself.
    ns._abDirty[button] = true
    ns._abFlush:Show()
end

-- Armed-members belt: covers the ONE transition with no event at all -- an
-- aura-granted shield expiring on its TIMER on an unhit, topped unit (VDH
-- Infernal Strike field report; damaged/healed units correct instantly via
-- the health/absorb events). One shared ticker exists only while some member
-- is armed and cancels itself when the armed set empties. Zero event
-- registrations, zero cost with no shields anywhere.
--
-- STAGGERED: the ticker runs at 0.1s and each tick visits one fifth of the
-- armed set (members whose ordinal in the walk matches the tick's phase), so
-- every member is still visited every 0.5s -- the accepted corner latency --
-- but the marks land in five different render frames instead of one. A
-- single 0.5s sweep re-marked the whole shielded roster at once, and because
-- that painted them together their stamps aged together, locking the burst
-- into a permanent 2 Hz rhythm no drain budget could break. Members painted
-- within 0.45s (event-active) are still skipped by the stamp compare.
-- Membership churn reshuffles the walk order harmlessly: a member is at worst
-- visited twice in a row or waits one extra sweep once.
ns._abArmed = ns._abArmed or {}
ns._abBeltPhase = 0
function ns._AbArm(button, unit, d)
    d._absActive = true
    ns._abArmed[button] = unit
    if not ns._abBelt and C_Timer then
        ns._abBelt = C_Timer.NewTicker(0.1, function()
            local now = GetTime()
            local phase = ns._abBeltPhase
            ns._abBeltPhase = (phase + 1) % 5
            local any = false
            local i = 0
            for btn, u in pairs(ns._abArmed) do
                any = true
                if i % 5 == phase then
                    local ab = GetFFD(btn).absorbBar
                    if not ab or (now - (ab._paintAt or 0)) > 0.45 then
                        ns._MarkAbsorbDirty(btn, u)
                    end
                end
                i = i + 1
            end
            if not any then
                ns._abBelt:Cancel()
                ns._abBelt = nil
            end
        end)
    end
end

-- Effective icon size for dispellable debuffs routed to their own anchor ("Dispellable Debuff
-- Location"): 0 = match the main Debuff Size. Reads scaled proxies transparently (the key is in
-- INDICATOR_SCALE_KEYS; 0 scales to 0, so the match sentinel survives).
function ns.DispellableDebuffSize(s)
    local v = s.dispellableDebuffSize
    if v and v > 0 then return v end
    return s.debuffSize or 18
end

-- Grid placement for debuff icons. opts (optional) overrides pos/grow/ox/oy/size for a
-- sub-group (e.g. dispellable debuffs on their own anchor); spacing/wrap/perRow stay shared.
function ns.DebuffGridPoint(s, idx0, total, opts)
    local pos    = (opts and opts.pos)  or s.debuffPosition or "bottomleft"
    local grow   = (opts and opts.grow) or s.debuffGrowDirection or "RIGHT"
    local sz     = PixelSnap((opts and opts.size) or s.debuffSize or 18)
    local spc    = PixelSnap(s.debuffSpacing or 1)
    local step   = sz + spc
    local ox     = (opts and opts.ox) or s.debuffOffsetX or 0
    local oy     = (opts and opts.oy) or s.debuffOffsetY or 0
    local perRow = s.debuffPerRow or 1
    if perRow < 1 then perRow = 1 end

    -- Icon corner anchored to the same corner of the health bar. Every position is explicit, so the default fallback is only a safety net.
    local corner = "BOTTOMLEFT"
    if     pos == "topleft"     then corner = "TOPLEFT"
    elseif pos == "top"         then corner = "TOP"
    elseif pos == "topright"    then corner = "TOPRIGHT"
    elseif pos == "left"        then corner = "LEFT"
    elseif pos == "center"      then corner = "CENTER"
    elseif pos == "right"       then corner = "RIGHT"
    elseif pos == "bottomleft"  then corner = "BOTTOMLEFT"
    elseif pos == "bottom"      then corner = "BOTTOM"
    elseif pos == "bottomright" then corner = "BOTTOMRIGHT"
    end

    -- Growth vector (per column within a row), screen coords (+x right, +y up).
    -- CENTER grows horizontally like RIGHT but centers each row on the anchor.
    local horizontal = (grow ~= "UP" and grow ~= "DOWN")
    local gvx, gvy = 0, 0
    if     grow == "LEFT" then gvx = -1
    elseif grow == "UP"   then gvy = 1
    elseif grow == "DOWN" then gvy = -1
    else                       gvx = 1   -- RIGHT or CENTER
    end

    -- Row-stack vector (perpendicular). CENTER growth stacks away from the
    -- position's own edge (ResolveFlowAnchor parity); wrap has no options
    -- setter and defaults to "UP", so letting it win here put this preview's
    -- rows on the opposite side from the live frame. Otherwise the explicit
    -- wrap direction wins, else derive away from the anchored edge.
    local svx, svy = 0, 0
    local wrap = s.debuffWrapDirection
    local centerSvy
    if grow == "CENTER" then
        if pos:find("top", 1, true) then centerSvy = -1
        elseif pos:find("bottom", 1, true) then centerSvy = 1 end
    end
    if     centerSvy       then svy = centerSvy
    elseif wrap == "UP"    then svy = 1
    elseif wrap == "DOWN"  then svy = -1
    elseif wrap == "RIGHT" then svx = 1
    elseif wrap == "LEFT"  then svx = -1
    elseif horizontal then
        if pos == "bottomleft" or pos == "bottom" or pos == "bottomright" then svy = 1 else svy = -1 end
    else
        if pos == "topright" or pos == "right" or pos == "bottomright" then svx = -1 else svx = 1 end
    end

    -- perRow == 1 is a single line ALONG the growth direction (no wrapping), keeping the growth control meaningful; >= 2 wraps into rows.
    local row, col
    if perRow <= 1 then
        row, col = 0, idx0
    else
        row = floor(idx0 / perRow)
        col = idx0 % perRow
    end
    local centerOff = 0
    if grow == "CENTER" then
        local rowCount = (perRow <= 1) and (total or 0) or min(perRow, max(0, (total or 0) - row * perRow))
        if rowCount > 0 then centerOff = -((rowCount - 1) * step) / 2 end
    end
    local along  = col * step
    local across = row * step
    local fx = ox + gvx * along + svx * across + centerOff
    local fy = oy + gvy * along + svy * across
    return corner, fx, fy
end

-------------------------------------------------------------------------------
--  Right-click camera movement over raid/party frames: a global mouse watcher starts mouselook
--  when the right button is dragged past a small threshold over one of our unit buttons. It never
--  touches the secure buttons (no taint / click-cast interference); a right-click tap still menus.
-------------------------------------------------------------------------------
do
    local MOVE_THRESHOLD = 4
    local watcher = ns.TakeShell()
    local inLook = false
    local lastX, lastY = 0, 0

    local function stopLook()
        if inLook then MouselookStop(); inLook = false end
        watcher:SetScript("OnUpdate", nil)
    end

    -- True if the cursor is over one of our visible unit buttons (direct IsMouseOver test against the registry).
    local function overOwnFrame()
        local reg = ns._euiUnitButtons
        if not reg then return false end
        for btn in pairs(reg) do
            if btn:IsVisible() and btn:IsMouseOver() then return true end
        end
        return false
    end

    local function onUpdate()
        if not IsMouseButtonDown(2) then stopLook(); return end
        if inLook then return end
        local x, y = GetCursorPosition()
        if abs(x - lastX) > MOVE_THRESHOLD or abs(y - lastY) > MOVE_THRESHOLD then
            pcall(MouselookStart)
            inLook = true
        end
    end

    watcher:SetScript("OnEvent", function(_, event, button)
        if event == "GLOBAL_MOUSE_DOWN" then
            if button ~= "RightButton" then return end
            if not (db and db.profile and db.profile.freeRightClickCamera) then return end
            if not overOwnFrame() then return end
            inLook = false
            lastX, lastY = GetCursorPosition()
            watcher:SetScript("OnUpdate", onUpdate)
        elseif event == "GLOBAL_MOUSE_UP" then
            if button == "RightButton" then stopLook() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- safety: never leave mouselook stuck after a combat-state change
            if not IsMouseButtonDown(2) then stopLook() end
        elseif event == "PLAYER_LOGIN" then
            if ns.FRCM_Refresh then ns.FRCM_Refresh() end
        end
    end)
    watcher:RegisterEvent("PLAYER_LOGIN")

    -- Register the per-click global events only while the feature is on (zero cost when off). Call on toggle.
    function ns.FRCM_Refresh()
        if db and db.profile and db.profile.freeRightClickCamera then
            watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
            watcher:RegisterEvent("GLOBAL_MOUSE_UP")
            watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            watcher:UnregisterEvent("GLOBAL_MOUSE_UP")
            watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
            stopLook()
        end
    end
end

-- Hover/target highlight on a BORDERLESS frame (Border Size 0): the highlight recolors the
-- frame's own border, and with none drawn there is nothing to recolor, so it draws its own at
-- hoverBorderSize/targetBorderSize in the configured border style. `size` nil/0 = not
-- highlighted. `px` = that size's exact pixels (EllesmereUI.BorderPx of the hover/target
-- companion key against `size` and the drawn texture), nil = the legacy size. The drawn size
-- (and px) is cached on the border frame so a group-wide target swap is a color write per
-- button rather than a restyle; callers clear it when the base border returns.
function ns.ApplyHighlightBorder(bf, s, size, r, g, b, a, px)
    if not (PP and bf) then return end
    local texKey = s.borderTexture or "solid"
    if not size or size <= 0 then
        if bf._hlBorderSize then
            EllesmereUI.ApplyBorderStyle(bf, 0, r, g, b, a, texKey)
            -- Keep the cache when the style call bailed (still shown) so the next one retries the hide.
            if not bf:IsShown() then bf._hlBorderSize = nil end
        end
        return
    end
    -- IsShown: a base restyle to Border Size 0 hides the frame without clearing the cache,
    -- so the size alone would let a hover/target repaint after one land on a hidden border.
    if bf._hlBorderSize == size and bf._hlBorderPx == px and bf:IsShown() then
        EllesmereUI.SetBorderStyleColor(bf, r, g, b, a)
        return
    end
    EllesmereUI.ApplyBorderStyle(bf, size, r, g, b, a, texKey,
        s.borderTextureOffset, s.borderTextureOffsetY,
        s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", size, nil, px)
    bf._hlBorderSize = size
    bf._hlBorderPx = px
end

-- Hover/target on a drawn border recolors that same border, so a highlight
-- color (nearly) equal to the border's own shows no change at all: every
-- textured style but Pixels seeds a white border and the highlight defaults
-- to white. Such a highlight draws gold instead (white on a gold border).
function ns.RF_VisibleHighlight(s, r, g, b)
    local c = s.borderColor
    local br, bg, bb = 0, 0, 0
    if c then br, bg, bb = c.r, c.g, c.b end
    if math.abs(r - br) + math.abs(g - bg) + math.abs(b - bb) >= 0.15 then return r, g, b end
    if math.abs(1 - br) + math.abs(0.82 - bg) + math.abs(bb) >= 0.15 then return 1, 0.82, 0 end
    return 1, 1, 1
end

function ns.RF_ColorPowerDivider(host, r, g, b, a)
    if not host or host._powerArtMode ~= "divider" then return end
    host._powerArtR, host._powerArtG, host._powerArtB, host._powerArtAlpha = r, g, b, a
    host._powerArtTex:SetVertexColor(r, g, b, a)
end

function ns.RF_ClearPowerBorderArt(host)
    if not host or not host._powerArtKey then return end
    if host._powerArtTex then host._powerArtTex:Hide() end
    if host._powerArtSeam then host._powerArtSeam:Hide() end
    EllesmereUI.HideBorderStyle(host)
    EllesmereUI.RegisterPxReapply(host, nil)
    PP.ShowBorder(host)
    host._powerArtKey = nil
    host._powerArtMode = nil
end

function ns.RF_LayoutPowerBorderArt(host)
    if not host:IsShown() or not host._powerArtKey then return end
    if host._powerArtMode == "border" then
        EllesmereUI.ApplyBorderStyle(host, host._powerArtSize, host._powerArtR, host._powerArtG, host._powerArtB,
            host._powerArtAlpha, host._powerArtKey, host._powerArtOffset, host._powerArtOffsetY,
            host._powerArtShiftX, host._powerArtShiftY, "unitframes", host._powerArtSize, nil, host._powerArtPx)
        return
    end
    local seam = host._powerArtSeam
    seam:SetFrameStrata(host:GetFrameStrata())
    seam:SetFrameLevel(host:GetParent():GetFrameLevel() + ns.LVL_TEXT - 1)
    local es = host:GetEffectiveScale()
    if not (es and es > 0.01) then es = UIParent:GetEffectiveScale() end
    local thick = EllesmereUI.BorderCompanionThickness(host._powerArtKey, host._powerArtSize, host._powerArtPx, es)
    local realPP = EllesmereUI.PP
    local raise = realPP.SnapForES(thick * 5 / 32, es) - realPP.perfect / es
    local t = host._powerArtTex
    t:ClearAllPoints()
    if host._powerArtEdge == "BOTTOM" then
        t:SetTexCoord(0, 1, 1, 0)
        t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, -raise)
        t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, -raise)
    else
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, raise)
        t:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, raise)
    end
    t:SetHeight(thick)
    t:Show()
    seam:Show()
end

-- Settings passes refresh the cached art; ordinary power paints reuse it.
function ns.RF_ApplyPowerBorderArt(host, s, force, preview, nameBar)
    local mode = nameBar and "divider" or (s.powerBorderStyle or "eui")
    local key = ((nameBar and s.topNameBarDivider == true) or (not nameBar and s.powerBorderMatchFrame == true))
        and not ns.RF_Stock() and s.borderTexture
    if (key ~= "pixels" and key ~= "pixels-textured") or (mode ~= "divider" and mode ~= "border") then
        ns.RF_ClearPowerBorderArt(host)
        return false
    end
    local size = s.borderSize or 1
    local height = nameBar and (s.topNameBarHeight or 20) or (s.powerHeight or 4)
    if size <= 0 or (mode == "divider" and height < 4) then
        ns.RF_ClearPowerBorderArt(host)
        host:Hide()
        return true
    end
    if not force and host._powerArtKey == key and host._powerArtMode == mode and host._powerArtSize == size then
        host:Show()
        return true
    end
    EllesmereUI.HideBorderStyle(host)
    if host._powerArtTex then host._powerArtTex:Hide() end
    if host._powerArtSeam then host._powerArtSeam:Hide() end
    host._powerArtKey, host._powerArtMode = key, mode
    host._powerArtEdge = (nameBar and not s.topNameBarBottom) and "BOTTOM" or "TOP"
    host._powerArtSize = size
    host._powerArtPx = EllesmereUI.BorderPx(s.borderSizePx, size, key)
    local c = s.borderColor
    host._powerArtR, host._powerArtG, host._powerArtB = c and c.r or 0, c and c.g or 0, c and c.b or 0
    host._powerArtAlpha = s.borderAlpha or 1
    host._powerArtOffset, host._powerArtOffsetY = s.borderTextureOffset, s.borderTextureOffsetY
    host._powerArtShiftX, host._powerArtShiftY = s.borderTextureShiftX, s.borderTextureShiftY
    if mode == "divider" then
        local t = host._powerArtTex
        if not t then
            local seam = CreateFrame("Frame", nil, host)
            seam:SetAllPoints(host)
            host._powerArtSeam = seam
            t = seam:CreateTexture(nil, "ARTWORK")
            PP.DisablePixelSnap(t)
            host._powerArtTex = t
        end
        t:SetTexture(EllesmereUI.GetBorderCompanion(key, "sepH"))
        t:SetVertexColor(host._powerArtR, host._powerArtG, host._powerArtB, host._powerArtAlpha)
    end
    host:Show()
    ns.RF_LayoutPowerBorderArt(host)
    EllesmereUI.RegisterPxReapply(host, (mode == "divider" and not preview) and ns.RF_LayoutPowerBorderArt or nil)
    return true, true
end

function ns.RF_ApplyTopNameDivider(tnb, s, preview)
    local host = tnb._divider
    local key = s.borderTexture
    if not PP or not s.topNameBarEnabled or s.topNameBarDivider ~= true or ns.RF_Stock()
        or (key ~= "pixels" and key ~= "pixels-textured") or (s.borderSize or 1) <= 0
        or (s.topNameBarHeight or 20) < 4 then
        if host then
            ns.RF_ClearPowerBorderArt(host)
            host:Hide()
        end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, tnb:GetParent())
        host:SetAllPoints(tnb)
        tnb._divider = host
    end
    ns.RF_ApplyPowerBorderArt(host, s, true, preview, true)
end

-------------------------------------------------------------------------------
--  Style a single button (called once per button at creation time)
-------------------------------------------------------------------------------
local function StyleButton(button)
    local d = GetFFD(button)
    if d.styled then return end
    d.styled = true

    -- Register our unit buttons so the free right-click camera watcher can tell when the cursor is
    -- over one. These are SecureGroupHeader/SecureUnitButton frames (Blizzard-owned), so membership
    -- lives in an external weak table, never a key on the button.
    ns._euiUnitButtons = ns._euiUnitButtons or setmetatable({}, { __mode = "k" })
    ns._euiUnitButtons[button] = true

    local s = db.profile
    -- The Anchor* closures below are stored on `d` and RE-CALLED after d._isParty / d._isExtra are
    -- set (StyleButton runs before that). They MUST resolve the settings source LIVE via LiveS()
    -- rather than capture this raid `s`, or party/extra frames would anchor every indicator, text
    -- and aura at the RAID position. The body keeps the raw `s` for creation-time sizing.
    local function LiveS()
        return d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    end
    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    -- The power bar is ALWAYS created (hidden) so a later swap into a power-enabled profile has a
    -- bar to show; UpdateButton drives per-role show/hide + matching health height. Health starts
    -- FULL height, else the bottom powerH strip shows dark bg as an "empty power bar" until the
    -- first UpdateButton (visible ~0.5s at login).
    local powerH = PixelSnap(s.powerHeight or 4)
    local healthH = h

    -- No SetSize here: sizing is window-phase work (combat-blocked), owned by
    -- ns._StyleButtonSecure below plus the header's initialConfigFunction.

    -- Background (visible behind the health bar where HP is missing)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local bgc = s.customBgColor or defaults.customBgColor
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    if PP then PP.DisablePixelSnap(bg) end
    d.bg = bg

    -- Health bar
    local health = CreateFrame("StatusBar", nil, button)
    health:SetFrameLevel(button:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    local texPath = ResolveHealthTexture()
    health:SetStatusBarTexture(texPath)
    health:GetStatusBarTexture():SetHorizTile(false)
    if PP then PP.DisablePixelSnap(health) end
    -- Fill axis + inversion. StyleButton runs before d._isParty is set, so these use
    -- the raid values; ReanchorAbsorbToFill re-resolves both against the button's real
    -- settings source each update.
    ns.RF_ApplyHealthOrientation(health, s)
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    -- Pre-paint tint: a StatusBar texture renders WHITE (default vertex
    -- color) until the first content paint assigns the real class/reaction
    -- color a few frames after login (the styling drain). Start dark so the
    -- loading shell reads as calm empty frames instead of a flat white flash.
    health:SetStatusBarColor(0.12, 0.12, 0.12)
    d.health = health

    -- Full-height anchor reference for Uniform Icon Anchoring: top tracks the health bar (so the
    -- Top Name Bar inset carries over), bottom pins to the button -- exactly where the health bar
    -- sits with no power bar. ns.RF_AnchorHost swaps decorations onto it; _euiHealth points back
    -- for the few sites that must hug the real bar (full-overlay BM bars).
    d.uniformRef = CreateFrame("Frame", nil, button)
    d.uniformRef:SetFrameLevel(health:GetFrameLevel())
    d.uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    d.uniformRef:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = d.uniformRef
    d.uniformRef._euiHealth = health

    -- Power bar: ALWAYS created, hidden, anchored to the button bottom for pixel alignment;
    -- UpdateButton's per-role gate shows/fills it. Unconditional creation is what lets a
    -- power-OFF login profile swap into a power-ON one.
    do
        local power = CreateFrame("StatusBar", nil, button)
        power:SetFrameLevel(button:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(texPath)
        power:GetStatusBarTexture():SetHorizTile(false)
        if PP then PP.DisablePixelSnap(power) end
        power:SetMinMaxValues(0, 1)
        power:SetValue(1)
        -- Pre-paint tint (see the health bar note above).
        power:SetStatusBarColor(0.12, 0.12, 0.12)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
        if PP then PP.DisablePixelSnap(pwBg) end
        d.power = power
        d.powerBg = pwBg

        -- Power border frame
        local pwBdrFrame = CreateFrame("Frame", nil, button)
        pwBdrFrame:SetAllPoints(power)
        pwBdrFrame:SetFrameLevel(power:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(pwBdrFrame, 0, 0, 0, 1, 1) end
        d.powerBorderFrame = pwBdrFrame

        -- Start hidden; UpdateButton shows it per role (wasShown=false there plain-snaps the first fill, no interpolation).
        power:Hide()
        pwBdrFrame:Hide()
    end

    -- Top Name Bar: ALWAYS created, hidden. The layout/refresh pass sizes, reserves and shows it from settings; UpdateButton sets the text.
    do
        local tnb = CreateFrame("Frame", nil, button)
        tnb:SetFrameLevel(button:GetFrameLevel() + 4)
        tnb:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        tnb:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        tnb:SetHeight(PixelSnap(s.topNameBarHeight or 20))
        local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
        tnbBg:SetAllPoints()
        if PP then PP.DisablePixelSnap(tnbBg) end
        local tnbText = tnb:CreateFontString(nil, "OVERLAY")
        ApplyFont(tnbText, s.topNameBarTextSize or 11)
        tnbText:SetWordWrap(false)
        d.topNameBar = tnb
        d.topNameBarBg = tnbBg
        d.topNameBarText = tnbText
        tnb:Hide()
    end


    -- Absorb shields
    CreateAbsorbBar(button, health)

    -- Border frame
    local bdrFrame = CreateFrame("Frame", nil, button)
    bdrFrame:SetAllPoints(button)
    bdrFrame:SetFrameLevel(button:GetFrameLevel() + 8)
    d.borderFrame = bdrFrame
    -- Styled via EllesmereUI.ApplyBorderStyle (PP or textured/SharedMedia) in UpdateBorder.
    -- Hover/Target are color states recolored onto this single border, not separate frames.

    -- Threat border
    local threatFrame = CreateFrame("Frame", nil, button)
    threatFrame:SetAllPoints(button)
    threatFrame:SetFrameLevel(button:GetFrameLevel() + 10)
    threatFrame:Hide()
    d.threatFrame = threatFrame
    if PP then PP.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Party Frames kit (the stock portrait party frame, latched): built here,
    -- before every anchor closure below and before the aura containers, so
    -- each of them takes the kit's host and spots from its first call.
    if d._isParty and ns.RF_PartyKit() then
        ns.RF_KitBuild(button, d, health, d.power, bdrFrame)
    end

    -- Text carrier: name + health text in the text band (ns.LVL_TEXT) -- above every border incl. the raise, below the aura band.
    local textCarrier = CreateFrame("Frame", nil, button)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(button:GetFrameLevel() + ns.LVL_TEXT)
    -- Kept for Power Text, whose FontString is built on it only when a mode first needs it.
    d.textCarrier = textCarrier

    -- Name text
    local nameFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(nameFS, s.nameSize or 10)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(false)
    d.nameText = nameFS

    -- Health deficit text
    local healthFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healthFS, s.healthTextSize or 9)
    healthFS:SetTextColor(1, 1, 1, 0.9)
    d.healthText = healthFS

    local function AnchorHealthText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_BarHost(health, s)   -- Uniform Icon Anchoring host swap / kit bar
        healthFS:ClearAllPoints()
        local pos = s.healthTextPosition or "center"
        local ox = s.healthTextOffsetX or 0
        local oy = s.healthTextOffsetY or 0
        healthFS:SetWidth(d.kitG and d.kitG.health.w or (s.frameWidth or 72) * 0.75)
        healthFS:SetHeight(0)
        if pos == "topleft" then
            healthFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
            healthFS:SetJustifyH("LEFT"); healthFS:SetJustifyV("TOP")
        elseif pos == "top" then
            healthFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
            healthFS:SetJustifyH("CENTER"); healthFS:SetJustifyV("TOP")
        elseif pos == "topright" then
            healthFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
            healthFS:SetJustifyH("RIGHT"); healthFS:SetJustifyV("TOP")
        elseif pos == "left" then
            healthFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
            healthFS:SetJustifyH("LEFT"); healthFS:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            healthFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
            healthFS:SetJustifyH("RIGHT"); healthFS:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            healthFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
            healthFS:SetJustifyH("LEFT"); healthFS:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            healthFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
            healthFS:SetJustifyH("CENTER"); healthFS:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            healthFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            healthFS:SetJustifyH("RIGHT"); healthFS:SetJustifyV("BOTTOM")
        else -- "center"
            healthFS:SetPoint("CENTER", health, "CENTER", ox, oy)
            healthFS:SetJustifyH("CENTER"); healthFS:SetJustifyV("MIDDLE")
        end
        local txt = healthFS:GetText()
        healthFS:SetText("")
        healthFS:SetText(txt or "")
    end
    AnchorHealthText()
    d.AnchorHealthText = AnchorHealthText

    -- Heal absorb text (1:1 with health text; independent position/size/color).
    local healAbsorbFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healAbsorbFS, s.healAbsorbTextSize or 9)
    healAbsorbFS:SetWordWrap(false)
    d.healAbsorbText = healAbsorbFS
    local function AnchorHealAbsorbText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_BarHost(health, s)   -- Uniform Icon Anchoring host swap / kit bar
        ns.AnchorRFText(healAbsorbFS, health, s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0,
            d.kitG and d.kitG.health.w or (s.frameWidth or 72) * 0.75)
    end
    AnchorHealAbsorbText()
    d.AnchorHealAbsorbText = AnchorHealAbsorbText

    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color).
    -- Party Frames kit: in the text band, so the Classic art (drawn over the
    -- bars) never covers it; it still anchors to the kit health bar.
    local statusFS = (d.kit and textCarrier or health):CreateFontString(nil, "OVERLAY")
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(stc.r, stc.g, stc.b)
    statusFS:Hide()
    d.statusText = statusFS

    local function AnchorStatusText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_BarHost(health, s)   -- Uniform Icon Anchoring host swap / kit bar
        statusFS:ClearAllPoints()
        local pos = s.statusTextPosition or "center"
        local ox = s.statusTextOffsetX or 0
        local oy = s.statusTextOffsetY or 0
        if pos == "topleft" then
            statusFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif pos == "top" then
            statusFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif pos == "topright" then
            statusFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif pos == "left" then
            statusFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            statusFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif pos == "bottomleft" then
            statusFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif pos == "bottom" then
            statusFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif pos == "bottomright" then
            statusFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            statusFS:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorStatusText()
    d.AnchorStatusText = AnchorStatusText

    -- Role icon. Carrier sits in the text band (ns.LVL_AURA - 1 = ns.LVL_TEXT): above every border incl. the raise, auras still over it.
    -- Level is owned by AnchorRoleIcon (live-resolves the "Show Behind Border" option); this is just the initial value.
    local roleCarrier = CreateFrame("Frame", nil, button)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)
    roleIcon:Hide()
    d.roleIcon = roleIcon

    local function AnchorRoleIcon()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        -- The normal textured border is +8, so the enabled carrier must sit below it.
        roleCarrier:SetFrameLevel(button:GetFrameLevel()
            + (s.roleIconBehindBorder and 7 or (ns.LVL_AURA - 1)))
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        roleIcon:ClearAllPoints()
        -- Party Frames kit: the stock spot plus the user's offsets.
        if d.kitG then
            ns.RF_KitSpot(d.kitG.role, roleIcon, button, s.roleIconOffsetX, s.roleIconOffsetY)
            return
        end
        -- The position key uppercases directly to a valid anchor point, so all
        -- 9 positions resolve like the Marker Position dropdown.
        local pos = (s.roleIconPosition or "bottomleft"):upper()
        roleIcon:SetPoint(pos, health, pos, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
    end
    AnchorRoleIcon()
    d.AnchorRoleIcon = AnchorRoleIcon

    -- Marker carrier: above the frame border (incl. the hover/target raise) so the raid marker renders on top, not clipped behind it.
    local markerCarrier = CreateFrame("Frame", nil, button)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(button:GetFrameLevel() + ns.LVL_MARKER)

    -- Leader/assistant icon. Own host frame (strata/level contract in ns.ApplyLeaderStrata) --
    -- NOT the marker carrier, whose high level keeps the raid marker always on top. Parented to
    -- the button so it tracks the frame; SetAllPoints(health) anchors it to the health bar.
    d.leaderHost = CreateFrame("Frame", nil, button)
    d.leaderHost:SetAllPoints(health)
    ns.ApplyLeaderStrata(d.leaderHost)

    local leaderIcon = d.leaderHost:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
    leaderIcon:Hide()
    d.leaderIcon = leaderIcon
    -- Party Frames kit: the stock spot (re-seated by the party reload pass).
    if d.kitG then ns.RF_KitLeader(d, LiveS()) end

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(s.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidMarker:Hide()
    d.raidMarker = raidMarker

    local function AnchorRaidMarker()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        raidMarker:ClearAllPoints()
        local pos = s.raidMarkerPosition or "center"
        local ox = s.raidMarkerOffsetX or 0
        local oy = s.raidMarkerOffsetY or 0
        if pos == "topleft" then
            raidMarker:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif pos == "top" then
            raidMarker:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif pos == "topright" then
            raidMarker:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif pos == "left" then
            raidMarker:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            raidMarker:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif pos == "bottomleft" then
            raidMarker:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif pos == "bottom" then
            raidMarker:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif pos == "bottomright" then
            raidMarker:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            raidMarker:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorRaidMarker()
    d.AnchorRaidMarker = AnchorRaidMarker

    -- Ready check icon (shared with incoming-summon / incoming-rez; above name text)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(s.readyCheckSize or 20), PixelSnap(s.readyCheckSize or 20))
    readyCheck:Hide()
    d.readyCheck = readyCheck

    local function AnchorReadyCheck()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        readyCheck:ClearAllPoints()
        local pos = s.readyCheckPosition or "center"
        local ox = s.readyCheckOffsetX or 0
        local oy = s.readyCheckOffsetY or 0
        -- Party Frames kit: centred on the portrait, as stock.
        if d.kitG and d.kitPortrait then
            ns.RF_KitSpot(d.kitG.rc, readyCheck, d.kitPortrait, ox, oy)
            return
        end
        if pos == "topleft" then
            readyCheck:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif pos == "top" then
            readyCheck:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif pos == "topright" then
            readyCheck:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif pos == "left" then
            readyCheck:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            readyCheck:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif pos == "bottomleft" then
            readyCheck:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif pos == "bottom" then
            readyCheck:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif pos == "bottomright" then
            readyCheck:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            readyCheck:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorReadyCheck()
    d.AnchorReadyCheck = AnchorReadyCheck

    -- Combat icon (marker carrier, above the border): members currently affecting combat; 9-position anchor mirrors the role icon.
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    local ciSz = PixelSnap(s.combatIndicatorSize or 16)
    combatIcon:SetSize(ciSz, ciSz)
    combatIcon:Hide()
    d.combatIcon = combatIcon

    local function AnchorCombatIcon()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        combatIcon:ClearAllPoints()
        local pos = (s.combatIndicatorPosition or "right"):upper()
        combatIcon:SetPoint(pos, health, pos, s.combatIndicatorOffsetX or 0, s.combatIndicatorOffsetY or 0)
    end
    AnchorCombatIcon()
    d.AnchorCombatIcon = AnchorCombatIcon

    -- Anchor name text: width-constrained region, position via a single anchor; JustifyH/V aligns within it.
    local function AnchorNameText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        -- Text band level, re-applied on every reload; BEFORE the name-hidden early return because
        -- health text shares this carrier. Default sits under the aura band (ns.LVL_TEXT); "Show
        -- Above Icons" (name cog) lifts it above the band's children (+6 clears each aura unit's
        -- +1..+5), still below the marker carrier.
        textCarrier:SetFrameLevel(button:GetFrameLevel()
            + (s.nameTextAboveIcons and (ns.LVL_AURA + 6) or ns.LVL_TEXT))
        nameFS:ClearAllPoints()
        local pos = s.namePosition or "center"
        -- Party Frames kit: the stock name spot and width plus the user's
        -- offsets ("None" still hides it; the kit has no Top Name Bar).
        local g = d.kitG
        if g then
            if pos == "none" then nameFS:Hide(); return end
            nameFS:Show()
            nameFS:SetWidth(g.name.w)
            nameFS:SetHeight(0)
            ns.RF_KitSpot(g.name, nameFS, button, s.nameOffsetX, s.nameOffsetY)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV(g.name.jv)
            local txt = nameFS:GetText()
            nameFS:SetText("")
            nameFS:SetText(txt or "")
            return
        end
        -- Top Name Bar enabled: it owns the unit name, suppress the in-frame name.
        if pos == "none" or s.topNameBarEnabled then
            nameFS:Hide()
            return
        end
        nameFS:Show()
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        nameFS:SetWidth((s.frameWidth or 72) * ns.RF_NAME_WIDTH_FRACTION)
        nameFS:SetHeight(0)
        if pos == "topleft" then
            nameFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("TOP")
        elseif pos == "top" then
            nameFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("TOP")
        elseif pos == "topright" then
            nameFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("TOP")
        elseif pos == "left" then
            nameFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            nameFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            nameFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            nameFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            nameFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("BOTTOM")
        else -- "center"
            nameFS:SetPoint("CENTER", health, "CENTER", ox, oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        local txt = nameFS:GetText()
        nameFS:SetText("")
        nameFS:SetText(txt or "")
    end
    AnchorNameText()
    d.AnchorNameText = AnchorNameText

    -- Raise the border above neighbors while hovered/targeted (or recolored for aggro): buttons share a frame level, so with
    -- small/negative Frame Spacing a neighbor's border would cover this frame's highlight.
    -- Highlight states bump it up, normal restores the base level. The PP container's level is
    -- fixed at creation, so it must be moved explicitly (borderFrame alone won't move it).
    local function ApplyBorderLevel(raised, s)
        if not (PP and d.borderFrame) then return end
        local pl = button:GetFrameLevel()
        -- Under a stock style the EllesmereUI border is stood down, so Show
        -- Behind has nothing to lower (the hover border must stay on top).
        -- Resolved LIVE like UpdateBorder (the caller passes its own LiveS()), so a
        -- party that keeps its own Show Behind (and the Color Custom Borders copy that
        -- follows it) stays in step.
        s = s or LiveS()
        local lvl = (s.borderBehind and not d.stockEdge and not d.kit) and math.max(0, pl - 1)
            or (pl + (raised and ns.LVL_RAISE or 8))
        -- Runs on hover/target transitions and restyles: skip the SetFrameLevel calls unless
        -- the level actually changes -- the common case is two getters.
        local container = PP.GetBorders(d.borderFrame)
        if d.borderFrame:GetFrameLevel() == lvl
           and (not container or container:GetFrameLevel() == lvl + 1) then
            return
        end
        d.borderFrame:SetFrameLevel(lvl)
        if container then container:SetFrameLevel(lvl + 1) end
        -- A textured style draws on a backdrop child levelled only at style time: carry
        -- it too, so the raise also clears the Color Custom Borders copies (base + 1).
        local bd = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[d.borderFrame]
        if bd then bd:SetFrameLevel(lvl) end
    end

    -- Recolor the single border for the current state: hover > target > aggro (Threat
    -- Borders' Color Custom Borders, flagged by ns.RF_PaintThreat) > normal. A borderless
    -- frame has nothing to recolor, so the highlight draws its own (ns.ApplyHighlightBorder).
    local function ApplyBorderColor()
        if not (PP and d.borderFrame) then return end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) so party overrides and profile swaps are honored.
        local s = LiveS()
        -- Party Frames kit: hover and target glow along the frame art.
        if d.kit then
            ApplyBorderLevel(false, s)
            ns.RF_KitHighlight(d, d.borderFrame, s, d._hovered and s.hoverBorderEnabled ~= false,
                d._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        -- Stock styles: the stock selection ring for the target, the hover
        -- border on the stood-down border frame.
        if d.stockEdge then
            local hover = d._hovered and s.hoverBorderEnabled ~= false
            ApplyBorderLevel(hover, s)
            ns.RF_StockHighlight(d, d.borderFrame, s, hover, d._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        local r, g, b, a
        local raised, hlSize, hlPx = false, nil, nil
        if d._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised, hlSize = true, s.hoverBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif d._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised, hlSize = true, s.targetBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif d._aggroBdr and s.threatCustomBorder == true and ns.RF_CustomBorderOn(s) then
            -- The threat color, raised like hover/target so it also covers the dispel
            -- Color Custom Borders copies (base + 9). Settings re-checked live: a
            -- restyle can run before the next threat paint clears the flag.
            r, g, b, a = 1, 0, 0, 1
            raised = true
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        ApplyBorderLevel(raised, s)
        if (s.borderSize or 1) <= 0 then
            ns.ApplyHighlightBorder(d.borderFrame, s, hlSize, r, g, b, a, hlPx)
            return
        end
        if hlSize then r, g, b = ns.RF_VisibleHighlight(s, r, g, b) end
        d.borderFrame._hlBorderSize = nil
        EllesmereUI.SetBorderStyleColor(d.borderFrame, r, g, b, a)
        if s.powerBorderMatchColor == true and d.powerBorderFrame and d.powerBorderFrame._powerArtMode == "divider" then
            ns.RF_ColorPowerDivider(d.powerBorderFrame, r, g, b, a)
        end
        if s.topNameBarDividerMatchColor == true and d.topNameBar and d.topNameBar._divider then
            ns.RF_ColorPowerDivider(d.topNameBar._divider, r, g, b, a)
        end
    end
    d.ApplyBorderColor = ApplyBorderColor

    -- Apply border (style/size/texture/offsets via shared ApplyBorderStyle,
    -- then recolor for state). "Show Behind" lowers it below the frame; else +8.
    local function UpdateBorder()
        if not (PP and d.borderFrame) then return end
        -- Re-called from Reload paths long after StyleButton: resolve LIVE (see LiveS note).
        local s = LiveS()
        local bs = s.borderSize or 1
        local bc = s.borderColor or { r = 0, g = 0, b = 0 }
        local texKey = s.borderTexture or "solid"
        local pl = button:GetFrameLevel()
        -- Stock styles: the EllesmereUI border stands down for the stock edge
        -- (for the art under the Party Frames kit).
        if d.kit then
            d.borderFrame:SetFrameLevel(pl + 8)
            EllesmereUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            d.borderFrame._hlBorderSize = nil
            ApplyBorderColor()
            EllesmereUI.RoundCorners(button, 0)
            return
        end
        if d.stockEdge then
            d.borderFrame:SetFrameLevel(pl + 8)
            EllesmereUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            d.borderFrame._hlBorderSize = nil
            ns.RF_StockSeat(d)
            ApplyBorderColor()
            EllesmereUI.RoundCorners(button, 0)
            return
        end
        d.borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        EllesmereUI.ApplyBorderStyle(d.borderFrame, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
            texKey, s.borderTextureOffset, s.borderTextureOffsetY,
            s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs, nil,
            EllesmereUI.BorderPx(s.borderSizePx, bs, texKey))
        ApplyBorderColor()
        -- Rounded corners (EllesmereUI_RoundedCorners.lua; nothing at radius 0).
        -- The power border rides in the body so its edge strips round too.
        local radius = s.cornerRadius or 0
        if radius > 0 then
            EllesmereUI.RoundCorners(button, radius, {
                roots = { d.health, d.power, d.topNameBar, d.powerBorderFrame },
                textures = { d.bg },
                border = d.borderFrame, style = texKey, corners = s.cornerMask,
            })
        else
            EllesmereUI.RoundCorners(button, 0)
        end
    end
    if ns.RF_Stock() and not d.kit then ns.RF_StockBuild(button, d, d.power) end
    UpdateBorder()
    d.UpdateBorder = UpdateBorder

    -- Apply power border
    local function UpdatePowerBorder(force)
        -- Party Frames kit: the mana bar sits in the art's own track.
        if d.kit then
            ns.RF_ClearPowerBorderArt(d.powerBorderFrame)
            if d.powerBorderFrame then d.powerBorderFrame:Hide() end
            return
        end
        -- No-op while the power bar is hidden: the border frame always exists and unconditional
        -- callers must not draw over a hidden bar. UpdateButton calls this AFTER power:Show().
        if not PP or not d.powerBorderFrame then return end
        if d.power and not d.power:IsShown() then
            ns.RF_ClearPowerBorderArt(d.powerBorderFrame)
            d.powerBorderFrame:Hide()
            return
        end
        -- Classic WoW UI: the stock health/power divider in place of the power border.
        if d.stockDiv then
            ns.RF_ClearPowerBorderArt(d.powerBorderFrame)
            d.powerBorderFrame:Hide()
            ns.RF_StockDivider(d)
            return
        end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) -- a captured `s` misses party overrides and profile swaps.
        local s = LiveS()
        if s.powerBorderMatchFrame == true or d.powerBorderFrame._powerArtKey then
            local handled, refreshed = ns.RF_ApplyPowerBorderArt(d.powerBorderFrame, s, force)
            if handled then
                if refreshed and s.powerBorderMatchColor == true and d.powerBorderFrame._powerArtMode == "divider" then ApplyBorderColor() end
                return
            end
        end
        local style = s.powerBorderStyle or "eui"
        if style == "eui" then
            -- EUI style: 1px divider, white at 20% opacity
            PP.UpdateBorder(d.powerBorderFrame, 1, 1, 1, 1, 0.2)
            d.powerBorderFrame:Show()
            local ppC = PP.GetBorders(d.powerBorderFrame)
            if ppC then
                if ppC._bottom then ppC._bottom:SetAlpha(0) end
                if ppC._left then ppC._left:SetAlpha(0) end
                if ppC._right then ppC._right:SetAlpha(0) end
                if ppC._top then ppC._top:SetAlpha(0.2) end
            end
            return
        end
        local bs = s.powerBorderSize or 1
        if bs <= 0 then
            d.powerBorderFrame:Hide()
            return
        end
        local bc = s.powerBorderColor
        local ba = s.powerBorderAlpha or 1
        PP.UpdateBorder(d.powerBorderFrame, bs, bc.r, bc.g, bc.b, ba)
        d.powerBorderFrame:Show()
        local ppC = PP.GetBorders(d.powerBorderFrame)
        if ppC then
            if style == "divider" then
                if ppC._bottom then ppC._bottom:SetAlpha(0) end
                if ppC._left then ppC._left:SetAlpha(0) end
                if ppC._right then ppC._right:SetAlpha(0) end
                if ppC._top then ppC._top:SetAlpha(ba) end
            else -- "border"
                if ppC._top then ppC._top:SetAlpha(ba) end
                if ppC._bottom then ppC._bottom:SetAlpha(ba) end
                if ppC._left then ppC._left:SetAlpha(ba) end
                if ppC._right then ppC._right:SetAlpha(ba) end
            end
        end
    end
    UpdatePowerBorder()
    d.UpdatePowerBorder = UpdatePowerBorder

    -- Tooltip handlers
    button:HookScript("OnEnter", function(self)
        local fd = GetFFD(self)
        fd._hovered = true
        if fd.ApplyBorderColor then fd.ApplyBorderColor() end
        -- Aura icons enable mouse and propagate motion up to this button, so entering an icon fires
        -- its OnEnter (aura tooltip) then bubbles here, clobbering it with the unit tooltip. Bail
        -- when the cursor is over one of our aura icons (stashed _tipIID).
        local foci = GetMouseFoci()
        if foci then
            for _, mf in ipairs(foci) do
                if mf ~= self and mf._tipIID ~= nil then return end
            end
        end
        -- Unit-tooltip gating: see ns.RaidFrameTooltipAllowed. It reads through the party-aware
        -- proxy, NOT raw db.profile -- else party_<key> overrides from a custom party
        -- "Range & Tooltip" section are never seen.
        if not ns.RaidFrameTooltipAllowed(self) then return end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            -- Populate with a freshly-built clean literal token (GUID-matched) rather than the
            -- secure unit attribute: a literal "raidN"/"partyN"/"player" string lacks the
            -- secure-frame origin that makes GameTooltip:GetUnit() return a secret, so external
            -- tooltip addons can resolve the unit. Falls back to the attribute if no clean token.
            local tip, g = u, UnitGUID(u)
            if g and not (issecretvalue and issecretvalue(g)) then
                if UnitGUID("player") == g then
                    tip = "player"
                elseif IsInRaid() then
                    for i = 1, GetNumGroupMembers() do
                        local tk = "raid" .. i
                        local tg = UnitGUID(tk)
                        if tg and not (issecretvalue and issecretvalue(tg)) and tg == g then tip = tk; break end
                    end
                else
                    for i = 1, GetNumSubgroupMembers() do
                        local tk = "party" .. i
                        local tg = UnitGUID(tk)
                        if tg and not (issecretvalue and issecretvalue(tg)) and tg == g then tip = tk; break end
                    end
                end
            end
            GameTooltip:SetUnit(tip)
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function(self)
        local fd = GetFFD(self)
        fd._hovered = false
        if fd.ApplyBorderColor then fd.ApplyBorderColor() end
        GameTooltip:Hide()
    end)

    -- Private auras: re-anchor whenever the secure header reassigns this button's unit. The engine
    -- drops private-aura anchors on unit reassignment (join/leave, sort, zone-in) even when the
    -- token string is unchanged, so the roster-event RebuildUnitMap path (which re-registers only
    -- when the token CHANGES) can leave the anchor dropped. OnAttributeChanged is the reliable
    -- per-button signal for exactly those reassignments. HookScript (NEVER SetScript) preserves the
    -- secure header's own handlers; helpers go through ns because they are defined later.
    button:HookScript("OnAttributeChanged", function(self, name)
        if name ~= "unit" then return end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            -- Repaint + remap the instant the header (re)assigns this button, so a late assignment
            -- landing after the roster-timer rebuild can never leave it blank or route live events
            -- to a stale button.
            local d = GetFFD(self)
            -- Extra Frames duplicates never enter the real routing maps (one button per unit);
            -- XF_Apply owns ns._xfUnitToButton. The repaint/range work below is 1:1.
            -- A set flagged hidden stays out of the maps: its headers can still
            -- re-process until the visibility driver hides them (the next tick), and
            -- a hidden button would win the routing over the set actually shown.
            if d._isExtra then
                -- map owned by XF_Apply
            elseif d._isParty then
                if ns._partyFramesVisible then ns._partyUnitToButton[u] = self end
            elseif ns._raidFramesVisible then unitToButton[u] = self end
            -- The secure header re-sets EVERY child's unit on EVERY re-process (each
            -- roster/name event, each sort attribute change), so most fires are a
            -- same-occupant re-confirm: same token AND same person as the last full
            -- paint. Nothing on the button changed -- its own unit events kept it
            -- current -- so only the routing write above and the container's
            -- assist gate run; the roster timer refreshes roster-derived state
            -- (leader/role/power layout) for unchanged occupants. A secret guid
            -- (never memoized) or a cleared/unstyled button takes the full path.
            local guid = UnitGUID(u)
            if issecretvalue(guid) then guid = nil end
            if guid and d._lastGuid == guid and d._lastUnit == u then
                if ns.RFC_OnUnitAssigned then ns.RFC_OnUnitAssigned(self, d, u) end
                return
            end
            -- Identity caches (class token, power type) drop on a real assignment:
            -- a different person can land on this button under the same token, and
            -- those derive again on the next tick for one cheap read each.
            d._clsTok = nil
            d._pwType = nil
            d._rmhPct = nil
            -- Drop the power-hide cache only on a token change -- else it forces an
            -- unconditional Show/Hide/SetHeight repaint, reintroducing the pop the
            -- deferred-power fix removed.
            if d._lastUnit ~= u then
                d._lastUnit = u
                d._appliedHidePower = nil
            end
            d._lastGuid = d.styled and guid or nil
            -- A ping marker belongs to the previous occupant; its pin-removed edge
            -- can no longer reach this button once the person moved.
            if d.pingFrame then d.pingFrame:Hide() end
            -- Containers first: the legacy refresh below still has restriction-era failure modes,
            -- and an error there must not starve the container of its unit assignment.
            if ns.RFC_OnUnitAssigned then ns.RFC_OnUnitAssigned(self, d, u) end
            -- Party Frames kit / party portrait: the new occupant's portrait
            -- (ahead of the legacy refresh for the same reason as the containers).
            if d.kitPortrait or d.pt then ns.RF_PtPaint(d, u, "UnitChanged") end
            if ns._RefreshAssignedButton then ns._RefreshAssignedButton(self, u) end
            if ns._UpdateButtonRange then ns._UpdateButtonRange(u, self) end
        else
            -- Cleared (button hidden by the header) or not yet resolvable: forget the
            -- painted occupant so the next assignment always takes the full path.
            GetFFD(self)._lastGuid = nil
        end
    end)

    -- 12.1 aura containers (container shell creation is combat-legal since
    -- 68914, so this rides the deferred styling pass with the rest of the body)
    if ns.RFC_SetupButton then
        ns.RFC_SetupButton(button, health, d)
    end
end

-------------------------------------------------------------------------------
--  Window-phase secure styling: everything on a fresh unit button that is
--  combat-blocked or writes secure state -- the size plus the click / ping /
--  click-cast tail (92 WrapScripts across the fleet live in CC_RegisterFrame).
--  Runs inside the login loading-screen window for every pre-spawned button;
--  the insecure visual body (StyleButton) runs in its own deferred
--  post-screen execution so the suite's shared login watchdog budget never
--  pays for it. Idempotent via d.securestyled, mirroring d.styled.
-------------------------------------------------------------------------------
ns._StyleButtonSecure = function(button)
    local d = GetFFD(button)
    if d.securestyled then return end
    d.securestyled = true
    local s = db.profile
    -- Party buttons take the party box (their creator stamps _isParty
    -- first); everything else the raid size.
    if d._isParty then
        local pw, ph = ns.RF_PartyDims(s)
        button:SetSize(PixelSnap(pw), PixelSnap(ph))
    else
        button:SetSize(PixelSnap(s.frameWidth or 72), PixelSnap(s.frameHeight or 46))
    end

    -- Secure click: left=target, right=menu
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type1", "target")
    -- Wildcard fallback so left-click target survives if the click-cast engine later clears type1.
    button:SetAttribute("*type1", "target")
    -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton
    -- proxy so the menu (and protected items like Set Focus) works without taint (*type2 = "click").
    if EllesmereUI.AttachSecureUnitMenu then
        EllesmereUI.AttachSecureUnitMenu(button)
    else
        button:SetAttribute("type2", "togglemenu")
        button:SetAttribute("*type2", "togglemenu")
    end

    -- Hover ping support, MIXIN-PURE: Blizzard's mixin methods run untouched
    -- (its GetTargetInfo resolves the unit from our "unit" attribute, which
    -- tracks the current occupant across sorts). Never override
    -- GetIsPingable/GetTargetInfo -- addon Lua in the ping path makes a
    -- secret GUID "inaccessible" to PingManager's securecopy (hard error +
    -- wedged listener), and a secrecy-guarded override deadens pings in all
    -- restricted content (both field-failed 2026-08-20). Writes are safe --
    -- our own spawned secure template, once per button, out of combat.
    if PingableType_UnitFrameMixin then
        Mixin(button, PingableType_UnitFrameMixin)
        button:SetAttribute("ping-receiver", true)
    end

    -- Register for click-casting (EUI built-in system)
    if ns.CC_RegisterFrame then
        ns.CC_RegisterFrame(button)
    elseif ClickCastFrames then
        ClickCastFrames[button] = true
    end
end

I.StyleButton = StyleButton
I.broken = false
