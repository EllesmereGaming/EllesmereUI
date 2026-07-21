-------------------------------------------------------------------------------
--  EllesmereUIDamageMeters_SpellHistory.lua
--  Standalone spell history tracker.  Two independent display modes:
--    - Icon strip: horizontal/vertical row of spell icons (grows configurable)
--    - Bar window: standalone window matching DM bar styling
--  Zero overhead when both features are disabled (no events registered).
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local MAX_HISTORY       = 80
local BAR_TEX           = "Interface\\Buttons\\WHITE8X8"
local ICON_POOL_SIZE    = 40
local BAR_POOL_SIZE     = 40

-- Interrupted/failed bar color (hardcoded)
local CLR_STOPPED       = { 0.859, 0.255, 0.255 }  -- #DB4141

local OUTCOME_TEXT = {
    failed      = "|cffdb4141Failed|r",
    interrupted = "|cffdb4141Interrupted|r",
}

-------------------------------------------------------------------------------
--  DB defaults
-------------------------------------------------------------------------------
local SH_DEFAULTS = {
    iconEnabled     = false,
    barEnabled      = false,
    growDirection   = "LEFT",
    iconSize        = 36,
    iconZoom        = 0.08,
    iconFadeTime    = 0,
    iconSpacing     = 1,
    iconCount       = 5,
    iconOpacity     = 1,
    iconAnimation   = "none",  -- none, slide, fly
    maxBars         = 5,
    hideTopBar      = false,
    barWidth        = 300,
    barLocked       = false,
    barPos          = nil,
    iconPos         = nil,
    barColorUseClass  = false,
    barColorUseAccent = false,
    barColor        = { r = 0.298, g = 0.565, b = 0.494 },  -- #4C907E
    barOpacity      = 1,
    spellHistoryBarTexture = "match",
    textSize        = 11,
    textColorUseAccent = false,
    textColor       = { r = 1, g = 1, b = 1 },
    shBarHeight     = 20,
    bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.25,
    iconHideInDungeon    = false,
    iconHideInRaid       = false,
    iconHideOutOfInstance = false,
    barHideInDungeon     = false,
    barHideInRaid        = false,
    barHideOutOfInstance = false,
}

-------------------------------------------------------------------------------
--  Shared history buffer (newest at index 1)
-------------------------------------------------------------------------------
local _history = {}
local _pendingCasts = {}

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local floor, format, min, max = math.floor, string.format, math.min, math.max
local GetTime = GetTime

-- Spell info cache: spellID -> { name, iconID } (never changes for a given ID)
local _spellInfoCache = {}

-- Cached DB accessor; defaults are merged once at init, not per-call
local _shDB
local function DB()
    if _shDB then return _shDB end
    local d = ns.EDM.DB()
    if not d.spellHistory then d.spellHistory = {} end
    local sh = d.spellHistory
    for k, v in pairs(SH_DEFAULTS) do
        if sh[k] == nil then sh[k] = v end
    end
    _shDB = sh
    return sh
end

local function GetDMFont()
    if EUI and EUI.GetFontPath then return EUI.GetFontPath("damageMeters") end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetDMOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("damageMeters")) or ""
end

local function SetFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local font, flags = GetDMFont(), GetDMOutline()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flags == "") end
    fs:SetFont(font, size, flags)
end

local function PhysicalPixels(val)
    local PP = EUI and EUI.PP
    return (val or 0) * ((PP and PP.mult) or 1)
end

local function GetBarTexturePath()
    local dmCfg = ns.EDM.DB()
    local sh = DB()
    local key = sh.spellHistoryBarTexture
    if not key or key == "match" then
        key = (dmCfg and dmCfg.barTexture) or "none"
    end
    local texTable = _G._EDM_BarTextures
    if texTable then return EUI.ResolveTexturePath(texTable, key, BAR_TEX) end
    return BAR_TEX
end

local function GetAccentRGB()
    local EG = EUI.ELLESMERE_GREEN
    if EG then return EG.r, EG.g, EG.b end
    return EUI.DEFAULT_ACCENT_R or 12/255, EUI.DEFAULT_ACCENT_G or 210/255, EUI.DEFAULT_ACCENT_B or 157/255
end

local function OutcomeColor(status)
    if status == "failed" or status == "interrupted" then
        return CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3]
    end
    local sh = DB()
    if sh.barColorUseClass then
        local _, classFile = UnitClass("player")
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] and EUI.GetClassColor(classFile)
        if cc then return cc.r, cc.g, cc.b end
    end
    if sh.barColorUseAccent then return GetAccentRGB() end
    local c = sh.barColor
    return c and c.r or 0.298, c and c.g or 0.565, c and c.b or 0.494
end

-- Resolve spell override (base -> active override) for correct name/icon
local function ResolveOverride(sid)
    if C_Spell and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if ov and ov ~= 0 and ov ~= sid then return ov end
    end
    if FindSpellOverrideByID then
        local ov = FindSpellOverrideByID(sid)
        if ov and ov ~= 0 and ov ~= sid then return ov end
    end
    return sid
end

local function FormatCastTime(entry)
    if entry.isInstant then return "" end
    local status = entry.status
    -- Active cast: show elapsed time counting up
    if status == "casting" or status == "channeling" then
        local elapsed = GetTime() - entry.startTime
        if elapsed > 0 then return format("%.1f", elapsed) end
        return ""
    end
    -- Completed/failed: show total duration
    if entry.castDuration and entry.castDuration > 0 then return format("%.1fs", entry.castDuration) end
    return ""
end

-- Build right-side text without allocating a temp table each time
local function BuildRightText(entry)
    local castStr = FormatCastTime(entry)
    local outcomeStr = OUTCOME_TEXT[entry.status]
    -- Outcome (Interrupted/Failed) replaces target; otherwise show target.
    -- Enemy names in M+ are secret values but FontStrings can display them.
    local target = entry.target
    local isSecret = target and issecretvalue and issecretvalue(target)
    local hasTarget = target and (isSecret or target ~= "")
    -- Strip realm suffix for non-secret names (secret values pass through to FontString as-is)
    if hasTarget and not isSecret and not outcomeStr and Ambiguate then
        target = Ambiguate(target, "short")
    end
    local rightPart = outcomeStr or (hasTarget and target) or nil
    local result
    if castStr ~= "" and rightPart then
        result = castStr .. "  " .. rightPart
    elseif castStr ~= "" then
        result = castStr
    elseif rightPart then
        result = rightPart
    else
        result = ""
    end
    return result
end

-------------------------------------------------------------------------------
--  Forward declarations (defined after UI code)
-------------------------------------------------------------------------------
local RefreshBarWindow
local BuildIconStrip
local StartCastAnim

-------------------------------------------------------------------------------
--  History management
-------------------------------------------------------------------------------
local function RefreshViews()
    local sh = DB()
    if sh.iconEnabled  then BuildIconStrip() end
    if sh.barEnabled   then RefreshBarWindow() end
end

local function PushEntry(entry)
    table.insert(_history, 1, entry)
    if #_history > MAX_HISTORY then _history[#_history] = nil end
    RefreshViews()
end

local _pendingTargets = {}  -- castGUID -> target name (from UNIT_SPELLCAST_SENT)
local _activeChannelSpell = nil  -- spellID of currently channeling spell (suppress tick SUCCEEDEDs)
local _knownOverrides = {}  -- spellID -> true for override spells that pass IsSpellKnownOrOverridesKnown

local function FinishPending(castGUID, status)
    _pendingTargets[castGUID] = nil
    local entry = _pendingCasts[castGUID]
    if not entry then return end
    -- Don't downgrade a success (server accepted) to failed/interrupted (client race)
    if entry.status == "success" then _pendingCasts[castGUID] = nil; return end
    -- Snapshot fill progress for interrupted/failed casts so the bar freezes
    if status == "interrupted" or status == "failed" then
        local now = GetTime()
        local dur = entry.endTime - entry.startTime
        if dur > 0 then
            if entry.isChannel then
                entry.fillProgress = max(0, min(1, (entry.endTime - now) / dur))
            else
                entry.fillProgress = max(0, min(1, (now - entry.startTime) / dur))
            end
        end
    end
    entry.status = status
    entry.endTime = GetTime()
    if entry.startTime then entry.castDuration = entry.endTime - entry.startTime end
    _pendingCasts[castGUID] = nil
    RefreshViews()
end

-------------------------------------------------------------------------------
--  Event-driven spell tracking
--  Events are only registered when at least one feature is enabled.
-------------------------------------------------------------------------------
local _eventsActive = false
local eventFrame = CreateFrame("Frame")

local function OnSpellEvent(_, event, unit, ...)
    if unit ~= "player" then return end

    -- UNIT_SPELLCAST_SENT has unique args: unit, target, castGUID, spellID
    if event == "UNIT_SPELLCAST_SENT" then
        local target, castGUID2 = ...
        if castGUID2 and target then
            _pendingTargets[castGUID2] = target
        end
        return
    end

    local castGUID, spellID = ...

    if event == "UNIT_SPELLCAST_START" then
        local name, _, _, startMS, endMS = UnitCastingInfo("player")
        if not name or not spellID then return end
        spellID = ResolveOverride(spellID)
        local info = _spellInfoCache[spellID]
        if not info then info = C_Spell and C_Spell.GetSpellInfo(spellID); if info then _spellInfoCache[spellID] = info end end
        local entry = {
            spellID      = spellID,
            spellName    = name,
            icon         = info and info.iconID,
            target       = castGUID and _pendingTargets[castGUID],
            startTime    = (startMS or 0) / 1000,
            endTime      = (endMS or 0) / 1000,
            castDuration = ((endMS or 0) - (startMS or 0)) / 1000,
            status       = "casting",
            isInstant    = false,
            isChannel    = false,
            timestamp    = GetTime(),
        }
        if castGUID then _pendingCasts[castGUID] = entry end
        PushEntry(entry)
        StartCastAnim()

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name, _, _, startMS, endMS, _, _, chanSpellID = UnitChannelInfo("player")
        local sid = ResolveOverride(chanSpellID or spellID)
        if not name then return end
        local info = sid and _spellInfoCache[sid]
        if not info and sid then info = C_Spell and C_Spell.GetSpellInfo(sid); if info then _spellInfoCache[sid] = info end end
        local entry = {
            spellID      = sid,
            spellName    = name,
            icon         = info and info.iconID,
            target       = castGUID and _pendingTargets[castGUID],
            startTime    = (startMS or 0) / 1000,
            endTime      = (endMS or 0) / 1000,
            castDuration = ((endMS or 0) - (startMS or 0)) / 1000,
            status       = "channeling",
            isInstant    = false,
            isChannel    = true,
            timestamp    = GetTime(),
        }
        _activeChannelSpell = sid
        if castGUID then _pendingCasts[castGUID] = entry end
        PushEntry(entry)
        StartCastAnim()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if castGUID and _pendingCasts[castGUID] then
            FinishPending(castGUID, "success")
        else
            -- Skip channeled spell ticks (SUCCEEDED fires per tick during a channel)
            if _activeChannelSpell and spellID == _activeChannelSpell then return end
            -- Skip internal/system spells (LOGINEFFECT, DNT, etc.)
            -- IsPlayerSpell catches most, but override/transform spells (e.g.
            -- Lightsmith armaments) fail it. Fall back to IsSpellKnownOrOverridesKnown
            -- and cache the result (that API is flaky on repeated calls).
            if not IsPlayerSpell(spellID) then
                if not _knownOverrides[spellID] then
                    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then
                        _knownOverrides[spellID] = true
                    else
                        return
                    end
                end
            end
            spellID = ResolveOverride(spellID)
            -- Latency race: INTERRUPTED/FAILED can fire before SUCCEEDED at
            -- the end of a cast.  The pending entry is already consumed and
            -- sitting in _history with a wrong status.  Scan recent history
            -- and fix it instead of creating a duplicate.
            local dominated = false
            -- Check pending casts first (different/nil castGUID race)
            for gid, pe in pairs(_pendingCasts) do
                if pe.spellID == spellID then
                    FinishPending(gid, "success")
                    dominated = true
                    break
                end
            end
            -- Check recent history (INTERRUPTED already consumed the entry)
            if not dominated then
                for hi = 1, min(#_history, 5) do
                    local he = _history[hi]
                    if he.spellID == spellID and (he.status == "interrupted" or he.status == "failed") then
                        he.status = "success"
                        he.fillProgress = nil
                        dominated = true
                        RefreshViews()
                        break
                    end
                end
            end
            if not dominated then
                local info = spellID and _spellInfoCache[spellID]
                if not info and spellID then info = C_Spell and C_Spell.GetSpellInfo(spellID); if info then _spellInfoCache[spellID] = info end end
                if not info then return end
                PushEntry({
                    spellID      = spellID,
                    spellName    = info.name or "?",
                    icon         = info.iconID,
                    target       = castGUID and _pendingTargets[castGUID],
                    startTime    = GetTime(),
                    endTime      = GetTime(),
                    castDuration = 0,
                    status       = "success",
                    isInstant    = true,
                    isChannel    = false,
                    timestamp    = GetTime(),
                })
            end
        end

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        if castGUID then FinishPending(castGUID, "failed") end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if castGUID then FinishPending(castGUID, "interrupted") end

    elseif event == "UNIT_SPELLCAST_STOP" then
        if not castGUID then return end
        local entry = _pendingCasts[castGUID]
        if entry and entry.status == "casting" then
            local gid = castGUID
            C_Timer.After(0, function()
                if _pendingCasts[gid] and _pendingCasts[gid].status == "casting" then
                    FinishPending(gid, "failed")
                end
            end)
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        _activeChannelSpell = nil
        if castGUID then
            _pendingTargets[castGUID] = nil
            local entry = _pendingCasts[castGUID]
            if entry then
                if entry.status == "channeling" then entry.status = "success" end
                entry.endTime = GetTime()
                if entry.startTime then entry.castDuration = entry.endTime - entry.startTime end
                _pendingCasts[castGUID] = nil
            end
        end
    end
end

local function RegisterEvents()
    if _eventsActive then return end
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")  -- player only (was global, fired for all units)
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    eventFrame:SetScript("OnEvent", OnSpellEvent)
    _eventsActive = true
end

local function UnregisterEvents()
    if not _eventsActive then return end
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    _eventsActive = false
end

-------------------------------------------------------------------------------
--  Instance visibility check
-------------------------------------------------------------------------------
local function ShouldHide(hideInDungeon, hideInRaid, hideOutOfInstance)
    -- Always visible while options panel is open
    if ns._optionsOpen then return false end
    local _, iType = IsInInstance()
    if hideInDungeon and iType == "party" then return true end
    if hideInRaid and iType == "raid" then return true end
    if hideOutOfInstance and (iType == "none" or iType == nil) then return true end
    return false
end

-------------------------------------------------------------------------------
--  ICON STRIP  (standalone movable frame)
-------------------------------------------------------------------------------
local _iconStrip
local _iconPool = {}
local _lastAnimTimestamp = 0  -- tracks when to animate icon 1
local _lastIconCount = 0      -- tracks visible count for minimal loop
local _iconLayoutKey = ""     -- tracks settings that affect icon layout (skip repositioning if unchanged)

local ANIM_DUR = 0.5
local ANIM_SLIDE_PX = 6

-------------------------------------------------------------------------------
--  Fade-out clock (iconFadeTime > 0): each icon expires individually once
--  its cast is older than the configured time, fading to zero over FADE_DUR.
--  Event-driven -- nothing runs while no icon is inside its fade window:
--    * out of combat, ONE one-shot timer is armed for the moment the next
--      icon begins fading; while an icon is actively fading, a throttled
--      OnUpdate driver (hidden when idle) repaints the strip;
--    * in combat everything is parked, so the history stays readable
--      through a fight. PLAYER_REGEN_ENABLED credits each entry the time
--      it spent in combat (per-entry base: icons cast mid-fight are
--      credited only their own in-combat lifetime) and restarts the clock.
-------------------------------------------------------------------------------
local FADE_DUR = 1.5
local _fadeTimer    -- one-shot C_Timer.NewTimer for the next fade start
local _fadeDriver   -- throttled OnUpdate frame, shown only while fading
local _fadeEvents   -- REGEN watcher, created on first use
local _combatStart

local function FadeBase(e)
    return e._fadeBase or e.timestamp or 0
end

local function StopFadeClock()
    if _fadeTimer then _fadeTimer:Cancel(); _fadeTimer = nil end
    if _fadeDriver then _fadeDriver:Hide() end
end

-- Arms exactly one of: the fast driver (an icon is mid-fade) or a one-shot
-- timer for the next fade start. Out-of-combat only; entries are newest
-- first, so effective ages grow with the index and the scan can stop at
-- the first fully-faded entry.
local function ScheduleFade(fadeTime, maxIcons)
    StopFadeClock()
    local n = min(#_history, maxIcons)
    if n == 0 then return end
    local now = GetTime()
    local fading = false
    local nextIn
    for i = 1, n do
        local age = now - FadeBase(_history[i])
        if age < fadeTime then
            local d = fadeTime - age
            if not nextIn or d < nextIn then nextIn = d end
        elseif age < fadeTime + FADE_DUR then
            fading = true
            break
        else
            break
        end
    end
    if fading then
        if not _fadeDriver then
            _fadeDriver = CreateFrame("Frame")
            _fadeDriver:Hide()
            local acc = 0
            _fadeDriver:SetScript("OnUpdate", function(_, dt)
                acc = acc + dt
                if acc < 0.05 then return end
                acc = 0
                BuildIconStrip()
            end)
        end
        _fadeDriver:Show()
    elseif nextIn then
        _fadeTimer = C_Timer.NewTimer(nextIn + 0.02, BuildIconStrip)
    end
end

local function EnsureFadeEvents()
    if _fadeEvents then return end
    _fadeEvents = CreateFrame("Frame")
    _fadeEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
    _fadeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
    _fadeEvents:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _combatStart = GetTime()
            StopFadeClock()
        else
            local cs = _combatStart
            _combatStart = nil
            if (DB().iconFadeTime or 0) <= 0 then return end
            local now = GetTime()
            cs = cs or now
            for i = 1, #_history do
                local e = _history[i]
                local base = FadeBase(e)
                e._fadeBase = base + (now - max(cs, base))
            end
            BuildIconStrip()
        end
    end)
end

-- Plays a one-shot intro animation on an icon frame.
-- Uses dt-accumulated OnUpdate for smooth sub-frame interpolation.
-- Only called on icon 1, which always rests at CENTER of _iconStrip.
local function PlayIconAnim(ic, animType, dir, targetAlpha)
    local f = ic.frame
    targetAlpha = targetAlpha or 1

    -- Kill any in-progress animation and snap to rest position.
    -- Using hardcoded rest anchor (icon 1 = CENTER,0,0) instead of
    -- GetPoint, which returns mid-animation displacement on rapid casts.
    f:SetScript("OnUpdate", nil)
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER", _iconStrip, "CENTER", 0, 0)

    local p1, rel, relP, origX, origY = "CENTER", _iconStrip, "CENTER", 0, 0

    -- Compute starting displacement for slide types
    local dx, dy = 0, 0
    if animType == "slide" then
        if dir == "LEFT" then dx = ANIM_SLIDE_PX
        elseif dir == "RIGHT" then dx = -ANIM_SLIDE_PX
        elseif dir == "UP" then dy = -ANIM_SLIDE_PX
        else dy = ANIM_SLIDE_PX end
    end

    local isFly = (animType == "fly")
    local elapsed = 0
    local startAlpha = targetAlpha * 0.5

    f:SetAlpha(startAlpha)
    if isFly then f:SetScale(1.35) end
    if dx ~= 0 or dy ~= 0 then
        f:SetPoint(p1, rel, relP, origX + dx, origY + dy)
    end

    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = elapsed / ANIM_DUR
        if t >= 1 then t = 1 end

        local inv = 1 - t
        local ease = 1 - inv * inv * inv

        self:SetAlpha(startAlpha + (targetAlpha - startAlpha) * ease)

        if dx ~= 0 or dy ~= 0 then
            self:SetPoint(p1, rel, relP, origX + dx * (1 - ease), origY + dy * (1 - ease))
        end

        if isFly then
            self:SetScale(1.35 + (1 - 1.35) * ease)
        end

        if t >= 1 then
            self:SetAlpha(targetAlpha)
            self:SetScript("OnUpdate", nil)
            if isFly then self:SetScale(1) end
            if dx ~= 0 or dy ~= 0 then
                self:SetPoint(p1, rel, relP, origX, origY)
            end
        end
    end)
end

local function MakeIcon(parent)
    local ic = {}
    ic.frame = CreateFrame("Frame", nil, parent)
    ic.frame:EnableMouse(false)
    -- Shift+drag on any icon moves the entire strip
    ic.frame:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and IsShiftKeyDown() and _iconStrip then
            _iconStrip._dragging = true
            _iconStrip:StartMoving()
        end
    end)
    ic.frame:SetScript("OnMouseUp", function()
        if _iconStrip then
            _iconStrip._dragging = nil
            _iconStrip:StopMovingOrSizing()
            local left, top = _iconStrip:GetLeft(), _iconStrip:GetTop()
            if left and top then DB().iconPos = { x = left, y = top } end
            -- Shift may have been released during drag; disable mouse now
            if not IsShiftKeyDown() then
                _iconStrip:EnableMouse(false)
                for _, ic in ipairs(_iconPool) do ic.frame:EnableMouse(false) end
            end
        end
    end)
    local bg = ic.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    ic.bg = bg
    ic.tex = ic.frame:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints()
    local z = DB().iconZoom or 0.08
    ic.tex:SetTexCoord(z, 1 - z, z, 1 - z)
    ic.frame:Hide()
    return ic
end

-- Preview icons: random spells from the player's action bars
local _previewIcons
local function GetPreviewIcons()
    if _previewIcons then return _previewIcons end
    _previewIcons = {}
    -- Pull from action bars first (most recognizable spells)
    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and id > 0 then
            local tex = GetActionTexture(slot)
            if tex then
                -- Deduplicate
                local dup = false
                for _, t in ipairs(_previewIcons) do
                    if t == tex then dup = true; break end
                end
                if not dup then
                    _previewIcons[#_previewIcons + 1] = tex
                    if #_previewIcons >= 10 then break end
                end
            end
        end
    end
    -- Fallback if action bars returned nothing
    if #_previewIcons == 0 then
        _previewIcons = { 134400, 134400, 134400 }
    end
    return _previewIcons
end

BuildIconStrip = function()
    local sh = DB()
    if not sh.iconEnabled or ShouldHide(sh.iconHideInDungeon, sh.iconHideInRaid, sh.iconHideOutOfInstance) then
        if _iconStrip then _iconStrip:Hide() end
        StopFadeClock()
        return
    end

    if not _iconStrip then
        _iconStrip = CreateFrame("Frame", "EllesmereUIDMIconStrip", UIParent)
        _iconStrip:SetFrameStrata("MEDIUM")
        _iconStrip:SetFrameLevel(10)
        _iconStrip:SetClampedToScreen(true)
        _iconStrip:SetMovable(true)
        _iconStrip:EnableMouse(false)
        _iconStrip:SetScript("OnMouseDown", function(self, btn)
            if btn == "LeftButton" and IsShiftKeyDown() then
                self._dragging = true
                self:StartMoving()
            end
        end)
        _iconStrip:SetScript("OnMouseUp", function(self)
            self._dragging = nil
            self:StopMovingOrSizing()
            local left, top = self:GetLeft(), self:GetTop()
            if left and top then DB().iconPos = { x = left, y = top } end
            if not IsShiftKeyDown() then
                self:EnableMouse(false)
                for _, ic in ipairs(_iconPool) do ic.frame:EnableMouse(false) end
            end
        end)
        -- Click-through unless shift is held (strip + all icon children)
        local modFrame = CreateFrame("Frame")
        modFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
        modFrame:SetScript("OnEvent", function(_, _, key, down)
            if key == "LSHIFT" or key == "RSHIFT" then
                local on = (down == 1)
                -- Don't disable mouse mid-drag; let OnMouseUp end it naturally
                if not on and _iconStrip._dragging then return end
                _iconStrip:EnableMouse(on)
                for _, ic in ipairs(_iconPool) do
                    ic.frame:EnableMouse(on)
                end
            end
        end)
        -- Per-icon backgrounds (created in MakeIcon) travel with each icon
        -- during animation. No strip-level background needed.
    end

    local iconSz = PhysicalPixels(sh.iconSize or 24)
    local gap = PhysicalPixels(sh.iconSpacing or 1)
    local dir = sh.growDirection or "LEFT"
    local iconZoom = sh.iconZoom or 0.08

    local maxIcons = sh.iconCount or 5
    local histCount = min(#_history, maxIcons)

    -- Fade-out: out of combat, entries past fadeTime+FADE_DUR drop off the
    -- strip (newest first, so the scan stops at the first faded one) and the
    -- clock re-arms for whatever comes next. In combat nothing runs; the
    -- REGEN watcher restarts the clock. fadeNow doubles as the "fade math
    -- active" flag for the alpha pass in the icon loop below.
    local fadeTime = sh.iconFadeTime or 0
    local fadeNow
    if fadeTime > 0 then
        EnsureFadeEvents()
        if not InCombatLockdown() then
            fadeNow = GetTime()
            if histCount > 0 then
                local visible = 0
                for i = 1, histCount do
                    if fadeNow - FadeBase(_history[i]) < fadeTime + FADE_DUR then
                        visible = i
                    else
                        break
                    end
                end
                histCount = visible
            end
            ScheduleFade(fadeTime, maxIcons)
        end
    else
        StopFadeClock()
    end

    -- Preview placeholders never backfill slots vacated by faded icons.
    local showPreview = ns._optionsOpen and histCount < maxIcons
        and not (fadeTime > 0 and #_history > 0)
    local count = showPreview and maxIcons or histCount

    -- Nothing to show: hide the strip entirely
    if count == 0 then _iconStrip:Hide(); return end

    -- Position and size only on layout change (checked after count is known)
    local iconAlphaCheck = sh.iconOpacity or 1
    local needsLayout = (iconSz .. "|" .. gap .. "|" .. dir .. "|" .. count .. "|" .. iconAlphaCheck) ~= _iconLayoutKey
    if needsLayout then
        _iconStrip:SetSize(iconSz, iconSz)
        local pos = sh.iconPos
        if pos and pos.x and pos.y then
            _iconStrip:ClearAllPoints()
            _iconStrip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        elseif not _iconStrip._positioned then
            _iconStrip:ClearAllPoints()
            _iconStrip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            _iconStrip._positioned = true
        end
    end

    while #_iconPool < ICON_POOL_SIZE do
        _iconPool[#_iconPool + 1] = MakeIcon(_iconStrip)
    end

    -- Layout only changes when settings change; content changes every cast.
    local iconAlpha = iconAlphaCheck
    local layoutChanged = needsLayout
    local loopEnd = max(count, _lastIconCount or 0)

    for i = 1, loopEnd do
        local ic = _iconPool[i]
        if not ic then break end
        if i <= count then
            if ic._cachedZoom ~= iconZoom then
                ic._cachedZoom = iconZoom
                ic.tex:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)
            end
            if layoutChanged then
                ic.frame:SetScript("OnUpdate", nil)
                ic.frame:SetScale(1)
                ic.frame:SetSize(iconSz, iconSz)
                ic.frame:ClearAllPoints()
                local offset = (i - 1) * (iconSz + gap)
                if i == 1 then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, 0)
                elseif dir == "RIGHT" then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", offset, 0)
                elseif dir == "LEFT" then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", -offset, 0)
                elseif dir == "DOWN" then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, -offset)
                else
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, offset)
                end
                ic.frame:SetAlpha(iconAlpha)
                ic.frame:Show()
            end

            if i <= histCount then
                local entry = _history[i]
                -- Only update texture/color when entry changes
                if ic._cachedEntry ~= entry then
                    ic._cachedEntry = entry
                    if entry.icon then ic.tex:SetTexture(entry.icon) end
                    ic._cachedStatus = nil
                end
                local st = entry.status
                if ic._cachedStatus ~= st then
                    ic._cachedStatus = st
                    if st == "failed" or st == "interrupted" then
                        ic.tex:SetVertexColor(CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3], 1)
                    else
                        ic.tex:SetVertexColor(1, 1, 1, 1)
                    end
                    ic.tex:SetAlpha(1)
                end
                if fadeNow then
                    local age = fadeNow - FadeBase(entry)
                    if age > fadeTime then
                        local k = 1 - (age - fadeTime) / FADE_DUR
                        if k < 0 then k = 0 end
                        ic.frame:SetAlpha(iconAlpha * k)
                        ic._fading = true
                    elseif ic._fading then
                        ic.frame:SetAlpha(iconAlpha)
                        ic._fading = nil
                    end
                elseif ic._fading then
                    ic.frame:SetAlpha(iconAlpha)
                    ic._fading = nil
                end
            else
                if not ic._isPreview then
                    ic._isPreview = true
                    ic._cachedEntry = nil
                    local previews = GetPreviewIcons()
                    local pIdx = ((i - 1) % #previews) + 1
                    ic.tex:SetTexture(previews[pIdx])
                    ic.tex:SetVertexColor(1, 1, 1, 1)
                    ic.tex:SetAlpha(0.75)
                end
            end
            if i <= histCount then ic._isPreview = nil end
            if not layoutChanged then ic.frame:Show() end

            if i == 1 and histCount > 0 then
                local ts = _history[1].timestamp
                if ts ~= _lastAnimTimestamp then
                    _lastAnimTimestamp = ts
                    local animType = sh.iconAnimation or "slide"
                    if animType ~= "none" then
                        PlayIconAnim(ic, animType, dir, iconAlpha)
                    end
                end
            end
        else
            ic.frame:SetScript("OnUpdate", nil)
            ic.frame:SetScale(1)
            ic.frame:Hide()
        end
    end
    _lastIconCount = count
    if layoutChanged then
        _iconLayoutKey = iconSz .. "|" .. gap .. "|" .. dir .. "|" .. count .. "|" .. iconAlpha
    end

    _iconStrip:Show()
end

-------------------------------------------------------------------------------
--  BAR WINDOW  (standalone, matches DM window styling)
-------------------------------------------------------------------------------
local _barWin
local _barPool = {}
local _barScroll = 0
local _barFontCache = ""  -- tracks font changes to avoid per-bar SetFont calls
local _barLayoutCache = "" -- tracks layout changes (barH, spacing, texture)
local _lastBarVisible = 0 -- tracks visible bar count for minimal loop

local function MakeHistoryBar(parent)
    local bar = {}
    bar.row = CreateFrame("Frame", nil, parent)
    bar.row:SetHeight(18)

    -- Icon anchored to row left; fill starts right of icon
    bar.icon = bar.row:CreateTexture(nil, "OVERLAY")
    bar.icon:SetSize(18, 18)
    bar.icon:SetPoint("LEFT", bar.row, "LEFT", 0, 0)
    local z = DB().iconZoom or 0.08
    bar.icon:SetTexCoord(z, 1 - z, z, 1 - z)

    bar.fill = CreateFrame("StatusBar", nil, bar.row)
    bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 0, 0)
    bar.fill:SetPoint("BOTTOMRIGHT", bar.row, "BOTTOMRIGHT", 0, 0)
    bar.fill:SetMinMaxValues(0, 1)
    bar.fill:SetValue(1)
    bar.fill:SetStatusBarTexture(BAR_TEX)

    local tf = CreateFrame("Frame", nil, bar.fill)
    tf:SetAllPoints(bar.fill)
    tf:SetFrameLevel(bar.fill:GetFrameLevel() + 2)

    local sh = DB()
    local fs = sh.textSize or 11

    bar.label = tf:CreateFontString(nil, "OVERLAY")
    bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(false)
    SetFont(bar.label, fs)

    bar.rightText = tf:CreateFontString(nil, "OVERLAY")
    bar.rightText:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
    bar.rightText:SetJustifyH("RIGHT")
    bar.rightText:SetWordWrap(false)
    SetFont(bar.rightText, fs)

    bar.label:SetPoint("RIGHT", bar.rightText, "LEFT", -4, 0)

    bar.row:Hide()
    return bar
end

local MEDIA       = "Interface\\AddOns\\EllesmereUIDamageMeters\\Media\\"
local RESIZE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png"
local MIN_W, MIN_H = 150, 80

local function BuildBarWindow()
    local sh = DB()
    local dmCfg = ns.EDM.DB()
    if not sh.barEnabled or ShouldHide(sh.barHideInDungeon, sh.barHideInRaid, sh.barHideOutOfInstance) then
        if _barWin then _barWin:Hide() end
        return
    end

    if not _barWin then
        local frame = CreateFrame("Frame", "EllesmereUIDMBarHistory", UIParent)
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:SetFrameStrata("MEDIUM")
        frame:EnableMouse(false)
        frame._visSlots = 1
        frame._locked = sh.barLocked or false
        frame._isHovered = false
        _barWin = frame

        frame._bg = frame:CreateTexture(nil, "BACKGROUND")
        frame._bg:SetAllPoints()

        -- Header
        local hdr = CreateFrame("Frame", nil, frame)
        hdr:SetHeight(22)
        hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
        hdr:SetFrameLevel(frame:GetFrameLevel() + 5)
        hdr:EnableMouse(true)
        frame._hdr = hdr

        local hdrBg = hdr:CreateTexture(nil, "BACKGROUND")
        hdrBg:SetAllPoints()
        frame._hdrBg = hdrBg

        local title = hdr:CreateFontString(nil, "OVERLAY")
        title:SetPoint("LEFT", hdr, "LEFT", 6, 0)
        SetFont(title, 11)
        title:SetText("Spell History")
        frame._title = title

        -- Header icons (right-aligned, matching DM window style)
        local ICON_A = 0.4
        local ICON_HA = 0.9
        local btnSize = 22
        local btnPad = -2

        local function MakeHdrBtn(texFile, xOff, tooltip, onClick)
            local btn = CreateFrame("Button", nil, hdr)
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("RIGHT", hdr, "RIGHT", xOff, 0)
            btn:SetFrameLevel(hdr:GetFrameLevel() + 2)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture(texFile)
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 1, 1, ICON_A)
            btn:SetScript("OnEnter", function()
                icon:SetVertexColor(1, 1, 1, ICON_HA)
                if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(btn, tooltip) end
            end)
            btn:SetScript("OnLeave", function()
                icon:SetVertexColor(1, 1, 1, ICON_A)
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
            btn:SetScript("OnClick", function()
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                onClick(btn)
            end)
            btn._icon = icon
            return btn
        end

        -- Btn 1 (rightmost): Settings
        MakeHdrBtn(MEDIA .. "dm_settings.png", -(btnPad + 2), "Settings", function()
            if ns._optionsOpen then
                if EUI.Hide then EUI:Hide() end
                return
            end
            if EUI.ShowModule then
                EUI:ShowModule("EllesmereUIDamageMeters")
                C_Timer.After(0, function()
                    if EUI.SelectPage then EUI:SelectPage("Spell History") end
                end)
            end
        end)

        -- Btn 2: Lock/Unlock
        local lockBtnHdr = MakeHdrBtn(
            frame._locked and (MEDIA .. "dm_locked_top.png") or (MEDIA .. "dm_unlock_top.png"),
            -(btnSize + btnPad * 2 + 2), frame._locked and "Locked" or "Unlocked",
            function()
                frame._locked = not frame._locked
                DB().barLocked = frame._locked
                frame._lockBtn._icon:SetTexture(frame._locked and (MEDIA .. "dm_locked_top.png") or (MEDIA .. "dm_unlock_top.png"))
            end
        )
        frame._lockBtn = lockBtnHdr
        lockBtnHdr:SetScript("OnEnter", function()
            lockBtnHdr._icon:SetVertexColor(1, 1, 1, ICON_HA)
            if EUI.ShowWidgetTooltip then
                EUI.ShowWidgetTooltip(lockBtnHdr, frame._locked and "Locked" or "Unlocked")
            end
        end)

        -- Btn 3: Resize (width drag)
        local resizeBtnHdr = MakeHdrBtn(MEDIA .. "dm_width_resize.png", -(btnSize * 2 + btnPad * 3 + 2), "Resize Width", function() end)
        -- Override: drag to resize width
        local resizeStartX, resizeStartW
        local resizeFrame = CreateFrame("Frame")
        resizeFrame:Hide()
        resizeFrame:SetScript("OnUpdate", function()
            if not frame._resizing then return end
            local cx = GetCursorPosition()
            local es = frame:GetEffectiveScale()
            frame:SetWidth(max(MIN_W, resizeStartW + (cx / es - resizeStartX)))
        end)
        resizeBtnHdr:SetScript("OnMouseDown", function(_, btn)
            if btn ~= "LeftButton" or frame._locked then return end
            local left, top = frame:GetLeft(), frame:GetTop()
            if left and top then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            local cx = GetCursorPosition()
            resizeStartX = cx / frame:GetEffectiveScale()
            resizeStartW = frame:GetWidth()
            frame._resizing = true
            resizeFrame:Show()
        end)
        resizeBtnHdr:SetScript("OnMouseUp", function(_, btn)
            if btn ~= "LeftButton" or not frame._resizing then return end
            frame._resizing = false
            resizeFrame:Hide()
            DB().barWidth = floor(frame:GetWidth() + 0.5)
        end)

        -- Header drag
        hdr:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" and not frame._locked then frame:StartMoving() end
        end)
        hdr:SetScript("OnMouseUp", function()
            frame:StopMovingOrSizing()
            local l, t = frame:GetLeft(), frame:GetTop()
            if l and t then DB().barPos = { x = l, y = t } end
        end)

        -- Content (click-through, mouse wheel only)
        local content = CreateFrame("Frame", nil, frame)
        content:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
        content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        content:EnableMouse(false)
        frame._content = content

        content:EnableMouseWheel(true)
        content:SetScript("OnMouseWheel", function(_, delta)
            local maxS = max(0, #_history - (frame._visSlots or 1))
            _barScroll = max(0, min(_barScroll - delta, maxS))
            RefreshBarWindow()
        end)

    end

    -- Apply styling (bg from spell history settings, header from DM settings)
    _barWin._bg:SetColorTexture(sh.bgR or 0, sh.bgG or 0, sh.bgB or 0, sh.bgAlpha or 0.25)

    local hc = dmCfg.hdrBgColor
    local hR, hG, hB = hc and hc.r or 0x1B/255, hc and hc.g or 0x1B/255, hc and hc.b or 0x1B/255
    _barWin._hdrBg:SetColorTexture(hR, hG, hB, dmCfg.hdrBgAlpha or 1)

    local tR, tG, tB
    if dmCfg.hdrTextUseAccent ~= false then tR, tG, tB = GetAccentRGB()
    else local tc = dmCfg.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
    _barWin._title:SetTextColor(tR, tG, tB, 1)

    -- Hide/show top bar
    local hideTop = sh.hideTopBar
    if hideTop then _barWin._hdr:Hide() else _barWin._hdr:Show() end
    _barWin._content:ClearAllPoints()
    if hideTop then
        _barWin._content:SetPoint("TOPLEFT", _barWin, "TOPLEFT", 0, 0)
    else
        _barWin._content:SetPoint("TOPLEFT", _barWin._hdr, "BOTTOMLEFT", 0, 0)
    end
    _barWin._content:SetPoint("BOTTOMRIGHT", _barWin, "BOTTOMRIGHT", 0, 0)

    -- Size: width from DB, height auto-calculated from maxBars
    local hdrH = hideTop and 0 or 22
    local maxBars = sh.maxBars or 5
    local barH = PhysicalPixels(sh.shBarHeight or 18)
    local barSp = PhysicalPixels(dmCfg.barSpacing or 2)
    local autoH = hdrH + maxBars * (barH + barSp)
    _barWin:SetSize(sh.barWidth or 300, autoH)
    _barWin._locked = sh.barLocked or false
    local pos = sh.barPos
    if pos and pos.x and pos.y then
        _barWin:ClearAllPoints()
        _barWin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    elseif not _barWin._positioned then
        _barWin:ClearAllPoints()
        _barWin:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        _barWin._positioned = true
    end

    while #_barPool < BAR_POOL_SIZE do
        _barPool[#_barPool + 1] = MakeHistoryBar(_barWin._content)
    end

    _barWin:Show()
    RefreshBarWindow()
end

RefreshBarWindow = function()
    if not _barWin or not _barWin:IsShown() then return end

    local dmCfg = ns.EDM.DB()
    local sh = DB()
    local barH = PhysicalPixels(sh.shBarHeight or 18)
    local barSp = PhysicalPixels(dmCfg.barSpacing or 2)
    local stride = barH + barSp
    local texPath = GetBarTexturePath()
    local fontSize = sh.textSize or 11
    local content = _barWin._content
    local frameH = content:GetHeight()
    local visSlots = max(1, floor(frameH / stride + 0.5))
    _barWin._visSlots = visSlots

    -- Text color from spell history settings
    local txR, txG, txB
    if sh.textColorUseAccent then txR, txG, txB = GetAccentRGB()
    else local tc = sh.textColor; txR = tc and tc.r or 1; txG = tc and tc.g or 1; txB = tc and tc.b or 1 end

    -- Re-apply fonts to ALL pool bars when settings change (not just visible ones)
    local fontKey = fontSize .. "|" .. GetDMFont() .. "|" .. GetDMOutline()
    local fontChanged = (fontKey ~= _barFontCache)
    if fontChanged then
        _barFontCache = fontKey
        for fi = 1, #_barPool do
            SetFont(_barPool[fi].label, fontSize)
            SetFont(_barPool[fi].rightText, fontSize)
        end
    end

    -- Precompute normal bar color outside loop (OutcomeColor calls DB per bar)
    local nR, nG, nB = OutcomeColor("success")
    local barAlpha = sh.barOpacity or 1
    local stR, stG, stB = CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3]

    local total = min(#_history, sh.maxBars or 5)
    local loopEnd = max(visSlots, _lastBarVisible)
    local barIconZoom = sh.iconZoom or 0.08

    -- Layout key: only rebuild positions/sizes when settings change
    local layoutKey = barH .. "|" .. barSp .. "|" .. texPath
    local layoutChanged = (layoutKey ~= _barLayoutCache)
    if layoutChanged then _barLayoutCache = layoutKey end

    for i = 1, loopEnd do
        local bar = _barPool[i]
        if not bar then break end
        local idx = _barScroll + i
        if i <= visSlots and idx <= total then
            local entry = _history[idx]

            if bar._cachedZoom ~= barIconZoom then
                bar._cachedZoom = barIconZoom
                bar.icon:SetTexCoord(barIconZoom, 1 - barIconZoom, barIconZoom, 1 - barIconZoom)
            end

            -- Layout: only on settings change or slot reuse
            if layoutChanged or bar._cachedSlot ~= i then
                bar._cachedSlot = i
                local y = -(i - 1) * stride
                bar.row:ClearAllPoints()
                bar.row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                bar.row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
                bar.row:SetHeight(barH)
                bar.fill:SetStatusBarTexture(texPath)
                bar.icon:SetSize(barH, barH)
                bar._cachedEntry = nil -- force content rebuild
            end

            -- Content: only when entry changes
            if bar._cachedEntry ~= entry then
                bar._cachedEntry = entry
                if entry.icon then bar.icon:SetTexture(entry.icon); bar.icon:Show()
                else bar.icon:Hide() end
                bar.label:SetText(entry.spellName or "?")
                bar._cachedStatus = nil -- force color/fill rebuild
                bar._cachedFillDone = nil -- force fill value reset
            end

            -- Color + fill: update when status changes or on active casts
            local status = entry.status
            if bar._cachedStatus ~= status then
                bar._cachedStatus = status
                local cr, cg, cb
                if status == "failed" or status == "interrupted" then
                    cr, cg, cb = stR, stG, stB
                else
                    cr, cg, cb = nR, nG, nB
                end
                bar.fill:SetStatusBarColor(cr, cg, cb, barAlpha)
            end

            -- Fill value: always set for active casts, once for finished
            if entry.fillProgress then
                bar.fill:SetValue(entry.fillProgress)
            elseif status == "casting" or status == "channeling" then
                local now = GetTime()
                local dur = entry.endTime - entry.startTime
                if dur > 0 then
                    local progress = status == "channeling"
                        and (entry.endTime - now) / dur
                        or  (now - entry.startTime) / dur
                    bar.fill:SetValue(min(max(progress, 0), 1))
                else
                    bar.fill:SetValue(1)
                end
            elseif not bar._cachedFillDone then
                bar._cachedFillDone = true
                bar.fill:SetValue(1)
            end

            -- Text color: only on settings change
            if layoutChanged or not bar._cachedTxColor then
                bar._cachedTxColor = true
                bar.label:SetTextColor(txR, txG, txB, 1)
                bar.rightText:SetTextColor(txR, txG, txB, 1)
            end

            bar.rightText:SetText(BuildRightText(entry))
            bar.row:Show()
        else
            if bar then
                bar.row:Hide()
                bar._cachedSlot = nil; bar._cachedEntry = nil; bar._cachedStatus = nil
                bar._cachedFillDone = nil; bar._cachedTxColor = nil
            end
        end
    end
    _lastBarVisible = visSlots
end

-------------------------------------------------------------------------------
--  Active-cast fill animation
--  Only runs while there are pending (in-progress) casts to animate.
--  Stops itself when all casts resolve.  Zero cost when idle.
-------------------------------------------------------------------------------
-- Lightweight per-frame updater: only touches fill values + right text on
-- bars with active casts.  Full RefreshBarWindow runs on PushEntry/Finish.
local _castAnimFrame = CreateFrame("Frame")
_castAnimFrame:Hide()
_castAnimFrame:SetScript("OnUpdate", function(self)
    if not next(_pendingCasts) then self:Hide(); return end
    if not _barWin or not _barWin:IsShown() then return end
    local now = GetTime()
    local visSlots = _barWin._visSlots or 5
    local scroll = _barScroll or 0
    for i = 1, min(visSlots, BAR_POOL_SIZE) do
        local idx = scroll + i
        local entry = _history[idx]
        if not entry then break end
        local status = entry.status
        if status == "casting" or status == "channeling" then
            local bar = _barPool[i]
            if bar and bar.row:IsShown() then
                local dur = entry.endTime - entry.startTime
                if dur > 0 then
                    local progress = status == "channeling"
                        and (entry.endTime - now) / dur
                        or  (now - entry.startTime) / dur
                    bar.fill:SetValue(min(max(progress, 0), 1))
                end
                bar.rightText:SetText(BuildRightText(entry))
            end
        end
    end
end)

StartCastAnim = function() _castAnimFrame:Show() end
local function StopCastAnim()  _castAnimFrame:Hide() end

-------------------------------------------------------------------------------
--  Public API
-------------------------------------------------------------------------------
function ns.ApplySpellHistory()
    local sh = DB()
    local active = sh.iconEnabled or sh.barEnabled

    -- Dynamic event registration: zero overhead when disabled
    if active then RegisterEvents() else UnregisterEvents(); StopCastAnim() end

    if sh.iconEnabled then BuildIconStrip()
    elseif _iconStrip then _iconStrip:Hide() end

    if sh.barEnabled then BuildBarWindow()
    elseif _barWin then _barWin:Hide() end
end

function ns.ClearSpellHistory()
    wipe(_history)
    wipe(_pendingCasts)
    wipe(_pendingTargets)
    _activeChannelSpell = nil
    ns.ApplySpellHistory()
end

-------------------------------------------------------------------------------
--  Init (deferred to PLAYER_LOGIN so DM DB is ready)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0.1, function()
        _shDB = nil  -- force defaults merge on first access
        ns.ApplySpellHistory()
    end)
end)

-- Re-evaluate visibility when entering/leaving instances; refresh preview on spec change
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
zoneFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then _previewIcons = nil end
    if ns.ApplySpellHistory then ns.ApplySpellHistory() end
end)
