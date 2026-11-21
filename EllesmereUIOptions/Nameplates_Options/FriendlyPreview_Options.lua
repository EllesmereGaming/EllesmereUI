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
    -- Read as a plate by the live stock-style builders (PaintBar): the bar's
    -- background, and the unit whose level the level art shows.
    s.healthBG = bg
    s.unit = "player"
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
-- FriendlyFrame:UpdateSubText). Under a stock style the live builders draw
-- its art on the sample; Corner Radius is not drawn. guild: a guild line sits
-- between the name and the bar.
-- Returns the plate's height.
local function PaintBar(s, DBVal, lineSize)
    local w, h = ns.GetFriendlyHealthBarWidth(), ns.GetFriendlyHealthBarHeight()
    local nameSize = DBVal("friendlyNameTextSize")
    local off = 4 + (lineSize and (lineSize + 2) or 0)
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
    -- The stock styles (Global Settings > Style, latched for the session as on
    -- the live plates, where both border tests above read false): the art the
    -- friendly plate's ApplyHealthBarTexture, ApplyBorder and selection pass
    -- give it, through the same builders.
    local style = ns.NP_Style()
    if style == "blizzard" then
        ns.NP_ApplyBlizzBarArt(s)
        ns.NP_ApplyBlizzSelection(s, false)
        s.hpText:SetDrawLayer("OVERLAY", 7)
        -- WoW Forever: the level box right of the bar.
        if ns.NP_Forever() then ns.NP_ApplyForeverLevelBox(s, h) end
    elseif style == "classic" then
        ns.NP_ApplyClassicHealthArt(s, h)
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

-------------------------------------------------------------------------------
--  What the samples stand for
-------------------------------------------------------------------------------
-- A row's eye in the highlight cogs puts that entry on a sample: the players'
-- entries on the player sample, the NPCs' and their pets' on the NPC sample,
-- which becomes a pet for a pet entry. The colour comes from the catalog by
-- that key (EUI_Nameplates_AlliedColors.lua), so a sample can never disagree
-- with a live plate; with no eye on, the sample is the plain unit. Name Only
-- only -- the health bar plate colours its name by its own settings.
local function PreviewIsPet(key)
    if not (key and ns.Allied and ns.Allied.PreviewTarget) then return false end
    local _, pet = ns.Allied.PreviewTarget(key)
    return pet
end
local function PreviewColor(key, base)
    if key and ns.Allied and ns.Allied.PreviewNameColor then
        return ns.Allied.PreviewNameColor(key, base)
    end
    return base.r, base.g, base.b
end
-- The line under a pet's or an NPC's name, as the overlay paints it. A pet's owner
-- line answers its own switches (Show Owner Name, Owner Text Color, Match Pet Name
-- Color); an NPC's subtitle answers the NPC ones (Show NPC Titles, NPC Title
-- Color, Match NPC Name Color). sizeKey is the row that sizes it. Returns the
-- height it adds.
local function PaintNameLine(s, DBVal, text, sizeKey, nameR, nameG, nameB, petLine)
    local colorKey = petLine and "friendlyPetOwnerColor" or "friendlyNPCTitleColor"
    local matchKey = petLine and "friendlyPetOwnerMatchNameColor" or "friendlyNPCTitleMatchNameColor"
    -- A pet's owner line always shows; an NPC's subtitle saves only when turned off.
    if not petLine and DBVal("showNPCTitles") == false then
        s.sub:SetText("")
        return 0
    end
    local size = DBVal(sizeKey)
    EllesmereUI.SetFontFamily(s.sub, ns.GetFont(), size, "OUTLINE", ns.GetNPUseShadow())
    local t = DBVal(colorKey)
    if DBVal(matchKey) == true then
        s.sub:SetTextColor(nameR, nameG, nameB, t.a or 1)
    else
        s.sub:SetTextColor(t.r, t.g, t.b, t.a or 1)
    end
    s.sub:SetText("<" .. text .. ">")
    s.sub:ClearAllPoints()
    s.sub:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
    return 1 + size
end

-- A pet's owner line: Owner Text Uses Its Own Size off, it takes the pet name's
-- size (as the live overlay does in GetNPCTitleSize).
local function PetOwnerSizeKey(DBVal)
    return DBVal("friendlyPetOwnerOwnSize") == true and "friendlyPetTitleSize" or "friendlyPetNameSize"
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
-- Name Format, the title around the name, the brackets, the level. Both modes
-- draw the guild under the name in the guild colour, as a text of its own at
-- Guild Text Size (ApplySubText; Name Only's WriteNameOnlySub). When a row's
-- eye previews the player's pet entry the
-- sample becomes that pet: the pet's sizes and its owner's line. Returns the
-- sample's height.
-- The Status Tags eye on the page puts a tag on the sample's name: <AFK> while
-- AFK is ticked (it wins, as on a live plate), else <DND>.
local function SampleStatusTag(DBVal)
    if DBVal("friendlyStatusTagAFK") == true then return " " .. (CHAT_FLAG_AFK or "<AFK>") end
    if DBVal("friendlyStatusTagDND") == true then return " " .. (CHAT_FLAG_DND or "<DND>") end
    return nil
end

local function PaintPlayer(s, DB, DBVal, nameOnly, key, tagged)
    local mode = DBVal("friendlyBelowName") or "none"
    local titled = mode == "title" or mode == "both"
    local name = SampleName(DBVal("friendlyNameFormat"))
    if titled then name = SampleTitled(name) end
    -- The tag rides the name, inside the group brackets, as UpdateNameOnlyText and
    -- FriendlyFrame:UpdateName write it.
    local tag = tagged and SampleStatusTag(DBVal)
    if tag then name = name .. tag end
    if DBVal("friendlyGroupBrackets") == true then name = "|cffaaaaff[|r" .. name .. "|cffaaaaff]|r" end
    if DBVal("friendlyShowLevel") == true then
        name = ns.GetUnitLevelText("player", DBVal("friendlyLevelDiffColor") == true and "diffAll" or nil) .. " | " .. name
    end
    local guild = (mode == "guild" or mode == "both") and EllesmereUI.L("Guild") or nil
    local body = DBVal("friendlyBelowNameGuildBrackets") ~= false and "<%s>" or "%s"
    local _, class = UnitClass("player")
    local cc = EllesmereUI.GetClassColor(class)
    -- The guild line's colour: Match Player Name Color makes it the name's own
    -- colour, else Class Colored the class colour, else the Custom one.
    local plateName = ns.FriendlyNameClass(DB(), false) and cc or DBVal("friendlyNameColor") or WHITE
    local gc = DBVal("friendlyBelowNameMatchNameColor") == true and plateName
        or (DBVal("friendlyBelowNameClassColor") and cc or DBVal("friendlyBelowNameColor"))
    if not nameOnly then
        local h = PaintBar(s, DBVal, guild and DBVal("friendlyBelowNameSize"))
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
    -- Name Only: Blizzard's name text under our font, size and colour. The
    -- player's pet entry makes it the overlay's pet plate: the pet's own sizes,
    -- and the owner's line under the name.
    local pet = PreviewIsPet(key)
    local size = pet and DBVal("friendlyPetNameSize") or DBVal("friendlyNameSize")
    -- Name Color, as Name Only shows it: the class colour, else the Custom
    -- colour, then the previewed entry's own.
    local nc = ns.FriendlyNameClass(DB(), true) and cc or DBVal("friendlyNameColor") or WHITE
    local nr, ng, nb = PreviewColor(key, nc)
    s.health:Hide()
    ns.SetFSFont(s.name, size, "OUTLINE, SLUG")
    s.name:SetTextColor(nr, ng, nb)
    s.name:ClearAllPoints()
    if pet then
        s.name:SetText(EllesmereUI.L("Pet"))
        local extra = PaintNameLine(s, DBVal, EllesmereUI.L("Friendly Player"),
            PetOwnerSizeKey(DBVal), nr, ng, nb, true)
        -- The name and its line sit as one block, as the overlay's do on a plate.
        s.name:SetPoint("TOP", s, "CENTER", 0, math.floor((size + extra) / 2))
        return size + extra
    end
    s.name:SetPoint("CENTER", s, "CENTER")
    s.name:SetText(name)
    if guild then
        local gr, gg, gb = gc.r, gc.g, gc.b
        if DBVal("friendlyBelowNameMatchNameColor") == true then gr, gg, gb = nr, ng, nb end
        -- The guild line, a text of its own at Guild Text Size.
        local gsize = DBVal("friendlyBelowNameSize")
        ns.SetFSFont(s.sub, gsize, "OUTLINE, SLUG")
        s.sub:SetFormattedText(body, guild)
        s.sub:SetTextColor(gr, gg, gb)
        s.sub:ClearAllPoints()
        s.sub:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
        local extra = 1 + gsize
        s.name:SetPoint("TOP", s, "CENTER", 0, math.floor((size + extra) / 2))
        return size + extra
    end
    s.sub:SetText("")
    return size
end

-- The NPC sample. Name Only: the name-only overlay of an NPC (mirrors
-- ShowNPCOverlay, ApplyOverlayStyle, FormatNPCName and UpdateOverlayRaidIcon):
-- the name in its format, size and colour, the title under it and, while the
-- page's eye asks for one (marked), a raid marker in the Raid Marker slot. A
-- row's eye previewing a pet entry makes it that pet: the pet's sizes and its
-- owner's line. Otherwise the health bar plate in the NPC colour, its name
-- whole and with no title (the tail of PaintFriendlyColors and
-- FriendlyFrame:UpdateName). Returns the sample's height.
local function PaintNPC(s, DBVal, nameOnly, marked, key)
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
    local pet = PreviewIsPet(key)
    local font, outline, shadow = ns.GetFont(), "OUTLINE", ns.GetNPUseShadow()
    local h, top = pet and DBVal("friendlyPetNameSize") or DBVal("friendlyNPCNameSize"), 0
    -- The overlay's own base colour, then the previewed entry's.
    local nr, ng, nb = PreviewColor(key, DBVal("friendlyNPCNameColor"))
    s.health:Hide()
    EllesmereUI.SetFontFamily(s.name, font, h, outline, shadow)
    s.name:SetTextColor(nr, ng, nb)
    s.name:SetText(EllesmereUI.ShortName(pet and EllesmereUI.L("Pet") or name, DBVal("friendlyNPCNameFormat")))
    -- A pet's line names its owner; an NPC's is its own subtitle.
    h = h + PaintNameLine(s, DBVal,
        pet and EllesmereUI.L("Friendly NPC") or EllesmereUI.L("Merchant"),
        pet and PetOwnerSizeKey(DBVal) or "friendlyNPCTitleSize", nr, ng, nb, pet)
    if marked and DBVal("showNPCRaidMarker") ~= false then
        local pos = ns.GetRaidMarkerPos()
        if pos ~= "none" then
            local size = ns.GetRaidMarkerSize()
            local xOff, yOff = ns.GetAuraSlotOffsets("raidMarker")
            SetRaidTargetIconTexture(s.raid, 8)
            s.raid:SetSize(size, size)
            s.raid:ClearAllPoints()
            -- Centred above the name, as the live overlay draws it: a name-only
            -- plate has no bar for a slot's alignment to hang off.
            s.raid:SetPoint("BOTTOM", s.name, "TOP", xOff, 2 + yOff)
            s.raid:Show()
            top = size + 2 + yOff
        end
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
    -- What each sample is previewing: the entry whose eye is on, or nil for the
    -- plain unit. An eye left on over an entry that is off or greyed shows
    -- nothing (its eye reads closed then): FriendlyPage_Options.lua answers.
    local pKey = env.optState.friendlyPlayerPreview
    local nKey = env.optState.friendlyNPCPreview
    if pKey and ns.NPO_AlliedPreviewOff(pKey) then pKey = nil end
    if nKey and ns.NPO_AlliedPreviewOff(nKey) then nKey = nil end
    -- The panel's scale compensated: a sample draws at a live plate's size.
    local scale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()
    pl:SetScale(scale)
    npc:SetScale(scale)
    local block = math.max(PaintPlayer(pl, env.DB, DBVal, nameOnly, pKey, env.optState.showStatusTagPreview),
        PaintNPC(npc, DBVal, nameOnly, env.optState.showNPCMarkerPreview, nKey)) * scale
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
    -- Dimmed while EllesmereUI does not draw that plate: the previewed kind's
    -- own toggle decides (a pet entry dims with Show Friendly Pet Nameplates).
    local pOn = playersOn and (not PreviewIsPet(pKey) or DBVal("showFriendlyPets") == true)
    local nOn
    if PreviewIsPet(nKey) then
        nOn = playersOn and DBVal("showFriendlyPets") == true
    else
        nOn = playersOn and DBVal("showFriendlyNPCs") == true
    end
    pl:SetAlpha(pOn and 1 or 0.3)
    npc:SetAlpha(nOn and 1 or 0.3)
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
