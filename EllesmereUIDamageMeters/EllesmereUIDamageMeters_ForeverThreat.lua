if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIDamageMeters_ForeverThreat.lua  (WoW Forever only)
--  The "Threat" meter type: Forever Essentials' threat list in a Damage Meters
--  window, painted by the window like any other type and in its style (the
--  rows carry their own value text, rank and highlight colours). Offered only
--  while Forever Essentials is loaded, which hands the list over as
--  EllesmereUI._ThreatFeed; a window saved on the type reads as Damage Done
--  wherever it is not offered. The main file reaches this file only through
--  nil-guarded ns hooks.
-------------------------------------------------------------------------------
local _, ns = ...
local THREAT = "threat"

-- Icons: the target crosshair glyph (on its plate under the WoW Forever look)
-- and the vanilla taunt icon under Classic WoW UI.
do
    local enemy = Enum.DamageMeterType.EnemyDamageTaken
    ns._DM_TYPE_ICONS[THREAT] = ns._DM_TYPE_ICONS[enemy]
    local fv = ns.DM_HDR_ART.forever
    fv.types[THREAT] = fv.types[enemy]
    ns.DM_HDR_ART.classic.types[THREAT] = { file = "Interface\\Icons\\Spell_Nature_Reincarnation", crop = 0.08, scale = 0.85 }
end

-- Repaints every shown Threat window after the list rebuilt (a hidden one
-- repaints on its show).
function ns.DMThreatNotify()
    for _, w in ipairs(ns._windows) do
        if w.curDMType == THREAT and w.frame and w.frame:IsVisible() then w.Refresh() end
    end
end

-- The session a visible Threat window paints. The first one starts the feed.
function ns.DMThreatSession()
    local feed = EllesmereUI._ThreatFeed
    if not feed then return nil end
    if not feed.IsActive() then feed.Start(ns.DMThreatNotify) end
    -- The value text follows the meter's Force English Units, as every type's does.
    local db = ns.EDM.DB()
    return feed.Session(db and db.forceEnglishUnits == true)
end

-- Stops the feed once no Threat window is on screen; `except` is a window in
-- the middle of hiding.
function ns.DMThreatSync(except)
    local feed = EllesmereUI._ThreatFeed
    if not (feed and feed.IsActive()) then return end
    for _, w in ipairs(ns._windows) do
        if w ~= except and w.curDMType == THREAT and w.frame and w.frame:IsVisible() then return end
    end
    feed.Stop()
end

-- The list's own settings (tracked unit, displayed value, pets) head a
-- Threat window's settings menu, and the clock and segment rows (noThreat)
-- leave it.
function ns.DMThreatMenu(items)
    local feed = EllesmereUI._ThreatFeed
    if not feed then return end
    for i = #items, 1, -1 do
        local e = items[i]
        if type(e) == "table" and e.noThreat then table.remove(items, i) end
    end
    local head = feed.MenuItems({})
    head[#head + 1] = "---"
    for i = #head, 1, -1 do table.insert(items, 1, head[i]) end
end

-- Forever Essentials loads after this addon: the type is offered from login
-- on, before the windows are built, when it is there.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if EllesmereUI._ThreatFeed then ns._DM_TYPE_NAMES[THREAT] = "Threat" end
end)
