if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_PluginGlows.lua
--
--  "Plugin Glows": lets other addons register a named glow source and push the
--  spell(s) that should glow right now. Every registered source gets a
--  Glow Style and a Glow Color in the icon right-click menu (Plugin Glows >
--  source), saved per spell with the usual Apply to Bar scopes, and the
--  matching Cooldown Manager icons glow. See PLUGIN_GLOWS_API.md.
--
--  Public API: EllesmereUI.PluginGlows (Register / Unregister / IsRegistered).
--  Suite-internal: the ns.PluginGlow* functions (menu + hook sites).
--
--  Cost: with nothing registered this file does nothing. A registration does
--  nothing until the player picks a glow style for it (reg.inUse); only then
--  do icon refreshes look at it and the plugin's onInUse callback fires.
--  Pushes from a plugin only touch the few icons that carry a plugin glow.
-------------------------------------------------------------------------------
local _, ns = ...

local MAX_ID_LEN, MAX_NAME_CHARS, MAX_REGISTRATIONS = 40, 40, 50

local regs, list = {}, {}
-- Icons whose resolved settings carry a plugin glow style; the only ones re-evaluated on a push.
local watch = setmetatable({}, { __mode = "k" })

local function ReportError(err) return geterrorhandler()(err) end

-------------------------------------------------------------------------------
--  Runtime: one overlay per (icon, source), driven by the source's spell list
-------------------------------------------------------------------------------
local function ResolveColor(ss, keys)
    local mode = ss[keys.color]
    if mode == "class" then
        local _, ct = UnitClass("player")
        local cc = ct and RAID_CLASS_COLORS[ct]
        if cc then return cc.r, cc.g, cc.b end
    elseif mode == "custom" and ss[keys.colorR] ~= nil then
        return ss[keys.colorR], ss[keys.colorG] or 0.788, ss[keys.colorB] or 0.137
    end
    return nil
end

local function IdMatches(id, target, targetBase)
    if type(id) ~= "number" or id <= 0 then return false end
    if issecretvalue and issecretvalue(id) then return false end
    if id == target or id == targetBase then return true end
    -- The frame may hold the base spell while the source reports its live override.
    return C_Spell.GetOverrideSpell(id) == target
end

local function FrameShowsSpell(fc, target)
    local targetBase = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(target) or target
    return IdMatches(fc.spellID, target, targetBase)
        or IdMatches(fc.resolvedSid, target, targetBase)
        or IdMatches(fc.baseSpellID, target, targetBase)
        or IdMatches(fc.overrideSid, target, targetBase)
end

local function FrameShowsAny(fc, spells)
    for i = 1, #spells do
        if FrameShowsSpell(fc, spells[i]) then return true end
    end
    return false
end

local function SettingsFor(frame, fc)
    if not (fc and fc.spellID and fc.barKey and ns.ResolveSpellSettings) then return nil end
    return ns.ResolveSpellSettings(frame, fc.spellID, ns.GetBarSpellData(fc.barKey), fc.barKey)
end

local function StopState(st)
    if st and st.on then
        if st.ov then ns.StopNativeGlow(st.ov) end
        st.on = false
    end
end

local function EvalFrame(frame, reg, ss)
    local fd = ns._hookFrameData and ns._hookFrameData[frame]
    if not fd then return end
    local states = fd._pluginGlows
    local st = states and states[reg.id]
    local keys = reg.keys
    local fc = ns._ecmeFC[frame]
    local style, alpha, r, g, b
    local spells = reg.spells
    if spells and ss and fc then
        local s = ss[keys.style]
        if s and s > 0 and FrameShowsAny(fc, spells) then
            style = s
            local entry = ns.GLOW_STYLES[s]
            alpha = (entry and entry.solidFill) and ss[keys.alpha] or nil
            r, g, b = ResolveColor(ss, keys)
        end
    end
    if not style then
        StopState(st)
        return
    end
    if st and st.on and st.style == style and st.alpha == alpha
       and st.r == r and st.g == g and st.b == b then
        return
    end
    if not states then states = {}; fd._pluginGlows = states end
    if not st then st = {}; states[reg.id] = st end
    local ov = st.ov
    if not ov then
        -- Own overlay (lazy, created on first use) so it never fights proc/active/max-charges glows.
        ov = CreateFrame("Frame", nil, frame)
        ov:SetAllPoints(frame)
        ov:SetAlpha(0)
        ov:EnableMouse(false)
        st.ov = ov
    end
    -- Blackout is a solid fill: keep it below the cooldown widget (as the CD-state glow does) so swipe and countdown text stay readable.
    local solid = ns.GLOW_STYLES[style] and ns.GLOW_STYLES[style].solidFill
    ov:SetFrameLevel(frame:GetFrameLevel() + (solid and 12 or 17))
    -- A fresh opts table per start: StartNativeGlow keeps it by reference for its combat-only replay.
    ns.StartNativeGlow(ov, style, r, g, b, solid and { alpha = alpha } or nil)
    st.on = true
    st.style, st.alpha, st.r, st.g, st.b = style, alpha, r, g, b
end

-- Called for every CDM icon refresh (gated on ns._cdmAnyPluginGlow by the caller).
function ns.PluginGlowRefreshIcon(frame)
    if not frame then return end
    local fc = ns._ecmeFC[frame]
    local ss = SettingsFor(frame, fc)
    local any = false
    for i = 1, #list do
        local reg = list[i]
        if ss and (ss[reg.keys.style] or 0) > 0 then any = true end
        EvalFrame(frame, reg, ss)
    end
    watch[frame] = any or nil
end

-------------------------------------------------------------------------------
--  Gate: a source counts as in use once any saved setting carries a style for it
-------------------------------------------------------------------------------
local function MarkInUse(reg)
    if reg.inUse then return end
    reg.inUse = true
    ns._cdmAnyPluginGlow = true
    if reg.onInUse then xpcall(reg.onInUse, ReportError, reg.handle) end
end

-- Runs with the other Rescan*Flag calls before each rebuild and after menu changes.
-- Repeats while a source is unused so a profile switch can bring settings in.
function ns.RescanPluginGlowFlag()
    if not EllesmereUIDB then return end
    local pending = false
    for i = 1, #list do
        if not list[i].inUse then pending = true; break end
    end
    if not pending then return end
    ns.ForEachSavedSettingsBlock(function(ss)
        for i = 1, #list do
            local reg = list[i]
            if not reg.inUse and (ss[reg.keys.style] or 0) > 0 then MarkInUse(reg) end
        end
    end)
end

local function RefreshAllBars()
    if not (ns.barDataByKey and ns.RefreshCDMIconAppearance) then return end
    for barKey in pairs(ns.barDataByKey) do ns.RefreshCDMIconAppearance(barKey) end
end

-- Menu hook: a style was applied/removed through any scope for this bar.
function ns.PluginGlowsSettingsChanged(barKey)
    ns.RescanPluginGlowFlag()
    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
end

-- Menu hook: a per-spell style was picked directly.
function ns.PluginGlowsMarkInUse(id)
    local reg = regs[id]
    if reg then MarkInUse(reg) end
end

function ns.PluginGlowsGetList() return list end

-------------------------------------------------------------------------------
--  Public registry
-------------------------------------------------------------------------------
local function Reject(id, msg)
    ReportError(("EllesmereUI.PluginGlows.Register(%s): %s"):format(tostring(id), msg))
    return nil
end

local function ValidId(s)
    return type(s) == "string" and #s <= MAX_ID_LEN and s:find("^%a[%w_%-]*$") ~= nil
end

-- Plain text only: color codes, textures and control characters are removed.
local function PlainName(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|[Tt].-|[Tt]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
         :gsub("|", ""):gsub("%c", " "):gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$")
    local n, cut = 0, nil
    for pos in s:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > MAX_NAME_CHARS then cut = pos; break end
    end
    if cut then s = s:sub(1, cut - 1) end
    if s == "" then return nil end
    return s
end

-- nil, a spell ID or a list of spell IDs -> nil or a fresh list of positive numbers.
local function NormalizeSpells(spells)
    if spells == nil then return nil end
    if type(spells) == "number" then
        return spells > 0 and { spells } or nil
    end
    if type(spells) ~= "table" then
        ReportError("EllesmereUI.PluginGlows: SetSpells expects nil, a spell ID or a list of spell IDs")
        return nil
    end
    local out
    for i = 1, #spells do
        local id = spells[i]
        if type(id) == "number" and id > 0 then
            out = out or {}
            out[#out + 1] = id
        end
    end
    return out
end

local function SameList(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function MakeHandle(reg)
    local handle = {}
    function handle:SetSpells(spells)
        if regs[reg.id] ~= reg then return end
        local new = NormalizeSpells(spells)
        if SameList(reg.spells, new) then return end
        reg.spells = new
        -- Only icons that carry a plugin glow are touched.
        for frame in pairs(watch) do
            EvalFrame(frame, reg, SettingsFor(frame, ns._ecmeFC[frame]))
        end
    end
    function handle:Clear()
        self:SetSpells(nil)
    end
    function handle:IsInUse()
        return reg.inUse == true
    end
    function handle:Unregister()
        if regs[reg.id] ~= reg then return end
        reg.spells = nil
        for frame in pairs(watch) do
            local fd = ns._hookFrameData and ns._hookFrameData[frame]
            local states = fd and fd._pluginGlows
            StopState(states and states[reg.id])
            if states then states[reg.id] = nil end
        end
        regs[reg.id] = nil
        for i = 1, #list do
            if list[i] == reg then table.remove(list, i); break end
        end
    end
    return handle
end

EllesmereUI.PluginGlows = {
    API_VERSION = 1,

    --- Registers a glow source.
    --- @param id string    unique id: a letter, then letters, digits, "_" or "-" (max 40)
    --- @param spec table   { name = "Shown in the menu", onInUse = function(handle) }
    --- @return table|nil   handle (SetSpells / Clear / IsInUse / Unregister), nil when rejected
    Register = function(id, spec)
        if not ValidId(id) then
            return Reject(id, ("id must match ^%%a[%%w_%%-]*$ (max %d chars)"):format(MAX_ID_LEN))
        end
        if regs[id] then return Reject(id, "a source with this id is already registered") end
        if type(spec) ~= "table" then return Reject(id, "spec must be a table") end
        local name = PlainName(spec.name)
        if not name then return Reject(id, "name must be a non-empty string") end
        if spec.onInUse ~= nil and type(spec.onInUse) ~= "function" then
            return Reject(id, "onInUse must be a function")
        end
        if #list >= MAX_REGISTRATIONS then
            return Reject(id, ("at most %d sources can be registered"):format(MAX_REGISTRATIONS))
        end

        -- Saved-setting keys live in each spell's settings table next to the
        -- built-in glow keys. The R/G/B suffixes are what the Apply to Bar
        -- machinery recognizes as one colour.
        local prefix = "pluginGlow:" .. id .. ":"
        local reg = {
            id = id,
            name = name,
            onInUse = spec.onInUse,
            inUse = false,
            keys = {
                style  = prefix .. "style",
                alpha  = prefix .. "alpha",
                color  = prefix .. "color",
                colorR = prefix .. "colorR",
                colorG = prefix .. "colorG",
                colorB = prefix .. "colorB",
            },
        }
        reg.handle = MakeHandle(reg)
        regs[id] = reg
        list[#list + 1] = reg
        -- Registered after the bars were built: pick up settings saved earlier. Before that, BuildAllCDMBars does it.
        if ns.barDataByKey and next(ns.barDataByKey) then
            ns.RescanPluginGlowFlag()
            if reg.inUse then RefreshAllBars() end
        end
        return reg.handle
    end,

    Unregister = function(id)
        local reg = regs[id]
        if reg then reg.handle:Unregister() end
    end,

    IsRegistered = function(id)
        return regs[id] ~= nil
    end,
}
