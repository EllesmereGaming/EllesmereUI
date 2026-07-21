-------------------------------------------------------------------------------
--  EllesmereUIMythicTimer.lua  —  M+ Timer overlay for EllesmereUI
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EMT = EllesmereUI.Lite.NewAddon(ADDON_NAME)

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local GetWorldElapsedTime = GetWorldElapsedTime
local GetTimePreciseSec = GetTimePreciseSec
local wipe = wipe

-- Constants
local PLUS_TWO_RATIO   = 0.8
local PLUS_THREE_RATIO = 0.6
local CHALLENGERS_PERIL_AFFIX_ID = 152

local COMPARE_NONE = "NONE"
local COMPARE_DUNGEON = "DUNGEON"
local COMPARE_LEVEL = "LEVEL"
local COMPARE_LEVEL_AFFIX = "LEVEL_AFFIX"

local TEXTURE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local barTextures = {
    ["none"]          = nil,
    ["melli"]         = TEXTURE_BASE .. "melli.tga",
    ["beautiful"]     = TEXTURE_BASE .. "beautiful.tga",
    ["plating"]       = TEXTURE_BASE .. "plating.tga",
    ["atrocity"]      = TEXTURE_BASE .. "atrocity.tga",
    ["divide"]        = TEXTURE_BASE .. "divide.tga",
    ["glass"]         = TEXTURE_BASE .. "glass.tga",
    ["fade-right"]    = TEXTURE_BASE .. "fade-right.tga",
    ["thin-line-top"] = TEXTURE_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = TEXTURE_BASE .. "thin-line-bottom.tga",
    ["fade"]          = TEXTURE_BASE .. "fade.tga",
    ["gradient-lr"]   = TEXTURE_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TEXTURE_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TEXTURE_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TEXTURE_BASE .. "gradient-tb.tga",
    ["matte"]         = TEXTURE_BASE .. "matte.tga",
    ["sheer"]         = TEXTURE_BASE .. "sheer.tga",
}
local barTextureOrder = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local barTextureNames = {
    ["none"]          = "None",
    ["melli"]         = "Melli (ElvUI)",
    ["beautiful"]     = "Beautiful",
    ["plating"]       = "Plating",
    ["atrocity"]      = "Atrocity",
    ["divide"]        = "Divide",
    ["glass"]         = "Glass",
    ["fade-right"]    = "Fade Right",
    ["thin-line-top"] = "Thin Line Top",
    ["thin-line-bottom"] = "Thin Line Bottom",
    ["fade"]          = "Fade",
    ["gradient-lr"]   = "Gradient Right",
    ["gradient-rl"]   = "Gradient Left",
    ["gradient-bt"]   = "Gradient Up",
    ["gradient-tb"]   = "Gradient Down",
    ["matte"]         = "Matte",
    ["sheer"]         = "Sheer",
}
ns.barTextures = barTextures
ns.barTextureOrder = barTextureOrder
ns.barTextureNames = barTextureNames

local function AppendSharedMediaBarTextures()
    if EllesmereUI and EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(barTextureNames, barTextureOrder, nil, barTextures)
    end
end
ns.AppendSharedMediaBarTextures = AppendSharedMediaBarTextures

local function ApplyBarTexture(tex, texKey, r, g, b, a)
    if not tex then return end
    local path = EllesmereUI and EllesmereUI.ResolveTexturePath
        and EllesmereUI.ResolveTexturePath(barTextures, texKey or "none", nil)
    if path then
        tex:SetTexture(path)
        tex:SetVertexColor(r, g, b, a)
    else
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetColorTexture(r, g, b, a)
    end
end

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for key, value in pairs(src) do
        out[key] = type(value) == "table" and CopyTable(value) or value
    end
    return out
end


local function CalculateBonusTimers(maxTime, affixes)
    local plusTwoT = (maxTime or 0) * PLUS_TWO_RATIO
    local plusThreeT = (maxTime or 0) * PLUS_THREE_RATIO

    if not maxTime or maxTime <= 0 then
        return plusTwoT, plusThreeT
    end

    if affixes then
        for _, affixID in ipairs(affixes) do
            if affixID == CHALLENGERS_PERIL_AFFIX_ID then
                local oldTimer = maxTime - 90
                if oldTimer > 0 then
                    plusTwoT = oldTimer * PLUS_TWO_RATIO + 90
                    plusThreeT = oldTimer * PLUS_THREE_RATIO + 90
                end
                break
            end
        end
    end

    return plusTwoT, plusThreeT
end

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled           = true,
        borderTexture     = "solid",
        borderSize        = 0,
        borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        showTitle         = true,
        showDungeonName   = true,
        -- Show the key level (e.g. "+21") with a divider to the left of the timer
        -- clock. Only usable while the dungeon name is hidden (the title is then
        -- just the lone key level, which moves down onto the timer line instead).
        showKeyLevelOnTimer = false,
        keyLevelTimerSpacing = 8,
        showAffixes       = true,
        showPlusTwoTimer  = true,
        showPlusThreeTimer = true,
        showThreshRemaining = false,
        showDeaths        = true,
        showObjectives    = true,
        showObjectiveTimes = true,
        objectiveTimePosition = "RIGHT",
        objectiveTextOffsetX = 0,
        objectiveTextOffsetY = 0,
        showEnemyBar      = true,
        showEnemyText     = true,
        scale             = 1.0,
        standaloneAlpha   = 0,
        showAccent        = false,
        showPreview       = false,
        enemyForcesPos    = "BOTTOM",
        enemyForcesPctPos = "LABEL",
        -- enemyForcesTextSize: intentionally unset so it falls back to objectivesSize
        -- (see RenderEnemyForces). Writing a default here would override a user's
        -- customized objectivesSize. Written only when the slider is changed.
        enemyForcesTextOffsetX = 0,
        enemyForcesTextOffsetY = 0,
        deathsInTitle     = false,
        deathTimeInTitle  = false,
        timerInBar        = false,
        showTimerBar      = true,
        showTimerBreakdown = false,
        titleAffixPosition = "ABOVE_TIMER",
        -- titleAffixDeathGap: intentionally unset so it falls back to ROW_GAP + 5
        -- (which tracks the user's rowGap). A hardcoded default would break the
        -- title/affix spacing for anyone who customized rowGap.
        titleAffixSandwichGap = 6,
        titleAffixTimerGap = 6,
        titleAffixBarGap = 6,
        alignAllText      = "RIGHT",
        titleUseAccent    = true,
        titleColor        = { r = 1, g = 1, b = 1 },
        titleSize         = 16,
        affixSize         = 12,
        thresholdSize     = 12,
        -- thresholdPlus*Size: intentionally unset so each falls back to thresholdSize
        -- (see RenderThresholdText). Hardcoding 12 here would override a user's
        -- customized thresholdSize. Written per-row only when its slider is changed.
        tickAlpha         = 1,
        timerBarStyle     = "TICKS",
        timerBarSegmentGap = 2,
        thresholdTextOffsetX = 0,
        thresholdTextOffsetY = 0,
        thresholdPlusThreeTextOffsetX = 0,
        thresholdPlusThreeTextOffsetY = 0,
        thresholdPlusTwoTextOffsetX = 0,
        thresholdPlusTwoTextOffsetY = 0,
        thresholdPlusOneTextOffsetX = 0,
        thresholdPlusOneTextOffsetY = 0,
        objectivesSize    = 12,
        timerExpiredColor = { r = 0.9, g = 0.2, b = 0.2 },
        enemyForcesTextFormat = "PERCENT",
        showCompletedMilliseconds = true,
        objectiveCompareMode = "NONE",
        objectiveCompareDeltaOnly = false,
        showUpcomingSplitTargets = false,
        frameWidth        = 260,
        barWidth          = 210,
        barHeight         = 8,
        barHeightExpanded = 22,
        barTexture        = "none",
        barBgTexture      = "none",
        enemyBarTexture   = "none",
        enemyBarBgTexture = "none",
        customBorderStyle = false,
        borderApplyToForces = true,
        rowGap            = 6,
        objectiveGap      = 4,
        timerPlusTwoColor = { r = 0.3, g = 0.8, b = 1 },
        timerPlusThreeColor = { r = 0.4, g = 1, b = 0.4 },
        timerBarUseCustomColor = false,
        timerBarColor = { r = 0.4, g = 1, b = 0.4 },
        timerSegment1Color = { r = 0.4, g = 1, b = 0.4 },
        timerSegment2Color = { r = 0.3, g = 0.8, b = 1 },
        timerSegment3Color = { r = 0xB0 / 255, g = 0x59 / 255, b = 0xCC / 255 },
        timerSegment1TextColor = { r = 0.4, g = 1, b = 0.4 },
        timerSegment2TextColor = { r = 0.3, g = 0.8, b = 1 },
        timerSegment3TextColor = { r = 1, g = 1, b = 1 },
        thresholdPlusThreeTextWhite = false,
        thresholdPlusTwoTextWhite = false,
        thresholdPlusOneTextWhite = false,
        affixTextColor    = { r = 1, g = 1, b = 1 },
        objectiveTextColor = { r = 0.9, g = 0.9, b = 0.9 },
        objectiveCompletedColor = { r = 0.3, g = 0.8, b = 0.3 },
        splitFasterColor  = { r = 0.4, g = 1, b = 0.4 },
        splitSlowerColor  = { r = 1, g = 0.45, b = 0.45 },
        deathTextColor    = { r = 0.93, g = 0.33, b = 0.33 },
        enemyBarUseAccent = true,
        enemyBarColor     = { r = 0.35, g = 0.55, b = 0.8 },
    },
}

-- Per-addon border texture defaults (same as resourcebars/cdm)
do
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for k = 0, 4 do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("MythicPlus", {
        ["glow"] = {
            defaultSize = 1,
            sizes = AllSizes(0, 0, 0, 0),
        },
        ["blizz"] = {
            defaultSize = 3,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 2, shiftX = 1, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                [4] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
            },
        },
        ["dialog"] = {
            defaultSize = 1,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 3, offsetY = 3, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 5, offsetY = 10, shiftX = 0, shiftY = 0 },
            },
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = 1,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 1, offsetY = 6, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 1, offsetY = 8, shiftX = 0, shiftY = 0 },
            },
        },
    })
end

-- State
local db
local updateTicker
local currentRun = {
    active        = false,
    mapID         = nil,
    mapName       = "",
    level         = 0,
    affixes       = {},
    maxTime       = 0,
    elapsed       = 0,
    completed     = false,
    deaths        = 0,
    deathTimeLost = 0,
    objectives    = {},
}

-- Per-player death tracking (reset each key).
-- Midnight removed CLEU, so we detect deaths by comparing the API death
-- count each tick and scanning the party for who is newly dead.
local playerDeaths = {}
local _prevDeathCount = 0
local _partyAlive = {}  -- [name] = true while alive, removed on death detection

local function ScanPartyAlive()
    wipe(_partyAlive)
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = (prefix == "party" and i == count) and "player" or (prefix .. i)
        local name = UnitName(unit)
        if name and not UnitIsDeadOrGhost(unit) then
            _partyAlive[name] = true
        end
    end
    if prefix == "party" then
        local name = UnitName("player")
        if name and not UnitIsDeadOrGhost("player") then
            _partyAlive[name] = true
        end
    end
end

local function CheckForNewDeaths(newDeathCount)
    if newDeathCount <= _prevDeathCount then
        _prevDeathCount = newDeathCount
        return
    end
    -- Death count went up -- find who is now dead that was alive last tick
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = (prefix == "party" and i == count) and "player" or (prefix .. i)
        local name = UnitName(unit)
        if name and _partyAlive[name] and UnitIsDeadOrGhost(unit) then
            playerDeaths[name] = (playerDeaths[name] or 0) + 1
            _partyAlive[name] = nil
        end
    end
    if prefix == "party" then
        local name = UnitName("player")
        if name and _partyAlive[name] and UnitIsDeadOrGhost("player") then
            playerDeaths[name] = (playerDeaths[name] or 0) + 1
            _partyAlive[name] = nil
        end
    end
    _prevDeathCount = newDeathCount
end

-- Helpers
local function FormatTime(seconds, withMilliseconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local whole = floor(seconds)
    local m = floor(whole / 60)
    local s = floor(whole % 60)
    if withMilliseconds then
        local ms = floor(((seconds - whole) * 1000) + 0.5)
        if ms >= 1000 then
            whole = whole + 1
            m = floor(whole / 60)
            s = floor(whole % 60)
            ms = 0
        end
        return format("%02d:%02d.%03d", m, s, ms)
    end
    return format("%02d:%02d", m, s)
end

-- Like FormatTime, but once the run is over time the remaining clock keeps
-- counting into the negative (e.g. "-01:04") instead of sitting frozen at
-- "00:00", so it's obvious by how much you're over.
local function FormatRemaining(remaining)
    if remaining and remaining < 0 then
        return "-" .. FormatTime(-remaining)
    end
    return FormatTime(remaining)
end

local function RoundToInt(value)
    if not value then return 0 end
    return floor(value + 0.5)
end

local function GetColor(tbl, fallbackR, fallbackG, fallbackB)
    if tbl then
        return tbl.r or fallbackR, tbl.g or fallbackG, tbl.b or fallbackB
    end
    return fallbackR, fallbackG, fallbackB
end

local function GetTimerBarFillColor(profile, elapsed, plusThreeTime, plusTwoTime, maxTime)
    if profile and profile.timerBarUseCustomColor == true then
        return GetColor(profile.timerBarColor, 0.4, 1, 0.4)
    end
    if maxTime and maxTime > 0 and elapsed > plusTwoTime then
        -- +2 lost: solid #B059CC.
        return 0xB0 / 255, 0x59 / 255, 0xCC / 255
    elseif maxTime and maxTime > 0 and elapsed > plusThreeTime then
        -- +3 lost, +2 still on: match the +2 threshold color.
        return GetColor(profile and profile.timerPlusTwoColor, 0.3, 0.8, 1)
    end
    -- On for +3: match the +3 threshold color.
    return GetColor(profile and profile.timerPlusThreeColor, 0.4, 1, 0.4)
end

local function GetTimerSegmentFillColor(profile, elapsed, plusThreeTime, plusTwoTime)
    if elapsed > plusTwoTime then
        return GetColor(profile and profile.timerSegment3Color, 0xB0 / 255, 0x59 / 255, 0xCC / 255)
    elseif elapsed > plusThreeTime then
        return GetColor(profile and profile.timerSegment2Color, 0.3, 0.8, 1)
    end
    return GetColor(profile and profile.timerSegment1Color, 0.4, 1, 0.4)
end

local function GetTimerSegmentTextColor(profile, index)
    if index == 3 then
        if profile and profile.thresholdPlusOneTextWhite == true then return 1, 1, 1 end
        return GetColor(profile and profile.timerSegment3Color, 0xB0 / 255, 0x59 / 255, 0xCC / 255)
    elseif index == 2 then
        if profile and profile.thresholdPlusTwoTextWhite == true then return 1, 1, 1 end
        return GetColor(profile and profile.timerSegment2Color, 0.3, 0.8, 1)
    end
    if profile and profile.thresholdPlusThreeTextWhite == true then return 1, 1, 1 end
    return GetColor(profile and profile.timerSegment1Color, 0.4, 1, 0.4)
end

local function NormalizeAffixKey(affixes)
    local ids = {}
    for _, affixID in ipairs(affixes or {}) do
        ids[#ids + 1] = affixID
    end
    table.sort(ids)
    return table.concat(ids, "-")
end

local function GetScopeKey(run, mode)
    if not run or not run.mapID then return nil end

    if mode == COMPARE_DUNGEON then
        return tostring(run.mapID)
    elseif mode == COMPARE_LEVEL then
        return format("%s:%d", run.mapID, run.level or 0)
    elseif mode == COMPARE_LEVEL_AFFIX then
        return format("%s:%d:%s", run.mapID, run.level or 0, NormalizeAffixKey(run.affixes))
    end

    return nil
end

local function EnsureProfileStore(key)
    if not db or not db.profile then return nil end
    if not db.profile[key] then db.profile[key] = {} end
    return db.profile[key]
end

local function GetReferenceObjectiveTime(run, objectiveIndex, mode)
    if mode == COMPARE_NONE then return nil end

    local store = EnsureProfileStore("bestObjectiveSplits")
    if not store then return nil end

    -- Try exact scope first, then fall back to broader scopes.
    -- LEVEL_AFFIX -> LEVEL -> DUNGEON
    local tryOrder
    if mode == COMPARE_LEVEL_AFFIX then
        tryOrder = { COMPARE_LEVEL_AFFIX, COMPARE_LEVEL, COMPARE_DUNGEON }
    elseif mode == COMPARE_LEVEL then
        tryOrder = { COMPARE_LEVEL, COMPARE_DUNGEON }
    else
        tryOrder = { mode }
    end

    for _, tryMode in ipairs(tryOrder) do
        local scopeKey = GetScopeKey(run, tryMode)
        local scope = scopeKey and store[scopeKey]
        if scope and scope[objectiveIndex] then
            return scope[objectiveIndex]
        end
    end
    return nil
end

local function UpdateBestObjectiveSplits(run, objectiveIndex, elapsed)
    local store = EnsureProfileStore("bestObjectiveSplits")
    if not store then return end

    for _, mode in ipairs({ COMPARE_DUNGEON, COMPARE_LEVEL, COMPARE_LEVEL_AFFIX }) do
        local scopeKey = GetScopeKey(run, mode)
        if scopeKey then
            if not store[scopeKey] then store[scopeKey] = {} end
            local previous = store[scopeKey][objectiveIndex]
            if not previous or elapsed < previous then
                store[scopeKey][objectiveIndex] = elapsed
            end
        end
    end
end

local function UpdateObjectiveCompletion(obj, objectiveIndex)
    if not db or not db.profile or not obj or not obj.elapsed or obj.elapsed <= 0 then return end

    local compareMode = db.profile.objectiveCompareMode or COMPARE_NONE
    local reference = GetReferenceObjectiveTime(currentRun, objectiveIndex, compareMode)
    obj.referenceElapsed = reference
    obj.compareDelta = reference and (obj.elapsed - reference) or nil
    obj.isNewBest = reference == nil or obj.elapsed < reference

    UpdateBestObjectiveSplits(currentRun, objectiveIndex, obj.elapsed)
end

local function BuildSplitCompareText(referenceTime, currentTime, deltaOnly, fasterColor, slowerColor)
    if not referenceTime or not currentTime then return "" end

    local diff = currentTime - referenceTime
    local color = diff <= 0 and fasterColor or slowerColor
    local cR, cG, cB = GetColor(color, 0.4, 1, 0.4)
    local diffPrefix = diff < 0 and "-" or "+"
    local diffText = diff == 0 and "0:00" or FormatTime(abs(diff))
    local colorHex = format("|cff%02x%02x%02x", floor(cR * 255), floor(cG * 255), floor(cB * 255))

    if deltaOnly then
        return format("  %s(%s%s)|r", colorHex, diffPrefix, diffText)
    end

    return format("  |cff888888(%s, %s%s%s)|r", FormatTime(referenceTime), colorHex, diffPrefix, diffText)
end

local function FormatEnemyForcesText(enemyObj, formatId, compact)
    local rawCurrent = enemyObj.rawQuantity or enemyObj.quantity or 0
    local rawTotal = enemyObj.rawTotalQuantity or enemyObj.totalQuantity or 100
    local percent = enemyObj.percent or enemyObj.quantity or 0
    local remaining = max(0, rawTotal - rawCurrent)
    local suffix = compact and "" or " Enemy Forces"

    if formatId == "COUNT" then
        return format("%d/%d%s", RoundToInt(rawCurrent), RoundToInt(rawTotal), suffix)
    elseif formatId == "COUNT_PERCENT" then
        return format("%d/%d - %.2f%%%s", RoundToInt(rawCurrent), RoundToInt(rawTotal), percent, suffix)
    elseif formatId == "REMAINING" then
        if compact then
            return format("%d left", RoundToInt(remaining))
        end
        return format("%d remaining%s", RoundToInt(remaining), suffix)
    end

    return format("%.2f%%%s", percent, suffix)
end

-- Objective tracking
local function UpdateObjectives()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    local elapsed = currentRun.elapsed

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local obj = currentRun.objectives[i]
            if not obj then
                obj = {
                    name          = "",
                    completed     = false,
                    elapsed       = 0,
                    quantity      = 0,
                    totalQuantity = 0,
                    rawQuantity   = 0,
                    rawTotalQuantity = 0,
                    percent       = 0,
                    isWeighted    = false,
                }
                currentRun.objectives[i] = obj
            end

            -- Strip Blizzard's leading checkmark so completed objectives
            -- render as clean text. UTF-8 for U+2713 is 0xE2 0x9C 0x93.
            local rawName = info.description or ("Objective " .. i)
            rawName = rawName:gsub("^\226\156\147%s*", "")
            rawName = rawName:gsub("^%-%s*", "")
            obj.name = rawName
            local wasCompleted = obj.completed
            obj.completed = info.completed

            if obj.completed and not wasCompleted then
                -- On reload, already-completed objectives would get current elapsed.
                -- Use persisted split time if available (saved on first completion).
                local saved = db and db.profile._activeRunSplits and db.profile._activeRunSplits[i]
                if saved and saved > 0 then
                    obj.elapsed = saved
                else
                    obj.elapsed = elapsed
                    -- Persist for reload survival
                    if db and db.profile then
                        if not db.profile._activeRunSplits then db.profile._activeRunSplits = {} end
                        db.profile._activeRunSplits[i] = elapsed
                    end
                end
                UpdateObjectiveCompletion(obj, i)
            end

            obj.quantity = info.quantity or 0
            obj.totalQuantity = info.totalQuantity or 0
            obj.rawQuantity = info.quantity or 0
            obj.rawTotalQuantity = info.totalQuantity or 0
            if info.isWeightedProgress then
                obj.isWeighted = true
                currentRun._weightedObj = obj  -- cached for RenderEnemyForces
                -- Normalize weighted progress to a 0-100 percent value.
                -- Cache the parsed result keyed on the raw string -- skips
                -- the gsub/tonumber chain on every tick where quantityString
                -- hasn't actually changed (the common case).
                local rawQuantity = info.quantity or 0
                local quantityString = info.quantityString
                if quantityString and quantityString ~= "" then
                    if obj._lastQS == quantityString then
                        rawQuantity = obj._lastQSParsed or rawQuantity
                    else
                        local normalized = quantityString:gsub("%%", "")
                        if normalized:find(",") and not normalized:find("%.") then
                            normalized = normalized:gsub(",", ".")
                        end
                        local parsed = tonumber(normalized)
                        if parsed then rawQuantity = parsed end
                        obj._lastQS, obj._lastQSParsed = quantityString, parsed
                    end
                end

                obj.rawQuantity = rawQuantity
                if obj.totalQuantity and obj.totalQuantity > 0 then
                    local percent = (rawQuantity / obj.totalQuantity) * 100
                    obj.quantity = floor(percent * 100 + 0.5) / 100
                else
                    obj.quantity = rawQuantity
                end
                obj.percent = obj.quantity

                if obj.completed then
                    obj.quantity = 100
                    obj.percent = 100
                    if obj.rawTotalQuantity and obj.rawTotalQuantity > 0 then
                        obj.rawQuantity = obj.rawTotalQuantity
                    end
                end
            else
                obj.isWeighted = false
                obj.percent = 0
                if obj.totalQuantity == 0 then
                    obj.quantity = obj.completed and 1 or 0
                    obj.totalQuantity = 1
                end
            end
        end
    end

    for i = numCriteria + 1, #currentRun.objectives do
        currentRun.objectives[i] = nil
    end
end

-- Coalesced refresh
local _refreshTimer
local function NotifyRefresh()
    if _refreshTimer then return end
    _refreshTimer = C_Timer.After(0.05, function()
        _refreshTimer = nil
        if _G._EMT_StandaloneRefresh then _G._EMT_StandaloneRefresh() end
    end)
end

-- Elapsed time: read from GetWorldElapsedTime(1) each tick. The Blizzard
-- hook on ChallengeModeBlock.UpdateTime is the primary tick driver (once
-- per second, zero cost outside M+). An OnUpdate fallback on our own
-- standalone frame ensures ticks keep firing even when QT reparents
-- ObjectiveTrackerFrame to a hidden container (which silences the hook).
local _lastTickedSec = -1

local function OnTimerTick()
    if not currentRun.active then return end

    local elapsed = select(2, GetWorldElapsedTime(1))
    if not (elapsed and elapsed >= 0) then return end

    -- Deduplicate: only refresh the display once per whole second.
    local sec = floor(elapsed)
    if sec == _lastTickedSec then return end
    _lastTickedSec = sec

    currentRun.elapsed = elapsed

    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    currentRun.deaths = deathCount or 0
    currentRun.deathTimeLost = timeLost or 0

    -- Detect per-player deaths, then refresh alive snapshot for next tick
    CheckForNewDeaths(deathCount or 0)
    ScanPartyAlive()

    UpdateObjectives()
    NotifyRefresh()
end

-- Primary driver: hook Blizzard's ChallengeModeBlock.UpdateTime (1/sec).
do
    local block = (ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock)
        or (ScenarioBlocksFrame and ScenarioBlocksFrame.ChallengeModeBlock)
    if block and block.UpdateTime then
        hooksecurefunc(block, "UpdateTime", function()
            OnTimerTick()
        end)
    end
end

-- Fallback driver: OnUpdate on the standalone frame, throttled to 1/sec.
-- Only runs while the frame is shown (active M+ key). Ensures the timer
-- stays accurate even when the hook is silenced by QT's reparent-to-hidden.
local _onUpdateAccum = 0
local function OnUpdateFallback(_, dt)
    _onUpdateAccum = _onUpdateAccum + dt
    if _onUpdateAccum < 1 then return end
    _onUpdateAccum = 0
    OnTimerTick()
end

local _timerLoopWanted = false
local function StartTimerLoop()
    _timerLoopWanted = true
    if standaloneFrame then
        _onUpdateAccum = 0
        standaloneFrame:SetScript("OnUpdate", OnUpdateFallback)
    end
end
local function StopTimerLoop()
    _timerLoopWanted = false
    if standaloneFrame then
        standaloneFrame:SetScript("OnUpdate", nil)
    end
end

-- Hide Blizzard's ObjectiveTrackerFrame whenever our M+ timer is enabled
-- and we're in an active challenge mode. Permanent hooksecurefunc on Show:
-- every time Blizzard tries to show it during M+, we re-hide it. No
-- SetParent (avoids tainting the secure scenario tree), no recursion into
-- children (avoids the invisible-click-catcher pattern).
local function TrackerShouldBeHidden()
    if not (db and db.profile and db.profile.enabled) then return false end
    -- Hide during active challenge AND after it completes but before the
    -- player has left the dungeon instance. Blizzard's end-of-run fanfare
    -- flips IsChallengeModeActive() back to false while the user is still
    -- inside -- without the completed + party gate the tracker pops back
    -- up for the last seconds before zone-out.
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    if currentRun and currentRun.completed then
        local _, iType = GetInstanceInfo()
        return iType == "party"
    end
    return false
end

-- ObjectiveTrackerFrame is EditMode-managed: its Hide() routes through the
-- system template to HideBase(), which is protected, so calling it from our
-- execution during combat is blocked (ADDON_ACTION_BLOCKED). In combat,
-- suppress with alpha only (top-level frame, never children, never mouse
-- state) and finish the real Hide once combat drops. The regen listener is
-- one-shot: it unregisters on fire and is re-registered by each new
-- in-combat request.
local _trackerRegenFrame
local function HideTracker(otf)
    if InCombatLockdown() then
        otf:SetAlpha(0)
        if not _trackerRegenFrame then
            _trackerRegenFrame = CreateFrame("Frame")
            _trackerRegenFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                local f = _G.ObjectiveTrackerFrame
                if not f then return end
                f:SetAlpha(1)
                if TrackerShouldBeHidden() then f:Hide() end
            end)
        end
        _trackerRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        otf:SetAlpha(1)  -- clear any combat alpha-suppression before hiding
        otf:Hide()
    end
end

local _trackerHookInstalled = false
local function InstallTrackerHook()
    if _trackerHookInstalled then return end
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    _trackerHookInstalled = true
    hooksecurefunc(otf, "Show", function()
        if TrackerShouldBeHidden() then
            HideTracker(otf)
        end
    end)
end

-- Force a re-evaluation now (used at run start / option change). If we're
-- in M+ and the addon is enabled, tracker hides; otherwise nothing happens.
local function ApplyTrackerVisibility()
    InstallTrackerHook()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    if TrackerShouldBeHidden() then
        HideTracker(otf)
    end
end

local function SuppressBlizzardMPlus()
    ApplyTrackerVisibility()
    if _G._EQT_SetSuppressed then _G._EQT_SetSuppressed("MythicPlus", true) end
end
local function UnsuppressBlizzardMPlus()
    if _G._EQT_SetSuppressed then _G._EQT_SetSuppressed("MythicPlus", false) end
end

-- Run lifecycle
local function StartRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then return end
    _lastTickedSec = -1  -- reset dedup so the first tick always fires

    local mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()

    currentRun.active        = true
    currentRun.completed     = false
    currentRun.mapID         = mapID
    currentRun.mapName       = mapName or "Unknown"
    currentRun.level         = level or 0
    currentRun.maxTime       = timeLimit or 0
    currentRun.elapsed       = 0
    currentRun.deaths        = 0
    currentRun.deathTimeLost = 0
    wipe(playerDeaths)
    _prevDeathCount = 0
    ScanPartyAlive()
    currentRun.affixes       = affixes or {}
    -- Cache affix names ONCE at run start. They never change mid-run, but
    -- RenderStandalone was previously calling C_ChallengeMode.GetAffixInfo
    -- for every affix on every render tick.
    currentRun.affixNames = {}
    if affixes then
        for i, affixID in ipairs(affixes) do
            local name = C_ChallengeMode.GetAffixInfo(affixID)
            currentRun.affixNames[i] = name or ""
        end
    end
    currentRun.preciseStart = GetTimePreciseSec and GetTimePreciseSec() or nil
    currentRun.preciseCompletedElapsed = nil
    currentRun._lastDungeonComplete = false
    currentRun._weightedObj = nil  -- populated by UpdateObjectives
    wipe(currentRun.objectives)

    StartTimerLoop()
    OnTimerTick()  -- prime the display immediately

    SuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CompleteRun()
    currentRun.completed = true
    currentRun.active = false

    StopTimerLoop()

    -- Use C_ChallengeMode.GetChallengeCompletionInfo() as the authoritative
    -- completion time (milliseconds). GetWorldElapsedTime can return secret
    -- or stale values after depletion, producing "99:99" display.
    local completionInfo = C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    if completionInfo and completionInfo.time and completionInfo.time > 0 then
        currentRun.elapsed = completionInfo.time / 1000
    else
        local elapsedTime = select(2, GetWorldElapsedTime(1))
        currentRun.elapsed = elapsedTime or currentRun.elapsed
    end
    if currentRun.preciseStart and GetTimePreciseSec then
        currentRun.preciseCompletedElapsed = max(0, GetTimePreciseSec() - currentRun.preciseStart)
    end
    UpdateObjectives()
    if db and db.profile then db.profile._activeRunSplits = nil end
    NotifyRefresh()
end

local function ResetRun()
    _lastTickedSec = -1
    currentRun.active    = false
    currentRun.completed = false
    currentRun.mapID     = nil
    currentRun.mapName   = ""
    currentRun.level     = 0
    currentRun.maxTime   = 0
    currentRun.elapsed   = 0
    currentRun.deaths    = 0
    currentRun.deathTimeLost = 0
    wipe(playerDeaths)
    _prevDeathCount = 0
    wipe(_partyAlive)
    currentRun.preciseStart = nil
    currentRun.preciseCompletedElapsed = nil
    currentRun._lastDungeonComplete = false
    wipe(currentRun.affixes)
    wipe(currentRun.objectives)
    if db and db.profile then db.profile._activeRunSplits = nil end

    StopTimerLoop()

    UnsuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CheckForActiveRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if mapID then StartRun() end
end

-- Preview data
local PREVIEW_RUN = {
    active        = true,
    completed     = false,
    mapID         = 2648,
    mapName       = "The Rookery",
    level         = 12,
    maxTime       = 1920,
    elapsed       = 1380,
    deaths        = 2,
    deathTimeLost = 10,
    affixes       = {},
    preciseCompletedElapsed = nil,
    _previewAffixNames = { "Tyrannical", "Xal'atath's Bargain: Ascendant" },
    _previewAffixIDs = { 9, 152 },
    objectives    = {
        { name = "Kyrioss",                 completed = true,  elapsed = 510,  quantity = 1,     totalQuantity = 1,   rawQuantity = 1, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Stormguard Gorren",       completed = true,  elapsed = 1005, quantity = 1,     totalQuantity = 1,   rawQuantity = 1, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Lua Error Monstrosity",   completed = false, elapsed = 0,    quantity = 0,     totalQuantity = 1,   rawQuantity = 0, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "|cffff3333Ellesmere|r",    completed = false, elapsed = 0,    quantity = 0,     totalQuantity = 1,   rawQuantity = 0, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Enemy Forces",            completed = false, elapsed = 0,    quantity = 78.42, totalQuantity = 100, rawQuantity = 188, rawTotalQuantity = 240, percent = 78.42, isWeighted = true },
    },
}

_G._EMT_Apply = function()
    -- Render before CENTER re-apply so height is known (placeholder is 200px).
    if _G._EMT_StandaloneRefresh then _G._EMT_StandaloneRefresh() end
    if _G._EMT_ApplyStandalonePosition then
        _G._EMT_ApplyStandalonePosition()
    end
end

-- Preset system removed. Users tweak settings directly.

-- Reset the current profile back to defaults.
-- Used by the module's "Reset" button in the EllesmereUI options panel.
_G._EMT_ResetProfile = function()
    if not db or not db.profile then return false end

    -- Clear every key in the current profile
    for key in pairs(db.profile) do
        db.profile[key] = nil
    end

    -- Repopulate with DB defaults
    for key, value in pairs(DB_DEFAULTS.profile) do
        db.profile[key] = type(value) == "table" and CopyTable(value) or value
    end

    if _G._EMT_StandaloneRefresh then
        _G._EMT_StandaloneRefresh()
    end
    return true
end

-- Standalone frame
local standaloneFrame
local standaloneCreated = false
local unlockLayoutActive = false -- force preview layout while Unlock Mode is open

-- NOTE: this function must be defined HERE (after the "local standaloneFrame"
-- and "local db" declarations). Placed earlier in the file (before those
-- locals) Lua would bind it to the same-named GLOBALS (which are never set)
-- instead of the locals, so it would always hit its early return immediately.
--
-- Uses the shared border system from EllesmereUI.lua (EllesmereUI.ApplyBorderStyle)
-- rather than a bespoke solution:
--   - "solid"           -> PP 4-strip system (as everywhere else in the addon)
--   - any other key     -> textured BackdropTemplate border (Glow, Blizzard,
--                          Lightspark, SharedMedia, ...)
-- ApplyBorderStyle needs a frame WE own ("borderFrame"). The bars ("_barBg",
-- "_enemyBarBg", segments in "_timerSegBgs") are only textures, so we give each
-- bar a slim carrier frame that sits exactly over its texture (SetAllPoints)
-- and hand THAT frame to ApplyBorderStyle.
local function ApplyBorderTo(parent, anchor, key, p, size, texKey, r, g, b, a)
    if not parent or not anchor then
        return
    end

    local bf = parent[key]
    -- Zero cost unless enabled: when the border is off (size 0 or the anchor is
    -- hidden) and no carrier frame was ever built, do nothing. No frame is
    -- created and no restyle runs for users who never turn a border on.
    if not bf and (size <= 0 or not anchor:IsShown()) then
        return
    end
    if not bf then
        bf = CreateFrame("Frame", nil, parent)
        bf:EnableMouse(false)
        bf:SetFrameLevel(parent:GetFrameLevel() + 10)
        -- Clip every border (including textured styles with an outward
        -- offsetX/offsetY, e.g. Glow/Blizzard) strictly to the area of "bf"
        -- (== the bar/segment). Without this, textured border styles spill past
        -- the segment edges and overlap in the gaps between segments.
        bf:SetClipsChildren(true)
        parent[key] = bf
        parent._emtBordersBuilt = true
    end

    bf:ClearAllPoints()
    bf:SetAllPoints(anchor)

    if size <= 0 or not anchor:IsShown() then
        bf:Hide()
        EllesmereUI.ApplyBorderStyle(bf, 0, r, g, b, a, texKey)
        return
    end

    bf:Show()
    EllesmereUI.ApplyBorderStyle(
        bf, size, r, g, b, a, texKey,
        p.borderTextureOffset, p.borderTextureOffsetY,
        p.borderTextureShiftX, p.borderTextureShiftY,
        "MythicPlus", size
    )
end

ns.ApplyBorder = function()
    if not standaloneFrame or not db or not db.profile then
        return
    end

    local f = standaloneFrame
    local p = db.profile
    local size = p.borderSize or 0
    -- "Custom Border Style" is the master gate: when off, no border renders
    -- regardless of the saved borderSize.
    if not p.customBorderStyle then size = 0 end
    -- Zero cost unless enabled: if the border is off and none were ever built,
    -- skip the whole pass (no per-segment loop, no restyle calls).
    if size <= 0 and not f._emtBordersBuilt then
        return
    end
    local texKey = p.borderTexture or "solid"
    local r, g, b, a = p.borderR or 0, p.borderG or 0, p.borderB or 0, p.borderA or 1

    -- Main timer bar.
    -- In SEGMENTS mode "_barBg" is only an invisible (Alpha 0) but still
    -- :IsShown() texture that spans the ENTIRE bar width (including the gaps
    -- between segments). Bordering it here would draw a border line in the gaps
    -- too (left/right is hidden by the adjacent segment border, top/bottom is
    -- not), so in SEGMENTS mode the main border is disabled here; the individual
    -- segment borders below draw the complete outline.
    local isSegmented = (p.timerBarStyle == "SEGMENTS")
    if isSegmented then
        ApplyBorderTo(f, f._barBg, "_emtBarBorderFrame", p, 0, texKey, r, g, b, a)
    else
        ApplyBorderTo(f, f._barBg, "_emtBarBorderFrame", p, size, texKey, r, g, b, a)
    end

    -- Forces bar (skipped when "Apply to Forces Bar" is off in the border cog).
    local forcesSize = size
    if p.borderApplyToForces == false then forcesSize = 0 end
    ApplyBorderTo(f, f._enemyBarBg, "_emtEnemyBorderFrame", p, forcesSize, texKey, r, g, b, a)

    -- Segment bars (timer bar SEGMENTS mode)
    if f._timerSegBgs then
        for i, seg in ipairs(f._timerSegBgs) do
            local segSize = isSegmented and size or 0
            ApplyBorderTo(f, seg, "_emtSegBorderFrame" .. i, p, segSize, texKey, r, g, b, a)
        end
    end
end

-- Font helpers
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
local FONT_OPTIONS = {
    { key = nil,                          label = "EllesmereUI Default" },
    { key = "Fonts/FRIZQT__.TTF",         label = "Fritz Quadrata" },
    { key = "Fonts/ARIALN.TTF",           label = "Arial Narrow" },
    { key = "Fonts/MORPHEUS.TTF",         label = "Morpheus" },
    { key = "Fonts/SKURRI.TTF",           label = "Skurri" },
    { key = "Fonts/FRIZQT___CYR.TTF",     label = "Fritz Quadrata (Cyrillic)" },
    { key = "Fonts/ARHei.TTF",            label = "AR Hei (CJK)" },
}
local function SFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        local p = EllesmereUI.GetFontPath("mythicTimer")
        if p and p ~= "" then return p end
    end
    return FALLBACK_FONT
end
-- _EMT_GetFontOptions removed: font dropdown deleted from options page.
local function SOutline()
    if EllesmereUI.GetFontOutlineFlag then return EllesmereUI.GetFontOutlineFlag("mythicTimer") end
    return ""
end
local function SetFS(fs, size, flags)
    if not fs then return end
    local p = SFont()
    flags = flags or SOutline()
    fs:SetFont(p, size, flags)
    if not fs:GetFont() then fs:SetFont(FALLBACK_FONT, size, flags) end
end
-- Per-user font override for the TIMER clock text only (profile.timerFont, a
-- dropdown key: "__global"/nil = follow the module font). SharedMedia keys
-- resolve via EllesmereUI.ResolveFontName, matching the Quest Tracker font
-- picker; anything else falls back to the module font (SFont).
local function TimerFont()
    local key = db and db.profile and db.profile.timerFont
    if key and key ~= "__global" and EllesmereUI and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(key)
        if path and path ~= "" then return path end
    end
    return SFont()
end
local function SetTimerFS(fs, size, flags)
    if not fs then return end
    local p = TimerFont()
    flags = flags or SOutline()
    fs:SetFont(p, size, flags)
    if not fs:GetFont() then fs:SetFont(FALLBACK_FONT, size, flags) end
end
local function ApplyShadow(fs)
    if not fs then return end
    local useShadow = EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("mythicTimer")
    -- Font is set elsewhere (SetFS) and ApplyShadow runs after it, so capture
    -- and restore the current font around PrimeFontShadow's SetFontObject.
    local _pf, _ps, _pfl = fs:GetFont()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, useShadow) end
    if _pf then fs:SetFont(_pf, _ps, _pfl) end
end

-- SetText with skip-if-unchanged. Avoids the per-tick SetText call (and
-- the implicit re-measure / re-layout) when the string hasn't changed.
local function SetTextDiff(fs, text)
    if not fs then return end
    text = text or ""
    if fs._lastText == text then return end
    fs:SetText(text)
    fs._lastText = text
end

local function SetFittedText(fs, text, maxWidth, preferredSize, minSize)
    if not fs then return end
    text = text or ""
    preferredSize = preferredSize or 10
    minSize = minSize or 8
    local outline = SOutline()
    SetFS(fs, preferredSize, outline)
    ApplyShadow(fs)
    fs:SetText(text)

    for size = preferredSize, minSize, -1 do
        SetFS(fs, size, outline)
        ApplyShadow(fs)
        fs:SetText(text)
        if not maxWidth or fs:GetStringWidth() <= maxWidth then
            return
        end
    end
end

-- Widest single-digit glyph in fs's CURRENT font. Clock-width templates replace
-- every digit with this instead of a hardcoded "9": proportional / oldstyle
-- numeral fonts can render another digit (e.g. "0" or "3") wider than "9", so a
-- "9" template under-measures and the pinned width then ellipsizes the live clock
-- (e.g. "33:00"). fs must already have its final font applied. Clears the width so
-- the per-glyph measurements are unbounded. Called only when a width cache key
-- changes (font / size / scale / length), never per tick.
local function WidestDigitChar(fs)
    fs:SetWidth(0)
    local widest, widestW = "9", 0
    for d = 0, 9 do
        local ch = tostring(d)
        fs:SetText(ch)
        local w = fs:GetStringWidth() or 0
        if w > widestW then widestW = w; widest = ch end
    end
    return widest
end

-- Set a threshold FontString's text and pin it to a stable, jitter-free width
-- based on the widest digit in the current font, so the small +2 / +3 / remaining
-- countdowns do not "breathe" horizontally as the seconds tick in a proportional
-- font (the same width-pin idea the main clock uses, applied to the threshold
-- row). Color escapes are zero-width, so they are stripped before templatizing.
-- The caller (placeAt) sets JustifyH to match the anchor edge so one edge stays
-- fixed. Returns the pinned width for the remaining-mode overlap packing.
local function SetThreshText(fs, text)
    local visible = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    fs:SetText((visible:gsub("%d", WidestDigitChar(fs))))
    -- +1px only (vs the clock's +3): the widest-digit template already covers the
    -- worst-case text for this length, so 1px is enough to absorb subpixel rounding
    -- at fractional UI scales -- keeps packed labels tight when GAP is 0.
    local w = (fs:GetStringWidth() or 0) + 1
    fs:SetWidth(w)
    fs:SetText(text)
    return w
end

local function GetAccentColor()
    if EllesmereUI.ResolveActiveAccent then
        return EllesmereUI.ResolveActiveAccent()
    end
    return 0.05, 0.83, 0.62
end

local function StripDefeated(name)
    if not name then return name end
    name = name:gsub("[Dd]efeated", "")
    return name:match("^%s*(.-)%s*$") or name
end

local objRows = {}
local function GetObjRow(parent, idx)
    if objRows[idx] then return objRows[idx] end
    local nameFS = parent:CreateFontString(nil, "OVERLAY")
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    local timeFS = parent:CreateFontString(nil, "OVERLAY")
    timeFS:SetWordWrap(false)
    timeFS:SetNonSpaceWrap(false)
    local entry = { name = nameFS, time = timeFS }
    objRows[idx] = entry
    return entry
end

local function CreateStandaloneFrame()
    if standaloneCreated then return standaloneFrame end
    standaloneCreated = true

    local f = CreateFrame("Frame", "EllesmereUIMythicTimerStandalone", UIParent, "BackdropTemplate")
    f:SetSize(260, 200)
    -- Default position: top of quest tracker, or right-side fallback
    local otf = _G.ObjectiveTrackerFrame
    if otf and otf:GetTop() then
        f:SetPoint("TOPRIGHT", otf, "TOPRIGHT", 0, 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -100, 0)
    end
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.04, 0.08, 0.85)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.6)

    -- Dedicated layer for text that sits ABOVE the bars (timer / forces /
    -- threshold text). ns.ApplyBorder() gives each bar/segment a border wrapper
    -- frame that always sits above "f" (ApplyBorderStyle's border container
    -- frame is always FrameLevel = passed frame + 1). Without this layer the
    -- border would therefore ALWAYS sit above the text, whatever draw layer the
    -- text uses (frame level beats draw layer across different frames). Must be
    -- created BEFORE the fontstrings below so they can be reparented onto it.
    f._emtTextLayer = CreateFrame("Frame", nil, f)
    f._emtTextLayer:SetFrameLevel(f:GetFrameLevel() + 30)
    f._emtTextLayer:EnableMouse(false)

    f._accent = f:CreateTexture(nil, "BORDER")
    f._accent:SetWidth(2)
    f._accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f._accent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    f._titleFS = f:CreateFontString(nil, "OVERLAY")
    f._titleFS:SetWordWrap(false)
    f._titleFS:SetJustifyV("MIDDLE")

    f._affixFS = f:CreateFontString(nil, "OVERLAY")
    f._affixFS:SetWordWrap(true)

    f._timerFS = f:CreateFontString(nil, "OVERLAY")
    f._timerFS:SetJustifyH("CENTER")
    f._timerFS:SetWordWrap(false)
    f._timerFS:SetNonSpaceWrap(false)
    -- Optional "+key  |" prefix rendered to the left of the timer clock
    -- (Show Key Level on Timer). Single-anchored, no explicit width, so it
    -- auto-sizes and never truncates.
    f._keyLevelFS = f:CreateFontString(nil, "OVERLAY")
    f._keyLevelFS:SetWordWrap(false)
    f._keyLevelFS:SetNonSpaceWrap(false)
    f._timerDetailFS = f:CreateFontString(nil, "OVERLAY")
    f._timerDetailFS:SetWordWrap(false)
    f._timerDetailFS:SetNonSpaceWrap(false)
    f._barBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f._barFill = f:CreateTexture(nil, "ARTWORK")
    f._seg3 = f:CreateTexture(nil, "OVERLAY")
    f._seg2 = f:CreateTexture(nil, "OVERLAY")
    f._threshFS = f:CreateFontString(nil, "OVERLAY")
    f._threshFS:SetParent(f._emtTextLayer)
    f._threshFS:SetWordWrap(false)
    f._threshFS2 = f:CreateFontString(nil, "OVERLAY")
    f._threshFS2:SetParent(f._emtTextLayer)
    f._threshFS2:SetWordWrap(false)
    f._threshRemFS = f:CreateFontString(nil, "OVERLAY")
    f._threshRemFS:SetParent(f._emtTextLayer)
    f._threshRemFS:SetWordWrap(false)
    f._deathFS = f:CreateFontString(nil, "OVERLAY")
    f._deathFS:SetWordWrap(false)
    f._deathHit = CreateFrame("Frame", nil, f)
    f._deathHit:SetFrameLevel(f:GetFrameLevel() + 5)
    f._deathHit:EnableMouse(true)

    -- Custom two-column death tooltip
    local deathTT = CreateFrame("Frame", nil, UIParent)
    deathTT:SetFrameStrata("TOOLTIP")
    deathTT:SetFrameLevel(200)
    deathTT:Hide()
    local ttBg = deathTT:CreateTexture(nil, "BACKGROUND")
    ttBg:SetAllPoints()
    ttBg:SetColorTexture(0.067, 0.067, 0.067, 0.90)
    EllesmereUI.MakeBorder(deathTT, 1, 1, 1, 0.15, EllesmereUI.PanelPP)
    deathTT._rows = {}

    local TT_PAD   = 8
    local TT_ROW_H = 14
    local TT_GAP   = 3
    local TT_FONT  = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"

    local function EnsureRows(n)
        for i = #deathTT._rows + 1, n do
            local nameFS = deathTT:CreateFontString(nil, "OVERLAY")
            nameFS:SetFont(TT_FONT, 10, "")
            nameFS:SetJustifyH("LEFT")
            local countFS = deathTT:CreateFontString(nil, "OVERLAY")
            countFS:SetFont(TT_FONT, 10, "")
            countFS:SetJustifyH("RIGHT")
            deathTT._rows[i] = { name = nameFS, count = countFS }
        end
    end

    f._deathHit:SetScript("OnEnter", function(self)
        local deaths = playerDeaths
        if not next(deaths) and currentRun.deaths and currentRun.deaths > 0 then
            deaths = { [UnitName("player") or "You"] = currentRun.deaths }
        end
        if not next(deaths) then return end

        local list = {}
        for name, count in pairs(deaths) do
            list[#list + 1] = { name = name, count = count }
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)

        EnsureRows(#list)

        -- Hide all rows first
        for i = 1, #deathTT._rows do
            deathTT._rows[i].name:Hide()
            deathTT._rows[i].count:Hide()
        end

        -- Measure max name width for tooltip sizing
        local maxNameW = 0
        local maxCountW = 0
        for i, entry in ipairs(list) do
            local row = deathTT._rows[i]
            local classFile = select(2, UnitClass(entry.name))
            local color = classFile and (RAID_CLASS_COLORS[classFile] or RAID_CLASS_COLORS["PRIEST"])
            local short = Ambiguate and Ambiguate(entry.name, "short") or entry.name
            local colored = color and color:WrapTextInColorCode(short) or short
            row.name:SetText(colored)
            row.name:SetTextColor(1, 1, 1, 0.80)
            row.count:SetText(entry.count)
            row.count:SetTextColor(1, 1, 1, 0.80)
            local nw = row.name:GetStringWidth() or 0
            local cw = row.count:GetStringWidth() or 0
            if nw > maxNameW then maxNameW = nw end
            if cw > maxCountW then maxCountW = cw end
        end

        local ttW = TT_PAD + maxNameW + 12 + maxCountW + TT_PAD
        local ttH = TT_PAD + #list * TT_ROW_H + (#list - 1) * TT_GAP + TT_PAD

        deathTT:SetSize(ttW, ttH)

        -- Position rows
        for i, entry in ipairs(list) do
            local row = deathTT._rows[i]
            local yOff = -TT_PAD - (i - 1) * (TT_ROW_H + TT_GAP)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", deathTT, "TOPLEFT", TT_PAD, yOff)
            row.count:ClearAllPoints()
            row.count:SetPoint("TOPRIGHT", deathTT, "TOPRIGHT", -TT_PAD, yOff)
            row.name:Show()
            row.count:Show()
        end

        -- Anchor tooltip above the death text
        local right = (self._align or "LEFT") == "RIGHT"
        deathTT:ClearAllPoints()
        if right then
            deathTT:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 4)
        else
            deathTT:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
        end
        deathTT:Show()
    end)
    f._deathHit:SetScript("OnLeave", function()
        deathTT:Hide()
    end)
    f._enemyFS = f:CreateFontString(nil, "OVERLAY")
    f._enemyFS:SetParent(f._emtTextLayer)
    f._enemyFS:SetWordWrap(false)
    f._enemyBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f._enemyBarFill = f:CreateTexture(nil, "ARTWORK")
    f._previewFS = f:CreateFontString(nil, "OVERLAY")
    f._previewFS:SetWordWrap(false)

    -- Hidden until RenderStandalone() shows it
    f:Hide()

    -- Apply saved scale and position immediately so the frame never flashes at default
    if db and db.profile then
        local scale = db.profile.scale or 1.0
        if scale == 0 then scale = 1.0 end
        f:SetScale(scale)
        if db.profile.standalonePos then
            local pos = db.profile.standalonePos
            local cx, cy = pos.centerX, pos.centerY
            if not cx then
                -- Legacy TOPLEFT-stored position; will be migrated to center
                -- on the first ApplyStandalonePosition / drag-save call.
                f:ClearAllPoints()
                f:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "BOTTOMLEFT",
                    pos.x or 0, pos.y or 0)
            else
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", cx / scale, cy / scale)
            end
        end
    end

    standaloneFrame = f
    -- If a run is already active (e.g. /reload mid-key), wire up the
    -- OnUpdate fallback now that the frame exists.
    if _timerLoopWanted then
        _onUpdateAccum = 0
        f:SetScript("OnUpdate", OnUpdateFallback)
    end
    return f
end

local function RenderStandalone()
    if not db or not db.profile.enabled then
        if standaloneFrame then standaloneFrame:Hide() end
        return
    end

    local p = db.profile
    local isPreview = false
    local run = currentRun
    if not run.active and not run.completed then
        if p.showPreview or unlockLayoutActive then
            run = PREVIEW_RUN
            isPreview = true
        else
            if standaloneFrame then standaloneFrame:Hide() end
            return
        end
    end

    local f = CreateStandaloneFrame()
    local PAD = 12
    local ALIGN_PAD = 0
    local TBAR_PAD = 0
    local configuredTimerBarH = p.barHeight or 8
    local expandedH = p.barHeightExpanded or 22
    local TBAR_H = p.timerInBar and max(configuredTimerBarH, expandedH) or configuredTimerBarH
    local ENEMY_BAR_H = p.barHeight or 8
    local ROW_GAP = p.rowGap or 6
    local OBJ_GAP = p.objectiveGap or 4

    f:SetWidth(p.frameWidth or 260)

    -- Scale ownership lives in ApplyStandalonePosition (called from
    -- _EMT_Apply on slider changes). Don't SetScale here -- doing so on
    -- every render can race the anchor and visually shift the frame.
    local alpha = p.standaloneAlpha or 0.85
    f:SetBackdropColor(0.05, 0.04, 0.08, alpha)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, min(alpha, 0.6))

    local aR, aG, aB = GetAccentColor()
    if p.showAccent then
        f._accent:SetColorTexture(aR, aG, aB, 0.9)
        f._accent:Show()
    else
        f._accent:Hide()
    end

    local frameW = f:GetWidth()
    local innerW = frameW - PAD * 2
    local y = -PAD

    -- "Show Key Level on Timer": render "+key  |" to the left of the timer clock.
    -- Gated on the dungeon name being hidden (the title is then just the lone key
    -- level, which relocates onto the timer line). Used by RenderTitleAffixes (to
    -- suppress the now-redundant title) and by the timer block below.
    local keyLevelOnTimer = (p.showKeyLevelOnTimer == true) and (p.showDungeonName == false)

    local function ContentPad(align)
        if align == "LEFT" or align == "RIGHT" then return PAD + ALIGN_PAD end
        return PAD
    end

    local _gAlign = (p.alignAllText == "LEFT") and "LEFT" or "RIGHT"
    local function _ra() return _gAlign end

    local function RenderTitleAffixes()
        local titleAlign = _ra(p.titleAlign or "CENTER")
        local tR, tG, tB
        if p.titleUseAccent ~= false then
            tR, tG, tB = aR, aG, aB
        elseif p.titleColor then
            tR, tG, tB = p.titleColor.r or 1, p.titleColor.g or 1, p.titleColor.b or 1
        else
            tR, tG, tB = 1, 1, 1
        end
        -- When "Show Key Level on Timer" is on (only possible with the dungeon
        -- name hidden), the title would be just the lone "+key" -- that moves down
        -- onto the timer line instead, so suppress the title row entirely here.
        -- keyLevelOnTimer is a function-scope upvalue computed once near the top.
        if p.showTitle ~= false and not keyLevelOnTimer then
            local titleText
            if p.showDungeonName == false then
                -- Show only the key level number, not the dungeon name.
                titleText = format("|cff%02x%02x%02x+%d|r",
                    floor(tR * 255), floor(tG * 255), floor(tB * 255), run.level)
            else
                titleText = format("|cff%02x%02x%02x+%d  %s|r",
                    floor(tR * 255), floor(tG * 255), floor(tB * 255),
                    run.level, run.mapName or "Mythic+")
            end
            f._titleFS:SetJustifyH(titleAlign)
            f._titleFS:SetTextColor(1, 1, 1)
            local titleMax = p.titleSize or 13
            local titleMin = max(8, titleMax - 3)
            SetFittedText(f._titleFS, titleText, innerW, titleMax, titleMin)
            f._titleFS:ClearAllPoints()
            f._titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
            f._titleFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
            f._titleFS:Show()
            local titleH = f._titleFS:GetStringHeight() or titleMax
            y = y - titleH - 2 - ROW_GAP
        else
            f._titleFS:Hide()
        end

        if p.showAffixes then
            local names = {}
            if run._previewAffixNames then
                for _, name in ipairs(run._previewAffixNames) do
                    names[#names + 1] = name
                end
            else
                -- Use the cached affix names snapshotted at StartRun. Falls back
                -- to GetAffixInfo only if cache is missing (run started before
                -- this code path was added, or preview mode).
                for i, id in ipairs(run.affixes) do
                    local name = (run.affixNames and run.affixNames[i])
                        or C_ChallengeMode.GetAffixInfo(id)
                    if name then
                        names[#names + 1] = name
                    end
                end
            end
            if #names > 0 then
                f._affixFS:SetTextColor(GetColor(p.affixTextColor, 1, 1, 1))
                f._affixFS:SetJustifyH(titleAlign)
                local affixMax = p.affixSize or 10
                local affixMin = max(6, affixMax - 2)
                SetFittedText(f._affixFS, table.concat(names, "  \194\183  "), innerW, affixMax, affixMin)
                f._affixFS:ClearAllPoints()
                f._affixFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y + 5)
                f._affixFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y + 5)
                f._affixFS:Show()
                y = y - (f._affixFS:GetStringHeight() or 12) - ROW_GAP + 5
            else
                f._affixFS:Hide()
            end
        else
            f._affixFS:Hide()
        end
    end

    local titleAffixBelowTimer = (p.titleAffixPosition == "BELOW_TIMER")
    local defaultTitleDeathGap = ROW_GAP + 5
    local defaultSandwichGap = ROW_GAP
    if not titleAffixBelowTimer then
        RenderTitleAffixes()
        y = y - ((p.titleAffixDeathGap or defaultTitleDeathGap) - defaultTitleDeathGap)
    end

    -- Deaths (toggle removed; always on when there are deaths)
    if run.deaths > 0 and not p.deathsInTitle then
        local deathAlign = _ra(p.deathAlign or "LEFT")
        local dPad = ContentPad(deathAlign)
        SetFS(f._deathFS, 12)
        ApplyShadow(f._deathFS)
        local dR, dG, dB = GetColor(p.deathTextColor, 0.93, 0.33, 0.33)
        f._deathFS:SetTextColor(dR, dG, dB)
        f._deathFS:SetText(format("%d Death%s  -%s",
            run.deaths, run.deaths ~= 1 and "s" or "", FormatTime(run.deathTimeLost)))
        f._deathFS:ClearAllPoints()
        f._deathFS:SetPoint("TOPLEFT", f, "TOPLEFT", dPad, y - 5)
        f._deathFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -dPad, y - 5)
        f._deathFS:SetJustifyH(deathAlign)
        f._deathFS:Show()
        -- Position hit frame over the actual text, not the full row
        local textW = f._deathFS:GetStringWidth() or 0
        local textH = f._deathFS:GetStringHeight() or 12
        f._deathHit:ClearAllPoints()
        f._deathHit:SetSize(textW, textH)
        if deathAlign == "RIGHT" then
            f._deathHit:SetPoint("TOPRIGHT", f._deathFS, "TOPRIGHT", 0, 0)
        else
            f._deathHit:SetPoint("TOPLEFT", f._deathFS, "TOPLEFT", 0, 0)
        end
        f._deathHit._align = deathAlign
        f._deathHit:Show()
        y = y - (f._deathFS:GetStringHeight() or 12) - ROW_GAP - 5
    else
        f._deathFS:Hide()
        f._deathHit:Hide()
        if titleAffixBelowTimer and not p.deathsInTitle then
            y = y - 12 - ROW_GAP - 5
        end
    end

    -- Timer colours
    local elapsed = run.elapsed or 0
    local maxTime = run.maxTime or 0
    local timeLeft = max(0, maxTime - elapsed)
    local plusTwoT, plusThreeT = CalculateBonusTimers(maxTime, run.affixes)
    local completedElapsed = run.preciseCompletedElapsed or elapsed
    local colorElapsed = run.completed and completedElapsed or elapsed
    local timerBarR, timerBarG, timerBarB
    if p.timerBarStyle == "SEGMENTS" then
        timerBarR, timerBarG, timerBarB = GetTimerSegmentFillColor(p, colorElapsed, plusThreeT, plusTwoT)
    else
        timerBarR, timerBarG, timerBarB = GetTimerBarFillColor(p, colorElapsed, plusThreeT, plusTwoT, maxTime)
    end

    -- Build timer text per user-selected display mode.
    --   REMAINING        -> "11:37"   (or "+OT" when overtime)
    --   REMAINING_TOTAL  -> "11:37 / 33:00"
    --   ELAPSED          -> "21:23"
    --   ELAPSED_DETAIL   -> "21:23 (11:37 / 33:00)"
    local timerText
    local timerDetailText
    if run.completed then
        -- Completed run: freeze the clock at the final elapsed seconds
        -- but preserve the user's chosen display mode so "/33:00" doesn't
        -- vanish on completion.
        local mode = p.timerDisplayMode or "REMAINING_TOTAL"
        local elaStr = FormatTime(run.elapsed or completedElapsed or 0)
        local maxStr = FormatTime(maxTime)
        if mode == "REMAINING_TOTAL" then
            timerText = elaStr .. " / " .. maxStr
        elseif mode == "ELAPSED_DETAIL" then
            timerText = elaStr
            timerDetailText = " (" .. elaStr .. " / " .. maxStr .. ")"
        else
            timerText = elaStr
        end
    else
        local mode = p.timerDisplayMode or "REMAINING_TOTAL"
        local elaStr = FormatTime(elapsed)
        local maxStr = FormatTime(maxTime)
        local remStr = FormatRemaining(maxTime - elapsed)
        if mode == "REMAINING_TOTAL" then
            timerText = elaStr .. " / " .. maxStr
        elseif mode == "ELAPSED" then
            timerText = remStr
        elseif mode == "ELAPSED_DETAIL" then
            timerText = remStr
            timerDetailText = " (" .. elaStr .. " / " .. maxStr .. ")"
        else
            timerText = elaStr
        end
    end

    local tR, tG, tB = 1, 1, 1
    local depleted = (run.completed and completedElapsed > maxTime)
        or ((not run.completed) and timeLeft <= 0 and maxTime > 0)
    if depleted then
        tR, tG, tB = GetColor(p.timerExpiredColor, 0.9, 0.2, 0.2)
    end

    local underBarMode = (p.enemyForcesPos == "UNDER_BAR")

    -- Threshold text
    local _barW_for_thresh = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2)
    if _barW_for_thresh < 60 then _barW_for_thresh = 60 end

    local function RenderThresholdText()
        if p.showTimerBar == false and p.showEnemyBar == false then
            f._threshFS:Hide()
            f._threshFS2:Hide()
            f._threshRemFS:Hide()
            return
        end

        local showRem = p.showThreshRemaining == true
        if (p.showPlusTwoTimer or p.showPlusThreeTimer or showRem) and maxTime > 0 then
            local plusThreeSize = p.thresholdPlusThreeSize or p.thresholdSize or 12
            local plusTwoSize = p.thresholdPlusTwoSize or p.thresholdSize or 12
            local plusOneSize = p.thresholdPlusOneSize or p.thresholdSize or 12
            local thresholdRowSize = max(
                p.showPlusThreeTimer and plusThreeSize or 0,
                p.showPlusTwoTimer and plusTwoSize or 0,
                showRem and plusOneSize or 0,
                12
            )

            local function buildLabel(threshTime, color)
                local diff = threshTime - elapsed
                if diff >= 0 then
                    local cR, cG, cB = GetColor(color, 0.3, 0.8, 1)
                    return format("|cff%02x%02x%02x%s|r",
                        floor(cR * 255), floor(cG * 255), floor(cB * 255), FormatTime(diff))
                end
                return format("|cff999999%s|r", FormatTime(threshTime))
            end

            local segmentedThresholds = (p.timerBarStyle == "SEGMENTS")
            local segmentGap = segmentedThresholds and max(0, p.timerBarSegmentGap or 2) or 0
            local plusThreeLabelX = max(0, min(_barW_for_thresh, _barW_for_thresh * (plusThreeT / maxTime) - segmentGap / 2))
            local plusTwoLabelX = max(0, min(_barW_for_thresh, _barW_for_thresh * (plusTwoT / maxTime) - segmentGap / 2))
            local thresholdAnchorBar = f._barBg
            if underBarMode and p.showTimerBar == false and p.showEnemyBar ~= false then
                thresholdAnchorBar = f._enemyBarBg
            end

            -- Anchor a FontString at bar-local x = cx in the threshold row.
            -- In segmented mode, +2/+3 labels right-align to segment ends.
            local function placeAt(fs, cx, rightJustified, offsetX, offsetY)
                local offX = offsetX
                local offY = offsetY
                if offX == nil then offX = p.thresholdTextOffsetX or 0 end
                if offY == nil then offY = p.thresholdTextOffsetY or 0 end
                local aboveBar = underBarMode or segmentedThresholds
                local point
                if rightJustified then
                    point = aboveBar and "BOTTOMRIGHT" or "TOPRIGHT"
                else
                    point = aboveBar and "BOTTOM" or "TOP"
                end
                -- Justify to the anchored edge so the pinned width leaves the
                -- fixed edge steady: right-anchored labels keep their right edge on
                -- the segment/bar end; center-anchored labels align left inside a
                -- box centered on the tick (near-centered, but the digits no longer
                -- shift as the seconds tick, since the widest-digit pin keeps the
                -- box a couple px wider than the live text).
                fs:SetJustifyH(rightJustified and "RIGHT" or "LEFT")
                fs:ClearAllPoints()
                if aboveBar then
                    -- threshold rendered before the bar -> sit above the bar
                    fs:SetPoint(point, thresholdAnchorBar, "TOPLEFT", cx + offX, 2 + offY)
                else
                    -- threshold rendered after the bar -> sit below the bar
                    fs:SetPoint(point, thresholdAnchorBar, "BOTTOMLEFT", cx + offX, -2 + offY)
                end
            end

            -- Prepare each visible FontString (text + style) up front. Each is
            -- pinned to a jitter-free width via SetThreshText; the returned widths
            -- feed the remaining-mode overlap packing below (in place of a live,
            -- per-second GetStringWidth that would make the packing shift too).
            local threshW3, threshW2, threshWr = 0, 0, 0
            if p.showPlusThreeTimer then
                SetFS(f._threshFS, plusThreeSize)
                ApplyShadow(f._threshFS)
                f._threshFS:SetTextColor(1, 1, 1)
                local c1r, c1g, c1b = GetTimerSegmentTextColor(p, 1)
                threshW3 = SetThreshText(f._threshFS, buildLabel(plusThreeT, { r = c1r, g = c1g, b = c1b }))
            end
            if p.showPlusTwoTimer then
                SetFS(f._threshFS2, plusTwoSize)
                ApplyShadow(f._threshFS2)
                f._threshFS2:SetTextColor(1, 1, 1)
                local c2r, c2g, c2b = GetTimerSegmentTextColor(p, 2)
                threshW2 = SetThreshText(f._threshFS2, buildLabel(plusTwoT, { r = c2r, g = c2g, b = c2b }))
            end
            if showRem then
                SetFS(f._threshRemFS, plusOneSize)
                ApplyShadow(f._threshRemFS)
                -- Same single MM:SS as the timer's text, showing time left in
                -- the key. In the default TICKS style it inherits the main timer
                -- color so it reddens on depletion just like the big clock (legacy
                -- behavior); the new SEGMENTS style colors it to match segment 3,
                -- and the per-row "white" toggle still forces white.
                if p.timerBarStyle == "SEGMENTS" then
                    f._threshRemFS:SetTextColor(GetTimerSegmentTextColor(p, 3))
                elseif p.thresholdPlusOneTextWhite == true then
                    f._threshRemFS:SetTextColor(1, 1, 1)
                else
                    f._threshRemFS:SetTextColor(tR, tG, tB)
                end
                threshWr = SetThreshText(f._threshRemFS, FormatRemaining(maxTime - elapsed))
            end

            if not showRem then
                -- Each threshold text sits on its tick/segment boundary.
                if p.showPlusThreeTimer then
                    placeAt(f._threshFS, segmentedThresholds and plusThreeLabelX or (_barW_for_thresh * (plusThreeT / maxTime)), segmentedThresholds, p.thresholdPlusThreeTextOffsetX, p.thresholdPlusThreeTextOffsetY)
                    f._threshFS:Show()
                else
                    f._threshFS:Hide()
                end
                if p.showPlusTwoTimer then
                    placeAt(f._threshFS2, segmentedThresholds and plusTwoLabelX or (_barW_for_thresh * (plusTwoT / maxTime)), segmentedThresholds, p.thresholdPlusTwoTextOffsetX, p.thresholdPlusTwoTextOffsetY)
                    f._threshFS2:Show()
                else
                    f._threshFS2:Hide()
                end
                f._threshRemFS:Hide()
            else
                if segmentedThresholds then
                    if p.showPlusThreeTimer then
                        placeAt(f._threshFS, plusThreeLabelX, true, p.thresholdPlusThreeTextOffsetX, p.thresholdPlusThreeTextOffsetY)
                        f._threshFS:Show()
                    else
                        f._threshFS:Hide()
                    end
                    if p.showPlusTwoTimer then
                        placeAt(f._threshFS2, plusTwoLabelX, true, p.thresholdPlusTwoTextOffsetX, p.thresholdPlusTwoTextOffsetY)
                        f._threshFS2:Show()
                    else
                        f._threshFS2:Hide()
                    end
                    placeAt(f._threshRemFS, _barW_for_thresh, true, p.thresholdPlusOneTextOffsetX, p.thresholdPlusOneTextOffsetY)
                    f._threshRemFS:Show()
                    y = y - thresholdRowSize - ROW_GAP
                    return
                end

                -- Remaining text pinned flush to the bar's right edge; the
                -- +2/+3 texts prefer their tick centers but are nudged left as
                -- needed so none of the three ever overlap. Packed right to
                -- left with a small gap, clamped to the bar's left edge.
                local GAP = 0
                local barW = _barW_for_thresh
                -- Visible set, left to right (plusThree < plusTwo < bar end).
                local entries = {}
                if p.showPlusThreeTimer then
                    entries[#entries + 1] = { fs = f._threshFS, w = threshW3,
                        center = barW * (plusThreeT / maxTime) }
                else
                    f._threshFS:Hide()
                end
                if p.showPlusTwoTimer then
                    entries[#entries + 1] = { fs = f._threshFS2, w = threshW2,
                        center = barW * (plusTwoT / maxTime) }
                else
                    f._threshFS2:Hide()
                end
                -- Use the pinned width (not a live GetStringWidth) so the right-edge
                -- pin and the overlap packing stay put as the seconds tick.
                local remW = threshWr
                entries[#entries + 1] = { fs = f._threshRemFS, w = remW,
                    center = barW - remW / 2, pinRight = true }

                -- Right-to-left: each text's right edge must clear the next
                -- text's left edge (minus GAP). Only shift left, never right,
                -- so tick-aligned texts stay put when there is room.
                local limit  -- max allowed right edge for the current text
                for i = #entries, 1, -1 do
                    local e = entries[i]
                    local half = e.w / 2
                    if (not e.pinRight) and limit then
                        local right = e.center + half
                        if right > limit then e.center = limit - half end
                    end
                    if e.center - half < 0 then e.center = half end  -- clamp to left edge
                    limit = (e.center - half) - GAP
                end

                for _, e in ipairs(entries) do
                    local rightJustified = segmentedThresholds or e.pinRight
                    local anchorX = rightJustified and (e.center + e.w / 2) or e.center
                    local offX, offY
                    if e.fs == f._threshFS then
                        offX, offY = p.thresholdPlusThreeTextOffsetX, p.thresholdPlusThreeTextOffsetY
                    elseif e.fs == f._threshFS2 then
                        offX, offY = p.thresholdPlusTwoTextOffsetX, p.thresholdPlusTwoTextOffsetY
                    elseif e.fs == f._threshRemFS then
                        offX, offY = p.thresholdPlusOneTextOffsetX, p.thresholdPlusOneTextOffsetY
                    end
                    placeAt(e.fs, anchorX, rightJustified, offX, offY)
                    e.fs:Show()
                end
            end

            -- Reserve vertical space for the threshold row (height + gap).
            y = y - thresholdRowSize - ROW_GAP
        else
            f._threshFS:Hide()
            f._threshFS2:Hide()
            f._threshRemFS:Hide()
        end
    end

    -- Enemy forces
    local function RenderEnemyForces()
        if p.showEnemyBar == false then
            f._enemyFS:Hide()
            f._enemyBarBg:Hide()
            f._enemyBarFill:Hide()
            if f._enemyBarText then f._enemyBarText:Hide() end
            return
        end

        -- Use cached ref (set by UpdateObjectives) instead of re-finding
        -- the weighted objective on every render.
        local enemyObj = run._weightedObj
        if not enemyObj then
            for _, obj in ipairs(run.objectives) do
                if obj.isWeighted then enemyObj = obj; break end
            end
        end
        if not enemyObj then
            f._enemyFS:Hide(); f._enemyBarBg:Hide(); f._enemyBarFill:Hide()
            if f._enemyBarText then f._enemyBarText:Hide() end
            return
        end

        local objAlign = _ra(p.objectiveAlign or "LEFT")
        local ePad = ContentPad(objAlign)
        local pctRaw = min(100, max(0, enemyObj.quantity))
        local pctPos = p.enemyForcesPctPos or "LABEL"
        local showEnemyText = p.showEnemyText ~= false

        local enemyTextFormat = p.enemyForcesTextFormat or "PERCENT"
        local hideLabel = p.hideEnemyForcesLabel == true
        local label
        if pctPos == "LABEL" then
            -- compact=true skips the " Enemy Forces" suffix baked into
            -- FormatEnemyForcesText, so percent/count text shows alone.
            label = FormatEnemyForcesText(enemyObj, enemyTextFormat, hideLabel)
        elseif hideLabel then
            label = ""
        else
            label = "Enemy Forces"
        end

        local enemyTextSize = p.enemyForcesTextSize or p.objectivesSize or 12
        SetFS(f._enemyFS, enemyTextSize)
        ApplyShadow(f._enemyFS)
        if enemyObj.completed then
            f._enemyFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
        else
            f._enemyFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
        end
        f._enemyFS:SetText(label)
        if hideLabel and pctPos ~= "LABEL" then
            f._enemyFS:Hide()
        else
            f._enemyFS:Show()
        end

        local function RenderEnemyBar()
            local besideRoom = (not enemyObj.completed and pctPos == "BESIDE") and 62 or 0
            local barW = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2) - besideRoom
            if barW < 60 then barW = 60 end
            f._enemyBarBg:ClearAllPoints()
            if objAlign == "RIGHT" then
                f._enemyBarBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + TBAR_PAD), y)
            elseif objAlign == "CENTER" then
                f._enemyBarBg:SetPoint("TOP", f, "TOP", 0, y)
            else
                f._enemyBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + TBAR_PAD, y)
            end
            f._enemyBarBg:SetSize(barW, ENEMY_BAR_H)
            ApplyBarTexture(f._enemyBarBg, p.enemyBarBgTexture, 0.12, 0.12, 0.12, 0.9)
            f._enemyBarBg:Show()

            local eR, eG, eB
            if enemyObj.completed then
                eR, eG, eB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
            elseif p.enemyBarUseAccent ~= false then
                eR, eG, eB = GetAccentColor()
            else
                eR, eG, eB = GetColor(p.enemyBarColor, 0.35, 0.55, 0.8)
            end

            local epct = enemyObj.completed and 1 or min(1, max(0, pctRaw / 100))
            local eFillW = max(1, barW * epct)
            f._enemyBarFill:ClearAllPoints()
            f._enemyBarFill:SetPoint("TOPLEFT", f._enemyBarBg, "TOPLEFT", 0, 0)
            f._enemyBarFill:SetSize(eFillW, ENEMY_BAR_H)
            ApplyBarTexture(f._enemyBarFill, p.enemyBarTexture, eR, eG, eB, 0.8)
            f._enemyBarFill:Show()

            if not f._enemyBarText then
                f._enemyBarText = f:CreateFontString(nil, "OVERLAY")
                f._enemyBarText:SetParent(f._emtTextLayer)
                f._enemyBarText:SetWordWrap(false)
            end
            if pctPos == "BAR" then
                SetFS(f._enemyBarText, enemyTextSize)
                ApplyShadow(f._enemyBarText)
                -- In-bar percent is always white for readability over the
                -- accent-filled bar regardless of completion / user colors.
                f._enemyBarText:SetTextColor(1, 1, 1)
                f._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                f._enemyBarText:ClearAllPoints()
                f._enemyBarText:SetPoint("CENTER", f._enemyBarBg, "CENTER", 0, 0)
                f._enemyBarText:Show()
            elseif pctPos == "BESIDE" then
                SetFS(f._enemyBarText, enemyTextSize)
                ApplyShadow(f._enemyBarText)
                if enemyObj.completed then
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                f._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                f._enemyBarText:ClearAllPoints()
                if objAlign == "RIGHT" then
                    f._enemyBarText:SetPoint("RIGHT", f._enemyBarBg, "LEFT", -4, 0)
                else
                    f._enemyBarText:SetPoint("LEFT", f._enemyBarBg, "RIGHT", 4, 0)
                end
                f._enemyBarText:Show()
            else
                f._enemyBarText:Hide()
            end

            y = y - ENEMY_BAR_H - ROW_GAP
        end

        local function RenderEnemyLabel()
            if not showEnemyText then
                f._enemyFS:Hide()
                return
            end
            -- In under-bar mode, lift the enemy text up 2px to sit closer to the bar.
            local labelX = p.enemyForcesTextOffsetX or 0
            local labelY = (underBarMode and (y + 2) or y) + (p.enemyForcesTextOffsetY or 0)
            f._enemyFS:ClearAllPoints()
            f._enemyFS:SetPoint("TOPLEFT", f, "TOPLEFT", ePad + labelX, labelY)
            f._enemyFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -ePad + labelX, labelY)
            f._enemyFS:SetJustifyH(objAlign)
            f._enemyFS:Show()
            local trailingGap = underBarMode and (4 - 2 + 5) or 4
            y = y - (f._enemyFS:GetStringHeight() or 12) - trailingGap
        end

        if underBarMode then
            RenderEnemyBar()
            RenderEnemyLabel()
        else
            RenderEnemyLabel()
            RenderEnemyBar()
        end
    end

    -- Timer text (with optional inline detail rendered as one combined block)
    if not p.timerInBar then
        local timerAlign = _ra(p.timerAlign or "CENTER")
        SetTimerFS(f._timerFS, p.timerTextSize or 20)
        ApplyShadow(f._timerFS)
        f._timerFS:SetTextColor(tR, tG, tB)
        SetTextDiff(f._timerFS, timerText)
        if timerAlign == "RIGHT" then
            f._timerFS:SetJustifyH("RIGHT")
        else
            f._timerFS:SetJustifyH("LEFT")
        end
        f._timerFS:ClearAllPoints()
        -- Pin a constant width so the timer doesn't wobble as digits change (a
        -- proportional font makes "1" narrower than "8"). We measure a worst-case
        -- template ("99:99 / 99:99") once per format and reuse it. The font path
        -- and outline flags are part of the key: without them a late font swap
        -- (LibSharedMedia load, "Apply to All Game Text", a heavier font) leaves
        -- the width pinned to the old, narrower measurement and the engine
        -- ellipsizes the overflow (e.g. "33:00" -> "33:...").
        local _timerSz = p.timerTextSize or 20
        local _fScale = f:GetEffectiveScale() or 1
        local _fPath, _, _fFlags = f._timerFS:GetFont()
        local _mainKey = #(timerText or "") .. "|" .. _timerSz .. "|" .. string.format("%.3f", _fScale)
            .. "|" .. (_fPath or "") .. "|" .. (_fFlags or "")
        if f._timerFS._lastLen ~= _mainKey then
            f._timerFS._lastLen = _mainKey
            -- Worst-case template using the WIDEST digit in the CURRENT font, not a
            -- hardcoded "9": decorative / oldstyle numeral fonts can make another
            -- digit (e.g. "0" or "3") wider than "9", so a "9" template under-measures
            -- and the live clock (e.g. "33:00") gets ellipsized. Once per key change.
            local templ = (timerText or ""):gsub("%d", WidestDigitChar(f._timerFS))
            f._timerFS:SetText(templ)
            -- Keep the SetTextDiff cache in sync with what we just wrote
            -- directly. Otherwise the cache still reflects the previous
            -- timerText, so the restore call below short-circuits and
            -- the "99:99" template stays visible (bug seen during the
            -- 10-second pre-start window where elapsed stays at 0).
            f._timerFS._lastText = templ
            -- Clear any previously pinned width BEFORE measuring. With wrap off,
            -- GetStringWidth() returns a value CLAMPED to the current width whenever
            -- the text is being truncated -- so if the box needs to GROW (bigger
            -- timer font, a heavier font finishing load, or the clock gaining a
            -- character in overtime, e.g. "-00:01"), measuring against the old,
            -- narrower pinned width yields a too-small result that then stays
            -- truncated for the rest of the run. Matches the objective-row pattern
            -- (SetWidth(0) before GetStringWidth) used later in this file.
            f._timerFS:SetWidth(0)
            -- +3px safety margin: subpixel rounding at fractional UI scales can
            -- otherwise clip the rightmost glyph and force a wrap.
            f._timerFS:SetWidth((f._timerFS:GetStringWidth() or 0) + 3)
            SetTextDiff(f._timerFS, timerText)
        end

        -- Optional "+key  |" prefix to the left of the timer clock. keyExtra is the
        -- horizontal room it needs on the left; the timer group is shifted right by
        -- keyExtra (LEFT align) or keyExtra/2 (CENTER) so the whole "+21 | timer"
        -- block stays aligned, and is left untouched (flush right, growing left) for
        -- RIGHT align. Single-anchored with no explicit width, so it never truncates.
        local keyExtra, keySpacing = 0, 0
        if keyLevelOnTimer then
            SetTimerFS(f._keyLevelFS, _timerSz)
            ApplyShadow(f._keyLevelFS)
            -- Title identity color (accent / custom / white) so it does not turn red
            -- alongside the timer on depletion.
            local klR, klG, klB
            if p.titleUseAccent ~= false then
                klR, klG, klB = aR, aG, aB
            elseif p.titleColor then
                klR, klG, klB = p.titleColor.r or 1, p.titleColor.g or 1, p.titleColor.b or 1
            else
                klR, klG, klB = 1, 1, 1
            end
            f._keyLevelFS:SetTextColor(klR, klG, klB)
            f._keyLevelFS:SetJustifyH("LEFT")
            f._keyLevelFS:SetWidth(0)
            -- "||" renders as a single literal pipe ("|" is WoW's escape introducer).
            SetTextDiff(f._keyLevelFS, format("+%d  ||", run.level))
            keySpacing = p.keyLevelTimerSpacing or 8
            keyExtra = (f._keyLevelFS:GetStringWidth() or 0) + keySpacing
        end

        if timerDetailText then
            local _mode = (not run.completed) and (p.timerDisplayMode or "REMAINING_TOTAL") or nil
            local detailSize = (_mode == "REMAINING_TOTAL") and 20 or 12
            SetTimerFS(f._timerDetailFS, detailSize)
            ApplyShadow(f._timerDetailFS)
            f._timerDetailFS:SetTextColor(1, 1, 1)
            f._timerDetailFS:SetText(timerDetailText)
            if timerAlign == "RIGHT" then
                f._timerDetailFS:SetJustifyH("RIGHT")
            else
                f._timerDetailFS:SetJustifyH("LEFT")
            end
            f._timerDetailFS:ClearAllPoints()
            -- Cache key includes font size, scale, and font (path + flags):
            -- switching modes (12pt detail <-> 20pt detail) or a late font swap
            -- must re-measure the templatized width, else the larger/wider
            -- glyphs get clipped and the detail vanishes.
            local _detScale = f:GetEffectiveScale() or 1
            local _detPath, _, _detFlags = f._timerDetailFS:GetFont()
            local _detKey = #timerDetailText .. "|" .. detailSize .. "|" .. string.format("%.3f", _detScale)
                .. "|" .. (_detPath or "") .. "|" .. (_detFlags or "")
            if f._timerDetailFS._lastKey ~= _detKey then
                f._timerDetailFS._lastKey = _detKey
                local templ = timerDetailText:gsub("%d", WidestDigitChar(f._timerDetailFS))
                f._timerDetailFS:SetText(templ)
                -- Clear the pinned width first so GetStringWidth returns the true
                -- unbounded width, not one clamped to a previous, narrower pin (see
                -- the main-timer measurement above for the full explanation).
                f._timerDetailFS:SetWidth(0)
                f._timerDetailFS:SetWidth((f._timerDetailFS:GetStringWidth() or 0) + 3)
                f._timerDetailFS:SetText(timerDetailText)
            end

            local gap = 4
            local detailW = f._timerDetailFS:GetStringWidth() or 0
            if timerAlign == "RIGHT" then
                -- Main timer flush right; detail sits to the LEFT of main.
                f._timerFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + ALIGN_PAD), y)
                f._timerDetailFS:SetPoint("BOTTOMRIGHT", f._timerFS, "BOTTOMLEFT", -gap, 4)
            elseif timerAlign == "LEFT" then
                f._timerFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ALIGN_PAD + keyExtra, y)
                f._timerDetailFS:SetPoint("BOTTOMLEFT", f._timerFS, "BOTTOMRIGHT", gap, 4)
            else
                f._timerFS:SetPoint("TOP", f, "TOP", -(detailW + gap) / 2 + keyExtra / 2, y)
                f._timerDetailFS:SetPoint("BOTTOMLEFT", f._timerFS, "BOTTOMRIGHT", gap, 4)
            end
            f._timerDetailFS:Show()
            -- Key prefix sits left of the leftmost timer element (the detail, when
            -- it is on the left for RIGHT align; otherwise the main clock).
            if keyLevelOnTimer then
                local leftmost = (timerAlign == "RIGHT") and f._timerDetailFS or f._timerFS
                f._keyLevelFS:ClearAllPoints()
                f._keyLevelFS:SetPoint("BOTTOMRIGHT", leftmost, "BOTTOMLEFT", -keySpacing, 0)
                f._keyLevelFS:Show()
            else
                f._keyLevelFS:Hide()
            end
        else
            if timerAlign == "RIGHT" then
                f._timerFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + ALIGN_PAD), y)
            elseif timerAlign == "LEFT" then
                f._timerFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ALIGN_PAD + keyExtra, y)
            else
                f._timerFS:SetPoint("TOP", f, "TOP", keyExtra / 2, y)
            end
            f._timerDetailFS:Hide()
            -- Key prefix immediately left of the clock, separated by the spacing.
            if keyLevelOnTimer then
                f._keyLevelFS:ClearAllPoints()
                f._keyLevelFS:SetPoint("BOTTOMRIGHT", f._timerFS, "BOTTOMLEFT", -keySpacing, 0)
                f._keyLevelFS:Show()
            else
                f._keyLevelFS:Hide()
            end
        end

        f._timerFS:Show()
        local timerH = f._timerFS:GetStringHeight() or 20
        if timerH < 20 then timerH = 20 end
        y = y - timerH - ROW_GAP
    else
        f._timerFS:Hide()
        f._timerDetailFS:Hide()
        -- In-bar mode: the key level is folded into the bar text (below), so the
        -- standalone prefix string is not used.
        f._keyLevelFS:Hide()
    end

    if titleAffixBelowTimer then
        local timerGap = p.titleAffixTimerGap or p.titleAffixSandwichGap or defaultSandwichGap
        local barGap = p.titleAffixBarGap or p.titleAffixSandwichGap or defaultSandwichGap
        if p.timerInBar then
            y = y - timerGap
        else
            y = y - (timerGap - defaultSandwichGap)
        end
        RenderTitleAffixes()
        y = y - (barGap - defaultSandwichGap)
    end

    if underBarMode then
        RenderThresholdText()
    end

    -- Timer bar
    if maxTime > 0 and p.showTimerBar ~= false then
        local barW = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2)
        if barW < 60 then barW = 60 end

        f._barBg:ClearAllPoints()
        local _barAlign = _ra(p.timerAlign or "CENTER")
        if _barAlign == "RIGHT" then
            f._barBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + TBAR_PAD), y)
        elseif _barAlign == "LEFT" then
            f._barBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + TBAR_PAD, y)
        else
            f._barBg:SetPoint("TOP", f, "TOP", 0, y)
        end
        f._barBg:SetSize(barW, TBAR_H)
        ApplyBarTexture(f._barBg, p.barBgTexture, 0.12, 0.12, 0.12, 0.9)
        f._barBg:SetAlpha(1)
        f._barBg:Show()

        local fillPct = min(1, elapsed / maxTime)
        local fillW = max(1, barW * fillPct)
        f._barFill:ClearAllPoints()
        f._barFill:SetPoint("TOPLEFT", f._barBg, "TOPLEFT", 0, 0)
        f._barFill:SetSize(fillW, TBAR_H)
        local _fillA = p.timerInBar and (p.barFillAlphaExpanded or 0.85) or 0.85
        ApplyBarTexture(f._barFill, p.barTexture, timerBarR, timerBarG, timerBarB, _fillA)
        f._barFill:Show()

        -- Pixel-perfect 2-physical-pixel tick markers and segment boundaries.
        local _PP = EllesmereUI and EllesmereUI.PP
        local _es = f:GetEffectiveScale()
        local _tickW = _PP and _PP.SnapForES(2, _es) or 2
        local function _snap(v) return _PP and _PP.SnapForES(v, _es) or v end

        local function HideTimerSegments()
            if f._timerSegBgs then
                for _, tex in ipairs(f._timerSegBgs) do tex:Hide() end
            end
            if f._timerSegFills then
                for _, tex in ipairs(f._timerSegFills) do tex:Hide() end
            end
        end

        local function EnsureTimerSegments()
            f._timerSegBgs = f._timerSegBgs or {}
            f._timerSegFills = f._timerSegFills or {}
            for i = 1, 3 do
                if not f._timerSegBgs[i] then
                    f._timerSegBgs[i] = f:CreateTexture(nil, "BACKGROUND", nil, 1)
                end
                if not f._timerSegFills[i] then
                    f._timerSegFills[i] = f:CreateTexture(nil, "ARTWORK")
                end
            end
        end

        local barStyle = p.timerBarStyle or "TICKS"
        if barStyle == "SEGMENTS" then
            EnsureTimerSegments()
            f._barBg:SetAlpha(0)
            f._barFill:Hide()
            f._seg3:Hide()
            f._seg2:Hide()

            -- Physical-pixel-perfect gaps, the same way ticks are: snap the gap
            -- WIDTH to a whole number of physical pixels, snap each boundary
            -- center, then derive the far gap edge as nearEdge + gapW so every
            -- gap is exactly gapW physical pixels wide (no independent-snap drift).
            local gapW = _snap(max(0, p.timerBarSegmentGap or 2))
            local b3 = _snap(barW * (plusThreeT / maxTime))
            local b2 = _snap(barW * (plusTwoT / maxTime))
            local g3L = _snap(b3 - gapW / 2); local g3R = g3L + gapW
            local g2L = _snap(b2 - gapW / 2); local g2R = g2L + gapW
            local segs = {
                { x1 = 0,    x2 = g3L,  t1 = 0,          t2 = plusThreeT },
                { x1 = g3R,  x2 = g2L,  t1 = plusThreeT, t2 = plusTwoT },
                { x1 = g2R,  x2 = barW, t1 = plusTwoT,   t2 = maxTime },
            }
            for i, seg in ipairs(segs) do
                local x1 = max(0, min(barW, seg.x1))
                local x2v = max(0, min(barW, seg.x2))
                local w = x2v - x1
                if w < 1 then w = 1 end

                local bg = f._timerSegBgs[i]
                bg:ClearAllPoints()
                bg:SetPoint("TOPLEFT", f._barBg, "TOPLEFT", x1, 0)
                bg:SetSize(w, TBAR_H)
                ApplyBarTexture(bg, p.barBgTexture, 0.12, 0.12, 0.12, 0.9)
                bg:Show()

                local segDur = max(1, seg.t2 - seg.t1)
                local segPct = min(1, max(0, (elapsed - seg.t1) / segDur))
                local fill = f._timerSegFills[i]
                fill:ClearAllPoints()
                fill:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
                fill:SetSize(max(1, w * segPct), TBAR_H)
                ApplyBarTexture(fill, p.barTexture, timerBarR, timerBarG, timerBarB, _fillA)
                if segPct > 0 then fill:Show() else fill:Hide() end
            end
        else
            HideTimerSegments()
        end

        local tickA = p.tickAlpha or 1
        local whiteTicks = p.tickWhite == true
        local tickR, tickG, tickB = GetColor(p.timerTickColor, 1, 1, 1)

        if barStyle == "SEGMENTS" then
            f._seg3:Hide()
            f._seg2:Hide()
        else
            f._seg3:ClearAllPoints()
            f._seg3:SetSize(_tickW, TBAR_H)
            f._seg3:SetPoint("TOPLEFT", f._barBg, "TOPLEFT", _snap(barW * (plusThreeT / maxTime)) - _tickW / 2, 0)
            if p.timerTickColor or whiteTicks or elapsed > plusThreeT then
                f._seg3:SetColorTexture(tickR, tickG, tickB, tickA)
            else
                f._seg3:SetColorTexture(0.4, 1, 0.4, tickA)
            end
            f._seg3:Show()

            f._seg2:ClearAllPoints()
            f._seg2:SetSize(_tickW, TBAR_H)
            f._seg2:SetPoint("TOPLEFT", f._barBg, "TOPLEFT", _snap(barW * (plusTwoT / maxTime)) - _tickW / 2, 0)
            if p.timerTickColor or whiteTicks or elapsed > plusTwoT then
                f._seg2:SetColorTexture(tickR, tickG, tickB, tickA)
            else
                f._seg2:SetColorTexture(0.3, 0.8, 1, tickA)
            end
            f._seg2:Show()
        end

        if p.timerInBar then
            if not f._barTimerFS then
                f._barTimerFS = f:CreateFontString(nil, "OVERLAY")
                f._barTimerFS:SetParent(f._emtTextLayer)
                f._barTimerFS:SetWordWrap(false)
            end
            SetTimerFS(f._barTimerFS, 12)
            ApplyShadow(f._barTimerFS)
            local btc = p.timerBarTextColor
            if btc then
                f._barTimerFS:SetTextColor(btc.r or 1, btc.g or 1, btc.b or 1)
            else
                f._barTimerFS:SetTextColor(tR, tG, tB)
            end
            local barTimerText = timerText
            if timerDetailText then
                barTimerText = timerText .. timerDetailText
            end
            -- In-bar mode folds the "+key  |" prefix inline (the pixel Spacing
            -- slider only applies to the standalone, non-in-bar clock).
            if keyLevelOnTimer then
                barTimerText = format("+%d  ||  ", run.level) .. barTimerText
            end
            SetTextDiff(f._barTimerFS, barTimerText)
            f._barTimerFS:ClearAllPoints()
            if p.timerInBarLeftText then
                f._barTimerFS:SetPoint("LEFT", f._barBg, "LEFT", 5, 0)
            else
                f._barTimerFS:SetPoint("CENTER", f._barBg, "CENTER", 0, 0)
            end
            f._barTimerFS:Show()
        elseif f._barTimerFS then
            f._barTimerFS:Hide()
        end

        y = y - TBAR_H - ROW_GAP - 2
    else
        f._barBg:Hide(); f._barFill:Hide()
        f._seg3:Hide(); f._seg2:Hide()
        if f._timerSegBgs then
            for _, tex in ipairs(f._timerSegBgs) do tex:Hide() end
        end
        if f._timerSegFills then
            for _, tex in ipairs(f._timerSegFills) do tex:Hide() end
        end
        if f._barTimerFS then f._barTimerFS:Hide() end
    end

    if underBarMode then
        RenderEnemyForces()
    end

    if not underBarMode then
        RenderThresholdText()
    end

    -- Objectives
    local objIdx = 0
    if p.showObjectives then
        local objAlign = _ra(p.objectiveAlign or "LEFT")
        local oPad = ContentPad(objAlign)
        for i, obj in ipairs(run.objectives) do
            if not obj.isWeighted then
                objIdx = objIdx + 1
                local entry = GetObjRow(f, objIdx)
                local nameFS, timeFS = entry.name, entry.time
                local objSize = p.objectivesSize or 12
                SetFS(nameFS, objSize)
                ApplyShadow(nameFS)
                SetFS(timeFS, objSize)
                ApplyShadow(timeFS)

                local displayName = StripDefeated(obj.name) or ("Objective " .. i)
                if obj.totalQuantity and obj.totalQuantity > 1 then
                    displayName = format("%d/%d %s", obj.quantity or 0, obj.totalQuantity, displayName)
                end
                if obj.completed then
                    nameFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    nameFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                local timeStr = ""
                if p.showObjectiveTimes ~= false and obj.completed and obj.elapsed and obj.elapsed > 0 then
                    local cR, cG, cB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
                    timeStr = format("|cff%02x%02x%02x%s|r",
                        floor(cR * 255), floor(cG * 255), floor(cB * 255), FormatTime(obj.elapsed))
                end
                local compareSuffix = ""
                if obj.completed and obj.referenceElapsed then
                    compareSuffix = BuildSplitCompareText(obj.referenceElapsed, obj.elapsed, p.objectiveCompareDeltaOnly, p.splitFasterColor, p.splitSlowerColor)
                elseif (not obj.completed) and p.showUpcomingSplitTargets and (p.objectiveCompareMode or COMPARE_NONE) ~= COMPARE_NONE then
                    local target = GetReferenceObjectiveTime(run, i, p.objectiveCompareMode or COMPARE_NONE)
                    if target then
                        compareSuffix = "  |cff888888PB " .. FormatTime(target) .. "|r"
                    end
                end
                -- Timer/split text uses its own FontString (never truncated).
                -- Boss name uses the remaining width (truncated with "..." by
                -- WoW's engine if it exceeds the remaining width). No string
                -- reads required -- SetWidth + SetWordWrap(false) handles
                -- truncation at the C++ level, safe for secret values.
                local splitText = timeStr
                if splitText ~= "" and compareSuffix ~= "" then
                    splitText = splitText .. compareSuffix
                elseif compareSuffix ~= "" then
                    splitText = compareSuffix:gsub("^%s+", "")
                end
                local oInnerW = frameW - oPad * 2
                local timeOnLeft = (p.objectiveTimePosition == "LEFT")
                local splitGap = 4
                local objTextX = p.objectiveTextOffsetX or 0
                local objTextY = p.objectiveTextOffsetY or 0
                local objY = y + objTextY
                nameFS:ClearAllPoints()
                timeFS:ClearAllPoints()
                nameFS:SetText(displayName)
                if splitText ~= "" then
                    timeFS:SetText(splitText)
                    timeFS:SetTextColor(1, 1, 1, 1)
                    timeFS:SetWidth(0)
                    local timeW = timeFS:GetStringWidth() or 0
                    local nameMaxW = oInnerW - timeW - splitGap
                    if nameMaxW < 20 then nameMaxW = 20 end
                    nameFS:SetWidth(0)
                    local nameW = nameFS:GetStringWidth() or 0
                    if nameW > nameMaxW then nameW = nameMaxW end
                    if nameW < 20 then nameW = 20 end
                    nameFS:SetWidth(nameW)
                    if timeOnLeft then
                        if objAlign == "RIGHT" then
                            nameFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad + objTextX, objY)
                            timeFS:SetPoint("TOPRIGHT", nameFS, "TOPLEFT", -splitGap, 0)
                        elseif objAlign == "CENTER" then
                            local groupW = timeW + splitGap + nameW
                            timeFS:SetPoint("TOP", f, "TOP", objTextX - (groupW - timeW) / 2, objY)
                            nameFS:SetPoint("TOPLEFT", timeFS, "TOPRIGHT", splitGap, 0)
                        else
                            timeFS:SetPoint("TOPLEFT", f, "TOPLEFT", oPad + objTextX, objY)
                            nameFS:SetPoint("TOPLEFT", timeFS, "TOPRIGHT", splitGap, 0)
                        end
                    else
                        if objAlign == "RIGHT" then
                            timeFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad + objTextX, objY)
                            nameFS:SetPoint("TOPRIGHT", timeFS, "TOPLEFT", -splitGap, 0)
                        elseif objAlign == "CENTER" then
                            local groupW = nameW + splitGap + timeW
                            nameFS:SetPoint("TOP", f, "TOP", objTextX - (groupW - nameW) / 2, objY)
                            timeFS:SetPoint("TOPLEFT", nameFS, "TOPRIGHT", splitGap, 0)
                        else
                            nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", oPad + objTextX, objY)
                            timeFS:SetPoint("TOPLEFT", nameFS, "TOPRIGHT", splitGap, 0)
                        end
                    end
                    timeFS:Show()
                else
                    timeFS:Hide()
                    if objAlign == "RIGHT" then
                        nameFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad + objTextX, objY)
                    elseif objAlign == "CENTER" then
                        nameFS:SetPoint("TOP", f, "TOP", objTextX, objY)
                    else
                        nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", oPad + objTextX, objY)
                    end
                    nameFS:SetWidth(oInnerW)
                end
                nameFS:SetJustifyH(objAlign)
                nameFS:Show()
                y = y - (nameFS:GetStringHeight() or 12) - OBJ_GAP
            end
        end
    end

    for i = objIdx + 1, #objRows do
        local e = objRows[i]
        if e then e.name:Hide(); e.time:Hide() end
    end

    if not underBarMode then
        if objIdx > 0 then y = y - 5 end
        RenderEnemyForces()
    end

    local totalH = abs(y) + PAD
    f:SetHeight(totalH)

    if isPreview and p.showPreview then
        SetFS(f._previewFS, 8)
        f._previewFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        f._previewFS:SetText("PREVIEW")
        f._previewFS:ClearAllPoints()
        f._previewFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 4)
        f._previewFS:Show()
    elseif f._previewFS then
        f._previewFS:Hide()
    end

    ns.ApplyBorder()
    f:Show()
end

_G._EMT_StandaloneRefresh = RenderStandalone
_G._EMT_GetStandaloneFrame = function()
    return CreateStandaloneFrame()
end

-- Forces a full rebuild by discarding the cached frame + its FontStrings
-- so the next RenderStandalone() re-creates them from scratch. Use when a
-- setting (e.g. text alignment) won't take effect via re-render alone.
_G._EMT_RebuildStandalone = function()
    if standaloneFrame then standaloneFrame:Hide() end
    standaloneFrame = nil
    standaloneCreated = false
    wipe(objRows)
    RenderStandalone()
end

-- One-time migration of legacy TOPLEFT-stored position into stable centerX/Y
-- offsets relative to UIParent center. Must run BEFORE SetScale so the
-- derived center reflects the unscaled frame; otherwise repeated calls
-- after SetScale would compute a different center each time and the frame
-- would drift.
local function _ensureCenterPos()
    local pos = db and db.profile and db.profile.standalonePos
    if not pos then return end
    if pos.centerX and pos.centerY then return end
    local f = standaloneFrame
    if not (f and f:GetCenter()) then return end
    -- Force scale 1.0 momentarily so GetCenter returns un-scaled coords.
    local prevScale = f:GetScale()
    f:SetScale(1.0)
    local cx, cy = f:GetCenter()
    local upX, upY = UIParent:GetCenter()
    pos.centerX = cx - upX
    pos.centerY = cy - upY
    -- Strip legacy keys so the migration only runs once.
    pos.point, pos.relPoint, pos.x, pos.y = nil, nil, nil, nil
    f:SetScale(prevScale)
end

local function _centerPosFromSaved(pos)
    if not pos or pos.centerX == nil or pos.centerY == nil then return end
    local scale = (db and db.profile and db.profile.scale) or 1.0
    if scale == 0 then scale = 1.0 end
    return pos.centerX / scale, pos.centerY / scale
end

local function ApplyStandalonePosition()
    if not db then return end
    if not standaloneFrame then return end
    _ensureCenterPos()
    local pos = db.profile.standalonePos
    local scale = db.profile.scale or 1.0
    if scale == 0 then scale = 1.0 end

    -- SetPoint offsets are in the frame's OWN scaled coord space, so the
    -- effective on-screen offset = stored * scale. To keep the visual
    -- center pinned regardless of scale, divide the stored offset by scale.
    standaloneFrame:SetScale(scale)
    local sx, sy = _centerPosFromSaved(pos)
    if sx ~= nil then
        standaloneFrame:ClearAllPoints()
        standaloneFrame:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
    end
end
_G._EMT_ApplyStandalonePosition = ApplyStandalonePosition

-- True only when every scenario objective is complete: Avoids false times being saved/missed runs due to completion on same tick
local function IsDungeonComplete()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    if numCriteria == 0 then return false end

    local seenAny = false
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            seenAny = true
            if not info.completed then
                return false
            end
        end
    end

    return seenAny
end

-- Event-driven runtime. Zero polling. Lifecycle events handle start /
-- complete / reset; SCENARIO_CRITERIA_UPDATE handles the "all objectives
-- done" detection (no need for a per-tick poller). Multi-event detection
-- with GetInstanceInfo difficulty fallback (IsChallengeModeActive returns
-- false post-completion, so map-id alone isn't reliable).
local runtimeFrame = CreateFrame("Frame")

local function _isInChallengeMode()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    -- Fallback: difficulty 8 = Mythic Keystone. Reliable across the brief
    -- window where IsChallengeModeActive flips false but we're still in
    -- the dungeon (e.g. immediately after completion).
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 8
end

local function HandleRuntimeEvent(event)
    if not db or not db.profile.enabled then
        if currentRun.active or currentRun.completed then ResetRun() end
        return
    end

    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    if activeMapID then
        if not currentRun.active and not currentRun.completed then
            StartRun()
        end
        -- Pure event-driven completion check: criteria updates fire when
        -- bosses die and when the weighted enemy-forces tally crosses 100.
        if currentRun.active and event == "SCENARIO_CRITERIA_UPDATE" then
            if IsDungeonComplete() then CompleteRun() end
        end
    elseif (currentRun.active or currentRun.completed) and not _isInChallengeMode() then
        -- M+ cleared and we're no longer in a M+ instance. Salvage as
        -- completion if the last criteria update saw it complete.
        if currentRun.active and IsDungeonComplete() then
            CompleteRun()
        else
            ResetRun()
        end
    end
end

-- Always-on (low-frequency) events: enough to detect a key starting.
local _ALWAYS_EVENTS = {
    "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET", "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP",
}
-- High-frequency events: only needed during an active run. SCENARIO_CRITERIA_UPDATE
-- fires constantly in any scenario (pet battles, world quest scenarios, garrisons,
-- etc.); ZONE_CHANGED_NEW_AREA fires on every subzone crossing while questing.
-- Registering them only during a key keeps idle CPU at zero.
local _RUN_EVENTS = { "SCENARIO_CRITERIA_UPDATE", "ZONE_CHANGED_NEW_AREA" }

local function _registerRunEvents()
    for _, ev in ipairs(_RUN_EVENTS) do runtimeFrame:RegisterEvent(ev) end
end
local function _unregisterRunEvents()
    for _, ev in ipairs(_RUN_EVENTS) do runtimeFrame:UnregisterEvent(ev) end
end

for _, ev in ipairs(_ALWAYS_EVENTS) do runtimeFrame:RegisterEvent(ev) end
runtimeFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ApplyStandalonePosition()
        -- API data isn't fully populated at PEW; retry once after 10s
        -- to catch a /reload mid-key.
        C_Timer.After(10, function() HandleRuntimeEvent("PLAYER_ENTERING_WORLD_DELAYED") end)
    end
    HandleRuntimeEvent(event)

    -- Toggle high-frequency event subscriptions based on whether we're
    -- actually in a key. Outside M+ we don't want to wake on every quest
    -- update or subzone change.
    if currentRun.active then
        _registerRunEvents()
    else
        _unregisterRunEvents()
    end
end)

function EMT:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIMythicTimerDB", DB_DEFAULTS)
    _G._EMT_AceDB = db
    AppendSharedMediaBarTextures()

    if db and db.profile then
        local pp = db.profile
        for key, value in pairs(DB_DEFAULTS.profile) do
            if pp[key] == nil then
                pp[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
        -- showPreview is a transient options-panel state. /reload doesn't fire
        -- the EUI window's OnHide auto-off, so the saved value can persist
        -- as true across reloads. Force it off at every login.
        pp.showPreview = false
    end

    -- Season-based data purge: clear split records from previous seasons.
    C_Timer.After(2, function()
        if not db or not db.profile then return end
        local currentMaps = C_ChallengeMode.GetMapTable()
        if not currentMaps or #currentMaps == 0 then return end

        local validMapIDs = {}
        for _, mapID in ipairs(currentMaps) do
            validMapIDs[mapID] = true
        end

        if db.profile.bestObjectiveSplits then
            for scopeKey in pairs(db.profile.bestObjectiveSplits) do
                -- Keys are normally scoped strings ("<mapID>-..."), but legacy
                -- data can store a bare numeric mapID. tostring() guards against
                -- calling :match on a number (crashes in Lua 5.1).
                local mapIDStr = tostring(scopeKey):match("^(%d+)")
                local mapID = tonumber(mapIDStr)
                if mapID and not validMapIDs[mapID] then
                    db.profile.bestObjectiveSplits[scopeKey] = nil
                end
            end
        end
    end)

    -- runtimeFrame is now event-driven (registered above); no OnUpdate needed.
end

function EMT:OnEnable()
    if not db or not db.profile.enabled then return end

    if EllesmereUI and EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EMT_MythicTimer", function(active)
            unlockLayoutActive = active == true
            -- When the element is anchor-linked to another unlock element,
            -- the anchor system owns the frame's position; re-applying our
            -- stored absolute standalonePos would snap it away from the
            -- anchor-derived spot on every unlock open/close.
            local anchored = EllesmereUI.IsUnlockAnchored
                and EllesmereUI.IsUnlockAnchored("EMT_MythicTimer")
            if unlockLayoutActive then
                RenderStandalone()
                if not anchored then ApplyStandalonePosition() end
            else
                if not db.profile.showPreview
                    and not currentRun.active and not currentRun.completed then
                    if standaloneFrame then standaloneFrame:Hide() end
                else
                    RenderStandalone()
                end
                if not anchored then ApplyStandalonePosition() end
            end
        end)
    end

    if EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement then
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EMT_MythicTimer",
                label = "Mythic+ Timer",
                group = "Mythic+",
                order = 520,
                noResize = true,
                getFrame = function()
                    return _G._EMT_GetStandaloneFrame and _G._EMT_GetStandaloneFrame()
                end,
                getSize  = function()
                    local f = standaloneFrame
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 260, 200
                end,
                isHidden = function()
                    return false
                end,
                savePos = function(_, point, relPoint, x, y)
                    -- Stored as delta in UIParent-logical units (matches the
                    -- migration in _ensureCenterPos). ApplyStandalonePosition
                    -- divides by profile.scale on apply; screen delta works
                    -- out to stored_UIlogical * UIParent:GetEffectiveScale().
                    --
                    -- f:GetCenter() returns coords in the frame's OWN scaled
                    -- units. At frame scale != 1 we must re-scale those to
                    -- UIParent-logical units before subtracting upX. Multiply
                    -- cx by (frame_effective / UIParent_effective) to land in
                    -- the same space as upX. Without this the stored offset
                    -- shrinks at larger scales and the frame snaps toward the
                    -- middle every time settings re-apply (e.g. Show Preview).
                    local f = standaloneFrame
                    if f and f:GetCenter() then
                        local cx, cy = f:GetCenter()
                        local upX, upY = UIParent:GetCenter()
                        local fes = f:GetEffectiveScale() or 1
                        local ues = UIParent:GetEffectiveScale() or 1
                        local ratio = fes / ues
                        db.profile.standalonePos = {
                            centerX = cx * ratio - upX,
                            centerY = cy * ratio - upY,
                        }
                    end
                    if f and not EllesmereUI._unlockActive then
                        local sx, sy = _centerPosFromSaved(db.profile.standalonePos)
                        if sx ~= nil then
                            f:ClearAllPoints()
                            f:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
                        end
                    end
                end,
                loadPos = function()
                    -- Unlock Mode expects { point, relPoint, x, y }; we store
                    -- centerX/centerY in UIParent-logical units.
                    local pos = db.profile.standalonePos
                    local sx, sy = _centerPosFromSaved(pos)
                    if sx == nil then return nil end
                    return {
                        point = "CENTER",
                        relPoint = "CENTER",
                        x = sx,
                        y = sy,
                    }
                end,
                clearPos = function()
                    db.profile.standalonePos = nil
                end,
                applyPos = function()
                    if standaloneFrame then ApplyStandalonePosition() end
                end,
            }),
        })
    end
end

