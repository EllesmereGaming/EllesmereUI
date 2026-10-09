if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Options.lua
--  Registers the Raid Frames module with EllesmereUI options panel.
--  Two tabs: Raid Frames (layout, health, power, text, border, absorbs,
--  indicators, debuffs, dispels, range/tooltip) and Buff Manager.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIRaidFrames"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

-- WoW Forever: the preview's numbers follow the live frames (EllesmereUI_NumberFormat.lua).
local AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

local PAGE_MAIN = "Frames"
local PAGE_PARTY = "Party"
local PAGE_BUFFS = "Buff Manager"
local PAGE_DM = "Debuff Manager"
local PAGE_CLICKCAST = "HoverCast"

-- Display-only tab labels. Page IDENTITY strings above are baked into nav
-- targets/unlock/overrides/saved state; tab bar renders these instead (see CreateTabButton in EllesmereUI.lua).
EllesmereUI.TAB_LABEL_OVERRIDES = EllesmereUI.TAB_LABEL_OVERRIDES or {}
EllesmereUI.TAB_LABEL_OVERRIDES[PAGE_BUFFS] = "Buffs"
EllesmereUI.TAB_LABEL_OVERRIDES[PAGE_DM] = "Debuffs"

-- Party page under "Frame Style: Party Frames" (the latched stock portrait
-- party frame): the rows its layout replaces are hidden on the Party page
-- only. The page being BUILT decides (BuildVisualSections builds the Frames
-- page too, and the search prebuild can leave the party context stale). ns
-- fields, so no page builder gains an upvalue.
function ns.RF_OptPartyKit()
    return EllesmereUI._buildingPage == PAGE_PARTY and ns.RF_PartyKit ~= nil
        and ns.RF_PartyKit() and true or false
end
function ns.RF_PartyKitGate(cfg)
    if not cfg or not ns.RF_OptPartyKit() then return cfg end
    cfg.disabled        = function() return true end
    cfg.disabledTooltip = "Frame Style: Party Frames"
    cfg.requireState    = "disabled"
    cfg.rawTooltip      = nil
    cfg._blizzGated     = true
    return cfg
end

-- Move Frames button of a Free Move group (Friendly Boss, Extra Frames, Pet Frames): toggles its
-- drag overlay, right-aligned in the DualRow half rgn. opts: isShown() and setShown(show), the
-- overlay; allowed(), whether it can open (Free Move chosen, out of combat); optional enabled()
-- with enabledTip, the group's own switch, which also dims rgn's plain label while off. Nothing is
-- built during the search prebuild; returns the button.
function ns.RF_OptMoveFramesButton(row, rgn, opts)
    if EllesmereUI._prebuilding then return end
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(140, 26)
    btn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 5)
    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
    EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyModuleFont(lbl, nil, 13, "raidFrames")
    lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local enabled = opts.enabled
    local function Update()
        lbl:SetText(opts.isShown() and EllesmereUI.L("Stop Moving") or EllesmereUI.L("Move Frames"))
        btn:SetAlpha(opts.allowed() and 1 or 0.35)
        -- Plain-label slots have no native disabled handling.
        if enabled and rgn._label then rgn._label:SetAlpha(enabled() and 1 or 0.3) end
    end
    btn:SetScript("OnEnter", function(self)
        if enabled and not enabled() then
            EllesmereUI.ShowWidgetTooltip(self, opts.enabledTip)
        elseif not opts.allowed() then
            EllesmereUI.ShowWidgetTooltip(self,
                EllesmereUI.DisabledTooltip("This option requires Position to be set to Free Move"))
        else
            EllesmereUI.ShowWidgetTooltip(self,
                "Drag the overlay to position the frames, then click again to lock")
        end
    end)
    btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    btn:SetScript("OnClick", function()
        if not opts.allowed() then return end
        opts.setShown(not opts.isShown())
        Update()
    end)
    EllesmereUI.RegisterWidgetRefresh(Update)
    Update()
    return btn
end

-- Party page PORTRAIT section (every style; EUI_RaidFrames_Portrait.lua):
-- Portrait Mode | Art Style, then Size | Position and (Detached) Shape |
-- Shape Border. Under "Frame Style: Party Frames" the stock socket takes
-- the Art Style alone (2D or class art). `PSSet` is the Party page's setter
-- (the full party pass, for the box-width changes); every other setting
-- takes the light path. Returns the new y.
function ns.RF_BuildPartyPortrait(parent, y, W, PSSet)
    local db = ns.db
    local kit = ns.RF_OptPartyKit()   -- build time only (the page rebuilds)
    local _, h
    local function PV(k, d)
        local v = db.profile[k]
        if v == nil then return d end
        return v
    end
    local function Refresh()
        if ns._RefreshProxyModes then ns._RefreshProxyModes() end
        if ns.RF_PtRefreshAll then ns.RF_PtRefreshAll() end
        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then ns.ShowPartyPreview() end
    end
    local function PtSet(k, v)
        db.profile[k] = v
        Refresh()
    end
    local function RunWidgetRefresh()
        C_Timer.After(0, function()
            local rl = EllesmereUI._widgetRefreshList
            if rl then for i = 1, #rl do rl[i]() end end
        end)
    end
    local function IsInside(side)
        return side == "insideleft" or side == "insideright" or side == "insidecenter"
    end

    _, h = W:SectionHeader(parent, "PORTRAIT", y); y = y - h

    -- An Art Style pick, with the side effects of leaving and entering 3D
    -- (Inside positions and the None shape are 3D only).
    local function SetArt(v)
        local p = db.profile
        p.partyPortraitMode = v
        if v == "3d" and p.partyPortraitStyle == "detached" then p.partyPortraitShape = "none" end
        if v ~= "3d" then
            if p.partyPortraitShape == "none" then p.partyPortraitShape = "portrait" end
            if IsInside(p.partyPortraitSide) then p.partyPortraitSide = "left" end
        end
        Refresh()
    end

    -- Art Style: 2D, 3D, or class art in one of seven sets (the flyout).
    local classVals = { modern = "Modern", arcade = "Arcade", glyph = "Glyph", legend = "Legend",
        midnight = "Midnight", pixel = "Pixel", pixelsComic = "Pixels Comic", runic = "Runic" }
    local classOrder = { "modern", "arcade", "glyph", "legend", "midnight", "pixel", "pixelsComic", "runic" }
    local artValues = {
        ["3d"] = "3D Portrait",
        ["2d"] = "2D Portrait",
        class = { text = "Class", subnav = { order = classOrder, values = classVals, itemHeight = 32,
            onSelect = function(key)
                db.profile.partyPortraitClassStyle = key
                SetArt("class")
                RunWidgetRefresh()
            end,
            icon = function(key)
                local _, ct = UnitClass("player")
                local c = ct and EllesmereUI.CLASS_ICON_SPRITE_COORDS and EllesmereUI.CLASS_ICON_SPRITE_COORDS[ct]
                if not c then return nil end
                return "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\" .. key .. ".tga",
                    c[1], c[2], c[3], c[4]
            end } },
    }

    -- Row 1: Portrait Mode | Art Style. A mode change can widen the frame
    -- (the full party pass) and shows or hides the rows below (a rebuild).
    _, h = W:DualRow(parent, y,
        ns.RF_PartyKitGate({ type="dropdown", text="Portrait Mode",
          tooltip="Attached widens each frame by the portrait.",
          values={ none = "None", attached = "Attached", detached = "Detached" },
          order={ "none", "attached", "detached" },
          getValue=function()
              if kit then return "attached" end
              return PV("partyPortraitStyle", "none")
          end,
          setValue=function(v)
              local p = db.profile
              local prev = p.partyPortraitStyle or "none"
              if v == prev then return end
              if v == "detached" and (p.partyPortraitMode or "2d") == "3d" then p.partyPortraitShape = "none" end
              if v ~= "detached" then
                  p.partyPortraitSize = 0
                  local sd = p.partyPortraitSide
                  if sd == "top" or IsInside(sd) then p.partyPortraitSide = "left" end
              end
              PSSet("partyPortraitStyle", v)
              EllesmereUI:RefreshPage(true)
          end }),
        { type="dropdown", text="Art Style", values=artValues, order={ "3d", "2d", "class" },
          disabled=function() return not kit and PV("partyPortraitStyle", "none") == "none" end,
          disabledTooltip="Portrait Mode is set to None", rawTooltip=true,
          -- A model cannot take the stock socket's round mask.
          itemDisabled=function(v) return kit and v == "3d" end,
          itemDisabledTooltip=function(v) if v == "3d" then return "Frame Style: Party Frames" end end,
          itemRequireState="disabled",
          getValue=function()
              local m = PV("partyPortraitMode", "2d")
              if m == "class" then return PV("partyPortraitClassStyle", "modern") end
              if kit and m == "3d" then return "2d" end
              return m
          end,
          setValue=function(v)
              if v == "3d" and PV("partyPortraitMode", "2d") ~= "3d"
                  and not (EllesmereUIDB and EllesmereUIDB.dismissed3DWarning) then
                  EllesmereUI:ShowConfirmPopup({
                      title       = "3D Portraits",
                      message     = "3D portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
                      confirmText = "Enable",
                      cancelText  = "Cancel",
                      onConfirm   = function()
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.dismissed3DWarning = true
                          SetArt("3d")
                          EllesmereUI:RefreshPage(true)
                      end,
                      onCancel    = function() EllesmereUI:RefreshPage() end,
                  })
                  return
              end
              SetArt(v)
              RunWidgetRefresh()
          end });  y = y - h

    if kit or PV("partyPortraitStyle", "none") == "none" then return y end

    -- Row 2: Size | Position.
    local sizePosRow
    sizePosRow, h = W:DualRow(parent, y,
        { type="slider", text="Size", min=-50, max=100, step=1,
          disabled=function()
              return PV("partyPortraitStyle", "none") ~= "detached" and not IsInside(PV("partyPortraitSide", "left"))
          end,
          disabledTooltip="Only available in Detached or Inside modes", rawTooltip=true,
          getValue=function() return PV("partyPortraitSize", 0) end,
          setValue=function(v) PtSet("partyPortraitSize", v) end },
        { type="dropdown", text="Position",
          values={ left = "Left", right = "Right", top = "Top",
              insideleft = "Inside Left", insideright = "Inside Right", insidecenter = "Inside Center" },
          order={ "left", "right", "top", "insideleft", "insideright", "insidecenter" },
          itemDisabled=function(v)
              local st = PV("partyPortraitStyle", "none")
              if v == "top" and st == "attached" then return true end
              if IsInside(v) then
                  if PV("partyPortraitMode", "2d") ~= "3d" then return true end
                  if st ~= "detached" then return true end
              end
              return false
          end,
          itemDisabledTooltip=function(v)
              if v == "top" then return "Top position is only available in Detached mode" end
              if IsInside(v) then
                  if PV("partyPortraitMode", "2d") ~= "3d" then return "Inside positions require 3D Art Style" end
                  return "Inside positions require Detached mode"
              end
          end,
          getValue=function() return PV("partyPortraitSide", "left") end,
          setValue=function(v)
              PtSet("partyPortraitSide", v)
              EllesmereUI:RefreshPage()
          end });  y = y - h
    EllesmereUI.BuildInlineCog(sizePosRow._leftRegion, { title = "Portrait Zoom", rows = {
        { type="slider", label="2D Zoom", min=50, max=100, step=1,
          get=function() return PV("partyPortraitArtScale", 100) end,
          set=function(v) PtSet("partyPortraitArtScale", v) end },
        { type="slider", label="3D Zoom", min=100, max=ns.RF_PT_ZOOM3D_MAX, step=1,
          tooltip="Above 300 the camera pulls back to show the whole character.",
          get=function() return PV("partyPortrait3dZoom", 100) end,
          set=function(v) PtSet("partyPortrait3dZoom", v) end },
        { type="slider", label="Character Size", min=50, max=200, step=1,
          tooltip="Scales the 3D character from the portrait's bottom edge, for use with the full-body 3D Zoom range above 300.",
          disabled=function()
              return PV("partyPortraitStyle", "none") ~= "detached" or not IsInside(PV("partyPortraitSide", "left"))
          end,
          disabledTooltip="This option requires an Inside position",
          get=function() return PV("partyPortraitCharScale", 100) end,
          set=function(v) PtSet("partyPortraitCharScale", v) end },
    } })
    EllesmereUI.BuildInlineCog(sizePosRow._rightRegion, { title = "Portrait Position Offsets", rows = {
        { type="slider", label="X Offset", min=-100, max=100, step=1,
          get=function() return PV("partyPortraitX", 0) end,
          set=function(v) PtSet("partyPortraitX", v) end },
        { type="slider", label="Y Offset", min=-100, max=100, step=1,
          get=function() return PV("partyPortraitY", 0) end,
          set=function(v) PtSet("partyPortraitY", v) end },
    }, icon = EllesmereUI.DIRECTIONS_ICON,
    disabled = function() return PV("partyPortraitStyle", "none") ~= "detached" end,
    disabledTooltip = "This option requires Portrait Mode to be set to Detached." })

    if PV("partyPortraitStyle", "none") ~= "detached" then return y end

    -- Row 3 (Detached): Shape | Shape Border (custom colour or class coloured).
    local shapeRow
    shapeRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Shape",
          values={ none = "None", portrait = "Portrait", circle = "Circle", square = "Square",
              csquare = "Rounded Square", diamond = "Diamond", hexagon = "Hexagon", shield = "Shield" },
          order={ "none", "portrait", "circle", "square", "csquare", "diamond", "hexagon", "shield" },
          itemDisabled=function(v) return v == "none" and PV("partyPortraitMode", "2d") ~= "3d" end,
          itemDisabledTooltip=function(v) if v == "none" then return "None shape requires 3D Art Style" end end,
          getValue=function() return PV("partyPortraitShape", "portrait") end,
          setValue=function(v) PtSet("partyPortraitShape", v) end },
        { type="multiSwatch", text="Shape Border",
          swatches = {
            { tooltip = "Custom Color",
              hasAlpha = false,
              getValue = function()
                  local c = db.profile.partyPortraitBorderColor or { r = 0, g = 0, b = 0 }
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  PtSet("partyPortraitBorderColor", { r = r, g = g, b = b })
              end,
              onClick = function(self)
                  if PV("partyPortraitBorderClassColor", true) then
                      PtSet("partyPortraitBorderClassColor", false)
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return PV("partyPortraitBorderClassColor", true) and 0.3 or 1
              end },
            { tooltip = "Class Colored",
              hasAlpha = false,
              getValue = function()
                  local _, ct = UnitClass("player")
                  local c = ct and RAID_CLASS_COLORS[ct]
                  if c then return c.r, c.g, c.b end
                  return 1, 1, 1
              end,
              setValue = function() end,
              onClick = function()
                  PtSet("partyPortraitBorderClassColor", true)
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return PV("partyPortraitBorderClassColor", true) and 1 or 0.3
              end },
          } });  y = y - h
    EllesmereUI.BuildInlineCog(shapeRow._rightRegion, { title = "Shape Border Settings", rows = {
        { type="slider", label="Size", min=1, max=7, step=1,
          get=function() return PV("partyPortraitBorderSize", 7) end,
          set=function(v) PtSet("partyPortraitBorderSize", v) end },
        { type="slider", label="Opacity", min=0, max=100, step=1,
          get=function() return PV("partyPortraitBorderOpacity", 100) end,
          set=function(v) PtSet("partyPortraitBorderOpacity", v) end },
    } })
    return y
end

-- Party page PARTY TARGETS section (every style, not kit-gated): Enable |
-- Include Own Target, then, only while enabled, Fill Color | Background,
-- Width | Height and Position (offsets cog). Party-only keys on db.profile;
-- each setter takes the runtime's own light path (restyle, layout or the
-- include edge), never a party reload. Returns the new y.
function ns.RF_BuildPartyTargets(parent, y, W)
    local db = ns.db
    local BLANK = EllesmereUI.BlankRowCfg
    local _, h, row
    local function PV(k, d)
        local v = db.profile[k]
        if v == nil then return d end
        return v
    end
    -- The party preview draws its own target frames (the real ones are dimmed under it).
    local function Preview()
        if ns.partyPvActive() then ns.ShowPartyPreview() end
    end
    -- Colour and background: the fingerprint-gated restyle and repaint.
    local function PtSet(k, v)
        db.profile[k] = v
        ns.PT_Refresh()
        Preview()
    end
    -- Size, side and offsets: the delta-gated layout (combat-deferred).
    local function LaySet(k, v)
        db.profile[k] = v
        ns._PT_Layout()
        Preview()
    end
    local DARK_TIP = "Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Colors."

    _, h = W:SectionHeader(parent, "PARTY TARGETS", y); y = y - h

    -- Row 1: Enable | Include Own Target. The rows below are HIDDEN while
    -- off, so the flip rebuilds the page.
    local on = db.profile.partyShowTargets == true   -- build time (the page rebuilds)
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Party Targets",
          tooltip="Show a smaller secure target button beside each party frame. Left-click a button to target that party member's current target.",
          getValue=function() return db.profile.partyShowTargets or false end,
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              db.profile.partyShowTargets = v
              ns.PT_SetEnabled(v)
              Preview()
          end) },
        on and { type="toggle", text="Include Own Target",
          tooltip="Also show your own target beside your frame.",
          -- Hide Self leaves no frame of yours to attach to.
          disabled=function() return db.profile.partyHideSelf == true end,
          disabledTooltip="Hide Self", requireState="disabled",
          getValue=function() return db.profile.partyTargetIncludeSelf or false end,
          setValue=function(v)
              db.profile.partyTargetIncludeSelf = v
              ns.PT_SetIncludeSelf(v)
              Preview()
          end }
        or BLANK());  y = y - h

    if not on then return y end

    -- Row 2: Fill Color | Background (the Health Bar row's controls on the
    -- target frames' own keys).
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Fill Color",
          values={ class = "Class Color", dark = "Dark Mode", classic = "Classic", custom = "Custom Color" },
          order={ "class", "dark", "classic", "custom" },
          tooltip="Class Color uses the class color for players and the reaction color for NPCs.",
          getValue=function() return PV("partyTargetHealthColorMode", "class") end,
          setValue=function(v)
              PtSet("partyTargetHealthColorMode", v)
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Background", min=0, max=100, step=1,
          disabled=function() return PV("partyTargetHealthColorMode", "class") == "dark" end,
          disabledTooltip=DARK_TIP, rawTooltip=true,
          getValue=function() return PV("partyTargetBgDarkness", 50) end,
          setValue=function(v) PtSet("partyTargetBgDarkness", v) end });  y = y - h
    -- Custom fill swatch: live only in Custom mode, dimmed and blocked otherwise.
    if not EllesmereUI._prebuilding then
        local rgn = row._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local c = db.profile.partyTargetCustomFillColor
                if c then return c.r, c.g, c.b, 1 end
                return 37/255, 193/255, 29/255, 1
            end,
            function(r, g, b)
                PtSet("partyTargetCustomFillColor", { r=r, g=g, b=b })
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        -- Blocking overlay: non-clickable + tooltip unless Fill Color is Custom.
        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints()
        block:SetFrameLevel(swatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, "Only available with Custom fill color") end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateSwatchVis()
            if PV("partyTargetHealthColorMode", "class") == "custom" then
                swatch:SetAlpha(1); block:Hide()
            else
                swatch:SetAlpha(0.3); block:Show()
            end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateSwatchVis)
        UpdateSwatchVis()
    end
    -- Background Custom + Class swatch pair: clicking either toggles partyTargetBgClassColored, the inactive one dims (mirrors the fill picker).
    if not EllesmereUI._prebuilding then
        local rgn = row._rightRegion
        -- Class swatch shows the player's class color and is not editable.
        local bgClassSwatch = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local _, ct = UnitClass("player")
                local cc = ct and EllesmereUI.GetClassColor(ct)
                if cc then return cc.r, cc.g, cc.b, 1 end
                return 1, 1, 1, 1
            end,
            function() end, false, 20)
        bgClassSwatch:SetScript("OnClick", function()
            PtSet("partyTargetBgClassColored", true)
            EllesmereUI:RefreshPage()
        end)
        bgClassSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSwatch, "Class Colored Background") end)
        bgClassSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        bgClassSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgClassSwatch

        local bgSwatch = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local c = db.profile.partyTargetCustomBgColor
                if c then return c.r, c.g, c.b, 1 end
                return 17/255, 17/255, 17/255, 1
            end,
            function(r, g, b)
                PtSet("partyTargetCustomBgColor", { r=r, g=g, b=b })
            end, false, 20)
        bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
        bgSwatch:SetScript("OnClick", function(self)
            if PV("partyTargetBgClassColored", false) then
                PtSet("partyTargetBgClassColored", false)
                EllesmereUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end)
        bgSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Custom Background Color") end)
        bgSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgSwatch
        -- Blocking overlay spans BOTH swatches: Dark Mode has no background.
        local bgBlock = CreateFrame("Frame", nil, rgn)
        bgBlock:SetPoint("TOPLEFT", bgSwatch, "TOPLEFT", 0, 0)
        bgBlock:SetPoint("BOTTOMRIGHT", bgClassSwatch, "BOTTOMRIGHT", 0, 0)
        bgBlock:SetFrameLevel(bgClassSwatch:GetFrameLevel() + 10)
        bgBlock:EnableMouse(true)
        bgBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, DARK_TIP) end)
        bgBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBgSwatchVis()
            if PV("partyTargetHealthColorMode", "class") == "dark" then
                bgSwatch:SetAlpha(0.3); bgClassSwatch:SetAlpha(0.3); bgBlock:Show()
            else
                bgBlock:Hide()
                local classOn = PV("partyTargetBgClassColored", false)
                bgSwatch:SetAlpha(classOn and 0.3 or 1)
                bgClassSwatch:SetAlpha(classOn and 1 or 0.3)
            end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatchVis)
        UpdateBgSwatchVis()
    end

    -- Row 3: Width | Height (absolute, not scaled with the party frames).
    _, h = W:DualRow(parent, y,
        { type="slider", text="Width", min=20, max=300, step=1,
          getValue=function() return PV("partyTargetWidth", 70) end,
          setValue=function(v) LaySet("partyTargetWidth", v) end },
        { type="slider", text="Height", min=10, max=150, step=1,
          getValue=function() return PV("partyTargetHeight", 33) end,
          setValue=function(v) LaySet("partyTargetHeight", v) end });  y = y - h

    -- Row 4: Position (+ offsets cog). Shows the side the frames actually
    -- take (the Horizontal Frames setter's refresh re-reads it); a pick of
    -- the side an unset Position shows (the kit's move included) is stored
    -- as unset, so it keeps following the layout and the frame style.
    -- Under the Party Frames kit the stacked frames' buff side is taken.
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Position",
          tooltip="Right by default, or Bottom with Horizontal Frames. With Frame Style: Party Frames, the side holding the buffs is not available.",
          values={ top = "Top", bottom = "Bottom", left = "Left", right = "Right" },
          order={ "top", "bottom", "left", "right" },
          itemDisabled=function(v)
              local p = db.profile
              if p.partyHorizontal or not ns.RF_PartyKit() then return false end
              local m = ns.RF_KitBuffMode(p)
              return (m == "RIGHT" and v == "right") or (m == "LEFT" and v == "left")
          end,
          itemDisabledTooltip=function(v)
              if v == "left" or v == "right" then return "Frame Style: Party Frames" end
          end,
          itemRequireState="disabled",
          getValue=function() return ns.PT_ShownSide() end,
          setValue=function(v)
              LaySet("partyTargetPosition", (v ~= ns.PT_ShownSide(true)) and v or nil)
          end },
        BLANK());  y = y - h
    EllesmereUI.BuildInlineCog(row._leftRegion, { title = "Target Position Offsets", rows = {
        { type="slider", label="X Offset", min=-100, max=100, step=1,
          get=function() return PV("partyTargetOffsetX", 0) end,
          set=function(v) LaySet("partyTargetOffsetX", v) end },
        { type="slider", label="Y Offset", min=-100, max=100, step=1,
          get=function() return PV("partyTargetOffsetY", 0) end,
          set=function(v) LaySet("partyTargetOffsetY", v) end },
    }, icon = EllesmereUI.DIRECTIONS_ICON })
    return y
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    ns._InitEUIModule = function()
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not ns.db then return end

    local PP = EllesmereUI.PanelPP
    local db = ns.db
    local ReloadFrames = ns.ReloadFrames
    local floor = math.floor


    ---------------------------------------------------------------------------
    --  Shared helpers
    ---------------------------------------------------------------------------
    local GetFFD = ns.GetFFD

    local function ReloadAndUpdate()
        if ReloadFrames then ReloadFrames() end
        -- Preview refresh keeps health values, updates layout/colors.
        if ns.previewActive and ns.previewActive() and ns.ShowPreview then
            ns.ShowPreview()
        end
        if ns._sizePreviewTier and ns._ShowSizePreview then
            ns._ShowSizePreview(ns._sizePreviewTier)
        end
        if ns.RefreshPvAuraVisuals then ns.RefreshPvAuraVisuals() end
        -- Party frames share all settings except width/height.
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
            ns.ShowPartyPreview()
        end
    end

    ---------------------------------------------------------------------------
    --  Context-aware settings helpers
    --  With _partyCtx true (party tab), reads/writes go to "party_<key>" with
    --  fallthrough to raid values, so ONE set of page builders serves both tabs.
    ---------------------------------------------------------------------------
    -- Mutable state shared with the page builders under RaidFrames_Options\.
    -- A table instead of locals so every file reads and writes the live value.
    -- _partyCtx: true while building/interacting on the party tab.
    local optState = { _partyCtx = false }
    local PARTY_KEY_SECTION = ns._PARTY_KEY_SECTION or {}
    local IsPartySectionCustom = ns._IsPartySectionCustom

    local function SGet(key)
        if optState._partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            local pv = db.profile["party_" .. key]
            if pv ~= nil then return pv end
        end
        return db.profile[key]
    end
    local function SSet(key, val)
        if optState._partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            db.profile["party_" .. key] = val
        else
            db.profile[key] = val
        end
        if ns._BumpAbsorbGen then ns._BumpAbsorbGen() end
        ReloadAndUpdate()
    end
    local function SVal(key, default)
        if optState._partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            local pv = db.profile["party_" .. key]
            if pv ~= nil then return pv end
        end
        local v = db.profile[key]
        if v ~= nil then return v end
        return default
    end
    -- Context-aware direct write, for color swatches that bypass SSet.
    local function SWrite(key, val)
        if optState._partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            db.profile["party_" .. key] = val
        else
            db.profile[key] = val
        end
        if ns._BumpAbsorbGen then ns._BumpAbsorbGen() end
    end
    -- A border's exact-size companion (<sib>Px) is ONE setting with its legacy
    -- sibling, the party proxy's rule: on the party tab a stored party sibling
    -- carries only the party companion (nil included), never the raid one.
    local function SGetPx(key, sib)
        if optState._partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key])
           and db.profile["party_" .. sib] ~= nil then
            return db.profile["party_" .. key]
        end
        return SGet(key)
    end

    -- WoW Forever: the Missing Buffs icons' glow (prefix keys missingBuffsGlow*)
    -- as a shared glow descriptor over a read/write pair -- the page's context-
    -- aware SVal/SWrite in the indicator's cog, the raid keys on Global
    -- Settings > Glows (built outside any tab, so never through the tab context).
    local MissingGlowDesc
    if EllesmereUI.IS_FOREVER then
        local GK = EllesmereUI.Glows.PrefixKeys("missingBuffsGlow")
        function MissingGlowDesc(read, write)
            return {
                host = "icon", excludes = { [4] = true },
                caps = { mode = true, params = true, bg = true },
                defaultColor = EllesmereUI.Glows.DEFAULT_COLOR,
                onChange = ReloadAndUpdate,
                disabled = function() return read("showMissingBuffs", true) == false end,
                disabledTooltip = "Missing Buffs",
                get = function(f)
                    if f == "style" then return read(GK.type, 2)
                    elseif f == "mode" then return read(GK.mode, "default")
                    elseif f == "color" then return read(GK.r), read(GK.g), read(GK.b)
                    elseif f == "lines" then return read(GK.lines)
                    elseif f == "thickness" then return read(GK.th)
                    elseif f == "speed" then return read(GK.speed)
                    elseif f == "bg" then return read(GK.bg) == true
                    elseif f == "bgColor" then return read(GK.bgR), read(GK.bgG), read(GK.bgB)
                    end
                end,
                set = function(f, a, b, c)
                    if f == "style" then write(GK.type, a)
                    elseif f == "mode" then write(GK.mode, a)
                    elseif f == "color" then write(GK.r, a); write(GK.g, b); write(GK.b, c)
                    elseif f == "lines" then write(GK.lines, a)
                    elseif f == "thickness" then write(GK.th, a)
                    elseif f == "speed" then write(GK.speed, a)
                    elseif f == "bg" then write(GK.bg, a and true or nil)
                    elseif f == "bgColor" then write(GK.bgR, a); write(GK.bgG, b); write(GK.bgB, c)
                    end
                end,
            }
        end
        EllesmereUI.GlowOptions.RegisterSite({ id = "rf_missing_buffs", label = "Missing Buffs Glow",
            group = "module", module = "EllesmereUIRaidFrames", page = PAGE_MAIN,
            section = "INDICATORS", highlight = "Missing Buffs",
            desc = MissingGlowDesc(
                function(key, default)
                    local v = db.profile[key]
                    if v == nil then return default end
                    return v
                end,
                function(key, v) db.profile[key] = v end) })
    end

    ---------------------------------------------------------------------------
    --  Health bar texture dropdown
    ---------------------------------------------------------------------------
    -- Re-append post-login: the OnInitialize append runs too early to catch most
    -- SM texture providers, which register after our ADDON_LOADED.
    EllesmereUI.AppendSharedMediaTextures(
        ns.healthBarTextureNames or {},
        ns.healthBarTextureOrder or {},
        nil,
        ns.healthBarTextures
    )

    local hbtValues = {}
    local hbtOrder = {}
    do
        local texNames = ns.healthBarTextureNames or {}
        local texOrder2 = ns.healthBarTextureOrder or {}
        local texLookup = ns.healthBarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                hbtValues[key] = texNames[key] or key
            end
            hbtOrder[#hbtOrder + 1] = key
        end
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return texLookup[key] end,
        }
    end

    ---------------------------------------------------------------------------
    --  Value tables for dropdowns
    ---------------------------------------------------------------------------
    local healthColorValues = {
        ["class"]         = "Class Color",
        ["classReactive"] = "Class Color Reactive",
        ["dark"]          = "Dark Mode",
        ["classic"]       = "Classic",
        ["custom"]        = "Custom Color",
        ["customDynamic"] = "Custom Dynamic Colors",
    }
    local healthColorOrder = { "class", "classReactive", "dark", "classic", "custom", "customDynamic" }

    local namePositionValues = EllesmereUI.POSITION_GRID_VALUES
    local namePositionOrder = EllesmereUI.POSITION_GRID_ORDER

    -- Name Position adds "None" (hides the name); Health Text Position reuses these base tables, so keep "None" out of the shared set.
    local namePositionValuesName = EllesmereUI.POSITION_GRID_VALUES_NONE
    local namePositionOrderName = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright", "none" }

    local healthTextValues = {
        ["none"]          = "None",
        ["percent"]       = "Percent",
        ["percentNoSign"] = "Percent (No Sign)",
        ["number"]        = "Number",
        ["numberPercent"] = "Number | Percent",
        ["percentNumber"] = "Percent | Number",
        ["missing"]       = "Missing Number",
    }
    local healthTextOrder = { "none", "percent", "percentNoSign", "number", "numberPercent", "percentNumber", "missing" }

    local absorbStyleValues = {
        ["none"]            = "None",
        ["striped"]         = "Striped",
        ["stripedReversed"] = "Striped Reversed",
        ["stripedThick"]    = "Striped Thick",           -- striped-thick.png
        ["stripedThickR"]   = "Striped Thick Reversed",  -- striped-thick-r.png
        ["clean"]           = "Clean (Flat)",
        ["blizzard"]        = "Classic WoW",          -- DB key stays "blizzard"; label only
        ["blizzardModern"]  = "Default Blizz Frames", -- compound: solid base + tiled stripes (shield only)
        ["healBlizzModern"] = "Default Blizz Frames", -- heal-absorb only: louis-absorb.png texture
        ["largeOutlinedStripes"]  = "Large Outlined Stripes",  -- heal-absorb only: large-habsorb-left.png
        ["largeOutlinedStripesR"] = "Large Outlined Stripes R", -- heal-absorb only: large-habsorb-right.png
        ["largeStripes"]          = "Large Stripes",            -- large-absorb-left.png
        ["largeStripesR"]         = "Large Stripes R",          -- large-absorb-right.png
        ["maxHealthStripes"]      = "Max Health Stripes",       -- reduced max-health overlay
        -- The native raid fill (the shared-media copy dedupes against it).
        ["blizzardRaid"]          = "Blizzard Raid Bar",
        ["pixelsShield"]          = "Pixels Shield",            -- pixels-shield.tga
        ["pixelsShieldEdge"]      = "Pixels Shield Edge",       -- shield-only: pixels-shield-edge.tga
        ["pixelsShieldFill"]      = "Pixels Shield Fill",       -- shield-only: pixels-shield-fill.tga (tiled)
    }
    -- Shield absorb shows every style including Blizzard (Modern).
    local absorbStyleOrder = { "none", "blizzardModern", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeStripes", "largeStripesR", "blizzardRaid", "pixelsShield", "pixelsShieldEdge", "pixelsShieldFill" }
    -- Heal absorb shares the values table but EXCLUDES Blizzard (Modern).
    local healAbsorbStyleOrder = { "none", "healBlizzModern", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR", "blizzardRaid", "pixelsShield" }
    -- Max Health mirrors Heal Absorb plus "Max Health Stripes" first.
    local maxHealthStyleOrder = { "none", "maxHealthStripes", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "healBlizzModern", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR", "blizzardRaid", "pixelsShield" }
    -- Appends SharedMedia statusbar textures after a divider (mirrors Bar Texture dropdown). "sm:" keys land in the shared health-bar tables via AppendSharedMediaTextures; resolution flows through ns.ResolveAbsorbStyleTex -> health-bar lookup.
    -- All three dropdowns share absorbStyleValues, so each gains the SM entries and preview swatch.
    do
        EllesmereUI.AppendSharedMediaTextures(
            ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
        local smNames = ns.healthBarTextureNames or {}
        local smKeys = {}
        for _, k in ipairs(ns.healthBarTextureOrder or {}) do
            if type(k) == "string" and k:find("^sm:") then
                smKeys[#smKeys + 1] = k
                absorbStyleValues[k] = smNames[k] or k
            end
        end
        if #smKeys > 0 then
            for _, ord in ipairs({ absorbStyleOrder, healAbsorbStyleOrder, maxHealthStyleOrder }) do
                ord[#ord + 1] = "---"
                for _, k in ipairs(smKeys) do ord[#ord + 1] = k end
            end
        end
        -- Preview swatch behind each row via ns.ResolveAbsorbStyleTex. Default Blizz
        -- Frames draws its in-game compound: tinted tiled stripes over the solid base
        -- (ns.ApplyModernAbsorbBar / the _modernBase colour).
        local modernSwatch = { base = { 0.776, 0.784, 1.0 }, tint = { 0.569, 0.588, 1.0 }, tile = true }
        absorbStyleValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" or key == "none" then return nil end
                if key == "blizzardModern" then return ns.ResolveAbsorbStyleTex("striped"), modernSwatch end
                if key == "maxHealthStripes" then return "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png" end
                return ns.ResolveAbsorbStyleTex and ns.ResolveAbsorbStyleTex(key) or nil
            end,
        }
    end

    local growthValues = {
        DOWN  = "Down",
        UP    = "Up",
        RIGHT = "Right",
        LEFT  = "Left",
    }
    local allGrowthOrder        = { "DOWN", "UP", "RIGHT", "LEFT" }

    -- Group Growth additionally offers the grid flow: ns._RF_GRID_ROWS groups
    -- stack down the first column (G1 above G2) before the next column starts to
    -- the right (G3 above G4) -- a 2x2 raid block instead of one long run. Unit
    -- Growth has no such mode: a header's children only ever run along one axis.
    local groupGrowthValues = {
        DOWN      = "Down",
        UP        = "Up",
        RIGHT     = "Right",
        LEFT      = "Left",
        DOWNRIGHT = "Down and then Right",
    }
    local groupGrowthOrder  = { "DOWN", "UP", "RIGHT", "LEFT", "DOWNRIGHT" }

    -- Merge Groups renders through Blizzard's flat header, which has a single
    -- column axis and cannot wrap into a grid, so the grid flow degrades to the
    -- plain RIGHT run there (same self-heal as ns._RFEffectiveGrowth in the
    -- runtime). Report what actually renders instead of showing a value the
    -- merged grid ignores.
    local function ReadGroupGrowth(v)
        if v == "DOWNRIGHT" and SVal("mergeGroups", false) then return "RIGHT" end
        return v
    end

    -- ns._RFGrowthIsVertical is the runtime module's single source of truth for
    -- this check (EUI_RaidFrames_Reload.lua); reuse it here rather than a second copy.
    local GrowthIsVertical = ns._RFGrowthIsVertical

    -- Merge Groups renders through Blizzard's flat SecureGroupHeader, whose column
    -- axis (columnAnchorPoint) is always perpendicular to Unit Growth -- a same-axis
    -- Group Growth has no valid column direction, so the runtime silently substitutes
    -- an unrelated one instead of honoring it. Bump the OTHER axis to a perpendicular
    -- value instead of letting an unrenderable pair through, mirroring the Spell
    -- Name/Spell Target side-conflict rule used elsewhere in these options.
    local function KeepGrowthPerpendicular(newVal, getOther, setOther)
        local other = getOther()
        if GrowthIsVertical(newVal) == GrowthIsVertical(other) then
            setOther(GrowthIsVertical(newVal) and "RIGHT" or "DOWN")
        end
    end

    -- Every preview mode dropdown across tabs; all refresh when one changes.
    local pvModeDropdowns = {}

    -- Preview Mode controls carrying override-preview chrome (gold border host
    -- + tooltip), one entry per built row across tabs/rebuilds.
    local pvModeCtrls = {}

    -- Gold border + tooltip on every Preview Mode control while the REAL preview renders an override's effective values (spec group or applied conditional). State comes from the runtime resolvers, NEVER the panel's view flags, so it always matches what the real preview shows.
    -- Recomputed at row build time and from ns._RebuildPvOverlay (view/spec/conditional changes).
    function ns._UpdatePvModeChrome()
        if #pvModeCtrls == 0 then return end
        local text
        if (db.profile.previewMode or "overlay") == "real" then
            -- Editing-as session: preview shows THAT session's values (effective overlay off there by design), so name it.
            local sessName = EllesmereUI.SpecOverrides_EditSessionName()
            if sessName then
                text = EllesmereUI.Lf("Previewing Override: %1$s", sessName)
            elseif EllesmereUI.SpecOverrides_PeekEffectiveValues then
                local _, specSrc, condSrc =
                    EllesmereUI.SpecOverrides_PeekEffectiveValues("EllesmereUIRaidFrames")
                if specSrc and condSrc then
                    text = EllesmereUI.Lf("Previewing Overrides: %1$s, %2$s", specSrc, condSrc)
                elseif specSrc or condSrc then
                    text = EllesmereUI.Lf("Previewing Override: %1$s", specSrc or condSrc)
                end
            end
        end
        for _, e in ipairs(pvModeCtrls) do
            if e.gold then e.gold:SetShown(text ~= nil) end
            if e.ctrl then
                e.ctrl._ttText = text
                e.ctrl._ttOpts = nil
            end
        end
    end

    -- True when preview is disabled; eyeball toggles gray out.
    local function IsPreviewOff()
        return (db.profile.previewMode or "overlay") == "none"
    end

    -- Builds the "Preview Mode" row at the top of a page; returns the new y.
    local function BuildPreviewModeRow(parent, y)
        local ROW_H = 50
        local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local contentPad = EllesmereUI.CONTENT_PAD or 45

        y = y - 10
        local modeRow = CreateFrame("Frame", nil, parent)
        PP.Size(modeRow, parent:GetWidth() - contentPad * 2, ROW_H)
        PP.Point(modeRow, "TOPLEFT", parent, "TOPLEFT", contentPad, y)
        y = y - ROW_H

        local modeLabel = modeRow:CreateFontString(nil, "OVERLAY")
        EllesmereUI.ApplyModuleFont(modeLabel, fontPath, 14, "raidFrames")
        modeLabel:SetPoint("TOP", modeRow, "TOP", 0, 0)
        modeLabel:SetText(EllesmereUI.L("Preview Mode"))
        modeLabel:SetTextColor(1, 1, 1, 0.6)

        local previewModeValues = {
            real    = "Real Preview",
            overlay = "Overlay Preview",
            none    = "No Preview",
        }
        local previewModeOrder = { "real", "overlay", "none" }
        local ddCtrl, ddLbl = EllesmereUI.BuildDropdownControl(
            modeRow, 180, modeRow:GetFrameLevel() + 2,
            previewModeValues, previewModeOrder,
            function() return db.profile.previewMode or "overlay" end,
            function(v)
                db.profile.previewMode = v
                -- Apply to whichever preview the current tab owns.
                local page = EllesmereUI:GetActivePage()
                if page == PAGE_PARTY then
                    if v == "none" then
                        if ns.HidePartyPreview then ns.HidePartyPreview() end
                    else
                        if ns.HidePreview then ns.HidePreview() end
                        if ns.ShowPartyPreview then ns.ShowPartyPreview() end
                    end
                else
                    if ns.ApplyPreviewMode then ns.ApplyPreviewMode() end
                    if ns.HidePartyPreview then ns.HidePartyPreview() end
                end
                for _, syncLbl in ipairs(pvModeDropdowns) do
                    syncLbl:SetText(previewModeValues[v] or v)
                end
                EllesmereUI:RefreshPage()
            end)
        ddCtrl:SetPoint("TOP", modeLabel, "BOTTOM", 0, -9)

        pvModeDropdowns[#pvModeDropdowns + 1] = ddLbl

        -- Override-preview chrome lives on a SEPARATE gold border host: the control's own border is re-asserted by its hover scripts, so never recolor it directly (same pattern as the overrides UI slot marks).
        do
            local gold = EllesmereUI._SPECOV_GOLD or { 199 / 255, 166 / 255, 90 / 255 }
            local host = CreateFrame("Frame", nil, ddCtrl)
            host:SetAllPoints(ddCtrl)
            host:SetFrameLevel(ddCtrl:GetFrameLevel() + 30)
            EllesmereUI.PP.CreateBorder(host, gold[1], gold[2], gold[3], 0.9, 1, "OVERLAY", 7)
            host:Hide()
            pvModeCtrls[#pvModeCtrls + 1] = { ctrl = ddCtrl, gold = host }
        end
        if ns._UpdatePvModeChrome then ns._UpdatePvModeChrome() end

        ns._previewMode = db.profile.previewMode or "overlay"
        return y
    end


    ---------------------------------------------------------------------------
    --  Visual settings sections (shared by raid + party pages)
    ---------------------------------------------------------------------------
    local function BuildVisualSections(parent, y, W, onSection)
        -- Eyeball handles are per-context (raid vs party) so the two page builds don't clobber each other's eye-icon refreshers. Animation start/stop stay on ns: one shared ticker resolves the active preview at call time via ns.PvActiveFrames.
        local _eyeCtx = optState._partyCtx and "party" or "raid"
        ns._eye = ns._eye or {}
        ns._eye[_eyeCtx] = ns._eye[_eyeCtx] or {}
        local EYE = ns._eye[_eyeCtx]
        -- The sections live in RaidFrames_Options\VisualBars_Options.lua (HEALTH BAR ..
        -- TEXT DISPLAY) and VisualIndicators_Options.lua (INDICATORS .. RANGE & TOOLTIP);
        -- Dispels reuses the Health Bar custom-border gates.
        local CustomBorderOff, CustomBorderOffTip
        y, CustomBorderOff, CustomBorderOffTip = ns.RFO_BuildVisualBars(parent, y, W, onSection, EYE)
        y = ns.RFO_BuildVisualIndicators(parent, y, W, onSection, EYE, CustomBorderOff, CustomBorderOffTip)
        return y
    end

    ---------------------------------------------------------------------------
    --  Buff Manager page (placeholder)
    ---------------------------------------------------------------------------
    local function BuildBuffManagerPage(pageName, parent, yOffset)
        -- Buff Manager v2 runs INSIDE the legacy page shell.
        -- The from-scratch replacement page was rejected in field review and is not routed to; do not wire it up.
        if ns.BM_BuildPage then
            return ns.BM_BuildPage(pageName, parent, yOffset)
        end
        return math.abs(yOffset)
    end

    ---------------------------------------------------------------------------
    --  Test Mode (global preview with all toggleable elements)
    ---------------------------------------------------------------------------
    local testModeFrame = nil
    local testModeActive = false

    local function CloseTestMode()
        testModeActive = false
        ns._testMode = false
        if testModeFrame then
            testModeFrame:SetAlpha(1)
            local fadeOutAG = testModeFrame:CreateAnimationGroup()
            local fadeOutA = fadeOutAG:CreateAnimation("Alpha")
            fadeOutA:SetFromAlpha(1); fadeOutA:SetToAlpha(0); fadeOutA:SetDuration(0.3)
            testModeFrame:SetAlpha(0)
            fadeOutAG:SetScript("OnFinished", function() testModeFrame:Hide() end)
            fadeOutAG:Play()
        end
        ns._indicatorsVisible = false
        ns._dispelsVisible = false
        ns._defensivesPreviewVisible = false
        ns._debuffsPreviewVisible = false
        if ns._stopHealthAnim and ns._healthAnimActive then ns._stopHealthAnim() end
        ns._healthAnimActive = false
        ns._bmFrameEffectsVisible = false
        ns._testReducedMaxHealth = false
        ns._testAbsorbs = nil
        ns._testHealAbsorbs = nil
        ns._testHealPrediction = nil
        ns._testThreat = nil
        ns._testBuffsVisible = false
        if ns.StopPvBuffTicker then ns.StopPvBuffTicker() end
        -- Hide the container immediately; the dimmer fade masks it.
        if ns._overlayContainer then ns._overlayContainer:Hide() end
        if ns.HidePreview then ns.HidePreview() end
        local activePage = EllesmereUI:GetActivePage()
        if activePage == PAGE_MAIN then
            local mode = db.profile.previewMode or "overlay"
            if mode ~= "none" and ns.ShowPreview then
                C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
            end
        end
    end

    local function OpenTestMode()
        if testModeActive then CloseTestMode(); return end
        testModeActive = true
        ns._testMode = true

        local PP = EllesmereUI.PanelPP or EllesmereUI.PP
        local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local accentColor = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local s = db.profile

        if not testModeFrame then
            testModeFrame = CreateFrame("Frame", nil, UIParent)
            testModeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            testModeFrame:SetAllPoints()
            testModeFrame:EnableMouse(true)
            local dimBg = testModeFrame:CreateTexture(nil, "BACKGROUND")
            dimBg:SetAllPoints(); dimBg:SetColorTexture(0, 0, 0, 0.75)
        end
        testModeFrame:SetFrameLevel(50)
        testModeFrame:SetAlpha(0)
        testModeFrame:Show()

        for _, c in ipairs({testModeFrame:GetChildren()}) do c:Hide(); c:SetParent(nil) end

        -- Preview flags are set by ns._applyTestState() below.
        local fadeInAG = testModeFrame:CreateAnimationGroup()
        local fadeInA = fadeInAG:CreateAnimation("Alpha")
        fadeInA:SetFromAlpha(0); fadeInA:SetToAlpha(1); fadeInA:SetDuration(0.3)
        testModeFrame:SetAlpha(1)
        fadeInAG:Play()

        -- Force the preview up; ns._testMode forces overlay mode.
        if ns.HidePreview then ns.HidePreview() end
        C_Timer.After(0, function()
            if ns.ShowPreview and ns._testMode then
                ns.ShowPreview()
                -- Re-apply now that preview frames exist and previewActive is true.
                if ns._applyTestState then ns._applyTestState() end
                -- Reanchor + fade in the sidebar once the container is placed.
                C_Timer.After(0, function()
                    if not ns._testMode then return end
                    local oc = ns._overlayContainer
                    if oc and oc:IsShown() and ns._testPanel then
                        ns._testPanel:ClearAllPoints()
                        ns._testPanel:SetPoint("RIGHT", oc, "LEFT", -20, 0)
                        ns._testPanel:SetAlpha(0)
                        ns._testPanel:Show()
                        local panelFadeAG = ns._testPanel:CreateAnimationGroup()
                        local panelFadeA = panelFadeAG:CreateAnimation("Alpha")
                        panelFadeA:SetFromAlpha(0); panelFadeA:SetToAlpha(1); panelFadeA:SetDuration(0.3)
                        ns._testPanel:SetAlpha(1)
                        panelFadeAG:Play()
                    end
                end)
            end
        end)

        local PANEL_W = 260
        local ROW_H = 32
        local PAD = 16
        local panel = CreateFrame("Frame", nil, testModeFrame)
        ns._testPanel = panel
        panel:SetSize(PANEL_W, 600)
        panel:SetPoint("LEFT", testModeFrame, "LEFT", 40, 0)
        panel:Hide()  -- shown once the overlay container is positioned
        panel:SetFrameLevel(testModeFrame:GetFrameLevel() + 5)
        local panelBg = panel:CreateTexture(nil, "BACKGROUND")
        panelBg:SetAllPoints(); panelBg:SetColorTexture(17/255, 15/255, 12/255, 0.9)
        EllesmereUI.MakeBorder(panel, 1, 1, 1, 0.1, PP)

        local function MakeFont(p, size, r, g, b, a)
            local fs = p:CreateFontString(nil, "OVERLAY")
            EllesmereUI.PrimeFontShadow(fs, true)
            fs:SetFont(fontPath, size, "")
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        local cy = -PAD

        local function SectionHeader(text)
            cy = cy - 10
            local lbl = MakeFont(panel, 11, 1, 1, 1, 0.75)
            lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, cy)
            lbl:SetText(EllesmereUI.L(text))
            local line = panel:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            line:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
            line:SetColorTexture(1, 1, 1, 0.06)
            cy = cy - 15
        end

        -- Every checkbox refresher, re-run together for mutual exclusion.
        local allRefreshFns = {}
        local editGlow   -- shared edit-target glow, made on first use

        local function CheckboxRow(label, getVal, setVal, editTarget)
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(PANEL_W - PAD * 2, ROW_H)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, cy)
            row:SetFrameLevel(panel:GetFrameLevel() + 1)

            local cb = CreateFrame("CheckButton", nil, row)
            cb:SetSize(18, 18)
            cb:SetPoint("LEFT", row, "LEFT", 0, 0)

            local cbBg = cb:CreateTexture(nil, "BACKGROUND")
            cbBg:SetAllPoints(); cbBg:SetColorTexture(0.15, 0.15, 0.15, 1)
            EllesmereUI.MakeBorder(cb, 1, 1, 1, 0.2, PP)

            local checkMark = cb:CreateTexture(nil, "OVERLAY")
            checkMark:SetSize(12, 12)
            checkMark:SetPoint("CENTER")
            checkMark:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)

            local function Refresh()
                local v = getVal()
                checkMark:SetShown(v)
            end
            Refresh()

            local function DoToggle()
                setVal(not getVal())
                for _, fn in ipairs(allRefreshFns) do fn() end
                if ns._applyTestState then ns._applyTestState() end
                if ns.ShowPreview then ns.ShowPreview() end
            end

            cb:SetScript("OnClick", DoToggle)

            -- Label is clickable and toggles the checkbox.
            local lblBtn = CreateFrame("Button", nil, row)
            lblBtn:SetPoint("LEFT", cb, "RIGHT", 8, 0)
            lblBtn:SetPoint("RIGHT", row, "RIGHT", -50, 0)
            lblBtn:SetHeight(ROW_H)
            lblBtn:SetScript("OnClick", DoToggle)
            local lbl = MakeFont(lblBtn, 11, 1, 1, 1, 0.85)
            lbl:SetPoint("LEFT")
            lbl:SetText(EllesmereUI.L(label))

            if editTarget then
                local editBtn = CreateFrame("Button", nil, row)
                editBtn:SetSize(43, 22)
                editBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                editBtn:SetFrameLevel(row:GetFrameLevel() + 1)
                local eBg = editBtn:CreateTexture(nil, "BACKGROUND")
                eBg:SetAllPoints(); eBg:SetColorTexture(1, 1, 1, 0.05)
                local eLbl = MakeFont(editBtn, 10, 1, 1, 1, 0.4)
                eLbl:SetPoint("CENTER"); eLbl:SetText(EllesmereUI.L("Edit"))
                editBtn:SetScript("OnEnter", function()
                    eBg:SetColorTexture(1, 1, 1, 0.1); eLbl:SetAlpha(0.7)
                end)
                editBtn:SetScript("OnLeave", function()
                    eBg:SetColorTexture(1, 1, 1, 0.05); eLbl:SetAlpha(0.4)
                end)
                editBtn:SetScript("OnClick", function()
                    CloseTestMode()
                    if editTarget.page then
                        EllesmereUI:SelectPage(editTarget.page)
                        -- Scroll to + highlight the target row once the page builds.
                        if editTarget.key then
                            C_Timer.After(0.1, function()
                                local target = ns._editTargets and ns._editTargets[editTarget.key]
                                if not target then return end
                                local sf = EllesmereUI._scrollFrame
                                if sf then
                                    local _, _, _, _, rowY = target:GetPoint(1)
                                    if rowY then
                                        local scrollPos = math.max(0, math.abs(rowY) - 40)
                                        if EllesmereUI.SmoothScrollTo then EllesmereUI.SmoothScrollTo(scrollPos) end
                                    end
                                end
                                C_Timer.After(0.15, function()
                                    if not target:IsShown() then return end
                                    editGlow = editGlow or EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })
                                    editGlow(target)
                                end)
                            end)
                        end
                    end
                end)
            end

            cy = cy - ROW_H
            allRefreshFns[#allRefreshFns + 1] = Refresh
            return cb, Refresh, row
        end

        local nonIndicatorRows = {}

        -- Test mode toggle state persists across open/close within a session.
        if not ns._testState then
            local specIdx = GetSpecialization and GetSpecialization()
            local specRole = specIdx and GetSpecializationRole and GetSpecializationRole(specIdx)
            ns._testState = {
                animateBars = false,
                absorbs = s.absorbStyle ~= "none",
                healAbsorbs = (s.healAbsorbStyle or "clean") ~= "none",
                healPrediction = s.healPrediction == true,
                threat = (s.threatBorderSize or 0) > 0 or (s.threatCustomBorder == true and ns.RF_CustomBorderOn(s)),
                reducedMaxHealth = false,
                dispels = false,
                debuffs = s.debuffFilter ~= "none",
                defensives = s.showDefensives or s.showExternals or false,
                buffs = true,
                indicators = false,
            }
        end
        local testState = ns._testState

        ns._applyTestState = function()
            local indOn = testState.indicators
            ns._indicatorsVisible = indOn
            -- Indicators suppress every other preview WITHOUT altering testState.
            ns._dispelsVisible = not indOn and testState.dispels
            ns._debuffsPreviewVisible = not indOn and testState.debuffs
            ns._defensivesPreviewVisible = not indOn and testState.defensives
            ns._testReducedMaxHealth = not indOn and testState.reducedMaxHealth
            ns._testAbsorbs = not indOn and testState.absorbs
            ns._testHealAbsorbs = not indOn and testState.healAbsorbs
            ns._testHealPrediction = not indOn and testState.healPrediction
            ns._testThreat = not indOn and testState.threat
            ns._testBuffsVisible = not indOn and testState.buffs
            local wantAnim = not indOn and testState.animateBars
            if wantAnim then
                if ns._startHealthAnim and not ns._healthAnimActive then ns._startHealthAnim() end
            else
                if ns._stopHealthAnim and ns._healthAnimActive then ns._stopHealthAnim() end
            end
            -- Restart so debuff/defensive icons hide/show immediately.
            if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            -- Always stop first so re-init picks up new preview frames.
            if ns.StopPvBuffTicker then ns.StopPvBuffTicker() end
            local wantBuffs = not indOn and testState.buffs
            if wantBuffs and ns.StartPvBuffTicker then
                ns.StartPvBuffTicker()
            end
        end
        ns._applyTestState()

        ---------------------------------------------------------------
        --  HEALTH & POWER BARS
        ---------------------------------------------------------------
        SectionHeader("HEALTH & POWER BARS")

        do local _, _, r = CheckboxRow("Animate Bars", function() return testState.animateBars end,
            function(v) testState.animateBars = v end,
            { page = PAGE_MAIN, key = "animateBars" })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Absorbs", function() return testState.absorbs end,
            function(v) testState.absorbs = v end,
            { page = PAGE_MAIN, key = "absorbs" })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Healing Absorbs", function() return testState.healAbsorbs end,
            function(v) testState.healAbsorbs = v end,
            { page = PAGE_MAIN, key = "healAbsorbs" })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Heal Prediction", function() return testState.healPrediction end,
            function(v) testState.healPrediction = v end,
            { page = PAGE_MAIN, key = "healPrediction" })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Threat Indicator", function() return testState.threat end,
            function(v) testState.threat = v end,
            { page = PAGE_MAIN, key = "threat" })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Reduced Max Health", function() return testState.reducedMaxHealth end,
            function(v) testState.reducedMaxHealth = v end,
            { page = PAGE_MAIN, key = "absorbs" })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        ---------------------------------------------------------------
        --  AURAS
        ---------------------------------------------------------------
        SectionHeader("AURAS")

        do local _, _, r = CheckboxRow("Dispels", function() return testState.dispels end,
            function(v) testState.dispels = v; ns._applyTestState() end,
            { page = PAGE_MAIN })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Debuffs", function() return testState.debuffs end,
            function(v) testState.debuffs = v; ns._applyTestState() end,
            { page = PAGE_DM })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Defensives & Externals", function() return testState.defensives end,
            function(v) testState.defensives = v; ns._applyTestState() end,
            { page = PAGE_BUFFS })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Configured Buffs", function() return testState.buffs end,
            function(v) testState.buffs = v; ns._applyTestState() end,
            { page = PAGE_BUFFS })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        ---------------------------------------------------------------
        --  INDICATORS
        ---------------------------------------------------------------
        SectionHeader("INDICATORS")

        local function SetNonIndicatorRowsEnabled(enabled)
            for _, row2 in ipairs(nonIndicatorRows) do
                row2:SetAlpha(enabled and 1 or 0.35)
                row2:EnableMouse(enabled)
            end
        end

        CheckboxRow("Show All", function() return testState.indicators end,
            function(v)
                testState.indicators = v
                SetNonIndicatorRowsEnabled(not v)
                ns._applyTestState()
            end,
            { page = PAGE_MAIN })

        -- Indicators may already be on from a previous session.
        if testState.indicators then SetNonIndicatorRowsEnabled(false) end

        -- Content height plus room for the close button.
        panel:SetHeight(math.abs(cy) + 32 + PAD * 3)

        local closeBtn = CreateFrame("Button", nil, panel)
        closeBtn:SetSize(PANEL_W - PAD * 2, 32)
        closeBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, PAD)
        closeBtn:SetFrameLevel(panel:GetFrameLevel() + 1)
        local clBg = closeBtn:CreateTexture(nil, "BACKGROUND")
        clBg:SetAllPoints(); clBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
        local clLbl = MakeFont(closeBtn, 12, 1, 1, 1, 0.7)
        clLbl:SetPoint("CENTER"); clLbl:SetText(EllesmereUI.L("Close"))
        closeBtn:SetScript("OnEnter", function() clBg:SetColorTexture(0.35, 0.35, 0.35, 0.8); clLbl:SetAlpha(1) end)
        closeBtn:SetScript("OnLeave", function() clBg:SetColorTexture(0.25, 0.25, 0.25, 0.6); clLbl:SetAlpha(0.7) end)
        closeBtn:SetScript("OnClick", CloseTestMode)

        -- Dead space closes.
        testModeFrame:SetScript("OnMouseDown", function()
            local oc = ns._overlayContainer
            if (panel and panel:IsMouseOver()) or (oc and oc:IsMouseOver()) then return end
            CloseTestMode()
        end)

        testModeFrame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                CloseTestMode()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        testModeFrame:EnableKeyboard(true)
    end

    ns.OpenTestMode = OpenTestMode
    ns.CloseTestMode = CloseTestMode

    -- Test button appears on the tab bar while the RF module is selected.
    local testTabBtn = nil
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName == "EllesmereUIRaidFrames" then
                local tb = EllesmereUI._tabBar
                if not tb or not tb._tabButtons then return end
                local lastBtn = tb._tabButtons[#tb._tabButtons]
                if not lastBtn then return end

                if testTabBtn then
                    -- The tab bar rebuilds on module switch, so re-anchor.
                    testTabBtn:SetParent(tb)
                    testTabBtn:ClearAllPoints()
                    testTabBtn:SetPoint("BOTTOMLEFT", lastBtn, "BOTTOMRIGHT", 6, 0)
                    testTabBtn:Show()
                    return
                end

                testTabBtn = CreateFrame("Button", nil, tb)
                testTabBtn:SetHeight(40)
                testTabBtn:SetFrameLevel(tb:GetFrameLevel() + 1)

                local PP2 = EllesmereUI.PanelPP or EllesmereUI.PP
                local label = EllesmereUI.MakeFont(testTabBtn, 16, nil,
                    EllesmereUI.TEXT_DIM_R or 0.65, EllesmereUI.TEXT_DIM_G or 0.65,
                    EllesmereUI.TEXT_DIM_B or 0.65, EllesmereUI.TEXT_DIM_A or 0.65)
                label:SetPoint("CENTER", 0, 0)
                label:SetText(EllesmereUI.L("Full Preview"))
                testTabBtn._label = label

                local textW = label:GetStringWidth() or 30
                testTabBtn:SetWidth(textW + 30)
                testTabBtn:SetPoint("BOTTOMLEFT", lastBtn, "BOTTOMRIGHT", 6, 0)

                testTabBtn:SetScript("OnEnter", function(self) self._label:SetTextColor(1, 1, 1, 0.86) end)
                testTabBtn:SetScript("OnLeave", function(self)
                    self._label:SetTextColor(
                        EllesmereUI.TEXT_DIM_R or 0.65, EllesmereUI.TEXT_DIM_G or 0.65,
                        EllesmereUI.TEXT_DIM_B or 0.65, EllesmereUI.TEXT_DIM_A or 0.65)
                end)
                testTabBtn:SetScript("OnClick", function() OpenTestMode() end)
            else
                if testTabBtn then testTabBtn:Hide() end
            end
        end)
    end

    -- Shared with the page builders under RaidFrames_Options\ (read in their
    -- prologs). Every field is final here: optState holds the mutable state.
    ns._RFO_OptEnv = {
        AbbreviateNumbers = AbbreviateNumbers, absorbStyleOrder = absorbStyleOrder,
        absorbStyleValues = absorbStyleValues, allGrowthOrder = allGrowthOrder,
        BuildPreviewModeRow = BuildPreviewModeRow, BuildVisualSections = BuildVisualSections,
        db = db, floor = floor, growthValues = growthValues, groupGrowthOrder = groupGrowthOrder,
        groupGrowthValues = groupGrowthValues, hbtOrder = hbtOrder,
        hbtValues = hbtValues, healAbsorbStyleOrder = healAbsorbStyleOrder,
        healthColorOrder = healthColorOrder, healthColorValues = healthColorValues,
        healthTextOrder = healthTextOrder, healthTextValues = healthTextValues,
        IsPreviewOff = IsPreviewOff, KeepGrowthPerpendicular = KeepGrowthPerpendicular,
        maxHealthStyleOrder = maxHealthStyleOrder, MissingGlowDesc = MissingGlowDesc,
        namePositionOrder = namePositionOrder, namePositionOrderName = namePositionOrderName,
        namePositionValues = namePositionValues, namePositionValuesName = namePositionValuesName,
        optState = optState, PP = PP, ReadGroupGrowth = ReadGroupGrowth,
        ReloadAndUpdate = ReloadAndUpdate, SGet = SGet,
        SGetPx = SGetPx, SSet = SSet, SVal = SVal, SWrite = SWrite,
    }

    ---------------------------------------------------------------------------
    --  Register module
    ---------------------------------------------------------------------------
    local rfSearchTerms = {
        "raid", "frames", "group", "health", "power", "absorb", "shield",
        "debuff", "dispel", "threat", "role", "marker", "ready", "check",
        "border", "range", "tooltip", "layout", "spacing", "buff", "manager",
        "strata", "layer", "overlap",
        "click", "cast", "binding", "keybind", "spell", "macro", "mouseover",
    }

    -- Drops the BM / DM / CC roots (built on the shared scroll frame, not a
    -- page wrapper) except keepPage's. popups: true = also hide the Add New,
    -- DM add and BM2 editor/menu popups; "dm" = those DM/BM2 popups only when
    -- the DM root drops. stripAlways: clear the CC spell strip (parented to
    -- the panel, not the CC root) even with no CC root.
    local function DropManagerRoots(keepPage, popups, stripAlways)
        if popups == true and ns._addNewPopup then ns._addNewPopup:Hide() end
        if keepPage ~= PAGE_BUFFS and ns._bmRoot then
            ns._bmRoot:Hide(); ns._bmRoot:SetParent(nil); ns._bmRoot = nil
        end
        local dropDm = keepPage ~= PAGE_DM and ns._dmRoot
        if popups == true or (popups == "dm" and dropDm) then
            if ns._dmAddPopup then ns._dmAddPopup:Hide() end
            if ns._bm2FilterEditor then ns._bm2FilterEditor:Hide(); ns._bm2FilterEditor = nil end
            if ns._bm2Menu then ns._bm2Menu:Hide(); ns._bm2Menu = nil end
        end
        if dropDm then
            ns._dmRoot:Hide(); ns._dmRoot:SetParent(nil); ns._dmRoot = nil
        end
        local dropCc = keepPage ~= PAGE_CLICKCAST and ns._ccRoot
        if dropCc then
            if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
            if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
            if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
            ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil); ns._ccRoot = nil
        end
        if (dropCc or stripAlways) and ns._ccSpellStrip then
            ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil
        end
    end

    local function RestorePartyCtx(saved, ok, ...)
        optState._partyCtx = saved
        if not ok then error((...), 0) end
        return ...
    end

    EllesmereUI:RegisterModule("EllesmereUIRaidFrames", {
        title       = "Raid Frames",
        description = "Configure raid frame appearance and behavior.",
        -- No Auras page: debuffs and defensives/externals live in the managers.
        pages       = { PAGE_MAIN, PAGE_PARTY, PAGE_BUFFS, PAGE_DM, PAGE_CLICKCAST },
        searchTerms = rfSearchTerms,
        buildPage   = function(pageName, parent, yOffset)
            -- The cleanup/preview logic below acts on live state (BM/CC roots, raid/party preview overlays over the player's real frames) keyed only on the pageName being built, not what the player is actually looking at. An off-screen search pre-build cycles pageName through every page in `pages`, so NONE of it may run here.
            -- PAGE_BUFFS / PAGE_CLICKCAST go further: their builders (BuildBuffManagerPage -> ns.BM_BuildPage, ns.CC_BuildPage) bypass `parent` and build directly onto the live shared EllesmereUI._scrollFrame, so building them here would inject visible UI over whatever is on screen. Skip them; they index normally on the player's first live visit.
            --
            -- The pre-build must not leave the live page's _partyCtx changed.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_MAIN or pageName == PAGE_PARTY then
                    local saved = optState._partyCtx
                    optState._partyCtx = (pageName == PAGE_PARTY)
                    local build = (pageName == PAGE_PARTY) and ns.RFO_BuildPartyPage or ns.RFO_BuildMainPage
                    return RestorePartyCtx(saved, pcall(build, pageName, parent, yOffset))
                end
                return
            end
            -- Drop the BM / DM / CC roots when switching away.
            DropManagerRoots(pageName)
            if pageName == PAGE_MAIN then
                local mode = db.profile.previewMode or "overlay"
                -- Skip-restore keeps real party frames hidden under the preview so they don't flash on return to the party tab; restore only for "none", where real frames are meant to be visible.
                if ns.HidePartyPreview then ns.HidePartyPreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPreview then
                    C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
                elseif mode == "none" and ns.HidePreview then
                    ns.HidePreview()
                end
            elseif pageName == PAGE_PARTY then
                local mode = db.profile.previewMode or "overlay"
                -- Skip-restore avoids a one-frame flash of the real frames before the deferred ShowPartyPreview.
                if ns.HidePreview then ns.HidePreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPartyPreview then
                    C_Timer.After(0, function() if ns.ShowPartyPreview then ns.ShowPartyPreview() end end)
                elseif mode == "none" and ns.HidePartyPreview then
                    ns.HidePartyPreview()
                end
            else
                -- BUFFS / CLICKCAST show no preview, so FULL restore both real containers: a skip-restore here would strand the party container under the hidden preview parent with nothing to reparent it back.
                if ns.HidePreview then ns.HidePreview() end
                if ns.HidePartyPreview then ns.HidePartyPreview() end
            end
            -- Set party context BEFORE building any page so SGet/SSet/SVal read the correct keys during widget construction.
            optState._partyCtx = (pageName == PAGE_PARTY)

            if pageName == PAGE_MAIN then
                return ns.RFO_BuildMainPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PARTY then
                return ns.RFO_BuildPartyPage(pageName, parent, yOffset)
            elseif pageName == PAGE_DM then
                if ns.DMP_BuildPage then
                    return ns.DMP_BuildPage(pageName, parent, yOffset)
                end
                return math.abs(yOffset)
            elseif pageName == PAGE_BUFFS then
                return BuildBuffManagerPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CLICKCAST then
                if ns.CC_BuildPage then
                    return ns.CC_BuildPage(pageName, parent, yOffset)
                end
                return math.abs(yOffset)
            end
        end,
        onPageCacheRestore = function(pageName)
            -- Mirrors buildPage's root cleanup: fires INSTEAD of buildPage when the target page is already cached.
            -- Without it, switching from Buffs/HoverCast to a cached page never hides ns._bmRoot/ns._ccRoot, which are built onto the shared live scroll frame (not a per-page wrapper) and would stay stuck over the restored page.
            DropManagerRoots(pageName)
            if pageName == PAGE_MAIN then
                local mode = db.profile.previewMode or "overlay"
                -- Skip-restore; see buildPage.
                if ns.HidePartyPreview then ns.HidePartyPreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPreview then
                    C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
                elseif mode == "none" and ns.HidePreview then
                    ns.HidePreview()
                end
            elseif pageName == PAGE_PARTY then
                local mode = db.profile.previewMode or "overlay"
                -- Skip-restore avoids a one-frame flash of the real frames before the deferred ShowPartyPreview.
                if ns.HidePreview then ns.HidePreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPartyPreview then
                    C_Timer.After(0, function() if ns.ShowPartyPreview then ns.ShowPartyPreview() end end)
                elseif mode == "none" and ns.HidePartyPreview then
                    ns.HidePartyPreview()
                end
            elseif pageName == PAGE_BUFFS then
                if ns.HidePreview then ns.HidePreview() end
                if ns.HidePartyPreview then ns.HidePartyPreview() end
                if not ns._bmRoot then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" then
                            BuildBuffManagerPage(pageName, nil, -6)
                        end
                    end)
                end
            elseif pageName == PAGE_DM then
                if ns.HidePreview then ns.HidePreview() end
                if ns.HidePartyPreview then ns.HidePartyPreview() end
                if not ns._dmRoot then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" and ns.DMP_BuildPage then
                            ns.DMP_BuildPage(PAGE_DM, nil, -6)
                        end
                    end)
                end
            elseif pageName == PAGE_CLICKCAST then
                if ns.HidePreview then ns.HidePreview() end
                if not ns._ccRoot then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" and ns.CC_BuildPage then
                            ns.CC_BuildPage(PAGE_CLICKCAST, nil, -6)
                        end
                    end)
                end
            end
        end,
        onReset = function()
            -- Clearing the first-install flag re-captures position on reload.
            if db.sv then db.sv._capturedOnce_RF = nil end
            db:ResetProfile()
            -- No reload here: the footer Reset popup (reload = true) reloads after this returns.
        end,
        -- Tears down all 6 Raid Frames preview mechanisms on cross-module
        -- switch (Real/Party/Size/HealthAnim/PowerAnim/HM previews).
        onModuleLeave = function()
            if ns.HidePreview then ns.HidePreview() end
            if ns.HidePartyPreview then ns.HidePartyPreview() end
            ns._sizePreviewTier = nil
            if ns._HideSizePreview then ns._HideSizePreview() end
            if ns._healthAnimActive and ns.StopHealthAnim then ns.StopHealthAnim() end
            if ns._powerAnimActive and ns.StopPowerAnim then ns.StopPowerAnim() end
            if ns._hmPreview and ns.HM_SetPreview then ns.HM_SetPreview(false) end
        end,
    })

    -- Re-open on an RF page: show preview / rebuild BM.
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" then
            local page = EllesmereUI:GetActivePage()
            if page == PAGE_MAIN then
                local mode = db.profile.previewMode or "overlay"
                if mode ~= "none" and ns.ShowPreview then ns.ShowPreview() end
            elseif page == PAGE_PARTY then
                local mode = db.profile.previewMode or "overlay"
                if mode ~= "none" and ns.ShowPartyPreview then ns.ShowPartyPreview() end
            elseif page == PAGE_BUFFS then
                -- Panel opening on Buffs counts as entering it (WoW Forever: All Specs).
                ns.BM_EnterAllSpecs()
                if not ns._bmRoot then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" then
                            BuildBuffManagerPage(PAGE_BUFFS, nil, -6)
                        end
                    end)
                end
            elseif page == PAGE_DM then
                if not ns._dmRoot then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" and ns.DMP_BuildPage then
                            ns.DMP_BuildPage(PAGE_DM, nil, -6)
                        end
                    end)
                end
            elseif page == PAGE_CLICKCAST then
                if not ns._ccRoot then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" and ns.CC_BuildPage then
                            ns.CC_BuildPage(PAGE_CLICKCAST, nil, -6)
                        end
                    end)
                end
            end
        end
    end)
    -- Panel close: hide preview and clean up BM/CC.
    if EllesmereUI.RegisterOnHide then
        EllesmereUI:RegisterOnHide(function()
            if ns._rfEyeHintTip then ns._rfEyeHintTip:Hide() end
            -- HARD INVARIANT against "frames vanish after closing options": both real containers get reparented to UIParent and their visibility recomputed even if a skip-restore tab swap or a post-close deferred ShowPreview orphaned one under the hidden preview parent.
            -- Self-defers to PLAYER_REGEN_ENABLED in combat.
            if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
            if ns._sizePreviewTier then
                ns._sizePreviewTier = nil
                if ns._HideSizePreview then ns._HideSizePreview() end
            end
            -- BM root + Add New popup: the popup is DIALOG strata and otherwise persists after close.
            DropManagerRoots(nil, true, true)
        end)
    end

    -- HideAllChildren callback: BM/CC intentionally bypass the scroll child, so their scrollFrame-parented roots need explicit cleanup.
    EllesmereUI._hideScrollFrameRoots = function()
        DropManagerRoots(nil, true, true)
    end

    -- Module switch: drop the BM/CC roots and hide the preview.
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName ~= "EllesmereUIRaidFrames" then
                if ns._rfEyeHintTip then ns._rfEyeHintTip:Hide() end
                -- Tear down previews and guarantee the real containers return to UIParent, including the orphaned-flag-false cases.
                if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
                DropManagerRoots(nil, true)
            end
        end)
    end

    -- Party Frames search excludes raid-synced sections (their controls live on the Raid tabs). Maps section HEADER TEXT to sync key:
    -- KEEP IN SYNC with the SectionHeader names in the builders and ns._PARTY_SECTION_ORDER.
    ns._PARTY_SEARCH_SECTION_KEY = {
        ["HEALTH BAR"]             = "healthBar",
        ["ABSORBS"]                = "absorbs",
        ["POWER BAR"]              = "powerBar",
        ["TEXT DISPLAY"]           = "textDisplay",
        ["INDICATORS"]             = "indicators",
        ["DISPELS"]                = "dispels",
        ["TOP NAME BAR"]           = "topNameBar",
        ["EXTRAS"]                 = "rangeTooltip",
    }
    ns._PartySearchExclude = function(sectionName)
        local key = ns._PARTY_SEARCH_SECTION_KEY[sectionName]
        if not key then return false end
        if not db or not db.profile then return false end
        local ss = db.profile.partySyncSections
        return (not ss) or ss[key] ~= false  -- synced (default = all synced)
    end

    -- Party sync overlays track the inline search: hidden while a search is active (those sections are excluded), restored to their per-section sync state when empty. Overlays carry _searchIgnore so the generic search never re-anchors them.
    ns._PartySearchOverlaySync = function(query)
        if not ns._syncOverlays then return end
        local searching = query and query ~= ""
        local ss = db and db.profile and db.profile.partySyncSections
        for key, ov in pairs(ns._syncOverlays) do
            if searching then
                ov:Hide()
            elseif (not ss) or ss[key] ~= false then
                ov:Show()
            else
                ov:Hide()
            end
        end
    end

    -- Page switch cleanup within RF. PRE-hook (wrap, not hooksecurefunc): _partyCtx must be set BEFORE SelectPage refreshes widget values.
    if EllesmereUI.SelectPage then
        local origSelectPage = EllesmereUI.SelectPage
        EllesmereUI.SelectPage = function(self, pageName, ...)
            optState._partyCtx = (pageName == PAGE_PARTY)
            -- Entering Buffs from another page (not a rebuild while on it): WoW Forever opens it on All Specs.
            if pageName == PAGE_BUFFS and EllesmereUI:GetActivePage() ~= PAGE_BUFFS then ns.BM_EnterAllSpecs() end
            -- Party tab excludes synced sections from inline search; cleared on every other page (any module) so the hook can never leak.
            EllesmereUI._searchExcludeSection = (pageName == PAGE_PARTY) and ns._PartySearchExclude or nil
            EllesmereUI._onInlineSearch = (pageName == PAGE_PARTY) and ns._PartySearchOverlaySync or nil
            local result = origSelectPage(self, pageName, ...)
            -- Re-sync overlays on entering the party tab: a prior search may have hidden them, and the search box clears on page change.
            if pageName == PAGE_PARTY and ns._PartySearchOverlaySync then
                ns._PartySearchOverlaySync("")
            end
            if ns._rfEyeHintTip then
                if pageName == PAGE_MAIN then ns._rfEyeHintTip:Show()
                else ns._rfEyeHintTip:Hide() end
            end
            -- Every eyeball toggle resets on tab change.
            ns._indicatorsVisible = false
            ns._dispelsVisible = false
            ns._defensivesPreviewVisible = false
            ns._debuffsPreviewVisible = false
            ns._absorbsPreviewVisible = false
            -- The health/power tickers live on ns, so one cancel covers whichever preview built them.
            ns._healthAnimActive = false
            ns._powerAnimActive = false
            if ns._healthAnimTicker then ns._healthAnimTicker:Cancel(); ns._healthAnimTicker = nil end
            if ns._powerAnimTicker then ns._powerAnimTicker:Cancel(); ns._powerAnimTicker = nil end
            ns._bmFrameEffectsVisible = false
            if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            if ns.ResetPreviewRandomization then ns.ResetPreviewRandomization() end

            -- Manager/HoverCast tabs show no raid frame preview.
            if pageName == PAGE_BUFFS or pageName == PAGE_DM or pageName == PAGE_CLICKCAST then
                if ns.HidePreview then ns.HidePreview() end
            end
            if pageName == PAGE_MAIN then
                local mode = db.profile.previewMode or "overlay"
                if mode ~= "none" and ns.ShowPreview then
                    C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
                end
            end
            -- Drop the BM / DM / CC roots when switching away.
            DropManagerRoots(pageName, "dm")
            return result
        end
    end

    ---------------------------------------------------------------------------
    --  Slash command
    ---------------------------------------------------------------------------
    SLASH_ELLESMERERAIDFRAMES1 = "/erf"
    SlashCmdList.ELLESMERERAIDFRAMES = function(msg)
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end
        if msg == "reset" then
            db:ResetProfile()
            EllesmereUI.RequestReload()
            return
        end
        EllesmereUI:ShowModule("EllesmereUIRaidFrames")
    end
    end -- ns._InitEUIModule

    -- SetupOptionsPanel may already have run before PLAYER_LOGIN.
    if ns.db then
        ns._InitEUIModule()
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end



