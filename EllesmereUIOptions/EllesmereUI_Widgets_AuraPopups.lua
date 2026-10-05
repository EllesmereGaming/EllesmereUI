if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_AuraPopups.lua
--  Tracked auras and spell blacklist popups shared by the aura filter
--  options. Loads right after EllesmereUI_Widgets.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

-- Tracked Auras popup: the shared INCLUDED/EXCLUDED spell-list editor (announcement-popup chrome; two tri-state
-- columns with per-column Add buttons; adding an ID to one list removes it from the other). Storage-agnostic --
-- callers pass list accessors and an onChanged applier. Used by the nameplate slot filters and the target/focus/boss unit frame debuff filters.
-- opts = {
--     eyebrow / title    (header strings)
--     subtitle           (optional: one dim line under the title; the header
--                         band and the lists shift down to make room)
--     fontPath           (optional; defaults to the options font)
--     includeGet/excludeGet  -> tri-state map { [spellID] = true|false }
--     includePrompt/excludePrompt  (Add Spell ID popup messages)
--     onChanged          (engine reapply, called after every edit)
--     onAdd(id)          (optional; called on every Add Spell ID, before onChanged)
--     showAll = { label, get, set }        (optional header toggle)
--     copyFrom = { label, choices = { {key=,label=}, ... }, apply(key) }
--                                          (optional header copy row)
--     includeMine = { anyGet } | { mineGet }  (optional: INCLUDED rows carry a MINE tag.
--                                          anyGet(): entries default to your own casts,
--                                          the map holds any-caster OPT-OUTS (boss);
--                                          mineGet(): entries default to any caster,
--                                          the map holds MINE OPT-INS (target/focus))
-- }
-- showAll and copyFrom are mutually exclusive header bands; with neither the list section shifts up and gains the height.
local _trackedAurasDimmer
function EllesmereUI.ShowTrackedAurasPopup(opts)
    -- The panel's pixel helper, like every popup scaled by GetPopupScale:
    -- the real-UI-scale PP lands 1px borders on fractional pixels here.
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local fontPath = opts.fontPath or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    local ppScale = (EllesmereUI.GetPopupScale()) or 1
    local EG = EllesmereUI.ELLESMERE_GREEN

    if _trackedAurasDimmer then _trackedAurasDimmer:Hide(); _trackedAurasDimmer = nil end

    local dimmer = CreateFrame("Button", "EUITrackedAurasDimmer", UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetScale(ppScale)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dim = dimmer:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.35)
    dimmer:SetScript("OnClick", function()
        dimmer:Hide(); _trackedAurasDimmer = nil
    end)
    _trackedAurasDimmer = dimmer

    local panel = CreateFrame("Frame", "EUITrackedAurasPopup", dimmer)
    panel:SetSize(520, 470)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panel:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    local pbg = panel:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(); pbg:SetColorTexture(0.077, 0.068, 0.058, 1)
    -- One-physical-pixel border (announcement-popup chrome): four edge textures, snap disabled, scale-derived thickness.
    do
        local onePhys = 1 / (panel:GetEffectiveScale() or 1)
        local function Edge()
            local t = panel:CreateTexture(nil, "BORDER")
            t:SetColorTexture(1, 1, 1, 0.15)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0)
            end
            return t
        end
        local eT = Edge(); eT:SetPoint("TOPLEFT", 0, 0); eT:SetPoint("TOPRIGHT", 0, 0); eT:SetHeight(onePhys)
        local eB = Edge(); eB:SetPoint("BOTTOMLEFT", 0, 0); eB:SetPoint("BOTTOMRIGHT", 0, 0); eB:SetHeight(onePhys)
        local eL = Edge(); eL:SetPoint("TOPLEFT", eT, "BOTTOMLEFT"); eL:SetPoint("BOTTOMLEFT", eB, "TOPLEFT"); eL:SetWidth(onePhys)
        local eR = Edge(); eR:SetPoint("TOPRIGHT", eT, "BOTTOMRIGHT"); eR:SetPoint("BOTTOMRIGHT", eB, "TOPRIGHT"); eR:SetWidth(onePhys)
    end
    -- Header: accent eyebrow + large title (announcement style).
    local eyebrow = panel:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(fontPath, 11, "")
    eyebrow:SetPoint("TOP", panel, "TOP", 0, -16)
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    eyebrow:SetText(EllesmereUI.L(opts.eyebrow or "TRACKED AURAS"))
    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 20, "")
    title:SetPoint("TOP", panel, "TOP", 0, -32)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText(EllesmereUI.L(opts.title or "Tracked Auras"))
    -- Optional one-line description under the title; everything below the
    -- header (band + lists) shifts down by hdrY and the panel grows to match.
    local hdrY = 0
    if opts.subtitle then
        local sub = panel:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 12, "")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
        sub:SetWidth(470)
        sub:SetJustifyH("CENTER")
        sub:SetTextColor(1, 1, 1, 0.6)
        sub:SetText(EllesmereUI.L(opts.subtitle))
        hdrY = 18
        panel:SetHeight(470 + hdrY)
    end

    local function ClosePopup()
        dimmer:Hide()
        _trackedAurasDimmer = nil
    end

    -- Escape closes (consume Escape only; other keys propagate so chat/UI shortcuts keep working behind the dimmer).
    panel:EnableKeyboard(true)
    panel:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then ClosePopup() end
    end)

    -- X close (standard popup chrome: borderless eui-close, top right)
    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(19, 19)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -10)
    local closeTex = closeBtn:CreateTexture(nil, "OVERLAY")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    closeBtn:SetAlpha(0.5)
    closeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
    closeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    closeBtn:SetScript("OnClick", ClosePopup)

    local RefreshBoth

    -- Header band: the Show All toggle OR the copy-from row (mutually exclusive by contract; with neither the list section shifts up).
    if opts.showAll then
        local sa = opts.showAll
        local tog = CreateFrame("Button", nil, panel)
        tog:SetSize(170, 20)
        tog:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -68 - hdrY)
        local box = CreateFrame("Frame", nil, tog)
        box:SetSize(16, 16); box:SetPoint("LEFT", tog, "LEFT", 0, 0)
        local bbg = box:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(); bbg:SetColorTexture(0.114, 0.106, 0.099, 1)
        local bbrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
        local chk = box:CreateTexture(nil, "ARTWORK")
        PP.SetInside(chk, box, 2, 2)
        chk:SetColorTexture(EG.r, EG.g, EG.b, 1)
        local tl = tog:CreateFontString(nil, "OVERLAY")
        tl:SetFont(fontPath, 13, "")
        tl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        tl:SetTextColor(0.85, 0.85, 0.85)
        tl:SetText(EllesmereUI.L(sa.label or "Show All"))
        local function UpdAll()
            local on = sa.get() == true
            chk:SetShown(on)
            if bbrd and bbrd.SetColor then
                if on then
                    bbrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                else
                    bbrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
        end
        tog:SetScript("OnClick", function()
            sa.set(not (sa.get() == true))
            UpdAll()
        end)
        UpdAll()
    elseif opts.copyFrom then
        local cf = opts.copyFrom
        local lbl = panel:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(fontPath, 12, "")
        lbl:SetPoint("LEFT", panel, "TOPLEFT", 24, -80 - hdrY)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        lbl:SetText(EllesmereUI.L(cf.label or "Copy From:"))

        -- Apply (rightmost), source dropdown to its left.
        local applyBtn = CreateFrame("Button", nil, panel)
        applyBtn:SetSize(64, 24)
        applyBtn:SetPoint("RIGHT", panel, "TOPRIGHT", -24, -80 - hdrY)
        local apBg = applyBtn:CreateTexture(nil, "BACKGROUND")
        apBg:SetAllPoints(); apBg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
        local apBrd = EllesmereUI.MakeBorder(applyBtn, EG.r, EG.g, EG.b, 0.35, PP)
        local apLbl = applyBtn:CreateFontString(nil, "OVERLAY")
        apLbl:SetFont(fontPath, 12, "")
        apLbl:SetPoint("CENTER")
        apLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
        apLbl:SetText(EllesmereUI.L("Apply"))
        applyBtn:SetScript("OnEnter", function()
            apLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
            if apBrd and apBrd.SetColor then apBrd:SetColor(EG.r, EG.g, EG.b, 0.8) end
        end)
        applyBtn:SetScript("OnLeave", function()
            apLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
            if apBrd and apBrd.SetColor then apBrd:SetColor(EG.r, EG.g, EG.b, 0.35) end
        end)

        local ddBtn = CreateFrame("Button", nil, panel)
        ddBtn:SetSize(110, 24)
        ddBtn:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)
        local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints(); ddBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        EllesmereUI.MakeBorder(ddBtn, 0.4, 0.4, 0.4, 0.6, PP)
        local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
        ddLbl:SetFont(fontPath, 12, "")
        ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 8, 0)
        ddLbl:SetPoint("RIGHT", ddBtn, "RIGHT", -18, 0)
        ddLbl:SetJustifyH("LEFT")
        ddLbl:SetWordWrap(false)
        ddLbl:SetTextColor(1, 1, 1, 0.8)
        ddLbl:SetText(EllesmereUI.L("Select..."))
        EllesmereUI.MakeDropdownArrow(ddBtn, 10, PP)

        local chosen
        local menu = CreateFrame("Frame", nil, panel)
        menu:SetFrameLevel(panel:GetFrameLevel() + 20)
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
        menu:SetSize(110, #cf.choices * 22 + 8)
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints(); mBg:SetColorTexture(0.077, 0.068, 0.058, 0.98)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, 0.15, PP)
        menu:Hide()
        for i = 1, #cf.choices do
            local choice = cf.choices[i]
            local mrow = CreateFrame("Button", nil, menu)
            mrow:SetHeight(22)
            mrow:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 22)
            mrow:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -4 - (i - 1) * 22)
            local hl = mrow:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)
            local rl = mrow:CreateFontString(nil, "OVERLAY")
            rl:SetFont(fontPath, 12, "")
            rl:SetPoint("LEFT", mrow, "LEFT", 8, 0)
            rl:SetTextColor(0.85, 0.85, 0.85)
            rl:SetText(EllesmereUI.L(choice.label))
            mrow:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.06) end)
            mrow:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, 0) end)
            mrow:SetScript("OnClick", function()
                chosen = choice.key
                ddLbl:SetText(EllesmereUI.L(choice.label))
                ddLbl:SetTextColor(1, 1, 1, 1)
                menu:Hide()
            end)
        end
        ddBtn:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
        -- Controller cursor: Cancel inside the list clicks the button (closing just the list).
        if EllesmereUI.PadCP() then menu.CloseButton = ddBtn end

        applyBtn:SetScript("OnClick", function()
            if not chosen then return end
            cf.apply(chosen)
            if RefreshBoth then RefreshBoth() end
        end)
    end

    local hasBand = (opts.showAll or opts.copyFrom) and true or false

    -- The two tri-state spell lists. INCLUDED renders through the caller's include machinery; EXCLUDED rides the caller's exclude machinery. Without a header band the whole section shifts up and the lists gain the reclaimed height.
    local secY = (hasBand and -104 or -68) - hdrY
    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, secY)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, secY)
    div:SetColorTexture(1, 1, 1, 0.08)

    -- Vertical divider down the column gutter (panel center), spanning the list section. One PHYSICAL pixel via the panel border's recipe above (snap disabled, scale-derived width): an unsnapped quad exactly 1 physical px wide always rasterizes exactly one pixel column at any UI scale.
    local vdiv = panel:CreateTexture(nil, "ARTWORK")
    vdiv:SetWidth(1 / (panel:GetEffectiveScale() or 1))
    if vdiv.SetSnapToPixelGrid then
        vdiv:SetSnapToPixelGrid(false); vdiv:SetTexelSnappingBias(0)
    end
    vdiv:SetPoint("TOP", panel, "TOP", 0, secY - 8)
    vdiv:SetPoint("BOTTOM", panel, "BOTTOM", 0, 62)
    vdiv:SetColorTexture(1, 1, 1, 0.08)

    local COL_W = 228
    -- withMine: the caller's includeMine descriptor (INCLUDED column only). Two
    -- polarities: anyGet() = entries default to Only My Casts and the map holds
    -- any-caster OPT-OUTS; mineGet() = entries default to any caster and the map
    -- holds MINE OPT-INS. Either way the tag reads "MINE" and lights when the
    -- entry is restricted to your casts.
    local function MakeSpellColumn(x, titleText, promptText, listFn, otherFn, withMine)
        local function ScopeMap()
            if not withMine then return nil end
            if withMine.mineGet then return withMine.mineGet() end
            return withMine.anyGet and withMine.anyGet()
        end
        local function MineOn(id)
            local map = ScopeMap()
            if withMine and withMine.mineGet then
                return map ~= nil and map[id] == true
            end
            return not (map and map[id])
        end
        -- Both polarities toggle by flipping the entry's presence in the map.
        local function ToggleMine(id)
            local map = ScopeMap()
            if not map then return end
            if map[id] then map[id] = nil else map[id] = true end
        end
        -- Section label (options-page section style: small gray caps).
        local colTitle = panel:CreateFontString(nil, "OVERLAY")
        colTitle:SetFont(fontPath, 11, "")
        colTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", x, secY - 16)
        colTitle:SetTextColor(1, 1, 1, 0.45)
        colTitle:SetText(EllesmereUI.L(titleText))

        -- Add Spell ID: the announcement popup's bordered accent button, secondary weight (dim border, brightens on hover).
        local addBtn = CreateFrame("Button", nil, panel)
        addBtn:SetSize(96, 24)
        addBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", x + COL_W - 520, secY - 8)
        local abg = addBtn:CreateTexture(nil, "BACKGROUND")
        abg:SetAllPoints(); abg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
        local abrd = EllesmereUI.MakeBorder(addBtn, EG.r, EG.g, EG.b, 0.35, PP)
        local al = addBtn:CreateFontString(nil, "OVERLAY")
        al:SetFont(fontPath, 12, "")
        al:SetPoint("CENTER")
        al:SetTextColor(EG.r, EG.g, EG.b, 0.7)
        al:SetText(EllesmereUI.L("Add Spell ID"))
        addBtn:SetScript("OnEnter", function()
            al:SetTextColor(EG.r, EG.g, EG.b, 1)
            if abrd and abrd.SetColor then abrd:SetColor(EG.r, EG.g, EG.b, 0.8) end
        end)
        addBtn:SetScript("OnLeave", function()
            al:SetTextColor(EG.r, EG.g, EG.b, 0.7)
            if abrd and abrd.SetColor then abrd:SetColor(EG.r, EG.g, EG.b, 0.35) end
        end)

        local scroll = CreateFrame("ScrollFrame", nil, panel)
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", x, secY - 44)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", x + COL_W - 520, 62)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(COL_W)
        scroll:SetScrollChild(child)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxS = math.max(0, child:GetHeight() - self:GetHeight())
            local cur = self:GetVerticalScroll() - delta * 30
            if cur < 0 then cur = 0 elseif cur > maxS then cur = maxS end
            self:SetVerticalScroll(cur)
        end)

        -- Rows: checkbox (enable/disable the entry without deleting it) + spell icon + name with the spell ID in gray parentheses + delete X. Disabled entries stay stored (false) and dim the whole row; only true entries reach the engine.
        local rows = {}
        local function RefreshList()
            for i = 1, #rows do rows[i]:Hide() end
            local list = listFn() or {}
            local sorted = {}
            for id, v in pairs(list) do
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                sorted[#sorted + 1] = { id = id, on = v == true, name = nm or tostring(id) }
            end
            table.sort(sorted, function(a, b) return a.name < b.name end)
            for i = 1, #sorted do
                local row = rows[i]
                if not row then
                    row = CreateFrame("Button", nil, child)
                    row:SetSize(COL_W, 28)
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 29)
                    row.hl = row:CreateTexture(nil, "BACKGROUND")
                    row.hl:SetAllPoints()
                    row.hl:SetColorTexture(1, 1, 1, 0)
                    -- Checkbox (checkbox-dropdown visuals)
                    row.box = CreateFrame("Frame", nil, row)
                    row.box:SetSize(16, 16)
                    row.box:SetPoint("LEFT", row, "LEFT", 2, 0)
                    local bxbg = row.box:CreateTexture(nil, "BACKGROUND")
                    bxbg:SetAllPoints(); bxbg:SetColorTexture(0.114, 0.106, 0.099, 1)
                    row.boxBrd = EllesmereUI.MakeBorder(row.box, 0.4, 0.4, 0.4, 0.6, PP)
                    row.chk = row.box:CreateTexture(nil, "ARTWORK")
                    PP.SetInside(row.chk, row.box, 2, 2)
                    row.chk:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
                    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    row.name = row:CreateFontString(nil, "OVERLAY")
                    row.name:SetFont(fontPath, 13, "")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", row, "RIGHT", withMine and -52 or -24, 0)
                    row.name:SetJustifyH("LEFT")
                    row.name:SetWordWrap(false)
                    row.x = CreateFrame("Button", nil, row)
                    row.x:SetSize(14, 14)
                    row.x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    row.x:SetFrameLevel(row:GetFrameLevel() + 2)
                    if withMine then
                        -- Only My Casts tag: accent when restricted to your
                        -- casts, gray when the entry shows from any caster.
                        row.mine = CreateFrame("Button", nil, row)
                        row.mine:SetSize(30, 16)
                        row.mine:SetPoint("RIGHT", row.x, "LEFT", -2, 0)
                        row.mine:SetFrameLevel(row:GetFrameLevel() + 2)
                        row.mine.txt = row.mine:CreateFontString(nil, "OVERLAY")
                        row.mine.txt:SetFont(fontPath, 11, "")
                        row.mine.txt:SetPoint("CENTER")
                        row.mine.txt:SetText(EllesmereUI.L("MINE"))
                        row.mine:SetScript("OnClick", function()
                            ToggleMine(row._id)
                            if opts.onChanged then opts.onChanged() end
                            RefreshList()
                        end)
                        row.mine:SetScript("OnEnter", function(self)
                            local tip
                            if MineOn(row._id) then
                                tip = EllesmereUI.L("Showing this aura from your casts only; click for any caster.")
                            else
                                tip = EllesmereUI.L("Showing this aura from any caster; click for your casts only.")
                            end
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end)
                        row.mine:SetScript("OnLeave", function()
                            EllesmereUI.HideWidgetTooltip()
                        end)
                    end
                    row.x.tex = row.x:CreateTexture(nil, "OVERLAY")
                    row.x.tex:SetAllPoints()
                    row.x.tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
                    row.x:SetAlpha(0.5)
                    row.x:SetScript("OnEnter", function(self)
                        self:SetAlpha(0.9)
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Remove"))
                    end)
                    row.x:SetScript("OnLeave", function(self)
                        self:SetAlpha(0.5)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    row:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.04) end)
                    row:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
                    rows[i] = row
                end
                local entry = sorted[i]
                row._id = entry.id
                local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
                row.icon:SetTexture(tex or 134400)
                row.name:SetText(entry.name .. " |cff808080(" .. entry.id .. ")|r")
                -- Checked = entry active; unchecked entries dim.
                row.chk:SetShown(entry.on)
                if row.boxBrd and row.boxBrd.SetColor then
                    if entry.on then
                        row.boxBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                    else
                        row.boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
                row.icon:SetDesaturated(not entry.on)
                row.icon:SetAlpha(entry.on and 1 or 0.45)
                row.name:SetAlpha(entry.on and 0.9 or 0.45)
                if row.mine then
                    if MineOn(row._id) then
                        -- Restricted to your own casts: accent tag.
                        row.mine.txt:SetTextColor(EG.r, EG.g, EG.b, entry.on and 1 or 0.45)
                    else
                        -- Any caster: dim gray tag.
                        row.mine.txt:SetTextColor(0.6, 0.6, 0.6, entry.on and 0.4 or 0.25)
                    end
                end
                row:SetScript("OnClick", function()
                    local l2 = listFn()
                    if l2 then
                        l2[row._id] = not (l2[row._id] == true)
                        if opts.onChanged then opts.onChanged() end
                        RefreshList()
                    end
                end)
                row.x:SetScript("OnClick", function()
                    local l2 = listFn()
                    if l2 then l2[row._id] = nil end
                    if withMine then
                        local map = ScopeMap()
                        if map then map[row._id] = nil end
                    end
                    if opts.onChanged then opts.onChanged() end
                    RefreshList()
                end)
                row:Show()
            end
            child:SetHeight(math.max(1, #sorted * 29))
        end
        addBtn:SetScript("OnClick", function()
            EllesmereUI:ShowInputPopup({
                title = EllesmereUI.L("Add Spell ID"),
                message = promptText,
                confirmText = EllesmereUI.L("Add"),
                cancelText = EllesmereUI.L("Cancel"),
                onConfirm = function(text)
                    local id = tonumber(text or "")
                    local list = id and listFn()
                    if list then
                        -- One list per spell: adding here removes it from the opposite list.
                        local other = otherFn()
                        if other then other[id] = nil end
                        if opts.onAdd then opts.onAdd(id) end
                        list[id] = true
                        if opts.onChanged then opts.onChanged() end
                        if RefreshBoth then RefreshBoth() end
                    end
                end,
            })
        end)
        return RefreshList
    end

    local refreshInc = MakeSpellColumn(24, "INCLUDED DEBUFFS",
        EllesmereUI.L(opts.includePrompt or "Enter the spell ID to always show."),
        opts.includeGet,
        opts.excludeGet,
        opts.includeMine)
    local refreshEx = MakeSpellColumn(268, "EXCLUDED DEBUFFS",
        EllesmereUI.L(opts.excludePrompt or "Enter the spell ID to exclude."),
        opts.excludeGet,
        opts.includeGet)
    RefreshBoth = function()
        refreshInc(); refreshEx()
    end

    -- Done (announcement popup's primary action: green border and label, brighten on hover). Everything applies live, so Done = close.
    local doneBtn = CreateFrame("Button", nil, panel)
    doneBtn:SetSize(150, 32)
    doneBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
    local dbg2 = doneBtn:CreateTexture(nil, "BACKGROUND")
    dbg2:SetAllPoints(); dbg2:SetColorTexture(0.077, 0.068, 0.058, 0.92)
    local dbrd = EllesmereUI.MakeBorder(doneBtn, EG.r, EG.g, EG.b, 0.9, PP)
    local dl2 = doneBtn:CreateFontString(nil, "OVERLAY")
    dl2:SetFont(fontPath, 14, "")
    dl2:SetPoint("CENTER")
    dl2:SetText(EllesmereUI.L("Done"))
    dl2:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    doneBtn:SetScript("OnEnter", function()
        dl2:SetTextColor(EG.r, EG.g, EG.b, 1)
        if dbrd and dbrd.SetColor then dbrd:SetColor(EG.r, EG.g, EG.b, 1) end
    end)
    doneBtn:SetScript("OnLeave", function()
        dl2:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        if dbrd and dbrd.SetColor then dbrd:SetColor(EG.r, EG.g, EG.b, 0.9) end
    end)
    doneBtn:SetScript("OnClick", ClosePopup)

    -- Controller in use: the popup joins the controller cursor and answers the
    -- controller's Back (registered while hidden, so it counts from this show);
    -- the full-screen dimmer and the panel are no stops, Cancel clicks the X, the
    -- cursor starts on Done.
    if EllesmereUI.PadInUse() then
        dimmer:Hide()
        EllesmereUI.RegisterEscapeClose(dimmer, { padOnly = true, onEscape = ClosePopup })
        EllesmereUI.PadHint(dimmer, "nodepass")
        EllesmereUI.PadHint(panel, "nodepass")
        if EllesmereUI.PadCP() then panel.CloseButton = closeBtn end
        dimmer:Show()
        if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(doneBtn) end
    end

    RefreshBoth()
end

-------------------------------------------------------------------------------
-- Spell-ID blacklist editor: small standalone modal (dimmer, click-outside close) listing the current blacklist
-- with per-row remove plus an Add box. Storage-agnostic -- callers pass get/add/remove accessors and an onChanged
-- applier. Reused by the player-frame, Player Aura Bars and Buff Manager buff filter dropdowns ("Edit Blacklist" pinned actions).
function EllesmereUI.ShowSpellBlacklistPopup(opts)
    if EllesmereUI._blacklistPopup then
        EllesmereUI._blacklistPopup:Hide()
        EllesmereUI._blacklistPopup = nil
    end
    opts = opts or {}
    local fontPath = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    local PW, PH = 320, 400

    -- Controller cursor loaded: the dimmer is a named Button, so the cursor can
    -- take the popup as a window and its Cancel press can click the dimmer shut.
    local padCP = EllesmereUI.PadCP()
    local dimmer = CreateFrame(padCP and "Button" or "Frame", padCP and "EUISpellBlacklistDimmer" or nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local function CloseBlacklist()
        dimmer:Hide()
        EllesmereUI._blacklistPopup = nil
    end
    dimmer:SetScript("OnMouseDown", CloseBlacklist)
    EllesmereUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25):SetAllPoints(dimmer)
    EllesmereUI._blacklistPopup = dimmer

    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(PW, PH)
    popup:SetPoint("CENTER")
    popup:EnableMouse(true)
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 2)
    if EllesmereUI.GetPopupScale then popup:SetScale(EllesmereUI.GetPopupScale()) end
    EllesmereUI.SolidTex(popup, "BACKGROUND", 13 / 255, 17 / 255, 25 / 255, 0.98):SetAllPoints(popup)
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.22)

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 14, "")
    title:SetPoint("TOP", popup, "TOP", 0, -12)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText(EllesmereUI.L(opts.title or "Blacklist"))

    local hint = popup:CreateFontString(nil, "OVERLAY")
    hint:SetFont(fontPath, 11, "")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetWidth(PW - 32)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetText(EllesmereUI.L("Blacklisted spells never display."))

    local addBox = CreateFrame("EditBox", nil, popup)
    addBox:SetSize(PW - 24 - 70 - 8, 26)
    addBox:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -58)
    addBox:SetFont(fontPath, 12, "")
    addBox:SetTextColor(1, 1, 1, 0.9)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)
    addBox:SetMaxLetters(9)
    addBox:SetTextInsets(6, 6, 0, 0)
    addBox:SetJustifyH("LEFT")
    EllesmereUI.SolidTex(addBox, "BACKGROUND", 0, 0, 0, 0.4):SetAllPoints(addBox)
    EllesmereUI.MakeBorder(addBox, 1, 1, 1, 0.15)
    local ph = addBox:CreateFontString(nil, "OVERLAY")
    ph:SetFont(fontPath, 11, "")
    ph:SetPoint("LEFT", addBox, "LEFT", 6, 0)
    ph:SetTextColor(0.5, 0.5, 0.5, 0.6)
    ph:SetText(EllesmereUI.L("Spell ID..."))
    addBox:SetScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
    end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, popup)
    addBtn:SetSize(70, 26)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints()
    addBg:SetColorTexture(eg.r, eg.g, eg.b, 0.8)
    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
    addLbl:SetFont(fontPath, 11, "")
    addLbl:SetPoint("CENTER")
    addLbl:SetTextColor(1, 1, 1)
    addLbl:SetText(EllesmereUI.L("Add"))
    addBtn:SetScript("OnEnter", function() addBg:SetColorTexture(eg.r, eg.g, eg.b, 1) end)
    addBtn:SetScript("OnLeave", function() addBg:SetColorTexture(eg.r, eg.g, eg.b, 0.8) end)

    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -94)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 12)
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(PW - 24)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxS = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxS, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)

    local emptyLbl = child:CreateFontString(nil, "OVERLAY")
    emptyLbl:SetFont(fontPath, 11, "")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -10)
    emptyLbl:SetTextColor(1, 1, 1, 0.35)
    emptyLbl:SetText(EllesmereUI.L("No blacklisted spells."))

    local rows = {}
    local RebuildList
    RebuildList = function()
        for i = 1, #rows do rows[i]:Hide() end
        local map = (opts.get and opts.get()) or {}
        local ids = {}
        for id in pairs(map) do ids[#ids + 1] = id end
        table.sort(ids)
        local y = 0
        for i = 1, #ids do
            local id = ids[i]
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetSize(PW - 24, 26)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.rm = CreateFrame("Button", nil, row)
                row.rm:SetSize(18, 18)
                row.rm:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                row.rmX = row.rm:CreateFontString(nil, "OVERLAY")
                row.rmX:SetFont(fontPath, 12, "")
                row.rmX:SetPoint("CENTER")
                row.rmX:SetText("X")
                row.rmX:SetTextColor(1, 0.3, 0.3, 0.7)
                row.rm:SetScript("OnEnter", function() row.rmX:SetTextColor(1, 0.3, 0.3, 1) end)
                row.rm:SetScript("OnLeave", function() row.rmX:SetTextColor(1, 0.3, 0.3, 0.7) end)
                row.idText = row:CreateFontString(nil, "OVERLAY")
                row.idText:SetFont(fontPath, 10, "")
                row.idText:SetTextColor(1, 1, 1, 0.35)
                row.idText:SetPoint("RIGHT", row.rm, "LEFT", -6, 0)
                row.name = row:CreateFontString(nil, "OVERLAY")
                row.name:SetFont(fontPath, 12, "")
                row.name:SetTextColor(1, 1, 1, 0.85)
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row.idText, "LEFT", -6, 0)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
            row.icon:SetTexture((info and info.iconID) or 134400)
            row.name:SetText((info and info.name) or ("Spell " .. tostring(id)))
            row.idText:SetText(tostring(id))
            row.rm:SetScript("OnClick", function()
                if opts.remove then opts.remove(id) end
                if opts.onChanged then opts.onChanged() end
                RebuildList()
            end)
            row:Show()
            y = y - 26
        end
        child:SetHeight(math.max(1, -y))
        emptyLbl:SetShown(#ids == 0)
    end

    local function AddFromBox()
        local id = tonumber(addBox:GetText() or "")
        addBox:SetText("")
        addBox:ClearFocus()
        if not (id and id > 0) then return end
        local map = opts.get and opts.get()
        if map and map[id] then return end
        if opts.add then opts.add(id) end
        if opts.onChanged then opts.onChanged() end
        RebuildList()
    end
    addBtn:SetScript("OnClick", AddFromBox)
    addBox:SetScript("OnEnterPressed", AddFromBox)

    -- Controller in use: the popup joins the controller cursor and answers the
    -- controller's Back (registered while hidden, so it counts from this show);
    -- the dimmer and the panel are no stops, Cancel clicks the dimmer (the popup
    -- has no close button), and the cursor starts inside the popup.
    if padCP or EllesmereUI.PadNative() then
        dimmer:Hide()
        if padCP then
            dimmer:SetScript("OnClick", CloseBlacklist)
            EllesmereUI.PadHint(dimmer, "nodepass")
            EllesmereUI.PadHint(popup, "nodepass")
            popup.CloseButton = dimmer
        end
        EllesmereUI.RegisterEscapeClose(dimmer, { padOnly = true, onEscape = CloseBlacklist })
        dimmer:Show()
    end

    RebuildList()
    if padCP and EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(popup) end
end

