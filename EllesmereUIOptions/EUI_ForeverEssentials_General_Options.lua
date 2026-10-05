if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_General_Options.lua
--  Builds the "General" page inside the Forever Essentials module: its
--  general quality of life features, one section each.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

_G._EUI_BuildForeverGeneralPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local SU = EllesmereUI._SpellUprank
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    _, h = W:SectionHeader(parent, "SPELL RANKS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Auto Uprank Spells",
          tooltip = "Swaps new spell ranks onto your action bars.",
          getValue = function() return SU.Get("enabled") end,
          setValue = function(v)
              SU.Cfg().enabled = v
              SU.Apply()
          end },
        BLANK()
    );  y = y - h

    return math.abs(y)
end
