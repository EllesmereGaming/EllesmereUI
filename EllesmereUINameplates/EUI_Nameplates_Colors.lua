if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Colors.lua
--
--  Threat context, quest mob detection and the plate colors (class, threat,
--  reaction).
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, ipairs, type = pairs, ipairs, type
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local UnitIsEnemy, UnitIsTapDenied = UnitIsEnemy, UnitIsTapDenied
local UnitAffectingCombat, UnitClassification = UnitAffectingCombat, UnitClassification
local UnitReaction = UnitReaction
local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass
local Enum = Enum

local defaults, GetTextSlot, IsComboHealthText = I.defaults, I.GetTextSlot, I.IsComboHealthText
local MaybeDarken = I.MaybeDarken

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-- Cached threat-context state; updated at zone transitions and spec changes
local _inThreatContent = false
local _isTankRole      = false

-- Off-tank color under identity restriction: the mob-target ROLE is secret, so
-- the question flips sides -- "is any OTHER tank tanking this mob" -- via
-- UnitDetailedThreatSituation(tankToken, mob) (plain tokens in; isTanking
-- boolean out, plain or secret; field-probed real boolean in keys) folded
-- through C_CurveUtil.EvaluateColorValueFromBoolean so no secret is ever read
-- in Lua. Returns ok plus possibly-SECRET r,g,b: the caller must hand them to
-- SETTERS ONLY -- never compare, cache, multiply or format them. Tank tokens
-- rebuild lazily off ns._otherTanksDirty (set by RefreshThreatCache's existing
-- roster/role/zone events -- zero new registrations; own-group role reads are
-- plain). On ns (file is at the 200-local cap).
function ns.ComputeOffTankFold(unit, br, bg, bb, otr, otg, otb)
    local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not eval then return false end
    if ns._otherTanksDirty or not ns._otherTankTokens then
        ns._otherTanksDirty = false
        local t = ns._otherTankTokens
        if t then wipe(t) else t = {}; ns._otherTankTokens = t end
        local n = 0
        local prefix, count
        if IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
        elseif IsInGroup() then prefix, count = "party", GetNumGroupMembers() - 1 end
        if prefix then
            for i = 1, count do
                if n >= 3 then break end
                local tok = prefix .. i
                if not UnitIsUnit(tok, "player")
                    and UnitGroupRolesAssigned(tok) == "TANK" then
                    n = n + 1; t[n] = tok
                end
            end
        end
    end
    local toks = ns._otherTankTokens
    if not toks[1] then return false end
    -- All colors arrive from the caller: the _C accessor is declared far BELOW
    -- this function, so resolving colors here read a nil global (field crash).
    local r, g, b = br, bg, bb
    if not (r and otr) then return false end
    for i = 1, #toks do
        local isTanking = UnitDetailedThreatSituation(toks[i], unit)
        -- type() is legal on secrets and reports the underlying type, so one
        -- check admits both plain and secret booleans; a refused call (nil)
        -- skips and the accumulator keeps the safe tankNoAggro color.
        if type(isTanking) == "boolean" then
            r = eval(isTanking, otr, r)
            g = eval(isTanking, otg, g)
            b = eval(isTanking, otb, b)
        end
    end
    return true, r, g, b
end

-- Show Threat Colors (threatColorMode): "always" colors every plate that has threat data,
-- "instances" only inside threat content (the zone verdict RefreshThreatCache caches),
-- "never" switches the whole threat-color feature off (health-bar arm, Border / Name
-- channels, Near Aggro glow, off-tank fold). Materialized into ns._npThreatColorsOn so
-- the per-plate color paths pay one field read; re-derived by RefreshThreatCache (zone,
-- role, spec), RefreshAllSettings (profile and override swaps), OnEnable and the options
-- setter. An unknown saved value reads as the default. On ns (file is at the 200-local cap).
ns._npThreatColorsOn = false
function ns.NP_RefreshThreatColorFlag()
    local mode = p and p.threatColorMode
    if mode ~= "never" and mode ~= "instances" and mode ~= "always" then
        mode = defaults.threatColorMode
    end
    ns._npThreatColorsOn = (mode == "always" or (mode == "instances" and _inThreatContent)) and true or false
end

local function RefreshThreatCache()
    ns._otherTanksDirty = true
    -- Zone: party/raid instances and delves (difficultyID 204) are threat-relevant
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    -- Dungeon-only flag for the "Mini Enemies" trash color (instanceType "party"; excludes
    -- raids/delves/open world). Cached so the per-plate color path costs one field read.
    ns._inDungeon = (instanceType == "party")
    if difficultyID == 0
    or (C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap()) then
        _inThreatContent = false
    else
        local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
        _inThreatContent = (instanceType == "party" or instanceType == "raid"
                            or isDelve)
    end
    -- Role: cache so we don't recalculate on every nameplate update. Effective
    -- role (EllesmereUI.UnitEffectiveRole): the player's spec wins over a stale
    -- premade-listing role (listed as tank, playing dps), and still covers the
    -- solo "NONE" case the old spec fallback existed for.
    local role = EllesmereUI.UnitEffectiveRole("player")
    _isTankRole = (role == "TANK")
    ns.NP_RefreshThreatColorFlag()
end

-- Threat-content zone verdict (party/raid instances, delves). The classification icon's
-- open-world rule reads it; the threat colors read ns._npThreatColorsOn instead.
local function InRealInstancedContent()
    return _inThreatContent
end

-------------------------------------------------------------------------------
--  Quest Mob Detection: C_TooltipInfo scans unit tooltips for quest objective lines. Cached
--  per unit; invalidated on QUEST_LOG_UPDATE and NAME_PLATE_UNIT_REMOVED.
-------------------------------------------------------------------------------
local questMobCache = {}
-- Parallel cache of verified-clean "objectives remaining" strings, keyed by unit. Populated
-- only when replaceQuestIconWithObjective is ON; same invalidation lifecycle. On ns (cap).
ns._questObjText = ns._questObjText or {}
-- Is this unit one of the local player's active quest objectives with work remaining? Read
-- from the tooltip's structured data: a QuestObjective line carries `completed` plus
-- numFulfilled/numRequired, a QuestTitle line the quest id, so completion needs no
-- progress-string parsing. Ownership goes through the player's own quest log (only their
-- quests answer C_QuestLog.IsOnQuest), so a group member's objective is ignored. Every
-- structured value is possibly secret and issecretvalue-checked before use. Cached per unit;
-- cleared on QUEST_LOG_UPDATE and plate removal.
local function IsQuestMob(unit)
    if not (C_TooltipInfo and Enum and Enum.TooltipDataLineType) then return false end
    local cached = questMobCache[unit]
    if cached ~= nil then return cached end

    -- Open-world only, unless the indicator's "Show In Instances" opt-in lifts it.
    if InRealInstancedContent() then
        local show = p and p.classificationShowInInstances
        if show == nil then show = defaults.classificationShowInInstances end
        if not show then
            questMobCache[unit] = false
            return false
        end
    end

    local info = C_TooltipInfo.GetUnit(unit)
    if not (info and info.lines) then
        questMobCache[unit] = false
        return false
    end

    local LT = Enum.TooltipDataLineType
    local onQuest = C_QuestLog and C_QuestLog.IsOnQuest
    local wantText = (p and p.replaceQuestIconWithObjective == true) or false
    local questID  -- id carried by the most recent QuestTitle line
    local isQuest, objText = false, nil

    for _, line in ipairs(info.lines) do
        local kind = line.type
        if kind == LT.QuestTitle then
            local id = line.id
            if id and not (issecretvalue and issecretvalue(id)) then
                questID = id
            else
                questID = nil
            end
        elseif kind == LT.QuestObjective then
            local done = line.completed
            -- An incomplete objective the player is actually on: their quest log scopes out a
            -- group member's objectives. Fail open when the id is unreadable so a real quest
            -- mob is never silently skipped.
            if not (issecretvalue and issecretvalue(done)) and done == false
               and (not questID or not onQuest or onQuest(questID)) then
                isQuest = true
                if wantText then
                    local have, need = line.numFulfilled, line.numRequired
                    if have and need
                       and not (issecretvalue and (issecretvalue(have) or issecretvalue(need))) then
                        -- Percent-style objectives (area progress bars)
                        -- degenerate to 0/1 in the structured fields; the
                        -- real progress lives only in the line text. Show
                        -- the extracted percent when readable, else the
                        -- count (real 0/1 kill objectives keep their count).
                        local lt = line.leftText
                        local pct
                        if lt and not (issecretvalue and issecretvalue(lt))
                           and type(lt) == "string" then
                            pct = lt:match("(%d+)%s*%%")
                        end
                        objText = pct and (pct .. "%") or (have .. "/" .. need)
                    end
                end
                break
            end
        end
    end

    questMobCache[unit] = isQuest
    if wantText then
        ns._questObjText[unit] = isQuest and objText or nil
    end
    return isQuest
end
ns.IsQuestMob = IsQuestMob

-- Thin reader for the icon-replace feature. Returns a clean digit string or nil.
function ns.GetQuestObjectiveText(unit)
    return ns._questObjText[unit]
end

-- Live refresh for the options toggle. Wiping BOTH caches is required: IsQuestMob short-circuits
-- on questMobCache[unit] ~= nil, so a unit cached while OFF never gets objective text extracted.
function ns.RefreshQuestObjective()
    wipe(questMobCache)
    wipe(ns._questObjText)
    for _, plate in pairs(ns.plates) do
        if plate.UpdateClassification then
            plate:UpdateClassification()
        end
    end
end

-- Invalidate quest cache on quest log changes (throttled to avoid
-- recoloring all plates on every QUEST_LOG_UPDATE burst).
local questCacheWatcher = CreateFrame("Frame")
questCacheWatcher:RegisterEvent("QUEST_LOG_UPDATE")
ns._questDirty = false
questCacheWatcher:SetScript("OnEvent", function()
    wipe(questMobCache)
    wipe(ns._questObjText)
    if not ns._questDirty then
        ns._questDirty = true
        C_Timer.After(0.5, function()
            ns._questDirty = false
            for _, plate in pairs(ns.plates) do
                plate:UpdateHealthColor()
                plate:UpdateClassification()
            end
        end)
    end
end)

local function _C(key)
    return (p and p[key]) or defaults[key]
end
-- Neutral health-bar color: enemyInCombat tint while in combat, else neutral color. Shared by
-- every precedence step resolving to "neutral" (step 5, neutral+mini carve-out 7b, dungeon 10d).
local function ResolveNeutralColor(unit)
    if UnitAffectingCombat(unit) then
        local c = _C("enemyInCombat")
        return c.r, c.g, c.b
    end
    local c = _C("neutral")
    return c.r, c.g, c.b
end
-- The Hostile or Neutral name colour (enemyNameHostileColor / enemyNameNeutralColor, shared
-- by every text slot) for an NPC in a Hostility / Class text slot, matching the unit's
-- reaction independent of the health-bar palette. Every NameplateFrame unit is an enemy
-- (HideBlizzardFrame only suppresses Blizzard's frame on UnitCanAttack units), so only
-- these two reactions are ever relevant here. Same
-- reaction/UnitCanAttack idiom as the health-bar Neutral check below (GetReactionColor step 5)
-- so a secret reaction read (identity-restricted units) falls through safely instead of erroring.
local function GetEnemyNameReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player"))
    local db = p or defaults
    local c
    if isNeutral then
        c = db.enemyNameNeutralColor or defaults.neutral
    else
        c = db.enemyNameHostileColor or defaults.hostile
    end
    return c.r, c.g, c.b
end

-- Core Text Coloring (ns.NP_SlotColorMode, per slot): a slot in
-- Hostility / Class ("class") or Level Difficulty ("level") mode has whatever it shows
-- painted per unit from UpdateHealthColor; "custom" keeps the static slot colour.
-- ns._npSlotClassOn is materialized at login and by RefreshAllSettings (also the Spec
-- Overrides refresher), so UpdateHealthColor pays one boolean read while every slot is
-- custom. ns fields throughout: this file is at its local cap.
ns._npSlotClassOn = false
ns._npSlotClassName = false
ns._npSlotClassFS = {}  -- plate font string keys painted in class mode
ns._npSlotLevelFS = {}  -- plate font string keys painted in level mode
ns._npSlotLevelCK = {}  -- parallel: the owning slot's colour key (unreadable-level fallback)
-- Materialized with the class flags: the font string key each bottom slot owns
-- (false = none, or a later slot rewrites that shared font string), whether
-- either owns one (the cast show / hide re-anchor runs only then), and the slot
-- showing Target of Target (false = none; its UNIT_TARGET registration follows
-- it) plus whether that slot is in class mode. _npToTUnits caches "<unit>target".
ns._npBottomFS = { false, false }
ns._npBottomUsed = false
ns._npToTSlot = false
ns._npToTClass = false
ns._npToTColorKey = nil
ns._npToTUnits = {}
do
    -- The order ApplyHealthTextAppearance lays the slots out in (bar slots, then top):
    -- the last slot writing a shared font string owns it.
    local SLOTS = { "textSlotRight", "textSlotLeft", "textSlotCenter",
        "textSlotBottomLeft", "textSlotBottomRight", "textSlotTop" }
    local owner, ownerSlot, lastIdx = {}, {}, {}
    local COLOR_KEY = {}  -- slot -> its colour key (prebuilt for UpdateToT and the painter)
    for i = 1, #SLOTS do COLOR_KEY[SLOTS[i]] = SLOTS[i] .. "Color" end
    -- The plate font string key an element renders on (nil for None).
    function ns.NP_ElementFSKey(el)
        if ns.IsNameElement(el) then return "name" end
        if el == "level" then return "levelText" end
        if el == "targetOfTarget" then return "totText" end
        if el == "healthNumber" then return "hpNumber" end
        if el == "healthPercent" or el == "healthPercentNoSign" or IsComboHealthText(el) then
            return "hpText"
        end
    end
    function ns.NP_RefreshSlotClassFlags()
        local L, V, VC = ns._npSlotClassFS, ns._npSlotLevelFS, ns._npSlotLevelCK
        wipe(L)
        wipe(V)
        wipe(VC)
        wipe(owner)
        wipe(ownerSlot)
        wipe(lastIdx)
        ns._npToTSlot = false
        ns._npToTClass = false
        local B = ns._npBottomFS
        -- The name is placed in FindNameSlot's slot (the first holding one), the
        -- other shared font strings by the last slot writing them.
        local nameSlot = ns.FindNameSlot()
        for i = 1, #SLOTS do
            local s = SLOTS[i]
            local key = ns.NP_ElementFSKey(GetTextSlot(s))
            if key == "totText" then
                -- Painted by UpdateToT from the target's class, never the plate unit's.
                ns._npToTSlot = s
                ns._npToTClass = ns.NP_SlotColorMode(s) == "class"
            elseif key and (key ~= "name" or s == nameSlot) then
                owner[key] = ns.NP_SlotColorMode(s)
                ownerSlot[key] = s
            end
            if key then lastIdx[key] = i end
            if i == 4 or i == 5 then B[i - 3] = key or false end
        end
        for b = 1, 2 do
            if B[b] == "name" then
                if nameSlot ~= SLOTS[b + 3] then B[b] = false end
            elseif B[b] and lastIdx[B[b]] ~= b + 3 then
                B[b] = false
            end
        end
        ns._npToTColorKey = ns._npToTSlot and COLOR_KEY[ns._npToTSlot] or nil
        ns._npBottomUsed = (B[1] or B[2]) and true or false
        for key, mode in pairs(owner) do
            if mode == "class" then
                L[#L + 1] = key
            elseif mode == "level" then
                V[#V + 1] = key
                VC[#V] = COLOR_KEY[ownerSlot[key]]
            end
        end
        ns._npSlotClassName = owner.name == "class" or owner.name == "level"
        ns._npSlotClassOn = (L[1] or V[1]) and true or false
        -- The name text's combo part colours (read by SetNameElementText).
        ns.NP_RefreshSlotNameParts()
    end
end
-- Paints one plate's class- and level-mode slots. Class mode: enemy players take the EUI
-- class palette (EllesmereUI.GetClassColor: custom class colours count; the bar's own class
-- colour reads RAID_CLASS_COLORS, so the two differ only under a custom palette). A redacted
-- class token takes the restricted-unit palette, else Blizzard's class colour, handed
-- straight to the font strings and never memoized (the memo entry is cleared instead).
-- Tapped NPCs take the Tapped name colour (default: the plate's Tapped grey), other
-- NPCs the Hostile / Neutral name colours. The class token is read once per unit (keyed
-- on the unit token; ClearUnit resets it). Level mode: the unit's level difficulty colour
-- (NP_UnitLevelColor); while the level cannot be read the slot colour is written once
-- (memo marker false). Per font string memo on our plate (_scMemo), reset wherever the
-- slot colours are written statically. Returns true while the name's slot is in either
-- mode. An inline colour escape in the text (a Level | Name part colour) still wins over
-- it. skipName leaves the name alone (Threat Colors "Text" holds it) and drops its memo
-- entry, so the first call without it repaints the name.
function ns.NP_PaintSlotClassColors(plate, unit, skipName)
    local m = plate._scMemo
    if not m then m = {}; plate._scMemo = m end
    local L = ns._npSlotClassFS
    if L[1] then
        if plate._scUnit ~= unit then
            plate._scUnit = unit
            local tok = false
            if UnitIsPlayer(unit) then
                local _, t = UnitClass(unit)
                if issecretvalue(t) then tok = true elseif t then tok = t end
            end
            plate._scTok = tok
        end
        local tok = plate._scTok
        local painted = false
        if tok == true then
            local _, t = UnitClass(unit)
            local ok, sr, sg, sb = EllesmereUI.GetClassColorForRestrictedUnit(unit, t)
            if not ok then
                local c = C_ClassColor.GetClassColor(t)
                if c then ok = true; sr, sg, sb = c:GetRGB() end
            end
            if ok then
                painted = true
                for i = 1, #L do
                    local key = L[i]
                    local e = m[key]
                    if e then e[1] = nil end
                    if not (skipName and key == "name") then
                        plate[key]:SetTextColor(sr, sg, sb, 1)
                    end
                end
            end
        end
        if not painted then
            local r, g, b
            if tok and tok ~= true then
                local c = EllesmereUI.GetClassColor(tok)
                r, g, b = c.r, c.g, c.b
            elseif UnitIsTapDenied(unit) then
                local c = (p and p.enemyNameTappedColor) or _C("tapped")
                r, g, b = c.r, c.g, c.b
            else
                r, g, b = GetEnemyNameReactionColor(unit)
            end
            for i = 1, #L do
                local key = L[i]
                local e = m[key]
                if not e then e = {}; m[key] = e end
                if skipName and key == "name" then
                    e[1] = nil
                elseif e[1] ~= r or e[2] ~= g or e[3] ~= b then
                    e[1], e[2], e[3] = r, g, b
                    plate[key]:SetTextColor(r, g, b, 1)
                end
            end
        end
    end
    local V = ns._npSlotLevelFS
    if V[1] then
        local r, g, b = ns.NP_UnitLevelColor(unit)
        for i = 1, #V do
            local key = V[i]
            local e = m[key]
            if not e then e = {}; m[key] = e end
            if skipName and key == "name" then
                e[1] = nil
            elseif not r then
                if e[1] ~= false then
                    e[1] = false
                    local ck = ns._npSlotLevelCK[i]
                    local c = (p and p[ck]) or defaults[ck]
                    plate[key]:SetTextColor(c.r, c.g, c.b, 1)
                end
            elseif e[1] ~= r or e[2] ~= g or e[3] ~= b then
                e[1], e[2], e[3] = r, g, b
                plate[key]:SetTextColor(r, g, b, 1)
            end
        end
    end
    return ns._npSlotClassName
end
-- Blizzard's own plate for this unit, colored by untainted code. Under HideBlizzardFrame the
-- UnitFrame keeps its unit (its events are killed), so its health bar still carries whatever
-- CompactUnitFrame_UpdateHealthColor resolved in the driver's SetUnit -- including the class
-- color we are not allowed to look up ourselves. Returns a PLAIN "have it" boolean plus three
-- numbers that may be secret: never branch on the numbers, only ever hand them to a setter.
-- On ns (module file is at the 200-local cap).
function ns.GetBlizzardBarColor(frame)
    local np = frame.nameplate
    local uf = np and np.UnitFrame
    -- Blizzard's plates are pooled too. Until ITS CompactUnitFrame_SetUnit has run for our
    -- unit, that bar still wears the previous occupant's colour, and latching onto it would
    -- paint a confidently WRONG class colour. No match, no mirror: the plain fallback applies
    -- and the next pass retries.
    if not uf or uf.unit ~= frame.unit then return false end
    local hb = uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
    if not hb or not hb.GetStatusBarColor then return false end
    -- Same filter HideBlizzardFrame applies to this frame's children: reading a forbidden
    -- widget throws, which would abort the rest of UpdateHealthColor on every health event.
    if hb.IsForbidden and hb:IsForbidden() then return false end
    local r, g, b = hb:GetStatusBarColor()
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
    return true, r, g, b
end
-- Threat Colors channels (multi-check on the Threat Colors section). All three on ns:
-- the module file is at the 200-local cap. Health Bar defaults ON so nothing changes
-- for an existing profile; Border/Text default OFF.
function ns.GetThreatColorHealth()
    local v = p and p.threatColorHealth
    if v == nil then return defaults.threatColorHealth end
    return v
end
function ns.GetThreatColorBorder()
    local v = p and p.threatColorBorder
    if v == nil then return defaults.threatColorBorder end
    return v
end
function ns.GetThreatColorName()
    local v = p and p.threatColorName
    if v == nil then return defaults.threatColorName end
    return v
end
-- The threat color for the SECOND channels (border / name text), resolved independently
-- of the health bar's priority chain. GetReactionColor cannot answer this: there the
-- threat colors compete with tapped/quest/target/focus/mob-type and lose (or win) by
-- priority, while a border/name channel exists precisely so the threat signal is never
-- traded against the type signal. Same role arms, same colors and same enable toggles as
-- the health arm, minus every priority interaction:
--   tank      -- no aggro / losing aggro always; off-tank color when a co-tank holds it;
--               has aggro only with Tank Has Aggro (or Classic Tank Aggro) enabled
--   non-tank  -- has aggro / near aggro always; no aggro only with DPS No Aggro enabled
-- Returns nothing when there is no signal to show (Show Threat Colors off here, no threat
-- data, solo, or the state's color is opt-in and switched off) -- the caller then leaves
-- the border/name at its normal color. The fourth return is a SECRET flag: true means
-- r/g/b are secret values (an off-tank C-fold over a secret isTanking read), so the caller
-- must hand them to setters only and never cache or compare them. status: the threat
-- situation this pass already read (false = no threat data), or nil to read it here; the
-- nil test reads the type tag only, since the situation read can be secret.
function ns.ResolveThreatColor(unit, status)
    if not ns._npThreatColorsOn then return end
    if type(status) == "nil" then status = UnitThreatSituation("player", unit) end
    if not status then return end
    local db = p or defaults
    if not _isTankRole then
        -- Solo players always have aggro: the signal only means something in a group.
        if not IsInGroup() then return end
        if status >= 3 then
            local c = _C("dpsHasAggro")
            return c.r, c.g, c.b, false
        elseif status >= 2 then
            local c = _C("dpsNearAggro")
            return c.r, c.g, c.b, false
        end
        local en = defaults.dpsNoAggroEnabled
        if db.dpsNoAggroEnabled ~= nil then en = db.dpsNoAggroEnabled end
        if en then
            local c = _C("dpsNoAggro")
            return c.r, c.g, c.b, false
        end
        return
    end
    -- Tank arm.
    if status >= 3 then
        -- Holding it: nothing is wrong, so the has-aggro color only paints when the user
        -- explicitly asked for one (either toggle). Otherwise no tint at all, which is the
        -- point of a border channel: red border = someone else's mob, plain border = mine.
        local hae = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then hae = db.tankHasAggroEnabled end
        if not hae then
            hae = defaults.classicTankAggro
            if db.classicTankAggro ~= nil then hae = db.classicTankAggro end
        end
        if hae then
            local c = _C("tankHasAggro")
            return c.r, c.g, c.b, false
        end
        return
    end
    if status >= 2 then
        local c = _C("tankLosingAggro")
        return c.r, c.g, c.b, false
    end
    -- No aggro. Another TANK holding the mob is normal off-tank positioning, not a
    -- warning -- same read as the health arm, including the secret-role fallback: an
    -- identity-restricted role read cannot be compared, so the question flips sides and
    -- ns.ComputeOffTankFold answers it C-side ("is any OTHER tank tanking this mob"),
    -- starting from the tankNoAggro color and folding toward offTankAggro.
    local otE = defaults.offTankAggroEnabled
    if db.offTankAggroEnabled ~= nil then otE = db.offTankAggroEnabled end
    local base = _C("tankNoAggro")
    local targetRole, roleSecret = "NONE", false
    local unitTarget = unit .. "target"
    if UnitExists(unitTarget) then
        local r = UnitGroupRolesAssigned(unitTarget)
        if issecretvalue(r) then roleSecret = true
        elseif r then targetRole = r end
    end
    if otE and roleSecret then
        local otc = _C("offTankAggro")
        local folded, fr, fg, fb = ns.ComputeOffTankFold(unit, base.r, base.g, base.b, otc.r, otc.g, otc.b)
        -- Secret when an isTanking read was: those components reach setters only. A
        -- plain fold goes through the caller's memos like any other colour.
        if folded then
            return fr, fg, fb, (issecretvalue(fr) or issecretvalue(fg) or issecretvalue(fb))
        end
        return base.r, base.g, base.b, false
    end
    if targetRole == "TANK" then
        -- Co-tank holds it. With Off-Tank Color off there is no signal to show (the health
        -- arm falls through here too) -- a red border would call normal positioning a bug.
        if not otE then return end
        local c = _C("offTankAggro")
        return c.r, c.g, c.b, false
    end
    return base.r, base.g, base.b, false
end
local function GetReactionColor(unit)
    -- Per-call marker read SYNCHRONOUSLY by UpdateHealthColor right after this
    -- returns: true only when this resolution landed on the non-tank Near
    -- Aggro color, so the near-aggro glow rides the exact same decision.
    -- On ns (module file is at the 200-local cap).
    ns._reactionNearAggro = false
    -- Same idiom, for the enemy player class color at step 6: set when the class token
    -- came back redacted, so UpdateHealthColor knows to mirror Blizzard's bar instead.
    ns._reactionMirrorClass = false
    -- Same idiom, for the off-tank color under identity restriction: set when the
    -- mob-target ROLE read came back secret with Off-Tank Color enabled, so
    -- UpdateHealthColor asks ns.ComputeOffTankFold for a C-folded color instead
    -- of the plain tankNoAggro fallback this function returns.
    ns._reactionOffTankFold = false
    -- Same idiom, for the threat situation: nil until this pass reads it, then the value
    -- (false = no threat data), which UpdateHealthColor hands to ns.ResolveThreatColor
    -- instead of a second UnitThreatSituation read.
    ns._reactionThreatStatus = nil
    local db = p or defaults
    -- 1. Tapped always highest
    if UnitIsTapDenied(unit) then
        local c = _C("tapped")
        return c.r, c.g, c.b
    end
    -- 2. Quest mob second highest
    if db.questMobColorEnabled and IsQuestMob(unit) then
        local qc = db.questMobColor or defaults.questMobColor
        return qc.r, qc.g, qc.b
    end
    -- Threat colors that can NEVER be overwritten:
    -- Non-tank: has aggro, near aggro Tank: losing aggro, no aggro
    local isThreatUnit = false   -- set true when threat data exists
    local threatStatus = 0
    -- Show Threat Colors (Never / Instances / Always): one cached field read.
    if ns._npThreatColorsOn then
        local status = UnitThreatSituation("player", unit)
        ns._reactionThreatStatus = status or false
        if status then
            isThreatUnit = true
            threatStatus = status
            -- Threat Colors "Health Bar" channel off: the bar carries no threat color at
            -- all. Clearing isThreatUnit here is what makes that complete -- it also
            -- switches off the LOW-priority has-aggro / no-aggro steps further down
            -- (6b, 7b, 9, 10), which read these two locals -- so the bar ends up purely
            -- mob-type/reaction colored and the Border/Text channels own the threat signal
            -- on their own. The near-aggro glow rides the STATE, not the bar color, so it
            -- is still marked here; ns._reactionOffTankFold is a health-bar mechanism and
            -- deliberately stays unset (ns.ResolveThreatColor does its own fold).
            if not ns.GetThreatColorHealth() then
                if not _isTankRole and IsInGroup() and status >= 2 and status < 3 then
                    ns._reactionNearAggro = true
                end
                isThreatUnit, threatStatus = false, 0
            elseif not _isTankRole then
                -- Non-tank: has aggro / near aggro absolute priority
                -- Only apply when in a group (solo players always have aggro)
                if IsInGroup() then
                if status >= 3 then
                    local c = _C("dpsHasAggro")
                    return c.r, c.g, c.b
                elseif status >= 2 then
                    ns._reactionNearAggro = true
                    local c = _C("dpsNearAggro")
                    return c.r, c.g, c.b
                end
                end
            else
                -- Tank arm. 12.1 field facts (side-by-side dump): the situation
                -- API pins 3 on plate tokens while the DETAILED API returns
                -- SECRET booleans for plate pairings (plain only for "target"
                -- pairings) -- no Lua branch can know who holds the mob. With
                -- Off-Tank Color on, mark EVERY tank-arm paint for the C-side
                -- fold: it starts from the plain color this function returns
                -- and overrides toward offTankAggro exactly when a co-tank's
                -- isTanking folds true. One tank holds per mob, so the fold
                -- self-resolves with zero secret reads.
                local otE = db.offTankAggroEnabled
                if otE == nil then otE = defaults.offTankAggroEnabled end
                if otE then ns._reactionOffTankFold = true end
                if status < 3 and status >= 2 then
                    local c = _C("tankLosingAggro")
                    return c.r, c.g, c.b
                elseif status < 3 then
                    -- Only show no-aggro warning if a non-tank has it.
                    -- If another tank holds aggro, this is normal offtank positioning.
                    local unitTarget = unit .. "target"
                    -- Role reads on identity-restricted units return SECRET values: never
                    -- truthiness-chain or compare one. Unreadable role reads as non-tank.
                    local targetRole = "NONE"
                    local roleSecret = false
                    if UnitExists(unitTarget) then
                        local r = UnitGroupRolesAssigned(unitTarget)
                        if issecretvalue(r) then roleSecret = true
                        elseif r then targetRole = r end
                    end
                    -- Role unreadable (identity restriction): the plain path
                    -- below lands on tankNoAggro, but mark the frame so
                    -- UpdateHealthColor can answer the REAL question from the
                    -- other side -- "is any other tank tanking this mob" via
                    -- UnitDetailedThreatSituation + the C_CurveUtil color fold
                    -- (field-probed: returns a real boolean in keys).
                    if roleSecret then
                        local otE = db.offTankAggroEnabled
                        if otE == nil then otE = defaults.offTankAggroEnabled end
                        if otE then ns._reactionOffTankFold = true end
                    end
                    if targetRole ~= "TANK" then
                        local c = _C("tankNoAggro")
                        return c.r, c.g, c.b
                    end
                    -- Another tank has aggro -- show off-tank color if enabled
                    local otEnabled = db.offTankAggroEnabled
                    if otEnabled == nil then otEnabled = defaults.offTankAggroEnabled end
                    if otEnabled then
                        local c = _C("offTankAggro")
                        return c.r, c.g, c.b
                    end
                end
                -- Classic tank aggro: has-aggro overrides all mob-type colors
                if status >= 3 then
                    local classic = db.classicTankAggro
                    if classic == nil then classic = defaults.classicTankAggro end
                    if classic then
                        local c = _C("tankHasAggro")
                        return c.r, c.g, c.b
                    end
                end
                -- Default: tank has aggro falls through to caster/miniboss colors
            end
        end
    end
    -- 4. Target color (if enabled)
    local targetC = _C("target")
    if targetC and UnitIsUnit(unit, "target") then
        local tEnabled = defaults.targetColorEnabled
        if db.targetColorEnabled ~= nil then tEnabled = db.targetColorEnabled end
        if tEnabled then
            return targetC.r, targetC.g, targetC.b
        end
    end
    -- 5. Focus color (if enabled)
    local focusC = _C("focus")
    if focusC and UnitIsUnit(unit, "focus") then
        local enabled = defaults.focusColorEnabled
        if db.focusColorEnabled ~= nil then enabled = db.focusColorEnabled end
        if enabled then
            return focusC.r, focusC.g, focusC.b
        end
    end
    -- 5. Neutral (colored as an enemy while in combat with them). OUTSIDE dungeons keeps its
    -- high priority; IN dungeons deferred to just above the enemy fallback (step 10d) so
    -- mob-type/threat colors win on neutral dungeon units and neutral becomes near-last resort.
    local reaction = UnitReaction(unit, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player"))
    if isNeutral and not ns._inDungeon then
        return ResolveNeutralColor(unit)
    end
    -- 6. Enemy player class colors
    if UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
        local _, class = UnitClass(unit)
        -- A secret class token (identity-restricted, i.e. instanced PvP) cannot key a
        -- color table. Blizzard resolves the same lookup UNTAINTED on its own plate and
        -- its bar keeps updating under our suppression, so flag the plate here and let
        -- UpdateHealthColor copy that color across without ever inspecting it. We still
        -- fall through to the reaction color so every plain-number consumer downstream
        -- (the skip-if-unchanged compare, the No Tint overlay tints) keeps plain numbers.
        -- Gated on the CVar because that is what decides whether Blizzard's bar is a class
        -- color at all: with it off the bar carries a selection/threat color, and copying
        -- that would overwrite the user's Enemy Types color with red.
        if issecretvalue(class) then
            ns._reactionMirrorClass = GetCVarBool("nameplateShowClassColor") == true
            class = nil
        end
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r, c.g, c.b
        end
    end
    -- Classify the mob-type tier once up front so the tank has-aggro overrides can reason about
    -- boss vs mini-boss vs caster independently. Booleans only: mob-type colors still return at
    -- their own priority steps (7, 8, 10b).
    local inCombat = UnitAffectingCombat(unit)
    local classification = UnitClassification(unit)
    -- Simple Coloring When Not In M+ (inline cog on Enemy Types): outside 5-man dungeons, collapse the
    -- mob-type colors (Mini Enemies, Spell Casters, Mini-Bosses, Bosses) into flat owBasicColor
    -- at the enemy fallback (step 11). Neutral unaffected (already returned at step 5 outside
    -- dungeons). Same dungeon gate as Mini Coloring M+ Only (ns._inDungeon).
    local owBasic = false
    if not ns._inDungeon then
        owBasic = defaults.owBasicColoring
        if db.owBasicColoring ~= nil then owBasic = db.owBasicColoring end
    end
    -- Mini Enemies color scope: restricted to 5-man dungeons when "Mini Coloring
    -- M+ Only" is on (default), applied everywhere when it is off.
    local miniMPlusOnly = defaults.miniColoringMPlusOnly
    if db.miniColoringMPlusOnly ~= nil then miniMPlusOnly = db.miniColoringMPlusOnly end
    local miniColorScope = not owBasic and (ns._inDungeon or not miniMPlusOnly)
    local _isBossUnit = false  -- deferred: boss color is applied at step 10b
    local _isMiniBoss = false
    if not owBasic
       and (classification == "elite" or classification == "worldboss" or classification == "rareelite") then
        -- Effective level (handles scaling / Chromie time), not raw level, so
        -- the tier tracks how the game ranks the mob against the player.
        local level = UnitEffectiveLevel(unit)
        local lvlClean = level and not (issecretvalue and issecretvalue(level))
        local isSkull = lvlClean and level == -1
        local playerLevel = UnitEffectiveLevel("player")
        local plvlClean = playerLevel and not (issecretvalue and issecretvalue(playerLevel))
        -- A skull, or an elite ranked at least one effective level above the
        -- player, gets a tier; ordinary same/lower-level elites are left alone.
        local aboveOne = plvlClean and lvlClean and level >= playerLevel + 1
        if isSkull or aboveOne then
            -- Boss when it reads as boss-ranked: a skull, a world boss, or two+ effective
            -- levels up. UnitIsLieutenant is the client's mini-boss marker, so a non-skull
            -- lieutenant is pinned to mini-boss.
            local aboveTwo = plvlClean and lvlClean and level >= playerLevel + 2
            local lieutenant = (not isSkull) and UnitIsLieutenant and UnitIsLieutenant(unit)
            if not lieutenant and (isSkull or aboveTwo or classification == "worldboss") then
                _isBossUnit = true
            else
                _isMiniBoss = true
            end
        end
    end
    -- Caster = the unit actually has a mana pool, rather than a class match. Second arg is
    -- typed PowerType (enum NUMBER), not the global MANA (localized "Mana" string, never
    -- matches). hasPower carries no secrecy flag, so it is safe to branch on directly.
    -- Excludes boss units: _isMiniBoss already skips this step by returning earlier (step 7,
    -- above Caster's step 8), but _isBossUnit's own color is deferred to step 10b (below the
    -- threat-color steps, intentionally) -- with no exclusion here, a mana-using boss (e.g. a
    -- caster-type raid boss) hit step 8's return before step 10b was ever reached, showing the
    -- Spell Caster color instead of Bosses. Mirrors the mutual exclusivity boss/mini-boss
    -- already have with each other.
    local _isCaster = not owBasic and not _isBossUnit and UnitHasPowerType(unit, Enum.PowerType.Mana)
    -- DPS/healer No Aggro override state (mirrors tank has-aggro overrides at 6b). Each
    -- override independently promotes the No Aggro color above one mob-type step (mini-boss 7,
    -- caster 8). Active only for a non-tank without aggro in a group (matches step 10).
    local dpsNoAggroActive = isThreatUnit and (not _isTankRole) and threatStatus < 2 and IsInGroup()
    if dpsNoAggroActive then
        local en = defaults.dpsNoAggroEnabled
        if db.dpsNoAggroEnabled ~= nil then en = db.dpsNoAggroEnabled end
        dpsNoAggroActive = en
    end
    -- 6b. Tank has aggro -- "Override Mini-Boss and Caster colors" option. Promotes the
    -- has-aggro color above the mini-boss/caster steps, still below target/focus/enemy-class.
    -- Boss units excluded (governed by "Override Boss colors", step 9/10b). Sits between the
    -- absolute-priority Classic Tank Aggro path above and low-priority step 9.
    if isThreatUnit and _isTankRole and threatStatus >= 3 and not _isBossUnit then
        local hae = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then hae = db.tankHasAggroEnabled end
        local ovr = defaults.tankHasAggroOverrideMobType
        if db.tankHasAggroOverrideMobType ~= nil then ovr = db.tankHasAggroOverrideMobType end
        if hae and ovr then
            local c = _C("tankHasAggro")
            return c.r, c.g, c.b
        end
    end
    -- 7. Mini-boss. Boss is intentionally LOWER priority than the low-priority threat colors
    -- below, so it is deferred to step 10b (see _isBossUnit); mini-boss stays here, above threat.
    if _isMiniBoss then
        -- DPS/healer No Aggro "Override Mini-Boss colors": promotes the No Aggro
        -- color above the mini-boss color when enabled.
        if dpsNoAggroActive then
            local ovr = defaults.dpsNoAggroOverrideMiniBoss
            if db.dpsNoAggroOverrideMiniBoss ~= nil then ovr = db.dpsNoAggroOverrideMiniBoss end
            if ovr then
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
        local c = _C("miniboss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 7b. Mini Enemies promoted ABOVE Caster -- but ONLY for DPS/healers and tanks that do NOT
    -- use the special Tank Has Aggro color. Tanks WITH that option enabled skip this and keep
    -- Mini Enemies at its original low priority (step 10c), so has-aggro/caster/mob-type colors
    -- still win on trash.
    if miniColorScope
       and (classification == "normal" or classification == "minus" or classification == "trivial") then
        local thae = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then thae = db.tankHasAggroEnabled end
        -- Neutral + mini-enemy: neutral coloring wins over the trash color, EXCEPT for a tank
        -- holding aggro with Tank Has Aggro enabled -- that viewer falls through so step 9
        -- paints the has-aggro color; otherwise in-combat neutral blocks threat coloring and
        -- neutral mobs stay enemy-red for tanks. Other viewers: neutral beats trash/DPS
        -- carve-out/Caster (7b sits above step 8). Non-trash neutral units defer to 10d.
        local tankAggroPending = isThreatUnit and _isTankRole and threatStatus >= 3 and thae
        if isNeutral and not tankAggroPending then return ResolveNeutralColor(unit) end
        if not (_isTankRole and thae) then
            -- DPS "No Aggro" still wins over the promoted Mini Enemies color, so a DPS/healer
            -- without aggro sees the warning on trash. Scoped to this trash branch so Caster
            -- still outranks DPS No Aggro on non-trash casters (step 10, same condition).
            if isThreatUnit and not _isTankRole and threatStatus < 2 and IsInGroup() then
                local dpsNA = defaults.dpsNoAggroEnabled
                if db.dpsNoAggroEnabled ~= nil then dpsNA = db.dpsNoAggroEnabled end
                if dpsNA then
                    local c = _C("dpsNoAggro")
                    return c.r, c.g, c.b
                end
            end
            local c = (p and p.miniEnemy) or _C("enemyInCombat")
            return MaybeDarken(c.r, c.g, c.b, inCombat)
        end
    end
    -- 8. Caster
    if _isCaster then
        -- DPS/healer No Aggro "Override Caster colors": promotes No Aggro above the caster
        -- color when enabled. Kept separate from the mini-boss override for contrast.
        if dpsNoAggroActive then
            local ovr = defaults.dpsNoAggroOverrideCaster
            if db.dpsNoAggroOverrideCaster ~= nil then ovr = db.dpsNoAggroOverrideCaster end
            if ovr then
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
        local c = _C("caster")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 9. Tank has aggro (if enabled) below focus/caster/miniboss. Normally sits above the boss
    -- color (step 10b); with "Override Boss colors" disabled it's held below boss instead (the
    -- 10b return wins for boss units, so has-aggro lands just below bosses).
    if isThreatUnit and _isTankRole and threatStatus >= 3 then
        local enabled = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then enabled = db.tankHasAggroEnabled end
        if enabled then
            local ovrBoss = defaults.tankHasAggroOverrideBoss
            if db.tankHasAggroOverrideBoss ~= nil then ovrBoss = db.tankHasAggroOverrideBoss end
            if ovrBoss or not _isBossUnit then
                local c = _C("tankHasAggro")
                return c.r, c.g, c.b
            end
        end
    end
    -- 10. Non-tank no aggro (if enabled) below focus/caster/miniboss. Boss units gated behind
    -- their own "Override Boss colors" toggle (default ON = the behaviour before the toggle
    -- existed, so nothing changes for users who did not touch it), mirroring tank has-aggro's
    -- ovrBoss check at step 9 above -- previously unconditional, so a DPS/healer without aggro
    -- always lost the Bosses color on engage with no way to turn that off (unlike Mini-Boss/
    -- Caster, which already had their own override toggles here, both off by default).
    if isThreatUnit and not _isTankRole and threatStatus < 2 and IsInGroup() then
        local enabled = defaults.dpsNoAggroEnabled
        if db.dpsNoAggroEnabled ~= nil then enabled = db.dpsNoAggroEnabled end
        if enabled then
            local ovrBoss = defaults.dpsNoAggroOverrideBoss
            if db.dpsNoAggroOverrideBoss ~= nil then ovrBoss = db.dpsNoAggroOverrideBoss end
            if ovrBoss or not _isBossUnit then
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
    end
    -- 10b. Boss (intentionally below the low-priority threat colors above, so tank-has-aggro/
    -- dps-no-aggro takes precedence over boss -- unless "Override Boss colors" is disabled, in
    -- which case the has-aggro/no-aggro step above defers to this boss color for boss units).
    if _isBossUnit then
        local c = _C("boss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10c. Mini Enemies: non-elite trash (normal/minus), DUNGEONS ONLY -- outside dungeons
    -- these fall through to the enemy color below. Elites handled at step 7, so same-level
    -- elites still use the enemy color. Below the threat colors, so aggro still wins.
    -- DPS/healers and non-special-aggro tanks already returned at 7b; this path only serves
    -- tanks with "Has Aggro" on.
    if miniColorScope
       and (classification == "normal" or classification == "minus" or classification == "trivial") then
        -- Views "Enemies" (enemyInCombat) until the user sets a Mini Enemies color explicitly.
        local c = (p and p.miniEnemy) or _C("enemyInCombat")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10d. Neutral, deferred (dungeons only -- step 5 skipped it there): a neutral unit
    -- matching no mob-type/threat color lands here, just above the generic enemy fallback.
    if isNeutral then
        return ResolveNeutralColor(unit)
    end
    -- 11. Fallback: enemy in/out of combat. With Simple Coloring When Not In M+ active, every mob-type
    -- special above was suppressed, so all hostile mobs share the flat "All Enemies" color.
    local eic = _C(owBasic and "owBasicColor" or "enemyInCombat")
    return MaybeDarken(eic.r, eic.g, eic.b, inCombat)
end

I._C, I.GetReactionColor, I.questMobCache = _C, GetReactionColor, questMobCache
I.RefreshThreatCache = RefreshThreatCache
I.broken = false
