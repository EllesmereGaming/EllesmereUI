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
        midnight = "Midnight", pixel = "Pixel", runic = "Runic" }
    local classOrder = { "modern", "arcade", "glyph", "legend", "midnight", "pixel", "runic" }
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
        { type="slider", label="3D Zoom", min=100, max=300, step=1,
          get=function() return PV("partyPortrait3dZoom", 100) end,
          set=function(v) PtSet("partyPortrait3dZoom", v) end },
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
    local _partyCtx = false  -- true while building/interacting on the party tab
    local PARTY_KEY_SECTION = ns._PARTY_KEY_SECTION or {}
    local IsPartySectionCustom = ns._IsPartySectionCustom

    local function SGet(key)
        if _partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            local pv = db.profile["party_" .. key]
            if pv ~= nil then return pv end
        end
        return db.profile[key]
    end
    local function SSet(key, val)
        if _partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            db.profile["party_" .. key] = val
        else
            db.profile[key] = val
        end
        if ns._BumpAbsorbGen then ns._BumpAbsorbGen() end
        ReloadAndUpdate()
    end
    local function SVal(key, default)
        if _partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            local pv = db.profile["party_" .. key]
            if pv ~= nil then return pv end
        end
        local v = db.profile[key]
        if v ~= nil then return v end
        return default
    end
    -- Context-aware direct write, for color swatches that bypass SSet.
    local function SWrite(key, val)
        if _partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
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
        if _partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key])
           and db.profile["party_" .. sib] ~= nil then
            return db.profile["party_" .. key]
        end
        return SGet(key)
    end

    ---------------------------------------------------------------------------
    --  Shared "Sort By" control: Group/Role radio + drag-to-reorder role rows,
    --  installed into a DualRow half-region (replaces its placeholder dropdown);
    --  used by both raid LAYOUT and party FRAMES tabs. opts wires it to:
    --      opts.readMode()    -> "INDEX" | "ROLE"
    --      opts.writeMode(v)  -- persist sort mode + trigger reload/preview
    --      opts.readRoles()   -> { role, role, role }  (read-only)
    --      opts.writeRoles(t) -- persist role order + trigger reload/preview
    ---------------------------------------------------------------------------
    local function BuildSortByControl(rgn, opts)
        if rgn._control then rgn._control:Hide() end

        local sortBtn = CreateFrame("Button", nil, rgn)
        sortBtn:SetSize(170, 30)
        PP.Point(sortBtn, "RIGHT", rgn, "RIGHT", -20, 0)
        sortBtn:SetFrameLevel(rgn:GetFrameLevel() + 2)

        local sBg = sortBtn:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        local sBrd = EllesmereUI.MakeBorder(sortBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

        local sLabel = EllesmereUI.MakeFont(sortBtn, 13, nil, 1, 1, 1)
        sLabel:SetAlpha(EllesmereUI.DD_TXT_A)
        sLabel:SetJustifyH("LEFT")
        sLabel:SetWordWrap(false)
        sLabel:SetMaxLines(1)
        sLabel:SetPoint("LEFT", sortBtn, "LEFT", 8, 0)
        local sArrow = EllesmereUI.MakeDropdownArrow(sortBtn, 12, PP)
        sLabel:SetPoint("RIGHT", sArrow, "LEFT", -5, 0)

        local function UpdateSortLabel()
            local mode = opts.readMode()
            if mode == "FRAMESORT" then
                sLabel:SetText("FrameSort")
            else
                sLabel:SetText(mode == "ROLE" and EllesmereUI.L("Role") or EllesmereUI.L("Group"))
            end
        end
        UpdateSortLabel()

        sortBtn:SetScript("OnEnter", function()
            sBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            sBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_HA)
            sLabel:SetAlpha(EllesmereUI.DD_TXT_HA)
        end)
        sortBtn:SetScript("OnLeave", function()
            sBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            sBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
            sLabel:SetAlpha(EllesmereUI.DD_TXT_A)
        end)

        local MH = 26       -- row height
        local DH = 16       -- divider height
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

        local menuFrame = CreateFrame("Frame", nil, UIParent)
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(200)
        menuFrame:SetClampedToScreen(true)
        menuFrame:SetWidth(170)
        menuFrame:Hide()

        local mBg = menuFrame:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
        EllesmereUI.MakeBorder(menuFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

        -- Declared before OnShow: its OnUpdate suppresses click-away dismiss while a row is dragged.
        local dragRow, dsY, isDragging = nil, nil, false

        menuFrame:SetScript("OnShow", function(self)
            local sc = sortBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
            self:SetScale(sc)
            self:SetScript("OnUpdate", function(m)
                if isDragging then return end  -- never dismiss mid-drag
                if not sortBtn:IsMouseOver() and not m:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                end
            end)
        end)
        menuFrame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        menuFrame:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", 0, -2)

        local mY = -2
        local FONT = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

        local radioItems = {
            { key = "INDEX", label = "Group" },
            { key = "ROLE",  label = "Role" },
        }
        -- Offered only while FrameSort's API is present (its sorted unit list
        -- orders the frames; the same test the frames use). A saved choice
        -- with the addon gone falls back to Group order in the frames and
        -- keeps its label here.
        if ns._FrameSortApi and ns._FrameSortApi() then
            radioItems[#radioItems + 1] = { key = "FRAMESORT", label = "FrameSort", noLoc = true }
        end
        local SEL_A = EllesmereUI.DD_ITEM_SEL_A
        local HL_A  = EllesmereUI.DD_ITEM_HL_A
        local itemDimA = EllesmereUI.TEXT_DIM_A or 0.53
        local radioRows = {}
        for _, ri in ipairs(radioItems) do
            local rr = CreateFrame("Button", nil, menuFrame)
            rr:SetHeight(MH)
            rr:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
            rr:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
            rr:SetFrameLevel(menuFrame:GetFrameLevel() + 1)

            local rl = rr:CreateFontString(nil, "OVERLAY")
            rl:SetFont(FONT, 13, "")
            rl:SetPoint("LEFT", rr, "LEFT", 10, 0)
            rl:SetJustifyH("LEFT")

            local rHL = rr:CreateTexture(nil, "ARTWORK")
            rHL:SetAllPoints(); rHL:SetColorTexture(1, 1, 1, 1); rHL:SetAlpha(0)

            local function UpdateRadio()
                local isSel = opts.readMode() == ri.key
                rl:SetTextColor(1, 1, 1, itemDimA)
                rHL:SetAlpha(isSel and SEL_A or 0)
            end
            UpdateRadio()
            rr._updateRadio = UpdateRadio

            rr:SetScript("OnEnter", function() rHL:SetAlpha(HL_A) end)
            rr:SetScript("OnLeave", function() UpdateRadio() end)
            rr:SetScript("OnClick", function()
                opts.writeMode(ri.key)
                UpdateSortLabel()
                for _, r2 in ipairs(radioRows) do r2._updateRadio() end
                menuFrame:Hide()
            end)

            rl:SetText(ri.noLoc and ri.label or EllesmereUI.L(ri.label))
            radioRows[#radioRows + 1] = rr
            mY = mY - MH
        end

        local dv = CreateFrame("Frame", nil, menuFrame)
        dv:SetHeight(DH)
        dv:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 0, mY)
        dv:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", 0, mY)
        local dl = dv:CreateTexture(nil, "ARTWORK")
        dl:SetHeight(1)
        dl:SetPoint("LEFT", dv, "LEFT", 10, 0)
        dl:SetPoint("RIGHT", dv, "RIGHT", -10, 0)
        dl:SetColorTexture(1, 1, 1, 0.08)
        mY = mY - DH

        local ht = CreateFrame("Frame", nil, menuFrame)
        ht:SetHeight(18)
        ht:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 0, mY)
        ht:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", 0, mY)
        local hfs = ht:CreateFontString(nil, "OVERLAY")
        hfs:SetFont(FONT, 10, "")
        hfs:SetPoint("LEFT", ht, "LEFT", 10, 0)
        hfs:SetTextColor(1, 1, 1, 0.25)
        hfs:SetText(EllesmereUI.L("Drag to Reorder Roles"))
        mY = mY - 18

        -- Draggable role rows
        local roleLabels = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
        local roleItems = {}
        local roleOrder = opts.readRoles()
        if type(roleOrder) ~= "table" or #roleOrder < 3 then
            roleOrder = { "TANK", "HEALER", "DAMAGER" }
        end
        for i, rk in ipairs(roleOrder) do
            roleItems[i] = { key = rk, label = roleLabels[rk] or rk }
        end

        local cbBaseY = mY
        local rowFrames = {}
        local insLine = menuFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        insLine:SetHeight(2)
        insLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        insLine:Hide()

        for ci, cb in ipairs(roleItems) do
            local row = CreateFrame("Button", nil, menuFrame)
            row:SetHeight(MH)
            row._baseY = mY
            row._cbIndex = ci
            row._cb = cb
            row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
            row:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
            row:SetFrameLevel(menuFrame:GetFrameLevel() + 2)

            local rl = row:CreateFontString(nil, "OVERLAY")
            rl:SetFont(FONT, 13, "")
            rl:SetPoint("LEFT", row, "LEFT", 20, 0)
            rl:SetJustifyH("LEFT")
            rl:SetText(EllesmereUI.L(cb.label))
            rl:SetTextColor(0.75, 0.75, 0.75, 1)
            row._lbl = rl

            -- Drag handle dots
            local grip = row:CreateFontString(nil, "OVERLAY")
            grip:SetFont(FONT, 10, "")
            grip:SetPoint("LEFT", row, "LEFT", 8, 0)
            grip:SetText("=")
            grip:SetTextColor(1, 1, 1, 0.2)

            local rHL = row:CreateTexture(nil, "ARTWORK")
            rHL:SetAllPoints(); rHL:SetColorTexture(1, 1, 1, 0)

            row:SetScript("OnEnter", function()
                if isDragging then return end
                rl:SetTextColor(1, 1, 1, 1); rHL:SetColorTexture(1, 1, 1, 0.04)
            end)
            row:SetScript("OnLeave", function()
                if isDragging then return end
                rl:SetTextColor(0.75, 0.75, 0.75, 1); rHL:SetColorTexture(1, 1, 1, 0)
            end)

            row:SetScript("OnMouseDown", function(self, b)
                if b ~= "LeftButton" then return end
                local _, cy = GetCursorPosition()
                dsY = cy
                dragRow = self
            end)

            row:SetScript("OnUpdate", function(self)
                if dragRow ~= self then return end
                if not dsY then return end
                local _, cy = GetCursorPosition()
                if not isDragging then
                    if math.abs(cy - dsY) < 3 then return end
                    isDragging = true
                    self:SetFrameLevel(menuFrame:GetFrameLevel() + 10)
                    self:SetAlpha(0.8)
                    for _, rf in ipairs(rowFrames) do
                        if rf._lbl then rf._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                    end
                end
                -- Insertion line
                local sc = menuFrame:GetEffectiveScale()
                local cY = cy / sc
                local mT = menuFrame:GetTop() or 0
                local iI = #roleItems
                for ri, rf in ipairs(rowFrames) do
                    if rf ~= self and rf._baseY then
                        local rm = mT + rf._baseY - MH / 2
                        if cY > rm then iI = ri; break end
                        iI = ri + 1
                    end
                end
                iI = math.max(1, math.min(iI, #roleItems + 1))
                local lnY = (iI <= 1) and (cbBaseY + 1) or (cbBaseY - (iI - 1) * MH + 1)
                insLine:ClearAllPoints()
                insLine:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, lnY)
                insLine:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, lnY)
                insLine:Show()

                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, cY - mT)
                self:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, cY - mT)
            end)

            row:SetScript("OnMouseUp", function(self, b)
                if b ~= "LeftButton" then return end
                if dragRow ~= self then return end
                dsY = nil
                dragRow = nil
                if not isDragging then return end
                isDragging = false; insLine:Hide()
                self:SetFrameLevel(menuFrame:GetFrameLevel() + 2); self:SetAlpha(1)

                local _, cy = GetCursorPosition()
                local sc = menuFrame:GetEffectiveScale(); cy = cy / sc
                local mT = menuFrame:GetTop() or 0
                local from = self._cbIndex
                -- Same logic as insertion line: skip the dragged row
                local iI = #roleItems
                for ri, rf in ipairs(rowFrames) do
                    if rf ~= self and rf._baseY then
                        local rm = mT + rf._baseY - MH / 2
                        if cy > rm then iI = ri; break end
                        iI = ri + 1
                    end
                end
                iI = math.max(1, math.min(iI, #roleItems + 1))
                -- Adjust for index shift from table.remove
                if from < iI then iI = iI - 1 end
                local to = math.max(1, math.min(iI, #roleItems))

                if from ~= to then
                    -- Persist as a FRESH table -- mutating in place would corrupt the raid order via party fallback.
                    local mvItem = table.remove(roleItems, from)
                    table.insert(roleItems, to, mvItem)
                    local ro = {}
                    for _, it in ipairs(roleItems) do ro[#ro + 1] = it.key end
                    opts.writeRoles(ro)
                end

                for ri = 1, #rowFrames do
                    local rf = rowFrames[ri]
                    rf._cbIndex = ri
                    rf._cb = roleItems[ri]
                    rf._lbl:SetText(roleItems[ri].label)
                    local ry = cbBaseY - (ri - 1) * MH
                    rf._baseY = ry
                    rf:ClearAllPoints()
                    rf:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, ry)
                    rf:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, ry)
                end
            end)

            rowFrames[#rowFrames + 1] = row
            mY = mY - MH
        end

        menuFrame:SetHeight(math.abs(mY) + 4)

        sortBtn:SetScript("OnClick", function()
            if menuFrame:IsShown() then menuFrame:Hide() else menuFrame:Show() end
        end)

        rgn._control = sortBtn
        rgn._lastInline = nil
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
    }
    -- Shield absorb shows every style including Blizzard (Modern).
    local absorbStyleOrder = { "none", "blizzardModern", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeStripes", "largeStripesR", "blizzardRaid" }
    -- Heal absorb shares the values table but EXCLUDES Blizzard (Modern).
    local healAbsorbStyleOrder = { "none", "healBlizzModern", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR", "blizzardRaid" }
    -- Max Health mirrors Heal Absorb plus "Max Health Stripes" first.
    local maxHealthStyleOrder = { "none", "maxHealthStripes", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "healBlizzModern", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR", "blizzardRaid" }
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
    -- this check (EllesmereUIRaidFrames.lua); reuse it here rather than a second copy.
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
        local _, h
        local row
        local _secY  -- section start tracker
        -- Eyeball handles are per-context (raid vs party) so the two page builds don't clobber each other's eye-icon refreshers. Animation start/stop stay on ns: one shared ticker resolves the active preview at call time via ns.PvActiveFrames.
        local _eyeCtx = _partyCtx and "party" or "raid"
        ns._eye = ns._eye or {}
        ns._eye[_eyeCtx] = ns._eye[_eyeCtx] or {}
        local EYE = ns._eye[_eyeCtx]
        -------------------------------------------------------------------
        --  HEALTH BAR
        -------------------------------------------------------------------
        _secY = y
        local healthHeader
        healthHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

        -- Eyeball: animate health bars (damage/healing simulation); built on raid + party pages, reads the active frame set via ns.PvActiveFrames().
        do
            local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
            -- State lives on ns (single shared ticker) so raid and party eyeball builds drive one animation and start/stop works across both. ns._healthAnimActive is the truth the renderer reads.
            ns._healthAnimState = ns._healthAnimState or {}

            local function StopHealthAnim()
                if ns._healthAnimTicker then
                    ns._healthAnimTicker:Cancel()
                    ns._healthAnimTicker = nil
                end
                ns._healthAnimActive = false
                -- Pause: persist animated values so they stay on screen.
                local phv = ns.PvHealthValues()
                if phv then
                    for i, st in ipairs(ns._healthAnimState) do
                        phv[i] = st.current
                    end
                end
            end
            -- Exposed for onModuleLeave below.
            ns.StopHealthAnim = StopHealthAnim

            local function StartHealthAnim()
                if ns._healthAnimTicker then return end
                ns._healthAnimActive = true
                wipe(ns._healthAnimState)

                local frames = ns.PvActiveFrames()
                local s = (ns.PvEffectiveProfile and ns.PvEffectiveProfile()) or db.profile
                for i = 1, 20 do
                    local f = frames[i]
                    if f and f._health then
                        ns._healthAnimState[i] = {
                            frame = f,
                            current = f._healthPct or (40 + math.random(60)),
                            target = 20 + math.random(80),
                            snapTimer = math.random() * 2,
                            nextSnap = 1.2 + math.random() * 1.6,
                        }
                    end
                end

                local smoothInterp = Enum and Enum.StatusBarInterpolation
                    and Enum.StatusBarInterpolation.ExponentialEaseOut
                ns._healthAnimTicker = C_Timer.NewTicker(0.1, function()
                    if not ns._healthAnimActive then return end
                    -- Real preview contract: ticks must render effective-overlay values only, never the panel view's swapped values.
                    local s = (ns.PvEffectiveProfile and ns.PvEffectiveProfile()) or db.profile
                    local smooth = s.smoothBars

                    for i, st in ipairs(ns._healthAnimState) do
                        local f = st.frame
                        if f and f._health and not f._pvHideHealthText then
                            -- Per-unit staggered timer, same cadence smooth or not.
                            st.snapTimer = st.snapTimer + 0.1
                            if st.snapTimer < st.nextSnap then
                            else
                                st.snapTimer = 0
                                st.nextSnap = 1.2 + math.random() * 1.6
                                st.current = st.target
                                st.target = 15 + math.random(85)

                                if smooth and smoothInterp then
                                    f._health:SetValue(st.current, smoothInterp)
                                else
                                    f._health:SetValue(st.current)
                                end

                                if f._healthText then
                                    local mode = s.healthTextMode or "none"
                                    if mode == "percent" then
                                        f._healthText:SetFormattedText("%d%%", st.current)
                                    elseif mode == "percentNoSign" then
                                        f._healthText:SetFormattedText("%d", st.current)
                                    elseif mode == "number" then
                                        local fakeHP = st.current * 12000
                                        if AbbreviateNumbers then
                                            f._healthText:SetText(AbbreviateNumbers(fakeHP))
                                        end
                                    elseif mode == "numberPercent" then
                                        local fakeHP = st.current * 12000
                                        local numStr = AbbreviateNumbers and AbbreviateNumbers(fakeHP) or tostring(fakeHP)
                                        f._healthText:SetFormattedText("%s | %d%%", numStr, st.current)
                                    elseif mode == "percentNumber" then
                                        local fakeHP = st.current * 12000
                                        local numStr = AbbreviateNumbers and AbbreviateNumbers(fakeHP) or tostring(fakeHP)
                                        f._healthText:SetFormattedText("%d%% | %s", st.current, numStr)
                                    elseif mode == "missing" then
                                        local fakeHP = (100 - st.current) * 12000
                                        f._healthText:SetText(C_StringUtil.TruncateWhenZero(fakeHP))
                                        if f._healthText:GetText() then
                                            if AbbreviateNumbers then
                                                f._healthText:SetText(AbbreviateNumbers(fakeHP))
                                            end
                                        end
                                    end
                                end

                                -- Fill color only moves in gradient modes.
                                if s.healthColorMode == "classic" then
                                    local pct = st.current / 100
                                    local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
                                    local g = pct > 0.5 and 1 or (pct * 2)
                                    f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
                                elseif s.healthColorMode == "customDynamic" then
                                    local r, g, b = ns.ResolveDynamicColor(s, st.current / 100)
                                    f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
                                elseif s.healthColorMode == "classReactive" then
                                    local r, g, b = ns.ResolveClassReactiveColor(s, f._classToken, st.current / 100)
                                    f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
                                end
                            end -- snapTimer ready
                        end
                    end
                end)
            end

            -- Eye button anchors to the section header's label FontString.
            local headerLabel
            for _, rgn in ipairs({ healthHeader:GetRegions() }) do
                if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "HEALTH BAR" then
                    headerLabel = rgn; break
                end
            end
            local eyeBtn = CreateFrame("Button", nil, healthHeader)
            eyeBtn:SetSize(24, 24)
            if headerLabel then
                eyeBtn:SetPoint("LEFT", headerLabel, "RIGHT", 5, 0)
            else
                eyeBtn:SetPoint("LEFT", healthHeader, "BOTTOMLEFT", 85, 8)
            end
            eyeBtn:SetFrameLevel(healthHeader:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshHealthEye()
                if IsPreviewOff() then
                    eyeTex:SetTexture(EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.15)
                    return
                end
                eyeTex:SetTexture(ns._healthAnimActive and EYE_INVISIBLE or EYE_VISIBLE)
                eyeBtn:SetAlpha(0.4)
            end
            RefreshHealthEye()
            EYE.refreshHealthEye = RefreshHealthEye
            ns._stopHealthAnim = StopHealthAnim
            ns._startHealthAnim = StartHealthAnim
            eyeBtn:SetScript("OnClick", function()
                if IsPreviewOff() then return end
                if ns._healthAnimActive then
                    StopHealthAnim()
                else
                    if ns._indicatorsVisible then
                        ns._indicatorsVisible = false
                        if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                    end
                    StartHealthAnim()
                end
                RefreshHealthEye()
                if ns.PvRefresh then ns.PvRefresh() end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if IsPreviewOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                    return
                end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._healthAnimActive and "Stop health bar effects" or "Preview health bar effects")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                if not IsPreviewOff() then self:SetAlpha(0.4) end
                EllesmereUI.HideWidgetTooltip()
            end)

            EllesmereUI:RegisterOnHide(function()
                if ns._healthAnimActive then StopHealthAnim(); RefreshHealthEye() end
            end)

            -- One-time eyeball hint, raid/main page only.
            if not _partyCtx and not (EllesmereUIDB and EllesmereUIDB.rfEyeHintSeen) then
                local TIP_W, TIP_H = 310, 82
                local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
                local ar, ag, ab = EG.r, EG.g, EG.b

                local tip = CreateFrame("Frame", nil, UIParent)
                tip:SetFrameStrata("FULLSCREEN_DIALOG")
                tip:SetFrameLevel(200)
                if PP then PP.Size(tip, TIP_W, TIP_H) end
                tip:SetSize(TIP_W, TIP_H)
                tip:EnableMouse(true)
                tip:SetPoint("TOP", eyeBtn, "BOTTOM", 0, -14)

                local tipBg = tip:CreateTexture(nil, "BACKGROUND")
                tipBg:SetAllPoints()
                tipBg:SetColorTexture(0.06, 0.08, 0.10, 0.95)

                EllesmereUI.MakeBorder(tip, ar, ag, ab, 0.25, PP)

                -- Arrow pointing up (clipped diamond)
                local ARROW_SZ = 16
                local arrowClip = CreateFrame("Frame", nil, tip)
                arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
                arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
                arrowClip:SetClipsChildren(true)
                arrowClip:SetSize(ARROW_SZ * 2, ARROW_SZ)
                arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

                local arrowFrame = CreateFrame("Frame", nil, arrowClip)
                arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
                arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
                arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

                local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
                arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
                arrowBorder:SetPoint("CENTER")
                arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
                arrowBorder:SetRotation(math.rad(45))
                if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

                local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
                arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
                arrowFill:SetPoint("CENTER")
                arrowFill:SetColorTexture(0.06, 0.08, 0.10, 0.95)
                arrowFill:SetRotation(math.rad(45))
                if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

                local msg = EllesmereUI.MakeFont(tip, 10, nil, 1, 1, 1, 0.85)
                msg:SetPoint("TOP", tip, "TOP", 0, -12)
                msg:SetWidth(TIP_W - 24)
                msg:SetJustifyH("CENTER")
                msg:SetSpacing(4)
                msg:SetText(EllesmereUI.L("Click this eye icon to preview live\nhealth bar effects like absorbs and healing."))

                local okBtn = CreateFrame("Button", nil, tip)
                okBtn:SetSize(70, 22)
                okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 10)
                EllesmereUI.MakeStyledButton(okBtn, "Okay", 10,
                    EllesmereUI.RB_COLOURS, function()
                        tip:Hide()
                        ns._rfEyeHintTip = nil
                        EllesmereUIDB = EllesmereUIDB or {}
                        EllesmereUIDB.rfEyeHintSeen = true
                    end)

                ns._rfEyeHintTip = tip

                tip:SetAlpha(0)
                tip:Show()
                local fadeIn = 0
                tip:SetScript("OnUpdate", function(self, dt)
                    fadeIn = fadeIn + dt
                    if fadeIn >= 0.3 then
                        self:SetAlpha(1)
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    self:SetAlpha(fadeIn / 0.3)
                end)
            end
        end  -- close do (health eyeball)

        local texRow
        texRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Health Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return SVal("healthBarTexture", "atrocity") end,
              setValue=function(v) SSet("healthBarTexture", v) end },
            { type="slider", text="Fill Opacity", min=0, max=100, step=1,
              disabled=function() return SVal("healthColorMode", "class") == "dark" end,
              disabledTooltip="Not available in Dark Mode", rawTooltip=true,
              getValue=function() return SVal("healthBarOpacity", 100) end,
              setValue=function(v) SSet("healthBarOpacity", v) end });
        -- Vertical Fill cog lives in the Health Bar party-sync section, so an unsynced party tab keeps its own value.
        if not EllesmereUI._prebuilding then
            local lrgn = texRow._leftRegion
            EllesmereUI.BuildInlineCog(lrgn, {
                title = "Health Bar Fill",
                rows = {
                    ns.RF_PartyKitGate({ type="toggle", label="Vertical Fill",
                      tooltip="Fill the health bar bottom-to-top instead of left-to-right. Absorbs, heal prediction and the bar background follow the same axis.",
                      get=function() return SVal("healthVerticalFill", false) end,
                      -- RefreshPage re-labels Absorbs Placement for the new axis; cog popups bake labels in on first build.
                      set=function(v) SSet("healthVerticalFill", v); EllesmereUI:RefreshPage() end }),
                },
            })
        end
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Fill Color", values=healthColorValues, order=healthColorOrder,
              tooltip="Custom Dynamic Colors: the health bar smoothly blends between three colors you pick -- one for full health (100%), one for half (50%), and one for empty (0%) -- shifting through them as the unit takes damage or is healed.",
              getValue=function() return SVal("healthColorMode", "class") end,
              setValue=function(v)
                  SSet("healthColorMode", v)
                  -- "dark" feeds the Dark Mode conditional-override condition.
                  EllesmereUI.Conditions_Recheck()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Background", min=0, max=100, step=1,
              disabled=function() return SVal("healthColorMode", "class") == "dark" end,
              disabledTooltip="Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Fonts & Colors.", rawTooltip=true,
              getValue=function() return SVal("bgDarkness", 50) end,
              setValue=function(v) SSet("bgDarkness", v) end });  y = y - h
        -- Fill Color's "dark" choice IS the Dark Mode condition's input, so lock the dropdown while a Dark Mode conditional is being edited -- else the override could capture a mode change that flips its own condition.
        if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
            EllesmereUI.SpecOverrides_AttachEditLock(row._leftRegion,
                "Fill Color's Dark Mode choice drives a Dark Mode override condition, so it can't be changed while editing an override",
                EllesmereUI.SpecOverrides_DarkCondEditActive)
        end
        -- Custom fill swatch plus the three Custom Dynamic stop swatches (100/50/0%) share one inline slot; the Fill Color mode decides which set is interactive.
        if not EllesmereUI._prebuilding then
            local rgn = row._leftRegion

            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local c = SGet("customFillColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 37/255, 193/255, 29/255, 1
                end,
                function(r, g, b)
                    SWrite("customFillColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
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

            -- Three gradient-stop swatches, built right-to-left so the visual order reads 100% | 50% | 0%; tooltips carry the pct.
            local dynDefs = {
                { key = "dynamicColor100", def = { r = 0, g = 1, b = 0 }, label = "100%", tip = "Health bar color at full (100%) health" },
                { key = "dynamicColor50",  def = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }, label = "50%",  tip = "Health bar color at half (50%) health" },
                { key = "dynamicColor0",   def = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }, label = "0%",   tip = "Health bar color at empty (0%) health" },
            }
            local dynSwatches = {}
            local prevAnchor = rgn._control
            for i = #dynDefs, 1, -1 do
                local dd = dynDefs[i]
                local sw = EllesmereUI.BuildColorSwatch(
                    rgn, row:GetFrameLevel() + 3,
                    function()
                        local c = SGet(dd.key) or dd.def
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        SWrite(dd.key, { r=r, g=g, b=b })
                        ReloadAndUpdate()
                    end, false, 18)
                sw:SetPoint("RIGHT", prevAnchor, "LEFT", (prevAnchor == rgn._control) and -8 or -6, 0)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, dd.tip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                dynSwatches[i] = sw
                prevAnchor = sw
            end

            local function UpdateSwatchVis()
                local mode = SVal("healthColorMode", "class")
                local isDynamic = mode == "customDynamic"
                -- Class Reactive shares the dynamic stops but its 100% color IS
                -- the class color: only the 0%/50% swatches apply there.
                local isClassReactive = mode == "classReactive"
                -- Single custom swatch: live only in Custom mode, dimmed+blocked in other modes, fully HIDDEN in Dynamic/Class Reactive modes so it doesn't sit behind the dynamic swatches.
                if isDynamic or isClassReactive then
                    swatch:Hide(); block:Hide()
                else
                    swatch:Show()
                    if mode == "custom" then swatch:SetAlpha(1); block:Hide()
                    else swatch:SetAlpha(0.3); block:Show() end
                end
                for i, sw in ipairs(dynSwatches) do
                    -- dynSwatches[1] = the 100% stop (class-driven in Class Reactive).
                    if isDynamic or (isClassReactive and i > 1) then sw:Show() else sw:Hide() end
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateSwatchVis)
            UpdateSwatchVis()
        end
        -- Background Custom + Class swatch pair: clicking either toggles bgClassColored, the inactive one dims (mirrors the fill picker).
        do
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
                SSet("bgClassColored", true)
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end)
            bgClassSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSwatch, "Class Colored Background") end)
            bgClassSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            bgClassSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgClassSwatch

            local bgSwatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local c = SGet("customBgColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 17/255, 17/255, 17/255, 1
                end,
                function(r, g, b)
                    SWrite("customBgColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
            bgSwatch:SetScript("OnClick", function(self)
                if SVal("bgClassColored", false) then
                    SSet("bgClassColored", false)
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
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
            bgBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Fonts & Colors.") end)
            bgBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBgSwatchVis()
                if SVal("healthColorMode", "class") == "dark" then
                    bgSwatch:SetAlpha(0.3); bgClassSwatch:SetAlpha(0.3); bgBlock:Show()
                else
                    bgBlock:Hide()
                    local classOn = SVal("bgClassColored", false)
                    bgSwatch:SetAlpha(classOn and 0.3 or 1)
                    bgClassSwatch:SetAlpha(classOn and 1 or 0.3)
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatchVis)
            UpdateBgSwatchVis()
        end

        ns._editTargets = ns._editTargets or {}

        local healPredRow
        healPredRow, h = W:DualRow(parent, y,
            { type="toggle", text="Heal Prediction",
              getValue=function() return SVal("healPrediction", false) end,
              setValue=function(v) SSet("healPrediction", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Prediction Opacity", min=5, max=100, step=1,
              disabled=function() return not SVal("healPrediction", false) end,
              disabledTooltip="Heal Prediction",
              getValue=function() return SVal("healPredOpacity", 75) end,
              setValue=function(v) SSet("healPredOpacity", v) end });  y = y - h
        ns._editTargets.healPrediction = healPredRow
        if not EllesmereUI._prebuilding then
            local rgn = healPredRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healPredRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("healPredColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 102/255, 243/255, 102/255, 1
                end,
                function(r, g, b)
                    SWrite("healPredColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateHealPredSwatchVis()
                swatch:SetAlpha(SVal("healPrediction", false) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHealPredSwatchVis)
            UpdateHealPredSwatchVis()
        end

        -- Color Custom Borders (the Threat Borders and Dispel Border cogs) recolors the
        -- frame's own border, so it needs one to recolor: the EllesmereUI style, a Border
        -- Style other than Solid and a Border Size above 0 (runtime twin:
        -- ns.RF_CustomBorderOn). Cog rows re-check this on every open.
        local function CustomBorderOff()
            if ns.RF_Stock and ns.RF_Stock() then return true end
            local tex = SGet("borderTexture")
            return tex == nil or tex == "" or tex == "solid" or SVal("borderSize", 1) <= 0
        end
        local function CustomBorderOffTip()
            if ns.RF_Stock and ns.RF_Stock() then
                return EllesmereUI.BlizzStyle and EllesmereUI.BlizzStyle.Label("raidframes")
            end
            local tex = SGet("borderTexture")
            if tex == nil or tex == "" or tex == "solid" then
                return "This option requires a Border Style other than Solid."
            end
            return "This option requires a Border Size above 0."
        end

        local smoothThreatRow
        smoothThreatRow, h = W:DualRow(parent, y,
            { type="toggle", text="Smooth Health Bars",
              getValue=function() return SVal("smoothBars", true) end,
              setValue=function(v) SSet("smoothBars", v) end },
            { type="slider", text="Threat Borders", min=0, max=4, step=1,
              getValue=function() return SVal("threatBorderSize", 2) end,
              setValue=function(v) SSet("threatBorderSize", v) end });  y = y - h
        ns._editTargets.threat = smoothThreatRow
        ns._editTargets.animateBars = smoothThreatRow
        -- Cog on Threat Borders: Color Custom Borders recolors the frame's own border in
        -- the threat color on aggro, drawn instead of the inner border (the slider's
        -- size still applies whenever the recolor cannot).
        if not EllesmereUI._prebuilding then
            local rgn = smoothThreatRow._rightRegion
            -- Its only row needs a custom border: dimmed, with the reason, until there is one.
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = CustomBorderOff, disabledTooltip = CustomBorderOffTip, requireState = "disabled",
                title = "Threat Borders",
                rows = {
                    { type="toggle", label="Color Custom Borders",
                      tooltip="Recolors the frame border in the threat color while the unit has aggro instead of drawing a separate border.",
                      disabled=CustomBorderOff,
                      disabledTooltip=CustomBorderOffTip,
                      requireState="disabled",
                      get=function() return SVal("threatCustomBorder", false) end,
                      set=function(v) SSet("threatCustomBorder", v) end },
                },
            })
        end

        -------------------------------------------------------------------
        --  ABSORBS
        --  Own party-sync section ("absorbs"); pre-split profiles inherit the
        --  Health Bar sync state via ns._NormalizePartySyncSections.
        -------------------------------------------------------------------
        local absorbsHeader
        if onSection then onSection("healthBar", _secY, y) end; _secY = y
        absorbsHeader, h = W:SectionHeader(parent, "ABSORBS", y); y = y - h

        -- Eyeball: toggle shield/heal-absorb effects on the preview frames.
        do
            local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON

            local abLabel
            for _, rgn in ipairs({ absorbsHeader:GetRegions() }) do
                if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "ABSORBS" then
                    abLabel = rgn; break
                end
            end
            local eyeBtn = CreateFrame("Button", nil, absorbsHeader)
            eyeBtn:SetSize(24, 24)
            if abLabel then
                eyeBtn:SetPoint("LEFT", abLabel, "RIGHT", 5, 0)
            else
                eyeBtn:SetPoint("LEFT", absorbsHeader, "BOTTOMLEFT", 85, 8)
            end
            eyeBtn:SetFrameLevel(absorbsHeader:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()

            -- On ns so the preview renderer can read it.
            if ns._absorbsPreviewVisible == nil then ns._absorbsPreviewVisible = false end

            local function RefreshAbsorbEye()
                if IsPreviewOff() then
                    eyeTex:SetTexture(EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.15)
                    return
                end
                eyeTex:SetTexture(ns._absorbsPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
                eyeBtn:SetAlpha(0.4)
            end
            EYE.refreshAbsorbEye = RefreshAbsorbEye
            RefreshAbsorbEye()
            eyeBtn:SetScript("OnClick", function()
                if IsPreviewOff() then return end
                ns._absorbsPreviewVisible = not ns._absorbsPreviewVisible
                -- Indicators suppress bar effects, so clear them.
                if ns._absorbsPreviewVisible and ns._indicatorsVisible then
                    ns._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                end
                RefreshAbsorbEye()
                if ns.PvRefresh then ns.PvRefresh() end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if IsPreviewOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                    return
                end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._absorbsPreviewVisible and "Hide shield effects on preview" or "Show shield effects on preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                if not IsPreviewOff() then self:SetAlpha(0.4) end
                EllesmereUI.HideWidgetTooltip()
            end)
        end  -- close do (absorbs eyeball)

        local absorbRow
        absorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
              getValue=function() return SVal("absorbStyle", "none") end,
              setValue=function(v)
                  -- Blizzard Glow Line follows the pick: on with Default Blizz Frames, off when
                  -- leaving it, else kept. A set value is stored explicitly, so a party that
                  -- starts keeping its own style here keeps the line it showed; an unset one
                  -- stays unset and keeps following the style.
                  local was = SVal("absorbStyle", "none")
                  local glow = SGetPx("absorbGlowLine", "absorbStyle")
                  if v == "blizzardModern" then
                      glow = true
                  elseif was == "blizzardModern" then
                      glow = false
                  end
                  if glow ~= nil then SWrite("absorbGlowLine", glow == true) end
                  SSet("absorbStyle", v)
                  if v == "clean" then
                      SSet("absorbOpacity", 30)
                  elseif v ~= "blizzardModern" then
                      -- Blizzard (Modern) hardcodes color+opacity in the renderer; leave saved opacity untouched.
                      SSet("absorbOpacity", 90)
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Absorb Opacity", min=5, max=100, step=1,
              disabled=function()
                  local st = SVal("absorbStyle", "none")
                  return st == "none" or st == "blizzardModern"
              end,
              disabledTooltip="Absorb Style",
              getValue=function() return SVal("absorbOpacity", 90) end,
              setValue=function(v) SSet("absorbOpacity", v) end });  y = y - h
        ns._editTargets.absorbs = absorbRow
        if not EllesmereUI._prebuilding then
            local rgn = absorbRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, absorbRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("absorbColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    SWrite("absorbColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            -- BuildColorSwatch has no disabled state, so a mouse-enabled frame on top eats clicks when the color isn't user-editable (no absorb, or hardcoded-color "Blizzard (Modern)").
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:Hide()
            local function UpdateAbsorbSwatchVis()
                local st = SVal("absorbStyle", "none")
                local off = (st == "none" or st == "blizzardModern")
                swatch:SetAlpha(off and 0.3 or 1)
                if off then swatchBlock:Show() else swatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
            UpdateAbsorbSwatchVis()
        end
        -- Inline cog: absorb placement (overlay / right edge / left edge)
        do
            local rgn = absorbRow._leftRegion
            -- Placement labels follow the FILL AXIS: saved values stay right/left (meaning the FAR/NEAR end of the fill), worded top/bottom on a vertical bar.
            -- MUTATE IN PLACE, never rebuild this table: RefreshPage's fast path skips a full rebuild and the cog popup is built once then cached, so a fresh table would never reach the widget. The popup re-reads values[get()] every show; _invalidateMenu makes an already-built menu re-read entries from this same table on next click.
            local absorbEdgeLabels = { overlay = "Overlay", overlayReverse = "Overlay Reverse" }
            local absorbEdgeLabelsVert  -- last applied axis; nil until first sync
            -- (The Party Frames kit's bar always fills horizontally; decided at build.)
            local kitPage = ns.RF_OptPartyKit()
            -- Returns true ONLY when the axis flipped, so callers skip _invalidateMenu on unrelated refreshes -- it nils the cached menu and would break an open menu's wired click.
            local function SyncAbsorbEdgeLabels()
                local vert = (not kitPage) and SVal("healthVerticalFill", false) and true or false
                if absorbEdgeLabelsVert == vert then return false end
                absorbEdgeLabelsVert = vert
                absorbEdgeLabels.right = vert and "From Top Edge"    or "From Right Edge"
                absorbEdgeLabels.left  = vert and "From Bottom Edge" or "From Left Edge"
                return true
            end
            SyncAbsorbEdgeLabels()
            local _, cogShow = EllesmereUI.BuildInlineCog(rgn, {
                title = "Absorb Rendering",
                rows = {
                    { type="dropdown", label="Placement",
                      values = absorbEdgeLabels,
                      order = { "overlay", "overlayReverse", "right", "left" },
                      disabled = function() return SVal("absorbStyle", "none") == "blizzardModern" end,
                      disabledTooltip = "Default Blizz Frames uses a fixed placement",
                      rawTooltip = true,
                      get=function() SyncAbsorbEdgeLabels(); return SVal("absorbEdgeMode", "overlay") end,
                      set=function(v) SSet("absorbEdgeMode", v) end },
                    { type="dropdown", label="Show Overshield",
                      tooltip="Overshield is the part of an absorb exceeding your empty health. Always backfills it over current health from the shield's edge; From Left grows it from the opposite end of the bar; Never hides it.",
                      values = { never = "Never", always = "Always", fromleft = "From Left" },
                      order = { "never", "always", "fromleft" },
                      -- From Left only exists in the plain Overlay placement:
                      -- edge modes have no overshield and Overlay Reverse
                      -- already clamps the whole absorb inside the fill.
                      itemDisabled=function(v)
                          return v == "fromleft" and SVal("absorbEdgeMode", "overlay") ~= "overlay"
                      end,
                      get=function()
                          -- Legacy boolean fallback: profiles saved before the
                          -- dropdown keep their toggle's meaning.
                          local m = SVal("overshieldMode", nil)
                          if m == nil then m = (SVal("showOvershield", true) == false) and "never" or "always" end
                          return m
                      end,
                      set=function(v)
                          -- Mirror the legacy boolean so pre-dropdown readers
                          -- (incl. the live-client profile) track Never/Always.
                          SSet("showOvershield", v ~= "never")
                          SSet("overshieldMode", v)
                      end },
                    { type="toggle", label="Blizzard Glow Line",
                      tooltip="Adds the Default Blizz Frames glow line where the shield meets current health.",
                      disabled = function()
                          if (not kitPage) and SVal("healthVerticalFill", false) == true then return true end
                          return SVal("absorbEdgeMode", "overlay") == "left" and SVal("absorbStyle", "none") ~= "blizzardModern"
                      end,
                      disabledTooltip = "The glow line is not shown on a vertical fill or with the From Left Edge placement",
                      rawTooltip = true,
                      get=function()
                          -- Unset follows the style: on for Default Blizz Frames only.
                          local g = SGetPx("absorbGlowLine", "absorbStyle")
                          if g == nil then return SVal("absorbStyle", "none") == "blizzardModern" end
                          return g == true
                      end,
                      set=function(v) SSet("absorbGlowLine", v and true or false) end },
                },
            })
            -- Re-label on page refresh (Vertical Fill fires one) and drop any built menu so its entries rebuild with the new wording.
            EllesmereUI.RegisterWidgetRefresh(function()
                if not SyncAbsorbEdgeLabels() then return end
                local pf = cogShow and cogShow._popupFrame
                if pf and pf.GetChildren then
                    for _, child in ipairs({ pf:GetChildren() }) do
                        if child._invalidateMenu then child._invalidateMenu() end
                    end
                end
            end)
        end

        local function CurAbsorbBarPos()
            local p = SGet("absorbBarPosition")
            if p then return p end
            return SVal("absorbBarEnabled", false) and "aboveRight" or "none"
        end
        local absorbBarRow
        absorbBarRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Absorb Bar",
              values={ none="None", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left", rightVertical="Right Edge (Vertical)", leftVertical="Left Edge (Vertical)" },
              order={ "none", "aboveRight", "aboveLeft", "topRight", "topLeft", "rightVertical", "leftVertical" },
              getValue=function() return CurAbsorbBarPos() end,
              setValue=function(v)
                  SWrite("absorbBarEnabled", v ~= "none")  -- keep legacy flag in sync
                  SSet("absorbBarPosition", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Bar Height", min=1, max=20, step=1,
              disabled=function() return CurAbsorbBarPos() == "none" end,
              disabledTooltip="Absorb Bar",
              getValue=function() return SVal("absorbBarHeight", 4) end,
              setValue=function(v) SSet("absorbBarHeight", v) end });  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = absorbBarRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                -- Vertical Grow, its only setting, has no effect off the vertical positions.
                disabled = function()
                    local p = CurAbsorbBarPos()
                    return p ~= "rightVertical" and p ~= "leftVertical"
                end,
                disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                rawTooltip = true,
                title = "Absorb Bar Rendering",
                rows = {
                    { type="dropdown", label="Vertical Grow",
                      values = { up = "Up", down = "Down" },
                      order = { "up", "down" },
                      disabled = function()
                          local p = CurAbsorbBarPos()
                          return p ~= "rightVertical" and p ~= "leftVertical"
                      end,
                      disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                      rawTooltip = true,
                      get=function() return SVal("absorbBarGrowDir", "up") end,
                      set=function(v) SSet("absorbBarGrowDir", v) end },
                },
            })
        end
        -- The size slider reads as width for the vertical positions; retitle live.
        do
            local lbl = absorbBarRow._rightRegion._label
            local function UpdateAbsorbBarSizeLabel()
                local p = CurAbsorbBarPos()
                local vertical = p == "rightVertical" or p == "leftVertical"
                lbl:SetText(EllesmereUI.L(vertical and "Bar Width" or "Bar Height"))
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbBarSizeLabel)
            UpdateAbsorbBarSizeLabel()
        end
        if not EllesmereUI._prebuilding then
            local rgn = absorbBarRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, absorbBarRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("absorbBarColor")
                    if c then return c.r, c.g, c.b, c.a or 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b, a)
                    SWrite("absorbBarColor", { r=r, g=g, b=b, a=a })
                    ReloadAndUpdate()
                end, true, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateAbsorbBarSwatchVis()
                swatch:SetAlpha(CurAbsorbBarPos() ~= "none" and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbBarSwatchVis)
            UpdateAbsorbBarSwatchVis()
        end

        local healAbsorbRow
        healAbsorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Style", values=absorbStyleValues, order=healAbsorbStyleOrder,
              getValue=function() return SVal("healAbsorbStyle", "clean") end,
              setValue=function(v)
                  SSet("healAbsorbStyle", v)
                  if v == "clean" then
                      SSet("healAbsorbOpacity", 50)
                  else
                      SSet("healAbsorbOpacity", 75)
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Heal Absorb Opacity", min=5, max=100, step=1,
              disabled=function() return SVal("healAbsorbStyle", "clean") == "none" end,
              disabledTooltip="Heal Absorb Style",
              getValue=function() return SVal("healAbsorbOpacity", 75) end,
              setValue=function(v) SSet("healAbsorbOpacity", v) end });  y = y - h
        ns._editTargets.healAbsorbs = healAbsorbRow
        if not EllesmereUI._prebuilding then
            local rgn = healAbsorbRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healAbsorbRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("healAbsorbColor")
                    if c then return c.r or 0.8, c.g or 0.15, c.b or 0.15, 1 end
                    return 0.8, 0.15, 0.15, 1
                end,
                function(r, g, b)
                    SWrite("healAbsorbColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            -- Blocked for "none" and the pre-colored heal styles (healBlizzModern is hardcoded white).
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:Hide()
            local function UpdateHealAbsorbSwatchVis()
                local st = SVal("healAbsorbStyle", "clean")
                local off = (st == "none" or st == "healBlizzModern" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR")
                swatch:SetAlpha(off and 0.3 or 1)
                if off then swatchBlock:Show() else swatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
            UpdateHealAbsorbSwatchVis()
        end
        -- Inline cog: heal absorb placement (independent of shield absorb)
        do
            local rgn = healAbsorbRow._leftRegion
            -- Same axis-labelling contract as the shield absorb cog above (MUTATE IN PLACE; return true only on a real axis flip).
            local healAbsorbEdgeLabels = { overlay = "Overlay" }
            local healAbsorbEdgeLabelsVert  -- last applied axis; nil until first sync
            local kitPage = ns.RF_OptPartyKit()
            local function SyncHealAbsorbEdgeLabels()
                local vert = (not kitPage) and SVal("healthVerticalFill", false) and true or false
                if healAbsorbEdgeLabelsVert == vert then return false end
                healAbsorbEdgeLabelsVert = vert
                healAbsorbEdgeLabels.right = vert and "From Top Edge"    or "From Right Edge"
                healAbsorbEdgeLabels.left  = vert and "From Bottom Edge" or "From Left Edge"
                return true
            end
            SyncHealAbsorbEdgeLabels()
            local _, cogShow = EllesmereUI.BuildInlineCog(rgn, {
                title = "Heal Absorb Rendering",
                rows = {
                    { type="dropdown", label="Placement",
                      values = healAbsorbEdgeLabels,
                      order = { "overlay", "right", "left" },
                      get=function() SyncHealAbsorbEdgeLabels(); return SVal("healAbsorbEdgeMode", "overlay") end,
                      set=function(v) SSet("healAbsorbEdgeMode", v) end },
                    { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                      get=function() return SVal("healAbsorbBgOpacity", 25) end,
                      set=function(v) SSet("healAbsorbBgOpacity", v) end },
                    { type="toggle", label="Show Over Dispels",
                      get=function() return SVal("healAbsorbOverDispel", false) == true end,
                      set=function(v) SSet("healAbsorbOverDispel", v) end },
                },
            })
            EllesmereUI.RegisterWidgetRefresh(function()
                if not SyncHealAbsorbEdgeLabels() then return end
                local pf = cogShow and cogShow._popupFrame
                if pf and pf.GetChildren then
                    for _, child in ipairs({ pf:GetChildren() }) do
                        if child._invalidateMenu then child._invalidateMenu() end
                    end
                end
            end)
        end

        do
            local function CurHealAbsorbBarPos()
                return SGet("healAbsorbBarPosition") or "none"
            end
            local healAbsorbBarRow
            healAbsorbBarRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Heal Absorb Bar",
                  values={ none="None", belowAbsorb="Below Absorb Bar", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left", rightVertical="Right Edge (Vertical)", leftVertical="Left Edge (Vertical)" },
                  order={ "none", "belowAbsorb", "aboveRight", "aboveLeft", "topRight", "topLeft", "rightVertical", "leftVertical" },
                  getValue=function() return CurHealAbsorbBarPos() end,
                  setValue=function(v) SSet("healAbsorbBarPosition", v); EllesmereUI:RefreshPage() end },
                { type="slider", text="Bar Height", min=1, max=20, step=1,
                  disabled=function() return CurHealAbsorbBarPos() == "none" end,
                  disabledTooltip="Heal Absorb Bar",
                  getValue=function() return SVal("healAbsorbBarHeight", 4) end,
                  setValue=function(v) SSet("healAbsorbBarHeight", v) end });  y = y - h
            if not EllesmereUI._prebuilding then
                local rgn = healAbsorbBarRow._rightRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, healAbsorbBarRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("healAbsorbBarColor")
                        if c then return c.r, c.g, c.b, c.a or 1 end
                        return 200/255, 29/255, 29/255, 1
                    end,
                    function(r, g, b, a)
                        SWrite("healAbsorbBarColor", { r=r, g=g, b=b, a=a })
                        ReloadAndUpdate()
                    end, true, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                local function UpdateHealAbsorbBarSwatchVis()
                    swatch:SetAlpha(CurHealAbsorbBarPos() ~= "none" and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbBarSwatchVis)
                UpdateHealAbsorbBarSwatchVis()
            end
            if not EllesmereUI._prebuilding then
                local rgn = healAbsorbBarRow._leftRegion
                EllesmereUI.BuildInlineCog(rgn, {
                    -- Vertical Grow is inert off the vertical positions.
                    disabled = function()
                        local p = CurHealAbsorbBarPos()
                        return p ~= "rightVertical" and p ~= "leftVertical"
                    end,
                    disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                    rawTooltip = true,
                    title = "Heal Absorb Bar Rendering",
                    rows = {
                        { type="dropdown", label="Vertical Grow",
                          values = { up = "Up", down = "Down" },
                          order = { "up", "down" },
                          disabled = function()
                              local p = CurHealAbsorbBarPos()
                              return p ~= "rightVertical" and p ~= "leftVertical"
                          end,
                          disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                          rawTooltip = true,
                          get=function() return SVal("healAbsorbBarGrowDir", "up") end,
                          set=function(v) SSet("healAbsorbBarGrowDir", v) end },
                    },
                })
            end
            -- The size slider reads as width for the vertical positions; retitle live.
            do
                local lbl = healAbsorbBarRow._rightRegion._label
                local function UpdateHealAbsorbBarSizeLabel()
                    local p = CurHealAbsorbBarPos()
                    local vertical = p == "rightVertical" or p == "leftVertical"
                    lbl:SetText(EllesmereUI.L(vertical and "Bar Width" or "Bar Height"))
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbBarSizeLabel)
                UpdateHealAbsorbBarSizeLabel()
            end
        end

        -- Max Health Texture (+swatch+cog) | Max Health Opacity. Styles mirror Heal Absorb plus "Max Health Stripes" first; no placement control, overlay is always right-anchored.
        do
            local maxHealthRow
            maxHealthRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Max Health Style", values=absorbStyleValues,
                  order=maxHealthStyleOrder,
                  getValue=function() return SVal("maxHealthStyle", "maxHealthStripes") end,
                  setValue=function(v) SSet("maxHealthStyle", v); EllesmereUI:RefreshPage() end },
                { type="slider", text="Max Health Opacity", min=5, max=100, step=1,
                  disabled=function() return SVal("maxHealthStyle", "maxHealthStripes") == "none" end,
                  disabledTooltip="Max Health Style",
                  getValue=function() return SVal("maxHealthOpacity", 100) end,
                  setValue=function(v) SSet("maxHealthOpacity", v) end });  y = y - h
            -- Swatch tints the max health texture.
            if not EllesmereUI._prebuilding then
                local rgn = maxHealthRow._leftRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, maxHealthRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("maxHealthColor")
                        if c then return c.r or 0.7, c.g or 0.1, c.b or 0.1, 1 end
                        return 0.7, 0.1, 0.1, 1
                    end,
                    function(r, g, b)
                        SWrite("maxHealthColor", { r=r, g=g, b=b })
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                -- Blocked for "none" and the pre-colored styles.
                local swatchBlock = CreateFrame("Frame", nil, swatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                swatchBlock:Hide()
                local function UpdateMaxHealthSwatchVis()
                    local st = SVal("maxHealthStyle", "maxHealthStripes")
                    local off = (st == "none" or st == "healBlizzModern" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR")
                    swatch:SetAlpha(off and 0.3 or 1)
                    if off then swatchBlock:Show() else swatchBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateMaxHealthSwatchVis)
                UpdateMaxHealthSwatchVis()
            end
            -- Cog carries backing opacity only; placement is fixed right-side.
            if not EllesmereUI._prebuilding then
                local rgn = maxHealthRow._leftRegion
                EllesmereUI.BuildInlineCog(rgn, {
                    title = "Max Health Rendering",
                    rows = {
                        { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                          get=function() return SVal("maxHealthBgOpacity", 100) end,
                          set=function(v) SSet("maxHealthBgOpacity", v) end },
                    },
                })
            end
        end

        -------------------------------------------------------------------
        --  POWER BAR
        -------------------------------------------------------------------
        local powerHeader
        if onSection then onSection("absorbs", _secY, y) end; _secY = y
        powerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

        -- Power bar animation: same pattern as health, serves raid + party.
        do
            local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
            -- On ns: single ticker, resolves the active preview at call time.
            ns._powerAnimState = ns._powerAnimState or {}

            local function StopPowerAnim()
                if ns._powerAnimTicker then
                    ns._powerAnimTicker:Cancel()
                    ns._powerAnimTicker = nil
                end
                ns._powerAnimActive = false
                local ppv = ns.PvPowerValues()
                if ppv then
                    for i, st in ipairs(ns._powerAnimState) do
                        ppv[i] = st.current
                    end
                end
            end
            -- Exposed for onModuleLeave below.
            ns.StopPowerAnim = StopPowerAnim

            local function StartPowerAnim()
                if ns._powerAnimTicker then return end
                ns._powerAnimActive = true
                wipe(ns._powerAnimState)

                local frames = ns.PvActiveFrames()
                for i = 1, 20 do
                    local f = frames[i]
                    if f and f._power and f._power:IsShown() then
                        local cur = f._powerPct or (50 + math.random(50))
                        ns._powerAnimState[i] = {
                            frame = f,
                            current = cur,
                            target = math.max(10, math.min(100, cur + math.random(-8, 8))),
                            snapTimer = math.random() * 3,
                            nextSnap = 1.8 + math.random() * 2.3,
                        }
                    end
                end

                local pwSmoothInterp = Enum and Enum.StatusBarInterpolation
                    and Enum.StatusBarInterpolation.ExponentialEaseOut
                ns._powerAnimTicker = C_Timer.NewTicker(0.1, function()
                    if not ns._powerAnimActive then return end
                    -- Effective overlay; see the health ticker note above.
                    local smooth = ((ns.PvEffectiveProfile and ns.PvEffectiveProfile())
                        or db.profile).smoothPowerBars

                    for i, st in pairs(ns._powerAnimState) do
                        local f = st.frame
                        if f and f._power then
                            st.snapTimer = st.snapTimer + 0.1
                            if st.snapTimer < st.nextSnap then
                            else
                                st.snapTimer = 0
                                st.nextSnap = 2.5 + math.random() * 3
                                st.current = st.target
                                st.target = math.max(10, math.min(100, st.current + math.random(-8, 8)))

                                if smooth and pwSmoothInterp then
                                    f._power:SetValue(st.current, pwSmoothInterp)
                                else
                                    f._power:SetValue(st.current)
                                end
                            end
                        end
                    end
                end)
            end

            local pwLabel
            for _, rgn in ipairs({ powerHeader:GetRegions() }) do
                if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "POWER BAR" then
                    pwLabel = rgn; break
                end
            end
            local eyeBtn = CreateFrame("Button", nil, powerHeader)
            eyeBtn:SetSize(24, 24)
            if pwLabel then
                eyeBtn:SetPoint("LEFT", pwLabel, "RIGHT", 5, 0)
            else
                eyeBtn:SetPoint("LEFT", powerHeader, "BOTTOMLEFT", 85, 8)
            end
            eyeBtn:SetFrameLevel(powerHeader:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshPowerEye()
                if IsPreviewOff() then
                    eyeTex:SetTexture(EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.15)
                    return
                end
                eyeTex:SetTexture(ns._powerAnimActive and EYE_INVISIBLE or EYE_VISIBLE)
                eyeBtn:SetAlpha(0.4)
            end
            EYE.refreshPowerEye = RefreshPowerEye
            ns._stopPowerAnim = StopPowerAnim
            RefreshPowerEye()
            eyeBtn:SetScript("OnClick", function()
                if IsPreviewOff() then return end
                if ns._powerAnimActive then
                    StopPowerAnim()
                else
                    if ns._indicatorsVisible then
                        ns._indicatorsVisible = false
                        if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                    end
                    StartPowerAnim()
                end
                RefreshPowerEye()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if IsPreviewOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                    return
                end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._powerAnimActive and "Stop power animation" or "Animate power bars")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                if not IsPreviewOff() then self:SetAlpha(0.4) end
                EllesmereUI.HideWidgetTooltip()
            end)

            EllesmereUI:RegisterOnHide(function()
                if ns._powerAnimActive then StopPowerAnim(); RefreshPowerEye() end
            end)
        end  -- close do (power eyeball)

        -- Power bar is off when no role is selected.
        -- The Party Frames kit's mana bar always shows. Decided at build time:
        -- the page being built is only known then, and this runs on refreshes.
        local IsPowerOff = ns.RF_OptPartyKit() and function() return false end or function()
            return not SVal("powerShowForHealer", true) and not SVal("powerShowForTank", true) and not SVal("powerShowForDPS", false)
        end

        do
            local showForItems = {
                { key = "healer", label = "Healers" },
                { key = "tank",   label = "Tanks" },
                { key = "dps",    label = "DPS" },
            }
            local showForKeyMap = { healer = "powerShowForHealer", tank = "powerShowForTank", dps = "powerShowForDPS" }
            -- Party Frames kit: the stock mana bar always shows at the stock
            -- size, so this row (and its cog) hides on the Party page.
            row, h = W:DualRow(parent, y,
                ns.RF_PartyKitGate({ type="dropdown", text="Show Power Bar For",
                  values={ __placeholder = "Healers, Tanks" }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end }),
                ns.RF_PartyKitGate({ type="slider", text="Power Height", min=1, max=20, step=1,
                  disabled=function() return IsPowerOff() end,
                  disabledTooltip="Show Power Bar For",
                  getValue=function() return SVal("powerHeight", 4) end,
                  setValue=function(v) SSet("powerHeight", v) end }));  y = y - h
            -- Cog: uniform icon anchoring. Greyed + blocked while no role shows a power bar (nothing to ignore then).
            do
                local rgn = row._rightRegion
                EllesmereUI.BuildInlineCog(rgn, {
                    disabled = IsPowerOff, disabledTooltip = "Show Power Bar For",
                    title = "Power Height",
                    rows = {
                        { type="toggle", label="Icons Ignore Power Bar",
                          tooltip="Anchor icons and text as if no power bar existed, so frames with and without one line up identically.",
                          get=function() return SVal("powerUniformAnchors", false) end,
                          set=function(v) SSet("powerUniformAnchors", v) end },
                        { type="toggle", label="Extend Health Bar Behind Power",
                          tooltip="Health bar spans the full frame height and the power bar draws on top of it.",
                          get=function() return SVal("extendHealthBehindPower", false) end,
                          set=function(v) SSet("extendHealthBehindPower", v) end },
                    },
                })
            end
            if not EllesmereUI._prebuilding then
                local rgn = row._leftRegion
                if rgn._control then rgn._control:Hide() end
                local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 170, rgn:GetFrameLevel() + 2,
                    showForItems,
                    function(k) return SVal(showForKeyMap[k], true) end,
                    function(k, v)
                        SSet(showForKeyMap[k], v)
                        if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                        EllesmereUI:RefreshPage()
                    end)
                PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD
                rgn._lastInline = nil
            end
        end

        local pwBorderStyleValues = {
            eui     = "EllesmereUI",
            divider = "Divider",
            border  = "Border",
        }
        local pwBorderStyleOrder = { "eui", "divider", "border" }
        -- Classic WoW UI draws the stock health/power divider in place of the
        -- power border (Blizzard Style has none, so the row stays there).
        local function PwClassicGate(cfg)
            if EllesmereUI.BlizzStyle and EllesmereUI.BlizzStyle.Active("raidframes") == "classic" then
                return EllesmereUI.BlizzStyle.Gate("raidframes", cfg)
            end
            return cfg
        end
        local pwBdrRow
        pwBdrRow, h = W:DualRow(parent, y,
            ns.RF_PartyKitGate(PwClassicGate({ type="dropdown", text="Border Style", values=pwBorderStyleValues, order=pwBorderStyleOrder,
              disabled=function() return IsPowerOff() end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerBorderStyle", "divider") end,
              setValue=function(v) SSet("powerBorderStyle", v); EllesmereUI:RefreshPage() end })),
            ns.RF_PartyKitGate(PwClassicGate({ type="slider", text="Border Size", min=0, max=4, step=1,
              disabled=function() return IsPowerOff() or SVal("powerBorderStyle", "eui") == "eui" end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerBorderSize", 1) end,
              setValue=function(v) SSet("powerBorderSize", v) end })));  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = pwBdrRow._rightRegion
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, pwBdrRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("powerBorderColor")
                    if c then return c.r, c.g, c.b, SVal("powerBorderAlpha", 1) end
                    return 0, 0, 0, 1
                end,
                function(r, g, b, a)
                    SWrite("powerBorderColor", { r=r, g=g, b=b })
                    SWrite("powerBorderAlpha", a)
                    ReloadAndUpdate()
                end, true, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10); block:EnableMouse(true)
            block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Border Style")) end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdatePwBdrSwatchState()
                local off = IsPowerOff() or SVal("powerBorderSize", 1) == 0 or SVal("powerBorderStyle", "eui") == "eui"
                if off then swatch:SetAlpha(0.3); block:Show() else swatch:SetAlpha(1); block:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() if updateSwatch then updateSwatch() end; UpdatePwBdrSwatchState() end)
            UpdatePwBdrSwatchState()
        end

        local pwBgRow
        pwBgRow, h = W:DualRow(parent, y,
            { type="toggle", text="Smooth Power Bars",
              disabled=function() return IsPowerOff() end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("smoothPowerBars", true) end,
              setValue=function(v) SSet("smoothPowerBars", v) end },
            { type="slider", text="Background", min=0, max=100, step=1,
              disabled=function() return IsPowerOff() end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerBgDarkness", 70) end,
              setValue=function(v) SSet("powerBgDarkness", v) end });  y = y - h
        -- Power bg Custom + Power Colored swatch pair: clicking either toggles powerBgPowerColored, the inactive one dims (mirrors the health bg).
        do
            local rgn = pwBgRow._rightRegion
            -- Power swatch shows the player's power color and is not editable.
            local bgPwrSwatch = EllesmereUI.BuildColorSwatch(
                rgn, pwBgRow:GetFrameLevel() + 3,
                function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    local f = EllesmereUI.GetPowerBgDarkenFactor()
                    if info then return info.r * f, info.g * f, info.b * f, 1 end
                    return 0, 0.5 * f, f, 1
                end,
                function() end, false, 20)
            bgPwrSwatch:SetScript("OnClick", function()
                SSet("powerBgPowerColored", true)
                EllesmereUI:RefreshPage()
            end)
            bgPwrSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSwatch, "Power Colored Background. Power colors can be adjusted in Global Settings -> Fonts & Colors.") end)
            bgPwrSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            bgPwrSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgPwrSwatch

            local bgSwatch = EllesmereUI.BuildColorSwatch(
                rgn, pwBgRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("powerBgColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 0, 0, 0, 1
                end,
                function(r, g, b)
                    SWrite("powerBgColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
            bgSwatch:SetScript("OnClick", function(self)
                if SVal("powerBgPowerColored", false) then
                    SSet("powerBgPowerColored", false)
                    EllesmereUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            bgSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Custom Colored Background") end)
            bgSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSwatch

            local function UpdatePwBgSwatchVis()
                local pwrOn = SVal("powerBgPowerColored", false)
                bgSwatch:SetAlpha(pwrOn and 0.3 or 1)
                bgPwrSwatch:SetAlpha(pwrOn and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdatePwBgSwatchVis)
            UpdatePwBgSwatchVis()
        end

        -------------------------------------------------------------------
        --  TEXT DISPLAY
        -------------------------------------------------------------------
        if onSection then onSection("powerBar", _secY, y) end; _secY = y
        _, h = W:SectionHeader(parent, "TEXT DISPLAY", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Name Size", min=6, max=26, step=1,
              getValue=function() return SVal("nameSize", 10) end,
              setValue=function(v) SSet("nameSize", v) end },
            { type="multiSwatch", text="Name Color",
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("nameCustomColor")
                      if c then return c.r, c.g, c.b end
                      return 1, 1, 1
                  end,
                  setValue = function(r, g, b)
                      SWrite("nameCustomColor", { r=r, g=g, b=b })
                      ReloadAndUpdate()
                  end,
                  onClick = function(self)
                      if SVal("nameColorMode", "class") ~= "custom" then
                          SSet("nameColorMode", "custom")
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return SVal("nameColorMode", "class") == "custom" and 1 or 0.3
                  end },
                { tooltip = "Class Color",
                  hasAlpha = false,
                  getValue = function()
                      local _, ct = UnitClass("player")
                      if ct and RAID_CLASS_COLORS[ct] then
                          local cc = RAID_CLASS_COLORS[ct]
                          return cc.r, cc.g, cc.b
                      end
                      return 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSet("nameColorMode", "class")
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SVal("nameColorMode", "class") == "class" and 1 or 0.3
                  end },
                { tooltip = "Accent Color",
                  hasAlpha = false,
                  getValue = function()
                      return EllesmereUI.ResolveActiveAccent()
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSet("nameColorMode", "accent")
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SVal("nameColorMode", "class") == "accent" and 1 or 0.3
                  end },
              } });  y = y - h
        -- Name char cap + text stacking cog, on the Name Size slider.
        do
            local rgn = row._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Name Text",
                rows = {
                    { type="slider", label="Max Characters (0=off)", min=0, max=30, step=1,
                      get=function() return SVal("nameMaxLength", 15) end,
                      set=function(v) SSet("nameMaxLength", v) end },
                    { type="toggle", label="Show Above Icons",
                      tooltip="Render the name and health text above buff and debuff icons.",
                      get=function() return SVal("nameTextAboveIcons", false) end,
                      set=function(v) SSet("nameTextAboveIcons", v) end },
                },
            })
        end

        -- Party Frames kit: the name has the stock spot (its offsets stay on
        -- the cog), so the dropdown only chooses shown or None.
        row, h = W:DualRow(parent, y,
            ns.RF_OptPartyKit() and { type="dropdown", text="Name Position",
              values={ kit = "Party Frame", none = "None" }, order={ "kit", "none" },
              getValue=function() return (SVal("namePosition", "center") == "none") and "none" or "kit" end,
              setValue=function(v)
                  if v == "none" then SSet("namePosition", "none")
                  elseif SVal("namePosition", "center") == "none" then SSet("namePosition", "topleft") end
              end }
            or { type="dropdown", text="Name Position", values=namePositionValuesName, order=namePositionOrderName,
              getValue=function() return SVal("namePosition", "center") end,
              setValue=function(v) SSet("namePosition", v) end },
            { type="dropdown", text="Health Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return SVal("healthTextMode", "none") end,
              -- Rebuilds the page on the None <-> not-None flip so the Position/Size row below appears/vanishes.
              setValue=EllesmereUI.DependentSetValue(
                  function() return SVal("healthTextMode", "none") ~= "none" end,
                  function(v) SSet("healthTextMode", v) end) });  y = y - h
        do
            local rgn = row._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Name Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("nameOffsetX", 0) end,
                      set=function(v) SSet("nameOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("nameOffsetY", 0) end,
                      set=function(v) SSet("nameOffsetY", v) end },
                },
            })
        end
        -- Health Text color swatches (custom/class/accent), mirroring the Name Color triple. Custom is added FIRST so the _lastInline chain places it next to the dropdown, matching Name Color.
        if not EllesmereUI._prebuilding then
            local rgn = row._rightRegion
            local function AddHTSwatch(getColor, setColor, mode, opensPicker, tooltip)
                local sw = EllesmereUI.BuildColorSwatch(
                    rgn, row:GetFrameLevel() + 3, getColor, setColor, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = sw
                -- Preserve the picker-opening click, then switch mode on click (same technique multiSwatch uses for Name Color).
                sw._eabOrigClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self)
                    if SVal("healthTextColorMode", "custom") ~= mode then
                        SSet("healthTextColorMode", mode)
                        EllesmereUI:RefreshPage()
                        return
                    end
                    if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
                end)
                -- HookScript so BuildColorSwatch's own hover stays intact.
                if tooltip then
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tooltip) end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end
                local function vis()
                    sw:SetAlpha(SVal("healthTextColorMode", "custom") == mode and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(vis)
                vis()
            end
            -- Custom (rightmost): editable, opens the picker when active.
            AddHTSwatch(
                function()
                    local c = SGet("healthTextCustomColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    SWrite("healthTextCustomColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, "custom", true, "Custom Color")
            AddHTSwatch(
                function()
                    local _, ct = UnitClass("player")
                    if ct and RAID_CLASS_COLORS[ct] then
                        local cc = RAID_CLASS_COLORS[ct]
                        return cc.r, cc.g, cc.b, 1
                    end
                    return 1, 1, 1, 1
                end,
                function() end, "class", false, "Class Color")
            -- Accent (leftmost).
            AddHTSwatch(
                function()
                    local r, g, b = EllesmereUI.ResolveActiveAccent()
                    return r or 1, g or 1, b or 1, 1
                end,
                function() end, "accent", false, "Accent Color")
        end

        -- Health Text Position (+ cog for X/Y) | Health Text Size. Hidden entirely while Health Text is None.
        if SVal("healthTextMode", "none") ~= "none" then
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Health Text Position", values=namePositionValues, order=namePositionOrder,
              getValue=function() return SVal("healthTextPosition", "center") end,
              setValue=function(v) SSet("healthTextPosition", v) end },
            { type="slider", text="Health Text Size", min=6, max=26, step=1,
              getValue=function() return SVal("healthTextSize", 9) end,
              setValue=function(v) SSet("healthTextSize", v) end });  y = y - h
        do
            local rgn = row._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Health Text Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("healthTextOffsetX", 0) end,
                      set=function(v) SSet("healthTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("healthTextOffsetY", 0) end,
                      set=function(v) SSet("healthTextOffsetY", v) end },
                },
            })
        end
        end   -- close Health Text dependent-row gate

        -- Heal Absorb Text (+swatches) | Heal Absorb Text Position (+offset cog); Heal Absorb Text Size row is 1:1 with Health Text. Shows the heal-absorb shield amount (short/full), hidden at zero.
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Text",
              values={ ["none"]="None", ["short"]="Short (240k)", ["amount"]="Amount" },
              order={ "none", "short", "amount" },
              getValue=function() return SVal("healAbsorbTextMode", "none") end,
              -- Rebuilds the page on the None <-> not-None flip so the Text Size row below appears/vanishes.
              setValue=EllesmereUI.DependentSetValue(
                  function() return SVal("healAbsorbTextMode", "none") ~= "none" end,
                  function(v) SSet("healAbsorbTextMode", v); EllesmereUI:RefreshPage() end) },
            { type="dropdown", text="Heal Absorb Text Position", values=namePositionValues, order=namePositionOrder,
              disabled=function() return SVal("healAbsorbTextMode", "none") == "none" end,
              disabledTooltip="Heal Absorb Text",
              getValue=function() return SVal("healAbsorbTextPosition", "center") end,
              setValue=function(v) SSet("healAbsorbTextPosition", v) end });  y = y - h
        -- Heal Absorb Text swatches (custom/class/accent), same pattern as the Health Text triple above.
        if not EllesmereUI._prebuilding then
            local rgn = row._leftRegion
            local function AddHASwatch(getColor, setColor, mode, opensPicker, tooltip)
                local sw = EllesmereUI.BuildColorSwatch(
                    rgn, row:GetFrameLevel() + 3, getColor, setColor, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = sw
                sw._eabOrigClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self)
                    if SVal("healAbsorbTextColorMode", "custom") ~= mode then
                        SSet("healAbsorbTextColorMode", mode)
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
                    sw:SetAlpha(SVal("healAbsorbTextColorMode", "custom") == mode and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(vis)
                vis()
            end
            -- Custom (rightmost): editable, opens the picker when active.
            AddHASwatch(
                function()
                    local c = SGet("healAbsorbTextCustomColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 0.3, 0.3, 1
                end,
                function(r, g, b)
                    SWrite("healAbsorbTextCustomColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, "custom", true, "Custom Color")
            AddHASwatch(
                function()
                    local _, ct = UnitClass("player")
                    if ct and RAID_CLASS_COLORS[ct] then
                        local cc = RAID_CLASS_COLORS[ct]
                        return cc.r, cc.g, cc.b, 1
                    end
                    return 1, 1, 1, 1
                end,
                function() end, "class", false, "Class Color")
            -- Accent (leftmost).
            AddHASwatch(
                function()
                    local r, g, b = EllesmereUI.ResolveActiveAccent()
                    return r or 1, g or 1, b or 1, 1
                end,
                function() end, "accent", false, "Accent Color")
        end
        -- Offset cog on the Heal Absorb Text Position region.
        do
            local rgn = row._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function() return SVal("healAbsorbTextMode", "none") == "none" end,
                disabledTooltip = "Heal Absorb Text",
                title = "Heal Absorb Text Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("healAbsorbTextOffsetX", 0) end,
                      set=function(v) SSet("healAbsorbTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("healAbsorbTextOffsetY", 0) end,
                      set=function(v) SSet("healAbsorbTextOffsetY", v) end },
                },
            })
        end
        -- Row 5: Heal Absorb Text Size | (blank odd last slot). Hidden entirely
        -- while Heal Absorb Text is None.
        if SVal("healAbsorbTextMode", "none") ~= "none" then
            row, h = W:DualRow(parent, y,
                { type="slider", text="Heal Absorb Text Size", min=6, max=26, step=1,
                  getValue=function() return SVal("healAbsorbTextSize", 9) end,
                  setValue=function(v) SSet("healAbsorbTextSize", v) end },
                { type="label", text="" });  y = y - h
        end

        -------------------------------------------------------------------
        --  INDICATORS
        -------------------------------------------------------------------
        local indicatorHeader
        if onSection then onSection("textDisplay", _secY, y) end; _secY = y
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
        local roleStyleOrder = { "none", "modern", "blizzLight", "modernCircle", "styled", "classicCircle", "classic", "blizzDefault" }
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

        -- Rows below Marker Position are the less-common indicators. The RAID tab collapses them behind the shared session expander (BuildLessCommonExpander in EllesmereUI_Widgets.lua, honors the global Auto Expand Less Common Settings toggle); the party tab always shows them.
        local lessCommonOpen = true
        if not _partyCtx then
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
        if not _partyCtx then
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
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Dispel Border",
                rows = {
                    { type="slider", label="Debuff Icon Border", min=-1, max=4, step=1,
                      tooltip="Thickness in physical pixels. -1 follows the Debuff Manager's Border setting, 0 hides the dispel color border.",
                      get=function() return SVal("dispelIconBorderSize", 2) end,
                      set=function(v) SSet("dispelIconBorderSize", v) end },
                    { type="toggle", label="Color Custom Borders",
                      tooltip="Recolors the frame border in the dispel type color while a debuff of that type is shown.",
                      -- Copies the frame's own border: only over a custom border (CustomBorderOff).
                      disabled=CustomBorderOff,
                      disabledTooltip=CustomBorderOffTip,
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
            { type="label", text="" });  y = y - h
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
        if not _partyCtx then
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
                      if ns.FB_Apply then ns.FB_Apply() end
                      EllesmereUI:RefreshPage()
                  end) },
                (not FBEnabled()) and { type="label", text="" } or
                { type="dropdown", text="Position",
                  values = { left="Before First Group", right="After Last Group", free="Free Move" },
                  order  = { "left", "right", "free" },
                  getValue = function() return FBSet().position or "right" end,
                  setValue = function(v)
                      FBSet().position = v
                      if v ~= "free" and ns.FB_SetMoverShown then ns.FB_SetMoverShown(false) end
                      if ns.FB_Apply then ns.FB_Apply() end
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
                              if ns.FB_Apply then ns.FB_Apply() end
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
                local btn = CreateFrame("Button", nil, row)
                btn:SetSize(140, 26)
                btn:SetPoint("RIGHT", row._leftRegion, "RIGHT", -20, 0)
                btn:SetFrameLevel(row:GetFrameLevel() + 5)
                local bbg = btn:CreateTexture(nil, "BACKGROUND")
                bbg:SetAllPoints()
                bbg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
                EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
                local lbl = btn:CreateFontString(nil, "OVERLAY")
                EllesmereUI.ApplyModuleFont(lbl, nil, 13, "raidFrames")
                lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
                lbl:SetText(EllesmereUI.L("Move Frames"))

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
                              if ns.FB_Apply then ns.FB_Apply() end
                              -- Resize/reposition the drag overlay if it is up.
                              if ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                                 and ns.FB_SetMoverShown then
                                  ns.FB_SetMoverShown(true)
                              end
                          end },
                    },
                })

                -- Capture the region NOW: the shared `row` local is reused by later rows, so closures must not read it at refresh time.
                local fmRegion = row._leftRegion
                local function MoveAllowed()
                    return FBEnabled() and (FBSet().position == "free")
                        and not InCombatLockdown()
                end
                local function UpdateMoveBtn()
                    local active = ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                    lbl:SetText(active and EllesmereUI.L("Stop Moving") or EllesmereUI.L("Move Frames"))
                    btn:SetAlpha(MoveAllowed() and 1 or 0.35)
                    -- Plain-label slots have no native disabled handling.
                    if fmRegion._label then
                        fmRegion._label:SetAlpha(FBEnabled() and 1 or 0.3)
                    end
                end
                btn:SetScript("OnEnter", function(self)
                    if not FBEnabled() then
                        EllesmereUI.ShowWidgetTooltip(self, FB_DISABLED_TIP)
                    elseif not MoveAllowed() then
                        EllesmereUI.ShowWidgetTooltip(self,
                            EllesmereUI.DisabledTooltip("Position must be set to Free Move"))
                    else
                        EllesmereUI.ShowWidgetTooltip(self,
                            "Drag the overlay to position the frames, then click again to lock")
                    end
                end)
                btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                btn:SetScript("OnClick", function()
                    if not MoveAllowed() then return end
                    local active = ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                    if ns.FB_SetMoverShown then ns.FB_SetMoverShown(not active) end
                    UpdateMoveBtn()
                end)
                EllesmereUI.RegisterWidgetRefresh(UpdateMoveBtn)
                UpdateMoveBtn()
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
                        if ns.FB_Apply then ns.FB_Apply() end
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
                      if ns.FB_Apply then ns.FB_Apply() end
                      if ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                         and ns.FB_SetMoverShown then
                          ns.FB_SetMoverShown(true)
                      end
                  end },
                { type="slider", text="Extra Height", min=-50, max=100, step=1,
                  tooltip="Makes the boss frames taller or shorter relative to the raid frame size.",
                  getValue = function() return FBSet().extraHeight or 0 end,
                  setValue = function(v)
                      FBSet().extraHeight = v
                      if ns.FB_Apply then ns.FB_Apply() end
                      if ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                         and ns.FB_SetMoverShown then
                          ns.FB_SetMoverShown(true)
                      end
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
                      if ns.XF_Apply then ns.XF_Apply() end
                      -- Feature may have just gone dark; the mover can't stay up.
                      if not XFConfigured() and ns.XF_SetMoverShown then
                          ns.XF_SetMoverShown(false)
                      end
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
                              if ns.XF_Apply then ns.XF_Apply() end
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
                        if not XFConfigured() and ns.XF_SetMoverShown then
                            ns.XF_SetMoverShown(false)
                        end
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
                      if v ~= "free" and ns.XF_SetMoverShown then ns.XF_SetMoverShown(false) end
                      if ns.XF_Apply then ns.XF_Apply() end
                      -- Full rebuild: the Grow/Wrap Direction row only exists while the position is Free Move.
                      EllesmereUI:RefreshPage(true)
                  end },
                { type="label", text="Free Move Position" }); y = y - h
            if not EllesmereUI._prebuilding then
                local rgn = row._rightRegion
                local btn = CreateFrame("Button", nil, row)
                btn:SetSize(140, 26)
                btn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
                btn:SetFrameLevel(row:GetFrameLevel() + 5)
                local bbg = btn:CreateTexture(nil, "BACKGROUND")
                bbg:SetAllPoints()
                bbg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
                EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
                local lbl = btn:CreateFontString(nil, "OVERLAY")
                EllesmereUI.ApplyModuleFont(lbl, nil, 13, "raidFrames")
                lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
                lbl:SetText(EllesmereUI.L("Move Frames"))

                local function MoveAllowed()
                    return XFConfigured() and (XFSet().position == "free")
                        and not InCombatLockdown()
                end
                local function UpdateMoveBtn()
                    local active = ns.XF_IsMoverShown and ns.XF_IsMoverShown()
                    lbl:SetText(active and EllesmereUI.L("Stop Moving") or EllesmereUI.L("Move Frames"))
                    btn:SetAlpha(MoveAllowed() and 1 or 0.35)
                end
                btn:SetScript("OnEnter", function(self)
                    if not MoveAllowed() then
                        EllesmereUI.ShowWidgetTooltip(self,
                            EllesmereUI.DisabledTooltip("Position must be set to Free Move"))
                    else
                        EllesmereUI.ShowWidgetTooltip(self,
                            "Drag the overlay to position the frames, then click again to lock")
                    end
                end)
                btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                btn:SetScript("OnClick", function()
                    if not MoveAllowed() then return end
                    local active = ns.XF_IsMoverShown and ns.XF_IsMoverShown()
                    if ns.XF_SetMoverShown then ns.XF_SetMoverShown(not active) end
                    UpdateMoveBtn()
                end)
                EllesmereUI.RegisterWidgetRefresh(UpdateMoveBtn)
                UpdateMoveBtn()
            end

            -- Free Move ONLY (hidden otherwise; Position's setValue forces a rebuild): growth axes of the free-floating grid, with Wrap After in an inline cog on Wrap Direction.
            -- Attached positions need none of this -- they stack group-sized runs of 5 along the raid's own growth settings, like extra raid groups.
            -- Grow Direction defaults from the legacy freeHorizontal key, so existing layouts read back unchanged.
            if XFSet().position == "free" then
            local function XFGrowDir()
                local set = XFSet()
                return set.growDirection or (set.freeHorizontal and "RIGHT" or "DOWN")
            end
            local function XFReapply()
                if ns.XF_Apply then ns.XF_Apply() end
                if ns.XF_IsMoverShown and ns.XF_IsMoverShown()
                   and ns.XF_SetMoverShown then
                    ns.XF_SetMoverShown(true)
                end
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
                      if ns.XF_Apply then ns.XF_Apply() end
                      if ns.XF_IsMoverShown and ns.XF_IsMoverShown()
                         and ns.XF_SetMoverShown then
                          ns.XF_SetMoverShown(true)
                      end
                  end },
                { type="slider", text="Extra Height", min=-50, max=100, step=1,
                  tooltip="Makes the extra frames taller or shorter relative to the raid frame size.",
                  getValue = function() return XFSet().extraHeight or 0 end,
                  setValue = function(v)
                      XFSet().extraHeight = v
                      if ns.XF_Apply then ns.XF_Apply() end
                      if ns.XF_IsMoverShown and ns.XF_IsMoverShown()
                         and ns.XF_SetMoverShown then
                          ns.XF_SetMoverShown(true)
                      end
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
                              if ns.XF_Apply then ns.XF_Apply() end
                          end },
                    },
                })
            end
            end   -- close Extra Frames hidden-while-unconfigured gate

            if onSection then onSection("extraFrames", _secY, y) end; _secY = y
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

    ---------------------------------------------------------------------------
    --  Page Builder
    ---------------------------------------------------------------------------
    local function BuildMainPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local _, h
        local row

        parent._showRowDivider = true
        local y = yOffset

        y = BuildPreviewModeRow(parent, y)

        -------------------------------------------------------------------
        --  FRAME SIZES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FRAME SIZES", y); y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="20 Man Frame Width", min=40, max=300, step=1,
              getValue=function() return SVal("frameWidth", 72) end,
              setValue=function(v) SSet("frameWidth", v) end },
            { type="slider", text="20 Man Frame Height", min=20, max=150, step=1,
              getValue=function() return SVal("frameHeight", 46) end,
              setValue=function(v) SSet("frameHeight", v) end });  y = y - h

        -- One row per defined custom raid size.
        do
            local CUSTOM_TIERS = { 10, 15, 25, 30, 40 }
            local TIER_LABELS = { [10] = "10 Man", [15] = "15 Man", [25] = "25 Man", [30] = "30 Man", [40] = "40 Man" }
            local overrides = db.profile.raidSizeOverrides
            local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
            local CLOSE_ICON    = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"

            for _, tier in ipairs(CUSTOM_TIERS) do
                if overrides and overrides[tier] then
                    local tierLabel = TIER_LABELS[tier]
                    local sizeRow
                    sizeRow, h = W:DualRow(parent, y,
                        { type="slider", text=tierLabel .. " Frame Width", min=40, max=300, step=1,
                          getValue=function()
                              local ov = db.profile.raidSizeOverrides
                              return ov and ov[tier] and ov[tier].width or SVal("frameWidth", 72)
                          end,
                          setValue=function(v)
                              local ovs = ns._EnsureRaidSizeOverrides()
                              if not ovs[tier] then
                                  ovs[tier] = { width = v, height = db.profile.frameHeight or 60 }
                              else
                                  ovs[tier].width = v
                              end
                              if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                  ns._ShowSizePreview(tier)
                              elseif ns._ResizeButtons then
                                  local num = GetNumGroupMembers()
                                  if num > 0 then
                                      local w, h = ns._GetRaidSizeFrameDimensions(num)
                                      ns._ResizeButtons(w, h)
                                  end
                              end
                              -- Full reload on drag end applies indicator scaling.
                              if not EllesmereUI._sliderDragging then
                                  ReloadAndUpdate()
                              end
                          end },
                        { type="slider", text=tierLabel .. " Frame Height", min=20, max=150, step=1,
                          getValue=function()
                              local ov = db.profile.raidSizeOverrides
                              return ov and ov[tier] and ov[tier].height or SVal("frameHeight", 46)
                          end,
                          setValue=function(v)
                              local ovs = ns._EnsureRaidSizeOverrides()
                              if not ovs[tier] then
                                  ovs[tier] = { width = db.profile.frameWidth or 125, height = v }
                              else
                                  ovs[tier].height = v
                              end
                              if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                  ns._ShowSizePreview(tier)
                              elseif ns._ResizeButtons then
                                  local num = GetNumGroupMembers()
                                  if num > 0 then
                                      local w, h = ns._GetRaidSizeFrameDimensions(num)
                                      ns._ResizeButtons(w, h)
                                  end
                              end
                              -- Full reload on drag end applies indicator scaling.
                              if not EllesmereUI._sliderDragging then
                                  ReloadAndUpdate()
                              end
                          end });  y = y - h

                    -- Eyeball (preview toggle), left of the row.
                    if not EllesmereUI._prebuilding then
                        local eyeBtn = CreateFrame("Button", nil, sizeRow)
                        eyeBtn:SetSize(24, 24)
                        eyeBtn:SetPoint("RIGHT", sizeRow, "LEFT", -5, 0)
                        eyeBtn:SetFrameLevel(sizeRow:GetFrameLevel() + 5)
                        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                        eyeTex:SetAllPoints()

                        local function RefreshSizeEye()
                            local active = ns._sizePreviewTier == tier
                            eyeTex:SetTexture(active and EYE_INVISIBLE or EYE_VISIBLE)
                            eyeBtn:SetAlpha(active and 0.6 or 0.4)
                        end
                        RefreshSizeEye()
                        ns["_refreshSizeEye" .. tier] = RefreshSizeEye

                        eyeBtn:SetScript("OnEnter", function(self)
                            self:SetAlpha(0.7)
                            local active = ns._sizePreviewTier == tier
                            EllesmereUI.ShowWidgetTooltip(self, active and "Hide " .. tierLabel .. " preview" or "Preview " .. tierLabel .. " frame size")
                        end)
                        eyeBtn:SetScript("OnLeave", function(self)
                            RefreshSizeEye()
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        eyeBtn:SetScript("OnClick", function()
                            if ns._sizePreviewTier == tier then
                                -- Restore the regular preview if the mode allows.
                                ns._sizePreviewTier = nil
                                if ns._HideSizePreview then ns._HideSizePreview() end
                                local mode = db.profile.previewMode or "overlay"
                                if mode ~= "none" and ns.ShowPreview then
                                    ns.ShowPreview()
                                end
                            else
                                if ns._sizePreviewTier then
                                    local oldRefresh = ns["_refreshSizeEye" .. ns._sizePreviewTier]
                                    ns._sizePreviewTier = nil
                                    if ns._HideSizePreview then ns._HideSizePreview() end
                                    if oldRefresh then oldRefresh() end
                                end
                                -- _ShowSizePreview hides the other previews.
                                ns._sizePreviewTier = tier
                                if ns._ShowSizePreview then ns._ShowSizePreview(tier) end
                            end
                            RefreshSizeEye()
                            for _, t in ipairs(CUSTOM_TIERS) do
                                if t ~= tier then
                                    local otherRefresh = ns["_refreshSizeEye" .. t]
                                    if otherRefresh then otherRefresh() end
                                end
                            end
                        end)
                    end

                    if not EllesmereUI._prebuilding then
                        local closeBtn = CreateFrame("Button", nil, sizeRow)
                        closeBtn:SetSize(18, 18)
                        closeBtn:SetPoint("LEFT", sizeRow, "RIGHT", 5, 0)
                        closeBtn:SetFrameLevel(sizeRow:GetFrameLevel() + 5)
                        closeBtn:SetAlpha(0.45)
                        local closeTex = closeBtn:CreateTexture(nil, "OVERLAY")
                        closeTex:SetAllPoints()
                        closeTex:SetTexture(CLOSE_ICON)
                        closeBtn:SetScript("OnEnter", function(self)
                            self:SetAlpha(0.7)
                            EllesmereUI.ShowWidgetTooltip(self, "Remove " .. tierLabel .. " size")
                        end)
                        closeBtn:SetScript("OnLeave", function(self)
                            self:SetAlpha(0.45)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        closeBtn:SetScript("OnClick", function()
                            if ns._sizePreviewTier == tier then
                                ns._sizePreviewTier = nil
                                if ns._HideSizePreview then ns._HideSizePreview() end
                            end
                            local ovs = db.profile.raidSizeOverrides
                            if ovs then
                                ovs[tier] = nil
                                -- Conversion markers (_topLeftAnchored/_cornerAnchored) always stay in the table; only tier TABLES count as content.
                                local anyTier = false
                                for _, o in pairs(ovs) do
                                    if type(o) == "table" then anyTier = true; break end
                                end
                                if not anyTier then
                                    db.profile.raidSizeOverrides = nil
                                end
                            end
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage(true)
                        end)
                    end

                    -- X/Y offset cog on the width slider.
                    if not EllesmereUI._prebuilding then
                        local rgn = sizeRow._leftRegion
                        local function EnsureTierOv()
                            local ovs = ns._EnsureRaidSizeOverrides()
                            if not ovs[tier] then
                                ovs[tier] = { width = db.profile.frameWidth or 125, height = db.profile.frameHeight or 60 }
                            end
                            return ovs[tier]
                        end
                        local function TierGrowthChanged()
                            -- ReloadAndUpdate reloads the live frames (including the growth-corner anchor) AND re-shows the active size preview, so the two never diverge.
                            ReloadAndUpdate()
                        end
                        -- Custom switch boundary per tier (consumed by
                        -- ns._RFResolveTierOverride): lower tiers set the highest
                        -- count they cover, upper tiers the count they engage at.
                        local TIER_BOUNDS = {
                            [10] = { key = "sizeCap", label = "Covers Up To", def = 10, min = 5,  max = 14,
                                     tip = "Highest group size that uses this layout." },
                            [15] = { key = "sizeCap", label = "Covers Up To", def = 15, min = 11, max = 19,
                                     tip = "Highest group size that uses this layout." },
                            [25] = { key = "sizeMin", label = "Switch At", def = 21, min = 21, max = 30,
                                     tip = "Group size at which this layout takes over from the 20 Man layout." },
                            [30] = { key = "sizeMin", label = "Switch At", def = 26, min = 22, max = 40,
                                     tip = "Group size at which this layout takes over from the 25 Man layout." },
                            [40] = { key = "sizeMin", label = "Switch At", def = 31, min = 31, max = 40,
                                     tip = "Group size at which this layout takes over from the 30 Man layout." },
                        }
                        local tb = TIER_BOUNDS[tier]
                        EllesmereUI.BuildInlineCog(rgn, {
                            icon = EllesmereUI.DIRECTIONS_ICON,
                            title = EllesmereUI.Lf("%1$s Options", EllesmereUI.L(tierLabel)),
                            rows = {
                                { type="slider", label=tb.label, min=tb.min, max=tb.max, step=1,
                                  tooltip=tb.tip,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier][tb.key] or tb.def
                                  end,
                                  set=function(v)
                                      EnsureTierOv()[tb.key] = v
                                      -- Re-resolves the live tier against the new boundary.
                                      ReloadAndUpdate()
                                  end },
                                { type="dropdown", label="Group Growth",
                                  values=groupGrowthValues, order=groupGrowthOrder,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ReadGroupGrowth(
                                          ov and ov[tier] and ov[tier].groupGrowth
                                          or db.profile.groupGrowth or "RIGHT")
                                  end,
                                  set=function(v)
                                      -- Separated groups allow every combination (see
                                      -- the main LAYOUT dropdowns); merged needs this
                                      -- tier's effective Unit Growth kept perpendicular.
                                      local ov = EnsureTierOv()
                                      ov.groupGrowth = v
                                      if SVal("mergeGroups", false) then
                                          local ovs = db.profile.raidSizeOverrides
                                          KeepGrowthPerpendicular(v,
                                              function() return (ovs and ovs[tier] and ovs[tier].unitGrowth) or db.profile.unitGrowth or "DOWN" end,
                                              function(nv) ov.unitGrowth = nv end)
                                      end
                                      TierGrowthChanged()
                                  end },
                                { type="dropdown", label="Unit Growth",
                                  values=growthValues, order=allGrowthOrder,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].unitGrowth or db.profile.unitGrowth or "DOWN"
                                  end,
                                  set=function(v)
                                      local ov = EnsureTierOv()
                                      ov.unitGrowth = v
                                      if SVal("mergeGroups", false) then
                                          local ovs = db.profile.raidSizeOverrides
                                          KeepGrowthPerpendicular(v,
                                              function() return (ovs and ovs[tier] and ovs[tier].groupGrowth) or db.profile.groupGrowth or "RIGHT" end,
                                              function(nv) ov.groupGrowth = nv end)
                                      end
                                      TierGrowthChanged()
                                  end },
                                { type="slider", label="X Offset", min=-1000, max=1000, step=1,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].offsetX or 0
                                  end,
                                  set=function(v)
                                      EnsureTierOv().offsetX = v
                                      -- Update BOTH: live frames (cheap per-tick corner re-anchor) and the size preview when it is showing this tier.
                                      if ns._ApplyTierOffset then ns._ApplyTierOffset() end
                                      if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                          ns._ShowSizePreview(tier)
                                      end
                                  end },
                                { type="slider", label="Y Offset", min=-1000, max=1000, step=1,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].offsetY or 0
                                  end,
                                  set=function(v)
                                      EnsureTierOv().offsetY = v
                                      -- Update BOTH: live frames (cheap per-tick corner re-anchor) and the size preview when it is showing this tier.
                                      if ns._ApplyTierOffset then ns._ApplyTierOffset() end
                                      if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                          ns._ShowSizePreview(tier)
                                      end
                                  end },
                            },
                        })
                    end
                end
            end

            -- Add Custom Raid Size | Auto Resize Indicators. Offered tiers exclude the already-added ones.
            local availableTiers = {}
            local availableValues = { _select = "Select Raid Size" }
            local availableOrder = { "_select" }
            for _, tier in ipairs(CUSTOM_TIERS) do
                if not overrides or not overrides[tier] then
                    availableTiers[#availableTiers + 1] = tier
                    availableValues[tostring(tier)] = TIER_LABELS[tier]
                    availableOrder[#availableOrder + 1] = tostring(tier)
                end
            end

            -- Auto Resize Icons: checkbox dropdown, pure VIEW (no migration) over autoResizeIndicators ("Indicators & Auras") and autoResizeTrackedBuffs ("Tracked Buffs"). Tracked Buffs defaults on.
            local autoResizeRow
            local autoResizeSlot = { type="dropdown", text="Auto Resize Icons",
                values={ __placeholder = "All" }, order={ "__placeholder" },
                getValue=function() return "__placeholder" end,
                setValue=function() end }
            if #availableTiers > 0 then
                autoResizeRow, h = W:DualRow(parent, y,
                    { type="dropdown", text="Add Custom Raid Size",
                      tooltip="This option allows you to set custom frame sizing and positioning to different raid sizes. Note: This does NOT resize/reposition frames while in combat, if players join/leave mid combat it will resize after combat completes.",
                      values=availableValues, order=availableOrder,
                      getValue=function() return "_select" end,
                      setValue=function(v)
                          local tier = tonumber(v)
                          if not tier then return end
                          local ovs = ns._EnsureRaidSizeOverrides()
                          -- Seed from the current 20 man size.
                          ovs[tier] = {
                              width = db.profile.frameWidth or 125,
                              height = db.profile.frameHeight or 60,
                          }
                          ReloadAndUpdate()
                          EllesmereUI:RefreshPage(true)
                      end },
                    autoResizeSlot);  y = y - h
            else
                -- All tiers added: only Auto Resize Icons remains.
                autoResizeRow, h = W:DualRow(parent, y,
                    { type="label", text="" },
                    autoResizeSlot);  y = y - h
            end
            -- Overlay the checkbox dropdown onto the right region, mirroring the "Hover Borders" conversion pattern.
            if not EllesmereUI._prebuilding then
                local rightRgn = autoResizeRow._rightRegion
                if rightRgn._control then rightRgn._control:Hide() end
                local arKeyMap = { indicators = "autoResizeIndicators", trackedBuffs = "autoResizeTrackedBuffs" }
                local arItems = {
                    { key = "indicators",   label = "Indicators & Auras" },
                    { key = "trackedBuffs", label = "Tracked Buffs" },
                }
                local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                    rightRgn, 170, rightRgn:GetFrameLevel() + 2,
                    arItems,
                    function(k)
                        -- Tracked Buffs defaults on, Indicators & Auras off.
                        if k == "trackedBuffs" then return SVal(arKeyMap[k], true) end
                        return SVal(arKeyMap[k], false)
                    end,
                    function(k, v) SSet(arKeyMap[k], v) end)
                PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
                rightRgn._control = cbDD
            end
        end

        -------------------------------------------------------------------
        --  FRAME DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FRAME DISPLAY", y); y = y - h
        -- Stock styles: the stock frame edge stands in for the EllesmereUI
        -- border (its style/size row hides; the hover border stays).
        if EllesmereUI.BlizzStyle then y = EllesmereUI.BlizzStyle.Note(parent, y, "raidframes") end
        local function StockGate(cfg)
            if EllesmereUI.BlizzStyle then return EllesmereUI.BlizzStyle.Gate("raidframes", cfg) end
            return cfg
        end

        _, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Frame Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("cellSpacing", 2) end,
              setValue=function(v) SSet("cellSpacing", v) end },
            { type="slider", pixel=true, text="Group Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("groupSpacing", 8) end,
              setValue=function(v) SSet("groupSpacing", v) end });  y = y - h

        -- Border Style (+ options cog) | Border Size (+ Border swatch). Mirrors Unit Frames: ONE border recolored by state (hover/target), full SharedMedia support. Hover/Target swatches live on the row below.
        local bdrTexValues, bdrTexOrder = EllesmereUI.GetBorderTextureDropdown()
        local borderStyleRow
        borderStyleRow, h = W:DualRow(parent, y,
            StockGate({ type="dropdown", text="Border Style", values=bdrTexValues, order=bdrTexOrder,
              getValue=function() return SGet("borderTexture") or "solid" end,
              setValue=function(v)
                  SWrite("borderTexture", v)
                  SWrite("borderTextureOffset", nil)
                  SWrite("borderTextureOffsetY", nil)
                  SWrite("borderTextureShiftX", nil)
                  SWrite("borderTextureShiftY", nil)
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  SWrite("borderColor", _bcol)
                  SWrite("borderBehind", _bbehind)
                  local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                  if defSz then SWrite("borderSize", defSz) end
                  -- A style pick returns the size to its step: clear a set exact size.
                  if SGetPx("borderSizePx", "borderSize") then SWrite("borderSizePx", false) end
                  -- Rebuild: the offset row below exists only for a textured style.
                  ReloadAndUpdate(); EllesmereUI:RefreshPage(true)
              end }),
            -- Exact pixel size: borderSize keeps its step, borderSizePx the pixels.
            StockGate(EllesmereUI.BorderPxSliderCfg({
              getStep=function() return SVal("borderSize", 1) end,
              setStep=function(v) SWrite("borderSize", v) end,
              getTex=function() return SGet("borderTexture") or "solid" end,
              getPx=function() return SGetPx("borderSizePx", "borderSize") end,
              setPx=function(v) SWrite("borderSizePx", v) end,
              apply=ReloadAndUpdate })));  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = borderStyleRow._leftRegion
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type="slider", label="Shift X", min=-10, max=10, step=1,
                      get=function()
                          local v = SGet("borderTextureShiftX"); if v then return v end
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("unitframes", SGet("borderTexture") or "solid", SVal("borderSize", 1))
                          return dsx
                      end,
                      set=function(v) SSet("borderTextureShiftX", v) end },
                    { type="slider", label="Shift Y", min=-10, max=10, step=1,
                      get=function()
                          local v = SGet("borderTextureShiftY"); if v then return v end
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("unitframes", SGet("borderTexture") or "solid", SVal("borderSize", 1))
                          return dsy
                      end,
                      set=function(v) SSet("borderTextureShiftY", v) end },
                    { type="toggle", label="Show Behind",
                      get=function() return SVal("borderBehind", false) end,
                      set=function(v) SSet("borderBehind", v) end },
                },
            })
            local function UpdateCogVis()
                local tex = SGet("borderTexture") or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        if not EllesmereUI._prebuilding then
            local rgn = borderStyleRow._rightRegion
            local lvl = borderStyleRow:GetFrameLevel() + 3
            local borderSwatch, updBorder = EllesmereUI.BuildColorSwatch(
                rgn, lvl,
                function()
                    local c = SGet("borderColor") or { r = 0, g = 0, b = 0 }
                    return c.r, c.g, c.b, SVal("borderAlpha", 1)
                end,
                function(r, g, b, a)
                    SWrite("borderColor", { r=r, g=g, b=b }); SWrite("borderAlpha", a); ReloadAndUpdate()
                end, true, 20)
            borderSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = borderSwatch
            borderSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(borderSwatch, "Border") end)
            borderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function() updBorder() end)
        end

        -- Width Offset | Height Offset: the textured edge's outward offsets as their
        -- own row, present only while a textured style is selected (the Border Style
        -- setter rebuilds the page). Each slider shows what is drawn: the override,
        -- else the unitframes registry default for the step (scaled to a set exact
        -- size), and clears the override when a click lands on that default, so the
        -- per-texture defaults keep seeding. Reads and writes go through the party
        -- twin helpers exactly as the cog rows did.
        local bdrTex = SGet("borderTexture")
        if bdrTex and bdrTex ~= "" and bdrTex ~= "solid" then
            -- Party tab: a cleared party override inherits the RAID override, not the
            -- texture default, so a click on the default pins it explicitly whenever
            -- the raid holds one (else the party slider could never reach it). The pin
            -- is the default as drawn: scaled to a set exact size, as nil draws it.
            local function SetOffset(key, v, isY)
                SWrite(key, v)
                if v == nil and SGet(key) ~= nil then
                    local tex, step = SGet("borderTexture") or "solid", SVal("borderSize", 1)
                    local dx, dy = EllesmereUI.GetBorderDefaults("unitframes", tex, step)
                    local px = EllesmereUI.BorderPx(SGetPx("borderSizePx", "borderSize"), step, tex)
                    if px then
                        local PPg, EM = EllesmereUI.PP, EllesmereUI.BORDER_EDGE_MAP
                        local f = (px * PPg.mult) / (EM[step] or EM[1])
                        dx, dy = PPg.Snap(dx * f), PPg.Snap(dy * f)
                    end
                    if isY then SWrite(key, dy) else SWrite(key, dx) end
                end
            end
            local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function() return SGet("borderTexture") or "solid" end,
                getStep = function() return SVal("borderSize", 1) end,
                getSizeKey = function() return SVal("borderSize", 1) end,
                getPx = function() return SGetPx("borderSizePx", "borderSize") end,
                getX = function() return SGet("borderTextureOffset") end,
                setX = function(v) SetOffset("borderTextureOffset", v, false) end,
                getY = function() return SGet("borderTextureOffsetY") end,
                setY = function(v) SetOffset("borderTextureOffsetY", v, true) end,
                apply = ReloadAndUpdate })
            _, h = W:DualRow(parent, y, StockGate(ocfgL), StockGate(ocfgR));  y = y - h
        end

        -- Show When Solo | Hover Borders: which highlight states are active. Disabling one skips that recolor entirely and the frame keeps its normal border. Hover + Target swatches are inline here.
        local hoverBordersRow
        hoverBordersRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show When Solo",
              -- Disabled only while Party's is the ONE that is on: a profile holding both
              -- flags (older profile, override swap, import) shows the player twice, and
              -- each toggle must stay clickable to switch itself off.
              disabled=function() return db.profile.partyShowWhenSolo and not db.profile.showWhenSolo end,
              disabledTooltip="Party Frames Show When Solo", requireState="disabled",
              getValue=function() return SVal("showWhenSolo", false) end,
              setValue=function(v)
                  SSet("showWhenSolo", v)
                  if ns.UpdateVisibility then ns.UpdateVisibility() end
                  if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Hover Borders",
              values={ __placeholder = "All" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h
        if not EllesmereUI._prebuilding then
            local rightRgn = hoverBordersRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local hbItems = {
                { key = "hover",  label = "Hover Border" },
                { key = "target", label = "Target Border" },
            }
            local hbKeyMap = { hover = "hoverBorderEnabled", target = "targetBorderEnabled" }
            local UpdateHBSwatchVis  -- forward declare; assigned after swatches
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 170, rightRgn:GetFrameLevel() + 2,
                hbItems,
                function(k) return SVal(hbKeyMap[k], true) end,
                function(k, v)
                    SSet(hbKeyMap[k], v)
                    if UpdateHBSwatchVis then UpdateHBSwatchVis() end
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil

            -- Hover sits nearest the dropdown, Target to its left.
            local lvl = hoverBordersRow:GetFrameLevel() + 3
            local hoverSwatch, updHover = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = SGet("hoverBorderColor") or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, SVal("hoverBorderAlpha", 1)
                end,
                function(r, g, b, a)
                    SWrite("hoverBorderColor", { r=r, g=g, b=b }); SWrite("hoverBorderAlpha", a); ReloadAndUpdate()
                end, true, 20)
            hoverSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = hoverSwatch
            hoverSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hoverSwatch, "Hover") end)
            hoverSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local targetSwatch, updTarget = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = SGet("targetBorderColor") or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, SVal("targetBorderAlpha", 1)
                end,
                function(r, g, b, a)
                    SWrite("targetBorderColor", { r=r, g=g, b=b }); SWrite("targetBorderAlpha", a); ReloadAndUpdate()
                end, true, 20)
            targetSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = targetSwatch
            targetSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(targetSwatch, "Target") end)
            targetSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Stock styles: the stock selection ring carries its own colour.
            local targetBlocked = EllesmereUI.BlizzStyle
                and EllesmereUI.BlizzStyle.BlockInline("raidframes", targetSwatch) or false

            -- Highlight thickness. Shown only while the frame is borderless (Border Size 0):
            -- with a border drawn the highlight recolors THAT and these sizes do nothing.
            -- Exact pixel sizes (hover/targetBorderSizePx beside the steps) in the frame's
            -- border style; under a stock style the hover border draws solid, so the
            -- slider reads and writes against Solid there. The floor stays at 1.
            local function HlTex()
                if ns.RF_Stock and ns.RF_Stock() then return "solid" end
                return SGet("borderTexture") or "solid"
            end
            local hoverPx = EllesmereUI.BorderPxSliderCfg({
                getStep=function() return SVal("hoverBorderSize", 1) end,
                setStep=function(v) SWrite("hoverBorderSize", v) end,
                getTex=HlTex,
                getPx=function() return SGetPx("hoverBorderSizePx", "hoverBorderSize") end,
                setPx=function(v) SWrite("hoverBorderSizePx", v) end,
                apply=ReloadAndUpdate })
            local targetPx = EllesmereUI.BorderPxSliderCfg({
                getStep=function() return SVal("targetBorderSize", 1) end,
                setStep=function(v) SWrite("targetBorderSize", v) end,
                getTex=HlTex,
                getPx=function() return SGetPx("targetBorderSizePx", "targetBorderSize") end,
                setPx=function(v) SWrite("targetBorderSizePx", v) end,
                apply=ReloadAndUpdate })
            local hlCog = EllesmereUI.BuildInlineCog(rightRgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Highlight Border",
                rows = {
                    { type="slider", label="Hover Border Size", min=1, max=hoverPx.max, step=1,
                      tooltip=hoverPx.tooltip,
                      get=hoverPx.getValue, set=hoverPx.setValue },
                    { type="slider", label="Target Border Size", min=1, max=targetPx.max, step=1,
                      tooltip=targetPx.tooltip,
                      -- Stock styles draw the stock selection ring instead.
                      disabled=function() return ns.RF_Stock and ns.RF_Stock() end,
                      disabledTooltip=EllesmereUI.BlizzStyle and EllesmereUI.BlizzStyle.Label("raidframes") or nil,
                      get=targetPx.getValue, set=targetPx.setValue },
                },
            })
            local function UpdateHLCogVis()
                -- Under a stock style the EllesmereUI border is stood down, so
                -- the hover border draws on its own at this size.
                local bs = (ns.RF_Stock and ns.RF_Stock()) and 0 or SVal("borderSize", 1)
                if bs > 0 then hlCog:Hide() else hlCog:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHLCogVis)
            UpdateHLCogVis()

            -- Gray a swatch when its border state is off but keep it clickable so the color can be pre-set (matches the Heal Prediction swatch).
            UpdateHBSwatchVis = function()
                hoverSwatch:SetAlpha(SVal("hoverBorderEnabled", true) and 1 or 0.3)
                targetSwatch:SetAlpha((not targetBlocked and SVal("targetBorderEnabled", true)) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updHover(); updTarget(); UpdateHBSwatchVis() end)
            UpdateHBSwatchVis()
        end

        -------------------------------------------------------------------
        --  LAYOUT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h

        -- Group Growth | Unit Growth: separated groups (Merge Groups off) support every
        -- combination of the two axes (5 Group Growth values x 4 Unit Growth ones), but
        -- merged mode's single Blizzard flat header can only make its column direction
        -- perpendicular to Unit Growth, so a same-axis pair -- and the two-axis grid
        -- flow, which it renders as a plain RIGHT run (ReadGroupGrowth above) -- gets
        -- silently reinterpreted (see the colAnchor comment in EllesmereUIRaidFrames.lua)
        -- -- KeepGrowthPerpendicular bumps the other axis instead. A base edit can also
        -- leave a per-tier override same-axis (an override that only set one axis
        -- inherits the other from base), so fix those up too.
        local function FixTierOverridesPerpendicular()
            local overrides = db.profile.raidSizeOverrides
            if type(overrides) ~= "table" then return end
            for _, ov in pairs(overrides) do
                if type(ov) == "table" then
                    KeepGrowthPerpendicular(ov.groupGrowth or SVal("groupGrowth", "RIGHT"),
                        function() return ov.unitGrowth or SVal("unitGrowth", "DOWN") end,
                        function(nv) ov.unitGrowth = nv end)
                end
            end
        end

        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Group Growth", values=groupGrowthValues, order=groupGrowthOrder,
              getValue=function() return ReadGroupGrowth(SVal("groupGrowth", "RIGHT")) end,
              setValue=function(v)
                  db.profile.groupGrowth = v
                  if SVal("mergeGroups", false) then
                      KeepGrowthPerpendicular(v,
                          function() return SVal("unitGrowth", "DOWN") end,
                          function(nv) db.profile.unitGrowth = nv end)
                      FixTierOverridesPerpendicular()
                      EllesmereUI:RefreshPage() -- the sibling dropdown may have just changed
                  end
                  if ns._BumpAbsorbGen then ns._BumpAbsorbGen() end
                  ReloadAndUpdate()
              end },
            { type="dropdown", text="Unit Growth", values=growthValues, order=allGrowthOrder,
              getValue=function() return SVal("unitGrowth", "DOWN") end,
              setValue=function(v)
                  db.profile.unitGrowth = v
                  if SVal("mergeGroups", false) then
                      KeepGrowthPerpendicular(v,
                          function() return SVal("groupGrowth", "RIGHT") end,
                          function(nv) db.profile.groupGrowth = nv end)
                      FixTierOverridesPerpendicular()
                      EllesmereUI:RefreshPage() -- the sibling dropdown may have just changed
                  end
                  if ns._BumpAbsorbGen then ns._BumpAbsorbGen() end
                  ReloadAndUpdate()
              end });  y = y - h

        -- Row 4: Sort By (custom dropdown with drag-to-reorder roles) | Self Position
        local sortRow
        do
            sortRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Sort By",
                  values={ __placeholder = "Group" }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end },
                { type="dropdown", text="Self Position",
                  values={ none = "Default", first = "First", last = "Last" },
                  order={ "none", "first", "last" },
                  getValue=function()
                      if SVal("showSelfLast", false) then return "last" end
                      if SVal("showSelfFirst", false) then return "first" end
                      return "none"
                  end,
                  setValue=function(v)
                      SSet("showSelfFirst", v == "first")
                      SSet("showSelfLast", v == "last")
                      EllesmereUI:RefreshPage()
                  end });  y = y - h

            -- Swap the placeholder dropdown for the shared Sort By control, wired to the raid keys.
            if not EllesmereUI._prebuilding then
            BuildSortByControl(sortRow._leftRegion, {
                readMode   = function() return SVal("sortMode", "INDEX") end,
                writeMode  = function(v) SSet("sortMode", v) end,
                readRoles  = function() return SVal("roleOrder", { "TANK", "HEALER", "DAMAGER" }) end,
                writeRoles = function(ro) db.profile.roleOrder = ro; ReloadAndUpdate() end,
            })
            end

            -- Cog next to Sort By: Prioritize Class toggle plus a drag-to-reorder
            -- Class Order list the toggle disables (the party cog, on the raid keys).
            local rgn = sortRow._leftRegion
            -- Class list in saved order, always covering every class: any missing/new
            -- class is appended from the default alphabetical order.
            local function GetClassItems()
                local def = ns._GetDefaultClassOrder()  -- also populates ns._classNameByToken
                local names = ns._classNameByToken or {}
                local saved = db.profile.classOrder
                local order, seen = {}, {}
                if saved then
                    for _, t in ipairs(saved) do
                        if names[t] and not seen[t] then order[#order + 1] = t; seen[t] = true end
                    end
                end
                for _, t in ipairs(def) do if not seen[t] then order[#order + 1] = t; seen[t] = true end end
                local out = {}
                for _, t in ipairs(order) do out[#out + 1] = { key = t, label = names[t] or t } end
                return out
            end
            -- FrameSort's list owns the order while it is the loaded Sort By choice.
            local function FsOwns()
                return db.profile.sortMode == "FRAMESORT" and ns._FrameSortApi and ns._FrameSortApi() ~= nil or false
            end
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Class Sorting",
                rows = {
                    { type = "toggle", label = "Prioritize Class",
                      tooltip = "This will not override sorting by role",
                      get = function() return db.profile.prioritizeClass end,
                      set = function(v) db.profile.prioritizeClass = v; ReloadAndUpdate() end,
                      disabled = FsOwns,
                      disabledTooltip = "FrameSort sets the order while Sort By is FrameSort.", rawTooltip = true },
                    { type = "reorder", label = "Class Order", hint = "Drag to Reorder Classes",
                      items = GetClassItems,
                      set = function(keys) db.profile.classOrder = keys; ReloadAndUpdate() end,
                      disabled = function() return not db.profile.prioritizeClass or FsOwns() end },
                },
            })
        end

        -- Row 3: Show Groups (checkbox dropdown) | Merge Groups
        local showGroupsRow
        do
            showGroupsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Show Groups",
                  values={ __placeholder = "..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end },
                { type="toggle", text="Merge Groups",
                  getValue=function() return SVal("mergeGroups", false) end,
                  -- Custom Group Order only applies to separated groups, so a flip that
                  -- changes whether it applies rebuilds the Show Groups dropdown.
                  setValue=EllesmereUI.DependentSetValue(function()
                      return db.profile.customGroupOrder and not db.profile.mergeGroups
                  end, function(v)
                      -- Fix up an already-saved same-axis Group/Unit Growth pair so the
                      -- SAVED profile and the dropdowns stay honest about what's rendering
                      -- (the runtime's own read-time backstop, ns._RFEffectiveGrowth, already
                      -- makes the first merged render correct either way). Covers both the
                      -- base pair and every per-tier override, same as the per-tier cog
                      -- dropdowns do while merge is already on.
                      if v then
                          KeepGrowthPerpendicular(SVal("groupGrowth", "RIGHT"),
                              function() return SVal("unitGrowth", "DOWN") end,
                              function(nv) db.profile.unitGrowth = nv end)
                          FixTierOverridesPerpendicular()
                      end
                      SSet("mergeGroups", v)
                      EllesmereUI:RefreshPage()
                  end) });  y = y - h

            -- Left dropdown becomes a checkbox dropdown for groups 1-8.
            if not EllesmereUI._prebuilding then
            local rgn = showGroupsRow._leftRegion
            if rgn._control then rgn._control:Hide() end

            -- The order is ignored while groups are merged, so only offer dragging when it applies.
            local useCustomOrder = db.profile.customGroupOrder and not db.profile.mergeGroups
            local groupItems = {}
            if useCustomOrder then
                local savedGroupOrder = ns._RFValidatedGroupOrder(db.profile.groupOrder)
                for i = 1, 8 do
                    local group = savedGroupOrder and savedGroupOrder[i] or i
                    groupItems[i] = { key = group, label = "Group " .. group }
                end
            else
                for i = 1, 8 do
                    groupItems[i] = { key = i, label = "Group " .. i }
                end
            end

            local function GroupVisible(k)
                local vg = db.profile.visibleGroups
                return vg and vg[k] ~= false
            end
            local function SetGroupVisible(k, v)
                if not db.profile.visibleGroups then
                    db.profile.visibleGroups = { true, true, true, true, true, true, false, false }
                end
                db.profile.visibleGroups[k] = v
                ReloadAndUpdate()
            end

            local cbDD, cbDDRefresh
            if useCustomOrder then
                cbDD, cbDDRefresh = EllesmereUI.BuildReorderCBDropdown(
                    rgn, 170, rgn:GetFrameLevel() + 2,
                    groupItems, GroupVisible, SetGroupVisible, {
                        hint = EllesmereUI.L("Drag to Reorder Groups"),
                        canReorder = function() return not InCombatLockdown() and not db.profile.mergeGroups end,
                        setOrder = function(order)
                            if InCombatLockdown() or db.profile.mergeGroups then return end
                            db.profile.groupOrder = order
                            ReloadAndUpdate()
                        end,
                        summaryLabel = function(movable, _, getFn)
                            local visible = {}
                            for _, item in ipairs(movable) do
                                if getFn(item.key) then
                                    visible[#visible + 1] = EllesmereUI.L("Group") .. " " .. item.key
                                end
                            end
                            return #visible > 0 and table.concat(visible, ", ") or EllesmereUI.L("None")
                        end,
                    })
            else
                cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 170, rgn:GetFrameLevel() + 2,
                    groupItems, GroupVisible, SetGroupVisible)
            end
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            local cogShow
            local cogRows = {
                    { type="toggle", label="Hide Empty Groups",
                      tooltip="Collapse subgroups that have no members so the remaining groups close ranks. For example, if only groups 1, 2, 3 and 6 have players, they show with no gaps instead of leaving empty space where groups 4 and 5 would be. Real raid frames only.",
                      get=function() return SVal("hideEmptyGroups", true) end,
                      set=function(v) SSet("hideEmptyGroups", v) end },
                    { type="toggle", label="Exclude Hidden from Size",
                      tooltip="When using custom raid sizes, don't count members in hidden groups toward the raid-size breakpoint. For example, if you hide groups 7 and 8, a full 40-man raid is sized as if it were 24-man instead of jumping to the 30-man frame size. Has no effect unless you have custom raid sizes set up.",
                      get=function() return SVal("excludeHiddenGroupsFromSize", true) end,
                      set=function(v) SSet("excludeHiddenGroupsFromSize", v) end },
                    { type="toggle", label=EllesmereUI.L("Custom Group Order"),
                      tooltip=EllesmereUI.L("Display separated raid groups in your chosen order."),
                      get=function() return db.profile.customGroupOrder == true end,
                      set=function(v)
                          if InCombatLockdown() then return end
                          db.profile.customGroupOrder = v
                          ReloadAndUpdate()
                          if cogShow and cogShow._popupFrame then cogShow._popupFrame:Hide() end
                          EllesmereUI:RefreshPage(true)
                      end,
                      disabled=function() return InCombatLockdown() end,
                      disabledTooltip=EllesmereUI.L("Unavailable in combat"), rawTooltip=true },
            }
            cogShow = select(2, EllesmereUI.BuildInlineCog(rgn, { title = "Show Groups", rows = cogRows }))
        end
            end


        y = BuildVisualSections(parent, y, W)

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Party page
    ---------------------------------------------------------------------------
    -- Party reuses BuildPreviewModeRow (same previewMode key + pvModeDropdowns).

    local function PartyReloadAndUpdate()
        -- ReloadPartyFrames handles container sizing internally.
        if ns.ReloadPartyFrames then
            ns.ReloadPartyFrames()
        end
        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
            ns.ShowPartyPreview()
        end
    end

    local function PSSet(key, val)
        db.profile[key] = val
        -- Set showSolo directly: _UpdatePartyVisibility bails while preview is up.
        if key == "partyShowWhenSolo" and ns._partyHeader and not InCombatLockdown() then
            ns._partyHeader:SetAttribute("showSolo", val or false)
        end
        -- Dimension keys (the Party Frames kit's Frame Scale included) take the
        -- lightweight resize path.
        if (key == "partyFrameWidth" or key == "partyFrameHeight" or key == "partyKitScale")
            and ns._ResizePartyButtons then
            local w, h = ns.RF_PartyDims(db.profile)
            ns._ResizePartyButtons(w, h)
            -- Preview refresh needs no full reload.
            if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
                ns.ShowPartyPreview()
            end
            -- Container SetSize re-processes the secure header (= blink), so the container resize is deferred off the hot path and run the moment the drag releases via the slider system's end-of-drag callback set, snapping frames to final position instead of on options close.
            if EllesmereUI._sliderDragging then
                EllesmereUI._deferredDriftChecks = EllesmereUI._deferredDriftChecks or {}
                EllesmereUI._deferredDriftChecks[PartyReloadAndUpdate] = true
            else
                -- Direct set (input box / post-release commit): finalize now and drop any pending registration so it runs once.
                if EllesmereUI._deferredDriftChecks then
                    EllesmereUI._deferredDriftChecks[PartyReloadAndUpdate] = nil
                end
                PartyReloadAndUpdate()
            end
            return
        end
        PartyReloadAndUpdate()
    end

    local function BuildPartyPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local _, h
        local row

        parent._showRowDivider = true
        local y = yOffset

        y = BuildPreviewModeRow(parent, y)

        -------------------------------------------------------------------
        --  FRAME STYLE (stock styles only): the party in the Raid Frames
        --  layout, or as the stock portrait party frame. Latched like the
        --  style itself, so a pick is written on the reload confirm only.
        -------------------------------------------------------------------
        local p0 = db.profile
        if ns.RF_Stock and ns.RF_Stock() and (p0.useBlizzardStyle or p0.useClassicStyle) then
            _, h = W:SectionHeader(parent, "FRAME STYLE", y); y = y - h
            local kitOn = ns.RF_PartyKit and ns.RF_PartyKit()
            -- Frame Scale default (nil = this, 120%).
            local scaleDef = math.floor((ns.RF_KIT_SCALE or 1.2) * 100 + 0.5)
            local styleRow
            styleRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Frame Style",
                  tooltip="Party Frames switches the party to the stock portrait party frames.",
                  values={ raid = "Raid Frames", party = "Party Frames" }, order={ "raid", "party" },
                  noCapture=true,
                  getValue=function() return (db.profile.partyFrameStyle == "party") and "party" or "raid" end,
                  setValue=function(v)
                      local cur = (db.profile.partyFrameStyle == "party") and "party" or "raid"
                      if v == cur then return end
                      EllesmereUI:ShowConfirmPopup({
                          title = "Reload Required",
                          message = "Changing the party frame style requires a UI reload.",
                          confirmText = "Reload Now",
                          cancelText = "Cancel",
                          reload = true,
                          onConfirm = function()
                              EllesmereUI.SpecOverrides_CloseEditSessions()
                              db.profile.partyFrameStyle = (v == "party") and "party" or nil
                          end,
                      })
                  end },
                kitOn and { type="slider", text="Frame Scale", min=50, max=200, step=5,
                  getValue=function()
                      local k = db.profile.partyKitScale
                      return k and math.floor(k * 100 + 0.5) or scaleDef
                  end,
                  setValue=function(v) PSSet("partyKitScale", (v ~= scaleDef) and (v / 100) or nil) end }
                or { type="label", text="" });  y = y - h
            if kitOn then
                -- Frame Scale cog: the gap between the party frames.
                EllesmereUI.BuildInlineCog(styleRow._rightRegion, { title = "Frame Scale", rows = {
                    { type="slider", label="Spacing", min=0, max=30, step=1,
                      get=function() return db.profile.partyKitSpacing or ns.RF_KIT_SPACING or 6 end,
                      set=function(v) PSSet("partyKitSpacing", v) end },
                } })
                -- Party Frames: the aura row under the frame and the buff run
                -- beside it (sizes, X/Y, and where the buffs sit).
                local kitAuraRow
                kitAuraRow, h = W:DualRow(parent, y,
                    { type="slider", text="Debuff Size", min=8, max=40, step=1,
                      getValue=function() return db.profile.partyKitDebuffSize or 15 end,
                      setValue=function(v) PSSet("partyKitDebuffSize", v) end },
                    { type="slider", text="Buff Size", min=8, max=40, step=1,
                      getValue=function() return db.profile.partyKitBuffSize or 15 end,
                      setValue=function(v) PSSet("partyKitBuffSize", v) end });  y = y - h
                EllesmereUI.BuildInlineCog(kitAuraRow._leftRegion, { title = "Debuff Position", rows = {
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return db.profile.partyKitDebuffX or 0 end,
                      set=function(v) PSSet("partyKitDebuffX", v) end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return db.profile.partyKitDebuffY or 0 end,
                      set=function(v) PSSet("partyKitDebuffY", v) end },
                } })
                -- Horizontal Frames always puts the buffs above each frame
                -- (the next frame sits beside it): the side picks disable.
                EllesmereUI.BuildInlineCog(kitAuraRow._rightRegion, { title = "Buff Position", rows = {
                    { type="dropdown", label="Anchor",
                      values={ right = "Right of Frame", left = "Left of Frame", above = "Above Frame" },
                      order={ "right", "left", "above" },
                      itemDisabled=function(v) return db.profile.partyHorizontal and v ~= "above" end,
                      get=function()
                          if db.profile.partyHorizontal then return "above" end
                          local a = db.profile.partyKitBuffAnchor
                          if a == "left" or a == "above" then return a end
                          return "right"
                      end,
                      set=function(v)
                          -- Horizontal frames show Above without storing it,
                          -- so the stacked choice survives.
                          if db.profile.partyHorizontal then return end
                          if v == "left" or v == "above" then PSSet("partyKitBuffAnchor", v)
                          else PSSet("partyKitBuffAnchor", nil) end
                      end },
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return db.profile.partyKitBuffX or 0 end,
                      set=function(v) PSSet("partyKitBuffX", v) end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return db.profile.partyKitBuffY or 0 end,
                      set=function(v) PSSet("partyKitBuffY", v) end },
                } })
            end
        end

        -------------------------------------------------------------------
        --  RAID SYNC AND SOLO
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "RAID SYNC AND SOLO", y); y = y - h

        -- Row 1: Use Raid Settings For (checkbox dropdown) | Show When Solo
        local SECTION_ORDER = ns._PARTY_SECTION_ORDER or {}
        local SECTION_LABELS = ns._PARTY_SECTION_LABELS or {}

        local syncItems = {}
        -- (The Party Frames kit has no Top Name Bar section to sync.)
        local kitPage = ns.RF_OptPartyKit()
        for _, secKey in ipairs(SECTION_ORDER) do
            if not (kitPage and secKey == "topNameBar") then
                syncItems[#syncItems + 1] = { key = secKey, label = SECTION_LABELS[secKey] or secKey }
            end
        end

        local syncRow
        syncRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Use Raid Settings For",
              values={ _placeholder = "..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Show When Solo",
              -- Same rule as the Raid toggle: both flags on must leave both clickable.
              disabled=function() return db.profile.showWhenSolo and not db.profile.partyShowWhenSolo end,
              disabledTooltip="Raid Frames Show When Solo", requireState="disabled",
              getValue=function() return SVal("partyShowWhenSolo", false) end,
              setValue=function(v)
                  PSSet("partyShowWhenSolo", v)
                  EllesmereUI:RefreshPage()
              end });  y = y - h

        if not EllesmereUI._prebuilding then
            local rgn = syncRow._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                -- Off while only the Raid toggle is on: party never shows solo then (both on = party does show).
                disabled = function() return db.profile.showWhenSolo and not db.profile.partyShowWhenSolo end,
                disabledTooltip = "Raid Frames Show When Solo", requireState = "disabled",
                title = "Show When Solo",
                rows = {
                    { type = "toggle", label = "Center When Solo",
                      tooltip = "When you are solo, center the player frame on the party frame instead of anchoring it at the top.",
                      get = function() return db.profile.partyCenterWhenSolo or false end,
                      set = function(v)
                          db.profile.partyCenterWhenSolo = v
                          if ns._LayoutPartyFrames then ns._LayoutPartyFrames() end
                      end },
                },
            })
        end

        -- Left dropdown becomes a per-section sync checkbox dropdown.
        if not EllesmereUI._prebuilding then
            local rgn = syncRow._leftRegion
            if rgn._control then rgn._control:Hide() end

            local syncDD  -- forward declared for the setter closure
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                syncItems,
                function(k)
                    -- Checked = synced (using raid settings).
                    local ss = db.profile.partySyncSections
                    if not ss then return true end  -- default: all synced
                    return ss[k] ~= false
                end,
                function(k, v)
                    local function ApplySync()
                        if not db.profile.partySyncSections then
                            db.profile.partySyncSections = {}
                        end
                        db.profile.partySyncSections[k] = v and true or false
                        if ns._RefreshProxyModes then ns._RefreshProxyModes() end
                        -- Toggle the overlay directly; no page rebuild needed.
                        local ov = ns._syncOverlays and ns._syncOverlays[k]
                        if ov then
                            if v then ov:Show() else ov:Hide() end
                        end
                        -- The proxy now reads different values.
                        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
                        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
                            ns.ShowPartyPreview()
                        end
                        if ns._syncDDRefresh then ns._syncDDRefresh() end
                    end

                    -- Re-syncing discards custom party values; warn if any exist.
                    if v then
                        local hasCustom = false
                        for key, section in pairs(ns._PARTY_KEY_SECTION) do
                            if section == k and rawget(db.profile, "party_" .. key) ~= nil then
                                hasCustom = true
                                break
                            end
                        end
                        if hasCustom then
                            -- Close the menu before the popup.
                            if syncDD and syncDD._ddMenu then syncDD._ddMenu:Hide() end
                            EllesmereUI:ShowConfirmPopup({
                                title = EllesmereUI.Lf("Re-sync %1$s?", SECTION_LABELS[k] or k),
                                message = "This will discard your custom party settings for this section and use raid settings instead.",
                                confirmText = "Sync",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    for key, section in pairs(ns._PARTY_KEY_SECTION) do
                                        if section == k then
                                            db.profile["party_" .. key] = nil
                                        end
                                    end
                                    ApplySync()
                                end,
                            })
                            return
                        end
                    end

                    ApplySync()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            syncDD = cbDD
            ns._syncDDRefresh = cbDDRefresh
        end

        -------------------------------------------------------------------
        --  FRAMES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FRAMES", y); y = y - h

        -- (Party Frames kit: its Frame Scale, under FRAME STYLE, sizes it.)
        _, h = W:DualRow(parent, y,
            ns.RF_PartyKitGate({ type="slider", text="Frame Width", min=40, max=300, step=1,
              getValue=function() return SVal("partyFrameWidth", 125) end,
              setValue=function(v) PSSet("partyFrameWidth", v) end }),
            ns.RF_PartyKitGate({ type="slider", text="Frame Height", min=20, max=150, step=1,
              getValue=function() return SVal("partyFrameHeight", 60) end,
              setValue=function(v) PSSet("partyFrameHeight", v) end }));  y = y - h

        -- Horizontal Frames | Sort By: same control as the raid LAYOUT tab, wired to the party keys.
        -- (Party Frames kit: horizontal frames carry their buffs above each frame;
        -- RefreshPage re-reads the Buff Anchor that follows it.)
        local pSortRow
        pSortRow, h = W:DualRow(parent, y,
            { type="toggle", text="Horizontal Frames",
              getValue=function() return db.profile.partyHorizontal end,
              setValue=function(v) db.profile.partyHorizontal = v; PartyReloadAndUpdate(); EllesmereUI:RefreshPage() end },
            { type="dropdown", text="Sort By",
              values={ __placeholder = "Group" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h

        if not EllesmereUI._prebuilding then
        BuildSortByControl(pSortRow._rightRegion, {
            readMode   = function() return SVal("partySortMode", "ROLE") end,
            writeMode  = function(v) PSSet("partySortMode", v) end,
            readRoles  = function() return db.profile.partyRoleOrder or db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" } end,
            writeRoles = function(ro) db.profile.partyRoleOrder = ro; PartyReloadAndUpdate() end,
        })
        end

        -- Cog next to Sort By (party only): Prioritize Class toggle plus a drag-to-reorder Class Order list the toggle disables.
        do
            local rgn = pSortRow._rightRegion
            -- Class list in saved order, always covering all 13 classes: any missing/new class is appended from the default alphabetical order.
            local function GetClassItems()
                local def = ns._GetDefaultClassOrder()  -- also populates ns._classNameByToken
                local names = ns._classNameByToken or {}
                local saved = db.profile.partyClassOrder
                local order, seen = {}, {}
                if saved then
                    for _, t in ipairs(saved) do
                        if names[t] and not seen[t] then order[#order + 1] = t; seen[t] = true end
                    end
                end
                for _, t in ipairs(def) do if not seen[t] then order[#order + 1] = t; seen[t] = true end end
                local out = {}
                for _, t in ipairs(order) do out[#out + 1] = { key = t, label = names[t] or t } end
                return out
            end
            -- FrameSort's list owns the order while it is the loaded Sort By choice.
            local function FsOwns()
                return (db.profile.partySortMode or db.profile.sortMode) == "FRAMESORT"
                    and ns._FrameSortApi and ns._FrameSortApi() ~= nil or false
            end
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Class Sorting",
                rows = {
                    { type = "toggle", label = "Prioritize Class",
                      tooltip = "This will not override sorting by role",
                      get = function() return db.profile.partyPrioritizeClass end,
                      set = function(v) db.profile.partyPrioritizeClass = v; PartyReloadAndUpdate() end,
                      disabled = FsOwns,
                      disabledTooltip = "FrameSort sets the order while Sort By is FrameSort.", rawTooltip = true },
                    { type = "reorder", label = "Class Order", hint = "Drag to Reorder Classes",
                      items = GetClassItems,
                      set = function(keys) db.profile.partyClassOrder = keys; PartyReloadAndUpdate() end,
                      disabled = function() return not db.profile.partyPrioritizeClass or FsOwns() end },
                },
            })
        end

        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Self Position",
              values={ none = "Default", first = "First", last = "Last" },
              order={ "none", "first", "last" },
              getValue=function()
                  if SVal("partySelfLast", false) then return "last" end
                  if SVal("partyShowSelfFirst", true) then return "first" end
                  return "none"
              end,
              setValue=function(v)
                  PSSet("partyShowSelfFirst", v == "first")
                  PSSet("partySelfLast", v == "last")
              end },
            { type="toggle", text="Hide Self",
              getValue=function() return db.profile.partyHideSelf or false end,
              setValue=function(v) db.profile.partyHideSelf = v; PartyReloadAndUpdate() end });  y = y - h

        -- Auto Resize Icons | Frame Spacing. The checkbox dropdown is a pure VIEW (no migration) over partyAutoResizeIndicators ("Indicators & Auras") and partyAutoResizeTrackedBuffs ("Tracked Buffs", defaults on).
        local partyAutoResizeRow
        partyAutoResizeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Auto Resize Icons",
              values={ __placeholder = "All" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            -- (The Party Frames kit keeps its own spacing, set in its Frame
            -- Scale cog, so the Raid Frames layout's value survives a switch
            -- between the two.)
            ns.RF_PartyKitGate({ type="slider", pixel=true, text="Frame Spacing", min=-1, max=15, step=1,
              getValue=function()
                  if ns.RF_PartyKit() then return db.profile.partyKitSpacing or ns.RF_KIT_SPACING or 6 end
                  return SVal("partyCellSpacing", db.profile.cellSpacing or 2)
              end,
              setValue=function(v) PSSet(ns.RF_PartyKit() and "partyKitSpacing" or "partyCellSpacing", v) end }));  y = y - h
        -- Auto Resize Icons sits in the LEFT slot here; same conversion pattern as the Frames tab.
        if not EllesmereUI._prebuilding then
            local leftRgn = partyAutoResizeRow._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end
            local arKeyMap = { indicators = "partyAutoResizeIndicators", trackedBuffs = "partyAutoResizeTrackedBuffs" }
            local arItems = {
                { key = "indicators",   label = "Indicators & Auras" },
                { key = "trackedBuffs", label = "Tracked Buffs" },
            }
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 170, leftRgn:GetFrameLevel() + 2,
                arItems,
                function(k)
                    -- Tracked Buffs defaults on, Indicators & Auras off.
                    if k == "trackedBuffs" then return SVal(arKeyMap[k], true) end
                    return SVal(arKeyMap[k], false)
                end,
                function(k, v) PSSet(arKeyMap[k], v) end)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
        end

        -- Frame Growth is a VIEW over the tri-state partyFlipGrowth key (false=Default, true=Reversed, "centered"=Centered), the same key the Flip Frame Growth toggle wrote, so profiles, exports and spec-override entries carry over with no migration.
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Frame Growth",
              tooltip="Default grows down or right, Reversed grows up or left, and Centered keeps the frames centered as the party size changes.",
              values={ default="Default", reversed="Reversed", centered="Centered" },
              order={ "default", "reversed", "centered" },
              getValue=function()
                  local v = db.profile.partyFlipGrowth
                  if v == "centered" then return "centered" end
                  return v == true and "reversed" or "default"
              end,
              setValue=function(v)
                  if v == "centered" then db.profile.partyFlipGrowth = "centered"
                  elseif v == "reversed" then db.profile.partyFlipGrowth = true
                  else db.profile.partyFlipGrowth = false end
                  PartyReloadAndUpdate()
              end },
            { type="toggle", text="Party Frames in Small Raids",
              tooltip="In raid groups under 10 players, show group 1 as party frames and hide everyone else.",
              getValue=function() return db.profile.partySmallRaid or false end,
              setValue=function(v)
                  db.profile.partySmallRaid = v
                  -- Both visibility passes re-read the mode; the raid one runs
                  -- first so its hidden branch never races the party show.
                  if not InCombatLockdown() then
                      if ns.UpdateVisibility then ns.UpdateVisibility() end
                      if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
                  end
              end });  y = y - h

        -------------------------------------------------------------------
        --  PORTRAIT (party only, every style; file-scope builder)
        -------------------------------------------------------------------
        y = ns.RF_BuildPartyPortrait(parent, y, W, PSSet)

        -------------------------------------------------------------------
        --  ALL VISUAL SECTIONS
        --  _partyCtx makes SGet/SSet/SVal read/write "party_<key>", so the same section builders produce party controls; synced sections get a per-section blocking overlay.
        -------------------------------------------------------------------
        local CPAD = EllesmereUI.CONTENT_PAD or 10
        local FONT = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

        local syncOverlays = {}
        ns._syncOverlays = syncOverlays

        local function SyncOverlay(sectionKey, startY, endY)
            local hdrH = 40  -- SectionHeader height
            local contentStart = startY - hdrH
            local ov = CreateFrame("Frame", nil, parent)
            ov._searchIgnore = true  -- inline search must not re-anchor/collapse it
            ov:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD, contentStart)
            ov:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CPAD, contentStart)
            ov:SetHeight(math.abs(endY - contentStart))
            ov:SetFrameLevel(parent:GetFrameLevel() + 50)
            ov:EnableMouse(true)
            local bg = ov:CreateTexture(nil, "OVERLAY")
            bg:SetAllPoints()
            bg:SetColorTexture(13/255, 17/255, 25/255, 0.98)
            local label = ov:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT, 13, "")
            label:SetPoint("CENTER", ov, "CENTER", 0, 0)
            label:SetTextColor(1, 1, 1, 0.56)
            label:SetText(EllesmereUI.L("Synced with Raid Settings"))
            -- Accent on hover so the overlay reads as clickable.
            ov:SetScript("OnEnter", function()
                local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
                label:SetTextColor(eg.r, eg.g, eg.b, 1)
            end)
            ov:SetScript("OnLeave", function() label:SetTextColor(1, 1, 1, 0.56) end)
            -- Click unsyncs the section (custom party settings), mirroring an uncheck in the "Use Raid Settings For" dropdown.
            ov:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end
                if not db.profile.partySyncSections then db.profile.partySyncSections = {} end
                db.profile.partySyncSections[sectionKey] = false
                if ns._RefreshProxyModes then ns._RefreshProxyModes() end
                self:Hide()
                if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
                if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
                    ns.ShowPartyPreview()
                end
                if ns._syncDDRefresh then ns._syncDDRefresh() end
            end)
            syncOverlays[sectionKey] = ov
            -- Shown only while the section is synced.
            local ss = db.profile.partySyncSections
            if ss and ss[sectionKey] == false then ov:Hide() end
        end

        _partyCtx = true
        y = BuildVisualSections(parent, y, W, SyncOverlay)
        -- Do NOT reset _partyCtx here (the SelectPage hook owns it): resetting would break SSet after any RefreshPage on the party tab.

        return math.abs(y)
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
        panelBg:SetAllPoints(); panelBg:SetColorTexture(15/255, 17/255, 22/255, 0.9)
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
            -- _partyCtx (read by SGet/SSet/SVal in the value closures) is left
            -- untouched: this hidden pass's widgets and closures are discarded
            -- with the wrapper and never invoked, so only the live path needs it.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_MAIN then
                    return BuildMainPage(pageName, parent, yOffset)
                elseif pageName == PAGE_PARTY then
                    return BuildPartyPage(pageName, parent, yOffset)
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
            _partyCtx = (pageName == PAGE_PARTY)

            if pageName == PAGE_MAIN then
                return BuildMainPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PARTY then
                return BuildPartyPage(pageName, parent, yOffset)
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
            _partyCtx = (pageName == PAGE_PARTY)
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



