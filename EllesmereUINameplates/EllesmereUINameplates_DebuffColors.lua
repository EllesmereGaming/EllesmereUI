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
--   "spellID:r,g,b;!spellID:r,g,b/spellID+spellID:r,g,b"
-- A "!" marks a debuff that colors while it is missing (While Missing below).
-- Spell 0 is a debuff not chosen yet; a combo needs two to four spells. The
-- options page edits the lists through this kit; the plates read only the
-- player's own class.
-------------------------------------------------------------------------------
local DC = {
    MAX_SINGLES = 10, MAX_MISSING = 5, MAX_COMBOS = 5, MAX_COMBO_SPELLS = 4,
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

-- A saved list as fresh tables: singles = { { spell, color, missing } },
-- combos = { { spells = { ids }, color } }.
function DC.Parse(s)
    local singles, combos = {}, {}
    if type(s) ~= "string" then return singles, combos end
    local singlePart, comboPart = s:match("^([^/]*)/?(.*)$")
    for entry in singlePart:gmatch("[^;]+") do
        if #singles == DC.MAX_SINGLES then break end
        local miss, id, color = entry:match("^(!?)(%d*):?(.*)$")
        singles[#singles + 1] = { spell = DC.SpellID(id) or 0, color = ParseColor(color, DC.SINGLE_COLOR),
            missing = miss == "!" or nil }
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
    for i, e in ipairs(singles) do s[i] = (e.missing and "!" or "") .. e.spell .. ":" .. ColorText(e.color) end
    for i, e in ipairs(combos) do c[i] = table.concat(e.spells, "+") .. ":" .. ColorText(e.color) end
    return table.concat(s, ";") .. "/" .. table.concat(c, ";")
end

-- A class's lists; get reads the caller's profile (the plates' by default).
function DC.Read(class, get)
    return DC.Parse((get or Value)(DC.Key(class)))
end

-- What the color goes on: "nameplate" (the health fill, in the bar's texture),
-- "texture" (the health fill, in debuffColorsTexture), "border" or "name". A
-- view over debuffColorsMode, which holds only the last two, and the older
-- debuffColorsBorder (Color Border, else Color Nameplate).
function DC.Mode(get)
    get = get or Value
    local m = get("debuffColorsMode")
    if m == "texture" or m == "name" then return m end
    return get("debuffColorsBorder") == true and "border" or "nameplate"
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
    local mode = DC.Mode()
    local parts = { tostring(c.enabled), tostring(playerOnly), mode }
    -- Color Border draws over the plate's border; Color Nameplate tints the
    -- health fill with the bar's own texture, Texture Nameplate with the one
    -- picked for it (the bar's until then); Color Name draws the name again.
    -- channel: the threat color each one gives way to (see Threat).
    if mode == "border" then
        c.border = BorderSpec()
        c.channel = "border"
        parts[#parts + 1] = c.border and c.border.key or "noborder"
    elseif mode == "name" then
        c.name, c.channel = true, "name"
    else
        local key = Value("healthBarTexture")
        if mode == "texture" then key = Value("debuffColorsTexture") or key end
        c.texture = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key, WHITE)
        c.channel = "health"
        parts[#parts + 1] = tostring(c.texture)
    end
    -- Declared bottom to top (a later-declared slot draws on top): the single
    -- debuffs from the end of the list up, then the combos the same way, so a
    -- combo always wins over a single debuff. Missing debuffs draw over both, on
    -- OVERLAY -4 down to -8 by list order (under the bar's shade, hash line,
    -- border and target/focus/hover stripes): one sublevel each, so at most
    -- MAX_MISSING. A spell listed again lower down in the same state can never
    -- show beneath itself, so only its highest entry gets a slot.
    local ranked, seen, missing = {}, {}, 0
    for _, e in ipairs(singles) do
        local key = (e.missing and "!" or "") .. e.spell
        if e.spell > 0 and not seen[key] and not (e.missing and missing == DC.MAX_MISSING) then
            seen[key] = true
            ranked[#ranked + 1] = e
            if e.missing then missing = missing + 1; e.sublevel = -3 - missing end
        end
    end
    for i = #ranked, 1, -1 do
        local e = ranked[i]
        c.singles[#c.singles + 1] = { spell = e.spell, color = e.color,
            sublevel = e.sublevel or (i == 1 and 5) or 4, missing = e.missing }
        parts[#parts + 1] = (e.missing and "m" or "s") .. e.spell .. ":" .. ColorText(e.color)
        if e.missing then c.anyMissing = true end
    end
    for i = #combos, 1, -1 do
        local spells = Distinct(combos[i].spells)
        if #spells >= 2 then
            c.combos[#c.combos + 1] = { spells = spells, color = combos[i].color }
            parts[#parts + 1] = "c" .. table.concat(spells, "+") .. ":" .. ColorText(combos[i].color)
        end
    end
    -- Color Border on a plate with no border has nothing to show.
    c.any = (#c.singles > 0 or #c.combos > 0) and (c.border ~= nil or mode ~= "border")
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

-------------------------------------------------------------------------------
-- While Missing: a slot only shows a debuff that is up, so a missing debuff
-- reads a hidden one-aura group (its sensor). The engine lays the group's
-- container out at 1x1 while the debuff is absent and SPAN wide while it is up
-- (AnchorUtil.ApplyFlowLayout); a mask on the container's right edge covers
-- the bar only in the first case, and the color draws through it. Groups can
-- never be removed, so a plate keeps its sensors and re-points them.
-------------------------------------------------------------------------------
local SENSOR_KEY = "EUI_DEBUFF_MISSING"
local REACH = 96   -- past each bar edge, for border art
-- The mask's size and the sensor's width while up: past the widest bar (the
-- Health Bar Width slider's max, 250) plus twice REACH. An 8px texture
-- stretched this far fades over its outer 32px, so border art up to 64px past
-- the bar draws at full strength.
local SPAN = 512
local kits = {}    -- plate -> { gate, hider, host, sensors, looks, used, unit, open }
local engagers = {}        -- you, your group and the pets out
local engagersStale = true -- a roster or pet change: the next read rebuilds the list
local groupTokens          -- the raid and party tokens and their pets', built once
local resync               -- the roster re-check's one-shot frame (RequestResync)

local function GroupTokens()
    if not groupTokens then
        groupTokens = { raid = {}, raidpet = {}, party = {}, partypet = {} }
        for i = 1, 40 do
            groupTokens.raid[i], groupTokens.raidpet[i] = "raid" .. i, "raidpet" .. i
        end
        for i = 1, 4 do
            groupTokens.party[i], groupTokens.partypet[i] = "party" .. i, "partypet" .. i
        end
    end
    return groupTokens
end

-- Whether an engager is on the mob's threat list (a mob fighting only
-- strangers is not). Only the type tag is read: the value can be secret.
local function Engaged(unit)
    if engagersStale then
        engagersStale = false
        local n = 1
        engagers[1] = "player"
        if UnitExists("pet") then
            n = 2
            engagers[2] = "pet"
        end
        local tokens, raid = GroupTokens(), IsInRaid()
        local who = raid and tokens.raid or tokens.party
        local pets = raid and tokens.raidpet or tokens.partypet
        for i = 1, math.min(GetNumGroupMembers() - (raid and 0 or 1), #who) do
            if not UnitIsUnit(who[i], "player") then
                n = n + 1
                engagers[n] = who[i]
                if UnitExists(pets[i]) then
                    n = n + 1
                    engagers[n] = pets[i]
                end
            end
        end
        for i = #engagers, n + 1, -1 do engagers[i] = nil end
    end
    for i = 1, #engagers do
        if type(UnitThreatSituation(engagers[i], unit)) ~= "nil" then return true end
    end
    return false
end

-- Shown on an engaged enemy: an assistable unit's debuffs cannot be spell-filtered.
-- nameGated: Color Name's Missing rows (see NameKit).
local function SyncGate(kit)
    local open = not UnitCanAssist("player", kit.unit, true, true) and Engaged(kit.unit)
    if open ~= kit.open then
        kit.open = open
        kit.gate:SetShown(open)
        if kit.nameGated then kit.nameGated:SetShown(open) end
    end
end

local function RunResync(self)
    self:Hide()
    self:SetScript("OnUpdate", nil)
    for _, kit in pairs(kits) do
        if kit.unit then SyncGate(kit) end
    end
end

-- Roster and pet changes come in bursts: the engager list goes stale at once
-- (a gate event in between reads it fresh), and the bound plates are checked
-- again once, on the next frame.
local function RequestResync()
    engagersStale = true
    if not resync then
        resync = CreateFrame("Frame")
        resync:Hide()
    end
    resync:SetScript("OnUpdate", RunResync)
    resync:Show()
end

local function Kit(plate)
    local kit = kits[plate]
    if kit then return kit end
    -- Only aspect-bearing objects may anchor to a container that holds a group,
    -- and the aspect is inherited at creation: the masks are born in the gate,
    -- and so is the host the Missing rows draw on (DressLook).
    local gate = CreateFrame("Frame", nil, plate.health, "DisableUntrustedLayoutScriptsTemplate")
    gate:SetAllPoints(plate.health)
    gate:Hide()
    local hider = CreateFrame("Frame", nil, plate.health)
    hider:SetAllPoints(plate.health)
    hider:SetAlpha(0)
    hider:Hide()
    local host = CreateFrame("Frame", nil, gate)
    host:SetAllPoints(gate)
    kit = { gate = gate, hider = hider, host = host, sensors = {}, looks = {}, used = 0 }
    gate:SetScript("OnEvent", function() SyncGate(kit) end)
    kits[plate] = kit
    return kit
end

-- Sensor n, pointed at spell. Its mask takes two anchors and a width: a single
-- point and a size draws displaced inside the plate (see PlaceArrow).
local function PointSensor(kit, n, spell)
    local AK = EllesmereUI.AuraKit
    local filter, ids = AK.Filter(unpack(config.filterTokens)), { includeSpellIDs = { [spell] = true } }
    local s = kit.sensors[n]
    if not s then
        local c = AK.CreateContainerShell(kit.hider, { point = { "TOPLEFT", kit.hider, "TOPLEFT", -(REACH + 1), REACH } })
        AK.AddGroupToContainer(c, { key = SENSOR_KEY, filter = config.filterTokens, maxFrameCount = 1,
            style = STYLE, candidateFilters = ids, layout = { elementWidth = SPAN, elementHeight = 1 },
            extraInit = function(button) button:EnableMouse(false) end })
        local mask = kit.gate:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, 0)
        mask:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, 1 - SPAN)
        mask:SetWidth(SPAN)
        s = { container = c, mask = mask, n = n }
        kit.sensors[n] = s
    elseif s.spell ~= spell or s.filter ~= filter then
        s.container:SetAuraGroupFilterString(SENSOR_KEY, filter)
        s.container:SetAuraGroupCandidateFilters(SENSOR_KEY, ids)
    end
    s.spell, s.filter = spell, filter
    AK.SetGroupCap(s.container, SENSOR_KEY, 1)
    return s
end

-- Sensors the bundle did not use are switched off (no UNIT_AURA work).
local function ParkSensors(kit)
    for n = kit.used + 1, #kit.sensors do
        EllesmereUI.AuraKit.SetGroupCap(kit.sensors[n].container, SENSOR_KEY, 0)
    end
end

-- The gate's events only while a Missing row reads it (Color Name binds a kit
-- for its sensors alone).
local function BindKit(kit, unit)
    for n = 1, kit.used do
        local s = kit.sensors[n]
        if s.unit ~= unit then
            s.unit = unit
            s.container:SetUnit(unit)
        end
    end
    kit.hider:Show()
    kit.unit, kit.open = unit, nil
    if config.anyMissing then
        kit.gate:RegisterUnitEvent("UNIT_FLAGS", unit)
        kit.gate:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
        SyncGate(kit)
    end
end

local function ParkKit(kit)
    kit.unit, kit.open = nil, nil
    kit.gate:UnregisterAllEvents()
    kit.gate:Hide()
    kit.hider:Hide()
    if kit.nameGated then kit.nameGated:Hide() end
end

-- A bundle a settings change replaces can never be freed (frames are permanent);
-- releasing its containers keeps their engine slots out of AuraKit's restyle
-- registry. Refresh runs this out of combat only.
local function ReleaseBundle(b)
    if b.holder then b.holder:Hide() end
    for _, container in ipairs(b.containers) do
        container:SetEnabled(false)
        EllesmereUI.AuraKit.ReleaseContainer(container)
    end
    if b.nameKit then
        b.nameKit.attached = nil
        b.nameKit.root:Hide()
    end
    if b.kit then ParkKit(b.kit) end
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

-- The health fill's tint: the bar's own texture in the color, over the fill.
local function PaintTint(tint, b, color)
    tint:SetTexture(b.config.texture)
    tint:SetVertexColor(color.r, color.g, color.b, 1)
    tint:ClearAllPoints()
    tint:SetPoint("TOPLEFT", b.fill, "TOPLEFT", 0, 0)
    tint:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT", 0, 0)
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
        PaintTint(tint, b, color)
        if b.mask then tint:AddMaskTexture(b.mask) end
    end
end

-- Color Border: the plate's border drawn again in the debuff color, just above
-- it (b.config.border, see BorderSpec), so the border reads as recolored while
-- its slot shows. Strips keep whole physical pixels in scale-1 space as the
-- plate scales, like the border's own (the PP scale guard); slices sit on the
-- textured border's own geometry.
-- The copies rank like the tints (a combo over the top single over the rest)
-- without moving past anything else. On a custom border's MEDIUM strata a copy
-- stays one level above the border and its sublevel ranks it (the frames that
-- share that level draw ARTWORK). A Basic copy shares the flattened plate with
-- the border's OVERLAY 7 strips, under which a lower sublevel sinks, so it keeps
-- OVERLAY 7 and ranks by frame level (no other plate frame uses those levels).

-- A copy's frame level: rank levels over the plate border it recolors (a custom
-- border's frame level as ns.ApplyCustomBorderStyle sets it; Basic counts from
-- the bar).
local function CopyLevel(b, spec, rank)
    local base = b.level
    if spec.behind ~= nil then
        base = spec.behind and math.max(1, b.level - 1) or (b.level + 1)
    end
    return base + spec.up + rank
end

-- A copy's frame and pieces, not yet colored or placed: four strips, or one
-- texture per edge-art slice (the shared cut table's keys). sensorMask: a
-- Missing row's; the pieces draw through a copy of it on their own frame (it
-- may draw on another strata).
local function NewBorderCopy(parent, spec, sensorMask)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    if spec.strata then f:SetFrameStrata(spec.strata) end
    local mask
    if sensorMask then
        mask = f:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(sensorMask)
    end
    local pieces = {}
    if spec.kind == "strips" then
        f:SetIgnoreParentScale(true)
        f:SetScale(1)
        for i = 1, 4 do
            local tx = f:CreateTexture(nil, "OVERLAY")
            if tx.SetSnapToPixelGrid then
                tx:SetSnapToPixelGrid(false)
                tx:SetTexelSnappingBias(0)
            end
            pieces[i] = tx
        end
    else
        for key, coords in pairs(EllesmereUI.SECRET_BORDER_UV) do
            local tx = f:CreateTexture(nil, "OVERLAY")
            tx:SetTexCoord(unpack(coords))
            pieces[key] = tx
        end
    end
    if mask then
        for _, tx in pairs(pieces) do tx:AddMaskTexture(mask) end
    end
    return f, pieces
end

local function LayStrip(tx, f, p1, y1, p2, y2, width, height)
    tx:SetPoint(p1, f, p1, 0, y1)
    tx:SetPoint(p2, f, p2, 0, y2)
    if width then tx:SetWidth(width) else tx:SetHeight(height) end
end

-- Colors a copy and lays it over owner (the bar's rect), on OVERLAY sublevel.
local function DressBorderCopy(f, pieces, spec, owner, color, sublevel)
    f:ClearAllPoints()
    f:SetAllPoints(owner)
    for _, tx in pairs(pieces) do
        tx:SetDrawLayer("OVERLAY", sublevel)
        tx:ClearAllPoints()
    end
    if spec.kind == "strips" then
        local ok, es = pcall(f.GetEffectiveScale, f)
        if not (ok and es and es > 0) then es = 1 end
        local one = EllesmereUI.PP.perfect / es
        local t = math.max(one, math.floor(spec.px + 0.5) * one)
        for _, tx in ipairs(pieces) do tx:SetColorTexture(color.r, color.g, color.b, 1) end
        LayStrip(pieces[1], f, "TOPLEFT", 0, "TOPRIGHT", 0, nil, t)
        LayStrip(pieces[2], f, "BOTTOMLEFT", 0, "BOTTOMRIGHT", 0, nil, t)
        LayStrip(pieces[3], f, "TOPLEFT", -t, "BOTTOMLEFT", t, t)
        LayStrip(pieces[4], f, "TOPRIGHT", -t, "BOTTOMRIGHT", t, t)
    else
        for _, tx in pairs(pieces) do
            tx:SetTexture(spec.path, true, true)
            tx:SetVertexColor(color.r, color.g, color.b, 1)
        end
        local edge, aL, aT, aR, aB = EllesmereUI.SecretBorderGeometry(f, spec.size, spec.tex,
            spec.offX, spec.offY, spec.shX, spec.shY, "nameplates", spec.size, nil, spec.px)
        EllesmereUI.LayoutSecretBorderEdges(pieces, f, edge, aL, aT, aR, aB)
    end
end

-- A slot's copy, built in the creation window only.
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
        local f, pieces = NewBorderCopy(button, spec)
        f:SetFrameLevel(CopyLevel(b, spec, rank))
        DressBorderCopy(f, pieces, spec, b.holder, color, sublevel)
    end
end

-- What a slot shows while its debuffs are up: the health fill's tint (Color
-- Nameplate) or the border in the color (Color Border).
local function ColorInit(b, color, sublevel)
    if b.config.border then return MakeBorderInit(b, color, sublevel) end
    return MakeTintInit(b, color, sublevel)
end

-- Missing row n draws on the kit's host through sensor n's mask: a tint on
-- OVERLAY at the bar's level (one higher draws over the border), or a copy
-- ranked over every other copy by n. These frames are ours, unlike the slots'
-- engine buttons, so each is built once (a copy once per border style) and
-- dressed again on every rebuild.
local function DressLook(b, sensor, color, sublevel)
    local kit, n = b.kit, sensor.n
    local look = kit.looks[n]
    if not look then
        look = { copies = {} }
        kit.looks[n] = look
    end
    local spec = b.config.border
    if not spec then
        local tint = look.tint
        if not tint then
            tint = kit.host:CreateTexture(nil, "OVERLAY")
            if b.mask then tint:AddMaskTexture(b.mask) end
            tint:AddMaskTexture(sensor.mask)
            look.tint = tint
        end
        tint:SetDrawLayer("OVERLAY", sublevel)
        PaintTint(tint, b, color)
        tint:Show()
        return
    end
    local rank = 0
    if not spec.strata then rank, sublevel = 2, 7 end
    local style = spec.kind .. (spec.strata or "")
    local copy = look.copies[style]
    if not copy then
        local f, pieces = NewBorderCopy(kit.host, spec, sensor.mask)
        copy = { frame = f, pieces = pieces }
        look.copies[style] = copy
    end
    copy.frame:SetFrameLevel(CopyLevel(b, spec, rank) + n)
    DressBorderCopy(copy.frame, copy.pieces, spec, kit.host, color, sublevel)
    copy.frame:Show()
end

local function HideLooks(kit)
    for _, look in ipairs(kit.looks) do
        if look.tint then look.tint:Hide() end
        for _, copy in pairs(look.copies) do copy.frame:Hide() end
    end
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

-------------------------------------------------------------------------------
-- Color Name: the plate's name drawn again in the color, over the name. Font
-- strings take no masks, so each copy sits inside clip frames hung on the
-- While Missing sensors (one per debuff spell): a clip covers the name while
-- its sensor's container is SPAN wide (the debuff is up) or, for a Missing
-- row, while it is a single pixel. A combo nests one clip per debuff, so its
-- copy shows only while every one is up. These frames are ours: a plate keeps
-- them across rebuilds and re-points them, and the copies follow the name's
-- text, font and placement through ns.DebuffColors_NameChanged.
-------------------------------------------------------------------------------
local CLIP_REACH = 300  -- above and below a sensor (REACH over the bar): past any name slot
local CHAIN_STEP = 5    -- frame levels per row (a combo nests up to four clips)
local nameKits = {}     -- plate -> { root, gated, chains, used, attached }

-- root rides the name's host (MirrorName); gated holds the Missing rows and is
-- shown with the kit's gate. Born with the aspect: only such frames may anchor
-- to a container that holds a group, and their clips inherit it.
local function NameKit(plate, kit)
    local nk = nameKits[plate]
    if not nk then
        local root = CreateFrame("Frame", nil, plate, "DisableUntrustedLayoutScriptsTemplate")
        root:SetAllPoints(plate.health)
        root:Hide()
        local gated = CreateFrame("Frame", nil, root)
        gated:SetAllPoints(root)
        nk = { root = root, gated = gated, chains = {}, used = 0 }
        nameKits[plate] = nk
    end
    kit.nameGated = nk.gated
    nk.gated:SetShown(kit.open == true)
    return nk
end

-- Row i's chain: depth clips, each inside the last, the copy in the innermost.
-- Pooled by index; a row that needs more clips adds them.
local function Chain(nk, i, depth, parent)
    local ch = nk.chains[i]
    if not ch then
        ch = { clips = {} }
        nk.chains[i] = ch
    end
    local clips = ch.clips
    for d = 1, depth do
        local want = (d == 1) and parent or clips[d - 1]
        local clip = clips[d]
        if not clip then
            clip = CreateFrame("Frame", nil, want)
            clip:SetClipsChildren(true)
            clips[d] = clip
        elseif clip:GetParent() ~= want then
            clip:SetParent(want)
        end
        clip:Show()
    end
    for d = depth + 1, #clips do clips[d]:Hide() end
    ch.depth = depth
    local inner = clips[depth]
    if not ch.copy then
        ch.copy = inner:CreateFontString(nil, "OVERLAY")
    elseif ch.copy:GetParent() ~= inner then
        ch.copy:SetParent(inner)
    end
    return ch
end

-- A clip open while its debuff is up (the sensor's container SPAN wide), or
-- for a Missing row while it is absent (a single pixel; the mask's placement).
local function AnchorClip(clip, sensor, missing)
    local c = sensor.container
    clip:ClearAllPoints()
    if missing then
        clip:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, CLIP_REACH)
        clip:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, -CLIP_REACH)
        clip:SetWidth(SPAN)
    else
        clip:SetPoint("TOPLEFT", c, "TOPLEFT", 0, CLIP_REACH)
        clip:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -CLIP_REACH)
    end
end

-- A later row draws over an earlier one, every row over the name itself. Each
-- frame takes the root's strata itself, parents first: on the flattened plate a
-- frame that only inherits it renders in the plate's own batch, under the name,
-- and a parent's strata change resets its children's strata and levels.
local function LevelChains(nk)
    local strata, base = nk.root:GetFrameStrata(), nk.root:GetFrameLevel()
    nk.gated:SetFrameStrata(strata)
    nk.gated:SetFrameLevel(base)
    for i = 1, nk.used do
        local ch = nk.chains[i]
        for d = 1, ch.depth do
            local clip = ch.clips[d]
            clip:SetFrameStrata(strata)
            clip:SetFrameLevel(base + (i - 1) * CHAIN_STEP + d)
        end
    end
end

-- The copies follow the name: its host (and so its strata), its shown state,
-- font, shadow, justification, wrapping and text. The text may be secret: it
-- only passes from one font string to the others. shownOnly: just the shown
-- state (the name hides while casting, a hot path).
local function MirrorName(plate, shownOnly)
    local b = bundles[plate]
    local nk = b and b.nameKit
    if not nk then return end
    local name, root = plate.name, nk.root
    root:SetShown(nk.attached == true and name:IsShown())
    if shownOnly then return end
    -- The host's own strata change (SlotTextHost) reaches its children, so the
    -- strata and levels are set again on every pass.
    local host = name:GetParent()
    if root:GetParent() ~= host then root:SetParent(host) end
    root:SetFrameStrata(host:GetFrameStrata())
    root:SetFrameLevel(host:GetFrameLevel() + 1)
    LevelChains(nk)
    local font, size, flags = name:GetFont()
    local sr, sg, sb, sa = name:GetShadowColor()
    local sx, sy = name:GetShadowOffset()
    local jh, jv = name:GetJustifyH(), name:GetJustifyV()
    local wrap, nsWrap, lines = name:CanWordWrap(), name:CanNonSpaceWrap(), name:GetMaxLines()
    local text = name:GetText()
    for i = 1, nk.used do
        local fs = nk.chains[i].copy
        if font then fs:SetFont(font, size, flags or "") end
        fs:SetShadowColor(sr, sg, sb, sa)
        fs:SetShadowOffset(sx, sy)
        fs:SetJustifyH(jh)
        fs:SetJustifyV(jv)
        fs:SetWordWrap(wrap)
        fs:SetNonSpaceWrap(nsWrap)
        fs:SetMaxLines(lines)
        fs:SetText(text)
    end
end

-- The rows bottom to top, as the tints rank: the single debuffs, then the
-- combos, then the Missing ones by their sublevel (the first listed on top).
local function NameEntries(c)
    local out, missing = {}, {}
    for _, e in ipairs(c.singles) do
        if e.missing then
            missing[#missing + 1] = e
        else
            out[#out + 1] = { spells = { e.spell }, color = e.color }
        end
    end
    for _, combo in ipairs(c.combos) do
        out[#out + 1] = { spells = combo.spells, color = combo.color }
    end
    table.sort(missing, function(x, y) return x.sublevel < y.sublevel end)
    for _, e in ipairs(missing) do
        out[#out + 1] = { spells = { e.spell }, color = e.color, missing = true }
    end
    return out
end

-- One sensor per debuff spell, shared by every row that names it.
local function CreateNameBundle(plate)
    local kit = Kit(plate)
    -- Nothing of Color Name draws on the kit's host: hide the tints and border
    -- copies a Missing row left there in another mode, or they show again
    -- whenever the gate opens for the name's own Missing rows.
    HideLooks(kit)
    local nk = NameKit(plate, kit)
    local b = { config = config, kit = kit, nameKit = nk, containers = {} }
    kit.used = 0
    local sensorOf = {}
    for i, e in ipairs(config.nameEntries) do
        local ch = Chain(nk, i, #e.spells, e.missing and nk.gated or nk.root)
        for d, spell in ipairs(e.spells) do
            local s = sensorOf[spell]
            if not s then
                kit.used = kit.used + 1
                s = PointSensor(kit, kit.used, spell)
                sensorOf[spell] = s
            end
            AnchorClip(ch.clips[d], s, e.missing)
        end
        local fs = ch.copy
        fs:ClearAllPoints()
        fs:SetAllPoints(plate.name)
        fs:SetTextColor(e.color.r, e.color.g, e.color.b, 1)
    end
    nk.used = #config.nameEntries
    for i = nk.used + 1, #nk.chains do nk.chains[i].clips[1]:Hide() end
    ParkSensors(kit)
    LevelChains(nk)
    bundles[plate] = b
    return b
end

-- The tints share one frame level (the target/focus/hover patterns sit one
-- level up), so a later-declared slot draws on top: ReadConfig orders them.
local function CreateBundle(plate)
    if config.name then return CreateNameBundle(plate) end
    local b = {
        config = config,
        fill = plate.health:GetStatusBarTexture(), mask = plate._absorbMask,
        level = plate.health:GetFrameLevel(), containers = {},
        kit = config.anyMissing and Kit(plate) or nil,
    }
    -- Tint shares the fill's frame level; EUI's text, target/focus patterns,
    -- border and absorb effects keep their own higher layers.
    b.holder = CreateFrame("Frame", nil, plate.health)
    b.holder:SetAllPoints(plate.health)
    b.holder:SetFrameLevel(b.level)
    b.holder:EnableMouse(false)
    b.holder:Hide()
    local root = CreateTintContainer(b, b.holder)
    local kit = b.kit
    if kit then
        kit.used = 0
        kit.host:SetFrameLevel(b.level)
        HideLooks(kit)
    end
    for i, single in ipairs(config.singles) do
        if single.missing then
            kit.used = kit.used + 1
            DressLook(b, PointSensor(kit, kit.used, single.spell), single.color, single.sublevel)
        else
            AddTintSlot(b, root, "EUI_DEBUFF_COLOR_" .. i, single.spell,
                ColorInit(b, single.color, single.sublevel))
        end
    end
    if kit then ParkSensors(kit) end
    for i, run in ipairs(config.comboRuns) do
        AddComboRun(b, root, "EUI_DEBUFF_COMBO_" .. i, run)
    end
    bundles[plate] = b
    return b
end

-------------------------------------------------------------------------------
-- Bad threat: the plate's threat colors as UpdateHealthColor reads them, one
-- alpha per channel, 1 while nothing is wrong, 0 on bad threat (a non-tank with
-- or near aggro, a tank without or losing it), or the off-tank fold's secret
-- answer where only another tank's hold decides. The coloring yields where that
-- threat color shows under it: the health bar for the tints, the Threat Colors
-- border for Color Border, their name for Color Name. Kept on the plate (ours)
-- so a bundle built later takes it; an alpha, not a hide, so the containers
-- keep their aura data.
-------------------------------------------------------------------------------
local function ApplyThreat(b, plate)
    local a
    if b.config.channel == "border" then
        a = plate._dcThreatB
    elseif b.config.channel == "name" then
        a = plate._dcThreatN
    else
        a = plate._dcThreatH
    end
    if type(a) == "nil" then a = 1 end
    if issecretvalue(a) then
        b.threatA = nil
    elseif a == b.threatA then
        return
    else
        b.threatA = a
    end
    if b.holder then b.holder:SetAlpha(a) end
    if b.kit then b.kit.host:SetAlpha(a) end
    if b.nameKit then b.nameKit.root:SetAlpha(a) end
end

local function Threat(plate, healthA, borderA, nameA)
    plate._dcThreatH, plate._dcThreatB, plate._dcThreatN = healthA, borderA, nameA
    local b = bundles[plate]
    if b then ApplyThreat(b, plate) end
end

local function Attach(plate, unit)
    local b = bundles[plate] or CreateBundle(plate)
    if b.nameKit then
        BindKit(b.kit, unit)
        b.nameKit.attached = true
        MirrorName(plate)
        ApplyThreat(b, plate)
        return
    end
    -- Parent level changes propagate to all descendants. Touch only the ordinary
    -- holder; a nested container inherits its secure AuraButton's restrictions.
    b.level = plate.health:GetFrameLevel()
    b.holder:SetFrameLevel(b.level)
    if b.kit then BindKit(b.kit, unit) end
    BindBundle(b, unit)
    ApplyThreat(b, plate)
end

-- Parking is a hide, at once even while a parse is pending; the containers
-- keep their binding (see BindBundle). The plate's threat state is the last
-- unit's: its next one arrives with UpdateHealthColor.
local function Detach(plate)
    plate._dcThreatH, plate._dcThreatB, plate._dcThreatN = nil, nil, nil
    local b = bundles[plate]
    if not b then return end
    if b.holder then b.holder:Hide() end
    if b.nameKit then
        b.nameKit.attached = nil
        b.nameKit.root:Hide()
    end
    if b.kit then ParkKit(b.kit) end
end

local function EnsureWorker()
    if worker then return worker end
    worker = CreateFrame("Frame")
    worker:Hide()
    -- PLAYER_REGEN_ENABLED, held only while a combat-deferred refresh waits;
    -- DISPLAY_SIZE_CHANGED, held only while border strips are built (they are
    -- sized in physical pixels, so a resolution change redraws them);
    -- GROUP_ROSTER_UPDATE and UNIT_PET (yours or your group's), held only while
    -- a Missing row exists (who counts as engaged).
    worker:SetScript("OnEvent", function(self, event, unit)
        if event == "DISPLAY_SIZE_CHANGED" then
            ns.DebuffColors_RequestRefresh()
            return
        elseif event == "UNIT_PET" and unit ~= "player"
            and not (unit or ""):find("^party%d") and not (unit or ""):find("^raid%d") then
            return
        elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
            RequestResync()
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
        if config.name then config.nameEntries = NameEntries(config) end
        local AK = EllesmereUI.AuraKit
        AK.styles[STYLE] = AK.styles[STYLE] or { noRegions = true, noTooltips = true }
        ns.DebuffColors_Attach, ns.DebuffColors_Detach = Attach, Detach
        ns.DebuffColors_Threat = Threat
        ns.DebuffColors_NameChanged = config.name and MirrorName or nil
        for unit, plate in pairs(ns.plates) do Attach(plate, unit) end
        -- Every plate's threat state, read again now that the bundles take it.
        for _, plate in pairs(ns.plates) do plate:UpdateHealthColor() end
    else
        -- Nothing to color: no plate hooks. An enabled config stays as the
        -- applied state the next refresh compares against.
        ns.DebuffColors_Attach, ns.DebuffColors_Detach = nil, nil
        ns.DebuffColors_Threat, ns.DebuffColors_NameChanged = nil, nil
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
    engagersStale = true
    local watchRoster = config and config.any and config.anyMissing
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
        if watchRoster then
            EnsureWorker():RegisterEvent(event)
        elseif worker then
            worker:UnregisterEvent(event)
        end
    end
    if not watchRoster and resync then
        resync:SetScript("OnUpdate", nil)
        resync:Hide()
    end
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
