-------------------------------------------------------------------------------
--  EUI_RaidFrames_ClickCast.lua
--  Lightweight click-casting system for EllesmereUI unit frames.
--  Per-spec bindings with global target/menu/macro defaults.
--
--  Two binding paths:
--  1. Frame-based: WrapScript OnEnter/OnLeave on unit frames, activates
--     keyboard bindings via SetBindingClick. Click bindings use direct
--     attribute setting on the frame.
--  2. Hovercast: Persistent global bindings on a dedicated secure button
--     targeting @mouseover in the game world. Friend/harm filtered via
--     macro conditionals.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local pairs        = pairs
local ipairs       = ipairs
local tinsert      = table.insert
local tremove      = table.remove
local wipe         = wipe
local format       = string.format
local tostring     = tostring
local type         = type
local floor        = math.floor
local max          = math.max
local CreateFrame  = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown   = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown     = IsAltKeyDown
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local C_Spell      = C_Spell
local C_SpellBook  = C_SpellBook
local C_Timer      = C_Timer
local GetMacroInfo = GetMacroInfo
local GetMacroBody = GetMacroBody
local GetMacroIndexByName = GetMacroIndexByName
local GetNumMacros = GetNumMacros
local MAX_ACCOUNT_MACROS   = MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS or 18

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

local MOUSE_BUTTON_MAP = {
    LeftButton   = "BUTTON1",
    RightButton  = "BUTTON2",
    MiddleButton = "BUTTON3",
    Button4      = "BUTTON4",
    Button5      = "BUTTON5",
}

local ACTION_ICONS = {
    target  = 132212,
    menu    = 5341597,
    macro   = 134400,
    dispel  = 135894,   -- Dispel Magic icon
    external = 135966,  -- Blessing of Sacrifice icon
}

-- Dispel spells by class (friendly dispels only)
local DISPEL_SPELLS = {
    { id = 240166, name = "Purify",        class = "PRIEST" },
    { id = 218164, name = "Detox",         class = "MONK" },
    { id = 4987,   name = "Cleanse",       class = "PALADIN" },  -- Holy
    { id = 213644, name = "Cleanse Toxins", class = "PALADIN" }, -- Prot & Ret (Cleanse is Holy-only)
    { id = 88423,  name = "Nature's Cure", class = "DRUID" },  -- Resto
    { id = 2782,   name = "Remove Corruption", class = "DRUID" }, -- Guardian, Feral & Balance
    { id = 254420, name = "Purify Spirit", class = "SHAMAN" },  -- Resto
    { id = 51886,  name = "Cleanse Spirit", class = "SHAMAN" }, -- Ele & Enh
    { id = 360823, name = "Naturalize",    class = "EVOKER" },  -- Pres
    { id = 365585, name = "Expunge",       class = "EVOKER" },  -- Aug & Dev
    { id = 89808,  name = "Singe Magic",   class = "WARLOCK" }, -- Warlock
    { id = 475,    name = "Remove Curse",  class = "MAGE" },  -- All specs (Curse only)
}

-- External defensive spells by class
local EXTERNAL_SPELLS = {
    { id = 33206,  name = "Pain Suppression",      class = "PRIEST" },
    { id = 255312, name = "Guardian Spirit",        class = "PRIEST" },
    { id = 102342, name = "Ironbark",              class = "DRUID" },
    { id = 6940,   name = "Blessing of Sacrifice",  class = "PALADIN" },
    { id = 357170, name = "Time Dilation",          class = "EVOKER" },
    { id = 343744, name = "Life Cocoon",            class = "MONK" },
}

-- Resurrection spells by class: single (ooc), group (ooc), battle (combat)
local REZ_BY_CLASS = {
    PRIEST      = { single = 2006,   group = 212036 },
    PALADIN     = { single = 7328,   group = 212056, battle = 391054 },
    SHAMAN      = { single = 2008,   group = 212048 },
    DRUID       = { single = 50769,  group = 212040, battle = 20484 },
    MONK        = { single = 115178, group = 212051 },
    EVOKER      = { single = 361227, group = 361178 },
    DEATHKNIGHT = { battle = 61999 },
    WARLOCK     = { battle = 20707 },
}

-- Build a lookup set of spell IDs in these collections
local PRESET_SPELL_IDS = {}
for _, s in ipairs(DISPEL_SPELLS) do PRESET_SPELL_IDS[s.id] = true end
for _, s in ipairs(EXTERNAL_SPELLS) do PRESET_SPELL_IDS[s.id] = true end
for _, kit in pairs(REZ_BY_CLASS) do
    for _, sid in pairs(kit) do PRESET_SPELL_IDS[sid] = true end
end
ns.CC_PRESET_SPELL_IDS = PRESET_SPELL_IDS

-- Lookup set of every rez spell ID across all classes. Directly-bound rez
-- spells are exempt from the exists/nodead corpse filter in macro building:
-- corpses are their only valid target, so the filter would break them.
local REZ_SPELL_IDS = {}
for _, kit in pairs(REZ_BY_CLASS) do
    for _, sid in pairs(kit) do REZ_SPELL_IDS[sid] = true end
end

-- True when a spell binding is a rez spell (by stored ID, with a name
-- fallback for legacy bindings saved before spell IDs were stored).
local function IsRezSpellBinding(binding)
    if type(binding.spellID) == "number" and REZ_SPELL_IDS[binding.spellID] then
        return true
    end
    local bn = binding.spell
    if type(bn) == "string" and C_Spell and C_Spell.GetSpellName then
        for sid in pairs(REZ_SPELL_IDS) do
            if C_Spell.GetSpellName(sid) == bn then return true end
        end
    end
    return false
end

local KEY_DISPLAY = {
    BUTTON1 = "Left Click",  BUTTON2 = "Right Click", BUTTON3 = "Middle Click",
    BUTTON4 = "Mouse 4",     BUTTON5 = "Mouse 5",
    MOUSEWHEELUP = "Wheel Up", MOUSEWHEELDOWN = "Wheel Down",
}

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local header           = nil   -- SecureHandlerBaseTemplate (frame bindings)
local bindProxy          = nil   -- SecureActionButtonTemplate (unnamed frame fallback)
local globalBtn        = nil   -- SecureActionButtonTemplate (hovercast bindings)
local registeredFrames = {}
local ownedFrames      = {}
-- Native left-click target attrs (type1 / *type1) captured the first time a frame
-- is registered, so DoUnregisterFrame restores EXACTLY what the frame had: raid
-- frames target on left-click, EUI unit frames don't. Without this, disabling
-- click-cast would force the raid default (left-click targets) onto unit frames.
-- Weak-keyed so dead frames drop out.
local originalTargetAttrs = setmetatable({}, { __mode = "k" })
local regQueue         = {}
local unregQueue       = {}
local pendingApply     = false
local ccInitialized    = false
local ccEventFrame     = nil
local lastBindingCount = 0
local lastHoverCount   = 0
local pendingSetEnabled = nil  -- deferred CC_SetEnabled value when toggled in combat

-------------------------------------------------------------------------------
--  Data access
-------------------------------------------------------------------------------
local function GetClickCastDB()
    local db = ns.db
    if not db then return nil end
    if not db.sv.clickCast then
        db.sv.clickCast = {
            enabled    = false,
            allFrames  = true,
            downClick  = true,
            specs      = {},
            globals    = {
                { key = "BUTTON1",  type = "target",   enabled = true },
                { key = "BUTTON2",  type = "menu",     enabled = true },
                { type = "dispel",   enabled = true },
                { type = "dynamicrez", enabled = true },
                { type = "external", enabled = true },
                { type = "trinket1", enabled = true },
                { type = "trinket2", enabled = true },
            },
        }
    end
    local cc = db.sv.clickCast
    return cc
end

-- Exposed for the suite conflict check (EllesmereUI._RunConflictCheck): true when
-- HoverCast / click-casting is currently enabled. Read on demand (the conflict
-- check runs once at login); not relied on to update dynamically.
_G._ERF_IsHoverCastEnabled = function()
    local cc = GetClickCastDB()
    return (cc and cc.enabled) or false
end

local function GetCurrentSpecID()
    local idx = GetSpecialization()
    return idx and (GetSpecializationInfo(idx)) or nil
end
local function GetCurrentSpecName()
    local idx = GetSpecialization()
    if idx then local _, n = GetSpecializationInfo(idx); return n end
    return "No Spec"
end
local function GetCurrentSpecIcon()
    local idx = GetSpecialization()
    if idx then local _, _, _, ic = GetSpecializationInfo(idx); return ic end
    return nil
end

local function GetSpecBindings(specID)
    local cc = GetClickCastDB()
    if not cc then return {} end
    specID = specID or GetCurrentSpecID()
    if specID and cc.specs[specID] then return cc.specs[specID] end
    return {}
end

local function GetGlobalBindings()
    local cc = GetClickCastDB()
    return cc and cc.globals or {}
end

-- Merge globals + current spec. Spec overrides globals on key conflict.
-- Only includes enabled bindings. Respects master enable toggle.
local function GetActiveBindings()
    local cc = GetClickCastDB()
    if not cc or not cc.enabled then return {} end
    local result, usedKeys = {}, {}
    for _, b in ipairs(GetSpecBindings()) do
        if b.enabled ~= false and b.key then
            result[#result + 1] = b
            usedKeys[b.key] = true
        end
    end
    for _, b in ipairs(cc.globals) do
        if b.enabled ~= false and b.key and not usedKeys[b.key] then
            result[#result + 1] = b
        end
    end
    return result
end

-------------------------------------------------------------------------------
--  Key utilities
-------------------------------------------------------------------------------
local function GetModifierPrefix()
    local p = ""
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    return p
end
-- Exposed so the keybind-capture button reuses this SAME canonical modifier
-- order (ALT-CTRL-SHIFT -- the order WoW matches bindings/clicks in). The button
-- previously built its own SHIFT-CTRL-ALT prefix, which never matched for a
-- double-modifier bind (e.g. Ctrl+Shift+click) -> the click fell through to the
-- default (target). Single modifier worked because order is irrelevant with one.
ns.CC_GetModifierPrefix = GetModifierPrefix

function ns.CC_CaptureKey(rawKey)
    if MODIFIER_KEYS[rawKey] or rawKey == "ESCAPE" or rawKey == "UNKNOWN" then return nil end
    local key = MOUSE_BUTTON_MAP[rawKey] or rawKey:upper()
    return GetModifierPrefix() .. key
end

-- Parse a key string ("ALT-CTRL-SHIFT-KEY") into modifiers + key. Modifiers are
-- peeled from the FRONT as known prefixes instead of splitting on "-", because
-- the key itself can BE "-" (the minus key). The old split-on-"-" produced no
-- parts for "-" and left key nil -> "attempt to index local 'key'" crash when a
-- user tried to bind the minus key (or any modified form like CTRL--).
local function ParseKeyString(keyStr)
    if not keyStr or keyStr == "" then
        return { modifiers = "", key = "", isMouseButton = false, buttonNum = nil, full = keyStr or "" }
    end
    local rest, mods = keyStr, ""
    while true do
        local pre = (rest:sub(1, 4) == "ALT-" and "ALT-")
                 or (rest:sub(1, 5) == "CTRL-" and "CTRL-")
                 or (rest:sub(1, 6) == "SHIFT-" and "SHIFT-")
                 or (rest:sub(1, 5) == "META-" and "META-")
        if pre and #rest > #pre then
            mods = mods .. pre
            rest = rest:sub(#pre + 1)
        else
            break
        end
    end
    local key = rest
    local isMouse = key:match("^BUTTON%d+$") or key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN"
    local btnNum = key:match("^BUTTON(%d+)$")
    return { modifiers = mods, key = key, isMouseButton = isMouse ~= nil,
             buttonNum = btnNum and tonumber(btnNum), full = keyStr }
end

function ns.CC_FormatKey(keyStr)
    if not keyStr or keyStr == "" then return "" end
    -- Parse via ParseKeyString so the key part can be "-" (the minus key);
    -- modifiers is a run of "MOD-" tokens (never contains a bare "-").
    local parsed = ParseKeyString(keyStr)
    local display = {}
    for m in parsed.modifiers:gmatch("([^-]+)") do
        display[#display + 1] = m == "SHIFT" and "Shift" or m == "CTRL" and "Ctrl" or m == "ALT" and "Alt" or m
    end
    display[#display + 1] = KEY_DISPLAY[parsed.key] or parsed.key
    return table.concat(display, " + ")
end
ns.CC_ParseKeyString = ParseKeyString

-- Heal saved binding keys whose modifiers are in a non-canonical order. Older
-- builds' keybind button emitted SHIFT-CTRL-ALT, but WoW matches bindings/clicks
-- in ALT-CTRL-SHIFT order, so a double-modifier bind saved that way silently
-- failed (just targeted the frame). Rewrites the key in place -- the DB binding
-- tables are referenced directly -- so old binds start working without the user
-- re-binding. Called once at the top of CC_ApplyBindings, which only fires on
-- load / binding change / spec change / profile swap (never per-frame or in
-- combat); it is a no-op once every key is already canonical, so there is no
-- steady-state cost.
local function NormalizeSavedBindingKeys()
    local cc = GetClickCastDB()
    if not cc then return end
    local function canon(b)
        if not b.key or b.key == "" then return end
        local parsed = ParseKeyString(b.key)
        if parsed.modifiers == "" then return end  -- no modifiers -> nothing to reorder
        local p = ""
        if parsed.modifiers:find("ALT-",   1, true) then p = p .. "ALT-"   end
        if parsed.modifiers:find("CTRL-",  1, true) then p = p .. "CTRL-"  end
        if parsed.modifiers:find("SHIFT-", 1, true) then p = p .. "SHIFT-" end
        if parsed.modifiers:find("META-",  1, true) then p = p .. "META-"  end
        local canonical = p .. parsed.key
        if canonical ~= b.key then b.key = canonical end
    end
    if cc.specs then
        for _, list in pairs(cc.specs) do
            if type(list) == "table" then
                for _, b in ipairs(list) do canon(b) end
            end
        end
    end
    if cc.globals then
        for _, b in ipairs(cc.globals) do canon(b) end
    end
end

-------------------------------------------------------------------------------
--  Macro / spell helpers
-------------------------------------------------------------------------------
-- Build the macrotext for a binding based on its options.
-- For spells: wraps with @mouseover + friend/harm + nocombat conditionals.
-- For macros: reads the saved macro body, optionally prepends /stopmacro [combat].
-- Mount/vehicle guard appended to hovercast conditionals so override
-- bindings don't consume keypresses while dragonriding or in vehicles.
local MOUNT_GUARD = ",nomounted,noflying"

-- Resolve a spell binding to its BASE spell NAME so the cast survives talent /
-- hero-talent / proc overrides. Example: a Chronowarden binds "Chrono Flames"
-- (a hero-talent override of Living Flame). Casting the BASE "Living Flame"
-- works in every spec -- the game auto-resolves it to whatever override is
-- currently active (Chrono Flames here) -- whereas "/cast Chrono Flames" fails
-- in a spec that lacks that override. Same for proc overrides (a spell bound
-- while a proc like Mathias's Blessing is up captures the proc form). Resolution
-- is by the stored spellID, so it repairs both existing and new bindings without
-- rewriting saved data. The binding still DISPLAYS the name the user picked.
local function ResolveCastSpellName(binding)
    local id = binding.spellID
    if type(id) == "number" and id > 0 and C_Spell and C_Spell.GetBaseSpell then
        local baseId = C_Spell.GetBaseSpell(id)
        if type(baseId) == "number" and baseId > 0 and baseId ~= id then
            local n = C_Spell.GetSpellName and C_Spell.GetSpellName(baseId)
            if n then return n end
        end
    end
    return binding.spell
end

-- Build the dynamic-rez /cast lines for a binding. Used by the dynamicrez
-- binding type and by Smart Rez on any castable binding. Returns a list of
-- macro lines (possibly empty) or nil when the player's class has no rez kit.
-- Never includes /stopmacro -- the caller adds that for oocOnly.
local function BuildRezLines(binding, guard)
    local _, pClass = UnitClass("player")
    local kit = REZ_BY_CLASS[pClass]
    if not kit then return nil end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local function Known(sid)
        if not sid then return nil end
        if C_SpellBook.IsSpellInSpellBook and bank then
            if not C_SpellBook.IsSpellInSpellBook(sid, bank, true) then return nil end
        end
        return C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
    end
    local battleName = Known(kit.battle)
    local groupName  = Known(kit.group)
    local singleName = Known(kit.single)
    local lines = {}
    if battleName and not binding.oocOnly then
        lines[#lines + 1] = "/cast [@mouseover,help,dead,combat" .. guard .. "] " .. battleName
    end
    if groupName then
        lines[#lines + 1] = "/cast [@mouseover,help,dead,nocombat" .. guard .. "] " .. groupName
    elseif singleName then
        lines[#lines + 1] = "/cast [@mouseover,help,dead,nocombat" .. guard .. "] " .. singleName
    end
    return lines
end

-- Build the base macrotext for a binding (without Smart Rez). Returns nil when
-- the binding needs no macro wrapping (it is applied as a direct spell instead).
local function BuildBaseMacroText(binding)
    local isHC = binding.hovercast
    local guard = isHC and MOUNT_GUARD or ""

    if binding.type == "spell" then
        local name = ResolveCastSpellName(binding)
        if not name then return nil end
        local isRez = IsRezSpellBinding(binding)
        local conds = { "@mouseover" }
        if isHC then
            if binding.hoverFriendly and not binding.hoverEnemy then
                conds[#conds + 1] = "help"
            elseif binding.hoverEnemy and not binding.hoverFriendly then
                conds[#conds + 1] = "harm"
            end
        end
        -- exists,nodead: when the hovered unit is gone (left group, phased,
        -- despawned) or just died, the conditional fails and the macro does
        -- nothing. Without it the cast goes out against an invalid unit and
        -- Blizzard default targeting takes over -- with auto self cast
        -- enabled, the spell lands on the player instead of being dropped.
        -- Rez spells are exempt: corpses are their only valid target.
        if not isRez then
            conds[#conds + 1] = "exists"
            conds[#conds + 1] = "nodead"
        end
        if binding.oocOnly then
            conds[#conds + 1] = "nocombat"
        end
        -- A frame-click rez binding with no other conditions needs no macro
        -- wrapping; it is applied as a direct spell attribute instead.
        if isRez and not isHC and #conds == 1 then
            return nil
        end
        return "/cast [" .. table.concat(conds, ",") .. guard .. "] " .. name
    elseif binding.type == "macro" then
        local macroName = binding.macroName
        if not macroName then return nil end
        local idx = GetMacroIndexByName(macroName)
        if not idx or idx == 0 then return nil end
        local body = GetMacroBody(idx)
        if not body then return nil end
        if binding.oocOnly then
            body = "/stopmacro [combat]\n" .. body
        end
        if isHC then
            body = "/stopmacro [mounted][flying]\n" .. body
        end
        return body
    elseif binding.type == "item" then
        local target = binding.itemSlot or binding.itemName
        if not target then return nil end
        local cmd = "/use [@mouseover,exists,nodead" .. guard .. "] " .. target
        if binding.oocOnly then
            cmd = "/stopmacro [combat]\n" .. cmd
        end
        return cmd
    elseif binding.type == "trinket1" or binding.type == "trinket2" then
        local slot = binding.type == "trinket1" and 13 or 14
        local cmd = "/use [@mouseover,exists,nodead" .. guard .. "] " .. slot
        if binding.oocOnly then
            cmd = "/stopmacro [combat]\n" .. cmd
        end
        return cmd
    elseif binding.type == "dynamicrez" then
        local lines = BuildRezLines(binding, guard)
        if not lines or #lines == 0 then return nil end
        if binding.oocOnly then
            table.insert(lines, 1, "/stopmacro [combat]")
        end
        return table.concat(lines, "\n")
    elseif binding.type == "dispel" or binding.type == "external" then
        local spellList = binding.type == "dispel" and DISPEL_SPELLS or EXTERNAL_SPELLS
        local _, pClass = UnitClass("player")
        local lines = {}
        if binding.oocOnly then
            lines[#lines + 1] = "/stopmacro [combat]"
        end
        for _, sp in ipairs(spellList) do
            if sp.class == pClass then
                -- Use the client-localized spell name. /cast resolves spells by
                -- their localized name, so the hardcoded English sp.name silently
                -- fails on non-English clients. Fall back to sp.name if the API
                -- is unavailable or returns nothing.
                local castName = (C_Spell.GetSpellName and C_Spell.GetSpellName(sp.id)) or sp.name
                lines[#lines + 1] = "/cast [@mouseover,exists,nodead" .. guard .. "] " .. castName
            end
        end
        if #lines == 0 then return nil end
        return table.concat(lines, "\n")
    end
    return nil
end

-- Wrap a binding's base macrotext with Smart Rez. When binding.smartRez is set,
-- the dynamic-rez /cast lines are prepended so pressing the binding on a dead
-- unit resurrects it; on a living unit the rez lines fail their [dead] condition
-- and the macro falls through to the binding's normal action.
local function BuildMacroText(binding)
    local base = BuildBaseMacroText(binding)
    if not binding.smartRez then return base end
    -- Smart Rez never applies to non-cast bindings or the rez binding itself.
    if binding.type == "target" or binding.type == "menu" or binding.type == "dynamicrez" then
        return base
    end
    local guard = binding.hovercast and MOUNT_GUARD or ""
    local rez = BuildRezLines(binding, guard)
    if not rez or #rez == 0 then return base end
    local rezText = table.concat(rez, "\n")

    if base then
        return rezText .. "\n" .. base
    end
    -- A plain spell binding produces no base macro (it is applied as a direct
    -- spell). Convert it to a macro so the rez lines can lead, then cast the
    -- spell on the same unit the rez check used.
    if binding.type == "spell" then
        local name = ResolveCastSpellName(binding)
        if not name then return rezText end
        return rezText .. "\n/cast [@mouseover,exists,nodead" .. guard .. "] " .. name
    end
    return rezText
end

-- Get the icon for a binding
function ns.CC_GetBindingIcon(b)
    if b.type == "dispel" then
        local _, pc = UnitClass("player")
        for _, sp in ipairs(DISPEL_SPELLS) do
            if sp.class == pc then
                local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sp.id)
                if tex then return tex end
            end
        end
        return ACTION_ICONS.dispel
    elseif b.type == "external" then
        local _, pc = UnitClass("player")
        for _, sp in ipairs(EXTERNAL_SPELLS) do
            if sp.class == pc then
                local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sp.id)
                if tex then return tex end
            end
        end
        return ACTION_ICONS.external
    elseif b.type == "trinket1" then
        return GetInventoryItemTexture("player", 13) or 134400
    elseif b.type == "trinket2" then
        return GetInventoryItemTexture("player", 14) or 134400
    elseif b.type == "dynamicrez" then
        local _, pc = UnitClass("player")
        local kit = REZ_BY_CLASS[pc]
        if kit then
            local sid = kit.battle or kit.group or kit.single
            if sid then
                local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                if tex then return tex end
            end
        end
        return 136080
    end
    if b.icon then return b.icon end
    if b.spellID then
        local info = C_Spell.GetSpellInfo(b.spellID)
        if info and info.iconID then return info.iconID end
    end
    if b.spell then
        local info = C_Spell.GetSpellInfo(b.spell)
        if info and info.iconID then return info.iconID end
    end
    if b.macroName then
        local idx = GetMacroIndexByName(b.macroName)
        if idx and idx > 0 then
            local _, iconTex = GetMacroInfo(idx)
            if iconTex then return iconTex end
        end
    end
    if b.itemSlot then
        local tex = GetInventoryItemTexture("player", b.itemSlot)
        if tex then return tex end
    end
    return ACTION_ICONS[b.type] or 134400
end

function ns.CC_GetBindingName(b)
    if b.type == "target" then return EllesmereUI.L("Target Unit") end
    if b.type == "menu" then return EllesmereUI.L("Context Menu") end
    if b.type == "trinket1" then return EllesmereUI.L("Trinket 1") end
    if b.type == "trinket2" then return EllesmereUI.L("Trinket 2") end
    if b.type == "dynamicrez" then return EllesmereUI.L("Dynamic Rez") end
    if b.type == "spell" then return b.spell or EllesmereUI.L("Unknown Spell") end
    if b.type == "macro" then return b.macroName or EllesmereUI.L("Unknown Macro") end
    if b.type == "item" then
        if b.itemSlot then
            local itemID = GetInventoryItemID("player", b.itemSlot)
            if itemID then
                local name = C_Item.GetItemInfo(itemID)
                if name then return name end
            end
        end
        return b.itemName or EllesmereUI.L("Unknown Item")
    end
    if b.type == "dispel" then return EllesmereUI.L("Dispels") end
    if b.type == "external" then return EllesmereUI.L("Externals") end
    return EllesmereUI.L("Unknown")
end

-------------------------------------------------------------------------------
--  Spell enumeration (class/spec spells, non-passive, non-general)
-------------------------------------------------------------------------------
function ns.CC_GetClassSpells()
    local spells = {}
    if not C_SpellBook then return spells end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not bank then return spells end

    local numTabs = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    local seen = {}

    for tab = 1, numTabs do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        if lineInfo then
            local tabName = lineInfo.name or ""
            local isGeneral = (tabName == "General" or tabName == GENERAL or tabName == "")
            local isOffSpec = lineInfo.offSpecID and lineInfo.offSpecID ~= 0

            if not isGeneral and not isOffSpec and not lineInfo.shouldHide then
                local offset = lineInfo.itemIndexOffset or 0
                local count = lineInfo.numSpellBookItems or 0
                for si = offset + 1, offset + count do
                    local spellType, actionId, spellId = C_SpellBook.GetSpellBookItemType(si, bank)
                    if spellType == Enum.SpellBookItemType.Spell then
                        local sid = spellId or actionId
                        if sid and not seen[sid] then
                            local isPassive = C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(sid)
                            if not isPassive then
                                seen[sid] = true
                                local name = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                                local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                                if name then
                                    spells[#spells + 1] = { id = sid, name = name, icon = icon }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(spells, function(a, b) return a.name < b.name end)
    return spells
end

-------------------------------------------------------------------------------
--  Macro enumeration
-------------------------------------------------------------------------------
function ns.CC_GetGlobalMacros()
    local macros = {}
    local numGlobal = select(1, GetNumMacros()) or 0
    for i = 1, numGlobal do
        local name, iconTex, body = GetMacroInfo(i)
        if name then
            macros[#macros + 1] = { index = i, name = name, icon = iconTex, isGlobal = true }
        end
    end
    return macros
end

function ns.CC_GetAllMacros()
    local macros = ns.CC_GetGlobalMacros()
    local _, numChar = GetNumMacros()
    numChar = numChar or 0
    for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numChar do
        local name, iconTex, body = GetMacroInfo(i)
        if name then
            macros[#macros + 1] = { index = i, name = name, icon = iconTex, isGlobal = false }
        end
    end
    return macros
end

-------------------------------------------------------------------------------
--  Item enumeration (equipped on-use items)
--  Shows trinkets and other equipped items that have an on-use effect.
-------------------------------------------------------------------------------
local EQUIP_SLOTS = {
    { slot = 13, label = "Trinket 1" },
    { slot = 14, label = "Trinket 2" },
    { slot = 1,  label = "Head" },
    { slot = 2,  label = "Neck" },
    { slot = 15, label = "Back" },
    { slot = 10, label = "Hands" },
    { slot = 6,  label = "Waist" },
    { slot = 16, label = "Main Hand" },
    { slot = 17, label = "Off Hand" },
}

function ns.CC_GetEquippedItems()
    local items = {}
    local seen = {}
    -- Equipped on-use items
    for _, info in ipairs(EQUIP_SLOTS) do
        local itemID = GetInventoryItemID("player", info.slot)
        if itemID then
            local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
            if itemName then
                local spellName = C_Item.GetItemSpell(itemID)
                if spellName then
                    seen[itemID] = true
                    items[#items + 1] = {
                        name = itemName,
                        icon = itemIcon or GetInventoryItemTexture("player", info.slot),
                        itemSlot = info.slot,
                        slotLabel = info.label,
                        itemID = itemID,
                    }
                end
            end
        end
    end
    -- Bag on-use items (potions, healthstones, consumables, etc.)
    if C_Container then
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                if containerInfo and containerInfo.itemID and not seen[containerInfo.itemID] then
                    local itemID = containerInfo.itemID
                    local spellName = C_Item.GetItemSpell(itemID)
                    if spellName then
                        seen[itemID] = true
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
                        if itemName then
                            items[#items + 1] = {
                                name = itemName,
                                icon = itemIcon or containerInfo.iconFileID,
                                itemName = itemName,
                                itemID = itemID,
                            }
                        end
                    end
                end
            end
        end
    end
    return items
end

-------------------------------------------------------------------------------
--  Attribute generation helpers
-------------------------------------------------------------------------------
local function ModPrefixForAttr(modsStr)
    if not modsStr or modsStr == "" then return "" end
    return modsStr:lower()
end

-- Set a secure "type" attribute, optionally gated to out-of-combat only.
-- Unlike spell/macro (which carry their own [combat] conditional in the macro
-- text), menu/target are raw action types with no conditional, so when oocOnly
-- is set we drive the type attribute by combat state: the real action out of
-- combat, an inert "none" in combat.
--
-- "none" (not nil) matters: unit buttons set a default type2 = "click" wildcard
-- (the right-click menu via the secure proxy, see AttachSecureUnitMenu). The
-- secure resolver falls back to that wildcard whenever the specific type<N> is
-- nil, so clearing the attribute in combat would let the wildcard menu open
-- anyway. A non-nil unrecognized type ("none") suppresses the wildcard fallback
-- and performs no action.
--
-- Binding application is deferred out of combat (see the InCombatLockdown guards
-- in DoRegisterFrame / CC_ApplyBindings) so these driver calls never run in
-- combat. Unregister first so a stale driver can't survive a rebuild that
-- changed the binding type.
local function SetGatedType(frame, attrName, value, oocOnly)
    UnregisterAttributeDriver(frame, attrName)
    if oocOnly then
        RegisterAttributeDriver(frame, attrName, "[combat] none; " .. value)
    else
        frame:SetAttribute(attrName, value)
    end
end

-- Apply click (mouse button 1-5) attributes on a frame for one binding.
local function SetClickAttr(frame, parsed, actionType, spellOrMacro, macrotext, oocOnly)
    local prefix = ModPrefixForAttr(parsed.modifiers)
    local suffix = tostring(parsed.buttonNum)
    local typeAttr = prefix .. "type" .. suffix
    -- 12.0.7 gates a raw "togglemenu" on unit buttons (and an insecure reopen
    -- taints its protected items). Route the menu through the secure proxy via
    -- the ungated "click" action instead.
    if actionType == "togglemenu" and EllesmereUI.GetSecureMenuProxy then
        SetGatedType(frame, typeAttr, "click", oocOnly)
        frame:SetAttribute(prefix .. "clickbutton" .. suffix, EllesmereUI.GetSecureMenuProxy(frame))
        return
    end
    -- 12.0.7 also gates a raw "target" on unit buttons. Plain unmodified
    -- left-click (button 1) still targets natively via Blizzard's default
    -- Interaction click-binding, so leave that one direct; route every OTHER
    -- target binding (other buttons / modifiers) through the ungated "click"
    -- proxy. Keeps the change scoped to users who rebound target off left-click.
    if actionType == "target" and (suffix ~= "1" or prefix ~= "") and EllesmereUI.GetSecureTargetProxy then
        SetGatedType(frame, typeAttr, "click", oocOnly)
        frame:SetAttribute(prefix .. "clickbutton" .. suffix, EllesmereUI.GetSecureTargetProxy(frame))
        return
    end
    -- Raw action type. Only menu/target honor oocOnly via the combat driver;
    -- spell/macro carry their own conditional in the macro text.
    local gate = oocOnly and (actionType == "togglemenu" or actionType == "target")
    SetGatedType(frame, typeAttr, actionType, gate)
    if actionType == "spell" then
        frame:SetAttribute(prefix .. "spell" .. suffix, spellOrMacro or "")
    elseif actionType == "macro" then
        frame:SetAttribute(prefix .. "macrotext" .. suffix, macrotext or "")
    end
end

local function ClearClickAttr(frame, parsed)
    local prefix = ModPrefixForAttr(parsed.modifiers)
    local suffix = tostring(parsed.buttonNum)
    UnregisterAttributeDriver(frame, prefix .. "type" .. suffix)
    frame:SetAttribute(prefix .. "type" .. suffix, nil)
    frame:SetAttribute(prefix .. "spell" .. suffix, nil)
    frame:SetAttribute(prefix .. "macrotext" .. suffix, nil)
    frame:SetAttribute(prefix .. "clickbutton" .. suffix, nil)
end

-- Apply keyboard binding attributes on a frame (virtual button suffix).
local function SetKeyAttr(frame, idx, actionType, spellOrMacro, macrotext, oocOnly)
    local suffix = "eui_" .. idx
    local typeAttr = "type-" .. suffix
    -- Route a "menu" keybind through the secure proxy (see SetClickAttr).
    if actionType == "togglemenu" and EllesmereUI.GetSecureMenuProxy then
        SetGatedType(frame, typeAttr, "click", oocOnly)
        frame:SetAttribute("clickbutton-" .. suffix, EllesmereUI.GetSecureMenuProxy(frame))
        return
    end
    -- A "target" keybind is never plain left-click, so it always hits the 12.0.7
    -- gate -- route it through the ungated "click" proxy (see SetClickAttr).
    if actionType == "target" and EllesmereUI.GetSecureTargetProxy then
        SetGatedType(frame, typeAttr, "click", oocOnly)
        frame:SetAttribute("clickbutton-" .. suffix, EllesmereUI.GetSecureTargetProxy(frame))
        return
    end
    -- Only menu/target honor oocOnly via the combat driver; spell/macro carry
    -- their own conditional in the macro text.
    local gate = oocOnly and (actionType == "togglemenu" or actionType == "target")
    SetGatedType(frame, typeAttr, actionType, gate)
    if actionType == "spell" then
        frame:SetAttribute("spell-" .. suffix, spellOrMacro or "")
    elseif actionType == "macro" then
        frame:SetAttribute("macrotext-" .. suffix, macrotext or "")
    end
end

local function ClearKeyAttrs(frame, count)
    for i = 1, count do
        local suffix = "eui_" .. i
        UnregisterAttributeDriver(frame, "type-" .. suffix)
        frame:SetAttribute("type-" .. suffix, nil)
        frame:SetAttribute("spell-" .. suffix, nil)
        frame:SetAttribute("macrotext-" .. suffix, nil)
        frame:SetAttribute("clickbutton-" .. suffix, nil)
    end
end

-- Same for hovercast global button
local function ClearHoverAttrs(btn, count)
    for i = 1, count do
        local suffix = "eui_hc_" .. i
        UnregisterAttributeDriver(btn, "type-" .. suffix)
        btn:SetAttribute("type-" .. suffix, nil)
        btn:SetAttribute("spell-" .. suffix, nil)
        btn:SetAttribute("macrotext-" .. suffix, nil)
        btn:SetAttribute("unit-" .. suffix, nil)
    end
end

-- Resolve a binding to its action type + value for attribute setting.
-- Returns: actionType, spellOrMacroName, macrotext
local function ResolveBinding(b)
    if b.type == "target" then return "target", nil, nil end
    if b.type == "menu" then return "togglemenu", nil, nil end

    -- Check if we need macro wrapping (OOC, hovercast conditionals)
    local mt = BuildMacroText(b)
    if mt then
        return "macro", nil, mt
    end

    if b.type == "spell" then
        return "spell", ResolveCastSpellName(b), nil
    elseif b.type == "macro" then
        local macroName = b.macroName
        if macroName then
            local idx = GetMacroIndexByName(macroName)
            if idx and idx > 0 then
                local body = GetMacroBody(idx)
                return "macro", nil, body
            end
        end
        return nil, nil, nil
    end
    return nil, nil, nil
end

-------------------------------------------------------------------------------
--  OnEnter/OnLeave secure script generation (frame-based keyboard bindings)
-------------------------------------------------------------------------------
-- Returns: enterScript, leaveScript, kbClearLines
-- kbClearLines uses self:ClearBinding (for state driver where self=header)
-- leaveScript uses control:ClearBinding (for WrapScript where control=header)
local function GenerateKeyBindSnippets(bindings)
    local enter, leave, selfClear = {}, {}, {}
    local kbBindings = {}
    for i, b in ipairs(bindings) do
        if not b.hovercast then
            local parsed = ParseKeyString(b.key)
            if not parsed.isMouseButton or not parsed.buttonNum or parsed.buttonNum > 5 then
                kbBindings[#kbBindings + 1] = { binding = b, index = i, parsed = parsed }
            end
        end
    end
    if #kbBindings == 0 then return "", "", selfClear end

    enter[#enter + 1] = [[local name = self:GetName()]]
    enter[#enter + 1] = [[local target = name]]
    enter[#enter + 1] = [[if not name then]]
    enter[#enter + 1] = [[    local sc = control:GetFrameRef("bindProxy")]]
    enter[#enter + 1] = [[    sc:SetAttribute("unit", self:GetAttribute("unit"))]]
    enter[#enter + 1] = [[    target = "EUIClickCastBindProxy"]]
    enter[#enter + 1] = [[end]]

    -- Set/clear bindings on CONTROL (header) so both OnLeave and the
    -- state driver failsafe can clear them (same owner).
    for _, kb in ipairs(kbBindings) do
        local suffix = "eui_" .. kb.index
        enter[#enter + 1] = format([[control:SetBindingClick(true, %q, target, %q)]], kb.binding.key, suffix)
    end
    for _, kb in ipairs(kbBindings) do
        leave[#leave + 1] = format([[control:ClearBinding(%q)]], kb.binding.key)
        -- self:ClearBinding version for state driver context (self = header)
        selfClear[#selfClear + 1] = format([[self:ClearBinding(%q)]], kb.binding.key)
    end
    return table.concat(enter, "\n"), table.concat(leave, "\n"), selfClear
end

-------------------------------------------------------------------------------
--  Frame registration
-------------------------------------------------------------------------------
local wrappedFrames = {}
local externalFrames = {}
local ccHookInstalled = false

-- Clique interop. When EUI click-casting is OFF we hand our frames to Clique (or
-- any other ClickCastFrames consumer) by adding them to the global table, and we
-- never touch the frame's own click attributes -- so the right-click context menu
-- stays exactly as Blizzard set it (Clique only rebinds clicks the user bound in
-- their own Clique profile). These are no-ops once OUR proxy owns the global table
-- (click-casting enabled), because then EUI manages these frames itself.
local function AddFrameToClickCast(frame)
    if ccHookInstalled or not frame then return end
    if type(ClickCastFrames) ~= "table" then ClickCastFrames = {} end
    if ClickCastFrames[frame] == nil then ClickCastFrames[frame] = true end
end
local function RemoveFrameFromClickCast(frame)
    if ccHookInstalled or not frame then return end
    if type(ClickCastFrames) == "table" and ClickCastFrames[frame] then
        ClickCastFrames[frame] = nil  -- tells Clique to drop its bindings
    end
end

local function GetClickDirection()
    local cc = GetClickCastDB()
    -- Down-click only applies while click-casting is enabled. When disabled we
    -- must leave frames on the native "AnyUp" so the right-click context menu
    -- fires on the up-stroke exactly like Blizzard's default (a down-stroke
    -- togglemenu opens then instantly dismisses on the trailing up event).
    return (cc and cc.enabled and cc.downClick) and "AnyDown" or "AnyUp"
end

-- After a frame's click-cast bindings are applied, neutralize the no-click-cast
-- defaults so an UNBOUND left/right click does nothing. A unit button is created
-- with type1/*type1 = "target" and the menu wildcard *type2 = "click" (+
-- *clickbutton2). Clearing the wildcards is not enough on its own:
--   * The creation-time SPECIFIC type1 = "target" survives, and even if it were
--     cleared, plain left-click still targets via Blizzard's native ClickBindings
--     interaction -- which a nil type1 falls through to. So when nothing is bound
--     to plain left-click we write an inert type1 = "none": a non-nil,
--     unrecognized action the secure handler performs (i.e. nothing), which also
--     suppresses the wildcard / native-interaction fallback.
--   * Same idea for the menu on type2.
-- A button the user DID bind already wrote its own type<N> via SetClickAttr, so
-- we leave those alone. Own secure frame, only ever reached out of combat -> no taint.
local function NeutralizeDefaultClicks(frame, bindings)
    local b1, b2 = false, false
    for _, b in ipairs(bindings) do
        if not b.hovercast and b.key then
            local parsed = ParseKeyString(b.key)
            if parsed.isMouseButton and parsed.modifiers == "" then
                if parsed.buttonNum == 1 then b1 = true
                elseif parsed.buttonNum == 2 then b2 = true end
            end
        end
    end
    frame:SetAttribute("*type1", nil)
    frame:SetAttribute("*type2", nil)
    frame:SetAttribute("*clickbutton2", nil)
    if not b1 then frame:SetAttribute("type1", "none") end
    if not b2 then frame:SetAttribute("type2", "none") end
end

local function DoRegisterFrame(frame)
    if registeredFrames[frame] then return end
    if not frame or not frame.RegisterForClicks then return end
    if not header then return end
    -- Hard guarantee: while click-casting is disabled we touch ZERO frames --
    -- no RegisterForClicks, no WrapScript, no attribute writes. The user's
    -- click bindings (especially right-click) are never altered unless they
    -- explicitly enable the feature.
    local cc = GetClickCastDB()
    if not (cc and cc.enabled) then return end
    registeredFrames[frame] = true
    -- Capture the frame's native left-click target attrs once, before we touch
    -- anything, so DoUnregisterFrame restores them exactly (raid -> target, EUI
    -- unit frames -> none). Kept across register/unregister cycles.
    if originalTargetAttrs[frame] == nil then
        originalTargetAttrs[frame] = {
            type1     = frame:GetAttribute("type1"),
            starType1 = frame:GetAttribute("*type1"),
        }
    end
    frame:RegisterForClicks(GetClickDirection())
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    if not wrappedFrames[frame] then
        wrappedFrames[frame] = true
        header:WrapScript(frame, "OnEnter", [[
            -- Record the hovered EUI frame (the state-driver clear guard reads it),
            -- run the per-frame keyboard setup, then SET the hover override binding
            -- right now if it isn't already active -- so a keypress on arrival can
            -- never lose the race against the binding being set.
            eui_hoverframe = self
            control:RunFor(self, control:GetAttribute("eui_setup_onenter"))
            if not eui_hoveractive then
                control:RunAttribute("eui_hover_set")
                eui_hoveractive = true
            end
        ]])
        header:WrapScript(frame, "OnLeave", [[
            -- Forget the hovered frame (so the guard stops protecting it) and run
            -- the per-frame keyboard teardown. The hover binding itself is left to
            -- the guarded state driver so moving onto a non-EUI frame keeps it.
            if eui_hoverframe == self then eui_hoverframe = nil end
            control:RunFor(self, control:GetAttribute("eui_setup_onleave"))
        ]])
    end

    -- Apply current bindings to this frame immediately
    local bindings = GetActiveBindings()
    for i, b in ipairs(bindings) do
        if not b.hovercast and b.key then
            local parsed = ParseKeyString(b.key)
            local aType, spellName, macrotext = ResolveBinding(b)
            if aType then
                if parsed.isMouseButton and parsed.buttonNum and parsed.buttonNum <= 5 then
                    SetClickAttr(frame, parsed, aType, spellName, macrotext, b.oocOnly)
                else
                    SetKeyAttr(frame, i, aType, spellName, macrotext, b.oocOnly)
                end
            end
        end
    end

    -- Neutralize the default left-click target / right-click menu for any button
    -- the user did not bind (see NeutralizeDefaultClicks). Restored in
    -- DoUnregisterFrame on disable.
    NeutralizeDefaultClicks(frame, bindings)

end

local function DoUnregisterFrame(frame)
    if not registeredFrames[frame] then return end
    registeredFrames[frame] = nil

    -- Clear all click-cast attributes from this frame
    local bindings = GetActiveBindings()
    for i, b in ipairs(bindings) do
        if not b.hovercast and b.key then
            local parsed = ParseKeyString(b.key)
            if parsed.isMouseButton and parsed.buttonNum and parsed.buttonNum <= 5 then
                ClearClickAttr(frame, parsed)
            end
        end
    end
    ClearKeyAttrs(frame, lastBindingCount)

    -- Restore the frame's NATIVE left-click target attrs captured at register
    -- time: raid frames revert to type1/*type1 = "target", EUI unit frames revert
    -- to NO left-click target (their native state) rather than being forced to
    -- target. The menu's *type2 / *clickbutton2 are restored by AttachSecureUnitMenu.
    local o = originalTargetAttrs[frame]
    if o then
        frame:SetAttribute("type1", o.type1)
        frame:SetAttribute("*type1", o.starType1)
    else
        -- Never captured (shouldn't happen): fall back to the historical raid default.
        frame:SetAttribute("type1", "target")
        frame:SetAttribute("*type1", "target")
    end
    if EllesmereUI.AttachSecureUnitMenu then
        EllesmereUI.AttachSecureUnitMenu(frame)
    else
        frame:SetAttribute("type2", "togglemenu")
    end
    -- Fully revert the click registration and remove our secure OnEnter/OnLeave
    -- wraps so the frame behaves exactly as it did before click-casting touched
    -- it. Right-click must never be left broken after a disable.
    if frame.RegisterForClicks then frame:RegisterForClicks("AnyUp") end
    if frame.EnableMouseWheel then frame:EnableMouseWheel(false) end
    if wrappedFrames[frame] then
        wrappedFrames[frame] = nil
        if header and header.UnwrapScript then
            pcall(header.UnwrapScript, header, frame, "OnEnter")
            pcall(header.UnwrapScript, header, frame, "OnLeave")
        end
    end
end

function ns.CC_RegisterFrame(frame)
    -- Always record ownership so a later enable can pick the frame up, but do
    -- not touch the frame's click behavior while disabled.
    ownedFrames[frame] = true
    local cc = GetClickCastDB()
    if not (cc and cc.enabled) then
        -- EUI click-casting is OFF: defer to Clique by registering the frame in
        -- the global ClickCastFrames table. We do NOT alter the frame's own click
        -- attributes here, so the right-click context menu stays Blizzard-default
        -- unless the user's Clique profile rebinds it. (Restores Clique support
        -- that the "touch zero frames while disabled" guard removed.)
        AddFrameToClickCast(frame)
        return
    end
    if not ccInitialized then tinsert(regQueue, frame); return end
    if InCombatLockdown() then tinsert(regQueue, frame); return end
    DoRegisterFrame(frame)
end

function ns.CC_UnregisterFrame(frame)
    if InCombatLockdown() then tinsert(unregQueue, frame); return end
    DoUnregisterFrame(frame)
end

local function RegisterExternalFrame(frame)
    if not ccInitialized then tinsert(regQueue, frame); return end
    local cc = GetClickCastDB()
    -- Never touch external/Blizzard frames unless click-casting is BOTH enabled
    -- and set to capture all frames. (externalFrames already recorded the frame
    -- at the call sites, so enabling later still picks it up.)
    if not cc or not cc.enabled or not cc.allFrames then return end
    if InCombatLockdown() then tinsert(regQueue, frame); return end
    DoRegisterFrame(frame)
end

-- Forward declaration: defined further below (after the per-frame registration
-- helpers). Declared here so CC_SetAllFrames can register the static Blizzard
-- frame list when "All Unit Frames" is toggled on at runtime.
local RegisterBlizzardFrames

function ns.CC_SetAllFrames(enabled)
    local cc = GetClickCastDB()
    if not cc then return end
    cc.allFrames = enabled
    if InCombatLockdown() then pendingApply = true; return end
    if enabled then
        -- Grab the static Blizzard list (PlayerFrame/TargetFrame/party/etc.) and
        -- install the CompactUnitFrame hook. Idempotent: self-gates on
        -- enabled+allFrames, DoRegisterFrame skips already-registered frames,
        -- and the CUF hook installs at most once.
        if RegisterBlizzardFrames then RegisterBlizzardFrames() end
        for frame in pairs(externalFrames) do
            if not registeredFrames[frame] and not ownedFrames[frame] then
                DoRegisterFrame(frame)
            end
        end
        ns.CC_ApplyBindings()
    else
        for frame in pairs(registeredFrames) do
            if not ownedFrames[frame] then DoUnregisterFrame(frame) end
        end
    end
end

function ns.CC_SetDownClick(enabled)
    local cc = GetClickCastDB()
    if not cc then return end
    cc.downClick = enabled
    if InCombatLockdown() then pendingApply = true; return end
    -- Re-register clicks on all frames with the new direction
    local dir = enabled and "AnyDown" or "AnyUp"
    for frame in pairs(registeredFrames) do
        if frame.RegisterForClicks then
            frame:RegisterForClicks(dir)
        end
    end
end

-------------------------------------------------------------------------------
--  ClickCastFrames hook
-------------------------------------------------------------------------------
local function SetupClickCastFramesHook()
    -- Install exactly once, and only after the user enables click-casting (see
    -- CC_Init / CC_SetEnabled). A never-enabled install would leave a fresh
    -- user's default disabled, so the global ClickCastFrames table is never
    -- replaced and Clique/Blizzard are never perturbed.
    if ccHookInstalled then return end
    ccHookInstalled = true
    local oldCCF = ClickCastFrames
    ClickCastFrames = setmetatable({}, {
        __newindex = function(t, frame, value)
            if value == nil or value == false then
                externalFrames[frame] = nil
                if not ownedFrames[frame] then ns.CC_UnregisterFrame(frame) end
            else
                externalFrames[frame] = true
                if not ownedFrames[frame] then RegisterExternalFrame(frame) end
            end
        end,
        __index = function(t, frame) return registeredFrames[frame] or nil end,
    })
    if oldCCF then
        for frame, val in pairs(oldCCF) do
            if val then
                externalFrames[frame] = true
                if not ownedFrames[frame] then RegisterExternalFrame(frame) end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Apply bindings to all registered frames + global button
-------------------------------------------------------------------------------
local prevBindings = {}

function ns.CC_ApplyBindings()
    if not ccInitialized then pendingApply = true; return end
    if InCombatLockdown() then pendingApply = true; return end

    -- Self-heal any legacy non-canonical modifier-order keys before reading the
    -- active set (so GetActiveBindings' key de-dup also sees canonical keys).
    NormalizeSavedBindingKeys()

    local bindings = GetActiveBindings()

    -- Split into frame-based and hovercast
    local frameBindings = {}
    local hoverBindings = {}
    for i, b in ipairs(bindings) do
        if b.hovercast then
            hoverBindings[#hoverBindings + 1] = { b = b, idx = i }
        else
            frameBindings[#frameBindings + 1] = { b = b, idx = i }
        end
    end

    ---------------------------------------------------------------
    -- Frame-based bindings
    ---------------------------------------------------------------
    -- Clear old frame attributes
    for frame in pairs(registeredFrames) do
        for _, pb in ipairs(prevBindings) do
            if not pb.b.hovercast then
                local parsed = ParseKeyString(pb.b.key)
                if parsed.isMouseButton and parsed.buttonNum and parsed.buttonNum <= 5 then
                    ClearClickAttr(frame, parsed)
                end
            end
        end
        ClearKeyAttrs(frame, lastBindingCount)
    end
    ClearKeyAttrs(bindProxy, lastBindingCount)

    -- Apply new frame-based bindings
    for frame in pairs(registeredFrames) do
        for _, fb in ipairs(frameBindings) do
            local parsed = ParseKeyString(fb.b.key)
            local aType, spellName, macrotext = ResolveBinding(fb.b)
            if aType then
                if parsed.isMouseButton and parsed.buttonNum and parsed.buttonNum <= 5 then
                    SetClickAttr(frame, parsed, aType, spellName, macrotext, fb.b.oocOnly)
                else
                    SetKeyAttr(frame, fb.idx, aType, spellName, macrotext, fb.b.oocOnly)
                end
            else
            end
        end
        -- Re-neutralize the unbound left/right defaults after the rebuild (the
        -- clear pass above may have stripped a previous binding's type<N>).
        NeutralizeDefaultClicks(frame, bindings)
    end
    -- Bind proxy gets keyboard attrs too (unnamed frame fallback)
    for _, fb in ipairs(frameBindings) do
        local parsed = ParseKeyString(fb.b.key)
        local aType, spellName, macrotext = ResolveBinding(fb.b)
        if aType and (not parsed.isMouseButton or not parsed.buttonNum or parsed.buttonNum > 5) then
            SetKeyAttr(bindProxy, fb.idx, aType, spellName, macrotext, fb.b.oocOnly)
        end
    end

    -- Generate secure OnEnter/OnLeave scripts
    local enterScript, leaveScript, kbClearLines = GenerateKeyBindSnippets(bindings)
    header:SetAttribute("eui_setup_onenter", enterScript)
    header:SetAttribute("eui_setup_onleave", leaveScript)

    ---------------------------------------------------------------
    -- Hovercast + frame-based keyboard failsafe, unified on ONE header state
    -- driver (eui_cc) reacting to [@mouseover,exists].
    --
    --  * The hover override binding is SET the instant you hover an EUI frame, in
    --    the frame's secure OnEnter (eui_hover_set), so a keypress on arrival can
    --    never lose the race against the binding being set. (This is the part the
    --    old design lacked: it relied solely on the state driver to set, which
    --    lags on arrival and -- worse -- could stay stuck cleared.)
    --  * The state driver also SETS on "1", covering NON-EUI mouseover targets
    --    (nameplates / Blizzard frames that have no OnEnter wrap), and on "0"
    --    CLEARS the hover bindings AND runs the frame-based keyboard failsafe.
    --  * The "0" clear is GUARDED: skipped while the last-hovered EUI frame is
    --    still physically under the cursor, so a transient [@mouseover,exists]==0
    --    (a churning unit token -- common in follower dungeons) cannot strand the
    --    binding cleared (the "stuck until I re-mouseover" report).
    --  * eui_hoveractive gates the SetBindingClick work to the become-active edge
    --    only, so sweeping the mouse across frames does zero extra binding writes
    --    (same cadence as before -- no per-hover cost).
    -- globalBtn stays the @mouseover click target; its macro re-evaluates at cast
    -- time, so a press always fires on whatever the cursor is actually over.
    ---------------------------------------------------------------
    -- Retire the previous driver(s) and wipe the override bindings the prior
    -- build owned (the teardown script also resets eui_hoveractive), then rebuild.
    UnregisterStateDriver(header, "eui_cc")
    UnregisterStateDriver(header, "eui_fbs")     -- legacy: split failsafe driver
    UnregisterStateDriver(globalBtn, "eui_mo")   -- legacy: globalBtn hover driver
    if header._ccClearScript then
        pcall(function() header:Execute(header._ccClearScript) end)
    end
    ClearHoverAttrs(globalBtn, lastHoverCount)

    local hoverSetLines = {}
    local hoverClearLines = {}
    local gbName = globalBtn:GetName()

    for hi, hb in ipairs(hoverBindings) do
        local suffix = "eui_hc_" .. hi
        local aType, spellName, macrotext = ResolveBinding(hb.b)
        if aType then
            local mt
            if aType == "spell" then
                mt = BuildMacroText(hb.b)
                if not mt then
                    mt = "/cast [@mouseover" .. MOUNT_GUARD .. "] " .. (spellName or "")
                end
            elseif aType == "macro" then
                mt = macrotext or ""
            end

            if mt then
                globalBtn:SetAttribute("type-" .. suffix, "macro")
                globalBtn:SetAttribute("macrotext-" .. suffix, mt)
            else
                -- menu/target carry no macro conditional, so honor oocOnly via
                -- the combat driver (present out of combat, cleared in combat).
                SetGatedType(globalBtn, "type-" .. suffix, aType,
                    hb.b.oocOnly and (aType == "togglemenu" or aType == "target"))
            end
            globalBtn:SetAttribute("unit-" .. suffix, "mouseover")
            -- Route the key/button to the global button for EVERY action type, not
            -- just spell/macro. Hovercast "Context Menu" (togglemenu) and "Target"
            -- bindings previously set their attributes but were never bound to a
            -- click, so the keypress did nothing. The global button is a
            -- SecureActionButton, which the 12.0.7 SecureUnitButton menu gate does
            -- NOT touch, so togglemenu opens the menu here once the click is routed.
            hoverSetLines[#hoverSetLines + 1] = string.format(
                [[self:SetBindingClick(true, %q, %q, %q)]],
                hb.b.key, gbName, suffix)
            hoverClearLines[#hoverClearLines + 1] = string.format(
                [[self:ClearBinding(%q)]], hb.b.key)
        end
    end

    -- Hover set/clear bodies. Stored as header attributes and invoked via
    -- RunAttribute from both the OnEnter wrap and the state driver, so they
    -- always run with self = header (the owner of the override bindings).
    header:SetAttribute("eui_hover_set", table.concat(hoverSetLines, "\n"))
    header:SetAttribute("eui_hover_clear", table.concat(hoverClearLines, "\n"))

    -- Teardown executed on the NEXT rebuild (line ~1311): drop every override
    -- binding this header owns and reset the active flag. self:ClearBindings()
    -- wipes them ALL in one shot rather than replaying a per-key ClearBinding
    -- list. The per-key list was fragile: when the LAST hover/keyboard binding is
    -- unbound, the state driver is not re-registered (the gate just below), so any
    -- override the per-key teardown missed -- e.g. one still active because the
    -- user was hovering a frame when they unbound -- had nothing left to clear it
    -- and kept firing until /reload (the unbind-doesn't-take-effect bug). The
    -- header owns only click-cast overrides and they re-establish on the next
    -- hover, so a full wipe is always safe.
    header._ccClearScript = "self:ClearBindings()\neui_hoveractive = false"

    if #hoverSetLines > 0 or #kbClearLines > 0 then
        local fbFailsafe = table.concat(kbClearLines, "\n")
        header:SetAttribute("_onstate-eui_cc", [[
            if newstate == "1" then
                if not eui_hoveractive then
                    self:RunAttribute("eui_hover_set")
                    eui_hoveractive = true
                end
            elseif not (eui_hoverframe and eui_hoverframe:IsUnderMouse()) then
                self:RunAttribute("eui_hover_clear")
                eui_hoveractive = false
                ]] .. fbFailsafe .. [[

            end
        ]])
        RegisterStateDriver(header, "eui_cc", "[@mouseover,exists] 1; 0")
    end

    -- Store for next cleanup
    lastBindingCount = #bindings
    lastHoverCount = #hoverBindings
    prevBindings = {}
    for i, b in ipairs(bindings) do
        prevBindings[i] = { b = b, idx = i }
    end
end

-------------------------------------------------------------------------------
--  Binding CRUD
-------------------------------------------------------------------------------
function ns.CC_AddSpecBinding(binding)
    local cc = GetClickCastDB()
    if not cc then return end
    local specID = GetCurrentSpecID()
    if not specID then return end
    if not cc.specs[specID] then cc.specs[specID] = {} end
    if binding.enabled == nil then binding.enabled = true end
    tinsert(cc.specs[specID], binding)
    ns.CC_ApplyBindings()
end

function ns.CC_RemoveSpecBinding(index)
    local cc = GetClickCastDB()
    if not cc then return end
    local specID = GetCurrentSpecID()
    if not specID or not cc.specs[specID] then return end
    tremove(cc.specs[specID], index)
    ns.CC_ApplyBindings()
end

function ns.CC_AddGlobalBinding(binding)
    local cc = GetClickCastDB()
    if not cc then return end
    if binding.enabled == nil then binding.enabled = true end
    tinsert(cc.globals, binding)
    ns.CC_ApplyBindings()
end

function ns.CC_RemoveGlobalBinding(index)
    local cc = GetClickCastDB()
    if not cc then return end
    tremove(cc.globals, index)
    ns.CC_ApplyBindings()
end

function ns.CC_SetGlobalBindingKey(bindingType, newKey)
    local cc = GetClickCastDB()
    if not cc then return end
    for _, b in ipairs(cc.globals) do
        if b.type == bindingType then
            b.key = newKey
            break
        end
    end
    ns.CC_ApplyBindings()
end

function ns.CC_ToggleBinding(binding)
    binding.enabled = not binding.enabled
    ns.CC_ApplyBindings()
end

function ns.CC_FindBinding(keyStr)
    for _, b in ipairs(GetActiveBindings()) do
        if b.key == keyStr then return b end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Expose getters
-------------------------------------------------------------------------------
ns.CC_GetActiveBindings  = GetActiveBindings
ns.CC_GetSpecBindings    = GetSpecBindings
ns.CC_GetGlobalBindings  = GetGlobalBindings
ns.CC_GetCurrentSpecID   = GetCurrentSpecID
ns.CC_GetCurrentSpecName = GetCurrentSpecName
ns.CC_GetCurrentSpecIcon = GetCurrentSpecIcon
ns.CC_GetClickCastDB     = GetClickCastDB

-- Find all bindings (excluding the given one) that use the same key.
-- Returns a list of binding names, or empty table.
local function FindKeyConflicts(keyStr, excludeBinding)
    if not keyStr then return {} end
    local conflicts = {}
    local cc = GetClickCastDB()
    if not cc then return conflicts end
    for _, b in ipairs(cc.globals) do
        if b ~= excludeBinding and b.key == keyStr then
            conflicts[#conflicts + 1] = ns.CC_GetBindingName(b)
        end
    end
    -- Only check the active spec's bindings (other specs are never active simultaneously)
    local specIdx = GetSpecialization and GetSpecialization()
    local specID = specIdx and select(1, GetSpecializationInfo(specIdx))
    local activeList = specID and cc.specs[specID]
    if activeList then
        for _, b in ipairs(activeList) do
            if b ~= excludeBinding and b.key == keyStr then
                conflicts[#conflicts + 1] = ns.CC_GetBindingName(b)
            end
        end
    end
    return conflicts
end

-------------------------------------------------------------------------------
--  Enable / disable sweep
-------------------------------------------------------------------------------
-- Register the Blizzard default unit frames + party pool + dynamic raid frames.
-- Self-gated on enabled+allFrames (via RegisterExternalFrame); the
-- CompactUnitFrame hook installs at most once.
local blizzHookInstalled = false
-- Assigns to the forward-declared upvalue above (so CC_SetAllFrames can call it).
function RegisterBlizzardFrames()
    local cc = GetClickCastDB()
    if not (cc and cc.enabled and cc.allFrames) then return end
    local blizzNames = {
        "PlayerFrame", "TargetFrame", "TargetFrameToT",
        "FocusFrame", "FocusFrameToT", "PetFrame",
    }
    for i = 1, 5 do blizzNames[#blizzNames + 1] = "Boss" .. i .. "TargetFrame" end
    for _, name in ipairs(blizzNames) do
        local f = _G[name]
        if f then
            externalFrames[f] = true
            RegisterExternalFrame(f)
        end
    end
    -- Party frames (retail pool)
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for mf in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            externalFrames[mf] = true
            RegisterExternalFrame(mf)
            if mf.PetFrame then
                externalFrames[mf.PetFrame] = true
                RegisterExternalFrame(mf.PetFrame)
            end
        end
    end
    -- CompactUnitFrames (Blizzard raid frames) created dynamically. Install the
    -- hook once; it self-gates via RegisterExternalFrame (enabled+allFrames).
    if not blizzHookInstalled and CompactUnitFrame_SetUpFrame then
        blizzHookInstalled = true
        hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
            if not frame then return end
            if frame.IsForbidden and frame:IsForbidden() then return end
            local ok, name = pcall(frame.GetName, frame)
            if ok and name and not name:match("^NamePlate") then
                externalFrames[frame] = true
                RegisterExternalFrame(frame)
            end
        end)
    end
end

-- Toggle click-casting with a full register / restore sweep. Enabling installs
-- the global hook and registers owned + external frames. Disabling returns
-- EVERY touched frame to its native click behavior so right-click is never left
-- broken. Defers to PLAYER_REGEN_ENABLED in combat.
function ns.CC_SetEnabled(enabled)
    local cc = GetClickCastDB()
    if not cc then return end
    cc.enabled = enabled
    if not ccInitialized then return end
    if InCombatLockdown() then pendingSetEnabled = enabled; pendingApply = true; return end
    if enabled then
        -- Hand our frames back from Clique before we take them over, so Clique
        -- drops its bindings and we do not double-bind. Must run BEFORE the proxy
        -- replaces the global table (RemoveFrameFromClickCast no-ops once it has).
        for frame in pairs(ownedFrames) do RemoveFrameFromClickCast(frame) end
        SetupClickCastFramesHook()
        -- Register owned EUI frames.
        for frame in pairs(ownedFrames) do
            if not registeredFrames[frame] then DoRegisterFrame(frame) end
        end
        -- Register external/Blizzard frames when allFrames is set.
        if cc.allFrames then
            RegisterBlizzardFrames()
            for frame in pairs(externalFrames) do
                if not registeredFrames[frame] and not ownedFrames[frame] then
                    DoRegisterFrame(frame)
                end
            end
        end
        ns.CC_ApplyBindings()
    else
        -- Clear applied attributes first (CC_ApplyBindings uses the last-applied
        -- binding set), then fully revert every registered frame to native
        -- behavior (restores type1/type2, AnyUp, mousewheel, removes wraps).
        ns.CC_ApplyBindings()
        local list = {}
        for frame in pairs(registeredFrames) do list[#list + 1] = frame end
        for _, frame in ipairs(list) do DoUnregisterFrame(frame) end
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local function OnCCEvent(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        local cc = GetClickCastDB()
        -- Apply a deferred enable/disable sweep that was requested during combat.
        if pendingSetEnabled ~= nil then
            local v = pendingSetEnabled
            pendingSetEnabled = nil
            ns.CC_SetEnabled(v)
        end
        local enabled = cc and cc.enabled
        local allF = cc and cc.allFrames
        for _, frame in ipairs(regQueue) do
            -- Never register while disabled (DoRegisterFrame also self-gates).
            if enabled and (ownedFrames[frame] or allF) then DoRegisterFrame(frame) end
        end
        wipe(regQueue)
        for _, frame in ipairs(unregQueue) do DoUnregisterFrame(frame) end
        wipe(unregQueue)
        if pendingApply then pendingApply = false; ns.CC_ApplyBindings() end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not InCombatLockdown() then ns.CC_ApplyBindings() else pendingApply = true end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Reapply bindings after zone/loading screen to clear any stuck
        -- frame-based bindings (OnLeave may not fire during transitions)
        if not InCombatLockdown() then ns.CC_ApplyBindings() else pendingApply = true end
    end
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
function ns.CC_Init()
    if ccInitialized then return end
    if not ns.db then return end
    GetClickCastDB()

    header = CreateFrame("Frame", "EUIClickCastHeader", UIParent, "SecureHandlerBaseTemplate")
    ns._ccHeader = header

    bindProxy = CreateFrame("Button", "EUIClickCastBindProxy", UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    bindProxy:RegisterForClicks("AnyDown", "AnyUp")
    bindProxy:SetSize(1, 1); bindProxy:SetAlpha(0)
    bindProxy:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    bindProxy:Show()
    ns._ccBindProxy = bindProxy
    header:SetFrameRef("bindProxy", bindProxy)

    globalBtn = CreateFrame("Button", "EUIClickCastGlobalBtn", UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    globalBtn:RegisterForClicks("AnyDown", "AnyUp")
    globalBtn:EnableMouse(false)
    globalBtn:SetSize(1, 1); globalBtn:SetAlpha(0)
    globalBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 100)
    globalBtn:Show()
    ns._ccGlobalBtn = globalBtn

    header:SetAttribute("eui_setup_onenter", "")
    header:SetAttribute("eui_setup_onleave", "")
    header:SetAttribute("eui_hover_set", "")
    header:SetAttribute("eui_hover_clear", "")

    ccEventFrame = CreateFrame("Frame")
    ccEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    ccEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ccEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ccEventFrame:SetScript("OnEvent", OnCCEvent)

    ccInitialized = true

    -- Only touch frames when click-casting is enabled. A fresh/default install
    -- (enabled=false) registers nothing: the global ClickCastFrames table is
    -- never replaced, no RegisterForClicks, no WrapScript -- the user's clicks
    -- (especially right-click) stay exactly as Blizzard set them. Enabling
    -- later runs the same sweep via CC_SetEnabled.
    local cc = GetClickCastDB()
    if cc and cc.enabled then
        SetupClickCastFramesHook()
        for _, frame in ipairs(regQueue) do DoRegisterFrame(frame) end
        wipe(regQueue)
        ns.CC_ApplyBindings()
        RegisterBlizzardFrames()
    else
        wipe(regQueue)
    end
end

-------------------------------------------------------------------------------
--  Options Page Builder
--  Layout: Left sidebar (Global) | Center (Options + Per-Binding) | Right sidebar (Spec)
--  Sidebars are 1:1 replica of Buff Manager tile style.
-------------------------------------------------------------------------------
function ns.CC_BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local db = ns.db
    if not db then return 0 end

    local cc = GetClickCastDB()
    if not cc then return 0 end

    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local outlineFlag = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("raidFrames")) or ""
    local useShadow = not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("raidFrames")
    local accentColor = EllesmereUI.ACCENT_COLOR or { r = 0.05, g = 0.82, b = 0.62 }

    -- The page root bypasses the scroll system (like BM does)
    local scrollFrame = EllesmereUI._scrollFrame
    if not scrollFrame then return 0 end
    local visibleH = scrollFrame:GetHeight()
    local parentW = scrollFrame:GetWidth()

    -- Guard: clean up old root before creating new (prevents frame accumulation)
    if ns._ccRoot then ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil) end
    if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
    if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
    -- QB popup is NOT cleaned up here -- it stays open during rebuilds
    if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end

    local root = CreateFrame("Frame", nil, scrollFrame)
    root:SetSize(parentW, visibleH)
    root:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    root:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    ns._ccRoot = root

    local TILE_H       = 56
    local ICON_SZ      = 36
    local ADD_BTN_H    = 30
    local ADD_BTN_PAD  = 10
    local SPELL_STRIP_W = 57  -- narrow spell icon strip (outside the root, on EUI window edge)
    local SIDEBAR_PCT  = 0.24
    local sidebarW     = floor(parentW * SIDEBAR_PCT)
    local centerW      = parentW - sidebarW * 2

    local function MakeFont(p, size, r, g, b, a)
        local fs = p:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, outlineFlag == "" and useShadow) end
        fs:SetFont(fontPath, size, outlineFlag)
        fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
        return fs
    end

    -- Selected binding state (persists across rebuilds via namespace)
    local selectedBinding = nil
    local selectedSide = ns._ccSelSide
    local selectedIndex = ns._ccSelIndex
    -- Resolve the binding reference from stored side+index
    if selectedSide == "global" and selectedIndex then
        selectedBinding = cc.globals[selectedIndex]
    elseif selectedSide == "spec" and selectedIndex then
        local sb = GetSpecBindings()
        selectedBinding = sb[selectedIndex]
    end

    -- Lookup sets for already-bound spells/macros/items (used to dim in popups + strip)
    local boundSpells, boundMacros, boundItems = {}, {}, {}
    for _, b in ipairs(GetGlobalBindings()) do
        if b.spell then boundSpells[b.spell] = true end
        if b.macroName then boundMacros[b.macroName] = true end
        if b.itemSlot then boundItems[b.itemSlot] = true end
    end
    for _, b in ipairs(GetSpecBindings()) do
        if b.spell then boundSpells[b.spell] = true end
        if b.macroName then boundMacros[b.macroName] = true end
        if b.itemSlot then boundItems[b.itemSlot] = true end
    end
    -- Dim spells covered by bound presets for the player's class
    local _, pClass = UnitClass("player")
    local hasDispel, hasExternal, hasDynamicRez = false, false, false
    for _, gb in ipairs(GetGlobalBindings()) do
        if gb.enabled and gb.key then
            if gb.type == "dispel" then hasDispel = true end
            if gb.type == "external" then hasExternal = true end
            if gb.type == "dynamicrez" then hasDynamicRez = true end
        end
    end
    if hasDispel then
        for _, sp in ipairs(DISPEL_SPELLS) do
            if sp.class == pClass then
                -- Match the localized name stored by the spell picker so the
                -- "already bound" dimming works on non-English clients.
                local n = (C_Spell.GetSpellName and C_Spell.GetSpellName(sp.id)) or sp.name
                boundSpells[n] = true
            end
        end
    end
    if hasExternal then
        for _, sp in ipairs(EXTERNAL_SPELLS) do
            if sp.class == pClass then
                local n = (C_Spell.GetSpellName and C_Spell.GetSpellName(sp.id)) or sp.name
                boundSpells[n] = true
            end
        end
    end
    if hasDynamicRez then
        local kit = REZ_BY_CLASS[pClass]
        if kit then
            for _, sid in pairs(kit) do
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                if name then boundSpells[name] = true end
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Keybind capture button builder (Party Mode pattern)
    ---------------------------------------------------------------------------
    local function BuildKeybindButton(parentFrame, width, getCurrentKey, onKeySet, onKeyClear)
        local KB_H = 30
        local kbBtn = CreateFrame("Button", nil, parentFrame)
        kbBtn:SetSize(width, KB_H)
        kbBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 2)
        kbBtn:RegisterForClicks("AnyUp")
        local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND",
            EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        kbBg:SetAllPoints()
        kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local kbLbl = EllesmereUI.MakeFont(kbBtn, 13, nil, 1, 1, 1)
        kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
        kbLbl:SetPoint("CENTER")

        local listening = false
        local function RefreshLabel()
            local key = getCurrentKey and getCurrentKey()
            kbLbl:SetText(key and ns.CC_FormatKey(key) or EllesmereUI.L("Not Bound"))
        end
        RefreshLabel()

        -- Stop capturing: disable keyboard + mouse wheel so the page scrolls
        -- normally again when this button is not actively listening.
        local function StopListening()
            listening = false
            kbBtn:EnableKeyboard(false)
            kbBtn:EnableMouseWheel(false)
            RefreshLabel()
        end

        kbBtn:SetScript("OnClick", function(self, button)
            if not listening then
                if button == "LeftButton" then
                    listening = true
                    kbLbl:SetText(EllesmereUI.L("Press a key, click, or scroll..."))
                    kbBtn:EnableKeyboard(true)
                    kbBtn:EnableMouseWheel(true)
                elseif button == "RightButton" then
                    if onKeyClear then onKeyClear() end
                    RefreshLabel()
                end
                return
            end
            -- While listening, any click is a binding (including bare left-click).
            local mods = ns.CC_GetModifierPrefix()
            local normalized = MOUSE_BUTTON_MAP[button] or ("BUTTON" .. (button:match("%d+") or button))
            if onKeySet then onKeySet(mods .. normalized) end
            StopListening()
        end)

        kbBtn:SetScript("OnKeyDown", function(self, key)
            if not listening then self:SetPropagateKeyboardInput(true); return end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
               or key == "LALT" or key == "RALT" then
                self:SetPropagateKeyboardInput(true); return
            end
            self:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" then
                StopListening(); return
            end
            local mods = ns.CC_GetModifierPrefix()
            if onKeySet then onKeySet(mods .. key) end
            StopListening()
        end)

        -- Scroll wheel binding -- only via this capture button, never Quickbind.
        -- Mouse wheel is enabled only while listening, so the page scrolls
        -- normally otherwise. MOUSEWHEELUP/DOWN bind through the keybind path
        -- (SetBindingClick), same as keyboard keys.
        kbBtn:SetScript("OnMouseWheel", function(self, delta)
            if not listening then return end
            local mods = ns.CC_GetModifierPrefix()
            local wheel = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
            if onKeySet then onKeySet(mods .. wheel) end
            StopListening()
        end)

        kbBtn:SetScript("OnEnter", function(self)
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, 0.3) end
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Left-click to set keybind.\nRight-click to clear."))
        end)
        kbBtn:SetScript("OnLeave", function()
            if listening then return end
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
            EllesmereUI.HideWidgetTooltip()
        end)

        parentFrame:SetScript("OnHide", function()
            if listening then StopListening() end
        end)

        kbBtn._refresh = RefreshLabel
        return kbBtn
    end

    ---------------------------------------------------------------------------
    --  Sidebar tile builder (BM replica)
    ---------------------------------------------------------------------------
    local function BuildTile(scrollChild, tileY, binding, isSelected, side, idx, onSelect, onDelete)
        local tile = CreateFrame("Button", nil, scrollChild)
        tile:SetSize(sidebarW, TILE_H)
        tile:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, tileY)
        tile:SetFrameLevel(scrollChild:GetFrameLevel() + 1)

        local tileBg = tile:CreateTexture(nil, "BACKGROUND")
        tileBg:SetAllPoints()
        tileBg:SetColorTexture(1, 1, 1, isSelected and 0.06 or 0)

        if isSelected then
            local accent = tile:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, TILE_H)
            accent:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
            accent:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
        end

        -- Icon
        local iconFrame = CreateFrame("Frame", nil, tile)
        iconFrame:SetSize(ICON_SZ, ICON_SZ)
        iconFrame:SetPoint("LEFT", tile, "LEFT", 8, 0)
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetTexture(ns.CC_GetBindingIcon(binding))
        if PP then
            local iBdr = CreateFrame("Frame", nil, iconFrame)
            iBdr:SetAllPoints(); iBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            PP.CreateBorder(iBdr, 0, 0, 0, 0.6, 1)
        end

        -- Title
        local textX = 8 + ICON_SZ + 8
        local title = MakeFont(tile, 13, 1, 1, 1, 1)
        title:SetPoint("TOPLEFT", tile, "TOPLEFT", textX, -8)
        title:SetPoint("RIGHT", tile, "RIGHT", -30, 0)
        title:SetJustifyH("LEFT"); title:SetWordWrap(false)
        title:SetText(EllesmereUI.L(ns.CC_GetBindingName(binding)))

        -- Keybind subtitle
        local keySub = MakeFont(tile, 11, 0.75, 0.75, 0.75, 0.65)
        keySub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        keySub:SetPoint("RIGHT", tile, "RIGHT", -30, 0)
        keySub:SetJustifyH("LEFT"); keySub:SetWordWrap(false)
        keySub:SetText(binding.key and ns.CC_FormatKey(binding.key) or EllesmereUI.L("Not Bound"))

        -- Delete button (top-right, where toggle used to be)
        if onDelete then
            local delBtn = CreateFrame("Button", nil, tile)
            delBtn:SetSize(16, 16)
            delBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
            delBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
            local delTex = delBtn:CreateTexture(nil, "ARTWORK")
            delTex:SetAllPoints()
            delTex:SetAtlas("common-icon-delete")
            delTex:SetDesaturated(true)
            delTex:SetVertexColor(0.75, 0.75, 0.75)
            delTex:SetAlpha(0.5)
            delBtn:SetScript("OnEnter", function() delTex:SetAlpha(0.9) end)
            delBtn:SetScript("OnLeave", function() delTex:SetAlpha(0.5) end)
            delBtn:SetScript("OnClick", function() onDelete(idx) end)
        end

        -- Separator
        local sep = tile:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
        sep:SetColorTexture(1, 1, 1, 0.04)

        -- Interaction
        tile:SetScript("OnClick", function() onSelect(side, idx) end)
        tile:SetScript("OnEnter", function() if not isSelected then tileBg:SetColorTexture(1, 1, 1, 0.04) end end)
        tile:SetScript("OnLeave", function() if not isSelected then tileBg:SetColorTexture(1, 1, 1, 0) end end)

        return tile
    end

    ---------------------------------------------------------------------------
    --  Icon grid popup builder
    ---------------------------------------------------------------------------
    -- side: "left" or "right". sidebarFrame: the sidebar outer frame for anchoring.
    local function BuildIconGridPopup(anchorBtn, sidebarFrame, side, items, onSelect)
        local GRID_COLS = 5
        local ICON_SZ2 = 32
        local CELL_W = 48         -- horizontal slot width (text truncates here)
        local COL_GAP = 19       -- horizontal gap between columns
        local LABEL_FONT = 10
        local LABEL_GAP = 4      -- gap between label bottom and icon top
        local ROW_GAP = 8        -- gap between rows (contains divider)
        local DIV_H = 1
        local INSET = 15

        -- Pre-compute per-row: does any item in this row have a name?
        local gridRows = math.ceil(#items / GRID_COLS)
        local rowHasText = {}
        for r = 0, gridRows - 1 do
            rowHasText[r] = false
            for c = 0, GRID_COLS - 1 do
                local idx = r * GRID_COLS + c + 1
                if items[idx] and items[idx].name and items[idx].name ~= "" then
                    rowHasText[r] = true; break
                end
            end
        end

        -- Compute row Y positions and heights
        -- Label height: ~14px for font 10. Measure once.
        local LABEL_H = 14
        local rowY = {}     -- [r] = top Y of this row (negative, from top)
        local rowH = {}     -- [r] = height of this row
        local curY = 0
        for r = 0, gridRows - 1 do
            if r > 0 then curY = curY + ROW_GAP end  -- gap (+ divider) between rows
            rowY[r] = -curY
            if rowHasText[r] then
                rowH[r] = LABEL_H + LABEL_GAP + ICON_SZ2
            else
                rowH[r] = ICON_SZ2
            end
            curY = curY + rowH[r]
        end
        local innerW = GRID_COLS * CELL_W + (GRID_COLS - 1) * COL_GAP
        local innerH = max(curY, 40)

        local popupW = innerW + INSET * 2
        local rootBottom = root:GetBottom() or 0
        local btnTop = anchorBtn:GetTop() or 0
        local maxH = btnTop - rootBottom
        local popupH = min(innerH + INSET * 2, maxH, 400)

        local popup = CreateFrame("Frame", nil, UIParent)
        popup:Hide()  -- start hidden so Show() triggers OnShow
        popup:SetSize(popupW, popupH)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(200)

        if side == "left" then
            popup:SetPoint("TOPLEFT", sidebarFrame, "TOPRIGHT", 0, -(anchorBtn:GetTop() - sidebarFrame:GetTop()))
        else
            popup:SetPoint("TOPRIGHT", sidebarFrame, "TOPLEFT", 0, -(anchorBtn:GetTop() - sidebarFrame:GetTop()))
        end

        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints()
        popBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        popup:EnableMouse(true)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)
        ns._ccGridPopup = popup

        local scroll = CreateFrame("ScrollFrame", nil, popup)
        scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", INSET, -INSET)
        scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -INSET, INSET)
        scroll:SetFrameLevel(popup:GetFrameLevel() + 2)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(innerW, innerH)
        scroll:SetScrollChild(child)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local s = self:GetVerticalScroll()
            local mx = max(0, child:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
        end)

        for i, item in ipairs(items) do
            local col = (i - 1) % GRID_COLS
            local r = floor((i - 1) / GRID_COLS)
            local cx = col * (CELL_W + COL_GAP)
            local cy = rowY[r]
            local hasText = rowHasText[r]
            local cellH = rowH[r]

            local pxSnap = ns.PixelSnap or function(v) return v end

            -- Divider line between rows (drawn once per row, in the gap)
            if col == 0 and r > 0 then
                local divY = cy + ROW_GAP / 2
                local div = child:CreateTexture(nil, "ARTWORK")
                div:SetHeight(pxSnap(1))
                div:SetPoint("TOPLEFT", child, "TOPLEFT", 0, divY)
                div:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, divY)
                div:SetColorTexture(1, 1, 1, 0.06)
                if PP then PP.DisablePixelSnap(div) end
            end

            local cell = CreateFrame("Button", nil, child)
            cell:SetSize(CELL_W, cellH)
            cell:SetPoint("TOPLEFT", child, "TOPLEFT", cx, cy)

            -- Icon with hover border
            local iconFrame = CreateFrame("Frame", nil, cell)
            iconFrame:SetSize(ICON_SZ2, ICON_SZ2)
            local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTex:SetTexture(item.icon or 134400)

            local iconBdr = CreateFrame("Frame", nil, iconFrame)
            iconBdr:SetAllPoints()
            iconBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            iconBdr:Hide()
            if PP then PP.CreateBorder(iconBdr, accentColor.r, accentColor.g, accentColor.b, 1, 2) end

            local cellLbl = nil
            if hasText and item.name and item.name ~= "" then
                cellLbl = MakeFont(cell, LABEL_FONT, 1, 1, 1, 0.7)
                cellLbl:SetPoint("TOP", cell, "TOP", 0, 0)
                cellLbl:SetWidth(CELL_W + 4)
                cellLbl:SetJustifyH("CENTER"); cellLbl:SetWordWrap(false)
                cellLbl:SetText(item.name)
                iconFrame:SetPoint("TOP", cellLbl, "BOTTOM", 0, -LABEL_GAP)
            else
                iconFrame:SetPoint("TOP", cell, "TOP", 0, 0)
            end

            cell:SetScript("OnEnter", function()
                iconBdr:Show()
                if cellLbl then cellLbl:SetAlpha(1) end
            end)
            cell:SetScript("OnLeave", function()
                iconBdr:Hide()
                if cellLbl then cellLbl:SetAlpha(0.7) end
            end)
            cell:SetScript("OnClick", function()
                onSelect(item)
                popup:Hide()
            end)
        end

        -- Auto-close on click outside (dropdown pattern: poll IsMouseButtonDown)
        popup:SetScript("OnShow", function(p)
            p:SetScript("OnUpdate", function(m)
                if not m:IsMouseOver() and not anchorBtn:IsMouseOver()
                   and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
        end)
        popup:SetScript("OnHide", function(p)
            p:SetScript("OnUpdate", nil)
            if ns._ccGridPopup == p then ns._ccGridPopup = nil end
        end)

        popup:Show()
        return popup
    end

    ---------------------------------------------------------------------------
    --  Page rebuild function (called on selection change, add, delete, toggle)
    ---------------------------------------------------------------------------
    local function RebuildPage()
        -- Hide any open popups (QB stays open -- it's parented to UIParent)
        if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
        if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
        -- Destroy and recreate root
        if ns._ccRoot then ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil); ns._ccRoot = nil end
        ns.CC_BuildPage(pageName, parent, yOffset)
    end

    local function SelectBinding(side, idx)
        ns._ccSelSide = side
        ns._ccSelIndex = idx
        RebuildPage()
    end

    ---------------------------------------------------------------------------
    --  LEFT SIDEBAR (Global Bindings)
    ---------------------------------------------------------------------------
    local leftOuter = CreateFrame("Frame", nil, root)
    leftOuter:SetSize(sidebarW, visibleH)
    leftOuter:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    leftOuter:SetFrameLevel(root:GetFrameLevel() + 1)
    local leftBg = leftOuter:CreateTexture(nil, "BACKGROUND")
    leftBg:SetAllPoints(); leftBg:SetColorTexture(0, 0, 0, 0.25)

    -- Header label
    local leftHeader = MakeFont(leftOuter, 13, 1, 1, 1, 0.75)
    leftHeader:SetPoint("TOP", leftOuter, "TOP", 0, -18)
    leftHeader:SetText(EllesmereUI.L("Global Bindings"))

    local leftScroll = CreateFrame("ScrollFrame", nil, leftOuter)
    leftScroll:SetPoint("TOPLEFT", leftOuter, "TOPLEFT", 0, -38)
    leftScroll:SetPoint("BOTTOMRIGHT", leftOuter, "BOTTOMRIGHT", 0, 0)
    leftScroll:SetFrameLevel(leftOuter:GetFrameLevel() + 1)
    local leftChild = CreateFrame("Frame", nil, leftScroll)
    leftChild:SetWidth(sidebarW)
    leftScroll:SetScrollChild(leftChild)
    leftScroll:EnableMouseWheel(true)
    leftScroll:SetScript("OnMouseWheel", function(self, delta)
        local s = self:GetVerticalScroll()
        local mx = max(0, leftChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
    end)

    local leftY = 0
    local globals = GetGlobalBindings()
    for i, gb in ipairs(globals) do
        local isSel = selectedSide == "global" and selectedIndex == i
        local canDelete = gb.type ~= "target" and gb.type ~= "menu" and gb.type ~= "dispel" and gb.type ~= "external" and gb.type ~= "trinket1" and gb.type ~= "trinket2" and gb.type ~= "dynamicrez"
        BuildTile(leftChild, leftY, gb, isSel, "global", i,
            SelectBinding,
            canDelete and function(idx2)
                ns.CC_RemoveGlobalBinding(idx2)
                ns._ccSelSide = nil; ns._ccSelIndex = nil
                RebuildPage()
            end or nil)
        leftY = leftY - TILE_H
    end

    -- Add Global Binding button
    local addGlobalBtn = CreateFrame("Button", nil, leftChild)
    addGlobalBtn:SetSize(floor(sidebarW * 0.8), ADD_BTN_H)
    addGlobalBtn:SetPoint("TOP", leftChild, "TOPLEFT", sidebarW / 2, leftY - ADD_BTN_PAD)
    addGlobalBtn:SetFrameLevel(leftChild:GetFrameLevel() + 1)
    local agBg = addGlobalBtn:CreateTexture(nil, "BACKGROUND")
    agBg:SetAllPoints(); agBg:SetColorTexture(0.05, 0.52, 0.39, 0.8)
    local agLbl = MakeFont(addGlobalBtn, 12, 1, 1, 1, 1)
    agLbl:SetPoint("CENTER"); agLbl:SetText(EllesmereUI.L("Add Global Binding"))
    addGlobalBtn:SetScript("OnEnter", function() agBg:SetColorTexture(0.07, 0.62, 0.49, 1) end)
    addGlobalBtn:SetScript("OnLeave", function() agBg:SetColorTexture(0.05, 0.52, 0.39, 0.8) end)

    addGlobalBtn:SetScript("OnClick", function()
        if ns._ccGridPopup and ns._ccGridPopup:IsShown() then ns._ccGridPopup:Hide(); return end

        local INSETG = 15
        local innerGridWG = 5 * 48 + 4 * 19
        local popupWG = innerGridWG + INSETG * 2
        local popupHG = 400

        local popup = CreateFrame("Frame", nil, UIParent)
        popup:Hide()
        popup:SetSize(popupWG, popupHG)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(200)
        -- Left edge flush with right edge of left sidebar, centered vertically on the add button
        local btnMidYG = select(2, addGlobalBtn:GetCenter()) or 0
        local sidebarMidYG = select(2, leftOuter:GetCenter()) or 0
        local offsetYG = btnMidYG - sidebarMidYG
        -- Clamp so popup bottom doesn't go below root (EUI window)
        local rootBot = root:GetBottom() or 0
        local popupBotG = btnMidYG - popupHG / 2
        if popupBotG < rootBot then offsetYG = offsetYG + (rootBot - popupBotG) end
        popup:SetPoint("LEFT", leftOuter, "RIGHT", 0, offsetYG)

        local pBg = popup:CreateTexture(nil, "BACKGROUND")
        pBg:SetAllPoints(); pBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        popup:EnableMouse(true)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)
        ns._ccGridPopup = popup

        -- Macros / Items toggle
        local toggleModeG = "macro"
        local macroToggleG = CreateFrame("Button", nil, popup)
        macroToggleG:SetSize((popupWG - INSETG * 2) / 2 - 2, 26)
        macroToggleG:SetPoint("TOPLEFT", popup, "TOPLEFT", INSETG, -INSETG)
        local mtBgG = macroToggleG:CreateTexture(nil, "BACKGROUND"); mtBgG:SetAllPoints()
        local mtHlG = macroToggleG:CreateTexture(nil, "HIGHLIGHT"); mtHlG:SetAllPoints(); mtHlG:SetColorTexture(1, 1, 1, 0.1)
        local mtLblG = MakeFont(macroToggleG, 12, 1, 1, 1, 0.9); mtLblG:SetPoint("CENTER"); mtLblG:SetText(EllesmereUI.L("Macros"))

        local itemToggleG = CreateFrame("Button", nil, popup)
        itemToggleG:SetSize((popupWG - INSETG * 2) / 2 - 2, 26)
        itemToggleG:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -INSETG, -INSETG)
        local itBgG = itemToggleG:CreateTexture(nil, "BACKGROUND"); itBgG:SetAllPoints()
        local itHlG = itemToggleG:CreateTexture(nil, "HIGHLIGHT"); itHlG:SetAllPoints(); itHlG:SetColorTexture(1, 1, 1, 0.1)
        local itLblG = MakeFont(itemToggleG, 12, 1, 1, 1, 0.9); itLblG:SetPoint("CENTER"); itLblG:SetText(EllesmereUI.L("Items"))

        local gridScrollG = CreateFrame("ScrollFrame", nil, popup)
        gridScrollG:SetPoint("TOPLEFT", popup, "TOPLEFT", INSETG, -(INSETG + 40))
        gridScrollG:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -INSETG, INSETG)
        gridScrollG:SetFrameLevel(popup:GetFrameLevel() + 2)
        local gridChildG = CreateFrame("Frame", nil, gridScrollG)
        gridChildG:SetWidth(innerGridWG)
        gridScrollG:SetScrollChild(gridChildG)
        gridScrollG:EnableMouseWheel(true)
        gridScrollG:SetScript("OnMouseWheel", function(self, delta)
            local s = self:GetVerticalScroll()
            local mx = max(0, gridChildG:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
        end)

        -- Reuse the same grid constants as BuildIconGridPopup
        local GCG = 5; local ISZG = 32; local CWG = 48; local CGAPG = 19
        local LFONTG = 10; local LGAPG = 4; local RGAPG = 8; local LHG = 14

        local function PopulateGridG(itemsG, onItemClick)
            for _, c2 in ipairs({gridChildG:GetChildren()}) do c2:Hide(); c2:SetParent(nil) end
            local totalRowsG = math.ceil(#itemsG / GCG)
            local rhtG = {}
            for r = 0, totalRowsG - 1 do
                rhtG[r] = false
                for c = 0, GCG - 1 do
                    local ii = r * GCG + c + 1
                    if itemsG[ii] and itemsG[ii].name and itemsG[ii].name ~= "" then rhtG[r] = true; break end
                end
            end
            local rYG, rHG = {}, {}
            local cYG = 0
            for r = 0, totalRowsG - 1 do
                if r > 0 then cYG = cYG + RGAPG end
                rYG[r] = -cYG
                rHG[r] = rhtG[r] and (LHG + LGAPG + ISZG) or ISZG
                cYG = cYG + rHG[r]
            end
            local pxSnapG = ns.PixelSnap or function(v) return v end
            for i, itm in ipairs(itemsG) do
                local col = (i - 1) % GCG
                local r = floor((i - 1) / GCG)
                local cx = col * (CWG + CGAPG)
                local cy = rYG[r]
                if col == 0 and r > 0 then
                    local div = gridChildG:CreateTexture(nil, "ARTWORK")
                    div:SetHeight(pxSnapG(1)); div:SetPoint("TOPLEFT", gridChildG, "TOPLEFT", 0, cy + RGAPG / 2)
                    div:SetPoint("TOPRIGHT", gridChildG, "TOPRIGHT", 0, cy + RGAPG / 2)
                    div:SetColorTexture(1, 1, 1, 0.06)
                    if PP then PP.DisablePixelSnap(div) end
                end
                local cell = CreateFrame("Button", nil, gridChildG)
                cell:SetSize(CWG, rHG[r]); cell:SetPoint("TOPLEFT", gridChildG, "TOPLEFT", cx, cy)
                local iconFr = CreateFrame("Frame", nil, cell); iconFr:SetSize(ISZG, ISZG)
                local iconTx = iconFr:CreateTexture(nil, "ARTWORK"); iconTx:SetAllPoints()
                iconTx:SetTexCoord(0.08, 0.92, 0.08, 0.92); iconTx:SetTexture(itm.icon or 134400)
                local dimmedG = (itm.macroName and boundMacros[itm.macroName])
                    or (itm.itemSlot and boundItems[itm.itemSlot])
                if dimmedG then iconTx:SetAlpha(0.3) end
                local iconBd = CreateFrame("Frame", nil, iconFr); iconBd:SetAllPoints()
                iconBd:SetFrameLevel(iconFr:GetFrameLevel() + 1); iconBd:Hide()
                if PP then PP.CreateBorder(iconBd, accentColor.r, accentColor.g, accentColor.b, 1, 2) end
                local cellLbl = nil
                if rhtG[r] and itm.name and itm.name ~= "" then
                    cellLbl = MakeFont(cell, LFONTG, 1, 1, 1, dimmedG and 0.3 or 0.7)
                    cellLbl:SetPoint("TOP", cell, "TOP", 0, 0); cellLbl:SetWidth(CWG + 4)
                    cellLbl:SetJustifyH("CENTER"); cellLbl:SetWordWrap(false); cellLbl:SetText(itm.name)
                    iconFr:SetPoint("TOP", cellLbl, "BOTTOM", 0, -LGAPG)
                else iconFr:SetPoint("TOP", cell, "TOP", 0, 0) end
                cell:SetScript("OnEnter", function() iconBd:Show(); if cellLbl then cellLbl:SetAlpha(1) end end)
                cell:SetScript("OnLeave", function() iconBd:Hide(); if cellLbl then cellLbl:SetAlpha(0.7) end end)
                cell:SetScript("OnClick", function() onItemClick(itm); popup:Hide() end)
            end
            gridChildG:SetHeight(max(10, cYG))
        end

        local function UpdateToggleG()
            if toggleModeG == "macro" then
                mtBgG:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.25)
                itBgG:SetColorTexture(1, 1, 1, 0.05)
                local macros = ns.CC_GetGlobalMacros()
                local mItems = {}
                for _, m in ipairs(macros) do mItems[#mItems + 1] = { name = m.name, icon = m.icon, macroName = m.name } end
                PopulateGridG(mItems, function(itm)
                    ns.CC_AddGlobalBinding({ type = "macro", macroName = itm.macroName, icon = itm.icon,
                        enabled = true, oocOnly = false, hovercast = false, hoverFriendly = true, hoverEnemy = false })
                    ns._ccSelSide = "global"; ns._ccSelIndex = #(GetGlobalBindings()); RebuildPage()
                end)
            else
                mtBgG:SetColorTexture(1, 1, 1, 0.05)
                itBgG:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.25)
                local eqItems = ns.CC_GetEquippedItems()
                PopulateGridG(eqItems, function(itm)
                    ns.CC_AddGlobalBinding({ type = "item", itemSlot = itm.itemSlot, itemName = itm.name, icon = itm.icon,
                        enabled = true, oocOnly = false, hovercast = false, hoverFriendly = true, hoverEnemy = false })
                    ns._ccSelSide = "global"; ns._ccSelIndex = #(GetGlobalBindings()); RebuildPage()
                end)
            end
        end
        UpdateToggleG()

        macroToggleG:SetScript("OnClick", function() toggleModeG = "macro"; UpdateToggleG() end)
        itemToggleG:SetScript("OnClick", function() toggleModeG = "item"; UpdateToggleG() end)

        popup:SetScript("OnShow", function(p)
            p:SetScript("OnUpdate", function(m)
                if not m:IsMouseOver() and not addGlobalBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then m:Hide() end
            end)
        end)
        popup:SetScript("OnHide", function(p)
            p:SetScript("OnUpdate", nil)
            if ns._ccGridPopup == p then ns._ccGridPopup = nil end
        end)
        popup:Show()
    end)
    leftY = leftY - ADD_BTN_PAD - ADD_BTN_H - 10
    leftChild:SetHeight(max(10, math.abs(leftY)))

    -- Sticky clone for Add Global button
    local stickyLeftBg = CreateFrame("Frame", nil, leftOuter)
    stickyLeftBg:SetHeight(ADD_BTN_H + 20)
    stickyLeftBg:SetPoint("BOTTOMLEFT", leftOuter, "BOTTOMLEFT", 0, 0)
    stickyLeftBg:SetPoint("BOTTOMRIGHT", leftOuter, "BOTTOMRIGHT", 0, 0)
    stickyLeftBg:SetFrameLevel(leftOuter:GetFrameLevel() + 4)
    local slbTex = stickyLeftBg:CreateTexture(nil, "BACKGROUND")
    slbTex:SetAllPoints(); slbTex:SetColorTexture(15/255, 17/255, 22/255, 1)
    stickyLeftBg:Hide()

    local stickyGlobalBtn = CreateFrame("Button", nil, leftOuter)
    stickyGlobalBtn:SetSize(floor(sidebarW * 0.8), ADD_BTN_H)
    stickyGlobalBtn:SetPoint("BOTTOM", leftOuter, "BOTTOM", 0, 10)
    stickyGlobalBtn:SetFrameLevel(leftOuter:GetFrameLevel() + 5)
    local sgBg = stickyGlobalBtn:CreateTexture(nil, "BACKGROUND")
    sgBg:SetAllPoints(); sgBg:SetColorTexture(0.05, 0.52, 0.39, 0.8)
    local sgLbl = MakeFont(stickyGlobalBtn, 12, 1, 1, 1, 1)
    sgLbl:SetPoint("CENTER"); sgLbl:SetText(EllesmereUI.L("Add Global Binding"))
    stickyGlobalBtn:SetScript("OnEnter", function() sgBg:SetColorTexture(0.07, 0.62, 0.49, 1) end)
    stickyGlobalBtn:SetScript("OnLeave", function() sgBg:SetColorTexture(0.05, 0.52, 0.39, 0.8) end)
    stickyGlobalBtn:SetScript("OnClick", function()
        if ns._ccGridPopup and ns._ccGridPopup:IsShown() then ns._ccGridPopup:Hide(); return end
        addGlobalBtn:Click()
    end)
    stickyGlobalBtn:Hide()

    -- Button bottom in scroll child space (positive downward)
    local globalBtnBottom = math.abs(leftY)
    local function UpdateLeftSticky()
        local scrollVal = leftScroll:GetVerticalScroll()
        local viewH = leftScroll:GetHeight()
        if globalBtnBottom > scrollVal + viewH then
            stickyLeftBg:Show(); stickyGlobalBtn:Show()
            addGlobalBtn:SetAlpha(0)
        else
            stickyLeftBg:Hide(); stickyGlobalBtn:Hide()
            addGlobalBtn:SetAlpha(1)
        end
    end
    local origLeftWheel = leftScroll:GetScript("OnMouseWheel")
    leftScroll:SetScript("OnMouseWheel", function(self, delta)
        origLeftWheel(self, delta)
        UpdateLeftSticky()
    end)
    UpdateLeftSticky()

    ---------------------------------------------------------------------------
    --  RIGHT SIDEBAR (Spec Bindings)
    ---------------------------------------------------------------------------
    local rightOuter = CreateFrame("Frame", nil, root)
    rightOuter:SetSize(sidebarW, visibleH)
    rightOuter:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    rightOuter:SetFrameLevel(root:GetFrameLevel() + 1)
    local rightBg = rightOuter:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints(); rightBg:SetColorTexture(0, 0, 0, 0.25)

    local rightHeader = MakeFont(rightOuter, 13, 1, 1, 1, 0.75)
    rightHeader:SetPoint("TOP", rightOuter, "TOP", 0, -18)
    rightHeader:SetText(EllesmereUI.L("Spec Bindings"))

    local rightScroll = CreateFrame("ScrollFrame", nil, rightOuter)
    rightScroll:SetPoint("TOPLEFT", rightOuter, "TOPLEFT", 0, -38)
    rightScroll:SetPoint("BOTTOMRIGHT", rightOuter, "BOTTOMRIGHT", 0, 0)
    rightScroll:SetFrameLevel(rightOuter:GetFrameLevel() + 1)
    local rightChild = CreateFrame("Frame", nil, rightScroll)
    rightChild:SetWidth(sidebarW)
    rightScroll:SetScrollChild(rightChild)
    rightScroll:EnableMouseWheel(true)
    rightScroll:SetScript("OnMouseWheel", function(self, delta)
        local s = self:GetVerticalScroll()
        local mx = max(0, rightChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
    end)

    local rightY = 0
    local specBinds = GetSpecBindings()
    for i, sb in ipairs(specBinds) do
        local isSel = selectedSide == "spec" and selectedIndex == i
        BuildTile(rightChild, rightY, sb, isSel, "spec", i,
            SelectBinding,
            function(idx2)
                ns.CC_RemoveSpecBinding(idx2)
                ns._ccSelSide = nil; ns._ccSelIndex = nil
                RebuildPage()
            end)
        rightY = rightY - TILE_H
    end

    -- Add New + Quickbind buttons
    local btnW = floor(sidebarW * 0.42)
    local addSpecBtn = CreateFrame("Button", nil, rightChild)
    addSpecBtn:SetSize(btnW, ADD_BTN_H)
    addSpecBtn:SetPoint("TOPLEFT", rightChild, "TOPLEFT", floor((sidebarW - btnW * 2 - 8) / 2), rightY - ADD_BTN_PAD)
    addSpecBtn:SetFrameLevel(rightChild:GetFrameLevel() + 1)
    local asBg = addSpecBtn:CreateTexture(nil, "BACKGROUND")
    asBg:SetAllPoints(); asBg:SetColorTexture(0.05, 0.52, 0.39, 0.8)
    local asLbl = MakeFont(addSpecBtn, 11, 1, 1, 1, 1)
    asLbl:SetPoint("CENTER"); asLbl:SetText(EllesmereUI.L("Add New"))
    addSpecBtn:SetScript("OnEnter", function() asBg:SetColorTexture(0.07, 0.62, 0.49, 1) end)
    addSpecBtn:SetScript("OnLeave", function() asBg:SetColorTexture(0.05, 0.52, 0.39, 0.8) end)

    local qbBtn = CreateFrame("Button", nil, rightChild)
    qbBtn:SetSize(btnW, ADD_BTN_H)
    qbBtn:SetPoint("LEFT", addSpecBtn, "RIGHT", 8, 0)
    qbBtn:SetFrameLevel(rightChild:GetFrameLevel() + 1)
    local qbBg = qbBtn:CreateTexture(nil, "BACKGROUND")
    qbBg:SetAllPoints(); qbBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
    local qbLbl = MakeFont(qbBtn, 11, 1, 1, 1, 0.5)
    qbLbl:SetPoint("CENTER"); qbLbl:SetText(EllesmereUI.L("Quickbind"))
    qbBtn:SetScript("OnEnter", function() qbBg:SetColorTexture(0.35, 0.35, 0.35, 0.8); qbLbl:SetAlpha(0.9) end)
    qbBtn:SetScript("OnLeave", function() qbBg:SetColorTexture(0.25, 0.25, 0.25, 0.6); qbLbl:SetAlpha(0.5) end)

    qbBtn:SetScript("OnClick", function()
        if ns._ccQBPopup and ns._ccQBPopup:IsShown() then ns._ccQBPopup:Hide(); return end

        -- Full screen dimmer
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN")
        dimmer:SetAllPoints()
        dimmer:EnableMouse(true)
        local dimBg = dimmer:CreateTexture(nil, "BACKGROUND")
        dimBg:SetAllPoints(); dimBg:SetColorTexture(0, 0, 0, 0.6)

        local QB_INSET = 15
        local QB_COLS = 5
        local QB_ICON = 32
        local QB_CELL = 48
        local QB_CGAP = 19
        local QB_LFONT = 10
        local QB_LGAP = 4
        local QB_RGAP = 8
        local QB_LH = 14
        local innerGridWQB = QB_COLS * QB_CELL + (QB_COLS - 1) * QB_CGAP
        local popupWQB = innerGridWQB + QB_INSET * 2
        local popupHQB = 400

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(popupWQB, popupHQB)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(200)
        popup:EnableMouse(true)

        local pBg = popup:CreateTexture(nil, "BACKGROUND")
        pBg:SetAllPoints(); pBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)
        ns._ccQBPopup = dimmer

        -- Title
        local titleLbl = MakeFont(popup, 13, 1, 1, 1, 0.9)
        titleLbl:SetPoint("TOP", popup, "TOP", 0, -QB_INSET)
        titleLbl:SetText(EllesmereUI.L("Quickbind: hover a spell, press a key"))

        -- Spells / Macros / Items toggle
        local toggleModeQB = "spell"
        local toggleInnerQB = popupWQB - QB_INSET * 2
        local toggleBtnWQB = floor(toggleInnerQB / 3) - 2
        local toggleTopQB = -(QB_INSET + 22)

        local spellTglQB = CreateFrame("Button", nil, popup)
        spellTglQB:SetSize(toggleBtnWQB, 26)
        spellTglQB:SetPoint("TOPLEFT", popup, "TOPLEFT", QB_INSET, toggleTopQB)
        local stBgQB = spellTglQB:CreateTexture(nil, "BACKGROUND"); stBgQB:SetAllPoints()
        local stHlQB = spellTglQB:CreateTexture(nil, "HIGHLIGHT"); stHlQB:SetAllPoints(); stHlQB:SetColorTexture(1, 1, 1, 0.1)
        local stLblQB = MakeFont(spellTglQB, 12, 1, 1, 1, 0.9); stLblQB:SetPoint("CENTER"); stLblQB:SetText(EllesmereUI.L("Spells"))

        local macroTglQB = CreateFrame("Button", nil, popup)
        macroTglQB:SetSize(toggleBtnWQB, 26)
        macroTglQB:SetPoint("LEFT", spellTglQB, "RIGHT", 3, 0)
        local mtBgQB = macroTglQB:CreateTexture(nil, "BACKGROUND"); mtBgQB:SetAllPoints()
        local mtHlQB = macroTglQB:CreateTexture(nil, "HIGHLIGHT"); mtHlQB:SetAllPoints(); mtHlQB:SetColorTexture(1, 1, 1, 0.1)
        local mtLblQB = MakeFont(macroTglQB, 12, 1, 1, 1, 0.9); mtLblQB:SetPoint("CENTER"); mtLblQB:SetText(EllesmereUI.L("Macros"))

        local itemTglQB = CreateFrame("Button", nil, popup)
        itemTglQB:SetSize(toggleBtnWQB, 26)
        itemTglQB:SetPoint("LEFT", macroTglQB, "RIGHT", 3, 0)
        local itBgQB = itemTglQB:CreateTexture(nil, "BACKGROUND"); itBgQB:SetAllPoints()
        local itHlQB = itemTglQB:CreateTexture(nil, "HIGHLIGHT"); itHlQB:SetAllPoints(); itHlQB:SetColorTexture(1, 1, 1, 0.1)
        local itLblQB = MakeFont(itemTglQB, 12, 1, 1, 1, 0.9); itLblQB:SetPoint("CENTER"); itLblQB:SetText(EllesmereUI.L("Items"))

        -- Grid scroll area
        local gridScrollQB = CreateFrame("ScrollFrame", nil, popup)
        gridScrollQB:SetPoint("TOPLEFT", popup, "TOPLEFT", QB_INSET, toggleTopQB - 36)
        gridScrollQB:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -QB_INSET, QB_INSET + 38)
        gridScrollQB:SetFrameLevel(popup:GetFrameLevel() + 2)
        local gridChildQB = CreateFrame("Frame", nil, gridScrollQB)
        gridChildQB:SetWidth(innerGridWQB)
        gridScrollQB:SetScrollChild(gridChildQB)
        gridScrollQB:EnableMouseWheel(true)
        gridScrollQB:SetScript("OnMouseWheel", function(self, delta)
            local s = self:GetVerticalScroll()
            local mx = max(0, gridChildQB:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
        end)

        -- Hovered item reference (set by cell OnEnter/OnLeave)
        local hoveredItem = nil

        local UpdateToggleQB
        local function PopulateGridQB(items3)
            for _, c2 in ipairs({gridChildQB:GetChildren()}) do c2:Hide(); c2:SetParent(nil) end
            hoveredItem = nil
            local totalRows = math.ceil(#items3 / QB_COLS)
            local rht3 = {}
            for r = 0, totalRows - 1 do
                rht3[r] = false
                for c = 0, QB_COLS - 1 do
                    local ii = r * QB_COLS + c + 1
                    if items3[ii] and items3[ii].name and items3[ii].name ~= "" then rht3[r] = true; break end
                end
            end
            local rY3, rH3 = {}, {}
            local cY3 = 0
            for r = 0, totalRows - 1 do
                if r > 0 then cY3 = cY3 + QB_RGAP end
                rY3[r] = -cY3
                rH3[r] = rht3[r] and (QB_LH + QB_LGAP + QB_ICON) or QB_ICON
                cY3 = cY3 + rH3[r]
            end
            local pxSnap3 = ns.PixelSnap or function(v) return v end
            for i, item in ipairs(items3) do
                local col = (i - 1) % QB_COLS
                local r = floor((i - 1) / QB_COLS)
                local cx = col * (QB_CELL + QB_CGAP)
                local cy = rY3[r]
                if col == 0 and r > 0 then
                    local div = gridChildQB:CreateTexture(nil, "ARTWORK")
                    div:SetHeight(pxSnap3(1))
                    div:SetPoint("TOPLEFT", gridChildQB, "TOPLEFT", 0, cy + QB_RGAP / 2)
                    div:SetPoint("TOPRIGHT", gridChildQB, "TOPRIGHT", 0, cy + QB_RGAP / 2)
                    div:SetColorTexture(1, 1, 1, 0.06)
                    if PP then PP.DisablePixelSnap(div) end
                end
                local cell = CreateFrame("Button", nil, gridChildQB)
                cell:SetSize(QB_CELL, rH3[r])
                cell:SetPoint("TOPLEFT", gridChildQB, "TOPLEFT", cx, cy)
                cell:RegisterForClicks("AnyUp")
                cell:EnableKeyboard(false)
                local iconFr = CreateFrame("Frame", nil, cell); iconFr:SetSize(QB_ICON, QB_ICON)
                local iconTx = iconFr:CreateTexture(nil, "ARTWORK"); iconTx:SetAllPoints()
                iconTx:SetTexCoord(0.08, 0.92, 0.08, 0.92); iconTx:SetTexture(item.icon or 134400)
                local dimmed3 = (item.id and boundSpells[item.name])
                    or (item.macroName and boundMacros[item.macroName])
                    or (item.itemSlot and boundItems[item.itemSlot])
                if dimmed3 then iconTx:SetAlpha(0.3) end
                local iconBd = CreateFrame("Frame", nil, iconFr); iconBd:SetAllPoints()
                iconBd:SetFrameLevel(iconFr:GetFrameLevel() + 1); iconBd:Hide()
                if PP then PP.CreateBorder(iconBd, accentColor.r, accentColor.g, accentColor.b, 1, 2) end
                local cellLbl3 = nil
                if rht3[r] and item.name and item.name ~= "" then
                    cellLbl3 = MakeFont(cell, QB_LFONT, 1, 1, 1, dimmed3 and 0.3 or 0.7)
                    cellLbl3:SetPoint("TOP", cell, "TOP", 0, 0); cellLbl3:SetWidth(QB_CELL + 4)
                    cellLbl3:SetJustifyH("CENTER"); cellLbl3:SetWordWrap(false); cellLbl3:SetText(item.name)
                    iconFr:SetPoint("TOP", cellLbl3, "BOTTOM", 0, -QB_LGAP)
                else
                    iconFr:SetPoint("TOP", cell, "TOP", 0, 0)
                end
                cell:SetScript("OnEnter", function()
                    iconBd:Show()
                    if cellLbl3 then cellLbl3:SetAlpha(1) end
                    hoveredItem = item
                    cell:EnableKeyboard(true)
                end)
                cell:SetScript("OnLeave", function()
                    iconBd:Hide()
                    if cellLbl3 then cellLbl3:SetAlpha(dimmed3 and 0.3 or 0.7) end
                    hoveredItem = nil
                    cell:EnableKeyboard(false)
                end)
                -- Key press while hovering: bind this item to that key
                cell:SetScript("OnKeyDown", function(self, key)
                    if MODIFIER_KEYS[key] then self:SetPropagateKeyboardInput(true); return end
                    if key == "ESCAPE" then self:SetPropagateKeyboardInput(false); dimmer:Hide(); return end
                    self:SetPropagateKeyboardInput(false)
                    local captured = ns.CC_CaptureKey(key)
                    if not captured or not hoveredItem then return end
                    local binding
                    if hoveredItem.id then
                        binding = { type = "spell", spell = hoveredItem.name, spellID = hoveredItem.id,
                            icon = hoveredItem.icon, key = captured, enabled = true }
                    elseif hoveredItem.macroName then
                        binding = { type = "macro", macroName = hoveredItem.macroName,
                            icon = hoveredItem.icon, key = captured, enabled = true }
                    elseif hoveredItem.itemSlot then
                        binding = { type = "item", itemSlot = hoveredItem.itemSlot, itemName = hoveredItem.name,
                            icon = hoveredItem.icon, key = captured, enabled = true }
                    end
                    if binding then
                        ns.CC_AddSpecBinding(binding)
                        if hoveredItem.macroName then boundMacros[hoveredItem.macroName] = true
                        elseif hoveredItem.itemSlot then boundItems[hoveredItem.itemSlot] = true
                        else boundSpells[hoveredItem.name or ""] = true end
                        UpdateToggleQB()
                        RebuildPage()
                    end
                end)
                -- Mouse click while hovering: bind with modifier+button
                cell:SetScript("OnClick", function(self, button)
                    if not hoveredItem then return end
                    local mods = GetModifierPrefix()
                    local normalized = MOUSE_BUTTON_MAP[button] or ("BUTTON" .. (button:match("%d+") or button))
                    local captured = mods .. normalized
                    local binding
                    if hoveredItem.id then
                        binding = { type = "spell", spell = hoveredItem.name, spellID = hoveredItem.id,
                            icon = hoveredItem.icon, key = captured, enabled = true }
                    elseif hoveredItem.macroName then
                        binding = { type = "macro", macroName = hoveredItem.macroName,
                            icon = hoveredItem.icon, key = captured, enabled = true }
                    elseif hoveredItem.itemSlot then
                        binding = { type = "item", itemSlot = hoveredItem.itemSlot, itemName = hoveredItem.name,
                            icon = hoveredItem.icon, key = captured, enabled = true }
                    end
                    if binding then
                        ns.CC_AddSpecBinding(binding)
                        if hoveredItem.macroName then boundMacros[hoveredItem.macroName] = true
                        elseif hoveredItem.itemSlot then boundItems[hoveredItem.itemSlot] = true
                        else boundSpells[hoveredItem.name or ""] = true end
                        UpdateToggleQB()
                        RebuildPage()
                    end
                end)
            end
            gridChildQB:SetHeight(max(10, cY3))
        end

        function UpdateToggleQB()
            local selA = { accentColor.r, accentColor.g, accentColor.b, 0.25 }
            local offA = { 1, 1, 1, 0.05 }
            stBgQB:SetColorTexture(toggleModeQB == "spell" and selA[1] or offA[1], toggleModeQB == "spell" and selA[2] or offA[2], toggleModeQB == "spell" and selA[3] or offA[3], toggleModeQB == "spell" and selA[4] or offA[4])
            mtBgQB:SetColorTexture(toggleModeQB == "macro" and selA[1] or offA[1], toggleModeQB == "macro" and selA[2] or offA[2], toggleModeQB == "macro" and selA[3] or offA[3], toggleModeQB == "macro" and selA[4] or offA[4])
            itBgQB:SetColorTexture(toggleModeQB == "item" and selA[1] or offA[1], toggleModeQB == "item" and selA[2] or offA[2], toggleModeQB == "item" and selA[3] or offA[3], toggleModeQB == "item" and selA[4] or offA[4])
            if toggleModeQB == "spell" then
                PopulateGridQB(ns.CC_GetClassSpells())
            elseif toggleModeQB == "macro" then
                local macros = ns.CC_GetAllMacros()
                local mItems = {}
                for _, m in ipairs(macros) do
                    local prefix = m.isGlobal and "" or "(C) "
                    mItems[#mItems + 1] = { name = prefix .. m.name, icon = m.icon, macroName = m.name }
                end
                PopulateGridQB(mItems)
            else
                PopulateGridQB(ns.CC_GetEquippedItems())
            end
        end
        UpdateToggleQB()

        spellTglQB:SetScript("OnClick", function() toggleModeQB = "spell"; UpdateToggleQB() end)
        macroTglQB:SetScript("OnClick", function() toggleModeQB = "macro"; UpdateToggleQB() end)
        itemTglQB:SetScript("OnClick", function() toggleModeQB = "item"; UpdateToggleQB() end)

        -- Done button
        local doneBtn = CreateFrame("Button", nil, popup)
        doneBtn:SetSize(100, 30)
        doneBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, QB_INSET)
        doneBtn:SetFrameLevel(popup:GetFrameLevel() + 3)
        local doneBg = doneBtn:CreateTexture(nil, "BACKGROUND")
        doneBg:SetAllPoints(); doneBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
        local doneLbl = MakeFont(doneBtn, 11, 1, 1, 1, 0.5)
        doneLbl:SetPoint("CENTER"); doneLbl:SetText(EllesmereUI.L("Done"))
        doneBtn:SetScript("OnEnter", function() doneBg:SetColorTexture(0.35, 0.35, 0.35, 0.8); doneLbl:SetAlpha(0.9) end)
        doneBtn:SetScript("OnLeave", function() doneBg:SetColorTexture(0.25, 0.25, 0.25, 0.6); doneLbl:SetAlpha(0.5) end)
        doneBtn:SetScript("OnClick", function() dimmer:Hide() end)

        -- Click dimmer to close
        dimmer:SetScript("OnMouseDown", function(self, button)
            if not popup:IsMouseOver() then dimmer:Hide() end
        end)
        dimmer:SetScript("OnHide", function()
            if ns._ccQBPopup == dimmer then ns._ccQBPopup = nil end
            RebuildPage()
        end)

        dimmer:Show()
    end)

    -- Add New popup logic
    addSpecBtn:SetScript("OnClick", function()
        if ns._ccSpecPopup and ns._ccSpecPopup:IsShown() then ns._ccSpecPopup:Hide(); return end

        -- Build popup with spell/macro toggle
        local INSET3 = 15
        -- Match BuildIconGridPopup: 6 cols, 48px wide, 4px gap
        local innerGridW3 = 5 * 48 + 4 * 19
        local popupW = innerGridW3 + INSET3 * 2
        local popupH2 = 400
        local popup = CreateFrame("Frame", nil, UIParent)
        popup:Hide()  -- start hidden so Show() triggers OnShow
        popup:SetSize(popupW, popupH2)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(200)
        -- Right edge flush with left edge of right sidebar, centered vertically on the add button
        local btnMidY = select(2, addSpecBtn:GetCenter()) or 0
        local sidebarMidY = select(2, rightOuter:GetCenter()) or 0
        local offsetY = btnMidY - sidebarMidY
        -- Clamp so popup bottom doesn't go below root (EUI window)
        local rootBotR = root:GetBottom() or 0
        local popupBotR = btnMidY - popupH2 / 2
        if popupBotR < rootBotR then offsetY = offsetY + (rootBotR - popupBotR) end
        popup:SetPoint("RIGHT", rightOuter, "LEFT", 0, offsetY)

        local pBg = popup:CreateTexture(nil, "BACKGROUND")
        pBg:SetAllPoints(); pBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        popup:EnableMouse(true)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)

        -- Store ref for cleanup
        ns._ccSpecPopup = popup

        -- Spell / Macro toggle
        local INSET2 = 15
        local toggleMode = "spell"
        local toggleInner = popupW - INSET2 * 2
        local toggleBtnW = floor(toggleInner / 3) - 2

        local spellToggle = CreateFrame("Button", nil, popup)
        spellToggle:SetSize(toggleBtnW, 26)
        spellToggle:SetPoint("TOPLEFT", popup, "TOPLEFT", INSET2, -INSET2)
        local stBg = spellToggle:CreateTexture(nil, "BACKGROUND"); stBg:SetAllPoints()
        local stHl = spellToggle:CreateTexture(nil, "HIGHLIGHT"); stHl:SetAllPoints(); stHl:SetColorTexture(1, 1, 1, 0.1)
        local stLbl = MakeFont(spellToggle, 12, 1, 1, 1, 0.9); stLbl:SetPoint("CENTER"); stLbl:SetText(EllesmereUI.L("Spells"))

        local macroToggle = CreateFrame("Button", nil, popup)
        macroToggle:SetSize(toggleBtnW, 26)
        macroToggle:SetPoint("LEFT", spellToggle, "RIGHT", 3, 0)
        local mtBg = macroToggle:CreateTexture(nil, "BACKGROUND"); mtBg:SetAllPoints()
        local mtHl = macroToggle:CreateTexture(nil, "HIGHLIGHT"); mtHl:SetAllPoints(); mtHl:SetColorTexture(1, 1, 1, 0.1)
        local mtLbl = MakeFont(macroToggle, 12, 1, 1, 1, 0.9); mtLbl:SetPoint("CENTER"); mtLbl:SetText(EllesmereUI.L("Macros"))

        local itemToggle = CreateFrame("Button", nil, popup)
        itemToggle:SetSize(toggleBtnW, 26)
        itemToggle:SetPoint("LEFT", macroToggle, "RIGHT", 3, 0)
        local itBg = itemToggle:CreateTexture(nil, "BACKGROUND"); itBg:SetAllPoints()
        local itHl = itemToggle:CreateTexture(nil, "HIGHLIGHT"); itHl:SetAllPoints(); itHl:SetColorTexture(1, 1, 1, 0.1)
        local itLbl = MakeFont(itemToggle, 12, 1, 1, 1, 0.9); itLbl:SetPoint("CENTER"); itLbl:SetText(EllesmereUI.L("Items"))

        -- Grid scroll area (inset on all sides, below toggle row)
        local gridScroll = CreateFrame("ScrollFrame", nil, popup)
        gridScroll:SetPoint("TOPLEFT", popup, "TOPLEFT", INSET2, -(INSET2 + 40))
        gridScroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -INSET2, INSET2)
        gridScroll:SetFrameLevel(popup:GetFrameLevel() + 2)
        local innerGridW = popupW - INSET2 * 2
        local gridChild = CreateFrame("Frame", nil, gridScroll)
        gridChild:SetWidth(innerGridW)
        gridScroll:SetScrollChild(gridChild)
        gridScroll:EnableMouseWheel(true)
        gridScroll:SetScript("OnMouseWheel", function(self, delta)
            local s = self:GetVerticalScroll()
            local mx = max(0, gridChild:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
        end)

        local GC2 = 5
        local ISZ2 = 32
        local CW2 = 48
        local CGAP2 = 19
        local LFONT2 = 10
        local LGAP2 = 4
        local RGAP2 = 8
        local DIVH2 = 1
        local LH2 = 14

        local function PopulateGrid(items2, onItemClick)
            -- Clear existing children
            for _, c2 in ipairs({gridChild:GetChildren()}) do c2:Hide(); c2:SetParent(nil) end

            local totalRows2 = math.ceil(#items2 / GC2)
            -- Per-row text check
            local rht = {}
            for r = 0, totalRows2 - 1 do
                rht[r] = false
                for c = 0, GC2 - 1 do
                    local ii = r * GC2 + c + 1
                    if items2[ii] and items2[ii].name and items2[ii].name ~= "" then
                        rht[r] = true; break
                    end
                end
            end
            -- Compute row positions
            local rY2, rH2 = {}, {}
            local cY2 = 0
            for r = 0, totalRows2 - 1 do
                if r > 0 then cY2 = cY2 + RGAP2 end
                rY2[r] = -cY2
                rH2[r] = rht[r] and (LH2 + LGAP2 + ISZ2) or ISZ2
                cY2 = cY2 + rH2[r]
            end

            local pxSnap2 = ns.PixelSnap or function(v) return v end

            for i, item in ipairs(items2) do
                local col = (i - 1) % GC2
                local r = floor((i - 1) / GC2)
                local cx = col * (CW2 + CGAP2)
                local cy = rY2[r]

                if col == 0 and r > 0 then
                    local divY = cy + RGAP2 / 2
                    local div = gridChild:CreateTexture(nil, "ARTWORK")
                    div:SetHeight(pxSnap2(1))
                    div:SetPoint("TOPLEFT", gridChild, "TOPLEFT", 0, divY)
                    div:SetPoint("TOPRIGHT", gridChild, "TOPRIGHT", 0, divY)
                    div:SetColorTexture(1, 1, 1, 0.06)
                    if PP then PP.DisablePixelSnap(div) end
                end

                local cell = CreateFrame("Button", nil, gridChild)
                cell:SetSize(CW2, rH2[r])
                cell:SetPoint("TOPLEFT", gridChild, "TOPLEFT", cx, cy)

                -- Icon with hover border
                local iconFrame2 = CreateFrame("Frame", nil, cell)
                iconFrame2:SetSize(ISZ2, ISZ2)
                local iconTex = iconFrame2:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                iconTex:SetTexture(item.icon or 134400)
                local dimmed = (item.id and boundSpells[item.name])
                    or (item.macroName and boundMacros[item.macroName])
                    or (item.itemSlot and boundItems[item.itemSlot])
                if dimmed then iconTex:SetAlpha(0.3) end

                local iconBdr2 = CreateFrame("Frame", nil, iconFrame2)
                iconBdr2:SetAllPoints()
                iconBdr2:SetFrameLevel(iconFrame2:GetFrameLevel() + 1)
                iconBdr2:Hide()
                if PP then PP.CreateBorder(iconBdr2, accentColor.r, accentColor.g, accentColor.b, 1, 2) end

                local cellLbl2 = nil
                if rht[r] and item.name and item.name ~= "" then
                    cellLbl2 = MakeFont(cell, LFONT2, 1, 1, 1, dimmed and 0.3 or 0.7)
                    cellLbl2:SetPoint("TOP", cell, "TOP", 0, 0)
                    cellLbl2:SetWidth(CW2 + 4); cellLbl2:SetJustifyH("CENTER"); cellLbl2:SetWordWrap(false)
                    cellLbl2:SetText(item.name)
                    iconFrame2:SetPoint("TOP", cellLbl2, "BOTTOM", 0, -LGAP2)
                else
                    iconFrame2:SetPoint("TOP", cell, "TOP", 0, 0)
                end

                cell:SetScript("OnEnter", function()
                    iconBdr2:Show()
                    if cellLbl2 then cellLbl2:SetAlpha(1) end
                end)
                cell:SetScript("OnLeave", function()
                    iconBdr2:Hide()
                    if cellLbl2 then cellLbl2:SetAlpha(0.7) end
                end)
                cell:SetScript("OnClick", function() onItemClick(item); popup:Hide() end)
            end
            gridChild:SetHeight(max(10, cY2))
        end

        local function UpdateToggle()
            local selA = accentColor.r and { accentColor.r, accentColor.g, accentColor.b, 0.25 } or { 0.05, 0.82, 0.62, 0.25 }
            local offA = { 1, 1, 1, 0.05 }
            stBg:SetColorTexture(toggleMode == "spell" and selA[1] or offA[1], toggleMode == "spell" and selA[2] or offA[2], toggleMode == "spell" and selA[3] or offA[3], toggleMode == "spell" and selA[4] or offA[4])
            mtBg:SetColorTexture(toggleMode == "macro" and selA[1] or offA[1], toggleMode == "macro" and selA[2] or offA[2], toggleMode == "macro" and selA[3] or offA[3], toggleMode == "macro" and selA[4] or offA[4])
            itBg:SetColorTexture(toggleMode == "item" and selA[1] or offA[1], toggleMode == "item" and selA[2] or offA[2], toggleMode == "item" and selA[3] or offA[3], toggleMode == "item" and selA[4] or offA[4])

            if toggleMode == "spell" then
                local spells = ns.CC_GetClassSpells()
                PopulateGrid(spells, function(item)
                    ns.CC_AddSpecBinding({
                        type = "spell", spell = item.name, spellID = item.id, icon = item.icon,
                        enabled = true, oocOnly = false, hovercast = false,
                        hoverFriendly = true, hoverEnemy = false,
                    })
                    ns._ccSelSide = "spec"; ns._ccSelIndex = #(GetSpecBindings()); RebuildPage()
                end)
            elseif toggleMode == "macro" then
                local macros = ns.CC_GetAllMacros()
                local mItems = {}
                for _, m in ipairs(macros) do
                    local prefix = m.isGlobal and "" or "(C) "
                    mItems[#mItems + 1] = { name = prefix .. m.name, icon = m.icon, macroName = m.name }
                end
                PopulateGrid(mItems, function(item)
                    ns.CC_AddSpecBinding({
                        type = "macro", macroName = item.macroName, icon = item.icon,
                        enabled = true, oocOnly = false, hovercast = false,
                        hoverFriendly = true, hoverEnemy = false,
                    })
                    ns._ccSelSide = "spec"; ns._ccSelIndex = #(GetSpecBindings()); RebuildPage()
                end)
            else -- "item"
                local eqItems = ns.CC_GetEquippedItems()
                PopulateGrid(eqItems, function(item)
                    ns.CC_AddSpecBinding({
                        type = "item", itemSlot = item.itemSlot, itemName = item.name, icon = item.icon,
                        enabled = true, oocOnly = false, hovercast = false,
                        hoverFriendly = true, hoverEnemy = false,
                    })
                    ns._ccSelSide = "spec"; ns._ccSelIndex = #(GetSpecBindings()); RebuildPage()
                end)
            end
        end
        UpdateToggle()

        spellToggle:SetScript("OnClick", function() toggleMode = "spell"; UpdateToggle() end)
        macroToggle:SetScript("OnClick", function() toggleMode = "macro"; UpdateToggle() end)
        itemToggle:SetScript("OnClick", function() toggleMode = "item"; UpdateToggle() end)

        -- Auto-close on click outside (dropdown pattern: poll IsMouseButtonDown)
        popup:SetScript("OnShow", function(p)
            p:SetScript("OnUpdate", function(m)
                if not m:IsMouseOver() and not addSpecBtn:IsMouseOver()
                   and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
        end)
        popup:SetScript("OnHide", function(p)
            p:SetScript("OnUpdate", nil)
            if ns._ccSpecPopup == p then ns._ccSpecPopup = nil end
        end)

        popup:Show()
    end)

    rightY = rightY - ADD_BTN_PAD - ADD_BTN_H - 10
    rightChild:SetHeight(max(10, math.abs(rightY)))

    -- Sticky clones for Add New + Quickbind buttons
    local stickyRightBg = CreateFrame("Frame", nil, rightOuter)
    stickyRightBg:SetHeight(ADD_BTN_H + 20)
    stickyRightBg:SetPoint("BOTTOMLEFT", rightOuter, "BOTTOMLEFT", 0, 0)
    stickyRightBg:SetPoint("BOTTOMRIGHT", rightOuter, "BOTTOMRIGHT", 0, 0)
    stickyRightBg:SetFrameLevel(rightOuter:GetFrameLevel() + 4)
    local srbTex = stickyRightBg:CreateTexture(nil, "BACKGROUND")
    srbTex:SetAllPoints(); srbTex:SetColorTexture(15/255, 17/255, 22/255, 1)
    stickyRightBg:Hide()

    local stickySpecBtn = CreateFrame("Button", nil, rightOuter)
    stickySpecBtn:SetSize(btnW, ADD_BTN_H)
    stickySpecBtn:SetPoint("BOTTOMLEFT", rightOuter, "BOTTOMLEFT", floor((sidebarW - btnW * 2 - 8) / 2), 10)
    stickySpecBtn:SetFrameLevel(rightOuter:GetFrameLevel() + 5)
    local ssBg = stickySpecBtn:CreateTexture(nil, "BACKGROUND")
    ssBg:SetAllPoints(); ssBg:SetColorTexture(0.05, 0.52, 0.39, 0.8)
    local ssLbl = MakeFont(stickySpecBtn, 11, 1, 1, 1, 1)
    ssLbl:SetPoint("CENTER"); ssLbl:SetText(EllesmereUI.L("Add New"))
    stickySpecBtn:SetScript("OnEnter", function() ssBg:SetColorTexture(0.07, 0.62, 0.49, 1) end)
    stickySpecBtn:SetScript("OnLeave", function() ssBg:SetColorTexture(0.05, 0.52, 0.39, 0.8) end)
    stickySpecBtn:SetScript("OnClick", function()
        if ns._ccSpecPopup and ns._ccSpecPopup:IsShown() then ns._ccSpecPopup:Hide(); return end
        addSpecBtn:Click()
    end)

    local stickyQBBtn = CreateFrame("Button", nil, rightOuter)
    stickyQBBtn:SetSize(btnW, ADD_BTN_H)
    stickyQBBtn:SetPoint("LEFT", stickySpecBtn, "RIGHT", 8, 0)
    stickyQBBtn:SetFrameLevel(rightOuter:GetFrameLevel() + 5)
    local sqBg = stickyQBBtn:CreateTexture(nil, "BACKGROUND")
    sqBg:SetAllPoints(); sqBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
    local sqLbl = MakeFont(stickyQBBtn, 11, 1, 1, 1, 0.5)
    sqLbl:SetPoint("CENTER"); sqLbl:SetText(EllesmereUI.L("Quickbind"))
    stickyQBBtn:SetScript("OnEnter", function() sqBg:SetColorTexture(0.35, 0.35, 0.35, 0.8); sqLbl:SetAlpha(0.9) end)
    stickyQBBtn:SetScript("OnLeave", function() sqBg:SetColorTexture(0.25, 0.25, 0.25, 0.6); sqLbl:SetAlpha(0.5) end)
    stickyQBBtn:SetScript("OnClick", function() qbBtn:Click() end)

    stickySpecBtn:Hide()
    stickyQBBtn:Hide()

    local rightBtnBottom = math.abs(rightY)
    local function UpdateRightSticky()
        local scrollVal = rightScroll:GetVerticalScroll()
        local viewH = rightScroll:GetHeight()
        if rightBtnBottom > scrollVal + viewH then
            stickyRightBg:Show(); stickySpecBtn:Show(); stickyQBBtn:Show()
            addSpecBtn:SetAlpha(0); qbBtn:SetAlpha(0)
        else
            stickyRightBg:Hide(); stickySpecBtn:Hide(); stickyQBBtn:Hide()
            addSpecBtn:SetAlpha(1); qbBtn:SetAlpha(1)
        end
    end
    local origRightWheel = rightScroll:GetScript("OnMouseWheel")
    rightScroll:SetScript("OnMouseWheel", function(self, delta)
        origRightWheel(self, delta)
        UpdateRightSticky()
    end)
    UpdateRightSticky()

    ---------------------------------------------------------------------------
    --  CENTER CONTENT
    --  Uses the standard EUI row pattern: ROW_H=50 frames with RowBg,
    --  SIDE_PAD=20, label on left, control on right.
    ---------------------------------------------------------------------------
    local centerFrame = CreateFrame("Frame", nil, root)
    centerFrame:SetSize(centerW, visibleH)
    centerFrame:SetPoint("TOPLEFT", leftOuter, "TOPRIGHT", 0, 0)
    centerFrame:SetFrameLevel(root:GetFrameLevel() + 1)

    local C_PAD = 16           -- padding inside center panel
    local ROW_H = 50           -- standard row height (matches Party Mode)
    local SIDE_PAD = 20        -- padding inside each row
    local rowW = centerW - C_PAD * 2  -- row width
    local centerY = 0
    -- Everything below the Enable Click Casting row is gated on it. Rows parent
    -- to bodyHost so we can swap in a dimmable container after that first row.
    local bodyHost = centerFrame

    -- Helper: create a standard row frame with RowBg
    local function MakeRow(yPos)
        local row = CreateFrame("Frame", nil, bodyHost)
        PP.Size(row, rowW, ROW_H)
        PP.Point(row, "TOPLEFT", bodyHost, "TOPLEFT", C_PAD, yPos)
        EllesmereUI.RowBg(row, bodyHost)
        return row
    end

    -- Helper: add a label to a row (left side)
    local function RowLabel(row, text)
        local lbl = EllesmereUI.MakeFont(row, 14, nil,
            EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
        PP.Point(lbl, "LEFT", row, "LEFT", SIDE_PAD, 0)
        lbl:SetText(EllesmereUI.L(text))
        return lbl
    end

    -- Helper: add a toggle pill to a row (right side)
    local function RowToggle(row, getValue, setValue)
        local toggleW, toggleH = 36, 18
        local pill = CreateFrame("Button", nil, row)
        pill:SetSize(toggleW, toggleH)
        PP.Point(pill, "RIGHT", row, "RIGHT", -SIDE_PAD, 0)
        pill:SetFrameLevel(row:GetFrameLevel() + 2)
        local pillBg = pill:CreateTexture(nil, "BACKGROUND"); pillBg:SetAllPoints()
        local knob = pill:CreateTexture(nil, "OVERLAY")
        knob:SetSize(toggleH - 4, toggleH - 4)
        local function Refresh()
            if getValue() then
                pillBg:SetColorTexture(0.05, 0.65, 0.45, 1)
                knob:SetColorTexture(1, 1, 1, 1)
                knob:ClearAllPoints(); knob:SetPoint("RIGHT", pill, "RIGHT", -2, 0)
            else
                pillBg:SetColorTexture(0.25, 0.25, 0.25, 1)
                knob:SetColorTexture(0.5, 0.5, 0.5, 1)
                knob:ClearAllPoints(); knob:SetPoint("LEFT", pill, "LEFT", 2, 0)
            end
        end
        Refresh()
        pill:SetScript("OnClick", function()
            setValue(not getValue())
            Refresh()
        end)
        return pill, Refresh
    end

    -------------------------------------------------------------------
    --  GLOBAL OPTIONS section
    -------------------------------------------------------------------
    -- Section header (accent-colored, matches W:SectionHeader style)
    do
        centerY = centerY - 6
        local secH = 33
        local secLabel = MakeFont(centerFrame, 11, 1, 1, 1, 0.75)
        secLabel:SetPoint("TOPLEFT", centerFrame, "TOPLEFT", C_PAD, centerY - 14)
        secLabel:SetText(EllesmereUI.L("GLOBAL OPTIONS"))
        local secLine = centerFrame:CreateTexture(nil, "ARTWORK")
        secLine:SetHeight(1)
        secLine:SetPoint("LEFT", secLabel, "RIGHT", 8, 0)
        secLine:SetPoint("RIGHT", centerFrame, "RIGHT", -C_PAD, 0)
        secLine:SetColorTexture(1, 1, 1, 0.08)
        centerY = centerY - secH
    end

    -- Row 1: Enable Click Casting (everything else gates on it). Disabled while the
    -- Clique addon is loaded -- Clique and HoverCast both bind click-casting on the
    -- same frames and cannot coexist. Clique's loaded state cannot change without a
    -- /reload, so this one-time check is authoritative for the whole session.
    do
        local row = MakeRow(centerY)
        local lbl = RowLabel(row, "Enable Click Casting")
        local pill = RowToggle(row,
            function() return cc.enabled end,
            function(v) ns.CC_SetEnabled(v); EllesmereUI:RefreshPage(true) end)
        local cliqueLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Clique")
        if cliqueLoaded then
            lbl:SetAlpha(0.4)
            pill:SetAlpha(0.3)
            pill:SetScript("OnClick", nil)  -- non-interactive while Clique owns clicks
            pill:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L('Please disable the addon "Clique" to use this feature.'))
            end)
            pill:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        centerY = centerY - ROW_H
    end

    -- Container holding every gated center control. Dimmed + click-blocked when
    -- click casting is off; built into instead of centerFrame from here down.
    local centerBody = CreateFrame("Frame", nil, centerFrame)
    centerBody:SetAllPoints(centerFrame)
    centerBody:SetFrameLevel(centerFrame:GetFrameLevel() + 1)
    bodyHost = centerBody
    local gatedTop = centerY  -- Y just below the Enable row; the gated region starts here

    -- Row 2: Trigger Bindings on Down
    do
        local row = MakeRow(centerY)
        RowLabel(row, "Trigger Bindings on Down")
        RowToggle(row,
            function() return cc.downClick end,
            function(v) ns.CC_SetDownClick(v) end)
        centerY = centerY - ROW_H
    end

    -- Row 3: Mouseover Frames
    do
        local row = MakeRow(centerY)
        RowLabel(row, "Mouseover Frames")
        local mfValues = { all = "All Unit Frames", rf = "EUI Raid Frames" }
        local mfOrder = { "all", "rf" }
        local ddCtrl = EllesmereUI.BuildDropdownControl(
            row, 160, row:GetFrameLevel() + 2,
            mfValues, mfOrder,
            function() return cc.allFrames and "all" or "rf" end,
            function(v) ns.CC_SetAllFrames(v == "all") end)
        PP.Point(ddCtrl, "RIGHT", row, "RIGHT", -SIDE_PAD, 0)
        centerY = centerY - ROW_H
    end

    -------------------------------------------------------------------
    --  PER-SPELL OPTIONS section
    -------------------------------------------------------------------
    do
        centerY = centerY - 12
        local secH = 33
        local secLabel = MakeFont(bodyHost, 11, 1, 1, 1, 0.75)
        secLabel:SetPoint("TOPLEFT", bodyHost, "TOPLEFT", C_PAD, centerY - 14)
        secLabel:SetText(EllesmereUI.L("PER-SPELL OPTIONS"))
        local secLine = bodyHost:CreateTexture(nil, "ARTWORK")
        secLine:SetHeight(1)
        secLine:SetPoint("LEFT", secLabel, "RIGHT", 8, 0)
        secLine:SetPoint("RIGHT", bodyHost, "RIGHT", -C_PAD, 0)
        secLine:SetColorTexture(1, 1, 1, 0.08)
        centerY = centerY - secH
    end

    if selectedBinding then
        -- Editing title with icon (centered, type label above name)
        do
            centerY = centerY - 10
            local titleRow = CreateFrame("Frame", nil, bodyHost)
            titleRow:SetSize(rowW, 44)
            titleRow:SetPoint("TOPLEFT", bodyHost, "TOPLEFT", C_PAD, centerY)

            -- Type label (smaller, dimmer)
            local typeStr = "Spell"
            if selectedBinding.type == "macro" then typeStr = "Macro"
            elseif selectedBinding.type == "item" then typeStr = "Item"
            elseif selectedBinding.type == "target" then typeStr = "Action"
            elseif selectedBinding.type == "menu" then typeStr = "Action"
            elseif selectedBinding.type == "dispel" then typeStr = "Preset"
            elseif selectedBinding.type == "external" then typeStr = "Preset"
            end
            local tType = MakeFont(titleRow, 11, 1, 1, 1, 0.4)
            tType:SetText(EllesmereUI.L(typeStr))

            -- Name label (larger, brighter)
            local tName = MakeFont(titleRow, 15, 1, 1, 1, 0.9)
            tName:SetText(EllesmereUI.L(ns.CC_GetBindingName(selectedBinding)))

            -- Measure widths for centering
            local typeW = tType:GetStringWidth()
            local nameW = tName:GetStringWidth()
            local textW = max(typeW, nameW)
            local iconSz = 32
            local gap = 10
            local totalW = iconSz + gap + textW

            -- Icon (vertically centered in row, spans both text lines)
            local tIcon = titleRow:CreateTexture(nil, "ARTWORK")
            tIcon:SetSize(iconSz, iconSz)
            tIcon:SetPoint("LEFT", titleRow, "CENTER", -totalW / 2, 0)
            tIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            tIcon:SetTexture(ns.CC_GetBindingIcon(selectedBinding))

            -- Position text lines to the right of icon
            tType:ClearAllPoints()
            tType:SetPoint("TOPLEFT", tIcon, "TOPRIGHT", gap, 0)
            tName:ClearAllPoints()
            tName:SetPoint("BOTTOMLEFT", tIcon, "BOTTOMRIGHT", gap, 0)

            centerY = centerY - 53
        end

        -- Keybind row (Party Mode style button)
        do
            local row = MakeRow(centerY)
            RowLabel(row, "Keybind")
            local function ApplyKey(newKey)
                selectedBinding.key = newKey
                ns.CC_ApplyBindings()
                RebuildPage()
            end
            local kbBtn = BuildKeybindButton(row, 180,
                function() return selectedBinding.key end,
                function(newKey)
                    if cc.hideKeyWarning then ApplyKey(newKey); return end
                    local conflicts = FindKeyConflicts(newKey, selectedBinding)
                    if #conflicts == 0 then ApplyKey(newKey); return end
                    EllesmereUI:ShowConfirmPopup({
                        title = EllesmereUI.L("Duplicate Keybind"),
                        message = EllesmereUI.Lf("%s is already assigned to:\n%s", ns.CC_FormatKey(newKey), table.concat(conflicts, ", ")),
                        confirmText = EllesmereUI.L("Okay"),
                        cancelText = EllesmereUI.L("Don't Show Again"),
                        onConfirm = function() ApplyKey(newKey) end,
                        onCancel = function() cc.hideKeyWarning = true; ApplyKey(newKey) end,
                    })
                end,
                function()
                    selectedBinding.key = nil
                    ns.CC_ApplyBindings()
                    RebuildPage()
                end)
            PP.Point(kbBtn, "RIGHT", row, "RIGHT", -SIDE_PAD, 0)
            centerY = centerY - ROW_H
        end

        -- Smart Rez row: when on, pressing this binding on a dead unit runs the
        -- dynamic rez logic; on a living unit the binding's normal action fires.
        do
            -- Smart Rez applies to any binding whose action is macro-expressible
            -- (so a [dead] /cast can lead and fall through to the normal action).
            -- target/menu are excluded: their native secure actions have no macro
            -- fallback (see note in BuildMacroText).
            local t = selectedBinding.type
            local canSmartRez = t == "spell" or t == "macro" or t == "item"
                or t == "dispel" or t == "external"
                or t == "trinket1" or t == "trinket2"
            if canSmartRez then
                local row = MakeRow(centerY)
                RowLabel(row, "Enable Dynamic Rez")
                RowToggle(row,
                    function() return selectedBinding.smartRez end,
                    function(v) selectedBinding.smartRez = v; ns.CC_ApplyBindings() end)
                centerY = centerY - ROW_H
            end
        end

        -- Spell/macro-specific options (not for target/menu)
        local hasAdvancedOpts = selectedBinding.type == "spell" or selectedBinding.type == "macro"
            or selectedBinding.type == "item" or selectedBinding.type == "dispel" or selectedBinding.type == "external"
            or selectedBinding.type == "trinket1" or selectedBinding.type == "trinket2"
            or selectedBinding.type == "dynamicrez"
        -- OOC-Only is available for spell/macro AND for menu/target, so the
        -- right-click context menu (or targeting) can be suppressed in combat to
        -- avoid accidental opens. Combat-gating for menu/target is enforced
        -- securely via an attribute driver (see SetGatedType).
        if hasAdvancedOpts or selectedBinding.type == "menu" or selectedBinding.type == "target" then
            local row = MakeRow(centerY)
            local oocLabel = "Only Cast Out of Combat"
            if selectedBinding.type == "menu" then
                oocLabel = "Only Open Menu Out of Combat"
            elseif selectedBinding.type == "target" then
                oocLabel = "Only Target Out of Combat"
            end
            RowLabel(row, oocLabel)
            RowToggle(row,
                function() return selectedBinding.oocOnly end,
                function(v) selectedBinding.oocOnly = v; ns.CC_ApplyBindings() end)
            centerY = centerY - ROW_H
        end

        if hasAdvancedOpts then
            -- Hovercast row (disabled for bare left/right click)
            do
                local row = MakeRow(centerY)
                local isBareMouseBtn = selectedBinding.key == "BUTTON1" or selectedBinding.key == "BUTTON2"
                RowLabel(row, "Only Cast on Actual Units (Not Frames)")
                if isBareMouseBtn then
                    -- Force off and show disabled state
                    if selectedBinding.hovercast then
                        selectedBinding.hovercast = false
                        ns.CC_ApplyBindings()
                    end
                    local pill, _ = RowToggle(row,
                        function() return false end,
                        function() end)
                    pill:SetAlpha(0.35)
                    pill:EnableMouse(false)
                    if EllesmereUI.ShowWidgetTooltip then
                        row:SetScript("OnEnter", function(self)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Hovercast is not available for unmodified left/right click"))
                        end)
                        row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    end
                else
                    RowToggle(row,
                        function() return selectedBinding.hovercast end,
                        function(v)
                            selectedBinding.hovercast = v
                            ns.CC_ApplyBindings()
                            RebuildPage()
                        end)
                end
                centerY = centerY - ROW_H
            end

            -- Hovercast targets (only when hovercast is on)
            if selectedBinding.hovercast then
                -- Friendly row
                do
                    local row = MakeRow(centerY)
                    RowLabel(row, "    Friendly Units")
                    RowToggle(row,
                        function() return selectedBinding.hoverFriendly ~= false end,
                        function(v)
                            selectedBinding.hoverFriendly = v
                            ns.CC_ApplyBindings()
                        end)
                    centerY = centerY - ROW_H
                end
                -- Enemy row
                do
                    local row = MakeRow(centerY)
                    RowLabel(row, "    Enemy Units")
                    RowToggle(row,
                        function() return selectedBinding.hoverEnemy == true end,
                        function(v)
                            selectedBinding.hoverEnemy = v
                            ns.CC_ApplyBindings()
                        end)
                    centerY = centerY - ROW_H
                end
            end
        end
    else
        -- No binding selected hint
        local hint = MakeFont(bodyHost, 12, 1, 1, 1, 0.25)
        hint:SetPoint("TOP", bodyHost, "TOP", 0, centerY - 50)
        hint:SetJustifyH("CENTER")
        hint:SetText(EllesmereUI.L("Select a binding from either sidebar to edit its options"))
    end

    ---------------------------------------------------------------------------
    --  SPELL STRIP (right edge, always visible)
    --  Narrow scrollable column of class/spec spell icons. Click to add.
    ---------------------------------------------------------------------------
    do
        local SS_ICON = 32
        local SS_PAD = 10
        local SS_GAP = 4

        -- Parent to the EUI panel (outside the scroll system) so it's flush with the window edge
        local euiPanel = scrollFrame:GetParent()
        local stripOuter = CreateFrame("Frame", nil, euiPanel or root)
        stripOuter:SetSize(SPELL_STRIP_W, visibleH)
        stripOuter:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, 0)
        stripOuter:SetFrameLevel((euiPanel or root):GetFrameLevel() + 10)
        local stripBg = stripOuter:CreateTexture(nil, "BACKGROUND")
        stripBg:SetAllPoints(); stripBg:SetColorTexture(0, 0, 0, 0.6)
        stripOuter:SetAlpha(0.35)
        local stripOverlay = CreateFrame("Frame", nil, stripOuter)
        stripOverlay:SetAllPoints()
        stripOverlay:SetFrameLevel(stripOuter:GetFrameLevel() + 20)
        stripOverlay:EnableMouse(false)
        local overlayTex = stripOverlay:CreateTexture(nil, "OVERLAY")
        overlayTex:SetAllPoints(); overlayTex:SetColorTexture(0, 0, 0, 0.5)
        local stripWantHover = false
        local stripPending = false
        local function StripUpdate()
            stripPending = false
            if stripWantHover then
                stripOuter:SetAlpha(1); overlayTex:SetAlpha(0)
            else
                stripOuter:SetAlpha(0.35); overlayTex:SetAlpha(0.5)
            end
        end
        local function StripEnter()
            stripWantHover = true
            if not stripPending then stripPending = true; C_Timer.After(0, StripUpdate) end
        end
        local function StripLeave()
            stripWantHover = false
            if not stripPending then stripPending = true; C_Timer.After(0, StripUpdate) end
        end

        stripOuter:SetScript("OnEnter", StripEnter)
        stripOuter:SetScript("OnLeave", StripLeave)
        ns._ccSpellStrip = stripOuter

        local stripScroll = CreateFrame("ScrollFrame", nil, stripOuter)
        stripScroll:SetPoint("TOPLEFT", stripOuter, "TOPLEFT", 0, -SS_PAD)
        stripScroll:SetPoint("BOTTOMRIGHT", stripOuter, "BOTTOMRIGHT", 0, SS_PAD)
        stripScroll:SetFrameLevel(stripOuter:GetFrameLevel() + 1)
        local stripChild = CreateFrame("Frame", nil, stripScroll)
        stripChild:SetWidth(SPELL_STRIP_W)
        stripScroll:SetScrollChild(stripChild)
        stripScroll:EnableMouseWheel(true)
        stripScroll:SetScript("OnMouseWheel", function(self, delta)
            local s = self:GetVerticalScroll()
            local mx = max(0, stripChild:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(max(0, min(mx, s - delta * 30)))
        end)

        local spells = ns.CC_GetClassSpells()
        local stripY = 0
        for _, sp in ipairs(spells) do
            local cell = CreateFrame("Button", nil, stripChild)
            cell:SetSize(SS_ICON, SS_ICON)
            cell:SetPoint("TOPLEFT", stripChild, "TOPLEFT", 10, stripY)

            local iconTex = cell:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTex:SetTexture(sp.icon or 134400)
            local alreadyBound = boundSpells[sp.name]
            if alreadyBound then iconTex:SetAlpha(0.3) end

            local iconBdr = CreateFrame("Frame", nil, cell)
            iconBdr:SetAllPoints()
            iconBdr:SetFrameLevel(cell:GetFrameLevel() + 1)
            iconBdr:Hide()
            if PP then PP.CreateBorder(iconBdr, accentColor.r, accentColor.g, accentColor.b, 1, 2) end

            cell:SetScript("OnEnter", function()
                iconBdr:Show()
                StripEnter()
                EllesmereUI.ShowWidgetTooltip(cell, sp.name)
            end)
            cell:SetScript("OnLeave", function()
                iconBdr:Hide()
                StripLeave()
                EllesmereUI.HideWidgetTooltip()
            end)
            cell:SetScript("OnClick", function()
                ns.CC_AddSpecBinding({
                    type = "spell", spell = sp.name, spellID = sp.id, icon = sp.icon,
                    enabled = true, oocOnly = false, hovercast = false,
                    hoverFriendly = true, hoverEnemy = false,
                })
                ns._ccSelSide = "spec"
                ns._ccSelIndex = #(GetSpecBindings())
                RebuildPage()
            end)

            stripY = stripY - (SS_ICON + SS_GAP)
        end
        stripChild:SetHeight(max(10, math.abs(stripY)))
    end

    -- Click casting off: the whole UI is gated on the Enable toggle.
    --   Sidebars  -> dim to 75% alpha + a 50% black overlay that swallows clicks.
    --   Center    -> dim the gated body to the standard disabled alpha + block clicks.
    -- (The Enable Click Casting row stays fully interactive on centerFrame above.)
    if not cc.enabled then
        for _, sb in ipairs({ leftOuter, rightOuter }) do
            sb:SetAlpha(0.6)
            local ov = CreateFrame("Frame", nil, root)
            ov:SetAllPoints(sb)
            ov:SetFrameLevel(sb:GetFrameLevel() + 100)
            ov:EnableMouse(true)
            ov:EnableMouseWheel(true)
            ov:SetScript("OnMouseWheel", function() end)
            local ovTex = ov:CreateTexture(nil, "OVERLAY")
            ovTex:SetAllPoints()
            ovTex:SetColorTexture(.08, .08, .08, 0.4)
        end

        centerBody:SetAlpha(0.4)
        -- Block only the gated region (below the Enable row) so the toggle stays usable.
        local blocker = CreateFrame("Frame", nil, centerBody)
        blocker:SetPoint("TOPLEFT", centerBody, "TOPLEFT", 0, gatedTop)
        blocker:SetPoint("BOTTOMRIGHT", centerBody, "BOTTOMRIGHT", 0, 0)
        blocker:SetFrameLevel(centerBody:GetFrameLevel() + 100)
        blocker:EnableMouse(true)
        blocker:EnableMouseWheel(true)
        blocker:SetScript("OnMouseWheel", function() end)
    end

    return 0  -- bypass framework scroll (custom root)
end
