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
        "GamingGrammers", "Khardi", "Cartridgebros", "Lurn",
        "Ani", "fizzle_crunk", "Tzahal", "Venalis",
        "Natasi", "Drekonus", "Quiim", "Keato03",
        "Capa", "e_luvin", "ccpoppin1", "Arjax",
        "Excelvior", "Marple_V", "shy_x00", "Ferniss",
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
        version = "9.6",
        heroes = {
            {
                -- Retail only: the module does not load on WoW Forever.
                module = "Group Finder",
                title  = "Premade Groups Filters",
                desc   = "Filter Premade Groups by dungeon, delve, raid boss, role and rating, see each group's specs and leader rating at a glance, and count your M+ applications. The module is off until you turn it on.",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search",
                           section = "GROUP FINDER", highlight = "Enable Group Finder" } or nil,
            },
            {
                module = "Blizzard Skins+",
                title  = "Merchant Bulk Buy",
                desc   = "Turn on Bulk Buy in the Merchant card of Window Skins, then shift-click a vendor item to buy any amount at once, with Max and +1 Stack buttons and the total cost shown before you buy.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "MERCHANT OPTIONS", highlight = "Bulk Buy" },
            },
            {
                module = "Unit Frames",
                title  = "Hide Power Bar",
                desc   = "Under the Blizzard Style, Classic WoW UI and WoW Forever looks, the player, target and focus frames can hide their power bar so the health bar fills its space. Under these looks the power bar now always sits in the frame's own track.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Hide Power Bar",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Classic Windows",
                desc   = "Your spellbook and talent keys can open the classic spellbook and talent window instead of Talents & Spellbook. The spellbook's tabs and pages work in combat, and talent points you spend count only once you press Learn.",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "CLASSIC WINDOWS", highlight = "Classic Spellbook" } or nil,
            },
        },
        features = {
            {
                -- Retail only: the AURAS grid is not built on WoW Forever.
                module = "AuraBuff Reminders",
                title  = "Moonkin Form Reminder",
                desc   = "Balance druids can turn on a reminder that shows in combat while they are out of Moonkin Form",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "AURAS", highlight = "Moonkin Form" } or nil,
            },
            {
                module = "Bags",
                title  = "Item Level Colors",
                desc   = "Show Item Level is now Never, Default Colors or Custom Colored, with a color swatch for your own color",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "DISPLAY (GRID / COMPACT)", highlight = "Show Item Level" },
            },
            {
                -- A buff menu item (Always Show Buff): the link opens the Buffs bar.
                module = "Cooldown Manager",
                title  = "Also Show Below",
                desc   = "A buff set to Show When Missing can also show for its last few seconds, as a reminder to refresh it before it drops",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end end },
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Active Stance Icon",
                desc   = "An optional icon shows your active warrior stance, druid form, paladin aura or hunter aspect",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "ACTIVE STANCE, FORM, ASPECT & AURA", highlight = "Show Current" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Auto Summon Pet",
                desc   = "Your companion pet comes back after loading screens, flights and deaths, from your favorites or this character's own",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "COMPANION PETS", highlight = "Auto Summon Pet" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Fishing",
                desc   = "A Fishing Key equips your pole, applies a lure, casts and reels in, a step per press, with optional double-click casting and a bobber indicator",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "FISHING", highlight = "Fishing Key" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Gathering Skill in Tooltips",
                desc   = "Herb and ore tooltips show the skill a node needs, colored by your chance to raise your skill there",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "GATHERING", highlight = "Gathering Skill in Tooltips" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Gold per Hour Tracker",
                desc   = "The Loot Feed can pin a row with your gold per hour and the session's total, counting looted coin and the value of looted items",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Loot",
                           section = "SOURCES", highlight = "Gold per Hour Tracker" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Junk Items on Low Bag Space",
                desc   = "The Junk Items window can show only when your bags are nearly full, below a free-slot threshold you choose",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "JUNK ITEMS", highlight = "Only Show When Bag Space Is Low" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Map Markers",
                desc   = "The world map can show boats, zeppelins, dungeon entrances, flight points and zone exits; click a marker to link it in chat",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "WORLD MAP", highlight = "Show Map Markers" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Most Valuable Reward",
                desc   = "A money bag marks the quest reward choice that sells for the most gold",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "QUEST REWARDS", highlight = "Most Valuable Reward" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Show Zone Levels",
                desc   = "Hovering a zone on a continent map shows its level range, colored by difficulty",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "WORLD MAP", highlight = "Show Zone Levels" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "World Map Fade",
                desc   = "The world map can fade while you move, and the black behind the maximized map can be lightened so the game shows around it",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "WORLD MAP", highlight = "Fade Map While Moving" } or nil,
            },
            {
                -- Each item is listed only where the client has its combat text setting.
                module = "General",
                title  = "More Combat Text Options",
                desc   = "The Combat Text dropdown adds Absorb Shields, Target Effects and Others' Target Effects",
                nav    = { module = "_EUIGlobal", page = "General",
                           section = "COMBAT", highlight = "Combat Text" },
            },
            {
                -- A row in the Cast Color cog.
                module = "Nameplates",
                title  = "Interruptible While Kick Ready",
                desc   = "With Important Cast Color on, an important cast can keep the Interruptible color while your interrupt is ready",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CAST COLORS AND EFFECTS", highlight = "Cast Color" },
            },
            {
                module = "Nameplates",
                title  = "Pandemic and Dispel Glow Styles",
                desc   = "Pandemic Glow and Dispel Glow get their glow styles and settings back, with Blizzard's pandemic border kept as a style and still the default",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "EXTRA AURA OPTIONS", highlight = "Pandemic Glow Style" },
            },
            {
                -- Retail only: rows of the Hide Blizzard Elements list, which WoW Forever does not show.
                module = "Quality of Life",
                title  = "Hide Banners and Toasts",
                desc   = "Hide Blizzard Elements can hide the big boss and event banners and Blizzard's loot, achievement and housing pop-ups",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIQoL", page = "QoL",
                           section = "GENERAL", highlight = "Hide Blizzard Elements" } or nil,
            },
            {
                -- Retail only: a row of the Hide Blizzard Elements list, which WoW Forever does not show.
                module = "Quality of Life",
                title  = "Mute Talking Head",
                desc   = "Hide Blizzard Elements can silence the talking head's voice lines, with or without hiding the talking head",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIQoL", page = "QoL",
                           section = "GENERAL", highlight = "Hide Blizzard Elements" } or nil,
            },
            {
                forever = true,
                module = "Quality of Life",
                title  = "Off-hand Hit",
                desc   = "The Secondary Stats block can show your off-hand hit chance (pick it in Choose Stats)",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQoL", page = "QoL",
                           section = "EXTRAS", highlight = "Secondary Stat Display" } or nil,
            },
            {
                forever = true,
                module = "Quest Tracker",
                title  = "Quest Sorting and Filters",
                desc   = "Sort, filter and auto-track your quests (experimental), color objectives by progress, and play a sound or tell your party as quests progress",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQuestTracker", page = "Quest Tracker",
                           section = "TRACKING", highlight = "Experimental Quest Tools" } or nil,
            },
            {
                -- Retail only: the Buff Manager row is not built on WoW Forever.
                module = "Raid Frames",
                title  = "Pandemic Border",
                desc   = "Buff icon indicators can show a colored border while the buff is in its refresh window",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIRaidFrames", page = "Buff Manager" } or nil,
            },
            {
                forever = true,
                module = "Raid Frames",
                title  = "Salvation Reminder",
                desc   = "Missing Buffs can remind Salvation on its own, now that it stacks with other blessings, on every group member but tanks",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "INDICATORS", highlight = "Missing Buffs" } or nil,
            },
            {
                -- A row in the Texture cog (also on the Cast Bar and GCD Bar pages and Global Settings > Textures).
                module = "Resource Bars",
                title  = "Textured Background",
                desc   = "Bar backgrounds can use the bar's own texture, tinted by the background color, on the class, power and health bars, the cast bar and the GCD bar",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "BAR DISPLAY", highlight = "Texture" },
            },
            {
                forever = true,
                module = "Resource Bars",
                title  = "Swing Timer Movement Guide",
                desc   = "The swing timer shows when you can move and when to stand still for wand and Auto Shot shots, and colors rows by your attack's state",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Swing Timer",
                           section = "DISPLAY", highlight = "Movement Guide" } or nil,
            },
            {
                forever = true,
                module = "Resource Bars",
                title  = "Swing Timer Spark",
                desc   = "The swing timer's spark can be wider, reach past the bar, and take its own color for each weapon",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Swing Timer",
                           section = "DISPLAY", highlight = "Show Spark" } or nil,
            },
        },
        fixes = {
            { forever = true, module = "AuraBuff Reminders", text = "Battle Shout reminders now count the whole raid, now that the shout reaches every raid member." },
            { forever = true, module = "Action Bars", text = "The Extra Action Button's mover and settings are gone, now that the game no longer has an Extra Action Button." },
            { forever = true, module = "Blizzard Skins+", text = "The skinned Character Sheet colors the pet stats' Combat section like Attack." },
            { forever = true, module = "Blizzard Skins+", text = "The skinned Talents window's spec tabs, top bar and search options arrow match the skin again after the game's new talent window art." },
            { module = "Cooldown Manager", text = "While editing an override, you can now remove spells from a bar and drag them to reorder in the CDM Bars preview." },
            { module = "Damage Meters", text = "Hovering a death with no recap, or another player's row in combat, no longer shows the previous tooltip's target list." },
            { module = "Data Bars", text = "Global search now finds the selected bar's settings, its blocks' settings included, without opening the Data Bars page first." },
            { module = "General", text = "The settings window now refreshes its pages in place, reusing what it has already built instead of building them again." },
            { module = "General", text = "Cog popups no longer jump aside or stay open when a settings page redraws, previews keep following your changes after a tab switch, and buttons no longer look dimmer after you hover them." },
            { module = "General", text = "Raid Frames, Unit Frames, Nameplates, Resource Bars, Action Bars and Cooldown Manager use less CPU in combat." },
            { module = "General", text = "Animated glows on buff and debuff icons no longer use CPU while their icon is hidden." },
            { module = "General", text = "A popup left open as combat starts no longer causes errors or holds back your key presses, and the Cooldown Manager's Edit Mode reload popup no longer stops later popups closing with Escape or a click outside." },
            { forever = true, module = "General", text = "Typing /rl, reload buttons and settings that need a reload now reload right away, in combat too, with no extra popup." },
            { forever = true, module = "Minimap", text = "The Forever Circle (and Blizzard Style's Circle) now wears the game's new header bar and buttons, with the day/night orb at its new spot, and Blizzard's new event link button stays on the minimap." },
            { module = "Mythic+ Tools", text = "Previewing the target and focus cast bars no longer shows an error." },
            { module = "Nameplates", text = "Elite and rare badges now show on mobs seen for the first time, without needing a /reload." },
            { module = "Nameplates", text = "Blizzard's new arrow under the nameplates of units behind the camera is now hidden on retail too, as it already was on WoW Forever." },
            { forever = true, module = "Nameplates", text = "The level box and its target border line up with the game's redrawn nameplates again." },
            { forever = true, module = "Profiles & Presets", text = "Importing a profile's Edit Mode layout while using the Gamepad interface style keeps that layout's gamepad systems." },
            { module = "Quality of Life", text = "The Shifter now moves the game's Options window too." },
            { module = "Quality of Life", text = "A hidden talking head no longer reappears later, for example when you leave Edit Mode." },
            { forever = true, module = "Quality of Life", text = "The Shifter now moves the pet stable and Legacy windows too." },
            { module = "Raid Frames", text = "The Full Preview shows the buffs your Buff Manager groups track, at their current size." },
            { forever = true, module = "Raid Frames", text = "Under the Party Frames kit, the health and power bar shapes no longer change with the game's new frame art." },
            { module = "Resource Bars", text = "Buff colors on the class resource bar no longer cause errors in raids that stopped the bar from updating (combo points looking like they were not generating)." },
            { forever = true, module = "Resource Bars", text = "The Call Totem Bar no longer slips back to Blizzard's spot when your bottom action bars re-stack." },
            { module = "Standalones", text = "Settings pages with glow options no longer show an error in the standalone editions." },
            { module = "Unit Frames", text = "With Show Icon on Portrait, the cast icon no longer covers the portrait's border, inner shadow and outer ring." },
            { module = "Unit Frames", text = "Under Blizzard Style with the portrait on the right, the Target of Target, Focus Target and pet frames' power bar no longer runs into the portrait ring." },
            { forever = true, module = "Unit Frames", text = "Under the WoW Forever look, the bars, names, type strip, PvP crest and combo points line up with the game's redrawn unit frames again, and every bar fills its track right up to the bronze rim." },
            { forever = true, module = "Unit Frames", text = "Under Blizzard Style, the health, power and portrait shapes no longer change with the game's new frame art." },
            { forever = true, module = "Unit Frames", text = "With your cast bar hidden for the Gamepad interface style, the game's own gamepad cast bar shows again (the Resource Bars cast bar too)." },
            { module = "Unit Frames", text = "Escape in the Player Aura Bars Edit Filters window now closes that window instead of the whole settings window." },
            { module = "Unit Frames", text = "Turning a frame's Raid Marker back on shows the current marker right away, instead of after the next marker change." },
            { module = "Localization", text = "Spanish (Spain) translation added, and German, Korean, Brazilian Portuguese and Traditional Chinese translations updated for the latest options." },
        },
        -- Closing thank-you; its "contributors" word links to the Legends contributors box.
        thanks = true,
    },
    {
        version = "9.5.5",
        heroes = {
            {
                -- Full-width banner with the performance bar-chart art, as 9.0.1's.
                banner = true,
                title  = "Performance Patch",
                desc   = "CPU usage has been reduced across the suite, with the biggest gains in Nameplates, Chat, Action Bars, Resource Bars, Unit Frames, Cooldown Manager, and Spec Changes.",
            },
        },
        fixes = {
            { forever = true, module = "Action Bars", text = "Fixed combat errors from Blizzard's hidden action buttons and the gamepad bars (blocked actions and secret value errors on cooldowns)." },
            { module = "Blizzard Skins+", text = "Fixed a stack overflow error on zone changes in sessions where the interface holds a very large number of frames." },
            { forever = true, module = "Forever Essentials", text = "Shorten Equip Lines in Simplified Stats is now off by default; turn it on in Forever Essentials > General." },
            { forever = true, module = "Forever Essentials", text = "Simplified Stats lists spell healing before spell damage, matching the item's own Equip line." },
            { module = "Nameplates", text = "Pandemic Glow and Dispel Glow now draw Blizzard's own pandemic border instead of an animated glow. Pandemic Glow is a simple toggle, and the dispellable-buff border is Show Glow in the Enemy Buff Filter's settings." },
            { module = "Unit Frames", text = "New Health # Short text, always one decimal (230.5K)." },
            { module = "Unit Frames", text = "Text X/Y offsets reach twice as far, and the mini and boss frames' texts can color their level by difficulty." },
            { module = "Localization", text = "Brazilian Portuguese translation updated for the latest options." },
        },
        -- Closing thank-you; its "contributors" word links to the Legends contributors box.
        thanks = true,
    },
    {
        version = "9.5.4",
        heroes = {
            {
                module = "Nameplates",
                title  = "Pandemic Glow",
                desc   = "Your debuffs on enemy nameplates glow again while they are in their pandemic window, when a recast keeps the time left. The style, color and settings you had before come back, now with Default, Custom and Class color choices.",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "EXTRA AURA OPTIONS", highlight = "Pandemic Glow Style" },
            },
            {
                -- The sliders are built only on clients that have these CVars (patch 12.1.5 restored them).
                patch  = "12.1.5",
                module = "Nameplates",
                title  = "Stacking Speed and Top Screen Inset",
                desc   = "Once you have updated to the 12.1.5 client, Nameplate Spacing has two new sliders for settings Blizzard brought back in this patch: how fast stacked nameplates slide into place, and how close nameplates can come to the top of the screen.",
                nav    = C_CVar.GetCVarInfo("nameplateMotionSpeed") and { module = "EllesmereUINameplates", page = "General",
                           section = "NAMEPLATE SPACING", highlight = "Stacking Speed" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Macro Manager",
                desc   = "The new Macros tab builds macros by click: commands, spells, targets and conditions line by line, with the live macro text that you can also edit directly. Save each one for your account or character, pick its icon and drag it onto your bars; turn it on at the top of the tab.",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Macros",
                           section = "MACRO", highlight = "Enable Macro Manager" } or nil,
            },
            {
                module = "Unit Frames",
                title  = "Pet Frame Auras",
                desc   = "The pet frame can now show its buffs and debuffs, with their own location, size and position, styled like the frame you pick in Copy Auras From.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Buffs Location",
                           preSelect = function() if EllesmereUI._setMiniUnit then EllesmereUI._setMiniUnit("pet") end; EllesmereUI._pendingMiniSelect = "pet" end },
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Skip Visible Bars When Paging",
                desc   = "An optional Action Bar 1 setting makes next/previous page skip the pages your other enabled bars use, like Blizzard's paging",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "PAGING", highlight = "Skip Visible Bars When Paging",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
            {
                forever = true,
                module = "Action Bars",
                title  = "Berserker Stance Paging",
                desc   = "Warriors can now set a bar to page while in Berserker Stance",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIActionBars", page = "Bar Display",
                           section = "PAGING", highlight = "Berserker Stance",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end } or nil,
            },
            {
                -- Retail only: the toggle is built for Holy Paladins and never on WoW Forever.
                module = "AuraBuff Reminders",
                title  = "Beacon M+ Reminders",
                desc   = "For Holy Paladins: during Mythic+ boss fights, your tank's raid frame shows a glowing red Beacon while they have your Beacon of Light or Faith",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "CORE", highlight = "Beacon M+ Reminders" } or nil,
            },
            {
                forever = true,
                module = "AuraBuff Reminders",
                title  = "Well Fed",
                desc   = "An optional reminder when you have no food buff, counting every food including Grilled Squid, Nightfin Soup and the other raid foods",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "WOW FOREVER", highlight = "Well Fed" } or nil,
            },
            {
                -- A search keyword with no setting: static.
                module = "Bags",
                title  = "Bind Type Search",
                desc   = "Type BoP, BoE or WuE in the bag or bank search box to show only items with that bind type",
            },
            {
                -- The option sits in the Show Pinned Items cog.
                module = "Bags",
                title  = "Hide Pinned Items from Their Categories",
                desc   = "An option in the Pinned Items cog shows pinned items only in Pinned Items, not in their categories or Recent Items",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "CATEGORIES", highlight = "Show Pinned Items" },
            },
            {
                module = "Bags",
                title  = "Open with Character Window",
                desc   = "An optional setting opens your bags with the character window and closes them when you close it",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "EXTRAS", highlight = "Open Bags with Character Window" },
            },
            {
                -- The icon is an entry of the Bag Top Bar Icons dropdown.
                module = "Bags",
                title  = "Quick Actions",
                desc   = "An optional Bag Top Bar icon dims every item but those your spells work on, like Disenchant or Pick Lock; click one to cast it, or just Alt-click it",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "EXTRAS", highlight = "Bag Top Bar Icons" },
            },
            {
                -- Retail only: the options live on the Character Sheet card (Item Details,
                -- the Socket Panel cog and the GEAR FLYOUT section).
                module = "Blizzard Skins+",
                title  = "Stat Letters",
                desc   = "Optional letters on character sheet slots, gear flyout items and socketed gems show each item's secondary stats, largest first",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "CORE OPTIONS", highlight = "Item Details" } or nil,
            },
            {
                module = "Chat",
                title  = "Chat Menu Button",
                desc   = "An optional sidebar button (off by default) opens Blizzard's chat menu for chat types, emotes and your spoken language",
                nav    = { module = "EllesmereUIChat", page = "Sidebar",
                           section = "ICONS", highlight = "Sidebar Icons" },
            },
            {
                -- Retail only (no Talent Conditions on WoW Forever); picked in each empty slot's menu on the bars: page-only.
                module = "Cooldown Manager",
                title  = "Empty Slot Talent Conditions",
                desc   = "Empty slots on cooldown and utility bars can take Talent Conditions, so they only reserve space while the talents you pick are taken or not taken",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end } or nil,
            },
            {
                -- Picked in each spell's menu on the bars: page-only.
                module = "Cooldown Manager",
                title  = "Ignore Resource Cost",
                desc   = "A per-spell option under Cooldown Saturation keeps an icon in full color while you lack the resource to cast it; out of range still tints it red",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                -- Picked in each spell's menu on the bars: page-only.
                module = "Cooldown Manager",
                title  = "Glows Combine With Hide Effects",
                desc   = "The Cooldown State glows are now + toggles in each spell's menu, so a glow can combine with Lower Alpha (On CD) or a Hidden effect",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                module = "Cooldown Manager",
                title  = "Glow When Usable & Glow When Visible",
                desc   = "Bar Glows can light a button whenever its ability can be pressed, and buff icons can glow while shown, so a Show When Missing buff lights up",
                nav    = { module = "EllesmereUICooldownManager", page = "Bar Glows" },
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Junk Items",
                desc   = "An optional window lists your cheapest gray and Junk Marker items by vendor value; Ctrl + Left Click deletes a stack, Middle Click hides an item",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "JUNK ITEMS", highlight = "Enable Junk Items Window" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Simplified Stats",
                desc   = "Item tooltips now show Equip: and Set: stats as short lines like +52 Spell Power, with optional stat colors and a merged Spell Power line",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "SIMPLIFIED STATS", highlight = "Shorten Equip Lines" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Reveal Unexplored Areas",
                desc   = "The world map can show the areas you have not explored yet, tinted in a color you pick so they stand apart",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "WORLD MAP", highlight = "Reveal Unexplored Areas" } or nil,
            },
            {
                -- The Corner Radius cog sits on the Border Size slot; this opens the Unit Frames one.
                module = "General",
                title  = "Choose Which Corners Round",
                desc   = "The Corner Radius cog can round only the corners you pick, and a detached power bar or a nameplate's cast bar can round as one shape with its frame",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Border Size",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "General",
                title  = "Current / Max Text",
                desc   = "Health and power text can show current / maximum values, Classic-style, on unit frames, nameplates and Resource Bars",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "HEALTH BAR", highlight = "Right Text",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "General",
                title  = "EUI Legends Spotlight",
                desc   = "EUI Legends moved to its own sidebar page below Profiles & Presets, and now spotlights the Seasonal Legend and the All-Time Legend",
                nav    = { module = "_EUILegends", page = "EUI Legends" },
            },
            {
                module = "General",
                title  = "Module Resets in Global Settings",
                desc   = "The Reset buttons on module pages moved to Global Settings: Reset EUI Module Settings resets one module, or ALL of EUI, after you type Confirm",
                nav    = { module = "_EUIGlobal", page = "General" },
            },
            {
                -- Border Style shows only on the WoW Forever look; this opens the Chat one.
                forever = true,
                module = "General",
                title  = "Border Styles",
                desc   = "On the WoW Forever look, Chat and Damage Meters can pick Slim, Slim Textured or Heavy Bronze borders, and the Minimap is now a bronze Forever Square",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIChat", page = "Chat",
                           section = "DISPLAY", highlight = "Border Style" } or nil,
            },
            {
                -- The row shows only under Blizzard Style or the WoW Forever look.
                forever = true,
                module = "Minimap",
                title  = "Blizzard Style Square",
                desc   = "Blizzard Style's minimap is now a thin bronze square with the zone name in its title bar; its Circle matches WoW Forever's round one",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIMinimap", page = "Minimap",
                           section = "DISPLAY", highlight = "Border Style" } or nil,
            },
            {
                module = "Nameplates",
                title  = "Always Threat Colors",
                desc   = "Show Threat Colors adds Always, which shows them even when you play solo with no pet out; the old Always is now called Group or Pet",
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "THREAT COLORS", highlight = "Show Threat Colors" },
            },
            {
                module = "Nameplates",
                title  = "Aura Tooltips",
                desc   = "An optional Show Buff / Debuff Tooltips setting shows a spell's tooltip when you hover its icon on a nameplate",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "EXTRA AURA OPTIONS", highlight = "Show Buff / Debuff Tooltips" },
            },
            {
                module = "QoL",
                title  = "/way Command",
                desc   = "The optional /way command (also /euiway) turns coordinates, zone names or map IDs into map pin links and announces when you reach a pin",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "WAYPOINT COMMAND", highlight = "Enable /way Command" },
            },
            {
                module = "QoL",
                title  = "Potion Ready and Unspent Talents Alerts",
                desc   = "Quality of Life's new ALERTS section adds a Potion Ready alert and an Unspent Talents alert beside the Combat Alert, all on one movable anchor",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "ALERTS", highlight = "Potion Ready Alert" },
            },
            {
                -- Compact Mode sits in the Frame Spacing cog, Grid Mode in the Group Spacing one.
                module = "Raid Frames",
                title  = "Compact Mode",
                desc   = "With a Pixels border, Compact Mode joins your party or raid frames into one bordered block, and Grid Mode joins the raid groups into one grid",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "FRAME DISPLAY", highlight = "Frame Spacing" },
            },
            {
                module = "Raid Frames",
                title  = "Role Text",
                desc   = "Show Tank, Healer or DPS as colored text instead of the role icon, with a color for each role",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "INDICATORS", highlight = "Role Icons" },
            },
            {
                module = "Raid Frames",
                title  = "Matching Power and Name Bar Dividers",
                desc   = "With the Pixels border styles, the power bar's Divider or Border can match the frame border, and the Top Name Bar can show a matching divider",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "POWER BAR", highlight = "Border Style" },
            },
            {
                -- The Growth Direction row shows only while Position is Free Move.
                module = "Raid Frames",
                title  = "Pet Growth Direction",
                desc   = "Pet frames set to Free Move can now grow down, up, right or left, instead of always following your party or raid frames",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "PET FRAMES", highlight = "Show Pets" },
            },
            {
                -- The blessing lists sit in the Missing Buffs cog (WoW Forever only).
                forever = true,
                module = "Raid Frames",
                title  = "Blessing Priority Lists",
                desc   = "The Tank, Healer and DPS blessings in Missing Buffs are drag-to-order priority lists, with per-class exceptions for members who need a different one",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "INDICATORS", highlight = "Missing Buffs" } or nil,
            },
            {
                module = "Resource Bars",
                title  = "Per-Spec Hash Lines",
                desc   = "The Health and Power bars can show their own hash lines for each spec or talent, set in their new Threshold & Hash Lines editor",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "POWER BAR", highlight = "Threshold & Hash Lines" },
            },
            {
                -- The row is built on WoW Forever only (spell ranks).
                forever = true,
                module = "Resource Bars",
                title  = "Show Spell Rank",
                desc   = "The player cast bar can show the rank of the spell you are casting, such as Frostbolt (Rank 4)",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Cast Bar",
                           section = "DISPLAY", highlight = "Show Spell Rank" } or nil,
            },
            {
                module = "Unit Frames",
                title  = "Max Important",
                desc   = "With the Important or Own debuff filter, important debuffs from others get their own limit under Max Count",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Debuff Display",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end; EllesmereUI._pendingUnitSelect = "target" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "With Always Show Buttons off, the pet bar now shows up when you summon your pet in combat instead of staying hidden until combat ends." },
            { module = "Action Bars", text = "The pet bar's Attack button now stops flashing once your pet stops attacking, as it does on Blizzard's bar, instead of flashing on after combat." },
            { module = "Action Bars", text = "The vehicle exit button now stays where you place it in Edit Mode instead of moving back to the main action bar after a reload." },
            { module = "Action Bars", text = "Fixed a niche issue where the Extra Action Button could disappear until the end of a fight when Blizzard rearranged its bottom-of-screen frames mid-combat; it now stays usable at Blizzard's spot until combat ends." },
            { module = "Action Bars", text = "Unlock Mode no longer shows a mover for the Extra Action Button while its visibility is set to Never, like the other bars." },
            { forever = true, module = "Action Bars", text = "With the Gamepad interface style, the action bar extras for the spellbook, the macro window, Quick Keybind, the spell flyout and bar paging now step aside to avoid blocked-action errors." },
            { forever = true, module = "Action Bars", text = "Under Blizzard Style, the micro menu and bag bar no longer sit inside WoW Forever's bronze frame, matching the rest of the look." },
            { forever = true, module = "AuraBuff Reminders", text = "The AuraBuff Reminders settings now say up front that the module is for out-of-combat buff and consumable reminders, and link to the Cooldown Manager's Buffs bar for in-combat and rotational auras." },
            { module = "Bags", text = "The gold tooltips of the bag window and the Data Bars Gold block now read one shared list of your characters' gold, so their amounts and totals match." },
            { module = "Bags", text = "Gold Tracking and History is now one account-wide switch, also on the Data Bars Gold block, and Data Bars no longer records your characters' gold while it is off." },
            { module = "Blizzard Skins+", text = "A tooltip whose fixed position is linked to a screen edge in Unlock Mode no longer jumps up and back while you hover unit frames or action buttons." },
            { module = "Blizzard Skins+", text = "Chat bubbles from speakers who start off screen are now styled once they come into view, and a styled bubble stays styled when you turn away and back." },
            { module = "Blizzard Skins+", text = "The loot roll timer bar is no longer hidden behind the skinned loot roll window." },
            { module = "Blizzard Skins+", text = "The merchant quantity box now fits both lines for items sold in bundles, centers a single count, and keeps its look when you shift-click another item while it is open." },
            { module = "Blizzard Skins+", text = "The inspect window's item text toggle now only shows on the Character tab." },
            { module = "Blizzard Skins+", text = "The character sheet's Equipment tab now matches the other tabs: its buttons and scroll bar are skinned instead of Blizzard's red buttons, and the buttons and gear set list fill the full column width." },
            { module = "Blizzard Skins+", text = "The character sheet's gear flyout now matches the skinned sheet instead of showing Blizzard's parchment and round icon borders." },
            { module = "Blizzard Skins+", text = "The character sheet and inspect window now show an upgraded or catalyzed item's real item level instead of its base level." },
            { module = "Blizzard Skins+", text = "Character sheet and inspect window item labels read before an item's data has loaded now fill in once it arrives instead of staying blank or showing a missing enchant." },
            { module = "Blizzard Skins+", text = "A slot emptied while the character sheet was closed no longer keeps the removed item's labels after you change a sheet setting." },
            { module = "Blizzard Skins+", text = "The character sheet's item level, upgrade track and enchant text, and the inspect window's enchant names, now follow Disable Slug Outline." },
            { forever = true, module = "Blizzard Skins+", text = "The character sheet no longer shows a gray bar across the top of the character model after the latest game update." },
            { forever = true, module = "Blizzard Skins+", text = "The inspect window's new PvP tab no longer opens blank, and the item level and slot labels stay on the character tab instead of floating over the PvP and Guild tabs." },
            { forever = true, module = "Blizzard Skins+", text = "The Looking For Group window's new Voice Chat dropdown is now skinned." },
            { module = "Chat", text = "Up and Down now also recall the addon slash commands you typed, like /eui, not only messages." },
            { module = "Cooldown Manager", text = "Tracking Bars now show a tracked buff or target debuff the moment it starts, even from a proc or in Mythic+, instead of waiting for your next cast." },
            { module = "Cooldown Manager", text = "Hidden (Outside Form/Stance) now hides Druid caster spells such as Moonfire, Rebirth and the Restoration heals in forms they cannot be cast in, unless a talent or proc allows it." },
            { module = "Cooldown Manager", text = "Spells set to Hidden (CD Ready) no longer flash onto the bar for a moment as a global cooldown ends." },
            { module = "Cooldown Manager", text = "Group loot rolls no longer get pushed off screen or to random heights; they now sit clear of your action bars, Cooldown Manager bars and Tracking Bars." },
            { module = "Cooldown Manager", text = "The talking head, the encounter bar and Blizzard's other frames stacked above your action bars no longer get pushed up or off screen while tracked buffs are showing." },
            { module = "Cooldown Manager", text = "Saving Edit Mode with an Essential or Utility viewer snapped to another frame no longer anchors that viewer to an EllesmereUI bar in the saved layout." },
            { module = "Cooldown Manager", text = "With a Pixels or Pixels Textured border, the cooldown swipe now stays under the border line, so its rounded corners and bottom edge no longer disappear while a cooldown runs." },
            { module = "Cooldown Manager", text = "Bar Glows now stay with the ability they were set on, so a stance or form swap no longer moves a glow onto a different ability." },
            { module = "Cooldown Manager", text = "Picking Lower Alpha (On CD) with Apply to This Spell now asks for its opacity, as clicking it does, instead of setting 50%." },
            { module = "Cooldown Manager", text = "Lifebloom's pandemic glow on Tracking Bars now starts exactly when a refresh would keep its remaining time, talents that lengthen that window included, instead of always at 30% of its duration." },
            { module = "Cooldown Manager", text = "Hovering an icon in the bar preview now shows its spell name and that clicking it opens its alert settings." },
            { forever = true, module = "Cooldown Manager", text = "The Racial slot now tracks the right racial for Humans, Night Elves, Trolls and Skyborne." },
            { module = "Damage Meters", text = "Force English Units now follows the profile you switch to instead of keeping the previous profile's setting." },
            { module = "Data Bars", text = "Blocks on a bar made from a starter template, and blocks you add, now show at their real widths in the preview strip right away." },
            { forever = true, module = "Forever Essentials", text = "The threat meter's Not While Tanking now ignores Bear Form and Defensive Stance while someone in your group has the tank role." },
            { module = "General", text = "Reduced memory use across the whole EllesmereUI suite." },
            { module = "General", text = "Odd sizes of the Pixels and Pixels Textured borders no longer sit further out than the next even size." },
            { module = "General", text = "Turning off Hide Blizzard Party Panel during combat now brings the panel back once combat ends, and turning it off no longer shows an empty panel tab while you are solo." },
            { module = "General", text = "The Cooldown Manager, Action Bars, Raid Frames and Unit Frames no longer interfere with Edit Mode's own updates, which could cause blocked-action errors or unsnap frames you had snapped to Blizzard's party, raid or boss frames." },
            { module = "General", text = "Macro Factory buttons now update the moment a macro is created or deleted, and changes made to spec macros during combat (such as Show Tooltip) are applied when combat ends." },
            { module = "General", text = "A confirmation popup that is open when the accent color changes, such as on an automatic spec profile switch, now stays open in the new color instead of closing." },
            { module = "General", text = "Full-account profile exports no longer include your characters' gold balances." },
            { module = "General", text = "Greyed-out buttons in the settings, such as Apply Template on the Glows page, now explain on hover why they are unavailable." },
            { module = "General", text = "The icons beside Unlock Mode, Global Settings, Patch Notes and Profiles & Presets in the options sidebar are no longer slightly squashed." },
            { module = "General", text = "The donor named at the top right of the options window is now most often the Seasonal or All-Time Legend, then their #2 and #3, then the rest of the all-time donors." },
            { module = "General", text = "Global search now finds the settings on almost every options page without opening that page first." },
            { module = "General", text = "Settings links, such as global search results, now highlight the exact setting instead of an earlier one whose name contains it." },
            { module = "General", text = "Patch Notes cards for a module you have turned off are no longer clickable, so they no longer show a Lua error or jump the page back to the top." },
            { module = "General", text = "A settings page that was reset while the settings window was closed (for example by a profile change) now rebuilds when the window opens instead of showing an empty page." },
            { module = "General", text = "Changing the Window Scale right after a settings page rebuilt itself now re-aligns that page's borders correctly." },
            { module = "General", text = "Opening an add-on page that has no tabs no longer breaks the other settings pages, which could then show outside or on top of the settings window." },
            { module = "General", text = "A settings page that runs into an error while building no longer leaves the settings window in a broken state until a reload." },
            { module = "General", text = "A setting that makes its own page rebuild while that page is still building no longer leaves a half-built copy of the page on screen." },
            { module = "General", text = "A settings page that rebuilds while one of its sliders is being dragged no longer leaves slider tooltips, Shift + mouse wheel window scaling and some live preview updates switched off until a reload." },
            { patch = "12.1.5", module = "General", text = "Consumable reminders, the character sheet's item details and Great Vault item levels keep working now that Blizzard has removed its old item functions." },
            { patch = "12.1.5", module = "General", text = "Buff and debuff rows you have turned off on unit frames, raid frames, nameplates and Player Aura Bars no longer do any work when auras change." },
            { forever = true, module = "General", text = "On the WoW Forever look, Chat, Damage Meters and the threat meter draw Blizzard's latest weathered bronze line cleanly (Slim Textured), and the older flat line is the Slim border style." },
            { forever = true, module = "General", text = "The WoW Forever look's slim bronze borders on Chat, Damage Meters, the threat meter and the XP bar now have clean angled corners that match the action bars." },
            { forever = true, module = "General", text = "Cast bars now find every class's interrupt in all its ranks, so the interrupt-ready color and kick tick work for Shamans, Druids and Warriors, with Shield Bash, Pummel and Feral Charge following your stance or form." },
            { forever = true, module = "General", text = "The Threat % text on unit frames and nameplates can now be moved up to 300 in any direction with its X and Y Offset sliders, up from 100." },
            { module = "Minimap", text = "Blizzard's Toggle Minimap key now keeps the map hidden until you press it again, instead of the map coming back when you change targets, leave combat, switch profiles or toggle the damage meters." },
            { module = "Mythic+ Tools", text = "Objective split times and their comparisons now survive leaving and re-entering the dungeon during a key, a reload no longer changes their comparisons, and split times from an abandoned or crashed key no longer carry over into your next key." },
            { module = "Mythic+ Tools", text = "A finished key's timer color now matches its result, also for keys finished close to the limit or after a reload." },
            { module = "Nameplates", text = "Enemy players in battlegrounds and arenas now show their class color on the health bar even with Blizzard's enemy nameplate class colors turned off, as they do in the open world." },
            { module = "Nameplates", text = "Pixels and Pixels Textured custom borders no longer flicker a thin gap against the health bar while the plate moves." },
            { module = "Nameplates", text = "Objective gauges above friendly NPCs now show while Show Friendly NPC Nameplates is on." },
            { module = "Nameplates", text = "After a duel, your opponent's name shows again right away instead of only once you look away and back." },
            { forever = true, module = "Nameplates", text = "The Elite/Rare Indicator in Core Positions now also works on the WoW Forever look, where it starts unchecked." },
            { module = "Nameplates", text = "At a Window Scale other than 100%, the Grow, Strata and other dropdowns in the Display page cogs now open at the right size the first time too." },
            { module = "Nameplates", text = "The nameplate preview no longer stretches or pushes the class resource out of view at a large Class Resource Y Offset; it shows the offset as a small number instead." },
            { module = "Nameplates", text = "Threat colors now also show for damage dealers and healers playing solo with a pet out, so you can see which mobs your pet is holding." },
            { forever = true, module = "Nameplates", text = "Threat colors now treat you as the tank in Bear Form, Dire Bear Form, Defensive Stance or with Righteous Fury up while nobody in your group has the tank role, so tanks see tank colors solo too." },
            { module = "QoL", text = "The Upgrade Calculator now keeps your +80 / -80 crest adjustments after a reload, and Update at Upgrader clears them." },
            { module = "QoL", text = "Moving the loot windows (Group Loot, Bonus Roll, Alert Toasts) no longer risks blocked-action errors when rolls appear, and turning a mover off or resetting it puts its window back right away." },
            { module = "QoL", text = "Turning off Move Top Bar Event Text in Unlock Mode, or resetting its mover, now puts the text back in its usual spot right away instead of after a reload." },
            { module = "QoL", text = "Switching profiles now updates the Battle Res and Bloodlust icons right away (synced profiles keep their own icon positions), and resetting Quality of Life now also resets them, the /keys popup and the LFG Reminder." },
            { module = "QoL", text = "Hide Error Messages now lets every error on its keep list show (being dead, a dead pet, dungeon kick votes and pickpocketing), and turning it off now applies after a reload." },
            { forever = true, module = "QoL", text = "The Shifter now moves the new friends window and the Looking For Group window." },
            { module = "Quest Tracker", text = "A tracker hidden by the Mythic+ timer no longer keeps processing quest updates in the background, and Auto Accept / Auto Turn In Quests keep working while the tracker is hidden in raids and arenas." },
            { module = "Quickdraw", text = "Action menus no longer come back empty after a reload when the Quickdraw settings page was opened before visiting another settings page, and the error this could show is gone." },
            { module = "Raid Frames", text = "The Buff Manager's Defensives filter now includes Primordial Bond for Shamans." },
            { module = "Raid Frames", text = "Buff Manager indicators now follow a conditional or spec override's size and layout when it swaps in, instead of keeping the old size or drawing off their corner." },
            { module = "Raid Frames", text = "Healer Mana now shows the new group once combat ends when someone joins or leaves mid-fight while the raid and party frames are hidden, instead of keeping the old one." },
            { module = "Raid Frames", text = "After using the options search, changes on the raid frames page no longer land in the party frames' settings." },
            { module = "Raid Frames", text = "Changing the absorb style, color or opacity with rounded corners no longer causes a Lua error." },
            { module = "Raid Frames", text = "Role icons set to Show Behind Border now draw under textured frame borders too." },
            { module = "Raid Frames", text = "Frame Spacing and Group Spacing, and the party Frame Spacing, now go below -1 at every UI scale, so frames with 2 px borders can share one border line." },
            { module = "Raid Frames", text = "The Click Casting icon grids no longer leave stray or stacked divider lines after switching between Spells, Macros and Items, and Quickbind's divider lines no longer get brighter with every binding." },
            { module = "Raid Frames", text = "The eye icon tip on the Frames page no longer stacks a new copy every time the page refreshes, so a single Okay dismisses it and no leftover copy stays on screen over other pages." },
            { module = "Raid Frames", text = "Group members whose role the game keeps hidden from addons no longer risk Lua errors." },
            { patch = "12.1.5", module = "Raid Frames", text = "Role icons now show for group members whose role the game keeps hidden from addons." },
            { forever = true, module = "Raid Frames", text = "Missing Buffs no longer reminds you to bless a member who already carries one of your blessings, since a paladin keeps only one blessing on each target." },
            { forever = true, module = "Raid Frames", text = "Group members with no assigned role now follow your DPS blessing list in Missing Buffs instead of always showing Kings, since many groups never set roles." },
            { module = "Resource Bars", text = "The GCD bar now hides as soon as a short global cooldown ends in instanced combat, and in every fight on WoW Forever, instead of lingering (Rogues, Feral Druids and hasted characters)." },
            { module = "Resource Bars", text = "In instanced combat, and in every fight on WoW Forever, the GCD bar no longer shows up again after a hard cast finishes or after a spell that does not trigger the global cooldown, such as an interrupt." },
            { module = "Resource Bars", text = "Channel tick marks on the cast bar are now correct for Penance, with or without Castigation, and on WoW Forever for every rank of Mind Flay and Penance." },
            { module = "Resource Bars", text = "Hash lines turned off and back on now reappear right away instead of after a reload." },
            { module = "Resource Bars", text = "The mouse wheel over a short Threshold & Hash Lines list now scrolls the settings page instead of doing nothing." },
            { module = "Resource Bars", text = "Druid Power Bars that still carry per-form thresholds from the old Advanced mode now use the spec thresholds and hash lines you add, in any form without a per-form entry." },
            { forever = true, module = "Resource Bars", text = "Elements linked above or below the Power Bar now move clear of the druid's Mana Bar while Shapeshifted instead of being covered by it." },
            { module = "Unit Frames", text = "Putting buffs and debuffs on the same spot now moves the other row out of the way instead of turning it off or drawing both on top of each other." },
            { module = "Unit Frames", text = "Buff and debuff rows you have turned off no longer slow down login." },
            { module = "Unit Frames", text = "Switching Class Resource between the Blizzard style and another style no longer makes Resource Bars' Blizzard Class Resource Art jump under the player frame when your cast bar shows or hides, or leaves the Blizzard bar overlapping your cast bar while you cast." },
            { module = "Unit Frames", text = "The Mini Frames and Boss Frames previews no longer leave an empty gap below them after switching units or changing a setting while the Main Frames preview hint is still showing." },
            { module = "Unit Frames", text = "Bottom-anchored player buffs and debuffs now sit below the Resource Bars docked under the player frame instead of overlapping them; if you had moved them down by hand, reset their Y offset." },
            { module = "Unit Frames", text = "Player Aura Bars icons with a custom Icon Shape no longer zoom far into the spell; the shape now shows the whole icon at your Icon Zoom, as on the action bars." },
            { forever = true, module = "Unit Frames", text = "Combo points on the unit frames, the target nameplate and Resource Bars now update when your points move to a new target." },
            { module = "Unlock Mode", text = "An edit made while Unlock Mode is still opening, such as a width match, now asks to be saved when you exit instead of being kept without a prompt." },
            { module = "Unlock Mode", text = "Exiting after combat interrupted it no longer asks to save changes you never made." },
            { module = "Unlock Mode", text = "Reopening an element's cog menu after closing it mid-edit no longer leaves your keyboard typing into a hidden box." },
            { module = "Unlock Mode", text = "Exit Without Saving now fully restores pet fallback anchors, so the element keeps moving when your pet is summoned or dismissed." },
            { module = "Localization", text = "Brazilian Portuguese, French, German, Korean, Simplified Chinese and Traditional Chinese translations updated for the latest options, and the Raid Frames Free Move labels now show in your language." },
        },
        -- Closing thank-you; its "contributors" word links to the Legends contributors box.
        thanks = true,
    },
    {
        version = "9.4",
        heroes = {
            {
                module = "Bags",
                title  = "Compact Display",
                desc   = "Bag Style and Bank Display have a new Compact choice: each category becomes a block of icons with its name and count on top, side by side with a small gap and arranged to keep the window short. In the bag window, carry an item to drop it on a category.",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "LAYOUT", highlight = "Bag Style" },
            },
            {
                -- Corner Radius is a cog beside each module's border color; this
                -- opens the Unit Frames one.
                module = "General",
                title  = "Rounded Corners",
                desc   = "Unit Frames, Raid Frames, Nameplates and Resource Bars can round their corners: a Corner Radius cog next to each border color rounds the bars along with their Solid, Glow or Shadow border. Corners stay square until you set a radius.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Border Size",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- The effect is picked in each spell's menu on the bars: page-only.
                module = "Cooldown Manager",
                title  = "Hidden Outside Form/Stance",
                desc   = "A new Cooldown State Effect, picked in each spell's menu, shows a spell only in the form or stance it can be cast in, so caster spells hide while you are in a form that cannot cast them. A Shift Icons version also closes the gap the hidden icons leave.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                -- The coin is the Junk Icon of Bag Top Bar Icons.
                module = "Bags",
                title  = "Junk Marker",
                desc   = "A coin button on the bags, on by default, marks items as junk with a click. Marked and grey items gather in their own Junk category, Junk Item Visuals picks how they look, and Sell Junk or Auto Sell Junk sells them at merchants.",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "EXTRAS", highlight = "Bag Top Bar Icons" },
            },
        },
        features = {
            {
                module = "Bags",
                title  = "Bag Top Bar Icons",
                desc   = "Pick which of the Bags, Junk and Sort icons show in the bag window's top bar",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "EXTRAS", highlight = "Bag Top Bar Icons" },
            },
            {
                module = "Bags",
                title  = "Frame Strata",
                desc   = "Choose the layer the bags and bank draw on; it replaces Allow Windows Over Bags, and your choice there carries over",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "LAYOUT", highlight = "Frame Strata" },
            },
            {
                module = "Bags",
                title  = "Hide Sidebar Icons When Collapsed",
                desc   = "A collapsed sidebar can hide completely, with its expand arrow next to the Inventory title",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "CATEGORIES", highlight = "Hide Sidebar Icons When Collapsed" },
            },
            {
                module = "Bags",
                title  = "Quality Item Border",
                desc   = "One setting now colors item borders by quality in every bag and bank display, on by default; Grid and Compact can now turn it off",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "EXTRAS", highlight = "Quality Item Border" },
            },
            {
                -- The lock sits on the bag and bank windows themselves: static.
                module = "Bags",
                title  = "Window Lock",
                desc   = "The bag and bank windows get a corner lock: unlocked, a plain drag moves them (no Shift needed) and a grip resizes them",
            },
            {
                -- Set on the Friends List card (WoW Forever only).
                forever = true,
                module = "Blizzard Skins+",
                title  = "Friends List Tiles",
                desc   = "Friends show as EllesmereUI tiles with class icons, class colors, region icons and optional faction banners, and invites can auto-accept",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" } or nil,
            },
            {
                forever = true,
                module = "Forever Essentials",
                title  = "Name Format",
                desc   = "Pick first, last or full names for every module at once, now also on friendly player nameplates, Damage Meters and the threat meter",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "NAME FORMAT", highlight = "First Name" } or nil,
            },
            {
                module = "QoL",
                title  = "Type /cd to open Blizzard CDM",
                desc   = "/cd now opens Blizzard's Cooldown Manager only while this new option is on; it is off by default, leaving /cd free for other addons",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "GENERAL", highlight = "Type /cd to open Blizzard CDM" },
            },
            {
                -- Ignore Older Expansion Quests sits in Auto Accept Quests' cog.
                module = "Quest Tracker",
                title  = "Ignore Older Expansion Quests",
                desc   = "Auto Accept can leave quests from older expansions for you to pick up yourself once you reach max level",
                nav    = { module = "EllesmereUIQuestTracker", page = "Quest Tracker",
                           section = "EXTRAS", highlight = "Auto Accept Quests" },
            },
            {
                -- Assign to Spec sits under the preview in Action Menu Setup.
                module = "Quickdraw",
                title  = "Assign to Spec",
                desc   = "Each action menu can be assigned to the specs it works in, and menus that never load in the same spec can share one keybind",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw",
                           section = "ACTION MENU SETUP" },
            },
            {
                -- Thorns Only on Tank and the blessing dropdowns sit in the Missing Buffs cog.
                forever = true,
                module = "Raid Frames",
                title  = "Blessings by Role",
                desc   = "Missing Buffs reminds you of the blessing you pick for each role (Kings while solo), and Thorns can show on tanks only",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIRaidFrames", page = "Frames",
                           section = "INDICATORS", highlight = "Missing Buffs" } or nil,
            },
            {
                -- Hide Exhaustion is a Debuff Filter entry (player) or a filter cog row.
                module = "Unit & Raid Frames",
                title  = "Hide Exhaustion",
                desc   = "Debuff filters on the unit frames, Player Aura Bars and Raid Frames can now show or hide Sated and the other Bloodlust lockout debuffs",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Debuff Filter",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- The row shows for rogues and druids under the WoW Forever look.
                forever = true,
                module = "Unit Frames",
                title  = "Combo Points Placement",
                desc   = "The Blizzard-style combo points can now show on the target frame, the player frame, or not at all",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "CLASS RESOURCE", highlight = "Combo Points",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end } or nil,
            },
            {
                module = "Unit Frames",
                title  = "Dispel Type Icon",
                desc   = "The player frame can show the dispel type's icon on a corner of its health bar, with its own size and offsets, as Raid Frames does",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Type Icon Position",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "On a first install, the Pet Bar no longer starts hidden in the top-left corner when no pet was out: it starts set to Always above your other bars, where Blizzard places it (the Stance Bar too, for characters without forms yet)." },
            { module = "Bags", text = "Recent Items now lists your newest pickups first in every view, moves an item back to the top when you loot more of it, and no longer lists gear you take off or swap out with an equipment set." },
            { module = "Bags", text = "Picking an item to pin or file now ends when you click outside the bags (instead of passing the click through) or close them, and the selection no longer holds the keyboard." },
            { module = "Bags", text = "An open bank window now follows the bags' search box and Window Scale changes right away, and the Desaturate option of Junk Item Visuals now also greys junk in the bank's Grid and Compact displays." },
            { module = "Bags", text = "The Hide links on the Pinned Items and Recent Items headers now always hide the section you clicked, even after switching between OneBag and All Items." },
            { module = "Bags", text = "A custom category's Edit | Delete links no longer stay on screen after you switch to another view." },
            { module = "Bags", text = "Switching profiles now applies that profile's categories right away." },
            { module = "Bags", text = "The Pinned Items and Recent Items hints now show when you hover their titles, and new users get a one-time tip that sidebar categories can be dragged to reorder them." },
            { module = "Bags", text = "Merge Duplicate Items, Category Title Size and Group Gear by Slot (formerly Group Armory by Slot) now also apply to the List display, which merges duplicates unless you turn it off and groups gear under equipment slot headers." },
            { module = "Bags", text = "The OneBag Randomize button and the OneBag / MultiBag warning text are gone." },
            { module = "Blizzard Skins+", text = "Showing player buffs on tooltips no longer causes an error when hovering raid or party frames in combat." },
            { module = "Blizzard Skins+", text = "Resurrect Accept Glow now needs Reskin Popups and Menus, and is greyed out while that is off." },
            { module = "Blizzard Skins+", text = "Spell ID on Tooltip is now on by default for new installs; existing setups keep their setting." },
            { module = "Blizzard Skins+", text = "The Premade Groups filter's reset X now draws above the filter button's border." },
            { forever = true, module = "Blizzard Skins+", text = "The Looking For Group skin's refresh button now shows its icon, its options cog is a plain cog that is always visible, the big eye in the top left corner is gone, and the role header's background ends on the line under it." },
            { forever = true, module = "Blizzard Skins+", text = "The Character window's Reputation tab now matches the other tabs in the EllesmereUI look, keeping Blizzard's own list on the window's background." },
            { forever = true, module = "Blizzard Skins+", text = "The inspect window's Talents button no longer covers the average item level, and the ranged slot now fits beside the other weapons with its own item level and enchant." },
            { forever = true, module = "Chat", text = "Whisper tabs now blink when a whisper arrives while you are viewing another tab." },
            { forever = true, module = "Cooldown Manager", text = "A queued Heroic Strike, Cleave, Maul or Raptor Strike now lights up on the Cooldown Manager with the same highlight your action bars show." },
            { forever = true, module = "General", text = "Choosing the WoW Forever look now gives the Blizzard Skins+ windows the EllesmereUI skin instead of Blizz Default (the micro menu and bag bar keep Blizzard's look)." },
            { module = "Nameplates", text = "With Debuff Coloring set to Color Border, a combo's color now always shows over its single debuffs." },
            { module = "Quickdraw", text = "Dim Unusable Actions now grays out mount entries where you can't mount, such as indoors." },
            { module = "Quickdraw", text = "Quickdraw is no longer part of Spec Overrides: its per-spec overrides are dropped (your current settings stay), and Assign to Spec on each action menu takes their place." },
            { module = "Resource Bars", text = "With Smooth Bars off, the Devourer Demon Hunter's soul fragments bar no longer eases its fill; every bar now follows its Smooth Bars setting." },
            { module = "Resource Bars", text = "Blizzard Class Resource Art now centers each class's points on the Class Resource Bar's spot, so it no longer sits off center or shifts when you switch characters." },
            { forever = true, module = "Resource Bars", text = "The Mana Bar while Shapeshifted now follows the Power Bar's Smooth Bars setting." },
            { forever = true, module = "Resource Bars", text = "The swing timer's Highlight Queued Attacks now also lights up for the Hunter's Raptor Strike." },
            { forever = true, module = "Unit Frames", text = "Rogues now have their own class resource setting under the EllesmereUI style, hidden until you turn it on, so a rogue's choice no longer changes other classes on the same profile." },
            { module = "Localization", text = "Brazilian Portuguese, German, Simplified Chinese and Traditional Chinese translations updated for the latest options, and the Cooldown Manager's add-by-ID popups now show their error messages in your language." },
        },
    },
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
                           section = "DISPLAY (LIST)", highlight = "Row Height" },
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
                           section = "LAYOUT", highlight = "Frame Strata" },
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
                           section = "POWER BAR", highlight = "Threshold & Hash Lines" },
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
                           section = "BAR SHIFTING", highlight = "Expand Power Bar if No Resource" },
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
