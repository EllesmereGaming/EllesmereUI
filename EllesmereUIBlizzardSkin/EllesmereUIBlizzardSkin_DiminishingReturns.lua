--------------------------------------------------------------------------------
--  Secondary / Tertiary Stat Diminishing Returns
--------------------------------------------------------------------------------
-- Powers the "Show Diminishing Returns" tooltip option on the themed character sheet.
--
-- Secondary stats (Crit, Haste, Mastery, Versatility) and tertiary stats
-- (Leech, Avoidance, Speed) suffer escalating diminishing returns once their
-- rating-derived percent crosses fixed breakpoints. The penalty is applied to
-- the *gross* percent a stat would grant with no DR (gross% = rating /
-- conversionFactor), bracket by bracket -- not to the in-game effect percent
-- shown for things like Mastery.
--
-- Breakpoint and penalty data are Blizzard game constants (item-scaling rows
-- 21024 / 21025); the per-level rating->percent conversion factors are the
-- corresponding combat-rating scale constants. These are reproduced here as
-- data. The calculation below is our own.
--------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Gross-percent brackets: each entry is the width (in gross %) of the bracket
-- and the rating penalty applied within it. Walking them yields how much rating
-- is "kept" (effective) versus "wasted" to the penalty.
local SECONDARY_BRACKETS = {
    { size = 30,     penalty = 0.00 },
    { size = 10,     penalty = 0.10 },
    { size = 10,     penalty = 0.20 },
    { size = 10,     penalty = 0.30 },
    { size = 20,     penalty = 0.40 },
    { size = 120,    penalty = 0.50 },
    { size = 1e9,    penalty = 1.00 },  -- hard cap (200% gross / 126% effective)
}

local TERTIARY_BRACKETS = {
    { size = 10,     penalty = 0.00 },
    { size = 5,      penalty = 0.20 },
    { size = 5,      penalty = 0.40 },
    { size = 80,     penalty = 0.60 },
    { size = 1e9,    penalty = 1.00 },
}

-- Per-level rating-per-1% conversion factors (level 1..90), Blizzard scale data.
-- Crit and Mastery share the same curve.
local CRIT_CONV = {
    3.056530805, 3.056530805, 3.056530805, 3.056530805, 3.056530805,
    3.056530805, 3.056530805, 3.056530805, 3.056530805, 3.056530805,
    3.056530805, 3.209357346, 3.362183886, 3.515010426, 3.667836966,
    3.820663507, 3.973490047, 4.126316587, 4.279143127, 4.431969668,
    4.477766688, 4.525529532, 4.575310357, 4.627163874, 4.681147453,
    4.737321222, 4.795748184, 4.856494328, 4.919628754, 4.985223804,
    5.053355196, 5.124102169, 5.197547633, 5.273778332, 5.352885007,
    5.434962577, 5.520110324, 5.608432089, 5.70003648,  5.795037088,
    5.893552718, 5.995707632, 6.1016318,   6.211461173, 6.325337961,
    6.443410936, 6.565835744, 6.692775235, 6.824399815, 6.960887811,
    7.102425863, 7.249209331, 7.401442727, 7.559340172, 7.723125876,
    7.893034645, 8.069312419, 8.252216833, 8.442017821, 8.638998236,
    8.843454528, 9.055697437, 9.276052741, 9.504862042, 9.742483593,
    9.989293177, 10.24568504, 10.51207285, 10.78889076, 11.07659452,
    11.18028258, 11.28494127, 11.39057967, 11.49720694, 11.60483236,
    11.71346526, 11.82311507, 11.93379132, 12.04550361, 12.15826163,
    13.58403151, 15.17699796, 16.95676773, 18.94524679, 21.16690997,
    23.6491022,  26.42237511, 29.520863,   32.98270306, 46,
}

local HASTE_CONV = {
    2.923638162, 2.923638162, 2.923638162, 2.923638162, 2.923638162,
    2.923638162, 2.923638162, 2.923638162, 2.923638162, 2.923638162,
    2.923638162, 3.06982007,  3.216001978, 3.362183886, 3.508365794,
    3.654547702, 3.80072961,  3.946911518, 4.093093426, 4.239275334,
    4.283081179, 4.328767379, 4.37638382,  4.425982836, 4.477619303,
    4.531350734, 4.587237394, 4.6453424,   4.705731852, 4.768474943,
    4.833644101, 4.901315118, 4.971567301, 5.044483622, 5.120150876,
    5.198659856, 5.280105527, 5.364587216, 5.452208807, 5.543078954,
    5.637311296, 5.735024692, 5.836343461, 5.941397644, 6.050323267,
    6.163262635, 6.280364625, 6.401785008, 6.527686779, 6.658240515,
    6.793624739, 6.934026317, 7.079640869, 7.230673208, 7.387337794,
    7.549859225, 7.718472748, 7.893424797, 8.074973567, 8.263389617,
    8.458956505, 8.661971461, 8.8727461,   9.09160717,  9.31889735,
    9.554976083, 9.800220469, 10.0550262,  10.31980856, 10.59500345,
    10.69418334, 10.79429165, 10.89533707, 10.99732838, 11.10027443,
    11.20418416, 11.30906659, 11.41493083, 11.52178606, 11.62964156,
    12.99342144, 14.51712849, 16.21951696, 18.12154041, 20.24660954,
    22.62088037, 25.27357619, 28.23734722, 31.5486725,  44,
}

local VERS_CONV = {
    3.58810138,  3.58810138,  3.58810138,  3.58810138,  3.58810138,
    3.58810138,  3.58810138,  3.58810138,  3.58810138,  3.58810138,
    3.58810138,  3.767506449, 3.946911518, 4.126316587, 4.305721656,
    4.485126725, 4.664531794, 4.843936863, 5.023341932, 5.202747001,
    5.25650872,  5.312578146, 5.371016506, 5.431888026, 5.495260053,
    5.561203174, 5.629791347, 5.701102037, 5.775216363, 5.852219248,
    5.932199578, 6.015250372, 6.101468961, 6.190957172, 6.28382153,
    6.38017346,  6.480129511, 6.583811583, 6.691347172, 6.802869625,
    6.918518409, 7.038439394, 7.162785157, 7.29171529,  7.425396737,
    7.564004143, 7.707720221, 7.856736146, 8.011251956, 8.171476996,
    8.337630361, 8.509941389, 8.688650158, 8.874008028, 9.066278202,
    9.265736322, 9.4726711,   9.687384978, 9.910194833, 10.14143271,
    10.38144662, 10.63060134, 10.8892793,  11.15788153, 11.43682857,
    11.72656156, 12.0275433,  12.34025943, 12.66521959, 13.00295878,
    13.12467955, 13.24753975, 13.37155004, 13.4967212,  13.62306408,
    13.75058965, 13.879309,   14.00923329, 14.1403738,  14.27274192,
    15.94647177, 17.81647587, 19.90577082, 22.24007232, 24.8481117,
    27.76198954, 31.01757078, 34.65492613, 38.71882534, 54,
}

local LEECH_CONV = {
    4.584861654, 4.584861654, 4.584861654, 4.584861654, 4.584861654,
    4.584861654, 4.584861654, 4.584861654, 4.584861654, 4.584861654,
    4.584861654, 4.814104737, 5.04334782,  5.272590902, 5.501833985,
    5.731077068, 5.96032015,  6.189563233, 6.418806316, 6.648049399,
    6.716745909, 6.788391199, 6.863063502, 6.940844888, 7.021821412,
    7.106083269, 7.193724963, 7.284845479, 7.37954847,  7.47794245,
    7.580140996, 7.68626297,  7.79643274,  7.91078042,  8.029442126,
    8.152560239, 8.280283682, 8.412768221, 8.550176769, 8.692679715,
    8.84045527,  8.993689828, 9.152578349, 9.317324759, 9.488142379,
    9.665254371, 9.848894204, 10.03930616, 10.23674585, 10.44148076,
    10.65379087, 10.87396922, 11.10232257, 11.33917212, 11.58485418,
    11.83972097, 12.10414141, 12.37850195, 12.66320749, 12.95868233,
    13.26537115, 13.58374006, 13.91427773, 14.25749658, 14.613934,
    14.98415366, 15.36874693, 15.76833435, 16.18356716, 16.61512895,
    16.77066326, 16.92765353, 17.08611339, 17.24605659, 17.40749702,
    17.5704487,  17.73492577, 17.90094251, 18.06851333, 18.23765278,
    20.37633812, 22.76582191, 25.43551468, 28.41827584, 31.75081818,
    35.47415968, 39.63412842, 44.2819266,  49.47476082, 69.00098495,
}

local AVOID_CONV = {
    2.445259549, 2.445259549, 2.445259549, 2.445259549, 2.445259549,
    2.445259549, 2.445259549, 2.445259549, 2.445259549, 2.445259549,
    2.445259549, 2.567522526, 2.689785504, 2.812048481, 2.934311459,
    3.056574436, 3.178837414, 3.301100391, 3.423363368, 3.545626346,
    3.582264485, 3.620475306, 3.660300534, 3.70178394,  3.74497142,
    3.789911077, 3.836653313, 3.885250922, 3.935759184, 3.988235973,
    4.042741865, 4.099340251, 4.158097461, 4.219082891, 4.282369134,
    4.348032127, 4.416151297, 4.486809718, 4.560094277, 4.636095848,
    4.714909477, 4.796634575, 4.881375119, 4.969239871, 5.060342602,
    5.154802331, 5.252743575, 5.354296618, 5.459597785, 5.56878974,
    5.682021798, 5.799450249, 5.921238704, 6.047558463, 6.178588896,
    6.314517852, 6.455542084, 6.601867705, 6.753710662, 6.911297244,
    7.074864612, 7.244661363, 7.420948123, 7.603998176, 7.794098131,
    7.991548617, 8.196665031, 8.409778322, 8.631235818, 8.861402106,
    8.94435374,  9.028081885, 9.112593809, 9.19789685,  9.283998413,
    9.370905974, 9.458627076, 9.547169336, 9.636540441, 9.726748149,
    10.86738033, 12.14177169, 13.56560783, 15.15641378, 16.9337697,
    18.91955183, 21.13820182, 23.61702752, 26.3865391,  36.80052531,
}

local SPEED_CONV = {
    0.764143609, 0.764143609, 0.764143609, 0.764143609, 0.764143609,
    0.764143609, 0.764143609, 0.764143609, 0.764143609, 0.764143609,
    0.764143609, 0.802350789, 0.84055797,  0.87876515,  0.916972331,
    0.955179511, 0.993386692, 1.031593872, 1.069801053, 1.108008233,
    1.119457652, 1.131398533, 1.143843917, 1.156807481, 1.170303569,
    1.184347211, 1.19895416,  1.214140913, 1.229924745, 1.246323742,
    1.263356833, 1.281043828, 1.299405457, 1.318463403, 1.338240354,
    1.35876004,  1.38004728,  1.402128037, 1.425029461, 1.448779953,
    1.473409212, 1.498948305, 1.525429725, 1.55288746,  1.581357063,
    1.610875728, 1.641482367, 1.673217693, 1.706124308, 1.740246794,
    1.775631812, 1.812328203, 1.850387095, 1.88986202,  1.93080903,
    1.973286829, 2.017356901, 2.063083658, 2.110534582, 2.159780389,
    2.210895191, 2.263956676, 2.319046288, 2.37624943,  2.435655666,
    2.497358943, 2.561457822, 2.628055726, 2.697261193, 2.769188158,
    2.795110544, 2.821275589, 2.847685565, 2.874342766, 2.901249504,
    2.928408117, 2.955820961, 2.983490418, 3.011418888, 3.039608797,
    3.396056354, 3.794303652, 4.239252446, 4.736379307, 5.29180303,
    5.912359947, 6.605688069, 7.3803211,   8.24579347,  11.50016416,
}

-- Map the character-sheet stat names to their conversion curve + bracket set.
-- Keys MUST match the stat.name strings in the CharacterSheet stat table
-- verbatim (the tooltip calls GetStatDR(stat.name, ...)): a display rename
-- there without a key update here silently drops the DR breakdown ("Crit"
-- -> "Critical Strike", 8.4.8).
local STAT_INFO = {
    ["Critical Strike"] = { conv = CRIT_CONV, brackets = SECONDARY_BRACKETS },
    Haste       = { conv = HASTE_CONV, brackets = SECONDARY_BRACKETS },
    Mastery     = { conv = CRIT_CONV,  brackets = SECONDARY_BRACKETS },
    Versatility = { conv = VERS_CONV,  brackets = SECONDARY_BRACKETS },
    Leech       = { conv = LEECH_CONV, brackets = TERTIARY_BRACKETS },
    Avoidance   = { conv = AVOID_CONV, brackets = TERTIARY_BRACKETS },
    Speed       = { conv = SPEED_CONV, brackets = TERTIARY_BRACKETS },
}

-- Returns diminishing-returns info for a stat given its raw combat rating, or
-- nil if the stat is not subject to DR / data is unavailable.
--   adjustedRating  : effective rating kept after DR penalties
--   wastedRating    : rating lost to the penalties (raw - adjusted)
--   penaltyPct      : the marginal penalty (%) applied to your next point of rating
--   nextPenaltyPct  : the penalty (%) of the next bracket, or nil at the hard cap
--   nextThreshold   : raw rating at which that next bracket begins, or nil
function EllesmereUI.GetStatDR(statName, rawRating)
    local info = STAT_INFO[statName]
    if not info or not rawRating or rawRating <= 0 then return nil end

    local level = UnitLevel("player") or 1
    if level < 1 then level = 1 end
    local conv = info.conv[level] or info.conv[#info.conv]
    if not conv or conv <= 0 then return nil end

    local grossPct   = rawRating / conv  -- percent the rating would grant with no DR
    local remaining  = grossPct
    local keptPct    = 0                 -- effective percent after penalties
    local penaltyPct = 0
    local consumed   = 0                 -- cumulative gross % at bracket boundaries
    local nextPenaltyPct, nextThreshold

    for i, bracket in ipairs(info.brackets) do
        if remaining <= bracket.size then
            keptPct    = keptPct + remaining * (1 - bracket.penalty)
            penaltyPct = bracket.penalty * 100  -- bracket we ended in = marginal penalty
            local nextBracket = info.brackets[i + 1]
            if nextBracket then
                -- The next bracket begins at the end of this one.
                nextPenaltyPct = nextBracket.penalty * 100
                nextThreshold  = (consumed + bracket.size) * conv
            end
            remaining = 0
            break
        end
        keptPct   = keptPct + bracket.size * (1 - bracket.penalty)
        remaining = remaining - bracket.size
        consumed  = consumed + bracket.size
    end

    local adjustedRating = keptPct * conv
    local wastedRating   = rawRating - adjustedRating

    return adjustedRating, wastedRating, penaltyPct, nextPenaltyPct, nextThreshold
end
