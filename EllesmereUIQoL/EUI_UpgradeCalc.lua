-------------------------------------------------------------------------------
--  EUI_UpgradeCalc.lua  (part of EllesmereUIQoL)
--  Gear upgrade planner: data tables, game logic, and calculator UI.
--  Frame: EUIUpgCalcFrame | Slash: /euic
-------------------------------------------------------------------------------

EUIUpgCalc      = EUIUpgCalc or {}
EUIUpgCalc.Data = {}

local Calc = EUIUpgCalc
local Data = EUIUpgCalc.Data
local EUI  = EllesmereUI
local PP   = EUI.PP

local function IsLocked()
    return InCombatLockdown() or (EUI.InProtectedInstance and EUI.InProtectedInstance())
end

-------------------------------------------------------------------------------
--  DATA
-------------------------------------------------------------------------------

-- ── SEASON UPDATE: replace all values in Data.tracks each new season. ────────
-- Per track: crestName (tooltip display name),
-- hexColor (UI tint, can stay if the crest colour is unchanged), currID (currency
-- ID from Blizzard — check Wowhead or /dump C_CurrencyInfo.GetCurrencyInfo(id)),
-- ranks (ilvl at each of the 6 upgrade ranks, lowest to highest).
-- Add or remove tracks from Data.trackOrder to match the season's track list.
Data.tracks = {
    Adventurer = {
        crestName = "Adventurer Crest",
        hexColor = "|cff1eff00", currID = 3383, tier = 1,
        ranks = { 220, 224, 227, 230, 233, 237 },
    },
    Veteran = {
        crestName = "Veteran Crest",
        hexColor = "|cff0070dd", currID = 3341, tier = 2,
        ranks = { 233, 237, 240, 243, 246, 250 },
    },
    Champion = {
        crestName = "Champion Crest",
        hexColor = "|cffa335ee", currID = 3343, tier = 3,
        ranks = { 246, 250, 253, 256, 259, 263 },
    },
    Hero = {
        crestName = "Hero Crest",
        hexColor = "|cffff8000", currID = 3345, tier = 4,
        ranks = { 259, 263, 266, 269, 272, 276 },
    },
    Myth = {
        crestName = "Myth Crest",
        hexColor = "|cffffd100", currID = 3347, tier = 5,
        ranks = { 272, 276, 279, 282, 285, 289 },
    },
}

Data.trackOrder = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- All equippable character slot IDs (paper-doll order; excludes ammo/relic).
Data.equipSlots = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- Human-readable slot names keyed by slot ID.
Data.slotNames = {
    [1]  = "Head",       [2]  = "Neck",      [3]  = "Shoulder",
    [5]  = "Chest",      [6]  = "Waist",     [7]  = "Legs",
    [8]  = "Feet",       [9]  = "Wrist",     [10] = "Hands",
    [11] = "Ring 1",     [12] = "Ring 2",    [13] = "Trinket 1",
    [14] = "Trinket 2",  [15] = "Back",      [16] = "Main Hand",
    [17] = "Off Hand",
}

-- SEASON UPDATE: if Voidcore (or its equivalent) is removed, set voidcoreBonus=0
-- and clear voidcoreEligibleSlots. If new slots become eligible, add their IDs here.
-- The bonus ilvl value (currently 9) should match the Voidcore item level increase.
Data.voidcoreEligibleSlots = { 13, 14, 16, 17 }
Data.voidcoreBonus         = 9

-- Reverse lookup: currencyID → crestName (built after track table is complete).
local _currIDToCrestName = {}
for _, td in pairs(Data.tracks) do
    if td.currID and td.currID > 0 then
        _currIDToCrestName[td.currID] = td.crestName
    end
end

-- SEASON UPDATE: update these ilvl steps to match the base-crafted tier ilvls
-- for the new season (currently T1–T5 = 246/249/252/255/259).
-- Referenced in GetCraftedInfo; hoisted here so it is allocated once, not per call.
Data.craftedTierSteps = { 246, 249, 252, 255, 259 }

-- SEASON UPDATE: update minIlvl/maxIlvl each new season to match crafted item ilvl caps.
-- minIlvl: lowest ilvl at which an item belongs to this crafted band (checked highest-first).
-- maxIlvl: ilvl ceiling for crafted items in this band.
-- Ordered highest-first so CraftedBandFromIlvl can short-circuit on the first match.
Data.craftedBands = {
    { name = "Myth", minIlvl = 272, maxIlvl = 285 },
    { name = "Hero", minIlvl = 259, maxIlvl = 272 },
    { name = "None", minIlvl = 0,   maxIlvl = 259 },
}
-- Reverse lookup: band name → band data (for O(1) access in ScanItemLink).
Data.craftedBandByName = {}
for _, b in ipairs(Data.craftedBands) do Data.craftedBandByName[b.name] = b end

-------------------------------------------------------------------------------
--  CORE
-------------------------------------------------------------------------------

-- Pointer to the active EllesmereUIDB profile slice for this module.
-- Set on PLAYER_LOGIN once the profile system initialises.
-- All persistent reads/writes go through DB() and Opts() which use this.
local _euicProfileRef = nil
-- Cached direct references to the sub-tables, set once in PLAYER_LOGIN so that
-- every subsequent DB()/Opts() call is a simple local read with no table traversal.
local _dbCache   = nil
local _optsCache = nil
-- (Character key used only locally in PLAYER_LOGIN to index per-character storage;
--  not retained as a module variable since _dbCache is set directly.)

local function DB()
    if _dbCache then return _dbCache end
    local store
    if _euicProfileRef then
        store = _euicProfileRef
    else
        EllesmereUIQoLDB = EllesmereUIQoLDB or {}
        store            = EllesmereUIQoLDB
    end
    store.upgradeCalc       = store.upgradeCalc      or {}
    local db                = store.upgradeCalc
    db.cache                = db.cache               or { slots = {}, ts = 0 }
    db.calibrated           = db.calibrated          or false
    db.queue                = db.queue               or {}
    db.crestManualAdds      = db.crestManualAdds     or {}
    return db
end

local function Opts()
    if _optsCache then return _optsCache end
    local store
    if _euicProfileRef then
        store = _euicProfileRef
    else
        EllesmereUIQoLDB     = EllesmereUIQoLDB or {}
        store                = EllesmereUIQoLDB
    end
    store.upgradeCalcOpts    = store.upgradeCalcOpts or {}
    return store.upgradeCalcOpts
end

-- Exposed so EUI_UpgradeCalc_Options.lua can always read the live opts table,
-- regardless of whether the profile system has been initialised yet.
Calc.GetOptsDB  = function() return Opts() end
Calc.GetCalcDB  = function() return DB()   end  -- exposed for Options reset helper

-- Slot IDs grouped by category, used for filter settings.
Data.slotGroups = {
    Armour    = { 1, 3, 5, 6, 7, 8, 9, 10, 15 },  -- head, shoulder, chest, waist, legs, feet, wrist, hands, back
    Jewellery = { 2, 11, 12 },                      -- neck, ring 1, ring 2
    Trinkets  = { 13, 14 },
    Weapons   = { 16, 17 },
}
-- Build reverse lookup: slotID -> group name
Data.slotToGroup = {}
for grp, ids in pairs(Data.slotGroups) do
    for _, id in ipairs(ids) do Data.slotToGroup[id] = grp end
end

-- C_TooltipInfo-based scanning. NEVER create a scanning GameTooltipTemplate
-- from Lua -- it taints the tooltip system. See CLAUDE.md / reference_tooltip_template_taint.
local function GetTooltipLines(link)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local data = C_TooltipInfo.GetHyperlink(link)
    if not data then return nil end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end
    return data.lines
end

local function ForEachTooltipLine(lines, fn)
    if not lines then return end
    for _, line in ipairs(lines) do
        local text = line.leftText
        if text and text ~= "" then fn(text) end
    end
end

-- Strip WoW inline colour codes from a string.
local function Plain(s)
    return s and (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or ""
end

-- Returns { slot, link, ilvl } for every equipped item on `unit` (default "player").
function Calc:GetEquippedGear(unit)
    unit = unit or "player"
    local gear = {}
    for _, slot in ipairs(Data.equipSlots) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local ilvl = C_Item.GetDetailedItemLevelInfo(link) or 0
            gear[#gear + 1] = { slot = slot, link = link, ilvl = ilvl }
        end
    end
    return gear
end

Calc._tipCache = {}   -- [link] = { track, rank, isCrafted, craftBand, craftMaxIlvl, isVoidforged }

function Calc:ScanItemLink(link)
    if not link then return nil end
    local cached = Calc._tipCache[link]
    if cached then return cached end

    local result = {
        track = nil, rank = nil,
        isCrafted = false, craftBand = nil, craftMaxIlvl = nil,
        isVoidforged = false,
    }

    local lines = GetTooltipLines(link)
    local foundTrack, foundRank, foundVoid = nil, nil, false
    ForEachTooltipLine(lines, function(text)
        if not foundTrack and text:find("Upgrade Level") then
            local t, r = text:match("Upgrade Level:%s+(%a+)%s+(%d+)/%d+")
            if t then foundTrack = t; foundRank = tonumber(r) end
        end
        if not foundVoid and Plain(text):find("Ascendant Voidforged") then
            foundVoid = true
        end
    end)
    result.track = foundTrack
    result.rank  = foundRank
    result.isVoidforged = foundVoid

    -- Only scan the crafted tooltip if no upgrade track was found.
    -- Reuse the same lines -- C_TooltipInfo returns all tooltip data in one call.
    if not foundTrack then
        local isCrafted, sawHero, sawMyth = false, false, false
        ForEachTooltipLine(lines, function(raw)
            local t = Plain(raw)
            if t:find("Crafted") or t:find("Optional Reagents") or t:find("Recrafting") or t:find("Made by") then
                isCrafted = true
            end
            if t:find("Hero") then sawHero = true end
            if t:find("Myth") then sawMyth = true end
        end)
        result.isCrafted = isCrafted

        if isCrafted then
            local bname = sawMyth and "Myth" or sawHero and "Hero" or "None"
            local bdata = Data.craftedBandByName[bname]
            result.craftBand    = bname
            result.craftMaxIlvl = bdata and bdata.maxIlvl or 259
        end
    end

    Calc._tipCache[link] = result
    return result
end

-- Returns: trackName (string|nil), rank (number|nil).
function Calc:GetItemTrackAndRank(link)
    local r = self:ScanItemLink(link)
    return r and r.track, r and r.rank
end

-- Shared helper: given an ilvl, returns band ("Myth"/"Hero"/"None") and maxIlvl.
-- Called by both GetCraftedInfo (tooltip fallback) and the PopulateGear heuristic
-- so the two code paths can never silently diverge on a season update.
-- Thresholds are read from Data.craftedBands — update that table each new season.
local function CraftedBandFromIlvl(ilvl)
    for _, band in ipairs(Data.craftedBands) do
        if ilvl >= band.minIlvl then
            return band.name, math.max(band.maxIlvl, ilvl)
        end
    end
    -- Fallback: treat as base crafted (should never be reached; ilvl < 0 is impossible).
    local base = Data.craftedBandByName["None"]
    return "None", math.max(base and base.maxIlvl or 259, ilvl)
end

-- Returns: isCrafted, band, tier, maxIlvl.
function Calc:GetCraftedInfo(link, ilvl)
    local r = self:ScanItemLink(link)
    if not r or not r.isCrafted then return false end
    local band, maxIlvl = r.craftBand or "None", r.craftMaxIlvl or 259

    -- If tooltip gave no band keywords, fall back to ilvl thresholds via shared helper.
    -- (See CraftedBandFromIlvl above for the SEASON UPDATE note.)
    if r.craftBand == "None" then
        band, maxIlvl = CraftedBandFromIlvl(ilvl)
    end

    local tier
    if band == "None" then
        local steps   = Data.craftedTierSteps
        local best, bestDist = 1, math.huge
        for i, s in ipairs(steps) do
            local d = math.abs(ilvl - s)
            if d < bestDist then bestDist = d; best = i end
        end
        tier = best
    end
    return true, band, tier, maxIlvl
end

-- Returns true when the item has "Ascendant Voidforged" in its tooltip.
-- SEASON UPDATE: if the Voidforged modifier is renamed or replaced, update the
-- search string below to match the new tooltip text.
function Calc:IsVoidforged(link)
    local r = self:ScanItemLink(link)
    return r and r.isVoidforged or false
end

-- Returns the ilvl gain from the next upgrade step, or nil if already at max.
-- (Reserved for future use; not currently called by PopulateGear.)
function Calc:GetNextUpgradeGain(item)
    local track, rank = self:GetItemTrackAndRank(item.link)
    if not track or not rank then return nil end
    local td = Data.tracks[track]
    if not td or rank >= #td.ranks then return nil end
    return (td.ranks[rank + 1] or 0) - (td.ranks[rank] or 0)
end

-- Returns a table mapping crestName -> { quantity, cap, earned } for each track.
function Calc:GetPlayerCrests()
    local owned = {}
    for _, td in pairs(Data.tracks) do
        if td.currID and td.currID > 0 then
            local info = C_CurrencyInfo.GetCurrencyInfo(td.currID)
            if info then
                owned[td.crestName] = {
                    quantity = info.quantity    or 0,
                    cap      = (info.maxQuantity and info.maxQuantity > 0) and info.maxQuantity or nil,
                    earned   = info.totalEarned or 0,
                }
            end
        end
    end
    return owned
end

-- Returns detailed cost info for a single item.
-- Non-crafted: trackName, rank, crestCost, maxIlvl
-- Crafted:     "Crafted", nil, nil, maxIlvl, tierLabel, band
function Calc:GetItemUpgradeCost(item)
    local track, rank = self:GetItemTrackAndRank(item.link)

    if not track then
        local isCrafted, band, tier, maxIlvl = self:GetCraftedInfo(item.link, item.ilvl)
        if isCrafted then
            local label = (band == "Hero" and "Hero Craft")
                       or (band == "Myth" and "Myth Craft")
                       or (tier and "T" .. tier .. "/5")
                       or "Crafted"
            return "Crafted", nil, nil, maxIlvl, label, band
        end
        return nil
    end

    local td = Data.tracks[track]
    if not td then return nil end

    local db = DB()

    local expectedMax = td.ranks[#td.ranks]
    for _, vs in ipairs(Data.voidcoreEligibleSlots) do
        if vs == item.slot then expectedMax = expectedMax + Data.voidcoreBonus; break end
    end

    -- Priority 1: exact costs from Upgrader NPC API (calibrated).
    local slotCache = db.calibrated and db.cache.slots[item.slot]
    if slotCache and slotCache.crestAmounts
            and slotCache.link == item.link then
        local exactCrests = 0
        for _, v in pairs(slotCache.crestAmounts) do exactCrests = exactCrests + v end
        return track, rank, exactCrests, expectedMax
    end

    -- Priority 2: raw estimate (upgrader scan not available for this slot).
    local upgradesLeft = #td.ranks - rank
    return track, rank, upgradesLeft * 20, expectedMax
end

function Calc:IsUpgraderOpen()
    return (ItemUpgradeFrame and ItemUpgradeFrame.IsShown and ItemUpgradeFrame:IsShown()) or false
end

local function SelectSlotInUpgrader(loc)
    -- Never touch protected API in combat; would cause taint.
    if not loc or IsLocked() then return false end
    if C_ItemUpgrade and C_ItemUpgrade.ClearItemUpgrade then
        pcall(C_ItemUpgrade.ClearItemUpgrade)
    end
    for _, fnName in ipairs({ "SetItemUpgradeFromItemLocation", "SetItemUpgradeFromLocation" }) do
        if C_ItemUpgrade and C_ItemUpgrade[fnName] then
            if pcall(C_ItemUpgrade[fnName], loc) then return true end
        end
    end
    return false
end

local function TallySlotCosts(info)
    local crestAmounts = {}
    local curr = info.currUpgrade or 0
    for _, lvl in ipairs(info.upgradeLevelInfos or {}) do
        if (lvl.upgradeLevel or 0) > curr then
            for _, cc in ipairs(lvl.currencyCostsToUpgrade or {}) do
                crestAmounts[cc.currencyID] = (crestAmounts[cc.currencyID] or 0) + (cc.cost or 0)
            end
        end
    end
    return crestAmounts
end

-- Scans every equipped slot at the Upgrader NPC, building an accurate cost cache.
-- Single-pass: selects each slot via SelectSlotInUpgrader, waits 0.3 s for the
-- Upgrader frame to populate async data for that slot, then reads the result via
-- C_ItemUpgrade.GetItemUpgradeItemInfo() (no arguments — returns data for the
-- currently-selected slot). Passing a loc argument is silently ignored by the API.
function Calc:ScanEquippedAtUpgrader(onDone)
    if IsLocked() then
        if onDone then onDone(false) end
        return
    end
    if Calc._scanning then
        if onDone then onDone(false) end
        return
    end
    local db = DB()
    if not self:IsUpgraderOpen() then
        if onDone then onDone(false) end
        return
    end

    Calc._scanning = true
    Calc._tipCache = {}

    -- Build into a fresh scratch table; only swap into db.cache on success.
    local newSlots = {}
    local slots    = Data.equipSlots
    local total    = #slots

    local function onScanDone(ok)
        Calc._scanning = false
        if ok then
            db.cache      = { slots = newSlots, ts = time() }
            db.calibrated = true
        end
        if onDone then onDone(ok) end
    end

    local function saveSlotInfo(slotID, info)
        if not (info and info.upgradeLevelInfos) then return end
        local crestAmounts = TallySlotCosts(info)
        local link = GetInventoryItemLink("player", slotID)
        newSlots[slotID] = {
            link         = link,
            crestAmounts = crestAmounts,
        }
    end

    -- Single-pass scan: select each slot, wait 0.3 s for the Upgrader frame to
    -- populate async data, then call GetItemUpgradeItemInfo() with NO arguments
    -- (the API returns data for whichever slot is currently selected; passing a
    -- loc argument is silently ignored and the call returns nil).
    local si = 1
    local function scanNext()
        if IsLocked() then onScanDone(false); return end
        if si > total then onScanDone(true); return end
        local slotID = slots[si]
        local loc    = ItemLocation and ItemLocation:CreateFromEquipmentSlot(slotID)
        if loc and SelectSlotInUpgrader(loc) then
            -- Wait for the Upgrader frame to load this slot's data, then read it.
            C_Timer.After(0.3, function()
                if IsLocked() then onScanDone(false); return end
                local info = C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo
                    and C_ItemUpgrade.GetItemUpgradeItemInfo()
                saveSlotInfo(slotID, info)
                si = si + 1
                scanNext()
            end)
        else
            -- Slot has no item or select failed; skip it.
            si = si + 1
            C_Timer.After(0.05, scanNext)
        end
    end

    scanNext()
end

function Calc:ClearCache()
    local db = DB()
    db.cache      = { slots = {}, ts = 0 }
    db.calibrated = false
end

-- Rescans a single slot at the Upgrader NPC and updates the cache entry for it.
-- Used after an upgrade so the display reflects the new remaining cost immediately.
-- Calls onDone(ok) when finished; ok=false if the NPC is closed, combat fires, or
-- the API returns no data for the slot.
function Calc:RescanSlot(slotID, onDone)
    if IsLocked() or Calc._scanning then
        if onDone then onDone(false) end; return
    end
    if not self:IsUpgraderOpen() then
        if onDone then onDone(false) end; return
    end
    local loc = ItemLocation and ItemLocation:CreateFromEquipmentSlot(slotID)
    if not loc or not SelectSlotInUpgrader(loc) then
        if onDone then onDone(false) end; return
    end
    -- Guard the async window with _scanning so a second upgrade event within
    -- 0.3 s can't launch a concurrent rescan and overwrite the wrong slot.
    Calc._scanning = true
    local db = DB()
    C_Timer.After(0.3, function()
        Calc._scanning = false
        if IsLocked() then
            if onDone then onDone(false) end; return
        end
        local info = C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo
            and C_ItemUpgrade.GetItemUpgradeItemInfo()
        if info and info.upgradeLevelInfos then
            local crestAmounts = TallySlotCosts(info)
            db.cache        = db.cache or { slots = {}, ts = 0 }
            db.cache.slots  = db.cache.slots or {}
            db.cache.slots[slotID] = {
                link         = GetInventoryItemLink("player", slotID),
                crestAmounts = crestAmounts,
                }
        end
        if onDone then onDone(true) end
    end)
end

-------------------------------------------------------------------------------
--  UI
-------------------------------------------------------------------------------

local function SolidTex(p,l,r,g,b,a) return EUI.SolidTex(p,l,r,g,b,a) end

local function GetCalcFont()
    return (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
end
local function GetCalcOutline()
    return (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
end
local function MFont(p, s, _, r, g, b, a)
    local fs = p:CreateFontString(nil, "OVERLAY")
    local flags = GetCalcOutline()
    fs:SetFont(GetCalcFont(), s, flags)
    if r then fs:SetTextColor(r, g or 1, b or 1, a or 1) end
    if flags == "" then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    return fs
end

local G    = EUI.ELLESMERE_GREEN
local ROW_H, HDR_H, FRAME_W, FRAME_H = 20, 20, 860, 730

-- Tile layout constants
local TILE_W    = 183
local TILE_H    = 50   -- tile frame height
local TILE_STEP = TILE_H + 5  -- row stride: tile height + gap (used in all layout math)
local TILE_COLS = 3
local TILE_GAP  = 5
local TILE_ROW_W = TILE_COLS * TILE_W + (TILE_COLS - 1) * TILE_GAP  -- 559
local QUEUE_X_OFF    = TILE_ROW_W + 16                                    -- 575
local QUEUE_W        = FRAME_W - 20 - QUEUE_X_OFF                        -- 265

-- Per-track RGB accent colours used on tile left-edge bars
local TRACK_RGB = {
    Adventurer = {0.12, 1.0,  0.0 },
    Veteran    = {0.0,  0.44, 0.87},
    Champion   = {0.64, 0.21, 0.93},
    Hero       = {1.0,  0.50, 0.0 },
    Myth       = {1.0,  0.82, 0.0 },
    Voidforged = {0.55, 0.0,  1.0 },
}

local f = CreateFrame("Frame", "EUIUpgCalcFrame", UIParent)
PP.Size(f, FRAME_W, FRAME_H)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -40)
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function(self) self:StartMoving() end)
f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
f:Hide()

local fBg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
fBg:SetAllPoints(f)
fBg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
fBg:SetTexCoord(0.25, 1, 0, 0.75)
local fBgOverlay = f:CreateTexture(nil, "BACKGROUND", nil, 1)
fBgOverlay:SetAllPoints(f)
fBgOverlay:SetColorTexture(0, 0, 0, 0.5)

function Calc.ApplyBgOpacity()
    local opts  = Opts()
    local alpha = opts and opts.bgOpacity
    if alpha == nil then alpha = 50 end
    fBgOverlay:SetColorTexture(0, 0, 0, alpha / 100)
end

function Calc.ApplyScale()
    local opts  = Opts()
    local scale = opts and opts.uiScale
    if scale == nil then scale = 100 end
    f:SetScale(scale / 100)
end

if EUI and EUI.PanelPP then
    EUI.PanelPP.CreateBorder(f, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
end

local titleBg = SolidTex(f, "BORDER", 0, 0, 0, 0.25)
PP.Point(titleBg, "TOPLEFT",  f, "TOPLEFT",  1, -1)
PP.Point(titleBg, "TOPRIGHT", f, "TOPRIGHT", -1, 0)
PP.Height(titleBg, 32)

local titleTxt = MFont(f, 13, "OUTLINE", 1, 1, 1, 1)
PP.Point(titleTxt, "TOPLEFT", f, "TOPLEFT", 10, -10)
titleTxt:SetText("Upgrade Calculator")

local closeBtn = CreateFrame("Button", nil, f)
PP.Size(closeBtn, 24, 24)
closeBtn:SetPoint("RIGHT", titleBg, "RIGHT", -5, 5)
local closeTxt = MFont(closeBtn, 16, "", 1, 1, 1, 0.75)
closeTxt:SetPoint("CENTER", -2, -3)
closeTxt:SetText("x")
closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1, 1, 1, 1) end)
closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(1, 1, 1, 0.75) end)
closeBtn:SetScript("OnClick", function() f:Hide() end)

-- RegisterEscapeClose is created at PLAYER_LOGIN; deferred in _firstRunEvt below.

local tabY = -36

local tabSep = SolidTex(f, "BORDER", 0.2, 0.2, 0.2, 1)
PP.Point(tabSep, "TOPLEFT",  f, "TOPLEFT",  10,  tabY - 22)
PP.Point(tabSep, "TOPRIGHT", f, "TOPRIGHT", -10, tabY - 22)
tabSep:SetHeight(PP.mult)

-- Row helpers
local function MakeTableHeader(parent, cols, yOffset)
    local hdrBg = SolidTex(parent, "BACKGROUND", 0, 0, 0, 0.35)
    PP.Point(hdrBg, "TOPLEFT",  parent, "TOPLEFT",  0, yOffset)
    PP.Point(hdrBg, "TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    PP.Height(hdrBg, HDR_H)
    for _, col in ipairs(cols) do
        local lbl = MFont(parent, 11, "OUTLINE", G.r, G.g, G.b, 1)
        PP.Point(lbl, "TOPLEFT", parent, "TOPLEFT", col.x + 4, yOffset - 2)
        PP.Width(lbl, col.w)
        lbl:SetJustifyH(col.align)
        lbl:SetText(col.label)
    end
end

local function MakeRow(parent, cols, yOffset, isAlt)
    local row = {}
    if isAlt then
        local bg = SolidTex(parent, "BACKGROUND", 0, 0, 0, 0.15)
        PP.Point(bg, "TOPLEFT",  parent, "TOPLEFT",  0, yOffset)
        PP.Point(bg, "TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
        PP.Height(bg, ROW_H)
        row.altBg = bg  -- stored so PopulateGear can reposition and hide/show it
    end
    for _, col in ipairs(cols) do
        local cell = MFont(parent, 11, nil, 0.85, 0.85, 0.85, 1)
        PP.Point(cell, "TOPLEFT", parent, "TOPLEFT", col.x + 4, yOffset - 2)
        PP.Width(cell, col.w - 8)
        cell:SetJustifyH(col.align)
        row[col.key] = cell
    end
    return row
end

local function MakeButton(parent, label, w, h, yOff, xOff)
    local btn = CreateFrame("Button", nil, parent)
    PP.Size(btn, w, h)
    PP.Point(btn, "TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    local btnBg = SolidTex(btn, "BACKGROUND", 0, 0, 0, 0.35)
    btnBg:SetAllPoints()
    local bb = EUI.MakeBorder(btn, 0.2, 0.2, 0.2, 1)
    if bb.SetColor then bb:SetColor(0.2, 0.2, 0.2, 1) end
    local txt = MFont(btn, 10, "OUTLINE", 1, 1, 1, 0.75)
    txt:SetAllPoints(); txt:SetJustifyH("CENTER"); txt:SetText(label)
    btn:SetScript("OnEnter", function() txt:SetTextColor(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function() txt:SetTextColor(1, 1, 1, 0.75) end)
    return btn, txt
end

-- Character Pane ──────────────────────────────────────────────────────────────
f.charPane = CreateFrame("Frame", nil, f)
f.charPane:SetAllPoints(f)

local ilvlStatLbl = MFont(f.charPane, 12, "OUTLINE", 1, 1, 1, 1)
PP.Point(ilvlStatLbl, "TOPLEFT", f.charPane, "TOPLEFT", 10, tabY - 11)
ilvlStatLbl:SetText("Current iLvl: -   Max Possible: -")
local ilvlEstLbl = MFont(f.charPane, 10, "OUTLINE", 0.53, 0.53, 0.53, 1)
PP.Point(ilvlEstLbl, "LEFT", ilvlStatLbl, "RIGHT", 4, 0)
ilvlEstLbl:SetText("")

local cc = CreateFrame("Frame", nil, f.charPane)
PP.Point(cc, "TOPLEFT",  f.charPane, "TOPLEFT",  10, tabY - 30)
PP.Point(cc, "TOPRIGHT", f.charPane, "TOPRIGHT", -10, tabY - 30)
PP.Height(cc, FRAME_H - 100)

-- ── iLvl Timeline bar ──────────────────────────────────────────────────────────
-- iLvl timeline bar: same line as the stat label, starts after "(estimated)"
local tlTrack = SolidTex(f.charPane, "BACKGROUND", 0, 0, 0, 0.3)
PP.Point(tlTrack, "LEFT", ilvlEstLbl, "RIGHT", 10, 0)
PP.Height(tlTrack, 10)
-- Right edge aligns with tile row right edge (cc x=10 + TILE_ROW_W)
tlTrack:SetPoint("RIGHT", f.charPane, "LEFT", 10 + TILE_ROW_W, 0)

-- Fill lives inside a clip frame so it can't overflow the track
local tlClip = CreateFrame("Frame", nil, f.charPane)
tlClip:SetPoint("TOPLEFT", tlTrack, "TOPLEFT", 0, 0)
tlClip:SetPoint("BOTTOMRIGHT", tlTrack, "BOTTOMRIGHT", 0, 0)
tlClip:SetClipsChildren(true)
local tlFill = SolidTex(tlClip, "ARTWORK", G.r, G.g, G.b, 0.9)
PP.Point(tlFill, "TOPLEFT", tlClip, "TOPLEFT", 0, 0)
PP.Point(tlFill, "BOTTOMLEFT", tlClip, "BOTTOMLEFT", 0, 0)
tlFill:SetWidth(1)  -- updated each refresh

-- ── Tile frames ──────────────────────────────────────────────────────────────────
local ToggleTileQueue  -- forward declaration (defined in queue section)

local tileFrames = {}
for i = 1, 18 do
    local btn = CreateFrame("Button", nil, cc)
    PP.Size(btn, TILE_W, TILE_H)
    btn:Hide()
    local bg = SolidTex(btn, "BACKGROUND", 1, 1, 1, 0.05)
    bg:SetAllPoints(btn)
    btn.bg = bg
    -- Left accent bar (3 px, track colour)
    local accentBar = SolidTex(btn, "BORDER", 0.5, 0.5, 0.5, 1)
    PP.Point(accentBar, "TOPLEFT",    btn, "TOPLEFT",    0, 0)
    PP.Point(accentBar, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(PP.mult * 3)
    accentBar:SetSnapToPixelGrid(false)
    accentBar:SetTexelSnappingBias(0)
    btn.accentBar = accentBar
    -- Queue overlay: 50% black with "In Queue" text
    local queueOv = CreateFrame("Frame", nil, btn)
    queueOv:SetAllPoints(btn)
    queueOv:SetFrameLevel(btn:GetFrameLevel() + 5)
    local queueOvBg = SolidTex(queueOv, "BACKGROUND", 0, 0, 0, 0.75)
    queueOvBg:SetAllPoints()
    local queueOvTxt = MFont(queueOv, 11, "OUTLINE", 1, 1, 1, 0.9)
    queueOvTxt:SetPoint("CENTER", queueOv, "CENTER", 0, 0)
    queueOvTxt:SetText("In Queue")
    queueOv:Hide()
    btn.selHL = queueOv
    -- Top-left: slot name
    local sLbl = MFont(btn, 12, "OUTLINE", 0.9, 0.9, 0.9, 1)
    PP.Point(sLbl, "TOPLEFT", btn, "TOPLEFT", 7, -4)
    PP.Width(sLbl, TILE_W - 82)
    sLbl:SetJustifyH("LEFT")
    btn.sLbl = sLbl
    -- Top-right: current ^ max ilvl
    local iLbl = MFont(btn, 11, "OUTLINE", 0.8, 0.8, 0.8, 1)
    PP.Point(iLbl, "TOPRIGHT", btn, "TOPRIGHT", -5, -4)
    PP.Width(iLbl, 76)
    iLbl:SetJustifyH("RIGHT")
    btn.iLbl = iLbl
    -- Bottom-left: track name
    local tLbl = MFont(btn, 11, "OUTLINE", 0.55, 0.55, 0.55, 1)
    PP.Point(tLbl, "BOTTOMLEFT", btn, "BOTTOMLEFT", 7, 5)
    PP.Width(tLbl, TILE_W - 82)
    tLbl:SetJustifyH("LEFT")
    btn.tLbl = tLbl
    -- Bottom-right: rank badge
    local rLbl = MFont(btn, 11, "OUTLINE", 0.8, 0.8, 0.8, 1)
    PP.Point(rLbl, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
    PP.Width(rLbl, 76)
    rLbl:SetJustifyH("RIGHT")
    btn.rLbl = rLbl

    btn.tileEntry = nil

    -- Handlers wired ONCE here — no closures created during refresh.
    btn:SetScript("OnClick", function(self)
        if self.tileEntry then ToggleTileQueue(self.tileEntry, self) end
    end)
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.1)
        local e = self.tileEntry
        if not e or not EUI.ShowWidgetTooltip then return end
        local lines = {}
        if e.isAtMax then
            lines[#lines + 1] = "|cff20c020At maximum item level|r"
        elseif e.trackKey == "Crafted" then
            lines[#lines + 1] = "Crafted item — cannot be upgraded here"
        elseif e.trackKey then
            local td = Data.tracks[e.trackKey]
            local snap = DB()
            local sc = snap.calibrated and snap.cache.slots[e.slotID] or nil
            -- Discard cached entry if the item in that slot has changed since the scan.
            if sc and sc.link and sc.link ~= (GetInventoryItemLink("player", e.slotID) or "") then
                sc = nil
            end
            if sc and sc.crestAmounts and next(sc.crestAmounts) then
                for cid, amt in pairs(sc.crestAmounts) do
                    local cn = _currIDToCrestName[cid]
                    if cn and amt > 0 then
                        lines[#lines + 1] = amt .. "x  " .. cn
                    end
                end
            elseif (e.crestCost or 0) > 0 then
                lines[#lines + 1] = "~" .. e.crestCost .. "x  " .. (td and td.crestName or "Crest")
                lines[#lines + 1] = "|cff888888Scan at Upgrader for exact costs|r"
            end
        end
        if #lines > 0 then
            EUI.ShowWidgetTooltip(self, table.concat(lines, "\n"))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        local e = self.tileEntry
        if not e then return end
        if e.isAtMax then
            self.bg:SetColorTexture(0.1, 0.4, 0.1, 0.2)
        elseif type(e.max) == "number" and (e.max - e.ilvl) >= 10 then
            self.bg:SetColorTexture(0.5, 0.1, 0.1, 0.2)
        else
            self.bg:SetColorTexture(0.5, 0.35, 0.05, 0.2)
        end
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    tileFrames[i] = btn
end

-- Section header labels and group separator line (repositioned each refresh)
local sHdrNeeds    = MFont(cc, 11, "OUTLINE", 1, 1, 1, 1)
local sHdrMax      = MFont(cc, 10, "OUTLINE", 0.48, 0.48, 0.48, 1)
local groupSepLine = SolidTex(cc, "BORDER", 0.2, 0.2, 0.2, 1)
groupSepLine:SetHeight(PP.mult)
PP.Width(groupSepLine, TILE_ROW_W)


-- ── Queue panel ──────────────────────────────────────────────────────────────────
local queuePane = CreateFrame("Frame", nil, cc)
PP.Size(queuePane, QUEUE_W, FRAME_H - 140)
PP.Point(queuePane, "TOPLEFT", cc, "TOPLEFT", QUEUE_X_OFF, -10)

local qHdrLbl = MFont(queuePane, 11, "OUTLINE", 1, 1, 1, 1)
PP.Point(qHdrLbl, "TOPLEFT", queuePane, "TOPLEFT", 0, 0)
qHdrLbl:SetText("Upgrade Queue")

-- Sort-by-crest button sits in the header bar, right-aligned (swaps with qSubLbl)
local qSortBtn = CreateFrame("Button", nil, queuePane)
qSortBtn:SetHeight(16)
local qSortTxt = MFont(qSortBtn, 11, "OUTLINE", 1, 1, 1, 0.75)
qSortTxt:SetPoint("RIGHT", qSortBtn, "RIGHT", 0, 0)
qSortTxt:SetText("Sort")
qSortBtn:SetWidth(qSortTxt:GetStringWidth() + 4)
PP.Point(qSortBtn, "RIGHT", queuePane, "RIGHT", 0, 0)
qSortBtn:SetPoint("TOP", queuePane, "TOP", 0, 0)
qSortBtn:SetScript("OnEnter", function(self)
    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Sort queue by crest type (cheapest first)") end
end)
qSortBtn:SetScript("OnLeave", function()
    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
end)
qSortBtn:Hide()  -- shown only when queue has items

local qHdrSep = CreateFrame("Frame", nil, queuePane)
qHdrSep:SetPoint("TOPLEFT",  queuePane, "TOPLEFT",  0, -18)
qHdrSep:SetPoint("TOPRIGHT", queuePane, "TOPRIGHT", 0, -18)
qHdrSep:SetHeight(math.max(PP.mult, 1))
qHdrSep:SetFrameLevel(queuePane:GetFrameLevel() + 5)
local qHdrSepTex = qHdrSep:CreateTexture(nil, "OVERLAY")
qHdrSepTex:SetAllPoints()
qHdrSepTex:SetColorTexture(1, 1, 1, 0.15)

local qEmptyLbl = MFont(queuePane, 10, "OUTLINE", 0.32, 0.32, 0.32, 1)
PP.Point(qEmptyLbl, "TOPLEFT", queuePane, "TOPLEFT", 4, -23)
qEmptyLbl:SetText("No items queued, click tiles to add an item to queue.")

-- 16 pre-created queue entry rows
local queueEntries = {}
local Q_ROW_H = 20
local Q_ROW_STEP = Q_ROW_H + PP.mult  -- row height + 1 physical pixel gap
for i = 1, 16 do
    local ef = CreateFrame("Frame", nil, queuePane)
    PP.Size(ef, QUEUE_W, Q_ROW_H)
    PP.Point(ef, "TOPLEFT", queuePane, "TOPLEFT", 0, -(23 + (i - 1) * Q_ROW_STEP))
    ef:Hide()
    local ebg = SolidTex(ef, "BACKGROUND", 1, 1, 1, 0.05)
    ebg:SetAllPoints(ef)
    local nLbl = MFont(ef, 10, "OUTLINE", 0.8, 0.8, 0.8, 1)
    PP.Point(nLbl, "LEFT", ef, "LEFT", 4, 0)
    PP.Width(nLbl, QUEUE_W - 84)
    nLbl:SetJustifyH("LEFT")
    local cLbl = MFont(ef, 10, nil, 0.8, 0.8, 0.8, 1)
    PP.Point(cLbl, "RIGHT", ef, "RIGHT", -4, 0)
    PP.Width(cLbl, 82)
    cLbl:SetJustifyH("RIGHT")
    ef.nLbl = nLbl; ef.cLbl = cLbl
    queueEntries[i] = ef
end

local qTotalSep = CreateFrame("Frame", nil, queuePane)
qTotalSep:SetPoint("TOPLEFT",  queuePane, "TOPLEFT",  0, -42)
qTotalSep:SetPoint("TOPRIGHT", queuePane, "TOPRIGHT", 0, -42)
qTotalSep:SetHeight(math.max(PP.mult, 1))
qTotalSep:SetFrameLevel(queuePane:GetFrameLevel() + 5)
local qTotalSepTex = qTotalSep:CreateTexture(nil, "OVERLAY")
qTotalSepTex:SetAllPoints()
qTotalSepTex:SetColorTexture(1, 1, 1, 0.15)
qTotalSep:Hide()

local qTotalLbl = MFont(queuePane, 10, "OUTLINE", G.r, G.g, G.b, 1)
PP.Point(qTotalLbl, "TOPRIGHT", queuePane, "TOPRIGHT", -4, -46)
qTotalLbl:SetJustifyH("RIGHT")
qTotalLbl:SetText("")
qTotalLbl:Hide()

local qClearBtn = MakeButton(queuePane, "Clear Queue", QUEUE_W - 6, 20, -70, 0)
qClearBtn:Hide()


-- Queue state
local queueItems   = {}   -- ordered list of tileEntry tables
local queueSlotSet = {}   -- slotName -> position in queueItems
local _queueLoaded = false  -- true once saved queue has been applied after session start

local crestManualAdds = { ["Hero Crest"] = 0, ["Myth Crest"] = 0 }

-- Persist the current queue (slot IDs only) to the profile DB.
local function SaveQueue()
    local db = DB()
    db.queue = {}
    for i, it in ipairs(queueItems) do db.queue[i] = it.slotID end
end

-- Persist the current crest manual-add offsets to the profile DB.
local function SaveCrestManualAdds()
    local db = DB()
    db.crestManualAdds = db.crestManualAdds or {}
    for k, v in pairs(crestManualAdds) do db.crestManualAdds[k] = v end
end

local function UpdateQueueDisplay()
    local n = #queueItems
    qEmptyLbl:SetText(n == 0 and "No items queued, click tiles to add an item to queue." or "")
    if n > 0 then qSortBtn:Show() else qSortBtn:Hide() end

    local totalCrests = {}
    for i, entry in ipairs(queueItems) do
        local qe = queueEntries[i]
        qe:Show()
        local parts = {}
        if entry.trackKey and entry.trackKey ~= "Crafted" then
            local td = Data.tracks[entry.trackKey]
            if td and (entry.crestCost or 0) > 0 then
                parts[#parts + 1] = entry.crestCost .. " " ..
                    (td.crestName or entry.trackKey):gsub(" Crest", "")
                totalCrests[td.crestName] = (totalCrests[td.crestName] or 0) + entry.crestCost
            end
        end
        local costStr = #parts > 0 and table.concat(parts, " ") or "|cff20c020Max|r"
        local gain = (not entry.isAtMax and type(entry.max) == "number" and entry.max > entry.ilvl)
            and (entry.max - entry.ilvl) or nil
        local nameStr = gain and (entry.slotName .. " |cff888888+" .. gain .. "|r") or entry.slotName
        qe.nLbl:SetText(nameStr)
        qe.cLbl:SetText(costStr)
    end
    for i = n + 1, 16 do queueEntries[i]:Hide() end

    if n > 0 then
        local parts = {}
        for _, trackName in ipairs(Data.trackOrder) do
            local td   = Data.tracks[trackName]
            local ckey = td and td.crestName or trackName
            local amt  = totalCrests[ckey] or 0
            if amt > 0 then parts[#parts + 1] = amt .. " " .. ckey:gsub(" Crest", "") end
        end

        local sepY = -(23 + n * Q_ROW_STEP + 6)
        qTotalSep:ClearAllPoints()
        PP.Point(qTotalSep, "TOPLEFT",  queuePane, "TOPLEFT",  0, sepY)
        PP.Point(qTotalSep, "TOPRIGHT", queuePane, "TOPRIGHT", 0, sepY)
        qTotalSep:SetHeight(math.max(PP.mult, 1))
        qTotalLbl:ClearAllPoints()
        PP.Point(qTotalLbl, "TOPRIGHT", queuePane, "TOPRIGHT", -4, sepY - 6)
        qClearBtn:ClearAllPoints()
        PP.Point(qClearBtn, "TOPLEFT", queuePane, "TOPLEFT", 0, sepY - 28)

        qTotalLbl:SetText(#parts > 0 and table.concat(parts, "  ") or "Nothing needed")
        qTotalLbl:Show(); qTotalSep:Show(); qClearBtn:Show()
    else
        qTotalLbl:Hide(); qTotalSep:Hide(); qClearBtn:Hide()
    end
end

-- Sort the queue by crest tier (cheapest/lowest first: Adventurer→Myth→Crafted).
local function SortQueueByCrest()
    if #queueItems == 0 then return end
    local trackIdx = {}
    for i, tn in ipairs(Data.trackOrder) do trackIdx[tn] = i end
    table.sort(queueItems, function(a, b)
        -- No crest cost sorts first (0), then by track order, unknowns last.
        local ia = (a.crestCost or 0) == 0 and 0 or (trackIdx[a.trackKey] or 99)
        local ib = (b.crestCost or 0) == 0 and 0 or (trackIdx[b.trackKey] or 99)
        if ia ~= ib then return ia < ib end
        return (a.slotID or 0) < (b.slotID or 0)
    end)
    queueSlotSet = {}
    for i, it in ipairs(queueItems) do queueSlotSet[it.slotName] = i end
    UpdateQueueDisplay()
    SaveQueue()
end

qSortBtn:SetScript("OnClick", SortQueueByCrest)

ToggleTileQueue = function(entry, btn)
    local sn = entry.slotName
    if queueSlotSet[sn] then
        local idx = queueSlotSet[sn]
        table.remove(queueItems, idx)
        queueSlotSet = {}
        for i, it in ipairs(queueItems) do queueSlotSet[it.slotName] = i end
        btn.selHL:Hide()
    else
        queueItems[#queueItems + 1] = entry
        queueSlotSet[sn] = #queueItems
        btn.selHL:Show()
    end
    UpdateQueueDisplay()
    SaveQueue()
end

qClearBtn:SetScript("OnClick", function()
    queueItems   = {}
    queueSlotSet = {}
    for _, btn in ipairs(tileFrames) do btn.selHL:Hide() end
    UpdateQueueDisplay()
    SaveQueue()
end)

-- ── Crest section — parented to a repositionable container frame ──────────────
-- crestSection is moved each PopulateGear so the window height stays tight.
local crestSection = CreateFrame("Frame", nil, cc)
PP.Point(crestSection, "TOPLEFT",  cc, "TOPLEFT",  0, -430)  -- initial; overwritten each refresh
PP.Point(crestSection, "TOPRIGHT", cc, "TOPRIGHT", 0, -430)
PP.Height(crestSection, 200)  -- large enough; content determines visible area

local gearSep = SolidTex(crestSection, "BORDER", 0.2, 0.2, 0.2, 1)
PP.Point(gearSep, "TOPLEFT",  crestSection, "TOPLEFT",  0, 4)
PP.Point(gearSep, "TOPRIGHT", crestSection, "TOPRIGHT", 0, 4)
gearSep:SetHeight(PP.mult)

-- Forward-declared so buttons can call it.
local PopulateGear

-- Summary text labels
local missingLbl = MFont(crestSection, 11, "OUTLINE", 1, 1, 1, 1)
PP.Point(missingLbl, "TOPLEFT", crestSection, "TOPLEFT", 4, 0)
missingLbl:SetJustifyH("LEFT")
missingLbl:SetText("Total Missing Upgrades: -")

local crestsLbl = MFont(crestSection, 11, "OUTLINE", 1, 1, 1, 1)
PP.Point(crestsLbl, "TOPLEFT", missingLbl, "BOTTOMLEFT", 0, -4)
PP.Width(crestsLbl, TILE_ROW_W)
crestsLbl:SetJustifyH("LEFT")
crestsLbl:SetText("Total Crests Needed: -")

local refreshBtn               = MakeButton(crestSection, "Refresh",            140, 22, 0, 0)
local scanBtn, scanBtnTxt      = MakeButton(crestSection, "Update at Upgrader", 160, 22, 0, 150)

-- ── Per-track crest breakdown table ─────────────────────────────────────────
-- Rows are pre-created once; repositioned and populated each PopulateGear.
local CROW_H   = 20
local CROW_STEP = CROW_H + 1

local CC_NAME_X, CC_NAME_W = 0,   110
local CC_NEED_X, CC_NEED_W = 115,  65
local CC_OWN_X,  CC_OWN_W  = 185,  65
local CC_EARN_X, CC_EARN_W = 255, 100
local CC_REM_X,  CC_REM_W  = 360,  90
local CC_BTN_W             = 40
local CC_MINUS_X           = TILE_ROW_W - CC_BTN_W * 2 - 5
local CC_PLUS_X            = TILE_ROW_W - CC_BTN_W

local crestTblHdr = CreateFrame("Frame", nil, crestSection)
PP.Size(crestTblHdr, TILE_ROW_W, CROW_H)
local cHdrBg = SolidTex(crestTblHdr, "BACKGROUND", 0, 0, 0, 0.35)
cHdrBg:SetAllPoints()
local function MakeCHdr(parent, text, x, w, align)
    local lbl = MFont(parent, 10, "OUTLINE", 1, 1, 1, 0.9)
    PP.Point(lbl, "LEFT", parent, "TOPLEFT", x + 4, -CROW_H / 2)
    PP.Width(lbl, w - 8)
    lbl:SetJustifyH(align or "LEFT")
    lbl:SetText(text)
    return lbl
end
MakeCHdr(crestTblHdr, "Crest",       CC_NAME_X, CC_NAME_W, "LEFT")
MakeCHdr(crestTblHdr, "Needed",      CC_NEED_X, CC_NEED_W, "RIGHT")
MakeCHdr(crestTblHdr, "Owned",       CC_OWN_X,  CC_OWN_W,  "RIGHT")
local cHdrEarn = MakeCHdr(crestTblHdr, "Earned/Cap",  CC_EARN_X, CC_EARN_W, "RIGHT")
local cHdrRem  = MakeCHdr(crestTblHdr, "Still Avail", CC_REM_X,  CC_REM_W,  "RIGHT")
crestTblHdr:Hide()

local crestTableRows = {}
for ri, trackName in ipairs(Data.trackOrder) do
    local td       = Data.tracks[trackName]
    local crestKey = td and td.crestName or (trackName .. " Crest")
    local row      = CreateFrame("Frame", nil, crestSection)
    PP.Size(row, TILE_ROW_W, CROW_H)
    if ri % 2 == 0 then
        local altBg = SolidTex(row, "BACKGROUND", 0, 0, 0, 0.15)
        altBg:SetAllPoints()
    end
    local function MakeCell(x, w, align)
        local lbl = MFont(row, 11, nil, 0.85, 0.85, 0.85, 1)
        PP.Point(lbl, "TOPLEFT", row, "TOPLEFT", x + 4, -3)
        PP.Width(lbl, w - 8)
        lbl:SetJustifyH(align or "LEFT")
        lbl:SetText("-")
        return lbl
    end
    local hexColor = td and td.hexColor or "|cffffffff"
    local nameLbl  = MFont(row, 11, nil, 0.85, 0.85, 0.85, 1)
    PP.Point(nameLbl, "TOPLEFT", row, "TOPLEFT", CC_NAME_X + 4, -3)
    PP.Width(nameLbl, CC_NAME_W - 8)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetText(hexColor .. trackName .. "|r")
    local needLbl = MakeCell(CC_NEED_X, CC_NEED_W, "RIGHT")
    local ownLbl  = MakeCell(CC_OWN_X,  CC_OWN_W,  "RIGHT")
    local earnLbl = MakeCell(CC_EARN_X, CC_EARN_W, "RIGHT")
    local remLbl  = MakeCell(CC_REM_X,  CC_REM_W,  "RIGHT")
    local minusBtn, plusBtn
    if trackName == "Hero" or trackName == "Myth" then
        minusBtn = MakeButton(row, "-80", CC_BTN_W, CROW_H - 4, -2, CC_MINUS_X)
        plusBtn  = MakeButton(row, "+80", CC_BTN_W, CROW_H - 4, -2, CC_PLUS_X)
        do
            local ck = crestKey
            minusBtn:SetScript("OnClick", function()
                crestManualAdds[ck] = math.max(0, (crestManualAdds[ck] or 0) - 80)
                SaveCrestManualAdds(); PopulateGear()
            end)
            plusBtn:SetScript("OnClick", function()
                crestManualAdds[ck] = (crestManualAdds[ck] or 0) + 80
                SaveCrestManualAdds(); PopulateGear()
            end)
        end
    end
    row:Hide()
    crestTableRows[ri] = {
        frame     = row,
        trackName = trackName,
        crestKey  = crestKey,
        needLbl   = needLbl,
        ownLbl    = ownLbl,
        earnLbl   = earnLbl,
        remLbl    = remLbl,
        minusBtn  = minusBtn,
        plusBtn   = plusBtn,
    }
end

-- ── PopulateGear ──────────────────────────────────────────────────────────────
PopulateGear = function()
    local gear  = Calc:GetEquippedGear()
    local owned = Calc:GetPlayerCrests()
    local totalMissing, crestNeeds = 0, {}
    local tileEntries = {}

    -- Pre-pass: compute the theoretical max ilvl across ALL equipped slots,
    -- deliberately ignoring slotFilter and hideCrafted so the timeline bar and
    -- "Max Possible" stat always reflect the full character potential.
    -- Running this first also warms _tipCache so the display loop below pays no
    -- extra tooltip scanning cost.
    local maxTotal = 0
    for _, item in ipairs(gear) do
        local pOk, _, _, _, _, maxIlvl = pcall(Calc.GetItemUpgradeCost, Calc, item)
        if pOk and type(maxIlvl) == "number" then
            maxTotal = maxTotal + maxIlvl
        elseif Calc:IsVoidforged(item.link) then
            maxTotal = maxTotal + item.ilvl
        elseif item.ilvl >= 200 then
            local _, maxI = CraftedBandFromIlvl(item.ilvl)
            maxTotal = maxTotal + maxI
        else
            maxTotal = maxTotal + item.ilvl
        end
    end

    -- Pre-build per-slot crest breakdown from scan data.
    -- Done once here from a single DB snapshot so every item in the loop
    -- sees a consistent view of the cache with no per-item DB reads.
    -- Link validation: skip any slot whose cached link doesn't match current gear.
    local slotCrestMap = {}
    local dbSnap = DB()
    if dbSnap.calibrated then
        for slotID, sc in pairs(dbSnap.cache.slots or {}) do
            local currentLink = GetInventoryItemLink("player", slotID)
            if sc and sc.crestAmounts and sc.link == currentLink then
                local byName = {}
                for cid, amt in pairs(sc.crestAmounts) do
                    local cn = _currIDToCrestName[cid]
                    if cn and amt > 0 then byName[cn] = (byName[cn] or 0) + amt end
                end
                if next(byName) then slotCrestMap[slotID] = byName end
            end
        end
    end
    -- Read persistent settings once per refresh
    local opts         = Opts()
    local hideCrafted  = opts.hideCrafted
    local showMaxed    = opts.showMaxed
    local slotFilter   = opts.slotFilter   -- table of group -> bool (nil = all shown)
    local crestFilter         = opts.crestFilter         -- table of trackName -> bool (nil/true = shown)
    local showEarnedCap       = opts.showEarnedCap
    local showWeeklyRemaining = opts.showWeeklyRemaining

    -- Build per-slot data
    for _, item in ipairs(gear) do
        local grp = Data.slotToGroup[item.slot]
        if not (slotFilter and grp and slotFilter[grp] == false) then
            local sn = Data.slotNames[item.slot] or ("Slot " .. item.slot)
            local pOk, pa, pb, pc, pd, pe, pf = pcall(Calc.GetItemUpgradeCost, Calc, item)
            local track, rank, crestCost, maxIlvl, craftLabel
            if pOk then track, rank, crestCost, maxIlvl, craftLabel = pa, pb, pc, pd, pe end
            local dt, dm, du = "-", "-", "-"
            local isAtMax, shouldAdd = false, true

            if track == "Crafted" then
                if hideCrafted then
                    shouldAdd = false
                else
                    dt = craftLabel or "Crafted"; dm = maxIlvl or item.ilvl
                    isAtMax = true
                    du = "Crafted"
                end
            elseif track then
                local td = Data.tracks[track]
                totalMissing = totalMissing + ((td and #td.ranks or 6) - (rank or 0))
                local cn_map = slotCrestMap[item.slot]
                if cn_map then
                    for cn, amt in pairs(cn_map) do
                        crestNeeds[cn] = (crestNeeds[cn] or 0) + amt
                    end
                elseif td and (crestCost or 0) > 0 then
                    crestNeeds[td.crestName] = (crestNeeds[td.crestName] or 0) + crestCost
                end
                dt = track; dm = maxIlvl or item.ilvl
                du = rank and (rank .. "/" .. (td and #td.ranks or 6)) or "-"
                isAtMax = (rank == (td and #td.ranks or 6))
            else
                if Calc:IsVoidforged(item.link) then
                    dt = "Voidforged"; dm = item.ilvl; du = "Max"; isAtMax = true
                elseif item.ilvl >= 200 then
                    -- Use the shared helper so thresholds stay in one place.
                    local band, maxI = CraftedBandFromIlvl(item.ilvl)
                    local label = band == "Myth" and "Myth Craft"
                               or band == "Hero" and "Hero Craft" or "Crafted"
                    dt = label; dm = maxI
                    du = item.ilvl >= maxI and "Max" or "-"
                    isAtMax = item.ilvl >= maxI
                else
                    dm = item.ilvl; isAtMax = true
                end
            end

            if shouldAdd then
                tileEntries[#tileEntries + 1] = {
                    slotName = sn,       slotID  = item.slot,
                    ilvl     = item.ilvl, max    = dm,
                    upgrade  = du,       trackName = dt,
                    isAtMax  = isAtMax,  trackKey  = track,
                    crestCost = crestCost,
                }
            end
        end
    end

    -- Fold in manual crest additions (from the +/-80 buttons on Hero/Myth rows)
    for ckey, amt in pairs(crestManualAdds) do
        if (amt or 0) > 0 then
            crestNeeds[ckey] = (crestNeeds[ckey] or 0) + amt
        end
    end

    -- Sort: needs-upgrades first, then at-max. Within each group follow character sheet slot order.
    table.sort(tileEntries, function(a, b)
        if a.isAtMax ~= b.isAtMax then return not a.isAtMax end
        return a.slotID < b.slotID
    end)

    -- Restore queue from DB on the first PopulateGear call after a session start.
    -- We only do this once (_queueLoaded guard) so that subsequent Refresh calls
    -- don't overwrite in-session queue changes the user has made.
    if not _queueLoaded then
        _queueLoaded = true
        local savedSlots = DB().queue
        if savedSlots and #savedSlots > 0 then
            local slotToEntry = {}
            for _, e in ipairs(tileEntries) do slotToEntry[e.slotID] = e end
            queueItems = {}; queueSlotSet = {}
            for _, slotID in ipairs(savedSlots) do
                local e = slotToEntry[slotID]
                if e and not queueSlotSet[e.slotName] then
                    queueItems[#queueItems + 1] = e
                    queueSlotSet[e.slotName] = #queueItems
                end
            end
        end
    end

    -- On every refresh, sync queue item references to the current tileEntries so
    -- UpdateQueueDisplay shows live costs rather than costs snapshotted at session open.
    -- Also prunes entries whose slot is now at max rank (tile hidden, can't be clicked
    -- to dequeue — e.g. equipped a fully-upgraded item in that slot).
    -- Safe to run on the first PopulateGear call too (entries are already fresh then).
    if #queueItems > 0 then
        local slotToEntry = {}
        for _, e in ipairs(tileEntries) do slotToEntry[e.slotID] = e end
        local newQueue, newSet = {}, {}
        for _, old in ipairs(queueItems) do
            local fresh = slotToEntry[old.slotID]
            if fresh and not fresh.isAtMax then
                newQueue[#newQueue + 1] = fresh
                newSet[fresh.slotName] = #newQueue
            end
        end
        local pruned = (#newQueue ~= #queueItems)
        queueItems   = newQueue
        queueSlotSet = newSet
        if pruned then
            -- At least one entry was pruned; persist the trimmed queue.
            SaveQueue()
        end
    end

    -- Timeline bar
    local curAvg = select(2, GetAverageItemLevel()) or 0
    -- Blizzard counts 2H weapons as two slots; clamp so max never shows below current.
    local maxAvg = math.max(curAvg, #gear > 0 and maxTotal / #gear or 0)
    local minBase = 200
    local frac = (maxAvg > minBase and curAvg > minBase)
        and math.min(1, (curAvg - minBase) / math.max(1, maxAvg - minBase)) or 0
    -- Defer fill width to next frame so layout has resolved tlTrack's anchor-derived width
    local capFrac = frac
    C_Timer.After(0, function()
        local trackW = tlTrack:GetWidth()
        if trackW <= 0 then trackW = 1 end
        tlFill:SetWidth(math.max(1, math.floor(capFrac * trackW)))
    end)
    local acHex = string.format("|cff%02x%02x%02x", G.r * 255, G.g * 255, G.b * 255)
    ilvlStatLbl:SetText(string.format(
        "Current iLvl: %s%.1f|r     Max Possible: %s%.1f|r",
        acHex, curAvg, acHex, maxAvg))
    ilvlEstLbl:SetText("(est)")

    -- Section header positions
    local needsCount = 0
    for _, e in ipairs(tileEntries) do if not e.isAtMax then needsCount = needsCount + 1 end end
    local maxCount  = #tileEntries - needsCount
    local needsRows = needsCount > 0 and math.ceil(needsCount / TILE_COLS) or 0

    if needsCount > 0 then
        sHdrNeeds:ClearAllPoints()
        PP.Point(sHdrNeeds, "TOPLEFT", cc, "TOPLEFT", 0, -10)
        local acH = string.format("|cff%02x%02x%02x", G.r * 255, G.g * 255, G.b * 255)
        sHdrNeeds:SetText("Upgradable Items (" .. acH .. needsCount .. "|r)")
        sHdrNeeds:Show()
    else
        sHdrNeeds:SetText(""); sHdrNeeds:Hide()
    end

    local atMaxHdrY = -10 - (needsCount > 0 and needsRows * TILE_STEP + 18 or 0)
    if maxCount > 0 and showMaxed then
        groupSepLine:ClearAllPoints()
        PP.Point(groupSepLine, "TOPLEFT", cc, "TOPLEFT", 0, atMaxHdrY - 2)
        groupSepLine:Show()
        sHdrMax:ClearAllPoints()
        PP.Point(sHdrMax, "TOPLEFT", cc, "TOPLEFT", 0, atMaxHdrY - 6)
        sHdrMax:SetText(string.format("At Max (%d)", maxCount))
        sHdrMax:Show()
    else
        groupSepLine:Hide(); sHdrMax:Hide()
    end

    -- Position and fill tile frames
    local function getTilePos(group_start_y, local_idx)
        local row = math.floor(local_idx / TILE_COLS)
        local col = local_idx % TILE_COLS
        return col * (TILE_W + TILE_GAP), group_start_y - row * TILE_STEP
    end

    local needsStartY = -28  -- below section header(~18) + gap
    local atMaxStartY = needsStartY - needsRows * TILE_STEP - (needsCount > 0 and 34 or 18)

    for _, btn in ipairs(tileFrames) do btn:Hide() end

    local ni, mi = 0, 0
    for idx, entry in ipairs(tileEntries) do
        if idx > #tileFrames then break end  -- tileFrames has 18 slots; equipSlots has 16
        local btn = tileFrames[idx]
        local tx, ty
        if not entry.isAtMax then
            tx, ty = getTilePos(needsStartY, ni); ni = ni + 1
        elseif showMaxed then
            tx, ty = getTilePos(atMaxStartY, mi); mi = mi + 1
        end
        if tx then
            btn:ClearAllPoints()
            PP.Point(btn, "TOPLEFT", cc, "TOPLEFT", tx, ty)
            btn:Show()

            -- Tile background colour by upgrade gap
            if entry.isAtMax then
                btn.bg:SetColorTexture(0.1, 0.4, 0.1, 0.2)
            elseif type(entry.max) == "number" and (entry.max - entry.ilvl) >= 10 then
                btn.bg:SetColorTexture(0.5, 0.1, 0.1, 0.2)
            else
                btn.bg:SetColorTexture(0.5, 0.35, 0.05, 0.2)
            end

            -- Left accent bar: track colour
            local rgb = (entry.trackKey and TRACK_RGB[entry.trackKey])
                   or TRACK_RGB[entry.trackName]
                   or {0.4, 0.4, 0.4}
            btn.accentBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

            -- Text labels
            btn.sLbl:SetText(entry.slotName)
            local maxStr = type(entry.max) == "number" and tostring(entry.max) or "-"
            btn.iLbl:SetText(entry.ilvl .. " (" .. maxStr .. ")")
            btn.tLbl:SetText(entry.trackName)
            btn.tLbl:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
            btn.rLbl:SetText(entry.upgrade)

            local txtA = entry.isAtMax and 0.45 or 0.9
            btn.sLbl:SetTextColor(txtA, txtA, txtA, 1)
            btn.iLbl:SetTextColor(txtA, txtA, txtA, 1)
            btn.rLbl:SetTextColor(txtA, txtA, txtA, 1)

            -- Restore queue highlight
            if queueSlotSet[entry.slotName] then btn.selHL:Show()
            else btn.selHL:Hide() end

            btn.tileEntry = entry
        end
    end

    -- Reposition the crest section immediately below the last rendered tile row.
    local crestY
    if showMaxed and maxCount > 0 then
        -- atMaxStartY is where the at-max group starts; offset by its rows + gap.
        crestY = atMaxStartY - math.ceil(maxCount / TILE_COLS) * TILE_STEP - 20
    else
        -- Only needs-upgrade tiles are visible (or none at all).
        crestY = needsStartY - needsRows * TILE_STEP - 20
    end
    crestSection:ClearAllPoints()
    PP.Point(crestSection, "TOPLEFT",  cc, "TOPLEFT",  0, crestY)
    PP.Width(crestSection, TILE_ROW_W)

    -- Summary text: Total Missing Upgrades + Total Crests Needed
    local acHex2 = string.format("|cff%02x%02x%02x", G.r * 255, G.g * 255, G.b * 255)
    missingLbl:SetText("Total Missing Upgrades: " .. acHex2 .. totalMissing .. "|r")

    local crestParts = {}
    -- Reverse order: highest tier first (Myth -> Adventurer)
    for i = #Data.trackOrder, 1, -1 do
        local trackName = Data.trackOrder[i]
        local td   = Data.tracks[trackName]
        local ckey = td and td.crestName or trackName
        local amt  = crestNeeds[ckey] or 0
        if amt > 0 then
            local hexColor = (td and td.hexColor) or "|cffffffff"
            crestParts[#crestParts + 1] = hexColor .. amt .. " " .. trackName .. "|r"
        end
    end
    local crestStr = #crestParts > 0 and table.concat(crestParts, ", ") or "None"
    local db = DB()
    local accuracyTag = db.calibrated and " |cff20ff20(exact)|r" or " |cff888888(est)|r"
    crestsLbl:SetText("Total Crests Needed" .. accuracyTag .. ": " .. crestStr)

    -- Crest breakdown table: populate rows, apply filter and optional columns
    cHdrEarn:SetShown(showEarnedCap or false)
    cHdrRem:SetShown(showWeeklyRemaining or false)

    local visRowCount = 0
    for _, rowData in ipairs(crestTableRows) do
        local tn    = rowData.trackName
        local shown = not (crestFilter and crestFilter[tn] == false)
        if shown then
            local needed  = crestNeeds[rowData.crestKey] or 0
            local ownInfo = owned[rowData.crestKey]
            rowData.needLbl:SetText(needed > 0 and tostring(needed) or "-")
            rowData.ownLbl:SetText(ownInfo and tostring(ownInfo.quantity) or "-")
            if showEarnedCap then
                if ownInfo then
                    local capStr = ownInfo.cap and tostring(ownInfo.cap) or "-"
                    rowData.earnLbl:SetText(ownInfo.earned .. " / " .. capStr)
                else
                    rowData.earnLbl:SetText("-")
                end
                rowData.earnLbl:Show()
            else
                rowData.earnLbl:Hide()
            end
            if showWeeklyRemaining then
                if ownInfo and ownInfo.cap then
                    rowData.remLbl:SetText(tostring(math.max(0, ownInfo.cap - ownInfo.earned)))
                else
                    rowData.remLbl:SetText("-")
                end
                rowData.remLbl:Show()
            else
                rowData.remLbl:Hide()
            end
            rowData.frame:ClearAllPoints()
            PP.Point(rowData.frame, "TOPLEFT", crestTblHdr, "BOTTOMLEFT", 0, -(visRowCount * CROW_STEP))
            rowData.frame:Show()
            visRowCount = visRowCount + 1
        else
            rowData.frame:Hide()
        end
    end

    -- Table sits above the buttons when rows are visible; buttons fall back to crestsLbl otherwise
    if visRowCount > 0 then
        crestTblHdr:ClearAllPoints()
        PP.Point(crestTblHdr, "TOPLEFT", crestsLbl, "BOTTOMLEFT", 4, -8)
        crestTblHdr:Show()
        refreshBtn:ClearAllPoints()
        PP.Point(refreshBtn, "TOPLEFT", crestTblHdr, "BOTTOMLEFT", -4, -(visRowCount * CROW_STEP + 10))
    else
        crestTblHdr:Hide()
        refreshBtn:ClearAllPoints()
        PP.Point(refreshBtn, "TOPLEFT", crestsLbl, "BOTTOMLEFT", -4, -10)
    end
    scanBtn:ClearAllPoints()
    PP.Point(scanBtn, "TOPLEFT", refreshBtn, "TOPRIGHT", 10, 0)

    -- Resize frame to fit content
    local CC_TOP = 66  -- distance from frame top to cc top
    local crestTblH     = visRowCount > 0 and (CROW_H + visRowCount * CROW_STEP + 8) or 0
    local crestSectionH = 14 + 14 + 10 + 22 + 10 + crestTblH  -- two text lines + gap + buttons + padding + table
    local contentH = math.abs(crestY) + crestSectionH
    local queueH = 22 + #queueItems * Q_ROW_STEP + (#queueItems > 0 and 50 or 0)
    local newFrameH = math.max(contentH, queueH) + CC_TOP + 10
    PP.Size(f, FRAME_W, newFrameH)
    PP.Size(queuePane, QUEUE_W, newFrameH - CC_TOP - 10)

    -- Sync queue panel text to match restored/refreshed queue state.
    UpdateQueueDisplay()
end

refreshBtn:SetScript("OnClick", PopulateGear)
Calc.PopulateGear = PopulateGear  -- exposed for options page live-refresh
refreshBtn:HookScript("OnEnter", function(self)
    if EUI.ShowWidgetTooltip then
        EUI.ShowWidgetTooltip(self,
            "Refresh using tooltip scan data.\n"
            .. "For exact costs, use |cffffffff'Update at Upgrader'|r\n"
            .. "while at an Item Upgrade NPC.")
    end
end)
refreshBtn:HookScript("OnLeave", function()
    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
end)

scanBtn:HookScript("OnEnter", function(self)
    if EUI.ShowWidgetTooltip then
        local tip = "Scan all equipped gear costs at the Item Upgrade NPC.\n"
                 .. "Scans each slot one at a time — this can take up to 10 seconds.\n"
                 .. "Requires the Item Upgrade window to be open."
        if not Calc:IsUpgraderOpen() then
            tip = tip .. "\n|cffff6060Item Upgrade window is not open.|r"
        end
        EUI.ShowWidgetTooltip(self, tip)
    end
end)
scanBtn:HookScript("OnLeave", function()
    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
end)

scanBtn:SetScript("OnClick", function()
    if Calc._scanning then return end
    scanBtnTxt:SetText("Scanning...")
    scanBtn:SetAlpha(0.5)
    Calc:ScanEquippedAtUpgrader(function(ok)
        scanBtnTxt:SetText("Update at Upgrader")
        scanBtn:SetAlpha(1)
        if ok then
            crestManualAdds["Hero Crest"] = 0
            crestManualAdds["Myth Crest"] = 0
            SaveCrestManualAdds()
            PopulateGear()
        end
    end)
end)

-- Debounce timer handle for PLAYER_EQUIPMENT_CHANGED: coalesces rapid gear swaps
-- (e.g. multiple pieces at once) into a single PopulateGear call.
-- Declared before equipListener so both the OnEvent and OnHide closures capture
-- the same upvalue (declaring it after would cause OnEvent to use the global slot
-- instead, making OnHide unable to cancel a pending debounce timer).
local _equipDebounce = nil

local equipListener = CreateFrame("Frame")
equipListener:SetScript("OnEvent", function(_, event, slotID)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: close the frame silently
        if f:IsShown() then f:Hide() end
        return
    end
    -- Invalidate the tip cache for the changed slot (or all if slotID is missing).
    if slotID and slotID > 0 then
        local link = GetInventoryItemLink("player", slotID)
        if link then Calc._tipCache[link] = nil end
    else
        Calc._tipCache = {}
    end
    if not f:IsShown() then return end
    -- If the Upgrader NPC is open and we have a valid slot ID, rescan just that
    -- slot so the exact post-upgrade cost is shown without a full re-scan.
    if slotID and slotID > 0 and Calc:IsUpgraderOpen() and not Calc._scanning then
        -- Invalidate the slot's cache entry so PopulateGear won't stale-serve
        -- the old data while the rescan is in flight.
        local db = DB()
        if db.cache and db.cache.slots then
            db.cache.slots[slotID] = nil
        end
        Calc:RescanSlot(slotID, function()
            if f:IsShown() then PopulateGear() end
        end)
        return
    end
    -- Debounce: wait 0.3 s after the last equip event before refreshing.
    -- This prevents hammering PopulateGear when the user swaps multiple pieces.
    if _equipDebounce then _equipDebounce:Cancel() end
    _equipDebounce = C_Timer.NewTimer(0.3, function()
        _equipDebounce = nil
        if f:IsShown() then PopulateGear() end
    end)
end)

-- Show / Hide

f:SetScript("OnShow", function()
    if IsLocked() then f:Hide(); return end
    Calc.ApplyBgOpacity()
    Calc.ApplyScale()
    -- Reload persisted crest manual-add offsets each time the frame opens,
    -- so that values the user set before logging out are visible immediately.
    local dbAdds = DB().crestManualAdds
    for k in pairs(crestManualAdds) do
        crestManualAdds[k] = (dbAdds and dbAdds[k]) or 0
    end
    equipListener:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    equipListener:RegisterEvent("PLAYER_REGEN_DISABLED")
    PopulateGear()
end)
f:SetScript("OnHide", function()
    equipListener:UnregisterAllEvents()
    -- Cancel any pending equipment-change debounce.
    if _equipDebounce then _equipDebounce:Cancel(); _equipDebounce = nil end
    -- If hidden mid-scan (e.g. combat, /reload), unblock future scans.
    Calc._scanning = false
    Calc._tipCache = {}
    -- crestManualAdds are now persisted to DB; no longer reset on hide.
end)

SLASH_EUIUPGCALC1 = "/euic"
SLASH_EUIUPGCALC2 = "/upgcalc"
SLASH_EUIUPGCALC3 = "/eec"
SlashCmdList["EUIUPGCALC"] = function()
    if IsLocked() then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- ── Profile integration + first-run crest filter ────────────────────────────
-- On PLAYER_LOGIN we call NewDB so our data lives inside EllesmereUIDB.profiles
-- (the same place Cursor, BattleRes etc store theirs).  Without this, NewDB
-- wipes EllesmereUIQoLDB and our saved data is lost every session.
-- The first-run filter runs once (guarded by opts.firstRunDone) to auto-hide
-- crest tracks that have no upgradeable items on the player's current gear.
local _firstRunEvt = CreateFrame("Frame")
_firstRunEvt:RegisterEvent("PLAYER_LOGIN")
_firstRunEvt:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    -- Register with the escape proxy system (available after PLAYER_LOGIN)
    if EUI.RegisterEscapeClose then EUI.RegisterEscapeClose(f) end
    -- Register with the profile system; this MUST happen before Opts()/DB() are
    -- called so data is read from / written to the correct persistent location.
    if EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB then
        local profileDB = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", {
            profile = {
                upgradeCalcOpts = {},
                chars           = {},
            },
        })
        _euicProfileRef = profileDB.profile
        -- Store character data under a per-character key so alts on the same
        -- profile each have their own queue, scan cache, and crest offsets.
        local charKey = UnitName("player") .. " - " .. GetRealmName()
        local store = _euicProfileRef
        store.chars             = store.chars           or {}
        store.chars[charKey]    = store.chars[charKey]  or {}
        local charStore         = store.chars[charKey]
        charStore.upgradeCalc   = charStore.upgradeCalc or {}
        local db                = charStore.upgradeCalc
        db.cache                = db.cache              or { slots = {}, ts = 0 }
        db.calibrated           = db.calibrated         or false
        db.queue                = db.queue              or {}
        db.crestManualAdds      = db.crestManualAdds    or {}
        store.upgradeCalcOpts   = store.upgradeCalcOpts or {}
        _dbCache   = db
        _optsCache = store.upgradeCalcOpts
    end
    local opts = Opts()
    if opts.firstRunDone then return end
    -- Brief delay so the client has fully loaded item data before tooltip scanning.
    C_Timer.After(1.5, function()
        opts.firstRunDone = true
        local tracksNeeded = {}
        for _, slotID in ipairs(Data.equipSlots) do
            local link = GetInventoryItemLink("player", slotID)
            if link then
                local r = Calc:ScanItemLink(link)
                local td = r and r.track and Data.tracks[r.track]
                if td and (r.rank or 0) < #td.ranks then
                    tracksNeeded[r.track] = true
                end
            end
        end
        -- Only apply a filter if at least one track can be hidden.
        local anyHidden = false
        for _, tn in ipairs(Data.trackOrder) do
            if not tracksNeeded[tn] then anyHidden = true; break end
        end
        if anyHidden then
            opts.crestFilter = opts.crestFilter or {}
            for _, tn in ipairs(Data.trackOrder) do
                if not tracksNeeded[tn] then
                    opts.crestFilter[tn] = false
                end
            end
        end
    end)
end)
