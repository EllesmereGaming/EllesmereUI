-- Stub harness: Nameplates, Cast Bar X Offset (EUI_Nameplates_Layout.lua and the Display page).
-- The cog on Cast Bar Y Offset holds an X Offset slider (-50 to 50, 0 by default) that moves the
-- enemy cast bar left or right under the health bar; the spell icon follows in every icon mode.
-- Rules checked here:
--   - unset or 0: every anchor is what it was without the setting;
--   - a set offset is snapped to whole physical pixels at the plate's own scale, and the full
--     sized icon's top corner (hung from the health bar) moves with its bottom corner (hung from
--     the cast bar);
--   - the offset stands down only while Wrap Around Castbar can DRAW: the setting on and a border
--     to wrap (Basic or Custom). Under Blizzard Style, Classic WoW UI or Border None a saved wrap
--     holds nothing back, and the cog is live;
--   - a setting that only moves the cast bar re-places the cast bars (ns.NP_RelayoutCastBars:
--     each live plate at its cast bar's own height, so a focus plate keeps its Focus Cast Height;
--     pooled plates at their next spawn, through the appearance generation) and never runs the
--     full nameplate refresh. Cast Bar Y Offset, the wrap toggle and the Border control use it.
-- Driven here: the real Nameplates main and Layout files loaded whole, and the real setters of
-- the options rows, over recording frames.
--   lua .tools/tests/test_np_cast_bar_offset_x.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

-------------------------------------------------------------------------------
-- The real main and Layout files, loaded whole
-------------------------------------------------------------------------------
local function StubFrame()
    return setmetatable({}, { __index = function() return function() end end })
end
local function NewFanOut(list)
    local has, cur = false, nil
    setmetatable(list, { __newindex = function(l, i, fn)
        rawset(l, i, fn)
        if has then fn(cur) end
    end })
    return function(v)
        has, cur = true, v
        for i = 1, #list do list[i](v) end
    end
end
local function NewInternals(ns, field, t, setters)
    for setter, listName in pairs(setters or {}) do t[setter] = NewFanOut(t[listName]) end
    t.broken = false
    ns[field] = setmetatable(t, { __index = function(_, k)
        error("ns." .. field .. " has no entry " .. tostring(k), 2)
    end })
    return ns[field]
end

local PERFECT = 768 / 1080
local env = setmetatable({}, { __index = _G })
env._G = env
env.CreateFrame = StubFrame
env.EllesmereUI = {
    IS_FOREVER = false, _ModuleNS = {}, NewInternals = NewInternals,
    NewCombatQueue = function() return {} end, _Pool = { CreateFrame = StubFrame },
    Glows = { FlatKeys = {}, PANDEMIC_BORDER = 101, STEALABLE_BORDER = 102,
        MakeView = function(list) return { list = list, toShared = {} } end },
    AbbreviateValue = function(v) return tostring(v) end, IsZeroValue = function(v) return v == 0 end,
    UnitNameFormat = function(m) return m end, OwnSurnameHidden = function() return false end,
    ShortName = function(n) return n end, ApplyModuleFontFamily = function() end,
    SetFontFamily = function() end, SetFontObjectFace = function() end,
    SnapshotFontObject = function() end, RestoreFontObject = function() end,
    Lite = { NewAddon = function() return {} end },
    PP = { perfect = PERFECT, mult = 1 },
    AuraKit = { OnOffensiveDispelChange = function() end, OffensiveDispelTypes = function() end },
    TextTags = { Bind = function() return {} end, UNIT = { keys = { name = { width = 60 } } } },
}
local ns = {}
do
    local main = assert(loadstring(ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua"), "=EllesmereUINameplates.lua"))
    setfenv(main, env)
    main("EllesmereUINameplates", ns)
    local layout = assert(loadstring(ReadSource("EllesmereUINameplates/EUI_Nameplates_Layout.lua"), "=EUI_Nameplates_Layout.lua"))
    setfenv(layout, env)
    layout("EllesmereUINameplates", ns)
    assert(ns._npInternals.broken == false, "the Layout file did not load to its end")
end
local defaults, SetProfile = ns.defaults, ns._npInternals.SetProfile

-- The look (the Styles file is not loaded): "eui", "blizzard" or "classic".
local look = "eui"
ns.NP_Blizz = function() return look ~= "eui" end
ns.NP_Classic = function() return look == "classic" end
ns.NP_ClassicCastLayout = function(w) return 3, w + 2, -4 end
ns.NP_ApplyClassicCastArt = function() end
ns.NP_CLASSIC = { icon = 1 }
ns.NP_ClassicIconOffset = function() return -8, -2 end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end
-- A profile: the module's defaults with `saved` over them (a "nil" string unsets a key).
local function Profile(saved)
    local prof = Copy(defaults)
    for k, v in pairs(saved or {}) do
        if v == "nil" then prof[k] = nil else prof[k] = v end
    end
    SetProfile(prof)
    return prof
end

local function Rec(es)
    local r = { pts = {} }
    function r:ClearAllPoints() self.pts = {} end
    function r:SetPoint(pt, rel, relPt, x, y) self.pts[#self.pts + 1] = { pt, rel, relPt, x, y } end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:GetHeight() return self.h end
    function r:SetScale(s) self.scale = s end
    function r:GetEffectiveScale() return es end
    function r:IsShown() return false end
    return r
end
local function NewPlate(es)
    local plate = Rec(es)
    plate.health = { name = "health" }
    plate.cast = Rec(es)
    plate.cast.name = "cast"
    plate.castIconFrame = Rec(es)
    return plate
end
local function Lay(es, castH)
    local plate = NewPlate(es)
    ns.LayoutCastBar(plate, 150, castH or 17)
    ns.LayoutCastIcon(plate, castH or 17)
    return plate
end
local function Fmt(p)
    local t = {}
    for i, a in ipairs(p) do
        t[i] = string.format("%s>%s.%s(%.6f,%.6f)", a[1], type(a[2]) == "table" and (a[2].name or "?") or "?", a[3], a[4], a[5])
    end
    return table.concat(t, " ")
end
local function Snap(v, es)
    local onePx = PERFECT / es
    return math.floor(v / onePx + 0.5) * onePx
end

-------------------------------------------------------------------------------
-- 1. the default: nothing moves
-------------------------------------------------------------------------------
check(defaults.castBarOffsetX == 0, "the default Cast Bar X Offset is not 0")
Profile()
check(ns.GetCastBarOffsetX() == 0, "an untouched profile has an X offset")
Profile({ castBarOffsetX = "nil" })
check(ns.GetCastBarOffsetX() == 0, "an unset key does not read as 0")

-------------------------------------------------------------------------------
-- 2. when Wrap Around Castbar can draw, and what that does to the offset
-------------------------------------------------------------------------------
do
    local BORDERS = {
        none = { showBorder = false, customBorderEnabled = false },
        basic = { showBorder = true, customBorderEnabled = false },
        custom = { showBorder = false, customBorderEnabled = true },
    }
    for _, lk in ipairs({ "eui", "blizzard", "classic" }) do
        for border, keys in pairs(BORDERS) do
            for _, wrap in ipairs({ false, true }) do
                look = lk
                local saved = { wrapBorderCastbar = wrap, castBarOffsetX = 12 }
                for k, v in pairs(keys) do saved[k] = v end
                Profile(saved)
                local draws = wrap and lk == "eui" and border ~= "none"
                local tag = lk .. ", border " .. border .. ", wrap " .. tostring(wrap)
                check(ns.NP_WrapCanDraw() == draws, tag .. ": the wrap " .. (draws and "can draw but reads as unable" or "cannot draw but reads as able"))
                check(ns.GetCastBarOffsetX() == (draws and 0 or 12), tag .. ": the offset reads " .. tostring(ns.GetCastBarOffsetX()))
            end
        end
    end
    look = "eui"
end

-------------------------------------------------------------------------------
-- 3. the cast bar and its icon, in every icon mode
-------------------------------------------------------------------------------
do
    local MODES = {
        { name = "icon left" }, { name = "icon right", castIconOnRight = true },
        { name = "icon in the bar, left", castbarIconInWidth = true },
        { name = "icon in the bar, right", castbarIconInWidth = true, castIconOnRight = true },
        { name = "full size left", castIconFullSize = true },
        { name = "full size right", castIconFullSize = true, castIconOnRight = true },
        { name = "no icon", showCastIcon = false },
    }
    for _, mode in ipairs(MODES) do
        for _, es in ipairs({ 0.71, 1, 1.3333 }) do
            for _, oy in ipairs({ 0, 5, -3.3 }) do
                for _, ixo in ipairs({ 0, 4 }) do
                    local base = { castBarOffsetY = oy, castIconOffsetX = ixo }
                    for k, v in pairs(mode) do if k ~= "name" then base[k] = v end end
                    local tag = mode.name .. ", scale " .. es .. ", y " .. oy .. ", icon x " .. ixo
                    -- without the setting
                    base.castBarOffsetX = "nil"
                    Profile(base)
                    local b = Lay(es)
                    base.castBarOffsetX = 0
                    Profile(base)
                    local z = Lay(es)
                    check(Fmt(z.cast.pts) == Fmt(b.cast.pts) and Fmt(z.castIconFrame.pts) == Fmt(b.castIconFrame.pts) and z._castDrop == b._castDrop,
                        tag .. ": an offset of 0 moves something")
                    for _, ox in ipairs({ 7, -12.4, 50 }) do
                        base.castBarOffsetX = ox
                        base.wrapBorderCastbar = false
                        Profile(base)
                        local h = Lay(es)
                        local want = Snap(ox, es)
                        local bp, hp = b.cast.pts[1], h.cast.pts[1]
                        check(#h.cast.pts == 1 and hp[1] == "TOPLEFT" and hp[2] == h.health and hp[3] == "BOTTOMLEFT", tag .. ": the cast bar is not hung from the health bar's bottom left")
                        check(math.abs(hp[4] - (bp[4] + want)) < 1e-9, tag .. ", x " .. ox .. ": the cast bar moved " .. tostring(hp[4] - bp[4]) .. ", not " .. want)
                        local steps = (hp[4] - bp[4]) / (PERFECT / es)
                        check(math.abs(steps - math.floor(steps + 0.5)) < 1e-6, tag .. ", x " .. ox .. ": the offset is not a whole number of physical pixels")
                        check(hp[5] == bp[5] and h.cast.w == b.cast.w and h.cast.h == b.cast.h and h._castDrop == b._castDrop, tag .. ", x " .. ox .. ": the offset changed the bar's height, size or drop")
                        check(h._castOffsetX == want, tag .. ", x " .. ox .. ": the plate does not carry the offset for its icon")
                        -- the full sized icon: its top corner (off the health bar) lands on the same x as
                        -- its bottom corner (off the cast bar)
                        if mode.castIconFullSize then
                            local top, bottom = h.castIconFrame.pts[1], h.castIconFrame.pts[2]
                            local castLeft, castRight = hp[4], hp[4] + h.cast.w
                            local topX, bottomX
                            if mode.castIconOnRight then
                                topX, bottomX = 150 + top[4], castRight + bottom[4]
                            else
                                topX, bottomX = top[4], castLeft + bottom[4]
                            end
                            check(top[2] == h.health and bottom[2] == h.cast and math.abs(topX - bottomX) < 1e-9, tag .. ", x " .. ox .. ": the full sized icon is skewed (" .. topX .. " against " .. bottomX .. ")")
                        else
                            check(Fmt(h.castIconFrame.pts) == Fmt(b.castIconFrame.pts), tag .. ", x " .. ox .. ": an icon hung from the cast bar was re-anchored")
                        end
                        -- a wrap that draws holds the bar in place
                        base.wrapBorderCastbar = true
                        base.showBorder = true
                        Profile(base)
                        local w = Lay(es)
                        check(Fmt(w.cast.pts) == Fmt(b.cast.pts) and Fmt(w.castIconFrame.pts) == Fmt(b.castIconFrame.pts), tag .. ", x " .. ox .. ": the bar moves under a drawn wrap")
                        -- a saved wrap with no border to wrap does not
                        base.showBorder = false
                        Profile(base)
                        local nb = Lay(es)
                        check(Fmt(nb.cast.pts) == Fmt(h.cast.pts), tag .. ", x " .. ox .. ": a wrap that cannot draw (Border None) holds the bar back")
                        base.showBorder = "nil"
                        base.wrapBorderCastbar = "nil"
                    end
                end
            end
        end
    end
    -- the stock looks: a saved wrap holds nothing back there
    for _, lk in ipairs({ "blizzard", "classic" }) do
        look = lk
        Profile({ wrapBorderCastbar = true, showBorder = true, castBarOffsetX = "nil" })
        local b = Lay(1)
        Profile({ wrapBorderCastbar = true, showBorder = true, castBarOffsetX = 9 })
        local h = Lay(1)
        check(math.abs(h.cast.pts[1][4] - (b.cast.pts[1][4] + Snap(9, 1))) < 1e-9, lk .. ": a saved wrap holds the cast bar back although nothing can wrap")
    end
    look = "eui"
end

-------------------------------------------------------------------------------
-- 4. ns.NP_RelayoutCastBars: every live plate at its own cast height
-------------------------------------------------------------------------------
do
    -- a full sized icon: its top corner hangs from the health bar, so it only follows a new
    -- offset when the icon is laid out again
    Profile({ castBarOffsetX = 10, castIconFullSize = true })
    local a, focus, c = NewPlate(1), NewPlate(1), NewPlate(1)
    ns.LayoutCastBar(a, 150, 17); ns.LayoutCastIcon(a, 17)
    ns.LayoutCastBar(focus, 150, 26); ns.LayoutCastIcon(focus, 26)
    ns.LayoutCastBar(c, 150, 17); ns.LayoutCastIcon(c, 17)
    for k in pairs(ns.plates) do ns.plates[k] = nil end
    ns.plates.nameplate1, ns.plates.nameplate2, ns.plates.nameplate3 = a, focus, c
    local pooled = NewPlate(1)
    ns.LayoutCastBar(pooled, 150, 17)
    local before = Fmt(pooled.cast.pts)
    local gen = ns._npAppearanceGen or 0
    local full = 0
    ns.RefreshAllSettings = function() full = full + 1 end
    Profile({ castBarOffsetX = 30, castIconFullSize = true })
    ns.NP_RelayoutCastBars()
    local want = Snap(30, 1)
    check(a.cast.pts[1][4] == want and c.cast.pts[1][4] == want and focus.cast.pts[1][4] == want, "a live plate's cast bar was not placed again")
    check(a.cast.h == 17 and c.cast.h == 17, "a plate's cast height changed")
    check(focus.cast.h == 26, "the focus plate lost its own cast height (" .. tostring(focus.cast.h) .. ")")
    -- each live plate now equals a fresh layout at its own cast height
    local ref17, ref26 = Lay(1, 17), Lay(1, 26)
    check(Fmt(a.castIconFrame.pts) == Fmt(ref17.castIconFrame.pts) and a.castIconFrame.w == ref17.castIconFrame.w,
        "a plate's cast icon was not laid out again (its top corner kept the old offset)")
    check(Fmt(focus.castIconFrame.pts) == Fmt(ref26.castIconFrame.pts) and focus.castIconFrame.w == ref26.castIconFrame.w and ref26.castIconFrame.w ~= ref17.castIconFrame.w,
        "the focus plate's cast icon was not laid out at its own cast height")
    check(Fmt(pooled.cast.pts) == before, "a plate outside the live set was touched")
    check((ns._npAppearanceGen or 0) == gen + 1, "pooled plates are not told to take the new place at their next spawn")
    check(full == 0, "the full nameplate refresh ran")
    for k in pairs(ns.plates) do ns.plates[k] = nil end
end

-------------------------------------------------------------------------------
-- 5. the options rows: their real setters
-------------------------------------------------------------------------------
do
    local BARS = ReadSource("EllesmereUIOptions/Nameplates_Options/DisplayBars_Options.lua")
    local LAYOUT = ReadSource("EllesmereUIOptions/Nameplates_Options/DisplayLayout_Options.lua")
    local PREVIEW = ReadSource("EllesmereUIOptions/Nameplates_Options/NameplatePreview_Options.lua")
    local db = {}
    local calls = {}
    local function Count(name) return function() calls[name] = (calls[name] or 0) + 1 end end
    local canDraw = false
    local ons = {
        NP_RelayoutCastBars = Count("relayout"), RefreshAllSettings = Count("full"), RefreshBorder = Count("border"),
        RefreshBorderColor = Count("borderColor"), RefreshCastBorder = Count("castBorder"), ApplyBorderWrapToAll = Count("wrapAll"),
        NP_WrapCanDraw = function() return canDraw end,
        GetHealthBarWidth = function() return 150 end, GetCastBarHeight = function() return 17 end,
        LayoutCastBar = Count("layoutBar"), LayoutCastIcon = Count("layoutIcon"),
    }
    local function DB() return db end
    local function DBVal(k)
        local v = db[k]
        if v == nil then v = defaults[k] end
        return v
    end
    local EUI = { L = function(s) return s end }
    function EUI:RefreshPage() calls.page = (calls.page or 0) + 1 end
    local cog
    EUI.BuildInlineCog = function(_, opts) cog = opts end
    local HEAD = "local EllesmereUI, ns, DB, DBVal, defaults, UpdatePreview, castTimerRow, plates, pairs = ...\n"
    local args = { EUI, ons, DB, DBVal, defaults, Count("preview"), { _rightRegion = { _control = {} } }, {}, pairs }
    local function Reset() calls = {} end

    -- the X Offset cog on Cast Bar Y Offset
    assert(loadstring(HEAD .. Cut(BARS, "        -- Inline cog on Cast Bar Y Offset (right region) for X Offset", "    _, h = W:Spacer(parent, y, 20);  y = y - h\n\n    -----------------------------------------------------------------------\n    --  CAST COLORS AND EFFECTS", "the X Offset cog"):gsub("\n    end\n%s*$", "\n"), "=DisplayBars_Options.lua"))(unpack(args))
    check(type(cog) == "table" and cog.rows and cog.rows[1] and cog.rows[1].label == "X Offset", "the X Offset cog was not built")
    if cog and cog.rows and cog.rows[1] then
        local row = cog.rows[1]
        check(row.min == -50 and row.max == 50 and row.step == 1 and row.get() == 0, "the slider is not -50 to 50 from 0")
        canDraw = true
        check(cog.disabled() == true and cog.requireState == "disabled" and cog.disabledTooltip == "Wrap Around Castbar", "the cog is not locked behind a wrap that draws")
        canDraw = false
        db.wrapBorderCastbar = true
        check(cog.disabled() == false, "the cog is locked by a saved wrap that cannot draw")
        db.wrapBorderCastbar = nil
        Reset()
        row.set(20)
        check(db.castBarOffsetX == 20 and row.get() == 20, "the slider did not save its value")
        check(calls.relayout == 1 and calls.preview == 1, "the slider did not re-place the cast bars and the preview once")
        check(calls.full == nil, "a slider step runs the full nameplate refresh")
    end

    -- Cast Bar Y Offset
    local yRow = assert(loadstring(HEAD .. "return " .. Cut(BARS, '        { type="slider", text="Cast Bar Y Offset"', " });  y = y - h", "the Y Offset row") .. " }", "=DisplayBars_Options.lua"))(unpack(args))
    Reset()
    yRow.setValue(8)
    check(db.castBarOffsetY == 8 and calls.relayout == 1 and calls.preview == 1, "Cast Bar Y Offset does not re-place the cast bars through the shared helper")
    check(calls.layoutBar == nil and calls.full == nil, "Cast Bar Y Offset lays the plates out with one shared cast height")

    -- the wrap toggle: an offset in play is re-placed, without the full refresh
    local wrapSet = assert(loadstring(HEAD .. "local t = {\n" .. Cut(LAYOUT, "              set=function(v)\n                DB().wrapBorderCastbar = v", "              end },\n        }\n        -- Show Seam Line", "the wrap toggle") .. "              end }\nreturn t.set", "=DisplayLayout_Options.lua"))(unpack(args))
    db.castBarOffsetX = 20
    Reset()
    wrapSet(true)
    check(db.wrapBorderCastbar == true and calls.wrapAll == 1 and calls.relayout == 1 and calls.full == nil, "turning the wrap on with an offset saved does not re-place the cast bars alone")
    db.castBarOffsetX = 0
    Reset()
    wrapSet(false)
    check(calls.relayout == nil and calls.full == nil, "the wrap toggle re-places the cast bars with no offset saved")

    -- the Border control: with the wrap saved on it decides whether the offset applies
    local borderSet = assert(loadstring(HEAD .. "local t = {\n" .. Cut(LAYOUT, '          setValue=function(v)\n            if v == "custom" then', '          end }, EllesmereUI.BlizzStyle.Active("nameplates") == "classic"),', "the Border control") .. "          end }\nreturn t.setValue", "=DisplayLayout_Options.lua"))(unpack(args))
    db.castBarOffsetX, db.wrapBorderCastbar = 20, true
    Reset()
    borderSet("none")
    check(db.showBorder == false and db.customBorderEnabled == false and calls.border == 1, "the Border control did not save None")
    check(calls.relayout == 1 and calls.full == nil, "a border change under a saved wrap does not re-place the cast bars")
    db.wrapBorderCastbar = false
    Reset()
    borderSet("basic")
    check(calls.relayout == nil, "a border change re-places the cast bars although no wrap is saved")
    db.wrapBorderCastbar, db.castBarOffsetX = true, 0
    Reset()
    borderSet("custom")
    check(calls.relayout == nil, "a border change re-places the cast bars although no offset is saved")

    -- the options preview places its cast bar with the same offset
    local _, n = PREVIEW:gsub('cast:SetPoint%("TOPLEFT", health, "BOTTOMLEFT", pShiftX %+ ns%.GetCastBarOffsetX%(%), pCastY%)', "")
    check(n == 1, "the options preview does not place its cast bar with the offset")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_cast_bar_offset_x (%d checks)"):format(count))
