if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Style.lua
--
--  The stock looks on our own windows and rows: Blizzard Style, Classic WoW
--  UI and the WoW Forever variant, with the header art of each.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local DB, DM_TYPE_ICONS, EnsureDB, MEDIA = I.DB, I.DM_TYPE_ICONS, I.EnsureDB, I.MEDIA

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style) on our own windows and rows:
--  Blizzard Style = the stock meter's atlases; Classic WoW UI = the stock
--  meter's shape in vanilla art: the tiled tooltip background inside the
--  vanilla chat tab's border (the classic chat tabs' own art) as the window,
--  a lighter band of the same tile under a rim-grey hairline as the header,
--  and the user's bar texture
--  over a plain track (seeded a quarter black on the first switch). Reload-gated
--  per-profile flags; every read is on a build/refresh path. On ns so the
--  spell history window shares the painters.
-------------------------------------------------------------------------------
ns.DM_BLIZZ_BAR_BG   = "ui-damagemeters-bar-shadowbg"
ns.DM_BLIZZ_BAR_EDGE = "ui-damagemeters-bar-shadowedge"
ns.DM_BLIZZ_HEADER   = "ui-damagemeters-header-bar"
ns.DM_CLASSIC_BG        = "Interface\\Tooltips\\UI-Tooltip-Background"
ns.DM_CLASSIC_EDGE      = "Interface\\ChatFrame\\ChatFrameTab"
ns.DM_CLASSIC_EDGE_SIZE = 5    -- one edge piece at 1x: shadow (2), rim (1), bevel (2)
ns.DM_CLASSIC_BODY      = 3    -- the tile starts this far inside the rect (under the bevel)
ns.DM_CLASSIC_INSET     = 5    -- the header and rows start this far inside the rect (past the bevel)
ns.DM_CLASSIC_HDR_SHADE = 1.6  -- the header's tint relative to the window's (a lighter band)
ns.DM_CLASSIC_HDR_LIFT  = 0.05 -- plus this, so a black window still gets a visible header band
-- The style this module RENDERS this session: "eui" | "blizzard" | "classic".
-- Read from the profile once (first call with a real profile) and latched for
-- the session: a live profile switch never flips the look under the one-time
-- art setup; the profile system prompts for a reload instead. Both flags set
-- resolves as classic (the Style page never writes both).
function ns.DMStyle()
    local v = ns._dmStyle
    if v == nil then
        local d = _G._EDM_DB
        local dm = d and d.profile and d.profile.dm
        if not dm then return "eui" end
        v = (dm.useClassicStyle and "classic") or (dm.useBlizzardStyle and "blizzard") or "eui"
        ns._dmStyle = v
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        ns._dmForever = v == "blizzard" and EllesmereUI.IS_FOREVER == true
            and dm.useForeverStyle == true
        -- Its Border Style (DM page), latched with it: "slim" (the shipped
        -- line), "textured" (Blizzard's live line; unset, the default, reads
        -- the same) or "heavy" (the heavy frame), each kind that lacks its art
        -- drawing Slim (EllesmereUI.ForeverBorderKind).
        ns._dmFvKind = ns._dmForever and EllesmereUI.ForeverBorderKind(dm.foreverBorder) or nil
        ns._dmFvHeavy = ns._dmFvKind == "heavy"
    end
    return v
end
-- Stock-art mode: true for both stock styles (what they share: no EUI window
-- or bar borders, no header bottom border).
function ns.DMBlizz() return ns.DMStyle() ~= "eui" end
function ns.DMClassic() return ns.DMStyle() == "classic" end
-- WoW Forever variant: DMStyle() still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces. False off Forever.
function ns.DMForever()
    if ns._dmStyle == nil then ns.DMStyle() end
    return ns._dmForever == true
end
-- The WoW Forever windows' Border Style this session: "slim", "textured" or
-- "heavy" (latched with the look). Nil everywhere else.
function ns.DMFvKind()
    if ns._dmStyle == nil then ns.DMStyle() end
    return ns._dmFvKind
end
-- The same kind for another addon's window that wears these windows' frame
-- (the Forever Essentials threat meter reads it through _ModuleNS once, as
-- it sets up its look at login): the profile is opened first, so a read
-- made before this module's own login pass still latches the saved value.
function ns.DMFvKindShared()
    EnsureDB()
    return ns.DMFvKind()
end
-- The WoW Forever windows wear the heavy bronze frame this session (Border
-- Style Heavy Bronze). False everywhere else.
function ns.DMFvHeavy()
    if ns._dmStyle == nil then ns.DMStyle() end
    return ns._dmFvHeavy == true
end
-- Profiles (ProfileChangesStyle's `extra`, handed the incoming dm table):
-- true when that profile would latch another Border Style kind than the one
-- latched this session (the latch above, read off `p`), so the switch asks
-- for a reload.
function ns.DMFvBorderChanged(p)
    local kind
    if type(p) == "table" and not p.useClassicStyle and p.useBlizzardStyle
        and EllesmereUI.IS_FOREVER == true and p.useForeverStyle == true then
        kind = EllesmereUI.ForeverBorderKind(p.foreverBorder)
    end
    return kind ~= ns.DMFvKind()
end
-- The one-time Classic WoW UI seed on a profile `p`: a near-black window
-- (#101010), the game's own bar fill as the bar texture and a quarter-black
-- track behind every bar (once per profile; the controls stay the user's
-- afterwards). Run by the Style page on the switch and at login for a
-- profile that arrived with the flag already set (an import, an older
-- build).
function ns.DMSeedClassic(p)
    if p.classicSeeded then return end
    p.classicSeeded = true
    p.bgR, p.bgG, p.bgB = 16 / 255, 16 / 255, 16 / 255
    p.barTexture = "blizzard"
    p.barBgR, p.barBgG, p.barBgB, p.barBgAlpha = 0, 0, 0, 0.25
    p.barBgUseClassColor = false
end
-------------------------------------------------------------------------------
--  Header art by style and header key. Classic WoW UI takes vanilla button
--  art (each sheet cropped to its visible art: the lock and red X sheets
--  are 32x32 with a 19x18 button at columns 6..24, rows 7..24; the refresh
--  and plus buttons fill their 16x16; the quest log book fills its 64x64
--  bar a texel) and vanilla spell icons for the meter types, drawn a little
--  smaller than the EUI glyphs with a gap between them (the art fills its
--  crop, the glyphs carry their own margin). Blizzard Style keeps the EUI
--  glyphs (no entries). A key with no entry keeps the glyph. Stock art is
--  coloured: no desaturation, no Icon Colour tint, hover is a brightness
--  step, and an entry with hover art swaps it in.
-------------------------------------------------------------------------------
ns.DM_HDR_ART = {
    classic = {
        -- `scale` insets the art inside its button (a full-bleed icon reads
        -- larger than a glyph in the same box); the button keeps its size.
        settings = { file = "Interface\\Icons\\Trade_Engineering", crop = 0.08, scale = 0.9 },
        segment  = { file = "Interface\\QuestFrame\\UI-QuestLog-BookIcon", l = 0.015625, r = 0.96875, t = 0.03125, b = 0.96875 },
        reset    = { file = "Interface\\Buttons\\UI-RefreshButton", scale = 0.9 },
        open     = { file = "Interface\\Buttons\\UI-PlusButton-Up" },
        close    = { file = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
        locked   = { file = "Interface\\Buttons\\LockButton-Locked-Up",   l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
        unlocked = { file = "Interface\\Buttons\\LockButton-Unlocked-Up", l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
        types = {
            [Enum.DamageMeterType.DamageDone]           = { file = "Interface\\Icons\\INV_Sword_04", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.HealingDone]          = { file = "Interface\\Icons\\Spell_Holy_Heal", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.DamageTaken]          = { file = "Interface\\Icons\\Ability_Warrior_ShieldWall", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.AvoidableDamageTaken] = { file = "Interface\\Icons\\Spell_Fire_Fire", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.EnemyDamageTaken]     = { file = "Interface\\Icons\\INV_Sword_27", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.Interrupts]           = { file = "Interface\\Icons\\Ability_Kick", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.Dispels]              = { file = "Interface\\Icons\\Spell_Holy_DispelMagic", crop = 0.08, scale = 0.85 },
            [Enum.DamageMeterType.Deaths]               = { file = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", crop = 0.08, scale = 0.85 },
        },
    },
}
ns.DM_HDR_IDLE, ns.DM_HDR_HOVER = 0.85, 1
ns.DM_HDR_CLASSIC_SCALE, ns.DM_HDR_CLASSIC_PAD = 0.85, 2
-- The stock-style art entry for a header key this session (nil = EUI glyph).
-- WoW Forever reads its own set; an atlas entry the client lacks keeps the
-- glyph.
function ns.DMHdrArt(key)
    local style = ns.DMStyle()
    local set = ns.DM_HDR_ART[ns._dmForever and "forever" or style]
    local art = set and set[key] or nil
    if art and art.atlas and not ns.DMFvAtlas(art.atlas) then return nil end
    return art
end
-- Header button size for a config (the Icon Size setting; the Spell History
-- header passes nil for its fixed 22), and the gap between buttons: the
-- classic art draws at 85% with a 2px gap, WoW Forever's plates a little
-- smaller with their own gap, the glyphs at full size 2px overlapped (their
-- margin is in the file).
function ns.DMHdrIconSize(cfg)
    local sz = (cfg and cfg.hdrIconSize) or 22
    if ns.DMStyle() == "classic" then sz = math.floor(sz * ns.DM_HDR_CLASSIC_SCALE + 0.5) end
    if ns._dmForever then sz = math.floor(sz * ns.DM_FV.btnScale + 0.5) end
    return sz
end
function ns.DMHdrIconPad()
    if ns.DMStyle() == "classic" then return ns.DM_HDR_CLASSIC_PAD end
    if ns._dmForever then return ns.DM_FV.btnPad end
    return -2
end
-- Seats a header icon texture in its button: full-bleed, or inset to its
-- art entry's `scale` (relative anchors, so the button's current size
-- decides; re-run after a resize).
function ns.DMSeatHdrArt(tex, size)
    local btn = tex:GetParent()
    local art = tex._hdrArt
    local k = art and art.scale
    tex:ClearAllPoints()
    if k and k < 1 then
        local inset = ((size or btn:GetWidth()) * (1 - k)) / 2
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
    else
        tex:SetAllPoints(btn)
    end
end
-- Paints an art entry on a header icon texture and stamps it (tex._hdrArt)
-- for the hover pass. An atlas is never followed by SetTexCoord. An entry
-- with `tint` is a desaturated glyph in that colour, one with `plate` sits
-- on WoW Forever's square button plate (ns.DMFvPlate).
function ns.DMApplyHdrArt(tex, art)
    tex._hdrArt = art
    tex:SetDesaturated(art.tint ~= nil)
    if art.atlas then
        tex:SetAtlas(art.atlas)
    else
        tex:SetTexture(art.file)
        if art.crop then
            tex:SetTexCoord(art.crop, 1 - art.crop, art.crop, 1 - art.crop)
        else
            tex:SetTexCoord(art.l or 0, art.r or 1, art.t or 0, art.b or 1)
        end
    end
    local k, c = ns.DM_HDR_IDLE, art.tint
    if c then tex:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, 1) else tex:SetVertexColor(k, k, k, 1) end
    if art.plate or tex._fvPlate then ns.DMFvPlate(tex, false) end
    ns.DMSeatHdrArt(tex)
end
-- Paints a header key's stock art on a texture; false when the key keeps
-- the EUI glyph (the caller paints that).
function ns.DMPaintHdrArt(tex, key)
    local art = ns.DMHdrArt(key)
    if not art then
        tex._hdrArt = nil
        if tex._fvPlate then tex._fvPlate:Hide() end
        return false
    end
    ns.DMApplyHdrArt(tex, art)
    return true
end
-- Hover / idle (and the dimmed state a locked window puts on its close
-- icon) on a stock-art texture; false when the texture carries the EUI
-- glyph, whose tint the caller owns.
function ns.DMHdrHover(tex, hover, dimmed)
    local art = tex._hdrArt
    if not art then return false end
    if art.hover then tex:SetAtlas(hover and art.hover or art.atlas) end
    local k, c = hover and ns.DM_HDR_HOVER or ns.DM_HDR_IDLE, art.tint
    if c then
        tex:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, dimmed and 0.5 or 1)
    else
        tex:SetVertexColor(k, k, k, dimmed and 0.5 or 1)
    end
    if art.plate then ns.DMFvPlate(tex, hover) end
    return true
end
-- The mode button's icon for a meter type: the vanilla spell icon under
-- Classic WoW UI, the tinted glyph on a plate under WoW Forever, the EUI
-- glyph otherwise (its desaturation and tint were set when the button was
-- built and stay).
function ns.DMSetTypeIcon(tex, dmType)
    local style = ns.DMStyle()
    local set = ns.DM_HDR_ART[ns._dmForever and "forever" or style]
    local art = set and set.types and set.types[dmType]
    if art then ns.DMApplyHdrArt(tex, art); return end
    tex._hdrArt = nil
    tex:SetTexture(DM_TYPE_ICONS[dmType] or DM_TYPE_ICONS[Enum.DamageMeterType.DamageDone])
end
-- A texture as the tiled tooltip background in the given colour and opacity
-- (the file is near-white; the vertex colour is the tone). Tiling is set up
-- once per texture; every call re-tints.
function ns.DMClassicTint(tex, r, g, b, a)
    if not tex._classicTiled then
        tex._classicTiled = true
        tex:SetHorizTile(true); tex:SetVertTile(true)
        tex:SetTexture(ns.DM_CLASSIC_BG, "REPEAT", "REPEAT")
    end
    tex:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
end
-- Header background: the stock atlas (opacity still applies) under Blizzard
-- Style, Forever's header band in its place under the WoW Forever variant
-- (ns.DMFvHeader); under Classic WoW UI the window's tooltip background
-- again as a lighter band (the header's own colour is not used, its opacity
-- is), the way the stock meter's header stands off its body: the window
-- colour is the trailing winR/winG/winB when given (a window body tinted
-- from its own settings), the main meter's otherwise; the configured colour
-- on the EUI look.
function ns.DMPaintHeaderBg(tex, r, g, b, a, winR, winG, winB)
    local style = ns.DMStyle()
    if style == "blizzard" then
        if ns._dmForever and ns.DMFvHeader(tex, a) then return end
        tex:SetAtlas(ns.DM_BLIZZ_HEADER)
        tex:SetVertexColor(1, 1, 1, a)
    elseif style == "classic" then
        local c, k, lift = ns.EDM.DB(), ns.DM_CLASSIC_HDR_SHADE, ns.DM_CLASSIC_HDR_LIFT
        ns.DMClassicTint(tex,
            math.min(1, (winR or c.bgR or 0) * k + lift),
            math.min(1, (winG or c.bgG or 0) * k + lift),
            math.min(1, (winB or c.bgB or 0) * k + lift), a)
    else
        tex:SetColorTexture(r, g, b, a)
    end
end
-- Classic WoW UI window edge: the vanilla chat tab's own border, the art the
-- classic chat tabs wear, cut from Interface\ChatFrame\ChatFrameTab (64x32,
-- greyscale; measured on the sheet): a 2px soft black shadow outside, a 1px
-- opaque grey rim (row 11 on top, brighter than the side rims at columns 4
-- and 59) and a 2px darker bevel inside, rounded top corners stepping in
-- about 2px, a flat 40% black inside and an open bottom. So every piece is
-- 5x5 at 1x: the top corners at columns 2..6 / 57..61, rows 9..13; the top
-- edge from one uniform block of the top rim (columns 24..31); the side
-- edges from rows 20..23; the bottom pieces are the top ones flipped (the
-- art carries no top-to-bottom lighting). Edges stretch along their length
-- (a cut from a sheet cannot tile). Corners first in this table:
-- { point, left, right, top, bottom }.
ns.DM_CLASSIC_EDGE_UV = {
    { "TOPLEFT",     0.03125,  0.109375, 0.28125, 0.4375  },
    { "TOPRIGHT",    0.890625, 0.96875,  0.28125, 0.4375  },
    { "BOTTOMLEFT",  0.03125,  0.109375, 0.4375,  0.28125 },
    { "BOTTOMRIGHT", 0.890625, 0.96875,  0.4375,  0.28125 },
    { "TOP",         0.375,    0.5,      0.28125, 0.4375  },
    { "BOTTOM",      0.375,    0.5,      0.4375,  0.28125 },
    { "LEFT",        0.03125,  0.109375, 0.625,   0.75    },
    { "RIGHT",       0.890625, 0.96875,  0.625,   0.75    },
}
-- The eight edge pieces as regions of the window frame, lying along the
-- INSIDE of its rect (the window's rect is the box; the header and rows sit
-- DM_CLASSIC_INSET inside it, past the rim and bevel): corners pinned to the
-- window's corners, edges spanning between them. Built once per window.
function ns.DMClassicEdge(win, e)
    local p = {}
    for i = 1, 8 do
        local spec = ns.DM_CLASSIC_EDGE_UV[i]
        local t = win:CreateTexture(nil, "BORDER")
        t:SetTexture(ns.DM_CLASSIC_EDGE)
        t:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
        if i <= 4 then t:SetSize(e, e) end
        p[spec[1]] = t
    end
    -- Inside the window's rect: the rim sits two pixels in from the edge,
    -- the tile starts under the bevel, the header and rows sit past it.
    p.TOPLEFT:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    p.TOPRIGHT:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    p.BOTTOMLEFT:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    p.BOTTOMRIGHT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT", 0, 0)
    p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
    p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
    p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT", 0, 0)
    p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT", 0, 0)
    p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
    p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
    p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT", 0, 0)
end
-- Classic WoW UI window background. Without `edged` the bg texture paints
-- nothing: the panel sits inside a window that already wears the box (the
-- breakdown source panel, shown over the window's own tile). With it the
-- window carrying the texture wears the whole classic box: the tinted
-- tooltip tile spanning the window rect inside the rim, the eight chat tab
-- edge pieces along the rect's inside, and the bg texture itself paints
-- nothing. The tab's own inside is pure black (no vertex tint could colour
-- it), so the window keeps the tile as its body. All regions of the window
-- frame, under every child; built once per bg texture, re-tinted per call.
function ns.DMPaintClassicBg(tex, r, g, b, a, edged)
    if not edged then
        tex:SetTexture(nil)
        tex:SetColorTexture(0, 0, 0, 0)
        return
    end
    local tile = tex._classicBg
    if not tile then
        local win = tex:GetParent()
        local e, inset = ns.DM_CLASSIC_EDGE_SIZE, ns.DM_CLASSIC_BODY
        tile = win:CreateTexture(nil, "BACKGROUND", nil, -8)
        -- The tile starts right under the bevel: the rim's opaque corner
        -- pixels cover its square corners (so the corners read rounded) and
        -- the bevel darkens its edge rather than showing the world through.
        tile:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -inset)
        tile:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, inset)
        ns.DMClassicEdge(win, e)
        tex._classicBg = tile
        tex:SetTexture(nil)
        tex:SetColorTexture(0, 0, 0, 0)
    end
    ns.DMClassicTint(tile, r, g, b, a)
end
-- How far the header and the row area sit inside the window under Classic
-- WoW UI (past the rim and bevel) and WoW Forever (past the bronze line, or
-- the heavy frame's band), zero on every other look so the anchors below are
-- exactly what they were.
function ns.DMClassicInset()
    if ns.DMClassic() then return ns.DM_CLASSIC_INSET end
    if ns._dmFvHeavy then return ns.DM_FV.heavyInset end
    if ns._dmForever and EUI.ForeverBorderOK() then return ns.DM_FV.inset end
    return 0
end
-- The header's bottom line under Classic WoW UI: one hairline (h = the
-- caller's physical pixel) in the chat tab rim's own grey (0x68 on the top
-- rim), whatever the header border setting says (that line is an EUI-look
-- control). Returns true when it painted.
function ns.DMClassicSeparator(tex, h)
    if not ns.DMClassic() then return false end
    tex:SetHeight(h)
    tex:SetColorTexture(0.41, 0.41, 0.41, 1)
    tex:Show()
    return true
end
-- Window background: the configured colour on the EUI look; the classic box
-- above under Classic WoW UI (`edged` = this texture's window wears the edge).
-- Under Blizzard Style the stock panel atlas is plain black with an alpha ramp
-- baked in -- transparent at the top edge, opaque about a third of the way
-- down (50 of its 148 rows, stretched with the window), and a short fade at
-- the bottom -- far too heavy on a tall window. Drawn from parts instead
-- (user ruling: half the strength, the top 20px only, no bottom fade): a
-- 20px top band running from half the body alpha up to it over a flat black
-- body, both hung off the bg texture's own rect (the window code owns that
-- rect and re-anchors it under the header), which itself paints nothing.
-- Parts are created once per bg texture; every call re-colours them with
-- the configured opacity multiplied in.
ns.DM_BLIZZ_BG_BODY = 245 / 255
ns._dmBgLo = CreateColor(0, 0, 0, 1)
ns._dmBgHi = CreateColor(0, 0, 0, 0.5)
function ns.DMPaintWindowBg(tex, r, g, b, a, edged)
    local style = ns.DMStyle()
    if style == "eui" then
        local key = ns.EDM.DB().bgTexture or "none"
        local path = key ~= "none" and EUI.ResolveTexturePath(_G._EDM_BarTextures, key, nil)
        if path then
            tex:SetTexture(path)
            tex:SetVertexColor(r, g, b, a)
            tex._dmTexturedBg = true
        else
            if tex._dmTexturedBg then
                tex:SetVertexColor(1, 1, 1, 1)
                tex._dmTexturedBg = nil
            end
            tex:SetColorTexture(r, g, b, a)
        end
        return
    elseif style == "classic" then
        ns.DMPaintClassicBg(tex, r, g, b, a, edged)
        return
    end
    if ns._dmForever and ns.DMPaintForeverBg(tex, a, edged) then return end
    local parts = tex._blizzParts
    if not parts then
        local parent = tex:GetParent()
        local layer, sub = tex:GetDrawLayer()
        parts = {}
        for i = 1, 2 do
            local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
            parts[i] = t
        end
        parts[1]:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
        parts[1]:SetPoint("TOPRIGHT", tex, "TOPRIGHT", 0, 0)
        parts[1]:SetHeight(20)
        parts[2]:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, -20)
        parts[2]:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        tex._blizzParts = parts
        tex:SetTexture(nil)
        tex:SetColorTexture(0, 0, 0, 0)
    end
    local body = ns.DM_BLIZZ_BG_BODY * (a or 1)
    ns._dmBgLo:SetRGBA(0, 0, 0, body)
    ns._dmBgHi:SetRGBA(0, 0, 0, body * 0.5)
    -- VERTICAL gradients run bottom -> top.
    parts[1]:SetGradient("VERTICAL", ns._dmBgLo, ns._dmBgHi)
    parts[2]:SetGradient("VERTICAL", ns._dmBgLo, ns._dmBgLo)
end
-- Bar fill: the user's own texture keeps its colour (the stock fill art is
-- pre-coloured and halves every tint, the ruling the unit frames and plates
-- follow), and the bevel that art bakes in is drawn over the filled part:
-- four gradient strips anchored to the fill TEXTURE so they follow the
-- value, above the fill and under the edge highlight and the texts. Created
-- once per fill; re-anchored only when the texture object or the height
-- changes (a path swap mints a new texture object), so refresh passes pay
-- two compares.
ns._dmShadeClear  = CreateColor(0, 0, 0, 0)
ns._dmShadeTop    = CreateColor(0, 0, 0, 0.55)
ns._dmShadeBottom = CreateColor(0, 0, 0, 0.30)
ns._dmShadeEnd    = CreateColor(0, 0, 0, 0.35)
function ns.DMApplyBlizzFill(fill)
    local sh = fill._blizzShadow
    if not sh then
        sh = {}
        fill._blizzShadow = sh
        for i = 1, 4 do
            local tex = fill:CreateTexture(nil, "OVERLAY", nil, -3)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
            sh[i] = tex
        end
        -- VERTICAL runs bottom -> top, HORIZONTAL left -> right.
        sh[1]:SetGradient("VERTICAL", ns._dmShadeClear, ns._dmShadeTop)
        sh[2]:SetGradient("VERTICAL", ns._dmShadeBottom, ns._dmShadeClear)
        sh[3]:SetGradient("HORIZONTAL", ns._dmShadeEnd, ns._dmShadeClear)
        sh[4]:SetGradient("HORIZONTAL", ns._dmShadeClear, ns._dmShadeEnd)
    end
    local ft = fill:GetStatusBarTexture()
    local h = fill:GetHeight()
    -- A bar carrying secret values (the tooltip preview rows in combat)
    -- reports a secret height; the last plain height stands in, then the
    -- row default, so nothing here ever compares a secret.
    if issecretvalue and issecretvalue(h) then h = sh._h or 18 end
    h = h or 0
    if h <= 0 then h = 18 end
    if not ft or (sh._tex == ft and sh._h == h) then return end
    sh._tex, sh._h = ft, h
    local top, bottom, ends = math.max(2, math.floor(h * 0.2)), math.max(1, math.floor(h * 0.1)), math.max(2, math.floor(h * 0.15))
    sh[1]:ClearAllPoints(); sh[1]:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0); sh[1]:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0); sh[1]:SetHeight(top)
    sh[2]:ClearAllPoints(); sh[2]:SetPoint("BOTTOMLEFT", ft, "BOTTOMLEFT", 0, 0); sh[2]:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0); sh[2]:SetHeight(bottom)
    sh[3]:ClearAllPoints(); sh[3]:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0); sh[3]:SetPoint("BOTTOMLEFT", ft, "BOTTOMLEFT", 0, 0); sh[3]:SetWidth(ends)
    sh[4]:ClearAllPoints(); sh[4]:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0); sh[4]:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0); sh[4]:SetWidth(ends)
    for i = 1, 4 do sh[i]:Show() end
end
-- Row background: the stock shadowed track under the fill plus its edge
-- highlight over it, both hugging the fill's rect (the shadow style's own
-- insets: the track sits 2px outside the fill on every side, exactly under
-- its edge). One-time per row. WoW Forever wears the same track (a bar
-- texture, not frame art).
function ns.DMApplyBlizzBarBg(bar)
    local bg = bar._bg
    if not bg or not bar.fill then return end
    if bar._blizzBgOn then return end
    bar._blizzBgOn = true
    bg:SetAtlas(ns.DM_BLIZZ_BAR_BG)
    bg:SetVertexColor(1, 1, 1, 1)
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", bar.fill, "TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", bar.fill, "BOTTOMRIGHT", 2, -2)
    local edge = bar.fill:CreateTexture(nil, "OVERLAY", nil, 6)
    edge:SetAtlas(ns.DM_BLIZZ_BAR_EDGE)
    edge:SetPoint("TOPLEFT", bar.fill, "TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", bar.fill, "BOTTOMRIGHT", 2, -2)
end

-------------------------------------------------------------------------------
--  WoW Forever (the Forever client's variant of Blizzard Style: DMStyle()
--  still reads "blizzard", ns.DMForever() gates these). Forever's own art on
--  our windows: the bronze line of Forever's micro menu box the chat panel
--  wears (EllesmereUI.ForeverBorder, on its own child frame, the line inside
--  the window's rect so snapping and size matching are unchanged) over a
--  flat dark body; header buttons on Forever's square plates with tan
--  glyphs, Forever's red close button; Forever's dropdown panel on the
--  menus and its list buttons on the home page (the rows keep Blizzard
--  Style's bar art); gold titles and menu highlights, tan glyphs and timers
--  in place of the EllesmereUI accent. The header bar is Forever's
--  objective tracker header (Forever's art for the retail header bar's own
--  design: a dark body warming toward a lower rail), cut to its warm body
--  and lower bronze rod, the rod running under the frame's side lines.
--  The Border Style (ns.DMFvKind, latched with the look) picks the frame:
--  Slim draws the line from our shipped flat art, Slim Textured from
--  Blizzard's live art, and Heavy Bronze wears the bronze frame of
--  Forever's own windows instead (EllesmereUI.ForeverHeavy, on the same
--  child frame at the art's window scale), the header and rows further in
--  past its rim.
--  Every atlas is probed once and a missing piece leaves plain Blizzard
--  Style in its place. Built on the build paths only; nothing here runs off
--  the variant.
-------------------------------------------------------------------------------
ns.DM_FV = {
    frameLevel = 14,  -- the line over the header and rows, under the resize grip and lock (15, 16)
    inset      = EUI.FOREVER_BORDER.shade, -- header and rows start past the line and its inner shadow
    bodyInset  = EUI.FOREVER_BORDER.fill,  -- the body under the line's inner shadow, its corners inside the chamfers
    -- Heavy Bronze: header and rows start past the rim and its dark line;
    -- the body tucks under the rim, its corners inside the corner cuts.
    heavyInset     = EUI.FOREVER_HEAVY.band,
    heavyBodyInset = EUI.FOREVER_HEAVY.fill,
    -- Header band: a cut of this 300x40 art, as fractions of its box (art
    -- pixels 64..176 across clear its fading ends and the filigree; 9..39
    -- down hold the body, the lower rod and its shadow, leaving out the
    -- upper rod the frame's top line stands in for), drawn hdrReach wider
    -- than the header each side so the rod ends under the side lines.
    header     = "ui-questtracker-primary-objective-header",
    hdrCut     = { 64 / 300, 176 / 300, 9 / 40, 39 / 40 },
    hdrReach   = 2,
    -- The cut's rod and shadow (6 of its 30 rows) under its 24-row body: a
    -- header grows by this share of its height so the body holds the title
    -- and buttons and the rod runs beneath them.
    hdrRail    = 0.25,
    plate      = "common-button-tertiary-square-normal",
    plateHover = "common-button-tertiary-square-hover",
    glyph      = { 0.95, 0.82, 0.60 }, -- x the idle 0.85: the reference's tan
    -- Text in place of the accent: titles and menu highlights (the menu
    -- headers' gold), menu timers.
    gold       = { r = 1, g = 0.82, b = 0 },
    tan        = { r = 174 / 255, g = 157 / 255, b = 129 / 255 },
    close      = "RedButton-Exit",
    btnScale   = 0.86, btnPad = 3,
    menu       = "common-dropdown-bg",
    card       = { normal = "common-button-list-small", hover = "common-button-list-small-hover",
                   selected = "common-button-list-small-selected" },
}
-- Atlas presence, probed once per name.
ns._dmFvAtlas = {}
function ns.DMFvAtlas(name)
    local v = ns._dmFvAtlas[name]
    if v == nil then
        v = C_Texture.GetAtlasInfo(name) ~= nil
        ns._dmFvAtlas[name] = v
    end
    return v
end
-- The bronze line on one of our frames, built once: the pieces (the latched
-- Border Style's art, shipped or Blizzard's live) on a child frame over the
-- owner's content, the line's outer edge on the owner's edge, or with
-- `outside` FOREVER_BORDER.fill past it (the breakdown popup, whose rows
-- and body run flush: its square corners stay inside the chamfers).
-- Heavy Bronze: the bronze window frame there, the child frame drawn at the
-- art's window scale, its rim's outer edge on the owner's edge or, with
-- `outside`, its rim and dark line past it. Nil off the variant or where the
-- frame cannot be drawn.
function ns.DMFvFrameArt(owner, outside)
    if owner._fvRim then return owner._fvRim end
    if ns.DMFvHeavy() then
        local H = EUI.FOREVER_HEAVY
        local host = CreateFrame("Frame", nil, owner)
        host:SetScale(H.k)
        host:SetFrameLevel(owner:GetFrameLevel() + ns.DM_FV.frameLevel)
        host:SetAllPoints(owner)
        local o = outside and H.band * H.k or 0
        EUI.ForeverHeavySeat(EUI.ForeverHeavy(host, "ARTWORK"), owner, "TOPLEFT", -o, o, o, -o)
        owner._fvRim = host
        return host
    end
    if not (ns.DMForever() and EUI.ForeverBorderOK()) then return nil end
    local host = CreateFrame("Frame", nil, owner)
    host:SetFrameLevel(owner:GetFrameLevel() + ns.DM_FV.frameLevel)
    host:SetAllPoints(owner)
    local o = outside and EUI.FOREVER_BORDER.fill or 0
    EUI.ForeverBorderSeat(EUI.ForeverBorder(host, nil, nil, nil, ns._dmFvKind), owner, "TOPLEFT", -o, o, o, -o)
    owner._fvRim = host
    return host
end
-- Window background under WoW Forever. With `edged` the window wears the
-- bronze line over a flat dark body spanning it (from the line's inner
-- edge; Heavy Bronze: the heavy frame, the body tucked under its band;
-- black at the Background Opacity, as Blizzard Style), both regions and
-- frames of the window built once, the body re-tinted per call; the bg
-- texture itself paints nothing. Without it (the breakdown panel inside a
-- window) nothing: the window's body stays up behind it. False where the
-- frame cannot be drawn (the caller paints plain Blizzard Style).
function ns.DMPaintForeverBg(tex, a, edged)
    if not EUI.ForeverBorderOK() then return false end
    local heavy = ns._dmFvHeavy
    if not edged then
        tex:SetTexture(nil)
        tex:SetColorTexture(0, 0, 0, 0)
        return true
    end
    local body = tex._fvBody
    if not body then
        local win = tex:GetParent()
        local e = heavy and ns.DM_FV.heavyBodyInset or ns.DM_FV.bodyInset
        body = win:CreateTexture(nil, "BACKGROUND", nil, -8)
        body:SetPoint("TOPLEFT", win, "TOPLEFT", e, -e)
        body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -e, e)
        tex._fvBody = body
        ns.DMFvFrameArt(win)
        tex:SetTexture(nil)
        tex:SetColorTexture(0, 0, 0, 0)
    end
    body:SetColorTexture(0, 0, 0, ns.DM_BLIZZ_BG_BODY * (a or 1))
    return true
end
-- A header's background as the Forever header band (FV.header cut to
-- FV.hdrCut): an atlas cannot be cropped, so the cut is drawn from the
-- atlas's own sheet file at its coords, reaching FV.hdrReach past the
-- header's sides under the frame. Set up once per texture; every call only
-- re-applies the opacity `a`. False without the art, or where the frame
-- cannot be drawn (the rod needs the side lines, or the heavy frame's
-- bands, over its ends); the caller paints plain Blizzard Style.
function ns.DMFvHeader(tex, a)
    if not tex._fvHdr then
        local FV = ns.DM_FV
        if not (EUI.ForeverBorderOK() and ns.DMFvAtlas(FV.header)) then return false end
        local info = C_Texture.GetAtlasInfo(FV.header)
        local l, t = info.leftTexCoord, info.topTexCoord
        local w, h = info.rightTexCoord - l, info.bottomTexCoord - t
        local c, e, hdr = FV.hdrCut, FV.hdrReach, tex:GetParent()
        tex:SetTexture(info.file or info.filename)
        tex:SetTexCoord(l + w * c[1], l + w * c[2], t + h * c[3], t + h * c[4])
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", hdr, "TOPLEFT", -e, 0)
        tex:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", e, 0)
        tex._fvHdr = true
    end
    tex:SetVertexColor(1, 1, 1, a or 1)
    return true
end
-- The rail the Forever header band adds under a header of height h (the
-- rod and its shadow, below the band's body); 0 off the variant or without
-- the art (the same gates as ns.DMFvHeader).
function ns.DMFvRail(h)
    if not ns.DMForever() then return 0 end
    local FV = ns.DM_FV
    if not (EUI.ForeverBorderOK() and ns.DMFvAtlas(FV.header)) then return 0 end
    return math.floor(h * FV.hdrRail + 0.5)
end
-- How far a header's title and buttons rise to centre on the band's body
-- (h = the header's own height setting; nil = the meter's Header Height).
function ns.DMHdrLift(h)
    return ns.DMFvRail(h or DB().hdrHeight or 22) / 2
end
-- A header glyph's square plate (Forever's button art, normal or hover)
-- under the glyph on its button, built once; hidden when the texture's art
-- entry carries none or the client lacks the art.
function ns.DMFvPlate(tex, hover)
    local FV, art, plate = ns.DM_FV, tex._hdrArt, tex._fvPlate
    local on = art and art.plate and ns.DMFvAtlas(FV.plate) and ns.DMFvAtlas(FV.plateHover)
    if not plate then
        if not on then return end
        local btn = tex:GetParent()
        plate = btn:CreateTexture(nil, "BACKGROUND")
        plate:SetAllPoints(btn)
        tex._fvPlate = plate
    end
    if not on then plate:Hide(); return end
    local atlas = hover and FV.plateHover or FV.plate
    if plate._fvAtlas ~= atlas then plate:SetAtlas(atlas); plate._fvAtlas = atlas end
    plate:Show()
end
-- A context menu panel in Forever's dropdown art (what Blizzard's menus wear
-- on that client: a bronze line round a black body, soft shadow), its line
-- 1px outside our flush panel, in place of the EUI fill and border. False
-- off the variant or without the art.
function ns.DMFvMenuArt(f, bg)
    local atlas = ns.DM_FV.menu
    if not (ns.DMForever() and ns.DMFvAtlas(atlas)) then return false end
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    t:SetAtlas(atlas)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 7)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 10, -13)
    t:SetAlpha(0.925)
    bg:SetColorTexture(0, 0, 0, 0)
    f._fvArt = t
    return true
end
-- A home page card's background as Forever's list button ("normal" |
-- "hover" | "selected"), `a` its opacity (the add button reads fainter).
-- False off the variant or without the art (the caller paints its colour).
function ns.DMFvCard(tex, state, a)
    if not ns._dmForever then return false end
    local C = ns.DM_FV.card
    if not (ns.DMFvAtlas(C.normal) and ns.DMFvAtlas(C.hover) and ns.DMFvAtlas(C.selected)) then return false end
    local atlas = C[state]
    if tex._fvCard ~= atlas then tex:SetAtlas(atlas); tex._fvCard = atlas end
    tex:SetVertexColor(1, 1, 1, a or 1)
    return true
end
-- Header art: our glyphs, desaturated and tan, on the square plates (the
-- meter types too); the close button is Forever's red one. Built by a
-- function so the main chunk gains no locals, on the Forever client only
-- (read only under the variant).
function ns.DMFvHdrArtSet()
    local tint = ns.DM_FV.glyph
    local function G(file) return { file = file, tint = tint, plate = true } end
    local types = {}
    for dmType, file in pairs(DM_TYPE_ICONS) do types[dmType] = G(file) end
    return {
        settings = G(MEDIA .. "dm_settings.png"),
        segment  = G(MEDIA .. "dm_sheet.png"),
        reset    = G(MEDIA .. "dm_undo.png"),
        open     = G(MEDIA .. "dm_open.png"),
        close    = { atlas = ns.DM_FV.close },
        locked   = G(MEDIA .. "dm_locked_top.png"),
        unlocked = G(MEDIA .. "dm_unlock_top.png"),
        resize   = G(MEDIA .. "dm_width_resize.png"),
        types    = types,
    }
end
if EllesmereUI.IS_FOREVER then ns.DM_HDR_ART.forever = ns.DMFvHdrArtSet() end

I.broken = false
