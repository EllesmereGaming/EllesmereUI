if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\MicroMenu.lua
-- Micro menu block factory and Blizzard micro menu hider.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local _G               = _G
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer          = C_Timer
local GetTime          = GetTime
local pairs            = pairs
local ipairs           = ipairs
local type             = type
local pcall            = pcall
local format           = string.format
local tinsert          = table.insert
local tremove          = table.remove
local tconcat          = table.concat
local floor            = math.floor
local max              = math.max

local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local ParkSecureFrame      = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  MICROMENU (SECURE; three verbatim mechanisms)
--    1. Secure click-passthrough buttons (*clickbutton1 -> Blizzard button)
--    2. Combat lockout via RegisterStateDriver _onstate-combatlock snippet (never addon-Lua EnableMouse/SetAlpha on these frames post-creation)
--    3. Blizzard micro menu hider via SecureHandlerStateTemplate _onstate-vis (never :Hide() on MicroMenuContainer from insecure code)
-------------------------------------------------------------------------------
local MM_SPACING = 2
local MM_MEDIA = ns.MICROMENU_MEDIA

-- Button key -> icon file in EllesmereUI\media\micromenu\ (one PNG per button).
local MM_ICON_FILE = {
    menu    = "menu-options",
    guild   = "menu-guild",
    social  = "menu-friends",
    char    = "menu-character",
    spell   = "menu-spellbook",
    ach     = "menu-achievements",
    quest   = "menu-quests",
    lfg     = "menu-group",
    pvp     = "menu-pvp",
    housing = "menu-housing",
    journal = "menu-adventure",
    pet     = "menu-collections",
    shop    = "menu-shop",
    help    = "menu-cs",
}

local mmButtonDefs = {
    { key = 'menu',    binding = 'TOGGLEGAMEMENU',    label = MAINMENU_BUTTON,                  special = true },
    { key = 'guild',   binding = 'TOGGLEGUILD',       label = GUILD,                            info = true },
    { key = 'social',  binding = 'TOGGLESOCIAL',      label = SOCIAL_LABEL or SOCIAL_BUTTON,    info = true },
    { key = 'char',    binding = 'TOGGLECHARACTER0',  label = CHARACTER_BUTTON },
    -- Single combined button: PlayerSpellsMicroButton opens the merged
    -- Spec / Talents / Spellbook (and professions) frame.
    { key = 'spell',   binding = 'TOGGLESPELLBOOK',   label = 'Spec / Talents / Spellbook', special = true },
    { key = 'ach',     binding = 'TOGGLEACHIEVEMENT', label = ACHIEVEMENTS },
    { key = 'quest',   binding = 'TOGGLEQUESTLOG',    label = QUEST_LOG },
    { key = 'lfg',     binding = 'TOGGLEGROUPFINDER', label = DUNGEONS_BUTTON },
    { key = 'pvp',     binding = 'TOGGLECHARACTER4',  label = PLAYER_V_PLAYER or PVP_OPTIONS or 'PvP', special = true },
    { key = 'housing', binding = 'TOGGLEHOUSINGDASHBOARD', label = HOUSING_MICRO_BUTTON or 'Housing' },
    { key = 'journal', binding = 'TOGGLEENCOUNTERJOURNAL', label = ADVENTURE_JOURNAL,            special = true },
    { key = 'pet',     binding = 'TOGGLECOLLECTIONS', label = COLLECTIONS },
    { key = 'shop',    binding = false,               label = BLIZZARD_STORE },
    { key = 'help',    binding = false,               label = HELP_BUTTON },
}
local mmButtonOrder = {}
local mmButtonDefsByKey = {}
for _, def in ipairs(mmButtonDefs) do
    mmButtonOrder[#mmButtonOrder + 1] = def.key
    mmButtonDefsByKey[def.key] = def
end

-- String names for Blizzard MicroButtons, resolved via _G at creation (first existing
-- global wins). Spellbook/talents/journal MUST open via a secure click on the micro
-- button -- addon-Lua opening taints the frame, and SetCooldown then rejects secrets inside Blizzard_SpellBookItem.
local MM_MICRO_BUTTON_NAMES = {
    guild   = "GuildMicroButton",
    social  = "QuickJoinToastButton",
    char    = "CharacterMicroButton",
    spell   = { "PlayerSpellsMicroButton", "SpellbookMicroButton" },
    journal = { "EJMicroButton" },
    ach     = "AchievementMicroButton",
    quest   = "QuestLogMicroButton",
    lfg     = "LFDMicroButton",
    housing = "HousingMicroButton",
    pet     = "CollectionsMicroButton",
    shop    = "StoreMicroButton",
    help    = "HelpMicroButton",
}

-- Native art is copied onto our textures; Blizzard's buttons are never modified.
local MM_BLIZZARD_ATLAS = {
    menu = "GameMenu", guild = "GuildCommunities", spell = "SpecTalents",
    talent = "SpecTalents", ach = "Achievements", quest = "Questlog",
    lfg = "Groupfinder", housing = "Housing", journal = "AdventureGuide",
    pet = "Collections", shop = "Shop", help = "GameMenu",
    profession = "Professions", legacy = "Legacy",
}
-- WoW Forever's group finder emblem is a round eye, held small by the art's
-- narrow width: it gets a square crop (this fraction of the art's width)
-- instead of the shared trim, so it fills the slot's full height.
local MM_SQUARE_CROP = EllesmereUI.IS_FOREVER and { lfg = 0.66 } or {}

local function FitBlizzardMicroIcon(icon, key)
    -- Native micro art has padding around its emblem. Trim that padding to
    -- match the portrait's visual weight without enlarging the slot or counters.
    -- Work inside the current sheet UV rectangle so packed sheets stay intact.
    local ulx, uly, llx, lly, urx, ury, lrx, lry = icon:GetTexCoord()
    local cx = (ulx + llx + urx + lrx) / 4
    local cy = (uly + lly + ury + lry) / 4
    local sx, sy = 2 / 3, 2 / 3
    local square, aspect = MM_SQUARE_CROP[key], icon._edbAspect
    if square and aspect then
        -- Equal pixels both ways: the height share shrinks by the art's aspect.
        sx, sy = square, square * aspect
        icon._edbAspect = nil
    end
    icon:SetTexCoord(
        cx + (ulx - cx) * sx, cy + (uly - cy) * sy,
        cx + (llx - cx) * sx, cy + (lly - cy) * sy,
        cx + (urx - cx) * sx, cy + (ury - cy) * sy,
        cx + (lrx - cx) * sx, cy + (lry - cy) * sy)
end
-- Art-only sources: these keys click a different Blizzard button than they copy art from.
local MM_ART_BUTTON = { menu = "MainMenuMicroButton", pvp = "PVPMicroButton", social = "SocialsMicroButton" }

-- First existing global among a name or list of names.
local function FindMicroButton(names)
    if type(names) ~= "table" then return names and _G[names] end
    for _, name in ipairs(names) do
        if _G[name] then return _G[name] end
    end
end

-- Draws an atlas from its sheet file with the sheet coords. An atlas-mode
-- texture does not take sheet coords in SetTexCoord, so the trim above only
-- works on art painted this way.
local function SetAtlasArt(icon, atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    local file = info and (info.file or info.filename)
    if not file then return false end
    icon:SetTexture(file)
    icon:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
    -- Native shape (retail micro art is 32x40); PaintIcon fits it in the slot.
    if info.width > 0 and info.height > 0 then icon._edbAspect = info.width / info.height end
    return true
end

-- Blizzard's guild button: in a guild with a tabard, the banner tinted with the
-- tabard's background colour (the block draws the emblem over it); otherwise
-- the plain guild icon. The tint rides icon._edbTint for IconColor.
local function SetGuildArt(icon)
    local tabard = select(10, GetGuildLogoInfo()) and C_GuildInfo.GetGuildTabardInfo("player")
    if tabard and tabard.backgroundColor
        and SetAtlasArt(icon, "UI-HUD-MicroMenu-GuildCommunities-GuildColor-Up") then
        icon._edbTint = tabard.backgroundColor
        return "micro"
    end
    return SetAtlasArt(icon, "UI-HUD-MicroMenu-GuildCommunities-Up") and "micro" or false
end

-- Copies Blizzard's art for key onto icon: "micro" for padded art (micro
-- buttons) that gets trimmed, "plain" for art that fills its texture (the PvP
-- faction crest, the Battle.net portrait), false when none exists.
local function SetBlizzardArt(icon, key)
    if key == "guild" then return SetGuildArt(icon) end
    local source = FindMicroButton(MM_ART_BUTTON[key] or MM_MICRO_BUTTON_NAMES[key])
    local normal = source and source.GetNormalTexture and source:GetNormalTexture()
    local atlas = normal and normal:GetAtlas()
    if atlas then
        if SetAtlasArt(icon, atlas) then return "micro" end
    else
        local texture = normal and normal:GetTexture()
        if texture then
            icon:SetTexture(texture)
            icon:SetTexCoord(normal:GetTexCoord())
            -- The shape Blizzard draws it at; an unresolved size stays square.
            local w, h = normal:GetSize()
            if not (issecretvalue(w) or issecretvalue(h)) and w > 0 and h > 0 then
                icon._edbAspect = w / h
            end
            return "micro"
        end
    end
    local stem = MM_BLIZZARD_ATLAS[key]
    if stem and SetAtlasArt(icon, "UI-HUD-MicroMenu-" .. stem .. "-Up") then return "micro" end
    if key == "social" then
        -- No friends micro button exists: the Friends window's own portrait.
        icon:SetTexture("Interface\\FriendsFrame\\Battlenet-Portrait")
        icon:SetTexCoord(0, 1, 0, 1)
        return "plain"
    elseif key == "pvp" then
        -- No PvP micro button exists: the faction crest the player frame shows
        -- while flagged (the UI-PVP file keeps its emblem in one corner).
        local faction = UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance"
        if SetAtlasArt(icon, "UI-HUD-UnitFrame-Player-PVP-" .. faction .. "Icon")
            or SetAtlasArt(icon, "UI-HUD-UnitFrame-SmallCircle-" .. faction) then
            return "plain"
        end
        icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
        icon:SetTexCoord(0, 1, 0, 1)
        return "plain"
    end
    return false
end

-- Skips the repaint while the icon already shows this style; force repaints
-- (portrait and guild changes, and PLAYER_ENTERING_WORLD for Blizzard art that
-- was missing). Returns true when it painted.
local function ApplyMicroIcon(icon, key, blizzard, force)
    if not force and icon._edbWow == blizzard then return end
    icon._edbWow = blizzard
    icon._edbAspect = nil   -- square unless the Blizzard art below sets its own
    icon._edbTint = nil
    if blizzard and key == "char" then
        icon:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(icon, "player")
        return true
    end
    local art = blizzard and SetBlizzardArt(icon, key)
    if art == "micro" then
        FitBlizzardMicroIcon(icon, key)
    elseif not art then
        local def = mmButtonDefsByKey[key]
        icon:SetTexture(def.icon or (MM_MEDIA .. (MM_ICON_FILE[key] or key) .. ".png"))
        icon:SetTexCoord(0, 1, 0, 1)
    end
    return true
end

-- Blizzard art keeps its own colors (the guild banner its tabard tint); custom
-- art takes the block color.
local function IconColor(block, icon)
    local s = block.settings
    if s and s.iconStyle == "wow" then
        local tint = icon and icon._edbTint
        if tint then return tint.r, tint.g, tint.b end
        return 1, 1, 1
    end
    return BlockColorOf(block)
end

local function OnlineCount(key)
    if key == "guild" then
        if IsInGuild() then return select(2, GetNumGuildMembers()) or 0 end
    elseif key == "social" then
        return (select(2, BNGetNumFriends()) or 0) + (C_FriendList.GetNumOnlineFriends() or 0)
    end
end

-- WoW Forever splits the spellbook and the talents into two micro buttons. Its
-- PlayerSpellsMicroButton still exists but opens the frame on whichever tab was last
-- shown, so there the spell entry clicks the spellbook's own button and a Talents entry follows it.
if EllesmereUI.IS_FOREVER then
    MM_MICRO_BUTTON_NAMES.spell  = "SpellbookMicroButton"
    MM_MICRO_BUTTON_NAMES.talent = "TalentMicroButton"
    for i, def in ipairs(mmButtonDefs) do
        if def.key == 'spell' then
            def.label = SPELLBOOK or 'Spellbook'
            -- Full icon path: the shared micromenu art holds glyphs this strip's own set lacks,
            -- so Talents does not repeat the Achievements glyph right beside it.
            local talent = { key = 'talent', binding = 'TOGGLETALENTS', label = TALENTS or 'Talents', onWhenUnset = true,
                icon = MM_MEDIA .. "menu-vault.png" }
            tinsert(mmButtonDefs, i + 1, talent)
            tinsert(mmButtonOrder, i + 1, 'talent')
            mmButtonDefsByKey.talent = talent
            break
        end
    end
    -- Forever-only micro buttons, placed after the Talents entry. Default
    -- off (opt-in via Menu Elements). Professions uses the shared
    -- menu-professions art; in the Blizzard icon style both copy their own
    -- micro button's art like every other button.
    MM_MICRO_BUTTON_NAMES.profession = "ProfessionMicroButton"
    MM_MICRO_BUTTON_NAMES.legacy     = "LegacyMicroButton"
    MM_ICON_FILE.legacy = "menu-legacy"
    local extras = {
        { key = 'profession', binding = 'TOGGLEPROFESSIONBOOK', label = PROFESSIONS_BUTTON or 'Professions',
          icon = MM_MEDIA .. "menu-professions.png" },
        { key = 'legacy', binding = 'TOGGLELEGACYSYSTEM', label = LEGACY_BUTTON or 'Legacy' },
    }
    for i, def in ipairs(mmButtonDefs) do
        if def.key == 'talent' then
            for j, extra in ipairs(extras) do
                tinsert(mmButtonDefs, i + j, extra)
                tinsert(mmButtonOrder, i + j, extra.key)
                mmButtonDefsByKey[extra.key] = extra
            end
            break
        end
    end
    -- Achievements, PvP, Housing, Adventure Guide and Shop stay out of the
    -- Forever strip and options checklist. Saved settings keep their keys.
    local FOREVER_OFF = { ach = true, pvp = true, housing = true, journal = true, shop = true }
    for i = #mmButtonDefs, 1, -1 do
        local key = mmButtonDefs[i].key
        if FOREVER_OFF[key] then
            tremove(mmButtonDefs, i)
            tremove(mmButtonOrder, i)
            mmButtonDefsByKey[key] = nil
        end
    end
end

-- Whether a block shows one button. A button added after blocks were saved
-- (onWhenUnset) reads a missing setting as on, as the options checklist does.
local function MMButtonOn(mm, key)
    local v = mm[key]
    if v == nil then
        local def = mmButtonDefsByKey[key]
        return def and def.onWhenUnset or false
    end
    return v
end
ns.MicroMenuButtonOn = MMButtonOn

local function IndexOf(list, key)
    for i = 1, #list do if list[i] == key then return i end end
end

-- Saved order first (unknown and repeated keys dropped). A default key the
-- saved order lacks (new, or saved on the other client: profiles are shared)
-- goes back behind its default predecessor, not to the end.
local orderSeen = {}
function ns.GetMicroMenuOrder(settings, out)
    wipe(out); wipe(orderSeen)
    if type(settings.buttonOrder) == "table" then
        for _, key in ipairs(settings.buttonOrder) do
            if mmButtonDefsByKey[key] and not orderSeen[key] then
                out[#out + 1] = key; orderSeen[key] = true
            end
        end
    end
    for i, key in ipairs(mmButtonOrder) do
        if not orderSeen[key] then
            local at = i > 1 and IndexOf(out, mmButtonOrder[i - 1]) or 0
            tinsert(out, at + 1, key)
        end
    end
    return out
end
-- Refresh's scratch for the resolved order (read straight through, never kept).
local orderScratch = {}

-- Saves a reordered strip. Saved keys this client lacks (the other client's
-- buttons) stay behind the key they followed, so neither client loses its order.
function ns.SetMicroMenuOrder(settings, keys)
    local old = settings.buttonOrder
    if type(old) == "table" then
        for i, key in ipairs(old) do
            if not mmButtonDefsByKey[key] and not IndexOf(keys, key) then
                local at = i > 1 and IndexOf(keys, old[i - 1]) or 0
                tinsert(keys, at + 1, key)
            end
        end
    end
    settings.buttonOrder = keys
end


-- Plain-button click handlers (no Blizzard secure backing). Shared table: they close over no instance state.
local mmClickFunctions = {}
mmClickFunctions.menu = function(_, button)
    if button == "LeftButton" then
        if not InCombatLockdown() then ToggleFrame(GameMenuFrame) end
    elseif button == "RightButton" then
        if IsShiftKeyDown() then EllesmereUI.RequestReload(EllesmereUI.L("Reload UI"), EllesmereUI.L("Reload the UI now?"))
        elseif not InCombatLockdown() then ToggleFrame(AddonList) end
    end
end
local function MMBlockedInCombat(button)
    return button ~= "LeftButton" or InCombatLockdown()
end
mmClickFunctions.spell = function(_, button)
    if MMBlockedInCombat(button) then return end
    if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
        PlayerSpellsUtil.ToggleSpellBookFrame()
    elseif _G.SpellBookFrame then ToggleFrame(_G.SpellBookFrame) end
end
mmClickFunctions.pvp = function(_, button)
    if MMBlockedInCombat(button) then return end
    if _G.TogglePVPUI then
        _G.TogglePVPUI()
    elseif _G.PVEFrame and _G.PVEFrame:IsShown() then
        -- Behave as a toggle: close when already on the PvP tab, otherwise switch to it.
        if PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(_G.PVEFrame) == 2 then
            HideUIPanel(_G.PVEFrame)
        elseif PanelTemplates_SetTab then
            PanelTemplates_SetTab(_G.PVEFrame, 2)
        else
            HideUIPanel(_G.PVEFrame)
        end
    elseif _G.LFDMicroButton and _G.LFDMicroButton.Click then
        _G.LFDMicroButton:Click()
        C_Timer.After(0, function()
            if _G.PVEFrame and _G.PVEFrame:IsShown() and PanelTemplates_SetTab then
                PanelTemplates_SetTab(_G.PVEFrame, 2)
            end
        end)
    end
end
mmClickFunctions.journal = function(_, button)
    if MMBlockedInCombat(button) then return end
    -- Go through Blizzard's toggle so the frame is placed by the UI panel system; ej:Show() directly would bypass ShowUIPanel.
    if _G.ToggleEncounterJournal then
        _G.ToggleEncounterJournal()
    else
        if _G.EncounterJournal_LoadUI then _G.EncounterJournal_LoadUI() end
        local ej = _G.EncounterJournal
        if ej then
            if ej:IsShown() then HideUIPanel(ej) else ShowUIPanel(ej) end
        end
    end
end

-- Blizzard micro menu hider. Calling frame:Hide() from addon Lua on Edit Mode managed
-- frames (MicroMenuContainer) taints the managed frame system, blocking the next
-- ActionBarController_UpdateAll (e.g. vehicle exit); the hider's _onstate-vis runs inside the secure context instead.
local mmHiders = {}
local function MMGetHider(frame)
    local hider = mmHiders[frame]
    if hider then return hider end
    if InCombatLockdown() then return nil end
    hider = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
    hider:SetFrameRef("target", frame)
    hider:SetAttribute("_onstate-vis", [[
        local target = self:GetFrameRef('target')
        if newstate == 'hide' then target:Hide() else target:Show() end
    ]])
    mmHiders[frame] = hider
    return hider
end

-- Union semantics: Blizzard's micro menu is hidden iff ANY micromenu block on an
-- enabled, non-deleted bar sets settings.disableBlizzardMicroMenu. Recomputed on
-- every micromenu Refresh/Destroy and every bar enable/disable/delete (engine calls this from AfterBarStateChange).
local mmLastApplied = nil  -- last driver state pushed ("hide"/"show"); nil = never touched
-- force: re-push the driver even when the wanted state is unchanged. The driver registers
-- a CONSTANT state string, so its snippet runs once and never re-evaluates: anything that
-- hides the container later (a pet battle) is never undone, and the steady-state guard below
-- makes later refreshes no-ops. Callers repairing an EXTERNAL actor's move pass force; settings-driven callers pass nothing.
function ns.RefreshMicroMenuHider(force)
    local hide = false
    local profile = ns.GetProfile()
    if profile then
        local bars = profile.bars
        for i = 1, #bars do
            local bar = bars[i]
            if not ns.VisIsNever(bar) then
                for j = 1, #bar.blocks do
                    local b = bar.blocks[j]
                    if b.type == "micromenu" and b.settings and b.settings.disableBlizzardMicroMenu then
                        hide = true
                    end
                end
            end
        end
    end
    -- Never touch Blizzard's micro menu until a block opts in: with nothing applied a "show" needs no restore, so no hiders on the managed frames.
    if not hide and mmLastApplied == nil then return end
    -- Steady-state guard: re-registering the same driver re-runs the secure snippet (and
    -- re-Shows the target) for nothing. Push only changes, unless a caller is repairing an external hide, where the re-run IS the repair.
    local want = hide and "hide" or "show"
    if not force and want == mmLastApplied then return end
    mmLastApplied = want
    ns.DeferUntilOOC("edb_mm_blizz", function()
        -- Build the target list without array holes (any of these globals may be absent on a given client).
        local targets = {}
        if _G.MicroMenuContainer then targets[#targets + 1] = _G.MicroMenuContainer end
        if _G.MainMenuBarMicroButtons then targets[#targets + 1] = _G.MainMenuBarMicroButtons end
        if _G.MicroButtonAndBagsBar then targets[#targets + 1] = _G.MicroButtonAndBagsBar end
        for i = 1, #targets do
            local hider = MMGetHider(targets[i])
            if hider then
                UnregisterStateDriver(hider, "vis")
                RegisterStateDriver(hider, "vis", want)
            end
        end
        -- Action Bars' micro menu end caps follow the container's shown state
        -- (a no-op while that bar shows none).
        local ab = EllesmereUI._ModuleNS.EllesmereUIActionBars
        if ab and ab.AB_ExtraCapsShown then ab.AB_ExtraCapsShown("MicroBar") end
    end)
end

-- Character stats tooltip (always on). Fixed set: equipped item
-- level, primary stat, and the four secondary percentages with raw combat rating in
-- parentheses. Versatility is pcall-wrapped: GetVersatilityBonus/GetCombatRatingBonus
-- can return a secret value under tainted execution (arithmetic on it errors), so drop the line instead.
local CS_DIM = "|cffaaaaaa"

local function MMPrimaryStat()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    local _, _, _, _, _, statID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if statID == LE_UNIT_STAT_STRENGTH  then return SPELL_STAT1_NAME or "Strength",  1 end
    if statID == LE_UNIT_STAT_AGILITY   then return SPELL_STAT2_NAME or "Agility",   2 end
    if statID == LE_UNIT_STAT_INTELLECT then return SPELL_STAT4_NAME or "Intellect", 4 end
    return nil
end

local function MMAddCharStats()
    local ar, ag, ab = ns.GetAccent()
    -- Stat reads return SECRET numbers in restricted content. They do NOT error on
    -- read: format() carries the secret into the row text, which detonates in
    -- Tip_Show's width measuring. Check every value and drop that row alone (Tip_AddDouble also refuses secret rows as a net).
    local function clean(v)
        if issecretvalue(v) then return nil end
        return v or 0
    end
    local function pctRating(label, pct, rating)
        pct, rating = clean(pct), clean(rating)
        if not (pct and rating) then return end
        ns.Tip_AddDouble(label,
            format("%.2f%%", pct) .. " " .. CS_DIM .. "(" .. floor(rating + 0.5) .. ")|r",
            ar, ag, ab, 1, 1, 1)
    end

    ns.Tip_AddLine(" ")

    local _, eq = GetAverageItemLevel()
    eq = clean(eq)
    if eq then
        ns.Tip_AddDouble(STAT_AVERAGE_ITEM_LEVEL or "Item Level", format("%.1f", eq), ar, ag, ab, 1, 1, 1)
    end

    local pLabel, pIdx = MMPrimaryStat()
    if pLabel and pIdx then
        local _, eff = UnitStat("player", pIdx)
        eff = clean(eff)
        if eff then
            ns.Tip_AddDouble(pLabel, format("%.0f", eff), ar, ag, ab, 1, 1, 1)
        end
    end

    -- WoW Forever has no Mastery or Versatility.
    if EllesmereUI.IS_FOREVER then
        local crit, critCR = EllesmereUI.ForeverCritChance()
        local haste, hasteCR = EllesmereUI.ForeverHaste()
        pctRating(STAT_CRITICAL_STRIKE or "Critical Strike", crit,  GetCombatRating(critCR))
        pctRating(STAT_HASTE or "Haste",                     haste, GetCombatRating(hasteCR))
        return
    end

    local crit, critCR = EllesmereUI.PlayerCritChance()
    pctRating(STAT_CRITICAL_STRIKE or "Critical Strike", crit,               GetCombatRating(critCR))
    pctRating(STAT_HASTE or "Haste",                     GetHaste(),         GetCombatRating(CR_HASTE_MELEE))
    pctRating(STAT_MASTERY or "Mastery",                 GetMasteryEffect(), GetCombatRating(CR_MASTERY))

    -- Versatility: secret-value-safe (see block comment above).
    local ok, dmg, rating = pcall(function()
        local d = (GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0)
                + (GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)  or 0)
        return d, GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0
    end)
    if ok then
        pctRating(STAT_VERSATILITY or "Versatility", dmg, rating)
    end
end

-- Interactive Social / Guild tooltips (always on): online member lists
-- built on the owned Tip system's insecure clickable-row primitive (Tip_AddClickable).
-- Every action (whisper/invite/BNet whisper) is UNPROTECTED, so rows stay clickable in and out of combat. Shift is the fixed invite modifier.

-- Taint-safe whisper (mirrors the minimap friends tooltip): BNet friends by
-- Battle.net account name (any character/faction/realm), everyone else by character
-- name. Explicit DEFAULT_CHAT_FRAME skips ChatFrame_SendTell's FCF_OpenTemporaryWindow
-- path, which drives the secret window list and taints all of chat. Whispers are
-- suppressed in protected content (Mythic+/raid); invites are unaffected (InviteUnit opens no window).
local function MMOpenWhisper(charName, bnetName)
    -- Suppress whispers wherever chat is taint-sensitive: (1) protected content, (2)
    -- while /euidev is on -- it forces the same secret-value restricted environment
    -- as a real Mythic+. InProtectedInstance() itself reports true in dev mode; the
    -- separate branch exists only for the clearer message.
    local blocked
    if EllesmereUI.IsDevModeActive() then
        blocked = "This action is protected while dev mode (/euidev) is on."
    elseif EllesmereUI.InProtectedInstance() then
        blocked = "This action is protected in Mythic+ and raid combat."
    end
    if blocked then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(blocked, 1.0, 0.3, 0.3, 1.0) end
        return
    end
    if bnetName and bnetName ~= "" then
        local sendBN = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if sendBN then sendBN(bnetName, DEFAULT_CHAT_FRAME); return end
    end
    if charName and charName ~= "" then
        local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        -- Fix "Name-Realm-Realm" to "Name-Realm"
        local target = EllesmereUI.BuildFullName(charName) or charName
        if sendTell then sendTell(target, DEFAULT_CHAT_FRAME) end
    end
end

-- GuildRoster() itself fires GUILD_ROSTER_UPDATE, and the server rate-limits it (~10s); throttle so hovering the guild button does not spam requests.
local mmLastTipRoster = 0

-- Member rows per tooltip, as in the minimap friends tooltip: a big friend list or
-- guild otherwise grows it past the screen. The rest become one "...and N more" line.
local MM_TIP_MAX_ROWS = 30

local function MMBuildSocialTip()
    local ar, ag, ab = ns.GetAccent()
    local totalBN = BNGetNumFriends() or 0
    local totalWoW = C_FriendList.GetNumOnlineFriends() or 0
    local playerFaction = UnitFactionGroup("player")

    ns.Tip_AddLine(" ")

    -- Only people actually in WoW: app / other-game friends add nothing here. Same filter as the minimap tooltip (gameAccountInfo.clientProgram=="WoW").
    local shown, hidden = 0, 0

    -- BNet friends in WoW. Indices are unsorted, so iterate all and filter.
    for i = 1, totalBN do
        local acc = C_BattleNet.GetFriendAccountInfo(i)
        local ga  = acc and acc.gameAccountInfo
        local inWoW = ga and ga.isOnline and ga.clientProgram == BNET_CLIENT_WOW
        if inWoW and shown >= MM_TIP_MAX_ROWS then
            hidden = hidden + 1
        elseif inWoW then
            local charName, realmName = ga.characterName, ga.realmName
            local faction = ga.factionName
            local icon    = FRIENDS_TEXTURE_ONLINE
            if acc.isAFK or ga.isGameAFK  then icon = FRIENDS_TEXTURE_AFK end
            if acc.isDND or ga.isGameBusy then icon = FRIENDS_TEXTURE_DND end
            -- Left text carries NO |c codes so hover recolor (Tip_Show) shows; its blue rides the left-color args. Right column keeps its codes.
            local left  = format("|T%s:16|t %s", icon, acc.accountName or "?")
            -- A cross-faction BNet friend's characterName can be secret; format("%s", ...)
            -- rejects it outright, so display text uses a nil'd-out copy. The real
            -- charName below is kept whole for BuildFullName (invite/whisper). The
            -- area name rides the same format call and the faction feeds a compare,
            -- so a secret in either is dropped the same way: no area shown, and a
            -- friend whose faction cannot be read is treated as not ours to invite.
            local displayCharName, displayArea = charName, ga.areaName
            if issecretvalue(displayCharName) then displayCharName = nil end
            if issecretvalue(displayArea) then displayArea = nil end
            local secretFaction = issecretvalue(faction)
            -- Character name in its class colour when the class reads plain, else gold.
            local nameText
            local classID = ga.classID
            local ci = displayCharName and classID and not issecretvalue(classID)
                and C_CreatureInfo.GetClassInfo(classID)
            if ci and ci.classFile then
                local cc = EllesmereUI.GetClassColor(ci.classFile)
                nameText = EllesmereUI.ColorText(displayCharName, cc.r, cc.g, cc.b)
            else
                nameText = format("|cffecd672%s|r", displayCharName or "?")
            end
            local right = format("%s %s", nameText, displayArea or "")
            local bnetName   = acc.accountName
            local sameFaction = (not secretFaction) and ((not faction) or (faction == playerFaction))
            -- Fix "Name-Realm-Realm" to "Name-Realm"
            local inviteName  = EllesmereUI.BuildFullName(charName, realmName)
            ns.Tip_AddClickable(left, right, function(mouseButton)
                if mouseButton == "LeftButton" then
                    if IsShiftKeyDown() and sameFaction and inviteName then
                        C_PartyInfo.InviteUnit(inviteName)
                    else
                        MMOpenWhisper(nil, bnetName)
                    end
                elseif mouseButton == "RightButton" and sameFaction and inviteName then
                    MMOpenWhisper(inviteName, nil)
                end
            end, 0.51, 0.77, 1, 1, 1, 1)
            shown = shown + 1
        end
    end

    -- WoW (non-BNet) friends.
    if totalWoW > 0 then
        for i = 1, C_FriendList.GetNumFriends() do
            local fi = C_FriendList.GetFriendInfoByIndex(i)
            local online = fi and fi.connected
            if online and shown >= MM_TIP_MAX_ROWS then
                hidden = hidden + 1
            elseif online then
                local icon = FRIENDS_TEXTURE_ONLINE
                if fi.afk then icon = FRIENDS_TEXTURE_AFK end
                if fi.dnd then icon = FRIENDS_TEXTURE_DND end
                -- No |c codes on the left (hover recolor needs a plain string); the class
                -- colour rides the left-color args (white when the class is unknown).
                local left = format("|T%s:16|t %s  %s", icon, fi.name or "?", fi.level or "")
                local cr, cg, cb = 1, 1, 1
                local token = EllesmereUI.ClassTokenFromLocalized(fi.className)
                if token then
                    local cc = EllesmereUI.GetClassColor(token)
                    cr, cg, cb = cc.r, cc.g, cc.b
                end
                local fname = fi.name
                ns.Tip_AddClickable(left, fi.area or "", function(mouseButton)
                    local n = fname
                    if not n then return end
                    if not n:find("%-") then n = n .. "-" .. GetRealmName():gsub("%s+", "") end
                    if mouseButton == "RightButton" then
                        MMOpenWhisper(n, nil)
                    elseif mouseButton == "LeftButton" and IsShiftKeyDown() then
                        C_PartyInfo.InviteUnit(n)
                    end
                end, cr, cg, cb, 0.8, 0.8, 0.8)
                shown = shown + 1
            end
        end
    end

    if shown == 0 then
        ns.Tip_AddLine(L["NO_FRIENDS_ONLINE"], 0.6, 0.6, 0.6)
        return
    end
    if hidden > 0 then ns.Tip_AddLine(format("...and %d more", hidden), 0.53, 0.53, 0.53) end

    -- Left-click BNet-whispers (reaches them cross-realm/faction), right-click whispers the character directly: distinct actions, distinct labels.
    ns.Tip_AddLine(" ")
    ns.Tip_AddDouble(L["LEFT_CLICK"],       L["WHISPER_BNET"], 1, 1, 1, ar, ag, ab)
    ns.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["INVITE"],       1, 1, 1, ar, ag, ab)
    ns.Tip_AddDouble(L["RIGHT_CLICK"],      L["WHISPER"],      1, 1, 1, ar, ag, ab)
end

local function MMBuildGuildTip()
    local ar, ag, ab = ns.GetAccent()
    ns.Tip_AddLine(" ")
    if not IsInGuild() then
        ns.Tip_AddLine(L["NOT_IN_GUILD"], 0.6, 0.6, 0.6)
        return
    end

    local now = GetTime()
    if not InCombatLockdown() and (now - mmLastTipRoster) >= 10 then
        mmLastTipRoster = now
        C_GuildInfo.GuildRoster()
    end

    local gName = GetGuildInfo("player")
    if gName then ns.Tip_AddLine("|cff00ff00" .. gName .. "|r") end

    local shown, hidden = 0, 0
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, _, _, isOnline, status, class = GetGuildRosterInfo(i)
        if isOnline and shown >= MM_TIP_MAX_ROWS then
            hidden = hidden + 1
        elseif isOnline then
            shown = shown + 1
            local clr, clg, clb = 1, 1, 1
            if class then
                local cc = EllesmereUI.GetClassColor(class)
                clr, clg, clb = cc.r, cc.g, cc.b
            end
            local st  = (status == 1 and DEFAULT_AFK_MESSAGE) or (status == 2 and DEFAULT_DND_MESSAGE) or ""
            local cn  = name and name:match("[^-]+") or "?"
            -- Left plain (no |c): the class color rides the left-color args so the hover recolor to accent shows, like the M+ teleport rows.
            local left  = format("%s  %s %s", level or "", cn, st)
            local fname = name
            ns.Tip_AddClickable(left, zone or "", function(mouseButton)
                if not fname then return end
                if mouseButton == "LeftButton" then
                    if IsShiftKeyDown() then C_PartyInfo.InviteUnit(EllesmereUI.BuildFullName(fname) or fname)
                    else MMOpenWhisper(fname, nil) end
                end
            end, clr, clg, clb, 1, 1, 1)
        end
    end
    if hidden > 0 then ns.Tip_AddLine(format("...and %d more", hidden), 0.53, 0.53, 0.53) end

    ns.Tip_AddLine(" ")
    ns.Tip_AddDouble(L["LEFT_CLICK"],       L["WHISPER"], 1, 1, 1, ar, ag, ab)
    ns.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["INVITE"],  1, 1, 1, ar, ag, ab)
end

ns.BlockFactories.micromenu = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = {
        "GUILD_ROSTER_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
        "FRIENDLIST_UPDATE",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
        -- A pet battle hides this block's buttons and, with Disable Blizzard Micro
        -- Menu on, Blizzard's container; neither returns on its own. BOTH end events
        -- are registered: OVER fires while the result panel is up, CLOSE when the world
        -- UI returns, and which lands last differs per win/forfeit/flee (handler is
        -- idempotent). OPENING_START is NOT registered: refreshing into the takeover restores nothing.
        "PET_BATTLE_OVER", "PET_BATTLE_CLOSE",
    }

    -- Per-instance button sets (unique global names per instance).
    local frames = {}
    local icons = {}
    local textFS = {}
    local active, portraitEvents, guildEvents = false, false, false
    local guildEmblem
    local lastRosterRequest = 0

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local function GetIconSize()
        -- Fixed content size: bar Height never scales icons (Content Scale does).
        return max(16, floor(CONTENT_BASE * 0.82 + 0.5))
    end

    local function SocialFontSize()
        -- 0.3667 ratio = 11px at the 30px base.
        return max(7, floor(CONTENT_BASE * 0.3667 + 0.5))
    end

    -- The guild emblem over the tinted tabard banner (Blizzard style in a guild),
    -- placed as Blizzard's guild button places it: 12x14, 2px up, on 32x40 art,
    -- here trimmed to its middle 2/3. Re-textured only when the banner repainted.
    local function PaintGuildEmblem(icon, frame, painted, w, h)
        if not icon._edbTint then
            if guildEmblem then guildEmblem:Hide() end
            return
        end
        if not guildEmblem then
            guildEmblem = frame:CreateTexture(nil, "OVERLAY", nil, 1)
            painted = true
        end
        if painted then SetSmallGuildTabardTextures("player", guildEmblem) end
        guildEmblem:SetSize(w * 0.5625, h * 0.525)
        guildEmblem:ClearAllPoints()
        guildEmblem:SetPoint("CENTER", icon, "CENTER", 0, h * 0.075)
        guildEmblem:Show()
    end

    -- Blizzard style: a shown counter sits above its icon (new blocks seed the
    -- Text Position 8px up), so the guild banner and the friends emblem drop
    -- to clear it.
    local function PlaceIcon(key)
        local icon, fs = icons[key], textFS[key]
        local drop = 0
        if fs and fs:IsShown() and D().iconStyle == "wow" then
            drop = floor(SocialFontSize() * 0.45 + 0.5)
        end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", 0, -drop)
    end

    local function PaintIcon(key, force)
        local icon, frame = icons[key], frames[key]
        if not icon or not frame then return end
        local painted = ApplyMicroIcon(icon, key, D().iconStyle == "wow", force)
        -- SetPortraitTexture can reset anchors; restore our slot after each paint.
        PlaceIcon(key)
        local size = max(8, GetIconSize() - 6)
        -- Non-square Blizzard art keeps its shape, fitted inside the square.
        local w, h = size, size
        local aspect = icon._edbAspect
        if aspect and aspect < 1 then w = floor(size * aspect + 0.5)
        elseif aspect and aspect > 1 then h = floor(size / aspect + 0.5) end
        icon:SetSize(w, h)
        if frame:IsMouseOver() then icon:SetVertexColor(ns.GetAccent())
        else icon:SetVertexColor(IconColor(blockCfg, icon)) end
        if key == "guild" then PaintGuildEmblem(icon, frame, painted, w, h) end
    end

    -- Blizzard style only: the portrait and the guild tabard repaint from their
    -- own events, registered while the style and that button are on.
    local function SyncStyleEvents()
        local mm = D()
        local wow = active and mm.iconStyle == "wow"
        local want = wow and MMButtonOn(mm, "char") and icons.char ~= nil
        if portraitEvents ~= want then
            portraitEvents = want
            if want then
                inst.eventFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player")
                inst.eventFrame:RegisterEvent("PORTRAITS_UPDATED")
            else
                inst.eventFrame:UnregisterEvent("UNIT_PORTRAIT_UPDATE")
                inst.eventFrame:UnregisterEvent("PORTRAITS_UPDATED")
            end
        end
        want = wow and MMButtonOn(mm, "guild") and icons.guild ~= nil
        if guildEvents ~= want then
            guildEvents = want
            if want then inst.eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
            else inst.eventFrame:UnregisterEvent("PLAYER_GUILD_UPDATE") end
        end
    end

    -- Counters sit on their button (the Text Position offsets move them; new
    -- blocks seed them 8px above the icon) in both icon styles.
    local function SetCounterText(key, value)
        local fs = textFS[key]
        ns.SetFont(fs, SocialFontSize(), BC())
        fs:SetText(value)
        if not fs:IsShown() then
            fs:Show()
            if icons[key] then PlaceIcon(key) end
        end
        if frames[key]:IsMouseOver() then fs:SetTextColor(ns.GetAccent())
        else fs:SetTextColor(BlockColorOf(blockCfg)) end
    end

    local function ShowButtonTooltip(name)
        local frame = frames[name]; if not frame then return end
        local def = mmButtonDefsByKey[name]; if not def then return end
        local r, g, b = 1, 1, 1
        ns.Tip_Begin(frame)
        local title = '|cFFFFFFFF' .. (def.label or name) .. '|r'
        if def.binding then
            local k1, k2 = GetBindingKey(def.binding)
            local keys = {}
            if k1 and k1 ~= '' then keys[#keys + 1] = GetBindingText(k1) end
            if k2 and k2 ~= '' then keys[#keys + 1] = GetBindingText(k2) end
            if #keys > 0 then
                title = title .. ' |cFFFFD200(' .. tconcat(keys, ' / ') .. ')|r'
            end
        end
        ns.Tip_AddLine(title, r, g, b)

        if name == 'ach' then
            local pts = 0
            if GetTotalAchievementPoints then pts = GetTotalAchievementPoints() or 0 end
            local hexAccent = format('%02x%02x%02x', floor(r * 255), floor(g * 255), floor(b * 255))
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble('|cFFFFFFFF' .. L["ACH_POINTS"] .. '|r', '|cFF' .. hexAccent .. pts .. '|r', 1, 1, 1, r, g, b)
        end

        -- Delve Journey and Companion Level rows: WoW Forever has no Delves.
        if name == 'journal' and not EllesmereUI.IS_FOREVER then
            local hexAccent = format('%02x%02x%02x', floor(r * 255), floor(g * 255), floor(b * 255))
            ns.Tip_AddLine(" ")
            local delveRank, delveMax = 0, '?'
            if C_DelvesUI and C_DelvesUI.GetDelvesFactionForSeason
               and C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
                local fid = C_DelvesUI.GetDelvesFactionForSeason()
                if fid then
                    delveRank = C_MajorFactions.GetCurrentRenownLevel(fid) or 0
                    if C_MajorFactions.GetRenownLevels then
                        local levels = C_MajorFactions.GetRenownLevels(fid)
                        if type(levels) == 'table' and #levels > 0 then
                            delveMax = tostring(#levels)
                        end
                    end
                end
            end
            ns.Tip_AddDouble('|cFFFFFFFF' .. L["DELVE_JOURNEY"] .. '|r',
                '|cFF' .. hexAccent .. delveRank .. '|r |cFFAAAAAA/ ' .. delveMax .. '|r', 1, 1, 1, r, g, b)
            local companionLvl = 0
            if C_DelvesUI and C_DelvesUI.GetFactionForCompanion and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local cfid = C_DelvesUI.GetFactionForCompanion()
                if cfid then
                    local fi = C_GossipInfo.GetFriendshipReputation(cfid)
                    if fi and fi.reaction then
                        companionLvl = tonumber(fi.reaction:match("%d+")) or 0
                    end
                end
            end
            ns.Tip_AddDouble('|cFFFFFFFF' .. L["COMPANION_LEVEL"] .. '|r',
                '|cFF' .. hexAccent .. companionLvl .. '|r', 1, 1, 1, r, g, b)
        end

        if name == 'char' then
            -- Secret handling lives inside (every stat value is issecretvalue-checked);
            -- pcall is only a last resort so an API surprise never kills the rest of the tooltip.
            pcall(MMAddCharStats)
        end

        if name == 'social' then pcall(MMBuildSocialTip) end
        if name == 'guild'  then pcall(MMBuildGuildTip)  end

        ns.Tip_Show()
    end

    -- Per-button hover/click wiring. Runs once per frame, at creation time.
    local function SetupButtonScripts(name, frame)
        local isSecure = frame:GetAttribute("*clickbutton1") ~= nil
        if not isSecure then
            -- Plain button (special actions with no Blizzard micro button: menu, pvp;
            -- plus spell/journal on clients missing the global). Safe to call EnableMouse/SetScript freely.
            frame:EnableMouse(true)
            frame:RegisterForClicks("AnyUp")
            local fn = mmClickFunctions[name]
            if fn then
                frame:SetScript("OnClick", fn)
            else
                frame:SetScript("OnClick", function() end)
            end
        else
            -- Secure button: RegisterForClicks is permitted before combat;
            -- SetScript("OnClick") is not.
            frame:RegisterForClicks("AnyUp")
        end

        -- OnEnter / OnLeave are never protected, safe on all button types.
        frame:SetScript("OnEnter", function()
            -- Hover tint stays alive in combat (our textures/fonts only).
            local r, g, b = ns.GetAccent()
            if icons[name] then
                icons[name]:SetVertexColor(r, g, b, 1)
            end
            -- The counter text (guild/social) follows its button's hover.
            if textFS[name] then
                textFS[name]:SetTextColor(r, g, b, 1)
            end
            if InCombatLockdown() then
                -- The FULL tooltip reads combat-restricted surfaces (char stat
                -- secrets, guild/social rosters); in lockdown show a notice.
                local def = mmButtonDefsByKey[name]
                ns.Tip_Begin(frame)
                ns.Tip_AddLine('|cFFFFFFFF' .. ((def and def.label) or name) .. '|r', 1, 1, 1)
                ns.Tip_AddLine(L["CANNOT_USE_COMBAT"], 0.65, 0.65, 0.65)
                ns.Tip_Show()
                return
            end
            ShowButtonTooltip(name)
        end)
        frame:SetScript("OnLeave", function()
            if icons[name] then icons[name]:SetVertexColor(IconColor(blockCfg, icons[name])) end
            if textFS[name] then textFS[name]:SetTextColor(BlockColorOf(blockCfg)) end
            ns.Tip_HideUnlessInteractive(frame)
        end)
    end

    -- Create one button frame (idempotent). Returns nil in combat: secure frame creation/attribute setup must wait for PLAYER_REGEN_ENABLED.
    local function EnsureButtonFrame(def)
        local key = def.key
        if frames[key] then return frames[key] end
        if InCombatLockdown() then
            -- Secure creation must wait for regen; the deferred marker is the only thing that still hides the strip in combat.
            inst._mmDeferred = true
            return nil
        end
        local microBtnName = MM_MICRO_BUTTON_NAMES[key]
        local microRef
        if type(microBtnName) == "table" then
            for _, n in ipairs(microBtnName) do
                microRef = _G[n]
                if microRef then break end
            end
        elseif microBtnName then
            microRef = _G[microBtnName]
        end
        if (key == 'housing' or key == 'talent' or key == 'profession' or key == 'legacy') and not microRef then
            -- Skip optional buttons whose Blizzard micro button does not exist.
            return nil
        end
        local frame
        local gname = "EWB_MM_" .. inst.key .. "_" .. key
        if microRef then
            -- Taint-safe: pass clicks through to the Blizzard MicroButton.
            frame = CreateFrame("Button", gname, content,
                "SecureActionButtonTemplate,SecureHandlerStateTemplate")
            frame:SetAttribute("*clickbutton1", microRef)
            -- Without this, the ActionButtonUseKeyDown CVar makes the secure handler act on key-down only, discarding our "AnyUp" clicks.
            frame:SetAttribute("useOnKeyDown", false)
            frame:SetAttribute("*type1", "click")
            frame:EnableMouse(true)
            frame:RegisterForClicks("AnyUp")
            -- Combat: drop the click ACTION only, from inside the secure env. Stays
            -- mouse-enabled so hover works (OnEnter shows the combat notice); a click while *type1 is nil does nothing.
            RegisterStateDriver(frame, "combatlock", "[combat] combat; nocombat")
            frame:SetAttribute("_onstate-combatlock", [[
                if newstate == 'combat' then
                    self:SetAttribute('*type1', nil)
                else
                    self:SetAttribute('*type1', 'click')
                end
            ]])
        else
            -- Plain button for special actions with no secure backing.
            frame = CreateFrame("Button", gname, content)
            frame:EnableMouse(true)
        end
        frames[key] = frame
        if def.info then
            textFS[key]    = frame:CreateFontString(nil, "OVERLAY")
            AttachTextOffset(inst, textFS[key])
        end
        icons[key] = frame:CreateTexture(nil, "OVERLAY")
        ApplyMicroIcon(icons[key], key, D().iconStyle == "wow")
        SetupButtonScripts(key, frame)
        return frame
    end

    -- Materialise buttons for every enabled key. Tolerates a nil/partial set in combat; the REGEN_ENABLED event retries.
    local function CreateFramesInner()
        local mm = D()
        for _, def in ipairs(mmButtonDefs) do
            if MMButtonOn(mm, def.key) then EnsureButtonFrame(def) end
        end
        -- A full out-of-combat pass clears the deferred marker (buttons that cannot exist, e.g. housing without its micro button, do not count).
        if not InCombatLockdown() then inst._mmDeferred = nil end
    end

    local function ApplyCombatState()
        -- Combat does not hide the strip or kill mouse: buttons stay visible and
        -- hoverable (combat notice tooltip), clicks are inert in lockdown (secure
        -- buttons drop *type1 via their state driver). The one combat hide left: a strip
        -- whose enabled buttons could not all be built yet stays hidden until the REGEN retry materializes them.
        if inst._mmDeferred and InCombatLockdown() then
            content:Hide()
        else
            content:Show()
        end
    end

    local function UpdateGuildText()
        local mm = D()
        if not textFS.guild or not mm.guild or mm.hideSocialText then return end
        if not IsInGuild() then
            if textFS.guild:IsShown() then
                textFS.guild:Hide()
                if icons.guild then PlaceIcon("guild") end
            end
            return
        end
        -- Throttled: GuildRoster() itself fires GUILD_ROSTER_UPDATE, which re-enters this function; unthrottled that is a request loop.
        local now = GetTime()
        if not InCombatLockdown() and (now - lastRosterRequest) >= 15 then
            lastRosterRequest = now
            C_GuildInfo.GuildRoster()
        end
        SetCounterText("guild", OnlineCount("guild"))
    end

    local function UpdateFriendText()
        local mm = D()
        if mm.hideSocialText or not mm.social or not textFS.social then return end
        SetCounterText("social", OnlineCount("social"))
    end

    function inst:Refresh()
        ns.RefreshMicroMenuHider()
        ApplyCombatState()
        if not content:IsShown() or InCombatLockdown() then
            SyncStyleEvents()
            return
        end

        local mm = D()
        -- Materialise any buttons enabled after creation (options toggle).
        CreateFramesInner()
        SyncStyleEvents()
        if not next(frames) then return end
        if mm.hideSocialText then
            for _, fs in pairs(textFS) do fs:Hide() end
        else
            UpdateFriendText(); UpdateGuildText()
        end
        local ICON_SIZE = GetIconSize()
        local isVertical = barCtx.IsVertical()
        local totalWidth, totalHeight, prev = 0, 0, nil
        for _, key in ipairs(ns.GetMicroMenuOrder(mm, orderScratch)) do
            local frame = frames[key]
            -- Hide buttons toggled off after creation; lay out enabled ones.
            if frame and not MMButtonOn(mm, key) then
                frame:Hide()
                frame = nil
            end
            if frame then
                frame:Show()
                frame:SetSize(ICON_SIZE, ICON_SIZE)
                PaintIcon(key)
                if textFS[key] then
                    -- Plain button-center anchor: the block's Text Position offsets are the ONE positioning input (the wrapper injects them here).
                    textFS[key]:ClearAllPoints()
                    textFS[key]:SetPoint("CENTER", frame, "CENTER", 0, 0)
                end
                frame:ClearAllPoints()
                local spacing = mm.iconSpacing or MM_SPACING
                if prev and prev == frames.menu then spacing = mm.mainMenuSpacing or 4 end
                if not prev then
                    if isVertical then frame:SetPoint("TOP", content, "TOP", 0, 0)
                    else               frame:SetPoint("LEFT", content, "LEFT", 0, 0) end
                else
                    if isVertical then frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
                    else               frame:SetPoint("LEFT", prev, "RIGHT", spacing, 0) end
                end
                local prevSpacing = 0
                if prev then prevSpacing = spacing end
                if isVertical then
                    totalHeight = totalHeight + ICON_SIZE + prevSpacing
                    totalWidth  = max(totalWidth, ICON_SIZE)
                else
                    totalWidth  = totalWidth + ICON_SIZE + prevSpacing
                    totalHeight = max(totalHeight, ICON_SIZE)
                end
                prev = frame
            end
        end

        content:SetSize(max(totalWidth, 1), max(totalHeight, 1))

        MaybeRelayout(inst)
    end

    inst.eventFrame = MakeEventFrame(inst, function(self, event, unit)
        if event == "PORTRAITS_UPDATED" or event == "UNIT_PORTRAIT_UPDATE" then
            if portraitEvents and (event == "PORTRAITS_UPDATED" or unit == "player") then PaintIcon("char", true) end
        elseif event == "PLAYER_GUILD_UPDATE" then
            -- Joined, left or changed tabard: repaint the guild art. In combat the
            -- cleared memo lets the regen refresh repaint it instead.
            if guildEvents and icons.guild then
                icons.guild._edbWow = nil
                if not InCombatLockdown() then PaintIcon("guild") end
            end
        elseif event == 'GUILD_ROSTER_UPDATE' then
            UpdateGuildText()
        elseif event == 'BN_FRIEND_ACCOUNT_ONLINE'
            or event == 'BN_FRIEND_ACCOUNT_OFFLINE'
            or event == 'FRIENDLIST_UPDATE' then
            UpdateFriendText()
        elseif event == 'PET_BATTLE_OVER' or event == 'PET_BATTLE_CLOSE' then
            -- A pet battle hides two things, neither self-restoring: this block's
            -- buttons (rebuilt by the same ApplyCombatState+Refresh pair REGEN uses),
            -- and Blizzard's micro menu container if a block opted into hiding it --
            -- its hider runs off a CONSTANT state driver, so the snippet fires once and
            -- nothing re-asserts it; force makes the refresh re-push and re-register it.
            -- Both safe here: REGEN already calls Refresh in combat, and the hider defers its driver work until OOC.
            ApplyCombatState()
            self:Refresh()
            ns.RefreshMicroMenuHider(true)
        else
            -- REGEN x2 / PLAYER_ENTERING_WORLD: retry deferred button creation and re-apply the combat state.
            if event == "PLAYER_ENTERING_WORLD" then
                for _, icon in pairs(icons) do icon._edbWow = nil end
            end
            ApplyCombatState()
            self:Refresh()
        end
    end)

    CreateFramesInner()

    function inst:Enable()
        active = true
        content:Show()
        RegisterInstEvents(self)
        SyncStyleEvents()
        ns.RefreshMicroMenuHider()
        ApplyCombatState()
    end

    function inst:Disable()
        active, portraitEvents, guildEvents = false, false, false
        UnregisterInstEvents(self)
        content:Hide()
    end

    -- Refresh sizes content to the laid-out strip.
    function inst:GetAutoLength()
        return max(barCtx.IsVertical() and content:GetHeight() or content:GetWidth(), 50)
    end

    function inst:Destroy()
        self._dead = true
        for key, frame in pairs(frames) do
            ParkSecureFrame(frame, self.key .. "_" .. key)
        end
        content:Hide()
        -- The union recomputes without this instance's bar/block cfg (the
        -- engine removes the cfg before calling Destroy).
        ns.RefreshMicroMenuHider()
    end

    return inst
end
