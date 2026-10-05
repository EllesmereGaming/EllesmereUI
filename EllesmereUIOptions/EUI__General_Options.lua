if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI__General_Options.lua -- Global Settings module (CVar-based settings
--  shared by all EllesmereUI addons).
--
--  Default-application policy: EUI preferred defaults apply ONLY while
--  C_CVar.GetCVarInfo shows the CVar still at Blizzard's default (untouched
--  by player/other addon). Widgets always read the live CVar to stay in sync.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL      = "General"
local PAGE_FONTS       = "Fonts"     -- centralized fonts page; body lives in EUI_Fonts_Options.lua
local PAGE_TEXTURES    = "Textures"  -- centralized textures page; body lives in EUI_Textures_Options.lua
local PAGE_GLOWS       = "Glows"     -- centralized glow page; body lives in EUI_Glows_Options.lua
local PAGE_GAMEPAD     = "Gamepad"   -- controller settings page; body lives in EUI_Gamepad_Options.lua
local PAGE_STYLE       = "Style"     -- per-module EllesmereUI / Blizzard Style page; body lives in EUI_Style_Options.lua
local PAGE_COLORS      = "Colors"    -- the color half of the old "Fonts & Colors" page
local PAGE_PROFILES    = "Profiles"
local PAGE_PRESETS     = "Presets"   -- navigation tab over the presets subpage of the profiles page
local PAGE_WHATSNEW    = "Patch Notes"
local PAGE_LEGENDS     = "EUI Legends"

-- Profiles/Patch Notes are their own sidebar pages (single-page modules), not tabs under Global Settings. Keys match the sidebar buttons in EllesmereUI.lua.
local PROFILES_KEY     = "_EUIProfiles"
local PATCHNOTES_KEY   = "_EUIPatchNotes"

-- Standalone single-module builds rename the host addon to contain "Standalone". The What's New tab is suite-only, so it is never added to the page list there.
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil

-------------------------------------------------------------------------------
--  Shared CDM spell-layout export flow (full-profile AND per-addon export).
--  Asks to bundle the CDM spell layout (bar assignments + per-spell settings);
--  Yes opens the spec picker, then calls exportFn(includeCDM, cdmSpecs).
--  Exports ONLY on explicit "No" or a completed picker pick -- escaping
--  either popup produces NO export.
-------------------------------------------------------------------------------
function EllesmereUI.RunCDMSpellExportFlow(activeName, exportFn)
    local function pickThenExport()
        local specs = {}
        local sp = EllesmereUIDB and EllesmereUIDB.spellAssignments
            and EllesmereUIDB.spellAssignments.profiles
            and EllesmereUIDB.spellAssignments.profiles[activeName]
            and EllesmereUIDB.spellAssignments.profiles[activeName].specProfiles
        local n = EllesmereUI.IS_FOREVER and 0 or ((GetNumSpecializations and GetNumSpecializations()) or 0)
        for i = 1, n do
            local specID = GetSpecializationInfo and GetSpecializationInfo(i)
            if specID then
                local key = tostring(specID)
                local d = sp and sp[key]
                specs[#specs + 1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true or false,
                }
            end
        end
        -- WoW Forever: one row, the store key the player's class uses.
        if EllesmereUI.IS_FOREVER then
            local id = EllesmereUI.ForeverClassSpec(nil, EllesmereUI.SpecHasStringEntry, sp or {}, true)
            if id then
                local key = tostring(id)
                local d = sp and sp[key]
                specs[1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true or false,
                }
            end
        end
        EllesmereUI:ShowCDMSpecPickerPopup({
            title         = EllesmereUI.L("Export CDM Spells"),
            foreverAllKeys = true,
            subtitle      = EllesmereUI.L("This can't change which spells the user tracks in Blizzard's CDM.\nIt's recommended to also share your Blizzard CDM layout for any spec you choose here."),
            subtitleColor = { 1, 0.82, 0.2 },
            subtitleAtBottom = true,
            confirmText   = EllesmereUI.L("Export"),
            specs         = specs,
            onConfirm     = function(selectedSpecs) exportFn(true, selectedSpecs) end,
            onCancel      = function() end,  -- cancel / Esc / click-off: just close, NO export
        })
    end
    EllesmereUI:ShowConfirmPopup({
        title       = EllesmereUI.L("Include CDM Spell Layout?"),
        message     = EllesmereUI.L("Include your Cooldown Manager spell layout (which spells sit on which bars) plus all per-spell settings for any specs you choose."),
        confirmText = EllesmereUI.L("Yes"),
        cancelText  = EllesmereUI.L("No"),
        onConfirm   = function() pickThenExport() end,
        onCancel    = function() exportFn(false, nil) end,  -- "No": export WITHOUT layout
        onDismiss   = function() end,  -- Esc / click-off: just close, NO export
    })
end

-------------------------------------------------------------------------------
--  EUI LEGENDS content.
--  The block between the GENERATED DONORS markers is written by the
--  update-donors.ps1 dev tool from the internal donor list: change the list
--  and rerun the tool instead of editing the block by hand.
--    season      : "spring" / "summer" / "fall" / "winter" (page accents)
--    seasonYear  : shown after the season name over the podium
--    topSeasonal : rank-ordered top three donors this season (1st, 2nd, 3rd)
--    donors      : the all-time donor wall, numbered in this order
--  The staff table below the block is edited by hand:
--    staff       : grouped team sections ({ group, members } tables)
-------------------------------------------------------------------------------
-- BEGIN GENERATED DONORS
EllesmereUI._LEGENDS = {
    season      = "fall",
    seasonYear  = "2026",
    topSeasonal = { "Khardi", "Ani", "Keato03" },
    donors = {
        "Thias", "StickyMittens", "Xeno", "Delasteve",
        "Toxik", "Lily", "Pelleas", "Kulia",
        "GamingGrammers", "Khardi", "Cartridgebros", "Lurn",
        "Ani", "fizzle_crunk", "Tzahal", "Venalis",
        "Natasi", "Quiim", "Keato03", "Capa",
        "e_luvin", "ccpoppin1", "Arjax", "Excelvior",
        "Marple_V", "shy_x00", "Ferniss",
    },
}
-- END GENERATED DONORS
EllesmereUI._LEGENDS.staff = {
    { group = "Support Leads", members = {
        "Burne", "Mudd", "Kulia", "Dookie", "Lily",
    } },
    { group = "Support Team", members = {
        "Mantis", "Kned", "Zylann", "Svart", "Meza",
        "Tzahal", "Spaze", "Terrible", "Mohkan", "Groukh",
        "Freschi", "Twilight", "Bierbauch",
    } },
    { group = "Major Bugfix/Feature Contributors", members = {
        "Glyalith", "Derek", "JuJu", "Kneeul", "Kiri",
        "Stoley", "Stormspren", "Xanax", "DNL",
        "Svart", "Nnoggie",
        "Filpet96", "Snsei987", "JensBaumannDev", "Absol3m",
        "SamJin98", "RedAces", "liamcooper", "uNBEx", "natty",
        "Ricoder92", "0x963D", "Barbiero", "Lyrex", "Delasteve",
        "andybergon", "TF0rd",
    } },
    { group = "Multi-language Support Contributors", members = {
        "LoChinAn", "Crazyyoungs", "Barbiero", "Dlarge", "labrie75",
        "tenngoxars", "Shiyan66666", "Absol3m",
    } },
}

-- Seasonal accents: a palette (first entry leads, tinting the season name) and
-- the drift of the small particles around the hero head and podium. dir -1
-- falls, dir 1 rises; size/dur are {min, max} ranges; spin is total degrees.
EllesmereUI._LEGENDS_SEASONS = {
    spring = { name = "Spring", dir = -1, size = { 4, 7 }, dur = { 11, 15 }, spin = 200, alpha = 0.50,
        colors = { { 1.00, 0.70, 0.82 }, { 0.98, 0.86, 0.91 }, { 0.66, 0.88, 0.55 } } },
    summer = { name = "Summer", dir = 1, size = { 3, 4 }, dur = { 8, 11 }, spin = 45, alpha = 0.60,
        colors = { { 1.00, 0.84, 0.34 }, { 1.00, 0.64, 0.40 }, { 1.00, 0.93, 0.62 } } },
    fall   = { name = "Fall", dir = -1, size = { 5, 8 }, dur = { 10, 14 }, spin = 320, alpha = 0.55,
        colors = { { 0.96, 0.58, 0.20 }, { 0.84, 0.34, 0.15 }, { 0.98, 0.78, 0.30 }, { 0.70, 0.42, 0.18 } } },
    winter = { name = "Winter", dir = -1, size = { 3, 5 }, dur = { 12, 17 }, spin = 90, alpha = 0.60,
        colors = { { 0.72, 0.86, 1.00 }, { 0.90, 0.95, 1.00 }, { 0.62, 0.74, 0.95 } } },
}

-- Weighted pick for the options header's thanks line. Ranking = this season's
-- podium, then the rest of the all-time wall (so an empty podium falls back to
-- the all-time order). Slots 1-3 carry 50/25/15; everyone after shares 10.
local _thanksRanked, _thanksSeen = {}, {}
function EllesmereUI._PickLegendsThanks()
    local data = EllesmereUI._LEGENDS
    if not data then return nil end
    local ranked, seen = _thanksRanked, _thanksSeen
    wipe(ranked); wipe(seen)
    local top, donors = data.topSeasonal or {}, data.donors or {}
    for i = 1, #top do
        local n = top[i]
        if n and n ~= "" and not seen[n] then seen[n] = true; ranked[#ranked + 1] = n end
    end
    for i = 1, #donors do
        local n = donors[i]
        if n and n ~= "" and not seen[n] then seen[n] = true; ranked[#ranked + 1] = n end
    end
    local count = #ranked
    if count == 0 then return nil end
    local restW = count > 3 and (10 / (count - 3)) or 0
    local total = 0
    for i = 1, count do
        total = total + ((i == 1 and 50) or (i == 2 and 25) or (i == 3 and 15) or restW)
    end
    local roll = math.random() * total
    for i = 1, count do
        roll = roll - ((i == 1 and 50) or (i == 2 and 25) or (i == 3 and 15) or restW)
        if roll <= 0 then return ranked[i] end
    end
    return ranked[count]
end

-- Language-picker font: each entry is entirely one script (the CJK stock fonts
-- also cover the trailing "(Korean)"-style Latin text), so a plain per-entry
-- font from the locale system's own glyph table beats a multi-script family.
local function LP_FontFor(locale)
    local fn = EllesmereUI.LocaleGlyphFont
    return (fn and fn(locale)) or (EllesmereUI.MEDIA_PATH .. "fonts\\Expressway.TTF")
end

-------------------------------------------------------------------------------
--  Patch-notes content for the What's New page (newest first). Entry `nav`
--  deep-links via NavigateToElementSettings(module, page, section, preSelect, highlight).
-------------------------------------------------------------------------------
EllesmereUI._WHATSNEW_PATCHES = {
    {
        version = "9.3.8",
        mini = true,
        fixes = {
            { module = "AuraBuff Reminders", text = "Reminders now follow Where to Show in Island Expeditions, Torghast and other scenarios, which get their own Scenario entry, and housing plots now count as Open World." },
            { forever = true, module = "Bags", text = "The keyring button on the bag bar opens your keyring again instead of the bags." },
            { module = "Chat", text = "Chat placed near the bottom or left edge of the screen no longer shifts up and to the right after logging in or opening Edit Mode." },
            { module = "Mythic+ Tools", text = "Targeted Spell Bars now follow Where to Show in scenarios, which get their own Scenario entry, and housing plots now count as Open World." },
            { module = "Localization", text = "Brazilian Portuguese translation updated for the latest options." },
        },
    },
    {
        version = "9.3.7",
        features = {
            {
                module = "Action Bars",
                title  = "Quest XP Overlay",
                desc   = "The XP bar can show the XP from the quests in your log ahead of its fill, completed quests in green and the rest in gold",
                nav    = { module = "EllesmereUIActionBars", page = "XP Bar",
                           section = "DISPLAY", highlight = "Quest XP Overlay" },
            },
            {
                forever = true,
                module = "AuraBuff Reminders",
                title  = "Raid Buffs",
                desc   = "Mark of the Wild, Fortitude, Arcane Intellect and Battle Shout get their own Raid Buffs section: any rank counts, and a click buffs whoever needs it",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "RAID BUFFS", highlight = "Where to Show" },
            },
            {
                module = "Blizzard Skins+",
                title  = "Player Buffs on Tooltips",
                desc   = "Hovering a player can show their buffs as icons on the tooltip, with position, size and per-row settings",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups",
                           section = "BLIZZARD TOOLTIP", highlight = "Show Player Buffs" },
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Loot Feed Styles",
                desc   = "The loot feed now uses a new Accent Bar look, with Icon Tray, Loot Toast and the old Box look to pick from, and a live preview on the Loot page",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Loot",
                           section = "LOOT FEED", highlight = "Style" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Auto Uprank Spells",
                desc   = "Learning a new spell rank swaps it onto your action bars in place of the old rank",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "SPELL RANKS", highlight = "Auto Uprank Spells" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Flight Timer Preview",
                desc   = "The Travel page shows the flight timer flying a sample route on a loop, so every setting shows as you change it",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Travel" } or nil,
            },
            {
                module = "Nameplates",
                title  = "Debuff Border Coloring",
                desc   = "Debuff Based Nameplate Coloring (formerly Debuff Colors) can color an enemy plate's border instead of its health bar, and thicken it while it shows",
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "DEBUFF BASED NAMEPLATE COLORING", highlight = "Debuff Coloring" },
            },
            {
                module = "QoL",
                title  = "Auto Select Single Gossip",
                desc   = "Talking to an NPC with only one dialog option picks it for you, unless they have a quest for you",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "GENERAL", highlight = "Auto Select Single Gossip" },
            },
            {
                -- Ignore Low Level Quests sits in Auto Accept Quests' cog.
                module = "Quest Tracker",
                title  = "Ignore Low Level Quests",
                desc   = "Auto Accept can leave low level quests for you to pick up yourself",
                nav    = { module = "EllesmereUIQuestTracker", page = "Quest Tracker",
                           section = "EXTRAS", highlight = "Auto Accept Quests" },
            },
            {
                module = "Raid Frames",
                title  = "Down and then Right",
                desc   = "Group Growth can lay raid groups out in a grid, two groups down each column before the next column starts to the right",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "LAYOUT", highlight = "Group Growth" },
            },
        },
        fixes = {
            { forever = true, module = "Action Bars", text = "Fixed a niche issue that could cause cooldown errors from Blizzard's hidden action buttons when entering combat." },
            { forever = true, module = "AuraBuff Reminders", text = "Custom spell reminders now count every rank of the spell and its group version, so a higher rank no longer leaves the reminder showing." },
            { module = "Chat", text = "Chat and its input bar no longer blink or jump when Edit Mode re-applies its layout (at login, on level-ups and on layout switches), which could also make right-clicks on names do nothing or pick the wrong player." },
            { module = "Cooldown Manager", text = "Icons no longer show the previous spell's keybind after you add a spell in Blizzard's Cooldown Manager settings." },
            { module = "Minimap", text = "Minimap buttons on a round minimap now sit around the edge of the circle instead of in a straight row beside it." },
            { module = "Nameplates", text = "Debuff coloring changes now apply as you make them, without an Apply Coloring button, and the coloring uses less CPU." },
            { module = "Nameplates", text = "Debuff coloring no longer uses the previous profile's debuff lists after a spec profile switches profiles at login." },
            { module = "QoL", text = "Self Combat Text's Stagger Hits now spaces out hits that land together so none hides another, and Straight text rises in a straight line instead of drifting side to side." },
            { module = "Raid Frames", text = "Debuff Manager filters now dim when another indicator already shows those debuffs, and hovering one names that indicator." },
            { forever = true, module = "Resource Bars & Unit Frames", text = "Blizzard's cast bar no longer comes back next to ours after leveling up in combat." },
            { module = "Unlock Mode", text = "Moving or resizing Blizzard Style unit frames no longer causes errors." },
            { module = "Localization", text = "Traditional Chinese translation updated for the latest options, and Unlock Mode's size-match, anchor and override messages can now be translated." },
        },
    },
    {
        version = "9.3.6",
        mini = true,
        fixes = {
            { module = "Raid Frames", text = "Click-cast bindings with Enable Dynamic Rez, HoverCast keys holding both a friendly and an enemy spell, and HoverCast Dynamic Rez keys work again." },
        },
    },
    {
        version = "9.3.5",
        heroes = {
            {
                module = "Action Bars",
                title  = "XP Bar Overhaul",
                desc   = "The XP bar gets its own tab with frame styles, gradient and animated fills, divider ticks and its own background and rested colors. Up to seven texts can sit around or inside it, each mixing XP, rested, quest XP, level, XP per hour and time to level in the order you drag them.",
                nav    = { module = "EllesmereUIActionBars", page = "XP Bar",
                           section = "CORE", highlight = "XP Bar Style" },
            },
            {
                module = "Nameplates",
                title  = "Debuff Colors",
                desc   = "Enemy health bars can take a color while your chosen debuffs are on them: up to ten per class in priority order, plus combo colors for two to four debuffs at once. Only your own class's list ever loads, and Apply Coloring sends your changes to the plates.",
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "DEBUFF BASED NAMEPLATE COLORING", highlight = "Debuff Coloring" },
            },
            {
                module = "Bags",
                title  = "List View",
                desc   = "Bags and the bank can show items as a list with sortable, resizable columns, adjustable rows and an Upgrade Track column. Drag a corner to resize the bags or bank, and drop items picked up elsewhere anywhere on the empty bag space.",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "LIST VIEW", highlight = "Row Height" },
            },
            {
                module = "QoL",
                title  = "Self Combat Text",
                desc   = "Shows your damage taken, healing, avoids and entering or leaving combat as scrolling text above the player frame in place of Blizzard's combat text, with its own font, colors and animation; move it in Unlock Mode.",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "SELF COMBAT TEXT", highlight = "Self Combat Text" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Modifier/Target Paging",
                desc   = "Shift, Ctrl, Alt, Friendly and Hostile Target paging sit behind one toggle that turns them off without losing your picks",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "PAGING", highlight = "Modifier/Target Paging" },
            },
            {
                module = "Action Bars",
                title  = "Show Equipped Item Color",
                desc   = "Buttons holding an equipped item, such as a trinket, can show a border in its rarity color (on by default in WoW Forever)",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "ICON EFFECTS", highlight = "Show Equipped Item Color" },
            },
            {
                forever = true,
                module = "Action Bars",
                title  = "Forever XP Bar Style",
                desc   = "The XP bar can wear the bronze border of the chat and Damage Meters windows",
                nav    = { module = "EllesmereUIActionBars", page = "XP Bar",
                           section = "CORE", highlight = "XP Bar Style" },
            },
            {
                module = "Bags",
                title  = "Allow Windows Over Bags",
                desc   = "Other windows, like the Auction House, can now come in front of the bags; turn it off to keep the bags on top, as before",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "LAYOUT", highlight = "Allow Windows Over Bags" },
            },
            {
                forever = true,
                module = "Bags",
                title  = "Special Bags",
                desc   = "Quivers, ammo pouches and soul, herb and enchanting bags get their own OneBag sections and a Special Bags category",
                nav    = { module = "EllesmereUIBags", page = "Bags" },
            },
            {
                module = "Blizzard Skins+",
                title  = "Character Sheet Blizz Default",
                desc   = "Blizz Default keeps Blizzard's sheet with the EllesmereUI stats, item text and socket panel, and a new Off leaves the sheet untouched",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
            {
                module = "Blizzard Skins+",
                title  = "Chat Bubbles",
                desc   = "Chat Bubbles moved here from Chat, with their own font and outline, optional speaker names and a live preview",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Chat Bubbles",
                           section = "DISPLAY", highlight = "Enable Chat Bubbles Customization" },
            },
            {
                -- Texture and height sit in Show Health Strip's cog.
                module = "Blizzard Skins+",
                title  = "Health Strip Texture and Height",
                desc   = "Show Health Strip's cog sets the tooltip health strip's texture and height",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups",
                           section = "BLIZZARD TOOLTIP", highlight = "Show Health Strip" },
            },
            {
                module = "Blizzard Skins+",
                title  = "Inspect Sheet Enchant Text",
                desc   = "The inspect sheet can show enchant names as text like the character sheet, picked from a new Enchants dropdown on both sheets",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "INSPECT SHEET", highlight = "Enchants" },
            },
            {
                module = "Blizzard Skins+",
                title  = "Stat Item Highlight",
                desc   = "Hovering a secondary or tertiary stat on the character sheet can glow the equipped items that grant it",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "STAT DISPLAY", highlight = "Secondary/Tertiary Highlights" },
            },
            {
                forever = true,
                module = "Blizzard Skins+",
                title  = "New Window Skins",
                desc   = "The Looking For Group, Progress Legacy, micro menu and bag bar windows take the EllesmereUI look, each with its own Window Skins card",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
            {
                -- The effect is picked in each spell's menu on the bars: page-only.
                module = "Cooldown Manager",
                title  = "Glow On Cooldown",
                desc   = "Glow (On CD) marks a spell for its whole cooldown, by default with Blackout, a black fill under the swipe that is also a Glow Style and Bar Glow",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Cooldown Manager",
                title  = "Bar Glow Conditions",
                desc   = "A Bar Glow can also require a second buff to be active or missing, be limited to one hero talent tree, and be duplicated",
                nav    = { module = "EllesmereUICooldownManager", page = "Bar Glows" },
            },
            {
                -- The effect is picked in each spell's menu on the bars: page-only.
                module = "Cooldown Manager",
                title  = "Hidden Until Usable",
                desc   = "A Cooldown State Effect that hides a spell until it is usable, so procs like Overpower and Victory Rush show only when they can be pressed",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                -- Added from a bar's Add menu: page-only.
                module = "Cooldown Manager",
                title  = "Empty Slot",
                desc   = "CD and utility bars can hold empty slots to space their icons into groups (Add menu > Empty Slot)",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                -- A slash command: nothing to open.
                module = "Cooldown Manager",
                title  = "/cd Command",
                desc   = "Type /cd to open or close Blizzard's Cooldown Manager settings",
            },
            {
                module = "Data Bars",
                title  = "Blizzard Icon Style",
                desc   = "Bags, gold, item level, location, coordinates, durability, travel, audio, spec, professions and the micro menu can show the game's own icons",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Data Bars",
                title  = "Text Display Options",
                desc   = "The XP / Reputation bar can show a percentage or values, with or without level or faction, and profession blocks can show skill values",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Data Bars",
                title  = "Micro Menu Order",
                desc   = "Drag the entries in Menu Elements to set the micro menu's button order",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                forever = true,
                module = "Data Bars",
                title  = "Class Resources",
                desc   = "A new block counts your ammo, thrown weapon and class reagents; right-click it to choose which ones show",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                forever = true,
                module = "Data Bars",
                title  = "First Aid",
                desc   = "The secondary professions block also shows First Aid",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                forever = true,
                module = "Data Bars",
                title  = "Professions and Legacy Buttons",
                desc   = "The micro menu can show the Professions and Legacy buttons; turn them on in Menu Elements",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- The Loot page exists only on WoW Forever.
                forever = true,
                module = "Forever Essentials",
                title  = "Loot Feed",
                desc   = "Shows what you loot and gain (items, money, reputation, currencies and skill ups) as short rows that fade out",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Loot" } or nil,
            },
            {
                module = "General",
                title  = "Uninstall EUI",
                desc   = "A new button on Global Settings puts back the game settings EUI changed, then turns EUI off and reloads; turning a module off puts back its own",
                nav    = { module = "_EUIGlobal", page = "General" },
            },
            {
                -- Static card: the slider sits in the options window's header, not on a page.
                module = "General",
                title  = "Window Scale",
                desc   = "The options window has a Window Scale slider in its top corner that resizes it in smooth 5% steps; Shift + mouse wheel over it works too",
            },
            {
                module = "General",
                title  = "Style Picks",
                desc   = "The Style page sets each look's modules from a dropdown under its card, and Apply Styles applies every change with one reload",
                nav    = { module = "_EUIGlobal", page = "Style" },
            },
            {
                module = "General",
                title  = "Per-Section Color Sources",
                desc   = "Class, Power and Class Resource colors each choose their own Apply to All Profiles and Pull Colors From",
                nav    = { module = "_EUIGlobal", page = "Colors" },
            },
            {
                -- Static card: nothing to open; other addons' pages load in sections of their own.
                module = "General",
                title  = "Addon Plugins",
                desc   = "Other addons can add their own sections to the settings panel, and can no longer change or break EllesmereUI's own pages",
            },
            {
                module = "Minimap",
                title  = "Coordinate Precision",
                desc   = "The Show Coordinates cog sets how many decimal places the coordinates show",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap",
                           section = "TEXT", highlight = "Show Coordinates" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Per-Bar Spell Target",
                desc   = "Show Spell Target now sits in the Target and Focus Cast Bar sections, so the spell target can show on one bar and not the other",
                nav    = { module = "EllesmereUIMythicTimer", page = "Target/Focus Bars",
                           section = "TARGET CAST BAR", highlight = "Show Spell Target" },
            },
            {
                -- Add Text Slot is the list's last row, so the link always finds it.
                module = "Nameplates",
                title  = "Core Text Positions",
                desc   = "Core Text Positions lists only the texts you use, with Add Text Slot, a menu on each text's name to move it, and Remove in its dropdown",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE TEXT POSITIONS", highlight = "Add Text Slot" },
            },
            {
                -- The section exists while a text is assigned; the highlight lands on its first half.
                module = "Nameplates",
                title  = "Core Text Coloring",
                desc   = "Each text gets Custom, Hostility / Class or Level Difficulty coloring in its own Core Text Coloring section, with Level | Name parts colored apart",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE TEXT COLORING", highlight = "Text Coloring" },
            },
            {
                module = "Nameplates",
                title  = "Core Positions Checklists",
                desc   = "Each Core Positions slot is a checklist: Rare and Quest switch separately, and Debuffs with CC or Rare/Quest with Faction can share a slot",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE POSITIONS", highlight = "Top" },
            },
            {
                -- Placement sits in the Absorb Style row's Absorb Settings cog.
                module = "Nameplates",
                title  = "Shield Placement",
                desc   = "The Absorb Settings cog picks where shields draw: Overlay, Overlay Reverse, From Right Edge or From Left Edge",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "STYLE", highlight = "Absorb Style" },
            },
            {
                module = "Nameplates",
                title  = "Show All Enemy Buffs",
                desc   = "The Enemy Buff Filter has a Show All choice that shows every buff on enemy nameplates",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "EXTRA AURA OPTIONS", highlight = "Enemy Buff Filter" },
            },
            {
                -- The separator sits in the Icon Borders cog, built while Border is Custom.
                module = "Nameplates",
                title  = "Vertical Separator",
                desc   = "Draws a divider in your custom border's style between the cast bar and a spell icon that is part of the bar",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "STYLE", highlight = "Custom Border Style" },
            },
            {
                -- WoW Forever, a static card on retail.
                forever = true,
                module = "Nameplates",
                title  = "Threat Gap",
                desc   = "The Threat % text can show the flat threat lead on your target's plate, green when you lead and blue when someone else does",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Threat",
                           section = "THREAT % TEXT", highlight = "Show on Nameplates" } or nil,
            },
            {
                module = "Party Mode",
                title  = "Spinning Party and Raid Frames",
                desc   = "Spinning can now orbit your party and raid frames, which snap back into place for every fight",
                nav    = { module = "EllesmereUIPartyMode", page = "Party Mode",
                           section = "PARTY MODE", highlight = "Spinning" },
            },
            {
                module = "QoL",
                title  = "Bonus Roll Confirmation",
                desc   = "Asks before you spend a bonus roll and shows your loot specialization, with an option to confirm Pass too",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "UI", highlight = "Bonus Roll Confirmation" },
            },
            {
                module = "QoL",
                title  = "Environment Ping",
                desc   = "While the key is held, left-clicking the world pings the spot under your cursor instead of a unit",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "EXTRAS", highlight = "Environment Ping" },
            },
            {
                -- The stat catalog shows only on WoW Forever.
                forever = true,
                module = "QoL",
                title  = "Character Stats Display",
                desc   = "The Secondary Stat Display shows your character pane's stats, from attack and spell power to crit, haste, hit, regen, armor and resistances",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQoL", page = "QoL",
                           section = "EXTRAS", highlight = "Secondary Stat Display" } or nil,
            },
            {
                module = "Raid Frames",
                title  = "Clear Stuck Spell Targeting",
                desc   = "HoverCast clears a spell left waiting for a target before it casts, so your next press goes through; on by default",
                nav    = { module = "EllesmereUIRaidFrames", page = "HoverCast" },
            },
            {
                module = "Raid Frames",
                title  = "Combat Rez Items",
                desc   = "Classes without a battle rez use an Emergency Soul Link from their bags through Dynamic Rez and Smart Rez on a dead ally in combat",
                nav    = { module = "EllesmereUIRaidFrames", page = "HoverCast" },
            },
            {
                module = "Resource Bars",
                title  = "Health Bar Absorbs",
                desc   = "The Health Bar can show damage and heal absorbs, each with its own style, color and opacity, and a max health reduction overlay",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "HEALTH BAR", highlight = "Absorb Style" },
            },
            {
                module = "Resource Bars",
                title  = "Power Bar Spenders",
                desc   = "The Power Bar can change color while a spell you choose is ready to cast, set per entry under Threshold Settings",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "POWER BAR", highlight = "Threshold Settings" },
            },
            {
                module = "Resource Bars",
                title  = "Cast Bar Upgrades",
                desc   = "The cast bar can turn gray while your target is out of range, and its spell icon can be resized and offset to sit beside the bar",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar",
                           section = "LAYOUT", highlight = "Show Spell Icon" },
            },
            {
                module = "Resource Bars",
                title  = "Expand Extra Y Offset",
                desc   = "Expand Power Bar if No Resource gains an Extra Y Offset, so the expanded bar can cover a gap left by the class resource",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "BAR DISPLAY", highlight = "Expand Power Bar if No Resource" },
            },
            {
                module = "Resource Bars",
                title  = "Per-Bar Texture and Strata",
                desc   = "The Texture and Frame Strata cogs give the health and power bars their own texture and strata, or Match Main to follow the row",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "BAR DISPLAY", highlight = "Frame Strata" },
            },
            {
                module = "Unit & Raid Frames",
                title  = "Overlay Reverse (Full)",
                desc   = "A new shield Placement shows a shield larger than current health from the start of the bar",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "ABSORBS AND HEALS", highlight = "Absorb Style",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- Mirror Portrait sits in the portrait cog.
                module = "Unit Frames",
                title  = "Portrait Mirroring",
                desc   = "Mirror Portrait now also turns 3D portraits of playable races; in 2D it flips playable-race portraits only (class art always flips)",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "PORTRAIT", highlight = "Portrait Mode",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "Unit Frames",
                title  = "Focus Aura Borders",
                desc   = "The Focus frame's Buffs and Debuffs section gets Border Style, Border Size, color and border options, like Player and Target",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Border Style",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("focus"); EllesmereUI._pendingUnitSelect = "focus" end },
            },
            {
                module = "Unit Frames",
                title  = "Boss Frame Borders",
                desc   = "Boss frames gain Mirror Portrait, a Vertical Border Separator, a Power Bar Seam and Border Above Effects for aura borders",
                nav    = { module = "EllesmereUIUnitFrames", page = "Boss Frames" },
            },
            {
                module = "Unit Frames",
                title  = "Mini Frame Looks",
                desc   = "Target of Target, Focus Target and Pet choose which main frame they copy their look from, and the Target of Target portrait can be mirrored",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "An equipped item dragged onto or off a bar now shows or drops its border right away instead of after a mouseover." },
            { module = "Action Bars", text = "The XP, reputation and House Favor bars' text now always shows your chosen font, including in the standalone Action Bars download and right after logging in to a character whose spec profile uses another font." },
            { module = "Action Bars", text = "Switching from Blizzard's XP/Rep bars back to EllesmereUI's now offers a reload popup instead of a chat message." },
            { module = "Action Bars", text = "The live preview shows Action Bar 1's paging arrows while they are turned on." },
            { forever = true, module = "Action Bars", text = "In the WoW Forever style, our own XP and reputation bars no longer draw Blizzard's segment marks; turn on Show Dividers to mark them." },
            { module = "Bags", text = "Merged duplicate items now split into their stacks while a vendor is open, as at the mailbox, auction house and bank, since selling one only ever sold a single stack." },
            { module = "Bags", text = "Equipped bag icons now update after swapping a bag." },
            { forever = true, module = "Bags", text = "OneBag Sort and Randomize no longer try to move items into a quiver, ammo pouch or other special bag, or pull ammo out of it." },
            { module = "Blizzard Skins+", text = "Blizz UI Enhanced is now called Blizzard Skins+, and its tabs are now Window Skins and Skyriding." },
            { module = "Blizzard Skins+", text = "Reset now also restores the Character Sheet, Inspect, Merchant and tooltip options." },
            { module = "Blizzard Skins+", text = "The Great Vault is no longer reskinned while Disable Window Skins is on." },
            { module = "Blizzard Skins+", text = "The equipment set icon picker is no longer dimmed and unclickable on the EllesmereUI and Modern character sheets." },
            { module = "Blizzard Skins+", text = "Inspect sheet enchant tooltips no longer pop up on its other tabs or while enchants are hidden." },
            { module = "Blizzard Skins+", text = "Character sheet stat titles no longer show a custom color you switched off when the sheet first opens." },
            { forever = true, module = "Blizzard Skins+", text = "Blizzard Style and Classic WoW UI now keep the item text beside the character sheet's slots, as WoW Forever does." },
            { forever = true, module = "Blizzard Skins+", text = "The inspect sheet shows each item's enchant, as the character sheet does." },
            { forever = true, module = "Blizzard Skins+", text = "With the Gamepad interface style, the window, popup and tooltip skins step aside, so navigating bags and windows with a controller no longer causes blocked-action errors." },
            { module = "Chat", text = "Idle fade now wakes only for chat in the tab you are looking at (or an open undocked window), and chat no longer fades while your mouse is over it after a new message arrives." },
            { module = "Chat", text = "The Copy Chat window now opens at the newest lines instead of the oldest." },
            { module = "Cooldown Manager", text = "CD Ready and Glow (On CD) glows no longer cover a live proc or Active State Glow (also on trinkets, potions and spells added by Spell ID), and come back the moment it ends." },
            { module = "Cooldown Manager", text = "Cooldown State Effects now work on racials that Blizzard's Cooldown Manager tracks itself." },
            { module = "Cooldown Manager", text = "Bar Glows on target debuffs (such as Freezing) light up right away, and At Stacks glows follow every stack change." },
            { module = "Cooldown Manager", text = "The per-spell settings menu no longer cuts off its last row." },
            { module = "Cooldown Manager", text = "A tracked trinket's buff placed on another bar now stays there after a reload or relog (add it to the bar once more if it already moved back)." },
            { module = "Cooldown Manager", text = "Custom spells from a talent you've swapped away from no longer stay on your bars, and return to their spot when you pick the talent again." },
            { module = "Data Bars", text = "Profession blocks catch up on skill changes made in combat once it ends, and a block with no profession no longer leaves a gap on an auto-sized bar." },
            { forever = true, module = "Data Bars", text = "The micro menu no longer shows Achievements, PvP, Housing, Adventure Guide and Shop buttons, which do not exist there." },
            { module = "General", text = "Clicking Optimize My FPS and Graphics in combat no longer offers a Restore when nothing was changed." },
            { module = "General", text = "Popups that close when you click outside them (profile sync, Add Bar in Player Aura Bars, Add New in the Buff and Debuff Managers, Create Custom Buff Manager) now also do so the first time they open." },
            { module = "General", text = "Confirmation popups shown before the options window was opened (for example when leaving Unlock Mode right after a reload) are no longer drawn too large." },
            { module = "General", text = "Searching the options for range now finds Target Distance Text and the nameplate Distance to Target Text." },
            { module = "General", text = "The Auto Expand Less Common Settings and Enable Tutorial Tips options are gone: less common settings always start collapsed, and video guide badges show until you click them." },
            { forever = true, module = "General", text = "The reload popup that /rl and reload-needing settings open now also reloads when you press Enter." },
            { module = "Minimap", text = "The Addon Buttons flyout now centers its buttons in the same square boxes as the button row (Button Backgrounds on) instead of gold rings." },
            { forever = true, module = "Minimap", text = "With the Gamepad interface style, the Friends button is hidden, since the game blocks opening the friends list from it." },
            { module = "Nameplates", text = "Shields on enemy nameplates no longer shrink the health bar in combat; they draw over it the way the unit frames do." },
            { module = "Nameplates", text = "Solid custom borders and the cast lockout icon's border no longer lose sides or flicker when Scale Target or Scale Casting Nameplate is above 100%." },
            { module = "Nameplates", text = "Custom Border on Spell Icon no longer draws a second border inside the cast bar while the icon is part of the bar." },
            { module = "Nameplates", text = "Color Name by Reaction is now the name's Hostility / Class coloring, which also shows enemy players in their class colors." },
            { module = "Nameplates", text = "In the options preview, text and raid markers draw above the auras, and the name sits in front of or behind them as its Strata setting does on real nameplates." },
            { forever = true, module = "Nameplates", text = "Enemy nameplates now show every buff by default (Enemy Buff Filter: Show All); pick Important or Only Dispellable to narrow them again." },
            { module = "Player Aura Bars", text = "Bars sorted by Expiration or Name now sort by that alone instead of putting your own auras first, and the options preview shows the icons in the chosen order." },
            { module = "QoL", text = "Announce Instance Reset no longer tells a party the reset failed; a party reset always succeeds." },
            { module = "QoL", text = "The Raid Tools marker rows now read Target Markers and World Markers, so translated clients no longer label the ground marker row just World." },
            { module = "Raid Frames", text = "HoverCast on macOS now takes Command (Cmd) as a modifier, so Command bindings, including Command-clicks on your frames, work." },
            { module = "Resource Bars", text = "Tip of the Spear's stack count now always matches the buff on every class resource display (it could read a stack low after some spenders)." },
            { module = "Resource Bars", text = "The Class Resource Bar now fills in right away when a zone change alters its maximum, instead of staying empty until your resource next changes." },
            { module = "Unit & Raid Frames", text = "Buff and debuff borders now line up with their icons at UI scales that are not pixel perfect." },
            { module = "Unit Frames", text = "The power bar seam no longer overlaps the portrait separator where they meet, and Color Custom Borders also recolors the power and portrait separators." },
            { module = "Unit Frames", text = "Show When Health Missing now works when the class resource bar is locked to the player frame." },
            { module = "Unit Frames", text = "The options preview follows Power Fill Opacity with a bar texture, shows the Target of Target, Focus Target and Pet frames' own Border Size, and clicking its heal absorb and class resource parts opens their settings." },
            { forever = true, module = "Unit Frames", text = "Threat % shows on the target frame only by default (tick Show on Focus in its cog to keep it on the focus frame too), and can sit outside the target and focus frames (Outside Right / Outside Left), clear of the portrait." },
            { module = "Unlock Mode", text = "Resizing the Battle Res, Bloodlust, cursor ring and Flight Timer displays keeps them under their mover instead of jumping back." },
            { module = "Unlock Mode", text = "The fixed tooltip position, Battle Res, Bloodlust, Mythic+ Timer, Targeted Spell Bars and Target / Focus bars no longer keep a dragged position after Exit Without Saving." },
            { module = "Unlock Mode", text = "Element Options on the XP, reputation, House Favor, micro menu and bag bars now opens their own settings instead of the Bar Display page." },
            { module = "Localization", text = "German, Korean, Traditional Chinese and Brazilian Portuguese translations updated for the latest options." },
        },
    },
    {
        version = "9.3.4",
        heroes = {
            {
                module = "Nameplates",
                title  = "Target of Target and Bottom Text",
                desc   = "Any Core Text Position can now show the name of whoever the enemy is targeting, class colored for players. New Bottom Left and Bottom Right text slots sit under the health bar and drop below the cast bar while the enemy casts.",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE TEXT POSITIONS", highlight = "Bottom Left Text" },
            },
            {
                -- Static card: it happens at first install, nothing to open.
                forever = true,
                module = "General",
                title  = "First Install Keeps Your Layout",
                desc   = "A fresh install now starts from where your Blizzard frames already are, including the experience bar, micro menu and bags, with the gryphons at the outer ends of that row, instead of a fixed EllesmereUI layout. If you already use EllesmereUI, your current layout stays exactly as it is.",
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Micro Menu and Bag Bar End Caps",
                desc   = "The micro menu and bag bar can show end caps like the action bars, and a fresh install moves Action Bar 1's end caps to the outer ends of any bars placed directly beside it",
                nav    = { module = "EllesmereUIActionBars", page = "Menu, Bags & Rep Bars",
                           section = "MICRO MENU & BAGS", highlight = "Micro Menu End Caps" },
            },
            {
                -- Static card: picked from a window's meter type menu, no options row.
                forever = true,
                module = "Damage Meters",
                title  = "Threat Meter Type",
                desc   = "Windows can show Forever Essentials' threat list as a Threat meter type, in the window's own style and with the Threat page's list settings",
            },
            {
                -- Icon Size sits in the Size slider's cog.
                module = "Minimap",
                title  = "Icon Size",
                desc   = "The Size setting's cog can scale the icons on the map, like Edit Mode's Icon Size",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap",
                           section = "DISPLAY", highlight = "Size" },
            },
            {
                module = "Raid Frames",
                title  = "Level Text",
                desc   = "Level Position can show each member's level in front of their name or on its own spot (WoW Forever shows it by default)",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "TEXT DISPLAY", highlight = "Level Position" },
            },
            {
                -- The Missing Buffs row exists only on WoW Forever.
                forever = true,
                module = "Raid Frames",
                title  = "Missing Buffs Choices",
                desc   = "Missing Buffs now covers only the buffs you can cast, and its cog picks which ones, Thorns and Paladin Blessings included (all on by default)",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "INDICATORS", highlight = "Missing Buffs" } or nil,
            },
            {
                -- Name Format heads the Name Size row's cog, on WoW Forever only.
                forever = true,
                module = "Raid Frames",
                title  = "Name Format",
                desc   = "Raid and party names can show only the first or last word of a name, set at the top of the Name Size cog",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "TEXT DISPLAY", highlight = "Name Size" } or nil,
            },
            {
                -- The CALL TOTEM BAR section is built for shamans on WoW Forever only.
                forever = true,
                module = "Resource Bars",
                title  = "Call Totem Bar",
                desc   = "Shamans can show Blizzard's call totem bar in the Totem Bar look and move it with Unlock Mode (off by default)",
                nav    = (EllesmereUI.IS_FOREVER and select(2, UnitClass("player")) == "SHAMAN")
                    and { module = "EllesmereUIResourceBars", page = "Totem Bar",
                          section = "CALL TOTEM BAR", highlight = "Enable Call Totem Bar" } or nil,
            },
            {
                module = "Unit Frames",
                title  = "Has Duration Filter",
                desc   = "The player frame's Debuff Filter and the target and focus Buff Filter can hide permanent auras with Has Duration, and the target and focus Debuff Filter cog has it too",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Debuff Filter" },
            },
        },
        fixes = {
            { forever = true, module = "Bags", text = "A bank whose free base slots were never opened now offers an Open Bank Slots button instead of showing an empty window." },
            { forever = true, module = "Bags", text = "Items in your sixth bank bag and any after it now show in the bank window." },
            { module = "Blizz UI Enhanced", text = "The Bonus Roll window's timer bar is visible again with the window skin on, in the same style as the loot roll timers." },
            { module = "Chat", text = "On a fresh install the chat window now starts far enough from the screen edge to fit its sidebar." },
            { module = "Minimap", text = "Edit Mode no longer shows a selection box for Blizzard's hidden minimap." },
            { module = "Nameplates", text = "Auras in the top slot now sit above the Level text when Level is the Top Text." },
            { module = "Nameplates", text = "Clicking the Level or Health # text in the settings preview now scrolls to its text position, like the name and health %." },
            { module = "Nameplates", text = "Text colors set by a spec-assigned nameplate preset now apply to the first nameplates after login, not only after the next settings change." },
            { forever = true, module = "Nameplates", text = "Blizzard's arrow under the nameplates of units behind your camera no longer shows." },
            { forever = true, module = "Raid Frames", text = "Missing Buffs no longer marks group members who have the buff as missing during and after fights in dungeons and raids." },
            { forever = true, module = "Resource Bars", text = "The Totem Bar's Enabled Classes list no longer offers Death Knight, Monk, Demon Hunter or Evoker." },
            { module = "Unit Frames", text = "The target and focus cast bars no longer go missing from Unlock Mode when it is opened with a target or focus selected under the Blizzard, Classic or WoW Forever looks." },
            { module = "Localization", text = "Brazilian Portuguese translations updated." },
        },
    },
    {
        version = "9.3.3",
        mini = true,
        features = {
            {
                -- Match All sits in each indicator tile's Filters dropdown: page-only.
                module = "Raid Frames",
                title  = "Match All on Indicators",
                desc   = "Debuff indicators can show only debuffs that match all their filters; everything else stays where it was",
                nav    = { module = "EllesmereUIRaidFrames", page = "Debuff Manager" },
            },
            {
                module = "Raid Frames",
                title  = "Name Bar on Bottom",
                desc   = "The Top Name Bar can sit at the bottom of the frame, under the health and power bars",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "TOP NAME BAR", highlight = "Show on Bottom" },
            },
            {
                -- The Missing Buffs row exists only on WoW Forever.
                forever = true,
                module = "Raid Frames",
                title  = "Missing Buffs",
                desc   = "Raid and party frames show a glowing Fortitude, Mark of the Wild or Spirit icon on anyone missing it while your group can cast it",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "INDICATORS", highlight = "Missing Buffs" } or nil,
            },
        },
        fixes = {
            { forever = true, module = "Action Bars", text = "Edit Mode no longer shows selection boxes for Blizzard's hidden action bar end caps." },
            { forever = true, module = "Raid Frames", text = "HoverCast can bind a specific spell rank: a lower rank picked from the spell grids casts exactly that rank on its own key, while the top rank keeps casting your highest rank." },
            { module = "Resource Bars", text = "Clicking the icon, spell text or duration text in the Cast Bar preview now jumps to the matching setting." },
            { module = "Unit Frames", text = "The Portrait Dragon's Frame Level now defaults to 2, so it sits over more of the frame." },
            { forever = true, module = "Unit Frames", text = "Weapon imbues such as Rockbiter Weapon now show on the Player Aura Bars Buffs bar." },
        },
    },
    {
        version = "9.3.2",
        heroes = {
            {
                -- The End Caps row sits in Layout under the WoW Forever look and in Visibility otherwise,
                -- read at click time (the Style page code loads after this file).
                module = "Action Bars",
                title  = "End Caps on Any Bar",
                desc   = "End caps can go on any action bar, left, right or both, each with its own size and offsets. On the WoW Forever look any bar can also show the bar background.",
                onClick = function()
                    local section = EllesmereUI.BlizzStyle.Forever("actionbars") and "LAYOUT" or "VISIBILITY"
                    EllesmereUI:NavigateToElementSettings("EllesmereUIActionBars", "Bar Display", section,
                        function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end, "End Caps")
                end,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Upgraded Flight Timer",
                desc   = "The flight timer now shows your route: a track between the two ends of the flight with each stop scrolling past as you reach it, plus an early landing button and adjustable height and end caps. It is now on by default.",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Travel",
                           section = "FLIGHT TIMER", highlight = "Enable Flight Timer" } or nil,
            },
        },
        features = {
            {
                -- Static card: the bag bar in the bag window, nothing to open.
                module = "Bags",
                title  = "Rearrange Bags",
                desc   = "Drag a bag on the bag bar onto another slot to swap them; the bar now runs in Blizzard's order",
            },
            {
                -- Tooltip behavior: page-only.
                module = "Data Bars",
                title  = "Micro Menu Tooltips",
                desc   = "Character always shows item level and stats; Social and Guild always list who is online",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- Show Notes sits in the Friends Tooltip Cap cog.
                module = "Minimap",
                title  = "Friend Notes",
                desc   = "The Friends Online tooltip can show each friend's or guildmate's note (off by default)",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap",
                           section = "MINIMAP & QOL BUTTONS", highlight = "Friends Tooltip Cap" },
            },
            {
                -- The toggle sits in the Show Groups cog; no Mythic raids on WoW Forever.
                module = "Raid Frames",
                title  = "Hide Groups 5-8 in Mythic",
                desc   = "A Show Groups option hides groups 5-8 inside a Mythic raid, where only groups 1-4 take part",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "LAYOUT", highlight = "Show Groups" } or nil,
            },
            {
                -- The Buffs tab: page-only.
                forever = true,
                module = "Raid Frames",
                title  = "Starter Buff Indicators",
                desc   = "Defensives, Externals and Consumables in the center, your own core healing buffs top right",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Buff Manager" } or nil,
            },
            {
                -- The Resource Bars Power Bar row (Unit Frames has the same dropdown).
                forever = true,
                module = "Resource Bars & Unit Frames",
                title  = "Regen Ticks",
                desc   = "Mana Regen Spark can keep sweeping every 2 seconds while your mana regenerates",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "POWER BAR", highlight = "Mana Regen Spark" } or nil,
            },
            {
                -- Icon Border sits in the Show Icon cog.
                module = "Unit Frames",
                title  = "Cast Icon Border",
                desc   = "The cast icon can use the cast bar's border style, with an optional divider or wrap-around border",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "CAST BAR", highlight = "Show Icon",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- Class Zoom sits in the portrait Size row's zoom cog.
                module = "Unit Frames",
                title  = "Class Zoom",
                desc   = "Class-art portraits get a Class Zoom slider in the portrait zoom settings",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "PORTRAIT", highlight = "Size",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- The separator sits in the Portrait Mode cog.
                module = "Unit Frames",
                title  = "Portrait Border Separator",
                desc   = "Attached portraits can draw the border style's divider between the portrait and the bars",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "PORTRAIT", highlight = "Portrait Mode",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "Unit Frames",
                title  = "Portrait Dragon",
                desc   = "The dragon has its own Portrait row and works with any portrait, attached or detached",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "PORTRAIT", highlight = "Enable Player Frame Dragon",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- A Power Type choice for druids on WoW Forever.
                forever = true,
                module = "Unit Frames",
                title  = "Mana + Form Power",
                desc   = "Druids can keep Mana on the power bar with Energy or Rage in a second bar",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Power Type",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end } or nil,
            },
        },
        fixes = {
            { module = "Action Bars", text = "Action bars, including the Stance Bar, now stay on screen after a UI Scale, resolution or window size change, and return to their saved spot when there is room again." },
            { module = "AuraBuff Reminders", text = "Source of Magic now counts only your own cast, clears as soon as you cast it (even in combat), no longer flashes after loading screens, and reminds early by your Show Below settings." },
            { module = "AuraBuff Reminders", text = "Elemental Orbit shamans can turn on an out-of-combat reminder for when no groupmate has their Earth Shield or it is about to run out." },
            { module = "Blizz UI Enhanced", text = "The Great Vault shortcut now opens the vault without closing the character sheet, and a second click closes it." },
            { forever = true, module = "Forever Essentials", text = "The flight timer now starts when you take off." },
            { module = "General", text = "The Gamepad settings in Global Settings (hide action bars and the player cast bars while a controller is connected) are now off by default." },
            { module = "General", text = "A UI Scale change made during combat is no longer undone by the game in the same fight." },
            { module = "General", text = "The \"How should EllesmereUI look?\" popup marks the look you are using as In Use, like Global Settings > Style." },
            { forever = true, module = "General", text = "Sound pickers (Chat whisper sound, Cooldown Manager bar sounds and others) show their speaker preview icon again." },
            { module = "Minimap", text = "Popups that an addon opens from a button collected in the minimap button bag now draw above the bag and take clicks outside it." },
            { module = "Nameplates", text = "The Interrupted flash now also shows when a channeled or empowered cast is interrupted, on nameplates and on the Mythic+ target and focus cast bars." },
            { module = "Nameplates", text = "Fixed a Lua error from the faction badge on full friendly nameplates when player names are hidden by the game (e.g. switching off Name Only)." },
            { module = "Nameplates", text = "Friendly nameplates shown by Blizzard no longer lose their widget bars, raid marker or interact icon, or show them on another nameplate, after reusing a frame from an enemy nameplate." },
            { module = "Nameplates", text = "Enemy nameplates no longer keep Blizzard's hidden cast bar running underneath, which cuts background work in large caster pulls." },
            { module = "QoL", text = "A moved Top Bar Event Text that the game re-anchors during combat now returns to your spot after the fight." },
            { forever = true, module = "QoL", text = "With the Gamepad interface style, the Shifter steps aside, so closing bags or windows opened from the radial menu no longer shows a blocked-action error and freezes the game." },
            { module = "Quest Tracker", text = "Tracker sections added by other addons now get the EllesmereUI skin like Blizzard's own sections." },
            { module = "Raid Frames", text = "Party and raid frames now appear right away when you join a group or your party becomes a raid during combat, instead of after the fight." },
            { forever = true, module = "Raid Frames", text = "The Buffs tab now opens on All Specs." },
            { module = "Resource Bars", text = "Hide Power Bar if Resource no longer hides the Power Bar while the Class Resource is turned off, which also brings back the druid mana bar in Cat Form on WoW Forever." },
            { forever = true, module = "Resource Bars", text = "Spell Cost Prediction now shows on the Power Bar while you cast." },
            { module = "Unit Frames", text = "The Power Bar Seam now joins the frame border on the Pixels border styles." },
            { module = "Unit Frames", text = "The player power bar and its text now move smoothly as power regenerates or drains, in step with Blizzard's displays and the Resource Bars power bar, instead of updating every couple of seconds." },
            { module = "Unlock Mode", text = "Width-matched action bars and unit frames settle back into their saved spot after every fight, not only the first one of the session." },
        },
    },
    {
        version = "9.3.1",
        heroes = {
            {
                -- Set from the bar list (speaker icon or right-click): page-only.
                module = "Cooldown Manager",
                title  = "Tracking Bar Sounds",
                desc   = "Tracking Bars can play a sound when their buff is gained or lost, from the built-in sounds or your SharedMedia sounds, the Bloodlust, Time Spiral and potion bars included. Set it from a bar's speaker icon in the bar list or by right-clicking the bar.",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
            {
                -- The page is not registered on WoW Forever: a static card there.
                module = "Cooldown Manager",
                title  = "Rotation Assist Icon",
                desc   = "A movable icon shows Blizzard's recommended next ability with its keybind and an optional GCD swipe. It needs Blizzard's Assisted Highlight turned on.",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUICooldownManager", page = "Rotation Assist Icon",
                           section = "ROTATION ASSIST ICON", highlight = "Show Rotation Assist Icon" } or nil,
            },
        },
        features = {
            {
                -- The End Caps row sits in Visibility under the EllesmereUI style.
                module = "Action Bars",
                title  = "End Caps for the EllesmereUI Style",
                desc   = "Action Bar 1 can show modern or classic gryphons under the EllesmereUI style too, plus the WoW Forever art there (off by default)",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "VISIBILITY", highlight = "End Caps",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
            {
                forever = true,
                module = "Action Bars",
                title  = "Show Bar Background",
                desc   = "Under the WoW Forever style, Action Bar 1's frame and dividers can be turned off, next to Show End Caps in Layout",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "LAYOUT", highlight = "Show Bar Background",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end } or nil,
            },
            {
                -- Retail-only row (no seasons on WoW Forever).
                module = "Blizz UI Enhanced",
                title  = "Season Panel",
                desc   = "The Character Sheet shows an Omnium Folio shortcut in Midnight seasons (on by default), with an optional Great Vault shortcut",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "CORE OPTIONS", highlight = "Season Panel" } or nil,
            },
            {
                module = "Blizz UI Enhanced",
                title  = "Hide Slot Flyout Arrows",
                desc   = "The Character Sheet can hide the arrows beside its equipment slots; the gear flyouts keep working",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "CORE OPTIONS", highlight = "Hide Slot Flyout Arrows" } or nil,
            },
            {
                -- The styling cog sits on Show Keybind.
                module = "Cooldown Manager",
                title  = "Keybind Label Styling",
                desc   = "Keybind text on CDM bars gets its own font, outline, size, anchor, offsets, color, background and border",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           section = "EXTRAS", highlight = "Show Keybind",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                -- Added from the block picker: page-only.
                module = "Data Bars",
                title  = "Bags Block",
                desc   = "A new block shows your free or used bag slots, can include the reagent bag and recolors the count when space runs low",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- Tooltip behavior: page-only.
                module = "Data Bars",
                title  = "Interactive Audio Tooltip",
                desc   = "Mute channels and set their volume from the tooltip by clicking, dragging or scrolling; the block turns red while muted",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- The Friends List card on the Window Skins page (retail).
                module = "Friends",
                title  = "Window Skin Look",
                desc   = "The friends window's frame, border, tabs and search box follow the Blizzard Window Skins style (Friends List card)",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" } or nil,
            },
            {
                module = "General",
                title  = "Glows",
                desc   = "A new Global Settings page sets one glow look for every module that shows a glow; CD Ready glows can use every style too",
                nav    = { module = "_EUIGlobal", page = "Glows" },
            },
            {
                module = "General",
                title  = "Gamepad Settings",
                desc   = "A new Gamepad tab hides chosen action bars and the player cast bars while a controller is connected (on by default)",
                nav    = { module = "_EUIGlobal", page = "Gamepad",
                           section = "ACTION BARS", highlight = "Hide Action Bars" },
            },
            {
                -- Static card: the work is automatic, nothing to open.
                forever = true,
                module = "General",
                title  = "Class Settings and Retail Parity",
                desc   = "Spec settings apply to your class, retail-only options are hidden, and profiles survive trips to retail",
            },
            {
                -- Mythic+ Tools does not load on WoW Forever.
                module = "Mythic+ Tools",
                title  = "Forces Bar Height",
                desc   = "The enemy forces bar can have its own height, and the Mythic+ Timer settings are regrouped so each one sits with the bar it changes",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer",
                           section = "FORCES", highlight = "Forces Bar Height" } or nil,
            },
            {
                module = "Nameplates",
                title  = "Threat Color Options",
                desc   = "Show Threat Colors picks Never, Instances (the default) or Always, and threat can also tint the border or the name",
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "THREAT COLORS", highlight = "Show Threat Colors" },
            },
            {
                -- The Name Format rows sit in the text slots' cogs.
                forever = true,
                module = "Nameplates & Unit Frames",
                title  = "Name Format",
                desc   = "Name text slots can show only the first or last word of a name, set at the top of the slot's text cog",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE TEXT POSITIONS", highlight = "Top Text" } or nil,
            },
            {
                -- The LFG Reminder is not built on WoW Forever.
                module = "QoL",
                title  = "LFG Reminder for Group Leaders",
                desc   = "The LFG Reminder also shows for the leader when listing a group, and again only if the listed dungeon changes",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIQoL", page = "QoL",
                           section = "LFG REMINDER", highlight = "Enable LFG Reminder" } or nil,
            },
            {
                -- The toggle lives in the Health Bar Texture cog.
                module = "Raid Frames",
                title  = "Fill Missing Health",
                desc   = "Health bars can fill with the health a unit is missing instead of what it has left, from the Health Bar Texture cog",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "HEALTH BAR", highlight = "Health Bar Texture" },
            },
            {
                module = "Raid Frames",
                title  = "Power Text",
                desc   = "Raid and party frames can show power as a percent or number on frames with a power bar, with its own color, size and position",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "TEXT DISPLAY", highlight = "Power Text" },
            },
            {
                -- Set per entry in the Threshold & Hash Lines editor.
                module = "Resource Bars",
                title  = "Spenders",
                desc   = "The Class Resource Bar can change color while a spell you choose is ready to cast, set per entry under Threshold & Hash Lines",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "CLASS RESOURCE BAR", highlight = "Threshold & Hash Lines" },
            },
            {
                forever = true,
                module = "Resource Bars",
                title  = "Mana Bar while Shapeshifted",
                desc   = "Druids can show a thin mana bar with the Power Bar in Bear and Cat Form, with its own position, size and text",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "POWER BAR", highlight = "Mana Bar while Shapeshifted" } or nil,
            },
            {
                forever = true,
                module = "Resource Bars",
                title  = "Spell Cost Prediction",
                desc   = "The Power Bar can shade the mana your current cast will spend, like the Unit Frames power bar",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "POWER BAR", highlight = "Spell Cost Prediction" } or nil,
            },
            {
                -- The dragon row closes the PORTRAIT section on the player, target
                -- and focus tabs (any portrait but None); the link opens the
                -- player's.
                module = "Unit Frames",
                title  = "Wingless Dragon",
                desc   = "The player portrait can wear Blizzard's boss dragon, and target and focus can show it on elite enemies",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "PORTRAIT", highlight = "Enable Player Frame Dragon",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "AuraBuff Reminders", text = "Another player's Soulstone, Source of Magic, Blistering Scales or Symbiotic Relationship no longer counts as your own, so your reminder stays up until you cast yours." },
            { forever = true, module = "Bags", text = "The bank window has a Show Bags button with the bank bag slots, so a bought bank tab can take a bag and shows up right away." },
            { forever = true, module = "Bags", text = "The bag window now fits its contents instead of leaving a large empty area below your items." },
            { module = "Chat", text = "Whisper Sound now replaces Blizzard's whisper sound instead of playing over it: Blizzard Default keeps the game's sound, and the new None option plays no sound at all." },
            { module = "Chat", text = "Idle Fade no longer stays off after you hover the sidebar while chat is faded." },
            { module = "Cooldown Manager", text = "A 1px Pandemic Pixel Glow on Tracked Buff Bars is no longer hidden under the bar border." },
            { module = "Cooldown Manager", text = "The Healthstone presets now show only the stone you can make: the Demonic Healthstone with Pact of Gluttony and the regular Healthstone without it, so your stones no longer show on two icons." },
            { module = "Cooldown Manager", text = "Item icons now update right after quick bag changes, such as conjuring a Healthstone, instead of staying greyed out until your next action." },
            { module = "Damage Meters", text = "Windows hidden by a visibility rule (Hide in Raids or Dungeons, the toggle key, mouseover) no longer keep updating in the background, and catch up the moment they show." },
            { module = "Damage Meters", text = "With Visibility set to Mouseover, a window set to Hide in Raids or Hide in Dungeons no longer appears when hovered, and deleted windows no longer reappear there." },
            { module = "Data Bars", text = "The Gold block's bag space no longer counts quivers, soul bags or profession bags as free space." },
            { module = "General", text = "Options pages no longer get stuck without a scrollbar after collapsing a card near the bottom." },
            { module = "General", text = "Glow previews in the options now match the thickness of the live glow." },
            { forever = true, module = "General", text = "Numbers below 10,000 are shown in full instead of being shortened to K (for example 1446 instead of 1.4K)." },
            { module = "Minimap", text = "Addon buttons that are hidden or shown again while the button bag is closed no longer leave an empty or blank slot in the bag." },
            { forever = true, module = "Minimap", text = "A fresh install now starts the EllesmereUI and BugSack minimap buttons outside the button group." },
            { module = "Mythic+ Tools", text = "An imported profile with Move Timer Inside Bar on and the timer bar hidden now shows the regular timer instead of none." },
            { module = "Mythic+ Tools", text = "Hiding the timer bar no longer turns off Move Timer Inside Bar, so the timer goes back inside the bar when you show it again." },
            { module = "Nameplates", text = "The Blizzard, Classic and WoW Forever nameplate looks have a slightly taller click area." },
            { module = "Nameplates", text = "Show Seam Line now spans the full health bar width when Make Icon Part of the Bar is on, and draws only with the Pixels and Pixels Textured border styles." },
            { forever = true, module = "Nameplates", text = "With the WoW Forever style, friendly nameplates in busy areas no longer cause a Lua error." },
            { forever = true, module = "Nameplates", text = "Nameplates and their names are centered on the health bar again, with the level box beside it." },
            { forever = true, module = "Nameplates", text = "The top text is now larger and sits slightly higher by default." },
            { forever = true, module = "Nameplates", text = "Threat colors now show everywhere by default instead of only in instances." },
            { forever = true, module = "Nameplates & QoL", text = "Out-of-range nameplate fading and the crosshair color now follow spell range for Druids outside Cat and Bear Form, Priests, Mages and Warlocks as intended, and for Shamans too." },
            { forever = true, module = "QoL", text = "Auto Combat Logging now starts in every raid, the original raids included, and offers a Dungeons trigger (off by default) in place of the retail difficulty, Mythic+, Arena and Scenario triggers." },
            { module = "Raid Frames", text = "The hover and target highlight now shows on every border style: when it would match the border's own color it is drawn in gold." },
            { module = "Raid Frames", text = "The Debuff Manager's Glow and Health Bar Color indicators now have the Max Duration filter." },
            { forever = true, module = "Raid Frames", text = "The delete buttons on HoverCast binding tiles and on Buff Manager, Debuff Manager and Player Aura Bars tiles are visible again, as a trash can." },
            { forever = true, module = "Resource Bars", text = "Paladins and Warlocks no longer get an empty Holy Power or Soul Shard slot, \"Hide Power Bar if Resource\" no longer hides their mana bar, and \"Shift Elements if No Resource\" now moves elements up or down for them." },
            { forever = true, module = "Resource Bars", text = "Rogue and Cat Form combo points now show the points on your current target and update when you switch targets." },
            { forever = true, module = "Resource Bars & Unit Frames", text = "Mana Regen Spark now makes a single five second sweep after you spend mana, matching the five second rule, instead of also sweeping with each regen tick." },
            { module = "Unit Frames", text = "Boss frames now always stack in the chosen Stack Direction; Vertical Spacing no longer flips them when set below zero." },
            { module = "Unit Frames", text = "The Mistweaver Monk power bar no longer shows the wrong color after zoning into an instance, delve or portal." },
            { module = "Unit Frames", text = "Round portraits have a new Naowh Thin Circle outer ring in the Shape Border cog." },
            { module = "Localization", text = "German, Brazilian Portuguese and Traditional Chinese caught up on the latest strings, including the new Glows page and the Action Bars border and end cap options." },
        },
    },
    {
        version = "9.3",
        heroes = {
            {
                -- Every Pixels addition in one card (user directive). Static card:
                -- the additions span every module, so there is no one page to open.
                module = "General",
                title  = "PapaPixels Customization Collab",
                desc   = "Customization has been upgraded across every module, with over 130 new settings for custom borders, separators, textures and more. Tons of new media art was added including new PapaPixels textures with matching portrait rings, absorb shields, fonts and more class/role art.",
            },
            {
                -- The Party tab holds both: Party Targets and the pets' Beside Owner position.
                module = "Raid Frames",
                title  = "Target and Pet Frames",
                desc   = "Each party member can show a small target frame, with its own size, position and bar colors; click it to target that unit. Pets can show beside the party and raid frames with health, range fading, borders and click-casting, after the groups, beside their owners or with Free Move.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Party",
                           section = "PARTY TARGETS", highlight = "Enable Party Targets" },
            },
            {
                -- Static card: automatic while a controller is in use, no setting to open.
                module = "General",
                title  = "Controller Support",
                desc   = "Bags, the options window, popups, dropdowns, sliders and cog menus now work with a controller, through a controller addon or WoW's gamepad mode, and Back closes every open EllesmereUI window. Quick Keybind can bind macros to pad buttons; mouse and keyboard play is unchanged.",
            },
            {
                -- Page-only on purpose: the WoW Forever card sits in the Style
                -- page header above every section.
                forever = true,
                module = "General",
                title  = "WoW Forever Style",
                desc   = "A new style that matches WoW Forever's default UI: a framed action bar with gryphons or wyverns, the day/night minimap orb, round level badges, nameplate level boxes and bronze chat and meter windows. Pick it per module or for the whole UI on Global Settings > Style.",
                nav    = { module = "_EUIGlobal", page = "Style" },
            },
        },
        features = {
            {
                -- The row exists only under a stock look; size and offsets live in its cog.
                module = "Action Bars",
                title  = "Gryphon End Caps",
                desc   = "Blizzard Style and Classic WoW UI can show gryphon or wyvern end caps on Action Bar 1, with size and offsets",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "VISIBILITY", highlight = "Show End Caps",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
            {
                module = "AuraBuff Reminders",
                title  = "Grow Direction",
                desc   = "Reminder icons can grow left or right from a fixed edge instead of from the center, so they stop shifting as buffs come and go",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "CORE", highlight = "Grow Direction" },
            },
            {
                -- The Dragon Riding page is not registered on WoW Forever: clickable
                -- on retail, a static card there.
                module = "Blizz UI Enhanced",
                title  = "Skyriding HUD Styles",
                desc   = "Blizzard Style or Classic WoW UI from the Style page, Classic Gems vigor, hideable parts and a full-charge sound",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBlizzardSkin", page = "Dragon Riding",
                           section = "GENERAL", highlight = "Vigor Style" } or nil,
            },
            {
                -- The Adjust Crop slider lives in the Custom Icon Shape row's cog.
                module = "Cooldown Manager",
                title  = "Adjust Crop",
                desc   = "Cropped icons can trim more or less of the icon, per bar, from a cog on Custom Icon Shape",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           section = "ICON DISPLAY", highlight = "Custom Icon Shape",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                -- Lives in the preview icon's right-click menu: page-only.
                module = "Cooldown Manager",
                title  = "Out of Range Coloring",
                desc   = "Spells added by Spell ID can turn red while your target is out of range (right-click the icon in the preview)",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                -- Lives in the preview icon's right-click menu: page-only.
                module = "Cooldown Manager",
                title  = "Talent Conditions",
                desc   = "Show a cooldown or utility icon only with or without chosen talents (right-click the icon in the preview)",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                -- The Forever Essentials module only exists on WoW Forever: clickable
                -- there, a static card on retail.
                forever = true,
                module = "Forever Essentials",
                title  = "Threat Meter Window",
                desc   = "A Damage Meters style window that resizes and snaps, with focus tracking, class icons, Blizzard or Classic looks and /euitm chat commands",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Threat",
                           section = "THREAT METER", highlight = "Enable Threat Meter" } or nil,
            },
            {
                -- Clickable on WoW Forever only, like the card above.
                forever = true,
                module = "Forever Essentials",
                title  = "Threat Meter Customization",
                desc   = "Header, bar color, bar text and border settings like the Damage Meters, a Tank % value and a live preview at the top of the Threat page",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Threat",
                           section = "BAR TEXT", highlight = "Displayed Value" } or nil,
            },
            {
                -- Static card: a title-bar button on the options window.
                module = "General",
                title  = "Collapse Options Window",
                desc   = "A button beside the close X shrinks the options window to a mini window so you can see your UI, and both buttons glow on hover",
            },
            {
                forever = true,
                module = "General",
                title  = "Raid Frame and Character Sheet Styles",
                desc   = "Raid Frames and the Character Sheet get Style page rows; any style but EllesmereUI Style shows Blizzard's own sheet",
                nav    = { module = "_EUIGlobal", page = "Style" },
            },
            {
                forever = true,
                module = "Nameplates",
                title  = "Show Sunder Armor",
                desc   = "Warriors can show Sunder Armor and its stacks from any warrior on enemy nameplates",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "EXTRAS", highlight = "Show Sunder Armor" },
            },
            {
                -- The rows live on the Forever Essentials Threat page: clickable on
                -- WoW Forever, a static card on retail.
                forever = true,
                module = "Nameplates & Unit Frames",
                title  = "Threat % Text",
                desc   = "Your threat percentage on enemy nameplates and the target and focus frames, colored by threat status",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Threat",
                           section = "THREAT % TEXT", highlight = "Show on Nameplates" } or nil,
            },
            {
                -- The slider lives in the cog on the Visibility row.
                module = "Minimap",
                title  = "Minimap Opacity",
                desc   = "Fade the minimap between 10 and 100% from a cog on Visibility; it works with every Visibility setting, Mouseover and combat included",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap",
                           section = "DISPLAY", highlight = "Visibility" },
            },
            {
                -- The toggle lives in the Friendly Nameplate Settings cog.
                module = "Nameplates",
                title  = "Class Colored Names",
                desc   = "Full friendly nameplates can show player names in their class color, set separately from the health bar color",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "OTHER NAMEPLATES", highlight = "Show EUI Friendly Player Nameplates" },
            },
            {
                -- Both sliders live in the Portrait Zoom cog on the Size row.
                module = "Raid Frames",
                title  = "Full-Body 3D Portraits",
                desc   = "Party 3D Zoom can pull back to show the whole character, and Character Size scales it inside an Inside portrait",
                nav    = { module = "EllesmereUIRaidFrames", page = "Party",
                           section = "PORTRAIT", highlight = "Size" },
            },
            {
                -- Gated to WoW Forever: on retail "Power Type" would pulse the
                -- retail spec-based row, a different setting.
                forever = true,
                module = "Resource Bars & Unit Frames",
                title  = "Druid Power Type",
                desc   = "Druids can keep the power bar on Mana in Bear and Cat Form",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Power Type",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end } or nil,
            },
            {
                forever = true,
                module = "Resource Bars & Unit Frames",
                title  = "Mana Regen Spark",
                desc   = "A spark sweeps the mana bar through the five second rule, then with each regen tick",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Mana Regen Spark",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "Unit Frames",
                title  = "Important Cast Glow",
                desc   = "Target and focus cast bars can glow when the unit casts an important spell",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "CAST BAR", highlight = "Important Cast Glow",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("target"); EllesmereUI._pendingUnitSelect = "target" end },
            },
            {
                -- The toggle lives in the Portrait Mode cog; it reveals the Non-Player Portrait row.
                module = "Unit Frames",
                title  = "Custom Non-Player Portrait",
                desc   = "With Class art, NPCs can show nothing or their 3D model instead of the 2D portrait, from the Portrait Mode cog",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "PORTRAIT", highlight = "Portrait Mode",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("target"); EllesmereUI._pendingUnitSelect = "target" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "The XP, reputation and house favor bars now update their size, texture and text when you switch or import a profile or a spec override applies." },
            { forever = true, module = "Action Bars", text = "Action Bar 1 now switches with every stance or form like the default UI, warrior stances included, so keybinds always cast the icon you see (turn on Disable Form Paging to keep one bar)." },
            { forever = true, module = "Action Bars", text = "The queue status eye now stays where you placed it." },
            { module = "Action Bars", text = "With Spec Overrides, Pushed Type and Highlight Type now show as overridden when only the Border Size in their cog is overridden." },
            { module = "Bags", text = "Opening, closing and sorting bags now play Blizzard's sounds." },
            { forever = true, module = "Bags", text = "With the Gamepad interface style on, Blizzard's own bags and bank open instead, so the D-pad can reach them." },
            { module = "Blizz UI Enhanced", text = "Crafted Myth and Hero gear shows its item level in the Myth or Hero color on the character sheet, inspect window, equipment flyout and merchant." },
            { module = "Blizz UI Enhanced", text = "With the tooltip's Show Item Level on, the Inspect window now opens reliably, and tooltip item levels show after a brief pause." },
            { module = "Blizz UI Enhanced", text = "With Hide in Combat on, the Skyriding HUD now shows your current vigor, Second Wind charges and Whirling Surge cooldown as soon as it reappears after combat." },
            { forever = true, module = "Blizz UI Enhanced", text = "Profiles set to Blizzard Style or Classic WoW UI for the whole UI now show Blizzard's own character sheet; choose EllesmereUI Style on the Style page's Character Sheet row to keep the EllesmereUI sheet." },
            { forever = true, module = "Blizz UI Enhanced", text = "With the WoW Forever style, the character sheet now shows each item's stats, weapon damage per second and enchant beside its slot." },
            { module = "Blizz UI Enhanced & QoL", text = "The character sheet, Secondary Stats and the Data Bars stats tooltip show your best crit chance (spell, ranged or melee) like Blizzard's, so casters see their spell crit." },
            { module = "Cooldown Manager", text = "Remove Active State on a trinket, potion, racial or spell added by Spell ID no longer clears that icon's other per-spell settings." },
            { module = "Cooldown Manager", text = "The Healthstone preset now counts and shows Demonic Healthstones, item counts update as soon as a charge is used or refilled, and Hide Items if Missing drops an item the moment its last charge is gone." },
            { module = "Cooldown Manager", text = "Cast Trigger rules on the Healthstone and multi-rank potion presets now also fire when you use a Demonic Healthstone or another rank." },            { module = "Damage Meters", text = "Rows no longer show as empty outlines right after logging in or after switching to a shorter segment, your pinned row clears when a segment has no data, and a turned-off icon border stays hidden." },
            { module = "Damage Meters", text = "Making a meter window taller fills the new rows right away, and your pinned row now follows Icon Style, Opacity and bar color changes." },
            { module = "Data Bars", text = "Clicking the Item Level block opens the character sheet without an error; like the Location block, it does nothing in combat." },
            { forever = true, module = "Data Bars & Quickdraw", text = "The Spellbook button in the micro menu and in Quickdraw opens the Spellbook, with a separate Talents button beside it." },
            { module = "Forever Essentials", text = "No longer appears as an out-of-date, incompatible addon on retail." },
            { forever = true, module = "Forever Essentials", text = "The threat meter now keeps a fixed size with scrolling rows instead of growing from its middle, and a spot set in Unlock Mode no longer moves when combat starts. A meter you never customized takes the new default size and look." },
            { forever = true, module = "Forever Essentials", text = "Threat meter names no longer cut off early: the threat and percent column now takes only the room its numbers need." },
            { forever = true, module = "Forever Essentials", text = "Threat meter pet bars now take their owner's class color with a pet icon instead of a fixed grey-green, and your own bar is marked with a thin white stripe." },
            { forever = true, module = "Forever Essentials", text = "The threat meter's warning sound now plays again when you switch straight to another mob you are already past your Warn At threshold on." },
            { forever = true, module = "Forever Essentials", text = "The threat meter's In Combat and Out of Combat visibility now also count your pet's and the tracked mob's combat, so the meter shows as soon as that mob is fighting your group." },
            { module = "General", text = "Changing the UI scale or window size no longer brings back borders you turned off, such as meter icon borders, the chat border under a Blizzard look and the minimap's square border on a round map." },
            { forever = true, module = "General", text = "Blizzard Style now uses the retail Blizzard art on action buttons, unit frames, nameplates, cast bars, cooldown icons and party portraits, matching Blizzard Style on retail; the new WoW Forever style uses the Forever frame art with Blizzard Style's bar textures." },
            { forever = true, module = "General", text = "Frames placed by an imported profile, such as unit frames, now take their saved spots at login instead of sitting at the screen center." },
            { forever = true, module = "General", text = "On some screen sizes and UI scales, a width or height match no longer stops the UI from loading at login." },
            { forever = true, module = "General", text = "New installs now start on the WoW Forever style." },
            { forever = true, module = "General", text = "The Reload UI buttons on the first-install module picker and at the bottom of the options window now reload right away instead of opening a reload popup." },
            { forever = true, module = "Minimap", text = "With Rotate Minimap on, the EllesmereUI and Classic WoW UI minimaps no longer show a stray ring around the map." },
            { module = "Nameplates", text = "Wrap Around Castbar now wraps a Custom border around the cast bar on your nameplates, not only in the options preview." },
            { module = "Nameplates", text = "Full friendly nameplates no longer keep the hover Border Color after the mouse moves away." },
            { module = "Nameplates", text = "Changing Health Bar Width or Height now also resizes nameplates that appear afterwards, not only the ones already on screen." },
            { module = "Nameplates", text = "Full friendly nameplates with Class Colored Health Bar off no longer switch to class colors after a profile switch, a Dark Mode change or a class color edit." },
            { module = "Nameplates", text = "Full friendly nameplates now use your custom class colors and Class Color Darken, and update right away when you change profile or edit those colors." },
            { forever = true, module = "Nameplates & QoL", text = "Druids outside Cat and Bear Form, Priests, Mages and Warlocks now fade out-of-range nameplates and color the crosshair by their spell range instead of melee range." },
            { module = "QoL", text = "The cursor GCD circle now shows in instanced combat and with Combat Only on the pull, and a cancelled cast there no longer causes a Lua error." },
            { forever = true, module = "QoL & Data Bars", text = "Secondary Stats and the Data Bars stats tooltip show your real haste (spell, ranged or melee) and no longer list Mastery or Versatility." },
            { forever = true, module = "QoL & Resource Bars", text = "The cursor GCD circle and the GCD bar now work." },
            { forever = true, module = "QoL", text = "Quick Signup no longer causes a Lua error at login that stopped other Quality of Life features from loading; it and Persistent Signup Note are removed on WoW Forever, whose group finder has no premade group list." },
            { module = "Raid Frames", text = "Debuff Manager layouts that switch with a spec or conditional override no longer cause a Lua error or mix up their indicators, and Shown on Modifier tooltips now work on square and spec-specific tiles." },
            { module = "Raid Frames", text = "Debuff and buff indicator sizes now go up to 80, and text offsets have a wider range." },
            { module = "Resource Bars", text = "The Class Resource Bar's threshold spec list now greys out All Specs once a card uses it, so All Specs can no longer be added twice." },
            { forever = true, module = "Resource Bars", text = "Threshold colors, multi-band coloring and hash lines now work, the threshold spec list no longer shows empty spec headers, and Druid combo points show as pips in the options instead of a bar." },
            { forever = true, module = "Resource Bars", text = "The Swing Timer's Off Hand and Ranged bars no longer vanish and stay gone after your attack speed changes in combat, such as from a haste proc." },
            { module = "Unit Frames", text = "Boss frames keep your border color when you target or mouse over them instead of turning black, and a boss target or hover border color now stays after a settings change." },
            { module = "Unit Frames", text = "With Blizzard Style, Classic WoW UI or WoW Forever, the player frame no longer comes apart after leveling up or changing form in combat." },
            { module = "Unit Frames", text = "Switching a portrait from 3D to a Class art style no longer leaves it on the 3D-only None shape or an Inside position." },
            { module = "Unit Frames", text = "Changing a setting while in a vehicle no longer switches the player frame's portrait to 2D or the pet frame's to the player frame's Art Style." },
            { module = "Unit Frames", text = "The Player Threat border now turns on or off with a profile switch or spec override instead of waiting for a reload." },
            { module = "Unit Frames & Mythic+ Tools", text = "Korean and Chinese clients show decimal health text and the Mythic+ Run Summary in their own number units, matching the Damage Meters." },
            { forever = true, module = "Unit Frames & Nameplates", text = "Level text now uses the same difficulty colors as the default nameplates (grey, green, yellow, orange and red), so lower-level mobs no longer show yellow." },
            { module = "Localization", text = "Korean gained over 900 new translations and Simplified Chinese over 1,100; Traditional Chinese, German and Brazilian Portuguese caught up on the latest strings." },
        },
    },
    {
        version = "9.2.9",
        heroes = {
            {
                module = "Unit Frames",
                title  = "Heal Prediction",
                desc   = "Player, target and focus frames can show incoming heals on the health bar, yours and other players' in separate colors. Choose the opacity, texture and how far heals may run past a full bar; off by default under Absorbs and Heals.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "ABSORBS AND HEALS", highlight = "Heal Prediction",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "Unit Frames & Nameplates",
                title  = "Faction Indicators",
                desc   = "Player and target frames and nameplates can show a Horde or Alliance badge in seven icon styles, dimmed or hidden on units not flagged for PvP. Nameplates take it in any Core Positions slot or with Rare/Quest, and full friendly plates show it by the name; off by default.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "EXTRAS", highlight = "Faction Indicator",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("target"); EllesmereUI._pendingUnitSelect = "target" end },
            },
            {
                -- The Forever Essentials module only exists on WoW Forever: clickable
                -- there, a static card on retail.
                forever = true,
                module = "Forever Essentials",
                title  = "Threat Meter",
                desc   = "A bar for each group member's threat on your target, or on what your friendly target is fighting, with a pull aggro bar and an optional warning sound as you near aggro. Off by default on the Threat tab of the new Forever Essentials module, with layout, text and color options.",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Threat",
                           section = "THREAT METER", highlight = "Enable Threat Meter" } or nil,
            },
            {
                forever = true,
                module = "General",
                title  = "Raid Frames and Quickdraw",
                desc   = "Raid Frames, click-casting included, and Quickdraw are available now that Blizzard's client runs secure handlers. Action bar stance and form paging, conditional hiding and Cast Actions on Key Down work too, as do micro menu clicks, Raid Tools, the Shifter and Disable Right Click.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames" },
            },
        },
        features = {
            {
                forever = true,
                module = "Blizz UI Enhanced",
                title  = "Character Sheet Item Stats",
                desc   = "Slots show item stats like +14 Int / +9 Stam, weapon DPS and the enchant, with an eye button to hide them",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "CORE OPTIONS", highlight = "Show Item Stats" },
            },
            {
                module = "Party Mode",
                title  = "Spin More of Your UI",
                desc   = "The Spinning checklist adds Data Bars, Unit Frames, Resource Bars and Power Bars to the Action Bars spin",
                nav    = { module = "EllesmereUIPartyMode", page = "Party Mode",
                           section = "PARTY MODE", highlight = "Spinning" },
            },
            {
                -- The Swing Timer page only exists on WoW Forever: clickable there, a
                -- static card on retail. Combine Hands lives in the Tracked Weapons cog.
                forever = true,
                module = "Resource Bars",
                title  = "Swing Timer Options",
                desc   = "Combine both hands on one bar with an off-hand spark, give Cleave its own queued color and offset the text",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Swing Timer",
                           section = "DISPLAY", highlight = "Tracked Weapons" } or nil,
            },
            {
                -- The toggle lives in the Buff Settings cog on the Buff Display row.
                module = "Unit Frames",
                title  = "Buff Dispel Type Borders",
                desc   = "Target, focus and boss buffs can take a border in their dispel type color, from the Buff Settings cog",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Buff Display",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("target"); EllesmereUI._pendingUnitSelect = "target" end },
            },
            {
                forever = true,
                module = "Unit Frames",
                title  = "Pet Happiness",
                desc   = "Hunter pets show their happiness icon beside the pet frame, with a tooltip plus size and position options",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames",
                           section = "PET HAPPINESS", highlight = "Show Happiness",
                           preSelect = function() EllesmereUI._setMiniUnit("pet"); EllesmereUI._pendingMiniSelect = "pet" end },
            },
            {
                forever = true,
                module = "Unit Frames",
                title  = "Pet Power Bar",
                desc   = "The pet frame shows its focus or mana on a power bar, with height, color, position and text options",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames",
                           section = "POWER BAR", highlight = "Power Bar Height",
                           preSelect = function() EllesmereUI._setMiniUnit("pet"); EllesmereUI._pendingMiniSelect = "pet" end },
            },
            {
                forever = true,
                module = "Unit Frames",
                title  = "Spell Cost Prediction",
                desc   = "While you cast, the player power bar marks the mana the spell will cost, in a color you choose",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Spell Cost Prediction",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- The level colours live in the Core Text Coloring section.
                module = "Unit Frames & Nameplates",
                title  = "Level Difficulty Colors",
                desc   = "Level text can take Blizzard's difficulty colors, with an option for friendly units; Blizzard Style levels too",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE TEXT COLORING", highlight = "Text Coloring" },
            },
        },
        fixes = {
            { forever = true, module = "Blizz UI Enhanced", text = "Show Item Level on vendor items no longer causes Lua errors." },
            { forever = true, module = "Blizz UI Enhanced & QoL", text = "The Character Sheet card no longer offers Show Mythic+ Rating and Item Level, and the QoL page no longer offers AH Current Expansion Only and Hide Talking Head, as they had nothing to act on." },
            { module = "Chat", text = "Undocked chat windows no longer show a flickering or faint black bar beside them, and their minimize button fades in on hover without flickering." },
            { forever = true, module = "Cooldown Manager", text = "Spells, trinkets and items can now be added to bars, clicking a bar icon in the options no longer causes a Lua error, and Sync Generic CDs/Buffs now lists your specs." },
            { module = "General", text = "Visibility checklists have new Party Mode and Dungeons rows, to show or hide an element while Party Mode is on or in five-player dungeons and Mythic+, leaving delves out." },
            { forever = true, module = "General", text = "The Reload UI button, /rl, profile imports, turning a module on or off and the other actions that reload the UI now open a reload popup instead of being blocked, and /rl in combat asks you to type /reload." },
            { forever = true, module = "General", text = "The Macro Factory's Potion and Food macros no longer cause Lua errors." },
            { module = "Minimap", text = "Ungrouping all but one of several minimap buttons now keeps the last one in the button group instead of forcing it onto the minimap, and Ungroup Minimap Buttons is greyed out with fewer than two buttons." },
            { forever = true, module = "Nameplates & QoL", text = "The nameplate Range Check and the crosshair's Color Out of Range no longer cause Lua errors." },
            { forever = true, module = "QoL", text = "The Travel tab and its Flight Timer moved to the new Forever Essentials module, keeping its settings and position." },
            { forever = true, module = "Resource Bars", text = "The Class, Power and Health Bars tab is now called Main Resources." },
            { forever = true, module = "Resource Bars", text = "Between swings the Swing Timer no longer shows 0.0, and with Show Spark on, the spark shows only while a swing is running." },
            { forever = true, module = "Resource Bars", text = "The Swing Timer now defaults to In Combat with Deplete Fill on, and a timer still set to Always moves to In Combat once." },
            { forever = true, module = "Unit Frames & Nameplates", text = "Player names now include the character's surname, as Blizzard's own frames show them." },
            { module = "Localization", text = "Brazilian Portuguese translations updated." },
        },
    },
}

-------------------------------------------------------------------------------
--  FCT font -- handled by EllesmereUI_Startup.lua which runs earlier.
-------------------------------------------------------------------------------

-- Wait for EllesmereUI to exist
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local GLOBAL_KEY = EllesmereUI.GLOBAL_KEY or "_EUIGlobal"
    local floor = math.floor
    local ceil  = math.ceil
    local max   = math.max

    ---------------------------------------------------------------------------
    --  CVar helpers
    ---------------------------------------------------------------------------
    local function GetCVarNum(cvar)
        return tonumber(GetCVar(cvar)) or 0
    end

    local function SetCVarSafe(cvar, value)
        if InCombatLockdown() then return end
        EllesmereUI.SetCVar(cvar, value)
    end

    -- Graphics and sound settings (Optimize My FPS and Graphics, its Restore and
    -- Increase Game Image Quality) are written as they are, not through
    -- EllesmereUI.SetCVar: Optimize keeps its own Restore, and Uninstall EUI
    -- never touches them.
    local function SetGfxCVar(cvar, value)
        if InCombatLockdown() then return end
        SetCVar(cvar, value)
    end

    --- Returns current, default as strings (nil-safe)
    local function CVarInfo(cvar)
        local cur, def = C_CVar.GetCVarInfo(cvar)
        return cur or "", def or ""
    end

    --- True while the CVar sits at Blizzard's built-in default (untouched by player or addon).
    local function IsAtBlizzardDefault(cvar)
        local cur, def = CVarInfo(cvar)
        return cur == def
    end

    ---------------------------------------------------------------------------
    --  EUI preferred defaults -- only applied when CVar == Blizzard default
    --
    --  { cvarName, euiPreferred }
    ---------------------------------------------------------------------------
    local EUI_DEFAULTS = {
        { "cameraDistanceMaxZoomFactor",                    "2.6" },
        { "ActionButtonUseKeyDown",                         "1"   },
    }

    --- Walk the table once at login and apply only where safe.
    local function ApplySmartDefaults()
        for _, entry in ipairs(EUI_DEFAULTS) do
            local cvar, preferred = entry[1], entry[2]
            if IsAtBlizzardDefault(cvar) then
                SetCVarSafe(cvar, preferred)
            end
        end
    end
    ApplySmartDefaults()

    -- Apply suppress lua errors on login (default: ON)
    if not EllesmereUIDB or EllesmereUIDB.suppressErrors ~= false then
        SetCVarSafe("scriptErrors", "0")
    end

    -- Optimized graphics settings are NOT re-applied on login: SetCVar already persists, so re-applying would override the user's manual adjustments.

    ---------------------------------------------------------------------------
    --  General page
    ---------------------------------------------------------------------------
    local function BuildGeneralPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  Optimized graphics CVar table + buttons (above all sections)
        -------------------------------------------------------------------
        local OPTIMIZED_CVARS = {
            { "graphicsShadowQuality",      "1" },
            { "graphicsLiquidDetail",       "0" },
            { "graphicsParticleDensity",    "5" },
            { "graphicsSSAO",              "0" },
            { "graphicsDepthEffects",       "0" },
            { "graphicsComputeEffects",     "0" },
            { "graphicsOutlineMode",        "0" },
            { "graphicsTextureResolution",  "2" },
            { "graphicsSpellDensity",       "0" },
            { "graphicsProjectedTextures",  "1" },
            { "graphicsViewDistance",        "0" },
            { "graphicsEnvironmentDetail",  "0" },
            { "graphicsGroundClutter",      "0" },
            { "RAIDsettingsEnabled",        "0" },
            { "ResampleAlwaysSharpen",      "1" },
            -- Reverb runs a full effect bus over the mix; disabling it trims audio DSP work and keeps spell/interrupt cues dry and crisp.
            { "Sound_EnableReverb",         "0" },
        }

        local function ApplyOptimizedGfx()
            -- Refused in combat, where SetGfxCVar writes nothing: a backup taken
            -- then would turn the card into Restore with nothing optimized.
            if InCombatLockdown() then return end
            if not EllesmereUIDB then EllesmereUIDB = {} end
            -- One-time store: only snapshot if no backup exists yet
            if not EllesmereUIDB.gfxBackup then
                local backup = {}
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    backup[entry[1]] = GetCVar(entry[1])
                end
                backup["Contrast"] = GetCVar("Contrast")
                EllesmereUIDB.gfxBackup = backup
            else
                -- Backfill CVars added to the list after the original snapshot so Restore covers them too.
                local backup = EllesmereUIDB.gfxBackup
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    if backup[entry[1]] == nil then
                        backup[entry[1]] = GetCVar(entry[1])
                    end
                end
            end
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                SetGfxCVar(entry[1], entry[2])
            end
            local curContrast = tonumber(GetCVar("Contrast")) or 50
            if curContrast <= 55 then
                SetGfxCVar("Contrast", curContrast + 10)
            end
            local rl = EllesmereUI._widgetRefreshList
            if rl then for i = 1, #rl do rl[i]() end end
        end

        local function RestoreGfxSettings()
            if not EllesmereUIDB or not EllesmereUIDB.gfxBackup then return end
            if InCombatLockdown() then return end
            local backup = EllesmereUIDB.gfxBackup
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                local saved = backup[entry[1]]
                if saved then SetGfxCVar(entry[1], saved) end
            end
            if backup["Contrast"] then SetGfxCVar("Contrast", backup["Contrast"]) end
            EllesmereUIDB.gfxBackup = nil
            local rl2 = EllesmereUI._widgetRefreshList
            if rl2 then for i = 1, #rl2 do rl2[i]() end end
        end

        -------------------------------------------------------------------
        --  TOP SECTION: one row, Reset ALL EUI Addon Settings | Optimize My FPS
        --  and Graphics | Uninstall EUI. While a graphics backup exists the
        --  Optimize card restores it instead.
        -------------------------------------------------------------------
        local MEDIA_ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
        -- Red for stop (Reset ALL, Uninstall, Restore), EllesmereUI's own green
        -- (#0cd29d) for go (Optimize and its link): fixed, never the theme accent.
        local WARN = { r = 0.9, g = 0.3, b = 0.3 }
        local GO = { r = 0x0c / 255, g = 0xd2 / 255, b = 0x9d / 255 }

        -- Reset ALL's wipe: every EUI addon back to its defaults.
        local function ResetAllNow()
            -- Nuclear wipe: same logic as the beta-exit popup
            local svNames = {
                "EllesmereUIActionBarsDB",
                "EllesmereUIAuraBuffRemindersDB",
                "EllesmereUICooldownManagerDB",
                "EllesmereUINameplatesDB",
                "EllesmereUIResourceBarsDB",
                "EllesmereUIUnitFramesDB",
            }
            for _, name in ipairs(svNames) do
                _G[name] = {}
            end
            local oldScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
            local oldScaleAuto = EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto
            -- Preserve friend group data across reset
            local oldGlobal = EllesmereUIDB and EllesmereUIDB.global
            local savedFriends
            if oldGlobal then
                savedFriends = {
                    friendGroups = oldGlobal.friendGroups,
                    friendAssignments = oldGlobal.friendAssignments,
                    friendGroupOrder = oldGlobal.friendGroupOrder,
                    friendGroupColors = oldGlobal.friendGroupColors,
                    friendNotes = oldGlobal.friendNotes,
                    friendFavCollapsed = oldGlobal.friendFavCollapsed,
                    friendPendingCollapsed = oldGlobal.friendPendingCollapsed,
                    friendUngroupedCollapsed = oldGlobal.friendUngroupedCollapsed,
                }
            end
            -- Preserve QoL settings (stored on EllesmereUIDB root)
            local qolKeys = {
                "autoOpenContainers", "autoSellJunk", "autoRepair",
                "autoRepairGuild", "hideScreenshotStatus", "autoUnwrapCollections",
                "trainAllButton", "ahCurrentExpansion", "quickLoot",
                "autoFillDelete", "skipCinematics", "skipCinematicsAuto",
                "bonusRollConfirmation", "bonusRollOnly",
                "autoInsertKeystone", "mythicKeystoneControls", "autoKeystoneReadyCheck",
                "autoStartKeystone", "quickSignup",
                "persistSignupNote", "signupNote", "hideBlizzardPartyFrame",
                "instanceResetAnnounce", "instanceResetAnnounceMsg",
                "macroFactory",
            }
            local savedQoL = {}
            for _, k in ipairs(qolKeys) do
                if EllesmereUIDB[k] ~= nil then
                    savedQoL[k] = EllesmereUIDB[k]
                end
            end
            -- Game settings, not EUI ones: the record of the settings from
            -- before EUI (Uninstall EUI) and Optimize Graphics' Restore values.
            local oldRestore = EllesmereUIDB.restoreOnUninstall
            local oldGfx = EllesmereUIDB.gfxBackup
            _G["EllesmereUIDB"] = {}
            EllesmereUIDB = _G["EllesmereUIDB"]
            EllesmereUIDB.restoreOnUninstall = oldRestore
            EllesmereUIDB.gfxBackup = oldGfx
            if oldScale then EllesmereUIDB.ppUIScale = oldScale end
            if oldScaleAuto ~= nil then EllesmereUIDB.ppUIScaleAuto = oldScaleAuto end
            if savedFriends then
                if not EllesmereUIDB.global then EllesmereUIDB.global = {} end
                for k, v in pairs(savedFriends) do
                    EllesmereUIDB.global[k] = v
                end
            end
            for k, v in pairs(savedQoL) do
                EllesmereUIDB[k] = v
            end
        end

        -- Reset ALL: a typed confirm, then the wipe and a reload. The reload is
        -- a RequestReload from onConfirm, not reload = true: a typed confirm
        -- cannot gate WoW Forever's /reload click, so there the wipe waits for
        -- the reload popup's Reload Now (and Later changes nothing).
        local function ConfirmResetAll()
            EllesmereUI:ShowConfirmPopup({
                title         = "Reset ALL Settings",
                -- The wipe replaces the whole account store, profiles included.
                message       = "Are you sure you want to reset ALL EUI addon settings to their defaults? This deletes ALL of your profiles, not just the current one, and reloads your UI.",
                disclaimer    = "Every profile on this account is deleted. Export any profile you want to keep first.",
                typeToConfirm = "Confirm",
                confirmText   = "Reset All & Reload",
                cancelText    = "Cancel",
                onConfirm     = function()
                    EllesmereUI.RequestReload(EllesmereUI.L("Reset ALL Settings"),
                        EllesmereUI.L("Reload to finish resetting EUI."), ResetAllNow)
                end,
            })
        end

        -- Uninstall EUI is refused in combat (it reloads) and while Edit Mode is open (it
        -- saves its own copy of the layouts on exit, over the ones put back). True when
        -- it was refused.
        local function UninstallRefused()
            local msg
            if InCombatLockdown() then
                msg = EllesmereUI.L("Uninstalling reloads the UI and cannot run in combat. Leave combat and try again.")
            elseif EllesmereUI.EditModeOpen() then
                msg = EllesmereUI.L("Close Edit Mode first, then try again.")
            end
            if not msg then return false end
            EllesmereUI:ShowConfirmPopup({
                title       = EllesmereUI.L("Uninstall EUI"),
                message     = msg,
                confirmText = EllesmereUI.L("OK"),
                hideCancel  = true,
            })
            return true
        end

        -- Uninstall EUI: puts back the game settings EllesmereUI changed, turns it off for
        -- every character and reloads (EllesmereUI_Uninstall.lua). Profiles are kept. The
        -- reload is a RequestReload from onConfirm, not reload = true: the refusal is
        -- checked again there, and reload = true would reload even when it is refused.
        local function ConfirmUninstall()
            if UninstallRefused() then return end
            local message = EllesmereUI.L("Puts back the game settings EUI changed, such as nameplate, action bar, chat and tooltip options, and turns EUI off for every character, then reloads the UI.") .. "\n\n"
                .. EllesmereUI.L("Your profiles are kept, so you can turn EUI back on later in the AddOns list.")
            if EllesmereUIDB and EllesmereUIDB.gfxBackup then
                message = message .. "\n\n" .. EllesmereUI.L("Graphics changed by Optimize My FPS and Graphics stay as they are. To undo them, click Restore My Graphics Settings first.")
            end
            EllesmereUI:ShowConfirmPopup({
                title         = EllesmereUI.L("Uninstall EUI"),
                message       = message,
                disclaimer    = (not EllesmereUI.UninstallKnowsOriginals())
                    and EllesmereUI.L("EUI was installed before it kept a record of your original settings, so the settings it still manages go back to the game's defaults.")
                    or nil,
                confirmText   = EllesmereUI.L("Uninstall & Reload"),
                cancelText    = EllesmereUI.L("Cancel"),
                onConfirm     = function()
                    if UninstallRefused() then return end
                    EllesmereUI.RequestReload(EllesmereUI.L("Uninstall EUI"),
                        EllesmereUI.L("Reload to finish uninstalling EUI."), EllesmereUI.Uninstall)
                end,
            })
        end

        -- The first card's two forms: Optimize, or Restore while a backup exists
        -- (restore given: that form, else the current one).
        local function HasGfxBackup() return (EllesmereUIDB and EllesmereUIDB.gfxBackup) ~= nil end
        local function GfxCardContent(restore)
            if restore == nil then restore = HasGfxBackup() end
            if restore then
                return MEDIA_ICONS .. "undo.png", EllesmereUI.L("Restore My Graphics Settings"),
                    EllesmereUI.L("Put back your graphics from before optimizing.")
            end
            return MEDIA_ICONS .. "optimize.png", EllesmereUI.L("Optimize My FPS and Graphics"),
                EllesmereUI.L("Tune graphics for higher FPS and clarity.")
        end

        -- One row of plain text buttons: Reset ALL, then in the middle Optimize
        -- (a boxed button, with its "What Does This Do?" link under it) or
        -- Restore (plain and red like the others), then Uninstall.
        local GFX_GAP = 8

        -- "What Does This Do?": what Optimize changes. Built first, so the
        -- card's footer can take its measured height.
        local infoBtn = CreateFrame("Button", nil, parent)
        infoBtn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local infoH
        do
            local EG = GO
            local infoFS = infoBtn:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(EllesmereUI.EXPRESSWAY, 12, EllesmereUI.GetFontOutlineFlag())
            infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70)
            infoFS:SetText(EllesmereUI.L("What Does This Do?"))
            infoFS:SetPoint("TOP")
            infoH = math.ceil(infoFS:GetStringHeight())
            infoBtn:SetSize(infoFS:GetStringWidth() + 10, infoH)
            infoBtn:SetScript("OnEnter", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            infoBtn:SetScript("OnLeave", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70) end)
            -- Three parts, each its own translation.
            local CHANGES = "What we change:\n\n"
                .. "Shadow Quality - Fair (balanced quality/FPS)\n"
                .. "Liquid Detail - Disabled\n"
                .. "Particle Density - Set to Ultra (keeps important spell effects)\n"
                .. "SSAO (Ambient Occlusion) - Disabled\n"
                .. "Depth Effects - Disabled\n"
                .. "Compute Effects - Disabled\n"
                .. "Outline Mode - Disabled\n"
                .. "Texture Resolution - Set to High\n"
                .. "Spell Density - Set to Essential\n"
                .. "Projected Textures - Enabled (needed for ground effects)\n"
                .. "View Distance - Reduced to 1\n"
                .. "Environment Detail - Reduced to 1\n"
                .. "Ground Clutter - Reduced to 1\n"
                .. "Raid/Dungeon Settings - Uses same settings everywhere\n"
                .. "Resample Sharpening - Enabled (crisper image)\n"
                .. "Contrast - Boosted by +10 (if currently 55 or below)\n"
                .. "Enable Reverb - Disabled (spell and interrupt audio cues stay crisp)\n\n"
                .. "These settings prioritize frame rate and visual clarity over environmental detail. Textures stay high quality so your character and the world still look perfect."
            infoBtn:SetScript("OnClick", function()
                EllesmereUI:ShowInfoPopup({
                    title = "FPS & Graphics Optimization",
                    content = EllesmereUI.L("This feature optimizes your in-game graphics settings to give you the best combination of high FPS and visual clarity.")
                        .. "\n\n" .. EllesmereUI.L("After optimizing, the button changes to 'Restore My Graphics Settings', which reverts every change.")
                        .. "\n\n\n" .. EllesmereUI.L(CHANGES),
                })
            end)
        end

        -- "What Does This Do?" explains Optimize, so it and its gap exist only
        -- in the Optimize form: under Restore the row has no footer and the
        -- page below moves up. A click that changes the form rebuilds the
        -- page for it. Its text keeps one width for both forms.
        local showInfo = not HasGfxBackup()
        local gfxIcon, gfxTitle, gfxDesc = GfxCardContent()
        local _, altTitle, altDesc = GfxCardContent(showInfo)
        local cards
        y, cards = EllesmereUI.BuildActionCardRow(parent, y, {
            { icon = MEDIA_ICONS .. "sync.png", accent = WARN,
              title = EllesmereUI.L("Reset ALL EUI Addon Settings"),
              desc = EllesmereUI.L("Return every EUI addon to its defaults."),
              onClick = ConfirmResetAll },
            { icon = gfxIcon, title = gfxTitle, desc = gfxDesc,
              hero = showInfo, accent = showInfo and GO or WARN,
              sizeAlso = { altTitle, altDesc },
              onClick = function()
                  local had = HasGfxBackup()
                  if had then RestoreGfxSettings() else ApplyOptimizedGfx() end
                  if HasGfxBackup() ~= had then EllesmereUI:RefreshPage(true) end
              end },
            -- power.png's glyph fills its whole canvas: drawn smaller, it matches sync.png.
            { icon = MEDIA_ICONS .. "power.png", accent = WARN, iconSize = 22,
              title = EllesmereUI.L("Uninstall EUI"), desc = EllesmereUI.L("Revert EUI's changes and disable."),
              onClick = ConfirmUninstall },
        }, { inline = true, footer = showInfo and (GFX_GAP + infoH) or nil })
        local gfxCard = cards[2]
        -- The link rides the card: clearing the page search shows every
        -- top-level page frame again, which would bring it back over Restore.
        infoBtn:SetParent(gfxCard)
        infoBtn:SetFrameLevel(gfxCard:GetFrameLevel() + 5)
        infoBtn:SetShown(showInfo)
        EllesmereUI.RegisterWidgetRefresh(function() gfxCard:SetCardContent(GfxCardContent()) end)
        PP.Point(infoBtn, "TOP", gfxCard, "BOTTOM", 0, -GFX_GAP)
        y = y - 6

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        local themeValues = {}
        for _, name in ipairs(EllesmereUI.THEME_ORDER) do
            themeValues[name] = name
        end

        -- Row 1: UI Accent Color | EUI Options Theme
        local themeRow
        themeRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="UI Accent Color",
              tooltip="Sets the accent color used across all EllesmereUI elements (tabs, glows, highlights, borders). Defaults to your theme color.",
              swatches = {
                { tooltip = "Class Color",
                  getValue = function()
                      local cr, cg, cb = EllesmereUI.GetPlayerClassColor()
                      return cr, cg, cb, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      -- Per-profile: set use-class, then re-resolve + apply live.
                      EllesmereUI.SetActiveProfileAccent(nil, true)
                      EllesmereUI.RefreshAccent()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return (select(1, EllesmereUI.GetActiveAccentState())) and 1 or 0.3
                  end },
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local _, ca = EllesmereUI.GetActiveAccentState()
                      if ca then return ca.r, ca.g, ca.b, 1 end
                      return EllesmereUI.DEFAULT_ACCENT_R, EllesmereUI.DEFAULT_ACCENT_G, EllesmereUI.DEFAULT_ACCENT_B, 1
                  end,
                  setValue = function(r, g, b)
                      -- Persists per-profile (custom + useClass=false), applies live.
                      EllesmereUI.SetAccentColor(r, g, b)
                  end,
                  onClick = function(self)
                      if select(1, EllesmereUI.GetActiveAccentState()) then
                          -- Switch class -> custom: clear the per-profile class flag and re-resolve (profile custom -> global -> theme).
                          EllesmereUI.SetActiveProfileAccent(nil, false)
                          EllesmereUI.RefreshAccent()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return (select(1, EllesmereUI.GetActiveAccentState())) and 0.3 or 1
                  end },
              } },
            { type="dropdown", text="EUI Options Theme",
              values=themeValues,
              order=EllesmereUI.THEME_ORDER,
              getValue=function()
                return EllesmereUI.GetActiveTheme()
              end,
              setValue=function(v)
                EllesmereUI.SetActiveTheme(v)
                -- Re-resolve the accent so the sidebar highlight tracks the theme.
                if EllesmereUI.RefreshAccent then
                    EllesmereUI.RefreshAccent()  -- ApplyAccentLive already refreshes the page
                else
                    EllesmereUI:RefreshPage()
                end
              end }
        );  y = y - h

        -- Inline color swatch on EUI Options Theme (right region)
        if not EllesmereUI._prebuilding then
            local rightRgn = themeRow._rightRegion
            local function isCustomColorOff()
                return EllesmereUI.GetActiveTheme() ~= "Custom Color"
            end

            local tcGet = function()
                local db = EllesmereUIDB
                local sa = db and db.accentColor
                if sa then return sa.r, sa.g, sa.b, 1 end
                return EllesmereUI.GetAccentColor()
            end
            local tcSet = function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.accentColor = { r = r, g = g, b = b }
                -- Only update the window background, not the accent color
                if EllesmereUI._applyBgTint then
                    EllesmereUI._applyBgTint(r, g, b)
                end
            end
            local tcSwatch, tcUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, tcGet, tcSet, nil, 20)
            PP.Point(tcSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = tcSwatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isCustomColorOff()
                tcSwatch:SetAlpha(off and 0.15 or 1)
                tcSwatch:EnableMouse(not off)
                tcUpdateSwatch()
            end)
            tcSwatch:SetAlpha(isCustomColorOff() and 0.15 or 1)
            tcSwatch:EnableMouse(not isCustomColorOff())
            tcSwatch:SetScript("OnEnter", function(self)
                if isCustomColorOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "This option is only available for the Custom Color Theme")
                end
            end)
            tcSwatch:SetScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
            end)
        end

        -- EUI Options Language (Row 2's right slot): options-panel display language (auto-detects the client; untranslated text falls back to English).
        local langCfg
        do
            -- _noLoc: the language list itself is never translated, so a player who booted the wrong language can always read and change it.
            local langValues = {
                _noLoc = true,
                ["auto"] = { text = EllesmereUI.L("Automatic (Client)") },
                ["enUS"] = { text = "English" },
                ["deDE"] = { text = "Deutsch" },
                ["frFR"] = { text = "Français" },
                ["esES"] = { text = "Español (EU)" },
                ["esMX"] = { text = "Español (LatAm)" },
                ["itIT"] = { text = "Italiano" },
                ["ptBR"] = { text = "Português (BR)" },
                ["ruRU"] = { text = "Русский" },
                ["koKR"] = { text = "한국어 (Korean)" },
                ["zhCN"] = { text = "简体中文 (Simplified Chinese)" },
                ["zhTW"] = { text = "繁體中文 (Traditional Chinese)" },
            }
            local langOrder = { "auto", "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
            -- Pin each entry to the plain font its own script needs, independent
            -- of whichever display locale is currently active.
            for _, key in ipairs(langOrder) do
                langValues[key].font = LP_FontFor(key)
            end
            -- "auto"'s own text is translated, not a fixed native-script name, so
            -- its script follows the ACTIVE locale rather than its own key.
            langValues["auto"].font = LP_FontFor(EllesmereUI.LOCALE)

            local function LanguageReload()
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reload Required",
                    message     = "Changing the language requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText  = "Later",
                    reload      = true,
                })
            end

            langCfg = { type="dropdown", text="EUI Options Language",
                tooltip="The display language for the EllesmereUI options panel. Auto follows your game client. Untranslated text falls back to English.",
                values=langValues, order=langOrder,
                getValue=function() return (EllesmereUIDB and EllesmereUIDB.displayLocale) or "auto" end,
                setValue=function(v)
                    if v == "auto" then v = nil end
                    if EllesmereUIDB then EllesmereUIDB.displayLocale = v end
                    LanguageReload()
                end }
        end

        -- Row 2: UI Scale | EUI Options Language
        _, h = W:DualRow(parent, y,
            { type="slider", text="UI Scale",
              min=0.40, max=1.00, step=0.01,
              tooltip="Sets the scale of the whole game UI. 0.53 = 0.5333 and 0.71 = 0.7111",
              tooltipOnControl=true,
              getValue=function()
                if EllesmereUI._uiScaleDragVal then
                    return EllesmereUI._uiScaleDragVal
                end
                return EllesmereUIDB and EllesmereUIDB.ppUIScale or EllesmereUI.PP.PixelBestSize()
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                -- Snap 0.53 to exact pixel-perfect 0.5333... (768/1440)
                if math.abs(v - 0.53) < 0.005 then v = 0.5333333333 end
                -- Snap 0.71 to exact pixel-perfect 0.7111... (768/1080)
                if math.abs(v - 0.71) < 0.005 then v = 0.7111111111 end
                EllesmereUI._uiScaleDragVal = v
                EllesmereUIDB.ppUIScaleAuto = false
                local mf = EllesmereUI._mainFrame
                local panelScaleBefore
                if mf then panelScaleBefore = mf:GetEffectiveScale() end
                EllesmereUI.PP.SetUIScale(v)
                if mf and panelScaleBefore then
                    local newEff = UIParent:GetEffectiveScale()
                    if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
                end
                if not EllesmereUI._uiScaleCleanup then
                    EllesmereUI._uiScaleCleanup = true
                    C_Timer.After(0, function()
                        if not EllesmereUI._sliderDragging then
                            EllesmereUI._uiScaleDragVal = nil
                            EllesmereUI:ShowConfirmPopup({
                                title = "UI Scale Changed",
                                message = "Blizzard's Edit Mode snapping may not work correctly until you reload your UI.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload    = true,
                            })
                        end
                        EllesmereUI._uiScaleCleanup = false
                    end)
                end
              end },
            langCfg
        );  y = y - h

        -- Row 3: EUI Buttons (merged button toggles) | Disable Sync Icons (+ cog)
        -- "EUI Buttons" merges the Pause Menu, Unlock Mode Menu and Minimap
        -- toggles into one checkbox-dropdown over the SAME backend variables: front-end grouping only, settings/defaults unchanged.
        local euiBtnItems = {
            { key = "pause",   label = "Hide Pause Menu Button",
              tooltip = "Hides the EllesmereUI button from the game's Escape/pause menu." },
            { key = "unlock",  label = "Hide Unlock Mode Menu Button",
              tooltip = "Hides the Unlock Mode button from the game's Escape/pause menu. You can still toggle Unlock Mode from the EUI options panel." },
            { key = "minimap", label = "Show Minimap Button" },
        }
        local euiBtnRow
        euiBtnRow, h = W:DualRow(parent, y,
            { type="dropdown", text="EUI Buttons",
              tooltip="Toggle EllesmereUI's optional buttons: the Escape menu buttons and the minimap button.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Disable Sync Icons",
              tooltip="Hides the sync icons on the sidebar module list.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideSyncIcons or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideSyncIcons = v
                  if EllesmereUI._refreshAllSyncIcons then EllesmereUI._refreshAllSyncIcons() end
              end }
        );  y = y - h
        -- EUI Buttons checkbox-dropdown (left region)
        if not EllesmereUI._prebuilding then
            local rgn = euiBtnRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                euiBtnItems,
                function(k)
                    if k == "pause" then
                        return EllesmereUIDB and EllesmereUIDB.hideGameMenuButton or false
                    elseif k == "unlock" then
                        return not EllesmereUIDB or EllesmereUIDB.hideUnlockMenuButton ~= false
                    elseif k == "minimap" then
                        return not (EllesmereUIDB and EllesmereUIDB.showMinimapButton == false)
                    end
                    return false
                end,
                function(k, v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if k == "pause" then
                        EllesmereUIDB.hideGameMenuButton = v
                    elseif k == "unlock" then
                        EllesmereUIDB.hideUnlockMenuButton = v
                    elseif k == "minimap" then
                        EllesmereUIDB.showMinimapButton = v
                        if v then EllesmereUI.ShowMinimapButton() else EllesmereUI.HideMinimapButton() end
                    end
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        -- Cog with "Only Hide Fully Synced" toggle on Disable Sync Icons (right region)
        if not EllesmereUI._prebuilding then
            local rgn = euiBtnRow._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Sync Icon Options",
                rows = {
                    { type="toggle", label="Only Hide Fully Synced",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.hideSyncIconsOnlyFull or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.hideSyncIconsOnlyFull = v
                          if EllesmereUI._refreshAllSyncIcons then EllesmereUI._refreshAllSyncIcons() end
                      end },
                },
            })
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "COMBAT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Camera Distance",
              min=1, max=2.6, step=0.1,
              getValue=function() return GetCVarNum("cameraDistanceMaxZoomFactor") end,
              setValue=function(v)
                v = floor(v * 10 + 0.5) / 10
                SetCVarSafe("cameraDistanceMaxZoomFactor", v)
              end },
            { type="toggle", text="Increase Game Image Quality",
              tooltip="Enables sharpening to improve image clarity. Especially noticeable at lower render scales.",
              getValue=function() return GetCVarBool("ResampleAlwaysSharpen") end,
              setValue=function(v)
                SetGfxCVar("ResampleAlwaysSharpen", v and "1" or "0")
              end });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Cast Actions on Key Down",
              tooltip="Keybinds respond on key down instead of key up. This helps make your abilities feel more responsive.",
              getValue=function() return GetCVarBool("ActionButtonUseKeyDown") end,
              setValue=function(v)
                SetCVarSafe("ActionButtonUseKeyDown", v and "1" or "0")
                if _G._EAB_ApplyKeyDown then _G._EAB_ApplyKeyDown() end
              end },
            { type="slider", text="Lag Tolerance",
              tooltip="This is the Spell Queue Window, it helps with making sure you can't queue up too many spells at once which makes the game feel laggy. Recommended settings are generally a minimum of 200 + your local ping. If you are unsure of exactly what this setting does, leave it at 400.",
              min=0, max=400, step=1,
              getValue=function() return GetCVarNum("SpellQueueWindow") end,
              setValue=function(v)
                SetCVarSafe("SpellQueueWindow", v)
              end });  y = y - h

        local FCT_FONT_DIR = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
        local fctFontValues = {
            ["default"]                                = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" },
            [FCT_FONT_DIR .. "Expressway.TTF"]         = { text = "Expressway",            font = FCT_FONT_DIR .. "Expressway.TTF" },
            [FCT_FONT_DIR .. "Avant Garde Naowh.ttf"]        = { text = "Avant Garde",   font = FCT_FONT_DIR .. "Avant Garde Naowh.ttf" },
            [FCT_FONT_DIR .. "Arial Bold.TTF"]         = { text = "Arial Bold",            font = FCT_FONT_DIR .. "Arial Bold.TTF" },
            [FCT_FONT_DIR .. "Poppins.ttf"]            = { text = "Poppins",               font = FCT_FONT_DIR .. "Poppins.ttf" },
            [FCT_FONT_DIR .. "FiraSans Medium.ttf"]    = { text = "Fira Sans Medium",      font = FCT_FONT_DIR .. "FiraSans Medium.ttf" },
            [FCT_FONT_DIR .. "Expressway CAPS.ttf"]    = { text = "Expressway CAPS",       font = FCT_FONT_DIR .. "Expressway CAPS.ttf" },
            [FCT_FONT_DIR .. "Arial Narrow.ttf"]       = { text = "Arial Narrow",          font = FCT_FONT_DIR .. "Arial Narrow.ttf" },
            [FCT_FONT_DIR .. "Changa.ttf"]             = { text = "Changa",                font = FCT_FONT_DIR .. "Changa.ttf" },
            [FCT_FONT_DIR .. "Cinzel Decorative.ttf"]  = { text = "Cinzel Decorative",     font = FCT_FONT_DIR .. "Cinzel Decorative.ttf" },
            [FCT_FONT_DIR .. "Exo.otf"]                = { text = "Exo",                   font = FCT_FONT_DIR .. "Exo.otf" },
            [FCT_FONT_DIR .. "FiraSans Bold.ttf"]      = { text = "Fira Sans Bold",        font = FCT_FONT_DIR .. "FiraSans Bold.ttf" },
            [FCT_FONT_DIR .. "FiraSans Light.ttf"]     = { text = "Fira Sans Light",       font = FCT_FONT_DIR .. "FiraSans Light.ttf" },
            [FCT_FONT_DIR .. "Future X Black.otf"]     = { text = "Future X Black",        font = FCT_FONT_DIR .. "Future X Black.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow Ultra.otf"] = { text = "Gotham Narrow Ultra",  font = FCT_FONT_DIR .. "Gotham Narrow Ultra.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow.otf"]      = { text = "Gotham Narrow",         font = FCT_FONT_DIR .. "Gotham Narrow.otf" },
            [FCT_FONT_DIR .. "Russo One.ttf"]          = { text = "Russo One",             font = FCT_FONT_DIR .. "Russo One.ttf" },
            [FCT_FONT_DIR .. "Ubuntu.ttf"]             = { text = "Ubuntu",                font = FCT_FONT_DIR .. "Ubuntu.ttf" },
            [FCT_FONT_DIR .. "Homespun.ttf"]           = { text = "Homespun",              font = FCT_FONT_DIR .. "Homespun.ttf" },
            [FCT_FONT_DIR .. "HWT Artz.ttf"]           = { text = "HWT Artz",              font = FCT_FONT_DIR .. "HWT Artz.ttf" },
            ["Fonts\\FRIZQT__.TTF"]                    = { text = "Friz Quadrata",         font = "Fonts\\FRIZQT__.TTF" },
            ["Fonts\\ARIALN.TTF"]                      = { text = "Arial",                 font = "Fonts\\ARIALN.TTF" },
            ["Fonts\\MORPHEUS.TTF"]                    = { text = "Morpheus",              font = "Fonts\\MORPHEUS.TTF" },
            ["Fonts\\skurri.ttf"]                      = { text = "Skurri",                font = "Fonts\\skurri.ttf" },
        }
        local fctFontOrder = {
            "default",
            FCT_FONT_DIR .. "Expressway.TTF",
            FCT_FONT_DIR .. "Avant Garde Naowh.ttf",
            FCT_FONT_DIR .. "Arial Bold.TTF",
            FCT_FONT_DIR .. "Poppins.ttf",
            FCT_FONT_DIR .. "FiraSans Medium.ttf",
            FCT_FONT_DIR .. "Expressway CAPS.ttf",
            "---",
            FCT_FONT_DIR .. "Arial Narrow.ttf",
            FCT_FONT_DIR .. "Changa.ttf",
            FCT_FONT_DIR .. "Cinzel Decorative.ttf",
            FCT_FONT_DIR .. "Exo.otf",
            FCT_FONT_DIR .. "FiraSans Bold.ttf",
            FCT_FONT_DIR .. "FiraSans Light.ttf",
            FCT_FONT_DIR .. "Future X Black.otf",
            FCT_FONT_DIR .. "Gotham Narrow Ultra.otf",
            FCT_FONT_DIR .. "Gotham Narrow.otf",
            FCT_FONT_DIR .. "Russo One.ttf",
            FCT_FONT_DIR .. "Ubuntu.ttf",
            FCT_FONT_DIR .. "Homespun.ttf",
            FCT_FONT_DIR .. "HWT Artz.ttf",
            "Fonts\\FRIZQT__.TTF",
            "Fonts\\ARIALN.TTF",
            "Fonts\\MORPHEUS.TTF",
            "Fonts\\skurri.ttf",
        }
        EllesmereUI.AppendSharedMediaFonts(fctFontValues, fctFontOrder)

        -- Combat Text (checkbox dropdown + size cog) | Combat Text Font. The
        -- dropdown is a view over the five floating combat text CVars; the three
        -- damage extras only apply while Damage is on.
        local function DmgOff() return not GetCVarBool("floatingCombatTextCombatDamage_v2") end
        local dmgTip = EllesmereUI.DisabledTooltip("Damage")
        local COMBAT_TEXT = {
            { key="floatingCombatTextCombatDamage_v2",            label="Damage" },
            { key="floatingCombatTextCombatHealing_v2",           label="Healing" },
            { key="floatingCombatTextCombatLogPeriodicSpells_v2", label="Periodic Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextPetMeleeDamage_v2",          label="Pet Melee Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextPetSpellDamage_v2",          label="Pet Spell Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
        }
        local combatTextRow
        combatTextRow, h = W:DualRow(parent, y,
            { type="label", text="Combat Text" },
            { type="dropdown", text="Combat Text Font",
              tooltip="WARNING: This feature requires you to re-log or restart WoW to take effect.",
              tooltipOpts={ color={1, 0.3, 0.3} },
              values = fctFontValues, order = fctFontOrder,
              getValue=function()
                return (EllesmereUIDB and EllesmereUIDB.fctFont) or "default"
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                if v == "default" then
                    EllesmereUIDB.fctFont = nil
                    EllesmereUIDB.fctFontPath = nil
                    EllesmereUIDB.fctFontPathFor = nil
                else
                    EllesmereUIDB.fctFont = v
                    -- smf: keys cache their resolved path for the next login's
                    -- early window; see ApplyCombatTextFont in Startup.
                    local e = v:match("^smf:") and fctFontValues[v]
                    EllesmereUIDB.fctFontPath = e and e.font
                    EllesmereUIDB.fctFontPathFor = e and v
                end
                EllesmereUI:ShowConfirmPopup({
                    title   = "Logout Required",
                    message = "Combat text font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                    confirmText = "Okay",
                    cancelText  = "Later",
                })
              end });  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = combatTextRow._leftRegion
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, COMBAT_TEXT,
                function(key) return GetCVarBool(key) end,
                function(key, v) SetCVarSafe(key, v and "1" or "0") end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.RESIZE_ICON, title = "Combat Text Size",
                rows = {
                    { type="slider", label="Size", min=0.5, max=2.5, step=0.1,
                      get=function() return GetCVarNum("WorldTextScale_v2") end,
                      set=function(v)
                          v = floor(v * 10 + 0.5) / 10
                          SetCVarSafe("WorldTextScale_v2", v)
                      end },
                },
            })
        end

        -- Swiftmend Brightness Fix (Druid only)
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Prevent Swiftmend Icon Dim",
                  tooltip="Prevents Blizzard from dimming Swiftmend on action bars and CDM based on Efflorescence state.",
                  getValue=function()
                      return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
                  end,
                  setValue=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.brightenSwiftmend = v
                      if v then
                          if _G._EAB_ScanSwiftmend then _G._EAB_ScanSwiftmend() end
                          if _G._ECDM_ScanSwiftmend then _G._ECDM_ScanSwiftmend() end
                      end
                  end },
                { type="label", text="" }
            ); y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  DEVELOPER -- both toggles are duplicated in Quality of Life
        --  (Suppress Lua Errors) and Blizzard UI Enhanced (Show Spell ID on
        --  Tooltip): hidden here when BOTH modules are loaded, shown if either is missing so the settings stay reachable.
        -------------------------------------------------------------------
        local _devDupesAvailable = C_AddOns and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("EllesmereUIQoL")
            and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
        if not _devDupesAvailable then
            _, h = W:SectionHeader(parent, "DEVELOPER", y);  y = y - h

            _, h = W:DualRow(parent, y,
                { type="toggle", text="Suppress Lua Errors",
                  getValue=function()
                    return not (EllesmereUIDB and EllesmereUIDB.suppressErrors == false)
                  end,
                  setValue=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.suppressErrors = v
                    SetCVarSafe("scriptErrors", v and "0" or "1")
                  end },
                { type="toggle", text="Show Spell ID on Tooltip",
                  getValue=function()
                    return EllesmereUIDB and EllesmereUIDB.showSpellID or false
                  end,
                  setValue=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.showSpellID = v
                    -- Engine-side combat aura-ID CVar rides this setting.
                    if EllesmereUI.SyncAuraSpellIDCVar then EllesmereUI.SyncAuraSpellIDCVar() end
                  end });  y = y - h

            _, h = W:Spacer(parent, y, 20);  y = y - h
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Re-read live CVars on panel open: widgets call their getter on each build, so a rebuild picks up external changes (addons, /console).
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI:GetActiveModule() == GLOBAL_KEY then
            EllesmereUI:RefreshPage()
        end
    end)

    ---------------------------------------------------------------------------
    --  Enabled Addons page
    ---------------------------------------------------------------------------

    -- Cleanup helper for profiles root (parented to scrollFrame, persists across page changes)
    local function CleanupProfilesRoot()
        if EllesmereUI._profilesRoot then
            EllesmereUI._profilesRoot:Hide()
            EllesmereUI._profilesRoot:SetParent(nil)
            EllesmereUI._profilesRoot = nil
        end
    end

    -- Profiles and Patch Notes are their own sidebar pages (registered below), so Global Settings owns General + Style + Fonts + Textures + Glows + Colors (Style second, beside General), plus Gamepad while a module it configures is loaded.
    local globalPages = { PAGE_GENERAL, PAGE_STYLE, PAGE_FONTS, PAGE_TEXTURES, PAGE_GLOWS, PAGE_COLORS }
    if EllesmereUI.ModuleNS("EllesmereUIActionBars") or EllesmereUI.ModuleNS("EllesmereUIUnitFrames")
       or EllesmereUI.ModuleNS("EllesmereUIResourceBars") then
        globalPages[#globalPages + 1] = PAGE_GAMEPAD
    end

    EllesmereUI:RegisterModule(GLOBAL_KEY, {
        title       = "Global Settings",
        description = "General options for all EllesmereUI addons.",
        pages       = globalPages,
        buildPage   = function(pageName, parent, yOffset)
            -- CleanupProfilesRoot hides/nils the LIVE _profilesRoot, not anything scoped to this pageName. An off-screen search pre-build
            -- cycles pageName through PAGE_GENERAL/PAGE_FONTS/PAGE_TEXTURES/PAGE_COLORS regardless of what the player has open, so it would yank their real Profiles
            -- page away. This module's config.pages never includes PAGE_PROFILES anyway.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_GENERAL then
                    return BuildGeneralPage(pageName, parent, yOffset)
                elseif pageName == PAGE_FONTS then
                    return _G._EUI_BuildFontsPage and _G._EUI_BuildFontsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_TEXTURES then
                    return _G._EUI_BuildTexturesPage and _G._EUI_BuildTexturesPage(pageName, parent, yOffset)
                elseif pageName == PAGE_GLOWS then
                    return _G._EUI_BuildGlowsPage and _G._EUI_BuildGlowsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_GAMEPAD then
                    return _G._EUI_BuildGamepadPage and _G._EUI_BuildGamepadPage(pageName, parent, yOffset)
                elseif pageName == PAGE_STYLE then
                    return _G._EUI_BuildStylePage and _G._EUI_BuildStylePage(pageName, parent, yOffset)
                elseif pageName == PAGE_COLORS then
                    return _G._EUI_BuildColorsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_WHATSNEW then
                    return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
                end
                return
            end
            -- Clean up profiles root when switching to a non-Profiles tab
            if pageName ~= PAGE_PROFILES then
                CleanupProfilesRoot()
            end
            if pageName == PAGE_GENERAL then
                return BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_FONTS then
                return _G._EUI_BuildFontsPage and _G._EUI_BuildFontsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TEXTURES then
                return _G._EUI_BuildTexturesPage and _G._EUI_BuildTexturesPage(pageName, parent, yOffset)
            elseif pageName == PAGE_GLOWS then
                return _G._EUI_BuildGlowsPage and _G._EUI_BuildGlowsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_GAMEPAD then
                return _G._EUI_BuildGamepadPage and _G._EUI_BuildGamepadPage(pageName, parent, yOffset)
            elseif pageName == PAGE_STYLE then
                return _G._EUI_BuildStylePage and _G._EUI_BuildStylePage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return _G._EUI_BuildColorsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PROFILES then
                return _G._EUI_BuildProfilesPage(pageName, parent, yOffset)
            elseif pageName == PAGE_WHATSNEW then
                return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_GLOWS then
                -- Glow sites bind per-bar and per-spec tables at build time (CDM bars,
                -- tracking bars); a spec swap or bar change behind a cached page would
                -- leave rows writing into stale tables. Rebuild on every return.
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == GLOBAL_KEY
                       and EllesmereUI:GetActivePage() == PAGE_GLOWS then
                        EllesmereUI:RefreshPage(true)
                    end
                end)
            end
            if pageName ~= PAGE_PROFILES then
                CleanupProfilesRoot()
            elseif pageName == PAGE_PROFILES and not EllesmereUI._profilesRoot then
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == GLOBAL_KEY then
                        _G._EUI_BuildProfilesPage(PAGE_PROFILES, nil, -6)
                    end
                end)
            end
        end,
        onReset     = function()
            -- Reset CVars to EUI preferred defaults (ignoring current state)
            for _, entry in ipairs(EUI_DEFAULTS) do
                SetCVarSafe(entry[1], entry[2])
            end
            -- Reset style/theme settings (accent color, custom theme, class-colored)
            EllesmereUI.ResetTheme()
            -- Reset all custom class, power, and resource colors to defaults
            if EllesmereUIDB then
                EllesmereUIDB.customColors = nil
            end
            -- Reset fonts to defaults
            if EllesmereUIDB then
                EllesmereUIDB.fonts = nil
            end
            EllesmereUI.InvalidateFontCache()
            EllesmereUI.ApplyColorsToOUF()
            -- Reset panel scale to 100%
            EllesmereUI:SetPanelScale(1.0)
            -- Reset right-click targeting to default (disabled = off)
            if EllesmereUIDB then
                EllesmereUIDB.disableRightClickTarget = false
                EllesmereUIDB.disableRightClickTargetAllyCombat = false
                -- FPS + Secondary Stats are per-profile now; turn them off for the active profile (QoLExtrasSet) so the visible widgets actually clear.
                if EllesmereUI.QoLExtrasSet then
                    EllesmereUI.QoLExtrasSet("showFPS", false)
                    EllesmereUI.QoLExtrasSet("showSecondaryStats", false)
                end
                EllesmereUIDB.guildChatPrivacy = false
                EllesmereUIDB.repairWarning = nil
                -- Reset UI scale so next reload re-snapshots from Blizzard default
                EllesmereUIDB.ppUIScale = nil
                EllesmereUIDB.ppUIScaleAuto = nil
                -- Developer settings defaults
                EllesmereUIDB.showSpellID = false
                if EllesmereUI.SyncAuraSpellIDCVar then EllesmereUI.SyncAuraSpellIDCVar() end
                EllesmereUIDB.suppressErrors = true
                -- Crosshair: the root is the inherited global default, reset here (per-profile overrides clear with the profile's own reset).
                -- Root off = profiles without an override inherit "None".
                EllesmereUIDB.crosshairSize = "None"
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
                -- Reset unlock mode layout data
                EllesmereUIDB.unlockAnchors = nil
                EllesmereUIDB.unlockWidthMatch = nil
                EllesmereUIDB.unlockHeightMatch = nil
                EllesmereUIDB.unlockWidthMatchExtra = nil
                EllesmereUIDB.unlockHeightMatchExtra = nil
                -- QoL Features are NOT reset here; they have their own module reset
            end
            if EllesmereUI._applyRightClickTarget then
                EllesmereUI._applyRightClickTarget()
            end
            EllesmereUI._applyHideBlizzardPartyFrame()
            -- One call for both: the FPS readout may be drawn by the Secondary
            -- Stats block, so the two owners have to re-evaluate together.
            if EllesmereUI._applyFPSDisplay then
                EllesmereUI._applyFPSDisplay()
            elseif EllesmereUI._applySecondaryStats then
                EllesmereUI._applySecondaryStats()
            end
            if EllesmereUI._applyCrosshair then
                EllesmereUI._applyCrosshair()
            end
            if EllesmereUI._applyGuildChatPrivacy then
                EllesmereUI._applyGuildChatPrivacy()
            end
            -- Apply suppress errors default (on)
            SetCVarSafe("scriptErrors", "0")
            EllesmereUI:SelectPage(PAGE_GENERAL)
        end,
    })

    -- Profiles & Presets: its own sidebar module, reusing the profiles page builder; the profiles-root lifecycle rides the shared
    -- CleanupProfilesRoot hooks below (keyed to PROFILES_KEY). Second tab: the Overrides management list (built by EllesmereUI_SpecOverrides.lua).
    --
    -- ONE tab, TWO pages: "Spec Overrides" and "Conditional Overrides" stay completely separate page builders with their own stores, prune
    -- passes and row logic. The tab strip shows one "Overrides" entry and a centered segmented toggle picks the builder (the same control
    -- Raid Frames uses for Simple Setup / Custom Buff Display). The mode is runtime-only, defaulting to the spec list.
    local PAGE_OVERRIDES = "Overrides"

    -- Builds the centered mode toggle, returning the vertical space used. Plain local closure on purpose: no widget row, no capture config, no saved state.
    local function BuildOverridesModeToggle(parent, y)
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local fontPath = (EllesmereUI.GetFontPath())
            or "Fonts\\FRIZQT__.TTF"
        -- Wider than the Raid Frames pair (162): "Conditional Overrides" is a longer label than "Custom Buff Display" and must not clip.
        local BTN_W, BTN_H = 180, 31
        local wrap = CreateFrame("Frame", nil, parent)
        wrap:SetSize(BTN_W * 2, BTN_H)
        wrap:SetPoint("TOP", parent, "TOP", 0, y - 14)
        wrap:SetFrameLevel(parent:GetFrameLevel() + 1)
        if EllesmereUI.PP then
            EllesmereUI.PP.CreateBorder(wrap, 1, 1, 1, 0.10, 1)
        end
        local MODES = {
            { key = "spec", label = "Spec Overrides" },
            { key = "cond", label = "Conditional Overrides" },
        }
        local cur = EllesmereUI._overridesTabMode or "spec"
        for i, m in ipairs(MODES) do
            local btn = CreateFrame("Button", nil, wrap)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("LEFT", wrap, "LEFT", (i - 1) * BTN_W, 0)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetPoint("CENTER")
            lbl:SetText(EllesmereUI.L(m.label))
            if cur == m.key then
                bg:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                lbl:SetTextColor(1, 1, 1, 1)
            else
                bg:SetColorTexture(0.10, 0.10, 0.11, 0.85)
                lbl:SetTextColor(1, 1, 1, 0.55)
                btn:SetScript("OnEnter", function()
                    bg:SetColorTexture(0.16, 0.16, 0.17, 0.9); lbl:SetTextColor(1, 1, 1, 0.85)
                end)
                btn:SetScript("OnLeave", function()
                    bg:SetColorTexture(0.10, 0.10, 0.11, 0.85); lbl:SetTextColor(1, 1, 1, 0.55)
                end)
                btn:SetScript("OnClick", function()
                    EllesmereUI._overridesTabMode = m.key
                    -- Forced: the two builders render entirely different rows.
                    EllesmereUI:RefreshPage(true)
                end)
            end
        end
        -- 14 above + 15 below the buttons.
        return BTN_H + 29
    end

    -- FULL EXPORT tab: a warning and one button, with its own exporter (EllesmereUI.ExportFullAccountData) sharing NO code path with the
    -- Profiles tab's export flow, so nothing here changes a normal profile string.
    local PAGE_FULLEXPORT = "Full Export"

    local function BuildFullExportPage(parent, yOffset)
        local PAD = EllesmereUI.CONTENT_PAD or 40
        local y = yOffset - 10
        local width = parent:GetWidth() - PAD * 2

        -- Warning card (red-bordered, full width).
        local warn = CreateFrame("Frame", nil, parent)
        warn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        warn:SetWidth(width)
        warn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local wbg = EllesmereUI.SolidTex(warn, "BACKGROUND", 0.10, 0.04, 0.04, 0.55)
        wbg:SetAllPoints()
        EllesmereUI.MakeBorder(warn, 0.8, 0.2, 0.2, 0.55)
        local wtext = EllesmereUI.MakeFont(warn, 13, nil, 1, 0.55, 0.55, 1)
        wtext:SetPoint("TOPLEFT", warn, "TOPLEFT", 16, -14)
        wtext:SetWidth(width - 32)
        wtext:SetJustifyH("LEFT")
        wtext:SetSpacing(3)
        wtext:SetText(EllesmereUI.L("This export includes cross profile settings that will overwrite the importing user's settings including Quality of Life, Hovercast and more that should typically not be shared with standard profiles. THIS IS NOT RECOMMENDED for public sharing of profiles."))
        warn:SetHeight((wtext:GetStringHeight() or 40) + 28)
        y = y - warn:GetHeight() - 40

        -- Centered export button.
        local BTN_W, BTN_H = 300, 38
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", parent, "TOP", 0, y)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local DARK_BG = EllesmereUI.DARK_BG
        local bbg = EllesmereUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bbg:SetAllPoints()
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local bbrd = EllesmereUI.MakeBorder(btn, EG.r, EG.g, EG.b, 0.5)
        local blbl = EllesmereUI.MakeFont(btn, 13, nil, EG.r, EG.g, EG.b, 1)
        blbl:SetAlpha(0.8)
        blbl:SetPoint("CENTER")
        blbl:SetText(EllesmereUI.L("Export All Data with Profile"))
        btn:SetScript("OnEnter", function()
            blbl:SetAlpha(1)
            if bbrd and bbrd.SetColor then bbrd:SetColor(EG.r, EG.g, EG.b, 0.9) end
        end)
        btn:SetScript("OnLeave", function()
            blbl:SetAlpha(0.8)
            if bbrd and bbrd.SetColor then bbrd:SetColor(EG.r, EG.g, EG.b, 0.5) end
        end)
        btn:SetScript("OnClick", function()
            local str = EllesmereUI.ExportFullAccountData()
            if str then
                EllesmereUI:ShowExportPopup(str)
            else
                EllesmereUI:ShowInfoPopup({
                    title = EllesmereUI.L("Export Failed"),
                    content = EllesmereUI.L("Could not build the export string."),
                })
            end
        end)
        y = y - BTN_H - 20

        return -y + 40
    end

    -- Runs the toggle, then the selected mode's builder. Builders return total content height measured from the ORIGINAL page top (they
    -- accumulate from the startY handed in), so the toggle's space is already included.
    local function BuildOverridesPage(parent, yOffset)
        local y = yOffset - BuildOverridesModeToggle(parent, yOffset)
        if (EllesmereUI._overridesTabMode or "spec") == "cond" then
            if EllesmereUI.Conditions_BuildListPage then
                return EllesmereUI.Conditions_BuildListPage(parent, y)
            end
        elseif EllesmereUI.SpecOverrides_BuildListPage then
            return EllesmereUI.SpecOverrides_BuildListPage(parent, y)
        end
        return 200
    end
    -- PAGE_PRESETS is a NAVIGATION tab only: the in-game browser is retired, so the tab shows the presets-website popup over the normal Profiles page.
    -- The tab builds the profiles page and flips it to the presets subpage via the pending flag consumed at the end of _G._EUI_BuildProfilesPage.
    EllesmereUI:RegisterModule(PROFILES_KEY, {
        title       = "Profiles & Presets",
        description = "Import, export, and switch EllesmereUI profiles and presets.",
        pages       = { PAGE_PROFILES, PAGE_PRESETS, PAGE_OVERRIDES, PAGE_FULLEXPORT },
        buildPage   = function(pageName, parent, yOffset)
            -- _G._EUI_BuildProfilesPage bypasses `parent` and builds onto the live shared _scrollFrame, and first checks the active profile against the
            -- current spec -- it can call SwitchProfile/RefreshAllAddons and pop a "Reload Required" confirmation. None of that is safe from a
            -- hidden indexing pass, so skip PAGE_PROFILES; it indexes on the player's first visit.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_OVERRIDES then
                    -- Index the spec list only: the conditional builder is not part of the hidden pre-build pass, and the toggle is chrome.
                    if EllesmereUI.SpecOverrides_BuildListPage then
                        return EllesmereUI.SpecOverrides_BuildListPage(parent, yOffset)
                    end
                    return 200
                end
                return
            end
            if pageName == PAGE_OVERRIDES then
                CleanupProfilesRoot()
                return BuildOverridesPage(parent, yOffset)
            end
            if pageName == PAGE_FULLEXPORT then
                CleanupProfilesRoot()
                return BuildFullExportPage(parent, yOffset)
            end
            if pageName == PAGE_PRESETS then
                -- The in-game presets browser is retired: the tab opens the
                -- website popup (copyable link) over the normal Profiles page.
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                return _G._EUI_BuildProfilesPage(PAGE_PROFILES, parent, yOffset)
            end
            return _G._EUI_BuildProfilesPage(pageName, parent, yOffset)
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_FULLEXPORT then
                -- The Profiles page builds onto the SHARED profiles root, which outlives page switches, so a cached Full Export page would show
                -- profiles content layered over it. The page itself is static, so cleanup is enough -- no rebuild.
                CleanupProfilesRoot()
            elseif pageName == PAGE_OVERRIDES then
                CleanupProfilesRoot()
                -- The override list changes while the page is cached; rebuild.
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY
                       and EllesmereUI:GetActivePage() == pageName then
                        EllesmereUI:RefreshPage(true)
                    end
                end)
            elseif pageName == PAGE_PRESETS then
                -- Retired browser: the tab shows the website popup over the
                -- normal Profiles view. An active API import session wins --
                -- re-enter it instead of hiding its import page.
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                if EllesmereUI._profilesRoot then
                    local s = EllesmereUI._apiImportSession
                    if s and s.state ~= "done" then
                        if EllesmereUI._ProfilesConsumeApiImport then
                            EllesmereUI._ProfilesConsumeApiImport()
                        end
                    elseif EllesmereUI._ProfilesResetToMain then
                        EllesmereUI._ProfilesResetToMain()
                    end
                else
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == PROFILES_KEY
                           and EllesmereUI:GetActivePage() == PAGE_PRESETS then
                            _G._EUI_BuildProfilesPage(PAGE_PROFILES, nil, -6)
                        end
                    end)
                end
            elseif not EllesmereUI._profilesRoot then
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY then
                        _G._EUI_BuildProfilesPage(PAGE_PROFILES, nil, -6)
                    end
                end)
            else
                -- Shared root is alive but the Presets tab may have left its subpage showing; the Profiles tab lands on main. An active API
                -- import session wins -- re-enter instead of hiding its page.
                local s = EllesmereUI._apiImportSession
                if s and s.state ~= "done" then
                    if EllesmereUI._ProfilesConsumeApiImport then
                        EllesmereUI._ProfilesConsumeApiImport()
                    end
                elseif EllesmereUI._ProfilesResetToMain then
                    EllesmereUI._ProfilesResetToMain()
                end
            end
        end,
    })

    -- The Presets tab is a dummy trigger: clicking it opens the website popup
    -- and must NOT become the active page (no tab underline, current page
    -- stays). All tab clicks route through SelectPage, so intercept it here;
    -- the PAGE_PRESETS buildPage/cache-restore branches above remain only as
    -- fallbacks for programmatic selects that bypass this wrapper.
    do
        local origSelectPage = EllesmereUI.SelectPage
        function EllesmereUI:SelectPage(pageName, ...)
            if pageName == PAGE_PRESETS and self.GetActiveModule
               and self:GetActiveModule() == PROFILES_KEY then
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                return
            end
            return origSelectPage(self, pageName, ...)
        end
    end

    -- Patch Notes: its own sidebar module (patch notes + the EUI Legends
    -- donor celebration page). Suite-only, never registered in standalone builds.
    if not IS_STANDALONE then
        EllesmereUI:RegisterModule(PATCHNOTES_KEY, {
            title       = "Patch Notes",
            description = EllesmereUI.L("What's new in EllesmereUI."),
            pages       = { PAGE_WHATSNEW, PAGE_LEGENDS },
            buildPage   = function(pageName, parent, yOffset)
                if pageName == PAGE_LEGENDS then
                    return EllesmereUI._BuildLegendsPage(pageName, parent, yOffset)
                end
                return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end,
        })

        -- Window Scale: the header's panel scale slider, left of the collapse box and
        -- centred on the close X. 5% steps from 75% to 200%: a drag shows its value
        -- live and applies on release, the mouse wheel steps one notch per tick, and
        -- every change glides with the track pinned (SetPanelScale), so the slider
        -- never slides out from under the cursor. Built on the first open.
        local scaleCtl, ScaleCtlRefresh
        local function BuildScaleControl()
            local ca = EllesmereUI._clickArea
            if scaleCtl or not ca then return end
            local MIN = EllesmereUI.PANEL_SCALE_MIN * 100
            local MAX = EllesmereUI.PANEL_SCALE_MAX * 100
            local STEP, TRACK_W, PCT_W = 5, 110, 40
            local ctl = CreateFrame("Frame", nil, ca)
            scaleCtl = ctl
            ctl:SetFrameLevel(ca:GetFrameLevel() + 20)
            ctl:SetHeight(24)
            ctl:SetPoint("RIGHT", ca, "TOPRIGHT", -110, -31)

            local pctFs = EllesmereUI.MakeFont(ctl, 13, nil, 1, 1, 1, 0.9)
            pctFs:SetWidth(PCT_W)
            pctFs:SetJustifyH("RIGHT")
            pctFs:SetPoint("RIGHT", ctl, "RIGHT", 0, 0)
            local function ShowPct(v)
                pctFs:SetText(string.format("%d%%", math.floor(v + 0.5)))
            end
            local function SavedPct()
                return ((EllesmereUIDB and EllesmereUIDB.panelScale) or 1) * 100
            end

            local pending   -- the dragged value, shown until the release applies it
            local track, valBox, refresh
            local function Apply(v)
                ShowPct(v)
                if math.abs(v - SavedPct()) < 0.01 then return end
                EllesmereUI:SetPanelScale(v / 100, track)
            end
            track, valBox, refresh = EllesmereUI.BuildSliderCore(ctl, TRACK_W, 4, 12, PCT_W, 20, 12, 0.5,
                MIN, MAX, STEP,
                function() return pending or SavedPct() end,
                function(v)
                    if EllesmereUI._sliderDragging then
                        pending = v
                        ShowPct(v)
                        return
                    end
                    pending = nil
                    Apply(v)
                end, true)
            valBox:Hide()   -- the plain readout replaces the input box
            track:SetPoint("RIGHT", pctFs, "LEFT", -10, 0)

            local label = EllesmereUI.MakeFont(ctl, 13, nil, 1, 1, 1, 0.6)
            label:SetText(EllesmereUI.L("Window Scale"))
            label:SetPoint("RIGHT", track, "LEFT", -16, 0)
            -- The whole control takes the wheel; clicks off the track still reach the
            -- click area below (the window drag).
            ctl:SetWidth(PCT_W + 10 + TRACK_W + 16 + label:GetStringWidth())
            ctl:EnableMouseWheel(true)
            ctl:SetScript("OnMouseWheel", function(_, delta)
                if EllesmereUI._sliderDragging then return end
                if EllesmereUI:StepPanelScale(delta, track) then
                    ShowPct(SavedPct())
                    refresh()
                end
            end)

            ScaleCtlRefresh = function()
                pending = nil
                ShowPct(SavedPct())
                refresh()
            end
            ScaleCtlRefresh()
            -- Shift + mouse wheel elsewhere on the panel steps the scale too: the
            -- readout follows at once and an accent outline round the control (a
            -- padded host, our own frame) lights up and fades, so the change is easy
            -- to trace. Each step restarts the fade.
            local glowHost = CreateFrame("Frame", nil, ctl)
            glowHost:SetPoint("TOPLEFT", ctl, "TOPLEFT", -10, 6)
            glowHost:SetPoint("BOTTOMRIGHT", ctl, "BOTTOMRIGHT", 8, -6)
            local PlayGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })
            EllesmereUI._FlashWindowScale = function()
                ScaleCtlRefresh()
                PlayGlow(glowHost)
            end
            EllesmereUI.RegAccent({ type = "callback", fn = function() refresh() end })
            -- Any scale change (this slider, Reset) lands here once its glide ends.
            if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
            EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = function()
                if not EllesmereUI._sliderDragging then ScaleCtlRefresh() end
            end
        end
        local function ScaleCtlOnShow()
            if scaleCtl then ScaleCtlRefresh() else BuildScaleControl() end
        end
        EllesmereUI:RegisterOnShow(ScaleCtlOnShow)
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then ScaleCtlOnShow() end

        -- "Special thanks to: <donor>" right-aligned under the header's close X,
        -- re-rolled on every panel open (weighted by _PickLegendsThanks); a click
        -- opens the EUI Legends page. Built on the first open.
        local thanksBtn
        local function RollThanks()
            local ca = EllesmereUI._clickArea
            if not ca then return end
            local name = EllesmereUI._PickLegendsThanks()
            if not name then
                if thanksBtn then thanksBtn:Hide() end
                return
            end
            if not thanksBtn then
                thanksBtn = CreateFrame("Button", nil, ca)
                thanksBtn:SetFrameLevel(ca:GetFrameLevel() + 20)
                thanksBtn:SetHeight(20)
                -- Right edge on the painted close box's, just below it.
                thanksBtn:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -12, -54)
                local nameFs = EllesmereUI.MakeFont(thanksBtn, 13, nil, 1, 1, 1, 0.9)
                nameFs:SetPoint("RIGHT", thanksBtn, "RIGHT", 0, 0)
                local prefixFs = EllesmereUI.MakeFont(thanksBtn, 13, nil, 1, 1, 1, 0.45)
                prefixFs:SetPoint("RIGHT", nameFs, "LEFT", -4, 0)
                prefixFs:SetText(EllesmereUI.L("Special thanks to:"))
                thanksBtn._nameFs, thanksBtn._prefixFs = nameFs, prefixFs
                thanksBtn:SetScript("OnEnter", function(self)
                    self._prefixFs:SetAlpha(0.75)
                    self._nameFs:SetAlpha(1)
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("View EUI Legends"))
                end)
                thanksBtn:SetScript("OnLeave", function(self)
                    self._prefixFs:SetAlpha(0.45)
                    self._nameFs:SetAlpha(0.9)
                    EllesmereUI.HideWidgetTooltip()
                end)
                thanksBtn:SetScript("OnClick", function()
                    EllesmereUI.HideWidgetTooltip()
                    EllesmereUI:SelectModule(PATCHNOTES_KEY)
                    EllesmereUI:SelectPage(PAGE_LEGENDS)
                end)
            end
            local EG = EllesmereUI.ELLESMERE_GREEN
            thanksBtn._nameFs:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            thanksBtn._nameFs:SetText(name)
            thanksBtn:SetWidth(thanksBtn._nameFs:GetStringWidth() + 4 + thanksBtn._prefixFs:GetStringWidth())
            thanksBtn:Show()
        end
        EllesmereUI:RegisterOnShow(RollThanks)
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then RollThanks() end
    end

    -- Clean up profiles root when panel closes
    EllesmereUI:RegisterOnHide(function()
        CleanupProfilesRoot()
    end)

    -- Clean up profiles root when switching to any module other than Profiles
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName ~= PROFILES_KEY then
                CleanupProfilesRoot()
            end
        end)
    end

    -- Hook for HideAllChildren (framework calls this on page rebuilds)
    local origHideRoots = EllesmereUI._hideScrollFrameRoots
    EllesmereUI._hideScrollFrameRoots = function()
        if origHideRoots then origHideRoots() end
        CleanupProfilesRoot()
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
