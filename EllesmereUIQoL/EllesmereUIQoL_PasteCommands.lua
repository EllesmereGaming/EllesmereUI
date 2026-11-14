if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- /euipaste runs a pasted block of /way lines. Off by default and reload-gated.
if not (EllesmereUIDB and EllesmereUIDB.pasteCommands == true) then return end

local EUI = EllesmereUI

local SLASH      = "/euipaste"
local OWN_KEY    = "EUIPASTE"
local MACRO_NAME = "EUI_Paste"
local PREFIX     = EUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "
-- Run executes inside our click, so a blocked or tainting command would be blamed on EllesmereUI.
local ALLOWED    = { ["/WAY"] = true, ["/EUIWAY"] = true }

local function Say(msg) EUI.Print(PREFIX .. msg) end

local function SplitLines(text)
    local lines = {}
    for line in (text:gsub("\r\n?", "\n") .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

-- The chat code moves commands it has imported into hash_SlashCmdList; the rest wait in SlashCmdList.
local function LookupCommand(upper)
    local handler = hash_SlashCmdList[upper]
    if handler then return hash_ChatTypeInfoList[upper], handler end
    for key, fn in pairs(SlashCmdList) do
        local i, alias = 1, _G["SLASH_" .. key .. "1"]
        while type(alias) == "string" do
            if alias:upper() == upper then return key, fn end
            i = i + 1
            alias = _G["SLASH_" .. key .. i]
        end
    end
end

-- Runs whichever addon owns the command; a secure alias means Blizzard's, which is never called.
local function WaypointCommand(cmd)
    local upper = cmd:upper()
    if not ALLOWED[upper] then return end
    local key, handler = LookupCommand(upper)
    if key and not issecurevariable("SLASH_" .. key .. "1") then return handler end
end

local function Run(text)
    local lines, skipped = SplitLines(text), 0
    local editBox = DEFAULT_CHAT_FRAME.editBox
    for _, line in ipairs(lines) do
        local cmd, args = line:match("^(/%S+)%s*(.-)$")
        local handler = cmd and WaypointCommand(cmd)
        if handler then
            xpcall(handler, geterrorhandler(), args, editBox)
        else
            skipped = skipped + 1
        end
    end
    if skipped > 0 then
        Say(EllesmereUI.Lf("Skipped %1$d of %2$d lines: only /way and /euiway waypoint lines can be pasted.", skipped, #lines))
    end
end

local function Open()
    EUI:ShowImportPopup(Run, EllesmereUI.L("Paste Waypoints"),
        EllesmereUI.L("Paste /way or /euiway lines, one waypoint per line"),
        { confirmLabel = "Run", rawPaste = true })
end

-- The macro is the action bar button: created once, then handed to the cursor to drop on a bar.
function EUI._createPasteMacro()
    if InCombatLockdown() then
        Say(EllesmereUI.L("Leave combat to create the macro."))
        return
    end
    if GetMacroIndexByName(MACRO_NAME) == 0 then
        if GetNumMacros() >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            Say(EllesmereUI.L("All account macro slots are in use. Delete one to create the macro."))
            return
        end
        CreateMacro(MACRO_NAME, "INV_Misc_Note_01", SLASH, nil)
    end
    -- Found again by name: other addons' macro event handlers run inside CreateMacro and may reorder the list.
    local index = GetMacroIndexByName(MACRO_NAME)
    if index > 0 then PickupMacro(index) end
end

-- One frame after loading, so a /paste another addon registers at load or login is seen.
C_Timer.After(0, function()
    SLASH_EUIPASTE1 = SLASH
    local _, taken = LookupCommand("/PASTE")
    if not taken then SLASH_EUIPASTE2 = "/paste" end
    SlashCmdList[OWN_KEY] = Open
end)
