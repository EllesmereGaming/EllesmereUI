if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI or EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidBuffCheck.lua -- Raid Buff Check, part of Raid Tools
--
--  A window listing each group member's flask, food, augment rune, vantus rune
--  and missing raid buffs (QoL > Raid Tools > RAID BUFF CHECK, off by default).
--  Opens from the Buff Check button (any group member: it only reads auras)
--  and, if wanted, on every ready check while the player leads or assists.
--  Settings live in the Raid Tools profile slice;
--  RaidTools' Apply calls ns.BuffCheckSync, so nothing listens while it is off.
--
--  Out of combat only. Flask and raid buff IDs are non-secret and looked up by
--  ID. Food has no fixed ID and needs an index scan, which errors under the
--  12.1 aura restriction, so food reads as unknown there, and so do augment
--  and vantus runes while their IDs are secret. Durability, weapon oils and
--  healthstones of other players are not readable without addon comms. The
--  window hides when combat starts.
-------------------------------------------------------------------------------
local _, ns = ...

local IsSecret, PlainString = EllesmereUI.IsSecret, EllesmereUI.PlainString
local RT = ns.RT

local WELL_FED_ICON = 136000
local EATING_ICON   = 133950
local AURA_SCAN_LIMIT = 255
local EXPIRE_SOON = 600     -- under 10 minutes left shows the time instead of a check
local TICK = 15             -- countdown repaint interval while one shows
local TEX_YES  = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_NO   = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- SEASON UPDATE: the season's augment rune and Vantus Rune items (header icons).
local RUNE_ITEM   = 259085   -- header icons come from items: the buff spells have no cached texture
local VANTUS_ITEM = 272195   -- Vantus Rune: Tides

-- Buff IDs: the shared lists AuraBuff Reminders reads too. Older augment runes
-- count as missing. Raid buffs: only those whose class is in the group are checked.
local PREP = EllesmereUI.RAID_PREP_IDS
local FLASK_BUFF_IDS = PREP.flask
local RUNE_IDS, OLD_RUNE_IDS = PREP.rune, PREP.oldRune
local VANTUS_IDS = PREP.vantus
local RAID_BUFFS = PREP.raidBuffs

local PAD, TITLE_H, HEAD_H = 8, RT.TOPBAR_H, 20
local ROW_H, NAME_W, CELL_W, ICON = 18, 110, 24, 14
local BUFF_SLOTS, BUFF_STEP = 6, 16
local CELLS = 4             -- flask, food, rune, vantus
local RUNE_COL, VANTUS_COL = 3, 4
local BLOCK_GAP = 12
local ROWS_PER_BLOCK = 20
local TOTAL_ROWS = 3        -- Missing, Expiring soon, Unknown
local MIN_W = 400           -- fits the note line; the checkbox row can widen it
local NOTE_H = 16
local CB_H = 22             -- checkbox row between the totals and the note

local ev = CreateFrame("Frame")
local frame
local rows, heads = {}, {}
local units = {}            -- display order
local isMember = {}         -- [unit] = true for listed group members
local states = {}           -- [unit] = last computed state, reused
local shownUnits = {}       -- units drawn, in order
local Render                -- defined with the refresh code below

-- Column geometry. The rune and vantus columns drop out while their Require
-- box is off; SetColumns recomputes this and bumps colsKey, and every row,
-- header and totals row re-places itself once per change (Place*).
local colShown, colX = { true, true, true, true }, {}
local buffsX, blockW
local colsKey = 0

local function SetColumns(runeShown, vantusShown)
    if buffsX and colShown[RUNE_COL] == runeShown and colShown[VANTUS_COL] == vantusShown then return end
    colShown[RUNE_COL], colShown[VANTUS_COL] = runeShown, vantusShown
    local x = NAME_W
    for k = 1, CELLS do
        colX[k] = x
        if colShown[k] then x = x + CELL_W end
    end
    buffsX = x + 4
    blockW = buffsX + BUFF_SLOTS * BUFF_STEP + 2
    colsKey = colsKey + 1
end
SetColumns(true, false)
local providers = {}        -- [classToken] = true for connected members
local dirty, flushPending, rosterDirty = {}, false, false
local runeReadable, vantusReadable  -- every ID of the list is non-secret on this client; set on first open

local function CDB()
    return ns.RaidToolsProfile and ns.RaidToolsProfile()
end

local function Enabled()
    local c = CDB()
    return c and c.buffCheck == true
end

local function OpenOnReady()
    local c = CDB()
    return c and c.buffCheckOnReady ~= false
end

-- Default on: shows only the players who are not fully buffed.
local function OnlyMissing()
    local c = CDB()
    return not c or c.buffCheckOnlyMissing ~= false
end

-- Default on: a missing augment rune makes a player not fully buffed.
local function RuneRequired()
    local c = CDB()
    return not c or c.buffCheckRuneRequired ~= false
end

-- Default off: a missing vantus rune makes a player not fully buffed.
local function VantusRequired()
    local c = CDB()
    return c and c.buffCheckVantusRequired == true or false
end

local function Restricted()
    return EllesmereUI.AuraKit.AurasRestricted()
end

local function Msg(text)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. text)
end

-- On-screen text in the QoL font; Raid Tools' ApplyFonts keeps it current.
local function Text(parent, size, r, g, b)
    return RT.Text(frame, parent, size, r, g, b)
end

-------------------------------------------------------------------------------
--  Aura lookups
-------------------------------------------------------------------------------
local function AllReadable(ids)
    local should = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if not should then return true end
    for i = 1, #ids do
        local ok, secret = pcall(should, ids[i])
        if not ok or IsSecret(secret) or secret ~= false then return false end
    end
    return true
end

-- What a present aura reads as: its expiration time, or true when that is
-- secret or the aura never expires.
local function Present(aura)
    local exp = aura.expirationTime
    if exp == nil or IsSecret(exp) or exp == 0 then return true end
    return exp
end

-- Non-nil means the aura is there, even when its fields are secret.
local function FindID(unit, id)
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
    if ok and aura ~= nil then return Present(aura) end
end

-- State values: true or an expiration time = has it, false = verified
-- missing, nil = cannot tell, "eating" = food channel up.
local function ListState(unit, ids, readable, restricted)
    for i = 1, #ids do
        local v = FindID(unit, ids[i])
        if v then return v end
    end
    if restricted and not readable then return nil end
    return false
end

-- Seconds left when under EXPIRE_SOON, else nil.
local function SoonLeft(v, now)
    if type(v) ~= "number" then return nil end
    local left = v - now
    if left < EXPIRE_SOON then return math.max(0, left) end
end

local function MinutesText(left)
    return EllesmereUI.Lf("%dm", math.ceil(left / 60))
end

-- "eating" while the food channel is up.
local function FoodState(unit, restricted)
    if restricted then return nil end
    local sawReadable, eating = false, false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return nil end
        if not aura then break end
        local ic = aura.icon
        if ic ~= nil and not IsSecret(ic) then
            sawReadable = true
            if ic == WELL_FED_ICON then return Present(aura) end
            -- Eating only counts when no stat buff is up: refreshing one shows both.
            if ic == EATING_ICON then eating = true end
        end
    end
    if eating then return "eating" end
    if not sawReadable then return nil end
    return false
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function SetCell(cell, state, now)
    if state == nil then
        cell.tex:Hide()
        cell.q:SetText("?")
        cell.q:SetTextColor(0.6, 0.6, 0.6)
        cell.q:Show()
        return
    end
    local left = SoonLeft(state, now)
    if left then
        cell.tex:Hide()
        cell.q:SetText(MinutesText(left))
        cell.q:SetTextColor(1, 0.8, 0.2)
        cell.q:Show()
        return
    end
    cell.q:Hide()
    if state == "eating" then
        cell.tex:SetTexture(EATING_ICON)
        cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        cell.tex:SetTexture(state and TEX_YES or TEX_NO)
        cell.tex:SetTexCoord(0, 1, 0, 1)
    end
    cell.tex:Show()
end

local function MakeCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(CELL_W, ROW_H)
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetSize(ICON, ICON)
    cell.tex:SetPoint("CENTER")
    cell.q = Text(cell, 11, 0.6, 0.6, 0.6)
    cell.q:SetPoint("CENTER")
    cell.q:SetText("?")
    return cell
end

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, frame.table)
    r:SetHeight(ROW_H)
    if i % 2 == 0 then
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetColorTexture(1, 1, 1, 0.03)
        stripe:SetAllPoints(r)
    end
    r.name = Text(r, 11, 1, 1, 1)
    r.name:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name:SetWidth(NAME_W - 6)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.flask = MakeCell(r)
    r.food  = MakeCell(r)
    r.rune  = MakeCell(r)
    r.vantus = MakeCell(r)
    r.cells = { r.flask, r.food, r.rune, r.vantus }
    r.buffs = {}
    for j = 1, BUFF_SLOTS do
        local t = r:CreateTexture(nil, "ARTWORK")
        t:SetSize(ICON, ICON)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.buffs[j] = t
    end
    r.buffsOk = r:CreateTexture(nil, "ARTWORK")
    r.buffsOk:SetSize(ICON, ICON)
    r.buffsOk:SetTexture(TEX_YES)
    r.buffsQ = Text(r, 11, 0.6, 0.6, 0.6)
    r.buffsQ:SetPoint("LEFT", r.buffsOk, "LEFT", 0, 0)
    r.buffsQ:SetText("?")
    rows[i] = r
    return r
end

local function PlaceRow(r)
    if r._colsKey == colsKey then return end
    r._colsKey = colsKey
    r:SetWidth(blockW)
    for k = 1, CELLS do
        local cell = r.cells[k]
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", r, "LEFT", colX[k], 0)
        cell:SetShown(colShown[k])
    end
    for j = 1, BUFF_SLOTS do
        r.buffs[j]:ClearAllPoints()
        r.buffs[j]:SetPoint("LEFT", r, "LEFT", buffsX + (j - 1) * BUFF_STEP, 0)
    end
    r.buffsOk:ClearAllPoints()
    r.buffsOk:SetPoint("LEFT", r, "LEFT", buffsX, 0)
end

local function PlaceHeader(h)
    if h._colsKey == colsKey then return end
    h._colsKey = colsKey
    h:SetWidth(blockW)
    for k = 1, CELLS do
        local hit = h.icons[k]
        hit:ClearAllPoints()
        hit:SetPoint("LEFT", h, "LEFT", colX[k], 0)
        hit:SetShown(colShown[k])
    end
    h.buffsLabel:ClearAllPoints()
    h.buffsLabel:SetPoint("LEFT", h, "LEFT", buffsX, 0)
end

local function PlaceTotals(tr)
    if tr._colsKey == colsKey then return end
    tr._colsKey = colsKey
    tr:SetWidth(blockW)
    for k = 1, CELLS do
        local fs = tr.counts[k]
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tr, "LEFT", colX[k] + CELL_W / 2, 0)
        fs:SetShown(colShown[k])
    end
    tr.counts[CELLS + 1]:ClearAllPoints()
    tr.counts[CELLS + 1]:SetPoint("CENTER", tr, "LEFT", buffsX + ICON / 2, 0)
end

local function MakeHeader(b)
    local h = CreateFrame("Frame", nil, frame.table)
    h:SetHeight(HEAD_H)
    h.icons = {}
    local function Icon(tex, tip)
        local hit = CreateFrame("Frame", nil, h)
        hit:SetSize(CELL_W, HEAD_H)
        h.icons[#h.icons + 1] = hit
        local t = hit:CreateTexture(nil, "ARTWORK")
        t:SetSize(ICON + 2, ICON + 2)
        t:SetPoint("CENTER")
        t:SetTexture(tex)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tip) end)
        hit:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end
    Icon(C_Spell.GetSpellTexture(FLASK_BUFF_IDS[1]), EllesmereUI.L("Flask"))
    Icon(WELL_FED_ICON, EllesmereUI.L("Food"))
    Icon(C_Item.GetItemIconByID(RUNE_ITEM), EllesmereUI.L("Augment Rune"))
    Icon(C_Item.GetItemIconByID(VANTUS_ITEM), EllesmereUI.L("Vantus Rune"))
    h.buffsLabel = Text(h, 11, 0.8, 0.8, 0.8)
    h.buffsLabel:SetText(EllesmereUI.L("Raid Buffs"))
    heads[b] = h
    return h
end

-- The window's events follow the window; READY_CHECK follows the option.
local function Listen(shown)
    ev:UnregisterAllEvents()
    if Enabled() and OpenOnReady() then ev:RegisterEvent("READY_CHECK") end
    if shown then
        ev:RegisterEvent("UNIT_AURA")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("UNIT_CONNECTION")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
end

-- Kept as a TOPLEFT offset: the height (and width) change with the roster and
-- the filter, and the top-left corner must stay put while they do.
local function SavePosition()
    local c = CDB()
    if not c then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    local x, y = left, top - UIParent:GetTop()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    c.buffCheckPos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = x, y = y }
end

local function StopWake()
    if frame._wake then frame._wake:Cancel() end
    frame._wake, frame._wakeAt = nil, nil
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "EllesmereUIRaidBuffCheck", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:Hide()
    frame:SetScript("OnHide", function()
        Listen(false)
        StopWake()
    end)
    RT.AddFontOwner(frame)
    RT.SkinPanelBg(frame)
    RT.SkinPanelBorder(frame)

    local title = Text(frame, 12, 1, 1, 1)
    title:SetPoint("LEFT", frame, "TOPLEFT", PAD, -TITLE_H / 2)
    title:SetText(EllesmereUI.L("Raid Buff Check"))

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(14, 14)
    close:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -TITLE_H / 2)
    RT.SkinButtonChrome(close)
    local cfs = Text(close, 12, 1, 1, 1)
    cfs:SetPoint("CENTER", close, "CENTER", 0, 1)
    cfs:SetText("x")
    cfs:SetAlpha(0.7)
    close:SetScript("OnEnter", function() cfs:SetAlpha(1) end)
    close:SetScript("OnLeave", function() cfs:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Checkbox row above the note, left to right; each label is part of its
    -- box's hit rect.
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    local function MakeCheckbox(text, onClick)
        local cb = CreateFrame("Button", nil, frame)
        cb:SetSize(14, 14)
        local box = cb:CreateTexture(nil, "BACKGROUND")
        box:SetColorTexture(0.08, 0.08, 0.08, 0.92)
        box:SetAllPoints(cb)
        EllesmereUI.MakeBorder(cb, 0.35, 0.35, 0.35, 1)
        cb.check = cb:CreateTexture(nil, "ARTWORK")
        cb.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        cb.check:SetPoint("CENTER")
        cb.check:SetSize(16, 16)
        cb.check:SetVertexColor(ar, ag, ab)
        cb.label = Text(frame, 11, 0.85, 0.85, 0.85)
        cb.label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        cb.label:SetText(text)
        cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 6), 0, 0)
        cb:SetScript("OnClick", onClick)
        return cb
    end
    frame.onlyBox = MakeCheckbox(EllesmereUI.L("Hide Fully Buffed"), function()
        local c = CDB()
        if not c then return end
        c.buffCheckOnlyMissing = not OnlyMissing()
        Render()
    end)
    frame.runeBox = MakeCheckbox(EllesmereUI.L("Require Augment Rune"), function()
        local c = CDB()
        if not c then return end
        c.buffCheckRuneRequired = not RuneRequired()
        Render()
    end)
    frame.vantusBox = MakeCheckbox(EllesmereUI.L("Require Vantus Rune"), function()
        local c = CDB()
        if not c then return end
        c.buffCheckVantusRequired = not VantusRequired()
        Render()
    end)
    frame.boxes = { frame.onlyBox, frame.runeBox, frame.vantusBox }
    frame.onlyBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 4, NOTE_H + (CB_H - 14) / 2)
    frame.runeBox:SetPoint("LEFT", frame.onlyBox.label, "RIGHT", 16, 0)
    frame.vantusBox:SetPoint("LEFT", frame.runeBox.label, "RIGHT", 16, 0)

    frame.empty = Text(frame, 11, 0.4, 0.9, 0.4)
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, -TITLE_H - 6)
    frame.empty:SetText(EllesmereUI.L("Everyone is fully buffed."))
    frame.empty:Hide()

    -- The table (column headers, player rows, totals) in one container, so
    -- "everyone fully buffed" hides it in one go.
    frame.table = CreateFrame("Frame", nil, frame)
    frame.table:SetAllPoints(frame)

    -- Totals under the first block: one count per column, aligned with its cells.
    -- Render places them; a row of zeros is hidden.
    local labels = { EllesmereUI.L("Missing"), EllesmereUI.L("Expiring soon"), EllesmereUI.L("Unknown") }
    frame.totals = {}
    for t = 1, TOTAL_ROWS do
        local tr = CreateFrame("Frame", nil, frame.table)
        tr:SetHeight(ROW_H)
        local lbl = Text(tr, 11, 0.85, 0.85, 0.85)
        lbl:SetPoint("LEFT", tr, "LEFT", 4, 0)
        lbl:SetText(labels[t])
        tr.counts = {}
        for k = 1, CELLS + 1 do
            tr.counts[k] = Text(tr, 11, 1, 1, 1)
        end
        frame.totals[t] = tr
    end
    frame.sep = frame.table:CreateTexture(nil, "ARTWORK")
    frame.sep:SetColorTexture(1, 1, 1, 0.15)
    frame.sep:SetHeight(1)
    frame.note = Text(frame, 10, 0.6, 0.6, 0.6)
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 4)

    local pos = CDB() and CDB().buffCheckPos
    if pos and pos.point == "TOPLEFT" then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() / 2 - MIN_W / 2, -150)
    end
end

-------------------------------------------------------------------------------
--  Roster and refresh: a state per unit, then Render draws the shown subset
-------------------------------------------------------------------------------
local function UnitClassToken(unit)
    local _, cls = UnitClass(unit)
    return PlainString(cls)
end

-- Alphabetical by name; a secret name sorts last, by unit token.
local sortName = {}
local function SortByName(a, b)
    local na, nb = sortName[a], sortName[b]
    if na ~= nb then
        if not na then return false end
        if not nb then return true end
        return na < nb
    end
    return a < b
end

local function CollectUnits()
    wipe(units)
    wipe(providers)
    wipe(isMember)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) then units[#units + 1] = u end
        end
    else
        units[1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            local u = "party" .. i
            if UnitExists(u) then units[#units + 1] = u end
        end
    end
    wipe(sortName)
    for i = 1, #units do
        local u = units[i]
        local name = PlainString(UnitName(u))
        if name then sortName[u] = strlower(name) end
    end
    table.sort(units, SortByName)
    for i = 1, #units do
        local u = units[i]
        isMember[u] = true
        local cls = UnitIsConnected(u) and UnitClassToken(u)
        if cls then providers[cls] = true end
    end
end

local function ComputeState(unit, restricted)
    local s = states[unit]
    if not s then s = { icons = {} }; states[unit] = s end
    local online = UnitIsConnected(unit)
    local dead = UnitIsDeadOrGhost(unit)
    local visible = UnitIsVisible(unit)
    if IsSecret(online) then online = true end
    if IsSecret(dead) then dead = false end
    if IsSecret(visible) then visible = true end
    s.online = online
    s.missing = 0
    s.buffsExp = nil
    local icons = s.icons
    if not online or dead or not visible then
        s.flask, s.food, s.rune, s.vantus = nil, nil, nil, nil
        for j = #icons, 1, -1 do icons[j] = nil end
        return
    end
    s.flask = ListState(unit, FLASK_BUFF_IDS, true, false)
    s.food = FoodState(unit, restricted)
    s.rune = ListState(unit, RUNE_IDS, runeReadable, restricted)
    if not s.rune and ListState(unit, OLD_RUNE_IDS, true, false) then s.rune = false end
    s.vantus = ListState(unit, VANTUS_IDS, vantusReadable, restricted)
    local n = 0
    for _, buff in ipairs(RAID_BUFFS) do
        if providers[buff.class] then
            local has
            local ids = buff.buffIDs
            for k = 1, #ids do
                has = FindID(unit, ids[k])
                if has then break end
            end
            if not has then
                n = n + 1
                icons[n] = buff.castSpell
            elseif type(has) == "number" and (not s.buffsExp or has < s.buffsExp) then
                s.buffsExp = has
            end
        end
    end
    for j = #icons, n + 1, -1 do icons[j] = nil end
    s.missing = n
end

-- Missing, unknown (nil) and running out count; eating does not.
local function NotFullyBuffed(s, now, runeRequired, vantusRequired)
    if runeRequired and (not s.rune or SoonLeft(s.rune, now)) then return true end
    if vantusRequired and (not s.vantus or SoonLeft(s.vantus, now)) then return true end
    return not s.flask or not s.food or s.missing > 0
        or SoonLeft(s.flask, now) or SoonLeft(s.food, now) or SoonLeft(s.buffsExp, now)
end

local function PaintRow(r, unit, now)
    local s = states[unit]
    r.name:SetText(UnitName(unit))
    local cls = UnitClassToken(unit)
    local cc = cls and EllesmereUI.GetClassColor(cls)
    if cc and s.online then r.name:SetTextColor(cc.r, cc.g, cc.b) else r.name:SetTextColor(0.5, 0.5, 0.5) end
    SetCell(r.flask, s.flask, now)
    SetCell(r.food, s.food, now)
    SetCell(r.rune, s.rune, now)
    SetCell(r.vantus, s.vantus, now)
    local icons = s.icons
    for j = 1, BUFF_SLOTS do
        local id = icons[j]
        if id then
            r.buffs[j]:SetTexture(C_Spell.GetSpellTexture(id))
            r.buffs[j]:Show()
        else
            r.buffs[j]:Hide()
        end
    end
    -- flask is nil only for a row that was not read at all (offline, dead, out of range).
    local left = s.missing == 0 and SoonLeft(s.buffsExp, now)
    r.buffsOk:SetShown(s.flask ~= nil and s.missing == 0 and not left)
    if s.flask == nil then
        r.buffsQ:SetText("?")
        r.buffsQ:SetTextColor(0.6, 0.6, 0.6)
        r.buffsQ:Show()
    elseif left then
        r.buffsQ:SetText(MinutesText(left))
        r.buffsQ:SetTextColor(1, 0.8, 0.2)
        r.buffsQ:Show()
    else
        r.buffsQ:Hide()
    end
end

-- Wide enough for the note line and the checkbox row (its labels follow the font).
local function MinWidth()
    local w = PAD + 4
    for i, cb in ipairs(frame.boxes) do
        if i > 1 then w = w + 16 end
        w = w + 14 + 6 + cb.label:GetStringWidth()
    end
    return math.max(MIN_W, w + PAD)
end

-- n == 0: Render hides the whole table; the empty message takes one row
-- under the title.
local function Layout(n, nTotals)
    if n == 0 then
        frame:SetSize(MinWidth(), TITLE_H + 2 + ROW_H + 6 + CB_H + NOTE_H)
        frame._bgFit()
        return
    end
    local blocks = math.max(1, math.ceil(n / ROWS_PER_BLOCK))
    local perBlock = math.max(1, math.ceil(n / blocks))
    for b = 1, blocks do
        local h = heads[b] or MakeHeader(b)
        PlaceHeader(h)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (b - 1) * (blockW + BLOCK_GAP), -TITLE_H - 2)
        h:Show()
    end
    for b = blocks + 1, #heads do heads[b]:Hide() end
    for i = 1, n do
        local r = rows[i] or MakeRow(i)
        PlaceRow(r)
        local b = math.floor((i - 1) / perBlock)
        local slot = (i - 1) % perBlock
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", heads[b + 1], "BOTTOMLEFT", 0, -slot * ROW_H)
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    frame:SetSize(math.max(MinWidth(), PAD * 2 + blocks * blockW + (blocks - 1) * BLOCK_GAP),
        TITLE_H + 2 + HEAD_H + perBlock * ROW_H + 6 + nTotals * ROW_H + CB_H + NOTE_H)
    frame._bgFit()
end

-- totals[row][column]; columns are flask, food, rune, vantus, raid buffs.
local totals = { {}, {}, {} }

local function Tally(t, col, v, now)
    if v == false then t[1][col] = t[1][col] + 1
    elseif v == nil then t[3][col] = t[3][col] + 1
    elseif SoonLeft(v, now) then t[2][col] = t[2][col] + 1 end
end

-- The next time the drawing changes on its own: a countdown's next step, or a
-- shown buff crossing into its last 10 minutes. One timer, re-armed only for
-- an earlier time.
local wakeAt
local function Wake(v, now)
    if type(v) ~= "number" then return end
    local at = v - EXPIRE_SOON
    if at <= now then at = now + TICK end
    if not wakeAt or at < wakeAt then wakeAt = at end
end

local function OnWake()
    frame._wake, frame._wakeAt = nil, nil
    Render()
end

function Render()
    local filter = OnlyMissing()
    local runeRequired, vantusRequired = RuneRequired(), VantusRequired()
    SetColumns(runeRequired, vantusRequired)
    local now = GetTime()
    for t = 1, TOTAL_ROWS do
        for k = 1, CELLS + 1 do totals[t][k] = 0 end
    end
    wipe(shownUnits)
    wakeAt = nil
    for i = 1, #units do
        local u = units[i]
        local s = states[u]
        if s then
            Tally(totals, 1, s.flask, now)
            Tally(totals, 2, s.food, now)
            Tally(totals, 3, s.rune, now)
            Tally(totals, 4, s.vantus, now)
            -- Raid buffs: unread row = unknown, a missing buff = missing, else the soonest expiry.
            if s.flask == nil then
                totals[3][5] = totals[3][5] + 1
            elseif s.missing > 0 then
                totals[1][5] = totals[1][5] + 1
            elseif SoonLeft(s.buffsExp, now) then
                totals[2][5] = totals[2][5] + 1
            end
            Wake(s.flask, now)
            Wake(s.food, now)
            if runeRequired then Wake(s.rune, now) end
            if vantusRequired then Wake(s.vantus, now) end
            Wake(s.buffsExp, now)
            if not filter or NotFullyBuffed(s, now, runeRequired, vantusRequired) then
                shownUnits[#shownUnits + 1] = u
            end
        end
    end
    -- Totals rows with a non-zero count, stacked upward from the note line.
    local n = #shownUnits
    local nTotals, top = 0, nil
    for t = TOTAL_ROWS, 1, -1 do
        local tr = frame.totals[t]
        PlaceTotals(tr)
        local any = false
        for k = 1, CELLS + 1 do
            local c = totals[t][k]
            tr.counts[k]:SetText(c)
            if c == 0 then
                tr.counts[k]:SetTextColor(0.3, 0.9, 0.3)
            else
                tr.counts[k]:SetTextColor(1, 0.3, 0.3)
                -- A hidden column's count does not keep its row up.
                if k > CELLS or colShown[k] then any = true end
            end
        end
        tr:SetShown(any)
        if any then
            tr:ClearAllPoints()
            tr:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, NOTE_H + CB_H + nTotals * ROW_H)
            nTotals = nTotals + 1
            top = tr
        end
    end
    frame.sep:ClearAllPoints()
    if top then
        frame.sep:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 0, 1)
        frame.sep:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 0, 1)
    end
    frame.sep:SetShown(top ~= nil)

    Layout(n, nTotals)
    for i = 1, n do PaintRow(rows[i], shownUnits[i], now) end
    -- Nobody listed (everyone fully buffed): no header and no totals either,
    -- even when a count is non-zero for a column the filter ignores.
    frame.table:SetShown(n > 0)
    frame.empty:SetShown(n == 0)
    frame.onlyBox.check:SetShown(filter)
    frame.runeBox.check:SetShown(runeRequired)
    frame.vantusBox.check:SetShown(vantusRequired)
    if frame._restricted then
        frame.note:SetText(EllesmereUI.L("Food and runes cannot be read here (aura restriction). ? = unknown"))
    else
        frame.note:SetText(EllesmereUI.L("? = unknown (offline, dead or out of range)"))
    end
    if wakeAt and (not frame._wakeAt or wakeAt < frame._wakeAt) then
        if frame._wake then frame._wake:Cancel() end
        frame._wake = C_Timer.NewTimer(wakeAt - now, OnWake)
        frame._wakeAt = wakeAt
    end
end

local function Rebuild()
    if not frame or not frame:IsShown() or InCombatLockdown() then return end
    CollectUnits()
    local restricted = Restricted()
    frame._restricted = restricted
    for i = 1, #units do ComputeState(units[i], restricted) end
    Render()
end

-- Same-burst events end in one pass: a roster or connection change re-reads
-- every member, aura changes only the members they named.
local function Flush()
    flushPending = false
    if not frame or not frame:IsShown() or InCombatLockdown() then
        wipe(dirty)
        rosterDirty = false
        return
    end
    if rosterDirty then
        rosterDirty = false
        wipe(dirty)
        Rebuild()
        return
    end
    local restricted = Restricted()
    frame._restricted = restricted
    for unit in pairs(dirty) do
        if isMember[unit] then ComputeState(unit, restricted) end
    end
    wipe(dirty)
    Render()
end

local function Schedule()
    if not flushPending then
        flushPending = true
        C_Timer.After(0.2, Flush)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local function Open()
    if InCombatLockdown() then
        Msg(EllesmereUI.L("Raid Buff Check cannot be opened in combat."))
        return
    end
    if runeReadable == nil then
        runeReadable = AllReadable(RUNE_IDS)
        vantusReadable = AllReadable(VANTUS_IDS)
    end
    Build()
    frame:Show()
    Listen(true)
    Rebuild()
end

-- Called by RaidTools' Apply (login, settings, profile switch).
function ns.BuffCheckSync()
    if not Enabled() and frame then frame:Hide() end
    Listen(frame and frame:IsShown())
end

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if not isMember[unit] then return end
        dirty[unit] = true
        Schedule()
    elseif event == "UNIT_CONNECTION" then
        -- Also who can provide the raid buffs.
        if not isMember[unit] then return end
        rosterDirty = true
        Schedule()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then frame:Hide(); return end
        rosterDirty = true
        Schedule()
    elseif event == "READY_CHECK" then
        if RT.HasAssist() then Open() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if frame then frame:Hide() end
    end
end)

-- The Buff Check button.
function ns.ToggleBuffCheck()
    if not Enabled() then return end
    if frame and frame:IsShown() then frame:Hide(); return end
    Open()
end
