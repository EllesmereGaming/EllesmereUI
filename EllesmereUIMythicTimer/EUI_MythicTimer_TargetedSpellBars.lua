if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_TargetedSpellBars.lua
--  Targeted Spell Bars (Mythic+ Tools): one movable group of cast bars, one per
--  enemy nameplate currently casting -- a replica of the nameplate cast display
--  (spell name, spell target, timer) collected in one place so every active
--  cast reads at a glance. Optional interrupt awareness (kick-ready tint,
--  uninterruptible wash, important-cast tint/glow), out-of-interrupt-range
--  fade, and raid target markers, all opt-in and off by default.
--
--  Zero cost while disabled: no events are registered and no frames are built
--  until the feature is enabled. All cast reads follow the nameplate module's
--  secret discipline: type() existence checks, duration objects into
--  SetTimerDuration, secret strings straight into SetText, never a Lua branch
--  on a secret value.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local db  -- Lite DB handle, handed over by ns.TSB_OnEnable

local function Cfg()
    local p = db and db.profile
    return p and p.tsb
end

--------------------------------------------------------------------------------
--  Fonts: module-wide family/outline/shadow (surface key "mythicTimer"), only
--  per-text sizes are settings -- same contract as every other bar surface.
--------------------------------------------------------------------------------
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function SetFSFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("mythicTimer")) or FONT_FALLBACK
    local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("mythicTimer")) or ""
    local useShadow = EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("mythicTimer")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, useShadow) end
    fs:SetFont(path, size, outline)
end

--------------------------------------------------------------------------------
--  Shared engines consumed read-only (core addon, loaded before this module).
--------------------------------------------------------------------------------
local GetActiveKickSpell = EllesmereUI.GetActiveKickSpell
local ComputeCastBarTint = EllesmereUI.ComputeCastBarTint
local Glows = EllesmereUI.Glows

-- Raid marker sheet texcoords (4x4 grid), same layout as EllesmereUIRaidFrames.
local RAID_MARKER_TEXCOORDS = {
    [1] = { 0,    0.25, 0,    0.25 }, -- Star
    [2] = { 0.25, 0.5,  0,    0.25 }, -- Circle
    [3] = { 0.5,  0.75, 0,    0.25 }, -- Diamond
    [4] = { 0.75, 1,    0,    0.25 }, -- Triangle
    [5] = { 0,    0.25, 0.25, 0.5  }, -- Moon
    [6] = { 0.25, 0.5,  0.25, 0.5  }, -- Square
    [7] = { 0.5,  0.75, 0.25, 0.5  }, -- Cross
    [8] = { 0.75, 1,    0.25, 0.5  }, -- Skull
}

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local container            -- anchor frame the unlock mover drags; built lazily
local bars = {}             -- frame pool (holder frames, reused forever)
local shown = {}            -- active entries in display order
local unitEntry = {}        -- unit token -> entry while its bar is shown
local plateUnits = {}       -- unit token -> true while its nameplate exists
local active = false        -- events registered / feature live
local previewOn = false     -- sample bars forced on (options eyeball / unlock)
local timerTicker           -- shared 10Hz text ticker, self-stops when idle
local slowAccum = 0         -- 10Hz tick counter driving the 0.2s poll pass
local styleGen = 0          -- bumped by TSB_Refresh; O3 restyle-on-stale stamp
local anyCastDropped = false -- true only when the maxBars cap actually dropped a cast
local whereActive = false   -- location/combat watcher registered (tied to cfg.enabled only)

local DEFAULT_X, DEFAULT_Y = -340, 60

--------------------------------------------------------------------------------
--  Where to Show: content-type gate (positive filter, see WhereShows). Runs
--  independently of the nameplate-tracking lifecycle below -- entering or
--  leaving a matching zone must be able to (de)activate the group even while
--  the bucket the player is currently in is excluded, so this watcher stays
--  armed for as long as the feature is enabled, never tied to `active`.
--------------------------------------------------------------------------------
local function CurrentWhereBucket()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return "dungeon_mythic"
    end
    local _, iType, diffID = GetInstanceInfo()
    diffID = tonumber(diffID) or 0
    if iType == "party" then
        if diffID == 23 or diffID == 8 then return "dungeon_mythic" end
        if diffID == 2 or diffID == 1 or diffID == 205 then return "dungeon_nonmythic" end
        if diffID == 24 then return "timewalking" end
    elseif iType == "raid" then
        if diffID == 16 or diffID == 233 then return "raid_mythic" end
        if diffID == 15 or diffID == 6 then return "raid_heroic" end
        if diffID == 14 or diffID == 3 or diffID == 4 or diffID == 5
            or diffID == 17 or diffID == 7 then return "raid_normal_lfr" end
        if diffID == 33 then return "timewalking" end
    elseif iType == "scenario" then
        if diffID == 208 then return "delve" end
    end
    if IsInInstance and not IsInInstance() then return "open_world" end
    return nil -- unmapped (PvP/arena/etc.) -- always shows, matching AuraBuffReminders
end

-- Positive filter: nothing selected = no filter (bars show everywhere, the
-- original behavior). Selected location buckets limit WHERE, the two combat
-- entries limit WHEN, and the two groups AND together. Unmapped content
-- (PvP, arena) never hides.
local LOCATION_KEYS = {
    "open_world", "raid_mythic", "raid_heroic", "raid_normal_lfr",
    "dungeon_mythic", "dungeon_nonmythic", "timewalking", "delve",
}

local function WhereShows(whereToShow)
    if not whereToShow or not next(whereToShow) then return true end
    local wantIn  = whereToShow.in_combat == true
    local wantOut = whereToShow.out_of_combat == true
    if wantIn ~= wantOut then
        local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
        if inCombat ~= wantIn then return false end
    end
    local anyLoc = false
    for i = 1, #LOCATION_KEYS do
        if whereToShow[LOCATION_KEYS[i]] == true then anyLoc = true; break end
    end
    if not anyLoc then return true end
    local bucket = CurrentWhereBucket()
    if not bucket then return true end
    return whereToShow[bucket] == true
end

-- Zone/combat edges only flip the group on or off (defined after Activate/
-- Deactivate); a full restyle belongs to settings writes, not combat entry.
local SyncWhereActive

local whereEvt = CreateFrame("Frame")
local WHERE_EVENTS = {
    "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}
whereEvt:SetScript("OnEvent", function() SyncWhereActive() end)

local function SetWhereWatcherActive(on)
    on = on and true or false
    if on == whereActive then return end
    whereActive = on
    if on then
        for i = 1, #WHERE_EVENTS do whereEvt:RegisterEvent(WHERE_EVENTS[i]) end
    else
        whereEvt:UnregisterAllEvents()
    end
end

--------------------------------------------------------------------------------
--  Container + position (unlock interchange = raw UIParent-logical center
--  delta, same contract as the timer frame -- scale division never leaves the
--  module's own SetPoint).
--------------------------------------------------------------------------------
local function ApplyContainerPosition()
    if not container then return end
    local cfg = Cfg()
    local pos = cfg and cfg.pos
    container:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        container:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    end
end

local function EnsureContainer()
    if container then return container end
    container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(240, 20)
    ApplyContainerPosition()
    return container
end

--------------------------------------------------------------------------------
--  Bar construction: holder > bg + icon + StatusBar fill + uninterruptible
--  overlay + raid marker + text zones. Built once per pool slot, restyled by
--  StyleBar.
--------------------------------------------------------------------------------
local function BuildBar()
    local holder = CreateFrame("Frame", nil, EnsureContainer())
    holder:Hide()

    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints(holder)

    holder.iconFrame = CreateFrame("Frame", nil, holder)
    holder.iconFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    holder.iconFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints(holder.iconFrame)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Icon/bar seam divider (opt-in). Rides its own frame above holder.sb:
    -- a texture on holder itself would draw under the StatusBar child.
    holder.overlayFrame = CreateFrame("Frame", nil, holder)
    holder.overlayFrame:SetAllPoints(holder)
    holder.overlayFrame:SetFrameLevel(holder:GetFrameLevel() + 5)
    holder.iconDivider = holder.overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    holder.iconDivider:Hide()

    holder.sb = CreateFrame("StatusBar", nil, holder)
    -- Placeholder fill: a StatusBar has NO texture object until one is set, and
    -- the fill-edge rider below (the uninterruptible overlay) would index nil
    -- on a bar that never reached StyleBar (TargetFocusBars carries the same
    -- guard, same reason).
    holder.sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    holder.sb:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 0, 0)
    holder.sb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    holder.sb:SetMinMaxValues(0, 1)
    holder.sb:SetValue(0)

    -- Uninterruptible grey wash: rides the fill texture, alpha-gated by the
    -- (possibly secret) protection flag via SetAlphaFromBoolean.
    holder.overlay = holder.sb:CreateTexture(nil, "ARTWORK", nil, 2)
    holder.overlay:SetAllPoints(holder.sb:GetStatusBarTexture())
    holder.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    holder.overlay:SetAlpha(0)

    -- Text zones ride a child frame so they draw above the fill and any border.
    holder.textFrame = CreateFrame("Frame", nil, holder.sb)
    holder.textFrame:SetAllPoints(holder.sb)

    -- Raid target marker, left of the spell name; hidden until a cast paints it.
    holder.marker = holder.textFrame:CreateTexture(nil, "OVERLAY")
    holder.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    holder.marker:Hide()

    -- Fonts applied at BUILD as well as in StyleBar: SetText on a fontless
    -- FontString errors, and build/paint ordering must not be load-bearing.
    holder.name = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.name:SetJustifyH("LEFT")
    holder.name:SetWordWrap(false)
    holder.name:SetMaxLines(1)
    SetFSFont(holder.name, 10)
    holder.target = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.target:SetJustifyH("RIGHT")
    holder.target:SetWordWrap(false)
    holder.target:SetMaxLines(1)
    SetFSFont(holder.target, 10)
    holder.timer = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.timer:SetJustifyH("RIGHT")
    holder.timer:SetWordWrap(false)
    holder.timer:SetMaxLines(1)
    SetFSFont(holder.timer, 10)

    return holder
end

local function AcquireBarFrame()
    for i = 1, #bars do
        if not bars[i]._tsbInUse then
            bars[i]._tsbInUse = true
            return bars[i]
        end
    end
    local b = BuildBar()
    bars[#bars + 1] = b
    b._tsbInUse = true
    return b
end

--------------------------------------------------------------------------------
--  Name anchoring: shared by StyleBar and the raid-marker paint pass, since
--  the name has to shift right while a marker is shown.
--------------------------------------------------------------------------------
local function AnchorName(holder, cfg, markerShown)
    local w = cfg.width or 240
    local h = cfg.height or 20
    local markerReserve = markerShown and ((cfg.raidMarkerSize or 14) + 2) or 0
    holder.name:ClearAllPoints()
    holder.name:SetPoint("LEFT", holder.sb, "LEFT", 4 + markerReserve + (cfg.nameX or 0), cfg.nameY or 0)
    local nameWidth = (w - h) * 0.48 - markerReserve
    if nameWidth < 1 then nameWidth = 1 end
    holder.name:SetWidth(nameWidth)
end

--------------------------------------------------------------------------------
--  Style pass: sizes, texture, colors, fonts, text layout. Runs on enable and
--  on any settings change (options call ns.TSB_Refresh), and once per bar the
--  first time it is used after a refresh (O3: StartCast skips this otherwise).
--------------------------------------------------------------------------------
local function StyleBar(holder, cfg)
    local w = cfg.width or 240
    local h = cfg.height or 20
    holder:SetSize(w, h)

    local bg = cfg.bgColor
    if bg then holder.bg:SetColorTexture(bg.r, bg.g, bg.b, bg.a or 0.45)
    else holder.bg:SetColorTexture(0, 0, 0, 0.45) end

    local showIcon = cfg.showIcon ~= false
    -- Hidden icon stays on the left so the bar keeps its full-width anchors.
    local iconOnRight = showIcon and cfg.iconOnRight
    holder.iconFrame:ClearAllPoints()
    if iconOnRight then
        holder.iconFrame:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
        holder.iconFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
        holder.iconFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.iconFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    end
    holder.iconFrame:SetWidth(showIcon and h or 0.001)
    holder.iconFrame:SetShown(showIcon)

    holder.sb:ClearAllPoints()
    if iconOnRight then
        holder.sb:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.sb:SetPoint("BOTTOMRIGHT", holder.iconFrame, "BOTTOMLEFT", 0, 0)
    else
        holder.sb:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 0, 0)
        holder.sb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    end

    local texPath = EllesmereUI.ResolveTexturePath
        and EllesmereUI.ResolveTexturePath(ns.barTextures, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
        or "Interface\\Buttons\\WHITE8x8"
    holder.sb:SetStatusBarTexture(texPath)
    local pp = EllesmereUI.PP
    if pp and pp.DisablePixelSnap then pp.DisablePixelSnap(holder.sb:GetStatusBarTexture()) end
    local c = cfg.barColor
    if c then holder.sb:SetStatusBarColor(c.r, c.g, c.b) end

    -- Fill texture re-mint: SetStatusBarTexture creates a NEW texture object
    -- every call, so the uninterruptible overlay must be re-pinned to it.
    holder.overlay:ClearAllPoints()
    holder.overlay:SetAllPoints(holder.sb:GetStatusBarTexture())
    local un = cfg.uninterruptible
    if un then holder.overlay:SetVertexColor(un.r, un.g, un.b) end

    -- Solid black border on the holder; size 0 removes it.
    local bsz = cfg.borderSize
    if bsz == nil then bsz = 1 end
    if pp and pp.CreateBorder then
        if bsz > 0 then
            if not holder._tsbBorder then
                holder._tsbBorder = true
                pp.CreateBorder(holder, 0, 0, 0, 1, bsz, "OVERLAY", 7)
            elseif pp.UpdateBorder then
                pp.UpdateBorder(holder, bsz)
            end
            if pp.ShowBorder then pp.ShowBorder(holder) end
        elseif holder._tsbBorder and pp.HideBorder then
            pp.HideBorder(holder)
        end
    end

    -- Optional icon/bar seam divider (opt-in "Show Icon Divider"), matching
    -- the border color so it reads as part of the same frame.
    if showIcon and cfg.showIconDivider then
        local des = holder:GetEffectiveScale()
        local onePixel = (pp and des > 0) and (pp.perfect / des) or ((pp and pp.mult) or 1)
        local dbs = bsz > 0 and bsz or 1
        holder.iconDivider:ClearAllPoints()
        holder.iconDivider:SetWidth(math.max(onePixel, math.floor(dbs + 0.5) * onePixel))
        if iconOnRight then
            holder.iconDivider:SetPoint("TOPRIGHT", holder.iconFrame, "TOPLEFT", 0, 0)
            holder.iconDivider:SetPoint("BOTTOMRIGHT", holder.iconFrame, "BOTTOMLEFT", 0, 0)
        else
            holder.iconDivider:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 0, 0)
            holder.iconDivider:SetPoint("BOTTOMLEFT", holder.iconFrame, "BOTTOMRIGHT", 0, 0)
        end
        holder.iconDivider:SetColorTexture(0, 0, 0, 1)
        holder.iconDivider:Show()
    else
        holder.iconDivider:Hide()
    end

    SetFSFont(holder.name, cfg.nameSize or 10)
    SetFSFont(holder.target, cfg.targetSize or 10)
    SetFSFont(holder.timer, cfg.timerSize or 10)

    local showTimer = cfg.showTimer ~= false
    local timerReserve = showTimer and ((cfg.timerSize or 10) * 2.2) or 0
    AnchorName(holder, cfg, holder.marker:IsShown())
    holder.timer:ClearAllPoints()
    holder.timer:SetPoint("RIGHT", holder.sb, "RIGHT", -3 + (cfg.timerX or 0), cfg.timerY or 0)
    holder.target:ClearAllPoints()
    holder.target:SetPoint("RIGHT", holder.sb, "RIGHT",
        -3 - timerReserve + (cfg.targetX or 0), cfg.targetY or 0)
    holder.target:SetWidth((w - h) * 0.40)

    -- Marker size/anchor; visibility and texcoords are per-cast (ApplyRaidMarker).
    local msz = cfg.raidMarkerSize or 14
    holder.marker:SetSize(msz, msz)
    holder.marker:ClearAllPoints()
    holder.marker:SetPoint("LEFT", holder.sb, "LEFT", 3, 0)

    holder.name:SetShown(cfg.showSpellName ~= false)
    holder.timer:SetShown(showTimer)
    -- target visibility is per-cast (hasTarget); the paint pass owns it

    holder._glowDirty = true -- size may have changed; the glow geometry is size-dependent
    holder._styleGen = styleGen
end

local function PositionBar(holder, slot, cfg)
    holder:ClearAllPoints()
    local off = (slot - 1) * ((cfg.height or 20) + (cfg.spacing or 4))
    if cfg.growUp then
        holder:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, off)
    else
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -off)
    end
end

local function Reflow()
    local cfg = Cfg()
    if not cfg then return end
    for i = 1, #shown do
        PositionBar(shown[i].bar, i, cfg)
    end
end

--------------------------------------------------------------------------------
--  Important-cast glow: routed through Glows.StartEngineGlow (the C-side
--  AnimationGroup path built for the 12.1 forbidden aura partition), so it
--  costs ZERO per-frame Lua regardless of how many bars glow -- unlike the
--  driver-ticked engines the nameplate module uses. Only styles with a
--  genuine C-side twin are offered (1/2/5/6/7); styles 3/4 silently remap
--  inside the engine and are left off the options dropdown.
--------------------------------------------------------------------------------
local function EnsureGlowOverlay(holder)
    if holder._glow then return holder._glow end
    local ov = CreateFrame("Frame", nil, holder.sb)
    ov:SetAllPoints(holder.sb)
    ov:SetFrameLevel(holder.sb:GetFrameLevel() + 5)
    ov:EnableMouse(false)
    holder._glow = ov
    return ov
end

local function ClearImportantGlow(holder)
    if holder._glowActive and holder._glow then
        if Glows then Glows.StopAllGlows(holder._glow) end
        holder._glow:SetAlpha(0)
        holder._glow:Hide()
        holder._glowActive = false
        holder._glowStyle = nil
    end
end

local function StartImportantGlowAnim(holder, cfg)
    local ov = EnsureGlowOverlay(holder)
    local style = cfg.importantGlowStyle or 1
    local c = cfg.importantGlowColor or { r = 1, g = 0.2, b = 0.2 }
    local n = cfg.importantGlowLines or 8
    local th = cfg.importantGlowThickness or 2
    local period = cfg.importantGlowSpeed or 4

    -- Dirty-check so the animation is not restarted on every cast event; only
    -- a real style/color/param/size change tears it down and re-plays it.
    if not holder._glowActive or holder._glowStyle ~= style
        or holder._glowR ~= c.r or holder._glowG ~= c.g or holder._glowB ~= c.b
        or holder._glowN ~= n or holder._glowTh ~= th or holder._glowPeriod ~= period
        or holder._glowDirty then
        holder._glowDirty = nil
        Glows.StopAllGlows(ov)
        local pW, pH = holder.sb:GetWidth(), holder.sb:GetHeight()
        if pW < 5 then pW = 100 end
        if pH < 5 then pH = 14 end
        Glows.StartEngineGlow(ov, style, pW, c.r, c.g, c.b, { N = n, th = th, period = period }, pH)
        holder._glowActive = true
        holder._glowStyle = style
        holder._glowR, holder._glowG, holder._glowB = c.r, c.g, c.b
        holder._glowN, holder._glowTh, holder._glowPeriod = n, th, period
    end
    ov:Show()
    return ov
end

-- e._important may be true / false / a SECRET boolean (C_Spell.IsSpellImportant
-- can return secret under restricted execution) -- only the issecretvalue()
-- branch below is allowed to touch it without deciding what it IS.
local function ApplyImportantGlow(e, cfg)
    local holder = e.bar
    if not (cfg.importantGlow and Glows and Glows.StartEngineGlow) then
        ClearImportantGlow(holder)
        return
    end
    local imp = e._important
    if type(imp) == "nil" then
        ClearImportantGlow(holder)
        return
    end
    if issecretvalue and issecretvalue(imp) then
        -- Must run the animation regardless; only its alpha carries the answer.
        -- StartEngineGlow forces alpha 1 on (re)start, so the boolean alpha
        -- assignment always runs AFTER the start call, never before.
        local ov = StartImportantGlowAnim(holder, cfg)
        ov:SetAlphaFromBoolean(imp)
        return
    end
    -- Known, non-secret boolean: safe to branch directly.
    if imp then
        local ov = StartImportantGlowAnim(holder, cfg)
        ov:SetAlpha(1)
    else
        ClearImportantGlow(holder)
    end
end

--------------------------------------------------------------------------------
--  Cast color: kick-ready tint and uninterruptible wash always apply (Cast
--  Colors has no off switch); the important-cast tint blends in on top only
--  when enabled. All secret combines ride C_CurveUtil boolean curves or
--  SetAlphaFromBoolean; nothing branches on a secret.
--------------------------------------------------------------------------------
-- Kick off-cooldown flag (possibly SECRET), read ONCE per slow pass and shared
-- by every bar; nil when the API is unavailable (callers fall back to the
-- shared per-call tint helper).
local function KickOffCooldown()
    local kick = GetActiveKickSpell and GetActiveKickSpell()
    if not (kick and C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local cd = C_Spell.GetSpellCooldownDuration(kick)
    if not (cd and cd.IsZero) then return nil end
    return cd:IsZero()
end

local impScratch = {}
-- offCd: pre-read KickOffCooldown() for batched passes; omitted on per-cast
-- paints. Same blend as the shared helper (off cooldown = base, on = ready tint).
local function ApplyCastColor(e, cfg, offCd)
    local holder = e.bar
    holder.overlay:SetAlphaFromBoolean(e._kickProtected)
    local base = cfg.barColor or { r = 0.70, g = 0.40, b = 0.90 }
    local ev = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if cfg.importantEnabled and ev then
        local imp = e._important
        if type(imp) == "nil" then imp = false end
        local ic = cfg.importantColor or { r = 1, g = 0.2, b = 0.2 }
        impScratch.r = ev(imp, ic.r, base.r)
        impScratch.g = ev(imp, ic.g, base.g)
        impScratch.b = ev(imp, ic.b, base.b)
        base = impScratch
    end
    local cr, cg, cb = base.r, base.g, base.b
    local ready = cfg.interruptReady or { r = 0.92, g = 0.35, b = 0.20 }
    if type(offCd) ~= "nil" and ev then
        cr = ev(offCd, base.r, ready.r)
        cg = ev(offCd, base.g, ready.g)
        cb = ev(offCd, base.b, ready.b)
    elseif ComputeCastBarTint then
        cr, cg, cb = ComputeCastBarTint(ready, base)
    end
    holder.sb:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
end

--------------------------------------------------------------------------------
--  Raid target marker: left of the spell name. Deliberately NOT
--  SetRaidTargetIconTexture -- that helper derives texcoords with Lua
--  arithmetic on the index, which throws on a secret number.
--  GetRaidTargetIndex is a known secret-prone call.
--------------------------------------------------------------------------------
local function ApplyRaidMarker(e, cfg)
    local holder = e.bar
    if not cfg.showRaidMarker then
        if holder.marker:IsShown() then
            holder.marker:Hide()
            AnchorName(holder, cfg, false)
        end
        return
    end
    local idx = GetRaidTargetIndex and GetRaidTargetIndex(e.unit)
    if type(idx) == "nil" then -- type() is the taint-safe existence check
        if holder.marker:IsShown() then
            holder.marker:Hide()
            AnchorName(holder, cfg, false)
        end
        return
    end
    if issecretvalue and issecretvalue(idx) then
        if holder.marker.SetSpriteSheetCell then
            pcall(holder.marker.SetSpriteSheetCell, holder.marker, idx, 4, 4, 64, 64)
        end
    else
        local tc = RAID_MARKER_TEXCOORDS[idx]
        if tc then holder.marker:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    end
    holder.marker:Show()
    AnchorName(holder, cfg, true)
end

--------------------------------------------------------------------------------
--  Out-of-interrupt-range fade: dims the whole bar (icon, texts, marker, glow
--  together) when the unit is beyond the player's active interrupt spell's
--  range. Secret-safe idiom: issecretvalue() runs BEFORE the ~= nil check so
--  the comparison never touches a secret value.
--------------------------------------------------------------------------------
local function ApplyRangeAlpha(e, cfg)
    local holder = e.bar
    if not (cfg.oorEnabled and GetActiveKickSpell and GetActiveKickSpell()
        and C_Spell and C_Spell.IsSpellInRange) then
        if e._oorApplied then
            holder:SetAlpha(1)
            e._oorApplied = nil
        end
        return
    end
    local inRange = C_Spell.IsSpellInRange(GetActiveKickSpell(), e.unit)
    if (issecretvalue and issecretvalue(inRange)) or inRange ~= nil then
        holder:SetAlphaFromBoolean(inRange, 1, cfg.oorAlpha or 0.45)
    else
        holder:SetAlpha(1)
    end
    e._oorApplied = true
end

--------------------------------------------------------------------------------
--  Duration lookup: ArmFill already knows which getter applies (it picks the
--  fill direction), so the timer text reuses that instead of trying all three
--  duration APIs every tick (O2). Falls back to the full chain on a transient
--  miss or before any kind has been cached, so behaviour never regresses.
--------------------------------------------------------------------------------
local function GetDurationObj(e)
    local kind = e.durKind
    if kind == "cast" then
        local d = UnitCastingDuration(e.unit)
        if d then return d end
    elseif kind == "empowered" then
        local d = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(e.unit, true)
        if d then return d end
    elseif kind == "channel" then
        local d = UnitChannelDuration and UnitChannelDuration(e.unit)
        if d then return d end
    end
    return UnitCastingDuration(e.unit)
        or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(e.unit, true))
        or (UnitChannelDuration and UnitChannelDuration(e.unit))
end

--------------------------------------------------------------------------------
--  Shared 10Hz timer text: one ticker for the whole group, armed only while
--  needed (O1), self-stops when the last bar releases. Remaining time comes
--  from the duration object only -- cast start/end times are secret and
--  unusable in arithmetic. Also drives a 0.2s slow pass (every 2nd fire) for
--  kick-ready repaint and range fade, since neither reliably fires a naming
--  event (a kick coming off cooldown, or walking back into range).
--------------------------------------------------------------------------------
local function TimerBody()
    local n = #shown
    if n == 0 then return false end
    local cfg = Cfg()
    local showTimer = UnitCastingDuration and cfg and cfg.showTimer ~= false
    if showTimer then
        for i = 1, n do
            local e = shown[i]
            if not e.preview then
                local fs = e.bar.timer
                local durObj = GetDurationObj(e)
                if durObj then
                    fs:SetFormattedText("%.1f", durObj:GetRemainingDuration())
                else
                    fs:SetText("")
                end
            end
        end
    end

    local wantColor = cfg and GetActiveKickSpell and GetActiveKickSpell()
    local wantRange = cfg and cfg.oorEnabled
    if wantColor or wantRange then
        slowAccum = slowAccum + 1
        if slowAccum >= 2 then
            slowAccum = 0
            -- One cooldown read per pass, not per bar. Plain assignment: the
            -- flag can be SECRET, and `x and flag or y` would boolean-test it.
            local offCd
            if wantColor then offCd = KickOffCooldown() end
            for i = 1, n do
                local e = shown[i]
                if not e.preview then
                    if wantColor then ApplyCastColor(e, cfg, offCd) end
                    if wantRange then ApplyRangeAlpha(e, cfg) end
                end
            end
        end
    end

    return true
end

local function ArmTimerTicker()
    local cfg = Cfg()
    -- O1: don't arm the ticker at all unless something needs its 10Hz tick --
    -- the timer text, or one of the polling features.
    local needed = cfg and (cfg.showTimer ~= false or cfg.oorEnabled or (GetActiveKickSpell and GetActiveKickSpell()))
    if not needed then return end
    if not timerTicker and EllesmereUI.Tick and EllesmereUI.Tick.NewAnimTicker then
        timerTicker = EllesmereUI.Tick.NewAnimTicker(EnsureContainer(), TimerBody, 0.1)
    end
    if timerTicker then
        TimerBody()
        timerTicker.Start()
    end
end

--------------------------------------------------------------------------------
--  Cast lifecycle
--------------------------------------------------------------------------------
local function ArmFill(e, isChannel)
    local sb = e.bar.sb
    if not (UnitCastingDuration and sb.SetTimerDuration) then return end
    local dur, isEmp
    if isChannel then
        if UnitEmpoweredChannelDuration then
            dur = UnitEmpoweredChannelDuration(e.unit, true)
            if dur then isEmp = true end
        end
        if not dur then dur = UnitChannelDuration(e.unit) end
        if dur then
            sb:SetReverseFill(false)
            -- Empowered channels build forward; normal channels drain.
            local dirn = isEmp and Enum.StatusBarTimerDirection.ElapsedTime
                or Enum.StatusBarTimerDirection.RemainingTime
            sb:SetTimerDuration(dur, nil, dirn)
            e.durKind = isEmp and "empowered" or "channel"
        end
    else
        dur = UnitCastingDuration(e.unit)
        if dur then
            sb:SetReverseFill(false)
            sb:SetTimerDuration(dur, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            e.durKind = "cast"
        end
    end
end

local function PaintTarget(e, cfg)
    local fs = e.bar.target
    if cfg.showTarget == false then
        fs:SetText("")
        fs:Hide()
        return
    end
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(e.unit) then
        -- Names may be SECRET: type() is the safe existence check, and
        -- SetText accepts secret strings without exposing them to Lua.
        local raw = UnitSpellTargetName and UnitSpellTargetName(e.unit)
        if type(raw) ~= "nil" then
            spellTarget = raw
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(e.unit)
        end
    end
    if type(spellTarget) == "nil" then
        fs:SetText("")
        fs:Hide()
        return
    end
    if cfg.targetClassColor ~= false and type(spellTargetClass) ~= "nil" and C_ClassColor then
        local col = C_ClassColor.GetClassColor(spellTargetClass)
        if col then fs:SetTextColor(col:GetRGB()) else fs:SetTextColor(1, 1, 1, 1) end
    else
        local tc = cfg.targetColor
        if tc then fs:SetTextColor(tc.r, tc.g, tc.b, 1) else fs:SetTextColor(1, 1, 1, 1) end
    end
    fs:SetText(spellTarget)
    fs:Show()
end

local function Release(unit)
    local e = unitEntry[unit]
    if not e then return end
    unitEntry[unit] = nil
    for i = 1, #shown do
        if shown[i] == e then
            table.remove(shown, i)
            break
        end
    end
    -- Bars are pooled and reused forever: every piece of per-cast visual state
    -- set by the new features must be cleared here, or the next occupant
    -- inherits it.
    local holder = e.bar
    ClearImportantGlow(holder)
    holder:SetAlpha(1)
    holder.overlay:SetAlpha(0)
    holder.marker:Hide()
    holder._tsbInUse = nil
    holder:Hide()
    Reflow()
end

-- Only CLEANLY-friendly plates are excluded (friendly NPC nameplates). The
-- attackable flag can be SECRET in instanced combat; a secret answer fail-
-- OPENS (the cast shows) rather than ever branching on the secret.
local function IsTrackableUnit(unit)
    local ok, att = pcall(UnitCanAttack, "player", unit)
    if ok and not (issecretvalue and issecretvalue(att)) and att == false then
        return false
    end
    return true
end

local PromoteWaiting -- forward: StartCast <-> PromoteWaiting recursion

local function StartCast(unit)
    local cfg = Cfg()
    if not cfg then return end
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(unit)
    local isChannel = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(unit)
        isChannel = true
    end
    if type(name) == "nil" then
        Release(unit)
        if PromoteWaiting then PromoteWaiting() end
        return
    end
    if not IsTrackableUnit(unit) then return end

    local e = unitEntry[unit]
    local isNew = false
    if not e then
        if #shown >= (cfg.maxBars or 5) then
            anyCastDropped = true -- promoted when a slot frees (O4)
            return
        end
        e = { unit = unit, bar = AcquireBarFrame() }
        unitEntry[unit] = e
        shown[#shown + 1] = e
        isNew = true
        PositionBar(e.bar, #shown, cfg)
    end
    -- O3: a bar only needs a full restyle once per settings generation, not on
    -- every cast -- new/reused-from-pool bars never carry the current stamp.
    if isNew or e.bar._styleGen ~= styleGen then
        StyleBar(e.bar, cfg)
    end
    e.isChannel = isChannel
    e.preview = nil

    if type(kickProtected) == "nil" then kickProtected = false end
    e._kickProtected = kickProtected
    -- Important flag may be SECRET: stored raw, fed only to color curves and
    -- SetAlphaFromBoolean, never branched on directly.
    e._important = false
    if C_Spell and C_Spell.IsSpellImportant then
        local impOK, imp = pcall(C_Spell.IsSpellImportant, castSpellID or 0)
        if impOK then e._important = imp end
    end

    -- Icon and name MUST describe the SAME cast: both come from this
    -- snapshot. The live texture may be SECRET -- SetTexture accepts it.
    if cfg.showIcon ~= false then
        if type(texture) ~= "nil" then
            e.bar.icon:SetTexture(texture)
        elseif type(castSpellID) ~= "nil" then
            local okInfo, info = pcall(C_Spell.GetSpellInfo, castSpellID)
            if okInfo and type(info) == "table" then
                e.bar.icon:SetTexture(info.iconID)
            else
                e.bar.icon:SetTexture(nil)
            end
        else
            e.bar.icon:SetTexture(nil)
        end
    end
    if cfg.showSpellName ~= false then
        e.bar.name:SetText(name)
    end
    PaintTarget(e, cfg)
    ApplyRaidMarker(e, cfg)
    ApplyCastColor(e, cfg)
    ApplyImportantGlow(e, cfg)
    e.bar.timer:SetText("")
    ArmFill(e, isChannel)
    ApplyRangeAlpha(e, cfg)
    e.bar:Show()
    ArmTimerTicker()
end

-- Fill freed slots from plates that were casting while the group was full.
-- O4: only scans plateUnits when a cast was actually dropped at the cap --
-- with nothing ever dropped, every release is a free no-op instead of a full
-- plate walk.
PromoteWaiting = function()
    if not anyCastDropped then return end
    local cfg = Cfg()
    if not cfg then return end
    if #shown >= (cfg.maxBars or 5) then return end
    anyCastDropped = false
    for unit in pairs(plateUnits) do
        if not unitEntry[unit] then
            local nm = UnitCastingInfo(unit)
            if type(nm) == "nil" then nm = UnitChannelInfo(unit) end
            if type(nm) ~= "nil" then
                StartCast(unit)
                if #shown >= (cfg.maxBars or 5) then return end
            end
        end
    end
end

-- Mid-cast interruptibility flips: re-read protection once, store, repaint.
-- Port of the TargetFocusBars KickProtectionChanged pattern.
local function RefreshKickProtection(unit)
    local cfg = Cfg()
    if not cfg then return end
    local e = unitEntry[unit]
    if not e then return end
    local kickProtected
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(unit)
    if type(sName) ~= "nil" then
        kickProtected = kp
    else
        local cName
        cName, _, _, _, _, _, kp = UnitChannelInfo(unit)
        if type(cName) == "nil" then return end
        kickProtected = kp
    end
    if type(kickProtected) == "nil" then kickProtected = false end
    e._kickProtected = kickProtected
    ApplyCastColor(e, cfg)
end

local function RefreshAllRaidMarkers()
    local cfg = Cfg()
    if not cfg then return end
    for i = 1, #shown do
        local e = shown[i]
        if not e.preview then ApplyRaidMarker(e, cfg) end
    end
end

--------------------------------------------------------------------------------
--  Events: registered ONLY while enabled. One frame; unit filtering is the
--  plateUnits hash (nameplate tokens only -- party/raid cast chatter costs
--  one failed lookup).
--------------------------------------------------------------------------------
local evt = CreateFrame("Frame")

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local UPDATE_EVENTS = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}
local PROBE_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
}
-- These release directly instead of re-probing: in restricted execution the
-- cast-info reads can return secret values (not nil) for a stale channel or
-- empowered cast, making a probe think it is still active (nameplate lesson).
local RELEASE_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

evt:SetScript("OnEvent", function(_, event, unit)
    if previewOn then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        if unit then
            plateUnits[unit] = true
            -- Probe the delta: only this plate, only if it is mid-cast.
            local nm = UnitCastingInfo(unit)
            if type(nm) == "nil" then nm = UnitChannelInfo(unit) end
            if type(nm) ~= "nil" then StartCast(unit) end
        end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if unit then
            plateUnits[unit] = nil
            Release(unit)
            PromoteWaiting()
        end
        return
    end
    if event == "RAID_TARGET_UPDATE" then
        RefreshAllRaidMarkers()
        return
    end
    -- Spellcast family: nameplate units only.
    if not unit or not plateUnits[unit] then return end
    if START_EVENTS[event] then
        StartCast(unit)
    elseif UPDATE_EVENTS[event] then
        local e = unitEntry[unit]
        if e then ArmFill(e, e.isChannel) end
    elseif PROBE_EVENTS[event] then
        if unitEntry[unit] then StartCast(unit) end
    elseif RELEASE_EVENTS[event] then
        Release(unit)
        PromoteWaiting()
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        RefreshKickProtection(unit)
    end
end)

local ALL_EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- RAID_TARGET_UPDATE only while the marker feature is on (zero cost otherwise).
local function SyncMarkerEvent(cfg)
    if not active then return end
    if cfg and cfg.showRaidMarker then
        evt:RegisterEvent("RAID_TARGET_UPDATE")
    else
        evt:UnregisterEvent("RAID_TARGET_UPDATE")
    end
end

local function ReleaseAll()
    for i = #shown, 1, -1 do
        local e = shown[i]
        unitEntry[e.unit] = nil
        local holder = e.bar
        ClearImportantGlow(holder)
        holder:SetAlpha(1)
        holder.overlay:SetAlpha(0)
        holder.marker:Hide()
        holder._tsbInUse = nil
        holder:Hide()
        shown[i] = nil
    end
end

-- Seed from plates that already exist (mid-session enable).
local function SeedFromLivePlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for i = 1, #plates do
        local unit = plates[i] and plates[i].namePlateUnitToken
        if unit then
            plateUnits[unit] = true
            local nm = UnitCastingInfo(unit)
            if type(nm) == "nil" then nm = UnitChannelInfo(unit) end
            if type(nm) ~= "nil" then StartCast(unit) end
        end
    end
end

local function Activate()
    if active then return end
    active = true
    EnsureContainer()
    for i = 1, #ALL_EVENTS do evt:RegisterEvent(ALL_EVENTS[i]) end
    SyncMarkerEvent(Cfg())
    SeedFromLivePlates()
end

local function Deactivate()
    if not active then return end
    active = false
    evt:UnregisterAllEvents()
    ReleaseAll()
    wipe(plateUnits)
end

SyncWhereActive = function()
    local cfg = Cfg()
    local want = cfg and cfg.enabled == true and WhereShows(cfg.whereToShow)
    if want and not active then
        Activate()
    elseif not want and active then
        Deactivate()
        previewOn = false
    end
end

--------------------------------------------------------------------------------
--  Preview: sample bars for options / unlock placement. Static content --
--  plain SetValue (cancels timer mode) so nothing animates or reads units.
--  Every new feature gets one sample row so it is visible while configuring.
--------------------------------------------------------------------------------
local PREVIEW_ROWS = {
    { name = "Shadow Bolt",     fill = 0.65, timer = "1.2" },
    { name = "Mending",         fill = 0.35, timer = "2.4", uninterruptible = true },
    { name = "Terrifying Roar", fill = 0.85, timer = "0.6", marker = 8, important = true },
}

local function ShowPreview()
    local cfg = Cfg()
    if not cfg then return end
    ReleaseAll()
    EnsureContainer()
    local rows = math.min(#PREVIEW_ROWS, cfg.maxBars or 5)
    for i = 1, rows do
        local sample = PREVIEW_ROWS[i]
        local e = { unit = "preview" .. i, bar = AcquireBarFrame(), preview = true }
        shown[#shown + 1] = e
        StyleBar(e.bar, cfg)
        PositionBar(e.bar, i, cfg)
        e.bar:SetAlpha(1)
        e.bar.icon:SetTexture(134400)
        if cfg.showSpellName ~= false then e.bar.name:SetText(sample.name) end
        if cfg.showTarget ~= false then
            local tc = cfg.targetColor
            if cfg.targetClassColor ~= false and C_ClassColor and UnitClassBase then
                local col = C_ClassColor.GetClassColor(UnitClassBase("player"))
                if col then e.bar.target:SetTextColor(col:GetRGB()) end
            elseif tc then
                e.bar.target:SetTextColor(tc.r, tc.g, tc.b, 1)
            end
            e.bar.target:SetText(UnitName("player") or "Target")
            e.bar.target:Show()
        else
            e.bar.target:SetText("")
            e.bar.target:Hide()
        end
        e.bar.timer:SetText(cfg.showTimer ~= false and sample.timer or "")
        e.bar.sb:SetValue(sample.fill)

        -- Uninterruptible / kick-ready sample: static, no live unit involved.
        if sample.uninterruptible then
            e.bar.overlay:SetAlpha(1)
            local un = cfg.uninterruptible or { r = 0.45, g = 0.45, b = 0.45 }
            e.bar.sb:GetStatusBarTexture():SetVertexColor(un.r, un.g, un.b)
        else
            e.bar.overlay:SetAlpha(0)
            local c = cfg.barColor
            if c then e.bar.sb:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b) end
        end

        -- Raid marker sample: static, non-secret index.
        if cfg.showRaidMarker and sample.marker then
            local tc = RAID_MARKER_TEXCOORDS[sample.marker]
            if tc then e.bar.marker:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
            e.bar.marker:Show()
            AnchorName(e.bar, cfg, true)
        else
            e.bar.marker:Hide()
            AnchorName(e.bar, cfg, false)
        end

        -- Important sample: tint and/or glow, both driven by a plain (never
        -- secret) boolean here.
        e._important = sample.important == true
        if cfg.importantEnabled and sample.important then
            local ic = cfg.importantColor or { r = 1, g = 0.2, b = 0.2 }
            e.bar.sb:GetStatusBarTexture():SetVertexColor(ic.r, ic.g, ic.b)
        end
        if cfg.importantGlow and sample.important then
            ApplyImportantGlow(e, cfg)
        else
            ClearImportantGlow(e.bar)
        end

        e.bar:Show()
    end
end

function ns.TSB_SetPreview(on)
    previewOn = on == true
    if previewOn then
        ShowPreview()
    else
        ReleaseAll()
        if active then SeedFromLivePlates() end
    end
end

function ns.TSB_IsPreview()
    return previewOn
end

--------------------------------------------------------------------------------
--  Refresh: the one entry point for enable/disable + live restyle. Options
--  call this after every settings write.
--------------------------------------------------------------------------------
function ns.TSB_Refresh()
    local cfg = Cfg()
    SetWhereWatcherActive(cfg and cfg.enabled == true)
    SyncWhereActive()
    if not cfg then return end
    SyncMarkerEvent(cfg)
    styleGen = styleGen + 1 -- O3: invalidate every bar's cached style stamp
    if container then
        container:SetSize(cfg.width or 240, cfg.height or 20)
        ApplyContainerPosition()
    end
    if previewOn then
        ShowPreview()
        return
    end
    -- Restyle live bars in place; trim overflow if Max Bars shrank.
    local maxBars = cfg.maxBars or 5
    for i = #shown, maxBars + 1, -1 do
        local e = shown[i]
        unitEntry[e.unit] = nil
        local holder = e.bar
        ClearImportantGlow(holder)
        holder:SetAlpha(1)
        holder.overlay:SetAlpha(0)
        holder.marker:Hide()
        holder._tsbInUse = nil
        holder:Hide()
        shown[i] = nil
    end
    for i = 1, #shown do
        local e = shown[i]
        StyleBar(e.bar, cfg)
        PositionBar(e.bar, i, cfg)
        if not e.preview then
            ApplyRaidMarker(e, cfg)
            ApplyCastColor(e, cfg)
            ApplyImportantGlow(e, cfg)
            ApplyRangeAlpha(e, cfg)
        end
    end
    ArmTimerTicker()
end

--------------------------------------------------------------------------------
--  Unlock mode: one group element. Registered once at init (a stored table);
--  the mover is hidden while the feature is disabled.
--------------------------------------------------------------------------------
local function RegisterUnlock()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EMT_TargetedSpellBars",
            label = "Targeted Spell Bars",
            group = "Mythic+",
            order = 521,
            -- Sized by the options sliders (no drag-resize handle), but the
            -- group can size-MATCH another element and be matched TO: the match
            -- apply pushes through setWidth/setHeight into the same cfg keys
            -- the sliders write (per-bar size; the container relayouts).
            noResize = true,
            allowMatchSource = true,
            isHidden = function()
                local cfg = Cfg()
                return not (cfg and cfg.enabled == true)
            end,
            getFrame = function()
                return EnsureContainer()
            end,
            getSize = function()
                local cfg = Cfg()
                return (cfg and cfg.width) or 240, (cfg and cfg.height) or 20
            end,
            setWidth = function(_, w)
                local cfg = Cfg()
                if not cfg then return end
                cfg.width = math.floor(w + 0.5)
                ns.TSB_Refresh()
            end,
            setHeight = function(_, h)
                local cfg = Cfg()
                if not cfg then return end
                cfg.height = math.floor(h + 0.5)
                ns.TSB_Refresh()
            end,
            savePos = function()
                local cfg = Cfg()
                local f = container
                if not (cfg and f and f:GetCenter()) then return end
                -- Raw UIParent-logical center delta; the effective-scale ratio
                -- normalizes GetCenter's frame-scaled units (timer lesson:
                -- scale division must never live in the interchange format).
                local cx, cy = f:GetCenter()
                local upX, upY = UIParent:GetCenter()
                local fes = f:GetEffectiveScale() or 1
                local ues = UIParent:GetEffectiveScale() or 1
                local ratio = fes / ues
                cfg.pos = { centerX = cx * ratio - upX, centerY = cy * ratio - upY }
                if not (EllesmereUI._unlockActive) then ApplyContainerPosition() end
            end,
            loadPos = function()
                local cfg = Cfg()
                local pos = cfg and cfg.pos
                if not (pos and pos.centerX and pos.centerY) then return nil end
                return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
            end,
            clearPos = function()
                local cfg = Cfg()
                if cfg then cfg.pos = nil end
            end,
            applyPos = function()
                ApplyContainerPosition()
            end,
        }),
    }, "EllesmereUIMythicTimer")

    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EMT_TargetedSpellBars", function(unlockActive)
            local cfg = Cfg()
            if not (cfg and cfg.enabled == true) then return end
            -- Sample bars while placing; back to live content on exit.
            ns.TSB_SetPreview(unlockActive == true)
            local anchored = EllesmereUI.IsUnlockAnchored
                and EllesmereUI.IsUnlockAnchored("EMT_TargetedSpellBars")
            if not anchored then ApplyContainerPosition() end
        end)
    end
end

--------------------------------------------------------------------------------
--  Init: called from EMT:OnEnable (before the timer's own enable guard).
--------------------------------------------------------------------------------
function ns.TSB_OnEnable(database)
    db = database
    if not db then return end
    RegisterUnlock()
    ns.TSB_Refresh()
end
