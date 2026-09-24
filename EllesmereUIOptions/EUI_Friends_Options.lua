if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Friends_Options.lua
--  Registers the Friends List module with EllesmereUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIFriends"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local PAGE_CHAT          = "Chat"
local PAGE_MINIMAP       = "Minimap"
local PAGE_FRIENDS       = "Friends"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR        = "Cursor"
local PAGE_DMG_METERS    = "Damage Meters"

local SECTION_CHAT    = "CHAT"
local SECTION_MINIMAP = "DISPLAY"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db

    C_Timer.After(0, function()
        db = _G._EFR_DB
    end)

    local function DB()
        if not db then db = _G._EFR_DB end
        return db and db.profile
    end

    local function ChatDB()
        local p = DB()
        return p and p.chat
    end

    local function MinimapDB()
        local p = DB()
        return p and p.minimap
    end

    local function FriendsDB()
        local p = DB()
        return p and p.friends
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshChat()
        if _G._EBS_ApplyChat then _G._EBS_ApplyChat() end
    end

    local function RefreshMinimap()
        if _G._EBS_ApplyMinimap then _G._EBS_ApplyMinimap() end
    end

    local function RefreshFriends()
        if _G._EFR_ApplyFriends then _G._EFR_ApplyFriends() end
    end

    local function RefreshAll()
        if _G._EBS_ApplyAll then _G._EBS_ApplyAll() end
    end

    ---------------------------------------------------------------------------
    --  Border color multiSwatch builder
    ---------------------------------------------------------------------------
    local function MakeBorderSwatch(getCfg, refreshFn)
        return {
            { tooltip = "Custom Color",
              hasAlpha = false,
              getValue = function()
                  local c = getCfg()
                  if not c then return 0.05, 0.05, 0.05 end
                  return c.borderR, c.borderG, c.borderB
              end,
              setValue = function(r, g, b)
                  local c = getCfg(); if not c then return end
                  c.borderR, c.borderG, c.borderB = r, g, b
                  refreshFn()
              end,
              onClick = function(self)
                  local c = getCfg(); if not c then return end
                  if c.useClassColor then
                      c.useClassColor = false
                      refreshFn(); EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = getCfg()
                  if not c or not c.enabled then return 0.15 end
                  return c.useClassColor and 0.3 or 1
              end },
            { tooltip = "Accent Color",
              hasAlpha = false,
              getValue = function()
                  local ar, ag, ab = EllesmereUI.GetAccentColor()
                  return ar, ag, ab
              end,
              setValue = function() end,
              -- Flag name stays `useClassColor` for backwards compat with
              -- users who already have it stamped in their SavedVariables.
              -- Only the color resolution changes -- the flag now means
              -- "use live accent" rather than "use class color".
              onClick = function()
                  local c = getCfg(); if not c then return end
                  c.useClassColor = true
                  refreshFn(); EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = getCfg()
                  if not c or not c.enabled then return 0.15 end
                  return c.useClassColor and 1 or 0.3
              end },
        }
    end

    ---------------------------------------------------------------------------
    --  Chat Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Friends List Page
    ---------------------------------------------------------------------------

    local ICON_STYLE_VALUES = {
        blizzard = "Blizzard",
        modern   = "Modern",
        pixel    = "Pixel",
        glyph    = "Glyph",
        arcade   = "Arcade",
        legend   = "Legend",
        midnight = "Midnight",
        runic    = "Runic",
    }
    local ICON_STYLE_ORDER = {
        "blizzard", "modern", "pixel", "glyph",
        "arcade", "legend", "midnight", "runic",
    }

    -- Live repaint after a display toggle: the legacy list's row pass, plus a
    -- decoration-only pass over the 12.1 cards (never Blizzard's view:Refresh,
    -- which regenerates the list data from our execution and taints whispers).
    local function RepaintFriendRows()
        if _G._EFR_ProcessFriendButtons then _G._EFR_ProcessFriendButtons() end
        if _G._EFR_RedecorateTiles then _G._EFR_RedecorateTiles() end
    end

    local function BuildFriendsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, row, h

        EllesmereUI:ClearContentHeader()

        -- Stock styles (Blizzard Style / Classic WoW UI) keep Blizzard's own
        -- window and rows on either friends window (12.1 Social UI or the
        -- legacy one) and add the class icon, class-coloured name and region
        -- mark to them, so those rows and auto-accept stay. The border and
        -- accent rows drive only the EllesmereUI skin of the legacy window,
        -- faction banners also the 12.1 tiles; all three hide under stock.
        local BS = EllesmereUI.BlizzStyle
        local function Gate(cfg)
            if BS then BS.Gate("friends", cfg) end
            return cfg
        end

        -- DISPLAY
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h
        if BS then y = BS.Note(parent, y, "friends") end

        -- Class Icon Theme | Class Color Names
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Class Icon Theme",
              values = ICON_STYLE_VALUES,
              order  = ICON_STYLE_ORDER,
              getValue=function()
                local f = FriendsDB(); return f and f.iconStyle or "modern"
              end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.iconStyle = v
                RepaintFriendRows()
              end },
            { type="toggle", text="Class Color Names",
              getValue=function() local f = FriendsDB(); return f and f.classColorNames end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.classColorNames = v
                RepaintFriendRows()
              end }
        );  y = y - h

        -- Border Size | Border Color
        _, h = W:DualRow(parent, y,
            Gate({ type="slider", text="Border Size", min=0, max=4, step=1,
              getValue=function() local f = FriendsDB(); return f and f.borderSize or 0 end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.borderSize = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end }),
            Gate({ type="multiSwatch", text="Border Color",
              disabled=function()
                local f = FriendsDB()
                return not f or (f.borderSize or 0) == 0
              end,
              disabledTooltip="Set Border Size above 0", rawTooltip=true,
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = FriendsDB()
                      if not c then return 0.05, 0.05, 0.05 end
                      return c.borderR, c.borderG, c.borderB
                  end,
                  setValue = function(r, g, b)
                      local c = FriendsDB(); if not c then return end
                      c.borderR, c.borderG, c.borderB = r, g, b
                      RefreshFriends()
                  end,
                  onClick = function(self)
                      local c = FriendsDB(); if not c then return end
                      if c.useClassColor then
                          c.useClassColor = false
                          RefreshFriends(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = FriendsDB()
                      if not c or not c.enabled then return 0.15 end
                      return c.useClassColor and 0.3 or 1
                  end },
                { tooltip = "Accent Colored",
                  hasAlpha = false,
                  getValue = function()
                      local ar, ag, ab = EllesmereUI.GetAccentColor()
                      return ar, ag, ab
                  end,
                  setValue = function() end,
                  onClick = function()
                      local c = FriendsDB(); if not c then return end
                      c.useClassColor = true
                      RefreshFriends(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = FriendsDB()
                      if not c or not c.enabled then return 0.15 end
                      return c.useClassColor and 1 or 0.3
                  end },
              } })
        );  y = y - h

        -- Enable Accent Colors | Enable Faction Banners
        _, h = W:DualRow(parent, y,
            Gate({ type="toggle", text="Enable Accent Colors",
              getValue=function() local f = FriendsDB(); return f and (f.accentColors ~= false) end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.accentColors = v
                RefreshFriends()
              end }),
            Gate({ type="toggle", text="Enable Faction Banners",
              getValue=function() local f = FriendsDB(); return f and (f.factionBanners ~= false) end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.factionBanners = v
                RepaintFriendRows()
              end })
        );  y = y - h

        -- Show Region Icons | Auto-Accept Friend Invites
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Region Icons",
              tooltip="Shows a map icon of the friend's region if they are not playing within your region",
              getValue=function() local f = FriendsDB(); return f and (f.showRegionIcons ~= false) end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.showRegionIcons = v
                RepaintFriendRows()
              end },
            { type="toggle", text="Auto-Accept Friend Invites",
              tooltip="Auto-accepts all group invites from people on your friends list",
              getValue=function() local f = FriendsDB(); return f and f.autoAcceptFriendInvites end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.autoAcceptFriendInvites = v
                if _G._EFR_SyncAutoAccept then _G._EFR_SyncAutoAccept() end
                EllesmereUI:RefreshPage()  -- update the auto-accept cog disabled state
              end }
        );  y = y - h

        -- Guildmate option lives in a cog on Auto-Accept Friend Invites; it
        -- only extends that feature, so the cog blocks while the toggle is off.
        if not EllesmereUI._prebuilding then
        local rgn = row._rightRegion
        local function autoAcceptOff()
            local f = FriendsDB()
            return not (f and f.autoAcceptFriendInvites)
        end
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Auto Accept Settings",
            rows = {
                { type="toggle", label="Accept Invites from Guildmates",
                  get=function() local f = FriendsDB(); return f and f.autoAcceptGuildInvites end,
                  set=function(v)
                    local f = FriendsDB(); if not f then return end
                    f.autoAcceptGuildInvites = v
                  end }
            },
        })
        EllesmereUI.MakeCogBtn(rgn, cogShow, nil, nil, autoAcceptOff, "Auto-Accept Friend Invites")
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIFriends", {
        title       = "Friends List",
        description = "Custom friends list with groups, notes, and realm grouping.",
        pages       = { "Friends" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == "Friends" then return BuildFriendsPage(pageName, parent, yOffset) end
        end,
        onReset = function()
            if _G._EFR_DB and _G._EFR_DB.ResetProfile then
                _G._EFR_DB:ResetProfile()
            end
            EllesmereUI:InvalidatePageCache()
            if _G._EFR_ApplyFriends then _G._EFR_ApplyFriends() end
            if _G._EFR_SyncAutoAccept then _G._EFR_SyncAutoAccept() end
            RepaintFriendRows()
        end,
    })

    SLASH_EFR1 = "/efr"
    SlashCmdList.EFR = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIFriends")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
