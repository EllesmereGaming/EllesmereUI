if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI or EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  EllesmereUIABR_RaidCheck.lua
--  Raid Check (CONSUMABLES > Raid Check, off by default): a window listing each
--  group member's flask, food, augment rune, vantus rune and missing raid
--  buffs. Opens on a ready check while the player leads or assists, or with
--  /euicheck.
--
--  Out of combat only. Flask and raid buff IDs are non-secret and looked up by
--  ID. Food has no fixed ID and needs an index scan, which errors under the
--  12.1 aura restriction, so food reads as unknown there, and so do augment
--  and vantus runes while their IDs are secret. Durability, weapon oils and healthstones of other
--  players are not readable without addon comms. The window hides when combat
--  starts; events are registered only while the option is on (READY_CHECK) or
--  the window is shown.
-------------------------------------------------------------------------------

local isSecret = issecretvalue or function() return false end

local WELL_FED_ICON = 136000
local EATING_ICON   = 133950
local AURA_SCAN_LIMIT = 255
local EXPIRE_SOON = 600     -- under 10 minutes left shows the time instead of a check
local TICK = 15             -- re-render interval for the countdowns while the window is open
local TEX_YES  = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_NO   = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local RUNE_ITEM   = 259085   -- header icons come from items: the buff spells have no cached texture
local VANTUS_ITEM = 272195   -- Vantus Rune: Tides

-- Midnight boss buffs of Vantus Runes (Season 1 and 2, both IDs of each boss).
local VANTUS_IDS = {
    1276666, 1276669, 1276682, 1276683, 1276685, 1276686, 1276687, 1276688,
    1276691, 1276698, 1276704, 1276705, 1276708, 1276709, 1276711, 1276712,
    1276714, 1276715,
    1300173, 1300174, 1303172, 1303173, 1303174, 1303175, 1303176, 1303177,
    1303178, 1303179, 1303180, 1303181, 1303182, 1303183, 1303184, 1303185,
    1303186, 1303187, 1310437, 1310439, 1319284, 1319286,
}

local PAD, TITLE_H, HEAD_H = 8, 24, 20
local ROW_H, NAME_W, CELL_W, ICON = 18, 110, 24, 14
local BUFF_SLOTS, BUFF_STEP = 6, 16
local CELLS = 4             -- flask, food, rune, vantus
local BUFFS_X = NAME_W + CELLS * CELL_W + 4
local BLOCK_W = BUFFS_X + BUFF_SLOTS * BUFF_STEP + 2
local BLOCK_GAP = 12
local ROWS_PER_BLOCK = 20
local TOTAL_ROWS = 3        -- Missing, Expiring soon, Unknown
local MIN_W = 400           -- fits the title bar and the note line
local NOTE_H = 16

local ev = CreateFrame("Frame")
local started = false
local frame
local rows, heads = {}, {}
local units = {}            -- display order
local isMember = {}         -- [unit] = true for listed group members
local states = {}           -- [unit] = last computed state
local shownUnits = {}       -- units drawn, in order
local Render                -- defined with the refresh code below
local providers = {}        -- [classToken] = true for connected members
local dirty, flushPending = {}, false
local flaskSet, runeIDs, raidBuffs
local runeReadable, vantusReadable  -- every ID of the list is non-secret on this client

local function CDB()
    local db = _G._EABR_AceDB
    local p = db and db.profile
    return p and p.consumables
end

local function Enabled()
    local c = CDB()
    return c and c.raidCheck == true
end

local function OpenOnReady()
    local c = CDB()
    return c and c.raidCheckOnReady ~= false
end

-- Default on: a missing key shows only the players who are not fully buffed.
local function OnlyMissing()
    local c = CDB()
    return not c or c.raidCheckOnlyMissing ~= false
end

local function CanLead()
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    return IsInGroup() and UnitIsGroupLeader("player")
end

local function Restricted()
    local ak = EllesmereUI.AuraKit
    return ak and ak.AurasRestricted() or false
end

local function Msg(text)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. text)
end

-------------------------------------------------------------------------------
--  Data (ABR's tables, published at its OnEnable)
-------------------------------------------------------------------------------
local function AllReadable(ids)
    local should = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if not should then return true end
    for i = 1, #ids do
        local ok, secret = pcall(should, ids[i])
        if not ok or isSecret(secret) or secret ~= false then return false end
    end
    return true
end

local function LoadData()
    if flaskSet then return true end
    flaskSet, runeIDs, raidBuffs = _G._EABR_FLASK_BUFF_ID_SET, _G._EABR_RUNE_BUFF_IDS, _G._EABR_RAID_BUFFS
    if not (flaskSet and runeIDs and raidBuffs) then
        flaskSet = nil
        return false
    end
    runeReadable = AllReadable(runeIDs)
    vantusReadable = AllReadable(VANTUS_IDS)
    return true
end

-- What a present aura reads as: its expiration time, or true when that is
-- secret or the aura never expires.
local function Present(aura)
    local exp = aura.expirationTime
    if exp == nil or isSecret(exp) or exp == 0 then return true end
    return exp
end

-- Non-nil means the aura is there, even when its fields are secret.
local function FindID(unit, id)
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
    if ok and aura ~= nil then return Present(aura) end
end

-- State values: true or an expiration time = has it, false = verified
-- missing, nil = cannot tell, "eating" = food channel up.
local function FlaskState(unit)
    for id in pairs(flaskSet) do
        local v = FindID(unit, id)
        if v then return v end
    end
    return false
end

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
    local sawReadable = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return nil end
        if not aura then break end
        local ic = aura.icon
        if ic ~= nil and not isSecret(ic) then
            sawReadable = true
            if ic == WELL_FED_ICON then return Present(aura) end
            if ic == EATING_ICON then return "eating" end
        end
    end
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

local function MakeCell(parent, x)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(CELL_W, ROW_H)
    cell:SetPoint("LEFT", parent, "LEFT", x, 0)
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetSize(ICON, ICON)
    cell.tex:SetPoint("CENTER")
    cell.q = EllesmereUI.MakeFont(cell, 11, nil, 0.6, 0.6, 0.6)
    cell.q:SetPoint("CENTER")
    cell.q:SetText("?")
    return cell
end

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(BLOCK_W, ROW_H)
    if i % 2 == 0 then
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetColorTexture(1, 1, 1, 0.03)
        stripe:SetAllPoints(r)
    end
    r.name = EllesmereUI.MakeFont(r, 11, nil, 1, 1, 1)
    r.name:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name:SetWidth(NAME_W - 6)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.flask = MakeCell(r, NAME_W)
    r.food  = MakeCell(r, NAME_W + CELL_W)
    r.rune  = MakeCell(r, NAME_W + 2 * CELL_W)
    r.vantus = MakeCell(r, NAME_W + 3 * CELL_W)
    r.buffs = {}
    for j = 1, BUFF_SLOTS do
        local t = r:CreateTexture(nil, "ARTWORK")
        t:SetSize(ICON, ICON)
        t:SetPoint("LEFT", r, "LEFT", BUFFS_X + (j - 1) * BUFF_STEP, 0)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.buffs[j] = t
    end
    r.buffsOk = r:CreateTexture(nil, "ARTWORK")
    r.buffsOk:SetSize(ICON, ICON)
    r.buffsOk:SetPoint("LEFT", r, "LEFT", BUFFS_X, 0)
    r.buffsOk:SetTexture(TEX_YES)
    r.buffsQ = EllesmereUI.MakeFont(r, 11, nil, 0.6, 0.6, 0.6)
    r.buffsQ:SetPoint("LEFT", r.buffsOk, "LEFT", 0, 0)
    r.buffsQ:SetText("?")
    rows[i] = r
    return r
end

local function MakeHeader(b)
    local h = CreateFrame("Frame", nil, frame)
    h:SetSize(BLOCK_W, HEAD_H)
    local function Icon(x, tex, tip)
        local hit = CreateFrame("Frame", nil, h)
        hit:SetSize(CELL_W, HEAD_H)
        hit:SetPoint("LEFT", h, "LEFT", x, 0)
        local t = hit:CreateTexture(nil, "ARTWORK")
        t:SetSize(ICON + 2, ICON + 2)
        t:SetPoint("CENTER")
        t:SetTexture(tex)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tip) end)
        hit:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end
    Icon(NAME_W, C_Spell.GetSpellTexture(1235110), EllesmereUI.L("Flask"))
    Icon(NAME_W + CELL_W, WELL_FED_ICON, EllesmereUI.L("Food"))
    Icon(NAME_W + 2 * CELL_W, C_Item.GetItemIconByID(RUNE_ITEM), EllesmereUI.L("Augment Rune"))
    Icon(NAME_W + 3 * CELL_W, C_Item.GetItemIconByID(VANTUS_ITEM), EllesmereUI.L("Vantus Rune"))
    local fs = EllesmereUI.MakeFont(h, 11, nil, 0.8, 0.8, 0.8)
    fs:SetPoint("LEFT", h, "LEFT", BUFFS_X, 0)
    fs:SetText(EllesmereUI.L("Raid Buffs"))
    heads[b] = h
    return h
end

local function Listen(shown)
    ev:UnregisterAllEvents()
    if not Enabled() then return end
    if OpenOnReady() then ev:RegisterEvent("READY_CHECK") end
    if shown then
        ev:RegisterEvent("UNIT_AURA")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("UNIT_CONNECTION")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
end

local function SavePosition()
    local c = CDB()
    if not c then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    c.raidCheckPos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "EllesmereUIRaidCheck", UIParent)
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
        if frame._ticker then frame._ticker:Cancel(); frame._ticker = nil end
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    bg:SetAllPoints(frame)
    local band = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    band:SetColorTexture(0, 0, 0, 0.5)
    band:SetPoint("TOPLEFT")
    band:SetPoint("TOPRIGHT")
    band:SetHeight(TITLE_H)
    EllesmereUI.MakeBorder(frame, 0.2, 0.2, 0.2, 1)

    local title = EllesmereUI.MakeFont(frame, 12, nil, 1, 1, 1)
    title:SetPoint("LEFT", frame, "TOPLEFT", PAD, -TITLE_H / 2)
    title:SetText(EllesmereUI.L("Raid Check"))

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -TITLE_H / 2)
    local cfs = EllesmereUI.MakeFont(close, 13, nil, 1, 1, 1)
    cfs:SetPoint("CENTER", close, "CENTER", 0, 1)
    cfs:SetText("x")
    cfs:SetAlpha(0.7)
    close:SetScript("OnEnter", function() cfs:SetAlpha(1) end)
    close:SetScript("OnLeave", function() cfs:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Only Not Fully Buffed checkbox, left of the close button; the label is part of the hit rect.
    local cb = CreateFrame("Button", nil, frame)
    cb:SetSize(14, 14)
    cb:SetPoint("RIGHT", close, "LEFT", -10, 0)
    local box = cb:CreateTexture(nil, "BACKGROUND")
    box:SetColorTexture(0.08, 0.08, 0.08, 0.92)
    box:SetAllPoints(cb)
    EllesmereUI.MakeBorder(cb, 0.35, 0.35, 0.35, 1)
    local check = cb:CreateTexture(nil, "ARTWORK")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetPoint("CENTER")
    check:SetSize(16, 16)
    local ar, ag, ab = 1, 1, 1
    if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
    check:SetVertexColor(ar, ag, ab)
    frame.check = check
    local cbLabel = EllesmereUI.MakeFont(frame, 11, nil, 0.85, 0.85, 0.85)
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -6, 0)
    cbLabel:SetText(EllesmereUI.L("Only Not Fully Buffed"))
    cb:SetHitRectInsets(-(cbLabel:GetStringWidth() + 6), 0, 0, 0)
    cb:SetScript("OnClick", function()
        local c = CDB()
        if not c then return end
        c.raidCheckOnlyMissing = not OnlyMissing()
        Render()
    end)

    frame.empty = EllesmereUI.MakeFont(frame, 11, nil, 0.4, 0.9, 0.4)
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, -TITLE_H - 2 - HEAD_H - 2)
    frame.empty:SetText(EllesmereUI.L("Everyone is fully buffed."))
    frame.empty:Hide()

    -- Totals under the first block: one count per column, aligned with its cells.
    local labels = { EllesmereUI.L("Missing"), EllesmereUI.L("Expiring soon"), EllesmereUI.L("Unknown") }
    frame.totals = {}
    for t = 1, TOTAL_ROWS do
        local tr = CreateFrame("Frame", nil, frame)
        tr:SetSize(BLOCK_W, ROW_H)
        tr:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, NOTE_H + (TOTAL_ROWS - t) * ROW_H)
        local lbl = EllesmereUI.MakeFont(tr, 11, nil, 0.85, 0.85, 0.85)
        lbl:SetPoint("LEFT", tr, "LEFT", 4, 0)
        lbl:SetText(labels[t])
        tr.counts = {}
        for k = 1, CELLS + 1 do
            local fs = EllesmereUI.MakeFont(tr, 11, nil, 1, 1, 1)
            if k <= CELLS then
                fs:SetPoint("CENTER", tr, "LEFT", NAME_W + (k - 0.5) * CELL_W, 0)
            else
                fs:SetPoint("CENTER", tr, "LEFT", BUFFS_X + ICON / 2, 0)
            end
            tr.counts[k] = fs
        end
        frame.totals[t] = tr
    end
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.15)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", frame.totals[1], "TOPLEFT", 0, 1)
    sep:SetPoint("BOTTOMRIGHT", frame.totals[1], "TOPRIGHT", 0, 1)
    frame.note = EllesmereUI.MakeFont(frame, 10, nil, 0.6, 0.6, 0.6)
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 4)

    local pos = CDB() and CDB().raidCheckPos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

-------------------------------------------------------------------------------
--  Roster and refresh: a state per unit, then Render draws the shown subset
-------------------------------------------------------------------------------
local function UnitClassToken(unit)
    local _, cls = UnitClass(unit)
    if cls == nil or isSecret(cls) then return nil end
    return cls
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
        local name = UnitName(u)
        if name ~= nil and not isSecret(name) then sortName[u] = strlower(name) end
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
    if isSecret(online) then online = true end
    if isSecret(dead) then dead = false end
    if isSecret(visible) then visible = true end
    s.online = online
    s.missing = 0
    s.buffsExp = nil
    local icons = s.icons
    if not online or dead or not visible then
        s.flask, s.food, s.rune, s.vantus = nil, nil, nil, nil
        for j = #icons, 1, -1 do icons[j] = nil end
        return
    end
    s.flask = FlaskState(unit)
    s.food = FoodState(unit, restricted)
    s.rune = ListState(unit, runeIDs, runeReadable, restricted)
    s.vantus = ListState(unit, VANTUS_IDS, vantusReadable, restricted)
    local n = 0
    for _, buff in ipairs(raidBuffs) do
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
local function NotFullyBuffed(s, now)
    return not s.flask or not s.food or not s.rune or not s.vantus or s.missing > 0
        or SoonLeft(s.flask, now) or SoonLeft(s.food, now) or SoonLeft(s.rune, now)
        or SoonLeft(s.vantus, now) or SoonLeft(s.buffsExp, now)
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

local function Layout(n)
    local blocks = math.max(1, math.ceil(n / ROWS_PER_BLOCK))
    local perBlock = math.max(1, math.ceil(n / blocks))
    for b = 1, blocks do
        local h = heads[b] or MakeHeader(b)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (b - 1) * (BLOCK_W + BLOCK_GAP), -TITLE_H - 2)
        h:Show()
    end
    for b = blocks + 1, #heads do heads[b]:Hide() end
    for i = 1, n do
        local r = rows[i] or MakeRow(i)
        local b = math.floor((i - 1) / perBlock)
        local slot = (i - 1) % perBlock
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", heads[b + 1], "BOTTOMLEFT", 0, -slot * ROW_H)
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    frame:SetSize(math.max(MIN_W, PAD * 2 + blocks * BLOCK_W + (blocks - 1) * BLOCK_GAP),
        TITLE_H + 2 + HEAD_H + perBlock * ROW_H + 6 + TOTAL_ROWS * ROW_H + NOTE_H)
end

-- totals[row][column]; columns are flask, food, rune, vantus, raid buffs.
local totals = { {}, {}, {} }

local function Tally(t, col, v, now)
    if v == false then t[1][col] = t[1][col] + 1
    elseif v == nil then t[3][col] = t[3][col] + 1
    elseif SoonLeft(v, now) then t[2][col] = t[2][col] + 1 end
end

function Render()
    local filter = OnlyMissing()
    local now = GetTime()
    for t = 1, TOTAL_ROWS do
        for k = 1, CELLS + 1 do totals[t][k] = 0 end
    end
    wipe(shownUnits)
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
            if not filter or NotFullyBuffed(s, now) then shownUnits[#shownUnits + 1] = u end
        end
    end
    local n = #shownUnits
    Layout(n)
    for i = 1, n do PaintRow(rows[i], shownUnits[i], now) end
    frame.empty:SetShown(n == 0)
    frame.check:SetShown(filter)
    for t = 1, TOTAL_ROWS do
        local counts = frame.totals[t].counts
        for k = 1, CELLS + 1 do
            local c = totals[t][k]
            counts[k]:SetText(c)
            if c == 0 then counts[k]:SetTextColor(0.3, 0.9, 0.3) else counts[k]:SetTextColor(1, 0.3, 0.3) end
        end
    end
    if frame._restricted then
        frame.note:SetText(EllesmereUI.L("Food and runes cannot be read here (aura restriction). ? = unknown"))
    else
        frame.note:SetText(EllesmereUI.L("? = unknown (offline, dead or out of range)"))
    end
end

local function Rebuild()
    if not frame or not frame:IsShown() or InCombatLockdown() then return end
    CollectUnits()
    local restricted = Restricted()
    frame._restricted = restricted
    wipe(states)
    for i = 1, #units do ComputeState(units[i], restricted) end
    Render()
end

local function Flush()
    flushPending = false
    if not frame or not frame:IsShown() or InCombatLockdown() then wipe(dirty); return end
    local restricted = Restricted()
    frame._restricted = restricted
    for unit in pairs(dirty) do
        if isMember[unit] then ComputeState(unit, restricted) end
    end
    wipe(dirty)
    Render()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local function Open()
    if InCombatLockdown() then
        Msg(EllesmereUI.L("Raid Check cannot be opened in combat."))
        return
    end
    if not LoadData() then return end
    Build()
    frame:Show()
    Listen(true)
    Rebuild()
    if not frame._ticker then frame._ticker = C_Timer.NewTicker(TICK, Render) end
end

local function Sync()
    if not Enabled() and frame then frame:Hide() end
    Listen(frame and frame:IsShown())
end

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" or event == "UNIT_CONNECTION" then
        if not isMember[unit] then return end
        dirty[unit] = true
        if not flushPending then
            flushPending = true
            C_Timer.After(0.2, Flush)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then frame:Hide(); return end
        Rebuild()
    elseif event == "READY_CHECK" then
        if CanLead() then Open() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if frame then frame:Hide() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not started then
            -- After every module's OnEnable, so ABR's DB and refresh exist; the
            -- options page and profile switches both go through that refresh.
            started = true
            if _G._EABR_RequestRefresh then hooksecurefunc("_EABR_RequestRefresh", Sync) end
            Sync()
        end
    end
end)
ev:RegisterEvent("PLAYER_ENTERING_WORLD")

SLASH_EUIRAIDCHECK1 = "/euicheck"
SlashCmdList["EUIRAIDCHECK"] = function()
    if not Enabled() then
        Msg(EllesmereUI.L("Raid Check is disabled in the EllesmereUI options."))
        return
    end
    if frame and frame:IsShown() then frame:Hide(); return end
    Open()
end

_G._EABR_RaidCheckOpen = function()
    if Enabled() then Open() end
end
