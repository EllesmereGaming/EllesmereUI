if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_RaidFrames_ManagerPages.lua
-- 12.1 redesigned manager options: the Debuff Manager page (sidebar of
-- tiles with the undeletable Base Icons tile first) and the Buff Manager page's Base
-- Icons pieces (pinned sidebar tile + left detail pane) that the page file splices in.
--
-- All settings written here are new additive keys (dmDebuff table,
-- bmBaseEnabled/bmIndicatorsEnabled shims, bmSimple keys that already
-- exist); the legacy mode/preset keys are never written.

local ns = EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page
local EllesmereUI = _G.EllesmereUI

local floor = math.floor
local max = math.max

local TILE_H = 66 -- Buff Manager sidebar tile height (visual parity)

local POS_VALUES = { topleft = "Top Left", top = "Top", topright = "Top Right", left = "Left",
    center = "Center", right = "Right", bottomleft = "Bottom Left", bottom = "Bottom", bottomright = "Bottom Right" }
local POS_ORDER = EllesmereUI.POSITION_GRID_ORDER
local GROW_VALUES = EllesmereUI.GROW_DIR_VALUES_FULL
local GROW_ORDER = EllesmereUI.GROW_DIR_ORDER_FULL

local CAT_VALUES = { boss = "Boss", role = "Role", priority = "Important",
    cc = "Crowd Control", raid = "Raid", raidcombat = "Raid In Combat", dispel = "Dispellable",
    nonplayer = "Non-Player" }
local CAT_ORDER = { "nonplayer", "priority", "boss", "role", "cc", "raid", "raidcombat", "dispel" }

local TYPE_NAMES = { icons = "Icon", glow = "Frame Glow", square = "Square",
    healthcolor = "Health Bar Color", bar = "Duration Bar" }
-- Grid types above the divider, frame effects below (BM dropdown parity).
local TYPE_ORDER = { "icons", "square", "---", "glow", "healthcolor", "bar" }

-- 5-state aura tooltip mode stored on the legacy hide-tooltips keys:
-- true/nil = hidden, false = shown, "cursor" = shown at the cursor,
-- "combat" = shown but hidden during combat, "modifier" = shown only while
-- the Use Modifier cog's key is held.
local TIP_VALUES = { hidden = "Hidden", shown = "Shown",
    cursor = "Shown At Cursor", modifier = "Shown on Modifier",
    combat = "Hidden In Combat" }
local TIP_ORDER = { "hidden", "shown", "cursor", "modifier", "combat" }
local function TipModeKey(v)
    if v == false then return "shown" end
    if v == "cursor" or v == "combat" or v == "modifier" then return v end
    return "hidden"
end
local function TipModeStore(k)
    if k == "shown" then return false end
    if k == "hidden" then return true end
    return k
end

-- Page-local selection: "base" or a tile id. Reset when the page rebuilds
-- with a vanished selection.
local dmSel = "base"
-- Add New popup's picked indicator type (session-sticky like the BM's).
local dmSelType = "icons"
-- Editing-spec bucket: "allspecs" (the legacy tile list), a group bucket
-- key, or a concrete "spec<ID>". Session-sticky like dmSel.
local dmSpecSel = "allspecs"
-- Inherited-tile selection ({ group, id }); wins over dmSel while set.
local dmInhSel = nil

local function L(s) return EllesmereUI.L and EllesmereUI.L(s) or s end

-- Stable random preview swipe seeds (fraction remaining, 0.2-0.9), keyed by preview
-- slot index -- generated once and reused so refreshes never reshuffle the frozen swipe
-- positions (same pattern as the Buff Manager preview's own seeds).
local pvCDSeeds = {}
local function GetPvCDSeed(i)
    local v = pvCDSeeds[i]
    if not v then v = 0.2 + math.random() * 0.7; pvCDSeeds[i] = v end
    return v
end

local function DmApply()
    if ns.ReloadFrames then ns.ReloadFrames() end
    -- Live preview parity with the BM page: every setting change re-renders
    -- the page's preview band immediately.
    if ns.DMP_RefreshPreview then ns.DMP_RefreshPreview() end
end

local function DmProfile()
    return ns.db and ns.db.profile
end

local function DmTable()
    local p = DmProfile()
    if not p then return nil end
    local dm = p.dmDebuff
    if not dm then dm = {}; p.dmDebuff = dm end
    return dm
end

-------------------------------------------------------------------------------
-- Shared tile widget (used by the DM sidebar and the BM Base Icons splice)
-------------------------------------------------------------------------------
-- opts: { width, fontPath, title, subtitle, selected, enabled,
--         showToggle, onSelect(), onToggle(newState), onDelete(),
--         icon (texture), posText ("(Top Left)" gray inline suffix),
--         inheritedTooltip (string; marks the INHERITED variant: blue
--         identity tint on title/subtitle, always-on blue edge strip, hover
--         tooltip -- callers pass no onDelete/onEdit and wire onToggle to
--         the per-spec disable) }
-- Mirrors the Buff Manager sidebar tile exactly (66px rows, 36px icon face, 13px title
-- + gray position suffix, 11px gray subtitle, pill toggle with the active accent, atlas
-- delete icon, accent selected bar, hairline separator) so both manager pages stay
-- visually and structurally identical.
local INH_R, INH_G, INH_B = 0.55, 0.72, 1
local function BuildTile(parentFrame, y, opts)
    local fontPath = opts.fontPath
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
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
            accent:SetColorTexture(INH_R, INH_G, INH_B, 1)
        else
            local ac = EllesmereUI.ELLESMERE_GREEN
            if ac then accent:SetColorTexture(ac.r, ac.g, ac.b, 1)
            else accent:SetColorTexture(0.05, 0.82, 0.62, 1) end
        end
    elseif opts.inheritedTooltip then
        local edge = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        edge:SetSize(2, TILE_H)
        edge:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        edge:SetColorTexture(INH_R, INH_G, INH_B, 0.45)
    end

    local textX = 12
    local titleY = -10
    local textRight = -52 -- room for toggle + delete (BM parity)

    -- Icon face (BM tile parity: 36px, zoom crop, black border)
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
        if PP then
            local iconBdr = CreateFrame("Frame", nil, iconFrame)
            iconBdr:SetAllPoints()
            iconBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            PP.CreateBorder(iconBdr, 0, 0, 0, 0.6, 1)
        end
        textX = 8 + ICON_SZ + 8
        titleY = -8
    end

    local title = tile:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 13, "")
    title:SetPoint("TOPLEFT", tile, "TOPLEFT", textX, titleY)
    if not opts.posText then
        title:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
    end
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(opts.title or "")
    if opts.inheritedTooltip then
        title:SetTextColor(INH_R, INH_G, INH_B)
    else
        title:SetTextColor(1, 1, 1)
    end

    -- Position suffix (smaller, grayer, inline after the title -- BM parity)
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

    if opts.subtitle then
        local sub = tile:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 11, "")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetText(opts.subtitle)
        if opts.inheritedTooltip then
            sub:SetTextColor(INH_R, INH_G, INH_B, 0.55)
        else
            sub:SetTextColor(0.4, 0.4, 0.4)
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
    -- Right-click routes to opts.onContext (the "Add To" menu) when the
    -- caller provides it; tiles without it ignore right-clicks.
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            if opts.onContext then opts.onContext(tile) end
            return
        end
        if opts.onSelect then opts.onSelect() end
    end)

    if opts.showToggle then
        local toggleW, toggleH = 32, 16
        local toggleBtn = CreateFrame("Button", nil, tile)
        toggleBtn:SetSize(toggleW, toggleH)
        toggleBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
        toggleBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        -- Inherited rows: the pill is the per-spec CONTROL and stays
        -- full-brightness even when the row dims (opts.dimmed) or wears the
        -- inherited tint -- SetAlpha on the tile inherits to children.
        if opts.inheritedTooltip and toggleBtn.SetIgnoreParentAlpha then
            toggleBtn:SetIgnoreParentAlpha(true)
        end
        local toggleBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
        toggleBg:SetAllPoints()
        local toggleKnob = toggleBtn:CreateTexture(nil, "ARTWORK")
        toggleKnob:SetSize(toggleH - 4, toggleH - 4)
        local function UpdateToggleVisual()
            toggleKnob:ClearAllPoints()
            if opts.enabled then
                local acr, acg, acb = 0.05, 0.82, 0.62
                if EllesmereUI.ResolveActiveAccent then
                    acr, acg, acb = EllesmereUI.ResolveActiveAccent()
                end
                toggleBg:SetColorTexture(acr, acg, acb, 1)
                toggleKnob:SetPoint("RIGHT", toggleBtn, "RIGHT", -2, 0)
                toggleKnob:SetColorTexture(1, 1, 1, 1)
            else
                toggleBg:SetColorTexture(0.25, 0.25, 0.25, 1)
                toggleKnob:SetPoint("LEFT", toggleBtn, "LEFT", 2, 0)
                toggleKnob:SetColorTexture(0.5, 0.5, 0.5, 1)
            end
        end
        UpdateToggleVisual()
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
        delTex:SetAtlas("common-icon-delete")
        delTex:SetDesaturated(true)
        delTex:SetVertexColor(0.75, 0.75, 0.75)
        delBtn:SetAlpha(0.5)
        delBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        delBtn:SetScript("OnClick", function() opts.onDelete() end)
    end

    -- Rename pencil beside the trash (the suite's standard eui-edit inline
    -- button, delete-icon size).
    if opts.onEdit then
        local editBtn = CreateFrame("Button", nil, tile)
        editBtn:SetSize(16, 16)
        if delBtn then
            editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
        else
            editBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        end
        editBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local editTex = editBtn:CreateTexture(nil, "OVERLAY")
        editTex:SetAllPoints()
        if editTex.SetSnapToPixelGrid then editTex:SetSnapToPixelGrid(false); editTex:SetTexelSnappingBias(0) end
        editTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
        editBtn:SetAlpha(0.5)
        editBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
            EllesmereUI.ShowWidgetTooltip(self, L("Rename Indicator"))
        end)
        editBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
            EllesmereUI.HideWidgetTooltip()
        end)
        editBtn:SetScript("OnClick", function() opts.onEdit() end)
    end

    -- Thin separator line at bottom of tile (BM parity)
    local sep = tile:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.04)

    -- Dimmed rows (inherited tiles whose GROUP disabled the entry): the
    -- whole tile fades; the pill stays the per-spec layer's own state.
    if opts.dimmed then tile:SetAlpha(0.55) end

    return TILE_H
end

-------------------------------------------------------------------------------
-- BUFF MANAGER splice pieces (called from the Buff Manager page)
-------------------------------------------------------------------------------

-- The pinned Base Icons sidebar tile. Returns the height consumed.
function ns.BMP_BuildBaseTile(sidebarFrame, sidebarW, tileY, opts)
    local p = DmProfile()
    local bs = p and p.bmSimple
    local enabled = (ns.BM_BaseActive and ns.BM_BaseActive())
        and (bs and bs.showBuffs ~= false) and true or false
    return BuildTile(sidebarFrame, tileY, {
        width = sidebarW, height = TILE_H, fontPath = opts.fontPath,
        title = L("Base Icons"),
        subtitle = L("The standard buff grid"),
        selected = opts.selected,
        enabled = enabled,
        showToggle = true,
        onSelect = opts.onSelect,
        onToggle = function(v)
            if p then
                -- Interacting adopts the coexistence keys: the shim default
                -- (derived from the old mode) is replaced by explicit state.
                p.bmBaseEnabled = true
                local b = p.bmSimple
                if not b then b = {}; p.bmSimple = b end
                b.showBuffs = v and true or false
            end
            DmApply()
            EllesmereUI:RefreshPage(true)
        end,
    })
end

-- The Base Icons detail pane for the Buff Manager page: the simple-setup
-- preview plus its full settings block, built at left-column width. A
-- faithful transcription of the legacy Simple Setup body over the SAME
-- bmSimple keys (the legacy inline builder stays untouched for 12.0).
function ns.BMP_BuildBaseDetail(root, leftW, visibleH, s, fontPath, PP)
    local W = EllesmereUI.Widgets
    if not W then return end
    ns._bmPreviewFrame = nil

    local bs = s.bmSimple
    if not bs then bs = {}; s.bmSimple = bs end

    local PREVIEW_TOP = -16
    local _pv, pvSectionH, RefreshSimplePreview =
        ns.BM_BuildSimplePreview(root, s, fontPath, PP, leftW / 2, PREVIEW_TOP)

    local function BVal(key, default) local v = bs[key]; if v == nil then return default end; return v end
    local function BApply()
        if ns.ReloadFrames then ns.ReloadFrames() end
        if RefreshSimplePreview then RefreshSimplePreview() end
    end
    local function BSet(key, v) bs[key] = v; BApply() end
    local function BuffsOff() return not (bs.showBuffs ~= false) end

    local function GetDefaultGrow(pos)
        if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
        if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
        if pos == "top" then return "DOWN" end
        if pos == "bottom" then return "UP" end
        return "CENTER"
    end

    local PADX = 20
    local optsFrame = CreateFrame("Frame", nil, root)
    optsFrame:SetPoint("TOPLEFT", root, "TOPLEFT", PADX, PREVIEW_TOP - pvSectionH - 4)
    optsFrame:SetPoint("TOPRIGHT", root, "TOPLEFT", leftW - PADX, PREVIEW_TOP - pvSectionH - 4)
    optsFrame:SetHeight(400)
    optsFrame._showRowDivider = true

    local sy, hh = 0, 0

    _, hh = W:DualRow(optsFrame, sy,
        { type = "toggle", text = "Show Buffs",
          getValue = function() return bs.showBuffs ~= false end,
          setValue = function(v)
              bs.showBuffs = v
              s.bmBaseEnabled = true -- adopt the coexistence key on interaction
              BApply(); EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Max Buffs", min = 1, max = 10, step = 1,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("maxBuffs", 10) end,
          setValue = function(v) BSet("maxBuffs", v) end }); sy = sy - hh

    _, hh = W:SectionHeader(optsFrame, "BUFF DISPLAY", sy); sy = sy - hh

    local row1
    row1, hh = W:DualRow(optsFrame, sy,
        { type = "slider", text = "Icons Per Row", min = 1, max = 8, step = 1,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("iconsPerRow", 4) end,
          setValue = function(v) BSet("iconsPerRow", v) end },
        { type = "dropdown", text = "Position", values = POS_VALUES, order = POS_ORDER,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("position", "topright") end,
          setValue = function(v)
              bs.position = v
              bs.growDirection = GetDefaultGrow(v)
              BApply()
              EllesmereUI:RefreshPage()
          end }); sy = sy - hh
    do
        local rgn = row1._rightRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Buff Offset",
            rows = {
                { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                  get = function() return BVal("offsetX", 0) end, set = function(v) BSet("offsetX", v) end },
                { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                  get = function() return BVal("offsetY", 0) end, set = function(v) BSet("offsetY", v) end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
        local function UpdCog() local off = BuffsOff(); cogBtn:SetAlpha(off and 0.15 or 0.4); cogBtn:EnableMouse(not off) end
        cogBtn:SetScript("OnEnter", function(self) if not BuffsOff() then self:SetAlpha(0.7) end end)
        cogBtn:SetScript("OnLeave", function() UpdCog() end)
        cogBtn:SetScript("OnClick", function(self) if not BuffsOff() then cogShow(self) end end)
        UpdCog(); EllesmereUI.RegisterWidgetRefresh(UpdCog)
    end

    local row2
    row2, hh = W:DualRow(optsFrame, sy,
        { type = "dropdown", text = "Growth Direction", values = GROW_VALUES, order = GROW_ORDER,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("growDirection", "LEFT") end,
          setValue = function(v) BSet("growDirection", v) end },
        { type = "slider", text = "Size", min = 10, max = 40, step = 1,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("size", 22) end,
          setValue = function(v) BSet("size", v) end }); sy = sy - hh
    do
        local rgn = row2._rightRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Icon Zoom",
            rows = {
                { type = "slider", label = "Zoom", min = 0, max = 0.20, step = 0.01,
                  get = function() return BVal("iconZoom", 0.08) end,
                  set = function(v) BSet("iconZoom", v) end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        local function UpdCog() local off = BuffsOff(); cogBtn:SetAlpha(off and 0.15 or 0.4); cogBtn:EnableMouse(not off) end
        cogBtn:SetScript("OnEnter", function(self) if not BuffsOff() then self:SetAlpha(0.7) end end)
        cogBtn:SetScript("OnLeave", function() UpdCog() end)
        cogBtn:SetScript("OnClick", function(self) if not BuffsOff() then cogShow(self) end end)
        UpdCog(); EllesmereUI.RegisterWidgetRefresh(UpdCog)
    end

    local row3
    row3, hh = W:DualRow(optsFrame, sy,
        { type = "slider", pixel = true, text = "Spacing", min = -1, max = 10, step = 1,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("spacing", 1) end,
          setValue = function(v) BSet("spacing", v) end },
        { type = "slider", text = "Border Size", min = 0, max = 4, step = 1, trackWidth = 120,
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("borderSize", 1) end,
          setValue = function(v) BSet("borderSize", v) end }); sy = sy - hh
    do
        local rgn = row3._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, row3:GetFrameLevel() + 3,
            function() local c = bs.borderColor or { r = 0, g = 0, b = 0 }; return c.r, c.g, c.b, 1 end,
            function(r, g, b) bs.borderColor = { r = r, g = g, b = b }; BApply() end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
    end

    local row4
    row4, hh = W:DualRow(optsFrame, sy,
        { type = "toggle", text = "Show Duration Swipe",
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("showSwipe", true) end,
          setValue = function(v) BSet("showSwipe", v) end },
        { type = "toggle", text = "Show Duration Text",
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("showDurText", false) end,
          setValue = function(v) BSet("showDurText", v) end }); sy = sy - hh
    do
        local rgn = row4._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, row4:GetFrameLevel() + 3,
            function() local c = bs.durTextColor or { r = 1, g = 1, b = 1 }; return c.r, c.g, c.b, 1 end,
            function(r, g, b) bs.durTextColor = { r = r, g = g, b = b }; BApply() end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch

        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Duration Text",
            rows = {
                { type = "slider", label = "Text Size", min = 6, max = 26, step = 1,
                  get = function() return BVal("durTextSize", 8) end, set = function(v) BSet("durTextSize", v) end },
                { type = "slider", label = "Offset X", min = -20, max = 20, step = 1,
                  get = function() return BVal("durTextOffsetX", 0) end, set = function(v) BSet("durTextOffsetX", v) end },
                { type = "slider", label = "Offset Y", min = -20, max = 20, step = 1,
                  get = function() return BVal("durTextOffsetY", 0) end, set = function(v) BSet("durTextOffsetY", v) end },
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

    local row5
    row5, hh = W:DualRow(optsFrame, sy,
        { type = "toggle", text = "Show Stacks",
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("showStacks", true) end,
          setValue = function(v) BSet("showStacks", v) end },
        { type = "toggle", text = "Own Only", tooltip = "Shows only the buffs you apply",
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("ownOnly", true) end,
          setValue = function(v) BSet("ownOnly", v) end }); sy = sy - hh
    do
        local rgn = row5._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, row5:GetFrameLevel() + 3,
            function() local c = bs.stacksTextColor or { r = 1, g = 1, b = 1 }; return c.r, c.g, c.b, 1 end,
            function(r, g, b) bs.stacksTextColor = { r = r, g = g, b = b }; BApply() end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch

        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Stacks Text",
            rows = {
                { type = "slider", label = "Text Size", min = 6, max = 26, step = 1,
                  get = function() return BVal("stacksTextSize", 8) end, set = function(v) BSet("stacksTextSize", v) end },
                { type = "slider", label = "Offset X", min = -20, max = 20, step = 1,
                  get = function() return BVal("stacksOffsetX", -1) end, set = function(v) BSet("stacksOffsetX", v) end },
                { type = "slider", label = "Offset Y", min = -20, max = 20, step = 1,
                  get = function() return BVal("stacksOffsetY", 2) end, set = function(v) BSet("stacksOffsetY", v) end },
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
        local function UpdateStacksCog()
            local off = BuffsOff() or not BVal("showStacks", true)
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            cogBtn:EnableMouse(not off)
        end
        cogBtn:SetScript("OnEnter", function(self) if not (BuffsOff() or not BVal("showStacks", true)) then self:SetAlpha(0.7) end end)
        cogBtn:SetScript("OnLeave", function() UpdateStacksCog() end)
        cogBtn:SetScript("OnClick", function(self) if not (BuffsOff() or not BVal("showStacks", true)) then cogShow(self) end end)
        UpdateStacksCog()
        EllesmereUI.RegisterWidgetRefresh(UpdateStacksCog)
    end

    _, hh = W:DualRow(optsFrame, sy,
        { type = "toggle", text = "Show Own on All Specs",
          tooltip = "Show your own class buffs on every spec, not only on the tracked healer spec.",
          disabled = BuffsOff, disabledTooltip = "Show Buffs",
          getValue = function() return BVal("showOwnAllSpecs", false) end,
          setValue = function(v)
              bs.showOwnAllSpecs = v and true or false
              if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
              BApply()
          end },
        { type = "label", text = "" }); sy = sy - hh
end

-------------------------------------------------------------------------------
-- DEBUFF MANAGER page
-------------------------------------------------------------------------------

local function TileSubtitle(t)
    -- Every tile type routes via the catch-all flavor plus the checked filter set.
    local names = {}
    if t.all == true then names[#names + 1] = L("All Debuffs") end
    if t.hasDuration == true then names[#names + 1] = L("Has Duration") end
    if t.claim then
        for _, cat in ipairs(CAT_ORDER) do
            if t.claim[cat] then names[#names + 1] = L(CAT_VALUES[cat]) end
        end
    end
    if #names == 0 then return L("No filters routed") end
    return table.concat(names, ", ")
end

-- EFFECTS section (base + grid tile panes): each effect is one DualRow --
-- left = the filters it applies to (checkbox dropdown), right = the effect
-- control. First effect: Icon Glow, a 1:1 copy of the BM display-level
-- Icon Glow control (style dropdown + class/custom inline swatches).
-- fxOwner = the PERSISTED table carrying .fxGlow (the dm table for the
-- base pane, the tile table for grid tiles).
local TILE_FILTER_ITEMS = {
    { key = "nonplayer", label = "Non-Player Auras",
      tooltip = "Debuffs not caused by any player or player pet (this is what shows most pve debuffs)." },
    { key = "priority", label = "Important",
      tooltip = "Debuffs Blizzard flags as priority for raid frames." },
    { key = "cc", label = "Crowd Control",
      tooltip = "Loss-of-control debuffs." },
    { key = "boss", label = "Boss Debuffs",
      tooltip = "Debuffs applied by boss encounters." },
    { key = "role", label = "Role Debuffs",
      tooltip = "Debuffs flagged as relevant to your role." },
    { key = "raid", label = "Raid",
      tooltip = "Blizzard's curated raid-frame debuff set." },
    { key = "raidcombat", label = "Raid In Combat",
      tooltip = "The stricter in-combat subset of the raid set." },
    { key = "dispel_you", label = "Dispellable By You",
      tooltip = "Debuffs you can dispel." },
    { key = "dispel_typed", label = "Dispels",
      tooltip = "Any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it." },
}
-- Single-lane filter checkbox dropdown for per-filter ICON EFFECTS blocks
-- (`claim` is the effect entry's claim-shaped target set). The two dispel
-- entries are mutually exclusive and steer dm.dispelMode. Tile dropdowns use
-- the full two-lane build below instead.
local function BuildFilterCBDropdown(rgn, claim, dm)
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    if rgn._control then rgn._control:Hide() end
    local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
        rgn, 190, rgn:GetFrameLevel() + 2,
        TILE_FILTER_ITEMS,
        function(k)
            if k == "dispel_you" then
                return (claim.dispel and true or false) and dm.dispelMode ~= "typed"
            elseif k == "dispel_typed" then
                return (claim.dispel and true or false) and dm.dispelMode == "typed"
            end
            return claim[k] and true or false
        end,
        function(k, v)
            if k == "dispel_you" or k == "dispel_typed" then
                if v then
                    claim.dispel = true
                    dm.dispelMode = (k == "dispel_typed") and "typed" or "you"
                else
                    claim.dispel = false
                end
                DmApply()
                return
            end
            claim[k] = v and true or false
            DmApply()
        end,
        nil, 12)
    PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
    rgn._control = cbDD
    rgn._lastInline = nil
end
-- Tile filter dropdown: full two-lane parity with the base Filters dropdown
-- (user directive 2026-08-16) plus All Debuffs and the Has Duration
-- AND-modifier. Checked claims also steer ROUTING (a claimed category renders
-- in the tile instead of the base grid), so the show lane stays live even
-- while All Debuffs is checked -- no lane locks here.
local TILE_CA_ALL = "__caAll"
local TILE_CA_DUR = "__caDur"
local TILE_LANE_ITEMS = {
    { key = TILE_CA_ALL, label = "All Debuffs",
      tooltip = "Show every debuff in this indicator. Use the Hide lane below to remove specific filters." },
    { key = TILE_CA_DUR, label = "Has Duration",
      tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff." },
    { isHeader = true, label = "Show", rightLabel = "Hide" },
    { key = "nonplayer", label = "Non-Player Auras", dual = true,
      tooltip = "Debuffs not caused by any player or player pet (this is what shows most pve debuffs)." },
    { key = "priority", label = "Important", dual = true,
      tooltip = "Debuffs Blizzard flags as priority for raid frames." },
    { key = "cc", label = "Crowd Control", dual = true,
      tooltip = "Loss-of-control debuffs." },
    { key = "boss", label = "Boss Debuffs", dual = true,
      tooltip = "Debuffs applied by boss encounters." },
    { key = "role", label = "Role Debuffs", dual = true,
      tooltip = "Debuffs flagged as relevant to your role." },
    { key = "raid", label = "Raid", dual = true,
      tooltip = "Blizzard's curated raid-frame debuff set." },
    { key = "raidcombat", label = "Raid In Combat", dual = true,
      tooltip = "The stricter in-combat subset of the raid set." },
    { key = "dispel_you", label = "Dispellable By You", dual = true,
      tooltip = "Debuffs you can dispel." },
    { key = "dispel_typed", label = "Dispels", dual = true,
      tooltip = "Any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it." },
}
local function BuildTileFiltersDD(rgn, t, dm)
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    if rgn._control then rgn._control:Hide() end
    if not t.claim then t.claim = {} end
    local claim = t.claim
    local function NegHas(cat) return t.neg ~= nil and t.neg[cat] == true end
    local function SetNeg(cat, v)
        if v then
            t.neg = t.neg or {}
            t.neg[cat] = true
        elseif t.neg then
            t.neg[cat] = nil
            if not next(t.neg) then t.neg = nil end
        end
    end
    local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
        rgn, 190, rgn:GetFrameLevel() + 2,
        TILE_LANE_ITEMS,
        function(k, neg)
            if k == TILE_CA_ALL then return t.all == true end
            if k == TILE_CA_DUR then return t.hasDuration == true end
            if k == "dispel_you" then
                if neg then return NegHas("dispel") and dm.dispelMode ~= "typed" end
                return (claim.dispel and true or false) and dm.dispelMode ~= "typed"
            elseif k == "dispel_typed" then
                if neg then return NegHas("dispel") and dm.dispelMode == "typed" end
                return (claim.dispel and true or false) and dm.dispelMode == "typed"
            end
            if neg then return NegHas(k) end
            return claim[k] and true or false
        end,
        function(k, v, neg)
            if k == TILE_CA_ALL or k == TILE_CA_DUR then
                -- Independent bits: All Debuffs = catch-all, Has Duration =
                -- AND-modifier (combinable with All or any claims).
                if k == TILE_CA_ALL then
                    t.all = v and true or nil
                else
                    t.hasDuration = v and true or nil
                end
                DmApply()
                EllesmereUI:RefreshPage()
                return
            end
            if k == "dispel_you" or k == "dispel_typed" then
                -- ONE dispel category, one global flavor (shared with the base
                -- grid): any checked lane owns both the lane and dm.dispelMode;
                -- checking one lane/flavor clears the other.
                if neg then
                    SetNeg("dispel", v and true or false)
                    if v then
                        claim.dispel = nil
                        dm.dispelMode = (k == "dispel_typed") and "typed" or "you"
                    end
                else
                    claim.dispel = v and true or nil
                    if v then
                        SetNeg("dispel", false)
                        dm.dispelMode = (k == "dispel_typed") and "typed" or "you"
                    end
                end
                DmApply()
                EllesmereUI:RefreshPage()
                return
            end
            -- Two-lane category write: checking one lane clears the other.
            if neg then
                SetNeg(k, v and true or false)
                if v then claim[k] = nil end
            else
                claim[k] = v and true or nil
                if v then SetNeg(k, false) end
            end
            DmApply()
            -- Non-force: re-evaluates the base dropdown's empty-selection
            -- warning (tile claims count as grid content) without closing
            -- the menu.
            EllesmereUI:RefreshPage()
        end,
        nil, 12)
    PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
    rgn._control = cbDD
    rgn._lastInline = nil
end
local function BuildFxEffects(frame, sy, fxOwner)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    if not (W and PP) then return sy end
    local hh
    local MEDIA_MP = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

    -- One-time heal: the first Effects build stored a single fxGlow config.
    if fxOwner.fxGlow then
        local fg = fxOwner.fxGlow
        fxOwner.fxList = fxOwner.fxList or {}
        fxOwner.fxList[#fxOwner.fxList + 1] = {
            filters = fg.filters or {},
            glowType = fg.type, glowClassColor = fg.classColor,
            glowR = fg.r, glowG = fg.g, glowB = fg.b,
        }
        fxOwner.fxGlow = nil
    end
    local list = fxOwner.fxList or {}

    local GLOW_VALUES = { [0] = "None" }
    local GLOW_ORDER = { 0 }
    local Styles = EllesmereUI.Glows and EllesmereUI.Glows.STYLES
    if Styles then
        for i, entry in ipairs(Styles) do
            -- Auto-Cast Shine joins Shape Glow in the exclusions: these
            -- glows live on the forbidden slot-button subtree, and neither
            -- style has a C-side equivalent to render there (stale saved
            -- picks fall back to Modern WoW Glow via StartEngineGlow).
            if not (entry.shapeGlow or entry.autocast) then
                GLOW_VALUES[i] = entry.name
                GLOW_ORDER[#GLOW_ORDER + 1] = i
            end
        end
    end

    -- One "ICON EFFECTS" section block per list entry.
    for bi = 1, #list do
        local e = list[bi]
        if not e.filters then e.filters = {} end

        local hdrRgn
        hdrRgn, hh = W:SectionHeader(frame, "ICON EFFECTS", sy); sy = sy - hh
        -- Remove X right after the section title text
        if hdrRgn then
            local del = CreateFrame("Button", nil, hdrRgn)
            del:SetSize(14, 14)
            if hdrRgn._label then
                del:SetPoint("LEFT", hdrRgn._label, "RIGHT", 8, 0)
            else
                del:SetPoint("BOTTOMRIGHT", hdrRgn, "BOTTOMRIGHT", 0, 6)
            end
            del:SetFrameLevel(hdrRgn:GetFrameLevel() + 2)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then dx:SetSnapToPixelGrid(false); dx:SetTexelSnappingBias(0) end
            dx:SetTexture(MEDIA_MP .. "eui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                EllesmereUI.HideWidgetTooltip()
            end)
            local blockIdx = bi
            del:SetScript("OnClick", function()
                table.remove(list, blockIdx)
                DmApply()
                EllesmereUI:RefreshPage(true)
            end)
        end

        -- Row 1: Filters | Icon Glow (+ class/custom swatches)
        local row
        row, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Filters",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            { type = "dropdown", text = "Icon Glow",
              values = GLOW_VALUES, order = GLOW_ORDER,
              getValue = function() return e.glowType or 0 end,
              setValue = function(v) e.glowType = v; DmApply(); EllesmereUI:RefreshPage() end }); sy = sy - hh
        do
            -- The SAME filter dropdown as Assigned Debuffs / tile panes
            -- (shared items incl. the split dispel entries + tooltips).
            if not e.filters then e.filters = {} end
            BuildFilterCBDropdown(row._leftRegion, e.filters, DmTable() or {})
        end
        do
            local rgn = row._rightRegion
            local ctrl = rgn._control

            local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 0.82, 0
                end,
                function() end,
                false, 20)
            PP.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", function()
                e.glowClassColor = true; DmApply(); EllesmereUI:RefreshPage()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function() return e.glowR or 1.0, e.glowG or 0.776, e.glowB or 0.376 end,
                function(r, g, b)
                    e.glowR, e.glowG, e.glowB = r, g, b
                    DmApply()
                end,
                false, 20)
            PP.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
            glowSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(glowSwatch, "Custom Colored")
            end)
            glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Click the dimmed custom swatch to switch back from class color.
            local origGlowClick = glowSwatch:GetScript("OnClick")
            glowSwatch:SetScript("OnClick", function(self, ...)
                if e.glowClassColor then
                    e.glowClassColor = false; DmApply(); EllesmereUI:RefreshPage()
                    return
                end
                if (e.glowType or 0) == 0 then return end
                if origGlowClick then origGlowClick(self, ...) end
            end)

            local function UpdateFxGlowState()
                local noGlow = (e.glowType or 0) == 0
                local isClassColored = e.glowClassColor
                glowSwatch:SetAlpha((isClassColored or noGlow) and 0.3 or 1)
                classSwatch:SetAlpha((isClassColored and not noGlow) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateGlowSwatch(); updateClassSwatch(); UpdateFxGlowState() end)
            UpdateFxGlowState()
        end

        -- Row 2: Border (+ swatch, the DISPLAY-section Border style) | Size
        -- (icon size for the matched filters; 0 = the grid's own size).
        local bRow
        bRow, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Border", min = 0, max = 4, step = 1, trackWidth = 120,
              getValue = function() return e.borderSize or 0 end,
              setValue = function(v) e.borderSize = v; DmApply() end },
            { type = "slider", text = "Size", min = 0, max = 40, step = 1, trackWidth = 120,
              getValue = function() return e.size or 0 end,
              setValue = function(v)
                  e.size = (v and v > 0) and v or nil
                  DmApply()
              end }); sy = sy - hh
        do
            local rgn = bRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, bRow:GetFrameLevel() + 3,
                function()
                    local c = e.borderColor or { r = 0, g = 0, b = 0 }
                    return c.r or 0, c.g or 0, c.b or 0, 1
                end,
                function(r, g, b)
                    e.borderColor = { r = r, g = g, b = b }
                    DmApply()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end
    end

    -- "Add Icon Effects Per-Filter" accent text link (centered)
    do
        local ar, ag, ab = 1, 0.82, 0.30
        if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
        local addBtn = CreateFrame("Button", nil, frame)
        addBtn:SetHeight(22)
        addBtn:SetPoint("TOP", frame, "TOP", 0, sy - 17)
        addBtn:SetFrameLevel(frame:GetFrameLevel() + 2)
        local lbl = addBtn:CreateFontString(nil, "OVERLAY")
        local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("options")) or "Fonts\\FRIZQT__.TTF"
        lbl:SetFont(fp, 16, "")
        lbl:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        lbl:SetText(EllesmereUI.L("Add Icon Effects Per-Filter"))
        lbl:SetTextColor(ar, ag, ab)
        lbl:SetAlpha(0.9)
        addBtn:SetWidth(lbl:GetStringWidth() + 8)
        addBtn:SetScript("OnEnter", function() lbl:SetAlpha(1) end)
        addBtn:SetScript("OnLeave", function() lbl:SetAlpha(0.9) end)
        addBtn:SetScript("OnClick", function()
            if not fxOwner.fxList then fxOwner.fxList = {} end
            fxOwner.fxList[#fxOwner.fxList + 1] = { filters = {} }
            EllesmereUI:RefreshPage(true)
        end)
        sy = sy - 17 - 22 - 8
    end
    return sy
end

-- Shared tile Filters checkbox dropdown (grid AND effect tiles): identical
-- items/behavior to the Base Icons pane's Base Filters dropdown, writing the tile's
-- t.claim set (the dispel flavors also steer the global mode). Auto-default growth for
-- a just-picked anchor (BM parity): icons flow INTO the frame from the anchored edge;
-- the user can still override the growth afterwards.
local function DmDefaultGrow(pos)
    if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
    if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
    if pos == "top" then return "DOWN" end
    if pos == "bottom" then return "UP" end
    return "CENTER"
end

-- Detail builders (left pane). Each builds W rows on `frame` and manages
-- its own vertical cursor.
local function BuildBaseDetailDM(frame, fontPath)
    local W = EllesmereUI.Widgets
    local p = DmProfile()
    local dm = DmTable()
    if not (W and p and dm) then return 0 end
    frame._showRowDivider = true
    local sy, hh = 0, 0

    _, hh = W:SectionHeader(frame, "ASSIGNED DEBUFFS", sy); sy = sy - hh

    -- Unified Filters dropdown (Player Aura Bars parity): pinned "All Debuffs" row
    -- above a Show/Hide caption row, then TWO-LANE category rows -- ONE control,
    -- live in both modes. The left checkbox SHOWS a category (dm[cat], add mode;
    -- dimmed while All Debuffs is on), the right red box HIDES it (dm.neg[cat],
    -- subtracting in both modes -- see BuildRecords). Lanes are mutually exclusive
    -- per category and persist across mode flips.
    local safRow
    safRow, hh = W:DualRow(frame, sy,
        { type = "dropdown", text = "Filters",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end },
        { type = "label", text = "" }); sy = sy - hh
    do
        local PPl = EllesmereUI.PP or EllesmereUI.PanelPP
        local rgn = safRow._leftRegion
        if rgn._control then rgn._control:Hide() end
        local DM_ALL_KEY = "__all"
        local DM_DUR_KEY = "__hasDuration"
        local function AllOn() return dm.all ~= false end
        local FILTER_ITEMS = {
            { key = DM_ALL_KEY, label = "All Debuffs",
              tooltip = "Show every debuff. Use the Hide lane below to remove specific filters." },
            { key = DM_DUR_KEY, label = "Has Duration",
              tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff." },
            { isHeader = true, label = "Show", rightLabel = "Hide" },
            { key = "nonplayer", label = "Non-Player Auras", dual = true, showLockedFn = AllOn,
              tooltip = "Debuffs not caused by any player or player pet (this is what shows most pve debuffs)." },
            { key = "priority", label = "Important", dual = true, showLockedFn = AllOn,
              tooltip = "Debuffs Blizzard flags as priority for raid frames." },
            { key = "cc", label = "Crowd Control", dual = true, showLockedFn = AllOn,
              tooltip = "Loss-of-control debuffs. When shown, these lead the row and carry the CC glow." },
            { key = "boss", label = "Boss Debuffs", dual = true, showLockedFn = AllOn,
              tooltip = "Debuffs applied by boss encounters." },
            { key = "role", label = "Role Debuffs", dual = true, showLockedFn = AllOn,
              tooltip = "Debuffs flagged as relevant to your role." },
            { key = "raid", label = "Raid", dual = true, showLockedFn = AllOn,
              tooltip = "Blizzard's curated raid-frame debuff set." },
            { key = "raidcombat", label = "Raid In Combat", dual = true, showLockedFn = AllOn,
              tooltip = "The stricter in-combat subset of the raid set." },
            -- Two flavors of ONE dispel category (mutually exclusive across rows
            -- AND lanes -- either lane's check flips the mode, the widget
            -- refreshes both rows):
            { key = "dispel_you", label = "Dispellable By You", dual = true, showLockedFn = AllOn,
              tooltip = "Debuffs you can dispel." },
            { key = "dispel_typed", label = "Dispels", dual = true, showLockedFn = AllOn,
              tooltip = "Any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it." },
        }
        -- Hovering a dimmed Show box explains the dim (the lane is inert
        -- while All Debuffs already shows everything). Has Duration is an
        -- AND-modifier, not a mode: it never locks the lane.
        do
            local lockedTip = L("All Debuffs is selected, so every debuff already shows. Use the red Hide box to exclude these instead.")
            for i = 1, #FILTER_ITEMS do
                if FILTER_ITEMS[i].dual then
                    FILTER_ITEMS[i].showLockedTooltip = lockedTip
                end
            end
        end
        local function NegHas(cat)
            return dm.neg ~= nil and dm.neg[cat] == true
        end
        local function SetNeg(cat, v)
            if v then
                dm.neg = dm.neg or {}
                dm.neg[cat] = true
            elseif dm.neg then
                dm.neg[cat] = nil
                if not next(dm.neg) then dm.neg = nil end
            end
        end
        -- One of the grid's content sources (with All Debuffs and enabled
        -- claiming tiles -- see DmHasContent).
        local function AnyShowCat()
            return dm.boss == true or dm.role == true or dm.priority == true
                or dm.cc == true or dm.raid == true or dm.raidcombat == true
                or dm.dispel == true or dm.nonplayer == true
        end
        -- Empty selections are LEGAL here (user directive 2026-08-16, the
        -- same reversal PAB got): any content source can be unchecked,
        -- including the last one, and EllesmereUI.AttachEmptyFilterWarn owns
        -- the loud feedback (red dropdown border + persistent bubble +
        -- close-pulse) while the grid displays nothing. Enabled tiles with
        -- claimed categories still render those categories under an empty
        -- base selection (EffectiveState forces eff[cat] on for claims and
        -- fx routing), so a claims-only grid displays debuffs and must not
        -- warn -- the same rule that keeps fx-forced PAB bars silent.
        local warnClosed
        local function DmHasContent()
            if AllOn() or dm.hasDuration == true or AnyShowCat() then return true end
            local tiles = ns.DM_ActiveTiles and ns.DM_ActiveTiles()
            if tiles then
                for i = 1, #tiles do
                    local t = tiles[i]
                    if t.enabled then
                        if t.all == true or t.hasDuration == true then return true end
                        if t.claim then
                            for _, on in pairs(t.claim) do
                                if on then return true end
                            end
                        end
                    end
                end
            end
            return false
        end
        local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 190, rgn:GetFrameLevel() + 2,
            FILTER_ITEMS,
            function(k, neg)
                if k == DM_ALL_KEY then return AllOn() end
                if k == DM_DUR_KEY then return dm.hasDuration == true end
                if k == "dispel_you" then
                    if neg then return NegHas("dispel") and dm.dispelMode ~= "typed" end
                    return dm.dispel == true and dm.dispelMode ~= "typed"
                elseif k == "dispel_typed" then
                    if neg then return NegHas("dispel") and dm.dispelMode == "typed" end
                    return dm.dispel == true and dm.dispelMode == "typed"
                end
                if neg then return NegHas(k) end
                return dm[k] == true
            end,
            function(k, v, neg)
                if k == DM_ALL_KEY then
                    -- Lanes persist across mode flips (the hide lane subtracts in
                    -- both modes; the show lane goes dormant while All is on).
                    dm.all = v and true or false
                    DmApply()
                    EllesmereUI:RefreshPage()
                    return
                end
                if k == DM_DUR_KEY then
                    -- AND-modifier: combines with All Debuffs or any show-lane
                    -- selection; checked alone it acts as the timed catch-all.
                    dm.hasDuration = v or nil
                    DmApply()
                    EllesmereUI:RefreshPage()
                    return
                end
                if k == "dispel_you" or k == "dispel_typed" then
                    -- ONE dispel category, one global flavor: any checked lane owns
                    -- both the lane and dm.dispelMode; checking one lane/flavor
                    -- clears the other lane.
                    if neg then
                        SetNeg("dispel", v and true or false)
                        if v then
                            dm.dispel = nil
                            dm.dispelMode = (k == "dispel_typed") and "typed" or "you"
                        end
                    else
                        dm.dispel = v and true or nil
                        if v then
                            SetNeg("dispel", false)
                            dm.dispelMode = (k == "dispel_typed") and "typed" or "you"
                        end
                    end
                    DmApply()
                    -- Non-force: re-evaluates the empty-selection warning (and
                    -- any other widget refreshers) without closing the menu.
                    EllesmereUI:RefreshPage()
                    return
                end
                -- Two-lane category write: checking one lane clears the other.
                if neg then
                    SetNeg(k, v and true or false)
                    if v then dm[k] = nil end
                else
                    dm[k] = v and true or nil
                    if v then SetNeg(k, false) end
                end
                DmApply()
                -- Non-force: re-evaluates the empty-selection warning (and
                -- any other widget refreshers) without closing the menu.
                EllesmereUI:RefreshPage()
            end,
            nil, 12, nil, nil, function()
                if warnClosed then warnClosed() end
            end)
        PPl.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        if cbRefresh then EllesmereUI.RegisterWidgetRefresh(cbRefresh) end
        warnClosed = EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD,
            L("You are displaying NO debuffs at all."), DmHasContent)
    end

    _, hh = W:SectionHeader(frame, "CORE", sy); sy = sy - hh

    -- Row: Size (+ Icon Zoom cog) | Max Debuffs
    local sizeRow
    sizeRow, hh = W:DualRow(frame, sy,
        { type = "slider", text = "Size", min = 10, max = 40, step = 1, trackWidth = 120,
          getValue = function() return p.debuffSize or 18 end,
          setValue = function(v) p.debuffSize = v; DmApply() end },
        { type = "slider", text = "Max Debuffs", min = 1, max = 10, step = 1, trackWidth = 120,
          getValue = function() return p.debuffCap or 3 end,
          setValue = function(v) p.debuffCap = v; DmApply() end }); sy = sy - hh
    do
        local rgn = sizeRow._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Icon Zoom",
            rows = {
                { type = "slider", label = "Zoom", min = 0, max = 0.20, step = 0.01,
                  get = function() return p.debuffIconZoom or 0.08 end,
                  set = function(v) p.debuffIconZoom = v; DmApply() end },
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

    -- Row: Position (+ offsets cog) | Growth Direction
    local posRow2
    posRow2, hh = W:DualRow(frame, sy,
        { type = "dropdown", text = "Position", values = POS_VALUES, order = POS_ORDER,
          getValue = function() return p.debuffPosition or "bottomright" end,
          setValue = function(v)
              p.debuffPosition = v
              p.debuffGrowDirection = DmDefaultGrow(v)
              DmApply()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Growth Direction", values = GROW_VALUES, order = GROW_ORDER,
          getValue = function() return p.debuffGrowDirection or "LEFT" end,
          setValue = function(v) p.debuffGrowDirection = v; DmApply() end }); sy = sy - hh
    do
        local rgn = posRow2._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Position Offset",
            rows = {
                { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                  get = function() return p.debuffOffsetX or 0 end,
                  set = function(v) p.debuffOffsetX = v; DmApply() end },
                { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                  get = function() return p.debuffOffsetY or 0 end,
                  set = function(v) p.debuffOffsetY = v; DmApply() end },
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

    -- Row: Icons Per Row (end of CORE). The key predates this UI (its row
    -- died with the Auras tab): >= 2 wraps -- rows for horizontal growth,
    -- COLUMNS for vertical (12.1 flow axis) -- with the stored
    -- debuffWrapDirection convention deciding the stack side.
    _, hh = W:DualRow(frame, sy,
        { type = "slider", text = "Icons Per Row", min = 0, max = 20, step = 1, trackWidth = 120,
          tooltip = "Wraps into a new row (or column for vertical growth) after this many icons; below 2 keeps one continuous run.",
          getValue = function() return p.debuffPerRow or 5 end,
          setValue = function(v) p.debuffPerRow = v; DmApply() end },
        { type = "label", text = "" }); sy = sy - hh

    -- Display: the legacy debuff style keys (retired Auras tab), which the
    -- base grid and icon tiles read directly. CC glow settings are
    -- deliberately NOT surfaced here (separate follow-up). Party frames
    -- sync from these keys unless an old party override exists.
    _, hh = W:SectionHeader(frame, "DISPLAY", sy); sy = sy - hh

    -- Row: Border (+ swatch) | Spacing
    local bRow
    bRow, hh = W:DualRow(frame, sy,
        { type = "slider", text = "Border", min = 0, max = 4, step = 1, trackWidth = 120,
          getValue = function() return p.debuffBorderSize or 1 end,
          setValue = function(v) p.debuffBorderSize = v; DmApply() end },
        { type = "slider", pixel = true, text = "Spacing", min = -1, max = 10, step = 1, trackWidth = 120,
          getValue = function() return p.debuffSpacing or 1 end,
          setValue = function(v) p.debuffSpacing = v; DmApply() end }); sy = sy - hh
    do
        local rgn = bRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, bRow:GetFrameLevel() + 3,
            function()
                local c = p.debuffBorderColor or { r = 0, g = 0, b = 0 }
                return c.r or 0, c.g or 0, c.b or 0, 1
            end,
            function(r, g, b)
                p.debuffBorderColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
    end

    -- Row: Show Duration Text (+ swatch + cog) | Show Stacks (+ swatch + cog)
    local dtRow
    dtRow, hh = W:DualRow(frame, sy,
        { type = "toggle", text = "Show Duration Text",
          getValue = function() return p.debuffShowDurText and true or false end,
          setValue = function(v) p.debuffShowDurText = v; DmApply() end },
        { type = "toggle", text = "Show Stacks",
          getValue = function() return p.debuffShowStacks ~= false end,
          setValue = function(v) p.debuffShowStacks = v; DmApply() end }); sy = sy - hh
    do
        local rgn = dtRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, dtRow:GetFrameLevel() + 3,
            function()
                local c = p.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                return c.r or 1, c.g or 1, c.b or 1, 1
            end,
            function(r, g, b)
                p.debuffDurTextColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch

        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Duration Text",
            rows = {
                { type = "slider", label = "Text Size", min = 6, max = 26, step = 1,
                  get = function() return p.debuffDurTextSize or 10 end,
                  set = function(v) p.debuffDurTextSize = v; DmApply() end },
                { type = "slider", label = "Offset X", min = -20, max = 20, step = 1,
                  get = function() return p.debuffDurTextOffsetX or 0 end,
                  set = function(v) p.debuffDurTextOffsetX = v; DmApply() end },
                { type = "slider", label = "Offset Y", min = -20, max = 20, step = 1,
                  get = function() return p.debuffDurTextOffsetY or 0 end,
                  set = function(v) p.debuffDurTextOffsetY = v; DmApply() end },
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
    do
        local rgn = dtRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, dtRow:GetFrameLevel() + 3,
            function()
                local c = p.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                return c.r or 1, c.g or 1, c.b or 1, 1
            end,
            function(r, g, b)
                p.debuffStacksTextColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch

        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Stacks Text",
            rows = {
                { type = "slider", label = "Text Size", min = 6, max = 26, step = 1,
                  get = function() return p.debuffStacksTextSize or 11 end,
                  set = function(v) p.debuffStacksTextSize = v; DmApply() end },
                { type = "slider", label = "Offset X", min = -20, max = 20, step = 1,
                  get = function() return p.debuffStacksOffsetX or 0 end,
                  set = function(v) p.debuffStacksOffsetX = v; DmApply() end },
                { type = "slider", label = "Offset Y", min = -20, max = 20, step = 1,
                  get = function() return p.debuffStacksOffsetY or 0 end,
                  set = function(v) p.debuffStacksOffsetY = v; DmApply() end },
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

    -- Row: Tooltips | Show Duration Swipe. The swipe toggle was not in
    -- the requested layout but silently orphaning a stored setting is
    -- worse -- parked here pending a call on removing it outright.
    local tipRow
    tipRow, hh = W:DualRow(frame, sy,
        { type = "dropdown", text = "Tooltips", values = TIP_VALUES, order = TIP_ORDER,
          getValue = function() return TipModeKey(p.debuffHideTooltips) end,
          setValue = function(k)
              p.debuffHideTooltips = TipModeStore(k); DmApply()
              EllesmereUI:RefreshPage()  -- update the Use Modifier cog disabled state
          end },
        { type = "toggle", text = "Show Duration Swipe",
          getValue = function() return p.debuffShowSwipe ~= false end,
          setValue = function(v) p.debuffShowSwipe = v; DmApply() end }); sy = sy - hh

    -- "Use Modifier" cog on Tooltips (left region): picks the key for the
    -- "Shown on Modifier" mode, so it is only available there. While that
    -- mode is selected with the key still at None, the cog hover warns that
    -- tooltips will always show (the runtime degrades to plain Shown).
    do
        local leftRgn = tipRow._leftRegion
        local function tipOff()
            return TipModeKey(p.debuffHideTooltips) ~= "modifier"
        end
        local _, tipModShow = EllesmereUI.BuildCogPopup({
            title = "Tooltips",
            rows = {
                { type = "dropdown", label = "Use Modifier",
                  values = { none = "None", shift = "Shift", control = "Control", alt = "Alt" },
                  order = { "none", "shift", "control", "alt" },
                  get = function() return p.debuffTooltipModifier or "none" end,
                  set = function(v)
                      p.debuffTooltipModifier = v; DmApply()
                      EllesmereUI:RefreshPage()  -- clear/raise the no-key warning bubble
                  end },
            },
        })
        local tipModBtn = CreateFrame("Button", nil, leftRgn)
        tipModBtn:SetSize(26, 26)
        tipModBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = tipModBtn
        tipModBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        tipModBtn:SetAlpha(tipOff() and 0.15 or 0.4)
        local tipModTex = tipModBtn:CreateTexture(nil, "OVERLAY")
        tipModTex:SetAllPoints()
        tipModTex:SetTexture(EllesmereUI.COGS_ICON)
        tipModBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            if (p.debuffTooltipModifier or "none") == "none" then
                EllesmereUI.ShowWidgetTooltip(self,
                    "Select a modifier key here, or tooltips will always be shown")
            end
        end)
        tipModBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(tipOff() and 0.15 or 0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        tipModBtn:SetScript("OnClick", function(self) tipModShow(self) end)

        -- Blocking overlay + disabled tooltip while the mode is Hidden
        local tipModBlock = CreateFrame("Frame", nil, tipModBtn)
        tipModBlock:SetAllPoints()
        tipModBlock:SetFrameLevel(tipModBtn:GetFrameLevel() + 10)
        tipModBlock:EnableMouse(true)
        tipModBlock:SetScript("OnEnter", function()
            -- Whole sentence: DisabledTooltip passes "This option..." strings
            -- through verbatim (still localized).
            EllesmereUI.ShowWidgetTooltip(tipModBtn,
                EllesmereUI.DisabledTooltip("This option requires Tooltips to be set to Shown on Modifier"))
        end)
        tipModBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateTipModState()
            local off = tipOff()
            tipModBtn:SetAlpha(off and 0.15 or 0.4)
            if off then tipModBlock:Show() else tipModBlock:Hide() end
        end
        UpdateTipModState(); EllesmereUI.RegisterWidgetRefresh(UpdateTipModState)

        -- Persistent red bubble above the cog while Shown on Modifier is
        -- selected with no key picked (the standard empty-selection warning);
        -- the hover tooltip above keeps the explanation.
        EllesmereUI.AttachEmptyFilterWarn(leftRgn, tipModBtn, L("Select a Modifier"),
            function()
                return tipOff() or (p.debuffTooltipModifier or "none") ~= "none"
            end)
    end

    sy = BuildFxEffects(frame, sy, dm)
    return sy
end

local function BuildTileDetail(frame, fontPath, t)
    local W = EllesmereUI.Widgets
    if not W then return 0 end
    frame._showRowDivider = true
    local sy, hh = 0, 0

    local function TSet(key, v) t[key] = v; DmApply() end

    if t.type == "icons" or t.type == "square" then
        -- Grid tiles (Icon / Square): the Base Icons pane layout 1:1, with
        -- per-tile style values as VIEWS over the base debuff style keys
        -- (nil = inherit; getters show the effective value).
        local p = DmProfile() or {}
        local dm = DmTable() or {}
        local PP = EllesmereUI.PP or EllesmereUI.PanelPP
        local function TEff(key, baseKey, default)
            local v = t[key]
            if v == nil then v = p[baseKey] end
            if v == nil then v = default end
            return v
        end
        local function TBoolOn(key, baseKey) -- base default ON
            if t[key] ~= nil then return t[key] and true or false end
            return p[baseKey] ~= false
        end
        local function TBoolOff(key, baseKey) -- base default OFF
            if t[key] ~= nil then return t[key] and true or false end
            return p[baseKey] and true or false
        end

        _, hh = W:SectionHeader(frame, "ASSIGNED DEBUFFS", sy); sy = sy - hh

        local fRow
        fRow, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Filters",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            { type = "label", text = "" }); sy = sy - hh
        BuildTileFiltersDD(fRow._leftRegion, t, dm)

        _, hh = W:SectionHeader(frame, "CORE", sy); sy = sy - hh

        -- Row: Size (+ Icon Zoom cog) | Max Debuffs
        local sizeRow
        sizeRow, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Size", min = 10, max = 40, step = 1, trackWidth = 120,
              getValue = function() return t.size or 18 end,
              setValue = function(v) TSet("size", v) end },
            { type = "slider", text = "Max Debuffs", min = 1, max = 10, step = 1, trackWidth = 120,
              getValue = function() return t.cap or 3 end,
              setValue = function(v) TSet("cap", v) end }); sy = sy - hh
        do
            local rgn = sizeRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type = "slider", label = "Zoom", min = 0, max = 0.20, step = 0.01,
                      get = function() return TEff("iconZoom", "debuffIconZoom", 0.08) end,
                      set = function(v) TSet("iconZoom", v) end },
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

        -- Row: Position (+ offsets cog) | Growth Direction
        local posRow2
        posRow2, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Position", values = POS_VALUES, order = POS_ORDER,
              getValue = function() return t.position or "top" end,
              setValue = function(v)
                  t.growDirection = DmDefaultGrow(v)
                  TSet("position", v)
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Growth Direction", values = GROW_VALUES, order = GROW_ORDER,
              getValue = function() return t.growDirection or "CENTER" end,
              setValue = function(v) TSet("growDirection", v) end }); sy = sy - hh
        do
            local rgn = posRow2._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Position Offset",
                rows = {
                    { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                      get = function() return t.offsetX or 0 end,
                      set = function(v) TSet("offsetX", v) end },
                    { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                      get = function() return t.offsetY or 0 end,
                      set = function(v) TSet("offsetY", v) end },
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

        -- Row: Icons Per Row (end of CORE). Tile-local key, no base
        -- inheritance: >= 2 wraps the tile's run -- rows for horizontal
        -- growth, COLUMNS for vertical -- stacking away from the anchored
        -- edge (position rule).
        _, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Icons Per Row", min = 0, max = 20, step = 1, trackWidth = 120,
              tooltip = "Wraps into a new row (or column for vertical growth) after this many icons; below 2 keeps one continuous run.",
              getValue = function() return t.iconsPerRow or 0 end,
              setValue = function(v) TSet("iconsPerRow", v) end },
            { type = "label", text = "" }); sy = sy - hh

        _, hh = W:SectionHeader(frame, "DISPLAY", sy); sy = sy - hh

        -- Row: Border (+ swatch) | Spacing
        local bRow
        bRow, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Border", min = 0, max = 4, step = 1, trackWidth = 120,
              getValue = function() return TEff("borderSize", "debuffBorderSize", 1) end,
              setValue = function(v) TSet("borderSize", v) end },
            { type = "slider", pixel = true, text = "Spacing", min = -1, max = 10, step = 1, trackWidth = 120,
              getValue = function() return t.spacing or 1 end,
              setValue = function(v) TSet("spacing", v) end }); sy = sy - hh
        do
            local rgn = bRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, bRow:GetFrameLevel() + 3,
                function()
                    local c = t.borderColor or p.debuffBorderColor or { r = 0, g = 0, b = 0 }
                    return c.r or 0, c.g or 0, c.b or 0, 1
                end,
                function(r, g, b)
                    t.borderColor = { r = r, g = g, b = b }
                    DmApply()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end

        -- Row: Show Duration Text (+ swatch + cog) | Show Stacks (+ swatch + cog)
        local dtRow
        dtRow, hh = W:DualRow(frame, sy,
            { type = "toggle", text = "Show Duration Text",
              getValue = function() return TBoolOff("showDurText", "debuffShowDurText") end,
              setValue = function(v) TSet("showDurText", v and true or false) end },
            { type = "toggle", text = "Show Stacks",
              getValue = function() return TBoolOn("showStacks", "debuffShowStacks") end,
              setValue = function(v) TSet("showStacks", v and true or false) end }); sy = sy - hh
        do
            local rgn = dtRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, dtRow:GetFrameLevel() + 3,
                function()
                    local c = t.durTextColor or p.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                    return c.r or 1, c.g or 1, c.b or 1, 1
                end,
                function(r, g, b)
                    t.durTextColor = { r = r, g = g, b = b }
                    DmApply()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type = "slider", label = "Text Size", min = 6, max = 26, step = 1,
                      get = function() return TEff("durTextSize", "debuffDurTextSize", 10) end,
                      set = function(v) TSet("durTextSize", v) end },
                    { type = "slider", label = "Offset X", min = -20, max = 20, step = 1,
                      get = function() return TEff("durTextOffsetX", "debuffDurTextOffsetX", 0) end,
                      set = function(v) TSet("durTextOffsetX", v) end },
                    { type = "slider", label = "Offset Y", min = -20, max = 20, step = 1,
                      get = function() return TEff("durTextOffsetY", "debuffDurTextOffsetY", 0) end,
                      set = function(v) TSet("durTextOffsetY", v) end },
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
        do
            local rgn = dtRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, dtRow:GetFrameLevel() + 3,
                function()
                    local c = t.stacksTextColor or p.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                    return c.r or 1, c.g or 1, c.b or 1, 1
                end,
                function(r, g, b)
                    t.stacksTextColor = { r = r, g = g, b = b }
                    DmApply()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Stacks Text",
                rows = {
                    { type = "slider", label = "Text Size", min = 6, max = 26, step = 1,
                      get = function() return TEff("stacksTextSize", "debuffStacksTextSize", 11) end,
                      set = function(v) TSet("stacksTextSize", v) end },
                    { type = "slider", label = "Offset X", min = -20, max = 20, step = 1,
                      get = function() return TEff("stacksOffsetX", "debuffStacksOffsetX", 0) end,
                      set = function(v) TSet("stacksOffsetX", v) end },
                    { type = "slider", label = "Offset Y", min = -20, max = 20, step = 1,
                      get = function() return TEff("stacksOffsetY", "debuffStacksOffsetY", 0) end,
                      set = function(v) TSet("stacksOffsetY", v) end },
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

        -- Row: Tooltips | Show Duration Swipe (base pane parity)
        _, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Tooltips", values = TIP_VALUES, order = TIP_ORDER,
              getValue = function()
                  local v = t.hideTooltips
                  if v == nil then v = p.debuffHideTooltips end
                  return TipModeKey(v)
              end,
              setValue = function(k) TSet("hideTooltips", TipModeStore(k)) end },
            { type = "toggle", text = "Show Duration Swipe",
              getValue = function() return TBoolOn("showSwipe", "debuffShowSwipe") end,
              setValue = function(v) TSet("showSwipe", v and true or false) end }); sy = sy - hh

        -- Square only: the block color the flat squares render with.
        if t.type == "square" then
            _, hh = W:DualRow(frame, sy,
                { type = "colorpicker", text = "Color", hasAlpha = true,
                  getValue = function()
                      local c = t.color or { r = 1, g = 0.35, b = 0.35, a = 1 }
                      return c.r or 1, c.g or 0.35, c.b or 0.35, c.a or 1
                  end,
                  setValue = function(r, g, b, a)
                      t.color = { r = r, g = g, b = b, a = a or 1 }
                      DmApply()
                  end },
                { type = "label", text = "" }); sy = sy - hh
        end

        sy = BuildFxEffects(frame, sy, t)
        return sy
    end

    -- Effect tiles: checked filter categories + type-specific visuals.
    _, hh = W:SectionHeader(frame, "EFFECT", sy); sy = sy - hh
    local catRow
    catRow, hh = W:DualRow(frame, sy,
        { type = "dropdown", text = "Filters",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end },
        { type = "label", text = (t.type == "bar") and "" or "Color" }); sy = sy - hh
    BuildTileFiltersDD(catRow._leftRegion, t, DmTable() or {})
    if t.type == "glow" then
        -- Trio swatch (default / custom / class) -- the CDM pandemic-glow
        -- color pattern.
        local rgn = catRow._rightRegion
        local PPl = EllesmereUI.PP or EllesmereUI.PanelPP
        local customSwatch, defaultSwatch, classSwatch = EllesmereUI.BuildTrioColorSwatch(
            rgn, catRow:GetFrameLevel() + 3,
            {
                getMode = function() return t.glowColorMode or "default" end,
                setMode = function(m)
                    t.glowColorMode = m
                    DmApply()
                end,
                getCustomRGB = function()
                    local c = t.color
                    return (c and c.r) or 1, (c and c.g) or 0.78, (c and c.b) or 0.38
                end,
                setCustomRGB = function(r, g, b)
                    t.color = { r = r, g = g, b = b }
                    DmApply()
                end,
                hasClassColor = true,
                onChange = function() EllesmereUI:RefreshPage() end,
            })
        PPl.Point(classSwatch, "RIGHT", rgn, "RIGHT", -20, 0)
        PPl.Point(customSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
        PPl.Point(defaultSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        rgn._lastInline = defaultSwatch
    elseif t.type ~= "bar" then
        -- Health color rides a dedicated Opacity slider (BM parity), so
        -- its swatch has no alpha strip. (The bar's colors live in its
        -- DISPLAY section below, BM parity.)
        local rgn = catRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(rgn, catRow:GetFrameLevel() + 3,
            function()
                local c = t.color or { r = 1, g = 1, b = 1 }
                return c.r or 1, c.g or 1, c.b or 1, 1
            end,
            function(r, g, b)
                local c = t.color or {}
                c.r, c.g, c.b = r, g, b
                t.color = c
                DmApply()
            end, false, 20)
        -- Label slots have no _control: anchor to the region itself.
        swatch:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        rgn._lastInline = swatch
    end

    if t.type == "glow" then
        -- Frame Glow renders exactly one style: the animation-driven pixel
        -- march (the only look the forbidden slot subtree can run).
        _, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Speed", min = 1, max = 10, step = 1,
              getValue = function() return t.glowSpeed or 4 end,
              setValue = function(v) TSet("glowSpeed", v) end },
            { type = "slider", text = "Lines", min = 4, max = 16, step = 1,
              getValue = function() return t.glowLines or 8 end,
              setValue = function(v) TSet("glowLines", v) end }); sy = sy - hh
        _, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Thickness", min = 1, max = 4, step = 1,
              getValue = function() return t.glowThickness or 2 end,
              setValue = function(v) TSet("glowThickness", v) end },
            { type = "label", text = "" }); sy = sy - hh
    elseif t.type == "bar" then
        -- BM bar indicator CORE + DISPLAY 1:1 (minus Own Only and the
        -- 12.1-removed Max Duration / Threshold).
        local isVert = (t.orientation or "HORIZONTAL") == "VERTICAL"
        _, hh = W:SectionHeader(frame, "CORE", sy); sy = sy - hh
        local coreRow
        coreRow, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Orientation",
              values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
              order = { "HORIZONTAL", "VERTICAL" },
              getValue = function() return t.orientation or "HORIZONTAL" end,
              -- Full rebuild: the Width/Height + Full toggle labels flip
              -- with the orientation.
              setValue = function(v) TSet("orientation", v); EllesmereUI:RefreshPage(true) end },
            { type = "dropdown", text = "Position", values = POS_VALUES, order = POS_ORDER,
              getValue = function() return t.position or "bottom" end,
              setValue = function(v) TSet("position", v) end }); sy = sy - hh
        do
            local rgn = coreRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Position Offset",
                rows = {
                    { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                      get = function() return t.offsetX or 0 end,
                      set = function(v) TSet("offsetX", v) end },
                    { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                      get = function() return t.offsetY or 0 end,
                      set = function(v) TSet("offsetY", v) end },
                    { type = "dropdown", label = "Frame Level",
                      values = { behindBorders = "Behind Borders", behindText = "Behind Text",
                                 medium = "Medium", high = "High", highest = "Highest" },
                      order = { "behindBorders", "behindText", "medium", "high", "highest" },
                      get = function() return t.frameLevel or "behindBorders" end,
                      set = function(v) TSet("frameLevel", v) end },
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
        _, hh = W:DualRow(frame, sy,
            { type = "toggle", text = "Reverse Fill",
              getValue = function() return t.reverseFill or false end,
              setValue = function(v) TSet("reverseFill", v and true or false) end },
            { type = "label", text = "" }); sy = sy - hh

        _, hh = W:SectionHeader(frame, "DISPLAY", sy); sy = sy - hh
        -- Width | Height: labels flip with orientation so each slot names
        -- the on-screen axis; each is disabled while its Full toggle is on.
        _, hh = W:DualRow(frame, sy,
            { type = "slider", text = isVert and "Height" or "Width", min = 5, max = 200, step = 1,
              disabled = function() return t.barFullWidth end,
              disabledTooltip = isVert and "Full Height Bar" or "Full Width Bar",
              requireState = "disabled",
              getValue = function() return t.width or 60 end,
              setValue = function(v) TSet("width", v) end },
            { type = "slider", text = isVert and "Width" or "Height", min = 1, max = 100, step = 1,
              disabled = function() return t.barFullHeight end,
              disabledTooltip = isVert and "Full Width Bar" or "Full Height Bar",
              requireState = "disabled",
              getValue = function() return t.height or 5 end,
              setValue = function(v) TSet("height", v) end }); sy = sy - hh
        _, hh = W:DualRow(frame, sy,
            { type = "toggle", text = isVert and "Full Height Bar" or "Full Width Bar",
              getValue = function() return t.barFullWidth or false end,
              setValue = function(v) TSet("barFullWidth", v and true or false); EllesmereUI:RefreshPage() end },
            { type = "toggle", text = isVert and "Full Width Bar" or "Full Height Bar",
              getValue = function() return t.barFullHeight or false end,
              setValue = function(v) TSet("barFullHeight", v and true or false); EllesmereUI:RefreshPage() end }); sy = sy - hh
        -- Color | Background: opacity sliders + inline swatches.
        local barBgRow
        barBgRow, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Color", min = 0, max = 100, step = 1, trackWidth = 120,
              getValue = function() return t.barColorOpacity or 100 end,
              setValue = function(v) TSet("barColorOpacity", v) end },
            { type = "slider", text = "Background", min = 0, max = 100, step = 1, trackWidth = 120,
              getValue = function() return t.barBgOpacity or 50 end,
              setValue = function(v) TSet("barBgOpacity", v) end }); sy = sy - hh
        do
            local rgn = barBgRow._leftRegion
            local colorSwatch = EllesmereUI.BuildColorSwatch(
                rgn, barBgRow:GetFrameLevel() + 3,
                function()
                    local c = t.color or { r = 0.25, g = 0.8, b = 0.45 }
                    return c.r or 0.25, c.g or 0.8, c.b or 0.45, 1
                end,
                function(r, g, b)
                    t.color = { r = r, g = g, b = b }
                    DmApply()
                end, false, 20)
            colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = colorSwatch
        end
        do
            local rgn = barBgRow._rightRegion
            local bgSwatch = EllesmereUI.BuildColorSwatch(
                rgn, barBgRow:GetFrameLevel() + 3,
                function()
                    local c = t.barBgColor or { r = 0, g = 0, b = 0 }
                    return c.r or 0, c.g or 0, c.b or 0, 1
                end,
                function(r, g, b)
                    t.barBgColor = { r = r, g = g, b = b }
                    DmApply()
                end, false, 20)
            bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSwatch
        end
    elseif t.type == "healthcolor" then
        _, hh = W:DualRow(frame, sy,
            { type = "slider", text = "Opacity", min = 5, max = 100, step = 1,
              getValue = function() return t.opacity or 45 end,
              setValue = function(v) TSet("opacity", v) end },
            { type = "label", text = "" }); sy = sy - hh
    end
    return sy
end

-------------------------------------------------------------------------------
-- DM preview renderer (BM preview parity): the base debuff grid plus every enabled
-- tile's visual, drawn on the replica frame. The selected element renders at full
-- alpha, everything else dims to 0.5 (never hidden); frame-wide effects (glow / health
-- color) show while their tile is selected or when the eyeball forces everything
-- visible. Clicking any element selects its tile for editing.
-------------------------------------------------------------------------------
-- Sample debuff spells for preview icons + tile faces (ancient, stable ids).
local SAMPLE_DEBUFF_SPELLS = { 589, 118, 2818, 702 }
local function SampleDebuffTexture(i)
    local id = SAMPLE_DEBUFF_SPELLS[((i - 1) % #SAMPLE_DEBUFF_SPELLS) + 1]
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    return tex or 136243
end
local CAT_SAMPLE_SPELL = { cc = 118, dispel = 2818 }
local function TileFaceTexture(t)
    local id
    if t.claim then
        for _, cat in ipairs(CAT_ORDER) do
            if t.claim[cat] then id = CAT_SAMPLE_SPELL[cat] or 589 break end
        end
    end
    id = id or 589
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    return tex or 136243
end

local function DmPvEnter(self)
    if not self._dmSel then return end
    if self._hoverBdr then
        local lPP = EllesmereUI.PanelPP or EllesmereUI.PP
        if lPP then
            local ac = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            lPP.UpdateBorder(self._hoverBdr, 2, ac.r, ac.g, ac.b, 1)
            self._hoverBdr:Show()
        end
    end
end

local function DmPvLeave(self)
    if self._hoverBdr then self._hoverBdr:Hide() end
end

local function DmPvClick(self)
    if not self._dmSel then return end
    local id = self._dmSel
    -- An id outside the edited bucket belongs to an INHERITED group tile
    -- (concrete spec views union them into the preview): select its
    -- read-only sidebar row instead of the (absent) own tile. The base
    -- grid is an All Specs row, inherited in every concrete spec view.
    if id == "base" then
        if dmSpecSel ~= "allspecs" and ns.BM_InheritedGroupsFor
            and ns.BM_InheritedGroupsFor(dmSpecSel) then
            dmInhSel = { group = "allspecs", id = "base" }
            EllesmereUI:RefreshPage(true)
            return
        end
    else
        local own = (ns.DM_BucketTiles and ns.DM_BucketTiles(dmSpecSel)) or {}
        local inOwn = false
        for i = 1, #own do
            if own[i].id == id then inOwn = true break end
        end
        if not inOwn then
            local inhG = ns.BM_InheritedGroupsFor and ns.BM_InheritedGroupsFor(dmSpecSel)
            if inhG then
                for gi = 1, #inhG do
                    local gl = ns.DM_BucketTiles and ns.DM_BucketTiles(inhG[gi])
                    for i = 1, #(gl or {}) do
                        if gl[i].id == id then
                            dmInhSel = { group = inhG[gi], id = id }
                            EllesmereUI:RefreshPage(true)
                            return
                        end
                    end
                end
            end
        end
    end
    dmSel = id
    dmInhSel = nil
    EllesmereUI:RefreshPage(true)
end

function ns.DMP_RefreshPreview()
    local pv = ns._dmPreviewFrame
    if not (pv and pv._health and pv:IsShown()) then return end
    local p = DmProfile()
    if not p then return end
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local fontPath = pv._dmFontPath
        or (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames"))
        or "Fonts\\FRIZQT__.TTF"
    local health = pv._health
    local host = (ns.RF_AnchorHost and ns.RF_AnchorHost(health, p)) or health
    local allVis = ns._dmAllVisible
    -- The EDITED view's tiles: inherited group tiles first (concrete spec
    -- views only, that spec's per-spec disables applied), then the bucket's
    -- own list -- the preview mirrors what that spec renders.
    local tiles = {}
    do
        local inhG = ns.BM_InheritedGroupsFor and ns.BM_InheritedGroupsFor(dmSpecSel)
        if inhG then
            for gi = 1, #inhG do
                local gl = ns.DM_BucketTiles and ns.DM_BucketTiles(inhG[gi])
                if gl then
                    for i = 1, #gl do
                        local t = gl[i]
                        if not (ns.DM_InhDisabled and ns.DM_InhDisabled(dmSpecSel, t.id)) then
                            tiles[#tiles + 1] = t
                        end
                    end
                end
            end
        end
        local own = (ns.DM_BucketTiles and ns.DM_BucketTiles(dmSpecSel)) or {}
        for i = 1, #own do tiles[#tiles + 1] = own[i] end
    end
    local Glows = EllesmereUI.Glows

    -- Reset pools
    local icons = pv._dmIconPool
    if not icons then icons = {}; pv._dmIconPool = icons end
    local shapes = pv._dmShapePool
    if not shapes then shapes = {}; pv._dmShapePool = shapes end
    for i = 1, #icons do
        local fr = icons[i]
        if fr._cooldown then fr._cooldown:SetCooldown(0, 0); fr._cooldown:Hide() end
        if fr._hoverBdr then fr._hoverBdr:Hide() end
        fr._dmSel = nil
        fr:Hide()
    end
    for i = 1, #shapes do
        local fr = shapes[i]
        if fr._hoverBdr then fr._hoverBdr:Hide() end
        fr._dmSel = nil
        fr:Hide()
    end
    if pv._dmHC then pv._dmHC:Hide() end
    if pv._dmGlow then
        if Glows then
            if Glows.StopAnimatedAnts then Glows.StopAnimatedAnts(pv._dmGlow) end
            if pv._dmGlow._euiGlowActive and Glows.StopGlow then Glows.StopGlow(pv._dmGlow) end
        end
        pv._dmGlow:Hide()
    end

    local iIdx, sIdx = 0, 0
    local function GetIcon()
        iIdx = iIdx + 1
        local fr = icons[iIdx]
        if not fr then
            fr = CreateFrame("Frame", nil, health)
            -- Live parity: aura icons render in the aura band (frame +
            -- LVL_AURA = 13), above the +8 border and the +12 text band
            -- (matches the BM preview pool and live frames).
            fr:SetFrameLevel(pv:GetFrameLevel() + (ns.LVL_AURA or 13))
            local tex = fr:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            fr._tex = tex
            local cd = CreateFrame("Cooldown", nil, fr, "CooldownFrameTemplate")
            cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetReverse(true)
            cd:SetSwipeColor(0, 0, 0, 0.6); cd:SetHideCountdownNumbers(true)
            cd:Hide()
            fr._cooldown = cd
            if PP then
                local b = CreateFrame("Frame", nil, fr)
                b:SetAllPoints(); b:SetFrameLevel(fr:GetFrameLevel() + 1)
                PP.CreateBorder(b, 0, 0, 0, 1, 1)
                fr._borderFrame = b
                local hb = CreateFrame("Frame", nil, fr)
                hb:SetAllPoints(); hb:SetFrameLevel(fr:GetFrameLevel() + 8)
                hb:EnableMouse(false)
                PP.CreateBorder(hb, 0, 0, 0, 0, 2)
                hb:Hide()
                fr._hoverBdr = hb
            end
            local tc = CreateFrame("Frame", nil, fr)
            tc:SetAllPoints(); tc:SetFrameLevel(fr:GetFrameLevel() + 5)
            fr._count = tc:CreateFontString(nil, "OVERLAY")
            fr:EnableMouse(true)
            fr:SetScript("OnEnter", DmPvEnter)
            fr:SetScript("OnLeave", DmPvLeave)
            fr:SetScript("OnMouseUp", DmPvClick)
            icons[iIdx] = fr
        end
        return fr
    end
    local function GetShape()
        sIdx = sIdx + 1
        local fr = shapes[sIdx]
        if not fr then
            fr = CreateFrame("Frame", nil, health)
            -- Bars render in the aura band like live (BM bars ride button + LVL_AURA).
            fr:SetFrameLevel(pv:GetFrameLevel() + (ns.LVL_AURA or 13))
            local bgTex = fr:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            fr._bgTex = bgTex
            local tex = fr:CreateTexture(nil, "ARTWORK")
            fr._tex = tex
            if PP then
                local hb = CreateFrame("Frame", nil, fr)
                hb:SetAllPoints(); hb:SetFrameLevel(fr:GetFrameLevel() + 8)
                hb:EnableMouse(false)
                PP.CreateBorder(hb, 0, 0, 0, 0, 2)
                hb:Hide()
                fr._hoverBdr = hb
            end
            fr:EnableMouse(true)
            fr:SetScript("OnEnter", DmPvEnter)
            fr:SetScript("OnLeave", DmPvLeave)
            fr:SetScript("OnMouseUp", DmPvClick)
            shapes[sIdx] = fr
        end
        return fr
    end

    -- One icon run (the base grid or an icon-container tile). Base style
    -- (zoom/border/swipe/duration/stacks) applies to both, matching the
    -- live renderer where icon tiles inherit the base debuff style.
    local function RenderRun(cfg)
        if cfg.count <= 0 then return end
        local anchor = string.upper(cfg.pos or "center")
        local sz = cfg.size or 18
        local gap = cfg.spacing or 1
        local dir = cfg.grow or "LEFT"
        local cursor = 0
        local selfPoint = anchor
        -- Grid wrap preview: >= 2 wraps lines exactly like live (base rows
        -- follow debuffWrapDirection, tiles the anchored-edge rule -- both
        -- arrive here as cfg.wrapV/cfg.wrapH from the caller).
        local per = cfg.perRow or 0
        if per < 2 then per = 0 end
        if dir == "CENTER" then
            -- Live parity: CENTER growth centers the run ON the position point (the
            -- base grid pins the container's row-edge midpoint at the corner, tiles pin
            -- the container's center -- both x-centered on it). Anchoring each icon by
            -- the pos corner would skew the run by that corner's own x-alignment (half
            -- an icon for center-x points, a full icon for right-x corners), so CENTER
            -- runs anchor icons by an explicit
            -- self-point instead: x = symmetric icon-center offsets, y =
            -- the caller's vertical seat (cfg.vAlign -- tiles sit flush
            -- with the anchored edge, base rows hang off the point in the
            -- wrap direction).
            selfPoint = cfg.vAlign or "CENTER"
            local lineN = cfg.count
            if per > 0 and per < lineN then lineN = per end
            cursor = -((lineN - 1) * (sz + gap)) / 2
        end
        local lineStart = cursor
        for i = 1, cfg.count do
            local fr = GetIcon()
            fr._dmSel = cfg.selKey
            fr:SetSize(sz, sz)
            fr:ClearAllPoints()
            local lineOff = 0
            if per > 0 then
                if i > 1 and (i - 1) % per == 0 then cursor = lineStart end
                lineOff = math.floor((i - 1) / per) * (sz + gap)
            end
            local gx, gy = 0, 0
            if dir == "RIGHT" or dir == "CENTER" then
                gx = cursor; cursor = cursor + sz + gap
                gy = (cfg.wrapV == "UP") and lineOff or -lineOff
            elseif dir == "LEFT" then
                gx = -cursor; cursor = cursor + sz + gap
                gy = (cfg.wrapV == "UP") and lineOff or -lineOff
            elseif dir == "DOWN" then
                gy = -cursor; cursor = cursor + sz + gap
                gx = (cfg.wrapH == "LEFT") and -lineOff or lineOff
            elseif dir == "UP" then
                gy = cursor; cursor = cursor + sz + gap
                gx = (cfg.wrapH == "LEFT") and -lineOff or lineOff
            end
            fr:SetPoint(selfPoint, host, anchor, (cfg.offX or 0) + gx, (cfg.offY or 0) + gy)
            if cfg.color then
                -- Square grid tiles: flat color blocks instead of icons.
                fr._tex:SetColorTexture(cfg.color.r or 1, cfg.color.g or 0.35,
                    cfg.color.b or 0.35, cfg.color.a or 1)
            else
                fr._tex:SetTexture(SampleDebuffTexture(i))
                local z = p.debuffIconZoom or 0.08
                fr._tex:SetTexCoord(z, 1 - z, z, 1 - z)
            end
            fr:SetAlpha(cfg.alpha)
            if fr._borderFrame and PP then
                local bsz = p.debuffBorderSize or 1
                if bsz > 0 then
                    local bc = p.debuffBorderColor or { r = 0, g = 0, b = 0 }
                    PP.UpdateBorder(fr._borderFrame, bsz, bc.r or 0, bc.g or 0, bc.b or 0, 1)
                    fr._borderFrame:Show()
                else
                    fr._borderFrame:Hide()
                end
            end
            local cd = fr._cooldown
            if cd then
                local wantSwipe = p.debuffShowSwipe ~= false
                local wantDurText = p.debuffShowDurText and true or false
                if wantSwipe or wantDurText then
                    -- Randomized FROZEN sweep: stable per-slot fraction on an hour-long
                    -- cooldown, so the preview shows varied mid-flight states without
                    -- visibly animating (same pattern as the Buff Manager preview). The
                    -- native countdown text would read the frozen hour, so it stays
                    -- hidden; duration text is a static seeded number on a manual
                    -- FontString instead, exactly like the BM preview.
                    local seed = GetPvCDSeed(i)
                    local dur = 3600
                    cd:SetCooldown(GetTime() - dur * (1 - seed), dur)
                    cd:SetDrawSwipe(wantSwipe)
                    cd:SetHideCountdownNumbers(true)
                    cd:Show()
                    if not fr._pvDurText then
                        fr._pvDurText = cd:CreateFontString(nil, "OVERLAY")
                    end
                    if wantDurText then
                        local dt = fr._pvDurText
                        local dtc = p.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                        EllesmereUI.ApplyIconTextFont(dt, fontPath, p.debuffDurTextSize or 10, "raidFrames")
                        dt:SetTextColor(dtc.r or 1, dtc.g or 1, dtc.b or 1)
                        dt:ClearAllPoints()
                        dt:SetPoint("CENTER", fr, "CENTER",
                            p.debuffDurTextOffsetX or 0, p.debuffDurTextOffsetY or 0)
                        dt:SetText(tostring(math.floor(3 + seed * 17)))
                        dt:Show()
                    else
                        fr._pvDurText:Hide()
                    end
                else
                    cd:Hide()
                    if fr._pvDurText then fr._pvDurText:Hide() end
                end
            end
            if fr._count then
                if p.debuffShowStacks ~= false then
                    local sc = p.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                    EllesmereUI.ApplyIconTextFont(fr._count, fontPath, p.debuffStacksTextSize or 11, "raidFrames")
                    fr._count:SetTextColor(sc.r or 1, sc.g or 1, sc.b or 1)
                    fr._count:ClearAllPoints()
                    fr._count:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT",
                        p.debuffStacksOffsetX or -1, p.debuffStacksOffsetY or 2)
                    fr._count:SetText("3")
                else
                    -- Only the stacks-on branch ever fonts this FontString: a
                    -- bare SetText on a fontless one spams "Font not set"
                    -- (field report 2026-08-16, 122x with stacks disabled).
                    -- Fonted = a previous stacks-on render left text to clear.
                    if fr._count:GetFont() then fr._count:SetText("") end
                end
            end
            fr:Show()
        end
    end

    -- Base grid (BM icon-cap parity: selected 4, unselected 2, dimmed 0.5).
    -- An All Specs indicator: drawn in the All Specs view and in concrete
    -- spec views that have not switched it off; group views omit it like
    -- every other All Specs row.
    local baseShown
    if dmSpecSel == "allspecs" then
        baseShown = true
    elseif ns.BM_InheritedGroupsFor and ns.BM_InheritedGroupsFor(dmSpecSel) then
        baseShown = not (ns.DM_BaseDisabled and ns.DM_BaseDisabled(dmSpecSel))
    end
    if baseShown then
        local sel = (dmSel == "base" and not dmInhSel)
            or (dmInhSel and dmInhSel.id == "base") or false
        local basePos = p.debuffPosition or "bottomright"
        local baseCenterEdge
        if (p.debuffGrowDirection or "LEFT") == "CENTER" then
            baseCenterEdge = (string.find(basePos, "top", 1, true) and "TOP")
                or (string.find(basePos, "bottom", 1, true) and "BOTTOM")
                or nil
        end
        RenderRun({
            selKey = "base",
            count = math.min(p.debuffCap or 3, (sel or allVis) and 4 or 2),
            size = p.debuffSize or 18,
            spacing = p.debuffSpacing or 1,
            pos = p.debuffPosition or "bottomright",
            grow = p.debuffGrowDirection or "LEFT",
            -- CENTER-growth vertical seat: live seats the edge from POSITION
            -- (ResolveFlowAnchor), falling back to wrap only when the position
            -- names neither side. Other growth modes keep wrap as the cross-axis.
            vAlign = baseCenterEdge or ((p.debuffWrapDirection == "DOWN") and "TOP" or "BOTTOM"),
            -- Base wrap: rows follow the stored debuffWrapDirection (the
            -- runtime's cross-axis source); vertical growth wraps columns
            -- by its LEFT/RIGHT reading.
            perRow = p.debuffPerRow or 5,
            wrapV = (baseCenterEdge and ((baseCenterEdge == "TOP") and "DOWN" or "UP"))
                or ((p.debuffWrapDirection == "DOWN") and "DOWN" or "UP"),
            wrapH = (p.debuffWrapDirection == "LEFT") and "LEFT" or "RIGHT",
            offX = p.debuffOffsetX or 0,
            offY = p.debuffOffsetY or 0,
            alpha = (sel or allVis) and 1 or 0.5,
        })
    end

    -- Tiles (enabled only, mirroring the BM preview's enabled gate)
    for ti = 1, #tiles do
        local t = tiles[ti]
        if t.enabled then
            -- Selected = the edited bucket's selection OR the inherited
            -- selection (ids are globally unique across buckets).
            local sel = (dmSel == t.id and not dmInhSel)
                or (dmInhSel and dmInhSel.id == t.id) or false
            local alpha = (sel or allVis) and 1 or 0.5
            if t.type == "icons" or t.type == "square" then
                RenderRun({
                    selKey = t.id,
                    count = math.min(t.cap or 3, (sel or allVis) and 4 or 2),
                    size = t.size or 18,
                    spacing = t.spacing or 1,
                    pos = t.position or "top",
                    grow = t.growDirection or "CENTER",
                    -- CENTER growth: vertical seat flush with the anchored
                    -- edge (AnchorTileContainer parity -- only the growth
                    -- axis centers on the position point).
                    vAlign = (string.find(t.position or "top", "top", 1, true) and "TOP")
                        or (string.find(t.position or "top", "bottom", 1, true) and "BOTTOM")
                        or "CENTER",
                    -- Tile wrap: away from the anchored edge (position rule,
                    -- matching AnchorTileContainer).
                    perRow = t.iconsPerRow or 0,
                    wrapV = string.find(t.position or "top", "bottom", 1, true) and "UP" or "DOWN",
                    wrapH = string.find(t.position or "top", "right", 1, true) and "LEFT" or "RIGHT",
                    offX = t.offsetX or 0,
                    offY = t.offsetY or 0,
                    alpha = alpha,
                    color = (t.type == "square")
                        and (t.color or { r = 1, g = 0.35, b = 0.35, a = 1 }) or nil,
                })
            elseif t.type == "bar" then
                local fr = GetShape()
                fr._dmSel = t.id
                -- BM_PlaceBar parity: fill-axis sliders + Full pins that
                -- swap screen edges when the bar is vertical.
                local w = t.width or 60
                local hh2 = t.height or 5
                local isVert = (t.orientation or "HORIZONTAL") == "VERTICAL"
                local anchor = string.upper(t.position or "bottom")
                local fullW, fullH
                if isVert then
                    fullW, fullH = t.barFullHeight, t.barFullWidth
                else
                    fullW, fullH = t.barFullWidth, t.barFullHeight
                end
                fr:ClearAllPoints()
                if fullW and fullH then
                    fr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                    fr:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
                elseif fullW then
                    local vEdge = (anchor:find("BOTTOM", 1, true) and "BOTTOM")
                        or (anchor:find("TOP", 1, true) and "TOP") or ""
                    local oy = t.offsetY or 0
                    fr:SetPoint(vEdge .. "LEFT", host, vEdge .. "LEFT", 0, oy)
                    fr:SetPoint(vEdge .. "RIGHT", host, vEdge .. "RIGHT", 0, oy)
                    fr:SetHeight(isVert and w or hh2)
                elseif fullH then
                    local hEdge = (anchor:find("RIGHT", 1, true) and "RIGHT")
                        or (anchor:find("LEFT", 1, true) and "LEFT") or ""
                    local ox = t.offsetX or 0
                    fr:SetPoint("TOP" .. hEdge, host, "TOP" .. hEdge, ox, 0)
                    fr:SetPoint("BOTTOM" .. hEdge, host, "BOTTOM" .. hEdge, ox, 0)
                    fr:SetWidth(isVert and hh2 or w)
                else
                    if isVert then fr:SetSize(hh2, w) else fr:SetSize(w, hh2) end
                    fr:SetPoint(anchor, host, anchor, t.offsetX or 0, t.offsetY or 0)
                end
                local c = t.color or { r = 0.25, g = 0.8, b = 0.45 }
                local bgc = t.barBgColor or { r = 0, g = 0, b = 0 }
                fr._bgTex:SetColorTexture(bgc.r or 0, bgc.g or 0, bgc.b or 0,
                    (t.barBgOpacity or 50) / 100)
                fr._bgTex:Show()
                -- 60% sample fill along the fill axis, reverse-aware.
                local sw = (fullW and (host:GetWidth() or w)) or (isVert and hh2 or w)
                local sh = (fullH and (host:GetHeight() or hh2)) or (isVert and w or hh2)
                fr._tex:ClearAllPoints()
                if isVert then
                    local edge = t.reverseFill and "TOP" or "BOTTOM"
                    fr._tex:SetPoint(edge .. "LEFT", fr, edge .. "LEFT", 0, 0)
                    fr._tex:SetPoint(edge .. "RIGHT", fr, edge .. "RIGHT", 0, 0)
                    fr._tex:SetHeight(math.max(1, floor(sh * 0.6)))
                else
                    local edge = t.reverseFill and "RIGHT" or "LEFT"
                    fr._tex:SetPoint("TOP" .. edge, fr, "TOP" .. edge, 0, 0)
                    fr._tex:SetPoint("BOTTOM" .. edge, fr, "BOTTOM" .. edge, 0, 0)
                    fr._tex:SetWidth(math.max(1, floor(sw * 0.6)))
                end
                fr._tex:SetColorTexture(c.r or 1, c.g or 1, c.b or 1,
                    (t.barColorOpacity or 100) / 100)
                fr:SetAlpha(alpha)
                fr:Show()
            elseif t.type == "healthcolor" then
                -- Frame-wide effect: shown while selected / eyeball (BM parity)
                if sel or allVis then
                    local hc = pv._dmHC
                    if not hc then
                        -- BM parity: ARTWORK sublevel 2 over the FILL texture
                        -- only, so it tints just the filled portion.
                        hc = health:CreateTexture(nil, "ARTWORK", nil, 2)
                        local fill = health.GetStatusBarTexture
                            and health:GetStatusBarTexture()
                        hc:SetAllPoints(fill or health)
                        pv._dmHC = hc
                    end
                    local c = t.color or { r = 1, g = 0.25, b = 0.25 }
                    ns.RF_TintOverBarFill(hc, health, c.r or 1, c.g or 0.25,
                        c.b or 0.25, (t.opacity or 45) / 100)
                    hc:Show()
                end
            elseif t.type == "glow" then
                if (sel or allVis) and Glows and not pv._dmGlowUsed then
                    local gov = pv._dmGlow
                    if not gov then
                        gov = CreateFrame("Frame", nil, pv)
                        gov:SetAllPoints(pv)
                        -- Live parity: the frame-glow host sits at +15,
                        -- above the aura and text bands.
                        gov:SetFrameLevel(pv:GetFrameLevel() + 15)
                        gov:EnableMouse(false)
                        pv._dmGlow = gov
                    end
                    -- Color mode parity with the live renderer.
                    local cr, cg2, cb2 = 1.0, 0.788, 0.137
                    local mode = t.glowColorMode or "default"
                    if mode == "class" then
                        local _, cf = UnitClass("player")
                        local ccc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
                        if ccc then cr, cg2, cb2 = ccc.r, ccc.g, ccc.b end
                    elseif mode == "custom" then
                        local c = t.color or { r = 1, g = 0.78, b = 0.38 }
                        cr, cg2, cb2 = c.r or 1, c.g or 0.78, c.b or 0.38
                    end
                    gov:Show()
                    -- Live parity: the animation-driven pixel march (the
                    -- only style the live slots render).
                    if Glows.StartAnimatedAnts then
                        Glows.StartAnimatedAnts(gov, t.glowLines or 8,
                            t.glowThickness or 2, t.glowSpeed or 4,
                            cr, cg2, cb2, pv:GetWidth() or 72, pv:GetHeight() or 72)
                    end
                    -- One overlay: the first qualifying glow tile wins.
                    pv._dmGlowUsed = true
                end
            end
        end
    end
    pv._dmGlowUsed = nil
end

function ns.DMP_BuildPage(pageName, parent, yOffset)
    local scrollFrame = EllesmereUI._scrollFrame
    if not scrollFrame then return 0 end
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local PP = EllesmereUI.PanelPP

    local parentW = scrollFrame:GetWidth()
    local fullH = scrollFrame:GetHeight()
    local sidebarW = floor(parentW * 0.28)
    local leftW = parentW - sidebarW

    local outerRoot = CreateFrame("Frame", nil, scrollFrame)
    outerRoot:SetAllPoints(scrollFrame)
    outerRoot:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    if ns._dmRoot then ns._dmRoot:Hide(); ns._dmRoot:SetParent(nil) end
    if ns._dmAddPopup then ns._dmAddPopup:Hide() end
    if EllesmereUI._pickMenu then EllesmereUI._pickMenu:Hide() end
    ns._dmRoot = outerRoot

    -- Override-session gate: heals a stale Debuff Manager layer FIRST (so
    -- the page content below renders the edited group's fork) and reports
    -- the full-page overlay to build at the end. nil = normal page.
    local dmOverlayState = EllesmereUI.SpecOverrides_DmPagePrelude
        and EllesmereUI.SpecOverrides_DmPagePrelude() or nil

    local dm = DmTable()

    -- Editing-spec bucket sanity: stale/unknown keys reset to All Specs.
    if dmSpecSel ~= "allspecs"
        and not (ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO[dmSpecSel])
        and not (type(dmSpecSel) == "string" and dmSpecSel:match("^spec%d")) then
        dmSpecSel = "allspecs"
    end
    local tiles = (ns.DM_BucketTiles and ns.DM_BucketTiles(dmSpecSel)) or {}

    -- Group buckets this view inherits from (concrete "spec<ID>" views
    -- only): their tiles lead the sidebar as read-only rows.
    local inhGroups = ns.BM_InheritedGroupsFor and ns.BM_InheritedGroupsFor(dmSpecSel) or nil

    -- The Base Icons grid is an All Specs indicator: OWN in the All Specs
    -- view, INHERITED (read-only, per-spec disable pill) in concrete spec
    -- views, absent from the other group views like any All Specs tile.
    local baseOwn = (dmSpecSel == "allspecs")
    local baseInherited = (inhGroups ~= nil)
    local allSpecsName = (ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO.allspecs)
        and L(ns.BM_GROUP_BUCKET_INFO.allspecs.name) or L("All Specs")

    -- Inherited selection: resolve against the owning group's bucket; drop
    -- it when the view no longer inherits that group or the tile is gone.
    -- id "base" = the inherited Base Icons grid (concrete spec views only).
    local inhSelTile = nil
    local inhSelBase = false
    if dmInhSel and inhGroups then
        if dmInhSel.id == "base" then
            inhSelBase = (dmInhSel.group == "allspecs")
        else
            for gi = 1, #inhGroups do
                if inhGroups[gi] == dmInhSel.group then
                    local gl = ns.DM_BucketTiles and ns.DM_BucketTiles(dmInhSel.group)
                    for i = 1, #(gl or {}) do
                        if gl[i].id == dmInhSel.id then inhSelTile = gl[i] break end
                    end
                    break
                end
            end
        end
    end
    if not (inhSelTile or inhSelBase) then dmInhSel = nil end

    -- Validate selection.
    if dmSel ~= "base" then
        local found = false
        for i = 1, #tiles do
            if tiles[i].id == dmSel then found = true break end
        end
        if not found then dmSel = "base" end
    end
    -- "base" in a concrete spec view IS the inherited base grid.
    if dmSel == "base" and not dmInhSel and baseInherited then
        dmInhSel = { group = "allspecs", id = "base" }
        inhSelBase = true
    end

    -- Editing-spec roster, shared by the Editing Spec dropdown and the
    -- right-click "Add To" menu: the group buckets lead, then every spec in
    -- the game as its own "spec<ID>" bucket (healer specs included -- the DM
    -- has no healer-key legacy).
    local function BuildDmSpecRoster()
        local values, order, icons = {}, {}, {}
        local groups = ns.BM_GROUP_BUCKETS or {}
        for i = 1, #groups do
            values[groups[i].key] = L(groups[i].name)
            order[#order + 1] = groups[i].key
            icons[groups[i].key] = groups[i].icon
        end
        order[#order + 1] = "---a"
        for classID = 1, (GetNumClasses and GetNumClasses() or 0) do
            local className = GetClassInfo(classID)
            local numSpecs = GetNumSpecializationsForClassID
                and GetNumSpecializationsForClassID(classID) or 0
            for si = 1, numSpecs do
                local specID, specName, _, sIcon = GetSpecializationInfoForClassID(classID, si)
                if specID then
                    local key = "spec" .. specID
                    values[key] = (specName or "") .. " " .. (className or "")
                    order[#order + 1] = key
                    icons[key] = sIcon
                end
            end
        end
        return values, order, icons
    end

    -- Right-click "Add To" items: the roster minus dividers, the edited
    -- bucket (= the source) disabled.
    local function DmBucketMenuItems()
        local values, order, icons = BuildDmSpecRoster()
        local items = {}
        for i = 1, #order do
            local key = order[i]
            if not key:match("^%-%-%-") then
                items[#items + 1] = {
                    key = key, label = values[key], icon = icons[key],
                    disabled = key == dmSpecSel,
                }
            end
        end
        return items
    end

    local p = DmProfile()
    if not p then return 0 end

    -- No header bar (matches the redesigned Buff Manager page): content
    -- starts at the top of the viewport.
    local root = CreateFrame("Frame", nil, outerRoot)
    root:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    root:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH

    -------------------------------------------------------------------
    --  RIGHT SIDEBAR (full visible height, own scroll, dark bg)
    -------------------------------------------------------------------
    local sidebarOuter = CreateFrame("Frame", nil, root)
    sidebarOuter:SetSize(sidebarW, visibleH)
    sidebarOuter:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -1)
    sidebarOuter:SetFrameLevel(root:GetFrameLevel() + 1)
    local sbBg = sidebarOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)

    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebarOuter)
    sidebarScroll:SetAllPoints()
    sidebarScroll:SetFrameLevel(sidebarOuter:GetFrameLevel() + 1)
    local sidebarChild = CreateFrame("Frame", nil, sidebarScroll)
    sidebarChild:SetWidth(sidebarW)
    sidebarScroll:SetScrollChild(sidebarChild)
    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll:SetScript("OnMouseWheel", function(self, delta)
        local scroll = self:GetVerticalScroll()
        local maxS = max(0, sidebarChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, math.min(maxS, scroll - delta * 30)))
    end)

    local tileY = 0

    -- Pinned Base Icons tile (All Specs view): undeletable, no toggle (an
    -- empty grid is expressed through the filters).
    if baseOwn then
        tileY = tileY - BuildTile(sidebarChild, tileY, {
            width = sidebarW, fontPath = fontPath,
            icon = SampleDebuffTexture(1),
            title = L("Base Icons"),
            posText = "(" .. L(POS_VALUES[p.debuffPosition or "bottomright"] or "") .. ")",
            subtitle = L("The standard debuff grid"),
            selected = (dmSel == "base" and not dmInhSel),
            enabled = true,
            onSelect = function()
                dmSel = "base"
                dmInhSel = nil
                EllesmereUI:RefreshPage(true)
            end,
        })
    elseif baseInherited then
        -- Concrete spec view: the All Specs base grid as an INHERITED row
        -- (read-only here; the pill is this spec's own on/off).
        local disHere = ns.DM_BaseDisabled and ns.DM_BaseDisabled(dmSpecSel)
        tileY = tileY - BuildTile(sidebarChild, tileY, {
            width = sidebarW, fontPath = fontPath,
            icon = SampleDebuffTexture(1),
            title = L("Base Icons"),
            posText = "(" .. L(POS_VALUES[p.debuffPosition or "bottomright"] or "") .. ")",
            subtitle = allSpecsName,
            inheritedTooltip = EllesmereUI.Lf("Inherited from %1$s. Editable only there.", allSpecsName),
            selected = inhSelBase,
            enabled = (not disHere) and true or false,
            showToggle = true,
            onSelect = function()
                dmInhSel = { group = "allspecs", id = "base" }
                EllesmereUI:RefreshPage(true)
            end,
            onToggle = function()
                ns.DM_SetBaseDisabled(dmSpecSel, not ns.DM_BaseDisabled(dmSpecSel))
                DmApply()
                EllesmereUI:RefreshPage(true)
            end,
        })
    end

    -- INHERITED group tiles lead concrete spec views: read-only here (edit
    -- them in their group); the pill toggles ONLY this spec's enable.
    if inhGroups then
        for gi = 1, #inhGroups do
            local gkey = inhGroups[gi]
            local ginfo = ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO[gkey]
            local gname = ginfo and L(ginfo.name) or gkey
            local gl = (ns.DM_BucketTiles and ns.DM_BucketTiles(gkey)) or {}
            for i = 1, #gl do
                local t = gl[i]
                local posText
                if t.type == "icons" or t.type == "square" or t.type == "bar" then
                    posText = "(" .. L(POS_VALUES[t.position or "top"] or "") .. ")"
                end
                local disHere = ns.DM_InhDisabled and ns.DM_InhDisabled(dmSpecSel, t.id)
                tileY = tileY - BuildTile(sidebarChild, tileY, {
                    width = sidebarW, fontPath = fontPath,
                    icon = TileFaceTexture(t),
                    title = t.name or L(TYPE_NAMES[t.type] or t.type),
                    posText = posText,
                    subtitle = gname,
                    inheritedTooltip = EllesmereUI.Lf("Inherited from %1$s. Editable only there.", gname),
                    selected = (dmInhSel and dmInhSel.group == gkey
                        and dmInhSel.id == t.id) and true or false,
                    -- Pill = the PER-SPEC enable only; a group-level disable
                    -- dims the tile instead (the pill must never look dead).
                    dimmed = not t.enabled or nil,
                    enabled = (not disHere) and true or false,
                    showToggle = true,
                    onSelect = function()
                        dmInhSel = { group = gkey, id = t.id }
                        EllesmereUI:RefreshPage(true)
                    end,
                    onToggle = function()
                        ns.DM_SetInhDisabled(dmSpecSel, t.id,
                            not ns.DM_InhDisabled(dmSpecSel, t.id))
                        DmApply()
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end
        end
    end

    -- Tile list (BM tile parity: icon face, type title, gray position
    -- suffix, routed-filters subtitle, pill toggle, atlas delete)
    for i = 1, #tiles do
        local t = tiles[i]
        local posText
        if t.type == "icons" or t.type == "square" or t.type == "bar" then
            posText = "(" .. L(POS_VALUES[t.position or "top"] or "") .. ")"
        end
        tileY = tileY - BuildTile(sidebarChild, tileY, {
            width = sidebarW, fontPath = fontPath,
            icon = TileFaceTexture(t),
            -- User-typed name over the type-name default. Display-only
            -- (additive key; DM_CfgFP serializes explicit fields, so a
            -- rename never re-declares containers).
            title = t.name or L(TYPE_NAMES[t.type] or t.type),
            posText = posText,
            subtitle = TileSubtitle(t),
            selected = (dmSel == t.id and not dmInhSel),
            enabled = t.enabled and true or false,
            showToggle = true,
            onSelect = function()
                dmSel = t.id
                dmInhSel = nil
                EllesmereUI:RefreshPage(true)
            end,
            -- Right-click: copy this tile into another editing-spec bucket
            -- (full clone, fresh id; the source stays).
            onContext = function(tileFrame)
                if not EllesmereUI.ShowPickMenu then return end
                EllesmereUI.ShowPickMenu(tileFrame, {
                    title = L("Add To"),
                    fontPath = fontPath,
                    items = DmBucketMenuItems(),
                    onPick = function(key)
                        if ns.DM_CopyTile and ns.DM_CopyTile(t, key) then
                            DmApply()
                            EllesmereUI:RefreshPage(true)
                        end
                    end,
                })
            end,
            onToggle = function(v)
                t.enabled = v and true or false
                DmApply()
                EllesmereUI:RefreshPage(true)
            end,
            onEdit = function()
                local cur = t.name or L(TYPE_NAMES[t.type] or t.type)
                EllesmereUI:ShowInputPopup({
                    title = L("Rename Indicator"),
                    message = L("Enter a new name for this indicator:"),
                    placeholder = cur,
                    confirmText = L("Rename"),
                    cancelText = L("Cancel"),
                    onConfirm = function(text)
                        text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
                        -- Empty reverts to the type-name default.
                        t.name = (text ~= "") and text or nil
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end,
            onDelete = function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Indicator"),
                    message = L("Delete this indicator? Its settings are removed from the profile."),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if ns.DM_DeleteTile then ns.DM_DeleteTile(t.id) end
                        if dmSel == t.id then dmSel = "base" end
                        DmApply()
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end,
        })
    end

    -------------------------------------------------------------------
    --  "Add New" button at bottom of sidebar tiles (BM parity: green
    --  accent button + dark type-picker popup on the BM popup chrome)
    -------------------------------------------------------------------
    local ADD_BTN_H = 30
    local ADD_BTN_PAD = 10
    do
        local btnW = floor(sidebarW * 0.6)
        local addBtn = CreateFrame("Button", nil, sidebarChild)
        addBtn:SetSize(btnW, ADD_BTN_H)
        addBtn:SetPoint("TOP", sidebarChild, "TOPLEFT", floor(sidebarW / 2), tileY - ADD_BTN_PAD)
        addBtn:SetFrameLevel(sidebarChild:GetFrameLevel() + 1)

        local accentColor = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)

        local addLabel = addBtn:CreateFontString(nil, "OVERLAY")
        -- Drop shadow via the shadow FontObject, primed BEFORE SetFont
        -- (SetShadowOffset alone does not render).
        if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(addLabel, true) end
        addLabel:SetFont(fontPath, 12, "")
        addLabel:SetPoint("CENTER")
        addLabel:SetText(L("Add New"))
        addLabel:SetTextColor(1, 1, 1)

        addBtn:SetScript("OnEnter", function()
            addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
        end)
        addBtn:SetScript("OnLeave", function()
            addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
        end)

        addBtn:SetScript("OnClick", function(self)
            -- Toggle popup (BM Add New popup parity: label + dropdown +
            -- accent Create button on the same chrome and metrics)
            local popup = ns._dmAddPopup
            if popup and popup:IsShown() then popup:Hide(); return end

            if not popup then
                local POPUP_W = 220
                local POPUP_PAD = 10
                local ROW_H2 = 30
                local LABEL_H = 14
                local LBL_GAP = 4   -- label to dropdown
                local DD_GAP = 11   -- dropdown to next label/button

                popup = CreateFrame("Frame", nil, UIParent)
                popup:SetFrameStrata("DIALOG")
                popup:SetFrameLevel(200)
                popup:SetSize(POPUP_W, POPUP_PAD
                    + 2 * (LABEL_H + LBL_GAP + ROW_H2 + DD_GAP)
                    + ROW_H2 + POPUP_PAD)
                popup:EnableMouse(true)
                popup:SetClampedToScreen(true)

                local bg = popup:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)

                -- Pending filter picks for the new tile (wiped on hide)
                popup._dmFilters = {}

                -- Auto-close when clicking outside (but not on a child
                -- dropdown's open menu)
                popup:SetScript("OnShow", function(p2)
                    p2:SetScript("OnUpdate", function(m)
                        if not self:IsMouseOver() and not m:IsMouseOver() then
                            local tDD = m._indDD
                            if tDD and tDD._ddMenu and tDD._ddMenu:IsShown() and tDD._ddMenu:IsMouseOver() then return end
                            local fDD = m._fltDD
                            if fDD and fDD._ddMenu and fDD._ddMenu:IsShown() and fDD._ddMenu:IsMouseOver() then return end
                            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                m:Hide()
                            end
                        end
                    end)
                end)
                popup:SetScript("OnHide", function(p2)
                    p2:SetScript("OnUpdate", nil)
                    if p2._dmFilters then wipe(p2._dmFilters) end
                    if p2._fltDDRefresh then p2._fltDDRefresh() end
                end)

                local py = -POPUP_PAD
                local ddW = POPUP_W - POPUP_PAD * 2

                -- Filters label + checkbox dropdown (identical items to the
                -- tile Filters dropdown; picks become the new tile's routed
                -- filters at Create)
                local fltLbl = popup:CreateFontString(nil, "OVERLAY")
                fltLbl:SetFont(fontPath, 11, "")
                fltLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                fltLbl:SetText(L("Filters"))
                fltLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                -- Same two-lane item list as the tile Filters dropdown; picks
                -- pend in popup._dmFilters (show keys plain, hide keys with a
                -- "neg_" prefix; the pinned All/Has Duration keys ride the
                -- plain lane) and become the new tile's claim/neg/all/
                -- hasDuration at Create.
                local pend = popup._dmFilters
                local fltDD, fltDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    popup, ddW, popup:GetFrameLevel() + 2,
                    TILE_LANE_ITEMS,
                    function(k, neg)
                        if neg then return pend["neg_" .. k] and true or false end
                        return pend[k] and true or false
                    end,
                    function(k, v, neg)
                        if k == TILE_CA_ALL or k == TILE_CA_DUR then
                            -- Independent bits (All Debuffs / Has Duration modifier).
                            pend[k] = v and true or nil
                            return
                        end
                        if k == "dispel_you" or k == "dispel_typed" then
                            -- ONE dispel category (flavors mutually exclusive
                            -- across rows AND lanes, base-dropdown parity).
                            pend.dispel_you, pend.dispel_typed = nil, nil
                            pend.neg_dispel_you, pend.neg_dispel_typed = nil, nil
                            if v then pend[(neg and "neg_" or "") .. k] = true end
                            return
                        end
                        -- Two-lane pend write: checking one lane clears the other.
                        if neg then
                            pend["neg_" .. k] = v and true or nil
                            if v then pend[k] = nil end
                        else
                            pend[k] = v and true or nil
                            if v then pend["neg_" .. k] = nil end
                        end
                    end,
                    nil, 12)
                fltDD:SetSize(ddW, ROW_H2)
                fltDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                popup._fltDD = fltDD
                popup._fltDDRefresh = fltDDRefresh
                py = py - ROW_H2 - DD_GAP

                local indLbl = popup:CreateFontString(nil, "OVERLAY")
                indLbl:SetFont(fontPath, 11, "")
                indLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                indLbl:SetText(L("Indicator"))
                indLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                local indDD = EllesmereUI.BuildDropdownControl(
                    popup, ddW, popup:GetFrameLevel() + 2,
                    TYPE_NAMES, TYPE_ORDER,
                    function() return dmSelType end,
                    function(v) dmSelType = v end)
                indDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                popup._indDD = indDD
                py = py - ROW_H2 - DD_GAP

                local accentColor = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
                local cBtn = CreateFrame("Button", nil, popup)
                cBtn:SetSize(ddW, ROW_H2)
                cBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                cBtn:SetFrameLevel(popup:GetFrameLevel() + 1)
                local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
                cBg:SetAllPoints()
                cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
                local cTx = cBtn:CreateFontString(nil, "OVERLAY")
                cTx:SetPoint("CENTER")
                cTx:SetFont(fontPath, 12, "")
                cTx:SetText(L("Create"))
                cTx:SetTextColor(1, 1, 1)
                cBtn:SetScript("OnEnter", function() cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1) end)
                cBtn:SetScript("OnLeave", function() cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8) end)
                cBtn:SetScript("OnClick", function()
                    -- Snapshot picks BEFORE Hide (hide wipes the pending set)
                    local picked, negPicked = {}, nil
                    local caAll = popup._dmFilters[TILE_CA_ALL] and true or false
                    local caDur = popup._dmFilters[TILE_CA_DUR] and true or false
                    local mode
                    for k in pairs(popup._dmFilters) do
                        if k ~= TILE_CA_ALL and k ~= TILE_CA_DUR then
                            local cat, isNeg = k, false
                            if cat:sub(1, 4) == "neg_" then
                                cat = cat:sub(5)
                                isNeg = true
                            end
                            if cat == "dispel_you" then cat = "dispel"; mode = "you"
                            elseif cat == "dispel_typed" then cat = "dispel"; mode = "typed" end
                            if isNeg then
                                negPicked = negPicked or {}
                                negPicked[cat] = true
                            else
                                picked[cat] = true
                            end
                        end
                    end
                    local t = ns.DM_AddTile and ns.DM_AddTile(dmSelType, dmSpecSel)
                    popup:Hide()
                    if t then
                        if mode then
                            local dm2 = DmTable()
                            if dm2 then dm2.dispelMode = mode end
                        end
                        -- Every tile type takes the full picked set now
                        -- (effect tiles run one slot per category).
                        if not t.claim then t.claim = {} end
                        for cat in pairs(picked) do t.claim[cat] = true end
                        if negPicked then t.neg = negPicked end
                        if caAll then t.all = true end
                        if caDur then t.hasDuration = true end
                        dmSel = t.id
                        dmInhSel = nil
                        DmApply()
                        EllesmereUI:RefreshPage(true)
                    end
                end)

                ns._dmAddPopup = popup
            end

            -- Position below the Add New button, centered on sidebar
            popup:ClearAllPoints()
            local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            popup:SetScale(sc)
            popup:SetPoint("TOP", self, "BOTTOM", 0, -12)
            popup:Show()
        end)
        tileY = tileY - ADD_BTN_PAD - ADD_BTN_H - ADD_BTN_PAD
    end

    sidebarChild:SetHeight(max(10, math.abs(tileY)))

    -------------------------------------------------------------------
    --  LEFT COLUMN (72%): fixed top (preview band + Editing Spec section
    --  + accent title) + scrollable settings below -- a clone of the BM
    --  page's left column, band split 65/35 like the BM's.
    -------------------------------------------------------------------
    local PAD = 20
    local leftFixed = CreateFrame("Frame", nil, root)
    leftFixed:SetSize(leftW, 10) -- height set after content
    leftFixed:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    local ly = 0

    local pvSplitW = floor(leftW * 0.65)
    local specSplitW = leftW - pvSplitW

    -- Preview: the shared health-bar replica in replica-only mode; the DM
    -- renderer draws the base grid + tiles on it. Centered in the LEFT 65%
    -- (the Editing Spec section owns the right 35%).
    local pvFrame, sectionH = ns.BM_BuildSimplePreview(leftFixed, p, fontPath, PP, pvSplitW / 2, -PAD, true)
    ns._dmPreviewFrame = pvFrame
    pvFrame._dmFontPath = fontPath

    -- Matches the replica builder's scale math (for the eyeball offset).
    local PV_SCALE = 1.5
    do
        local rawH = p.frameHeight or 46
        if rawH * PV_SCALE > 100 then PV_SCALE = 100 / rawH end
    end

    -- Eyeball toggle: show all tiles at full opacity (BM parity)
    do
        local EYE_VIS = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVIS = EllesmereUI.EYE_INVISIBLE_ICON
        ns._dmAllVisible = ns._dmAllVisible or false

        local eyeBtn = CreateFrame("Button", nil, leftFixed)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("LEFT", pvFrame, "RIGHT", 18 / PV_SCALE, 0)
        eyeBtn:SetFrameLevel(leftFixed:GetFrameLevel() + 5)

        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(ns._dmAllVisible and EYE_INVIS or EYE_VIS)
        eyeBtn:SetAlpha(0.4)

        eyeBtn:SetScript("OnClick", function()
            ns._dmAllVisible = not ns._dmAllVisible
            eyeTex:SetTexture(ns._dmAllVisible and EYE_INVIS or EYE_VIS)
            if ns.DMP_RefreshPreview then ns.DMP_RefreshPreview() end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Toggle All Indicators")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
    end

    -------------------------------------------------------------------
    --  EDITING SPEC (right 35% of the band, BM parity): the group
    --  buckets lead, then every spec in the game as its own "spec<ID>"
    --  bucket -- healer specs included (the DM has no healer-key legacy).
    -------------------------------------------------------------------
    do
        local splitDiv = leftFixed:CreateTexture(nil, "ARTWORK")
        splitDiv:SetWidth(1)
        splitDiv:SetPoint("TOP", leftFixed, "TOPLEFT", pvSplitW, ly - 10)
        splitDiv:SetPoint("BOTTOM", leftFixed, "TOPLEFT", pvSplitW, ly - sectionH + 10)
        splitDiv:SetColorTexture(1, 1, 1, 0.08)

        local specCenterX = pvSplitW + specSplitW / 2
        -- Roster shared with the right-click "Add To" menu (the menu
        -- rebuilds it lazily per open).
        local specDDValues, specDDOrder, specDDIcons = BuildDmSpecRoster()
        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(key) return specDDIcons[key] end,
        }

        local groupH = 14 + 7 + 30
        local groupTopY = ly - (sectionH - groupH) / 2
        local specLabel = leftFixed:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontPath, 12, "")
        specLabel:SetPoint("TOP", leftFixed, "TOPLEFT", specCenterX, groupTopY)
        specLabel:SetJustifyH("CENTER")
        specLabel:SetText(L("Editing Spec"))
        specLabel:SetTextColor(1, 1, 1, 0.75)

        local specDDW = specSplitW - PAD - 50
        local specDD = EllesmereUI.BuildDropdownControl(
            leftFixed, specDDW, leftFixed:GetFrameLevel() + 2,
            specDDValues, specDDOrder,
            function() return dmSpecSel or "allspecs" end,
            function(v)
                dmSpecSel = v
                dmSel = "base"
                dmInhSel = nil
                EllesmereUI:RefreshPage(true)
            end)
        specDD:SetPoint("TOP", specLabel, "BOTTOM", 0, -7)
    end

    -- No text under the DM preview (user call 2026-07-24): the "Edit
    -- Excluded Debuffs" link is retired (exclude list is internal now) and
    -- the BM-style click-hint was dropped the next day. The band-height
    -- accounting stays so the divider seats where it always did.
    ly = ly - sectionH - 10

    -------------------------------------------------------------------
    --  DIVIDER (below preview, above settings title) -- BM parity
    -------------------------------------------------------------------
    local div1 = leftFixed:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", leftFixed, "TOPLEFT", PAD, ly)
    div1:SetPoint("TOPRIGHT", leftFixed, "TOPRIGHT", -PAD, ly)
    div1:SetColorTexture(1, 1, 1, 0.08)

    ly = ly - 25

    -- Accent-colored title + gray subtitle (BM parity)
    local settingsTitle = leftFixed:CreateFontString(nil, "OVERLAY")
    settingsTitle:SetFont(fontPath, 18, "")
    settingsTitle:SetPoint("TOPLEFT", leftFixed, "TOPLEFT", PAD, ly)
    settingsTitle:SetJustifyH("LEFT")
    settingsTitle:SetWordWrap(false)
    local ac2 = EllesmereUI.ELLESMERE_GREEN
    if ac2 then settingsTitle:SetTextColor(ac2.r, ac2.g, ac2.b)
    else settingsTitle:SetTextColor(0.05, 0.82, 0.62) end

    local subTitle = leftFixed:CreateFontString(nil, "OVERLAY")
    subTitle:SetFont(fontPath, 13, "")
    subTitle:SetPoint("LEFT", settingsTitle, "RIGHT", 4, 0)
    subTitle:SetPoint("RIGHT", leftFixed, "RIGHT", -PAD, 0)
    subTitle:SetJustifyH("LEFT")
    subTitle:SetWordWrap(false)
    subTitle:SetTextColor(0.75, 0.75, 0.75, 0.65)

    local selTile
    if not dmInhSel and dmSel ~= "base" then
        for i = 1, #tiles do
            if tiles[i].id == dmSel then selTile = tiles[i] break end
        end
    end
    -- Group views (not All Specs, not a concrete spec) list no base grid: a
    -- "base" selection there means nothing is selected.
    local groupEmpty = (dmSel == "base" and not dmInhSel and not baseOwn and not baseInherited)
    if dmInhSel and inhSelTile then
        local ginfo2 = ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO[dmInhSel.group]
        local gname2 = ginfo2 and L(ginfo2.name) or dmInhSel.group
        settingsTitle:SetTextColor(0.55, 0.72, 1)
        settingsTitle:SetText(inhSelTile.name or L(TYPE_NAMES[inhSelTile.type] or inhSelTile.type))
        subTitle:SetText("(" .. EllesmereUI.Lf("Inherited from %1$s", gname2) .. ")")
    elseif dmInhSel and inhSelBase then
        settingsTitle:SetTextColor(0.55, 0.72, 1)
        settingsTitle:SetText(L("Base Icons"))
        subTitle:SetText("(" .. EllesmereUI.Lf("Inherited from %1$s", allSpecsName) .. ")")
    elseif selTile then
        settingsTitle:SetText(L(TYPE_NAMES[selTile.type] or selTile.type))
        subTitle:SetText("(" .. TileSubtitle(selTile) .. ")")
    elseif groupEmpty then
        local ginfo3 = ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO[dmSpecSel]
        settingsTitle:SetText(ginfo3 and L(ginfo3.name) or dmSpecSel)
        subTitle:SetText("(" .. L("No indicator selected") .. ")")
    else
        settingsTitle:SetText(L("Base Icons"))
        subTitle:SetText("(" .. L("The standard debuff grid") .. ")")
    end

    ly = ly - 18 - 10

    local fixedH = math.abs(ly)
    leftFixed:SetHeight(fixedH)

    -------------------------------------------------------------------
    --  Settings scroll area (BM parity: smooth scroll + thin thumb;
    --  DualRow width compensated so rows align with the 20px PAD)
    -------------------------------------------------------------------
    local contentPad = EllesmereUI.CONTENT_PAD or 45
    local padDiff = contentPad - PAD
    local viewportH = max(10, visibleH - fixedH)
    local settingsW = leftW + padDiff * 2

    local settingsScroll = CreateFrame("ScrollFrame", nil, root)
    settingsScroll:SetPoint("TOPLEFT", leftFixed, "BOTTOMLEFT", -padDiff, 5)
    settingsScroll:SetSize(settingsW, viewportH)
    settingsScroll:SetFrameLevel(root:GetFrameLevel() + 1)
    settingsScroll:SetClipsChildren(true)

    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetSize(settingsW, viewportH)
    settingsScroll:SetScrollChild(settingsChild)

    local SBAR_W = 5
    local sbTrack = CreateFrame("Frame", nil, settingsScroll)
    sbTrack:SetPoint("TOPRIGHT", settingsScroll, "TOPRIGHT", -31, -12)
    sbTrack:SetPoint("BOTTOMRIGHT", settingsScroll, "BOTTOMRIGHT", -31, 12)
    sbTrack:SetWidth(SBAR_W)
    sbTrack:SetFrameLevel(settingsScroll:GetFrameLevel() + 20)
    do local t = sbTrack:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.05) end
    local sbThumb = CreateFrame("Frame", nil, sbTrack)
    sbThumb:SetWidth(SBAR_W); sbThumb:SetHeight(30)
    sbThumb:SetPoint("TOP", sbTrack, "TOP", 0, 0)
    sbThumb:EnableMouse(true)
    do local t = sbThumb:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.22) end
    sbTrack:Hide()

    local SCROLL_STEP, SMOOTH_SPEED = 60, 12
    local scrollTarget = 0
    local function MaxScroll() return max(0, settingsChild:GetHeight() - settingsScroll:GetHeight()) end
    local function UpdateThumb()
        local ms = MaxScroll()
        if ms <= 0 then sbTrack:Hide(); return end
        sbTrack:Show()
        local trackH = sbTrack:GetHeight()
        local visH = settingsScroll:GetHeight()
        local thumbH = max(30, trackH * (visH / (visH + ms)))
        sbThumb:SetHeight(thumbH)
        local ratio = (settingsScroll:GetVerticalScroll() or 0) / ms
        sbThumb:ClearAllPoints()
        sbThumb:SetPoint("TOP", sbTrack, "TOP", 0, -(ratio * (trackH - thumbH)))
    end
    local smoothFrame = CreateFrame("Frame", nil, root)
    smoothFrame:Hide()
    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = settingsScroll:GetVerticalScroll()
        local ms = MaxScroll()
        scrollTarget = max(0, math.min(ms, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            settingsScroll:SetVerticalScroll(scrollTarget); UpdateThumb(); smoothFrame:Hide(); return
        end
        local nv = max(0, math.min(ms, cur + diff * math.min(1, SMOOTH_SPEED * elapsed)))
        settingsScroll:SetVerticalScroll(nv); UpdateThumb()
    end)
    local function SmoothTo(t)
        scrollTarget = max(0, math.min(MaxScroll(), t))
        smoothFrame:Show()
    end
    settingsScroll:EnableMouseWheel(true)
    settingsScroll:SetScript("OnMouseWheel", function(_, delta)
        if MaxScroll() <= 0 then return end
        local base = smoothFrame:IsShown() and scrollTarget or settingsScroll:GetVerticalScroll()
        SmoothTo(base - delta * SCROLL_STEP)
    end)
    sbThumb:SetScript("OnMouseDown", function()
        smoothFrame:Hide()
        local _, cy0 = GetCursorPosition()
        local startY = cy0 / settingsScroll:GetEffectiveScale()
        local startScroll = settingsScroll:GetVerticalScroll()
        sbThumb:SetScript("OnUpdate", function(self)
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil); return end
            local ms = MaxScroll()
            local travel = sbTrack:GetHeight() - sbThumb:GetHeight()
            if travel <= 0 then return end
            local _, cy = GetCursorPosition(); cy = cy / settingsScroll:GetEffectiveScale()
            local nv = max(0, math.min(ms, startScroll + ((startY - cy) / travel) * ms))
            scrollTarget = nv
            settingsScroll:SetVerticalScroll(nv); UpdateThumb()
        end)
    end)

    -- Read-only pane for an INHERITED row (group tile or the All Specs base
    -- grid): where it lives, a jump link to the owning group, and a pointer
    -- at the tile toggle for the per-spec enable. No settings render --
    -- edits belong to the group. (Child x = padDiff + PAD aligns with the
    -- PAD margin.) Returns the consumed height.
    local function BuildInheritedPane(gname2, jumpGroup, jumpId)
        local info = settingsChild:CreateFontString(nil, "OVERLAY")
        info:SetFont(fontPath, 12, "")
        info:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", padDiff + PAD, -14)
        info:SetPoint("RIGHT", settingsChild, "RIGHT", -(padDiff + PAD), 0)
        info:SetJustifyH("LEFT")
        info:SetWordWrap(true)
        info:SetText(EllesmereUI.Lf("Inherited from %1$s. Edit it there, or use the tile toggle to enable or disable it for this spec.", gname2))
        info:SetTextColor(0.65, 0.65, 0.65)
        local link = CreateFrame("Button", nil, settingsChild)
        link:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", padDiff + PAD, -78)
        link:SetFrameLevel(settingsChild:GetFrameLevel() + 2)
        local linkFS = link:CreateFontString(nil, "OVERLAY")
        linkFS:SetFont(fontPath, 12, "")
        linkFS:SetPoint("TOPLEFT")
        linkFS:SetText(EllesmereUI.Lf("Edit in %1$s", gname2))
        local lac = EllesmereUI.ELLESMERE_GREEN
        if lac then linkFS:SetTextColor(lac.r, lac.g, lac.b, 0.85)
        else linkFS:SetTextColor(0.05, 0.82, 0.62, 0.85) end
        link:SetSize(linkFS:GetStringWidth() + 4, 18)
        link:SetScript("OnEnter", function() linkFS:SetAlpha(1) end)
        link:SetScript("OnLeave", function() linkFS:SetAlpha(0.85) end)
        link:SetScript("OnClick", function()
            dmSpecSel = jumpGroup
            dmSel = jumpId
            dmInhSel = nil
            EllesmereUI:RefreshPage(true)
        end)
        return -110
    end

    -- Detail rows build inside the scroll child
    local sy
    if dmInhSel and inhSelTile then
        local ginfo2 = ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO[dmInhSel.group]
        local gname2 = ginfo2 and L(ginfo2.name) or dmInhSel.group
        sy = BuildInheritedPane(gname2, dmInhSel.group, dmInhSel.id)
    elseif dmInhSel and inhSelBase then
        sy = BuildInheritedPane(allSpecsName, "allspecs", "base")
    elseif selTile then
        sy = BuildTileDetail(settingsChild, fontPath, selTile)
    elseif groupEmpty then
        -- Group view with nothing selected: All Specs content (base grid
        -- included) is not listed here, exactly like it is not for tiles.
        local info = settingsChild:CreateFontString(nil, "OVERLAY")
        info:SetFont(fontPath, 12, "")
        info:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", padDiff + PAD, -14)
        info:SetPoint("RIGHT", settingsChild, "RIGHT", -(padDiff + PAD), 0)
        info:SetJustifyH("LEFT")
        info:SetWordWrap(true)
        info:SetText(EllesmereUI.Lf("Indicators added here show on every spec in this group. The Base Icons grid lives in %1$s.", allSpecsName))
        info:SetTextColor(0.65, 0.65, 0.65)
        sy = -60
    else
        sy = BuildBaseDetailDM(settingsChild, fontPath)
    end

    settingsChild:SetHeight(max(viewportH, math.abs(sy or 0) + 12))
    UpdateThumb()

    -- First render of the preview content
    if ns.DMP_RefreshPreview then ns.DMP_RefreshPreview() end

    -- Override-session overlay (mirror of the Buff Manager page's): built
    -- LAST so it covers the whole page incl. the sidebar. High frame level;
    -- child of outerRoot so every teardown path destroys it.
    if dmOverlayState then
        local st = dmOverlayState
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
        title:SetText(EllesmereUI.L("Custom Debuff Manager"))
        local body = ov:CreateFontString(nil, "OVERLAY")
        body:SetFont(fontPath, 13, "")
        body:SetPoint("TOP", title, "BOTTOM", 0, -14)
        body:SetWidth(floor(parentW * 0.7))
        body:SetJustifyH("CENTER")
        body:SetTextColor(1, 1, 1, 0.56)
        body:SetText(st.text or "")
        local sub
        if st.sub then
            sub = ov:CreateFontString(nil, "OVERLAY")
            sub:SetFont(fontPath, 12, "")
            sub:SetPoint("TOP", body, "BOTTOM", 0, -8)
            sub:SetWidth(floor(parentW * 0.7))
            sub:SetJustifyH("CENTER")
            sub:SetTextColor(1, 1, 1, 0.45)
            sub:SetText(st.sub)
        end
        if st.mode == "activate" then
            local btn = CreateFrame("Button", nil, ov)
            btn:SetSize(240, 28)
            btn:SetPoint("TOP", sub or body, "BOTTOM", 0, -22)
            EllesmereUI.SolidTex(btn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9):SetAllPoints(btn)
            local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.22)
            local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1, 0.85)
            lbl:SetPoint("CENTER")
            lbl:SetText(EllesmereUI.L("Activate Custom Debuff Manager"))
            local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
            btn:SetScript("OnEnter", function()
                if brd and brd.SetColor then brd:SetColor(eg.r, eg.g, eg.b, 0.9) end
            end)
            btn:SetScript("OnLeave", function()
                if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end
            end)
            btn:SetScript("OnClick", function()
                if EllesmereUI.SpecOverrides_ActivateDm then
                    EllesmereUI.SpecOverrides_ActivateDm(st.kind, st.gid)
                end
            end)
        end
    end

    return 0
end

-------------------------------------------------------------------------------
-- BUFF MANAGER v2 page (spell -> filter -> indicator). Replaces the legacy
-- BM page wholesale on 12.1 (the options file redirects BuildBuffManagerPage
-- here when v2 is loaded). Assigns ns._bmRoot so every existing cleanup
-- path (page switch, panel close, module switch) manages this page too;
-- the Filter Editor popup parents into the root and dies with it.
-------------------------------------------------------------------------------

local CLASS_ORDER = EllesmereUI.CLASS_TOKEN_ORDER

-- Filter Editor popup: right sidebar = filter list (presets pinned),
-- left = the selected filter's spells as checkboxes grouped by class
-- (curated data) or under Custom (user-added), plus an Add Spell ID box.
local fdSel = nil -- selected filter id
local fdScrollPos = 0 -- preserved spell-list scroll across editor rebuilds

-- Filter Editor modal, built on the standard popup chrome (mirrors
-- ShowInputPopup: fullscreen dimmer at black 0.25, opaque 0.06/0.08/0.10
-- panel, 0.15 white border, MakeFont title, SolidTex+MakeBorder buttons).
-- Right sidebar = filter list (presets pinned; custom rename via the
-- standard input popup + delete via the standard confirm popup); left =
-- the selected filter's spells as checkbox rows using the checkbox-
-- dropdown widget's exact visuals, grouped by class.
function ns.BMP_ShowFilterEditor()
    if ns._bm2FilterEditor then ns._bm2FilterEditor:Hide(); ns._bm2FilterEditor = nil end
    local filters = ns.BM2_Filters and ns.BM2_Filters()
    if not filters then return end
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("options"))
        or (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames"))
        or "Fonts\\FRIZQT__.TTF"
    local ar, ag, ab = 1, 0.82, 0.30
    if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
    local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

    local POPUP_W, POPUP_H = 620, 520
    local SIDE_W = 180

    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    -- Clicking off the popup closes the editor (the popup is mouse-enabled,
    -- so clicks on it never reach the dimmer).
    dimmer:SetScript("OnMouseDown", function()
        dimmer:Hide()
        ns._bm2FilterEditor = nil
    end)
    local dimTex = EllesmereUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()
    ns._bm2FilterEditor = dimmer

    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local popBg = EllesmereUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1)
    popBg:SetAllPoints()
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15)
    local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
    popup:SetScale(ppScale)

    local title = EllesmereUI.MakeFont(popup, 16, "", 1, 1, 1)
    title:SetPoint("TOP", popup, "TOP", 0, -18)
    title:SetText(EllesmereUI.L("Edit Filters"))

    -- Standard popup-style button (SolidTex bg + border + hover fade-lite).
    local function PopupButton(parent, w, h, label, onClick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(w, h)
        btn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", 0, 0, 0, 0.5)
        bg:SetAllPoints()
        local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
        local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
        lbl:SetAlpha(0.6)
        lbl:SetPoint("CENTER")
        lbl:SetText(EllesmereUI.L(label))
        btn:SetScript("OnEnter", function()
            lbl:SetAlpha(0.9)
            if brd and brd.SetColor then brd:SetColor(ar, ag, ab, 0.6) end
        end)
        btn:SetScript("OnLeave", function()
            lbl:SetAlpha(0.6)
            if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.25) end
        end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- Close button (top-right): the borderless X (the boxed close-popup
    -- variant reads as a framed button here).
    do
        local close = CreateFrame("Button", nil, popup)
        close:SetSize(19, 19)
        close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -13, -8)
        close:SetFrameLevel(popup:GetFrameLevel() + 5)
        local closeIcon = close:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAllPoints()
        closeIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
        closeIcon:SetAlpha(0.40)
        closeIcon:SetSnapToPixelGrid(false)
        closeIcon:SetTexelSnappingBias(0)
        close:SetScript("OnEnter", function() closeIcon:SetAlpha(0.50) end)
        close:SetScript("OnLeave", function() closeIcon:SetAlpha(0.40) end)
        close:SetScript("OnClick", function()
            dimmer:Hide()
            ns._bm2FilterEditor = nil
        end)
    end

    -- Validate selection
    if fdSel then
        local ok = false
        for i = 1, #filters do if filters[i].id == fdSel then ok = true end end
        if not ok then fdSel = nil end
    end
    if not fdSel and filters[1] then fdSel = filters[1].id end

    local function Rebuild()
        ns.BMP_ShowFilterEditor()
    end
    local function Apply()
        if ns.BM2_Invalidate then ns.BM2_Invalidate() end
        if ns.ReloadFrames then ns.ReloadFrames() end
    end
    -- The standard input popup is a lazily-created singleton that predates
    -- this (later-created) editor, so at equal strata it renders BEHIND it.
    -- Raise it above the editor whenever it opens from here.
    local function EditorInput(opts)
        EllesmereUI:ShowInputPopup(opts)
        local d = _G.EUIInputDimmer
        if d and ns._bm2FilterEditor then
            d:SetFrameLevel(popup:GetFrameLevel() + 40)
            local p = _G.EUIInputPopup
            if p then p:SetFrameLevel(d:GetFrameLevel() + 10) end
        end
    end

    local MEDIA_FE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

    -- Standard smooth scroll + thin custom scrollbar for an editor scroll
    -- region (the settings-viewport pattern). Track shows only on overflow.
    -- Returns UpdateThumb and a SetScrollTo(v) that syncs bar + target.
    local function AttachEditorScroll(scroll, child, onScroll)
        local SBAR_W = 4
        local track = CreateFrame("Frame", nil, scroll)
        track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -2)
        track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -2, 2)
        track:SetWidth(SBAR_W)
        track:SetFrameLevel(scroll:GetFrameLevel() + 5)
        do local tx = track:CreateTexture(nil, "BACKGROUND"); tx:SetAllPoints(); tx:SetColorTexture(1, 1, 1, 0.05) end
        local thumb = CreateFrame("Frame", nil, track)
        thumb:SetWidth(SBAR_W); thumb:SetHeight(30)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)
        thumb:EnableMouse(true)
        do local tx = thumb:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints(); tx:SetColorTexture(1, 1, 1, 0.22) end
        track:Hide()

        local function MaxScroll() return max(0, child:GetHeight() - scroll:GetHeight()) end
        local function UpdateThumb()
            local ms = MaxScroll()
            if ms <= 0 then track:Hide(); return end
            track:Show()
            local trackH = track:GetHeight()
            local visH = scroll:GetHeight()
            local thumbH = max(20, trackH * (visH / (visH + ms)))
            thumb:SetHeight(thumbH)
            local ratio = (scroll:GetVerticalScroll() or 0) / ms
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(ratio * (trackH - thumbH)))
        end

        local SCROLL_STEP, SMOOTH_SPEED = 60, 12
        local target = 0
        local smooth = CreateFrame("Frame", nil, scroll)
        smooth:Hide()
        smooth:SetScript("OnUpdate", function(_, elapsed)
            local cur = scroll:GetVerticalScroll()
            local ms = MaxScroll()
            target = max(0, math.min(ms, target))
            local diff = target - cur
            if math.abs(diff) < 0.3 then
                scroll:SetVerticalScroll(target); UpdateThumb(); smooth:Hide()
                if onScroll then onScroll(target) end
                return
            end
            local nv = max(0, math.min(ms, cur + diff * math.min(1, SMOOTH_SPEED * elapsed)))
            scroll:SetVerticalScroll(nv); UpdateThumb()
            if onScroll then onScroll(nv) end
        end)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            if MaxScroll() <= 0 then return end
            local base = smooth:IsShown() and target or scroll:GetVerticalScroll()
            target = max(0, math.min(MaxScroll(), base - delta * SCROLL_STEP))
            smooth:Show()
        end)
        thumb:SetScript("OnMouseDown", function()
            smooth:Hide()
            local _, cy0 = GetCursorPosition()
            local startY = cy0 / scroll:GetEffectiveScale()
            local startScroll = scroll:GetVerticalScroll()
            thumb:SetScript("OnUpdate", function(self2)
                if not IsMouseButtonDown("LeftButton") then self2:SetScript("OnUpdate", nil); return end
                local ms = MaxScroll()
                local travel = track:GetHeight() - thumb:GetHeight()
                if travel <= 0 then return end
                local _, cy = GetCursorPosition(); cy = cy / scroll:GetEffectiveScale()
                local nv = max(0, math.min(ms, startScroll + ((startY - cy) / travel) * ms))
                target = nv
                scroll:SetVerticalScroll(nv); UpdateThumb()
                if onScroll then onScroll(nv) end
            end)
        end)

        local function SetScrollTo(v)
            local ms = MaxScroll()
            if v > ms then v = ms end
            if v < 0 then v = 0 end
            target = v
            scroll:SetVerticalScroll(v)
            UpdateThumb()
            if onScroll then onScroll(v) end
        end
        return UpdateThumb, SetScrollTo
    end

    -- RIGHT: filter list (dropdown-item styling: hover wash, accent-washed
    -- selected row)
    local side = CreateFrame("Frame", nil, popup)
    side:SetWidth(SIDE_W)
    -- Flush with the popup's right edge and bottom.
    side:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -44)
    side:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 0)
    side:SetFrameLevel(popup:GetFrameLevel() + 1)
    local sideBg = EllesmereUI.SolidTex(side, "BACKGROUND", 0, 0, 0, 0.35)
    sideBg:SetAllPoints()
    EllesmereUI.MakeBorder(side, 1, 1, 1, 0.10)

    -- Sidebar content scrolls when it outgrows the popup (standard smooth
    -- scroll + thin custom bar; bar shows only on overflow).
    local sideScroll = CreateFrame("ScrollFrame", nil, side)
    sideScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -1)
    sideScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -1, 1)
    sideScroll:SetFrameLevel(side:GetFrameLevel() + 1)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetWidth(SIDE_W - 2)
    sideScroll:SetScrollChild(sideChild)

    local fy = -4
    for i = 1, #filters do
        local f = filters[i]
        local isSel = (fdSel == f.id)
        local frow = CreateFrame("Button", nil, sideChild)
        frow:SetHeight(26)
        frow:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, fy)
        frow:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, fy)
        frow:SetFrameLevel(sideChild:GetFrameLevel() + 1)
        local rbg = frow:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        local rl = EllesmereUI.MakeFont(frow, 12, nil, 1, 1, 1)
        rl:SetAlpha(isSel and 0.95 or 0.6)
        rl:SetPoint("LEFT", frow, "LEFT", 10, 0)
        rl:SetPoint("RIGHT", frow, "RIGHT", f.preset and -8 or -42, 0)
        rl:SetJustifyH("LEFT")
        rl:SetWordWrap(false)
        rl:SetText(L(f.name))
        if isSel then
            local accent = frow:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, 26)
            accent:SetPoint("TOPLEFT", frow, "TOPLEFT", 0, 0)
            accent:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
        end
        frow:SetScript("OnEnter", function()
            if not isSel then rbg:SetColorTexture(1, 1, 1, 0.04) end
        end)
        frow:SetScript("OnLeave", function()
            rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        end)
        frow:SetScript("OnClick", function()
            fdSel = f.id
            fdScrollPos = 0 -- new filter = new list; start at the top
            Rebuild()
        end)
        if not f.preset then
            -- Inline X (delete) + pencil (rename) -- the CDM preset-menu
            -- inline-button pattern (eui-close / eui-edit at 14px).
            local del = CreateFrame("Button", nil, frow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", frow, "RIGHT", -6, 0)
            del:SetFrameLevel(frow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then dx:SetSnapToPixelGrid(false); dx:SetTexelSnappingBias(0) end
            dx:SetTexture(MEDIA_FE .. "eui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                EllesmereUI.HideWidgetTooltip()
            end)
            del:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title = EllesmereUI.L("Delete Filter"),
                    message = EllesmereUI.L("Delete this filter? It is removed from every indicator using it."),
                    confirmText = EllesmereUI.L("Delete"),
                    cancelText = EllesmereUI.L("Cancel"),
                    onConfirm = function()
                        ns.BM2_DeleteFilter(f.id)
                        Apply()
                        Rebuild()
                    end,
                })
            end)

            local edit = CreateFrame("Button", nil, frow)
            edit:SetSize(14, 14)
            edit:SetPoint("RIGHT", del, "LEFT", -4, 0)
            edit:SetFrameLevel(frow:GetFrameLevel() + 1)
            edit:SetAlpha(0.5)
            local ex = edit:CreateTexture(nil, "OVERLAY")
            ex:SetAllPoints()
            if ex.SetSnapToPixelGrid then ex:SetSnapToPixelGrid(false); ex:SetTexelSnappingBias(0) end
            ex:SetTexture(MEDIA_FE .. "eui-edit.png")
            edit:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Edit"))
            end)
            edit:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                EllesmereUI.HideWidgetTooltip()
            end)
            edit:SetScript("OnClick", function()
                EditorInput({
                    title = EllesmereUI.L("Rename Filter"),
                    placeholder = f.name,
                    confirmText = EllesmereUI.L("Rename"),
                    cancelText = EllesmereUI.L("Cancel"),
                    onConfirm = function(text)
                        ns.BM2_RenameFilter(f.id, text)
                        Rebuild()
                    end,
                })
            end)
        end
        fy = fy - 27
    end
    local addFilterBtn = PopupButton(sideChild, SIDE_W - 16, 26, "Add Filter", function()
        EditorInput({
            title = EllesmereUI.L("Add Filter"),
            message = EllesmereUI.L("Name the new filter."),
            confirmText = EllesmereUI.L("Add"),
            cancelText = EllesmereUI.L("Cancel"),
            onConfirm = function(text)
                local f = ns.BM2_AddFilter((text and text ~= "" and text) or EllesmereUI.L("New Filter"))
                if f then fdSel = f.id end
                Rebuild()
            end,
        })
    end)
    addFilterBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, fy - 8)
    local sideBottom = fy - 8 - 26
    -- One-time copy of the Player Aura Bars filter setups INTO this library
    -- by name (same-named filters replaced, missing ones created). Ids here
    -- never change, so indicator assignments and banked spec-override forks
    -- stay valid. Hidden while that module is disabled.
    if EllesmereUI._PABFilterBridge then
        local copyBtn = PopupButton(sideChild, SIDE_W - 16, 26, EllesmereUI.L("Copy Player Auras Filters"), function()
            EllesmereUI:ShowConfirmPopup({
                title = EllesmereUI.L("Copy Player Auras Filters"),
                message = EllesmereUI.L("One-time copy of your Player Aura Bars filter setups into these filters. Same-named filters are OVERWRITTEN; the two lists stay separate afterwards."),
                confirmText = EllesmereUI.L("Copy"),
                cancelText = EllesmereUI.L("Cancel"),
                typeToConfirm = "Confirm",
                onConfirm = function()
                    local br = EllesmereUI._PABFilterBridge
                    if br and br.CopyIntoBM2() then
                        Apply()
                        Rebuild()
                    end
                end,
            })
        end)
        copyBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, sideBottom - 6)
        sideBottom = sideBottom - 6 - 26
    end
    sideChild:SetHeight(math.abs(sideBottom) + 8)
    local updSideThumb = AttachEditorScroll(sideScroll, sideChild)
    updSideThumb()

    -- LEFT: selected filter detail
    local sel
    for i = 1, #filters do if filters[i].id == fdSel then sel = filters[i] end end
    if not sel then return end

    local left = CreateFrame("Frame", nil, popup)
    left:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -44)
    left:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -(SIDE_W + 12), 12)
    left:SetFrameLevel(popup:GetFrameLevel() + 1)

    local nm = EllesmereUI.MakeFont(left, 13, nil, 1, 1, 1)
    nm:SetAlpha(0.9)
    nm:SetPoint("TOPLEFT", left, "TOPLEFT", 2, -2)
    nm:SetText(L(sel.name))
    if not sel.preset then
        local ren = CreateFrame("Button", nil, left)
        ren:SetSize(54, 16)
        ren:SetPoint("LEFT", nm, "RIGHT", 10, 0)
        ren:SetFrameLevel(left:GetFrameLevel() + 2)
        local rl = EllesmereUI.MakeFont(ren, 11, nil, ar, ag, ab)
        rl:SetAlpha(0.9)
        rl:SetPoint("LEFT")
        rl:SetText(EllesmereUI.L("Rename"))
        ren:SetScript("OnEnter", function() rl:SetAlpha(1) end)
        ren:SetScript("OnLeave", function() rl:SetAlpha(0.9) end)
        ren:SetScript("OnClick", function()
            EditorInput({
                title = EllesmereUI.L("Rename Filter"),
                placeholder = sel.name,
                confirmText = EllesmereUI.L("Rename"),
                cancelText = EllesmereUI.L("Cancel"),
                onConfirm = function(text)
                    ns.BM2_RenameFilter(sel.id, text)
                    Rebuild()
                end,
            })
        end)
    end

    -- Preset-universe spell search (identical list to the Extra Spells
    -- dropdown: curated primaries, name-sorted, spell icons, searchable):
    -- every spell already ON this filter is excluded -- checked or unchecked, curated
    -- or custom alike. Picking one adds it to the filter's Custom group (the same
    -- landing as Add Spell ID) and the editor rebuild re-lists without it.
    local searchDD = EllesmereUI.BuildVisOptsCBDropdown(
        left, 170, left:GetFrameLevel() + 5,
        function()
            local f = (ns.BM2_GetFilter and ns.BM2_GetFilter(sel.id)) or sel
            local universe = (ns.BM2_AllPresetSpells and ns.BM2_AllPresetSpells()) or {}
            local out = {}
            for i = 1, #universe do
                local id = universe[i]
                local onFilter = (f.spells and f.spells[id] ~= nil)
                    or (f.custom and f.custom[id])
                if not onFilter then
                    local nm = (ns.SPELL_NAME_BY_ID and ns.SPELL_NAME_BY_ID[id])
                        or (C_Spell.GetSpellName and C_Spell.GetSpellName(id))
                    out[#out + 1] = {
                        key = id, label = nm or tostring(id), noCheck = true,
                        icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id),
                    }
                end
            end
            table.sort(out, function(a, b)
                return tostring(a.label or a.key) < tostring(b.label or b.key)
            end)
            return out
        end,
        function() return false end, -- nothing listed is ever on the filter
        function(k, v)
            if v and ns.BM2_AddCustomSpell and ns.BM2_AddCustomSpell(sel.id, k) then
                Apply()
                Rebuild()
            end
        end,
        nil, 10, true)
    searchDD:ClearAllPoints()
    searchDD:SetPoint("TOPLEFT", left, "TOPLEFT", 2, -23)
    -- One-shot title: the checked-count summary a checkbox dropdown shows
    -- ("None") reads wrong for an action search, and every add rebuilds
    -- the editor, so the label never needs re-asserting.
    for _, r in ipairs({ searchDD:GetRegions() }) do
        if r.SetText and r.GetText then
            r:SetText(EllesmereUI.L("Search Spells"))
            break
        end
    end

    local addSpellBtn = PopupButton(left, 110, 24, "Add Spell ID", function()
        EditorInput({
            title = EllesmereUI.L("Add Spell ID"),
            message = EllesmereUI.L("Enter the spell ID to add to this filter."),
            confirmText = EllesmereUI.L("Add"),
            cancelText = EllesmereUI.L("Cancel"),
            onConfirm = function(text)
                local id = tonumber(text or "")
                if id and ns.BM2_AddCustomSpell(sel.id, id) then
                    Apply()
                    Rebuild()
                end
            end,
        })
    end)
    addSpellBtn:SetPoint("LEFT", searchDD, "RIGHT", 8, 0)

    -- Spell checkbox list: rows mirror the checkbox-dropdown widget's
    -- visuals exactly (16px box at 0.12/0.12/0.14, gray 0.4 border, accent
    -- fill inset 2, hover wash), grouped All Classes / class-colored / Custom.
    local scroll = CreateFrame("ScrollFrame", nil, left)
    scroll:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(POPUP_W - SIDE_W - 40)
    scroll:SetScrollChild(child)
    -- Standard smooth scroll + thin bar; every scroll write persists the
    -- position so rebuilds land the user back where they were.
    local _updSpellThumb, setSpellScroll = AttachEditorScroll(scroll, child,
        function(v) fdScrollPos = v end)

    local curated = (ns.BM2_DEFAULT_FILTER_SPELLS and sel.preset)
        and ns.BM2_DEFAULT_FILTER_SPELLS[sel.preset] or nil
    local byClass, customList = {}, {}
    for id in pairs(sel.spells) do
        local info = curated and curated[id]
        if info and info.class then
            byClass[info.class] = byClass[info.class] or {}
            table.insert(byClass[info.class], id)
        else
            table.insert(customList, id)
        end
    end
    -- Alphabetical by spell name (id tiebreak for identical names).
    local function NameOf(id)
        return (ns.SPELL_NAME_BY_ID and ns.SPELL_NAME_BY_ID[id])
            or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or tostring(id)
    end
    local function ByName(a, b)
        local na, nb = NameOf(a), NameOf(b)
        if na == nb then return a < b end
        return na < nb
    end
    for _, list in pairs(byClass) do table.sort(list, ByName) end
    table.sort(customList, ByName)

    local cy = 0
    local function SpellRow(id, classColor)
        local srow = CreateFrame("Button", nil, child)
        srow:SetHeight(24)
        srow:SetPoint("TOPLEFT", child, "TOPLEFT", 2, cy)
        srow:SetPoint("TOPRIGHT", child, "TOPRIGHT", -2, cy)
        srow:SetFrameLevel(child:GetFrameLevel() + 1)
        local hl = srow:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0)
        local box = CreateFrame("Frame", nil, srow)
        box:SetSize(16, 16)
        box:SetPoint("LEFT", srow, "LEFT", 6, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
        local boxBrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6)
        local chk = box:CreateTexture(nil, "ARTWORK")
        chk:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        chk:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        chk:SetColorTexture(eg.r, eg.g, eg.b, 1)
        local on = sel.spells[id] and true or false
        local ico = srow:CreateTexture(nil, "ARTWORK")
        ico:SetSize(22, 22)
        ico:SetPoint("LEFT", box, "RIGHT", 6, 0)
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if tex then ico:SetTexture(tex) end
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = (ns.SPELL_NAME_BY_ID and ns.SPELL_NAME_BY_ID[id])
            or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
        local lr, lg2, lb2 = 1, 1, 1
        if classColor then lr, lg2, lb2 = classColor.r, classColor.g, classColor.b end
        local lbl = EllesmereUI.MakeFont(srow, 13, nil, lr, lg2, lb2)
        lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        lbl:SetPoint("RIGHT", srow, "RIGHT", sel.custom[id] and -24 or -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(name or ("Spell " .. tostring(id)))
        -- Toggles update IN PLACE -- a rebuild here would reset the list
        -- scroll position out from under the cursor.
        local function UpdateRow()
            on = sel.spells[id] and true or false
            if on then
                chk:Show()
                if boxBrd and boxBrd.SetColor then boxBrd:SetColor(eg.r, eg.g, eg.b, 0.8) end
            else
                chk:Hide()
                if boxBrd and boxBrd.SetColor then boxBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
            end
            lbl:SetAlpha(on and 0.9 or 0.45)
            -- Dim the spell icon with the text (it stayed full-bright).
            ico:SetAlpha(on and 1 or 0.45)
            ico:SetDesaturated(not on)
        end
        UpdateRow()
        srow:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.04) end)
        srow:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, 0) end)
        srow:SetScript("OnClick", function()
            ns.BM2_SetSpellState(sel.id, id, not on)
            Apply()
            UpdateRow()
        end)
        if sel.custom[id] then
            local del = CreateFrame("Button", nil, srow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", srow, "RIGHT", -6, 0)
            del:SetFrameLevel(srow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then dx:SetSnapToPixelGrid(false); dx:SetTexelSnappingBias(0) end
            dx:SetTexture(MEDIA_FE .. "eui-close.png")
            del:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
            del:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
            del:SetScript("OnClick", function()
                ns.BM2_SetSpellState(sel.id, id, nil)
                Apply()
                Rebuild()
            end)
        end
        cy = cy - 29
    end
    local function GroupHeader(text)
        local hdr = EllesmereUI.MakeFont(child, 14, nil, 0.5, 0.5, 0.5)
        hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 2, cy - 10)
        hdr:SetText(text)
        local line = child:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", hdr, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", child, "RIGHT", -10, 0)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        cy = cy - 30
    end
    -- Custom leads (the user's own additions), then All Classes, then the class groups.
    if #customList > 0 then
        GroupHeader(EllesmereUI.L("Custom"))
        for i = 1, #customList do SpellRow(customList[i]) end
    end
    if byClass.ALL and #byClass.ALL > 0 then
        GroupHeader(EllesmereUI.L("All Classes"))
        for i = 1, #byClass.ALL do SpellRow(byClass.ALL[i]) end
    end
    for c = 1, #CLASS_ORDER do
        local cls = CLASS_ORDER[c]
        local list = byClass[cls]
        if list and #list > 0 then
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            local cname = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or cls
            GroupHeader(cc and ("|c" .. cc.colorStr .. cname .. "|r") or cname)
            for i = 1, #list do SpellRow(list[i], cc) end
        end
    end
    if cy == 0 then
        local empty = EllesmereUI.MakeFont(child, 12, nil, 1, 1, 1)
        empty:SetAlpha(0.4)
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -6)
        empty:SetText(EllesmereUI.L("No spells yet. Add spell IDs above."))
        cy = -30
    end
    child:SetHeight(math.abs(cy) + 10)

    -- Restore the preserved scroll position (rebuilds from add/remove/
    -- rename land the user back where they were, clamped to the new range).
    setSpellScroll(fdScrollPos)
end

-- "ASSIGNED BUFFS" section for the legacy BM page's settings scroll: one
-- standard DualRow -- left = "Filters" checkbox dropdown (the shared
-- BuildVisOptsCBDropdown widget) with an inline accent "Edit Filters" link,
-- right = "Extra Spells" searchable checkbox dropdown over the curated
-- spell universe plus the indicator's custom ids, with an inline accent
-- "Custom ID" link that opens the standard input popup. Built on the
-- canonical placeholder-dropdown hosting pattern (hide rgn._control, mount
-- the CB dropdown, re-point, register its refresh).
function ns.BMP_BuildAssignedFilters(parent, sy, ind, fontPath)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    if not (W and PP) then return sy end
    local hh
    local _r
    _r, hh = W:SectionHeader(parent, "ASSIGNED BUFFS", sy); sy = sy - hh

    local row
    row, hh = W:DualRow(parent, sy,
        { type = "dropdown", text = "Filters",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end },
        { type = "dropdown", text = "Extra Spells",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end }); sy = sy - hh

    -- LEFT: Filters checkbox dropdown; "Edit Filters" rides the menu as a
    -- pinned top action with a divider (the CDM spell-picker pattern).
    -- TWO-LANE rows: the left checkbox SHOWS a filter's spells (ind.filters,
    -- the classic union), the right red box HIDES them (ind.negFilters --
    -- dropped from the resolved union in BM2_ResolveSpellsOwn; direct Extra
    -- Spells win over the hide lane). Lanes are mutually exclusive per filter.
    do
        local rgn = row._leftRegion
        if rgn._control then rgn._control:Hide() end
        -- Dynamic items (function): the filter list re-evaluates on every
        -- menu open, so filters added/renamed in the editor appear live.
        local function FilterItems()
            local filters = (ns.BM2_Filters and ns.BM2_Filters()) or {}
            local items = {
                { isTopAction = true, label = "Edit Filters", onClick = function()
                    ns.BMP_ShowFilterEditor()
                end },
                { isHeader = true, label = "Show", rightLabel = "Hide" },
            }
            for i = 1, #filters do
                items[#items + 1] = { key = filters[i].id, label = filters[i].name, dual = true }
            end
            return items
        end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 190, rgn:GetFrameLevel() + 2,
            FilterItems,
            function(k, neg)
                if neg then
                    return ind.negFilters and ind.negFilters[k] == true
                end
                return ind.filters and ind.filters[k] and true or false
            end,
            function(k, v, neg)
                -- Two-lane write: checking one lane clears the other.
                if neg then
                    ind.negFilters = ind.negFilters or {}
                    ind.negFilters[k] = v and true or nil
                    if not next(ind.negFilters) then ind.negFilters = nil end
                    if v and ind.filters then ind.filters[k] = nil end
                else
                    if not ind.filters then ind.filters = {} end
                    ind.filters[k] = v and true or nil
                    if v and ind.negFilters then
                        ind.negFilters[k] = nil
                        if not next(ind.negFilters) then ind.negFilters = nil end
                    end
                end
                if ns.BM2_Invalidate then ns.BM2_Invalidate() end
                if ns.ReloadFrames then ns.ReloadFrames() end
            end,
            nil, 12)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- RIGHT: Extra Spells searchable checkbox dropdown; "Custom Spell ID"
    -- rides the menu as a pinned top action above the search bar.
    do
        local rgn = row._rightRegion
        if rgn._control then rgn._control:Hide() end
        local function HasDirect(id)
            local sp = ind.spells
            if not sp then return false end
            for i = 1, #sp do if sp[i] == id then return true end end
            return false
        end
        local function ShowCustomIdPopup()
            EllesmereUI:ShowInputPopup({
                title = EllesmereUI.L("Add Spell ID"),
                message = EllesmereUI.L("Enter the spell ID to track on this indicator."),
                confirmText = EllesmereUI.L("Add"),
                cancelText = EllesmereUI.L("Cancel"),
                onConfirm = function(text)
                    local id = tonumber(text or "")
                    if id and id > 0 and not HasDirect(id) then
                        ind.spells = ind.spells or {}
                        ind.spells[#ind.spells + 1] = id
                        if ns.ReloadFrames then ns.ReloadFrames() end
                        EllesmereUI:RefreshPage(true)
                    end
                end,
            })
        end
        -- Universe = curated preset primaries (name-sorted) plus any custom
        -- ids already on the indicator that fall outside it.
        -- Two groups: "Selected" = everything currently assigned (universe
        -- picks AND custom ids alike), "Presets" = the remaining curated
        -- universe. Dynamic items (function): re-evaluated on every menu open, so
        -- grouping and the filter-covered exclusion never go stale. Spells already
        -- provided by the ASSIGNED FILTERS' enabled spells are excluded from Presets
        -- (adding them as extras would be redundant); direct picks always show under
        -- Selected so they can be unchecked.
        local function SpellEntry(id)
            local name = (ns.SPELL_NAME_BY_ID and ns.SPELL_NAME_BY_ID[id])
                or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
            return { key = id, label = (name or ("Spell " .. tostring(id))),
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) }
        end
        local function ByLabel(a, b) return a.label < b.label end
        local function ExtraItems()
            local covered = {}
            if ind.filters and ns.BM2_GetFilter then
                for fid in pairs(ind.filters) do
                    local f = ns.BM2_GetFilter(fid)
                    if f then
                        for id, on in pairs(f.spells) do
                            if on then covered[id] = true end
                        end
                    end
                end
            end
            local universe = (ns.BM2_AllPresetSpells and ns.BM2_AllPresetSpells()) or {}
            local selected, rest = {}, {}
            local seen = {}
            local sp = ind.spells or {}
            for i = 1, #sp do
                seen[sp[i]] = true
                selected[#selected + 1] = SpellEntry(sp[i])
            end
            for i = 1, #universe do
                local id = universe[i]
                if not seen[id] and not covered[id] then rest[#rest + 1] = SpellEntry(id) end
            end
            table.sort(selected, ByLabel)
            table.sort(rest, ByLabel)
            local items = {
                { isTopAction = true, label = "Custom Spell ID", onClick = ShowCustomIdPopup },
            }
            if #selected > 0 then
                items[#items + 1] = { isHeader = true, label = "Selected" }
                for i = 1, #selected do items[#items + 1] = selected[i] end
            end
            items[#items + 1] = { isHeader = true, label = "Presets" }
            for i = 1, #rest do items[#items + 1] = rest[i] end
            return items
        end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 190, rgn:GetFrameLevel() + 2,
            ExtraItems,
            HasDirect,
            function(k, v)
                ind.spells = ind.spells or {}
                if v then
                    if not HasDirect(k) then ind.spells[#ind.spells + 1] = k end
                else
                    for i = #ind.spells, 1, -1 do
                        if ind.spells[i] == k then table.remove(ind.spells, i) end
                    end
                end
                if ns.ReloadFrames then ns.ReloadFrames() end
            end,
            nil, 10, true)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- CUSTOM ORDER (icon/square indicators): opt-in fixed arrangement. The
    -- cog's drag list writes ind.spellOrder; the runtime renders one engine
    -- group per arranged spell in that order (BmSegments in the containers
    -- file) instead of the engine's default in-group sorting.
    if ind.type == "icon" or ind.type == "square" then
        -- Default presentation for anything the user has not arranged yet:
        -- the editing spec's own class spells lead, then class-agnostic
        -- (consumables/no hint), then other classes' (externals etc.). The
        -- STORED arrangement is never re-prioritized -- it is the user's.
        local function EditingClassToken()
            local key = ns._bmSelectedSpecKey
            local specs = ns.BM_HEALER_SPECS
            if key and specs then
                for i = 1, #specs do
                    if specs[i].key == key then return specs[i].classToken end
                end
            end
            local _, cls = UnitClass("player")
            return cls
        end
        local function PrioritizeResolved(list)
            local cls = EditingClassToken()
            local sc = ns.BM2_SpellClass or {}
            local mine, shared, other = {}, {}, {}
            for i = 1, #list do
                local id = list[i]
                local c = sc[id]
                if c == cls then
                    mine[#mine + 1] = id
                elseif c == nil or c == "ALL" then
                    shared[#shared + 1] = id
                else
                    other[#other + 1] = id
                end
            end
            for i = 1, #shared do mine[#mine + 1] = shared[i] end
            for i = 1, #other do mine[#mine + 1] = other[i] end
            return mine
        end
        local orow
        orow, hh = W:DualRow(parent, sy,
            { type = "toggle", text = "Custom Order",
              tooltip = "Show this indicator's buffs in the exact order you arrange (the first 10 arranged buffs are guaranteed; any beyond follow the default sorting).",
              getValue = function() return ind.customOrder == true end,
              setValue = function(v)
                  ind.customOrder = v or nil
                  if v and not ind.spellOrder then
                      -- Seed the arrangement from the current resolved list so
                      -- the ordered groups engage immediately; the cog only
                      -- rearranges from there.
                      local r = (ns.BM2_ResolveSpells and ns.BM2_ResolveSpells(ind)) or ind.spells or {}
                      ind.spellOrder = PrioritizeResolved(r)
                  end
                  if ns.ReloadFrames then ns.ReloadFrames() end
              end },
            { type = "label", text = "" }); sy = sy - hh
        do
            local rgn = orow._leftRegion
            -- Effective arrangement: stored order first (stale ids skipped),
            -- then any newly-resolved spells appended in prioritized order.
            -- Items snapshot at popup build like the Class Sorting cog; a
            -- page rebuild re-snapshots.
            local function OrderItems()
                local resolved = (ns.BM2_ResolveSpells and ns.BM2_ResolveSpells(ind)) or ind.spells or {}
                local present, seen, out = {}, {}, {}
                for i = 1, #resolved do present[resolved[i]] = true end
                local function Add(id)
                    local nm = (ns.SPELL_NAME_BY_ID and ns.SPELL_NAME_BY_ID[id])
                        or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
                    out[#out + 1] = { key = id, label = nm or ("Spell " .. tostring(id)) }
                end
                local so = ind.spellOrder
                if so then
                    for i = 1, #so do
                        local id = so[i]
                        if present[id] and not seen[id] then
                            seen[id] = true
                            Add(id)
                        end
                    end
                end
                local rest = {}
                for i = 1, #resolved do
                    if not seen[resolved[i]] then rest[#rest + 1] = resolved[i] end
                end
                rest = PrioritizeResolved(rest)
                for i = 1, #rest do Add(rest[i]) end
                return out
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Custom Order",
                rows = {
                    { type = "reorder", label = "Buff Order", hint = "Drag to Reorder",
                      maxVisible = 12,
                      items = OrderItems,
                      set = function(keys)
                          ind.spellOrder = keys
                          if ns.ReloadFrames then ns.ReloadFrames() end
                      end,
                      disabled = function() return ind.customOrder ~= true end,
                      disabledTooltip = "Custom Order" },
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
    end

    return sy
end

-- Indicator detail pane for the v2 BM page.









