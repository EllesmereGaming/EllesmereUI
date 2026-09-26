if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Character Sheet on WoW Forever
--
--  The retail character sheet gets the full makeover
--  (EllesmereUIBlizzardSkin_CharacterSheet.lua); that file stands down on the
--  Forever client and this one gives the sheet the ordinary window-skin
--  treatment instead, on Blizzard's own Forever frame:
--    - the standard window shell (dark backdrop, border, top bar) and the
--      house close button, through the same engine calls every skinned
--      Blizzard window uses;
--    - every piece of frame art stripped: the pane backdrops and stone
--      header, the item slot frames, the class icon and its ring, the level
--      text plate, the right-pane collapse arrow;
--    - the retail sheet's model backdrop behind the character, cover-cropped
--      to the model area, and the retail sidebar's darker panel behind the
--      stats (its left edge is the divider between the two panes);
--    - the item slots as on retail: icons cropped by the Icon Zoom setting,
--      a grey square behind each and a 2px border in the item's quality
--      colour (dark grey when empty), recoloured through Blizzard's own
--      per-slot update;
--    - text beside each slot where retail shows its item level and upgrade
--      track (neither means much on Forever): the item's main and secondary
--      stat, or its armor when it has no stats, a weapon's damage per second
--      under that, and the enchant name under those, painted through the
--      same per-slot update; retail's top-left eyeball hides it all for the
--      session;
--    - the character name and the "Level N Class" line in the house font,
--      as on retail (Blizzard keeps writing the text, so the class colour
--      and the pvp title still come from the client);
--    - the stats list stays Blizzard's list on Blizzard's scrollbar, whose
--      track and thumb take the house thin style in place (arrows kept);
--      its category headers and values take the retail sidebar's colour
--      system (per-category colours, the user's overrides from the options
--      page, the thin header bars) through the scroll box's own frame
--      callbacks, never by touching its data.
--
--  Cost: a one-time pass at login on frames that already exist, then a
--  recolour per element initialisation (what Blizzard does anyway on each
--  stats refresh) and one colour compare plus one item-link compare per slot
--  update (Blizzard's own, only while the slots are shown). The one event of
--  our own, GET_ITEM_INFO_RECEIVED, is registered only while a shown slot
--  waits on item data the client has not cached yet.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

local function Enabled()
    if not EllesmereUIDB then return true end
    if EllesmereUIDB.themedCharacterSheet == false then return false end
    if EllesmereUI.BlizzWindowSkinsKilled and EllesmereUI.BlizzWindowSkinsKilled() then return false end
    return true
end

local function FontPath()
    return (EllesmereUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
end

local MEDIA = "Interface\\AddOns\\EllesmereUIBlizzardSkin\\Media\\"

-- The retail sheet's Icon Zoom setting (same key, same default).
local function Zoom()
    return (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07
end

-- Blizzard pieces that must go for good are parked under a hidden frame:
-- Hide() gets undone by the client's own refreshes, a hidden parent does not.
local Bin
local function Discard(region)
    if not region or not region.SetParent then return end
    if not Bin then
        Bin = CreateFrame("Frame")
        Bin:Hide()
    end
    region:SetParent(Bin)
end

--------------------------------------------------------------------------------
--  Colours: the retail sidebar's category palette, keyed the way the options
--  page stores overrides (EllesmereUIDB.statCategoryColors[key]). Forever's
--  categories map onto it; General gets its own cyan.
--------------------------------------------------------------------------------
local DEFAULT_COLORS = {
    General            = { r = 0.30,  g = 0.80,  b = 0.95 },
    Attributes         = { r = 0.047, g = 0.824, b = 0.616 },
    Attack             = { r = 1,     g = 0.353, b = 0.122 },
    ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
    Defense            = { r = 0.247, g = 0.655, b = 1 },
}
local CATEGORY_KEY = {}
if STAT_CATEGORY_GENERAL then CATEGORY_KEY[STAT_CATEGORY_GENERAL] = "General" end
if STAT_CATEGORY_PRIMARY_ATTRIBUTES then CATEGORY_KEY[STAT_CATEGORY_PRIMARY_ATTRIBUTES] = "Attributes" end
if STAT_CATEGORY_WEAPONS then CATEGORY_KEY[STAT_CATEGORY_WEAPONS] = "Attack" end
if STAT_CATEGORY_MODIFIERS then CATEGORY_KEY[STAT_CATEGORY_MODIFIERS] = "Secondary Stats" end
if STAT_CATEGORY_DEFENSE then CATEGORY_KEY[STAT_CATEGORY_DEFENSE] = "Defense" end

local function CategoryColor(categoryName)
    local key = categoryName and CATEGORY_KEY[categoryName]
    local db = EllesmereUIDB
    -- A custom colour applies only while its "use" flag is on, as on retail.
    local custom = key and db and db.statCategoryUseColor and db.statCategoryUseColor[key]
        and db.statCategoryColors and db.statCategoryColors[key]
    local c = custom or (key and DEFAULT_COLORS[key])
    if c and c.r then return c.r, c.g, c.b end
    local EG = EllesmereUI.ELLESMERE_GREEN
    if EG then return EG.r, EG.g, EG.b end
    return 1, 1, 1
end

-- The category a stat element belongs to: the data provider lists a header
-- then its rows, so it is the last header ahead of the element.
local function CategoryOf(box, elementData)
    local list = box and box.elementData
    if type(list) ~= "table" then return nil end
    local current
    for i = 1, #list do
        local d = list[i]
        if d.isHeader then current = d.name end
        if d == elementData then return current end
    end
    return current
end

--------------------------------------------------------------------------------
--  Stats list elements
--------------------------------------------------------------------------------
local function OnePixel(frame)
    local PP = EllesmereUI.PP
    local perfect = (PP and PP.perfect) or 1
    local es = frame:GetEffectiveScale()
    if not es or es <= 0 then es = 1 end
    return perfect / es
end

local function SkinHeader(frame, r, g, b)
    local d = GetFFD(frame)
    if not d.done then
        d.done = true
        if frame.Background then frame.Background:SetAlpha(0) end
        if frame.Title then
            frame.Title:SetFont(FontPath(), 11, "")
        end
        local leftBar = frame:CreateTexture(nil, "ARTWORK")
        leftBar:SetPoint("LEFT", frame, "LEFT", 8, 0)
        leftBar:SetPoint("RIGHT", frame.Title, "LEFT", -6, 0)
        d.leftBar = leftBar
        local rightBar = frame:CreateTexture(nil, "ARTWORK")
        rightBar:SetPoint("LEFT", frame.Title, "RIGHT", 6, 0)
        rightBar:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        d.rightBar = rightBar
    end
    if frame.Title then frame.Title:SetTextColor(r, g, b, 1) end
    local px = OnePixel(frame)
    d.leftBar:SetColorTexture(r, g, b, 0.8)
    d.rightBar:SetColorTexture(r, g, b, 0.8)
    d.leftBar:SetHeight(px)
    d.rightBar:SetHeight(px)
end

local function SkinRow(frame, r, g, b)
    local d = GetFFD(frame)
    if not d.done then
        d.done = true
        if frame.Background then frame.Background:SetAlpha(0) end
        if frame.Label then frame.Label:SetFont(FontPath(), 10, "") end
        if frame.Value then frame.Value:SetFont(FontPath(), 10, "") end
        -- The retail rows carry a faint divider under each line.
        local divider = frame:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.06)
        divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 0)
        divider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
        divider:SetHeight(OnePixel(frame))
        d.divider = divider
    end
    if frame.Label then frame.Label:SetTextColor(0.7, 0.7, 0.7, 0.8) end
    if frame.Value then frame.Value:SetTextColor(r, g, b, 1) end
end

local function SkinElement(box, frame, elementData)
    if not frame or not elementData then return end
    if elementData.isHeader then
        SkinHeader(frame, CategoryColor(elementData.name))
    else
        SkinRow(frame, CategoryColor(CategoryOf(box, elementData)))
    end
end

local function HookStatsList(box)
    if not box or not box.ScrollBox or GetFFD(box).hooked then return end
    GetFFD(box).hooked = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        -- The event hands (owner, frame, elementData); the helper's own
        -- iterateExisting pass hands (frame, elementData) instead, so the
        -- frames already alive are walked separately below.
        ScrollUtil.AddInitializedFrameCallback(box.ScrollBox, function(_, frame, elementData)
            SkinElement(box, frame, elementData)
        end, nil, false)
        if box.ScrollBox.ForEachFrame then
            box.ScrollBox:ForEachFrame(function(frame, elementData) SkinElement(box, frame, elementData) end)
        end
    end
end

-- Options-page refresh: colour overrides and their use flags land here, on
-- the frames alive in both lists. The retail sheet's refresher of the same
-- name is replaced (it walks retail-only state), so the swatches reach this.
local STAT_BOXES = { "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }
function EllesmereUI._refreshCharacterSheetColors()
    if not Enabled() then return end
    for i = 1, #STAT_BOXES do
        local box = _G[STAT_BOXES[i]]
        if box and box.ScrollBox and box.ScrollBox.ForEachFrame then
            box.ScrollBox:ForEachFrame(function(frame, elementData) SkinElement(box, frame, elementData) end)
        end
    end
end

--------------------------------------------------------------------------------
--  The frame
--------------------------------------------------------------------------------
local SLOTS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot", "CharacterAmmoSlot",
}

local function FadeChildren(frame, Fade)
    if not frame then return end
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and child.GetRegions and not (child.IsForbidden and child:IsForbidden()) then
            Fade(child)
        end
    end
end

-- The equipped item's quality colour; nothing when the slot is empty.
local function QualityColor(slot)
    local quality = GetInventoryItemQuality("player", slot:GetID())
    if quality and not (issecretvalue and issecretvalue(quality)) then
        local r, g, b
        if C_Item and C_Item.GetItemQualityColor then
            r, g, b = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            r, g, b = GetItemQualityColor(quality)
        end
        if r then return r, g, b end
    end
end

-- The slot border colour: the equipped item's quality, dark grey when empty
-- (the retail sheet's values).
local function SlotBorderColor(slot)
    local r, g, b = QualityColor(slot)
    if r then return r, g, b end
    return 0.4, 0.4, 0.4
end

local function ColorSlotBorder(slot)
    local PanelPP = EllesmereUI.PanelPP
    if not (PanelPP and PanelPP.SetBorderColor) then return end
    local r, g, b = SlotBorderColor(slot)
    PanelPP.SetBorderColor(slot, r, g, b, 1)
end

--------------------------------------------------------------------------------
--  Slot text where the retail sheet shows the item level and upgrade track:
--  the item's main and secondary stat, or its armor when it has no stats,
--  and the enchant name under it. It reads the retail upgrade track and
--  enchant settings keys, sizes and colours, so those options rows drive it
--  through the refreshers redefined below.
--------------------------------------------------------------------------------
local EX = 5   -- the text's near edge, off the slot edge

-- Where each slot's text sits: "R" right of it, "L" left of it, "B" below
-- it. The inner side for the two columns; the outer side for the outer
-- weapon slots (the ranged text past the ammo slot while that shows); below
-- the middle weapon slot, whose sides are taken and whose top holds the
-- flyout arrow. Shirt, tabard and ammo carry none (shirt and tabard carry
-- none on retail either).
local TEXT_SIDE = {
    CharacterHeadSlot = "R", CharacterNeckSlot = "R", CharacterShoulderSlot = "R",
    CharacterBackSlot = "R", CharacterChestSlot = "R", CharacterWristSlot = "R",
    CharacterHandsSlot = "L", CharacterWaistSlot = "L", CharacterLegsSlot = "L",
    CharacterFeetSlot = "L", CharacterFinger0Slot = "L", CharacterFinger1Slot = "L",
    CharacterTrinket0Slot = "L", CharacterTrinket1Slot = "L",
    CharacterMainHandSlot = "L", CharacterSecondaryHandSlot = "B", CharacterRangedSlot = "R",
}

-- The slots that can hold a weapon carry a dps line (painted only when the
-- item there is one).
local WEAPON_SLOT = {
    CharacterMainHandSlot = true, CharacterSecondaryHandSlot = true, CharacterRangedSlot = true,
}

-- C_Item.GetItemStats keys in tie order (an earlier key wins a tie), with our
-- own short labels. Main stat: the largest of the first three (the
-- primaries), else of the next two (Stamina, Spirit). Secondary: the largest
-- of every other listed key. Armor, shield block value, weapon damage,
-- sockets and any unlisted key never show. Built on first use, once the
-- locale catalog is active.
local STAT_LIST
local function StatList()
    if STAT_LIST then return STAT_LIST end
    local crit, hit = EllesmereUI.L("Crit"), EllesmereUI.L("Hit")
    local mp5, hp5 = EllesmereUI.L("MP5"), EllesmereUI.L("HP5")
    STAT_LIST = {
        { "ITEM_MOD_STRENGTH_SHORT",             EllesmereUI.L("Str") },
        { "ITEM_MOD_AGILITY_SHORT",              EllesmereUI.L("Agi") },
        { "ITEM_MOD_INTELLECT_SHORT",            EllesmereUI.L("Int") },
        { "ITEM_MOD_STAMINA_SHORT",              EllesmereUI.L("Stam") },
        { "ITEM_MOD_SPIRIT_SHORT",               EllesmereUI.L("Spi") },
        { "ITEM_MOD_ATTACK_POWER_SHORT",         EllesmereUI.L("AP") },
        { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",  EllesmereUI.L("RAP") },
        { "ITEM_MOD_SPELL_POWER_SHORT",          EllesmereUI.L("SP") },
        { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",    EllesmereUI.L("Spell Dmg") },
        { "ITEM_MOD_SPELL_HEALING_DONE_SHORT",   EllesmereUI.L("Heal") },
        { "ITEM_MOD_CRIT_RATING_SHORT",          crit },
        { "ITEM_MOD_CRIT_MELEE_RATING_SHORT",    crit },
        { "ITEM_MOD_CRIT_RANGED_RATING_SHORT",   crit },
        { "ITEM_MOD_CRIT_SPELL_RATING_SHORT",    EllesmereUI.L("Spell Crit") },
        { "ITEM_MOD_HIT_RATING_SHORT",           hit },
        { "ITEM_MOD_HIT_MELEE_RATING_SHORT",     hit },
        { "ITEM_MOD_HIT_RANGED_RATING_SHORT",    hit },
        { "ITEM_MOD_HIT_SPELL_RATING_SHORT",     EllesmereUI.L("Spell Hit") },
        { "ITEM_MOD_HASTE_RATING_SHORT",         EllesmereUI.L("Haste") },
        { "ITEM_MOD_MANA_REGENERATION_SHORT",    mp5 },
        { "ITEM_MOD_POWER_REGEN0_SHORT",         mp5 },
        { "ITEM_MOD_HEALTH_REGEN_SHORT",         hp5 },
        { "ITEM_MOD_HEALTH_REGENERATION_SHORT",  hp5 },
        { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", EllesmereUI.L("Def") },
        { "ITEM_MOD_DODGE_RATING_SHORT",         EllesmereUI.L("Dodge") },
        { "ITEM_MOD_PARRY_RATING_SHORT",         EllesmereUI.L("Parry") },
        { "ITEM_MOD_BLOCK_RATING_SHORT",         EllesmereUI.L("Block") },
        { "ITEM_MOD_SPELL_PENETRATION_SHORT",    EllesmereUI.L("Spell Pen") },
        { "RESISTANCE1_NAME",                    EllesmereUI.L("Holy Res") },
        { "RESISTANCE2_NAME",                    EllesmereUI.L("Fire Res") },
        { "RESISTANCE3_NAME",                    EllesmereUI.L("Nature Res") },
        { "RESISTANCE4_NAME",                    EllesmereUI.L("Frost Res") },
        { "RESISTANCE5_NAME",                    EllesmereUI.L("Shadow Res") },
        { "RESISTANCE6_NAME",                    EllesmereUI.L("Arcane Res") },
    }
    return STAT_LIST
end

-- "+14 Int / +9 Stam": main / secondary, one when only one exists; an item
-- with no listed stat shows its armor ("45 Armor"), else "". Memoized per
-- link (the link carries every input: item, suffix, enchant); an item whose
-- stats have not arrived is not recorded.
local statTextCache = {}
local armorLabel
local function StatText(link)
    local text = statTextCache[link]
    if text then return text end
    local stats = C_Item.GetItemStats(link)
    if not stats then return "" end
    local list = StatList()
    local main, mainV = nil, 0
    for i = 1, 3 do
        local v = stats[list[i][1]]
        if v and v > mainV then main, mainV = i, v end
    end
    if not main then
        for i = 4, 5 do
            local v = stats[list[i][1]]
            if v and v > mainV then main, mainV = i, v end
        end
    end
    local second, secondV = nil, 0
    for i = 1, #list do
        local v = i ~= main and stats[list[i][1]]
        if v and v > secondV then second, secondV = i, v end
    end
    if main and second then
        text = string.format("+%d %s / +%d %s", mainV, list[main][2], secondV, list[second][2])
    elseif main or second then
        text = string.format("+%d %s", main and mainV or secondV, list[main or second][2])
    else
        local armor = stats.RESISTANCE0_NAME
        if armor and armor > 0 then
            armorLabel = armorLabel or EllesmereUI.L("Armor")
            text = string.format("%d %s", armor, armorLabel)
        else
            text = ""
        end
    end
    statTextCache[link] = text
    return text
end

-- "6.3 Dps" for a weapon (item class Weapon, so never a shield or a held-in
-- off-hand item), "" for anything else. Memoized per link like the stats.
local dpsTextCache = {}
local dpsLabel
local function DpsText(link)
    local text = dpsTextCache[link]
    if text then return text end
    text = ""
    if select(6, C_Item.GetItemInfoInstant(link)) == Enum.ItemClass.Weapon then
        local stats = C_Item.GetItemStats(link)
        if not stats then return "" end
        local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
        if dps and dps > 0 then
            dpsLabel = dpsLabel or EllesmereUI.L("Dps")
            text = string.format("%.1f %s", dps, dpsLabel)
        end
    end
    dpsTextCache[link] = text
    return text
end

local function DB(key)
    local db = EllesmereUIDB
    return db and db[key]
end

-- The enchant name through the retail sheet's reader, which takes the
-- engine-tagged permanent enchant tooltip line. A vanilla line is the effect
-- itself ("+7 Agility"): the plus the reader trims goes back on, and an
-- "Enchanted: " prefix, where the client adds one, comes off.
local ENCHANT_PREFIX = ENCHANTED_TOOLTIP_LINE and ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s")
local function EnchantName(slotID)
    local text = EllesmereUI.GetEnchantText(slotID)
    if text == "" then return text end
    if ENCHANT_PREFIX and ENCHANT_PREFIX ~= "" and text:sub(1, #ENCHANT_PREFIX) == ENCHANT_PREFIX then
        text = text:sub(#ENCHANT_PREFIX + 1)
    end
    if text:find("^%d") then text = "+" .. text end
    return text
end

local textVer = 1               -- bumped by every options refresh
local pending, pendingN = {}, 0 -- SLOTS index -> itemID waiting on item data
local itemWatch                 -- GET_ITEM_INFO_RECEIVED, registered only while a slot waits

-- The stats font (and the weapon slots' dps line): the retail upgrade
-- track's size, outline and shadow keys. The enchant's font follows its
-- name mode at paint.
local function ApplyLabelFonts(d)
    local path = FontPath()
    local size = DB("charSheetUpgradeTrackSize") or 11
    local flags = DB("charSheetUpgradeTrackOutline") and "OUTLINE, SLUG" or ""
    EllesmereUI.PrimeFontShadow(d.stats, DB("charSheetUpgradeTrackShadow"))
    d.stats:SetFont(path, size, flags)
    if d.dps then
        EllesmereUI.PrimeFontShadow(d.dps, DB("charSheetUpgradeTrackShadow"))
        d.dps:SetFont(path, size, flags)
    end
    d.fontVer = textVer
end

-- Weapon slots stack their lines from the top: the stats, the dps, then the
-- enchant, a line moving up when the one above it is empty. Beside a slot
-- the first line sits where retail's item level does and the enchant keeps
-- its retail spot unless the dps line pushes it down; below the middle
-- weapon slot the lines stack centred under it, stats and dps sharing a row. Re-run after each paint
-- (the lines' contents and heights decide the stack).
local LINE = 13
local function StackWeaponText(d, anchor)
    local stats, dps, ench = d.stats, d.dps, d.ench
    stats:ClearAllPoints(); dps:ClearAllPoints(); ench:ClearAllPoints()
    if d.side == "B" then
        -- About 30px sit between the weapon row and the frame's bottom edge:
        -- three lines do not fit, so under the middle slot the stats and the
        -- dps share one row, centred as a pair.
        local top = -3
        if d.hasStats and d.hasDps then
            local gap = 6
            local w = stats:GetStringWidth() + gap + dps:GetStringWidth()
            stats:SetPoint("TOPLEFT", anchor, "BOTTOM", -w / 2, top)
            dps:SetPoint("LEFT", stats, "RIGHT", gap, 0)
            top = top - math.max(stats:GetStringHeight(), dps:GetStringHeight()) - 1
        elseif d.hasStats then
            stats:SetPoint("TOP", anchor, "BOTTOM", 0, top)
            top = top - stats:GetStringHeight() - 1
        elseif d.hasDps then
            dps:SetPoint("TOP", anchor, "BOTTOM", 0, top)
            top = top - dps:GetStringHeight() - 1
        end
        ench:SetPoint("TOP", anchor, "BOTTOM", 0, top)
        ench:SetJustifyH("CENTER")
        return
    end
    local point, rel, x = "LEFT", "RIGHT", EX
    if d.side == "L" then point, rel, x = "RIGHT", "LEFT", -EX end
    local y = 10
    if d.hasStats then
        stats:SetPoint(point, anchor, rel, x, y)
        y = y - LINE
    end
    if d.hasDps then
        dps:SetPoint(point, anchor, rel, x, y)
        y = y - LINE
    end
    ench:SetPoint(point, anchor, rel, x, math.min(y, -3) - 2)
    ench:SetJustifyH(point)
end

-- The stats off the slot's edge where retail's item level sits, the
-- enchant under them hugging the slot.
local function PlaceText(d, anchor)
    if d.dps then return StackWeaponText(d, anchor) end
    local stats, ench = d.stats, d.ench
    stats:ClearAllPoints(); ench:ClearAllPoints()
    if d.side == "R" then
        stats:SetPoint("LEFT", anchor, "RIGHT", EX, 10)
        ench:SetPoint("LEFT", anchor, "RIGHT", EX, -5)
        ench:SetJustifyH("LEFT")
    else
        stats:SetPoint("RIGHT", anchor, "LEFT", -EX, 10)
        ench:SetPoint("RIGHT", anchor, "LEFT", -EX, -5)
        ench:SetJustifyH("RIGHT")
    end
end

-- One slot's text. Runs from Blizzard's per-slot update (only while the
-- slots are shown), from the options refreshers and from item data landing.
local function PaintSlotText(slot)
    local d = FFD[slot]
    local stats = d and d.stats
    if not stats then return end
    -- The ranged text sits past the ammo slot while that shows (checked
    -- ahead of the memo: the ammo slot comes and goes with the class).
    local ammo = d.ammo
    if ammo then
        local anchor = ammo:IsShown() and ammo or slot
        if d.anchor ~= anchor then
            d.anchor = anchor
            PlaceText(d, anchor)
        end
    end
    -- Memo: the equipped link and the settings version are every input.
    local slotID = slot:GetID()
    local link = GetInventoryItemLink("player", slotID)
    if d.paintLink == link and d.paintVer == textVer then return end
    d.paintLink, d.paintVer = link, textVer
    local idx = d.idx
    if pending[idx] then
        pending[idx] = nil
        pendingN = pendingN - 1
        if pendingN == 0 then itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
    end
    if d.fontVer ~= textVer then ApplyLabelFonts(d) end
    local ench = d.ench
    local itemID = link and GetInventoryItemID("player", slotID)
    if not (itemID and C_Item.IsItemDataCachedByID(itemID)) then
        stats:SetText(""); ench:SetText("")
        if d.dps then d.dps:SetText("") end
        if itemID then
            -- Not cached yet: one repaint when it lands, watched only while
            -- the slot shows (and ahead of the request, whose answer can
            -- come at once); a hidden one repaints on its next show.
            if slot:IsVisible() then
                pending[idx] = itemID
                pendingN = pendingN + 1
                itemWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            else
                d.paintLink = nil
            end
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return
    end

    -- The item's colour as retail colours its item level: the custom colour,
    -- else the item's quality (unless turned off), else white.
    local r, g, b = 1, 1, 1
    local custom = DB("charSheetItemLevelUseColor") and DB("charSheetItemLevelColor")
    if custom then
        r, g, b = custom.r, custom.g, custom.b
    elseif DB("charSheetColorItemLevel") ~= false then
        local qr, qg, qb = QualityColor(slot)
        if qr then r, g, b = qr, qg, qb end
    end

    -- The upgrade track's key and colour override: the item's stats (or its
    -- armor), else in the item's colour.
    -- A weapon's damage per second rides the same key and colour.
    local showStats = DB("showUpgradeTrack") ~= false
    local statText = showStats and StatText(link) or ""
    stats:SetText(statText)
    local sc = DB("charSheetUpgradeTrackUseColor") and DB("charSheetUpgradeTrackColor")
    local sr, sg, sb = r, g, b
    if sc then sr, sg, sb = sc.r, sc.g, sc.b end
    stats:SetTextColor(sr, sg, sb, 0.8)
    local dps = d.dps
    if dps then
        local dpsText = showStats and DpsText(link) or ""
        dps:SetText(dpsText)
        dps:SetTextColor(sr, sg, sb, 0.8)
        d.hasStats, d.hasDps = statText ~= "", dpsText ~= ""
    end

    -- Vanilla enchants carry no icon, so the name always shows; Show Enchant
    -- Names gives it retail's name look (outlined, tinted from the item's
    -- colour). Capped at 45% of the gap between the columns, as on retail.
    local name = DB("showEnchants") ~= false and EnchantName(slotID) or ""
    ench:SetText(name)
    if name ~= "" then
        local size = DB("charSheetEnchantSize") or 9
        if DB("charSheetEnchantNames") then
            ench:SetFont(FontPath(), size, "OUTLINE, SLUG")
            ench:SetTextColor(r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5, 0.9)
        else
            ench:SetFont(FontPath(), size, "")
            ench:SetTextColor(1, 1, 1, 0.8)
        end
        local head, hands = _G.CharacterHeadSlot, _G.CharacterHandsSlot
        local lr, rl = head and head:GetRight(), hands and hands:GetLeft()
        ench:SetWidth((lr and rl and rl > lr) and (rl - lr) * 0.45 or 0)
    end
    if dps then StackWeaponText(d, d.anchor) end
end

-- The slots went away (tab, pet view, close): nothing waits any more; a
-- slot that was waiting repaints on its next show.
local function ClearPending()
    if pendingN == 0 then return end
    for i = 1, #SLOTS do
        if pending[i] then
            pending[i] = nil
            local d = FFD[_G[SLOTS[i]]]
            if d then d.paintLink = nil end
        end
    end
    pendingN = 0
    itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- Item data landed: one repaint per waiting slot. A failed load is not
-- asked for again (no retry loop); that slot stays blank until its item or
-- a setting changes.
local function OnItemInfo(_, _, itemID, success)
    for i = 1, #SLOTS do
        if pending[i] == itemID then
            pending[i] = nil
            pendingN = pendingN - 1
            if success then
                local slot = _G[SLOTS[i]]
                local d = FFD[slot]
                if d then d.paintLink = nil end
                PaintSlotText(slot)
            end
        end
    end
    if pendingN == 0 then itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local slotOverlay   -- every slot's text; the eyeball fades it

local function BuildSlotText()
    local host = _G.PaperDollItemsFrame
    if not host or itemWatch then return end
    itemWatch = CreateFrame("Frame")
    itemWatch:SetScript("OnEvent", OnItemInfo)
    -- A child of the slots' own frame, so it goes with them (other tabs, the
    -- pet view); above the model scene, below the slot buttons.
    local overlay = CreateFrame("Frame", nil, host)
    slotOverlay = overlay
    overlay:SetAllPoints(host)
    local scene = _G.CharacterModelScene
    overlay:SetFrameLevel((scene and scene:GetFrameLevel() or 50) + 10)
    local ranged = _G.CharacterRangedSlot
    local rangedShown = ranged and ranged:IsShown()
    local path = FontPath()
    for i = 1, #SLOTS do
        local name = SLOTS[i]
        local side, slot = TEXT_SIDE[name], _G[name]
        if side and slot then
            -- Without a ranged slot the off hand is the outer one on the right.
            if side == "B" and not rangedShown then side = "R" end
            local d = GetFFD(slot)
            d.idx, d.side, d.anchor = i, side, slot
            d.stats = overlay:CreateFontString(nil, "OVERLAY")
            if WEAPON_SLOT[name] then d.dps = overlay:CreateFontString(nil, "OVERLAY") end
            d.ench = overlay:CreateFontString(nil, "OVERLAY")
            d.ench:SetFont(path, DB("charSheetEnchantSize") or 9, "")
            d.ench:SetWordWrap(false)
            ApplyLabelFonts(d)
            if slot == ranged then d.ammo = _G.CharacterAmmoSlot end
            PlaceText(d, slot)
        end
    end
    host:HookScript("OnHide", ClearPending)
    -- A first open that skinned the sheet has already had Blizzard's update.
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and slot:IsVisible() then PaintSlotText(slot) end
    end
end

-- Options refreshers: the retail slot text setters (the track key shown
-- here as Show Item Stats, Enchants and its cog, the Fonts page's Enchant
-- Text Size) land here; the retail versions walk retail-only state.
-- The version bump feeds every setting into the paint memo, so a hidden
-- sheet repaints on its next show.
local function RefreshSlotText()
    textVer = textVer + 1
    if not Enabled() then return end
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and slot:IsVisible() then PaintSlotText(slot) end
    end
end
EllesmereUI._refreshItemLevelVisibility = RefreshSlotText
EllesmereUI._refreshUpgradeTrackVisibility = RefreshSlotText
EllesmereUI._refreshEnchantsVisibility = RefreshSlotText
EllesmereUI._refreshCharSheetSlotLabels = RefreshSlotText
EllesmereUI._applyCharSheetTextSizes = RefreshSlotText

-- Blizzard refreshes every shown slot through this on equipment changes and
-- on show; the border and the slot text follow. Foreign item buttons (bags)
-- have no entry.
local function OnSlotUpdate(slot)
    local d = FFD[slot]
    if not d then return end
    if d.border then ColorSlotBorder(slot) end
    if d.stats then PaintSlotText(slot) end
end

local function SkinSlot(slotName, Fade)
    local slot = _G[slotName]
    if not slot or GetFFD(slot).done then return end
    GetFFD(slot).done = true
    -- The bronze slot frame lives on a child frame; the button art is the
    -- named NormalTexture (hidden, not faded: the client rewrites its vertex
    -- colour, and with it the alpha, on every item update).
    if slot.BorderFrame then
        Fade(slot.BorderFrame)
    else
        -- The ammo slot is built without that child: its ring is an atlas
        -- texture on the button itself. The arrow pointing at the ranged slot
        -- (an unnamed child frame of its own) stays.
        for i = 1, select("#", slot:GetRegions()) do
            local r = select(i, slot:GetRegions())
            if r.GetAtlas and r:GetAtlas() == "UI-Character-Info-GearSlotSmall" then r:SetAlpha(0) end
        end
    end
    local normal = _G[slotName .. "NormalTexture"]
    if normal then normal:Hide() end
    -- Blizzard's quality ring gets re-shown and recoloured on every item
    -- update, so it is collapsed onto one blank texel instead of hidden.
    if slot.IconBorder then slot.IconBorder:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
    -- The item icon is the button's own; the ammo slot also declares a
    -- legacy texture under the same global name, which is not it.
    local icon = slot.icon or _G[slotName .. "IconTexture"]
    if icon then
        local z = Zoom()
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    local bg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    bg:SetAllPoints(slot)
    bg:SetColorTexture(0.5, 0.5, 0.5, 0.7)
    GetFFD(slot).bg = bg
    local PanelPP = EllesmereUI.PanelPP
    if PanelPP and PanelPP.CreateBorder then
        PanelPP.CreateBorder(slot, 0.4, 0.4, 0.4, 1, 2, "OVERLAY", 1)
        local borders = PanelPP.GetBorders and PanelPP.GetBorders(slot)
        if borders then borders:SetFrameLevel(slot:GetFrameLevel()) end
        GetFFD(slot).border = true
        ColorSlotBorder(slot)
    end
end

-- Options-page refresh: the Icon Zoom slider lands here (the retail sheet's
-- own refresher is replaced, it walks the retail slot list).
function EllesmereUI._refreshCharSheetIconZoom()
    if not Enabled() then return end
    local z = Zoom()
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and FFD[slot] and FFD[slot].done then
            local icon = slot.icon or _G[SLOTS[i] .. "IconTexture"]
            if icon then icon:SetTexCoord(z, 1 - z, z, 1 - z) end
        end
    end
end

--------------------------------------------------------------------------------
--  The model backdrop and the sidebar panel, as on retail
--------------------------------------------------------------------------------
local IMG_ASPECT = 787 / 1030   -- character-bg.png

-- Cover crop: the image keeps its aspect and the box shows its centre.
local function CoverCrop(tex, w, h)
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return end
    if not w or not h or w <= 0 or h <= 0 then return end
    local box = w / h
    if box > IMG_ASPECT then
        local trim = (1 - IMG_ASPECT / box) / 2
        tex:SetTexCoord(0, 1, trim, 1 - trim)
    else
        local trim = (1 - box / IMG_ASPECT) / 2
        tex:SetTexCoord(trim, 1 - trim, 0, 1)
    end
end

-- Both panels draw above the shell's top bar (children of the frame render
-- over its own textures), so their top edge is pinned to the bar's bottom:
-- flush under it, never over it, no gap of bare backdrop between.
local function PinTop(region, topBar, fallback)
    if topBar then
        region:SetPoint("TOP", topBar, "BOTTOM", 0, 0)
    else
        region:SetPoint("TOP", fallback, "TOP", 0, 0)
    end
end

local function ModelBackdrop(frame, topBar)
    local scene = _G.CharacterModelScene
    local doll = _G.PaperDollFrame
    if not (scene and doll) or GetFFD(frame).modelBg then return end
    -- Under the paper doll so it comes and goes with that tab; one level
    -- under the scene so the character renders over it.
    local host = CreateFrame("Frame", nil, doll)
    PinTop(host, topBar, scene)
    host:SetPoint("LEFT", scene, "LEFT", 0, 0)
    host:SetPoint("RIGHT", scene, "RIGHT", 0, 0)
    host:SetPoint("BOTTOM", scene, "BOTTOM", 0, 0)
    host:SetFrameLevel(math.max(0, scene:GetFrameLevel() - 1))
    local tex = host:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(host)
    tex:SetTexture(MEDIA .. "character-bg.png")
    host:SetScript("OnSizeChanged", function(_, w, h) CoverCrop(tex, w, h) end)
    CoverCrop(tex, host:GetSize())
    GetFFD(frame).modelBg = host
end

local function SidebarPanel(frame, topBar)
    local host = frame.RightPaneHost
    if not host or GetFFD(frame).sidebar then return end
    -- A child of the pane host so it collapses with it, at the host's own
    -- level so every list and scrollbar draws over it.
    local panel = CreateFrame("Frame", nil, host)
    panel:SetFrameLevel(host:GetFrameLevel())
    PinTop(panel, topBar, host)
    panel:SetPoint("LEFT", host, "LEFT", 0, 0)
    panel:SetPoint("RIGHT", host, "RIGHT", -6, 0)
    panel:SetPoint("BOTTOM", host, "BOTTOM", 0, 8)
    local tex = panel:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(panel)
    tex:SetColorTexture(0, 0, 0, 0.2)
    GetFFD(frame).sidebar = panel
end

local function SkinFrame()
    local frame = _G.CharacterFrame
    local WSkin = ns.WSkin
    if not (frame and WSkin and WSkin.Shell) then return false end
    local Fade = WSkin.FadeRegions
    if not Fade then return false end
    local d = GetFFD(frame)
    if d.done then return true end
    d.done = true

    -- The ordinary window treatment: shell, border, top bar, house close
    -- button, title centred on the bar. explicitControls keeps the engine
    -- away from the stats scrollbar, which stays Blizzard's.
    WSkin.Shell("charsheet", frame)
    if WSkin.CommonChrome then WSkin.CommonChrome(frame, "CharacterFrame", true) end
    if WSkin.RemovePortrait then WSkin.RemovePortrait(frame) end

    -- The right-pane collapse arrow goes. The pane it toggles is kept open:
    -- with the arrow gone a sheet collapsed from an earlier session (the
    -- state is a cvar, read once at load) could never be opened again.
    Discard(frame.RightPaneToggleButton)
    if frame.IsRightPaneCollapsed and frame.SetRightPaneCollapsed then
        frame:HookScript("OnShow", function(self)
            if self:IsRightPaneCollapsed() then self:SetRightPaneCollapsed(false) end
        end)
    end

    -- Name in the top bar and the level line: the house font on Blizzard's
    -- own font strings, so the text (pvp title, class colour) stays theirs.
    local title = _G.CharacterFrameTitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if title and WSkin.Font then WSkin.Font(title, 1, 1, 1) end
    local level = _G.CharacterLevelText
    if level and WSkin.Font then WSkin.Font(level) end
    if _G.CharacterLevelTextBackground then _G.CharacterLevelTextBackground:SetAlpha(0) end

    -- Pane backdrops, the stone header, the divider strip, the stats box
    -- chrome (inside frame, scroll line, class crest) and the model backdrop.
    Fade(frame.LeftPaneHost)
    Fade(frame.RightPaneHost)
    FadeChildren(frame.RightPaneHost, function(child)
        -- The stats and pet lists are children too; their chrome goes, their
        -- rows and scrollbars are handled by the element callback and kept.
        if child ~= _G.CharacterStatsPaneScrollBox and child ~= _G.CharacterStatsPanePetScrollBox then
            Fade(child)
        end
    end)
    if frame.RightPaneHost and frame.RightPaneHost.StoneBg then frame.RightPaneHost.StoneBg:SetAlpha(0) end
    Fade(_G.CharacterStatsPaneScrollBox)
    Fade(_G.CharacterStatsPanePetScrollBox)
    Fade(_G.PaperDollFrame)
    Fade(_G.CharacterModelScene)
    local shell = WSkin.GetFFD and WSkin.GetFFD(frame)
    local topBar = shell and shell.topBar
    ModelBackdrop(frame, topBar)
    SidebarPanel(frame, topBar)

    -- Item slots: frames off, icons cropped, a grey square and a quality
    -- border on each, and the slot text beside them; both follow Blizzard's
    -- own slot refresh.
    for i = 1, #SLOTS do SkinSlot(SLOTS[i], Fade) end
    BuildSlotText()
    -- Top-left eyeball, as on retail: hides every slot's text for the
    -- session by fading their shared overlay.
    if slotOverlay and not d.eyeBtn then
        local EYE_VISIBLE, EYE_INVISIBLE = EllesmereUI.EYE_VISIBLE_ICON, EllesmereUI.EYE_INVISIBLE_ICON
        local hidden = false
        -- On the slots' own frame: it goes with the slot text (other tabs,
        -- the pet view) and sits above the mouse-enabled model scene, which
        -- reaches up under the button's lower edge.
        local items = slotOverlay:GetParent()
        local eyeBtn = CreateFrame("Button", nil, items)
        eyeBtn:SetSize(20, 20)
        eyeBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -6)
        eyeBtn:SetFrameLevel(items:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(EYE_VISIBLE)
        eyeBtn:SetScript("OnClick", function(self)
            hidden = not hidden
            eyeTex:SetTexture(hidden and EYE_INVISIBLE or EYE_VISIBLE)
            slotOverlay:SetAlpha(hidden and 0 or 1)
            EllesmereUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            EllesmereUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        d.eyeBtn = eyeBtn
    end
    if not d.slotHook and type(_G.PaperDollItemSlotButton_Update) == "function" then
        d.slotHook = true
        hooksecurefunc("PaperDollItemSlotButton_Update", OnSlotUpdate)
    end

    -- Stats list colours.
    HookStatsList(_G.CharacterStatsPaneScrollBox)
    HookStatsList(_G.CharacterStatsPanePetScrollBox)

    -- The stats scrollbars: the house thin thumb in Blizzard's own track
    -- position, the up/down arrows left as they are. Texture work only, the
    -- bar keeps its scripts and its mouse handling.
    if WSkin.ScrollBar then
        local stats = _G.CharacterStatsPaneScrollBox
        if stats and stats.ScrollBar then WSkin.ScrollBar(stats.ScrollBar, true) end
        local pet = _G.CharacterStatsPanePetScrollBox
        if pet and pet.ScrollBar then WSkin.ScrollBar(pet.ScrollBar, true) end
    end
    return true
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not _G.CharacterFrame or not Enabled() then return end
    if not SkinFrame() then
        -- The engine loads after this addon's own files; one retry on the
        -- first open covers a late shell.
        _G.CharacterFrame:HookScript("OnShow", function() SkinFrame() end)
    end
end)
