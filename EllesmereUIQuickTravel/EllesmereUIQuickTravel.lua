if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQuickTravel.lua
--  Quick Travel popup: hearths, class/racial travel, mage teleports/portals,
--  and Hero's Path dungeon/raid teleports. Opt-in via Quick Travel options.
--
--  Taint / secret-value safety:
--   - Every spell/item/toy id is a static integer from HEARTH_TELEPORT_DATA or
--     EllesmereUI.SEASON_PORTALS. Never read LFG or other secret fields.
--   - SecureActionButtonTemplate rows are pooled once on first enable (OOC).
--     SetAttribute runs only out of combat; the last OOC layout is what
--     stays on the unprotected shell.
--   - Cooldown reads skip in protected instances.
--   - Lua cannot Show() or Hide() the popup in combat (secure children).
--     A companion SecureHandlerStateTemplate hides the shell and flyouts
--     on combat entry. Lua Hide() is still deferred if it runs in lockdown.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = ns

local EUI = EllesmereUI
local PP  = EUI and EUI.PP
local DATA = EUI and EUI.HEARTH_TELEPORT_DATA

local PAD         = 10
local POPUP_W     = 572
local COL_GAP     = 12
local LEFT_COL_W  = 200
local RIGHT_COL_W = 340
local BODY_W      = POPUP_W - PAD * 2
local COL_RIGHT_X = LEFT_COL_W + COL_GAP
local TITLE_H     = 32
local ROW_H       = 28
local SEC_HDR_H   = 18
local SEC_GAP     = 8
local TAB_H       = 22
local ROW_POOL_SZ = 100
local FLYOUT_MIN_W = 120
local FLYOUT_MAX_W = 260
local FLYOUT_ROW_H = 24
local FLYOUT_BTN_ICON = 20
local FLYOUT_BTN_TEXT_GAP = 6
local FLYOUT_BTN_RIGHT_PAD = 4
local FLYOUT_PAD  = 8
local FLYOUT_MAX_H = 380
local FLYOUT_BTN_POOL = 60
local FLYOUT_PANEL_COUNT = 14
local FLYOUT_BRIDGE_W = 24
local FLYOUT_GAP = 2
local TRIGGER_POOL_SZ = 14
local MAX_BODY_H  = 480

local popup, toggleBtn, rowPool, secHeaders, flyoutTriggerPool, flyouts, flyoutBtnPool
local flyoutMeasureFS
local dungeonTab = "current"
local pendingLayout
local db
local pendingHide
local combatHider
local ev

local DB_DEFAULTS = {
    profile = {
        enabled = false,
        toggleKey = false,
        scale = 1.05,
        hideAfterUse = true,
        highlightCurrentKey = true,
        keystoneReminder = false,
        show = {},
        randomPool = {},
        randomHearthstones = true,
        pos = nil,
    },
}
ns.DB_DEFAULTS = DB_DEFAULTS

local function P()
    return db and db.profile
end

local function IsEnabled()
    local p = P()
    return p and p.enabled == true
end

local function ShowOn(key)
    local p = P()
    local s = p and p.show
    if not s or s[key] == nil then return true end
    return s[key] ~= false
end

local function RandomHearthOn()
    local p = P()
    if p and p.randomHearthstones == false then return false end
    return true
end

local function NormalizeDungeonTab(showSeasonal, showLegacy)
    if showSeasonal and showLegacy then
        if dungeonTab ~= "current" and dungeonTab ~= "legacy" then
            dungeonTab = "current"
        end
        return
    end
    if showSeasonal then
        dungeonTab = "current"
    elseif showLegacy then
        dungeonTab = "legacy"
    end
end

local function RandomPoolOn(id)
    local p = P()
    local pool = p and p.randomPool
    if not pool or pool[id] == nil then return true end
    return pool[id] ~= false
end

local BuildAll, ApplyHearthTeleport, TogglePopup, ShowPopup, HidePopup
local RefreshHighlights, SavePosition, ApplySavedPosition
local PopulateFlyout
local pendingFlyoutPopulate
local EnsureTeleportPromptHook, SyncEvents

local mapToSpell = {}
do
    if DATA and DATA.LEGACY_DUNGEONS then
        for _, e in ipairs(DATA.LEGACY_DUNGEONS) do
            if e.mapID and e.spell then mapToSpell[e.mapID] = e.spell end
        end
    end
    if EUI and EUI.SEASON_PORTALS then
        for _, e in ipairs(EUI.SEASON_PORTALS) do
            if e.dungeonID and e.spellID then mapToSpell[e.dungeonID] = e.spellID end
        end
    end
end

local function ResolveFont()
    return (EUI and EUI.GetFontPath and EUI.GetFontPath("quickTravel")) or "Fonts\\FRIZQT__.TTF"
end
local function ResolveOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("quickTravel")) or ""
end
local function MakeLabel(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = ResolveOutline()
    if EUI and EUI.PrimeFontShadow then EUI.PrimeFontShadow(fs, flags == "") end
    fs:SetFont(ResolveFont(), size, flags)
    if r then fs:SetTextColor(r, g or 1, b or 1, a or 1) end
    return fs
end

local function PlayerRaceFile()
    return select(2, UnitRace("player"))
end

local function RaceAllowed(raceReq)
    if not raceReq then return true end
    local rf = PlayerRaceFile()
    if type(raceReq) == "table" then
        for _, r in ipairs(raceReq) do if r == rf then return true end end
        return false
    end
    return raceReq == rf
end

local function HasToy(id)
    return PlayerHasToy and PlayerHasToy(id)
end

local function HasItem(id)
    return C_Item and C_Item.GetItemCount and (C_Item.GetItemCount(id) or 0) > 0
end

local function ToyIcon(id)
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local _, _, icon = C_ToyBox.GetToyInfo(id)
        if icon then return icon end
    end
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134414
end

local SPELL_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

local function IsKnownSpell(spellID)
    if not spellID then return false end
    if C_SpellBook and SPELL_BANK then
        if C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID, SPELL_BANK) then
            return true
        end
        if C_SpellBook.IsSpellInSpellBook
            and C_SpellBook.IsSpellInSpellBook(spellID, SPELL_BANK, true) then
            return true
        end
        if C_SpellBook.FindSpellBookSlotForSpell then
            local slot = C_SpellBook.FindSpellBookSlotForSpell(spellID, true, true, false, false)
            if slot then return true end
        end
    end
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnown and IsSpellKnown(spellID) then return true end
    return false
end

local function FactionSpellPair(spellID)
    if not spellID or not DATA or not DATA.FACTION_SPELLS then return nil end
    return DATA.FACTION_SPELLS[spellID]
end

local function ResolveFactionSpellID(spellID)
    local pair = FactionSpellPair(spellID)
    if not pair then return spellID end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Horde" then return pair.horde or spellID end
    return pair.alliance or spellID
end

local function IsKnownSpellOrFaction(spellID)
    if IsKnownSpell(spellID) then return true end
    local pair = FactionSpellPair(spellID)
    if not pair then return false end
    if pair.alliance and IsKnownSpell(pair.alliance) then return true end
    if pair.horde and IsKnownSpell(pair.horde) then return true end
    return false
end

local function FactionGroupKey(spellID)
    local pair = FactionSpellPair(spellID)
    if pair then
        return (pair.alliance or 0) .. ":" .. (pair.horde or 0)
    end
    return spellID
end

local function StripMagePrefix(name)
    if not name then return name end
    return name:gsub("^Teleport: ", ""):gsub("^Portal: ", "")
end

local function SpellEntryRef(spellID, opts)
    opts = opts or {}
    if not spellID then return nil end
    local castID = ResolveFactionSpellID(spellID)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(castID)
    return {
        kind = "spell", id = castID,
        name = info and info.name or ("Spell " .. castID),
        icon = info and info.iconID or 134400,
        cancelForm = opts.cancelForm,
    }
end

local function SpellEntry(spellID, opts)
    opts = opts or {}
    if not IsKnownSpellOrFaction(spellID) then return nil end
    return SpellEntryRef(spellID, opts)
end

local function ApplyEntryVisuals(icon, nameFS)
    if icon then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
    end
    if nameFS then
        nameFS:SetTextColor(0.85, 0.85, 0.85, 1)
    end
end

local function ApplyEntryInteractivity(btn)
    if not btn then return end
    btn:Enable()
    btn:EnableMouse(true)
    if btn._hl then btn._hl:Show() end
end

local function ToyEntry(id)
    if not HasToy(id) then return nil end
    if DATA and DATA.RACE_LOCKED_HEARTHS and not RaceAllowed(DATA.RACE_LOCKED_HEARTHS[id]) then
        return nil
    end
    local name = C_ToyBox and C_ToyBox.GetToyInfo and select(2, C_ToyBox.GetToyInfo(id))
    return { kind = "toy", id = id, name = name or ("Toy " .. id), icon = ToyIcon(id) }
end

local function ItemEntry(id)
    if not HasItem(id) then return nil end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return {
        kind = "item", id = id,
        name = name or ("Item " .. id),
        icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134414,
    }
end

local function FixedHearthEntry(entry)
    if not entry then return nil end
    -- Unique destination stones can live as a bag item or a toy depending on
    -- the account; try the declared kind first, then the other.
    if entry.kind == "item" then
        return ItemEntry(entry.id) or ToyEntry(entry.id)
    end
    return ToyEntry(entry.id) or ItemEntry(entry.id)
end

local function BuildRandomPool()
    local pool = {}
    if not DATA then return pool end
    if RandomPoolOn(DATA.BASE_HEARTH_ITEM) and HasItem(DATA.BASE_HEARTH_ITEM) then
        pool[#pool + 1] = DATA.BASE_HEARTH_ITEM
    end
    for _, id in ipairs(DATA.COSMETIC_HEARTHS or {}) do
        if RandomPoolOn(id) and HasToy(id) and RaceAllowed(DATA.RACE_LOCKED_HEARTHS and DATA.RACE_LOCKED_HEARTHS[id]) then
            pool[#pool + 1] = id
        end
    end
    return pool
end

local function RollRandomHearth()
    local pool = BuildRandomPool()
    if #pool == 0 then return nil end
    local pick = pool[math.random(#pool)]
    if pick == DATA.BASE_HEARTH_ITEM then return { kind = "item", id = pick } end
    return { kind = "toy", id = pick }
end

local function GetOwnedKeystone()
    if EUI and EUI.InProtectedInstance and EUI.InProtectedInstance() then return 0, 0 end
    if not C_MythicPlus then return 0, 0 end
    local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
    local lvl = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
    return map, lvl
end

local function HighlightSpellIDs()
    local keySpell, reminderSpell, keyLvl
    local p = P()
    if not p then return keySpell, reminderSpell, keyLvl end
    if EUI and EUI.InProtectedInstance and EUI.InProtectedInstance() then
        return keySpell, reminderSpell, keyLvl
    end
    if ShowOn("seasonalDungeons") and p.highlightCurrentKey ~= false then
        local map, lvl = GetOwnedKeystone()
        if map and map > 0 and lvl and lvl > 0 then
            keySpell = mapToSpell[map]
            keyLvl = lvl
        end
    end
    if ShowOn("seasonalDungeons") and p.keystoneReminder == true then
        local tp = _G.EUITeleportPopup
        if tp and tp:IsShown() then
            local getter = _G._EUI_GetTeleportPromptSpellID
            if getter then reminderSpell = getter() end
        end
    end
    return keySpell, reminderSpell, keyLvl
end

RefreshHighlights = function()
    if not popup or not popup:IsShown() or not rowPool then return end
    local keySpell, reminderSpell, keyLvl = HighlightSpellIDs()
    local EG = EUI and EUI.ELLESMERE_GREEN
    for i = 1, #rowPool do
        local r = rowPool[i]
        if r:IsShown() and r._nameFS then
            local sid = r._spellID
            local hl = sid and ((keySpell and sid == keySpell) or (reminderSpell and sid == reminderSpell))
            if hl and EG then
                local txt = r._baseName or "?"
                if keySpell and sid == keySpell and keyLvl and keyLvl > 0 then
                    txt = txt .. " +" .. keyLvl
                end
                r._nameFS:SetText(txt)
                r._nameFS:SetTextColor(EG.r, EG.g, EG.b, 1)
            elseif r._baseName then
                r._nameFS:SetText(r._baseName)
                ApplyEntryVisuals(r._icon, r._nameFS)
            end
        end
    end
end
_G._EUI_RefreshHearthTeleportHighlight = RefreshHighlights

local function ApplySecureAttributes(btn, entry)
    if not btn then return end
    btn:SetAttribute("type", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("item", nil)
    btn:SetAttribute("toy", nil)
    btn:SetAttribute("macrotext", nil)
    if not entry then
        ApplyEntryInteractivity(btn)
        return
    end
    if entry.kind == "spell" then
        if entry.cancelForm then
            btn:SetAttribute("type", "macro")
            local info = C_Spell.GetSpellInfo(entry.id)
            btn:SetAttribute("macrotext", "/cancelform\n/cast " .. (info and info.name or ""))
        else
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", entry.id)
        end
    elseif entry.kind == "toy" then
        btn:SetAttribute("type", "toy")
        btn:SetAttribute("toy", entry.id)
    elseif entry.kind == "item" then
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", entry.id)
    end
    ApplyEntryInteractivity(btn)
end

local function ApplyRowAttributes(row, entry)
    ApplySecureAttributes(row._btn, entry)
end

local function UpdateRowCooldown(row, entry)
    if not row._cd then return end
    if EUI and EUI.InProtectedInstance and EUI.InProtectedInstance() then
        row._cd:Clear()
        return
    end
    if not entry then row._cd:Clear(); return end
    if entry.kind == "spell" then
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(entry.id)
        if cdInfo and cdInfo.duration and cdInfo.duration > 1.5 then
            row._cd:SetCooldown(cdInfo.startTime, cdInfo.duration)
        else row._cd:Clear() end
    elseif entry.kind == "toy" or entry.kind == "item" then
        local id = entry.id
        if id and C_Container and C_Container.GetItemCooldown then
            local ok, start, dur = pcall(C_Container.GetItemCooldown, id)
            if ok and start and dur and dur > 1.5 then
                row._cd:SetCooldown(start, dur)
            else row._cd:Clear() end
        else row._cd:Clear() end
    else row._cd:Clear() end
end

local function FlyoutRoot(frame)
    local p = frame
    while p do
        if flyouts then
            for _, f in ipairs(flyouts) do
                if p == f then return f end
            end
        end
        p = p:GetParent()
    end
end

local function FlyoutHoverActive(flyout)
    if not flyout or not flyout:IsShown() then return false end
    if flyout:IsMouseOver() then return true end
    if flyout._bridge and flyout._bridge:IsMouseOver() then return true end
    if flyout._anchor and flyout._anchor:IsMouseOver() then return true end
    if flyout._scrollFrame and flyout._scrollFrame:IsMouseOver() then return true end
    if flyoutBtnPool then
        for i = 1, FLYOUT_BTN_POOL do
            local btn = flyoutBtnPool[i]
            if btn and btn:IsShown() and FlyoutRoot(btn) == flyout and btn:IsMouseOver() then
                return true
            end
        end
    end
    return false
end

local function MaybeHideFlyout(flyout)
    if flyout and flyout:IsShown() and not FlyoutHoverActive(flyout) then
        flyout:Hide()
    end
end

local function HideAllFlyouts()
    if not flyouts then return end
    for _, f in ipairs(flyouts) do
        if f:IsShown() then
            f:Hide()
        end
    end
end

local function SetCombatHiderEnabled(on)
    if not combatHider or InCombatLockdown() then return end
    if on then
        RegisterStateDriver(combatHider, "euiqtcombat", "[combat] combat; nocombat")
    else
        UnregisterStateDriver(combatHider, "euiqtcombat")
    end
end

local function MeasureFlyoutWidth(entries)
    if not flyoutMeasureFS then
        local m = CreateFrame("Frame", nil, UIParent)
        m:Hide()
        flyoutMeasureFS = m:CreateFontString(nil, "ARTWORK")
        local flags = ResolveOutline()
        flyoutMeasureFS:SetFont(ResolveFont(), 10, flags)
    end
    local rowInner = FLYOUT_BTN_ICON + FLYOUT_BTN_TEXT_GAP + FLYOUT_BTN_RIGHT_PAD
    local maxTextW = 0
    for _, entry in ipairs(entries or {}) do
        flyoutMeasureFS:SetText(entry.name or "?")
        maxTextW = math.max(maxTextW, flyoutMeasureFS:GetStringWidth())
    end
    local innerW = rowInner + maxTextW
    return math.max(FLYOUT_MIN_W, math.min(FLYOUT_MAX_W, innerW + FLYOUT_PAD * 2))
end

local function PositionFlyout(flyout, anchor)
    if not flyout or not anchor then return end
    flyout:ClearAllPoints()
    flyout._anchor = anchor
    flyout:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -(FLYOUT_BRIDGE_W + FLYOUT_GAP), 0)
end

local function OpenFlyout(flyout)
    if not flyout then return end
    if flyouts then
        for _, f in ipairs(flyouts) do
            if f ~= flyout then
                f:Hide()
            end
        end
    end
    if popup then
        flyout:SetScale(popup:GetScale() or 1)
    end
    if InCombatLockdown() then
        pendingFlyoutPopulate = flyout
    else
        pendingFlyoutPopulate = nil
        PopulateFlyout(flyout, flyout._entries or {}, flyout._anchor, 0)
    end
    if flyout._anchor then
        PositionFlyout(flyout, flyout._anchor)
    end
    flyout:Show()
    flyout:Raise()
end

local function RefreshCooldowns()
    if not popup or not popup:IsShown() or not rowPool then return end
    for i = 1, #rowPool do
        local r = rowPool[i]
        if r:IsShown() and r._entry then
            UpdateRowCooldown(r, r._entry)
        end
    end
end

local function EnsureFlyoutBridge(flyout)
    if not flyout._bridge then
        local bridge = CreateFrame("Frame", nil, flyout)
        bridge:SetFrameLevel(flyout:GetFrameLevel() + 5)
        bridge:EnableMouse(true)
        bridge:SetScript("OnEnter", function() end)
        bridge:SetScript("OnLeave", function() MaybeHideFlyout(flyout) end)
        flyout._bridge = bridge
    end
    local bridge = flyout._bridge
    bridge:ClearAllPoints()
    bridge:SetWidth(FLYOUT_BRIDGE_W)
    bridge:SetPoint("TOPRIGHT", flyout, "TOPLEFT", 0, 0)
    return bridge
end

local function CreateFlyoutPool()
    flyouts = {}
    flyoutBtnPool = {}
    flyoutTriggerPool = {}
    local body = popup._body
    for i = 1, TRIGGER_POOL_SZ do
        local r = CreateFrame("Frame", nil, body)
        r:SetHeight(ROW_H)
        r:Hide()
        r:EnableMouse(true)
        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r._icon = icon
        r._nameFS = MakeLabel(r, 11, 0.85, 0.85, 0.85, 1)
        r._nameFS:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        r._nameFS:SetPoint("RIGHT", -18, 0)
        r._nameFS:SetJustifyH("LEFT")
        r._nameFS:SetWordWrap(false)
        r._chevron = MakeLabel(r, 11, 0.5, 0.5, 0.5, 1)
        r._chevron:SetPoint("RIGHT", -6, 0)
        r._chevron:SetText(">")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)
        local EG = EUI and EUI.ELLESMERE_GREEN
        r:SetScript("OnEnter", function(self)
            if self._flyout and #(self._flyout._entries or {}) > 0 then
                OpenFlyout(self._flyout)
                if EG and self._nameFS then
                    self._nameFS:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end)
        r:SetScript("OnLeave", function(self)
            if self._nameFS then self._nameFS:SetTextColor(0.85, 0.85, 0.85, 1) end
            MaybeHideFlyout(self._flyout)
        end)
        flyoutTriggerPool[i] = r
    end
    for i = 1, FLYOUT_PANEL_COUNT do
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(100 + i)
        f:Hide()
        f:EnableMouse(true)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.10, 0.96)
        if PP and PP.CreateBorder then PP.CreateBorder(f, 0.25, 0.25, 0.25, 0.8, 1, "OVERLAY", 5) end
        f:SetScript("OnLeave", function(self) MaybeHideFlyout(self) end)
        if not f._mousePad then
            f._mousePad = CreateFrame("Frame", nil, f)
            f._mousePad:SetAllPoints()
            f._mousePad:SetFrameLevel(f:GetFrameLevel() + 1)
            f._mousePad:EnableMouse(true)
            f._mousePad:SetScript("OnLeave", function() MaybeHideFlyout(f) end)
        end
        EnsureFlyoutBridge(f)
        flyouts[i] = f
    end
    for i = 1, FLYOUT_BTN_POOL do
        flyoutBtnPool[i] = CreateFrame("Button", "EUIHearthFlyoutBtn" .. i, UIParent, "SecureActionButtonTemplate")
        flyoutBtnPool[i]:Hide()
        flyoutBtnPool[i]:RegisterForClicks("AnyUp", "AnyDown")
        flyoutBtnPool[i]:SetScript("OnLeave", function(btn)
            MaybeHideFlyout(FlyoutRoot(btn))
        end)
        flyoutBtnPool[i]:SetScript("PostClick", function(btn)
            if btn._randomRef then
                C_Timer.After(0, function()
                    if popup and popup:IsShown() and not InCombatLockdown() then BuildAll() end
                end)
            end
            local hp = P()
            if not hp or hp.hideAfterUse ~= false then HidePopup() end
        end)
    end
end

local function EnsureFlyoutScroll(flyout)
    if flyout._scrollFrame then return flyout._scrollFrame, flyout._scrollChild end
    local sf = CreateFrame("ScrollFrame", nil, flyout)
    sf:SetPoint("TOPLEFT", FLYOUT_PAD, -FLYOUT_PAD)
    sf:SetPoint("BOTTOMRIGHT", -FLYOUT_PAD, FLYOUT_PAD)
    sf:EnableMouseWheel(true)
    sf:SetFrameLevel(flyout:GetFrameLevel() + 8)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local child = self:GetScrollChild()
        local maxS = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 20)))
    end)
    sf:SetScript("OnLeave", function() MaybeHideFlyout(flyout) end)
    local child = CreateFrame("Frame", nil, sf)
    sf:SetScrollChild(child)
    flyout._scrollFrame = sf
    flyout._scrollChild = child
    return sf, child
end

PopulateFlyout = function(flyout, entries, anchor, btnOffset)
    if not flyout then return end
    entries = entries or {}
    btnOffset = btnOffset or 0
    flyout:Hide()
    local panelW = MeasureFlyoutWidth(entries)
    local innerW = panelW - FLYOUT_PAD * 2
    local innerH = #entries * FLYOUT_ROW_H
    local contentH = FLYOUT_PAD * 2 + innerH
    local panelH = math.min(contentH, FLYOUT_MAX_H)
    flyout:SetSize(panelW, math.max(panelH, 1))
    if anchor then
        PositionFlyout(flyout, anchor)
    else
        flyout:ClearAllPoints()
        flyout._anchor = nil
    end
    local bridge = EnsureFlyoutBridge(flyout)
    bridge:SetHeight(panelH)

    local btnParent = flyout
    if contentH > FLYOUT_MAX_H then
        local sf, child = EnsureFlyoutScroll(flyout)
        sf:Show()
        child:SetWidth(innerW)
        child:SetHeight(innerH)
        sf:SetVerticalScroll(0)
        btnParent = child
    elseif flyout._scrollFrame then
        flyout._scrollFrame:Hide()
    end

    for i, entry in ipairs(entries) do
        local btn = flyoutBtnPool[btnOffset + i]
        if not btn then break end
        btn:SetParent(btnParent)
        btn:SetSize(innerW, FLYOUT_ROW_H)
        if btnParent == flyout then
            btn:SetPoint("TOPLEFT", flyout, "TOPLEFT", FLYOUT_PAD, -FLYOUT_PAD - (i - 1) * FLYOUT_ROW_H)
        else
            btn:SetPoint("TOPLEFT", btnParent, "TOPLEFT", 0, -(i - 1) * FLYOUT_ROW_H)
        end
        btn:SetFrameLevel(flyout:GetFrameLevel() + 10)
        btn:Show()
        btn._entry = entry
        btn._randomRef = entry.randomRef
        ApplySecureAttributes(btn, entry)
        if not btn._icon then
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(20, 20)
            btn._icon:SetPoint("LEFT", 0, 0)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._nameFS = MakeLabel(btn, 10, 0.85, 0.85, 0.85, 1)
            btn._nameFS:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
            btn._nameFS:SetPoint("RIGHT", -4, 0)
            btn._nameFS:SetJustifyH("LEFT")
            btn._nameFS:SetWordWrap(false)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            btn._hl = hl
        end
        btn._icon:SetTexture(entry.icon)
        btn._nameFS:SetText(entry.name or "?")
        ApplyEntryVisuals(btn._icon, btn._nameFS)
        ApplyEntryInteractivity(btn)
    end

    for j = btnOffset + #entries + 1, FLYOUT_BTN_POOL do
        local btn = flyoutBtnPool[j]
        if not btn then break end
        btn:Hide()
        btn:SetAttribute("type", nil)
        btn:SetAttribute("spell", nil)
        btn:SetAttribute("item", nil)
        btn:SetAttribute("toy", nil)
        btn:SetAttribute("macrotext", nil)
    end
end

local function CreateRowPool()
    rowPool = {}
    secHeaders = {}
    local body = popup._body
    for i = 1, ROW_POOL_SZ do
        local r = CreateFrame("Frame", nil, body)
        r:SetHeight(ROW_H)
        r:Hide()
        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r._icon = icon
        r._nameFS = MakeLabel(r, 11, 0.85, 0.85, 0.85, 1)
        r._nameFS:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        r._nameFS:SetPoint("RIGHT", -4, 0)
        r._nameFS:SetJustifyH("LEFT")
        r._nameFS:SetWordWrap(false)
        local btn = CreateFrame("Button", "EUIHearthTeleportRow" .. i, r, "SecureActionButtonTemplate")
        btn:SetAllPoints()
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetFrameLevel(r:GetFrameLevel() + 2)
        btn:SetScript("PostClick", function()
            if r._randomRef then
                C_Timer.After(0, function()
                    if popup and popup:IsShown() and not InCombatLockdown() then BuildAll() end
                end)
            end
            local hp = P()
            if not hp or hp.hideAfterUse ~= false then HidePopup() end
        end)
        r._btn = btn
        local cd = CreateFrame("Cooldown", nil, r, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        r._cd = cd
        local EG = EUI and EUI.ELLESMERE_GREEN
        btn:SetScript("OnEnter", function()
            if EG then r._nameFS:SetTextColor(EG.r, EG.g, EG.b, 1) end
        end)
        btn:SetScript("OnLeave", RefreshHighlights)
        rowPool[i] = r
    end
    CreateFlyoutPool()
end

local function AcquireSecHeader(idx)
    if secHeaders[idx] then return secHeaders[idx] end
    local h = CreateFrame("Frame", nil, popup._body)
    h:SetHeight(SEC_HDR_H)
    h._label = MakeLabel(h, 10, 1, 1, 1, 0.56)
    h._label:SetPoint("LEFT", 0, 0)
    secHeaders[idx] = h
    return h
end

local function CollectEntries()
    local left, right = {}, {}
    if not DATA then return left, right end

    if ShowOn("hearthstones") then
        local rows = {}
        local rowsAfter = {}
        local hearthFlyout = {}
        if RandomHearthOn() then
            local pool = BuildRandomPool()
            if #pool > 0 then
                local pick = RollRandomHearth()
                if pick then
                    rows[#rows + 1] = {
                        kind = pick.kind, id = pick.id,
                        name = "Random Hearthstone",
                        icon = pick.kind == "item" and (C_Item.GetItemIconByID(pick.id) or 134414) or ToyIcon(pick.id),
                        randomRef = true,
                    }
                end
            end
        end
        for _, id in ipairs(DATA.COSMETIC_HEARTHS or {}) do
            local e = ToyEntry(id)
            if e then hearthFlyout[#hearthFlyout + 1] = e end
        end
        for _, entry in ipairs(DATA.FIXED_HEARTHS or {}) do
            local e = FixedHearthEntry(entry)
            if e then rowsAfter[#rowsAfter + 1] = e end
        end
        local hearthFlyouts = {}
        if #hearthFlyout > 0 then
            hearthFlyouts[#hearthFlyouts + 1] = {
                label = "Hearthstones", icon = hearthFlyout[1].icon, entries = hearthFlyout,
            }
        end
        if #rows > 0 or #rowsAfter > 0 or #hearthFlyouts > 0 then
            left[#left + 1] = {
                title = "HEARTHSTONE", entries = rows, flyouts = hearthFlyouts,
                entriesAfterFlyouts = rowsAfter,
            }
        end
    end

    local classEntries = {}
    local classFlyouts = {}
    local _, cls = UnitClass("player")

    if ShowOn("racials") then
        for _, e in ipairs(DATA.RACIALS or {}) do
            if RaceAllowed(e.race) then
                local se = SpellEntry(e.spell)
                if se then classEntries[#classEntries + 1] = se end
            end
        end
    end

    if ShowOn("classTeleports") then
        for _, e in ipairs(DATA.CLASS_TELEPORTS or {}) do
            if cls == e.class then
                local se = SpellEntry(e.spell, { cancelForm = e.cancelForm })
                if se then classEntries[#classEntries + 1] = se end
            end
        end
    end

    if cls == "MAGE" then
        if ShowOn("mageTeleports") then
            local list = {}
            local fallback
            for _, sid in ipairs(DATA.MAGE_TELEPORTS or {}) do
                local se = SpellEntry(sid)
                if se then
                    se.name = StripMagePrefix(se.name)
                    if not fallback then fallback = se end
                    list[#list + 1] = se
                end
            end
            if fallback then
                classFlyouts[#classFlyouts + 1] = {
                    label = "Teleports", icon = (list[1] or fallback).icon, entries = list,
                }
            end
        end
        if ShowOn("magePortals") then
            local list = {}
            local fallback
            for _, sid in ipairs(DATA.MAGE_PORTALS or {}) do
                local se = SpellEntry(sid)
                if se then
                    se.name = StripMagePrefix(se.name)
                    if not fallback then fallback = se end
                    list[#list + 1] = se
                end
            end
            if fallback then
                classFlyouts[#classFlyouts + 1] = {
                    label = "Portals", icon = (list[1] or fallback).icon, entries = list,
                }
            end
        end
    end

    if #classEntries > 0 or #classFlyouts > 0 then
        left[#left + 1] = {
            title = "CLASS / RACIALS", entries = classEntries, flyouts = classFlyouts,
        }
    end

    local dungeons = {}
    local dungeonFlyouts = {}
    local showSeasonal = ShowOn("seasonalDungeons")
    local showLegacy = ShowOn("legacyDungeons")
    if showSeasonal or showLegacy then
        NormalizeDungeonTab(showSeasonal, showLegacy)
        if dungeonTab == "current" and showSeasonal and EUI.SEASON_PORTALS then
            for _, e in ipairs(EUI.SEASON_PORTALS) do
                local se = SpellEntry(e.spellID)
                if se then
                    if e.short then se.name = se.name .. " (" .. e.short .. ")" end
                    dungeons[#dungeons + 1] = se
                end
            end
        elseif dungeonTab == "legacy" and showLegacy then
            local byExpansion = {}
            local seen = {}
            for _, e in ipairs(DATA.LEGACY_DUNGEONS or {}) do
                local key = FactionGroupKey(e.spell)
                if not seen[key] then
                    seen[key] = true
                    local se = SpellEntry(e.spell)
                    if se then
                        local exp = e.expansion or "Other"
                        if not byExpansion[exp] then byExpansion[exp] = {} end
                        byExpansion[exp][#byExpansion[exp] + 1] = se
                    end
                end
            end
            local function SortEntries(list)
                table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
            end
            local order = DATA.LEGACY_EXPANSION_ORDER or {}
            local listed = {}
            for _, expName in ipairs(order) do
                local list = byExpansion[expName]
                if list and #list > 0 then
                    SortEntries(list)
                    dungeonFlyouts[#dungeonFlyouts + 1] = {
                        label = expName, icon = list[1].icon, entries = list,
                    }
                    listed[expName] = true
                end
            end
            for expName, list in pairs(byExpansion) do
                if not listed[expName] and #list > 0 then
                    SortEntries(list)
                    dungeonFlyouts[#dungeonFlyouts + 1] = {
                        label = expName, icon = list[1].icon, entries = list,
                    }
                end
            end
        end
        right[#right + 1] = {
            title = "DUNGEONS", entries = dungeons, flyouts = dungeonFlyouts,
            tabs = showSeasonal and showLegacy,
        }
    end

    if ShowOn("raids") then
        local list = {}
        for _, sid in ipairs(DATA.RAIDS or {}) do
            local se = SpellEntry(sid)
            if se then list[#list + 1] = se end
        end
        if #list > 0 then right[#right + 1] = { title = "RAIDS", entries = list } end
    end

    return left, right
end

BuildAll = function()
    if not popup or InCombatLockdown() then
        pendingLayout = true
        return
    end
    pendingLayout = nil
    HideAllFlyouts()
    pendingFlyoutPopulate = nil
    for i = 1, #rowPool do rowPool[i]:Hide(); rowPool[i]._entry = nil end
    if flyoutTriggerPool then
        for i = 1, #flyoutTriggerPool do flyoutTriggerPool[i]:Hide() end
    end
    if flyoutBtnPool then
        for i = 1, FLYOUT_BTN_POOL do
            local btn = flyoutBtnPool[i]
            if btn then
                btn:Hide()
                btn:SetAttribute("type", nil)
                btn:SetAttribute("spell", nil)
                btn:SetAttribute("item", nil)
                btn:SetAttribute("toy", nil)
                btn:SetAttribute("macrotext", nil)
            end
        end
    end
    for _, h in pairs(secHeaders) do h:Hide() end
    if popup._tabBar then popup._tabBar:Hide() end

    local leftSections, rightSections = CollectEntries()
    local rowIdx = 0
    local secIdx = 0
    local trigIdx = 0
    local flyoutPanelIdx = 0

    local function LayoutRows(entries, colX, colW, y)
        for _, entry in ipairs(entries or {}) do
            rowIdx = rowIdx + 1
            if rowIdx > ROW_POOL_SZ then return y end
            local r = rowPool[rowIdx]
            r:Show()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", popup._body, "TOPLEFT", colX, -y)
            r:SetPoint("TOPRIGHT", popup._body, "TOPLEFT", colX + colW, -y)
            r._icon:SetTexture(entry.icon)
            r._nameFS:SetText(entry.name or "?")
            r._baseName = entry.name
            r._spellID = entry.kind == "spell" and entry.id or nil
            r._randomRef = entry.randomRef
            r._entry = entry
            ApplyEntryVisuals(r._icon, r._nameFS)
            ApplyRowAttributes(r, entry)
            UpdateRowCooldown(r, entry)
            y = y + ROW_H
        end
        return y
    end

    local function LayoutFlyoutTriggers(flyoutList, colX, colW, y)
        if not flyoutList then return y end
        for _, fo in ipairs(flyoutList) do
            trigIdx = trigIdx + 1
            if trigIdx > TRIGGER_POOL_SZ then break end
            flyoutPanelIdx = flyoutPanelIdx + 1
            if flyoutPanelIdx > FLYOUT_PANEL_COUNT then break end
            local tr = flyoutTriggerPool[trigIdx]
            tr:Show()
            tr:ClearAllPoints()
            tr:SetPoint("TOPLEFT", popup._body, "TOPLEFT", colX, -y)
            tr:SetPoint("TOPRIGHT", popup._body, "TOPLEFT", colX + colW, -y)
            tr._icon:SetTexture(fo.icon)
            tr._nameFS:SetText(fo.label or "?")
            tr._nameFS:SetTextColor(0.85, 0.85, 0.85, 1)
            tr._nameFS:ClearAllPoints()
            tr._nameFS:SetPoint("LEFT", tr._icon, "RIGHT", 8, 0)
            tr._nameFS:SetPoint("RIGHT", -18, 0)
            local panel = flyouts and flyouts[flyoutPanelIdx]
            if panel then
                panel._entries = fo.entries
                panel._anchor = tr
                tr._flyout = panel
            else
                tr._flyout = nil
            end
            y = y + ROW_H
        end
        return y
    end

    local function LayoutColumn(sections, colX, colW)
        local y = 0
        for _, sec in ipairs(sections) do
            secIdx = secIdx + 1
            local hdr = AcquireSecHeader(secIdx)
            hdr:Show()
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", popup._body, "TOPLEFT", colX, -y)
            hdr:SetPoint("TOPRIGHT", popup._body, "TOPLEFT", colX + colW, -y)
            hdr._label:SetText(sec.title)
            y = y + SEC_HDR_H

            if sec.tabs then
                if not popup._tabBar then
                    popup._tabBar = CreateFrame("Frame", nil, popup._body)
                    popup._tabBar:SetHeight(TAB_H)
                    local cur = CreateFrame("Button", nil, popup._tabBar)
                    cur:SetSize(70, TAB_H)
                    cur:SetPoint("LEFT", 0, 0)
                    cur._lbl = MakeLabel(cur, 10, 0.7, 0.7, 0.7, 1)
                    cur._lbl:SetPoint("CENTER")
                    cur._lbl:SetText("Current")
                    cur:SetScript("OnClick", function()
                        if not ShowOn("seasonalDungeons") then return end
                        dungeonTab = "current"; BuildAll()
                    end)
                    popup._tabBar._current = cur
                    local leg = CreateFrame("Button", nil, popup._tabBar)
                    leg:SetSize(70, TAB_H)
                    leg:SetPoint("LEFT", cur, "RIGHT", 8, 0)
                    leg._lbl = MakeLabel(leg, 10, 0.7, 0.7, 0.7, 1)
                    leg._lbl:SetPoint("CENTER")
                    leg._lbl:SetText("Legacy")
                    leg:SetScript("OnClick", function()
                        if not ShowOn("legacyDungeons") then return end
                        dungeonTab = "legacy"; BuildAll()
                    end)
                    popup._tabBar._legacy = leg
                end
                popup._tabBar:Show()
                popup._tabBar:ClearAllPoints()
                popup._tabBar:SetPoint("TOPLEFT", popup._body, "TOPLEFT", colX, -y)
                popup._tabBar:SetWidth(colW)
                local curActive = dungeonTab == "current"
                popup._tabBar._current._lbl:SetTextColor(curActive and 1 or 0.6, curActive and 1 or 0.6, curActive and 1 or 0.6, 1)
                popup._tabBar._legacy._lbl:SetTextColor(not curActive and 1 or 0.6, not curActive and 1 or 0.6, not curActive and 1 or 0.6, 1)
                y = y + TAB_H + 2
            end

            y = y + SEC_GAP
            y = LayoutRows(sec.entries, colX, colW, y)
            y = LayoutFlyoutTriggers(sec.flyouts, colX, colW, y)
            y = LayoutRows(sec.entriesAfterFlyouts, colX, colW, y)
            y = y + SEC_GAP
        end
        return y
    end

    local leftH = LayoutColumn(leftSections, 0, LEFT_COL_W)
    local rightH = LayoutColumn(rightSections, COL_RIGHT_X, RIGHT_COL_W)
    local y = math.max(leftH, rightH)

    popup:SetWidth(POPUP_W)
    popup._body:SetWidth(BODY_W)
    popup._body:SetHeight(math.max(1, y))
    local viewH = math.min(y, MAX_BODY_H)
    if popup._sf then
        popup._sf:SetHeight(viewH)
        popup._sf:SetVerticalScroll(0)
        popup._sf:EnableMouseWheel(y > MAX_BODY_H)
    end
    popup:SetHeight(TITLE_H + 8 + viewH + PAD)
    RefreshHighlights()
end

SavePosition = function()
    if not popup then return end
    local p = P()
    if not p then return end
    local pt, _, rp, x, yo = popup:GetPoint()
    if pt then p.pos = { p = pt, rp = rp, x = x, y = yo } end
end

ApplySavedPosition = function()
    if not popup then return end
    popup:ClearAllPoints()
    local pos = P() and P().pos
    if pos and pos.p then
        popup:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
end

local function BuildPopupShell()
    if popup then return end
    popup = CreateFrame("Frame", "EUIHearthTeleportPopup", UIParent)
    popup:SetWidth(POPUP_W)
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
    popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePosition() end)

    local bg = popup:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bg:SetTexCoord(0.25, 1, 0, 0.75)
    local overlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.5)
    if PP and PP.CreateBorder then PP.CreateBorder(popup, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end

    local hdrBg = popup:CreateTexture(nil, "BORDER")
    hdrBg:SetColorTexture(0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1)
    hdrBg:SetPoint("TOPRIGHT", -1, 0)
    hdrBg:SetHeight(TITLE_H)

    local title = MakeLabel(popup, 13, 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText(EllesmereUI.L("Quick Travel"))

    local xBtn = CreateFrame("Button", nil, popup)
    xBtn:SetSize(24, 24)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -5, 5)
    local closeTxt = MakeLabel(xBtn, 16, 1, 1, 1, 0.75)
    closeTxt:SetPoint("CENTER", -2, -3)
    closeTxt:SetText("x")
    xBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1, 1, 1, 1) end)
    xBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(1, 1, 1, 0.75) end)
    xBtn:SetScript("OnClick", HidePopup)

    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
    sf:SetPoint("TOPRIGHT", -PAD, -PAD)
    sf:EnableMouseWheel(false)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local child = self:GetScrollChild()
        local maxS = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 20)))
    end)
    popup._sf = sf
    popup._body = CreateFrame("Frame", nil, sf)
    popup._body:SetWidth(BODY_W)
    popup._body:SetHeight(1)
    sf:SetScrollChild(popup._body)

    if EUI and EUI.RegisterEscapeClose then EUI.RegisterEscapeClose(popup) end
    popup:SetScript("OnShow", function()
        RefreshHighlights()
        EnsureTeleportPromptHook()
        if ev then
            ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
        end
    end)
    popup:SetScript("OnHide", function()
        pendingHide = nil
        ev:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        ev:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        HideAllFlyouts()
    end)

    CreateRowPool()
    combatHider = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    combatHider:Hide()
    combatHider:SetFrameRef("popup", popup)
    for i, f in ipairs(flyouts) do
        combatHider:SetFrameRef("flyout" .. i, f)
    end
    combatHider:SetAttribute("_onstate-euiqtcombat", [[
        if newstate == "combat" then
            local p = self:GetFrameRef("popup")
            if p then p:Hide() end
            local i = 1
            while true do
                local f = self:GetFrameRef("flyout" .. i)
                if not f then break end
                f:Hide()
                i = i + 1
            end
        end
    ]])
    SetCombatHiderEnabled(true)
    ApplySavedPosition()
    popup:Hide()
end

local function BuildToggleButton()
    if toggleBtn then return end
    toggleBtn = CreateFrame("Button", "EUIHearthTeleportToggle", UIParent)
    toggleBtn:Hide()
    toggleBtn:SetScript("OnClick", TogglePopup)
end

ShowPopup = function()
    if not IsEnabled() then return end
    if not popup then
        if InCombatLockdown() then
            EUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Quick Travel cannot open in combat."))
            return
        end
        BuildPopupShell()
        BuildToggleButton()
    end
    if InCombatLockdown() then
        if popup:IsShown() then HidePopup()
        else EUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Quick Travel cannot open in combat.")) end
        return
    end
    pendingHide = nil
    BuildAll()
    local hp = P()
    popup:SetScale((hp and hp.scale) or 1.05)
    popup:Show()
end

HidePopup = function()
    if not (popup and popup:IsShown()) then pendingHide = nil; return end
    if InCombatLockdown() then
        pendingHide = true
        SyncEvents()
        return
    end
    pendingHide = nil
    popup:Hide()
end

TogglePopup = function()
    if not IsEnabled() then
        EUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Enable Quick Travel in EllesmereUI options."))
        return
    end
    if popup and popup:IsShown() then HidePopup() else ShowPopup() end
end

local function ApplyToggleKeybind()
    if not toggleBtn then return end
    ClearOverrideBindings(toggleBtn)
    local p = P()
    local k = p and p.toggleKey
    if IsEnabled() and k and k ~= "" and k ~= false then
        SetOverrideBindingClick(toggleBtn, false, k, "EUIHearthTeleportToggle")
    end
end

local _tpHooked = false
EnsureTeleportPromptHook = function()
    if _tpHooked then return end
    local p = P()
    if not (IsEnabled() and p and p.keystoneReminder == true) then return end
    local tp = _G.EUITeleportPopup
    if not tp then return end
    _tpHooked = true
    tp:HookScript("OnShow", RefreshHighlights)
    tp:HookScript("OnHide", RefreshHighlights)
end

SyncEvents = function()
    if not ev then return end
    if IsEnabled() then
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        local p = P()
        if p and p.keystoneReminder == true then
            ev:RegisterEvent("LFG_LIST_JOINED_GROUP")
        else
            ev:UnregisterEvent("LFG_LIST_JOINED_GROUP")
        end
    else
        ev:UnregisterEvent("LFG_LIST_JOINED_GROUP")
        if not (pendingHide or pendingLayout or pendingFlyoutPopulate) then
            ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        if not (popup and popup:IsShown()) then
            ev:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
            ev:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        end
    end
end

ApplyHearthTeleport = function()
    if IsEnabled() then
        if not popup and InCombatLockdown() then
            pendingLayout = true
            SyncEvents()
            return
        end
        BuildToggleButton()
        ApplyToggleKeybind()
        EnsureTeleportPromptHook()
        SetCombatHiderEnabled(true)
    else
        HidePopup()
        if toggleBtn then ClearOverrideBindings(toggleBtn) end
        SetCombatHiderEnabled(false)
    end
    SyncEvents()
    if popup and popup:IsShown() and not InCombatLockdown() then BuildAll() end
end
_G._EUI_ApplyHearthTeleport = ApplyHearthTeleport

SLASH_EUIHEARTHTELEPORT1 = "/eht"
SLASH_EUIHEARTHTELEPORT2 = "/euihearth"
SlashCmdList["EUIHEARTHTELEPORT"] = TogglePopup

ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingHide then HidePopup() end
        if pendingLayout and IsEnabled() and popup and rowPool then
            pendingLayout = nil
            BuildAll()
        end
        if pendingFlyoutPopulate and not InCombatLockdown() then
            local flyout = pendingFlyoutPopulate
            pendingFlyoutPopulate = nil
            if flyout:IsShown() then
                PopulateFlyout(flyout, flyout._entries or {}, flyout._anchor, 0)
            end
        end
        SyncEvents()
    elseif event == "LFG_LIST_JOINED_GROUP" then
        EnsureTeleportPromptHook()
        RefreshHighlights()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        if popup and popup:IsShown() and rowPool and not InCombatLockdown() then
            RefreshCooldowns()
        end
    end
end)

local FOLDER = "EllesmereUIQuickTravel"

local function CopyInto(dest, src)
    if type(dest) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        dest[k] = v
    end
end

-- Move the old QoL nested slice onto dest. Source wins so an already-enabled
-- Travel setting survives the split; dest is the live NewDB table for the
-- active profile (or a newly created folder table for inactive profiles).
local function MigrateProfile(prof, live)
    local addons = prof and prof.addons
    if type(addons) ~= "table" then return end
    local qol = addons.EllesmereUIQoL
    local src = qol and qol.hearthTeleport
    local dest = live
    if not dest then
        if type(addons[FOLDER]) ~= "table" then addons[FOLDER] = {} end
        dest = addons[FOLDER]
    end
    if type(src) == "table" then
        CopyInto(dest, src)
        qol.hearthTeleport = nil
    end
    if EUI.Lite and EUI.Lite.DeepMergeDefaults and DB_DEFAULTS.profile then
        EUI.Lite.DeepMergeDefaults(dest, DB_DEFAULTS.profile)
    end
end

local function MigrateLegacySettings()
    local live = P()
    local profiles = EllesmereUIDB and EllesmereUIDB.profiles
    local active = (db and db._profileName) or (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if type(profiles) == "table" then
        for name, prof in pairs(profiles) do
            if name == active then
                MigrateProfile(prof, live)
            else
                MigrateProfile(prof, nil)
            end
        end
    end
    -- Account-wide leftover from before the QoL store.
    local legacy = EllesmereUIDB and EllesmereUIDB.hearthTeleport
    if type(legacy) == "table" and live then
        for k, v in pairs(legacy) do
            if live[k] == nil then live[k] = v end
        end
        EllesmereUIDB.hearthTeleport = nil
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EUI and EUI.Lite and EUI.Lite.NewDB) then return end
    db = EUI.Lite.NewDB("EllesmereUIQuickTravelDB", DB_DEFAULTS)
    ns.db = db
    _G._EUI_HearthTeleport_DB = function() return db end
    MigrateLegacySettings()
    ApplyHearthTeleport()
end)
