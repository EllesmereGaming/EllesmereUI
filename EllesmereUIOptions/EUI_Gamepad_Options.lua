if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Gamepad_Options.lua -- Global Settings > Gamepad. The settings that
--  apply only while a controller is connected and WoW's gamepad mode is on:
--  which action bars hide, and whether our cast bars hide (Blizzard's gamepad
--  interface draws its own cast bar). Every value lives in its module's
--  profile (Action Bars bars[key].gamepadHideBar, Unit Frames
--  player.castbarGamepadHide, Resource Bars castBar.gamepadHide); this page
--  only reads and writes them and calls the module's apply entry. It
--  registers nothing: the Global Settings module dispatches its builder.
-------------------------------------------------------------------------------

local AB_FOLDER = "EllesmereUIActionBars"
local UF_FOLDER = "EllesmereUIUnitFrames"
local RB_FOLDER = "EllesmereUIResourceBars"

-------------------------------------------------------------------------------
--  Module access (nil while a module is not loaded)
-------------------------------------------------------------------------------

-- Action Bars module ns once its profile exists.
local function ABNS()
    local ns = EllesmereUI.ModuleNS(AB_FOLDER)
    local EAB = ns and ns.EAB
    if EAB and EAB.db then return ns end
    return nil
end

-- Unit Frames player unit settings.
local function UFPlayer()
    local ns = EllesmereUI.ModuleNS(UF_FOLDER)
    local db = ns and ns.db
    return db and db.profile.player
end

-- Resource Bars cast bar settings.
local function RBCast()
    if not EllesmereUI.ModuleNS(RB_FOLDER) then return nil end
    local db = _G._ERB_AceDB
    return db and db.profile.castBar
end

-------------------------------------------------------------------------------
--  Action bars checklist
-------------------------------------------------------------------------------

-- Every bar the runtime can hide, in the Action Bars dropdown order (the
-- visibility-only entries, such as the Micro Menu, Bag Bar and data bars,
-- never take the setting).
local function BarItems(ns)
    local items = {}
    local order, labels, visOnly = ns.BAR_DROPDOWN_ORDER, ns.BAR_DROPDOWN_VALUES, ns.VISIBILITY_ONLY
    for i = 1, #order do
        local key = order[i]
        if not visOnly[key] then
            items[#items + 1] = { key = key, label = labels[key] or key }
        end
    end
    return items
end

local function BarSettings(key)
    local ns = ABNS()
    return ns and ns.EAB.db.profile.bars[key]
end

local function BarHidden(key)
    local s = BarSettings(key)
    return (s and s.gamepadHideBar == true) or false
end

local function SetBarHidden(key, v)
    local s = BarSettings(key)
    if not s then return end
    s.gamepadHideBar = v and true or false
    local EAB = ABNS().EAB
    -- Controller verdict first: the Never map and the drivers read it.
    EAB._PadSync()
    EAB:RefreshRuntimeVisibility()
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._EUI_BuildGamepadPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Intro: sized host + single TOPLEFT point (the search geometry
    -- contract). Chrome only, so the search index pass skips it.
    if not EllesmereUI._prebuilding then
        local introHost = CreateFrame("Frame", nil, parent)
        PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 44)
        PP.Point(introHost, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 20)
        local intro = EllesmereUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
        intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
        intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
        intro:SetJustifyH("CENTER")
        intro:SetWordWrap(true)
        intro:SetText(EllesmereUI.L("Everything here applies only while a controller is connected and WoW's gamepad mode is on.") .. "\n"
            .. EllesmereUI.L("Mouse and keyboard play is unaffected."))
    end
    y = y - 48

    ---------------------------------------------------------------------------
    --  ACTION BARS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ACTION BARS", y);  y = y - h

    local abNS = ABNS()
    -- The checklist replaces this placeholder dropdown (DualRow only builds
    -- plain widgets); the placeholder keeps the label, its tooltip and the
    -- disabled state while Action Bars is not loaded.
    local barRow
    barRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Hide Action Bars",
          tooltip = "Checked bars hide while a controller is connected and gamepad mode is on, the way Visibility set to Never hides them.",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end,
          disabled = function() return not ABNS() end,
          disabledTooltip = "Action Bars" },
        BLANK());  y = y - h

    if abNS and not EllesmereUI._prebuilding then
        local rgn = barRow._leftRegion
        if rgn._control then rgn._control:Hide() end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 210, rgn:GetFrameLevel() + 2,
            BarItems(abNS), BarHidden, SetBarHidden)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

        -- Chrome only (no search entry), so the index pass skips it too.
        y = EllesmereUI.BuildNoteRow(parent, y, "Hidden bars still show in Quick Keybind mode so you can bind them.")
    elseif abNS then
        -- The index pass still steps past the note (BuildNoteRow's 34px row)
        -- so the rows below index at their live positions.
        y = y - 34
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  CAST BARS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CAST BARS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hide Unit Frames Cast Bar",
          tooltip = "Hides the Unit Frames player cast bar while a controller is connected and gamepad mode is on. Blizzard's gamepad interface shows its own.",
          getValue = function()
              local p = UFPlayer()
              return (p and p.castbarGamepadHide == true) or false
          end,
          setValue = function(v)
              local p = UFPlayer()
              if not p then return end
              p.castbarGamepadHide = v and true or false
              EllesmereUI.ModuleNS(UF_FOLDER).UF_ApplyGamepadCastbar()
          end,
          -- Our player cast bar exists only on the EllesmereUI player frame
          -- (a Blizzard or hidden frame source has none to hide).
          disabled = function()
              local p = UFPlayer()
              if not (p and p.showPlayerCastbar) then return true end
              return EllesmereUI.ModuleNS(UF_FOLDER).GetUnitFrameSource("player") ~= "eui"
          end,
          disabledTooltip = function()
              if not UFPlayer() then return "Unit Frames" end
              return "This option requires the Unit Frames player frame and its cast bar to be enabled"
          end },
        { type = "toggle", text = "Hide Resource Bars Cast Bar",
          tooltip = "Hides the Resource & Cast Bars cast bar while a controller is connected and gamepad mode is on. Blizzard's gamepad interface shows its own.",
          getValue = function()
              local cb = RBCast()
              return (cb and cb.gamepadHide == true) or false
          end,
          setValue = function(v)
              local cb = RBCast()
              if not cb then return end
              cb.gamepadHide = v and true or false
              EllesmereUI.ModuleNS(RB_FOLDER).RB_ApplyGamepadCastbar()
          end,
          disabled = function()
              local cb = RBCast()
              return not (cb and cb.enabled)
          end,
          disabledTooltip = function()
              if not RBCast() then return "Resource & Cast Bars" end
              return "This option requires the cast bar in Resource & Cast Bars to be enabled"
          end });  y = y - h

    -- Framework contract: return the positive total content height.
    return math.abs(y)
end
