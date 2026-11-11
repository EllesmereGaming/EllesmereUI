-- Run from the repository root: lua .tools/tests/test_specov_capture_reuse.lua [session file]
-- Loads the real EUI_SpecOverrides_Session.lua over stubs of the Spec Overrides
-- internals and drives its capture paths (the notified write and the polling
-- fallback): a slot with no entry under its name reuses the entry of the session's
-- OWN store (same module and element, no conflicting group) that owns a key the
-- slot's getters read -- one of the edit's owned fkeys, or, for an edit of only
-- new keys, an entry under the slot's label on the same page whose every key the
-- slot reads -- and takes the slot's current name and place; anything else,
-- including a setter's write to another row's key, captures as before.
local path = arg and arg[1] or "EUI_SpecOverrides_Session.lua"

local FOLDER = "EllesmereUIActionBars"
local FS, PS = "\31", "\30"
local function FK(key) return FOLDER .. FS .. key end

-------------------------------------------------------------------------------
--  Game and frame stubs
-------------------------------------------------------------------------------
local texts = {}
local function NewFrame()
    local f = { _shown = true }
    return setmetatable(f, { __index = function(t, k)
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "SetText" then return function(_, s) texts[#texts + 1] = s end end
        if k == "GetParent" then return function() return nil end end
        if k == "CreateFontString" or k == "CreateTexture" then
            return function() return NewFrame() end
        end
        return function(self) return self end
    end })
end

local timers, tickFn = {}, nil
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function(_, fn)
        tickFn = fn
        return { Cancel = function() end }
    end,
}
local function Flush()
    while #timers > 0 do
        local fn = table.remove(timers, 1)
        fn()
    end
end
GetTime = function() return 100 end
local foci = {}
GetMouseFoci = function() return foci end
WorldFrame = NewFrame()
UIParent = NewFrame()
CreateFrame = function() return NewFrame() end
IsMouseButtonDown = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return unpack(out)
end
EllesmereUIFrame = NewFrame()

-------------------------------------------------------------------------------
--  The profile, the two stores and their fkey indexes
-------------------------------------------------------------------------------
local profile = {}
local specStore, condStore = {}, {}
local specIndex, condIndex

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = DeepCopy(v) end
    return o
end
local function IndexOf(store)
    local idx = {}
    for _, e in ipairs(store) do
        for fkey in pairs(e.values and e.values.default or {}) do idx[fkey] = e end
    end
    return idx
end
local function RebuildFKeyIndex() specIndex = IndexOf(specStore) end
local function EntryOwning(fkey)
    if not specIndex then RebuildFKeyIndex() end
    return specIndex[fkey]
end

local Cond = {}
function Cond.GetStore() return condStore end
function Cond.RebuildIndex() condIndex = IndexOf(condStore) end
function Cond.EntryOwning(fkey)
    if not condIndex then Cond.RebuildIndex() end
    return condIndex[fkey]
end
function Cond.WriteValues() return nil end
function Cond.PruneRedundant() end

local groups = {}
local function GroupById(id)
    for _, g in ipairs(groups) do if g.id == id then return g end end
    return nil
end
local curGroup
-- The same rule as the main file's ConflictSpec.
local function ConflictSpec(entry, group)
    group = group or curGroup
    if not group or not entry.group or entry.group == group.id then return nil end
    local og = GroupById(entry.group)
    if not og then return nil end
    for _, sid in ipairs(group.specs or {}) do
        for _, osid in ipairs(og.specs or {}) do
            if sid == osid then return sid end
        end
    end
    return nil
end

local function SplitFKey(fkey) return fkey:match("^([^\31]+)\31(.*)$") end

-------------------------------------------------------------------------------
--  EllesmereUI, the namespace and the Spec Overrides internals
-------------------------------------------------------------------------------
local curModule, curPage, curElement = FOLDER, "Bar Display", "Action Bar 1"
EllesmereUI = {
    EXPRESSWAY = "font",
    GetActiveModule = function() return curModule end,
    GetActivePage = function() return curPage end,
    GetModuleTitle = function(_, m) return m and ("Title:" .. m) or nil end,
    RegisterOnCollapse = function() end,
    RefreshPage = function() end,
    SolidTex = function() return NewFrame() end,
    MakeBorder = function() return { SetColor = function() end } end,
    MakeRoundedBorder = function() return { SetColor = function() end, Fit = function() end } end,
    MakeFont = function() return NewFrame() end,
    SpecOverrides_HarvestCurrent = function() end,
    SpecOverrides_BmSessionRelease = function() end,
    SpecOverrides_DmSessionRelease = function() end,
    ShowConfirmPopup = function() end,
}

local NIL_SENT = "\0nil"
local I = {
    broken = false,
    editGroupSetters = {}, defaultViewSetters = {}, enterSnapSetters = {},
    inTransitionSetters = {}, activeSpecSetters = {}, updateIndicatorSetters = {},
    watchResyncSetters = {},
}
local function Fan(list) return function(v) for _, f in ipairs(I[list]) do f(v) end end end
I.SetEditGroup = function(v) curGroup = v; Fan("editGroupSetters")(v) end
I.SetDefaultView = Fan("defaultViewSetters")
I.SetEnterSnap = Fan("enterSnapSetters")
I.SetWatchResync = Fan("watchResyncSetters")
for _, n in ipairs({ "SetExitGroupEdit", "SetSweepUncaptured", "SetTeardownEditSession",
                     "SetPanelShown", "SetEnterDefaultView" }) do
    I[n] = function() end
end
I.BlacklistedFKey = function() return false end
I.ConflictSpec = ConflictSpec
I.CurrentSpecID = function() return 101 end
I.DBFor = function(folder) return folder == FOLDER and profile or nil end
I.EDIT_R, I.EDIT_G, I.EDIT_B = 1, 1, 1
I.EntryOwning = EntryOwning
I.FKeyLoaded = function(fkey) return SplitFKey(fkey) == FOLDER end
I.FOLDER_BLACKLIST = {}
I.GetGroups = function() return groups end
I.GetStore = function() return specStore end
I.HasRegisteredDefault = function() return false end
I.L = function(s) return s end
I.LayerOwnedFKey = function() return nil end
I.MatchOwnedFKey = function() return false end
I.NIL_SENT = NIL_SENT
I.NumAllowedFKey = function() return true end
I.PS = PS
-- One size key with an exact-size partner, as the main file's PxCo names them.
I.PxCo = { Partner = function(fkey)
    if fkey == FK("borderThickness") then return FK("borderThicknessPx") end
    return nil
end }
I.ReadLive = function(fkey)
    local folder, key = SplitFKey(fkey)
    return folder == FOLDER and profile[key] or nil
end
I.RebuildFKeyIndex = RebuildFKeyIndex
I.RunRefreshers = function() end
I.SegKey = function(_, s) return s end
I.SnapValue = function(snap, fkey)
    local folder, key = SplitFKey(fkey)
    local t = snap and snap[folder]
    return t and t[key]
end
I.SplitFKey = SplitFKey
I.WriteLive = function(fkey, v)
    local _, key = SplitFKey(fkey)
    profile[key] = v
    return true
end
I.HarvestDefaults = function() end
I.HarvestGroup = function() end
I.WriteDefaultValues = function() return nil end
I.WriteGroupValues = function() return nil end
I.WriteSpecValues = function() return nil end
I.Cond = Cond
I.CurrentContext = function() return curElement end
I.DiffProfiles = function(snap)
    local out, old = {}, snap[FOLDER] or {}
    for k, v in pairs(profile) do
        if old[k] ~= v then out[#out + 1] = { fkey = FK(k), folder = FOLDER, path = k } end
    end
    for k in pairs(old) do
        if profile[k] == nil then
            out[#out + 1] = { fkey = FK(k), folder = FOLDER, path = k, removed = true }
        end
    end
    table.sort(out, function(a, b) return a.fkey < b.fkey end)
    return out
end
I.IsExcludedContext = function() return false end
I.RequestGoldWalk = function() end
I.SnapshotProfiles = function() return { [FOLDER] = DeepCopy(profile) } end
I.UpdateEditLocks = function() end
-- The read trace, as the Borders file's SlotReads: a slot's getter reads the
-- profile through P, which records each key; an empty set while another trace is
-- live (traceBusy).
local traceSink, traceBusy = nil, false
local P = setmetatable({}, { __index = function(_, k)
    if traceSink then traceSink[FK(k)] = true end
    return profile[k]
end })
I.SlotReads = function(cfg)
    if traceBusy or not cfg then return {} end
    traceSink = {}
    if cfg.getValue then pcall(cfg.getValue) end
    local s = traceSink
    traceSink = nil
    return s
end
-- Strict, as the real internals table: a name the file reads that is not stubbed
-- fails here instead of reading nil.
setmetatable(I, { __index = function(_, k) error("stub internals have no entry " .. tostring(k), 2) end })

local ns = {
    _soInternals = I,
    GetTabLabel = function(_, page) return "Tab:" .. tostring(page) end,
}

local chunk = assert(loadfile(path))
chunk("EllesmereUI", ns)
assert(rawget(I, "broken") == false, "the session file did not load to its end")
for _, f in ipairs(I.updateIndicatorSetters) do f(function() end) end
local EnterGroupEdit = I.EnterGroupEdit
assert(type(EnterGroupEdit) == "function" and type(Cond.EnterEdit) == "function")

-------------------------------------------------------------------------------
--  Driving edits
-------------------------------------------------------------------------------
local counter = 0
-- A slot whose getter reads `reads` (the profile keys its settings live in).
local function Region(label, section, reads)
    return {
        _captureCfg = { text = label, getValue = function()
            for _, k in ipairs(reads) do local _ = P[k] end
        end },
        _isOptionRow = true,
        _sectionHeader = { _sectionName = section },
        GetParent = function() return nil end,
    }
end
-- One widget write through the notified path: the setter changes `keys`, then the
-- factory notifies, and the next frame attributes and captures. The slot reads
-- `reads`, by default the keys it writes.
local function Edit(label, section, keys, reads)
    for _, k in ipairs(keys) do
        counter = counter + 1
        profile[k] = counter
    end
    EllesmereUI._NotifySettingWrite(Region(label, section, reads or keys))
    Flush()
end
-- The same edit picked up by the polling fallback (the slot under the mouse).
local function TickEdit(label, section, keys, reads)
    for _, k in ipairs(keys) do
        counter = counter + 1
        profile[k] = counter
    end
    foci = { Region(label, section, reads or keys) }
    tickFn()
    foci = {}
end
local function StatusSaysNew(n0)
    for i = n0 + 1, #texts do
        if tostring(texts[i]):find("is now customized", 1, true) then return true end
    end
    return false
end
local function Count(store, label)
    local n = 0
    for _, e in ipairs(store) do if e.label == label then n = n + 1 end end
    return n
end
local function Find(store, label)
    for _, e in ipairs(store) do if e.label == label then return e end end
    return nil
end

local G1 = { id = 1, name = "G1", specs = { 101 } }
local G2 = { id = 2, name = "G2", specs = { 101, 102 } }   -- shares spec 101 with G1
groups[1], groups[2] = G1, G2
local CG = { id = 900, name = "Dark Mode" }

-------------------------------------------------------------------------------
--  1. Spec session: a label match reuses as today; a new slot creates an entry
-------------------------------------------------------------------------------
EnterGroupEdit(G1)
local n0 = #texts
Edit("Hide Keybind Text", "TEXT", { "hideKeybind" })
assert(#specStore == 1, "first capture creates one entry")
local E0 = specStore[1]
assert(E0.label == "Hide Keybind Text" and E0.section == "TEXT" and E0.group == 1)
assert(E0.element == "Action Bar 1" and E0.page == "Bar Display")
assert(E0.values.default[FK("hideKeybind")] ~= nil)
assert(StatusSaysNew(n0), "a new entry says so")

n0 = #texts
Edit("Hide Keybind Text", "TEXT", { "keybindFontSize" })
assert(#specStore == 1, "label match reuses the entry")
assert(EntryOwning(FK("keybindFontSize")) == E0)
assert(not StatusSaysNew(n0), "a label match is not new")

-------------------------------------------------------------------------------
--  2. Renamed slot: it writes an fkey the old entry owns plus a new one
-------------------------------------------------------------------------------
n0 = #texts
Edit("Keybind Text", "TEXT", { "hideKeybind", "keybindExtra" })
assert(#specStore == 1, "a renamed slot reuses the entry owning its fkey")
assert(E0.label == "Keybind Text" and E0.slotLabel == "Keybind Text", "label follows the slot")
assert(E0.section == "TEXT" and E0.page == "Bar Display" and E0.element == "Action Bar 1")
assert(E0.crumb == "Title:" .. FOLDER .. "  >  Action Bar 1  >  Tab:Bar Display  >  TEXT")
assert(EntryOwning(FK("keybindExtra")) == E0, "the spec index is rebuilt")
assert(E0.values.default[FK("keybindExtra")] ~= nil, "the new fkey's default is seeded")
assert(E0.group == 1)
assert(not StatusSaysNew(n0), "a reused entry is not new")

-- Moved slot: same label, new section.
Edit("Cooldown Numbers", "ICONS", { "cdNumbers" })
local E1 = Find(specStore, "Cooldown Numbers")
assert(E1 and E1.section == "ICONS" and #specStore == 2)
n0 = #texts
Edit("Cooldown Numbers", "TEXT", { "cdNumbers", "cdExtra" })
assert(#specStore == 2 and Count(specStore, "Cooldown Numbers") == 1, "a moved slot keeps one entry")
assert(E1.section == "TEXT", "section follows the slot")
assert(E1.crumb:find("TEXT", 1, true))
assert(EntryOwning(FK("cdExtra")) == E1)
assert(not StatusSaysNew(n0))

-- The polling fallback hands the owned fkeys over too.
TickEdit("Keybind Words", "TEXT", { "hideKeybind", "keybindTick" })
assert(#specStore == 2 and E0.label == "Keybind Words", "the fallback path reuses too")
assert(EntryOwning(FK("keybindTick")) == E0)

-------------------------------------------------------------------------------
--  3. A slot writing only unowned fkeys still creates a new entry
-------------------------------------------------------------------------------
n0 = #texts
Edit("Charge Numbers", "TEXT", { "hideChargeCount" })
assert(#specStore == 3 and Find(specStore, "Charge Numbers"), "unowned only = a new entry")
assert(StatusSaysNew(n0))

-------------------------------------------------------------------------------
--  4. Another module or another element never reuses
-------------------------------------------------------------------------------
curModule = "_EUIGlobal"
Edit("Global Row", "TEXTURES", { "hideKeybind", "globalExtra" })
curModule = FOLDER
assert(#specStore == 4 and Find(specStore, "Global Row"), "another module: a new entry")
assert(E0.label == "Keybind Words", "the other module's edit leaves the entry alone")

curElement = "Action Bar 2"
Edit("Keybind Text", "TEXT", { "hideKeybind", "bar2Key" })
curElement = "Action Bar 1"
assert(#specStore == 5, "another element: a new entry")
assert(E0.element == "Action Bar 1" and E0.label == "Keybind Words")

-------------------------------------------------------------------------------
--  5. Conditional session: the conditional store is the one reused
-------------------------------------------------------------------------------
Cond.EnterEdit(CG)
n0 = #texts
Edit("Hide Macro Text", "TEXT", { "hideMacro" })
assert(#condStore == 1 and #specStore == 5)
local C0 = condStore[1]
assert(C0.label == "Hide Macro Text" and C0.group == 900)
assert(C0.values[900] and C0.values[900][FK("hideMacro")] ~= nil, "the group's map is seeded")
assert(StatusSaysNew(n0))

n0 = #texts
Edit("Macro Text", "TEXT", { "hideMacro", "macroExtra" })
assert(#condStore == 1 and #specStore == 5, "a renamed slot reuses the conditional entry")
assert(C0.label == "Macro Text" and C0.slotLabel == "Macro Text")
assert(Cond.EntryOwning(FK("macroExtra")) == C0, "the conditional index is rebuilt")
assert(EntryOwning(FK("macroExtra")) == nil, "the spec store is untouched")
assert(C0.values[900][FK("macroExtra")] ~= nil)
assert(not StatusSaysNew(n0))

-- A spec-owned fkey never makes a conditional session reuse a spec entry.
Edit("Keybind Cond", "TEXT", { "hideKeybind" })
assert(#condStore == 2 and Find(condStore, "Keybind Cond"), "a spec-owned fkey: a new conditional entry")
assert(E0.label == "Keybind Words" and #specStore == 5)

-------------------------------------------------------------------------------
--  6. Spec session: a conditional-owned fkey never makes it reuse that entry
-------------------------------------------------------------------------------
EnterGroupEdit(G1)
assert(Cond._edit == nil)
Edit("Macro Words", "TEXT", { "macroExtra" })
assert(#specStore == 6 and Find(specStore, "Macro Words"), "a conditional-owned fkey: a new spec entry")
assert(C0.label == "Macro Text" and #condStore == 2)

-------------------------------------------------------------------------------
--  7. Spec session: an entry of a conflicting group is never reused
-------------------------------------------------------------------------------
EnterGroupEdit(G2)
Edit("Shared Row", "TEXT", { "sharedKey" })
local S2 = Find(specStore, "Shared Row")
assert(S2 and S2.group == 2 and #specStore == 7)
EnterGroupEdit(G1)
Edit("Shared Row Renamed", "TEXT", { "sharedKey", "sharedExtra" })
assert(#specStore == 8 and Find(specStore, "Shared Row Renamed"), "a conflicting owner: a new entry")
assert(S2.label == "Shared Row" and EntryOwning(FK("sharedExtra")) ~= S2)

-- The same group's own entry is reused.
Edit("Charge Words", "TEXT", { "hideChargeCount", "chargeExtra" })
assert(#specStore == 8 and Find(specStore, "Charge Words") and not Find(specStore, "Charge Numbers"))

-------------------------------------------------------------------------------
--  8. A setter's write to another row's key never reuses that row's entry
-------------------------------------------------------------------------------
Edit("Keybind Text Size", "TEXT", { "kbSize" })
local K = Find(specStore, "Keybind Text Size")
assert(K and #specStore == 9)
n0 = #texts
-- Custom Button Shape writes the keybind size too, but reads only its shape.
Edit("Custom Button Shape", "APPEARANCE", { "buttonShape", "kbSize" }, { "buttonShape" })
local CBS = Find(specStore, "Custom Button Shape")
assert(#specStore == 10 and CBS and CBS ~= K, "a side-effect write: the slot gets its own entry")
assert(K.label == "Keybind Text Size" and K.slotLabel == "Keybind Text Size" and K.section == "TEXT",
    "the other row's entry keeps its name and place")
assert(EntryOwning(FK("kbSize")) == K and EntryOwning(FK("buttonShape")) == CBS)
assert(StatusSaysNew(n0))
-- The polling fallback the same way.
TickEdit("Shape Tick", "APPEARANCE", { "shapeTick", "kbSize" }, { "shapeTick" })
assert(#specStore == 11 and Find(specStore, "Shape Tick") and K.label == "Keybind Text Size")

-------------------------------------------------------------------------------
--  9. An edit of only new keys: a row moved under its label keeps its entry
-------------------------------------------------------------------------------
Edit("Border Size", "ICONS", { "borderSize" })
local B = Find(specStore, "Border Size")
assert(B and #specStore == 12)
n0 = #texts
Edit("Border Size", "APPEARANCE", { "borderOffsetX" }, { "borderSize", "borderOffsetX" })
assert(#specStore == 12 and Count(specStore, "Border Size") == 1, "a moved row keeps one entry")
assert(B.section == "APPEARANCE" and B.crumb:find("APPEARANCE", 1, true))
assert(EntryOwning(FK("borderOffsetX")) == B)
assert(not StatusSaysNew(n0))

-- A size key's exact-size partner counts with it.
Edit("Thickness", "ICONS", { "borderThickness" })
local T = Find(specStore, "Thickness")
assert(T and T.values.default[FK("borderThicknessPx")] ~= nil, "the partner joins")
Edit("Thickness", "APPEARANCE", { "thicknessOffset" }, { "borderThickness", "thicknessOffset" })
assert(Count(specStore, "Thickness") == 1 and T.section == "APPEARANCE")
-- Only a size key's own partner: a "...Px" key the slot does not read is not one.
Edit("Gap", "ICONS", { "gap", "gapPx" })
local G = Find(specStore, "Gap")
Edit("Gap", "APPEARANCE", { "gapNew" }, { "gap", "gapNew" })
assert(Count(specStore, "Gap") == 2 and G.section == "ICONS")
local nT = #specStore

-- An entry owning a key the slot does not read stays where it is.
Edit("Spacing", "BAR BACKGROUND", { "bgSpacing", "bgOther" })
local S = Find(specStore, "Spacing")
Edit("Spacing", "APPEARANCE", { "bgSpacingNew" }, { "bgSpacing", "bgSpacingNew" })
assert(#specStore == nT + 2 and Count(specStore, "Spacing") == 2 and S.section == "BAR BACKGROUND")

-- Another label is never reused from reads alone.
Edit("Old Row", "SEC", { "oldKey" })
local O = Find(specStore, "Old Row")
Edit("New Row", "SEC", { "newKey" }, { "oldKey", "newKey" })
assert(Find(specStore, "New Row") and O.label == "Old Row" and EntryOwning(FK("newKey")) ~= O)

-- Nor an entry on another page.
curPage = "Party"
Edit("Border Size", "APPEARANCE", { "partyBorder" }, { "borderSize", "borderOffsetX", "partyBorder" })
curPage = "Bar Display"
assert(Count(specStore, "Border Size") == 2 and B.page == "Bar Display")
assert(EntryOwning(FK("partyBorder")) ~= B)

-- Nothing is reused while the slot cannot be traced.
traceBusy = true
local nBusy = #specStore
Edit("Keybind Busy", "TEXT", { "hideKeybind", "busyKey" })
traceBusy = false
assert(#specStore == nBusy + 1 and Find(specStore, "Keybind Busy") and E0.label == "Keybind Words")

-- A conditional session reuses its own store's moved row the same way.
Cond.EnterEdit(CG)
Edit("Cond Size", "ICONS", { "condSize" })
local CS = Find(condStore, "Cond Size")
assert(CS)
Edit("Cond Size", "APPEARANCE", { "condOffset" }, { "condSize", "condOffset" })
assert(Count(condStore, "Cond Size") == 1 and CS.section == "APPEARANCE")
assert(Cond.EntryOwning(FK("condOffset")) == CS and CS.values[900][FK("condOffset")] ~= nil)

-------------------------------------------------------------------------------
--  10. An edit of only owned keys captures nothing, but a renamed or moved slot
--      takes over the entry it has (values untouched)
-------------------------------------------------------------------------------
EnterGroupEdit(G1)
Edit("CD Swipe Opacity", "ICON EFFECTS", { "swipeAlpha" })
local W = Find(specStore, "CD Swipe Opacity")
local nW = #specStore
local wDefault = W.values.default[FK("swipeAlpha")]
n0 = #texts
Edit("Cooldown Swipe Opacity", "EFFECTS", { "swipeAlpha" })
assert(#specStore == nW and W.label == "Cooldown Swipe Opacity" and W.slotLabel == "Cooldown Swipe Opacity",
    "an owned-only edit by a renamed slot relabels its entry")
assert(W.section == "EFFECTS" and W.crumb:find("EFFECTS", 1, true))
assert(EntryOwning(FK("swipeAlpha")) == W and W.values.default[FK("swipeAlpha")] == wDefault,
    "the relabel leaves the values alone")
assert(not StatusSaysNew(n0))
-- The polling fallback the same way.
TickEdit("Swipe Polled", "EFFECTS", { "swipeAlpha" })
assert(#specStore == nW and W.label == "Swipe Polled", "the fallback path relabels too")
-- A setter's write to the key from a slot that reads another one never relabels.
Edit("Shape Side", "APPEARANCE", { "swipeAlpha" }, { "shapeOnly" })
assert(#specStore == nW and W.label == "Swipe Polled", "a side-effect write never relabels")
-- An owned-only edit under the slot's own name and place changes nothing.
Edit("Swipe Polled", "EFFECTS", { "swipeAlpha" })
assert(#specStore == nW and W.label == "Swipe Polled" and W.section == "EFFECTS")
-- A row moved to another page of the same module and bar takes its entry along.
curPage = "Effects Page"
Edit("Swipe Moved", "EFFECTS", { "swipeAlpha" })
curPage = "Bar Display"
assert(#specStore == nW and W.label == "Swipe Moved" and W.page == "Effects Page")
-- Nothing changes while the slot cannot be traced.
traceBusy = true
Edit("Swipe Busy", "EFFECTS", { "swipeAlpha" })
traceBusy = false
assert(#specStore == nW and W.label == "Swipe Moved")
-- A conditional session relabels its own store's entry, never a spec entry.
Cond.EnterEdit(CG)
Edit("Cond Old", "ICONS", { "condKey" })
local CO = Find(condStore, "Cond Old")
local nC = #condStore
Edit("Cond New", "APPEARANCE", { "condKey" })
assert(#condStore == nC and CO.label == "Cond New" and CO.section == "APPEARANCE",
    "a conditional session relabels its own entry")
assert(W.label == "Swipe Moved", "a conditional session never relabels a spec entry")

print("test_specov_capture_reuse: ok")
