if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\GeneralPage_Options.lua
--  Nameplates options: the General page (BuildGeneralPage). Definitions only;
--  the shared helpers come from ns._NPO_OptEnv (filled by
--  EUI_Nameplates_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

---------------------------------------------------------------------------
--  General page (Friendly settings, Spacing, Show All Debuffs); two-column DualRow layout where possible
---------------------------------------------------------------------------
local function BuildGeneralPage(pageName, parent, yOffset)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults, FOCUS_LETTER_ANCHOR_ORDER = env.DB, env.DBVal, env.defaults, env.FOCUS_LETTER_ANCHOR_ORDER
    local FOCUS_LETTER_ANCHORS, GetFocusLetterAnchor, GetNPOptOutline, npDispelGlowDesc = env.FOCUS_LETTER_ANCHORS, env.GetFocusLetterAnchor, env.GetNPOptOutline, env.npDispelGlowDesc
    local pairs, pcall, plates, PP = env.pairs, env.pcall, env.plates, env.PP
    local RefreshAllAuras, RefreshAllPlates, SECTION_AURA, SECTION_ENEMY_NP = env.RefreshAllAuras, env.RefreshAllPlates, env.SECTION_AURA, env.SECTION_ENEMY_NP
    local SECTION_FRIENDLY, SECTION_MISC, UpdatePreview = env.SECTION_FRIENDLY, env.SECTION_MISC, env.UpdatePreview
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    -- No preview on General tab
    EllesmereUI:ClearContentHeader()

    -- Enable per-row center divider for the dual-column layout
    parent._showRowDivider = true

    -----------------------------------------------------------------------
    --  FRIENDLY NAMEPLATES
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_FRIENDLY, y);  y = y - h

    local function friendlyPlayersOff() return DBVal("showFriendlyPlayers") == false end
    local function friendlyPlateOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") ~= false end
    local function nameOnlyOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") == false end
    -- Title renders INLINE with the name (one string, takes the name's own font/size/color); only the guild line below is styled by the size/color/bracket controls, so those gate on a mode that includes guild.
    local function subtitleGuildOff()
        local m = DBVal("friendlyBelowName") or "none"
        return friendlyPlayersOff() or (m ~= "guild" and m ~= "both")
    end

    local friendlyRow
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Show EUI Friendly Player Nameplates",
          tooltip="When disabled, EUI relinquishes full control of friendly player nameplates to Blizzard. Use Blizzard's own Nameplate settings (Esc > Options > Nameplates) to control them.",
          getValue=function() return DBVal("showFriendlyPlayers") ~= false end,
          setValue=function(v)
            DB().showFriendlyPlayers = v
            do
                if v then
                    -- Enabling: re-assert every friendly-player CVar that SetupAuraCVars sets on load (it skips these while the toggle is off) -- runtime is the only restore path short of /reload.
                    local p = DB()
                    local nameOnly = (p and p.friendlyNameOnly ~= false)
                    local classColor = (p and p.classColorFriendly ~= false)
                    -- One of only two places EUI is allowed to force friendly plates visible; also clears any follower-dungeon capture.
                    if ns.ForceFriendlyPlayerCVarsOn then
                        ns.ForceFriendlyPlayerCVarsOn()
                    end
                    pcall(EllesmereUI.SetCVar, "UnitNameFriendlyPlayerName", 1, "EllesmereUINameplates")
                    pcall(EllesmereUI.SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0, "EllesmereUINameplates")
                    pcall(EllesmereUI.SetCVar, "ShowClassColorInFriendlyNameplate", classColor and 1 or 0, "EllesmereUINameplates")
                    pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(p), "EllesmereUINameplates")
                else
                    -- Disabling: reset the three CVars EUI uniquely manages (name-only override + class color) to Blizzard defaults for a clean slate; visibility CVars stay untouched so Blizzard's panel keeps the user's values.
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
                end
            end
            if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
            -- Re-assert stacking after friendly CVar changes (Blizzard can reset the stacking bitfield as a side effect).
            ns.RefreshStackingMotion()
            EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Make Friendly Nameplates Name Only",
          tooltip="Hide friendly player health bars and instead only see their names.\n\nRequires 'Simplified Friendly Nameplates' to be disabled in Blizzard's Nameplate settings (Esc > Options > Nameplates).",
          getValue=function() return DBVal("friendlyNameOnly") ~= false end,
          setValue=function(v)
            DB().friendlyNameOnly = v
            pcall(EllesmereUI.SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", v and 1 or 0, "EllesmereUINameplates")
            -- Turning name-only ON means the user wants to SEE friendly plates -- the second sanctioned force-visible point.
            if v and ns.ForceFriendlyPlayerCVarsOn then
                ns.ForceFriendlyPlayerCVarsOn()
            end
            if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
            EllesmereUI:RefreshPage()
          end,
          disabled = friendlyPlayersOff,
          disabledTooltip = "Show EUI Friendly Player Nameplates" });  friendlyRow = _; y = y - h

    ---------------------------------------------------------------
    --  Friendly Player cog popup (size, health text, class colours, target border)
    ---------------------------------------------------------------
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(friendlyRow._leftRegion, {
            chain = false,
            disabled = friendlyPlateOff,
            disabledTooltip = "Requires Name Only setting to be disabled", rawTooltip = true,
            title = "Friendly Nameplate Settings",
            rows = {
                { type = "slider", label = "Distance", min = -50, max = 50, step = 1,
                  get = function() return DBVal("friendlyPlateYOffset") or 0 end,
                  set = function(v) DB().friendlyPlateYOffset = v; if ns.RefreshFriendlyPlateYOffset then ns.RefreshFriendlyPlateYOffset() end end },
                { type = "slider", label = "Height", min = 6, max = 40, step = 1,
                  get = function() return DBVal("friendlyHealthBarHeight") or defaults.friendlyHealthBarHeight end,
                  set = function(v) DB().friendlyHealthBarHeight = v; if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end end },
                { type = "slider", label = "Width", min = 80, max = 250, step = 1,
                  get = function() return DBVal("friendlyHealthBarWidth") or defaults.friendlyHealthBarWidth end,
                  set = function(v) DB().friendlyHealthBarWidth = v; if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end end },
                { type = "slider", label = "Name Size", min = 6, max = 30, step = 1,
                  get = function() return DBVal("friendlyNameTextSize") or defaults.friendlyNameTextSize end,
                  set = function(v) DB().friendlyNameTextSize = v; if ns.RefreshFriendlyNameTextSize then ns.RefreshFriendlyNameTextSize() end end },
                { type = "toggle", label = "Show Health Percent",
                  get = function() local db = DB(); return not (db and db.friendlyHideHealthText) end,
                  set = function(v)
                    DB().friendlyHideHealthText = not v
                    if ns.RefreshFriendlyHealthText then ns.RefreshFriendlyHealthText() end
                  end },
                { type = "toggle", label = "Class Colored Health Bar",
                  get = function() return DBVal("classColorFriendly") ~= false end,
                  set = function(v)
                    DB().classColorFriendly = v and true or false
                    -- Blizzard's instance plates colour their names by this CVar.
                    if not InCombatLockdown() then
                        pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(DB()), "EllesmereUINameplates")
                    end
                    ns.RefreshAllSettings()
                  end },
                { type = "toggle", label = "Class Colored Names",
                  get = function() return DBVal("friendlyNameClassColor") == true end,
                  set = function(v)
                    DB().friendlyNameClassColor = v and true or false
                    if not InCombatLockdown() then
                        pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(DB()), "EllesmereUINameplates")
                    end
                    ns.RefreshFriendlyColors()
                  end },
                { type = "toggle", label = "Target Border Effects",
                  tooltip = "Also applies the target Border Color and Border Size effects to friendly nameplates.",
                  -- Borders stand down under the stock styles.
                  disabled = function()
                    return EllesmereUI.BlizzStyle.Get("nameplates")
                        or not (ns.GetTargetGlowBorderColor() or ns.GetTargetGlowBorderSize())
                  end,
                  disabledTooltip = function()
                    if EllesmereUI.BlizzStyle.Get("nameplates") then
                        return EllesmereUI.BlizzStyle.Label("nameplates")
                    end
                    return "This option requires the Border Color or Border Size target effect."
                  end,
                  rawTooltip = function() return not EllesmereUI.BlizzStyle.Get("nameplates") end,
                  requireState = "disabled",
                  get = function() return DBVal("friendlyTargetBorderFx") == true end,
                  set = function(v)
                    DB().friendlyTargetBorderFx = v
                    -- Applies to (or restores) the friendly target now.
                    for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                    UpdatePreview()
                  end },
            },
        })
    end

    ---------------------------------------------------------------
    --  Name Only inline swatches (White + Class Color) mirror the Target Arrows double-swatch pattern: classColorFriendly picks the active swatch (inactive dims); neither opens a picker (White fixed, Class = player's class color). Both gray out when Name Only is off.
    ---------------------------------------------------------------
    if not EllesmereUI._prebuilding then
        local rightRgn = friendlyRow._rightRegion
        local whiteSwatch, updateWhite, classSwatch, updateClass
        local function refreshNameSwatches()
            if updateWhite then updateWhite() end
            if updateClass then updateClass() end
            local off = nameOnlyOff()
            local useClass = DBVal("classColorFriendly") ~= false
            whiteSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
            classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
            whiteSwatch:SetMouseClickEnabled(not off)
            classSwatch:SetMouseClickEnabled(not off)
        end
        local function ApplyClassColored(useClass)
            DB().classColorFriendly = useClass and true or false
            pcall(EllesmereUI.SetCVar, "ShowClassColorInFriendlyNameplate", useClass and 1 or 0, "EllesmereUINameplates")
            pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(DB()), "EllesmereUINameplates")
            if ns.RefreshAllSettings then ns.RefreshAllSettings() end
            refreshNameSwatches()
        end
        -- White swatch: fixed white, not editable; clicking only selects the non-class-colored mode (default OnClick picker replaced below).
        whiteSwatch, updateWhite = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() return 1, 1, 1 end,
            function() end, nil, 20)
        PP.Point(whiteSwatch, "RIGHT", rightRgn._control, "LEFT", -8, 0)
        whiteSwatch:SetScript("OnClick", function()
            if nameOnlyOff() then return end
            ApplyClassColored(false)
        end)
        whiteSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(whiteSwatch, "White") end)
        whiteSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        -- Class color swatch: player's class color; selects class-colored mode.
        classSwatch, updateClass = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function()
                local _, ct = UnitClass("player")
                local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(classSwatch, "RIGHT", whiteSwatch, "LEFT", -8, 0)
        rightRgn._lastInline = classSwatch
        classSwatch:SetScript("OnClick", function()
            if nameOnlyOff() then return end
            ApplyClassColored(true)
        end)
        classSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color") end)
        classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(refreshNameSwatches)
        refreshNameSwatches()
    end

    ---------------------------------------------------------------
    --  Subtitle Text: title renders inline with the name, guild sits on its own line below. The colour pair styles ONLY the guild line -- the inline title is part of the name string, using its colour.
    ---------------------------------------------------------------
    -- Custom/Class pair follows the multiSwatch convention: clicking the INACTIVE custom swatch only selects custom mode (click again to open the picker); the inactive swatch dims, both grey out together.
    local function MakeGuildColorSwatches()
        return {
            { tooltip = "Custom Color", hasAlpha = false,
              getValue = function()
                  local c = DBVal("friendlyBelowNameColor") or defaults.friendlyBelowNameColor
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  DB().friendlyBelowNameColor = { r = r, g = g, b = b }
                  if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
              end,
              onClick = function(self)
                  if DBVal("friendlyBelowNameClassColor") == true then
                      DB().friendlyBelowNameClassColor = false
                      if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  if subtitleGuildOff() then return 0.15 end
                  return (DBVal("friendlyBelowNameClassColor") == true) and 0.3 or 1
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
                  DB().friendlyBelowNameClassColor = true
                  if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  if subtitleGuildOff() then return 0.15 end
                  return (DBVal("friendlyBelowNameClassColor") == true) and 1 or 0.3
              end },
        }
    end

    local subtitleRow
    subtitleRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Subtitle Text",
          tooltip="Show the player's title inline with their name, and/or their guild on a line below it, on friendly nameplates.",
          disabled=friendlyPlayersOff,
          disabledTooltip="Show EUI Friendly Player Nameplates",
          values={ none="None", title="Player Title", guild="Guild Name", both="Title & Guild" },
          order={ "none", "title", "guild", "both" },
          getValue=function() return DBVal("friendlyBelowName") or "none" end,
          setValue=function(v)
            DB().friendlyBelowName = v
            if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
            EllesmereUI:RefreshPage()
          end },
        { type="multiSwatch", text="Guild Text Color",
          disabled=subtitleGuildOff,
          disabledTooltip=function()
              if friendlyPlayersOff() then return "Show EUI Friendly Player Nameplates" end
              return "This option requires Subtitle Text to include the Guild Name"
          end,
          rawTooltip=function() return not friendlyPlayersOff() end,
          swatches = MakeGuildColorSwatches() });  y = y - h

    -- Subtitle Text inline cog (guild bracket toggle)
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(subtitleRow._leftRegion, {
            chain = false,
            disabled = subtitleGuildOff,
            -- Same requirement as the Guild Text Color swatch beside it; the
            -- guild sentence is already whole, so it goes raw.
            disabledTooltip = function()
                if friendlyPlayersOff() then return "Show EUI Friendly Player Nameplates" end
                return EllesmereUI.L("This option requires Subtitle Text to include the Guild Name")
            end,
            rawTooltip = function() return not friendlyPlayersOff() end,
            title = "Subtitle Text Settings",
            rows = {
                { type = "toggle", label = "Show <> Around Guild",
                  get = function() return DBVal("friendlyBelowNameGuildBrackets") ~= false end,
                  set = function(v)
                    DB().friendlyBelowNameGuildBrackets = v and true or false
                    if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
                  end },
            },
        })
    end

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
          end },
        { type="slider", text="Friendly Name Size", trackWidth=120,
          min=8, max=30, step=1,
          disabled=nameOnlyOff,
          disabledTooltip="Make Friendly Nameplates Name Only",
          getValue=function() return DBVal("friendlyNameSize") or defaults.friendlyNameSize end,
          setValue=function(v)
            DB().friendlyNameSize = v
            if ns.RefreshFriendlyNameSize then ns.RefreshFriendlyNameSize() end
          end,
          tooltip="Adjusts the size of friendly player names shown in Name Only mode. Default is 15." });  y = y - h

    -- Cog popup for NPC nameplate settings (Show NPC Titles)
    do
        local function npcOff() return DBVal("showFriendlyNPCs") ~= true end
        -- Every row here styles the name-only overlay, so the mode gate lives
        -- on the cog button; only the title rows need a gate of their own.
        local function npcCogOff() return npcOff() or nameOnlyOff() end
        local function titleOff() return DBVal("showNPCTitles") == false end

        local rgn = npcRow._leftRegion
        local btn = EllesmereUI.BuildInlineCog(rgn, {
            chain = false,
            disabled = npcCogOff,
            disabledTooltip = function()
                return npcOff() and "Requires Show Friendly NPC Nameplates to be enabled" or "Requires Name Only mode"
            end,
            rawTooltip = true,
            title = "Friendly NPC Settings",
            rows = {
                { type = "toggle", label = "Show NPC Titles",
                  get = function() return DBVal("showNPCTitles") ~= false end,
                  set = function(v)
                    DB().showNPCTitles = v and true or false
                    if ns.RefreshAllNPCOverlays then ns.RefreshAllNPCOverlays() end
                  end },
                { type = "slider", label = "Name Size", min = 6, max = 30, step = 1,
                  get = function() return DBVal("friendlyNPCNameSize") or defaults.friendlyNPCNameSize end,
                  set = function(v)
                    DB().friendlyNPCNameSize = v
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                  end },
                { type = "slider", label = "Title Size", min = 6, max = 30, step = 1,
                  get = function() return DBVal("friendlyNPCTitleSize") or defaults.friendlyNPCTitleSize end,
                  set = function(v)
                    DB().friendlyNPCTitleSize = v
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                  end,
                  disabled = titleOff, disabledTooltip = "Show NPC Titles" },
                { type = "colorpicker", label = "Name Color",
                  get = function()
                    local c = DBVal("friendlyNPCNameColor") or defaults.friendlyNPCNameColor
                    return c.r, c.g, c.b
                  end,
                  set = function(r, g, b)
                    DB().friendlyNPCNameColor = { r = r, g = g, b = b }
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                  end },
                { type = "colorpicker", label = "Title Color", hasAlpha = true,
                  get = function()
                    local c = DBVal("friendlyNPCTitleColor") or defaults.friendlyNPCTitleColor
                    return c.r, c.g, c.b, c.a or 1
                  end,
                  set = function(r, g, b, a)
                    DB().friendlyNPCTitleColor = { r = r, g = g, b = b, a = a or 1 }
                    if ns.RefreshNPCOverlayStyle then ns.RefreshNPCOverlayStyle() end
                  end,
                  disabled = titleOff, disabledTooltip = "Show NPC Titles" },
            },
        })

        -- Inline swatch: friendly NPC bar & name color, full-plate mode only -- the exact complement of the cog beside it, which owns the name-only colors.
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
            end, nil, 20)
        PP.Point(npcSwatch, "RIGHT", btn or rgn._control, "LEFT", -8, 0)
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
                EllesmereUI.ShowWidgetTooltip(self, "Requires Name Only mode to be disabled")
            else
                EllesmereUI.ShowWidgetTooltip(self, "NPC Bar & Name Color")
            end
        end)
        npcSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(refreshNpcSwatch)
        refreshNpcSwatch()
    end

    _, h = W:DualRow(parent, y,
        { type="toggle", text="Friendly Names Not Clickable",
          tooltip="Make friendly player and NPC nameplates click-through so their names never block your mouse or cause accidental friendly targeting.\n\nUse this when friendly names get in the way of clicking the world or the enemy nameplates behind them.",
          getValue=function() return DBVal("friendlyClickThrough") == true end,
          setValue=function(v)
            DB().friendlyClickThrough = v
            if ns.UpdateFriendlyClickThrough then ns.UpdateFriendlyClickThrough() end
          end },
        { type="toggle", text="Show Enemy Pet Nameplates",
          getValue=function() return DBVal("showEnemyPets") == true end,
          setValue=function(v)
            DB().showEnemyPets = v
            pcall(EllesmereUI.SetCVar, "nameplateShowEnemyPets", v and 1 or 0, "EllesmereUINameplates")
          end,
          tooltip="Toggle visibility of enemy pet nameplates." });  y = y - h

    -- Inline DIRECTIONS cog on Friendly Name Size: name-only vertical distance
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(npcRow._rightRegion, {
            icon = EllesmereUI.DIRECTIONS_ICON,
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

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  ENEMY NAMEPLATE SPACING
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_ENEMY_NP, y);  y = y - h

    local stackingRow
    stackingRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Stacking Nameplates",
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function() return "__placeholder" end,
          setValue=function() end },
        { type="slider", text="Stacked Nameplate Spacing",
          trackWidth=130,
          min=50, max=200, step=5,
          getValue=function() return DBVal("stackSpacingScale") or defaults.stackSpacingScale end,
          setValue=function(v)
            DB().stackSpacingScale = v
            ns.RefreshStackingBounds()
          end,
          tooltip="Adjusts the vertical spacing between stacked nameplates. 100% = default, lower = tighter, higher = more spread." });  y = y - h

    -- Replace the placeholder dropdown with a multi-select checkbox dropdown; Enemy and Friendly stacking are independent toggles over the Midnight stacking bitfield. Friendly locks out while EUI isn't managing friendly plates (Blizzard owns that bit then).
    if not EllesmereUI._prebuilding then
        local leftRgn = stackingRow._leftRegion
        if leftRgn._control then leftRgn._control:Hide() end
        local stackItems = {
            { key = "enemy",    label = "Enemy Nameplates" },
            { key = "friendly", label = "Friendly Nameplates",
              lockedFn = function() return DBVal("showFriendlyPlayers") == false end },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            leftRgn, 170, leftRgn:GetFrameLevel() + 2,
            stackItems,
            function(k)
                if k == "enemy" then return DBVal("stackingEnabled") ~= false end
                if k == "friendly" then return DBVal("stackingFriendly") == true end
                return false
            end,
            function(k, v)
                if k == "enemy" then DB().stackingEnabled = v
                elseif k == "friendly" then DB().stackingFriendly = v end
                ns.RefreshStackingMotion()
            end)
        PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        cbDD:HookScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cbDD, "Choose which nameplates stack vertically instead of overlapping.")
        end)
        cbDD:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    local hitboxRow
    hitboxRow, h = W:DualRow(parent, y,
        { type="slider", text="Hitbox Size X",
          min=50, max=250, step=5,
          getValue=function() return DBVal("hitboxScaleX") or defaults.hitboxScaleX end,
          setValue=function(v)
            DB().hitboxScaleX = v
            ns.RefreshHitboxSize()
          end,
          tooltip="Widens the clickable hitbox of enemy nameplates. 100% = matches bar width. Increase to make nameplates easier to click." },
        { type="slider", text="Hitbox Size Y",
          min=50, max=250, step=5,
          getValue=function() return DBVal("hitboxScaleY") or defaults.hitboxScaleY end,
          setValue=function(v)
            DB().hitboxScaleY = v
            ns.RefreshHitboxSize()
          end,
          tooltip="Increases the clickable hitbox height of enemy nameplates. 100% = matches bar height. Increase to make nameplates easier to click." });  y = y - h

    -- Eyeball toggle on Hitbox Size X: translucent overlay on real enemy nameplates marking the clickable area, for visual slider tuning; runtime-only, auto-hides when the panel closes.
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local leftRgn = hitboxRow._leftRegion
        local eyeBtn = CreateFrame("Button", nil, leftRgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        leftRgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshEyeIcon()
            eyeTex:SetTexture(ns._hitboxOverlayShown and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshEyeIcon()
        eyeBtn:SetScript("OnClick", function()
            if ns.SetHitboxOverlayShown then ns.SetHitboxOverlayShown(not ns._hitboxOverlayShown) end
            RefreshEyeIcon()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide Hitbox Overlay", { width = 175 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        -- Auto-hide the overlay when the options panel closes (hook once).
        if not ns._hitboxOverlayCloseHook and EllesmereUI._mainFrame then
            ns._hitboxOverlayCloseHook = true
            EllesmereUI._mainFrame:HookScript("OnHide", function()
                if ns._hitboxOverlayShown and ns.SetHitboxOverlayShown then
                    ns.SetHitboxOverlayShown(false)
                end
            end)
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  EXTRA AURA OPTIONS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_AURA, y);  y = y - h

    local maxDbfOriginal = DBVal("maxDebuffs") or defaults.maxDebuffs
    local maxDbfPendingPopup
    local maxDbfCfg =
        { type="slider", text="Max Debuffs", min=1, max=10, step=1,
          getValue=function() return DBVal("maxDebuffs") or defaults.maxDebuffs end,
          setValue=function(v)
            DB().maxDebuffs = v
            -- 12.1 containers raise/lower the group's frame cap live via SetAuraGroupMaxFrameCount inside the reload's cfg pass.
            if ns.NPC_ReloadAll then
                ns.NPC_ReloadAll()
                return
            end
            -- Legacy pools are sized at plate creation: show the reload popup once after the slider drag ends (debounced).
            if v ~= maxDbfOriginal then
                if maxDbfPendingPopup then maxDbfPendingPopup:Cancel() end
                maxDbfPendingPopup = C_Timer.NewTimer(0.5, function()
                    maxDbfPendingPopup = nil
                    if (DB().maxDebuffs or defaults.maxDebuffs) ~= maxDbfOriginal then
                        EllesmereUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Changing Max Debuffs requires a UI reload to take effect.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload    = true,
                        })
                    end
                end)
            end
          end,
          tooltip="Maximum number of debuff icons shown on enemy nameplates." }
    local debuffRow1
        debuffRow1, h = W:DualRow(parent, y, maxDbfCfg, { type="label", text="" });  y = y - h

    -- --- Dispellable Buff Glow ----------------------------------------
    local GO = EllesmereUI.GlowOptions
    local dispelDesc = npDispelGlowDesc
    local dispelGlowDropdown = GO.DropdownSpec(dispelDesc, "Dispel Glow Style")
    -- Enemy Buff Filter (replaces the retired Show All Enemy Buffs toggle;
    -- npEnemyBuffFilter, default "important", "showall" on WoW Forever; the
    -- old key is an inert orphan). UNION semantics: Important = important OR
    -- dispellable (two engine groups); Dispellable = dispellable only; Show
    -- All = every buff; the removed "all" value reads back as important.
    -- The Dispel Glow never changes the filters -- it is just the style the
    -- dispellable group wears, so every shown dispellable buff glows when a
    -- style is set.
    local buffFilterDropdown = { type="dropdown", text="Enemy Buff Filter",
        tooltip = "Which enemy buffs show on nameplates. Important shows the buffs Blizzard flags for enemy nameplates plus anything dispellable; Only Dispellable shows just the buffs that can be dispelled, purged or soothed; Show All shows every buff. With a Dispel Glow style set, every dispellable buff shown glows.",
        values = { important = "Important", dispellable = "Only Dispellable", showall = "Show All" },
        order = { "important", "dispellable", "showall" },
        getValue = function()
            local m = DBVal("npEnemyBuffFilter")
            if m == "dispellable" or m == "showall" then return m end
            return "important"
        end,
        setValue = function(v)
            DB().npEnemyBuffFilter = v
            -- Applies live: RefreshAllAuras drives the container reload;
            -- its cfg pass re-drives both buff group filter strings and
            -- parks/unparks the plain remainder group.
            RefreshAllAuras()
            UpdatePreview()
            C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
        end }
    local dispelGlowRow
    dispelGlowRow, h = W:DualRow(parent, y, buffFilterDropdown, dispelGlowDropdown);  y = y - h

    GO.AttachInline(dispelGlowRow._rightRegion, dispelDesc)

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  TARGET AND FOCUS EFFECTS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TARGET AND FOCUS EFFECTS", y);  y = y - h

    local function hashLineOff() return not (DBVal("hashLineEnabled")) end

    local row
    row, h = W:DualRow(parent, y,
        { type="toggle", text="Show Hash Line on Target at Percent",
          getValue=function() return DBVal("hashLineEnabled") or false end,
          setValue=function(v)
            DB().hashLineEnabled = v
            RefreshAllPlates()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Hash Line Location",
          min=0, max=100, step=1,
          disabled=hashLineOff, disabledTooltip="Show Hash Line on Target at Percent",
          getValue=function() return DBVal("hashLinePercent") or defaults.hashLinePercent end,
          setValue=function(v)
            DB().hashLinePercent = v
            RefreshAllPlates()
            UpdatePreview()
          end });  y = y - h

    -- Add "(Percent)" suffix in smaller, dimmer text next to the slider label
    if not EllesmereUI._prebuilding then
        local rightFrame = row._rightRegion
        if rightFrame then
            local suffixFS = rightFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel
            local regions = { rightFrame:GetRegions() }
            for i = 1, #regions do
                local reg = regions[i]
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Hash Line Location" then
                    sliderLabel = reg
                    break
                end
            end
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", rightFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Percent)"))
            -- Gray out suffix when hash line is off
            EllesmereUI.RegisterWidgetRefresh(function()
                suffixFS:SetAlpha(hashLineOff() and 0.10 or 0.35)
            end)
            suffixFS:SetAlpha(hashLineOff() and 0.10 or 0.35)
        end
    end

    -- Inline color swatch for hash line custom color
    if not EllesmereUI._prebuilding then
        local hashColorGet = function()
            local c = (DB() and DB().hashLineColor) or defaults.hashLineColor
            return c.r, c.g, c.b
        end
        local hashColorSet = function(r, g, b)
            DB().hashLineColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            UpdatePreview()
        end
        local leftRgn = row._leftRegion
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, hashColorGet, hashColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        -- Gray out swatch when hash line is off
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = hashLineOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        swatch:SetAlpha(hashLineOff() and 0.15 or 1)
        swatch:EnableMouse(not hashLineOff())
    end

    -- Row 2: Scale Target Nameplate | Non-Target Opacity
    local tfScaleRow
    tfScaleRow, h = W:DualRow(parent, y,
        { type="slider", text="Scale Target Nameplate",
          trackWidth=110,
          min=50, max=200, step=5,
          getValue=function() return DBVal("targetScale") or defaults.targetScale end,
          setValue=function(v)
            DB().targetScale = v
            for _, plate in pairs(plates) do
                plate:ApplyScale()
            end
          end,
          tooltip="Scales your current target's nameplate. 100% = no change." },
        { type="slider", text="Non-Target Opacity",
          tooltip="Fades enemy nameplates that are not your current target or focus while you have a target. 100 = no fading.",
          min=0, max=100, step=1,
          getValue=function() return DBVal("nonTargetAlpha") or 100 end,
          setValue=function(v)
            DB().nonTargetAlpha = v
            if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
            EllesmereUI:RefreshPage()  -- update the cog disabled state
          end });  y = y - h
    -- "(Percent)" suffix on the target scale slider
    if not EllesmereUI._prebuilding then
        local leftFrame = tfScaleRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel
            local regions = { leftFrame:GetRegions() }
            for i = 1, #regions do
                local reg = regions[i]
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Scale Target Nameplate" then
                    sliderLabel = reg
                    break
                end
            end
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Percent)"))
        end
    end
    -- Inline cog on Non-Target Opacity: focus exclusion toggle.
    if not EllesmereUI._prebuilding then
        local function ntOff() return (DBVal("nonTargetAlpha") or 100) >= 100 end
        local rgn = tfScaleRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = ntOff,
            disabledTooltip = "This option requires Non-Target Opacity to be below 100",
            title = "Non-Target Opacity",
            rows = {
                { type="toggle", label="Keep Focus Full Opacity",
                  tooltip="Your focus target's nameplate never fades with the non-target opacity.",
                  get=function() return DBVal("nonTargetKeepFocus") ~= false end,
                  set=function(v)
                    DB().nonTargetKeepFocus = v
                    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
                  end },
            },
        })
    end

    -- Row 3: Focus Cast Height | Focus Letter
    local focusLetterOff = function()
        return DBVal("focusLetterEnabled") ~= true
    end
    local tfFocusRow
    tfFocusRow, h = W:DualRow(parent, y,
        { type="slider", text="Focus Cast Height",
          trackWidth=110,
          min=100, max=200, step=5,
          getValue=function() return DBVal("focusCastHeight") or defaults.focusCastHeight end,
          setValue=function(v)
            DB().focusCastHeight = v
            ns.RefreshAllSettings()
          end,
          tooltip="Increases the cast bar height on your focus target's nameplate. 100% = normal height." },
        { type="toggle", text="Focus Letter",
          tooltip="Draws a white letter F on your current focus target's nameplate.",
          getValue=function() return DBVal("focusLetterEnabled") == true end,
          setValue=function(v)
            DB().focusLetterEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end });  y = y - h
    -- "(Percent)" suffix on Focus Cast Height
    if not EllesmereUI._prebuilding then
        local leftFrame = tfFocusRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel
            local regions = { leftFrame:GetRegions() }
            for i = 1, #regions do
                local reg = regions[i]
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Focus Cast Height" then
                    sliderLabel = reg
                    break
                end
            end
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Percent)"))
        end
    end

    if not EllesmereUI._prebuilding then
        local rgn = tfFocusRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = focusLetterOff,
            disabledTooltip = "Focus Letter",
            title = "Focus Letter",
            rows = {
                { type="dropdown", label="Anchor",
                  values=FOCUS_LETTER_ANCHORS,
                  order=FOCUS_LETTER_ANCHOR_ORDER,
                  get=GetFocusLetterAnchor,
                  set=function(v)
                    DB().focusLetterAnchor = v
                    RefreshAllPlates()
                  end },
                { type="slider", label="Size", min=6, max=40, step=1,
                  get=function() return DBVal("focusLetterSize") or defaults.focusLetterSize end,
                  set=function(v)
                    DB().focusLetterSize = v
                    RefreshAllPlates()
                  end },
                { type="slider", label="X", min=-100, max=100, step=1,
                  get=function() return DBVal("focusLetterX") or defaults.focusLetterX end,
                  set=function(v)
                    DB().focusLetterX = v
                    RefreshAllPlates()
                  end },
                { type="slider", label="Y", min=-100, max=100, step=1,
                  get=function() return DBVal("focusLetterY") or defaults.focusLetterY end,
                  set=function(v)
                    DB().focusLetterY = v
                    RefreshAllPlates()
                  end },
            },
        })
    end

    -- Row 4: Distance to Target Text
    local tfRangeOff = function() return DBVal("rangeTextEnabled") ~= true end
    local tfRangeRow
    tfRangeRow, h = W:DualRow(parent, y,
        { type="toggle", text="Distance to Target Text (Range)",
          tooltip="Shows the approximate distance to your current target on its nameplate as a range bracket, e.g. 15+ when the target is 15-20 yards away.",
          getValue=function() return DBVal("rangeTextEnabled") == true end,
          setValue=function(v)
            DB().rangeTextEnabled = v
            if ns.RangeText_Apply then ns.RangeText_Apply() end
            EllesmereUI:RefreshPage()
          end },
        { type="label", text="" }
    );  y = y - h
    -- RESIZE cog: text size + X/Y offsets (mirrors the raid-marker cog)
    if not EllesmereUI._prebuilding then
        local rgn = tfRangeRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = tfRangeOff,
            disabledTooltip = "Distance to Target Text (Range)",
            title = "Distance Text",
            rows = {
                { type="slider", label="Text Size", min=6, max=32, step=1,
                  get=function() return DBVal("rangeTextSize") or defaults.rangeTextSize end,
                  set=function(v)
                    DB().rangeTextSize = v
                    if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                  end },
                { type="slider", label="Offset X", min=-200, max=200, step=1,
                  get=function() return DBVal("rangeTextOffsetX") or 0 end,
                  set=function(v)
                    DB().rangeTextOffsetX = v
                    if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                  end },
                { type="slider", label="Offset Y", min=-200, max=200, step=1,
                  get=function() return DBVal("rangeTextOffsetY") or 0 end,
                  set=function(v)
                    DB().rangeTextOffsetY = v
                    if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                  end },
            },
        })
    end
    -- Inline color swatch (default light orange), left of the cog
    if not EllesmereUI._prebuilding then
        local rgn = tfRangeRow._leftRegion
        local rangeColorGet = function()
            local c = (DB() and DB().rangeTextColor) or defaults.rangeTextColor
            return c.r, c.g, c.b
        end
        local rangeColorSet = function(r, g, b)
            DB().rangeTextColor = { r = r, g = g, b = b }
            if ns.RangeText_Refresh then ns.RangeText_Refresh() end
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, rangeColorGet, rangeColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = tfRangeOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        swatch:SetAlpha(tfRangeOff() and 0.15 or 1)
        swatch:EnableMouse(not tfRangeOff())
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  EXTRAS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_MISC, y);  y = y - h

    -- Row 1: Scale Nameplate on Cast | Hide Enemy Name While Casting
    local exCastRow
    exCastRow, h = W:DualRow(parent, y,
        { type="slider", text="Scale Nameplate On Cast",
          trackWidth=110,
          min=50, max=200, step=5,
          getValue=function() return DBVal("castScale") or defaults.castScale end,
          setValue=function(v)
            DB().castScale = v
          end,
          tooltip="Scales enemy nameplates while they are casting. 100% = no change." },
        { type="toggle", text="Hide Enemy Name While Casting",
          tooltip="Hide the enemy name text while that nameplate's cast bar is visible.",
          getValue=function() return DBVal("hideEnemyNameWhileCasting") == true end,
          setValue=function(v)
            DB().hideEnemyNameWhileCasting = v
            ns.RefreshAllSettings()
            UpdatePreview()
          end });  y = y - h
    -- "(Percent)" suffix on the cast scale slider
    if not EllesmereUI._prebuilding then
        local leftFrame = exCastRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel
            local regions = { leftFrame:GetRegions() }
            for i = 1, #regions do
                local reg = regions[i]
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Scale Nameplate On Cast" then
                    sliderLabel = reg
                    break
                end
            end
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Percent)"))
        end
    end

    -- Row 2: Name Raid Marker (target marker shown directly before the enemy name; size lives on inline cog) | Experimental: Cast Lockout as CC Icon.
    local nameRaidMarkerRow
    nameRaidMarkerRow, h = W:DualRow(parent, y,
        { type="toggle", text="Name Raid Marker",
          tooltip="Shows the target marker directly before the enemy name text. Uses its own size and does not use the Core Positions raid marker slot.",
          getValue=function() return DBVal("nameRaidMarkerEnabled") == true end,
          setValue=function(v)
            DB().nameRaidMarkerEnabled = v
            ns.RefreshAllSettings()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Experimental: Cast Lockout as CC Icon",
          tooltip = "Show successful interrupt lockouts in the crowd-control icon slot.\n\nDue to addon restrictions, the duration shown is a generic 4 seconds for all classes, so it is not 100% accurate.",
          getValue = function() return DBVal("showCastLockoutAsCrowdControl") == true end,
          setValue = function(v)
              DB().showCastLockoutAsCrowdControl = v
              RefreshAllAuras()
          end });  y = y - h

    if not EllesmereUI._prebuilding then
        local function nameRaidMarkerOff() return DBVal("nameRaidMarkerEnabled") ~= true end
        local rgn = nameRaidMarkerRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = nameRaidMarkerOff,
            disabledTooltip = "Name Raid Marker",
            title = "Name Raid Marker",
            rows = {
                { type="slider", label="Size", min=6, max=32, step=1,
                  get=function() return DBVal("nameRaidMarkerSize") or defaults.nameRaidMarkerSize end,
                  set=function(v)
                    DB().nameRaidMarkerSize = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
            },
        })
    end

    -- Row 3: Replace Quest Icon with Objective | Line of Sight Opacity
    local questObjRow
    questObjRow, h = W:DualRow(parent, y,
        { type="toggle", text="Replace Quest Icon with Objective",
          getValue=function() return DBVal("replaceQuestIconWithObjective") == true end,
          setValue=function(v)
            DB().replaceQuestIconWithObjective = v
            if ns.RefreshQuestObjective then ns.RefreshQuestObjective() end
            EllesmereUI:RefreshPage()
          end,
          tooltip="On quest mobs in the open world, replaces the quest icon with the objective progress (ex: kill quests show 0/6, percentage objectives show 50%)." },
        -- Line of Sight Opacity: pure CVar passthrough (like Lag Tolerance). Nothing stored in our DB -- getValue reflects the live CVar, setValue only writes on slider move; combat-guarded, mirrors SetCVarSafe.
        { type="slider", text="Line of Sight Opacity",
          tooltip="Nameplates opacity for units that are out of line of sight. 0 = fully transparent, 1 = fully opaque.",
          min=0, max=1, step=0.01,
          getValue=function() return tonumber(GetCVar("nameplateOccludedAlphaMult")) or 0 end,
          setValue=function(v)
            if InCombatLockdown() then return end
            EllesmereUI.SetCVar("nameplateOccludedAlphaMult", v, "EllesmereUINameplates")
          end });  y = y - h

    -- Inline cog on the quest toggle: objective text size
    if not EllesmereUI._prebuilding then
        local function questObjOff() return DBVal("replaceQuestIconWithObjective") ~= true end
        local rgn = questObjRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = questObjOff,
            disabledTooltip = "Replace Quest Icon with Objective",
            title = "Quest Objective",
            rows = {
                { type = "slider", label = "Text Size", min = 6, max = 24, step = 1,
                  get = function() return DBVal("questObjectiveTextSize") or defaults.questObjectiveTextSize end,
                  set = function(v)
                    DB().questObjectiveTextSize = v
                    if ns.RefreshQuestObjective then ns.RefreshQuestObjective() end
                  end },
            },
        })
    end

    -- Row 4: Range Check (custom cutoff in the inline cog) | Out of Range Opacity
    local rangeCheckRow
    rangeCheckRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Range Check",
          values={ disabled="Disabled", auto="Auto (Class/Spec)", custom="Custom" },
          order={ "disabled", "auto", "custom" },
          tooltip="Disabled runs no nameplate range checks. Auto uses your class and specialization's normal attack range. Custom uses the range set in the cog beside this option.",
          getValue=function() return DBVal("outOfRangeMode") or defaults.outOfRangeMode end,
          setValue=function(v)
            local prev = DBVal("outOfRangeMode") or defaults.outOfRangeMode
            local function ApplyMode(mode)
                DB().outOfRangeMode = mode
                if mode == "custom" and DB().outOfRangeCustomRange == nil then
                    DB().outOfRangeCustomRange = EllesmereUI.Range_GetAttackCutoff()
                end
                if ns.RangeText_Apply then ns.RangeText_Apply() end
                EllesmereUI:RefreshPage()
            end
            -- Performance confirm on the disabled -> enabled edge only:
            -- the sweep range-checks every visible nameplate continuously.
            if prev == "disabled" and v ~= "disabled" then
                EllesmereUI:ShowConfirmPopup({
                    title = "Out of Range Opacity",
                    message = "This feature runs continuous range checks against every visible enemy nameplate. It is one of the more expensive features in EllesmereUI and can measurably increase CPU usage in crowded areas.",
                    confirmText = "Enable",
                    cancelText = "Cancel",
                    onConfirm = function() ApplyMode(v) end,
                    onCancel = function() EllesmereUI:RefreshPage() end,
                })
                return
            end
            ApplyMode(v)
          end },
        { type="slider", text="Out of Range Opacity",
          tooltip="Opacity used for enemy nameplates outside the selected attack range.",
          min=0, max=100, step=1,
          disabled=function() return (DBVal("outOfRangeMode") or defaults.outOfRangeMode) == "disabled" end,
          disabledTooltip="Range Check: Auto or Custom",
          getValue=function() return DBVal("outOfRangeAlpha") or defaults.outOfRangeAlpha end,
          setValue=function(v)
            DB().outOfRangeAlpha = v
            if ns.RangeText_Apply then ns.RangeText_Apply() end
          end });  y = y - h

    -- Inline cog on Range Check: the custom cutoff lives here.
    if not EllesmereUI._prebuilding then
        local function customOff()
            return (DBVal("outOfRangeMode") or defaults.outOfRangeMode) ~= "custom"
        end
        local rgn = rangeCheckRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = customOff,
            disabledTooltip = "Range Check: Custom",
            title = "Range Check",
            rows = {
                { type="slider", label="Custom Range", min=5, max=50, step=5,
                  tooltip="Attack-range cutoff used by Out of Range Opacity. Five-yard steps match the available fallback range checks.",
                  disabled=customOff,
                  disabledTooltip="Range Check: Custom",
                  get=function()
                      return DBVal("outOfRangeCustomRange") or EllesmereUI.Range_GetAttackCutoff()
                  end,
                  set=function(v)
                    DB().outOfRangeCustomRange = v
                    if ns.RangeText_Apply then ns.RangeText_Apply() end
                  end },
            },
        })
    end

    -- Row 5: Execute Pulse Glow | Hide Enemy Nameplates out of Combat
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Execute Pulse Glow",
          tooltip="Pulses a red glow on enemy nameplates below 30% health.",
          getValue=function() return DBVal("lowHpGlow") == true end,
          setValue=function(v)
            DB().lowHpGlow = v
            ns.RefreshAllSettings()
          end },
        { type="toggle", text="Hide Enemy Nameplates out of Combat",
          tooltip="Hide enemy nameplates while you are out of combat; they return the moment combat starts. Drives the same game setting as the Show Enemy Name Plates keybind.",
          getValue=function() return DBVal("hideEnemyPlatesOOC") == true end,
          setValue=function(v)
            DB().hideEnemyPlatesOOC = v
            if ns.ApplyOOCPlates then ns.ApplyOOCPlates() end
          end });  y = y - h

    -- Row 6 (Blood Death Knight only): Hide Copies of Blood Plague. The row
    -- is not built at all for anyone else -- the setting only affects a
    -- debuff Blood spec applies.
    do
        local _, classFile = UnitClass("player")
        local specIdx = C_SpecializationInfo.GetSpecialization()
        local specID = specIdx and C_SpecializationInfo.GetSpecializationInfo(specIdx)
        if classFile == "DEATHKNIGHT" and specID == 250 then
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Hide Copies of Blood Plague",
                  tooltip="Shows a single Blood Plague debuff on enemy nameplates instead of one per copy (Blood Boil from weapon copies).",
                  getValue=function() return DBVal("hideBloodPlagueCopies") ~= false end,
                  setValue=function(v)
                    DB().hideBloodPlagueCopies = v
                    if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
                  end },
                EllesmereUI.BlankRowCfg());  y = y - h
        end
    end

    -- Row 7 (WoW Forever warriors only): Show Sunder Armor.
    if EllesmereUI.IS_FOREVER and select(2, UnitClass("player")) == "WARRIOR" then
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Sunder Armor",
              tooltip="Shows Sunder Armor and its stacks on enemy nameplates, including stacks applied by other warriors.",
              getValue=function() return DBVal("showSunderArmor") == true end,
              setValue=function(v)
                DB().showSunderArmor = v
                if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
              end },
            EllesmereUI.BlankRowCfg());  y = y - h
    end

    return math.abs(y)
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildGeneralPage = BuildGeneralPage
