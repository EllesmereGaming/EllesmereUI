if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Preview.lua
--
--  The options preview's shared data: the sample rosters and icon tables,
--  and ns._previewInternals for the EUI_RaidFrames_Preview*.lua files behind
--  it, which hold the preview itself (fake members, the tickers, the
--  real-frame overlay, the size preview). Loads behind the EUI_RaidFrames_*.lua
--  chain and reads it through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local I = ns._internals
-- EllesmereUIRaidFrames.lua or one of the EUI_RaidFrames_*.lua files failed to load.
if not I or I.broken then return end

-------------------------------------------------------------------------------
--  Options preview (fake raid members when options panel is open)
--  Shows 20 buttons with randomized class colors and names so the user
--  can see their settings applied without needing a real group.
-------------------------------------------------------------------------------
ns._PV_CLASS_TOKENS = EllesmereUI.CLASS_TOKEN_ORDER
ns._PV_TANK_CLASSES   = { "WARRIOR", "PALADIN", "DEATHKNIGHT", "MONK", "DRUID", "DEMONHUNTER" }
ns._PV_HEALER_CLASSES = { "PRIEST", "PALADIN", "SHAMAN", "MONK", "DRUID", "EVOKER" }
ns._PV_DPS_CLASSES    = ns._PV_CLASS_TOKENS
ns._PV_EXT_ICONS = {
    572025, 135936, 237542, 627485, 135964, 135966, 4622478,
}
ns._PV_DEF_ICONS = {
    DEATHKNIGHT = { 237525, 136120 }, DEMONHUNTER = { 1305150, 463284 },
    DRUID = { 136097, 236169 }, EVOKER = { 1394891 },
    HUNTER = { 132199, 136094 }, MAGE = { 135841, 609811 },
    MONK = { 615341, 620827 }, PALADIN = { 524353, 524354 },
    PRIEST = { 237550, 237563 }, ROGUE = { 136177, 132294 },
    SHAMAN = { 538565 }, WARLOCK = { 136146, 136150 }, WARRIOR = { 132336, 132361 },
}
ns._PV_NAMES = {
    "Thaldrin", "Kaelara", "Morgath", "Sylvaris", "Drakmoor",
    "Elyndra", "Bronthar", "Velisara", "Grimjaw", "Luneth",
    "Ashvane", "Tormund", "Ravynne", "Zulkhar", "Brightwing",
    "Fenwick", "Dawnforge", "Nighthollow", "Stormhelm", "Embertide",
}
-- EUI LEGENDS event roster (PERMANENT): the event winners + team members who
-- earned a spot on the raid preview, with class-balancing filler names.
-- Preview slot 1 is always the player; entries 1-19 fill slots 2-20. Name,
-- class and role travel together through the role sort (ns._pvNames).
ns._PV_ROSTER = {
    { name = "Xeno",          class = "MONK",        role = "TANK" },
    { name = "Grimjaw",       class = "WARRIOR",     role = "TANK" },
    { name = "Stickymittens", class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Toxik",         class = "MONK",        role = "HEALER" },
    { name = "Delasteve",     class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Burne",         class = "DRUID",       role = "HEALER" },
    { name = "Lily",          class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Kulia",         class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Thiaspriest",   class = "PRIEST",      role = "DAMAGER" },
    { name = "Pelleas",       class = "SHAMAN",      role = "DAMAGER" },
    { name = "Khardi",        class = "HUNTER",      role = "DAMAGER" },
    { name = "Morgath",       class = "DEATHKNIGHT", role = "DAMAGER" },
    { name = "Drakmoor",      class = "DEMONHUNTER", role = "DAMAGER" },
    { name = "Embertide",     class = "EVOKER",      role = "DAMAGER" },
    { name = "Elyndra",       class = "MAGE",        role = "DAMAGER" },
    { name = "Fenwick",       class = "ROGUE",       role = "DAMAGER" },
    { name = "Zulkhar",       class = "WARLOCK",     role = "DAMAGER" },
    { name = "Luneth",        class = "DRUID",       role = "DAMAGER" },
    { name = "Stormhelm",     class = "SHAMAN",      role = "DAMAGER" },
}
ns._PV_DISPEL_DB_ICONS = {
    Magic = 135735, Curse = 132291, Disease = 237535, Poison = 132106, [""] = 4547635,
}
ns._PV_DEBUFF_ICONS = { 135813, 136139, 132090, 136197, 135849, 136188 }
ns._pvActiveAuras = {}

-- What the EUI_RaidFrames_Preview*.lua files share: each file adds the names
-- later files re-import. previewActiveSetters and the list beside it: every file
-- that reads one of these keeps its own copy and adds a setter here; each
-- place that assigns it writes through the Set<Name> function built below,
-- which runs them all.
-- broken: true while an EUI_RaidFrames_Preview*.lua file loads; a file that
-- fails leaves it set, and the files behind it return at their first lines.
EllesmereUI.NewInternals(ns, "_previewInternals", {
    -- Created here: files that load ahead of CreatePreviewFrame and
    -- BuildPreviewRoles read them too.
    previewFrames = {},
    previewClassTokens = {}, -- [1..20] class token per slot
    previewActiveSetters = {}, previewContainerSetters = {},
}, {
    SetPreviewActive = "previewActiveSetters", SetPreviewContainer = "previewContainerSetters",
})
-- The main chain's visibility passes read the raid preview's state as this plain
-- field (as the party preview's ns._partyPvActive), never a preview function: a
-- preview file that fails to load must not leave them a nil call.
do
    local list = ns._previewInternals.previewActiveSetters
    list[#list + 1] = function(v) ns._raidPvActive = v end
end
