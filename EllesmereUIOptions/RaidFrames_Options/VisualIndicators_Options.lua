if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  RaidFrames_Options\VisualIndicators_Options.lua
--  Raid Frames options: the Indicators, Dispels, Top Name Bar, Friendly Boss
--  and Extra Frames, Pet Frames and Range & Tooltip sections of the raid and
--  party pages. Called by BuildVisualSections after BuildVisualBars; returns y.
--  Shared helpers come from ns._RFO_OptEnv.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]
if not ns then return end  -- module disabled: no options page

local function BuildVisualIndicators(parent, y, W, onSection, EYE, CustomBorderOff, CustomBorderOffTip)
    local env = ns._RFO_OptEnv
    local db, floor, IsPreviewOff, MissingGlowDesc = env.db, env.floor, env.IsPreviewOff, env.MissingGlowDesc
    local optState, PP, ReloadAndUpdate, SGet = env.optState, env.PP, env.ReloadAndUpdate, env.SGet
    local SSet, SVal, SWrite = env.SSet, env.SVal, env.SWrite
    local _, h
    local row
    local _secY = y  -- section start tracker
    -------------------------------------------------------------------
    --  INDICATORS
    -------------------------------------------------------------------
    local indicatorHeader
    indicatorHeader, h = W:SectionHeader(parent, "INDICATORS", y); y = y - h

    -- Eyeball: toggle indicator visibility on preview (raid + party)
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON

        local indLabel
        for _, rgn in ipairs({ indicatorHeader:GetRegions() }) do
            if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "INDICATORS" then
                indLabel = rgn; break
            end
        end
        local eyeBtn = CreateFrame("Button", nil, indicatorHeader)
        eyeBtn:SetSize(24, 24)
        if indLabel then
            eyeBtn:SetPoint("LEFT", indLabel, "RIGHT", 5, 0)
        else
            eyeBtn:SetPoint("LEFT", indicatorHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeBtn:SetFrameLevel(indicatorHeader:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()

        -- On ns so the preview can read it.
        if ns._indicatorsVisible == nil then ns._indicatorsVisible = false end

        local function RefreshIndicatorEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                eyeBtn:SetAlpha(0.15)
                return
            end
            eyeTex:SetTexture(ns._indicatorsVisible and EYE_INVISIBLE or EYE_VISIBLE)
            eyeBtn:SetAlpha(0.4)
        end
        EYE.refreshIndicatorEye = RefreshIndicatorEye
        RefreshIndicatorEye()
        eyeBtn:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            ns._indicatorsVisible = not ns._indicatorsVisible
            -- Indicators are exclusive with health/power/dispel effects.
            if ns._indicatorsVisible then
                if ns._healthAnimActive then
                    if ns._stopHealthAnim then ns._stopHealthAnim() end
                    if EYE.refreshHealthEye then EYE.refreshHealthEye() end
                end
                if ns._powerAnimActive then
                    if ns._stopPowerAnim then ns._stopPowerAnim() end
                    if EYE.refreshPowerEye then EYE.refreshPowerEye() end
                end
                if ns._dispelsVisible then
                    ns._dispelsVisible = false
                    if EYE.refreshDispelEye then EYE.refreshDispelEye() end
                end
            end
            RefreshIndicatorEye()
            if ns.PvRefresh then ns.PvRefresh() end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, ns._indicatorsVisible and "Hide indicators on preview" or "Show indicators on preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then self:SetAlpha(0.4) end
            EllesmereUI.HideWidgetTooltip()
        end)
    end  -- close do (indicators eyeball)

    -- WoW Forever: Missing Buffs, first in the section (runtime in
    -- EUI_RaidFrames_ForeverMissingBuffs.lua). The raid marker row's
    -- shape: Position (None turns it off) | Size, offsets in the cog.
    if EllesmereUI.IS_FOREVER then
        local mbPositionValues = {
            none        = "None",
            topleft     = "Top Left",
            top         = "Top",
            topright    = "Top Right",
            left        = "Left",
            center      = "Center",
            right       = "Right",
            bottomleft  = "Bottom Left",
            bottom      = "Bottom",
            bottomright = "Bottom Right",
        }
        local mbPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
        local mbRow
        mbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Missing Buffs", values=mbPositionValues, order=mbPositionOrder,
              tooltip="Shows Fortitude, Mark of the Wild, Spirit or Thorns on a member who is missing it, for the buffs you can cast yourself (choose which in the cog).",
              getValue=function()
                  if not SVal("showMissingBuffs", true) then return "none" end
                  return SVal("missingBuffsPosition", "top")
              end,
              setValue=function(v)
                  if v == "none" then
                      SSet("showMissingBuffs", false)
                  else
                      SWrite("showMissingBuffs", true)
                      SSet("missingBuffsPosition", v)
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Missing Buffs Size", min=8, max=40, step=1,
              disabled=function() return not SVal("showMissingBuffs", true) end,
              disabledTooltip="Missing Buffs",
              getValue=function() return SVal("missingBuffsSize", 22) end,
              setValue=function(v) SSet("missingBuffsSize", v) end });  y = y - h
        do
            local rgn = mbRow._leftRegion
            -- The role blessings, None first: the client's own spell names minus
            -- the words every blessing starts with ("Blessing of ", in any
            -- language; names sharing no leading word stay whole), English
            -- if the names are not loaded. Reads go through the runtime's
            -- resolver over the page's raw, party-aware reads, so an unset
            -- role shows what it does.
            local blessOrder = { "none", "might", "wisdom", "kings", "salvation", "light" }
            local BLESS_ID = { might = 19740, wisdom = 19742, kings = 20217, salvation = 1038, light = 19977 }
            local BLESS_EN = { might = "Might", wisdom = "Wisdom", kings = "Kings", salvation = "Salvation", light = "Light" }
            local blessValues = { none = "None" }
            local full, common = {}, nil
            for i = 2, #blessOrder do
                local n = C_Spell.GetSpellName(BLESS_ID[blessOrder[i]])
                if not n then full = nil; break end
                full[blessOrder[i]] = n
                local j = 0
                if common then
                    while j < #common and j < #n and common:byte(j + 1) == n:byte(j + 1) do j = j + 1 end
                end
                common = common and common:sub(1, j) or n
            end
            local cut = full and common and common:match("^(.*%s)")
            for i = 2, #blessOrder do
                local k = blessOrder[i]
                local n = full and full[k]
                blessValues[k] = (n and cut) and n:sub(#cut + 1) or n or BLESS_EN[k]
            end
            local view = setmetatable({}, { __index = function(_, k) return SGet(k) end })
            local function BlessRow(label, tip, role)
                return { type="dropdown", label=label, tooltip=tip, values=blessValues, order=blessOrder,
                  get=function() return ns.RF_FvBlessingChoice(view, role) end,
                  set=function(v) SSet(ns.RF_FvBlessingKey[role], v) end }
            end
            local rows = {
                -- One switch per buff (all on by default). The list is the
                -- profile's, shared across classes, so every buff is listed;
                -- only the ones this character can cast ever show. The
                -- paladin blessings follow the role rows below instead.
                { type="reordercheck", label="Buffs", ddWidth=170,  -- the Glow dropdown's width
                  hint="Only buffs you can cast show",
                  items={
                      { key="missingBuffsFort",   label="Fortitude",        fixed=true },
                      { key="missingBuffsMark",   label="Mark of the Wild", fixed=true },
                      { key="missingBuffsSpirit", label="Spirit",           fixed=true },
                      { key="missingBuffsThorns", label="Thorns",           fixed=true },
                  },
                  get=function(key) return SVal(key, true) end,
                  set=function(key, on) SSet(key, on) end },
                -- Stored false, not nil, so a party tab with its own settings
                -- can turn it off over a raid value that is on.
                { type="toggle", label="Thorns Only on Tank",
                  tooltip="Thorns shows on tanks only while the group has one, and on you while solo or without a tank.",
                  disabled=function() return not SVal("missingBuffsThorns", true) end,
                  disabledTooltip="Thorns",
                  get=function() return SVal("missingBuffsThornsTank", false) end,
                  set=function(v) SSet("missingBuffsThornsTank", v and true or false) end },
                BlessRow("Tank Blessing", "Reminds you while a tank lacks this blessing. Members with no assigned role count any blessing.", "TANK"),
                BlessRow("Healer Blessing", "Reminds you while a healer lacks this blessing.", "HEALER"),
                BlessRow("DPS Blessing", "Reminds you while a damage dealer lacks this blessing.", "DAMAGER"),
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("missingBuffsOffsetX", 0) end,
                  set=function(v) SSet("missingBuffsOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("missingBuffsOffsetY", 0) end,
                  set=function(v) SSet("missingBuffsOffsetY", v) end },
            }
            -- The icons' glow: the shared glow controls (also listed on
            -- Global Settings > Glows); the Pixel Glow rows show only
            -- while Pixel Glow is picked.
            for _, r in ipairs(EllesmereUI.GlowOptions.PopupRows(MissingGlowDesc(SVal, SWrite), "Glow", true)) do
                rows[#rows + 1] = r
            end
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Missing Buffs",
                rows = rows,
                disabled = function() return not SVal("showMissingBuffs", true) end,
                disabledTooltip = "Missing Buffs",
            })
        end
    end

    local RI_STYLES = ns.ROLE_ICON_STYLES
    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = EllesmereUI.UnitEffectiveRole("player")
    local roleStyleValues = {
        none          = "None",
        modern        = "Modern",
        modernCircle  = "Modern Circle",
        styled        = "Styled",
        classicCircle = "Classic Circle",
        classic       = "Classic",
        blizzDefault  = "Blizz Default",
        -- Key stays "blizzLight" so saved roleIconStyle values resolve; only the display label reads "Modern Light".
        blizzLight    = "Modern Light",
        pixels        = "Pixels",
        _menuOpts = {
            icon = function(key)
                local map = RI_STYLES[key]
                if not map or not playerRole or map[playerRole] == nil then return nil end
                if map._isTexture then return map[playerRole] end
                return nil
            end,
            iconAtlas = function(key)
                local map = RI_STYLES[key]
                if not map or not playerRole or map[playerRole] == nil then return nil end
                if not map._isTexture then return map[playerRole] end
                return nil
            end,
        },
    }
    local roleStyleOrder = { "none", "modern", "blizzLight", "pixels", "modernCircle", "styled", "classicCircle", "classic", "blizzDefault" }
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Role Icons", values=roleStyleValues, order=roleStyleOrder,
          getValue=function() return SVal("roleIconStyle", "modern") end,
          setValue=function(v) SSet("roleIconStyle", v); EllesmereUI:RefreshPage() end },
        { type="dropdown", text="Show Role",
          disabled=function() return SVal("roleIconStyle", "modern") == "none" end,
          disabledTooltip="Role Icons",
          values={ __placeholder = "All Roles" }, order={ "__placeholder" },
          getValue=function() return "__placeholder" end,
          setValue=function() end });  y = y - h
    -- Right side placeholder dropdown is swapped for a checkbox dropdown.
    if not EllesmereUI._prebuilding then
        local rightRgn = row._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end
        local showRoleItems = {
            { key = "tank",   label = "Tank" },
            { key = "healer", label = "Healer" },
            { key = "dps",    label = "DPS" },
        }
        local roleKeyMap = { tank = "showRoleForTank", healer = "showRoleForHealer", dps = "showRoleForDPS" }
        local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 170, rightRgn:GetFrameLevel() + 2,
            showRoleItems,
            function(k) return SVal(roleKeyMap[k], true) end,
            function(k, v)
                SSet(roleKeyMap[k], v)
            end)
        PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil
    end
    do
        local rgn = row._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Role Icons",
            rows = {
                { type="toggle", label="Hide In Combat",
                  tooltip="Hide role icons while you are in combat.",
                  get=function() return SVal("roleIconHideInCombat", false) end,
                  set=function(v) SSet("roleIconHideInCombat", v); if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end end },
                { type="toggle", label="Show Behind Border",
                  tooltip="Draw role icons behind the frame border, including the hover and target highlight.",
                  get=function() return SVal("roleIconBehindBorder", false) end,
                  set=function(v) SSet("roleIconBehindBorder", v) end },
            },
        })
    end
    local rolePositionValues = {
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local rolePositionOrder = EllesmereUI.POSITION_GRID_ORDER
    local roleRow2
    -- Party Frames kit: role, ready check and leader take the stock spots
    -- (their offset cogs stay live).
    roleRow2, h = W:DualRow(parent, y,
        ns.RF_PartyKitGate({ type="dropdown", text="Role Position", values=rolePositionValues, order=rolePositionOrder,
          disabled=function() return SVal("roleIconStyle", "modern") == "none" end,
          disabledTooltip="Role Icons",
          getValue=function() return SVal("roleIconPosition", "bottomleft") end,
          setValue=function(v) SSet("roleIconPosition", v) end }),
        { type="slider", text="Role Icon Size", min=8, max=30, step=1,
          disabled=function() return SVal("roleIconStyle", "modern") == "none" end,
          disabledTooltip="Role Icons",
          getValue=function() return SVal("roleIconSize", 14) end,
          setValue=function(v) SSet("roleIconSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = roleRow2._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Role Icon Offset",
            rows = {
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("roleIconOffsetX", 0) end,
                  set=function(v) SSet("roleIconOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("roleIconOffsetY", 0) end,
                  set=function(v) SSet("roleIconOffsetY", v) end },
            },
        })
    end

    local markerPositionValues = {
        none        = "None",
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local markerPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Marker Position", values=markerPositionValues, order=markerPositionOrder,
          getValue=function()
              if not SVal("showRaidMarker", true) then return "none" end
              return SVal("raidMarkerPosition", "center")
          end,
          setValue=function(v)
              if v == "none" then
                  SSet("showRaidMarker", false)
              else
                  SWrite("showRaidMarker", true)
                  SSet("raidMarkerPosition", v)
              end
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Marker Size", min=8, max=40, step=1,
          disabled=function() return not SVal("showRaidMarker", true) end,
          disabledTooltip="Marker Position",
          getValue=function() return SVal("raidMarkerSize", 16) end,
          setValue=function(v) SSet("raidMarkerSize", v) end });  y = y - h

    do
        local rgn = row._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Marker Offset",
            rows = {
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("raidMarkerOffsetX", 0) end,
                  set=function(v) SSet("raidMarkerOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("raidMarkerOffsetY", 0) end,
                  set=function(v) SSet("raidMarkerOffsetY", v) end },
            },
        })
    end

    -- Rows below Marker Position are the less-common indicators. The RAID tab collapses them behind the shared session expander (BuildLessCommonExpander in EllesmereUI_Widgets_RowAddons.lua); the party tab always shows them.
    local lessCommonOpen = true
    if not optState._partyCtx then
        lessCommonOpen, y = EllesmereUI.BuildLessCommonExpander(parent, y,
            "rfIndicators", "Show Less Common Indicator Options")
    end
    if lessCommonOpen then

    -- The three indicators share a single texture, so one position + size control set drives all of them.
    local readyCheckPositionValues = {
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local readyCheckPositionOrder = EllesmereUI.POSITION_GRID_ORDER
    local rcRow
    rcRow, h = W:DualRow(parent, y,
        ns.RF_PartyKitGate({ type="dropdown", text="Ready Check / Summon / Rez", values=readyCheckPositionValues, order=readyCheckPositionOrder,
          getValue=function() return SVal("readyCheckPosition", "center") end,
          setValue=function(v) SSet("readyCheckPosition", v) end }),
        { type="slider", text="Icon Size", min=8, max=40, step=1,
          getValue=function() return SVal("readyCheckSize", 20) end,
          setValue=function(v) SSet("readyCheckSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = rcRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Ready Check / Summon / Rez",
            rows = {
                { type="toggle", label="Show Ready Check",
                  get=function() return SVal("showReadyCheck", true) end,
                  set=function(v) SSet("showReadyCheck", v) end },
                { type="toggle", label="Show Incoming Summon",
                  get=function() return SVal("showSummonPending", true) end,
                  set=function(v) SSet("showSummonPending", v) end },
                { type="toggle", label="Show Incoming Resurrection",
                  get=function() return SVal("showIncomingRez", true) end,
                  set=function(v) SSet("showIncomingRez", v) end },
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("readyCheckOffsetX", 0) end,
                  set=function(v) SSet("readyCheckOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("readyCheckOffsetY", 0) end,
                  set=function(v) SSet("readyCheckOffsetY", v) end },
            },
        })
    end

    local statusTextPositionValues = {
        none        = "None",
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local statusTextPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
    local stRow
    stRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Status Text", values=statusTextPositionValues, order=statusTextPositionOrder,
          getValue=function() return SVal("statusTextPosition", "center") end,
          setValue=function(v) SSet("statusTextPosition", v) end },
        { type="slider", text="Text Size", min=6, max=30, step=1,
          getValue=function() return SVal("statusTextSize", 14) end,
          setValue=function(v) SSet("statusTextSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = stRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Status Text",
            rows = {
                { type="toggle", label="Show AFK",
                  get=function() return SVal("statusShowAFK", false) end,
                  set=function(v) SSet("statusShowAFK", v); ReloadAndUpdate() end },
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("statusTextOffsetX", 0) end,
                  set=function(v) SSet("statusTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("statusTextOffsetY", 0) end,
                  set=function(v) SSet("statusTextOffsetY", v) end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = stRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, stRow:GetFrameLevel() + 3,
            function()
                local c = SGet("statusTextColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b)
                SWrite("statusTextColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
    end

    local leaderPositionValues = {
        none        = "None",
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local leaderPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
    -- (The dropdown is also the leader icon's on/off switch, so under the
    -- kit it keeps that job: shown at the stock spot, or None.)
    row, h = W:DualRow(parent, y,
        ns.RF_OptPartyKit() and { type="dropdown", text="Leader Icon",
          values={ kit = "Party Frame", none = "None" }, order={ "kit", "none" },
          getValue=function() return SVal("showLeaderIcon", false) and "kit" or "none" end,
          setValue=function(v)
              SSet("showLeaderIcon", v ~= "none")
              EllesmereUI:RefreshPage()
          end }
        or { type="dropdown", text="Leader Icon", values=leaderPositionValues, order=leaderPositionOrder,
          getValue=function()
              if not SVal("showLeaderIcon", false) then return "none" end
              return SVal("leaderIconPosition", "top")
          end,
          setValue=function(v)
              if v == "none" then
                  SSet("showLeaderIcon", false)
              else
                  SWrite("showLeaderIcon", true)
                  SSet("leaderIconPosition", v)
              end
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Leader Icon Size", min=8, max=30, step=1,
          disabled=function() return not SVal("showLeaderIcon", false) end,
          disabledTooltip="Leader Icon",
          getValue=function() return SVal("leaderIconSize", 14) end,
          setValue=function(v) SSet("leaderIconSize", v) end });  y = y - h
    do
        local rgn = row._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Leader Icon",
            rows = {
                { type="toggle", label="Show In Combat",
                  tooltip="Show the leader/assistant icon while you are in combat. Disable to hide it during combat.",
                  get=function() return SVal("showLeaderIconInCombat", true) end,
                  set=function(v) SSet("showLeaderIconInCombat", v); if ns._UpdateLeaderIcons then ns._UpdateLeaderIcons() end end },
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("leaderIconOffsetX", 0) end,
                  set=function(v) SSet("leaderIconOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("leaderIconOffsetY", 0) end,
                  set=function(v) SSet("leaderIconOffsetY", v) end },
            },
        })
    end

    -- Combat Icon Position ("None" disables) | Combat Icon Size; shows on members currently in combat. Style/color/offset live in the inline cog.
    local combatPositionValues = {
        none        = "None",
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local combatPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
    local combatStyleValues = {
        standard = "Standard",
        class    = "Class Theme",
        combat0  = "Arcade",
        combat1  = "Dungeoneer",
        combat2  = "Classic",
        combat3  = "Cross",
        combat4  = "Circle",
        combat5  = "Square",
    }
    local combatStyleOrder = { "standard", "class", "combat0", "combat1", "combat2", "combat3", "combat4", "combat5" }
    local ciRow
    ciRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Combat Icon", values=combatPositionValues, order=combatPositionOrder,
          getValue=function()
              if not SVal("showCombatIndicator", false) then return "none" end
              return SVal("combatIndicatorPosition", "right")
          end,
          setValue=function(v)
              if v == "none" then
                  SSet("showCombatIndicator", false)
              else
                  SWrite("showCombatIndicator", true)
                  SSet("combatIndicatorPosition", v)
              end
              if ns._UpdateCombatIcons then ns._UpdateCombatIcons() end
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Combat Icon Size", min=8, max=40, step=1,
          disabled=function() return not SVal("showCombatIndicator", false) end,
          disabledTooltip="Combat Icon",
          getValue=function() return SVal("combatIndicatorSize", 16) end,
          setValue=function(v) SSet("combatIndicatorSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = ciRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Combat Icon",
            rows = {
                { type="dropdown", label="Style", values=combatStyleValues, order=combatStyleOrder,
                  get=function() return SVal("combatIndicatorStyle", "standard") end,
                  set=function(v) SSet("combatIndicatorStyle", v); if ns._UpdateCombatIcons then ns._UpdateCombatIcons() end end },
                { type="toggle", label="Class Colored",
                  tooltip="Tint the combat icon by the member's class color. Not available for the Arcade/Dungeoneer/Classic/Cross/Circle/Square styles.",
                  disabled=function()
                      local st = SVal("combatIndicatorStyle", "standard")
                      return st:find("^combat%d") and true or false
                  end,
                  disabledTooltip="Not available for this combat icon style.", rawTooltip=true,
                  get=function() return SVal("combatIndicatorColor", "custom") == "classcolor" end,
                  set=function(v) SSet("combatIndicatorColor", v and "classcolor" or "custom"); if ns._UpdateCombatIcons then ns._UpdateCombatIcons() end end },
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("combatIndicatorOffsetX", 0) end,
                  set=function(v) SSet("combatIndicatorOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("combatIndicatorOffsetY", 0) end,
                  set=function(v) SSet("combatIndicatorOffsetY", v) end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = ciRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, ciRow:GetFrameLevel() + 3,
            function()
                local c = SGet("combatIndicatorCustomColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 0.2, 0.2, 1
            end,
            function(r, g, b)
                SWrite("combatIndicatorCustomColor", { r=r, g=g, b=b })
                if ns._UpdateCombatIcons then ns._UpdateCombatIcons() end
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
    end

    -- Show Group Numbers | Number Size (+ alpha swatch). Raid only: party has no groups. Size + color also drive the always-on preview group labels; the toggle gates only the real frames.
    if not optState._partyCtx then
        local gnRow
        gnRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Group Numbers",
              getValue=function() return SVal("showGroupNumbers", false) end,
              setValue=function(v) SSet("showGroupNumbers", v) end },
            { type="slider", text="Number Size", min=6, max=30, step=1,
              getValue=function() return SVal("groupNumberSize", 10) end,
              setValue=function(v) SSet("groupNumberSize", v) end });  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = gnRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, gnRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("groupNumberColor")
                    if c then return c.r, c.g, c.b, c.a or 0.75 end
                    return 1, 1, 1, 0.75
                end,
                function(r, g, b, a)
                    SWrite("groupNumberColor", { r=r, g=g, b=b, a=a })
                    ReloadAndUpdate()
                end, true, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end
        if not EllesmereUI._prebuilding then
            local rgn = gnRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Group Number Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("groupNumberOffsetX", 0) end,
                      set=function(v) SSet("groupNumberOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("groupNumberOffsetY", 0) end,
                      set=function(v) SSet("groupNumberOffsetY", v) end },
                },
            })
        end
    end

    -- Ping Marker | Ping Marker Size (+ offset cog). The mark a group member's ping
    -- puts on the pinged unit's frame, Blizzard's own art. Also needs Blizzard's
    -- "Show Pings on Raid Frames" setting on (same gate as the default frames).
    local pingPositionValues = {
        none        = "None",
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local pingPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
    local pingRow
    pingRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Ping Marker", values=pingPositionValues, order=pingPositionOrder,
          tooltip="Shows the ping mark on a member's frame when someone pings them (needs Blizzard's Show Pings on Raid Frames setting on).",
          getValue=function()
              if not SVal("showPingMarker", true) then return "none" end
              return SVal("pingMarkerPosition", "center")
          end,
          setValue=function(v)
              if v == "none" then
                  SSet("showPingMarker", false)
              else
                  SWrite("showPingMarker", true)
                  SSet("pingMarkerPosition", v)
              end
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Ping Marker Size", min=10, max=60, step=1,
          disabled=function() return not SVal("showPingMarker", true) end,
          disabledTooltip="Ping Marker",
          getValue=function() return SVal("pingMarkerSize", 30) end,
          setValue=function(v) SSet("pingMarkerSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = pingRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Ping Marker Offset",
            rows = {
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("pingMarkerOffsetX", 0) end,
                  set=function(v) SSet("pingMarkerOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("pingMarkerOffsetY", 0) end,
                  set=function(v) SSet("pingMarkerOffsetY", v) end },
            },
        })
    end
    end   -- close the less-common-indicators collapse wrapper
    -- While expanded the shared link re-renders here in its "Hide ..." form; no-op while collapsed or in party ctx.
    if not optState._partyCtx then
        y = EllesmereUI.FinishLessCommonExpander(parent, y,
            "rfIndicators", "Show Less Common Indicator Options")
    end

    -------------------------------------------------------------------
    --  DISPELS
    -------------------------------------------------------------------
    local dispelHeader
    if onSection then onSection("indicators", _secY, y) end; _secY = y
    dispelHeader, h = W:SectionHeader(parent, "DISPELS", y); y = y - h

    -- Eyeball: toggle dispel visibility on preview (raid + party)
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON

        local dispLabel
        for _, rgn in ipairs({ dispelHeader:GetRegions() }) do
            if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "DISPELS" then
                dispLabel = rgn; break
            end
        end
        local eyeBtn = CreateFrame("Button", nil, dispelHeader)
        eyeBtn:SetSize(24, 24)
        if dispLabel then
            eyeBtn:SetPoint("LEFT", dispLabel, "RIGHT", 5, 0)
        else
            eyeBtn:SetPoint("LEFT", dispelHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeBtn:SetFrameLevel(dispelHeader:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()

        if ns._dispelsVisible == nil then ns._dispelsVisible = false end

        local function RefreshDispelEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                eyeBtn:SetAlpha(0.15)
                return
            end
            eyeTex:SetTexture(ns._dispelsVisible and EYE_INVISIBLE or EYE_VISIBLE)
            eyeBtn:SetAlpha(0.4)
        end
        EYE.refreshDispelEye = RefreshDispelEye
        RefreshDispelEye()
        eyeBtn:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            ns._dispelsVisible = not ns._dispelsVisible
            -- Dispels and indicators are mutually exclusive.
            if ns._dispelsVisible then
                if ns._indicatorsVisible then
                    ns._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                end
            end
            RefreshDispelEye()
            if ns.PvRefresh then ns.PvRefresh() end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, ns._dispelsVisible and "Hide dispels on preview" or "Show dispels on preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then self:SetAlpha(0.4) end
            EllesmereUI.HideWidgetTooltip()
        end)
    end  -- close do (dispels eyeball)

    local dispelOverlayValues = {
        none     = "None",
        fill     = "Fill Overlay",
        full     = "Full Overlay",
        gradient = "Gradient Overlay",
        gradient_sharp = "Gradient Sharp",
    }
    local dispelOverlayOrder = { "none", "fill", "full", "gradient", "gradient_sharp" }

    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Dispel Overlay", values=dispelOverlayValues, order=dispelOverlayOrder,
          getValue=function() return SVal("dispelOverlay", "fill") end,
          setValue=function(v) SSet("dispelOverlay", v); EllesmereUI:RefreshPage() end },
        { type="slider", text="Overlay Opacity", min=5, max=100, step=1,
          disabled=function() return SVal("dispelOverlay", "fill") == "none" end,
          disabledTooltip="Dispel Overlay",
          getValue=function() return SVal("dispelOverlayOpacity", 100) end,
          setValue=function(v) SSet("dispelOverlayOpacity", v) end });  y = y - h


    local dispelIconPositionValues = {
        none        = "None",
        topleft     = "Top Left",
        top         = "Top",
        topright    = "Top Right",
        left        = "Left",
        center      = "Center",
        right       = "Right",
        bottomleft  = "Bottom Left",
        bottom      = "Bottom",
        bottomright = "Bottom Right",
    }
    local dispelIconPositionOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
    row, h = W:DualRow(parent, y,
        { type="slider", text="Frame Border", min=0, max=4, step=1,
          getValue=function() return SVal("dispelBorderSize", 2) end,
          setValue=function(v) SSet("dispelBorderSize", v) end },
        { type="dropdown", text="Type Icon Position", values=dispelIconPositionValues, order=dispelIconPositionOrder,
          getValue=function()
              if not SVal("showDispelIcons", false) then return "none" end
              return SVal("dispelIconPosition", "center")
          end,
          setValue=function(v)
              if v == "none" then
                  SSet("showDispelIcons", false)
              else
                  SSet("showDispelIcons", true)
                  SSet("dispelIconPosition", v)
              end
              EllesmereUI:RefreshPage()
          end });  y = y - h
    do
        local rgn = row._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = function() return not SVal("showDispelIcons", false) end,
            disabledTooltip = "This option requires a Type Icon Position other than None",
            title = "Dispel Icon",
            rows = {
                { type="slider", label="Icon Size", min=8, max=48, step=1,
                  get=function() return SVal("dispelIconSize", 16) end,
                  set=function(v) SSet("dispelIconSize", v) end },
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("dispelIconOffsetX", 0) end,
                  set=function(v) SSet("dispelIconOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("dispelIconOffsetY", 0) end,
                  set=function(v) SSet("dispelIconOffsetY", v) end },
            },
        })
    end
    -- Cog on the Dispel Border slider: thickness in physical pixels of the engine-tinted dispel ring on dispellable debuff ICONS,
    -- and Color Custom Borders (the frame's own border copied in the dispel type color).
    if not EllesmereUI._prebuilding then
        local rgn = row._leftRegion
        local function CompactDispelBorder()
            if optState._partyCtx then return ns.RF_PartySharedBorderOn(ns._scaledPartyProxy) end
            return ns.RF_RaidSharedBorderOn(db.profile)
        end
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Dispel Border",
            rows = {
                { type="slider", label="Debuff Icon Border", min=-1, max=4, step=1,
                  tooltip="Thickness in physical pixels. -1 follows the Debuff Manager's Border setting, 0 hides the dispel color border.",
                  get=function() return SVal("dispelIconBorderSize", 2) end,
                  set=function(v) SSet("dispelIconBorderSize", v) end },
                { type="toggle", label="Color Custom Borders",
                  tooltip="Recolors the frame border in the dispel type color while a debuff of that type is shown.",
                  disabled=function() return CompactDispelBorder() or CustomBorderOff() end,
                  disabledTooltip=function()
                      if CompactDispelBorder() then return "This option is unavailable while Compact Mode is active." end
                      return CustomBorderOffTip()
                  end,
                  requireState="disabled",
                  get=function() return SVal("dispelCustomBorder", false) end,
                  set=function(v) SSet("dispelCustomBorder", v) end },
            },
        })
    end

    -- Dispel Colors: five always-active swatches, one per type. Unlike Name Color (a mode picker) each is independently editable, so no onClick/refreshAlpha -- the default click opens the picker.
    _, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Dispel Colors",
          -- Per-type alpha 0 hides that type's border/overlay entirely.
          swatches = {
            { tooltip = "Magic", hasAlpha = true,
              getValue = function() local c = SGet("dispelColorMagic"); if c then return c.r, c.g, c.b, c.a or 1 end return 0.354, 0.396, 0.74, 1 end,
              setValue = function(r, g, b, a) SWrite("dispelColorMagic", { r=r, g=g, b=b, a=a or 1 }); ReloadAndUpdate() end },
            { tooltip = "Curse", hasAlpha = true,
              getValue = function() local c = SGet("dispelColorCurse"); if c then return c.r, c.g, c.b, c.a or 1 end return 0.636, 0.0, 0.64, 1 end,
              setValue = function(r, g, b, a) SWrite("dispelColorCurse", { r=r, g=g, b=b, a=a or 1 }); ReloadAndUpdate() end },
            { tooltip = "Disease", hasAlpha = true,
              getValue = function() local c = SGet("dispelColorDisease"); if c then return c.r, c.g, c.b, c.a or 1 end return 0.71, 0.379, 0.0, 1 end,
              setValue = function(r, g, b, a) SWrite("dispelColorDisease", { r=r, g=g, b=b, a=a or 1 }); ReloadAndUpdate() end },
            { tooltip = "Poison", hasAlpha = true,
              getValue = function() local c = SGet("dispelColorPoison"); if c then return c.r, c.g, c.b, c.a or 1 end return 0.052, 0.586, 0.62, 1 end,
              setValue = function(r, g, b, a) SWrite("dispelColorPoison", { r=r, g=g, b=b, a=a or 1 }); ReloadAndUpdate() end },
            { tooltip = "Bleed", hasAlpha = true,
              getValue = function() local c = SGet("dispelColorBleed"); if c then return c.r, c.g, c.b, c.a or 1 end return 0.75, 0.15, 0.15, 1 end,
              setValue = function(r, g, b, a) SWrite("dispelColorBleed", { r=r, g=g, b=b, a=a or 1 }); ReloadAndUpdate() end },
          } },
        { type="toggle", text="Only Show Dispellable",
          -- Inverse of dispelShowAll: ON = only-mine (dispelShowAll=false).
          getValue=function() return not SVal("dispelShowAll", true) end,
          setValue=function(v) SSet("dispelShowAll", not v) end });  y = y - h

    if onSection then onSection("dispels", _secY, y) end; _secY = y

    -- Party Frames kit: the stock frame has no Top Name Bar (the whole
    -- section, its sync overlay included, is skipped on the Party page).
    if not ns.RF_OptPartyKit() then
    -------------------------------------------------------------------
    --  TOP NAME BAR
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TOP NAME BAR", y); y = y - h

    local function TNBOff() return not SVal("topNameBarEnabled", false) end

    -- Enable Top Name Bar | Height. The master toggle HIDES the dependent rows while off; SectionToggleSetValue forces that rebuild.
    row, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Top Name Bar",
          getValue=function() return SVal("topNameBarEnabled", false) end,
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              SSet("topNameBarEnabled", v)
          end) },
        TNBOff() and { type="label", text="" } or
        { type="slider", text="Height", min=8, max=40, step=1,
          getValue=function() return SVal("topNameBarHeight", 20) end,
          setValue=function(v) SSet("topNameBarHeight", v) end });  y = y - h

    if not TNBOff() and not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._rightRegion, {
            disabled=function()
                local key = SGet("borderTexture")
                return TNBOff() or EllesmereUI.BlizzStyle.Get("raidframes")
                    or (key ~= "pixels" and key ~= "pixels-textured")
            end,
            disabledTooltip=function() return TNBOff() and "Enable Top Name Bar" or "Pixels or Pixels Textured Border Style" end,
            title="Top Name Bar Options",
            rows={
                { type="toggle", label="Divider",
                  tooltip="Draw a separator matching the frame's Pixels style, size, color and transparency. Hidden below Height 4.",
                  get=function() return SVal("topNameBarDivider", false) end,
                  set=function(v) SSet("topNameBarDivider", v) end },
                { type="toggle", label="Match Highlight Colors",
                  tooltip="Divider follows the frame border's highlight colors and transparency, including hover and target. When off, it keeps the normal frame border color.",
                  disabled=function() return not SVal("topNameBarDivider", false) end,
                  disabledTooltip="Requires Divider.",
                  rawTooltip=true,
                  get=function() return SVal("topNameBarDividerMatchColor", false) end,
                  set=function(v) SSet("topNameBarDividerMatchColor", v) end },
            },
        })
    end

    if not TNBOff() then
    local tnbRow2
    tnbRow2, h = W:DualRow(parent, y,
        { type="slider", text="Background", min=0, max=100, step=1,
          getValue=function() return SVal("topNameBarBgOpacity", 80) end,
          setValue=function(v) SSet("topNameBarBgOpacity", v) end },
        { type="slider", text="Text Size", min=6, max=30, step=1,
          getValue=function() return SVal("topNameBarTextSize", 11) end,
          setValue=function(v) SSet("topNameBarTextSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = tnbRow2._leftRegion
        local bgSwatch = EllesmereUI.BuildColorSwatch(
            rgn, tnbRow2:GetFrameLevel() + 3,
            function()
                local c = SGet("topNameBarBgColor")
                if c then return c.r, c.g, c.b, 1 end
                return 17/255, 17/255, 17/255, 1
            end,
            function(r, g, b)
                SWrite("topNameBarBgColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgSwatch
    end
    do
        local rgn = tnbRow2._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Text Offset",
            rows = {
                { type="slider", label="Offset X", min=-50, max=50, step=1,
                  get=function() return SVal("topNameBarTextOffsetX", 0) end,
                  set=function(v) SSet("topNameBarTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-50, max=50, step=1,
                  get=function() return SVal("topNameBarTextOffsetY", 0) end,
                  set=function(v) SSet("topNameBarTextOffsetY", v) end },
            },
        })
    end

    -- Align dropdown plus a custom/class swatch pair that doubles as the color-mode selector (as with Health Text). Defaults to class.
    local tnbRow3
    tnbRow3, h = W:DualRow(parent, y,
        { type="dropdown", text="Alignment & Color",
          values={ center="Center", left="Left", right="Right" },
          order={ "center", "left", "right" },
          getValue=function() return SVal("topNameBarTextAlign", "center") end,
          setValue=function(v) SSet("topNameBarTextAlign", v) end },
        { type="toggle", text="Show on Bottom",
          tooltip="Places the bar at the bottom of the frame instead of the top.",
          getValue=function() return SVal("topNameBarBottom", false) end,
          setValue=function(v) SSet("topNameBarBottom", v) end });  y = y - h
    -- Custom rightmost (opens picker), class leftmost. Clicking switches topNameBarTextColorMode; the inactive one dims. Custom is added FIRST so it sits next to the dropdown.
    if not EllesmereUI._prebuilding then
        local rgn = tnbRow3._leftRegion
        local function AddTNBSwatch(getColor, setColor, mode, opensPicker, tooltip)
            local sw = EllesmereUI.BuildColorSwatch(
                rgn, tnbRow3:GetFrameLevel() + 3, getColor, setColor, false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = sw
            sw._eabOrigClick = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self)
                if SVal("topNameBarTextColorMode", "class") ~= mode then
                    SSet("topNameBarTextColorMode", mode)
                    EllesmereUI:RefreshPage()
                    return
                end
                if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
            end)
            if tooltip then
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tooltip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            local function vis()
                sw:SetAlpha(SVal("topNameBarTextColorMode", "class") == mode and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(vis); vis()
        end
        -- Custom (rightmost): editable, opens the picker when active.
        AddTNBSwatch(
            function()
                local c = SGet("topNameBarTextColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b)
                SWrite("topNameBarTextColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, "custom", true, "Custom Color")
        AddTNBSwatch(
            function()
                local _, ct = UnitClass("player")
                if ct and RAID_CLASS_COLORS[ct] then
                    local cc = RAID_CLASS_COLORS[ct]
                    return cc.r, cc.g, cc.b, 1
                end
                return 1, 1, 1, 1
            end,
            function() end, "class", false, "Class Color")
    end
    end   -- close Top Name Bar hidden-while-disabled gate

    if onSection then onSection("topNameBar", _secY, y) end
    end   -- not Party Frames kit
    _secY = y

    -------------------------------------------------------------------
    --  FRIENDLY BOSS FRAMES (raid tab only)
    -------------------------------------------------------------------
    if not optState._partyCtx then
        _, h = W:SectionHeader(parent, "FRIENDLY BOSS FRAMES", y); y = y - h

        local function FBSet()
            local p = db.profile
            if not p.friendlyBoss then
                p.friendlyBoss = { display = "never", position = "right" }
            end
            return p.friendlyBoss
        end
        -- Everything below the display dropdown is inert while "Never".
        local function FBEnabled()
            return (FBSet().display or "never") ~= "never"
        end
        local FB_DISABLED_TIP = "This option requires Add Friendly Boss Group to be set to Healers or Always."

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Add Friendly Boss Group",
              values = { never="Never", healers="Healers", always="Always" },
              order  = { "never", "healers", "always" },
              getValue = function() return FBSet().display or "never" end,
              -- Rows below are HIDDEN while Never; only the Never <-> enabled flip forces the full rebuild.
              setValue = EllesmereUI.DependentSetValue(FBEnabled, function(v)
                  FBSet().display = v
                  ns.FB_Apply()
                  EllesmereUI:RefreshPage()
              end) },
            (not FBEnabled()) and { type="label", text="" } or
            { type="dropdown", text="Position",
              values = { left="Before First Group", right="After Last Group", free="Free Move" },
              order  = { "left", "right", "free" },
              getValue = function() return FBSet().position or "right" end,
              setValue = function(v)
                  FBSet().position = v
                  if v ~= "free" then ns.FB_SetMoverShown(false) end
                  ns.FB_Apply()
                  EllesmereUI:RefreshPage()
              end }); y = y - h
        -- Inline cog on the display dropdown: Show in Dungeons (opt-in;
        -- the group gate is raid-only without it). Dimmed while Never,
        -- like every row below the dropdown.
        if not EllesmereUI._prebuilding then
            local rgn = row._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = function() return not FBEnabled() end, disabledTooltip = FB_DISABLED_TIP,
                title = "Friendly Boss Group",
                rows = {
                    { type="toggle", label="Show in Dungeons",
                      get=function() return FBSet().showInDungeons == true end,
                      set=function(v)
                          -- Absent = off (additive key); FB_Apply re-registers
                          -- the secure group driver, so the flip is live.
                          FBSet().showInDungeons = v and true or nil
                          ns.FB_Apply()
                      end },
                },
            })
        end
        if FBEnabled() then
        -- Free Move Position: label left, Move Frames button right (Free Move only). Right slot: Boss Health Color.
        row, h = W:DualRow(parent, y,
            { type="label", text="Free Move Position" },
            { type="label", text="Boss Health Color" }); y = y - h
        do
            local btn = ns.RF_OptMoveFramesButton(row, row._leftRegion, {
                isShown = ns.FB_IsMoverShown, setShown = ns.FB_SetMoverShown,
                allowed = function()
                    return FBEnabled() and (FBSet().position == "free") and not InCombatLockdown()
                end,
                enabled = FBEnabled, enabledTip = FB_DISABLED_TIP,
            })
            EllesmereUI.BuildInlineCog(row, {
                anchorTo = btn, chain = false,
                disabled = function() return not (FBEnabled() and FBSet().position == "free") end,
                disabledTooltip = "This option requires Position to be set to Free Move",
                title = "Free Move Options",
                rows = {
                    { type="toggle", label="Horizontal Frames",
                      get=function() return FBSet().freeHorizontal == true end,
                      set=function(v)
                          FBSet().freeHorizontal = v
                          ns.FB_Apply()
                          -- Resize/reposition the drag overlay if it is up.
                          if ns.FB_IsMoverShown() then ns.FB_SetMoverShown(true) end
                      end },
                },
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = row._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local c = FBSet().healthColor
                    if c then return c.r, c.g, c.b, 1 end
                    return 23/255, 172/255, 49/255, 1
                end,
                function(r, g, b)
                    FBSet().healthColor = { r=r, g=g, b=b }
                    ns.FB_Apply()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
            rgn._lastInline = swatch
            -- Dimming alone leaves the swatch clickable; this blocks it.
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, FB_DISABLED_TIP)
            end)
            swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateFBSwatch()
                local on = FBEnabled()
                swatch:SetAlpha(on and 1 or 0.3)
                swatchBlock:SetShown(not on)
                if rgn._label then rgn._label:SetAlpha(on and 1 or 0.3) end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateFBSwatch)
            UpdateFBSwatch()
        end

        -- Row 3: size offset on top of the shared raid frame size
        row, h = W:DualRow(parent, y,
            { type="slider", text="Extra Width", min=-50, max=100, step=1,
              tooltip="Widens or narrows the boss frames relative to the raid frame size.",
              getValue = function() return FBSet().extraWidth or 0 end,
              setValue = function(v)
                  FBSet().extraWidth = v
                  ns.FB_Apply()
                  if ns.FB_IsMoverShown() then ns.FB_SetMoverShown(true) end
              end },
            { type="slider", text="Extra Height", min=-50, max=100, step=1,
              tooltip="Makes the boss frames taller or shorter relative to the raid frame size.",
              getValue = function() return FBSet().extraHeight or 0 end,
              setValue = function(v)
                  FBSet().extraHeight = v
                  ns.FB_Apply()
                  if ns.FB_IsMoverShown() then ns.FB_SetMoverShown(true) end
              end }); y = y - h
        end   -- close Friendly Boss Frames hidden-while-disabled gate

        if onSection then onSection("friendlyBossFrames", _secY, y) end; _secY = y

        -------------------------------------------------------------------
        --  EXTRA FRAMES (raid tab only)
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRA FRAMES", y); y = y - h

        local function XFSet()
            local p = db.profile
            if not p.extraFrames then
                p.extraFrames = { showTanks = false, position = "right", players = {} }
            end
            return p.extraFrames
        end
        -- Position settings only matter once something can feed the group: the tanks toggle or a bound hotkey.
        local function XFConfigured()
            return XFSet().showTanks == true
                or (EllesmereUIDB and EllesmereUIDB.extraFramesKey) ~= nil
        end
        -- Row 1: Add to Extra Group Hotkey (capture) | Show Tanks toggle
        row, h = W:DualRow(parent, y,
            { type="label", text="Add to Extra Group Hotkey" },
            { type="toggle", text="Show Tanks in Extra Group",
              tooltip="Automatically duplicates the raid's tanks into the Extra Frames group. Shares the frame cap with hotkey picks.",
              getValue = function() return XFSet().showTanks == true end,
              -- Rows below are HIDDEN while unconfigured (no tanks toggle AND no hotkey); only a configured-state flip forces the rebuild.
              setValue = EllesmereUI.DependentSetValue(XFConfigured, function(v)
                  XFSet().showTanks = v
                  ns.XF_Apply()
                  -- Feature may have just gone dark; the mover can't stay up.
                  if not XFConfigured() then ns.XF_SetMoverShown(false) end
                  EllesmereUI:RefreshPage()
              end) }); y = y - h
        -- Inline cog on Show Tanks: tank auto-include options.
        if not EllesmereUI._prebuilding then
            local rgn = row._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Show Tanks Options",
                rows = {
                    { type="toggle", label="Exclude Myself",
                      tooltip="Skips your own frame when Show Tanks duplicates the raid's tanks. Hotkey picks can still add you.",
                      get=function() return XFSet().excludeSelfTank == true end,
                      set=function(v)
                          XFSet().excludeSelfTank = v or nil
                          ns.XF_Apply()
                      end },
                },
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = row._leftRegion
            local kbBtn, refresh = EllesmereUI.BuildKeybindButton(row, {
                w = 140, h = 26, font = 13, level = 5,
                tooltip = "Left-click to set a keybind. Right-click to unbind.\nPress the key while hovering a raid frame to add or remove that player from the Extra Frames group.",
                get = function() return EllesmereUIDB and EllesmereUIDB.extraFramesKey end,
                set = function(key)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    local bindBtn = _G["ERFExtraFramesBindBtn"]
                    if bindBtn then
                        -- Override bindings cannot change in combat: keep the old key.
                        if InCombatLockdown() then return end
                        if key or EllesmereUIDB.extraFramesKey then ClearOverrideBindings(bindBtn) end
                        if key then SetOverrideBindingClick(bindBtn, true, key, "ERFExtraFramesBindBtn") end
                    end
                    local wasConfigured = XFConfigured()
                    EllesmereUIDB.extraFramesKey = key
                    -- The mover can't stay up once the feature goes dark.
                    if not XFConfigured() then ns.XF_SetMoverShown(false) end
                    -- Hidden rows below: a configured-state flip needs the full rebuild, not the fast refresh.
                    if XFConfigured() ~= wasConfigured then
                        EllesmereUI:RefreshPage(true)
                    else
                        EllesmereUI:RefreshPage()
                    end
                end,
            })
            EllesmereUI.PanelPP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
            EllesmereUI.RegisterWidgetRefresh(refresh)
        end

        -- Rows 2-4 are HIDDEN while unconfigured (no tanks toggle AND no hotkey); the triggers above rebuild when that state flips.
        if XFConfigured() then
        -- Row 2: Position | Free Move Position (Move Frames)
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Position",
              values = { left="Before First Group", right="After Last Group", free="Free Move" },
              order  = { "left", "right", "free" },
              getValue = function() return XFSet().position or "right" end,
              setValue = function(v)
                  XFSet().position = v
                  if v ~= "free" then ns.XF_SetMoverShown(false) end
                  ns.XF_Apply()
                  -- Full rebuild: the Grow/Wrap Direction row only exists while the position is Free Move.
                  EllesmereUI:RefreshPage(true)
              end },
            { type="label", text="Free Move Position" }); y = y - h
        ns.RF_OptMoveFramesButton(row, row._rightRegion, {
            isShown = ns.XF_IsMoverShown, setShown = ns.XF_SetMoverShown,
            allowed = function()
                return XFConfigured() and (XFSet().position == "free") and not InCombatLockdown()
            end,
        })

        -- Free Move ONLY (hidden otherwise; Position's setValue forces a rebuild): growth axes of the free-floating grid, with Wrap After in an inline cog on Wrap Direction.
        -- Attached positions need none of this -- they stack group-sized runs of 5 along the raid's own growth settings, like extra raid groups.
        -- Grow Direction defaults from the legacy freeHorizontal key, so existing layouts read back unchanged.
        if XFSet().position == "free" then
        local function XFGrowDir()
            local set = XFSet()
            return set.growDirection or (set.freeHorizontal and "RIGHT" or "DOWN")
        end
        local function XFReapply()
            ns.XF_Apply()
            if ns.XF_IsMoverShown() then ns.XF_SetMoverShown(true) end
        end

        -- The wrap dropdown only offers the two directions perpendicular to the primary run, so a grow change forces a full rebuild to swap its value set.
        local xfHoriz = (XFGrowDir() == "RIGHT" or XFGrowDir() == "LEFT")
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Grow Direction",
              tooltip="Direction the frames are laid out.",
              values = { DOWN="Down", UP="Up", RIGHT="Right", LEFT="Left" },
              order  = { "DOWN", "UP", "RIGHT", "LEFT" },
              getValue = XFGrowDir,
              setValue = function(v)
                  local set = XFSet()
                  set.growDirection = v
                  -- Keep the legacy key coherent for exports/older reads.
                  set.freeHorizontal = (v == "RIGHT" or v == "LEFT")
                  XFReapply()
                  EllesmereUI:RefreshPage(true)
              end },
            { type="dropdown", text="Wrap Direction",
              tooltip="Direction each new row or column stacks. Set Wrap After in the cog to enable wrapping.",
              values = xfHoriz and { DOWN="Down", UP="Up" } or { RIGHT="Right", LEFT="Left" },
              order  = xfHoriz and { "DOWN", "UP" } or { "RIGHT", "LEFT" },
              getValue = function()
                  local wd = XFSet().wrapDirection
                  if XFGrowDir() == "RIGHT" or XFGrowDir() == "LEFT" then
                      return (wd == "UP" or wd == "DOWN") and wd or "DOWN"
                  end
                  return (wd == "LEFT" or wd == "RIGHT") and wd or "RIGHT"
              end,
              setValue = function(v)
                  XFSet().wrapDirection = v
                  XFReapply()
              end }); y = y - h
        do
            local rgn = row._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Row Wrapping",
                rows = {
                    { type="slider", label="Wrap After", min=0, max=20, step=1,
                      get=function() return XFSet().wrapAfter or 0 end,
                      set=function(v)
                          XFSet().wrapAfter = v
                          XFReapply()
                      end },
                },
            })
        end
        end -- Free Move only row

        -- Row 4: size offset on top of the shared raid frame size
        row, h = W:DualRow(parent, y,
            { type="slider", text="Extra Width", min=-50, max=100, step=1,
              tooltip="Widens or narrows the extra frames relative to the raid frame size.",
              getValue = function() return XFSet().extraWidth or 0 end,
              setValue = function(v)
                  XFSet().extraWidth = v
                  ns.XF_Apply()
                  if ns.XF_IsMoverShown() then ns.XF_SetMoverShown(true) end
              end },
            { type="slider", text="Extra Height", min=-50, max=100, step=1,
              tooltip="Makes the extra frames taller or shorter relative to the raid frame size.",
              getValue = function() return XFSet().extraHeight or 0 end,
              setValue = function(v)
                  XFSet().extraHeight = v
                  ns.XF_Apply()
                  if ns.XF_IsMoverShown() then ns.XF_SetMoverShown(true) end
              end }); y = y - h
        -- Inline cog on Extra Width: Auto Resize Indicators (default on;
        -- off keeps indicators/auras at the real frames' base scale
        -- regardless of the extra frames' custom size).
        do
            local rgn = row._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Extra Frame Size",
                rows = {
                    { type="toggle", label="Auto Resize Indicators",
                      get=function() return XFSet().autoResizeIndicators ~= false end,
                      set=function(v)
                          -- nil = on (additive key, zero migration); false = off.
                          if v then XFSet().autoResizeIndicators = nil else XFSet().autoResizeIndicators = false end
                          ns.XF_Apply()
                      end },
                },
            })
        end
        end   -- close Extra Frames hidden-while-unconfigured gate

        if onSection then onSection("extraFrames", _secY, y) end; _secY = y
    end

    -------------------------------------------------------------------
    --  PET FRAMES (party and raid tabs, each with its own switch)
    -------------------------------------------------------------------
    -- Not a synced section: no onSection call, so the party tab never overlays it.
    do
        _, h = W:SectionHeader(parent, "PET FRAMES", y); y = y - h

        local function PFSet()
            local p = db.profile
            if not p.petFrames then
                p.petFrames = { position = "right" }
            end
            return p.petFrames
        end
        local tabKey = optState._partyCtx and "party" or "raid"
        local onParty = tabKey == "party"
        -- This tab's Position, Extra Width/Height and Free Move spot (it reads the shared ones
        -- until it sets its own).
        local function PFTab()
            PFSet()
            return ns.PF_View(tabKey)
        end
        local function PFEnabled()
            return PFSet()[tabKey] == true
        end
        -- Only a preview already on screen: starting one here would show the raid preview on the
        -- party tab, or a preview with Preview Mode set to None.
        local function PFRefreshPreview()
            if ns.previewActive() then ns.ShowPreview() end
            if ns.partyPvActive() then ns.ShowPartyPreview() end
        end
        -- The last row holds what the chosen position needs: the Move Frames button (Free Move)
        -- or Pet Side (Beside Owner). The other positions have none.
        local function PFPlacement()
            local p = PFTab().position
            if p == "free" or (p == "owner" and onParty) then return p end
        end
        local BLANK = EllesmereUI.BlankRowCfg

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Pets",
              tooltip="Adds your group's pets beside these frames, with their health, name, range and click-casting.",
              getValue = function() return PFEnabled() end,
              -- Rows below are HIDDEN while off; only the on/off flip forces the rebuild.
              setValue = EllesmereUI.DependentSetValue(PFEnabled, function(v)
                  PFSet()[tabKey] = v and true or false
                  ns.PF_Apply()
                  -- The Move Frames button goes with the page rebuild; the overlay can't stay up.
                  if not v and ns.PF_IsMoverShown(tabKey) then ns.PF_SetMoverShown(false) end
                  PFRefreshPreview()
                  EllesmereUI:RefreshPage()
              end) },
            (not PFEnabled()) and BLANK() or
            { type="dropdown", text="Position",
              -- Beside Owner (a pet beside each party frame) is party only.
              values = onParty
                  and { left="Before First Group", right="After Last Group", free="Free Move", owner="Beside Owner" }
                  or { left="Before First Group", right="After Last Group", free="Free Move" },
              order  = onParty and { "left", "right", "free", "owner" } or { "left", "right", "free" },
              getValue = function() return PFTab().position or "right" end,
              setValue = function(v)
                  local before = PFPlacement()
                  PFTab().position = v
                  if v ~= "free" and ns.PF_IsMoverShown(tabKey) then ns.PF_SetMoverShown(false) end
                  ns.PF_Apply()
                  PFRefreshPreview()
                  -- A new last row needs the full rebuild.
                  EllesmereUI:RefreshPage(PFPlacement() ~= before)
              end }); y = y - h

        if PFEnabled() then
        row, h = W:DualRow(parent, y,
            { type="slider", text="Extra Width", min=-50, max=100, step=1,
              tooltip="Widens or narrows the pet frames relative to the frame size.",
              getValue = function() return PFTab().extraWidth or 0 end,
              setValue = function(v)
                  PFTab().extraWidth = v
                  ns.PF_Apply()
                  ns.PF_PlaceMover(tabKey)
                  PFRefreshPreview()
              end },
            { type="slider", text="Extra Height", min=-50, max=100, step=1,
              tooltip="Makes the pet frames taller or shorter relative to the frame size.",
              getValue = function() return PFTab().extraHeight or 0 end,
              setValue = function(v)
                  PFTab().extraHeight = v
                  ns.PF_Apply()
                  ns.PF_PlaceMover(tabKey)
                  PFRefreshPreview()
              end }); y = y - h

        local placement = PFPlacement()
        if placement == "free" then
            row, h = W:DualRow(parent, y, { type="label", text="Free Move Position" }, BLANK()); y = y - h
            ns.RF_OptMoveFramesButton(row, row._leftRegion, {
                isShown = function() return ns.PF_IsMoverShown(tabKey) end,
                setShown = function(show) ns.PF_SetMoverShown(show, tabKey) end,
                allowed = function() return PFTab().position == "free" and not InCombatLockdown() end,
            })
        elseif placement == "owner" then
            -- Across the party frames' stack only: beside stacked frames, above or below
            -- horizontal ones (the other sides hold the next frame).
            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Pet Side",
                  values = { right="Right", left="Left", above="Above", below="Below" },
                  order  = { "right", "left", "above", "below" },
                  itemDisabled = function(v)
                      local across = (v == "above" or v == "below")
                      return across ~= (db.profile.partyHorizontal and true or false)
                  end,
                  itemDisabledTooltip = function(v)
                      if v == "above" or v == "below" then return "Horizontal Frames" end
                      return "This option requires Horizontal Frames to be disabled"
                  end,
                  getValue = function() return ns.PF_OwnerSide() end,
                  setValue = function(v)
                      PFSet().ownerSide = v
                      ns.PF_Apply()
                      PFRefreshPreview()
                  end },
                BLANK()); y = y - h
        end
        end
        _secY = y
    end

    -------------------------------------------------------------------
    --  RANGE & TOOLTIP
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

    -- OOR Alpha | Show Raid Frames Tooltip (dropdown + cog). The dropdown is a pure VIEW over the legacy keys: with tooltipMode unset it derives the shown option from the showTooltip toggle plus the global "show in combat" flag, so behavior only changes once the user picks.
    -- Same derive as the runtime ns._ResolveTooltipMode.
    local function CurTooltipMode()
        local m = SVal("tooltipMode", nil)
        if m ~= nil then return m end
        if SVal("showTooltip", true) == false then return "never" end
        if EllesmereUIDB and EllesmereUIDB.showUnitTooltipsInCombat then return "always" end
        return "outOfCombat"
    end
    row, h = W:DualRow(parent, y,
        { type="slider", text="Out of Range Alpha", min=10, max=100, step=1,
          getValue=function() return floor((SVal("oorAlpha", 0.4)) * 100) end,
          setValue=function(v)
              SSet("oorAlpha", v / 100)
              -- SetAlphaFromBoolean bakes the value in at call time, so already-OOR units keep the old alpha until a range re-eval.
              -- Seed all buttons so the slider takes effect now.
              if ns._RangeSeedAll then ns._RangeSeedAll() end
          end },
        { type="dropdown", text="Show Raid Frames Tooltip",
          tooltip="Controls when the tooltip appears as you hover a raid or party frame",
          values={ always="Always", outOfCombat="Out of Combat", outOfBossCombat="Out of Boss Combat", never="Never" },
          order={ "always", "outOfCombat", "outOfBossCombat", "never" },
          getValue=function() return CurTooltipMode() end,
          setValue=function(v) SSet("tooltipMode", v) end });  y = y - h
    -- Cog: buff/HoT aura-icon tooltips (Buff Manager), hidden by default and opt-in here. This is the ONLY gate on the aura tip: the dropdown's tooltip mode governs the UNIT tooltip and must NOT veto an aura tip enabled here (see ns.RaidFrameTooltipAllowed).
    if not EllesmereUI._prebuilding then
        local rgn = row._rightRegion
        local tipRows
            -- 4-state on the same key: true/nil=hidden, false=shown, "cursor"=shown at cursor, "combat"=hidden during combat.
            tipRows = {
                { type="dropdown", label="Buff Tooltips",
                  tooltip="Tooltip behavior when hovering a buff/HoT icon on a raid or party frame.",
                  values={ hidden="Hidden", shown="Shown", cursor="Shown At Cursor", combat="Hidden In Combat" },
                  order={ "hidden", "shown", "cursor", "combat" },
                  get=function()
                      local v = SVal("buffHideTooltips", true)
                      if v == false then return "shown" end
                      if v == "cursor" or v == "combat" then return v end
                      return "hidden"
                  end,
                  set=function(k)
                      local v = k
                      if k == "shown" then v = false elseif k == "hidden" then v = true end
                      SSet("buffHideTooltips", v); if ns.ReloadFrames then ns.ReloadFrames() end
                  end },
            }
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Tooltip Settings",
            rows = tipRows,
        })
    end

    -- Healer Mana Display: one mana-percent text row per group healer,
    -- riding the existing power-event plumbing (see ns.HM_Rebuild).
    local function HMS()
        local p = db.profile
        if not p.healerMana then p.healerMana = { mode = "none" } end
        return p.healerMana
    end
    local function HMRefresh()
        if ns.HM_Rebuild then ns.HM_Rebuild() end
    end
    local hmRow
    hmRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Healer Mana Display",
          tooltip="Shows a mana percentage row for every healer in your group as its own movable text display. Position it in Unlock Mode.",
          values={ none="None", party="In Party", raid="In Raid", both="In Party & Raid" },
          order={ "none", "party", "raid", "both" },
          getValue=function()
              local m = HMS().mode
              return (m == "party" or m == "raid" or m == "both") and m or "none"
          end,
          setValue=function(v)
              HMS().mode = v
              -- Re-syncs healer power-event registrations and rebuilds.
              if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
              -- Re-register unlock elements: the mover's isHidden verdict
              -- just changed, and re-registration applies it live to an
              -- open unlock session (both directions).
              if ns._RFRegisterUnlock then ns._RFRegisterUnlock() end
          end },
        { type="multiSwatch", text="Healer Mana Text Color",
          swatches = {
            { tooltip = "Custom Colored",
              getValue = function()
                  local c = HMS().color
                  return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, 1
              end,
              setValue = function(r, g, b)
                  local hm = HMS()
                  hm.color = { r = r, g = g, b = b }
                  hm.colorMode = "custom"
                  HMRefresh()
              end,
              onClick = function(self)
                  local hm = HMS()
                  if hm.colorMode == "power" then
                      hm.colorMode = "custom"
                      HMRefresh()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return (HMS().colorMode == "power") and 0.3 or 1
              end },
            { tooltip = "Power Colored",
              getValue = function()
                  -- Same resolver chain as the runtime rows: the global
                  -- custom power color first, stock mana color after.
                  local info = EllesmereUI.GetPowerColor("MANA")
                  if info then return info.r, info.g, info.b, 1 end
                  local mc = PowerBarColor and PowerBarColor.MANA
                  if mc then return mc.r, mc.g, mc.b, 1 end
                  return 0.3, 0.5, 0.85, 1
              end,
              setValue = function() end,
              onClick = function()
                  local hm = HMS()
                  hm.colorMode = "power"
                  HMRefresh()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return (HMS().colorMode == "power") and 1 or 0.3
              end },
          } }
    );  y = y - h
    -- Inline cog (text settings) + preview eyeball on the toggle
    if not EllesmereUI._prebuilding then
        local rgn = hmRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Healer Mana Display",
            rows = {
                { type="slider", label="Text Size", min=8, max=24, step=1,
                  get=function() return HMS().textSize or 12 end,
                  set=function(v) HMS().textSize = v; HMRefresh() end },
                { type="slider", label="Spacing", min=0, max=12, step=1,
                  tooltip="Vertical space between rows.",
                  get=function() return HMS().spacing or 2 end,
                  set=function(v) HMS().spacing = v; HMRefresh() end },
                { type="dropdown", label="Text Align",
                  values={ LEFT="Left", CENTER="Center", RIGHT="Right" },
                  order={ "LEFT", "CENTER", "RIGHT" },
                  get=function()
                      local a = HMS().align
                      return (a == "RIGHT" or a == "CENTER") and a or "LEFT"
                  end,
                  set=function(k) HMS().align = k; HMRefresh() end },
                { type="dropdown", label="Text Growth",
                  tooltip="Which way the rows stack as healers are added.",
                  values={ DOWN="Down", UP="Up" }, order={ "DOWN", "UP" },
                  get=function() return HMS().growth == "UP" and "UP" or "DOWN" end,
                  set=function(k) HMS().growth = k; HMRefresh() end },
                { type="toggle", label="Show Names in Raid",
                  tooltip="Shows each healer's name before the number while in a raid. In a party the display always shows numbers only.",
                  get=function() return HMS().showNames ~= false end,
                  -- if/else, NOT `v and nil or false`: that expression is
                  -- ALWAYS false (the nil arm falls through the or).
                  set=function(v)
                      if v then HMS().showNames = nil
                      else HMS().showNames = false end
                      HMRefresh()
                  end },
                { type="toggle", label="Class Colored Names",
                  get=function() return HMS().classNames ~= false end,
                  set=function(v)
                      if v then HMS().classNames = nil
                      else HMS().classNames = false end
                      HMRefresh()
                  end },
            },
        })

        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline, "LEFT", -4, 0)
        rgn._lastInline = eyeBtn
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints(); eyeTex:SetTexture(EYE_VISIBLE)
        local function RefreshHMEye()
            eyeTex:SetTexture(ns._hmPreview and EYE_INVISIBLE or EYE_VISIBLE)
        end
        eyeBtn:SetScript("OnClick", function()
            if ns.HM_SetPreview then ns.HM_SetPreview(not ns._hmPreview) end
            RefreshHMEye()
        end)
        eyeBtn:SetScript("OnEnter", function(s)
            s:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(s, ns._hmPreview and "Hide the preview" or "Preview the display at its position")
        end)
        eyeBtn:SetScript("OnLeave", function(s)
            s:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        EllesmereUI:RegisterOnHide(function()
            if ns._hmPreview and ns.HM_SetPreview then
                ns.HM_SetPreview(false)
                RefreshHMEye()
            end
        end)
    end

    -- Hide Blizzard Party Panel shares the exact global setting and apply function as the QoL toggle (EllesmereUIDB.hideBlizzardPartyFrame -> EllesmereUI._applyHideBlizzardPartyFrame); the QoL toggle is disabled while Raid Frames is loaded. Off when unset.
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Hide Blizzard Party Panel",
          tooltip="Hides the collapsed Blizzard party/raid sidebar panel on the side of the screen.",
          getValue=function() return EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame or false end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.hideBlizzardPartyFrame = v
              EllesmereUI._applyHideBlizzardPartyFrame()
          end },
        { type="multiSwatch", text="Status Colors",
          swatches = {
            { tooltip = "Offline", hasAlpha = false,
              getValue = function() local c = SGet("statusColorOffline"); if c then return c.r, c.g, c.b end return 0x66/255, 0x66/255, 0x66/255 end,
              setValue = function(r, g, b) SWrite("statusColorOffline", { r=r, g=g, b=b }); ReloadAndUpdate() end },
            { tooltip = "Dead", hasAlpha = false,
              getValue = function() local c = SGet("statusColorDead"); if c then return c.r, c.g, c.b end return 0x24/255, 0x17/255, 0x17/255 end,
              setValue = function(r, g, b) SWrite("statusColorDead", { r=r, g=g, b=b }); ReloadAndUpdate() end },
          } });  y = y - h

    -- Right-click + drag over a raid/party frame turns the camera (mouselook).
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Right Mouse Camera Unlock",
          tooltip="Allows free camera movement while holding and dragging right mouse button over raid frames. Right-click tap still opens the unit menu.",
          getValue=function() return SVal("freeRightClickCamera", false) end,
          setValue=function(v) SSet("freeRightClickCamera", v); if ns.FRCM_Refresh then ns.FRCM_Refresh() end end },
        { type="dropdown", text="Frame Strata",
          tooltip="Controls the display order of raid and party frames. Set higher to show above other elements.",
          values=EllesmereUI.FRAME_STRATA_LABELS,
          order=EllesmereUI.FRAME_STRATA_ORDER_BASE,
          getValue=function() return SVal("frameStrata", "LOW") end,
          setValue=function(v)
              -- Reload after changing strata to restore child frame levels.
              SWrite("frameStrata", v)
              if ns.ApplyFrameStrata then ns.ApplyFrameStrata() end
              ReloadAndUpdate()
          end });  y = y - h

    if onSection then onSection("rangeTooltip", _secY, y) end
    return y
end

-- Used by EUI_RaidFrames_Options.lua
ns.RFO_BuildVisualIndicators = BuildVisualIndicators
