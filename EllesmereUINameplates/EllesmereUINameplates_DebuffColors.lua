if EUI_CLIENT_BLOCKED then return end
local _, ns = ...

-- EUI_DEBUFF_COLORS: declarative aura slots own visibility. Never read aura
-- payloads, inspect secure button visibility, or infer debuffs from casts.
-- Credit to Jeebz (PlateTweaks) for the debuff tinting on nameplates technique, used with permission.
local bundles = {} -- plate -> its tint bundle (reused when its unit changes)
local config
local worker
local pendingRefresh = false
local WHITE = "Interface\\Buttons\\WHITE8x8"
local STYLE = "np:debuffColorPresence"

-- Spell IDs identify DEBUFFS (Rake's damage spell, for example, is 1822).
-- Curated for debuffs players maintain on individual enemies. Names and icons
-- come from the client; verified icon paths cover unavailable spell metadata.
-- A debuff row's spell menu offers only its class's presets, in this order.
ns.DebuffColorPresets = {
    { 703, "Garrote", "Rogue", "Interface\\Icons\\ability_rogue_garrote" },
    { 1943, "Rupture", "Rogue", "Interface\\Icons\\ability_rogue_rupture" },
    { 164812, "Moonfire", "Druid", "Interface\\Icons\\spell_nature_starfall" },
    { 164815, "Sunfire", "Druid", "Interface\\Icons\\ability_mage_firestarter" },
    { 1079, "Rip", "Druid", "Interface\\Icons\\ability_ghoulfrenzy" },
    { 155722, "Rake", "Druid", "Interface\\Icons\\ability_druid_disembowel" },
    { 34914, "Vampiric Touch", "Priest", "Interface\\Icons\\spell_holy_stoicism" },
    { 589, "Shadow Word: Pain", "Priest", "Interface\\Icons\\spell_shadow_shadowwordpain" },
    { 980, "Agony", "Warlock", "Interface\\Icons\\spell_shadow_curseofsargeras" },
    { 1259790, "Unstable Affliction", "Warlock", "Interface\\Icons\\spell_shadow_unstableaffliction_3" },
    { 146739, "Corruption", "Warlock", "Interface\\Icons\\spell_shadow_abominationexplosion" },
    { 445474, "Wither", "Warlock", "Interface\\Icons\\inv_ability_hellcallerwarlock_wither" },
    { 188389, "Flame Shock", "Shaman", "Interface\\Icons\\spell_fire_flameshock" },
}
ns.DebuffColorPresetByID = {}
for _, spell in ipairs(ns.DebuffColorPresets) do ns.DebuffColorPresetByID[spell[1]] = spell end

local function Value(key)
    local p = ns.NP_GetProfile()
    if p and p[key] ~= nil then return p[key] end
    return ns.defaults[key]
end

-------------------------------------------------------------------------------
-- The debuff lists: one setting per class ("debuffColors" .. class token)
-- holding its single debuffs, then its combos, each list in priority order
-- (the higher entry wins), as one string so a profile copy or a per-spec
-- override carries a class's whole list as one value:
--   "spellID:r,g,b;spellID:r,g,b/spellID+spellID:r,g,b"
-- Spell 0 is a debuff not chosen yet; a combo needs two to four spells. The
-- options page edits the lists through this kit; the plates read only the
-- player's own class.
-------------------------------------------------------------------------------
local DC = {
    MAX_SINGLES = 10, MAX_COMBOS = 5, MAX_COMBO_SPELLS = 4,
    SINGLE_COLOR = { r = 1.00, g = 0.43, b = 0.04 },
    COMBO_COLOR = { r = 0.10, g = 0.88, b = 0.32 },
}
ns.DebuffColorKit = DC

function DC.Key(class) return "debuffColors" .. class end

function DC.SpellID(v)
    local id = tonumber(v)
    if id and id > 0 and id == math.floor(id) then return id end
end

local function ParseColor(s, d)
    local r, g, b = s:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then return { r = d.r, g = d.g, b = d.b } end
    return { r = math.min(r, 1), g = math.min(g, 1), b = math.min(b, 1) }
end

local function Num(v) return (string.format("%.4f", v):gsub("%.?0+$", "")) end
local function ColorText(c) return Num(c.r) .. "," .. Num(c.g) .. "," .. Num(c.b) end

-- A saved list as fresh tables: singles = { { spell, color } },
-- combos = { { spells = { ids }, color } }.
function DC.Parse(s)
    local singles, combos = {}, {}
    if type(s) ~= "string" then return singles, combos end
    local singlePart, comboPart = s:match("^([^/]*)/?(.*)$")
    for entry in singlePart:gmatch("[^;]+") do
        if #singles == DC.MAX_SINGLES then break end
        local id, color = entry:match("^(%d*):?(.*)$")
        singles[#singles + 1] = { spell = DC.SpellID(id) or 0, color = ParseColor(color, DC.SINGLE_COLOR) }
    end
    for entry in comboPart:gmatch("[^;]+") do
        if #combos == DC.MAX_COMBOS then break end
        local ids, color = entry:match("^([%d%+]*):?(.*)$")
        local spells = {}
        for id in ids:gmatch("%d+") do
            id = DC.SpellID(id)
            if id and #spells < DC.MAX_COMBO_SPELLS then spells[#spells + 1] = id end
        end
        combos[#combos + 1] = { spells = spells, color = ParseColor(color, DC.COMBO_COLOR) }
    end
    return singles, combos
end

-- The string to save (nil once both lists are empty).
function DC.Encode(singles, combos)
    if #singles == 0 and #combos == 0 then return nil end
    local s, c = {}, {}
    for i, e in ipairs(singles) do s[i] = e.spell .. ":" .. ColorText(e.color) end
    for i, e in ipairs(combos) do c[i] = table.concat(e.spells, "+") .. ":" .. ColorText(e.color) end
    return table.concat(s, ";") .. "/" .. table.concat(c, ";")
end

-- A class's lists; get reads the caller's profile (the plates' by default).
function DC.Read(class, get)
    return DC.Parse((get or Value)(DC.Key(class)))
end

local function Distinct(spells)
    local out, seen = {}, {}
    for _, id in ipairs(spells) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

-- Extra Border Size (whole pixels), for the borders drawn as plain strips.
local function ExtraBorderPx()
    local v = tonumber(Value("debuffColorsBorderExtra")) or 0
    return math.max(0, math.floor(v + 0.5))
end

-- Color Border: the border a plate shows, as the numbers its own apply draws it
-- with (plate:ApplyBorder, ns.ApplyCustomBorderStyle). kind "strips" = Basic
-- and Custom Solid, four strips inside the bar, Extra Border Size added; kind
-- "slices" = a textured Custom border, the eight pieces its edge art is cut
-- into. nil while the plate draws no EUI border (Border None, a stock style,
-- size 0, an unresolved texture): then there is nothing to color.
local function BorderSpec()
    if ns.NP_Blizz() then return nil end
    local s
    if ns.IsCustomBorderEnabled() then
        local tex = Value("customBorderTexture")
        local size = Value("customBorderSize") or 0
        if size <= 0 then return nil end
        local px = EllesmereUI.BorderPx(Value("customBorderSizePx"), size, tex)
        -- On MEDIUM strata. The border frame sits one level above the bar (one
        -- below it when drawn behind); a textured border draws on that frame,
        -- a Solid one on the pixel border's container one level higher. The
        -- color goes one level above whichever draws: up = levels above the
        -- border frame (MakeBorderInit places that frame's level).
        local behind = Value("customBorderBehind") == true
        if not tex or tex == "" or tex == "solid" then
            s = { kind = "strips", px = (px or size) + ExtraBorderPx(), strata = "MEDIUM",
                behind = behind, up = 2 }
        else
            local path = EllesmereUI.ResolveBorderTexture(tex)
            if not path then return nil end
            s = { kind = "slices", path = path, tex = tex, size = size, px = px,
                strata = "MEDIUM", behind = behind, up = 1,
                offX = Value("customBorderOffset"), offY = Value("customBorderOffsetY"),
                shX = Value("customBorderShiftX"), shY = Value("customBorderShiftY") }
        end
    elseif ns.IsBorderEnabled() then
        -- Basic: the bar's own strips sit one level above the bar; the color
        -- goes above them (up = levels above the bar).
        s = { kind = "strips", px = ns.NP_BorderSize() + ExtraBorderPx(), up = 2 }
    else
        return nil
    end
    -- The pixel grid the copy is drawn on: strips in physical pixels
    -- (PP.perfect), slices in UI units of the exact border size (PP.mult).
    local PP = EllesmereUI.PP
    s.key = table.concat({ s.kind, tostring(s.px), tostring(s.path), tostring(s.tex), tostring(s.size),
        tostring(s.offX), tostring(s.offY), tostring(s.shX), tostring(s.shY),
        tostring(s.strata), tostring(s.behind), s.up, s.kind == "strips" and PP.perfect or PP.mult }, ",")
    return s
end

local function ReadConfig()
    local _, class = UnitClass("player")
    local singles, combos = DC.Read(class or "")
    local playerOnly = Value("debuffColorsPlayerOnly") ~= false
    local c = {
        enabled = Value("debuffColorsEnabled") == true,
        filterTokens = playerOnly and { "HARMFUL", "PLAYER" } or { "HARMFUL" },
        singles = {}, combos = {},
    }
    local parts = { tostring(c.enabled), tostring(playerOnly) }
    -- Color Border draws over the plate's border; Color Nameplate tints the
    -- health fill with the bar's own texture.
    local colorsBorder = Value("debuffColorsBorder") == true
    if colorsBorder then
        c.border = BorderSpec()
        parts[#parts + 1] = c.border and c.border.key or "noborder"
    else
        c.texture = EllesmereUI.ResolveTexturePath(ns.healthBarTextures,
            Value("healthBarTexture"), WHITE)
        parts[#parts + 1] = tostring(c.texture)
    end
    -- Declared bottom to top (a later-declared slot draws on top): the single
    -- debuffs from the end of the list up, then the combos the same way, so a
    -- combo always wins over a single debuff. A spell listed again lower down
    -- can never show beneath itself, so only its highest entry gets a slot.
    local ranked, seen = {}, {}
    for _, e in ipairs(singles) do
        if e.spell > 0 and not seen[e.spell] then
            seen[e.spell] = true
            ranked[#ranked + 1] = e
        end
    end
    for i = #ranked, 1, -1 do
        local e = ranked[i]
        c.singles[#c.singles + 1] = { spell = e.spell, color = e.color, sublevel = i == 1 and 5 or 4 }
        parts[#parts + 1] = "s" .. e.spell .. ":" .. ColorText(e.color)
    end
    for i = #combos, 1, -1 do
        local spells = Distinct(combos[i].spells)
        if #spells >= 2 then
            c.combos[#c.combos + 1] = { spells = spells, color = combos[i].color }
            parts[#parts + 1] = "c" .. table.concat(spells, "+") .. ":" .. ColorText(combos[i].color)
        end
    end
    -- Color Border on a plate with no border has nothing to show.
    c.any = (#c.singles > 0 or #c.combos > 0) and (c.border ~= nil or not colorsBorder)
    c.fingerprint = table.concat(parts, "|")
    return c
end

-- Neighbouring combos (in declaration order) that have a debuff in common
-- share their first slot. A combo shows only while all its debuffs are up, so
-- the debuff its chain starts with never changes when it shows, and the
-- shared slot nests the rest of each combo in the same bottom-to-top order,
-- so nothing draws in a different order. Each sharer saves a root slot and,
-- on every mob carrying the shared debuff, a live nested container.
local function GroupComboRuns(combos)
    local runs, i = {}, 1
    while i <= #combos do
        local common = {}
        for _, id in ipairs(combos[i].spells) do common[id] = true end
        local j = i
        while j < #combos do
            local both, any = {}, false
            for _, id in ipairs(combos[j + 1].spells) do
                if common[id] then both[id], any = true, true end
            end
            if not any then break end
            common, j = both, j + 1
        end
        -- The run's first combo keeps its own spell order where it can, so a
        -- combo with no neighbour to share with builds exactly as saved.
        local first
        for _, id in ipairs(combos[i].spells) do
            if common[id] then first = id; break end
        end
        local run = {}
        for k = i, j do
            local spells = { first }
            for _, id in ipairs(combos[k].spells) do
                if id ~= first then spells[#spells + 1] = id end
            end
            run[#run + 1] = { spells = spells, color = combos[k].color }
        end
        runs[#runs + 1] = run
        i = j + 1
    end
    return runs
end

-- A bundle a settings change replaces can never be freed (frames are permanent);
-- releasing its containers keeps their engine slots out of AuraKit's restyle
-- registry. Refresh runs this out of combat only.
local function ReleaseBundle(b)
    b.holder:Hide()
    for _, container in ipairs(b.containers) do
        container:SetEnabled(false)
        EllesmereUI.AuraKit.ReleaseContainer(container)
    end
end

-- Containers are born enabled on unit "none" and stay enabled: the holder's
-- visibility gates them (a hidden container drops its aura events, a shown
-- one re-reads its unit in full). A new token rebinds every container,
-- nested ones included; the same token needs only the show.
local function BindBundle(b, unit)
    if b.unit ~= unit then
        b.unit = unit
        -- Binding a slot may initialize its nested container; re-read the count.
        local i = 1
        while i <= #b.containers do
            b.containers[i]:SetUnit(unit)
            i = i + 1
        end
    end
    b.holder:Show()
end

local function CreateTintContainer(b, parent)
    local c = EllesmereUI.AuraKit.CreateContainerShell(parent, {})
    c:SetAllPoints(b.holder)
    c:SetFrameLevel(b.level)
    b.containers[#b.containers + 1] = c
    return c
end

local function MakeTintInit(b, color, sublevel)
    local initialized = setmetatable({}, { __mode = "k" })
    return function(button)
        if initialized[button] then return end
        initialized[button] = true
        -- Only creation-window decoration. Once owned by the aura engine, these
        -- regions may become forbidden; never read or repaint them on rebind.
        button:SetFrameLevel(b.level)
        button:EnableMouse(false)
        local tint = button:CreateTexture(nil, "ARTWORK", nil, sublevel)
        tint:SetTexture(b.config.texture)
        tint:SetVertexColor(color.r, color.g, color.b, 1)
        tint:SetPoint("TOPLEFT", b.fill, "TOPLEFT", 0, 0)
        tint:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT", 0, 0)
        if b.mask then tint:AddMaskTexture(b.mask) end
    end
end

-- Color Border init: the plate's border drawn again in the debuff color, just
-- above it (b.config.border, see BorderSpec), so the border reads as recolored
-- while the slot shows. Strips keep whole physical pixels in scale-1 space as
-- the plate scales, like the border's own (the PP scale guard); slices sit on
-- the textured border's own geometry. Built in the creation window only.
-- The copies rank like the tints (a combo over the top single over the rest)
-- without moving past anything else. On a custom border's MEDIUM strata a copy
-- stays one level above the border and its sublevel ranks it (the frames that
-- share that level draw ARTWORK). A Basic copy shares the flattened plate with
-- the border's OVERLAY 7 strips, under which a lower sublevel sinks, so it keeps
-- OVERLAY 7 and ranks by frame level (no other plate frame uses those levels).
local function MakeBorderInit(b, color, sublevel)
    local initialized = setmetatable({}, { __mode = "k" })
    local rank = 0
    if not b.config.border.strata then
        rank = (sublevel == 7 and 2) or (sublevel == 5 and 1) or 0
        sublevel = 7
    end
    return function(button)
        if initialized[button] then return end
        initialized[button] = true
        button:SetFrameLevel(b.level)
        button:EnableMouse(false)
        local spec = b.config.border
        local f = CreateFrame("Frame", nil, button)
        f:EnableMouse(false)
        if spec.strata then f:SetFrameStrata(spec.strata) end
        -- A custom border's frame level as ns.ApplyCustomBorderStyle sets it;
        -- Basic counts from the bar.
        local base = b.level
        if spec.behind ~= nil then
            base = spec.behind and math.max(1, b.level - 1) or (b.level + 1)
        end
        f:SetFrameLevel(base + spec.up + rank)
        if spec.kind == "strips" then
            f:SetIgnoreParentScale(true)
            f:SetScale(1)
            f:SetAllPoints(b.holder)
            local ok, es = pcall(f.GetEffectiveScale, f)
            if not (ok and es and es > 0) then es = 1 end
            local one = EllesmereUI.PP.perfect / es
            local t = math.max(one, math.floor(spec.px + 0.5) * one)
            local function Strip(p1, y1, p2, y2, width, height)
                local tx = f:CreateTexture(nil, "OVERLAY", nil, sublevel)
                tx:SetColorTexture(color.r, color.g, color.b, 1)
                if tx.SetSnapToPixelGrid then
                    tx:SetSnapToPixelGrid(false)
                    tx:SetTexelSnappingBias(0)
                end
                tx:SetPoint(p1, f, p1, 0, y1)
                tx:SetPoint(p2, f, p2, 0, y2)
                if width then tx:SetWidth(width) else tx:SetHeight(height) end
            end
            Strip("TOPLEFT", 0, "TOPRIGHT", 0, nil, t)
            Strip("BOTTOMLEFT", 0, "BOTTOMRIGHT", 0, nil, t)
            Strip("TOPLEFT", -t, "BOTTOMLEFT", t, t)
            Strip("TOPRIGHT", -t, "BOTTOMRIGHT", t, t)
        else
            f:SetAllPoints(b.holder)
            -- One texture per edge-art slice (the shared cut table's keys).
            local edges = {}
            for key, coords in pairs(EllesmereUI.SECRET_BORDER_UV) do
                local tx = f:CreateTexture(nil, "OVERLAY", nil, sublevel)
                tx:SetTexture(spec.path, true, true)
                tx:SetTexCoord(unpack(coords))
                tx:SetVertexColor(color.r, color.g, color.b, 1)
                edges[key] = tx
            end
            local edge, aL, aT, aR, aB = EllesmereUI.SecretBorderGeometry(f, spec.size, spec.tex,
                spec.offX, spec.offY, spec.shX, spec.shY, "nameplates", spec.size, nil, spec.px)
            EllesmereUI.LayoutSecretBorderEdges(edges, f, edge, aL, aT, aR, aB)
        end
    end
end

-- What a slot shows while its debuffs are up: the health fill's tint (Color
-- Nameplate) or the border in the color (Color Border).
local function ColorInit(b, color, sublevel)
    if b.config.border then return MakeBorderInit(b, color, sublevel) end
    return MakeTintInit(b, color, sublevel)
end

local function AddTintSlot(b, container, key, spell, initialize)
    EllesmereUI.AuraKit.AddSlotToContainer(container, {
        key = key, filter = b.config.filterTokens, style = STYLE,
        candidateFilters = { includeSpellIDs = { [spell] = true } },
        extraInit = initialize,
    })
end

-- Init for a slot whose engine button hosts the next step of a combo: a
-- container nested in the button, filled by declare and bound to the unit.
local function MakeNestInit(b, declare)
    local initialized = setmetatable({}, { __mode = "k" })
    return function(button)
        if initialized[button] then return end
        initialized[button] = true
        button:SetFrameLevel(b.level)
        button:EnableMouse(false)
        local nested = CreateTintContainer(b, button)
        declare(nested)
        if b.unit then nested:SetUnit(b.unit) end
    end
end

-- A combo nests one slot per spell, each inside the previous spell's engine
-- button: the tint in the innermost slot renders only while EVERY engine
-- button above it is shown.
local function AddComboSlot(b, container, key, combo, depth)
    local spell = combo.spells[depth]
    if depth == #combo.spells then
        AddTintSlot(b, container, key .. "_" .. depth, spell, ColorInit(b, combo.color, 7))
        return
    end
    AddTintSlot(b, container, key .. "_" .. depth, spell, MakeNestInit(b, function(nested)
        AddComboSlot(b, nested, key, combo, depth + 1)
    end))
end

-- A run's combos share their first slot; its nested container holds the rest
-- of each combo, declared bottom to top like the runs themselves.
local function AddComboRun(b, container, key, run)
    AddTintSlot(b, container, key, run[1].spells[1], MakeNestInit(b, function(nested)
        for i, combo in ipairs(run) do
            AddComboSlot(b, nested, key .. "_" .. i, combo, 2)
        end
    end))
end

-- The tints share one frame level (the target/focus/hover patterns sit one
-- level up), so a later-declared slot draws on top: ReadConfig orders them.
local function CreateBundle(plate)
    local b = {
        config = config,
        fill = plate.health:GetStatusBarTexture(), mask = plate._absorbMask,
        level = plate.health:GetFrameLevel(), containers = {},
    }
    -- Tint shares the fill's frame level; EUI's text, target/focus patterns,
    -- border and absorb effects keep their own higher layers.
    b.holder = CreateFrame("Frame", nil, plate.health)
    b.holder:SetAllPoints(plate.health)
    b.holder:SetFrameLevel(b.level)
    b.holder:EnableMouse(false)
    b.holder:Hide()
    local root = CreateTintContainer(b, b.holder)
    for i, single in ipairs(config.singles) do
        AddTintSlot(b, root, "EUI_DEBUFF_COLOR_" .. i, single.spell,
            ColorInit(b, single.color, single.sublevel))
    end
    for i, run in ipairs(config.comboRuns) do
        AddComboRun(b, root, "EUI_DEBUFF_COMBO_" .. i, run)
    end
    bundles[plate] = b
    return b
end

local function Attach(plate, unit)
    local b = bundles[plate] or CreateBundle(plate)
    -- Parent level changes propagate to all descendants. Touch only the ordinary
    -- holder; a nested container inherits its secure AuraButton's restrictions.
    b.level = plate.health:GetFrameLevel()
    b.holder:SetFrameLevel(b.level)
    BindBundle(b, unit)
end

-- Parking is a hide, at once even while a parse is pending; the containers
-- keep their binding (see BindBundle).
local function Detach(plate)
    local b = bundles[plate]
    if b then b.holder:Hide() end
end

local function EnsureWorker()
    if worker then return worker end
    worker = CreateFrame("Frame")
    worker:Hide()
    -- PLAYER_REGEN_ENABLED, held only while a combat-deferred refresh waits;
    -- DISPLAY_SIZE_CHANGED, held only while border strips are built (they are
    -- sized in physical pixels, so a resolution change redraws them).
    worker:SetScript("OnEvent", function(self, event)
        if event == "DISPLAY_SIZE_CHANGED" then
            ns.DebuffColors_RequestRefresh()
            return
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingRefresh then ns.DebuffColors_Refresh() end
    end)
    return worker
end

function ns.DebuffColors_Refresh()
    if not config and Value("debuffColorsEnabled") ~= true then return end
    -- Profile/spec swaps can arrive in combat. Rebuilding secure decoration is
    -- deferred; the new configuration is applied on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        pendingRefresh = true
        EnsureWorker():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pendingRefresh = false
    local nextConfig = ReadConfig()
    if config and config.fingerprint == nextConfig.fingerprint then return end
    config = nextConfig
    -- Clear active AND currently pooled bundles so a later plate reuse cannot bind
    -- a previous profile's spells or colors.
    for plate, b in pairs(bundles) do
        ReleaseBundle(b)
        bundles[plate] = nil
    end
    if config.enabled and config.any then
        config.comboRuns = GroupComboRuns(config.combos)
        local AK = EllesmereUI.AuraKit
        AK.styles[STYLE] = AK.styles[STYLE] or { noRegions = true, noTooltips = true }
        ns.DebuffColors_Attach, ns.DebuffColors_Detach = Attach, Detach
        for unit, plate in pairs(ns.plates) do Attach(plate, unit) end
    else
        -- Nothing to color: no plate hooks. An enabled config stays as the
        -- applied state the next refresh compares against.
        ns.DebuffColors_Attach, ns.DebuffColors_Detach = nil, nil
        if not config.enabled then config = nil end
        if worker then
            worker:UnregisterEvent("PLAYER_REGEN_ENABLED")
            worker:SetScript("OnUpdate", nil)
            worker:Hide()
        end
    end
    -- A border color is drawn in whole pixels, on the grid its key names: slices
    -- rebuild through the shared re-apply on a UI scale change, strips on a
    -- resolution change.
    local border = config and config.any and config.border
    EllesmereUI.RegisterPxReapply(DC, (border and border.kind == "slices")
        and ns.DebuffColors_RequestRefresh or nil)
    if border and border.kind == "strips" then
        EnsureWorker():RegisterEvent("DISPLAY_SIZE_CHANGED")
    elseif worker then
        worker:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
end

local function RunRequestedRefresh(self)
    self:Hide()
    self:SetScript("OnUpdate", nil)
    ns.DebuffColors_Refresh()
end

-- Coalesce settings writes into one next-frame refresh; never poll aura state.
-- The options page applies every edit through here as it is made. A slider
-- drag commits every step, and a border number change rebuilds every plate's
-- bundle, so while one is dragged the refresh waits for its release (the
-- slider runs the deferred checks once).
function ns.DebuffColors_RequestRefresh()
    if not config and Value("debuffColorsEnabled") ~= true then return end
    if EllesmereUI._sliderDragging then
        local checks = EllesmereUI._deferredDriftChecks
        if not checks then
            checks = {}
            EllesmereUI._deferredDriftChecks = checks
        end
        checks[ns.DebuffColors_RequestRefresh] = true
        return
    end
    local w = EnsureWorker()
    w:SetScript("OnUpdate", RunRequestedRefresh)
    w:Show()
end
