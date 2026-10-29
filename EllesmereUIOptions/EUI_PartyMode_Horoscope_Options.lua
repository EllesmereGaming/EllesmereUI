if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PartyMode_Horoscope_Options.lua
--  Party Mode > Should I Raid Tonight?: tonight's raid verdict, read from the
--  character's birthday (its Sun sign) and its race's starting zone (its rising
--  sign) against tonight's real Moon: the house it crosses (whole signs from the
--  rising sign), its aspect to the Sun, its phase and the day's ruling planet.
--  Options-only: it runs while the tab is built, refreshed or clicked and nowhere
--  else, so never in combat (the panel closes as combat starts). The star card's
--  twinkle plays only while the card shows.
--  One reading per character per WoW daily reset: the first read saves the period
--  (readAt, the reset that ends it), the card shows that reading until then and the
--  birthday stays locked.
--  Each character's chart: EllesmereUIDB.raidHoroscope[CharKey] = { month, day,
--  readAt }, left out of profile exports (FULL_EXPORT_EXCLUDED).
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if EllesmereUI._BuildRaidHoroscopePage then return end

-- The day of each month from which its second sign runs (Jan 20 Aquarius .. Dec 22 Capricorn)
local SIGN_START = { 20, 19, 21, 20, 21, 21, 23, 23, 23, 23, 22, 22 }
-- Weekday (1 = Sunday) of each sign's ruling planet: Mars, Venus, Mercury, Moon,
-- Sun, Mercury, Venus, Mars, Jupiter, Saturn, Saturn, Jupiter
local SIGN_RULER = { 3, 6, 4, 2, 1, 4, 6, 3, 5, 7, 7, 5 }
-- The night's score by the Moon's house ...
local HOUSE_SCORE = { 0, 1, 0, -1, 1, -1, 0, -2, 1, 2, 2, -2 }
-- ... by the signs from the Sun to the Moon (0 = conjunction, 6 = opposition), with
-- the aspect lines each distance reads ...
local ASPECT_SCORE = { [0] = 1, 0, 1, -1, 2, -1, -2, -1, 2, -1, 1, 0 }
local ASPECT_LINE  = { [0] = 1, 7, 2, 3, 4, 6, 5, 6, 4, 3, 2, 7 }
-- ... and by weekday: Mars (Tuesday) and Jupiter (Thursday) help, Saturn (Saturday) hurts
local DAY_SCORE = { 0, 0, 1, 0, 1, 0, -1 }
-- The lowest score of each verdict from send it down (log off takes the rest):
-- about 10 / 14 / 16 / 20 / 16 / 14 / 10 % of nights
local TIER_CUT = { 6.85, 4.24, 2.12, -0.32, -2.45, -5.03 }
-- Share of the Moon lit, by phase
local MOON_LIT = { 0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25 }

local function SunSign(month, day)
    if day >= SIGN_START[month] then return (month + 9) % 12 + 1 end
    return (month + 8) % 12 + 1
end

-- The Moon's sign (1 = Aries) and phase (1 = new, 5 = full) at epoch t: its mean
-- longitude with the largest correction (within about two degrees), and its age
-- from the new moon of 2000-01-06 18:14 UTC.
local function Moon(t)
    local d = t / 86400 - 10957.5
    local lon = (218.32 + 13.176396 * d + 6.29 * math.sin(math.rad(134.96 + 13.064993 * d))) % 360
    local age = (d - 5.26) % 29.530588853
    return math.floor(lon / 30) + 1, math.floor(age / 29.530588853 * 8 + 0.5) % 8 + 1
end

-- The reading period, one per WoW daily reset: the reset that ends it (rounded to
-- the minute, as the two clocks are read a second apart), the evening whose sky it
-- reads (the first 21:00 after it begins), that evening's day number and weekday
local function Period()
    local secs = C_DateAndTime.GetSecondsUntilDailyReset()
    if secs <= 0 then secs = secs + 86400 end
    local resetAt = math.floor((time() + secs) / 60 + 0.5) * 60
    local start = resetAt - 86400
    local t = date("*t", start)
    local tonight = time({ year = t.year, month = t.month, day = t.day, hour = 21 })
    if tonight < start then
        tonight = time({ year = t.year, month = t.month, day = t.day + 1, hour = 21 })
    end
    return resetAt, tonight, math.floor(tonight / 86400), date("*t", tonight).wday
end

-- 1..n, fixed for a night and a salt: squared twice modulo a prime below 2^26 (every
-- product stays exact in a double), so neighbouring salts pick independently
local PRIME = 67108859
local function Pick(night, salt, n)
    local x = (night * 48271 + salt * 69621 + 1) % PRIME
    x = (x * x + 40503) % PRIME
    x = (x * x + 9973) % PRIME
    return x % n + 1
end

-- The reading's words, translated on first use (the locale is loaded by then)
local T
local function Text()
    if T then return T end
    local function Zone(name, sign) return { name = name, sign = sign } end
    T = {
        signs = {
            EllesmereUI.L("Aries"), EllesmereUI.L("Taurus"), EllesmereUI.L("Gemini"),
            EllesmereUI.L("Cancer"), EllesmereUI.L("Leo"), EllesmereUI.L("Virgo"),
            EllesmereUI.L("Libra"), EllesmereUI.L("Scorpio"), EllesmereUI.L("Sagittarius"),
            EllesmereUI.L("Capricorn"), EllesmereUI.L("Aquarius"), EllesmereUI.L("Pisces"),
        },
        phases = {
            EllesmereUI.L("New Moon"), EllesmereUI.L("Waxing Crescent"), EllesmereUI.L("First Quarter"),
            EllesmereUI.L("Waxing Gibbous"), EllesmereUI.L("Full Moon"), EllesmereUI.L("Waning Gibbous"),
            EllesmereUI.L("Last Quarter"), EllesmereUI.L("Waning Crescent"),
        },
        -- By house, the lines a night picks among
        houses = {
            { EllesmereUI.L("your house of Self: all eyes are on you tonight."),
              EllesmereUI.L("your house of Self: trust your own calls tonight."),
              EllesmereUI.L("your house of Self: tonight your parse is the main character."),
              EllesmereUI.L("your house of Self: play your own game and let it show.") },
            { EllesmereUI.L("your house of Loot: something drops with your name on it."),
              EllesmereUI.L("your house of Loot: the vault is watching you."),
              EllesmereUI.L("your house of Loot: tonight's tier token knows your name."),
              EllesmereUI.L("your house of Loot: bring bag space, just in case.") },
            { EllesmereUI.L("your house of Comms: speak up, your callouts will land."),
              EllesmereUI.L("your house of Comms: someone finally reads the strat."),
              EllesmereUI.L("your house of Comms: mind what you type in raid chat."),
              EllesmereUI.L("your house of Comms: the clearest voice on comms is yours.") },
            { EllesmereUI.L("your house of Home: the couch is calling."),
              EllesmereUI.L("your house of Home: a cozy night in looks tempting."),
              EllesmereUI.L("your house of Home: there is decorating to be done."),
              EllesmereUI.L("your house of Home: your hearthstone feels heavy.") },
            { EllesmereUI.L("your house of Fun: a pug could surprise you."),
              EllesmereUI.L("your house of Fun: tonight's wipes will be funny ones."),
              EllesmereUI.L("your house of Fun: someone pulls off something legendary."),
              EllesmereUI.L("your house of Fun: the best stories start with a bad pull.") },
            { EllesmereUI.L("your house of Chores: it smells like a farm night."),
              EllesmereUI.L("your house of Chores: your bags need sorting first."),
              EllesmereUI.L("your house of Chores: the repair bill adds up."),
              EllesmereUI.L("your house of Chores: restock before you queue.") },
            { EllesmereUI.L("your house of Partners: stay close to your healer."),
              EllesmereUI.L("your house of Partners: the tank needs a friend tonight."),
              EllesmereUI.L("your house of Partners: your duo partner carries you."),
              EllesmereUI.L("your house of Partners: a well-timed external saves the night.") },
            { EllesmereUI.L("your house of Endings: wipes are coming, and so is growth."),
              EllesmereUI.L("your house of Endings: something dies tonight, maybe the boss."),
              EllesmereUI.L("your house of Endings: expect a lot of running back."),
              EllesmereUI.L("your house of Endings: one boss's story ends tonight.") },
            { EllesmereUI.L("your house of Adventure: try the boss you keep skipping."),
              EllesmereUI.L("your house of Adventure: a new strat wants a try."),
              EllesmereUI.L("your house of Adventure: the next difficulty is calling."),
              EllesmereUI.L("your house of Adventure: an alt deserves a raid night.") },
            { EllesmereUI.L("your house of Glory: a progress kill is written in the stars."),
              EllesmereUI.L("your house of Glory: tonight's kill screenshot gets framed."),
              EllesmereUI.L("your house of Glory: your name tops the meters."),
              EllesmereUI.L("your house of Glory: the guild talks about this pull for weeks.") },
            { EllesmereUI.L("your house of the Guild: everyone shows up on time."),
              EllesmereUI.L("your house of the Guild: the roster fills itself."),
              EllesmereUI.L("your house of the Guild: someone brings a feast for all."),
              EllesmereUI.L("your house of the Guild: guild chat is in a good mood.") },
            { EllesmereUI.L("your house of Shadows: someone stands in the fire, maybe you."),
              EllesmereUI.L("your house of Shadows: a mechanic is hiding from you."),
              EllesmereUI.L("your house of Shadows: beware what lurks behind the boss."),
              EllesmereUI.L("your house of Shadows: a disconnect lurks in the dark.") },
        },
        aspects = {
            { EllesmereUI.L("The Moon meets your Sun: you and the raid want the same thing."),
              EllesmereUI.L("The Moon meets your Sun: your instincts are dialed in."),
              EllesmereUI.L("The Moon meets your Sun: you set the raid's tempo."),
              EllesmereUI.L("The Moon meets your Sun: your heart and your hands agree.") },
            { EllesmereUI.L("The Moon sextiles your Sun: small chances, take them."),
              EllesmereUI.L("The Moon sextiles your Sun: a lucky crit is on its way."),
              EllesmereUI.L("The Moon sextiles your Sun: friendly faces in the group."),
              EllesmereUI.L("The Moon sextiles your Sun: a small favor comes back to you.") },
            { EllesmereUI.L("The Moon squares your Sun: friction with the raid leader."),
              EllesmereUI.L("The Moon squares your Sun: a mechanic tests your patience."),
              EllesmereUI.L("The Moon squares your Sun: your keybinds feel cursed."),
              EllesmereUI.L("The Moon squares your Sun: count to ten before you type.") },
            { EllesmereUI.L("The Moon trines your Sun: cooldowns line up."),
              EllesmereUI.L("The Moon trines your Sun: every proc arrives on time."),
              EllesmereUI.L("The Moon trines your Sun: your rotation flows like water."),
              EllesmereUI.L("The Moon trines your Sun: the healers adore you tonight.") },
            { EllesmereUI.L("The Moon opposes your Sun: the raid pulls one way, you pull the other."),
              EllesmereUI.L("The Moon opposes your Sun: you and the boss want the same spot."),
              EllesmereUI.L("The Moon opposes your Sun: someone steals your soak."),
              EllesmereUI.L("The Moon opposes your Sun: meet the raid halfway.") },
            { EllesmereUI.L("The Moon is quincunx your Sun: something feels off, check your talents."),
              EllesmereUI.L("The Moon is quincunx your Sun: check your gear before the pull."),
              EllesmereUI.L("The Moon is quincunx your Sun: your addons need updating."),
              EllesmereUI.L("The Moon is quincunx your Sun: a small fix makes a big difference.") },
            { EllesmereUI.L("No major aspect tonight: the stars leave it to you."),
              EllesmereUI.L("No major aspect tonight: the sky keeps quiet."),
              EllesmereUI.L("No major aspect tonight: write your own legend."),
              EllesmereUI.L("No major aspect tonight: your choices are your own.") },
        },
        days = {
            { EllesmereUI.L("Sunday belongs to the Sun: a night for personal glory."),
              EllesmereUI.L("Sunday belongs to the Sun: shine, but share the spotlight."),
              EllesmereUI.L("Sunday belongs to the Sun: your parse wants to glow orange."),
              EllesmereUI.L("Sunday belongs to the Sun: warmth and confidence carry you.") },
            { EllesmereUI.L("Monday belongs to the Moon: moods run high."),
              EllesmereUI.L("Monday belongs to the Moon: trust your gut on the pull."),
              EllesmereUI.L("Monday belongs to the Moon: tempers rise and fall like tides."),
              EllesmereUI.L("Monday belongs to the Moon: start the week gently.") },
            { EllesmereUI.L("Tuesday belongs to Mars: there is blood in the water."),
              EllesmereUI.L("Tuesday belongs to Mars: fresh lockouts, fresh courage."),
              EllesmereUI.L("Tuesday belongs to Mars: pull hard, pull fast."),
              EllesmereUI.L("Tuesday belongs to Mars: fortune favors the bold pull.") },
            { EllesmereUI.L("Wednesday belongs to Mercury: the raid leader's words carry."),
              EllesmereUI.L("Wednesday belongs to Mercury: read the dungeon journal."),
              EllesmereUI.L("Wednesday belongs to Mercury: quick hands win the night."),
              EllesmereUI.L("Wednesday belongs to Mercury: clear callouts, clean kills.") },
            { EllesmereUI.L("Thursday belongs to Jupiter: loot luck is real."),
              EllesmereUI.L("Thursday belongs to Jupiter: think big, pull bigger."),
              EllesmereUI.L("Thursday belongs to Jupiter: share your feast, it pays off."),
              EllesmereUI.L("Thursday belongs to Jupiter: generous rolls come back twice.") },
            { EllesmereUI.L("Friday belongs to Venus: the guild gets along."),
              EllesmereUI.L("Friday belongs to Venus: transmog runs are blessed."),
              EllesmereUI.L("Friday belongs to Venus: kind words in voice chat go far."),
              EllesmereUI.L("Friday belongs to Venus: dress for the kill screenshot.") },
            { EllesmereUI.L("Saturday belongs to Saturn: expect a lesson."),
              EllesmereUI.L("Saturday belongs to Saturn: patience beats panic."),
              EllesmereUI.L("Saturday belongs to Saturn: the hard way is the only way."),
              EllesmereUI.L("Saturday belongs to Saturn: discipline turns wipes into kills.") },
        },
        -- Added to the day's line when tonight's planet rules the character's sign
        ruled = {
            EllesmereUI.L("It rules your sign."), EllesmereUI.L("Home turf for your sign."),
            EllesmereUI.L("Your ruler runs the night."), EllesmereUI.L("Your sign has the edge."),
        },
        -- { headline, then the lines a night picks among }, from send it to log off
        verdicts = {
            { EllesmereUI.L("SEND IT"),
              EllesmereUI.L("Pull the boss. The stars already did the strat."),
              EllesmereUI.L("Every cooldown lines up tonight. Bring them all."),
              EllesmereUI.L("The stars rolled Need for you."),
              EllesmereUI.L("Tonight's kill is already in the logs. Go collect it."),
              EllesmereUI.L("Even the trash wants to drop loot for you.") },
            { EllesmereUI.L("RAID TONIGHT"),
              EllesmereUI.L("Sign up early and bring your best flask."),
              EllesmereUI.L("The raid needs you, and the stars agree."),
              EllesmereUI.L("Show up on time. The night is on your side."),
              EllesmereUI.L("Your rotation will feel like a dance."),
              EllesmereUI.L("A good night to push one more boss.") },
            { EllesmereUI.L("PROBABLY RAID"),
              EllesmereUI.L("Go, but keep your repair bill in mind."),
              EllesmereUI.L("Show up. The stars are mostly on your side."),
              EllesmereUI.L("Worth it, if you remember your consumables."),
              EllesmereUI.L("Raid, but keep one eye on the floor."),
              EllesmereUI.L("Go for a few pulls and see how it feels.") },
            { EllesmereUI.L("YOUR CALL"),
              EllesmereUI.L("The stars shrug. Check who else signed up."),
              EllesmereUI.L("Flip a coin, then raid anyway."),
              EllesmereUI.L("The sky is split. Let the roster decide."),
              EllesmereUI.L("Nothing up there says yes or no. Ask your guild."),
              EllesmereUI.L("Half the stars say go. The other half say snacks.") },
            { EllesmereUI.L("MAYBE SKIP IT"),
              EllesmereUI.L("If you go, stand nowhere near anything glowing."),
              EllesmereUI.L("A quiet night of transmog would be wise."),
              EllesmereUI.L("The stars suggest dailies, not progress."),
              EllesmereUI.L("Go only if they really need your buff."),
              EllesmereUI.L("Maybe sit the first hour out.") },
            { EllesmereUI.L("SIT IT OUT"),
              EllesmereUI.L("The bench has never looked comfier."),
              EllesmereUI.L("Let someone else take the wipes tonight."),
              EllesmereUI.L("The stars booked you a night of fishing."),
              EllesmereUI.L("Tonight's mechanics have your name on them."),
              EllesmereUI.L("Your alts miss you. Spend the night with them.") },
            { EllesmereUI.L("LOG OFF"),
              EllesmereUI.L("The stars say no. Touch grass."),
              EllesmereUI.L("Tonight belongs to your bench."),
              EllesmereUI.L("Even your pet would rather stay home."),
              EllesmereUI.L("The boss has read your horoscope too."),
              EllesmereUI.L("Close the game. The stars insist.") },
        },
        lucky = {
            EllesmereUI.L("A fresh flask"), EllesmereUI.L("Your second trinket"),
            EllesmereUI.L("The healer's whisper"), EllesmereUI.L("The second pull"),
            EllesmereUI.L("A full repair"), EllesmereUI.L("A well-timed battle rez"),
            EllesmereUI.L("A hearty feast"), EllesmereUI.L("The left side of the room"),
            EllesmereUI.L("Your oldest transmog"), EllesmereUI.L("The tank's pull timer"),
            EllesmereUI.L("The raid leader's good mood"), EllesmereUI.L("Your favorite keybind"),
            EllesmereUI.L("A soulstone you didn't ask for"), EllesmereUI.L("An early Bloodlust"),
            EllesmereUI.L("A crit at the right moment"), EllesmereUI.L("The off-tank's patience"),
            EllesmereUI.L("A quiet voice chat"), EllesmereUI.L("The last potion in your bags"),
            EllesmereUI.L("A freshly sorted bag"), EllesmereUI.L("The number seven"),
        },
        avoid = {
            EllesmereUI.L("Standing in fire"), EllesmereUI.L("The first pull"),
            EllesmereUI.L("Loot drama"), EllesmereUI.L("Late pulls"),
            EllesmereUI.L("Going AFK in the portal"), EllesmereUI.L("Pulling with your pet"),
            EllesmereUI.L("The boss's frontal"), EllesmereUI.L("The wrong side of the room"),
            EllesmereUI.L("Pulling before the timer"), EllesmereUI.L("Untested keybinds"),
            EllesmereUI.L("The trash pack nobody marked"), EllesmereUI.L("Forgetting your food buff"),
            EllesmereUI.L("The boss's enrage timer"), EllesmereUI.L("Outranging your healer"),
            EllesmereUI.L("One last pull"), EllesmereUI.L("Arguing with the loot council"),
            EllesmereUI.L("Running out of potions"), EllesmereUI.L("The dragon's tail"),
            EllesmereUI.L("Releasing too early"), EllesmereUI.L("Reading the meters mid-fight"),
        },
        -- The card's corners
        sunLabel = EllesmereUI.L("SUN SIGN"),
        riseLabel = EllesmereUI.L("RISING SIGN"),
        luckyLabel = EllesmereUI.L("LUCKY"),
        avoidLabel = EllesmereUI.L("AVOID"),
        -- Birth zone and rising sign by race (UnitRace's race file)
        zones = {
            Human              = Zone(EllesmereUI.L("Elwynn Forest"), 6),
            Dwarf              = Zone(EllesmereUI.L("Dun Morogh"), 10),
            Gnome              = Zone(EllesmereUI.L("Dun Morogh"), 10),
            NightElf           = Zone(EllesmereUI.L("Teldrassil"), 12),
            Draenei            = Zone(EllesmereUI.L("Azuremyst Isle"), 11),
            Worgen             = Zone(EllesmereUI.L("Gilneas"), 4),
            Pandaren           = Zone(EllesmereUI.L("The Wandering Isle"), 7),
            Orc                = Zone(EllesmereUI.L("Durotar"), 1),
            Troll              = Zone(EllesmereUI.L("Echo Isles"), 9),
            Tauren             = Zone(EllesmereUI.L("Mulgore"), 2),
            Scourge            = Zone(EllesmereUI.L("Tirisfal Glades"), 8),
            BloodElf           = Zone(EllesmereUI.L("Eversong Woods"), 5),
            Goblin             = Zone(EllesmereUI.L("Kezan"), 3),
            Dracthyr           = Zone(EllesmereUI.L("The Forbidden Reach"), 5),
            EarthenDwarf       = Zone(EllesmereUI.L("Isle of Dorn"), 2),
            Harronir           = Zone(EllesmereUI.L("Harandar"), 12),
            VoidElf            = Zone(EllesmereUI.L("Telogrus Rift"), 11),
            LightforgedDraenei = Zone(EllesmereUI.L("The Vindicaar"), 5),
            DarkIronDwarf      = Zone(EllesmereUI.L("Shadowforge City"), 1),
            KulTiran           = Zone(EllesmereUI.L("Boralus"), 4),
            Mechagnome         = Zone(EllesmereUI.L("Mechagon"), 6),
            Nightborne         = Zone(EllesmereUI.L("Suramar"), 12),
            HighmountainTauren = Zone(EllesmereUI.L("Highmountain"), 2),
            MagharOrc          = Zone(EllesmereUI.L("Nagrand"), 9),
            ZandalariTroll     = Zone(EllesmereUI.L("Zuldazar"), 10),
            Vulpera            = Zone(EllesmereUI.L("Vol'dun"), 3),
        },
        fallbackZone = Zone(EllesmereUI.L("Exile's Reach"), 1),
        sealed = EllesmereUI.L("THE STARS ARE WAITING"),
        needBirthday = EllesmereUI.L("Set your character's birthday first, then ask the stars."),
        footer = EllesmereUI.L("One reading per character each day, renewed at the daily reset. For entertainment only: the stars have never parsed."),
    }
    return T
end

-- This character's birth zone and its localized race name
local function BirthZone()
    local T = Text()
    local raceName, raceFile = UnitRace("player")
    return (raceFile and T.zones[raceFile]) or T.fallbackZone, raceName
end

-- This character's chart; create = make it (setters only, never a getter)
local function Chart(create)
    local db = EllesmereUIDB
    if not db then return nil end
    local all = db.raidHoroscope
    if not all then
        if not create then return nil end
        all = {}
        db.raidHoroscope = all
    end
    local key = EllesmereUI.CharKey("-", all)
    if not key then return nil end
    local c = all[key]
    if not c and create then
        c = {}
        all[key] = c
    end
    return c
end

-- Tonight's reading, or nil while the chart has no birthday: one table, filled again
-- on every read (tier 1 = send it .. 7 = log off, the sky's three lines, the
-- verdict's own line, lucky and avoid, the Sun and rising signs, the Moon's phase)
local R = {}
local function Reading(c)
    if not (c and c.month and c.day) then return nil end
    local T = Text()
    local zone = BirthZone()
    local _, tonight, night, wday = Period()
    local sun, rise = SunSign(c.month, c.day), zone.sign
    local moon, phase = Moon(tonight)
    local house, dist = (moon - rise) % 12 + 1, (moon - sun) % 12
    local ruled = SIGN_RULER[sun] == wday
    -- Each pick draws from its own stream of the birthday and the birth zone, so two
    -- characters under one sky read different lines
    local salt = ((c.month * 32 + c.day) * 13 + rise) * 8
    -- The sky counts double against a die of -3.5..3.5 (in thousandths)
    local score = 2 * (HOUSE_SCORE[house] + ASPECT_SCORE[dist] + DAY_SCORE[wday]
        + (phase == 5 and 1 or phase == 1 and -1 or 0) + (ruled and 1 or 0))
        + (Pick(night, salt, 7000) - 3500.5) / 1000
    local tier = 7
    for i = 1, 6 do
        if score >= TIER_CUT[i] then
            tier = i
            break
        end
    end
    local v = T.verdicts[tier]
    local houses, aspects, days = T.houses[house], T.aspects[ASPECT_LINE[dist]], T.days[wday]
    local day = days[Pick(night, salt + 3, #days)]
    if ruled then day = day .. " " .. T.ruled[Pick(night, salt + 4, #T.ruled)] end
    R.tier, R.headline, R.phase = tier, v[1], phase
    R.sky = EllesmereUI.Lf("The %1$s is in %2$s, %3$s", T.phases[phase], T.signs[moon],
        houses[Pick(night, salt + 1, #houses)]) .. "\n" .. aspects[Pick(night, salt + 2, #aspects)] .. "\n" .. day
    R.verdict = v[Pick(night, salt + 5, #v - 1) + 1]
    R.lucky = T.lucky[Pick(night, salt + 6, #T.lucky)]
    R.avoid = T.avoid[Pick(night, salt + 7, #T.avoid)]
    R.sun, R.rise = T.signs[sun], T.signs[rise]
    return R
end

-- The star card: x as a share of the card's width from its centre, y down from its
-- top, size (clear of the corners' captions)
local STARS = {
    { -0.24, 20, 2 }, { -0.35, 66, 3 }, { -0.15, 38, 2 }, { -0.44, 102, 2 }, { -0.30, 134, 3 },
    { -0.11, 112, 2 }, { -0.21, 148, 2 }, { 0.17, 26, 2 }, { 0.24, 14, 2 }, { 0.27, 74, 3 },
    { 0.43, 90, 2 }, { 0.38, 128, 3 }, { 0.12, 118, 2 }, { 0.29, 150, 2 },
}
local CIRCLE = "Interface\\Common\\CommonMaskCircle"
-- Card height; the Moon's size and centre, the verdict's top and the sky lines'
-- top, each down from the card's top; the corners' inset
local CARD_H, MOON, MOON_Y, HEAD_Y, BODY_Y, INSET = 380, 40, 70, 160, 212, 16
local FILL_R, FILL_G, FILL_B = 0.06, 0.06, 0.07

function EllesmereUI._BuildRaidHoroscopePage(parent, yOffset)
    -- Frames on the kept page go through the options frame pool
    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local T = Text()
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    local Paint  -- assigned with the card

    local function Set(field, v)
        local c = Chart(true)
        if c then c[field] = v end
        EllesmereUI:RefreshPage()
    end

    local months = CALENDAR_FULLDATE_MONTH_NAMES
    local monthValues, monthOrder = { [0] = EllesmereUI.L("None") }, { 0 }
    for m = 1, 12 do
        monthValues[m] = months and months[m] or tostring(m)
        monthOrder[m + 1] = m
    end
    local dayValues, dayOrder = { [0] = EllesmereUI.L("None") }, { 0 }
    for d = 1, 31 do
        dayValues[d] = tostring(d)
        dayOrder[d + 1] = d
    end
    -- The labels name the character: the birthday is this character's
    local who = UnitName("player") or UNKNOWN
    -- One reading per character per daily reset: the first read saves the period on
    -- the chart (readAt), and the birthday stays locked until that reset
    local function Locked()
        local c = Chart()
        return c ~= nil and c.readAt == Period()
    end
    local function LockTip()
        local left = math.max(0, Period() - time())
        return EllesmereUI.Lf("One reading a day: the birthday unlocks at the daily reset, in %s.",
            SecondsToTime(left, left >= 60, nil, 2))
    end

    _, h = W:SectionHeader(parent, "YOUR CHARACTER", y);  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = EllesmereUI.Lf("%s's Birth Month", who), values = monthValues, order = monthOrder,
          disabled = Locked, disabledTooltip = LockTip, rawTooltip = true,
          getValue = function() local c = Chart(); return c and c.month or 0 end,
          setValue = function(v) Set("month", v ~= 0 and v or nil) end },
        { type = "dropdown", text = EllesmereUI.Lf("%s's Birth Day", who), values = dayValues, order = dayOrder,
          disabled = Locked, disabledTooltip = LockTip, rawTooltip = true,
          getValue = function() local c = Chart(); return c and c.day or 0 end,
          setValue = function(v) Set("day", v ~= 0 and v or nil) end });  y = y - h

    local prebuild = EllesmereUI._prebuilding
    local pad = EllesmereUI.CONTENT_PAD
    local width = parent:GetWidth() - pad * 2
    local acR, acG, acB = EllesmereUI.GetAccentColor()
    -- Where the character was born: its race's starting zone, shown, never picked
    if not prebuild then
        local zone, raceName = BirthZone()
        local born = EllesmereUI.MakeFont(parent, 12, nil, 1, 1, 1, 0.55)
        born:SetWidth(width)
        born:SetJustifyH("CENTER")
        born:SetText(EllesmereUI.Lf("Born in %1$s, where every %2$s begins.",
            EllesmereUI.HexColor(acR, acG, acB) .. zone.name .. "|r", raceName or ""))
        PP.Point(born, "TOPLEFT", parent, "TOPLEFT", pad, y - 12)
    end
    y = y - 38

    _, h = W:SectionHeader(parent, "TONIGHT'S READING", y);  y = y - h
    if prebuild then return math.abs(y) end

    -- The star card: dim while sealed (as a skin's glyph while it is off), lit in
    -- the accent once read, the Moon in its real phase over a twinkling sky. While
    -- sealed the whole card is the Read Tonight's Stars button.
    local card = CreateFrame("Button", nil, parent)
    PP.Size(card, width, CARD_H)
    PP.Point(card, "TOPLEFT", parent, "TOPLEFT", pad, y - 6)
    local fill = card:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(FILL_R, FILL_G, FILL_B, 1)
    local border = EllesmereUI.MakeBorder(card, 1, 1, 1, 0.12, PP)
    local edge = card:CreateTexture(nil, "ARTWORK")
    edge:SetHeight(2)
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("TOPRIGHT")

    -- Two star sets twinkling out of step
    local skies = {}
    for s = 1, 2 do
        local sky = CreateFrame("Frame", nil, card)
        sky:SetAllPoints()
        local tw = sky:CreateAnimationGroup()
        tw:SetLooping("BOUNCE")
        local a = tw:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.2)
        a:SetDuration(s == 1 and 1.3 or 1.9)
        skies[s] = { frame = sky, twinkle = tw }
    end
    for i, st in ipairs(STARS) do
        local star = skies[i % 2 + 1].frame:CreateTexture(nil, "ARTWORK")
        PP.Size(star, st[3], st[3])
        PP.Point(star, "CENTER", card, "TOP", math.floor(st[1] * width), -st[2])
        star:SetColorTexture(1, 1, 1, 1)
    end

    -- The Moon: a lit disc, a card-coloured disc over it for the shadow (the
    -- earthshine shows through) and an accent halo
    local moon = card:CreateTexture(nil, "ARTWORK", nil, 1)
    PP.Size(moon, MOON, MOON)
    PP.Point(moon, "CENTER", card, "TOP", 0, -MOON_Y)
    moon:SetTexture(CIRCLE)
    local shade = card:CreateTexture(nil, "ARTWORK", nil, 2)
    PP.Size(shade, MOON + 2, MOON + 2)
    shade:SetTexture(CIRCLE)
    shade:SetVertexColor(FILL_R, FILL_G, FILL_B, 0.88)
    local halo = card:CreateTexture(nil, "ARTWORK", nil, 3)
    PP.Size(halo, MOON * 2, MOON * 2)
    PP.Point(halo, "CENTER", card, "TOP", 0, -MOON_Y)
    halo:SetTexture(CIRCLE)
    halo:SetBlendMode("ADD")

    -- The verdict, the sky's lines, the verdict's own line and the corners fade in together
    local content = CreateFrame("Frame", nil, card)
    content:SetAllPoints()
    local fade = content:CreateAnimationGroup()
    local fa = fade:CreateAnimation("Alpha")
    fa:SetFromAlpha(0)
    fa:SetToAlpha(1)
    fa:SetDuration(0.6)
    fa:SetSmoothing("OUT")
    local headline = EllesmereUI.MakeFont(content, 26)
    headline:SetWidth(width - 40)
    headline:SetJustifyH("CENTER")
    PP.Point(headline, "TOP", card, "TOP", 0, -HEAD_Y)
    local body = EllesmereUI.MakeFont(content, 13, nil, 1, 1, 1, 0.85)
    body:SetWidth(width - 60)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetSpacing(5)
    PP.Point(body, "TOP", card, "TOP", 0, -BODY_Y)
    -- The verdict's own line, under the sky's lines in the verdict's colour
    local verdict = EllesmereUI.MakeFont(content, 17)
    verdict:SetWidth(width - 60)
    verdict:SetJustifyH("CENTER")
    verdict:SetWordWrap(true)
    PP.Point(verdict, "TOP", body, "BOTTOM", 0, -16)

    -- The corners, for a glance: the Sun and rising signs over the sky, lucky and
    -- avoid under the reading, each a caption with its value away from the edge
    local G = EllesmereUI.ELLESMERE_GREEN
    local corners = {}
    for i, k in ipairs({
        { T.sunLabel, 1, 1, 1, 0.45 }, { T.riseLabel, 1, 1, 1, 0.45 },
        { T.luckyLabel, G.r, G.g, G.b, 1 }, { T.avoidLabel, 1, 0.4, 0.4, 1 },
    }) do
        local side = i % 2 == 1 and "LEFT" or "RIGHT"
        local x = side == "LEFT" and INSET or -INSET
        local cap = EllesmereUI.MakeFont(content, 12, nil, k[2], k[3], k[4], k[5])
        cap:SetText(k[1])
        local val = EllesmereUI.MakeFont(content, 16, nil, 1, 1, 1, 0.9)
        val:SetWidth(math.floor(width * 0.4))
        val:SetJustifyH(side)
        if i <= 2 then
            PP.Point(cap, "TOP" .. side, card, "TOP" .. side, x, -INSET)
            PP.Point(val, "TOP" .. side, cap, "BOTTOM" .. side, 0, -3)
        else
            PP.Point(val, "BOTTOM" .. side, card, "BOTTOM" .. side, x, INSET)
            PP.Point(cap, "BOTTOM" .. side, val, "TOP" .. side, 0, 3)
        end
        corners[i] = { cap = cap, val = val }
    end

    -- The sealed card's button: the shared button look, its mouse off, so the card
    -- takes every click and hands it its hover
    local cta = CreateFrame("Button", nil, content)
    PP.Size(cta, 260, 42)
    PP.Point(cta, "TOP", card, "TOP", 0, -(BODY_Y + 8))
    EllesmereUI.MakeStyledButton(cta, "Read Tonight's Stars", 14, EllesmereUI.WB_COLOURS)
    cta:EnableMouse(false)
    local ctaEnter, ctaLeave = cta:GetScript("OnEnter"), cta:GetScript("OnLeave")

    -- Send it .. log off
    local TIER_COLOR = { { G.r, G.g, G.b }, { 0.45, 0.88, 0.55 }, { 0.72, 0.92, 0.72 }, { 1, 1, 1 },
        { 1, 0.82, 0.5 }, { 1, 0.6, 0.32 }, { 1, 0.4, 0.4 } }
    -- lit: tonight's reading shows; askable: sealed with a birthday to read (the
    -- card takes the mouse only then, and its hover answers only then, so a leave
    -- that arrives after the reveal keeps the lit border)
    local lit, askable = false, false
    local function Twinkle(on)
        for _, s in ipairs(skies) do
            if on then s.twinkle:Play() else s.twinkle:Stop() end
        end
    end
    card:SetScript("OnShow", function() if lit then Twinkle(true) end end)
    card:SetScript("OnHide", function() Twinkle(false) end)
    card:SetScript("OnEnter", function()
        if not askable then return end
        border:SetColor(acR, acG, acB, 0.6)
        ctaEnter(cta)
    end)
    card:SetScript("OnLeave", function()
        if not askable then return end
        border:SetColor(1, 1, 1, 0.12)
        ctaLeave(cta)
    end)
    card:SetScript("OnClick", function()
        if not askable then return end
        local c = Chart(true)
        if c then c.readAt = (Period()) end
        -- the birthday rows lock with the reading
        EllesmereUI:RefreshPage()
        Paint(true)
    end)

    Paint = function(animate)
        local c = Chart()
        local r = c and c.readAt == Period() and Reading(c) or nil
        lit = r ~= nil
        askable = not lit and c and c.month and c.day and true or false
        card:EnableMouse(askable)
        ctaLeave(cta)
        cta:SetShown(askable)
        verdict:SetShown(lit)
        for _, k in ipairs(corners) do
            k.cap:SetShown(lit)
            k.val:SetShown(lit)
        end
        if lit then
            local col = TIER_COLOR[r.tier]
            border:SetColor(acR, acG, acB, 0.45)
            edge:SetColorTexture(acR, acG, acB, 1)
            moon:SetVertexColor(0.95, 0.95, 1, 1)
            halo:SetVertexColor(acR, acG, acB, 0.22)
            halo:Show()
            local share = MOON_LIT[r.phase]
            if share >= 1 then
                shade:Hide()
            else
                -- Waxing Moons are lit on the right, waning ones on the left
                local waxing = r.phase >= 2 and r.phase <= 4
                shade:ClearAllPoints()
                PP.Point(shade, "CENTER", moon, "CENTER", (waxing and -1 or 1) * MOON * share, 0)
                shade:Show()
            end
            for _, s in ipairs(skies) do s.frame:SetAlpha(0.85) end
            headline:SetTextColor(col[1], col[2], col[3], 1)
            headline:SetText(r.headline)
            body:SetText(r.sky)
            verdict:SetTextColor(col[1], col[2], col[3], 1)
            verdict:SetText(r.verdict)
            corners[1].val:SetText(r.sun)
            corners[2].val:SetText(r.rise)
            corners[3].val:SetText(r.lucky)
            corners[4].val:SetText(r.avoid)
        else
            border:SetColor(1, 1, 1, 0.12)
            edge:SetColorTexture(1, 1, 1, 0.12)
            moon:SetVertexColor(1, 1, 1, 0.1)
            halo:Hide()
            shade:Hide()
            for _, s in ipairs(skies) do s.frame:SetAlpha(0.12) end
            headline:SetTextColor(1, 1, 1, 0.35)
            headline:SetText(T.sealed)
            body:SetText(askable and "" or T.needBirthday)
        end
        Twinkle(lit and card:IsVisible())
        if animate then
            fade:Stop()
            fade:Play()
        end
    end
    Paint(false)
    EllesmereUI.RegisterWidgetRefresh(function() Paint(false) end)
    y = y - 6 - CARD_H

    local footer = EllesmereUI.MakeFont(parent, 10, nil, 1, 1, 1, 0.35)
    footer:SetWidth(width)
    footer:SetJustifyH("CENTER")
    footer:SetText(T.footer)
    PP.Point(footer, "TOPLEFT", parent, "TOPLEFT", pad, y - 14)
    return math.abs(y) + 40
end
