if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBar_Options.lua
--  Registers the Action Bars module. All get/set calls go to EAB.db.profile.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIActionBars"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page
local EAB = ns.EAB
local VisibilityCompat = EAB and EAB.VisibilityCompat
-- Anchor dropdown for the three button texts (keybind / charges / macro name);
-- "default" = stock placement, stored as nil in the profile.
local TEXT_ANCHOR_LABELS = {
    default = "Default", TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}
local TEXT_ANCHOR_DROPDOWN_ORDER = { "default" }
for i, a in ipairs(EAB and EAB.TEXT_ANCHOR_ORDER or {}) do TEXT_ANCHOR_DROPDOWN_ORDER[i + 1] = a end

-- Fall back to LibStub if Action Bars hasn't added the helper yet.
-- Masque can be available even before we've created a group.
local function IsMasqueAvailable()
    if ns.IsMasqueAvailable then
        return ns.IsMasqueAvailable()
    end
    return LibStub and LibStub("Masque", true) ~= nil
end


-- The registry offsets/shifts a border renders with when the user has set none
-- (the Border Options cog's shown Shift defaults; the Width/Height Offset row
-- resolves its own): its step's "actionbars" entry, scaled to an exact size
-- (EllesmereUI.BorderPx) the way ApplyBorderStyle scales it; px nil = the
-- step's own values, the legacy path.
local function ShownBorderDefaults(tex, sizeKey, step, px)
    local dox, doy, dsx, dsy = EllesmereUI.GetBorderDefaults("actionbars", tex, sizeKey)
    if px then
        local gamePP = EllesmereUI.PP
        local EDGE_MAP = EllesmereUI.BORDER_EDGE_MAP
        local f = (px * gamePP.mult) / (EDGE_MAP[step] or EDGE_MAP[1])
        dox, doy, dsx, dsy = gamePP.Snap(dox * f), gamePP.Snap(doy * f), gamePP.Snap(dsx * f), gamePP.Snap(dsy * f)
    end
    return dox, doy, dsx, dsy
end

-------------------------------------------------------------------------------
--  Section / page names  (edit here to rename everywhere)
-------------------------------------------------------------------------------
local PAGE_DISPLAY        = "Bar Display"
local PAGE_XPBAR          = "XP Bar"
local PAGE_MENUBAGSREP    = "Menu, Bags & Rep Bars"
local PAGE_ANIMATIONS     = "Bar Animations"
local SECTION_ICON_APPEARANCE = "ICONS"
local SECTION_LAYOUT      = "LAYOUT"
local SECTION_TEXT        = "TEXT"
local SECTION_VISIBILITY  = "VISIBILITY"

-- EllesmereUI is created by another addon in the suite; wait for it.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP
    if not EAB or not EAB.db then return end

    ---------------------------------------------------------------------------
    --  Local references from the addon namespace
    ---------------------------------------------------------------------------
    local BAR_DROPDOWN_VALUES = ns.BAR_DROPDOWN_VALUES
    local BAR_DROPDOWN_ORDER  = ns.BAR_DROPDOWN_ORDER
    local VISIBILITY_ONLY     = ns.VISIBILITY_ONLY
    local BAR_LOOKUP          = ns.BAR_LOOKUP
    local DATA_BAR            = ns.DATA_BAR or {}

    -- Filtered bar list for multi-edit: action bars only (no MicroBar/BagBar)
    local GROUP_BAR_ORDER = {}
    local MASQUE_BAR_ORDER = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        if not VISIBILITY_ONLY[key] then
            GROUP_BAR_ORDER[#GROUP_BAR_ORDER + 1] = key
            local info = BAR_LOOKUP[key]
            if info then
                MASQUE_BAR_ORDER[#MASQUE_BAR_ORDER + 1] = key
            end
        end
    end

    -- Bar enabled state; we control all bars, so default is true.
    local function IsBarEnabled(barKey)
        if not EAB or not EAB.db then return true end
        local s = EAB.db.profile.bars[barKey]
        if s and s.enabled ~= nil then return s.enabled end
        return true
    end

    local InCombatLockdown = InCombatLockdown
    local pcall = pcall
    local floor = math.floor
    local RANGE_INDICATOR = RANGE_INDICATOR or "\226\128\162"

    ---------------------------------------------------------------------------
    --  Helpers
    ---------------------------------------------------------------------------
    local _selectedBarKey = "MainBar"
    local function SelectedKey()
        return _selectedBarKey
    end

    local function SB()
        return EAB.db.profile.bars[SelectedKey()] or {}
    end

    local function IsVisOnly()
        return VISIBILITY_ONLY[SelectedKey()]
    end

    local function IsDataBar()
        return DATA_BAR[SelectedKey()]
    end

    -- First button of a bar (source of default size): our EABButton, else the
    -- native Blizzard button. nil for custom bars (Bar9/Bar10) which have no
    -- native button -- callers default the size; avoids concatenating a nil prefix.
    local function FirstBarButton(key)
        local eb = ns.barButtons and ns.barButtons[key]
        if eb and eb[1] then return eb[1] end
        local bi = BAR_LOOKUP[key]
        if bi and bi.buttonPrefix then return _G[bi.buttonPrefix .. "1"] end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Ordered dropdown values for the bar selector
    ---------------------------------------------------------------------------
    local barLabels = {}
    local barOrder  = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        -- XP lives on the "XP Bar" tab and Micro/Bag/Rep/Favor on the "Menu,
        -- Bags & Rep Bars" tab, not the Bar Display bar selector.
        if key ~= "MicroBar" and key ~= "BagBar" and key ~= "XPBar" and key ~= "RepBar" and key ~= "FavorBar" then
            barLabels[key] = BAR_DROPDOWN_VALUES[key]
            barOrder[#barOrder + 1] = key
        end
    end

    -- Unlock Mode "Element Options" pre-selects a bar before the Bar Display page
    -- builds (mirrors the unit-frame path): direct setter (already built) + pending
    -- value consumed at build time. Both ignore non-dropdown keys (Micro/Bag/XP/Rep)
    -- so the selector never blanks.
    EllesmereUI._setActionBarKey = function(key)
        if barLabels[key] then _selectedBarKey = key end
    end
    EllesmereUI._consumePendingActionBarSelect = function()
        local pending = EllesmereUI._pendingActionBarSelect
        EllesmereUI._pendingActionBarSelect = nil
        if pending and barLabels[pending] then _selectedBarKey = pending end
    end

    ---------------------------------------------------------------------------
    --  Edit Overlay System
    --  Non-draggable unlock-mode-style overlay at the real bar position during
    --  Single Bar Edit. XP/Rep: always when selected. BagBar/MicroBar: only
    --  when hidden or mouseover-fade.
    ---------------------------------------------------------------------------
    local EXTRA_BARS = ns.EXTRA_BARS or {}
    local editOverlayFrame = nil  -- reusable overlay frame

    local function GetEditOverlayTarget(barKey)
        -- Data bars: show overlay only if not using Blizzard data bars
        if DATA_BAR[barKey] then
            if EAB.db.profile.useBlizzardDataBars then return nil end
            local df = ns.dataBarFrames and ns.dataBarFrames[barKey]
            return df
        end
        -- BagBar / MicroBar: show only when hidden or mouseover
        if barKey == "BagBar" or barKey == "MicroBar" then
            local s = EAB.db.profile.bars[barKey]
            if s and (s.alwaysHidden or s.mouseoverEnabled) then
                for _, info in ipairs(EXTRA_BARS) do
                    if info.key == barKey and info.frameName then
                        return _G[info.frameName]
                    end
                end
            end
        end
        return nil
    end

    local function ShowEditOverlay(barKey)
        local target = GetEditOverlayTarget(barKey)
        if not target then
            if editOverlayFrame then editOverlayFrame:Hide() end
            return
        end

        if not editOverlayFrame then
            editOverlayFrame = CreateFrame("Frame", "EllesmereEAB_EditOverlay", UIParent)
            editOverlayFrame:SetFrameStrata("HIGH")
            editOverlayFrame:SetFrameLevel(100)
            editOverlayFrame:EnableMouse(false)  -- non-interactive, no dragging

            local bg = editOverlayFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.075, 0.113, 0.141, 0.85)
            editOverlayFrame._bg = bg

            if EllesmereUI and EllesmereUI.MakeBorder then
                local eg = EllesmereUI.ELLESMERE_GREEN
                local ar, ag, ab = 1, 1, 1
                if eg then ar, ag, ab = eg.r, eg.g, eg.b end
                editOverlayFrame._border = EllesmereUI.MakeBorder(editOverlayFrame, ar, ag, ab, 0.6, EllesmereUI.PanelPP)
            end

            local label = editOverlayFrame:CreateFontString(nil, "OVERLAY")
            local fontPath = EllesmereUI and EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
            label:SetFont(fontPath, 10, EllesmereUI.GetFontOutlineFlag())
            label:SetTextColor(1, 1, 1, 0.75)
            label:SetPoint("CENTER")
            label:SetWordWrap(false)
            editOverlayFrame._label = label
        end

        local s = target:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local w = (target:GetWidth() or 50) * s / uiS
        local h = (target:GetHeight() or 50) * s / uiS
        editOverlayFrame:SetSize(w, h)

        local left, top = target:GetLeft(), target:GetTop()
        if left and top then
            local uiH = UIParent:GetHeight()
            local cx = left * s / uiS + w * 0.5
            local cy = top * s / uiS - h * 0.5
            editOverlayFrame:ClearAllPoints()
            editOverlayFrame:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy - uiH)
        end

        local labelText = BAR_DROPDOWN_VALUES[barKey] or barKey
        editOverlayFrame._label:SetText(labelText)
        editOverlayFrame:Show()
    end

    local function HideEditOverlay()
        if editOverlayFrame then editOverlayFrame:Hide() end
    end

    EllesmereUI:RegisterOnHide(HideEditOverlay)

    -- Sync Edit Mode icon counts on panel close (numIcons may have changed).
    EllesmereUI:RegisterOnHide(function() EAB:SyncEditModeIcons() end)

    ---------------------------------------------------------------------------
    --  Live Preview System
    --  Child frames are created ONCE; :Update() re-reads DB values and applies
    --  them to the existing objects. Widget callbacks call UpdatePreview(): no
    --  frame creation, no GC pressure, just SetPoint/SetSize/SetColorTexture/
    --  SetTexCoord on already-existing objects.
    ---------------------------------------------------------------------------
    -- Mutable state shared with the page builders under ActionBars_Options\.
    -- A table instead of locals so every file reads and writes the live value.
    -- activePreview: reference to the current preview frame (if any).
    local optState = {}
    local headerFixedH = 0 -- fixed height in content header (dropdown + label + padding), excluding preview
    local _barsHeaderBuilder  -- stored header builder for cache restore
    local _abPreviewHintFS                 -- hint FontString for Single Bar Edit
    local barsHeaderBaseH = 0              -- bars header height WITHOUT hint

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    -- Lightweight refresh: re-read settings, update visuals.
    local function UpdatePreview()
        -- Recover activePreview from content header if lost (e.g. page cache restore)
        if not optState.activePreview and EllesmereUI._contentHeaderPreview then
            optState.activePreview = EllesmereUI._contentHeaderPreview
        end
        if optState.activePreview and optState.activePreview.Update then
            optState.activePreview:Update()
        end
    end

    -- Full refresh also recalculates content header height (for bar scale changes)
    local function UpdatePreviewAndResize()
        if not optState.activePreview and EllesmereUI._contentHeaderPreview then
            optState.activePreview = EllesmereUI._contentHeaderPreview
        end
        if optState.activePreview and optState.activePreview.Update then
            optState.activePreview:Update()
            if headerFixedH > 0 then
                local hintH = (not IsPreviewHintDismissed()) and 29 or 0
                local wrapH = optState.activePreview._wrapper and optState.activePreview._wrapper:GetHeight() or (optState.activePreview:GetHeight() * optState.activePreview:GetScale())
                local newTotal = headerFixedH + wrapH + hintH
                EllesmereUI:UpdateContentHeaderHeight(newTotal)
            end
        end
    end

    EllesmereUI:RegisterOnShow(UpdatePreview)

    -- Rebuild the preview on spec change (new talent group).
    do
        local specChangeFrame = CreateFrame("Frame")
        specChangeFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        specChangeFrame:SetScript("OnEvent", function(self, event)
            if event == "ACTIVE_TALENT_GROUP_CHANGED" and _barsHeaderBuilder then
                optState.activePreview = nil
                if EllesmereUI:IsShown() and EllesmereUI:GetActiveModule() == "EllesmereUIActionBars" then
                    EllesmereUI:SetContentHeader(_barsHeaderBuilder)
                    UpdatePreviewAndResize()
                end
            end
        end)
    end




    ---------------------------------------------------------------------------
    --  Short labels for sync icon multi-apply
    ---------------------------------------------------------------------------
    local SHORT_LABELS = {
        MainBar  = "Bar 1",
        Bar2     = "Bar 2",
        Bar3     = "Bar 3",
        Bar4     = "Bar 4",
        Bar5     = "Bar 5",
        Bar6     = "Bar 6",
        Bar7     = "Bar 7",
        Bar8     = "Bar 8",
        Bar9     = "Bar 9",
        Bar10    = "Bar 10",
        StanceBar = "Stance",
        PetBar   = "Pet",
        MicroBar = "Micro",
        BagBar   = "Bags",
        XPBar    = "XP",
        RepBar   = "Rep",
        FavorBar = "Favor",
    }

    -- Spec Overrides capture: label captured entries with the selected bar's element (e.g. "Action Bars > Bar 1 > ...").
    EllesmereUI.RegisterCaptureContext("EllesmereUIActionBars", function()
        local key = SelectedKey()
        return SHORT_LABELS[key] or key
    end)

    -- Legacy boolean flags and the visibility-mode dropdown must stay in sync: the runtime reads both shapes.
    local function GetVisibilityKey(s)
        if not VisibilityCompat then
            return s.barVisibility or "always"
        end
        return VisibilityCompat.Normalize(s)
    end

    local function ApplyVisibilityKey(s, v)
        if VisibilityCompat then
            VisibilityCompat.ApplyMode(s, v)
            return
        end

        s.barVisibility = v
        s.alwaysHidden = (v == "never")

        local wasMouseover = s.mouseoverEnabled
        s.mouseoverEnabled = (v == "mouseover")
        if v == "mouseover" then
            if not wasMouseover then
                s._savedBarAlpha = s.mouseoverAlpha or 1
            end
            s.mouseoverAlpha = 0
        elseif wasMouseover and s._savedBarAlpha then
            s.mouseoverAlpha = s._savedBarAlpha
            s._savedBarAlpha = nil
        end

        s.combatHideEnabled = (v == "out_of_combat")
        s.combatShowEnabled = (v == "in_combat")
    end

    local function CopyVisibilitySettings(dst, src, dstKey)
        -- The merged Visibility control owns the option booleans too, so every copy
        -- carries them alongside the mode selection.
        local optKeys = EllesmereUI.VIS_OPT_KEYS
        if optKeys then
            for i = 1, #optKeys do dst[optKeys[i]] = src[optKeys[i]] or nil end
        end
        if VisibilityCompat then
            -- Pet Bar ignores group modes: strip them from a copied multi-selection.
            VisibilityCompat.Copy(dst, src, dstKey == "PetBar")
            return
        end

        local v = src.barVisibility or "always"
        dst.barVisibility = v
        dst.visibilityMatch = src.visibilityMatch or nil
        dst.alwaysHidden = src.alwaysHidden
        dst.mouseoverEnabled = src.mouseoverEnabled
        dst.mouseoverAlpha = src.mouseoverAlpha
        dst._savedBarAlpha = src._savedBarAlpha
        dst.combatHideEnabled = src.combatHideEnabled
        dst.combatShowEnabled = src.combatShowEnabled
        dst.dragShow = src.dragShow
    end




    -- An End Caps row: the End Caps checklist (Left Endcap / Right Endcap) and
    -- its cog (the EllesmereUI style's art, size, offsets), per bar through the
    -- runtime's own readers (ns.AB_CapsSides / AB_CapsVal: an unset Action Bar
    -- 1 key reads the profile-wide one, a bar carrying one of bar 1's caps reads
    -- bar 1's). Horizontal bars only: the art sits at the bar's two ends.
    --   o.key()          the bar
    --   o.store()        its settings table
    --   o.label          the row text
    --   o.vertical()     true greys the row
    --   o.write(k, v)    stores cog value v under k (k nil: the checklist has
    --                    already stored both sides) and repaints
    --   o.copyApply(key) repaints another bar after an Apply to All copy
    --   o.syncKeys, o.syncLabels  the Apply to All link's bars (nil = no link)
    local function EndCapsCtl(o)
        local C = {}
        C.stock = EllesmereUI.BlizzStyle.Get("actionbars") and true or false
        C.forever = C.stock and EllesmereUI.BlizzStyle.Forever("actionbars")
        C.Vertical = o.vertical
        -- True while the bar shows a cap at neither end.
        function C.Off()
            local l, r = ns.AB_CapsSides(o.key())
            return not (l or r)
        end
        -- The row slot C.Build swaps for the checklist; its label carries the
        -- tooltip and dims on a vertical bar.
        function C.Cfg()
            local classic = EllesmereUI.BlizzStyle.Active("actionbars") == "classic"
            return { type="dropdown", text=o.label,
              tooltip=(not C.stock) and "Which ends of the bar show end cap art; the cog picks the art."
                  or classic and "Which ends of the bar show the gryphons."
                  or "Which ends of the bar show the gryphons or wyverns.",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              disabled=C.Vertical,
              disabledTooltip="Vertical Orientation", requireState="disabled",
              getValue=function() return "__placeholder" end,
              setValue=function() end }
        end
        -- A bar's whole end cap setting onto bar `dst`, as this bar resolves
        -- it (sides, the EllesmereUI style's art, size, offsets).
        function C.CopyTo(dst)
            local src = o.key()
            local d = EAB.db.profile.bars[dst]
            if dst == src or not d then return end
            d.endCapLeft, d.endCapRight = ns.AB_CapsSides(src)
            if not C.stock then d.endCapArt = ns.AB_CapsArt(src) end
            local _, dx, dy, sc = ns.AB_CapsTweak(src)
            d.endCapScale, d.endCapOffsetX, d.endCapOffsetY = sc, dx, dy
            o.copyApply(dst)
        end
        function C.Same(key)
            local src = o.key()
            local sl, sr = ns.AB_CapsSides(src)
            local kl, kr = ns.AB_CapsSides(key)
            if sl ~= kl or sr ~= kr then return false end
            if not (sl or sr) then return true end
            if not C.stock and ns.AB_CapsArt(src) ~= ns.AB_CapsArt(key) then return false end
            local _, sx, sy, ss = ns.AB_CapsTweak(src)
            local _, kx, ky, ks = ns.AB_CapsTweak(key)
            return ss == ks and sx == kx and sy == ky
        end
        -- The checklist in `rgn` (a DualRow half built from C.Cfg), its cog
        -- and its Apply to All link.
        function C.Build(rgn)
            if EllesmereUI._prebuilding then return end
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                { { key = "L", label = "Left Endcap" }, { key = "R", label = "Right Endcap" } },
                function(k)
                    local l, r = ns.AB_CapsSides(o.key())
                    if k == "L" then return l end
                    return r
                end,
                function(k, v)
                    -- Both sides are written, the untouched one as the bar
                    -- shows it now: a written side never reads a default.
                    local s = o.store()
                    local l, r = ns.AB_CapsSides(o.key())
                    if k == "L" then l = v and true or false else r = v and true or false end
                    s.endCapLeft, s.endCapRight = l, r
                    o.write()
                end, nil, nil, nil, nil, nil,
                -- Spec Overrides see each click as it happens (the slot's capture).
                { notifyWrites = true })
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            -- The checklist has no disabled state of its own: grey it and
            -- block clicks on a vertical bar (the row label explains).
            local function ApplyCapsDisabled()
                local off = C.Vertical()
                cbDD:SetAlpha(off and 0.3 or 1)
                cbDD:EnableMouse(not off)
            end
            ApplyCapsDisabled()
            EllesmereUI.RegisterWidgetRefresh(ApplyCapsDisabled)

            local rows = {}
            if not C.stock then
                -- WoW Forever's own art exists only on that client.
                local values = { blizzard="Modern", classic="Classic" }
                local order = { "blizzard", "classic" }
                if EllesmereUI.IS_FOREVER then
                    values.forever = "WoW Forever"
                    order[#order + 1] = "forever"
                end
                rows[#rows + 1] = { type="dropdown", label="Art", values=values, order=order,
                  tooltip=EllesmereUI.IS_FOREVER
                      and "Modern shows gryphons or wyverns by faction, Classic the vanilla gryphons, WoW Forever this client's own."
                      or "Modern shows gryphons or wyverns by faction, Classic the vanilla gryphons.",
                  get=function() return ns.AB_CapsArt(o.key()) end,
                  set=function(v) o.write("endCapArt", v) end }
            end
            rows[#rows + 1] = { type="slider", label="Size", min=50, max=200, step=5,
              tooltip="Percent of the end caps' normal size.",
              get=function() return ns.AB_CapsVal(o.key(), "endCapScale") or 100 end,
              set=function(v) o.write("endCapScale", v) end }
            rows[#rows + 1] = { type="slider", label="X Offset", min=-100, max=100, step=1,
              tooltip="Positive values move both end caps away from the bar.",
              get=function() return ns.AB_CapsVal(o.key(), "endCapOffsetX") or 0 end,
              set=function(v) o.write("endCapOffsetX", v) end }
            rows[#rows + 1] = { type="slider", label="Y Offset", min=-100, max=100, step=1,
              get=function() return ns.AB_CapsVal(o.key(), "endCapOffsetY") or 5 end,
              set=function(v) o.write("endCapOffsetY", v) end }
            EllesmereUI.BuildInlineCog(rgn, {
                title = "End Cap Settings",
                icon = C.stock and EllesmereUI.RESIZE_ICON or nil,
                disabled = function()
                    return C.Vertical() or C.Off()
                end,
                disabledTooltip = function()
                    if C.Vertical() then return EllesmereUI.DisabledTooltip("Vertical Orientation", "disabled") end
                    return EllesmereUI.DisabledTooltip("Left Endcap or Right Endcap")
                end,
                rawTooltip = true,
                rows = rows,
            })

            if o.syncKeys then
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply End Caps to all Bars",
                    onClick = function()
                        for _, key in ipairs(o.syncKeys) do C.CopyTo(key) end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        for _, key in ipairs(o.syncKeys) do
                            if not C.Same(key) then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = o.syncKeys,
                        elementLabels = o.syncLabels,
                        getCurrentKey = function() return o.key() end,
                        onApply       = function(checkedKeys)
                            for _, key in ipairs(checkedKeys) do C.CopyTo(key) end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
        end
        return C
    end

    local function BuildSharedBarSettings(parent, y)
        local W = EllesmereUI.Widgets

        ---------------------------------------------------------------
        --  Unified Get / Set / DB abstraction
        ---------------------------------------------------------------
        local function SGet(key)
            return SB()[key]
        end
        local function SSet(key, val, applyFn)
            SB()[key] = val
            if applyFn then applyFn(SelectedKey()) end
            EllesmereUI:RefreshPage()
        end
        local function SDB()
            return SB()
        end
        local function SVal(key, default)
            local v = SB()[key]
            return v ~= nil and v or default
        end
        local function SSetColor(key, r, g, b, a, applyFn)
            SB()[key] = { r=r, g=g, b=b, a=a }
            if applyFn then applyFn(SelectedKey()) end
            EllesmereUI:RefreshPage()
        end
        local function SUpdatePreview()
            UpdatePreview()
        end

        -- The stock spacing lives in the offset boxes, not in the placement. A
        -- position pick swaps the old placement's spacing for the new one's on each
        -- axis and keeps whatever the user added on top (Default carries none: its
        -- stock lines hold their own spacing). Opting in, moving between positions
        -- and going back to Default therefore never move the text by the spacing,
        -- whatever the boxes held (a Cropped shape's preset included).
        local function SSeedTextOffsets(kind, anchorKey, oxKey, oyKey, anchor)
            local prev = SVal(anchorKey, nil)
            if prev == anchor then return end
            local px, py, nx, ny = 0, 0, 0, 0
            if prev then px, py = EAB.StockTextOffsets(kind, prev) end
            if anchor then nx, ny = EAB.StockTextOffsets(kind, anchor) end
            SB()[oxKey] = SVal(oxKey, 0) - px + nx
            SB()[oyKey] = SVal(oyKey, 0) - py + ny
        end
        local function SUpdatePreviewAndResize()
            UpdatePreviewAndResize()
        end
        parent._showRowDivider = true

        local visOnly = IsVisOnly()
        -- Row / section references for click-navigation
        local iconsSectionHeader, textSectionHeader
        local keybindRow, chargesRow

        local function BgDisabled()
            return not SB().bgEnabled
        end

        -- The sections live in ActionBars_Options\BarVisibilityLayout_Options.lua
        -- (Bar 10 caution, VISIBILITY, LAYOUT) and BarAppearance_Options.lua (BAR
        -- BACKGROUND, ICON APPEARANCE, ICON EFFECTS, PAGING, TEXT); the second
        -- returns the rows the click navigation below maps to.
        local ctx = {
            BgDisabled = BgDisabled, SDB = SDB, SGet = SGet, SSeedTextOffsets = SSeedTextOffsets,
            SSet = SSet, SSetColor = SSetColor, SUpdatePreview = SUpdatePreview,
            SUpdatePreviewAndResize = SUpdatePreviewAndResize, SVal = SVal, visOnly = visOnly,
            W = W,
        }
        y = ns.ABO_BuildBarVisibilityLayout(parent, y, ctx)

        if not visOnly then
            local classColorBorderRow
            y, iconsSectionHeader, textSectionHeader, keybindRow, chargesRow, classColorBorderRow =
                ns.ABO_BuildBarAppearance(parent, y, ctx)

            -------------------------------------------------------------------
            --  CLICK NAVIGATION
            -------------------------------------------------------------------
            local PlaySettingGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN, thickness = function() return PP.Scale(2) end, noSnap = true })

            local clickMappings = {
                icon       = { section = iconsSectionHeader, target = classColorBorderRow },
                keybind    = { section = textSectionHeader,  target = keybindRow, slotSide = "right" },
                charges    = { section = textSectionHeader,  target = chargesRow, slotSide = "left" },
            }

            local function NavigateToSetting(key)
                local m = clickMappings[key]
                if not m or not m.section or not m.target then return end

                EllesmereUI.DismissPreviewHint(_abPreviewHintFS, barsHeaderBaseH, 29, 17)

                local sf = EllesmereUI._scrollFrame
                if not sf then return end
                local _, _, _, _, headerY = m.section:GetPoint(1)
                if not headerY then return end
                local scrollPos = math.max(0, math.abs(headerY) - 40)
                EllesmereUI.SmoothScrollTo(scrollPos)
                local glowTarget = m.target
                if m.slotSide and m.target then
                    local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                    if region then glowTarget = region end
                end
                C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
            end

            local hitStyle = { tightText = true }
            local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
                return (EllesmereUI.CreatePreviewHitOverlay(element, NavigateToSetting, mappingKey, isText, frameLevelOverride, opts, hitStyle))
            end

            local textOverlays = {}
            if optState.activePreview then
                local pv = optState.activePreview
                local pvButtons = pv._buttons
                local iconLevel = (pvButtons[1] and pvButtons[1].frame and pvButtons[1].frame:GetFrameLevel() or 5) + 10
                local textOnIconLevel = iconLevel + 10
                local iconHlOpts = { hlBehindText = true }
                for i = 1, pv._barInfo.count do
                    local entry = pvButtons[i]
                    if entry and entry.frame then
                        CreateHitOverlay(entry.frame, "icon", false, iconLevel, iconHlOpts)
                        if entry.keybind then
                            textOverlays[#textOverlays + 1] = CreateHitOverlay(entry.keybind, "keybind", true, textOnIconLevel)
                        end
                        if entry.count then
                            textOverlays[#textOverlays + 1] = CreateHitOverlay(entry.count, "charges", true, textOnIconLevel)
                        end
                    end
                end
                pv._textOverlays = textOverlays
            end
        end  -- if not visOnly

        return y
    end

    local function BuildBarDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        optState.activePreview = nil

        -- Consume any pending bar selection from Element Options navigation.
        if EllesmereUI._consumePendingActionBarSelect then EllesmereUI._consumePendingActionBarSelect() end

        -- Tag every option registered while building this page with the selected bar, so a global-search
        -- jump to a bar-specific setting restores this exact selection first via _setActionBarKey
        -- (full reasoning: the matching _buildingSelector comment in EUI_CooldownManager_Options.lua).
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setActionBarKey, key = SelectedKey() }

        ShowEditOverlay(SelectedKey())

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _barsHeaderBuilder = function(hdr, hdrW)
            local PAD = EllesmereUI.CONTENT_PAD
            local PV_PAD = 10  -- internal padding inside BuildLivePreview
            local fy = -20

            -- Centered dropdown (same pattern as Multi Bar Edit)
            local DD_H = 34
            local availW = hdrW - PAD * 2
            local ddW = 350
            local ddBtn, ddLbl = EllesmereUI.BuildDropdownControl(
                hdr, ddW, hdr:GetFrameLevel() + 5,
                barLabels, barOrder,
                function() return SelectedKey() end,
                function(v)
                    _selectedBarKey = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_barsHeaderBuilder)
                    -- Always force a full rebuild: visibility-only bars and StanceBar share visOnly/dataBar flags, so a conditional misses transitions.
                    EllesmereUI:RefreshPage(true)
                    ShowEditOverlay(v)
                end,
                function(key)
                    -- Bar9/Bar10 default to Hidden visibility but must stay selectable so they can be configured -- never show the disabled effect.
                    if key == "Bar9" or key == "Bar10" then return nil end
                    if not IsBarEnabled(key) then return EllesmereUI.DisabledTooltip("this action bar") end
                end
            )
            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            ddBtn:SetHeight(DD_H)
            fy = fy - DD_H - PV_PAD

            local previewH = ns.ABO_BuildLivePreview(hdr, fy)
            fy = fy - previewH - PV_PAD

            headerFixedH = 20 + DD_H + PV_PAD + PV_PAD

            if _abPreviewHintFS and not _abPreviewHintFS:GetParent() then
                _abPreviewHintFS = nil
            end
            local hintH = 0
            if not IsPreviewHintDismissed() then
                if not _abPreviewHintFS then
                    local hintHost = CreateFrame("Frame", nil, hdr)
                    hintHost:SetAllPoints(hdr)
                    _abPreviewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                    _abPreviewHintFS:SetAlpha(0.45)
                    _abPreviewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                _abPreviewHintFS:GetParent():SetParent(hdr)
                _abPreviewHintFS:GetParent():Show()
                _abPreviewHintFS:ClearAllPoints()
                _abPreviewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 17)
                _abPreviewHintFS:SetAlpha(0.45)
                _abPreviewHintFS:Show()
                hintH = 29
            elseif _abPreviewHintFS then
                _abPreviewHintFS:Hide()
            end

            barsHeaderBaseH = math.abs(fy)
            return barsHeaderBaseH + hintH
        end
        EllesmereUI:SetContentHeader(_barsHeaderBuilder)

        -------------------------------------------------------------------
        --  Top action buttons: Quick Keybind + Blizzard/EUI Style toggle
        -------------------------------------------------------------------
        do
            local BTN_W = 312
            local BTN_H = 38
            local GAP = 40
            local ROW_H = BTN_H + 20
            local rowFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            local qkbBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(qkbBtn, BTN_W, BTN_H)
            PP.Point(qkbBtn, "RIGHT", rowFrame, "CENTER", -(GAP / 2), 0)
            qkbBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
            EllesmereUI.MakeStyledButton(qkbBtn, "Quick Keybind Mode (/kb)", 14,
                EllesmereUI.WB_COLOURS, function()
                    if InCombatLockdown() then return end
                    if not C_AddOns.IsAddOnLoaded("Blizzard_QuickKeybind") then
                        C_AddOns.LoadAddOn("Blizzard_QuickKeybind")
                    end
                    if QuickKeybindFrame then
                        EllesmereUI:Toggle()
                        QuickKeybindFrame:Show()
                    end
                end)

            -- A stock style on (Blizzard, Classic or WoW Forever) offers the
            -- way back to the EUI look; off, the way to Blizzard Style. Classic
            -- WoW UI and WoW Forever are the Style page's; the write is the
            -- Style page's own switch, so leaving WoW Forever here brings the
            -- queue eye's spot back as a Style row does.
            local isStock = EllesmereUI.BlizzStyle.Get("actionbars")
            local styleBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(styleBtn, BTN_W, BTN_H)
            PP.Point(styleBtn, "LEFT", rowFrame, "CENTER", GAP / 2, 0)
            styleBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
            local _, _, styleLbl = EllesmereUI.MakeStyledButton(styleBtn,
                isStock and "EUI Style Action Bars" or "Blizzard Style Action Bars", 14,
                EllesmereUI.WB_COLOURS, function()
                    local toBlizz = not EllesmereUI.BlizzStyle.Get("actionbars")
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Reload Required",
                        message     = "Changing icon style requires a UI reload to apply.",
                        confirmText = "Reload Now",
                        cancelText  = "Cancel",
                        reload      = true,
                        onConfirm   = function()
                            EllesmereUI.BlizzStyle.Switch("actionbars", toBlizz and "blizzard" or "eui")
                        end,
                    })
                end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  Build shared settings (single mode)
        -------------------------------------------------------------------
        y = BuildSharedBarSettings(parent, y)

        return math.abs(y)
    end


    -- Bar Animations page (ActionBars_Options\AnimationsPage_Options.lua). Called
    -- here so its Custom Proc Glow site registers at the original point in the load order.
    local BuildAnimationsPage = ns.ABO_InitAnimationsPage(PP, EAB, PAGE_ANIMATIONS)

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (opens EllesmereUI Unlock Mode overlay)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        -- Defer to next frame so the page switch completes first
        C_Timer.After(0, function()
            if ns.OpenUnlockMode then
                ns.OpenUnlockMode()
            end
        end)
        return 0
    end

    -- Shared with the page builders under ActionBars_Options\ (read in their
    -- prologs). Every field is final here: optState holds the mutable state.
    ns._ABO_OptEnv = {
        ApplyVisibilityKey = ApplyVisibilityKey, BAR_LOOKUP = BAR_LOOKUP,
        CopyVisibilitySettings = CopyVisibilitySettings, EAB = EAB, EndCapsCtl = EndCapsCtl,
        FirstBarButton = FirstBarButton, floor = floor, GetVisibilityKey = GetVisibilityKey,
        GROUP_BAR_ORDER = GROUP_BAR_ORDER, InCombatLockdown = InCombatLockdown,
        MASQUE_BAR_ORDER = MASQUE_BAR_ORDER, IsMasqueAvailable = IsMasqueAvailable,
        IsDataBar = IsDataBar, optState = optState, pcall = pcall, PP = PP,
        RANGE_INDICATOR = RANGE_INDICATOR, SB = SB,
        SECTION_ICON_APPEARANCE = SECTION_ICON_APPEARANCE, SECTION_LAYOUT = SECTION_LAYOUT,
        SECTION_TEXT = SECTION_TEXT, SECTION_VISIBILITY = SECTION_VISIBILITY,
        SelectedKey = SelectedKey, SHORT_LABELS = SHORT_LABELS,
        ShownBorderDefaults = ShownBorderDefaults,
        TEXT_ANCHOR_DROPDOWN_ORDER = TEXT_ANCHOR_DROPDOWN_ORDER,
        TEXT_ANCHOR_LABELS = TEXT_ANCHOR_LABELS,
    }

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIActionBars", {
        title       = "Action Bars",
        description = "Configure visuals and behavior for your action bars.",
        pages       = { PAGE_DISPLAY, PAGE_XPBAR, PAGE_MENUBAGSREP, PAGE_ANIMATIONS },
        buildPage   = function(pageName, parent, yOffset)
            -- BuildBarDisplayPage calls ShowEditOverlay() unconditionally at build time, showing a
            -- real UIParent-parented overlay over the live action bars. A hidden search pre-build
            -- would flash it onscreen, so skip PAGE_DISPLAY here; it indexes on first visit.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_XPBAR then
                    return ns.ABO_BuildXPBarPage(pageName, parent, yOffset)
                elseif pageName == PAGE_MENUBAGSREP then
                    return ns.ABO_BuildMenuBagsRepPage(pageName, parent, yOffset)
                elseif pageName == PAGE_ANIMATIONS then
                    return BuildAnimationsPage(pageName, parent, yOffset)
                end
                return
            end
            if pageName ~= PAGE_DISPLAY then
                HideEditOverlay()
            end
            if pageName == PAGE_DISPLAY then
                return BuildBarDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_XPBAR then
                return ns.ABO_BuildXPBarPage(pageName, parent, yOffset)
            elseif pageName == PAGE_MENUBAGSREP then
                return ns.ABO_BuildMenuBagsRepPage(pageName, parent, yOffset)
            elseif pageName == PAGE_ANIMATIONS then
                return BuildAnimationsPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _barsHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                UpdatePreview()
                ShowEditOverlay(SelectedKey())
                local dismissed = IsPreviewHintDismissed()
                if _abPreviewHintFS then
                    if dismissed then
                        _abPreviewHintFS:Hide()
                    else
                        _abPreviewHintFS:SetAlpha(0.45)
                        _abPreviewHintFS:Show()
                        if _abPreviewHintFS:GetParent() then _abPreviewHintFS:GetParent():Show() end
                    end
                end
                if barsHeaderBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(barsHeaderBaseH + (dismissed and 0 or 29))
                end
            else
                HideEditOverlay()
            end
        end,
        onReset     = function()
            EAB.db:ResetProfile()
            -- Clear the per-install capture flag: the snapshot re-runs post-reload and re-reads Blizzard's bar layout.
            if EAB.db and EAB.db.sv then
                EAB.db.sv._capturedOnce_EAB = nil
            end
            -- No reload here: the footer Reset popup (reload = true) reloads after this returns.
        end,
    })

    -- Search skips Bar Display because building it opens the bar edit overlay.
    -- Add Masque here so search can find it before the page has been opened.
    if EllesmereUI._RegisterSearchEntry then
        EllesmereUI._RegisterSearchEntry(
            "Enable Masque Support", nil,
            "Allows Masque to skin the buttons on Action Bars 1-10, the Pet Bar, and the Stance Bar. Requires a UI reload to apply.",
            "EllesmereUIActionBars", PAGE_DISPLAY, SECTION_ICON_APPEARANCE,
            EllesmereUI._setActionBarKey, "MainBar")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
