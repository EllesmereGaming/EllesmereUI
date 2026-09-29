if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end -- no Great Vault on WoW Forever: no factory, no keystone feed (the main file drops the block from BLOCK_TYPES too)
-- Blocks\GreatVault.lua
-- Great Vault block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local MEDIA = ns.MEDIA
local K = ns.BlockKit

-- Upvalues
local _G          = _G
local CreateFrame = CreateFrame
local C_Timer     = C_Timer
local GetTime     = GetTime
local pairs       = pairs
local type        = type
local wipe        = wipe
local format      = string.format
local tsort       = table.sort
local floor       = math.floor
local max         = math.max
local min         = math.min

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf

-------------------------------------------------------------------------------
--  GREAT VAULT (weekly reward progress + owned / party keystones)
--
--  The three reward rows mirror the minimap's vault tooltip (same activity types,
--  thresholds, done/partial/empty colors); reward data is read live when the
--  tooltip opens, so this block registers NO vault events.
--
--  Party keystones are the only async part, riding LibKeystone (injected at package
--  time via .pkgmeta, absent from a source checkout -- missing, the party section
--  just never renders, same as for group members whose client broadcasts nothing).
-------------------------------------------------------------------------------
local GV_RAID  = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid) or 3
local GV_MPLUS = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities) or 1
local GV_WORLD = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World) or 6

local function GVTokenColor(state)
    if state == "done" then return 0.176, 0.796, 0.349 end
    if state == "partial" then return 0.812, 0.592, 0.212 end
    return 0.58, 0.58, 0.58
end

local function GVColorize(text, r, g, b)
    return format("%s%s|r", EllesmereUI.HexColor(r, g, b), text)
end

local function GVSortActivities(a, b)
    local ai = (a and a.index) or 0
    local bi = (b and b.index) or 0
    if ai == bi then return ((a and a.threshold) or 0) < ((b and b.threshold) or 0) end
    return ai < bi
end

-- Both buffers are consumed before the next call in the same row build.
local _gvSortBuf  = {}
local _gvTokenBuf = { "", "", "" }

-- One reward row as three tokens, each carrying its own state color inline. Tip_AddColumns
-- lays them out in pixel-aligned sub-columns so the three rows line up vertically; the shared buffer is safe because it copies.
local function GVRowTokens(activityType, isRaid)
    local acts
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        acts = C_WeeklyRewards.GetActivities(activityType)
    end
    if type(acts) ~= "table" or #acts == 0 then
        acts = nil
    else
        wipe(_gvSortBuf)
        for i = 1, #acts do _gvSortBuf[i] = acts[i] end
        tsort(_gvSortBuf, GVSortActivities)
        acts = _gvSortBuf
    end

    for i = 1, 3 do
        local info = acts and acts[i]
        local text, state = "-", "empty"
        if info then
            local progress  = max(0, tonumber(info.progress) or 0)
            local threshold = max(0, tonumber(info.threshold) or 0)
            local level     = max(0, tonumber(info.level) or 0)
            if threshold > 0 then
                if progress >= threshold then
                    state = "done"
                    -- A cleared M+ / world slot reports the reward level it earned; raids have no such level and keep the count.
                    if not isRaid and level > 0 then
                        text = "+" .. level
                    else
                        text = format("%d/%d", progress, threshold)
                    end
                else
                    text = format("%d/%d", progress, threshold)
                    if progress > 0 then state = "partial" end
                end
            end
        end
        _gvTokenBuf[i] = GVColorize(text, GVTokenColor(state))
    end
    return _gvTokenBuf
end

local function GVDungeonName(mapID)
    if not mapID or mapID == 0 then return nil end
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        return (C_ChallengeMode.GetMapUIInfo(mapID))
    end
    return nil
end

local function GVOwnedKeystone()
    if not C_MythicPlus then return nil end
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    if not mapID or not level or level <= 0 then return nil end
    local name = GVDungeonName(mapID)
    if not name then return nil end
    return name, level
end

local function GVShortName(name)
    if not name then return nil end
    return name:match("^([^-]+)") or name
end

-- Keystone feed: registered on the first Enable of a Great Vault block, so a user without one pays nothing per incoming keystone message.
local _gvKeys        = {}   -- ["Name-Realm"] = { mapID = n, level = n }
local _gvLibToken    = {}
local _gvRegistered  = false
local _gvLastRequest = 0

local function GVLib()
    return LibStub and LibStub("LibKeystone", true)
end

-- The open tooltip, so a reply landing a second after the hover can repaint it in place instead of waiting for the next hover.
local _gvOpenBtn, _gvOpenFn
local _gvRepaintQueued = false

-- Debounced like the QoL keystone popup: a request solicits a reply from every group member, and each rebuild re-lays-out the whole tooltip.
local function GVRepaintOpenTooltip()
    if not _gvOpenFn or _gvRepaintQueued then return end
    _gvRepaintQueued = true
    C_Timer.After(0.2, function()
        _gvRepaintQueued = false
        if _gvOpenFn and _gvOpenBtn and ns.Tip_IsOwned(_gvOpenBtn) then _gvOpenFn() end
    end)
end

local GVInGroup  -- forward declaration; defined below with the roster helpers

local function GVEnsureKeystoneFeed()
    if _gvRegistered then return end
    local lib = GVLib()
    if not lib then return end
    _gvRegistered = true
    -- Filtered on group membership, NOT the delivery channel: a group member who is
    -- also a guildmate can have their reply arrive tagged GUILD, and dropping it
    -- blanks their row. Membership is still required so a guild-wide reply burst cannot flood the cache with unshowable players.
    lib.Register(_gvLibToken, function(keyLevel, keyMapID, _, playerName)
        if not playerName or not GVInGroup(playerName) then return end
        local e = _gvKeys[playerName]
        if e then e.mapID, e.level = keyMapID, keyLevel
        else _gvKeys[playerName] = { mapID = keyMapID, level = keyLevel } end
        GVRepaintOpenTooltip()
    end)
end

-- Polls the group over LibKeystone. Silent: an addon-channel request, and QoL's keystone
-- popup ignores incoming data while closed, so no window surfaces. Throttled: a filling group fires GROUP_ROSTER_UPDATE repeatedly.
local GV_REQUEST_THROTTLE = 5
local GV_REQUEST_FLOOR    = 1

-- `emptyHand` = the caller has nothing to show for this group, exactly when the poll
-- matters most, so it respects only a short floor: a member who just joined may not
-- have answered the roster-change request, and swallowing the hover request too would leave the tooltip blank until a later re-hover.
local function GVRequestKeys(emptyHand)
    local lib = GVLib()
    if not lib or not IsInGroup() then return end
    local now = GetTime()
    local wait = emptyHand and GV_REQUEST_FLOOR or GV_REQUEST_THROTTLE
    if now - _gvLastRequest < wait then return end
    _gvLastRequest = now
    lib.Request("PARTY")
end

-- The player's own unit is excluded everywhere: their key has its own row, read straight from C_MythicPlus.
local function GVGroupRange()
    if IsInRaid() then return "raid", GetNumGroupMembers() end
    return "party", GetNumGroupMembers() - 1
end

-- Matched on the short name, exactly like the render path, so a sender is recognised whether the library reports "Name" or "Name-Realm".
function GVInGroup(playerName)
    if not IsInGroup() then return false end
    local short = GVShortName(playerName)
    if not short then return false end
    local prefix, count = GVGroupRange()
    for i = 1, count do
        if GVShortName(GetUnitName(prefix .. i, true)) == short then return true end
    end
    return false
end

-- The cache is roster-scoped: otherwise every player met across an evening of pugs
-- leaves a permanent entry that can never display again, since rendering only looks
-- at the current group. Pruning drops only names already gone, so it can never blank a member still here while the request throttle is closed.
local function GVPruneKeys()
    if not next(_gvKeys) then return end
    if not IsInGroup() then wipe(_gvKeys) return end

    -- GROUP_ROSTER_UPDATE can land before units resolve; pruning an unresolved roster discards live keys and costs a request round-trip on next hover.
    local prefix, count = GVGroupRange()
    local resolved = false
    for i = 1, count do
        if GetUnitName(prefix .. i, true) then resolved = true break end
    end
    if not resolved then return end

    for name in pairs(_gvKeys) do
        if not GVInGroup(name) then _gvKeys[name] = nil end
    end
end

local function GVSortPartyRows(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
end

-- Reused row tables (no per-show garbage). The sort swaps table REFERENCES inside the buffer, so the row tables survive to be refilled next hover.
local _gvPartyBuf   = {}
local _gvPartyCount = 0
local _gvShortIdx   = {}

local function GVAddPartyRow(name, dungeon, level, r, g, b)
    _gvPartyCount = _gvPartyCount + 1
    local e = _gvPartyBuf[_gvPartyCount]
    if not e then e = {}; _gvPartyBuf[_gvPartyCount] = e end
    e.name, e.dungeon, e.level = name, dungeon, level
    e.r, e.g, e.b = r, g, b
end

-- LibKeystone reports "Name-Realm" while the roster hands back a bare name for
-- same-realm members: try the exact match first, short name only as fallback. Two
-- cross-realm members CAN share a first name, so colliding short names are marked ambiguous (false) and skipped -- better nothing than the wrong key.
local function GVBuildPartyRows()
    _gvPartyCount = 0
    if not IsInGroup() then return 0 end

    wipe(_gvShortIdx)
    local any = false
    for name, info in pairs(_gvKeys) do
        if info and (info.level or 0) > 0 then
            local short = GVShortName(name)
            if short then
                if _gvShortIdx[short] == nil then _gvShortIdx[short] = info
                else _gvShortIdx[short] = false end
                any = true
            end
        end
    end
    if not any then return 0 end

    local prefix, count = GVGroupRange()
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local unitName = GetUnitName(unit, true)
            local info = _gvKeys[unitName]
            if not (info and (info.level or 0) > 0) then
                info = _gvShortIdx[GVShortName(unitName)] or nil
            end
            local dungeon = info and GVDungeonName(info.mapID)
            if dungeon then
                local _, classFile = UnitClass(unit)
                local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                GVAddPartyRow(GetUnitName(unit) or unit, dungeon, info.level,
                              (cc and cc.r) or 1, (cc and cc.g) or 1, (cc and cc.b) or 1)
            end
        end
    end

    for i = 2, _gvPartyCount do
        local j = i
        while j > 1 and GVSortPartyRows(_gvPartyBuf[j], _gvPartyBuf[j - 1]) do
            _gvPartyBuf[j], _gvPartyBuf[j - 1] = _gvPartyBuf[j - 1], _gvPartyBuf[j]
            j = j - 1
        end
    end
    return _gvPartyCount
end

local function GVToggleVault()
    if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    local wrf = _G.WeeklyRewardsFrame
    if not wrf then return end
    wrf:SetShown(not wrf:IsShown())
end

ns.BlockFactories.greatvault = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }

    local mouseOver = false

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(MEDIA .. "great_vault.png")
    local label = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, label)

    function inst:Refresh()
        local barCfg = barCtx.cfg
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        -- Core translator, not the file's English-only `L` table: vault terms share catalog entries with the minimap's vault tooltip.
        local text = EllesmereUI.L("Great Vault")
        local iconSz = fontSize + 4

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            ns.SetFont(label, fontSize, barCfg)
            label:SetText(text)
            icon:SetSize(iconSz, iconSz)
            icon:ClearAllPoints()
            icon:SetPoint("TOP", button, "TOP", 0, -4)
            ns.SetWrappedText(label, innerW, "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            local totalH = 8 + iconSz + 2 + ns.SnapToPixelGrid(label:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 120)
            local gap = ICON_GAP
            ns.SetFont(label, fontSize, barCfg)
            ns.ResetInlineText(label, "LEFT")
            label:SetText(text)
            icon:SetSize(iconSz, iconSz)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", button, "LEFT", 0, 0)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", iconSz + gap, 0)
            local tw = ns.SnapToPixelGrid(label:GetStringWidth())
            local totalW = min(slotW, iconSz + gap + tw + 4)
            content:SetSize(max(totalW, 10), barH)
            button:SetSize(max(totalW, 10), barH)
        end

        if mouseOver then
            local ar, ag, ab = ns.GetAccent()
            label:SetTextColor(ar, ag, ab, 1)
            icon:SetVertexColor(ar, ag, ab, 1)
        else
            local cbr, cbg, cbb = BlockColorOf(blockCfg)
            local ir, ig, ib = IconColorOf(blockCfg)
            label:SetTextColor(cbr, cbg, cbb, 1)
            icon:SetVertexColor(ir, ig, ib, 1)
        end
        MaybeRelayout(inst)
    end

    local function ShowVaultTooltip()
        local ar, ag, ab = ns.GetAccent()
        ns.Tip_Begin(button)
        ns.Tip_AddLine("|cFFFFFFFF[|r" .. EllesmereUI.L("Great Vault") .. "|cFFFFFFFF]|r", ar, ag, ab)
        ns.Tip_AddLine(" ")
        ns.Tip_AddColumns(EllesmereUI.L("Raids"),   GVRowTokens(GV_RAID,  true),  0.8, 0.8, 0.8)
        ns.Tip_AddColumns(EllesmereUI.L("Mythic+"), GVRowTokens(GV_MPLUS, false), 0.8, 0.8, 0.8)
        ns.Tip_AddColumns(EllesmereUI.L("World"),   GVRowTokens(GV_WORLD, false), 0.8, 0.8, 0.8)

        local myDungeon, myLevel = GVOwnedKeystone()
        if myDungeon then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(EllesmereUI.L("Your Keystone"), ar, ag, ab)
            ns.Tip_AddDouble(myDungeon, "+" .. myLevel, 0.8, 0.8, 0.8, 1, 1, 1)
        end

        local partyCount = GVBuildPartyRows()
        if partyCount > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(EllesmereUI.L("Party Keystones"), ar, ag, ab)
            for i = 1, partyCount do
                local e = _gvPartyBuf[i]
                ns.Tip_AddDouble(e.name, e.dungeon .. " |cffffffff+" .. e.level .. "|r",
                                 e.r, e.g, e.b, 0.6, 0.6, 0.6)
            end
        end

        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], EllesmereUI.L("Open Great Vault"), 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
        return partyCount
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        -- Paint from the cache first, then poll: a member can pick up a new key without
        -- the group changing, and the painted row count says whether we had anything --
        -- an empty section bypasses the throttle. Replies land ~1s later and repaint the tip in place.
        local shown = ShowVaultTooltip()
        _gvOpenBtn, _gvOpenFn = button, ShowVaultTooltip
        GVRequestKeys(shown == 0)
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        _gvOpenBtn, _gvOpenFn = nil, nil
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    button:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" then GVToggleVault() end
    end)

    -- The block's visuals never change with the roster; these events exist only to drop departed members and keep the cache warm for the next hover.
    inst.eventFrame = MakeEventFrame(inst, function()
        GVPruneKeys()
        GVRequestKeys()
    end)

    -- Teardown can happen while the tip is open (a bar rebuild never fires OnLeave),
    -- and _gvOpenFn is module-level: left set, it would pin this factory's whole scope for the rest of the session.
    local function ForgetOpenTip()
        if _gvOpenBtn == button then _gvOpenBtn, _gvOpenFn = nil, nil end
    end

    function inst:Enable()
        content:Show()
        GVEnsureKeystoneFeed()
        RegisterInstEvents(self)
        GVRequestKeys()
    end

    function inst:Disable()
        ForgetOpenTip()
        UnregisterInstEvents(self)
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
        ForgetOpenTip()
        content:Hide()
    end

    return inst
end
