if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_PageParts.lua
--  Shared page parts: unlock placeholder, max duration and sound dropdown
--  data, the Global Settings rows and module card, and the manager-page
--  parts. Read at load by the Fonts and Textures options files, so it
--  loads before them.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  BuildUnlockPlaceholder
--  Reusable overlay that mirrors the unlock mode mover style. Shows accent-colored text (default "Move in
--  Unlock Mode") and opens unlock mode on click.
--  opts = {
--      parent   = frame,          -- parent frame to overlay
--      text     = "...",          -- optional, defaults to "Move in Unlock Mode"
--      level    = number,         -- optional frame level override
--      onClick  = function,       -- optional custom click handler (default: toggle unlock mode)
--  }
--  Returns the placeholder frame.
-------------------------------------------------------------------------------
function EllesmereUI.BuildUnlockPlaceholder(opts)
    local parent = opts.parent
    local eg = EllesmereUI.ELLESMERE_GREEN
    local ar, ag, ab = eg.r, eg.g, eg.b

    local f = CreateFrame("Button", nil, parent)
    f:SetAllPoints(parent)
    if opts.level then
        f:SetFrameLevel(opts.level)
    else
        f:SetFrameLevel(parent:GetFrameLevel() + 10)
    end
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp")

    -- Dark background matching unlock mode movers
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
    f._bg = bg

    -- Accent border at 60% alpha
    f._brd = EllesmereUI.MakeBorder(f, ar, ag, ab, 0.6)

    -- White centered label matching unlock mode mover style
    local fontPath = (EllesmereUI.GetFontPath("extras"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 10, "OUTLINE, SLUG")
    label:SetText(EllesmereUI.L(opts.text or "Move in Unlock Mode"))
    label:SetTextColor(1, 1, 1, 0.9)
    label:SetPoint("CENTER")
    f._label = label

    -- Hover: accent text + brighten border
    local brd = f._brd
    f:SetScript("OnEnter", function()
        label:SetTextColor(ar, ag, ab, 1)
        if brd then brd:SetColor(ar, ag, ab, 0.85) end
    end)
    f:SetScript("OnLeave", function()
        label:SetTextColor(1, 1, 1, 0.9)
        if brd then brd:SetColor(ar, ag, ab, 0.6) end
    end)

    -- Click: open unlock mode (or custom handler)
    f:SetScript("OnClick", opts.onClick or function()
        if EllesmereUI.ToggleUnlockMode then
            EllesmereUI:ToggleUnlockMode()
        end
    end)

    return f
end

-- Debuff "Max Duration" dropdown spec for a DualRow slot: Unlimited (nil, the
-- consumer adds nothing to its candidate filters) or Custom, which opens the
-- standard input popup for a whole number of seconds and then reads back as
-- "Custom (Ns)". get/set move the stored seconds (nil = unlimited); apply
-- re-drives the display. Shared by the Raid Frames Debuff Manager (base grid
-- and grid tiles) and Player Aura Bars debuff bars.
function EllesmereUI.MaxDurationDropdown(get, set, apply)
    local L = EllesmereUI.L
    local cur = get()
    local values = {
        unlimited = L("Unlimited"),
        custom = cur and (L("Custom") .. " (" .. tostring(cur) .. "s)") or (L("Custom") .. "..."),
    }
    return {
        type = "dropdown", text = "Max Duration",
        tooltip = "Only show debuffs whose full duration is at most this many seconds. Combines with the filters; Unlimited applies no cap.",
        values = values, order = { "unlimited", "custom" },
        getValue = function() return get() and "custom" or "unlimited" end,
        setValue = function(v)
            if v == "unlimited" then
                if get() ~= nil then
                    set(nil)
                    if apply then apply() end
                end
                EllesmereUI:RefreshPage(true)
                return
            end
            local now = get()
            EllesmereUI:ShowInputPopup({
                title = L("Max Duration"),
                message = L("Enter the maximum debuff duration in seconds:"),
                placeholder = now and tostring(now) or "30",
                confirmText = L("Apply"),
                cancelText = L("Cancel"),
                onConfirm = function(text)
                    local n = tonumber(text or "")
                    if n and n > 0 then
                        n = math.floor(n)
                        if n ~= get() then
                            set(n)
                            if apply then apply() end
                        end
                    end
                    EllesmereUI:RefreshPage(true)
                end,
                onCancel = function() EllesmereUI:RefreshPage(true) end,
            })
        end,
    }
end

-- Sound dropdown data for a DualRow slot or a cog row: a fresh values table
-- (a click-to-preview speaker icon on every playable row) and the order list.
-- paths / names / order are a catalogue from BuildAlertSoundTables(); left out,
-- they are the Quality of Life alert-sound catalogue (just "None" while it is
-- absent). A path is a sound file or a SoundKit id.
-- Sound preview icon for every sound picker and play button. WoW Forever has no
-- common-icon-sound atlases; its dropdown speaker stands in for both states.
EllesmereUI.SOUND_ICON_ATLAS = C_Texture.GetAtlasInfo("common-icon-sound")
    and "common-icon-sound" or "common-dropdown-icon-sound-on"
EllesmereUI.SOUND_ICON_PRESSED_ATLAS = C_Texture.GetAtlasInfo("common-icon-sound-pressed")
    and "common-icon-sound-pressed" or EllesmereUI.SOUND_ICON_ATLAS

function EllesmereUI.BuildSoundDropdownValues(paths, names, order)
    paths = paths or EllesmereUI._groupDeathSoundPaths or {}
    names = names or EllesmereUI._groupDeathSoundNames or { none = "None" }
    order = order or EllesmereUI._groupDeathSoundOrder or { "none" }
    local values = {}
    for k, v in pairs(names) do values[k] = v end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return EllesmereUI.SOUND_ICON_ATLAS
        end,
        iconPressedAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return EllesmereUI.SOUND_ICON_PRESSED_ATLAS
        end,
        iconOnClick = function(key)
            local path = paths[key]
            if type(path) == "number" then
                if path ~= 1 then PlaySound(path, "Master") end
            elseif path then
                PlaySoundFile(path, "Master")
            end
        end,
        iconTooltip = function() return "Preview Sound" end,
    }
    return values, order
end

-------------------------------------------------------------------------------
--  Global Settings > Fonts / Textures: shared row helpers and module card
-------------------------------------------------------------------------------

-- Fresh table per call: DualRow configs must never be shared across rows.
function EllesmereUI.BlankRowCfg() return { type = "label", text = "" } end

function EllesmereUI.ModuleNS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end

-- Custom link row: label on the left, an Open Settings button on the right,
-- jumping to the module page that owns a selection-bound settings family.
function EllesmereUI.BuildLinkRow(parent, y, label, module, page, section, highlight)
    local PP = EllesmereUI.PanelPP
    local ROW_H = 40
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    EllesmereUI.RowBg(row, parent)

    local lbl = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
    lbl:SetAlpha(0.9)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetText(EllesmereUI.L(label))

    local btn = CreateFrame("Button", nil, row)
    PP.Size(btn, 122, 26)
    btn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(btn, "Open Settings", 11, EllesmereUI.WB_COLOURS, function()
        EllesmereUI:NavigateToElementSettings(module, page, section, nil, highlight)
    end)

    return y - ROW_H
end

-- Dim note row shown inside a card when its module is disabled.
function EllesmereUI.BuildNoteRow(parent, y, text)
    local PP = EllesmereUI.PanelPP
    local ROW_H = 34
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.45)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetText(EllesmereUI.L(text))
    return y - ROW_H
end

local MC_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local MC_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
local MC_HEADER_H   = 54
local MC_CARD_GAP   = 14

-- One expandable module card (adapted from the Window Skins card). opts:
-- enabled, expanded (session table keyed by tile.key), descW,
-- glyph(hdr, enabled) builds the left glyph, headerDD(hdr) -> dd or nil,
-- searchDesc: what search indexes (and the header's section name carries) in
-- place of tile.desc, for a card whose description is live (a count).
-- A disabled module's card is inert: dimmed header, tag and tooltip only.
-- Sets tile._hdr and tile._descFS (the header and its description line)
-- before tile.buildContent runs, for content that updates the header.
function EllesmereUI.BuildModuleCard(parent, y, W, tile, opts)
    local PP = EllesmereUI.PanelPP
    local EG = EllesmereUI.ELLESMERE_GREEN
    local L  = EllesmereUI.L
    local enabled = opts.enabled
    local expanded = enabled and opts.expanded[tile.key]
    local cardTop = y
    local brd

    -- Explicit size + single TOPLEFT anchor (the widget contract; see the
    -- Window Skins card for why a second point would zero the width).
    local cardW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
    local hdr = CreateFrame("Button", nil, parent)
    PP.Size(hdr, cardW, MC_HEADER_H)
    PP.Point(hdr, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    hdr:SetFrameLevel(parent:GetFrameLevel() + 3)

    -- The header is its own pseudo-section, so searching the module name
    -- lands on the card; each page's deep-link pre-hook expands cards first.
    local sDesc = opts.searchDesc
    if sDesc == nil then sDesc = tile.desc or "" end
    local searchName = tile.display .. " " .. sDesc
    hdr._isSectionHeader = true
    hdr._sectionName = searchName
    local searchNameLoc = L(tile.display) .. " " .. L(sDesc)
    if searchNameLoc ~= searchName then hdr._sectionNameLoc = searchNameLoc end
    if EllesmereUI._RegisterSearchEntry then
        local titleLoc = L(tile.display)
        local descSearch = sDesc
        local descLoc = L(sDesc)
        if descLoc ~= descSearch then descSearch = descSearch .. " " .. descLoc end
        EllesmereUI._RegisterSearchEntry(tile.display,
            titleLoc ~= tile.display and titleLoc or nil,
            descSearch,
            EllesmereUI._buildingModule, EllesmereUI._buildingPage,
            searchName, nil, nil, true)
    end

    local hbg = EllesmereUI.SolidTex(hdr, "BACKGROUND", 0, 0, 0, 0)
    hbg:SetAllPoints()

    opts.glyph(hdr, enabled)

    local title = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 0.9)
    PP.Point(title, "TOPLEFT", hdr, "TOPLEFT", 50, -12)
    title:SetText(L(tile.display))

    local desc = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.42)
    PP.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(opts.descW)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetText(L(tile.desc or ""))
    tile._hdr, tile._descFS = hdr, desc

    if not enabled then
        title:SetAlpha(0.4)
        desc:SetAlpha(0.22)
    end

    local chev
    if enabled then
        chev = hdr:CreateTexture(nil, "OVERLAY")
        PP.Size(chev, 16, 16)
        PP.Point(chev, "RIGHT", hdr, "RIGHT", -16, 0)
        chev:SetTexture(expanded and MC_ARROW_UP or MC_ARROW_DOWN)
        chev:SetAlpha(0.45)
        if expanded then chev:SetVertexColor(EG.r, EG.g, EG.b) end
    end

    local dd = enabled and opts.headerDD and opts.headerDD(hdr)

    local strip
    local function ApplyHeaderHover()
        hbg:SetColorTexture(1, 1, 1, 0.05)
        title:SetAlpha(1)
        if chev then chev:SetAlpha(0.85) end
        if brd then brd:SetColor(1, 1, 1, 0.22) end
    end
    local function ClearHeaderHover()
        if hdr:IsMouseOver() then return end
        hbg:SetColorTexture(0, 0, 0, 0)
        title:SetAlpha(0.9)
        if chev then chev:SetAlpha(0.45) end
        if brd then brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12) end
    end
    if enabled then
        hdr:SetScript("OnEnter", ApplyHeaderHover)
        hdr:SetScript("OnLeave", ClearHeaderHover)
        if dd then
            dd:HookScript("OnEnter", ApplyHeaderHover)
            dd:HookScript("OnLeave", ClearHeaderHover)
        end
        hdr:SetScript("OnClick", function()
            opts.expanded[tile.key] = not opts.expanded[tile.key]
            EllesmereUI:RefreshPage(true)
        end)
    else
        local tag = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1)
        tag:SetAlpha(0.3)
        PP.Point(tag, "RIGHT", hdr, "RIGHT", -16, 0)
        tag:SetText(L("Module Disabled"))
        hdr:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.Lf("Enable %1$s to edit these settings.", L(tile.display)))
        end)
        hdr:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end

    y = y - MC_HEADER_H

    if expanded then
        local div = hdr:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.07)
        div:SetHeight(1)
        PP.Point(div, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 0)
        PP.Point(div, "BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -1, 0)
        PP.DisablePixelSnap(div)

        y = y - 8
        y = tile.buildContent(parent, y, W, tile)
        y = y - 8
    end

    -- Card background + border spanning header and expanded content (header
    -- child so inline search re-flows it with the header; see WS card notes).
    local bg = CreateFrame("Frame", nil, hdr)
    bg:SetFrameLevel(parent:GetFrameLevel())
    PP.Size(bg, cardW, cardTop - y)
    PP.Point(bg, "TOPLEFT", hdr, "TOPLEFT", 0, 0)
    local fill = EllesmereUI.SolidTex(bg, "BACKGROUND", 0.06, 0.08, 0.10, 0.5)
    fill:SetAllPoints()
    brd = EllesmereUI.MakeBorder(bg, 1, 1, 1, expanded and 0.16 or 0.12, PP)

    strip = bg:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(2)
    if enabled then
        strip:SetColorTexture(EG.r, EG.g, EG.b, 0.7)
    else
        strip:SetColorTexture(1, 1, 1, 0.10)
    end
    PP.Point(strip, "TOPLEFT", hdr, "TOPLEFT", 1, -1)
    PP.Point(strip, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 1)
    if strip.SetSnapToPixelGrid then strip:SetSnapToPixelGrid(false); strip:SetTexelSnappingBias(0) end

    return y - MC_CARD_GAP
end

-------------------------------------------------------------------------------
--  Manager-page parts (Buff Manager, Debuff Manager, Player Aura Bars)
-------------------------------------------------------------------------------
-- Sidebar tile. opts: width, fontPath, title, subtitle | subtitleFn, icon,
-- posText, selected, enabled, showToggle, dimmed, inheritedTooltip,
-- onSelect(), onToggle(newState), onDelete(), onEdit(), onContext(tile),
-- height (66), textRight (-52), titleUnclamped, editSize (16), editTooltip,
-- editSnap (keep pixel snapping on the pencil). Returns height, tile.
function EllesmereUI.BuildManagerTile(parentFrame, y, opts)
    local fontPath = opts.fontPath
    local PP = EllesmereUI.PanelPP
    local TILE_H = opts.height or 66
    local IR, IG, IB = 0.55, 0.72, 1
    local tile = CreateFrame("Button", nil, parentFrame)
    tile:SetSize(opts.width, TILE_H)
    tile:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, y)
    tile:SetFrameLevel(parentFrame:GetFrameLevel() + 1)

    local bg = tile:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, opts.selected and 0.06 or 0)

    if opts.selected then
        local accent = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetSize(2, TILE_H)
        accent:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        if opts.inheritedTooltip then
            accent:SetColorTexture(IR, IG, IB, 1)
        else
            local ac = EllesmereUI.ELLESMERE_GREEN
            accent:SetColorTexture(ac.r, ac.g, ac.b, 1)
        end
    elseif opts.inheritedTooltip then
        local edge = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        edge:SetSize(2, TILE_H)
        edge:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        edge:SetColorTexture(IR, IG, IB, 0.45)
    end

    local textX = 12
    local titleY = -10
    local textRight = opts.textRight or -52

    if opts.icon then
        local ICON_SZ = 36
        local iconFrame = CreateFrame("Frame", nil, tile)
        iconFrame:SetSize(ICON_SZ, ICON_SZ)
        iconFrame:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -8)
        iconFrame:SetFrameLevel(tile:GetFrameLevel() + 1)
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetTexture(opts.icon)
        local iconBdr = CreateFrame("Frame", nil, iconFrame)
        iconBdr:SetAllPoints()
        iconBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
        PP.CreateBorder(iconBdr, 0, 0, 0, 0.6, 1)
        textX = 8 + ICON_SZ + 8
        titleY = -8
    end

    local title = tile:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 13, "")
    title:SetPoint("TOPLEFT", tile, "TOPLEFT", textX, titleY)
    if not opts.posText and not opts.titleUnclamped then
        title:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
    end
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(opts.title or "")
    if opts.inheritedTooltip then
        title:SetTextColor(IR, IG, IB)
    else
        title:SetTextColor(1, 1, 1)
    end

    if opts.posText then
        local posFS = tile:CreateFontString(nil, "OVERLAY")
        posFS:SetPoint("LEFT", title, "RIGHT", 4, 0)
        posFS:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        posFS:SetFont(fontPath, 11, "")
        posFS:SetJustifyH("LEFT")
        posFS:SetWordWrap(false)
        posFS:SetText(opts.posText)
        posFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
    end

    if opts.subtitle or opts.subtitleFn then
        local sub = tile:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 11, "")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetText(opts.subtitleFn and opts.subtitleFn() or opts.subtitle)
        if opts.inheritedTooltip then
            sub:SetTextColor(IR, IG, IB, 0.55)
        else
            sub:SetTextColor(0.4, 0.4, 0.4)
        end
        -- Re-read on every non-force RefreshPage (a full rebuild would close
        -- an open checkbox dropdown in the detail pane).
        if opts.subtitleFn then
            EllesmereUI.RegisterWidgetRefresh(function() sub:SetText(opts.subtitleFn()) end)
        end
    end

    tile:SetScript("OnEnter", function()
        if not opts.selected then bg:SetColorTexture(1, 1, 1, 0.04) end
        if opts.inheritedTooltip then
            EllesmereUI.ShowWidgetTooltip(tile, opts.inheritedTooltip)
        end
    end)
    tile:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 1, 1, opts.selected and 0.06 or 0)
        if opts.inheritedTooltip then
            EllesmereUI.HideWidgetTooltip()
        end
    end)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            if opts.onContext then opts.onContext(tile) end
            return
        end
        if opts.onSelect then opts.onSelect() end
    end)

    if opts.showToggle then
        local toggleH = 16
        local toggleBtn = CreateFrame("Button", nil, tile)
        toggleBtn:SetSize(32, toggleH)
        toggleBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
        toggleBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        -- Inherited rows: the pill is the per-spec control and stays
        -- full-brightness when the row dims.
        if opts.inheritedTooltip and toggleBtn.SetIgnoreParentAlpha then
            toggleBtn:SetIgnoreParentAlpha(true)
        end
        local toggleBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
        toggleBg:SetAllPoints()
        local toggleKnob = toggleBtn:CreateTexture(nil, "ARTWORK")
        toggleKnob:SetSize(toggleH - 4, toggleH - 4)
        if opts.enabled then
            local acr, acg, acb = EllesmereUI.ResolveActiveAccent()
            toggleBg:SetColorTexture(acr, acg, acb, 1)
            toggleKnob:SetPoint("RIGHT", toggleBtn, "RIGHT", -2, 0)
            toggleKnob:SetColorTexture(1, 1, 1, 1)
        else
            toggleBg:SetColorTexture(0.25, 0.25, 0.25, 1)
            toggleKnob:SetPoint("LEFT", toggleBtn, "LEFT", 2, 0)
            toggleKnob:SetColorTexture(0.5, 0.5, 0.5, 1)
        end
        toggleBtn:SetScript("OnClick", function()
            if opts.onToggle then opts.onToggle(not opts.enabled) end
        end)
    end

    local delBtn
    if opts.onDelete then
        delBtn = CreateFrame("Button", nil, tile)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        delBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local delTex = delBtn:CreateTexture(nil, "OVERLAY")
        delTex:SetAllPoints()
        EllesmereUI.SetDeleteIcon(delTex)
        delTex:SetDesaturated(true)
        delTex:SetVertexColor(0.75, 0.75, 0.75)
        delBtn:SetAlpha(0.5)
        delBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        delBtn:SetScript("OnClick", function() opts.onDelete() end)
    end

    -- Rename pencil beside the trash.
    if opts.onEdit then
        local editSize = opts.editSize or 16
        local editBtn = CreateFrame("Button", nil, tile)
        editBtn:SetSize(editSize, editSize)
        if delBtn then
            editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
        else
            editBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        end
        editBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local editTex = editBtn:CreateTexture(nil, "OVERLAY")
        editTex:SetAllPoints()
        if not opts.editSnap and editTex.SetSnapToPixelGrid then
            editTex:SetSnapToPixelGrid(false); editTex:SetTexelSnappingBias(0)
        end
        editTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
        editBtn:SetAlpha(0.5)
        local tip = opts.editTooltip
        editBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
            if tip then EllesmereUI.ShowWidgetTooltip(self, tip) end
        end)
        editBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
            if tip then EllesmereUI.HideWidgetTooltip() end
        end)
        editBtn:SetScript("OnClick", function() opts.onEdit() end)
    end

    local sep = tile:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.04)

    if opts.dimmed then tile:SetAlpha(0.55) end

    return TILE_H, tile
end

-- Full-page cover over a manager page (override-session notice or the PAB
-- enable prompt). opts: fontPath, width, title, text, sub, buttonLabel.
-- Returns ov, btn (btn only with buttonLabel; the caller sets its OnClick).
function EllesmereUI.BuildActivationOverlay(outerRoot, opts)
    local fontPath = opts.fontPath
    local ov = CreateFrame("Frame", nil, outerRoot)
    ov:SetAllPoints(outerRoot)
    ov:SetFrameLevel(outerRoot:GetFrameLevel() + 60)
    ov:EnableMouse(true)
    ov._searchIgnore = true
    local bg = ov:CreateTexture(nil, "OVERLAY")
    bg:SetAllPoints()
    bg:SetColorTexture(13/255, 17/255, 25/255, 0.98)
    local title = ov:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 15, "")
    title:SetPoint("CENTER", ov, "CENTER", 0, 60)
    title:SetTextColor(1, 1, 1, 0.9)
    title:SetText(opts.title)
    local body = ov:CreateFontString(nil, "OVERLAY")
    body:SetFont(fontPath, 13, "")
    body:SetPoint("TOP", title, "BOTTOM", 0, -14)
    body:SetWidth(math.floor(opts.width * 0.7))
    body:SetJustifyH("CENTER")
    body:SetTextColor(1, 1, 1, 0.56)
    body:SetText(opts.text or "")
    local sub
    if opts.sub then
        sub = ov:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 12, "")
        sub:SetPoint("TOP", body, "BOTTOM", 0, -8)
        sub:SetWidth(math.floor(opts.width * 0.7))
        sub:SetJustifyH("CENTER")
        sub:SetTextColor(1, 1, 1, 0.45)
        sub:SetText(opts.sub)
    end
    if not opts.buttonLabel then return ov end
    local btn = CreateFrame("Button", nil, ov)
    btn:SetSize(240, 28)
    btn:SetPoint("TOP", sub or body, "BOTTOM", 0, -22)
    EllesmereUI.SolidTex(btn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9):SetAllPoints(btn)
    local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.22)
    local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1, 0.85)
    lbl:SetPoint("CENTER")
    lbl:SetText(opts.buttonLabel)
    local eg = EllesmereUI.ELLESMERE_GREEN
    btn:SetScript("OnEnter", function() brd:SetColor(eg.r, eg.g, eg.b, 0.9) end)
    btn:SetScript("OnLeave", function() brd:SetColor(1, 1, 1, 0.22) end)
    return ov, btn
end

-- Filter-editor popup button (dark bg, 1px border, accent border on hover).
function EllesmereUI.BuildPopupButton(parent, w, h, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", 0, 0, 0, 0.5); bg:SetAllPoints()
    local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
    local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.6)
    lbl:SetPoint("CENTER")
    lbl:SetText(EllesmereUI.L(label))
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    btn:SetScript("OnEnter", function() lbl:SetAlpha(0.9); brd:SetColor(ar, ag, ab, 0.6) end)
    btn:SetScript("OnLeave", function() lbl:SetAlpha(0.6); brd:SetColor(1, 1, 1, 0.25) end)
    btn:SetScript("OnClick", onClick)
    return btn
end
