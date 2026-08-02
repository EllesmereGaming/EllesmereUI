-------------------------------------------------------------------------------
--  EUI_QoL_PremadeFilter_Options.lua
--  Builds the "Group Finder" page inside the Quality of Life module.
--  Holds the filter panel master enable, the always-on result filters, the
--  sorting defaults, the result display options and the sign-up / dungeon
--  conveniences. The per-search filters (leader score, roles, difficulties,
--  dungeon whitelist, filter expression) sit on the Filters panel attached to
--  the Group Finder itself, which is the primary control surface for them.
-------------------------------------------------------------------------------

local function DB()
    local fn = _G._EUI_PremadeFilter_DB
    return fn and fn() or nil
end

local function P()
    local d = DB()
    return d and d.profile and d.profile.premadeFilter
end

local function Cfg(key, fallback)
    local p = P()
    if not p then return fallback end
    if p[key] == nil then return fallback end
    return p[key]
end

local function Set(key, v)
    local p = P()
    if p then p[key] = v end
end

local function Refresh()
    local fn = _G._EUI_RefreshPremadeFilter
    if fn then fn() end
end

local function RefreshDisplay()
    local fn = _G._EUI_RefreshPremadeFilterDisplay
    if fn then fn() end
end

local function FilterOff()
    return Cfg("enabled", false) ~= true
end

local FILTER_TIP = "Premade Group Filter"

-- No sort controls: reordering the browse means writing Blizzard's results
-- array, which permanently taints the Group Finder for the session (the full
-- account is in EllesmereUIQoL_PremadeFilter.lua's header). Blizzard's own
-- comparator already sorts declined groups last and friends first.
local MEMBER_VALUES = {
    DEFAULT  = "Blizzard Default",
    SPEC     = "Spec Icons",
    SPEC_BAR = "Spec Icons + Class Bar",
}
local MEMBER_ORDER = { "DEFAULT", "SPEC", "SPEC_BAR" }

_G._EUI_BuildPremadeFilterPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
    parent._showRowDivider = true

    ---------------------------------------------------------------------------
    --  FILTER PANEL
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "FILTER PANEL", y);  y = y - h

    -- Enable | Hide Delisted Groups
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Premade Group Filter",
          tooltip = "Adds a Filters panel beside the Premade Groups browser in the Group Finder, with live filtering and sorting of the search results.",
          getValue = function() return Cfg("enabled", false) end,
          setValue = function(v)
              Set("enabled", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Dim Delisted Groups",
          tooltip = "Shades groups in the results once they have been delisted or filled. Applies to every Group Finder category. Blizzard's own filter has no field for this, so the row is shaded rather than removed -- removing it would taint the Group Finder.",
          disabled = FilterOff, disabledTooltip = FILTER_TIP,
          getValue = function() return Cfg("hideDelisted", true) end,
          setValue = function(v) Set("hideDelisted", v); Refresh() end }
    );  y = y - h

    -- Hide Declined Groups | Advanced Filter Expression
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Dim Declined Groups",
          tooltip = "Shades groups that have declined your application. Applies to every Group Finder category. Blizzard already sorts declined groups to the bottom of the list.",
          disabled = FilterOff, disabledTooltip = FILTER_TIP,
          getValue = function() return Cfg("hideDeclined", false) end,
          setValue = function(v) Set("hideDeclined", v); Refresh() end },
        { type = "toggle", text = "Advanced Filter Expression",
          tooltip = "Adds an expression box to the Filters panel so you can write your own rule, e.g. score > 2800 and tanks == 0. Variables include score, members, tanks, heals, dps, age and activity -- the panel lists the full set.",
          disabled = FilterOff, disabledTooltip = FILTER_TIP,
          getValue = function() return Cfg("expressionEnabled", false) end,
          setValue = function(v) Set("expressionEnabled", v); Refresh() end }
    );  y = y - h

    -- Panel-lives-in-game note (the per-search filters are deliberately not
    -- duplicated here -- they change per search, so they belong on the panel).
    do
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath())
            or "Fonts\\FRIZQT__.TTF"
        local infoFrame = CreateFrame("Frame", nil, parent)
        infoFrame:SetSize(parent:GetWidth(), 34)
        infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 16)
        infoFrame._isSpacer = true
        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
        line1:SetFont(fontPath, 15, "")
        line1:SetTextColor(1, 1, 1, 0.75)
        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
        line1:SetJustifyH("CENTER")
        line1:SetText(EllesmereUI.L("Per-search filters live on the Filters panel in the Group Finder."))
        local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
        line2:SetFont(fontPath, 15, "")
        line2:SetTextColor(1, 1, 1, 0.75)
        line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
        line2:SetJustifyH("CENTER")
        line2:SetText(EllesmereUI.L("Score, role, difficulty and dungeon filters remove groups; everything else shades them."))
        y = y - 60
    end

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- Leader Score on Entries | Group Members
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Leader Score on Entries",
          tooltip = "Appends the group leader's Mythic+ rating, coloured by score, to each Dungeon result row.",
          getValue = function() return Cfg("showLeaderScore", false) end,
          setValue = function(v) Set("showLeaderScore", v); RefreshDisplay() end },
        { type = "dropdown", text = "Group Members",
          tooltip = "How the members already in a listed group are shown on each result row. Spec Icons replaces the role icons with each member's specialisation, and the class bar adds a colour strip for the group composition.",
          values = MEMBER_VALUES, order = MEMBER_ORDER,
          getValue = function() return Cfg("memberDisplay", "DEFAULT") end,
          setValue = function(v) Set("memberDisplay", v); RefreshDisplay() end }
    );  y = y - h

    ---------------------------------------------------------------------------
    --  SIGN-UP
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "SIGN-UP", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type="toggle", text="Quick Signup",
          tooltip="Double-click a group listing to instantly sign up without pressing the Sign Up button. Hold Shift to keep the dialog open, e.g. to type a signup note.",
          getValue=function()
              return EllesmereUIDB and EllesmereUIDB.quickSignup or false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.quickSignup = v
              if EllesmereUI._applyQuickSignup then
                  EllesmereUI._applyQuickSignup()
              end
          end },
        { type="toggle", text="Persistent Signup Note",
          tooltip="Keeps your note text in the Sign Up dialog instead of clearing it each time you open it.",
          getValue=function()
              return EllesmereUIDB and EllesmereUIDB.persistSignupNote or false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.persistSignupNote = v
              if EllesmereUI._applyPersistSignupNote then
                  EllesmereUI._applyPersistSignupNote()
              end
          end }
    );  y = y - h

    ---------------------------------------------------------------------------
    --  DUNGEON
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DUNGEON", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type="toggle", text="Auto Insert Keystone",
          tooltip="Automatically inserts your key into the Font of Power.",
          getValue=function()
              if not EllesmereUIDB then return true end
              return EllesmereUIDB.autoInsertKeystone ~= false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.autoInsertKeystone = v
          end },
        { type="toggle", text="Announce Instance Reset",
          tooltip="After a successful instance reset, automatically announces it in party or raid chat so your group knows they can re-enter.",
          getValue=function()
              return EllesmereUIDB and EllesmereUIDB.instanceResetAnnounce or false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.instanceResetAnnounce = v
              if EllesmereUI._applyInstanceResetAnnounce then
                  EllesmereUI._applyInstanceResetAnnounce()
              end
          end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return math.abs(y)
end
