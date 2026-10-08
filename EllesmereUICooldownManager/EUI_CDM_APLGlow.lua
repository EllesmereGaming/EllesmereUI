if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_APLGlow.lua   (EllesmereUI-APL_Glow fork only -- not for upstream)
--
--  Glows the CDM icon of the spell APLforEUI reports as next up in the APL.
--  Per-spell settings (tier-chained like every other CDM spell setting):
--    aplGlow        glow style index (same numbering as Active State Glow)
--    aplGlowColor   nil | "class" | "custom"
--    aplGlowColorR/G/B
--
--  Everything lives in this file. Core touch points (keep them tiny):
--    EUI_CDM_Icons.lua          -> calls ns.APLGlowRefreshIcon(icon) per icon refresh
--    EUI_CDM_Rebuild.lua        -> calls ns.RescanAPLGlowFlag() with the other gate scans
--    SpellPicker_Options.lua    -> the "APL Glow" / "APL Glow Color" menu rows
--  Data source: the public API exposed by APLforEUI (global APLforEUI_API).
--  Without that addon nothing here registers, hooks or runs.
-------------------------------------------------------------------------------
local _, ns = ...

local APLGlow = {}
ns.APLGlow = APLGlow

-- Frames whose resolved settings carry an APL glow; the only ones re-evaluated when the APL's pick changes.
local watch = setmetatable({}, { __mode = "k" })
local nextSpellID
local listening = false

function APLGlow.IsAvailable()
    return _G.APLforEUI_API ~= nil
end

local function ResolveColor(ss)
    local mode = ss.aplGlowColor
    if mode == "class" then
        local _, ct = UnitClass("player")
        local cc = ct and RAID_CLASS_COLORS[ct]
        if cc then return cc.r, cc.g, cc.b end
    elseif mode == "custom" and ss.aplGlowColorR ~= nil then
        return ss.aplGlowColorR, ss.aplGlowColorG or 0.788, ss.aplGlowColorB or 0.137
    end
    return nil
end

local function IdMatches(id, target, targetBase)
    if type(id) ~= "number" or id <= 0 then return false end
    if issecretvalue and issecretvalue(id) then return false end
    if id == target or id == targetBase then return true end
    -- The frame may hold the base spell while the APL reports its live override.
    return C_Spell.GetOverrideSpell(id) == target
end

local function FrameShowsSpell(fc, target)
    local targetBase = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(target) or target
    return IdMatches(fc.spellID, target, targetBase)
        or IdMatches(fc.resolvedSid, target, targetBase)
        or IdMatches(fc.baseSpellID, target, targetBase)
        or IdMatches(fc.overrideSid, target, targetBase)
end

local function SettingsFor(frame, fc)
    if not (fc and fc.spellID and fc.barKey and ns.ResolveSpellSettings) then return nil end
    return ns.ResolveSpellSettings(frame, fc.spellID, ns.GetBarSpellData(fc.barKey), fc.barKey)
end

local function StopFrame(fd)
    if fd._aplGlowOn then
        if fd.aplGlowOverlay then ns.StopNativeGlow(fd.aplGlowOverlay) end
        fd._aplGlowOn = false
    end
end

local function EvalFrame(frame)
    local fd = ns._hookFrameData and ns._hookFrameData[frame]
    if not fd then return end
    local fc = ns._ecmeFC[frame]
    local style, r, g, b
    if nextSpellID and fc and watch[frame] then
        local ss = SettingsFor(frame, fc)
        local st = ss and ss.aplGlow
        if st and st > 0 and FrameShowsSpell(fc, nextSpellID) then
            style = st
            r, g, b = ResolveColor(ss)
        end
    end
    if not style then
        StopFrame(fd)
        return
    end
    if fd._aplGlowOn and fd._aplGlowStyle == style
       and fd._aplGlowR == r and fd._aplGlowG == g and fd._aplGlowB == b then
        return
    end
    local ov = fd.aplGlowOverlay
    if not ov then
        -- Own overlay (lazy, created on first use) so it never fights proc/active/max-charges glows.
        ov = CreateFrame("Frame", nil, frame)
        ov:SetAllPoints(frame)
        ov:SetAlpha(0)
        ov:EnableMouse(false)
        fd.aplGlowOverlay = ov
    end
    ov:SetFrameLevel(frame:GetFrameLevel() + 17)
    ns.StartNativeGlow(ov, style, r, g, b)
    fd._aplGlowOn = true
    fd._aplGlowStyle, fd._aplGlowR, fd._aplGlowG, fd._aplGlowB = style, r, g, b
end

local function OnNextSpell(spellID)
    nextSpellID = spellID
    for frame in pairs(watch) do EvalFrame(frame) end
end

local function EnsureListening()
    if listening or not APLGlow.IsAvailable() then return end
    listening = true
    _G.APLforEUI_API.RegisterListener(OnNextSpell)
end

-- Called for every CDM icon refresh (gated on ns._cdmAnyAPLGlow by the caller).
function ns.APLGlowRefreshIcon(frame)
    if not frame then return end
    local fc = ns._ecmeFC[frame]
    local ss = SettingsFor(frame, fc)
    local st = ss and ss.aplGlow
    watch[frame] = (st and st > 0) and true or nil
    EvalFrame(frame)
end

-- Turn the feature on at runtime (menu setter / bar-tier apply).
function APLGlow.MarkConfigured()
    ns._cdmAnyAPLGlow = true
    EnsureListening()
end

-- Gate scan, run with the other Rescan*Flag calls before each rebuild/refresh.
-- Repeats while nothing is found so a profile switch can bring settings in.
function ns.RescanAPLGlowFlag()
    if ns._cdmAnyAPLGlow or not APLGlow.IsAvailable() then return end
    if not EllesmereUIDB then return end
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.aplGlow and ss.aplGlow > 0 then
            APLGlow.MarkConfigured()
            return true
        end
    end)
end
