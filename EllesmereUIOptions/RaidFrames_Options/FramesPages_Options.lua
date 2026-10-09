if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  RaidFrames_Options\FramesPages_Options.lua
--  Raid Frames options: the raid Frames page (BuildMainPage), the Party page
--  (BuildPartyPage) and the Sort By control both use. Definitions only; the
--  shared helpers come from ns._RFO_OptEnv (filled by EUI_RaidFrames_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]
if not ns then return end  -- module disabled: no options page

---------------------------------------------------------------------------
--  Shared "Sort By" control: Group/Role radio + drag-to-reorder role rows, installed into a DualRow half-region
--  (replaces its placeholder dropdown); used by both raid LAYOUT and party FRAMES tabs. opts wires it to:
--      opts.readMode()    -> "INDEX" | "ROLE"
--      opts.writeMode(v)  -- persist sort mode + trigger reload/preview
--      opts.readRoles()   -> { role, role, role }  (read-only)
--      opts.writeRoles(t) -- persist role order + trigger reload/preview
---------------------------------------------------------------------------
local function BuildSortByControl(rgn, opts)
    local env = ns._RFO_OptEnv
    local PP = env.PP
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
--  Page Builder
---------------------------------------------------------------------------
local function PartyPixelsBorder()
    if ns.RF_PartyKit() or ns.RF_Stock() then return false end
    local p = ns._RFO_OptEnv.db.profile
    local key = p.borderTexture
    if ns._IsPartySectionCustom(ns._PARTY_KEY_SECTION.borderTexture) then
        key = p.party_borderTexture or key
    end
    return key == "pixels" or key == "pixels-textured"
end

local function BuildMainPage(pageName, parent, yOffset)
    local env = ns._RFO_OptEnv
    local allGrowthOrder, BuildPreviewModeRow, BuildVisualSections, db = env.allGrowthOrder, env.BuildPreviewModeRow, env.BuildVisualSections, env.db
    local growthValues, KeepGrowthPerpendicular, PP, ReloadAndUpdate = env.growthValues, env.KeepGrowthPerpendicular, env.PP, env.ReloadAndUpdate
    local groupGrowthValues, groupGrowthOrder, ReadGroupGrowth = env.groupGrowthValues, env.groupGrowthOrder, env.ReadGroupGrowth
    local SGet, SGetPx, SSet, SVal = env.SGet, env.SGetPx, env.SSet, env.SVal
    local SWrite = env.SWrite
    local W = EllesmereUI.Widgets
    local _, h
    local row

    -- Both Group Growth menus grey out the grid flow while groups are merged,
    -- where it would render as Right (ReadGroupGrowth).
    local function GridFlowOff(v)
        if v == "DOWNRIGHT" and SVal("mergeGroups", false) then
            return EllesmereUI.DisabledTooltip("Merge Groups", "disabled")
        end
    end

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
                              itemDisabled=GridFlowOff,
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
            autoResizeRow, h = W:DualRow(parent, y,  -- eui-style: allow dualrow-left-gap (the checkbox dropdown below overlays the right region)
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
              if (v == "pixels" or v == "pixels-textured") and PartyPixelsBorder()
                  and EllesmereUI.PP.ToPixels(db.profile.partyCellSpacing or db.profile.cellSpacing or 2) <= 1 then
                  db.profile.partyCellSpacing = EllesmereUI.PP.FromPixels(1)
                  db.profile.partySharedBorder = true
              end
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
        -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog left
        -- of the Border swatch.
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Corner Radius", tip = "Corner Radius",
            disabled = function() return not EllesmereUI.RoundedStyleOK(SGet("borderTexture")) end,
            disabledTooltip = "This option requires the Solid, Glow or Shadow border style.",
            rows = EllesmereUI.RoundedCornerRows({
                { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                  get = function() return SVal("cornerRadius", 0) end,
                  set = function(v) SSet("cornerRadius", v) end },
            }, function() return SGet("cornerMask") end, function(v) SSet("cornerMask", v) end),
        })
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
    -- flow, which it renders as a plain RIGHT run (see ReadGroupGrowth in
    -- EUI_RaidFrames_Options.lua) -- gets silently reinterpreted (see the colAnchor
    -- comment in EUI_RaidFrames_Layout.lua)
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
          disabledValues=GridFlowOff,
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
                { type="toggle", label="Hide Groups 5-8 in Mythic Raid",
                  tooltip="Mythic raids allow only 20 players (groups 1-4), so hide groups 5-8 while inside one. Groups 1-4 still follow Show Groups, and Show Groups applies as normal everywhere else.",
                  get=function() return SVal("mythicRaidHideGroups", false) end,
                  set=function(v) SSet("mythicRaidHideGroups", v) end },
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
    local env = ns._RFO_OptEnv
    local db = env.db
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
    local env = ns._RFO_OptEnv
    local BuildPreviewModeRow, BuildVisualSections, db, optState = env.BuildPreviewModeRow, env.BuildVisualSections, env.db, env.optState
    local PP, SVal = env.PP, env.SVal
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
          -- RefreshPage re-reads Include Own Target's disabled state.
          setValue=function(v) db.profile.partyHideSelf = v; PartyReloadAndUpdate(); EllesmereUI:RefreshPage() end });  y = y - h

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
        ns.RF_PartyKitGate({ type="slider", pixel=true, text="Frame Spacing",
          min=PartyPixelsBorder() and EllesmereUI.PP.FromPixels(1) or -1, max=15, step=1,
          tooltip="Pixels and Pixels Textured require at least 1 pixel of spacing. Selecting 1 enables compact mode with one party border and separators.",
          getValue=function()
              if ns.RF_PartyKit() then return db.profile.partyKitSpacing or ns.RF_KIT_SPACING or 6 end
              return SVal("partyCellSpacing", db.profile.cellSpacing or 2)
          end,
          setValue=function(v)
              local pixels = PartyPixelsBorder()
              if pixels then v = math.max(v, EllesmereUI.PP.FromPixels(1)) end
              db.profile.partySharedBorder = pixels and EllesmereUI.PP.ToPixels(v) == 1
              PSSet(ns.RF_PartyKit() and "partyKitSpacing" or "partyCellSpacing", v)
          end }));  y = y - h
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
    --  PARTY TARGETS (party only, every style; file-scope builder)
    -------------------------------------------------------------------
    y = ns.RF_BuildPartyTargets(parent, y, W)

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
        bg:SetColorTexture(17/255, 15/255, 12/255, 0.98)
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

    optState._partyCtx = true
    y = BuildVisualSections(parent, y, W, SyncOverlay)
    -- Do NOT reset _partyCtx here (the SelectPage hook owns it): resetting would break SSet after any RefreshPage on the party tab.

    return math.abs(y)
end

-- Used by EUI_RaidFrames_Options.lua
ns.RFO_BuildMainPage = BuildMainPage
ns.RFO_BuildPartyPage = BuildPartyPage
