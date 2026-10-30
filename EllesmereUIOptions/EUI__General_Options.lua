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
        version = "9.7.1",
        mini = true,
        features = {
            {
                -- The GENERAL section of the Mail card in Window Skins (both clients).
                module = "Blizzard Skins+",
                title  = "Close Bags on Mail Close",
                desc   = "Closing the mailbox also closes your bags; on by default, in the Mail card's settings",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "GENERAL", highlight = "Close Bags on Mail Close" },
            },
            {
                -- The DataBars page, where blocks are added (retail only: the block is not offered on
                -- WoW Forever).
                module = "Data Bars",
                title  = "M+ Summary Block",
                desc   = "A new block shows your latest Mythic+ run; hover lists every stored run, click opens the Run Summary and right click clears the history",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIDataBars", page = "DataBars" } or nil,
            },
            {
                -- The DISPLAY section of Global Settings > General (both clients).
                module = "General",
                title  = "Accent Colored Settings Elements",
                desc   = "A new Display setting shows the cogwheel and preview icons in your accent color (both off by default), and those icons are now easier to see",
                nav    = { module = "_EUIGlobal", page = "General", section = "DISPLAY",
                           highlight = "Accent Colored Settings Elements" },
            },
            {
                -- Show Nicknames in the player frame's DISPLAY section (both clients); raid and party
                -- frames show CustomNames names with no setting of ours.
                module = "Unit Frames",
                title  = "CustomNames Nicknames",
                desc   = "Names you set in the CustomNames addon now show on raid and party frames, and on your unit frames with Show Nicknames on",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Show Nicknames",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "Chat", text = "Nudging a resized chat window with the arrow keys in Unlock Mode no longer makes it jump, and it stays where you save it." },
            { module = "Cooldown Manager", text = "A spell's right-click menu now shows the settings its icon uses even when they were saved on another form of the spell, such as before a talent changed it, instead of looking empty." },
            { module = "General", text = "Accent-colored text and markers on the Patch Notes and EUI Legends pages, the sidebar's new-patch dot, the Special Thanks name, Nameplates' Edit Tracked Auras links, Resource Bars' threshold buttons and the Move in Unlock Mode buttons now follow accent color changes without a reload." },
            { module = "Nameplates", text = "Switching Debuff Coloring to Color Name no longer leaves a debuff set to Missing showing its old texture or color on the nameplate until a reload." },
            { module = "Unlock Mode", text = "The chat's Unlock Mode settings no longer list an old anchor that does nothing, and that old anchor no longer stops other elements from being anchored to the chat." },
            { module = "Localization", text = "Brazilian Portuguese, German, Korean and Traditional Chinese translations updated for the latest options." },
        },
    },
    {
        version = "9.7",
        heroes = {
            {
                -- The OFFLINE BANK section of the Bags module's Bank page (retail only: the
                -- feature and its section do not exist on WoW Forever).
                module = "Bags",
                title  = "Offline Bank",
                desc   = "Look through your other characters' bags and banks, and the warband bank, from anywhere: pick a character with the button beside the bags or bank title. Item tooltips can also count an item across all your characters, and both are off by default.",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBags", page = "Bank",
                           section = "OFFLINE BANK", highlight = "Offline Bank" } or nil,
            },
            {
                -- Each name text's Name Format (Unit Frames text cogs, nameplate slot cogs, Raid & Party
                -- Frames, Damage Meters; both clients). Opens on the player frame's text slots.
                module = "General",
                title  = "Name Format",
                desc   = "Names on unit frames, nameplates, raid frames and damage meters can show only the first or last name, initials such as I. Stormrage, or a number of characters you choose. Friendly nameplates take it too, and Custom texts take [name:first], [name:last] and [name:abbr].",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "CORE TEXT POSITIONS",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- The RAID BUFF CHECK section of Quality of Life's Raid Tools page (retail only: the
                -- check returns on WoW Forever).
                module = "Quality of Life",
                title  = "Raid Buff Check",
                desc   = "A window lists each group member's flask, food, augment rune, vantus rune and missing raid buffs. It opens on ready checks or from Raid Tools' Buff Check button, and is off by default.",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIQoL", page = "Raid Tools",
                           section = "RAID BUFF CHECK", highlight = "Raid Buff Check" } or nil,
            },
            {
                -- Opens Unlock Mode with the quest tracker's mover selected (both clients).
                module = "Quest Tracker",
                title  = "Move in Unlock Mode",
                desc   = "Drag the quest tracker in Unlock Mode, anchor it to other elements such as the minimap, and set its height from its mover's cog. The first move asks for one reload, and the spot is the same in every spec.",
                onClick = function() EllesmereUI.OpenUnlockModeAt("EQT_Tracker") end,
            },
        },
        features = {
            {
                -- LAYOUT on the Bags page (both clients): Slot Size, Slot Spacing, Background Color,
                -- Background Opacity and Slot Background.
                module = "Bags",
                title  = "Slot Size, Spacing and Colors",
                desc   = "Set the size of item slots and the space between them, tint and fade the window background, and color empty slots in the bags and bank",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "LAYOUT", highlight = "Slot Size" },
            },
            {
                -- The Name Text Settings cog of a Tracking Bar (both clients): page-only.
                module = "Cooldown Manager",
                title  = "Custom Tracking Bar Names",
                desc   = "Give any Tracking Bar a name of your own in its Name Text settings, such as Free Starfall for Touch of the Cosmos",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
            {
                -- FocusKick Options on the CDM Bars page with the FocusKick bar selected (both clients).
                module = "Cooldown Manager",
                title  = "Focus Cast Sound Without the Icon",
                desc   = "The focus cast sound can play without the nameplate icon: leave the FocusKick bar empty and pick your kick, or Any Cast to hear every enemy cast",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           section = "FocusKick Options", highlight = "Focus Cast Sound",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("focuskick") end end },
            },
            {
                -- BARS on the Damage Meters page: the Show Breakdown on Hover switch it rides (retail only).
                module = "Damage Meters",
                title  = "Enemy Breakdowns in Combat",
                desc   = "In this season's Mythic+ dungeons and raids, hovering an enemy in Enemy Damage Taken shows who did how much to it during the pull, not only after it",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIDamageMeters", page = "Damage Meters",
                           section = "BARS", highlight = "Show Breakdown on Hover" } or nil,
            },
            {
                -- COMBAT on Global Settings > General (both clients; off by default).
                module = "General",
                title  = "Round Timer Seconds Down",
                desc   = "Timer seconds can round down like Blizzard's buff frame, so a timer reads 0 in its last second; off by default",
                nav    = { module = "_EUIGlobal", page = "General", section = "COMBAT", highlight = "Round Timer Seconds Down" },
            },
            {
                -- CORE TEXT POSITIONS on the Nameplates Display page (both clients).
                module = "Nameplates",
                title  = "Custom Text",
                desc   = "Any Core Text Position can show your own mix of tags and text, like [name] - [hp:pct]% or [target], with a live preview and tag suggestions",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE TEXT POSITIONS" },
            },
            {
                -- EXTRAS on the Nameplates General page (both clients).
                module = "Nameplates",
                title  = "Out of Combat Opacity",
                desc   = "Enemies that are not in combat can fade to an opacity you choose, so the pack you are fighting stands out from the ones you have not pulled",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Out of Combat Opacity" },
            },
            {
                -- Texture Nameplate and Color Name in the Debuff Coloring dropdown (both clients).
                module = "Nameplates",
                title  = "Texture and Name Debuff Coloring",
                desc   = "Debuff Coloring can tint enemy health bars in a texture you pick, such as one that covers half the bar, or color the enemy's name instead",
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "DEBUFF BASED NAMEPLATE COLORING", highlight = "Debuff Coloring" },
            },
            {
                -- EXTRAS on the Quality of Life page (both clients; off by default).
                module = "Quality of Life",
                title  = "Auto-Accept Resurrection",
                desc   = "Resurrections from players out of combat, such as raid resses after a wipe, are accepted for you, with an option for battle resses too; off by default",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "EXTRAS", highlight = "Auto-Accept Resurrection" },
            },
            {
                -- BATTLEGROUND FRAMES on the Shifter page (both clients; off by default).
                module = "Quality of Life",
                title  = "Move Battleground Frames",
                desc   = "The Shifter page can add Unlock Mode movers for the battleground flag carriers and the capture bar under the minimap",
                nav    = { module = "EllesmereUIQoL", page = "Shifter", section = "BATTLEGROUND FRAMES",
                           highlight = "Move Battleground Frames in Unlock Mode" },
            },
            {
                -- EXTRAS on the Quality of Life page (retail only).
                module = "Quality of Life",
                title  = "Transparent World Map Sidebars",
                desc   = "The black bars beside the maximized world map can go transparent, and clicks, camera turns and zoom pass through them to the game",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIQoL", page = "QoL",
                           section = "EXTRAS", highlight = "Transparent World Map Sidebars" } or nil,
            },
            {
                -- The Auto Accept and Auto Turn In cogs in the Quest Tracker's EXTRAS (both clients).
                module = "Quest Tracker",
                title  = "Hold Shift to Enable",
                desc   = "Auto Accept Quests and Auto Turn In Quests can be set to run only while Shift is held",
                nav    = { module = "EllesmereUIQuestTracker", page = "Quest Tracker", section = "EXTRAS", highlight = "Auto Accept Quests" },
            },
            {
                -- The Toys list of an action menu (both clients).
                module = "Quickdraw",
                title  = "Random Hearthstone",
                desc   = "A Random Hearthstone entry at the top of the Toys list uses a different hearthstone toy you own each time its menu opens",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw", section = "ACTION MENU SETUP" },
            },
            {
                -- TEXT DISPLAY on the Raid & Party Frames Frames page (both clients).
                module = "Raid & Party Frames",
                title  = "Custom Text",
                desc   = "Up to four Custom texts with tags like [name] [hp:pct]%, a second Health Text, and text tiles you can move to any of nine positions",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "TEXT DISPLAY" },
            },
            {
                -- The Health Bar Fill cog of the Health Bar Texture row on the Frames page (both clients).
                module = "Raid & Party Frames",
                title  = "Textured Background",
                desc   = "Health and power bar backgrounds can use the bar's own texture, tinted by the background color",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "HEALTH BAR", highlight = "Health Bar Texture" },
            },
            {
                -- HEALTH BAR on the Resource Bars display page (both clients).
                module = "Resource Bars",
                title  = "Health Bar Absorb Options",
                desc   = "The health bar's absorbs get the player frame's display options: placement, overshield, the Blizzard Glow Line and a heal absorb backing",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "HEALTH BAR" },
            },
            {
                -- The Resource Text cog in CLASS RESOURCE BAR on the Resource Bars display page (both clients).
                module = "Resource Bars",
                title  = "Hide Class Resource Text at Zero",
                desc   = "The class resource text can hide while the resource is empty, and its size now goes up to 64",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "CLASS RESOURCE BAR", highlight = "Resource Text" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Rotation spells placed on the bars as macros now show cooldown reductions as quickly as plain spell buttons." },
            { module = "Action Bars", text = "The bars now show the dark red loss of control overlay while you are stunned, polymorphed or locked out by an interrupt, in arenas and battlegrounds too, as soon as it starts." },
            { module = "AuraBuff Reminders", text = "Rogue Poisons, Paladin Rites and Shaman Imbues & Shields no longer change each other's Where to Show and Reminder Sound, Pets has its own Where to Show, and poison reminders now play the Rogue Poisons sound." },
            { module = "AuraBuff Reminders", text = "The Blistering Scales reminder no longer comes back after the first pull of a Mythic+ key while the Scales are still up." },
            { module = "Bags", text = "The warbank deposit and withdraw window takes gold, silver and copper, and the bank footer shows silver and copper too." },
            { module = "Bags", text = "The categories in the bank's sidebar can be reordered by dragging, as in the bags sidebar." },
            { module = "Blizzard Skins+", text = "The Character Sheet's player model no longer opens off screen." },
            { module = "Blizzard Skins+", text = "A ready check that starts during combat no longer causes a blocked-action error from the skinned ready check window." },
            { module = "Chat", text = "With Idle Fade on, a chat hidden by a visibility rule such as Hide in Combat now counts as idle: it comes back faded and wakes on hover, which did not work at full fade strength before." },
            { module = "Cooldown Manager", text = "Grouped Tracking Bars no longer overlap after a bar in the group is width or height matched to another element." },
            { module = "Cooldown Manager", text = "The focus cast sound no longer plays for a friendly or self focus." },
            { module = "Damage Meters", text = "Hide in Delves no longer hides meter windows or Spell History inside Lairs such as the Tidebound Grotto." },
            { module = "Damage Meters", text = "Meter rows fit the window again after switching to a profile with a different window width, instead of keeping the old width until a reload." },
            { module = "Data Bars", text = "Switching profiles no longer leaves a frozen copy of a block, such as a second clock, on a data bar." },
            { module = "Data Bars", text = "The item level block's Band color matches this season's upgrade tracks again, instead of last season's item levels." },
            { module = "General", text = "Aura and cooldown timers now round like Blizzard's buff timers, so a fresh 1-hour flask reads 60m instead of 59m, and Precise Below reaches 90 minutes." },
            { module = "Mythic+ Tools", text = "Kick Tracker bars now grow from the edge you placed them at, instead of shifting half a row for each member more or fewer than the Unlock Mode preview." },
            { module = "Mythic+ Tools", text = "The Mythic+ Timer and Run Summary previews show a current-season dungeon and this season's item levels." },
            { module = "Nameplates", text = "A tank without or losing aggro and a damage dealer with or near aggro now see the threat color over debuff coloring, on the border and name too when Threat Colors paints them." },
            { module = "Nameplates", text = "Target of Target text now keeps up when an enemy changes target, instead of sometimes showing its last target." },
            { module = "Party Mode", text = "Bouncing Logo When AFK no longer causes a Lua error when you reload or go AFK in a Mythic+ key or a raid encounter." },
            { module = "Quality of Life", text = "The upgrade calculator reads this season's crafted gear correctly (its quality tier and Hero or Myth band), instead of last season's item levels." },
            { module = "Quest Tracker", text = "Auto Turn In no longer opens a completed quest from an NPC's list while Hold Shift to Skip is on and Shift is held." },
            { module = "Raid & Party Frames", text = "Pet frames no longer get pushed off the screen in arenas while the Friendly Boss group is on." },
            { module = "Raid & Party Frames", text = "Extra, Pet and Friendly Boss frames placed with Free Move no longer have blurry borders." },
            { module = "Resource Bars", text = "Evoker Essence and Destruction Soul Shards now fill vertically while recharging when the Class Resource is set to Vertical Up or Vertical Down." },
            { module = "Unit Frames", text = "With Absorb Placement on Overlay, the player frame's absorb shield now shows above a dispel overlay instead of being hidden under it." },
            { module = "Unit Frames", text = "Hide Exhaustion in the debuff filters can be turned off again, so Sated, Exhaustion and the other Bloodlust lockouts can show on the frames." },
            { module = "Unit Frames & Resource Bars", text = "Restoration druids now have the Power Type option, so their power bars can keep Mana in every form." },
            { module = "Localization", text = "Brazilian Portuguese, German, Korean and Traditional Chinese translations updated." },
        },
        thanks = true,
    },
    {
        version = "9.6.9",
        heroes = {
            {
                -- The Custom entry of the text dropdowns on the Main Frames page (the health texts in
                -- CORE TEXT POSITIONS, the text bar's slots, Power Text), edited in a popup with a
                -- live preview and tag suggestions (both clients). Opens on the player frame.
                module = "Unit Frames",
                title  = "Custom Text",
                desc   = "Health texts, the text bar and power text can now show your own mix of tags and text, like [name] - [hp:pct]%. Pick Custom in a text slot to write one, with a live preview and tag suggestions as you type.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "CORE TEXT POSITIONS",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                -- Party Mode's second tab (both clients): one reading per character per daily reset.
                module = "Party Mode",
                title  = "Should I Raid Tonight?",
                desc   = "Give your character a birthday and ask the stars: tonight's real Moon decides whether you raid, from Send It to Log Off. Each character gets one reading a day, in Party Mode's new tab.",
                nav    = { module = "EllesmereUIPartyMode", page = "Should I Raid Tonight?" },
            },
        },
        features = {
            {
                -- The Applied / Missing pick on each Debuff Coloring row (both clients).
                module = "Nameplates",
                title  = "Missing Debuff Colors",
                desc   = "Debuff Coloring can also color an enemy fighting you or your group while your debuff is missing from it",
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "DEBUFF BASED NAMEPLATE COLORING", highlight = "Debuff Coloring" },
            },
            {
                -- Party Mode's AFK tab (both clients).
                module = "Party Mode",
                title  = "AFK Screen",
                desc   = "While you're AFK, the screen dims and the EllesmereUI logo bounces around it, with optional spins and party lights when it hits a corner",
                nav    = { module = "EllesmereUIPartyMode", page = "AFK",
                           section = "AFK SCREEN", highlight = "Bouncing Logo When AFK" },
            },
            {
                -- Drag a bar's row in the Currently Editing menu of the Tracking Bars page (both clients).
                module = "Cooldown Manager",
                title  = "Reorder Tracking Bars",
                desc   = "Drag a Tracking Bar within its group in the Currently Editing menu to change its place",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
            {
                -- The TOOLTIPS section of the Upgrader tab (retail only: the tab is not offered on WoW Forever).
                module = "Quality of Life",
                title  = "Enhanced Upgrade Tooltips",
                desc   = "Gear tooltips can show the upgrade rank, track and item-level range, the Ascendant ceiling where it applies, and the crest still needed",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIQoL", page = "Upgrader",
                           section = "TOOLTIPS", highlight = "Enhanced Upgrade Tooltips" } or nil,
            },
            {
                -- Gathering Tracking (with its cog) and Find Treasure in the WOW FOREVER section (Forever only).
                forever = true,
                module = "AuraBuff Reminders",
                title  = "Gathering Tracking Reminders",
                desc   = "Optional reminders when Find Herbs or Find Minerals is off, and for Dwarves when Find Treasure is off; click one to turn tracking back on",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "WOW FOREVER", highlight = "Gathering Tracking" } or nil,
            },
        },
        fixes = {
            { module = "Action Bars", text = "A spec or conditional Visibility override of Always now shows a bar saved as Never, and the Toggle Action Bar key follows the override." },
            { module = "Action Bars", text = "Paging settings from a spec override or another profile, such as Disable Form Paging, now apply on a spec switch, profile switch or login without a /reload." },
            { module = "AuraBuff Reminders", text = "Searching the talent and zone lists now scrolls them back to the top, and a missing talent now flashes the talent dropdown." },
            { module = "Bags", text = "Items in the bags and the bank respond to the mouse again with Frame Strata set to High." },
            { module = "Bags", text = "Moving items in the warband bank now does less work." },
            { module = "Blizzard Skins+", text = "The spellbook's level line under spells you have not learned yet is now white like the spell names, instead of a dark color that was hard to read." },
            { module = "Cooldown Manager", text = "The options preview no longer shows charge counts on custom spells whose bar icons do not show them." },
            { module = "Cooldown Manager", text = "Equipping a gear set no longer causes a brief stutter." },
            { module = "Cooldown Manager", text = "The Focus Kick bar follows its nameplate again after its settings change, and turning a bar's tooltips off now hides one that is showing." },
            { module = "General", text = "Fonts set to Blizzard Default now stay on the game's own font while Apply to All Game Text is on." },
            { module = "Party Mode", text = "Party Mode you turned on yourself is no longer switched off by an automatic celebration." },
            { module = "Profiles & Presets", text = "A full account import now keeps your other profiles' keybinds, sync groups, color sources and Cooldown Manager spell layouts." },
            { module = "Profiles & Presets", text = "Importing a profile over the one you are using now keeps the imported layout and settings." },
            { module = "Profiles & Presets", text = "A damaged import string no longer freezes the game." },
            { module = "Profiles & Presets", text = "Pasting an old Cooldown Manager layout string says so again instead of calling it invalid." },
            { module = "Profiles & Presets", text = "Profile sync now removes things you delete, like a Cooldown Manager bar, from your synced profiles, and spec override values no longer spread into them." },
            { module = "Quality of Life", text = "The Upgrade Calculator now uses Season 2 item levels and Ascendant caps." },
            { module = "Raid & Party Frames", text = "The real frames no longer pop back over the raid preview while it is open." },
            { module = "Spec Overrides", text = "Overrides for a module you have turned off are now kept." },
            { module = "Spec Overrides", text = "Conditional overrides now keep each group's values apart when a spec change ends an edit, and an error during a switch no longer blocks later switches until a reload." },
            { module = "Spec Overrides", text = "Logging out while editing an override group no longer leaves that group's values in your profile's own settings." },
            { module = "Unit Frames", text = "Turning Dark Mode off with the options open now repaints the player bar at once, and frame texts now follow a new profile right after a switch or import." },
            { module = "Unlock Mode", text = "A layout change while Unlock Mode is paused for combat now closes it, so its changes are never saved onto the wrong layout." },
            { module = "Localization", text = "Brazilian Portuguese, German, Korean and Traditional Chinese translations updated for the latest options." },
        },
        thanks = true,
    },
    {
        version = "9.6.8",
        mini = true,
        features = {
            {
                -- The Mail card of Window Skins (retail only: its ALT LIST section is not built on WoW Forever).
                module = "Blizzard Skins+",
                title  = "Mail Alt List",
                desc   = "Turn on Show Alt List in the Mail card to list your alts beside Send Mail: click one to address the mail, right-click to ignore it",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins",
                           section = "ALT LIST", highlight = "Show Alt List" } or nil,
            },
        },
        fixes = {
            { module = "AuraBuff Reminders", text = "Reminders no longer look up your map on every refresh, which steers clear of a game bug in Murder Row." },
            { module = "Cooldown Manager", text = "Proc glows work as they did before 9.6.7 again: buff icons no longer light up with proc glows the Buff Glow setting could not turn off, and a proc no longer replaces the Active State Glow." },
            { module = "Mythic+ Tools", text = "Other Mythic+ timer addons no longer trigger the incompatible addon warning while EllesmereUI's own Mythic+ Timer is turned off, and the warning now says how to turn it off." },
            { module = "Profiles & Presets", text = "The Window Skins part of an imported profile string now applies only the Window Skins settings it carries." },
            { module = "Localization", text = "Brazilian Portuguese, German, Korean and Traditional Chinese translations updated for the latest options, and a non-English game client now loads only its own language's translations at login instead of all ten, so EUI Options Language there greys out the ones it no longer loads." },
        },
    },
    {
        version = "9.6.7",
        mini = true,
        features = {
            {
                -- The Tracked Weapons and Attack State Colors cogs of the Swing Timer page's DISPLAY section (Forever only).
                forever = true,
                module = "Resource Bars",
                title  = "Swing Timer Rows and Queued Colors",
                desc   = "Rows can stay up without a weapon, a shield can take the Off Hand row, and each queued attack gets its own color and can keep to the Main Hand row",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Swing Timer",
                           section = "DISPLAY", highlight = "Tracked Weapons" } or nil,
            },
        },
        fixes = {
            { module = "Action Bars", text = "Action Bar 1 now switches to the temporary bar when you are turned into a creature (such as the WoW Forever zombie event), as Blizzard's own bar does." },
            { module = "Bags", text = "With Nest by Expansion, the Midnight header now shows the expansion's name in your game's language." },
            { module = "Cooldown Manager", text = "Proc glows no longer disappear while an ability's icon shows its buff or debuff, and a proc glow now shows over the Active State Glow." },
            { module = "Localization", text = "Brazilian Portuguese, Korean, Simplified Chinese, Spanish (Spain) and Traditional Chinese translations updated for the latest options, including the Arcane Soul countdown in Traditional Chinese." },
        },
    },
    {
        version = "9.6.6",
        heroes = {
            {
                -- A new Mythic+ Tools tab (retail only: the module does not load on WoW Forever).
                -- Opens that tab on its Enable Kick Tracker toggle.
                module = "Mythic+ Tools",
                title  = "Kick Tracker",
                desc   = "Tracks your group's interrupts, even inside a key: a bar per member with their kick's cooldown, read from their spec and talents, and each kicker's icon on the enemy they kicked last. It is off until you turn it on in the Kick Tracker tab of Mythic+ Tools.",
                -- Website only: the patch notes page lifts a hero with a feature
                -- spotlight page out of its Main Features list into a wide card
                -- linking there (the site's build-patch-notes.js carries it; the
                -- game ignores it).
                spotlight = { url = "/spotlight-kick-tracker", art = "media/spotlight/nameplate1.png" },
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIMythicTimer", page = "Kick Tracker",
                           section = "KICK TRACKER", highlight = "Enable Kick Tracker" } or nil,
            },
            {
                -- The Core Positions dropdowns of the Display page (both clients): any elements
                -- in one slot, in the order they are dragged into, Element Spacing in the slot's cog.
                module = "Nameplates",
                title  = "Shared Core Positions",
                desc   = "Any elements can now share a Core Positions slot on your nameplates, side by side in the order you drag them into, such as the raid marker next to the crowd control icons. Each slot's cog gains an Element Spacing row, and existing setups look exactly as before.",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "CORE POSITIONS", highlight = "Top" },
            },
            {
                -- Unlock Mode point-to-point anchors (PR #2813), behind the Point Anchor Handles toggle.
                module = "General",
                title  = "Point Anchors",
                desc   = "Unlock Mode can now anchor any point of an element to any point of another, a corner to a corner or an edge to an edge, and the two stay lined up when either resizes. Turn on Point Anchoring in Global Settings > General, then Anchor an element and pick its point and the target's.",
                nav    = { module = "_EUIGlobal", page = "General",
                           section = "UNLOCK MODE", highlight = "Point Anchoring" },
            },
            {
                -- The Overlap Cycling dropdown of the UNLOCK MODE section (PR #2845), on from the
                -- start with the plain wheel (owner ruling 2026-10-23).
                module = "Unlock Mode",
                title  = "Overlap Cycling",
                desc   = "Scroll the wheel over overlapping frames in Unlock Mode to bring the one under your cursor to the front. On from the start with the plain wheel; choose a Shift, Ctrl or Alt modifier, or turn it off, in Global Settings > General.",
                nav    = { module = "_EUIGlobal", page = "General",
                           section = "UNLOCK MODE", highlight = "Overlap Cycling" },
            },
        },
        features = {
            {
                -- The section-title button EllesmereUI.BuildSectionUnlockJump puts on the first
                -- settings section of every movable element (suite-wide, 2026-10-21). Static card:
                -- the button is on every such page, so there is no one place to open.
                module = "General",
                title  = "Move in Unlock Mode",
                desc   = "A Move in Unlock Mode button beside each movable element's first settings section opens Unlock Mode with that element selected and flashed",
            },
            {
                -- Static card: the header previews added this patch, one per page, so there is
                -- no one place to open (the Mythic+ Tools pages are retail only).
                module = "General",
                title  = "Page Previews",
                desc   = "The Kick Tracker, Cast Bars, Target/Focus Bars, GCD Bar, Totem Bar and XP Bar pages now preview their bars and icons at the top",
            },
            {
                -- Beside Enable Group Finder; the window's Group Settings menu entry Show Specialization is the same setting.
                module = "Group Finder",
                title  = "Show Spec Icons",
                desc   = "Turn the spec icons on the group list's filled slots off to keep the game's own class and role icons",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search",
                           section = "GROUP FINDER", highlight = "Show Spec Icons" } or nil,
            },
            {
                -- A row of the cast bar's Fill Color cog, above Uninterruptible Color Override.
                module = "Resource Bars",
                title  = "Channel Color Override",
                desc   = "Channeled spells can fill the cast bar in their own color, set in its Fill Color cog",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar",
                           section = "DISPLAY", highlight = "Fill Color" },
            },
            {
                -- The first row of the cast bar's Show Spell Icon cog; needs an EllesmereUI player portrait.
                module = "Resource Bars",
                title  = "Spell Icon in Player Portrait",
                desc   = "The cast bar's spell icon can show over your player portrait while you cast",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar",
                           section = "LAYOUT", highlight = "Show Spell Icon" },
            },
            {
                -- Rows of the Border Options cog on the power, class resource, cast and GCD bars.
                module = "Resource Bars",
                title  = "Extend Border Left and Right",
                desc   = "The power, class resource, cast and GCD bar borders can reach past the bar's left and right edges, like Extend Top and Bottom",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar",
                           section = "DISPLAY", highlight = "Border Style" },
            },
            {
                -- Rows of the Health and Power bars' Out of Combat Opacity & Visibility cogs (both clients;
                -- the Power rows follow the class: Energy or Focus, and Mana).
                module = "Resource Bars",
                title  = "Show When Missing",
                desc   = "The Health and Power bars can show while your health, energy, focus or mana is below full, even when their Visibility setting hides them",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "HEALTH BAR", highlight = "Opacity" },
            },
            {
                -- Debuff Manager (base and tiles) and Buff Manager icon and square indicators.
                module = "Raid & Party Frames",
                title  = "Aura Border Styles",
                desc   = "Buff and debuff icons can use any border style, an exact border size and border opacity, with optional textured dispel and pandemic rings",
                nav    = { module = "EllesmereUIRaidFrames", page = "Debuff Manager" },
            },
            {
                -- A row in the Attach Important Buffs to Cursor cog (both clients).
                module = "AuraBuff Reminders",
                title  = "Only on Cursor in Combat",
                desc   = "Important buffs can follow your cursor only while you are in combat, and show with your other reminders the rest of the time",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "DISPLAY", highlight = "Attach Important Buffs to Cursor" },
            },
            {
                -- A dropdown on each Talent Reminders row (retail only: the page is not built on WoW Forever).
                module = "AuraBuff Reminders",
                title  = "Not Needed Reminder Choice",
                desc   = "Each talent's 'Not Needed' reminder can show never, in this season's instances (the new default for ones that were on) or in every instance",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIAuraBuffReminders", page = "Talent Reminders",
                           section = "ACTIVE REMINDERS" } or nil,
            },
            {
                -- The zone dropdown on each Talent Reminders row (retail only, as above).
                module = "AuraBuff Reminders",
                title  = "Edit Talent Reminder Zones",
                desc   = "Each talent reminder in the list has its own zone dropdown to change where it reminds you, with Delete Reminder at its top",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIAuraBuffReminders", page = "Talent Reminders",
                           section = "ACTIVE REMINDERS" } or nil,
            },
            {
                -- Picked in each spell's menu on the bars (classes with stance bar pages): page-only.
                module = "Cooldown Manager",
                title  = "Stance Bar Hiding",
                desc   = "A per-spell Stance Bar option hides an icon in or outside Stealth, a form or a stance, so icons can swap with keys that cast something else there",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                -- Static card: a lookup for other addons (PLUGINS_API.md), nothing to open.
                module = "General",
                title  = "Cooldown Manager Icons for Addons",
                desc   = "Other addons can find the Cooldown Manager icons showing a spell, even one Blizzard's Cooldown Manager doesn't track, to highlight the next cast",
            },
            {
                -- Static card: EllesmereUI.RequestCDMRepopulate (PLUGINS_API.md), nothing to open.
                module = "General",
                title  = "Cooldown Manager Repopulate for Addons",
                desc   = "Profile installers that write Blizzard Cooldown Manager layouts can have the Cooldown Manager rebuild its bars from them after their reload",
            },
            {
                -- Cogs on Bar Border Style (Separators), Icon Style (Zoom, Separator), Header Bottom
                -- Border and Always Show Player, the value gradient swatch, Background Texture (both clients).
                module = "Damage Meters",
                title  = "Separators and Value Gradient",
                desc   = "Pixels border separators between bars, values colored green to red from the top amount down, background textures, icon zoom and a marker on your bar",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters",
                           section = "BARS", highlight = "Border Style" },
            },
            {
                -- The EXTRAS row beside Quest Item Hotkey, with its Wowhead Link Settings cog (both clients).
                module = "Quest Tracker",
                title  = "Wowhead Quest Links",
                desc   = "Right-click a quest in the quest tracker or quest log for a Wowhead link to copy, optionally in your game's language or opening at the comments",
                nav    = { module = "EllesmereUIQuestTracker", page = "Quest Tracker",
                           section = "EXTRAS", highlight = "Wowhead Quest Links" },
            },
            {
                -- Static card: the box sits on the Unlock Mode top bar, not on a settings page (both clients).
                module = "Unlock Mode",
                title  = "Element Filter",
                desc   = "A box on the Unlock Mode bar shows only the elements whose name contains every word you type, in English or your own language",
            },
            {
                -- The Power Type row's Form Power Bar cog and the Form rows built with Mana + Form Power (Forever druids).
                forever = true,
                module = "Unit Frames",
                title  = "Form Power Bar Settings",
                desc   = "A druid's Mana + Form Power bar has its own offsets and its own text format, position, size and color",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Power Type",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end } or nil,
            },
            {
                -- The Travel page's Border Style row and Border Options cog, Background Texture,
                -- the Separator Settings and Early Exit Border cogs, Show Spark (Forever only).
                forever = true,
                module = "Forever Essentials",
                title  = "Flight Timer Appearance",
                desc   = "Any border style and size, a background texture and color, a Pixels stop separator, a spark at the end of the fill and an early exit button border",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Travel",
                           section = "DISPLAY", highlight = "Border Style" } or nil,
            },
            {
                -- The Loot page's Background Texture and Border Style rows (Border Options cog)
                -- and LAYOUT's Spacing (Forever only).
                forever = true,
                module = "Forever Essentials",
                title  = "Loot Feed Appearance",
                desc   = "Any border style and size, a background texture, adjustable spacing and an optional Pixels separator beside the icon",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Loot",
                           section = "DISPLAY", highlight = "Border Style" } or nil,
            },
            {
                -- Cogs on Icon Style, Header Bottom Border, Custom Player Color and Bar Border Style,
                -- the value gradient swatch and Background Texture (Forever only).
                forever = true,
                module = "Forever Essentials",
                title  = "Threat Meter Appearance",
                desc   = "Icon zoom, Comic class icons, a background texture, Pixels separators, your bar's marker on or off, and values colored green to red as threat climbs",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "Threat",
                           section = "BARS", highlight = "Icon Style" } or nil,
            },
            {
                -- Beside Show Map Markers in the General page's WORLD MAP section (Forever only).
                forever = true,
                module = "Forever Essentials",
                title  = "Show Fishing Skill",
                desc   = "The world map shows the fishing skill a zone needs under its name, colored by your skill: red too low, yellow still loses fish, green loses none",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIForeverEssentials", page = "General",
                           section = "WORLD MAP", highlight = "Show Fishing Skill" } or nil,
            },
        },
        fixes = {
            { module = "AuraBuff Reminders", text = "Talent reminders now remind in zones added to them later, and in the zone of a reminder made with an older version." },
            { module = "AuraBuff Reminders", text = "Attach Important Buffs to Cursor no longer does work as you move your mouse while nothing is on the cursor." },
            { module = "AuraBuff Reminders", text = "Reminders for raid buffs a groupmate provides no longer take left clicks, since you cannot cast them; the click goes through to the game and middle-click still dismisses the reminder." },
            { module = "Blizzard Skins+", text = "Bulk Buy now opens on a shift-click for items a vendor sells one at a time, such as armor and weapons, which used to get no window." },
            { module = "Chat", text = "Copy Chat and chat tabs pulled out of the dock no longer cause a blocked-action error during combat." },
            { module = "Cooldown Manager", text = "Add Custom Spell now refuses spells that are in the spell list, since their settings had no effect when added that way; to fix one added before, remove it and pick it from the list." },
            { module = "Cooldown Manager", text = "The Add Custom Spell popup's messages no longer cover the Show Charges checkbox." },
            { module = "Cooldown Manager", text = "Dragging icons in the bar preview now works up and down on vertical bars, with the insert line across the gap, and the line matches the icons' height with the Cropped shape." },
            { module = "Cooldown Manager", text = "The Add Custom Spell window now warns that Blizzard restrictions can keep custom spells from working fully." },
            { module = "Damage Meters", text = "Scrolling a meter with the mouse wheel now lines the bars up again after reaching the end of the list." },
            { forever = true, module = "Forever Essentials", text = "The threat meter no longer hides its bottom bar when the window is a pixel or two too short for it." },
            { module = "General", text = "Nameplates, Unit Frames and Action Bars do less work while you log in or reload the UI." },
            { module = "General", text = "The interrupt-ready color on cast bars now follows a warlock's real interrupt: Grimoire: Fel Ravager, which only summons, no longer counts as one." },
            { module = "General", text = "The options window no longer opens during combat, as it could from a Data Bars block click or a request made just before the pull, which caused blocked-action errors." },
            { module = "General", text = "The profile keybind window and the conditional overrides condition picker now close with the options window, so they can no longer hold your clicks or keys in combat." },
            { forever = true, module = "General", text = "Characters are now grouped and remembered by ruleset, Normal, PvP, Roleplaying or Hardcore, instead of a realm name, so the gold roster, spec memory, bag currency order and Cooldown Manager bar sizes no longer mix across rulesets." },
            { module = "Mythic+ Tools", text = "Cast Bars, Target/Focus Bars and Run Summary now follow a profile switch right away." },
            { module = "Mythic+ Tools", text = "Cast Bars (formerly Targeted Spell Bars) now show casts from enemies already on screen when you turn them on." },
            { module = "Mythic+ Tools", text = "The Mythic+ Timer tab now starts with an Enable Mythic+ Timer toggle, and its preview is the eye beside it instead of a Show Preview toggle." },
            { module = "Quality of Life", text = "The Movement Alert's Burning Rush text now uses the alert font, outline and text size like the other alerts." },
            { module = "Nameplates", text = "Target arrows no longer make room for icons or auras that a Y offset has moved above or below them." },
            { module = "Nameplates", text = "With the Full Sized spell icon, the target arrows and the auras beside the bar now move out past it during a cast instead of overlapping it." },
            { module = "Raid & Party Frames", text = "Pinging an ability no longer makes the ping marker on raid and party frames grow bigger or show an earlier ping's marker again." },
            { module = "Resource Bars", text = "The Class, Power and Health Bars preview now includes the Arcane Soul helper for Mages, and plays it at its real spot on screen while the page is open." },
            { module = "Unit Frames", text = "Player Aura Bars tooltips no longer vanish when you move from one icon to the next with a negative Spacing or Row Spacing." },
            { module = "Unit Frames", text = "Absorb text on a frame whose absorb bars are turned off now clears when a shield runs out on its own." },
            { module = "Unit Frames", text = "Boss frames now show the right name when the bosses change places mid-fight, such as when a new boss joins." },
            { module = "Unit Frames", text = "Dark Mode now applies to each frame on its own, with a toggle on the Main Frames and Mini Frames pages; Global Settings > Colors still switches every frame." },
            { module = "Unit Frames", text = "The Target of Target and Focus Target frames now change the moment your target or focus switches who it is attacking, instead of up to half a second later." },
            { forever = true, module = "Unit Frames", text = "A druid's Mana + Form Power bar now sits just under the player frame on the WoW Forever, Blizzard Style and Classic WoW UI looks instead of hanging below it." },
            { module = "Unlock Mode", text = "Unlock Mode now comes back after combat even when another fight starts within half a second of the first one ending." },
            { module = "Localization", text = "German, Korean, Traditional Chinese and Brazilian Portuguese translations updated for the latest options, and more tooltip, Damage Meters, minimap friends list and Raid & Party Frames labels now show in your language." },
        },
        thanks = true,
    },
    {
        version = "9.6.1",
        features = {
            {
                -- The New Spell Group slot in the WOW FOREVER section (Forever only).
                forever = true,
                module = "AuraBuff Reminders",
                title  = "Spell Groups",
                desc   = "One reminder for buffs that replace each other, like armors or aspects: it shows while none of the group's spells is active",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "WOW FOREVER", highlight = "New Spell Group" } or nil,
            },
            {
                -- A row of the condition picker; the link opens the Conditional Overrides list.
                module = "General",
                title  = "Party Condition",
                desc   = "Conditional overrides can now apply while you are in a party (a group that is not a raid), inside instances or out",
                nav    = { module = "_EUIProfiles", page = "Overrides",
                           preSelect = function() EllesmereUI._overridesTabMode = "cond" end },
            },
            {
                -- Retail only (the module does not load on WoW Forever). The switch is in the
                -- Premade Groups list's Group Settings menu, so the link lands on the module's page.
                module = "Group Finder",
                title  = "Dungeon Keystone Level",
                desc   = "Each dungeon square in Premade Groups can show your best keystone level this season, colored by its score (Group Settings menu)",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIGroupFinder", page = "Premade Search",
                           section = "GROUP FINDER", highlight = "Enable Group Finder" } or nil,
            },
            {
                -- A row in the Bar Texture and Cast Bar Texture cogs (also on Global Settings > Textures).
                module = "Nameplates",
                title  = "Textured Background",
                desc   = "Enemy nameplate health and cast bar backgrounds can use the bar's own texture, tinted by the background color",
                nav    = { module = "EllesmereUINameplates", page = "Display",
                           section = "STYLE", highlight = "Bar Texture" },
            },
            {
                -- A row in the Filter Quests cog, built while Experimental Quest Tools is on
                -- (the link lands on the TRACKING section until then).
                forever = true,
                module = "Quest Tracker",
                title  = "Quest Filter Button",
                desc   = "An optional button on the Quests header turns Filter Quests on and off",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIQuestTracker", page = "Quest Tracker",
                           section = "TRACKING", highlight = "Filter Quests" } or nil,
            },
            {
                -- Display-only rename of EllesmereUIRaidFrames; its main tab reads Raid.
                module = "Raid & Party Frames",
                title  = "New Name",
                desc   = "Raid Frames is now called Raid & Party Frames, since it covers your party frames too; its main tab is now Raid",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames" },
            },
            {
                -- The OVERRIDES section of the Buff and Debuff Manager sidebars.
                module = "Raid & Party Frames",
                title  = "Override List",
                desc   = "The Buff and Debuff Manager sidebars list the overrides that have their own manager; click one to edit it",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager" },
            },
            {
                -- The last rows of the cast bar's Fill Color cog.
                module = "Resource Bars",
                title  = "Uninterruptible Color Override",
                desc   = "Casts that cannot be interrupted can fill the cast bar in their own color, set in its Fill Color cog",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar",
                           section = "DISPLAY", highlight = "Fill Color" },
            },
            {
                -- Follows the Resource Bars row of Global Settings > Style (Forever only).
                forever = true,
                module = "Resource Bars",
                title  = "Swing Timer Styles",
                desc   = "The swing timer now follows your Resource Bars style, wearing the Blizzard, WoW Forever or Classic WoW UI frame like the other bars",
                nav    = EllesmereUI.IS_FOREVER and { module = "EllesmereUIResourceBars", page = "Swing Timer",
                           section = "DISPLAY" } or nil,
            },
            {
                -- Retail only: a choice of the Power Type row, built for Balance Druids
                -- (WoW Forever has no specs).
                module = "Resource Bars",
                title  = "Balance Mana (Always)",
                desc   = "Balance Druids can keep the Power Bar on Mana in every form, Cat and Bear Form included, a new Power Type choice",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "POWER BAR", highlight = "Power Type" } or nil,
            },
            {
                -- The preview header of the Class, Power and Health Bars page; each
                -- section title carries its bar's eye.
                module = "Resource Bars",
                title  = "Bar Previews",
                desc   = "The Class, Power and Health Bars page now previews your power and health bars too, each with an eye to hide it",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars" },
            },
            {
                -- A row in the Bar Texture cog (also on Mini Frames; the cast bars' is on Global Settings > Textures).
                module = "Unit Frames",
                title  = "Textured Background",
                desc   = "Health, power and cast bar backgrounds can use the bar's own texture, tinted by the background color",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Bar Texture" },
            },
            {
                -- Retail only: a choice of the player's Power Type row, built for Balance
                -- Druids (WoW Forever has no specs).
                module = "Unit Frames",
                title  = "Balance Astral Power",
                desc   = "Balance Druids can show Astral Power on the player power bar in every form except Cat and Bear Form, a new Power Type choice",
                nav    = (not EllesmereUI.IS_FOREVER) and { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "POWER BAR", highlight = "Power Type",
                           preSelect = function() if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end; EllesmereUI._pendingUnitSelect = "player" end } or nil,
            },
        },
        fixes = {
            { module = "Action Bars", text = "Attack, Shoot and Auto Shot buttons flash again while active, and stop flashing and lose their highlight as soon as they stop." },
            { module = "Action Bars", text = "Your pet's Attack button stops flashing as soon as your pet stops attacking." },
            { forever = true, module = "Action Bars", text = "Fixed combat errors that could stop logging out, the game menu and your action bar buttons from working until a reload." },
            { module = "Action Bars", text = "Turning Use Blizzard's Rep Bars back on now asks for a reload, which keeps Blizzard's XP and reputation bars from slowing the game and causing errors in combat." },
            { forever = true, module = "AuraBuff Reminders", text = "Custom spell reminders no longer show for a buff you already have while the game is hiding aura details from addons." },
            { module = "Bags", text = "The bag window stutters less when it opens, updates or you search, and the search now updates once you pause typing." },
            { module = "Blizzard Skins+", text = "The Character Sheet's character model and item level, enchant and upgrade text no longer go missing behind the sheet's background." },
            { module = "Blizzard Skins+", text = "The Equipment Manager's set icon popup now matches the skinned Character Sheet." },
            { module = "Cooldown Manager", text = "Blizzard's swing timers and the other frames stacked above your action bars no longer move up the screen in combat when your cooldowns update." },
            { module = "Damage Meters", text = "After an earlier fight, the meter now keeps filling when a teammate pulls before you or when you zone into a fight your group is already in." },
            { module = "Damage Meters", text = "Spell History now lists the healthstones and potions you use." },
            { module = "General", text = "Removed a brief freeze when combat ends, most noticeable after a boss dies." },
            { module = "General", text = "Cooldown Manager, Nameplates, Resource Bars, Unit Frames and Quality of Life's Movement Alert use less CPU in combat." },
            { module = "Group Finder", text = "The leaver mark on a group member's icon in Premade Groups is no longer hidden under their spec or class icon." },
            { module = "Minimap", text = "Addon buttons in the grouped flyout no longer turn dark after you click them." },
            { module = "Nameplates", text = "Stacking Speed and Top Screen Inset now keep your setting after a game restart." },
            { module = "Nameplates", text = "Health and cast bar background colors now update right away when you switch profiles." },
            { module = "Nameplates", text = "The Honor Portrait faction icon now shows the unit's honor level badge inside it, as Blizzard's frames do." },
            { module = "Quality of Life", text = "Hide Talking Head hides the speaker's 3D portrait again." },
            { module = "Quality of Life", text = "The Movement Alert now plays your chosen sound when a movement spell is ready." },
            { module = "Quality of Life", text = "Changing form no longer makes the Movement Alert announce a spell that is still on cooldown." },
            { module = "Quest Tracker", text = "Quests added to the tracker no longer flash Blizzard's quest icon for a moment while Show Quest Icons is off." },
            { module = "Raid & Party Frames", text = "Click Casting no longer causes a brief freeze when a bound spell swaps, such as Holy Armaments." },
            { module = "Raid & Party Frames", text = "The Buff Manager preview now follows each indicator's Show In setting, showing Raid Only and Party Only indicators only when it previews those frames." },
            { module = "Resource Bars", text = "Hiding the Class Resource bar or its text in Moonkin Form (Enable/Disable per Form) now works." },
            { module = "Unit Frames", text = "A cast bar's pushback now shows its added time in full beside the countdown, and repeated pushbacks add up correctly." },
            { module = "Unit Frames", text = "The faction indicator's Honor Portrait style now shows the unit's honor level badge inside it, as Blizzard's frames do." },
            { module = "Localization", text = "Spanish (Spain), German, Korean, Brazilian Portuguese and Traditional Chinese translations updated for the latest options." },
        },
        -- Closing thank-you; its "contributors" word links to the Legends contributors box.
        thanks = true,
    },
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

        -- Row 4: Accent Colored Settings Elements (account-wide accentCogIcons /
        -- accentPreviewIcons, both off by default: the icons stay white).
        local accentElRow
        accentElRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Accent Colored Settings Elements",
              tooltip="Shows these settings icons in your accent color instead of white.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            EllesmereUI.BlankRowCfg()
        );  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = accentElRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local accDD, accDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                {
                    { key = "cog", label = "Cogwheel Icons", icon = EllesmereUI.COGS_ICON, iconSize = 18,
                      tooltip = "The cog, position and resize icons beside settings." },
                    { key = "preview", label = "Preview Icons", icon = EllesmereUI.EYE_VISIBLE_ICON, iconSize = 18,
                      tooltip = "The eye icons that show or hide a preview." },
                },
                function(k) return EllesmereUI.AccentGlyphsOn(k) end,
                function(k, v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if k == "cog" then
                        EllesmereUIDB.accentCogIcons = v or nil
                    else
                        EllesmereUIDB.accentPreviewIcons = v or nil
                    end
                    -- Every built glyph repaints through the accent registry.
                    EllesmereUI.RefreshAccent()
                end)
            PP.Point(accDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = accDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(accDDRefresh)
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
              values={ disabled="Disabled", scroll="Scroll", shiftscroll="Shift + Scroll",
                  controlscroll="Ctrl + Scroll", altscroll="Alt + Scroll" },
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
                -- Accent Colored Settings Elements back to off
                EllesmereUIDB.accentCogIcons = nil
                EllesmereUIDB.accentPreviewIcons = nil
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
