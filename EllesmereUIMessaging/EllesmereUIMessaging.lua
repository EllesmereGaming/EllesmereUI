if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIMessaging: whispers in one tabbed window, in the EllesmereUI look.
--
--  Core: settings, conversations, the whisper events, sending, and the
--  history store. The main chat is never touched: whispers keep showing in
--  every chat window set up for them; the whisper window is an extra view.
--  The UI lives in Window.lua / History.lua / Minimap.lua, the settings page
--  in Options.lua, the friends-window and reply integration in Intercept.lua.
--
--  Secret values (12.x): while the client hides chat contents from addons
--  (encounters and other restricted moments) every argument of a whisper
--  event can be a secret. Such a whisper can't be read then; it is queued by
--  its chat line and filed into the window once the lockdown lifts (see the
--  lockdown queue).
-------------------------------------------------------------------------------
local ADDON_NAME, addonNS = ...
local ns = addonNS.Whispers or {}
addonNS.Whispers = ns
EllesmereUI._ModuleNS = EllesmereUI._ModuleNS or {}
EllesmereUI._ModuleNS["EllesmereUIMessaging"] = ns

ns.MEDIA = "Interface\\AddOns\\EllesmereUIMessaging\\Media\\"
ns.EUI_ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

-- Message directions
ns.IN, ns.OUT, ns.SYSTEM = 1, 2, 3

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local DEFAULTS = {
    enabled = true,
    popup = "always",          -- "always" | "nocombat" | "never"
    sound = true,              -- play the whisper sound (the main chat's is skipped with it)
    flash = true,              -- flash the taskbar icon on an incoming whisper
    battleNet = true,          -- handle Battle.net whispers too
    minimap = { show = true, angle = 200 },   -- angle: its spot on the map's edge (degrees, 0 = right)
    -- Appearance: the EllesmereUI chat window's options and defaults, so the
    -- whisper window matches the chat out of the box and customizes the same way
    window = {
        -- "list": one window, conversations down the left; "windows": a window per person
        layout = "list",   -- "list" | "windows"
        width = 520, height = 320,
        point = nil,           -- { point, relativePoint, x, y } once moved
        sidebarWidth = 160,
        personSize = nil,      -- { w, h } shared by the per-person windows
        personPoints = nil,    -- [convo key] = { point, relativePoint, x, y }
        locked = false,
        -- panel
        bgColor = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
        -- the title bar: the EllesmereUI Damage Meters header (#1B1B1B, opaque)
        headerColor = { r = 0x1B / 255, g = 0x1B / 255, b = 0x1B / 255, a = 1 },
        -- the band behind the name / status / location lines: opaque, as the
        -- chat's combat log filter row
        headerBandColor = { r = 0.03, g = 0.045, b = 0.05, a = 1 },
        dividerUseAccent = false,
        dividerColor = { r = 1, g = 1, b = 1, a = 0.06 },
        border = false,
        borderUseAccent = false,
        borderColor = { r = 1, g = 1, b = 1, a = 0.18 },
        -- text
        font = "__global",     -- "__global" = the EllesmereUI chat font, or a font key
        outline = "__global",  -- "__global" | "none" | "outline" | "thick"
        fontSize = 12,
        timestamps = true,
        timestampFormat = "%H:%M ",
        chatColors = true,     -- whisper colors from the game's chat settings
        inColor = { r = 1, g = 0.5, b = 1 },
        outColor = { r = 1, g = 0.5, b = 1 },
        -- title: the fixed "Message Center" title of the title bar, as the Damage
        -- Meters' header title (accent, size 11)
        titleFontSize = 11,
        titleUseAccent = true,
        titleColor = { r = 1, g = 1, b = 1, a = 1 },
        -- tabs: a row under the title bar, as the EllesmereUI chat's tabs
        tabFontSize = 11,
        tabColor = { r = 0.03, g = 0.045, b = 0.05, a = 0.44 },
        tabColorActive = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
        tabTextColor = { r = 1, g = 1, b = 1, a = 0.65 },
        tabTextUseAccent = false,
        tabTextColorActive = { r = 1, g = 1, b = 1, a = 1 },
        underline = true,
        underlineUseAccent = true,
        underlineColor = { r = 0.05, g = 0.82, b = 0.61, a = 1 },
        -- title bar glyphs
        iconUseAccent = false,
        iconColor = { r = 1, g = 1, b = 1 },
    },
    history = {
        enabled = true,
        keep = 250,            -- messages kept per conversation
        days = 0,              -- delete conversations idle this many days (0 = never)
        replay = 30,           -- messages shown when a conversation opens
    },
}
ns.DEFAULTS = DEFAULTS

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.ResetSettings()
    local profile = ns.db.profile
    wipe(profile)
    CopyDefaults(DEFAULTS, profile)
    ns.Fire("SettingsChanged")
end

-------------------------------------------------------------------------------
--  Tiny callback hub (Core -> UI)
-------------------------------------------------------------------------------
local listeners = {}
function ns.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end
function ns.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        xpcall(list[i], geterrorhandler(), ...)
    end
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
local function IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end
ns.IsSecret = IsSecret

local function MyRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
end

-- "Name" or "Name-Realm" -> "Name-Realm"
local function FullName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = MyRealm()
    return realm ~= "" and (name .. "-" .. realm) or name
end
ns.FullName = FullName

-- What the window shows for a character: the realm only when it is not ours
function ns.ShortName(name)
    return Ambiguate and Ambiguate(name, "none") or name
end

-------------------------------------------------------------------------------
--  WoW Forever look: the whisper windows follow the Chat module's style. When
--  the chat renders Blizzard Style's WoW Forever variant, our windows wear
--  its Border Style frame (Slim / Slim Textured line, or Heavy Bronze) in
--  place of the 1px border, gold in place of the accent and tan glyphs.
--  Latched once (the chat latches its look per session too); read from the
--  Chat module when it is loaded, else from its saved Style flags.
-------------------------------------------------------------------------------
ns.FV = {
    gold  = { 1, 0.82, 0 },
    tan   = { 0.83, 0.71, 0.52 },
    thumb = { 0.72, 0.56, 0.36, 0.7 },   -- the chat's Forever scroll thumb
    line  = { 0.55, 0.45, 0.30, 1 },     -- a bronze hairline (search box, buttons)
}

-- The Damage Meters' Forever header, for our title bars and headers: the
-- band is Forever's objective tracker header cut to its warm body and lower
-- bronze rod (a cut of the 300x40 art: 64..176 across, 9..39 down), reaching
-- under the frame's sides; the glyphs tan on Forever's square button
-- plates; Forever's red close button.
ns.FV_HDR = {
    atlas = "ui-questtracker-primary-objective-header",
    cut = { 64 / 300, 176 / 300, 9 / 40, 39 / 40 },
    reach = 2,
    height = 30, rail = 6,          -- the window band, and its rod with the rod's shadow
    plate = "common-button-tertiary-square-normal",
    plateHover = "common-button-tertiary-square-hover",
    close = "RedButton-Exit",
    btn = 20, step = 24, pad = 5,   -- plate size, plate spacing, right edge gap
    glyph = { 0.95, 0.82, 0.60 },   -- the meter's tan
    alpha = 0.85, hoverAlpha = 1,
}

local fvAtlas = {}
function ns.FvAtlas(name)
    local v = fvAtlas[name]
    if v == nil then
        v = C_Texture.GetAtlasInfo(name) ~= nil
        fvAtlas[name] = v
    end
    return v
end

-- `tex` as the Forever header band along the top of `rel`, `height` tall
-- (an atlas cannot be cropped: the cut is drawn from the atlas's sheet at its
-- coords). False off the look or without the art (the caller paints its own).
function ns.FvHeaderBand(tex, rel, height)
    local H = ns.FV_HDR
    if not (ns.Forever() and ns.FvAtlas(H.atlas)) then return false end
    local info = C_Texture.GetAtlasInfo(H.atlas)
    if not info then return false end
    local l, t = info.leftTexCoord, info.topTexCoord
    local w, h = info.rightTexCoord - l, info.bottomTexCoord - t
    local c = H.cut
    tex:SetTexture(info.file or info.filename)
    tex:SetTexCoord(l + w * c[1], l + w * c[2], t + h * c[3], t + h * c[4])
    tex:SetVertexColor(1, 1, 1, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", rel, "TOPLEFT", -H.reach, 0)
    tex:SetPoint("TOPRIGHT", rel, "TOPRIGHT", H.reach, 0)
    tex:SetHeight(height)
    return true
end

-- How far a band `height` tall lifts its centred contents onto its body
-- (above the rod); 0 off the look
function ns.FvBandLift(height)
    local H = ns.FV_HDR
    if not (ns.Forever() and ns.FvAtlas(H.atlas)) then return 0 end
    return math.floor(height * H.rail / H.height / 2 + 0.5)
end

-- `button`'s icon as Forever's red close button (the whole button, untinted,
-- with no hover change of ours). False off the look or without the art.
function ns.FvCloseButton(button, icon)
    if not (ns.Forever() and ns.FvAtlas(ns.FV_HDR.close)) then return false end
    icon:SetTexture(nil)
    icon:SetAtlas(ns.FV_HDR.close)
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    icon:SetVertexColor(1, 1, 1, 0.9)
    button:SetScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, 1) end)
    button:SetScript("OnLeave", function() icon:SetVertexColor(1, 1, 1, 0.9) end)
    return true
end

-- The chat's look, latched once: lookStyle "eui" | "blizzard" | "classic"
-- (Global Settings > Style, the Chat row), and on the Forever client the
-- Forever variant of Blizzard Style with its Border Style.
local fvLatched, fvOn, fvKind, lookStyle
local function LatchForever()
    if fvLatched then return end
    fvLatched = true
    local EUI = EllesmereUI
    if not EUI then lookStyle = "eui" return end
    local canForever = EUI.IS_FOREVER == true and EUI.ForeverBorderOK and EUI.ForeverBorderOK()
    local chat = EUI._ModuleNS and EUI._ModuleNS["EllesmereUIChat"]
    -- The chat's own latch once its DB exists (before that it reads "eui"
    -- without latching, so the saved flags below answer instead)
    if chat and chat.ChatStyle and _G._ECHAT_DB and _G._ECHAT_DB.profile then
        lookStyle = chat.ChatStyle()
        if canForever and chat.ChatForever then
            fvOn = chat.ChatForever()
            fvKind = fvOn and chat.ChatFvKind() or nil
        end
        return
    end
    -- Chat module disabled (or not up yet): its saved Style flags in the
    -- active profile
    local db = EllesmereUIDB
    local profiles = type(db) == "table" and db.profiles
    local p = type(profiles) == "table" and profiles[db.activeProfile or "Default"]
    local addon = type(p) == "table" and type(p.addons) == "table" and p.addons.EllesmereUIChat
    local c = type(addon) == "table" and addon.chat
    lookStyle = "eui"
    if type(c) ~= "table" then return end
    lookStyle = (c.useClassicStyle and "classic") or (c.useBlizzardStyle and "blizzard") or "eui"
    if canForever and lookStyle == "blizzard" and c.useForeverStyle == true then
        fvOn = true
        fvKind = EUI.ForeverBorderKind(c.foreverBorder)
    end
end

-- The windows wear plain Blizzard Style this session (the chat's; not its
-- WoW Forever variant): the Damage Meters' Blizzard Style windows
function ns.BlizzStyle()
    LatchForever()
    return lookStyle == "blizzard" and fvOn ~= true
end

-- The windows wear Classic WoW UI this session (the chat's)
function ns.ClassicStyle()
    LatchForever()
    return lookStyle == "classic"
end

-------------------------------------------------------------------------------
--  Classic WoW UI, as the Damage Meters draws it: the tiled tooltip
--  background inside the vanilla chat tab's border, a lighter band of the
--  same tile under a rim-grey hairline as the header, vanilla art on the
--  title buttons (brightening on hover).
-------------------------------------------------------------------------------
ns.CLASSIC = {
    tile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edge = "Interface\\ChatFrame\\ChatFrameTab",
    edgeSize = 5,     -- one edge piece: shadow (2), rim (1), bevel (2)
    body = 3,         -- the tile starts this far inside (under the bevel)
    inset = 5,        -- contents start this far inside (past the bevel)
    hdrShade = 1.6, hdrLift = 0.05,   -- the header band: the window's tint x shade + lift
    rim = { 0.41, 0.41, 0.41, 1 },   -- the header hairline
    idle = 0.85, hover = 1,
    -- Vanilla art per title button, cropped to what it draws; `scale` insets
    -- it in its button (a full-bleed icon reads larger than a glyph)
    art = {
        close    = { file = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
        settings = { file = "Interface\\Icons\\Trade_Engineering", crop = 0.08, scale = 0.9 },
        history  = { file = "Interface\\QuestFrame\\UI-QuestLog-BookIcon", l = 0.015625, r = 0.96875, t = 0.03125, b = 0.96875 },
        pin      = { file = "Interface\\Icons\\INV_Misc_Map_01", crop = 0.08, scale = 0.85 },
    },
}
-- The chat tab's border cut from its 64x32 sheet { point, l, r, t, b }: 5x5
-- corners (the bottom ones the top ones flipped), edges stretched between
local CLASSIC_EDGE_UV = {
    { point = "TOPLEFT",     0.03125,  0.109375, 0.28125, 0.4375  },
    { point = "TOPRIGHT",    0.890625, 0.96875,  0.28125, 0.4375  },
    { point = "BOTTOMLEFT",  0.03125,  0.109375, 0.4375,  0.28125 },
    { point = "BOTTOMRIGHT", 0.890625, 0.96875,  0.4375,  0.28125 },
    { point = "TOP",         0.375,    0.5,      0.28125, 0.4375  },
    { point = "BOTTOM",      0.375,    0.5,      0.4375,  0.28125 },
    { point = "LEFT",        0.03125,  0.109375, 0.625,   0.75    },
    { point = "RIGHT",       0.890625, 0.96875,  0.625,   0.75    },
}

local function ClassicTile(tex, r, g, b, a)
    if not tex._eumTiled then
        tex._eumTiled = true
        tex:SetTexture(ns.CLASSIC.tile, "REPEAT", "REPEAT")
        tex:SetHorizTile(true)
        tex:SetVertTile(true)
    end
    tex:SetVertexColor(r, g, b, a)
end

-- A Classic body in place of `tex` (a background region spanning its
-- window, left painting nothing): the tile tinted r, g, b, a from under the
-- bevel, and the chat tab's border along the window's inside on a frame of
-- ours over the window's children (so a sidebar or panel never covers it).
-- Built once per texture; later calls only re-tint. False off the look.
local classicBody = setmetatable({}, { __mode = "k" })
function ns.ClassicBody(tex, r, g, b, a)
    if not ns.ClassicStyle() then return false end
    local C = ns.CLASSIC
    local tile = classicBody[tex]
    if not tile then
        local win = tex:GetParent()
        local layer, sub = tex:GetDrawLayer()
        tile = win:CreateTexture(nil, layer, nil, sub)
        tile:SetPoint("TOPLEFT", win, "TOPLEFT", C.body, -C.body)
        tile:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -C.body, C.body)
        local art = CreateFrame("Frame", nil, win)
        art:SetAllPoints()
        art:SetFrameLevel(win:GetFrameLevel() + 20)
        local p = {}
        for _, uv in ipairs(CLASSIC_EDGE_UV) do
            local t = art:CreateTexture(nil, "BORDER")
            t:SetTexture(C.edge)
            t:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
            p[uv.point] = t
        end
        for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
            p[corner]:SetSize(C.edgeSize, C.edgeSize)
            p[corner]:SetPoint(corner, art, corner)
        end
        p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT")
        p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT")
        p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT")
        p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT")
        p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT")
        p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT")
        p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT")
        p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT")
        classicBody[tex] = tile
    end
    tex:SetTexture(nil)
    tex:SetColorTexture(0, 0, 0, 0)
    ClassicTile(tile, r, g, b, a)
    return true
end

-- `tex` as the Classic header: a lighter band of the window's tile (window
-- tint winR, winG, winB; opacity a) inside the bevel along the top of `rel`,
-- `height` tall from the window's top edge, and a rim-grey hairline under it
-- (built once). False off the look.
function ns.ClassicHeader(tex, rel, height, winR, winG, winB, a)
    if not ns.ClassicStyle() then return false end
    local C = ns.CLASSIC
    local function Lift(v) return math.min(1, v * C.hdrShade + C.hdrLift) end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", rel, "TOPLEFT", C.body, -C.body)
    tex:SetPoint("TOPRIGHT", rel, "TOPRIGHT", -C.body, -C.body)
    tex:SetHeight(height - C.body)
    ClassicTile(tex, Lift(winR), Lift(winG), Lift(winB), a or 1)
    if not tex._eumLine then
        local line = rel:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", tex, "BOTTOMLEFT")
        line:SetPoint("TOPRIGHT", tex, "BOTTOMRIGHT")
        local PP = EllesmereUI and EllesmereUI.PP
        line:SetHeight(PP and PP.Scale and PP.mult and PP.Scale(PP.mult) or 1)
        line:SetColorTexture(unpack(C.rim))
        tex._eumLine = line
    end
    return true
end

-- `tex` painted with a Classic button art entry, at the idle brightness
function ns.ClassicArt(tex, art)
    tex:SetDesaturated(false)
    tex:SetTexture(art.file)
    if art.crop then
        tex:SetTexCoord(art.crop, 1 - art.crop, art.crop, 1 - art.crop)
    else
        tex:SetTexCoord(art.l or 0, art.r or 1, art.t or 0, art.b or 1)
    end
    local k = ns.CLASSIC.idle
    tex:SetVertexColor(k, k, k, 1)
end

-- A close button's icon as the vanilla close art, brightening on hover.
-- False off the look.
function ns.ClassicCloseButton(button, icon)
    if not ns.ClassicStyle() then return false end
    local C = ns.CLASSIC
    ns.ClassicArt(icon, C.art.close)
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    button:SetScript("OnEnter", function() icon:SetVertexColor(C.hover, C.hover, C.hover, 1) end)
    button:SetScript("OnLeave", function() icon:SetVertexColor(C.idle, C.idle, C.idle, 1) end)
    return true
end

-- Blizzard Style's art, as the Damage Meters draws it: the stock meter's
-- header bar (a dark band over a gold rule) and a borderless black body,
-- softer along its top.
ns.BLIZZ = {
    header = "ui-damagemeters-header-bar",
    band = 20,         -- the body's softer top band
    body = 245 / 255,  -- the body's strength (times the window opacity)
}

-- `tex` as the stock meter's header bar. False off Blizzard Style or
-- without the art (the caller paints its own).
function ns.BlizzHeader(tex)
    if not (ns.BlizzStyle() and ns.FvAtlas(ns.BLIZZ.header)) then return false end
    tex:SetAtlas(ns.BLIZZ.header)
    tex:SetVertexColor(1, 1, 1, 1)
    return true
end

-- A Blizzard Style body in place of `tex` (a background region spanning the
-- window, left painting nothing): flat black at the opacity `a`, the top
-- band from half that up to it. Built once per texture; later calls only
-- re-tint. False off Blizzard Style.
local blizzBody = setmetatable({}, { __mode = "k" })
local blizzLo, blizzHi
function ns.BlizzBody(tex, a)
    if not ns.BlizzStyle() then return false end
    local parts = blizzBody[tex]
    if not parts then
        local parent = tex:GetParent()
        local layer, sub = tex:GetDrawLayer()
        parts = {}
        for i = 1, 2 do
            local t = parent:CreateTexture(nil, layer, nil, sub)
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            parts[i] = t
        end
        local band = ns.BLIZZ.band
        parts[1]:SetPoint("TOPLEFT", tex, "TOPLEFT")
        parts[1]:SetPoint("TOPRIGHT", tex, "TOPRIGHT")
        parts[1]:SetHeight(band)
        parts[2]:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, -band)
        parts[2]:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
        blizzBody[tex] = parts
        blizzLo, blizzHi = blizzLo or CreateColor(0, 0, 0, 1), blizzHi or CreateColor(0, 0, 0, 1)
    end
    tex:SetTexture(nil)
    tex:SetColorTexture(0, 0, 0, 0)
    local body = ns.BLIZZ.body * (a or 1)
    blizzLo:SetRGBA(0, 0, 0, body)
    blizzHi:SetRGBA(0, 0, 0, body * 0.5)
    -- VERTICAL runs bottom to top
    parts[1]:SetGradient("VERTICAL", blizzLo, blizzHi)
    parts[2]:SetGradient("VERTICAL", blizzLo, blizzLo)
    return true
end

-- The windows wear the WoW Forever look this session
function ns.Forever()
    LatchForever()
    return fvOn == true
end

-- Its Border Style: "slim", "textured" or "heavy" (nil off the look)
function ns.FvKind()
    LatchForever()
    return fvKind
end

-- The Forever frame round `frame` (a window of ours), drawn just outside its
-- edges so nothing inside moves: the bronze line (Slim / Slim Textured) or the
-- heavy bronze rim. Returns the frame's art, or nil off the look.
function ns.ForeverFrame(frame)
    if not ns.Forever() then return nil end
    local EUI = EllesmereUI
    local art = CreateFrame("Frame", nil, frame)
    art:SetAllPoints()
    art:SetFrameLevel(frame:GetFrameLevel() + 20)
    local kind = ns.FvKind()
    if kind == "heavy" then
        local H = EUI.FOREVER_HEAVY
        art:SetScale(H.k)
        local ring = EUI.ForeverHeavy(art, "BORDER")
        if ring then
            local o = H.shade * H.k
            EUI.ForeverHeavySeat(ring, frame, "TOPLEFT", -o, o, o, -o)
            return ring
        end
        art:SetScale(1)
        kind = "textured"
    end
    local ring = EUI.ForeverBorder(art, "BORDER", 0, nil, kind)
    if ring then
        local o = EUI.FOREVER_BORDER.shade
        EUI.ForeverBorderSeat(ring, frame, "TOPLEFT", -o, o, o, -o)
    end
    return ring
end

function ns.Accent()
    if ns.Forever() then
        local g = ns.FV.gold
        return g[1], g[2], g[3]
    end
    local EUI = EllesmereUI
    if EUI and EUI.GetAccentColor then
        local r, g, b = EUI.GetAccentColor()
        if r then return r, g, b end
    end
    local c = EUI and EUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

function ns.Font()
    local EUI = EllesmereUI
    local path = EUI and EUI.GetFontPath and EUI.GetFontPath("chat")
    return path or STANDARD_TEXT_FONT
end

function ns.ClassColor(classFile)
    if not classFile then return nil end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
end

function ns.InChatLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

function ns.Print(msg)
    local r, g, b = ns.Accent()
    DEFAULT_CHAT_FRAME:AddMessage(("|cff%02x%02x%02xMessaging:|r %s"):format(r * 255, g * 255, b * 255, msg))
end

-------------------------------------------------------------------------------
--  Conversations
--
--  key: "c:<name-realm>" (lower case) for characters, "b:<battletag>" for
--  Battle.net friends. A conversation lives for the session once touched;
--  `open` marks it as a tab in the window. Its recent lines are kept in
--  memory, everything else in the history store.
-------------------------------------------------------------------------------
ns.convos = {}   -- key -> convo
ns.order = {}    -- open conversations, tab order

local MAX_LIVE_LINES = 200

local function NewConvo(key, kind)
    local convo = { key = key, kind = kind, lines = {}, unread = 0, open = false }
    ns.convos[key] = convo
    return convo
end

-- Character conversation by name (any form)
function ns.GetCharConvo(name, create)
    local full = FullName(name)
    if not full then return nil end
    local key = "c:" .. full:lower()
    local convo = ns.convos[key]
    if not convo and create then
        convo = NewConvo(key, "char")
        convo.name = full
        ns.LoadHistory(convo)
    end
    if convo then convo.display = ns.ShortName(convo.name) end
    return convo
end

-- Battle.net account info for an id (nil when the friend is gone)
local function BNInfo(bnID)
    if not (bnID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return nil end
    return C_BattleNet.GetAccountInfoByID(bnID)
end
ns.BNInfo = BNInfo

-- Class file from a localized class name (Battle.net reports class names
-- only); the male and female names both map back
local classByName
local function ClassFileFromName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not classByName then
        classByName = {}
        for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
            for file, localized in pairs(names) do classByName[localized] = file end
        end
    end
    return classByName[name]
end
ns.ClassFileFromName = ClassFileFromName

-- The class file of the WoW character a Battle.net friend plays (by class id,
-- as the EllesmereUI friends list reads it; by name as the fallback)
function ns.BNClassFile(info)
    local game = info and info.gameAccountInfo
    if not (game and game.isOnline) then return nil end
    if game.classID and game.classID > 0 and GetClassInfo then
        local _, classFile = GetClassInfo(game.classID)
        if classFile then return classFile end
    end
    return ClassFileFromName(game.className)
end

-- Battle.net conversation by account id (the id is per session; the key is
-- the BattleTag, so history and reopened tabs survive a relog)
function ns.GetBNConvo(bnID, create)
    local info = BNInfo(bnID)
    if not info then return nil end
    local tag = info.battleTag
    if not tag or tag == "" then return nil end
    local key = "b:" .. tag:lower()
    local convo = ns.convos[key]
    if not convo and create then
        convo = NewConvo(key, "bn")
        ns.LoadHistory(convo)
    end
    if convo then
        convo.bnID = bnID
        convo.battleTag = tag
        -- the account name is a protected |K string: shown as the real name,
        -- never stored. History keeps the BattleTag's name part.
        convo.display = (info.accountName and info.accountName ~= "") and info.accountName or tag:match("^[^#]+") or tag
        -- the class of the character they play, for the name color
        convo.class = ns.BNClassFile(info) or convo.class
    end
    return convo
end

-- Finds a Battle.net friend's current account id by BattleTag (after a relog)
function ns.FindBNID(battleTag)
    if not (battleTag and BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return nil end
    local want = battleTag:lower()
    for i = 1, BNGetNumFriends() do
        local info = C_BattleNet.GetFriendAccountInfo(i)
        if info and info.battleTag and info.battleTag:lower() == want then return info.bnetAccountID end
    end
end

-------------------------------------------------------------------------------
--  One conversation per Battle.net friend, whatever character they play: a
--  character whisper to or from a character a Battle.net friend is playing
--  right now belongs to that friend's Battle.net conversation. Matched by the
--  character's GUID (Battle.net reports each game account's playerGuid), else
--  by name and realm. Off with the "Battle.net whispers" setting.
-------------------------------------------------------------------------------
local function RealmKey(realm)
    return type(realm) == "string" and realm:gsub("[%s%-']", ""):lower() or ""
end

-- Our realm under every spelling the client and Battle.net use (normalized,
-- display name; on some clients the normalized name is an internal id)
local function OwnRealmKeys()
    local keys = {}
    keys[RealmKey(MyRealm())] = true
    keys[RealmKey(GetRealmName and GetRealmName())] = true
    keys[""] = nil
    return keys
end

-- Priority, best first:
--   1. the GUID of the character (whispers carry it; Battle.net reports the
--      playerGuid of each game account)
--   2. name and realm: the realm id when the name is on our realm, else any
--      spelling of the realm
--   3. the name alone, when exactly one Battle.net friend plays a WoW
--      character of that name right now
-- WIM keys its windows by name only and never merges; this goes further so a
-- Battle.net friend keeps one conversation whatever character they play.
function ns.FindBNFriendForCharacter(guid, name)
    if not (ns.settings.battleNet and BNGetNumFriends and C_BattleNet
            and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
        return nil
    end
    if type(guid) ~= "string" or guid == "" or IsSecret(guid) then guid = nil end
    if IsSecret(name) then name = nil end
    local wantName, wantRealm
    if type(name) == "string" and name ~= "" then
        local n, r = name:match("^(.-)%-(.+)$")
        wantName = (n or name):lower()
        wantRealm = r and RealmKey(r) or nil
    end
    if not (guid or wantName) then return nil end

    local own = OwnRealmKeys()
    local onOurRealm = (wantRealm == nil) or own[wantRealm]
    local myRealmID = GetRealmID and GetRealmID()
    local wowClient = BNET_CLIENT_WOW or "WoW"
    local byNameID, byNameCount

    local function AccountID(i)
        local account = C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
        return account and account.bnetAccountID
    end

    for i = 1, BNGetNumFriends() do
        for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
            local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
            local char = game and game.isOnline and game.characterName
            if game and type(char) == "string" and char ~= "" and (game.clientProgram == nil or game.clientProgram == wowClient) then
                if guid and game.playerGuid == guid then return AccountID(i) end
                local gameName = char:match("^[^%-]+") or char
                if wantName and gameName:lower() == wantName then
                    local realm, shown = RealmKey(game.realmName), RealmKey(game.realmDisplayName)
                    local match
                    if onOurRealm then
                        match = (myRealmID and game.realmID and game.realmID == myRealmID)
                            or own[realm] or own[shown]
                    end
                    if not match and wantRealm then
                        match = (realm == wantRealm) or (shown == wantRealm)
                    end
                    if match then return AccountID(i) end
                    local id = AccountID(i)
                    if id and id ~= byNameID then
                        byNameCount = (byNameCount or 0) + 1
                        byNameID = id
                    end
                end
            end
        end
    end
    if byNameCount == 1 then return byNameID end
end

-- The conversation for a character: their Battle.net friend's conversation
-- while a Battle.net friend plays them, else the character's own
function ns.ConvoForCharacter(name, guid, create)
    local bnID = ns.FindBNFriendForCharacter(guid, name)
    local convo = bnID and ns.GetBNConvo(bnID, create)
    if convo then return convo end
    return ns.GetCharConvo(name, create)
end

function ns.OpenConvo(convo, select)
    if not convo then return end
    if not convo.open then
        convo.open = true
        table.insert(ns.order, convo)
    end
    if select then ns.active = convo end
    ns.Fire("ConvoOpened", convo, select)
end

function ns.CloseConvo(convo)
    if not convo or not convo.open then return end
    convo.open = false
    convo.unread = 0
    for i, c in ipairs(ns.order) do
        if c == convo then
            table.remove(ns.order, i)
            if ns.active == convo then ns.active = ns.order[i] or ns.order[i - 1] end
            break
        end
    end
    ns.Fire("ConvoClosed", convo)
    ns.Fire("UnreadChanged")
end

function ns.TotalUnread()
    local n = 0
    for _, convo in pairs(ns.convos) do n = n + convo.unread end
    return n
end

-- The most recent conversation with unread messages
function ns.LatestUnread()
    local best
    for _, convo in pairs(ns.convos) do
        if convo.unread > 0 and (not best or (convo.lastTime or 0) > (best.lastTime or 0)) then best = convo end
    end
    return best
end

function ns.MarkRead(convo)
    if convo and convo.unread > 0 then
        convo.unread = 0
        ns.Fire("UnreadChanged")
    end
end

-------------------------------------------------------------------------------
--  History store
--
--  EllesmereUIDB.global.messagingHistory[<character>][<key>] = {
--      n = display name, k = kind, c = class file, g = gm, t = last time,
--      m = { { time, direction, text }, ... }  (oldest first)
--  }
-------------------------------------------------------------------------------
local function OwnerHistory(create)
    local store = ns.history
    if not (store and ns.owner) then return nil end
    local h = store[ns.owner]
    if not h and create then
        h = {}
        store[ns.owner] = h
    end
    return h
end
ns.OwnerHistory = OwnerHistory

function ns.LoadHistory(convo)
    local h = OwnerHistory(false)
    local entry = h and h[convo.key]
    if not entry then return end
    convo.class = convo.class or entry.c
    convo.gm = convo.gm or entry.g
    convo.lastTime = entry.t
    if convo.kind == "char" then convo.name = convo.name or entry.n end
    local replay = ns.settings.history.replay or 0
    local m = entry.m
    for i = math.max(1, #m - replay + 1), #m do
        local rec = m[i]
        table.insert(convo.lines, { t = rec[1], d = rec[2], text = rec[3], old = true })
    end
end

local function SaveLine(convo, line)
    if not ns.settings.history.enabled then return end
    local h = OwnerHistory(true)
    if not h then return end
    local entry = h[convo.key]
    if not entry then
        entry = { k = convo.kind, m = {} }
        h[convo.key] = entry
    end
    entry.n = (convo.kind == "bn") and (convo.battleTag or entry.n) or convo.name
    entry.c = convo.class or entry.c
    entry.g = convo.gm or nil
    entry.t = line.t
    local m = entry.m
    m[#m + 1] = { line.t, line.d, line.text }
    local keep = ns.settings.history.keep or 250
    while #m > keep do table.remove(m, 1) end
end

-- Drops conversations idle longer than the setting
function ns.PruneHistory()
    local days = ns.settings.history.days or 0
    if days <= 0 then return end
    local cutoff = time() - days * 86400
    for _, h in pairs(ns.history or {}) do
        for key, entry in pairs(h) do
            if (entry.t or 0) < cutoff then h[key] = nil end
        end
    end
end

function ns.DeleteHistory(key)
    local h = OwnerHistory(false)
    if h then h[key] = nil end
    local convo = ns.convos[key]
    if convo then wipe(convo.lines) end
    ns.Fire("HistoryChanged", key)
end

function ns.ClearAllHistory()
    if ns.history then wipe(ns.history) end
    for _, convo in pairs(ns.convos) do wipe(convo.lines) end
    ns.Fire("HistoryChanged")
end

-------------------------------------------------------------------------------
--  Lines
-------------------------------------------------------------------------------
-- While whispers recovered after a chat lockdown are replayed, their lines
-- keep the time they were received (see the lockdown queue below)
local replayTime

function ns.AddLine(convo, dir, text)
    local line = { t = replayTime or time(), d = dir, text = text }
    local lines = convo.lines
    lines[#lines + 1] = line
    if #lines > MAX_LIVE_LINES then table.remove(lines, 1) end
    convo.lastTime = line.t
    if dir ~= ns.SYSTEM then SaveLine(convo, line) end
    ns.Fire("LineAdded", convo, line)
end

-------------------------------------------------------------------------------
--  Incoming: unread, sound, flash, popup
-------------------------------------------------------------------------------
local pendingPopup -- the newest popup held back by combat ("nocombat")

local function Popup(convo)
    ns.Fire("ShowWindow", convo)
end

local function PopupAfterCombat()
    local convo = pendingPopup
    pendingPopup = nil
    if convo then Popup(convo) end
end

local function OnIncoming(convo)
    local s = ns.settings
    -- Unread until you look: a window that pops open by itself does not
    -- count as read; typing in the conversation, selecting it or opening the
    -- window yourself does
    if not (ns.IsReading and ns.IsReading(convo)) then
        convo.unread = convo.unread + 1
        ns.Fire("UnreadChanged")
    end
    -- A chat window that shows whispers already plays the whisper sound and
    -- flashes the taskbar; the window does both only when none does (a
    -- whisper recovered after a lockdown already rang in the main chat)
    if not replayTime and not ns.ChatShowsWhispers(convo.kind) then
        if s.sound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
        if s.flash and FlashClientIcon then FlashClientIcon() end
    end

    if s.popup == "always" or (s.popup == "nocombat" and not InCombatLockdown()) then
        Popup(convo)
    elseif s.popup == "nocombat" then
        pendingPopup = convo
        EllesmereUI.CombatQueue.Defer("EUIMessagingPopup", PopupAfterCombat)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local events = {}

local function ClassFromGUID(guid)
    if type(guid) ~= "string" or guid == "" or not GetPlayerInfoByGUID then return nil end
    local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
    if ok then return classFile end
end

function events.CHAT_MSG_WHISPER(text, sender, _, _, _, flags, _, _, _, _, _, guid)
    if IsSecret(text, sender, flags, guid) then return end
    local isGM = (flags == "GM" or flags == "DEV")
    -- a Battle.net friend's character: into that friend's conversation
    local convo = isGM and ns.GetCharConvo(sender, true) or ns.ConvoForCharacter(sender, guid, true)
    if not convo then return end
    if convo.kind == "char" then
        convo.class = ClassFromGUID(guid) or convo.class
        convo.guid = guid or convo.guid
    end
    if isGM then convo.gm = true end
    ns.OpenConvo(convo, false)
    ns.AddLine(convo, ns.IN, text)
    OnIncoming(convo)
end

function events.CHAT_MSG_WHISPER_INFORM(text, target, _, _, _, flags, _, _, _, _, _, guid)
    if IsSecret(text, target, flags, guid) then return end
    local convo = ns.ConvoForCharacter(target, guid, true)
    if not convo then return end
    if convo.kind == "char" then
        convo.class = ClassFromGUID(guid) or convo.class
        convo.guid = guid or convo.guid
    end
    ns.OpenConvo(convo, false)
    ns.AddLine(convo, ns.OUT, text)
    ns.MarkRead(convo) -- (a reply: you have read them)
    -- Sent from the main chat (/w): the window opens only when no chat window
    -- shows whispers (else the main chat already shows it)
    if not (ns.WindowShown and ns.WindowShown()) and not ns.ChatShowsWhispers("char") then Popup(convo) end
end

function events.CHAT_MSG_BN_WHISPER(text, _, _, _, _, _, _, _, _, _, _, _, bnID)
    if not ns.settings.battleNet or IsSecret(text, bnID) then return end
    local convo = ns.GetBNConvo(bnID, true)
    if not convo then return end
    ns.OpenConvo(convo, false)
    ns.AddLine(convo, ns.IN, text)
    OnIncoming(convo)
end

function events.CHAT_MSG_BN_WHISPER_INFORM(text, _, _, _, _, _, _, _, _, _, _, _, bnID)
    if not ns.settings.battleNet or IsSecret(text, bnID) then return end
    local convo = ns.GetBNConvo(bnID, true)
    if not convo then return end
    ns.OpenConvo(convo, false)
    ns.AddLine(convo, ns.OUT, text)
    ns.MarkRead(convo)
    if not (ns.WindowShown and ns.WindowShown()) and not ns.ChatShowsWhispers("bn") then Popup(convo) end
end

-- Auto-replies (AFK / DND) of someone we whispered
local function AutoReply(text, sender)
    if IsSecret(text, sender) then return end
    local convo = ns.ConvoForCharacter(sender, nil, false)
    if convo and convo.open then ns.AddLine(convo, ns.SYSTEM, text) end
end
events.CHAT_MSG_AFK = AutoReply
events.CHAT_MSG_DND = AutoReply

-- Testing (/euiw test): an incoming whisper through the same handler a real
-- one takes (conversation, unread, sound, popup, history). "bn" uses the
-- first online Battle.net friend; otherwise `name` (any text) is the sender.
-- Nothing is sent, and the main chat does not see it.
function ns.SimulateIncoming(kind, name, text)
    text = (text and text ~= "") and text or ("Test whisper " .. date("%H:%M:%S"))
    if kind == "bn" then
        for i = 1, (BNGetNumFriends and BNGetNumFriends() or 0) do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info and info.gameAccountInfo and info.gameAccountInfo.isOnline then
                events.CHAT_MSG_BN_WHISPER(text, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, info.bnetAccountID)
                return true
            end
        end
        ns.Print("no Battle.net friend is online to test with.")
        return false
    end
    events.CHAT_MSG_WHISPER(text, (name and name ~= "") and name or "Testwhisperer", nil, nil, nil, "", nil, nil, nil, nil, nil, nil)
    return true
end

function events.CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE(text, _, _, _, _, _, _, _, _, _, _, _, bnID)
    if IsSecret(text, bnID) then return end
    local convo = ns.GetBNConvo(bnID, false)
    if convo and convo.open then ns.AddLine(convo, ns.SYSTEM, text) end
end

-- "No player named 'X' is currently playing." for an open conversation
local notFoundPattern
local function NotFoundTarget(text)
    if not notFoundPattern and ERR_CHAT_PLAYER_NOT_FOUND_S then
        notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    end
    return notFoundPattern and text:match(notFoundPattern)
end

function events.CHAT_MSG_SYSTEM(text)
    if IsSecret(text) or type(text) ~= "string" then return end
    local name = NotFoundTarget(text)
    local convo = name and ns.GetCharConvo(name, false)
    if convo and convo.open then ns.AddLine(convo, ns.SYSTEM, text) end
end

-------------------------------------------------------------------------------
--  Chat lockdown queue
--
--  A whisper whose contents are secret can't be read now, but the client
--  keeps the chat line: once the chat restriction lifts, its text, sender and
--  GUID are read back by the event's line id (C_ChatInfo.GetChatLine*), and
--  the whisper is filed into its conversation with the time it arrived.
--  Meanwhile it shows in the main chat, which addons can't hide during the
--  lockdown. A line the client no longer has is counted and reported once.
-------------------------------------------------------------------------------
local RECOVERABLE = {
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
}
local MAX_QUEUED = 200
local queue, lost = {}, 0

local function Readable(v)
    return type(v) == "string" and v ~= "" and not IsSecret(v)
end

local function Enqueue(event, ...)
    if not RECOVERABLE[event] then return end
    local lineID, bnID = select(11, ...), select(13, ...)
    if IsSecret(lineID) or type(lineID) ~= "number" or lineID <= 0 then
        lost = lost + 1
        return
    end
    for _, item in ipairs(queue) do
        if item.lineID == lineID and item.event == event then return end
    end
    if #queue >= MAX_QUEUED then
        table.remove(queue, 1)
        lost = lost + 1
    end
    local flags = select(6, ...)
    queue[#queue + 1] = {
        event = event, lineID = lineID, time = time(),
        bnID = (not IsSecret(bnID) and type(bnID) == "number") and bnID or nil,
        flags = (not IsSecret(flags) and type(flags) == "string") and flags or nil,
    }
end

local GetLine = C_ChatInfo and C_ChatInfo.GetChatLineText
local GetLineSender = C_ChatInfo and C_ChatInfo.GetChatLineSenderName
local GetLineGUID = C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID

local IsValidLine = C_ChatInfo and C_ChatInfo.IsValidChatLine

local function Recover(item)
    if not GetLine then return false end
    -- the client keeps a finite number of chat lines (how many is undocumented)
    if IsValidLine then
        local okV, valid = pcall(IsValidLine, item.lineID)
        if okV and valid == false then return false end
    end
    local ok, text = pcall(GetLine, item.lineID)
    if not ok or not Readable(text) then return false end
    local sender
    if GetLineSender then
        local ok2, name = pcall(GetLineSender, item.lineID)
        if ok2 and Readable(name) then sender = name end
    end
    local guid
    if GetLineGUID then
        local ok3, g = pcall(GetLineGUID, item.lineID)
        if ok3 and Readable(g) then guid = g end
    end
    local bnID = item.bnID
    if not bnID and sender and item.event:find("^CHAT_MSG_BN_") and BNet_GetBNetIDAccount then
        bnID = BNet_GetBNetIDAccount(sender)
    end
    if item.event:find("^CHAT_MSG_BN_") then
        if not bnID then return false end
    elseif not sender then
        return false
    end
    replayTime = item.time
    local handler = events[item.event]
    xpcall(handler, geterrorhandler(), text, sender, nil, nil, nil, item.flags, nil, nil, nil, nil, item.lineID, guid, bnID)
    replayTime = nil
    return true
end

local function ProcessQueue()
    if #queue == 0 or ns.InChatLockdown() then return end
    local items = queue
    queue = {}
    for _, item in ipairs(items) do
        if not Recover(item) then lost = lost + 1 end
    end
    if lost > 0 then
        ns.Print(("%d whisper(s) from the chat lockdown couldn't be recovered; they are in the main chat."):format(lost))
        lost = 0
    end
end

-- Called with the raw event arguments when any of them is secret. The queue
-- is filed when the chat restriction lifts, or at the end of combat should
-- the lockdown come with it.
local function Defer(event, ...)
    Enqueue(event, ...)
    if #queue > 0 and InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("EUIMessagingQueue", ProcessQueue)
    end
end

function events.ADDON_RESTRICTION_STATE_CHANGED(restrictionType, state)
    if IsSecret(restrictionType, state) then return end
    if restrictionType == Enum.AddOnRestrictionType.Chat and state == Enum.AddOnRestrictionState.Inactive then
        ProcessQueue()
    end
end

-------------------------------------------------------------------------------
--  The main chat is never touched: whispers show in every chat window the
--  player set up for them (Chat Settings, the window's message types), as
--  they would without this addon. The window is an extra view. This only
--  READS that setup, to know whether the game already plays the whisper
--  sound (it does when a chat window shows the whisper) and whether a whisper
--  sent from the main chat is already visible there.
-------------------------------------------------------------------------------
function ns.ChatShowsWhispers(kind)
    local group = (kind == "bn") and "BN_WHISPER" or "WHISPER"
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chatFrame = _G["ChatFrame" .. i]
        local list = chatFrame and chatFrame.messageTypeList
        if type(list) == "table" then
            local shown, docked
            if GetChatWindowInfo then
                local _
                _, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
            end
            if shown or docked or i == 1 then
                for _, g in ipairs(list) do
                    if g == group then return true end
                end
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Sending
-------------------------------------------------------------------------------
local MAX_BYTES = 255

-- Splits text into chunks the server accepts, at spaces, never inside a link
local function Split(text)
    local chunks, current = {}, ""
    local inLink = 0
    for word in text:gmatch("%S+") do
        local candidate = (current == "") and word or (current .. " " .. word)
        if #candidate <= MAX_BYTES or inLink > 0 then
            current = candidate
        else
            if current ~= "" then chunks[#chunks + 1] = current end
            current = word
        end
        -- keep "|H...|h[...]|h" together: count opens and closes
        local opens = select(2, word:gsub("|H", ""))
        local closes = select(2, word:gsub("|h", "")) - opens
        inLink = math.max(0, inLink + opens - closes)
        while #current > MAX_BYTES and inLink == 0 and not current:find("|H", 1, true) do
            chunks[#chunks + 1] = current:sub(1, MAX_BYTES)
            current = current:sub(MAX_BYTES + 1)
        end
    end
    if current ~= "" then chunks[#chunks + 1] = current end
    return chunks
end

local SendChat = C_ChatInfo.SendChatMessage

-- Returns true when the text went out (the window then clears its input)
function ns.Send(convo, text)
    if not convo or type(text) ~= "string" then return false end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end
    if ns.InChatLockdown() then
        ns.Print("chat is locked right now; your message was kept.")
        return false
    end
    if convo.kind == "bn" then
        local bnID = convo.bnID
        local info = BNInfo(bnID)
        if not info or (info.battleTag or ""):lower() ~= (convo.battleTag or ""):lower() then
            bnID = ns.FindBNID(convo.battleTag)
            convo.bnID = bnID
        end
        if not bnID or not BNSendWhisper then
            ns.AddLine(convo, ns.SYSTEM, "This Battle.net friend can't be reached.")
            return false
        end
        for _, chunk in ipairs(Split(text)) do BNSendWhisper(bnID, chunk) end
    else
        -- To the name as the game shortens it: no realm for our own realm
        -- (the key's "Name-Realm" form uses the normalized realm name, which
        -- on some clients is an internal id the server won't take back)
        local target = ns.ShortName(convo.name)
        for _, chunk in ipairs(Split(text)) do SendChat(chunk, "WHISPER", nil, target) end
    end
    -- the sent text shows when the server echoes it (the *_INFORM event)
    return true
end

-------------------------------------------------------------------------------
--  Startup
-------------------------------------------------------------------------------
local loggedIn = false
local function OnLogin()
    if loggedIn then return end
    loggedIn = true
    frame:UnregisterEvent("PLAYER_LOGIN")
    ns.owner = (UnitName("player") or "?") .. "-" .. MyRealm()
    ns.PruneHistory()
    for name in pairs(events) do
        -- (the chat restriction event is not on every client)
        if C_EventUtils.IsEventValid(name) then frame:RegisterEvent(name) end
    end
    -- (a "New Whispers" value an earlier build held at "inline" goes back at
    -- the first loading screen's end, once the game's saved options are in)
    if type(EllesmereUIDB.global.messagingWhisperMode) == "table" then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    ns.Fire("Ready")
end

-- Puts back the player's "New Whispers" options (whisperMode / bnWhisperMode)
-- that an earlier build switched to "inline", once; nothing writes them now
local function RestoreWhisperMode()
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("EUIMessagingWhisperMode", RestoreWhisperMode)
        return
    end
    local kept = EllesmereUIDB.global.messagingWhisperMode
    EllesmereUIDB.global.messagingWhisperMode = nil
    if type(kept) ~= "table" then return end
    for cvar, value in pairs(kept) do
        if type(value) == "string" and C_CVar.GetCVar(cvar) == "inline" then C_CVar.SetCVar(cvar, value) end
    end
end

-- Saved data -> settings and history (once; at our ADDON_LOADED, or at the
-- login should that event ever be missed)
local function Init()
    if ns.settings then return end
    EllesmereUIDB = type(EllesmereUIDB) == "table" and EllesmereUIDB or {}
    if type(EllesmereUIDB.global) ~= "table" then EllesmereUIDB.global = {} end
    if type(EllesmereUIDB.global.messagingHistory) ~= "table" then
        EllesmereUIDB.global.messagingHistory = {}
    end
    ns.history = EllesmereUIDB.global.messagingHistory

    -- Settings live in the central profile store, as every module's do
    ns.db = EllesmereUI.Lite.NewDB("EllesmereUIMessagingDB", { profile = DEFAULTS })
    CopyDefaults(DEFAULTS, ns.db.profile)

    -- Everything reads the settings through ns.settings, which always
    -- points at the active profile (a profile switch replaces db.profile)
    ns.settings = setmetatable({}, {
        __index = function(_, k)
            local p = ns.db.profile
            if p[k] == nil and DEFAULTS[k] ~= nil then CopyDefaults(DEFAULTS, p) end
            return p[k]
        end,
        __newindex = function(_, k, v) ns.db.profile[k] = v end,
    })
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        frame:UnregisterEvent("ADDON_LOADED")
        Init()
        return
    end
    if event == "PLAYER_LOGIN" then
        Init()
        OnLogin()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        RestoreWhisperMode()
        return
    end
    if not ns.settings then return end
    if not ns.settings.enabled then return end
    local handler = events[event]
    if not handler then return end
    if RECOVERABLE[event] and IsSecret(...) then
        Defer(event, ...)
        return
    end
    xpcall(handler, geterrorhandler(), ...)
end)
