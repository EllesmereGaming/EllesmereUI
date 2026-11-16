-- Stub harness: Nameplates, the plate frame's size and click area
-- (EUI_Nameplates_PlatePool.lua) and the Blizzard Nameplate Size setting.
-- Every nameplate shares one frame. The sizing pass makes it our hitbox and sets insets that
-- let the click area fill it: the same inside dungeons, raids, scenarios, arenas and
-- battlegrounds as in the open world. (The game applies an inset to the hit rect Blizzard's
-- own unit frame sets inside the frame, so a frame wider than the hitbox, with the click area
-- trimmed back by insets, comes out narrower than asked.)
-- Checked here on the real functions, cut from the files:
--   the sizing pass: the frame's size and both plate types' insets, in and out of an instance,
--     with no read of Blizzard's own plate width and no look at the zone; in combat it waits
--     on the module's combat queue; the live plates are re-anchored only when their shift
--     changed; the hitbox overlay covers the frame;
--   a zone change runs no sizing pass, and Blizzard's own option passes still run it;
--   Friendly Names Not Clickable keeps the friendly insets while it is on and hands them back
--     to the pass when it is turned off;
--   the Blizzard Nameplate Size value sent to the game, its default, its place outside Spec
--     Overrides, its options row and the translations of its texts.
--   lua .tools/tests/test_np_hitbox_instances.lua        (from the repository root)
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

local POOL = ReadSource("EllesmereUINameplates/EUI_Nameplates_PlatePool.lua")
local FRIENDLY = ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua")
local EVENTS = ReadSource("EllesmereUINameplates/EUI_Nameplates_Events.lua")
local CASTSTATE = ReadSource("EllesmereUINameplates/EUI_Nameplates_CastState.lua")

local ENEMY, FRIEND = 1, 2
local OURS, BLIZZ = 156, 287.5     -- our hitbox width (a 150 bar at Hitbox Size X 104), Blizzard's at size 3

-- A fresh world: the client's calls, and the real functions loaded over it.
local function World()
    local W = { combat = false, iType = "none", sizes = 0, insets = {}, insetCalls = 0, queue = {},
                widthReads = 0, zoneAsks = 0, clickThrough = false, overlays = 0, anchors = 0 }
    local function Plate()
        local plate = { nameplate = {} }
        function plate:ClearAllPoints() self.point = nil end
        function plate:SetPoint(point, rel, relPoint, x, y) self.point = { point, rel, relPoint, x, y }; W.anchors = W.anchors + 1 end
        return plate
    end
    local ns = { plates = { a = Plate(), b = Plate() }, CombatQueue = {} }
    function ns.CombatQueue.Defer(key, fn) W.queue[key] = fn end
    function ns.NP_HitboxHeight() return 20 end
    function ns._ApplyHitboxOverlay() W.overlays = W.overlays + 1 end
    -- Blizzard's own plate width and the zone: there to be counted, the pass reads neither.
    local driver = {}
    function driver:GetNamePlateScale() return { horizontal = 1.25 } end
    function driver:GetNamePlateWidth() W.widthReads = W.widthReads + 1; return BLIZZ end
    local env = {
        ns = ns, p = { hitboxScaleX = 104 }, defaults = {},
        GetHealthBarWidth = function() return 150 end,
        GetHitboxYShift = function() return W.yShift or 0 end,
        NamePlateDriverFrame = driver,
        NamePlateConstants = { STYLE_CVAR = "nameplateStyle" },
        CVarCallbackRegistry = { GetCVarNumberOrDefault = function(_, cvar) return cvar == "nameplateStyle" and 7 or nil end },
        InCombatLockdown = function() return W.combat end,
        GetInstanceInfo = function() W.zoneAsks = W.zoneAsks + 1; return "Somewhere", W.iType end,
        C_NamePlate = { SetNamePlateSize = function(w, h) W.size = { w, h }; W.sizes = W.sizes + 1 end },
        C_NamePlateManager = { SetNamePlateHitTestInsets = function(kind, l, r, t, b)
            W.insets[kind] = { l, r, t, b }
            W.insetCalls = W.insetCalls + 1
        end },
        Enum = { NamePlateType = { Enemy = ENEMY, Friendly = FRIEND } },
        FP = function() return { friendlyClickThrough = W.clickThrough } end,
    }
    setmetatable(env, { __index = _G })
    local pool = assert(loadstring(Cut(POOL, "function ns.RefreshHitboxSize()",
        "-- Hitbox visualizer: translucent overlay", "the sizing pass"), "=EUI_Nameplates_PlatePool.lua"))
    setfenv(pool, env)
    pool()
    local friendly = assert(loadstring(Cut(FRIENDLY, "local CLICK_THROUGH_INSET = 10000", "--------------------------------------------------------------------",
        "the friendly click-through"), "=EllesmereUINameplatesFriendly.lua"))
    setfenv(friendly, env)
    friendly()
    W.ns, W.env, W.driver = ns, env, driver
    -- Combat ends: the module's queue runs what waited.
    function W.Regen()
        W.combat = false
        local q = W.queue
        W.queue = {}
        for _, fn in pairs(q) do fn() end
    end
    function W.Insets(kind) local i = W.insets[kind] or {}; return table.concat({ tostring(i[1]), tostring(i[2]), tostring(i[3]), tostring(i[4]) }, " ") end
    return W
end
local FULL = "-10000 -10000 -10000 -10000"
local SHUT = "10000 10000 10000 10000"

-------------------------------------------------------------------------------
-- 1. the sizing pass: our hitbox and a click area that fills it, in and out of an instance
-------------------------------------------------------------------------------
do
    local W = World()
    check(type(W.ns.RefreshHitboxSize) == "function" and type(W.ns.UpdateFriendlyClickThrough) == "function", "the real functions were not cut from the files")
    W.ns.RefreshHitboxSize()
    check(W.size and W.size[1] == OURS and W.size[2] == 20, "in the open world the frame is not our hitbox (" .. tostring(W.size and W.size[1]) .. ")")
    check(W.Insets(ENEMY) == FULL and W.Insets(FRIEND) == FULL, "in the open world the click area is not the whole frame")
    check(W.sizes == 1 and W.insetCalls == 2, "one pass does not size the frame once and set each plate type's insets once")
    for _, kind in ipairs({ "party", "raid", "scenario", "arena", "pvp" }) do
        local I = World()
        I.iType = kind
        I.ns.RefreshHitboxSize()
        check(I.size[1] == OURS and I.size[2] == 20, "inside a " .. kind .. " instance the frame is not our hitbox (" .. tostring(I.size[1]) .. ")")
        check(I.Insets(ENEMY) == FULL and I.Insets(FRIEND) == FULL, "inside a " .. kind .. " instance the click area is not the whole frame (" .. I.Insets(ENEMY) .. ")")
        check(I.widthReads == 0 and I.zoneAsks == 0, "inside a " .. kind .. " instance the pass read Blizzard's plate width or looked at the zone")
    end
    check(W.widthReads == 0 and W.zoneAsks == 0, "the pass read Blizzard's plate width or looked at the zone")
    -- nothing of a frame wider than the hitbox is left
    check(W.ns._hitboxSide == nil and W.ns._hitboxInside == nil and W.ns.NP_HitboxZoneEdge == nil, "the pass keeps a side inset, a zone verdict or a zone edge entry")
    check(not POOL:find("GetNamePlateWidth", 1, true) and not POOL:find("PLATE_INSTANCES", 1, true), "the pool file reads Blizzard's plate width or lists instances")
    -- the hitbox follows the bar width and Hitbox Size X
    local S = World()
    S.env.p.hitboxScaleX = 150
    S.ns.RefreshHitboxSize()
    check(S.size[1] == 225, "Hitbox Size X does not scale the frame's width (" .. tostring(S.size[1]) .. ")")
    S.env.p.hitboxScaleX = nil
    S.ns.RefreshHitboxSize()
    check(S.size[1] == 150, "an unset Hitbox Size X does not give the bar's own width")
    -- a client without the size call sets nothing; one without the insets call still sizes
    local N = World()
    N.env.C_NamePlate = {}
    N.ns.RefreshHitboxSize()
    check(N.sizes == 0 and N.insetCalls == 0, "a client without the size call still set insets")
    N = World()
    N.env.C_NamePlateManager = nil
    local ok, err = pcall(N.ns.RefreshHitboxSize)
    check(ok and N.sizes == 1 and N.insetCalls == 0, "a client without the insets call does not just size the frame: " .. tostring(err))
end

-------------------------------------------------------------------------------
-- 2. combat: nothing is set; the pass waits on the module's combat queue
-------------------------------------------------------------------------------
do
    local W = World()
    W.combat = true
    W.ns.RefreshHitboxSize()
    W.ns.RefreshHitboxSize()
    check(W.sizes == 0 and W.insetCalls == 0 and W.anchors == 0, "the frame was sized, or a plate moved, in combat")
    local waiting = 0
    for _ in pairs(W.queue) do waiting = waiting + 1 end
    check(waiting == 1 and W.queue.NPHitboxSize == W.ns.RefreshHitboxSize, "a combat request does not wait once on the module's combat queue")
    check(W.ns._hitboxPending == nil, "a combat request leaves a flag for the regen handler")
    W.Regen()
    check(W.sizes == 1 and W.size[1] == OURS and W.Insets(ENEMY) == FULL, "the pass does not run as combat ends")
    check(not EVENTS:find("_hitboxPending", 1, true), "the regen handler still reads a flag for the pass")
end

-------------------------------------------------------------------------------
-- 3. a zone change runs no sizing pass; Blizzard's own option passes still do
-------------------------------------------------------------------------------
do
    local zone = Cut(EVENTS, 'if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then', "ns._UpdateMouseover()", "the zone handler")
    check(not zone:find("RefreshHitboxSize", 1, true) and not zone:find("NP_HitboxZoneEdge", 1, true), "the zone handler runs a sizing pass")
    check(not EVENTS:find("NP_HitboxZoneEdge", 1, true), "the events file names a zone edge entry")
    -- Blizzard's own option pass puts the frame back to Blizzard's size: every pass re-applies ours
    local B = World()
    B.ns.RefreshHitboxSize()
    B.size = { BLIZZ, 44 }
    B.insets = {}
    B.ns.RefreshHitboxSize()
    check(B.sizes == 2 and B.size[1] == OURS and B.Insets(ENEMY) == FULL, "a second pass is skipped (Blizzard's reset would stay)")
    -- the entry the login setup, a display change and Blizzard's option passes call is that pass
    local area = Cut(CASTSTATE, "    local function ApplyNamePlateClickArea()", "    ApplyNamePlateClickArea()", "the click area entry")
    check(area:find("ns.RefreshHitboxSize()", 1, true) and not area:find("SetNamePlateSize", 1, true)
        and not area:find("SetNamePlateHitTestInsets", 1, true), "the click area entry is not the one sizing pass")
end

-------------------------------------------------------------------------------
-- 4. the live plates are re-anchored only when their shift changed; the overlay covers the frame
-------------------------------------------------------------------------------
do
    local W = World()
    W.ns.RefreshHitboxSize()
    check(W.anchors == 2 and W.ns.plates.a.point and W.ns.plates.a.point[1] == "CENTER" and W.ns.plates.a.point[3] == "CENTER"
        and W.ns.plates.a.point[2] == W.ns.plates.a.nameplate and W.ns.plates.a.point[5] == 0, "the first pass does not anchor the live plates at the frame's centre")
    W.ns.RefreshHitboxSize()
    W.iType = "party"
    W.ns.RefreshHitboxSize()
    check(W.anchors == 2, "a pass with the same shift re-anchored the plates (" .. (W.anchors - 2) .. ")")
    W.yShift = 4
    W.ns.RefreshHitboxSize()
    check(W.anchors == 4 and W.ns.plates.b.point[5] == 4 and W.ns.plates.a.point[5] == 4, "a changed shift does not re-anchor the live plates")
    W.yShift = 0
    W.ns.RefreshHitboxSize()
    check(W.anchors == 6 and W.ns.plates.a.point[5] == 0, "a shift back to 0 does not re-anchor the live plates")
    -- the pass has no overlay work: the overlay covers the frame, whatever the zone
    local O = World()
    O.ns._hitboxOverlayShown = true
    O.ns.RefreshHitboxSize()
    O.iType = "party"
    O.ns.RefreshHitboxSize()
    check(O.overlays == 0, "the sizing pass re-applied the hitbox overlays (" .. O.overlays .. ")")
    -- the real overlay, over a frame that records its anchors
    local made
    local function Region()
        local r = { points = {} }
        function r:SetAllPoints(rel) self.all = rel or true end
        function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function r:ClearAllPoints() self.all, self.points = nil, {} end
        function r:CreateTexture() return Region() end
        function r:SetParent(parent) self.parent = parent end
        function r:GetFrameLevel() return 3 end
        function r:Show() self.shown = true end
        function r:Hide() self.shown = false end
        return setmetatable(r, { __index = function() return function() end end })
    end
    local ons = { _hitboxOverlayShown = true }
    local overlay = assert(loadstring(Cut(POOL, "function ns._ApplyHitboxOverlay(plate)", "-- Toggle the hitbox visualizer", "the hitbox overlay"), "=the hitbox overlay"))
    setfenv(overlay, setmetatable({ ns = ons, CreateFrame = function(_, _, parent) made = Region(); made.parent = parent; return made end }, { __index = _G }))
    overlay()
    local np = Region()
    local plate = { nameplate = np }
    ons._ApplyHitboxOverlay(plate)
    check(made and plate.hitboxOverlay == made and made.shown == true, "the overlay is not built and shown")
    check(made and made.all == np and #made.points == 0, "the overlay does not cover the whole frame")
    check(made and made.parent == np, "the overlay does not hang from the nameplate")
    ons._hitboxOverlayShown = false
    ons._ApplyHitboxOverlay(plate)
    check(made and made.shown == false, "the overlay stays up once it is switched off")
    -- a pooled plate reused on another nameplate: the same overlay, on that nameplate
    local first, np2 = made, Region()
    plate.nameplate = np2
    ons._hitboxOverlayShown = true
    ons._ApplyHitboxOverlay(plate)
    check(made == first and made.parent == np2 and made.all == np2 and made.shown == true,
        "a reused plate's overlay does not move to its new nameplate")
end

-------------------------------------------------------------------------------
-- 5. Friendly Names Not Clickable
-------------------------------------------------------------------------------
do
    local W = World()
    -- never on: the pass's insets stand
    W.ns.RefreshHitboxSize()
    check(W.Insets(FRIEND) == FULL, "with the option off the friendly insets are not the pass's")
    -- on: it owns the friendly insets after every pass, in and out of an instance
    W.clickThrough = true
    W.ns.UpdateFriendlyClickThrough()
    check(W.Insets(FRIEND) == SHUT and W.Insets(ENEMY) == FULL, "the option does not shut the friendly click area alone")
    W.ns.RefreshHitboxSize()
    check(W.Insets(FRIEND) == SHUT, "a sizing pass opened the friendly click area while the option is on")
    W.iType = "party"
    W.ns.RefreshHitboxSize()
    check(W.Insets(FRIEND) == SHUT and W.Insets(ENEMY) == FULL, "inside an instance the option does not keep friendly plates shut, or the enemy insets are off")
    -- turned off: the pass's insets again
    W.clickThrough = false
    local ok, err = pcall(W.ns.UpdateFriendlyClickThrough)
    check(ok, "turning the option off raised: " .. tostring(err))
    check(W.Insets(FRIEND) == FULL and W.Insets(ENEMY) == FULL, "turning the option off leaves the friendly click area at " .. W.Insets(FRIEND))
    local calls = W.insetCalls
    W.ns.UpdateFriendlyClickThrough()
    check(W.insetCalls == calls, "the option, off and already handed back, set insets again")
    -- turned off in combat: it waits, then hands back
    W.clickThrough = true
    W.ns.UpdateFriendlyClickThrough()
    W.combat, W.clickThrough = true, false
    W.ns.UpdateFriendlyClickThrough()
    check(W.Insets(FRIEND) == SHUT and W.queue.FriendlyClickThrough ~= nil, "the option changed insets in combat, or did not wait")
    W.Regen()
    check(W.Insets(FRIEND) == FULL, "the option turned off in combat does not hand the insets back as combat ends")
end

-------------------------------------------------------------------------------
-- 6. Blizzard Nameplate Size: the value sent, its default, Spec Overrides, the options row
-------------------------------------------------------------------------------
do
    local CAST = ReadSource("EllesmereUINameplates/EUI_Nameplates_CastState.lua")
    local sent
    local send = assert(loadstring("local db, EllesmereUI = ...\n" .. Cut(CAST, "        local npSize = tonumber(db.nameplateSize) or 3",
        '        EllesmereUI.SetCVar("nameplateShowAll"', "the size sent to the game"), "=EUI_Nameplates_CastState.lua"))
    local function Sent(v)
        sent = nil
        send({ nameplateSize = v }, { SetCVar = function(name, value, owner) if name == "nameplateSize" then sent = value; check(owner == "EllesmereUINameplates", "the CVar is written with no owner") end end })
        return sent
    end
    check(Sent(nil) == 3 and Sent(3) == 3, "an unset size is not sent as 3")
    check(Sent(1) == 1 and Sent(5) == 5 and Sent(4) == 4, "a size of 1 to 5 is not sent as it is")
    check(Sent(0) == 3 and Sent(6) == 3 and Sent(-2) == 3, "a size outside 1 to 5 is not sent as 3")
    check(Sent(2.6) == 3 and Sent(2.4) == 2, "a size between two steps is not rounded")
    check(Sent("4") == 4 and Sent("big") == 3, "a size saved as text is not read")
    local MAIN = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")
    check(MAIN:find("\n    nameplateSize = 3,\n", 1, true), "the default Blizzard Nameplate Size is not 3, the size the module forced before")
    -- a size that only applies after a reload is no Spec or Conditional Override
    local SPEC = ReadSource("EllesmereUI_SpecOverrides.lua")
    local blacklist = assert(loadstring(Cut(SPEC, "local SETTING_BLACKLIST = {", "\n-- Only the COMPOUND half", "the setting blacklist") .. "\nreturn SETTING_BLACKLIST"))()
    check(blacklist.EllesmereUINameplates and blacklist.EllesmereUINameplates.nameplateSize == true, "Blizzard Nameplate Size can be captured as a Spec Override")
    -- the options row (in the cog of Friendly Nameplate Style): a slider of 1 to 5
    -- with a one-sentence tooltip and a reload confirm
    local OPTIONS = ReadSource("EllesmereUIOptions/Nameplates_Options/FriendlyPage_Options.lua")
    local row = Cut(OPTIONS, '{ type="slider", label="Blizzard Nameplate Size", min=1, max=5, step=1,', '\n          end }\n', "the options row")
    local tip = row:match('tooltip="([^"]*)"')
    check(tip == "Size of Blizzard's own nameplates, which still show for friendly players inside instances. Default is 3.", "the row's tooltip is not the one sentence: " .. tostring(tip))
    check(row:find('EllesmereUI.SetCVar("nameplateSize", v, "EllesmereUINameplates")', 1, true) and row:find("reload    = true", 1, true), "the row does not write the CVar and ask for a reload")
    local TEXTS = { "Blizzard Nameplate Size", tip or "?", "Changing Blizzard Nameplate Size requires a UI reload to take effect." }
    for _, code in ipairs({ "deDE", "esES", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local loc = ReadSource("EllesmereUILocales/" .. code .. ".lua")
        for _, key in ipairs(TEXTS) do
            local _, n = loc:gsub('\nL%["' .. key:gsub("%p", "%%%0") .. '"%]', "")
            check(n == 1, code .. " holds " .. n .. " translations of: " .. key:sub(1, 50))
        end
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_hitbox_instances (%d checks)"):format(count))
