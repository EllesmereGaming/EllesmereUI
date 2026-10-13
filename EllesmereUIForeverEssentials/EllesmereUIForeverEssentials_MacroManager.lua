if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MacroManager.lua  (WoW Forever only)
--  The Macro Manager's switch and /euimacros. The editor is the "Macros" page
--  of the Forever Essentials options (EUI_ForeverEssentials_Macros_Options.lua,
--  its model EUI_ForeverEssentials_MacroModel_Options.lua), built with the
--  panel. EllesmereUIDB.macroManager holds only the switch: the game's macro
--  text is the macro.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("macroManager", { enabled = false })

-- /euimacros opens the page; registered at the first enable.
local slashDone
local function Apply()
    if slashDone or not F.Enabled() then return end
    slashDone = true
    SLASH_EUIMACROS1 = "/euimacros"
    SlashCmdList.EUIMACROS = function()
        if F.Enabled() and not InCombatLockdown() then
            EllesmereUI:NavigateToElementSettings("EllesmereUIForeverEssentials", "Macros")
        end
    end
end

-- Options-page entry points.
EllesmereUI._MacroManager = { Enabled = F.Enabled, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply)
