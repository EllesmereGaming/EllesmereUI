-- Run from the repository root: lua .tools/tests/test_cdm_forever_import_spec_bucket.lua
-- WoW Forever: a profile apply (import or switch) restores the Tracking Bar
-- unlock links for the incoming profile. The spec key must resolve against
-- the incoming profile's store, so the restore never creates a bucket there
-- under the outgoing profile's key, which the class would read first and
-- which would hide the incoming layout.
EUI_CLIENT_BLOCKED = false

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopy(v) end
    return c
end

-- A hunter: Forever spec 1485, retail specs 253/254/255. SpecFor takes the
-- Forever key when the store holds it, else the first retail spec with data,
-- else the first retail spec (EllesmereUI_Presets.lua).
EllesmereUI = {
    IS_FOREVER = true,
    Lite = { DeepCopy = DeepCopy },
    SpecHasStringEntry = function(id, tbl) return tbl ~= nil and tbl[tostring(id)] ~= nil end,
}
local HUNTER = { 253, 254, 255 }
function EllesmereUI.SpecFor(raw, pred, arg)
    if pred(raw, arg) then return raw end
    for i = 1, #HUNTER do
        if pred(HUNTER[i], arg) then return HUNTER[i] end
    end
    return HUNTER[1]
end
GetTime = function() return 0 end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1485 end,
}

local LINK = { point = "TOP", target = "cooldowns" }
EllesmereUIDB = {
    activeProfile = "A",
    spellAssignments = { profiles = {
        A = { specProfiles = { ["1485"] = { barSpells = {}, tbbUnlockLinks = { anchors = {}, wm = {}, hm = {} } } } },
        B = { specProfiles = { ["253"] = { barSpells = { cooldowns = { assignedSpells = { 20572 } } },
            trackedBuffBars = { bars = { {} } },
            tbbUnlockLinks = { anchors = { ["1"] = LINK }, wm = {}, hm = {} } } } },
    } },
}

local ns = { _internals = { broken = false, ECME = {} }, _buffBarInternals = { broken = false, ecmeSetters = {} } }
function ns.GetTrackedBuffBars()
    local sp, key = ns.GetActiveSpecProfiles(), ns.GetActiveSpecKey()
    return (sp[key] and sp[key].trackedBuffBars) or { bars = {} }
end

assert(loadfile("EllesmereUICooldownManager/EUI_CDM_Store.lua"))("EllesmereUICooldownManager", ns)
assert(ns._internals.broken == false, "EUI_CDM_Store.lua did not load")
assert(loadfile("EllesmereUICooldownManager/EUI_CDM_Spec.lua"))("EllesmereUICooldownManager", ns)
assert(ns._internals.broken == false, "EUI_CDM_Spec.lua did not load")
assert(loadfile("EllesmereUICooldownManager/EUI_CDM_BuffBarStore.lua"))("EllesmereUICooldownManager", ns)
assert(ns._buffBarInternals.broken == false, "EUI_CDM_BuffBarStore.lua did not load")

-- Profile A is live: the hunter reads its Forever key.
assert(ns.GetActiveSpecKey() == "1485", "profile A resolves to its Forever key")
ns.SyncTBBUnlockLinks(true)

-- Apply profile B: the profile switches, the restore runs before the rebuild
-- drops the active-store cache.
EllesmereUIDB.activeProfile = "B"
EllesmereUIDB.unlockAnchors = {}
EllesmereUI._TBBRestoreUnlockLinks()

local B = EllesmereUIDB.spellAssignments.profiles.B.specProfiles
assert(B["1485"] == nil, "the restore creates no Forever-key bucket in the incoming profile")
assert(ns.GetActiveSpecKey() == "253", "the hunter reads the imported layout: " .. tostring(ns.GetActiveSpecKey()))
assert(EllesmereUIDB.unlockAnchors.TBB_1 and EllesmereUIDB.unlockAnchors.TBB_1.target == "cooldowns",
    "the incoming layout's Tracking Bar links are swapped in")
assert(EllesmereUIDB._tbbLinkOwner.profile == "B" and EllesmereUIDB._tbbLinkOwner.spec == "253",
    "the links are owned by the key the class reads")

print("test_cdm_forever_import_spec_bucket: all checks passed")
