if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MacroManager.lua  (WoW Forever only)
--  Macro Manager storage and macro access. The editor itself is the "Macros"
--  page of the Forever Essentials options (EUI_ForeverEssentials_Macros_Options.lua).
--
--  Macros are stored by the game. Next to each one we keep its builder model
--  (which also holds switched-off lines), but only trust that model while it
--  still builds the exact macro text.
--  Settings live in EllesmereUIDB.macroManager; per-character data (character
--  macro models, bulk selection) under chars["Name - Realm"].
-------------------------------------------------------------------------------
local _, module = ...
local B = module.MacroBuilder

local F = module.Feature("macroManager", { enabled = false })

local MM = {}
MM.Builder = B
MM.MAX_ACCOUNT = Constants.MacroConsts.MAX_ACCOUNT_MACROS
MM.MAX_CHAR    = Constants.MacroConsts.MAX_CHARACTER_MACROS
MM.MAX_BYTES   = 255
MM.MAX_NAME    = 16
MM.QUESTION    = 134400 -- INV_Misc_QuestionMark: the icon follows #showtooltip

-------------------------------------------------------------------------------
--  Storage. Only called from the page, so nothing is written before use.
-------------------------------------------------------------------------------
local function DB()
    local c = F.Cfg()
    c.meta = c.meta or {}
    c.bulk = c.bulk or { prefix = "", perChar = true, overwrite = true, spellIcon = false }
    c.chars = c.chars or {}
    return c
end
MM.DB = DB

local function CharDB()
    local chars = DB().chars
    local key = UnitName("player") .. " - " .. GetRealmName()
    local c = chars[key]
    if not c then
        c = { meta = {}, bulkSelected = {} }
        chars[key] = c
    end
    return c
end
MM.CharDB = CharDB

-- UTF-8 safe cut to n characters (macro names hold 16).
function MM.Truncate(s, n)
    local out, count = {}, 0
    for ch in (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > n then break end
        out[count] = ch
    end
    return table.concat(out)
end

-- Per-macro builder model: { model, body }
local function MetaStore(perChar)
    return perChar and CharDB().meta or DB().meta
end
function MM.Meta(name, perChar) return MetaStore(perChar)[name] end
function MM.SetMeta(name, perChar, meta) MetaStore(perChar)[name] = meta end

-------------------------------------------------------------------------------
--  Macro access
-------------------------------------------------------------------------------
function MM.Counts()
    local a, c = GetNumMacros()
    return a or 0, c or 0
end

function MM.Free(perChar)
    local a, c = MM.Counts()
    if perChar then return MM.MAX_CHAR - c end
    return MM.MAX_ACCOUNT - a
end

-- { { index, name, icon, body, perChar } }
function MM.List(perChar)
    local out = {}
    local a, c = MM.Counts()
    local first, count = 1, a
    if perChar then first, count = MM.MAX_ACCOUNT + 1, c end
    for i = first, first + count - 1 do
        local name, icon, body = GetMacroInfo(i)
        if name then
            out[#out + 1] = { index = i, name = name, icon = icon, body = body or "", perChar = perChar }
        end
    end
    return out
end

function MM.Find(name, perChar)
    for _, m in ipairs(MM.List(perChar)) do
        if m.name == name then return m end
    end
end

-- GetMacroInfo returns the icon currently shown: for a "?" macro that is the
-- spell's icon, and saving that back would freeze the dynamic icon.
function MM.PickedIcon(index, showing)
    return C_Macro.GetSelectedMacroIcon(index) or showing
end

function MM.Blocked()
    if InCombatLockdown() then
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "
            .. EllesmereUI.L("Macros can't be changed in combat."))
        return true
    end
end

-- Create or update; a scope change re-creates the macro in the other list.
-- Returns true, or nil and an error.
function MM.Save(index, name, icon, body, perChar)
    if MM.Blocked() then return nil, EllesmereUI.L("Locked in combat") end
    perChar = perChar and true or false
    icon = icon or MM.QUESTION
    if index and (index > MM.MAX_ACCOUNT) == perChar then
        local ok, err = pcall(EditMacro, index, name, icon, body)
        if not ok then return nil, err end
        return true
    end
    if MM.Free(perChar) <= 0 then return nil, EllesmereUI.L("No free macro slot") end
    local ok, err = pcall(CreateMacro, name, icon, body, perChar)
    if not ok then return nil, err end
    if index then DeleteMacro(index) end
    return true
end

function MM.Delete(index)
    if MM.Blocked() then return end
    DeleteMacro(index)
end

-------------------------------------------------------------------------------
--  Opening the page: /euimacros, registered on the first enable.
-------------------------------------------------------------------------------
function MM.Open()
    if InCombatLockdown() then return end
    EllesmereUI:NavigateToElementSettings("EllesmereUIForeverEssentials", "Macros")
end

local slashDone
local function Apply()
    if not F.Enabled() or slashDone then return end
    slashDone = true
    SLASH_EUIMACROS1 = "/euimacros"
    SlashCmdList.EUIMACROS = function()
        if F.Enabled() then MM.Open() end
    end
end

MM.Get, MM.Cfg, MM.Enabled, MM.Apply = F.Get, F.Cfg, F.Enabled, Apply

-- Options-page entry points.
EllesmereUI._MacroManager = MM

F.Start(Apply)
