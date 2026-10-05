"""Exercise the shipped Debuff Colors Lua module against a visibility-driven aura engine.

Engine button reads and post-initialization writes deliberately fail. Aura
changes only go through the mock engine, never through addon aura events.
As in the live engine, a container is born enabled on unit "none", a hidden
one processes nothing and a shown one reads its unit in full. By default a
slot's button is born at its first matching aura; --eager creates it at
declaration instead (the live engine's batches). Either way a tint ranks by
its slot path from the root (each level's declaration order), so a
later-declared slot draws on top, and a combo (a nested chain) draws above
every single debuff.

Run: python .tools/tests/test_nameplate_debuff_colors.py [--eager]  (needs lupa)
"""
from pathlib import Path
import sys
from lupa import lua51

ROOT = Path(__file__).resolve().parents[2]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().EAGER = '--eager' in sys.argv
lua.execute(r'''
ns = { defaults = { debuffColorsEnabled = false, debuffColorsPlayerOnly = true,
    debuffColorsBorder = false, debuffColorsBorderExtra = 0,
    healthBarTexture = "custom", customBorderTexture = "solid", customBorderSize = 1 },
    plates = {}, healthBarTextures = {} }
profile = {}
ns.db = { profile = profile }
function ns.NP_GetProfile() return profile end
function UseProfile(t) profile = t; ns.db.profile = t end
EllesmereUI = {
    IS_FOREVER = false,
    ResolveTexturePath = function(_, key) return "test-texture-" .. key end,
}
-- The plate border Color Border draws over (the nameplate main file's helpers),
-- set per case: Basic by default.
border = { blizz = false, custom = false, basic = true, size = 1 }
function ns.NP_Blizz() return border.blizz end
function ns.IsCustomBorderEnabled() return border.custom end
function ns.IsBorderEnabled() return border.basic end
function ns.NP_BorderSize() return border.size end
EllesmereUI.PP = { perfect = 0.5, mult = 0.75 }
-- The exact size string ("px|step|texture") counts only for its own step and texture.
function EllesmereUI.BorderPx(value, step, tex)
    if type(value) ~= "string" then return nil end
    local px, s, t = value:match("^(%d+)|(%d+)|(.*)$")
    px, s = tonumber(px), tonumber(s)
    if not px or px <= 0 or s ~= step then return nil end
    if not tex or tex == "" then tex = "solid" end
    if t ~= tex then return nil end
    return px
end
function EllesmereUI.ResolveBorderTexture(key) if key == "pixels" then return "path-pixels" end end
EllesmereUI.SECRET_BORDER_UV = {}
for i, key in ipairs({ "topLeft", "topRight", "bottomLeft", "bottomRight", "top", "bottom", "left", "right" }) do
    EllesmereUI.SECRET_BORDER_UV[key] = { i, i + 0.5 }
end
geometry = {}
function EllesmereUI.SecretBorderGeometry(owner, size, tex, ox, oy, sx, sy, addon, sizeKey, edgeScale, edgePx)
    geometry[#geometry+1] = { owner=owner, size=size, tex=tex, ox=ox, oy=oy, sx=sx, sy=sy,
        addon=addon, sizeKey=sizeKey, edgeScale=edgeScale, px=edgePx }
    return 7, -1, 2, 3, -4
end
pxReapply = {}
function EllesmereUI.RegisterPxReapply(owner, fn) pxReapply.owner, pxReapply.fn = owner, fn end
C_AddOns = { IsAddOnLoaded = function() return true end }
function UnitClass() return "Druid", "DRUID" end
combat = false
function InCombatLockdown() return combat end
function forbidden() error("addon read restricted aura state") end
C_UnitAuras = setmetatable({}, { __index = forbidden })
UnitAura, UnitDebuff, UnitGUID = forbidden, forbidden, forbidden

frames, containers, textures = {}, {}, {}
local states = {} -- engine-private visibility state, unavailable to addon
local unitAuras = {}
local methods = {}
local declared = 0
local function Mutable(self)
    assert(not states[self].locked, "write to forbidden AuraButton/texture")
end
function methods:SetFrameLevel(level) Mutable(self); states[self].level = level end
function methods:GetFrameLevel() assert(not states[self].locked); return states[self].level or 10 end
function methods:SetAllPoints(anchor) Mutable(self); states[self].anchor = anchor end
function methods:SetPoint(...) Mutable(self); table.insert(states[self].points, {...}) end
function methods:SetSize(w, h) Mutable(self); states[self].size = { w, h } end
function methods:SetAlpha(alpha) Mutable(self); states[self].alpha = alpha end
function UIState(obj) return states[obj] end
function methods:EnableMouse(value) Mutable(self); states[self].mouse = value end
function methods:SetVertexColor(...) Mutable(self); states[self].color = {...} end
function methods:AddMaskTexture(mask) Mutable(self); states[self].mask = mask end
function methods:Hide() Mutable(self); states[self].shown = false end
function methods:Show() Mutable(self); states[self].shown = true end
function methods:IsShown() error("addon inspected engine-owned visibility") end
function methods:GetParent() error("addon inspected engine-owned parent") end
function methods:RegisterEvent(event) states[self].events[event] = true end
function methods:UnregisterEvent(event) states[self].events[event] = nil end
function methods:SetScript(event, callback) states[self].scripts[event] = callback end
local calls = { enabled = 0, unit = 0 }
function methods:SetEnabled(enabled) states[self].enabled = enabled; calls.enabled = calls.enabled + 1 end
function methods:SetUnit(unit) states[self].unit = unit; calls.unit = calls.unit + 1 end
function ResetCalls() calls.enabled, calls.unit = 0, 0 end
function Calls() return calls.enabled, calls.unit end
function methods:GetStatusBarTexture() return states[self].fill end
function methods:SetFrameStrata(strata) Mutable(self); states[self].strata = strata end
function methods:SetIgnoreParentScale(v) Mutable(self); states[self].ignoreParentScale = v end
function methods:SetScale(v) Mutable(self); states[self].scale = v end
function methods:GetEffectiveScale()
    assert(not states[self].locked)
    return states[self].ignoreParentScale and (states[self].scale or 1) or 0.8
end
function methods:SetColorTexture(r, g, b, a) Mutable(self); states[self].color = { r, g, b, a } end
function methods:SetSnapToPixelGrid(v) Mutable(self); states[self].snap = v end
function methods:SetTexelSnappingBias(v) Mutable(self); states[self].bias = v end
function methods:SetWidth(w) Mutable(self); states[self].width = w end
function methods:SetHeight(h) Mutable(self); states[self].height = h end
function methods:SetTexCoord(...) Mutable(self); states[self].texCoord = {...} end
function methods:SetTexture(value, wrapH, wrapV)
    Mutable(self); states[self].texture = value; states[self].wrap = { wrapH, wrapV }
end
function EllesmereUI.LayoutSecretBorderEdges(edges, owner, edge, aL, aT, aR, aB)
    for key, tx in pairs(edges) do
        Mutable(tx)
        states[tx].slice, states[tx].layout = key, { owner=owner, edge=edge, aL=aL, aT=aT, aR=aR, aB=aB }
    end
end

local function New(kind, parent)
    local obj = setmetatable({}, { __index = methods })
    states[obj] = { kind=kind, parent=parent, shown=true, level=10,
        points={}, scripts={}, events={}, slots={} }
    frames[#frames+1] = obj
    return obj
end
function CreateFrame(kind, _, parent, template)
    if kind == "AuraContainer" then
        assert(template == "CustomAuraContainerTemplate")
    end
    local obj = New(kind, parent)
    if kind == "AuraContainer" then
        -- The intrinsic AuraContainer's KeyValues: enabled, on unit "none".
        states[obj].enabled, states[obj].unit = true, "none"
        containers[#containers+1] = obj
    end
    return obj
end
function methods:CreateTexture(_, layer, _, sublevel)
    Mutable(self)
    local tex = New("Texture", self)
    states[tex].layer, states[tex].sublevel = layer, sublevel
    textures[#textures+1] = tex
    return tex
end
local function Birth(slot)
    slot.button = New("AuraButton", slot.container)
    states[slot.button].slot = slot
    local first = #frames + 1
    slot.init(slot.button)
    states[slot.button].locked = true
    -- What the init decorated is engine-owned afterwards: its textures and
    -- plain frames (a nested container stays the kit's).
    for i = first, #frames do
        local kind = states[frames[i]].kind
        if kind == "Texture" or kind == "Frame" then states[frames[i]].locked = true end
    end
end
function methods:AddAuraSlot(key, filter, spec)
    assert(states[self].kind == "AuraContainer")
    assert(filter == "HARMFUL|PLAYER" or filter == "HARMFUL")
    assert(spec.candidateFilters.includeSpellIDs)
    assert(not states[self].slots[key], "slot key reused within one container")
    declared = declared + 1
    local slot = { filter=filter, ids=spec.candidateFilters.includeSpellIDs,
        init=spec.initializeFrame, decl=declared, container=self }
    states[self].slots[key] = slot
    if EAGER then Birth(slot) end
end
function SlotCount(container)
    local n = 0
    for _ in pairs(states[container].slots) do n = n + 1 end
    return n
end
-- The plate's current bundle root (its holder is shown), and how many
-- containers that bundle owns, nested ones included.
function RootOf(plate)
    for i = #containers, 1, -1 do
        local c = containers[i]
        local holder = states[c].parent
        if states[holder].kind == "Frame" and states[holder].parent == plate.health
            and states[holder].shown and states[c].shown then
            return c
        end
    end
end
function LiveContainers(plate)
    local holder = states[RootOf(plate)].parent
    local n = 0
    for _, c in ipairs(containers) do
        local obj = c
        while obj and obj ~= holder do obj = states[obj].parent end
        if obj then n = n + 1 end
    end
    return n
end

local function Matches(slot, unit)
    for _, aura in ipairs(unitAuras[unit] or {}) do
        if slot.ids[aura.id] and (slot.filter == "HARMFUL" or aura.mine) then return true end
    end
    return false
end
local function Visible(obj)
    local state = states[obj]
    if not state.shown then return false end
    return not state.parent or Visible(state.parent)
end
local function UpdateEngine()
    local i = 1
    while i <= #containers do
        local c = containers[i]
        local state = states[c]
        -- A hidden container processes nothing; a shown one reads its unit in
        -- full (the live engine's parse on show).
        if Visible(c) then
            for _, slot in pairs(state.slots) do
                local active = state.enabled and Matches(slot, state.unit)
                if active and not slot.button then Birth(slot) end
                if slot.button then states[slot.button].shown = active end
            end
        end
        i = i + 1
    end
end
function Auras(unit, auras) unitAuras[unit] = auras; UpdateEngine() end
-- Draw order: buttons are born in declaration order (a nested container's
-- slots inside its button's init), so a tint ranks by its slot path from the
-- root, each level's declaration index in turn; a nested chain (a combo)
-- also sits above every root-level tint.
local function Rank(tex)
    local path = {}
    local owner = states[tex].parent
    while owner and not states[owner].slot do owner = states[owner].parent end
    local slot = owner and states[owner].slot
    while slot do
        table.insert(path, 1, string.format("%08d", slot.decl))
        slot = states[states[slot.container].parent].slot
    end
    return (#path > 1 and "1:" or "0:") .. table.concat(path, ".")
end
-- Color Nameplate: the top visible tint (a texture right in a slot button).
function Paint(plate)
    UpdateEngine()
    local chosen, best
    for _, tex in ipairs(textures) do
        local state = states[tex]
        if state.color and Visible(tex) and states[state.parent].kind == "AuraButton" then
            local parent = tex
            while parent and parent ~= plate.health do parent = states[parent].parent end
            if parent then
                local rank = Rank(tex)
                if not best or rank > best then chosen, best = state, rank end
            end
        end
    end
    return chosen
end
function NewPlate(unit)
    local plate = { health=New("StatusBar"), _absorbMask={} }
    states[plate.health].fill = New("Texture", plate.health)
    states[plate.health].baseColor = { .2, .3, .4 }
    plate.unit = unit
    ns.plates[unit] = plate
    return plate
end
function AssertColor(plate, r, g, b, msg)
    local painted = Paint(plate)
    if r == nil then assert(not painted, msg or "stale debuff tint"); return end
    assert(painted, msg or "missing active tint")
    assert(painted.color[1] == r and painted.color[2] == g and painted.color[3] == b,
        (msg or "wrong tint") .. ": got " .. tostring(painted.color[1]) .. "," ..
        tostring(painted.color[2]) .. "," .. tostring(painted.color[3]))
    assert(painted.texture == "test-texture-" .. (profile.healthBarTexture or "custom"))
    assert(painted.mask == plate._absorbMask)
    assert(painted.points[1][2] == states[plate.health].fill)
    assert(painted.points[2][2] == states[plate.health].fill)
    assert(states[plate.health].baseColor[1] == .2, "mutated base health color")
end
-- Color Border: the top visible border drawn in a slot (a plain frame in a slot
-- button holding the pieces): its state and its pieces' states.
function BorderPaint(plate)
    UpdateEngine()
    local chosen, best
    for _, f in ipairs(frames) do
        local state = states[f]
        local button = state.parent
        if state.kind == "Frame" and button and states[button].kind == "AuraButton" and Visible(f) then
            local parent = f
            while parent and parent ~= plate.health do parent = states[parent].parent end
            if parent then
                local rank = Rank(f)
                if not best or rank > best then chosen, best = f, rank end
            end
        end
    end
    if not chosen then return nil end
    local pieces = {}
    for _, tex in ipairs(textures) do
        if states[tex].parent == chosen then pieces[#pieces+1] = states[tex] end
    end
    return states[chosen], pieces
end
function AssertBorder(plate, r, g, b, msg)
    local f, pieces = BorderPaint(plate)
    if r == nil then assert(not f, msg or "stale debuff border"); return end
    assert(f, msg or "missing debuff border")
    assert(#pieces == 4 or #pieces == 8, "a debuff border without its pieces")
    for _, piece in ipairs(pieces) do
        local c = piece.color
        assert(c and c[1] == r and c[2] == g and c[3] == b and c[4] == 1,
            (msg or "wrong border color") .. ": got " .. tostring(c and c[1]) .. "," ..
            tostring(c and c[2]) .. "," .. tostring(c and c[3]))
    end
    assert(not Paint(plate), "Color Border also tinted the health bar")
    assert(states[plate.health].baseColor[1] == .2, "mutated base health color")
    return f, pieces
end
function RunWorker()
    for _, frame in ipairs(frames) do
        if states[frame].shown and states[frame].scripts.OnUpdate then
            states[frame].scripts.OnUpdate(frame, .2)
        end
    end
end
-- The frames registered for an event (none while nothing needs it).
function Watching(event)
    local n = 0
    for _, frame in ipairs(frames) do
        if states[frame].events[event] then n = n + 1 end
    end
    return n
end
function FireEvent(event)
    for _, frame in ipairs(frames) do
        if states[frame].events[event] then states[frame].scripts.OnEvent(frame, event) end
    end
end
-- Where the plate's own custom border draws, as the nameplate module places
-- it (ns.ApplyCustomBorderStyle): its frame one level above the bar (one below
-- when behind); a textured border on that frame, a Solid one on the pixel
-- border's container one level higher.
function CustomBorderLevel(plate, behind, solid)
    local bar = states[plate.health].level
    local frame = behind and math.max(1, bar - 1) or (bar + 1)
    return solid and frame + 1 or frame
end
function Regen()
    combat = false
    for _, frame in ipairs(frames) do
        if states[frame].events.PLAYER_REGEN_ENABLED then states[frame].scripts.OnEvent(frame) end
    end
end
''')
load = lua.eval('function(src) return assert(loadstring(src)) end')

# Exercise the actual shared kit's shell/slot/release wrappers and bare
# initializer. Standard icon styling is not needed for a presence-only slot.
kit = (ROOT / 'EllesmereUI_AuraKit.lua').read_text()
kit_init = 'function AK.MakeInitializer' + kit.split('function AK.MakeInitializer', 1)[1].split(
    'function AK.CreateStyledCell', 1)[0]
kit_slots = 'function AK.CreateContainerShell' + kit.split('function AK.CreateContainerShell', 1)[1].split(
    '------------------------------------------------------------------------------\n-- Item enchantments', 1)[0]
kit_release = 'function AK.ReleaseContainer' + kit.split('function AK.ReleaseContainer', 1)[1].split(
    '------------------------------------------------------------------------------', 1)[0]
lua.execute(r'''
EllesmereUI.AuraKit = {styles={}, ApplyContainerLayout=function() end}
function EllesmereUI.AuraKit.Filter(...) return table.concat({...}, "|") end
''')
load(r'''
local AK = ...
local bd, containerData, styleButtons = {}, {}, {}
local function ApplyStyleToRegions(button, style)
    assert(style.noRegions, "presence slot allocated standard icon regions")
    button:SetSize(style.width or 32, style.height or style.width or 32)
end
local function GetStyleSet(key)
    styleButtons[key] = styleButtons[key] or {}
    return styleButtons[key]
end
''' + kit_init + kit_slots + kit_release)(lua.globals().EllesmereUI.AuraKit)
load((ROOT / 'EllesmereUINameplates/EllesmereUINameplates_DebuffColors.lua').read_text())('test', lua.globals().ns)
lua.execute(r'''
local DC = ns.DebuffColorKit
local ORANGE, RED, GREEN, BLUE, PURPLE = "1,0.43,0.04", "0.8,0.2,0.1", "0.1,0.88,0.32", "0.2,0.4,1", "0.6,0.2,0.8"

-- The list codec: round trips, 4-decimal colors, tolerant parsing, caps.
local s, c = DC.Parse("703:" .. ORANGE .. ";0:1,1,1/703+1943:" .. GREEN)
assert(#s == 2 and s[1].spell == 703 and s[2].spell == 0 and s[1].color.g == .43)
assert(#c == 1 and c[1].spells[1] == 703 and c[1].spells[2] == 1943 and c[1].color.r == .1)
assert(DC.Encode(s, c) == "703:" .. ORANGE .. ";0:1,1,1/703+1943:" .. GREEN)
assert(DC.Encode({}, {}) == nil, "an empty list left a saved value")
assert(DC.Encode({ { spell = 5, color = { r = 0.43137254, g = 0, b = 1 } } }, {}) == "5:0.4314,0,1/")
s, c = DC.Parse("junk;x:1,2;703:bad/9+x:7,7")
assert(#s == 3 and s[1].spell == 0 and s[3].spell == 703 and s[3].color.r == 1 and s[3].color.g == .43)
assert(s[2].color.r == DC.SINGLE_COLOR.r, "a malformed color did not fall back")
assert(#c == 1 and #c[1].spells == 1 and c[1].color.g == .88)
s, c = DC.Parse(("1:1,1,1;"):rep(12) .. "/" .. ("1+2+3+4+5:1,1,1;"):rep(7))
assert(#s == DC.MAX_SINGLES and #c == DC.MAX_COMBOS and #c[1].spells == DC.MAX_COMBO_SPELLS)
s, c = DC.Parse(nil)
assert(#s == 0 and #c == 0)
assert(DC.Key("DRUID") == "debuffColorsDRUID")

-- Disabled: nothing built, no hooks, no worker.
assert(#frames == 0 and not ns.DebuffColors_Attach and not ns.DebuffColors_Detach)
ns.DebuffColors_Refresh()
ns.DebuffColors_RequestRefresh()
assert(#frames == 0, "disabled feature built a frame or worker")
local p = NewPlate("nameplate1")

-- Enabled with nothing listed: still no plate hooks or containers.
profile.debuffColorsEnabled = true
ns.DebuffColors_Refresh()
assert(not ns.DebuffColors_Attach and #containers == 0, "empty lists hooked the plates")

-- Another class's list is never read; the player's own builds after combat.
profile.debuffColorsROGUE = "589:" .. BLUE .. "/"
ns.DebuffColors_Refresh()
assert(not ns.DebuffColors_Attach and #containers == 0, "another class's list changed the plates")
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. "/703+1943:" .. GREEN
combat = true
ns.DebuffColors_Refresh()
assert(not ns.DebuffColors_Attach and #containers == 0, "combat change was not deferred")
Regen()
assert(ns.DebuffColors_Attach)
AssertColor(p, nil)

-- Secret combat aura changes: engine visibility must be sufficient on its own.
combat = true
Auras("nameplate1", {{ id=589, mine=true }})
AssertColor(p, nil, nil, nil, "another class's debuff tinted the plate")
Auras("nameplate1", {{ id=703, mine=true }})
AssertColor(p, 1, .43, .04)
Auras("nameplate1", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1)
Auras("nameplate1", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .1, .88, .32, "the combo did not win")
Auras("nameplate1", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1, "the combo outlived its first spell")
Auras("nameplate1", {})
AssertColor(p, nil)
Auras("nameplate1", {{ id=703, mine=false }, { id=1943, mine=false }})
AssertColor(p, nil, nil, nil, "someone else's debuffs counted")
local before = #containers
ns.DebuffColors_Detach(p)
ns.plates.nameplate1 = nil
AssertColor(p, nil)
ns.plates.nameplate2 = p
ns.DebuffColors_Attach(p, "nameplate2")
Auras("nameplate2", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1)
assert(#containers == before, "plate reuse rebuilt its aura containers")

-- Plate churn: parking is only a hide, and the same token rebinds with only a
-- show, which re-reads the unit (the debuff fell off while parked); a new
-- token sets each container's unit once. Nothing is disabled or re-enabled.
ResetCalls()
ns.DebuffColors_Detach(p)
Auras("nameplate2", {})
ns.DebuffColors_Attach(p, "nameplate2")
local enabledCalls, unitCalls = Calls()
assert(enabledCalls == 0 and unitCalls == 0, "a park and same-token rebind toggled the containers")
AssertColor(p, nil, nil, nil, "a reshown bundle kept a stale tint")
ns.DebuffColors_Detach(p)
ns.plates.nameplate2, ns.plates.nameplate5 = nil, p
ResetCalls()
ns.DebuffColors_Attach(p, "nameplate5")
enabledCalls, unitCalls = Calls()
assert(enabledCalls == 0 and unitCalls == LiveContainers(p) and unitCalls == 2,
    "a new token did not set each container's unit exactly once")
Auras("nameplate5", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .1, .88, .32)
ns.DebuffColors_Detach(p)
ns.plates.nameplate5, ns.plates.nameplate2 = nil, p
ns.DebuffColors_Attach(p, "nameplate2")

-- The higher entry wins, in both cast orders; Only My Debuffs off.
combat = false
profile.debuffColorsPlayerOnly = false
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. "/"
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=1943, mine=false }, { id=703, mine=false }})
AssertColor(p, 1, .43, .04, "the higher debuff did not win")
before = #containers
ns.DebuffColors_Refresh()
assert(#containers == before, "unchanged config rebuilt secure decoration")
profile.debuffColorsDRUID = "1943:" .. RED .. ";703:" .. ORANGE .. "/"
ns.DebuffColors_Refresh()
combat = true
Auras("nameplate2", {{ id=703, mine=true }})
AssertColor(p, 1, .43, .04)
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .8, .2, .1, "reordering did not change the winner")
Auras("nameplate2", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1)

-- Changes made in combat apply after combat.
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. "/"
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .8, .2, .1)
Regen()
AssertColor(p, 1, .43, .04)

-- A three-debuff combo shows only while all three are up; two combos: the
-- higher wins.
combat = false
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. ";589:" .. PURPLE ..
    "/703+1943+589:" .. GREEN .. ";703+589:" .. BLUE
ns.DebuffColors_Refresh()
combat = true
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, 1, .43, .04, "a partial three-debuff combo tinted the plate")
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .1, .88, .32, "the higher combo did not win")
Auras("nameplate2", {{ id=703, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1)
Auras("nameplate2", {{ id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .8, .2, .1, "a combo outlived its first spell")
combat = false
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. ";589:" .. PURPLE ..
    "/703+589:" .. BLUE .. ";703+1943+589:" .. GREEN
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1, "reordered combos kept the old winner")

-- Neighbouring combos with a debuff in common share their first slot: fewer
-- root slots, the same winners. Saved top first: the bottom three share 589
-- (MAGENTA's chain starts with it although it is saved second), GREEN shares
-- nothing with its neighbour.
local YELLOW, MAGENTA = "0.9,0.9,0.1", "0.5,0.1,0.5"
local SINGLES = "703:" .. ORANGE .. ";1943:" .. RED .. ";589:" .. PURPLE
profile.debuffColorsDRUID = SINGLES .. "/1943+703:" .. GREEN .. ";703+589:" .. BLUE ..
    ";703+1943+589:" .. YELLOW .. ";1943+589:" .. MAGENTA
ns.DebuffColors_Refresh()
assert(SlotCount(RootOf(p)) == 5, "neighbouring combos did not share a first slot")
combat = true
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .1, .88, .32, "the top combo lost to a shared run")
Auras("nameplate2", {{ id=703, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1)
Auras("nameplate2", {{ id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .5, .1, .5, "a combo reordered to share its slot lost its tint")
Auras("nameplate2", {{ id=589, mine=true }})
AssertColor(p, .6, .2, .8, "a shared slot tinted on its own")
-- Inside one run the higher combo still wins: top, middle and bottom.
combat = false
profile.debuffColorsDRUID = SINGLES .. "/703+589:" .. BLUE .. ";703+1943+589:" .. YELLOW .. ";589+1943:" .. MAGENTA
ns.DebuffColors_Refresh()
assert(SlotCount(RootOf(p)) == 4, "one run built more than one first slot")
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1, "the top of a run lost")
profile.debuffColorsDRUID = SINGLES .. "/589+155722:" .. GREEN .. ";703+1943+589:" .. YELLOW .. ";703+589:" .. BLUE
ns.DebuffColors_Refresh()
AssertColor(p, .9, .9, .1, "the middle of a run lost")
profile.debuffColorsDRUID = SINGLES .. "/589+1943:" .. MAGENTA .. ";703+1943+589:" .. YELLOW .. ";703+589:" .. BLUE
ns.DebuffColors_Refresh()
AssertColor(p, .5, .1, .5, "the reordered top of a run lost")
Auras("nameplate2", {{ id=703, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1, "the bottom of a run lost")
-- A neighbour with nothing in common keeps combos apart.
profile.debuffColorsDRUID = SINGLES .. "/703+589:" .. BLUE .. ";1943+155722:" .. GREEN .. ";703+1079:" .. YELLOW
ns.DebuffColors_Refresh()
assert(SlotCount(RootOf(p)) == 6, "combos shared a slot across a neighbour")
Auras("nameplate2", {{ id=703, mine=true }, { id=589, mine=true }, { id=1079, mine=true }})
AssertColor(p, .2, .4, 1)

-- Unchosen debuffs, duplicates and one-spell combos never get a slot.
profile.debuffColorsDRUID = "0:1,1,1;703:" .. ORANGE .. ";703:" .. RED .. "/703+703:" .. GREEN .. ";1943:" .. BLUE
ns.DebuffColors_Refresh()
local root = containers[#containers]
assert(SlotCount(root) == 1, "an unchosen, duplicate or one-spell entry got a slot")
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, 1, .43, .04, "a duplicate entry drew over its higher copy")
-- Edits that cannot change the plates rebuild nothing.
profile.debuffColorsDRUID = profile.debuffColorsDRUID .. ";0:0,0,0"
before = #containers
ns.DebuffColors_Refresh()
assert(#containers == before, "a no-op edit rebuilt the plates")

-- Coalesce repeated requests into one rebuild.
before = #containers
for i = 1, 20 do
    profile.debuffColorsDRUID = "703:0.5,0.5," .. (i / 100) .. "/"
    ns.DebuffColors_RequestRefresh()
end
assert(#containers == before)
RunWorker()
AssertColor(p, .5, .5, .2)
assert(#containers == before + 1)
RunWorker()
assert(#containers == before + 1, "the worker ran again without a request")

-- Disabling in combat applies after combat and leaves nothing armed.
combat = true
profile.debuffColorsEnabled = false
ns.DebuffColors_Refresh()
AssertColor(p, .5, .5, .2)
Regen()
AssertColor(p, nil)
assert(not ns.DebuffColors_Attach and not ns.DebuffColors_Detach)
for _, frame in ipairs(frames) do
    assert(not UIState(frame).events.PLAYER_REGEN_ENABLED, "disabled feature left an event registered")
    assert(not UIState(frame).scripts.OnUpdate, "disabled feature left an update callback armed")
end

-- Profile swaps refresh active AND pooled bundles, including textures.
profile.debuffColorsEnabled = true
ns.DebuffColors_Refresh()
local pooled = NewPlate("nameplate3")
ns.DebuffColors_Attach(pooled, "nameplate3")
ns.DebuffColors_Detach(pooled)
ns.plates.nameplate3 = nil
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID="1943:0.3,0.4,0.5/", healthBarTexture="other" })
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=703, mine=true }})
AssertColor(p, nil)
Auras("nameplate2", {{ id=1943, mine=true }})
AssertColor(p, .3, .4, .5)
ns.plates.nameplate4 = pooled
ns.DebuffColors_Attach(pooled, "nameplate4")
Auras("nameplate4", {{ id=1943, mine=true }})
AssertColor(pooled, .3, .4, .5)
ns.DebuffColors_Detach(pooled)
AssertColor(pooled, nil)

-- Saved IDs stay exact: no normalization rewrites the profile.
profile.debuffColorsDRUID = "316099:0.3,0.4,0.5/"
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=1259790, mine=true }})
AssertColor(p, nil)
Auras("nameplate2", {{ id=316099, mine=true }})
AssertColor(p, .3, .4, .5)
assert(profile.debuffColorsDRUID == "316099:0.3,0.4,0.5/", "reading rewrote the saved list")

-- Color Border: the plate's own border drawn again in the debuff color over
-- it, never a fill tint. Basic: four strips in scale-1 space, as thick as the
-- border plus Extra Border Size, one level above the border's own strips.
combat = false
UseProfile({ debuffColorsEnabled=true, debuffColorsBorder=true, debuffColorsBorderExtra=1,
    debuffColorsDRUID="703:" .. ORANGE .. ";1943:" .. RED .. "/703+1943:" .. GREEN })
border.blizz, border.custom, border.basic, border.size = false, false, true, 2
ns.DebuffColors_Refresh()
assert(ns.DebuffColors_Attach, "Color Border over a Basic border built nothing")
-- Strips are drawn in physical pixels: a resolution change redraws them, a UI
-- scale change (the pixel re-apply) does not.
assert(pxReapply.fn == nil, "strips joined the UI scale re-apply")
assert(Watching("DISPLAY_SIZE_CHANGED") == 1, "strips do not follow a resolution change")
combat = true
Auras("nameplate2", {})
AssertBorder(p, nil)
Auras("nameplate2", {{ id=1943, mine=true }})
local f, pieces = AssertBorder(p, .8, .2, .1)
assert(f.anchor == UIState(RootOf(p)).parent and f.ignoreParentScale == true and f.scale == 1
    and not f.strata, "Basic's color is not in scale-1 space over the bar")
assert(f.level == UIState(p.health).level + 2, "the color is not just above the border")
-- 3 px at 0.5 units a pixel: top and bottom 1.5 high, the sides 1.5 wide and
-- inset by it, so no corner is drawn twice.
local rows, sides = 0, 0
for _, piece in ipairs(pieces) do
    assert(piece.layer == "OVERLAY" and piece.snap == false)
    if piece.height then
        assert(piece.height == 1.5)
        rows = rows + 1
    else
        assert(piece.width == 1.5 and piece.points[1][5] == -1.5 and piece.points[2][5] == 1.5,
            "a side strip overlaps a corner")
        sides = sides + 1
    end
end
assert(rows == 2 and sides == 2)
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertBorder(p, .1, .88, .32, "the combo's border did not win")
Auras("nameplate2", {{ id=703, mine=true }})
AssertBorder(p, 1, .43, .04)
-- The bar texture is not a Color Border input; the border size and Extra
-- Border Size are.
combat = false
local before = #containers
profile.healthBarTexture = "other"
ns.DebuffColors_Refresh()
assert(#containers == before, "a bar texture edit rebuilt Color Border")
border.size = 1
profile.debuffColorsBorderExtra = 0
ns.DebuffColors_Refresh()
assert(#containers > before, "a border size edit kept the old thickness")
f, pieces = AssertBorder(p, 1, .43, .04)
for _, piece in ipairs(pieces) do
    assert((piece.height or piece.width) == .5, "a 1 px border drew " .. tostring(piece.height or piece.width))
end
-- The strips' grid is the physical pixel: a UI scale change alone keeps them;
-- a resolution change redraws them at the new pixel size.
before = #containers
EllesmereUI.PP.mult = 0.6
ns.DebuffColors_Refresh()
assert(#containers == before, "a UI scale change rebuilt strips drawn in physical pixels")
EllesmereUI.PP.perfect = 0.25
FireEvent("DISPLAY_SIZE_CHANGED")
RunWorker()
assert(#containers > before, "a resolution change kept the old pixel size")
f, pieces = AssertBorder(p, 1, .43, .04)
for _, piece in ipairs(pieces) do
    assert((piece.height or piece.width) == .25, "the strips missed the new pixel size")
end
EllesmereUI.PP.perfect, EllesmereUI.PP.mult = 0.5, 0.75
ns.DebuffColors_Refresh()
-- A slider drag (Extra Border Size, the Display page's border sliders, UI
-- Scale) rebuilds nothing until it is released, then once.
before = #containers
EllesmereUI._sliderDragging = 1
for step = 1, 4 do
    profile.debuffColorsBorderExtra = step
    ns.DebuffColors_RequestRefresh()
    RunWorker()
end
assert(#containers == before, "a slider drag rebuilt the bundles on every step")
assert(EllesmereUI._deferredDriftChecks and EllesmereUI._deferredDriftChecks[ns.DebuffColors_RequestRefresh],
    "the drag left no refresh for its release")
EllesmereUI._sliderDragging = nil
local releases = EllesmereUI._deferredDriftChecks
EllesmereUI._deferredDriftChecks = nil
for fn in pairs(releases) do fn() end
RunWorker()
assert(#containers > before, "the drag's release did not apply")
f, pieces = AssertBorder(p, 1, .43, .04)
for _, piece in ipairs(pieces) do assert((piece.height or piece.width) == 2.5) end
profile.debuffColorsBorderExtra = 0
ns.DebuffColors_Refresh()

-- Custom Solid: the same strips, on the custom border's MEDIUM strata, from its
-- exact size (only one saved for its own size and texture), one level above the
-- pixel border's container its strips draw on; drawn behind, the same.
border.custom = true
profile.customBorderTexture, profile.customBorderSize, profile.customBorderSizePx = "solid", 2, "3|2|solid"
profile.debuffColorsBorderExtra = 1
ns.DebuffColors_Refresh()
f, pieces = AssertBorder(p, 1, .43, .04)
assert(f.strata == "MEDIUM" and f.ignoreParentScale)
assert(f.level == CustomBorderLevel(p, false, true) + 1, "the color is not just above the Solid border's strips")
for _, piece in ipairs(pieces) do assert((piece.height or piece.width) == 2) end
profile.customBorderSizePx = "3|1|solid"
ns.DebuffColors_Refresh()
f, pieces = AssertBorder(p, 1, .43, .04)
for _, piece in ipairs(pieces) do
    assert((piece.height or piece.width) == 1.5, "an exact size saved for another step was used")
end
profile.customBorderSizePx = "3|2|solid"
profile.customBorderBehind = true
ns.DebuffColors_Refresh()
f = AssertBorder(p, 1, .43, .04)
assert(f.level == CustomBorderLevel(p, true, true) + 1, "a border drawn behind lost its color or rose above the bar")

-- A textured custom border: its eight slices in the color on its own geometry
-- (offsets and size as saved) just above the border frame they draw on; Extra
-- Border Size does not apply. Slices follow a UI scale change (the pixel
-- re-apply), not a resolution change.
profile.customBorderBehind = nil
profile.customBorderTexture, profile.customBorderSizePx = "pixels", nil
profile.customBorderOffset, profile.customBorderShiftY = 2, -1
local g0 = #geometry
ns.DebuffColors_Refresh()
f, pieces = AssertBorder(p, 1, .43, .04)
assert(#pieces == 8 and f.strata == "MEDIUM" and not f.ignoreParentScale)
assert(f.level == CustomBorderLevel(p, false, false) + 1, "the color is not just above the textured border")
assert(pxReapply.owner == DC and pxReapply.fn == ns.DebuffColors_RequestRefresh, "slices left the UI scale re-apply")
assert(Watching("DISPLAY_SIZE_CHANGED") == 0, "slices kept the resolution watch")
before = #containers
EllesmereUI.PP.perfect = 0.25
ns.DebuffColors_Refresh()
assert(#containers == before, "a pixel size change alone rebuilt the slices")
EllesmereUI.PP.mult = 0.6
pxReapply.fn(pxReapply.owner)
RunWorker()
assert(#containers > before, "a UI scale change kept the slices' old geometry")
EllesmereUI.PP.perfect, EllesmereUI.PP.mult = 0.5, 0.75
ns.DebuffColors_Refresh()
profile.customBorderBehind = true
ns.DebuffColors_Refresh()
f = AssertBorder(p, 1, .43, .04)
assert(f.level == CustomBorderLevel(p, true, false) + 1, "a textured border drawn behind lost its color")
profile.customBorderBehind = nil
g0 = #geometry
ns.DebuffColors_Refresh()
f, pieces = AssertBorder(p, 1, .43, .04)
local g
for i = g0 + 1, #geometry do
    if UIState(geometry[i].owner) == f then g = geometry[i] end
end
assert(g and g.size == 2 and g.tex == "pixels" and g.ox == 2
    and g.oy == nil and g.sy == -1 and g.px == nil and g.addon == "nameplates" and g.sizeKey == 2
    and g.edgeScale == nil, "the slices are not on the border's own geometry")
for _, piece in ipairs(pieces) do
    assert(piece.texture == "path-pixels" and piece.wrap[1] == true and piece.wrap[2] == true)
    assert(piece.texCoord[1] == EllesmereUI.SECRET_BORDER_UV[piece.slice][1], "a slice has another one's cut")
    assert(piece.layout.edge == 7 and piece.layout.aL == -1 and UIState(piece.layout.owner) == f)
end
-- An exact custom size reaches the slices' geometry; one saved for another
-- texture does not.
profile.customBorderSizePx = "5|2|pixels"
g0 = #geometry
ns.DebuffColors_Refresh()
f = AssertBorder(p, 1, .43, .04)
g = nil
for i = g0 + 1, #geometry do
    if UIState(geometry[i].owner) == f then g = geometry[i] end
end
assert(g and g.px == 5 and g.size == 2, "the slices lost the border's exact size")
profile.customBorderSizePx = "5|2|solid"
g0 = #geometry
ns.DebuffColors_Refresh()
f = AssertBorder(p, 1, .43, .04)
g = nil
for i = g0 + 1, #geometry do
    if UIState(geometry[i].owner) == f then g = geometry[i] end
end
assert(g and g.px == nil, "the slices took an exact size saved for another texture")
profile.customBorderSizePx = nil

-- Nothing to color (an unresolved texture, Border None, a stock style): no
-- plate hooks, no containers, out of the pixel re-apply.
for _, case in ipairs({
    function() profile.customBorderTexture = "missing" end,
    function() border.custom, border.basic = false, false end,
    function() border.basic, border.blizz = true, true end,
}) do
    case()
    before = #containers
    ns.DebuffColors_Refresh()
    assert(not ns.DebuffColors_Attach and #containers == before and pxReapply.fn == nil
        and Watching("DISPLAY_SIZE_CHANGED") == 0,
        "Color Border built over a plate with no border")
    AssertBorder(p, nil)
end
border.blizz = false

-- Back to Color Nameplate: the fill tint again, out of the pixel re-apply.
profile.debuffColorsBorder = false
ns.DebuffColors_Refresh()
assert(pxReapply.fn == nil, "Color Nameplate stayed in the pixel re-apply")
AssertColor(p, 1, .43, .04)
assert(not BorderPaint(p), "Color Nameplate drew a border")

assert(#ns.DebuffColorPresets == 13)
assert(ns.DebuffColorPresetByID[1259790][2] == "Unstable Affliction")
assert(ns.DebuffColorPresetByID[445474][2] == "Wither")
for _, id in ipairs({121411, 2818, 259491, 106830, 335467, 55078, 55095, 191587, 217200, 12654, 316099}) do
    assert(not ns.DebuffColorPresetByID[id], "unwanted or obsolete preset remains")
end
''')
print('PASS: list codec, caps, class scoping, priority by order, combos (chains of 2-4, shared first slots),')
print('      duplicates, ownership, plate churn, combat deferral, pooling, profiles, textures, coalesced')
print('      refreshes, no-op edits, Color Border (Basic, Custom Solid, textured, no border, stock style).')

# Execute the actual Colors-page builder against mocked widgets.
options = (ROOT / 'EllesmereUIOptions/Nameplates_Options/ColorsPage_Options.lua').read_text()
helper = options.split('-- EUI_DEBUFF_COLORS: the per-class debuff lists', 1)[1].split(
    '-- Mini preview bar builder', 1)[0]
lua.execute(r'''
-- A small UI object model for the widget mocks (the engine mock above is done).
local uiMethods = {}
local function UIObj(kind, parent)
    local o = setmetatable({ kind=kind, parent=parent, scripts={}, hooks={}, shown=true,
        alpha=1, points={}, children={}, mouse=true, width=170 }, { __index = uiMethods })
    if parent and parent.children then table.insert(parent.children, o) end
    return o
end
function uiMethods:SetSize(w, h) self.width, self.height = w, h end
function uiMethods:SetPoint(...) table.insert(self.points, {...}) end
function uiMethods:GetPoint(i) local pt = self.points[i or 1]; if pt then return unpack(pt) end end
function uiMethods:ClearAllPoints() self.points = {} end
function uiMethods:SetFrameLevel(l) self.level = l end
function uiMethods:GetFrameLevel() return self.level or 1 end
function uiMethods:CreateTexture() return UIObj("Texture", self) end
function uiMethods:SetTexture(t) self.texture = t end
function uiMethods:SetVertexColor(...) self.color = {...} end
function uiMethods:SetAlpha(a) self.alpha = a end
function uiMethods:EnableMouse(v) self.mouse = v end
function uiMethods:SetScript(e, f) self.scripts[e] = f; self.hooks[e] = nil end
function uiMethods:GetScript(e) return self.scripts[e] end
function uiMethods:HookScript(e, f)
    self.hooks[e] = self.hooks[e] or {}
    table.insert(self.hooks[e], f)
end
function uiMethods:Show() self.shown = true end
function uiMethods:Hide() self.shown = false end
function uiMethods:SetShown(v) self.shown = v and true or false end
function uiMethods:IsShown() return self.shown end
function uiMethods:IsMouseOver() return false end
function uiMethods:SetText(t) self.text = t end
function uiMethods:GetText() return self.text end
function uiMethods:GetStringWidth() return #(self.text or "") * 7 end
function uiMethods:GetWidth() return self.width end
function uiMethods:GetChildren() return unpack(self.children) end
function Fire(o, e, ...)
    if o.scripts[e] then o.scripts[e](o, ...) end
    for _, f in ipairs(o.hooks[e] or {}) do f(o, ...) end
end
function CreateFrame(kind, _, parent) return UIObj(kind, parent) end

uiRows, uiRefreshers, uiSwatches, uiCB, uiWarn, uiMenus = {}, {}, {}, {}, {}, {}
uiNotified, uiErrors, uiOnHide, uiTips, uiCogs, uiHeaders = {}, {}, {}, {}, {}, {}
stockStyle = nil
EllesmereUI.BlizzStyle = { Get = function() return stockStyle end }
function EllesmereUI.BuildInlineCog(rgn, opts)
    local btn = UIObj("Button", rgn)
    btn.cogOpts = opts
    uiCogs[#uiCogs+1] = btn
    return btn
end
local builds = 0
local function Region(row, cfg)
    local rgn = UIObj("Frame", row)
    rgn._cfg = cfg
    rgn._label = UIObj("FontString", rgn)
    rgn._label:SetText(cfg.text)
    local ctrl = UIObj("Button", rgn)
    ctrl:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    if cfg.type == "button" then
        ctrl:SetScript("OnClick", function() if not cfg.disabled or not cfg.disabled() then cfg.onClick() end end)
        ctrl:SetScript("OnEnter", function() end)
        ctrl:SetScript("OnLeave", function() end)
    else
        ctrl._invalidateMenu = function() rgn.invalidations = (rgn.invalidations or 0) + 1 end
        ctrl._refreshLabel = function() rgn.shownValue = cfg.getValue and cfg.getValue() end
    end
    rgn._control = ctrl
    return rgn
end
EllesmereUI.Widgets = {
    SectionHeader=function(_, _, text) uiHeaders[#uiHeaders+1] = text; return {}, 30 end,
    Spacer=function() return {}, 20 end,
    DualRow=function(_, _, _, left, right)
        local row = UIObj("Frame")
        row._leftRegion, row._rightRegion = Region(row, left), Region(row, right)
        uiRows[#uiRows+1] = { left, right, frame=row }
        return row, 50
    end,
    WideButton=function(_, _, text, _, onClick, width)
        local frame = UIObj("Frame")
        local btn = UIObj("Button", frame)
        btn:SetScript("OnClick", function() onClick() end)
        uiApply = { frame=frame, button=btn, text=text, width=width }
        return frame, 62
    end,
}
EllesmereUI.PanelPP = { Point=function(f, ...) f:SetPoint(...) end, Size=function(f, w, h) f:SetSize(w, h) end }
EllesmereUI.ELLESMERE_GREEN = { r=.05, g=.82, b=.62 }
function EllesmereUI.L(s) return s end
function EllesmereUI.Lf(s, ...) return (s:gsub("%%%d%$", "%%")):format(...) end
function EllesmereUI.GetClassColor() return { r=1, g=1, b=1 } end
function EllesmereUI.HexColor() return "|cffffffff" end
function EllesmereUI.BlankRowCfg() return { type="label", text="" } end
function EllesmereUI.RegisterWidgetRefresh(fn) uiRefreshers[#uiRefreshers+1] = fn end
function EllesmereUI:RegisterOnHide(fn) uiOnHide[#uiOnHide+1] = fn end
function EllesmereUI._NotifySettingWrite(rgn) uiNotified[#uiNotified+1] = rgn end
function EllesmereUI:ShowInputPopup(opts) uiPopup = opts end
function EllesmereUI.PrintError(msg) uiErrors[#uiErrors+1] = msg end
function EllesmereUI.ShowWidgetTooltip(_, text) uiTips[#uiTips+1] = text end
function EllesmereUI.HideWidgetTooltip() end
function EllesmereUI.MakeFont(parent) return UIObj("FontString", parent) end
function EllesmereUI.SectionToggleSetValue(fn) return function(v) fn(v); EllesmereUI:RefreshPage(true) end end
function EllesmereUI.BuildInlineSwatches(rgn, list)
    uiSwatches[#uiSwatches+1] = { rgn=rgn, list=list }
    rgn._lastInline = UIObj("Button", rgn)
end
function EllesmereUI.BuildVisOptsCBDropdown(rgn, w, _, items, get, set, _, _, _, _, onClosed, opts)
    local dd = UIObj("Button", rgn)
    dd.items, dd.get, dd.set, dd.opts, dd.onClosed = items, get, set, opts, onClosed
    uiCB[#uiCB+1] = dd
    return dd, function() end
end
function EllesmereUI.AttachEmptyFilterWarn(rgn, dd, text, hasContent)
    uiWarn[#uiWarn+1] = { rgn=rgn, dd=dd, text=text, hasContent=hasContent }
    return function() end
end
function EllesmereUI.BuildDropdownMenu(btn, w, order, values, get, set, lbl, style, disabled)
    local menu = UIObj("Frame")
    menu:Hide()
    uiMenus[btn] = { menu=menu, order=order, values=values, set=set, disabled=disabled }
    return menu, nil, function() end
end
function EllesmereUI.WireDropdownScripts() end
function GetNumClasses() return 4 end
local CLASSES = { { "Warrior", "WARRIOR" }, { "Rogue", "ROGUE" }, { "Druid", "DRUID" }, { "Priest", "PRIEST" } }
function GetClassInfo(i) return CLASSES[i][1], CLASSES[i][2], i end
C_Spell = {
    GetSpellName=function(id) return "Spell " .. id end,
    GetSpellTexture=function(id) return id + 100000 end,
    GetSpellInfo=function(id) if id == 155722 or id == 33333 or id == 44444 then return { name="Known" } end end,
}
function EllesmereUI:RefreshPage(force)
    if force then
        uiRows, uiRefreshers, uiSwatches, uiCB, uiWarn, uiCogs, uiHeaders = {}, {}, {}, {}, {}, {}, {}
        uiApply = nil
        builds = builds + 1
        BuildPage()
    else
        for _, fn in ipairs(uiRefreshers) do fn() end
    end
end
function Builds() return builds end
-- Rows: { left cfg, right cfg, frame }; cells in reading order.
function Cells()
    local out = {}
    for _, row in ipairs(uiRows) do
        out[#out+1] = { cfg=row[1], rgn=row.frame._leftRegion }
        out[#out+1] = { cfg=row[2], rgn=row.frame._rightRegion }
    end
    return out
end
function Cell(text)
    for _, c in ipairs(Cells()) do
        if c.cfg.text == text then return c end
    end
end
-- The up / down arrows a row's chrome made (children of its region).
function Arrows(rgn)
    local out = {}
    for _, child in ipairs(rgn.children) do
        if child.kind == "Button" and child.children[1] and child.children[1].texture
            and child.children[1].texture:find("eui%-arrow") then out[#out+1] = child end
    end
    return out[1], out[2]
end
''')
load('local ns = ...\n-- EUI_DEBUFF_COLORS: the per-class debuff lists' + helper)(lua.globals().ns)
lua.execute(r'''
local DC = ns.DebuffColorKit
-- The page drives the real runtime; no plates (the engine mock is done).
ns.plates = {}
function BuildPage() ns.NP_BuildDebuffColorsOptions({}, 0) end
UseProfile({ debuffColorsEnabled=false })
ns.DebuffColors_Refresh()

-- Off: only the mode row; no lists.
EllesmereUI:RefreshPage(true)
assert(#uiRows == 1 and uiApply == nil)
assert(uiHeaders[1] == "DEBUFF BASED NAMEPLATE COLORING", "the section kept its old name")
local mode = uiRows[1][1]
assert(mode.type == "dropdown" and mode.text == "Debuff Coloring" and uiRows[1][2].text == "Only My Debuffs")
assert(mode.order[1] == "none" and mode.order[2] == "nameplate" and mode.order[3] == "border"
    and mode.values.none == "None" and mode.values.nameplate == "Color Nameplate"
    and mode.values.border == "Color Border")
assert(mode.getValue() == "none" and #uiCogs == 0)
assert(uiRows[1][2].disabled())

-- Every edit asks the runtime for a refresh at once (it rebuilds at most once a
-- frame, and only for the player's own class): count the requests.
local requests = 0
local request = ns.DebuffColors_RequestRefresh
ns.DebuffColors_RequestRefresh = function() requests = requests + 1; request() end

-- Color Nameplate applies at once and builds the section: the two Add buttons,
-- with no Apply button, no close hook and no Color Border cog.
uiRows[1][1].setValue("nameplate")
assert(profile.debuffColorsEnabled == true and profile.debuffColorsBorder == false and #uiCogs == 0)
assert(uiApply == nil, "the Apply Coloring button is back")
assert(#uiRows == 2 and uiRows[2][1].text == "+ Add Debuff" and uiRows[2][2].text == "+ Add Combo")
assert(not uiRows[2][1].disabled() and uiRows[2][2].disabled(), "Add Combo enabled with no debuffs")
assert(#uiOnHide == 0, "a close hook was registered")

-- Add Debuff opens the classes (the player's first) and adds an unchosen debuff.
local addRgn = uiRows[2].frame._leftRegion
Fire(addRgn._control, "OnClick")
local picker = uiMenus[addRgn._control]
assert(picker.menu.shown and picker.order[1] == "DRUID" and picker.order[2] == "PRIEST")
assert(picker.values.DRUID:find("Druid", 1, true) and picker.values._noLoc)
picker.set("DRUID")
assert(profile.debuffColorsDRUID == "0:1,0.43,0.04/", "Add Debuff saved " .. tostring(profile.debuffColorsDRUID))
local d1 = Cell("Druid Debuff 1")
assert(d1 and d1.cfg.getValue() == "none" and d1.cfg.values.none == "None")
assert(uiNotified[#uiNotified] == d1.rgn, "the new row did not report the write")
assert(d1.cfg.tooltip == "Higher in the list wins when several are up.")
-- Only the class's own presets, in its order.
local o = d1.cfg.order
assert(#o == 6 and o[1] == "remove" and o[2] == "custom" and o[3] == "164812" and o[4] == "164815"
    and o[5] == "1079" and o[6] == "155722", "a Druid debuff does not offer Moonfire, Sunfire, Rip, Rake")
assert(not d1.cfg.values["980"] and not d1.cfg.values["703"], "another class's preset is offered")
local sw = uiSwatches[1]
assert(sw.rgn == d1.rgn and sw.list[1].disabled(), "the color is not gated on a chosen debuff")

-- Choosing a spell applies at once; a color drag (the picker open) applies
-- once, when the picker closes.
requests = 0
d1.cfg.setValue("1079")
assert(profile.debuffColorsDRUID == "1079:1,0.43,0.04/")
assert(requests == 1, "choosing a spell did not apply")
EllesmereUI._colorPickerOpen = true
sw.list[1].setValue(.9, .3, .4)
sw.list[1].setValue(.5, .3, .4)
sw.list[1].setValue(.2, .3, .4)
assert(profile.debuffColorsDRUID == "1079:0.2,0.3,0.4/")
assert(requests == 1, "a color drag applied on every frame")
EllesmereUI._colorPickerOpen = false
local checks = EllesmereUI._deferredDriftChecks
EllesmereUI._deferredDriftChecks = nil
for fn in pairs(checks or {}) do fn() end
assert(requests == 2, "closing the picker did not apply the drag once")
RunWorker()

-- A second debuff, then the arrows reorder (first up / last down disabled).
Fire(Cell("+ Add Debuff").rgn._control, "OnClick")
uiMenus[Cell("+ Add Debuff").rgn._control].set("DRUID")
Cell("Druid Debuff 2").cfg.setValue("155722")
local up1, down1 = Arrows(Cell("Druid Debuff 1").rgn)
local up2, down2 = Arrows(Cell("Druid Debuff 2").rgn)
assert(up1 and down1 and up2 and down2, "missing reorder arrows")
assert(not up1.mouse and down1.mouse and up2.mouse and not down2.mouse)
assert(up1.children[1].alpha == .2 and down2.children[1].alpha == .2)
Fire(down1, "OnClick")
assert(profile.debuffColorsDRUID == "155722:1,0.43,0.04;1079:0.2,0.3,0.4/", "move down did not swap")
up2 = Arrows(Cell("Druid Debuff 2").rgn)
Fire(up2, "OnClick")
assert(profile.debuffColorsDRUID == "1079:0.2,0.3,0.4;155722:1,0.43,0.04/", "move up did not swap")

-- In use: a spell another debuff of the class holds is greyed in the menu,
-- with the reason; the row's own spell, the rest and the actions stay open.
local IN_USE = "Already in use. Use the arrows to reorder."
local u1, u2 = Cell("Druid Debuff 1"), Cell("Druid Debuff 2")
assert(u1.cfg.disabledValues("155722") == IN_USE and u2.cfg.disabledValues("1079") == IN_USE,
    "a spell another debuff holds is pickable")
assert(not u1.cfg.disabledValues("1079") and not u1.cfg.disabledValues("164812")
    and not u1.cfg.disabledValues("custom") and not u1.cfg.disabledValues("remove"),
    "a free spell or an action is greyed")

-- Custom spells: Custom Spell... only adds (an empty popup, its own label
-- never changes); each added spell joins every menu of its class, a second
-- one too, and leaves once nothing holds it.
d1 = Cell("Druid Debuff 1")
local d2 = Cell("Druid Debuff 2")
d1.cfg.values.custom.action()
assert(not uiPopup.allowEmpty and (uiPopup.initialText or "") == "" and uiPopup.title == "Druid Debuff 1")
assert(uiPopup.confirmText == "Add" and uiPopup.message == "Enter the debuff's spell ID.")
uiPopup.onConfirm("garbage")
uiPopup.onConfirm("-1")
uiPopup.onConfirm("99999999")
assert(#uiErrors == 3 and profile.debuffColorsDRUID:sub(1, 5) == "1079:")
uiPopup.onConfirm(" 33333 ")
assert(profile.debuffColorsDRUID:sub(1, 6) == "33333:" and d1.cfg.getValue() == "33333")
assert(d1.cfg.values.custom.text == "Custom Spell...", "Custom Spell... renamed itself")
local function Tail(cell, k) local list = cell.cfg.order; return list[#list - (k or 0)] end
assert(Tail(d1) == "33333" and Tail(d2) == "33333", "an added spell did not join its class's menus")
assert(d2.cfg.values["33333"] == "Spell 33333" and (d2.rgn.invalidations or 0) >= 1,
    "another row's menu kept a stale list")
assert(d2.cfg.disabledValues("33333") == IN_USE, "an added spell another debuff holds is pickable")
local errs = #uiErrors
d2.cfg.values.custom.action()
uiPopup.onConfirm("33333")
assert(#uiErrors == errs + 1 and uiErrors[#uiErrors] == IN_USE and d2.cfg.getValue() == "155722",
    "Custom Spell... took a spell another debuff holds")
d2.cfg.values.custom.action()
assert((uiPopup.initialText or "") == "", "Custom Spell... opened with a spell filled in")
uiPopup.onConfirm("44444")
assert(Tail(d1, 1) == "33333" and Tail(d1) == "44444" and #d1.cfg.order == 8,
    "a second added spell did not join")
d1.cfg.setValue("1079")
assert(Tail(d2) == "44444" and Tail(d2, 1) == "155722", "a spell nothing holds stayed listed")
d2.cfg.setValue("155722")
assert(#d2.cfg.order == 6 and #d1.cfg.order == 6, "a menu kept a spell nothing holds")

-- Add Combo pairs the class's top two debuffs; a checkbox list edits it.
local addCombo = Cell("+ Add Combo")
assert(not addCombo.cfg.disabled())
Fire(addCombo.rgn._control, "OnClick")
local comboPicker = uiMenus[addCombo.rgn._control]
assert(comboPicker.disabled("ROGUE") and not comboPicker.disabled("DRUID"),
    "Add Combo offers a class without two debuffs")
comboPicker.set("DRUID")
assert(profile.debuffColorsDRUID == "1079:0.2,0.3,0.4;155722:1,0.43,0.04/1079+155722:0.1,0.88,0.32",
    "Add Combo saved " .. profile.debuffColorsDRUID)
local k1 = Cell("Druid Combo 1")
assert(k1 and k1.cfg.getValue() == "1079+155722" and k1.cfg.tooltip:find("Combos win", 1, true))
local cb = uiCB[1]
assert(cb.opts.noAllLabel and cb.opts.notifyWrites and cb.opts.separatorFn() == " + ")
local items = cb.items()
assert(items[1].isTopAction and items[1].label == "Remove" and #items == 3)
assert(cb.get("1079") and cb.get("155722"))
assert(#uiWarn == 1 and uiWarn[1].hasContent())
cb.set("155722", false)
assert(profile.debuffColorsDRUID:find("/1079:0.1,0.88,0.32", 1, true) and not uiWarn[1].hasContent())
cb.set("155722", true)
-- Up to four spells: a fifth stays locked.
UseProfile({ debuffColorsEnabled=true,
    debuffColorsDRUID="1:1,1,1;2:1,1,1;3:1,1,1;4:1,1,1;5:1,1,1/1+2+3+4:1,1,1" })
EllesmereUI:RefreshPage(true)
cb = uiCB[1]
items = cb.items()
assert(#items == 6)
local fifth
for _, it in ipairs(items) do if it.key == "5" then fifth = it end end
assert(fifth.lockedFn() and fifth.lockedTooltip, "a fifth combo spell is not locked")
cb.set("5", true)
assert(profile.debuffColorsDRUID:find("/1+2+3+4:", 1, true), "a fifth spell was added")
-- Remove (top action) drops the combo; the debuff menu's Remove drops a debuff.
items[1].onClick()
assert(profile.debuffColorsDRUID == "1:1,1,1;2:1,1,1;3:1,1,1;4:1,1,1;5:1,1,1/")
Cell("Druid Debuff 3").cfg.values.remove.action()
assert(profile.debuffColorsDRUID == "1:1,1,1;2:1,1,1;4:1,1,1;5:1,1,1/")
assert(Cell("Druid Debuff 4") and not Cell("Druid Debuff 5"))
-- Removing the last entry clears the saved value.
for i = 4, 1, -1 do Cell("Druid Debuff " .. i).cfg.values.remove.action() end
assert(profile.debuffColorsDRUID == nil, "an emptied list left a saved value")

-- Every class is listed after the player's; ten debuffs fill a class.
local ten = ("1:1,1,1;"):rep(10)
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID=ten .. "/", debuffColorsROGUE="703:1,1,1/" })
EllesmereUI:RefreshPage(true)
local cells = Cells() -- the first two: Debuff Coloring | Only My Debuffs
assert(cells[3].cfg.text == "Druid Debuff 1" and cells[13].cfg.text == "Rogue Debuff 1")
assert(cells[14].cfg.text == "+ Add Debuff" and cells[15].cfg.text == "+ Add Combo")
assert(cells[16].cfg.type == "label", "the odd last slot is not blank")
Fire(cells[14].rgn._control, "OnClick")
assert(uiMenus[cells[14].rgn._control].disabled("DRUID") and not uiMenus[cells[14].rgn._control].disabled("ROGUE"))

-- Only My Debuffs applies at once too.
requests = 0
uiRows[1][2].setValue(false)
assert(profile.debuffColorsPlayerOnly == false and requests == 1, "Only My Debuffs did not apply")

-- A row offers only its class's presets; another class's preset it holds reads
-- as a custom spell, and a class without presets offers none.
UseProfile({ debuffColorsEnabled=true, debuffColorsROGUE="589:1,1,1/", debuffColorsWARRIOR="0:1,1,1/" })
EllesmereUI:RefreshPage(true)
local r1 = Cell("Rogue Debuff 1")
o = r1.cfg.order
assert(#o == 5 and o[3] == "703" and o[4] == "1943" and o[5] == "589",
    "a Rogue debuff does not offer Garrote, Rupture and the spell it holds")
assert(r1.cfg.getValue() == "589" and r1.cfg.values["589"] == "Spell 589",
    "another class's preset a row holds is not listed as its spell")
assert(#Cell("Warrior Debuff 1").cfg.order == 2, "a class without presets offered some")
-- A list saved with a duplicate: each row's own spell stays open (lit label).
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID="1079:1,1,1;1079:1,1,1/" })
EllesmereUI:RefreshPage(true)
assert(not Cell("Druid Debuff 1").cfg.disabledValues("1079") and not Cell("Druid Debuff 2").cfg.disabledValues("1079"),
    "a row's own spell is greyed")

-- Debuff Coloring is a view over the saved keys: the old toggle's on reads
-- Color Nameplate, and Color Border adds its own key beside it.
UseProfile({ debuffColorsEnabled=true })
EllesmereUI:RefreshPage(true)
assert(uiRows[1][1].getValue() == "nameplate", "a profile with the old toggle on changed mode")
UseProfile({ debuffColorsEnabled=false, debuffColorsBorder=true })
EllesmereUI:RefreshPage(true)
assert(uiRows[1][1].getValue() == "none")
requests = 0
uiRows[1][1].setValue("border")
assert(profile.debuffColorsEnabled == true and profile.debuffColorsBorder == true
    and uiRows[1][1].getValue() == "border")
-- Color Border's cog: Extra Border Size (0-4), shown over Basic or Custom
-- Solid only, following border edits made on another page.
local cog = uiCogs[1]
assert(#uiCogs == 1 and cog.parent == uiRows[1].frame._leftRegion, "Color Border has no cog on its row")
local extra = cog.cogOpts.rows[1]
assert(#cog.cogOpts.rows == 1 and extra.label == "Extra Border Size" and extra.min == 0 and extra.max == 4)
assert(cog.shown, "the cog is hidden over a Basic border")
local function PageShown() for _, fn in ipairs(uiRefreshers) do fn() end end
profile.customBorderEnabled, profile.customBorderTexture = true, "pixels"
PageShown()
assert(not cog.shown, "the cog shows over a textured border")
profile.customBorderTexture = "solid"
PageShown()
assert(cog.shown, "the cog is hidden over a Custom Solid border")
stockStyle = "classic"
PageShown()
assert(not cog.shown, "the cog shows under a stock style")
stockStyle = nil
PageShown()
extra.set(2)
assert(profile.debuffColorsBorderExtra == 2 and extra.get() == 2 and requests == 1,
    "Extra Border Size did not apply")
-- Color Border needs a border: greyed with the reason while there is none.
profile.customBorderEnabled, profile.showBorder = false, false
assert(uiRows[1][1].disabledValues("border") == "This option requires a Border to be selected")
assert(not uiRows[1][1].disabledValues("nameplate") and not uiRows[1][1].disabledValues("none"))
profile.showBorder = true
assert(not uiRows[1][1].disabledValues("border"))
-- A custom border the runtime draws nothing for counts as none, cog hidden:
-- Solid at size 0, or a texture that no longer resolves.
profile.customBorderEnabled, profile.customBorderTexture, profile.customBorderSize = true, "solid", 0
PageShown()
assert(uiRows[1][1].disabledValues("border") and not cog.shown, "Custom Solid at size 0 offers Color Border")
profile.customBorderSize, profile.customBorderTexture = 2, "missing"
PageShown()
assert(uiRows[1][1].disabledValues("border") and not cog.shown, "an unresolved texture offers Color Border")
profile.customBorderTexture = "pixels"
PageShown()
assert(not uiRows[1][1].disabledValues("border") and not cog.shown)
profile.customBorderEnabled, profile.customBorderTexture, profile.customBorderSize = false, nil, nil
-- Color Nameplate drops the cog; None keeps the border choice for later.
uiRows[1][1].setValue("nameplate")
assert(profile.debuffColorsBorder == false and #uiCogs == 0)
uiRows[1][1].setValue("border")
uiRows[1][1].setValue("none")
assert(profile.debuffColorsEnabled == false and profile.debuffColorsBorder == true and #uiRows == 1)

-- WoW Forever: its own class roster and no presets (custom IDs only).
EllesmereUI.IS_FOREVER = true
function EllesmereUI.ForeverClasses() return { "WARRIOR", "DRUID", "MAGE" } end
function EllesmereUI.ForeverClassName(token) return token:sub(1, 1) .. token:sub(2):lower() end
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID="0:1,1,1/" })
EllesmereUI:RefreshPage(true)
d1 = Cell("Druid Debuff 1")
assert(d1 and #d1.cfg.order == 2, "WoW Forever listed retail presets")
Fire(Cell("+ Add Debuff").rgn._control, "OnClick")
local fvOrder = uiMenus[Cell("+ Add Debuff").rgn._control].order
assert(#fvOrder == 3 and fvOrder[1] == "DRUID" and fvOrder[2] == "MAGE", "WoW Forever class roster")
EllesmereUI.IS_FOREVER = false

-- The search pre-build makes rows but no chrome.
local before = #uiNotified
EllesmereUI._prebuilding = true
uiSwatches, uiCB = {}, {}
EllesmereUI:RefreshPage(true)
assert(#uiSwatches == 0 and #uiCB == 0 and #uiOnHide == 0)
EllesmereUI._prebuilding = nil
''')
print('PASS: options page: gate, live apply (every edit, color drags on picker close), class picker,')
print('      add/remove, reorder arrows, class-only presets, in-use spells greyed, custom spells (add-only,')
print('      listed while held), combo list (2-4 spells, warn, remove), caps, prebuild, Debuff Coloring')
print('      modes (a view over the saved keys), Color Border cog and its border gates.')
