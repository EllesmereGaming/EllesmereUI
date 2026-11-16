-- Stub harness: Unit Frames, the player frame's Rested Indicator. Everywhere it
-- sits on the health bar's top-left ("ZZZ", or the animated icon at its Size).
-- Under the WoW Forever look's player art the animated icon takes the stock
-- frame's own spot above the portrait (a 20 x Size/24 frame at 64, -6 of the
-- frame, the flipbook 30 x Size/24 centred on it, the cog's X / Y added) and a
-- gold glow pulses over the art while resting. Icon and glow follow the art:
-- when the layout pass resolves another one (Portrait Side), both are placed
-- and shown again.
-- Cuts the rest block out of EUI_UnitFrames_Init.lua and ns.UF_RestFollowArt
-- out of EUI_UnitFrames_StockStyles.lua by their first and last lines (a moved
-- line fails here by name) and runs them over stub frames.
--   lua .tools/tests/test_uf_forever_rest_icon.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local INIT = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Init.lua")
local STOCK = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_StockStyles.lua")
local BLOCK = Cut(INIT, "    -- Rested indicator on the player frame:", "    -- Castbar state is managed by ApplyBlizzCastbarState", "the rest block")
local FOLLOW = Cut(STOCK, "function ns.UF_RestFollowArt(frame, G, mirror)\n", "function ns.UF_BlizzGeom(frame)\n", "the follow function")
-- the layout pass hands the art it resolved to the follow function, before anything can return
assert(STOCK:find("    local G, mirror = ns.UF_BlizzResolve(frame, unit)\n    if not G then return end\n    ns.UF_RestFollowArt(frame, G, mirror)\n", 1, true),
    "the stock layout pass does not hand the resolved art to the rest indicator")

-------------------------------------------------------------------------------
--  Stubs
-------------------------------------------------------------------------------
local function AnimGroup()
    local ag = { playing = false, anims = {}, plays = 0 }
    function ag:SetLooping(v) self.looping = v end
    function ag:Play() self.playing = true; self.plays = self.plays + 1 end
    function ag:Stop() self.playing = false end
    function ag:CreateAnimation(kind)
        local a = setmetatable({ kind = kind }, { __index = function() return function(self, ...) end end })
        self.anims[#self.anims + 1] = a
        return a
    end
    return ag
end
local function Region(kind, parent)
    local r = { kind = kind, parent = parent, points = {}, shown = true, scripts = {}, events = {} }
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(p, rel, rp, x, y) self.points[p] = { rel = rel, rp = rp or p, x = x or 0, y = y or 0 } end
    function r:SetAllPoints(rel) self.points = { ALL = { rel = rel or self.parent } } end
    function r:SetFrameLevel(l) self.level = l end
    function r:GetFrameLevel() return self.level or 1 end
    function r:SetFrameStrata(s) self.strata = s end
    function r:GetFrameStrata() return self.strata or "MEDIUM" end
    function r:EnableMouse(v) self.mouse = v end
    function r:SetScript(n, fn) self.scripts[n] = fn end
    function r:RegisterEvent(e) self.events[e] = true end
    function r:UnregisterAllEvents() self.events = {} end
    function r:Show() self:SetShown(true) end
    function r:Hide() self:SetShown(false) end
    function r:IsShown() return self.shown end
    function r:SetShown(v)
        v = v and true or false
        local was = self.shown
        self.shown = v
        if was ~= v then
            local fn = self.scripts[v and "OnShow" or "OnHide"]
            if fn then fn(self) end
        end
    end
    function r:SetAtlas(name) self.atlas = name end
    function r:SetVertexColor(a, b, c) self.color = { a, b, c } end
    function r:SetText(t) self.text = t end
    function r:SetTextColor() end
    function r:CreateTexture() return Region("Texture", self) end
    function r:CreateFontString() return Region("FontString", self) end
    function r:CreateAnimationGroup()
        local ag = AnimGroup()
        self.groups = self.groups or {}
        self.groups[#self.groups + 1] = ag
        return ag
    end
    return r
end

-- One player frame with the rest block run over it.
-- o.db: the account settings; o.resting; o.forever: the WoW Forever look;
-- o.art: "player" | "target" | nil (no stock art: the EllesmereUI look)
local function Make(o)
    local env = setmetatable({}, { __index = _G })
    env.CreateFrame = function(kind, name, parent) return Region(kind, parent) end
    env.EllesmereUIDB = o.db
    env.IsResting = function() return o.resting end
    env.SetFSFont = function() end
    env.UnsnapTex = function() end
    env.EllesmereUI = {
        AddRestFlipbook = function(frame, tex)
            tex:SetAtlas("rest-flipbook")
            local anim = frame:CreateAnimationGroup()
            anim:SetLooping("REPEAT")
            frame:SetScript("OnShow", function() anim:Play() end)
            frame:SetScript("OnHide", function() anim:Stop() end)
            return anim
        end,
    }
    local P, T = { name = "player art" }, { name = "target art" }
    local asked = 0
    local ns = {
        UF_BLIZZ = { player = P, target = T },
        UF_Forever = function() asked = asked + 1; return o.forever end,
        UF_AtlasOK = function() return o.noGlowArt ~= true end,
        UF_StockAtlas = function(tex, name) tex:SetAtlas(name) end,
        UF_BlizzPoint = function(region, point, rel, relPoint, x, y, mirror)
            assert(not mirror, "the player frame is never mirrored")
            region:SetPoint(point, rel, relPoint, x, y)
        end,
    }
    env.ns = ns
    local pf = Region("Button")
    pf.level = 5
    pf.Health = Region("StatusBar", pf)
    pf.Health.level = 7
    pf._barClip = Region("Frame", pf)
    pf._barClip.level, pf._barClip.strata = 5, "LOW"
    pf._blizzGeom = o.art == "target" and T or (o.art == "player" and P or nil)
    env.frames = { player = pf }
    local chunk = assert(loadstring(BLOCK, "=rest-block"))
    setfenv(chunk, env)
    chunk()
    assert(loadstring("local ns = ...\n" .. FOLLOW, "=follow-cut"))(ns)
    return pf, env, ns, P, T, function() return asked end
end
local function DB(t)
    local d = { showRestedIndicator = true, restedIndicatorAnimated = true, restedIndicatorAnimatedSize = 30,
        restedIndicatorXOffset = 5, restedIndicatorYOffset = -3 }
    for k, v in pairs(t or {}) do d[k] = v end
    return d
end
local n = 0
local function check(cond, msg)
    n = n + 1
    assert(cond, msg)
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-6 end
-- where the animated icon stands
local function OnHealthBar(pf, size)
    local a, q = pf._restAnim, pf._restAnim.points.TOPLEFT
    return q and q.rel == pf.Health and q.x == 8 and q.y == -5 and a.w == size and a.h == size
        and pf._restAnimTex.points.ALL ~= nil and pf._restAnimTex.points.ALL.rel == a
end
local function AtStockSpot(pf, size)
    local a, q, k = pf._restAnim, pf._restAnim.points.TOPLEFT, size / 24
    local tex = pf._restAnimTex
    return q and q.rel == pf and q.rp == "TOPLEFT" and q.x == 69 and q.y == -9 and near(a.w, 20 * k) and near(a.h, 20 * k)
        and tex.points.CENTER ~= nil and tex.points.CENTER.rel == a and near(tex.w, 30 * k) and near(tex.h, 30 * k)
end

-------------------------------------------------------------------------------
-- 1. every look but the WoW Forever one, and the WoW Forever look on any art
--    but the player's: the icon on the health bar at its Size, no glow
-------------------------------------------------------------------------------
for _, o in ipairs({ { forever = false }, { forever = false, art = "player" }, { forever = false, art = "target" }, { forever = true }, { forever = true, art = "target" } }) do
    local what = (o.forever and "WoW Forever look" or "another look") .. ", art " .. tostring(o.art)
    o.db, o.resting = DB(), true
    local pf = Make(o)
    check(pf._restAnim ~= nil and OnHealthBar(pf, 30), what .. ": the icon is not on the health bar at its Size")
    check(pf._restGlow == nil, what .. ": a glow was built")
    check(pf._restAnim.shown and pf._restAnim.groups[1].playing and not pf._restText.shown, what .. ": the icon does not play")
    local t = pf._restText.points.TOPLEFT
    check(t and t.rel == pf.Health and t.x == 8 and t.y == -5, what .. ": the ZZZ text's spot")
end

-------------------------------------------------------------------------------
-- 2. the WoW Forever look's player art: the stock spot, and the resting glow
-------------------------------------------------------------------------------
do
    local pf, env = Make({ db = DB(), resting = true, forever = true, art = "player" })
    local a, glow = pf._restAnim, pf._restGlow
    check(AtStockSpot(pf, 30), "the icon is not at the stock spot (64 + X, -6 + Y of the frame) at 20 / 30 x Size / 24")
    check(a.level == pf._barClip.level + 10, "the icon's level")
    check(glow ~= nil and glow.shown and glow.level == pf._barClip.level + 9 and glow.strata == "LOW" and glow.mouse == false,
        "the glow: not built, not shown, or not right under the icon")
    check(glow.points.ALL ~= nil and glow.points.ALL.rel == pf, "the glow does not cover the frame")
    local pulse = glow.groups[1]
    check(pulse.playing and pulse.looping == "REPEAT" and #pulse.anims == 2 and pulse.anims[1].kind == "Alpha", "the glow does not pulse")
    -- leaving the rest area, and coming back: the same glow
    env.IsResting = function() return false end
    pf._restEventFrame.scripts.OnEvent()
    check(not glow.shown and not pulse.playing and not a.shown, "out of rest: the glow or the icon stayed")
    env.IsResting = function() return true end
    pf._restEventFrame.scripts.OnEvent()
    check(pf._restGlow == glow and glow.shown and pulse.playing and a.shown, "resting again: a second glow, or none")
    -- Animated off: the text, no glow; on again
    env.EllesmereUIDB.restedIndicatorAnimated = false
    pf._restUpdate()
    check(not glow.shown and not a.shown and pf._restText.shown, "Animated off: the glow stayed, or no ZZZ text")
    env.EllesmereUIDB.restedIndicatorAnimated = true
    pf._restUpdate()
    check(glow.shown and a.shown and not pf._restText.shown, "Animated on again")
    -- the indicator off: everything down, no event heard
    env.EllesmereUIDB.showRestedIndicator = false
    pf._restUpdate()
    check(not glow.shown and not a.shown and not pf._restText.shown and next(pf._restEventFrame.events) == nil, "the indicator off: something stayed, or an event is still heard")
    env.EllesmereUIDB.showRestedIndicator = true
    pf._restUpdate()
    check(pf._restEventFrame.events.PLAYER_UPDATE_RESTING and glow.shown, "the indicator on again")
    -- the cog: Size and the offsets
    env.EllesmereUIDB.restedIndicatorAnimatedSize = 48
    env.EllesmereUIDB.restedIndicatorXOffset, env.EllesmereUIDB.restedIndicatorYOffset = 0, 0
    pf._restPlace()
    local q = a.points.TOPLEFT
    check(near(a.w, 40) and near(pf._restAnimTex.w, 60) and q.x == 64 and q.y == -6, "Size 48 with no offset: 40 / 60 at 64, -6")
    -- a client without the glow's art: the stock spot, no glow built
    local pf2 = Make({ db = DB(), resting = true, forever = true, art = "player", noGlowArt = true })
    check(AtStockSpot(pf2, 30) and pf2._restGlow == nil, "no glow art: a glow was built, or the icon moved")
end

-------------------------------------------------------------------------------
-- 3. off, or the ZZZ style: nothing built, the look never asked
-------------------------------------------------------------------------------
do
    local pf, _, _, _, _, asked = Make({ db = DB({ showRestedIndicator = false }), resting = true, forever = true, art = "player" })
    check(pf._restAnim == nil and pf._restGlow == nil and asked() == 0 and next(pf._restEventFrame.events) == nil, "the indicator off built or asked something")
    pf, _, _, _, _, asked = Make({ db = DB({ restedIndicatorAnimated = false }), resting = true, forever = true, art = "player" })
    check(pf._restAnim == nil and pf._restGlow == nil and asked() == 0 and pf._restText.shown, "the ZZZ style built an icon or a glow")
    pf, _, _, _, _, asked = Make({ db = DB(), resting = false, forever = true, art = "player" })
    check(pf._restAnim == nil and pf._restGlow == nil and asked() == 0, "not resting: something was built")
end

-------------------------------------------------------------------------------
-- 4. the icon and the glow follow the art: Portrait Side moved to the right
--    hands the frame the target art, and back
-------------------------------------------------------------------------------
do
    local pf, env, ns, P, T = Make({ db = DB(), resting = true, forever = true, art = "player" })
    local a, glow = pf._restAnim, pf._restGlow
    local places, updates = 0, 0
    local place, update = pf._restPlace, pf._restUpdate
    pf._restPlace = function() places = places + 1; place() end
    pf._restUpdate = function() updates = updates + 1; update() end
    -- the first layout pass on the art the block was placed for
    ns.UF_RestFollowArt(pf, P, false)
    check(places == 1 and updates == 1 and AtStockSpot(pf, 30) and glow.shown, "the first pass on the player art")
    ns.UF_RestFollowArt(pf, P, nil)
    ns.UF_RestFollowArt(pf, P, false)
    check(places == 1 and updates == 1, "the same art placed the icon again")
    -- the portrait moves to the right while resting
    pf._blizzGeom = T
    ns.UF_RestFollowArt(pf, T, false)
    check(places == 2 and updates == 2, "another art was not followed")
    check(OnHealthBar(pf, 30), "on the target art the icon is not on the health bar")
    check(not glow.shown and not glow.groups[1].playing, "on the target art the player glow stayed")
    check(a.shown, "on the target art the icon went away")
    -- and back to the left
    pf._blizzGeom = P
    ns.UF_RestFollowArt(pf, P, false)
    check(places == 3 and AtStockSpot(pf, 30) and glow.shown and glow.groups[1].playing, "back on the player art: the stock spot or the glow did not come back")
    -- a mirrored art counts as another art
    ns.UF_RestFollowArt(pf, P, true)
    check(places == 4, "a mirrored art was not followed")
    -- a frame with no rest indicator: nothing, no error
    local other = {}
    ns.UF_RestFollowArt(other, T, false)
    check(other._restGeom == nil, "a frame with no rest indicator was stamped")
end

print(("unit frames rest icon harness: %d checks, ok"):format(n))
