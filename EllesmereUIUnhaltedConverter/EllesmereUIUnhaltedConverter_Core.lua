--[[ EllesmereUI Unhalted Converter — pure mapping core.
     Environment-agnostic: no WoW API calls. Takes a decoded Unhalted profile
     (the `.profile` table: { General=..., Units=... }) and returns EllesmereUI
     module settings tables + a list of human-readable warnings.

     Position resolution is delegated to an injected `ctx` so the same code runs
     offline (tests, with a mock ctx) and in-game (with live UIParent size and
     optional live Unhalted frame rects).
]]

local _, ns = ...
ns = ns or {}

local Core = {}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- Unhalted stores colors as arrays {[1]=r,[2]=g,[3]=b,[4]=a}. EUI uses {r,g,b,a}.
local function col(a)
    if type(a) ~= "table" then return nil end
    local c = { r = a[1] or 0, g = a[2] or 0, b = a[3] or 0 }
    if a[4] ~= nil then c.a = a[4] end
    return c
end

local function round(n, dp)
    if type(n) ~= "number" then return n end
    local m = 10 ^ (dp or 0)
    return math.floor(n * m + 0.5) / m
end

local function num(v, default)
    if type(v) == "number" then return v end
    return default
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[deepcopy(k)] = deepcopy(v) end
    return o
end

-- Return a deep copy of `src` with every key that is nil in src filled from the
-- matching key in `def`. A value already present in src (INCLUDING an explicit
-- false) is never overwritten; nested tables recurse into EVERY key, arrays
-- included, filling only nil indices.
--
-- AceDB serializes arrays SPARSELY -- one key per index that differs from the
-- default. A saved Layout {[2]="BOTTOMRIGHT"} means indices 1/3/4 still equal the
-- defaults; a {[3]=0,[4]=0} means the two anchor-point strings equal the
-- defaults. So element-wise recursion is exactly correct for AceDB-shaped data: a
-- nil index always means "use the default", and AceDB cannot express an array
-- SHORTER than its default (dropping a trailing element just re-serializes the
-- default). Treating arrays as opaque leaves loses defaults in BOTH directions --
-- e.g. a real target TagThree Layout {[3]=0,[4]=0} would lose its default
-- {"RIGHT","BOTTOMRIGHT"} anchor points and route the power text to "center"
-- instead of "right". Used to back-fill a sparse or old-version Unhalted import
-- from UUF's own defaults before mapping.
local function deepFillCopy(src, def)
    local out = deepcopy(src)
    if type(def) ~= "table" then return out end
    local function fill(dst, d)
        for k, dv in pairs(d) do
            local sv = dst[k]
            if sv == nil then
                dst[k] = deepcopy(dv)
            elseif type(sv) == "table" and type(dv) == "table" then
                fill(sv, dv)
            end
        end
    end
    fill(out, def)
    return out
end

-- Fractional position of an anchor point within a rect (0..1). x: LEFT 0 / RIGHT 1
-- / CENTER .5 ; y: BOTTOM 0 / TOP 1 / CENTER .5 (WoW bottom-left origin).
local function pointFrac(point)
    point = tostring(point or "CENTER"):upper()
    local fx, fy = 0.5, 0.5
    if point:find("LEFT") then fx = 0 elseif point:find("RIGHT") then fx = 1 end
    if point:find("TOP") then fy = 1 elseif point:find("BOTTOM") then fy = 0 end
    return fx, fy
end

-- Horizontal side of an anchor point / offset, for routing text into EUI regions.
local function hSide(point, x)
    point = tostring(point or ""):upper()
    if point:find("LEFT") then return "left" end
    if point:find("RIGHT") then return "right" end
    if type(x) == "number" and math.abs(x) > 20 then
        return x < 0 and "left" or "right"
    end
    return "center"
end

-- WoW anchor point -> nearest 4-corner key (topleft/topright/bottomleft/bottomright).
-- `relPoint` is the FRAME edge the icon is actually pinned to (mirrors the
-- auraAnchor fix above) -- e.g. Layout {CENTER, BOTTOM, 2, -20} hangs the icon
-- below the frame, not in a "top" corner as the icon's own CENTER point would
-- naively suggest. `x` breaks a side-only relPoint (BOTTOM/TOP alone, no L/R)
-- toward whichever half the offset leans. EUI's leaderIndicatorPosition is a
-- fixed 4-corner-inside-the-bar model with no "outside the frame" concept, so
-- a relPoint that hangs the icon below/above the frame can only be
-- approximated by its closest corner -- exact vertical placement is lost.
local function corner4(point, relPoint, x)
    local rp = tostring(relPoint or ""):upper()
    if rp ~= "" then
        local v = rp:find("BOTTOM") and "bottom" or (rp:find("TOP") and "top") or nil
        if v then
            local h
            if rp:find("RIGHT") then h = "right"
            elseif rp:find("LEFT") then h = "left"
            elseif type(x) == "number" and math.abs(x) > 20 then h = x < 0 and "left" or "right"
            else h = "left"
            end
            return v .. h
        end
        -- A side-only relPoint (LEFT/RIGHT, no top/bottom) carries no vertical
        -- signal; fall through to the icon's own point below.
    end
    point = tostring(point or "TOPLEFT"):upper()
    local v = point:find("BOTTOM") and "bottom" or "top"
    local h = point:find("RIGHT") and "right" or "left"
    return v .. h
end

-- WoW anchor point -> EllesmereUI raid 9-position key (lowercased 1:1).
local POS9 = {
    TOPLEFT="topleft", TOP="top", TOPRIGHT="topright",
    LEFT="left", CENTER="center", RIGHT="right",
    BOTTOMLEFT="bottomleft", BOTTOM="bottom", BOTTOMRIGHT="bottomright",
}
local function pos9(point)
    return POS9[tostring(point or "CENTER"):upper()] or "center"
end

-- Group-indicator offset transform. Unhalted anchors an icon as {point, relPoint,
-- x, y}; EllesmereUI instead anchors the icon's relPoint-derived point to the SAME
-- frame point plus a fixed inward inset (2px for the raid marker, 0 for role/leader
-- icons). To land the icon's CENTER where Unhalted put it -- including the "half in,
-- half out" straddle from point=CENTER on a frame edge -- convert the raw offset
-- with this size- and inset-aware delta. Since EllesmereUI's anchor point equals
-- Unhalted's relPoint, the frame anchor cancels and only the icon-center deltas and
-- the inset remain.
local function centerVec(anchor, size)
    anchor = tostring(anchor or "CENTER"):upper()
    local h = (size or 0) / 2
    local x, y = 0, 0
    if anchor:find("LEFT") then x = h elseif anchor:find("RIGHT") then x = -h end
    if anchor:find("TOP") then y = -h elseif anchor:find("BOTTOM") then y = h end
    return x, y
end
local function insetVec(pos, amount)
    pos = tostring(pos or ""):upper()
    amount = amount or 0
    local x, y = 0, 0
    if pos:find("LEFT") then x = amount elseif pos:find("RIGHT") then x = -amount end
    if pos:find("TOP") then y = -amount elseif pos:find("BOTTOM") then y = amount end
    return x, y
end
local function indicatorOffset(L, size, insetAmount)
    local point = L[1] or "CENTER"
    local relPoint = L[2] or point
    local cpx, cpy = centerVec(point, size)
    local crx, cry = centerVec(relPoint, size)
    local ix, iy = insetVec(relPoint, insetAmount)
    return round(num(L[3], 0) + cpx - crx - ix, 1),
           round(num(L[4], 0) + cpy - cry - iy, 1)
end

--------------------------------------------------------------------------------
-- Enum / name maps
--------------------------------------------------------------------------------

-- Unhalted frame global name -> EUI single-unit key.
local FRAME_TO_UNIT = {
    UUF_Player = "player", UUF_Target = "target", UUF_TargetTarget = "targettarget",
    UUF_Focus = "focus", UUF_FocusTarget = "focustarget", UUF_Pet = "pet",
    UUF_Boss = "boss",
}
local UNIT_TO_FRAME = {}
for frame, unit in pairs(FRAME_TO_UNIT) do UNIT_TO_FRAME[unit] = frame end

-- Aura anchor. In Unhalted the aura block's Layout is {point, relPoint, x, y}: the
-- block's `point` is pinned to the FRAME's `relPoint`, so relPoint is the frame
-- EDGE the icons sit against -- that's what EllesmereUI's buffAnchor encodes (NOT
-- the block's own corner). e.g. {point=RIGHT, relPoint=LEFT} => block sits to the
-- LEFT of the frame => "left". Fall back to the block's point for CENTER/unknown.
local ANCHOR_MAP = {
    TOPLEFT = "topleft", TOPRIGHT = "topright",
    BOTTOMLEFT = "bottomleft", BOTTOMRIGHT = "bottomright",
    LEFT = "left", RIGHT = "right",
    TOP = "topleft", BOTTOM = "bottomleft", CENTER = "topleft",
}
local function auraAnchor(point, relPoint)
    local pt = tostring(point or ""):upper()
    local rp = tostring(relPoint or ""):upper()
    -- A pure-side `point` opposing the relPoint side means the block sits BESIDE
    -- the frame, extending away from its own anchored edge -- e.g. {point=LEFT,
    -- relPoint=TOPRIGHT} pins the block's left edge at the frame's top-right
    -- corner, so the icons run rightward beside the frame ("right"); they do not
    -- hang above it ("topright"). Only exact side points take this path; corner
    -- points keep the relPoint-edge heuristic below.
    if pt == "LEFT" and rp:find("RIGHT") then return "right" end
    if pt == "RIGHT" and rp:find("LEFT") then return "left" end
    if pt == "TOP" and rp:find("BOTTOM") then return rp:find("RIGHT") and "bottomright" or "bottomleft" end
    if pt == "BOTTOM" and rp:find("TOP") then return rp:find("RIGHT") and "topright" or "topleft" end
    if rp:find("TOP") then return rp:find("RIGHT") and "topright" or "topleft" end
    if rp:find("BOTTOM") then return rp:find("RIGHT") and "bottomright" or "bottomleft" end
    if rp == "LEFT" then return "left" end
    if rp == "RIGHT" then return "right" end
    return ANCHOR_MAP[pt] or "topleft"
end

-- Unhalted growth direction -> EUI buff/debuff growth key. UUF's oUF SetPosition
-- only ever tests GrowthDirection against the literal "LEFT" (auras.lua:158-171) --
-- it is a horizontal sign flip, never a vertical-axis signal. Orientation is
-- carried by Wrap vs Num (single column when Wrap<=1), and in that case the
-- vertical sign comes from WrapDirection ("DOWN" -> -1), not GrowthDirection.
local function auraGrowth(group)
    if group.Wrap and group.Wrap <= 1 then
        -- true single column: vertical direction comes from WrapDirection
        return tostring(group.WrapDirection or ""):upper() == "DOWN" and "down" or "up"
    end
    return tostring(group.GrowthDirection or ""):upper() == "LEFT" and "left" or "right"
end

-- Unhalted LibSharedMedia statusbar name -> EUI built-in healthBarTexture key.
-- Anything not a built-in is emitted as a LibSharedMedia key ("sm:<name>"), which
-- is the ONLY form EllesmereUI resolves via LibSharedMedia (a raw name silently
-- falls back to a white bar). Keep the source texture pack / addon installed.
local TEXTURE_MAP = {
    ["flat"]     = "melli",
    ["smooth"]   = "melli",
    ["glow"]     = "glass",
    ["gradient"] = "gradient-lr",
}
local EUI_HEALTH_TEXTURES = {
    none=true, melli=true, beautiful=true, plating=true, atrocity=true, divide=true,
    glass=true, ["fade-right"]=true, ["thin-line-top"]=true, ["thin-line-bottom"]=true,
    fade=true, ["gradient-lr"]=true, ["gradient-rl"]=true, ["gradient-bt"]=true,
    ["gradient-tb"]=true, matte=true, sheer=true, ["blinkii-diamonds"]=true,
    ["kringel-window"]=true,
}
-- Statusbar textures that Unhalted itself registers with LibSharedMedia
-- (UnhaltedUnitFrames/Core/Globals.lua:35-39). The apply flow disables the
-- Unhalted addon (EllesmereUIUnhaltedConverter.lua ~224), and LSM registrations
-- only persist while the providing addon is loaded -- so an "sm:<name>" key for
-- one of these silently resolves to a plain white bar after the migration. None
-- of these names collide with TEXTURE_MAP / EUI_HEALTH_TEXTURES above, so they
-- would otherwise fall through to the "sm:" branch. Lowercased for lookup.
local UUF_BUNDLED_TEXTURES = {
    ["better blizzard"]=true, ["dragonflight"]=true, ["skyline"]=true,
    ["stripes"]=true, ["thin stripes"]=true,
}
-- Fonts that Unhalted itself registers (UnhaltedUnitFrames/Core/Globals.lua:43-48)
-- AND that EllesmereUI does NOT bundle on its own. Like the textures above, an
-- "sm:<name>" key for one of these stops resolving once the disabled Unhalted
-- addon is unloaded. Note "Expressway" (Globals.lua:43) is EXCLUDED -- EllesmereUI
-- ships its own "Expressway" (EllesmereUI.lua:3519 FONT_FILES), so that key still
-- resolves. EllesmereUI's "Avant Garde" (EllesmereUI.lua:3521) is a distinct name
-- from Unhalted's "Avante"/"Avantgarde (...)" variants and does not cover them.
-- Lowercased for lookup.
local UUF_BUNDLED_FONTS_EUI_LACKS = {
    ["avante"]=true, ["avantgarde (book)"]=true, ["avantgarde (book oblique)"]=true,
    ["avantgarde (demi)"]=true, ["avantgarde (regular)"]=true,
}

--------------------------------------------------------------------------------
-- Tag parsing: Unhalted oUF tag string -> EUI text content descriptor
--------------------------------------------------------------------------------

-- A color-prefix token ([powercolor], [raidcolor], [classcolor], [reactioncolour],
-- [class]) carries no text -- it only tints the value that follows. Treat as a hint.
local function isColorToken(low)
    return low:match("^%a*colou?r$") ~= nil or low == "class"
end

-- [reactioncolour] is a DIFFERENT semantic from [raidcolor]/[classcolor]/[class]:
-- it's a UUF-authored tag (Core/Config/TagsDatabase.lua) that reads
-- UUF.db.profile.General.Colours.Reaction directly and embeds that hex color --
-- i.e. it always renders Unhalted's REACTION color table, on every unit
-- (players included), never an actual class color. [raidcolor]/[classcolor]/
-- [class], by contrast, are oUF's built-in tag (Libraries/oUF/elements/tags.lua)
-- backed by UnitClass(u) -- a REAL class color for any unit WoW resolves a class
-- for (players, and player-controlled pets/guardians per Blizzard's own
-- UnitTreatAsPlayerForDisplay-gated CompactUnitFrame.lua coloring). EUI's single
-- <region>TextClassColor toggle only reproduces the class-color half of this
-- (ns.ResolveUnitNameColor falls back to reaction color for any non-player unit,
-- which is what a pet's real reaction color needs anyway) -- so a pet's
-- [reactioncolour] tag already lands correctly through that toggle, while a
-- pet's [raidcolor]/[classcolor] tag needs the real class color resolved
-- separately (see writeRegion's pet branch below). Only pet needs this
-- distinction: every other unit's "class" prefix already gets a real class
-- through ResolveUnitNameColor's own UnitIsPlayer branch.
local function colorTokenKind(low)
    return low:find("reaction") and "reaction" or "class"
end

-- Classify one bracket token's inner text -> a content descriptor, or nil if it
-- isn't recognised text content.
local function classifyToken(low)
    -- "[curpp:manapercent]" is a CONDITIONAL single value, not "current + percent":
    -- UUF's tag renders mana-percent for mana users and raw current power otherwise
    -- (UnhaltedUnitFrames/Core/Config/TagsDatabase.lua:356-366). EUI has an exact
    -- equivalent -- powerTextFormat="smart" (percent for mana-based specs, numeric
    -- for others, EllesmereUIUnitFrames.lua:4337-4350). Must catch this BEFORE the
    -- plain curpp check below (find() would match "curpp" first) and BEFORE the
    -- curpp+perpp "both" case (manapercent wins).
    -- `raw` (curpp/bothpp/smartpp only): UUF's plain [curpp] renders the RAW power
    -- number and only [curpp:abbr] abbreviates, so a token WITHOUT ":abbr" must map
    -- to EUI's non-abbreviating [eui-curpp-raw] path (out.powerTextRaw) -- otherwise
    -- a full number renders as e.g. "250K". Percent-only ([perpp]) has no abbr form.
    if low:find("curpp") and low:find("manapercent") then
        return { content = "smartpp", power = true, raw = low:find("abbr", 1, true) == nil }
    end
    -- "[curpp][perpp]"-style token combining raw current AND percent in one token
    -- genuinely renders TWO values -> EUI powerTextFormat="both".
    if low:find("curpp") and low:find("perpp") then
        return { content = "bothpp", power = true, raw = low:find("abbr", 1, true) == nil }
    end
    if low:find("curpp") or low:find("maxpp") then
        return { content = "curpp", power = true, raw = low:find("abbr", 1, true) == nil }
    end
    if low:find("perpp") or low:find("manapercent") then return { content = "perpp", power = true } end
    if low:find("curhpperhp") then return { content = "both" } end
    if low:find("perhp") then return { content = "perhp" } end
    if low:find("curhp") or low:find("missinghp") or low:find("maxhp") then return { content = "curhpshort" } end
    if low:find("absorb") then return { content = "absorbshort" } end
    if low:find("group") then return { content = "group" } end
    -- oUF's built-in [status] tag (Dead/Ghost/Offline) -- exact match only, so it
    -- never fires on some other token that merely contains the word "status".
    if low == "status" then return { content = "status" } end
    if low:find("name") or low:find("nick") then
        return { content = low:find("target") and "nametotarget" or "name" }
    end
    return nil
end

-- Literal text made up only of separator/divider characters -- any mix of
-- "| / - • » : ," plus whitespace and "%" -- carries no content once the
-- bracket tokens are stripped out (e.g. the " | " between two tags, or a
-- trailing "%"). Such literals are dropped silently; anything else left over
-- is real lost text and still warns.
local function isDividerLiteral(s)
    return s ~= "" and s:match("^[%s|/%-•»:,%%]+$") ~= nil
end

-- Parse a full Unhalted tag string -- which may combine color-prefix tokens,
-- one or more content tokens, and literal decoration (e.g. "[powercolor][curpp]",
-- "[name:short10:colour]|[perhp]%") -- into an ORDERED list of recognised EUI
-- content descriptors (one per recognised token) plus the leftover literal.
-- A color-prefix token ([powercolor], [classcolor]...) tints only the very next
-- token in the stream (mirrors reading order; UUF tags conventionally put the
-- color prefix immediately before the value it colors).
-- Returns { tokens = {desc, ...}, mapped, multiContent, unrecognizedCount,
--           literal, raw, content, power, powerColor, classColor, shortLen }
-- (the last five are the FIRST token's fields, kept for callers -- like
-- mapGroupText -- that only ever place one token) or nil for an empty/disabled
-- slot (no bracket tokens at all).
local function parseTag(tagStr)
    if type(tagStr) ~= "string" then return nil end
    local rawTokens = {}
    for inner in tagStr:gmatch("%[(.-)%]") do rawTokens[#rawTokens + 1] = inner end
    if #rawTokens == 0 then return nil end

    local descs, unrecognized, colorHint, colorHintKind = {}, 0, false, nil
    for _, inner in ipairs(rawTokens) do
        local low = inner:lower()
        if isColorToken(low) then
            colorHint = true
            colorHintKind = colorTokenKind(low)
        else
            local c = classifyToken(low)
            if c then
                c.shortLen = tonumber(low:match("short:?(%d+)"))
                if colorHint or low:find("colou?r") or low:find("class") then
                    if c.power then c.powerColor = true else
                        c.classColor = true
                        -- An inline suffix (e.g. "[name:colour]", no separate prefix
                        -- token) has no reaction form in Unhalted's tag set -- only
                        -- a genuine [reactioncolour] PREFIX carries that kind.
                        c.colorKind = colorHint and colorHintKind or "class"
                    end
                end
                descs[#descs + 1] = c
            else
                unrecognized = unrecognized + 1
            end
            colorHint, colorHintKind = false, nil
        end
    end

    -- Literal decoration left after removing every [...] token.
    local litRaw = tagStr:gsub("%[.-%]", ""):gsub("%s+", "")
    local lit
    if litRaw ~= "" and not isDividerLiteral(litRaw) then
        -- A "%" is implied by the percent presets, so it doesn't count as lost
        -- text once we know the literal is more than just divider punctuation.
        lit = litRaw:gsub("%%", "")
        if lit == "" then lit = nil end
    end

    if #descs == 0 then
        return { content = "none", mapped = false, raw = tagStr, literal = lit, tokens = {} }
    end

    local first = descs[1]
    return {
        tokens = descs, raw = tagStr, literal = lit, mapped = true,
        multiContent = (#descs + unrecognized) > 1,
        unrecognizedCount = unrecognized,
        content = first.content, power = first.power,
        powerColor = first.powerColor, classColor = first.classColor,
        colorKind = first.colorKind, shortLen = first.shortLen,
    }
end

--------------------------------------------------------------------------------
-- Position resolver
--------------------------------------------------------------------------------
-- ctx = {
--   uiWidth, uiHeight,             -- UIParent logical dimensions
--   getLiveUnitRect(frameName),    -- optional: {x=cx,y=cy} live center in UIParent space, or nil
--   getExternalRect(frameName),    -- optional: {left,bottom,w,h} for non-unit anchors (CDM…), or nil
-- }

local EUI_DEFAULT_POS = {
    player = { point="CENTER", relPoint="CENTER", x=-317, y=-193.5 },
    target = { point="CENTER", relPoint="CENTER", x=317, y=-201 },
    focus = { point="CENTER", relPoint="CENTER", x=0, y=-285 },
    pet = { point="CENTER", relPoint="CENTER", x=-300, y=-260 },
    targettarget = { point="CENTER", relPoint="CENTER", x=383, y=-152.5 },
    focustarget = { point="CENTER", relPoint="CENTER", x=50, y=-261 },
    boss = { point="CENTER", relPoint="CENTER", x=661, y=251 },
}

local function centerToPos(cx, cy, ctx)
    return {
        point = "CENTER", relPoint = "CENTER",
        x = round(cx - ctx.uiWidth / 2, 1),
        y = round(cy - ctx.uiHeight / 2, 1),
    }
end

-- Compute an absolute rect {left,bottom,w,h,cx,cy} for a Unhalted unit frame in
-- UIParent space, or nil if the anchor chain can't be resolved offline.
-- `warnings` (optional) receives a note when an unresolvable AnchorParent falls
-- back to UIParent -- mirroring UUF's own runtime resolution of AnchorParent as
-- `_G[AnchorParent] or UIParent` (UnhaltedUnitFrames/Core/UnitFrame.lua:155):
-- case-sensitive, silent fallback to UIParent for any name it doesn't find.
local function resolveRect(unitKey, units, ctx, cache, depth, warnings)
    if cache[unitKey] ~= nil then return cache[unitKey] or nil end
    if depth > 12 then return nil end
    local unit = units[unitKey]
    if not unit or not unit.Frame then return nil end
    local f = unit.Frame
    local layout = f.Layout or {}
    local w = num(f.Width, 0)
    local h = num(f.Height, 0)
    local point = layout[1] or "CENTER"
    local relPoint = layout[2] or point
    local ox = num(layout[3], 0)
    local oy = num(layout[4], 0)

    -- Determine parent rect
    local parentName = f.AnchorParent
    local cdmAnchored = false
    if not parentName and (unitKey == "player" or unitKey == "target")
        and unit.HealthBar and unit.HealthBar.AnchorToCooldownViewer then
        parentName = "UUF_CDMAnchor"
        cdmAnchored = true
    end

    local pRect
    if not parentName or parentName == "UIParent" then
        pRect = { left = 0, bottom = 0, w = ctx.uiWidth, h = ctx.uiHeight }
    elseif FRAME_TO_UNIT[parentName] then
        pRect = resolveRect(FRAME_TO_UNIT[parentName], units, ctx, cache, depth + 1, warnings)
    elseif ctx.getExternalRect then
        pRect = ctx.getExternalRect(parentName)
    end

    if not pRect then
        -- Unknown/unresolvable AnchorParent (wrong case, nonexistent frame, or a
        -- Cooldown-Viewer anchor we can't resolve offline): fall back to UIParent,
        -- same as UUF does, instead of leaving the frame unresolved.
        pRect = { left = 0, bottom = 0, w = ctx.uiWidth, h = ctx.uiHeight }
        if warnings then
            if cdmAnchored then
                warnings[#warnings + 1] = ("%s: anchored to the Cooldown Viewer, which could not be resolved here — anchored to the screen instead (actual in-game position may differ if the Cooldown Viewer existed for you).")
                    :format(unitKey)
            else
                warnings[#warnings + 1] = ('%s: anchor frame "%s" not found — anchored to the screen instead (same as Unhalted\'s fallback).')
                    :format(unitKey, tostring(parentName))
            end
        end
    end

    local pfx, pfy = pointFrac(relPoint)
    local ax = pRect.left + pfx * pRect.w + ox
    local ay = pRect.bottom + pfy * pRect.h + oy
    local ffx, ffy = pointFrac(point)
    local left = ax - ffx * w
    local bottom = ay - ffy * h
    local rect = { left = left, bottom = bottom, w = w, h = h, cx = left + w / 2, cy = bottom + h / 2 }
    cache[unitKey] = rect
    return rect
end

-- Clamp a frame center so its rect stays within the [0,uiWidth] x [0,uiHeight]
-- screen. If the frame itself is wider/taller than the screen, center it on
-- that axis instead of pinning min>max. Warns (once per unitKey, via the
-- caller's cache-backed dedup) when the clamp moved the center more than ~2px.
local function clampToScreen(cx, cy, w, h, ctx, unitKey, warnings)
    local hw, hh = (num(w, 0)) / 2, (num(h, 0)) / 2
    local minX, maxX = hw, ctx.uiWidth - hw
    if minX > maxX then minX, maxX = ctx.uiWidth / 2, ctx.uiWidth / 2 end
    local minY, maxY = hh, ctx.uiHeight - hh
    if minY > maxY then minY, maxY = ctx.uiHeight / 2, ctx.uiHeight / 2 end
    local nx = math.max(minX, math.min(maxX, cx))
    local ny = math.max(minY, math.min(maxY, cy))
    local moved = math.sqrt((nx - cx) ^ 2 + (ny - cy) ^ 2)
    if moved > 2 and warnings then
        warnings[#warnings + 1] = ("%s: frame was (partly) off-screen — moved to the nearest visible position.")
            :format(unitKey)
    end
    return nx, ny
end

-- Public: resolve a single-frame position -> EUI positions entry + ok flag.
local function resolvePosition(unitKey, units, ctx, cache, warnings)
    local unit = units[unitKey]
    local f = unit and unit.Frame
    if not f then return EUI_DEFAULT_POS[unitKey], false end

    -- 1. Live Unhalted frame rect (most accurate; only in-game with UUF loaded).
    --    The live rect has no w/h of its own -- use the unit's own Frame
    --    Width/Height from the profile for the off-screen clamp below.
    if ctx.getLiveUnitRect then
        local r = ctx.getLiveUnitRect(UNIT_TO_FRAME[unitKey])
        if r and r.x then
            local cx, cy = clampToScreen(r.x, r.y, f.Width, f.Height, ctx, unitKey, warnings)
            return centerToPos(cx, cy, ctx), true
        end
    end

    -- 2. Resolve the anchor chain to an absolute CENTER and emit CENTER/CENTER.
    --    Never pass Unhalted's raw corner anchor through verbatim: EllesmereUI's
    --    frame is a different size, so keeping a non-center corner anchor shifts the
    --    frame's center by ~(dWidth/2, dHeight/2) -- the "less centered" symptom.
    --    Resolving to the center (which subtracts Unhalted's own Width/Height) makes
    --    the differing sizes cancel out and the frame lands where Unhalted had it.
    --    resolveRect itself now always resolves to SOME rect (falling back to
    --    UIParent for an unresolvable AnchorParent, mirroring UUF), so this only
    --    returns nil for a structural failure (circular anchor chain).
    local rect = resolveRect(unitKey, units, ctx, cache, 0, warnings)
    if rect then
        local cx, cy = clampToScreen(rect.cx, rect.cy, rect.w, rect.h, ctx, unitKey, warnings)
        return centerToPos(cx, cy, ctx), true
    end

    -- 3. Unresolvable (circular anchor chain, or UUF not loaded and no live rect):
    --    keep EUI default and tell the user to reposition.
    local parentName = f.AnchorParent
    local cdmAnchored = (unitKey == "player" or unitKey == "target")
        and unit.HealthBar and unit.HealthBar.AnchorToCooldownViewer
    warnings[#warnings + 1] = ("Could not resolve %s frame position (anchored to %s); left at EllesmereUI default — reposition in Unlock mode.")
        :format(unitKey, tostring(parentName or (cdmAnchored and "Cooldown Viewer") or "?"))
    return EUI_DEFAULT_POS[unitKey], false
end

--------------------------------------------------------------------------------
-- Element mappers (single frames)
--------------------------------------------------------------------------------

-- Units whose EllesmereUI frame actually builds a power bar/text, cast bar, and
-- aura containers. CreatePowerBar/CreateCastBar/CreateTargetAuras in
-- EllesmereUIUnitFrames.lua are only called for player/target/focus/boss;
-- targettarget/focustarget/pet use the simple/pet frame style (health + portrait
-- + text only), so those keys would otherwise be dead writes.
local FULL_ELEMENT_UNITS = { player = true, target = true, focus = true, boss = true }

-- Leader/assistant and combat indicators are hardcoded to player/target only
-- (EllesmereUIUnitFrames.lua:11508-11509 and 11322-11325) -- every other unit's
-- frame never reads leaderIndicator*/combatIndicator*.
local LEADER_COMBAT_UNITS = { player = true, target = true }

-- Units whose EllesmereUI frame actually spawns a portrait. UUF hard-excludes
-- targettarget/focustarget from portrait creation (UnhaltedUnitFrames/Core/
-- UnitFrame.lua:31, :200 -- `not isTargetTarget and not isFocusTarget`) and its
-- GUI never exposes a Portrait tab for those two units, so their
-- Portrait.Enabled is vestigial schema data that must not be mapped.
local PORTRAIT_UNITS = { player = true, target = true, focus = true, boss = true, pet = true }

local function mapHealth(u, out)
    local hb = u.HealthBar
    if not hb then return end
    -- UUF's HealthBar.ColourByClass defaults true on every single unit, so a
    -- missing value (sparse/old import) reads as class-colored.
    out.healthClassColored = hb.ColourByClass ~= false
    if not hb.ColourByClass and hb.Foreground then
        out.customFillColor = col(hb.Foreground)
    end
    if hb.Background then out.customBgColor = col(hb.Background) end
    out.bgClassColored = hb.ColourBackgroundByClass and true or false
    out.healthReverseFill = hb.Inverse and true or false
    out.smoothBars = hb.Smooth and true or false
    -- Opacity is 0-1 in Unhalted, 0-100 in EllesmereUI. Foreground -> fill alpha,
    -- Background -> the separate background alpha key.
    if hb.ForegroundOpacity then out.healthBarOpacity = round(hb.ForegroundOpacity * 100) end
    if hb.BackgroundOpacity then out.customBgAlpha = round(hb.BackgroundOpacity * 100) end
end

local function mapPower(u, out, unitKey, warnings)
    local pb = u.PowerBar
    if not pb then return end
    if not pb.Enabled then
        out.powerPosition = "none"
    elseif tostring(pb.Position or ""):upper() == "TOP" then
        -- EUI's powerPosition enum has no "top" value (below/above/detached_top/
        -- detached_bottom/none — EUI_UnitFrames_Options.lua:6747 ppPosValues); every
        -- read site falls through to "below" for an unrecognized value
        -- (EllesmereUIUnitFrames.lua:4115-4127), so "top" must map to "above".
        out.powerPosition = "above"
    else
        out.powerPosition = "below"
    end
    if pb.Height then out.powerHeight = pb.Height end
    out.powerReverseFill = pb.Inverse and true or false
    out.powerBgPowerColored = pb.ColourBackgroundByType and true or false
    -- Custom power-bar fill: EUI reads customPowerFillColor only when
    -- powerPercentPowerColor is false (usePowerColor = powerPercentPowerColor ~= false,
    -- EllesmereUIUnitFrames.lua:4159-4166). ColourByType==false is UUF's "use a fixed
    -- color, not the power-type color".
    if pb.ColourByType == false then
        out.powerPercentPowerColor = false
        if pb.Foreground then out.customPowerFillColor = col(pb.Foreground) end
    end
    -- Custom power-bar background is independent of the fill: EUI uses
    -- customPowerBgColor when powerBgPowerColored is false (EllesmereUIUnitFrames.lua:4150,:4231).
    if pb.Background then out.customPowerBgColor = col(pb.Background) end
    -- UUF class-colored power (ColourByClass, default false) has no EUI equivalent --
    -- EUI power fill is either power-type or a single custom color, never class.
    if pb.ColourByClass and warnings then
        warnings[#warnings + 1] = ("%s: class-colored power bar isn't supported — using power-type color instead.")
            :format(tostring(unitKey))
    end
end

-- Player-only secondary (class) power bar. UUF SecondaryPowerBar.Position is
-- TOP/BOTTOM, matching EllesmereUI's classPowerPosition "top"/"bottom" enum
-- 1:1 (a third "above" value exists in EUI but has no UUF equivalent).
local function mapSecondaryPower(u, out)
    local sp = u.SecondaryPowerBar
    if not sp then return end
    if not sp.Enabled then return end  -- EUI default is classPowerStyle="none"; nothing to write
    out.classPowerStyle = "modern"
    out.showClassPowerBar = true  -- kept in sync with style ~= "none" (EllesmereUIUnitFrames.lua:11171)
    out.classPowerPosition = (tostring(sp.Position or ""):upper() == "BOTTOM") and "bottom" or "top"
    if sp.Height then out.classPowerSize = sp.Height end
    if sp.ColourByClass then
        out.classPowerClassColor = true
    elseif sp.ColourByType == false then
        out.classPowerClassColor = false
        if sp.Foreground then out.classPowerCustomColor = col(sp.Foreground) end
    end
    if sp.Background then out.classPowerBgColor = col(sp.Background) end
end

local function mapPortrait(u, out)
    local p = u.Portrait
    if not p then return end
    out.showPortrait = p.Enabled and true or false
    -- Mirror UUF's own precedence (UnhaltedUnitFrames/Elements/Portrait.lua):
    -- Style=="3D" spawns a PlayerModel and IGNORES UseClassPortrait entirely;
    -- UseClassPortrait (class icon vs unit portrait) only applies in the 2D
    -- branch. Checking UseClassPortrait first (as this used to) mis-mapped any
    -- 3D-model frame that also had UseClassPortrait set -- it became a class
    -- icon in EUI instead of the 3D model UUF actually shows. EUI portraitMode
    -- values: "2d" / "3d" / "class".
    local style = p.Style and tostring(p.Style):upper()
    if style == "3D" then
        out.portraitMode = "3d"
    elseif p.UseClassPortrait then
        out.portraitMode = "class"
    elseif style then
        out.portraitMode = style:lower()
    end
    if type(p.Width) == "number" and p.Width > 0 then out.portraitSize = p.Width end
    local L = p.Layout
    if L then
        out.portraitX = round(num(L[3], 0), 1)
        out.portraitY = round(num(L[4], 0), 1)
        local relPoint = tostring(L[2] or ""):upper()
        if relPoint:find("LEFT") then
            out.portraitSide = "left"
        elseif relPoint:find("RIGHT") then
            out.portraitSide = "right"
        end
    end
end

-- Mouseover highlight border. All units (single frames). EUI highlight defaults
-- ON (nil == enabled); only an explicit false disables it, so only write
-- highlightEnabled when Unhalted's Mouseover is explicitly disabled.
local function mapHighlight(u, out)
    local mo = u.Indicators and u.Indicators.Mouseover
    if not mo then return end
    -- Mouseover.Enabled defaults true on every single unit; only an explicit
    -- false disables the highlight (a missing value stays enabled).
    if mo.Enabled == false then out.highlightEnabled = false end
    if mo.Colour then out.highlightColor = col(mo.Colour) end
    if mo.HighlightOpacity then out.highlightAlpha = mo.HighlightOpacity end
end

-- Castbar. `pfx` is the key prefix: "" for target/focus/boss (showCastbar/castbar*)
-- or "player" for the player frame (showPlayerCastbar/playerCastbar*).
-- `unitKey` selects the width/offset special-casing below (MatchParentWidth,
-- boss castbarOffsetX/Y).
local function mapCastbar(u, out, unitKey, warnings)
    local cb = u.CastBar
    if not cb then return end
    local isPlayer = (unitKey == "player")
    local isBoss = (unitKey == "boss")
    -- MatchParentWidth (UUF default true) makes the castbar track the frame's own
    -- width instead of its own Width setting.
    local frameWidth = u.Frame and u.Frame.Width
    local matchParent = cb.MatchParentWidth ~= false
    -- playerCastbarX/Y (and, for target/focus below, a would-be castbarX/Y) are
    -- dead keys -- nothing in EllesmereUI reads them; castbar position for
    -- player/target/focus is owned by the drag/unlock anchor DB (only boss
    -- castbarOffsetX/Y is live). Warn instead of writing them when Unhalted's
    -- offset is non-trivial.
    local function warnDragPositioned()
        local L = cb.Layout
        if L and (math.abs(num(L[3], 0)) > 1 or math.abs(num(L[4], 0)) > 1) then
            warnings[#warnings + 1] = ("%s: cast bar position is drag-positioned in EllesmereUI — use Unlock mode to move it (Unhalted offset x,y dropped).")
                :format(unitKey)
        end
    end
    if isPlayer then
        out.showPlayerCastbar = cb.Enabled and true or false
        if matchParent then
            if frameWidth then out.playerCastbarWidth = frameWidth end
        elseif cb.Width then
            out.playerCastbarWidth = cb.Width
        end
        if cb.Height then out.playerCastbarHeight = cb.Height end
        if cb.Icon then out.showPlayerCastIcon = cb.Icon.Enabled and true or false end
        warnDragPositioned()
        -- NotInterruptibleColour is functionally live for player too (only EUI's
        -- options UI hides the picker) -- map it here as well.
        if cb.NotInterruptibleColour then out.castbarUninterruptibleColor = col(cb.NotInterruptibleColour) end
    else
        out.showCastbar = cb.Enabled and true or false
        if matchParent then
            -- 0 = match frame width (EUI_UnitFrames_Options.lua:1487); boss always
            -- uses this form since it has no "auto" width of its own otherwise.
            out.castbarWidth = isBoss and 0 or frameWidth
        elseif cb.Width and cb.Width > 0 then
            out.castbarWidth = cb.Width
        end
        if cb.Height then out.castbarHeight = cb.Height end
        if cb.Icon then out.showCastIcon = cb.Icon.Enabled and true or false end
        if cb.NotInterruptibleColour then out.castbarUninterruptibleColor = col(cb.NotInterruptibleColour) end
        if isBoss then
            local L = cb.Layout
            if L then
                out.castbarOffsetX = round(num(L[3], 0), 1)
                out.castbarOffsetY = round(num(L[4], 0), 1)
            end
        else
            warnDragPositioned()
        end
    end
    if cb.Icon and tostring(cb.Icon.Position or ""):upper() == "RIGHT" then
        if isPlayer then out.playerCastbarIconRight = true else out.castbarIconRight = true end
    end
    out.castReverseFill = cb.Inverse and true or false
    out.castbarClassColored = cb.ColourByClass and true or false
    if cb.Foreground then out.castbarFillColor = col(cb.Foreground) end
    if cb.Background then
        out.castBgColor = col(cb.Background)
        if cb.Background[4] then out.castBgAlpha = cb.Background[4] end
    end
    local T = cb.Text
    if T then
        if T.SpellName then
            -- UUF honors SpellName.Enabled=false by hiding the cast name
            -- (UnhaltedUnitFrames/Elements/CastBar.lua:156). EUI has no show/hide key
            -- for the castbar spell name (only size/color/x/y), so it always shows it.
            if T.SpellName.Enabled == false then
                warnings[#warnings + 1] = ("%s: cast bar spell name is hidden in Unhalted, but EllesmereUI always shows the spell name — it will be visible.")
                    :format(unitKey)
            end
            if T.SpellName.FontSize then out.castSpellNameSize = T.SpellName.FontSize end
            if T.SpellName.Colour then out.castSpellNameColor = col(T.SpellName.Colour) end
            local L = T.SpellName.Layout
            if L then out.castSpellNameX = round(num(L[3], 0), 1); out.castSpellNameY = round(num(L[4], 0), 1) end
        end
        if T.Duration then
            -- CastBar.Text.Duration.Enabled defaults true on every unit that
            -- builds a cast bar (player/target/focus/boss).
            out.showCastDuration = T.Duration.Enabled ~= false
            if T.Duration.FontSize then out.castDurationSize = T.Duration.FontSize end
            if T.Duration.Colour then out.castDurationColor = col(T.Duration.Colour) end
            local L = T.Duration.Layout
            if L then out.castDurationX = round(num(L[3], 0), 1); out.castDurationY = round(num(L[4], 0), 1) end
        end
    end
    if cb.ShowTarget ~= nil then out.showCastTarget = cb.ShowTarget and true or false end
end

-- UUF absorb Position ("LEFT"/"RIGHT"/"ATTACH") -> EUI overlay edge mode.
local function edgeMode(pos)
    pos = tostring(pos or "ATTACH"):upper()
    if pos == "LEFT" then return "left" elseif pos == "RIGHT" then return "right" end
    return "overlay"
end

-- Heal prediction / absorbs. EllesmereUI draws shield-absorb and heal-absorb
-- overlays on player/target/focus only; it has no incoming-heal element.
local function mapAbsorbs(u, out, unitKey, warnings)
    if unitKey ~= "player" and unitKey ~= "target" and unitKey ~= "focus" then return end
    local hp = u.HealPrediction
    if not hp then return end
    local a = hp.Absorbs
    if a then
        out.showPlayerAbsorb = a.Enabled and (a.UseStripedTexture and "striped" or "clean") or "none"
        if a.Colour then out.absorbColor = col(a.Colour) end
        out.absorbEdgeMode = edgeMode(a.Position)
        if a.ShowOverAbsorb ~= nil then out.showOvershield = a.ShowOverAbsorb and true or false end
    end
    local ha = hp.HealAbsorbs
    if ha then
        out.healAbsorbStyle = ha.Enabled and (ha.UseStripedTexture and "striped" or "clean") or "none"
        if ha.Colour then out.healAbsorbColor = col(ha.Colour) end
        out.healAbsorbEdgeMode = edgeMode(ha.Position)
    end
    if hp.IncomingHeal and hp.IncomingHeal.Enabled and warnings and unitKey == "player" then
        warnings[#warnings + 1] = "Incoming-heal prediction isn't available on EllesmereUI single frames — skipped."
    end
end

-- Auras: one Unhalted group (Buffs/Debuffs) -> EUI keys with the given prefix.
-- isBoss selects the spacing-key form (boss reads a single buff/debuffSpacing; all
-- other units read split buff/debuffSpacingX + Y).
local function mapAuraGroup(group, out, prefix, durText, isBoss)
    if not group then return end
    local isBuff = (prefix == "buff")
    local enabled = group.Enabled and true or false
    local L = group.Layout or {}
    local anchor = auraAnchor(L[1], L[2])
    -- Visibility: buffs use showBuffs; EllesmereUI has NO showDebuffs -- debuff
    -- visibility is driven entirely by debuffAnchor=="none", so a disabled debuff
    -- group must anchor to "none" (writing showDebuffs=false is a no-op and the
    -- debuffs would keep showing).
    if isBuff then
        out.showBuffs = enabled
        out.buffAnchor = anchor
    else
        out.debuffAnchor = enabled and anchor or "none"
    end
    out["max" .. (isBuff and "Buffs" or "Debuffs")] = group.Num
    out[prefix .. "Size"] = group.Size
    out[prefix .. "Growth"] = auraGrowth(group)
    out[prefix .. "OffsetX"] = round(num(L[3], 0), 1)
    out[prefix .. "OffsetY"] = round(num(L[4], 0), 1)
    if group.Wrap then out[prefix .. "MaxPerRow"] = group.Wrap end
    -- Icon spacing is Unhalted's Layout 5th element.
    local sp = L[5]
    if type(sp) == "number" then
        if isBoss then
            out[prefix .. "Spacing"] = sp
        else
            out[prefix .. "SpacingX"] = sp
            out[prefix .. "SpacingY"] = sp
        end
    end
    if durText then
        out[prefix .. "ShowCooldownText"] = true
        if durText.FontSize then out[prefix .. "CooldownTextSize"] = durText.FontSize end
    end
end

-- Text: Unhalted's 5 positioned tag slots -> EUI fixed regions + power text.
local function mapText(u, out, isBoss, warnings, unitKey, ctx)
    local tags = u.Tags
    if not tags then return end
    local slots = { tags.TagOne, tags.TagTwo, tags.TagThree, tags.TagFour, tags.TagFive }
    -- "extra" is only a real region on the full player/target/focus frame style. It
    -- is NOT a region on boss: boss has exactly left/right/center, so "extra" must
    -- stay unavailable there or a 3rd/4th boss tag folded into "extra" would clobber
    -- an already-written region. targettarget/focustarget/pet (simple/pet frames)
    -- likewise have no "extra" slot. A boss tag with nowhere left to go now takes the
    -- "more content than EllesmereUI has room for" warning path below.
    local regionFree = { left = true, right = true, center = true,
        extra = (FULL_ELEMENT_UNITS[unitKey] and not isBoss) or false }
    local spillOrder = { "left", "right", "center", "extra" }
    -- Power text (powerTextFormat/powerPercent*) only exists alongside the power bar,
    -- which is only built for player/target/focus/boss.
    local hasPowerText = FULL_ELEMENT_UNITS[unitKey] or false
    local powerUsed = false
    local powerContent = nil  -- content of the FIRST placed power token (for the curpp+perpp -> "both" merge)
    local powerFirstRaw = false  -- .raw of the FIRST placed power token (for the "both" merge's raw carry-over)
    local statusWarned = false  -- [status] has no <region>TextContent value on single frames (see below)

    -- Frame geometry for folding UUF's full-frame tag anchors into EUI's
    -- health-bar-centered text regions (consumed by writeRegion's vertical fold).
    local frameH = num(u.Frame and u.Frame.Height, 0)
    -- Power bar only exists (and only steals health-bar height) on full units.
    local powerH = (FULL_ELEMENT_UNITS[unitKey] and u.PowerBar and u.PowerBar.Enabled)
        and num(u.PowerBar.Height, 0) or 0
    -- UUF stacks the power bar at the BOTTOM of the frame unless Position=="TOP"
    -- (mirrors mapPower's Position check); a bottom bar lifts the health center up.
    local powerAtBottom = tostring((u.PowerBar or {}).Position or ""):upper() ~= "TOP"

    local function writeRegion(region, tag, parsed)
        local L = tag.Layout or {}
        out[region .. "TextContent"] = parsed.content
        if tag.FontSize then out[region .. "TextSize"] = tag.FontSize end
        -- UUF anchors each tag FontString on the FULL frame via
        -- SetPoint(point, frame, relPoint, x, y), so profiles routinely pin text to a
        -- frame CORNER (TOPLEFT name, BOTTOMRIGHT health). EUI instead renders every
        -- region vertically CENTERED on the health bar -- leftText at
        -- ("LEFT", textOverlay, "LEFT", 5+TextX, TextY), rightText at (-5+TextX),
        -- centerText at (TextX), where textOverlay SetAllPoints(frame.Health)
        -- (EllesmereUIUnitFrames.lua:6515-6541 full style, :7109-7133 simple style,
        -- same geometry). Copying the raw y verbatim thus renders a top/bottom-pinned
        -- tag centered instead (the reported "name and health text isn't offsetting the
        -- same way" bug), so re-express the UUF anchor as an offset from the health
        -- bar's vertical center.
        local point = L[1]
        local relPoint = L[2] or point
        local x = num(L[3], 0)
        local y = num(L[4], 0)
        local fontSize = tag.FontSize or 12
        local _, relFy = pointFrac(relPoint)
        local _, ptFy = pointFrac(point)
        local healthCenterFromBottom = (powerAtBottom and powerH or 0) + (frameH - powerH) / 2
        local anchorY = relFy * frameH + y
        -- The (0.5 - ptFy)*fontSize term approximates the FontString's own height so a
        -- TOP-point tag (which hangs BELOW its anchor) folds correctly.
        out[region .. "TextY"] = round(anchorY - healthCenterFromBottom + (0.5 - ptFy) * fontSize, 1)
        -- Horizontal: EUI bakes a 5px pad into left/right regions (LEFT +5, RIGHT -5).
        -- When the UUF relPoint pins text to the SAME edge EUI chose for this region,
        -- cancel that base pad so the net inset matches UUF's raw x (e.g.
        -- {LEFT,LEFT,3,0} -> 5 + (3-5) = 3px, matching UUF's 3px). A corner/CENTER
        -- relPoint or a mismatched side would need the rendered text WIDTH to fold
        -- fully, which isn't known at conversion time, so those keep the raw x.
        local rp = tostring(relPoint or ""):upper()
        if region == "left" and rp:find("LEFT") then
            out[region .. "TextX"] = round(x - 5, 1)
        elseif region == "right" and rp:find("RIGHT") then
            out[region .. "TextX"] = round(x + 5, 1)
        else
            out[region .. "TextX"] = round(x, 1)
        end
        -- pet + a genuine class-color request (colorKind=="class", i.e.
        -- [raidcolor]/[classcolor]/[class] -- NOT [reactioncolour], which
        -- already renders correctly through the reaction branch below) is the
        -- one case EUI's single TextClassColor toggle can't reproduce: EUI's
        -- reaction-based fallback for non-player units would show reaction
        -- color, not Unhalted's real class color. Resolve the pet's actual,
        -- live class color at conversion time and bake it in as a custom RGB
        -- instead (ctx.resolveClassColor mirrors oUF's own raidcolor tag,
        -- which calls UnitClass(u) directly -- see colorTokenKind's comment).
        local petClassColor = (unitKey == "pet" and parsed.classColor and parsed.colorKind == "class"
            and ctx and ctx.resolveClassColor and ctx.resolveClassColor("pet")) or nil
        out[region .. "TextClassColor"] = (parsed.classColor and not petClassColor) and true or false
        if parsed.shortLen then out[region .. "TextShortNameLength"] = parsed.shortLen end
        -- Per-region color keys (<region>TextColorR/G/B) are read by
        -- ApplyClassColor for every frame style, including the full
        -- player/target/focus frames (EllesmereUIUnitFrames.lua's
        -- StyleFullFrame/StyleFocusFrame already pass s[region.."TextColorR"]
        -- etc. through) -- so they're always safe to emit from the tag's Colour.
        if petClassColor then
            out[region .. "TextColorR"] = petClassColor.r
            out[region .. "TextColorG"] = petClassColor.g
            out[region .. "TextColorB"] = petClassColor.b
        elseif tag.Colour then
            out[region .. "TextColorR"] = tag.Colour[1] or 1
            out[region .. "TextColorG"] = tag.Colour[2] or 1
            out[region .. "TextColorB"] = tag.Colour[3] or 1
        end
    end

    -- EllesmereUI text regions render one of a fixed set of presets, not a
    -- free-form oUF tag string. A tag string can carry several recognised
    -- tokens (e.g. "[name:short10:colour]|[perhp]%") -- each gets its own
    -- region/slot in turn (first token to the side-preferred region, the rest
    -- spilling into whatever regions are still free), so multiple tokens are
    -- only "lost" when there's nowhere left to put them, or the token itself
    -- has no EllesmereUI equivalent.
    for _, tag in ipairs(slots) do
        if type(tag) == "table" then
            local parsed = parseTag(tag.Tag)
            if parsed then
                if not parsed.mapped then
                    warnings[#warnings + 1] = ("%s: text tag %s has no EllesmereUI equivalent — left blank.")
                        :format(unitKey, tostring(parsed.raw or tag.Tag))
                else
                    local dropped = (parsed.unrecognizedCount or 0) > 0
                    local firstRegional = true
                    for _, tokDesc in ipairs(parsed.tokens) do
                        if tokDesc.power then
                            if not hasPowerText then
                                if not powerUsed then
                                    powerUsed = true
                                    warnings[#warnings + 1] = ("%s: power text tag (%s) has no EllesmereUI equivalent on this frame (no power bar/text) — skipped.")
                                        :format(unitKey, tostring(tag.Tag))
                                end
                            elseif not powerUsed then
                                powerUsed = true
                                powerContent = tokDesc.content
                                powerFirstRaw = tokDesc.raw or false
                                local L = tag.Layout or {}
                                out.powerTextFormat = (tokDesc.content == "smartpp" and "smart")
                                    or (tokDesc.content == "bothpp" and "both")
                                    or (tokDesc.content == "curpp" and "curpp") or "perpp"
                                out.powerShowPercent = (tokDesc.content ~= "curpp")
                                -- UUF [curpp]/[curpp:manapercent]/[curpp][perpp] without
                                -- ":abbr" -> EUI's non-abbreviating raw power tag.
                                if tokDesc.raw then out.powerTextRaw = true end
                                out.powerPercentText = hSide(L[1], L[3])
                                if tokDesc.powerColor then
                                    out.powerPercentTextPowerColor = true
                                elseif tag.Colour then
                                    -- Explicit custom color (no [powercolor]/class prefix) --
                                    -- mirrors writeRegion's tag.Colour -> TextColorR/G/B handling.
                                    out.powerPercentTextColorR = tag.Colour[1] or 1
                                    out.powerPercentTextColorG = tag.Colour[2] or 1
                                    out.powerPercentTextColorB = tag.Colour[3] or 1
                                end
                                if tag.FontSize then out.powerPercentSize = tag.FontSize end
                                out.powerPercentX = round(num(L[3], 0), 1)
                                out.powerPercentY = round(num(L[4], 0), 1)
                            else
                                -- A SECOND power token on the same unit. When the two
                                -- placed tokens are the raw-current and percent halves
                                -- (curpp + perpp, in either order -- e.g. UUF "[curpp]"
                                -- in one slot and "[perpp]" in another), they together
                                -- map to EUI's "both" format rather than dropping the
                                -- second one.
                                local a, b = powerContent, tokDesc.content
                                if (a == "curpp" and b == "perpp") or (a == "perpp" and b == "curpp") then
                                    out.powerTextFormat = "both"
                                    out.powerShowPercent = true
                                    -- Carry raw-ness from whichever half is the curpp:
                                    -- first token (powerFirstRaw) or this second token.
                                    if (a == "curpp" and powerFirstRaw) or (b == "curpp" and tokDesc.raw) then
                                        out.powerTextRaw = true
                                    end
                                else
                                    warnings[#warnings + 1] = ("%s: extra power text tag (%s) dropped — EllesmereUI supports one power text.")
                                        :format(unitKey, tostring(tag.Tag))
                                end
                            end
                        elseif tokDesc.content == "status" then
                            -- [status] (Dead/Ghost/Offline) is not a valid <region>TextContent
                            -- value on single frames -- EUI's single-frame text regions only
                            -- render the fixed content list writeRegion knows about, with no
                            -- status-tag equivalent. Don't let it claim a region; just warn.
                            if not statusWarned then
                                statusWarned = true
                                warnings[#warnings + 1] = ("%s: [status] text tag has no EllesmereUI equivalent on single frames — skipped.")
                                    :format(unitKey)
                            end
                        else
                            local pref
                            if firstRegional then
                                pref = hSide((tag.Layout or {})[1], (tag.Layout or {})[3])
                                firstRegional = false
                            end
                            if not pref or not regionFree[pref] then
                                for _, r in ipairs(spillOrder) do
                                    if regionFree[r] then pref = r; break end
                                end
                            end
                            if pref and regionFree[pref] then
                                regionFree[pref] = false
                                writeRegion(pref, tag, tokDesc)
                            else
                                dropped = true
                            end
                        end
                    end
                    if dropped then
                        warnings[#warnings + 1] = ("%s: text \"%s\" has more content than EllesmereUI has room for — some of it was dropped.")
                            :format(unitKey, tostring(tag.Tag))
                    end
                    if parsed.literal then
                        warnings[#warnings + 1] = ("%s: literal text in \"%s\" was dropped (EllesmereUI text uses fixed presets, not custom tags).")
                            :format(unitKey, tostring(tag.Tag))
                    end
                end
            end
        end
    end

    -- EVERY frame style's runtime (StyleFullFrame/StyleFocusFrame/StyleSimpleFrame/
    -- StylePetFrame/StyleBossFrame -- confirmed by grepping every "TextContent or"
    -- fallback in EllesmereUIUnitFrames.lua) defaults an UNSET leftTextContent to
    -- "name", and rightTextContent to a non-"none" value on full frames ("both" on
    -- player/target, "perhp" on focus/boss) -- so a profile with only, say, one
    -- tag mapped to "center" leaves left (and on full frames, right too) unwritten,
    -- and EUI's own default silently fills in a phantom name/health text nothing in
    -- the source profile asked for. Explicitly suppress every region no UUF tag
    -- ever claimed, on every unit -- center/extra already default to "none"
    -- everywhere so writing it here is a no-op, but left/right do not.
    for _, region in ipairs(spillOrder) do
        if regionFree[region] and out[region .. "TextContent"] == nil then
            out[region .. "TextContent"] = "none"
        end
    end
end

local function mapIndicators(u, out, unitKey, warnings)
    local ind = u.Indicators
    if not ind then return end
    -- Raid-target-marker indicator: player/target/focus/boss only.
    if ind.RaidTargetMarker then
        if FULL_ELEMENT_UNITS[unitKey] then
            -- RaidTargetMarker.Enabled defaults true on player/target/focus/boss.
            out.raidMarkerEnabled = ind.RaidTargetMarker.Enabled ~= false
            if ind.RaidTargetMarker.Size then out.raidMarkerSize = ind.RaidTargetMarker.Size end
            local L = ind.RaidTargetMarker.Layout
            if L then
                out.raidMarkerAlign = hSide(L[1], L[3])
                out.raidMarkerX = round(num(L[3], 0), 1)
                out.raidMarkerY = round(num(L[4], 0), 1)
            end
        elseif ind.RaidTargetMarker.Enabled then
            warnings[#warnings + 1] = ("%s: raid target marker is enabled in Unhalted, but EllesmereUI has no raid marker on this frame — skipped.")
                :format(unitKey)
        end
    end
    -- Leader/assistant and combat indicators: player/target only.
    if ind.LeaderAssistantIndicator then
        local li = ind.LeaderAssistantIndicator
        if LEADER_COMBAT_UNITS[unitKey] then
            out.leaderIndicatorEnabled = li.Enabled and true or false
            if li.Size then out.leaderIndicatorSize = li.Size end
            local L = li.Layout
            if L then
                out.leaderIndicatorPosition = corner4(L[1], L[2], L[3])
                out.leaderIndicatorX = round(num(L[3], 0), 1)
                out.leaderIndicatorY = round(num(L[4], 0), 1)
            end
        elseif li.Enabled then
            warnings[#warnings + 1] = ("%s: leader/assistant indicator is enabled in Unhalted, but EllesmereUI only shows it on player/target — skipped.")
                :format(unitKey)
        end
    end
    if ind.Combat and ind.Combat.Enabled then
        if LEADER_COMBAT_UNITS[unitKey] then
            out.combatIndicatorStyle = "class"
            if ind.Combat.Size then out.combatIndicatorSize = ind.Combat.Size end
            local L = ind.Combat.Layout
            if L then
                out.combatIndicatorX = round(num(L[3], 0), 1)
                out.combatIndicatorY = round(num(L[4], 0), 1)
            end
        else
            warnings[#warnings + 1] = ("%s: combat indicator is enabled in Unhalted, but EllesmereUI only shows it on player/target — skipped.")
                :format(unitKey)
        end
    end
    -- Boss current-target border. UUF's boss Indicators.Target (default Enabled=true,
    -- Style="Glow") highlights which boss is your current target; EUI's equivalent is
    -- the boss-only bossTargetBorderEnabled/Color (default off, applied in
    -- ApplyBossBorderState, EllesmereUIUnitFrames.lua:973-975,:5507-5509). Only boss
    -- has this key -- for every other unit EUI has no target-border concept, and UUF's
    -- default-true Target would make a warning fire on ~every profile, so stay silent.
    if unitKey == "boss" and ind.Target then
        out.bossTargetBorderEnabled = ind.Target.Enabled and true or false
        if ind.Target.Colour then out.bossTargetBorderColor = col(ind.Target.Colour) end
    end
    -- Threat indicator. EUI has a PLAYER-only threat border
    -- (playerThreatBorderEnabled, profile-root global read as
    -- db.profile.playerThreatBorderEnabled, EllesmereUIUnitFrames.lua:100,:5637);
    -- promoted to the unitFrames root in Core.Convert since it is not a per-unit key.
    -- No other single frame has any threat equivalent, so they still warn.
    if ind.Threat then
        if unitKey == "player" then
            out.playerThreatBorderEnabled = ind.Threat.Enabled and true or false
        elseif ind.Threat.Enabled then
            warnings[#warnings + 1] = ("%s: threat indicator is enabled in Unhalted, but EllesmereUI has no threat indicator — skipped.")
                :format(unitKey)
        end
    end
    -- Resting/PvP/Totems only exist on the Unhalted player frame; none have an
    -- EllesmereUI equivalent.
    if ind.Resting and ind.Resting.Enabled then
        warnings[#warnings + 1] = ("%s: resting indicator is enabled in Unhalted, but EllesmereUI has no resting indicator — skipped.")
            :format(unitKey)
    end
    if ind.PvP and ind.PvP.Enabled then
        warnings[#warnings + 1] = ("%s: PvP indicator is enabled in Unhalted, but EllesmereUI has no PvP indicator — skipped.")
            :format(unitKey)
    end
    if ind.Totems and ind.Totems.Enabled then
        warnings[#warnings + 1] = ("%s: totem tracker is enabled in Unhalted, but EllesmereUI has no totem tracker — skipped.")
            :format(unitKey)
    end
end

--------------------------------------------------------------------------------
-- Single unit assembly
--------------------------------------------------------------------------------

local UNIT_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

local function mapUnit(unitKey, u, ctx, cache, warnings)
    local out = {}
    local f = u.Frame
    if f then
        if f.Width then out.frameWidth = f.Width end
        if f.Height then
            -- UUF renders the primary power bar INSIDE Frame.Height: the PowerBar
            -- anchors BOTTOMLEFT within the container and the health bar shrinks to
            -- fit above it (UnhaltedUnitFrames/Elements/PowerBar.lua:74-75,
            -- HealthBar.lua:49-50). EUI instead attaches its power bar OUTSIDE
            -- healthHeight (barHeight = healthHeight + powerH + cpAboveH,
            -- EllesmereUIUnitFrames.lua:3068-3101). So to keep the converted frame's
            -- total height == UUF's Frame.Height, subtract the power-bar height from
            -- healthHeight whenever this unit actually builds a power bar.
            -- Do NOT subtract SecondaryPowerBar height: the converter only ever emits
            -- classPowerPosition "top"/"bottom", neither of which adds frame height
            -- (only "above" does: EllesmereUIUnitFrames.lua:3090-3099).
            if FULL_ELEMENT_UNITS[unitKey] and u.PowerBar and u.PowerBar.Enabled then
                out.healthHeight = math.max(1, f.Height - num(u.PowerBar.Height, 0))
            else
                out.healthHeight = f.Height
            end
        end
    end
    mapHealth(u, out)

    if FULL_ELEMENT_UNITS[unitKey] then
        mapPower(u, out, unitKey, warnings)
    elseif u.PowerBar and u.PowerBar.Enabled then
        warnings[#warnings + 1] = ("%s: power bar is enabled in Unhalted, but EllesmereUI has no power bar on this frame — skipped.")
            :format(unitKey)
    end

    if unitKey == "player" then
        mapSecondaryPower(u, out)
        if u.AlternativePowerBar and u.AlternativePowerBar.Enabled then
            warnings[#warnings + 1] = "player: alternative power bar is enabled in Unhalted, but EllesmereUI has no alternative power bar — skipped."
        end
    end

    -- targettarget/focustarget never render a portrait in UUF, even when their
    -- (vestigial) Portrait.Enabled flag is true -- skip silently, don't warn
    -- (this vestigial default exists in every UUF profile).
    if PORTRAIT_UNITS[unitKey] then mapPortrait(u, out) end
    mapHighlight(u, out)

    if FULL_ELEMENT_UNITS[unitKey] then
        mapCastbar(u, out, unitKey, warnings)
    elseif u.CastBar and u.CastBar.Enabled then
        warnings[#warnings + 1] = ("%s: cast bar is enabled in Unhalted, but EllesmereUI has no cast bar on this frame — skipped.")
            :format(unitKey)
    end

    mapAbsorbs(u, out, unitKey, warnings)

    if FULL_ELEMENT_UNITS[unitKey] then
        local durText = u.Auras and u.Auras.AuraDuration
        if u.Auras then
            local isBoss = (unitKey == "boss")
            mapAuraGroup(u.Auras.Buffs, out, "buff", durText, isBoss)
            mapAuraGroup(u.Auras.Debuffs, out, "debuff", durText, isBoss)
            if u.Auras.Debuffs and u.Auras.Debuffs.OnlyShowPlayer ~= nil then
                out.onlyPlayerDebuffs = u.Auras.Debuffs.OnlyShowPlayer and true or false
            end
            if u.Auras.Buffs and u.Auras.Buffs.OnlyShowPlayer ~= nil then
                out.onlyPlayerBuffs = u.Auras.Buffs.OnlyShowPlayer and true or false
            end
            if isBoss then
                -- EllesmereUI's boss frame defaults simpleDebuffs="left", and whenever
                -- it isn't "none" the debuff container builder force-overrides
                -- debuffAnchor/Growth/Size/Offset with a fixed left-column layout --
                -- silently discarding the debuff layout mapped above (and showing a
                -- column even if Unhalted's boss debuffs were disabled). Opt out.
                out.simpleDebuffs = "none"
            end
        end
    elseif u.Auras then
        if u.Auras.Buffs and u.Auras.Buffs.Enabled then
            warnings[#warnings + 1] = ("%s: buffs are enabled in Unhalted, but EllesmereUI has no aura display on this frame — skipped.")
                :format(unitKey)
        end
        if u.Auras.Debuffs and u.Auras.Debuffs.Enabled then
            warnings[#warnings + 1] = ("%s: debuffs are enabled in Unhalted, but EllesmereUI has no aura display on this frame — skipped.")
                :format(unitKey)
        end
    end

    mapText(u, out, unitKey == "boss", warnings, unitKey, ctx)
    mapIndicators(u, out, unitKey, warnings)

    -- Texture (from General, applied per unit)
    if ctx._texture then out.healthBarTexture = ctx._texture end

    -- Boss range dimming. Unhalted's range fade is a PROFILE-GLOBAL setting
    -- (General.Range), applied uniformly to non-player frames incl. boss via
    -- Elements/Range.lua -- Units.boss never has a Range table of its own.
    if unitKey == "boss" then
        local range = ctx._general and ctx._general.Range
        if type(range) == "table" and range.Enabled and type(range.OutOfRange) == "number" then
            out.oorAlpha = range.OutOfRange
        end
        -- Boss stack direction: UUF's boss GrowthDirection is a plain UP/DOWN
        -- dropdown (direct semantics, unlike raid's edge-token pair -- see
        -- parseGroupGrowth) that AnchorUtil.VerticalLayout consumes by reversing
        -- the frame list when it's "UP" (UnhaltedUnitFrames/Core/UnitFrame.lua:84-99).
        -- EUI's equivalent is boss.bossStackDirection ("up"/"down",
        -- EllesmereUIUnitFrames.lua:8542-8570).
        out.bossStackDirection = (tostring(f and f.GrowthDirection or ""):upper() == "UP") and "up" or "down"
    end

    return out
end

--------------------------------------------------------------------------------
-- Raid / Party (best-effort structural)
--------------------------------------------------------------------------------

-- Unhalted's raid GrowthDirection token pair is "<edge>_<groupAxis>" where the
-- FIRST token names the STARTING EDGE units anchor from, not the flow direction --
-- the actual unit-axis flow is the OPPOSITE of that token. Evidence:
--  - UUF GUI labels (UnhaltedUnitFrames/Core/Config/GUI.lua:89-100): "RIGHT_DOWN" =
--    "Right to Left, then Down"; "UP_RIGHT" = "Top to Bottom, then Right".
--  - UUF layout (UnhaltedUnitFrames/Core/GroupFrames.lua:484-487): unitGrowth ==
--    "RIGHT" -> secure-header point="RIGHT", xOffset=-spacing -> each button
--    anchors its RIGHT to the previous button's LEFT -> units flow LEFTWARD.
--  - EUI is direct (EllesmereUIRaidFrames.lua:8166-8174): unitGrowth == "RIGHT" ->
--    hdrPoint="LEFT", xOff=+cs -> units flow RIGHTWARD.
-- So the unit-axis token must be INVERTED when carried over to EUI's unitGrowth.
-- The SECOND (group-axis) token is direct on both sides (GroupFrames.lua:~511-517;
-- EUI colAnchor 8177-8190) -- never inverted.
local INVERT_AXIS = { UP = "DOWN", DOWN = "UP", LEFT = "RIGHT", RIGHT = "LEFT" }
local GROUP_AXIS_VALID = { UP = true, DOWN = true, LEFT = true, RIGHT = true }
local function parseGroupGrowth(dir)
    dir = tostring(dir or ""):upper()
    local unitTok, groupTok = dir:match("^(%a+)_(%a+)$")
    if not unitTok then
        -- UUF's own fallback for an unmatched value (GroupFrames.lua:484 defaults
        -- to RIGHT_DOWN).
        unitTok, groupTok = "RIGHT", "DOWN"
    end
    local unit = INVERT_AXIS[unitTok] or "DOWN"
    local group = GROUP_AXIS_VALID[groupTok] and groupTok or "DOWN"
    return unit, group
end

-- Normalize an Unhalted RoleOrder list to EllesmereUI's role tokens. EllesmereUI
-- feeds these verbatim to the secure header's groupingOrder, where DPS MUST be
-- spelled "DAMAGER" (Blizzard's ASSIGNEDROLE value), so translate any DPS spelling.
local ROLE_TOKEN = {
    TANK = "TANK", HEALER = "HEALER", HEAL = "HEALER",
    DAMAGER = "DAMAGER", DAMAGE = "DAMAGER", DPS = "DAMAGER",
}
local function roleOrderList(ro)
    if type(ro) ~= "table" then return nil end
    local out = {}
    for i = 1, #ro do
        local t = ROLE_TOKEN[tostring(ro[i]):upper()]
        if t then out[#out + 1] = t end
    end
    return (#out > 0) and out or nil
end

-- Shared appearance mappers. `p` is the key prefix ("" for raid base keys, or
-- "party_" for party overrides) and `sec` is a section-name set the caller uses to
-- flip partySyncSections; both are ignored for raid.
local function markSec(sec, name) if sec then sec[name] = true end end

-- UUF group Tags -> EUI raid health/name text keys. EUI group frames have
-- exactly THREE text regions (name, health%, heal-absorb -- no absorb-shield or
-- power text region), so anything recognised but not name/health has nowhere to
-- go and must warn rather than silently drop or misroute. `label` is "raid" or
-- "party", used only in warning text.
local function mapGroupText(tags, out, p, sec, warnings, label)
    if not tags then return end
    local slots = { tags.TagOne, tags.TagTwo, tags.TagThree, tags.TagFour, tags.TagFive }
    local nameDone, healthDone, statusDone = false, false, false
    local powerWarned = false
    for _, tag in ipairs(slots) do
        if type(tag) == "table" then
            local parsed = parseTag(tag.Tag)
            if parsed and parsed.mapped and parsed.power then
                -- Power tags (e.g. healer-mana [curpp:manapercent:healer]) are common
                -- in UUF group layouts but raid/party frames have no power text
                -- region at all -- previously dropped silently, contradicting this
                -- function's own contract (recognised-but-unmappable content warns).
                if not powerWarned then
                    powerWarned = true
                    warnings[#warnings + 1] = ("%s: power text tag (%s) has no EllesmereUI equivalent on raid/party frames — skipped.")
                        :format(label, tostring(tag.Tag))
                end
            elseif parsed and parsed.mapped then
                local L = tag.Layout or {}
                local isName = (parsed.content == "name" or parsed.content == "nametotarget")
                -- Genuine health-family content, per classifyToken: current HP
                -- (short), HP percent, or both combined. This is an INCLUSION list
                -- (not the old "anything but name/group" exclusion) so a token like
                -- [absorbs] (content "absorbshort") no longer falls through into the
                -- health text at the absorb tag's position/size.
                local isHealth = (parsed.content == "curhpshort" or parsed.content == "perhp"
                    or parsed.content == "both")
                if isName and not nameDone then
                    nameDone = true
                    out[p .. "namePosition"] = pos9(L[1])
                    if tag.FontSize then out[p .. "nameSize"] = tag.FontSize end
                    out[p .. "nameOffsetX"] = round(num(L[3], 0), 1)
                    out[p .. "nameOffsetY"] = round(num(L[4], 0), 1)
                    -- Name color: a ":colour" token draws class color (escape wins
                    -- over the tag's own Colour, mirroring UUF). A plain [name]
                    -- takes the tag's explicit Colour instead -- previously dropped,
                    -- so a custom-colored group name silently fell back to EUI's
                    -- default (class). Map it to EUI's "custom" mode + color.
                    if parsed.classColor then
                        out[p .. "nameColorMode"] = "class"
                    elseif tag.Colour then
                        out[p .. "nameColorMode"] = "custom"
                        out[p .. "nameCustomColor"] = col(tag.Colour)
                    end
                    markSec(sec, "textDisplay")
                elseif isHealth and not healthDone then
                    healthDone = true
                    out[p .. "healthTextMode"] = (parsed.content == "curhpshort" and "number")
                        or (parsed.content == "both" and "numberPercent") or "percent"
                    out[p .. "healthTextPosition"] = pos9(L[1])
                    if tag.FontSize then out[p .. "healthTextSize"] = tag.FontSize end
                    out[p .. "healthTextOffsetX"] = round(num(L[3], 0), 1)
                    out[p .. "healthTextOffsetY"] = round(num(L[4], 0), 1)
                    -- Health color: mirror the name branch (previously dropped
                    -- tag.Colour entirely).
                    if parsed.classColor then
                        out[p .. "healthTextColorMode"] = "class"
                    elseif tag.Colour then
                        out[p .. "healthTextColorMode"] = "custom"
                        out[p .. "healthTextCustomColor"] = col(tag.Colour)
                    end
                    markSec(sec, "textDisplay")
                elseif parsed.content == "status" and not statusDone then
                    -- oUF's built-in [status] tag (Dead/Ghost/Offline). EUI's raid/party
                    -- statusText* lives in the "indicators" sync section, NOT
                    -- textDisplay -- see EllesmereUIRaidFrames.lua's section registry.
                    statusDone = true
                    out[p .. "statusTextPosition"] = pos9(L[1])
                    if tag.FontSize then out[p .. "statusTextSize"] = tag.FontSize end
                    out[p .. "statusTextOffsetX"] = round(num(L[3], 0), 1)
                    out[p .. "statusTextOffsetY"] = round(num(L[4], 0), 1)
                    if tag.Colour then out[p .. "statusTextColor"] = col(tag.Colour) end
                    markSec(sec, "indicators")
                elseif parsed.content == "group" and p == "" then
                    -- [group] on RAID only: EUI's showGroupNumbers/groupNumberSize/
                    -- groupNumberColor/groupNumberOffsetX/Y are raid-only (no party_
                    -- override exists -- EllesmereUIRaidFrames.lua:633-639). The
                    -- anchor position itself is fixed in EUI (no groupNumberPosition
                    -- key); only the offsets carry over.
                    out.showGroupNumbers = true
                    if tag.FontSize then out.groupNumberSize = tag.FontSize end
                    if tag.Colour then out.groupNumberColor = col(tag.Colour) end
                    out.groupNumberOffsetX = round(num(L[3], 0), 1)
                    out.groupNumberOffsetY = round(num(L[4], 0), 1)
                elseif warnings then
                    if parsed.content == "absorbshort" then
                        warnings[#warnings + 1] = ("%s: absorb-shield text tag ([absorbs]) has no EllesmereUI equivalent on raid/party frames (absorb shields only render as a bar overlay, not text) — skipped.")
                            :format(label)
                    elseif parsed.content == "group" then
                        -- Party call (p == "party_"): group numbers are raid-only.
                        warnings[#warnings + 1] = ("%s: group-number text tag ([group]) has no EllesmereUI equivalent on raid/party frames — skipped.")
                            :format(label)
                    else
                        warnings[#warnings + 1] = ("%s: text tag %s has no EllesmereUI equivalent on raid/party frames — skipped.")
                            :format(label, tostring(parsed.raw or tag.Tag))
                    end
                end
            end
        end
    end
    if not statusDone then
        -- EUI defaults status text to visible (center); a UUF profile without a
        -- [status] tag never showed DEAD/OFFLINE text, so suppress it explicitly
        -- or the converted frames grow phantom status text nothing asked for.
        out[p .. "statusTextPosition"] = "none"
        markSec(sec, "indicators")
    end
end

-- UUF group Indicators -> EUI raid indicator keys (9-position enums).
local function mapGroupIndicators(ind, out, p, sec)
    if not ind then return end
    -- EllesmereUI anchors each indicator with SetPoint(pos, frame, pos, ...), so the
    -- 9-position enum is the FRAME edge the icon sits against -- Unhalted's relPoint
    -- (Layout[2]), not the icon's own point (Layout[1]). Using the point flips them.
    local rtm = ind.RaidTargetMarker
    if rtm then
        -- RaidTargetMarker.Enabled defaults true on both raid and party.
        out[p .. "showRaidMarker"] = rtm.Enabled ~= false
        local sz = rtm.Size or 16
        if rtm.Size then out[p .. "raidMarkerSize"] = rtm.Size end
        local L = rtm.Layout
        if L then
            out[p .. "raidMarkerPosition"] = pos9(L[2] or L[1])
            -- EllesmereUI's raid marker applies a 2px inward inset.
            out[p .. "raidMarkerOffsetX"], out[p .. "raidMarkerOffsetY"] = indicatorOffset(L, sz, 2)
        end
        markSec(sec, "indicators")
    end
    local mo = ind.Mouseover
    if mo then
        if mo.Enabled ~= nil then out[p .. "hoverBorderEnabled"] = mo.Enabled and true or false end
        if mo.Colour then out[p .. "hoverBorderColor"] = col(mo.Colour) end
        if mo.HighlightOpacity then out[p .. "hoverBorderAlpha"] = mo.HighlightOpacity end
        markSec(sec, "indicators")
    end
    local tgt = ind.Target
    if tgt then
        if tgt.Enabled ~= nil then out[p .. "targetBorderEnabled"] = tgt.Enabled and true or false end
        if tgt.Colour then out[p .. "targetBorderColor"] = col(tgt.Colour) end
        markSec(sec, "indicators")
    end
    -- Group threat border. EUI defaults its aggro border ON (threatBorderSize=2,
    -- "indicators" section, read as `s.threatBorderSize or 0`,
    -- EllesmereUIRaidFrames.lua:611,:4490) while UUF's group threat highlight
    -- defaults OFF -- without an explicit 0 write here, every converted profile
    -- would show an aggro border UUF's own setup never had.
    if type(ind.Threat) == "table" then
        out[p .. "threatBorderSize"] = ind.Threat.Enabled and 2 or 0
        markSec(sec, "indicators")
    end
    if ind.Role then
        -- Role.Texture: left unmapped -- no clean enum correspondence.
        if ind.Role.Enabled == false then out[p .. "roleIconStyle"] = "none" end
        if ind.Role.ShowTank ~= nil then out[p .. "showRoleForTank"] = ind.Role.ShowTank and true or false end
        if ind.Role.ShowHealer ~= nil then out[p .. "showRoleForHealer"] = ind.Role.ShowHealer and true or false end
        if ind.Role.ShowDamager ~= nil then out[p .. "showRoleForDPS"] = ind.Role.ShowDamager and true or false end
        local sz = ind.Role.Size or 12
        if ind.Role.Size then out[p .. "roleIconSize"] = ind.Role.Size end
        local L = ind.Role.Layout
        if L then
            out[p .. "roleIconPosition"] = pos9(L[2] or L[1])
            out[p .. "roleIconOffsetX"], out[p .. "roleIconOffsetY"] = indicatorOffset(L, sz, 0)
        end
        markSec(sec, "indicators")
    end
    local li = ind.LeaderAssistantIndicator
    if li then
        out[p .. "showLeaderIcon"] = li.Enabled and true or false
        local sz = li.Size or 14
        if li.Size then out[p .. "leaderIconSize"] = li.Size end
        local L = li.Layout
        if L then
            out[p .. "leaderIconPosition"] = pos9(L[2] or L[1])
            out[p .. "leaderIconOffsetX"], out[p .. "leaderIconOffsetY"] = indicatorOffset(L, sz, 0)
        end
        markSec(sec, "indicators")
    end
    -- ResurrectIndicator/Summon Size/Layout: NONE -- shared readyCheck region;
    -- leave. Their Enabled maps to the showIncomingRez/showSummonPending gates.
    local ri = ind.ResurrectIndicator
    if ri then
        out[p .. "showIncomingRez"] = ri.Enabled ~= false
        markSec(sec, "indicators")
    end
    local sm = ind.Summon
    if sm then
        out[p .. "showSummonPending"] = sm.Enabled ~= false
        markSec(sec, "indicators")
    end
    -- ReadyCheckIndicator maps to readyCheck* (2px inward inset, same as the raid
    -- marker).
    local rc = ind.ReadyCheckIndicator
    if rc then
        -- ReadyCheckIndicator.Enabled defaults true on both raid and party.
        out[p .. "showReadyCheck"] = rc.Enabled ~= false
        local sz = rc.Size or 20
        if rc.Size then out[p .. "readyCheckSize"] = rc.Size end
        local L = rc.Layout
        if L then
            out[p .. "readyCheckPosition"] = pos9(L[2] or L[1])
            out[p .. "readyCheckOffsetX"], out[p .. "readyCheckOffsetY"] = indicatorOffset(L, sz, 2)
        end
        markSec(sec, "indicators")
    end
end

-- UUF group HealPrediction -> EUI raid absorb / heal-prediction keys.
local function mapGroupAbsorbs(hp, out, p, sec)
    if not hp then return end
    local a = hp.Absorbs
    if a then
        out[p .. "absorbStyle"] = a.Enabled and (a.UseStripedTexture and "striped" or "clean") or "none"
        if a.Colour then out[p .. "absorbColor"] = col(a.Colour) end
        out[p .. "absorbEdgeMode"] = edgeMode(a.Position)
        if a.ShowOverAbsorb ~= nil then out[p .. "showOvershield"] = a.ShowOverAbsorb and true or false end
        markSec(sec, "absorbs")
    end
    local ha = hp.HealAbsorbs
    if ha then
        out[p .. "healAbsorbStyle"] = ha.Enabled and (ha.UseStripedTexture and "striped" or "clean") or "none"
        if ha.Colour then out[p .. "healAbsorbColor"] = col(ha.Colour) end
        out[p .. "healAbsorbEdgeMode"] = edgeMode(ha.Position)
        markSec(sec, "absorbs")
    end
    local ih = hp.IncomingHeal
    if ih and ih.Enabled then
        out[p .. "healPrediction"] = true
        if ih.Colour then out[p .. "healPredColor"] = col(ih.Colour) end
        markSec(sec, "healthBar")
    end
end

-- UUF group PowerBar -> EUI raid/party power-bar keys. showPowerBar is written for
-- parity with the options default set, but it is a DEAD key -- nothing reads it;
-- group power-bar visibility is governed solely by the powerShowFor* role flags
-- (EllesmereUIRaidFrames.lua:1228-1230, shown if ANY flag is true). OnlyShowHealers
-- maps to that gate: true -> healer-only, false -> all roles. When UUF disables the
-- bar entirely (Enabled == false), all three flags must be false too, or a
-- disabled UUF power bar still renders for healers on the EUI side.
local function mapGroupPower(pb, out, p, sec, warnings)
    if not pb then return end
    -- PowerBar.Enabled defaults true on both raid and party.
    local enabled = pb.Enabled ~= false
    out[p .. "showPowerBar"] = enabled
    if pb.Height then out[p .. "powerHeight"] = pb.Height end
    if not enabled then
        out[p .. "powerShowForHealer"] = false
        out[p .. "powerShowForTank"] = false
        out[p .. "powerShowForDPS"] = false
    else
        local healersOnly = pb.OnlyShowHealers and true or false
        out[p .. "powerShowForHealer"] = true
        out[p .. "powerShowForTank"] = not healersOnly
        out[p .. "powerShowForDPS"] = not healersOnly
    end
    out[p .. "powerBgPowerColored"] = pb.ColourBackgroundByType and true or false
    if pb.Background then out[p .. "powerBgColor"] = col(pb.Background) end
    out[p .. "smoothPowerBars"] = pb.Smooth and true or false
    if warnings and enabled and (pb.ColourByClass or (pb.ColourByType == false and pb.Foreground)) then
        warnings[#warnings + 1] = "party/raid power bars in EllesmereUI are always colored by power type — custom power bar color dropped."
    end
    markSec(sec, "powerBar")
end

-- UUF group PrivateAuras -> EUI raid/party pa* keys. pa* IS a party-syncable
-- section ("privateAuras", EllesmereUIRaidFrames.lua:10181-10184), but this
-- writes the base keys only: UUF's party/raid private-aura settings rarely
-- differ, raid wins when both exist (mapRaid runs first), and the party proxy
-- (:10226-10235) falls back to the base key for any unwritten party_ override
-- -- so base-only writes cover both frames. Hence no `p`/`sec` parameters.
local function mapGroupPrivateAuras(pa, out)
    if pa.Enabled == false then
        out.paPosition = "none"
        return
    end
    local L = pa.Layout or {}
    -- Mirrors mapGroupIndicators' relPoint convention: the FRAME edge the icon
    -- is anchored to is Layout[2] (relPoint), falling back to Layout[1].
    out.paPosition = pos9(L[2] or L[1])
    out.paOffsetX = round(num(L[3], 0), 1)
    out.paOffsetY = round(num(L[4], 0), 1)
    if pa.Size then out.paSize = pa.Size end
    if pa.Spacing then out.paSpacing = pa.Spacing end
    local growX = tostring(pa.GrowthX or ""):upper()
    if growX == "LEFT" or growX == "RIGHT" then out.paGrowDirection = growX end
    -- EUI defaults the countdown text OFF (paShowCountdown=false); UUF shows the
    -- cooldown countdown unless DisableCooldown is explicitly set.
    out.paShowCountdown = pa.DisableCooldown ~= true
end

local function mapRaid(raid, out, warnings)
    out = out or {}
    local f = raid.Frame or {}
    if f.Width then out.frameWidth = f.Width end
    if f.Height then out.frameHeight = f.Height end
    local hb = raid.HealthBar
    if hb then
        -- Raid HealthBar.ColourByClass defaults true; nil reads as class-colored.
        out.healthColorMode = (hb.ColourByClass ~= false) and "class" or "custom"
        if not hb.ColourByClass and hb.Foreground then out.customFillColor = col(hb.Foreground) end
        if hb.Background then out.customBgColor = col(hb.Background) end
        if hb.ForegroundOpacity then out.healthBarOpacity = round(hb.ForegroundOpacity * 100) end
        out.smoothBars = hb.Smooth and true or false
        out.bgClassColored = hb.ColourBackgroundByClass and true or false
        if hb.BackgroundOpacity then out.bgDarkness = round(hb.BackgroundOpacity * 100) end
        -- Raid's OWN dispel highlight (distinct from the player -> profile-root
        -- uf.dispelOverlay mapping above).
        if hb.DispelHighlight then
            local dh = hb.DispelHighlight
            if dh.Enabled == false then
                out.dispelOverlay = "none"
            else
                out.dispelOverlay = (tostring(dh.Style or "HEALTHBAR"):upper() == "GRADIENT") and "gradient" or "fill"
            end
        end
    end
    mapGroupPower(raid.PowerBar, out, "", nil, warnings)
    local ug, gg = parseGroupGrowth(f.GrowthDirection)
    out.unitGrowth, out.groupGrowth = ug, gg
    -- Unhalted's raid SortBy dropdown only offers GROUP/INDEX (ROLE is party/single-
    -- unit only -- UnhaltedUnitFrames/Core/Config/GUI.lua:794), and raid.Frame has no
    -- RoleOrder at all (that's party-only). EllesmereUI's raid layout is inherently
    -- group-structured, so either Unhalted raid option lands on EllesmereUI's "INDEX".
    if f.SortBy then out.sortMode = "INDEX" end
    -- Unhalted sorts strictly by role/group; EllesmereUI otherwise floats the local
    -- player to the top (showSelfFirst defaults true), breaking that order.
    out.showSelfFirst = false
    -- Frame spacing is Unhalted's Layout 5th element (gap between units).
    -- EllesmereUI defaults to -1 (1px overlap), so leaving it unset shows no gaps.
    local sp = f.Layout and f.Layout[5]
    if type(sp) == "number" then out.cellSpacing = sp; out.groupSpacing = sp end
    if type(f.Groups) == "table" then
        local vg = {}
        for i = 1, 8 do vg[i] = f.Groups[i] and true or false end
        out.visibleGroups = vg
    end
    local au = raid.Auras
    if au and au.Debuffs then
        local d = au.Debuffs
        if d.Size then out.debuffSize = d.Size end
        if d.Num then out.debuffCap = d.Num end
        out.debuffPosition = auraAnchor((d.Layout or {})[1], (d.Layout or {})[2])
        out.debuffGrowDirection = tostring(d.GrowthDirection or "LEFT"):upper()
        if d.Wrap then out.debuffPerRow = d.Wrap end
        if type(d.Count) == "table" then
            local c = d.Count
            local cl = c.Layout or {}
            out.debuffShowStacks = c.HideStacks ~= true
            if c.FontSize then out.debuffStacksTextSize = c.FontSize end
            if c.Colour then out.debuffStacksTextColor = col(c.Colour) end
            out.debuffStacksOffsetX = round(num(cl[3], 0), 1)
            out.debuffStacksOffsetY = round(num(cl[4], 0), 1)
        end
    end
    if au and au.Buffs then
        local b = au.Buffs
        local bl = b.Layout or {}
        -- bmDisplayMode has NO default entry, so it effectively stays "custom" and
        -- the Simple grid never renders (buffs fall back to default indicator
        -- presets in the wrong spot). Force "simple" to mirror Unhalted's icon row.
        out.bmDisplayMode = "simple"
        out.bmSimple = {
            showBuffs = b.Enabled and true or false,
            maxBuffs = b.Num,
            iconsPerRow = b.Wrap,
            size = b.Size,
            growDirection = tostring(b.GrowthDirection or "LEFT"):upper(),
            position = auraAnchor(bl[1], bl[2]),
            offsetX = round(num(bl[3], 0), 1),
            offsetY = round(num(bl[4], 0), 1),
        }
        if type(bl[5]) == "number" then out.bmSimple.spacing = bl[5] end
        -- Unhalted always draws aura duration text (its AuraDuration block), but
        -- bmSimple.showDurText defaults false, so the converted raid buff grid would
        -- show no timers. Enable it and carry the font size.
        out.bmSimple.showDurText = true
        local dur = au.AuraDuration
        if dur and dur.FontSize then out.bmSimple.durTextSize = dur.FontSize end
        -- Stack-count text (bmSimple's own showStacks/stacksTextColor/stacksTextSize/
        -- stacksOffsetX/Y -- verified against EllesmereUIRaidFrames.lua:744-748).
        if type(b.Count) == "table" then
            local c = b.Count
            local cl = c.Layout or {}
            out.bmSimple.showStacks = c.HideStacks ~= true
            if c.FontSize then out.bmSimple.stacksTextSize = c.FontSize end
            if c.Colour then out.bmSimple.stacksTextColor = col(c.Colour) end
            out.bmSimple.stacksOffsetX = round(num(cl[3], 0), 1)
            out.bmSimple.stacksOffsetY = round(num(cl[4], 0), 1)
        end
    end
    mapGroupText(raid.Tags, out, "", nil, warnings, "raid")
    mapGroupIndicators(raid.Indicators, out, "", nil)
    mapGroupAbsorbs(raid.HealPrediction, out, "", nil)
    if au and type(au.PrivateAuras) == "table" then
        mapGroupPrivateAuras(au.PrivateAuras, out)
    end
    -- Position (raid unlockPos supports arbitrary point/relPoint)
    local L = f.Layout
    if L and (not f.AnchorParent or f.AnchorParent == "UIParent") then
        out.unlockPos = { point = L[1], relPoint = L[2] or L[1], x = round(num(L[3], 0), 1), y = round(num(L[4], 0), 1) }
    else
        warnings[#warnings + 1] = "Raid frame position not resolved (container-anchored); using EllesmereUI default — reposition in Unlock mode."
    end
    return out
end

local function mapParty(party, out, warnings)
    out = out or {}
    local f = party.Frame or {}
    if f.Width then out.partyFrameWidth = f.Width end
    if f.Height then out.partyFrameHeight = f.Height end
    if f.SortBy then out.partySortMode = (tostring(f.SortBy):upper() == "ROLE") and "ROLE" or "INDEX" end
    -- Units.party.Frame.ShowPlayer (default false -- UnhaltedUnitFrames/Core/
    -- Defaults.lua:1718; when true UUF spawns an extra partyplayer frame,
    -- GroupFrames.lua:243-254) is the direct inverse of EUI's partyHideSelf (read
    -- at EllesmereUIRaidFrames.lua:10510, 10621, 15312).
    out.partyHideSelf = not f.ShowPlayer
    local pro = roleOrderList(f.RoleOrder)
    if pro then out.partyRoleOrder = pro end
    -- Honor Unhalted's role/group order instead of floating the player to the top
    -- (partyShowSelfFirst defaults true -> the local player would appear first).
    out.partyShowSelfFirst = false
    local dir = tostring(f.GrowthDirection or "DOWN"):upper()
    out.partyHorizontal = (dir:find("LEFT") or dir:find("RIGHT")) and (not dir:find("UP") and not dir:find("DOWN")) and true or false
    out.partyFlipGrowth = (dir:find("UP") or dir:find("LEFT")) and true or false
    local L = f.Layout
    if L and (not f.AnchorParent or f.AnchorParent == "UIParent") then
        out.partyUnlockPos = { point = L[1], relPoint = L[2] or L[1], x = round(num(L[3], 0), 1), y = round(num(L[4], 0), 1) }
    else
        warnings[#warnings + 1] = "Party frame position not resolved (anchored to another frame); using EllesmereUI default — reposition in Unlock mode."
    end
    -- Inter-frame spacing (Unhalted Layout 5th element); EllesmereUI default is -1.
    if L and type(L[5]) == "number" then out.partyCellSpacing = L[5] end
    -- Party appearance is written into party_<key> overrides; flip the matching
    -- partySyncSections so EllesmereUI reads them instead of the raid values.
    local sec = {}
    mapGroupText(party.Tags, out, "party_", sec, warnings, "party")
    mapGroupIndicators(party.Indicators, out, "party_", sec)
    mapGroupAbsorbs(party.HealPrediction, out, "party_", sec)
    mapGroupPower(party.PowerBar, out, "party_", sec, warnings)
    local phb = party.HealthBar
    if phb then
        if phb.ColourByClass ~= nil then
            out.party_healthColorMode = phb.ColourByClass and "class" or "custom"
            sec.healthBar = true
        end
        if not phb.ColourByClass and phb.Foreground then
            out.party_customFillColor = col(phb.Foreground)
            sec.healthBar = true
        end
        if phb.Background then
            out.party_customBgColor = col(phb.Background)
            sec.healthBar = true
        end
        if phb.ForegroundOpacity then
            out.party_healthBarOpacity = round(phb.ForegroundOpacity * 100)
            sec.healthBar = true
        end
        if phb.Smooth ~= nil then
            out.party_smoothBars = phb.Smooth and true or false
            sec.healthBar = true
        end
        if phb.ColourBackgroundByClass ~= nil then
            out.party_bgClassColored = phb.ColourBackgroundByClass and true or false
            sec.healthBar = true
        end
        if phb.BackgroundOpacity then
            out.party_bgDarkness = round(phb.BackgroundOpacity * 100)
            sec.healthBar = true
        end
        if phb.DispelHighlight then
            local dh = phb.DispelHighlight
            if dh.Enabled == false then
                out.party_dispelOverlay = "none"
            else
                out.party_dispelOverlay = (tostring(dh.Style or "HEALTHBAR"):upper() == "GRADIENT") and "gradient" or "fill"
            end
            sec.dispels = true
        end
    end
    -- Party debuffs: mapParty never read party.Auras.Debuffs at all before --
    -- follow mapRaid's raid.Auras.Debuffs mapping as the template, party_ prefixed.
    local pau = party.Auras
    if pau and pau.Debuffs then
        local d = pau.Debuffs
        if d.Size then out.party_debuffSize = d.Size; sec.debuffStyle = true end
        if d.Num then out.party_debuffCap = d.Num end
        local dl = d.Layout or {}
        out.party_debuffPosition = auraAnchor(dl[1], dl[2])
        out.party_debuffOffsetX = round(num(dl[3], 0), 1)
        out.party_debuffOffsetY = round(num(dl[4], 0), 1)
        out.party_debuffGrowDirection = tostring(d.GrowthDirection or "LEFT"):upper()
        if d.Wrap then out.party_debuffPerRow = d.Wrap end
        out.party_debuffWrapDirection = tostring(d.WrapDirection or "UP"):upper()
        sec.debuffDisplay = true
        if type(d.Count) == "table" then
            local c = d.Count
            local cl = c.Layout or {}
            out.party_debuffShowStacks = c.HideStacks ~= true
            if c.FontSize then out.party_debuffStacksTextSize = c.FontSize end
            if c.Colour then out.party_debuffStacksTextColor = col(c.Colour) end
            out.party_debuffStacksOffsetX = round(num(cl[3], 0), 1)
            out.party_debuffStacksOffsetY = round(num(cl[4], 0), 1)
            sec.debuffStyle = true
        end
    end
    -- Party buffs render via the SHARED bmSimple table (no party_ override
    -- exists). Only take over if the raid mapping above left bmSimple absent or
    -- disabled -- otherwise leave raid's mapping alone.
    if pau and pau.Buffs and pau.Buffs.Enabled then
        if not (out.bmSimple and out.bmSimple.showBuffs) then
            local b = pau.Buffs
            local bl = b.Layout or {}
            out.bmDisplayMode = "simple"
            out.bmSimple = {
                showBuffs = true,
                maxBuffs = b.Num,
                iconsPerRow = b.Wrap,
                size = b.Size,
                growDirection = tostring(b.GrowthDirection or "LEFT"):upper(),
                position = auraAnchor(bl[1], bl[2]),
                offsetX = round(num(bl[3], 0), 1),
                offsetY = round(num(bl[4], 0), 1),
            }
            if type(bl[5]) == "number" then out.bmSimple.spacing = bl[5] end
            out.bmSimple.showDurText = true
            local dur = pau.AuraDuration
            if dur and dur.FontSize then out.bmSimple.durTextSize = dur.FontSize end
            if type(b.Count) == "table" then
                local c = b.Count
                local cl = c.Layout or {}
                out.bmSimple.showStacks = c.HideStacks ~= true
                if c.FontSize then out.bmSimple.stacksTextSize = c.FontSize end
                if c.Colour then out.bmSimple.stacksTextColor = col(c.Colour) end
                out.bmSimple.stacksOffsetX = round(num(cl[3], 0), 1)
                out.bmSimple.stacksOffsetY = round(num(cl[4], 0), 1)
            end
            warnings[#warnings + 1] = "party: EllesmereUI party and raid frames share one buff display — applied the party buff settings to both."
        else
            -- Raid already claimed the shared bmSimple (mapRaid runs first in
            -- Core.Convert and set showBuffs). Raid still wins, but if the party's
            -- own buff layout differs (UUF's raid default Num=1/Wrap=1 vs party's
            -- Num=3/Wrap=3) the party frames silently show the raid layout -- warn.
            local b = pau.Buffs
            if b.Num ~= out.bmSimple.maxBuffs
                or b.Wrap ~= out.bmSimple.iconsPerRow
                or b.Size ~= out.bmSimple.size then
                warnings[#warnings + 1] = "party: EllesmereUI party and raid frames share one buff display — the raid buff layout was used (party's differing max buffs/icons per row were dropped). Adjust it under Raid Frames → Buffs if the party layout mattered more."
            end
        end
    end
    -- Private auras (pa*) are one SHARED key set with no party_ override -- raid
    -- wins if it already claimed them (mapRaid runs first in Core.Convert).
    if out.paPosition == nil and pau and type(pau.PrivateAuras) == "table" then
        mapGroupPrivateAuras(pau.PrivateAuras, out)
    end
    if next(sec) then
        out.partySyncSections = out.partySyncSections or {}
        for name in pairs(sec) do out.partySyncSections[name] = false end
    end
    return out
end

--------------------------------------------------------------------------------
-- Public entry point
--------------------------------------------------------------------------------

-- profile: decoded Unhalted profile { General=..., Units=... }
-- opts:    { single=bool, group=bool }
-- ctx:     position-resolution context (see above). Minimal: { uiWidth, uiHeight }.
-- returns: { unitFrames=<table|nil>, raidFrames=<table|nil>, warnings={...} }
function Core.Convert(profile, opts, ctx)
    opts = opts or { single = true, group = true }
    ctx = ctx or {}
    ctx.uiWidth = ctx.uiWidth or 1024
    ctx.uiHeight = ctx.uiHeight or 768
    local warnings = {}
    local result = { warnings = warnings }

    if type(profile) ~= "table" or type(profile.Units) ~= "table" then
        warnings[#warnings + 1] = "Invalid Unhalted profile (no Units table)."
        return result
    end

    -- Sparse / old-version hardening: when the caller supplies UUF's own default
    -- profile (ctx.uufDefaults = UUF:GetDefaultDB().profile), deep-fill any key
    -- missing from the import from defaults. Runs on a COPY so the caller's table
    -- is untouched, and before any mapping below reads the profile.
    if type(ctx.uufDefaults) == "table" then
        profile = deepFillCopy(profile, ctx.uufDefaults)
    end

    local units = profile.Units
    local general = profile.General or {}

    -- UI-scale mismatch warning. UUF forces UIParent scale on import; a profile
    -- built at a different scale lands its (current-UIParent-relative) positions
    -- offset after conversion. Only emitted when the live scale is known
    -- (ctx.currentUiScale) and differs meaningfully from the profile's.
    local uiScale = general.UIScale
    if type(uiScale) == "table" and uiScale.Enabled and type(uiScale.Scale) == "number"
        and type(ctx.currentUiScale) == "number"
        and math.abs(uiScale.Scale - ctx.currentUiScale) > 0.01 then
        warnings[#warnings + 1] = ("Profile was built for UI scale %.2f (current %.2f) — frame positions may be shifted; reposition in Unlock mode if needed.")
            :format(uiScale.Scale, ctx.currentUiScale)
    end
    -- Threaded through ctx (like ctx._texture below) so mapUnit's boss branch can
    -- read General.Range for range-fade dimming (see Boss range dimming, above).
    ctx._general = general

    -- Resolve a health-bar texture once (from General.Textures.Foreground). EUI
    -- reuses this one key for health, power and cast bars.
    local texKey
    local texName = general.Textures and general.Textures.Foreground
    if texName then
        local low = tostring(texName):lower()
        if EUI_HEALTH_TEXTURES[low] then
            texKey = low                      -- already an EUI built-in key
        elseif TEXTURE_MAP[low] then
            texKey = TEXTURE_MAP[low]          -- known name -> EUI built-in
        elseif UUF_BUNDLED_TEXTURES[low] then
            -- Bundled with Unhalted itself (Globals.lua:35-39), which this migration
            -- disables -- an "sm:" key would go white. Leave texKey nil so EllesmereUI
            -- keeps its own default bar texture (see the uf/rf emission below, both
            -- guarded by `if texKey`).
            warnings[#warnings + 1] = ("Health texture '%s' is bundled with Unhalted itself, which this migration disables — EllesmereUI's default bar texture is used instead; pick a similar texture in EllesmereUI's options if you want.")
                :format(tostring(texName))
        else
            texKey = "sm:" .. tostring(texName)  -- LibSharedMedia texture, by name
            warnings[#warnings + 1] = ("Health texture '%s' is used from LibSharedMedia — keep its source addon/pack installed or EllesmereUI shows a plain bar.")
                :format(tostring(texName))
        end
    end
    ctx._texture = texKey

    -- Fonts (profile-global; the wrapper puts result.fonts into payload.data.fonts).
    local fonts = general.Fonts
    if type(fonts) == "table" and fonts.Font then
        local flag = tostring(fonts.FontFlag or ""):upper()
        local outlineMode = "none"
        if flag:find("THICK") then outlineMode = "thick"
        elseif flag:find("OUTLINE") then outlineMode = "outline"
        elseif fonts.Shadow and fonts.Shadow.Enabled then outlineMode = "shadow" end
        result.fonts = { outlineMode = outlineMode }
        -- outlineMode (a stroke/outline flag) is independent of the font family, so
        -- it is always carried. Only the font family itself is dropped when it is
        -- bundled with Unhalted and EllesmereUI lacks it (Globals.lua:44-48): an
        -- "sm:" key would stop resolving once the disabled Unhalted addon unloads,
        -- so leave result.fonts.global unset and EllesmereUI keeps its default font.
        if UUF_BUNDLED_FONTS_EUI_LACKS[tostring(fonts.Font):lower()] then
            warnings[#warnings + 1] = ("Font '%s' is bundled with Unhalted itself, which this migration disables — EllesmereUI's default font is kept.")
                :format(tostring(fonts.Font))
        else
            result.fonts.global = fonts.Font
        end
    end

    if opts.single ~= false then
        local uf = { enabledFrames = {}, frameSource = {}, positions = {} }
        if texKey then uf.healthBarTexture = texKey end
        local cache = {}
        for _, unitKey in ipairs(UNIT_KEYS) do
            local u = units[unitKey]
            if type(u) == "table" then
                uf[unitKey] = mapUnit(unitKey, u, ctx, cache, warnings)
                local enabled = u.Enabled and true or false
                -- Frame ownership (mirrors the MSUF importer's ForceHideBlizzard
                -- rule): an ENABLED UUF frame owns the unit regardless of the flag;
                -- a DISABLED unit with ForceHideBlizzard explicitly false keeps the
                -- stock Blizzard frame; nil/true stays hidden. (u.Enabled is left as
                -- `and true or false` on purpose -- its UUF default varies per unit
                -- [targettarget/focustarget default false], so it can't be nil-widened.)
                local source
                if enabled then
                    source = "eui"
                elseif u.ForceHideBlizzard == false then
                    source = "blizzard"
                else
                    source = "hidden"
                end
                uf.frameSource[unitKey] = source
                -- ns.GetUnitFrameSource returns "hidden" the moment
                -- enabledFrames[unit]==false, BEFORE it consults frameSource
                -- (EllesmereUIUnitFrames.lua:2072). So a "blizzard" source only
                -- takes effect while enabledFrames stays truthy -- keep the legacy
                -- flag in sync exactly as ns.SetUnitFrameSource does
                -- (enabledFrames = source ~= "hidden").
                uf.enabledFrames[unitKey] = source ~= "hidden"
                uf.positions[unitKey] = select(1, resolvePosition(unitKey, units, ctx, cache, warnings))
                if unitKey == "boss" and u.Frame then
                    -- EUI chains boss2..boss5 TOPLEFT->TOPLEFT at a fixed distance
                    -- (db.profile.bossSpacing, module ROOT key, default 80 --
                    -- EllesmereUIUnitFrames.lua:8542-8570), while UUF's Layout[5] is
                    -- only the GAP between frames (AnchorUtil.VerticalLayout). With
                    -- healthHeight now = UUF f.Height MINUS the power-bar height (see
                    -- mapUnit above), the converted EUI boss frame's visual height is
                    -- healthHeight + pbHeight == f.Height, so the correct
                    -- frame-to-frame distance is just f.Height + the gap -- the
                    -- pbHeight term would now double-count the power bar.
                    local bf = u.Frame
                    local gap = num(bf.Layout and bf.Layout[5], 0)
                    uf.bossSpacing = round(num(bf.Height, 0) + gap)
                end
            end
        end

        -- Player threat border is a PROFILE-ROOT global on EllesmereUI
        -- (db.profile.playerThreatBorderEnabled, EllesmereUIUnitFrames.lua:100,:5637),
        -- NOT a per-unit key -- mapIndicators writes it onto the player table, so
        -- promote it to the unitFrames root here (and clear the per-unit copy, which
        -- nothing reads).
        if uf.player and uf.player.playerThreatBorderEnabled ~= nil then
            uf.playerThreatBorderEnabled = uf.player.playerThreatBorderEnabled
            uf.player.playerThreatBorderEnabled = nil
        end

        -- Dispel overlay is a PROFILE-ROOT setting on EllesmereUI (mirrors Raid
        -- Frames), sourced from the Unhalted player's HealthBar.DispelHighlight.
        local playerHb = units.player and units.player.HealthBar
        local dh = playerHb and playerHb.DispelHighlight
        if dh and dh.Enabled then
            local style = tostring(dh.Style or "HEALTHBAR"):upper()
            uf.dispelOverlay = (style == "GRADIENT") and "gradient" or "fill"
        end

        -- Custom abbreviations (1-decimal K/M/B, e.g. "79.7K") is EUI's
        -- showDecimalOnText, a profile-root setting mirroring UUF's General.
        if general.UseCustomAbbreviations then
            uf.showDecimalOnText = true
            uf.showDecimalBoss2 = false  -- UUF has no boss-specific 2-decimal option
            warnings[#warnings + 1] = "Custom abbreviations enabled in Unhalted — EllesmereUI's matching option also adds a decimal to health-percent text (e.g. 87.3% vs 87%)."
        end

        -- Reaction colors (General.Colours.Reaction) -> EllesmereUI's profile-root
        -- enemyColors {hostile, neutral, friendly, tapped}. Hostile = index 2,
        -- Neutral = index 4, Friendly = index 5 (EllesmereUIUnitFrames.lua:8360-8362
        -- applies these uniformly to reactions 1-3 / 4 / 5-8). Status.Tapped maps to
        -- the separate "tapped" key.
        local colours = general.Colours
        local reaction = colours and colours.Reaction
        local status = colours and colours.Status
        if (reaction and (reaction[2] or reaction[4] or reaction[5])) or (status and status.Tapped) then
            uf.enemyColors = {}
            if reaction and reaction[2] then uf.enemyColors.hostile = col(reaction[2]) end
            if reaction and reaction[4] then uf.enemyColors.neutral = col(reaction[4]) end
            if reaction and reaction[5] then uf.enemyColors.friendly = col(reaction[5]) end
            if status and status.Tapped then uf.enemyColors.tapped = col(status.Tapped) end
        end

        result.unitFrames = uf
    end

    if opts.group ~= false then
        local rf
        if type(units.raid) == "table" then rf = mapRaid(units.raid, nil, warnings) end
        if type(units.party) == "table" then rf = mapParty(units.party, rf, warnings) end
        -- EUI has no group-type enable key (showWhenGroup/showWhenRaid are dead) --
        -- its group frames always show while you're in a party/raid.
        if (type(units.raid) == "table" and units.raid.Enabled == false)
            or (type(units.party) == "table" and units.party.Enabled == false) then
            warnings[#warnings + 1] = "party/raid frames are disabled in Unhalted, but EllesmereUI always shows its group frames when you are in a party/raid — disable them manually in the Raid Frames options if unwanted."
        end
        -- EllesmereUIRaidFrames keeps its OWN healthBarTexture (default "atrocity")
        -- independent of the unit-frames addon, so carry the texture across or the
        -- party/raid bars keep the default texture instead of the converted one.
        if rf and texKey then rf.healthBarTexture = texKey end

        -- Out-of-range fade (General.Range, profile-global -- mirrors the boss
        -- oorAlpha mapping in mapUnit above). EUI's rangeTooltip-section oorAlpha
        -- defaults to 0.4; an UUF profile with fade disabled never dimmed
        -- out-of-range units at all, so that must land as 1 (no fade), not EUI's
        -- default.
        if rf and type(general.Range) == "table" then
            local range = general.Range
            if range.Enabled == false then
                rf.oorAlpha = 1
            elseif type(range.OutOfRange) == "number" then
                local inRange = (type(range.InRange) == "number" and range.InRange > 0) and range.InRange or 1
                local ratio = range.OutOfRange / inRange
                if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
                rf.oorAlpha = round(ratio, 2)
            end
        end

        -- Dispel type colors (General.Colours.Dispel). Base keys only -- the party
        -- proxy (EllesmereUIRaidFrames.lua:10226-10235) falls back to the
        -- unprefixed base key when a party_ key is nil, so a base-only write is
        -- always safe even for a custom party section.
        if rf and general.Colours and type(general.Colours.Dispel) == "table" then
            local dispel = general.Colours.Dispel
            if dispel.Magic then rf.dispelColorMagic = col(dispel.Magic) end
            if dispel.Curse then rf.dispelColorCurse = col(dispel.Curse) end
            if dispel.Disease then rf.dispelColorDisease = col(dispel.Disease) end
            if dispel.Poison then rf.dispelColorPoison = col(dispel.Poison) end
            if dispel.Bleed then rf.dispelColorBleed = col(dispel.Bleed) end
        end

        if rf then result.raidFrames = rf end
        if type(units.raid) ~= "table" and type(units.party) ~= "table" then
            warnings[#warnings + 1] = "No party/raid data found in the Unhalted profile."
        end

        -- units.raid.augmentation is a separate sub-roster (UnhaltedUnitFrames/
        -- Core/Defaults.lua:2201) with no EllesmereUI equivalent.
        local aug = type(units.raid) == "table" and units.raid.augmentation
        if type(aug) == "table" and (aug.Enabled or (type(aug.Names) == "string" and aug.Names:match("%S"))) then
            warnings[#warnings + 1] = "raid: the augmentation sub-roster has no EllesmereUI equivalent — skipped."
        end
    end

    return result
end

Core.parseTag = parseTag
Core.UNIT_KEYS = UNIT_KEYS

ns.ConverterCore = Core
return Core
