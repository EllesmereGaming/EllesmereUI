-------------------------------------------------------------------------------
--  EUI_RaidFrames_Options.lua
--  Registers the Raid Frames module with EllesmereUI options panel.
--  Two tabs: Raid Frames (layout, health, power, text, border, absorbs,
--  indicators, debuffs, dispels, range/tooltip) and Buff Manager.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_MAIN = "Frames"
local PAGE_PARTY = "Party"
local PAGE_DEBUFFS = "Auras"
local PAGE_BUFFS = "Buff Manager"
-- 12.1 only: the Debuff Manager page registers exclusively on 12.1 clients
-- (its builder lives in the self-gated manager-pages file); every reference
-- below is either inside a 12.1-selected pages list or guarded on state
-- that stays nil on 12.0, so retail behavior is byte-identical.
local PAGE_DM = "Debuff Manager"
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
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("raidFrames")) or ""
    end
    local function GetUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("raidFrames")
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

        -- Drag state (declared before OnShow so its OnUpdate can suppress the
        -- click-away dismiss while a row is actively being dragged).
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
        local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

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
        ["class"]         = "Class Color",
        ["dark"]          = "Dark Mode",
        ["classic"]       = "Classic",
        ["custom"]        = "Custom Color",
        ["customDynamic"] = "Custom Dynamic Colors",
    }
    local healthColorOrder = { "class", "dark", "classic", "custom", "customDynamic" }

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

    -- Name Position offers an extra "None" (hides the name entirely). Health Text
    -- Position reuses the base tables above, so keep "None" out of the shared set.
    local namePositionValuesName = {
        ["topleft"]    = "Top Left",
        ["top"]        = "Top",
        ["topright"]   = "Top Right",
        ["left"]       = "Left",
        ["center"]     = "Center",
        ["right"]      = "Right",
        ["bottomleft"] = "Bottom Left",
        ["bottom"]     = "Bottom",
        ["bottomright"] = "Bottom Right",
        ["none"]       = "None",
    }
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
        ["clean"]           = "Clean (Flat)",
        ["blizzard"]        = "Classic WoW",          -- DB key stays "blizzard"; label only
        ["blizzardModern"]  = "Default Blizz Frames", -- compound: solid base + tiled stripes (shield only)
        ["healBlizzModern"] = "Default Blizz Frames", -- heal-absorb only: louis-absorb.png texture
        ["largeOutlinedStripes"]  = "Large Outlined Stripes",  -- heal-absorb only: large-habsorb-left.png
        ["largeOutlinedStripesR"] = "Large Outlined Stripes R", -- heal-absorb only: large-habsorb-right.png
        ["largeStripes"]          = "Large Stripes",            -- large-absorb-left.png
        ["largeStripesR"]         = "Large Stripes R",          -- large-absorb-right.png
        ["maxHealthStripes"]      = "Max Health Stripes",       -- reduced max-health overlay
    }
    -- Shield absorb dropdown shows every style including Blizzard (Modern).
    local absorbStyleOrder = { "none", "striped", "stripedReversed", "clean", "blizzard", "blizzardModern", "largeStripes", "largeStripesR" }
    -- Heal absorb shares the values table but EXCLUDES Blizzard (Modern).
    local healAbsorbStyleOrder = { "none", "striped", "stripedReversed", "clean", "blizzard", "healBlizzModern", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR" }
    -- Max Health mirrors Heal Absorb plus the dedicated "Max Health Stripes" first.
    local maxHealthStyleOrder = { "none", "maxHealthStripes", "striped", "stripedReversed", "clean", "blizzard", "healBlizzModern", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR" }
    -- Append SharedMedia statusbar textures after a divider, mirroring the Bar
    -- Texture dropdown. SM keys ("sm:" prefixed) were appended to the shared
    -- health-bar tables by AppendSharedMediaTextures; render-time resolution
    -- flows through ns.ResolveAbsorbStyleTex -> the health-bar texture lookup.
    -- All three dropdowns share absorbStyleValues, so each gains the SM entries
    -- and the preview swatch.
    do
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
        end
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
        -- Preview swatch behind each menu row. Special compound keys resolve to
        -- their representative texture; everything else via ns.ResolveAbsorbStyleTex.
        absorbStyleValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" or key == "none" then return nil end
                if key == "blizzardModern" then return ns.ResolveAbsorbStyleTex("striped") end
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

    -- Preview Mode controls carrying override-preview chrome (gold border
    -- host + tooltip), one entry per built row across tabs/rebuilds.
    local pvModeCtrls = {}

    -- Gold border + tooltip on every Preview Mode control when the REAL
    -- preview is rendering an override's effective values (spec group or
    -- applied conditional). State computed from the runtime resolvers --
    -- never the panel's view flags -- so it always matches what the real
    -- preview actually shows. Recomputed at row build time and from
    -- ns._RebuildPvOverlay (view/spec/conditional changes).
    function ns._UpdatePvModeChrome()
        if #pvModeCtrls == 0 then return end
        local text
        if (db.profile.previewMode or "overlay") == "real" then
            -- Editing-as session: the preview shows THAT session's values
            -- (the effective overlay is off there by design), so the chrome
            -- names the session being edited.
            local sessName = EllesmereUI.SpecOverrides_EditSessionName
                and EllesmereUI.SpecOverrides_EditSessionName()
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

    -- Shared helper: true when preview is disabled (eyeball toggles should gray out)
    local function IsPreviewOff()
        return (db.profile.previewMode or "overlay") == "none"
    end

    -- Shared: builds the "Preview Mode" dropdown row at the top of a page.
    -- Returns the new y offset after the row.
    local function BuildPreviewModeRow(parent, y)
        local ROW_H = 50
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local contentPad = EllesmereUI.CONTENT_PAD or 45

        y = y - 10
        local modeRow = CreateFrame("Frame", nil, parent)
        PP.Size(modeRow, parent:GetWidth() - contentPad * 2, ROW_H)
        PP.Point(modeRow, "TOPLEFT", parent, "TOPLEFT", contentPad, y)
        y = y - ROW_H

        local modeLabel = modeRow:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(modeLabel, GetOutline() == "" and GetUseShadow()) end
        modeLabel:SetFont(fontPath, 14, GetOutline())
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

        -- Override-preview chrome: a separate gold border host (the control's
        -- own border is re-asserted by its hover scripts, so it is never
        -- recolored directly -- same pattern as the overrides UI slot marks).
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
                    -- Effective overlay: preview ticks must never render the
                    -- panel view's swapped values (real preview contract).
                    local s = (ns.PvEffectiveProfile and ns.PvEffectiveProfile()) or db.profile
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

                                -- Update fill color for classic (gradient) mode
                                if s.healthColorMode == "classic" then
                                    local pct = st.current / 100
                                    local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
                                    local g = pct > 0.5 and 1 or (pct * 2)
                                    f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
                                elseif s.healthColorMode == "customDynamic" then
                                    local r, g, b = ns.ResolveDynamicColor(s, st.current / 100)
                                    f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
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
              disabled=function() return SVal("healthColorMode", "class") == "dark" end,
              disabledTooltip="Not available in Dark Mode", rawTooltip=true,
              getValue=function() return SVal("healthBarOpacity", 100) end,
              setValue=function(v) SSet("healthBarOpacity", v) end });  y = y - h

        -- Row 2: Fill Color | Background
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Fill Color", values=healthColorValues, order=healthColorOrder,
              tooltip="Custom Dynamic Colors: the health bar smoothly blends between three colors you pick -- one for full health (100%), one for half (50%), and one for empty (0%) -- shifting through them as the unit takes damage or is healed.",
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
        -- Inline color swatch for custom fill color, plus the three Custom Dynamic
        -- Colors stop swatches (100% / 50% / 0%). Only one set is interactive at a
        -- time depending on the Fill Color mode; they share the same inline slot.
        do
            local rgn = row._leftRegion

            -- Single custom-color swatch (Custom Color mode)
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
            -- Blocking overlay: dim + non-clickable + tooltip unless Fill Color is Custom.
            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints()
            block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, "Only available with Custom fill color") end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Custom Dynamic Colors: three gradient-stop swatches, built right-to-left
            -- from the dropdown control so the visual order reads 100% | 50% | 0%.
            -- The percentage is conveyed via each swatch's tooltip.
            local dynDefs = {
                { key = "dynamicColor100", def = { r = 0, g = 1, b = 0 }, label = "100%", tip = "Health bar color at full (100%) health" },
                { key = "dynamicColor50",  def = { r = 1, g = 1, b = 0 }, label = "50%",  tip = "Health bar color at half (50%) health" },
                { key = "dynamicColor0",   def = { r = 1, g = 0, b = 0 }, label = "0%",   tip = "Health bar color at empty (0%) health" },
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
                -- Single custom swatch: active only in Custom mode; dimmed + blocked in
                -- other modes (existing behavior), but fully hidden in Dynamic mode so
                -- it does not sit behind the three dynamic swatches.
                if isDynamic then
                    swatch:Hide(); block:Hide()
                else
                    swatch:Show()
                    if mode == "custom" then swatch:SetAlpha(1); block:Hide()
                    else swatch:SetAlpha(0.3); block:Show() end
                end
                for _, sw in ipairs(dynSwatches) do
                    if isDynamic then sw:Show() else sw:Hide() end
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateSwatchVis)
            UpdateSwatchVis()
        end
        -- Inline swatches for background: Custom + Class pair. Clicking either
        -- toggles bgClassColored; the inactive one dims (mirrors the fill picker).
        do
            local rgn = row._rightRegion
            -- Class-colored background swatch (player class color; not editable).
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

            -- Custom background color swatch.
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
            -- Blocking overlay over BOTH swatches: dim + non-clickable + tooltip in
            -- Dark Mode (no background exists there).
            local bgBlock = CreateFrame("Frame", nil, rgn)
            bgBlock:SetPoint("TOPLEFT", bgSwatch, "TOPLEFT", 0, 0)
            bgBlock:SetPoint("BOTTOMRIGHT", bgClassSwatch, "BOTTOMRIGHT", 0, 0)
            bgBlock:SetFrameLevel(bgClassSwatch:GetFrameLevel() + 10)
            bgBlock:EnableMouse(true)
            bgBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Not available in Dark Mode") end)
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

        -- Row 3: Heal Prediction (+ color swatch) | Prediction Opacity
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

        -- Row 4: Smooth Bars | Threat Borders
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
        --  ABSORBS
        --  Own party-sync section ("absorbs"). Pre-split profiles inherit
        --  the Health Bar sync state via ns._NormalizePartySyncSections.
        -------------------------------------------------------------------
        local absorbsHeader
        if onSection then onSection("healthBar", _secY, y) end; _secY = y
        absorbsHeader, h = W:SectionHeader(parent, "ABSORBS", y); y = y - h

        -- Eyeball: toggle shield/heal-absorb effects on the preview frames.
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"

            -- Find the section label FontString
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

            -- State stored on ns so the preview renderer can read it
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
                -- Turn off indicators if active (they suppress bar effects)
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

        -- Row 1: Absorb Style (+ color swatch) | Absorb Opacity
        local absorbRow
        absorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
              getValue=function() return SVal("absorbStyle", "none") end,
              setValue=function(v)
                  SSet("absorbStyle", v)
                  if v == "clean" then
                      SSet("absorbOpacity", 30)
                  elseif v ~= "blizzardModern" then
                      -- Blizzard (Modern) hardcodes color + opacity in the
                      -- renderer; leave the user's saved opacity untouched.
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
            -- Blocking overlay: BuildColorSwatch has no built-in disabled state,
            -- so a mouse-enabled frame over it intercepts clicks whenever the
            -- color is not user-editable (no absorb, or the hardcoded-color
            -- "Blizzard (Modern)" style).
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
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Absorb Rendering",
                rows = {
                    { type="dropdown", label="Placement",
                      values = { overlay = "Overlay", right = "From Right Edge", left = "From Left Edge" },
                      order = { "overlay", "right", "left" },
                      disabled = function() return SVal("absorbStyle", "none") == "blizzardModern" end,
                      disabledTooltip = "Default Blizz Frames uses a fixed placement",
                      rawTooltip = true,
                      get=function() return SVal("absorbEdgeMode", "overlay") end,
                      set=function(v) SSet("absorbEdgeMode", v) end },
                    { type="toggle", label="Show Overshield",
                      tooltip="Show the part of an absorb that exceeds your empty health and backfills over your current health. When off, absorbs only fill the empty part of the health bar; on Default Blizz Frames the glow line stays pinned at the right edge.",
                      get=function() return SVal("showOvershield", true) end,
                      set=function(v) SSet("showOvershield", v) end },
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

        -- Row 2: Absorb Bar (position dropdown) | Bar Height (+ inline color swatch)
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
        -- Inline cog: vertical grow direction (shared by both strip bars)
        do
            local rgn = absorbBarRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            -- Grey + block the cog whenever the bar isn't on a vertical position
            -- (its only setting, Vertical Grow, has no effect otherwise).
            local function cogOff()
                local p = CurAbsorbBarPos()
                return p ~= "rightVertical" and p ~= "leftVertical"
            end
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(cogOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) if not cogOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(cogOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) if not cogOff() then cogShow(self) end end)
            EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(cogOff() and 0.15 or 0.4) end)
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
        -- Inline color swatch for the absorb bar color
        do
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

        -- Row 3: Heal Absorb Style (+ color swatch) | Heal Absorb Opacity
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
            -- Blocking overlay: disabled for "none" and the hardcoded-white
            -- "Default Blizz Frames" (healBlizzModern) heal style.
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
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Heal Absorb Rendering",
                rows = {
                    { type="dropdown", label="Placement",
                      values = { overlay = "Overlay", right = "From Right Edge", left = "From Left Edge" },
                      order = { "overlay", "right", "left" },
                      get=function() return SVal("healAbsorbEdgeMode", "overlay") end,
                      set=function(v) SSet("healAbsorbEdgeMode", v) end },
                    { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                      get=function() return SVal("healAbsorbBgOpacity", 25) end,
                      set=function(v) SSet("healAbsorbBgOpacity", v) end },
                    { type="toggle", label="Show Over Dispels",
                      get=function() return SVal("healAbsorbOverDispel", false) == true end,
                      set=function(v) SSet("healAbsorbOverDispel", v) end },
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

        -- Row 4: Heal Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
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
            -- Inline alpha color swatch for the heal absorb bar color
            do
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
            -- Inline cog: heal absorb bar vertical grow direction
            do
                local rgn = healAbsorbBarRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
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
                -- Grey + block the cog whenever the bar isn't on a vertical
                -- position (Vertical Grow has no effect otherwise).
                local function cogOff()
                    local p = CurHealAbsorbBarPos()
                    return p ~= "rightVertical" and p ~= "leftVertical"
                end
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(cogOff() and 0.15 or 0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) if not cogOff() then self:SetAlpha(0.7) end end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(cogOff() and 0.15 or 0.4) end)
                cogBtn:SetScript("OnClick", function(self) if not cogOff() then cogShow(self) end end)
                EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(cogOff() and 0.15 or 0.4) end)
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

        -- Row 5: Max Health Texture (+ color swatch + backing cog) | Max Health Opacity.
        -- Styles mirror Heal Absorb plus the dedicated "Max Health Stripes" texture
        -- as the first option. No placement -- the overlay is always right-anchored.
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
            -- Inline color swatch: tints the max health texture
            do
                local rgn = maxHealthRow._leftRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, maxHealthRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("maxHealthColor")
                        if c then return c.r, c.g, c.b, 1 end
                        return 0.7, 0.1, 0.1, 1
                    end,
                    function(r, g, b)
                        SWrite("maxHealthColor", { r=r, g=g, b=b })
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                -- Blocking overlay: disabled for "none" and the pre-colored styles.
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
            -- Inline cog: backing opacity only (no placement -- always right side)
            do
                local rgn = maxHealthRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Max Health Rendering",
                    rows = {
                        { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                          get=function() return SVal("maxHealthBgOpacity", 100) end,
                          set=function(v) SSet("maxHealthBgOpacity", v) end },
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
        end

        -------------------------------------------------------------------
        --  POWER BAR
        -------------------------------------------------------------------
        local powerHeader
        if onSection then onSection("absorbs", _secY, y) end; _secY = y
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
                    -- Effective overlay: see the health ticker note above.
                    local smooth = ((ns.PvEffectiveProfile and ns.PvEffectiveProfile())
                        or db.profile).smoothPowerBars

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
            -- Cog: Uniform Icon Anchoring (power bar independence). Greyed +
            -- blocked while no role shows a power bar (nothing to ignore then).
            do
                local rgn = row._rightRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
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
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(IsPowerOff() and 0.15 or 0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) if not IsPowerOff() then self:SetAlpha(0.7) end end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(IsPowerOff() and 0.15 or 0.4) end)
                cogBtn:SetScript("OnClick", function(self) if not IsPowerOff() then cogShow(self) end end)
                EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(IsPowerOff() and 0.15 or 0.4) end)
            end
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
        -- Inline swatches for power bg: Custom + Power Colored pair. Clicking
        -- either toggles powerBgPowerColored; the inactive one dims (mirrors the
        -- health bar background picker).
        do
            local rgn = pwBgRow._rightRegion
            -- Power-colored background swatch (player's power color; not editable).
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
            bgPwrSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSwatch, "Power Colored Background") end)
            bgPwrSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            bgPwrSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgPwrSwatch

            -- Custom background color swatch.
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

        -- (Show Power Bar For moved to Row 1 above)

        -------------------------------------------------------------------
        --  TEXT DISPLAY
        -------------------------------------------------------------------
        if onSection then onSection("powerBar", _secY, y) end; _secY = y
        _, h = W:SectionHeader(parent, "TEXT DISPLAY", y); y = y - h

        -- Row 1: Name Size | Name Color (triple swatch: custom / class / accent)
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
        -- Cog for name character-count cap + text stacking (lives on the Name
        -- Size slider).
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end

        -- Row 2: Name Position (+ cog for X/Y) | Health Text
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Name Position", values=namePositionValuesName, order=namePositionOrderName,
              getValue=function() return SVal("namePosition", "center") end,
              setValue=function(v) SSet("namePosition", v) end },
            { type="dropdown", text="Health Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return SVal("healthTextMode", "none") end,
              -- DependentSetValue: rebuilds the page when the None <-> not-None
              -- state flips so the hidden Position/Size row below appears/vanishes.
              setValue=EllesmereUI.DependentSetValue(
                  function() return SVal("healthTextMode", "none") ~= "none" end,
                  function(v) SSet("healthTextMode", v) end) });  y = y - h
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
                    local r, g, b = EllesmereUI.ResolveActiveAccent()
                    return r or 1, g or 1, b or 1, 1
                end,
                function() end, "accent", false, "Accent Color")
        end

        -- Row 3: Health Text Position (+ cog for X/Y) | Health Text Size.
        -- Hidden entirely while Health Text is None (DependentSetValue on that
        -- dropdown rebuilds the page when the state flips).
        if SVal("healthTextMode", "none") ~= "none" then
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Health Text Position", values=namePositionValues, order=namePositionOrder,
              getValue=function() return SVal("healthTextPosition", "center") end,
              setValue=function(v) SSet("healthTextPosition", v) end },
            { type="slider", text="Health Text Size", min=6, max=26, step=1,
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
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        end   -- close Health Text dependent-row gate

        -- Row 4: Heal Absorb Text (+ color swatches) | Heal Absorb Text Position
        -- (+ offset cog). Row 5: Heal Absorb Text Size. 1:1 with Health Text; the
        -- text shows the heal-absorb shield amount (short/full), hidden at zero.
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Text",
              values={ ["none"]="None", ["short"]="Short (240k)", ["amount"]="Amount" },
              order={ "none", "short", "amount" },
              getValue=function() return SVal("healAbsorbTextMode", "none") end,
              -- DependentSetValue: rebuilds the page when the None <-> not-None
              -- state flips so the hidden Text Size row below appears/vanishes.
              setValue=EllesmereUI.DependentSetValue(
                  function() return SVal("healAbsorbTextMode", "none") ~= "none" end,
                  function(v) SSet("healAbsorbTextMode", v); EllesmereUI:RefreshPage() end) },
            { type="dropdown", text="Heal Absorb Text Position", values=namePositionValues, order=namePositionOrder,
              disabled=function() return SVal("healAbsorbTextMode", "none") == "none" end,
              disabledTooltip="Heal Absorb Text",
              getValue=function() return SVal("healAbsorbTextPosition", "center") end,
              setValue=function(v) SSet("healAbsorbTextPosition", v) end });  y = y - h
        -- Inline color swatches for Heal Absorb Text color (custom / class / accent),
        -- mirroring the Health Text triple swatch.
        do
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
            -- Custom (rightmost): editable color, opens the picker when active.
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
            -- Class color.
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
            -- Accent color (leftmost).
            AddHASwatch(
                function()
                    local r, g, b = EllesmereUI.ResolveActiveAccent()
                    return r or 1, g or 1, b or 1, 1
                end,
                function() end, "accent", false, "Accent Color")
        end
        -- Offset cog on the Heal Absorb Text Position region (right of Row 4)
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local haOff = SVal("healAbsorbTextMode", "none") == "none"
            cogBtn:SetAlpha(haOff and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s)
                s:SetAlpha(SVal("healAbsorbTextMode", "none") == "none" and 0.15 or 0.4)
            end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        -- Row 5: Heal Absorb Text Size | (blank odd last slot). Hidden entirely
        -- while Heal Absorb Text is None (DependentSetValue on that dropdown
        -- rebuilds the page when the state flips).
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
            blizzLight = { _isTexture = true, TANK = ROLE_MEDIA .. "tank.png", HEALER = ROLE_MEDIA .. "healer.png", DAMAGER = ROLE_MEDIA .. "dps.png" },
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
            -- Internal key stays "blizzLight" so existing saved roleIconStyle values
            -- keep resolving; only the display label changed to "Modern Light".
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
        -- Inline cog on the Role Icons dropdown: Hide In Combat toggle
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Role Icons",
                rows = {
                    { type="toggle", label="Hide In Combat",
                      tooltip="Hide role icons while you are in combat.",
                      get=function() return SVal("roleIconHideInCombat", false) end,
                      set=function(v) SSet("roleIconHideInCombat", v); if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end end },
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
        -- Row 2: Role Position (+ cog for X/Y) | Role Icon Size
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
        local rolePositionOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
        local roleRow2
        roleRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Role Position", values=rolePositionValues, order=rolePositionOrder,
              disabled=function() return SVal("roleIconStyle", "modern") == "none" end,
              disabledTooltip="Role Icons",
              getValue=function() return SVal("roleIconPosition", "bottomleft") end,
              setValue=function(v) SSet("roleIconPosition", v) end },
            { type="slider", text="Role Icon Size", min=8, max=30, step=1,
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

        -- The rows below Marker Position are the less-common indicators. On the
        -- RAID tab they collapse behind the shared session expander (see
        -- BuildLessCommonExpander in EllesmereUI_Widgets.lua; honors the global
        -- Auto Expand Less Common Settings toggle); the party tab (_partyCtx)
        -- always shows them.
        local lessCommonOpen = true
        if not _partyCtx then
            lessCommonOpen, y = EllesmereUI.BuildLessCommonExpander(parent, y,
                "rfIndicators", "Show Less Common Indicator Options")
        end
        if lessCommonOpen then

        -- Ready Check / Summon / Rez icon position + size (the three indicators
        -- share a single texture, so one set of controls drives all of them).
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
        local readyCheckPositionOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
        local rcRow
        rcRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Ready Check / Summon / Rez", values=readyCheckPositionValues, order=readyCheckPositionOrder,
              getValue=function() return SVal("readyCheckPosition", "center") end,
              setValue=function(v) SSet("readyCheckPosition", v) end },
            { type="slider", text="Icon Size", min=8, max=40, step=1,
              getValue=function() return SVal("readyCheckSize", 20) end,
              setValue=function(v) SSet("readyCheckSize", v) end });  y = y - h
        -- Cog for ready check / summon toggles + offset X/Y
        do
            local rgn = rcRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            { type="slider", text="Text Size", min=6, max=30, step=1,
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
            { type="slider", text="Leader Icon Size", min=8, max=30, step=1,
              disabled=function() return not SVal("showLeaderIcon", false) end,
              disabledTooltip="Leader Icon",
              getValue=function() return SVal("leaderIconSize", 14) end,
              setValue=function(v) SSet("leaderIconSize", v) end });  y = y - h
        -- Cog for leader icon offset X/Y
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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

        -- Row: Combat Icon Position (includes "None" to disable) | Combat Icon Size.
        -- Shows on members currently in combat -- e.g. to spot who's still pulling
        -- during a Mythic+ skip. Style/color/offset live in the inline cog.
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
        -- Cog for combat icon style / color / offset X/Y
        do
            local rgn = ciRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
        -- Inline color swatch for the combat icon custom color
        do
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

        -- Show Group Numbers | Number Size (+ inline color swatch with alpha).
        -- Raid only: party frames have no groups. The size + color also drive the
        -- always-on preview group labels; the toggle gates only the real frames.
        if not _partyCtx then
            local gnRow
            gnRow, h = W:DualRow(parent, y,
                { type="toggle", text="Show Group Numbers",
                  getValue=function() return SVal("showGroupNumbers", false) end,
                  setValue=function(v) SSet("showGroupNumbers", v) end },
                { type="slider", text="Number Size", min=6, max=30, step=1,
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
        end   -- close the less-common-indicators collapse wrapper
        -- While expanded, the shared link re-renders here (below the rows) in
        -- its "Hide ..." form; no-op while collapsed or party ctx.
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
            gradient_sharp = "Gradient Sharp",
        }
        local dispelOverlayOrder = { "none", "fill", "full", "gradient", "gradient_sharp" }

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
                      SSet("showDispelIcons", true)
                      SSet("dispelIconPosition", v)
                  end
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        -- Cog for dispel icon offset X/Y
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(SVal("showDispelIcons", false) and 0.4 or 0.15)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) if SVal("showDispelIcons", false) then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(SVal("showDispelIcons", false) and 0.4 or 0.15) end)
            cogBtn:SetScript("OnClick", function(self) if SVal("showDispelIcons", false) then cogShow(self) end end)
        end

        -- Row 3: Dispel Colors -- five always-active swatches, one per dispel type.
        -- Unlike Name Color (a mode picker), every swatch is independently
        -- editable, so no onClick/refreshAlpha (default click opens the picker).
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Dispel Colors",
              -- Alpha per type: 0 hides that type's dispel border/overlay
              -- entirely (an opt-out per dispel type).
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
              -- Front-end inverse of dispelShowAll: toggle ON = only-mine (dispelShowAll=false).
              getValue=function() return not SVal("dispelShowAll", true) end,
              setValue=function(v) SSet("dispelShowAll", not v) end });  y = y - h

        -- 12.1: the split location is a Debuff Manager tile, the clock
        -- border is a per-tile Debuff Manager setting, and the private
        -- dispel overlay position was removed -- none of these rows build.
        if not EllesmereUI.IS_121 then
        -- Dispellable Debuff Location: route dispellable debuffs to their own
        -- anchor + growth (separate from the main debuff display). "Same as
        -- Debuffs" keeps them in the normal debuff layout (no change).
        local dispLocValues = {
            same        = "Same as Debuffs",
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
        local dispLocOrder = { "same", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
        local dispGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
        local dispGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }
        local function GetDefaultDispGrow(pos)
            if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
            if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
            if pos == "top" then return "DOWN" end
            if pos == "bottom" then return "UP" end
            return "RIGHT"
        end
        local function dispLocOff() return SVal("dispellableDebuffLocation", "same") == "same" end

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Dispellable Debuff Location", values=dispLocValues, order=dispLocOrder,
              getValue=function() return SVal("dispellableDebuffLocation", "same") end,
              setValue=function(v)
                  SSet("dispellableDebuffLocation", v)
                  if v ~= "same" then SSet("dispellableDebuffGrowDirection", GetDefaultDispGrow(v)) end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Dispel Clock Border",
              getValue=function() return SVal("dispelClockBorder", false) end,
              setValue=function(v) SSet("dispelClockBorder", v); EllesmereUI:RefreshPage() end }
        ); y = y - h
        -- Left cog: Dispellable Debuff Location growth direction + X/Y offsets.
        -- Only interactive when a separate location is chosen (not "Same as Debuffs").
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Dispellable Debuff Location",
                rows = {
                    -- 0 = match the main Debuff Size (the pre-existing behavior).
                    { type="slider", label="Icon Size", min=0, max=60, step=1,
                      get=function() return SVal("dispellableDebuffSize", 0) end,
                      set=function(v) SSet("dispellableDebuffSize", v) end },
                    { type="dropdown", label="Growth Direction", values=dispGrowValues, order=dispGrowOrder,
                      get=function() return SVal("dispellableDebuffGrowDirection", "RIGHT") end,
                      set=function(v) SSet("dispellableDebuffGrowDirection", v) end },
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return SVal("dispellableDebuffOffsetX", 0) end,
                      set=function(v) SSet("dispellableDebuffOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return SVal("dispellableDebuffOffsetY", 0) end,
                      set=function(v) SSet("dispellableDebuffOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(dispLocOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) if not dispLocOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(dispLocOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) if not dispLocOff() then cogShow(self) end end)
        end
        -- Right cog on the toggle: Extra Border Size (physical px on top of the
        -- main debuff border size). Only interactive while the toggle is on.
        do
            local rgn = row._rightRegion
            local function clockOn() return SVal("dispelClockBorder", false) end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Dispel Clock Border",
                rows = {
                    { type="slider", label="Extra Border Size", min=0, max=4, step=1,
                      get=function() return SVal("dispelClockExtraBorder", 0) end,
                      set=function(v) SSet("dispelClockExtraBorder", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(clockOn() and 0.4 or 0.15)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) if clockOn() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(clockOn() and 0.4 or 0.15) end)
            cogBtn:SetScript("OnClick", function(self) if clockOn() then cogShow(self) end end)
        end

        -- Private Dispel Overlay Position (moved here, below the location row).
        local dispelOverlayPosValues = {
            [0] = "Top",
            [1] = "Bottom",
            [2] = "Left",
        }
        local dispelOverlayPosOrder = { 0, 1, 2 }
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Private Dispel Overlay Position", values=dispelOverlayPosValues, order=dispelOverlayPosOrder,
              getValue=function() return SVal("dispelOverlayPosition", 0) end,
              setValue=function(v) SSet("dispelOverlayPosition", v); ReloadAndUpdate() end },
            { type="label", text="" }
        ); y = y - h
        end -- not IS_121 (split location / clock border / private overlay rows)

        if onSection then onSection("dispels", _secY, y) end; _secY = y

        -------------------------------------------------------------------
        --  TOP NAME BAR
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "TOP NAME BAR", y); y = y - h

        local function TNBOff() return not SVal("topNameBarEnabled", false) end

        -- Row 1: Enable Top Name Bar | Height. The master toggle HIDES the
        -- dependent rows entirely while off (SectionToggleSetValue forces the
        -- page rebuild that reveals/hides them).
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
        -- Row 2: Background (+ bg color swatch) | Text Size (+ text swatch + offset cog)
        local tnbRow2
        tnbRow2, h = W:DualRow(parent, y,
            { type="slider", text="Background", min=0, max=100, step=1,
              getValue=function() return SVal("topNameBarBgOpacity", 80) end,
              setValue=function(v) SSet("topNameBarBgOpacity", v) end },
            { type="slider", text="Text Size", min=6, max=30, step=1,
              getValue=function() return SVal("topNameBarTextSize", 11) end,
              setValue=function(v) SSet("topNameBarTextSize", v) end });  y = y - h
        -- Inline bg color swatch (left region)
        do
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
        -- Inline text offset cog (DIRECTIONS) in the Text Size slot
        do
            local rgn = tnbRow2._rightRegion
            -- Offset X/Y cog with the DIRECTIONS icon
            local _, cogShow = EllesmereUI.BuildCogPopup({
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

        -- Row 3: Alignment & Color -- the text align dropdown plus a custom/class
        -- double inline swatch (the swatches double as the color-mode selector,
        -- mirroring the Health Text color swatches). Defaults to class color.
        local tnbRow3
        tnbRow3, h = W:DualRow(parent, y,
            { type="dropdown", text="Alignment & Color",
              values={ center="Center", left="Left", right="Right" },
              order={ "center", "left", "right" },
              getValue=function() return SVal("topNameBarTextAlign", "center") end,
              setValue=function(v) SSet("topNameBarTextAlign", v) end },
            { type="label", text="" });  y = y - h
        -- Inline color swatches (custom rightmost = opens picker, class leftmost).
        -- Clicking a swatch switches topNameBarTextColorMode; each dims when not
        -- the active mode. Added custom-first so it sits next to the dropdown.
        do
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
            -- Class color (leftmost).
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

        if onSection then onSection("topNameBar", _secY, y) end; _secY = y

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
            -- Everything below the display dropdown is inert while "Never"
            local function FBEnabled()
                return (FBSet().display or "never") ~= "never"
            end
            local FB_DISABLED_TIP = "This option requires Add Friendly Boss Group to be set to Healers or Always."

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Add Friendly Boss Group",
                  values = { never="Never", healers="Healers", always="Always" },
                  order  = { "never", "healers", "always" },
                  getValue = function() return FBSet().display or "never" end,
                  -- DependentSetValue: rows below are HIDDEN while Never; only
                  -- the Never <-> enabled flip forces the full rebuild.
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
            if FBEnabled() then
            -- Free Move Position: label left, Move Frames button right (standard
            -- setting layout; Free Move only). Right slot: Boss Health Color.
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
                if EllesmereUI.MakeBorder then
                    EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
                end
                local lbl = btn:CreateFontString(nil, "OVERLAY")
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, GetUseShadow()) end
                lbl:SetFont(EllesmereUI.GetFontPath("raidFrames"), 13, GetOutline())
                lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
                lbl:SetText(EllesmereUI.L("Move Frames"))

                -- Inline cog: Free Move layout options (created before
                -- UpdateMoveBtn so its closure captures the local)
                local _, fmCogShow = EllesmereUI.BuildCogPopup({
                    title = "Free Move Options",
                    rows = {
                        { type="toggle", label="Horizontal Frames",
                          get=function() return FBSet().freeHorizontal == true end,
                          set=function(v)
                              FBSet().freeHorizontal = v
                              if ns.FB_Apply then ns.FB_Apply() end
                              -- Resize/reposition the drag overlay if it is up
                              if ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                                 and ns.FB_SetMoverShown then
                                  ns.FB_SetMoverShown(true)
                              end
                          end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, row)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", btn, "LEFT", -8, 0)
                cogBtn:SetFrameLevel(row:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self)
                    self:SetAlpha(FBSet().position == "free" and 0.4 or 0.15)
                end)
                cogBtn:SetScript("OnClick", function(self) fmCogShow(self) end)

                -- Capture the region now: the shared `row` local is reused by
                -- later rows, so closures must not read it at refresh time.
                local fmRegion = row._leftRegion
                local function MoveAllowed()
                    return FBEnabled() and (FBSet().position == "free")
                        and not InCombatLockdown()
                end
                local function UpdateMoveBtn()
                    local active = ns.FB_IsMoverShown and ns.FB_IsMoverShown()
                    lbl:SetText(active and EllesmereUI.L("Stop Moving") or EllesmereUI.L("Move Frames"))
                    btn:SetAlpha(MoveAllowed() and 1 or 0.35)
                    local freeOn = FBEnabled() and FBSet().position == "free"
                    cogBtn:SetAlpha(freeOn and 0.4 or 0.15)
                    cogBtn:EnableMouse(freeOn)
                    -- Plain-label slots have no native disabled handling
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
            -- Boss Health Color swatch (right slot of the same row)
            do
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
                -- Blocking overlay: the dim alone left the swatch clickable
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
            -- Position settings only matter once something can feed the
            -- group: the tanks toggle or a bound hotkey.
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
                  -- DependentSetValue: the rows below are HIDDEN while the
                  -- section is unconfigured (no tanks toggle AND no hotkey);
                  -- only a configured-state flip forces the full rebuild.
                  setValue = EllesmereUI.DependentSetValue(XFConfigured, function(v)
                      XFSet().showTanks = v
                      if ns.XF_Apply then ns.XF_Apply() end
                      -- Feature may have just gone dark; the mover can't stay up.
                      if not XFConfigured() and ns.XF_SetMoverShown then
                          ns.XF_SetMoverShown(false)
                      end
                      EllesmereUI:RefreshPage()
                  end) }); y = y - h
            do
                local rgn = row._leftRegion
                local kbBtn = CreateFrame("Button", nil, row)
                kbBtn:SetSize(140, 26)
                kbBtn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
                kbBtn:SetFrameLevel(row:GetFrameLevel() + 5)
                kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                local kbBg = kbBtn:CreateTexture(nil, "BACKGROUND")
                kbBg:SetAllPoints()
                kbBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
                if EllesmereUI.MakeBorder then
                    EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, 0.25)
                end
                local kbLbl = kbBtn:CreateFontString(nil, "OVERLAY")
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(kbLbl, GetUseShadow()) end
                kbLbl:SetFont(EllesmereUI.GetFontPath("raidFrames"), 13, GetOutline())
                kbLbl:SetPoint("CENTER")

                local function FormatKey(key)
                    if not key then return EllesmereUI.L("Not Bound") end
                    local parts = {}
                    for mod in key:gmatch("(%u+)%-") do
                        parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                    end
                    local actualKey = key:match("[^%-]+$") or key
                    parts[#parts + 1] = actualKey
                    return table.concat(parts, " + ")
                end

                local function RefreshLabel()
                    kbLbl:SetText(FormatKey(EllesmereUIDB and EllesmereUIDB.extraFramesKey))
                end
                RefreshLabel()

                local listening = false

                kbBtn:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        if listening then
                            listening = false
                            self:EnableKeyboard(false)
                        end
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if EllesmereUIDB.extraFramesKey and _G["ERFExtraFramesBindBtn"] then
                            ClearOverrideBindings(_G["ERFExtraFramesBindBtn"])
                        end
                        local wasConfigured = XFConfigured()
                        EllesmereUIDB.extraFramesKey = nil
                        RefreshLabel()
                        -- Position settings gate on tanks-toggle/hotkey; the
                        -- mover can't stay up if the feature just went dark.
                        if not XFConfigured() and ns.XF_SetMoverShown then
                            ns.XF_SetMoverShown(false)
                        end
                        -- Rows below are hidden while unconfigured: a state
                        -- flip needs the full rebuild, not the fast refresh.
                        if XFConfigured() ~= wasConfigured then
                            EllesmereUI:RefreshPage(true)
                        else
                            EllesmereUI:RefreshPage()
                        end
                        return
                    end
                    if listening then return end
                    listening = true
                    kbLbl:SetText(EllesmereUI.L("Press a key..."))
                    kbBtn:EnableKeyboard(true)
                end)

                kbBtn:SetScript("OnKeyDown", function(self, key)
                    if not listening then
                        self:SetPropagateKeyboardInput(true)
                        return
                    end
                    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                       or key == "LALT" or key == "RALT" then
                        self:SetPropagateKeyboardInput(true)
                        return
                    end
                    self:SetPropagateKeyboardInput(false)
                    if key == "ESCAPE" then
                        listening = false
                        self:EnableKeyboard(false)
                        RefreshLabel()
                        return
                    end
                    local mods = ""
                    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                    if IsControlKeyDown() then mods = mods .. "CTRL-" end
                    if IsAltKeyDown() then mods = mods .. "ALT-" end
                    local fullKey = mods .. key

                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    local bindBtn = _G["ERFExtraFramesBindBtn"]
                    if bindBtn then
                        if InCombatLockdown() then
                            listening = false
                            self:EnableKeyboard(false)
                            RefreshLabel()
                            return
                        end
                        ClearOverrideBindings(bindBtn)
                        SetOverrideBindingClick(bindBtn, true, fullKey, "ERFExtraFramesBindBtn")
                    end
                    local wasConfigured = XFConfigured()
                    EllesmereUIDB.extraFramesKey = fullKey

                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                    -- Rows below are hidden while unconfigured: binding the
                    -- first hotkey flips the state and needs the full rebuild.
                    if XFConfigured() ~= wasConfigured then
                        EllesmereUI:RefreshPage(true)
                    else
                        EllesmereUI:RefreshPage()
                    end
                end)

                kbBtn:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self,
                        "Left-click to set a keybind. Right-click to unbind.\nPress the key while hovering a raid frame to add or remove that player from the Extra Frames group.")
                end)
                kbBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                EllesmereUI.RegisterWidgetRefresh(RefreshLabel)

                rgn:SetScript("OnHide", function()
                    if listening then
                        listening = false
                        kbBtn:EnableKeyboard(false)
                        RefreshLabel()
                    end
                end)
            end

            -- Rows 2-4 are HIDDEN entirely while the section is unconfigured
            -- (no tanks toggle AND no hotkey); the triggers above force the
            -- rebuild whenever the configured state flips.
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
                      -- Full rebuild: the Grow/Wrap Direction row only exists
                      -- while the position is Free Move.
                      EllesmereUI:RefreshPage(true)
                  end },
                { type="label", text="Free Move Position" }); y = y - h
            do
                local rgn = row._rightRegion
                local btn = CreateFrame("Button", nil, row)
                btn:SetSize(140, 26)
                btn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
                btn:SetFrameLevel(row:GetFrameLevel() + 5)
                local bbg = btn:CreateTexture(nil, "BACKGROUND")
                bbg:SetAllPoints()
                bbg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
                if EllesmereUI.MakeBorder then
                    EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
                end
                local lbl = btn:CreateFontString(nil, "OVERLAY")
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, GetUseShadow()) end
                lbl:SetFont(EllesmereUI.GetFontPath("raidFrames"), 13, GetOutline())
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

            -- Row 3 (Free Move only -- hidden otherwise, so Position's
            -- setValue forces a page rebuild): growth axes of the
            -- free-floating grid, with Wrap After tucked into an inline cog
            -- on Wrap Direction. Attached positions need none of this: they
            -- stack group-sized runs of 5 along the raid's own growth
            -- settings, like additional raid groups. Grow Direction
            -- supersedes the old Horizontal Frames cog toggle: its default
            -- derives from the legacy freeHorizontal key, so existing
            -- layouts read back unchanged.
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

            -- The wrap dropdown only offers the two directions perpendicular
            -- to the primary run, so a grow change forces a full page rebuild
            -- to swap its value set.
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
                      -- Keep the legacy key coherent for exports/older reads
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
            -- Inline cog on Wrap Direction: Wrap After slider
            do
                local rgn = row._rightRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
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
            end   -- close Extra Frames hidden-while-unconfigured gate

            if onSection then onSection("extraFrames", _secY, y) end; _secY = y
        end

        -------------------------------------------------------------------
        --  TARGETED SPELLS (raid only -- the party page builds its own
        --  section with the ts* keys; these are tsRaid* and deliberately
        --  OUTSIDE the party section-sync system, so no onSection call)
        -------------------------------------------------------------------
        if not _partyCtx then
            local tsHeader
            tsHeader, h = W:SectionHeader(parent, "TARGETED SPELLS", y); y = y - h

            local function TSApply()
                if ns.TS_ApplySettings then ns.TS_ApplySettings() end
            end

            -- Eyeball: toggle targeted spells visibility on the raid preview
            do
                local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
                local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
                local tsLabel
                for _, rgn in ipairs({ tsHeader:GetRegions() }) do
                    if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "TARGETED SPELLS" then
                        tsLabel = rgn; break
                    end
                end
                local eyeBtn = CreateFrame("Button", nil, tsHeader)
                eyeBtn:SetSize(24, 24)
                if tsLabel then
                    eyeBtn:SetPoint("LEFT", tsLabel, "RIGHT", 5, 0)
                else
                    eyeBtn:SetPoint("LEFT", tsHeader, "BOTTOMLEFT", 85, 8)
                end
                eyeBtn:SetFrameLevel(tsHeader:GetFrameLevel() + 5)
                eyeBtn:SetAlpha(0.4)
                local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                eyeTex:SetAllPoints()

                if ns._tsRaidPreviewVisible == nil then ns._tsRaidPreviewVisible = false end
                local function RefreshTsEye()
                    if IsPreviewOff() then
                        eyeTex:SetTexture(EYE_VISIBLE)
                        eyeBtn:SetAlpha(0.15)
                        return
                    end
                    eyeTex:SetTexture(ns._tsRaidPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.4)
                end
                RefreshTsEye()
                eyeBtn:SetScript("OnClick", function()
                    if IsPreviewOff() then return end
                    ns._tsRaidPreviewVisible = not ns._tsRaidPreviewVisible
                    RefreshTsEye()
                    if ns.TS_RefreshRaidPreview then ns.TS_RefreshRaidPreview() end
                end)
                eyeBtn:SetScript("OnEnter", function(self)
                    if IsPreviewOff() then
                        EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                        return
                    end
                    self:SetAlpha(0.7)
                    EllesmereUI.ShowWidgetTooltip(self, ns._tsRaidPreviewVisible and "Hide targeted spells on preview" or "Show targeted spells on preview")
                end)
                eyeBtn:SetScript("OnLeave", function(self)
                    if not IsPreviewOff() then self:SetAlpha(0.4) end
                    EllesmereUI.HideWidgetTooltip()
                end)
            end  -- close do (eyeball)

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Show Targeted Spells",
                  values={ never="Never", whenHealing="When Healing", always="Always" },
                  order={ "never", "whenHealing", "always" },
                  getValue=function() return SVal("tsRaidMode", "never") end,
                  -- DependentSetValue: rows below are HIDDEN while Never; only
                  -- the Never <-> enabled flip forces the full rebuild.
                  setValue=EllesmereUI.DependentSetValue(
                      function() return SVal("tsRaidMode", "never") ~= "never" end,
                      function(v) SSet("tsRaidMode", v); TSApply(); EllesmereUI:RefreshPage() end) },
                (SVal("tsRaidMode", "never") == "never") and { type="label", text="" } or
                { type="slider", text="Icon Size", min=12, max=48, step=1,
                  getValue=function() return SVal("tsRaidIconSize", 24) end,
                  setValue=function(v) SSet("tsRaidIconSize", v); TSApply() end });  y = y - h
            if SVal("tsRaidMode", "never") ~= "never" then
            -- Inline cog on Icon Size: Icon Zoom
            do
                local rgn = row._rightRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Icon Zoom",
                    rows = {
                        { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                          get=function() return SVal("tsRaidIconZoom", 0.08) end,
                          set=function(v) SSet("tsRaidIconZoom", v); TSApply() end },
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

            -- Row 2: Icon Position (+ cog for X/Y) | Growth Direction
            local tsPositionValues = {
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
            local tsPositionOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

            local tsGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
            local tsGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

            local function GetDefaultTSGrow(pos)
                if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
                if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
                if pos == "top" then return "DOWN" end
                if pos == "bottom" then return "UP" end
                return "CENTER"
            end

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Icon Position", values=tsPositionValues, order=tsPositionOrder,
                  getValue=function() return string.lower(SVal("tsRaidPosition", "center")) end,
                  setValue=function(v)
                      SSet("tsRaidPosition", v)
                      SSet("tsRaidGrowDirection", GetDefaultTSGrow(v))
                      TSApply()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Growth Direction", values=tsGrowValues, order=tsGrowOrder,
                  getValue=function() return SVal("tsRaidGrowDirection", "CENTER") end,
                  setValue=function(v) SSet("tsRaidGrowDirection", v); TSApply() end });  y = y - h
            -- Cog for targeted spells offset X/Y
            do
                local rgn = row._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Targeted Spells Offset",
                    rows = {
                        { type="slider", label="Offset X", min=-50, max=50, step=1,
                          get=function() return SVal("tsRaidOffsetX", 0) end,
                          set=function(v) SSet("tsRaidOffsetX", v); TSApply() end },
                        { type="slider", label="Offset Y", min=-50, max=50, step=1,
                          get=function() return SVal("tsRaidOffsetY", 0) end,
                          set=function(v) SSet("tsRaidOffsetY", v); TSApply() end },
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
            end   -- close Targeted Spells (raid) hidden-while-disabled gate

            _secY = y
        end

        -------------------------------------------------------------------
        --  RANGE & TOOLTIP
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        -- Row 1: OOR Alpha | Show Raid Frames Tooltip (dropdown + cog)
        -- The dropdown is a pure VIEW over the legacy keys for existing users:
        -- when tooltipMode is unset it derives the displayed option from the old
        -- showTooltip toggle + the old global "show in combat" flag, so nobody's
        -- behavior changes until they actively pick an option. (Same derive as
        -- the runtime ns._ResolveTooltipMode.)
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
                  -- Re-apply range alpha live: SetAlphaFromBoolean bakes the value
                  -- in at call time, so already-OOR units keep the old alpha until
                  -- a range re-eval. Seed all buttons so the slider takes effect now.
                  if ns._RangeSeedAll then ns._RangeSeedAll() end
              end },
            { type="dropdown", text="Show Raid Frames Tooltip",
              tooltip="Controls when the tooltip appears as you hover a raid or party frame",
              values={ always="Always", outOfCombat="Out of Combat", outOfBossCombat="Out of Boss Combat", never="Never" },
              order={ "always", "outOfCombat", "outOfBossCombat", "never" },
              getValue=function() return CurTooltipMode() end,
              setValue=function(v) SSet("tooltipMode", v) end });  y = y - h
        -- Cog: buff/HoT aura-icon tooltips (Buff Manager). Hidden by default --
        -- matches the long-standing behavior where buff icons showed no tooltip;
        -- opt in here. When shown, the aura tip still follows the tooltip mode
        -- on this dropdown (mode governs when, this governs whether).
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Tooltip Settings",
                rows = {
                    { type="toggle", label="Hide Buff Tooltips",
                      tooltip="Hide the tooltip when hovering a buff/HoT icon on a raid or party frame.",
                      get=function() return SVal("buffHideTooltips", true) end,
                      set=function(v) SSet("buffHideTooltips", v); if ns.ReloadFrames then ns.ReloadFrames() end end },
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
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
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
                            local ovs = db.profile.raidSizeOverrides
                            if ovs then
                                ovs[tier] = nil
                                -- Conversion markers (_topLeftAnchored /
                                -- _cornerAnchored) always remain in the
                                -- table; only tier TABLES count as content.
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

                    -- Inline cog for X/Y offset (on width slider, RESIZE icon)
                    do
                        local rgn = sizeRow._leftRegion
                        local function EnsureTierOv()
                            local ovs = ns._EnsureRaidSizeOverrides()
                            if not ovs[tier] then
                                ovs[tier] = { width = db.profile.frameWidth or 125, height = db.profile.frameHeight or 60 }
                            end
                            return ovs[tier]
                        end
                        local function TierGrowthChanged()
                            -- Resync BOTH representations: ReloadAndUpdate
                            -- reloads the live frames (incl. the growth-corner
                            -- anchor) and re-shows the active size preview
                            -- itself, so the two can never diverge.
                            ReloadAndUpdate()
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
                                      -- Update BOTH: live frames (cheap corner
                                      -- re-anchor, per tick) and the size
                                      -- preview when it shows this tier.
                                      if ns._ApplyTierOffset then ns._ApplyTierOffset() end
                                      if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                          ns._ShowSizePreview(tier)
                                      end
                                  end },
                                { type="slider", label="Y Offset", min=-200, max=200, step=1,
                                  get=function()
                                      local ov = db.profile.raidSizeOverrides
                                      return ov and ov[tier] and ov[tier].offsetY or 0
                                  end,
                                  set=function(v)
                                      EnsureTierOv().offsetY = v
                                      -- Update BOTH: live frames (cheap corner
                                      -- re-anchor, per tick) and the size
                                      -- preview when it shows this tier.
                                      if ns._ApplyTierOffset then ns._ApplyTierOffset() end
                                      if ns._sizePreviewTier == tier and ns._ShowSizePreview then
                                          ns._ShowSizePreview(tier)
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

            -- Auto Resize Icons: checkbox dropdown over the existing
            -- autoResizeIndicators key ("Indicators & Auras") plus the
            -- autoResizeTrackedBuffs key ("Tracked Buffs"). Pure view -- no
            -- migration; existing autoResizeIndicators values are preserved and
            -- Tracked Buffs defaults on (matching the prior always-on behavior).
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
                          -- Copy current 20 man size as starting point
                          ovs[tier] = {
                              width = db.profile.frameWidth or 125,
                              height = db.profile.frameHeight or 60,
                          }
                          ReloadAndUpdate()
                          EllesmereUI:RefreshPage(true)
                      end },
                    autoResizeSlot);  y = y - h
            else
                -- All tiers added, just show Auto Resize Icons
                autoResizeRow, h = W:DualRow(parent, y,
                    { type="label", text="" },
                    autoResizeSlot);  y = y - h
            end
            -- Overlay the checkbox dropdown onto the right region (mirrors the
            -- "Hover Borders" conversion pattern).
            do
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
                        -- Tracked Buffs defaults on; Indicators & Auras defaults off.
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

        -- Row 2: Frame Spacing | Group Spacing
        _, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Frame Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("cellSpacing", 2) end,
              setValue=function(v) SSet("cellSpacing", v) end },
            { type="slider", pixel=true, text="Group Spacing", min=-1, max=15, step=1,
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

            -- Inline cog: Hide Empty Groups
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Show Groups",
                rows = {
                    { type="toggle", label="Hide Empty Groups",
                      tooltip="Collapse subgroups that have no members so the remaining groups close ranks. For example, if only groups 1, 2, 3 and 6 have players, they show with no gaps instead of leaving empty space where groups 4 and 5 would be. Real raid frames only.",
                      get=function() return SVal("hideEmptyGroups", true) end,
                      set=function(v) SSet("hideEmptyGroups", v) end },
                    { type="toggle", label="Exclude Hidden from Size",
                      tooltip="When using custom raid sizes, don't count members in hidden groups toward the raid-size breakpoint. For example, if you hide groups 7 and 8, a full 40-man raid is sized as if it were 24-man instead of jumping to the 30-man frame size. Has no effect unless you have custom raid sizes set up.",
                      get=function() return SVal("excludeHiddenGroupsFromSize", true) end,
                      set=function(v) SSet("excludeHiddenGroupsFromSize", v) end },
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


        y = BuildVisualSections(parent, y, W)

        -- 12.1: the Auras page is retired; its surviving Private Auras
        -- section renders here (the shared builder gates everything else
        -- out on 12.1). Resolved through ns -- this function is defined
        -- above the builder's forward declaration.
        if EllesmereUI.IS_121 and ns._RF_BuildDebuffSections then
            y = ns._RF_BuildDebuffSections(parent, y, W)
        end

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
            -- The container resize is deferred off the hot path (container
            -- SetSize re-processes the secure header = blink), so run the full
            -- reload the moment the drag releases -- via the slider system's
            -- end-of-drag callback set -- so the frames snap to their final
            -- position immediately instead of on options close.
            if EllesmereUI._sliderDragging then
                EllesmereUI._deferredDriftChecks = EllesmereUI._deferredDriftChecks or {}
                EllesmereUI._deferredDriftChecks[PartyReloadAndUpdate] = true
            else
                -- Direct set (input box / final post-release commit): finalize
                -- now and drop any pending registration so it runs once.
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

        -- Inline cog next to Sort By: Prioritize Class toggle + drag-to-reorder
        -- Class Order list (party only). The toggle disables the order list.
        do
            local rgn = pSortRow._rightRegion
            -- Build the class list in saved order, always covering all 13 classes
            -- (appends any missing/new classes from the default alphabetical order).
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
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Class Sorting",
                rows = {
                    { type = "toggle", label = "Prioritize Class",
                      tooltip = "This will not override sorting by role",
                      get = function() return db.profile.partyPrioritizeClass end,
                      set = function(v) db.profile.partyPrioritizeClass = v; PartyReloadAndUpdate() end },
                    { type = "reorder", label = "Class Order", hint = "Drag to Reorder Classes",
                      items = GetClassItems,
                      set = function(keys) db.profile.partyClassOrder = keys; PartyReloadAndUpdate() end,
                      disabled = function() return not db.profile.partyPrioritizeClass end },
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
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end

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

        -- Row 5: Auto Resize Icons (checkbox dropdown) | Frame Spacing
        -- Checkbox dropdown over the existing partyAutoResizeIndicators key
        -- ("Indicators & Auras") plus partyAutoResizeTrackedBuffs ("Tracked
        -- Buffs"). Pure view -- no migration; existing values preserved and
        -- Tracked Buffs defaults on (matching the prior always-on behavior).
        local partyAutoResizeRow
        partyAutoResizeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Auto Resize Icons",
              values={ __placeholder = "All" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="slider", pixel=true, text="Frame Spacing", min=-1, max=15, step=1,
              getValue=function() return SVal("partyCellSpacing", db.profile.cellSpacing or 2) end,
              setValue=function(v) PSSet("partyCellSpacing", v) end });  y = y - h
        -- Overlay the checkbox dropdown onto the LEFT region (Auto Resize Icons
        -- sits in the left slot; mirrors the Frames-tab conversion).
        do
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
                    -- Tracked Buffs defaults on; Indicators & Auras defaults off.
                    if k == "trackedBuffs" then return SVal(arKeyMap[k], true) end
                    return SVal(arKeyMap[k], false)
                end,
                function(k, v) PSSet(arKeyMap[k], v) end)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
        end

        -- Row 6: Flip Frame Growth
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Flip Frame Growth",
              tooltip="Flips the direction the frames grow in: vertical frames grow up instead of down, horizontal frames grow left instead of right.",
              getValue=function() return db.profile.partyFlipGrowth or false end,
              setValue=function(v) db.profile.partyFlipGrowth = v; PartyReloadAndUpdate() end },
            { type="label", text="" });  y = y - h

        -------------------------------------------------------------------
        --  TARGETED SPELLS (party; the raid Frames tab builds its own
        --  section with independent tsRaid* keys)
        -------------------------------------------------------------------
        do
            local tsHeader
            tsHeader, h = W:SectionHeader(parent, "TARGETED SPELLS", y); y = y - h

            local function TSApply()
                if ns.TS_ApplySettings then ns.TS_ApplySettings() end
            end

            -- Eyeball: toggle targeted spells visibility on the party preview
            do
                local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
                local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
                local tsLabel
                for _, rgn in ipairs({ tsHeader:GetRegions() }) do
                    if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "TARGETED SPELLS" then
                        tsLabel = rgn; break
                    end
                end
                local eyeBtn = CreateFrame("Button", nil, tsHeader)
                eyeBtn:SetSize(24, 24)
                if tsLabel then
                    eyeBtn:SetPoint("LEFT", tsLabel, "RIGHT", 5, 0)
                else
                    eyeBtn:SetPoint("LEFT", tsHeader, "BOTTOMLEFT", 85, 8)
                end
                eyeBtn:SetFrameLevel(tsHeader:GetFrameLevel() + 5)
                eyeBtn:SetAlpha(0.4)
                local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                eyeTex:SetAllPoints()

                if ns._tsPreviewVisible == nil then ns._tsPreviewVisible = false end
                local function RefreshTsEye()
                    if IsPreviewOff() then
                        eyeTex:SetTexture(EYE_VISIBLE)
                        eyeBtn:SetAlpha(0.15)
                        return
                    end
                    eyeTex:SetTexture(ns._tsPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
                    eyeBtn:SetAlpha(0.4)
                end
                RefreshTsEye()
                eyeBtn:SetScript("OnClick", function()
                    if IsPreviewOff() then return end
                    ns._tsPreviewVisible = not ns._tsPreviewVisible
                    RefreshTsEye()
                    if ns.TS_RefreshPreview then ns.TS_RefreshPreview() end
                end)
                eyeBtn:SetScript("OnEnter", function(self)
                    if IsPreviewOff() then
                        EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                        return
                    end
                    self:SetAlpha(0.7)
                    EllesmereUI.ShowWidgetTooltip(self, ns._tsPreviewVisible and "Hide targeted spells on preview" or "Show targeted spells on preview")
                end)
                eyeBtn:SetScript("OnLeave", function(self)
                    if not IsPreviewOff() then self:SetAlpha(0.4) end
                    EllesmereUI.HideWidgetTooltip()
                end)
            end  -- close do (eyeball)

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Show Targeted Spells",
                  values={ never="Never", whenHealing="When Healing", always="Always" },
                  order={ "never", "whenHealing", "always" },
                  getValue=function() return SVal("tsMode", "whenHealing") end,
                  -- DependentSetValue: rows below are HIDDEN while Never; only
                  -- the Never <-> enabled flip forces the full rebuild.
                  setValue=EllesmereUI.DependentSetValue(
                      function() return SVal("tsMode", "whenHealing") ~= "never" end,
                      function(v) SSet("tsMode", v); TSApply(); EllesmereUI:RefreshPage() end) },
                (SVal("tsMode", "whenHealing") == "never") and { type="label", text="" } or
                { type="slider", text="Icon Size", min=12, max=48, step=1,
                  getValue=function() return SVal("tsIconSize", 24) end,
                  setValue=function(v) SSet("tsIconSize", v); TSApply() end });  y = y - h
            if SVal("tsMode", "whenHealing") ~= "never" then
            -- Inline cog on Icon Size: Icon Zoom
            do
                local rgn = row._rightRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Icon Zoom",
                    rows = {
                        { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                          get=function() return SVal("tsIconZoom", 0.08) end,
                          set=function(v) SSet("tsIconZoom", v); TSApply() end },
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

            -- Row 2: Icon Position (+ cog for X/Y) | Growth Direction
            local tsPositionValues = {
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
            local tsPositionOrder = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

            local tsGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
            local tsGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

            local function GetDefaultTSGrow(pos)
                if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
                if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
                if pos == "top" then return "DOWN" end
                if pos == "bottom" then return "UP" end
                return "CENTER"
            end

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Icon Position", values=tsPositionValues, order=tsPositionOrder,
                  getValue=function() return string.lower(SVal("tsPosition", "center")) end,
                  setValue=function(v)
                      SSet("tsPosition", v)
                      SSet("tsGrowDirection", GetDefaultTSGrow(v))
                      TSApply()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Growth Direction", values=tsGrowValues, order=tsGrowOrder,
                  getValue=function() return SVal("tsGrowDirection", "CENTER") end,
                  setValue=function(v) SSet("tsGrowDirection", v); TSApply() end });  y = y - h
            -- Cog for targeted spells offset X/Y
            do
                local rgn = row._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Targeted Spells Offset",
                    rows = {
                        { type="slider", label="Offset X", min=-50, max=50, step=1,
                          get=function() return SVal("tsOffsetX", 0) end,
                          set=function(v) SSet("tsOffsetX", v); TSApply() end },
                        { type="slider", label="Offset Y", min=-50, max=50, step=1,
                          get=function() return SVal("tsOffsetY", 0) end,
                          set=function(v) SSet("tsOffsetY", v); TSApply() end },
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
            end   -- close Targeted Spells (party) hidden-while-disabled gate
        end

        -------------------------------------------------------------------
        --  ALL VISUAL SECTIONS
        --  _partyCtx makes SGet/SSet/SVal read/write "party_<key>" keys,
        --  so the exact same section builders produce party-specific controls.
        --  Synced sections get a blocking overlay per-section.
        -------------------------------------------------------------------
        local CPAD = EllesmereUI.CONTENT_PAD or 10
        local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

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
        -- 12.1 redesign: only the PRIVATE AURAS section survives here (it
        -- renders on the Frames/Party pages; the Auras page is retired).
        -- Defensives/externals and the debuff display/style are owned by
        -- the Buff/Debuff Managers on 12.1. The 12.0 page is untouched.
        if not EllesmereUI.IS_121 then
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

        -- Row 2: Growth Direction | Size (+ icon zoom cog)
        local defSizeRow
        defSizeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Growth Direction", values=defGrowValues, order=defGrowOrder,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defGrowDirection", "CENTER") end,
              setValue=function(v) SSet("defGrowDirection", v) end },
            { type="slider", text="Size", min=10, max=60, step=1,
              disabled=DefDisabled, disabledTooltip="Show Defensives & Externals",
              getValue=function() return SVal("defSize", 22) end,
              setValue=function(v) SSet("defSize", v) end });  y = y - h
        -- Inline cog on Size: Icon Zoom
        do
            local rgn = defSizeRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                      get=function() return SVal("defIconZoom", 0.08) end,
                      set=function(v) SSet("defIconZoom", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(DefDisabled() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) if not DefDisabled() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(DefDisabled() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) if not DefDisabled() then cogShow(self) end end)
            EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(DefDisabled() and 0.15 or 0.4) end)
        end

        -- Row 3: Spacing | Border Size (+ swatch)
        local defBdrRow
        defBdrRow, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
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
                    { type="slider", label="Text Size", min=6, max=26, step=1,
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

        if onSection then onSection("defensives", _secY, y) end
        end -- not IS_121 (defensives section)
        -------------------------------------------------------------------
        --  PRIVATE AURAS
        -------------------------------------------------------------------
        local paHeader
        _secY = y
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
        local paPosOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
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
                  -- Clear/re-seed the preview private-aura icons so "None" hides
                  -- them on the preview immediately (matches the live frames).
                  if ns.RestartPvAuraTicker then ns.RestartPvAuraTicker() end
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
            { type="slider", text="Icon Size", min=10, max=60, step=1,
              getValue=function() return SVal("paSize", 20) end,
              setValue=function(v) SSet("paSize", v) end },
            { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
              getValue=function() return SVal("paSpacing", 0) end,
              setValue=function(v) SSet("paSpacing", v) end });  y = y - h

        -- Row 3: Show Countdown Text (Border Size removed -- Blizzard's border is
        -- always scaled 1:1 to the icon; no longer user-configurable)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Countdown Text",
              getValue=function() return SVal("paShowCountdown", false) end,
              setValue=function(v) SSet("paShowCountdown", v) end },
            { type="toggle", text="Hide Tooltips",
              getValue=function() return SVal("paHideTooltip", true) end,
              setValue=function(v) SSet("paHideTooltip", v) end });  y = y - h

        if onSection then onSection("privateAuras", _secY, y) end
        -- 12.1 redesign: everything below is retired here (see the gate at
        -- the top of this function).
        if not EllesmereUI.IS_121 then
        -------------------------------------------------------------------
        --  DEBUFFS
        -------------------------------------------------------------------
        --  DEBUFF DISPLAY
        -------------------------------------------------------------------
        local debuffHeader
        _secY = y
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
		local debuffWrapValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
        local debuffWrapOrder = { "RIGHT", "LEFT", "UP", "DOWN" }

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

        -- Row 3: Max Debuffs | Hide Tooltips
        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Debuffs", min=1, max=8, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffCap", 3) end,
              setValue=function(v) SSet("debuffCap", v) end },
            { type="toggle", text="Hide Tooltips",
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffHideTooltips", true) end,
              setValue=function(v) SSet("debuffHideTooltips", v) end });  y = y - h
			  
		-- Row 4: Per Row (1 = single line, no wrap) | Wrap Direction
        _, h = W:DualRow(parent, y,
            { type="slider", text="Per Row", min=1, max=8, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffPerRow", 1) end,
              setValue=function(v) SSet("debuffPerRow", v); EllesmereUI:RefreshPage() end },
            { type="dropdown", text="Wrap Direction", values=debuffWrapValues, order=debuffWrapOrder,
              disabled=function()
                  return SVal("debuffFilter", "all") == "none"
                      or (SVal("debuffPerRow", 1) or 1) <= 1
              end,
              disabledTooltip=function()
                  if SVal("debuffFilter", "all") == "none" then return "Show Debuffs" end
                  return "Per Row more than 1"
              end,
              getValue=function() return SVal("debuffWrapDirection", "UP") end,
              setValue=function(v) SSet("debuffWrapDirection", v) end });  y = y - h

        -------------------------------------------------------------------
        --  DEBUFF STYLE
        -------------------------------------------------------------------
        if onSection then onSection("debuffDisplay", _secY, y) end; _secY = y
        _, h = W:SectionHeader(parent, "DEBUFF STYLE", y); y = y - h

        -- Row 1: Debuff Size | Border Size (+ swatch)
        local dbBorderRow
        dbBorderRow, h = W:DualRow(parent, y,
            { type="slider", text="Debuff Size", min=10, max=60, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffSize", 18) end,
              setValue=function(v) SSet("debuffSize", v) end },
            { type="slider", text="Border Size", min=0, max=4, step=1,
              disabled=function() return SVal("debuffFilter", "all") == "none" end,
              disabledTooltip="Show Debuffs",
              getValue=function() return SVal("debuffBorderSize", 1) end,
              setValue=function(v) SSet("debuffBorderSize", v) end });  y = y - h
        -- Inline cog on Debuff Size: Icon Zoom
        do
            local rgn = dbBorderRow._leftRegion
            local function DbOff() return SVal("debuffFilter", "all") == "none" end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                      get=function() return SVal("debuffIconZoom", 0.08) end,
                      set=function(v) SSet("debuffIconZoom", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(DbOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) if not DbOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(DbOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) if not DbOff() then cogShow(self) end end)
            EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(DbOff() and 0.15 or 0.4) end)
        end
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
            { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
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
                    { type="slider", label="Text Size", min=6, max=26, step=1,
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
                    { type="slider", label="Text Size", min=6, max=26, step=1,
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

        -- Row 4: CC Debuff Glow (style dropdown + class/custom swatches + pixel cog)
        -- 1:1 of CDM's Buff Glow control, applied to crowd-control debuff icons.
        do
            local PP = EllesmereUI.PanelPP or EllesmereUI.PP
            local GLOW_VALUES = { [0] = "None" }
            local GLOW_ORDER = { 0 }
            local Styles = EllesmereUI.Glows and EllesmereUI.Glows.STYLES
            if Styles then
                for i, entry in ipairs(Styles) do
                    if not entry.shapeGlow then
                        GLOW_VALUES[i] = entry.name
                        GLOW_ORDER[#GLOW_ORDER + 1] = i
                    end
                end
            end
            local function glowOff() return SVal("debuffFilter", "all") == "none" end
            local ccGlowRow
            ccGlowRow, h = W:DualRow(parent, y,
                { type="dropdown", text="CC Debuff Glow",
                  values=GLOW_VALUES, order=GLOW_ORDER,
                  disabled=glowOff, disabledTooltip="Show Debuffs",
                  getValue=function() return SVal("debuffCCGlowType", 0) end,
                  setValue=function(v) SSet("debuffCCGlowType", v); EllesmereUI:RefreshPage() end },
                { type="label", text="" });  y = y - h

            -- Inline class + custom colour swatches (left of the dropdown), then the
            -- pixel-glow cog to their left. Mirrors the CDM Buff Glow row.
            do
                local leftRgn = ccGlowRow._leftRegion
                local ctrl = leftRgn._control

                local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                    leftRgn, ccGlowRow:GetFrameLevel() + 3,
                    function()
                        local _, classFile = UnitClass("player")
                        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                        if cc then return cc.r, cc.g, cc.b end
                        return 1, 0.82, 0
                    end,
                    function() end, false, 20)
                PP.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                classSwatch:SetScript("OnClick", function()
                    if glowOff() then return end
                    SWrite("debuffCCGlowClassColor", true); ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end)
                classSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored") end)
                classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                    leftRgn, ccGlowRow:GetFrameLevel() + 3,
                    function() return SVal("debuffCCGlowR", 1.0), SVal("debuffCCGlowG", 0.776), SVal("debuffCCGlowB", 0.376) end,
                    function(r, g, b)
                        SWrite("debuffCCGlowR", r); SWrite("debuffCCGlowG", g); SWrite("debuffCCGlowB", b)
                        ReloadAndUpdate()
                    end, false, 20)
                PP.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                glowSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(glowSwatch, "Custom Colored") end)
                glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local origGlowClick = glowSwatch:GetScript("OnClick")
                glowSwatch:SetScript("OnClick", function(self, ...)
                    if glowOff() then return end
                    if SGet("debuffCCGlowClassColor") then
                        SWrite("debuffCCGlowClassColor", false); ReloadAndUpdate(); EllesmereUI:RefreshPage()
                        return
                    end
                    if (SVal("debuffCCGlowType", 0) or 0) == 0 then return end
                    if origGlowClick then origGlowClick(self, ...) end
                end)

                leftRgn._lastInline = glowSwatch

                local function UpdateGlowState()
                    local gt = SVal("debuffCCGlowType", 0) or 0
                    local noGlow = gt == 0 or glowOff()
                    local isClassColored = SGet("debuffCCGlowClassColor")
                    glowSwatch:SetAlpha((isClassColored or noGlow) and 0.3 or 1)
                    classSwatch:SetAlpha((isClassColored and not noGlow) and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateGlowSwatch(); updateClassSwatch(); UpdateGlowState() end)
                UpdateGlowState()

                -- Pixel-glow cog, enabled only for Pixel Glow.
                local function pixelOff() return (SVal("debuffCCGlowType", 0) or 0) ~= 1 or glowOff() end
                local _, pgCogShow = EllesmereUI.BuildCogPopup({
                    title = "Pixel Glow",
                    rows = {
                        { type="slider", label="Lines", min=2, max=16, step=1,
                          get=function() return SVal("debuffCCGlowLines", 8) end,
                          set=function(v) SSet("debuffCCGlowLines", v) end },
                        { type="slider", label="Thickness", min=1, max=4, step=1,
                          get=function() return SVal("debuffCCGlowThickness", 2) end,
                          set=function(v) SSet("debuffCCGlowThickness", v) end },
                        -- Speed shown inverted (higher = faster) like the CDM cog.
                        { type="slider", label="Speed", min=1, max=8, step=1,
                          get=function() return 9 - (SVal("debuffCCGlowSpeed", 4)) end,
                          set=function(v) SSet("debuffCCGlowSpeed", 9 - v) end },
                        { type="toggle", label="Background",
                          get=function() return SVal("debuffCCGlowBackground", false) == true end,
                          set=function(v) SSet("debuffCCGlowBackground", v and true or nil) end },
                        { type="colorpicker", label="Background Color",
                          get=function() return SVal("debuffCCGlowBackgroundR", 0), SVal("debuffCCGlowBackgroundG", 0), SVal("debuffCCGlowBackgroundB", 0) end,
                          set=function(r, g, b)
                              SWrite("debuffCCGlowBackgroundR", r)
                              SWrite("debuffCCGlowBackgroundG", g)
                              SWrite("debuffCCGlowBackgroundB", b)
                              ReloadAndUpdate()
                          end,
                          disabled=function() return SVal("debuffCCGlowBackground", false) ~= true end,
                          disabledTooltip=EllesmereUI.DisabledTooltip("Pixel Glow Background") },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, leftRgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
                leftRgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(pixelOff() and 0.15 or 0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self)
                    if pixelOff() then
                        EllesmereUI.ShowWidgetTooltip(self, "This option requires Pixel Glow to be the selected glow type")
                    else self:SetAlpha(0.7) end
                end)
                cogBtn:SetScript("OnLeave", function(self) EllesmereUI.HideWidgetTooltip(); self:SetAlpha(pixelOff() and 0.15 or 0.4) end)
                cogBtn:SetScript("OnClick", function(self) if pixelOff() then return end pgCogShow(self) end)
                EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(pixelOff() and 0.15 or 0.4) end)
            end
        end

        if onSection then onSection("debuffStyle", _secY, y) end
        end -- not IS_121 (debuff display/style sections)
        return y
    end
    -- 12.1: the Frames page appends the surviving Private Auras section via
    -- this export (BuildMainPage is defined above the forward declaration,
    -- so it resolves through ns at call time).
    ns._RF_BuildDebuffSections = BuildDebuffSections

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
        -- 12.1 Buff Manager v2 runs INSIDE the legacy page shell (the
        -- storage accessor swaps under the activation flag) -- the
        -- from-scratch replacement page was rejected in field review and
        -- is no longer routed to.
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
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local accentColor = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
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
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
            fs:SetFont(fontPath, size, "")
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        local cy = -PAD

        -- Section header
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
            lbl:SetText(EllesmereUI.L(label))

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
                                    local ac = EllesmereUI.ELLESMERE_GREEN
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
        -- 12.1: the Auras page is retired entirely (debuffs and
        -- defensives/externals live in the managers; private auras moved to
        -- the Frames page).
        pages       = EllesmereUI.IS_121
            and { PAGE_MAIN, PAGE_PARTY, PAGE_BUFFS, PAGE_DM, PAGE_CLICKCAST }
            or  { PAGE_MAIN, PAGE_DEBUFFS, PAGE_PARTY, PAGE_BUFFS, PAGE_CLICKCAST },
        searchTerms = rfSearchTerms,
        buildPage   = function(pageName, parent, yOffset)
            -- All of the cleanup/preview logic below acts on live, real state
            -- (the buff-manager/click-cast roots, and the raid/party preview
            -- overlays over the player's actual frames) keyed only on the
            -- pageName this particular call happens to build -- not on
            -- whether the player is really looking at this module at all.
            -- During an off-screen search pre-build, pageName cycles through
            -- every page in this module's `pages` regardless of what's really
            -- on screen, so none of it may run here.
            --
            -- PAGE_BUFFS / PAGE_CLICKCAST go further: their builders
            -- (BuildBuffManagerPage -> ns.BM_BuildPage, ns.CC_BuildPage)
            -- bypass the given `parent` entirely and build directly onto the
            -- live, shared EllesmereUI._scrollFrame, so building them here
            -- would inject real, visible UI onto whatever the player is
            -- actually looking at. Skip them; they're indexed normally the
            -- first time the player visits them live.
            --
            -- _partyCtx (read by SGet/SSet/SVal inside getValue/setValue
            -- closures) is deliberately left untouched here: this hidden
            -- pass's widgets and their closures are discarded with the
            -- wrapper and never invoked again, so only the live path needs
            -- it to be correct.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_MAIN then
                    return BuildMainPage(pageName, parent, yOffset)
                elseif pageName == PAGE_PARTY then
                    return BuildPartyPage(pageName, parent, yOffset)
                elseif pageName == PAGE_DEBUFFS then
                    return BuildDebuffsPage(pageName, parent, yOffset)
                end
                return
            end
            -- Clean up Buff Manager root when switching away
            if pageName ~= PAGE_BUFFS and ns._bmRoot then
                ns._bmRoot:Hide()
                ns._bmRoot:SetParent(nil)
                ns._bmRoot = nil
            end
            -- Clean up Debuff Manager root when switching away (12.1 only;
            -- ns._dmRoot is never set on 12.0)
            if pageName ~= PAGE_DM and ns._dmRoot then
                ns._dmRoot:Hide()
                ns._dmRoot:SetParent(nil)
                ns._dmRoot = nil
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
            elseif pageName == PAGE_DM then
                -- 12.1 only (the page is only registered there); builder
                -- lives in the self-gated manager-pages file.
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
            -- Mirror buildPage's unconditional root cleanup (see above): this
            -- fires instead of buildPage whenever the target page was already
            -- cached, so without this, switching away from Buffs/HoverCast to
            -- an already-cached page (e.g. Party) never hid ns._bmRoot/
            -- ns._ccRoot -- both are built onto the shared live scroll frame,
            -- not a per-page wrapper, so they stayed stuck on screen over
            -- whatever page was cache-restored next.
            if pageName ~= PAGE_BUFFS and ns._bmRoot then
                ns._bmRoot:Hide()
                ns._bmRoot:SetParent(nil)
                ns._bmRoot = nil
            end
            if pageName ~= PAGE_DM and ns._dmRoot then
                ns._dmRoot:Hide()
                ns._dmRoot:SetParent(nil)
                ns._dmRoot = nil
            end
            if pageName ~= PAGE_CLICKCAST and ns._ccRoot then
                if ns._ccGridPopup then ns._ccGridPopup:Hide(); ns._ccGridPopup = nil end
                if ns._ccSpecPopup then ns._ccSpecPopup:Hide(); ns._ccSpecPopup = nil end
                if ns._ccQBPopup then ns._ccQBPopup:Hide(); ns._ccQBPopup = nil end
                if ns._ccSpellStrip then ns._ccSpellStrip:Hide(); ns._ccSpellStrip:SetParent(nil); ns._ccSpellStrip = nil end
                ns._ccRoot:Hide()
                ns._ccRoot:SetParent(nil)
                ns._ccRoot = nil
            end
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
            if ns._dmAddPopup then ns._dmAddPopup:Hide() end
            if ns._bm2FilterEditor then ns._bm2FilterEditor:Hide(); ns._bm2FilterEditor = nil end
            if ns._bm2Menu then ns._bm2Menu:Hide(); ns._bm2Menu = nil end
            if ns._dmRoot then
                ns._dmRoot:Hide(); ns._dmRoot:SetParent(nil); ns._dmRoot = nil
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
        if ns._dmAddPopup then ns._dmAddPopup:Hide() end
            if ns._bm2FilterEditor then ns._bm2FilterEditor:Hide(); ns._bm2FilterEditor = nil end
            if ns._bm2Menu then ns._bm2Menu:Hide(); ns._bm2Menu = nil end
        if ns._dmRoot then ns._dmRoot:Hide(); ns._dmRoot:SetParent(nil); ns._dmRoot = nil end
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
                if ns._dmAddPopup then ns._dmAddPopup:Hide() end
            if ns._bm2FilterEditor then ns._bm2FilterEditor:Hide(); ns._bm2FilterEditor = nil end
            if ns._bm2Menu then ns._bm2Menu:Hide(); ns._bm2Menu = nil end
                if ns._dmRoot then
                    ns._dmRoot:Hide(); ns._dmRoot:SetParent(nil); ns._dmRoot = nil
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
        ["ABSORBS"]                = "absorbs",
        ["POWER BAR"]              = "powerBar",
        ["TEXT DISPLAY"]           = "textDisplay",
        ["INDICATORS"]             = "indicators",
        ["DISPELS"]                = "dispels",
        ["TOP NAME BAR"]           = "topNameBar",
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
            ns._absorbsPreviewVisible = false
            ns._tsPreviewVisible = false
            if ns.TS_RefreshPreview then ns.TS_RefreshPreview() end
            ns._tsRaidPreviewVisible = false
            if ns.TS_RefreshRaidPreview then ns.TS_RefreshRaidPreview() end
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
            if pageName == PAGE_BUFFS or pageName == PAGE_DM or pageName == PAGE_CLICKCAST then
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
            -- Switching away from Debuff Manager: clean up DM root
            if pageName ~= PAGE_DM and ns._dmRoot then
                if ns._dmAddPopup then ns._dmAddPopup:Hide() end
            if ns._bm2FilterEditor then ns._bm2FilterEditor:Hide(); ns._bm2FilterEditor = nil end
            if ns._bm2Menu then ns._bm2Menu:Hide(); ns._bm2Menu = nil end
                ns._dmRoot:Hide(); ns._dmRoot:SetParent(nil); ns._dmRoot = nil
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



