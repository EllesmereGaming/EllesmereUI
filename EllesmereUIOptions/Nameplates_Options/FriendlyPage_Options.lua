if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\FriendlyPage_Options.lua
--  Nameplates options: the Friendly Plates page (BuildFriendlyPage).
--  Definitions only; the shared helpers come from ns._NPO_OptEnv (filled by
--  EUI_Nameplates_Options.lua). The two sample plates in the page's header are
--  FriendlyPreview_Options.lua's: every setter here whose setting they show
--  ends in ns.NPO_FriendlyPreviewUpdate(), and the page's last lines map the
--  samples' click overlays to its rows (env.Nav).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

local CreateFrame = EllesmereUI._Pool.CreateFrame

-------------------------------------------------------------------------------
--  The Name Only highlight entries (ns.NAME_ONLY_TARGETS): when one can paint
--  (its row greys otherwise) and when its eye can put it on a header sample.
--  File scope, because the page sets its content header before it builds its
--  rows, and the samples (FriendlyPreview_Options.lua) ask through
--  ns.NPO_AlliedPreviewOff from their first paint.
-------------------------------------------------------------------------------
local NAMEONLY_REQ = "Requires Friendly Nameplate Style set to Name Only"
local PET_PLATES_REQ = "Requires Show Friendly Pet Nameplates to be enabled"
-- The pet entries answer to their own nameplate toggle (a pet shows no plate
-- without it).
local PET_ENTRY = { PET_MINION_FRIENDLY = true }
local function Val(key) return ns._NPO_OptEnv.DBVal(key) end
local function NameOnlyOff()
    return Val("showFriendlyPlayers") == false or Val("friendlyNameOnly") == false
end
-- Whether the pet nameplates this palette paints are off. Every pet row
-- colors a plate EllesmereUI names itself, and those are friendly plates:
-- Show Friendly Pet Nameplates is what brings them up. An attackable pet's
-- plate belongs to the enemy nameplates and never reaches these colors, so
-- Show Enemy Pet Nameplates does not feed them.
local function PetPlatesOff() return Val("showFriendlyPets") ~= true end
-- Why an entry cannot paint: the nameplates of the entity it colors are off.
local function EntryDisabled(item)
    if NameOnlyOff() then return true end
    if PET_ENTRY[item.key] then return PetPlatesOff() end
    if item.sec == 1 then return false end
    -- A non-player plate outside the enemy system is a Blizzard friendly NPC
    -- plate, so its own toggle decides whether we can style it.
    return Val("showFriendlyNPCs") ~= true
end
local function EntryDisabledTip(item)
    if NameOnlyOff() then return NAMEONLY_REQ end
    if PET_ENTRY[item.key] then return PET_PLATES_REQ end
    return "Requires Show Friendly NPC Nameplates to be enabled"
end
-- Why an entry's eye cannot put it on a sample, or nil while it can: its row
-- is greyed, or the entry itself is off. An eye left on over an entry that
-- goes off shows nothing on the sample and comes back with the entry.
local function EyeOffTip(item)
    if EntryDisabled(item) then return EntryDisabledTip(item) end
    if Val(item.on) ~= true then return "Requires this highlight to be enabled" end
    return nil
end
function ns.NPO_AlliedPreviewOff(key)
    for _, item in ipairs(ns.NAME_ONLY_TARGETS) do
        if item.key == key then return EyeOffTip(item) ~= nil end
    end
    return true
end

local function BuildFriendlyPage(pageName, parent, yOffset)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults, pairs = env.DB, env.DBVal, env.defaults, env.pairs
    local pcall, PP, SearchWords, UpdatePreview = env.pcall, env.PP, env.SearchWords, env.UpdatePreview
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    -- The sample plates in the content header
    EllesmereUI:SetContentHeader(ns.NPO_BuildFriendlyHeader)

    -- Enable per-row center divider for the dual-column layout
    parent._showRowDivider = true

    -- The instance note, the page's first line, over the first section.
    y = EllesmereUI.BuildNoteRow(parent, y,
        "Friendly Nameplate customization is disabled in instances due to Blizzard limitations", { warn = true })

    -----------------------------------------------------------------------
    --  FRIENDLY PLAYERS
    -----------------------------------------------------------------------
    -- Global Search also finds both sections by the section name their rows
    -- are known by.
    SearchWords("FRIENDLY PLAYERS", nil, "OTHER NAMEPLATES")
    local playersHeader
    playersHeader, h = W:SectionHeader(parent, "FRIENDLY PLAYERS", y);  y = y - h

    local function friendlyPlayersOff() return DBVal("showFriendlyPlayers") == false end
    local function friendlyPlateOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") ~= false end
    local nameOnlyOff = NameOnlyOff
    -- Title renders INLINE with the name (one string, takes the name's own font/size/color); only the guild line below is styled by the size/color/bracket controls, so those gate on a mode that includes guild.
    local function subtitleGuildOff()
        local m = DBVal("friendlyBelowName") or "none"
        return friendlyPlayersOff() or (m ~= "guild" and m ~= "both")
    end
    -- Why a row is greyed under a Friendly Nameplate Style, shown as written: the
    -- rows of both EUI styles, of the health bar plate and of Name Only.
    local STYLE_REQ = "Requires Friendly Nameplate Style set to Name Only or Nameplate"
    local PLATE_TIP = "Requires Friendly Nameplate Style set to Nameplate"
    -- Why a control of the guild line is greyed (its row and its cog).
    local function guildOffTip()
        if friendlyPlayersOff() then return STYLE_REQ end
        return "This option requires Subtitle Text to include the Guild Name"
    end

    -- Blizzard's nameplateSize CVar, the one row of the first row's cog: read by
    -- Blizzard at load, so a change asks for a reload once the drag ends (debounced).
    local npSizeOriginal = DBVal("nameplateSize") or defaults.nameplateSize
    local npSizePendingPopup
    local npSizeRow =
        { type="slider", label="Blizzard Nameplate Size", min=1, max=5, step=1,
          tooltip="Size of Blizzard's own nameplates, which still show for friendly players inside instances. Default is 3.",
          get=function() return DBVal("nameplateSize") or defaults.nameplateSize end,
          set=function(v)
            DB().nameplateSize = v
            -- Written now: Blizzard reads it at load, before EUI's own CVar pass.
            EllesmereUI.SetCVar("nameplateSize", v, "EllesmereUINameplates")
            if v ~= npSizeOriginal then
                if npSizePendingPopup then npSizePendingPopup:Cancel() end
                npSizePendingPopup = C_Timer.NewTimer(0.5, function()
                    npSizePendingPopup = nil
                    if (DB().nameplateSize or defaults.nameplateSize) ~= npSizeOriginal then
                        EllesmereUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Changing Blizzard Nameplate Size requires a UI reload to take effect.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload    = true,
                        })
                    end
                end)
            end
          end }

    -- Friendly Nameplate Style: one dropdown over showFriendlyPlayers and
    -- friendlyNameOnly. Blizzard Default hands the friendly player plates back
    -- to Blizzard (and keeps the saved Name Only choice), Name Only and Nameplate
    -- are EUI's two forms.
    local function StyleOf()
        if DBVal("showFriendlyPlayers") == false then return "blizzard" end
        return DBVal("friendlyNameOnly") ~= false and "nameonly" or "plate"
    end
    local function SetStyle(v)
        local was = StyleOf()
        if v == was then return end
        local db = DB()
        if v == "blizzard" then
            db.showFriendlyPlayers = false
            -- Reset the three CVars EUI uniquely manages (name-only override + class color) to Blizzard defaults for a clean slate; visibility CVars stay untouched so Blizzard's panel keeps the user's values.
            if GetCVarDefault then
                for _, cvar in ipairs({
                    "nameplateShowOnlyNameForFriendlyPlayerUnits",
                    "ShowClassColorInFriendlyNameplate",
                    "nameplateUseClassColorForFriendlyPlayerUnitNames",
                }) do
                    local d = GetCVarDefault(cvar)
                    if d ~= nil then pcall(EllesmereUI.SetCVar, cvar, d, "EllesmereUINameplates") end
                end
            end
        else
            local nameOnly = v == "nameonly"
            db.friendlyNameOnly = nameOnly
            if was == "blizzard" then
                db.showFriendlyPlayers = true
                -- Back from Blizzard Default: re-assert every friendly-player CVar that SetupAuraCVars sets on load (it skips these under Blizzard Default) -- runtime is the only restore path short of /reload.
                -- One of only two places EUI is allowed to force friendly plates visible; also clears any follower-dungeon capture.
                if ns.ForceFriendlyPlayerCVarsOn then ns.ForceFriendlyPlayerCVarsOn() end
                pcall(EllesmereUI.SetCVar, "UnitNameFriendlyPlayerName", 1, "EllesmereUINameplates")
                pcall(EllesmereUI.SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0, "EllesmereUINameplates")
                pcall(EllesmereUI.SetCVar, "ShowClassColorInFriendlyNameplate", (db.classColorFriendly ~= false) and 1 or 0, "EllesmereUINameplates")
            else
                pcall(EllesmereUI.SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0, "EllesmereUINameplates")
                -- Picking Name Only means the user wants to SEE friendly plates -- the second sanctioned force-visible point.
                if nameOnly and ns.ForceFriendlyPlayerCVarsOn then ns.ForceFriendlyPlayerCVarsOn() end
            end
            -- Blizzard colors the names it draws by this CVar, and the two styles can answer differently.
            pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(db), "EllesmereUINameplates")
        end
        -- The page first, so the tab always repaints with the new style: this
        -- dropdown swaps whole row sets, and the plate/CVar pass below churns
        -- Blizzard's nameplates, which must never be able to leave the rebuilt
        -- tab unpainted.
        EllesmereUI:RefreshPage(true)
        if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
        -- Re-assert stacking after EUI takes or hands back the friendly plates (Blizzard can reset the stacking bitfield as a side effect).
        if v == "blizzard" or was == "blizzard" then ns.RefreshStackingMotion() end
        ns.NPO_FriendlyPreviewUpdate()
    end

    -- Name Color: the friendly players' names in both styles, a Custom | Class
    -- pair in the multiSwatch convention (see the guild pair below). The pick is
    -- friendlyNameColorMode; while it is unset each style reads a key of its own
    -- (ns.FriendlyNameClass), so the lit swatch follows the style in use until one
    -- is clicked, and a click sets both styles.
    local function NameClass() return ns.FriendlyNameClass(DB(), DBVal("friendlyNameOnly") ~= false) end
    local function ApplyNameColor(refresh)
        if not InCombatLockdown() then
            pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(DB()), "EllesmereUINameplates")
        end
        -- The health bar plates' names, then Name Only's composed names.
        ns.RefreshFriendlyColors()
        if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
        if refresh then EllesmereUI:RefreshPage() end
        ns.NPO_FriendlyPreviewUpdate()
    end
    local nameColorSwatches = {
        { tooltip = "Custom Color", hasAlpha = false,
          getValue = function()
              local c = DBVal("friendlyNameColor") or defaults.friendlyNameColor
              return c.r, c.g, c.b
          end,
          setValue = function(r, g, b)
              local db = DB()
              local wasClass = NameClass()
              db.friendlyNameColor = { r = r, g = g, b = b }
              -- A color picked while no pick is saved is a pick of Custom (the page
              -- refreshes where that changes which swatch is lit).
              if db.friendlyNameColorMode ~= "custom" then db.friendlyNameColorMode = "custom" end
              ApplyNameColor(wasClass)
          end,
          onClick = function(self)
              if NameClass() then
                  DB().friendlyNameColorMode = "custom"
                  ApplyNameColor(true)
                  return
              end
              if self._eabOrigClick then self._eabOrigClick(self) end
          end,
          refreshAlpha = function()
              if friendlyPlayersOff() then return 0.15 end
              return NameClass() and 0.3 or 1
          end },
        { tooltip = "Class Color", hasAlpha = false,
          getValue = function()
              local _, ct = UnitClass("player")
              local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
              if cc then return cc.r, cc.g, cc.b end
              return 1, 1, 1
          end,
          setValue = function() end,
          onClick = function()
              DB().friendlyNameColorMode = "class"
              ApplyNameColor(true)
          end,
          refreshAlpha = function()
              if friendlyPlayersOff() then return 0.15 end
              return NameClass() and 1 or 0.3
          end },
    }

    -- Show [] Around Group/Raid: the second row of the first row's cog.
    local bracketsRow =
        { type="toggle", label="Show [] Around Group/Raid",
          tooltip="Blue [Name] for party members and your raid subgroup, orange for other raid members. Not inside instances.",
          disabled=friendlyPlayersOff, disabledTooltip=STYLE_REQ, rawTooltip=true,
          get=function() return DBVal("friendlyGroupBrackets") == true end,
          set=function(v)
            DB().friendlyGroupBrackets = v and true or false
            if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
            ns.NPO_FriendlyPreviewUpdate()
          end }

    -- Name Only in Instances: the third row of the first row's cog. Blizzard draws
    -- the friendly plates inside instances, so the Nameplate style shows its plain
    -- health bar plates there; this shows those players as Name Only instead.
    local instNameOnlyRow =
        { type="toggle", label="Name Only in Instances",
          tooltip="With the Nameplate style, friendly players show as Name Only inside dungeons, raids, scenarios, arenas and battlegrounds.",
          disabled=friendlyPlateOff, disabledTooltip=PLATE_TIP, rawTooltip=true,
          get=function() return DBVal("friendlyNameOnlyInInstances") == true end,
          set=function(v)
            DB().friendlyNameOnlyInInstances = v and true or false
            if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
          end }

    -- The health bar plate's two rows (the bar's size; its color and the health
    -- percent) are on the page only under the Nameplate style, and the name size
    -- row holds the slider of the style in use: a pick of the style builds the
    -- page again (SetStyle). While the two rows are off the page, Global Search
    -- finds the style row by their names.
    local plateStyle = StyleOf() == "plate"
    local OFF_PAGE = plateStyle and {} or { "Health Bar Width", "Health Bar Height", "Health Bar Color",
        "Class Colored Health Bar", "Show Health Percent" }

    -- The dropdown's cog has no label on the page: Global Search finds the row
    -- by the cog's rows and their tooltips too, and by the names Show EUI Friendly
    -- Player Nameplates and Make Friendly Nameplates Name Only; Name Color by
    -- Class Colored Names and its swatches' names.
    SearchWords("Friendly Nameplate Style", "FRIENDLY PLAYERS", "Show EUI Friendly Player Nameplates",
        "Make Friendly Nameplates Name Only", npSizeRow.label, npSizeRow.tooltip, bracketsRow.label, bracketsRow.tooltip,
        instNameOnlyRow.label, instNameOnlyRow.tooltip,
        unpack(OFF_PAGE))
    SearchWords("Name Color", "FRIENDLY PLAYERS", "Class Colored Names", "Class Color", "Custom Color",
        "Player Pets & Minions", "Player Relationships")
    local friendlyRow
    friendlyRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Friendly Nameplate Style",
          values={ blizzard="Blizzard Default", nameonly="Name Only", plate="Nameplate" },
          order={ "blizzard", "nameonly", "plate" },
          getValue=StyleOf,
          setValue=SetStyle },
        { type="multiSwatch", text="Name Color",
          disabled=friendlyPlayersOff,
          disabledTooltip=STYLE_REQ, rawTooltip=true,
          swatches = nameColorSwatches });  y = y - h

    -- (Its cog is built further down, once the pet plate's rows exist: the
    -- section keeps the six rows it was cut to, so they share one cog.)

    ---------------------------------------------------------------
    --  Name Only target highlights: one toggle + color per entity
    --  (EUI_Nameplates_AlliedColors.lua holds the list and the resolution).
    --  Players here, off the Name Color row whose color they override; the
    --  NPC entries on the NPC name size row below, in their section.
    ---------------------------------------------------------------
    local ALLIED = ns.NAME_ONLY_TARGETS
    local petPlatesOff = PetPlatesOff
    -- A pet plate's own settings answer to the pet plates being on, and (in Name
    -- Only) to the friendly player nameplates being on at all.
    local function petOverlayOff() return petPlatesOff() or nameOnlyOff() end
    local function petOverlayTip()
        if nameOnlyOff() then return NAMEONLY_REQ end
        return PET_PLATES_REQ
    end
    -- A widget's color changed under the popup: repaint the live plates, the
    -- NPC overlay's names, and the players' composed names. RefreshFriendlyBelowName
    -- already recomposes the name-only text (SweepPlayerSubText), so it is not
    -- called twice.
    local function RepaintAlliedColors()
        if ns.RefreshFriendlyColors then ns.RefreshFriendlyColors() end
        if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
        if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
        ns.NPO_FriendlyPreviewUpdate()
    end
    -- One entry's toggle + swatch, in the cog popup's togglecolor form, with the
    -- eye that puts its color on the sample at the top of the page.
    local PREVIEW_KEY = { player = "friendlyPlayerPreview", npc = "friendlyNPCPreview" }
    local function EntryRow(item)
        local sample = ns.Allied and ns.Allied.PreviewTarget and ns.Allied.PreviewTarget(item.key)
        local previewKey = sample and PREVIEW_KEY[sample]
        local row = {
            type = "togglecolor",
            label = item.label,
            tooltip = item.tip,
            rawTooltip = true,
            disabled = function() return EntryDisabled(item) end,
            disabledTooltip = function() return EntryDisabledTip(item) end,
            getToggle = function() return DBVal(item.on) == true end,
            setToggle = function(v)
                DB()[item.on] = v and true or false
                RepaintAlliedColors()
            end,
            getColor = function()
                local c = DBVal(item.col) or defaults[item.col] or item.defColor
                return c.r, c.g, c.b
            end,
            setColor = function(r, g, b)
                DB()[item.col] = { r = r, g = g, b = b }
                RepaintAlliedColors()
            end,
        }
        if previewKey then
            -- The eye: this entry's color goes on the player's or the NPC's
            -- sample, so a swatch is picked against a plate rather than guessed.
            -- One entry per sample at a time; the eye shows which one. It works
            -- only while the entry is on and its row is not greyed (EyeOffTip),
            -- and reads closed meanwhile.
            row.eye = {
                tooltip = "Show/Hide on Preview",
                enabled = function() return EyeOffTip(item) == nil end,
                disabledTooltip = function() return EyeOffTip(item) end,
                get = function()
                    return EyeOffTip(item) == nil and env.optState[previewKey] == item.key
                end,
                set = function(v)
                    env.optState[previewKey] = v and item.key or nil
                    ns.NPO_FriendlyPreviewUpdate()
                end,
            }
        end
        return row
    end
    local function RowsForSec(sec)
        local rows = {}
        for _, item in ipairs(ALLIED) do
            if item.sec == sec then rows[#rows + 1] = EntryRow(item) end
        end
        return rows
    end
    -- Reset the color of one section, or of every section when none is named.
    -- One repaint for the lot: the popup re-reads its swatches itself.
    local function ResetAlliedColors(...)
        local secs = { ... }
        local all = #secs == 0
        for _, item in ipairs(ALLIED) do
            local hit = all
            for i = 1, #secs do
                if item.sec == secs[i] then hit = true; break end
            end
            if hit then
                local def = defaults[item.col] or item.defColor
                if def then DB()[item.col] = { r = def.r, g = def.g, b = def.b } end
            end
        end
        RepaintAlliedColors()
    end
    do
        EllesmereUI.BuildInlineCog(friendlyRow._rightRegion, {
            chain = true,
            disabled = nameOnlyOff,
            disabledTooltip = NAMEONLY_REQ,
            rawTooltip = true,
            tip = "Nameplate Highlights",
            title = "Nameplate Highlights",
            sections = { { title = "Player Relationships", rows = RowsForSec(1) } },
            footer = {
                buttonText = "Set Player Colors to Default",
                buttonWidth = 190,
                buttonTooltip = "Resets the colors above to their defaults.\n\nYour toggle selections are preserved.",
                buttonAction = function() ResetAlliedColors(1) end,
            },
        })
    end

    ---------------------------------------------------------------
    --  The health bar plate: size, color, health percent (Nameplate style only)
    ---------------------------------------------------------------
    -- Health Bar Color: a Custom | Class pair in the multiSwatch convention over
    -- the bar's two keys (classColorFriendly, friendlyBarColor).
    local function BarClass() return DBVal("classColorFriendly") ~= false end
    local function ApplyBarClass()
        -- Blizzard's instance plates color their names by this CVar, which reads
        -- the bar's class color while no Name Color is picked.
        if not InCombatLockdown() then
            pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(DB()), "EllesmereUINameplates")
        end
        ns.RefreshAllSettings()
        EllesmereUI:RefreshPage()
        ns.NPO_FriendlyPreviewUpdate()
    end
    local barColorSwatches = {
        { tooltip = "Custom Color", hasAlpha = false,
          getValue = function()
              local c = DBVal("friendlyBarColor") or defaults.friendlyBarColor
              return c.r, c.g, c.b
          end,
          setValue = function(r, g, b)
              local db = DB()
              db.friendlyBarColor = { r = r, g = g, b = b }
              -- A color picked while the bar is class colored is a pick of Custom.
              if db.classColorFriendly ~= false then
                  db.classColorFriendly = false
                  ApplyBarClass()
                  return
              end
              ns.RefreshFriendlyColors()
              ns.NPO_FriendlyPreviewUpdate()
          end,
          onClick = function(self)
              if BarClass() then
                  DB().classColorFriendly = false
                  ApplyBarClass()
                  return
              end
              if self._eabOrigClick then self._eabOrigClick(self) end
          end,
          refreshAlpha = function()
              if friendlyPlateOff() then return 0.15 end
              return BarClass() and 0.3 or 1
          end },
        { tooltip = "Class Color", hasAlpha = false,
          getValue = function()
              local _, ct = UnitClass("player")
              local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
              if cc then return cc.r, cc.g, cc.b end
              return 1, 1, 1
          end,
          setValue = function() end,
          onClick = function()
              DB().classColorFriendly = true
              ApplyBarClass()
          end,
          refreshAlpha = function()
              if friendlyPlateOff() then return 0.15 end
              return BarClass() and 1 or 0.3
          end },
    }

    local barSizeRow, barColorRow
    if plateStyle then
        barSizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Health Bar Width", min=80, max=250, step=1,
              disabled=friendlyPlateOff, disabledTooltip=PLATE_TIP, rawTooltip=true,
              getValue=function() return DBVal("friendlyHealthBarWidth") or defaults.friendlyHealthBarWidth end,
              setValue=function(v)
                DB().friendlyHealthBarWidth = v
                if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end
                ns.NPO_FriendlyPreviewUpdate()
              end },
            { type="slider", text="Health Bar Height", min=6, max=40, step=1,
              disabled=friendlyPlateOff, disabledTooltip=PLATE_TIP, rawTooltip=true,
              getValue=function() return DBVal("friendlyHealthBarHeight") or defaults.friendlyHealthBarHeight end,
              setValue=function(v)
                DB().friendlyHealthBarHeight = v
                if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end
                ns.NPO_FriendlyPreviewUpdate()
              end });  y = y - h

        SearchWords("Health Bar Color", "FRIENDLY PLAYERS", "Class Colored Health Bar", "Class Color", "Custom Color")
        barColorRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Health Bar Color",
              disabled=friendlyPlateOff, disabledTooltip=PLATE_TIP, rawTooltip=true,
              swatches = barColorSwatches },
            -- Off (friendlyHideHealthText), or the side of the bar the text sits on
            -- (friendlyHealthTextPos: "left" or "center", unset = the right).
            { type="dropdown", text="Show Health Percent",
              disabled=friendlyPlateOff, disabledTooltip=PLATE_TIP, rawTooltip=true,
              values={ none="None", right="Right", left="Left", center="Center" },
              order={ "none", "right", "left", "center" },
              getValue=function()
                if DBVal("friendlyHideHealthText") then return "none" end
                local pos = DBVal("friendlyHealthTextPos")
                return (pos == "left" or pos == "center") and pos or "right"
              end,
              setValue=function(v)
                local db = DB()
                if v == "none" then
                    db.friendlyHideHealthText = true
                else
                    db.friendlyHideHealthText = false
                    db.friendlyHealthTextPos = (v ~= "right") and v or nil
                end
                if ns.RefreshFriendlyHealthText then ns.RefreshFriendlyHealthText() end
                ns.NPO_FriendlyPreviewUpdate()
              end });  y = y - h
    end

    ---------------------------------------------------------------
    --  Name size (the slider of the style in use; its cog holds that style's
    --  vertical distance) and the Name Format
    ---------------------------------------------------------------
    -- The friendly Name Format (a friendly player's name, in both modes); Full
    -- Name is saved as unset. WoW Forever explains it for players, as Forever
    -- Essentials' Name Format section does (it only ever shaped players' names).
    local pnfValues, pnfOrder, pnfGet, pnfSet = EllesmereUI.NameFormatMenu(
        function() return DBVal("friendlyNameFormat") end,
        function(v)
            DB().friendlyNameFormat = (v ~= "full") and v or nil
            ns.NP_SyncFriendlyNameFormat()
            ns.NPO_FriendlyPreviewUpdate()
        end)

    -- Each style has its own size and distance: the health bar plates' while the
    -- saved style is Nameplate (Blizzard Default keeps the one it would go back to).
    local barNameSize = DBVal("friendlyNameOnly") == false
    local nameSizeCfg
    if barNameSize then
        SearchWords("Friendly Name Size", "FRIENDLY PLAYERS", "Friendly Name Size (Bar Mode)", "Nameplate Offset", "Distance")
        nameSizeCfg =
            { type="slider", text="Friendly Name Size", trackWidth=120,
              min=6, max=30, step=1,
              disabled=friendlyPlateOff, disabledTooltip=PLATE_TIP, rawTooltip=true,
              getValue=function() return DBVal("friendlyNameTextSize") or defaults.friendlyNameTextSize end,
              setValue=function(v)
                DB().friendlyNameTextSize = v
                if ns.RefreshFriendlyNameTextSize then ns.RefreshFriendlyNameTextSize() end
                ns.NPO_FriendlyPreviewUpdate()
              end }
    else
        SearchWords("Friendly Name Size", "FRIENDLY PLAYERS",
            "Adjusts the size of friendly player names shown in Name Only mode. Default is 15.", "Name Distance", "Distance")
        nameSizeCfg =
            { type="slider", text="Friendly Name Size", trackWidth=120,
              min=8, max=30, step=1,
              disabled=nameOnlyOff,
              disabledTooltip=NAMEONLY_REQ, rawTooltip=true,
              getValue=function() return DBVal("friendlyNameSize") or defaults.friendlyNameSize end,
              setValue=function(v)
                DB().friendlyNameSize = v
                if ns.RefreshFriendlyNameSize then ns.RefreshFriendlyNameSize() end
                ns.NPO_FriendlyPreviewUpdate()
              end,
              tooltip="Adjusts the size of friendly player names shown in Name Only mode. Default is 15." }
    end
    local sizeRow
    sizeRow, h = W:DualRow(parent, y,
        nameSizeCfg,
        { type="dropdown", text="Player Name Format",
          tooltip=EllesmereUI.IS_FOREVER == true and "Friendly player names on nameplates, in both modes." or nil,
          disabled=friendlyPlayersOff,
          disabledTooltip=STYLE_REQ, rawTooltip=true,
          values=pnfValues, order=pnfOrder, getValue=pnfGet, setValue=pnfSet });  y = y - h

    do
        if barNameSize then
            EllesmereUI.BuildInlineCog(sizeRow._leftRegion, {
                disabled = friendlyPlateOff,
                disabledTooltip = PLATE_TIP, rawTooltip = true,
                title = "Nameplate Offset",
                rows = {
                    { type = "slider", label = "Distance", min = -50, max = 50, step = 1,
                      get = function() return DBVal("friendlyPlateYOffset") or 0 end,
                      set = function(v) DB().friendlyPlateYOffset = v; if ns.RefreshFriendlyPlateYOffset then ns.RefreshFriendlyPlateYOffset() end end },
                },
            })
        else
            EllesmereUI.BuildInlineCog(sizeRow._leftRegion, {
                disabled = nameOnlyOff,
                title = "Name Distance",
                rows = {
                    { type = "slider", label = "Distance", min = -50, max = 50, step = 1,
                      get = function() return DBVal("friendlyNameOnlyYOffset") or defaults.friendlyNameOnlyYOffset end,
                      set = function(v)
                        DB().friendlyNameOnlyYOffset = v
                        if ns.RefreshFriendlyNameOnlyOffset then ns.RefreshFriendlyNameOnlyOffset() end
                      end },
                },
            })
        end
    end

    ---------------------------------------------------------------
    --  Level Text and Subtitle Text. The title renders inline with the name, the
    --  guild sits on its own line below; the color pair styles ONLY the guild
    --  line -- the inline title is part of the name string, using its color.
    ---------------------------------------------------------------
    -- Custom/Class pair follows the multiSwatch convention: clicking the INACTIVE custom swatch only selects custom mode (click again to open the picker); the inactive swatch dims, both grey out together.
    local function MakeGuildColorSwatches()
        return {
            { tooltip = "Custom Guild Color", hasAlpha = false,
              getValue = function()
                  local c = DBVal("friendlyBelowNameColor") or defaults.friendlyBelowNameColor
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  DB().friendlyBelowNameColor = { r = r, g = g, b = b }
                  if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                  ns.NPO_FriendlyPreviewUpdate()
              end,
              onClick = function(self)
                  if DBVal("friendlyBelowNameClassColor") == true then
                      DB().friendlyBelowNameClassColor = false
                      if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                      EllesmereUI:RefreshPage()
                      ns.NPO_FriendlyPreviewUpdate()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return (DBVal("friendlyBelowNameClassColor") == true) and 0.3 or 1
              end },
            { tooltip = "Class Guild Color", hasAlpha = false,
              getValue = function()
                  local _, ct = UnitClass("player")
                  local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
                  if cc then return cc.r, cc.g, cc.b end
                  return 1, 1, 1
              end,
              setValue = function() end,
              onClick = function()
                  DB().friendlyBelowNameClassColor = true
                  if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                  EllesmereUI:RefreshPage()
                  ns.NPO_FriendlyPreviewUpdate()
              end,
              refreshAlpha = function()
                  return (DBVal("friendlyBelowNameClassColor") == true) and 1 or 0.3
              end },
        }
    end

    -- Level Text: off, or the level in the name's color or by difficulty
    -- (friendlyShowLevel, friendlyLevelDiffColor). Subtitle Text: a checklist
    -- over friendlyBelowName and the guild line's brackets; its stand-in
    -- dropdown reads those keys, so Spec Overrides know the slot by them. Both
    -- answer in Global Search to the names their settings had.
    local SUBTITLE_TIP = "Show the player's title inline with their name, and/or their guild on a line below it, on friendly nameplates."
    -- Guild Text Size: a row of Subtitle Text's cog. The guild line is a text of
    -- its own in both styles, so the slider sets it wherever a guild shows.
    local guildSizeRow =
        { type="slider", label="Guild Text Size", min=6, max=30, step=1,
          tooltip="Size of the guild line under friendly player names.",
          disabled=subtitleGuildOff,
          disabledTooltip=function() return guildOffTip() end,
          rawTooltip=true,
          get=function() return DBVal("friendlyBelowNameSize") or defaults.friendlyBelowNameSize end,
          set=function(v)
            DB().friendlyBelowNameSize = v
            if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
            ns.NPO_FriendlyPreviewUpdate()
          end }
    -- The guild line takes the player's own name color -- a target highlight
    -- when one applies, else the name's custom or class color -- instead of
    -- the pair of swatches on the row.
    local matchNameRow =
        { type="toggle", label="Match Player Name Color",
          tooltip="Colors the guild name to match the player's name color, including target highlights.\n\nWhen disabled, the guild uses the Guild Color swatches.",
          disabled=subtitleGuildOff,
          disabledTooltip=function() return guildOffTip() end,
          rawTooltip=true,
          get=function() return DBVal("friendlyBelowNameMatchNameColor") == true end,
          set=function(v)
            DB().friendlyBelowNameMatchNameColor = v and true or false
            if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
            -- The guild swatches grey out with it.
            EllesmereUI:RefreshPage()
            ns.NPO_FriendlyPreviewUpdate()
          end }
    SearchWords("Level Text", "FRIENDLY PLAYERS", "Show Level", "Color Level by Difficulty")
    SearchWords("Subtitle Text", "FRIENDLY PLAYERS", SUBTITLE_TIP, "Player Title", "Guild Name", "Title & Guild", "Guild Text Color",
        "Show <> Around Guild", "Name Text Settings", "Custom Color", "Class Color", guildSizeRow.label, guildSizeRow.tooltip,
        matchNameRow.label, matchNameRow.tooltip)
    local levelRow
    levelRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Level Text",
          disabled=friendlyPlayersOff,
          disabledTooltip=STYLE_REQ, rawTooltip=true,
          values={ none="None", plain="Plain Colored", diff="Difficulty Colored" },
          order={ "none", "plain", "diff" },
          getValue=function()
            if DBVal("friendlyShowLevel") ~= true then return "none" end
            return DBVal("friendlyLevelDiffColor") == true and "diff" or "plain"
          end,
          setValue=function(v)
            local db = DB()
            if v == "none" then
                db.friendlyShowLevel = false
            else
                db.friendlyShowLevel = true
                db.friendlyLevelDiffColor = v == "diff"
            end
            if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
            ns.NPO_FriendlyPreviewUpdate()
          end },
        { type="dropdown", text="Subtitle Text",
          tooltip=SUBTITLE_TIP,
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function()
            local _ = DBVal("friendlyBelowName"), DBVal("friendlyBelowNameGuildBrackets")
            return "__placeholder"
          end,
          setValue=function() end });  y = y - h

    do
        local rgn = levelRow._rightRegion
        if not EllesmereUI._prebuilding then
            if rgn._control then rgn._control:Hide() end
            local function HasTitle() local m = DBVal("friendlyBelowName"); return m == "title" or m == "both" end
            local function HasGuild() local m = DBVal("friendlyBelowName"); return m == "guild" or m == "both" end
            local function Bracketed() return DBVal("friendlyBelowNameGuildBrackets") ~= false end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                { { key = "title", label = "Player Title" },
                  { key = "guild", label = "Guild Name" },
                  { key = "guildB", label = "<Guild Name>" } },
                function(k)
                    if k == "title" then return HasTitle() end
                    if k == "guild" then return HasGuild() and not Bracketed() end
                    return HasGuild() and Bracketed()
                end,
                function(k, v)
                    local db = DB()
                    local title, guild = HasTitle(), HasGuild()
                    if k == "title" then
                        title = v and true or false
                    else
                        -- The two guild entries are one line in two forms: a tick of one
                        -- takes the other's place, and unticking the ticked one hides the line.
                        guild = v and true or false
                        if v then db.friendlyBelowNameGuildBrackets = (k == "guildB") end
                    end
                    db.friendlyBelowName = (title and guild and "both") or (title and "title") or (guild and "guild") or "none"
                    if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                    -- The guild color swatches grey with the guild line.
                    EllesmereUI:RefreshPage()
                    ns.NPO_FriendlyPreviewUpdate()
                end,
                nil, nil, nil, nil, nil,
                { noAllLabel = true, notifyWrites = true,
                  disabled = friendlyPlayersOff, disabledTooltip = STYLE_REQ, rawTooltip = true })
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        -- The cog sits nearest the checklist; the swatches chain left of it.
        -- It greys with the guild line, not with the style: the line is painted
        -- in both styles, as a text of its own.
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Subtitle Text Settings",
            rows = { guildSizeRow, matchNameRow },
            disabled = subtitleGuildOff,
            disabledTooltip = guildOffTip,
            rawTooltip = true,
        })
    end
    -- Inline swatches, left of the cog: the guild line's color, live while
    -- the subtitle shows a guild and the line does not take the name's color.
    local function guildSwatchOff() return subtitleGuildOff() or DBVal("friendlyBelowNameMatchNameColor") == true end
    -- The style and the guild line first: Match Player Name Color only matters
    -- once the line shows.
    local function guildSwatchOffTip()
        if subtitleGuildOff() then return guildOffTip() end
        return "Requires Match Player Name Color to be off"
    end
    EllesmereUI.BuildInlineSwatches(levelRow._rightRegion, MakeGuildColorSwatches(),
        { disabled = guildSwatchOff, disabledTooltip = guildSwatchOffTip, rawTooltip = true })

    -- Show Friendly Pet Nameplates: the plate's toggle, in both styles, with the
    -- name size and the owner line in its cog. Unset until the user clicks it, so
    -- a profile that never touches it leaves the client's pet CVars alone.
    local petRow
    petRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Friendly Pet Nameplates",
          tooltip="Friendly player pets and minions get a nameplate of their own. In Name Only style it shows just the name.",
          disabled=friendlyPlayersOff, disabledTooltip=STYLE_REQ, rawTooltip=true,
          getValue=function() return DBVal("showFriendlyPets") == true end,
          setValue=function(v)
            DB().showFriendlyPets = v
            if ns.ApplyPetCVars then ns.ApplyPetCVars("friendly") end
            if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
            EllesmereUI:RefreshPage()  -- the pet name size greys with the toggle
            ns.NPO_FriendlyPreviewUpdate()
          end },
        { type="toggle", text="Target Border Effects",
          tooltip="Also applies the target Border Color and Border Size effects to friendly nameplates.",
          -- Borders stand down under the stock styles.
          disabled=function()
            return friendlyPlateOff() or EllesmereUI.BlizzStyle.Get("nameplates")
                or not (ns.GetTargetGlowBorderColor() or ns.GetTargetGlowBorderSize())
          end,
          disabledTooltip=function()
            if friendlyPlateOff() then return PLATE_TIP end
            if EllesmereUI.BlizzStyle.Get("nameplates") then
                return EllesmereUI.BlizzStyle.Label("nameplates")
            end
            return "This option requires the Border Color or Border Size target effect."
          end,
          rawTooltip=function() return friendlyPlateOff() or not EllesmereUI.BlizzStyle.Get("nameplates") end,
          requireState="disabled",
          getValue=function() return DBVal("friendlyTargetBorderFx") == true end,
          setValue=function(v)
            DB().friendlyTargetBorderFx = v
            -- Applies to (or restores) the friendly target now.
            for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
            UpdatePreview()
          end });  y = y - h

    -- Health Ticks and Health Animations switches for the health bar plate
    -- (Nameplate style only, as the bar's own rows).
    if plateStyle and EllesmereUI.HealthTicksPlaceCfg and EllesmereUI.HealthAnimationsPlaceCfg then
        local ticks, anim = EllesmereUI.HealthTicksPlaceCfg("friendly"), EllesmereUI.HealthAnimationsPlaceCfg("friendly")
        local placeRow
        placeRow, h = W:DualRow(parent, y, ticks, anim.damage);  y = y - h
        ticks.attach(placeRow._leftRegion)
        anim.AddEditLook(placeRow._rightRegion)
        _, h = W:DualRow(parent, y, anim.heal, EllesmereUI.BlankRowCfg());  y = y - h
    end

    ---------------------------------------------------------------
    --  Friendly pets: the pet plate's owner line
    ---------------------------------------------------------------
    -- The owner line always shows its owner, so its four settings answer only to
    -- the pet nameplates themselves, never to the NPC subtitle's switches.
    local petOwnerMatchNameRow =
        { type="toggle", label="Match Pet Name Color",
          tooltip="Colors the owner's name to match the pet's name color.\n\nWhen disabled, the owner line uses the Owner Text Color swatch.",
          disabled=petOverlayOff, disabledTooltip=petOverlayTip, rawTooltip=true,
          get=function() return DBVal("friendlyPetOwnerMatchNameColor") == true end,
          set=function(v)
            DB().friendlyPetOwnerMatchNameColor = v and true or false
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            ns.NPO_FriendlyPreviewUpdate()
          end }
    local petOwnerColorRow =
        { type="colorpicker", label="Owner Text Color", hasAlpha=true,
          tooltip="Color of the owner's name under a friendly pet's name.\n\nWith Match Pet Name Color on, the pet's name color is used and only this swatch's transparency applies.",
          disabled=petOverlayOff, disabledTooltip=petOverlayTip, rawTooltip=true,
          get=function()
            local c = DBVal("friendlyPetOwnerColor") or defaults.friendlyPetOwnerColor
            return c.r, c.g, c.b, c.a
          end,
          set=function(r, g, b, a)
            DB().friendlyPetOwnerColor = { r = r, g = g, b = b, a = a or 1 }
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            ns.NPO_FriendlyPreviewUpdate()
          end }
    -- Owner Text Uses Its Own Size: off, the owner line takes the pet name's size,
    -- and Owner Text Size below has nothing to set.
    local petOwnerSizeRow =
        { type="toggle", label="Owner Text Uses Its Own Size",
          tooltip="Off, the owner's name under a pet's name takes the pet name's size.\n\nOn, Owner Text Size sets it.",
          disabled=petOverlayOff, disabledTooltip=petOverlayTip, rawTooltip=true,
          get=function() return DBVal("friendlyPetOwnerOwnSize") == true end,
          set=function(v)
            DB().friendlyPetOwnerOwnSize = v and true or false
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            -- Owner Text Size greys with it.
            EllesmereUI:RefreshPage()
            ns.NPO_FriendlyPreviewUpdate()
          end }
    local petTitleSizeRow =
        { type="slider", label="Owner Text Size", min=6, max=30, step=1,
          tooltip="Size of the line under a friendly pet's name, where its owner is named.",
          disabled=function() return petOverlayOff() or DBVal("friendlyPetOwnerOwnSize") ~= true end,
          disabledTooltip=function()
            if petOverlayOff() then return petOverlayTip() end
            return "Owner Text Uses Its Own Size"
          end,
          rawTooltip=function() return petOverlayOff() end,
          get=function() return DBVal("friendlyPetTitleSize") or defaults.friendlyPetTitleSize end,
          set=function(v)
            DB().friendlyPetTitleSize = v
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            ns.NPO_FriendlyPreviewUpdate()
          end }
    SearchWords("Show Friendly Pet Nameplates", "FRIENDLY PLAYERS", "Friendly Pet Name Size",
        "Owner Text Size", petOwnerColorRow.label, petOwnerMatchNameRow.label,
        petOwnerSizeRow.label, petOwnerSizeRow.tooltip, petTitleSizeRow.tooltip)
    -- The Friendly Nameplate Style row's cog: the plate basics, none of which has
    -- a row of its own. Never
    -- greyed: its size slider sizes Blizzard's own plates, which show whatever
    -- the settings here say (the rows grey by themselves as their own
    -- requirements fail). Quiet: the dropdown's writes never light its dot.
    do
        EllesmereUI.BuildInlineCog(friendlyRow._leftRegion, {
            title = "Friendly Nameplate Settings",
            rows = { npSizeRow, bracketsRow, instNameOnlyRow },
            quiet = true,
        })
    end

    -- The pet plate's cog, beside its toggle: the name's size first, then the
    -- owner line's settings.
    do
        EllesmereUI.BuildInlineCog(petRow._leftRegion, {
            title = "Pet Nameplates",
            rows = {
                { type = "slider", label = "Friendly Pet Name Size", min = 6, max = 30, step = 1,
                  disabled = petOverlayOff, disabledTooltip = petOverlayTip, rawTooltip = true,
                  get = function() return DBVal("friendlyPetNameSize") or defaults.friendlyPetNameSize end,
                  set = function(v)
                    DB().friendlyPetNameSize = v
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                    ns.NPO_FriendlyPreviewUpdate()
                  end },
                petOwnerColorRow,
                petOwnerMatchNameRow,
                petOwnerSizeRow,
                petTitleSizeRow,
            },
            disabled = friendlyPlayersOff,
            disabledTooltip = STYLE_REQ,
            rawTooltip = true,
        })
    end

    -- Friendly Names Not Clickable | Status Tags, the section's last row. Status
    -- Tags is a checklist over friendlyStatusTagAFK and friendlyStatusTagDND (both
    -- off); its stand-in dropdown reads both keys, so Spec Overrides know the slot.
    local tagsRow
    tagsRow, h = W:DualRow(parent, y,
        { type="toggle", text="Friendly Names Not Clickable",
          tooltip="Make friendly player and NPC nameplates click-through so their names never block your mouse or cause accidental friendly targeting.\n\nUse this when friendly names get in the way of clicking the world or the enemy nameplates behind them.",
          getValue=function() return DBVal("friendlyClickThrough") == true end,
          setValue=function(v)
            DB().friendlyClickThrough = v
            if ns.UpdateFriendlyClickThrough then ns.UpdateFriendlyClickThrough() end
          end },
        { type="dropdown", text="Status Tags",
          tooltip="Adds a player's <AFK> or <DND> tag to their name.",
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function()
            local _ = DBVal("friendlyStatusTagAFK"), DBVal("friendlyStatusTagDND")
            return "__placeholder"
          end,
          setValue=function() end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = tagsRow._rightRegion
        if rgn._control then rgn._control:Hide() end
        local TAG_KEYS = { afk = "friendlyStatusTagAFK", dnd = "friendlyStatusTagDND" }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 170, rgn:GetFrameLevel() + 2,
            { { key = "afk", label = "AFK" },
              { key = "dnd", label = "Do Not Disturb" } },
            function(k) return DBVal(TAG_KEYS[k]) == true end,
            function(k, v)
                DB()[TAG_KEYS[k]] = v and true or false
                -- Arms or drops the flags listener, then repaints the names.
                if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
                if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                -- The preview eye greys with the last tag unticked.
                EllesmereUI:RefreshPage()
                ns.NPO_FriendlyPreviewUpdate()
            end,
            nil, nil, nil, nil, nil,
            { noAllLabel = true, notifyWrites = true,
              disabled = friendlyPlayersOff, disabledTooltip = STYLE_REQ, rawTooltip = true })
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

        -- The eye beside Status Tags: the player sample wears a tag while it is on
        -- (off until asked, as the marker's eye): <AFK> while AFK is ticked, else
        -- <DND>. Greyed while no tag is ticked or friendly player names are not ours.
        local optState = env.optState
        local function Off()
            return friendlyPlayersOff() or not (DBVal("friendlyStatusTagAFK") == true or DBVal("friendlyStatusTagDND") == true)
        end
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        rgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshEye()
            -- The art is named the other way round: the "invisible" file is the open eye.
            eyeTex:SetTexture(optState.showStatusTagPreview and EllesmereUI.EYE_INVISIBLE_ICON or EllesmereUI.EYE_VISIBLE_ICON)
            EllesmereUI.SetGlyphAlpha(eyeBtn, Off() and 0.15 or 0.4)
        end
        RefreshEye()
        EllesmereUI.RegisterWidgetRefresh(RefreshEye)
        eyeBtn:SetScript("OnClick", function()
            if Off() then return end
            optState.showStatusTagPreview = not optState.showStatusTagPreview
            RefreshEye()
            ns.NPO_FriendlyPreviewUpdate()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if Off() then
                EllesmereUI.ShowWidgetTooltip(self, friendlyPlayersOff() and STYLE_REQ
                    or EllesmereUI.DisabledTooltip("Status Tags"), { width = 175 })
                return
            end
            EllesmereUI.SetGlyphAlpha(self, 0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            EllesmereUI.SetGlyphAlpha(self, Off() and 0.15 or 0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
    end
    SearchWords("Status Tags", "FRIENDLY PLAYERS", "AFK", "Do Not Disturb", "DND", "Away", "Busy")

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  FRIENDLY NPCS
    -----------------------------------------------------------------------
    SearchWords("FRIENDLY NPCS", nil, "OTHER NAMEPLATES")
    local npcHeader
    npcHeader, h = W:SectionHeader(parent, "FRIENDLY NPCS", y);  y = y - h

    local function npcOff() return DBVal("showFriendlyNPCs") ~= true end
    local NPC_PLATES_REQ = "Requires Show Friendly NPC Nameplates to be enabled"
    -- The name-only overlay's rows (every row of the section but the first
    -- half): greyed while friendly NPC plates are off or outside the Name Only style.
    local function npcOverlayOff() return npcOff() or nameOnlyOff() end
    local function npcOverlayTip()
        return npcOff() and NPC_PLATES_REQ or NAMEONLY_REQ
    end
    local function titleOff() return DBVal("showNPCTitles") == false end
    -- The subtitle and its controls belong to the Name Only overlay, so they
    -- keep the overlay's requirement. A pet's owner line reads its own switches
    -- in the pet cog, so these stay the NPC's even when only pets are shown.
    local function npcTitleOff() return npcOverlayOff() or titleOff() end
    local function npcTitleTip() return npcOverlayOff() and npcOverlayTip() or "Show NPC Titles" end
    -- The marker follows the Raid Marker element, in both friendly styles.
    local function markerOff() return (DBVal("raidMarkerPos") or defaults.raidMarkerPos) == "none" end

    -- The friendly NPC Name Format; Full Name is saved as unset.
    local nnfValues, nnfOrder, nnfGet, nnfSet = EllesmereUI.NameFormatMenu(
        function() return DBVal("friendlyNPCNameFormat") end,
        function(v)
            DB().friendlyNPCNameFormat = (v ~= "full") and v or nil
            if ns.RefreshAllNPCOverlays then ns.RefreshAllNPCOverlays() end
            ns.NPO_FriendlyPreviewUpdate()
        end)

    local npcRow
    npcRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Friendly NPC Nameplates",
          getValue=function() return DBVal("showFriendlyNPCs") == true end,
          setValue=function(v)
            DB().showFriendlyNPCs = v
            pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNPCs", v and 1 or 0, "EllesmereUINameplates")
            pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNpcs", v and 1 or 0, "EllesmereUINameplates")
            if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
            EllesmereUI:RefreshPage()
            ns.NPO_FriendlyPreviewUpdate()
          end },
        { type="dropdown", text="Friendly NPC Name Format",
          disabled=npcOverlayOff, disabledTooltip=npcOverlayTip, rawTooltip=true,
          values=nnfValues, order=nnfOrder, getValue=nnfGet, setValue=nnfSet });  y = y - h

    -- Always Show Marked NPCs: a raid-marked friendly NPC is taken over -- name and
    -- marker -- even with its nameplate toggle off or Blizzard's own NPC-names
    -- filter against it. Off by default, so a mark never brings up a plate the
    -- user switched off; the marker still draws on any plate already shown.
    -- The cog sits nearest the toggle, the color swatch left of it.
    EllesmereUI.BuildInlineCog(npcRow._leftRegion, {
        title = "Friendly NPC Nameplates",
        rows = {
            { type = "toggle", label = "Always Show Marked NPCs",
              tooltip = "Shows a friendly NPC's plate while it wears a raid marker, even with Show Friendly NPC Nameplates off or Blizzard's NPC-names filter against it.",
              disabled = nameOnlyOff, disabledTooltip = NAMEONLY_REQ, rawTooltip = true,
              get = function() return DBVal("friendlyShowMarkedNPCs") == true end,
              set = function(v)
                DB().friendlyShowMarkedNPCs = v and true or false
                -- Claimed plates answer now: a mark going on shows the NPC, and
                -- turning this off hands its plate back.
                if ns.RefreshMarkedNPCOverlays then ns.RefreshMarkedNPCOverlays() end
                ns.NPO_FriendlyPreviewUpdate()
              end },
        },
        disabled = nameOnlyOff,
        disabledTooltip = NAMEONLY_REQ,
        rawTooltip = true,
    })

    -- Inline swatch: friendly NPC bar & name color, full-plate mode only -- the exact complement of the rows below, which own the name-only colors.
    if not EllesmereUI._prebuilding then
        local rgn = npcRow._leftRegion
        local function npcColorOff() return npcOff() or friendlyPlateOff() end
        local npcSwatch, updateNpcSwatch
        local function refreshNpcSwatch()
            if updateNpcSwatch then updateNpcSwatch() end
            local off = npcColorOff()
            npcSwatch:SetAlpha(off and 0.3 or 1)
            npcSwatch:SetMouseClickEnabled(not off)
        end
        npcSwatch, updateNpcSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
            function() local c = DBVal("friendlyNPCColor") or defaults.friendlyNPCColor; return c.r, c.g, c.b end,
            function(r, g, b)
                DB().friendlyNPCColor = { r = r, g = g, b = b }
                ns.RefreshFriendlyColors()
                refreshNpcSwatch()
                ns.NPO_FriendlyPreviewUpdate()
            end, nil, 20)
        PP.Point(npcSwatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = npcSwatch
        local origNpcClick = npcSwatch:GetScript("OnClick")
        npcSwatch:SetScript("OnClick", function(self, ...)
            if npcColorOff() then return end
            if origNpcClick then origNpcClick(self, ...) end
        end)
        npcSwatch:SetScript("OnEnter", function(self)
            if npcOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Requires Show Friendly NPC Nameplates to be enabled")
            elseif DBVal("friendlyNameOnly") ~= false then
                EllesmereUI.ShowWidgetTooltip(self, PLATE_TIP)
            else
                EllesmereUI.ShowWidgetTooltip(self, "NPC Bar & Name Color")
            end
        end)
        npcSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(refreshNpcSwatch)
        refreshNpcSwatch()
    end

    local npcTitlesRow
    npcTitlesRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show NPC Titles",
          disabled=npcOverlayOff, disabledTooltip=npcOverlayTip, rawTooltip=true,
          getValue=function() return DBVal("showNPCTitles") ~= false end,
          setValue=function(v)
            DB().showNPCTitles = v and true or false
            if ns.RefreshAllNPCOverlays then ns.RefreshAllNPCOverlays() end
            EllesmereUI:RefreshPage()
            ns.NPO_FriendlyPreviewUpdate()
          end },
        { type="toggle", text="Show Raid Marker",
          disabled=function() return npcOverlayOff() or markerOff() end,
          disabledTooltip=function() return npcOverlayOff() and npcOverlayTip() or "Raid Marker" end,
          rawTooltip=npcOverlayOff,
          getValue=function() return DBVal("showNPCRaidMarker") ~= false end,
          setValue=function(v)
            DB().showNPCRaidMarker = v and true or false
            if ns.RefreshAllNPCOverlays then ns.RefreshAllNPCOverlays() end
            EllesmereUI:RefreshPage()  -- the row's eye greys with it
            ns.NPO_FriendlyPreviewUpdate()
          end });  y = y - h

    -- The eye beside Show Raid Marker: the sample NPC wears a raid marker only
    -- while it is on (off until asked, as the Display page's markers are).
    -- Greyed while the sample could not wear one: outside Name Only, with no
    -- Raid Marker slot, or with Show Raid Marker off (not with friendly NPC
    -- nameplates off: the samples only dim then). None in the search pre-build.
    if not EllesmereUI._prebuilding then
        local optState = env.optState
        local rgn = npcTitlesRow._rightRegion
        local function BarMode() return DBVal("friendlyNameOnly") == false end
        local function Off() return BarMode() or markerOff() or DBVal("showNPCRaidMarker") == false end
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        rgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshEye()
            -- The art is named the other way round: the "invisible" file is the open eye.
            eyeTex:SetTexture(optState.showNPCMarkerPreview and EllesmereUI.EYE_INVISIBLE_ICON or EllesmereUI.EYE_VISIBLE_ICON)
            EllesmereUI.SetGlyphAlpha(eyeBtn, Off() and 0.15 or 0.4)
        end
        RefreshEye()
        EllesmereUI.RegisterWidgetRefresh(RefreshEye)
        eyeBtn:SetScript("OnClick", function()
            if Off() then return end
            optState.showNPCMarkerPreview = not optState.showNPCMarkerPreview
            RefreshEye()
            ns.NPO_FriendlyPreviewUpdate()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if Off() then
                EllesmereUI.ShowWidgetTooltip(self, BarMode() and NAMEONLY_REQ
                    or EllesmereUI.DisabledTooltip(markerOff() and "Raid Marker" or "Show Raid Marker"), { width = 175 })
                return
            end
            EllesmereUI.SetGlyphAlpha(self, 0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            EllesmereUI.SetGlyphAlpha(self, Off() and 0.15 or 0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
    end

    -- (found by their swatches' names too)
    SearchWords("Friendly NPC Name Size", "FRIENDLY NPCS", "Name Color")
    SearchWords("Friendly NPC Title Size", "FRIENDLY NPCS", "Title Color")
    local npcSizeRow
    npcSizeRow, h = W:DualRow(parent, y,
        { type="slider", text="Friendly NPC Name Size", trackWidth=120,
          min=6, max=30, step=1,
          disabled=npcOverlayOff, disabledTooltip=npcOverlayTip, rawTooltip=true,
          getValue=function() return DBVal("friendlyNPCNameSize") or defaults.friendlyNPCNameSize end,
          setValue=function(v)
            DB().friendlyNPCNameSize = v
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            ns.NPO_FriendlyPreviewUpdate()
          end },
        { type="slider", text="Friendly NPC Title Size", trackWidth=120,
          min=6, max=30, step=1,
          disabled=npcTitleOff, disabledTooltip=npcTitleTip, rawTooltip=npcOverlayOff,
          getValue=function() return DBVal("friendlyNPCTitleSize") or defaults.friendlyNPCTitleSize end,
          setValue=function(v)
            DB().friendlyNPCTitleSize = v
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            ns.NPO_FriendlyPreviewUpdate()
          end });  y = y - h

    ---------------------------------------------------------------
    --  The overlay's colors, on their own row as the players' Name Color is:
    --  the name on the left with the entity highlights beside it, the subtitle
    --  on the right with the row that makes it follow the name.
    ---------------------------------------------------------------
    SearchWords("NPC Name Color", "FRIENDLY NPCS", "Name Color")
    SearchWords("NPC Title Color", "FRIENDLY NPCS", "Title Color", "Match NPC Name Color")
    local npcMatchNameRow =
        { type="toggle", label="Match NPC Name Color",
          tooltip="Colors the subtitle under an NPC's name to match the name color, including target highlights.\n\nWhen disabled, the line uses the NPC Title Color swatch.",
          -- Raw only while no plate that wears the line can show (npcTitleTip
          -- then reads as a sentence); with just the titles off, the wrapper adds
          -- the "Requires ... to be enabled" around the control's name, as the
          -- title size slider does.
          disabled=npcTitleOff, disabledTooltip=npcTitleTip, rawTooltip=npcOverlayOff,
          get=function() return DBVal("friendlyNPCTitleMatchNameColor") == true end,
          set=function(v)
            DB().friendlyNPCTitleMatchNameColor = v and true or false
            if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
            ns.NPO_FriendlyPreviewUpdate()
          end }
    local npcColorRow
    npcColorRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="NPC Name Color",
          disabled=npcOverlayOff, disabledTooltip=npcOverlayTip, rawTooltip=true,
          swatches = {
              { tooltip = "Name Color. Friendly NPCs only: neutral and opposing NPCs keep their reaction color unless their highlight row is on.", hasAlpha = false,
                getValue = function()
                    local c = DBVal("friendlyNPCNameColor") or defaults.friendlyNPCNameColor
                    return c.r, c.g, c.b
                end,
                setValue = function(r, g, b)
                    DB().friendlyNPCNameColor = { r = r, g = g, b = b }
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                    -- The health bar style paints its name and bar from this too.
                    if ns.RefreshFriendlyColors then ns.RefreshFriendlyColors() end
                    ns.NPO_FriendlyPreviewUpdate()
                end },
          } },
        { type="multiSwatch", text="NPC Title Color",
          disabled=npcTitleOff, disabledTooltip=npcTitleTip, rawTooltip=npcOverlayOff,
          swatches = {
              { tooltip = "Title Color", hasAlpha = true,
                getValue = function()
                    local c = DBVal("friendlyNPCTitleColor") or defaults.friendlyNPCTitleColor
                    return c.r, c.g, c.b, c.a or 1
                end,
                setValue = function(r, g, b, a)
                    DB().friendlyNPCTitleColor = { r = r, g = g, b = b, a = a or 1 }
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                    ns.NPO_FriendlyPreviewUpdate()
                end },
          } });  y = y - h

    -- NPC & pet highlights: the same toggle + color per entity as the players'
    -- cog above, for the entities this overlay draws, beside the name color it
    -- overrides. An entry greys out while the nameplates it colors are off; the
    -- cog itself greys while nothing in it can paint.
    SearchWords("NPC Highlights", "FRIENDLY NPCS", "Friendly & Neutral Units", "Opposing Faction Units")
    local function npcHighlightsOff() return nameOnlyOff() or (npcOff() and petPlatesOff()) end
    local function npcHighlightsTip()
        if nameOnlyOff() then return NAMEONLY_REQ end
        return "Requires Show Friendly NPC Nameplates or Show Friendly Pet Nameplates to be enabled"
    end
    EllesmereUI.BuildInlineCog(npcColorRow._leftRegion, {
        disabled = npcHighlightsOff,
        disabledTooltip = npcHighlightsTip,
        rawTooltip = true,
        tip = "NPC & Pet Highlights",
        title = "NPC & Pet Highlights",
        sections = {
            { title = "Friendly & Neutral Units", rows = RowsForSec(2) },
            { title = "Opposing Faction Units", rows = RowsForSec(3) },
        },
        footer = {
            buttonText = "Set NPC Colors to Default",
            buttonWidth = 190,
            buttonTooltip = "Resets the colors above to their defaults.\n\nYour toggle selections are preserved.",
            buttonAction = function()
                ResetAlliedColors(2, 3)
            end,
        },
    })
    -- The subtitle's own cog: the one row that makes it follow the name. It is
    -- the NPC plate's subtitle alone; a pet's owner line has its own cog with the
    -- pets' rows in the players' section.
    EllesmereUI.BuildInlineCog(npcColorRow._rightRegion, {
        title = "NPC Subtitle Settings",
        rows = { npcMatchNameRow },
        disabled = npcTitleOff,
        disabledTooltip = npcTitleTip,
        rawTooltip = npcOverlayOff,
    })

    -- Nothing of the samples' click navigation in the search pre-build.
    if EllesmereUI._prebuilding then return math.abs(y) end

    -- The samples' click navigation (overlays in FriendlyPreview_Options.lua):
    -- each part reaches the row that sets it, the half that holds the control.
    -- A player's name reaches the name size row, which holds the slider of the
    -- style in use (on the health bar plate the NPC's name takes that size too);
    -- the level, brackets and title, and the guild line in Name Only mode, are
    -- part of the name's text.
    local function NameOnly() return DBVal("friendlyNameOnly") ~= false end
    local playerName = { section = playersHeader, target = sizeRow, slotSide = "left" }
    local npcOnlyName = { section = npcHeader, target = npcSizeRow, slotSide = "left" }
    env.Nav.Page(env.PAGE_FRIENDLY, {
        -- (the bar's two rows are on the page only under the Nameplate style)
        playerBar     = barSizeRow and { section = playersHeader, target = barSizeRow, slotSide = "left" } or nil,
        healthPercent = barColorRow and { section = playersHeader, target = barColorRow, slotSide = "right" } or nil,
        playerName    = playerName,
        playerGuild   = { section = playersHeader, target = levelRow, slotSide = "right" },
        npcBar        = { section = npcHeader, target = npcRow, slotSide = "left" },
        npcName       = function() return NameOnly() and npcOnlyName or playerName end,
        npcTitle      = { section = npcHeader, target = npcSizeRow, slotSide = "right" },
        npcMarker     = { section = npcHeader, target = npcTitlesRow, slotSide = "right" },
    })

    return math.abs(y)
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildFriendlyPage = BuildFriendlyPage
