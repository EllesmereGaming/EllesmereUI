-- Stub harness: the Minimap's clock, zone text and FPS readout sit far above
-- the map (above other addons' map icons), and so above the map's middle-click
-- interceptor. Cuts the click handlers from EUI_Minimap_Apply.lua and checks
-- that a middle click still opens the micro menu over the clock and the FPS
-- readout, that the clock acts on the left and right buttons alone, and that
-- the three frames take the shared level.
--   lua .tools/tests/test_minimap_info_text_clicks.lua        (from the repository root)
local TARGET = MM_TARGET or "EllesmereUIMinimap/EUI_Minimap_Apply.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local fh = assert(io.open(TARGET, "rb"))
local src = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

-- The text between `from` and the first `to` after it, both included.
local function Cut(from, to, what)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b, e = src:find(to, a, true)
    assert(b, what .. ": end not found")
    return src:sub(a, e)
end
-- A handler passed to SetScript: the function expression alone.
local function Handler(setCall, close, what)
    local text = Cut(setCall, close, what)
    text = text:sub(#setCall + 1, #text - 1)          -- drop the call's opening and its ")"
    return assert(loadstring("local EBS = ...\nreturn " .. text), what .. ": does not compile")
end

-- stubs
local menu, timeMgr, vault = 0, 0, 0
local profile = { minimap = {} }
local EBS = { db = { profile = profile }, _ToggleMicroMenu = function() menu = menu + 1 end }
EllesmereUI = { IS_FOREVER = false, ToggleGreatVault = function() vault = vault + 1 end }
ToggleTimeManager = function() timeMgr = timeMgr + 1 end
local function Reset() menu, timeMgr, vault = 0, 0, 0 end

-------------------------------------------------------------------------------
-- 1. The shared middle-click path
-------------------------------------------------------------------------------
assert(loadstring("local EBS = ...\n" .. Cut("function EBS._MapMiddleClick()", "\nend\n", "middle click")))(EBS)
check(type(EBS._MapMiddleClick) == "function", "the shared middle click exists")
Reset(); EBS._MapMiddleClick()
check(menu == 1, "middle click opens the micro menu by default")
profile.minimap.openMicroMenuOnMiddleClick = false
Reset(); EBS._MapMiddleClick()
check(menu == 0, "Open Micro Menu on Middle Click off: nothing")
profile.minimap.openMicroMenuOnMiddleClick = true
Reset(); EBS._MapMiddleClick()
check(menu == 1, "Open Micro Menu on Middle Click on: the micro menu")
profile.minimap.openMicroMenuOnMiddleClick = nil
do
    local keep = EBS._ToggleMicroMenu
    EBS._ToggleMicroMenu = nil
    check(pcall(EBS._MapMiddleClick), "no micro menu yet: no error")
    EBS._ToggleMicroMenu = keep
end

-------------------------------------------------------------------------------
-- 2. The interceptor over the map
-------------------------------------------------------------------------------
local onMap = Handler('blocker:SetScript("OnMouseUp", ', "\n        end)", "interceptor")(EBS)
Reset(); onMap(nil, "MiddleButton")
check(menu == 1, "map: middle click opens the micro menu")
Reset(); onMap(nil, "LeftButton"); onMap(nil, "RightButton"); onMap(nil, "Button4")
check(menu == 0, "map: the other buttons open nothing")

-------------------------------------------------------------------------------
-- 3. The clock: left and right act, middle goes to the map's path, the rest
--    do nothing (the interceptor used to let only left and right through)
-------------------------------------------------------------------------------
local onClock = Handler('clockBg:SetScript("OnClick", ', "\n            end)", "clock")(EBS)
Reset(); onClock(nil, "LeftButton")
check(timeMgr == 1 and menu == 0, "clock: left click opens the Time Manager")
Reset(); onClock(nil, "RightButton")
check(timeMgr == 1 and menu == 0, "clock: right click opens the Time Manager")
Reset(); onClock(nil, "MiddleButton")
check(menu == 1 and timeMgr == 0 and vault == 0, "clock: middle click opens the micro menu, not the Time Manager")
Reset(); onClock(nil, "Button4"); onClock(nil, "Button5")
check(menu == 0 and timeMgr == 0 and vault == 0, "clock: side buttons do nothing")
profile.minimap.openMicroMenuOnMiddleClick = false
Reset(); onClock(nil, "MiddleButton")
check(menu == 0 and timeMgr == 0, "clock: middle click with the option off does nothing")
profile.minimap.openMicroMenuOnMiddleClick = nil
-- the Great Vault hover mode keeps its click
profile.minimap.clockHoverTooltip = "vault"
Reset(); onClock(nil, "LeftButton")
check(vault == 1 and timeMgr == 0, "clock: left click opens the vault under the vault hover mode")
Reset(); onClock(nil, "MiddleButton")
check(menu == 1 and vault == 0, "clock: middle click still the micro menu under the vault hover mode")
EllesmereUI.IS_FOREVER = true
Reset(); onClock(nil, "LeftButton")
check(timeMgr == 1 and vault == 0, "clock on WoW Forever: a saved vault mode opens the Time Manager")
EllesmereUI.IS_FOREVER = false
profile.minimap.clockHoverTooltip = nil

-------------------------------------------------------------------------------
-- 4. The FPS readout (mouse on only while a hover tooltip is assigned)
-------------------------------------------------------------------------------
local onFps = Handler('fpsBg:SetScript("OnMouseUp", ', "\n            end)", "fps")(EBS)
Reset(); onFps(nil, "MiddleButton")
check(menu == 1 and vault == 0, "fps: middle click opens the micro menu")
profile.minimap.fpsHoverTooltip = "vault"
Reset(); onFps(nil, "LeftButton")
check(vault == 1 and menu == 0, "fps: left click opens the vault under the vault hover mode")
Reset(); onFps(nil, "MiddleButton")
check(menu == 1 and vault == 0, "fps: middle click the micro menu under the vault hover mode")
Reset(); onFps(nil, "RightButton")
check(menu == 0 and vault == 0, "fps: right click does nothing")
profile.minimap.fpsHoverTooltip = nil

-------------------------------------------------------------------------------
-- 5. Levels: the three frames take the shared level, which is above every
--    level the module gives its other map children (the interceptor and the
--    buttons at + 10 to + 20), and no file-scope local feeds ApplyMinimap for it
-------------------------------------------------------------------------------
local level = tonumber(src:match("EBS%._INFO_TEXT_LEVEL = (%d+)"))
check(level ~= nil, "the shared level is set")
for _, f in ipairs({ "clockBg", "locationBg", "fpsBg" }) do
    check(src:find(f .. ":SetFrameLevel(minimap:GetFrameLevel() + EBS._INFO_TEXT_LEVEL)", 1, true) ~= nil,
        f .. " takes the shared level")
end
local highest = 0
for n in src:gmatch("SetFrameLevel%(minimap:GetFrameLevel%(%) %+ (%d+)%)") do
    if tonumber(n) > highest then highest = tonumber(n) end
end
check(highest >= 10, "the interceptor's own level is read (" .. highest .. ")")
check(level and level > highest + 1000, "the text sits far above the module's other map children")
check(not src:find("local INFO_TEXT_LEVEL", 1, true), "the level is a field, not a local ApplyMinimap would capture")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_minimap_info_text_clicks (" .. count .. " checks)")
