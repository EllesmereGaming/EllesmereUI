-- Stub harness: the raid marker on the friendly NPC name-only overlay (Show
-- Raid Marker in the Friendly NPC Settings cog) and on the friendly plates.
-- Cuts the overlay block (npcOverlays through RefreshAllNPCOverlays) and
-- FriendlyFrame:UpdateRaidIcon out of EllesmereUINameplatesFriendly.lua and
-- drives them on fake frames: the marker shows by default, follows
-- RAID_TARGET_UPDATE, stays hidden while the Raid Marker element is off or the
-- option is off, never leaks onto a pooled overlay, and the marker index is
-- only ever tested through type() (it is secret in every dungeon).
--   lua .tools/tests/test_np_npc_overlay_raid_marker.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

-- From the start of `from` to the end of the line holding `to`.
local function CutThrough(src, from, to, label)
    local a = assert(src:find(from, 1, true), label .. ": start missing")
    local b = assert(src:find(to, a, true), label .. ": end marker missing")
    local e = src:find("\n", b, true) or #src
    return src:sub(a, e)
end

-- From the start of `from` to the first column-0 `end` after it.
local function CutFunction(src, from, label)
    local a = assert(src:find(from, 1, true), label .. ": start missing")
    local e = assert(src:find("\nend\n", a, true), label .. ": end missing")
    return src:sub(a, e + 4)
end

local FRIENDLY_SRC = ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua")
local OVERLAY = CutThrough(FRIENDLY_SRC, "local npcOverlays = {}",
    "ns.RefreshAllNPCOverlays = RefreshAllNPCOverlays", "overlay block")
local PLATE_MARKER = CutFunction(FRIENDLY_SRC, "function FriendlyFrame:UpdateRaidIcon()", "plate marker")
local OVERLAY_MARKER = CutFunction(OVERLAY, "local function UpdateOverlayRaidIcon(overlay)", "overlay marker")

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-------------------------------------------------------------------------------
--  Fake frames, font strings and textures
-------------------------------------------------------------------------------
local Region = {}
Region.__index = Region
local function NewRegion(kind)
    return setmetatable({ _kind = kind, _shown = true, _events = {}, _scripts = {} }, Region)
end
function Region:SetSize(w, h) self._w, self._h = w, h end
function Region:SetPoint(...) self._point = { ... } end
function Region:ClearAllPoints() self._point = nil end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:IsShown() return self._shown end
function Region:SetParent(p) self._parent = p end
function Region:SetFrameLevel(l) self._level = l end
function Region:GetFrameLevel() return self._level or 1 end
function Region:SetTexture(t) self._texture = t end
function Region:SetText(t) self._text = t end
function Region:SetWidth() end
function Region:SetWordWrap() end
function Region:SetNonSpaceWrap() end
function Region:SetMaxLines() end
function Region:SetTextColor() end
function Region:SetSnapToPixelGrid() end
function Region:SetTexelSnappingBias() end
function Region:RegisterEvent(e) self._events[e] = true end
function Region:RegisterUnitEvent(e) self._events[e] = true end
function Region:UnregisterAllEvents() for k in pairs(self._events) do self._events[k] = nil end end
function Region:SetScript(name, fn) self._scripts[name] = fn end
function Region:CreateFontString() return NewRegion("fontstring") end
function Region:CreateTexture()
    local t = NewRegion("texture")
    self._textures = (self._textures or 0) + 1
    return t
end

-- The engine delivers an event only to a frame that registered it.
local function Fire(frame, event)
    if frame._events[event] and frame._scripts.OnEvent then
        frame._scripts.OnEvent(frame, event)
    end
end

-------------------------------------------------------------------------------
--  Game state and the chunk environment
-------------------------------------------------------------------------------
local PROFILE = {}
local POS = "topright"
local SIZE = 22
local MARKS = {}
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local ns = {
    defaults = {
        friendlyNPCNameColor = { r = 1, g = 1, b = 1 },
        friendlyNPCTitleColor = { r = 1, g = 1, b = 1, a = 0.8 },
    },
    GetRaidMarkerSize = function() return SIZE end,
    GetRaidMarkerPos = function() return POS end,
    GetRaidMarkerYOffset = function() return 0 end,
    GetDebuffYOffset = function() return 4 end,
}

local env = setmetatable({
    ns = ns,
    FP = function() return PROFILE end,
    SetFSFont = function() end,
    GetFont = function() return "font" end,
    GetNPOutline = function() return "" end,
    GetNPUseShadow = function() return false end,
    ShowNPCTitles = function() return false end,
    GetNPCTitle = function() return nil end,
    UnitReaction = function() return 5 end,
    UnitName = function(unit) return "NPC " .. tostring(unit) end,
    UIParent = NewRegion("frame"),
    CreateFrame = function() return NewRegion("frame") end,
    GetRaidTargetIndex = function(unit) return MARKS[unit] end,
    SetRaidTargetIconTexture = function(tex, idx) tex._cell = idx end,
    EllesmereUI = {
        SetFontFamily = function() end,
        ShortName = function(name) return name end,
    },
    FriendlyFrame = {},
}, { __index = _G })

local chunk = assert(loadstring(OVERLAY .. PLATE_MARKER .. [[
return { Show = ShowNPCOverlay, Hide = HideNPCOverlay, Refresh = RefreshAllNPCOverlays, overlays = npcOverlays }
]], "=overlay"))
setfenv(chunk, env)
local O = chunk()

local function Plate(level) local np = NewRegion("nameplate"); np._level = level; return np end
local function MarkerShown(ov) return ov.raid ~= nil and ov.raid:IsShown() end

-------------------------------------------------------------------------------
--  1. The default is on
-------------------------------------------------------------------------------
do
    local main = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")
    check(main:find("\n%s*showNPCRaidMarker = true,") ~= nil, "1: the default showNPCRaidMarker is true")
end

-------------------------------------------------------------------------------
--  2. An unset option shows a marked NPC's marker above its name
-------------------------------------------------------------------------------
local np1 = Plate(10)
MARKS.nameplate1 = 3
O.Show(np1, "nameplate1")
local ov1 = O.overlays[np1]
check(ov1 ~= nil, "2: the overlay is shown")
check(ov1._events.RAID_TARGET_UPDATE == true, "2: RAID_TARGET_UPDATE is registered while the option is on")
check(MarkerShown(ov1), "2: the marker shows")
check(ov1.raid and ov1.raid._cell == 3, "2: the marker shows the unit's icon")
check(ov1.raid and ov1.raid._w == SIZE and ov1.raid._h == SIZE, "2: the marker takes the raid marker size")
local pt = ov1.raid and ov1.raid._point
check(pt and pt[1] == "BOTTOM" and pt[2] == ov1.name and pt[3] == "TOP" and pt[5] == 2,
    "2: the marker sits above the name")

-------------------------------------------------------------------------------
--  3. An unmarked NPC shows none; 4. markers follow RAID_TARGET_UPDATE
-------------------------------------------------------------------------------
local np2 = Plate(10)
O.Show(np2, "nameplate2")
local ov2 = O.overlays[np2]
check(not MarkerShown(ov2), "3: an unmarked NPC shows no marker")
MARKS.nameplate2 = 5
Fire(ov2, "RAID_TARGET_UPDATE")
check(MarkerShown(ov2) and ov2.raid._cell == 5, "4: a marker set later shows on the event")
MARKS.nameplate2 = nil
Fire(ov2, "RAID_TARGET_UPDATE")
check(not MarkerShown(ov2), "4: a cleared marker hides on the event")

-------------------------------------------------------------------------------
--  5. The Raid Marker element switched off hides it
-------------------------------------------------------------------------------
POS = "none"
Fire(ov1, "RAID_TARGET_UPDATE")
check(not MarkerShown(ov1), "5: hidden while the Raid Marker element is off")
POS = "topright"
Fire(ov1, "RAID_TARGET_UPDATE")
check(MarkerShown(ov1) and ov1.raid._cell == 3, "5: back once the element is on again")

-------------------------------------------------------------------------------
--  6. Turning the option off clears every marker and the event
-------------------------------------------------------------------------------
PROFILE.showNPCRaidMarker = false
O.Refresh()
for np, ov in pairs(O.overlays) do
    check(not MarkerShown(ov), "6: no marker while the option is off")
    check(not ov._events.RAID_TARGET_UPDATE, "6: RAID_TARGET_UPDATE is not registered while the option is off")
end
check(O.overlays[np1] ~= nil and O.overlays[np2] ~= nil, "6: the overlays are shown again")

-------------------------------------------------------------------------------
--  7. A pooled overlay never carries an old marker to its next NPC
-------------------------------------------------------------------------------
PROFILE.showNPCRaidMarker = nil
O.Refresh()
local marked = O.overlays[np1]
check(MarkerShown(marked), "7: the marker is back with the option on")
O.Hide(np1)
check(not MarkerShown(marked), "7: hiding the overlay hides its marker")
PROFILE.showNPCRaidMarker = false
local np3 = Plate(10)
O.Show(np3, "nameplate3")
local ov3 = O.overlays[np3]
check(ov3 == marked, "7: the pooled overlay is reused")
check(not MarkerShown(ov3), "7: the reused overlay shows no old marker")
O.Hide(np3)
PROFILE.showNPCRaidMarker = nil

-------------------------------------------------------------------------------
--  8. A secret index goes straight to the texture
-------------------------------------------------------------------------------
local np4 = Plate(10)
MARKS.nameplate4 = SECRET
O.Show(np4, "nameplate4")
local ov4 = O.overlays[np4]
check(MarkerShown(ov4) and ov4.raid._cell == SECRET, "8: a secret index is drawn by the texture setter")

-------------------------------------------------------------------------------
--  9. The marker index is only tested through type()
-------------------------------------------------------------------------------
local function ReadsIdxOnlyThroughType(text)
    local stripped = text:gsub("%-%-[^\n]*", "")
    local bad = {
        "%f[%w_]not%s+idx%f[^%w_]", "%f[%w_]if%s+idx%f[^%w_]", "%f[%w_]elseif%s+idx%f[^%w_]",
        "%f[%w_]idx%s+then%f[^%w_]", "%f[%w_]idx%s+and%f[^%w_]", "%f[%w_]idx%s+or%f[^%w_]",
        "%f[%w_]idx%s*==", "%f[%w_]idx%s*~=", "%f[%w_]idx%s*[<>]",
        "==%s*idx%f[^%w_]", "~=%s*idx%f[^%w_]", "[<>]=?%s*idx%f[^%w_]",
    }
    for _, pat in ipairs(bad) do
        if stripped:find(pat) then return false, pat end
    end
    return stripped:find('type%(idx%) == "nil"', 1) ~= nil, "no type() test"
end
do
    local ok, why = ReadsIdxOnlyThroughType(OVERLAY_MARKER)
    check(ok, "9: the overlay reads the index only through type() (" .. tostring(why) .. ")")
    ok, why = ReadsIdxOnlyThroughType(PLATE_MARKER)
    check(ok, "9: the friendly plate reads the index only through type() (" .. tostring(why) .. ")")
end

-------------------------------------------------------------------------------
--  10. The friendly plate's marker
-------------------------------------------------------------------------------
do
    local plate = setmetatable({ unit = "nameplate5", raidFrame = NewRegion("frame"),
        raid = NewRegion("texture"), health = NewRegion("statusbar") }, { __index = env.FriendlyFrame })
    POS = "top"
    MARKS.nameplate5 = 2
    plate:UpdateRaidIcon()
    check(plate.raidFrame:IsShown() and plate.raid._cell == 2, "10: the plate shows its marker")
    MARKS.nameplate5 = nil
    plate:UpdateRaidIcon()
    check(not plate.raidFrame:IsShown(), "10: an unmarked plate hides its marker")
    MARKS.nameplate5 = SECRET
    plate:UpdateRaidIcon()
    check(plate.raidFrame:IsShown() and plate.raid._cell == SECRET, "10: a secret index is drawn")
    POS = "none"
    plate:UpdateRaidIcon()
    check(not plate.raidFrame:IsShown(), "10: hidden while the Raid Marker element is off")
    POS = "topright"
end

-------------------------------------------------------------------------------
--  11. The options row: on unless saved off, greyed while the element is off
-------------------------------------------------------------------------------
do
    local opt = ReadSource("EllesmereUIOptions/Nameplates_Options/GeneralPage_Options.lua")
    local a = opt:find('label = "Show Raid Marker"', 1, true)
    check(a ~= nil, "11: the Show Raid Marker row exists")
    if a then
        local row = opt:sub(a, (opt:find("},\n", a, true) or #opt) + 2)
        check(row:find('get = function() return DBVal("showNPCRaidMarker") ~= false end', 1, true) ~= nil,
            "11: the row reads on unless saved off")
        check(row:find('disabled = markerOff, disabledTooltip = "Raid Marker"', 1, true) ~= nil,
            "11: the row greys out while the Raid Marker element is off")
    end
    check(opt:find('local function markerOff() return (DBVal("raidMarkerPos") or defaults.raidMarkerPos) == "none" end',
        1, true) ~= nil, "11: markerOff reads the Raid Marker element's slot")
end

if fails > 0 then
    error(fails .. " check(s) failed")
end
print("test_np_npc_overlay_raid_marker: all checks passed")
