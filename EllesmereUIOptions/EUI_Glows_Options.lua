if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Glows_Options.lua -- Global Settings > Glows. A glow template (style,
--  color, Pixel Glow parameters) applied once to every active custom glow,
--  plus one card per module with every registered glow site as a full mirror
--  of its own page's controls (EllesmereUI.GlowOptions sites). Apply to All
--  only changes active custom glows; a row's or a module's Apply also turns
--  off glows on and replaces Blizzard Default, Solid and Blizzard Border.
--  Glows kept per icon, indicator or filter are listed as hints and never
--  taken by the template; a site's own confirm prompt runs as for an edit.
-------------------------------------------------------------------------------

local PAGE_GLOWS = "Glows"
local GLOBAL_KEY = "_EUIGlobal"

-- Session-only view state (never saved): expanded cards, cards hiding
-- their inactive glows, and a pending rebuild (see RefreshCardState).
local _glExpanded, _glHideInactive = {}, {}
local _glRebuildQueued = false

-- Loads first in the options addon, before this file.
local GO = EllesmereUI.GlowOptions

-------------------------------------------------------------------------------
--  Template (account-wide; only ever a pattern, no module reads it)
-------------------------------------------------------------------------------
local TEMPLATE_DEFAULTS = { style = 1, mode = "default", lines = 8, thickness = 2, speed = 4 }

-- Read: the saved template, else the defaults. A read never writes, so a page
-- build (the hidden search pass included) saves nothing.
local function Template()
    return EllesmereUIDB.glowTemplate or TEMPLATE_DEFAULTS
end

-- Write: the saved template, made from the defaults on the first edit.
local function TemplateW()
    local t = EllesmereUIDB.glowTemplate
    if not t then
        t = CopyTable(TEMPLATE_DEFAULTS)
        EllesmereUIDB.glowTemplate = t
    end
    return t
end

local _templateDesc
local function TemplateDesc()
    if _templateDesc then return _templateDesc end
    -- Shape Glow is left out: almost no site can show it (it needs an icon shape).
    _templateDesc = {
        host = "icon", noNone = true, excludes = { [4] = true },
        caps = { mode = true, params = true, bg = true },
        get = function(f)
            local t = Template()
            if f == "style" then return t.style or 1
            elseif f == "mode" then return t.mode or "default"
            elseif f == "color" then return t.r, t.g, t.b
            elseif f == "lines" then return t.lines
            elseif f == "thickness" then return t.thickness
            elseif f == "speed" then return t.speed
            elseif f == "bg" then return t.bg == true
            elseif f == "bgColor" then return t.bgR, t.bgG, t.bgB
            end
        end,
        set = function(f, a, b, c)
            local t = TemplateW()
            if f == "style" then t.style = a
            elseif f == "mode" then
                t.mode = a
                -- Custom without a picked color would apply nothing visible: seed gold.
                if a == "custom" and t.r == nil then
                    local d = EllesmereUI.Glows.DEFAULT_COLOR
                    t.r, t.g, t.b = d.r, d.g, d.b
                end
            elseif f == "color" then t.r, t.g, t.b = a, b, c
            elseif f == "lines" then t.lines = a
            elseif f == "thickness" then t.thickness = a
            elseif f == "speed" then t.speed = a
            elseif f == "bg" then t.bg = a and true or nil
            elseif f == "bgColor" then t.bgR, t.bgG, t.bgB = a, b, c
            end
        end,
    }
    return _templateDesc
end

-------------------------------------------------------------------------------
--  Sites
-------------------------------------------------------------------------------

-- Every registered site as { module, label, sub, desc, entry, nav }, per-bar
-- lists expanded. nav: where Open Settings goes (a list item's own, else the
-- entry); sub: the in-card group a row is listed under.
local function CollectSites()
    local out = {}
    for _, entry in ipairs(GO.sites) do
        if entry.list then
            for _, item in ipairs(entry.list() or {}) do
                out[#out + 1] = { module = entry.module, label = item.label, sub = item.sub or entry.sub,
                                  desc = item.desc, entry = entry, nav = item.nav or entry }
            end
        elseif entry.desc then
            out[#out + 1] = { module = entry.module, label = entry.label, sub = entry.sub,
                              desc = entry.desc, entry = entry, nav = entry }
        end
    end
    return out
end

-- Glows kept per entry in modules that register no hint of their own: added
-- at page build while the module is loaded, and only when no entry holds the
-- id yet (a module's own registration wins).
local ENTRY_GLOW_INFOS = {
    { id = "rf_bm_icon_glows", label = "Buff Manager Icon Glows",
      module = "EllesmereUIRaidFrames", page = "Buff Manager",
      info = { glyph = "icon",
        tooltip = "Icon Glow is set per indicator on the Buff Manager page. The template never changes it.",
        text = function() return EllesmereUI.L("Set per indicator") end } },
    { id = "rf_dm_glows", label = "Debuff Manager Glows",
      module = "EllesmereUIRaidFrames", page = "Debuff Manager",
      info = { glyph = "icon",
        tooltip = "Icon Effects glows are set per filter and Frame Glow per tile on the Debuff Manager page. The template never changes them.",
        text = function() return EllesmereUI.L("Set per filter and tile") end } },
    { id = "pab_icon_glows", label = "Player Aura Bars Icon Glows",
      module = "EllesmereUIUnitFrames", page = "Player Aura Bars",
      info = { glyph = "icon",
        tooltip = "Icon Effects glows are set per filter on each bar of the Player Aura Bars page. The template never changes them.",
        text = function() return EllesmereUI.L("Set per filter") end } },
}

local function EnsureEntryGlowInfos()
    for _, e in ipairs(ENTRY_GLOW_INFOS) do
        if EllesmereUI.ModuleNS(e.module) then
            local have = false
            for i = 1, #GO.sites do
                if GO.sites[i].id == e.id then have = true; break end
            end
            if not have then GO.RegisterSite(e) end
        end
    end
end

-- Info entries ({ info = { text, tooltip } }): no glow of their own, a hint
-- with a count and Go to Settings for glows kept per entry elsewhere.
local function CollectInfos()
    EnsureEntryGlowInfos()
    local out = {}
    for _, entry in ipairs(GO.sites) do
        if entry.info then
            out[#out + 1] = { module = entry.module, label = entry.label, sub = entry.sub,
                              info = entry.info, nav = entry }
        end
    end
    return out
end

local function Blocked(site)
    return site.entry.blocked and site.entry.blocked() or false
end

-- Can the template be written here at all (not locked by Blizzard Style or
-- its own settings page, and not a paramsOnly site: the Pixel Glow
-- parameters per-icon glows read, which the template never changes)?
local function CanTake(site)
    local desc = site.desc
    return not Blocked(site) and not desc.paramsOnly and not GO.StyleLocked(desc)
end

-- An active custom glow: what the template can change (the rest is hidden
-- until the card shows its inactive glows).
local function IsActive(site)
    return CanTake(site) and GO.IsCustomGlow(site.desc)
end

local ST_GREY, ST_GREEN, ST_AMBER = { 0.5, 0.5, 0.5 }, { 0.05, 0.82, 0.62 }, { 0.88, 0.69, 0.31 }
-- The card summary's "differ" count wears the status dot's amber.
local AMBER_CODE = EllesmereUI.HexColor(ST_AMBER[1], ST_AMBER[2], ST_AMBER[3])

-- Status of a site against the template: dot color, short word, tooltip text,
-- and whether it matches (one MatchesTemplate per evaluation).
local function SiteStatus(site, t)
    local desc = site.desc
    if Blocked(site) then return ST_GREY, EllesmereUI.L("Blizzard"), EllesmereUI.L("Blizzard Style"), false end
    if desc.paramsOnly then
        return ST_GREY, EllesmereUI.L("Per icon"),
            EllesmereUI.L("The Pixel Glow settings this bar's per-icon glows use. The template never changes them."), false
    end
    if not GO.IsCustomGlow(desc) then
        if GO.IsOff(desc) then return ST_GREY, EllesmereUI.L("Off"), EllesmereUI.L("Off"), false end
        return ST_GREY, EllesmereUI.L("Not custom"), EllesmereUI.L("Not a custom glow"), false
    end
    if GO.MatchesTemplate(desc, t) then
        return ST_GREEN, EllesmereUI.L("Matches"), EllesmereUI.L("Matches template"), true
    end
    local idx, converted = GO.Resolve(desc, t.style or 1)
    if converted then
        return ST_AMBER, EllesmereUI.L("Differs"), EllesmereUI.Lf("Differs (template shows as %s)",
            EllesmereUI.L(EllesmereUI.Glows.STYLES[idx].name)), false
    end
    return ST_AMBER, EllesmereUI.L("Differs"), EllesmereUI.L("Differs from template"), false
end

-- Would ApplyTo change this site? anyState: any unlocked site that differs
-- (off glows and extras included); otherwise active custom glows that differ.
local function Eligible(site, t, anyState)
    if anyState then
        if not CanTake(site) then return false end
    elseif not IsActive(site) then
        return false
    end
    return not GO.MatchesTemplate(site.desc, t)
end

-- One pass's refreshes: each distinct module refresh once (CDM bars share one
-- rebuild), the touched modules' cached pages dropped, this page rebuilt.
local function Settle(touched, refresh)
    for fn in pairs(refresh) do fn() end
    for module in pairs(touched) do
        EllesmereUI:InvalidateModulePageCache(module)
    end
    EllesmereUI:RefreshPage(true)
end

-- Apply the template to sites[first..]. A site with its own confirm
-- (desc.confirm: the prompt an edit of its style gets, such as a performance
-- warning when a glow turns on) goes through it exactly as an edit would.
-- When it prompts, the pass settles what it changed so far and stops;
-- accepting resumes at that site (confirmed = its index: not asked twice),
-- cancelling leaves it and the sites after it unchanged.
local function ApplyRun(sites, t, anyState, first, confirmed)
    local touched, refresh = {}, {}
    for i = first, #sites do
        local site = sites[i]
        local desc = site.desc
        if Eligible(site, t, anyState) then
            local v = GO.TemplateValue(desc, t)
            if v ~= nil and desc.confirm and i ~= confirmed then
                local inCall, passed = true, false
                desc.confirm(v, function()
                    if inCall then passed = true
                    else ApplyRun(sites, t, anyState, i, i) end
                end)
                inCall = false
                if not passed then
                    Settle(touched, refresh)
                    return
                end
            end
            if GO.ApplyTemplate(desc, t, anyState) then
                if desc.onChange then refresh[desc.onChange] = true end
                touched[site.module] = true
            end
        end
    end
    Settle(touched, refresh)
end

-- Apply the template to the given sites: sites without a prompt first, so a
-- cancelled prompt holds back only the prompting sites after it.
local function ApplyTo(sites, t, anyState)
    local ordered = {}
    for _, site in ipairs(sites) do
        if not site.desc.confirm then ordered[#ordered + 1] = site end
    end
    for _, site in ipairs(sites) do
        if site.desc.confirm then ordered[#ordered + 1] = site end
    end
    ApplyRun(ordered, t, anyState, 1)
end

-- Counts what ApplyTo would change, for the confirm popup.
local function PreviewCounts(sites, t, anyState)
    local n, conv, turnOn = 0, 0, 0
    for _, site in ipairs(sites) do
        if Eligible(site, t, anyState) then
            n = n + 1
            local _, c = GO.TemplateValue(site.desc, t)
            if c then conv = conv + 1 end
            if not GO.IsCustomGlow(site.desc) then turnOn = turnOn + 1 end
        end
    end
    return n, conv, turnOn
end

-- anyState: a row's or a module's Apply (see Eligible).
local function ConfirmApply(sites, anyState)
    local t = Template()
    local n, conv, turnOn = PreviewCounts(sites, t, anyState)
    if n == 0 then
        EllesmereUI:ShowInfoPopup({
            title = EllesmereUI.L("Apply Glow Template"),
            content = anyState and EllesmereUI.L("Nothing to change: every glow here already matches the template.")
                or EllesmereUI.L("Nothing to change: no active custom glow differs from the template."),
        })
        return
    end
    local msg = anyState and EllesmereUI.Lf("Apply the template to %d glow(s)?", n)
        or EllesmereUI.Lf("Apply the template to the %d active custom glow(s) listed here?", n)
    if turnOn > 0 then
        msg = msg .. "\n\n" .. EllesmereUI.Lf("%d of them are off or use a Blizzard style and switch to the template glow.", turnOn)
    end
    if conv > 0 then
        msg = msg .. "\n\n" .. EllesmereUI.Lf("%d of them can't show the chosen style and use the closest one.", conv)
    end
    EllesmereUI:ShowConfirmPopup({
        title       = EllesmereUI.L("Apply Glow Template"),
        message     = msg,
        confirmText = EllesmereUI.L("Apply"),
        cancelText  = EllesmereUI.L("Cancel"),
        onConfirm   = function() ApplyTo(sites, t, anyState) end,
    })
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------

-- A DualRow kept out of the search index: view controls and live counts are
-- no search results (a count would also go stale there). The flag is restored
-- even when the row errors.
local function UnindexedDualRow(W, parent, y, left, right)
    local prev = EllesmereUI._searchIndexSuppress
    EllesmereUI._searchIndexSuppress = true
    local ok, row, h = pcall(W.DualRow, W, parent, y, left, right)
    EllesmereUI._searchIndexSuppress = prev
    if not ok then error(row, 0) end
    return row, h
end

-- Round status dot left of a label half's text (the core's circle-mask dot).
local DOT_MASK = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga"
local function StatusDot(rgn, color)
    local lbl = rgn._label
    if not lbl then return end
    local PP = EllesmereUI.PanelPP
    local p, rel, rp, x, y = lbl:GetPoint(1)
    local dot = CreateFrame("Frame", nil, rgn)
    PP.Size(dot, 8, 8)
    dot:SetPoint(p, rel, rp, x, y)
    local tex = dot:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(color[1], color[2], color[3], 1)
    local mask = dot:CreateMaskTexture()
    mask:SetTexture(DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    lbl:ClearAllPoints()
    PP.Point(lbl, "LEFT", dot, "RIGHT", 8, 0)
    lbl:SetTextColor(color[1], color[2], color[3], 1)
    return tex
end

-- Why a site's Apply Template is greyed out, or nil when it would change it
-- (an off glow or an extra takes the template too). Manual edits apply live;
-- the button only exists for the template. matches: an already computed
-- MatchesTemplate result (nil = compute it here).
local function ApplyBlockedTip(site, t, matches)
    local desc = site.desc
    if desc.paramsOnly then
        return EllesmereUI.L("Per-icon glow settings: the template never changes them.")
    end
    if not CanTake(site) then
        -- A style-only lock names its own reason (its colors stay editable).
        if not Blocked(site) and not (desc.disabled and desc.disabled())
            and desc.styleDisabled and desc.styleDisabled() then
            return EllesmereUI.L(desc.styleDisabledTooltip)
        end
        return EllesmereUI.L("This glow is locked on its settings page.")
    end
    if matches == nil then matches = GO.MatchesTemplate(site.desc, t) end
    if matches then return EllesmereUI.L("Already matches the template.") end
    return nil
end

-- Light in-card group heading (a SectionHeader would split the card's search
-- section); inline search matches it by its text.
local SUB_H = 30
local function SubHeader(parent, y, text)
    local PP = EllesmereUI.PanelPP
    local f = CreateFrame("Frame", nil, parent)
    PP.Size(f, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, SUB_H)
    PP.Point(f, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    local fs = EllesmereUI.MakeFont(f, 11, nil, 1, 1, 1, 0.55)
    PP.Point(fs, "BOTTOMLEFT", f, "BOTTOMLEFT", 20, 7)
    fs:SetText(text)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    PP.Point(line, "LEFT", fs, "RIGHT", 10, 0)
    PP.Point(line, "RIGHT", f, "RIGHT", -20, 0)
    f._labelText = text
    EllesmereUI._rowCounters[parent] = 0
    return y - SUB_H
end

-- Full-width rule between a card's control row and its glow rows.
local DIV_H = 11
local function CardDivider(parent, y)
    local PP = EllesmereUI.PanelPP
    local f = CreateFrame("Frame", nil, parent)
    PP.Size(f, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, DIV_H)
    PP.Point(f, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    PP.Point(line, "LEFT", f, "LEFT", 20, 0)
    PP.Point(line, "RIGHT", f, "RIGHT", -20, 0)
    EllesmereUI._rowCounters[parent] = 0
    return y - DIV_H
end

-- Small drawn symbol left of an info row's label, styled like the card
-- glyphs (dark fill, accent edge): "icon" = one glowing button, "bar" =
-- three buttons with the middle one glowing.
local function InfoGlyph(rgn, kind)
    local lbl = rgn._label
    if not (lbl and kind) then return end
    local PP = EllesmereUI.PanelPP
    local EG = EllesmereUI.ELLESMERE_GREEN
    local p, rel, rp, x, y = lbl:GetPoint(1)
    local holder = CreateFrame("Frame", nil, rgn)
    holder:SetPoint(p, rel, rp, x, y)
    local function Button(size, glow)
        local b = CreateFrame("Frame", nil, holder)
        PP.Size(b, size, size)
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetColorTexture(0.1, 0.1, 0.1, 1)
        if glow then
            EllesmereUI.MakeBorder(b, EG.r, EG.g, EG.b, 0.8, PP)
        else
            EllesmereUI.MakeBorder(b, 1, 1, 1, 0.15, PP)
        end
        return b
    end
    if kind == "bar" then
        PP.Size(holder, 32, 10)
        local prev
        for i = 1, 3 do
            local b = Button(10, i == 2)
            if prev then PP.Point(b, "LEFT", prev, "RIGHT", 1, 0) else PP.Point(b, "LEFT", holder, "LEFT", 0, 0) end
            prev = b
        end
    else
        PP.Size(holder, 16, 16)
        PP.Point(Button(16, true), "LEFT", holder, "LEFT", 0, 0)
    end
    lbl:ClearAllPoints()
    PP.Point(lbl, "LEFT", holder, "RIGHT", 8, 0)
end

-- One info entry: label (hint as tooltip), its count, Go to Settings. The
-- count is written after the build: a count is no search result.
local function InfoRow(parent, y, W, item)
    local info = item.info
    local row, h = W:DualRow(parent, y, { type = "label", text = item.label, tooltip = info.tooltip },
        EllesmereUI.BlankRowCfg())
    if not EllesmereUI._prebuilding then
        local rrgn = row._rightRegion
        if info.text and rrgn._label then rrgn._label:SetText(info.text()) end
        InfoGlyph(row._leftRegion, info.glyph)
        local nav, module = item.nav, item.module
        if nav and nav.page then
            EllesmereUI.BuildInlineButton(rrgn, EllesmereUI.L("Go to Settings"), function()
                EllesmereUI:NavigateToElementSettings(module, nav.page, nav.section, nav.preSelect, nav.highlight)
            end)
        end
    end
    return y - h
end

-- One site: its own glow controls on the left, status + Apply + Open Settings
-- right. The status word is written after the build (no search result); its
-- tooltip rides the empty label from the start.
local function SiteRow(parent, y, W, site)
    local desc = site.desc
    local left
    if desc.paramsOnly then
        left = { type = "label", text = site.label }
    else
        left = GO.DropdownSpec(desc, site.label)
    end
    local color, short, long = SiteStatus(site, Template())
    local statusCfg = EllesmereUI.BlankRowCfg()
    statusCfg.tooltip = long
    local row, h = W:DualRow(parent, y, left, statusCfg)
    if not EllesmereUI._prebuilding then
        local rrgn = row._rightRegion
        if rrgn._label then rrgn._label:SetText(short) end
        local dotTex = StatusDot(rrgn, color)
        local lrgn = row._leftRegion
        if desc.paramsOnly then
            -- A label half has no control to chain from: anchor the cog at the right edge.
            local PP = EllesmereUI.PanelPP
            local anchor = CreateFrame("Frame", nil, lrgn)
            PP.Size(anchor, 1, 1)
            PP.Point(anchor, "RIGHT", lrgn, "RIGHT", -20, 0)
            lrgn._lastInline = anchor
            EllesmereUI.BuildInlineCog(lrgn, { title = "Pixel Glow Settings", rows = GO.CogRows(desc), captureRegion = lrgn })
        else
            GO.AttachInline(lrgn, desc)
        end
        local nav, module = site.nav, site.module
        if nav and nav.page then
            EllesmereUI.BuildInlineButton(rrgn, EllesmereUI.L("Open Settings"), function()
                EllesmereUI:NavigateToElementSettings(module, nav.page, nav.section, nav.preSelect, nav.highlight)
            end, { width = 104 })
        end
        EllesmereUI.BuildInlineButton(rrgn, EllesmereUI.L("Apply Template"), function() ConfirmApply({ site }, true) end, {
            width = 110,
            disabled = function() return ApplyBlockedTip(site, Template()) ~= nil end,
            disabledTooltip = function() return ApplyBlockedTip(site, Template()) end,
            rawTooltip = true,
        })
        -- Row edits only refresh widgets (no rebuild): keep the status current.
        EllesmereUI.RegisterWidgetRefresh(function()
            local c, s, l = SiteStatus(site, Template())
            local lbl = rrgn._label
            if lbl then lbl:SetText(s); lbl:SetTextColor(c[1], c[2], c[3], 1) end
            if dotTex then dotTex:SetColorTexture(c[1], c[2], c[3], 1) end
            if rrgn._cfg then rrgn._cfg.tooltip = l end
        end)
    end
    return y - h
end

-------------------------------------------------------------------------------
--  Cards
-------------------------------------------------------------------------------
local GL_GLYPH = "Interface\\AddOns\\EllesmereUI\\media\\textures\\melli.tga"

-- Card header summary: active glows and how many differ from the template.
local function CardSummary(list, t)
    local active, differ = 0, 0
    for _, site in ipairs(list) do
        if IsActive(site) then
            active = active + 1
            if not GO.MatchesTemplate(site.desc, t) then differ = differ + 1 end
        end
    end
    if active == 0 then return EllesmereUI.L("No active glows"), active end
    local tail
    if differ > 0 then
        tail = AMBER_CODE .. EllesmereUI.Lf("%d differ from template", differ) .. "|r"
    else
        tail = EllesmereUI.L("all match the template")
    end
    return EllesmereUI.Lf("%d active", active) .. ", " .. tail, active
end

-- Is every site of the card already matching or locked (nothing for its Apply)?
local function ModuleBlocked(tile)
    local t = Template()
    for _, site in ipairs(tile.sites) do
        if not ApplyBlockedTip(site, t) then return false end
    end
    return true
end

-- Card body: a Hide Inactive toggle (off by default; greyed out when the card
-- has nothing inactive) and the module's Apply, then the rows grouped under
-- their sub headings. A card of hint rows only has neither.
local function BuildCardContent(parent, y, W, tile)
    local key = tile.key
    local showAll = _glHideInactive[key] ~= true
    local hasSites = #tile.sites > 0
    local row, h
    if hasSites then
        local inactive = #tile.sites - tile.active
        local left = { type = "toggle", text = EllesmereUI.Lf("Hide Inactive Glows (%d)", inactive),
            getValue = function() return _glHideInactive[key] == true end,
            setValue = function(v)
                _glHideInactive[key] = v or nil
                EllesmereUI:RefreshPage(true)
            end,
            disabled = function() return inactive == 0 end,
            disabledTooltip = EllesmereUI.L("Every glow in this module is active."), rawTooltip = true }
        row, h = UnindexedDualRow(W, parent, y, left, EllesmereUI.BlankRowCfg());  y = y - h
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineButton(row._rightRegion, EllesmereUI.L("Apply Template to This Module"),
                function() ConfirmApply(tile.sites, true) end, {
                    width = 220,
                    disabled = function() return ModuleBlocked(tile) end,
                    disabledTooltip = EllesmereUI.L("Every glow in this module already matches the template or is locked on its settings page."),
                    rawTooltip = true,
                })
            -- A row edit can change the header summary, the inactive count and which
            -- rows show. The summary text updates in place (a rebuild would close an
            -- open cog popup); a changed active count moves rows, so rebuild once.
            local function RefreshCardState()
                local summary, active = CardSummary(tile.sites, Template())
                if summary ~= tile.desc and active == tile.active then
                    if tile._descFS then tile._descFS:SetText(summary) end
                    tile.desc = summary
                end
                if (summary ~= tile.desc or active ~= tile.active) and not _glRebuildQueued then
                    _glRebuildQueued = true
                    C_Timer.After(0, function()
                        _glRebuildQueued = false
                        if EllesmereUI:GetActivePage() == PAGE_GLOWS then EllesmereUI:RefreshPage(true) end
                    end)
                end
            end
            EllesmereUI.RegisterWidgetRefresh(RefreshCardState)
        end
        y = CardDivider(parent, y)
    end
    local lastSub
    -- Info entries lead the card (above any group) and never hide.
    for _, item in ipairs(tile.infos) do
        if item.sub and item.sub ~= lastSub then y = SubHeader(parent, y, item.sub) end
        lastSub = item.sub
        y = InfoRow(parent, y, W, item)
    end
    local shown = 0
    for _, site in ipairs(tile.sites) do
        if showAll or IsActive(site) then
            if site.sub and site.sub ~= lastSub then y = SubHeader(parent, y, site.sub) end
            lastSub = site.sub
            y = SiteRow(parent, y, W, site)
            shown = shown + 1
        end
    end
    if hasSites and shown == 0 then
        row, h = UnindexedDualRow(W, parent, y,
            { type = "label", text = EllesmereUI.L("No active glows. Turn off Hide Inactive Glows to edit the others.") },
            EllesmereUI.BlankRowCfg());  y = y - h
    end
    return y
end

local function BuildTileList(sites, infos)
    local byModule, infosByModule, tiles = {}, {}, {}
    local t = Template()
    for _, site in ipairs(sites) do
        local list = byModule[site.module]
        if not list then list = {}; byModule[site.module] = list end
        list[#list + 1] = site
    end
    for _, item in ipairs(infos) do
        local list = infosByModule[item.module]
        if not list then list = {}; infosByModule[item.module] = list end
        list[#list + 1] = item
    end
    for _, entry in ipairs(EllesmereUI.ADDON_ROSTER) do
        local list = byModule[entry.folder]
        local infoList = infosByModule[entry.folder]
        if (list or infoList) and not entry.comingSoon then
            list = list or {}
            local summary, active
            if #list > 0 then
                summary, active = CardSummary(list, t)
            else
                summary, active = EllesmereUI.L("Glows set per entry, which the template never changes"), 0
            end
            tiles[#tiles + 1] = {
                key = entry.folder, folder = entry.folder, display = entry.display,
                desc = summary, active = active,
                sites = list, infos = infoList or {},
                buildContent = BuildCardContent,
            }
        end
    end
    return tiles
end

local function BuildGlowCard(parent, y, W, tile)
    return EllesmereUI.BuildModuleCard(parent, y, W, tile, {
        -- Sites register only from loaded modules' option files.
        enabled = true,
        expanded = _glExpanded, descW = 560,
        -- The summary is live (counts): search indexes a fixed word instead.
        searchDesc = "Glows",
        glyph = function(hdr, enabled)
            local PP = EllesmereUI.PanelPP
            local EG = EllesmereUI.ELLESMERE_GREEN
            local glyph = CreateFrame("Frame", nil, hdr)
            PP.Size(glyph, 18, 18)
            PP.Point(glyph, "LEFT", hdr, "LEFT", 18, 0)
            EllesmereUI.MakeBorder(glyph, EG.r, EG.g, EG.b, enabled and 0.8 or 0.15, PP)
            local tex = glyph:CreateTexture(nil, "ARTWORK")
            PP.Point(tex, "TOPLEFT", glyph, "TOPLEFT", 3, -3)
            PP.Point(tex, "BOTTOMRIGHT", glyph, "BOTTOMRIGHT", -3, 3)
            tex:SetTexture(GL_GLYPH)
            tex:SetVertexColor(1, 1, 1, enabled and 0.35 or 0.1)
        end,
    })
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._EUI_BuildGlowsPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    local introHost = CreateFrame("Frame", nil, parent)
    PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 62)
    PP.Point(introHost, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 20)
    local intro = EllesmereUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    PP.Point(intro, "TOPLEFT", introHost, "TOPLEFT", 0, -2)
    PP.Point(intro, "TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("CENTER")
    intro:SetWordWrap(true)
    intro:SetText(EllesmereUI.L("Set a glow once. Apply to All changes the active custom glows listed below.") .. "\n"
        .. EllesmereUI.L("Module and row buttons also replace off glows, Blizzard Default, Blizzard Border and Solid Border.") .. "\n"
        .. EllesmereUI.L("Glows set per icon, indicator or filter keep their own settings."))
    y = y - 66

    -- Template
    _, h = W:SectionHeader(parent, "GLOW TEMPLATE", y);  y = y - h
    local tpl = TemplateDesc()
    local sites = CollectSites()
    local tplRow
    tplRow, h = W:DualRow(parent, y, GO.DropdownSpec(tpl, "Glow Style"), EllesmereUI.BlankRowCfg());  y = y - h
    if not EllesmereUI._prebuilding then
        local lrgn = tplRow._leftRegion
        GO.AttachInline(lrgn, tpl)
        local pv = GO.BuildPreview(lrgn, tpl, { anchor = lrgn._lastInline, x = -12 })
        if pv then
            pv:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            lrgn._lastInline = pv
        end
        EllesmereUI.BuildInlineButton(tplRow._rightRegion, EllesmereUI.L("Apply to All Active Glows"),
            function() ConfirmApply(sites) end, { width = 190 })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -- Module cards
    _, h = W:SectionHeader(parent, "MODULE GLOWS", y);  y = y - h
    for _, tile in ipairs(BuildTileList(sites, CollectInfos())) do
        y = BuildGlowCard(parent, y, W, tile)
    end

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Deep-link pre-hook: a jump into this page (a search result) opens every
--  card and shows every row first, so the target row exists when the jump
--  looks for it (the Fonts and Textures pages do the same).
-------------------------------------------------------------------------------
do
    local origNav = EllesmereUI.NavigateToElementSettings
    function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
        if moduleName == GLOBAL_KEY and pageName == PAGE_GLOWS and (sectionName or highlightText) then
            local changed = false
            for _, entry in ipairs(GO.sites) do
                local k = entry.module
                if k and not _glExpanded[k] then _glExpanded[k] = true; changed = true end
            end
            if next(_glHideInactive) then wipe(_glHideInactive); changed = true end
            if changed then EllesmereUI:InvalidatePageCache() end
        end
        return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
    end
end
