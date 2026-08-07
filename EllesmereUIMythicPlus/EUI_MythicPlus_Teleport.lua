-------------------------------------------------------------------------------
--  EUI_MythicPlus_Teleport.lua  --  dungeon teleport buttons + announce
--
--  Turns every Group Finder dungeon icon into a one-click teleport, and can
--  announce the cast to the group from an editable template.
--
--  Taint discipline: the button is OURS (InsecureActionButtonTemplate, so no
--  protected state is involved) and is tracked in the weak-keyed side table, not
--  as a field on Blizzard's icon. It propagates mouse motion so Blizzard's own
--  icon tooltip still builds normally, and our extra lines are appended from a
--  HookScript on the icon -- we never call a Blizzard script ourselves.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

local enabled = false
local challengesHooked = false

-------------------------------------------------------------------------------
--  Tooltip
--
--  Blizzard's icon OnEnter has already built the tooltip by the time our hook
--  runs, so we only append. The cooldown countdown then rewrites THAT ONE LINE
--  in place through its FontString instead of rebuilding the tooltip, and the
--  driver disarms itself the moment the tooltip stops belonging to the icon.
-------------------------------------------------------------------------------
local TICK_KEY = "emp_teleport_tooltip"

local function CooldownText(spellID)
    if not IsSpellKnown(spellID) then
        return "|cffff4040" .. EllesmereUI.L("Teleport not learned") .. "|r"
    end
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd or not cd.startTime or not cd.duration then
        return "|cffff4040" .. EllesmereUI.L("Cooldown unavailable") .. "|r"
    end
    if cd.duration == 0 then
        return "|cff40ff40" .. EllesmereUI.L("Teleport ready") .. "|r"
    end
    return "|cffff4040" .. SecondsToTime(math.ceil(cd.startTime + cd.duration - GetTime())) .. "|r"
end

local function StopTooltipTicker()
    if ns.Drv then ns.Drv.Remove(TICK_KEY) end
end

local function StartTooltipTicker(icon, spellID, lineIndex)
    if not ns.Drv then return end
    local lineFS = _G["GameTooltipTextLeft" .. lineIndex]
    if not lineFS then return end
    local accum = 0
    ns.Drv.Add(TICK_KEY, function(dt)
        if not GameTooltip:IsShown() or not icon:IsMouseOver() then
            StopTooltipTicker()
            return
        end
        accum = accum + dt
        if accum < 0.5 then return end
        accum = 0
        lineFS:SetText(CooldownText(spellID))
    end)
end

local function OnIconEnter(icon)
    if not enabled then return end
    local spellID = GetFFD(icon).spellID
    if not spellID then return end
    -- Blizzard's own OnEnter has already built and shown the tooltip by now; if
    -- it did not, there is nothing to append to.
    if not GameTooltip:IsShown() then return end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(C_Spell.GetSpellName(spellID) or EllesmereUI.L("Dungeon Teleport"), 1, 1, 1)
    GameTooltip:AddLine(CooldownText(spellID))
    local lineIndex = GameTooltip:NumLines()
    GameTooltip:Show()
    StartTooltipTicker(icon, spellID, lineIndex)
end

local function OnIconLeave()
    StopTooltipTicker()
end

-------------------------------------------------------------------------------
--  Buttons
-------------------------------------------------------------------------------
local function BestSpellID(spellIDs)
    for _, spellID in ipairs(spellIDs) do
        if IsSpellKnown(spellID) then return spellID end
    end
    return spellIDs[1]
end

local function ReleaseIcon(icon)
    local d = FFD[icon]
    if d and d.button then
        d.button:Hide()
        d.button:SetAttribute("spell", nil)
    end
    if d then d.spellID = nil end
end

local SetUpIcon  -- forward declaration (the per-icon SetUp hook re-enters it)

function SetUpIcon(icon)
    if not enabled then return ReleaseIcon(icon) end

    local d = GetFFD(icon)
    -- Hook the icon itself, not just ChallengesFrame:Update. Blizzard re-runs an
    -- individual icon's SetUp when its map data lands or the list re-sorts,
    -- without a whole-frame Update -- and that changes icon.mapID. A button left
    -- carrying the previous mapID's spell would cast the WRONG dungeon's
    -- teleport, so the binding has to be re-resolved from the same signal the
    -- score overlay listens to.
    if not d.hooked then
        d.hooked = true
        if type(icon.SetUp) == "function" then
            hooksecurefunc(icon, "SetUp", function(self) SetUpIcon(self) end)
        end
        icon:HookScript("OnEnter", OnIconEnter)
        icon:HookScript("OnLeave", OnIconLeave)
    end

    local spellIDs = ns.TeleportSpells(icon.mapID)
    if not spellIDs then return ReleaseIcon(icon) end
    local spellID = BestSpellID(spellIDs)
    if not spellID then return ReleaseIcon(icon) end
    d.spellID = spellID

    local button = d.button
    if not button then
        button = CreateFrame("Button", nil, icon, "InsecureActionButtonTemplate")
        button:SetAllPoints(icon)
        button:SetAttribute("type", "spell")
        -- Blizzard's icon keeps receiving enter/leave, so its own tooltip still
        -- builds and our OnEnter hook above can simply append to it.
        if button.SetPropagateMouseMotion then button:SetPropagateMouseMotion(true) end
        d.button = button
    end
    -- Registering both AnyDown and AnyUp fires the action twice per click; the
    -- second activation restarts the cast with a fresh castGUID, which defeats
    -- the announce dedup and broadcasts twice. Match the player's cvar instead,
    -- re-read on every refresh so a cvar change is picked up.
    button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
    button:SetAttribute("spell", spellID)
    button:Show()
end

local function RefreshAllIcons()
    local cf = _G.ChallengesFrame
    if not cf or not cf.DungeonIcons then return end
    for _, icon in ipairs(cf.DungeonIcons) do
        SetUpIcon(icon)
    end
end

local function TryHookChallengesFrame()
    local cf = _G.ChallengesFrame
    if not cf then return end
    if not challengesHooked then
        challengesHooked = true
        if type(cf.Update) == "function" then
            hooksecurefunc(cf, "Update", RefreshAllIcons)
        end
        cf:HookScript("OnShow", RefreshAllIcons)
    end
    RefreshAllIcons()
end

-------------------------------------------------------------------------------
--  Announce
-------------------------------------------------------------------------------
local lastCastGUID, lastSpellID, lastAnnounceAt

local function SpellToMapID(spellID)
    local mapIDs = ns.SeasonMapIDs()
    if not mapIDs then return nil end
    for _, mapID in ipairs(mapIDs) do
        for _, id in ipairs(ns.TeleportSpells(mapID) or {}) do
            if id == spellID then return mapID end
        end
    end
    return nil
end

-- gsub treats "%" in a REPLACEMENT string as a capture reference and errors on
-- anything it cannot resolve, so substituted text has to be escaped first. A
-- spell link or localized dungeon name carrying a literal percent would
-- otherwise blow up the announce inside the cast handler.
local function EscapeReplacement(s)
    return (tostring(s):gsub("%%", "%%%%"))
end

--- The template actually in force: the user's edit, or the active locale's
--- default when they never customised it. Single source of truth -- the options
--- page reads this rather than repeating the default string.
function ns.TeleportTemplate()
    local stored = ns.P().teleport.template
    if stored and stored ~= "" then return stored end
    return EllesmereUI.L("Casting: {spell}, teleporting to: {dungeon}")
end

local function BuildMessage(spellID, mapID)
    local link = C_Spell.GetSpellLink(spellID)
        or ("|cff71d5ff[" .. (C_Spell.GetSpellName(spellID) or "?") .. "]|r")
    local msg = ns.TeleportTemplate()
        :gsub("{spell}", EscapeReplacement(link))
        :gsub("{dungeon}", EscapeReplacement(ns.DungeonName(mapID, false)))
    -- Chat rejects control characters and truncates past 255 bytes.
    return (msg:gsub("\n", " "):gsub("[%z\1-\31\127]", ""):sub(1, 255))
end

local function OnSpellCast(_, _, unit, castGUID, spellID)
    if unit ~= "player" then return end
    local cfg = ns.P().teleport
    if not cfg.announce then return end
    if not IsInGroup() then return end
    -- One cast can raise UNIT_SPELLCAST_START more than once (loading-screen
    -- edge cases, self-cast frame refreshes), so dedup on castGUID. A restarted
    -- cast carries a NEW guid, so also suppress the same spell inside a short
    -- window -- teleport casts run ~10s, so 5s never swallows a real second cast.
    if castGUID and castGUID == lastCastGUID then return end
    local now = GetTime()
    if lastSpellID == spellID and now - (lastAnnounceAt or 0) < 5 then return end

    local mapID = SpellToMapID(spellID)
    if not mapID then return end

    lastCastGUID, lastSpellID, lastAnnounceAt = castGUID, spellID, now
    local msg = BuildMessage(spellID, mapID)
    if msg == "" then return end
    -- A home-category RAID is not a party: sending to "PARTY" from a raid group
    -- is silently dropped, so the raid channel has to be picked explicitly.
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    else
        channel = "PARTY"
    end
    SendChatMessage(msg, channel)
end

-------------------------------------------------------------------------------
--  Feature
-------------------------------------------------------------------------------
local EVENTS = { "ADDON_LOADED" }

local function OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
        TryHookChallengesFrame()
    end
end

-- Unit-filtered registration needs its own frame (the shared fan-out in the core
-- file uses RegisterEvent), and it is created in this main chunk so the cast
-- handler bills this addon rather than the parent. Idle it holds no
-- registrations at all -- an unfiltered UNIT_SPELLCAST_START would otherwise
-- fire for every party, raid and nameplate unit in range.
local castFrame = CreateFrame("Frame")
castFrame:SetScript("OnEvent", OnSpellCast)

local function SyncCastEvent(on)
    if on then
        castFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    else
        castFrame:UnregisterAllEvents()
    end
end

ns.RegisterFeature({
    id = "teleport",

    IsEnabled = function(p)
        return p.teleport.enabled ~= false
    end,

    Start = function()
        TryHookChallengesFrame()
    end,

    Apply = function(on)
        enabled = on
        ns.SetEvents(OnEvent, EVENTS, on)
        SyncCastEvent(on and ns.P().teleport.announce == true)
        if on then TryHookChallengesFrame() end
        RefreshAllIcons()
    end,
})
