-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidCheck.lua -- Consumable check on a ready check
--
--  Shows on ANY ready check in the group, whoever started it, and lists every
--  member against what a raid expects of them: flask, food, augment rune,
--  vantus rune, the group-wide buffs, weapon enchant and durability. The grid
--  is the whole report -- there is no summary line, because a raid leader
--  reading twelve columns does not also need them counted in prose.
--
--  WHAT ANSWERS A COLUMN. Every column declares how it is matched, and the
--  vectors are not interchangeable:
--
--    ids     exact spell ids. The only vector that survives restricted
--            content, and the only one that rots -- new consumables need new
--            ids every expansion.
--    icons   "Well Fed" reuses a handful of icons, so any recipe matches and
--            nothing needs updating.
--    prefix  every Vantus buff is "<prefix>: <boss>", so the prefix catches
--            every boss of every tier.
--    class   a group-wide buff. Not a matcher: it says whose absence makes
--            the column meaningless.
--    selfRead  read live off your own client. No API reports a weapon enchant
--            for anyone else, so YOUR row is answered locally and everyone
--            else's is volunteered over the comms layer. The local read is
--            applied last and wins: it is current, and it still works when
--            there is no group and so no transport at all.
--            (Durability reaches the same place by another road -- see the
--            column, LibDurability already reports your own value locally --
--            so it needs nothing from this mechanism.)
--
--  MIDNIGHT AURA RESTRICTIONS. The game offers two ways to read another
--  player's auras and each is blind where the other sees, so both ship:
--
--    * the index sweep answers with the FULL aura -- icon and name included --
--      which is what lets an unlisted consumable register. It is refused
--      outright in restricted content.
--    * GetUnitAuraBySpellID survives restriction, and combat, but only for
--      ids the client does not consider secret, and never exposes an icon.
--      So there the id tables are all we have.
--
--  A secret result reads as "unknown" rather than "missing". Claiming someone
--  has no flask because the client refused to answer is worse than saying
--  nothing, and that principle runs through the whole file: a column with no
--  answer is blank, never a cross.
--
--  The honest limit: inside a raid this window knows exactly what it has been
--  told to look for. A client reading its OWN auras and volunteering the
--  result is what would remove that, and is the road the enchant column is
--  already on -- read locally, reported outward.
-------------------------------------------------------------------------------
local _, ns = ...

local GetRaidRosterInfo   = GetRaidRosterInfo
local GetNumGroupMembers  = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitIsUnit          = UnitIsUnit
local UnitName, UnitClass, UnitIsConnected = UnitName, UnitClass, UnitIsConnected
local Ambiguate           = Ambiguate
local issecretvalue       = issecretvalue
local GetAuraDataByIndex  = C_UnitAuras.GetAuraDataByIndex
local GetUnitAuraBySpellID = C_UnitAuras.GetUnitAuraBySpellID

-- Two member columns of twenty: a 40-man roster in one screenful, without a
-- scroll frame and without a window taller than the game. Sized to be legible
-- at a glance mid-raid rather than to save pixels -- the window fits the group
-- and the column set, so there is room, and the scale slider is there for
-- anyone who disagrees.
local MEMBER_COLS = 2
local COL_ROWS    = 20
local NAME_W      = 112
local CELL_W      = 30
local ROW_H       = 22
local COL_GAP     = 16
local PAD         = 14
local TITLE_H     = 26
local HEADER_H    = 20
local NAME_SIZE   = 12
local SMALL_SIZE  = 11
local ICON_SZ     = 18
local AURA_SCAN_LIMIT = 40
local SWEEP_PERIOD    = 2

-- Blizzard's own ready-check art: exactly these semantics, guaranteed present,
-- and no texture of ours to ship.
local TEX_OK   = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_MISS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

-- QoL's key in EllesmereUI._addonKeyToFolder. On-screen text has to resolve
-- through GetFontPath: EllesmereUI.MakeFont hardcodes the options-panel font,
-- and using it here would make this the one QoL window ignoring the user's
-- Global Font setting.
local FONT_KEY = "extras"

local fonts = {}   -- every fontstring the window owns, with its size

local function FontPath()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY))
        or STANDARD_TEXT_FONT
end

local function MakeText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FontPath(), size, "")
    fs:SetTextColor(1, 1, 1)
    fonts[#fonts + 1] = { fs = fs, size = size }
    return fs
end

-- Re-resolved every time the window opens rather than only at build: the
-- window is built once and lives for the session, so a Global Font change
-- between two ready checks would otherwise never reach it.
local function ApplyFonts()
    local path = FontPath()
    for _, e in ipairs(fonts) do e.fs:SetFont(path, e.size, "") end
end

-- "Well Fed" has reused the same handful of icons across expansions, so food
-- is identifiable without knowing its spell id at all. That is the one
-- consumable column that does not rot -- a new recipe keeps the icon and keeps
-- being detected.
local FOOD_ICONS = {
    [136000] = true,   -- the stat "Well Fed"
    [134062] = true,   -- plain "Well Fed", no stat line
    [132805] = true,
    [133950] = true,
}

-- The Vantus prefix is not hardcoded: it is read off a known Vantus rune and
-- cut at the first separator, so every client gets it correctly localized. The
-- seed spell is only a name source -- which rune it is does not matter, and an
-- old one is the safest choice because it will never be removed.
local VANTUS_SEED = 237825
local vantusPrefix, vantusTried
local function VantusPrefix()
    if vantusTried then return vantusPrefix end
    vantusTried = true
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(VANTUS_SEED)
    local name = info and info.name
    if name then vantusPrefix = name:match("^(.-)[:%-：]") end
    return vantusPrefix
end

-- Consumables, in display order. `seed` and `icon` are only the header art;
-- `seed` fetches it from the game so a header cannot drift from what it checks.
--
-- Only flask and rune carry ids, and they are the only entries here that will
-- ever need a patch-day edit. /euiraidcheck is the maintenance tool.
local CHECKS = {
    { key = "flask",  label = "Flask",  seed = 1235110,
      ids = { [1236763] = true, [1239355] = true, [1235057] = true, [1239755] = true,
              [1236767] = true, [1235111] = true, [1235110] = true, [1235108] = true } },
    { key = "food",   label = "Food",   icon = 136000, icons = FOOD_ICONS },
    { key = "rune",   label = "Rune",   seed = 1264426,
      ids = { [1264426] = true, [1242347] = true, [1234969] = true, [453250] = true,
              [393438]  = true } },
    -- Vantus runes apply to raid bosses, so in a Mythic+ key the column is not
    -- merely unlikely to be filled, it is meaningless.
    { key = "vantus", label = "Vantus", seed = VANTUS_SEED,
      prefix = VantusPrefix, raidOnly = true },
}

local DURABILITY_KEY = "durability"
local WENCHANT_KEY   = "wenchant"
local MSG_REPORT     = "rc"    -- a client describing itself
local MSG_QUERY      = "rcq"   -- someone asking the group to describe itself

-- What each client volunteered about itself, from either wire. One store, so
-- a future field lands here rather than growing a third parallel map -- and
-- the paint path never has to care which transport a value arrived on.
local reported = {}   -- player name -> { dur = number, we = enchantID }

-- The library reports names Ambiguate'd to "none" while UnitName gives the
-- bare name, so normalisation happens once, here, at the store boundary.
local function Note(name, field, value)
    if type(name) ~= "string" then return end
    name = Ambiguate(name, "short")
    local e = reported[name]
    if not e then e = {}; reported[name] = e end
    e[field] = value
end

-- Your own main-hand enchant id, or 0 for none. Only your own client can
-- answer this, for you or for anyone -- which is why it also goes on the wire.
--
-- Through the parent, not GetWeaponEnchantInfo directly: that call is a
-- deprecation shim on 12.1, and the parent owns the one reader that knows it.
--
-- Main hand only: off-hand items that cannot take an enchant at all are
-- common, and reading those as missing would be a false accusation.
local function MyEnchantID()
    local has, _, _, enchantID = EllesmereUI.WeaponEnchants()
    return (has and enchantID) or 0
end

-- The single place an enchant id becomes a verdict, so your row and everyone
-- else's are judged by the same rule -- one arrives locally and one off the
-- wire, and that must not be a difference the user can see.
local function EnchantOK(id)
    return (id or 0) > 0
end

-------------------------------------------------------------------------------
--  Columns
-------------------------------------------------------------------------------

local COLUMNS   = {}   -- display order
local SELF_COLS = {}   -- columns that read your own row locally
local ID_TO_KEY = {}   -- spell id -> column key, flattened from every id set
local ICON_COLS = {}   -- columns matched on aura icon
local NAME_COLS = {}   -- columns matched on an aura name prefix
local columnsBuilt

local function LibDur()
    return LibStub and LibStub("LibDurability", true)
end

-- Built on first open rather than at load: nothing here needs to exist until
-- the window does, and by then every file has run.
local function EnsureColumns()
    if columnsBuilt then return end
    columnsBuilt = true

    for _, def in ipairs(CHECKS) do
        COLUMNS[#COLUMNS + 1] = def
    end

    -- Oils and sharpening stones are one thing to the game -- a temporary
    -- weapon enchant -- so this is one column rather than two. Which
    -- consumable a player used is their business; whether the weapon is
    -- enchanted is the raid's, and it means no id table to maintain.
    --
    -- The column exists whether or not the transport does: `selfRead` answers
    -- your own row from your own client, so it is filled solo, filled before
    -- any reply could arrive, and never wrong because a message was dropped.
    -- Comms only ever fills OTHER people's rows.
    COLUMNS[#COLUMNS + 1] = { key = WENCHANT_KEY, label = "Weapon Enchant",
                              selfRead = function() return EnchantOK(MyEnchantID()) end,
                              note = "Oil or sharpening stone on the main hand. Other players' rows need them to be running EllesmereUI.",
                              icon = "Interface\\Icons\\INV_Stone_SharpeningStone_05" }

    -- Only offered when the library is embedded: a column nobody can ever
    -- answer is worse than none.
    --
    -- The note is not a detail. Every client on the shared channel reports an
    -- average across its equipped slots, so this number is not the one the
    -- DataBars durability block shows, which is the single worst piece. Both
    -- are right; only the average is comparable between people, which is why
    -- the column cannot use the other reading.
    if LibDur() then
        COLUMNS[#COLUMNS + 1] = { key = DURABILITY_KEY, label = "Durability",
                                  numeric = true,
                                  note = "Average across equipped items, as reported by each player.",
                                  icon = "Interface\\Icons\\Trade_BlackSmithing" }
    end

    -- Raid buff definitions are not ours and are not copied: they live in the
    -- parent, shared with Aura Buff Reminders. Every child addon has the
    -- parent, so these columns exist whatever else the user has switched off,
    -- and there is one list to maintain rather than two.
    for _, b in ipairs(EllesmereUI.RaidBuffs) do
        -- The table also carries entries checked per player rather than
        -- group-wide; only the group-wide ones belong in a raid check.
        if b.check == "raid" then
            local ids = {}
            for _, id in ipairs(b.buffIDs) do ids[id] = true end
            COLUMNS[#COLUMNS + 1] = { key = b.key, class = b.class, ids = ids,
                                      seed = b.castSpell, fallbackName = b.name }
        end
    end

    -- One flat lookup instead of walking every column's id set per aura.
    for _, def in ipairs(COLUMNS) do
        if def.selfRead then SELF_COLS[#SELF_COLS + 1] = def end
        if def.ids then
            for id in pairs(def.ids) do ID_TO_KEY[id] = def.key end
        end
        if def.icons  then ICON_COLS[#ICON_COLS + 1] = def end
        if def.prefix then NAME_COLS[#NAME_COLS + 1] = def end
    end
end

-- A buff column carries no label of ours: its name is the spell's, already
-- localized by the game. Resolved once and kept.
local columnName = {}
local function ColumnName(def)
    if def.label then return EllesmereUI.L(def.label) end
    local n = columnName[def.key]
    if not n then
        local info = def.seed and C_Spell and C_Spell.GetSpellInfo
            and C_Spell.GetSpellInfo(def.seed)
        n = (info and info.name) or def.fallbackName or def.key
        columnName[def.key] = n
    end
    return n
end

-------------------------------------------------------------------------------
--  Reading
-------------------------------------------------------------------------------

-- AuraKit is 12.1-gated and does not exist at all on an older client (see the
-- LIVE GATE at the top of EllesmereUI_AuraKit.lua), so the nil check is load
-- bearing, not defensive noise -- do not remove it. False is the right answer
-- there: aura restriction arrived WITH 12.1, so a client without AuraKit is a
-- client where nothing is restricted and the index sweep always works.
local function Restricted()
    local AK = EllesmereUI.AuraKit
    if not AK then return false end
    return AK.AurasRestricted()
end

-- Can this column be answered at all right now? One predicate, so nothing
-- downstream branches on a column's name.
local function Answerable(def, restricted, classPresent)
    if def.class    then return classPresent[def.class] or false end
    if def.raidOnly and not IsInRaid() then return false end
    if def.ids      then return true end
    -- Icon and name prefix live on the full aura, which only the sweep hands
    -- back, so those columns cannot answer under restriction. A prefix that
    -- did not resolve is the same situation: better no column than one that
    -- crosses everybody.
    if def.prefix   then return not restricted and def.prefix() ~= nil end
    if def.icons    then return not restricted end
    return true   -- volunteered: askable always, blank until someone answers
end

-- Unrestricted path. One sweep answers every column at once AND hands back the
-- icon and name, which is what lets an unlisted consumable register.
--
-- A named function so the pcall wraps the whole unit in one call rather than
-- allocating a closure per unit -- restriction was already decided by the
-- caller, so a per-index catch buys nothing here.
local function SweepBody(unit, out)
    for i = 1, AURA_SCAN_LIMIT do
        local aura = GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then return end
        local id = aura.spellId
        if id and not (issecretvalue and issecretvalue(id)) then
            local key = ID_TO_KEY[id]
            if key then out[key] = true end
            if aura.icon then
                for j = 1, #ICON_COLS do
                    local def = ICON_COLS[j]
                    if def.icons[aura.icon] then out[def.key] = true end
                end
            end
            if aura.name then
                for j = 1, #NAME_COLS do
                    local def = NAME_COLS[j]
                    -- Each column resolves its own prefix; the lookup is
                    -- memoised, so this is a table read per aura.
                    local p = def.prefix()
                    if p and aura.name:find(p, 1, true) == 1 then out[def.key] = true end
                end
            end
        end
    end
end

-- Restricted path. Returns true, false, or nil when the client refused to
-- answer -- and nil matters: see the header.
local function UnitHasAny(unit, ids)
    local unknown = false
    for id in pairs(ids) do
        local ok, aura = pcall(GetUnitAuraBySpellID, unit, id)
        if not ok then
            unknown = true
        elseif aura ~= nil then
            if issecretvalue and issecretvalue(aura) then
                unknown = true
            else
                return true
            end
        end
    end
    if unknown then return nil end
    return false
end

local function UnitChecks(unit, answerable, restricted)
    local out = {}
    if restricted then
        for _, def in ipairs(COLUMNS) do
            if answerable[def.key] and def.ids then
                out[def.key] = UnitHasAny(unit, def.ids)
            end
        end
    else
        -- Seeded only on this path: the sweep reports what it FINDS, so a
        -- column it never touches has to already read as absent.
        for _, def in ipairs(COLUMNS) do
            if answerable[def.key] and (def.ids or def.icons or def.prefix) then
                out[def.key] = false
            end
        end
        pcall(SweepBody, unit, out)
    end
    return out
end

-- Enumerating a group is three different APIs, not one, and mixing them is how
-- a Delve companion lands in a raid check:
--
--   * In a raid, GetRaidRosterInfo(i) pairs with raid<i> and is the only
--     source of the subgroup number.
--   * In a party it pairs with nothing -- a party is the player plus
--     party1..party4, and there are no subgroups.
--   * Solo there is no group, and the window reports the player, since
--     checking your own consumables before you join something is the same
--     question this answers.
--
-- Cheap on purpose: no auras are read here. Which buff columns are worth
-- reading depends on which classes are present, so the roster has to exist
-- before a single aura call is made.
local function ReadMembers()
    local out = {}

    local function Add(unit, subgroup)
        -- UnitIsPlayer keeps followers out: a Delve companion is a group
        -- member as far as these APIs are concerned, and it does not eat.
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local _, class = UnitClass(unit)
        out[#out + 1] = {
            unit   = unit,
            name   = UnitName(unit) or "?",
            class  = class,
            online = UnitIsConnected(unit),
            group  = subgroup or 1,
            -- Not a cosmetic flag: your own row is the one that can be read
            -- locally instead of waited for.
            isSelf = UnitIsUnit(unit, "player"),
        }
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            Add("raid" .. i, subgroup)
        end
    elseif IsInGroup() then
        Add("player")
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i) end
    else
        Add("player")
    end

    table.sort(out, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    return out
end

-------------------------------------------------------------------------------
--  Volunteered reports
-------------------------------------------------------------------------------

-- The raw id travels, not a verdict: the receiver applies EnchantOK, so a
-- later refinement of what counts works against everyone immediately instead
-- of waiting for the whole raid to update.
local function MyReport()
    return "we=" .. MyEnchantID()
end

-- Bounded parse: this is another player's client talking, so a field that is
-- not exactly what is expected is dropped rather than coerced.
local function ReadReport(sender, payload)
    if type(payload) ~= "string" then return end
    local we = payload:match("we=(%d+)")
    if we then Note(sender, "we", tonumber(we)) end
end

local function NoteDurability(percent, _, name)
    if type(percent) == "number" then Note(name, "dur", percent) end
end

-------------------------------------------------------------------------------
--  Permission
-------------------------------------------------------------------------------

local db
local function P()
    return db and db.profile and db.profile.raidCheck
end

local function HasRank()
    return IsInGroup()
       and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

-- The option only widens who SEES it; it grants nothing, because there is
-- nothing to grant -- every column is either a local read or volunteered.
local function MayShow()
    local p = P()
    if not p or not p.enabled then return false end
    if p.showWithoutRank then return true end
    return HasRank()
end

local DB_DEFAULTS = {
  profile = {
    raidCheck = {
        -- Off by default: this opens a window on an event the user did not
        -- ask for, so it is opt-in like every other QoL feature.
        enabled          = false,
        showWithoutRank  = false,
        -- Drop columns nothing in this group can satisfy instead of dimming
        -- them. On by default -- a dimmed column still costs the width and the
        -- eye that a used one would.
        hideInapplicable = true,
        -- Show only the people something is wrong with. Off by default: the
        -- full roster is what most people expect to open.
        hideReady        = false,
        scale            = 1,
        pos              = {},
    },
  },
}

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------

local win
local rows      = {}   -- flat, member-column major
local colHeader = {}   -- column key -> one frame per member column
local sweeper

local function MakeRow(parent, index)
    local r = CreateFrame("Frame", nil, parent)
    r._name = MakeText(r, NAME_SIZE)
    r._name:SetPoint("LEFT", r, "LEFT", 2, 0)
    r._name:SetWidth(NAME_W - 6)
    r._name:SetJustifyH("LEFT")

    -- Geometry belongs to Relayout, which runs before the window is ever
    -- shown: anything positioned here would only be overwritten.
    r._cells   = {}
    r._cellTex = {}
    for c, def in ipairs(COLUMNS) do
        if def.numeric then
            local fs = MakeText(r, SMALL_SIZE)
            fs:SetWidth(CELL_W)
            fs:SetJustifyH("CENTER")
            r._cells[c] = fs
            -- Full durability is the common case and three digits is the
            -- widest thing the grid draws, for the one value that says
            -- nothing. It gets the same tick every other column uses.
            local tex = r:CreateTexture(nil, "ARTWORK")
            tex:SetSize(ICON_SZ, ICON_SZ)
            tex:SetTexture(TEX_OK)
            tex:SetAlpha(0.9)
            tex:Hide()
            r._cellTex[c] = tex
        else
            local tex = r:CreateTexture(nil, "ARTWORK")
            tex:SetSize(ICON_SZ, ICON_SZ)
            tex:SetAlpha(0.9)
            r._cells[c] = tex
        end
    end

    rows[index] = r
    return r
end

local function Build()
    EnsureColumns()

    win = CreateFrame("Frame", "EllesmereUIRaidCheckWindow", UIParent)
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(200)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:Hide()
    EllesmereUI.RegisterEscapeClose(win)

    EllesmereUI.SolidTex(win, "BACKGROUND", 0.06, 0.08, 0.10, 0.95):SetAllPoints()
    EllesmereUI.MakeBorder(win, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PP)

    local title = MakeText(win, 13)
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -PAD)
    title:SetText(EllesmereUI.L("Raid Check"))
    local function TintTitle() title:SetTextColor(EllesmereUI.GetAccentColor()) end
    TintTitle()
    -- Set once at build would go stale on a theme change.
    EllesmereUI.RegAccent({ type = "callback", fn = TintTitle })

    -- Headers, once per member column so both halves are labelled. Icons
    -- rather than captions: twelve columns leave no room for words, and the
    -- spell's own art needs no translating. Each is a frame so it can be
    -- hovered -- twelve icons and not a word says nothing on its own.
    for mc = 1, MEMBER_COLS do
        for _, def in ipairs(COLUMNS) do
            local h = CreateFrame("Frame", nil, win)
            h:SetSize(ICON_SZ, ICON_SZ)
            local tex = h:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            local icon = def.icon
            if not icon and def.seed and C_Spell and C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(def.seed)
                icon = info and info.iconID
            end
            tex:SetTexture(icon or TEX_MISS)

            h:EnableMouse(true)
            h:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(ColumnName(def))
                if def.note then
                    GameTooltip:AddLine(EllesmereUI.L(def.note), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            h:SetScript("OnLeave", function() GameTooltip:Hide() end)

            colHeader[def.key] = colHeader[def.key] or {}
            colHeader[def.key][mc] = h
        end
    end

    -- Dragging the window, and remembering where it was left.
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = P()
        if not p then return end
        local point, _, relPoint, x, y = self:GetPoint()
        p.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Hooked on the frame rather than done in HideRaidCheck: Escape closes
    -- this through RegisterEscapeClose, which hides the frame directly. Arming
    -- and disarming anywhere else leaves the sweep running on a window nobody
    -- can see, for the rest of the session.
    win:HookScript("OnHide", function()
        if sweeper then sweeper.Stop() end
    end)

    local close = CreateFrame("Button", nil, win)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -PAD)
    local closeLbl = MakeText(close, 14)
    closeLbl:SetPoint("CENTER")
    closeLbl:SetText("x")
    closeLbl:SetAlpha(0.7)
    close:SetScript("OnEnter", function() closeLbl:SetAlpha(1) end)
    close:SetScript("OnLeave", function() closeLbl:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() win:Hide() end)

    for i = 1, MEMBER_COLS * COL_ROWS do MakeRow(win, i) end
end

-- Puts every header and cell where the current column set says it belongs, and
-- hides the ones that are not in it.
--
-- Guarded by a signature because it is real work -- forty rows times twelve
-- cells -- and the column set changes when the group does, not every two
-- seconds.
local lastLayoutSig
local function Relayout(visible, slotOf, memberCols, bodyW)
    local sig = memberCols .. "|" .. table.concat(visible, ",")
    if sig == lastLayoutSig then return end
    lastLayoutSig = sig

    local headerY = -(PAD + TITLE_H)
    for mc = 1, MEMBER_COLS do
        local baseX = PAD + (mc - 1) * (bodyW + COL_GAP)
        for _, def in ipairs(COLUMNS) do
            local h = colHeader[def.key][mc]
            local slot = slotOf[def.key]
            h:SetShown(slot ~= nil and mc <= memberCols)
            if slot then
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", win, "TOPLEFT",
                    baseX + NAME_W + (slot - 1) * CELL_W + (CELL_W - ICON_SZ) / 2,
                    headerY)
            end
        end
    end

    for i = 1, #rows do
        local r = rows[i]
        local mc   = math.floor((i - 1) / COL_ROWS)
        local line = (i - 1) % COL_ROWS
        r:SetSize(bodyW, ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", win, "TOPLEFT",
            PAD + mc * (bodyW + COL_GAP),
            headerY - HEADER_H - line * ROW_H)
        for ci, def in ipairs(COLUMNS) do
            local slot = slotOf[def.key]
            if slot then
                local x = NAME_W + (slot - 1) * CELL_W
                local cell = r._cells[ci]
                cell:ClearAllPoints()
                if def.numeric then
                    cell:SetPoint("LEFT", r, "LEFT", x, 0)
                    -- The tick shares the slot with the number; only one of
                    -- the two is ever shown.
                    local tex = r._cellTex[ci]
                    tex:ClearAllPoints()
                    tex:SetPoint("LEFT", r, "LEFT", x + (CELL_W - ICON_SZ) / 2, 0)
                else
                    cell:SetPoint("LEFT", r, "LEFT", x + (CELL_W - ICON_SZ) / 2, 0)
                end
            end
        end
    end
end

-- Repaints everything from a fresh roster read.
local function Refresh()
    if not win or not win:IsShown() then return end

    -- Roster first, auras second: a raid buff nobody present can cast is not a
    -- failing, and knowing that spares reading its ids on every member. With
    -- no Evoker, Blessing of the Bronze alone is thirteen ids across forty
    -- people that answer a column nobody will ever look at.
    local roster = ReadMembers()
    local classPresent = {}
    for _, e in ipairs(roster) do
        if e.class then classPresent[e.class] = true end
    end

    -- Roster-invariant, so decided once rather than per member per column.
    local restricted = Restricted()
    local answerable = {}
    for _, def in ipairs(COLUMNS) do
        answerable[def.key] = Answerable(def, restricted, classPresent)
    end

    for _, e in ipairs(roster) do
        e.checks = UnitChecks(e.unit, answerable, restricted)
        local r = reported[e.name]
        if r then
            e.durability = r.dur
            if r.we then e.checks[WENCHANT_KEY] = EnchantOK(r.we) end
        end
        -- Last, so the local read beats anything that came off the wire: it is
        -- current, and your own row must not depend on a message that is not
        -- sent at all when you are alone.
        if e.isSelf then
            for _, def in ipairs(SELF_COLS) do e.checks[def.key] = def.selfRead() end
        end
    end

    -- Which columns are on screen. Dimming an inapplicable one still spends
    -- width on it, so it can be dropped outright instead -- and then the
    -- remaining columns close ranks.
    local hide = ns.RaidCheckHideInapplicable()
    local visible, slotOf = {}, {}
    for _, def in ipairs(COLUMNS) do
        if answerable[def.key] or not hide then
            visible[#visible + 1] = def.key
            slotOf[def.key] = #visible
        end
    end

    -- Only the people something is wrong with, and only when asked -- nobody
    -- reads a fault count that is not on screen, so the whole pass is skipped
    -- rather than computed and discarded.
    --
    -- A missing verdict is NOT a fault. Someone whose client has not reported,
    -- or whose aura the game refused to disclose, has not failed anything, so
    -- only an explicit failure keeps a row.
    if ns.RaidCheckHideReady() then
        local short = {}
        local low = EllesmereUI.DURABILITY_LOW
        for _, e in ipairs(roster) do
            for _, def in ipairs(COLUMNS) do
                if answerable[def.key] then
                    local bad
                    if def.numeric then
                        bad = e.durability ~= nil and e.durability <= low
                    else
                        bad = e.checks[def.key] == false
                    end
                    -- One fault is enough to keep the row; what it is shows in
                    -- the grid.
                    if bad then
                        short[#short + 1] = e
                        break
                    end
                end
            end
        end
        roster = short
    end

    -- The window fits the group rather than the largest group possible.
    local n = #roster
    local memberCols = math.max(1, math.ceil(n / COL_ROWS))
    local rowsShown  = math.min(math.max(n, 1), COL_ROWS)
    local bodyW      = NAME_W + #visible * CELL_W
    win:SetSize(PAD * 2 + memberCols * bodyW + (memberCols - 1) * COL_GAP,
                PAD * 2 + TITLE_H + HEADER_H + rowsShown * ROW_H)
    Relayout(visible, slotOf, memberCols, bodyW)

    for i = 1, #rows do
        local r, e = rows[i], roster[i]
        if e then
            local c = EllesmereUI.GetClassColor(e.class)
            r._name:SetText(e.name)
            r._name:SetTextColor(c.r, c.g, c.b, e.online and 1 or 0.4)
            for ci, def in ipairs(COLUMNS) do
                local cell = r._cells[ci]
                local tex  = r._cellTex[ci]
                if not slotOf[def.key] then
                    cell:Hide()
                    if tex then tex:Hide() end
                elseif def.numeric then
                    -- The number, tinted on the suite's shared ramp -- except
                    -- at full, where the tick says the same in less room.
                    local pct = e.durability
                    local shown = pct and math.floor(pct + 0.5)
                    cell:SetShown(shown ~= nil and shown < 100)
                    tex:SetShown(shown == 100)
                    if shown and shown < 100 then
                        cell:SetText(shown)
                        cell:SetTextColor(EllesmereUI.GetDurabilityColor(pct))
                    end
                else
                    -- Deliberately not `answerable and checks or nil`: `and`
                    -- binds tighter, so a false verdict would fall through to
                    -- nil and a missing consumable would draw nothing at all.
                    local v
                    if answerable[def.key] then v = e.checks[def.key] end
                    if v == true then
                        cell:SetTexture(TEX_OK)
                        cell:Show()
                    elseif v == false then
                        cell:SetTexture(TEX_MISS)
                        cell:Show()
                    else
                        -- Unanswerable, or the client would not say.
                        cell:Hide()
                    end
                end
            end
            r:Show()
        else
            r:Hide()
        end
    end

    -- With hiding off, an unanswerable column stays but is dimmed, so it reads
    -- as "no data" rather than "nobody has it".
    for _, def in ipairs(COLUMNS) do
        if slotOf[def.key] then
            local on = answerable[def.key]
            for mc = 1, MEMBER_COLS do colHeader[def.key][mc]:SetAlpha(on and 0.8 or 0.2) end
        end
    end

    return true   -- the ticker keeps going while the window is up
end

-------------------------------------------------------------------------------
--  Options accessors
--
--  The page's entire view of this feature. Each reads with no argument and
--  writes with one, so the slice name and the profile walk never leave here.
-------------------------------------------------------------------------------

function ns.ApplyRaidCheckScale()
    if not win then return end
    local base = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    local p = P()
    win:SetScale(base * ((p and p.scale) or 1))
end

function ns.RaidCheckScale(v)
    local p = P()
    if v == nil then return (p and p.scale) or 1 end
    if not p then return end
    p.scale = v
    ns.ApplyRaidCheckScale()
end

function ns.RaidCheckHideReady(v)
    local p = P()
    if v == nil then return (p and p.hideReady) == true end
    if not p then return end
    p.hideReady = v
    lastLayoutSig = nil   -- the row count changed, so the grid is re-laid out
    Refresh()
end

function ns.RaidCheckHideInapplicable(v)
    local p = P()
    if v == nil then return not p or p.hideInapplicable ~= false end
    if not p then return end
    p.hideInapplicable = v
    lastLayoutSig = nil   -- the column set changed
    Refresh()
end

function ns.RaidCheckEnabled(v)
    local p = P()
    if v == nil then return (p and p.enabled) == true end
    if not p then return end
    p.enabled = v
    if not v then ns.HideRaidCheck() end
end

function ns.RaidCheckShowWithoutRank(v)
    local p = P()
    if v == nil then return (p and p.showWithoutRank) == true end
    if not p then return end
    p.showWithoutRank = v
    if not MayShow() then ns.HideRaidCheck() end
end

-------------------------------------------------------------------------------
--  Show / hide
-------------------------------------------------------------------------------

function ns.HideRaidCheck()
    if win then win:Hide() end   -- OnHide stops the sweep
end

-- `fromReadyCheck` suppresses the query: on that path every client has already
-- volunteered unprompted, and asking again would make each of them broadcast
-- once more for every leader whose window opened.
function ns.ShowRaidCheck(fromReadyCheck)
    if not MayShow() then return end
    if not win then Build() end

    ApplyFonts()
    ns.ApplyRaidCheckScale()
    win:ClearAllPoints()
    local p = P()
    local pos = p and p.pos
    if pos and pos.point then
        win:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER")
    end

    -- Ask before painting: answers land over the next few seconds and the
    -- sweep picks them up. Both transports throttle their own requests, so
    -- reopening the window repeatedly costs nothing.
    local LD = LibDur()
    if LD then LD:RequestDurability() end
    if not fromReadyCheck and EllesmereUI.Comms then
        EllesmereUI.Comms.Send(MSG_QUERY, "")
    end

    win:Show()
    Refresh()
    -- An interval driver, not a per-frame one: people drink their flask DURING
    -- the check so the grid has to follow, but not at frame rate. The frame is
    -- created here, in this addon's chunk, because the engine bills a
    -- handler's whole call tree to the addon that created the frame (see
    -- EllesmereUI_Ticker.lua) -- the shared driver would charge the parent.
    sweeper = sweeper or EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), Refresh, SWEEP_PERIOD)
    sweeper.Start()
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    -- Merges DB_DEFAULTS into the shared QoL profile, the arrangement every
    -- QoL feature uses.
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = ns.ApplyRaidCheckScale

    -- Listening and answering are unconditional and session-long: someone
    -- else's raid check should work whether or not you use your own, and a
    -- report that arrived before the window opened is already there when it
    -- does. Reports also answer other addons' requests, so the durability
    -- column is populated the moment the window opens.
    local LD = LibDur()
    if LD then LD:Register("EllesmereUIRaidCheck", NoteDurability) end

    local C = EllesmereUI.Comms
    if C then
        C.On(MSG_QUERY,  function() C.Send(MSG_REPORT, MyReport(), C.REPLY_SPREAD) end)
        C.On(MSG_REPORT, ReadReport)
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "READY_CHECK" then
        -- Volunteer on every ready check, feature enabled or not: a ready
        -- check is already the moment the group asks, so nobody needs to send
        -- a query and the answers are in flight before any window opens.
        local C = EllesmereUI.Comms
        if C then C.Send(MSG_REPORT, MyReport(), C.REPLY_SPREAD) end
        -- Any ready check, whoever started it: an assistant checking the raid
        -- and the leader should see the same thing.
        ns.ShowRaidCheck(true)
        return
    end
    -- Leaving the group, or losing rank without the option, closes it.
    if win and win:IsShown() and not MayShow() then ns.HideRaidCheck() end
end)

-------------------------------------------------------------------------------
--  Maintenance
--
--  Consumable ids change every patch, so this ships rather than living in a
--  branch: `ids` audits what is configured, `buffs` lists what the player is
--  carrying so a new id can be read off and pasted in. Inert until invoked,
--  the same arrangement as /euiloc.
-------------------------------------------------------------------------------
SLASH_EUIRAIDCHECK1 = "/euiraidcheck"
SlashCmdList["EUIRAIDCHECK"] = function(msg)
    local Print = EllesmereUI.Print
    local tag = "|cff0cd29fEllesmereUI:|r "
    EnsureColumns()

    if msg == "show" then
        -- Opening it without starting a ready check: looking at the raid
        -- should not require pinging everyone in it.
        if win and win:IsShown() then ns.HideRaidCheck() else ns.ShowRaidCheck() end
        return
    end

    if msg == "buffs" then
        -- The player's own auras, one line each: spell id, icon id, name, and
        -- the column it satisfies. When a consumable reads as missing, this
        -- says whether the id is simply unlisted or the sweep never saw the
        -- aura at all.
        --
        -- Matched through the same tables the grid uses, so it can never
        -- claim a hit the grid would not.
        for i = 1, AURA_SCAN_LIMIT do
            local ok, aura = pcall(GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            local id = aura.spellId
            if id and not (issecretvalue and issecretvalue(id)) then
                local key
                for _, def in ipairs(ICON_COLS) do
                    if aura.icon and def.icons[aura.icon] then key = def.key end
                end
                for _, def in ipairs(NAME_COLS) do
                    local p = def.prefix()
                    if p and aura.name and aura.name:find(p, 1, true) == 1 then key = def.key end
                end
                key = ID_TO_KEY[id] or key
                Print(tag .. id .. "  icon " .. tostring(aura.icon) .. "  "
                    .. (aura.name or "?")
                    .. (key and ("  |cff0cd29f-> " .. key .. "|r") or ""))
            end
        end
        return
    end

    Print(tag .. "auras restricted: " .. tostring(Restricted())
        .. "   vantus prefix: " .. (VantusPrefix() or "|cffff5555unresolved|r"))
    for _, def in ipairs(COLUMNS) do
        if def.ids then
            for id in pairs(def.ids) do
                local secret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
                    and C_Secrets.ShouldSpellAuraBeSecret(id)
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                Print(tag .. ColumnName(def) .. " " .. id .. "  "
                    .. ((info and info.name) or "|cffff5555?|r")
                    .. (secret and "  |cffff5555SECRET|r" or ""))
            end
        end
    end
end
