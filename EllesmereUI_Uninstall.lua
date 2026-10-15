if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Uninstall.lua
--  The game settings EllesmereUI changes that outlive it, and what puts them
--  back: the login pass that puts back the CVars of a module turned off, and
--  the Uninstall EUI action (Global Settings > General) for everything.
--
--  Every such change goes through the setters here: CVars (whole values and
--  single bits), Edit Mode layout settings, chat window font sizes and the
--  keys EllesmereUI takes for its own commands. The first change of a setting
--  records the value it had before (its snapshot); every change records the
--  value EllesmereUI left. A setting goes back only while it still holds
--  EllesmereUI's value: one the player changed since is theirs and stays.
--
--  A CVar writer names its module (owner: the addon folder; nil for the
--  parent). At login the CVars of a module that did not load go back and their
--  records are dropped, so its first writes once it is back record the values
--  found then: this character's own CVars when the module is off for this
--  character, the CVars every character shares only once it is off for all of
--  them (or gone). Uninstall puts back everything, drops what it put back,
--  runs the steps modules registered with OnUninstall, turns EllesmereUI off
--  for every character and reloads.
--
--  A CVar EllesmereUI only borrows (a sort's muted sound, chat bubbles in an
--  instance, friendly plates in a follower dungeon) goes through HoldCVar and
--  ReleaseCVar: once the release puts back the value from before the hold, the
--  record goes back as it was then, so the value the player gets back is never
--  mistaken for one of EllesmereUI's.
--
--  The settings Optimize My FPS and Graphics changes stay out of all of this:
--  it keeps its own backup (gfxBackup), which its card restores.
--
--  Snapshots are kept only on an account that started on this build or later,
--  or since Uninstall EUI ran (fresh), and only for the Edit Mode layouts
--  there were at EllesmereUI's first Edit Mode note (a layout made or renamed
--  since may be a copy of one it had changed). Elsewhere EllesmereUI may have
--  changed a setting before its first record here, so Uninstall puts a CVar
--  back to the game's default and an Edit Mode setting to the fallback its
--  writer named (or leaves it), and a module turned off leaves its CVars as
--  they are, their records kept for Uninstall while they still hold
--  EllesmereUI's values. Fresh is judged from the saved data alone: a value
--  EllesmereUI set before its saved data was deleted reads as the player's own.
--
--  Record: EllesmereUIDB.restoreOnUninstall (never exported or imported, kept
--  by Reset ALL Settings)
--    fresh    snapshots are kept
--    cvar     [lowercase name] = { b = before, a = EllesmereUI's last value, o = owner }
--    held     [lowercase name] = { e = the cvar entry before the hold (false: none),
--             v = the value then, o = owner }
--    bits     [lowercase name] = { [bit index] = { b, a, o } }
--    em       [layout name] = { [system * 1000 + index] = { [setting] =
--             { b, a, f = fallback, p = the setting it goes back with },
--             anchor = { b, a } } } (b: a position, { i = anchorInfo,
--             i2 = anchorInfo2, d = isInDefaultPosition }; a = EllesmereUI's
--             anchorInfo)
--    emKnown  [layout name] = true: the layouts there were at EllesmereUI's
--             first Edit Mode note (listed on a fresh account only)
--    bind     [key] = the action it had before EllesmereUI took it (false: none)
--    chars    [player GUID] = the same for per-character state: cvar, held, bits,
--             em and emKnown (Character layouts), bind (character binding set)
--             and chatFont = { [window] = { b, a } }
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local KEY = "restoreOnUninstall"
-- A standalone build is one addon: no part of it can be off while it runs
-- (the Lite lifecycle's folder-name test, which the build never renames).
local IS_STANDALONE = ADDON_NAME:find("Standalone") ~= nil
local _fresh       -- nil until this addon's saved data has loaded
local _uninstalled -- set once Uninstall ran: nothing re-applies before the reload
local _putBack = {} -- lowercase CVar names written back this session

-- The account started fresh: no saved data, or no profile holding any
-- module's settings yet (the first-install picker's own test).
local function IsFreshAccount(db)
    if type(db) ~= "table" then return true end
    if type(db.profiles) == "table" then
        for _, prof in pairs(db.profiles) do
            if type(prof) == "table" and type(prof.addons) == "table" and next(prof.addons) then
                return false
            end
        end
    end
    return true
end

local function Record()
    local db = EllesmereUIDB
    if type(db) ~= "table" then
        db = {}
        EllesmereUIDB = db
    end
    local r = db[KEY]
    if type(r) ~= "table" then
        r = { fresh = _fresh or nil }
        db[KEY] = r
    end
    return r
end

-- This character's part of the record (nil while its GUID is unknown, and
-- with peek while it holds nothing).
local function CharRecord(peek)
    local guid = UnitGUID("player")
    if not guid then return nil end
    local r = Record()
    local chars = r.chars
    if not chars then
        if peek then return nil end
        chars = {}
        r.chars = chars
    end
    local c = chars[guid]
    if not c and not peek then
        c = {}
        chars[guid] = c
    end
    return c
end

local function Sub(t, k)
    local s = t[k]
    if not s then s = {}; t[k] = s end
    return s
end

local CheckModules -- the login pass, below

EllesmereUI.Lite.OnSavedVariablesLoaded(function()
    local r = type(EllesmereUIDB) == "table" and EllesmereUIDB[KEY]
    if type(r) == "table" then
        _fresh = r.fresh == true
    else
        -- A standalone may have built the store before any saved data loaded:
        -- when no saved data replaced it, that is a fresh account too.
        _fresh = EllesmereUI.Lite.StoreFromBeforeLoad() or IsFreshAccount(EllesmereUIDB)
    end
    -- The record is written at login, so a fresh account keeps its mark even
    -- when this session changes nothing.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Record()
        if IS_STANDALONE then return end
        -- After a reload in combat the module pass waits for it to end: some
        -- CVars cannot change in combat.
        if InCombatLockdown() then
            EllesmereUI.CombatQueue.Defer("UninstallModulePass", CheckModules)
            return
        end
        CheckModules()
    end)
end)

-------------------------------------------------------------------------------
--  CVars
-------------------------------------------------------------------------------
local GetCVar, GetCVarBitfield = C_CVar.GetCVar, C_CVar.GetCVarBitfield

-- The part of the record a CVar belongs to: this character's for a
-- per-character one (nil while the character is unknown).
local function CVarRoot(name)
    local _, _, _, perChar = C_CVar.GetCVarInfo(name)
    if perChar then return CharRecord() end
    return Record()
end

-- What the game's own SetCVar passes on: true/false as "1"/"0", the rest as text.
local function CVarString(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    if value ~= nil then return tostring(value) end
    return nil
end

-- Keyed in lower case: CVar names are case-insensitive, and EllesmereUI
-- spells some two ways.
local function Note(name, before, owner)
    -- Nothing to record into before this addon's saved data loads, and an
    -- unknown CVar is nothing to put back.
    if _fresh == nil or before == nil then return end
    local root = CVarRoot(name)
    if not root then return end
    local t = Sub(root, "cvar")
    local key = name:lower()
    local e = t[key]
    if not e then
        e = {}
        t[key] = e
        if Record().fresh then e.b = before end
    end
    e.a = GetCVar(name)
    e.o = owner
end

--- SetCVar for every value EllesmereUI sets on its own. owner is the module
--- that sets it (its addon folder name, also from its options page; nil for
--- the parent): turning that module off puts the value back.
function EllesmereUI.SetCVar(name, value, owner)
    if _uninstalled then return false end
    local before = GetCVar(name)
    local ok = C_CVar.SetCVar(name, CVarString(value))
    -- A refused write (a locked or protected CVar) changed nothing.
    if ok then Note(name, before, owner) end
    return ok
end

--- For a CVar EllesmereUI holds only for a while: SetCVar, keeping what the
--- record held before, which ReleaseCVar puts back.
function EllesmereUI.HoldCVar(name, value, owner)
    if _uninstalled then return false end
    local cur = GetCVar(name)
    local root = _fresh ~= nil and cur ~= nil and CVarRoot(name)
    local key = name:lower()
    local snap
    if root and not (root.held and root.held[key]) then
        local e = root.cvar and root.cvar[key]
        snap = { e = e and { b = e.b, a = e.a, o = e.o } or false, v = cur, o = owner }
    end
    local ok = EllesmereUI.SetCVar(name, value, owner)
    if ok and snap then Sub(root, "held")[key] = snap end
    return ok
end

--- Ends a hold: writes value (what the CVar was when the hold began; nil
--- writes nothing). Once the CVar is back at the value from before the hold,
--- the record goes back as it was then. owner is the module, as for HoldCVar.
function EllesmereUI.ReleaseCVar(name, value, owner)
    local key = name:lower()
    -- After Uninstall the record is final, and what Uninstall put back stays.
    if _uninstalled then
        if value == nil or _putBack[key] then return false end
        return C_CVar.SetCVar(name, CVarString(value))
    end
    local prior = GetCVar(name)
    local ok
    if value ~= nil then
        ok = C_CVar.SetCVar(name, CVarString(value))
        -- Refused: the hold stands (Uninstall or the module pass releases it).
        if not ok then return ok end
    end
    local cur = GetCVar(name)
    if _fresh == nil or cur == nil then return ok end
    local root = CVarRoot(name)
    if not root then return ok end
    local h = root.held and root.held[key]
    if h and cur == h.v then
        root.held[key] = nil
        if h.e then
            Sub(root, "cvar")[key] = h.e
        elseif root.cvar then
            root.cvar[key] = nil
        end
    else
        local e = root.cvar and root.cvar[key]
        if e then
            -- Anything else is still EllesmereUI's doing (a module that lost
            -- track of the value it borrowed): the hold stands, with this as
            -- its value.
            e.a = cur
        elseif not h and prior ~= cur then
            -- A hand-back with no hold on file (one another character left,
            -- or one the module pass already ended) is a change of its own.
            Note(name, prior, owner)
        end
    end
    return ok
end

--- SetCVarBitfield likewise. Recorded per bit, so only the bits EllesmereUI
--- set go back, never one the game set since.
function EllesmereUI.SetCVarBitfield(name, index, value, owner)
    if _uninstalled then return false end
    local before = GetCVarBitfield(name, index)
    local ok = C_CVar.SetCVarBitfield(name, index, value)
    local root = ok and _fresh ~= nil and before ~= nil and CVarRoot(name)
    if root then
        local t = Sub(Sub(root, "bits"), name:lower())
        local e = t[index]
        if not e then
            e = {}
            t[index] = e
            if Record().fresh then e.b = before end
        end
        e.a = GetCVarBitfield(name, index)
        e.o = owner
    end
    return ok
end

-- A hold its module never ended (a reload in the middle of it, or the module
-- turned off since): the value from before the hold goes back while the CVar
-- still holds EllesmereUI's, and the record goes back as the release leaves it.
local function ReleaseHold(root, key, h)
    local e = root.cvar and root.cvar[key]
    if h.v ~= nil and e and GetCVar(key) == e.a then
        pcall(C_CVar.SetCVar, key, h.v)
        _putBack[key] = true
    end
    if h.e then
        Sub(root, "cvar")[key] = h.e
    elseif root.cvar then
        root.cvar[key] = nil
    end
    root.held[key] = nil
end

local function ReleaseHolds(root)
    local held = root and root.held
    if not held then return end
    for key, h in pairs(held) do ReleaseHold(root, key, h) end
end

-- Puts back every recorded CVar that still holds EllesmereUI's value: to its
-- snapshot, else the game's default.
local function RestoreCVars(t)
    if not t then return end
    for name, e in pairs(t) do
        local cur = GetCVar(name)
        if cur ~= nil and cur == e.a then
            local want = e.b or C_CVar.GetCVarDefault(name)
            if want ~= nil and want ~= cur then
                pcall(C_CVar.SetCVar, name, want)
                _putBack[name] = true
            end
        end
    end
end

-- A bitfield CVar is a version character followed by characters carrying six
-- bits each (the game's own reader, CVarCallbackRegistry:GetCVarBitfieldIndex):
-- the bit of index in the CVar's default.
local function DefaultBit(name, index)
    local def = C_CVar.GetCVarDefault(name)
    if type(def) ~= "string" then return nil end
    local i = index - 1
    local byte = def:byte(2 + math.floor(i / 6))
    if not byte then return false end
    return math.floor(byte / 2 ^ (i % 6)) % 2 == 1
end

local function RestoreBits(t)
    if not t then return end
    for name, bits in pairs(t) do
        for index, e in pairs(bits) do
            local cur = GetCVarBitfield(name, index)
            if cur ~= nil and cur == e.a then
                local want = e.b
                if want == nil then want = DefaultBit(name, index) end
                if want ~= nil and want ~= cur then pcall(C_CVar.SetCVarBitfield, name, index, want) end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Modules turned off
-------------------------------------------------------------------------------

-- The module that owns a record is off: it did not load this session and,
-- for a record of the account's (acct), which every character shares, it is
-- off for every character too, or gone.
local function ModuleOff(owner, acct)
    if owner == nil or owner == ADDON_NAME or C_AddOns.IsAddOnLoaded(owner) then return false end
    return not acct or not C_AddOns.DoesAddOnExist(owner)
        or C_AddOns.GetAddOnEnableState(owner) == Enum.AddOnEnableState.None
end

-- One part of the record (the account's, acct, or this character's): each
-- record of a module that is off goes back to its snapshot while it still
-- holds EllesmereUI's value, and is dropped. One with no snapshot stays while
-- the CVar holds EllesmereUI's value, so Uninstall can still put it back to
-- the game's default. A hold such a module left open is released.
local function RevertOffModules(root, acct)
    if not root then return end
    local held = root.held
    if held then
        for key, h in pairs(held) do
            if ModuleOff(h.o) then ReleaseHold(root, key, h) end
        end
        if next(held) == nil then root.held = nil end
    end
    local t = root.cvar
    if t then
        for key, e in pairs(t) do
            if ModuleOff(e.o, acct) then
                local cur = GetCVar(key)
                if e.b ~= nil and e.b ~= e.a and cur == e.a then
                    pcall(C_CVar.SetCVar, key, e.b)
                    _putBack[key] = true
                end
                if e.b ~= nil or cur ~= e.a then t[key] = nil end
            end
        end
        if next(t) == nil then root.cvar = nil end
    end
    local bits = root.bits
    if bits then
        for name, byIndex in pairs(bits) do
            for index, e in pairs(byIndex) do
                if ModuleOff(e.o, acct) then
                    local cur = GetCVarBitfield(name, index)
                    if e.b ~= nil and e.b ~= e.a and cur == e.a then
                        pcall(C_CVar.SetCVarBitfield, name, index, e.b)
                    end
                    if e.b ~= nil or cur ~= e.a then byIndex[index] = nil end
                end
            end
            if next(byIndex) == nil then bits[name] = nil end
        end
        if next(bits) == nil then root.bits = nil end
    end
end

-- At login (out of combat): the parent, which loads whenever any module does,
-- puts back what a module that is off left behind.
CheckModules = function()
    RevertOffModules(Record(), true)
    local c = CharRecord(true)
    if not c then return end
    RevertOffModules(c, false)
    if next(c) == nil then Record().chars[UnitGUID("player")] = nil end
end

-------------------------------------------------------------------------------
--  Edit Mode layouts
-------------------------------------------------------------------------------
local CHAR_LAYOUT = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character

--- Blizzard's Edit Mode is open: it saves its own copy of the layouts on
--- exit, over anything written meanwhile.
function EllesmereUI.EditModeOpen()
    local emf = _G.EditModeManagerFrame
    if not emf then return false end
    return (emf.editModeActive or (emf.IsShown and emf:IsShown())) and true or false
end
local EditModeOpen = EllesmereUI.EditModeOpen

--- The saved layouts with the presets first, as SaveLayouts takes them: it
--- replaces the whole set, and activeLayout indexes that merged list, while
--- C_EditMode.GetLayouts returns only the saved half. Returns the layout info
--- and the number of presets, or nil when that cannot be built (never save a
--- short list).
function EllesmereUI.EditModeLayoutsForSave()
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then return nil end
    local mgr = EditModePresetLayoutManager
    local presets = mgr and mgr.GetCopyOfPresetLayouts and mgr:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then return nil end
    local numPresets = #presets
    for i = 1, #info.layouts do presets[numPresets + i] = info.layouts[i] end
    info.layouts = presets
    return info, numPresets
end
local LayoutsForSave = EllesmereUI.EditModeLayoutsForSave

-- On a fresh account, the layouts there are when EllesmereUI first notes one:
-- listed once for the account, and once for each character (its own
-- Character layouts) at its first note, which the Action Bars sync makes at
-- every login.
local function ListLayouts(acct, mine)
    local newA, newM = not acct.emKnown, mine ~= nil and not mine.emKnown
    if not (newA or newM) then return end
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then return end
    local a, m = newA and {} or nil, newM and {} or nil
    for _, layout in ipairs(info.layouts) do
        if type(layout) == "table" and type(layout.layoutName) == "string" then
            if layout.layoutType == CHAR_LAYOUT then
                if m then m[layout.layoutName] = true end
            elseif a then
                a[layout.layoutName] = true
            end
        end
    end
    if a then acct.emKnown = a end
    if m then mine.emKnown = m end
end

-- The record of key (a setting, or "anchor") of sysInfo in layout, made on
-- the first note with the value from before (fresh, a layout there was at
-- the first note) or else fallback. nil while the character is unknown.
local function EditModeEntry(layout, sysInfo, key, before, fallback)
    local r = Record()
    local isChar = layout.layoutType == CHAR_LAYOUT
    local mine
    if r.fresh or isChar then mine = CharRecord() end
    if r.fresh then ListLayouts(r, mine) end
    local root
    if isChar then root = mine else root = r end
    if not root then return nil end
    local t = Sub(Sub(Sub(root, "em"), layout.layoutName), sysInfo.system * 1000 + (sysInfo.systemIndex or 0))
    local e = t[key]
    if not e then
        e = {}
        t[key] = e
        local known = root.emKnown
        if r.fresh and (known == nil or known[layout.layoutName]) then
            e.b = before
        else
            e.f = fallback
        end
    end
    return e
end

--- Before EllesmereUI writes value into setting of sysInfo (a system entry of
--- layout, a saved layout from C_EditMode.GetLayouts): records the row's
--- value then (before) and value. fallback is what Uninstall puts back when
--- the value from before EllesmereUI is unknown (an older account, or a
--- layout made or renamed since EllesmereUI first changed one, which may be a
--- copy of one it had changed); nil leaves that row as it is. pair names a
--- setting that only means something together with this one (a size's
--- hundreds and the rest): the two go back together or not at all.
function EllesmereUI.NoteEditModeSetting(layout, sysInfo, setting, before, value, fallback, pair)
    if _fresh == nil or before == nil then return end
    if type(layout) ~= "table" or type(layout.layoutName) ~= "string" then return end
    local e = EditModeEntry(layout, sysInfo, setting, before, fallback)
    if not e then return end
    e.a = value
    e.p = pair
end

local function AnchorCopy(info)
    if type(info) ~= "table" then return nil end
    return {
        point = info.point, relativeTo = info.relativeTo, relativePoint = info.relativePoint,
        offsetX = info.offsetX, offsetY = info.offsetY,
    }
end

-- A system's position: its anchors and whether Edit Mode counts it as the
-- default one.
local function Position(sys)
    return { i = AnchorCopy(sys.anchorInfo), i2 = AnchorCopy(sys.anchorInfo2), d = sys.isInDefaultPosition == true }
end

--- Before EllesmereUI moves sysInfo (a system entry of layout, as for
--- NoteEditModeSetting) to anchor, its only anchor from then on: records the
--- system's position then and anchor. Where the position from before is
--- unknown, Uninstall leaves the system where it is.
function EllesmereUI.NoteEditModeAnchor(layout, sysInfo, anchor)
    if _fresh == nil or type(anchor) ~= "table" then return end
    if type(sysInfo) ~= "table" or type(sysInfo.anchorInfo) ~= "table" then return end
    if type(layout) ~= "table" or type(layout.layoutName) ~= "string" then return end
    local e = EditModeEntry(layout, sysInfo, "anchor", Position(sysInfo))
    if not e then return end
    e.a = AnchorCopy(anchor)
end

-- The rows of one system that go back, as row -> value (nil: none).
local function SystemRestores(sys, bySys)
    local rows = {}
    for _, row in ipairs(sys.settings) do rows[row.setting] = row end
    local function Ours(setting)
        local e, row = bySys[setting], rows[setting]
        return e ~= nil and row ~= nil and row.value == e.a
    end
    local out
    for setting, e in pairs(bySys) do
        if Ours(setting) and (e.p == nil or Ours(e.p)) then
            local want = e.b
            if want == nil then want = e.f end
            if want ~= nil and want ~= rows[setting].value then
                out = out or {}
                out[rows[setting]] = want
            end
        end
    end
    return out
end

-- Within Edit Mode's own tolerance for anchors (0.1).
local function SameAnchor(a, b)
    return type(a) == "table" and type(b) == "table"
        and a.point == b.point and a.relativeTo == b.relativeTo and a.relativePoint == b.relativePoint
        and type(a.offsetX) == "number" and type(b.offsetX) == "number"
        and type(a.offsetY) == "number" and type(b.offsetY) == "number"
        and math.abs(a.offsetX - b.offsetX) < 0.1 and math.abs(a.offsetY - b.offsetY) < 0.1
end

-- Puts the system's position back while it is still EllesmereUI's (its only
-- anchor); true when it changed.
local function RestoreAnchor(sys, e)
    if type(e) ~= "table" or sys.anchorInfo2 ~= nil or not SameAnchor(sys.anchorInfo, e.a) then
        return false
    end
    local want = e.b
    if type(want) ~= "table" or not want.i then return false end
    if want.i2 == nil and SameAnchor(sys.anchorInfo, want.i) then return false end
    sys.anchorInfo = AnchorCopy(want.i)
    sys.anchorInfo2 = AnchorCopy(want.i2)
    sys.isInDefaultPosition = want.d == true
    return true
end

-- True once the layouts were gone through (false: they could not be read).
local function RestoreEditMode(acct, mine)
    if not (acct or mine) then return true end
    local info, numPresets = LayoutsForSave()
    if not info then return false end
    local changed = false
    for i = numPresets + 1, #info.layouts do
        local layout = info.layouts[i]
        local src
        if layout.layoutType == CHAR_LAYOUT then src = mine else src = acct end
        local byLayout = src and src[layout.layoutName]
        if byLayout and type(layout.systems) == "table" then
            for _, sys in ipairs(layout.systems) do
                local bySys = byLayout[sys.system * 1000 + (sys.systemIndex or 0)]
                local out = bySys and type(sys.settings) == "table" and SystemRestores(sys, bySys)
                if out then
                    for row, want in pairs(out) do row.value = want end
                    changed = true
                end
                if bySys and RestoreAnchor(sys, bySys.anchor) then changed = true end
            end
        end
    end
    if changed then C_EditMode.SaveLayouts(info) end
    return true
end

-------------------------------------------------------------------------------
--  Chat windows
-------------------------------------------------------------------------------

--- SetChatWindowSize for a font size EllesmereUI applies on its own (stored
--- per character, like the window itself).
function EllesmereUI.SetChatWindowSize(index, size)
    if _uninstalled then return end
    local _, before = GetChatWindowInfo(index)
    SetChatWindowSize(index, size)
    if _fresh == nil or before == nil then return end
    local c = CharRecord()
    if not c then return end
    local t = Sub(c, "chatFont")
    local e = t[index]
    if not e then
        e = {}
        t[index] = e
        if Record().fresh then e.b = before end
    end
    local _, after = GetChatWindowInfo(index)
    e.a = after
end

local function RestoreChatFonts(t)
    if not t then return end
    for index, e in pairs(t) do
        local _, cur = GetChatWindowInfo(index)
        if cur ~= nil and cur == e.a and e.b ~= nil and e.b ~= cur then
            SetChatWindowSize(index, e.b)
        end
    end
end

-------------------------------------------------------------------------------
--  Key bindings
-------------------------------------------------------------------------------

--- Before EllesmereUI binds key to one of its own commands (EUI_*): records
--- the action the key had then, so Uninstall can hand it back. The latest
--- action the player gave the key counts; an empty key or one of
--- EllesmereUI's own commands never replaces it.
function EllesmereUI.NoteBinding(key, before)
    if _fresh == nil or not key then return end
    local root
    if GetCurrentBindingSet() == 2 then root = CharRecord() else root = Record() end
    if not root then return end
    local t = Sub(root, "bind")
    local action = type(before) == "string" and before ~= "" and not before:find("^EUI_") and before or false
    if t[key] == nil or action then t[key] = action end
end

-- A key EllesmereUI took from another action goes back to it while the key
-- is still on one of EllesmereUI's commands, or empty (EllesmereUI moves and
-- clears the keys it took). Other keys on its commands stay: they do nothing
-- while it is off and work again if it comes back. Only the binding set in
-- use can be saved; returns that set.
local function RestoreBindings(acct, mine)
    local set = GetCurrentBindingSet()
    local rec
    if set == 2 then rec = mine.bind else rec = acct.bind end
    if rec then
        local changed = false
        for key, before in pairs(rec) do
            local action = GetBindingAction(key)
            if before and type(action) == "string" and (action == "" or action:find("^EUI_")) then
                SetBinding(key, before)
                changed = true
            end
        end
        if changed then SaveBindings(set) end
    end
    return set
end

-------------------------------------------------------------------------------
--  Uninstall EUI
-------------------------------------------------------------------------------
local _steps = {}

--- Adds a step Uninstall runs before EllesmereUI turns off: for changes only
--- its module knows how to undo.
function EllesmereUI.OnUninstall(fn)
    _steps[#_steps + 1] = fn
end

--- True when the record holds the settings from before EllesmereUI (false:
--- they go back to the game's defaults instead).
function EllesmereUI.UninstallKnowsOriginals()
    local r = type(EllesmereUIDB) == "table" and EllesmereUIDB[KEY]
    return type(r) == "table" and r.fresh == true
end

-- Every installed EllesmereUI addon: this one (the suite's parent or a
-- standalone) and each EllesmereUI module.
local function OwnAddOns()
    local list = { ADDON_NAME }
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= ADDON_NAME and name:find("^EllesmereUI") then
            list[#list + 1] = name
        end
    end
    return list
end

--- Puts back the settings EllesmereUI changed and turns it off for every
--- character; the caller reloads (EllesmereUI.RequestReload). Refused, with
--- nothing changed, in combat (key bindings and protected CVars cannot change
--- then) and while Edit Mode is open. Returns true when it ran.
function EllesmereUI.Uninstall()
    if _uninstalled or InCombatLockdown() or EditModeOpen() then return false end
    -- From here on nothing re-applies a setting, not even a handler the
    -- writes below wake.
    _uninstalled = true
    local r = Record()
    local mine = CharRecord(true) or {}
    -- Each part in a pcall: one that fails never keeps EllesmereUI from turning
    -- off. What a part put back is dropped, so the next time EllesmereUI is
    -- turned on its first writes record the values found then; a part that
    -- failed keeps its records for a later Uninstall.
    pcall(ReleaseHolds, r)
    pcall(ReleaseHolds, mine)
    if pcall(RestoreCVars, r.cvar) then r.cvar = nil end
    if pcall(RestoreCVars, mine.cvar) then mine.cvar = nil end
    if pcall(RestoreBits, r.bits) then r.bits = nil end
    if pcall(RestoreBits, mine.bits) then mine.bits = nil end
    local okEM, emDone = pcall(RestoreEditMode, r.em, mine.em)
    if okEM and emDone then
        r.em, mine.em = nil, nil
        r.emKnown, mine.emKnown = nil, nil
    end
    if pcall(RestoreChatFonts, mine.chatFont) then mine.chatFont = nil end
    local okBind, set = pcall(RestoreBindings, r, mine)
    if okBind then
        if set == 2 then mine.bind = nil else r.bind = nil end
    end
    for i = 1, #_steps do pcall(_steps[i]) end
    -- Everything EllesmereUI changed is back, so from here on every snapshot
    -- holds the player's own values.
    r.fresh = true
    for _, name in ipairs(OwnAddOns()) do
        C_AddOns.DisableAddOn(name)
    end
    C_AddOns.SaveAddOns()
    return true
end
