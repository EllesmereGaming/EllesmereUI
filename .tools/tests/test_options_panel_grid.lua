-- Stub harness: which pixel grid an options element snaps to.
-- The options panel runs on its own grid (EllesmereUI.PanelPP: one unit per pixel times the Window
-- Scale); the game grid (EllesmereUI.PP) is for frames at UIParent's scale. An element built inside
-- the panel on the game grid lands on half pixels when the UI Scale does not match the screen.
--   * BuildCheckboxControl snaps to the panel grid unless its caller hands it another one;
--   * the bank tab settings dialog, which lives outside the panel, hands it the game grid;
--   * the page scopes that anchor inline swatches, keybind buttons and warning lines read the
--     panel grid.
-- The real checkbox builder is cut out of the widget base file and run over stubs.
--   lua .tools/tests/test_options_panel_grid.lua        (from the repository root)
local function Read(name)
    local f = assert(io.open(name, "rb"))
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

-------------------------------------------------------------------------------
-- 1. the checkbox builder
-------------------------------------------------------------------------------
do
    local W = Read("EllesmereUIOptions/EllesmereUI_Widgets.lua")
    check(W:find("\nlocal PP = EllesmereUI.PanelPP\n", 1, true) ~= nil, "the widget base file's own grid is not the panel grid")
    local a = assert(W:find("local function BuildCheckboxControl(parent, frameLevel, pp)", 1, true), "the checkbox builder not found")
    local b = assert(W:find("\nend\n", a, true), "the end of the checkbox builder not found")
    local function Grid(name)
        local g = { name = name, calls = {} }
        function g.Size(obj, w, h) g.calls[#g.calls + 1] = { "Size", obj, w, h } end
        function g.SetInside(obj, rel, x, y) g.calls[#g.calls + 1] = { "SetInside", obj, rel, x, y } end
        return g
    end
    local panel, game = Grid("panel"), Grid("game")
    local function Tex()
        local t = {}
        function t:SetAllPoints() end
        function t:SetColorTexture() end
        function t:Show() end
        function t:Hide() end
        return t
    end
    local env = setmetatable({
        CreateFrame = function() return { SetFrameLevel = function() end } end,
        EllesmereUI = { RoundBody = function() end },
    }, { __index = _G })
    local chunk = assert(loadstring("local PP, SolidTex, DisablePixelSnap, MakeRoundedBorder, CB, ELLESMERE_GREEN, BORDER_R, BORDER_G, BORDER_B = ...\n"
        .. W:sub(a, b + #"\nend") .. "\nreturn BuildCheckboxControl", "=Widgets.lua (the checkbox builder)"))
    setfenv(chunk, env)
    local Build = chunk(panel, Tex, function() end, function() return { SetColor = function() end } end,
        { BOX_R = 0, BOX_G = 0, BOX_B = 0, BRD_A = 1, ACT_BRD_A = 1 }, { r = 0, g = 1, b = 0 }, 1, 1, 1)
    -- no grid handed in: the panel's
    local box, mark = Build({}, 5)
    check(#panel.calls == 2 and #game.calls == 0, "a checkbox built with no grid does not snap to the panel grid (" .. #panel.calls .. " panel, " .. #game.calls .. " game calls)")
    check(panel.calls[1] and panel.calls[1][1] == "Size" and panel.calls[1][2] == box and panel.calls[1][3] == 18 and panel.calls[1][4] == 18,
        "the box is not sized 18 x 18 on the grid")
    check(panel.calls[2] and panel.calls[2][1] == "SetInside" and panel.calls[2][2] == mark and panel.calls[2][3] == box
        and panel.calls[2][4] == 2 and panel.calls[2][5] == 2, "the fill is not set 2 inside the box on the grid")
    -- a grid handed in (a frame outside the panel): that one, for the box and for the fill
    panel.calls = {}
    Build({}, 5, game)
    check(#game.calls == 2 and #panel.calls == 0, "a checkbox handed the game grid still snaps to the panel grid")
    check(game.calls[1] and game.calls[1][1] == "Size" and game.calls[2] and game.calls[2][1] == "SetInside", "the handed grid does not size the box and seat the fill")
end

-------------------------------------------------------------------------------
-- 2. the one caller outside the panel hands the game grid
-------------------------------------------------------------------------------
do
    local B = Read("EllesmereUIBags/EllesmereUIBags_Bank.lua")
    check(B:find("EUI.BuildCheckboxControl(btn, assignToTabFrame:GetFrameLevel() + 2, EUI.PP)", 1, true) ~= nil,
        "the bank tab settings dialog (on UIParent, at the bank's scale) does not hand the checkbox builder the game grid")
end

-------------------------------------------------------------------------------
-- 3. page scopes that anchor panel pieces read the panel grid
-------------------------------------------------------------------------------
do
    -- { file, the line that picks the grid for the scope, what it anchors }
    local SCOPES = {
        { "EllesmereUIOptions/EUI_Chat_Options.lua", "        local PP = EllesmereUI.PanelPP\n", "the Chat page's inline swatches" },
        { "EllesmereUIOptions/EUI_BlizzardSkin_Options.lua", "        local W  = EllesmereUI.Widgets\n        local PP = EllesmereUI.PanelPP\n        local y  = yOffset\n",
          "the Chat Bubbles page's warning frame" },
        { "EllesmereUIOptions/EUI_MythicTimer_KickTracker_Options.lua", "        EllesmereUI.PanelPP.Point(warn, \"TOPLEFT\", parent, \"TOPLEFT\", pad, y - 10)\n",
          "the Kick Tracker page's warning line" },
        { "EllesmereUIOptions/EUI_QuestTracker_Options.lua", "EllesmereUI.PanelPP", "the Quest Tracker page's swatches and keybind button" },
        { "EllesmereUIOptions/EUI_MythicTimer_Options.lua", "EllesmereUI.PanelPP", "the Mythic+ Timer page's swatches" },
    }
    for _, sc in ipairs(SCOPES) do
        check(Read(sc[1]):find(sc[2], 1, true) ~= nil, sc[3] .. " are not on the panel grid (" .. sc[1] .. ")")
    end
    -- the Damage Meters keybind button takes the builder's default (the panel grid), not a grid of its own
    local D = Read("EllesmereUIOptions/EUI_DamageMeters_Options.lua")
    check(D:find("w = 120, h = 26, tooltip = tooltip,", 1, true) ~= nil and D:find("pp = EllesmereUI.PP", 1, true) == nil,
        "the Damage Meters keybind button is handed the game grid")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_options_panel_grid (%d checks)"):format(count))
