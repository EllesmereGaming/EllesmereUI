if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Options.lua: Group Finder settings page
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIGroupFinder"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end  -- module off: no page
local EUI = EllesmereUI

local PAGE_SEARCH = "Premade Search"
local PAGE_APPS = "Applications Tracker"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local AddAppsSections, AddListSections

    -----------------------------------------------------------------------
    -- applications settings (greyed while the module's off)
    -----------------------------------------------------------------------
    local function APCfg() return ns.AppsCfg() end
    local function APGet(key, default)
        local c = APCfg()
        local v = c and c[key]
        if v == nil then return default end
        return v
    end
    local function APSet(key, val)
        local c = APCfg()
        if c then c[key] = val end
        ns.ApplyApplications()
    end
    local function ModOff() return not ns.Enabled() end
    local function APOff() return ModOff() or APGet("enabled", false) ~= true end
    local function APOffTip() return ModOff() and "Group Finder" or "Show Applications in Group Finder" end

    local function BuildSearchPage(pageName, parent, yOffset)
        local W = EUI.Widgets
        local y = yOffset
        local _, h

        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- enable toggle reloads. beside it, the pgf warning when it's loaded
        local PGFLoaded = ns.Blocked
        local pgfNote = PGFLoaded()
            and { type = "label", text = EUI.COLOR_CODES.ERROR
                    .. EllesmereUI.L("Premade Groups Filter is loaded. Disable it to use the Group Finder.") .. "|r" }
            or EUI.BlankRowCfg()
        _, h = W:SectionHeader(parent, "GROUP FINDER", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Group Finder",
              disabled = function() return PGFLoaded() and not ns.Enabled() end,
              disabledTooltip = "Premade Groups Filter", requireState = "disabled",
              tooltip = "Premade Groups search filters, group list and the M+ applications bar in the Dungeons & Raids window. Requires a reload.",
              getValue = function() return ns.Enabled() end,
              setValue = function(v)
                  v = v and true or false
                  if v == ns.Enabled() then return end
                  -- only saved once the reload's confirmed
                  EUI:ShowConfirmPopup({
                      title       = v and "Enable Group Finder" or "Disable Group Finder",
                      message     = v and "Your UI will reload to turn on the Group Finder."
                                      or "Your UI will reload to turn off the Group Finder.",
                      confirmText = "Reload Now",
                      cancelText  = "Cancel",
                      reload      = true,
                      onConfirm   = function() ns.SetEnabled(v) end,
                      onCancel    = function() EUI:RefreshPage() end,
                  })
              end },
            pgfNote);  y = y - h

        y = AddListSections(parent, y)

        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y - yOffset)
    end

    -- applications page, reset buttons with it
    local function BuildAppsPage(parent, yOffset)
        local W = EUI.Widgets
        local y = yOffset
        local _, h
        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true
        y = AddAppsSections(parent, y)
        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y - yOffset)
    end

    -- results list, mythic+, display, sign up
    function AddListSections(parent, y)
        local W = EUI.Widgets
        local _, h
        _, h = W:SectionHeader(parent, "WINDOW", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Background Color", hasAlpha = true,
              tooltip = "The tint over the Dungeons & Raids window background. Its opacity sets how strong the tint is.",
              getValue = function()
                  local c = ns.OwnListGet("windowBgColor")
                  if c then return c.r, c.g, c.b, c.a or 0.62 end
                  return 0, 0, 0, 0.62
              end,
              setValue = function(r, g, b, a)
                  ns.SetWindowLook("windowBgColor", { r = r, g = g, b = b, a = a })
              end },
            { type = "slider", text = "Background Opacity", min = 0, max = 100, step = 5,
              tooltip = "How see-through the Dungeons & Raids window background is.",
              getValue = function() return ns.OwnListGet("windowBgOpacity") or 100 end,
              setValue = function(v) ns.SetWindowLook("windowBgOpacity", v) end })
        y = y - h

        _, h = W:SectionHeader(parent, "RESULTS LIST", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Title Text Size", min = 8, max = 20, step = 1,
              tooltip = "The group's title, the first line.",
              getValue = function() return ns.OwnListSize("titleSize") end,
              setValue = function(v) ns.SetOwnListSize("titleSize", v) end },
            { type = "toggle", text = "Colored Group Names",
              tooltip = "Green name when a group is new, Red name when you were declined or instance locked.",
              getValue = function() return ns.Cfg().nameColors ~= false end,
              setValue = function(v)
                  ns.Cfg().nameColors = v and true or false
                  if ns.Redecorate then ns.Redecorate() end
              end })
        y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Dungeon / Raid Text Size", min = 8, max = 20, step = 1,
              tooltip = "The dungeon or raid name text size.",
              getValue = function() return ns.OwnListSize("nameSize") end,
              setValue = function(v) ns.SetOwnListSize("nameSize", v) end },
            { type = "slider", text = "Activity Text Size", min = 8, max = 20, step = 1,
              tooltip = "The playstyle and region tag text size.",
              getValue = function() return ns.OwnListSize("lineSize") end,
              setValue = function(v) ns.SetOwnListSize("lineSize", v) end })
        y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Row Height", min = 20, max = 64, step = 1,
              tooltip = "How tall each row is. Lines that no longer fit drop off from the bottom: the playstyle line first, then the dungeon / raid name (its short name then sits ahead of the title) and the leader crown.",
              getValue = function() return ns.OwnListRowHeight() end,
              setValue = function(v) ns.SetOwnListRowHeight(v) end },
            { type = "toggle", text = "Applied Groups on Top",
              tooltip = "Groups you apply to move to the top of the list.",
              getValue = function() return ns.OwnListGet("appsFirst") ~= false end,
              setValue = function(v) ns.SetOwnListValue("appsFirst", v and true or false) end })
        y = y - h
        -- status color: a checklist, one color each
        local LINE_ITEMS = {
            { key = "lineDelisted",  label = "Delisted (|cff999999Grey|r)",   tooltip = "The group was delisted." },
            { key = "lineAccepted",  label = "Accepted (|cff1ae61aGreen|r)",  tooltip = "Applied and waiting, or invited." },
            { key = "lineCancelled", label = "Canceled (|cffff8c1aOrange|r)", tooltip = "You cancelled the application." },
            { key = "lineDeclined",  label = "Declined (|cffff3333Red|r)",    tooltip = "Declined, the group filled, or the application timed out." },
        }
        local lineRow
        lineRow, h = W:DualRow(parent, y,
            -- placeholder, the checklist replaces it
            { type = "dropdown", text = "Status Underline",
              tooltip = "A colored line below the group you applied to, to show its status.",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            { type = "dropdown", text = "Results Visibility",
              tooltip = "Groups your filters leave out: hidden from the list, or shown dimmed.",
              values = { dimmed = "Dimmed", hidden = "Hidden" }, order = { "dimmed", "hidden" },
              getValue = function() return ns.OwnListGet("visibility") end,
              setValue = function(v)
                  if v == ns.OwnListGet("visibility") then return end
                  ns.SetOwnListValue("visibility", v)
                  if ns.DimFiltersChanged then ns.DimFiltersChanged() end
              end })
        y = y - h
        if not EUI._prebuilding and EUI.BuildVisOptsCBDropdown then
            local rgn = lineRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local dd, ddRefresh = EUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, LINE_ITEMS,
                function(key) return ns.OwnListGet(key) ~= false end,
                function(key, v) ns.SetOwnListValue(key, v and true or false) end)
            EUI.PanelPP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = dd
            rgn._lastInline = nil
            EUI.RegisterWidgetRefresh(ddRefresh)
        end

        _, h = W:SectionHeader(parent, "MYTHIC+", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Raider.IO Rating Colors",
              tooltip = "Color the leader's rating with Raider.IO's score colors. Otherwise, use the game's rating colors.",
              disabled = function() return not (RaiderIO and RaiderIO.GetScoreColor) end,
              disabledTooltip = "Raider.IO",
              getValue = function() return ns.Cfg().rioRatingColors ~= false end,
              setValue = function(v)
                  ns.Cfg().rioRatingColors = v and true or false
                  if ns.Redecorate then ns.Redecorate() end
              end },
            { type = "slider", text = "Rating Text Size", min = 8, max = 20, step = 1,
              tooltip = "The leader's Mythic+ rating beside the role icons.",
              getValue = function() return ns.OwnListSize("scoreSize") end,
              setValue = function(v) ns.SetOwnListSize("scoreSize", v) end })
        y = y - h

        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
        local function Circle() return ns.OwnListGet("iconShape") ~= "square" end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Icon Shape",
              tooltip = "The member and specialization icon shape.",
              values = { circle = "Circle", square = "Square" }, order = { "circle", "square" },
              getValue = function() return ns.OwnListGet("iconShape") end,
              setValue = function(v) ns.SetOwnListValue("iconShape", v); EUI:RefreshPage(true) end },
            { type = "slider", text = "Role Icon Size", min = 100, max = 160, step = 5,
              tooltip = "Size of the role and specialization icons in the group list.",
              getValue = function() return tonumber(ns.Cfg().iconSize) or ns.DEFAULTS.iconSize end,
              setValue = function(v)
                  ns.Cfg().iconSize = v
                  if ns.Redecorate then ns.Redecorate() end
              end })
        y = y - h
        local texValues, texOrder = EUI.GetBorderTextureDropdown()
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Border Style",
              tooltip = "The border around square icons.",
              values = texValues, order = texOrder,
              disabled = Circle, disabledTooltip = "Icon Shape: Square",
              getValue = function() return ns.OwnListGet("borderTexture") end,
              setValue = function(v)
                  -- a new style starts on its own color
                  ns.SetOwnListValue("borderColor", nil)
                  ns.SetOwnListValue("borderTexture", v)
                  EUI:RefreshPage(true)
              end },
            { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
              tooltip = "In pixels. 0 for no border. Round icons get a ring.",
              getValue = function() return tonumber(ns.OwnListGet("borderSize")) or 0 end,
              setValue = function(v) ns.SetOwnListValue("borderSize", v) end })
        y = y - h
        do
            -- border color swatch
            local rgn = borderRow and borderRow._rightRegion
            if rgn and EUI.BuildColorSwatch then
                local swatch, update = EUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local r, g, b = ns.OwnListBorderColor()
                        return r, g, b, 1
                    end,
                    function(r, g, b)
                        ns.SetOwnListValue("borderColor", { r = r, g = g, b = b })
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = swatch
                if EUI.RegisterWidgetRefresh then EUI.RegisterWidgetRefresh(update) end
            end
        end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Missing Role Icons",
              tooltip = "When there is a missing role, add an icon to show you which one.",
              values = { none = "None", blizzard = "Blizzard", ellesmere = "EllesmereUI" }, order = { "none", "blizzard", "ellesmere" },
              getValue = function() return ns.OwnListGet("missingIcons") end,
              setValue = function(v)
                  ns.SetOwnListValue("missingIcons", v)
                  if ns.Redecorate then ns.Redecorate() end  -- blizzard's list too
              end },
            { type = "toggle", text = "Row Art",
              tooltip = "The instance's art across the left half of each group, fading out to the right.",
              getValue = function() return ns.Cfg().extraRowArt == true end,
              setValue = function(v)
                  ns.Cfg().extraRowArt = v and true or false
                  if ns.GFRetagRows then ns.GFRetagRows() end
              end })
        y = y - h

        _, h = W:SectionHeader(parent, "SIGN UP", y); y = y - h
        local function QuickOn() return EllesmereUIDB and EllesmereUIDB.quickSignup and true or false end
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Quick Signup",
              tooltip = "Hold Shift to keep the note box open when applying.",
              getValue = QuickOn,
              setValue = function(v)
                  EllesmereUIDB.quickSignup = v and true or false
                  if EUI._applyQuickSignup then EUI._applyQuickSignup() end
                  EUI:RefreshPage()
              end },
            { type = "dropdown", text = "Sign Up With",
              tooltip = "How many clicks it takes to sign up to a group.",
              values = { single = "Single-click", double = "Double-click", triple = "Triple-click" },
              order = { "single", "double", "triple" },
              disabled = function() return not QuickOn() end, disabledTooltip = "Quick Signup",
              getValue = function() return ns.OwnListGet("signupClicks") end,
              setValue = function(v) ns.SetOwnListValue("signupClicks", v) end })
        y = y - h

        _, h = W:SectionHeader(parent, "APPLICANT LIST", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Ellesmere Applicant List",
              disabled = ModOff, disabledTooltip = "Group Finder",
              tooltip = "Draws your listed group's applicants with spec, rating and best key columns.",
              getValue = function() return ns.ApplicantListOn() end,
              setValue = function(v) ns.SetOwnListValue("applicantList", v and true or false); EUI:RefreshPage() end },
            { type = "slider", text = "Applicant Row Height", min = 20, max = 64, step = 1,
              tooltip = "How tall each applicant row is.",
              disabled = function() return not ns.ApplicantListOn() end, disabledTooltip = "Ellesmere Applicant List",
              getValue = function() return ns.OwnListGet("applicantRowHeight") or 36 end,
              setValue = function(v) ns.SetOwnListValue("applicantRowHeight", v) end })
        y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Hide Applicant Note",
              tooltip = "Hides the applicant's note, especially helpful if you're a streamer.",
              disabled = function() return not ns.ApplicantListOn() end, disabledTooltip = "Ellesmere Applicant List",
              getValue = function() return ns.OwnListGet("applicantHideNote") == true end,
              setValue = function(v) ns.SetOwnListValue("applicantHideNote", v and true or false) end },
            EUI.BlankRowCfg())
        y = y - h

        local STREAMER_ITEMS = {
            { key = "streamerTitle",   label = "Hide Title",   tooltip = "Covers your group's title with a censor bar." },
            { key = "streamerDungeon", label = "Hide Dungeon", tooltip = "Covers the dungeon and description with a censor bar." },
            { key = "streamerNames",   label = "Class Names",  tooltip = "Shows each applicant's class instead of their name." },
            { key = "streamerRating",  label = "Hide Rating",  tooltip = "Removes the rating column." },
            { key = "streamerSpec",    label = "Hide Spec",    tooltip = "Removes the spec column." },
        }
        _, h = W:SectionHeader(parent, "STREAMER MODE", y); y = y - h
        local streamerRow
        streamerRow, h = W:DualRow(parent, y,
            -- placeholder, the checklist replaces it
            { type = "dropdown", text = "Applicant List",
              tooltip = "What to hide on your listed group's page.",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            EUI.BlankRowCfg())
        y = y - h
        if not EUI._prebuilding and EUI.BuildVisOptsCBDropdown then
            local rgn = streamerRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local dd, ddRefresh = EUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, STREAMER_ITEMS,
                function(key) return ns.OwnListGet(key) == true end,
                function(key, v) ns.SetOwnListValue(key, v and true or false) end,
                nil, nil, nil, nil, nil,
                { disabled = function() return not ns.ApplicantListOn() end, disabledTooltip = "Ellesmere Applicant List" })
            EUI.PanelPP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = dd
            rgn._lastInline = nil
            EUI.RegisterWidgetRefresh(ddRefresh)
        end
        return y
    end

    local function ResetMessage(scope)
        if scope == "session" then return EllesmereUI.L("Reset the session application counts to zero?") end
        if scope == "account" then return EllesmereUI.L("Reset the account application counts to zero?") end
        return EllesmereUI.L("Reset the character application counts to zero?")
    end

    AddAppsSections = function(parent, y)
        local W = EUI.Widgets
        local _, h

        _, h = W:SectionHeader(parent, "APPLICATIONS", y); y = y - h

        local scopeValues = { session = "Session", character = "Character", account = "Account" }
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Applications in Group Finder",
              tooltip="A bar at the top of the Dungeons & Raids sidebar that counts your Mythic+ application results.",
              disabled=ModOff, disabledTooltip="Group Finder",
              getValue=function() return APGet("enabled", false) == true end,
              setValue=function(v) APSet("enabled", v and true or false); EUI:RefreshPage() end },
            { type="dropdown", text="Counts Shown",
              tooltip="Which totals the card shows. Hover the card for all three.",
              values=scopeValues, order={ "session", "character", "account" },
              disabled=APOff, disabledTooltip=APOffTip,
              getValue=function() return APGet("scope", "character") end,
              setValue=function(v) APSet("scope", v) end });  y = y - h

        -- application visibility: which results show on the bar (all on when unset)
        local VIS_LABEL = "Application Visibility"
        local VIS_ITEMS = {
            { key = "showAccepted",  label = "Accepted",  tooltip = "Invites you accepted." },
            { key = "showDeclined",  label = "Declined",  tooltip = "Declined by the leader, the group filled, or the application timed out." },
            { key = "showDelisted",  label = "Delisted",  tooltip = "The group was delisted before answering." },
            { key = "showCancelled", label = "Cancelled", tooltip = "You cancelled the application." },
        }
        -- search only sees labels + tooltips, so this hidden entry carries the
        -- checklist's names
        if EllesmereUI._RegisterSearchEntry then
            local words = {}
            for i = 1, #VIS_ITEMS do
                local label = VIS_ITEMS[i].label
                words[#words + 1] = label
                local loc = EllesmereUI.L(label)
                if loc ~= label then words[#words + 1] = loc end
            end
            local labelLoc = EllesmereUI.L(VIS_LABEL)
            EllesmereUI._RegisterSearchEntry(VIS_LABEL, labelLoc ~= VIS_LABEL and labelLoc or nil,
                table.concat(words, " "), EllesmereUI._buildingModule, EllesmereUI._buildingPage,
                parent._currentSection and parent._currentSection._sectionName)
        end

        -- built-in textures, then sharedmedia's
        local tex, names, order = ns.BarTextureTables()
        local texValues, texOrder = {}, {}
        for _, key in ipairs(order) do
            if key ~= "---" then texValues[key] = names[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = { itemHeight = 28, background = function(key) return tex[key] end }
        local visRow
        visRow, h = W:DualRow(parent, y,
            -- placeholder, the checklist replaces it
            { type="dropdown", text=VIS_LABEL,
              tooltip="Choose which application results show on the bar.",
              disabled=APOff, disabledTooltip=APOffTip,
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="dropdown", text="Bar Texture", values=texValues, order=texOrder,
              disabled=APOff, disabledTooltip=APOffTip,
              getValue=function() return APGet("texture", "none") end,
              setValue=function(v) APSet("texture", v) end });  y = y - h

        if not EUI._prebuilding then
            local rgn = visRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local visDD, visDDRefresh = EUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, VIS_ITEMS,
                function(key) return APGet(key, true) == true end,
                function(key, v) APSet(key, v and true or false) end,
                nil, nil, nil, nil, nil, { disabled = APOff, disabledTooltip = APOffTip })
            EUI.PanelPP.Point(visDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = visDD
            rgn._lastInline = nil
            EUI.RegisterWidgetRefresh(visDDRefresh)
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Title",
              tooltip="The \"M+ Applications\" title above the bar.",
              disabled=APOff, disabledTooltip=APOffTip,
              getValue=function() return APGet("showTitle", true) ~= false end,
              setValue=function(v) APSet("showTitle", v and true or false) end },
            EUI.BlankRowCfg());  y = y - h

        _, h = W:SectionHeader(parent, "RESET APPLICATION COUNTS", y); y = y - h
        local function Reset(label, scope)
            return function()
                EUI:ShowConfirmPopup({
                    title = label,
                    message = ResetMessage(scope),
                    confirmText = "Reset", cancelText = "Cancel",
                    onConfirm = function() ns.ResetApplications(scope) end,
                })
            end
        end
        -- on / off only changes with a reload, so build time is enough
        local offOpts
        if ModOff() then
            local tip = EUI.DisabledTooltip("Group Finder")
            offOpts = { { disabled = true, tooltip = tip }, { disabled = true, tooltip = tip }, { disabled = true, tooltip = tip } }
        end
        _, h = W:WideTripleButton(parent, "Reset Session", "Reset Character", "Reset Account", y,
            Reset("Reset Session", "session"), Reset("Reset Character", "character"), Reset("Reset Account", "account"),
            nil, offOpts)
        y = y - h
        return y
    end

    EUI:RegisterModule(ADDON_NAME, {
        title       = "Group Finder",
        description = "Premade Groups search filters, group list, applicant list and application tools in the Dungeons & Raids window.",
        pages       = { PAGE_SEARCH, PAGE_APPS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_APPS then return BuildAppsPage(parent, yOffset) end
            return BuildSearchPage(pageName, parent, yOffset)
        end,
        onReset     = function()
            ns.ResetSettings()
            if ns.ResetOwnList then ns.ResetOwnList() end
            if ns.Enabled() then
                ns.Search_Layout()
                ns.ApplyApplications()
            end
        end,
    })
end)
-- LoadOnDemand: PLAYER_LOGIN already fired, so run it now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
