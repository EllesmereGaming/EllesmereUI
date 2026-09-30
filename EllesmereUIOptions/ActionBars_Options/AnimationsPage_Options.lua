if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\AnimationsPage_Options.lua
--  Action Bars options: the Bar Animations page (Bar Interactions, Custom
--  Proc Glow). EUI_ActionBars_Options.lua calls the init function once at
--  load, at the block's original place, so the Custom Proc Glow site
--  registers in the same order as before; it returns the page builder.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

local function InitAnimationsPage(PP, EAB, PAGE_ANIMATIONS)
    local SECTION_BAR_INTERACTIONS = "BAR INTERACTIONS"
    local SECTION_PROC_GLOW     = "CUSTOM PROC GLOW"

    local interactionTypeValues = { [1] = "Light", [2] = "Medium", [3] = "Strong", [4] = "Solid Color", [5] = "Border", [6] = "None" }
    local interactionTypeOrder  = { 1, 2, 3, 4, 5, 6 }
    local pushedTypeValues, pushedTypeOrder = interactionTypeValues, interactionTypeOrder
    local highlightTypeValues, highlightTypeOrder = interactionTypeValues, interactionTypeOrder
    -- Custom Proc Glow: shared glow controls over the proc glow keys. Shape Glow
    -- is internal-only (forced by custom button shapes at render time).
    local function ProcP() return EAB.db.profile end
    local _procGlowPreview
    local UpdateProcGlowPreview
    local GO = EllesmereUI.GlowOptions
    -- Custom button shapes force Shape Glow at render time (none/cropped do not).
    local function AnyBarHasCustomShape()
        local bars = EAB.db.profile.bars
        if not bars then return false end
        for _, s in pairs(bars) do
            if s.buttonShape and s.buttonShape ~= "none" and s.buttonShape ~= "cropped" then return true end
        end
        return false
    end
    local procGlowDesc = {
        host = "icon", excludes = { [4] = true },
        disabled = function() return EllesmereUI.BlizzStyle.Get("actionbars") end,
        disabledTooltip = function() return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled") end,
        rawTooltip = true,
        -- Custom shapes lock only the style: the forced Shape Glow still takes
        -- the color, and bars without a custom shape keep the saved style.
        styleDisabled = AnyBarHasCustomShape,
        styleDisabledTooltip = "Custom shapes always use Shape Glow -- change your bar shape to None or Cropped to pick a different glow",
        caps = { mode = true, params = true, bg = true },
        defaultColor = { r = 1, g = 0.776, b = 0.376 },
        isOff = function() local p = ProcP(); return p.procGlowEnabled == false or p.procGlowType == 0 end,
        onChange = function() EAB:RefreshProcGlows(); UpdateProcGlowPreview(_procGlowPreview) end,
        get = function(f)
            local p = ProcP()
            if f == "style" then return p.procGlowType or 1
            elseif f == "mode" then
                -- The class flag alone decides Class, so a spec override that
                -- holds only the flag keeps applying; the mode key tells Default
                -- from Custom. Both are read on every call (override tracing).
                local m = p.procGlowColorMode
                if p.procGlowUseClassColor then return "class" end
                return (m == "default") and "default" or "custom"
            elseif f == "color" then local c = p.procGlowColor or { r = 1, g = 0.776, b = 0.376 }; return c.r, c.g, c.b
            end
            return EllesmereUI.GlowOptions.FlatGet(p, "procGlow", f)
        end,
        set = function(f, a, b2, c2)
            local p = ProcP()
            if f == "style" then p.procGlowType = a; p.procGlowEnabled = (a ~= 0)
            elseif f == "mode" then
                -- The class flag stays in step (Bar Interactions' unified class toggle writes it too).
                p.procGlowColorMode = a
                p.procGlowUseClassColor = (a == "class")
            else EllesmereUI.GlowOptions.FlatSet(p, "procGlow", f, a, b2, c2)
            end
        end,
        confirm = function(v, commit)
            local p = ProcP()
            if ((p.procGlowType == 0) or (p.procGlowEnabled == false)) and v ~= 0 then
                EllesmereUI:ShowConfirmPopup({
                    title       = "Custom Proc Glow Settings",
                    message     = "Custom proc glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                    confirmText = "Enable",
                    cancelText  = "Cancel",
                    onConfirm   = commit,
                    onCancel    = function() EllesmereUI:RefreshPage() end,
                })
                return
            end
            commit()
        end,
    }
    GO.RegisterSite({ id = "ab_proc", label = "Custom Proc Glow", group = "module",
        module = "EllesmereUIActionBars", page = PAGE_ANIMATIONS, section = "CUSTOM PROC GLOW",
        highlight = "Custom Proc Glow", desc = procGlowDesc,
        -- Blizzard Style bars draw Blizzard's own proc glow.
        blocked = function() return EllesmereUI.BlizzStyle.Get("actionbars") end })

    -----------------------------------------------------------------------
    --  Preview icon helper for animation dropdown rows: small square icon with a 1px
    --  border, parented to a DualRow's left region, centered between label and dropdown.
    -----------------------------------------------------------------------
    local PREVIEW_ICON_SIZE = 30

    local function CreatePreviewIcon(parentRegion)
        local f = CreateFrame("Frame", nil, parentRegion)
        f:EnableMouse(false)
        PP.Size(f, PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
        -- Center vertically, positioned roughly between label and dropdown
        PP.Point(f, "RIGHT", parentRegion, "RIGHT", -200, 0)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetColorTexture(0.15, 0.15, 0.15, 1)
        f._icon = icon

        PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7)

        return f
    end

    -- Unified interaction preview (pushed / highlight)
    local INTERACTION_DEFAULTS = {
        pushed    = { typeDefault = 3, texFallback = 2, solidColor = { r = 1, g = 0.792, b = 0.427, a = 1 } },
        highlight = { typeDefault = 2, texFallback = 1, solidColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 } },
    }
    local function UpdateInteractionPreview(f, prefix)
        if not f then return end
        local p = EAB.db.profile
        local defs = INTERACTION_DEFAULTS[prefix]
        local iType = p[prefix .. "TextureType"] or defs.typeDefault
        if not f._overlay then
            local ov = f:CreateTexture(nil, "OVERLAY", nil, 1)
            ov:SetAllPoints()
            f._overlay = ov
        end
        if not f._borderOv then
            f._borderOv = {}
            for i = 1, 4 do
                local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
                t:SetColorTexture(1, 1, 1, 1)
                f._borderOv[i] = t
            end
        end
        local ov = f._overlay
        local bo = f._borderOv
        if iType == 6 then
            ov:Hide()
            for i = 1, 4 do bo[i]:Hide() end
        elseif iType == 4 then
            ov:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            ov:SetTexCoord(0, 1, 0, 1)
            ov:SetDesaturated(false)
            local cr, cg, cb, ca
            if p[prefix .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                cr, cg, cb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                ca = 1
            else
                local c = p[prefix .. "CustomColor"] or defs.solidColor
                cr, cg, cb, ca = c.r, c.g, c.b, c.a
            end
            ov:SetVertexColor(cr, cg, cb, 0.3)
            ov:Show()
            for i = 1, 4 do bo[i]:Hide() end
        elseif iType == 5 then
            ov:Hide()
            local bsz = p[prefix .. "BorderSize"] or 4
            local cr, cg, cb, ca
            if p[prefix .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                cr, cg, cb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                ca = 1
            else
                local c = p[prefix .. "CustomColor"] or { r = 1, g = 0.792, b = 0.427, a = 1 }
                cr, cg, cb, ca = c.r, c.g, c.b, c.a
            end
            for i = 1, 4 do bo[i]:SetVertexColor(cr, cg, cb, ca) end
            bo[1]:ClearAllPoints(); bo[1]:SetPoint("TOPLEFT", f); bo[1]:SetPoint("TOPRIGHT", f); PP.Height(bo[1], bsz); bo[1]:Show()
            bo[2]:ClearAllPoints(); bo[2]:SetPoint("BOTTOMLEFT", f); bo[2]:SetPoint("BOTTOMRIGHT", f); PP.Height(bo[2], bsz); bo[2]:Show()
            bo[3]:ClearAllPoints(); bo[3]:SetPoint("TOPLEFT", bo[1], "BOTTOMLEFT"); bo[3]:SetPoint("BOTTOMLEFT", bo[2], "TOPLEFT"); PP.Width(bo[3], bsz); bo[3]:Show()
            bo[4]:ClearAllPoints(); bo[4]:SetPoint("TOPRIGHT", bo[1], "BOTTOMRIGHT"); bo[4]:SetPoint("BOTTOMRIGHT", bo[2], "TOPRIGHT"); PP.Width(bo[4], bsz); bo[4]:Show()
        else
            local texIdx = iType
            if texIdx < 1 or texIdx > 3 then texIdx = defs.texFallback end
            ov:SetTexture(ns.HIGHLIGHT_TEXTURES[texIdx])
            ov:SetTexCoord(0, 1, 0, 1)
            if p[prefix .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                ov:SetDesaturated(true)
                ov:SetVertexColor(cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1, 1)
            else
                local c = p[prefix .. "CustomColor"] or { r = 1, g = 0.792, b = 0.427, a = 1 }
                ov:SetDesaturated(true)
                ov:SetVertexColor(c.r, c.g, c.b, c.a)
            end
            ov:Show()
            for i = 1, 4 do bo[i]:Hide() end
        end
    end
    local function UpdatePushedPreview(f)    UpdateInteractionPreview(f, "pushed")    end
    local function UpdateHighlightPreview(f) UpdateInteractionPreview(f, "highlight") end

    -- Proc glow preview: supports FlipBook + procedural glow engines
    local function GetNthActionButtonIcon(n)
        -- Find the Nth action button with an assigned spell across bars 1-8
        n = n or 1
        local BAR_CONFIG = {
            { prefix = "ActionButton", count = 12 },
            { prefix = "MultiBarBottomLeftButton", count = 12 },
            { prefix = "MultiBarBottomRightButton", count = 12 },
            { prefix = "MultiBarRightButton", count = 12 },
            { prefix = "MultiBarLeftButton", count = 12 },
            { prefix = "MultiBar5Button", count = 12 },
            { prefix = "MultiBar6Button", count = 12 },
            { prefix = "MultiBar7Button", count = 12 },
        }
        local found = 0
        for _, bar in ipairs(BAR_CONFIG) do
            for i = 1, bar.count do
                local btn = _G[bar.prefix .. i]
                if btn and btn.icon then
                    local tex = btn.icon:GetTexture()
                    if tex and tex ~= 0 and tex ~= "" and tex ~= 136235 then
                        found = found + 1
                        if found >= n then return tex end
                    end
                end
            end
        end
        return 136197  -- fallback: generic spell icon
    end

    UpdateProcGlowPreview = function(f)
        if not f then return end
        local G = EllesmereUI.Glows
        -- The glow draws on its own child frame: on f itself it shares the
        -- border's OVERLAY sublevel and a 1px Pixel Glow can vanish under it.
        local ov = f._glowOv
        if not ov then
            ov = CreateFrame("Frame", nil, f)
            ov:SetAllPoints(f)
            ov:EnableMouse(false)
            f._glowOv = ov
        end
        ov:SetFrameLevel(f:GetFrameLevel() + 2)
        G.StopAllGlows(ov)
        f:Show()
        -- Hidden (options closed, page left): stays stopped; OnShow restarts it.
        if not f:IsVisible() then return end
        -- If disabled (None selected), keep the icon visible but grayed out
        if not GO.IsCustomGlow(procGlowDesc) then
            f:SetAlpha(0.15)
            return
        end
        f:SetAlpha(1)
        G.StartSpecGlow(ov, GO.Spec(procGlowDesc), PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE, "icon", G.PANEL_EXTRA)
    end

    -- Assisted Highlight preview. Custom styles use the same shared glow engine
    -- as the live buttons, so the picker shows the real animation instead of a
    -- generic static border. Legacy Ring/Overlay modes keep a lightweight local
    -- preview and never touch live action-button glow state.
    local function UpdateAssistGlowPreview(f)
        if not f then return end
        local p = EAB.db and EAB.db.profile or {}
        local customType = p.assistGlowType or 0
        local style = p.assistGlowStyle or 1
        local G = EllesmereUI.Glows

        if not f._assistOverlay then
            local ov = f:CreateTexture(nil, "OVERLAY", nil, 1)
            ov:SetAllPoints()
            f._assistOverlay = ov
        end
        if not f._assistRing then
            local ring = {}
            for i = 1, 4 do
                local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
                t:SetColorTexture(0.15, 0.5, 1, 1)
                ring[i] = t
            end
            f._assistRing = ring
        end
        if not f._assistGlowOv then
            local host = CreateFrame("Frame", nil, f)
            host:SetAllPoints(f)
            host:EnableMouse(false)
            f._assistGlowOv = host
        end

        local ov = f._assistOverlay
        local ring = f._assistRing
        local glowHost = f._assistGlowOv
        glowHost:SetFrameLevel(f:GetFrameLevel() + 2)
        ov:Hide()
        for i = 1, 4 do ring[i]:Hide() end

        local list = ns.LOOP_GLOW_TYPES or {}
        if customType > 0 and list[customType] then
            local cr, cg, cb
            if p.assistGlowUseClassColor then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                cr, cg, cb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
            else
                local c = p.assistGlowColor or { r = 0.15, g = 0.5, b = 1 }
                cr, cg, cb = c.r or 0.15, c.g or 0.5, c.b or 1
            end
            f:SetAlpha(1)
            if f:IsVisible() then
                G.StartSpecGlow(glowHost,
                    { style = customType, r = cr, g = cg, b = cb },
                    PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE, "icon", G.PANEL_EXTRA)
            end
            return
        end

        G.StopAllGlows(glowHost)
        f:SetAlpha(1)

        -- Simple local representation for the legacy Blizzard/EUI ring modes.
        if style == 0 or style == 1 or style == 3 then
            ring[1]:ClearAllPoints(); ring[1]:SetPoint("TOPLEFT", f); ring[1]:SetPoint("TOPRIGHT", f); ring[1]:SetHeight(2)
            ring[2]:ClearAllPoints(); ring[2]:SetPoint("BOTTOMLEFT", f); ring[2]:SetPoint("BOTTOMRIGHT", f); ring[2]:SetHeight(2)
            ring[3]:ClearAllPoints(); ring[3]:SetPoint("TOPLEFT", ring[1], "BOTTOMLEFT"); ring[3]:SetPoint("BOTTOMLEFT", ring[2], "TOPLEFT"); ring[3]:SetWidth(2)
            ring[4]:ClearAllPoints(); ring[4]:SetPoint("TOPRIGHT", ring[1], "BOTTOMRIGHT"); ring[4]:SetPoint("BOTTOMRIGHT", ring[2], "TOPRIGHT"); ring[4]:SetWidth(2)
            for i = 1, 4 do ring[i]:Show() end
        end

        if style == 2 or style == 3 then
            local c = p.assistGlowOverlayColor or { r = 0.15, g = 0.5, b = 1 }
            local a = (p.assistGlowOverlayAlpha or 30) / 100
            ov:SetColorTexture(c.r or 0.15, c.g or 0.5, c.b or 1, a)
            ov:Show()
        end
    end

    -- Persistent preview icon frames (survive page cache restores)
    local _pushedPreview, _highlightPreview, _assistGlowPreview

    local function BuildAnimationsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h, row
        local p = EAB.db.profile

        -- No content header for animations page (global settings, no bar selector)
        EllesmereUI:ClearContentHeader()

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  BAR INTERACTIONS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_BAR_INTERACTIONS, y);  y = y - h

        local INTERACTIONS_TIP = "Bar Interactions are the light effects that happen when you hover/press a spell, your cooldown swipe line, aura active border glow, etc"

        -- Helper: apply unified color to ALL interaction systems
        local function ApplyAllInteractionColors()
            EAB:ApplyPushedTextures()
            EAB:ApplyHighlightTextures()
            EAB:ApplyCooldownEdge()
            EAB:ApplyMiscTextures()
            EAB:RefreshProcGlows()
            UpdatePushedPreview(_pushedPreview)
            UpdateHighlightPreview(_highlightPreview)
            UpdateProcGlowPreview(_procGlowPreview)
        end

        local function SetUnifiedColor(r, g, b, a)
            p.pushedCustomColor = { r = r, g = g, b = b, a = a }
            p.highlightCustomColor = { r = r, g = g, b = b, a = a }
            p.cooldownEdgeColor = { r = r, g = g, b = b, a = a }
            p.procGlowColor = { r = r, g = g, b = b }
            -- A Default-mode proc glow would ignore the pick; it takes the unified color as before.
            if p.procGlowColorMode == "default" then p.procGlowColorMode = "custom" end
            ApplyAllInteractionColors()
        end

        local function SetUnifiedClassColor(v)
            p.pushedUseClassColor = v
            p.highlightUseClassColor = v
            p.cooldownEdgeUseClassColor = v
            p.procGlowUseClassColor = v
            -- Keep the mode key in step with the flag.
            if p.procGlowColorMode == "class" or (v and p.procGlowColorMode) then
                p.procGlowColorMode = v and "class" or "custom"
            end
            ApplyAllInteractionColors()
            EllesmereUI:RefreshPage()
        end

        _, h = W:DualRow(parent, y,
            { type="colorpicker", text="Bar Interactions Color",
              tooltip=INTERACTIONS_TIP,
              disabled=function() return EllesmereUI.BlizzStyle.Get("actionbars") or p.pushedUseClassColor end,
              disabledTooltip=function()
                  if EllesmereUI.BlizzStyle.Get("actionbars") then return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled") end
                  return "This option requires Class Colors to be disabled"
              end,
              rawTooltip=true,
              getValue=function()
                  local c = p.pushedCustomColor
                  if not c then return 0.973, 0.839, 0.604, 1 end
                  return c.r, c.g, c.b, c.a
              end,
              setValue=function(r, g, b, a)
                  SetUnifiedColor(r, g, b, a)
              end,
              hasAlpha=true },
            { type="toggle", text="Class Colored Bar Interactions",
              tooltip=INTERACTIONS_TIP,
              disabled=function() return EllesmereUI.BlizzStyle.Get("actionbars") end,
              disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
              getValue=function() return p.pushedUseClassColor end,
              setValue=function(v)
                  SetUnifiedClassColor(v)
              end });  y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Pushed Type",
              tooltip="The overlay that appears on the icon when you press and hold a spell button",
              disabled=function() return EllesmereUI.BlizzStyle.Get("actionbars") end,
              disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
              values=pushedTypeValues, order=pushedTypeOrder,
              getValue=function() return p.pushedTextureType or 2 end,
              setValue=function(v)
                  p.pushedTextureType = v
                  EAB:ApplyPushedTextures()
                  UpdatePushedPreview(_pushedPreview)
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Highlight Type",
              tooltip="The overlay that appears on the icon when you hover your mouse over a spell button",
              disabled=function() return EllesmereUI.BlizzStyle.Get("actionbars") end,
              disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
              values=highlightTypeValues, order=highlightTypeOrder,
              getValue=function() return p.highlightTextureType or 2 end,
              setValue=function(v)
                  p.highlightTextureType = v
                  EAB:ApplyHighlightTextures()
                  UpdateHighlightPreview(_highlightPreview)
                  EllesmereUI:RefreshPage()
              end })
        -- Preview chrome: the search pre-build's absorber row cannot host frames.
        if not EllesmereUI._prebuilding then
            local leftRgn = row._leftRegion
            _pushedPreview = CreatePreviewIcon(leftRgn)
            if _pushedPreview._icon then
                _pushedPreview._icon:SetTexture(GetNthActionButtonIcon(1))
                _pushedPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            UpdatePushedPreview(_pushedPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdatePushedPreview(_pushedPreview) end)

            EllesmereUI.BuildInlineCog(leftRgn, {
                title = "Pushed Border Settings",
                anchorTo = _pushedPreview, chain = false,
                captureRegion = leftRgn,
                disabled = function() return (p.pushedTextureType or 2) ~= 5 end,
                disabledTooltip = "Border Pushed Type",
                rows = {
                    { type="slider", label="Border Size", min=1, max=10, step=1,
                      get=function() return p.pushedBorderSize or 4 end,
                      set=function(v)
                          p.pushedBorderSize = v
                          EAB:ApplyPushedTextures()
                          UpdatePushedPreview(_pushedPreview)
                      end },
                    { type="toggle", label="Match Bar Border",
                      tooltip="On bars with a textured border style, a press lights up the button's own border instead of drawing lines.",
                      get=function() return p.pushedBorderMatchBar or false end,
                      set=function(v)
                          p.pushedBorderMatchBar = v
                          EAB:ApplyPushedTextures()
                      end },
                },
            })

            local rightRgn = row._rightRegion
            _highlightPreview = CreatePreviewIcon(rightRgn)
            if _highlightPreview._icon then
                _highlightPreview._icon:SetTexture(GetNthActionButtonIcon(2))
                _highlightPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            UpdateHighlightPreview(_highlightPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdateHighlightPreview(_highlightPreview) end)

            EllesmereUI.BuildInlineCog(rightRgn, {
                title = "Highlight Border Settings",
                anchorTo = _highlightPreview, chain = false,
                captureRegion = rightRgn,
                disabled = function() return (p.highlightTextureType or 2) ~= 5 end,
                disabledTooltip = "Border Highlight Type",
                rows = {
                    { type="slider", label="Border Size", min=1, max=10, step=1,
                      get=function() return p.highlightBorderSize or 4 end,
                      set=function(v)
                          p.highlightBorderSize = v
                          EAB:ApplyHighlightTextures()
                          UpdateHighlightPreview(_highlightPreview)
                      end },
                    { type="toggle", label="Match Bar Border",
                      tooltip="On bars with a textured border style, hovering lights up the button's own border instead of drawing lines.",
                      get=function() return p.highlightBorderMatchBar or false end,
                      set=function(v)
                          p.highlightBorderMatchBar = v
                          EAB:ApplyHighlightTextures()
                      end },
                },
            })
        end
        y = y - h

        local function castAnimForced()
            local bars = EAB.db.profile.bars
            if not bars then return false end
            for _, s in pairs(bars) do
                if s.buttonShape and s.buttonShape ~= "none" then return true end
            end
            return false
        end
        local castRow
        castRow, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Casting Animations",
              tooltip="This is the full overlay that swipes from right to left on the icon during its cast duration",
              disabled=castAnimForced,
              disabledTooltip="This option requires a non-custom shaped action bar",
              rawTooltip=true,
              getValue=function() return p.hideCastingAnimations or castAnimForced() end,
              setValue=function(v)
                  p.hideCastingAnimations = v
                  -- ActionBarActionEventsFrame dies at file-load; ApplySettings owns casting animation visibility.
              end },
            { type="toggle", text="Show Highlight on Spell Cast",
              tooltip="The highlight overlay that appears on a spell button while it is the active/current action. Disable to hide it.",
              rawTooltip=true,
              getValue=function() return p.showCastHighlight ~= false end,
              setValue=function(v)
                  p.showCastHighlight = v
                  EAB:ApplyCheckedTextures()
                  -- The Spell Cast Highlight cog dims with this toggle.
                  EllesmereUI:RefreshPage()
              end })
        -- Spell Cast Highlight cog: the checked highlight as the button's own
        -- border on bars with a textured style (BuildInlineCog returns nothing
        -- during the search pre-build).
        EllesmereUI.BuildInlineCog(castRow._rightRegion, {
            title = "Spell Cast Highlight",
            captureRegion = castRow._rightRegion,
            disabled = function()
                return p.showCastHighlight == false or (EllesmereUI.BlizzStyle.Get("actionbars") and true or false)
            end,
            disabledTooltip = function()
                if EllesmereUI.BlizzStyle.Get("actionbars") then return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled") end
                return EllesmereUI.DisabledTooltip("Show Highlight on Spell Cast")
            end,
            rawTooltip = true,
            rows = {
                { type="toggle", label="Show as Border",
                  tooltip="On bars with a textured border style, the active spell shows a colored border instead of the highlight fill.",
                  get=function() return p.castHighlightBorder or false end,
                  set=function(v)
                      p.castHighlightBorder = v
                      EAB:ApplyCheckedTextures()
                  end },
            },
        })
        y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  PROC GLOW EFFECT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_PROC_GLOW, y);  y = y - h

        local procSpec = GO.DropdownSpec(procGlowDesc, "Custom Proc Glow")
        local function AssistOff()
            return not (GetCVarBool and GetCVarBool("assistedCombatHighlight"))
        end
        -- Row 1: Custom Proc Glow | its color swatches.
        row, h = W:DualRow(parent, y, procSpec, { type="label", text="Glow Color" })
        if not EllesmereUI._prebuilding then
            local leftRgn = row._leftRegion
            GO.AttachInline(leftRgn, procGlowDesc, row._rightRegion)
            _procGlowPreview = CreatePreviewIcon(leftRgn)
            -- Joins the inline chain left of the glow cog.
            _procGlowPreview:ClearAllPoints()
            PP.Point(_procGlowPreview, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = _procGlowPreview
            if _procGlowPreview._icon then
                local iconTex = GetNthActionButtonIcon(3)
                _procGlowPreview._icon:SetTexture(iconTex)
                _procGlowPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            -- Hidden (options closed, page left or rebuilt), the preview's glow
            -- leaves the glow driver; shown again, it restarts from the current values.
            _procGlowPreview:SetScript("OnHide", function(self)
                if self._glowOv then EllesmereUI.Glows.StopAllGlows(self._glowOv) end
            end)
            _procGlowPreview:SetScript("OnShow", UpdateProcGlowPreview)
            UpdateProcGlowPreview(_procGlowPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdateProcGlowPreview(_procGlowPreview) end)
        end
        y = y - h

        -- Assisted Highlight: keep the current upstream layout and add the
        -- optional custom glow engines as extra choices.
        local assistValues = {
            [0] = "Default (Blizzard)",
            [1] = "Glow Ring",
            [2] = "Button Overlay",
            [3] = "Ring + Overlay",
        }
        local assistOrder = { 0, 1, 2, 3 }
        for i, entry in ipairs(ns.LOOP_GLOW_TYPES or {}) do
            if not entry.shapeGlow then
                assistValues[100 + i] = entry.name
                assistOrder[#assistOrder + 1] = 100 + i
            end
        end
        local function assistCustomSelected() return (p.assistGlowType or 0) > 0 end
        local function RingOff()
            local style = p.assistGlowStyle or 1
            return AssistOff() or assistCustomSelected() or style == 2
        end
        local function OverlayOff()
            local style = p.assistGlowStyle or 1
            return AssistOff() or assistCustomSelected() or style == 1
        end

        -- Row 2: Assisted Highlight | Assisted Highlight Outset
        local assistRow
        assistRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Assisted Highlight",
              values=assistValues, order=assistOrder,
              tooltip="Use Blizzard-style highlighting, the existing EUI styles, or an optional custom glow. Existing users keep Glow Ring unless they choose another entry.",
              disabled=AssistOff,
              disabledTooltip="This option requires Blizzard's Assisted Highlight to be enabled",
              rawTooltip=true,
              getValue=function()
                  local custom = p.assistGlowType or 0
                  local list = ns.LOOP_GLOW_TYPES or {}
                  if custom > 0 and list[custom] then return 100 + custom end
                  return p.assistGlowStyle or 1
              end,
              setValue=function(v)
                  if v >= 100 then
                      p.assistGlowType = v - 100
                  else
                      p.assistGlowType = 0
                      p.assistGlowStyle = v
                  end
                  if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
                  UpdateAssistGlowPreview(_assistGlowPreview)
                  C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end },
            { type="slider", text="Assisted Highlight Outset", min=-10, max=30, step=1,
              tooltip="Moves the blue Assisted Highlight ring outward (or inward at negative values) so it no longer overlaps the proc glow on the same button. With Ring + Overlay the tint resizes along with it, so the two stay flush.",
              disabled=RingOff,
              disabledTooltip="This option requires Glow Ring or Ring + Overlay",
              rawTooltip=true,
              getValue=function() return p.assistGlowOutset or 0 end,
              setValue=function(v)
                  p.assistGlowOutset = v
                  if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
                  UpdateAssistGlowPreview(_assistGlowPreview)
              end })
        if not EllesmereUI._prebuilding then
            local leftRgn = assistRow._leftRegion
            _assistGlowPreview = CreatePreviewIcon(leftRgn)
            _assistGlowPreview:ClearAllPoints()
            PP.Point(_assistGlowPreview, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            if _assistGlowPreview._icon then
                _assistGlowPreview._icon:SetTexture(GetNthActionButtonIcon(4))
                _assistGlowPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            -- Custom Assisted Highlight color lives beside its preview icon, as
            -- in the original layout. It is disabled for legacy styles and while
            -- class color owns the custom glow color.
            local assistSwatch, assistUpdateSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local c = p.assistGlowColor or { r = 0.15, g = 0.5, b = 1 }
                    return c.r, c.g, c.b
                end,
                function(r, g, b)
                    p.assistGlowColor = { r = r, g = g, b = b }
                    if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
                    UpdateAssistGlowPreview(_assistGlowPreview)
                end, nil, 24)
            PP.Point(assistSwatch, "RIGHT", _assistGlowPreview, "LEFT", -12, 0)
            assistSwatch:HookScript("OnEnter", function(self)
                if AssistOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "This option requires Blizzard's Assisted Highlight to be enabled")
                elseif not assistCustomSelected() then
                    EllesmereUI.ShowWidgetTooltip(self, "This option requires a custom Assisted Highlight glow to be selected")
                elseif p.assistGlowUseClassColor then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Class Colors", "disabled"))
                end
            end)
            assistSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function RefreshAssistSwatch()
                local off = AssistOff() or not assistCustomSelected() or p.assistGlowUseClassColor
                assistSwatch:SetAlpha(off and 0.15 or 1)
                assistSwatch:SetMouseClickEnabled(not off)
                assistUpdateSwatch()
            end
            EllesmereUI.RegisterWidgetRefresh(RefreshAssistSwatch)
            RefreshAssistSwatch()

            -- Keep animated preview hosts out of the central glow driver while
            -- this page is hidden; restart them from the current values on show.
            _assistGlowPreview:SetScript("OnHide", function(self)
                if self._assistGlowOv then EllesmereUI.Glows.StopAllGlows(self._assistGlowOv) end
            end)
            _assistGlowPreview:SetScript("OnShow", UpdateAssistGlowPreview)
            UpdateAssistGlowPreview(_assistGlowPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdateAssistGlowPreview(_assistGlowPreview) end)
        end
        y = y - h

        -- Row 3: Overlay Opacity (+ overlay color) | Fit Ring to Cropped Buttons
        local overlayRow
        overlayRow, h = W:DualRow(parent, y,
            { type="slider", text="Overlay Opacity", min=0, max=100, step=1,
              tooltip="Opacity of the Button Overlay tint.",
              disabled=OverlayOff,
              disabledTooltip="This option requires the Button Overlay or Ring + Overlay style",
              rawTooltip=true,
              getValue=function() return p.assistGlowOverlayAlpha or 30 end,
              setValue=function(v)
                  p.assistGlowOverlayAlpha = v
                  if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
                  UpdateAssistGlowPreview(_assistGlowPreview)
              end },
            { type="toggle", text="Fit Ring to Cropped Buttons",
              tooltip="On Cropped bars, shapes the Assisted Highlight ring to the button instead of a square.",
              disabled=RingOff,
              disabledTooltip="This option requires Glow Ring or Ring + Overlay",
              rawTooltip=true,
              getValue=function() return p.assistGlowFitCropped or false end,
              setValue=function(v)
                  p.assistGlowFitCropped = v
                  if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
              end })
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(overlayRow._leftRegion, {
                { tooltip = "Button Overlay Color", hasAlpha = false,
                  getValue = function()
                      local c = p.assistGlowOverlayColor or { r = 0.15, g = 0.5, b = 1 }
                      return c.r, c.g, c.b
                  end,
                  setValue = function(r, g, b)
                      p.assistGlowOverlayColor = { r = r, g = g, b = b }
                      if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
                      UpdateAssistGlowPreview(_assistGlowPreview)
                  end },
            }, {
                disabled = OverlayOff,
                disabledTooltip = "This option requires the Button Overlay or Ring + Overlay style",
            })
        end
        y = y - h

        -- Row 4: class-color ownership for custom Assisted Highlight glows.
        -- The custom color swatch itself is inline beside the preview icon above.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Use Class Color",
              disabled=function() return AssistOff() or not assistCustomSelected() end,
              disabledTooltip="This option requires a custom Assisted Highlight glow to be selected",
              rawTooltip=true,
              getValue=function() return p.assistGlowUseClassColor or false end,
              setValue=function(v)
                  p.assistGlowUseClassColor = v
                  if ns.UpdateAssistHighlights then ns.UpdateAssistHighlights() end
                  UpdateAssistGlowPreview(_assistGlowPreview)
                  EllesmereUI:RefreshPage()
              end },
            { type="label", text="" });  y = y - h

        return math.abs(y)
    end

    return BuildAnimationsPage
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_InitAnimationsPage = InitAnimationsPage
