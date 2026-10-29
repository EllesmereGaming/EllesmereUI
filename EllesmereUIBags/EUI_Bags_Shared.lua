if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Shared.lua
--
--  The pieces the bank shares through ns (inset border, item button skin,
--  sidebar header, grid scrollbar), controller support and the stack
--  splitter.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local GetItemInfoInstant = C_Item.GetItemInfoInstant
local EUI = EllesmereUI

local BP, GetFont, SetBagFont = I.BP, I.GetFont, I.SetBagFont

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = I.selectedCategoryIndex
I.categoryIndexSetters[#I.categoryIndexSetters + 1] = function(v) selectedCategoryIndex = v end

-------------------------------------------------------------------------------
--  Inset border helper (1 physical pixel inside frame edge)
-------------------------------------------------------------------------------
local function CreateInsetBorder(btn)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local t = btn:CreateTexture(nil, "OVERLAY", nil, 2); t:SetTexture(WHITE)
    t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    t:SetHeight(px)
    local b = btn:CreateTexture(nil, "OVERLAY", nil, 2); b:SetTexture(WHITE)
    b:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(px)
    local l = btn:CreateTexture(nil, "OVERLAY", nil, 2); l:SetTexture(WHITE)
    l:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    l:SetWidth(px)
    local r = btn:CreateTexture(nil, "OVERLAY", nil, 2); r:SetTexture(WHITE)
    r:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(px)
    btn._brdT, btn._brdB, btn._brdL, btn._brdR = t, b, l, r
end

local function SetInsetBorderColor(btn, cr, cg, cb, ca)
    if btn._brdT then
        btn._brdT:SetColorTexture(cr, cg, cb, ca)
        btn._brdB:SetColorTexture(cr, cg, cb, ca)
        btn._brdL:SetColorTexture(cr, cg, cb, ca)
        btn._brdR:SetColorTexture(cr, cg, cb, ca)
    end
end

-- Border thickness in px (1 normally, 2 for quest items); must be re-applied per render because item buttons are pooled.
local function SetInsetBorderThickness(btn, px)
    if btn._brdT then
        btn._brdT:SetHeight(px)
        btn._brdB:SetHeight(px)
        btn._brdL:SetWidth(px)
        btn._brdR:SetWidth(px)
    end
end

-------------------------------------------------------------------------------
--  Shared with the bank (EllesmereUIBags_Bank.lua loads after this file) via ns
-------------------------------------------------------------------------------
ns.CreateInsetBorder = CreateInsetBorder
ns.SetBagFont = SetBagFont
ns.SetInsetBorderColor = SetInsetBorderColor

-- Item buttons (ContainerFrameItemButtonTemplate) carry frameLevel="10" in
-- Blizzard's XML, a fixed level that never follows their window: under a window
-- raised past it (High starts at 100) the window takes the clicks. So each one
-- sits at its window's level + 9: the template's own 10 over a window at level 1,
-- under Compact's drop zones (window + 22). The text overlay (+3, above the
-- cooldown swipe) and the warbank dim (+6) are fixed levels too and move with it.
local function PinItemButtonLevel(btn, level)
    btn:SetFrameLevel(level)
    if btn._textOverlay then btn._textOverlay:SetFrameLevel(level + 3) end
    if btn._warbankDim then btn._warbankDim:SetFrameLevel(level + 6) end
    -- Item Icons' marks (+4, a fixed level as well) follow (EUI_Bags_Slots.lua)
    if ns.ItemIconsRepin then ns.ItemIconsRepin(btn) end
end

-- background color/opacity for bags and bank: the texture fades with the
-- opacity, the tint on top takes the color
function ns.ApplyWindowBackground(bg, overlay)
    if not (bg and overlay) then return end
    local p = BP()
    local o = (p.bagBgOpacity or 100) / 100
    local c = p.bagBgColor
    bg:SetAlpha(o)
    overlay:SetColorTexture(c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 0.25)
    overlay:SetAlpha(o)
end

-- slot background: tint over an empty slot's backdrop, alpha is the slot's
-- own base opacity. each painted one is kept (weakly) so a color change can
-- retint them without a relayout
local slotBgs = setmetatable({}, { __mode = "k" })
function ns.PaintSlotBackground(tex, alpha)
    tex._slotBgAlpha = alpha
    slotBgs[tex] = true
    local c = BP().bagSlotBgColor
    if c then
        tex:SetVertexColor(c.r, c.g, c.b)
        tex:SetAlpha(alpha * (c.a or 1))
    else
        tex:SetVertexColor(1, 1, 1)
        tex:SetAlpha(alpha)
    end
end

-- the slot background picker: just the shown ones (hidden ones get painted when they show)
function ns.RetintSlotBackgrounds()
    for tex in pairs(slotBgs) do
        if tex:IsVisible() then ns.PaintSlotBackground(tex, tex._slotBgAlpha) end
    end
end

function ns.PinItemButton(btn, window)
    PinItemButtonLevel(btn, window:GetFrameLevel() + 9)
end

-- Re-pins a pool after its window's level moved (a strata change, a raise), once
-- per level: window[memoKey] holds the level the pool was last pinned at. Nothing
-- else moves these buttons, and new ones are pinned at creation from the live level.
function ns.PinItemPool(pool, window, memoKey)
    local level = window:GetFrameLevel() + 9
    if window[memoKey] == level then return end
    window[memoKey] = level
    for _, btn in pairs(pool) do PinItemButtonLevel(btn, level) end
end

-- Flat look for a ContainerFrameItemButtonTemplate slot, plus the text overlay
-- (above the cooldown swipe) with Count, ItemLevelText and BindTypeText.
-- Methods only: writing properties onto Blizzard template sub-objects taints.
-- opts: anchorIcon (re-anchor icon to the button), cooldownFont (restyle the
-- cooldown text), flatHighlight (bank: 8% white highlight, with highlight and
-- pushed textures looked up by template field first). Returns the overlay.
function ns.SkinItemButton(btn, opts)
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end

    ns.SizeSlot(btn)
    if btn.icon then
        local z = BP().bagItemIconZoom or 0.08
        btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        if opts.anchorIcon then
            btn.icon:ClearAllPoints()
            btn.icon:SetAllPoints(btn)
        end
    end

    local ht, pt
    if opts.flatHighlight then
        ht = btn.HighlightTexture or btn:GetHighlightTexture()
        if ht then ht:SetTexture(nil); ht:SetColorTexture(1, 1, 1, 0.08) end
        pt = btn.PushedTexture or btn:GetPushedTexture()
    else
        ht = btn:GetHighlightTexture()
        pt = btn:GetPushedTexture()
    end
    if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints(); pt:SetAllPoints(btn)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
    end

    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end

    if btn.icon and btn.IconMask then
        btn.icon:RemoveMaskTexture(btn.IconMask)
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end

    if opts.cooldownFont and btn.Cooldown then
        local cdText = btn.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            EllesmereUI.ApplyIconTextFont(cdText, GetFont(), 11, "bags")
        end
    end

    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(btn:GetFrameLevel() + 3)
    btn._textOverlay = textOverlay

    local fontPath = GetFont()
    local outline = (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        EllesmereUI.ApplyIconTextFont(countFS, fontPath, BP().bagCountFontSize or 11, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    -- Item level text (top-left, gear only)
    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    btn.ItemLevelText:SetFont(fontPath, BP().itemlevelFontSize or 12, outline)
    btn.ItemLevelText:SetText("")

    -- Bind Type text (bottom-left)
    if not btn.BindTypeText then
        btn.BindTypeText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.BindTypeText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 2)
        btn.BindTypeText:SetTextColor(1, 1, 1, 1)
    end
    btn.BindTypeText:SetFont(fontPath, BP().bagBindTypeFontSize or 11, outline)
    btn.BindTypeText:SetText("")
    return textOverlay
end

-- The sidebar's 12 px collapse / expand arrow (the caller anchors it and turns
-- its icon): 0.4 alpha, 0.9 on hover with its tooltip (a string, or a
-- function returning one).
do
    local function ArrowOnEnter(self)
        self._icon:SetAlpha(0.9)
        local tip = self._tip
        if type(tip) == "function" then tip = tip() end
        EUI.ShowWidgetTooltip(self, tip)
    end
    local function ArrowOnLeave(self)
        self._icon:SetAlpha(0.4)
        EUI.HideWidgetTooltip()
    end
    function ns.SidebarArrowButton(parent, tip)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(12, 12)
        btn._icon = btn:CreateTexture(nil, "OVERLAY")
        btn._icon:SetAllPoints()
        btn._icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png")
        btn._icon:SetAlpha(0.4)
        btn._tip = tip
        btn:SetScript("OnEnter", ArrowOnEnter)
        btn:SetScript("OnLeave", ArrowOnLeave)
        return btn
    end
end

-- Sidebar header: label + collapse arrow for the profile flag dbKey. The
-- caller's OnClick flips the flag, then calls the returned UpdateArrow.
function ns.CreateSidebarHeader(sidebar, label, dbKey)
    local hdr = CreateFrame("Frame", nil, sidebar)
    hdr:SetHeight(24)
    hdr:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

    hdr._label = hdr:CreateFontString(nil, "OVERLAY")
    SetBagFont(hdr._label, 10)
    hdr._label:SetPoint("LEFT", hdr, "LEFT", 8, 0)
    hdr._label:SetText(label)
    hdr._label:SetTextColor(0.5, 0.5, 0.5)

    local collapseBtn = ns.SidebarArrowButton(hdr, function()
        return BP()[dbKey] and "Expand Sidebar" or "Collapse Sidebar"
    end)

    local function UpdateArrow()
        collapseBtn:ClearAllPoints()
        if BP()[dbKey] then
            collapseBtn._icon:SetRotation(math.pi)
            collapseBtn:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        else
            collapseBtn._icon:SetRotation(0)
            collapseBtn:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
        end
    end
    UpdateArrow()
    return hdr, collapseBtn, UpdateArrow
end

-- Item-grid scrollbar: a 4px thumb in a 16px hit strip; the caller anchors the
-- returned track. Scrolls instantly, not smoothed (so not AttachSmoothScrollbar).
-- clamp: pull the scroll back into range on every update (content may have
-- shrunk). rawWheel: the wheel reads sf's scroll range directly rather than the
-- thumb metrics, which give up when the track is too short for a thumb.
local SCROLLBAR_HIT_W = 16  -- invisible hit area width
function ns.AttachGridScrollbar(host, sf, clamp, rawWheel)
    local SCROLLBAR_W = 4   -- thumb width
    local SCROLL_STEP = 40  -- pixels per mouse wheel tick
    local THUMB_MIN_H = 20  -- minimum thumb height

    local track = CreateFrame("Button", nil, host)
    track:SetWidth(SCROLLBAR_HIT_W)
    track:SetFrameLevel(sf:GetFrameLevel() + 5)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetWidth(SCROLLBAR_W)
    trackBg:SetPoint("TOP", track, "TOP", 0, 0)
    trackBg:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    trackBg:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    trackBg:SetColorTexture(1, 1, 1, 0.06)

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(SCROLLBAR_W)
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:Hide()

    local _isDragging = false
    local _dragStartY = 0
    local _dragStartPct = 0

    local function GetScrollMetrics()
        local scrollRange = sf:GetVerticalScrollRange()
        if not scrollRange or scrollRange <= 0 then return nil end
        local trackH = track:GetHeight()
        local ext = sf:GetHeight() / (sf:GetHeight() + scrollRange)
        local thumbH = math.max(THUMB_MIN_H, trackH * ext)
        local maxTravel = trackH - thumbH
        if maxTravel <= 0 then return nil end
        local pct = sf:GetVerticalScroll() / scrollRange
        return pct, thumbH, maxTravel, scrollRange
    end

    local function UpdateThumb()
        if clamp then
            local range = sf:GetVerticalScrollRange() or 0
            local cur = sf:GetVerticalScroll()
            if cur > range then sf:SetVerticalScroll(range) end
        end
        local pct, thumbH, maxTravel = GetScrollMetrics()
        if not pct then
            thumb:Hide()
            trackBg:Hide()
            return
        end
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(pct * maxTravel))
        thumb:Show()
        trackBg:Show()
    end

    -- On the scroll frame and on host (items might not cover the full area)
    local function OnWheel(_, delta)
        local scrollRange
        if rawWheel then
            scrollRange = sf:GetVerticalScrollRange()
            if scrollRange and scrollRange <= 0 then scrollRange = nil end
        else
            scrollRange = select(4, GetScrollMetrics())
        end
        if not scrollRange then return end
        local cur = sf:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
        sf:SetVerticalScroll(newVal)
        UpdateThumb()
    end
    sf:SetScript("OnMouseWheel", OnWheel)
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", OnWheel)

    -- Thumb dragging (dragUpdate must be declared before OnMouseDown uses it)
    local dragUpdate = CreateFrame("Frame")
    dragUpdate:Hide()
    dragUpdate:SetScript("OnUpdate", function(self)
        if not _isDragging then self:Hide(); return end
        if not IsMouseButtonDown("LeftButton") then
            _isDragging = false; self:Hide()
            thumb:SetColorTexture(1, 1, 1, 0.25)
            return
        end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then _isDragging = false; self:Hide(); return end
        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local deltaY = (_dragStartY - cy / scale)
        local deltaPct = deltaY / maxTravel
        local newPct = math.max(0, math.min(1, _dragStartPct + deltaPct))
        sf:SetVerticalScroll(newPct * scrollRange)
        UpdateThumb()
    end)

    track:RegisterForDrag("LeftButton")
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then return end

        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local trackTop = track:GetTop() * scale
        local cursorLocalY = (trackTop - cy) / scale

        -- Check if cursor is on the thumb
        local thumbTop = pct * maxTravel
        local thumbBot = thumbTop + thumbH
        if cursorLocalY >= thumbTop and cursorLocalY <= thumbBot then
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = pct
            dragUpdate:Show()
        else
            -- Click on track: jump to position
            local clickPct = math.max(0, math.min(1, (cursorLocalY - thumbH / 2) / maxTravel))
            sf:SetVerticalScroll(clickPct * scrollRange)
            UpdateThumb()
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = clickPct
            dragUpdate:Show()
        end
    end)

    track:SetScript("OnMouseUp", function()
        _isDragging = false
    end)

    track:SetScript("OnEnter", function() thumb:SetColorTexture(1, 1, 1, 0.4) end)
    track:SetScript("OnLeave", function()
        if not _isDragging then thumb:SetColorTexture(1, 1, 1, 0.25) end
    end)

    -- Controller cursor (a pad has no wheel): one-notch step buttons at the
    -- track ends, a visible track, a thumb that follows every scroll (the
    -- cursor scrolls the grid itself) and a track that is not a cursor stop
    -- (a press there would jump to the hidden pointer). The owner calls
    -- track.PadSync(on) at its show edge; nothing is built before a
    -- controller is in use.
    local padUp, padDown, padOn
    local function PadSteps()
        local show = padOn and trackBg:IsShown() or false
        padUp:SetShown(show)
        padDown:SetShown(show)
    end
    function track.PadSync(on)
        on = on and true or false
        if not padUp then
            if not on then return end
            padUp, padDown = ns.PadStepButtons(host, SCROLLBAR_HIT_W, function(delta) OnWheel(nil, delta) end)
            padUp:SetFrameLevel(track:GetFrameLevel() + 1)
            padDown:SetFrameLevel(track:GetFrameLevel() + 1)
            padUp:SetPoint("TOP", track, "TOP", 0, 0)
            padDown:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
            hooksecurefunc(trackBg, "Show", PadSteps)
            hooksecurefunc(trackBg, "Hide", PadSteps)
            sf:HookScript("OnVerticalScroll", function() UpdateThumb() end)
            EUI.PadHint(track, "nodeignore")
        end
        if on == padOn then return end
        padOn = on
        trackBg:SetColorTexture(1, 1, 1, on and 0.15 or 0.06)
        PadSteps()
    end
    return track, thumb, UpdateThumb
end

-------------------------------------------------------------------------------
--  Controller support (the bags and the bank). Everything here runs only on
--  an edge that already exists (a show, a click, a menu open) behind the
--  shared controller signal; mouse/keyboard players never build any of it.
-------------------------------------------------------------------------------
do
    local ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
    local ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"

    local function MakeStep(parent, size, icon, onClick)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(size, size)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(size - 4, size - 4)
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        t:SetTexture(icon)
        b:SetAlpha(0.5)
        b:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        b:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        b:SetScript("OnClick", onClick)
        b:Hide()
        return b
    end

    -- Up/down step buttons for a wheel-only scroller: step(1) scrolls up one
    -- notch, step(-1) down. Created hidden; the caller anchors them.
    function ns.PadStepButtons(parent, size, step)
        return MakeStep(parent, size, ARROW_UP, function() step(1) end),
               MakeStep(parent, size, ARROW_DOWN, function() step(-1) end)
    end

    -- Sidebar step buttons (categories, bank tabs) in the sidebar header, left
    -- of the collapse arrow: shown while a controller is in use, the sidebar
    -- is expanded and its entries overflow. Each click runs the sidebar's own
    -- wheel handler once (one entry). Called at the window's show edge.
    local function SidebarStepsUpdate(st)
        local show = st.on and not BP()[st.key] and (st.child:GetHeight() - st.sf:GetHeight()) > 0.5
        st.up:SetShown(show)
        st.down:SetShown(show)
    end

    function ns.PadSidebarSync(hdr, sf, child, dbKey, on)
        if not (hdr and sf and child) then return end
        local st = hdr._padSteps
        if not st then
            if not on then return end
            local up, down = ns.PadStepButtons(hdr, 14, function(delta)
                local wheel = sf:GetScript("OnMouseWheel")
                if wheel then wheel(sf, delta) end
            end)
            down:SetPoint("RIGHT", hdr, "RIGHT", -22, 0)
            up:SetPoint("RIGHT", down, "LEFT", -2, 0)
            st = { up = up, down = down, sf = sf, child = child, key = dbKey }
            hdr._padSteps = st
            -- The rebuild sets the list height; the window can resize it too.
            local function Update() SidebarStepsUpdate(st) end
            hooksecurefunc(child, "SetHeight", Update)
            sf:HookScript("OnSizeChanged", Update)
        end
        st.on = on and true or false
        SidebarStepsUpdate(st)
    end

    -- Blizzard's bag frames live under a hidden parent. One that its own
    -- toggle opened keeps reporting shown after we close the bags ourselves,
    -- so the next Back press counts as "closed a bag" and does nothing else.
    -- Only frames that are shown but not visible (still under that parent)
    -- are touched, and no Blizzard OnHide runs for them.
    function ns.PadReleaseBlizzBags()
        local f = ContainerFrameCombinedBags
        if f and f:IsShown() and not f:IsVisible() then f:Hide() end
        for i = 1, 13 do
            f = _G["ContainerFrame" .. i]
            if f and f:IsShown() and not f:IsVisible() then f:Hide() end
        end
    end

    -- WoW Forever's Gamepad interface style navigates Blizzard's own bags and
    -- bank with the D-pad, so the takeover stands down for the session there.
    -- Decided once, at login; a later style switch asks for a reload, once.
    local standDown, styleAsked
    function ns.PadUIStandDown()
        if standDown == nil then standDown = EUI.PadGamepadUI() end
        return standDown
    end
    -- Item Icons (EllesmereUIQoL) follows it for Blizzard's bags and bank
    EUI._BagsStandDown = ns.PadUIStandDown

    function ns.PadStyleChanged()
        if styleAsked then return end
        styleAsked = true
        -- The Gamepad style's D-pad cannot reach the popup, so chat says it too.
        -- A confirm, not RequestReload: this can run outside a click, which
        -- cannot reload; the popup's click can.
        EllesmereUI.PrintError(EllesmereUI.L("The interface style changed. Type /reload so the bags match it."))
        EUI:ShowConfirmPopup({
            title       = EllesmereUI.L("Reload Required"),
            message     = EllesmereUI.L("The interface style changed. Reload so the bags match it."),
            confirmText = EllesmereUI.L("Reload Now"),
            cancelText  = EllesmereUI.L("Later"),
            reload      = true,
        })
    end
end

-- Gold border for quest items (overrides the normal quality border).
local QUEST_BORDER_COLOR = { r = 1.0, g = 0.82, b = 0.0 }

-------------------------------------------------------------------------------
--  Stack splitter: replaces Blizzard's StackSplitFrame on our bag/bank slots
--  and on the guild bank's (opt-in) with a house dialog that adds Auto Split --
--  repeated splits into empty slots until the remainder is at most the chosen size.
-------------------------------------------------------------------------------
do
    local dialog
    local job          -- { bag, slot, itemID, size, targets, window, ops, pending, issuedAt }
    local StepJob

    -- Container and guild bank slots share the dialog and job; only the API differs.
    local containerOps = {
        ownerBag = function(owner) return owner:GetParent():GetID() end,
        info     = C_Container.GetContainerItemInfo,
        numSlots = C_Container.GetContainerNumSlots,
        split    = C_Container.SplitContainerItem,
        pickup   = C_Container.PickupContainerItem,
    }
    local guildOps = {
        ownerBag = function() return GetCurrentGuildBankTab() end,
        -- A tab that is no longer viewed reads as empty so a running job stops there.
        info = function(tab, slot)
            if tab ~= GetCurrentGuildBankTab() then return nil end
            local texture, count, locked = GetGuildBankItemInfo(tab, slot)
            if not texture then return nil end
            local link = GetGuildBankItemLink(tab, slot)
            return { stackCount = count, isLocked = locked, itemID = link and GetItemInfoInstant(link) or 0 }
        end,
        numSlots = function() return 98 end,
        split    = SplitGuildBankItem,
        pickup   = PickupGuildBankItem,
    }

    local function StopJob()
        job = nil
    end

    -- Polled on a short timer. The new stack's slot can still read empty for a
    -- moment after the source count has updated, so slots already used as a
    -- destination are skipped for the rest of the job.
    local function Later()
        local this = job
        C_Timer.After(0.05, function() if job == this then StepJob() end end)
    end

    -- One split per server round trip: issue, wait for the source stack to
    -- settle at the expected count, repeat.
    StepJob = function()
        if not job then return end
        if not job.window:IsVisible() then StopJob(); return end
        local ops = job.ops
        local info = ops.info(job.bag, job.slot)
        if not info or info.itemID ~= job.itemID then StopJob(); return end
        if info.isLocked or (job.pending and info.stackCount ~= job.pending) then
            if GetTime() - job.issuedAt > 2 then ClearCursor(); StopJob() else Later() end
            return
        end
        job.pending = nil
        if info.stackCount <= job.size then StopJob(); return end
        for _, bagID in ipairs(job.targets) do
            for s = 1, ops.numSlots(bagID) do
                local key = bagID * 1000 + s
                if not job.used[key] and not ops.info(bagID, s) then
                    job.used[key] = true
                    ClearCursor()
                    ops.split(job.bag, job.slot, job.size)
                    ops.pickup(bagID, s)
                    -- Single placed split: one issue, no settle polling.
                    if job.once then StopJob(); return end
                    job.pending = info.stackCount - job.size
                    job.issuedAt = GetTime()
                    Later()
                    return
                end
            end
        end
        StopJob()
    end

    -- once = a single split placed into the first empty target slot (the views
    -- that draw no empty slots have nowhere to drop a cursor stack).
    local function StartJob(bag, slot, itemID, size, targets, window, ops, once)
        job = { bag = bag, slot = slot, itemID = itemID, size = size, targets = targets, window = window,
                ops = ops, used = {}, issuedAt = GetTime(), once = once }
        StepJob()
    end

    -- Closing the window a dialog or job belongs to ends it; other windows are unaffected.
    local function WindowHidden(win)
        if dialog and dialog._window == win then dialog:Hide() end
        if job and job.window == win then StopJob() end
        -- Closing the bags ends every session unmerge; the next open merges again.
        if win == EUI_Bags and EUI_Bags._unmergedLinks then wipe(EUI_Bags._unmergedLinks) end
    end

    -- Re-checks the slot the dialog was opened on after every repaint: pooled
    -- buttons get repurposed, and the count can change under us.
    local function Validate()
        if not dialog or not dialog:IsShown() then return end
        local owner = dialog._owner
        if not owner:IsVisible() or dialog._ops.ownerBag(owner) ~= dialog._bag or owner:GetID() ~= dialog._slot then
            dialog:Hide(); return
        end
        local info = dialog._ops.info(dialog._bag, dialog._slot)
        if not info or info.itemID ~= dialog._itemID or not info.stackCount or info.stackCount < 2 then
            dialog:Hide(); return
        end
        if info.stackCount ~= dialog._max then
            dialog:SetRange(1, info.stackCount)
            dialog:SetValue(dialog:Current())
        end
    end

    local function MakeButton(parent, w, h, label, PP)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, h)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        if PP and PP.CreateBorder then PP.CreateBorder(b, 0.25, 0.25, 0.25, 1) end
        local fs = b:CreateFontString(nil, "OVERLAY")
        SetBagFont(fs, 12)
        fs:SetPoint("CENTER", 0, 0)
        fs:SetTextColor(1, 1, 1, 0.9)
        fs:SetText(label)
        b:SetScript("OnEnter", function() bg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0.15, 0.15, 0.15, 1) end)
        return b
    end

    local function DoSplit(auto)
        local d = dialog
        local bag, slot, n, ops = d._bag, d._slot, d:Current(), d._ops
        d:Hide()
        local info = ops.info(bag, slot)
        if not info or info.isLocked or info.itemID ~= d._itemID or not info.stackCount or n >= info.stackCount then return end
        -- Session unmerge mark, written BEFORE the split so the refresh it
        -- triggers already renders the pieces apart. Same link form the slot
        -- tables key on; bags and reagent window only (bank items never merge here).
        if d._window == EUI_Bags or d._window == EUI_BagsReagent then
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local set = EUI_Bags._unmergedLinks
                if not set then set = {}; EUI_Bags._unmergedLinks = set end
                set[link] = true
            end
        end
        if auto or d._placeOnce then
            StartJob(bag, slot, info.itemID, n, d._targets, d._window, ops, not auto)
        else
            ClearCursor()
            ops.split(bag, slot, n)
        end
    end

    -- The splitter's own dark look on the shared quantity window
    -- (EllesmereUI.CreateQuantityDialog).
    local SKIN = {
        frame = function(d)
            local PP = EUI.PP
            local bg = d:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
            if PP and PP.CreateBorder then PP.CreateBorder(d, 0.2, 0.2, 0.2, 1) end
        end,
        font = SetBagFont,
        button = function(parent, w, h, label) return MakeButton(parent, w, h, label, EUI.PP) end,
        editBox = function(eb)
            local PP = EUI.PP
            eb:SetFont(GetFont(), 12, "")
            local ebBg = eb:CreateTexture(nil, "BACKGROUND")
            ebBg:SetAllPoints()
            ebBg:SetColorTexture(0.1, 0.1, 0.1, 1)
            if PP and PP.CreateBorder then PP.CreateBorder(eb, 0.15, 0.15, 0.15, 1) end
        end,
        close = function(close)
            close:SetSize(12, 12)
            close:SetPoint("TOPRIGHT", close:GetParent(), "TOPRIGHT", -9, -9)
            close.icon = close:CreateTexture(nil, "OVERLAY")
            close.icon:SetAllPoints()
            close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
            close.icon:SetAlpha(0.7)
            close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
            close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
        end,
    }

    local function CreateDialog()
        local d = EUI.CreateQuantityDialog({
            name = "EUI_BagsStackSplitFrame", width = 206, height = 94,
            title = EllesmereUI.L("Split Stack"), editWidth = 56, maxLetters = 5,
            skin = SKIN,
            onEnter = function() DoSplit(IsAltKeyDown()) end,
            buttons = {
                { key = "split", label = EllesmereUI.L("Split"), width = 88, height = 24,
                  point = "BOTTOMLEFT", onClick = function() DoSplit(false) end, primary = true },
                { key = "auto", label = EllesmereUI.L("Auto Split"), width = 88, height = 24,
                  point = "BOTTOMRIGHT", onClick = function() DoSplit(true) end,
                  tooltip = EllesmereUI.L("Split this stack into empty slots repeatedly until only the chosen amount or less remains. Alt+Enter does the same.") },
            },
        })

        hooksecurefunc(EUI_Bags, "RefreshInventory", Validate)
        EUI_Bags:HookScript("OnHide", function() WindowHidden(EUI_Bags) end)
        hooksecurefunc(EUI_BagsReagent, "RefreshInventory", Validate)
        EUI_BagsReagent:HookScript("OnHide", function() WindowHidden(EUI_BagsReagent) end)
        local bankFrame = _G.EUI_BankFrame
        if bankFrame then
            hooksecurefunc(bankFrame, "RefreshBank", Validate)
            bankFrame:HookScript("OnHide", function() WindowHidden(bankFrame) end)
        end
        return d
    end

    -- Runs from the slot PostClick hooks, after Blizzard's OnModifiedClick has
    -- opened StackSplitFrame on this button (its lock/count/cursor checks passed).
    -- targets: bagIDs Auto Split may fill, in order; window: closing it aborts a job.
    function EUI_Bags.ShowStackSplitter(owner, targets, window, ops)
        -- Always on in the bags window's All Items (0) and category (> 0) views:
        -- they draw no empty slots, so Blizzard's cursor split has nowhere to
        -- land and a plain Split places its stack instead. Everywhere else the
        -- Stack Splitter setting decides whether the dialog replaces the popup.
        local placeOnce = (window == EUI_Bags and selectedCategoryIndex >= 0)
        if not placeOnce and BP().bagStackSplitter ~= true then return end
        local maxStack = EUI.StackSplitFor(owner)
        if not maxStack then return end
        -- Its OnHide leaves .owner on the owner button and writes a flag onto
        -- it, which nothing reads on a click path.
        EUI.TakeStackSplit()
        ops = ops or containerOps
        local bag, slot = ops.ownerBag(owner), owner:GetID()
        local info = ops.info(bag, slot)
        if not info or not info.itemID then return end
        dialog = dialog or CreateDialog()
        StopJob()
        dialog._owner, dialog._bag, dialog._slot, dialog._itemID = owner, bag, slot, info.itemID
        dialog._targets, dialog._window, dialog._ops = targets, window, ops
        dialog._placeOnce = placeOnce
        dialog:SetRange(1, maxStack)
        dialog:SetValue(1)
        dialog:Open(owner)
        dialog:FocusInput()
    end

    -- Blizzard's guild bank buttons open StackSplitFrame the same way ours do,
    -- so the same PostClick takeover applies. Auto Split stays on the viewed tab.
    local function HookGuildBank()
        local gb = GuildBankFrame
        if not gb or not gb.Columns then return end
        for _, column in ipairs(gb.Columns) do
            for _, b in ipairs(column.Buttons) do
                b:HookScript("PostClick", function(self)
                    EUI_Bags.ShowStackSplitter(self, { GetCurrentGuildBankTab() }, gb, guildOps)
                end)
            end
        end
        hooksecurefunc(gb, "Update", Validate)
        gb:HookScript("OnHide", function() WindowHidden(gb) end)
    end
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_GuildBankUI", HookGuildBank)
    end
end

I.CreateInsetBorder, I.QUEST_BORDER_COLOR = CreateInsetBorder, QUEST_BORDER_COLOR
I.SCROLLBAR_HIT_W, I.SetInsetBorderColor = SCROLLBAR_HIT_W, SetInsetBorderColor
I.SetInsetBorderThickness = SetInsetBorderThickness
I.broken = false
