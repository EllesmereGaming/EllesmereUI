-------------------------------------------------------------------------------
--  EUI_RaidFrames_Options.lua
--  Registers the Raid Frames module with EllesmereUI options panel.
--  Two tabs: Raid Frames (layout, health, power, text, border, absorbs,
--  indicators, debuffs, dispels, range/tooltip) and Buff Manager.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_MAIN = "Raid"
local PAGE_PARTY = "Party"
local PAGE_DEBUFFS = "Defense & Debuffs"
local PAGE_BUFFS = "Buff Manager"
local PAGE_CLICKCAST = "HoverCast"

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

    local function GetOutline()
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    end
    local function GetUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
    end

    ---------------------------------------------------------------------------
    --  Shared helpers
    ---------------------------------------------------------------------------
    local GetFFD = ns.GetFFD

    local function ReloadAndUpdate()
        if ReloadFrames then ReloadFrames() end
        -- Refresh preview visuals (keeps health values, updates layout/colors)
        if ns.previewActive and ns.previewActive() and ns.ShowPreview then
            ns.ShowPreview()
        end
        -- Refresh active size preview (growth direction, spacing, etc.)
        if ns._sizePreviewTier and ns._ShowSizePreview then
            ns._ShowSizePreview(ns._sizePreviewTier)
        end
        -- Re-anchor active preview aura icons with new settings
        if ns.RefreshPvAuraVisuals then ns.RefreshPvAuraVisuals() end
        -- Party frames share all settings except width/height; reload them too
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
            ns.ShowPartyPreview()
        end
    end

    ---------------------------------------------------------------------------
    --  Context-aware settings helpers
    --  When _partyCtx is true (party tab active), all reads/writes go to
    --  "party_<key>" with fallthrough to raid values. The SAME page builders
    --  work for both raid and party tabs with zero code changes.
    ---------------------------------------------------------------------------
    local _partyCtx = false  -- set true when building/interacting on party tab
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
    -- Direct write (for color swatches that bypass SSet). Context-aware.
    local function SWrite(key, val)
        if _partyCtx and PARTY_KEY_SECTION[key] and IsPartySectionCustom(PARTY_KEY_SECTION[key]) then
            db.profile["party_" .. key] = val
        else
            db.profile[key] = val
        end
    end

    ---------------------------------------------------------------------------
    --  Shared custom "Sort By" control: a Group/Role radio plus drag-to-reorder
    --  role rows. Installed into a DualRow half-region (replacing the region's
    --  placeholder dropdown). The raid LAYOUT tab and the party FRAMES tab both
    --  use this so the two controls are identical; the caller supplies opts to
    --  wire it to its own keys + reload path:
    --      opts.readMode()    -> "INDEX" | "ROLE"
    --      opts.writeMode(v)  -- persist the sort mode + trigger reload/preview
    --      opts.readRoles()   -> { role, role, role }  (read-only)
    --      opts.writeRoles(t) -- persist the role order + trigger reload/preview
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
            sLabel:SetText(mode == "ROLE" and EllesmereUI.L("Role") or EllesmereUI.L("Group"))
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

        -- Build the sort menu
        local MH = 26       -- row height
        local DH = 16       -- divider height
        local EG = EllesmereUI.ACCENT_COLOR or { r = 0.05, g = 0.82, b = 0.62 }

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

        menuFrame:SetScript("OnShow", function(self)
            local sc = sortBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
            self:SetScale(sc)
            self:SetScript("OnUpdate", function(m)
                if not sortBtn:IsMouseOver() and not m:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                end
            end)
        end)
        menuFrame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        menuFrame:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", 0, -2)

        local mY = -2
        local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"

        -- Radio items: Group, Role
        local radioItems = {
            { key = "INDEX", label = "Group" },
            { key = "ROLE",  label = "Role" },
        }
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

            rl:SetText(ri.label)
            radioRows[#radioRows + 1] = rr
            mY = mY - MH
        end

        -- Divider
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

        -- Hint text
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
        -- Ensure we have a valid table
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

        local dragRow = nil   -- which row is being dragged
        local dsY = nil       -- cursor Y at drag start
        local isDragging = false

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
            rl:SetText(cb.label)
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
                -- Position insertion line
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

                -- Move the dragged row with cursor
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
                    -- Reorder the display items, then persist the new order as a
                    -- fresh table (never mutate the source table in place -- when
                    -- party falls back to the raid order this would corrupt it).
                    local mvItem = table.remove(roleItems, from)
                    table.insert(roleItems, to, mvItem)
                    local ro = {}
                    for _, it in ipairs(roleItems) do ro[#ro + 1] = it.key end
                    opts.writeRoles(ro)
                end

                -- Reposition all rows
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
    -- Re-append SharedMedia textures now (post-login) so the dropdown includes
    -- SM entries registered after our ADDON_LOADED. The first append in
    -- OnInitialize runs too early to catch most SM texture providers.
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(
            ns.healthBarTextureNames or {},
            ns.healthBarTextureOrder or {},
            nil,
            ns.healthBarTextures
        )
    end

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
        ["class"]    = "Class Color",
        ["dark"]     = "Dark Mode",
        ["classic"]  = "Classic",
        ["custom"]   = "Custom Color",
    }
    local healthColorOrder = { "class", "dark", "classic", "custom" }

    local namePositionValues = {
        ["topleft"]    = "Top Left",
        ["top"]        = "Top",
        ["topright"]   = "Top Right",
        ["left"]       = "Left",
        ["center"]     = "Center",
        ["right"]      = "Right",
        ["bottomleft"] = "Bottom Left",
        ["bottom"]     = "Bottom",
        ["bottomright"] = "Bottom Right",
    }
    local namePositionOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

    local healthTextValues = {
        ["none"]          = "None",
        ["percent"]       = "Percent",
        ["percentNoSign"] = "Percent (No Sign)",
        ["number"]        = "Number",
        ["numberPercent"] = "Number | Percent",
        ["percentNumber"] = "Percent | Number",
    }
    local healthTextOrder = { "none", "percent", "percentNoSign", "number", "numberPercent", "percentNumber" }

    local absorbStyleValues = {
        ["none"]     = "None",
        ["striped"]  = "Striped",
        ["clean"]    = "Clean (Flat)",
        ["blizzard"] = "Blizzard",
    }
    local absorbStyleOrder = { "none", "striped", "clean", "blizzard" }

    local growthValues = {
        DOWN  = "Down",
        UP    = "Up",
        RIGHT = "Right",
        LEFT  = "Left",
    }
    local verticalGrowthOrder   = { "DOWN", "UP" }
    local horizontalGrowthOrder = { "RIGHT", "LEFT" }
    local allGrowthOrder        = { "DOWN", "UP", "RIGHT", "LEFT" }

    local function GetValidUnitGrowths(groupGrowth)
        if groupGrowth == "DOWN" or groupGrowth == "UP" then
            return { RIGHT = "Right", LEFT = "Left" }, horizontalGrowthOrder
        else
            return { DOWN = "Down", UP = "Up" }, verticalGrowthOrder
        end
    end

    -- All preview mode dropdowns across tabs (refresh all when one changes)
    local pvModeDropdowns = {}

    -- Shared helper: true when preview is disabled (eyeball toggles should gray out)
    local function IsPreviewOff()
        return (db.profile.previewMode or "overlay") == "none"
    end

    -- Shared: builds the "Preview Mode" dropdown row at the top of a page.
    -- Returns the new y offset after the row.
    local function BuildPreviewModeRow(parent, y)
        local ROW_H = 50
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local contentPad = EllesmereUI.CONTENT_PAD or 45

        y = y - 10
        local modeRow = CreateFrame("Frame", nil, parent)
        PP.Size(modeRow, parent:GetWidth() - contentPad * 2, ROW_H)
        PP.Point(modeRow, "TOPLEFT", parent, "TOPLEFT", contentPad, y)
        y = y - ROW_H

        local modeLabel = modeRow:CreateFontString(nil, "OVERLAY")
        modeLabel:SetFont(fontPath, 14, GetOutline())
        if GetOutline() == "" and GetUseShadow() then
            modeLabel:SetShadowOffset(1, -1); modeLabel:SetShadowColor(0, 0, 0, 1)
        end
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
                -- Apply to whichever preview is active based on current tab
                local page = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
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
                -- Refresh all preview mode dropdown labels across tabs
                for _, syncLbl in ipairs(pvModeDropdowns) do
                    syncLbl:SetText(previewModeValues[v] or v)
                end
                EllesmereUI:RefreshPage()
            end)
        ddCtrl:SetPoint("TOP", modeLabel, "BOTTOM", 0, -9)

        pvModeDropdowns[#pvModeDropdowns + 1] = ddLbl

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
        -- Eyeball coordination handles, kept per context (raid vs party) so the
        -- raid and party page builds do not clobber each other's eye-icon
        -- refreshers. Animation start/stop stay on ns (one shared ticker that
        -- resolves to the active preview at call time via ns.PvActiveFrames).
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

        -- Eyeball: animate health bars (damage/healing simulation).
        -- Built for both raid and party pages; the animation reads the active
        -- preview frame set at runtime via ns.PvActiveFrames().
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            -- Animation state lives on ns (single shared ticker) so the raid and
            -- party eyeball builds drive the same animation and start/stop works
            -- across both. ns._healthAnimActive is the truth read by the renderer.
            ns._healthAnimState = ns._healthAnimState or {}

            local function StopHealthAnim()
                if ns._healthAnimTicker then
                    ns._healthAnimTicker:Cancel()
                    ns._healthAnimTicker = nil
                end
                ns._healthAnimActive = false
                -- Pause: persist current animated values so they stay on screen
                local phv = ns.PvHealthValues()
                if phv then
                    for i, st in ipairs(ns._healthAnimState) do
                        phv[i] = st.current
                    end
                end
            end

            local function StartHealthAnim()
                if ns._healthAnimTicker then return end
                ns._healthAnimActive = true
                wipe(ns._healthAnimState)

                local frames = ns.PvActiveFrames()
                local s = db.profile
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
                    local s = db.profile
                    local smooth = s.smoothBars

                    for i, st in ipairs(ns._healthAnimState) do
                        local f = st.frame
                        if f and f._health and not f._pvHideHealthText then
                            -- Per-unit staggered timer (same cadence for smooth and non-smooth)
                            st.snapTimer = st.snapTimer + 0.1
                            if st.snapTimer < st.nextSnap then
                                -- not ready yet
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

                                -- Update health text
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
                                    end
                                end

                                -- Update fill color for classic (gradient) mode
                                if s.healthColorMode == "classic" then
                                    local pct = st.current / 100
                                    local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
                                    local g = pct > 0.5 and 1 or (pct * 2)
                                    f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
                                end
                            end -- snapTimer ready
                        end
                    end
                end)
            end

            -- Build the eye button on the section header
            -- Find the section label FontString
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
                    -- Turn off indicators if active
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

            -- Stop animation when leaving options
            if EllesmereUI.RegisterOnHide then
                EllesmereUI:RegisterOnHide(function()
                    if ns._healthAnimActive then StopHealthAnim(); RefreshHealthEye() end
                end)
            end

            -- One-time hint explaining the eyeball button (raid/main page only)
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

        -- Row 1: Health Bar Texture | Fill Opacity
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Health Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return SVal("healthBarTexture", "atrocity") end,
              setValue=function(v) SSet("healthBarTexture", v) end },
            { type="slider", text="Fill Opacity", min=10, max=100, step=1,
              getValue=function() return SVal("healthBarOpacity", 100) end,
              setValue=function(v) SSet("healthBarOpacity", v) end });  y = y - h

        -- Row 2: Fill Color | Background
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Fill Color", values=healthColorValues, order=healthColorOrder,
              getValue=function() return SVal("healthColorMode", "class") end,
              setValue=function(v)
                  SSet("healthColorMode", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Background", min=0, max=100, step=1,
              disabled=function() return SVal("healthColorMode", "class") == "dark" end,
              disabledTooltip="Not available in Dark Mode", rawTooltip=true,
              getValue=function() return SVal("bgDarkness", 50) end,
              setValue=function(v) SSet("bgDarkness", v) end });  y = y - h
        -- Inline color swatch for custom fill color
        do
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
            local function UpdateSwatchVis()
                local mode = SVal("healthColorMode", "class")
                swatch:SetAlpha(mode == "custom" and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateSwatchVis)
            UpdateSwatchVis()
        end
        -- Inline swatch for custom bg color
        do
            local rgn = row._rightRegion
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
            bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSwatch
        end

        ns._editTargets = ns._editTargets or {}

        -- Row 3: Absorb Style (+ color swatch) | Absorb Opacity
        local absorbRow
        absorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
              getValue=function() return SVal("absorbStyle", "none") end,
              setValue=function(v)
                  SSet("absorbStyle", v)
                  if v == "clean" then
                      SSet("absorbOpacity", 30)
                  else
                      SSet("absorbOpacity", 90)
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Absorb Opacity", min=5, max=100, step=1,
              disabled=function() return SVal("absorbStyle", "none") == "none" end,
              disabledTooltip="Absorb Style",
              getValue=function() return SVal("absorbOpacity", 90) end,
              setValue=function(v) SSet("absorbOpacity", v) end });  y = y - h
        ns._editTargets.absorbs = absorbRow
        -- Inline color swatch for absorb color
        do
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
            local function UpdateAbsorbSwatchVis()
                swatch:SetAlpha(SVal("absorbStyle", "none") == "none" and 0.3 or 1)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
            UpdateAbsorbSwatchVis()
        end
        -- Inline cog: right-edge absorb rendering
        do
            local rgn = absorbRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Absorb Rendering",
                rows = {
                    { type="toggle", label="Show Absorbs from Right Edge",
                      get=function() return SVal("absorbFromRightEdge", false) end,
                      set=function(v) SSet("absorbFromRightEdge", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 4: Heal Absorb Style (+ color swatch) | Heal Absorb Opacity
        local healAbsorbRow
        healAbsorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
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
        -- Inline color swatch for heal absorb color
        do
            local rgn = healAbsorbRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healAbsorbRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("healAbsorbColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 0.8, 0.15, 0.15, 1
                end,
                function(r, g, b)
                    SWrite("healAbsorbColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateHealAbsorbSwatchVis()
                swatch:SetAlpha(SVal("healAbsorbStyle", "clean") == "none" and 0.3 or 1)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
            UpdateHealAbsorbSwatchVis()
        end

        -- Row 5: Heal Prediction (+ color swatch) | Prediction Opacity
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
        -- Inline color swatch for heal prediction color
        do
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

        -- Row 6: Smooth Bars | Threat Borders
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

        -------------------------------------------------------------------
        --  POWER BAR
        -------------------------------------------------------------------
        local powerHeader
        if onSection then onSection("healthBar", _secY, y) end; _secY = y
        powerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

        -- Power bar animation (same pattern as health; serves raid + party).
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            -- Shared anim state on ns (single ticker, resolves active preview).
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
                    local smooth = db.profile.smoothPowerBars

                    for i, st in pairs(ns._powerAnimState) do
                        local f = st.frame
                        if f and f._power then
                            st.snapTimer = st.snapTimer + 0.1
                            if st.snapTimer < st.nextSnap then
                                -- not ready yet
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

            -- Find the section label FontString
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
                    -- Turn off indicators if active
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

            if EllesmereUI.RegisterOnHide then
                EllesmereUI:RegisterOnHide(function()
                    if ns._powerAnimActive then StopPowerAnim(); RefreshPowerEye() end
                end)
            end
        end  -- close do (power eyeball)

        -- Helper: power bar is off when no roles are selected
        local function IsPowerOff()
            return not SVal("powerShowForHealer", true) and not SVal("powerShowForTank", true) and not SVal("powerShowForDPS", false)
        end

        -- Row 1: Show Power Bar For (checkbox dropdown) | Power Height
        do
            local showForItems = {
                { key = "healer", label = "Healers" },
                { key = "tank",   label = "Tanks" },
                { key = "dps",    label = "DPS" },
            }
            local showForKeyMap = { healer = "powerShowForHealer", tank = "powerShowForTank", dps = "powerShowForDPS" }
            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Show Power Bar For",
                  values={ __placeholder = "Healers, Tanks" }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end },
                { type="slider", text="Power Height", min=1, max=20, step=1,
                  disabled=function() return IsPowerOff() end,
                  disabledTooltip="Show Power Bar For",
                  getValue=function() return SVal("powerHeight", 4) end,
                  setValue=function(v) SSet("powerHeight", v) end });  y = y - h
            do
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

        -- Row 2: Power Border | Power Border Size (+ inline color swatch)
        local pwBorderStyleValues = {
            eui     = "EllesmereUI",
            divider = "Divider",
            border  = "Border",
        }
        local pwBorderStyleOrder = { "eui", "divider", "border" }
        local pwBdrRow
        pwBdrRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style", values=pwBorderStyleValues, order=pwBorderStyleOrder,
              disabled=function() return IsPowerOff() end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerBorderStyle", "divider") end,
              setValue=function(v) SSet("powerBorderStyle", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Border Size", min=0, max=4, step=1,
              disabled=function() return IsPowerOff() or SVal("powerBorderStyle", "eui") == "eui" end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerBorderSize", 1) end,
              setValue=function(v) SSet("powerBorderSize", v) end });  y = y - h
        -- Inline swatch for power border color
        do
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
                    db.profile.powerBorderAlpha = a
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

        -- Row 3: Smooth Power Bars | Background (+ inline bg color swatch)
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
        -- Inline swatch for power bg color
        do
            local rgn = pwBgRow._rightRegion
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
            bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSwatch
        end

        -- (Show Power Bar For moved to Row 1 above)

        -------------------------------------------------------------------
        --  TEXT DISPLAY
        -------------------------------------------------------------------
        if onSection then onSection("powerBar", _secY, y) end; _secY = y
        _, h = W:SectionHeader(parent, "TEXT DISPLAY", y); y = y - h

        -- Row 1: Name Size | Name Color (triple swatch: custom / class / accent)
        row, h = W:DualRow(parent, y,
            { type="slider", text="Name Size", min=6, max=18, step=1,
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
                      return EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
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

        -- Row 2: Name Position (+ cog for X/Y) | Health Text
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Name Position", values=namePositionValues, order=namePositionOrder,
              getValue=function() return SVal("namePosition", "center") end,
              setValue=function(v) SSet("namePosition", v) end },
            { type="dropdown", text="Health Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return SVal("healthTextMode", "none") end,
              setValue=function(v) SSet("healthTextMode", v) end });  y = y - h
        -- Cog for name offset X/Y
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        -- Inline color swatches for Health Text color (custom / class / accent),
        -- mirroring the Name Color triple swatch. Added custom-first so the
        -- _lastInline chain puts custom next to the dropdown (matches Name Color).
        do
            local rgn = row._rightRegion
            local function AddHTSwatch(getColor, setColor, mode, opensPicker, tooltip)
                local sw = EllesmereUI.BuildColorSwatch(
                    rgn, row:GetFrameLevel() + 3, getColor, setColor, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = sw
                -- Preserve the picker-opening click, then switch mode on click
                -- (same technique the multiSwatch widget uses for Name Color).
                sw._eabOrigClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self)
                    if SVal("healthTextColorMode", "custom") ~= mode then
                        SSet("healthTextColorMode", mode)
                        EllesmereUI:RefreshPage()
                        return
                    end
                    if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
                end)
                -- Tooltip via HookScript so BuildColorSwatch's own hover stays intact.
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
            -- Custom (rightmost): editable color, opens the picker when active.
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
            -- Class color.
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
            -- Accent color (leftmost).
            AddHTSwatch(
                function()
                    local r, g, b = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
                    return r or 1, g or 1, b or 1, 1
                end,
                function() end, "accent", false, "Accent Color")
        end

        -- Row 3: Health Text Position (+ cog for X/Y) | Health Text Size
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Health Text Position", values=namePositionValues, order=namePositionOrder,
              disabled=function() return SVal("healthTextMode", "none") == "none" end,
              disabledTooltip="Health Text",
              getValue=function() return SVal("healthTextPosition", "center") end,
              setValue=function(v) SSet("healthTextPosition", v) end },
            { type="slider", text="Health Text Size", min=6, max=18, step=1,
              disabled=function() return SVal("healthTextMode", "none") == "none" end,
              disabledTooltip="Health Text",
              getValue=function() return SVal("healthTextSize", 9) end,
              setValue=function(v) SSet("healthTextSize", v) end });  y = y - h
        -- Cog for health text offset X/Y
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local htOff = SVal("healthTextMode", "none") == "none"
            cogBtn:SetAlpha(htOff and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s)
                s:SetAlpha(SVal("healthTextMode", "none") == "none" and 0.15 or 0.4)
            end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end

        -------------------------------------------------------------------
        --  INDICATORS
        -------------------------------------------------------------------
        local indicatorHeader
        if onSection then onSection("textDisplay", _secY, y) end; _secY = y
        indicatorHeader, h = W:SectionHeader(parent, "INDICATORS", y); y = y - h

        -- Eyeball: toggle indicator visibility on preview (raid + party)
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"

            -- Find the section label FontString
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

            -- State stored on ns so preview can read it
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
                -- Turn off health/power/dispels when indicators turn on
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

        -- Row 1: Role Icon Style | Role Icon Size
        local ROLE_MEDIA = "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\"
        local RI_STYLES = {
            modern = { _isTexture = true, TANK = ROLE_MEDIA .. "tank-modern.png", HEALER = ROLE_MEDIA .. "healer-modern.png", DAMAGER = ROLE_MEDIA .. "dps-modern.png" },
            modernCircle = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" },
            styled = { TANK = "UI-LFG-RoleIcon-Tank-Background", HEALER = "UI-LFG-RoleIcon-Healer-Background", DAMAGER = "UI-LFG-RoleIcon-DPS-Background" },
            classicCircle = { TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder" },
            classic = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" },
            blizzDefault = { TANK = "GM-icon-role-tank", HEALER = "GM-icon-role-healer", DAMAGER = "GM-icon-role-dps" },
        }
        local playerRole = UnitGroupRolesAssigned("player")
        if playerRole == "NONE" then
            local specIdx = GetSpecialization()
            if specIdx then playerRole = GetSpecializationRole(specIdx) end
        end
        local roleStyleValues = {
            none          = "None",
            modern        = "Modern",
            modernCircle  = "Modern Circle",
            styled        = "Styled",
            classicCircle = "Classic Circle",
            classic       = "Classic",
            blizzDefault  = "Blizz Default",
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
        local roleStyleOrder = { "none", "modern", "modernCircle", "styled", "classicCircle", "classic", "blizzDefault" }
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
        -- Replace right side with checkbox dropdown
        do
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
        -- Row 2: Role Position (+ cog for X/Y) | Role Icon Size
        local rolePositionValues = {
            topleft     = "Top Left",
            topright    = "Top Right",
            bottomleft  = "Bottom Left",
            bottomright = "Bottom Right",
        }
        local rolePositionOrder = { "topleft", "topright", "bottomleft", "bottomright" }
        local roleRow2
        roleRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Role Position", values=rolePositionValues, order=rolePositionOrder,
              disabled=function() return SVal("roleIconStyle", "modern") == "none" end,
              disabledTooltip="Role Icons",
              getValue=function() return SVal("roleIconPosition", "bottomleft") end,
              setValue=function(v) SSet("roleIconPosition", v) end },
            { type="slider", text="Role Icon Size", min=8, max=24, step=1,
              disabled=function() return SVal("roleIconStyle", "modern") == "none" end,
              disabledTooltip="Role Icons",
              getValue=function() return SVal("roleIconSize", 14) end,
              setValue=function(v) SSet("roleIconSize", v) end });  y = y - h
        -- Cog for role icon offset X/Y
        do
            local rgn = roleRow2._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 3: Marker Position (includes "None" to disable) | Marker Size
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

        -- Cog for marker offset X/Y
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Status Text Position (+ cog for X/Y) | Text Size (+ inline color swatch)
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
            { type="slider", text="Text Size", min=6, max=24, step=1,
              getValue=function() return SVal("statusTextSize", 14) end,
              setValue=function(v) SSet("statusTextSize", v) end });  y = y - h
        -- Cog for status text offset X/Y
        do
            local rgn = stRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end
        -- Inline color swatch for status text color
        do
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

        -- Row: Leader Icon Position | Leader Icon Size
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
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Leader Icon", values=leaderPositionValues, order=leaderPositionOrder,
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
            { type="slider", text="Leader Icon Size", min=8, max=24, step=1,
              disabled=function() return not SVal("showLeaderIcon", false) end,
              disabledTooltip="Leader Icon",
              getValue=function() return SVal("leaderIconSize", 14) end,
              setValue=function(v) SSet("leaderIconSize", v) end });  y = y - h
        -- Cog for leader icon offset X/Y
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Leader Icon Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("leaderIconOffsetX", 0) end,
                      set=function(v) SSet("leaderIconOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("leaderIconOffsetY", 0) end,
                      set=function(v) SSet("leaderIconOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Show Group Numbers | Number Size (+ inline color swatch with alpha).
        -- Raid only: party frames have no groups. The size + color also drive the
        -- always-on preview group labels; the toggle gates only the real frames.
        if not _partyCtx then
            local gnRow
            gnRow, h = W:DualRow(parent, y,
                { type="toggle", text="Show Group Numbers",
                  getValue=function() return SVal("showGroupNumbers", false) end,
                  setValue=function(v) SSet("showGroupNumbers", v) end },
                { type="slider", text="Number Size", min=6, max=24, step=1,
                  getValue=function() return SVal("groupNumberSize", 10) end,
                  setValue=function(v) SSet("groupNumberSize", v) end });  y = y - h
            -- Inline color swatch (alpha enabled) on the Number Size region
            do
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
            -- Inline cog (X/Y offset) on the Show Group Numbers toggle
            do
                local rgn = gnRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
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
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            end
        end

        -------------------------------------------------------------------
        --  DISPELS
        -------------------------------------------------------------------
        local dispelHeader
        if onSection then onSection("indicators", _secY, y) end; _secY = y
        dispelHeader, h = W:SectionHeader(parent, "DISPELS", y); y = y - h

        -- Eyeball: toggle dispel visibility on preview (raid + party)
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"

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
                -- Turn off indicators when dispels turn on
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
        }
        local dispelOverlayOrder = { "none", "fill", "full", "gradient" }

        -- Row 1: Dispel Overlay | Overlay Opacity
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Dispel Overlay", values=dispelOverlayValues, order=dispelOverlayOrder,
              getValue=function() return SVal("dispelOverlay", "fill") end,
              setValue=function(v) SSet("dispelOverlay", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Overlay Opacity", min=5, max=100, step=1,
              disabled=function() return SVal("dispelOverlay", "fill") == "none" end,
              disabledTooltip="Dispel Overlay",
              getValue=function() return SVal("dispelOverlayOpacity", 100) end,
              setValue=function(v) SSet("dispelOverlayOpacity", v) end });  y = y - h


        -- Row 2: Dispel Border Size | Dispel Icon Position (includes "None" to disable)
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
            { type="slider", text="Dispel Border", min=0, max=4, step=1,
              getValue=function() return SVal("dispelBorderSize", 2) end,
              setValue=function(v) SSet("dispelBorderSize", v) end },
            { type="dropdown", text="Dispel Icon Position", values=dispelIconPositionValues, order=dispelIconPositionOrder,
              getValue=function()
                  if not SVal("showDispelIcons", false) then return "none" end
                  return SVal("dispelIconPosition", "center")
              end,
              setValue=function(v)
                  if v == "none" then
                      SSet("showDispelIcons", false)
                  else
                      db.profile.showDispelIcons = true
                      SSet("dispelIconPosition", v)
                  end
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        -- Cog for dispel icon offset X/Y
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Dispel Icon Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("dispelIconOffsetX", 0) end,
                      set=function(v) SSet("dispelIconOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("dispelIconOffsetY", 0) end,
                      set=function(v) SSet("dispelIconOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(SVal("showDispelIcons", false) and 0.4 or 0.15)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(SVal("showDispelIcons", false) and 0.4 or 0.15) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 3: Dispel Colors -- five always-active swatches, one per dispel type.
        -- Unlike Name Color (a mode picker), every swatch is independently
        -- editable, so no onClick/refreshAlpha (default click opens the picker).
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Dispel Colors",
              swatches = {
                { tooltip = "Magic", hasAlpha = false,
                  getValue = function() local c = SGet("dispelColorMagic"); if c then return c.r, c.g, c.b end return 0.354, 0.396, 0.74 end,
                  setValue = function(r, g, b) SWrite("dispelColorMagic", { r=r, g=g, b=b }); ReloadAndUpdate() end },
                { tooltip = "Curse", hasAlpha = false,
                  getValue = function() local c = SGet("dispelColorCurse"); if c then return c.r, c.g, c.b end return 0.636, 0.0, 0.64 end,
                  setValue = function(r, g, b) SWrite("dispelColorCurse", { r=r, g=g, b=b }); ReloadAndUpdate() end },
                { tooltip = "Disease", hasAlpha = false,
                  getValue = function() local c = SGet("dispelColorDisease"); if c then return c.r, c.g, c.b end return 0.71, 0.379, 0.0 end,
                  setValue = function(r, g, b) SWrite("dispelColorDisease", { r=r, g=g, b=b }); ReloadAndUpdate() end },
                { tooltip = "Poison", hasAlpha = false,
                  getValue = function() local c = SGet("dispelColorPoison"); if c then return c.r, c.g, c.b end return 0.052, 0.586, 0.62 end,
                  setValue = function(r, g, b) SWrite("dispelColorPoison", { r=r, g=g, b=b }); ReloadAndUpdate() end },
                { tooltip = "Bleed", hasAlpha = false,
                  getValue = function() local c = SGet("dispelColorBleed"); if c then return c.r, c.g, c.b end return 0.75, 0.15, 0.15 end,
                  setValue = function(r, g, b) SWrite("dispelColorBleed", { r=r, g=g, b=b }); ReloadAndUpdate() end },
              } },
            { type="toggle", text="Only Show Dispellable",
              -- Front-end inverse of dispelShowAll: toggle ON = only-mine (dispelShowAll=false).
              getValue=function() return not SVal("dispelShowAll", true) end,
              setValue=function(v) SSet("dispelShowAll", not v) end });  y = y - h

        -- Debuffs section moved to PAGE_DEBUFFS tab
        -------------------------------------------------------------------
        --  RANGE & TOOLTIP
        -------------------------------------------------------------------
        if onSection then onSection("dispels", _secY, y) end; _secY = y
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        -- Row 1: OOR Alpha | Show Tooltip (+ cog for Tooltip in Combat)
        row, h = W:DualRow(parent, y,
            { type="slider", text="Out of Range Alpha", min=10, max=100, step=1,
              getValue=function() return floor((SVal("oorAlpha", 0.4)) * 100) end,
              setValue=function(v)
                  SSet("oorAlpha", v / 100)
                  -- Re-apply range alpha live: SetAlphaFromBoolean bakes the value
                  -- in at call time, so already-OOR units keep the old alpha until
                  -- a range re-eval. Seed all buttons so the slider takes effect now.
                  if ns._RangeSeedAll then ns._RangeSeedAll() end
              end },
            { type="toggle", text="Show Tooltip",
              getValue=function() return SVal("showTooltip", true) end,
              setValue=function(v) SSet("showTooltip", v) end });  y = y - h
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Tooltip Options",
                rows = {
                    { type="toggle", label="Show in Combat",
                      get=function() return SVal("tooltipInCombat", false) end,
                      set=function(v) SSet("tooltipInCombat", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.15)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(SVal("showTooltip", true) and 0.4 or 0.15)
            end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local function UpdateTooltipCog()
                local off = not SVal("showTooltip", true)
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                cogBtn:EnableMouse(not off)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateTooltipCog)
            UpdateTooltipCog()
        end

        -- Hide Blizzard Party Panel. Shares the exact same global setting and
        -- apply function as the QoL module's toggle (EllesmereUIDB.hideBlizzardPartyFrame
        -- -> EllesmereUI._applyHideBlizzardPartyFrame); the QoL toggle is disabled
        -- while Raid Frames is loaded. Default off when unset.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Blizzard Party Panel",
              tooltip="Hides the collapsed Blizzard party/raid sidebar panel on the side of the screen.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideBlizzardPartyFrame = v
                  if EllesmereUI._applyHideBlizzardPartyFrame then
                      EllesmereUI._applyHideBlizzardPartyFrame()
                  end
              end },
            { type="label", text="" });  y = y - h

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

        -------------------------------------------------------------------
        --  PREVIEW MODE DROPDOWN
        -------------------------------------------------------------------
        y = BuildPreviewModeRow(parent, y)

        -------------------------------------------------------------------
        --  FRAME SIZES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FRAME SIZES", y); y = y - h

        -- Row: 20 Man Frame Width | 20 Man Frame Height
        _, h = W:DualRow(parent, y,
            { type="slider", text="20 Man Frame Width", min=40, max=300, step=1,
              getValue=function() return SVal("frameWidth", 72) end,
              setValue=function(v) SSet("frameWidth", v) end },
            { type="slider", text="20 Man Frame Height", min=20, max=150, step=1,
              getValue=function() return SVal("frameHeight", 46) end,
              setValue=function(v) SSet("frameHeight", v) end });  y = y - h

        -- Dynamic rows for each defined custom raid size
        do
            local CUSTOM_TIERS = { 10, 15, 25, 30 }
            local TIER_LABELS = { [10] = "10 Man", [15] = "15 Man", [25] = "25 Man", [30] = "30 Man" }
            local overrides = db.profile.raidSizeOverrides
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
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
                              if not db.profile.raidSizeOverrides then db.profile.raidSizeOverrides = {} end
                              if not db.profile.raidSizeOverrides[tier] then
                                  db.profile.raidSizeOverrides[tier] = { width = v, height = db.profile.frameHeight or 60 }
                              else
                                  db.profile.raidSizeOverrides[tier].width = v
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
                              -- Full reload on drag end to apply indicator scaling
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
                              if not db.profile.raidSizeOverrides then db.profile.raidSizeOverrides = {} end
                              if not db.profile.raidSizeOverrides[tier] then
                                  db.profile.raidSizeOverrides[tier] = { width = db.profile.frameWidth or 125, height = v }
                              else
                                  db.profile.raidSizeOverrides[tier].height = v
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
                              -- Full reload on drag end to apply indicator scaling
                              if not EllesmereUI._sliderDragging then
                                  ReloadAndUpdate()
                              end
                          end });  y = y - h

                    -- Eyeball: left of the row (preview toggle)
                    do
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
                                -- Turn off size preview, restore regular preview if mode allows
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
                                -- _ShowSizePreview handles hiding other previews
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

                    -- Close button: right of the row
                    do
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
                            if db.profile.raidSizeOverrides then
                                db.profile.raidSizeOverrides[tier] = nil
                                if not next(db.profile.raidSizeOverrides) then
                                    db.profile.raidSizeOverrides = nil
                                end
                            end
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage(true)
                        end)
                    end

                    -- Inline cog for X/Y offset (on width slider, RESIZE icon)
                    do
                        local rgn = sizeRow._leftRegion
                        local function EnsureTierOv()
                            if not db.profile.raidSizeOverrides then db.profile.raidSizeOverrides = {} end
                            if not db.profile.raidSizeOverrides[tier] then
                                db.profile.raidSizeOverrides[tier] = { width = db.profile.frameWidth or 125, height = db.profile.frameHeight or 60 }
                            end
                            return db.profile.raidSizeOverrides[tier]
                        end
                        local function TierGrowthChanged()
                            if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                ns._ShowSizePreview(tier)
                            else
                                ReloadAndUpdate()
                            end
                        end
                        local _, cogShow = EllesmereUI.BuildCogPopup({
                            title = EllesmereUI.Lf("%1$s Options", tierLabel),
                            rows = {
                                { type="dropdown", label="Group Growth",
                                  values=growthValues, order=allGrowthOrder,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].groupGrowth or db.profile.groupGrowth or "RIGHT"
                                  end,
                                  set=function(v)
                                      local ov = EnsureTierOv()
                                      ov.groupGrowth = v
                                      -- Enforce perpendicular unit growth
                                      local ug = ov.unitGrowth or db.profile.unitGrowth or "DOWN"
                                      local valid = GetValidUnitGrowths(v)
                                      if not valid[ug] then
                                          ov.unitGrowth = (v == "DOWN" or v == "UP") and "RIGHT" or "DOWN"
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
                                      TierGrowthChanged()
                                  end,
                                  itemDisabled=function(v)
                                      local ov = db.profile.raidSizeOverrides
                                      local gg = ov and ov[tier] and ov[tier].groupGrowth or db.profile.groupGrowth or "RIGHT"
                                      if gg == "DOWN" or gg == "UP" then
                                          return v == "DOWN" or v == "UP"
                                      else
                                          return v == "RIGHT" or v == "LEFT"
                                      end
                                  end },
                                { type="slider", label="X Offset", min=-200, max=200, step=1,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].offsetX or 0
                                  end,
                                  set=function(v)
                                      EnsureTierOv().offsetX = v
                                      if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                          ns._ShowSizePreview(tier)
                                      elseif ns._ApplyTierOffset then
                                          ns._ApplyTierOffset()
                                      end
                                  end },
                                { type="slider", label="Y Offset", min=-200, max=200, step=1,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].offsetY or 0
                                  end,
                                  set=function(v)
                                      EnsureTierOv().offsetY = v
                                      if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                          ns._ShowSizePreview(tier)
                                      elseif ns._ApplyTierOffset then
                                          ns._ApplyTierOffset()
                                      end
                                  end },
                            },
                        })
                        local cogBtn = CreateFrame("Button", nil, rgn)
                        cogBtn:SetSize(26, 26)
                        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                        rgn._lastInline = cogBtn
                        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                        cogBtn:SetAlpha(0.4)
                        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                    end
                end
            end

            -- Row: Add Custom Raid Size | Auto Resize Indicators
            -- Build available tiers (exclude already-added ones)
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

            if #availableTiers > 0 then
                _, h = W:DualRow(parent, y,
                    { type="dropdown", text="Add Custom Raid Size",
                      tooltip="This option allows you to set custom frame sizing and positioning to different raid sizes. Note: This does NOT resize/reposition frames while in combat, if players join/leave mid combat it will resize after combat completes.",
                      values=availableValues, order=availableOrder,
                      getValue=function() return "_select" end,
                      setValue=function(v)
                          local tier = tonumber(v)
                          if not tier then return end
                          if not db.profile.raidSizeOverrides then
                              db.profile.raidSizeOverrides = {}
                          end
                          -- Copy current 20 man size as starting point
                          db.profile.raidSizeOverrides[tier] = {
                              width = db.profile.frameWidth or 125,
                              height = db.profile.frameHeight or 60,
                          }
                          ReloadAndUpdate()
                          EllesmereUI:RefreshPage(true)
                      end },
                    { type="toggle", text="Auto Resize Indicators & Auras",
                      getValue=function() return SVal("autoResizeIndicators", false) end,
                      setValue=function(v) SSet("autoResizeIndicators", v) end });  y = y - h
                -- Tooltip for Auto Resize Indicators
                do
                    local rgn = row and row._rightRegion
                    -- The toggle already has built-in tooltip support via the widget system
                end
            else
                -- All tiers added, just show Auto Resize Indicators
                _, h = W:DualRow(parent, y,
                    { type="label", text="" },
                    { type="toggle", text="Auto Resize Indicators & Auras",
                      getValue=function() return SVal("autoResizeIndicators", false) end,
                      setValue=function(v) SSet("autoResizeIndicators", v) end });  y = y - h
            end
        end

        -------------------------------------------------------------------
        --  FRAME DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FRAME DISPLAY", y); y = y - h

        -- Row 2: Frame Spacing | Group Spacing
        _, h = W:DualRow(parent, y,
            { type="slider", text="Frame Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("cellSpacing", 2) end,
              setValue=function(v) SSet("cellSpacing", v) end },
            { type="slider", text="Group Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("groupSpacing", 8) end,
              setValue=function(v) SSet("groupSpacing", v) end });  y = y - h

        -- Border Style (+ offset cog) | Border Size (+ Border swatch)
        -- Mirrors Unit Frames: one border, recolored by state (hover/target).
        -- Hover + Target swatches live on the "Hover Borders" row below.
        -- Full SharedMedia texture support.
        local bdrTexValues, bdrTexOrder = EllesmereUI.GetBorderTextureDropdown()
        local borderStyleRow
        borderStyleRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style", values=bdrTexValues, order=bdrTexOrder,
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
                  ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Border Size", min=0, max=4, step=1,
              getValue=function() return SVal("borderSize", 1) end,
              setValue=function(v) SSet("borderSize", v) end });  y = y - h
        -- Offset cog on Border Style (left region): Offset X/Y, Shift X/Y, Show Behind
        do
            local rgn = borderStyleRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Offset",
                rows = {
                    { type="slider", label="Offset X", min=-10, max=10, step=1,
                      get=function()
                          local v = SGet("borderTextureOffset"); if v then return v end
                          local dox = EllesmereUI.GetBorderDefaults("unitframes", SGet("borderTexture") or "solid", SVal("borderSize", 1))
                          return dox
                      end,
                      set=function(v) SSet("borderTextureOffset", v) end },
                    { type="slider", label="Offset Y", min=-10, max=10, step=1,
                      get=function()
                          local v = SGet("borderTextureOffsetY"); if v then return v end
                          local _, doy = EllesmereUI.GetBorderDefaults("unitframes", SGet("borderTexture") or "solid", SVal("borderSize", 1))
                          return doy
                      end,
                      set=function(v) SSet("borderTextureOffsetY", v) end },
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
            local function UpdateCogVis()
                local tex = SGet("borderTexture") or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        -- Swatch on Border Size (right region): Border color (nearest slider).
        -- Hover + Target swatches moved to the "Hover Borders" row below.
        do
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

        -- Show When Solo (left) | Hover Borders (right, below Border Size): which
        -- highlight states are active. Disabling one skips that recolor entirely
        -- (the frame keeps its normal border). Hover + Target swatches inline.
        local hoverBordersRow
        hoverBordersRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show When Solo",
              disabled=function() return db.profile.partyShowWhenSolo end,
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
        do
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

            -- Inline swatches: Hover (nearest the dropdown), then Target to its left
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

            -- Gray a swatch when its border state is disabled (still clickable so
            -- the color can be pre-set), matching the Heal Prediction swatch.
            UpdateHBSwatchVis = function()
                hoverSwatch:SetAlpha(SVal("hoverBorderEnabled", true) and 1 or 0.3)
                targetSwatch:SetAlpha(SVal("targetBorderEnabled", true) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updHover(); updTarget(); UpdateHBSwatchVis() end)
            UpdateHBSwatchVis()
        end

        -------------------------------------------------------------------
        --  LAYOUT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h

        -- Row 1: Group Growth | Unit Growth (perpendicular constraint)
        -- Both show all 4 directions; same-axis options are disabled.
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Group Growth", values=growthValues, order=allGrowthOrder,
              getValue=function() return SVal("groupGrowth", "RIGHT") end,
              setValue=function(v)
                  SSet("groupGrowth", v)
                  -- Enforce perpendicular: fix unitGrowth if now on same axis
                  local ug = SVal("unitGrowth", "DOWN")
                  local valid = GetValidUnitGrowths(v)
                  if not valid[ug] then
                      if v == "DOWN" or v == "UP" then
                          SSet("unitGrowth", "RIGHT")
                      else
                          SSet("unitGrowth", "DOWN")
                      end
                  end
              end },
            { type="dropdown", text="Unit Growth", values=growthValues, order=allGrowthOrder,
              getValue=function() return SVal("unitGrowth", "DOWN") end,
              setValue=function(v) SSet("unitGrowth", v) end,
              itemDisabled=function(v)
                  local gg = SVal("groupGrowth", "RIGHT")
                  if gg == "DOWN" or gg == "UP" then
                      return v == "DOWN" or v == "UP"
                  else
                      return v == "RIGHT" or v == "LEFT"
                  end
              end,
              itemDisabledTooltip=function()
                  return "This option requires a perpendicular Group Growth"
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
                  disabled=function() return SVal("mergeGroups", false) end,
                  disabledTooltip="Not available with Merge Groups enabled", rawTooltip=true,
                  setValue=function(v)
                      SSet("showSelfFirst", v == "first")
                      SSet("showSelfLast", v == "last")
                      EllesmereUI:RefreshPage()
                  end });  y = y - h

            -- Replace the placeholder left dropdown with the shared custom Sort
            -- By control (Group/Role radio + drag-to-reorder roles), wired to the
            -- raid keys.
            BuildSortByControl(sortRow._leftRegion, {
                readMode   = function() return SVal("sortMode", "INDEX") end,
                writeMode  = function(v) SSet("sortMode", v) end,
                readRoles  = function() return SVal("roleOrder", { "TANK", "HEALER", "DAMAGER" }) end,
                writeRoles = function(ro) db.profile.roleOrder = ro; ReloadAndUpdate() end,
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
                  setValue=function(v) SSet("mergeGroups", v); EllesmereUI:RefreshPage() end });  y = y - h

            -- Replace the left dropdown with a checkbox dropdown for groups 1-8
            local rgn = showGroupsRow._leftRegion
            if rgn._control then rgn._control:Hide() end

            local groupItems = {}
            for i = 1, 8 do
                groupItems[i] = { key = i, label = "Group " .. i }
            end

            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                groupItems,
                function(k)
                    local vg = db.profile.visibleGroups
                    return vg and vg[k] ~= false
                end,
                function(k, v)
                    if not db.profile.visibleGroups then
                        db.profile.visibleGroups = { true, true, true, true, true, true, false, false }
                    end
                    db.profile.visibleGroups[k] = v
                    ReloadAndUpdate()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end


        y = BuildVisualSections(parent, y, W)


        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Party page
    ---------------------------------------------------------------------------
    -- Party reuses the shared BuildPreviewModeRow (same previewMode setting + pvModeDropdowns)

    -- Forward declaration (defined after BuildPartyPage)
    local BuildDebuffSections

    local function PartyReloadAndUpdate()
        -- Reload real party frames (handles container sizing internally)
        if ns.ReloadPartyFrames then
            ns.ReloadPartyFrames()
        end
        -- Refresh party preview visuals
        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
            ns.ShowPartyPreview()
        end
    end

    local function PSSet(key, val)
        db.profile[key] = val
        -- Visibility-affecting keys: update showSolo attribute directly
        -- (_UpdatePartyVisibility bails out when preview is active)
        if key == "partyShowWhenSolo" and ns._partyHeader and not InCombatLockdown() then
            ns._partyHeader:SetAttribute("showSolo", val or false)
        end
        -- Lightweight resize for dimension keys
        if (key == "partyFrameWidth" or key == "partyFrameHeight") and ns._ResizePartyButtons then
            local w = db.profile.partyFrameWidth or db.profile.frameWidth or 125
            local h = db.profile.partyFrameHeight or db.profile.frameHeight or 60
            ns._ResizePartyButtons(w, h)
            -- Refresh preview if active (no full reload needed)
            if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
                ns.ShowPartyPreview()
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

        -------------------------------------------------------------------
        --  PREVIEW MODE DROPDOWN
        -------------------------------------------------------------------
        y = BuildPreviewModeRow(parent, y)

        -------------------------------------------------------------------
        --  RAID SYNC AND SOLO
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "RAID SYNC AND SOLO", y); y = y - h

        -- Row 1: Use Raid Settings For (checkbox dropdown) | Show When Solo
        local SECTION_ORDER = ns._PARTY_SECTION_ORDER or {}
        local SECTION_LABELS = ns._PARTY_SECTION_LABELS or {}

        local syncItems = {}
        for _, secKey in ipairs(SECTION_ORDER) do
            syncItems[#syncItems + 1] = { key = secKey, label = SECTION_LABELS[secKey] or secKey }
        end

        local syncRow
        syncRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Use Raid Settings For",
              values={ _placeholder = "..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Show When Solo",
              disabled=function() return db.profile.showWhenSolo end,
              disabledTooltip="Raid Frames Show When Solo", requireState="disabled",
              getValue=function() return SVal("partyShowWhenSolo", false) end,
              setValue=function(v)
                  PSSet("partyShowWhenSolo", v)
                  EllesmereUI:RefreshPage()
              end });  y = y - h

        -- Inline cog on Show When Solo: Center When Solo
        do
            local rgn = syncRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Raid Frames Show When Solo"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSoloCogDis()
                -- Disabled when the Show When Solo toggle itself is disabled
                -- (i.e. Raid Frames Show When Solo is on, so party never shows solo).
                if db.profile.showWhenSolo then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateSoloCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateSoloCogDis)
            UpdateSoloCogDis()
        end

        -- Replace the left dropdown with a checkbox dropdown for per-section sync
        do
            local rgn = syncRow._leftRegion
            if rgn._control then rgn._control:Hide() end

            local syncDD  -- forward declare so setter closure can reference it
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                syncItems,
                function(k)
                    -- Checked = synced (using raid settings)
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
                        -- Toggle overlay directly (no page rebuild needed)
                        local ov = ns._syncOverlays and ns._syncOverlays[k]
                        if ov then
                            if v then ov:Show() else ov:Hide() end
                        end
                        -- Refresh party frames + preview (proxy now reads different values)
                        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
                        if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
                            ns.ShowPartyPreview()
                        end
                        -- Update dropdown label text
                        if ns._syncDDRefresh then ns._syncDDRefresh() end
                    end

                    -- Re-syncing: check if custom party values exist that would be lost
                    if v then
                        local hasCustom = false
                        for key, section in pairs(ns._PARTY_KEY_SECTION) do
                            if section == k and rawget(db.profile, "party_" .. key) ~= nil then
                                hasCustom = true
                                break
                            end
                        end
                        if hasCustom then
                            -- Close the dropdown menu before showing popup
                            if syncDD and syncDD._ddMenu then syncDD._ddMenu:Hide() end
                            EllesmereUI:ShowConfirmPopup({
                                title = EllesmereUI.Lf("Re-sync %1$s?", SECTION_LABELS[k] or k),
                                message = "This will discard your custom party settings for this section and use raid settings instead.",
                                confirmText = "Sync",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    -- Delete custom party keys for this section
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
            syncDD = cbDD  -- assign after BuildVisOptsCBDropdown returns
            ns._syncDDRefresh = cbDDRefresh
        end

        -------------------------------------------------------------------
        --  FRAMES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FRAMES", y); y = y - h

        -- Row 2: Frame Width | Frame Height
        _, h = W:DualRow(parent, y,
            { type="slider", text="Frame Width", min=40, max=300, step=1,
              getValue=function() return SVal("partyFrameWidth", 125) end,
              setValue=function(v) PSSet("partyFrameWidth", v) end },
            { type="slider", text="Frame Height", min=20, max=150, step=1,
              getValue=function() return SVal("partyFrameHeight", 60) end,
              setValue=function(v) PSSet("partyFrameHeight", v) end });  y = y - h

        -- Row 3: Horizontal Frames | Sort By (custom dropdown with drag-to-reorder
        -- roles -- identical control to the raid LAYOUT tab, wired to party keys)
        local pSortRow
        pSortRow, h = W:DualRow(parent, y,
            { type="toggle", text="Horizontal Frames",
              getValue=function() return db.profile.partyHorizontal end,
              setValue=function(v) db.profile.partyHorizontal = v; PartyReloadAndUpdate() end },
            { type="dropdown", text="Sort By",
              values={ __placeholder = "Group" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h

        BuildSortByControl(pSortRow._rightRegion, {
            readMode   = function() return SVal("partySortMode", "ROLE") end,
            writeMode  = function(v) PSSet("partySortMode", v) end,
            readRoles  = function() return db.profile.partyRoleOrder or db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" } end,
            writeRoles = function(ro) db.profile.partyRoleOrder = ro; PartyReloadAndUpdate() end,
        })

        -- Row 4: Self Position | Hide Self
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

        -- Row 5: Auto Resize Indicators & Auras | Frame Spacing
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Resize Indicators & Auras",
              getValue=function() return SVal("partyAutoResizeIndicators", false) end,
              setValue=function(v) PSSet("partyAutoResizeIndicators", v) end },
            { type="slider", text="Frame Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("partyCellSpacing", db.profile.cellSpacing or 2) end,
              setValue=function(v) PSSet("partyCellSpacing", v) end });  y = y - h

        -------------------------------------------------------------------
        --  ALL VISUAL SECTIONS
        --  _partyCtx makes SGet/SSet/SVal read/write "party_<key>" keys,
        --  so the exact same section builders produce party-specific controls.
        --  Synced sections get a blocking overlay per-section.
        -------------------------------------------------------------------
        local CPAD = EllesmereUI.CONTENT_PAD or 10
        local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"

        local syncOverlays = {}
        ns._syncOverlays = syncOverlays

        local function SyncOverlay(sectionKey, startY, endY)
            local hdrH = 40  -- SectionHeader height
            local contentStart = startY - hdrH
            local ov = CreateFrame("Frame", nil, parent)
            ov._searchIgnore = true  -- inline search must never re-anchor/collapse it
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
            -- Hover: accent the text so users know the overlay is clickable.
            ov:SetScript("OnEnter", function()
                local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
                label:SetTextColor(eg.r, eg.g, eg.b, 1)
            end)
            ov:SetScript("OnLeave", function() label:SetTextColor(1, 1, 1, 0.56) end)
            -- Click to unsync this section (switch to custom party settings).
            -- Mirrors unchecking it in the "Use Raid Settings For" dropdown.
            ov:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end
                if not db.profile.partySyncSections then db.profile.partySyncSections = {} end
                db.profile.partySyncSections[sectionKey] = false
                self:Hide()
                if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
                if ns.partyPvActive and ns.partyPvActive() and ns.ShowPartyPreview then
                    ns.ShowPartyPreview()
                end
                if ns._syncDDRefresh then ns._syncDDRefresh() end
            end)
            syncOverlays[sectionKey] = ov
            -- Show only if section is synced
            local ss = db.profile.partySyncSections
            if ss and ss[sectionKey] == false then ov:Hide() end
        end

        _partyCtx = true
        y = BuildVisualSections(parent, y, W, SyncOverlay)
        y = BuildDebuffSections(parent, y, W, SyncOverlay)
        -- Do NOT reset _partyCtx here; the SelectPage hook manages it.
        -- Resetting it would break SSet after any RefreshPage on the party tab.

        return math.abs(y)
    end


    ---------------------------------------------------------------------------
    --  Debuff settings sections (shared by debuffs page)
    ---------------------------------------------------------------------------
    BuildDebuffSections = function(parent, y, W, onSection)
        local row, h, _
        local _secY = y
        -------------------------------------------------------------------
        --  DEFENSIVES & EXTERNALS
        -------------------------------------------------------------------
        local defHeader
        defHeader, h = W:SectionHeader(parent, "DEFENSIVES & EXTERNALS", y); y = y - h

        -- Eyeball: toggle defensive visibility on preview (raid + party)
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local defLabel
            for _, rgn in ipairs({ defHeader:GetRegions() }) do
                if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "DEFENSIVES & EXTERNALS" then
                    defLabel = rgn; break
                end
            end
            local eyeBtn = CreateFrame("Button", nil, defHeader)
            eyeBtn:SetSize(24, 24)
            if defLabel then
                eyeBtn:SetPoint("LEFT", defLabel, "RIGHT", 5, 0)
            else
                eyeBtn:SetPoint("LEFT", defHeader, "BOTTOMLEFT", 200, 8)
            end
            eyeBtn:SetFrameLevel(defHeader:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()

            if ns._defensivesPreviewVisible == nil then ns._defensivesPreviewVisible = false end
            local function RefreshDefEye()
                if IsPreviewOff() then
                    eyeTex:SetTexture(EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.15)
                    return
                end
                eyeTex:SetTexture(ns._defensivesPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
                eyeBtn:SetAlpha(0.4)
            end
            RefreshDefEye()
            eyeBtn:SetScript("OnClick", function()
                if IsPreviewOff() then return end
                ns._defensivesPreviewVisible = not ns._defensivesPreviewVisible
                RefreshDefEye()
                if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if IsPreviewOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                    return
                end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._defensivesPreviewVisible and "Hide defensives on preview" or "Show defensives on preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                if not IsPreviewOff() then self:SetAlpha(0.4) end
                EllesmereUI.HideWidgetTooltip()
            end)
        end  -- close do (eyeball)

        -- Shared disabled check for defensive settings
        local function DefDisabled()
            return not SVal("showDefensives", true) and not SVal("showExternals", true)
        end

        local defPosValues = {
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
        local defPosOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

        local defGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
        local defGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

        local function GetDefaultDefGrow(pos)
            if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
            if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
            if pos == "top" then return "DOWN" end
            if pos == "bottom" then return "UP" end
            return "CENTER"
        end

        -- Row 1: Show Defensives & Externals | Position (+ cog X/Y)
        local defShowItems = {
            { key = "defensives", label = "Defensives" },
            { key = "externals",  label = "Externals" },
        }
        local defShowKeyMap = { defensives = "showDefensives", externals = "showExternals" }
        local defShowRow
        defShowRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Defensives & Externals",
              values={ __placeholder = "Both" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="dropdown", text="Position", values=defPosValues, order=defPosOrder,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defPosition", "center") end,
              setValue=function(v)
                  SSet("defPosition", v)
                  SSet("defGrowDirection", GetDefaultDefGrow(v))
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        -- Replace left with CB dropdown
        do
            local rgn = defShowRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                defShowItems,
                function(k) return SVal(defShowKeyMap[k], true) end,
                function(k, v)
                    SSet(defShowKeyMap[k], v)
                    if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
        end
        -- Cog for position offset X/Y
        do
            local rgn = defShowRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Defensive Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("defOffsetX", 0) end,
                      set=function(v) SSet("defOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("defOffsetY", 0) end,
                      set=function(v) SSet("defOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(DefDisabled() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(DefDisabled() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 2: Growth Direction | Size
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Growth Direction", values=defGrowValues, order=defGrowOrder,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defGrowDirection", "CENTER") end,
              setValue=function(v) SSet("defGrowDirection", v) end },
            { type="slider", text="Size", min=10, max=40, step=1,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defSize", 22) end,
              setValue=function(v) SSet("defSize", v) end });  y = y - h

        -- Row 3: Spacing | Border Size (+ swatch)
        local defBdrRow
        defBdrRow, h = W:DualRow(parent, y,
            { type="slider", text="Spacing", min=0, max=10, step=1,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defSpacing", 1) end,
              setValue=function(v) SSet("defSpacing", v) end },
            { type="slider", text="Border Size", min=0, max=4, step=1, trackWidth=120,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defBorderSize", 1) end,
              setValue=function(v) SSet("defBorderSize", v) end });  y = y - h
        -- Inline swatch for border color
        do
            local rgn = defBdrRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, defBdrRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("defBorderColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 0, 0, 0, 1
                end,
                function(r, g, b)
                    SWrite("defBorderColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end

        -- Row 4: Show Duration Swipe (+ swatch) | Show Duration Text (+ swatch + cog)
        local defDurRow
        defDurRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Duration Swipe",
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defShowSwipe", true) end,
              setValue=function(v) SSet("defShowSwipe", v) end },
            { type="toggle", text="Show Duration Text",
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defShowDurText", false) end,
              setValue=function(v) SSet("defShowDurText", v) end });  y = y - h
        -- Inline swatch + cog for duration text
        do
            local rgn = defDurRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, defDurRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("defDurTextColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    SWrite("defDurTextColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type="slider", label="Text Size", min=6, max=18, step=1,
                      get=function() return SVal("defDurTextSize", 8) end,
                      set=function(v) SSet("defDurTextSize", v) end },
                    { type="slider", label="Offset X", min=-20, max=20, step=1,
                      get=function() return SVal("defDurTextOffsetX", 0) end,
                      set=function(v) SSet("defDurTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-20, max=20, step=1,
                      get=function() return SVal("defDurTextOffsetY", 0) end,
                      set=function(v) SSet("defDurTextOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -------------------------------------------------------------------
        --  PRIVATE AURAS
        -------------------------------------------------------------------
        local paHeader
        if onSection then onSection("defensives", _secY, y) end; _secY = y
        paHeader, h = W:SectionHeader(parent, "PRIVATE AURAS", y); y = y - h

        -- Eyeball: toggle private aura visibility on preview (raid + party)
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local paLabel
            for _, rgn in ipairs({ paHeader:GetRegions() }) do
                if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "PRIVATE AURAS" then
                    paLabel = rgn; break
                end
            end
            local eyeBtn = CreateFrame("Button", nil, paHeader)
            eyeBtn:SetSize(24, 24)
            if paLabel then
                eyeBtn:SetPoint("LEFT", paLabel, "RIGHT", 5, 0)
            else
                eyeBtn:SetPoint("LEFT", paHeader, "BOTTOMLEFT", 85, 8)
            end
            eyeBtn:SetFrameLevel(paHeader:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()

            if ns._privateAurasPreviewVisible == nil then ns._privateAurasPreviewVisible = false end
            local function RefreshPaEye()
                if IsPreviewOff() then
                    eyeTex:SetTexture(EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.15)
                    return
                end
                eyeTex:SetTexture(ns._privateAurasPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
                eyeBtn:SetAlpha(0.4)
            end
            RefreshPaEye()
            eyeBtn:SetScript("OnClick", function()
                if IsPreviewOff() then return end
                ns._privateAurasPreviewVisible = not ns._privateAurasPreviewVisible
                RefreshPaEye()
                if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if IsPreviewOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                    return
                end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._privateAurasPreviewVisible and "Hide private auras on preview" or "Show private auras on preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                if not IsPreviewOff() then self:SetAlpha(0.4) end
                EllesmereUI.HideWidgetTooltip()
            end)
        end  -- close do (eyeball)

        local paPosValues = {
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
        local paPosOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
        local paGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
        local paGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN" }

        local function GetDefaultPaGrow(pos)
            if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
            if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
            if pos == "top" then return "DOWN" end
            if pos == "bottom" then return "UP" end
            return "RIGHT"
        end

        -- Row 1: Position (+ cog X/Y) | Growth Direction
        local paRow1
        paRow1, h = W:DualRow(parent, y,
            { type="dropdown", text="Position", values=paPosValues, order=paPosOrder,
              getValue=function() return SVal("paPosition", "center") end,
              setValue=function(v)
                  SSet("paPosition", v)
                  SSet("paGrowDirection", GetDefaultPaGrow(v))
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Growth Direction", values=paGrowValues, order=paGrowOrder,
              getValue=function() return SVal("paGrowDirection", "RIGHT") end,
              setValue=function(v) SSet("paGrowDirection", v) end });  y = y - h
        ns._editTargets = ns._editTargets or {}
        ns._editTargets.privateAuras = paRow1
        -- Cog for position offset X/Y
        do
            local rgn = paRow1._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Private Aura Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("paOffsetX", 0) end,
                      set=function(v) SSet("paOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("paOffsetY", 0) end,
                      set=function(v) SSet("paOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 2: Icon Size | Spacing
        _, h = W:DualRow(parent, y,
            { type="slider", text="Icon Size", min=10, max=40, step=1,
              getValue=function() return SVal("paSize", 20) end,
              setValue=function(v) SSet("paSize", v) end },
            { type="slider", text="Spacing", min=0, max=10, step=1,
              getValue=function() return SVal("paSpacing", 0) end,
              setValue=function(v) SSet("paSpacing", v) end });  y = y - h

        -- Row 3: Show Countdown Text (Border Size removed -- Blizzard's border is
        -- always scaled 1:1 to the icon; no longer user-configurable)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Countdown Text",
              getValue=function() return SVal("paShowCountdown", false) end,
              setValue=function(v) SSet("paShowCountdown", v) end },
            { type="label", text="" });  y = y - h

        -------------------------------------------------------------------
        --  DEBUFFS
        -------------------------------------------------------------------
        --  DEBUFF DISPLAY
        -------------------------------------------------------------------
        local debuffHeader
        if onSection then onSection("privateAuras", _secY, y) end; _secY = y
        debuffHeader, h = W:SectionHeader(parent, "DEBUFF DISPLAY", y); y = y - h

        -- Eyeball: toggle debuff visibility on preview (raid + party)
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local dbLabel
            for _, rgn in ipairs({ debuffHeader:GetRegions() }) do
                if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "DEBUFF DISPLAY" then
                    dbLabel = rgn; break
                end
            end
            local eyeBtn = CreateFrame("Button", nil, debuffHeader)
            eyeBtn:SetSize(24, 24)
            if dbLabel then
                eyeBtn:SetPoint("LEFT", dbLabel, "RIGHT", 5, 0)
            else
                eyeBtn:SetPoint("LEFT", debuffHeader, "BOTTOMLEFT", 85, 8)
            end
            eyeBtn:SetFrameLevel(debuffHeader:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()

            if ns._debuffsPreviewVisible == nil then ns._debuffsPreviewVisible = false end
            local function RefreshDbEye()
                if IsPreviewOff() then
                    eyeTex:SetTexture(EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.15)
                    return
                end
                eyeTex:SetTexture(ns._debuffsPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
                eyeBtn:SetAlpha(0.4)
            end
            RefreshDbEye()
            eyeBtn:SetScript("OnClick", function()
                if IsPreviewOff() then return end
                ns._debuffsPreviewVisible = not ns._debuffsPreviewVisible
                RefreshDbEye()
                if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if IsPreviewOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                    return
                end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._debuffsPreviewVisible and "Hide debuffs on preview" or "Show debuffs on preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                if not IsPreviewOff() then self:SetAlpha(0.4) end
                EllesmereUI.HideWidgetTooltip()
            end)
        end  -- close do (eyeball)

        -- Row 1: Show Debuffs | Show Lust Debuff
        local debuffFilterValues = {
            none        = "None",
            all         = "All",
            raid        = "Raid Debuffs Only",
            dispellable = "Dispellable Only",
        }
        local debuffFilterOrder = { "none", "all", "raid", "dispellable" }
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Debuffs", values=debuffFilterValues, order=debuffFilterOrder,
              getValue=function() return SVal("debuffFilter", "all") end,
              setValue=function(v) SSet("debuffFilter", v); EllesmereUI:RefreshPage() end },
            { type="toggle", text="Show Lust Debuff",
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return not SVal("hideLustDebuff", true) end,
              setValue=function(v) SSet("hideLustDebuff", not v) end });  y = y - h

        -- Row 2: Debuff Position (+ cog for X/Y) | Growth Direction
        local debuffPositionValues = {
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
        local debuffPositionOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

        local debuffGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
        local debuffGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

        local function GetDefaultDebuffGrow(pos)
            if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
            if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
            if pos == "top" then return "DOWN" end
            if pos == "bottom" then return "UP" end
            return "RIGHT"
        end

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Debuff Position", values=debuffPositionValues, order=debuffPositionOrder,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffPosition", "bottomleft") end,
              setValue=function(v)
                  SSet("debuffPosition", v)
                  SSet("debuffGrowDirection", GetDefaultDebuffGrow(v))
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Growth Direction", values=debuffGrowValues, order=debuffGrowOrder,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffGrowDirection", "RIGHT") end,
              setValue=function(v) SSet("debuffGrowDirection", v) end });  y = y - h
        -- Cog for debuff offset X/Y
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Debuff Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("debuffOffsetX", 0) end,
                      set=function(v) SSet("debuffOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("debuffOffsetY", 0) end,
                      set=function(v) SSet("debuffOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha((SVal("debuffFilter", "all") ~= "none") and 0.4 or 0.15)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha((SVal("debuffFilter", "all") ~= "none") and 0.4 or 0.15) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 3: Max Debuffs | (empty)
        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Debuffs", min=1, max=8, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffCap", 3) end,
              setValue=function(v) SSet("debuffCap", v) end },
            { type="label", text="" });  y = y - h

        -------------------------------------------------------------------
        --  DEBUFF STYLE
        -------------------------------------------------------------------
        if onSection then onSection("debuffDisplay", _secY, y) end; _secY = y
        _, h = W:SectionHeader(parent, "DEBUFF STYLE", y); y = y - h

        -- Row 1: Debuff Size | Border Size (+ swatch)
        local dbBorderRow
        dbBorderRow, h = W:DualRow(parent, y,
            { type="slider", text="Debuff Size", min=10, max=40, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffSize", 18) end,
              setValue=function(v) SSet("debuffSize", v) end },
            { type="slider", text="Border Size", min=0, max=4, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffBorderSize", 1) end,
              setValue=function(v) SSet("debuffBorderSize", v) end });  y = y - h
        -- Inline swatch for border color
        do
            local rgn = dbBorderRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, dbBorderRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("debuffBorderColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 0, 0, 0, 1
                end,
                function(r, g, b)
                    SWrite("debuffBorderColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end

        -- Row 2: Spacing | Show Stacks (+ swatch + cog)
        local dbStacksRow
        dbStacksRow, h = W:DualRow(parent, y,
            { type="slider", text="Spacing", min=0, max=10, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffSpacing", 1) end,
              setValue=function(v) SSet("debuffSpacing", v) end },
            { type="toggle", text="Show Stacks",
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffShowStacks", true) end,
              setValue=function(v) SSet("debuffShowStacks", v) end });  y = y - h
        -- Inline swatch for stacks color
        do
            local rgn = dbStacksRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, dbStacksRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("debuffStacksTextColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    SWrite("debuffStacksTextColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end
        -- Cog for stacks size/offset
        do
            local rgn = dbStacksRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Stacks Text",
                rows = {
                    { type="slider", label="Text Size", min=6, max=18, step=1,
                      get=function() return SVal("debuffStacksTextSize", 8) end,
                      set=function(v) SSet("debuffStacksTextSize", v) end },
                    { type="slider", label="Offset X", min=-20, max=20, step=1,
                      get=function() return SVal("debuffStacksOffsetX", 0) end,
                      set=function(v) SSet("debuffStacksOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-20, max=20, step=1,
                      get=function() return SVal("debuffStacksOffsetY", 0) end,
                      set=function(v) SSet("debuffStacksOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.15)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(SVal("debuffShowStacks", true) and 0.4 or 0.15) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 3: Duration Swipe | Duration Text (+ swatch + cog)
        local dbDurRow
        dbDurRow, h = W:DualRow(parent, y,
            { type="toggle", text="Duration Swipe",
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffShowSwipe", true) end,
              setValue=function(v) SSet("debuffShowSwipe", v) end },
            { type="toggle", text="Duration Text",
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffShowDurText", false) end,
              setValue=function(v) SSet("debuffShowDurText", v) end });  y = y - h
        -- Inline swatch + cog for duration text
        do
            local rgn = dbDurRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, dbDurRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("debuffDurTextColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    SWrite("debuffDurTextColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type="slider", label="Text Size", min=6, max=18, step=1,
                      get=function() return SVal("debuffDurTextSize", 8) end,
                      set=function(v) SSet("debuffDurTextSize", v) end },
                    { type="slider", label="Offset X", min=-20, max=20, step=1,
                      get=function() return SVal("debuffDurTextOffsetX", 0) end,
                      set=function(v) SSet("debuffDurTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-20, max=20, step=1,
                      get=function() return SVal("debuffDurTextOffsetY", 0) end,
                      set=function(v) SSet("debuffDurTextOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        if onSection then onSection("debuffStyle", _secY, y) end
        return y
    end

    ---------------------------------------------------------------------------
    --  Defensives & Debuffs page
    ---------------------------------------------------------------------------
    local function BuildDebuffsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset or -6
        local row, h, _

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  PREVIEW MODE DROPDOWN
        -------------------------------------------------------------------
        y = BuildPreviewModeRow(parent, y)


        y = BuildDebuffSections(parent, y, W)


        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Buff Manager page (placeholder)
    ---------------------------------------------------------------------------
    local function BuildBuffManagerPage(pageName, parent, yOffset)
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
            -- Fade out
            testModeFrame:SetAlpha(1)
            local fadeOutAG = testModeFrame:CreateAnimationGroup()
            local fadeOutA = fadeOutAG:CreateAnimation("Alpha")
            fadeOutA:SetFromAlpha(1); fadeOutA:SetToAlpha(0); fadeOutA:SetDuration(0.3)
            testModeFrame:SetAlpha(0)
            fadeOutAG:SetScript("OnFinished", function() testModeFrame:Hide() end)
            fadeOutAG:Play()
        end
        -- Reset all preview flags
        ns._indicatorsVisible = false
        ns._dispelsVisible = false
        ns._defensivesPreviewVisible = false
        ns._debuffsPreviewVisible = false
        ns._privateAurasPreviewVisible = false
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
        -- Hide overlay container immediately (dimmer fade masks it)
        if ns._overlayContainer then ns._overlayContainer:Hide() end
        if ns.HidePreview then ns.HidePreview() end
        -- Re-show preview if on the right tab
        local activePage = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        if activePage == PAGE_MAIN or activePage == PAGE_DEBUFFS then
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
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local accentColor = EllesmereUI.ACCENT_COLOR or { r = 0.05, g = 0.82, b = 0.62 }
        local s = db.profile

        -- Dimmer
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

        -- Clean old children
        for _, c in ipairs({testModeFrame:GetChildren()}) do c:Hide(); c:SetParent(nil) end

        -- Preview flags will be set by ns._applyTestState() below

        -- Fade in the dimmer
        local fadeInAG = testModeFrame:CreateAnimationGroup()
        local fadeInA = fadeInAG:CreateAnimation("Alpha")
        fadeInA:SetFromAlpha(0); fadeInA:SetToAlpha(1); fadeInA:SetDuration(0.3)
        testModeFrame:SetAlpha(1)
        fadeInAG:Play()

        -- Force preview to show (overlay mode forced via ns._testMode)
        if ns.HidePreview then ns.HidePreview() end
        C_Timer.After(0, function()
            if ns.ShowPreview and ns._testMode then
                ns.ShowPreview()
                -- Re-apply test state now that preview frames exist and previewActive is true
                if ns._applyTestState then ns._applyTestState() end
                -- Reanchor panel + fade in sidebar after overlay container is positioned
                C_Timer.After(0, function()
                    if not ns._testMode then return end
                    local oc = ns._overlayContainer
                    if oc and oc:IsShown() and ns._testPanel then
                        ns._testPanel:ClearAllPoints()
                        ns._testPanel:SetPoint("RIGHT", oc, "LEFT", -20, 0)
                        -- Fade in the sidebar
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

        -- Left panel with checkboxes
        local PANEL_W = 260
        local ROW_H = 32
        local PAD = 16
        local panel = CreateFrame("Frame", nil, testModeFrame)
        ns._testPanel = panel
        panel:SetSize(PANEL_W, 600)
        panel:SetPoint("LEFT", testModeFrame, "LEFT", 40, 0)
        panel:Hide()  -- hidden until overlay container is positioned
        panel:SetFrameLevel(testModeFrame:GetFrameLevel() + 5)
        local panelBg = panel:CreateTexture(nil, "BACKGROUND")
        panelBg:SetAllPoints(); panelBg:SetColorTexture(15/255, 17/255, 22/255, 0.9)
        EllesmereUI.MakeBorder(panel, 1, 1, 1, 0.1, PP)

        local function MakeFont(p, size, r, g, b, a)
            local fs = p:CreateFontString(nil, "OVERLAY")
            fs:SetFont(fontPath, size, "")
            fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        local cy = -PAD

        -- Section header
        local function SectionHeader(text)
            cy = cy - 10
            local lbl = MakeFont(panel, 11, 1, 1, 1, 0.75)
            lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, cy)
            lbl:SetText(text)
            local line = panel:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            line:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
            line:SetColorTexture(1, 1, 1, 0.06)
            cy = cy - 15
        end

        -- Collect all checkbox refresh functions for mutual exclusion updates
        local allRefreshFns = {}

        -- Checkbox row builder
        local function CheckboxRow(label, getVal, setVal, editTarget)
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(PANEL_W - PAD * 2, ROW_H)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, cy)
            row:SetFrameLevel(panel:GetFrameLevel() + 1)

            -- Checkbox
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

            -- Label (clickable, toggles checkbox)
            local lblBtn = CreateFrame("Button", nil, row)
            lblBtn:SetPoint("LEFT", cb, "RIGHT", 8, 0)
            lblBtn:SetPoint("RIGHT", row, "RIGHT", -50, 0)
            lblBtn:SetHeight(ROW_H)
            lblBtn:SetScript("OnClick", DoToggle)
            local lbl = MakeFont(lblBtn, 11, 1, 1, 1, 0.85)
            lbl:SetPoint("LEFT")
            lbl:SetText(label)

            -- Edit button
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
                        -- Scroll to + highlight the target row after page builds
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
                                -- Glow effect
                                C_Timer.After(0.15, function()
                                    if not target:IsShown() then return end
                                    local ac = EllesmereUI.ACCENT_COLOR or EllesmereUI.ELLESMERE_GREEN
                                    if not ac then return end
                                    local glow = CreateFrame("Frame", nil, target)
                                    glow:SetAllPoints()
                                    glow:SetFrameLevel(target:GetFrameLevel() + 5)
                                    local px = 2
                                    local top = glow:CreateTexture(nil, "OVERLAY", nil, 7)
                                    top:SetHeight(px); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
                                    top:SetColorTexture(ac.r, ac.g, ac.b, 1)
                                    local bot = glow:CreateTexture(nil, "OVERLAY", nil, 7)
                                    bot:SetHeight(px); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
                                    bot:SetColorTexture(ac.r, ac.g, ac.b, 1)
                                    local lft = glow:CreateTexture(nil, "OVERLAY", nil, 7)
                                    lft:SetWidth(px); lft:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bot, "TOPLEFT")
                                    lft:SetColorTexture(ac.r, ac.g, ac.b, 1)
                                    local rgt = glow:CreateTexture(nil, "OVERLAY", nil, 7)
                                    rgt:SetWidth(px); rgt:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
                                    rgt:SetColorTexture(ac.r, ac.g, ac.b, 1)
                                    glow:SetAlpha(1)
                                    local elapsed = 0
                                    glow:SetScript("OnUpdate", function(self, dt)
                                        elapsed = elapsed + dt
                                        if elapsed >= 0.75 then
                                            self:Hide(); self:SetParent(nil); self:SetScript("OnUpdate", nil); return
                                        end
                                        self:SetAlpha(1 - elapsed / 0.75)
                                    end)
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

        -- Track toggle states for test mode (persists across open/close within session)
        if not ns._testState then
            local specIdx = GetSpecialization and GetSpecialization()
            local specRole = specIdx and GetSpecializationRole and GetSpecializationRole(specIdx)
            ns._testState = {
                animateBars = false,
                absorbs = s.absorbStyle ~= "none",
                healAbsorbs = (s.healAbsorbStyle or "clean") ~= "none",
                healPrediction = s.healPrediction == true,
                threat = (s.threatBorderSize or 0) > 0,
                reducedMaxHealth = false,
                dispels = false,
                debuffs = s.debuffFilter ~= "none",
                defensives = s.showDefensives or s.showExternals or false,
                privateAuras = true,
                buffs = true,
                indicators = false,
            }
        end
        local testState = ns._testState

        -- Apply test state to preview flags
        ns._applyTestState = function()
            local indOn = testState.indicators
            ns._indicatorsVisible = indOn
            -- When indicators are on, suppress all other previews (but don't change testState)
            ns._dispelsVisible = not indOn and testState.dispels
            ns._debuffsPreviewVisible = not indOn and testState.debuffs
            ns._defensivesPreviewVisible = not indOn and testState.defensives
            ns._privateAurasPreviewVisible = not indOn and testState.privateAuras
            ns._testReducedMaxHealth = not indOn and testState.reducedMaxHealth
            ns._testAbsorbs = not indOn and testState.absorbs
            ns._testHealAbsorbs = not indOn and testState.healAbsorbs
            ns._testHealPrediction = not indOn and testState.healPrediction
            ns._testThreat = not indOn and testState.threat
            ns._testBuffsVisible = not indOn and testState.buffs
            -- Start/stop health animation based on animate bars toggle
            local wantAnim = not indOn and testState.animateBars
            if wantAnim then
                if ns._startHealthAnim and not ns._healthAnimActive then ns._startHealthAnim() end
            else
                if ns._stopHealthAnim and ns._healthAnimActive then ns._stopHealthAnim() end
            end
            -- Restart aura ticker so debuff/defensives icons hide/show immediately
            if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            -- Start/stop buff ticker based on toggle (always stop first so
            -- re-init picks up newly created preview frames)
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
            { page = PAGE_DEBUFFS })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Debuffs", function() return testState.debuffs end,
            function(v) testState.debuffs = v; ns._applyTestState() end,
            { page = PAGE_DEBUFFS })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Defensives & Externals", function() return testState.defensives end,
            function(v) testState.defensives = v; ns._applyTestState() end,
            { page = PAGE_DEBUFFS })
            nonIndicatorRows[#nonIndicatorRows + 1] = r end

        do local _, _, r = CheckboxRow("Private Auras", function() return testState.privateAuras end,
            function(v) testState.privateAuras = v; ns._applyTestState() end,
            { page = PAGE_DEBUFFS, key = "privateAuras" })
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

        -- Apply initial disabled state if indicators was on from previous session
        if testState.indicators then SetNonIndicatorRowsEnabled(false) end

        -- Resize panel to content (+ room for close button)
        panel:SetHeight(math.abs(cy) + 32 + PAD * 3)

        -- Close button
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

        -- Click dead space to close
        testModeFrame:SetScript("OnMouseDown", function()
            local oc = ns._overlayContainer
            if (panel and panel:IsMouseOver()) or (oc and oc:IsMouseOver()) then return end
            CloseTestMode()
        end)

        -- ESC to close
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

    -- Add Test button to tab bar when RF module is selected
    local testTabBtn = nil
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName == "EllesmereUIRaidFrames" then
                local tb = EllesmereUI._tabBar
                if not tb or not tb._tabButtons then return end
                local lastBtn = tb._tabButtons[#tb._tabButtons]
                if not lastBtn then return end

                if testTabBtn then
                    -- Re-anchor to current last tab (tab bar rebuilds on module switch)
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
        "click", "cast", "binding", "keybind", "spell", "macro", "mouseover",
    }

    EllesmereUI:RegisterModule("EllesmereUIRaidFrames", {
        title       = "Raid Frames",
        description = "Configure raid frame appearance and behavior.",
        pages       = { PAGE_MAIN, PAGE_PARTY, PAGE_DEBUFFS, PAGE_BUFFS, PAGE_CLICKCAST },
        searchTerms = rfSearchTerms,
        buildPage   = function(pageName, parent, yOffset)
            -- Clean up Buff Manager root when switching away
            if pageName ~= PAGE_BUFFS and ns._bmRoot then
                ns._bmRoot:Hide()
                ns._bmRoot:SetParent(nil)
                ns._bmRoot = nil
            end
            -- Clean up Click Cast root when switching away
            if pageName ~= PAGE_CLICKCAST and ns._ccRoot then
                if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
                if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
                if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
                if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end
                ns._ccRoot:Hide()
                ns._ccRoot:SetParent(nil)
                ns._ccRoot = nil
            end
            -- Show/hide raid preview for main and defensives/debuffs tabs
            if pageName == PAGE_MAIN or pageName == PAGE_DEBUFFS then
                local mode = db.profile.previewMode or "overlay"
                -- Keep real party frames hidden under the preview (skip restore) so
                -- they don't flash for a frame when returning to the party tab.
                -- Restore them only for "none" (user wants real frames visible).
                if ns.HidePartyPreview then ns.HidePartyPreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPreview then
                    C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
                elseif mode == "none" and ns.HidePreview then
                    ns.HidePreview()
                end
            elseif pageName == PAGE_PARTY then
                local mode = db.profile.previewMode or "overlay"
                -- Keep real frames hidden under the preview (skip restore) so they
                -- don't flash for a frame before the deferred ShowPartyPreview.
                if ns.HidePreview then ns.HidePreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPartyPreview then
                    C_Timer.After(0, function() if ns.ShowPartyPreview then ns.ShowPartyPreview() end end)
                elseif mode == "none" and ns.HidePartyPreview then
                    ns.HidePartyPreview()
                end
            else
                -- BUFFS / CLICKCAST: no preview shown, so do a FULL restore of
                -- both real containers (no skipRestore). A skip-restore here
                -- would leave the party container orphaned under the hidden
                -- preview parent with nothing to reparent it back.
                if ns.HidePreview then ns.HidePreview() end
                if ns.HidePartyPreview then ns.HidePartyPreview() end
            end
            -- Set party context BEFORE building any page so SGet/SSet/SVal
            -- read the correct keys during widget construction.
            _partyCtx = (pageName == PAGE_PARTY)

            if pageName == PAGE_MAIN then
                return BuildMainPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PARTY then
                return BuildPartyPage(pageName, parent, yOffset)
            elseif pageName == PAGE_DEBUFFS then
                return BuildDebuffsPage(pageName, parent, yOffset)
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
            if pageName == PAGE_MAIN or pageName == PAGE_DEBUFFS then
                local mode = db.profile.previewMode or "overlay"
                -- Keep real party frames hidden under the preview (skip restore) so
                -- they don't flash when returning to the party tab; see buildPage.
                if ns.HidePartyPreview then ns.HidePartyPreview(mode ~= "none") end
                if mode ~= "none" and ns.ShowPreview then
                    C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
                elseif mode == "none" and ns.HidePreview then
                    ns.HidePreview()
                end
            elseif pageName == PAGE_PARTY then
                local mode = db.profile.previewMode or "overlay"
                -- Keep real frames hidden under the preview (skip restore) so they
                -- don't flash for a frame before the deferred ShowPartyPreview.
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
            -- Clear the first-install capture flag so position re-captures on reload
            if db.sv then db.sv._capturedOnce_RF = nil end
            db:ResetProfile()
            ReloadUI()
        end,
    })

    -- Show preview / rebuild BM when panel re-opens on RF page
    if EllesmereUI.RegisterOnShow then
        EllesmereUI:RegisterOnShow(function()
            if EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames" then
                local page = EllesmereUI:GetActivePage()
                if page == PAGE_MAIN or page == PAGE_DEBUFFS then
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
    end
    -- Hide preview and clean up BM/CC when panel closes
    if EllesmereUI.RegisterOnHide then
        EllesmereUI:RegisterOnHide(function()
            if ns._rfEyeHintTip then ns._rfEyeHintTip:Hide() end
            -- Guarantee both real containers are reparented to UIParent and
            -- their visibility recomputed, even if a skip-restore tab swap or a
            -- post-close deferred ShowPreview left a container orphaned under
            -- the hidden preview parent. This is the hard invariant that
            -- prevents "frames vanish after closing options". Self-defers to
            -- PLAYER_REGEN_ENABLED in combat.
            if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
            if ns._sizePreviewTier then
                ns._sizePreviewTier = nil
                if ns._HideSizePreview then ns._HideSizePreview() end
            end
            -- BM cleanup: root + Add New popup (DIALOG strata, persists otherwise)
            if ns._addNewPopup then ns._addNewPopup:Hide() end
            if ns._bmRoot then
                ns._bmRoot:Hide(); ns._bmRoot:SetParent(nil); ns._bmRoot = nil
            end
            if ns._ccRoot then
                if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
                if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
                if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
                ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil); ns._ccRoot = nil
            end
            if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end
        end)
    end

    -- Register callback for HideAllChildren to also clean up custom roots
    -- parented to scrollFrame (BM/CC bypass scroll child intentionally).
    EllesmereUI._hideScrollFrameRoots = function()
        if ns._addNewPopup then ns._addNewPopup:Hide() end
        if ns._bmRoot then ns._bmRoot:Hide(); ns._bmRoot:SetParent(nil); ns._bmRoot = nil end
        if ns._ccRoot then
            if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
            if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
            if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
            ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil); ns._ccRoot = nil
        end
        if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end
    end

    -- Clean up BM/CC root and hide preview when switching modules
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName ~= "EllesmereUIRaidFrames" then
                if ns._rfEyeHintTip then ns._rfEyeHintTip:Hide() end
                -- Tear down previews and guarantee the real containers are
                -- restored to UIParent (handles orphaned-flag-false cases too).
                if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
                if ns._addNewPopup then ns._addNewPopup:Hide() end
                if ns._bmRoot then
                    ns._bmRoot:Hide(); ns._bmRoot:SetParent(nil); ns._bmRoot = nil
                end
                if ns._ccRoot then
                    if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
                    if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
                    if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
                    ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil); ns._ccRoot = nil
                    if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end
                end
            end
        end)
    end

    -- Party Frames search: sections synced with raid settings are excluded from
    -- inline search results (their controls live on the Raid tabs). Maps the
    -- section HEADER TEXT to its sync key -- keep in sync with the SectionHeader
    -- names in the section builders and ns._PARTY_SECTION_ORDER.
    ns._PARTY_SEARCH_SECTION_KEY = {
        ["HEALTH BAR"]             = "healthBar",
        ["POWER BAR"]              = "powerBar",
        ["TEXT DISPLAY"]           = "textDisplay",
        ["INDICATORS"]             = "indicators",
        ["DISPELS"]                = "dispels",
        ["EXTRAS"]                 = "rangeTooltip",
        ["DEFENSIVES & EXTERNALS"] = "defensives",
        ["PRIVATE AURAS"]          = "privateAuras",
        ["DEBUFF DISPLAY"]         = "debuffDisplay",
        ["DEBUFF STYLE"]           = "debuffStyle",
    }
    ns._PartySearchExclude = function(sectionName)
        local key = ns._PARTY_SEARCH_SECTION_KEY[sectionName]
        if not key then return false end
        if not db or not db.profile then return false end
        local ss = db.profile.partySyncSections
        return (not ss) or ss[key] ~= false  -- synced (default = all synced)
    end

    -- Show/hide the party sync overlays in step with the inline search: hidden
    -- while a search is active (their sections are excluded), restored to their
    -- per-section sync state when the search is empty. The overlays are tagged
    -- _searchIgnore so the generic search never re-anchors them.
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

    -- Clean up when switching pages within RF.
    -- Pre-hook: _partyCtx must be set BEFORE SelectPage refreshes widget
    -- values, so we wrap the original rather than using hooksecurefunc.
    if EllesmereUI.SelectPage then
        local origSelectPage = EllesmereUI.SelectPage
        EllesmereUI.SelectPage = function(self, pageName, ...)
            _partyCtx = (pageName == PAGE_PARTY)
            -- Party tab: exclude synced sections from inline search. Cleared for
            -- every other page (any module) so the hook can never leak.
            EllesmereUI._searchExcludeSection = (pageName == PAGE_PARTY) and ns._PartySearchExclude or nil
            EllesmereUI._onInlineSearch = (pageName == PAGE_PARTY) and ns._PartySearchOverlaySync or nil
            local result = origSelectPage(self, pageName, ...)
            -- Re-sync the sync overlays on entering the party tab (a prior search
            -- may have hidden them; the search box is cleared on page change).
            if pageName == PAGE_PARTY and ns._PartySearchOverlaySync then
                ns._PartySearchOverlaySync("")
            end
            -- Hide/show eye hint based on tab
            if ns._rfEyeHintTip then
                if pageName == PAGE_MAIN then ns._rfEyeHintTip:Show()
                else ns._rfEyeHintTip:Hide() end
            end
            -- Reset all eyeball toggles on tab change
            ns._indicatorsVisible = false
            ns._dispelsVisible = false
            ns._defensivesPreviewVisible = false
            ns._debuffsPreviewVisible = false
            ns._privateAurasPreviewVisible = false
            -- Reset + cancel the shared health/power animation tickers (they are
            -- on ns now so a single cancel covers whichever preview built them).
            ns._healthAnimActive = false
            ns._powerAnimActive = false
            if ns._healthAnimTicker then ns._healthAnimTicker:Cancel(); ns._healthAnimTicker = nil end
            if ns._powerAnimTicker then ns._powerAnimTicker:Cancel(); ns._powerAnimTicker = nil end
            ns._bmFrameEffectsVisible = false
            if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
            if ns.ResetPreviewRandomization then ns.ResetPreviewRandomization() end

            -- Switching to Buff Manager or Click Casting: hide raid frame preview
            if pageName == PAGE_BUFFS or pageName == PAGE_CLICKCAST then
                if ns.HidePreview then ns.HidePreview() end
            end
            -- Switching to main or debuffs tab: show preview if enabled
            if pageName == PAGE_MAIN or pageName == PAGE_DEBUFFS then
                local mode = db.profile.previewMode or "overlay"
                if mode ~= "none" and ns.ShowPreview then
                    C_Timer.After(0, function() if ns.ShowPreview then ns.ShowPreview() end end)
                end
            end
            -- Switching away from Buff Manager: clean up BM root
            if pageName ~= PAGE_BUFFS and ns._bmRoot then
                ns._bmRoot:Hide(); ns._bmRoot:SetParent(nil); ns._bmRoot = nil
            end
            -- Switching away from Click Cast: clean up CC root
            if pageName ~= PAGE_CLICKCAST and ns._ccRoot then
                if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
                if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
                if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
                ns._ccRoot:Hide(); ns._ccRoot:SetParent(nil); ns._ccRoot = nil
                if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end
            end
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
            ReloadUI()
            return
        end
        EllesmereUI:ShowModule("EllesmereUIRaidFrames")
    end
    end -- ns._InitEUIModule

    -- If SetupOptionsPanel already ran before PLAYER_LOGIN, fire immediately
    if ns.db then
        ns._InitEUIModule()
    end
end)
