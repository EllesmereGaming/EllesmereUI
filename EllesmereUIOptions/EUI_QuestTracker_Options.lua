if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_QuestTracker_Options.lua
--
-- Options page for the Blizzard-backed quest tracker. All legacy display,
-- font, and color options from the custom-tracker era have been removed.
-- Surviving options are: enable, visibility mode, auto-hide rules,
-- auto-accept / auto-turn-in, quest item hotkey, and skin toggles.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIQuestTracker"]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page
local EQT = ns.EQT

-- Page reuse: the frames this file builds go through the options frame pool
-- (EllesmereUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not EQT then return end

    local function DB()
        local d = _G._EQT_DB
        if d and d.profile and d.profile.questTracker then
            return d.profile.questTracker
        end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end

    local function RefreshAll()
        if EQT.RefreshStateDriver then EQT.RefreshStateDriver() end
        if EQT.UpdateVisibility   then EQT.UpdateVisibility()   end
        if EQT.RestyleAll         then EQT.RestyleAll()         end
        if EQT.ApplyBackground    then EQT.ApplyBackground()    end
        if EQT.ApplyMasterHeaderVisibility then EQT.ApplyMasterHeaderVisibility() end
    end

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PanelPP
        local y  = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true
        -- WoW Forever: our own tracker frame (latched until reload).
        local CUSTOM = ns.UseCustomTracker()

        -- Drag instructions (centered, above settings). Wrapped in a Frame so the
        -- search system collects it as an orphan and auto-hides it during search.
        do
            local fontPath = EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local infoFrame = CreateFrame("Frame", nil, parent)
            infoFrame:SetSize(parent:GetWidth() or 400, 20)
            infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 20)
            infoFrame._isSpacer = true
            local infoLabel = infoFrame:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontPath, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("CENTER")
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText(CUSTOM and EllesmereUI.L("Reposition this element within Unlock Mode")
                or EllesmereUI.L("Reposition this element within Blizzard Edit Mode"))

            -- Accent toggle beneath the label. "Force Quest Tracker on Screen" keeps
            -- the tracker clamped to the screen; clicking again ("Allow Quest Tracker
            -- to be Moved Offscreen") releases it so it can be dragged off-screen. The
            -- choice is saved in the quest tracker DB (forceOnScreen) and re-applied at
            -- load by EQT.ApplyForceOnScreen(), so it persists through reload/logout.
            -- Edit Mode is opened so the user can reposition the frame after toggling.
            local EG = EllesmereUI.ELLESMERE_GREEN
            local fosBtn = CreateFrame("Button", nil, parent)
            local fosFS = fosBtn:CreateFontString(nil, "OVERLAY")
            fosFS:SetFont(fontPath, 15, "")
            fosFS:SetTextColor(EG.r, EG.g, EG.b, 0.75)
            fosFS:SetPoint("CENTER")
            local function UpdateForceOnScreenLabel()
                local on = Cfg("forceOnScreen") == true
                fosFS:SetText(EllesmereUI.L(on and "Allow Quest Tracker to be Moved Offscreen" or "Force Quest Tracker on Screen"))
                fosBtn:SetSize(fosFS:GetStringWidth() + 12, 18)
            end
            UpdateForceOnScreenLabel()
            fosBtn:SetPoint("TOP", infoLabel, "BOTTOM", 0, -10)
            fosBtn:SetScript("OnEnter", function() fosFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            fosBtn:SetScript("OnLeave", function() fosFS:SetTextColor(EG.r, EG.g, EG.b, 0.75) end)
            fosBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                Set("forceOnScreen", not (Cfg("forceOnScreen") == true))
                if EQT.ApplyForceOnScreen then EQT.ApplyForceOnScreen() end
                UpdateForceOnScreenLabel()
                if EditModeManagerFrame and not CUSTOM then ShowUIPanel(EditModeManagerFrame) end
            end)
            y = y - 68
        end

        -- Stock styles (Blizzard Style / Classic WoW UI) keep Blizzard's own
        -- tracker art, text and quest icons: the background, font and colour
        -- rows only apply to the EllesmereUI look.
        local BS = EllesmereUI.BlizzStyle
        local STOCK = BS and BS.Get("questtracker") and not CUSTOM
        -- WoW Forever's quest tools and objective colors (none of their rows on retail).
        local FOREVER = EllesmereUI.IS_FOREVER

        -- -- CUSTOM TRACKER (WoW Forever) ------------------------------------
        if EllesmereUI.IS_FOREVER then
            _, h = W:SectionHeader(parent, "CUSTOM TRACKER", y); y = y - h
            local function Off() return not CUSTOM end

            -- Custom Quest Tracker | Group Quests by Zone. The toggle shows what
            -- the profile asks for (its own pick, else on under the EllesmereUI
            -- style alone); the tracker in use changes at the reload.
            local zoneRow
            zoneRow, h = W:DualRow(parent, y,
                { type="toggle", text="Custom Quest Tracker",
                  tooltip="Replaces Blizzard's tracker with EllesmereUI's own quest tracker, which never touches Blizzard's tracker or watch list. On by default under the EllesmereUI style. Requires a UI reload.",
                  getValue=function() return ns.CustomTrackerWanted(DB()) end,
                  setValue=function(v)
                      ns.SetCustomTrackerWanted(DB(), v)
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Switching quest trackers requires a UI reload to apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          reload      = true,
                      })
                  end },
                { type="toggle", text="Group Quests by Zone",
                  tooltip="Lists quests under their quest log zone headers. Click a zone to collapse it.",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customGroupByZone") ~= false end,
                  setValue=function(v) Set("customGroupByZone", v); RefreshAll(); EllesmereUI:RefreshPage() end })
            y = y - h

            -- Zone header colour, on the Group Quests by Zone slot: Custom
            -- Colored | Accent Colored. With no pick the headers follow the
            -- Header Color, so the lit swatch is the one they show now.
            if not EllesmereUI._prebuilding then
                local function ZoneAccent() return (select(4, EQT.CustomZoneRGB())) end
                local function PickZone(accent)
                    local was = Cfg("customZoneUseAccent")
                    Set("customZoneUseAccent", accent)
                    EQT.RefreshCustom()
                    if was ~= accent then EllesmereUI:RefreshPage() end
                end
                EllesmereUI.BuildInlineSwatches(zoneRow._rightRegion, {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function()
                          if Cfg("customZoneUseAccent") == nil and not ZoneAccent() then
                              local r, g, b = EQT.CustomZoneRGB()
                              return r, g, b
                          end
                          return Cfg("customZoneR") or 1, Cfg("customZoneG") or 1, Cfg("customZoneB") or 1
                      end,
                      setValue = function(r, g, b)
                          Set("customZoneR", r); Set("customZoneG", g); Set("customZoneB", b)
                          PickZone(false)
                      end,
                      onClick = function(self)
                          if ZoneAccent() then PickZone(false); return end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return ZoneAccent() and 0.3 or 1 end },
                    { tooltip = "Accent Colored", hasAlpha = false,
                      getValue = function() return EllesmereUI.ResolveActiveAccent() end,
                      setValue = function() end,
                      onClick = function() PickZone(true) end,
                      refreshAlpha = function() return ZoneAccent() and 1 or 0.3 end },
                }, { disabled = function() return Off() or Cfg("customGroupByZone") == false end,
                     disabledTooltip = function() return Off() and "Custom Quest Tracker" or "Group Quests by Zone" end })
            end

            -- Width | Max Height (also the mover's size rows in Unlock Mode)
            local wMin, wMax, hMin, hMax = EQT.CustomSizeRange()
            local function ApplySize()
                if EQT.SyncPosition then EQT.SyncPosition() end
            end
            _, h = W:DualRow(parent, y,
                { type="slider", text="Width",
                  min = wMin, max = wMax, step = 1,
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customWidth") or 260 end,
                  setValue=function(v) Set("customWidth", v); ApplySize() end },
                { type="slider", text="Max Height",
                  tooltip="The tracker grows with your quests up to this height, then scrolls.",
                  min = hMin, max = hMax, step = 1,
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customMaxHeight") or 450 end,
                  setValue=function(v) Set("customMaxHeight", v); ApplySize() end })
            y = y - h

            -- Grow Direction | Scrollbar
            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Grow Direction",
                  tooltip="Which way the tracker grows as quests are added. Up keeps its bottom edge in place.",
                  values = { DOWN = "Down", UP = "Up" },
                  order  = { "DOWN", "UP" },
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customGrowUp") and "UP" or "DOWN" end,
                  setValue=function(v) EQT.SetCustomGrowUp(v == "UP") end },
                { type="dropdown", text="Scrollbar",
                  tooltip="When the scrollbar shows while the list is taller than the tracker. The mouse wheel scrolls either way.",
                  values = { always = "Always", hover = "Hovered", hidden = "Hidden" },
                  order  = { "always", "hover", "hidden" },
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customScrollbar") or "always" end,
                  setValue=function(v) Set("customScrollbar", v); RefreshAll() end })
            y = y - h

            -- Quest Click | Collapse Completed Quests
            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Quest Click",
                  tooltip="What left-clicking a quest does. Open Quest Details shows EllesmereUI's own details window and works in combat. Open Quest Log works out of combat only, for quests tracked in the quest log. Ctrl-click still collapses.",
                  values = { collapse = "Collapse", map = "Open Quest Log", details = "Open Quest Details" },
                  order  = { "collapse", "map", "details" },
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customClickAction") or "collapse" end,
                  setValue=function(v) Set("customClickAction", v); RefreshAll() end },
                { type="toggle", text="Collapse Completed Quests",
                  tooltip="Hides the objectives of quests that are ready to turn in. Click a quest to expand it.",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customCollapseCompleted") or false end,
                  setValue=function(v) Set("customCollapseCompleted", v); RefreshAll() end })
            y = y - h

            -- Quest Spacing | Objective Spacing
            _, h = W:DualRow(parent, y,
                { type="slider", text="Quest Spacing",
                  min = 0, max = 20, step = 1,
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customQuestSpacing") or 4 end,
                  setValue=function(v) Set("customQuestSpacing", v); RefreshAll() end },
                { type="slider", text="Objective Spacing",
                  min = 0, max = 10, step = 1,
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customObjSpacing") or 1 end,
                  setValue=function(v) Set("customObjSpacing", v); RefreshAll() end })
            y = y - h

            -- Quest Focus | Wrap Quest Names
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Quest Focus",
                  tooltip="Adds a focus button beside each quest, and Focus to its right-click menu. A focused quest gets the map waypoint.",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customFocusClick") or false end,
                  setValue=function(v) Set("customFocusClick", v); RefreshAll() end },
                { type="toggle", text="Wrap Quest Names",
                  tooltip="Long quest and zone names wrap onto more lines. Off: one line, cut short with ...",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customWrapTitles") ~= false end,
                  setValue=function(v) Set("customWrapTitles", v); RefreshAll() end })
            y = y - h

            -- Wrap Objectives | Zone Header Font Size
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Wrap Objectives",
                  tooltip="Long objectives wrap onto more lines. Off: one line, cut short with ...",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customWrapObjectives") ~= false end,
                  setValue=function(v) Set("customWrapObjectives", v); RefreshAll() end },
                { type="slider", text="Zone Header Font Size",
                  min = 8, max = 24, step = 1,
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customZoneFontSize") or 13 end,
                  setValue=function(v) Set("customZoneFontSize", v); RefreshAll() end })
            y = y - h

            -- Quest Item Buttons | Flash Objective Updates
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Quest Item Buttons",
                  tooltip="Adds a button beside quests that have a usable item. In combat, buttons stay where they are until combat ends.",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customItemButtons") or false end,
                  setValue=function(v) Set("customItemButtons", v); RefreshAll() end },
                { type="toggle", text="Flash Objective Updates",
                  tooltip="Briefly highlights an objective when its progress changes.",
                  disabled=Off, disabledTooltip="Custom Quest Tracker",
                  getValue=function() return Cfg("customFlashUpdates") or false end,
                  setValue=function(v) Set("customFlashUpdates", v); RefreshAll() end })
            y = y - h

            y = y - 10
        end

        -- -- DISPLAY ---------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
        if BS then y = BS.Note(parent, y, "questtracker") end

        -- Row 1: Visibility | Hide When In Raid. The raid-hide dropdown moved up from
        -- the Background Opacity row into the slot the old Visibility Options dropdown
        -- left behind: it answers the same question the Visibility control does.
        _, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
            { getStore = DB, legacyKey = "visibility",
              caps = { partyIncludesRaid = false, luaDragonriding = true },
              onChanged = function() RefreshAll() end,
              onOptionChanged = function() RefreshAll() end },
            { type="dropdown", text="Hide When In Raid",
              tooltip="Always: hide the tracker the whole time you are in a raid.\nBoss Combat: keep it visible and only hide during boss encounters.\nNever: keep it visible in raids; only the Visibility options hide it.",
              values = { always = "Always", boss = "Boss Combat", never = "Never" },
              order  = { "always", "boss", "never" },
              getValue=function() return Cfg("hideInRaidMode") or "boss" end,
              setValue=function(v) Set("hideInRaidMode", v); if EQT.UpdateVisibility then EQT.UpdateVisibility() end end })
        y = y - h

        if not STOCK then
        -- Row 2: Background Opacity (slider + inline color swatch) | Show Top Line.
        -- Show Top Line moved up from the old trailing half-row to close the gap left
        -- by Hide When In Raid; both settings describe the tracker's background chrome.
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.05,
              getValue=function() return Cfg("bgAlpha") or 0.5 end,
              setValue=function(v) Set("bgAlpha", v); if EQT.ApplyBackground then EQT.ApplyBackground() end end },
            { type="toggle", text="Show Top Line",
              tooltip="Draws a 1px accent line above the background at the top of the tracker.",
              getValue=function() return Cfg("showTopLine") ~= false end,
              setValue=function(v) Set("showTopLine", v); if EQT.ApplyBackground then EQT.ApplyBackground() end end })
        if not EllesmereUI._prebuilding then
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            -- The custom tracker can hide its background until hovered.
            if CUSTOM then
                EllesmereUI.BuildInlineCog(rgn, {
                    title = "Background Settings",
                    rows = {
                        { type="toggle", label="Show Only When Hovered",
                          get=function() return Cfg("customBgHover") or false end,
                          set=function(v) Set("customBgHover", v); RefreshAll() end },
                        { type="toggle", label="Fade In and Out",
                          disabled=function() return not Cfg("customBgHover") end,
                          disabledTooltip="Requires Show Only When Hovered.", rawTooltip=true,
                          get=function() return Cfg("customBgFade") ~= false end,
                          set=function(v) Set("customBgFade", v) end },
                    },
                })
            end
            local bgSwatch, bgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("bgR") or 0), (Cfg("bgG") or 0), (Cfg("bgB") or 0)
                end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    if EQT.ApplyBackground then EQT.ApplyBackground() end
                end,
                false, 20)
            PP.Point(bgSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
            rgn._lastInline = bgSwatch
            EllesmereUI.RegisterWidgetRefresh(function() bgSwatchRefresh() end)
        end
        y = y - h

        -- Row 3: Header Font Size | Title Font Size
        _, h = W:DualRow(parent, y,
            { type="slider", text="Header Font Size",
              min = 8, max = 24, step = 1,
              getValue=function() return Cfg("headerFontSize") or 13 end,
              setValue=function(v) Set("headerFontSize", v); RefreshAll() end },
            { type="slider", text="Title Font Size",
              min = 8, max = 24, step = 1,
              getValue=function() return Cfg("titleFontSize") or 12 end,
              setValue=function(v) Set("titleFontSize", v); RefreshAll() end }
            )
        y = y - h

        -- Row 3b: Objective Font Size | Font
        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
            _, h = W:DualRow(parent, y,
                { type="slider", text="Objective Font Size",
                  min = 8, max = 24, step = 1,
                  getValue=function() return Cfg("objectiveFontSize") or 10 end,
                  setValue=function(v) Set("objectiveFontSize", v); RefreshAll() end },
                { type="dropdown", text="Font",
                  values=fontValues, order=fontOrder,
                  getValue=function() return Cfg("font") or "__global" end,
                  setValue=function(v)
                      Set("font", v)
                      -- The custom tracker restyles live.
                      if CUSTOM then RefreshAll(); return end
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Font changed. A UI reload is needed to apply the new font.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          reload      = true,
                      })
                  end })
        end
        y = y - h
        end -- not STOCK

        -- Row 4: Show Quest Icons | Hide All Objectives. Both stock styles show
        -- Blizzard's native icons, so the toggle is gated there.
        local questIconsCfg = { type="toggle", text="Show Quest Icons",
              tooltip="Show Blizzard's native quest type icons/buttons on the right instead of EllesmereUI's custom icons. Requires a UI reload.",
              getValue=function() return Cfg("showQuestIcons") or false end,
              setValue=function(v)
                  Set("showQuestIcons", v)
                  EllesmereUI:ShowConfirmPopup({
                      title       = "Reload Required",
                      message     = "Changing quest icons requires a UI reload to apply.",
                      confirmText = "Reload Now",
                      cancelText  = "Later",
                      reload      = true,
                  })
              end }
        if BS then BS.Gate("questtracker", questIconsCfg) end
        if not CUSTOM then
        _, h = W:DualRow(parent, y,
            questIconsCfg,
            { type="toggle", text="Hide All Objectives",
              tooltip = STOCK
                  and "Hides the master header and its minimize button at the top of the tracker."
                  or "Hides the master header and its minimize button at the top of the tracker. When shown, it's skinned to match the section headers below it (Quests, Achievements, ...).",
              -- The module's own rule, so the per-style default (hidden under
              -- the EllesmereUI look, shown under the stock styles) reads true.
              getValue=function()
                  if EQT.ShouldHideMasterHeader then return EQT.ShouldHideMasterHeader() end
                  return Cfg("hideAllObjectivesHeader") ~= false
              end,
              setValue=function(v)
                  Set("hideAllObjectivesHeader", v)
                  if EQT.ApplyMasterHeaderVisibility then EQT.ApplyMasterHeaderVisibility() end
                  if EQT.QueueResize then EQT.QueueResize() end
              end })
        y = y - h
        end -- not CUSTOM

        if not STOCK then
        -- -- COLORS ----------------------------------------------------------
        _, h = W:SectionHeader(parent, "COLORS", y); y = y - h

        -- `default` must mirror the fallback in the matching Get*RGB()
        -- function in EllesmereUIQuestTracker_Skin.lua, or the swatch will
        -- show a color (black) that doesn't match what's actually rendered
        -- until the user picks one explicitly.
        local TITLE_KEYS, TITLE_DEFAULT = { r = "titleR", g = "titleG", b = "titleB" }, { 1.0, 0.910, 0.471 }
        local DONE_KEYS, DONE_DEFAULT = { r = "completedR", g = "completedG", b = "completedB" }, { 0.251, 1.0, 0.349 }
        local function ColorGetter(keys, default)
            return function()
                return (Cfg(keys.r) or default[1]), (Cfg(keys.g) or default[2]), (Cfg(keys.b) or default[3])
            end
        end
        local function ColorSetter(keys)
            return function(cr, cg, cb)
                Set(keys.r, cr); Set(keys.g, cg); Set(keys.b, cb)
                RefreshAll()
            end
        end
        local function WireColorSwatch(r, rgn, keys, default)
            local sw, swRefresh = EllesmereUI.BuildColorSwatch(
                rgn, r:GetFrameLevel() + 3, ColorGetter(keys, default), ColorSetter(keys), false, 20)
            PP.Point(sw, "RIGHT", rgn, "RIGHT", -20, 0)
            EllesmereUI.RegisterWidgetRefresh(function() swRefresh() end)
        end
        local function MakeColorRow(leftLabel, leftKeys, leftDefault, rightLabel, rightKeys, rightDefault)
            local r, rowH = W:DualRow(parent, y,
                { type="label", text = leftLabel },
                { type="label", text = rightLabel })
            if not EllesmereUI._prebuilding then
            WireColorSwatch(r, r._leftRegion,  leftKeys,  leftDefault)
            if rightKeys then WireColorSwatch(r, r._rightRegion, rightKeys, rightDefault) end
            end
            return r, rowH
        end

        if FOREVER then
            -- Title Difficulty Colors | Completed Color. The toggle is the
            -- game's own showQuestDifficultyColor option (EQT.TitleDifficultyOn),
            -- which Blizzard's tracker and quest log follow and the custom
            -- tracker reads; its inline swatch, the Title Color, greys out
            -- while it is on. Retail has no quest title difficulty colors.
            local r
            r, h = W:DualRow(parent, y,
                { type="toggle", text="Title Difficulty Colors",
                  tooltip="Colors quest titles by difficulty for your level. This is the game's own option, so its quest log follows it too.",
                  getValue=function() return EQT.TitleDifficultyOn() end,
                  setValue=function(v)
                      EllesmereUI.SetCVar("showQuestDifficultyColor", v and "1" or "0", "EllesmereUIQuestTracker")
                      RefreshAll(); EllesmereUI:RefreshPage()
                  end },
                { type="label", text="Completed Color" })
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineSwatches(r._leftRegion, {
                    { tooltip = "Title Color", hasAlpha = false,
                      getValue = ColorGetter(TITLE_KEYS, TITLE_DEFAULT),
                      setValue = ColorSetter(TITLE_KEYS) },
                }, { disabled = EQT.TitleDifficultyOn,
                     disabledTooltip = "Title Difficulty Colors", requireState = "disabled" })
                WireColorSwatch(r, r._rightRegion, DONE_KEYS, DONE_DEFAULT)
            end
        else
            _, h = MakeColorRow("Title Color", TITLE_KEYS, TITLE_DEFAULT, "Completed Color", DONE_KEYS, DONE_DEFAULT)
        end
        y = y - h

        -- Header Color / Line Color: each offers Class Color, Custom Color
        -- (free RGB picker, same swatch behavior as the rows above) and
        -- Accent Color. Default is Accent Color for both (headerUseAccent /
        -- lineUseAccent are treated as true until explicitly set to false).
        -- `customDefault` must mirror the fallback baked into the matching
        -- Get*RGB() function in EllesmereUIQuestTracker_Skin.lua.
        local function MakeColorModeSwatches(prefix, customDefault)
            local classKey  = prefix .. "ShowClassColor"
            local accentKey = prefix .. "UseAccent"
            local rKey, gKey, bKey = prefix .. "R", prefix .. "G", prefix .. "B"

            local function isClass()  return Cfg(classKey) == true end
            local function isAccent() return not isClass() and Cfg(accentKey) ~= false end

            local classSwatch = {
                tooltip = "Class Color", hasAlpha = false,
                getValue = function()
                    local cc = EllesmereUI._playerClass and EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                    if cc then return cc.r, cc.g, cc.b end
                    return 1.0, 1.0, 1.0
                end,
                setValue = function() end,
                onClick = function()
                    Set(classKey, true); Set(accentKey, false)
                    RefreshAll(); EllesmereUI:RefreshPage()
                end,
                refreshAlpha = function() return isClass() and 1 or 0.3 end,
            }

            local customSwatch = {
                tooltip = "Custom Color", hasAlpha = false,
                getValue = function()
                    return (Cfg(rKey) or customDefault[1]), (Cfg(gKey) or customDefault[2]), (Cfg(bKey) or customDefault[3])
                end,
                setValue = function(r, g, b)
                    Set(rKey, r); Set(gKey, g); Set(bKey, b)
                    Set(classKey, false); Set(accentKey, false)
                    RefreshAll(); EllesmereUI:RefreshPage()
                end,
                onClick = function(self)
                    if isClass() or isAccent() then
                        Set(classKey, false); Set(accentKey, false)
                        RefreshAll(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end,
                refreshAlpha = function()
                    if isClass() then return 0.15 end
                    return isAccent() and 0.3 or 1
                end,
            }

            local accentSwatch = {
                tooltip = "Accent Color", hasAlpha = false,
                getValue = function() return EllesmereUI.ResolveActiveAccent() end,
                setValue = function() end,
                onClick = function()
                    Set(classKey, false); Set(accentKey, true)
                    RefreshAll(); EllesmereUI:RefreshPage()
                end,
                refreshAlpha = function() return isAccent() and 1 or 0.3 end,
            }

            return classSwatch, customSwatch, accentSwatch
        end

        -- Focused Color | Header Color
        do
            local hClass, hCustom, hAccent = MakeColorModeSwatches("header", { 1.0, 1.0, 1.0 })
            local r, rowH = W:DualRow(parent, y,
                { type="label", text="Focused Color" },
                { type="multiSwatch", text="Header Color",
                  swatches = { hClass, hCustom, hAccent } })
            if not EllesmereUI._prebuilding then
            local sw, swRefresh = EllesmereUI.BuildColorSwatch(
                r._leftRegion, r:GetFrameLevel() + 3,
                function() return (Cfg("focusR") or 0.871), (Cfg("focusG") or 0.251), (Cfg("focusB") or 1.0) end,
                function(cr, cg, cb) Set("focusR", cr); Set("focusG", cg); Set("focusB", cb); RefreshAll() end,
                false, 20)
            PP.Point(sw, "RIGHT", r._leftRegion, "RIGHT", -20, 0)
            EllesmereUI.RegisterWidgetRefresh(function() swRefresh() end)
            end
            h = rowH
        end
        y = y - h

        -- Line Color | Color Objectives by Progress (+ color stops cog). The
        -- objective colors are WoW Forever only; retail keeps the spacer.
        do
            local lClass, lCustom, lAccent = MakeColorModeSwatches("line", { 1.0, 1.0, 1.0 })
            local r
            r, h = W:DualRow(parent, y,
                { type="multiSwatch", text="Line Color",
                  swatches = { lClass, lCustom, lAccent } },
                FOREVER and { type="toggle", text="Color Objectives by Progress",
                  tooltip="Colors objectives by how far along they are.",
                  getValue=function() return Cfg("objProgressColor") or false end,
                  setValue=function(v) Set("objProgressColor", v); RefreshAll(); EllesmereUI:RefreshPage() end }
                  or { type="spacer" })
            if FOREVER then
                local function Stop(label, name)
                    local d = EQT.OBJ_STOPS[name]
                    local kr, kg, kb = "obj" .. name .. "R", "obj" .. name .. "G", "obj" .. name .. "B"
                    return { type="colorpicker", label=label,
                        get=function() return Cfg(kr) or d[1], Cfg(kg) or d[2], Cfg(kb) or d[3] end,
                        set=function(cr, cg, cb) Set(kr, cr); Set(kg, cg); Set(kb, cb); RefreshAll() end }
                end
                EllesmereUI.BuildInlineCog(r._rightRegion, {
                    disabled = function() return not Cfg("objProgressColor") end,
                    disabledTooltip = "Color Objectives by Progress",
                    title = "Progress Colors",
                    rows = {
                        Stop("Start Color", "Start"),
                        Stop("Halfway Color", "Mid"),
                        Stop("End Color", "End"),
                    },
                })
            end
        end
        y = y - h

        -- Dim Completed Objectives (+ opacity cog) | blank (WoW Forever only)
        if FOREVER then
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Dim Completed Objectives",
                  tooltip="Fades objective lines that are already done.",
                  getValue=function() return Cfg("objDimCompleted") or false end,
                  setValue=function(v) Set("objDimCompleted", v); RefreshAll(); EllesmereUI:RefreshPage() end },
                EllesmereUI.BlankRowCfg())
            EllesmereUI.BuildInlineCog(row._leftRegion, {
                disabled = function() return not Cfg("objDimCompleted") end,
                disabledTooltip = "Dim Completed Objectives",
                title = "Dim Settings",
                rows = {
                    { type="slider", label="Opacity", min=10, max=100, step=5,
                      get=function() return Cfg("objDimAlpha") or 45 end,
                      set=function(v) Set("objDimAlpha", v); RefreshAll() end },
                },
            })
            y = y - h
        end

        y = y - 10
        end -- not STOCK

        if FOREVER then
        -- -- TRACKING (WoW Forever only) --------------------------------------
        -- Sorting and filters edit the watch list; filtered quests are
        -- untracked and come back once they pass again. They wait behind the
        -- Experimental Quest Tools switch, which warns before it turns on.
        _, h = W:SectionHeader(parent, "TRACKING", y); y = y - h
        -- The rows change nothing while the map is open (watch list edits wait
        -- for it to close, CanEditWatches), so the note says so up front.
        -- The custom tracker sorts its own list, so none of that applies there.
        if not CUSTOM then
            y = EllesmereUI.BuildNoteRow(parent, y,
                "Sorting, filtering and auto-tracking don't update while the map or quest log is open, in combat or in dungeons. Close the map to apply them.",
                { banner = true })
        end

        local ApplyWatches, ApplyProgress = EQT.ApplyQuestWatches, EQT.ApplyQuestProgress
        -- Quest Log Order is the base sort mode (a saved "default", the retired
        -- Blizzard order mode, reads as it).
        local function SortModeCfg()
            local m = Cfg("questSortMode")
            if m == nil or m == "default" then return "log" end
            return m
        end
        -- Section gate: Sort Quests, Filter Quests and Auto Track Zone Quests are
        -- built only while Experimental Quest Tools is on; turning
        -- it on or off rebuilds the page. The progress rows always show.
        -- The custom tracker needs no switch: it never edits the watch list.
        local toolsOn = CUSTOM or Cfg("questWatchExperimental") == true
        local function FilterRow(key, label)
            return { type="toggle", label=label,
                get=function() return Cfg(key) or false end,
                set=function(v) Set(key, v); ApplyWatches() end }
        end

        local expCfg = { type="toggle", text="Experimental Quest Tools",
              tooltip="Unlocks Sort Quests, Filter Quests and Auto Track Zone Quests.",
              disabled=function() return CUSTOM end,
              disabledTooltip="Always on with the Custom Quest Tracker.",
              rawTooltip=CUSTOM or nil,
              getValue=function() return CUSTOM or Cfg("questWatchExperimental") == true end,
              setValue=function(v)
                  if not v then
                      Set("questWatchExperimental", false)
                      ApplyWatches(); EllesmereUI:RefreshPage(true)
                      return
                  end
                  -- Saved only once the warning is confirmed.
                  EllesmereUI:ShowConfirmPopup({
                      title       = EllesmereUI.L("Experimental Feature"),
                      message     = EllesmereUI.L("Quest sorting, filtering and zone auto-tracking are experimental and may cause occasional Lua errors. If you run into one, type /reload or turn this option off."),
                      confirmText = EllesmereUI.L("Enable"),
                      cancelText  = EllesmereUI.L("Cancel"),
                      onConfirm   = function()
                          Set("questWatchExperimental", true)
                          ApplyWatches(); EllesmereUI:RefreshPage(true)
                      end,
                      onCancel    = function() EllesmereUI:RefreshPage() end,
                  })
              end }

        local sndValues, sndOrder = EllesmereUI.BuildSoundDropdownValues(EQT.Sounds())
        -- Preview through the module so the peon FileDataIDs play correctly.
        sndValues._menuOpts.iconOnClick = EQT.PlaySoundKey
        local announceCfg = { type="toggle", text="Announce Progress",
              tooltip="Posts each quest objective you complete to party or instance chat, with a link to the quest. Never in raids.",
              getValue=function() return Cfg("announceProgress") or false end,
              setValue=function(v) Set("announceProgress", v); ApplyProgress() end }
        local objSoundCfg = { type="dropdown", text="Objective Complete Sound", values=sndValues, order=sndOrder,
              getValue=function() return Cfg("soundObjective") or "none" end,
              setValue=function(v) Set("soundObjective", v); ApplyProgress() end }
        local questSoundCfg = { type="dropdown", text="Quest Complete Sound", values=sndValues, order=sndOrder,
              getValue=function() return Cfg("soundQuest") or "none" end,
              setValue=function(v) Set("soundQuest", v); ApplyProgress() end }

        if not toolsOn then
            -- Experimental Quest Tools | Announce Progress, then the two sounds.
            _, h = W:DualRow(parent, y, expCfg, announceCfg);  y = y - h
            _, h = W:DualRow(parent, y, objSoundCfg, questSoundCfg);  y = y - h
        else
            -- Experimental Quest Tools | Sort Quests (+ completed placement cog)
            row, h = W:DualRow(parent, y, expCfg,
                { type="dropdown", text="Sort Quests",
                  tooltip="Reorders your tracked quests; Quest Log Order lists them as your quest log does.",
                  values = { log = "Quest Log Order", zone = "Zone", level = "Level",
                             name = "Name", progress = "Progress", type = "Quest Type" },
                  order  = { "log", "zone", "level", "name", "progress", "type" },
                  getValue=SortModeCfg,
                  setValue=function(v) Set("questSortMode", v); ApplyWatches() end })
            EllesmereUI.BuildInlineCog(row._rightRegion, {
                title = "Sort Settings",
                rows = {
                    { type="dropdown", label="Completed Quests",
                      values = { mixed = "Mixed In", top = "Top", bottom = "Bottom" },
                      order  = { "mixed", "top", "bottom" },
                      get=function() return Cfg("questSortCompleted") or "mixed" end,
                      set=function(v) Set("questSortCompleted", v); ApplyWatches() end },
                    { type="dropdown", label="Then By",
                      values = { none = "None", zone = "Zone", level = "Level", name = "Name",
                                 progress = "Progress", type = "Quest Type" },
                      order  = { "none", "zone", "level", "name", "progress", "type" },
                      disabled=function() return SortModeCfg() == "log" end,
                      disabledTooltip="Requires Sort Quests set to something other than Quest Log Order.", rawTooltip=true,
                      get=function() return Cfg("questSortThenBy") or "none" end,
                      set=function(v) Set("questSortThenBy", v); ApplyWatches() end },
                },
            })
            y = y - h

            -- Filter Quests (+ filters cog) | Auto Track Zone Quests
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Filter Quests",
                  tooltip="Untracks quests that match the filters in the cog until they no longer match.",
                  getValue=function() return Cfg("filterEnabled") or false end,
                  setValue=function(v) Set("filterEnabled", v); ApplyWatches(); EllesmereUI:RefreshPage() end },
                { type="toggle", text="Auto Track Zone Quests",
                  tooltip="Tracks your current zone's or dungeon's quests and untracks them when you leave.",
                  getValue=function() return Cfg("autoTrackZone") or false end,
                  setValue=function(v) Set("autoTrackZone", v); ApplyWatches() end })
            EllesmereUI.BuildInlineCog(row._leftRegion, {
                -- Open while the header button shows too: it turns Filter Quests
                -- off, and its own row is in here.
                disabled = function() return not Cfg("filterEnabled") and not Cfg("filterHeaderToggle") end,
                disabledTooltip = "Filter Quests",
                title = "Filter Settings",
                rows = {
                    FilterRow("filterZone", "Current Zone Only"),
                    FilterRow("filterCompleted", "Hide Completed Quests"),
                    FilterRow("filterTrivial", "Hide Low Level Quests"),
                    FilterRow("filterRepeatable", "Hide Daily & Weekly Quests"),
                    FilterRow("filterHeaderToggle", "Show Toggle on Quests Header"),
                },
            })
            y = y - h

            -- Announce Progress | Objective Complete Sound, then Quest Complete Sound
            _, h = W:DualRow(parent, y, announceCfg, objSoundCfg);  y = y - h
            _, h = W:DualRow(parent, y, questSoundCfg, EllesmereUI.BlankRowCfg());  y = y - h
        end

        y = y - 10
        end -- FOREVER

        -- -- EXTRAS ----------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Accept Quests",
              getValue=function() return Cfg("autoAccept") or false end,
              setValue=function(v)
                  Set("autoAccept", v)
                  if EQT.SyncAutoQuests then EQT.SyncAutoQuests() end
              end },
            { type="toggle", text="Auto Turn In Quests",
              getValue=function() return Cfg("autoTurnIn") or false end,
              setValue=function(v)
                  Set("autoTurnIn", v)
                  if EQT.SyncAutoQuests then EQT.SyncAutoQuests() end
              end })
        local acceptRows = {
            { type="toggle", label="Prevent Multi Quest Accept",
              get=function() return Cfg("autoAcceptPreventMulti") ~= false end,
              set=function(v) Set("autoAcceptPreventMulti", v) end },
            -- Hold Shift to Enable and Hold Shift to Skip are opposites: turning one on turns the other off.
            { type="toggle", label="Hold Shift to Enable",
              get=function() return Cfg("autoAcceptShiftEnable") == true end,
              set=function(v)
                  Set("autoAcceptShiftEnable", v)
                  if v then Set("autoAcceptShiftSkip", false) end
              end },
            { type="toggle", label="Hold Shift to Skip",
              get=function() return Cfg("autoAcceptShiftSkip") ~= false end,
              set=function(v)
                  Set("autoAcceptShiftSkip", v)
                  if v then Set("autoAcceptShiftEnable", false) end
              end },
            { type="toggle", label="Ignore Low Level Quests",
              get=function() return Cfg("autoAcceptIgnoreTrivial") or false end,
              set=function(v) Set("autoAcceptIgnoreTrivial", v) end },
        }
        -- WoW Forever has no older expansions to skip.
        if not EllesmereUI.IS_FOREVER then
            acceptRows[#acceptRows + 1] = { type="toggle", label="Ignore Older Expansion Quests",
                get=function() return Cfg("autoAcceptIgnoreOldExpansion") or false end,
                set=function(v) Set("autoAcceptIgnoreOldExpansion", v) end }
        end
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Auto Accept Settings",
            rows = acceptRows,
        })

        EllesmereUI.BuildInlineCog(row._rightRegion, {
            title = "Auto Turn In Settings",
            rows = {
                { type="toggle", label="Hold Shift to Enable",
                  get=function() return Cfg("autoTurnInShiftEnable") == true end,
                  set=function(v)
                      Set("autoTurnInShiftEnable", v)
                      if v then Set("autoTurnInShiftSkip", false) end
                  end },
                { type="toggle", label="Hold Shift to Skip",
                  get=function() return Cfg("autoTurnInShiftSkip") ~= false end,
                  set=function(v)
                      Set("autoTurnInShiftSkip", v)
                      if v then Set("autoTurnInShiftEnable", false) end
                  end },
            },
        })
        y = y - h

        -- Quest Item Hotkey row
        local kbRow
        kbRow, h = W:DualRow(parent, y,
            { type="label", text="" },
            { type="toggle", text="Wowhead Quest Links",
                tooltip="Adds a copyable Wowhead link to the right-click menu of quests in the quest tracker and quest log.",
                getValue=function() return Cfg("wowheadQuestLinks") == true end,
                setValue=function(v)
                    Set("wowheadQuestLinks", v)
                    EQT.ApplyQuestLinks()
                    EllesmereUI:RefreshPage()
                end })
        EllesmereUI.BuildInlineCog(kbRow._rightRegion, {
            title = "Wowhead Link Settings",
            disabled = function() return not Cfg("wowheadQuestLinks") end,
            disabledTooltip = "Wowhead Quest Links",
            rows = {
                { type="toggle", label="Use Client Language",
                  get=function() return Cfg("wowheadQuestClientLanguage") == true end,
                  set=function(v) Set("wowheadQuestClientLanguage", v) end },
                { type="toggle", label="Jump to Comments",
                  get=function() return Cfg("wowheadQuestComments") == true end,
                  set=function(v) Set("wowheadQuestComments", v) end },
            },
        })
        if not EllesmereUI._prebuilding then
            local rgn = kbRow._leftRegion
            local SIDE_PAD = 20

            local label = EllesmereUI.MakeFont(rgn, 14, nil,
                EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", rgn, "LEFT", SIDE_PAD, 0)
            label:SetText(EllesmereUI.L("Quest Item Hotkey"))

            local kbBtn, refresh = EllesmereUI.BuildKeybindButton(rgn, {
                w = 120, h = 26, pp = PP, level = 5,
                get = function() return Cfg("questItemHotkey") end,
                set = function(v)
                    Set("questItemHotkey", v)
                    if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                end,
            })
            PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -SIDE_PAD, 0)
            EllesmereUI.RegisterWidgetRefresh(refresh)
        end
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildQuestTrackerPage = BuildPage

    EllesmereUI:RegisterModule("EllesmereUIQuestTracker", {
        title       = "Quest Tracker",
        description = "Blizzard tracker skin, visibility rules, auto-accept/turn-in, quest-item hotkey.",
        pages       = { "Quest Tracker" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        onReset = function()
            local d = _G._EQT_DB
            if d and d.ResetProfile then d:ResetProfile() end
            RefreshAll()
            EllesmereUI:InvalidatePageCache()
        end,
    })

    SLASH_EQTOPTS1 = "/eqtopts"
    SlashCmdList.EQTOPTS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIQuestTracker")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
