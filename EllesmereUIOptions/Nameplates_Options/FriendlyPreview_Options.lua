if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\FriendlyPreview_Options.lua
--  Nameplates options: the two sample plates in the content header of the
--  Friendly Plates page, a friendly player (named Friendly Player, in your
--  own class and level, with a set title and guild) and a friendly NPC
--  (ns.NPO_BuildFriendlyHeader, ns.NPO_FriendlyPreviewUpdate). Definitions
--  only; the shared helpers come from ns._NPO_OptEnv (filled by
--  EUI_Nameplates_Options.lua).
--
--  Each sample follows its section's settings as EllesmereUINameplatesFriendly.lua
--  draws a live plate: the name alone in Name Only mode, else the health bar
--  plate. It is a plain frame built once and hung on every header root the page
--  gets (the page pool buries what it did not make under a frame it made, so a
--  sample never sits under a pooled frame). The samples are painted by a write
--  on the page, a page show and the panel's show, and only while they are on
--  screen.
--
--  A click on a part of a sample scrolls the page to the row that sets it and
--  highlights it (env.Nav, page id env.PAGE_FRIENDLY): the overlays are made
--  once with the samples and shown with the part they cover; the page's
--  build maps each key to its rows. The kit's hint line sits under the samples.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

-- Never the page pool's CreateFrame: the samples are kept across header builds.
local NewFrame = _G.CreateFrame

local PAD = 16      -- header px kept free above the samples and under them
local MIN_H = 60    -- the header's least height
local HINT_Y = 17   -- the hint line's bottom over the header's
local WHITE = { r = 1, g = 1, b = 1 }
local S             -- { player, npc, hdr, colX, h }, nil until the first header build

-- The click overlays of each sample, made once with it: the part each covers,
-- the page's key for it, how it shows (text: while the font string holds
-- text; tex: while the texture shows; neither: with its parent, the bar) and
-- its frame level over the sample's (a text on the bar above the bar's).
local PLAYER_OVERLAYS = {
    { part = "health", key = "playerBar", lvl = 10 },
    { part = "hpText", key = "healthPercent", text = true, lvl = 16 },
    { part = "name", key = "playerName", text = true, lvl = 15 },
    { part = "sub", key = "playerGuild", text = true, lvl = 16 },
}
local NPC_OVERLAYS = {
    { part = "health", key = "npcBar", lvl = 10 },
    { part = "hpText", key = "healthPercent", text = true, lvl = 16 },
    { part = "name", key = "npcName", text = true, lvl = 15 },
    { part = "sub", key = "npcTitle", text = true, lvl = 16 },
    { part = "raid", key = "npcMarker", tex = true, lvl = 15 },
}

-- One sample plate: a health bar (its background, border frame and percent
-- text), a name, a second text (the guild line or the NPC's title) and a raid
-- marker, all placed around the sample's centre by the painters.
local function NewSample()
    local s = NewFrame("Frame")
    s:SetSize(1, 1)
    s.health = NewFrame("StatusBar", nil, s)
    s.health:SetMinMaxValues(0, 1)
    s.health:SetValue(1)
    local bg = s.health:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 1)
    s.border = NewFrame("Frame", nil, s.health)
    s.border:SetAllPoints()
    s.hpText = s.health:CreateFontString(nil, "OVERLAY")
    s.hpText:SetPoint("RIGHT", s.health, -2, 0)
    s.name = s:CreateFontString(nil, "OVERLAY")
    s.sub = s:CreateFontString(nil, "OVERLAY")
    -- A font string takes no text before its first font (a family, as on the plates).
    ns.SetFSFont(s.hpText, 10, "OUTLINE, SLUG")
    ns.SetFSFont(s.name, 12, "OUTLINE, SLUG")
    ns.SetFSFont(s.sub, 12, "OUTLINE, SLUG")
    s.raid = s:CreateTexture(nil, "OVERLAY")
    s.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    return s
end

-- A sample's click overlays over the page's navigator P, made once with the
-- sample (s.ovs: the button, its hover frame, the part, the spec).
local function MakeOverlays(s, P, specs)
    s.ovs = {}
    for i = 1, #specs do
        local spec = specs[i]
        local el = s[spec.part]
        local btn, _, hl = P.Overlay(el, spec.key, spec.text)
        s.ovs[i] = { btn = btn, hl = hl, el = el, spec = spec }
    end
end

-- Each overlay shows while the part it covers shows (the bar's go with the
-- bar); a text's overlay takes the text's new size.
local function SyncOverlays(s)
    local ovs = s.ovs
    for i = 1, #ovs do
        local o = ovs[i]
        if o.spec.text then
            local shown = (o.el:GetText() or "") ~= ""
            o.btn:SetShown(shown)
            if shown then o.btn._resizeToText() end
        elseif o.spec.tex then
            o.btn:SetShown(o.el:IsShown())
        end
    end
end

-- The health bar plate of either sample, at full health: the bar's size and
-- texture, the enemy plates' Basic or custom border, the percent text and the
-- name's size and lift (mirrors the friendly plate pool's build with its
-- plate:ApplyBorder, FriendlyFrame:UpdateHealth and the anchors of
-- FriendlyFrame:UpdateSubText). The stock styles' plate art and Corner Radius
-- are not drawn. guild: a guild line sits between the name and the bar.
-- Returns the plate's height.
local function PaintBar(s, DBVal, guild)
    local w, h = ns.GetFriendlyHealthBarWidth(), ns.GetFriendlyHealthBarHeight()
    local nameSize = DBVal("friendlyNameTextSize")
    local off = 4 + (guild and (DBVal("friendlyBelowNameSize") + 2) or 0)
    local total = h + off + nameSize
    local health, bf = s.health, s.border
    health:SetSize(w, h)
    health:ClearAllPoints()
    health:SetPoint("BOTTOM", s, "CENTER", 0, -math.floor(total / 2))
    health:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(ns.healthBarTextures,
        DBVal("healthBarTexture") or "none", "Interface\\Buttons\\WHITE8x8"))
    health:Show()
    if ns.IsCustomBorderEnabled() then
        local tex, sz, c = DBVal("customBorderTexture"), DBVal("customBorderSize"), DBVal("customBorderColor")
        bf:SetFrameLevel(math.max(0, health:GetFrameLevel() + (DBVal("customBorderBehind") and -1 or 1)))
        EllesmereUI.ApplyBorderStyle(bf, sz, c.r, c.g, c.b, DBVal("customBorderAlpha") or 1, tex,
            DBVal("customBorderOffset"), DBVal("customBorderOffsetY"),
            DBVal("customBorderShiftX"), DBVal("customBorderShiftY"),
            "nameplates", sz, nil, EllesmereUI.BorderPx(DBVal("customBorderSizePx"), sz, tex))
    elseif ns.IsBorderEnabled() then
        local r, g, b = ns.GetBorderColor()
        bf:SetFrameLevel(health:GetFrameLevel() + 1)
        EllesmereUI.ApplyBorderStyle(bf, ns.NP_BorderSize(), r, g, b, 1, "solid")
    else
        EllesmereUI.ApplyBorderStyle(bf, 0)
    end
    ns.SetFSFont(s.hpText, 10, "OUTLINE, SLUG")
    s.hpText:SetText(DBVal("friendlyHideHealthText") and "" or "100%")
    -- On the side of the bar the live plates put it (Show Health Percent).
    ns.NP_PlaceFriendlyHealthText(s.hpText, health, DBVal("friendlyHealthTextPos"))
    ns.SetFSFont(s.name, nameSize, "OUTLINE, SLUG")
    s.name:ClearAllPoints()
    s.name:SetPoint("BOTTOM", health, "TOP", 0, off)
    s.sub:ClearAllPoints()
    s.sub:SetPoint("TOP", health, "TOP", 0, off - 1)
    return total
end

-- The player sample's name under the Name Format. A retail character's name
-- is one word, which First Name, Last Name and Abbreviated leave whole, so
-- there only a Character Count cuts the sample's; a WoW Forever name carries
-- a surname, as the sample's two words do.
local function SampleName(mode)
    local name = EllesmereUI.L("Friendly Player")
    if not mode or (not EllesmereUI.IS_FOREVER and type(mode) ~= "number") then return name end
    return EllesmereUI.ShortName(name, mode)
end

-- The sample's title, for the Subtitle Text modes that show titles: a set
-- one after the name (one format string, so a language can place it).
local function SampleTitled(shown)
    return EllesmereUI.Lf("%s The Immortal", shown)
end

-- The player sample: a friendly player named Friendly Player, in your own
-- class and level, with a set title and guild. Its name is composed as both friendly modes
-- compose it (mirrors UpdateNameOnlyText and FriendlyFrame:UpdateName; your
-- own plate never takes group brackets, so the sample wears the party's): the
-- Name Format, the title around the name, the brackets, the level. Name Only
-- (Blizzard's own name text under our font, size and class colour setting)
-- carries the guild as a second line of the name in the guild colour; the
-- health bar plate draws it as a line of its own (ApplySubText) and takes its
-- bar and name colours from the plates' painter. Returns the sample's height.
local function PaintPlayer(s, DB, DBVal, nameOnly)
    local mode = DBVal("friendlyBelowName") or "none"
    local titled = mode == "title" or mode == "both"
    local name = SampleName(DBVal("friendlyNameFormat"))
    if titled then name = SampleTitled(name) end
    if DBVal("friendlyGroupBrackets") == true then name = "|cffaaaaff[|r" .. name .. "|cffaaaaff]|r" end
    if DBVal("friendlyShowLevel") == true then
        name = ns.GetUnitLevelText("player", DBVal("friendlyLevelDiffColor") == true and "diffAll" or nil) .. " | " .. name
    end
    local guild = (mode == "guild" or mode == "both") and EllesmereUI.L("Guild") or nil
    local body = DBVal("friendlyBelowNameGuildBrackets") ~= false and "<%s>" or "%s"
    local _, class = UnitClass("player")
    local cc = EllesmereUI.GetClassColor(class)
    local gc = DBVal("friendlyBelowNameClassColor") and cc or DBVal("friendlyBelowNameColor")
    if not nameOnly then
        local h = PaintBar(s, DBVal, guild)
        ns.NP_PaintFriendlyColors(s, "player", DB())
        s.name:SetText(name)
        if guild then
            ns.SetFSFont(s.sub, DBVal("friendlyBelowNameSize"), "OUTLINE, SLUG")
            s.sub:SetFormattedText(body, guild)
            s.sub:SetTextColor(gc.r, gc.g, gc.b)
        else
            s.sub:SetText("")
        end
        return h
    end
    local size = DBVal("friendlyNameSize")
    -- Name Color, as Name Only shows it: the class colour, else the Custom colour.
    local nc = ns.FriendlyNameClass(DB(), true) and cc or DBVal("friendlyNameColor") or WHITE
    s.health:Hide()
    s.sub:SetText("")
    ns.SetFSFont(s.name, size, "OUTLINE, SLUG")
    s.name:SetTextColor(nc.r, nc.g, nc.b)
    s.name:ClearAllPoints()
    s.name:SetPoint("CENTER", s, "CENTER")
    if guild then
        s.name:SetFormattedText("%s\n" .. EllesmereUI.HexColor(gc.r, gc.g, gc.b) .. body .. "|r", name, guild)
        return size * 2 + 2
    end
    s.name:SetText(name)
    return size
end

-- The NPC sample. Name Only: the name-only overlay of a friendly NPC (mirrors
-- ShowNPCOverlay, ApplyOverlayStyle, FormatNPCName and UpdateOverlayRaidIcon):
-- the name in its format, size and colour, the title under it and, while the
-- page's eye asks for one (marked), a raid marker above it. Otherwise the
-- health bar plate in the NPC colour, its name whole and with no title (the
-- tail of PaintFriendlyColors and FriendlyFrame:UpdateName). Returns the
-- sample's height.
local function PaintNPC(s, DBVal, nameOnly, marked)
    local name = EllesmereUI.L("Friendly NPC")
    s.raid:Hide()
    if not nameOnly then
        local h = PaintBar(s, DBVal)
        local c = DBVal("friendlyNPCColor")
        s.health:SetStatusBarColor(c.r, c.g, c.b)
        s.name:SetTextColor(c.r, c.g, c.b)
        s.name:SetText(name)
        s.sub:SetText("")
        return h
    end
    local font, outline, shadow = ns.GetFont(), ns.GetNPOutline(), ns.GetNPUseShadow()
    local h, top = DBVal("friendlyNPCNameSize"), 0
    local c = DBVal("friendlyNPCNameColor")
    s.health:Hide()
    EllesmereUI.SetFontFamily(s.name, font, h, outline, shadow)
    s.name:SetTextColor(c.r, c.g, c.b)
    s.name:SetText(EllesmereUI.ShortName(name, DBVal("friendlyNPCNameFormat")))
    if DBVal("showNPCTitles") ~= false then
        local size, t = DBVal("friendlyNPCTitleSize"), DBVal("friendlyNPCTitleColor")
        EllesmereUI.SetFontFamily(s.sub, font, size, outline, shadow)
        s.sub:SetTextColor(t.r, t.g, t.b, t.a or 1)
        s.sub:SetText("<" .. EllesmereUI.L("Merchant") .. ">")
        s.sub:ClearAllPoints()
        s.sub:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
        h = h + 1 + size
    else
        s.sub:SetText("")
    end
    if marked and DBVal("showNPCRaidMarker") ~= false and ns.GetRaidMarkerPos() ~= "none" then
        local size = ns.GetRaidMarkerSize()
        SetRaidTargetIconTexture(s.raid, 8)
        s.raid:SetSize(size, size)
        s.raid:ClearAllPoints()
        s.raid:SetPoint("BOTTOM", s.name, "TOP", 0, 2)
        s.raid:Show()
        top = size + 2
    end
    s.name:ClearAllPoints()
    s.name:SetPoint("TOP", s, "CENTER", 0, math.floor((h + top) / 2) - top)
    return h + top
end

-- Paints both samples and lays the header out; nothing while the samples are
-- not built or not on screen. The samples themselves are asked: the panel can
-- drop them from a header frame that then shows another page's header.
-- building: the header builder's own pass, which returns the height instead
-- of writing it.
local function Update(building)
    if not S or not (building or S.player:IsVisible()) then return end
    local hdr = S.hdr
    local env = ns._NPO_OptEnv
    local DBVal = env.DBVal
    local nameOnly = DBVal("friendlyNameOnly") ~= false
    local playersOn = DBVal("showFriendlyPlayers") ~= false
    local pl, npc = S.player, S.npc
    -- The panel's scale compensated: a sample draws at a live plate's size.
    local scale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()
    pl:SetScale(scale)
    npc:SetScale(scale)
    local block = math.max(PaintPlayer(pl, env.DB, DBVal, nameOnly),
        PaintNPC(npc, DBVal, nameOnly, env.optState.showNPCMarkerPreview)) * scale
    SyncOverlays(pl)
    SyncOverlays(npc)
    local H = math.max(MIN_H, math.ceil(PAD + block + PAD))
    -- Both samples centred in that room (the hint line adds its band under
    -- it). A SetPoint offset is in the sample's own units (header px over its
    -- scale), snapped to whole physical pixels.
    local Snap, es = EllesmereUI.PP.SnapForES, pl:GetEffectiveScale()
    local x, y = Snap(S.colX / scale, es), Snap(-H / 2 / scale, es)
    pl:ClearAllPoints()
    pl:SetPoint("CENTER", hdr, "TOP", -x, y)
    npc:ClearAllPoints()
    npc:SetPoint("CENTER", hdr, "TOP", x, y)
    -- Dimmed while EllesmereUI does not draw that plate.
    pl:SetAlpha(playersOn and 1 or 0.3)
    npc:SetAlpha((playersOn and DBVal("showFriendlyNPCs") == true) and 1 or 0.3)
    -- The header builder adds the hint line itself.
    if building then return H end
    -- The hint line's height while it shows; H is the height the header takes
    -- back when the hint goes (the kit keeps it).
    local total = H + env.Nav.HintH(env.PAGE_FRIENDLY, H)
    -- Against the height the samples last gave the header: the panel snaps what
    -- it is given to its own pixel grid, so the frame's height is no measure of it.
    if S.h ~= total then
        -- Silent: the page moves with the header, it never scrolls under it.
        EllesmereUI:SetContentHeaderHeightSilent(total)
        S.h = total
    end
    return total
end

-- A write on the Friendly Plates page, the page's show and the panel's show.
function ns.NPO_FriendlyPreviewUpdate()
    Update()
end

-- A header root lets go of the samples when it is cleared: each build takes
-- them back, at its own frame level, their overlays above them (a new parent
-- sets a frame's level anew).
local function Hang(s, hdr)
    s:SetParent(hdr)
    s:SetFrameLevel(hdr:GetFrameLevel() + 2)
    s.health:SetFrameLevel(s:GetFrameLevel() + 1)
    local base, ovs = s:GetFrameLevel(), s.ovs
    for i = 1, #ovs do
        local o = ovs[i]
        o.btn:SetFrameLevel(base + o.spec.lvl)
        o.hl:SetFrameLevel(base + o.spec.lvl + 1)
    end
    s:Show()
end

-- The header builder: hangs the samples on this build's header root, makes
-- the hint line and returns the header's height.
function ns.NPO_BuildFriendlyHeader(hdr, hdrW)
    local env = ns._NPO_OptEnv
    if not S then
        S = { player = NewSample(), npc = NewSample() }
        -- Clicks reach the rows of whichever build of the page mapped them last.
        local P = env.Nav.Page(env.PAGE_FRIENDLY)
        MakeOverlays(S.player, P, PLAYER_OVERLAYS)
        MakeOverlays(S.npc, P, NPC_OVERLAYS)
        -- Settings can change while the panel is closed: its show repaints the samples.
        EllesmereUI:RegisterOnShow(ns.NPO_FriendlyPreviewUpdate)
    end
    S.hdr, S.colX = hdr, hdrW / 4
    Hang(S.player, hdr)
    Hang(S.npc, hdr)
    local H = Update(true)
    S.h = env.Nav.Hint(env.PAGE_FRIENDLY, hdr, hdr, HINT_Y, H)
    return S.h
end
