if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Popups.lua
--
--  Group icons, the toolbar button and its indicator, group creation, the
--  cards popup and the Conditional Overrides UI.
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local ACCENT_B, ACCENT_G, ACCENT_R = I.ACCENT_B, I.ACCENT_G, I.ACCENT_R
local CLASS_COORDS, CLASS_ORDER, ConflictSpec = I.CLASS_COORDS, I.CLASS_ORDER, I.ConflictSpec
local CurrentSpecID, DeepCopy = I.CurrentSpecID, I.DeepCopy
local EntryHolderGroup, GetGroups, GetStore = I.EntryHolderGroup, I.GetGroups, I.GetStore
local GLYPH_SPRITE, GroupById, L, LIST_PAGE = I.GLYPH_SPRITE, I.GroupById, I.L, I.LIST_PAGE
local MatchOwnedFKey, MODERN_SPRITE = I.MatchOwnedFKey, I.MODERN_SPRITE
local MULTISPEC_ICON, NextGroupId = I.MULTISPEC_ICON, I.NextGroupId
local PROFILES_MODULE, RebuildFKeyIndex = I.PROFILES_MODULE, I.RebuildFKeyIndex
local ROLE_ICONS, ROLE_ORDER, RunRefreshers = I.ROLE_ICONS, I.ROLE_ORDER, I.RunRefreshers
local SpecInAnyGroup, SpecName = I.SpecInAnyGroup, I.SpecName
local SpecStrandedOnEntry, OwnerGid, Cond = I.SpecStrandedOnEntry, I.OwnerGid, I.Cond
local IsExcludedContext, RequestGoldWalk = I.IsExcludedContext, I.RequestGoldWalk
local EnsurePanelHideHook, EnterGroupEdit = I.EnsurePanelHideHook, I.EnterGroupEdit
local ExitGroupEdit, SetUpdateIndicator = I.ExitGroupEdit, I.SetUpdateIndicator
local SetRefreshCardsPopup = I.SetRefreshCardsPopup

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _activeSpec = nil
I.activeSpecSetters[#I.activeSpecSetters + 1] = function(v) _activeSpec = v end

-- Forward declarations (assigned further down in this file)
local UpdateIndicator, RefreshCardsPopup

-------------------------------------------------------------------------------
--  Group icon rendering
-------------------------------------------------------------------------------
local function ApplyGroupIcon(tex, icon)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, 1)
    if icon and icon.kind == "cond" and Cond.ICONS[icon.key] then
        tex:SetTexture(Cond.ICON_DIR .. Cond.ICONS[icon.key])
    elseif icon and icon.kind == "multi" then
        tex:SetTexture(MULTISPEC_ICON)
    elseif icon and icon.kind == "role" and ROLE_ICONS[icon.key] then
        tex:SetTexture(ROLE_ICONS[icon.key])
    elseif icon and icon.kind == "class" and CLASS_COORDS[icon.key] then
        tex:SetTexture(MODERN_SPRITE)
        local c = CLASS_COORDS[icon.key]
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        -- Default (no group icon): the player's class glyph in natural colors,
        -- matching the toolbar button.
        tex:SetTexture(GLYPH_SPRITE)
        local _, classFile = UnitClass("player")
        local c = classFile and CLASS_COORDS[classFile]
        if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    end
end
EllesmereUI.SpecOverrides_ApplyGroupIcon = ApplyGroupIcon

-- Pages (by module) that list override groups and are rebuilt after a group
-- is renamed, re-specced or deleted; modules add theirs: [module][page] = true.
EllesmereUI.SpecOverrides_GroupListingPages = EllesmereUI.SpecOverrides_GroupListingPages or {}

-- Forced rebuild of the pages that list override groups: the overrides list
-- page and every page a module registered above.
local function RefreshGroupListingPage()
    local ap = EllesmereUI:GetActivePage()
    local pages = EllesmereUI.SpecOverrides_GroupListingPages[EllesmereUI:GetActiveModule()]
    if ap == LIST_PAGE or (pages and pages[ap]) then
        EllesmereUI:RefreshPage(true)
    end
end

-------------------------------------------------------------------------------
--  Toolbar button + active-group indicator
-------------------------------------------------------------------------------
local specBtn, indicatorBtn

-- The spec-overrides button keeps ONE identity: the natural class glyph and the
-- standard tooltip regardless of editing/active state (no icon or tooltip
-- morphing). The second indicator icon stays retired.
UpdateIndicator = function()
    if indicatorBtn then indicatorBtn:Hide() end   -- retired second icon
    if not specBtn or not specBtn._tex then return end
    specBtn._tex:SetTexture(GLYPH_SPRITE)
    local _, classFile = UnitClass("player")
    local c = classFile and CLASS_COORDS[classFile]
    if c then specBtn._tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    specBtn._tex:SetDesaturated(false)
    specBtn._tex:SetVertexColor(1, 1, 1, 1)
end
SetUpdateIndicator(UpdateIndicator)

--- The toolbar button is DISABLED while the active page is excluded from the
--- override systems (blacklisted module pages, QoL Shifter/Upgrade Calc):
--- dimmed, click refused, explanatory tooltip. Re-evaluated on every
--- module/page selection (called from OnPageRebuilt).
EllesmereUI._specOvBtnPageState = function()
    if not specBtn then return end
    local off = IsExcludedContext()
    -- Buff Manager page bound to a live fork: block the dropdown entirely (the
    -- page edits that fork no matter what).
    local bmLock = false
    if not off and EllesmereUI.SpecOverrides_BmPageLocked then
        bmLock = EllesmereUI.SpecOverrides_BmPageLocked()
    end
    if not bmLock and not off and EllesmereUI.SpecOverrides_DmPageLocked then
        bmLock = EllesmereUI.SpecOverrides_DmPageLocked()
    end
    specBtn._ovPageDisabled = off or nil
    specBtn._ovBmLocked = bmLock or nil
    specBtn:SetAlpha((off or bmLock) and 0.35 or 0.9)
end

--- Draws attention to the toolbar glyph: a gold pulsing wash + ring over the
--- button for ~8 pulses, or until it is clicked. Used by the Settings Overrides
--- announcement's "Show Me" landing.
local function StopButtonPulse()
    if specBtn and specBtn._pulse then
        specBtn._pulseAG:Stop()
        specBtn._pulse:Hide()
    end
    if specBtn and specBtn._pulseTip then
        specBtn._pulseTipAG:Stop()
        specBtn._pulseTip:Hide()
    end
end

function EllesmereUI.SpecOverrides_PulseButton()
    if not specBtn then return end
    local p = specBtn._pulse
    if not p then
        p = CreateFrame("Frame", nil, specBtn)
        p:SetPoint("TOPLEFT", specBtn, "TOPLEFT", -5, 5)
        p:SetPoint("BOTTOMRIGHT", specBtn, "BOTTOMRIGHT", 5, -5)
        -- Soft gold wash (low alpha so the glyph stays readable) plus a gold
        -- ring; the whole frame's alpha is what pulses.
        local wash = p:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        wash:SetColorTexture(1, 0.82, 0.30, 0.14)
        EllesmereUI.MakeBorder(p, 1, 0.82, 0.30, 0.9)
        local ag = p:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local a1 = ag:CreateAnimation("Alpha")
        a1:SetFromAlpha(1); a1:SetToAlpha(0.15)
        a1:SetDuration(0.45); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
        local a2 = ag:CreateAnimation("Alpha")
        a2:SetFromAlpha(0.15); a2:SetToAlpha(1)
        a2:SetDuration(0.45); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
        ag:SetScript("OnLoop", function(self)
            self._loops = (self._loops or 0) + 1
            if self._loops >= 8 then StopButtonPulse() end
        end)
        specBtn._pulse = p
        specBtn._pulseAG = ag
    end
    -- Bouncing callout chip below the button: "New Overrides System".
    local tip = specBtn._pulseTip
    if not tip then
        tip = CreateFrame("Frame", nil, specBtn)
        tip:SetFrameStrata("DIALOG")   -- above the page content below the bar
        local lbl = EllesmereUI.MakeFont(tip, 12, nil, 1, 0.82, 0.30, 1)
        lbl:SetPoint("CENTER")
        lbl:SetText(L("New Overrides System"))
        local w = (lbl:GetStringWidth() or 120) + 20
        tip:SetSize(w, 24)
        tip:SetPoint("TOP", specBtn, "BOTTOM", 0, -8)
        local tbg = EllesmereUI.SolidTex(tip, "BACKGROUND", 0.062, 0.050, 0.039, 0.95)
        EllesmereUI.MakeBorder(tip, 1, 0.82, 0.30, 0.85)
        local ag = tip:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local t1 = ag:CreateAnimation("Translation")
        t1:SetOffset(0, -4); t1:SetDuration(0.45); t1:SetOrder(1); t1:SetSmoothing("IN_OUT")
        local t2 = ag:CreateAnimation("Translation")
        t2:SetOffset(0, 4); t2:SetDuration(0.45); t2:SetOrder(2); t2:SetSmoothing("IN_OUT")
        specBtn._pulseTip = tip
        specBtn._pulseTipAG = ag
    end
    specBtn._pulseAG._loops = 0
    p:Show()
    tip:Show()
    specBtn._pulseAG:Play()
    specBtn._pulseTipAG:Play()
end

--- Decorates and wires the toolbar button created in the tab bar (main panel).
function EllesmereUI.SpecOverrides_SetupButton(btn)
    specBtn = btn
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(GLYPH_SPRITE)
    -- Natural-color glyph: 90% opacity idle, full on hover.
    local _, classFile = UnitClass("player")
    local c = classFile and CLASS_COORDS[classFile]
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    btn._tex = tex
    btn:SetAlpha(0.9)
    btn:SetScript("OnEnter", function(self)
        if self._ovPageDisabled then
            EllesmereUI.ShowWidgetTooltip(self, L("This page is excluded from overrides."))
            return
        end
        if self._ovBmLocked then
            EllesmereUI.ShowWidgetTooltip(self, L("Overrides are locked: this page's custom Buff Manager is active. Leave the Buff Manager tab to manage overrides."))
            return
        end
        self:SetAlpha(1)
        EllesmereUI.ShowWidgetTooltip(self, L("Settings Overrides"))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha((self._ovPageDisabled or self._ovBmLocked) and 0.35 or 0.9)
        EllesmereUI.HideWidgetTooltip()
    end)
    btn:SetScript("OnClick", function(self)
        StopButtonPulse()   -- attention served the moment it is clicked
        if self._ovPageDisabled then return end
        if self._ovBmLocked then
            -- Blocked: explain at the icon instead of opening the dropdown.
            EllesmereUI.ShowWidgetTooltip(self, L("Overrides are locked: this page's custom Buff Manager is active. Leave the Buff Manager tab to manage overrides."))
            return
        end
        -- First-ever press shows the Settings Overrides video guide instead of
        -- the cards popup; later presses behave normally (FireOnce returns
        -- false once seen; the nil-guard covers standalone builds).
        local VG = EllesmereUI.VideoGuides
        if VG and VG.FireOnce("settings_overrides") then return end
        EllesmereUI.SpecOverrides_ToggleCardsPopup(self)
    end)
    UpdateIndicator()
    EllesmereUI._specOvBtnPageState()
end

-------------------------------------------------------------------------------
--  Group creation: spec picker -> name + icon popup
-------------------------------------------------------------------------------
local nameIconPopup

-- Name + icon popup chrome shared by spec groups and conditional groups: an
-- icon grid built from defs, Create runs onCreate(p). Callers set the title,
-- button label, name text and icon selection on every show.
local function BuildNameIconPopup(defs, onCreate)
    -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
    local p = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
    p:SetSize(380, 300)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(220)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)

    local title = EllesmereUI.MakeFont(p, 14, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
    title:SetPoint("TOP", p, "TOP", 0, -14)
    p._title = title

    local nameLbl = EllesmereUI.MakeFont(p, 12, nil, 1, 1, 1, 0.6)
    nameLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -44)
    nameLbl:SetText(L("Name"))

    local nameBox = CreateFrame("EditBox", nil, p)
    nameBox:SetSize(340, 26)
    nameBox:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -62)
    nameBox:SetAutoFocus(false)
    nameBox:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
    nameBox:SetTextColor(1, 1, 1, 1)
    nameBox:SetTextInsets(8, 8, 0, 0)
    nameBox:SetMaxLetters(24)
    EllesmereUI.SolidTex(nameBox, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    EllesmereUI.MakeBorder(nameBox, 1, 1, 1, 0.12)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p._nameBox = nameBox

    local iconLbl = EllesmereUI.MakeFont(p, 12, nil, 1, 1, 1, 0.6)
    iconLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -102)
    iconLbl:SetText(L("Icon"))

    p._iconBtns = {}
    local PER_ROW, SZ, GAP = 8, 34, 8
    for i, def in ipairs(defs) do
        local col = (i - 1) % PER_ROW
        local rowI = math.floor((i - 1) / PER_ROW)
        local b = CreateFrame("Button", nil, p)
        b:SetSize(SZ, SZ)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 20 + col * (SZ + GAP), -122 - rowI * (SZ + GAP))
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        ApplyGroupIcon(t, def)
        local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.10)
        b._def = def
        b._brd = brd
        b:SetScript("OnClick", function(self)
            p._selectedIcon = self._def
            for _, ob in ipairs(p._iconBtns) do
                if ob._brd and ob._brd.SetColor then
                    ob._brd:SetColor(1, 1, 1, ob == self and 0 or 0.10)
                end
                if ob._brd and ob._brd.SetColor and ob == self then
                    ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                end
                ob:SetAlpha(ob == self and 1 or 0.7)
            end
        end)
        b:SetAlpha(0.7)
        p._iconBtns[#p._iconBtns + 1] = b
    end

    local create = CreateFrame("Button", nil, p)
    create:SetSize(110, 28)
    -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
    create:SetPoint("BOTTOM", p, "BOTTOM", 44, 14)
    EllesmereUI.SolidTex(create, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local cbrd = EllesmereUI.MakeBorder(create, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
    local clbl = EllesmereUI.MakeFont(create, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
    clbl:SetPoint("CENTER")
    p._createLbl = clbl
    create:SetScript("OnEnter", function() if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end end)
    create:SetScript("OnLeave", function() if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end end)
    create:SetScript("OnClick", function() onCreate(p) end)

    local cancel = CreateFrame("Button", nil, p)
    cancel:SetSize(80, 28)
    cancel:SetPoint("RIGHT", create, "LEFT", -8, 0)
    EllesmereUI.SolidTex(cancel, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local xbrd = EllesmereUI.MakeBorder(cancel, 1, 1, 1, 0.22)
    local xlbl = EllesmereUI.MakeFont(cancel, 12, nil, 1, 1, 1, 0.7)
    xlbl:SetPoint("CENTER")
    xlbl:SetText(L("Cancel"))
    cancel:SetScript("OnEnter", function() if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.4) end end)
    cancel:SetScript("OnLeave", function() if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.22) end end)
    cancel:SetScript("OnClick", function() p:Hide() end)

    -- Controller cursor: its cancel press backs out through Cancel, and the
    -- panel is a blocker, not a stop.
    if EllesmereUI.PadCP() then p.CloseButton = cancel end
    EllesmereUI.TrackOverlay(p)
    EllesmereUI.PadHint(p, "nodepass")
    return p
end

local function ShowNameIconPopup(specIDs, editing)
    if not nameIconPopup then
        -- Icon grid: multi-spec + 3 modern role icons + 13 modern class icons
        local defs = { { kind = "multi" } }
        for _, role in ipairs(ROLE_ORDER) do
            defs[#defs + 1] = { kind = "role", key = role }
        end
        for _, cls in ipairs(CLASS_ORDER) do
            defs[#defs + 1] = { kind = "class", key = cls }
        end
        nameIconPopup = BuildNameIconPopup(defs, function(p)
            -- EDIT mode: rename/re-icon the existing group (specs were already
            -- applied by the picker's Next step).
            local editing = p._editing
            if editing then
                local name = p._nameBox:GetText()
                local changed = false
                if name and name ~= "" and name ~= editing.name then
                    editing.name = name; changed = true
                end
                local sel, cur = p._selectedIcon, editing.icon
                if sel and not (cur and cur.kind == sel.kind and cur.key == sel.key) then
                    editing.icon = sel; changed = true
                end
                p:Hide()
                if UpdateIndicator then UpdateIndicator() end
                if RefreshCardsPopup then RefreshCardsPopup() end
                -- SetGroupSpecs already rebuilt the listing pages; only a new
                -- name or icon needs another rebuild.
                if changed then RefreshGroupListingPage() end
                return
            end
            local specs = p._specs
            if not specs or #specs == 0 then p:Hide(); return end
            local groups = GetGroups(true)
            if not groups then p:Hide(); return end
            local id = NextGroupId()
            local name = p._nameBox:GetText()
            if not name or name == "" then name = L("Group") .. " " .. id end
            local g = {
                id = id, name = name,
                icon = p._selectedIcon or { kind = "role", key = "DAMAGER" },
                specs = specs,
            }
            groups[#groups + 1] = g
            p:Hide()
            -- WoW Forever: the new group can move the spec the class acts as.
            -- Apply it before the session opens, so every exit of that session
            -- (and a create the page lock refuses) sees it. While a session is
            -- open this stands down and that session's user exit applies it.
            if EllesmereUI.IS_FOREVER then EllesmereUI._SO_ForeverConverge() end
            -- Auto-activate: a new group goes straight into its "Editing as"
            -- session. EnterGroupEdit self-guards the BM page lock and tears
            -- down any active session.
            EnterGroupEdit(g)
            if UpdateIndicator then UpdateIndicator() end   -- current spec may have joined
            if RefreshCardsPopup then RefreshCardsPopup() end
        end)
        EllesmereUI._specOvNamePopup = nameIconPopup   -- panel-hide hook closes it (lexical: local declared below the hook)
    end
    nameIconPopup._specs = specIDs
    nameIconPopup._editing = editing
    nameIconPopup._title:SetText(editing
        and string.format(L("Edit Group: %s"), editing.name or "?")
        or L("New Spec Group"))
    nameIconPopup._createLbl:SetText(editing and L("Save") or L("Create Group"))
    nameIconPopup._nameBox:SetText(editing and (editing.name or "") or "")
    nameIconPopup._selectedIcon = nil
    for _, ob in ipairs(nameIconPopup._iconBtns) do
        -- EDIT mode pre-selects the group's current icon.
        local sel = editing and editing.icon and ob._def
            and ob._def.kind == editing.icon.kind
            and ob._def.key == editing.icon.key or false
        if sel then nameIconPopup._selectedIcon = ob._def end
        ob:SetAlpha(sel and 1 or 0.7)
        if ob._brd and ob._brd.SetColor then
            if sel then
                ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
            else
                ob._brd:SetColor(1, 1, 1, 0.10)
            end
        end
    end
    nameIconPopup:Show()
    -- Controller cursor: move it into the popup.
    EllesmereUI.PadFocus(nameIconPopup)
end

local function StartGroupCreation()
    if not EllesmereUI.ShowSpecAssignPopup then return end
    local dummyDB = { _specOv = { _specs = {} } }
    EllesmereUI:ShowSpecAssignPopup({
        db        = dummyDB,
        dbKey     = "_specOv",
        presetKey = "_specs",
        title     = L("New Spec Group"),
        subtitle  = L("Select the specs this group edits:"),
        buttonText = L("Next"),
        preCheckedSpecs = {},
        onConfirm = function(assignments)
            -- Specs may belong to multiple groups; settings a shared spec
            -- already overrides in another group are conflict-locked (red)
            -- while editing this one.
            local specs = {}
            for specID, on in pairs(assignments or {}) do
                if on and type(specID) == "number" then
                    specs[#specs + 1] = specID
                end
            end
            table.sort(specs)
            if #specs == 0 then return end
            ShowNameIconPopup(specs)
        end,
    })
end

-------------------------------------------------------------------------------
--  Cards popup
-------------------------------------------------------------------------------
local cardsPopup

-- Card rows are pooled by position on the popup (parent._cards; parent._cardN is the
-- next one RefreshCardsPopup lays out), and every per-card piece is re-applied here.
local function BuildCardRow(parent, y, opts)
    local cards = parent._cards
    if not cards then cards = {}; parent._cards = cards end
    local n = (parent._cardN or 0) + 1
    parent._cardN = n
    local row = cards[n]
    if not row then
        row = CreateFrame("Button", nil, parent)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        row._brd = EllesmereUI.MakeBorder(row, 1, 1, 1, 0.08)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row._icon = icon
        local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
        name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        row._nameFS = name
        cards[n] = row
    end
    row:SetSize(parent:GetWidth() - 20, 40)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    row:SetAlpha(1)
    row:Show()
    local brd = row._brd
    if opts.active then
        brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    else
        brd:SetColor(1, 1, 1, 0.08)
    end
    local icon = row._icon
    icon:SetTexture(nil)
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetDesaturated(false)
    icon:SetVertexColor(1, 1, 1, 1)
    if opts.iconApply then opts.iconApply(icon) end
    local name = row._nameFS
    name:SetTextColor(1, 1, 1, opts.dim and 0.55 or 0.9)
    name:SetText(opts.name)
    if opts.tooltip then
        row:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, opts.tooltip)
        end)
        row:SetScript("OnLeave", function()
            EllesmereUI.HideWidgetTooltip()
        end)
    else
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end
    if opts.locked then
        -- BM page lock: not selectable while another override's Buff Manager is
        -- bound to the open page. Dim + inert (tooltip only).
        row:SetAlpha(0.4)
        row:SetScript("OnClick", function(self)
            EllesmereUI.ShowWidgetTooltip(self, L("The active override's Buff Manager is bound to the open page. Leave the Buff Manager tab to switch overrides."))
        end)
    else
        row:SetScript("OnClick", opts.onClick)
    end
    local del
    if opts.deletable then
        del = row._del
        if not del then
            del = CreateFrame("Button", nil, row)
            del:SetSize(20, 20)
            del:SetPoint("RIGHT", row, "RIGHT", -6, 1)
            del:SetFrameLevel(row:GetFrameLevel() + 2)
            -- Same close glyph the Blizzard window skins use.
            local xt = del:CreateTexture(nil, "OVERLAY")
            xt:SetAtlas("uitools-icon-close")
            xt:SetSize(15, 15)
            xt:SetPoint("CENTER", del, "CENTER", 0, -2)
            del._xt = xt
            del:SetScript("OnEnter", function(self)
                xt:SetVertexColor(1, 1, 1, 1)
                EllesmereUI.ShowWidgetTooltip(self, L("Delete Override Group"))
            end)
            del:SetScript("OnLeave", function()
                xt:SetVertexColor(1, 1, 1, 0.75)
                EllesmereUI.HideWidgetTooltip()
            end)
            row._del = del
        end
        del._xt:SetVertexColor(1, 1, 1, 0.75)
        del:SetScript("OnClick", opts.onDelete)
        del:Show()
    elseif row._del then
        row._del:Hide()
    end
    local ed
    if opts.onEdit then
        ed = row._ed
        if not ed then
            ed = CreateFrame("Button", nil, row)
            ed:SetSize(16, 16)
            ed:SetFrameLevel(row:GetFrameLevel() + 2)
            local ico = ed:CreateTexture(nil, "OVERLAY")
            ico:SetAllPoints()
            if ico.SetSnapToPixelGrid then ico:SetSnapToPixelGrid(false); ico:SetTexelSnappingBias(0) end
            ico:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
            ed:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                EllesmereUI.ShowWidgetTooltip(self, L("Edit Override Group"))
            end)
            ed:SetScript("OnLeave", function(self)
                self:SetAlpha(0.75)
                EllesmereUI.HideWidgetTooltip()
            end)
            row._ed = ed
        end
        ed:ClearAllPoints()
        if del then
            -- del sits 1px high; -2 relative lands the pencil 1px low on the row.
            ed:SetPoint("RIGHT", del, "LEFT", -1, -2)
        else
            ed:SetPoint("RIGHT", row, "RIGHT", -5, -1)
        end
        ed:SetAlpha(0.75)
        ed:SetScript("OnClick", opts.onEdit)
        ed:Show()
    elseif row._ed then
        row._ed:Hide()
    end
    if opts.onUnlock then
        local ub = row._ub
        if not ub then
            ub = CreateFrame("Button", nil, row)
            -- Native art is 37x42; keep the aspect ratio at 16px height.
            ub:SetSize(16 * 37 / 42, 16)
            ub:SetFrameLevel(row:GetFrameLevel() + 2)
            local ico = ub:CreateTexture(nil, "OVERLAY")
            ico:SetAllPoints()
            if ico.SetSnapToPixelGrid then ico:SetSnapToPixelGrid(false); ico:SetTexelSnappingBias(0) end
            ico:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-unlocked-small.png")
            row._ub = ub
        end
        ub:ClearAllPoints()
        if ed then
            -- The pencil sits 1px low; +1 recenters the unlock icon on the row.
            ub:SetPoint("RIGHT", ed, "LEFT", -4, 1)
        elseif del then
            ub:SetPoint("RIGHT", del, "LEFT", -4, -1)
        else
            ub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
        ub:Show()
        local enabled = opts.unlockEnabled
        ub:SetAlpha(enabled and 0.75 or 0.3)
        ub:SetScript("OnEnter", function(self)
            if enabled then self:SetAlpha(1) end
            if EllesmereUI.ShowWidgetTooltip then
                local tip
                if enabled then
                    tip = L("Customize Unlock Mode")
                else
                    -- Owner-locked (another group provides this spec's unlock mode) has
                    -- its own text; non-membership gets the switch-spec hint.
                    tip = opts.unlockLockedTooltip
                        or L("Switch to a spec in this group to customize its Unlock Mode")
                end
                EllesmereUI.ShowWidgetTooltip(self, tip)
            end
        end)
        ub:SetScript("OnLeave", function(self)
            self:SetAlpha(enabled and 0.75 or 0.3)
            EllesmereUI.HideWidgetTooltip()
        end)
        ub:SetScript("OnClick", function()
            if enabled then opts.onUnlock() end
        end)
    elseif row._ub then
        row._ub:Hide()
    end
    return row, 44
end

-- Seed-map copy for membership adds, MINUS match-owned size keys: a seed member's map
-- can carry stale match-engine widths, and copying them forward replicates the poison
-- onto every spec added to the group. Returns a fresh filtered table per call (never
-- aliases one table across member ids), nil when nothing survives.
local function CopySeedMap(seedMap)
    if not seedMap then return nil end
    local out
    for k, v in pairs(seedMap) do
        if not MatchOwnedFKey(k) then
            out = out or {}
            out[k] = (type(v) == "table") and DeepCopy(v) or v
        end
    end
    return out
end

-- Applies a membership change: ADDED specs receive the group's current override values
-- (copied from the seed member, falling back to the defaults), REMOVED specs lose their
-- stored values (reverting to the baseline on their next apply). The live profile
-- re-syncs immediately so a current-spec join/leave takes effect without a spec swap.
local function SetGroupSpecs(g, newSpecs)
    if _editGroup == g then ExitGroupEdit(true) end
    -- Bank live Buff/Debuff Manager edits into the layer that holds them before
    -- the membership change can move fork ownership (the apply below never harvests).
    EllesmereUI.SpecOverrides_HarvestBmLayout()
    EllesmereUI.SpecOverrides_HarvestDmLayout()
    local oldSet, newSet = {}, {}
    for _, id in ipairs(g.specs or {}) do oldSet[id] = true end
    for _, id in ipairs(newSpecs) do newSet[id] = true end
    local seed = g.specs and g.specs[1]
    for _, entry in ipairs(GetStore() or {}) do
        if entry.group == g.id then
            -- capture the group's canonical values BEFORE removals (the seed
            -- member itself may be leaving)
            local seedMap = seed and entry.values[seed]
            for id in pairs(oldSet) do
                if not newSet[id] then entry.values[id] = nil end
            end
            for _, id in ipairs(newSpecs) do
                if not oldSet[id] then
                    -- Seed ONLY from a real member map: a verbatim copy of
                    -- values.default would pin the new member at the CURRENT
                    -- default forever (the sticky harvest retains held values).
                    -- With no map, WriteSpecValues' per-key default fallback
                    -- gives the same live result and keeps following future
                    -- default edits. Match-owned keys are filtered out.
                    entry.values[id] = CopySeedMap(seedMap)
                end
            end
        end
    end
    g.specs = newSpecs
    -- Added specs must receive the group's values EVERYWHERE those values live, not
    -- only on creator-tagged entries: auto-capture binds edits to an existing entry
    -- by slot identity across the WHOLE store, and session exits bank into every
    -- non-conflicting entry, so a group's member values routinely sit on entries it
    -- never created. The owned-entry loop above misses those, leaving the added spec
    -- with NO map there, so WriteSpecValues' per-key default fallback would resolve
    -- it to the shared default at every apply instead ("the override took my live
    -- value" for a joining CURRENT spec). Mirrors HarvestGroup's store-wide scope.
    -- Runs AFTER g.specs = newSpecs so conflicts judge against NEW membership, and
    -- BEFORE the ex-member sweep so a leaving seed member's foreign maps are still
    -- readable. Empty/absent seed maps write NOTHING, so the default fallback keeps
    -- following future edits and a foreign entry's existing legacy data is untouched.
    for _, entry in ipairs(GetStore() or {}) do
        if entry.group ~= g.id and entry.values and not ConflictSpec(entry, g) then
            local seedMap = seed and entry.values[seed]
            if seedMap and next(seedMap) ~= nil then
                for _, id in ipairs(newSpecs) do
                    if not oldSet[id] then
                        -- Fresh filtered copy PER id; nil when only
                        -- match-owned keys existed.
                        local copy = CopySeedMap(seedMap)
                        if copy then entry.values[id] = copy end
                    end
                end
            end
        end
    end
    -- Removed specs must lose their values EVERYWHERE, not only on this group's
    -- creator-tagged entries: session exits bank into every non-conflicting entry
    -- (shared slots), so a removed spec's values can live on another group's
    -- entries the loop above never looked at, leaving the spec overridden forever
    -- while "not assigned" to anything. Only specs left in NO group are cleared; a
    -- spec still in another group keeps its maps (that group's flows re-derive
    -- them). LEGACY entries (group == nil) are exempt: their per-spec values are
    -- user data this group never owned.
    for id in pairs(oldSet) do
        if not newSet[id] and not SpecInAnyGroup(id) then
            for _, entry in ipairs(GetStore() or {}) do
                if entry.values and entry.group ~= nil then entry.values[id] = nil end
            end
        end
    end
    -- Ingress guard for STRANDED values: a removed spec still in ANOTHER group is
    -- skipped by the blanket sweep above, but values THIS group's sessions banked
    -- onto foreign non-conflicting entries stay behind -- and when every group the
    -- spec still belongs to is conflict-locked against that entry's owner, no
    -- session can ever edit or remove them again (permanently pinned off the shared
    -- default, invisible in the list's group buckets). Removing the spec from this
    -- group means "stop overriding it here", so clear exactly those: only entries
    -- this group could reach BEFORE the change (its own swept in the first loop),
    -- and only values stranded under the NEW membership; values another group can
    -- still reach are kept. Pre-existing strays this group never could reach are
    -- untouched -- the management list surfaces those with a Remove control.
    local oldGroupView = { id = g.id, specs = {} }
    for id in pairs(oldSet) do
        oldGroupView.specs[#oldGroupView.specs + 1] = id
    end
    for id in pairs(oldSet) do
        if not newSet[id] and SpecInAnyGroup(id) then
            for _, entry in ipairs(GetStore() or {}) do
                if entry.values and entry.values[id] ~= nil
                    and entry.group ~= nil and entry.group ~= g.id
                    and not ConflictSpec(entry, oldGroupView)
                    and SpecStrandedOnEntry(entry, id) then
                    entry.values[id] = nil
                end
            end
        end
    end
    -- WoW Forever: when the new membership moves the spec the class acts as,
    -- the converge banks the live layers and values into the outgoing state,
    -- then applies the new spec (one apply). While an editing session or a
    -- spec transition is open it stands down, and that exit applies it.
    local r = EllesmereUI.IS_FOREVER and CurrentSpecID()
    if r and r ~= _activeSpec then
        EllesmereUI._SO_ForeverConverge()
    else
        EllesmereUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
    end
    UpdateIndicator()
    RequestGoldWalk()
    RefreshCardsPopup()
    -- The membership already changed here, even if the name/icon step is cancelled.
    RefreshGroupListingPage()
end

local function EditGroupSpecs(g)
    if not EllesmereUI.ShowSpecAssignPopup then return end
    if cardsPopup then cardsPopup:Hide() end
    local preChecked = {}
    for _, id in ipairs(g.specs or {}) do preChecked[id] = true end
    local dummyDB = { _specOv = { _specs = {} } }
    EllesmereUI:ShowSpecAssignPopup({
        db        = dummyDB,
        dbKey     = "_specOv",
        presetKey = "_specs",
        title     = string.format(L("Edit Group: %s"), g.name or "?"),
        subtitle  = L("Select the specs this group edits:"),
        buttonText = L("Next"),
        preCheckedSpecs = preChecked,
        onConfirm = function(assignments)
            local specs = {}
            for specID, on in pairs(assignments or {}) do
                if on and type(specID) == "number" then
                    specs[#specs + 1] = specID
                end
            end
            table.sort(specs)
            SetGroupSpecs(g, specs)
            -- Step 2: name + icon (same screen the creation flow ends on).
            ShowNameIconPopup(nil, g)
        end,
    })
end

RefreshCardsPopup = function()
    local p = cardsPopup
    if not p or not p:IsShown() then return end
    -- The card rows are pooled (BuildCardRow): hide them all, then lay out the
    -- ones this refresh uses again from the first.
    local cards = p._cards
    if cards then
        for i = 1, #cards do cards[i]:Hide() end
    end
    p._cardN = 0

    local y = -40
    local function add(_, h)
        y = y - h
    end

    -- Default editing mode (exit editing-as). The border tracks the EDITING selection
    -- only (which card's values the panel edits), never the runtime-applied state:
    -- standing in a dungeon must not light the dungeon card while Default is selected.
    add(BuildCardRow(p, y, {
        name = L("Default Editing Mode"),
        active = not _editGroup and not Cond._edit,
        iconApply = function(tex) ApplyGroupIcon(tex, nil) end,
        tooltip = L("Edit normally: changes apply to your current spec"),
        onClick = function()
            ExitGroupEdit()
            if Cond.ExitEdit then Cond.ExitEdit() end
            RefreshCardsPopup()
        end,
    }))

    -- BM page lock: while the Buff Manager page is bound to a live fork,
    -- every group card except the bound one is dimmed and inert.
    local bmLockKind, bmLockGid
    if EllesmereUI.SpecOverrides_BmPageLockInfo then
        bmLockKind, bmLockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
    end
    if not bmLockKind and EllesmereUI.SpecOverrides_DmPageLockInfo then
        bmLockKind, bmLockGid = EllesmereUI.SpecOverrides_DmPageLockInfo()
    end

    -- Saved groups
    local curSpec = CurrentSpecID()
    -- Exclusive unlock-layer ownership: a shared spec's unlock mode belongs to
    -- ONE group (first in creation order with a layout). Every other group's
    -- unlock button is owner-locked for this spec: dimmed with a tooltip naming
    -- the owner (the entry function refuses too; this shows it before a click).
    local curOwnerGid = OwnerGid(curSpec)
    local curOwnerName
    if curOwnerGid then
        local og = GroupById(curOwnerGid)
        curOwnerName = (og and og.name) or "?"
    end
    for _, g in ipairs(GetGroups() or {}) do
        local names = {}
        local isMember = false
        for _, id in ipairs(g.specs or {}) do
            names[#names + 1] = SpecName(id)
            if id == curSpec then isMember = true end
        end
        if EllesmereUI.IS_FOREVER then names = EllesmereUI._SO_ForeverGroupNames(g.specs, curSpec) end
        local ownerLocked = (isMember and curOwnerGid and curOwnerGid ~= g.id) or false
        add(BuildCardRow(p, y, {
            name = g.name or "?",
            active = _editGroup == g,
            locked = (bmLockKind and not (bmLockKind == "spec" and bmLockGid == g.id)) or nil,
            iconApply = function(tex) ApplyGroupIcon(tex, g.icon) end,
            tooltip = table.concat(names, "\n"),
            deletable = true,
            unlockEnabled = isMember and not ownerLocked,
            unlockLockedTooltip = ownerLocked
                and string.format(L("This spec's custom unlock mode is owned by '%s'. Customize it there, or remove the spec from that group."), curOwnerName)
                or nil,
            onUnlock = function()
                p:Hide()
                EllesmereUI.SpecOverrides_EnterUnlockForGroup(g)
            end,
            onEdit = function() EllesmereUI.SpecOverrides_EditOverrideGroup("spec", g.id) end,
            onClick = function()
                if _editGroup == g then
                    ExitGroupEdit()
                else
                    EnterGroupEdit(g)
                end
                RefreshCardsPopup()
            end,
            onDelete = function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Spec Group"),
                    message = string.format(L("Delete the group '%s'? Its captured overrides are removed with it; settings keep their current live values."), g.name or "?"),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if _editGroup == g then ExitGroupEdit(true) end
                        local groups = GetGroups()
                        if groups then
                            for i, gg in ipairs(groups) do
                                if gg == g then table.remove(groups, i); break end
                            end
                        end
                        -- The group's overrides go with it (settings keep
                        -- whatever is live; with the panel open that is the
                        -- Default view's baseline).
                        local st = GetStore()
                        if st then
                            -- Values-aware removal: entries CREATED by this group can carry
                            -- OTHER groups' banked values (session exits bank into every
                            -- non-conflicting entry), so deleting wholesale would destroy
                            -- those overrides plus the shared default. RETAG to the first
                            -- surviving group holding values on the entry; delete only when
                            -- none does (the group is already off the list, so
                            -- EntryHolderGroup sees only survivors).
                            for i = #st, 1, -1 do
                                local e = st[i]
                                if e.group == g.id then
                                    local holder = EntryHolderGroup(e)
                                    if holder then
                                        e.group = holder.id
                                    else
                                        table.remove(st, i)
                                    end
                                end
                            end
                            -- Ex-members now in NO group also lose their values on SURVIVING
                            -- entries (other groups' / shared slots): session exits bank into
                            -- every non-conflicting entry, and without this sweep the deleted
                            -- group's values keep applying to its ex-members forever with no
                            -- card or list row showing why. LEGACY entries (group == nil) are
                            -- exempt: user data this group never owned.
                            for _, sid in ipairs(g.specs or {}) do
                                if not SpecInAnyGroup(sid) then
                                    for _, e in ipairs(st) do
                                        if e.values and e.group ~= nil then e.values[sid] = nil end
                                    end
                                end
                            end
                        end
                        -- The group's custom unlock mode goes with it; if it
                        -- was live, the baseline layout is applied back.
                        EllesmereUI.SpecOverrides_RemoveUnlockLayout(g.id)
                        -- Same for its custom Buff Manager: otherwise the fork stays
                        -- orphaned AND live, with the BM page and preview showing it
                        -- until a reload's establish heals the dangling pointer.
                        EllesmereUI.SpecOverrides_RemoveBmLayout(g.id)
                        EllesmereUI.SpecOverrides_RemoveDmLayout(g.id)
                        RebuildFKeyIndex()
                        RequestGoldWalk()
                        -- WoW Forever: the delete can move the spec the class acts as.
                        if EllesmereUI.IS_FOREVER then EllesmereUI._SO_ForeverConverge() end
                        UpdateIndicator()   -- current spec may have been a member
                        RefreshCardsPopup()
                        RefreshGroupListingPage()
                    end,
                })
            end,
        }))
    end

    -- Add new group
    add(BuildCardRow(p, y, {
        name = L("+ Add New Spec Group"),
        dim = true,
        iconApply = function(tex)
            tex:SetTexture(GLYPH_SPRITE)
            tex:SetTexCoord(0, 0.125, 0, 0.125)
            tex:SetDesaturated(true)
            tex:SetVertexColor(1, 1, 1, 0.25)
        end,
        onClick = function()
            p:Hide()
            StartGroupCreation()
        end,
    }))

    -- ---- Conditional Overrides section (one popup, two systems) ----
    -- Centered, matching the "Spec Overrides" title at the top of the popup.
    do
        local hdr = p._condHdr
        if not hdr then
            hdr = CreateFrame("Frame", nil, p)
            local hl = EllesmereUI.MakeFont(hdr, 13, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
            hl:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 4)
            hl:SetText(L("Conditional Overrides"))
            local sub = EllesmereUI.MakeFont(hdr, 12, nil, 0.55, 0.55, 0.55, 1)
            sub:SetPoint("TOP", hl, "BOTTOM", 0, -2)
            sub:SetText(L("(Spec prio'd for settings conflicts)"))
            p._condHdr = hdr
        end
        hdr:SetSize(p:GetWidth() - 20, 26)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y - 6)
        y = y - 52
    end

    for _, g in ipairs(EllesmereUI.Conditions_GetGroups and EllesmereUI.Conditions_GetGroups() or {}) do
        add(BuildCardRow(p, y, {
            -- Border = editing selection only (never the runtime-applied
            -- state); the keybind toggle state gets a text badge.
            name = (g.name or "?")
                .. (g.conds and g.conds.keybind and g.keyOn and ("  |cffc7a65a" .. L("On") .. "|r") or ""),
            active = Cond._edit == g,
            locked = (bmLockKind and not (bmLockKind == "cond" and bmLockGid == g.id)) or nil,
            iconApply = function(tex) ApplyGroupIcon(tex, g.icon) end,
            tooltip = Cond.GroupTooltip(g),
            deletable = true,
            -- Dark Mode groups are values-only: no custom unlock mode can exist
            -- for them, so the button is not built.
            unlockEnabled = not (g.conds and g.conds.darkmode),
            onUnlock = (not (g.conds and g.conds.darkmode)) and function()
                p:Hide()
                EllesmereUI.Conditions_EnterUnlockForGroup(g)
            end or nil,
            onEdit = function() EllesmereUI.SpecOverrides_EditOverrideGroup("cond", g.id) end,
            onClick = function()
                -- Click = editing-as toggle, exactly like spec group cards.
                if Cond._edit == g then
                    Cond.ExitEdit()
                else
                    Cond.EnterEdit(g)
                end
                RefreshCardsPopup()
            end,
            onDelete = function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Conditional Group"),
                    message = string.format(L("Delete the conditional '%s'? Its captured overrides and custom unlock mode are removed with it."), g.name or "?"),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if Cond._edit == g then Cond.ExitEdit() end
                        local groups = EllesmereUI.Conditions_GetGroups()
                        if groups then
                            for i, gg in ipairs(groups) do
                                if gg == g then table.remove(groups, i); break end
                            end
                        end
                        local st = Cond.GetStore()
                        if st then
                            -- Put each entry's recorded default back on the live profile
                            -- BEFORE dropping it: while this conditional is applied its
                            -- values ARE the live values (the Default view swap covers the
                            -- spec store only), and a removed entry with no writer left would
                            -- silently leave its values as the profile's settings.
                            -- Value-equal no-op when the group was not applied.
                            local touched = {}
                            for i = #st, 1, -1 do
                                if st[i].group == g.id then
                                    Cond.RestoreEntryDefaults(st[i], touched)
                                    table.remove(st, i)
                                end
                            end
                            if next(touched) then RunRefreshers(touched) end
                        end
                        Cond.RebuildIndex()
                        EllesmereUI.Conditions_RemoveUnlockLayout(g.id)
                        -- The group's custom Buff Manager goes with it; if it was live
                        -- (or session-applied) the runtime layer is applied back, else
                        -- the fork stays orphaned AND live until a reload.
                        EllesmereUI.Conditions_RemoveBmLayout(g.id)
                        EllesmereUI.Conditions_RemoveDmLayout(g.id)
                        if EllesmereUI.Conditions_RebuildKeyBindings then EllesmereUI.Conditions_RebuildKeyBindings() end
                        if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
                        RequestGoldWalk()
                        RefreshCardsPopup()
                        -- FORCED rebuild on EVERY page, not just the management tabs: deleting
                        -- an APPLIED conditional changes live values (default restore above
                        -- plus the transition's writes for surviving entries), so open widgets
                        -- would show the deleted override's values until they re-read. Forced
                        -- because restored values can change page STRUCTURE too.
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end,
        }))
    end

    add(BuildCardRow(p, y, {
        name = L("+ Add New Conditional Group"),
        dim = true,
        iconApply = function(tex)
            tex:SetTexture(Cond.ICON_DIR .. Cond.ICONS.dungeon)
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetDesaturated(true)
            tex:SetVertexColor(1, 1, 1, 0.25)
        end,
        onClick = function()
            p:Hide()
            Cond.ShowPickerPopup(nil)
        end,
    }))

    -- Link to the management list (one link for both systems).
    local link = p._link
    if not link then
        link = CreateFrame("Button", nil, p)
        local ll = EllesmereUI.MakeFont(link, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
        ll:SetPoint("CENTER")
        ll:SetText(L("View All / Remove Overrides"))
        link._ll = ll
        link:SetScript("OnEnter", function() ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end)
        link:SetScript("OnLeave", function() ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end)
        link:SetScript("OnClick", function()
            p:Hide()
            -- Profiles & Presets is session-locked (excluded module): leave any
            -- editing session first or the navigation is refused.
            EllesmereUI.SpecOverrides_CloseEditSessions()
            EllesmereUI:SelectModule(PROFILES_MODULE)
            EllesmereUI:SelectPage(LIST_PAGE)
        end)
        p._link = link
    end
    link:SetSize(p:GetWidth() - 20, 22)
    link:ClearAllPoints()
    link:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y - 2)
    link._ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    y = y - 26

    p:SetHeight(-y + 12)
end
SetRefreshCardsPopup(RefreshCardsPopup)

function EllesmereUI.SpecOverrides_ToggleCardsPopup(anchorBtn)
    if cardsPopup and cardsPopup:IsShown() then
        cardsPopup:Hide()
        return
    end
    if not cardsPopup then
        local p = CreateFrame("Frame", nil, EllesmereUI._panelBody or UIParent)
        p:Hide()   -- born hidden so the first Show() fires OnShow (click-off arming)
        p:SetSize(280, 100)
        p:SetFrameStrata("DIALOG")
        p:SetFrameLevel(210)
        p:EnableMouse(true)
        p:SetClampedToScreen(true)
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.99)
        EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)
        local title = EllesmereUI.MakeFont(p, 13, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        title:SetPoint("TOP", p, "TOP", 0, -12)
        title:SetText(L("Spec Overrides"))

        -- Click-anywhere-to-close, same pattern as the dropdown widgets: a
        -- global mouse-down listener (non-blocking, world clicks pass through).
        -- Clicks on the spec button / indicator are excluded so their own
        -- OnClick handles the toggle instead of close-then-reopen.
        local clickOff = CreateFrame("Frame")
        clickOff:Hide()
        clickOff:SetScript("OnEvent", function()
            -- A modal dialog (delete confirm / spec picker) owns clicks while
            -- shown; interacting with it must not close the popup.
            local confirmDim = _G.EUIConfirmDimmer
            if confirmDim and confirmDim:IsShown() then return end
            local assignDim = _G.EUISpecAssignDimmer
            if assignDim and assignDim:IsShown() then return end
            if p:IsShown() and not p:IsMouseOver()
               and not (specBtn and specBtn:IsMouseOver())
               and not (indicatorBtn and indicatorBtn:IsShown() and indicatorBtn:IsMouseOver()) then
                p:Hide()
            end
        end)
        p:HookScript("OnShow", function()
            -- Defer registration one frame so the mouse-down that opened the
            -- popup does not immediately close it.
            C_Timer.After(0, function()
                if p:IsShown() then
                    clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN")
                    clickOff:Show()
                end
            end)
        end)
        p:HookScript("OnHide", function()
            clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            clickOff:Hide()
        end)

        cardsPopup = p
        EllesmereUI._specOvCardsPopup = p
    end
    cardsPopup:ClearAllPoints()
    if anchorBtn then
        cardsPopup:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 4, -8)
    else
        cardsPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    cardsPopup:Show()
    RefreshCardsPopup()
    EnsurePanelHideHook()
end

--- Editing-as toggle for one override group, like clicking its card in the
--- cards popup, but switching directly past the manager page lock (the
--- manager sidebar's override list). kind "spec"|"cond". The lock is only
--- skipped when the target's fork can go live here; otherwise the page would
--- open covered by the "info" overlay, so the lock's popup explains instead.
function EllesmereUI.SpecOverrides_ToggleOverrideEdit(kind, gid)
    local lockKind, lockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
    if not lockKind then lockKind, lockGid = EllesmereUI.SpecOverrides_DmPageLockInfo() end
    if kind == "spec" then
        local g = GroupById(gid)
        if not g then return end
        -- Eligible: a member spec, and no OTHER group owns the live spec fork.
        local cur, member = CurrentSpecID(), false
        for _, sid in ipairs(g.specs or {}) do
            if sid == cur then member = true; break end
        end
        local force = member and not (lockKind == "spec" and lockGid ~= g.id)
        if _editGroup == g then ExitGroupEdit() else EnterGroupEdit(g, force) end
    elseif kind == "cond" then
        local g = EllesmereUI.Conditions_GroupById(gid)
        if not g then return end
        -- A live spec fork means a spec owner exists, and spec wins.
        local force = lockKind ~= "spec"
        if Cond._edit == g then Cond.ExitEdit() else Cond.EnterEdit(g, force) end
    end
    RefreshCardsPopup()
end

--- The cards popup's pencil for one override group (spec: specs, then name and
--- icon; cond: the condition picker), for the manager sidebar's override list.
function EllesmereUI.SpecOverrides_EditOverrideGroup(kind, gid)
    if kind == "spec" then
        local g = GroupById(gid)
        if g then EditGroupSpecs(g) end
    elseif kind == "cond" then
        local g = EllesmereUI.Conditions_GroupById(gid)
        if not g then return end
        if cardsPopup then cardsPopup:Hide() end
        Cond.ShowPickerPopup(g)
    end
end

-------------------------------------------------------------------------------
--  CONDITIONAL OVERRIDES UI: toolbar button, cards popup, condition picker
--  (with keybind capture), name/icon popup. Mirrors the spec-overrides UI
--  one-for-one; the group icon picker reuses the class/role set.
-------------------------------------------------------------------------------

function Cond.GroupTooltip(g)
    local parts = {}
    for _, def in ipairs(EllesmereUI.CONDITIONS or {}) do
        if g.conds and g.conds[def.id] then
            local line = L(def.label)
            if def.id == "keybind" then
                line = line .. ": " .. (g.key and (GetBindingText and GetBindingText(g.key) or g.key) or L("no key set"))
            end
            parts[#parts + 1] = line
        end
    end
    return table.concat(parts, "\n")
end

-- ---- name + icon popup (cond variant; icon grid reuses role/class art) ------
function Cond.ShowNameIconPopup(conds, keyStr, existing)
    local p = Cond._namePopup
    if not p then
        -- Conditional icon set (one per condition), in ladder/display order.
        local defs = {}
        for _, cdef in ipairs(EllesmereUI.CONDITIONS or {}) do
            if Cond.ICONS[cdef.id] then
                defs[#defs + 1] = { kind = "cond", key = cdef.id }
            end
        end
        p = BuildNameIconPopup(defs, function(p)
            local conds2 = p._conds
            if not conds2 or not next(conds2) then p:Hide(); return end
            local name = p._nameBox:GetText()
            local newGroup
            if p._existing then
                local g = p._existing
                if name and name ~= "" then g.name = name end
                if p._selectedIcon then g.icon = p._selectedIcon end
                g.conds = conds2
                g.key = conds2.keybind and p._key or nil
                if not conds2.keybind then g.keyOn = nil end
            else
                local groups = EllesmereUI.Conditions_GetGroups(true)
                if not groups then p:Hide(); return end
                local id = EllesmereUI.Conditions_NewGroupId()
                if not name or name == "" then name = L("Conditional") .. " " .. id end
                -- Default icon: the first checked condition (ladder order).
                local defIcon = p._selectedIcon
                if not defIcon then
                    for _, cdef in ipairs(EllesmereUI.CONDITIONS or {}) do
                        if conds2[cdef.id] and Cond.ICONS[cdef.id] then
                            defIcon = { kind = "cond", key = cdef.id }
                            break
                        end
                    end
                end
                newGroup = {
                    id = id, name = name,
                    icon = defIcon or { kind = "cond", key = "dungeon" },
                    conds = conds2,
                    key = conds2.keybind and p._key or nil,
                }
                groups[#groups + 1] = newGroup
            end
            p:Hide()
            if EllesmereUI.Conditions_RebuildKeyBindings then EllesmereUI.Conditions_RebuildKeyBindings() end
            if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
            -- Auto-activate: a new conditional goes straight into its edit
            -- session (matches the spec-group create flow). Cond.EnterEdit
            -- self-guards the BM page lock and any active session.
            if newGroup then Cond.EnterEdit(newGroup) end
            Cond.RefreshCards()
            RefreshGroupListingPage()
        end)
        Cond._namePopup = p
    end
    p._conds = conds
    p._key = keyStr
    p._existing = existing
    p._title:SetText(existing and L("Edit Conditional Group") or L("New Conditional Group"))
    p._createLbl:SetText(existing and L("Save") or L("Create Group"))
    p._nameBox:SetText(existing and (existing.name or "") or "")
    -- Pre-select the group's saved icon, else the icon matching its first
    -- checked condition (ladder order).
    local want
    if existing and existing.icon then
        want = existing.icon
    else
        for _, cdef in ipairs(EllesmereUI.CONDITIONS or {}) do
            if conds and conds[cdef.id] and Cond.ICONS[cdef.id] then
                want = { kind = "cond", key = cdef.id }
                break
            end
        end
    end
    p._selectedIcon = nil
    for _, ob in ipairs(p._iconBtns) do
        local sel = want and ob._def
            and want.kind == ob._def.kind and want.key == ob._def.key
        ob:SetAlpha(sel and 1 or 0.7)
        if ob._brd and ob._brd.SetColor then
            if sel then
                ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                p._selectedIcon = ob._def
            else
                ob._brd:SetColor(1, 1, 1, 0.10)
            end
        end
    end
    p:Show()
    -- Controller cursor: move it into the popup.
    EllesmereUI.PadFocus(p)
end

-- ---- condition picker popup (checklist + keybind capture) -------------------
function Cond.ShowPickerPopup(existing)
    local p = Cond._pickerPopup
    if not p then
        -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
        p = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        p:SetSize(340, 100)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(220)
        p:EnableMouse(true)
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)

        local title = EllesmereUI.MakeFont(p, 14, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        title:SetPoint("TOP", p, "TOP", 0, -14)
        p._title = title
        local sub = EllesmereUI.MakeFont(p, 11, nil, 1, 1, 1, 0.5)
        sub:SetPoint("TOP", p, "TOP", 0, -32)
        sub:SetText(L("Select the conditions that activate this group:"))

        p._rows = {}
        local y = -52
        for _, def in ipairs(EllesmereUI.CONDITIONS) do
            local row = CreateFrame("Button", nil, p)
            row:SetSize(300, 24)
            row:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
            local box = row:CreateTexture(nil, "ARTWORK")
            box:SetSize(14, 14)
            box:SetPoint("LEFT", row, "LEFT", 0, 0)
            box:SetColorTexture(0.10, 0.10, 0.11, 0.9)
            local check = row:CreateTexture(nil, "OVERLAY")
            check:SetSize(8, 8)
            check:SetPoint("CENTER", box, "CENTER", 0, 0)
            check:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            check:Hide()
            local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1, def.comingSoon and 0.35 or 0.85)
            lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
            lbl:SetText(L(def.label) .. (def.comingSoon and ("  |cff888888" .. L("Coming Soon") .. "|r") or ""))
            row._check = check
            row._condID = def.id
            if def.comingSoon then
                row:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, L("This condition is coming in a future update."))
                end)
                row:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                end)
            elseif def.requires then
                -- Requirement-gated condition (e.g. Dark Mode needs every Dark Mode row
                -- but Class Resource Bar on). CHECKING is refused while unmet;
                -- UNchecking always works, so an existing group can never be trapped
                -- by a requirement that later went false. Dim state is per-open (rows
                -- build once, the popup is reused).
                row._reqFn = def.requires
                row._lbl = lbl
                row:SetScript("OnClick", function(self)
                    if not p._staged[self._condID] and not self._reqFn() then return end
                    p._staged[self._condID] = not p._staged[self._condID] or nil
                    self._check:SetShown(p._staged[self._condID] and true or false)
                    p._syncKeyRow()
                    if p._refreshReqRows then p._refreshReqRows() end
                end)
                row:SetScript("OnEnter", function(self)
                    -- The requirement hint while it would refuse a check, else
                    -- the condition's own tooltip (what keeps it active).
                    local tip = def.tooltip
                    if not p._staged[self._condID] and not self._reqFn() and def.requiresHint then
                        tip = def.requiresHint
                    end
                    if tip and EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, L(tip))
                    end
                end)
                row:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                end)
            else
                row:SetScript("OnClick", function(self)
                    p._staged[self._condID] = not p._staged[self._condID] or nil
                    self._check:SetShown(p._staged[self._condID] and true or false)
                    p._syncKeyRow()
                end)
            end
            p._rows[#p._rows + 1] = row
            y = y - 26
        end

        -- Re-evaluated per open and per click: requirement-gated rows dim while
        -- unmet; checked rows stay bright (uncheckable-only, never trapped).
        p._refreshReqRows = function()
            for _, r in ipairs(p._rows) do
                if r._reqFn and r._lbl then
                    local bright = r._reqFn() or p._staged[r._condID]
                    r._lbl:SetAlpha(bright and 1 or 0.4)
                end
            end
        end

        -- Keybind capture row (shown only while the keybind condition is
        -- checked): click, press a key, ESC cancels.
        local keyRow = CreateFrame("Frame", nil, p)
        keyRow:SetSize(300, 26)
        keyRow:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y - 4)
        local keyLbl = EllesmereUI.MakeFont(keyRow, 12, nil, 1, 1, 1, 0.6)
        keyLbl:SetPoint("LEFT", keyRow, "LEFT", 0, 0)
        keyLbl:SetText(L("Toggle Key"))
        local keyBtn = CreateFrame("Button", nil, keyRow)
        keyBtn:SetSize(150, 22)
        keyBtn:SetPoint("LEFT", keyLbl, "RIGHT", 12, 0)
        EllesmereUI.SolidTex(keyBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local kbrd = EllesmereUI.MakeBorder(keyBtn, 1, 1, 1, 0.22)
        local kl = EllesmereUI.MakeFont(keyBtn, 11, nil, 1, 1, 1, 0.85)
        kl:SetPoint("CENTER")
        p._keyRow, p._keyLblFS = keyRow, kl
        local function ShowKeyText()
            if p._capturing then
                kl:SetText(L("Press a key..."))
            elseif p._stagedKey then
                kl:SetText(GetBindingText and GetBindingText(p._stagedKey) or p._stagedKey)
            else
                kl:SetText(L("Click to Set Key"))
            end
        end
        p._showKeyText = ShowKeyText
        keyBtn:SetScript("OnClick", function()
            p._capturing = not p._capturing
            p:EnableKeyboard(p._capturing and true or false)
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(not p._capturing) end
            ShowKeyText()
        end)
        p:SetScript("OnKeyDown", function(_, key)
            if not p._capturing then return end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
               or key == "LALT" or key == "RALT" then
                return
            end
            p._capturing = false
            p:EnableKeyboard(false)
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(true) end
            if key ~= "ESCAPE" then
                local mods = ""
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                p._stagedKey = mods .. key
            end
            ShowKeyText()
        end)
        local keyClear = CreateFrame("Button", nil, keyRow)
        keyClear:SetSize(20, 20)
        keyClear:SetPoint("LEFT", keyBtn, "RIGHT", 6, 0)
        local kx = EllesmereUI.MakeFont(keyClear, 13, nil, 1, 1, 1, 0.6)
        kx:SetPoint("CENTER")
        kx:SetText("x")
        keyClear:SetScript("OnEnter", function() kx:SetTextColor(1, 0.4, 0.4, 1) end)
        keyClear:SetScript("OnLeave", function() kx:SetTextColor(1, 1, 1, 0.6) end)
        keyClear:SetScript("OnClick", function()
            p._stagedKey = nil
            ShowKeyText()
        end)

        p._syncKeyRow = function()
            keyRow:SetShown(p._staged.keybind and true or false)
            local extra = p._staged.keybind and 34 or 0
            p:SetHeight(-y + 56 + extra)
            ShowKeyText()
        end

        local nextBtn = CreateFrame("Button", nil, p)
        nextBtn:SetSize(110, 28)
        -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
        nextBtn:SetPoint("BOTTOM", p, "BOTTOM", 44, 14)
        EllesmereUI.SolidTex(nextBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local nbrd = EllesmereUI.MakeBorder(nextBtn, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
        local nlbl = EllesmereUI.MakeFont(nextBtn, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        nlbl:SetPoint("CENTER")
        nlbl:SetText(L("Next"))
        nextBtn:SetScript("OnEnter", function() if nbrd and nbrd.SetColor then nbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end end)
        nextBtn:SetScript("OnLeave", function() if nbrd and nbrd.SetColor then nbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end end)
        nextBtn:SetScript("OnClick", function()
            if not next(p._staged) then return end
            if p._staged.keybind and not p._stagedKey then
                EllesmereUI.ShowWidgetTooltip(nextBtn, L("Set the toggle key first (or uncheck Keybind)."))
                return
            end
            local conds = {}
            for k, v in pairs(p._staged) do conds[k] = v end
            p:Hide()
            Cond.ShowNameIconPopup(conds, p._stagedKey, p._editing)
        end)

        local cancel = CreateFrame("Button", nil, p)
        cancel:SetSize(80, 28)
        cancel:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
        EllesmereUI.SolidTex(cancel, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local xbrd2 = EllesmereUI.MakeBorder(cancel, 1, 1, 1, 0.22)
        local xlbl2 = EllesmereUI.MakeFont(cancel, 12, nil, 1, 1, 1, 0.7)
        xlbl2:SetPoint("CENTER")
        xlbl2:SetText(L("Cancel"))
        cancel:SetScript("OnEnter", function() if xbrd2 and xbrd2.SetColor then xbrd2:SetColor(1, 1, 1, 0.4) end end)
        cancel:SetScript("OnLeave", function() if xbrd2 and xbrd2.SetColor then xbrd2:SetColor(1, 1, 1, 0.22) end end)
        cancel:SetScript("OnClick", function()
            p._capturing = false
            p:EnableKeyboard(false)
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(true) end
            p:Hide()
        end)

        -- Controller cursor: its cancel press backs out through Cancel, and the
        -- panel is a blocker, not a stop.
        if EllesmereUI.PadCP() then p.CloseButton = cancel end
        EllesmereUI.TrackOverlay(p)
        EllesmereUI.PadHint(p, "nodepass")
        Cond._pickerPopup = p
    end
    p._editing = existing
    p._staged = {}
    p._stagedKey = existing and existing.key or nil
    p._capturing = false
    if existing and existing.conds then
        for k, v in pairs(existing.conds) do p._staged[k] = v end
    end
    for _, row in ipairs(p._rows) do
        row._check:SetShown(p._staged[row._condID] and true or false)
    end
    if p._refreshReqRows then p._refreshReqRows() end
    p._title:SetText(existing and string.format(L("Edit Conditional: %s"), existing.name or "?")
        or L("New Conditional Group"))
    p._syncKeyRow()
    p:Show()
    -- Controller cursor: move it into the popup.
    EllesmereUI.PadFocus(p)
end

-- ---- cards popup: UNIFIED with the spec overrides popup ----------------------
-- Conditional cards render as a second section inside RefreshCardsPopup; this alias
-- points every cond-side refresh at the one popup.
Cond.RefreshCards = function()
    if RefreshCardsPopup then RefreshCardsPopup() end
end

I.broken = false
