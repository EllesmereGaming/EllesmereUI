-------------------------------------------------------------------------------
--  EllesmereUIDataBars_Options.lua
--  The "DataBars" options page for the multi-bar engine.
--
--  Layout:
--    * Content header: bar selector dropdown (rename/delete inline), "+ New
--      Bar" template card strip, and an interactive preview of the selected
--      bar. Preview segments click-navigate to their block's section.
--    * Body: Bar Settings (topped by the Auto Sized / Even Split mode
--      toggle), then one section per block (in bar order); adding blocks =
--      the preview strip's "+" tile. Zero bars renders a template-card
--      empty state instead. (The old per-block % divider-drag machinery in
--      the strip is dormant: IsPctBlock returns false for every boundary.)
--
--  Everything here talks to the runtime exclusively through the ns.* API
--  listed at the top of EllesmereUIDataBars.lua.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local PAGE_DATABARS = "DataBars"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local PP     = EllesmereUI.PP
    local L      = EllesmereUI.L
    local Lf     = EllesmereUI.Lf
    local format = string.format
    local floor  = math.floor

    ---------------------------------------------------------------------------
    --  Module upvalues (survive page rebuilds; closures re-target each build)
    ---------------------------------------------------------------------------
    local _edbHeaderBuilder      -- content-header closure (getHeaderBuilder returns it)
    local _edbNavigateFn         -- set per page build: click-to-scroll handler
    local _edbSegHighlightFn     -- set per header build: preview segment wash
    local _edbSegHoverId         -- block id whose SEGMENT hover owns the live
                                 -- bar highlight (the watcher must not clear it)
    local _edbStripRelayout      -- set per header build: re-solves + repositions the preview
    local _edbPreviewHost        -- the preview strip frame (live theme feedback)
    local _cardsExpanded = false -- template card strip open/closed
    local _dividerDragging = false

    ---------------------------------------------------------------------------
    --  Block-type registry views
    ---------------------------------------------------------------------------
    local TYPE_LABEL = {}
    for _, t in ipairs(ns.BLOCK_TYPES) do TYPE_LABEL[t.key] = t.label end

    -- Typical content extents (real-bar px) for auto-fit blocks that have no
    -- live instance yet; the preview scales these into strip space.
    local EST_LEN = {
        clock = 150, fps = 70, ms = 70, gold = 150, xprep = 140, spec = 130,
        profession = 120, travel = 40, micromenu = 340, currency = 90, spacer = 40,
        durability = 70, profession2 = 120,
    }

    ---------------------------------------------------------------------------
    --  Profile helpers
    ---------------------------------------------------------------------------
    local function Profile()
        return ns.GetProfile()
    end

    -- Selected bar, validated (falls back to the first bar).
    local function SelectedBar()
        local p = Profile()
        if not p then return nil end
        local bars = p.bars
        if #bars == 0 then return nil end
        if p.selectedBarId then
            local b = ns.GetBar(p.selectedBarId)
            if b then return b end
        end
        p.selectedBarId = bars[1].id
        return bars[1]
    end

    local function ResolvedBarLength(cfg)
        if cfg.lengthMode == "full" then
            if cfg.orientation == "V" then return UIParent:GetHeight() end
            return UIParent:GetWidth()
        end
        if cfg.length then return cfg.length end
        return 400
    end

    -- Structural change: rebuild the content header AND the page body.
    -- Zero bars = NO content header at all: the page falls back to the
    -- full-body starting screen (template cards), same as first open.
    local function HardRefresh()
        EllesmereUI:InvalidateContentHeaderCache()
        if SelectedBar() then
            EllesmereUI:SetContentHeader(_edbHeaderBuilder)
        else
            EllesmereUI:ClearContentHeader()
        end
        EllesmereUI:RefreshPage(true)
    end

    -- Header-only change (template card strip open/close).
    local function HeaderOnly()
        EllesmereUI:InvalidateContentHeaderCache()
        if SelectedBar() then
            EllesmereUI:SetContentHeader(_edbHeaderBuilder)
        else
            EllesmereUI:ClearContentHeader()
        end
    end

    -- Live theme feedback for the preview strip (swatch drag / dim slider).
    local function RefreshPreviewTheme()
        local cfg = SelectedBar()
        if _edbPreviewHost and _edbPreviewHost:IsShown() and cfg then
            ns.MakePreviewBackdrop(_edbPreviewHost, cfg.theme)
        end
    end

    ---------------------------------------------------------------------------
    --  Shared popup flows (header menu + body buttons)
    ---------------------------------------------------------------------------
    local function PromptRenameBar(cfg)
        local oldName = cfg.name
        if oldName == nil then oldName = "" end
        EllesmereUI:ShowInputPopup({
            title = "Rename DataBar",
            message = Lf("Enter a new name for \"%1$s\":", oldName),
            placeholder = oldName,
            confirmText = "Rename",
            cancelText = "Cancel",
            onConfirm = function(newName)
                if newName then newName = strtrim(newName) else newName = "" end
                if newName == "" or newName == oldName then return end
                ns.RenameBar(cfg.id, newName)
                EllesmereUI:InvalidateModulePageCache("EllesmereUIDataBars")
                HardRefresh()
            end,
        })
    end

    local function PromptDeleteBar(cfg)
        local delName = cfg.name
        if delName == nil then delName = "" end
        EllesmereUI:ShowConfirmPopup({
            title = "Delete DataBar",
            message = Lf("Are you sure you want to delete \"%1$s\"?", delName),
            confirmText = "Delete",
            cancelText = "Cancel",
            onConfirm = function()
                ns.DeleteBar(cfg.id)
                local p = Profile()
                local bars = ns.BarsInOrder()
                if p and bars[1] then p.selectedBarId = bars[1].id end
                EllesmereUI:InvalidateModulePageCache("EllesmereUIDataBars")
                HardRefresh()
                -- The rebuilt page (possibly the zero-bar empty state) can
                -- be shorter than the old scroll offset, which leaves the
                -- viewport past the content = blank page. Always return to
                -- the top after a delete.
                if EllesmereUI.SmoothScrollTo then EllesmereUI.SmoothScrollTo(0) end
            end,
        })
    end

    local function CreateBarFromTemplate(key)
        ns.CreateBar(key)
        _cardsExpanded = false
        HardRefresh()
    end

    ---------------------------------------------------------------------------
    --  Template cards (header strip + zero-bars empty state)
    ---------------------------------------------------------------------------
    local TEMPLATE_CARDS = {
        { key = "empty",      icon = "eui-edit.png",    title = "Start Empty",
          desc = "A blank bar to build from scratch." },
        { key = "bottom",     icon = "grid.png",        title = "Bottom Info Bar",
          desc = "Full-width bar with the classic info blocks." },
        { key = "minimapc",   icon = "coordinates.png", title = "Minimap Companion",
          desc = "Compact clock and FPS readout." },
        { key = "microstrip", icon = "cogs.png",        title = "Micro Menu Strip",
          desc = "Just the micro menu buttons." },
    }
    local MEDIA_ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

    local function MakeTemplateCard(host, x, y, w, cardH, def)
        local EGc = EllesmereUI.ELLESMERE_GREEN
        local card = CreateFrame("Button", nil, host)
        PP.Size(card, w, cardH)
        PP.Point(card, "TOPLEFT", host, "TOPLEFT", x, y)
        card:SetFrameLevel(host:GetFrameLevel() + 2)

        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        local cbrd = EllesmereUI.MakeBorder(card, 1, 1, 1, 0.12, PP)

        local accentLine = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accentLine:SetColorTexture(EGc.r, EGc.g, EGc.b, 0.6)
        PP.Point(accentLine, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accentLine, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accentLine:SetHeight(2)
        if accentLine.SetSnapToPixelGrid then accentLine:SetSnapToPixelGrid(false); accentLine:SetTexelSnappingBias(0) end

        local cIcon = card:CreateTexture(nil, "ARTWORK")
        cIcon:SetSize(24, 24)
        PP.Point(cIcon, "LEFT", card, "LEFT", 14, 0)
        cIcon:SetTexture(MEDIA_ICONS .. def.icon)
        cIcon:SetVertexColor(EGc.r, EGc.g, EGc.b)
        cIcon:SetAlpha(0.6)
        if cIcon.SetSnapToPixelGrid then cIcon:SetSnapToPixelGrid(false); cIcon:SetTexelSnappingBias(0) end

        local titleFs = EllesmereUI.MakeFont(card, 12, nil, 1, 1, 1, 0.9)
        PP.Point(titleFs, "TOPLEFT", cIcon, "TOPRIGHT", 12, 1)
        PP.Point(titleFs, "RIGHT", card, "RIGHT", -8, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(L(def.title))

        local descFs = EllesmereUI.MakeFont(card, 10, nil, 1, 1, 1, 0.35)
        PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
        PP.Point(descFs, "RIGHT", card, "RIGHT", -8, 0)
        descFs:SetJustifyH("LEFT")
        descFs:SetWordWrap(false)
        descFs:SetText(L(def.desc))

        card:SetScript("OnEnter", function()
            cbg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
            cbrd:SetColor(1, 1, 1, 0.22)
            titleFs:SetAlpha(1)
            cIcon:SetAlpha(0.85)
        end)
        card:SetScript("OnLeave", function()
            cbg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            cbrd:SetColor(1, 1, 1, 0.12)
            titleFs:SetAlpha(0.9)
            cIcon:SetAlpha(0.6)
        end)
        card:SetScript("OnClick", function() CreateBarFromTemplate(def.key) end)
        return card
    end


    ---------------------------------------------------------------------------
    --  Content header: selector row + template cards + interactive preview
    ---------------------------------------------------------------------------
    local STRIP_H_THICK = 40   -- horizontal preview strip height
    local STRIP_V_LEN   = 150  -- vertical preview strip length (height)
    local STRIP_V_THICK = 40   -- vertical preview strip width
    local SEDGE = 0            -- strip edge pad (mirrors ns.EDGE_PAD visually)

    ---------------------------------------------------------------------------
    --  Vertical preview popout (TBB pattern): a vertical bar's interactive
    --  strip renders in an overlay docked to the panel's left edge -- a tall
    --  strip cannot live in the content header. Horizontal bars keep the
    --  in-header strip untouched.
    ---------------------------------------------------------------------------
    local _edbPopout
    local function PreviewPopoutAllowed()
        if not (EllesmereUI.IsShown and EllesmereUI:IsShown()) then return false end
        -- nil = mid-build (page state not stamped yet); only a definite
        -- mismatch blocks, mirroring the TBB popout gate.
        local am = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
        local ap = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        if am and ap and (am ~= "EllesmereUIDataBars" or ap ~= PAGE_DATABARS) then
            return false
        end
        return true
    end

    local function GetPreviewPopout()
        if _edbPopout then return _edbPopout end
        local oc = CreateFrame("Frame", nil, UIParent)
        oc:SetFrameStrata("FULLSCREEN_DIALOG")
        oc:SetFrameLevel(10)
        oc:SetClampedToScreen(true)
        oc:Hide()
        local bg = oc:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.9)
        local title = EllesmereUI.MakeFont(oc, 13, nil, 1, 1, 1, 0.9)
        title:SetPoint("TOP", oc, "TOP", 0, -7)
        title:SetText(L("Preview"))
        oc._title = title
        local hint = EllesmereUI.MakeFont(oc, 10, nil, 1, 1, 1, 0.4)
        hint:SetPoint("BOTTOM", oc, "BOTTOM", 0, 7)
        hint:SetText(L("Drag to Reorder. Click to Scroll. Right Click to Remove."))
        oc._hint = hint
        -- Self-heal (runs ONLY while shown = zero cost hidden): hide when
        -- the panel closes or another page fronts, like the TBB popout.
        local acc = 0
        oc:SetScript("OnUpdate", function(self, elapsed)
            acc = acc + elapsed
            if acc < 0.25 then return end
            acc = 0
            if not PreviewPopoutAllowed() then self:Hide() end
        end)
        _edbPopout = oc
        return oc
    end

    _edbHeaderBuilder = function(hdr, hdrW)
        local PAD = EllesmereUI.CONTENT_PAD
        if not PAD then PAD = 10 end
        local DDS = EllesmereUI.DD_STYLE
        local EGc = EllesmereUI.ELLESMERE_GREEN
        local tDimR = EllesmereUI.TEXT_DIM_R; if tDimR == nil then tDimR = 0.7 end
        local tDimG = EllesmereUI.TEXT_DIM_G; if tDimG == nil then tDimG = 0.7 end
        local tDimB = EllesmereUI.TEXT_DIM_B; if tDimB == nil then tDimB = 0.7 end
        local tDimA = EllesmereUI.TEXT_DIM_A; if tDimA == nil then tDimA = 0.85 end
        local fy = -8

        local cfg = SelectedBar()
        _edbPreviewHost = nil
        _edbStripRelayout = nil

        -----------------------------------------------------------------------
        --  Row 1: bar selector dropdown | + New Bar (centered as a pair)
        -----------------------------------------------------------------------
        local DD_H = 30
        local ddW = 280
        local NEWBTN_W = 110
        local ddBtn = CreateFrame("Button", nil, hdr)
        PP.Size(ddBtn, ddW, DD_H)
        PP.Point(ddBtn, "TOPLEFT", hdr, "TOPLEFT", (hdrW - (ddW + 10 + NEWBTN_W)) / 2, fy)
        ddBtn:SetFrameLevel(hdr:GetFrameLevel() + 5)
        local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_A)
        local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, DDS.BRD_A, EllesmereUI.PanelPP)
        local ddLbl = EllesmereUI.MakeFont(ddBtn, 13, nil, 1, 1, 1, DDS.TXT_A)
        ddLbl:SetJustifyH("LEFT")
        ddLbl:SetWordWrap(false)
        ddLbl:SetMaxLines(1)
        ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
        local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, EllesmereUI.PanelPP)
        ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        if cfg then
            local nm = cfg.name
            if nm == nil then nm = "" end
            ddLbl:SetText(nm)
        else
            ddLbl:SetText(L("No DataBars"))
        end

        local ddMenu
        local function BuildBarMenu()
            if ddMenu then ddMenu:Hide(); ddMenu = nil end
            local menu = CreateFrame("Frame", nil, UIParent)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
            menu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
            local bg = menu:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_HA)
            EllesmereUI.MakeBorder(menu, 1, 1, 1, DDS.BRD_A, PP)

            local ITEM_H = 26
            local ICON_SZ = 14
            local hlA = DDS.ITEM_HL_A
            local selA = DDS.ITEM_SEL_A
            local mH = 4
            local bars = ns.BarsInOrder()

            for idx = 1, #bars do
                local b = bars[idx]
                local isSel = cfg ~= nil and b.id == cfg.id
                local item = CreateFrame("Button", nil, menu)
                item:SetHeight(ITEM_H)
                item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                item:SetFrameLevel(menu:GetFrameLevel() + 2)

                local iLbl = EllesmereUI.MakeFont(item, 11, nil, tDimR, tDimG, tDimB, tDimA)
                iLbl:SetJustifyH("LEFT")
                iLbl:SetWordWrap(false)
                iLbl:SetMaxLines(1)
                iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                local nm = b.name
                if nm == nil then nm = "" end
                iLbl:SetText(nm)

                local iHl = item:CreateTexture(nil, "ARTWORK")
                iHl:SetAllPoints()
                iHl:SetColorTexture(1, 1, 1, 1)
                if isSel then iHl:SetAlpha(selA) else iHl:SetAlpha(0) end

                -- Inline delete + rename (every DataBar is user-created)
                local delBtn = CreateFrame("Button", nil, item)
                delBtn:SetSize(ICON_SZ, ICON_SZ)
                delBtn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                delIcon:SetSize(ICON_SZ, ICON_SZ)
                delIcon:SetPoint("CENTER", delBtn, "CENTER", 0, 0)
                if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
                delIcon:SetTexture(MEDIA_ICONS .. "eui-close.png")
                delBtn:SetAlpha(0.75)

                local editBtn = CreateFrame("Button", nil, item)
                editBtn:SetSize(ICON_SZ, ICON_SZ)
                editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
                editBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                local edIcon = editBtn:CreateTexture(nil, "OVERLAY")
                edIcon:SetSize(ICON_SZ, ICON_SZ)
                edIcon:SetPoint("CENTER", editBtn, "CENTER", 0, 0)
                if edIcon.SetSnapToPixelGrid then edIcon:SetSnapToPixelGrid(false); edIcon:SetTexelSnappingBias(0) end
                edIcon:SetTexture(MEDIA_ICONS .. "eui-edit.png")
                editBtn:SetAlpha(0.75)

                iLbl:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)

                local function InlineBtnEnter(btnSelf)
                    btnSelf:SetAlpha(1)
                    iLbl:SetTextColor(1, 1, 1, 1)
                    iHl:SetAlpha(hlA)
                    delBtn:SetAlpha(0.85)
                    editBtn:SetAlpha(0.85)
                end
                local function InlineBtnLeave(btnSelf)
                    if item:IsMouseOver() or delBtn:IsMouseOver() or editBtn:IsMouseOver() then
                        btnSelf:SetAlpha(0.85)
                        return
                    end
                    delBtn:SetAlpha(0.75)
                    editBtn:SetAlpha(0.75)
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    if isSel then iHl:SetAlpha(selA) else iHl:SetAlpha(0) end
                end

                delBtn:SetScript("OnEnter", function(btnSelf)
                    InlineBtnEnter(btnSelf)
                    EllesmereUI.ShowWidgetTooltip(btnSelf, EllesmereUI.L("Delete"))
                end)
                delBtn:SetScript("OnLeave", function(btnSelf)
                    InlineBtnLeave(btnSelf)
                    EllesmereUI.HideWidgetTooltip()
                end)
                editBtn:SetScript("OnEnter", function(btnSelf)
                    InlineBtnEnter(btnSelf)
                    EllesmereUI.ShowWidgetTooltip(btnSelf, EllesmereUI.L("Rename"))
                end)
                editBtn:SetScript("OnLeave", function(btnSelf)
                    InlineBtnLeave(btnSelf)
                    EllesmereUI.HideWidgetTooltip()
                end)
                delBtn:SetScript("OnClick", function()
                    menu:Hide()
                    PromptDeleteBar(b)
                end)
                editBtn:SetScript("OnClick", function()
                    menu:Hide()
                    PromptRenameBar(b)
                end)

                item:SetScript("OnEnter", function()
                    iLbl:SetTextColor(1, 1, 1, 1)
                    iHl:SetAlpha(hlA)
                    delBtn:SetAlpha(1)
                    editBtn:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    if delBtn:IsMouseOver() then return end
                    if editBtn:IsMouseOver() then return end
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    if isSel then iHl:SetAlpha(selA) else iHl:SetAlpha(0) end
                    delBtn:SetAlpha(0.75)
                    editBtn:SetAlpha(0.75)
                end)
                item:SetScript("OnClick", function()
                    menu:Hide()
                    local p = Profile()
                    if p then p.selectedBarId = b.id end
                    HardRefresh()
                end)

                mH = mH + ITEM_H
            end

            if #bars > 0 then
                local div = menu:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9
            end

            -- "+ Create New DataBar..." action row (expands the card strip)
            local addItem = CreateFrame("Button", nil, menu)
            addItem:SetHeight(ITEM_H)
            addItem:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
            addItem:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
            addItem:SetFrameLevel(menu:GetFrameLevel() + 2)
            local addLbl = EllesmereUI.MakeFont(addItem, 11, nil, tDimR, tDimG, tDimB, tDimA)
            addLbl:SetPoint("LEFT", addItem, "LEFT", 10, 0)
            addLbl:SetJustifyH("LEFT")
            addLbl:SetText(L("+ Create New DataBar..."))
            local addHl = addItem:CreateTexture(nil, "ARTWORK")
            addHl:SetAllPoints()
            addHl:SetColorTexture(1, 1, 1, 1)
            addHl:SetAlpha(0)
            addItem:SetScript("OnEnter", function()
                addLbl:SetTextColor(1, 1, 1, 1)
                addHl:SetAlpha(hlA)
            end)
            addItem:SetScript("OnLeave", function()
                addLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                addHl:SetAlpha(0)
            end)
            addItem:SetScript("OnClick", function()
                menu:Hide()
                _cardsExpanded = true
                HeaderOnly()
            end)
            mH = mH + ITEM_H

            menu:SetHeight(mH + 4)

            -- Close on left-click outside (non-blocking)
            menu:SetScript("OnUpdate", function(m)
                if not m:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
            menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)

            menu:Show()
            ddMenu = menu
        end

        ddBtn:SetScript("OnEnter", function()
            ddLbl:SetAlpha(1)
            local brdHA = DDS.BRD_HA; if brdHA == nil then brdHA = 0.30 end
            ddBrd:SetColor(1, 1, 1, brdHA)
            ddBg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_HA)
        end)
        ddBtn:SetScript("OnLeave", function()
            if ddMenu and ddMenu:IsShown() then return end
            ddLbl:SetAlpha(DDS.TXT_A)
            ddBrd:SetColor(1, 1, 1, DDS.BRD_A)
            ddBg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_A)
        end)
        ddBtn:SetScript("OnClick", function()
            if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildBarMenu() end
        end)
        ddBtn:HookScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)

        -- "+ New Bar" (toggles the template card strip)
        local newBtn = CreateFrame("Button", nil, hdr)
        PP.Size(newBtn, 110, DD_H)
        PP.Point(newBtn, "LEFT", ddBtn, "RIGHT", 10, 0)
        newBtn:SetFrameLevel(hdr:GetFrameLevel() + 5)
        EllesmereUI.MakeStyledButton(newBtn, "+ New Bar", 12, EllesmereUI.WB_COLOURS, function()
            _cardsExpanded = not _cardsExpanded
            HeaderOnly()
        end)

        -- (Bar enable lives in the BAR SETTINGS section, not the header.)

        fy = fy - DD_H - 10

        -----------------------------------------------------------------------
        --  Template card strip (expanded state)
        -----------------------------------------------------------------------
        if _cardsExpanded then
            local stripW = hdrW - PAD * 2
            local gap = 10
            local cw = floor((stripW - gap * 3) / 4)
            local ch = 64
            local host = CreateFrame("Frame", nil, hdr)
            PP.Size(host, stripW, ch)
            PP.Point(host, "TOPLEFT", hdr, "TOPLEFT", PAD, fy)
            for i = 1, 4 do
                MakeTemplateCard(host, (i - 1) * (cw + gap), 0, cw, ch, TEMPLATE_CARDS[i])
            end
            fy = fy - ch - 12
        end

        -----------------------------------------------------------------------
        --  Zero bars: hint only, no preview
        -----------------------------------------------------------------------
        if not cfg then
            local hint = EllesmereUI.MakeFont(hdr, 12, nil, 1, 1, 1, 0.4)
            hint:SetPoint("TOPLEFT", hdr, "TOPLEFT", PAD + 4, fy - 2)
            hint:SetText(L("Create a DataBar to get started."))
            fy = fy - 24
            return math.abs(fy) + 6
        end

        -----------------------------------------------------------------------
        --  Interactive preview strip
        -----------------------------------------------------------------------
        -- Extra breathing room above the preview strip.
        fy = fy - 10

        local vertical = cfg.orientation == "V"
        local stripLen, stripThick
        local stripParent = hdr
        if vertical then
            -- Vertical: the strip lives in the docked overlay popout. Drop
            -- the previous build's strip first (the popout persists across
            -- header rebuilds; header children are framework-managed but
            -- this one is ours).
            local oc = GetPreviewPopout()
            if oc._strip then oc._strip:Hide(); oc._strip:SetParent(nil); oc._strip = nil end
            stripParent = oc
            stripThick = STRIP_V_THICK
            stripLen = STRIP_V_LEN
            local sf = EllesmereUI._scrollFrame
            local sfH = sf and sf:GetHeight()
            if sfH and sfH > 260 then stripLen = math.min(520, sfH - 150) end
        else
            if _edbPopout then _edbPopout:Hide() end
            stripLen = hdrW - PAD * 2 - (STRIP_H_THICK + 8)   -- room for the + tile
            stripThick = STRIP_H_THICK
        end

        local strip = CreateFrame("Frame", nil, stripParent)
        if vertical then
            PP.Size(strip, stripThick, stripLen)
        else
            PP.Size(strip, stripLen, stripThick)
        end
        if vertical then
            local oc = stripParent
            oc._strip = strip
            -- Sized around strip + title/hint chrome + the add tile below.
            PP.Size(oc, math.max(stripThick + 90, 150), stripLen + stripThick + 74)
            strip:ClearAllPoints()
            strip:SetPoint("TOP", oc, "TOP", 0, -28)
            strip:SetFrameLevel(oc:GetFrameLevel() + 3)
            oc:ClearAllPoints()
            local sf = EllesmereUI._scrollFrame
            if sf then
                oc:SetPoint("RIGHT", sf, "LEFT", 0, 0)
            else
                oc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            oc:Show()
        else
            PP.Point(strip, "TOPLEFT", hdr, "TOPLEFT", PAD, fy)
            strip:SetFrameLevel(hdr:GetFrameLevel() + 3)
        end
        -- Border handle set BEFORE the backdrop so the theme pass can fade
        -- it with Bar Opacity, exactly like the live bar.
        strip._edbBorder = PP.CreateBorder(strip, 0, 0, 0, 0.8, 1, "OVERLAY", 7)
        ns.MakePreviewBackdrop(strip, cfg.theme)
        if cfg.enabled == false then strip:SetAlpha(0.45) end
        _edbPreviewHost = strip

        local stripUsable = stripLen - SEDGE * 2
        local blocks = cfg.blocks
        local nBlocks = #blocks

        if nBlocks == 0 then
            local hintFS = EllesmereUI.MakeFont(strip, 11, nil, 1, 1, 1, 0.4)
            hintFS:SetPoint("CENTER", strip, "CENTER", 0, 0)
            hintFS:SetText(L("Click + to add your first block"))
        end

        -- Segment overlays: one invisible button per block, retargeted by
        -- LayoutStrip below (built once per header build). dragIdx is shared
        -- with the reorder machinery below; hover borders are suppressed
        -- while a drag is live (only the insertion line marks placement).
        local dragIdx
        local dragEndTime = 0
        local segBtns, shareFSs = {}, {}
        for i = 1, nBlocks do
            local b = blocks[i]
            local btn = CreateFrame("Button", nil, strip)
            btn:SetFrameLevel(strip:GetFrameLevel() + 5)
            local hb = PP.CreateBorder(btn, EGc.r, EGc.g, EGc.b, 1, 2, "OVERLAY", 7)
            hb:Hide()
            btn._brd = hb
            btn:SetScript("OnEnter", function(s2)
                if dragIdx then return end
                s2._brd:Show()
                -- Hovering a preview segment lights the real bar's block
                -- the same way hovering its Width % setting does.
                _edbSegHoverId = b.id
                if ns.SetBlockEditHighlight then
                    ns.SetBlockEditHighlight(cfg.id, b.id)
                end
            end)
            btn:SetScript("OnLeave", function(s2)
                s2._brd:Hide()
                if _edbSegHoverId == b.id then
                    _edbSegHoverId = nil
                    if ns.SetBlockEditHighlight then
                        ns.SetBlockEditHighlight(nil, nil)
                    end
                end
            end)

            local typeLabel = TYPE_LABEL[b.type]
            if not typeLabel then typeLabel = b.type end
            local nameFS = EllesmereUI.MakeFont(btn, 10, nil, 1, 1, 1, 0.85)
            nameFS:SetPoint("LEFT", btn, "LEFT", 2, 6)
            nameFS:SetPoint("RIGHT", btn, "RIGHT", -2, 6)
            nameFS:SetJustifyH("CENTER")
            nameFS:SetWordWrap(false)
            nameFS:SetMaxLines(1)
            nameFS:SetText(L(typeLabel))

            local shareFS = EllesmereUI.MakeFont(btn, 9, nil, 1, 1, 1, 0.5)
            shareFS:SetPoint("LEFT", btn, "LEFT", 2, -7)
            shareFS:SetPoint("RIGHT", btn, "RIGHT", -2, -7)
            shareFS:SetJustifyH("CENTER")
            shareFS:SetWordWrap(false)
            shareFS:SetMaxLines(1)

            -- Settings-section hover wash (driven by the body watcher).
            local ehl = btn:CreateTexture(nil, "OVERLAY", nil, 5)
            ehl:SetAllPoints()
            ehl:SetColorTexture(1, 1, 1, 0.08)
            ehl:Hide()
            btn._editHL = ehl

            segBtns[i] = btn
            shareFSs[i] = shareFS
        end

        -- Hovering a block's settings section washes its preview segment.
        _edbSegHighlightFn = function(hlBlockId)
            for k = 1, nBlocks do
                local sb = segBtns[k]
                if sb and sb._editHL then
                    sb._editHL:SetShown(hlBlockId ~= nil and blocks[k].id == hlBlockId)
                end
            end
        end

        -- Boundary visuals: a draggable 8px hit strip between adjacent %
        -- segments (accent line on hover), a static 1px line otherwise.
        local function IsPctBlock(bc)
            -- Per-block % sizing is GONE (bar-level Auto Sized / Even Split
            -- modes own all widths now): no boundary is drag-resizable, so
            -- the divider machinery below stays dormant (static lines only).
            return false
        end
        local dividers, lines = {}, {}
        for i = 1, nBlocks - 1 do
            if IsPctBlock(blocks[i]) and IsPctBlock(blocks[i + 1]) then
                local div = CreateFrame("Button", nil, strip)
                div:SetFrameLevel(strip:GetFrameLevel() + 8)
                if vertical then div:SetSize(stripThick, 8) else div:SetSize(8, stripThick) end
                local line = div:CreateTexture(nil, "OVERLAY", nil, 2)
                line:SetColorTexture(1, 1, 1, 0.15)
                local ar, ag, ab2 = ns.GetAccent()
                local accent = div:CreateTexture(nil, "OVERLAY", nil, 3)
                accent:SetColorTexture(ar, ag, ab2, 0.9)
                accent:Hide()
                if vertical then
                    line:SetPoint("LEFT", div, "LEFT", 0, 0)
                    line:SetPoint("RIGHT", div, "RIGHT", 0, 0)
                    line:SetHeight(1)
                    accent:SetPoint("LEFT", div, "LEFT", 0, 0)
                    accent:SetPoint("RIGHT", div, "RIGHT", 0, 0)
                    accent:SetHeight(2)
                else
                    line:SetPoint("TOP", div, "TOP", 0, 0)
                    line:SetPoint("BOTTOM", div, "BOTTOM", 0, 0)
                    line:SetWidth(1)
                    accent:SetPoint("TOP", div, "TOP", 0, 0)
                    accent:SetPoint("BOTTOM", div, "BOTTOM", 0, 0)
                    accent:SetWidth(2)
                end
                div._accent = accent
                div:SetScript("OnEnter", function(s2) s2._accent:Show() end)
                div:SetScript("OnLeave", function(s2)
                    if not _dividerDragging then s2._accent:Hide() end
                end)
                dividers[i] = div
            else
                local line = strip:CreateTexture(nil, "OVERLAY", nil, 2)
                line:SetColorTexture(1, 1, 1, 0.12)
                if vertical then line:SetHeight(1) else line:SetWidth(1) end
                lines[i] = line
            end
        end

        -- Solve + position everything. Also called by the body's Width %
        -- and Length sliders for live feedback (no header rebuild).
        local lastSegs
        local function LayoutStrip()
            local barUsable = ResolvedBarLength(cfg) - 2 * ns.EDGE_PAD
            if barUsable < 1 then barUsable = 1 end
            local scale = stripUsable / barUsable
            local function measure(bc)
                local w = ns.GetLiveAutoLength(cfg.id, bc.id)
                if not w or w <= 0 then w = EST_LEN[bc.type] or 80 end
                return w
            end
            -- Solve in REAL bar px (Auto Sized extents and gaps are real
            -- pixels), then map each segment's own edges into strip px.
            -- Segments may be NON-contiguous (a Force Centered block leaves
            -- pads beside it); touching neighbors still telescope because
            -- they share the same real edge. _touch marks real seams --
            -- boundary lines draw only there.
            local segs = ns.SolveLayout(cfg, barUsable, measure)
            for i = 1, #segs do
                local seg = segs[i]
                local rAt = seg.at or 0
                local a = floor(rAt * scale + 0.5)
                local e = floor((rAt + seg.px) * scale + 0.5)
                local nxt = segs[i + 1]
                if nxt then
                    local d = (nxt.at or 0) - (rAt + seg.px)
                    seg._touch = d > -0.75 and d < 0.75
                else
                    seg._touch = false
                end
                seg.pos = SEDGE + a
                seg.px = e - a
            end
            lastSegs = segs
            for i = 1, #segs do
                local seg = segs[i]
                local px = seg.px
                if px < 1 then px = 1 end
                local cursor = seg.pos
                local btn = segBtns[i]
                if btn then
                    btn:ClearAllPoints()
                    if vertical then
                        btn:SetSize(stripThick, px)
                        btn:SetPoint("TOP", strip, "TOP", 0, -cursor)
                    else
                        btn:SetSize(px, stripThick)
                        btn:SetPoint("LEFT", strip, "LEFT", cursor, 0)
                    end
                    -- Base position for the drag-reorder nudge animation.
                    btn._basePos = cursor
                    btn._curOff = 0
                    btn._tgtOff = 0
                    if seg.isFill then
                        shareFSs[i]:SetText(L("fill"))
                    else
                        shareFSs[i]:SetText(format("%.1f%%", ns.NormalizedShare(cfg, seg.block.id)))
                    end
                end
                cursor = cursor + px
                local div = dividers[i]
                if div then
                    div:ClearAllPoints()
                    if vertical then
                        div:SetPoint("TOP", strip, "TOP", 0, -(cursor - 4))
                    else
                        div:SetPoint("LEFT", strip, "LEFT", cursor - 4, 0)
                    end
                end
                local lineTex = lines[i]
                if lineTex then
                    lineTex:SetShown(seg._touch and true or false)
                    lineTex:ClearAllPoints()
                    if vertical then
                        lineTex:SetPoint("LEFT", strip, "TOPLEFT", 0, -cursor)
                        lineTex:SetPoint("RIGHT", strip, "TOPRIGHT", 0, -cursor)
                    else
                        lineTex:SetPoint("TOP", strip, "TOPLEFT", cursor, 0)
                        lineTex:SetPoint("BOTTOM", strip, "BOTTOMLEFT", cursor, 0)
                    end
                end
            end
        end
        _edbStripRelayout = LayoutStrip
        LayoutStrip()

        -- Divider drag: zero-sum weight transfer between the two neighbors.
        -- All geometry is FROZEN at drag start (BeginDrag freeze technique);
        -- only the two segment frames and their readouts update per tick.
        for boundaryIdx, div in pairs(dividers) do
            local idx = boundaryIdx
            div:SetScript("OnMouseDown", function(divSelf)
                if _dividerDragging then return end
                if not lastSegs then return end
                local segA = lastSegs[idx]
                local segB = lastSegs[idx + 1]
                if not segA or not segB then return end
                if segA.isAuto or segB.isAuto then return end
                local blkA, blkB = segA.block, segB.block

                local drag = {}
                drag.scale = strip:GetEffectiveScale()
                if not drag.scale or drag.scale == 0 then drag.scale = 1 end
                local cx, cy = GetCursorPosition()
                if vertical then drag.start = cy else drag.start = cx end
                drag.wA = blkA.widthPct or 10
                drag.wB = blkB.widthPct or 10
                drag.budget = drag.wA + drag.wB
                -- Shares are absolute % of the total bar, so one percentage
                -- point is exactly 1% of the strip's usable length.
                drag.pxPerW = stripUsable / 100
                drag.aPos = segA.pos
                drag.liveA = drag.wA

                _dividerDragging = true
                divSelf._accent:Show()
                local btnA, btnB = segBtns[idx], segBtns[idx + 1]
                local fsA, fsB = shareFSs[idx], shareFSs[idx + 1]

                local function ApplyLive(aW)
                    local pxA = aW * drag.pxPerW
                    local pxB = (drag.budget - aW) * drag.pxPerW
                    if pxA < 1 then pxA = 1 end
                    if pxB < 1 then pxB = 1 end
                    btnA:ClearAllPoints()
                    btnB:ClearAllPoints()
                    divSelf:ClearAllPoints()
                    if vertical then
                        btnA:SetSize(stripThick, pxA)
                        btnA:SetPoint("TOP", strip, "TOP", 0, -drag.aPos)
                        btnB:SetSize(stripThick, pxB)
                        btnB:SetPoint("TOP", strip, "TOP", 0, -(drag.aPos + pxA))
                        divSelf:SetPoint("TOP", strip, "TOP", 0, -(drag.aPos + pxA - 4))
                    else
                        btnA:SetSize(pxA, stripThick)
                        btnA:SetPoint("LEFT", strip, "LEFT", drag.aPos, 0)
                        btnB:SetSize(pxB, stripThick)
                        btnB:SetPoint("LEFT", strip, "LEFT", drag.aPos + pxA, 0)
                        divSelf:SetPoint("LEFT", strip, "LEFT", drag.aPos + pxA - 4, 0)
                    end
                    fsA:SetText(format("%.1f%%", aW))
                    fsB:SetText(format("%.1f%%", drag.budget - aW))
                end

                local function Commit()
                    divSelf:SetScript("OnUpdate", nil)
                    _dividerDragging = false
                    if not divSelf:IsMouseOver() then divSelf._accent:Hide() end
                    -- Snap to 0.5 steps; B = budget - A keeps the pair exact.
                    local a = drag.liveA
                    a = floor(a / 0.5 + 0.5) * 0.5
                    local minW = 0.5
                    if a < minW then a = minW end
                    if a > drag.budget - minW then a = drag.budget - minW end
                    if a < 0 then a = 0 end
                    ns.TransferPct(cfg.id, blkA.id, blkB.id, a)
                    LayoutStrip()
                    EllesmereUI:RefreshPage()
                end

                divSelf:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") then
                        Commit()
                        return
                    end
                    local x, y = GetCursorPosition()
                    local d
                    if vertical then d = y - drag.start else d = x - drag.start end
                    d = d / drag.scale
                    -- Dragging DOWN grows the top segment on vertical bars.
                    if vertical then d = -d end
                    local dW = d / drag.pxPerW
                    local minW = 0.5
                    local a = drag.wA + dW
                    if a < minW then a = minW end
                    if a > drag.budget - minW then a = drag.budget - minW end
                    if a ~= drag.liveA then
                        drag.liveA = a
                        ApplyLive(a)
                    end
                end)
            end)
        end

        -----------------------------------------------------------------------
        -- Drag-to-reorder segments (CDM preview pattern): while dragging, the
        -- other segments ease apart around the hovered boundary via a small
        -- animated nudge and an accent insertion line marks the drop point;
        -- release commits the move.
        -----------------------------------------------------------------------
        local reorderLine = strip:CreateTexture(nil, "OVERLAY", nil, 7)
        do
            local ar2, ag2, ab3 = ns.GetAccent()
            reorderLine:SetColorTexture(ar2, ag2, ab3, 0.9)
        end
        if vertical then reorderLine:SetSize(stripThick, 2) else reorderLine:SetSize(2, stripThick) end
        reorderLine:Hide()

        local NUDGE = 6
        local animTicker
        local function EnsureAnimTicker()
            if animTicker then return end
            animTicker = C_Timer.NewTicker(0.016, function()
                local moving = false
                for k = 1, #segBtns do
                    local sb = segBtns[k]
                    local cur = sb._curOff or 0
                    local tgt = sb._tgtOff or 0
                    if math.abs(cur - tgt) > 0.4 then
                        cur = cur + (tgt - cur) * 0.35
                        moving = true
                    else
                        cur = tgt
                    end
                    sb._curOff = cur
                    if sb._basePos then
                        sb:ClearAllPoints()
                        if vertical then
                            sb:SetPoint("TOP", strip, "TOP", 0, -(sb._basePos + cur))
                        else
                            sb:SetPoint("LEFT", strip, "LEFT", sb._basePos + cur, 0)
                        end
                    end
                end
                if not moving and not dragIdx then
                    animTicker:Cancel()
                    animTicker = nil
                end
            end)
        end

        local function CursorStripPos()
            local cx, cy = GetCursorPosition()
            local es = strip:GetEffectiveScale()
            if not es or es == 0 then es = 1 end
            if vertical then
                return (strip:GetTop() or 0) - cy / es
            end
            return cx / es - (strip:GetLeft() or 0)
        end

        local function ComputeInsertIdx()
            if not lastSegs then return nil end
            local pos = CursorStripPos()
            local n = #lastSegs
            for k = 1, n do
                local s2 = lastSegs[k]
                if pos < (s2.pos or 0) + (s2.px or 0) / 2 then return k end
            end
            return n + 1
        end

        local function UpdateDragVisuals()
            if not dragIdx or not lastSegs then return end
            local targetIdx = ComputeInsertIdx()
            -- Boundaries adjoining the dragged segment are a no-op drop.
            local noop = (targetIdx == dragIdx or targetIdx == dragIdx + 1)
            for k = 1, #segBtns do
                if k == dragIdx or noop then
                    segBtns[k]._tgtOff = 0
                else
                    -- Virtual-position rule (CDM): with the dragged segment
                    -- removed from the indexing, everything at/after the
                    -- insertion point eases toward the end, everything
                    -- before it eases back toward the start.
                    local vPos = k
                    if k > dragIdx then vPos = k - 1 end
                    local vIns = targetIdx
                    if targetIdx > dragIdx then vIns = targetIdx - 1 end
                    if vPos >= vIns then
                        segBtns[k]._tgtOff = NUDGE
                    else
                        segBtns[k]._tgtOff = -NUDGE
                    end
                end
            end
            EnsureAnimTicker()
            if noop then
                reorderLine:Hide()
                return
            end
            local n = #lastSegs
            local linePos
            if targetIdx <= n then
                linePos = lastSegs[targetIdx].pos or SEDGE
            else
                local lastSeg = lastSegs[n]
                linePos = (lastSeg.pos or SEDGE) + (lastSeg.px or 0)
            end
            reorderLine:ClearAllPoints()
            if vertical then
                reorderLine:SetPoint("TOP", strip, "TOP", 0, -(linePos - 1))
            else
                reorderLine:SetPoint("LEFT", strip, "LEFT", linePos - 1, 0)
            end
            reorderLine:Show()
        end

        -- Pickup ghost: a floating half-scale copy of the segment that rides
        -- the cursor while dragging (CDM preview pattern); the segment itself
        -- stays in place dimmed to 0.3.
        local dragGhost
        local function EnsureDragGhost()
            if dragGhost then return dragGhost end
            dragGhost = CreateFrame("Frame", nil, UIParent)
            dragGhost:SetFrameStrata("TOOLTIP")
            dragGhost:SetFrameLevel(500)
            local gBg = dragGhost:CreateTexture(nil, "BACKGROUND")
            gBg:SetAllPoints()
            gBg:SetColorTexture(0.10, 0.12, 0.14, 0.95)
            local ar2, ag2, ab3 = ns.GetAccent()
            EllesmereUI.MakeBorder(dragGhost, ar2, ag2, ab3, 0.9, PP)
            local gl = EllesmereUI.MakeFont(dragGhost, 10, nil, 1, 1, 1, 0.9)
            gl:SetPoint("CENTER")
            dragGhost._lbl = gl
            dragGhost:Hide()
            return dragGhost
        end

        local function FinishDrag()
            strip:SetScript("OnUpdate", nil)
            local from = dragIdx
            dragIdx = nil
            dragEndTime = GetTime()
            if dragGhost then dragGhost:Hide() end
            reorderLine:Hide()
            if from and segBtns[from] then segBtns[from]:SetAlpha(1) end
            for k = 1, #segBtns do segBtns[k]._tgtOff = 0 end
            local targetIdx = ComputeInsertIdx()
            if not (from and targetIdx) then return end
            if targetIdx == from or targetIdx == from + 1 then return end
            ns.MoveBlockTo(cfg.id, blocks[from].id, targetIdx)
            -- Full refresh: the preview strip lives in the content header,
            -- which a plain RefreshPage never rebuilds.
            HardRefresh()
        end

        local function BeginDrag(fromIdx)
            dragIdx = fromIdx
            local sb = segBtns[fromIdx]
            if sb._brd then sb._brd:Hide() end
            sb:SetAlpha(0.3)
            local ghost = EnsureDragGhost()
            local gw, gh = sb:GetSize()
            if not gw or gw < 24 then gw = 24 end
            if not gh or gh < 12 then gh = stripThick end
            ghost:SetSize(gw, gh)
            local tl = TYPE_LABEL[blocks[fromIdx].type] or blocks[fromIdx].type
            ghost._lbl:SetText(L(tl))
            ghost:SetScale(0.5)
            ghost:Show()
            EnsureAnimTicker()
            -- Cursor follow + release detection (mouse-up can land anywhere).
            strip:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then
                    FinishDrag()
                    return
                end
                local cx, cy = GetCursorPosition()
                local sc = UIParent:GetEffectiveScale()
                cx, cy = cx / sc, cy / sc
                local gs = dragGhost:GetScale() or 1
                dragGhost:ClearAllPoints()
                dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / gs, cy / gs)
                UpdateDragVisuals()
            end)
        end

        -- Right-click context menu on a segment: block actions only
        -- (bar deletion = the selector dropdown's inline delete).
        local segMenu
        local function ShowSegmentMenu(anchorBtn, blockId)
            if segMenu and segMenu:IsShown() then segMenu:Hide() end
            segMenu = nil
            local ROW_H2 = 24
            local menu = CreateFrame("Frame", nil, UIParent)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            menu:SetWidth(150)
            menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
            local bg = menu:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_HA)
            EllesmereUI.MakeBorder(menu, 1, 1, 1, DDS.BRD_A, PP)
            local rowY = -3
            local function AddRow(text, onClick)
                local row = CreateFrame("Button", nil, menu)
                row:SetHeight(ROW_H2)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, rowY)
                row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, rowY)
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)
                local lbl = EllesmereUI.MakeFont(row, 11, nil, 1, 1, 1, 0.9)
                lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
                lbl:SetText(text)
                row:SetScript("OnClick", function()
                    menu:Hide()
                    segMenu = nil
                    onClick()
                end)
                rowY = rowY - ROW_H2
            end
            AddRow(L("Remove Block"), function()
                ns.RemoveBlock(cfg.id, blockId)
                -- Full refresh: the preview strip lives in the content
                -- header, which a plain RefreshPage never rebuilds.
                HardRefresh()
                -- The page just lost a whole section; a bottom-scrolled view
                -- would be left staring at blank space.
                if EllesmereUI.SmoothScrollTo then EllesmereUI.SmoothScrollTo(0) end
            end)
            menu:SetHeight(-rowY + 3)
            -- Click-away dismiss. The opening right-button is STILL DOWN on
            -- the first frames (the menu opens on RightButtonDown) -- without
            -- the guard the menu dismissed itself instantly.
            menu._openGuard = true
            menu:SetScript("OnUpdate", function(m)
                if m._openGuard then
                    if not IsMouseButtonDown("RightButton") then m._openGuard = nil end
                    return
                end
                if not m:IsMouseOver()
                   and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                    m:Hide()
                    segMenu = nil
                end
            end)
            segMenu = menu
        end

        -- Manual 3px drag threshold (CDM preview pattern -- WoW's native
        -- drag threshold is too coarse for small segments). Left press arms
        -- the pending tracker; movement starts the drag; right-click opens
        -- the context menu. dragEndTime guards the release-click.
        local DRAG_THRESHOLD = 3
        for i = 1, nBlocks do
            local segBtn = segBtns[i]
            local segBlockId = blocks[i].id
            segBtn:RegisterForClicks("LeftButtonUp", "RightButtonDown")
            segBtn:SetScript("OnClick", function(sb, mbtn)
                -- The dragEndTime guard swallows the release-click of a
                -- drag; a press that never crossed the 3px threshold is a
                -- TRUE click (drag starts never fire OnClick at all).
                if GetTime() - dragEndTime < 0.2 then return end
                if mbtn == "RightButton" then
                    ShowSegmentMenu(sb, segBlockId)
                elseif mbtn == "LeftButton" then
                    if _edbNavigateFn then _edbNavigateFn("block:" .. segBlockId) end
                end
            end)
            segBtn:SetScript("OnMouseDown", function(sb, mbtn)
                if mbtn ~= "LeftButton" then return end
                if _dividerDragging or dragIdx then return end
                local cx, cy = GetCursorPosition()
                sb._pendX, sb._pendY = cx, cy
                sb:SetScript("OnUpdate", function(s3)
                    if not IsMouseButtonDown("LeftButton") then
                        s3:SetScript("OnUpdate", nil)
                        s3._pendX, s3._pendY = nil, nil
                        return
                    end
                    local nx, nyy = GetCursorPosition()
                    if math.abs(nx - (s3._pendX or nx)) > DRAG_THRESHOLD
                       or math.abs(nyy - (s3._pendY or nyy)) > DRAG_THRESHOLD then
                        s3:SetScript("OnUpdate", nil)
                        s3._pendX, s3._pendY = nil, nil
                        BeginDrag(i)
                    end
                end)
            end)
        end

        -- "+" add-block tile (CDM preview add-button look): bar-height
        -- square, 4px off the strip, dark fill, colored "+" glyph that
        -- lights up with an accent border on hover.
        local addBtn = CreateFrame("Button", nil, stripParent)
        PP.Size(addBtn, stripThick, stripThick)
        if vertical then
            PP.Point(addBtn, "TOP", strip, "BOTTOM", 0, -4)
        else
            PP.Point(addBtn, "LEFT", strip, "RIGHT", 4, 0)
        end
        addBtn:SetFrameLevel(strip:GetFrameLevel() + 2)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if addBg.SetSnapToPixelGrid then addBg:SetSnapToPixelGrid(false); addBg:SetTexelSnappingBias(0) end
        PP.CreateBorder(addBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7)
        local addLbl = EllesmereUI.MakeFont(addBtn, 22, nil, EGc.r, EGc.g, EGc.b, 0.7)
        addLbl:SetPoint("CENTER", 0, 1)
        addLbl:SetText("+")
        local addHlCont = CreateFrame("Frame", nil, addBtn)
        addHlCont:SetAllPoints()
        addHlCont:SetFrameLevel(addBtn:GetFrameLevel() + 1)
        local addBrd = PP.CreateBorder(addHlCont, EGc.r, EGc.g, EGc.b, 1, 2, "OVERLAY", 7)
        addBrd:Hide()

        local addMenu
        local function ToggleAddMenu()
            if addMenu and addMenu:IsShown() then
                addMenu:Hide()
                addMenu = nil
                return
            end
            local menu = CreateFrame("Frame", nil, UIParent)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            menu:SetWidth(190)
            menu:SetPoint("TOPRIGHT", addBtn, "BOTTOMRIGHT", 0, -2)
            local bg = menu:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_HA)
            EllesmereUI.MakeBorder(menu, 1, 1, 1, DDS.BRD_A, PP)
            local ITEM_H = 24
            local hlA = DDS.ITEM_HL_A
            local mH = 4
            for _, t in ipairs(ns.BLOCK_TYPES) do
                local item = CreateFrame("Button", nil, menu)
                item:SetHeight(ITEM_H)
                item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                item:SetFrameLevel(menu:GetFrameLevel() + 2)
                -- Types already on this bar render dimmed -- still fully
                -- clickable (duplicates are legal), just an at-a-glance cue
                -- for what the bar is missing. The menu rebuilds per open,
                -- so this never goes stale.
                local onBar = false
                for bi = 1, #cfg.blocks do
                    if cfg.blocks[bi].type == t.key then onBar = true break end
                end
                local baseA = tDimA
                local hoverA = 1
                if onBar then baseA = 0.28; hoverA = 0.55 end
                local iLbl = EllesmereUI.MakeFont(item, 11, nil, tDimR, tDimG, tDimB, baseA)
                iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                iLbl:SetJustifyH("LEFT")
                iLbl:SetText(L(t.label))
                local iHl = item:CreateTexture(nil, "ARTWORK")
                iHl:SetAllPoints()
                iHl:SetColorTexture(1, 1, 1, 1)
                iHl:SetAlpha(0)
                item:SetScript("OnEnter", function()
                    iLbl:SetTextColor(1, 1, 1, hoverA)
                    iHl:SetAlpha(hlA)
                end)
                item:SetScript("OnLeave", function()
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, baseA)
                    iHl:SetAlpha(0)
                end)
                local typeKey = t.key
                item:SetScript("OnClick", function()
                    menu:Hide()
                    local nb = ns.AddBlock(cfg.id, typeKey)
                    HardRefresh()
                    if nb then
                        local navKey = "block:" .. nb.id
                        C_Timer.After(0.05, function()
                            if _edbNavigateFn then _edbNavigateFn(navKey) end
                        end)
                    end
                end)
                mH = mH + ITEM_H
            end
            menu:SetHeight(mH + 4)
            menu:SetScript("OnUpdate", function(m)
                if not m:IsMouseOver() and not addBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
            menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
            menu:Show()
            addMenu = menu
        end
        addBtn:SetScript("OnClick", ToggleAddMenu)
        addBtn:SetScript("OnEnter", function()
            addLbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
            addBrd:Show()
            EllesmereUI.ShowWidgetTooltip(addBtn, L("Add a block to this bar"))
        end)
        addBtn:SetScript("OnLeave", function()
            addLbl:SetTextColor(EGc.r, EGc.g, EGc.b, 0.7)
            addBrd:Hide()
            EllesmereUI.HideWidgetTooltip()
        end)
        addBtn:HookScript("OnHide", function() if addMenu then addMenu:Hide() end end)

        if vertical then
            -- The strip lives in the docked popout; the header only carries
            -- a pointer to it.
            local vh = EllesmereUI.MakeFont(hdr, 12, nil, 1, 1, 1, 0.4)
            vh:SetPoint("TOPLEFT", hdr, "TOPLEFT", PAD + 4, fy - 2)
            vh:SetText(L("Vertical bar: the interactive preview is docked beside this window."))
            fy = fy - 24
        else
            fy = fy - stripThick - 8
            -- Interaction hint directly below the preview (CDM preview pattern).
            local ph = EllesmereUI.MakeFont(hdr, 11, nil, 0.62, 0.62, 0.62, 0.9)
            ph:SetPoint("TOP", strip, "BOTTOM", 0, -8)
            ph:SetWidth(stripLen - 20)
            ph:SetJustifyH("CENTER")
            ph:SetWordWrap(true)
            ph:SetText(L("Drag to Reorder. Click to Scroll. Right Click to Remove."))
            fy = fy - 16 - 10
        end

        return math.abs(fy)
    end

    ---------------------------------------------------------------------------
    --  Page body
    ---------------------------------------------------------------------------
    local function BuildDataBarsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local row

        parent._showRowDivider = true
        parent._edbClickTargets = {}

        -------------------------------------------------------------------
        --  Click navigation (preview segments -> block sections). The map
        --  lives on parent._edbClickTargets; the header overlays call the
        --  current build's closure through the _edbNavigateFn upvalue so a
        --  cached/restored header never fires a stale closure.
        -------------------------------------------------------------------
        local _navGlowFrame
        local function PlaySettingGlow(targetFrame)
            if not targetFrame then return end
            if not _navGlowFrame then
                _navGlowFrame = CreateFrame("Frame")
                local c = EllesmereUI.ELLESMERE_GREEN
                local function MkEdge()
                    local t = _navGlowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(c.r, c.g, c.b, 1)
                    return t
                end
                local top, bot, lft, rgt = MkEdge(), MkEdge(), MkEdge(), MkEdge()
                top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
                bot:SetHeight(2); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
                lft:SetWidth(2)
                lft:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bot, "TOPLEFT")
                rgt:SetWidth(2)
                rgt:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
            end
            _navGlowFrame:SetParent(targetFrame)
            _navGlowFrame:SetAllPoints(targetFrame)
            _navGlowFrame:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
            _navGlowFrame:SetAlpha(1)
            _navGlowFrame:Show()
            local elapsed = 0
            _navGlowFrame:SetScript("OnUpdate", function(glowSelf, dt)
                elapsed = elapsed + dt
                if elapsed >= 0.75 then
                    glowSelf:Hide()
                    glowSelf:SetScript("OnUpdate", nil)
                    return
                end
                glowSelf:SetAlpha(1 - elapsed / 0.75)
            end)
        end

        local function NavigateToSetting(key)
            local targets = parent._edbClickTargets
            if not targets then return end
            local m = targets[key]
            if not m or not m.section or not m.target then return end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then return end
            EllesmereUI.SmoothScrollTo(math.max(0, math.abs(headerY) - 40))
            local glowTarget = m.target
            if m.slotSide then
                local region
                if m.slotSide == "left" then region = m.target._leftRegion else region = m.target._rightRegion end
                if region then glowTarget = region end
            end
            C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
        end
        -- Never retarget the live header's click handler from a hidden
        -- global-search pre-build: its targets belong to an off-screen
        -- wrapper. (SetContentHeader itself is stubbed out during pre-builds
        -- by the search module, so that call needs no guard.)
        if not EllesmereUI._prebuilding then
            _edbNavigateFn = NavigateToSetting
        end

        local p = Profile()
        if not p then return math.abs(y) end
        local cfg = SelectedBar()

        -- Bar selected -> editor chrome; zero bars -> no header, the body
        -- below renders the full starting screen.
        if cfg then
            EllesmereUI:SetContentHeader(_edbHeaderBuilder)
        else
            EllesmereUI:ClearContentHeader()
        end

        -------------------------------------------------------------------
        --  Zero bars: template-card empty state
        -------------------------------------------------------------------
        if not cfg then
            local PADC = EllesmereUI.CONTENT_PAD
            if not PADC then PADC = 10 end
            local hostW = parent:GetWidth() - PADC * 2
            local gap = 12
            local cw = floor((hostW - gap) / 2)
            local ch = 76
            local hostH = 40 + ch * 2 + gap + 10
            -- Explicit size + single TOPLEFT anchor (search contract); the
            -- host doubles as a search pseudo-section.
            local host = CreateFrame("Frame", nil, parent)
            PP.Size(host, hostW, hostH)
            PP.Point(host, "TOPLEFT", parent, "TOPLEFT", PADC, y)
            host._isSectionHeader = true
            host._sectionName = "Create New DataBar"
            local hint = EllesmereUI.MakeFont(host, 13, nil, 1, 1, 1, 0.55)
            hint:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -8)
            hint:SetText(L("Create your first DataBar from a starter template, or start empty."))
            for i = 1, 4 do
                local col = (i - 1) % 2
                local rowI = floor((i - 1) / 2)
                MakeTemplateCard(host, col * (cw + gap), -40 - rowI * (ch + gap), cw, ch, TEMPLATE_CARDS[i])
            end
            y = y - hostH - 10
            return math.abs(y)
        end

        local barId = cfg.id
        local vertical = cfg.orientation == "V"
        local theme = cfg.theme
        if not theme then
            theme = { style = "eui", euiAlpha = 0.5, modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 } }
            cfg.theme = theme
        end

        local function Apply()
            ns.ApplyBar(barId)
        end

        -- Standard inline cog button (house pattern): sits left of the row's
        -- control, opens a BuildCogPopup with extra rows.
        local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
            local anchor = anchorTo or (rgn and (rgn._lastInline or rgn._control)) or rgn
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(iconPath or EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) showFn(self) end)
            if rgn then rgn._lastInline = cogBtn end
            return cogBtn
        end

        -- Sizing mode: centered segmented two-button toggle (same recipe as
        -- the Buff Manager's Simple/Custom switch), in its OWN space between
        -- the preview header and BAR SETTINGS with 15px above and below.
        -- BAR-level -- it owns every block's width: Auto Sized = content +
        -- per-side gaps with one Fill Remaining block; Even Split = equal
        -- segments. Switching rebuilds the page (block sections gain/lose
        -- their sizing rows).
        y = y - 15
        do
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local BTN_W, BTN_H = 150, 26
            local wrap = CreateFrame("Frame", nil, parent)
            wrap:SetSize(BTN_W * 2, BTN_H)
            wrap:SetPoint("TOP", parent, "TOP", 0, y)
            PP.CreateBorder(wrap, 1, 1, 1, 0.10, 1)
            local curMode = ns.BarSizingMode(cfg)
            local MODES = {
                { key = "auto", label = "Auto Sized" },
                { key = "even", label = "Even Split" },
            }
            for mi, m in ipairs(MODES) do
                local btn = CreateFrame("Button", nil, wrap)
                btn:SetSize(BTN_W, BTN_H)
                btn:SetPoint("LEFT", wrap, "LEFT", (mi - 1) * BTN_W, 0)
                local bg = btn:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1, 1)
                lbl:SetPoint("CENTER")
                lbl:SetText(L(m.label))
                if curMode == m.key then
                    bg:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                else
                    bg:SetColorTexture(0.10, 0.10, 0.11, 0.85)
                    lbl:SetTextColor(1, 1, 1, 0.55)
                    btn:SetScript("OnEnter", function()
                        bg:SetColorTexture(0.16, 0.16, 0.17, 0.9)
                        lbl:SetTextColor(1, 1, 1, 0.85)
                    end)
                    btn:SetScript("OnLeave", function()
                        bg:SetColorTexture(0.10, 0.10, 0.11, 0.85)
                        lbl:SetTextColor(1, 1, 1, 0.55)
                    end)
                    btn:SetScript("OnClick", function()
                        cfg.sizingMode = m.key
                        ns.ApplyBar(barId)
                        HardRefresh()
                    end)
                end
            end
            y = y - (BTN_H + 15)
        end

        -------------------------------------------------------------------
        --  BAR SETTINGS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "BAR SETTINGS", y);  y = y - h

        -- Visibility | Visibility Options (renaming lives in the selector's
        -- inline edit; "Never" visibility fully disables the bar's work).
        local visRow
        visRow, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = function() return ns.GetBar(barId) end,
              legacyKey = "visibility",
              caps = ns.EDB_VIS_CAPS,
              onChanged = function()
                  -- "Never" tears the bar down entirely (and un-Never
                  -- rebuilds), so run the full apply, not just the vis pass.
                  ns.ApplyBar(barId)
                  ns.UpdateAllBarVisibility()
              end },
            { type = "dropdown", text = "Visibility Options",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end });  y = y - h
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                EllesmereUI.VIS_OPT_ITEMS,
                function(k)
                    local c = ns.GetBar(barId)
                    if c and c[k] then return true end
                    return false
                end,
                function(k, v)
                    local c = ns.GetBar(barId)
                    if not c then return end
                    c[k] = v
                    ns.UpdateAllBarVisibility()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Orientation | Theme (inline cog = EllesmereUI Backdrop Dim)
        local themeRow
        themeRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Orientation",
              tooltip = "Horizontal bars lay blocks left to right; vertical bars stack them top to bottom.",
              values = { H = "Horizontal", V = "Vertical" }, order = { "H", "V" },
              getValue = function()
                  if cfg.orientation == "V" then return "V" end
                  return "H"
              end,
              setValue = function(v)
                  cfg.orientation = v
                  -- An edge snap that no longer matches the orientation
                  -- remaps to the nearest valid edge.
                  local e = cfg.snapEdge
                  if v == "V" and (e == "bottom" or e == "top") then
                      cfg.snapEdge = "left"
                  elseif v == "H" and (e == "left" or e == "right") then
                      cfg.snapEdge = "bottom"
                  end
                  ns.ApplyBar(barId)
                  HardRefresh()
              end },
            { type = "dropdown", text = "Background Style",
              tooltip = "EllesmereUI matches the window-skin shell; Modern is a flat color.",
              values = { eui = "EllesmereUI", modern = "Modern" }, order = { "eui", "modern" },
              getValue = function()
                  if theme.style == "modern" then return "modern" end
                  return "eui"
              end,
              setValue = function(v)
                  theme.style = v
                  -- Selecting Modern starts Bar Opacity at 95.
                  if v == "modern" then
                      local c = theme.modernColor
                      if not c then
                          c = { r = 0.067, g = 0.067, b = 0.067 }
                          theme.modernColor = c
                      end
                      c.a = 0.95
                  end
                  ns.ApplyTheme(barId)
                  HardRefresh()
              end });  y = y - h
        do
            local rgn = themeRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "EllesmereUI Background",
                rows = {
                    { type = "slider", label = "Backdrop Dim", min = 0, max = 100, step = 1,
                      get = function()
                          local a = theme.euiAlpha
                          if a == nil then a = 0.5 end
                          return floor(a * 100 + 0.5)
                      end,
                      set = function(v)
                          theme.euiAlpha = v / 100
                          ns.ApplyTheme(barId)
                          RefreshPreviewTheme()
                      end },
                },
            })
            local cog = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.COGS_ICON)
            if theme.style ~= "eui" then
                -- Disabled state (house pattern): dimmed cog + blocking
                -- overlay with the requirement tooltip. Theme changes
                -- HardRefresh, so this re-evaluates on switch.
                cog:SetAlpha(0.15)
                cog:SetScript("OnEnter", nil)
                cog:SetScript("OnLeave", nil)
                cog:SetScript("OnClick", nil)
                local blk = CreateFrame("Frame", nil, cog)
                blk:SetAllPoints()
                blk:SetFrameLevel(cog:GetFrameLevel() + 5)
                blk:EnableMouse(true)
                blk:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(cog, EllesmereUI.DisabledTooltip("the EllesmereUI theme"))
                end)
                blk:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
        end

        local scaleCfg = { type = "slider", text = "Text Scale", min = 50, max = 150, step = 5,
              tooltip = "Scales every text element on this bar.",
              getValue = function()
                  local v = cfg.fontScale
                  if v == nil then v = 100 end
                  return v
              end,
              setValue = function(v)
                  cfg.fontScale = v
                  Apply()
              end }
        -- One bar-wide switch (was a per-block toggle).
        local hoverBlocksCfg = { type = "toggle", text = "Hover Highlight Blocks",
              tooltip = "Shows a faint white wash over each block on mouseover.",
              getValue = function() return cfg.hoverHighlight == true end,
              setValue = function(v)
                  cfg.hoverHighlight = v and true or false
                  Apply()
              end }
        -- Bar Opacity drives BOTH styles: the Modern flat color's alpha or
        -- the EllesmereUI shell's backdrop dim, whichever is active.
        local opacityRow
        opacityRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Bar Opacity", min = 0, max = 100, step = 1,
              tooltip = "Opacity of the bar's background; the swatch picks the Modern color.",
              getValue = function()
                  if theme.style == "modern" then
                      local c = theme.modernColor
                      local a = c and c.a
                      if a == nil then a = 0.95 end
                      return floor(a * 100 + 0.5)
                  end
                  local a = theme.euiOpacity
                  if a == nil then a = 1 end
                  return floor(a * 100 + 0.5)
              end,
              setValue = function(v)
                  if theme.style == "modern" then
                      local c = theme.modernColor
                      if not c then
                          c = { r = 0.067, g = 0.067, b = 0.067 }
                          theme.modernColor = c
                      end
                      c.a = v / 100
                  else
                      theme.euiOpacity = v / 100
                  end
                  ns.ApplyTheme(barId)
                  RefreshPreviewTheme()
              end },
            hoverBlocksCfg);  y = y - h
        do
            -- Inline Modern-background swatch: always present, disabled
            -- (house pattern) while the EllesmereUI style is active. Style
            -- changes HardRefresh, so the state re-evaluates on switch.
            local rgn = opacityRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, opacityRow:GetFrameLevel() + 3,
                function()
                    local c = theme.modernColor
                    if not c then return 0.067, 0.067, 0.067 end
                    local r = c.r; if r == nil then r = 0.067 end
                    local g = c.g; if g == nil then g = 0.067 end
                    local b2 = c.b; if b2 == nil then b2 = 0.067 end
                    return r, g, b2
                end,
                function(r, g, b2)
                    local c = theme.modernColor
                    if not c then c = { a = 0.95 }; theme.modernColor = c end
                    c.r = r; c.g = g; c.b = b2
                    ns.ApplyTheme(barId)
                    RefreshPreviewTheme()
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
            if theme.style ~= "modern" then
                swatch:SetAlpha(0.3)
                local blk = CreateFrame("Frame", nil, swatch)
                blk:SetAllPoints()
                blk:SetFrameLevel(swatch:GetFrameLevel() + 5)
                blk:EnableMouse(true)
                blk:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("the Modern background style"))
                end)
                blk:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
        end

        -- Full Screen Width/Height | Snap to Screen Edge, then Width +
        -- Height together on the next row. The sizing labels are PURELY a
        -- front-end relabel: cfg.length is always the along-axis extent
        -- and cfg.thickness the cross-axis, unchanged -- the labels flip
        -- with orientation so users read screen terms.
        local lenLabel, fullLabel, thickLabel
        if vertical then
            lenLabel, fullLabel, thickLabel = "Height", "Full Screen Height", "Width"
        else
            lenLabel, fullLabel, thickLabel = "Width", "Full Screen Width", "Height"
        end
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = fullLabel,
              tooltip = "Sizes the bar to the full screen extent along its axis.",
              getValue = function() return cfg.lengthMode == "full" end,
              setValue = function(v)
                  if v then cfg.lengthMode = "full" else cfg.lengthMode = "custom" end
                  ns.ApplyBar(barId)
                  if _edbStripRelayout then _edbStripRelayout() end
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Snap to Screen Edge",
              tooltip = "Pins the bar flush against a screen edge; moving the bar in unlock mode sets this back to None.",
              values = { none = "None", bottom = "Bottom", top = "Top", left = "Left", right = "Right" },
              order = { "none", "bottom", "top", "left", "right" },
              itemDisabled = function(v)
                  if vertical then
                      return v == "bottom" or v == "top"
                  end
                  return v == "left" or v == "right"
              end,
              itemDisabledTooltip = function(v)
                  if v == "bottom" or v == "top" then
                      return "Not available for vertical bars"
                  end
                  return "Not available for horizontal bars"
              end,
              getValue = function()
                  local v = cfg.snapEdge
                  if v == nil then v = "none" end
                  return v
              end,
              setValue = function(v)
                  cfg.snapEdge = v
                  ns.ApplyBar(barId)
              end });  y = y - h

        -- Width | Height (length + thickness in screen terms)
        _, h = W:DualRow(parent, y,
            { type = "slider", text = lenLabel, min = 100, max = 3000, step = 10,
              tooltip = "Size of the bar along its block axis in pixels.",
              disabled = function() return cfg.lengthMode == "full" end,
              disabledTooltip = "Disabled while " .. fullLabel .. " is enabled.",
              rawTooltip = true,
              getValue = function()
                  local v = cfg.length
                  if v == nil then v = 400 end
                  return v
              end,
              setValue = function(v)
                  cfg.length = v
                  ns.ApplyBar(barId)
                  if _edbStripRelayout then _edbStripRelayout() end
              end },
            { type = "slider", text = thickLabel, min = 16, max = 80, step = 1,
              tooltip = "Size of the bar across its block axis in pixels.",
              getValue = function()
                  local v = cfg.thickness
                  if v == nil then v = 30 end
                  return v
              end,
              setValue = function(v)
                  cfg.thickness = v
                  Apply()
              end });  y = y - h

        _, h = W:DualRow(parent, y, scaleCfg, { type = "label", text = "" });  y = y - h

        -- Bar deletion lives in the selector dropdown's inline delete -- no
        -- body row. Visibility moved to the top of the section; rename =
        -- selector inline edit.

        -------------------------------------------------------------------
        --  One section per block
        -------------------------------------------------------------------
        local blocks = cfg.blocks
        local blockHoverRegions = {}   -- { id, rgn } Width % control regions
        for i = 1, #blocks do
            local b = blocks[i]
            local blockId = b.id
            local s = b.settings
            if not s then s = {}; b.settings = s end
            local isSpacer = b.type == "spacer"
            local typeLabel = TYPE_LABEL[b.type]
            if not typeLabel then typeLabel = b.type end

            local secHdr
            secHdr, h = W:SectionHeader(parent, string.upper(EllesmereUI.L(typeLabel)), y);  y = y - h

            -- Bar-level sizing owns all widths now (Auto Sized / Even
            -- Split toggle at the top of Bar Settings). Auto mode: every
            -- block except the single Fill Remaining block gets a per-side
            -- gaps row, and every block gets the fill designation toggle.
            -- Even Split: no per-block sizing rows at all.
            local barMode = ns.BarSizingMode(cfg)
            local isFillBlock = barMode == "auto"
                and ns.EnsureFillBlock(cfg) == blockId
            local sizingRow
            if barMode == "auto" and not isFillBlock then
                local gapLLabel, gapRLabel
                if vertical then
                    gapLLabel, gapRLabel = "Top Gap", "Bottom Gap"
                else
                    gapLLabel, gapRLabel = "Left Gap", "Right Gap"
                end
                sizingRow, h = W:DualRow(parent, y,
                    { type = "slider", text = gapLLabel, min = 0, max = 200, step = 1,
                      tooltip = "Empty space reserved on this side of the block's content.",
                      getValue = function()
                          local l = ns.ContentGapsOf(b)
                          return l
                      end,
                      setValue = function(v)
                          b.contentGapL = v
                          Apply()
                          if _edbStripRelayout then _edbStripRelayout() end
                      end },
                    { type = "slider", text = gapRLabel, min = 0, max = 200, step = 1,
                      tooltip = "Empty space reserved on this side of the block's content.",
                      getValue = function()
                          local _, r = ns.ContentGapsOf(b)
                          return r
                      end,
                      setValue = function(v)
                          b.contentGapR = v
                          Apply()
                          if _edbStripRelayout then _edbStripRelayout() end
                      end });  y = y - h
            end
            if barMode == "auto" then
                local fillRow
                fillRow, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Set as 'Fill Remaining Space' Block",
                      tooltip = "Stretches this block to absorb the space the sized blocks leave over; exactly one block per bar fills.",
                      disabled = function()
                          return ns.EnsureFillBlock(cfg) == blockId
                      end,
                      disabledTooltip = "This block is already the 'Fill Remaining Space' block. Check another block to move the role.",
                      rawTooltip = true,
                      getValue = function()
                          return ns.EnsureFillBlock(cfg) == blockId
                      end,
                      setValue = function(v)
                          if v then
                              ns.SetFillBlock(barId, blockId)
                              HardRefresh()
                          end
                      end },
                    { type = "toggle", text = "Force Centered",
                      tooltip = "Pins this block's content to the exact center of the bar; blocks before it pack left, blocks after pack right. Combined with Fill Remaining, the block also absorbs the leftover space around the center.",
                      getValue = function()
                          return cfg.centerBlockId == blockId
                      end,
                      setValue = function(v)
                          if v then
                              ns.SetCenterBlock(barId, blockId)
                          elseif cfg.centerBlockId == blockId then
                              ns.SetCenterBlock(barId, nil)
                          end
                          HardRefresh()
                      end });  y = y - h
                if not sizingRow then sizingRow = fillRow end
            end

            -- The sizing rows drive the hover highlight (auto mode only;
            -- Even Split blocks light up from segment hover alone).
            if sizingRow then
                blockHoverRegions[#blockHoverRegions + 1] = {
                    id = blockId,
                    rgn = sizingRow,
                }
            end

            parent._edbClickTargets["block:" .. blockId] = { section = secHdr, target = sizingRow or secHdr }

            -- Text Align + X/Y offsets (skipped for spacers)
            if not isSpacer then
                local alignValues
                if vertical then
                    alignValues = { LEFT = "Top", CENTER = "Center", RIGHT = "Bottom" }
                else
                    alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
                end
                -- Text Align (X/Y offsets live in the inline cog) | Content
                -- Scale (icons + texts scale together as a group).
                -- Micro menu: alignment is meaningless (the button strip
                -- lays itself out), so its slot hosts an Enable Text toggle
                -- instead -- a view over the existing hideSocialText key
                -- (default enabled). The Text Position cog still moves the
                -- counter texts.
                local alignLeftCfg
                if b.type == "micromenu" then
                    alignLeftCfg = { type = "toggle", text = "Enable Text",
                      tooltip = "Shows the online friend and guild counters.",
                      getValue = function() return s.hideSocialText ~= true end,
                      setValue = function(v)
                          s.hideSocialText = not v
                          Apply()
                      end }
                else
                    alignLeftCfg = { type = "dropdown", text = "Text Align",
                      tooltip = "Where the block's content sits inside its slot.",
                      values = alignValues, order = { "LEFT", "CENTER", "RIGHT" },
                      getValue = function()
                          local a = b.align
                          if a == nil then a = "CENTER" end
                          return a
                      end,
                      setValue = function(v) b.align = v; Apply() end }
                end
                local alignRow
                alignRow, h = W:DualRow(parent, y,
                    alignLeftCfg,
                    { type = "slider", text = "Content Scale", min = 50, max = 200, step = 5,
                      tooltip = "Scales this block's content as a group inside its slot.",
                      getValue = function()
                          local v = b.scale
                          if v == nil then v = 100 end
                          return v
                      end,
                      setValue = function(v)
                          b.scale = v
                          Apply()
                      end });  y = y - h
                do
                    -- Text Position cog: offsets the TEXT only (factories
                    -- inject these into every text anchor; icons stay put).
                    local _, cogShow = EllesmereUI.BuildCogPopup({
                        title = "Text Position",
                        rows = {
                            { type = "slider", label = "X Offset", min = -50, max = 50, step = 1,
                              get = function()
                                  local v = b.textXOff
                                  if v == nil then v = 0 end
                                  return v
                              end,
                              set = function(v)
                                  b.textXOff = v
                                  if ns.ReflowBlocks then ns.ReflowBlocks(barId) end
                              end },
                            { type = "slider", label = "Y Offset", min = -50, max = 50, step = 1,
                              get = function()
                                  local v = b.textYOff
                                  if v == nil then v = 0 end
                                  return v
                              end,
                              set = function(v)
                                  b.textYOff = v
                                  if ns.ReflowBlocks then ns.ReflowBlocks(barId) end
                              end },
                        },
                    })
                    MakeCogBtn(alignRow._leftRegion, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)

                    -- Content Position cog (next to Content Scale): offsets
                    -- the WHOLE block content group, text included.
                    local _, cogShowAll = EllesmereUI.BuildCogPopup({
                        title = "Content Position",
                        rows = {
                            { type = "slider", label = "X Offset", min = -50, max = 50, step = 1,
                              get = function()
                                  local v = b.xOff
                                  if v == nil then v = 0 end
                                  return v
                              end,
                              set = function(v) b.xOff = v; Apply() end },
                            { type = "slider", label = "Y Offset", min = -50, max = 50, step = 1,
                              get = function()
                                  local v = b.yOff
                                  if v == nil then v = 0 end
                                  return v
                              end,
                              set = function(v) b.yOff = v; Apply() end },
                        },
                    })
                    MakeCogBtn(alignRow._rightRegion, cogShowAll, nil, EllesmereUI.DIRECTIONS_ICON)
                end
            end

            -- Block Background (inline swatch) | Color (Custom/Class/Accent
            -- swatches: text + icon tint, status-bar fills unaffected).
            -- (Hover Highlight is a bar-level setting in BAR SETTINGS now.)
            -- Colors apply during block re-render, so force a full reflow
            -- (a plain apply skips blocks whose width did not change).
            local function ApplyBlockColor()
                if ns.ReflowBlocks then ns.ReflowBlocks(barId) end
            end
            local colorCfg = { type = "multiSwatch", text = "Color",
                  swatches = {
                    { tooltip = "Custom Color", hasAlpha = false,
                      getValue = function()
                          local c = b.color
                          if c then return c.r or 1, c.g or 1, c.b or 1 end
                          return 1, 1, 1
                      end,
                      setValue = function(r, g, bl)
                          b.color = { r = r, g = g, b = bl }
                          ApplyBlockColor()
                      end,
                      onClick = function(self)
                          if b.useClassColor or b.useAccentColor then
                              b.useClassColor = nil
                              b.useAccentColor = nil
                              ApplyBlockColor(); EllesmereUI:RefreshPage()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function()
                          return (b.useClassColor or b.useAccentColor) and 0.3 or 1
                      end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, classFile = UnitClass("player")
                          local cc = classFile and RAID_CLASS_COLORS
                              and RAID_CLASS_COLORS[classFile]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function()
                          b.useClassColor = true
                          b.useAccentColor = nil
                          ApplyBlockColor(); EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha = function() return b.useClassColor and 1 or 0.3 end },
                    { tooltip = "Accent Color", hasAlpha = false,
                      getValue = function() return ns.GetAccent() end,
                      setValue = function() end,
                      onClick = function()
                          b.useAccentColor = true
                          b.useClassColor = nil
                          ApplyBlockColor(); EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha = function() return b.useAccentColor and 1 or 0.3 end },
                  } }
            local bgRow
            local bgRightCfg
            if isSpacer then bgRightCfg = { type = "label", text = "" } else bgRightCfg = colorCfg end
            bgRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Block Background",
                  tooltip = "Tints this block's slot with its own color.",
                  getValue = function() return b.bg ~= nil end,
                  setValue = function(v)
                      if v then
                          if not b.bg then b.bg = { r = 0, g = 0, b = 0, a = 0.5 } end
                      else
                          b.bg = nil
                      end
                      Apply()
                      EllesmereUI:RefreshPage()
                  end },
                bgRightCfg);  y = y - h
            do
                local rgn = bgRow._leftRegion
                local ctrl = rgn._control
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, bgRow:GetFrameLevel() + 3,
                    function()
                        local c = b.bg
                        if not c then return 0, 0, 0, 0.5 end
                        local r = c.r; if r == nil then r = 0 end
                        local g = c.g; if g == nil then g = 0 end
                        local b2 = c.b; if b2 == nil then b2 = 0 end
                        local a = c.a; if a == nil then a = 0.5 end
                        return r, g, b2, a
                    end,
                    function(r, g, b2, a)
                        b.bg = { r = r, g = g, b = b2, a = a }
                        Apply()
                    end,
                    true, 20)
                PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
                local block = CreateFrame("Frame", nil, swatch)
                block:SetAllPoints()
                block:SetFrameLevel(swatch:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Block Background"))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateState()
                    if b.bg then
                        swatch:SetAlpha(1)
                        block:Hide()
                    else
                        swatch:SetAlpha(0.3)
                        block:Show()
                    end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); UpdateState() end)
                UpdateState()
            end

            -- Type-specific rows (sequential DualRow fill; odd tail gets a
            -- blank label in the remaining slot)
            local function MkToggle(label, key, tip)
                return { type = "toggle", text = label, tooltip = tip,
                    getValue = function() return s[key] == true end,
                    setValue = function(v)
                        s[key] = v and true or false
                        Apply()
                    end }
            end

            local typeRows = {}
            if b.type == "clock" then
                typeRows = {
                    MkToggle("Local Time", "localTime", "Local computer time instead of server time."),
                    MkToggle("24 Hour Clock", "twentyFour", "Use 24-hour time."),
                    MkToggle("Mail Alert", "showMail", "Shows an envelope icon when you have unread mail."),
                    MkToggle("Resting Icon", "showResting", "Shows a rest icon while your character is resting."),
                }
            elseif b.type == "ms" then
                typeRows = {
                    MkToggle("World Latency", "useWorldLatency", "Show world latency instead of home latency."),
                }
            elseif b.type == "durability" then
                typeRows = {
                    MkToggle("Show Icon", "showIcon", "Shows the icon next to the durability readout."),
                }
            elseif b.type == "gold" then
                typeRows = {
                    MkToggle("Show Icon", "showIcons", "Shows the coin icon next to the amount."),
                    MkToggle("Show Bag Space", "showBagSpace", "Shows your free bag slots."),
                    MkToggle("Show Silver and Copper", "showSmall", "Shows silver and copper, not just gold."),
                }
            elseif b.type == "xprep" then
                typeRows = {
                    { type = "dropdown", text = "Mode",
                      tooltip = "Automatic shows XP while leveling and reputation at max level.",
                      values = { auto = "Automatic", xp = "Experience", rep = "Reputation" },
                      order = { "auto", "xp", "rep" },
                      getValue = function()
                          local m = s.mode
                          if m == nil then m = "auto" end
                          return m
                      end,
                      setValue = function(v) s.mode = v; Apply() end },
                }
            elseif b.type == "spec" then
                typeRows = {
                    MkToggle("Show Loadout Name", "showLoadout", "Shows the active talent loadout name."),
                    MkToggle("Uppercase Text", "useUppercase", "Renders the spec text in uppercase."),
                }
            elseif b.type == "travel" then
                typeRows = {
                    MkToggle("Random Hearthstone", "randomizeHs", "Uses a random hearthstone toy variant each cast."),
                    -- Default ON (nil = enabled), so this can't use MkToggle's
                    -- `== true` read.
                    { type = "toggle", text = "Clickable Teleports",
                      tooltip = "Left-click a ready Mythic+ teleport in the tooltip to cast it.",
                      getValue = function() return s.clickableTeleports ~= false end,
                      setValue = function(v)
                          s.clickableTeleports = v and true or false
                          Apply()
                      end },
                }
            elseif b.type == "micromenu" then
                -- Align Content returns here as a type row (its shared-row
                -- slot hosts the Enable Text toggle instead): anchors the
                -- whole icon strip within the block's slot via b.align.
                local mmAlignValues
                if vertical then
                    mmAlignValues = { LEFT = "Top", CENTER = "Center", RIGHT = "Bottom" }
                else
                    mmAlignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
                end
                typeRows = {
                    { type = "dropdown", text = "Align Content",
                      tooltip = "Where the icon strip sits inside its slot.",
                      values = mmAlignValues, order = { "LEFT", "CENTER", "RIGHT" },
                      getValue = function()
                          local a = b.align
                          if a == nil then a = "CENTER" end
                          return a
                      end,
                      setValue = function(v) b.align = v; Apply() end },
                    MkToggle("Hide Blizzard Micro Menu", "disableBlizzardMicroMenu", "Hides Blizzard's own micro menu while any bar has this on."),
                    { type = "slider", pixel = true, text = "Menu Spacing", min = 0, max = 16, step = 1,
                      tooltip = "Gap between the main menu button and the icon row.",
                      getValue = function()
                          local v = s.mainMenuSpacing
                          if v == nil then v = 4 end
                          return v
                      end,
                      setValue = function(v) s.mainMenuSpacing = v; Apply() end },
                    { type = "slider", pixel = true, text = "Icon Spacing", min = 0, max = 16, step = 1,
                      tooltip = "Gap between the micro menu icons.",
                      getValue = function()
                          local v = s.iconSpacing
                          if v == nil then v = 2 end
                          return v
                      end,
                      setValue = function(v) s.iconSpacing = v; Apply() end },
                    MkToggle("Character Stats Tooltip", "charStatsTooltip", "Shows item level and secondary stats in the Character button's tooltip."),
                    -- Individual button toggles live in the "Menu Elements"
                    -- checklist dropdown appended after the shared row loop.
                }
            elseif b.type == "currency" then
                local cValues, cOrder = ns.BuildCurrencyList()
                cValues._noLoc = true
                cValues._menuOpts = { searchable = true, itemHeight = 26 }
                cValues[0] = L("Select a currency")
                table.insert(cOrder, 1, 0)
                typeRows = {
                    { type = "dropdown", text = "Currency",
                      tooltip = "Pick any currency your character has discovered.",
                      values = cValues, order = cOrder,
                      getValue = function()
                          local id = s.currencyId
                          if id == nil then id = 0 end
                          return id
                      end,
                      setValue = function(v)
                          if v == 0 then s.currencyId = nil else s.currencyId = v end
                          Apply()
                      end },
                    MkToggle("Show Icon", "showIcon", "Shows the currency icon next to the amount."),
                }
            end

            for k = 1, #typeRows, 2 do
                local rightCfg = typeRows[k + 1]
                if not rightCfg then rightCfg = { type = "label", text = "" } end
                _, h = W:DualRow(parent, y, typeRows[k], rightCfg);  y = y - h
            end

            if b.type == "micromenu" then
                -- Menu Elements: ONE checklist dropdown for the individual
                -- micro menu buttons (same placeholder-swap idiom as the
                -- bar's Visibility Options row above).
                local MM_ELEMENTS = {
                    { key = "menu",    label = "Menu" },
                    { key = "guild",   label = "Guild" },
                    { key = "social",  label = "Social" },
                    { key = "char",    label = "Character" },
                    { key = "spell",   label = "Spellbook" },
                    { key = "ach",     label = "Achievements" },
                    { key = "quest",   label = "Quests" },
                    { key = "lfg",     label = "Group Finder" },
                    { key = "pvp",     label = "PvP" },
                    { key = "housing", label = "Housing" },
                    { key = "journal", label = "Journal" },
                    { key = "pet",     label = "Pets" },
                    { key = "shop",    label = "Shop" },
                    { key = "help",    label = "Help" },
                }
                local mmRow
                mmRow, h = W:DualRow(parent, y,
                    { type = "dropdown", text = "Menu Elements",
                      tooltip = "Which micro menu buttons this block shows.",
                      values = { __placeholder = "..." }, order = { "__placeholder" },
                      getValue = function() return "__placeholder" end,
                      setValue = function() end },
                    { type = "label", text = "" });  y = y - h
                do
                    local leftRgn = mmRow._leftRegion
                    if leftRgn._control then leftRgn._control:Hide() end
                    local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                        MM_ELEMENTS,
                        function(k)
                            return s[k] ~= false
                        end,
                        function(k, v)
                            if v then s[k] = true else s[k] = false end
                            Apply()
                        end)
                    PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                    leftRgn._control = cbDD
                    leftRgn._lastInline = nil
                    if cbDDRefresh then EllesmereUI.RegisterWidgetRefresh(cbDDRefresh) end
                end
            end

            -- Reordering = drag the segment in the preview strip; removal =
            -- right-click the segment (Remove Block). No body rows for either.
        end

        -- Width % hover highlight: while the cursor is over a block's
        -- Width % control (just that control, not the whole section), wash
        -- that block 8 percent white on BOTH the preview segment and the
        -- live bar slot. Poll watcher is parented to the page wrapper, so
        -- it stops (and clears) when the page hides.
        if #blockHoverRegions > 0 then
            local watcher = CreateFrame("Frame", nil, parent)
            watcher:SetSize(1, 1)
            local acc = 0
            local curHL
            local function SetHL(id)
                if id == curHL then return end
                curHL = id
                if _edbSegHighlightFn then _edbSegHighlightFn(id) end
                if ns.SetBlockEditHighlight then
                    if id then
                        ns.SetBlockEditHighlight(barId, id)
                    elseif not _edbSegHoverId then
                        -- A segment hover owns the live highlight right now;
                        -- clearing here would kill it 0.1s after OnEnter.
                        ns.SetBlockEditHighlight(nil, nil)
                    end
                end
            end
            watcher:SetScript("OnUpdate", function(_, elapsed)
                acc = acc + elapsed
                if acc < 0.1 then return end
                acc = 0
                if not parent:GetTop() or not parent:IsMouseOver() then
                    SetHL(nil)
                    return
                end
                -- The preview header (and the vertical popout) float OVER
                -- the scrolled body, and IsMouseOver is a pure rect test
                -- that ignores clipping -- a control scrolled under the
                -- preview would highlight while the cursor is on the strip.
                -- Only count the cursor inside the scroll viewport.
                local sf = EllesmereUI._scrollFrame
                if sf and not sf:IsMouseOver() then
                    SetHL(nil)
                    return
                end
                local hit
                for k = 1, #blockHoverRegions do
                    local hr = blockHoverRegions[k]
                    if hr.rgn and hr.rgn:IsMouseOver() then
                        hit = hr.id
                        break
                    end
                end
                SetHL(hit)
            end)
            watcher:HookScript("OnHide", function() SetHL(nil) end)
        end

        -- Adding blocks lives in the preview strip's "+" tile only -- no
        -- body section.
        W:Spacer(parent, y, 20);  y = y - 20

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Module registration
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIDataBars", {
        title       = "DataBars",
        description = "User-created info bars: clock, gold, XP, micro menu and more.",
        pages       = { PAGE_DATABARS },
        buildPage   = function(pageName, parent, yOffset)
            return BuildDataBarsPage(pageName, parent, yOffset)
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DATABARS then return _edbHeaderBuilder end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            -- Bars can be resized/width-matched via unlock mode between
            -- visits; re-solve the restored preview from the live cfg.
            if pageName == PAGE_DATABARS and _edbStripRelayout then
                _edbStripRelayout()
            end
        end,
        onReset = function()
            -- Resets the SELECTED bar's appearance/behavior to defaults;
            -- keeps its id, name and blocks. Never wipes the bar list.
            -- (The framework's footer button confirms and reloads for us.)
            local p = ns.GetProfile()
            if not p then return end
            local cfg = nil
            if p.selectedBarId then cfg = ns.GetBar(p.selectedBarId) end
            if not cfg then cfg = p.bars[1] end
            if not cfg then return end
            cfg.orientation = "H"
            cfg.lengthMode = "custom"
            cfg.length = 400
            cfg.thickness = 30
            cfg.fontScale = 100
            cfg.theme = { style = "eui", euiAlpha = 0.5, modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 } }
            cfg.visibility = "always"
            cfg.visibilityModes = nil
            for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                cfg[item.key] = nil
            end
            cfg.savedPos = nil
            ns.ApplyBar(cfg.id)
            ns.UpdateAllBarVisibility()
            EllesmereUI:InvalidatePageCache()
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /edb  opens EllesmereUI to the DataBars module
    ---------------------------------------------------------------------------
    SLASH_ELLESMEREDATABARS1 = "/edb"
    SlashCmdList.ELLESMEREDATABARS = function()
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end
        EllesmereUI:ShowModule("EllesmereUIDataBars")
    end
end)
