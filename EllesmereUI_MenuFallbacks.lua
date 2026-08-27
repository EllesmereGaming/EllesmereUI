if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_MenuFallbacks.lua
--
--  Secure "View Houses" for the one unit menu we cannot open securely.
--
--  A raid/party member who is in another zone (a house owner hosting a
--  housewarming is ALWAYS elsewhere) trips the togglemenu classifier, and the
--  menu proxy's backstop (EllesmereUI_Kick.lua) re-opens the player menu from
--  Lua -- a TAINTED menu. Every protected item in it fails: Set Focus and
--  Follow throw ADDON_ACTION_FORBIDDEN, and Blizzard's "View Houses" runs
--  HouseListFrame:InitWithContextData tainted, which poisons the house list's
--  ScrollBox data for the rest of the session (every later Visit House click,
--  even from a secure menu, is blocked at C_Housing.VisitHouse).
--
--  Everything here applies to THAT menu only. Blizzard's Set Focus / Follow /
--  View Houses entries are greyed out so they cannot throw or poison, and a
--  "View Houses" button docked beside the menu opens our own house list. Each
--  row's Visit is a SecureActionButton WE own running the stock "visithouse"
--  secure action from string attributes set out of combat -- the same channel
--  an action bar's macrotext rides, read clean by the hardware click. Nothing
--  reaches a protected call from tainted execution, and Blizzard's panel is
--  never touched.
--
--  Visuals mirror the Blizzard-window skin engine (panel fill, inset fill,
--  border, flat buttons with a white hover, atlas close glyph, the
--  "blizzardSkin" font settings) so the dock and list read as one of our
--  skinned windows. The engine itself is private to the BlizzardSkin child
--  addon, so its palette is reproduced here rather than called.
--
--  Zero cost until the backstop fires: the Menu.ModifyMenu callbacks return
--  on their first line unless EllesmereUI._menuReopenUnit is set (only during
--  the backstop's re-open call), the button and list are built on first use,
--  and their events are registered only while shown.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end
if not (Menu and Menu.ModifyMenu and Menu.GetManager and MenuUtil and MenuUtil.GetElementText) then return end

local HOUSING_OK = C_Housing and C_Housing.GetOthersOwnedHouses and C_Housing.VisitHouse

-------------------------------------------------------------------------------
--  Theme (the window skin engine's palette)
-------------------------------------------------------------------------------
local T = {}
local function ResolveTheme()
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    T.accR, T.accG, T.accB = EG.r, EG.g, EG.b
    T.bgR, T.bgG, T.bgB, T.bgA = 0.08, 0.08, 0.08, 0.92
    T.insetR, T.insetG, T.insetB, T.insetA = 0.04, 0.04, 0.04, 0.85
    T.brdR, T.brdG, T.brdB, T.brdA = 0.2, 0.2, 0.2, 1
    T.fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin"))
        or EllesmereUI._font or STANDARD_TEXT_FONT
    T.fontFlag = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("blizzardSkin")) or ""
    T.fontShadow = (T.fontFlag == "")
        and (not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("blizzardSkin"))
end

local function SolidTex(parent, layer, r, g, b, a, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- BORDER/-7 strips demoted to the frame's own level, exactly as the window
-- engine draws its borders (content on the frame renders above them).
local function AddBorder(frame)
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    if not (PP and PP.CreateBorder) then return end
    local c = PP.CreateBorder(frame, T.brdR, T.brdG, T.brdB, T.brdA, 1, "BORDER", -7)
    if c and c.SetFrameLevel then c:SetFrameLevel(frame:GetFrameLevel()) end
end

local function MakeText(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, T.fontShadow) end
    fs:SetFont(T.fontPath, size, T.fontFlag or "")
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    return fs
end

local function Panel(frame, inset)
    local r, g, b, a = T.bgR, T.bgG, T.bgB, T.bgA
    if inset then r, g, b, a = T.insetR, T.insetG, T.insetB, T.insetA end
    local bg = SolidTex(frame, "BACKGROUND", r, g, b, a, -6)
    bg:SetAllPoints(frame)
    AddBorder(frame)
    return bg
end

-- Flat dark block with a subtle white hover and a white label; secure = a
-- SecureActionButton whose attributes the caller sets.
local function MakeButton(parent, name, label, w, h, secure)
    local b = CreateFrame("Button", name, parent, secure and "SecureActionButtonTemplate" or nil)
    b:SetSize(w, h)
    b:RegisterForClicks("AnyUp")
    if secure then b:SetAttribute("useOnKeyDown", false) end
    local fill = SolidTex(b, "BACKGROUND", T.bgR, T.bgG, T.bgB, T.bgA)
    fill:SetAllPoints(b)
    AddBorder(b)
    local hover = SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(b)
    local t = MakeText(b, 12)
    t:SetPoint("CENTER")
    t:SetText(label)
    b:SetFontString(t)
    return b
end

local function MakeCloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    local x = btn:CreateTexture(nil, "OVERLAY")
    x:SetAtlas("uitools-icon-close")
    x:SetSize(14, 14)
    x:SetPoint("CENTER")
    x:SetVertexColor(1, 1, 1, 0.75)
    btn:SetScript("OnEnter", function() x:SetVertexColor(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function() x:SetVertexColor(1, 1, 1, 0.75) end)
    return btn
end

local OpenHousesFor  -- defined with the house list below

-------------------------------------------------------------------------------
--  "View Houses" button, docked to the reopened menu
-------------------------------------------------------------------------------
local dock
local dockEv = CreateFrame("Frame")
local hookedMenus = setmetatable({}, { __mode = "k" })
local reopenContext  -- the reopened menu's contextData, captured by the modifier

local function BuildDock()
    ResolveTheme()
    local d = CreateFrame("Frame", "EllesmereUI_MenuFallbackDock", UIParent)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetSize(124, 34)
    d:Hide()
    Panel(d)

    d.houses = MakeButton(d, nil, UNIT_VIEW_HOUSES or EllesmereUI.L("View Houses"), 112, 22, false)
    d.houses:SetPoint("CENTER")
    -- The menu closes on any GLOBAL_MOUSE_DOWN outside it UNLESS the frame
    -- under the cursor answers HandlesGlobalMouseEvent (Menu.lua's opt-out for
    -- attached UI). Claim our clicks so the menu stays until OnClick, which
    -- then closes it itself.
    d.houses.HandlesGlobalMouseEvent = function() return true end
    d.houses:SetScript("OnClick", function()
        local menu = d.menu
        d:Hide()
        if menu then
            local mgr = Menu.GetManager()
            if mgr and mgr.CloseMenu then mgr:CloseMenu(menu) end
        end
        OpenHousesFor(reopenContext)
    end)

    d:SetScript("OnHide", function(self)
        self.menu = nil
        dockEv:UnregisterAllEvents()
    end)
    d:SetScript("OnShow", function()
        dockEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    end)
    dockEv:SetScript("OnEvent", function() d:Hide() end)
    dock = d
    return d
end

-- Called by the backstop right after its (tainted) re-open, while that menu is
-- the open one.
function EllesmereUI._ShowReopenedMenuExtras(unit)
    if not HOUSING_OK or not reopenContext or reopenContext.unit ~= unit then return end
    local mgr = Menu.GetManager()
    local menu = mgr and mgr.GetOpenMenu and mgr:GetOpenMenu()
    if not menu or (menu.IsForbidden and menu:IsForbidden()) then return end
    local d = dock or BuildDock()
    d.menu = menu
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", menu, "TOPRIGHT", 2, 0)
    -- Close with the menu it is docked to (menu frames are pooled: hook once
    -- per frame, act only when the dock is anchored to that frame).
    if not hookedMenus[menu] then
        hookedMenus[menu] = true
        menu:HookScript("OnHide", function(self)
            if dock and dock.menu == self then dock:Hide() end
        end)
    end
    d:Show()
end

-------------------------------------------------------------------------------
--  House list (built once, on first use)
-------------------------------------------------------------------------------
local MAX_ROWS = 6
local ROW_H = 42
local ROW_GAP = 4
local FRAME_W = 440
local HEADER_H = 32

local listFrame, rows, statusText, titleText
local pendingHouses      -- last received house list, re-applied after combat
local listEv = CreateFrame("Frame")

local function BuildList()
    ResolveTheme()
    local f = CreateFrame("Frame", "EllesmereUI_HouseVisitFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetScale((EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1)
    f:SetWidth(FRAME_W)
    f:SetHeight(HEADER_H + 10 + MAX_ROWS * (ROW_H + ROW_GAP) + 6)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    Panel(f)

    -- Header band (inset fill) with the title and the close glyph, like a
    -- skinned window's title bar.
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    local hbg = SolidTex(header, "BACKGROUND", T.insetR, T.insetG, T.insetB, T.insetA, -5)
    hbg:SetAllPoints(header)
    local hline = SolidTex(header, "BORDER", T.brdR, T.brdG, T.brdB, T.brdA)
    hline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    hline:SetHeight(1)

    titleText = MakeText(header, 14)
    titleText:SetPoint("LEFT", header, "LEFT", 12, 0)
    titleText:SetPoint("RIGHT", header, "RIGHT", -34, 0)
    titleText:SetJustifyH("LEFT")

    local close = MakeCloseButton(header)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    statusText = MakeText(f, 12, 0.7, 0.7, 0.7)
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(HEADER_H + 12))
    statusText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -(HEADER_H + 12))
    statusText:SetJustifyH("LEFT")

    rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(ROW_H)
        local y = -(HEADER_H + 10 + (i - 1) * (ROW_H + ROW_GAP))
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y)
        Panel(row, true)

        row.name = MakeText(row, 13)
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -7)
        row.name:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.name:SetJustifyH("LEFT")

        row.info = MakeText(row, 11, 0.65, 0.65, 0.65)
        row.info:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 7)
        row.info:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.info:SetJustifyH("LEFT")

        -- The teleport: a stock secure action, attributes = plain strings.
        local visit = MakeButton(row, "EllesmereUI_HouseVisit" .. i, EllesmereUI.L("Visit"), 80, 24, true)
        visit:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        visit:SetAttribute("type", "visithouse")
        row.visit = visit

        row:Hide()
        rows[i] = row
    end

    if EllesmereUI.RegisterEscapeClose then EllesmereUI.RegisterEscapeClose(f) end
    listFrame = f
    return f
end

local function ClearRows()
    for i = 1, MAX_ROWS do rows[i]:Hide() end
end

local function ApplyHouses(houses)
    ClearRows()
    if not houses or #houses == 0 then
        statusText:SetText(EllesmereUI.L("No houses found."))
        statusText:Show()
        return
    end
    -- Attribute writes are refused in combat; keep the list and re-apply on
    -- PLAYER_REGEN_ENABLED (registered while shown).
    if InCombatLockdown() then
        statusText:SetText(EllesmereUI.L("Leave combat to enable visiting."))
        statusText:Show()
        return
    end
    statusText:Hide()
    for i = 1, math.min(#houses, MAX_ROWS) do
        local h = houses[i]
        local row = rows[i]
        row.name:SetText(h.houseName or EllesmereUI.L("House"))
        local where = h.neighborhoodName or ""
        if h.plotID then
            where = where .. (where ~= "" and "  -  " or "") .. string.format(HOUSING_PLOT_NUMBER or "Plot %d", h.plotID)
        end
        if h.ownerName and h.ownerName ~= "" then
            where = where .. (where ~= "" and "  -  " or "") .. h.ownerName
        end
        row.info:SetText(where)
        local v = row.visit
        v:SetAttribute("house-neighborhood-guid", h.neighborhoodGUID)
        v:SetAttribute("house-guid", h.houseGUID)
        v:SetAttribute("house-plot-id", h.plotID and tostring(h.plotID) or nil)
        local ok = h.neighborhoodGUID and h.houseGUID and h.plotID
        v:SetAlpha(ok and 1 or 0.3)
        v:EnableMouse(ok and true or false)
        row:Show()
    end
end

listEv:SetScript("OnEvent", function(self, event, arg1)
    if event == "VIEW_HOUSES_LIST_RECIEVED" then
        pendingHouses = arg1
        ApplyHouses(arg1)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingHouses then ApplyHouses(pendingHouses) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A successful visit loads a new map; the list has done its job.
        if listFrame then listFrame:Hide() end
    end
end)

local function ListOnShow()
    listEv:RegisterEvent("VIEW_HOUSES_LIST_RECIEVED")
    listEv:RegisterEvent("PLAYER_REGEN_ENABLED")
    listEv:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function ListOnHide()
    listEv:UnregisterAllEvents()
    pendingHouses = nil
end

-- Request the list for the menu's player.
function OpenHousesFor(contextData)
    if not contextData then return end
    local f = listFrame
    if not f then
        f = BuildList()
        f:SetScript("OnShow", ListOnShow)
        f:SetScript("OnHide", ListOnHide)
    end
    local unit = contextData.unit
    local name = (UnitPopupSharedUtil and UnitPopupSharedUtil.GetFullPlayerName
        and UnitPopupSharedUtil.GetFullPlayerName(contextData))
        or (unit and UnitName(unit)) or contextData.name or UNKNOWN
    local guid = (unit and UnitGUID(unit))
        or (UnitPopupSharedUtil and UnitPopupSharedUtil.GetGUID and UnitPopupSharedUtil.GetGUID(contextData))
    if issecretvalue and (issecretvalue(guid) or issecretvalue(name)) then return end
    if not guid then return end

    pendingHouses = nil
    titleText:SetText(string.format(VIEW_HOUSES_TITLE or "%s's Houses", name))
    ClearRows()
    statusText:SetText(EllesmereUI.L("Loading houses..."))
    statusText:Show()
    f:Show()
    C_Housing.GetOthersOwnedHouses(guid, contextData.bnetIDAccount, not not contextData.isGuildMember)
end

-------------------------------------------------------------------------------
--  Menu modification: only the backstop's re-opened menu
-------------------------------------------------------------------------------
local function ModifyReopenedMenu(owner, rootDescription, contextData)
    if not EllesmereUI._menuReopenUnit then return end
    if not contextData or contextData.unit ~= EllesmereUI._menuReopenUnit then return end
    reopenContext = contextData
    local viewHouses = UNIT_VIEW_HOUSES or "View Houses"
    local setFocus = SET_FOCUS or "Set Focus"
    local follow = FOLLOW or "Follow"
    for _, d in rootDescription:EnumerateElementDescriptions() do
        local text = MenuUtil.GetElementText(d)
        if d.SetEnabled and (text == setFocus or text == follow or (HOUSING_OK and text == viewHouses)) then
            -- Protected from a tainted menu: throws (focus/follow) or poisons
            -- HouseListFrame for the session (View Houses; the docked button
            -- replaces it).
            d:SetEnabled(false)
        end
    end
end

Menu.ModifyMenu("MENU_UNIT_RAID_PLAYER", ModifyReopenedMenu)
Menu.ModifyMenu("MENU_UNIT_PARTY", ModifyReopenedMenu)
