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
    local SU = EllesmereUI._SpellUprank
    local MM = EllesmereUI._MacroManager
    local ZL = EllesmereUI._ZoneLevels
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

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "MACROS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Macro Manager",
          tooltip = "Adds the Macros tab: build macros by click and create many at once. /euimacros opens it.",
          getValue = function() return MM.Get("enabled") end,
          setValue = function(v)
              MM.Cfg().enabled = v
              MM.Apply()
              -- The Macros tab rebuilds with or without its editor.
              EllesmereUI:InvalidateModulePageCache("EllesmereUIForeverEssentials")
          end },
        BLANK()
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "WORLD MAP", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Zone Levels",
          tooltip = "Shows the level range of the zone you hover on a continent of the world map, under its name, colored by difficulty.",
          getValue = function() return ZL.Get("enabled") end,
          setValue = function(v)
              ZL.Cfg().enabled = v
              ZL.Apply()
          end },
        BLANK()
    );  y = y - h

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

    return math.abs(y)
end
