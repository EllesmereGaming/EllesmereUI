-- Source-check harness: Unit Frames size limits for Vertical Fill. The Health Bar
-- Height and Bar Width sliders widen while Vertical Fill is on (height to 400,
-- width down to 20). A slider's range is baked in when it is built, so both
-- Vertical Fill toggles must rebuild the page (RefreshPage(true)); the fast
-- RefreshPage() re-reads values only and left the old limits in place. Unlock
-- Mode's width floor follows the same rule.
--   lua .tools/tests/test_uf_vertical_fill_ranges.lua [MiniFrames] [SharedBars] [Unlock]
local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return (s:gsub("\r\n", "\n"))
end
local MINI = Read((arg and arg[1]) or "EllesmereUIOptions/UnitFrames_Options/MiniFrames_Options.lua")
local SHARED = Read((arg and arg[2]) or "EllesmereUIOptions/UnitFrames_Options/SharedBars_Options.lua")
local UNLOCK = Read((arg and arg[3]) or "EllesmereUIUnitFrames/EUI_UnitFrames_Unlock.lua")

local fails = 0
local function has(src, text, msg)
    if not src:find(text, 1, true) then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- 1. The ranges follow Vertical Fill (mini and boss frames, main frames).
has(MINI, "local vertFill = settingsTable.healthVerticalFill == true", "mini: no Vertical Fill read")
has(MINI, 'text="Bar Width", min=vertFill and 20 or 60, max=300', "mini: Bar Width floor does not follow Vertical Fill")
has(MINI, 'text="Health Bar Height", min=10, max=vertFill and 400 or 100', "mini: Health Bar Height cap does not follow Vertical Fill")
has(SHARED, 'local vertFill = SVal("healthVerticalFill", false) == true', "main: no Vertical Fill read")
has(SHARED, 'text="Health Bar Height", min=15, max=vertFill and 400 or 100', "main: Health Bar Height cap does not follow Vertical Fill")
has(SHARED, 'text="Bar Width", min=vertFill and 20 or 80, max=400', "main: Bar Width floor does not follow Vertical Fill")

-- 2. Both Vertical Fill toggles rebuild the page, so the new limits show at once.
has(MINI, "settingsTable.healthVerticalFill = v; ReloadAndUpdate(); EllesmereUI:RefreshPage(true)",
    "mini: the Vertical Fill toggle does not rebuild the page")
has(SHARED, 'SSet("healthVerticalFill", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage(true)',
    "main: the Vertical Fill toggle does not rebuild the page")

-- 3. Unlock Mode's width floor: 20 with Vertical Fill, 50 otherwise, both paths.
has(UNLOCK, "s.frameWidth = math.max(PP.Snap(w - adjPH), s.healthVerticalFill and 20 or 50)",
    "unlock: the portrait-adjusted width floor ignores Vertical Fill")
has(UNLOCK, "s.frameWidth = math.max(PP.Snap(w), s.healthVerticalFill and 20 or 50)",
    "unlock: the plain width floor ignores Vertical Fill")

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_uf_vertical_fill_ranges")
