-- Stub harness: Raid & Party Frames, Dark Mode on the pet frames and the Friendly Boss group.
-- Both draw through one painter and one styler (FB.PaintBarColor / FB.StyleVisuals in
-- EUI_RaidFrames_BossFrames.lua); each owner says whether it draws dark (owner.Dark(s)):
--   * the pets follow the frames they are styled from until a Fill Color of their own is picked
--     (a picked mode decides, Dark Mode included);
--   * the boss group keeps Boss Health Color unless its Follow Dark Mode option is on (opt-in);
--   * a dark fill is written as the raid frames write it: the colour at 1, then the fill's alpha
--     (the Dark Mode Fill Opacity) last, since the two are one slot and the last write stands;
--   * the dark background is the styler's, and the paint's only once the palette changed;
--   * the options preview pets paint through the same painter;
--   * Boss Health Color greys out while the group draws dark;
--   * the dark background covers only the part of the bar the fill does not paint, as on the raid
--     frames; outside Dark Mode and under Textured Background it covers the whole button;
--   * the global Dark Mode toggle also flips a Fill Color the pets picked and puts it back, and
--     writes nothing for pets that follow.
-- The pieces are cut out of the real files by their first and last lines and run over stubs.
--   lua .tools/tests/test_rf_pet_dark_mode.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
-- The text from the line starting `first` up to the line starting `last`; nil when `first` is not
-- in the file (a piece an older file does not have: its checks then fail by name).
local function CutOpt(src, first, last)
    local a = src:find(first, 1, true)
    if not a then return nil end
    local b = assert(src:find(last, a + #first, true), "last line not found after: " .. first)
    return src:sub(a, b - 1)
end
local function Cut(src, first, last)
    return assert(CutOpt(src, first, last), "first line not found: " .. first)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local BOSS = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_BossFrames.lua")
local PETS = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_PetFrames.lua")
local MAIN = ReadSource("EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua")
local OPTS = ReadSource("EllesmereUIOptions/RaidFrames_Options/VisualIndicators_Options.lua")
local RFOPTS = ReadSource("EllesmereUIOptions/EUI_RaidFrames_Options.lua")

-------------------------------------------------------------------------------
-- The world: the Dark Mode palette with its generation, the profile, buttons
-- that log what is written to them
-------------------------------------------------------------------------------
local palette = { fill = { 0.10, 0.11, 0.12, 0.9 }, bg = { 0.30, 0.31, 0.32, 0.8 } }
local EllesmereUI = { _dmGen = 1 }
local toggles = {}
function EllesmereUI.RegisterDarkModeToggle(provider) toggles[#toggles + 1] = provider end
function EllesmereUI.GetDarkModeFill() return palette.fill[1], palette.fill[2], palette.fill[3], palette.fill[4] end
function EllesmereUI.GetDarkModeBg() return palette.bg[1], palette.bg[2], palette.bg[3], palette.bg[4] end
function EllesmereUI.GetFontPath() return "font" end
function EllesmereUI.GetFontOutlineFlag() return "" end
local refreshes = 0
function EllesmereUI:RefreshPage() refreshes = refreshes + 1 end

local db = { profile = { friendlyBoss = {}, petFrames = {} } }
local ns = { EllesmereUI = EllesmereUI, RF_TEXT_STYLE_N = 3 }
-- Textured Background, the fill axis and Inverted Fill as the settings under test say (texBg,
-- vert, inv): the swap marks the background with its texture path and clears the mark, and the
-- orientation call turns the bar, as the real ones do.
function ns.RF_TexBgTint(bg, path) bg._rfTexBgPath = path or nil end
function ns.RF_TexBgPath(s) return s.texBg end
function ns.RF_IsVerticalFill(s) return s.vert or false end
function ns.RF_ApplyHealthOrientation(health, s)
    health.orient = s.vert and "VERTICAL" or "HORIZONTAL"
    health.inv = s.inv or false
end
function ns.RF_RefreshBarTints() end
function ns.RF_TextStyleInputs() end
function ns.RF_CompactOn() return false end
function ns.CapName(name) return name end
function ns.RF_TextPreview() end
local applies = 0
function ns.FB_Apply() applies = applies + 1 end

-- A button: the fill's colour and alpha writes in order (log), the background's colour writes,
-- and the background's anchors (all = the whole button; pts = its points; anchors counts every
-- anchor write). The bar answers for its axis and direction (orient, inv) and its fill texture.
local function NewFill(log)
    local fill = {}
    function fill:SetAlpha(a) log[#log + 1] = { "alpha", a } end
    function fill:SetHorizTile() end
    return fill
end
local function NewButton()
    local log = {}
    local health = { fill = NewFill(log) }
    function health:GetStatusBarTexture() return self.fill end
    function health:GetOrientation() return self.orient or "HORIZONTAL" end
    function health:GetReverseFill() return self.inv or false end
    function health:SetStatusBarColor(r, g, b, a) log[#log + 1] = { "color", r, g, b, a } end
    function health:SetStatusBarTexture() end
    function health:SetMinMaxValues() end
    function health:SetValue() end
    local bg = { n = 0, pts = {}, anchors = 0 }
    function bg:SetColorTexture(r, g, b, a)
        self.r, self.g, self.b, self.a = r, g, b, a
        self.n = self.n + 1
    end
    function bg:ClearAllPoints() self.all, self.allRel, self.pts = nil, nil, {} end
    function bg:SetAllPoints(rel)
        self.all, self.allRel = true, rel
        self.anchors = self.anchors + 1
    end
    function bg:SetPoint(point, rel, relPoint, x, y)
        self.pts[#self.pts + 1] = { point, rel, relPoint, x, y }
        self.anchors = self.anchors + 1
    end
    local b = { _health = health, _bg = bg, log = log }
    function b:SetSize() end
    function b:ClearAllPoints() end
    function b:SetPoint() end
    function b:SetParent(p) self.parent = p end
    function b:GetParent() return self.parent end
    function b:SetFrameStrata() end
    function b:GetFrameStrata() return "MEDIUM" end
    function b:Show() end
    return b
end
local function Reset(b)
    for i = #b.log, 1, -1 do b.log[i] = nil end
end
-- The fill's alpha after the writes so far: the colour's alpha and SetAlpha are one slot.
local function FinalAlpha(b)
    local e = b.log[#b.log]
    if not e then return nil end
    return e[1] == "alpha" and e[2] or e[5]
end
local function Same(a, b) return math.abs(a - b) < 1e-9 end
local function IsDarkFill(b)
    local l = b.log
    return #l == 2 and l[1][1] == "color" and Same(l[1][2], palette.fill[1]) and Same(l[1][3], palette.fill[2])
        and Same(l[1][4], palette.fill[3]) and l[1][5] == 1 and l[2][1] == "alpha" and Same(l[2][2], palette.fill[4])
end
local function IsOwnFill(b, r, g, bl, a)
    local l = b.log
    return #l == 2 and l[1][1] == "alpha" and l[1][2] == 1 and l[2][1] == "color" and Same(l[2][2], r)
        and Same(l[2][3], g) and Same(l[2][4], bl) and Same(l[2][5], a)
end
local function BgIsDark(b)
    return b._bg.n > 0 and Same(b._bg.r, palette.bg[1]) and Same(b._bg.g, palette.bg[2])
        and Same(b._bg.b, palette.bg[3]) and Same(b._bg.a, palette.bg[4])
end
local function BgIs(b, r, g, bl, a)
    return b._bg.n > 0 and Same(b._bg.r, r) and Same(b._bg.g, g) and Same(b._bg.b, bl) and Same(b._bg.a, a)
end

-------------------------------------------------------------------------------
-- The real pieces
-------------------------------------------------------------------------------
local FB = { buttons = {}, txs = setmetatable({}, { __mode = "k" }), src = setmetatable({}, { __mode = "k" }) }
FB.Settings = function() return db.profile.friendlyBoss end
FB.SizeVisuals = function() end
FB.StyleBorder = function() end
FB.Pitch = function() return 2 end
FB.BuildVisuals = function(f)
    local b = NewButton()
    for k, v in pairs(b) do f[k] = v end
    FB.txs[f] = {}
end
local PF = { DEFAULT_BG = { r = 17 / 255, g = 17 / 255, b = 17 / 255 }, pv = {}, styledGen = {}, ownerOf = {} }
PF.Raw = function() return db.profile.petFrames end
PF.PvStyle = function() return PF.pvStyle end
PF.PV_PETS = { { name = "Felhunter", hp = 100 } }

local HEAD = "local ns, FB, PF, db, EllesmereUI, PixelSnap, ResolveHealthTexture, UIParent, CreateFrame, I, GetFFD = ...\n"
local UIParent = { GetEffectiveScale = function() return 1 end }
local function Load(text, name)
    return assert(loadstring(HEAD .. text, "=" .. name))(ns, FB, PF, db, EllesmereUI,
        function(v) return v end, function() return "tex" end, UIParent,
        function() return {} end, { FFD = {} }, function() return {} end)
end

local helpers = CutOpt(BOSS, "FB.Dark = function(s)", "-- Bar colour. An owner drawing in Dark Mode")
check(helpers ~= nil, "the boss group has no Dark Mode gate of its own (FB.Dark)")
if helpers then Load(helpers, "BossFrames.lua (the gate)") end
Load(Cut(BOSS, "FB.PaintBarColor = function(b, owner, s, pv)", "-- Text state of a button built with its texts"), "BossFrames.lua (the painter)")
Load(Cut(BOSS, "FB.StyleVisuals = function(b, s, w, h, texPath, bgc", "-- A container's one anchor point"), "BossFrames.lua (the styler)")
Load(Cut(BOSS, "FB.ApplyStyle = function(owner)", "-- The size-dependent part of FB.StyleVisuals"), "BossFrames.lua (ApplyStyle)")
-- the pets' own tables (owner tokens, the default background and fill colour)
Load(Cut(PETS, "PF.OWNER_OF = ", "-- Beside Owner pet -> the party frame it sits beside"), "PetFrames.lua (the tables)")
local petGate = CutOpt(PETS, "PF.Dark = function(s)", "-- The Party and Raid tabs each keep their own")
check(petGate ~= nil, "the pets have no Dark Mode gate of their own (PF.Dark)")
if petGate then Load(petGate, "PetFrames.lua (the gate)") end
Load(Cut(PETS, "PF.StyleHeaderButton = function(b)", "-- Every setting the button styler reads"), "PetFrames.lua (StyleHeaderButton)")
Load(Cut(PETS, "PF.STYLE_N = ", "-- True when the inputs differ from the ones last styled under key"), "PetFrames.lua (StyleInputs)")
Load(Cut(PETS, "PF.OwnerLayout = function(restyle)", "-- Your own pet: beside the self button"), "PetFrames.lua (OwnerLayout)")
Load(Cut(PETS, "PF.pvc = {}", "-- Beside Owner preview: the pet size, side and gap"), "PetFrames.lua (the preview)")

-- The styler, spied on for the Dark Mode flag its callers hand it.
local styledDark
do
    local real = FB.StyleVisuals
    FB.StyleVisuals = function(b, s, w, h, texPath, bgc, dark)
        styledDark = dark
        return real(b, s, w, h, texPath, bgc, dark)
    end
end

local DARK = { healthColorMode = "dark", healthBarOpacity = 60, bgDarkness = 70, customBgColor = { r = 0.5, g = 0.4, b = 0.3 } }
local CLASS = { healthColorMode = "class", healthBarOpacity = 60, bgDarkness = 70, customBgColor = { r = 0.5, g = 0.4, b = 0.3 } }
local GREEN = { 23 / 255, 172 / 255, 49 / 255 }

-------------------------------------------------------------------------------
-- 1. the pets follow the frames they are styled from
-------------------------------------------------------------------------------
do
    local b = NewButton()
    FB.PaintBarColor(b, PF, DARK)
    check(IsDarkFill(b), "a pet under Dark Mode: the fill is not the palette's colour at 1 followed by the Dark Mode Fill Opacity")
    check(FinalAlpha(b) and Same(FinalAlpha(b), 0.9), "a pet under Dark Mode draws at " .. tostring(FinalAlpha(b)) .. ", not the Dark Mode Fill Opacity (0.9)")
    check(BgIsDark(b), "a pet under Dark Mode keeps its own background")
    -- the frames' own colour mode: Pet Health Color (the default green) at Fill Opacity
    Reset(b)
    local n = b._bg.n
    FB.PaintBarColor(b, PF, CLASS)
    check(IsOwnFill(b, GREEN[1], GREEN[2], GREEN[3], 0.6), "a pet outside Dark Mode is not the default green at Fill Opacity")
    check(b._bg.n == n, "the paint writes a background outside Dark Mode")
    -- a saved Pet Health Color
    db.profile.petFrames.healthColor = { r = 0.2, g = 0.4, b = 0.6 }
    Reset(b)
    FB.PaintBarColor(b, PF, CLASS)
    check(IsOwnFill(b, 0.2, 0.4, 0.6, 0.6), "a saved Pet Health Color is not painted")
    Reset(b)
    FB.PaintBarColor(b, PF, DARK)
    check(IsDarkFill(b), "a saved Pet Health Color wins over Dark Mode")
    db.profile.petFrames.healthColor = nil

    -- a Fill Color of the pets' own decides, whatever the frames do
    local pet = db.profile.petFrames
    pet.healthColorMode = "custom"
    Reset(b)
    n = b._bg.n
    FB.PaintBarColor(b, PF, DARK)
    check(IsOwnFill(b, GREEN[1], GREEN[2], GREEN[3], 0.6), "pets with Custom Color picked turn dark with the frames")
    check(b._bg.n == n, "pets with Custom Color picked get the Dark Mode background from the paint")
    check(PF.Dark(DARK) == false and PF.Dark(CLASS) == false, "pets with Custom Color picked count as drawing dark")
    pet.healthColorMode = "dark"
    Reset(b)
    FB.PaintBarColor(b, PF, CLASS)
    check(IsDarkFill(b) and BgIsDark(b), "pets with Dark Mode picked do not draw dark beside frames in another mode")
    check(PF.Dark(CLASS) == true and PF.Dark(DARK) == true, "pets with Dark Mode picked do not count as drawing dark")
    pet.healthColorMode = nil
    check(PF.Dark(DARK) == true and PF.Dark(CLASS) == false, "pets with nothing picked do not follow the frames")
    -- what the options show and compare a pick with: the mode following gives, per tab
    PF.PartySource = function() return DARK end
    ns._scaledProfile = CLASS
    check(ns.PF_FollowMode("party") == "dark" and ns.PF_FollowMode("raid") == "custom", "the follow mode is not each tab's own frames'")
    PF.PartySource = function() return CLASS end
    ns._scaledProfile = DARK
    check(ns.PF_FollowMode("party") == "custom" and ns.PF_FollowMode("raid") == "dark", "the follow mode does not move with the frames' Fill Color")
    ns._scaledProfile = nil
    db.profile.healthColorMode = "dark"
    check(ns.PF_FollowMode("raid") == "dark", "the raid follow mode does not fall back to the profile")
    db.profile.healthColorMode = nil
end

-------------------------------------------------------------------------------
-- 2. the boss group keeps Boss Health Color unless Follow Dark Mode is on
-------------------------------------------------------------------------------
do
    local fb = db.profile.friendlyBoss
    fb.healthColor = { r = 0.9, g = 0.1, b = 0.1 }
    local b = NewButton()
    FB.PaintBarColor(b, FB, DARK)
    check(IsOwnFill(b, 0.9, 0.1, 0.1, 0.6), "a boss frame turns dark under raid Dark Mode with Follow Dark Mode off")
    check(b._bg.n == 0, "a boss frame's background turns dark with Follow Dark Mode off")
    fb.followDarkMode = false
    Reset(b)
    FB.PaintBarColor(b, FB, DARK)
    check(IsOwnFill(b, 0.9, 0.1, 0.1, 0.6), "Follow Dark Mode saved as false still darkens the boss frames")
    fb.followDarkMode = true
    Reset(b)
    FB.PaintBarColor(b, FB, DARK)
    check(IsDarkFill(b) and BgIsDark(b), "a boss frame with Follow Dark Mode on does not draw dark under raid Dark Mode")
    Reset(b)
    FB.PaintBarColor(b, FB, CLASS)
    check(IsOwnFill(b, 0.9, 0.1, 0.1, 0.6), "Follow Dark Mode darkens the boss frames while the raid frames are not in Dark Mode")
    -- the pets do not read the boss group's option
    fb.followDarkMode = nil
    local p = NewButton()
    FB.PaintBarColor(p, PF, DARK)
    check(IsDarkFill(p), "the pets wait for the boss group's Follow Dark Mode")
    fb.healthColor = nil
    check(MAIN:find("followDarkMode", 1, true) == nil, "Follow Dark Mode has a defaults entry (absent must read as off)")
end

-------------------------------------------------------------------------------
-- 3. the dark background: the styler's, and the paint's once the palette changed
-------------------------------------------------------------------------------
do
    local b = NewButton()
    FB.PaintBarColor(b, PF, DARK)
    FB.PaintBarColor(b, PF, DARK)
    FB.PaintBarColor(b, PF, DARK)
    check(b._bg.n == 1, "three dark paints wrote the background " .. b._bg.n .. " times (the palette did not change)")
    -- a colour edit: the generation moves, the next paint takes the new colour
    palette.bg = { 0.01, 0.02, 0.03, 1 }
    EllesmereUI._dmGen = EllesmereUI._dmGen + 1
    FB.PaintBarColor(b, PF, DARK)
    check(b._bg.n == 2 and BgIsDark(b), "a Dark Mode colour edit does not reach the background at the next paint")
    -- the styler always writes: dark, although the paint's stamp is current
    FB.StyleVisuals(b, DARK, 100, 40, "tex", DARK.customBgColor, true)
    check(b._bg.n == 3 and BgIsDark(b), "the styler leaves the dark background to the paint (its texture swap needs the write)")
    FB.PaintBarColor(b, PF, DARK)
    check(b._bg.n == 3, "the paint writes the dark background again right after the styler did")
    -- the styler outside Dark Mode: the frames' own background, and the next dark paint writes again
    FB.StyleVisuals(b, CLASS, 100, 40, "tex", CLASS.customBgColor, false)
    check(BgIs(b, 0.5, 0.4, 0.3, 0.7), "the styler outside Dark Mode does not write the frames' own background")
    FB.PaintBarColor(b, PF, DARK)
    check(BgIsDark(b), "a dark paint after the styler wrote the frames' own background keeps that background")
    -- the styler follows the flag it is handed, not the settings' mode (a boss frame not following)
    local o = NewButton()
    FB.StyleVisuals(o, DARK, 100, 40, "tex", DARK.customBgColor, false)
    check(BgIs(o, 0.5, 0.4, 0.3, 0.7), "the styler darkens a button whose owner does not draw in Dark Mode")
end

-------------------------------------------------------------------------------
-- 4. every caller hands the styler its owner's answer
-------------------------------------------------------------------------------
do
    -- the boss group
    local fb = db.profile.friendlyBoss
    FB.built, FB.container = true, { SetSize = function() end }
    FB.buttons = { NewButton(), NewButton() }
    ns._scaledProfile = DARK
    fb.followDarkMode = nil
    styledDark = nil
    FB.ApplyStyle()
    check(styledDark == false and BgIs(FB.buttons[1], 0.5, 0.4, 0.3, 0.7), "the boss group restyles dark with Follow Dark Mode off")
    fb.followDarkMode = true
    FB.ApplyStyle()
    check(styledDark == true and BgIsDark(FB.buttons[2]), "the boss group does not restyle dark with Follow Dark Mode on")
    ns._scaledProfile = CLASS
    FB.ApplyStyle()
    check(styledDark == false, "the boss group restyles dark outside raid Dark Mode")
    fb.followDarkMode = nil

    -- a header pet
    PF.w, PF.h, PF.styleGen = 100, 40, 1
    local src = DARK
    PF.StyleSource = function() return src end
    local b = NewButton()
    PF.StyleHeaderButton(b)
    check(styledDark == true and BgIsDark(b), "a header pet's background is not dark right after its restyle under Dark Mode")
    src = CLASS
    PF.StyleHeaderButton(b)
    check(styledDark == false and BgIs(b, 0.5, 0.4, 0.3, 0.7), "a header pet keeps the dark background after Dark Mode is turned off")

    -- the Beside Owner pets
    PF.Geometry = function() return 100, 40, 2 end
    PF.ResolveOwnerSide = function() return "right", 0 end
    PF.PartySource = function() return src end
    PF.StyleChanged = function() return true end
    PF.OwnerPoint = function() end
    PF.PlaceSelfPet = function() end
    PF.NotifyReserve = function() end
    PF.ownerButtons = { NewButton() }
    src = DARK
    PF.OwnerLayout(true)
    check(styledDark == true and BgIsDark(PF.ownerButtons[1]), "a Beside Owner pet's background is not dark right after its restyle under Dark Mode")
    src = CLASS
    PF.OwnerLayout(true)
    check(styledDark == false and BgIs(PF.ownerButtons[1], 0.5, 0.4, 0.3, 0.7), "a Beside Owner pet keeps the dark background after Dark Mode is turned off")

    -- the pets' restyle inputs carry the Dark Mode state, so a flip restyles them
    local t1, t2 = {}, {}
    PF.StyleInputs(t1, DARK, "tex")
    PF.StyleInputs(t2, CLASS, "tex")
    check(PF.STYLE_N == 27 + ns.RF_TEXT_STYLE_N, "the pets' restyle inputs changed length: " .. tostring(PF.STYLE_N))
    check(t1[PF.STYLE_N] == true and t2[PF.STYLE_N] == false, "the pets' restyle inputs do not carry the Dark Mode state")
    check(t1[PF.STYLE_N - 1] == nil and t2[PF.STYLE_N - 1] == nil, "the Textured Background input moved")
    -- a pick of the pets' own is part of that state: picking Custom Color under dark frames restyles
    db.profile.petFrames.healthColorMode = "custom"
    PF.StyleInputs(t1, DARK, "tex")
    check(t1[PF.STYLE_N] == false, "a pet Fill Color pick does not reach the restyle inputs")
    db.profile.petFrames.healthColorMode = "dark"
    PF.StyleInputs(t2, CLASS, "tex")
    check(t2[PF.STYLE_N] == true, "a pet Dark Mode pick does not reach the restyle inputs")
    db.profile.petFrames.healthColorMode = nil
end

-------------------------------------------------------------------------------
-- 5. the options preview pets paint as the real pets do
-------------------------------------------------------------------------------
do
    local parent = { GetFrameStrata = function() return "MEDIUM" end }
    local c = PF.PvColors(DARK)
    styledDark = nil
    local f = PF.PvFrame(1, parent, DARK, 100, 40, c)
    check(styledDark == true, "the preview pets are not styled dark under Dark Mode")
    check(IsDarkFill(f) and BgIsDark(f), "the preview pets keep Pet Health Color under Dark Mode")
    Reset(f)
    c = PF.PvColors(CLASS)
    f = PF.PvFrame(1, parent, CLASS, 100, 40, c)
    check(styledDark == false, "the preview pets are styled dark outside Dark Mode")
    check(IsOwnFill(f, GREEN[1], GREEN[2], GREEN[3], 0.6) and BgIs(f, 0.5, 0.4, 0.3, 0.7), "the preview pets outside Dark Mode are not the default green on the frames' background")
    db.profile.petFrames.healthColor = { r = 0.2, g = 0.4, b = 0.6 }
    Reset(f)
    f = PF.PvFrame(1, parent, CLASS, 100, 40, PF.PvColors(CLASS))
    check(IsOwnFill(f, 0.2, 0.4, 0.6, 0.6), "the preview pets do not show a saved Pet Health Color")
    db.profile.petFrames.healthColor = nil
end

-------------------------------------------------------------------------------
-- 6. the options: the Follow Dark Mode toggle and the Boss Health Color swatch
-------------------------------------------------------------------------------
do
    local fb = db.profile.friendlyBoss
    local function FBSet() return fb end
    local rowText = CutOpt(OPTS, '                    { type="toggle", label="Follow Dark Mode",', "                },\n            })")
    check(rowText ~= nil, "the Friendly Boss Group cog has no Follow Dark Mode toggle")
    if rowText then
        local row = assert(loadstring("local FBSet, ns, EllesmereUI = ...\nreturn " .. rowText:gsub(",%s*$", ""), "=the toggle"))(FBSet, ns, EllesmereUI)
        check(type(row.tooltip) == "string" and #row.tooltip > 0, "the toggle has no tooltip")
        fb.followDarkMode = nil
        check(row.get() == false, "the toggle reads on while unset")
        applies, refreshes = 0, 0
        row.set(true)
        check(fb.followDarkMode == true and row.get() == true, "turning the toggle on does not save it")
        check(applies == 1, "turning the toggle on does not re-apply the boss group")
        check(refreshes == 1, "turning the toggle on does not refresh the page (the swatch keeps its old state)")
        row.set(false)
        check(fb.followDarkMode == nil and row.get() == false, "turning the toggle off saves a value (off is the absent key)")
        check(applies == 2 and refreshes == 2, "turning the toggle off does not re-apply and refresh")
    end

    local darkText = CutOpt(OPTS, "        local function FBDark()", "        row, h = W:DualRow(parent, y,")
    check(darkText ~= nil, "the options do not ask whether the boss group draws in Dark Mode (FBDark)")
    local FBDark = darkText and assert(loadstring("local FBSet, db = ...\n" .. darkText .. "\nreturn FBDark", "=FBDark"))(FBSet, db)
    if FBDark then
        fb.followDarkMode, db.profile.healthColorMode = true, "dark"
        check(FBDark() == true, "the options do not see the boss group drawing dark")
        db.profile.healthColorMode = "class"
        check(FBDark() == false, "the options see the boss group dark outside raid Dark Mode")
        fb.followDarkMode, db.profile.healthColorMode = nil, "dark"
        check(FBDark() == false, "the options see the boss group dark with Follow Dark Mode off")
    end

    local swatchText = Cut(OPTS, "            local function UpdateFBSwatch()", "            EllesmereUI.RegisterWidgetRefresh(UpdateFBSwatch)")
    local enabled, dark = true, false
    local swatch, block, label = { a = 1 }, { shown = false }, { a = 1 }
    function swatch:SetAlpha(a) self.a = a end
    function block:SetShown(v) self.shown = v end
    function label:SetAlpha(a) self.a = a end
    local Update = assert(loadstring("local FBEnabled, FBDark, swatch, swatchBlock, rgn = ...\n" .. swatchText .. "\nreturn UpdateFBSwatch", "=UpdateFBSwatch"))(
        function() return enabled end, function() return dark end, swatch, block, { _label = label })
    Update()
    check(swatch.a == 1 and block.shown == false and label.a == 1, "Boss Health Color is greyed while the group shows its own colour")
    dark = true
    Update()
    check(swatch.a == 0.3 and block.shown == true and label.a == 0.3, "Boss Health Color stays live while the group draws in Dark Mode")
    dark, enabled = false, false
    Update()
    check(swatch.a == 0.3 and block.shown == true, "Boss Health Color stays live while the group is off")
    -- the greyed swatch says why, in the words of the frames' own Dark Mode note (one locale key)
    check(OPTS:find("EllesmereUI.ShowWidgetTooltip(swatch, FBDark() and FB_DARK_TIP or FB_DISABLED_TIP)", 1, true) ~= nil,
        "the greyed swatch does not say that Dark Mode is why")
    local tip = OPTS:match('local FB_DARK_TIP = "([^"]+)"')
    local shared = RFOPTS:match('local DARK_TIP = "([^"]+)"')
    check(tip ~= nil and tip == shared, "the swatch's Dark Mode note is not the frames' own (a second locale key)")
end

-------------------------------------------------------------------------------
-- 7. the background's extent: in Dark Mode the part the fill does not paint
-------------------------------------------------------------------------------
do
    -- Where the background sits: "all" (the whole button), or its points, each as
    -- point>bar|fill.relativePoint@x,y.
    local function Extent(b)
        local bg = b._bg
        if bg.all then return (#bg.pts == 0 and bg.allRel == nil) and "all" or "all and more" end
        local out = {}
        for i, p in ipairs(bg.pts) do
            local rel = (p[2] == b._health and "bar") or (p[2] ~= nil and p[2] == b._health.fill and "fill") or "?"
            out[i] = ("%s>%s.%s@%s,%s"):format(tostring(p[1]), rel, tostring(p[3]), tostring(p[4]), tostring(p[5]))
        end
        return #out > 0 and table.concat(out, " ") or "nowhere"
    end
    local function Turn(b, vert, inv)
        b._health.orient, b._health.inv = vert and "VERTICAL" or "HORIZONTAL", inv
    end
    local H = "TOPLEFT>fill.TOPRIGHT@0,0 BOTTOMRIGHT>bar.BOTTOMRIGHT@0,0"
    local HI = "TOPLEFT>bar.TOPLEFT@0,0 BOTTOMRIGHT>fill.BOTTOMLEFT@0,0"
    local V = "TOPLEFT>bar.TOPLEFT@0,0 BOTTOMRIGHT>fill.TOPRIGHT@0,0"
    local VI = "TOPLEFT>fill.BOTTOMLEFT@0,0 BOTTOMRIGHT>bar.BOTTOMRIGHT@0,0"
    local WANT = {
        { false, false, H, "a bar filling to the right" },
        { false, true, HI, "a bar under Inverted Fill" },
        { true, false, V, "a vertical bar" },
        { true, true, VI, "a vertical bar under Inverted Fill" },
    }
    for _, w in ipairs(WANT) do
        local b = NewButton()
        Turn(b, w[1], w[2])
        FB.PaintBarColor(b, PF, DARK)
        check(Extent(b) == w[3], w[4] .. " in Dark Mode: the background sits at " .. Extent(b))
        -- the same bar outside Dark Mode: the whole button, whatever its direction
        local o = NewButton()
        Turn(o, w[1], w[2])
        FB.PaintBarColor(o, PF, CLASS)
        check(Extent(o) == "all", w[4] .. " outside Dark Mode: the background sits at " .. Extent(o))
    end

    -- nothing moved: no anchor is written again, in or out of Dark Mode
    local b = NewButton()
    FB.PaintBarColor(b, PF, DARK)
    local n = b._bg.anchors
    FB.PaintBarColor(b, PF, DARK)
    FB.PaintBarColor(b, PF, DARK)
    check(b._bg.anchors == n, "a dark paint anchors the background again although nothing moved (" .. (b._bg.anchors - n) .. " writes)")
    FB.PaintBarColor(b, PF, CLASS)
    check(Extent(b) == "all", "leaving Dark Mode leaves the background at " .. Extent(b))
    n = b._bg.anchors
    FB.PaintBarColor(b, PF, CLASS)
    FB.PaintBarColor(b, PF, CLASS)
    check(b._bg.anchors == n, "a paint outside Dark Mode anchors the background again although nothing moved")
    FB.PaintBarColor(b, PF, DARK)
    check(Extent(b) == H, "back in Dark Mode the background sits at " .. Extent(b))

    -- each thing the extent hangs on moves it at the next paint: the axis, the direction, the
    -- fill texture itself
    Turn(b, true, false)
    FB.PaintBarColor(b, PF, DARK)
    check(Extent(b) == V, "a bar turned vertical keeps the background at " .. Extent(b))
    Turn(b, true, true)
    FB.PaintBarColor(b, PF, DARK)
    check(Extent(b) == VI, "a vertical bar turned to Inverted Fill keeps the background at " .. Extent(b))
    Turn(b, false, true)
    FB.PaintBarColor(b, PF, DARK)
    check(Extent(b) == HI, "an inverted bar turned horizontal keeps the background at " .. Extent(b))
    Turn(b, false, false)
    FB.PaintBarColor(b, PF, DARK)
    check(Extent(b) == H, "a bar turned back keeps the background at " .. Extent(b))
    b._health.fill = NewFill(b.log)
    FB.PaintBarColor(b, PF, DARK)
    check(Extent(b) == H, "a new fill texture: the background hangs off " .. Extent(b))
    -- a bar with no fill texture: the whole button, and no error
    b._health.fill = nil
    check(pcall(FB.PaintBarColor, b, PF, DARK) and Extent(b) == "all", "a dark bar with no fill texture: the background sits at " .. Extent(b))

    -- Textured Background never moves: the whole button in Dark Mode too
    local TEXDARK = { healthColorMode = "dark", healthBarOpacity = 60, bgDarkness = 70, texBg = "bgtex" }
    local t = NewButton()
    FB.StyleVisuals(t, TEXDARK, 100, 40, "tex", DARK.customBgColor, true)
    check(Extent(t) == "all", "Textured Background in Dark Mode: the styler puts the background at " .. Extent(t))
    FB.PaintBarColor(t, PF, TEXDARK)
    check(Extent(t) == "all", "Textured Background in Dark Mode: the paint puts the background at " .. Extent(t))
    -- turned off again, the flat dark background takes the part the fill leaves
    FB.StyleVisuals(t, DARK, 100, 40, "tex", DARK.customBgColor, true)
    check(Extent(t) == H, "Textured Background turned off in Dark Mode: the background sits at " .. Extent(t))

    -- the styler follows the bar it has just turned, and the flag it is handed
    local VDARK = { healthColorMode = "dark", healthBarOpacity = 60, bgDarkness = 70, vert = true }
    local VIDARK = { healthColorMode = "dark", healthBarOpacity = 60, bgDarkness = 70, vert = true, inv = true }
    local s = NewButton()
    FB.StyleVisuals(s, DARK, 100, 40, "tex", DARK.customBgColor, true)
    check(Extent(s) == H, "the styler in Dark Mode leaves the background at " .. Extent(s))
    FB.StyleVisuals(s, VDARK, 100, 40, "tex", DARK.customBgColor, true)
    check(Extent(s) == V, "the styler turned the bar vertical and left the background at " .. Extent(s))
    FB.StyleVisuals(s, VIDARK, 100, 40, "tex", DARK.customBgColor, true)
    check(Extent(s) == VI, "the styler inverted the vertical bar and left the background at " .. Extent(s))
    n = s._bg.anchors
    FB.PaintBarColor(s, PF, VIDARK)
    check(s._bg.anchors == n, "the paint after the styler anchors the background again")
    FB.StyleVisuals(s, VIDARK, 100, 40, "tex", DARK.customBgColor, false)
    check(Extent(s) == "all", "the styler for an owner not drawing dark leaves the background at " .. Extent(s))
    FB.StyleVisuals(s, VIDARK, 100, 40, "tex", DARK.customBgColor, nil)
    check(Extent(s) == "all", "the styler handed no Dark Mode flag leaves the background at " .. Extent(s))

    -- the boss group: only while it follows Dark Mode
    local fb = db.profile.friendlyBoss
    fb.followDarkMode = nil
    local boss = NewButton()
    FB.PaintBarColor(boss, FB, DARK)
    check(Extent(boss) == "all", "a boss frame not following Dark Mode: the background sits at " .. Extent(boss))
    fb.followDarkMode = true
    FB.PaintBarColor(boss, FB, DARK)
    check(Extent(boss) == H, "a boss frame following Dark Mode: the background sits at " .. Extent(boss))
    fb.followDarkMode = nil

    -- pets with a Fill Color of their own beside dark frames keep the whole button
    db.profile.petFrames.healthColorMode = "custom"
    local own = NewButton()
    FB.PaintBarColor(own, PF, DARK)
    check(Extent(own) == "all", "pets with Custom Color picked beside dark frames: the background sits at " .. Extent(own))
    db.profile.petFrames.healthColorMode = nil

    -- the options preview pets
    local parent = { GetFrameStrata = function() return "MEDIUM" end }
    local f = PF.PvFrame(1, parent, DARK, 100, 40, PF.PvColors(DARK))
    check(Extent(f) == H, "a preview pet in Dark Mode: the background sits at " .. Extent(f))
    f = PF.PvFrame(1, parent, CLASS, 100, 40, PF.PvColors(CLASS))
    check(Extent(f) == "all", "a preview pet outside Dark Mode: the background sits at " .. Extent(f))
end

-------------------------------------------------------------------------------
-- 8. the global Dark Mode toggle and the pets' own Fill Color
-------------------------------------------------------------------------------
do
    local RELOAD = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_Reload.lua")
    local reloads, partyReloads = 0, 0
    ns.ReloadFrames = function() reloads = reloads + 1 end
    ns.ReloadPartyFrames = function() partyReloads = partyReloads + 1 end
    Load(Cut(RELOAD, "EllesmereUI.RegisterDarkModeToggle({", "-- Lightweight resize: only changes button"), "Reload.lua (the toggle)")
    local toggle = toggles[1]
    check(#toggles == 1 and toggle and toggle.id == "raidFrames", "the raid frames register no Dark Mode toggle")
    local saved = db.profile
    local function Fresh(pet)
        db.profile = { healthColorMode = "class", friendlyBoss = {}, petFrames = pet }
        return db.profile
    end
    if toggle then
        -- pets that follow: nothing is written for them, and they follow both ways
        local p = Fresh({})
        check(toggle.isOn() == false, "the toggle reads on beside class coloured frames")
        toggle.setOn(true)
        check(p.healthColorMode == "dark" and toggle.isOn() == true, "the toggle does not turn the frames dark")
        check(next(p.petFrames) == nil, "the toggle writes a Fill Color for pets that only follow")
        check(PF.Dark(p) == true, "pets that follow are not dark after the toggle")
        check(reloads == 1 and partyReloads == 1, "the toggle does not restyle the frames once (" .. reloads .. ", " .. partyReloads .. ")")
        toggle.setOn(false)
        check(p.healthColorMode == "class" and next(p.petFrames) == nil, "turning the toggle off writes for pets that only follow")
        check(PF.Dark(p) == false, "pets that follow stay dark after the toggle is turned off")

        -- a picked Fill Color flips with the frames and comes back
        for _, mode in ipairs({ "class", "classic", "custom", "customDynamic" }) do
            p = Fresh({ healthColorMode = mode })
            toggle.setOn(true)
            check(p.petFrames.healthColorMode == "dark" and PF.Dark(p) == true, "pets with " .. mode .. " picked stay " .. tostring(p.petFrames.healthColorMode) .. " under the toggle")
            -- turned on again while on: the remembered pick is not overwritten
            toggle.setOn(true)
            toggle.setOn(false)
            check(p.petFrames.healthColorMode == mode, "pets with " .. mode .. " picked come back as " .. tostring(p.petFrames.healthColorMode))
            check(p.petFrames._darkPrevHealthColorMode == nil, "the pets' remembered pick outlives the toggle (" .. mode .. ")")
            check(PF.Dark(p) == false, "pets with " .. mode .. " picked stay dark after the toggle is turned off")
        end

        -- Dark Mode picked for the pets by hand: off means off everywhere, so they go back to
        -- following (frames that are no longer dark)
        p = Fresh({ healthColorMode = "dark" })
        toggle.setOn(true)
        check(p.petFrames.healthColorMode == "dark" and p.petFrames._darkPrevHealthColorMode == nil, "pets already dark get a remembered pick")
        toggle.setOn(false)
        check(p.petFrames.healthColorMode == nil and PF.Dark(p) == false, "pets with Dark Mode picked stay dark after the toggle is turned off")

        -- a Fill Color picked while the toggle is on is the player's: off leaves it alone
        p = Fresh({ healthColorMode = "class" })
        toggle.setOn(true)
        p.petFrames.healthColorMode = "custom"
        toggle.setOn(false)
        check(p.petFrames.healthColorMode == "custom", "a Fill Color picked while the toggle was on is put back to the older pick")
        check(p.petFrames._darkPrevHealthColorMode == nil, "the older pick is kept after the toggle went off")

        -- a profile with no pet settings: nothing breaks, the frames still flip
        p = Fresh(nil)
        check(pcall(toggle.setOn, true) and p.healthColorMode == "dark", "the toggle fails on a profile with no pet settings")
        check(pcall(toggle.setOn, false) and p.healthColorMode == "class", "turning the toggle off fails on a profile with no pet settings")
        check(p.petFrames == nil, "the toggle makes a pet settings table")

        -- the frames' own keys flip as they did
        p = Fresh({})
        p.healthColorMode, p.party_healthColorMode, p.partyTargetHealthColorMode = "customDynamic", "classic", "custom"
        toggle.setOn(true)
        check(p.healthColorMode == "dark" and p.party_healthColorMode == "dark" and p.partyTargetHealthColorMode == "dark", "the toggle no longer turns the raid, party and party target frames dark")
        toggle.setOn(false)
        check(p.healthColorMode == "customDynamic" and p.party_healthColorMode == "classic" and p.partyTargetHealthColorMode == "custom", "the toggle no longer puts the frames' Fill Colors back")
        check(p._darkPrevHealthColorMode == nil and p._darkPrevPartyHealthColorMode == nil and p._darkPrevPartyTargetHealthColorMode == nil, "the frames' remembered Fill Colors outlive the toggle")
    end
    db.profile = saved
    ns.ReloadFrames, ns.ReloadPartyFrames = nil, nil
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_rf_pet_dark_mode (%d checks)"):format(count))
