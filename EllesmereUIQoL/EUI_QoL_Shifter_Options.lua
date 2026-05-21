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
        line1:SetText("Shift + Left-Click Drag to permanently save a panel's position.")
        local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
        line2:SetFont(fontPath, 15, "")
        line2:SetTextColor(1, 1, 1, 0.75)
        line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
        line2:SetJustifyH("CENTER")
        line2:SetText("Ctrl + Left-Click Drag for a temporary move that resets when the panel closes.")
        y = y - 50
    end

    -- Reset All button
    _, h = W:WideButton(parent, "Reset All Positions", y,
        function()
            EllesmereUI:ShowConfirmPopup({
                title   = "Reset Shifter Positions",
                message = "This will reset all saved panel positions and reload your UI.",
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

    -- Build dropdown values for Reset Specific Window
    local ddValues = { [""] = "Choose Window..." }
    local ddOrder  = {}
    local positions = EllesmereUIDB and EllesmereUIDB.shifterPositions
    if positions then
        for name in pairs(positions) do
            ddValues[name] = PrettifyName(name)
            ddOrder[#ddOrder + 1] = name
        end
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
                  title   = "Reset Window Position",
                  message = "Reset " .. pretty .. " to its default position and reload your UI?",
                  confirmText = "Reset",
                  cancelText  = "Cancel",
                  onConfirm = function()
                      if EllesmereUIDB and EllesmereUIDB.shifterPositions then
                          EllesmereUIDB.shifterPositions[frameName] = nil
                      end
                      ReloadUI()
                  end,
              })
          end }
    );  y = y - h

    return math.abs(y)
end
