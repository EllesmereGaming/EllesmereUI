if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_StockStyles.lua
--
--  Stock styles (Global Settings > Style): the Blizzard, Classic and WoW
--  Forever art kits and the post-pass that lays them over the built frames.
--  Loads after the main file and reads it through ns and ns._internals;
--  db is set through I.dbSetters when EllesmereUF:OnInitialize creates the DB.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local frames, GetSettingsForUnit, UnsnapTex = I.frames, I.GetSettingsForUnit, I.UnsnapTex
local CastbarUnlockKey, CreatePowerBar, ApplyFramePosition = I.CastbarUnlockKey, I.CreatePowerBar, I.ApplyFramePosition
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style). A stock unit frame look on our own
--  frames: the frame art, portrait masks, bar shapes and bar placement of one
--  ART KIT, applied as an idempotent post-pass over the built EUI frame so
--  every EUI feature (text zones, auras, absorbs, cast bars, class power,
--  unlock movers) keeps working; only the EUI-look settings step aside. The
--  pass runs after every geometry re-apply (UpdateBordersForScale, the class
--  power re-anchor, the ReloadFrames sweep), creates its regions once per
--  frame, and costs nothing while the style is off. Two kits share the pass:
--  ns.UF_KITS.blizzard (Blizzard Style: the current stock atlases, rounded
--  masks and bevels) and ns.UF_KITS.classic (Classic WoW UI: the vanilla
--  frame files, plain rectangular bars). ns.UF_BLIZZ is the ACTIVE kit,
--  pointed at the latched style once per session (ns.UF_Style). An art entry
--  is an atlas name (validated once per session; a missing one leaves that
--  piece on the EUI look) or a file descriptor { key, file, l, r, t, b, w,
--  h, point, x, y }. Reload-gated per-profile flags. ns fields only:
--  written under the main file's local cap.
-------------------------------------------------------------------------------
ns.UF_BLIZZ = {
    player = {
        w = 232, h = 100, hit = { 6, 0, 4, 9 }, side = "left",
        -- Insets from the stock box to the visible art (the 198x71 atlas is
        -- centred in the box; measured from its alpha): what auras, anchors and
        -- the unlock mover line up with.
        vis = { l = 20, r = 18, t = 16.5, b = 15.5 },
        -- Transparent rows above / below the visible art (the options preview
        -- trims them; the live frame keeps the stock box for its hit rect).
        -- Same rows as vis, so the preview and the live alignment agree.
        pad = { top = 16.5, bottom = 15.5 },
        art = "UI-HUD-UnitFrame-Player-PortraitOn",
        -- The player mask squares off the lower-right corner (under the bars);
        -- rawArt = the client's own round crop is switched off so it shows.
        portrait = { point = "TOPLEFT", x = 24, y = -19, size = 60, mask = "UI-HUD-UnitFrame-Player-Portrait-Mask", rawArt = true },
        health = { x = 85, y = 40, w = 124, h = 20,
                   atlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
                   mask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask", mx = -2, my = 6 },
        power = { x = 85, y = 61, w = 124, h = 10,
                  prefix = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-",
                  mask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", mx = -2, my = 2 },
        name = { point = "TOPLEFT", x = 88, y = -27, w = 96 },
        -- Level number in the art's level circle (right end of the name bar).
        level = { point = "TOPRIGHT", x = -24.5, y = -28, justify = "RIGHT" },
    },
    target = {
        w = 232, h = 100, hit = { 0, 5, 4, 9 }, side = "right",
        vis = { l = 20, r = 21, t = 17.5, b = 17.5 },
        pad = { top = 17.5, bottom = 17.5 },
        art = "UI-HUD-UnitFrame-Target-PortraitOn",
        artRare = "UI-HUD-UnitFrame-Target-Rare-PortraitOn",
        portrait = { point = "TOPRIGHT", x = -26, y = -19, size = 58, mask = "CircleMask" },
        health = { x = 23, y = 40, w = 126, h = 20,
                   atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
                   mask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", mx = -1, my = 6 },
        power = { x = 23, y = 61, w = 134, h = 10,
                  prefix = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-",
                  mask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask", mx = -61, my = 3 },
        rep = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Type", x = -75, y = -25 },
        -- Level number on the type strip: the stock frame puts it in the
        -- circle at the strip's LEFT end (-133,-2 off the strip's top-right),
        -- but every frame keeps its level on the RIGHT here (user ruling), so
        -- it sits right-aligned where the name ends, just before the portrait
        -- ring, and the name gives up that much width (nameTrim).
        level = { point = "TOPRIGHT", x = -91, y = -27, justify = "RIGHT", nameTrim = 26 },
        name = { point = "TOPLEFT", x = 30, y = -26, w = 120 },
        boss = { gold = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold",
                 silver = "ui-hud-unitframe-target-portraiton-boss-rare-silver",
                 winged = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged" },
    },
    mini = {
        w = 120, h = 49, hit = { 0, 0, 0, 0 }, side = "left", small = true,
        vis = { l = 2, r = 1, t = 3, b = 1 },
        art = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
        portrait = { point = "TOPLEFT", x = 5, y = -5, size = 37, mask = "CircleMask" },
        health = { x = 44, y = 17, w = 70, h = 10,
                   atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health",
                   mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask", mx = -29, my = 3 },
        power = { x = 40, y = 28, w = 74, h = 7,
                  prefix = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-",
                  mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask", mx = -27, my = 4 },
        name = { point = "TOPLEFT", x = 44, y = -5, w = 68 },
    },
}
ns.UF_CAST_BLIZZ = {
    bg      = { "ui-castingbar-background",       "UI-CastingBar-Background" },
    frame   = { "ui-castingbar-frame",            "UI-CastingBar-Frame" },
    textbox = { "ui-castingbar-textbox",          "UI-CastingBar-TextBox" },
    cast    = { "ui-castingbar-filling-standard", "UI-CastingBar-Fill" },
    channel = { "ui-castingbar-filling-channel",  "UI-CastingBar-Fill" },
}
-- Classic WoW UI: the vanilla frames. The 256x128 frame sheet is drawn as
-- the 230x99 region the stock frame samples (x 26..256, y 1..100), which
-- also holds the elite, rare and boss variants' dragons; the player frame
-- samples it flipped so its portrait ring sits on the left. Bars are plain
-- rectangles in the art's transparent tracks (no masks, no bevel), the
-- portrait a plain round crop. Every art draws OVER the bars: its tracks are
-- windows in opaque art whose rim overlaps the fills' edges, which is the
-- look; a fill drawn over the art covers that rim. Sizes at 1x.
ns.UF_CLASSIC_SHEET = "Interface\\TargetingFrame\\UI-TargetingFrame"
ns.UF_KITS = {}
ns.UF_KITS.blizzard = ns.UF_BLIZZ
ns.UF_KITS.classic = {
    noBevel = true,
    skull = { key = "c-skull", file = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", w = 16, h = 16 },
    -- The vanilla cast bar frame: the shared nine-slice in
    -- EllesmereUI_ClassicArt.lua round the bar (caps and rims at the sheet's
    -- own pixel size, only the window stretching); `frame` is the file the
    -- presence probe checks before it is drawn.
    cast = {
        frame = { key = "c-castframe", file = "Interface\\CastingBar\\UI-CastingBar-Border" },
    },
    player = {
        w = 232, h = 100, hit = { 21, 19, 12, 15 }, side = "left", artAbove = true,
        vis = { l = 19.5, r = 19.5, t = 11.5, b = 11.5 },
        pad = { top = 11.5, bottom = 11.5 },
        art = { key = "c-player", file = ns.UF_CLASSIC_SHEET, l = 1, r = 0.1015625, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = -18.5, y = -4 },
        -- The dark plaque behind the name and both bars.
        back = { x = 89.5, y = 26, w = 119, h = 41 },
        portrait = { point = "TOPLEFT", x = 24, y = -16, size = 64, mask = "CircleMask" },
        health = { x = 90, y = 45, w = 119, h = 12 },
        power  = { x = 90, y = 56, w = 119, h = 12 },
        name  = { point = "CENTER", x = 34, y = 15, w = 100, justify = "CENTER" },
        -- Level number in the ring under the portrait. The ring is an oval
        -- in the sheet (28 wide, 24 tall) centred 35.6 from the frame's left
        -- and 31.4 up from its bottom, measured on the client's own render;
        -- the box sits half a unit right and under that so the digits' ink,
        -- which rides a little above and left of its box's middle, lands
        -- on the ring's middle.
        level = { point = "CENTER", relPoint = "BOTTOMLEFT", x = 36, y = 30.5, justify = "CENTER" },
    },
    target = {
        w = 232, h = 100, hit = { 19, 21, 12, 15 }, side = "right", artAbove = true,
        vis = { l = 19.5, r = 19.5, t = 11.5, b = 11.5 },
        pad = { top = 11.5, bottom = 11.5 },
        art = { key = "c-target", file = ns.UF_CLASSIC_SHEET, l = 0.1015625, r = 1, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = 18.5, y = -4 },
        -- Whole-frame variants by classification (the dragon is part of the art).
        artByClass = {
            elite     = { key = "c-elite",     file = ns.UF_CLASSIC_SHEET .. "-Elite",      l = 0.1015625, r = 1, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = 18.5, y = -4 },
            rareelite = { key = "c-rareelite", file = ns.UF_CLASSIC_SHEET .. "-Rare-Elite", l = 0.1015625, r = 1, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = 18.5, y = -4 },
            rare      = { key = "c-rare",      file = ns.UF_CLASSIC_SHEET .. "-Rare",       l = 0.1015625, r = 1, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = 18.5, y = -4 },
            boss      = { key = "c-boss",      file = "Interface\\TargetingFrame\\UI-UnitFrame-Boss", l = 0.1015625, r = 1, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = 18.5, y = -4 },
        },
        back = { x = 23.5, y = 26, w = 119, h = 41 },
        portrait = { point = "TOPRIGHT", x = -24, y = -16, size = 64, mask = "CircleMask" },
        health = { x = 23, y = 45, w = 119, h = 12 },
        power  = { x = 23, y = 56, w = 119, h = 12 },
        -- The name plaque behind the name, tinted by the unit's selection
        -- colour, under the art (the art's name window shows it).
        rep = { art = { key = "c-namebg", file = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground", w = 119, h = 19 },
                point = "TOPRIGHT", x = -90, y = -26, below = true },
        name  = { point = "CENTER", x = -34, y = 15, w = 100, justify = "CENTER" },
        -- The player ring's measured centre, mirrored.
        level = { point = "CENTER", relPoint = "BOTTOMRIGHT", x = -36, y = 30.5, justify = "CENTER" },
    },
    -- Target-of-target / focus-target.
    mini = {
        w = 93, h = 45, hit = { 0, 0, 0, 0 }, side = "left", small = true, artAbove = true,
        vis = { l = 2, r = 1, t = 3, b = 1 },
        art = { key = "c-tot", file = "Interface\\TargetingFrame\\UI-TargetofTargetFrame", l = 0.015625, r = 0.7265625, t = 0, b = 0.703125, w = 93, h = 45 },
        back = { x = 42, y = 17, w = 46, h = 15 },
        portrait = { point = "TOPLEFT", x = 6, y = -6, size = 35, mask = "CircleMask" },
        health = { x = 45, y = 15, w = 46, h = 7 },
        power  = { x = 45, y = 23, w = 46, h = 7 },
        name = { point = "TOPLEFT", x = 42, y = -33, w = 49, justify = "LEFT" },
    },
    pet = {
        w = 128, h = 53, hit = { 7, 10, 6, 7 }, side = "left", small = true, artAbove = true,
        vis = { l = 2, r = 1, t = 3, b = 1 },
        art = { key = "c-pet", file = "Interface\\TargetingFrame\\UI-SmallTargetingFrame", w = 128, h = 64, point = "TOPLEFT", x = 0, y = -2 },
        portrait = { point = "TOPLEFT", x = 7, y = -6, size = 37, mask = "CircleMask" },
        health = { x = 47, y = 22, w = 69, h = 8 },
        power  = { x = 47, y = 29, w = 69, h = 8 },
        name = { point = "TOPLEFT", x = 50, y = -9, w = 70, justify = "LEFT" },
    },
}
-- WoW Forever (a Blizzard Style variant, Forever client only): the stock kit,
-- whose atlas names the client already paints with its Forever art, plus the
-- Forever layout -- the level in a round badge at the frame's bottom corner
-- (the target's skull centred in it, the target name widened into the strip
-- the level left), a round PvP badge, Forever's dragon offsets and the
-- silver-winged dragon on rares too. The badge hangs below the art, so the
-- visible bottom edge (auras, cast bar, mover) is the badge's. Built once,
-- when the variant latches.
function ns.UF_ForeverKit()
    local k = ns.UF_KITS.forever
    if k then return k end
    k = CopyTable(ns.UF_KITS.blizzard)
    local circle = "UI-HUD-UnitFrame-SmallCircle"
    local P, T = k.player, k.target
    P.badge = { point = "BOTTOMLEFT", x = 13, y = 7, size = 39, atlas = circle }
    P.level = { point = "CENTER", x = 0, y = -0.5, justify = "CENTER", skullDy = 0.5 }
    P.pvp = { point = "TOP", relPoint = "TOPLEFT", x = 20, y = -50, scale = 0.8, atlas = circle }
    P.vis.b, P.pad.bottom = 7, 7
    T.badge = { point = "BOTTOMRIGHT", x = -13, y = 7, size = 39, atlas = circle }
    T.level = { point = "CENTER", x = 0, y = -0.5, justify = "CENTER", skullDy = 0.5 }
    T.name = { point = "TOPLEFT", x = 24, y = -26, w = 117 }
    T.pvp = { point = "TOP", relPoint = "TOPRIGHT", x = -23, y = -50, scale = 0.8, atlas = circle }
    T.vis.b, T.pad.bottom = 7, 7
    T.boss.silver = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged"
    T.boss.silverRare = true
    T.boss.pos = { winged = { 11, -4 }, silver = { 8, -7 }, gold = { 0, 1 } }
    ns.UF_KITS.forever = k
    return k
end
ns._ufAtlasMemo = {}
-- The style this module renders: "eui", "blizzard" or "classic". Read from
-- the profile once (first call with a profile present) and latched for the
-- session, pointing ns.UF_BLIZZ at the kit: a live profile switch never flips
-- the look under the one-time art setup; the profile system prompts for a
-- reload instead. The Classic flag wins when both flags are set.
function ns.UF_Style()
    local v = ns._ufStyle
    if v == nil then
        local p = db and db.profile
        if not p then return "eui" end
        v = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "eui"
        ns._ufStyle = v
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        ns._ufForever = v == "blizzard" and EllesmereUI.IS_FOREVER == true
            and p.useForeverStyle == true
        if v == "classic" then ns.UF_BLIZZ = ns.UF_KITS.classic end
        if ns._ufForever then ns.UF_BLIZZ = ns.UF_ForeverKit() end
    end
    return v
end
-- Stock-art mode: a kit dictates the geometry (true for both stock styles).
function ns.UF_Blizz() return ns.UF_Style() ~= "eui" end
-- WoW Forever variant: UF_Style() still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces. False off Forever.
function ns.UF_Forever()
    if ns._ufStyle == nil then ns.UF_Style() end
    return ns._ufForever == true
end
-- The class resource style that builds. WoW Forever outside its own style
-- has no Blizzard class resource bar to adopt, so a saved "blizzard" builds
-- as modern there. Read-side only: the saved style is never rewritten.
-- nil on every other client (readers test the field).
if EllesmereUI.IS_FOREVER == true then
    function ns.UF_ForeverCPStyle(style)
        if style == "blizzard" and not ns.UF_Forever() then return "modern" end
        return style
    end
end
-- A custom frame border Color Custom Borders can copy (the player's Dispel
-- Overlay cog): a Border Style other than Solid with a size, under the
-- EllesmereUI style. Read from the saved keys, like the options gate, so a
-- saved true stands down under a stock style or a Solid border.
function ns.UF_CustomBorderOn(s)
    if ns.UF_Blizz() then return false end
    local tex = s and s.borderTexture
    if tex == nil or tex == "" or tex == "solid" then return false end
    return (s.borderSize or 1) > 0
end
-- Blizzard Style's coloured type strip over the target-family name ("Blizz
-- Colored Target Header", on unless the unit's settings turn it off, which
-- leaves the header uncoloured like the player frame's). Classic keeps its
-- name plaque either way.
function ns.UF_BlizzHeaderOn(s)
    return not (ns.UF_Style() == "blizzard" and s and s.blizzColoredHeader == false)
end
-- The stock-style seeds on the profile `p` for `styleKey` ("blizzard" |
-- "classic"). Once per profile: the "Blizzard" cast fill (the vanilla cast
-- bar's own texture) as the cast bar texture, and under Classic the Plating
-- health bar texture on every frame (per-frame choices cleared so they
-- inherit it). Once per style switch: the
-- player frame's combat indicator on the portrait, in the style's own icon
-- (the Classic icon under Classic WoW UI, the Dungeoneer icon under
-- Blizzard Style), so each stock look starts with its matching indicator
-- while a later choice stands until the style changes again. Run by the
-- Style page on the switch and at enable for a profile that arrived already
-- switched (an import, an older build).
ns.UF_STOCK_COMBAT = { classic = "combat2", blizzard = "combat1" }
-- Frames whose own bar texture key overrides (or inherits) the global one.
ns.UF_TEXTURE_UNITS = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss" }
-- The keys the Style page keeps per style for this module (its SLOT_KEYS).
function ns.UF_StyleSlotKeys()
    local k = { "castBarTexture", "healthBarTexture",
                "player.combatIndicatorStyle", "player.combatIndicatorPosition" }
    local units = ns.UF_TEXTURE_UNITS
    for i = 1, #units do k[#k + 1] = units[i] .. ".healthBarTexture" end
    return k
end
-- The WoW Forever variant's own seed: its combo point arc (the "Blizzard"
-- class resource there), once per profile. The Style page keeps these keys
-- in a Forever-only slot (p._foreverStyleSlots): the other looks' values are
-- banked on the way into the variant and come back on the way out.
function ns.UF_SeedForever(p)
    if not (p and p.player) or p.foreverClassPowerSeeded then return end
    p.foreverClassPowerSeeded = true
    p.player.classPowerStyle = "blizzard"
    p.player.showClassPowerBar = true
end
-- `isForever`: the WoW Forever variant of Blizzard Style, which also runs
-- its own seed (UF_SeedForever).
function ns.UF_SeedStock(p, styleKey, isForever)
    if not p then return end
    if isForever then ns.UF_SeedForever(p) end
    if not p.stockCastTextureSeeded then
        p.stockCastTextureSeeded = true
        p.castBarTexture = "blizzard"
    end
    -- Classic WoW UI: "Plating" as the bar texture, once per profile (the
    -- controls stay the user's afterwards): the global key, with each frame's
    -- own override cleared so every frame (and its power bar) follows it.
    if styleKey == "classic" and not p.classicTextureSeeded then
        p.classicTextureSeeded = true
        p.healthBarTexture = "plating"
        local units = ns.UF_TEXTURE_UNITS
        for i = 1, #units do
            local s = p[units[i]]
            if type(s) == "table" then s.healthBarTexture = nil end
        end
    end
    local icon = ns.UF_STOCK_COMBAT[styleKey]
    if icon and p.player and p.stockCombatSeededStyle ~= styleKey then
        p.stockCombatSeededStyle = styleKey
        p.player.combatIndicatorStyle = icon
        p.player.combatIndicatorPosition = "portrait"
    end
end
function ns.UF_AtlasOK(name)
    if not name then return false end
    local memo = ns._ufAtlasMemo
    local v = memo[name]
    if v == nil then
        v = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
        memo[name] = v
    end
    return v
end
-- Art entries: an atlas name or a file descriptor (see the header). A file
-- is probed once through the client's path table (memo on the descriptor),
-- so a file this client does not ship leaves its piece on the fallback art
-- instead of painting blank.
function ns.UF_ArtOK(a)
    if type(a) == "table" then
        if not a.file then return false end
        local ok = a._ok
        if ok == nil then
            ok = true
            if GetFileIDFromPath then ok = GetFileIDFromPath(a.file) and true or false end
            a._ok = ok
        end
        return ok
    end
    return ns.UF_AtlasOK(a)
end
function ns.UF_ArtName(a)
    if type(a) == "table" then return a.key or a.file or "" end
    return a or ""
end
-- Kit atlas paints in place of tex:SetAtlas / C_Texture.GetAtlasInfo: the
-- stock looks draw the retail art on the Forever client (the shared stock
-- atlas helper), the WoW Forever look keeps the client's own frame art (the
-- cast bar background skips this: a bar texture, retail under the WoW
-- Forever look too).
-- Plain textures only (never a mask or a StatusBar fill).
function ns.UF_StockAtlas(tex, name, ...)
    if ns.UF_Forever() then return tex:SetAtlas(name, ...) end
    return EllesmereUI.StockAtlas(tex, name, ...)
end
function ns.UF_StockAtlasInfo(name)
    if ns.UF_Forever() then return C_Texture.GetAtlasInfo(name) end
    return EllesmereUI.StockAtlasInfo(name)
end
-- Paints an art entry on a texture; useSize takes the entry's own size.
function ns.UF_SetArt(tex, a, useSize)
    if type(a) == "table" then
        if not ns.UF_ArtOK(a) then return false end
        tex:SetTexture(a.file)
        tex:SetTexCoord(a.l or 0, a.r or 1, a.t or 0, a.b or 1)
        if useSize and a.w and a.h then tex:SetSize(a.w, a.h) end
        return true
    end
    if not ns.UF_AtlasOK(a) then return false end
    ns.UF_StockAtlas(tex, a, useSize)
    return true
end
-- The classic cast frame round a horizontal cast bar `bar`: the shared
-- nine-slice (EllesmereUI.ClassicFrame) whose pieces ride `tex`'s parent on
-- its layer, created once; `tex` is the callers' handle and draws nothing.
-- `pct` is the unit's Border Size percentage (nil = the shared default).
-- Idempotent (the seat memoizes on the rect and scale).
function ns.UF_SeatClassicCastFrame(tex, bar, h, pct)
    local CK = ns.UF_BLIZZ.cast
    local CF = EllesmereUI.ClassicFrame
    if not (tex and bar and CK and CF) then return end
    if not ns.UF_ArtOK(CK.frame) then tex:Hide(); return end
    local p = tex._classicPieces
    if not p then
        local layer, sub = tex:GetDrawLayer()
        p = CF.Create(tex:GetParent(), layer, sub)
        tex._classicPieces = p
        tex:Hide()
    end
    CF.Seat(p, bar, CF.ScaleK(pct), false)
end
-- First existing atlas of a candidate list (nil when none is available).
function ns.UF_BlizzAtlas(list)
    for i = 1, #list do
        if ns.UF_AtlasOK(list[i]) then return list[i] end
    end
    return nil
end
-- Frame kind: the player art, the target/focus/boss art, the pet art where
-- the kit has one, or the small target-of-target / focus-target art.
function ns.UF_BlizzKind(unit)
    if not unit then return nil end
    if unit == "player" then return "player" end
    if unit == "target" or unit == "focus" or unit:match("^boss%d$") then return "target" end
    if unit == "pet" and ns.UF_BLIZZ.pet then return "pet" end
    return "mini"
end
-- Portrait Side keeps working. Each art is drawn for one side (G.side). A
-- full frame set to the other side takes the stock layout drawn for that
-- side instead (player art for a left portrait, target art for a right one),
-- so its art, bars, masks and portrait are all native pieces. The small
-- frames have a single art, so the other side renders it mirrored: anchors
-- flip left/right with x negated and the art flips; their bar masks cannot
-- flip (MaskTextures ignore texcoords), so mirrored small bars run unmasked.
-- Resolved by the layout pass and stamped on the frame for the art helpers.
function ns.UF_BlizzResolve(frame, unit)
    unit = unit or frame._euiBaseUnit or frame._euiUnit
    local kind = ns.UF_BlizzKind(unit)
    if not kind then return nil end
    local native = ns.UF_BLIZZ[kind]
    local side = ns.UF_BlizzSide(GetSettingsForUnit(unit), native)
    local G, mirror = native, false
    if native.small then
        mirror = side ~= native.side
    elseif side == "right" then
        G = ns.UF_BLIZZ.target
    else
        G = ns.UF_BLIZZ.player
    end
    frame._blizzGeom = G
    frame._blizzMirror = mirror or nil
    -- The type strip, elite dragon and rare frame belong to the target family
    -- on its own art only.
    frame._blizzExtras = (G.rep and kind == "target") or nil
    return G, mirror
end
function ns.UF_BlizzGeom(frame)
    if not frame then return nil end
    return frame._blizzGeom or ns.UF_BlizzResolve(frame)
end
-- Visible art edges under the style: the frame is the stock box, whose art is
-- centred inside it with transparent padding round the visible frame (about
-- 20px each side and 16px above/below on the full frames). Returns the insets
-- from the box edges to the visible art -- left, right, top, bottom, in the
-- frame's units -- or nil while the style is off. A mirrored small frame
-- swaps left and right with its art.
function ns.UF_BlizzVis(frame)
    if not frame or not ns.UF_Blizz() then return nil end
    local G = ns.UF_BlizzGeom(frame)
    local v = G and G.vis
    if not v then return nil end
    if frame._blizzMirror then return v.r, v.l, v.t, v.b end
    return v.l, v.r, v.t, v.b
end
-- The aura block: an invisible frame spanning the stock box's width from the
-- visible art's bottom edge down to the bottom of the frame's lowest
-- bottom-anchored aura stack (the aura containers re-point it through
-- ns.UF_BlizzAuraBlockBottom; see AnchorContainer in
-- EUI_UnitFrames_AuraContainers). A cast bar linked under the frame anchors
-- to it (the follow provider below), so it hangs below the auras the way the
-- stock spell bar does and rides the rows engine-side: an engine aura
-- container's geometry is a secret value under aura restriction, so the
-- stack's extent can only ever be followed by anchoring, never read. The
-- block is the box's width so its centre is the frame's centre, which the
-- anchor math works from. Created once per frame, only under the style.
-- An engine aura container refuses any dependent that would silently inherit
-- its layout aspect ("Anchoring disallowed as dependent object would inherit
-- forbidden aspects: UntrustedLayoutScriptExecution"): a frame may anchor to
-- it only when it already carries that aspect, which Blizzard's opt-in
-- template stamps at creation (Blizzard_SharedXMLBase/ForbiddenAspectTemplates
-- .xml; the stock target spell bar takes the same aspect before anchoring to
-- its aura container). The aspect only stops the frame's own OnSizeChanged
-- scripts, which nothing on the block or the cast bar uses. Verified once on
-- a probe: a client without the template (or one that ignores it) keeps the
-- block on the resting bottom and never anchors to a container.
ns.UF_LAYOUT_ASPECT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
function ns.UF_LayoutAspectOK()
    local v = ns._ufLayoutAspectOK
    if v == nil then
        v = false
        local ok, probe = pcall(CreateFrame, "Frame", nil, UIParent, ns.UF_LAYOUT_ASPECT_TEMPLATE)
        if ok and probe then
            local want = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.UntrustedLayoutScriptExecution
            local mask = probe.GetForbiddenAspects and probe:GetForbiddenAspects()
            if want and type(mask) == "number" and bit.band(mask, want) ~= 0 then v = true end
            probe:Hide()
        end
        ns._ufLayoutAspectOK = v
    end
    return v
end
-- The template a unit's cast bar holder is created with under the style, so
-- it can hang off the aura block (nil = a plain frame: off-style, boss frames,
-- or a client without the aspect).
function ns.UF_CastbarAspectTemplate(unit)
    if ns.UF_Blizz() and CastbarUnlockKey(unit) and ns.UF_LayoutAspectOK() then
        return ns.UF_LAYOUT_ASPECT_TEMPLATE
    end
    return nil
end
function ns.UF_BlizzAuraBlock(frame)
    local blk = frame and frame._blizzAuraBlock
    if blk then return blk end
    if not ns.UF_BlizzVis(frame) then return nil end
    if ns.UF_LayoutAspectOK() then
        blk = CreateFrame("Frame", nil, frame, ns.UF_LAYOUT_ASPECT_TEMPLATE)
    else
        blk = CreateFrame("Frame", nil, frame)
    end
    blk:EnableMouse(false)
    frame._blizzAuraBlock = blk
    ns.UF_BlizzAuraBlockBottom(frame, nil)
    return blk
end
-- Re-point the block's bottom edge: `rel` nil = the visible art's bottom
-- (nothing stacked below); else the container's BOTTOMLEFT/BOTTOMRIGHT corner
-- (`relPoint`), x shifted by `x` so the corner lands on the box's own edge --
-- the top corners already pin left and right, and a bottom corner that
-- agrees with them keeps the rect from being over-constrained.
function ns.UF_BlizzAuraBlockBottom(frame, rel, relPoint, x)
    local blk = frame and frame._blizzAuraBlock
    if not blk then return end
    local _, _, _, b = ns.UF_BlizzVis(frame)
    b = b or 0
    blk:ClearAllPoints()
    blk:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, b)
    blk:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, b)
    -- A refused container anchor (the probe passed but this container still
    -- denies it) must not abort the aura pass: fall back to the resting bottom.
    if rel and ns.UF_LayoutAspectOK()
       and pcall(blk.SetPoint, blk, relPoint, rel, relPoint, x or 0, 0) then
        return
    end
    blk:SetPoint("BOTTOM", frame, "BOTTOM", 0, b)
end
-- Anchor-target edges for the unlock anchor system under the style: the
-- visible art's edges rather than the stock box. Static insets only -- the
-- aura stack below is never read (see the block). Chained in front of any
-- provider installed before this file loaded (ns fields, like the rest of
-- this file).
ns._ufPrevAnchorExtent = EllesmereUI._GetAnchorTargetExtent
ns._ufAnchorKeys = { player = true, target = true, focus = true, pet = true, targettarget = true, focustarget = true, boss = true }
EllesmereUI._GetAnchorTargetExtent = function(targetKey, side)
    if ns._ufAnchorKeys[targetKey] and ns.UF_Blizz() then
        local f = (targetKey == "boss") and frames.boss1 or frames[targetKey]
        local l, r, t, b = ns.UF_BlizzVis(f)
        if l and f:GetLeft() then
            local ratio = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if side == "LEFT" then return (f:GetLeft() + l) * ratio
            elseif side == "RIGHT" then return (f:GetRight() - r) * ratio
            elseif side == "TOP" then return (f:GetTop() - t) * ratio
            elseif side == "BOTTOM" then return (f:GetBottom() + b) * ratio
            end
        end
    end
    local prev = ns._ufPrevAnchorExtent
    if prev then return prev(targetKey, side) end
    return nil
end
-- Follow provider for the unlock anchor system: a unit's own cast bar linked
-- to the BOTTOM of its frame anchors to the frame's aura block instead of an
-- absolute position (its offsets stay edge-to-edge from the visible art's
-- bottom, the block's resting edge), so it rides the aura stack engine-side.
ns._ufPrevAnchorFollow = EllesmereUI._GetAnchorFollowFrame
EllesmereUI._GetAnchorFollowFrame = function(childKey, targetKey, side)
    -- Inert in unlock mode: a bar on the block reports a SECRET rect (the
    -- container's geometry is secret-wrapped), which the movers must read, so
    -- the bar sits at its resting spot there and re-attaches on the exit
    -- re-apply (the same posture as the tracking bar extent provider).
    if side == "BOTTOM" and ns.UF_Blizz() and not EllesmereUI._unlockActive
       and childKey == CastbarUnlockKey(targetKey) then
        -- Only a holder created with the layout aspect may hang off the block.
        local f = frames[targetKey]
        local holder = f and f.Castbar and f.Castbar:GetParent()
        if holder and holder._blizzAspect then return ns.UF_BlizzAuraBlock(f) end
    end
    local prev = ns._ufPrevAnchorFollow
    if prev then return prev(childKey, targetKey, side) end
    return nil
end

-- Saved positions are UIParent offsets, but a frame reads anchor offsets in
-- its own scale: a frame scaled by Frame Scale (Blizzard Style, where the
-- stock size is fixed) divides them back down so it lands where it was
-- saved. Identity at scale 1, which is every frame outside the style.
function ns.UF_ScaledOffsets(fr, x, y)
    local s = fr and fr:GetScale() or 1
    if s ~= 1 and s > 0 and x and y then return x / s, y / s end
    return x, y
end

-- Boss frames' Vertical Spacing: the top-to-top step between boss 2..5 and
-- the one before. Stack Direction alone sets the sign, so a negative value
-- saved while the slider allowed one stacks the same way as its positive.
function ns.UF_BossSpacing()
    return math.abs(db.profile.bossSpacing or 80)
end

ns._ufMirrorPoint = {
    TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", LEFT = "RIGHT", RIGHT = "LEFT",
    BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
}
function ns.UF_BlizzPoint(region, point, rel, relPoint, x, y, mirror)
    if mirror then
        point = ns._ufMirrorPoint[point] or point
        relPoint = ns._ufMirrorPoint[relPoint] or relPoint
        x = -x
    end
    region:SetPoint(point, rel, relPoint, x, y)
end
-- Flipped art is drawn straight from the atlas's sheet with the sheet coords
-- reversed (SetTexCoord on an atlas-mode texture does not address the sheet,
-- so SetAtlas + SetTexCoord samples the wrong region); see UF_PaintBlizzArt.
-- The side the portrait renders on: the frame's Portrait Side setting (the
-- inside variants map to their side), else the art's own side.
function ns.UF_BlizzSide(settings, G)
    local side = settings and settings.portraitSide
    if side == "insideleft" then side = "left" elseif side == "insideright" then side = "right" end
    if side ~= "left" and side ~= "right" then side = G.side end
    return side
end

-- Re-seat a mask on a fill (AddMaskTexture is additive, so drop first).
function ns.UF_SetMask(tex, mask)
    if not tex or not mask then return end
    pcall(tex.RemoveMaskTexture, tex, mask)
    tex:AddMaskTexture(mask)
end
-- Health + power bars: the user's own Bar Texture stays on the fills (the
-- stock fill art is pre-coloured and would darken every chosen colour), so
-- colours, gradients, opacity and textures render exactly as on the EUI
-- look; the stock rounded masks shape the fills AND the EUI bar backgrounds,
-- so Bar Background keeps working inside the stock track. Masks are
-- (re)seated after every texture swap (a swap replaces the fill object), so
-- a re-apply can never leave a bar unmasked.
function ns.UF_ApplyBlizzBarArt(frame)
    local G = ns.UF_BlizzGeom(frame)
    if not G then return end
    local mirror = frame._blizzMirror
    local health = frame.Health
    if health then
        local fill = health:GetStatusBarTexture()
        health:SetOrientation("HORIZONTAL")
        ns.ApplyFillRotation(health)
        -- The mask object exists only for a kit with bar masks (the classic
        -- kit's bars are plain rectangles).
        local mask = health._blizzMask
        if not mask and ns.UF_AtlasOK(G.health.mask) then
            mask = health:CreateMaskTexture()
            health._blizzMask = mask
        end
        local hp = frame.HealthPrediction and frame.HealthPrediction.damageAbsorb
        -- Reused scratch list (a layout pass allocates nothing).
        local bars = ns._ufBarScratch
        if not bars then bars = {}; ns._ufBarScratch = bars end
        bars[1], bars[2], bars[3], bars[4], bars[5] = hp, hp and hp._forward, hp and hp._healAbsorb, hp and hp._topBar, hp and hp._healTopBar
        if not mirror and ns.UF_AtlasOK(G.health.mask) then
            mask:SetAtlas(G.health.mask, true)
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", health, "TOPLEFT", G.health.mx, G.health.my)
            ns.UF_SetMask(fill, mask)
            if health.bg then ns.UF_SetMask(health.bg, mask) end
            ns.UF_BlizzBarShadow(health, mask, G.health.h)
            -- Absorb fills ride the same rounded ends.
            for i = 1, 5 do
                local sb = bars[i]
                if sb and sb.GetStatusBarTexture then ns.UF_SetMask(sb:GetStatusBarTexture(), mask) end
            end
            if hp then hp._blizzMaskOn = true end
        else
            -- Mirrored small frame (or no mask art): plain fills.
            if mask then
                if fill then pcall(fill.RemoveMaskTexture, fill, mask) end
                if health.bg then pcall(health.bg.RemoveMaskTexture, health.bg, mask) end
                for i = 1, #bars do
                    local sb = bars[i]
                    local t = sb and sb.GetStatusBarTexture and sb:GetStatusBarTexture()
                    if t then pcall(t.RemoveMaskTexture, t, mask) end
                end
            end
            if hp then hp._blizzMaskOn = nil end
            ns.UF_BlizzBarShadow(health, nil, G.health.h)
        end
        -- Heal prediction segments take the shape too (Overheal 0 only).
        if hp and hp._predMy then ns.UF_HealPredMasks(hp) end
    end
    local power = frame.Power
    if power then
        local pfill = power:GetStatusBarTexture()
        -- Stock rounded mask on the attached bar (stamped by the layout pass);
        -- a mirrored small frame runs unmasked.
        if pfill then
            local pm = power._blizzMask
            if power._blizzMasked and not mirror and ns.UF_AtlasOK(G.power.mask) then
                if not pm then
                    pm = power:CreateMaskTexture()
                    power._blizzMask = pm
                end
                pm:SetAtlas(G.power.mask, true)
                pm:ClearAllPoints()
                pm:SetPoint("TOPLEFT", power, "TOPLEFT", G.power.mx, G.power.my)
                ns.UF_SetMask(pfill, pm)
                if power.bg then ns.UF_SetMask(power.bg, pm) end
                ns.UF_BlizzBarShadow(power, pm, G.power.h)
            else
                if pm then
                    pcall(pfill.RemoveMaskTexture, pfill, pm)
                    if power.bg then pcall(power.bg.RemoveMaskTexture, power.bg, pm) end
                end
                if power._blizzMasked then
                    -- Mirrored small frame: in the track, unmasked.
                    ns.UF_BlizzBarShadow(power, nil, G.power.h)
                elseif power._blizzShadow then
                    -- Detached bar: it carries its own EUI border.
                    for i = 1, 4 do power._blizzShadow[i]:Hide() end
                end
            end
        end
    end
end

-- Paints the frame art (one texture on the art frame, centred) from the
-- atlas sheet; a mirrored small frame samples the sheet flipped. The extras
-- (type strip, dragon) draw above it on higher sublevels.
function ns.UF_PaintBlizzArt(frame, atlas)
    local af = frame._blizzArtFrame
    local art = af._art
    if not art then
        art = af:CreateTexture(nil, "BACKGROUND")
        UnsnapTex(art)
        af._art = art
    end
    local file, l, r, t, b, w, h, point, x, y
    if type(atlas) == "table" then
        -- File descriptor: its own sheet coords and anchor (CENTER by default).
        if not ns.UF_ArtOK(atlas) then art:Hide(); return end
        file = atlas.file
        l, r, t, b = atlas.l or 0, atlas.r or 1, atlas.t or 0, atlas.b or 1
        w, h = atlas.w, atlas.h
        point, x, y = atlas.point or "CENTER", atlas.x or 0, atlas.y or 0
    else
        local info = ns.UF_StockAtlasInfo(atlas)
        if not info then art:Hide(); return end
        file = info.file or info.filename
        l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        w, h = info.width, info.height
        point, x, y = "CENTER", 0, 0
    end
    if not file then art:Hide(); return end
    art:SetTexture(file)
    if frame._blizzMirror then
        art:SetTexCoord(r, l, t, b)
        point = ns._ufMirrorPoint[point] or point
        x = -x
    else
        art:SetTexCoord(l, r, t, b)
    end
    art:ClearAllPoints()
    art:SetPoint(point, frame, point, x, y)
    art:SetSize(w, h)
    art:Show()
end

-- Inner shadow on a bar, above its fill and under the bar's rounded mask so
-- it follows the track's shape: the stock fill art bakes this shading in,
-- and our fills are the user's own textures, so it is drawn here. Black
-- fading in from the top (deepest), the bottom and both ends. Regions of
-- the bar itself (no frame-level games); created once, resized per pass.
ns._ufShadeClear  = CreateColor(0, 0, 0, 0)
ns._ufShadeTop    = CreateColor(0, 0, 0, 0.55)
ns._ufShadeBottom = CreateColor(0, 0, 0, 0.30)
ns._ufShadeEnd    = CreateColor(0, 0, 0, 0.35)
function ns.UF_BlizzBarShadow(bar, mask, h)
    local sh = bar._blizzShadow
    -- A kit with flat bars (the classic frames) draws no bevel.
    if ns.UF_BLIZZ.noBevel then
        if sh then
            for i = 1, 4 do sh[i]:Hide() end
        end
        return
    end
    if not sh then
        sh = {}
        bar._blizzShadow = sh
        for i = 1, 4 do
            local tex = bar:CreateTexture(nil, "OVERLAY", nil, -3)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            UnsnapTex(tex)
            sh[i] = tex
        end
        -- VERTICAL runs bottom -> top, HORIZONTAL left -> right.
        sh[1]:SetGradient("VERTICAL", ns._ufShadeClear, ns._ufShadeTop)
        sh[2]:SetGradient("VERTICAL", ns._ufShadeBottom, ns._ufShadeClear)
        sh[3]:SetGradient("HORIZONTAL", ns._ufShadeEnd, ns._ufShadeClear)
        sh[4]:SetGradient("HORIZONTAL", ns._ufShadeClear, ns._ufShadeEnd)
    end
    -- nil = unmasked strips (mirrored small frames): an earlier mask comes off.
    if sh._mask ~= mask then
        for i = 1, 4 do
            if sh._mask then pcall(sh[i].RemoveMaskTexture, sh[i], sh._mask) end
            if mask then sh[i]:AddMaskTexture(mask) end
        end
        sh._mask = mask
    end
    local top, bottom, ends = math.max(2, math.floor(h * 0.2)), math.max(1, math.floor(h * 0.1)), math.max(2, math.floor(h * 0.15))
    sh[1]:ClearAllPoints(); sh[1]:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); sh[1]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0); sh[1]:SetHeight(top)
    sh[2]:ClearAllPoints(); sh[2]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); sh[2]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); sh[2]:SetHeight(bottom)
    sh[3]:ClearAllPoints(); sh[3]:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); sh[3]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); sh[3]:SetWidth(ends)
    sh[4]:ClearAllPoints(); sh[4]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0); sh[4]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); sh[4]:SetWidth(ends)
    for i = 1, 4 do sh[i]:Show() end
end

-- Frame art (plus the reputation strip and boss/elite dragon on the target
-- family) on a child frame under the bars and over the portrait, as the
-- stock frame layers it: the art's ring overlaps the portrait, the bars
-- draw over the art's tracks.
function ns.UF_ApplyBlizzFrameArt(frame, G)
    local mirror = frame._blizzMirror
    local af = frame._blizzArtFrame
    if not af then
        af = CreateFrame("Frame", nil, frame)
        af:SetAllPoints(frame)
        af:EnableMouse(false)
        frame._blizzArtFrame = af
    end
    -- Target-family extras (type strip, dragon), created the first time a
    -- frame renders on the target art; a side change can turn them off again.
    if frame._blizzExtras and not af._rep then
        local rep = af:CreateTexture(nil, "BACKGROUND", nil, 1)
        UnsnapTex(rep)
        af._rep = rep
        local dragon = af:CreateTexture(nil, "BACKGROUND", nil, 2)
        UnsnapTex(dragon)
        dragon:Hide()
        af._dragon = dragon
        -- One shared event frame refreshes every target-family frame's
        -- art; created with the first such frame, so it never exists
        -- while the style is off.
        if not ns._ufBlizzArtEvents then
            ns._ufBlizzArtFrames = {}
            local ev = CreateFrame("Frame")
            ev:RegisterEvent("PLAYER_TARGET_CHANGED")
            ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
            ev:RegisterEvent("PLAYER_ENTERING_WORLD")
            ev:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            ev:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "focus")
            ev:RegisterUnitEvent("UNIT_FACTION", "target", "focus")
            ev:SetScript("OnEvent", function()
                local list = ns._ufBlizzArtFrames
                for i = 1, #list do ns.UF_RefreshBlizzTargetArt(list[i]) end
            end)
            ns._ufBlizzArtEvents = ev
        end
        table.insert(ns._ufBlizzArtFrames, frame)
    end
    -- Draw order: art UNDER the bars, over the portrait. The bars live in a
    -- clipping container that renders as one group at the container's level
    -- (a frame AT that level ties with the group, and the tie fell either
    -- way in-game), so the art sits one level below the container; strata
    -- follows the container so a custom Strata setting cannot separate them.
    local clip = frame._barClip
    local base = (clip and clip:GetFrameLevel()) or frame:GetFrameLevel()
    af:SetFrameStrata((clip and clip:GetFrameStrata()) or frame:GetFrameStrata())
    -- A kit whose art is opaque round transparent bar windows (the classic
    -- target and pet frames) draws it OVER the bars instead: above the
    -- clipped group, still under the text overlays.
    if G.artAbove then
        af:SetFrameLevel(base + 2)
    else
        af:SetFrameLevel(math.max(0, base - 1))
    end
    af._artSig = mirror and "|m" or ""
    -- The target family resolves its art (classification variants) in the
    -- refresh below: one paint per change, never the base art first.
    if not af._rep then
        local key = ns.UF_ArtName(G.art) .. af._artSig
        if af._artKey ~= key then
            af._artKey = key
            ns.UF_PaintBlizzArt(frame, G.art)
        end
    end
    -- The dark plaque behind the name and bars (classic kit): its own frame
    -- under the bars whatever level the art takes.
    if G.back then
        local bf = af._backFrame
        if not bf then
            bf = CreateFrame("Frame", nil, frame)
            bf:SetAllPoints(frame)
            bf:EnableMouse(false)
            local bk = bf:CreateTexture(nil, "BACKGROUND")
            bk:SetColorTexture(0, 0, 0, 0.5)
            UnsnapTex(bk)
            bf._tex = bk
            af._backFrame = bf
        end
        bf:SetFrameStrata(af:GetFrameStrata())
        -- Under the art whether the art sits under the bars (base - 1) or
        -- over them; beside the portrait backdrop's level, never overlapping it.
        bf:SetFrameLevel(math.max(0, base - 2))
        bf._tex:ClearAllPoints()
        ns.UF_BlizzPoint(bf._tex, "TOPLEFT", frame, "TOPLEFT", G.back.x, -G.back.y, mirror)
        bf._tex:SetSize(G.back.w, G.back.h)
        bf:Show()
    elseif af._backFrame then
        af._backFrame:Hide()
    end
    if af._rep then
        local rep = G.rep
        local repArt = rep and (rep.art or rep.atlas)
        if frame._blizzExtras and ns.UF_ArtOK(repArt)
            and ns.UF_BlizzHeaderOn(GetSettingsForUnit(frame._euiBaseUnit or frame._euiUnit)) then
            ns.UF_SetArt(af._rep, repArt, true)
            -- Over the art (the stock type strip) or under it (the classic
            -- name plaque, seen through the art's name window).
            af._rep:SetDrawLayer("BACKGROUND", rep.below and -1 or 1)
            af._rep:ClearAllPoints()
            local rp = rep.point or "TOPRIGHT"
            af._rep:SetPoint(rp, frame, rp, rep.x, rep.y)
            af._rep:Show()
        else
            af._rep:Hide()
        end
        ns.UF_RefreshBlizzTargetArt(frame)
    end
end

-- Target-family art that follows the unit: rare frame variant, elite/rare/
-- boss dragon, reputation strip tint. Every unit read is secrecy-guarded.
function ns.UF_RefreshBlizzTargetArt(frame)
    local af = frame and frame._blizzArtFrame
    if not af or not af._rep then return end
    local G = frame._blizzGeom
    if not G then return end
    local unit = frame._euiUnit
    local extras = frame._blizzExtras and G.rep and unit and UnitExists(unit)
    local c
    if extras then
        local r, g, b = UnitSelectionColor(unit)
        if r and not issecretvalue(r) and not issecretvalue(g) and not issecretvalue(b) then
            af._rep:SetVertexColor(r, g, b)
        else
            af._rep:SetVertexColor(0.5, 0.5, 0.5)
        end
        c = UnitClassification(unit)
        if issecretvalue(c) then c = nil end
    end
    local boss = extras and UnitIsBossMob and UnitIsBossMob(unit)
    if issecretvalue(boss) then boss = false end
    -- The one art paint for this family (see UF_ApplyBlizzFrameArt): the
    -- classification variant -- the stock kit's rare frame, or the classic
    -- kit's whole-frame elite / rare / rare-elite / boss arts (boss frames
    -- always wear the boss art) -- else the base art, memo on the result.
    local artName = G.art
    local byc = G.artByClass
    if byc then
        -- A variant this client does not ship falls back a step (boss art to
        -- the elite frame, then the base art).
        if unit and unit:match("^boss%d$") and ns.UF_ArtOK(byc.boss) then
            artName = byc.boss
        elseif (boss or (unit and unit:match("^boss%d$"))) and ns.UF_ArtOK(byc.elite) then
            artName = byc.elite
        elseif extras and c and ns.UF_ArtOK(byc[c]) then
            artName = byc[c]
        end
    elseif (c == "rare" or c == "rareelite") and ns.UF_ArtOK(G.artRare) then
        artName = G.artRare
    end
    local artKey = ns.UF_ArtName(artName) .. (af._artSig or "")
    if af._artKey ~= artKey then
        af._artKey = artKey
        ns.UF_PaintBlizzArt(frame, artName)
    end
    -- The classic arts carry their dragon; the stock kit adds it below.
    if not extras or byc then
        af._dragon:Hide()
        return
    end
    -- Stock rule: the winged dragon for boss mobs, silver for rare elites,
    -- gold for elites, nothing else. WoW Forever puts the silver dragon on
    -- plain rares too and places each dragon its own way (the kit's `pos`).
    local B = G.boss
    local dragon, dx, pos
    if boss then
        dragon, dx, pos = B.winged, 8, B.pos and B.pos.winged
    elseif c == "rareelite" or (B.silverRare and c == "rare") then
        dragon, dx, pos = B.silver, -11, B.pos and B.pos.silver
    elseif c == "elite" then
        dragon, dx, pos = B.gold, -11, B.pos and B.pos.gold
    end
    local dy = -8
    if pos then dx, dy = pos[1], pos[2] end
    if dragon and ns.UF_AtlasOK(dragon) then
        ns.UF_StockAtlas(af._dragon, dragon, true)
        af._dragon:ClearAllPoints()
        af._dragon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", dx, dy)
        af._dragon:Show()
    else
        af._dragon:Hide()
    end
end

-- Portrait: always shown (the stock frames carry one), the stock size and
-- position with the stock mask (round, or the player frame's own crop), full
-- art, no EUI backdrop, and UNDER the frame art (the art's ring and bar edge
-- overlap it exactly as on the stock frame).
function ns.UF_ApplyBlizzPortrait(frame, G)
    local pt = frame.Portrait
    local bd = pt and pt.backdrop
    if not bd then return end
    local mirror = frame._blizzMirror
    bd:ClearAllPoints()
    ns.UF_BlizzPoint(bd, G.portrait.point, frame, G.portrait.point, G.portrait.x, G.portrait.y, mirror)
    bd:SetSize(G.portrait.size, G.portrait.size)
    -- Under the art (which sits one level below the bar clip container; see
    -- UF_ApplyBlizzFrameArt), in the same strata.
    local clip = frame._barClip
    bd:SetFrameStrata((clip and clip:GetFrameStrata()) or frame:GetFrameStrata())
    bd:SetFrameLevel(math.max(0, ((clip and clip:GetFrameLevel()) or frame:GetFrameLevel()) - 2))
    bd:SetClipsChildren(false)
    if bd._bg then bd._bg:SetAlpha(0) end
    if bd._2d then bd._2d:SetTexCoord(0, 1, 0, 1) end
    local m = bd._blizzMask
    if not m and ns.UF_AtlasOK(G.portrait.mask) then
        m = bd:CreateMaskTexture()
        m:SetAllPoints(bd)
        if bd._2d then bd._2d:AddMaskTexture(m) end
        if bd._class then bd._class:AddMaskTexture(m) end
        bd._blizzMask = m
    end
    -- Re-set each pass: a side change swaps the player crop for the circle.
    -- (A mirrored small frame keeps its circle; masks cannot flip anyway.)
    if m and ns.UF_AtlasOK(G.portrait.mask) then m:SetAtlas(G.portrait.mask) end
    -- SetPortraitTexture crops the art to a circle by itself (the stock
    -- target/pet frames keep that crop under their CircleMask); the player
    -- frame's mask is not a circle, so there the crop is switched off and the
    -- atlas mask is the only shape. The engine's portrait paint reads the
    -- stamp; a change repaints the current art.
    local repaint
    if bd._2d then
        local raw = (m and G.portrait.rawArt) or nil
        if bd._2d._blizzNoMask ~= raw then
            bd._2d._blizzNoMask = raw
            repaint = true
        end
    end
    -- Forced on: a profile with the portrait hidden or set to None still shows it.
    bd:Show()
    if frame.IsElementEnabled and not frame:IsElementEnabled("Portrait") then
        frame:EnableElement("Portrait")
        repaint = true
    end
    if repaint and pt.ForceUpdate then pt:ForceUpdate() end
end

-- Text zones: the left zone (the name by default) moves onto the stock name
-- strip; the other zones keep their bar-relative placement.
function ns.UF_BlizzTextPass(frame)
    local G = ns.UF_BlizzGeom(frame)
    local lt = frame and frame.LeftText
    if not (G and lt and G.name) then return end
    -- The Left Text offsets still apply on top of the stock spot, in screen
    -- terms (+X right, +Y up) on the mirrored art too, so they are added
    -- after the mirror rather than through it.
    local s = GetSettingsForUnit(frame._euiBaseUnit or frame._euiUnit)
    local lxo, lyo = (s and s.leftTextX) or 0, (s and s.leftTextY) or 0
    lt:ClearAllPoints()
    lt:SetJustifyH(G.name.justify or "LEFT")
    local point, x = G.name.point, G.name.x
    if frame._blizzMirror then
        point = ns._ufMirrorPoint[point] or point
        x = -x
    end
    lt:SetPoint(point, frame, point, x + lxo, G.name.y + lyo)
    lt:SetWidth(G.name.w)
end

-- Level number in the frame's level circle, as the stock frames draw it:
-- the stock number font at the stock spot (the right end of the player
-- art's name bar, the left end of the target art's type strip), gold, green
-- while the player is level-scaled, the creature difficulty colour on an
-- attackable target, and the stock skull for a level the client will not
-- tell. One FontString per full frame on its own host above the bars,
-- refreshed by a shared event frame created with the first frame (nothing
-- exists while the style is off). Per-unit "Show Level" (blizzShowLevel,
-- default on) hides it; per-unit "Difficulty Color" (blizzLevelDifficultyColor,
-- default on) off keeps an attackable unit's level gold too.
ns.UF_BLIZZ_SKULL = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon"
function ns.UF_BlizzLevelPass(frame)
    local G = ns.UF_BlizzGeom(frame)
    local L = G and G.level
    if not L then return end
    local clip = frame._barClip
    local host = frame._blizzLevelHost
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        host:EnableMouse(false)
        frame._blizzLevelHost = host
        local fs = host:CreateFontString(nil, "OVERLAY")
        -- The stock number font as the baseline: the name's font is copied
        -- below once the name text carries one (not yet at first spawn).
        fs:SetFontObject(GameNormalNumberFont)
        frame._blizzLevel = fs
        local skull = host:CreateTexture(nil, "OVERLAY", nil, 1)
        skull:Hide()
        frame._blizzLevelSkull = skull
        if not ns._ufBlizzLevelEvents then
            ns._ufBlizzLevelFrames = {}
            local ev = CreateFrame("Frame")
            ev:RegisterEvent("PLAYER_TARGET_CHANGED")
            ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
            ev:RegisterEvent("PLAYER_ENTERING_WORLD")
            ev:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            ev:RegisterEvent("PLAYER_LEVEL_UP")
            ev:RegisterEvent("UNIT_LEVEL")
            ev:RegisterEvent("UNIT_FACTION")
            ev:SetScript("OnEvent", function(_, event, unit)
                -- Unit events refresh their frame; everything else refreshes all.
                local list = ns._ufBlizzLevelFrames
                local byUnit = type(unit) == "string"
                for i = 1, #list do
                    local f = list[i]
                    if not byUnit or f._euiUnit == unit then ns.UF_BlizzLevelRefresh(f, event) end
                end
            end)
            ns._ufBlizzLevelEvents = ev
        end
        table.insert(ns._ufBlizzLevelFrames, frame)
    end
    -- Re-seated every pass: the host follows the bar clip's strata and sits
    -- above the bars, like the art frame does below them.
    host:SetFrameStrata((clip and clip:GetFrameStrata()) or frame:GetFrameStrata())
    host:SetFrameLevel(((clip and clip:GetFrameLevel()) or frame:GetFrameLevel()) + 12)
    local fs, skull = frame._blizzLevel, frame._blizzLevelSkull
    local s = GetSettingsForUnit(frame._euiBaseUnit or frame._euiUnit)
    -- Same face, outline and shadow as the unit name (and its size, unless
    -- the level has its own): the name's font object first (it carries the
    -- shadow), then its face. The colour keeps the stock rules (set as an
    -- instance text colour, never vertex-only).
    local lt = frame.LeftText
    if lt then
        local face, size, flags = lt:GetFont()
        if face then
            local fo = lt:GetFontObject()
            if fo then fs:SetFontObject(fo) end
            fs:SetFont(face, (s and s.blizzLevelSize) or size, flags)
        end
    end
    -- The stock spot, plus the level's own offsets.
    local ox, oy = (s and s.blizzLevelX) or 0, (s and s.blizzLevelY) or 0
    -- WoW Forever: the level sits in a round badge at the frame's bottom
    -- corner, which the level's own offsets move as a whole; the number and
    -- the skull centre on it (a fixed size, so a missing atlas keeps the spot).
    local rel, B = frame, G.badge
    if B then
        local badge = frame._blizzLevelBadge
        if not badge then
            badge = host:CreateTexture(nil, "OVERLAY", nil, -1)
            UnsnapTex(badge)
            ns.UF_SetArt(badge, B.atlas)
            frame._blizzLevelBadge = badge
        end
        badge:SetSize(B.size, B.size)
        badge:ClearAllPoints()
        ns.UF_BlizzPoint(badge, B.point, frame, B.point, B.x + ox, B.y + oy, frame._blizzMirror)
        rel, ox, oy = badge, 0, 0
    end
    fs:ClearAllPoints()
    fs:SetJustifyH(L.justify or "CENTER")
    ns.UF_BlizzPoint(fs, L.point, rel, L.relPoint or L.point, L.x + ox, L.y + oy, frame._blizzMirror)
    -- The skull takes the number's spot (its own anchor, so a hidden number
    -- never moves it).
    skull:ClearAllPoints()
    ns.UF_BlizzPoint(skull, L.point, rel, L.relPoint or L.point, L.x + ox, L.y + (L.skullDy or 2) + oy, frame._blizzMirror)
    ns.UF_SetArt(skull, ns.UF_BLIZZ.skull or ns.UF_BLIZZ_SKULL, true)
    -- WoW Forever: the round PvP badge on the player, target and focus
    -- frames (Blizzard's own display rule paints and shows it, below).
    local PV = G.pvp
    local u = frame._euiUnit
    if PV and (u == "player" or u == "target" or u == "focus") then
        local els = frame._blizzPvP
        if not els then
            els = { pvpBackground = host:CreateTexture(nil, "OVERLAY", nil, 2),
                    pvpIcon = host:CreateTexture(nil, "OVERLAY", nil, 3) }
            UnsnapTex(els.pvpBackground)
            UnsnapTex(els.pvpIcon)
            -- Blizzard's own scale and offsets, so the badge lands where the
            -- stock frame puts it whatever the scale does to the offsets.
            els.pvpBackground:SetScale(PV.scale)
            els.pvpIcon:SetScale(PV.scale)
            ns.UF_SetArt(els.pvpBackground, PV.atlas, true)
            els.pvpIcon:SetPoint("CENTER", els.pvpBackground, "CENTER", 0, 0)
            els.pvpBackground:Hide()
            els.pvpIcon:Hide()
            frame._blizzPvP = els
        end
        els.pvpBackground:ClearAllPoints()
        ns.UF_BlizzPoint(els.pvpBackground, PV.point, frame, PV.relPoint, PV.x, PV.y, frame._blizzMirror)
    end
    -- Where the level shares the name's end of the strip, the name gives up
    -- that width while the level shows (the text pass set the full width).
    if lt and G.name and L.nameTrim then
        local on = s and s.blizzShowLevel ~= false
        lt:SetWidth(G.name.w - (on and L.nameTrim or 0))
    end
    ns.UF_BlizzLevelRefresh(frame)
end
-- `event`: the level event that asked (nil = the layout pass).
function ns.UF_BlizzLevelRefresh(frame, event)
    local fs = frame and frame._blizzLevel
    if not fs then return end
    local skull = frame._blizzLevelSkull
    -- WoW Forever's level badge (nil on every other kit).
    local badge = frame._blizzLevelBadge
    local unit = frame._euiUnit
    -- WoW Forever's PvP badge, only where its unit can have changed.
    if frame._blizzPvP then
        local only = event and ns.UF_PVP_EVENT_UNIT[event]
        if only == nil or only == unit then ns.UF_ForeverPvPRefresh(frame, unit) end
    end
    local s = unit and GetSettingsForUnit(frame._euiBaseUnit or unit)
    if not s or s.blizzShowLevel == false or not UnitExists(unit) then
        fs:Hide(); skull:Hide()
        if badge then badge:Hide() end
        return
    end
    -- Every unit read is treated as possibly secret: a secret level still
    -- paints (SetText takes it), a secret flag reads as its stock default.
    local gold, level = true, nil
    if unit == "player" then
        level = UnitEffectiveLevel(unit)
        local base = UnitLevel(unit)
        if not issecretvalue(level) and not issecretvalue(base) and level ~= base then
            fs:SetTextColor(0.1, 1, 0.1); gold = false
        end
    else
        local corpse = UnitIsCorpse(unit)
        if issecretvalue(corpse) then corpse = false end
        local pet = UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit)
        if issecretvalue(pet) then pet = false end
        if corpse then
            level = 0
        elseif pet and badge then
            -- WoW Forever shows neither the level nor its badge for a battle pet.
            fs:Hide(); skull:Hide(); badge:Hide()
            return
        elseif pet then
            level = UnitBattlePetLevel(unit)
        else
            level = UnitEffectiveLevel(unit)
            local can = s.blizzLevelDifficultyColor ~= false and UnitCanAttack("player", unit)
            if not issecretvalue(can) and can then
                local diff = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit)
                local color = not issecretvalue(diff) and GetDifficultyColor and GetDifficultyColor(diff)
                if color then fs:SetTextColor(color.r, color.g, color.b); gold = false end
            end
        end
    end
    if gold then
        -- WoW Forever paints the player's own level white.
        if badge and unit == "player" then
            fs:SetTextColor(1, 1, 1)
        else
            fs:SetTextColor(1, 0.82, 0)
        end
    end
    if badge then badge:Show() end
    -- A level the client will not tell (corpse, or 0 and below): the stock skull.
    if issecretvalue(level) or (level and level > 0) then
        fs:SetText(level)
        fs:Show(); skull:Hide()
    else
        fs:Hide(); skull:Show()
    end
end
-- WoW Forever's round PvP badge: the client's own secret-safe painter (the
-- one its unit frames call, offered to addons) sets the faction or free for
-- all crest and shows the crest and circle under Blizzard's rule, including
-- the mercenary swap on the player. Rides the level refresh's events.
-- The level events that leave the badge alone, or repaint one frame's only:
-- a target or focus swap repaints that frame alone, and a level change or
-- an encounter unit none. Every other event (the unit's own UNIT_FACTION,
-- the loading screen) and the layout pass repaint each badge they reach.
ns.UF_PVP_EVENT_UNIT = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus",
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = false, PLAYER_LEVEL_UP = false, UNIT_LEVEL = false }
function ns.UF_ForeverPvPRefresh(frame, unit)
    local els = frame._blizzPvP
    local paint = UnitFrameUtil and UnitFrameUtil.UpdateUnitPvPIndicator
    if paint and UnitExists(unit) then
        paint(els, unit, unit == "player")
    else
        els.pvpIcon:Hide()
        els.pvpBackground:Hide()
    end
end

-- Cast bar fill per cast kind ("cast" | "channel"); one field test when the
-- style is off, memoized per bar.
function ns.UF_SetBlizzCastFill(cb, kind)
    if not cb or not cb._blizzCast then return end
    kind = kind or "cast"
    if cb._blizzFillKind == kind then return end
    local atlas = ns.UF_BlizzAtlas(ns.UF_CAST_BLIZZ[kind] or ns.UF_CAST_BLIZZ.cast)
    if not atlas then return end
    cb._blizzFillKind = kind
    cb:GetStatusBarTexture():SetAtlas(atlas)
end
-- Spell name into the text box under the bar (honouring its side + offsets).
function ns.UF_BlizzCastText(cb)
    local box = cb and cb._blizzTextBox
    if not box or not box:IsShown() or not cb.Text then return end
    if cb._nameSide == "none" then return end
    -- The box spans the bar (not the holder: an in-width icon takes part of
    -- the holder), so the name's width follows the bar.
    local w = cb:GetWidth()
    -- Secret under aura restriction when the holder rides the aura block:
    -- keep the out-of-combat layout (the width is fixed in combat).
    if issecretvalue(w) then return end
    w = w or 0
    cb.Text:ClearAllPoints()
    local side = cb._nameSide or "left"
    local ox, oy = cb._nameOX or 0, cb._nameOY or 0
    if side == "right" then
        cb.Text:SetJustifyH("RIGHT")
        cb.Text:SetPoint("RIGHT", box, "RIGHT", -8 + ox, oy)
    elseif side == "center" then
        cb.Text:SetJustifyH("CENTER")
        cb.Text:SetPoint("CENTER", box, "CENTER", ox, oy)
    else
        cb.Text:SetJustifyH("LEFT")
        cb.Text:SetPoint("LEFT", box, "LEFT", 8 + ox, oy)
    end
    if w > 20 then cb.Text:SetWidth(w - 16) end
    ns.ReflowFontString(cb.Text)
end
-- Cast icon under the style: a square spanning the bar and the stock text
-- box under it (the box hangs 13px below the bar while the spell name
-- shows), hung from the holder's top corner on the configured side -- inside
-- the footprint, where the bar then starts past it, or off its edge -- with
-- the user's offsets, so its top lines up with the bar and its bottom with
-- the box. Inputs are the ones LayoutCastbarIcon stamped; the only rect read
-- is the holder's explicit height (plain on every anchor chain).
function ns.UF_BlizzCastIcon(cb)
    local ico = cb and cb._iconFrame
    local host = cb and cb:GetParent()
    if not ico or not host then return end
    -- The configured height LayoutCastbarIcon stamped (the holder's own rect
    -- reads back secret while it rides the aura block).
    local hostH = cb._icoSide or host:GetHeight()
    if issecretvalue(hostH) or not hostH or hostH <= 0 then return end
    local box = cb._blizzTextBox
    local side = hostH + ((box and box:IsShown()) and 13 or 0)
    local inWidth, onRight = cb._icoInWidth, cb._icoOnRight
    local offX, offY = cb._icoOffX or 0, cb._icoOffY or 0
    ico:ClearAllPoints()
    ico:SetSize(side, side)
    if inWidth then
        if onRight then
            PP.Point(ico, "TOPRIGHT", host, "TOPRIGHT", offX, offY)
        else
            PP.Point(ico, "TOPLEFT", host, "TOPLEFT", offX, offY)
        end
        -- The bar takes the rest of the footprint (LayoutCastbarIcon inset it
        -- by the EUI square; this icon is wider).
        cb:ClearAllPoints()
        if onRight then
            PP.Point(cb, "TOPLEFT", host, "TOPLEFT", 0, 0)
            PP.Point(cb, "BOTTOMRIGHT", host, "BOTTOMRIGHT", -side, 0)
        else
            PP.Point(cb, "TOPLEFT", host, "TOPLEFT", side, 0)
            PP.Point(cb, "BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        end
    elseif onRight then
        PP.Point(ico, "TOPLEFT", host, "TOPRIGHT", offX, offY)
    else
        PP.Point(ico, "TOPRIGHT", host, "TOPLEFT", offX, offY)
    end
end
-- Cast bar: stock background, fill art, frame and text box; the EUI tint
-- layer stays off (the fill art is its own colour). Border and icon frame go.
function ns.UF_ApplyBlizzCastbar(cb)
    if not cb then return end
    -- The stock chrome owns the frame: a Custom Border Style host stays hidden.
    if cb._cbBorder then cb._cbBorder:Hide() end
    local host = cb:GetParent()
    local CK = ns.UF_BLIZZ.cast
    if CK then
        -- Classic kit: the vanilla cast bar frame round the user's own fill
        -- and colours; no stock background, fill art or text box (the spell
        -- name stays on the bar in its EUI zone). The frame is the shared
        -- nine-slice anchored to the HOLDER's corners (bar plus icon: the
        -- icon is part of the bar under this kit and sits inside the frame's
        -- window), so no rect is read here. Its pieces ride an art child of
        -- the holder above the bar and the icon (both holder +1) and under
        -- the text overlay, so the rim overlaps the icon's edges as it does
        -- the fill's.
        cb._blizzCast = nil
        PP.HideBorder(cb)
        if not cb._blizzFrame and host then
            local af = CreateFrame("Frame", nil, host)
            af:SetAllPoints(host)
            af:EnableMouse(false)
            af:SetFrameLevel(host:GetFrameLevel() + 3)
            cb._classicArt = af
            local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
            UnsnapTex(fr)
            cb._blizzFrame = fr
        end
        if cb._blizzFrame then ns.UF_SeatClassicCastFrame(cb._blizzFrame, host, nil, cb._classicPct) end
        local ico = cb._iconFrame
        if ico then
            PP.HideBorder(ico)
            if ico._bg then ico._bg:Hide() end
            if cb.Icon then
                cb.Icon:ClearAllPoints()
                cb.Icon:SetAllPoints(ico)
            end
        end
        if cb.Icon then cb.Icon:SetTexCoord(0, 1, 0, 1) end
        ns.UF_BlizzCastIcon(cb)
        if cb._layoutTextZones then cb:_layoutTextZones() end
        return
    end
    cb._blizzCast = true
    cb._blizzFillKind = nil
    cb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fill = cb:GetStatusBarTexture()
    if fill then fill:SetHorizTile(false); UnsnapTex(fill) end
    ns.UF_SetBlizzCastFill(cb, cb.channeling and "channel" or "cast")
    cb:SetStatusBarColor(1, 1, 1, cb._fillOp or 1)
    if cb.castTintLayer then
        cb.castTintLayer:SetAlpha(0)
        cb._castTintOn = nil
    end
    if host and host._bgTex then
        -- A bar texture, not frame chrome: the retail background under
        -- Blizzard Style, WoW Forever included.
        local bgAtlas = ns.UF_BlizzAtlas(ns.UF_CAST_BLIZZ.bg)
        if bgAtlas then EllesmereUI.StockAtlas(host._bgTex, bgAtlas) end
        host._bgTex:ClearAllPoints()
        host._bgTex:SetPoint("TOPLEFT", host, "TOPLEFT", -1, 1)
        host._bgTex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 1, -1)
    end
    PP.HideBorder(cb)
    if not cb._blizzFrame then
        -- The frame art rides its own child of the bar, above the
        -- uninterruptible shield's host (bar +1) and the kick marker (bar +2),
        -- under the text overlay: as a region of the bar itself, the shield
        -- frame would draw its grey over the art.
        local af = CreateFrame("Frame", nil, cb)
        af:SetAllPoints(cb)
        af:EnableMouse(false)
        cb._blizzArtFr = af
        local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
        UnsnapTex(fr)
        cb._blizzFrame = fr
        local tb = host:CreateTexture(nil, "BACKGROUND", nil, -1)
        UnsnapTex(tb)
        cb._blizzTextBox = tb
        local orig = cb._layoutTextZones
        if orig then
            cb._layoutTextZones = function(self)
                orig(self)
                ns.UF_BlizzCastText(self)
            end
        end
    end
    -- Re-asserted every pass (a strata change rebuilds child levels).
    local artLvl = cb:GetFrameLevel() + 3
    if cb._blizzArtFr and cb._blizzArtFr:GetFrameLevel() ~= artLvl then cb._blizzArtFr:SetFrameLevel(artLvl) end
    local frAtlas = ns.UF_BlizzAtlas(ns.UF_CAST_BLIZZ.frame)
    if frAtlas then
        ns.UF_StockAtlas(cb._blizzFrame, frAtlas)
        cb._blizzFrame:ClearAllPoints()
        cb._blizzFrame:SetPoint("TOPLEFT", cb, "TOPLEFT", -2, 2)
        cb._blizzFrame:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 2, -2)
        cb._blizzFrame:Show()
    else
        cb._blizzFrame:Hide()
    end
    local tbAtlas = ns.UF_BlizzAtlas(ns.UF_CAST_BLIZZ.textbox)
    if tbAtlas and cb._nameSide ~= "none" then
        -- Under the BAR (not the holder): with an in-width icon the bar
        -- starts past the icon, and the box's left edge follows the bar's.
        ns.UF_StockAtlas(cb._blizzTextBox, tbAtlas)
        cb._blizzTextBox:ClearAllPoints()
        cb._blizzTextBox:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, 3)
        cb._blizzTextBox:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, -13)
        cb._blizzTextBox:Show()
    else
        cb._blizzTextBox:Hide()
    end
    -- The icon is the bare art, as stock: no EUI black plate, no border and
    -- no 1px inset (the inset was that border's room).
    local ico = cb._iconFrame
    if ico then
        PP.HideBorder(ico)
        if ico._bg then ico._bg:Hide() end
        if cb.Icon then
            cb.Icon:ClearAllPoints()
            cb.Icon:SetAllPoints(ico)
        end
    end
    if cb.Icon then cb.Icon:SetTexCoord(0, 1, 0, 1) end
    ns.UF_BlizzCastIcon(cb)
    if cb._layoutTextZones then cb:_layoutTextZones() end
end

-- Small-frame power bar (pet focus/energy/mana, target-of-target and
-- focus-target mana), as the stock small frames carry it. Built at spawn
-- ONLY under Blizzard Style, from the unit's own settings with the stock bar
-- geometry stamped over them, so it is not a user-positioned bar: the layout
-- pass owns its spot, size and art. Zero cost otherwise: the frame keeps no
-- Power widget (a WoW Forever pet builds its own user-positioned bar in
-- StyleSimpleFrame instead), so the engine registers no power channel and the
-- painter returns on the first field test, exactly as today.
function ns.UF_BlizzMiniPower(frame, unit, settings)
    if not ns.UF_Blizz() or not frame.Health then return nil end
    local view = setmetatable({ powerPosition = "below", powerHeight = 7, powerWidth = 0 },
        { __index = settings })
    return CreatePowerBar(frame, unit, view)
end

-- The post-pass. Idempotent: geometry is re-asserted, regions exist once.
function ns.UF_ApplyBlizzardLayout(frame, unit)
    if not frame or not frame.Health then return end
    if InCombatLockdown() then return end
    unit = unit or frame._euiBaseUnit or frame._euiUnit
    -- Layout by unit + Portrait Side (stamped on the frame for the helpers).
    local G, mirror = ns.UF_BlizzResolve(frame, unit)
    if not G then return end
    local settings = GetSettingsForUnit(unit)

    -- Frame: stock size + hit rect.
    frame:SetSize(G.w, G.h)
    local hit = G.hit
    if mirror then
        frame:SetHitRectInsets(hit[2], hit[1], hit[3], hit[4])
    else
        frame:SetHitRectInsets(hit[1], hit[2], hit[3], hit[4])
    end
    -- Frame Scale: the stock size is fixed, so the whole frame scales instead.
    -- A change re-seats the saved position (anchor offsets follow the scale);
    -- chained boss frames and unlock-anchored frames sit relative to their
    -- anchor and need nothing.
    local sc = settings and settings.blizzScale or 1
    if sc < 0.5 then sc = 0.5 elseif sc > 2 then sc = 2 end
    local prevScale = frame:GetScale()
    if prevScale ~= sc then
        frame:SetScale(sc)
        local posKey = unit:match("^boss%d$") and "boss" or unit
        if (posKey ~= "boss" or unit == "boss1")
           and not (EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(posKey)) then
            ApplyFramePosition(frame, posKey)
        end
        -- Elements size-matched to the frame from another scale (bars on
        -- UIParent) re-pull its art width at the new scale; the frame's own
        -- size never changes, so no resize notify would reach them. Only on a
        -- real change: GetScale reads back float32, so most scales never
        -- compare equal to the setting.
        if math.abs(prevScale - sc) > 0.001 and (posKey ~= "boss" or unit == "boss1")
           and EllesmereUI.ReapplyMatchPads then
            EllesmereUI.ReapplyMatchPads(posKey)
        end
    end
    if frame._barClip then
        frame._barClip:ClearAllPoints()
        frame._barClip:SetAllPoints(frame)
    end

    -- Health bar at the stock position; the offsets the class power and
    -- scale passes read back are kept in step.
    local health = frame.Health
    local clip = frame._barClip or frame
    health:ClearAllPoints()
    ns.UF_BlizzPoint(health, "TOPLEFT", clip, "TOPLEFT", G.health.x, -G.health.y, mirror)
    health:SetSize(G.health.w, G.health.h)
    local hx = mirror and (G.w - G.health.x - G.health.w) or G.health.x
    health._xOffset = hx
    health._rightInset = G.w - hx - G.health.w
    health._topOffset = G.health.y

    -- Power bar: stock position when attached; detached bars keep their own
    -- spot (only the art changes); "none" stays hidden. The small frames carry
    -- the stock bar in the art's track, never a user-positioned one.
    local power = frame.Power
    local ppPos = settings and settings.powerPosition or "below"
    if power and G.small then
        power:ClearAllPoints()
        ns.UF_BlizzPoint(power, "TOPLEFT", clip, "TOPLEFT", G.power.x, -G.power.y, mirror)
        power:SetSize(G.power.w, G.power.h)
        if power._pbBorder then power._pbBorder:Hide() end
        power._blizzMasked = true
        power:Show()
    elseif power and ppPos ~= "none" then
        local detached = (ppPos == "detached_top" or ppPos == "detached_bottom")
        if not detached then
            power:ClearAllPoints()
            ns.UF_BlizzPoint(power, "TOPLEFT", clip, "TOPLEFT", G.power.x, -G.power.y, mirror)
            power:SetSize(G.power.w, G.power.h)
            -- The art pass below seats the stock mask after the fill texture is set.
            power._blizzMasked = true
        else
            power._blizzMasked = nil
        end
        if power._pbBorder then power._pbBorder:Hide() end
    end

    ns.UF_ApplyBlizzFrameArt(frame, G)

    ns.UF_ApplyBlizzBarArt(frame)

    -- Absorb overlays share the bar's new footprint.
    local hp = frame.HealthPrediction and frame.HealthPrediction.damageAbsorb
    if hp then
        local hw, hh = health:GetWidth(), health:GetHeight()
        local bars = ns._ufBarScratch
        if not bars then bars = {}; ns._ufBarScratch = bars end
        bars[1], bars[2], bars[3], bars[4], bars[5] = hp, hp._forward, hp._healAbsorb, nil, nil
        for i = 1, 3 do
            local sb = bars[i]
            if sb and sb.SetSize then sb:SetSize(hw, hh) end
        end
    end

    ns.UF_ApplyBlizzPortrait(frame, G)

    -- No EUI chrome: unified border and text bar step aside for the art.
    if frame.unifiedBorder then frame.unifiedBorder:Hide() end
    if frame.BottomTextBar then frame.BottomTextBar:Hide() end

    ns.UF_BlizzTextPass(frame)
    ns.UF_BlizzLevelPass(frame)
    -- Live text-position edits re-run the style's ApplyTextPositions directly;
    -- follow every call with the strip placement (wrapped once per frame).
    if frame._applyTextPositions and not frame._blizzTextWrapped then
        frame._blizzTextWrapped = true
        local orig = frame._applyTextPositions
        frame._applyTextPositions = function(s)
            orig(s)
            ns.UF_BlizzTextPass(frame)
            ns.UF_BlizzLevelPass(frame)
        end
    end
    if frame.Castbar then ns.UF_ApplyBlizzCastbar(frame.Castbar) end
end
