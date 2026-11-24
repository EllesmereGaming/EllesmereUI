if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\BarSpells_Options.lua
--  Action Bars options: the ACTION BAR SPELLS section, the last section of the
--  Bar Display page. It is built only while the active profile holds the
--  Builder's action bar spells for this character (ns.Populate.HasData,
--  EUI_ActionBars_Populate.lua); without them the builder returns y untouched
--  and builds nothing. Populate Action Bars opens the Choose Bars view
--  (ns.PopulatePicker, EUI_ActionBars_PopulatePicker.lua). Auto Populate is
--  this character's switch for the current spec, kept in the character
--  roster: neither row writes the profile, so Spec Overrides capture neither.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

local InCombatLockdown = InCombatLockdown

-- True while the active profile has bar spells for this character (this
-- spec on Retail, this class on WoW Forever).
local function HasBarSpells()
    local P = ns.Populate
    if P and P.HasData() then return true end
    return false
end

-- Choose Bars refuses with a red chat line where it cannot open (combat,
-- Unlock Mode, Edit Mode, a vehicle). It hides the options panel while open
-- and brings it back, its rows re-read, when the player closes it.
local function OpenChooseBars()
    local picker = ns.PopulatePicker
    if picker then picker.Open() end
end

local function AutoGet()
    return ns.Populate.Auto()
end

-- SetAuto refuses without bar spells or a readable character: the refresh
-- puts the switch back to what was stored.
local function AutoSet(v)
    ns.Populate.SetAuto(v and true or false)
    EllesmereUI:RefreshPage()
end

-- Auto Populate fills only the bars ticked at the last Populate: before the
-- first Populate there are none.
local function AutoOff()
    return ns.Populate.LastBars() == nil
end

local function BuildBarSpells(parent, y)
    local has = HasBarSpells()
    -- What this build shows, for the kept page's restore check and the spec
    -- change check (ABO_BarSpellsStale).
    if not EllesmereUI._prebuilding then
        ns._ABO_OptEnv.optState.barSpellsBuilt = has
    end
    if not has then return y end

    local W = EllesmereUI.Widgets
    local _, h
    parent._showRowDivider = true

    -------------------------------------------------------------------
    --  ACTION BAR SPELLS
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ACTION BAR SPELLS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "button", text = "Populate Action Bars", width = 200, noCapture = true,
          onClick = OpenChooseBars,
          disabled = InCombatLockdown,
          disabledTooltip = "Unavailable in combat", rawTooltip = true },
        { type = "toggle", text = "Auto Populate", noCapture = true,
          tooltip = "When you learn a spell, it is placed on its button on the bars you populated.",
          getValue = AutoGet, setValue = AutoSet,
          disabled = AutoOff,
          disabledTooltip = "This option needs a Populate first", rawTooltip = true });  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return y
end

-- True when the built Bar Display page no longer matches the profile: the
-- section is there without bar spells, or missing with them (a spec change
-- behind the page). False before the page was first built.
local function BarSpellsStale()
    local built = ns._ABO_OptEnv.optState.barSpellsBuilt
    if built == nil then return false end
    return HasBarSpells() ~= built
end

-- Whether a spec change can change what the built page shows: the section is
-- there, or the active profile holds bar spells for some spec. Without any,
-- one table read.
local function BarSpellsSpecSensitive()
    local built = ns._ABO_OptEnv.optState.barSpellsBuilt
    if built == nil then return false end
    if built then return true end
    if not ns.Populate then return false end
    local p = EllesmereUI.GetActiveProfileData()
    return type(p) == "table" and type(p.abSpells) == "table"
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildBarSpells = BuildBarSpells
ns.ABO_BarSpellsStale = BarSpellsStale
ns.ABO_BarSpellsSpecSensitive = BarSpellsSpecSensitive
