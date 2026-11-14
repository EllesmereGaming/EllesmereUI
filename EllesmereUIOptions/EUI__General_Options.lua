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

-- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

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
local PAGE_NUMBERS     = "Numbers"   -- Number Format page; body lives in EUI_NumberFormat_Options.lua
local PAGE_PROFILES    = "Profiles"
local PAGE_PRESETS     = "Presets"   -- navigation tab over the presets subpage of the profiles page
local PAGE_WHATSNEW    = "Patch Notes"
local PAGE_LEGENDS     = "EUI Legends"

-- Profiles/Patch Notes/EUI Legends are their own sidebar pages, not tabs under Global Settings. Keys match the sidebar buttons in EllesmereUI_Panel.lua.
local PROFILES_KEY     = "_EUIProfiles"
local PATCHNOTES_KEY   = "_EUIPatchNotes"
local LEGENDS_KEY      = "_EUILegends"

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
--    seasonYear  : the season's year
--    topSeasonal : rank-ordered top three donors this season (1st, 2nd, 3rd)
--    donors      : the all-time donor wall, numbered in this order
--  The staff table below the block is edited by hand:
--    staff       : grouped team sections ({ group, members } tables)
-------------------------------------------------------------------------------
-- BEGIN GENERATED DONORS
EllesmereUI._LEGENDS = {
    season      = "fall",
    seasonYear  = "2026",
    topSeasonal = { "Khardi", "Drekonus", "Ani" },
    donors = {
        "Thias", "StickyMittens", "Xeno", "Delasteve",
        "Toxik", "Lily", "Pelleas", "Kulia",
        "GamingGrammers", "Khardi", "Cartridgebros", "Ani",
        "Lurn", "fizzle_crunk", "Tzahal", "Venalis",
        "Natasi", "Drekonus", "Quiim", "Ferniss",
        "Keato03", "Capa", "e_luvin", "ccpoppin1",
        "Arjax", "Excelvior", "Marple_V", "shy_x00",
        "Vall", "Collie", "arxTank",
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
        "andybergon", "TF0rd", "Stanzilla", "Caedis", "PapaPixels",
        "ericellb", "takiguru", "Laxxzz", "defnotjec", "Zankyo",
        "Hasenburg", "eXhausted", "thoriphes", "jlauner", "msromike",
        "cassidymichael", "jixinliu666", "Cawfee", "Jetro974", "RoakStatic",
        "zanthor", "denis-makula", "brokencrown", "Tzahal", "Aelexe",
        "grant-shoemaker", "mariusch", "Nialoshaar", "lkshrk", "PeluxGit",
        "tekert", "friberg1991", "steakbbq",
    } },
    { group = "Multi-language Support Contributors", members = {
        "LoChinAn", "Crazyyoungs", "Barbiero", "Dlarge", "labrie75",
        "tenngoxars", "Shiyan66666", "Absol3m", "alvaro1929",
    } },
}

-- Seasonal accents: a palette (first entry leads, colouring the Seasonal Legend
-- spotlight) and the drift of the small particles in its column. dir -1 falls,
-- dir 1 rises; size/dur are {min, max} ranges; spin is total degrees.
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

-- Weighted pick for the options header's thanks line, in percent: the
-- Seasonal Legend and the All-Time Legend 25 each, the two #2s 10 each, the
-- two #3s 5 each, and every other all-time donor an even share of the last
-- 20. A name holding two spots adds both up; a spot nobody holds drops out and
-- the others scale up to fill it.
local _thanksNames, _thanksWeights, _thanksIndex = {}, {}, {}
-- Adds w to a name's chance, listing the name the first time.
local function AddThanks(who, w)
    if not who or who == "" then return end
    local i = _thanksIndex[who]
    if i then
        _thanksWeights[i] = _thanksWeights[i] + w
    else
        i = #_thanksNames + 1
        _thanksNames[i], _thanksWeights[i], _thanksIndex[who] = who, w, i
    end
end
function EllesmereUI._PickLegendsThanks()
    local data = EllesmereUI._LEGENDS
    if not data then return nil end
    local names, weights, index = _thanksNames, _thanksWeights, _thanksIndex
    wipe(names); wipe(weights); wipe(index)
    local top, donors = data.topSeasonal or {}, data.donors or {}
    AddThanks(top[1], 25); AddThanks(donors[1], 25)
    AddThanks(top[2], 10); AddThanks(donors[2], 10)
    AddThanks(top[3], 5);  AddThanks(donors[3], 5)
    -- Every other all-time donor (one holding none of the spots above) shares
    -- the last 20 evenly: count them first (false marks one counted but not
    -- listed yet), then list each once.
    local rest = 0
    for i = 1, #donors do
        local who = donors[i]
        if who and who ~= "" and index[who] == nil then index[who] = false; rest = rest + 1 end
    end
    for i = 1, #donors do
        if index[donors[i]] == false then AddThanks(donors[i], 20 / rest) end
    end
    local count = #names
    if count == 0 then return nil end
    local total = 0
    for i = 1, count do total = total + weights[i] end
    local roll = math.random() * total
    for i = 1, count do
        roll = roll - weights[i]
        if roll <= 0 then return names[i] end
    end
    return names[count]
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
        version = "9.8.5",
        thanks = true,
        features = {
            {
                -- The Sleeping Bag row of WOW FOREVER on the Auras, Buffs & Consumables page; Show Below is in its
                -- cog and in Well Fed's (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Show Below (Minutes)",
                desc    = "The Sleeping Bag and Well Fed reminders can also show a set number of minutes before their buff runs out, with a countdown; in each reminder's cog, off by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "WOW FOREVER", highlight = "Sleeping Bag" } or nil,
            },
            {
                -- The Flag/Hide Owned Items toggle of MERCHANT OPTIONS in the Merchant card of Window Skins (both
                -- clients).
                module = "Blizzard Skins+",
                title  = "Flag/Hide Owned Items",
                desc   = "Vendor items you already have (known recipes, mounts, pets, toys) can be tinted red, and under Expand Vendor UI a button hides them; off by default",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "MERCHANT OPTIONS", highlight = "Flag/Hide Owned Items" },
            },
            {
                -- The Reskin Timer Bars toggle of BLIZZARD BARS, POPUPS & BUTTONS on the Tooltips & Menus page (both
                -- clients).
                module = "Blizzard Skins+",
                title  = "Reskin Timer Bars",
                desc   = "An optional reskin for the breath, fatigue and feign death bars, with its own colors, texture, border and name text; off by default",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups", section = "BLIZZARD BARS, POPUPS & BUTTONS", highlight = "Reskin Timer Bars" },
            },
            {
                -- The Show Alt List toggle of ALT LIST in the Mail card of Window Skins (the list is new on WoW
                -- Forever; retail has had it).
                module  = "Blizzard Skins+",
                forever = true,
                title   = "Mail Alt List",
                desc    = "The Mail card's Alt List is now available, with Guild and Friends tabs beside your own characters; off by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "ALT LIST", highlight = "Show Alt List" } or nil,
            },
            {
                -- The Also Wake On dropdown of IDLE FADE on the Chat page (both clients).
                module = "Chat",
                title  = "Also Wake On",
                desc   = "The idle fade can also wake on emotes, loot, skill-ups, reputation, system messages, achievements or NPC speech; off by default",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "IDLE FADE", highlight = "Also Wake On" },
            },
            {
                -- The Loot History row of SOURCES on Forever Essentials' Loot page (WoW Forever only).
                module  = "Forever Essentials",
                forever = true,
                title   = "Loot History",
                desc    = "The Loot Feed can keep your latest rows per character, also after a reload; hold Shift and turn the mouse wheel over the feed to look back, off by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Loot", section = "SOURCES", highlight = "Loot History" } or nil,
            },
            {
                -- The Show Map Markers row of WORLD MAP on Forever Essentials' General page; the kinds are in its
                -- cog (WoW Forever only).
                module  = "Forever Essentials",
                forever = true,
                title   = "Map Markers by Kind",
                desc    = "Boats, zeppelins, skycutters, the tram, portals, dungeons, raids, zone exits and flight points each have their own toggle, in the cog and in the world map's filter menu",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General", section = "WORLD MAP", highlight = "Show Map Markers" } or nil,
            },
            {
                -- The Raid Role Icons row of DISPLAY on the Premade Search page (retail only: WoW Forever has no
                -- premade group list).
                module = "Group Finder",
                retail = true,
                title  = "Raid Role Icons",
                desc   = "Raid groups can show Blizzard's own tank, healer and damage circles in place of ours",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "DISPLAY", highlight = "Raid Role Icons" } or nil,
            },
            {
                -- The Row Highlight row of RESULTS LIST on the Premade Search page; the style, the colors and
                -- Delisted Opacity are in its cog (retail only).
                module = "Group Finder",
                retail = true,
                title  = "Row Highlight",
                desc   = "Status Effect is now Row Highlight: a Signed Up status of its own, a None style, and delisted groups greyed out with a Delisted Opacity slider",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "RESULTS LIST", highlight = "Row Highlight" } or nil,
            },
            {
                -- The Target, Focus & Hover page, one of the two new tabs with a header preview (both clients).
                module = "Nameplates",
                title  = "Settings Overhaul",
                desc   = "Nameplates' settings are regrouped into five tabs; the new Target, Focus & Hover and Friendly tabs show live previews you can click to jump to a setting, and friendly players gain a Name Color and a health percent position",
                nav    = { module = "EllesmereUINameplates", page = "Target, Focus & Hover" },
            },
            {
                -- The Friendly Nameplate Style row of FRIENDLY PLAYERS on the Friendly page; both options are in
                -- its cog (both clients).
                module = "Nameplates",
                title  = "Nameplate Size and Group Brackets",
                desc   = "The new cog on Friendly Nameplate Style sets the size of Blizzard's own nameplates, which still show for friendly players inside instances, and can put colored brackets around the names of your party and raid members",
                nav    = { module = "EllesmereUINameplates", page = "Friendly Plates", section = "FRIENDLY PLAYERS", highlight = "Friendly Nameplate Style" },
            },
            {
                -- The Cast Bar Y Offset row of HEALTH AND CAST BAR on the Enemy (Display) page; X Offset is in its
                -- cog (both clients).
                module = "Nameplates",
                title  = "Cast Bar X Offset",
                desc   = "A new cog on Cast Bar Y Offset moves the enemy cast bar left or right; the spell icon follows",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "HEALTH AND CAST BAR", highlight = "Cast Bar Y Offset" },
            },
            {
                -- The Add Friendly Boss Group row of FRIENDLY BOSS FRAMES on the Raid (Frames) page; Follow Dark
                -- Mode is in its cog (both clients).
                module = "Raid & Party Frames",
                title  = "Boss Frames Follow Dark Mode",
                desc   = "A new option in the Friendly Boss Group cog turns the friendly boss frames dark with the raid frames' Dark Mode; off, they keep Boss Health Color",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "FRIENDLY BOSS FRAMES", highlight = "Add Friendly Boss Group" },
            },
            {
                -- The Fill Color row of HEALTH BAR on the Raid (Frames) page; the thresholds are in its cog (both
                -- clients).
                module = "Raid & Party Frames",
                title  = "Gradient Thresholds",
                desc   = "With Custom Dynamic Colors, the Fill Color cog has Low and High thresholds: below Low the 0% color holds fully, above High the 100% color does",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "HEALTH BAR", highlight = "Fill Color" },
            },
            {
                -- The Fill Color row of PET FRAMES on the Party page (both clients).
                module = "Raid & Party Frames",
                title  = "Pet and Party Target Colors",
                desc   = "Pet frames have their own Fill Color and Name Color, and party targets gain Custom Dynamic Colors and a Text Color",
                nav    = { module = "EllesmereUIRaidFrames", page = "Party", section = "PET FRAMES", highlight = "Fill Color" },
            },
            {
                -- The OTHER BARS section at the end of the Cast Bar page (both clients).
                module = "Resource Bars",
                title  = "Breath, Fatigue and Countdown Bars",
                desc   = "Breath, Fatigue, Feign Death, the battleground start and group countdowns can show on bars drawn like your cast bar, each with its own color and an optional low warning; off by default",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar", section = "OTHER BARS" },
            },
            {
                -- The Player Aura Bars page; the VISIBILITY section is on the Buffs and the Debuffs bar (both
                -- clients).
                module = "Unit Frames",
                title  = "Buffs and Debuffs Bar Visibility",
                desc   = "The default Buffs and Debuffs bars of Player Aura Bars have a Visibility setting like other elements (in combat, mouseover, hide while mounted and more) and a Hidden Opacity slider to keep a faint bar instead of hiding it",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                -- The Fill Color row of HEALTH BAR on the Mini Frames page; the boss frames have the same row (both
                -- clients).
                module = "Unit Frames",
                title  = "Mini and Boss Frame Fill Colors",
                desc   = "Target of Target, Focus Target, Pet and the boss frames can use Classic and Custom Dynamic Colors, picked from a Fill Color dropdown",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames", section = "HEALTH BAR", highlight = "Fill Color" },
            },
        },
        fixes = {
            { module = "Action Bars", forever = true, text = "Empty action bar slots no longer show a stack count after logging in or reloading." },
            { module = "Bags", text = "Recipes and items that become usable through a skill rank lose their red tint without a reload." },
            { module = "Bags", text = "Other addons can now add their own views of your bags to the sidebar; junk keeps its own section." },
            { module = "Bags", text = "Sorting in OneBag now shows the items move round by round and finishes sooner." },
            { module = "Bags", text = "The gold summary on hover can now show silver and copper too: pick Only Gold, Gold and Silver, or all three in the new cog on Gold Tracking and History; WoW Forever starts on Gold and Silver." },
            { module = "Bags", forever = true, text = "The bank no longer shows warband gold or its Deposit and Withdraw buttons, which did nothing there." },
            { module = "Blizzard Skins+", text = "Lines other addons add to tooltips now match the tooltip's text size and Font Size Scale." },
            { module = "Blizzard Skins+", text = "Bags' Tooltip Item Counts is now Item Counts under Tooltip Extras on the Tooltips & Menus tab, with the other tooltip settings; your setting carries over." },
            { module = "Blizzard Skins+", text = "The Mail Alt List has a cog in its title for Sort By, Max Characters Shown and Minimum Level, and can show ignored characters again." },
            { module = "Chat", forever = true, text = "Timestamp All Messages no longer fills the chat with lines that hold only a timestamp." },
            { module = "Cooldown Manager", text = "A bar with a Minimum Width or Height now keeps its icons at the edge it grows from and leaves the spare room at the other end, instead of centering them." },
            { module = "Cooldown Manager", text = "A cooldown set to Replace with Buff follows its bar's Proc Glow again on bars where a buff was ever added with the + button." },
            { module = "Cooldown Manager", forever = true, text = "The Anti-Clip Glow now also lights instant spells and short casts, for their last 1.5 seconds; before, they never lit while you were idle." },
            { module = "Cooldown Manager", forever = true, text = "The Arcane Blast buff icon now shows its duration swipe, countdown and stack count for mages." },
            { module = "Data Bars", text = "A Broker Plugin block now shows its plugin's text when the plugin publishes it as a number (an error count, for example), instead of only its icon." },
            { module = "Forever Essentials", forever = true, text = "Gathering Skill in Tooltips now recognizes ore nodes, and the herb nodes named unlike their herb, on non-English game clients whatever EUI Options Language is set." },
            { module = "Forever Essentials", forever = true, text = "Gathering Skill in Tooltips no longer has a Minimap option: the game now keeps the minimap tooltip's text from addons." },
            { module = "General", text = "In the settings, hovering a dropdown whose value is cut off now shows the whole value." },
            { module = "General", text = "In the settings, color swatches, keybind buttons, checkboxes and drag-to-reorder lists keep sharp edges at any UI Scale and Window Scale." },
            { module = "General", text = "In Unlock Mode, Exit, Save & Exit and the - / + size buttons of the top bar explain themselves on hover." },
            { module = "General", text = "In Unlock Mode, with the top bar hidden by Hover Top Bar or Shift, its greyed - and + buttons no longer catch clicks meant for the element under them." },
            { module = "General", text = "In Unlock Mode, element borders, the Blizzard Edit Mode overlays and the Save & Exit button follow a new accent color without a reload." },
            { module = "General", text = "With Apply to All Game Text on, the range dot on Blizzard's own action buttons and the WoW Forever controller bars no longer shows as boxes." },
            { module = "Group Finder", retail = true, text = "With the Group Finder window skin off, the applicant list, the filter menus, the expressions panel and the M+ applications bar now use Blizzard's look too." },
            { module = "Group Finder", retail = true, text = "The raids tab now keeps its own filters (regions, party fit, class, role counts, expression and Sort By) instead of sharing the dungeons tab's; it starts with none set." },
            { module = "Group Finder", retail = true, text = "Raid boss tooltips in the filters name the right raid." },
            { module = "Group Finder", retail = true, text = "Group members who are not the leader can hover and right-click applicants, with a Your group is forming note under the dungeon name." },
            { module = "Minimap", text = "Right-click menu choices of addon buttons kept in the Addon Buttons flyout work again." },
            { module = "Minimap", forever = true, text = "The middle-click micro menu no longer lists Adventure Guide and Housing, which raised an error, and shows Legacy in place of Achievements." },
            { module = "Nameplates", text = "A name in the top text position is no longer cut short by a raid marker, Rare/Quest icon, Quest Objective Text or faction badge placed at the left, right or bottom of the plate." },
            { module = "Nameplates", text = "Friendly name-only plates: a pet's or NPC's plate no longer shows a nearby player's name and guild." },
            { module = "Nameplates", text = "Important Cast Glow and Cast Targets You Glow: the Modern WoW Glow style now draws Blizzard's own nameplate cast bar glow, above the nameplate's borders and around the spell icon, in place of the action bar glow that covered the spell name and timer." },
            { module = "Nameplates", text = "Under the Nameplate friendly style, the guild line under friendly player names has its own Guild Text Size, in the new cog on Subtitle Text." },
            { module = "Nameplates", forever = true, text = "Paladins' tank threat colors follow Righteous Fury again after it is recast or lost in combat." },
            { module = "Nameplates", forever = true, text = "Hunters' out-of-range check (nameplate Range Check on Auto and the crosshair's out-of-range color) now uses your shot range instead of melee range." },
            { module = "Nameplates", forever = true, text = "Pandemic Glow Style is no longer offered, since debuffs have no pandemic window there and the glow never lit." },
            { module = "Nameplates", forever = true, text = "Under the WoW Forever nameplate style, friendly players in your party or raid take Blizzard's group color on their health bar unless Health Bar Color is set to Class Color." },
            { module = "Nameplates", forever = true, text = "Nameplates no longer show at a shorter range than Blizzard's own." },
            { module = "Quality of Life", text = "A Cast Bar Circle or GCD Circle set to Attach to Cursor no longer sits in the middle of the screen after logging in." },
            { module = "Quest Tracker", forever = true, text = "Sharing a quest from the Custom Quest Tracker's menu or the Quest Details window no longer raises an error in combat: Share is greyed until combat ends." },
            { module = "Raid & Party Frames", text = "With Party Frames in Small Raids on, a battleground shows the raid frames from the start instead of only group 1 until the tenth player arrives." },
            { module = "Raid & Party Frames", text = "With Show Self Last, a member who joins your party while you are in combat no longer lands on top of your own frame." },
            { module = "Raid & Party Frames", text = "Pet frames follow Dark Mode like the frames beside them, at the Dark Mode fill opacity." },
            { module = "Resource Bars", text = "The Classic WoW UI cast bar keeps its raised spark during a cast, and the Cast Bar options preview shows the bar's style on the first visit." },
            { module = "Resource Bars", forever = true, text = "On the WoW Forever look, the cast bar's frame, spell name, timer and spark sit aligned, and a channel's latency zone no longer shows a red corner." },
            { module = "Resource Bars", forever = true, text = "Warlock channels show their tick marks on the cast bar." },
            { module = "Resource Bars", forever = true, text = "A vertical Call Totem Bar opens its totem lists beside the bar, on the side the new Flyout Direction setting picks, instead of over its own buttons." },
            { module = "Unit Frames", text = "Shift, Ctrl or Alt + left-click on a unit, raid, party, pet or boss frame targets again and a modified right-click opens the menu, with click casting on too while left-click is Target." },
            { module = "Unit Frames", text = "A boss frame no longer keeps the previous unit's name and a full bar when an add takes over its boss slot mid-fight." },
            { module = "Unit Frames", text = "The power bar background on ordinary enemies keeps your Bar Background opacity instead of turning solid gray after a reload, and stays gray after you change a setting." },
            { module = "Unit Frames", forever = true, text = "On the WoW Forever look, the cast bar frame no longer covers the spell icon's edge, and the spell name and timer sit centered." },
            { module = "Unit Frames", forever = true, text = "On the WoW Forever look, the player, target, focus and boss bars end inside the frame's rim instead of a pixel over it." },
            { module = "Unit Frames", forever = true, text = "On the WoW Forever look, the animated rest icon sits above the portrait as on Blizzard's frame, and the frame art glows gold while you are resting." },
            { module = "Unit Frames", forever = true, text = "Channeled spells show their name on cast bars instead of the word Channeling." },
            { module = "Localization", text = "Brazilian Portuguese, Korean, Russian, Spanish and Traditional Chinese translations updated for the 9.8.4 options and patch notes." },
        },
    },
    {
        version = "9.8.4",
        thanks = true,
        features = {
            {
                -- The RAID BUFFS section of the Auras, Buffs & Consumables page; the buff is a box of its
                -- grid, named by the client (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Divine Spirit",
                desc    = "Raid Buffs now reminds priests who have Divine Spirit to keep it on the group, on by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "RAID BUFFS" } or nil,
            },
            {
                -- The Sleeping Bag row of WOW FOREVER on the Auras, Buffs & Consumables page (WoW Forever
                -- only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Sleeping Bag",
                desc    = "A reminder to use your Cozy Sleeping Bag while Well-Rested is missing or under 3 stacks, below max level; off by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "WOW FOREVER", highlight = "Sleeping Bag" } or nil,
            },
            {
                -- The Show Pinned Items row of CATEGORIES on the Bags page; Pins per Character is in its
                -- cog (both clients).
                module = "Bags",
                title  = "Pins per Character",
                desc   = "Each character keeps its own pinned items, starting from your current pins; turn Pins per Character off to share them again",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "CATEGORIES", highlight = "Show Pinned Items" },
            },
            {
                -- The DataBars page; Show Other Characters is in a Travel block's settings (both clients).
                module = "Data Bars",
                title  = "Other Characters' Hearthstones",
                desc   = "The Travel block's tooltip can list your other characters' hearthstones: where each is bound and when it is ready",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- The Loot Rolls row of SOURCES on Forever Essentials' Loot page (WoW Forever only).
                module  = "Forever Essentials",
                forever = true,
                title   = "Loot Rolls",
                desc    = "The Loot Feed can show who won each group loot roll and with what roll, and adds your roll to items you win; off by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Loot", section = "SOURCES", highlight = "Loot Rolls" } or nil,
            },
            {
                -- The Class Colored Role Icons row of APPLICANT LIST on the Premade Search page (retail
                -- only: WoW Forever has no premade group list).
                module = "Group Finder",
                retail = true,
                title  = "Class Colored Role Icons",
                desc   = "Applicants' role icons can take their class color instead of the role's, off by default",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "APPLICANT LIST", highlight = "Class Colored Role Icons" } or nil,
            },
            {
                -- The Show Group Notes row of DISPLAY on the Premade Search page (retail only).
                module = "Group Finder",
                retail = true,
                title  = "Group Notes",
                desc   = "Each group's note can show on a line under it in the results list, off by default",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "DISPLAY", highlight = "Show Group Notes" } or nil,
            },
            {
                -- The Row Highlight row of RESULTS LIST on the Premade Search page (this release named it
                -- Status Effect); its cog holds the style and the colors (retail only).
                module = "Group Finder",
                retail = true,
                title  = "Status Effect",
                desc   = "Groups you applied to can be tinted in their status color instead of underlined, with a color of your choice for each status",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "RESULTS LIST", highlight = "Row Highlight" } or nil,
            },
            {
                -- The Enemy Players Use Enemy Color row of ENEMY COLORS on the Nameplates Colors page (both
                -- clients).
                module = "Nameplates",
                title  = "Enemy Players Use Enemy Color",
                desc   = "Enemy players' health bars can take the Enemies color instead of their class color, off by default",
                nav    = { module = "EllesmereUINameplates", page = "Colors", section = "ENEMY COLORS", highlight = "Enemy Players Use Enemy Color" },
            },
            {
                -- CORE POSITIONS on the Nameplates Display page; the toggle is in the Quest Objective Text
                -- section of a slot's cog (both clients).
                module = "Nameplates",
                title  = "Quest Objective Type Icon",
                desc   = "Quest Objective Text can show a sword for kill objectives or a bag for item objectives beside the count, off by default",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS" },
            },
            {
                -- The Portrait Mode row of PORTRAIT on the Main Frames page with the Player frame selected;
                -- the toggle is in its cog (both clients).
                module = "Unit Frames",
                title  = "3D Portrait Below Border",
                desc   = "A 3D portrait in a detached shape can sit inside the shape's border instead of over it (Portrait Mode cog)",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "PORTRAIT", highlight = "Portrait Mode",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Cast Actions on Key Down now applies to key presses only: a mouse click on an action button acts when the mouse is released, as on Blizzard's bars, so dragging a button no longer uses it." },
            { module = "Action Bars", text = "A bar paged by a form, stance or modifier in its Paging settings shows the right page right after a /reload or login." },
            { module = "Action Bars", text = "Each bar can now hide its spell charges, stack counts or item counts from Text > Charge Numbers on the Bar Display page." },
            { module = "Action Bars", text = "Paging Options on the Bar Display page now turns modifier paging and target paging on separately for each bar." },
            { module = "Action Bars", forever = true, text = "A Skyriding Paging setting saved before that option was hidden no longer turns off Press and Hold Casting on Action Bar 1." },
            { module = "Bags", text = "Other addons can now add their own categories to your bags and bank; they show after your own." },
            { module = "Blizzard Skins+", forever = true, text = "Friends show their ruleset (Normal, PvP, Roleplay) after their zone on the friends list and in the friend tooltip, with their region when it is not yours." },
            { module = "Blizzard Skins+", forever = true, text = "Friends in your own region no longer get a region icon on the friends list." },
            { module = "Cooldown Manager", text = "Spells on Hidden CDs no longer show their tooltip when you hover something near your Cooldowns or Utility bar, such as the target frame." },
            { module = "Data Bars", text = "The Gold block's tooltip lists each character under its own realm or ruleset instead of putting everyone under the current one." },
            { module = "Forever Essentials", forever = true, text = "The Active Stance icon now follows a Hunter aspect or Paladin aura you switch in combat instead of catching up after the fight." },
            { module = "General", text = "With Apply to All Game Text on, the combat text over your character keeps the Combat Text Font, so it matches the numbers over enemies." },
            { module = "General", text = "Checkbox dropdowns show their checkboxes, and dropdown lists such as the Buff Manager's Extra Spells their icons, as soon as the list opens instead of staying blank until the pointer moves over them." },
            { module = "General", text = "Buttons, checkboxes, popups, cards and switches in the settings have rounded corners like the dropdowns, with crisp 1 px outlines at every Window Scale." },
            { module = "General", retail = true, text = "With Apply to All Game Text on, the Questing button in Premade Groups now uses your font like the other category buttons." },
            { module = "General", retail = true, text = "The M+ Portals menu on the Minimap and the Chat sidebar now closes when you click anywhere outside it." },
            { module = "General", forever = true, text = "The Profiles page's Assign to Spec now reads Assign to Class, and its popup asks for classes instead of specs." },
            { module = "Group Finder", retail = true, text = "Groups with a friend or guildmate in them now show their name in blue, as on Blizzard's list." },
            { module = "Group Finder", retail = true, text = "The sign-up timer now counts down from 5:00 instead of counting up." },
            { module = "Group Finder", retail = true, text = "Your Class is now a separate filter on the Dungeons and Raids tabs." },
            { module = "Group Finder", retail = true, text = "With the Group Finder window skin off, the results list, filter bar and dungeon squares now use Blizzard's look." },
            { module = "Group Finder", retail = true, text = "With Raider.IO, hovering an applicant in the applicant list shows their Raider.IO lines, and holding Shift shows their full profile beside the window." },
            { module = "Group Finder", retail = true, text = "The settings page shows sample groups and applicants at its top, updating as you change your settings, and every Group Finder option now lives there: the window's cog opens it." },
            { module = "Minimap", text = "The clock, zone text and FPS readout now draw above other addons' minimap icons instead of under them." },
            { module = "Minimap", text = "Clicking the tracking button while its menu is open now closes the menu instead of reopening it." },
            { module = "Minimap", forever = true, text = "Closing the tracking menu with the mouse under the Gamepad interface style no longer raises a blocked action error." },
            { module = "Nameplates", text = "Friendly NPC names in Name Only mode now show their raid marker, and Friendly NPC Settings can turn it off." },
            { module = "Nameplates", text = "With Simple Coloring When Not In M+ on, neutral enemies you fight take the All Enemies color outside dungeons, as hostile enemies do." },
            { module = "Quest Tracker", forever = true, text = "The Custom Quest Tracker now shows your tracked profession recipes and their reagents under a Professions header." },
            { module = "Raid & Party Frames", text = "With debuff Tooltips set to Shown on Modifier, debuffs placed outside a frame no longer leave an empty area that takes clicks for that member." },
            { module = "Raid & Party Frames", retail = true, text = "A spell ID typed into a Buff Manager indicator's Custom Spell ID, or into a filter with Add Spell ID, now tracks that exact spell alone instead of every version of the buff; Presets and Search Spells picks and the preset filters work as before, and IDs added before this update are unchanged until typed again." },
            { module = "Resource Bars", forever = true, text = "The Call Totem Bar no longer leaves its place mid-fight when you change form, mount or level up in combat." },
            { module = "Unit Frames", text = "The raid marker on the target and focus frames now follows a change of target when Show Raid Marker was turned on without a reload." },
            { module = "Unit Frames", text = "3D portraits on unit frames and party frames fade with the rest of the interface when the whole UI is faded out, instead of staying on screen." },
            { module = "Unit Frames", forever = true, text = "A druid's buffs and debuffs shown below the player frame now sit below the Mana + Form Power bar in Cat and Bear Form instead of hiding behind it." },
            { module = "Unit Frames", forever = true, text = "Player Aura Bars and raid frame filters that hold Food or Drink now show every rank of food and drink, not only the first." },
            { module = "Localization", text = "German, Korean, Russian, Spanish and Traditional Chinese translations updated for the 9.8.3 options and patch notes, with shorter Russian labels where they ran over." },
        },
    },
    {
        version = "9.8.3",
        thanks = true,
        features = {
            {
                -- The Action Picker row at the end of DISPLAY on the Auras, Buffs & Consumables page
                -- (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Action Picker",
                desc    = "Right-click a spell group or Class Buffs reminder to pick the spell its click casts, and scroll over a spell to pick its rank",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "DISPLAY", highlight = "Action Picker" } or nil,
            },
            {
                -- The Bags row of the EllesmereUI and WoW Forever cards on Global Settings > Style
                -- (WoW Forever only).
                module  = "Bags",
                forever = true,
                title   = "WoW Forever Style",
                desc    = "The bags and bank take the bronze WoW Forever frame and beveled slots, on while most of your modules use the WoW Forever look",
                nav     = EllesmereUI.IS_FOREVER and { module = "_EUIGlobal", page = "Style" } or nil,
            },
            {
                -- The Health Bar Color swatch on Class Colored Health Bar, in FRIENDLY PLAYERS on the
                -- Nameplates Friendly Plates page (both clients).
                module = "Nameplates",
                title  = "Friendly Health Bar Color",
                desc   = "Friendly Nameplate Settings has a Health Bar Color for friendly players' bars while Class Colored Health Bar is off",
                nav    = { module = "EllesmereUINameplates", page = "Friendly Plates", section = "FRIENDLY PLAYERS", highlight = "Class Colored Health Bar" },
            },
            {
                -- The Forms and Talents cog on the Visibility row of LAYOUT on the Swing Timer page
                -- (WoW Forever only).
                module  = "Resource Bars",
                forever = true,
                title   = "Swing Timer Forms & Talents",
                desc    = "Show the swing timer only in chosen druid forms, or only with or without chosen talents, such as Stormstrike for Enhancement",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Swing Timer", section = "LAYOUT", highlight = "Visibility" } or nil,
            },
            {
                -- Show Cast Bar in CAST BAR on the Mini Frames page with Pet selected (both clients; the
                -- section is built for the EllesmereUI pet frame).
                module = "Unit Frames",
                title  = "Pet Cast Bar",
                desc   = "The Pet frame can show a cast bar for your pet's spells, off by default; move it in Unlock Mode",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames", section = "CAST BAR", highlight = "Show Cast Bar",
                           preSelect = function() if EllesmereUI._setMiniUnit then EllesmereUI._setMiniUnit("pet") end; EllesmereUI._pendingMiniSelect = "pet" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Buttons bound to keys with special characters, like those on German or Nordic keyboards, show the pressed look while the key is held." },
            { module = "Bags", text = "The built-in category groups, The Armory and Adventure Prep, show in your language." },
            { module = "Bags", text = "Sort Items in All Items and the other category views also merges partial stacks, as OneBag does." },
            { module = "Bags", text = "Offline Bank saves your bank at every banker, and items taken out there are no longer marked as new; some bankers were missed before." },
            { module = "Bags", forever = true, text = "Clicking the keyring on the bag bar opens Blizzard's keyring window again." },
            { module = "Bags", forever = true, text = "Opening the bags no longer closes the game for some characters with equipment sets." },
            { module = "Blizzard Skins+", text = "The tooltip of an aura (Player Aura Bars, unit frame auras) takes your tooltip's Border Style, Size, Color and Offsets." },
            { module = "Blizzard Skins+", text = "The Tooltips & Menus page shows a sample tooltip and popup at its top, updating as you change your settings." },
            { module = "Blizzard Skins+", retail = true, text = "The Skyriding page shows a sample bar at its top, updating as you change your settings." },
            { module = "Cooldown Manager", forever = true, text = "Importing or switching to a profile keeps its Cooldown Manager layout and shows its spells at the rank you know; profiles an earlier import got wrong are repaired at your next login, unless you have changed them since." },
            { module = "Cooldown Manager", forever = true, text = "Cooldowns Blizzard's Cooldown Manager hides by default keep their place on your bars, and the bar preview tells you how to show them in game." },
            { module = "Forever Essentials", forever = true, text = "Simplified Stats no longer hides item stats from other addons, so their gear scores and upgrade arrows show again." },
            { module = "Forever Essentials", forever = true, text = "A class-colored flight timer bar uses your custom class colors from Global Settings > Colors." },
            { module = "General", text = "Class-colored unit frame texts, unit and raid frame portrait borders and the Movement Alert use your custom class colors from Global Settings > Colors." },
            { module = "General", text = "The Global Font shows on names and tooltips on the first login after starting the game, not only after a /reload." },
            { module = "General", text = "In a settings cog, a row dragged to a new spot in a reorderable list, such as the blessing priority lists, no longer disappears behind the list." },
            { module = "General", text = "In the settings, color swatch borders stay a sharp 1 pixel after a Window Scale change, checkbox dropdowns no longer show blurred double edges at some UI scales, and the search box in dropdown lists is evenly spaced." },
            { module = "General", forever = true, text = "Characters with the same first name no longer share per-character settings such as their spec profile, bag currency order and Cooldown Manager bar sizes." },
            { module = "Minimap", text = "Other addons' minimap buttons and pins follow the square minimap's edge instead of an invisible circle." },
            { module = "Nameplates", text = "With Show Friendly NPC Nameplates on, the game's interact icon shows again over friendly NPCs and objects such as herbs, ore and mailboxes." },
            { module = "Nameplates", text = "The Display page's preview stays centered with cropped aura icons above or below the bar." },
            { module = "Nameplates", retail = true, text = "Dispellable By Me in the Enemy Buff Filter cog also works with Important: important enemy buffs still show, the rest only when your group can remove them." },
            { module = "Quality of Life", text = "Auto Open Containers waits until the bank closes at every banker; some bankers were missed before." },
            { module = "Quest Tracker", forever = true, text = "The quest tracker's right-click menu shows Wowhead Link again while Wowhead Quest Links is on." },
            { module = "Quest Tracker", forever = true, text = "Quest timer bars in the Custom Quest Tracker show their fill." },
            { module = "Quickdraw", text = "The Spells list no longer stops halfway with a Lua error when your spellbook has a flyout, such as a mage's portals." },
            { module = "Raid & Party Frames", text = "Click Casting binds the macro you picked when an account and a character macro share a name (the binding list marks character macros with (C)), and picks up a macro's new text at once when you edit, rename or delete it." },
            { module = "Raid & Party Frames", forever = true, text = "The Dispels click-cast key casts the best dispel your character knows, without a \"Spell is not ready yet\" error on every press." },
            { module = "Raid & Party Frames", forever = true, text = "Druids' Dynamic Rez, in Click Casting and in Quickdraw, casts Revive out of combat and keeps Rebirth for combat." },
            { module = "Raid & Party Frames", forever = true, text = "The Missing Buffs blessing lists no longer offer Blessing of Light, which no longer exists." },
            { module = "Resource Bars", text = "With Expand Power Bar if No Resource on, a moved power bar keeps its expanded spot after logging in instead of covering the elements below it." },
            { module = "Resource Bars", forever = true, text = "Hiding a bar or its text per form now treats Dire Bear Form as Bear Form instead of Caster." },
            { module = "Resource Bars", forever = true, text = "With Mana Bar While Shapeshifted below the Power Bar, elements linked under the Power Bar stay clear of the mana bar after a shapeshift." },
            { module = "Resource Bars", forever = true, text = "The Swing Timer keeps the row height you set on every character, also after a reload or a spec or profile switch." },
            { module = "Unit Frames", text = "A text showing the raid group number updates as soon as you move to another group." },
            { module = "Unit Frames", text = "With Vertical Fill on, Health Bar Height goes up to 400 and Bar Width down to 20, for tall, slim bars." },
            { module = "Unit Frames", text = "The options preview of the Blizzard Style, Classic WoW UI and WoW Forever frames moves the left text by its X and Y offsets, as the frames do in game." },
            { module = "Unlock Mode", text = "With Hover Top Bar on, the top bar appears only when the cursor reaches the bar itself and stays hidden while the cursor is over an element, so it no longer gets in the way of elements at the top of the screen." },
            { module = "Localization", text = "German, Korean, Brazilian Portuguese, Spanish and Traditional Chinese translations updated, including the Unlock Mode controls help, the options search and the WoW Forever class and weapon buff reminders." },
        },
    },
    {
        version = "9.8.2",
        mini = true,
        features = {
            {
                -- The Class Buffs row beside Weapon Buffs in WOW FOREVER on the Auras, Buffs & Consumables
                -- page; a mage sees Mage Armors there and a warrior or rogue nothing (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Class Buffs",
                desc    = "Reminds you when your class's own buffs are missing, such as a Blessing, Inner Fire or Demon Armor, and casts them when clicked",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "WOW FOREVER", highlight = "Class Buffs" } or nil,
            },
            {
                -- The Add Custom Spell row of WOW FOREVER, the custom spells listed after it (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Custom Spell Reminders",
                desc    = "Click a custom spell or spell group reminder to cast its best known rank, and limit each custom spell to chosen classes",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "WOW FOREVER", highlight = "Add Custom Spell" } or nil,
            },
            {
                -- The CDM Bars page; the condition is in an icon's right-click menu in the preview
                -- (WoW Forever only).
                module  = "Cooldown Manager",
                forever = true,
                title   = "Talent Conditions",
                desc    = "Show a cooldown or utility icon only with or without chosen talents from your three trees (right-click the icon in the preview)",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUICooldownManager", page = "CDM Bars" } or nil,
            },
            {
                -- The RESULTS LIST section of the Premade Search page (retail only: WoW Forever has no
                -- premade group list).
                module = "Group Finder",
                retail = true,
                title  = "Quests and Custom Lists",
                desc   = "Quests and Custom use the Group Finder's own group list too, and zone groups show how many players they have",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "RESULTS LIST" } or nil,
            },
            {
                -- Unlock Mode's own top bar: the click opens Unlock Mode (no options page shows it).
                module  = "Unlock Mode",
                title   = "Top Bar Help",
                desc    = "Each top bar toggle explains itself on hover, and an info icon lists the keyboard and mouse controls",
                onClick = function() EllesmereUI.OpenUnlockModeAt() end,
            },
        },
        fixes = {
            { module = "Cooldown Manager", text = "On the Bar Glows page, a Glow When Usable glow shows its ability's icon and name instead of a question mark." },
            { module = "Cooldown Manager", forever = true, text = "A spell no longer shows twice in a bar's preview after you learn a new rank of it." },
            { module = "General", text = "On the Glows page, a collapsed module card's summary updates as soon as the template changes, and \"all match the template\" shows in green like the rows." },
            { module = "General", text = "The options search lists equal matches in a fixed order, finds pages by their tab name, and says so when nothing matches, with a link from a page's search to every module." },
            { module = "Group Finder", retail = true, text = "Right-clicking a group or an applicant in the lists shows other addons' menu entries again." },
            { module = "Group Finder", retail = true, text = "The dungeons picked in the Dungeons row stay picked after logging out and back in." },
            { module = "Group Finder", retail = true, text = "The group list scrolls and lets you pick a group when Quests or Custom is the first category you open." },
            { module = "Quality of Life", text = "Quick Loot closes the loot window when there is nothing to take." },
            { module = "Quickdraw", text = "A nested menu with nothing your character can use no longer shows as an empty entry." },
            { module = "Resource Bars", forever = true, text = "Power Text and Mana Bar Text no longer offer Smart Text, which chose by spec; bars that used it show the power value." },
            { module = "Unit Frames", forever = true, text = "Power Text no longer offers Smart Text, which chose by spec; frames that used it show the power value." },
            { module = "Localization", text = "Russian translations updated across nearly every option, popup and tooltip, Traditional Chinese translations updated, and Latin American Spanish shows the Spanish (Spain) text where it has no translation of its own, instead of English." },
        },
    },
    {
        version = "9.8.1",
        mini = true,
        features = {
            {
                -- The Weapon Buffs row of WOW FOREVER on the Auras, Buffs & Consumables page; its cog
                -- holds each hand's picks (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Weapon Buffs",
                desc    = "A new reminder for poisons, imbues, stones and oils on each weapon, shown a minute before they run out too; click it to apply one from your bags",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "WOW FOREVER", highlight = "Weapon Buffs" } or nil,
            },
            {
                -- The Custom Friends List Tiles | Tile Height row of DISPLAY in the Friends List card of
                -- Window Skins (WoW Forever only).
                module  = "Blizzard Skins+",
                forever = true,
                title   = "Custom Friends List Tiles",
                desc    = "The custom friends list can now be turned off on the Friends List card or turned on with Blizz Default, and online friends show Blizzard's online card color: in full under Blizz Default, faintly under the EllesmereUI and Modern looks",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "DISPLAY", highlight = "Custom Friends List Tiles" } or nil,
            },
            {
                -- The Auto Uprank Spells on Bars row of GENERAL on Forever Essentials' General page
                -- (WoW Forever only).
                module  = "Forever Essentials",
                forever = true,
                title   = "Pet Spell Ranks",
                desc    = "Auto Uprank Spells on Bars now also swaps your pet's new spell ranks on your action bars, and catches ranks learned while it was off or your pet was away",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General", section = "GENERAL", highlight = "Auto Uprank Spells on Bars" } or nil,
            },
            {
                -- The Enemy Buff Filter cog of EXTRA AURA OPTIONS on the Nameplates General page
                -- (retail only: WoW Forever keeps the filter as it was and has no cog).
                module = "Nameplates",
                retail = true,
                title  = "Dispellable By Me",
                desc   = "Only Dispellable can show just the enemy buffs you or your group can dispel, purge or soothe: turn it on in the Enemy Buff Filter cog",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUINameplates", page = "General", section = "EXTRA AURA OPTIONS", highlight = "Enemy Buff Filter" } or nil,
            },
            {
                -- The Spells list of an action menu's entries, in ACTION MENU SETUP on the Quickdraw
                -- page (WoW Forever only).
                module  = "Quickdraw",
                forever = true,
                title   = "Spell Ranks",
                desc    = "The Spells list offers each learned rank of a spell, and an entry picked from a rank, or a lower rank dragged from the spellbook, always casts that rank",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQuickdraw", page = "Quickdraw", section = "ACTION MENU SETUP" } or nil,
            },
        },
        fixes = {
            { module = "Data Bars", text = "The bar no longer jitters every second while a Travel Cooldowns block counts down." },
            { module = "Data Bars", forever = true, text = "The Class Resources block now counts reagents kept in the reagent bag." },
            { module = "Forever Essentials", forever = true, text = "Fishing's Double-Click to Cast no longer applies a lure while its own Apply Lure is off." },
            { module = "General", text = "With Apply to All Game Text on, the Guild & Communities chat takes the global font again." },
            { module = "Group Finder", retail = true, text = "The results list's Delisted, Invited and Failed statuses now show in your language." },
            { module = "Nameplates", text = "With Show Threat On: Health Bar, neutral enemies you fight now take threat colors on the health bar, as hostile ones do." },
            { module = "Nameplates", forever = true, text = "The target's range text, and Quality of Life's, now read whole yards (24+) instead of long decimals when a talent such as Grim Reach extends your spell range." },
            { module = "Unit Frames", forever = true, text = "Hovering the hunter pet happiness icon no longer causes a Lua error." },
            { module = "Unit Frames", forever = true, text = "The [name:last] and [target:last] custom text tags no longer repeat your first name for your own character while My Surname is off, on Raid & Party Frames and Nameplates too." },
            { module = "Localization", text = "Brazilian Portuguese, French, Spanish and Traditional Chinese translations updated, including the Group Finder lists, the gamepad options and Forever Essentials." },
        },
    },
    {
        version = "9.8",
        thanks = true,
        heroes = {
            {
                -- The RESULTS LIST section of the Premade Search page; the lists themselves are in the
                -- Dungeons & Raids window (retail only: Group Finder does not load on WoW Forever).
                module = "Group Finder",
                retail = true,
                title  = "Group and Applicant Lists",
                desc   = "Group Finder now draws its own group list, with leader ratings, region tags, playstyles and sign-up timers, and its own applicant list that can hide applicant info. New filters cover classes and roles, raid bosses, filter expressions and regions or languages, saved per character.",
                nav    = { module = "EllesmereUIGroupFinder", page = "Premade Search", section = "RESULTS LIST" },
            },
            {
                -- The Custom Friends List Tiles | Tile Height row of DISPLAY in the Friends List card of
                -- Window Skins (WoW Forever only).
                module  = "Blizzard Skins+",
                forever = true,
                title   = "Custom Friends List",
                desc    = "EllesmereUI's own friends list now takes over the friends window while its Window Skins card is skinned: pick the tile height and sort friends into groups you name, color, reorder and collapse, Favorites included. Right click a friend to move it; Blizz Default keeps Blizzard's list.",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "DISPLAY", highlight = "Tile Height" } or nil,
            },
        },
        features = {
            {
                -- The Pinned Items cog on the Show Pinned Items row of CATEGORIES on the Bags page (both clients).
                module = "Bags",
                title  = "Dim Pinned Items in OneBag/MultiBag",
                desc   = "The Pinned Items settings can dim pinned items in their bag slots, since they also show in Pinned Items",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "CATEGORIES", highlight = "Show Pinned Items" },
            },
            {
                -- The OFFLINE BANK section of the Bags module's Bank page (new on WoW Forever; retail has
                -- had it since an earlier release).
                module  = "Bags",
                forever = true,
                title   = "Offline Bank",
                desc    = "Look through your other characters' bags and banks from anywhere: pick a character with the button beside the bags or bank title. Item tooltips can also count an item across all your characters, and both are off by default",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIBags", page = "Bank", section = "OFFLINE BANK", highlight = "Offline Bank" } or nil,
            },
            {
                -- The condition picker of a conditional group, from the Overrides tab of Profiles &
                -- Presets in its Conditional Overrides mode (WoW Forever only: retail lists no such condition).
                module  = "General",
                forever = true,
                title   = "Gamepad Mode Condition",
                desc    = "Conditional Overrides can switch your settings while WoW's gamepad interface is on, such as hiding bars or moving frames for controller play",
                nav     = EllesmereUI.IS_FOREVER and { module = "_EUIProfiles", page = "Overrides",
                            preSelect = function() EllesmereUI._overridesTabMode = "cond" end } or nil,
            },
            {
                -- The slot cogs of CORE POSITIONS on the Display page (both clients).
                module = "Nameplates",
                title  = "Per-Element Core Position Settings",
                desc   = "Each Core Positions cog now has a section per element in its slot, with its own size, and Show In Instances for the indicators",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS" },
            },
            {
                -- The element dropdowns of CORE POSITIONS on the Display page (both clients).
                module = "Nameplates",
                title  = "Quest Objective Text Element",
                desc   = "Quest Objective Text is now a Core Positions element of its own, replacing Replace Quest Icon with Objective; your setup carries over",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS" },
            },
            {
                -- The Equipment Sets list of an action menu's entries and the Equipment Sets preset for
                -- a new menu, in ACTION MENU SETUP on the Quickdraw page (both clients).
                module = "Quickdraw",
                title  = "Equipment Sets",
                desc   = "Action menus can hold your Equipment Manager sets, each equipping its set on a press, and a new menu can start from an Equipment Sets preset with all of them",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw", section = "ACTION MENU SETUP" },
            },
            {
                -- The Missing Buffs row of INDICATORS on the raid Frames page; Arcane Intellect is in its
                -- cog (WoW Forever only, mages).
                module  = "Raid & Party Frames",
                forever = true,
                title   = "Arcane Intellect",
                desc    = "Missing Buffs now shows mages which mana users lack Arcane Intellect",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames", section = "INDICATORS", highlight = "Missing Buffs" } or nil,
            },
            {
                -- The Craft Batches dropdown of DISPLAY on the Cast Bar page (both clients).
                module = "Resource Bars",
                title  = "Merge Craft Batches",
                desc   = "While crafting several items, the player cast bar can run as one bar across the whole batch instead of refilling for every craft",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar", section = "DISPLAY", highlight = "Craft Batches" },
            },
            {
                -- The Rested Indicator row of EXTRAS on the Main Frames page with the Player frame
                -- selected (both clients): Quality of Life's row mirrored, the same settings.
                module = "Unit Frames",
                title  = "Rested Indicator in Player Extras",
                desc   = "The Rested Indicator and its settings now also sit in the Player frame's Extras, shared with its row in Quality of Life",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "EXTRAS", highlight = "Rested Indicator",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Out of Range Coloring keeps working after you page bar 1 away and back, and bars with custom paging now color and glow the page they show." },
            { module = "Action Bars", forever = true, text = "Bar 1 no longer switches to the caster page after a druid powershifts." },
            { module = "AuraBuff Reminders", forever = true, text = "Reminders in the WoW Forever section, custom spell IDs included, no longer show in combat, and its Where to Show no longer offers In Combat." },
            { module = "Blizzard Skins+", forever = true, text = "The Looking For Group window no longer shows an error when opened inside an instance." },
            { module = "Cooldown Manager", text = "With Keep Keys on Bar Swap off, keybinds on icons update right away when a stance, form or page swap changes them, instead of up to a second later." },
            { module = "Data Bars", text = "An XP / Rep block with its text set to Off no longer shows a \"Font not set\" error after a reload, and lays out again." },
            { module = "Forever Essentials", forever = true, text = "The Loot Feed now shows fishing catches and crafted items." },
            { module = "General", text = "Player names, chat bubbles and other text written by players now show Cyrillic, Chinese and Korean letters instead of boxes; a font without those letters shows that text in Blizzard's font." },
            { module = "General", text = "Color swatches in the settings window keep their whole outline at every Window Scale." },
            { module = "General", forever = true, text = "The Gamepad page's action bar and cast bar hides now follow the game's gamepad interface: a controller left connected while you play with keyboard and mouse no longer hides them." },
            { module = "Nameplates", forever = true, text = "The Elite/Rare and Quest Indicators and Quest Objective Text now show in dungeons and raids by default." },
            { module = "Quality of Life", text = "The Movement Cooldown Alert's sound or spoken name now plays only when a cooldown you used comes back, no longer after wand shots or other casts while the spell was ready." },
            { module = "Quest Tracker", forever = true, text = "Title Difficulty Colors in the Colors section now turns quest difficulty colors on or off for both trackers through the game's own option, replacing the custom tracker's own toggle." },
            { module = "Quest Tracker", forever = true, text = "The Custom Quest Tracker no longer drifts as you accept or turn in quests while it is linked to another element in Unlock Mode." },
            { module = "Quest Tracker", forever = true, text = "Shift-clicking a quest in the Custom Quest Tracker now untracks it in the quest log too, out of combat." },
            { module = "Quest Tracker", forever = true, text = "Quest voice-over Play buttons now show beside quests in the Custom Quest Tracker, as they do on Blizzard's tracker." },
            { module = "Quickdraw", forever = true, text = "Spell entries now cast the highest rank of the spell you know, as /cast does, instead of the rank they were added with, and the Spells list shows each spell once." },
            { module = "Raid & Party Frames", forever = true, text = "The Buff Manager's Core Healing Buffs now include Prayer of Mending and every rank of Renew." },
            { module = "Raid & Party Frames", forever = true, text = "Missing Buffs on the Party tab now follows its own Salvation setting." },
            { module = "Resource Bars", text = "Show When Health, Energy, Focus or Mana Missing now shows the bar at its normal opacity while that resource is below full, even when Fade Out of Combat dims it." },
            { module = "Resource Bars & Unit Frames", text = "Looting a quest object now shows \"Opening\" on the cast bar instead of \"Opening - No Text\"." },
            { module = "Unit Frames", text = "3D portraits no longer go blank for NPCs inside dungeons and raids, where the game allows no 3D model of them; their 2D portrait shows instead." },
            { module = "Unit Frames", text = "Indicators set to Portrait, such as the Combat Indicator, now sit in the same spot in the options preview as on your frames: on the portrait under Blizzard Style, Classic WoW UI and the WoW Forever look, and at the health bar's top-left with Portrait Mode set to None." },
            { module = "Unit Frames", forever = true, text = "The target frame's Elite/Rare Indicator now shows in dungeons and raids by default." },
            { module = "Unit Frames", forever = true, text = "Rogue poisons and shaman weapon imbues no longer show twice on the Player Aura Bars Buffs bar, and an oil or sharpening stone on the same weapon now shows beside them." },
            { module = "Localization", text = "Korean, Spanish, Simplified Chinese and Traditional Chinese translations updated, including the Custom Quest Tracker and the friends list." },
        },
    },
    {
        version = "9.7.8",
        mini = true,
        features = {
            {
                -- The Width | Max Height and Grow Direction | Scrollbar rows of CUSTOM TRACKER on the
                -- Quest Tracker page, and the swatches on its Group Quests by Zone toggle (WoW Forever only).
                module  = "Quest Tracker",
                forever = true,
                title   = "Custom Tracker Layout Options",
                desc    = "New Width and Max Height sliders, a Grow Direction that can stack quests upward from the tracker's bottom edge, and accent or custom colors for its zone headers",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQuestTracker", page = "Quest Tracker", section = "CUSTOM TRACKER", highlight = "Grow Direction" } or nil,
            },
        },
        fixes = {
            { module = "Quest Tracker", forever = true, text = "The Custom Quest Tracker is now on by default only while your Quest Tracker style is EllesmereUI. With Blizzard Style, Classic WoW UI or the WoW Forever look you are back on Blizzard's tracker unless you turn the custom one on." },
            { module = "Quest Tracker", forever = true, text = "The Custom Quest Tracker now starts where Blizzard's tracker was, at its width and height; if you never moved it, it takes that spot once after this update." },
            { module = "Quest Tracker", forever = true, text = "In Unlock Mode the Custom Quest Tracker now shows the whole area it can grow into, and leaving without saving no longer changes its max height." },
        },
    },
    {
        version = "9.7.7",
        thanks = true,
        heroes = {
            {
                -- The whole settings window: toggles, sliders, dropdowns and their lists, input
                -- fields, its own buttons and the three-dot setting menus (both clients).
                module = "General",
                title  = "Settings Visual Update",
                desc   = "The settings window has a new rounded look: toggles, sliders, dropdowns, input fields and buttons, crisp at every Window Scale. Extra options now sit behind three dots that light up when you change their setting, and Apply to only shows while you hover a setting.",
            },
            {
                -- The CUSTOM TRACKER section of the Quest Tracker page (WoW Forever only).
                module  = "Quest Tracker",
                forever = true,
                title   = "Custom Quest Tracker",
                desc    = "EllesmereUI's own quest tracker now replaces Blizzard's, with zone groups, pinned quests, focus buttons, quest timers, quest item buttons, update flashes and a quest details window of its own; Blizzard's tracker is one switch away.",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQuestTracker", page = "Quest Tracker", section = "CUSTOM TRACKER", highlight = "Custom Quest Tracker" } or nil,
            },
        },
        features = {
            {
                -- The Auto Open Bags | Auto Close Bags row of EXTRAS on the Bags page (both clients;
                -- retail also lists the Scrapper, Item Interaction and Azerite Essences windows).
                module = "Bags",
                title  = "Auto Open and Close Bags",
                desc   = "Pick which windows open and close your bags, such as the merchant, mailbox and bank; bags now close with the window that opened them",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "EXTRAS", highlight = "Auto Open Bags" },
            },
            {
                -- The DataBars page, where blocks are added (both clients).
                module = "Data Bars",
                title  = "Time Played Block",
                desc   = "A new block shows your time played at this level or in total, and its tooltip lists every character's total",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- The CORE TEXT POSITIONS section of the Display page (both clients).
                module = "Nameplates",
                title  = "Top Left and Top Right Text",
                desc   = "Core Text Positions gains Top Left and Top Right above the health bar's corners; icons on those corners move up to clear them",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE TEXT POSITIONS" },
            },
            {
                -- The Low Durability Warning row of EXTRAS on the QoL page; Ignore Thrown Weapons sits
                -- in its Durability Settings cog (WoW Forever only).
                module  = "Quality of Life",
                forever = true,
                title   = "Ignore Thrown Weapons",
                desc    = "The Low Durability Warning now skips thrown weapons, whose durability counts their throws; turn it off in the warning's settings to include them",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQoL", page = "QoL", section = "EXTRAS", highlight = "Low Durability Warning" } or nil,
            },
            {
                -- The Targeting Sound Effects row of EXTRAS on the Main Frames page with the Target
                -- frame selected (both clients; on by default on WoW Forever).
                module = "Unit Frames",
                title  = "Targeting Sound Effects",
                desc   = "A new option in the Target frame's Extras plays the game's sounds when you select or lose a target, as Blizzard's own target frame does",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "EXTRAS", highlight = "Targeting Sound Effects",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end; EllesmereUI._pendingUnitSelect = "target" end },
            },
        },
        fixes = {
            { module = "Action Bars", forever = true, text = "With the Gamepad interface style, stance bar icons (auras, stances and forms) show at login and after a reload instead of staying blank until you switch." },
            { module = "Bags", forever = true, text = "Item icons now show square and keep your Icon Zoom setting when your bags update." },
            { module = "Blizzard Skins+", forever = true, text = "Item icons in skinned windows (merchants, mail, loot, quest rewards and more) now show square with their rarity border, and stay square when the window updates." },
            { module = "Cooldown Manager", text = "Buffs added by Custom Spell ID to a cooldown or utility bar now show: grey while missing, with the buff's time left while it is up." },
            { module = "Cooldown Manager", text = "Spells and racials no longer sometimes land on the wrong bar when you log in, before the game has loaded your Cooldown Manager layout." },
            { module = "Cooldown Manager", forever = true, text = "Paladins can add Seals to a cooldown or utility bar from its Add menu, beside Racial; it shows your active seal with its time left, since Blizzard's own Seals entry never shows a frame." },
            { module = "Data Bars", text = "Data bars keep their full width, edge snap and links after a reload or a UI scale change, Unlock Mode's Cancel no longer removes a bar's edge snap, and resizing a bar from its Unlock Mode cog no longer undoes an unsaved drag." },
            { module = "Data Bars", text = "Gold amounts under 1 gold show their silver and copper instead of 0g on vertical bars and in the gold tooltip." },
            { module = "Data Bars & Bags", forever = true, text = "Gold tooltips list each character by full name, and characters sharing a first name keep their own balances." },
            { module = "General", text = "Combat Text Font no longer turns floating combat text into boxes on Chinese, Korean and Russian clients; fonts without their letters are no longer offered there." },
            { module = "General", text = "The Incompatible Addon Detected popup now shows only while one of the other addon's chat or minimap options that clash with EllesmereUI is on, and lists those options." },
            { module = "General", text = "Scrolling dropdown lists no longer draw the text of a partly scrolled row over their top or bottom border." },
            { module = "General", text = "The Accent Colored Settings Elements option is gone: the menu dots and preview icons beside settings are always white." },
            { module = "Nameplates", forever = true, text = "With Show Friendly NPC Nameplates on, friendly NPCs such as Ironforge Mountaineers no longer lose their plate and name." },
            { module = "Quality of Life", text = "The Shifter now moves the window of an opened mail too, and keeps it where you leave it." },
            { module = "Quest Tracker", text = "Hide When In Raid has a new Never choice, keeping the tracker up through raids so only the Visibility options hide it." },
            { module = "Quest Tracker", forever = true, text = "Announce Progress now posts each objective you finish, with a link to the quest, instead of every step." },
            { module = "Quest Tracker", forever = true, text = "With quest difficulty colors on, the focused quest's title now shows your Focus color in Blizzard's tracker." },
            { module = "Unit Frames", text = "Cast bar Fill Opacity now takes effect; the cast fill drew fully opaque at any setting." },
            { module = "Unit Frames", forever = true, text = "With the Gamepad interface style, the target menu button (Y or Triangle) opens your target's menu again while EllesmereUI's target frame is in use." },
            { module = "Unit Frames", forever = true, text = "The target and lost-target sounds play again while EllesmereUI's target frame is in use; Targeting Sound Effects in the Target frame's Extras turns them off." },
            { module = "Localization", text = "Traditional Chinese translations updated for the latest options and the Numbers page." },
        },
    },
    {
        version = "9.7.6",
        mini = true,
        features = {
            {
                -- The Paging Arrows row of BEHAVIOR & PAGING on the Bar Display page with Action Bar 1
                -- selected; its While Paged choice is one of the row's dropdown entries (both clients).
                module = "Action Bars",
                title  = "Arrows While Paged",
                desc   = "Action Bar 1's paging arrows now show while it is on another page, even with Paging Arrows off, so a page switched by accident is easy to spot and undo",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "BEHAVIOR & PAGING", highlight = "Paging Arrows",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end; EllesmereUI._pendingActionBarSelect = "MainBar" end },
            },
            {
                -- The Mage Armors row of the WOW FOREVER section, built for mages only (WoW Forever only).
                module  = "AuraBuff Reminders",
                forever = true,
                title   = "Mage Armors",
                desc    = "A new reminder for mages while no Frost, Ice or Mage Armor is up; a click casts the armor you last wore",
                nav     = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                            section = "WOW FOREVER", highlight = "Mage Armors" } or nil,
            },
        },
        fixes = {
            { module = "Action Bars", text = "A stance or form learned during play now stays on the stance bar after you use it, instead of disappearing until a reload." },
            { module = "Action Bars", text = "Skip Visible Bars When Paging is now on by default, so the next and previous page keys no longer put Action Bar 1 on a page another of your bars already shows." },
            { module = "Chat", forever = true, text = "The Chat Menu sidebar icon opens the chat menu again on the WoW Forever look, and no longer shows with the Gamepad interface style, where the game hides that menu." },
            { module = "Forever Essentials", forever = true, text = "Classic Spellbook and Classic Talents now also open from the micro menu, the Data Bars micro menu block and Quickdraw (the spellbook outside combat), and the Shifter can move them." },
            { module = "General", forever = true, text = "First Name and Last Name name formats now shorten only player names, so mobs and NPCs keep their whole names (a Rot Hide Gnoll no longer reads Rot)." },
            { module = "Nameplates", forever = true, text = "Under the WoW Forever style, the health bar's fill no longer runs over the bottom of its border." },
            { module = "Nameplates", forever = true, text = "Under the WoW Forever style, Target Effect offers Highlight only: EUI Glow, Border Color and Border Size no longer apply there." },
            { module = "Quest Tracker", text = "Auto Accept and Auto Turn In now also work at NPCs that list their quests without a chat window, and Auto Turn In clicks Continue on item turn-ins; a turn-in that costs gold is left to you." },
            { module = "Quickdraw", forever = true, text = "The professions list names First Aid correctly instead of calling it Archaeology." },
            { module = "Unlock Mode", forever = true, text = "The Encounter Bar box no longer shows while no encounter bar is up." },
        },
    },
    {
        version = "9.7.5",
        mini = true,
        fixes = {
            { module = "Action Bars", text = "Turning Cooldown Numbers on or off now updates your bars at once instead of after a reload." },
            { module = "Chat", text = "With Input on Top and Blizzard's IM chat style, the empty space above your messages now closes while you aren't typing, and links on the top line can be clicked." },
            { module = "Cooldown Manager", text = "Buffs set to Also Show Below, buffs with a Stack Count glow and Stack Based Bar Tracking Bars no longer cause Lua errors in combat when the game hides an aura's details from addons." },
            { module = "Cooldown Manager", forever = true, text = "The Anti-Clip Glow no longer causes Lua errors in combat when the game hides an aura's details from addons; that aura shows no glow there." },
            { module = "General", forever = true, text = "Blizzard Skins+ window and tooltip skins, friend tiles, the Minimap Friends button, the Chat Menu icon, /cd, the Quest Tracker tools and the Action Bars spellbook, macro and flyout extras now work with the Gamepad interface style, since the 1.60.1 update stops addon hooks from blocking its navigation." },
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
        --  TOP SECTION: one row, Reset EUI Module Settings | Optimize My FPS
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
            -- Loadout Manager keeps a per-character store outside the profiles:
            -- this clears it for the character doing the reset.
            EllesmereUILoadoutManagerDB = nil
            -- Bags' offline bank keeps every character's saved bags and banks outside them too
            EllesmereUIBagsInventoryDB = nil
            local oldScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
            local oldScaleAuto = EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto
            -- Preserve friend group data across reset
            local oldGlobal = EllesmereUIDB and EllesmereUIDB.global
            local savedFriends
            if oldGlobal then
                savedFriends = {
                    friendGroups = oldGlobal.friendGroups,
                    friendGroupsByTag = oldGlobal.friendGroupsByTag,
                    friendGroupsTagMigrated = oldGlobal.friendGroupsTagMigrated,
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
                "autoInsertKeystone", "quickSignup",
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

        -- Reset ALL: a typed confirm, then the wipe and a reload (the wipe runs
        -- as RequestReload's pre-reload work).
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
            -- A menu of ALL Settings and each module's own reset (EllesmereUI_Panel.lua).
            { icon = MEDIA_ICONS .. "sync.png", accent = WARN,
              title = EllesmereUI.L("Reset EUI Module Settings"),
              desc = EllesmereUI.L("Pick a module, or ALL, to return to defaults."),
              onClick = function(card) EllesmereUI._ShowModuleResetMenu(card, ConfirmResetAll) end },
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

            -- A non-English game client reads only its own translation file, its
            -- pair's and none other: EllesmereUILocales.toc tags each file with
            -- the client languages that load it (keep LANG_PAIR in step with its
            -- pairs). English clients read every file.
            local LANG_PAIR = { esMX = "esES", zhCN = "zhTW", zhTW = "zhCN" }
            local clientLocale = GetLocale()
            local function LanguageUnavailable(v)
                if v == "auto" or v == "enUS" or clientLocale == "enUS" or clientLocale == "enGB" then return false end
                if v == clientLocale or LANG_PAIR[clientLocale] == v then return false end
                return "Needs the game client set to English or to this language."
            end

            langCfg = { type="dropdown", text="EUI Options Language",
                tooltip="The display language for the EllesmereUI options panel. Auto follows your game client. Untranslated text falls back to English.",
                values=langValues, order=langOrder, disabledValues=LanguageUnavailable,
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

        _, h = W:SectionHeader(parent, "UNLOCK MODE", y);  y = y - h
        local pointAnchorRow
        pointAnchorRow, h = W:DualRow(parent, y,
            { type="toggle", text="Point Anchoring",
              tooltip="Show nine source points after clicking Anchor in Unlock Mode. Choose a source point, then a target point. Turning this off hides the handles and preserves saved point anchors.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.unlockPointHandles == true end,
              setValue=function(v)
                  EllesmereUI.SetPointAnchorHandles(v)
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Overlap Cycling",
              tooltip="Scroll with the chosen modifier to cycle overlapping frames in Unlock Mode.",
              values=EllesmereUI.UNLOCK_OVERLAP_LABELS,
              order={ "disabled", "scroll", "shiftscroll", "controlscroll", "altscroll" },
              getValue=function() return EllesmereUI.GetUnlockOverlapMethod() end,
              setValue=function(v)
                  EllesmereUIDB = EllesmereUIDB or {}
                  EllesmereUIDB.unlockOverlapMethod = v
                  if EllesmereUI.RefreshUnlockOverlapMethod then EllesmereUI.RefreshUnlockOverlapMethod() end
              end }); y = y - h
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(pointAnchorRow._leftRegion, {
                { tooltip="Connector Lines Color", hasAlpha=true,
                  getValue=function() return EllesmereUI.GetPointAnchorColor("line") end,
                  setValue=function(r,g,b,a) EllesmereUI.SetPointAnchorColor("line",r,g,b,a) end },
                { tooltip="Border Color", hasAlpha=true,
                  getValue=function() return EllesmereUI.GetPointAnchorColor("border") end,
                  setValue=function(r,g,b,a) EllesmereUI.SetPointAnchorColor("border",r,g,b,a) end },
                { tooltip="Point Color", hasAlpha=true,
                  getValue=function() return EllesmereUI.GetPointAnchorColor("point") end,
                  setValue=function(r,g,b,a) EllesmereUI.SetPointAnchorColor("point",r,g,b,a) end },
            }, {
                disabled=function() return not (EllesmereUIDB and EllesmereUIDB.unlockPointHandles == true) end,
                disabledTooltip="Point Anchoring",
            })
        end
        _, h = W:Spacer(parent, y, 20); y = y - h

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
        for i = #fctFontOrder, 2, -1 do
            local k = fctFontOrder[i]
            if k ~= "---" and not EllesmereUI.CombatTextFontCoversLocale(k) then
                table.remove(fctFontOrder, i)
            end
        end
        if fctFontOrder[#fctFontOrder] == "---" then fctFontOrder[#fctFontOrder] = nil end
        EllesmereUI.AppendSharedMediaFonts(fctFontValues, fctFontOrder)

        -- Combat Text (checkbox dropdown + size cog) | Combat Text Font. The
        -- dropdown is a view over the floating combat text CVars the client
        -- has; each extra only applies while the item it refines is on (the
        -- damage extras under Damage, Absorb Shields under Healing, Others'
        -- Target Effects under Target Effects).
        local function DmgOff() return not GetCVarBool("floatingCombatTextCombatDamage_v2") end
        local function HealOff() return not GetCVarBool("floatingCombatTextCombatHealing_v2") end
        local function FxOff() return not GetCVarBool("floatingCombatTextSpellMechanics_v2") end
        local dmgTip = EllesmereUI.DisabledTooltip("Damage")
        local healTip = EllesmereUI.DisabledTooltip("Healing")
        local fxTip = EllesmereUI.DisabledTooltip("Target Effects")
        local COMBAT_TEXT = {}
        for _, item in ipairs({
            { key="floatingCombatTextCombatDamage_v2",            label="Damage" },
            { key="floatingCombatTextCombatLogPeriodicSpells_v2", label="Periodic Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextPetMeleeDamage_v2",          label="Pet Melee Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextPetSpellDamage_v2",          label="Pet Spell Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextCombatHealing_v2",           label="Healing" },
            { key="floatingCombatTextCombatHealingAbsorbTarget_v2", label="Absorb Shields",
              lockedFn=HealOff, lockedTooltip=healTip, excludeFromSummaryFn=HealOff },
            { key="floatingCombatTextSpellMechanics_v2",          label="Target Effects" },
            { key="floatingCombatTextSpellMechanicsOther_v2",     label="Others' Target Effects",
              lockedFn=FxOff, lockedTooltip=fxTip, excludeFromSummaryFn=FxOff },
        }) do
            if C_CVar.GetCVarInfo(item.key) then COMBAT_TEXT[#COMBAT_TEXT + 1] = item end
        end
        local combatTextRow
        combatTextRow, h = W:DualRow(parent, y,
            { type="label", text="Combat Text" },
            { type="dropdown", text="Combat Text Font",
              tooltip="WARNING: This feature requires you to re-log or restart WoW to take effect.",
              tooltipOpts={ color={1, 0.3, 0.3} },
              values = fctFontValues, order = fctFontOrder,
              getValue=function()
                local v = EllesmereUIDB and EllesmereUIDB.fctFont
                return v and EllesmereUI.CombatTextFontCoversLocale(v) and v or "default"
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
                title = "Combat Text Size",
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

        -- Swiftmend Brightness Fix (Druid only): the right slot beside Round
        -- Timer Seconds Down, blank for every other class.
        local swiftmendCfg = EllesmereUI.BlankRowCfg()
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            swiftmendCfg = { type="toggle", text="Prevent Swiftmend Icon Dim",
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
                end }
        end

        -- Row 4: Round Timer Seconds Down | Prevent Swiftmend Icon Dim. Every
        -- timer keeps the formatter it was given (AuraKit reads the setting
        -- once), so a change waits for a reload.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Round Timer Seconds Down",
              tooltip="Timer seconds round down like Blizzard's buff frame, so a timer reads 0 in its last second. Off, it reads 1 until it ends.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.timerSecondsDown == true or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.timerSecondsDown = v or nil
                  EllesmereUI:ShowConfirmPopup({
                      title       = "Reload Required",
                      message     = "Changing how timers round requires a UI reload.",
                      confirmText = "Reload Now",
                      cancelText  = "Later",
                      reload      = true,
                  })
              end },
            swiftmendCfg
        ); y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  DEVELOPER -- both toggles are duplicated in Quality of Life
        --  (Suppress Lua Errors) and Blizzard Skins+ (Spell ID on Tooltip):
        --  hidden here when BOTH modules are loaded, shown if either is missing so the settings stay reachable.
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
                { type="toggle", text="Spell ID on Tooltip",
                  getValue=function()
                    return EllesmereUI.SpellIDOn()
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

    -- The profiles root (EUI_Profiles_Options.lua) sits on the scroll frame
    -- itself, beside the pages: when another page shows it is hidden and
    -- leaves the scroll frame, and nil marks it as needing a build before it
    -- shows again. The frame stays its builder's (options page pool): the
    -- next build parents it to the scroll frame again and dresses it again.
    local function CleanupProfilesRoot()
        local root = EllesmereUI._profilesRoot
        if root then
            root:Hide()
            root:SetParent(nil)
            EllesmereUI._profilesRoot = nil
        end
    end

    -- A profiles root build outside a page pass (a cached page shown again):
    -- the refreshers its previous build registered leave the live list first.
    local function RenderProfilesRoot()
        EllesmereUI._BeginRootRender("profilesRoot")
        _G._EUI_BuildProfilesPage(PAGE_PROFILES, nil, -6)
        EllesmereUI._EndRootRender("profilesRoot")
    end

    -- Profiles and Patch Notes are their own sidebar pages (registered below), so Global Settings owns General + Style + Fonts + Textures + Glows + Colors + Numbers (Style second, beside General), plus Gamepad while a module it configures is loaded.
    local globalPages = { PAGE_GENERAL, PAGE_STYLE, PAGE_FONTS, PAGE_TEXTURES, PAGE_GLOWS, PAGE_COLORS, PAGE_NUMBERS }
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
                elseif pageName == PAGE_NUMBERS then
                    return _G._EUI_BuildNumberFormatPage and _G._EUI_BuildNumberFormatPage(pageName, parent, yOffset)
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
            elseif pageName == PAGE_NUMBERS then
                return _G._EUI_BuildNumberFormatPage and _G._EUI_BuildNumberFormatPage(pageName, parent, yOffset)
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
        -- Number Format: the value type picker and preview header, and one search
        -- pre-build per value type (each type's Precision row exists only under it).
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_NUMBERS and _G._EUI_NumberFormatHeaderBuilder then
                return _G._EUI_NumberFormatHeaderBuilder()
            end
            return nil
        end,
        getPrebuildVariants = function(pageName)
            if pageName == PAGE_NUMBERS and _G._EUI_NumberFormatVariants then
                return _G._EUI_NumberFormatVariants()
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            -- The cached header's preview may predate a profile switch.
            if pageName == PAGE_NUMBERS and _G._EUI_NumberFormatRefreshHeader then
                _G._EUI_NumberFormatRefreshHeader()
            end
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
                    if EllesmereUI:GetActiveModule() == GLOBAL_KEY
                       and EllesmereUI:GetActivePage() == pageName then
                        RenderProfilesRoot()
                    end
                end)
            end
        end,
        -- Reset EUI Module Settings: these settings sit on the account.
        resetScope  = "account",
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
            -- Reset the active profile's Number Format to defaults
            EllesmereUI.ResetNumberFormat()
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
                -- Developer settings defaults (Spell ID on Tooltip: unset = on)
                EllesmereUIDB.showSpellID = nil
                if EllesmereUI.SyncAuraSpellIDCVar then EllesmereUI.SyncAuraSpellIDCVar() end
                EllesmereUIDB.suppressErrors = true
                EllesmereUIDB.timerSecondsDown = nil
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
                EllesmereUIDB.unlockPointHandles = nil
                EllesmereUIDB.unlockPointColors = nil
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
    -- CleanupProfilesRoot hooks below (keyed to PROFILES_KEY). Second tab: the Overrides management list (built by EUI_SpecOverrides_ListPage.lua).
    --
    -- ONE tab, TWO pages: "Spec Overrides" and "Conditional Overrides" stay completely separate page builders with their own stores, prune
    -- passes and row logic. The tab strip shows one "Overrides" entry and a centered segmented toggle picks the builder (the same control
    -- Raid Frames uses for Simple Setup / Custom Buff Display). The mode is runtime-only, defaulting to the spec list.
    local PAGE_OVERRIDES = "Overrides"

    -- Builds the centered mode toggle, returning the vertical space used. Plain local closure on purpose: no widget row, no capture config, no saved state.
    -- The shared segmented control draws it, so it looks like every other segment switch.
    local function BuildOverridesModeToggle(parent, y)
        -- Wider than the Raid Frames pair (162): "Conditional Overrides" is a longer label than "Custom Buff Display" and must not clip.
        local BTN_W, BTN_H = 180, 31
        local seg = EllesmereUI.BuildSegmentedControl({
            parent     = parent,
            keys       = { "spec", "cond" },
            labels     = { spec = "Spec Overrides", cond = "Conditional Overrides" },
            width      = BTN_W * 2,
            square     = true,
            height     = BTN_H,
            getChecked = function(key) return (EllesmereUI._overridesTabMode or "spec") == key end,
            onToggle   = function(key)
                if (EllesmereUI._overridesTabMode or "spec") == key then return end
                EllesmereUI._overridesTabMode = key
                -- Forced: the two builders render entirely different rows.
                EllesmereUI:RefreshPage(true)
            end,
        })
        seg:SetPoint("TOP", parent, "TOP", 0, y - 14)
        seg:SetFrameLevel(parent:GetFrameLevel() + 1)
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
        EllesmereUI.MakeRoundedBorder(warn, 0.8, 0.2, 0.2, 0.55, wbg)
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
        local bbrd = EllesmereUI.MakeRoundedBorder(btn, EG.r, EG.g, EG.b, 0.5, bbg)
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
                            RenderProfilesRoot()
                        end
                    end)
                end
            elseif not EllesmereUI._profilesRoot then
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY
                       and EllesmereUI:GetActivePage() == pageName then
                        RenderProfilesRoot()
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

    -- Patch Notes and EUI Legends (the donor and team celebration page): one
    -- sidebar module each. Suite-only, never registered in standalone builds.
    if not IS_STANDALONE then
        EllesmereUI:RegisterModule(PATCHNOTES_KEY, {
            title       = "Patch Notes",
            description = EllesmereUI.L("What's new in EllesmereUI."),
            pages       = { PAGE_WHATSNEW },
            buildPage   = function(pageName, parent, yOffset)
                return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end,
        })
        EllesmereUI:RegisterModule(LEGENDS_KEY, {
            title       = "EUI Legends",
            description = EllesmereUI.L("Celebrating the donors and team behind EllesmereUI."),
            pages       = { PAGE_LEGENDS },
            buildPage   = function(pageName, parent, yOffset)
                return EllesmereUI._BuildLegendsPage(pageName, parent, yOffset)
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
            -- Panel chrome, not page content: the refresh the slider registers
            -- leaves the shown page's refresh list again (ScaleCtlRefresh and the
            -- accent callback below repaint it), so the page's first build
            -- registers what its later builds do.
            local pageRefresh = EllesmereUI._widgetRefreshList
            local pageRefreshN = #pageRefresh
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
            for i = #pageRefresh, pageRefreshN + 1, -1 do pageRefresh[i] = nil end
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
                EllesmereUI.RegAccent({ type = "callback", obj = nameFs,
                    fn = function(r, g, b) nameFs:SetTextColor(r, g, b, 0.9) end })
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
                    EllesmereUI:SelectModule(LEGENDS_KEY)
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

    -- HideAllChildren (every page switch) hides the profiles root too.
    EllesmereUI._AddScrollRootHider(CleanupProfilesRoot)
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
