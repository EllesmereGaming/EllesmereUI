-------------------------------------------------------------------------------
--  EUI_QoL_Shifter_Options.lua
--  Builds the "Shifter" page inside the Quality of Life module.
-------------------------------------------------------------------------------

-- "CharacterFrame" -> "Character", "AuctionHouseFrame" -> "Auction House", etc.
local function PrettifyName(name)
    local pretty = name:gsub("Frame$", "")
    pretty = pretty:gsub("(%l)(%u)", "%1 %2")
                    :gsub("(%u)(%u%l)", "%1 %2")
    return pretty
end

_G._EUI_BuildShifterPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    -- Info text (top of page, matching bags pattern)
    do
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath())
            or "Fonts\\FRIZQT__.TTF"
        local infoFrame = CreateFrame("Frame", nil, parent)
        infoFrame:SetSize(parent:GetWidth(), 34)
        infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 10)
        infoFrame._isSpacer = true
        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
        line1:SetFont(fontPath, 15, "")
        line1:SetTextColor(1, 1, 1, 0.75)
        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
        line1:SetJustifyH("CENTER")
        line1:SetText(EllesmereUI.L("Shift + Left-Click Drag to permanently save a panel's position."))
        local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
        line2:SetFont(fontPath, 15, "")
        line2:SetTextColor(1, 1, 1, 0.75)
        line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
        line2:SetJustifyH("CENTER")
        line2:SetText(EllesmereUI.L("Ctrl + Left-Click Drag for a temporary move that resets when the panel closes."))
        local line3 = infoFrame:CreateFontString(nil, "OVERLAY")
        line3:SetFont(fontPath, 15, "")
        line3:SetTextColor(1, 1, 1, 0.75)
        line3:SetPoint("TOP", line2, "BOTTOM", 0, -2)
        line3:SetJustifyH("CENTER")
        line3:SetText(EllesmereUI.L("Shift + Scroll to permanently zoom a panel. Ctrl + Scroll for a temporary zoom."))
        y = y - 70
    end

    -- Reset All button
    _, h = W:WideButton(parent, "Reset All Positions & Zoom", y,
        function()
            EllesmereUI:ShowConfirmPopup({
                title   = "Reset Shifter Positions & Zoom",
                message = "This will reset all saved panel positions and zoom levels and reload your UI.",
                confirmText = "Reset",
                cancelText  = "Cancel",
                onConfirm = function()
                    if EllesmereUI._ResetShifterPositions then
                        EllesmereUI._ResetShifterPositions()
                    end
                    ReloadUI()
                end,
            })
        end
    );  y = y - h

    ---------------------------------------------------------------------------
    --  SHIFTER
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "SHIFTER", y);  y = y - h

    parent._showRowDivider = true

    -- Build dropdown values for Reset Specific Window (any window with a
    -- saved position OR a saved zoom)
    local ddValues = { [""] = "Choose Window..." }
    local ddOrder  = {}
    do
        local seen = {}
        local function collect(tbl)
            if not tbl then return end
            for name in pairs(tbl) do
                if not seen[name] then
                    seen[name] = true
                    ddValues[name] = PrettifyName(name)
                    ddOrder[#ddOrder + 1] = name
                end
            end
        end
        collect(EllesmereUIDB and EllesmereUIDB.shifterPositions)
        collect(EllesmereUIDB and EllesmereUIDB.shifterScales)
        table.sort(ddOrder, function(a, b)
            return ddValues[a] < ddValues[b]
        end)
    end

    -- Row 1: Enable Shifter | Reset Specific Window
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Shifter",
          getValue = function()
              return EllesmereUIDB and EllesmereUIDB.shifterEnabled or false
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.shifterEnabled = v
              if v and EllesmereUI._InitShifter then
                  EllesmereUI._InitShifter()
              elseif not v and EllesmereUI._ShutdownShifter then
                  EllesmereUI._ShutdownShifter()
              end
          end },
        { type = "dropdown", text = "Reset Specific Window",
          values = ddValues,
          order  = ddOrder,
          getValue = function() return "" end,
          setValue = function(frameName)
              if frameName == "" then return end
              local pretty = ddValues[frameName] or PrettifyName(frameName)
              EllesmereUI:ShowConfirmPopup({
                  title   = "Reset Window Position & Zoom",
                  message = EllesmereUI.Lf("Reset %1$s to its default position and zoom and reload your UI?", pretty),
                  confirmText = "Reset",
                  cancelText  = "Cancel",
                  onConfirm = function()
                      if EllesmereUIDB and EllesmereUIDB.shifterPositions then
                          EllesmereUIDB.shifterPositions[frameName] = nil
                      end
                      if EllesmereUIDB and EllesmereUIDB.shifterScales then
                          EllesmereUIDB.shifterScales[frameName] = nil
                      end
                      ReloadUI()
                  end,
              })
          end }
    );  y = y - h

    -- Row 2: Move windows without shift
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Move Windows Without Shift",
          tooltip = "When enabled, left-click dragging a window will save its position without needing to hold Shift. Ctrl+drag still does a temporary move.",
          getValue = function()
              return EllesmereUIDB and EllesmereUIDB.shifterNoShift or false
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.shifterNoShift = v
          end },
        { type = "label", text = "" }
    );  y = y - h

    ---------------------------------------------------------------------------
    --  LOOT WINDOWS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LOOT WINDOWS", y);  y = y - h

    local function lootUnlockOff()
        return not (EllesmereUIDB and EllesmereUIDB.shifterLootUnlock)
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Move Loot Windows in Unlock Mode",
          tooltip = "Adds Bonus Roll, Group Loot, and Alert Toast movers to Unlock Mode.",
          getValue = function()
              return EllesmereUIDB and EllesmereUIDB.shifterLootUnlock or false
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.shifterLootUnlock = v
              if v then
                  if EllesmereUI._InitShifterLootWindows then
                      EllesmereUI._InitShifterLootWindows()
                  end
              else
                  if EllesmereUI._DisableShifterLootWindows then
                      EllesmereUI._DisableShifterLootWindows()
                  end
              end
              EllesmereUI:RefreshPage()  -- update the overlay toggle disabled state
          end },
        { type = "toggle", text = "Hide Unlock Mode Overlays",
          tooltip = "Hides the loot window movers in Unlock Mode while keeping their saved positions applied.",
          disabled = lootUnlockOff, disabledTooltip = "Move Loot Windows in Unlock Mode",
          getValue = function()
              return EllesmereUIDB and EllesmereUIDB.shifterLootHideOverlays or false
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.shifterLootHideOverlays = v
          end }
    );  y = y - h

    ---------------------------------------------------------------------------
    --  BLIZZARD TOP BAR EVENT TEXT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BLIZZARD TOP BAR EVENT TEXT", y);  y = y - h

    local function topBarUnlockOff()
        return not (EllesmereUIDB and EllesmereUIDB.shifterTopBarUnlock)
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Move Top Bar Event Text in Unlock Mode",
          tooltip = "Adds a mover for Blizzard's top-center event text and widgets (scenario, event, and encounter bars).",
          getValue = function()
              return EllesmereUIDB and EllesmereUIDB.shifterTopBarUnlock or false
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.shifterTopBarUnlock = v
              if v then
                  if EllesmereUI._InitShifterTopBar then
                      EllesmereUI._InitShifterTopBar()
                  end
              else
                  if EllesmereUI._DisableShifterTopBar then
                      EllesmereUI._DisableShifterTopBar()
                  end
              end
              EllesmereUI:RefreshPage()  -- update the overlay toggle disabled state
          end },
        { type = "toggle", text = "Hide Unlock Mode Overlay",
          tooltip = "Hides the Top Bar Event Text mover in Unlock Mode while keeping its saved position applied.",
          disabled = topBarUnlockOff, disabledTooltip = "Move Top Bar Event Text in Unlock Mode",
          getValue = function()
              return EllesmereUIDB and EllesmereUIDB.shifterTopBarHideOverlay or false
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.shifterTopBarHideOverlay = v
          end }
    );  y = y - h

    return math.abs(y)
end
