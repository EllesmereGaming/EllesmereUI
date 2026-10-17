if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Format.lua
--
--  Fonts, bar textures, row metrics, number and name formatting, source
--  keys, timer text, class icons and the per-target lists.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local BAR_TEX, DB, _deathStamps = I.BAR_TEX, I.DB, I._deathStamps
local _targetsCache, CleanupFeignCache = I._targetsCache, I.CleanupFeignCache
local GetCurrentViewDuration = I.GetCurrentViewDuration

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _inCombat = I._inCombat
I.inCombatSetters[#I.inCombatSetters + 1] = function(v) _inCombat = v end
local StartSharedTicker
I.startSharedTickerSetters[#I.startSharedTickerSetters + 1] = function(v) StartSharedTicker = v end
local _sharedTicker
I.sharedTickerSetters[#I.sharedTickerSetters + 1] = function(v) _sharedTicker = v end

local function SetDMFont(fs, size, flagsOverride, fontOverride)
    EllesmereUI.ApplyModuleFont(fs, fontOverride, size, "damageMeters", flagsOverride)
end

-- Accent color helper
local function GetAccentRGB()
    local EG = EUI.ELLESMERE_GREEN
    if EG then return EG.r, EG.g, EG.b end
    return EUI.DEFAULT_ACCENT_R or 12/255,
           EUI.DEFAULT_ACCENT_G or 210/255,
           EUI.DEFAULT_ACCENT_B or 157/255
end
-- A header title's "Use Accent" colour: WoW Forever's gold under the variant
-- (its kit carries no EllesmereUI accent), the accent otherwise.
function ns.DMTitleRGB()
    if ns.DMForever() then local c = ns.DM_FV.gold; return c.r, c.g, c.b end
    return GetAccentRGB()
end

-- Bar texture tables
local DM_BAR_TEXTURES, DM_BAR_TEXTURE_NAMES, DM_BAR_TEXTURE_ORDER =
    EllesmereUI.BuildBarTextureTables(true)
-- Meter-only extra entry, second in the list: the game's own bar fill (the
-- vanilla status bar), pointed at directly so it needs no SharedMedia
-- registration; Classic WoW UI seeds it.
DM_BAR_TEXTURES["blizzard"]      = "Interface\\TargetingFrame\\UI-StatusBar"
DM_BAR_TEXTURE_NAMES["blizzard"] = "Blizzard"
table.insert(DM_BAR_TEXTURE_ORDER, 2, "blizzard")
_G._EDM_BarTextures     = DM_BAR_TEXTURES
_G._EDM_BarTextureOrder = DM_BAR_TEXTURE_ORDER
_G._EDM_BarTextureNames = DM_BAR_TEXTURE_NAMES

local function AppendDMSharedMedia()
    if not EUI.AppendSharedMediaTextures then return end
    EUI.AppendSharedMediaTextures(
        DM_BAR_TEXTURE_NAMES,
        DM_BAR_TEXTURE_ORDER,
        nil,
        DM_BAR_TEXTURES
    )
end

local function GetBarTexturePath()
    local cfg = DB()
    local key = cfg and cfg.barTexture or "none"
    return EUI.ResolveTexturePath(DM_BAR_TEXTURES, key, BAR_TEX), key
end

local function GetBreakdownBarTexturePath()
    local cfg = DB()
    local key = cfg and cfg.breakdownBarTexture
    if not key or key == "match" then
        key = cfg and cfg.barTexture or "none"
    end
    return EUI.ResolveTexturePath(DM_BAR_TEXTURES, key, BAR_TEX), key
end

-- Thin-line overlay: a hairline bar at the top/bottom edge of a StatusBar. Hooks bar.fill's color/value setters to forward to the overlay when active, instead of touching every call site.
local THIN_LINE_KEYS = { ["thin-line-top"] = "TOP", ["thin-line-bottom"] = "BOTTOM" }
local THIN_LINE_PX = 1

local function SetupThinLine(fill, edge)
    if not fill._thinLine then
        local tl = CreateFrame("StatusBar", nil, fill)
        tl:SetStatusBarTexture(BAR_TEX)
        fill._thinLine = tl
        -- Hook SetStatusBarColor to forward to overlay
        local origSSBC = fill.SetStatusBarColor
        fill.SetStatusBarColor = function(self, r, g, b, a)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetStatusBarColor(r, g, b, a)
                origSSBC(self, 0, 0, 0, 0)
            else
                origSSBC(self, r, g, b, a)
            end
        end
        -- Hook SetMinMaxValues + SetValue to sync overlay
        local origSMMV = fill.SetMinMaxValues
        fill.SetMinMaxValues = function(self, lo, hi)
            origSMMV(self, lo, hi)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetMinMaxValues(lo, hi)
            end
        end
        local origSV = fill.SetValue
        fill.SetValue = function(self, v)
            origSV(self, v)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetValue(v)
            end
        end
    end
    local tl = fill._thinLine
    local PP = EUI and EUI.PP
    local px = THIN_LINE_PX * ((PP and PP.mult) or 1)
    tl:ClearAllPoints()
    if edge == "TOP" then
        tl:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
        tl:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    else
        tl:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        tl:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    tl:SetHeight(px)
    tl:Show()
    fill._thinLineActive = true
end

local function ClearThinLine(fill)
    if not fill._thinLineActive then return end
    fill._thinLineActive = false
    if fill._thinLine then fill._thinLine:Hide() end
    -- Thin-line mode left the fill transparent; reset to opaque so the bar is visible immediately (RefreshUI applies the real color)
    fill:SetStatusBarColor(1, 1, 1, 1)
end

local function ApplyBarTexture(fill, texPath, texKey)
    -- Blizzard Style: the user's texture as below, plus the stock bevel over
    -- it (strips on the fill, independent of the texture path). Classic WoW
    -- UI bars are plain rectangles: no strips.
    if ns.DMStyle() == "blizzard" then ns.DMApplyBlizzFill(fill) end
    local edge = THIN_LINE_KEYS[texKey]
    if edge then
        fill:SetStatusBarTexture(BAR_TEX)
        SetupThinLine(fill, edge)
    else
        fill:SetStatusBarTexture(texPath)
        ClearThinLine(fill)
    end
end

-- Physical pixel spacing: convert user values to physical pixels (user setting = physical pixel count).
-- Snapped through PP.Scale so accumulated row offsets (stride * index) don't drift off the pixel
-- grid from float dust -- without this, a spacing of 1 can round to 0px on some rows and 2px on others.
local function PhysicalPixels(userValue)
    local PP = EUI and EUI.PP
    local mult = (PP and PP.mult) or 1
    local value = (userValue or 0) * mult
    if PP and PP.Scale then return PP.Scale(value) end
    return value
end

-- Row geometry with both terms on ONE pixel grid. barHeight and barSpacing are
-- both coordinate units, like the window width and fonts, so bars keep their
-- proportion to the window at any UI scale and a shared profile renders the
-- same relative size for everyone. Both are snapped against the same effective
-- scale: a stride between two grids drifts down the list (-((i-1) * stride)),
-- rendering a spacing of 1 as 0px on some rows and 2px on others.
-- Returns barH, barSp, stride and one physical pixel, in coordinate units.
local function RowMetrics(height, spacingCoord, es)
    local PP = EUI and EUI.PP
    if PP and PP.perfect and PP.SnapForES then
        if not es or es <= 0 then es = (UIParent and UIParent:GetEffectiveScale()) or 1 end
        local barH = PP.SnapForES(height or 18, es)
        local barSp = PP.SnapForES(spacingCoord or 2, es)
        return barH, barSp, barH + barSp, PP.perfect / es
    end
    local barH, barSp = height or 18, spacingCoord or 2
    return barH, barSp, barH + barSp, (PP and PP.mult) or 1
end
-- On ns as well: CreateDMWindow sits at Lua 5.1's 60-upvalue cap, so its call
-- sites reach the helper through ns (already one of its upvalues).
ns._RowMetrics = RowMetrics

-- Number formatting: delegates to the shared EllesmereUI_NumberFormat.lua engine
-- (breakpoint tables, the CJK wan/yi grouping tables and the
-- AbbreviateNumbers/CreateAbbreviateConfig plumbing all live there now,
-- shared with EllesmereUIDataBars' gold abbreviation).
local _forceEnglishUnits = false

-- Re-read the saved setting: once at load (DB not ready yet -> reads false),
-- once after DB creation, and on every options toggle flip.
local function RebuildAbbrevCfg()
    _forceEnglishUnits = false
    if ns.EDM and ns.EDM.DB then
        local db = ns.EDM.DB()
        if db and db.forceEnglishUnits then _forceEnglishUnits = true end
    end
end
RebuildAbbrevCfg()
ns.RebuildNumberFormat = RebuildAbbrevCfg

local function AbbrevNumber(n)
    if n == nil then return "0" end
    return EllesmereUI.AbbreviateNumber(n, _forceEnglishUnits)
end

local function FormatBarValue(amt, perSec, numFmt)
    -- Per-second can drop below 1 on long Overall windows (dumps the raw float); clamp to a min of 1, but only for a plain number -- never compare a secret value (secret sessions are short, so perSec is never sub-1 anyway)
    if perSec ~= nil and (not issecretvalue or not issecretvalue(perSec)) then
        if perSec < 1 then perSec = 1 end
    end
    if numFmt == 0 then
        return AbbrevNumber(perSec)
    end
    if numFmt == 2 and perSec then
        return format("%s (%s)", AbbrevNumber(amt), AbbrevNumber(perSec))
    end
    if numFmt == 3 and perSec then
        return format("%s | %s", AbbrevNumber(amt), AbbrevNumber(perSec))
    end
    return AbbrevNumber(amt)
end

-- A combatant's name without its realm. On WoW Forever the Name Format
-- (dm.nameFormat, the Left Text cog) then keeps a PLAYER's first or last name:
-- src is the meter row the name belongs to (a player has a class, no creature
-- id and is no Threat list pet; the Pull Aggro line has no class), attacker an
-- Enemy Damage Taken attacker (AggregateEnemyPlayers: a class, neither pet nor
-- mob); with neither, the name is only stripped. Your own row (isLocalPlayer
-- is never secret) always takes your name from your unit, so it reads the same
-- in and out of combat; any other secret name (combat) cannot be split and
-- shows whole. ForeverShortName is nil off Forever, so src and attacker are
-- never read there.
local ForeverShortName = EUI.ForeverShortName
local function StripRealm(name, src, attacker)
    if not name then return "Unknown" end
    if Ambiguate then name = Ambiguate(name, "short") or name end
    if not (ForeverShortName and (src or attacker)) then return name end
    local player
    if not src then
        local cls = attacker.class
        player = cls ~= nil and cls ~= "" and not attacker.isPet and not attacker.isMob
    else
        local own = src.isLocalPlayer
        if own ~= nil and not issecretvalue(own) and own == true then
            local mode = DB().nameFormat
            if not mode then return name end
            return ForeverShortName(EUI.WithSurname(UnitName("player")), mode) or name
        end
        if issecretvalue(name) then return name end
        local cls = src.classFilename
        player = cls ~= nil and cls ~= "" and src.sourceCreatureID == nil and not src.threatPet
    end
    if not player then return name end
    local mode = DB().nameFormat
    if mode then return ForeverShortName(name, mode) end
    return name
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Is this bar the local player's? isLocalPlayer is documented NeverSecret, so
-- the read is legal mid-combat -- but a doc being wrong must degrade to "not
-- own" (the row stays blocked, today's behavior), never to a thrown compare.
local function IsOwnRow(src)
    local own = src and src.isLocalPlayer
    if own == nil or IsSecret(own) then return false end
    return own == true
end
-- On ns as well: CreateDMWindow sits at Lua 5.1's 60-upvalue cap, so it
-- re-reads both helpers through ns (already one of its upvalues) instead of
-- spending two upvalues of its own.
ns._IsSecret, ns._IsOwnRow = IsSecret, IsOwnRow

-- Resolve a group member's row to a PLAIN guid. Field truth (three debug
-- rounds): in combat the row's `name` and `sourceGUID` are SECRET (the
-- header only renders the name because engine sinks accept secrets) while
-- `classFilename` + `specIconID` are NeverSecret -- and OUT of combat the
-- whole source list reads plain. Group TOKEN reads (UnitGUID/name) stay
-- plain even in combat, but they cannot be JOINED to a row through a secret
-- name. So the bridge is CLASS+SPECICON: out of combat the session's own
-- sources are snapshotted into key "CLASS:specIconID" -> guid (a duplicate
-- key banks FALSE = ambiguous, honest block for e.g. two same-spec
-- players), and the in-combat resolver joins the row's two NeverSecret
-- fields against that snapshot. Guids never change for a player, so
-- pre-combat snapshots stay correct all fight; sources first seen only
-- mid-combat resolve after it ends.
local _srcKeyGuid = {}
-- The group-row resolve channel runs in DUNGEONS ONLY (user rule). Raids
-- mostly ambiguous-block anyway (duplicate specs collapse the class:spec
-- key), while the Overall harvest walk and its session fetch scale with
-- source count; outside instanced parties there is no group audience worth
-- the fetches. Own-row breakdowns and death recaps are separate lanes and
-- keep working everywhere (every caller checks IsOwnRow first).
local function AllyResolveZone()
    local _, instType = IsInInstance()
    return instType == "party"
end
local function SnapshotSourceKeys()
    if not AllyResolveZone() then return end
    -- Declassification LAGS regen (field-confirmed: a post-combat snapshot
    -- banked only the own row): while the Combat addon-restriction is still
    -- active the source list reads partially secret. Skip WITHOUT wiping so
    -- the previous good snapshot survives the lag window; the
    -- ADDON_RESTRICTION_STATE_CHANGED lift edge re-runs this at the exact
    -- declassified moment (the probe reads false during that dispatch by
    -- documented design).
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
       and Enum.AddOnRestrictionType
       and C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat) then
        return
    end
    -- ADDITIVE, never wiped here: guids are valid for the whole run, and the
    -- Current session ROLLS after each pull -- a refresh against the fresh
    -- (empty) session must not empty the map ("worked once then never
    -- again" was exactly that). The roster branch owns the wipe; Overall is
    -- harvested because it stays populated for the entire run.
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
    if not ok or not s or not s.combatSources then return end
    for _, src in ipairs(s.combatSources) do
        local g, cls, ic = src.sourceGUID, src.classFilename, src.specIconID
        if g and cls and ic
           and not (IsSecret(g) or IsSecret(cls) or IsSecret(ic))
           and type(cls) == "string" and type(ic) == "number" then
            local key = cls .. ":" .. ic
            if _srcKeyGuid[key] ~= nil and _srcKeyGuid[key] ~= g then
                _srcKeyGuid[key] = false   -- two sources share the key: ambiguous
            else
                _srcKeyGuid[key] = g
            end
        end
    end
end
ns._SnapshotSourceKeys = SnapshotSourceKeys
local function ResolveGroupGUID(src)
    if not src then return nil end
    if not AllyResolveZone() then return nil end
    -- Out of combat the callers' row guids are plain and the gates never
    -- fire, so a resolve call here is a cheap chance to refresh the
    -- snapshot instead (one session fetch at hover edge cadence).
    if not InCombatLockdown() then SnapshotSourceKeys() end
    local cls, ic = src.classFilename, src.specIconID
    if not cls or not ic or IsSecret(cls) or IsSecret(ic) then return nil end
    if type(cls) ~= "string" or type(ic) ~= "number" then return nil end
    local g = _srcKeyGuid[cls .. ":" .. ic]
    if g == false then return nil end
    return g
end
ns._ResolveGroupGUID = ResolveGroupGUID

local function FormatTimer(seconds)
    if not seconds or (issecretvalue and issecretvalue(seconds)) then return "0:00" end
    return format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Deaths row time text. Plain deathTimeSeconds wins; a secret one (in combat)
-- falls back to the placeholder stamped when the row first appeared. Published
-- on ns: CreateDMWindow sits at the 60-upvalue cap and already holds ns.
function ns._DeathTimeText(src, live)
    local t = src.deathTimeSeconds
    if t ~= nil and not (issecretvalue and issecretvalue(t)) then
        return FormatTimer(t)
    end
    local rid = src.deathRecapID
    if not rid or (issecretvalue and issecretvalue(rid)) then return "0:00" end
    local st = _deathStamps[rid]
    if not st then
        -- Only the LIVE Current view may stamp: a past segment viewed during
        -- the next pull is secret too, and its deaths must not borrow this
        -- pull's clock.
        if not (_inCombat and live) then return "0:00" end
        st = GetCurrentViewDuration()
        -- 0 = no live duration yet; leave unstamped so a later refresh can.
        if not st or st <= 0 then return "0:00" end
        _deathStamps[rid] = st
    end
    return FormatTimer(st)
end

-- A hidden window never paints, but a Deaths row's in-combat time is stamped on first
-- sight and the feign cache only drops a GUID it sees at 0 HP: a hidden Deaths window
-- keeps both moving without a paint, so it reads right the moment it shows. On ns:
-- CreateDMWindow sits at the 60-upvalue cap.
function ns._DMHiddenDeathsPass(w)
    if not _inCombat or w.curDMType ~= Enum.DamageMeterType.Deaths then return end
    CleanupFeignCache()
    -- Only the live Current view stamps (see ns._DeathTimeText)
    if w.curSessionID or w.curSession ~= Enum.DamageMeterSessionType.Current then return end
    -- A window switched onto this view while the ticks were off (combat-start auto-Current)
    if not _sharedTicker then StartSharedTicker() end
    local s = C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
    local srcs = s and s.combatSources
    if not srcs then return end
    for i = 1, #srcs do
        local src = srcs[i]
        local rid, t = src.deathRecapID, src.deathTimeSeconds
        -- A readable death time needs no stamp.
        if rid and not (issecretvalue and issecretvalue(rid)) and rid > 0 and not _deathStamps[rid]
           and (t == nil or (issecretvalue and issecretvalue(t))) then
            ns._DeathTimeText(src, true)
        end
    end
end

local function FormatTimerDecimal(seconds)
    if not seconds or (issecretvalue and issecretvalue(seconds)) then return "0:00.0" end
    return format("%d:%02d.%d", math.floor(seconds / 60), math.floor(seconds % 60),
        math.floor((seconds * 10) % 10))
end

local function GetBreakdownDuration(session, sessionID)
    if sessionID then
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local sess = C_DamageMeter.GetAvailableCombatSessions()
            if sess then
                for _, s in ipairs(sess) do
                    if s.sessionID == sessionID and type(s.durationSeconds) == "number" and not (issecretvalue and issecretvalue(s.durationSeconds)) then
                        return s.durationSeconds
                    end
                end
            end
        end
    elseif session == Enum.DamageMeterSessionType.Current then
        return GetCurrentViewDuration()
    elseif C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local d = C_DamageMeter.GetSessionDurationSeconds(session)
        if type(d) == "number" and not (issecretvalue and issecretvalue(d)) then return d end
    end
end

local function AmountPerSecond(total, duration)
    if type(total) ~= "number" or not duration or duration <= 0 then return nil end
    return total / duration
end

-- Class icon sprite system
local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({"modern", "dark", "light", "clean", "pixelsComic"}) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

local ICON_STYLE_VALUES = {
    none     = "None",
    spec     = "Default Spec Icons",
    blizzard = "Blizzard",
    modern   = "Modern",
    pixel    = "Pixel",
    pixelsComic = "Pixels Comic",
    glyph    = "Glyph",
    arcade   = "Arcade",
    legend   = "Legend",
    midnight = "Midnight",
    runic    = "Runic",
}
local ICON_STYLE_ORDER = {
    "none", "spec", "---", "blizzard", "modern", "pixel", "pixelsComic", "glyph",
    "arcade", "legend", "midnight", "runic",
}
_G._EDM_IconStyleValues = ICON_STYLE_VALUES
_G._EDM_IconStyleOrder  = ICON_STYLE_ORDER

local function ZoomCoords(u1, u2, v1, v2, z)
    local du = (u2 - u1) * z
    local dv = (v2 - v1) * z
    return u1 + du, u2 - du, v1 + dv, v2 - dv
end

local function ResolveIcon(src, iconTex, barH)
    local cfg = DB()
    local style = cfg.iconStyle or "spec"
    local zoom = cfg.classIconZoom or 0.06
    if style == "none" then iconTex:Hide(); return 0 end

    local classFile = src.classFilename
    if not classFile or (issecretvalue and issecretvalue(classFile)) or classFile == "" then iconTex:Hide(); return 0 end

    -- A Threat list's pet row (WoW Forever) shows the pet icon in every style, not its owner's class.
    if src.threatPet and type(src.specIconID) == "number" then
        iconTex:SetTexture(src.specIconID)
        iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    elseif style == "spec" then
        local specIcon = src.specIconID
        if specIcon and type(specIcon) == "number" and specIcon ~= 0 then
            iconTex:SetTexture(specIcon)
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            iconTex:SetSize(barH, barH)
            iconTex:SetDesaturated(false)
            iconTex:SetVertexColor(1, 1, 1, 1)
            iconTex:Show()
            return barH
        end
        iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            iconTex:SetTexCoord(ZoomCoords(coords[1], coords[2], coords[3], coords[4], zoom))
        else
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    elseif style == "blizzard" then
        iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            iconTex:SetTexCoord(ZoomCoords(coords[1], coords[2], coords[3], coords[4], zoom))
        else
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    else
        local coords = CLASS_SPRITE_COORDS[classFile]
        if coords then
            iconTex:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
            -- Sprite presets are pre-framed art; Icon Zoom does NOT apply (the options cog is disabled for these styles)
            iconTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            iconTex:Hide(); return 0
        end
    end
    iconTex:SetSize(barH, barH)
    iconTex:SetDesaturated(false)
    iconTex:SetVertexColor(1, 1, 1, 1)
    iconTex:Show()
    return barH
end

-- Enemy Damage Taken: aggregate combatSpellDetails into per-player totals. Returns sorted array
-- of { name, class, specIcon, total, amountPerSecond } or nil on failure.
local function AggregateEnemyPlayers(srcData, duration)
    if not srcData or not srcData.combatSpells or #srcData.combatSpells == 0 then return nil end
    local byName = {}
    local list = {}
    for _, spell in ipairs(srcData.combatSpells) do
        local det = spell.combatSpellDetails
        if det then
            local name = det.unitName
            if name and not (issecretvalue and issecretvalue(name)) then
                local ok, amt = pcall(function() return spell.totalAmount end)
                local amount = (ok and amt) or 0
                local p = byName[name]
                if not p then
                    p = { name = name, class = det.unitClassFilename, specIcon = det.specIconID, total = 0 }
                    -- WoW Forever: the Name Format leaves a pet's or a mob's name
                    -- whole (StripRealm); a flag that cannot be read counts as set.
                    if ForeverShortName then
                        local pet, mob = det.isPet, det.isMob
                        p.isPet, p.isMob = issecretvalue(pet) or pet, issecretvalue(mob) or mob
                    end
                    byName[name] = p
                    list[#list + 1] = p
                end
                p.total = p.total + amount
            end
        end
    end
    if #list == 0 then return nil end
    for _, p in ipairs(list) do
        p.amountPerSecond = AmountPerSecond(p.total, duration)
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

-- Damage Done targets: cross-reference EnemyDamageTaken to build a complete map of ALL players'
-- damage per enemy in one pass. First hover builds it; later hovers are instant cache lookups. _targetsCache
-- (declared with the event state above) is wiped on DAMAGE_METER_RESET and when combat starts or ends.
local function BuildAllPlayerTargets(session, sessionID)

    local cacheKey = tostring(session) .. "|" .. tostring(sessionID)
    if _targetsCache.key == cacheKey then return _targetsCache.map end

    if not C_DamageMeter then return nil end

    local enemySession
    if sessionID and C_DamageMeter.GetCombatSessionFromID then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, Enum.DamageMeterType.EnemyDamageTaken)
        if ok then enemySession = s end
    elseif C_DamageMeter.GetCombatSessionFromType then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, session, Enum.DamageMeterType.EnemyDamageTaken)
        if ok then enemySession = s end
    end
    if not enemySession or not enemySession.combatSources or #enemySession.combatSources == 0 then
        _targetsCache.key = cacheKey; _targetsCache.map = nil

        return nil
    end

    -- Build per-player target totals keyed by unitName; enemy key is creatureID (numeric, never secret) to avoid secret table keys
    local enemyNames = {}  -- creatureID -> display name
    local byPlayer = {}    -- unitName -> { [creatureID] = totalDamage }
    for ei = 1, #enemySession.combatSources do
        local enemy = enemySession.combatSources[ei]
        local rawCID = enemy.sourceCreatureID
        local eKey = (rawCID and not (issecretvalue and issecretvalue(rawCID))) and rawCID or ei
        enemyNames[eKey] = enemy.name
        local srcData
        if sessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, Enum.DamageMeterType.EnemyDamageTaken, enemy.sourceGUID, enemy.sourceCreatureID)
            if ok then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, session, Enum.DamageMeterType.EnemyDamageTaken, enemy.sourceGUID, enemy.sourceCreatureID)
            if ok then srcData = sd end
        end
        if srcData and srcData.combatSpells then
            for _, spell in ipairs(srcData.combatSpells) do
                local det = spell.combatSpellDetails
                if det and det.unitName and not (issecretvalue and issecretvalue(det.unitName)) then
                    local pName = det.unitName
                    local ok, amt = pcall(function() return spell.totalAmount end)
                    local amount = (ok and amt) or 0
                    if amount > 0 then
                        local pt = byPlayer[pName]
                        if not pt then pt = {}; byPlayer[pName] = pt end
                        pt[eKey] = (pt[eKey] or 0) + amount
                    end
                end
            end
        end
    end

    -- Convert each player's enemy map to a sorted array
    local duration = GetBreakdownDuration(session, sessionID)
    local map = {}
    for pName, enemies in pairs(byPlayer) do
        local list = {}
        for eKey, total in pairs(enemies) do
            list[#list + 1] = { name = enemyNames[eKey], total = total, amountPerSecond = AmountPerSecond(total, duration) }
        end
        table.sort(list, function(a, b) return a.total > b.total end)
        map[pName] = list
    end

    _targetsCache.key = cacheKey; _targetsCache.map = map

    return map
end

local function BuildPlayerTargets(playerName, session, sessionID, maxTargets)

    if not playerName then return nil end
    if issecretvalue and issecretvalue(playerName) then return nil end
    if playerName == "" then return nil end

    local map = BuildAllPlayerTargets(session, sessionID)
    if not map then return nil end

    local list = map[playerName]
    if not list or #list == 0 then return nil end

    if #list > maxTargets then
        local trimmed = {}
        for i = 1, maxTargets do trimmed[i] = list[i] end

        return trimmed
    end

    return list
end

I._srcKeyGuid, I.AbbrevNumber = _srcKeyGuid, AbbrevNumber
I.AggregateEnemyPlayers, I.AppendDMSharedMedia = AggregateEnemyPlayers, AppendDMSharedMedia
I.ApplyBarTexture, I.BuildPlayerTargets = ApplyBarTexture, BuildPlayerTargets
I.FormatBarValue, I.FormatTimer = FormatBarValue, FormatTimer
I.FormatTimerDecimal, I.GetAccentRGB = FormatTimerDecimal, GetAccentRGB
I.GetBarTexturePath = GetBarTexturePath
I.GetBreakdownBarTexturePath = GetBreakdownBarTexturePath
I.GetBreakdownDuration, I.IsOwnRow, I.IsSecret = GetBreakdownDuration, IsOwnRow, IsSecret
I.PhysicalPixels, I.ResolveGroupGUID = PhysicalPixels, ResolveGroupGUID
I.ResolveIcon, I.SetDMFont, I.SnapshotSourceKeys = ResolveIcon, SetDMFont, SnapshotSourceKeys
I.StripRealm = StripRealm
I.broken = false
