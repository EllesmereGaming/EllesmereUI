if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_LootRolls_Options.lua
--  Builds the "Loot" page inside the Quality of Life module: a live preview of
--  the Loot Roll Frame in the content header, then its settings. Position and
--  size are also set in Unlock Mode (registered in EllesmereUIQoL_LootRolls.lua).
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local LR = EllesmereUI._LootRolls
    if not LR then return 0 end
    local building = true
    local view = LR.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._EUI_LootRollsHeaderBuilder = HeaderBuilder

-- The eye's on-screen preview ends when the window closes; another QoL page
-- and another module end it through EUI_QoL_Options.lua.
EllesmereUI:RegisterOnHide(function()
    local LR = EllesmereUI._LootRolls
    if LR and LR.SamplesShown() then LR.ShowSamples(false) end
end)

-- Eye button left of the Enable toggle: shows the sample rolls in the real
-- frame, outside the options window.
local function AddPreviewEye(rgn, LR, off)
    if EllesmereUI._prebuilding then return end
    local VISIBLE, INVISIBLE = EllesmereUI.EYE_VISIBLE_ICON, EllesmereUI.EYE_INVISIBLE_ICON
    local eye = CreateFrame("Button", nil, rgn)
    eye:SetSize(26, 26)
    eye:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
    eye:SetFrameLevel(rgn:GetFrameLevel() + 5)
    rgn._lastInline = eye
    local tex = eye:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    local function Refresh()
        local disabled = off()
        tex:SetTexture(LR.SamplesShown() and INVISIBLE or VISIBLE)
        EllesmereUI.SetGlyphAlpha(eye, disabled and 0.15 or 0.4)
    end
    eye:SetScript("OnShow", Refresh)
    eye:SetScript("OnClick", function()
        if off() then return end
        LR.ShowSamples(not LR.SamplesShown())
        Refresh()
        EllesmereUI.SetGlyphAlpha(eye, 0.7)
    end)
    eye:SetScript("OnEnter", function(self)
        if off() then
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Loot Roll Frame"))
            return
        end
        EllesmereUI.SetGlyphAlpha(self, 0.7)
        EllesmereUI.ShowWidgetTooltip(self, LR.SamplesShown() and "Hide preview" or "Preview on screen")
    end)
    eye:SetScript("OnLeave", function()
        EllesmereUI.HideWidgetTooltip()
        Refresh()
    end)
    Refresh()
    EllesmereUI.RegisterWidgetRefresh(Refresh)
end

local GROW = { DOWN = "Down", UP = "Up" }
local GROW_ORDER = { "DOWN", "UP" }
local TIMER_POS = { none = "None", icon = "On Icon", barLeft = "Bar Left", barRight = "Bar Right" }
local TIMER_POS_ORDER = { "none", "icon", "barLeft", "barRight" }
local TIMER_FORMAT = { mmss = "Minutes and Seconds (1:02)", sec = "Seconds (62)" }
local TIMER_FORMAT_ORDER = { "mmss", "sec" }
local TIP_GROW = { rightUp = "Right and Up", rightDown = "Right and Down",
    leftUp = "Left and Up", leftDown = "Left and Down" }
local TIP_GROW_ORDER = { "rightUp", "rightDown", "leftUp", "leftDown" }
local WINNER_POS = { left = "Left", center = "Center", right = "Right" }
local WINNER_POS_ORDER = { "left", "center", "right" }
-- Whole sentences per client, so each is one translation key (WoW Forever has no transmog
-- roll, and its gamepad style has its own roll frame).
local TIP_ROLL_LIST = EllesmereUI.IS_FOREVER
    and "Hovering a roll's bar lists everyone who can roll, what they picked and what they rolled, Need first, then Greed and Pass, with those yet to pick last. Hover the icon for the item."
    or "Hovering a roll's bar lists everyone who can roll, what they picked and what they rolled, Need first, then Greed, Transmog and Pass, with those yet to pick last. Hover the icon for the item."
local TIP_ENABLE = EllesmereUI.IS_FOREVER
    and "Shows group loot rolls as one compact list in place of Blizzard's roll popups. Turning it off takes a reload. It stands down under the Gamepad interface style, which has its own roll frame."
    or "Shows group loot rolls as one compact list in place of Blizzard's roll popups. Turning it off takes a reload."

_G._EUI_BuildLootPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local LR = EllesmereUI._LootRolls
    local y = yOffset
    local _, h, hdr
    if not LR then return 0 end
    parent._showRowDivider = true

    EllesmereUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not LR.Get("enabled")
    end
    -- Binds cfg to setting key; apply runs after a change. Greyed out while
    -- the frame is off.
    local function Bind(cfg, key, apply)
        cfg.disabled, cfg.disabledTooltip = off, "Loot Roll Frame"
        cfg.getValue = function() return LR.Get(key) end
        cfg.setValue = function(v)
            local p = LR.Cfg()
            if not p then return end
            p[key] = v
            if apply then apply() end
        end
        return cfg
    end
    local function Slider(key, text, min, max, step, tooltip)
        return Bind({ type = "slider", text = text, tooltip = tooltip, min = min, max = max, step = step or 1 },
            key, LR.ApplyStyle)
    end
    -- Custom | Accent | Quality swatches for a color mode key; the active one
    -- is bright. A click on the dim Custom swatch selects it, the next opens
    -- the picker (the suite's multiSwatch convention).
    local function ColorSwatches(modeKey, colorKey)
        local function SetMode(mode)
            local p = LR.Cfg()
            if not p then return end
            p[modeKey] = mode
            LR.ApplyStyle()
            EllesmereUI:RefreshPage()
        end
        local function Bright(mode)
            return function() return LR.Get(modeKey) == mode and 1 or 0.3 end
        end
        return {
            { tooltip = "Custom Color", hasAlpha = false,
              getValue = function()
                  local c = LR.Get(colorKey)
                  return c.r, c.g, c.b, 1
              end,
              setValue = function(r, g, b)
                  local p = LR.Cfg()
                  if not p then return end
                  p[colorKey] = { r = r, g = g, b = b }
                  p[modeKey] = "custom"
                  LR.ApplyStyle()
              end,
              onClick = function(self)
                  if LR.Get(modeKey) ~= "custom" then SetMode("custom"); return end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = Bright("custom") },
            { tooltip = "Accent Color", hasAlpha = false,
              getValue = function() return EllesmereUI.GetAccentColor() end,
              setValue = function() end,
              onClick = function() SetMode("accent") end,
              refreshAlpha = Bright("accent") },
            { tooltip = "Item Quality Color", hasAlpha = false,
              getValue = function()
                  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[4]
                  if c then return c.r, c.g, c.b end
                  return 0.64, 0.21, 0.93
              end,
              setValue = function() end,
              onClick = function() SetMode("quality") end,
              refreshAlpha = Bright("quality") },
        }
    end
    -- The Custom | Accent | Quality swatches inline on a row half, left of its
    -- control (and of its three dots, when those are built first). The row's
    -- tooltip says what they color.
    local function Swatches(rgn, modeKey, colorKey, disabled, disabledTooltip)
        EllesmereUI.BuildInlineSwatches(rgn, ColorSwatches(modeKey, colorKey), {
            disabled = disabled or off, disabledTooltip = disabledTooltip or "Loot Roll Frame" })
    end

    -- A three-dot popup row bound to a setting key, like Bind.
    local function CogRow(row, key, apply)
        row.get = function() return LR.Get(key) end
        row.set = function(v)
            local p = LR.Cfg()
            if not p then return end
            p[key] = v
            local fn = apply or LR.ApplyStyle
            fn()
        end
        return row
    end
    -- The popup's options; disabled locks it (default: while the frame is off).
    local function CogOpts(title, rows, disabled, disabledTooltip)
        return { title = title, minWidth = 300, rows = rows, gap = 9,
                 disabled = disabled or off, disabledTooltip = disabledTooltip or "Loot Roll Frame" }
    end
    -- A setting other rows grey out by: the page refreshes after a change.
    local function Restyle()
        LR.ApplyStyle()
        EllesmereUI:RefreshPage()
    end

    -- Width and Icon Size also size the Unlock Mode mover.
    local function Resized()
        LR.ApplyStyle()
        if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
            EllesmereUI.RepositionBarToMover("EUI_LootRolls")
        end
    end

    ---------------------------------------------------------------------------
    --  LOOT ROLLS
    ---------------------------------------------------------------------------
    hdr, h = W:SectionHeader(parent, "LOOT ROLLS", y);  y = y - h
    EllesmereUI.BuildSectionUnlockJump(hdr, { key = "EUI_LootRolls", disabled = off,
        disabledTooltip = "Loot Roll Frame" })

    local enableRow
    enableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Loot Roll Frame",
          tooltip = TIP_ENABLE,
          getValue = function() return not off() end,
          setValue = function(v)
              local p = LR.Cfg()
              if not p then return end
              p.enabled = v
              LR.Apply()
              EllesmereUI:RefreshPage()
              if not v and LR.Suppressed() then
                  EllesmereUI:ShowConfirmPopup({
                      title = "Reload Required",
                      message = "Blizzard's loot roll popups come back after a reload. Until then, rolls keep showing in the Loot Roll Frame.",
                      confirmText = "Reload Now",
                      cancelText = "Later",
                      reload = true,
                  })
              end
          end },
        Bind({ type = "dropdown", text = "Grow Direction", values = GROW, order = GROW_ORDER,
               tooltip = "Which way new rolls stack from the frame's position." }, "grow", LR.ApplyStyle)
    );  y = y - h
    AddPreviewEye(enableRow._leftRegion, LR, off)

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    local row
    row, h = W:DualRow(parent, y,
        Bind({ type = "slider", text = "Width", min = 200, max = 800, step = 10 }, "width", Resized),
        Bind({ type = "slider", text = "Icon Size", min = 24, max = 64, step = 1,
               tooltip = "Size of each item icon. Each row is as tall as its icon. The swatches color the icon border." },
            "iconSize", Resized)
    );  y = y - h
    EllesmereUI.BuildInlineCog(row._rightRegion, CogOpts("Icon Settings", {
        CogRow({ type = "toggle", label = "Zoom Icons", tooltip = "Crops the edges of item icons." }, "iconZoom"),
        CogRow({ type = "toggle", label = "Show Icon Border", tooltip = "Draws a border around each item icon." },
            "iconBorder", Restyle),
        CogRow({ type = "toggle", label = "Show Item Level", tooltip = "Shows the item level on the icon of gear." },
            "showIlvl"),
    }))
    Swatches(row._rightRegion, "iconBorderColorMode", "iconBorderColor",
        function() return off() or not LR.Get("iconBorder") end, "Show Icon Border")

    row, h = W:DualRow(parent, y,
        Slider("spacing", "Spacing", 0, 20, 1, "Space between rows."),
        Slider("textSize", "Text Size", 8, 24, 1, "Size of the item names. The swatches color them.")
    );  y = y - h
    Swatches(row._rightRegion, "nameColorMode", "nameColor")

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- The three dots first: the swatches then land left of them.
    local function noTimer()
        return off() or LR.Get("timerPos") == "none"
    end
    local _, textureValues, textureOrder = EllesmereUI.BuildBarTextureTables(true)
    row, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Bar Texture", values = textureValues, order = textureOrder,
               tooltip = "The timer bar's texture. The swatches color it." }, "barTexture", LR.ApplyStyle),
        Bind({ type = "dropdown", text = "Timer Position", values = TIMER_POS, order = TIMER_POS_ORDER,
               tooltip = "Where the time left to roll shows on each row. The swatches color it." },
            "timerPos", Restyle)
    );  y = y - h
    EllesmereUI.BuildInlineCog(row._leftRegion, CogOpts("Bar Settings", {
        CogRow({ type = "slider", label = "Bar Height", min = 2, max = 40, step = 1,
                 tooltip = "Height of the timer bar. It stays short enough to leave room for the roll buttons above it." },
            "barHeight"),
        CogRow({ type = "toggle", label = "Show Bar Border", tooltip = "Draws a border around each timer bar." },
            "barBorder"),
    }))
    Swatches(row._leftRegion, "barColorMode", "barColor")
    EllesmereUI.BuildInlineCog(row._rightRegion, CogOpts("Timer Settings", {
        CogRow({ type = "dropdown", label = "Timer Format", values = TIMER_FORMAT, order = TIMER_FORMAT_ORDER },
            "timerFormat"),
        CogRow({ type = "slider", label = "Timer Size", min = 8, max = 24, step = 1 }, "timerSize"),
    }, noTimer, "Timer Position"))
    Swatches(row._rightRegion, "timerColorMode", "timerColor", noTimer, "Timer Position")

    row, h = W:DualRow(parent, y,
        Bind({ type = "toggle", text = "Show BoP", tooltip = "Labels items that bind on pickup. The swatches color the label." },
            "showBop", Restyle),
        Bind({ type = "toggle", text = "Show BoE", tooltip = "Labels items that bind on equip. The swatches color the label." },
            "showBoe", Restyle)
    );  y = y - h
    Swatches(row._leftRegion, "bopColorMode", "bopColor",
        function() return off() or not LR.Get("showBop") end, "Show BoP")
    Swatches(row._rightRegion, "boeColorMode", "boeColor",
        function() return off() or not LR.Get("showBoe") end, "Show BoE")

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  ROLL RESULTS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ROLL RESULTS", y);  y = y - h

    -- These also decide whether the loot history is listened to.
    local function Reapply()
        LR.Apply()
        EllesmereUI:RefreshPage()
    end
    row, h = W:DualRow(parent, y,
        Bind({ type = "toggle", text = "Show Winner",
               tooltip = "When a roll ends, shows who won it and their roll on its bar." }, "showWinner", Reapply),
        Bind({ type = "toggle", text = "Show Roll List",
               tooltip = TIP_ROLL_LIST },
               "showRollList", Reapply)
    );  y = y - h
    EllesmereUI.BuildInlineCog(row._leftRegion, CogOpts("Winner Settings", {
        CogRow({ type = "dropdown", label = "Position", values = WINNER_POS, order = WINNER_POS_ORDER,
                 tooltip = "Where the winner shows on the bar." }, "winnerPos"),
        CogRow({ type = "slider", label = "Size", min = 8, max = 24, step = 1,
                 tooltip = "Size of the winner's text and the icon of their pick." }, "winnerSize"),
    }, function() return off() or not LR.Get("showWinner") end, "Show Winner"))
    EllesmereUI.BuildInlineCog(row._rightRegion, CogOpts("Roll List Settings", {
        CogRow({ type = "slider", label = "Size", min = 8, max = 24, step = 1,
                 tooltip = "Size of the names and rolls in the roll list. Its icons size with it." }, "rollListSize"),
        CogRow({ type = "dropdown", label = "Growth", values = TIP_GROW, order = TIP_GROW_ORDER,
                 tooltip = "Which way the roll list opens from the cursor. It follows the cursor and stays on screen." },
            "tipGrow"),
    }, function() return off() or not LR.Get("showRollList") end, "Show Roll List"))

    local function noResults()
        return off() or not (LR.Get("showWinner") or LR.Get("showRollList"))
    end
    local delay = Bind({ type = "slider", text = "Result Delay", min = 1, max = 30, step = 1,
        tooltip = "Seconds a finished roll stays to show its result. Hovering it keeps it up." }, "resultDelay")
    delay.disabled, delay.disabledTooltip = noResults, "Show Winner or Show Roll List"
    _, h = W:DualRow(parent, y,
        Bind({ type = "toggle", text = "Show Roll Counts",
               tooltip = "Shows on each roll button how many players have picked it so far." },
            "showCounts", Reapply),
        delay
    );  y = y - h

    return math.abs(y)
end
