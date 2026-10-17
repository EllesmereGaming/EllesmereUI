if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_General_Options.lua
--  Builds the "General" page inside the Forever Essentials module: its
--  general quality of life features, one section each.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

-------------------------------------------------------------------------------
--  NAME FORMAT: one place for every Name Format in the suite, as two checkbox
--  dropdowns over the same module rows: a box shows that part of the name, so
--  First Name alone = first names, Last Name alone = last names, both = First
--  and Last. A name always shows, so a row's last checked box stays checked.
--  Each row is a WRITE-THROUGH MIRROR, as on Global Settings > Textures: it
--  reads and writes the module's OWN keys and calls the module's own apply, so
--  nothing is stored here and each module's page shows the same setting. A row
--  over several keys (every unit frame text; raid and party) reads checked in
--  neither while they differ, and a click sets them all. A module that is off
--  has no row.
-------------------------------------------------------------------------------
-- A saved Name Format as a row value ("full" = First and Last), and back (nil).
local function ModeOf(v) return (v == nil or v == "full") and "full" or v end
local function Stored(v) return (v ~= "full") and v or nil end
-- One value while every input agrees, "mixed" once two differ (nil: none yet).
local function Merge(acc, m)
    if acc == nil or acc == m then return m end
    return "mixed"
end

-- The rows in page order: { text, tooltip, get, set [, disabled, disabledTooltip] }.
local function NameFormatSources()
    local list, MNS = {}, EllesmereUI.ModuleNS

    -- Unit Frames: every text slot (the list the Unit Frames options publish).
    -- The slots that show a name on a frame of ours that is shown (its frame
    -- source, as the Unit Frames pages test it) decide what it reads; a pick
    -- sets every slot, so a text switched to a name later follows it.
    local uf = MNS("EllesmereUIUnitFrames")
    local slots = uf and uf.db and uf.UF_NAME_FORMAT_SLOTS
    if slots then
        local hasName = uf.UF_HAS_NAME
        list[#list + 1] = { text = "Unit Frames", tooltip = "Every unit frame text that shows a name.",
            get = function()
                local p, shown, all = uf.db.profile, nil, nil
                for i = 1, #slots do
                    local e = slots[i]
                    local s = p[e.unit]
                    if s and uf.GetUnitFrameSource(e.unit) == "eui" then
                        local m = ModeOf(s[e.format])
                        all = Merge(all, m)
                        if hasName[s[e.content]] and (not e.btb or s.bottomTextBar) then
                            shown = Merge(shown, m)
                        end
                    end
                end
                return shown or all or "full"
            end,
            set = function(v)
                local p, mode = uf.db.profile, Stored(v)
                for i = 1, #slots do
                    local s = p[slots[i].unit]
                    if s then s[slots[i].format] = mode end
                end
                uf.ReloadFrames()
            end }
    end

    -- Raid Frames: the raid key, and the party's while its Text Display is
    -- unsynced (Raid Frames saves "full"; an unset party key reads the raid's).
    local rf = MNS("EllesmereUIRaidFrames")
    if rf and rf.db then
        local function partyOwn() return rf._IsPartySectionCustom("textDisplay") end
        list[#list + 1] = { text = "Raid Frames", tooltip = "Raid and party frame names.",
            get = function()
                local p = rf.db.profile
                local m = ModeOf(p.nameFormat)
                if partyOwn() and p.party_nameFormat ~= nil then m = Merge(m, ModeOf(p.party_nameFormat)) end
                return m
            end,
            set = function(v)
                local p = rf.db.profile
                p.nameFormat = v
                -- A party key left from an unsync is set too, or a later unsync
                -- would bring the old value back.
                if partyOwn() or p.party_nameFormat ~= nil then p.party_nameFormat = v end
                rf._BumpAbsorbGen()
                rf.ReloadFrames()
                rf.ReloadPartyFrames()
            end }
    end

    -- Nameplates: the enemy name and Target of Target slots (a pick sets every
    -- slot's key, so a text moved later keeps it), then the friendly players.
    local np = MNS("EllesmereUINameplates")
    if np and np.db then
        local slotKeys, formatKey = np.textSlotKeys, {}
        for _, slot in ipairs(slotKeys) do formatKey[slot] = slot .. "NameFormat" end
        list[#list + 1] = { text = "Enemy Nameplates", tooltip = "Enemy nameplate names and their targets.",
            get = function()
                local p, m = np.db.profile, nil
                local nameSlot, totSlot = np.FindNameSlot(), np._npToTSlot
                if nameSlot then m = ModeOf(p[formatKey[nameSlot]]) end
                if totSlot then m = Merge(m, ModeOf(p[formatKey[totSlot]])) end
                if not m then
                    for i = 1, #slotKeys do m = Merge(m, ModeOf(p[formatKey[slotKeys[i]]])) end
                end
                return m or "full"
            end,
            set = function(v)
                local p, mode = np.db.profile, Stored(v)
                for i = 1, #slotKeys do p[formatKey[slotKeys[i]]] = mode end
                np.RefreshAllSettings()
            end }
        list[#list + 1] = { text = "Friendly Nameplates", tooltip = "Friendly player nameplates, in both modes.",
            disabled = function() return np.db.profile.showFriendlyPlayers == false end,
            disabledTooltip = "Show EUI Friendly Player Nameplates",
            get = function() return ModeOf(np.db.profile.friendlyNameFormat) end,
            set = function(v)
                np.db.profile.friendlyNameFormat = Stored(v)
                np.NP_SyncFriendlyNameFormat()
            end }
    end

    -- Damage Meters: one key for every window.
    local dm = MNS("EllesmereUIDamageMeters")
    if dm and _G._EDM_DB then
        local DMCfg = dm.EDM.DB
        list[#list + 1] = { text = "Damage Meters",
            tooltip = "Player names on the meter bars.",
            get = function() return ModeOf(DMCfg().nameFormat) end,
            set = function(v)
                DMCfg().nameFormat = Stored(v)
                dm.RefreshNames()
            end }
    end

    -- The threat meter (this module; account-wide like its other settings).
    local TM = EllesmereUI._ThreatMeter
    list[#list + 1] = { text = "Threat Meter",
        tooltip = "Player names on the threat meter, for all your characters.",
        disabled = function() return not TM.Get("enabled") end, disabledTooltip = "Threat Meter",
        get = function() return ModeOf(TM.Get("nameFormat")) end,
        set = function(v)
            TM.Cfg().nameFormat = Stored(v)
            TM.ApplyStyle()
        end }
    return list
end

_G._EUI_BuildForeverGeneralPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local SU, CS, CT = EllesmereUI._SpellUprank, EllesmereUI._ClassicSpellbook, EllesmereUI._ClassicTalents
    local MT = EllesmereUI._MapTravel
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

    ---------------------------------------------------------------------------
    --  WORLD MAP (Reveal Unexplored Areas, its color in the cog; Map Markers,
    --  their sets in the cog: EllesmereUIForeverEssentials_MapTravel.lua)
    ---------------------------------------------------------------------------
    local MR = EllesmereUI._MapReveal
    local function revealOff() return not MR.Get("enabled") end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "WORLD MAP", y);  y = y - h

    -- Fade Map While Moving | Show the Game Behind the Map. Runtime in
    -- EllesmereUIForeverEssentials_MapFade.lua.
    local MF = EllesmereUI._MapFade
    local function SetFade(key, v)
        MF.Cfg()[key] = v
        MF.Apply()
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Fade Map While Moving",
          tooltip = "Turns on the game's own map fade: while you move, the world map fades to half so you can see where you go, and comes back once you stop or put the cursor over it.",
          getValue = function() return MF.Get("enabled") end,
          setValue = function(v) SetFade("enabled", v) end },
        { type = "toggle", text = "Show the Game Behind the Map",
          tooltip = "Lightens the black screen behind the maximized world map so you can see the game around it.",
          getValue = function() return MF.Get("dim") end,
          setValue = function(v) SetFade("dim", v) end }
    );  y = y - h

    local revealRow
    revealRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Reveal Unexplored Areas",
          tooltip = "Shows the parts of the world map you have not explored yet. Use the cog to pick their color.",
          getValue = function() return MR.Get("enabled") end,
          setValue = function(v)
              MR.Cfg().enabled = v
              MR.Apply()
              EllesmereUI:RefreshPage()  -- the cog's disabled state
          end },
        { type = "toggle", text = "Show Zone Levels",
          tooltip = "Shows the level range of the zone you hover on a continent of the world map, under its name, colored by difficulty.",
          getValue = function() return EllesmereUI._ZoneLevels.Get("enabled") end,
          setValue = function(v)
              EllesmereUI._ZoneLevels.Cfg().enabled = v
              EllesmereUI._ZoneLevels.Apply()
          end }
    );  y = y - h

    local markersRow
    markersRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Map Markers",
          tooltip = "Shows travel markers on the world map: boats and zeppelins from the world map down, dungeon entrances from continents down, flight points and zone exits on zones. Hover a marker for its name, click it to link it in chat. Use the cog to pick which ones show.",
          getValue = function() return MT.Get("enabled") end,
          setValue = function(v)
              MT.Cfg().enabled = v
              MT.Apply()
              EllesmereUI:RefreshPage()  -- the cog's disabled state
          end },
        BLANK()
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(revealRow._leftRegion, {
            title = "Reveal Unexplored Areas Settings",
            rows = {
                { type = "colorpicker", label = "Unexplored Color", hasAlpha = true,
                  tooltip = "Tints the areas you have not explored yet. White shows them as they are.",
                  get = function()
                      local c = MR.Get("color")
                      return c.r, c.g, c.b, c.a
                  end,
                  set = function(r, g, b, a)
                      MR.Cfg().color = { r = r, g = g, b = b, a = a or 1 }
                      MR.Apply()
                  end },
            },
            disabled = revealOff, disabledTooltip = "Reveal Unexplored Areas",
        })
    end

    -- Map Markers: one toggle; the cog picks the sets, all shown until turned
    -- off.
    if not EllesmereUI._prebuilding then
        local function setRow(label, tooltip, key)
            return { type = "toggle", label = label, tooltip = tooltip,
                get = function() return MT.Get(key) end,
                set = function(v)
                    MT.Cfg()[key] = v
                    MT.Apply()
                end }
        end
        local rows = {
            setRow("Transports",
                "Boats, zeppelins and the tram, from the world map down, with where each one goes when you hover it.",
                "transports"),
            setRow("Zone Exits",
                "On zone maps, an arrow on each road out of the zone, pointing to the zone it leads to.",
                "exits"),
            setRow("Instance Entrances",
                "Dungeon and raid entrances, on continent and zone maps; hover one for its name.",
                "instances"),
            setRow("Flight Points",
                "On zone maps, the flight masters, those you have not found yet included.",
                "flights"),
        }
        EllesmereUI.BuildInlineCog(markersRow._leftRegion, {
            title = "Map Markers",
            rows = rows,
            disabled = function() return not MT.Get("enabled") end,
            disabledTooltip = "Show Map Markers",
        })
    end

    ---------------------------------------------------------------------------
    --  CLASSIC WINDOWS (the vanilla spellbook and talent window)
    ---------------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "CLASSIC WINDOWS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Classic Spellbook",
          tooltip = "Your spellbook key opens the vanilla spellbook. The micro menu still opens Talents & Spellbook. "
              .. "A search or option changed in combat applies when the fight ends.",
          getValue = function() return CS.Get("enabled") end,
          setValue = function(v)
              CS.Cfg().enabled = v
              CS.Apply()
          end },
        { type = "toggle", text = "Classic Talents",
          tooltip = "Your talents key opens the vanilla talent window for your active spec. "
              .. "The micro menu still opens Talents & Spellbook.",
          getValue = function() return CT.Get("enabled") end,
          setValue = function(v)
              CT.Cfg().enabled = v
              CT.Apply()
          end }
    );  y = y - h

    ---------------------------------------------------------------------------
    --  SIMPLIFIED STATS (item tooltips)
    ---------------------------------------------------------------------------
    local SS = EllesmereUI._SimplifiedStats
    if SS then
        local function Set(k, v)
            SS.Cfg()[k] = v
            EllesmereUI:RefreshPage()  -- update the dependent rows' disabled state
        end
        local function shortenOff() return not SS.Get("shorten") end
        local function colorsOff() return not SS.Get("colors") end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "SIMPLIFIED STATS", y);  y = y - h

        -- Shorten Equip Lines | Color Stats
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Shorten Equip Lines",
              tooltip = "Shortens Equip: and Set: stat lines on item tooltips to +X Stat.",
              getValue = function() return SS.Get("shorten") end,
              setValue = function(v) Set("shorten", v) end },
            { type = "toggle", text = "Color Stats",
              tooltip = "Colors each stat name on item tooltips, enchants included, and its number per Number Color.",
              getValue = function() return SS.Get("colors") end,
              setValue = function(v) Set("colors", v) end }
        );  y = y - h

        -- Merge Equal Spell Power | Number Color
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Merge Equal Spell Power",
              tooltip = "Shows equal spell damage and healing as one Spell Power line.",
              disabled = shortenOff, disabledTooltip = "Shorten Equip Lines",
              getValue = function() return SS.Get("merge") end,
              setValue = function(v) Set("merge", v) end },
            { type = "dropdown", text = "Number Color",
              disabled = colorsOff, disabledTooltip = "Color Stats",
              values = { signed = "Green / Red", stat = "Stat Color", line = "Line Color" },
              order = { "signed", "stat", "line" },
              getValue = function() return SS.Get("numColor") end,
              setValue = function(v) SS.Cfg().numColor = (v ~= "signed") and v or nil end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  QUEST REWARDS (EllesmereUIForeverEssentials_QuestRewards.lua)
    ---------------------------------------------------------------------------
    local QR = EllesmereUI._QuestRewards
    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "QUEST REWARDS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Most Valuable Reward",
          tooltip = "Among a quest's reward choices, a money bag marks the one that sells for most, its count included.",
          getValue = function() return QR.Get("enabled") end,
          setValue = function(v)
              QR.Cfg().enabled = v
              QR.Apply()
          end },
        BLANK()
    );  y = y - h
    --  COMPANION PETS (EllesmereUIForeverEssentials_PetSummon.lua)
    ---------------------------------------------------------------------------
    local PS = EllesmereUI._PetSummon
    if PS and C_PetJournal then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "COMPANION PETS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Auto Summon Pet",
              tooltip = "Summons a random favorite pet again a moment after the game takes yours away (death, loading screen, taxi, vehicle...), or any random pet while you have no favorite. A pet you dismiss yourself stays dismissed. Never in combat, dungeons, raids, PvP, stealth or while mounted.",
              getValue = function() return PS.Get("enabled") end,
              setValue = function(v)
                  PS.Cfg().enabled = v
                  PS.Apply()
                  EllesmereUI:RefreshPage()  -- Favorites per Character's disabled state
              end },
            { type = "toggle", text = "Favorites per Character",
              tooltip = "This character summons among its own favorites instead of your account's. Right-click a pet in the Pet Journal and check Favorite for This Character; a blue star marks it in the list. While this character has none, your account's favorites are used. Saved for this character only.",
              disabled = function() return not PS.Get("enabled") end,
              disabledTooltip = "Auto Summon Pet",
              -- This character's own setting, read without creating its table.
              getValue = function()
                  local chars, guid = PS.Get("chars"), UnitGUID("player")
                  return chars ~= nil and guid ~= nil and chars[guid] ~= nil and chars[guid].own == true
              end,
              setValue = function(v)
                  local guid = UnitGUID("player")
                  if not guid then return end
                  local cfg = PS.Cfg()
                  cfg.chars = cfg.chars or {}
                  cfg.chars[guid] = cfg.chars[guid] or {}
                  cfg.chars[guid].own = v or nil
                  PS.RefreshJournal()
              end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  ACTIVE STANCE, FORM, ASPECT & AURA
    ---------------------------------------------------------------------------
    local AF = EllesmereUI._ActiveForm
    if AF then
        local function afOff() return not AF.Get("enabled") end
        local function AFSet(key, v)
            AF.Cfg()[key] = v
            AF.Apply()
        end
        local _, classFile = UnitClass("player")
        local label = classFile == "WARRIOR" and "Show Current Stance"
            or classFile == "DRUID" and "Show Current Form"
            or classFile == "PALADIN" and "Show Current Aura"
            or classFile == "HUNTER" and "Show Current Aspect"
            or "Show Current Stance / Form"

        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "ACTIVE STANCE, FORM, ASPECT & AURA", y);  y = y - h

        _, h = EllesmereUI.BuildVisibilityRow(W, parent, y, {
            leftCfg = { type = "toggle", text = label,
                tooltip = "Shows an icon for your active stance, form, aura or aspect. Hidden while none is active.",
                getValue = function() return not afOff() end,
                setValue = EllesmereUI.SectionToggleSetValue(function(v) AFSet("enabled", v) end) },
            -- The table exists once it was turned on, and the row is greyed out
            -- while it is off, so viewing the page saves nothing.
            getStore = function() return afOff() and AF.Read() or AF.Cfg() end,
            caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
            disabledFn = afOff, disabledTooltip = label,
            onChanged = EllesmereUI.RequestVisibilityUpdate,
            onOptionChanged = EllesmereUI.RequestVisibilityUpdate,
        });  y = y - h

        if not afOff() then
            -- Icon Size | Icon Zoom
            _, h = W:DualRow(parent, y,
                { type = "slider", text = "Icon Size",
                  min = 16, max = 96, step = 1, isPercent = false,
                  getValue = function() return AF.Get("iconSize") end,
                  setValue = function(v) AFSet("iconSize", v) end },
                { type = "slider", text = "Icon Zoom",
                  tooltip = "Crops the icon's edges.",
                  min = 0, max = 25, step = 1, isPercent = false,
                  getValue = function() return AF.Get("zoom") end,
                  setValue = function(v) AFSet("zoom", v) end }
            );  y = y - h

            -- Border Style | Border Size (+ color swatch)
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local borderRow
            borderRow, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Border Style",
                  values = texValues, order = texOrder,
                  getValue = function() return AF.Get("borderTexture") end,
                  setValue = function(v)
                      local c = AF.Cfg()
                      c.borderTexture = v
                      c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                      local color = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      c.borderR, c.borderG, c.borderB, c.borderA = color.r, color.g, color.b, 1
                      local defaultSize = EllesmereUI.GetBorderDefaultSize(nil, v)
                      if defaultSize then c.borderSize = defaultSize end
                      if c.borderSizePx then c.borderSizePx = false end
                      AF.Apply()
                      -- Rebuild: the offset row follows the Solid / textured pick.
                      EllesmereUI:RefreshPage(true)
                  end },
                EllesmereUI.BorderPxSliderCfg{
                  text = "Border Size",
                  getStep = function() return AF.Get("borderSize") end,
                  setStep = function(v) AF.Cfg().borderSize = v end,
                  getTex = function() return AF.Get("borderTexture") end,
                  getPx = function() return AF.Read().borderSizePx end,
                  setPx = function(v) AF.Cfg().borderSizePx = v end,
                  apply = AF.Apply }
            );  y = y - h

            if not EllesmereUI._prebuilding then
                local rgn = borderRow._rightRegion
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        return AF.Get("borderR"), AF.Get("borderG"), AF.Get("borderB"), AF.Get("borderA")
                    end,
                    function(r, g, b, a)
                        local c = AF.Cfg()
                        c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a or 1
                        AF.Apply()
                    end, true, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = swatch
                EllesmereUI.RegisterWidgetRefresh(updateSwatch)
            end

            -- Width | Height Offset: only while a textured style is selected.
            local texKey = AF.Get("borderTexture")
            if texKey ~= "" and texKey ~= "solid" then
                local offL, offR = EllesmereUI.BorderOffsetRowCfgs{
                    getTex = function() return AF.Get("borderTexture") end,
                    getStep = function() return AF.Get("borderSize") end,
                    getSizeKey = function() return AF.Get("borderSize") end,
                    getPx = function() return AF.Read().borderSizePx end,
                    getX = function() return AF.Read().borderTextureOffset end,
                    setX = function(v) AF.Cfg().borderTextureOffset = v end,
                    getY = function() return AF.Read().borderTextureOffsetY end,
                    setY = function(v) AF.Cfg().borderTextureOffsetY = v end,
                    apply = AF.Apply,
                }
                _, h = W:DualRow(parent, y, offL, offR);  y = y - h
            end
        end
    end

    ---------------------------------------------------------------------------
    --  NAME FORMAT (while a module with a Name Format is on)
    ---------------------------------------------------------------------------
    local sources = NameFormatSources()
    if #sources > 0 then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "NAME FORMAT", y);  y = y - h
        -- Placeholder dropdowns keep the labels, tooltips and search entries; the
        -- checkbox dropdowns replace them (DualRow only builds plain widgets).
        local function Slot(text, tooltip)
            return { type = "dropdown", text = text, tooltip = tooltip,
                values = { __placeholder = "..." }, order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end }
        end
        local row
        row, h = W:DualRow(parent, y,
            Slot("First Name", "Checked modules show their first name. A module checked in both lists shows the full name."),
            Slot("Last Name", "Checked modules show their last name. A module checked in both lists shows the full name."));  y = y - h
        if not EllesmereUI._prebuilding then
            local PP = EllesmereUI.PanelPP
            -- A module that is switched off stays greyed out and out of "All".
            local items = {}
            for i = 1, #sources do
                local src = sources[i]
                items[i] = { key = i, label = src.text, tooltip = src.tooltip,
                    lockedFn = src.disabled, excludeFromSummaryFn = src.disabled,
                    lockedTooltip = src.disabled and function()
                        return EllesmereUI.DisabledTooltip(src.disabledTooltip)
                    end or nil }
            end
            -- Whether a row value shows that part of the name ("mixed" shows neither box).
            local function Has(m, part) return m == part or m == "full" end
            local function List(rgn, part)
                local other = (part == "first") and "last" or "first"
                if rgn._control then rgn._control:Hide() end
                local dd, refresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2, items,
                    function(i) return Has(sources[i].get(), part) end,
                    function(i, on)
                        local theirs = Has(sources[i].get(), other)
                        -- A name always shows: unchecking the last box keeps it.
                        if not (on or theirs) then return end
                        sources[i].set((on and theirs) and "full" or (on and part or other))
                        -- The other list reads the new value too.
                        EllesmereUI:RefreshPage()
                    end)
                PP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = dd
                rgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(refresh)
            end
            List(row._leftRegion, "first")
            List(row._rightRegion, "last")
        end
    end

    ---------------------------------------------------------------------------
    --  GATHERING (EllesmereUIForeverEssentials_GatherSkill.lua)
    ---------------------------------------------------------------------------
    local GS = EllesmereUI._GatherSkill
    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "GATHERING", y);  y = y - h

    local gsRow
    gsRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Gathering Skill in Tooltips",
          tooltip = "On herb and ore node tooltips, adds the skill the node needs to the game's \"Requires Herbalism\" or \"Requires Mining\" line and, when you can gather it, colors that line by your chance to raise your skill there: orange, yellow, green, grey.",
          getValue = function() return GS.Get("enabled") end,
          setValue = function(v)
              GS.Cfg().enabled = v
              GS.Apply()
              EllesmereUI:RefreshPage()  -- the cog's disabled state
          end },
        BLANK()
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(gsRow._leftRegion, {
            title = "Gathering Skill in Tooltips",
            rows = {
                { type = "toggle", label = "Minimap",
                  tooltip = "Also on the minimap: a tracked herb or ore node's name is followed by its required skill, in the same colors (red when you cannot gather it).",
                  get = function() return GS.Get("minimap") end,
                  set = function(v)
                      GS.Cfg().minimap = v
                      GS.Apply()
                  end },
            },
            disabled = function() return not GS.Get("enabled") end,
            disabledTooltip = "Gathering Skill in Tooltips",
        })
    end

    ---------------------------------------------------------------------------
    --  JUNK ITEMS (the rows after the toggle are built while the window is
    --  on; the toggle rebuilds the page)
    ---------------------------------------------------------------------------
    local JI = EllesmereUI._JunkItems
    local function junkOff() return not JI.Get("enabled") end
    -- Every write re-applies the window.
    local function JunkSet(key, v)
        JI.Cfg()[key] = v
        JI.Apply()
    end
    local function ClearJunkExclusions()
        EllesmereUI:ShowConfirmPopup({
            title       = EllesmereUI.L("Clear Excluded Items"),
            message     = EllesmereUI.L("Every item you middle-clicked away can show in the Junk Items window again."),
            confirmText = EllesmereUI.L("Clear"),
            cancelText  = CANCEL,
            onConfirm   = JI.ClearExclusions,
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "JUNK ITEMS", y);  y = y - h

    _, h = EllesmereUI.BuildVisibilityRow(W, parent, y, {
        leftCfg = { type = "toggle", text = "Enable Junk Items Window",
            tooltip = "Shows your cheapest junk in a small window.",
            getValue = function() return not junkOff() end,
            setValue = EllesmereUI.SectionToggleSetValue(function(v) JunkSet("enabled", v) end) },
        -- The window's table exists once it was turned on, and the row is
        -- greyed out while it is off, so viewing the page saves nothing.
        getStore = function() return junkOff() and JI.Read() or JI.Cfg() end,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
        disabledFn = junkOff, disabledTooltip = "Junk Items Window",
        onChanged = EllesmereUI.RequestVisibilityUpdate,
        onOptionChanged = EllesmereUI.RequestVisibilityUpdate,
    });  y = y - h

    if not junkOff() then
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Only Show When Bag Space Is Low",
              tooltip = "Shows the window only when free slots in regular bags are below the threshold. Existing visibility conditions still apply.",
              getValue = function() return JI.Get("onlyLowBagSpace") == true end,
              setValue = function(v) JunkSet("onlyLowBagSpace", v) end },
            { type = "slider", text = "Free-Slot Threshold",
              min = 1, max = 100, step = 1, isPercent = false,
              tooltip = "Show when fewer than this many regular bag slots are free. A threshold of 5 shows at 0-4 free slots.",
              getValue = function() return JI.Get("freeSlotThreshold") end,
              setValue = function(v) JunkSet("freeSlotThreshold", v) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Items Shown",
              min = 1, max = 6, step = 1, isPercent = false,
              tooltip = "How many junk stacks the window lists.",
              getValue = function() return JI.Get("itemCount") end,
              setValue = function(v) JunkSet("itemCount", v) end },
            { type = "toggle", text = "Include White Items",
              tooltip = "Lists white stacks as well as gray ones.",
              getValue = function() return JI.Get("includeWhite") == true end,
              setValue = function(v) JunkSet("includeWhite", v) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Skip Confirmation for White Items",
              tooltip = "White stacks delete on the first Ctrl + Left Click instead of the second.",
              getValue = function() return JI.Get("skipWhiteConfirm") == true end,
              setValue = function(v) JunkSet("skipWhiteConfirm", v) end },
            { type = "labeledButton", text = "Excluded Items", buttonText = "Clear", width = 90,
              tooltip = "Brings back items you middle-clicked away.",
              onClick = ClearJunkExclusions }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Icon Size",
              min = 16, max = 64, step = 1, isPercent = false,
              getValue = function() return JI.Get("iconSize") end,
              setValue = function(v) JunkSet("iconSize", v) end },
            { type = "slider", text = "Icon Spacing",
              tooltip = "Prices that don't fit show only their largest coin.",
              min = 0, max = 30, step = 1, isPercent = false,
              getValue = function() return JI.Get("iconSpacing") end,
              setValue = function(v) JunkSet("iconSpacing", v) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Price Position",
              values = { bottom = "Below Icon", top = "Above Icon" },
              order = { "bottom", "top" },
              getValue = function() return JI.Get("priceSide") end,
              setValue = function(v) JunkSet("priceSide", v) end },
            { type = "toggle", text = "Show Empty Bag Slots",
              tooltip = "Shows free and total bag slots as the title.",
              getValue = function() return JI.Get("showFreeSlots") == true end,
              setValue = function(v) JunkSet("showFreeSlots", v) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  FISHING (EllesmereUIForeverEssentials_Fishing.lua)
    ---------------------------------------------------------------------------
    local FI = EllesmereUI._Fishing
    local function SetFish(key, v)
        FI.Cfg()[key] = v
        FI.Apply()
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "FISHING", y);  y = y - h

    -- Fishing Key (keybind, its options in the cog) | Double-Click to Cast
    local fishKeyRow
    fishKeyRow, h = W:DualRow(parent, y,
        { type = "label", text = "Fishing Key",
          tooltip = "One key for the whole loop: casts your line, then reels it in once the bobber bites. With no fishing pole in hand, it first equips the best one in your bags. Use the cog to reel in, show the bobber indicator and apply lures." },
        { type = "toggle", text = "Double-Click to Cast",
          tooltip = "With a fishing pole in hand, a quick double right-click on the world casts your line (applying a lure first if its cog's option is on). Never on a character, in combat or while your line is in the water: right-click the bobber to reel in.",
          getValue = function() return FI.Get("doubleClick") end,
          setValue = function(v)
              SetFish("doubleClick", v)
              EllesmereUI:RefreshPage()  -- the cog's disabled state
          end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = fishKeyRow._leftRegion
        local kbBtn, refresh = EllesmereUI.BuildKeybindButton(rgn, {
            w = 140, h = 30, font = 13,
            get = function() return FI.Get("key") end,
            set = function(v)
                SetFish("key", v)
                EllesmereUI:RefreshPage()  -- the cog's disabled state
            end,
            tooltip = "Left-click to set a keybind.\nRight-click to unbind.",
        })
        EllesmereUI.PanelPP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
        EllesmereUI.RegisterWidgetRefresh(refresh)

        local function fishRow(label, tooltip, key)
            return { type = "toggle", label = label, tooltip = tooltip,
                get = function() return FI.Get(key) end,
                set = function(v) SetFish(key, v) end }
        end
        -- A label half has no control: the cog sits left of the keybind
        -- button, which also bounds the label.
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Fishing Key",
            rows = {
                fishRow("Reel In With the Key", "While your line is in the water and the bobber is on screen, the Fishing Key reels it in; the line out, the key casts again. Turns on soft interact while you fish, and puts your settings back after.", "reel"),
                fishRow("Bobber Indicator", "While your line is in the water, an icon shows whether the bobber is targeted: green, the key reels in; red, keep the bobber on screen. Hover it for details; place it in Unlock Mode.", "indicator"),
                fishRow("Apply Lure", "When your fishing pole has no lure, the Fishing Key first applies the best lure in your bags; the next press casts.", "lure"),
            },
            anchorTo = kbBtn,
            disabled = function() return FI.Get("key") == nil end,
            disabledTooltip = "Fishing Key",
        })
        EllesmereUI.BuildInlineCog(fishKeyRow._rightRegion, {
            title = "Double-Click to Cast",
            rows = { fishRow("Apply Lure", "When your fishing pole has no lure, a double-click first applies the best lure in your bags; the next one casts.", "clickLure") },
            disabled = function() return not FI.Get("doubleClick") end,
            disabledTooltip = "Double-Click to Cast",
        })
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Fishing Sounds",
          tooltip = "While you fish, lowers music and ambience, raises sound effects so you hear the bobber splash, and keeps sound on when the game is in the background. Your sound settings come back when you move, enter combat or change zone.",
          getValue = function() return FI.Get("sound") end,
          setValue = function(v) SetFish("sound", v) end },
        BLANK()
    );  y = y - h

    return math.abs(y)
end
