-------------------------------------------------------------------------------
--  EUI_Basics_Options.lua
--  Registers the Basics module with EllesmereUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_CHAT          = "Chat"
local PAGE_MINIMAP       = "Minimap"
local PAGE_FRIENDS       = "Friends"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR        = "Cursor"
local PAGE_DMG_METERS    = "Damage Meters"

local SECTION_CHAT    = "CHAT"
local SECTION_MINIMAP = "MINIMAP"

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
        db = _G._EBS_AceDB
    end)

    local function DB()
        if not db then db = _G._EBS_AceDB end
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
        if _G._EBS_ApplyFriends then _G._EBS_ApplyFriends() end
    end

    local function RefreshAll()
        if _G._EBS_ApplyAll then _G._EBS_ApplyAll() end
    end

    ---------------------------------------------------------------------------
    --  Visibility row builder (reused across all pages)
    ---------------------------------------------------------------------------
    local PP = EllesmereUI.PP
    local function BuildVisibilityRow(W, parent, y, getCfg, refreshFn)
        local visRow, visH = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = EllesmereUI.VIS_VALUES,
              order  = EllesmereUI.VIS_ORDER,
              getValue=function()
                  local c = getCfg(); if not c then return "always" end
                  if not c.enabled and c.enabled ~= nil then return "disabled" end
                  return c.visibility or "always"
              end,
              setValue=function(v)
                  local c = getCfg(); if not c then return end
                  if v == "disabled" then
                      c.enabled = false
                      c.visibility = "disabled"
                  else
                      c.enabled = true
                      c.visibility = v
                  end
                  if refreshFn then refreshFn() end
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Visibility Options",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                EllesmereUI.VIS_OPT_ITEMS,
                function(k) local c = getCfg(); return c and c[k] or false end,
                function(k, v)
                    local c = getCfg(); if not c then return end
                    c[k] = v
                    if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        return visH
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
            { tooltip = "Class Colored",
              hasAlpha = false,
              getValue = function()
                  local _, classFile = UnitClass("player")
                  local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                  if cc then return cc.r, cc.g, cc.b end
                  return 0.05, 0.05, 0.05
              end,
              setValue = function() end,
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
    local function BuildChatPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, SECTION_CHAT, y);  y = y - h

        h = BuildVisibilityRow(W, parent, y, ChatDB, RefreshChat);  y = y - h

        -- Font Size | Background Opacity
        _, h = W:DualRow(parent, y,
            { type="slider", text="Font Size", min=8, max=24, step=1,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.fontSize or 14 end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.fontSize = v
                RefreshChat()
              end },
            { type="slider", text="Background Opacity", min=0, max=1, step=0.05,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.bgAlpha or 0.6 end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.bgAlpha = v
                RefreshChat()
              end }
        );  y = y - h

        -- Border Color | (spacer)
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Border Color",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              swatches = MakeBorderSwatch(ChatDB, RefreshChat) },
            { type="label", text="" }
        );  y = y - h

        -- Hide Chat Buttons | Hide Tab Flash
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Chat Buttons",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.hideButtons end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.hideButtons = v
                RefreshChat()
              end },
            { type="toggle", text="Hide Tab Flash",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.hideTabFlash end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.hideTabFlash = v
                RefreshChat()
              end }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------
    local function BuildMinimapPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, SECTION_MINIMAP, y);  y = y - h

        h = BuildVisibilityRow(W, parent, y, MinimapDB, RefreshMinimap);  y = y - h

        -- Scale | Border Color
        _, h = W:DualRow(parent, y,
            { type="slider", text="Scale", min=0.5, max=2.0, step=0.1,
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.scale or 1.0 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.scale = v
                RefreshMinimap()
              end },
            { type="multiSwatch", text="Border Color",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              swatches = MakeBorderSwatch(MinimapDB, RefreshMinimap) }
        );  y = y - h

        -- Hide Zone Text | Hide Minimap Buttons
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Zone Text",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.hideZoneText end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.hideZoneText = v
                RefreshMinimap()
              end },
            { type="toggle", text="Hide Minimap Buttons",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.hideButtons end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.hideButtons = v
                RefreshMinimap()
              end }
        );  y = y - h

        return math.abs(y)
    end

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

    local function BuildFriendsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        -- ── DISPLAY ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Enable Friends Skin | Background Opacity
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Friends Skin",
              getValue=function() local f = FriendsDB(); return f and f.enabled end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.enabled = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Background Opacity", min=0, max=1, step=0.05,
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.bgAlpha or 0.8 end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.bgAlpha = v
                RefreshFriends()
              end }
        );  y = y - h

        -- Enable Border | Border Color
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Border",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.showBorder ~= false end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.showBorder = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="multiSwatch", text="Border Color",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled or not f.showBorder end,
              disabledTooltip="Enable border first",
              swatches = MakeBorderSwatch(FriendsDB, RefreshFriends) }
        );  y = y - h

        -- Accent Tab Underline
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Accent Tab Underline",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.useAccentTab end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.useAccentTab = v
                RefreshFriends()
              end },
            { type="label", text="" }
        );  y = y - h

        -- ── CLASS ICONS ──────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "CLASS ICONS", y);  y = y - h

        -- Show Class Icons | Icon Style
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Class Icons",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.showClassIcons end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.showClassIcons = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Icon Style",
              disabled=function()
                local f = FriendsDB()
                return not f or not f.enabled or not f.showClassIcons
              end,
              disabledTooltip="Enable class icons first",
              values = ICON_STYLE_VALUES,
              order  = ICON_STYLE_ORDER,
              getValue=function()
                local f = FriendsDB(); return f and f.iconStyle or "blizzard"
              end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.iconStyle = v
                RefreshFriends()
              end }
        );  y = y - h

        -- ── FRIEND GROUPS ────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "FRIEND GROUPS", y);  y = y - h

        -- Enable Groups | Show Ungrouped
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Friend Groups",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.groupsEnabled end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.groupsEnabled = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Ungrouped",
              disabled=function()
                local f = FriendsDB()
                return f and (not f.enabled or not f.groupsEnabled)
              end,
              disabledTooltip="Enable friend groups first",
              getValue=function() local f = FriendsDB(); return f and f.showUngrouped end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.showUngrouped = v
                RefreshFriends()
              end }
        );  y = y - h

        -- Group management (only shown when groups enabled)
        local fp = FriendsDB()
        if fp and fp.groupsEnabled then
            -- Add Group button
            _, h = W:DualRow(parent, y,
                { type="button", text="Add Group",
                  onClick=function()
                    local f = FriendsDB(); if not f then return end
                    local idx = #f.groups + 1
                    f.groups[idx] = { name = "Group " .. idx, collapsed = false }
                    RefreshFriends()
                    EllesmereUI:RefreshPage()
                  end },
                { type="label", text="" }
            );  y = y - h

            -- List existing groups with delete (capture name, not index, for safety)
            for i, group in ipairs(fp.groups) do
                local groupName = group.name
                _, h = W:DualRow(parent, y,
                    { type="label", text="|cff0cd29d" .. i .. ".|r  " .. groupName },
                    { type="button", text="Delete",
                      onClick=function()
                        local f = FriendsDB(); if not f then return end
                        for j = #f.groups, 1, -1 do
                            if f.groups[j].name == groupName then
                                for k, v in pairs(f.assignments) do
                                    if v == groupName then f.assignments[k] = nil end
                                end
                                table.remove(f.groups, j)
                                break
                            end
                        end
                        RefreshFriends()
                        EllesmereUI:RefreshPage()
                      end }
                );  y = y - h
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIBasics", {
        title       = "Basics",
        description = "Lightweight skins for all major Blizzard UI objects.",
        pages       = { PAGE_CURSOR, PAGE_DMG_METERS, PAGE_QUEST_TRACKER, PAGE_FRIENDS, PAGE_CHAT, PAGE_MINIMAP },
        disabledPages = { PAGE_DMG_METERS },
        disabledPageTooltips = { [PAGE_DMG_METERS] = "Coming Soon" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_CHAT    then return BuildChatPage(pageName, parent, yOffset) end
            if pageName == PAGE_MINIMAP then return BuildMinimapPage(pageName, parent, yOffset) end
            if pageName == PAGE_FRIENDS then return BuildFriendsPage(pageName, parent, yOffset) end
            if pageName == PAGE_QUEST_TRACKER and _G._EBS_BuildQuestTrackerPage then
                return _G._EBS_BuildQuestTrackerPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_CURSOR and _G._EBS_BuildCursorPage then
                return _G._EBS_BuildCursorPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if _G._EBS_AceDB then
                _G._EBS_AceDB:ResetProfile()
            end
            if _G._EBS_ResetCursor then _G._EBS_ResetCursor() end
            if _G._EBS_ResetQuestTracker then _G._EBS_ResetQuestTracker() end
            EllesmereUI:InvalidatePageCache()
            RefreshAll()
            if _G._EBS_ProcessFriendButtons then _G._EBS_ProcessFriendButtons() end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /ebs
    ---------------------------------------------------------------------------
    SLASH_EBS1 = "/ebs"
    SlashCmdList.EBS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIBasics")
    end
end)
