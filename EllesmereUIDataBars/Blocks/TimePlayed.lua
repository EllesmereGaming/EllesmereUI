if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\TimePlayed.lua
-- Time Played block factory and the account-wide record of each character's total.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime          = GetTime
local UnitLevel        = UnitLevel
local pairs            = pairs
local ipairs           = ipairs
local next             = next
local type             = type
local format           = string.format
local tinsert          = table.insert
local tsort            = table.sort
local floor            = math.floor
local max              = math.max
local min              = math.min

local CONTENT_BASE     = K.CONTENT_BASE
local InstKey          = K.InstKey
local HBudget          = K.HBudget
local VSlotW           = K.VSlotW
local MaybeRelayout    = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf     = K.BlockColorOf
local IsSecret         = EllesmereUI.IsSecret
local FmtDur           = EllesmereUI.FormatDuration

-------------------------------------------------------------------------------
--  TIME PLAYED
--
--  The server only gives played time through /played, and the game prints its
--  two lines in chat for each request. A login asks once while a block is
--  enabled (EllesmereUI.RequestTimePlayed, shared with the XP bar). A /reload
--  asks nothing: the time saved at PLAYER_LOGOUT (which fires on /reload too)
--  is taken back at the next load's first PLAYER_ENTERING_WORLD, plus the
--  seconds the reload took (/played counts on through a reload).
--  Totals live in EllesmereUIDB.timePlayedChars, outside the profile:
--      [guid] = { name, realm, class, level, total }  -- total in seconds
--  plus, from PLAYER_LOGOUT until the next load's first PLAYER_ENTERING_WORLD,
--  lvlTime (the seconds at this level) and at (the GetTime() both are as of).
--  By GUID: WoW Forever first names are not the whole name, and a rename keeps it.
-------------------------------------------------------------------------------
local liveInsts = {}
local eventFrame = CreateFrame("Frame")
-- Last known seconds as of baseAt (a GetTime()); nil until the first reply.
local baseTotal, baseLevel, baseAt
local baseCharLevel
local lastMinutes   -- the heartbeat's last seen minute counters
-- A /reload takes seconds: a saved time older than this is not taken back
-- (an earlier session's, or a reload that ran long), and the load asks.
local RELOAD_WINDOW = 120
local reloadPending -- a saved time waits for the first PLAYER_ENTERING_WORLD

local function PlayedTotal() return baseTotal + (GetTime() - baseAt) end
local function PlayedLevel() return baseLevel + (GetTime() - baseAt) end

local function Store()
    local db = EllesmereUIDB
    if type(db) ~= "table" then return nil end
    if type(db.timePlayedChars) ~= "table" then db.timePlayedChars = {} end
    return db.timePlayedChars
end

-- This character's store key; nil while the GUID cannot be read.
local function CharGUID()
    local guid = UnitGUID("player")
    if not guid or IsSecret(guid) then return nil end
    return guid
end

-- Writes the live total to this character's entry.
local function SaveCharacter()
    if not baseTotal then return end
    local store = Store()
    local key = CharGUID()
    if not store or not key then return end
    local e = store[key]
    if not e then e = {}; store[key] = e end
    local _, class = UnitClass("player")
    -- The full name whatever the show-surname preference.
    local name, surname = (UnitNameUnmodified or UnitName)("player")
    e.name, e.realm, e.class, e.level, e.total = EllesmereUI.WithSurname(name, surname, true), EllesmereUI.RealmGroupName(), class, baseCharLevel, PlayedTotal()
end

local function RefreshAll()
    for inst in pairs(liveInsts) do inst:Refresh() end
end

-- Every character gone; this one is recorded again at once, the others when
-- they next log in with a block enabled.
local function ResetAll()
    local db = EllesmereUIDB
    if type(db) == "table" then db.timePlayedChars = nil end
    SaveCharacter()
end

-- Repaints and saves only when a shown minute rolls over.
local function OnHeartbeat()
    if not baseTotal then return end
    local minutes = floor(PlayedTotal() / 60) + floor(PlayedLevel() / 60)
    if minutes == lastMinutes then return end
    lastMinutes = minutes
    SaveCharacter()
    RefreshAll()
end

-- Takes a reply, as of now. Ignores anything else (no reply known yet).
local function SetPlayed(total, level)
    if type(total) ~= "number" or type(level) ~= "number" then return end
    baseTotal, baseLevel, baseAt, baseCharLevel = total, level, GetTime(), UnitLevel("player")
    SaveCharacter()
    RefreshAll()
end

local function RequestPlayed()
    -- Not before the first PLAYER_ENTERING_WORLD has looked at a saved time.
    if reloadPending then return end
    SetPlayed(EllesmereUI.RequestTimePlayed())
end

-- PLAYER_LOGOUT (on /reload too): the time as of now, for the next load.
local function SaveReload()
    if not baseTotal then return end
    SaveCharacter()
    local store, key = Store(), CharGUID()
    local e = store and key and store[key]
    if e then e.lvlTime, e.at = PlayedLevel(), GetTime() end
end

-- The load's first PLAYER_ENTERING_WORLD: a /reload takes this character's
-- saved time back; every saved time is dropped, so none outlives this load.
local function TakeReload(isReloadingUi)
    reloadPending = nil
    local db = EllesmereUIDB
    local store = type(db) == "table" and db.timePlayedChars
    if type(store) == "table" then
        local me, now = CharGUID(), GetTime()
        for key, e in pairs(store) do
            if type(e) == "table" and e.at ~= nil then
                local at, lvlTime = e.at, e.lvlTime
                e.at, e.lvlTime = nil, nil
                if isReloadingUi and key == me and type(at) == "number" and type(lvlTime) == "number"
                    and type(e.total) == "number" and e.level == UnitLevel("player")
                    and at <= now and now - at < RELOAD_WINDOW then
                    SetPlayed(e.total + (now - at), lvlTime + (now - at))
                end
            end
        end
    end
    if next(liveInsts) and not baseTotal then RequestPlayed() end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "TIME_PLAYED_MSG" then
        SetPlayed(arg1, arg2)
    elseif event == "PLAYER_ENTERING_WORLD" then
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        TakeReload(arg2)
    elseif event == "PLAYER_LOGOUT" then
        SaveReload()
    elseif baseTotal then
        -- PLAYER_LEVEL_UP: the new level starts at no time played.
        baseTotal, baseLevel, baseAt, baseCharLevel = PlayedTotal(), 0, GetTime(), arg1
        SaveCharacter()
        RefreshAll()
    end
end)

local function SyncEvents()
    if next(liveInsts) then
        eventFrame:RegisterEvent("TIME_PLAYED_MSG")
        eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
        eventFrame:RegisterEvent("PLAYER_LOGOUT")
        ns.RegisterHeartbeat("timeplayed", OnHeartbeat)
        -- A level-up while no block was enabled also makes the level time stale.
        if not baseTotal or baseCharLevel ~= UnitLevel("player") then
            RequestPlayed()
        end
    else
        -- Keeps the record current up to the moment the last block goes.
        SaveCharacter()
        -- A first PLAYER_ENTERING_WORLD still owed stays: it drops the saved time.
        eventFrame:UnregisterEvent("TIME_PLAYED_MSG")
        eventFrame:UnregisterEvent("PLAYER_LEVEL_UP")
        eventFrame:UnregisterEvent("PLAYER_LOGOUT")
        ns.UnregisterHeartbeat("timeplayed")
    end
end

-- A load after one that saved its time waits for its first
-- PLAYER_ENTERING_WORLD, which tells a /reload from a login, before it asks.
do
    local db = EllesmereUIDB
    local store = type(db) == "table" and db.timePlayedChars
    if type(store) == "table" and not IsLoggedIn() then
        for _, e in pairs(store) do
            if type(e) == "table" and e.at ~= nil then
                reloadPending = true
                eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
                break
            end
        end
    end
end

ns.BlockFactories.timeplayed = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local mouseOver = false

    local function D() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local label = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, label)

    function inst:Refresh()
        if self._dead then return end
        local barCfg = barCtx.cfg
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local text = "--"
        if baseTotal then
            if D().alwaysTotal == true or K.AtMaxLevel() then
                text = FmtDur(PlayedTotal())
            else
                text = FmtDur(PlayedLevel())
            end
        end

        ns.SetFont(label, fontSize, barCfg)
        if mouseOver then
            label:SetTextColor(ns.GetAccent())
        else
            label:SetTextColor(BlockColorOf(blockCfg))
        end
        -- A secure overlay elsewhere on the bar protects its geometry in
        -- lockdown: only the text updates now, sizing waits for regen.
        if InCombatLockdown() then
            label:SetText(text)
            ns.DeferUntilOOC("timeplayed:" .. inst.key, function() inst:Refresh() end)
            return
        end
        if barCtx.IsVertical() then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            label:SetText(text)
            ns.SetWrappedText(label, innerW, "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", button, "TOP", 0, -4)
            local totalH = max(8 + ns.SnapToPixelGrid(label:GetStringHeight()) + 4, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 100)
            ns.ResetInlineText(label, "LEFT")
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            local tw = ns.SnapToPixelGrid(label:GetStringWidth())
            local totalW = max(min(slotW, tw + 4), 10)
            content:SetSize(totalW, barH)
            button:SetSize(totalW, barH)
        end
        MaybeRelayout(inst)
    end

    local function ShowTooltip()
        local ar, ag, ab = ns.GetAccent()
        SaveCharacter()
        -- Every stored character by key, grouped by realm: realms A-Z, most played first.
        local store = Store() or {}
        local selfKey = CharGUID()
        local byRealm, realms, total, charCount = {}, {}, 0, 0
        for key, e in pairs(store) do
            if type(e) == "table" and type(e.total) == "number" then
                local realm = e.realm or "?"
                if not byRealm[realm] then
                    byRealm[realm] = {}
                    tinsert(realms, realm)
                end
                tinsert(byRealm[realm], key)
                total = total + e.total
                charCount = charCount + 1
            end
        end
        tsort(realms)
        ns.Tip_Begin(button)
        ns.Tip_AddLine(EllesmereUI.L("Time Played"), ar, ag, ab)
        for _, realm in ipairs(realms) do
            local keys = byRealm[realm]
            tsort(keys, function(a, b) return store[a].total > store[b].total end)
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(realm, 0.5, 0.78, 1)
            for _, key in ipairs(keys) do
                local e = store[key]
                local cr, cg, cb = 1, 1, 1
                local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
                if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                -- The live character's click is inert: it saves again every minute.
                local label = e.name or "?"
                if e.level then label = format("%s (%d)", label, e.level) end
                ns.Tip_AddClickable(label, FmtDur(e.total), function(mouseButton)
                    if key == selfKey then return end
                    if mouseButton ~= "LeftButton" then return end
                    if not (IsControlKeyDown() and IsAltKeyDown()) then return end
                    store[key] = nil
                    ns.Tip_Hide(button)
                end, cr, cg, cb, 1, 1, 1)
            end
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["TOTAL"], FmtDur(total), 1, 1, 1, 1, 1, 1)
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["CTRL_SHIFT_RIGHT_CLICK"], L["RESET_ALL_DATA"], 1, 1, 1, ar, ag, ab)
        if charCount > 1 then
            ns.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, ar, ag, ab)
        end
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        -- Retry a request whose reply never came.
        if not baseTotal then RequestPlayed() end
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        -- The character rows are clickable, so the tooltip has to survive the cursor leaving the block.
        ns.Tip_HideUnlessInteractive(button)
        inst:Refresh()
    end)
    button:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" and IsControlKeyDown() and IsShiftKeyDown() then
            ns.Tip_Hide(button)
            EllesmereUI:ShowConfirmPopup({
                title = "Reset Time Played Data",
                message = "Clear the time played of every character? This character is recorded again at once, the others when they next log in.",
                confirmText = "Reset",
                cancelText = "Cancel",
                onConfirm = ResetAll,
            })
        end
    end)

    function inst:Enable()
        content:Show()
        liveInsts[self] = true
        SyncEvents()
        self:Refresh()
    end

    function inst:Disable()
        liveInsts[self] = nil
        SyncEvents()
        ns.Tip_Hide(button)
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        liveInsts[self] = nil
        SyncEvents()
        content:Hide()
    end

    return inst
end
