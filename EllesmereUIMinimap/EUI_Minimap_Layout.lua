if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Layout.lua
--
--  BuildCustomIndicators, the mouseover controller, LayoutIndicatorFrames,
--  the Blizzard minimap snapshot, the Omnium Folio and the map hover
--  reveal.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local _addonVisible, cachedAddonButtons, EBS = I._addonVisible, I.cachedAddonButtons, I.EBS
local GetFFD, PP, flyoutSavedParents = I.GetFFD, I.PP, I.flyoutSavedParents
local GetBtnRowMode, GetCustomTooltipScale = I.GetBtnRowMode, I.GetCustomTooltipScale
local GetElementRowMode, GetInteractableBtnSize = I.GetElementRowMode, I.GetInteractableBtnSize
local GetRowBase, IsJunkTexture, IsUngrouped = I.GetRowBase, I.IsJunkTexture, I.IsUngrouped
local RestoreButtonDecorations = I.RestoreButtonDecorations
local StripButtonDecorations, GetCoordsModePos = I.StripButtonDecorations, I.GetCoordsModePos
local UpdateCoords, ApplyBtnOffset = I.UpdateCoords, I.ApplyBtnOffset
local EnableFreeMove, FOLIO_REPLACEMENT_BUTTONS = I.EnableFreeMove, I.FOLIO_REPLACEMENT_BUTTONS
local _customIndicators, CreateGreatVaultBtn = I._customIndicators, I.CreateGreatVaultBtn
local CreateIndicatorBtn, CreatePortalBtn = I.CreateIndicatorBtn, I.CreatePortalBtn
local INDICATOR_ATLAS_OFFSET = I.INDICATOR_ATLAS_OFFSET
local INDICATOR_ATLAS_RATIO = I.INDICATOR_ATLAS_RATIO
local INDICATOR_ATLAS_SCALE, SizeGreatVaultBtn = I.INDICATOR_ATLAS_SCALE, I.SizeGreatVaultBtn
local SizePortalBtn, FRIENDS_ATLAS = I.SizePortalBtn, I.FRIENDS_ATLAS
local GetCalendarLockoutEntries = I.GetCalendarLockoutEntries
local HideCalendarTooltip, HideFriendsTooltip = I.HideCalendarTooltip, I.HideFriendsTooltip
local ShowCalendarTooltip, ShowFriendsTooltip = I.ShowCalendarTooltip, I.ShowFriendsTooltip
local SetMOEvaluate = I.SetMOEvaluate

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local flyoutToggle
I.flyoutToggleSetters[#I.flyoutToggleSetters + 1] = function(v) flyoutToggle = v end
local flyoutPanel
I.flyoutPanelSetters[#I.flyoutPanelSetters + 1] = function(v) flyoutPanel = v end
local _portalFlyout
I.portalFlyoutSetters[#I.portalFlyoutSetters + 1] = function(v) _portalFlyout = v end
local coordFrame
I.coordFrameSetters[#I.coordFrameSetters + 1] = function(v) coordFrame = v end
local coordTicker
I.coordTickerSetters[#I.coordTickerSetters + 1] = function(v) coordTicker = v end
local clockBg
I.clockBgSetters[#I.clockBgSetters + 1] = function(v) clockBg = v end

-- Assigned below; SetMOEvaluate hands it to the earlier files. It runs once,
-- at load: a file behind this one would have to import the function.
local MO_Evaluate

-- The Great Vault and M+ Portal buttons, built in BuildCustomIndicators.
local _greatVaultBtn = nil
local _portalBtn = nil

local function BuildCustomIndicators(minimap)
    if _customIndicators.tracking then
        -- Re-apply accent to the friends icon: a later ApplyAll (e.g. PLAYER_ENTERING_WORLD, after
        -- theme resolution mutates ELLESMERE_GREEN) must override the create-once read below, since creation can race theme resolution (same pattern as CreateFlyoutToggle).
        local fi = _customIndicators.friends and _customIndicators.friends._icon
        if fi then
            local EG2 = EllesmereUI.ELLESMERE_GREEN
            fi:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)
        end
        return
    end

    -- Tracking
    _customIndicators.tracking = CreateIndicatorBtn("_tracking", minimap,
        "UI-HUD-Minimap-Tracking-Up", "UI-HUD-Minimap-Tracking-Mouseover", "UI-HUD-Minimap-Tracking-Down",
        function(self)
            local blizBtn = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
            if not blizBtn or not blizBtn.OpenMenu then return end

            if blizBtn.menu and blizBtn.menu:IsShown() then
                blizBtn.menu:Hide()
                return
            end

            -- Position hidden Blizzard button at our custom button
            blizBtn:ClearAllPoints()
            blizBtn:SetPoint("CENTER", self, "CENTER", 0, 0)
            blizBtn:SetAlpha(0)
            blizBtn:EnableMouse(false)
            blizBtn:OpenMenu()

            if blizBtn.menu then
                blizBtn.menu:ClearAllPoints()
                blizBtn.menu:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
            end
        end)
    local trackBaseEnter = _customIndicators.tracking:GetScript("OnEnter")
    local trackBaseLeave = _customIndicators.tracking:GetScript("OnLeave")
    _customIndicators.tracking:SetScript("OnEnter", function(self)
        if trackBaseEnter then trackBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Tracking", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.tracking:SetScript("OnLeave", function(self)
        if trackBaseLeave then trackBaseLeave(self) end
        EllesmereUI.HideWidgetTooltip()
    end)

    -- Calendar (day-of-month atlas)
    local calDay = tonumber(date("%d")) or 1
    local calPrefix = "UI-HUD-Calendar-" .. calDay
    _customIndicators.calendar = CreateIndicatorBtn("_gameTime", minimap,
        calPrefix .. "-Up", calPrefix .. "-Mouseover", calPrefix .. "-Down",
        function()
            if ToggleCalendar then ToggleCalendar() end
        end)
    _customIndicators.calendar._calDay = calDay
    local calBaseEnter = _customIndicators.calendar:GetScript("OnEnter")
    local calBaseLeave = _customIndicators.calendar:GetScript("OnLeave")
    _customIndicators.calendar:SetScript("OnEnter", function(self)
        if calBaseEnter then calBaseEnter(self) end
        if GetFFD(self).freeMoveJustDragged then return end
        local lockoutEntries
        if not (EllesmereUI.InProtectedInstance()) then
            lockoutEntries = GetCalendarLockoutEntries()
        end
        if lockoutEntries then
            ShowCalendarTooltip(self, lockoutEntries)
        elseif EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Calendar", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.calendar:SetScript("OnLeave", function(self)
        if calBaseLeave then calBaseLeave(self) end
        HideCalendarTooltip()
        EllesmereUI.HideWidgetTooltip()
    end)

    -- Mail (informational: tooltip + hover atlas only)
    _customIndicators.mail = CreateIndicatorBtn("_mail", minimap,
        "UI-HUD-Minimap-Mail-Up", "UI-HUD-Minimap-Mail-Mouseover", nil, nil)
    local mailBaseEnter = _customIndicators.mail:GetScript("OnEnter")
    local mailBaseLeave = _customIndicators.mail:GetScript("OnLeave")
    _customIndicators.mail:SetScript("OnEnter", function(self)
        if EBS._HVRevealMapHover then EBS._HVRevealMapHover() end
        if mailBaseEnter then mailBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, HAVE_MAIL or "New Mail", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.mail:SetScript("OnLeave", function(self)
        if mailBaseLeave then mailBaseLeave(self) end
        EllesmereUI.HideWidgetTooltip()
    end)

    -- Crafting Order (informational: tooltip + hover atlas only)
    _customIndicators.crafting = CreateIndicatorBtn("_crafting", minimap,
        "UI-HUD-Minimap-CraftingOrder-Up-2x", "UI-HUD-Minimap-CraftingOrder-Over-2x", "UI-HUD-Minimap-CraftingOrder-Down-2x", nil)
    local craftBaseEnter = _customIndicators.crafting:GetScript("OnEnter")
    local craftBaseLeave = _customIndicators.crafting:GetScript("OnLeave")
    _customIndicators.crafting:SetScript("OnEnter", function(self)
        if craftBaseEnter then craftBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            local label = "Crafting Orders"
            if C_CraftingOrders and C_CraftingOrders.GetPersonalOrdersInfo then
                local infos = C_CraftingOrders.GetPersonalOrdersInfo()
                if type(infos) == "table" then
                    local lines = {}
                    for _, info in ipairs(infos) do
                        local count = tonumber(info.numPersonalOrders) or 0
                        if count > 0 then
                            local name = tostring(info.professionName or info.profession or "Unknown")
                            lines[#lines + 1] = count .. " " .. name .. " Order" .. (count > 1 and "s" or "")
                        end
                    end
                    if #lines > 0 then
                        label = label .. "\n" .. table.concat(lines, "\n")
                    end
                end
            end
            EllesmereUI.ShowWidgetTooltip(self, label, { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.crafting:SetScript("OnLeave", function(self)
        if craftBaseLeave then craftBaseLeave(self) end
        EllesmereUI.HideWidgetTooltip()
    end)

    -- Not under WoW Forever's Gamepad interface style: its navigation takes over a
    -- panel opened from our insecure click and makes protected calls, so the open is
    -- blocked (and the blocked-action popup can freeze the client). Every reader
    -- guards on the nil button.
    if not EllesmereUI.PadGamepadUI() then
    -- Friends Online button
    _customIndicators.friends = CreateIndicatorBtn("_friends", minimap,
        FRIENDS_ATLAS, FRIENDS_ATLAS, nil,
        function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            -- Switched to that style mid-session: opening the panel from here is blocked.
            if EllesmereUI.PadGamepadUI() then return end
            ToggleFriendsFrame()
        end)
    -- Not in INDICATOR_ATLAS_RATIO, so the icon uses inset anchoring; desaturated idle.
    if _customIndicators.friends._icon then
        _customIndicators.friends._icon:SetDesaturated(true)
        EllesmereUI.RegAccent({ type = "vertex", obj = _customIndicators.friends._icon })
        -- Apply current accent immediately (initial accent pass already ran)
        local g = EllesmereUI.ELLESMERE_GREEN
        if g then
            _customIndicators.friends._icon:SetVertexColor(g.r, g.g, g.b, 1)
        end
        _customIndicators.friends._icon:SetAlpha(0.85)
    end
    local friendsBtnEnter = _customIndicators.friends:GetScript("OnEnter")
    local friendsBtnLeave = _customIndicators.friends:GetScript("OnLeave")
    _customIndicators.friends:SetScript("OnEnter", function(self)
        if friendsBtnEnter then friendsBtnEnter(self) end
        if self._icon then self._icon:SetAlpha(1) end
        if GetFFD(self).freeMoveJustDragged then return end
        ShowFriendsTooltip(self)
    end)
    _customIndicators.friends:SetScript("OnLeave", function(self)
        if friendsBtnLeave then friendsBtnLeave(self) end
        if self._icon then self._icon:SetAlpha(0.85) end
        HideFriendsTooltip()
    end)

    end -- not PadGamepadUI

    -- Great Vault + M+ Portal buttons: built once, anchored in LayoutIndicatorFrames.
    -- Neither exists on WoW Forever (no vault, no keystone portals): the buttons are
    -- never built there, every reader guards on nil, and the options drop their rows.
    if not EllesmereUI.IS_FOREVER then
        _greatVaultBtn = CreateGreatVaultBtn(minimap)
        _portalBtn = CreatePortalBtn(minimap)
    end
end

-- Hide the Blizzard originals so they never render or intercept clicks
local function HideBlizzardIndicators()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then
        tracking:SetAlpha(0); tracking:EnableMouse(false)
        -- The click and tooltip scripts live on the child button, and a
        -- parent's mouse state does not reach it: left enabled it is an
        -- invisible hotspot at the cluster's corner.
        if tracking.Button then tracking.Button:EnableMouse(false) end
    end
    local gameTime = _G.GameTimeFrame
    if gameTime then gameTime:SetAlpha(0); gameTime:EnableMouse(false) end
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        if indicator.MailFrame then indicator.MailFrame:SetAlpha(0); indicator.MailFrame:EnableMouse(false) end
        if indicator.CraftingOrderFrame then indicator.CraftingOrderFrame:SetAlpha(0); indicator.CraftingOrderFrame:EnableMouse(false) end
    end
end

local function SyncIndicatorVisibility()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if _customIndicators.mail then
        local hasMail = false
        if HasNewMail then
            local raw = HasNewMail()
            if not issecretvalue(raw) then
                hasMail = raw or false
            end
        end
        local mp = EBS.db and EBS.db.profile.minimap
        if mp and mp.hideMail then
            hasMail = false
        end
        _customIndicators.mail:SetShown(hasMail)
    end
    if _customIndicators.crafting then
        local blizCraft = indicator and indicator.CraftingOrderFrame
        local hasCraft = blizCraft and blizCraft:IsShown()
        _customIndicators.crafting:SetShown(hasCraft or false)
    end
end

-------------------------------------------------------------------------------
--  Mouseover Extra Buttons: Great Vault/Portals/Friends/Group Button show only while
--  the mouse is over the minimap or one of them (either flyout open keeps them shown
--  until it closes). Event-driven off OnEnter/OnLeave, with a small deferred hide so
--  crossing tiny inter-frame gaps doesn't flicker.
-------------------------------------------------------------------------------
local _moActive  = false   -- mouseover mode currently engaged
local _moButtons = {}      -- extra buttons under control this layout
local _moHooked  = {}      -- frames whose OnEnter/OnLeave we've already hooked
local _moHideTimer = nil

local function MO_OverAny()
    if Minimap then
        local mapRegion = GetFFD(Minimap).pingBlocker or GetFFD(Minimap).layoutFrame or Minimap
        if mapRegion:IsMouseOver() then return true end
    end
    if _portalFlyout and _portalFlyout:IsShown() then return true end
    if flyoutPanel and flyoutPanel:IsShown() then return true end
    -- The friends tooltip is interactive (whisper/invite rows), so it keeps the stack
    -- shown like a flyout; it self-hides on a real exit and its OnHide re-evaluates.
    local ftt = EBS._friendsTT
    if ftt and ftt:IsShown() then return true end
    for i = 1, #_moButtons do
        local b = _moButtons[i]
        if b:IsShown() and b:IsMouseOver() then return true end
    end
    return false
end

local function MO_Apply(show)
    local a = show and 1 or 0
    for i = 1, #_moButtons do _moButtons[i]:SetAlpha(a) end
end

local function MO_CancelHide()
    if _moHideTimer then _moHideTimer:Cancel(); _moHideTimer = nil end
end

-- Assign the forward-declared upvalue so the earlier flyout hooks can re-evaluate.
MO_Evaluate = function()
    if not _moActive then return end
    MO_CancelHide()
    if MO_OverAny() then
        MO_Apply(true)
    else
        -- Brief delay bridges adjacent-frame gaps (minimap -> button, button -> button)
        -- so crossing one doesn't flash the stack off and on.
        _moHideTimer = C_Timer.NewTimer(0.12, function()
            _moHideTimer = nil
            if _moActive and not MO_OverAny() then MO_Apply(false) end
        end)
    end
end
SetMOEvaluate(MO_Evaluate)

local function MO_HookFrame(frame)
    if not frame or _moHooked[frame] then return end
    _moHooked[frame] = true
    frame:HookScript("OnEnter", function()
        if _moActive then MO_CancelHide(); MO_Apply(true) end
    end)
    frame:HookScript("OnLeave", function()
        if _moActive then MO_Evaluate() end
    end)
end

-- Rebuild the managed-button list from profile + hide state, hook minimap/buttons
-- (once), set initial alpha. Called at the end of every layout so it stays current.
local function MO_Refresh(p)
    wipe(_moButtons)
    local heb = (p and p.hideExtraBtns) or {}
    if p and p.mouseoverExtraBtns then
        if _greatVaultBtn and not heb.greatVault then _moButtons[#_moButtons + 1] = _greatVaultBtn end
        if _customIndicators.friends and not heb.friendsOnline then _moButtons[#_moButtons + 1] = _customIndicators.friends end
        if _portalBtn and not heb.portals then _moButtons[#_moButtons + 1] = _portalBtn end
        if flyoutToggle and not heb.groupButton then _moButtons[#_moButtons + 1] = flyoutToggle end
        -- Ungrouped addon buttons count as extra buttons for this setting too.
        for _, btn in ipairs(cachedAddonButtons) do
            if _addonVisible[btn] ~= false and IsUngrouped(btn) then
                _moButtons[#_moButtons + 1] = btn
            end
        end
    end
    _moActive = (#_moButtons > 0)
    if _moActive then
        MO_HookFrame(Minimap)
        for i = 1, #_moButtons do MO_HookFrame(_moButtons[i]) end
        MO_Evaluate()
    else
        MO_CancelHide()
        -- Restore full alpha (harmless on buttons hidden by hideExtraBtns).
        if _greatVaultBtn then _greatVaultBtn:SetAlpha(1) end
        if _customIndicators.friends then _customIndicators.friends:SetAlpha(1) end
        if _portalBtn then _portalBtn:SetAlpha(1) end
        if flyoutToggle then flyoutToggle:SetAlpha(1) end
        -- Restore ungrouped addon buttons we may have dimmed.
        for _, btn in ipairs(cachedAddonButtons) do
            if IsUngrouped(btn) then btn:SetAlpha(1) end
        end
    end
end

local MAIL_CORNER_POINTS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- Stock styles and Forever Square: dress one of OUR row buttons (and, under
-- Classic WoW UI, the indicators) as the stock round minimap
-- button: a 31px button with the 53px ring-border texture hung from its
-- top-left exactly as addon buttons hang it (its shadow falls bottom-right).
-- Measured on that texture at the 53px draw size, the gold band's inner
-- opening spans x 7..26 and y 7..25 -- centre 16.6,-16.2 from the button's
-- top-left, with the band's inner shadow on the top-left -- so the dark disc
-- and the icon are centred THERE, not at the addon-button icon slot (7,-6 at
-- 17px), which is drawn for icons with transparent margins; ours are
-- full-bleed art. The icon is clipped round by a mask so a square icon reads
-- as a round button. `crop` trims an atlas icon to its centre fraction (the
-- group toggle's plate art carries a small glyph) through the sheet file and
-- coords, since SetTexCoord on an atlas samples garbage. Extra args are the
-- button's own icon textures; the EUI black box hides. Created once,
-- re-applied per pass. Our own buttons only (keys are written on the button).
function EBS._ClassicRingButton(btn, crop, ...)
    if not btn then return end
    btn:SetSize(31, 31)
    if btn._bg then btn._bg:Hide() end
    local ring = btn._classicRing
    if not ring then
        ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(53, 53)
        ring:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn._classicRing = ring
        local disc = btn:CreateTexture(nil, "BACKGROUND")
        disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        disc:SetSize(20, 20)
        disc:SetPoint("CENTER", btn, "TOPLEFT", 16.6, -16.2)
        btn._classicDisc = disc
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints(btn)
        btn._classicHL = hl
        -- Icon 16px inside the 20px disc: a sliver of disc shows round the
        -- icon, as on the stock round buttons, rather than the art running
        -- under the band (which reads as zoomed in).
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(16, 16)
        mask:SetPoint("CENTER", btn, "TOPLEFT", 16.6, -16.2)
        btn._classicMask = mask
    end
    ring:Show()
    btn._classicDisc:Show()
    btn._classicHL:Show()
    for i = 1, select("#", ...) do
        local tex = select(i, ...)
        if tex then
            tex:ClearAllPoints()
            tex:SetSize(16, 16)
            tex:SetPoint("CENTER", btn, "TOPLEFT", 16.6, -16.2)
            if crop then
                -- GetAtlas is nil once the sheet file is on the texture, so
                -- this runs once per texture.
                local atlas = tex:GetAtlas()
                local info = atlas and C_Texture.GetAtlasInfo(atlas)
                if info and (info.file or info.filename) then
                    local r, g, b, a = tex:GetVertexColor()
                    tex:SetTexture(info.file or info.filename)
                    local l, rt, t, bt = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
                    local dw, dh = (rt - l) * crop, (bt - t) * crop
                    tex:SetTexCoord(l + dw, rt - dw, t + dh, bt - dh)
                    tex:SetVertexColor(r, g, b, a)
                end
            end
            if not tex._classicMasked then
                tex:AddMaskTexture(btn._classicMask)
                tex._classicMasked = true
            end
        end
    end
end

-- A ring button's ring inside its box: the left, top, right and bottom
-- insets (the button's units) from the box's edges to the ring's opaque
-- edge. The ring is the minimap tracking-border file (64px, its opaque ring
-- in columns 4..36 and rows 3..36) hung from the button's top-left at any
-- size, as the common minimap-button library (50 or 53px), our own button
-- and EBS._ClassicRingButton (53px) hang it. Found once per button (our
-- dress's ring, else the button's region drawing that file; a weak-keyed
-- record of ours, never a key on the button); a button without one, or with
-- its ring hung elsewhere, reads as its box.
EBS._ringTex = setmetatable({}, { __mode = "k" })
function EBS._RingInsets(btn)
    local ring = btn._classicRing
    if not ring then
        ring = EBS._ringTex[btn]
        if ring == nil then
            ring = false
            for i = 1, select("#", btn:GetRegions()) do
                local r = select(i, btn:GetRegions())
                if r:IsObjectType("Texture") then
                    local tex = r:GetTexture()
                    if (r.GetTextureFileID and r:GetTextureFileID()) == 136430
                       or (type(tex) == "string" and tex:find("MiniMap%-TrackingBorder")) then
                        ring = r
                        break
                    end
                end
            end
            EBS._ringTex[btn] = ring
        end
    end
    if not ring or not ring:IsShown() then return 0, 0, 0, 0 end
    local pt, rel, rp, x, y = ring:GetPoint(1)
    if pt ~= "TOPLEFT" or rp ~= "TOPLEFT" or rel ~= btn then return 0, 0, 0, 0 end
    local w, h = ring:GetWidth(), ring:GetHeight()
    x, y = x or 0, -(y or 0)
    return x + w * 4 / 64, y + h * 3 / 64,
        btn:GetWidth() - x - w * 37 / 64, btn:GetHeight() - y - h * 37 / 64
end

-- Takes the ring dress off a button the pass renders bare (a mail pinned to a
-- corner): ring, disc and highlight hide and the round mask comes off the
-- textures given, so the pass's own geometry shows unclipped. Re-dressing
-- puts everything back; a button never dressed is left alone.
function EBS._ClassicRingUndress(btn, ...)
    local ring = btn and btn._classicRing
    if not ring then return end
    ring:Hide()
    btn._classicDisc:Hide()
    btn._classicHL:Hide()
    for i = 1, select("#", ...) do
        local tex = select(i, ...)
        if tex and tex._classicMasked then
            tex:RemoveMaskTexture(btn._classicMask)
            tex._classicMasked = nil
        end
    end
end

-- Forever Square's element row: an indicator (tracking, calendar, mail,
-- crafting order) in the button row's ring dress, its icon at its atlas
-- aspect and scale on the ring's 16px icon height, nudged as the indicator
-- pass nudges it (INDICATOR_ATLAS_*), so the art sits as it does in the box.
-- Re-applied per pass: the indicator pass sizes the icon for the box first.
function EBS._RingIndicator(btn)
    local icon, up = btn._icon, btn._upAtlas
    EBS._ClassicRingButton(btn, nil, icon)
    local ratio = icon and up and INDICATOR_ATLAS_RATIO[up]
    if ratio then
        local s = INDICATOR_ATLAS_SCALE[up] or 1
        local off = INDICATOR_ATLAS_OFFSET[btn._indicatorKey]
        icon:SetSize(16 * ratio * s, 16 * s)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", btn, "TOPLEFT", 16.6 + (off and off[1] or 0), -16.2 + (off and off[2] or 0))
    end
end

-- WoW Forever's minimap header: its bar art (EBS._ApplyBlizzMinimapChrome)
-- and its own button arts, each plate and glyph in one atlas.
EBS.FV_HEADER_ATLAS = "ui-hud-minimap-header-button"
EBS.FV_HEADER_BUTTONS = {
    tracking = { "ui-hud-minimap-tracking-button", 23, 23 },
    calendar = { "ui-hud-minimap-calendar-button", 23, 23 },
    mail     = { "ui-hud-minimap-mail-icon", 32, 24 },
}
-- An indicator (tracking, calendar, mail) in its WoW Forever header art at
-- the header's scale `s` (map size / 198): the art fills the button in place
-- of the icon's own (every hover state reads the same atlas, so the swaps go
-- quiet) and an additive copy lights it on mouseover at Blizzard's 0.1, as
-- the stock header buttons light. Re-applied per pass: the indicator pass
-- sizes the button for the EUI row and the day rollover repaints the
-- calendar's icon before it. Our own buttons only.
function EBS._FvHeaderIndicator(btn, key, s)
    local art = btn and EBS.FV_HEADER_BUTTONS[key]
    if not art then return end
    local atlas = art[1]
    btn:SetSize(art[2] * s, art[3] * s)
    if btn._bg then btn._bg:Hide() end
    btn._upAtlas, btn._overAtlas, btn._downAtlas = atlas, atlas, atlas
    local icon = btn._icon
    icon:ClearAllPoints()
    icon:SetAllPoints(btn)
    icon:SetAtlas(atlas)
    local hl = btn._fvHeaderHL
    if not hl then
        hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints(btn)
        hl:SetAlpha(0.1)
        btn._fvHeaderHL = hl
    end
    hl:SetAtlas(atlas)
end

local function LayoutIndicatorFrames(minimap, p, circleMode)
    local flvl = minimap:GetFrameLevel() + 10
    local mapAnchor = GetFFD(minimap).layoutFrame or minimap
    -- The rows' anchor: the map, or Forever Square's outer frame edge.
    local rowAnchor = (EBS._fvSquare and GetFFD(minimap).fvOuter) or mapAnchor

    -- Build our custom buttons once, hide Blizzard originals
    BuildCustomIndicators(minimap)
    HideBlizzardIndicators()
    SyncIndicatorVisibility()

    local ci = _customIndicators
    local sz = GetInteractableBtnSize()
    local showBg = p.btnBackgrounds ~= false
    -- Mail Position: "button" = element row; a corner pins it there (as Omnium Folio).
    local mailCorner = MAIL_CORNER_POINTS[p.mailPosition] and p.mailPosition or nil
    -- Resize buttons and update icon aspect ratios
    local inset = 3
    local avail = sz - inset * 2
    local blizzHdr = EBS._MinimapBlizz() and GetFFD(minimap).blizzHeader or nil
    local function ResizeIndicator(btn)
        if not btn then return end
        btn:SetSize(sz, sz)
        -- Stock styles: no EUI black box behind the indicators.
        if btn._bg then btn._bg:SetShown(showBg and not blizzHdr) end
        local ratio = btn._upAtlas and INDICATOR_ATLAS_RATIO[btn._upAtlas]
        if ratio and btn._icon then
            local scale = INDICATOR_ATLAS_SCALE[btn._upAtlas] or 1
            local iconW, iconH
            if ratio >= 1 then iconW = avail * scale; iconH = (avail / ratio) * scale
            else iconH = avail * scale; iconW = (avail * ratio) * scale end
            btn._icon:ClearAllPoints()
            btn._icon:SetSize(iconW, iconH)
            local off = btn._indicatorKey and INDICATOR_ATLAS_OFFSET[btn._indicatorKey]
            btn._icon:SetPoint("CENTER", btn, "CENTER", off and off[1] or 0, off and off[2] or 0)
        end
    end
    ResizeIndicator(ci.tracking)
    -- Update calendar day if it changed (midnight rollover)
    if ci.calendar then
        local today = tonumber(date("%d")) or 1
        if ci.calendar._calDay ~= today then
            ci.calendar._calDay = today
            local prefix = "UI-HUD-Calendar-" .. today
            ci.calendar._upAtlas = prefix .. "-Up"
            ci.calendar._overAtlas = prefix .. "-Mouseover"
            ci.calendar._downAtlas = prefix .. "-Down"
            if ci.calendar._icon then ci.calendar._icon:SetAtlas(ci.calendar._upAtlas) end
        end
    end
    ResizeIndicator(ci.calendar)
    ResizeIndicator(ci.mail)
    ResizeIndicator(ci.crafting)
    -- Corner-pinned mail renders bare: no black box, just the mail icon
    if mailCorner and ci.mail and ci.mail._bg then
        ci.mail._bg:SetShown(false)
    end
    if flyoutToggle then
        flyoutToggle:SetSize(sz, sz)
        if flyoutToggle._bg then flyoutToggle._bg:SetShown(showBg) end
        -- Reset to base anchor so free-move offsets don't accumulate across relayouts
        local rowMode = GetBtnRowMode(p)
        local rowBaseX, rowBaseY = GetRowBase(rowMode, p.btnRowDistance)
        local resES = minimap:GetEffectiveScale()
        flyoutToggle:ClearAllPoints()
        flyoutToggle:SetPoint(rowMode.point, rowAnchor, rowMode.rel,
            PP.SnapForES(rowBaseX, resES), PP.SnapForES(rowBaseY, resES))
    end

    if ci.calendar then ci.calendar:SetShown(not p.hideGameTime) end

    -- Difficulty flag (instance type/size indicator)
    local diffFrame = (MinimapCluster and MinimapCluster.InstanceDifficulty) or _G.MiniMapInstanceDifficulty
    if diffFrame then
        diffFrame:SetParent(minimap)
        diffFrame:SetFrameLevel(flvl + 2)
        diffFrame:ClearAllPoints()
        diffFrame:SetPoint("TOPRIGHT", mapAnchor, "TOPRIGHT", 2, 1)
        -- Text mode overrides Show Blizzard Elements: the flag is always suppressed.
        -- Alpha leaves the hit region live, so a suppressed flag still answers mouseover
        -- with Blizzard's difficulty tooltip at the top-right corner.
        local suppressed = p.hideRaidDifficulty or p.diffTextEnabled
        diffFrame:SetAlpha(suppressed and 0 or 1)
        diffFrame:EnableMouseMotion(not suppressed)
        if diffFrame.Guild then diffFrame.Guild:EnableMouseMotion(not suppressed) end
    end
    if not minimap.Layout then minimap.Layout = function() end end

    if blizzHdr then
        -- Stock styles: placement around the top bar -- tracking on its left,
        -- calendar on its right, crafting stacked under the tracking button,
        -- the difficulty flag hung under the bar's right end. Blizzard Style
        -- stacks the mail under the tracking button too; Classic WoW UI puts
        -- it at the vanilla spot on the ring's upper right, below the flag,
        -- and dresses the row's indicators as the vanilla round buttons (a
        -- corner-pinned mail renders bare). WoW Forever's bar takes its own
        -- header buttons (EBS._FvHeaderIndicator) where its client puts them:
        -- tracking centred 8.5 past the bar's left end, the calendar
        -- overlapping its right end by 4, the mail icon under its left end
        -- (a corner mail keeps that art). Corner mail and every hide toggle
        -- still apply.
        local classic = EBS._MinimapClassic()
        local cs = (p.mapSize or 140) / 140
        local fvBar = blizzHdr._fvBar
        local hs = (p.mapSize or 140) / 198
        if ci.tracking and not p.hideTrackingButton then
            if classic then
                EBS._ClassicRingButton(ci.tracking, nil, ci.tracking._icon)
            elseif fvBar then
                EBS._FvHeaderIndicator(ci.tracking, "tracking", hs)
            elseif not ci.tracking._blizzRing then
                -- The stock tracking button sits on a round plate (our own button, so the
                -- texture lives on it directly).
                local ring = ci.tracking:CreateTexture(nil, "BACKGROUND")
                ring:SetAllPoints(ci.tracking)
                EBS._StockAtlas(ring, "ui-hud-minimap-button")
                ci.tracking._blizzRing = ring
            end
            ci.tracking:ClearAllPoints()
            if fvBar then
                ci.tracking:SetPoint("CENTER", blizzHdr, "LEFT", -8.5 * hs, 0)
            else
                ci.tracking:SetPoint("RIGHT", blizzHdr, "LEFT", -2, 0)
            end
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end
        if ci.calendar and not p.hideGameTime then
            -- Stock: the clock hangs from the bar's top-right corner.
            ci.calendar:ClearAllPoints()
            if fvBar then
                EBS._FvHeaderIndicator(ci.calendar, "calendar", hs)
                ci.calendar:SetPoint("TOPLEFT", blizzHdr, "TOPRIGHT", -4 * hs, 0)
            else
                ci.calendar:SetPoint("TOPLEFT", blizzHdr, "TOPRIGHT", 1, 0)
            end
        end
        local under = (ci.tracking and ci.tracking:IsShown() and not fvBar) and ci.tracking or nil
        if ci.mail and ci.mail:IsShown() then
            if fvBar then EBS._FvHeaderIndicator(ci.mail, "mail", hs) end
            if classic then
                if mailCorner then
                    EBS._ClassicRingUndress(ci.mail, ci.mail._icon)
                else
                    EBS._ClassicRingButton(ci.mail, nil, ci.mail._icon)
                    -- The dress squares its icon; the envelope keeps its atlas
                    -- aspect at the ring's 16px icon height.
                    local ratio = ci.mail._upAtlas and INDICATOR_ATLAS_RATIO[ci.mail._upAtlas]
                    if ratio and ci.mail._icon then ci.mail._icon:SetSize(16 * ratio, 16) end
                end
            end
            ci.mail:ClearAllPoints()
            if mailCorner then
                ci.mail:SetPoint(mailCorner, mapAnchor, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            elseif classic then
                -- The vanilla mail frame: 33px, its TOPRIGHT 24,-37 off the map's
                -- top-right corner, ring border hung from its top-left; placed by
                -- that top-left, 6 lower than the vanilla spot so the difficulty
                -- flag hanging under the banner's right end clears the ring.
                ci.mail:SetPoint("TOPLEFT", minimap, "TOPRIGHT", -9 * cs, -43 * cs)
            elseif fvBar then
                ci.mail:SetPoint("TOPLEFT", blizzHdr, "BOTTOMLEFT", 0, 0)
                under = ci.mail
            else
                if under then
                    ci.mail:SetPoint("TOP", under, "BOTTOM", 0, 0)
                else
                    ci.mail:SetPoint("RIGHT", blizzHdr, "LEFT", -2, 0)
                end
                under = ci.mail
            end
        end
        if ci.crafting and ci.crafting:IsShown() then
            if classic then EBS._ClassicRingButton(ci.crafting, nil, ci.crafting._icon) end
            ci.crafting:ClearAllPoints()
            if under then
                ci.crafting:SetPoint("TOP", under, "BOTTOM", 0, 0)
            else
                ci.crafting:SetPoint("RIGHT", blizzHdr, "LEFT", -2, 0)
            end
        end
        if diffFrame then
            diffFrame:ClearAllPoints()
            diffFrame:SetPoint("TOPRIGHT", blizzHdr, "BOTTOMRIGHT", 0, 1)
        end

    elseif circleMode then
        -- Circle layout: horizontal row growing left from the clock. Each element chains
        -- to the previous shown one; a hidden element is skipped, since anchoring to a
        -- frame that was never positioned leaves the whole chain undrawn.
        local leftAnchor = (clockBg and clockBg:IsShown()) and clockBg or nil
        local function PlaceLeft(btn)
            btn:ClearAllPoints()
            if leftAnchor then
                btn:SetPoint("RIGHT", leftAnchor, "LEFT", 0, 0)
            else
                btn:SetPoint("TOP", mapAnchor, "TOP", -20, -3)
            end
            leftAnchor = btn
        end

        if ci.tracking and not p.hideTrackingButton then
            PlaceLeft(ci.tracking)
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end

        if ci.calendar and not p.hideGameTime then
            ci.calendar:ClearAllPoints()
            if clockBg and clockBg:IsShown() then
                ci.calendar:SetPoint("LEFT", clockBg, "RIGHT", 0, 0)
            else
                ci.calendar:SetPoint("TOP", mapAnchor, "TOP", 20, -3)
            end
        end

        if ci.mail and ci.mail:IsShown() then
            if mailCorner then
                ci.mail:ClearAllPoints()
                ci.mail:SetPoint(mailCorner, mapAnchor, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            else
                PlaceLeft(ci.mail)
            end
        end

        if ci.crafting and ci.crafting:IsShown() then
            PlaceLeft(ci.crafting)
        end

    else
        -- Square layout: element row (corner + growth from Element Row Position), same running-total
        -- placement as the button row below using each element's real width so horizontal rows stay flush despite varying atlas ratios.
        local rowMode = GetElementRowMode(p)
        local baseX, baseY = GetRowBase(rowMode, p.elementRowDistance)
        local elES = minimap:GetEffectiveScale()
        local elPx = PP.perfect / elES
        local elGap = PP.SnapForES(p.elementRowSpacing or 0, elES)
        local elX = PP.SnapForES(baseX, elES)
        local elY = PP.SnapForES(baseY, elES)
        -- Forever Square: the row wears the button row's ring dress
        -- (EBS._RingIndicator), each ring rather than its box placed on the
        -- row (EBS._RingInsets), EBS.FV_RING_GAP apart.
        local fvRings = EBS._fvSquare
        local ringGap = fvRings and PP.SnapForES(EBS.FV_RING_GAP, elES) or 0
        local ptRight = rowMode.point:find("RIGHT") ~= nil
        local ptTop = rowMode.point:find("TOP") ~= nil
        local function PlaceElement(btn)
            if fvRings then EBS._RingIndicator(btn) end
            local adv = (rowMode.dirX ~= 0) and btn:GetWidth() or btn:GetHeight()
            local ox, oy = 0, 0
            if fvRings then
                local l, t, r, b = EBS._RingInsets(btn)
                adv = adv - ((rowMode.dirX ~= 0) and (l + r) or (t + b)) + ringGap
                ox = PP.SnapForES(ptRight and r or -l, elES)
                oy = PP.SnapForES(ptTop and t or -b, elES)
            end
            btn:ClearAllPoints()
            btn:SetPoint(rowMode.point, rowAnchor, rowMode.rel, elX + ox, elY + oy)
            adv = math.floor(adv / elPx + 0.001) * elPx + elGap
            elX = elX + adv * rowMode.dirX
            elY = elY + adv * rowMode.dirY
        end

        if ci.tracking and not p.hideTrackingButton then
            PlaceElement(ci.tracking)
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end

        if ci.calendar and not p.hideGameTime then
            PlaceElement(ci.calendar)
        end

        if ci.mail and ci.mail:IsShown() then
            if mailCorner then
                -- A corner mail renders bare, its ring dress off.
                if fvRings then EBS._ClassicRingUndress(ci.mail, ci.mail._icon) end
                ci.mail:ClearAllPoints()
                ci.mail:SetPoint(mailCorner, mapAnchor, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            else
                PlaceElement(ci.mail)
            end
        end

        if ci.crafting and ci.crafting:IsShown() then
            PlaceElement(ci.crafting)
        end
    end

    -- Ungrouped buttons along the button row; the flyout toggle is its first slot.
    if flyoutToggle then
        local rowMode = GetBtnRowMode(p)
        local rowBaseX, rowBaseY = GetRowBase(rowMode, p.btnRowDistance)
        local ungroupBtnSize = GetInteractableBtnSize()
        -- Running-total placement: cursor starts at snapped Distance from Map, advances per button
        -- by its size FLOORED to whole physical pixels (rounding up opens hairline seams; flooring can only overlap-flush) plus snapped Icon Spacing.
        local rowES = minimap:GetEffectiveScale()
        local rowPx = PP.perfect / rowES
        local rowGap = PP.SnapForES(p.btnRowSpacing or 0, rowES)
        local rowX = PP.SnapForES(rowBaseX, rowES)
        local rowY = PP.SnapForES(rowBaseY, rowES)
        -- Round maps: the row follows the ring instead of the square's edge,
        -- starting at the row's corner and walking round in its growth
        -- direction; Icon Spacing becomes the arc gap. Stock styles centre each
        -- button on the circle just outside the map, as the stock map's addon
        -- buttons do (the stock addon-button radius, 5px scaled with the map,
        -- plus Distance from Map). The EllesmereUI look's circle centres each
        -- button on the map's edge, half over the map so it reads as attached,
        -- Distance from Map further out, with a base gap between buttons. With
        -- Free Move on it keeps the straight row: saved offsets are relative to
        -- the row slots they were dragged from.
        local arcR, arcT, arcDir
        local arcGap = 0
        if blizzHdr or (circleMode and not p.freeMoveBtns) then
            local mapW = minimap:GetWidth() or 140
            if blizzHdr then
                arcR = mapW / 2 + 5 * (mapW / 198) + (p.btnRowDistance or 0)
            else
                local edge = (p.shape == "textured_circle") and 2 or (p.borderSize or 1)
                arcR = mapW / 2 + edge + (p.btnRowDistance or 0)
                arcGap = PP.SnapForES(4, rowES)
            end
            arcT = math.rad(rowMode.arc or 225)
            arcDir = rowMode.arcDir or -1
        end
        -- Stock styles and Forever Square: every button on the row wears the
        -- round minimap-button look -- ours dressed by EBS._ClassicRingButton,
        -- addon buttons in their own native dress (the common minimap-button
        -- library draws exactly that look). The EllesmereUI look keeps its own
        -- dress, its circle too.
        local ringDress = (blizzHdr or EBS._fvSquare) and true or false
        -- Forever Square's straight row places each ring, not its box: a ring
        -- sits off-centre in its button and at its own size (EBS._RingInsets),
        -- so each ring's edge lands on the row's edge and the next ring
        -- follows EBS.FV_RING_GAP past it.
        local fvRings = ringDress and EBS._fvSquare
        local ringGap = fvRings and PP.SnapForES(EBS.FV_RING_GAP, rowES) or 0
        local ptRight = rowMode.point:find("RIGHT") ~= nil
        local ptTop = rowMode.point:find("TOP") ~= nil
        local function PlaceRowButton(btn)
            local adv = (rowMode.dirX ~= 0) and btn:GetWidth() or btn:GetHeight()
            local ox, oy = 0, 0
            if fvRings then
                local l, t, r, b = EBS._RingInsets(btn)
                adv = adv - ((rowMode.dirX ~= 0) and (l + r) or (t + b)) + ringGap
                ox = PP.SnapForES(ptRight and r or -l, rowES)
                oy = PP.SnapForES(ptTop and t or -b, rowES)
            end
            adv = math.floor(adv / rowPx + 0.001) * rowPx + rowGap
            if arcR then
                EBS._ArcPoint(btn, minimap, arcR, arcT, rowES)
                arcT = arcT + arcDir * (adv + arcGap) / arcR
            else
                btn:SetPoint(rowMode.point, rowAnchor, rowMode.rel, rowX + ox, rowY + oy)
                rowX = rowX + adv * rowMode.dirX
                rowY = rowY + adv * rowMode.dirY
            end
        end
        if ringDress then EBS._ClassicRingButton(flyoutToggle, 0.12, flyoutToggle._norm, flyoutToggle._pushed, flyoutToggle._hl) end
        -- WoW Forever: a row starting at the bottom-left corner starts past
        -- the queue eye Action Bars parks there (half the 45px eye, the gap
        -- and half a ring button, as arc length).
        if arcR and EllesmereUI.IS_FOREVER and rowMode.arc == 225 then
            local ab = EllesmereUI._ModuleNS.EllesmereUIActionBars
            if ab and ab.AB_ForeverEyeParked() then
                arcT = arcT + arcDir * (22.5 + rowGap + arcGap + flyoutToggle:GetWidth() / 2) / arcR
            end
        end
        flyoutToggle:ClearAllPoints()
        local flyoutVisible = flyoutToggle:IsShown()
        if flyoutVisible then
            PlaceRowButton(flyoutToggle)
        elseif arcR then
            EBS._ArcPoint(flyoutToggle, minimap, arcR, arcT, rowES)
        else
            flyoutToggle:SetPoint(rowMode.point, rowAnchor, rowMode.rel, rowX, rowY)
        end
        local mp = EBS.db and EBS.db.profile.minimap
        local ungrouped = {}
        for _, btn in ipairs(cachedAddonButtons) do
            if _addonVisible[btn] ~= false and IsUngrouped(btn) then
                local name = btn:GetName()
                local order = mp and mp.ungroupedButtons and mp.ungroupedButtons[name] or 999
                if type(order) == "boolean" then order = 999 end
                ungrouped[#ungrouped + 1] = { btn = btn, order = order }
            end
        end
        table.sort(ungrouped, function(a, b) return a.order < b.order end)
        for idx, entry in ipairs(ungrouped) do
            local btn = entry.btn
            -- Restore from flyout if needed
            if flyoutSavedParents[btn] then
                if GetFFD(btn).flyoutRing then GetFFD(btn).flyoutRing:Hide() end
                if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
                if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
                flyoutSavedParents[btn] = nil
            end
            btn:SetParent(minimap)
            btn:SetFrameLevel(minimap:GetFrameLevel() + 11)
            btn:ClearAllPoints()
            -- Black boxes only on the EUI look; Blizzard Style keeps the button's
            -- own dress (the common library dress is the stock round minimap
            -- button) at its native size, restored BEFORE placement so the row
            -- advances by the size the button really draws at.
            local rowBoxes = showBg and not ringDress
            if rowBoxes then
                -- Strip BEFORE resize so the snapshot captures the real native size.
                StripButtonDecorations(btn)
                btn:SetSize(ungroupBtnSize, ungroupBtnSize)
            else
                RestoreButtonDecorations(btn)
            end
            PlaceRowButton(btn)
            btn:SetMovable(false)
            btn:RegisterForDrag()
            btn:SetScript("OnDragStart", nil)
            btn:SetScript("OnDragStop", nil)
            if rowBoxes then
                local icon = btn.icon or btn.Icon
                if not icon then
                    for _, region in ipairs({ btn:GetRegions() }) do
                        if region:IsObjectType("Texture") and region:IsShown()
                           and region:GetAlpha() > 0 and not IsJunkTexture(region)
                           and region ~= GetFFD(btn).ungroupBg then
                            icon = region
                            break
                        end
                    end
                end
                if icon then
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
                    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
                    pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95)
                    -- Foreign icon: no global SetTexCoord snap hook, so disable once.
                    if EllesmereUI.PP then EllesmereUI.PP.DisablePixelSnap(icon) end
                end
                EBS._ShowAddonBtnBox(btn)
                if btn._ungroupRing then btn._ungroupRing:Hide() end
            else
                -- No boxes: native appearance (restored above), our overlays hidden. Do NOT
                -- override button size -- native ring textures have fixed anchors correct only at the original size.
                if GetFFD(btn).ungroupBg then GetFFD(btn).ungroupBg:Hide() end
                if btn._ungroupRing then btn._ungroupRing:Hide() end
            end
            EBS._suppressVisTrack = true
            btn:SetAlpha(1)
            btn:Show()
            EBS._suppressVisTrack = false
        end

        local heb = p.hideExtraBtns or {}

        -- Extra buttons: Great Vault, Friends Online, M+ Portals. Visibility from
        -- hideExtraBtns; row order from extraBtnOrder (drag-to-reorder in options; nil = fallback list below).
        local function PlaceExtraButton(key)
            if key == "greatVault" then
                if _greatVaultBtn then
                    if heb.greatVault then
                        _greatVaultBtn:Hide()
                    else
                        SizeGreatVaultBtn(_greatVaultBtn, showBg)
                        if ringDress then EBS._ClassicRingButton(_greatVaultBtn, nil, _greatVaultBtn._whole) end
                        _greatVaultBtn:SetParent(minimap)
                        _greatVaultBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        _greatVaultBtn:ClearAllPoints()
                        PlaceRowButton(_greatVaultBtn)
                        _greatVaultBtn:Show()
                    end
                end
            elseif key == "friendsOnline" then
                if ci.friends then
                    if heb.friendsOnline then
                        ci.friends:Hide()
                    else
                        ci.friends:SetSize(sz, sz)
                        if ci.friends._bg then ci.friends._bg:SetShown(showBg) end
                        if ringDress then EBS._ClassicRingButton(ci.friends, nil, ci.friends._icon) end
                        ci.friends:SetParent(minimap)
                        ci.friends:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        ci.friends:ClearAllPoints()
                        PlaceRowButton(ci.friends)
                        ci.friends:Show()
                    end
                end
            elseif key == "portals" then
                if _portalBtn then
                    if heb.portals then
                        _portalBtn:Hide()
                    else
                        SizePortalBtn(_portalBtn, showBg)
                        if ringDress then EBS._ClassicRingButton(_portalBtn, nil, _portalBtn._icon) end
                        _portalBtn:SetParent(minimap)
                        _portalBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        _portalBtn:ClearAllPoints()
                        PlaceRowButton(_portalBtn)
                        _portalBtn:Show()
                    end
                end
            end
        end
        local placedExtra = {}
        if type(p.extraBtnOrder) == "table" then
            for _, key in ipairs(p.extraBtnOrder) do
                if not placedExtra[key] then placedExtra[key] = true; PlaceExtraButton(key) end
            end
        end
        -- Safety net: place anything a stale saved order is missing
        for _, key in ipairs({ "greatVault", "friendsOnline", "portals" }) do
            if not placedExtra[key] then placedExtra[key] = true; PlaceExtraButton(key) end
        end

        -- Flyout toggle (EUI group button for addon icons)
        if flyoutToggle and heb.groupButton then
            flyoutToggle:Hide()
        end
    end

    -- Free Move: hook shift+drag on all indicator buttons and apply saved offsets
    local heb = p.hideExtraBtns or {}
    local freeMove = p.freeMoveBtns
    local fmTargets = {}
    if ci.tracking and not p.hideTrackingButton then fmTargets[#fmTargets + 1] = ci.tracking end
    if ci.calendar and not p.hideGameTime then fmTargets[#fmTargets + 1] = ci.calendar end
    if ci.mail then fmTargets[#fmTargets + 1] = ci.mail end
    if ci.crafting then fmTargets[#fmTargets + 1] = ci.crafting end
    if flyoutToggle then fmTargets[#fmTargets + 1] = flyoutToggle end
    if _greatVaultBtn and not heb.greatVault then fmTargets[#fmTargets + 1] = _greatVaultBtn end
    if _portalBtn and not heb.portals then fmTargets[#fmTargets + 1] = _portalBtn end
    if ci.friends and not heb.friendsOnline then fmTargets[#fmTargets + 1] = ci.friends end
    -- Include ungrouped addon buttons
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and IsUngrouped(btn) then
            fmTargets[#fmTargets + 1] = btn
        end
    end
    for _, frame in ipairs(fmTargets) do
        EnableFreeMove(frame)
        if freeMove then
            ApplyBtnOffset(frame)
        end
    end

    -- After layout so the managed-button list and alpha reflect the shown state.
    MO_Refresh(p)
end

-------------------------------------------------------------------------------
-- Snapshot Blizzard minimap size and position on first install: native size and
-- center so we start matching the user's Edit Mode setup. Once per profile.
-------------------------------------------------------------------------------
local function CaptureBlizzardMinimap()
    local minimap = Minimap
    if not minimap then return end
    local p = EBS.db.profile.minimap
    if p._capturedOnce then return end

    local uiScale = UIParent:GetEffectiveScale()
    local mScale  = minimap:GetEffectiveScale()
    local ratio   = mScale / uiScale

    -- Capture size (use the larger dimension to keep it square)
    local w, h = minimap:GetWidth(), minimap:GetHeight()
    if w and w > 10 then
        local sz = math.floor(math.max(w, h) * ratio + 0.5)
        p.mapSize = sz
    end

    -- Capture center position as CENTER/CENTER offset from UIParent
    local cx, cy = minimap:GetCenter()
    if cx and cy then
        local uiW, uiH = UIParent:GetSize()
        cx = cx * ratio
        cy = cy * ratio
        p.position = {
            point = "CENTER", relPoint = "CENTER",
            x = cx - (uiW / 2), y = cy - (uiH / 2),
        }
    end

    -- WoW Forever: a new profile starts with our button, then the error-list
    -- addon's (its LibDBIcon name; an absent button costs nothing), on the
    -- button row out of the group. A first-capture seed, not a default: a
    -- player's regroup clears the entry for good.
    if EllesmereUI.IS_FOREVER == true then
        local ug = p.ungroupedButtons
        if type(ug) ~= "table" then ug = {}; p.ungroupedButtons = ug end
        if next(ug) == nil then
            ug.EllesmereUIMinimapButton = 1
            ug.LibDBIcon10_BugSack = 2
        end
    end

    p._capturedOnce = true
end

-- Expansion landing page button ("Omnium Folio"): kept off the addon-button flyout (see
-- flyoutBlacklist), anchored to a minimap corner and raised above it. We never force it
-- visible -- Blizzard decides when it appears, so we never display a stale old-expansion
-- button; our setting only HIDES it. Plain (non-secure) button, so SetParent/SetPoint are safe.
local _omniumFolioHooked = false

-- True while a replacement button (FOLIO_REPLACEMENT_BUTTONS) is on screen. Our
-- RefreshButton nudge below would undo the replacement's hide -- it re-Shows Blizzard's
-- button, which the replacement never re-hides (believing it already did), leaving both
-- visible. So while a replacement is in charge we keep hands off; it re-Shows Blizzard's itself if disabled, and our Show hook re-applies our state then.
local function IsFolioReplacedByAddOn()
    for _, name in ipairs(FOLIO_REPLACEMENT_BUTTONS) do
        -- IsShown presence check: if anything squats one of these global names with a non-frame value, treat it as no replacement instead of erroring.
        local b = _G[name]
        if b and b.IsShown and b:IsShown() then return true end
    end
    return false
end

-- Folio mode with legacy fallback: pre-dropdown data carries showOmniumFolio (default ON; only false is ever stored).
local function GetOmniumFolioMode(mp)
    -- No expansion landing page on WoW Forever: every folio path reads "never".
    if EllesmereUI.IS_FOREVER then return "never" end
    if not mp then return "always" end
    if mp.omniumFolioMode then return mp.omniumFolioMode end
    if mp.showOmniumFolio == false then return "never" end
    return "always"
end

-- Re-entrancy guard: PositionOmniumFolio calls the SetParent/SetScale/SetPoint we hook below, so our own writes must not recurse.
local _omniumFolioApplying = false
local function PositionOmniumFolio(btn)
    if not btn or not Minimap then return end
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not mp then return end
    _omniumFolioApplying = true
    if btn:GetParent() ~= Minimap then btn:SetParent(Minimap) end
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    btn:SetScale(mp.omniumFolioScale or 0.75)
    btn:ClearAllPoints()
    -- Anchor the button's chosen corner to the minimap's same corner; X/Y nudge from there (positive X = right, positive Y = up, regardless of corner).
    local corner = mp.omniumFolioCorner or "BOTTOMLEFT"
    if EBS._MinimapBlizz() then
        -- Stock styles: the stock spot on the ring (the button's centre
        -- 84 left and 63.5 below the map centre at the stock 198px map: the
        -- backdrop's TOPLEFT -3,-150 for the 53px button), mirrored to the chosen
        -- corner and scaled with the map. Anchor offsets are in the button's own
        -- scale, so the map units divide by it; the nudges stay as they were.
        local mapW = Minimap:GetWidth() or (mp.mapSize or 140)
        local s = (mapW / 198) / (btn:GetScale() or 1)
        local cx = (corner == "BOTTOMRIGHT" or corner == "TOPRIGHT") and 84 or -84
        local cy = (corner == "TOPLEFT" or corner == "TOPRIGHT") and 63.5 or -63.5
        btn:SetPoint("CENTER", Minimap, "CENTER", cx * s + (mp.omniumFolioX or 0), cy * s + (mp.omniumFolioY or 0))
    else
        btn:SetPoint(corner, GetFFD(Minimap).layoutFrame or Minimap, corner, mp.omniumFolioX or 0, mp.omniumFolioY or 0)
    end
    _omniumFolioApplying = false
end

-- True while the cursor is over the map region OR the hover-mode folio (which can
-- overhang the minimap rect at reduced scale). The 4px slop matters: OnEnter fires on
-- the engine's exact-pixel focus test, while this Lua-side test rounds cursor coords
-- through effective scale and can round the other way sub-pixel at the boundary
-- (resolution/scale dependent, which is why it repros on some machines only); the
-- expanded rect ensures "engine entered" implies "this test passes", so the exit watcher never fires early.
function EBS._HoverStillOver(minimap)
    local hoverFrame = GetFFD(minimap).pingBlocker or GetFFD(minimap).layoutFrame or minimap
    if hoverFrame:IsMouseOver(4, -4, -4, 4) then return true end
    local b = _G.ExpansionLandingPageMinimapButton
    if b and b:IsShown() and b:IsMouseOver(4, -4, -4, 4) then return true end
    return false
end

-- Immediate hide for map-region hover elements (zoom buttons, hover-mode folio,
-- coordinates): fired from the minimap's OnLeave on a real exit (in step with
-- Blizzard's own zoom fade), and from the exit watcher for exits across a child
-- element (those never fire a second minimap OnLeave). Cancels the watcher.
function EBS._HVHideNow()
    local minimap = Minimap
    if not minimap then return end
    local ffd = GetFFD(minimap)
    if ffd.hvWatcher then
        ffd.hvWatcher:Cancel()
        ffd.hvWatcher = nil
    end
    local zi, zo = minimap.ZoomIn, minimap.ZoomOut
    if zi then zi:Hide() end
    if zo then zo:Hide() end
    local m2 = EBS.db and EBS.db.profile.minimap
    if m2 then
        if GetOmniumFolioMode(m2) == "hover" then
            local b = _G.ExpansionLandingPageMinimapButton
            if b then b:Hide() end
        end
        if GetCoordsModePos(m2) == "hover" then
            if coordFrame then coordFrame:Hide() end
            if coordTicker then coordTicker:Hide() end
        end
    end
    -- Extra buttons hide in the SAME instant: the 0.12s deferral only bridges gap-
    -- crossings between stack frames mid-hover, and a true region exit has nothing to
    -- bridge. If the cursor is still over part of the stack (row button, open flyouts,
    -- friends tooltip), OverAny keeps it shown via the normal path.
    if _moActive then
        if MO_OverAny() then
            if MO_Evaluate then MO_Evaluate() end
        else
            MO_CancelHide()
            MO_Apply(false)
        end
    end
end

-- Central map-region hover reveal (EBS field, see EllesmereUIMinimap.lua). Fired from the
-- minimap's OnEnter/OnLeave and from over-map children's OnEnter (clock, FPS text,
-- corner mail, folio): no-ops off-region, reveals zoom buttons and hover-mode folio,
-- and runs one self-cancelling watcher (minimap's FFD data) that hides them once the
-- cursor truly leaves -- including exits FROM a child, which never fire a 2nd OnLeave.
function EBS._HVRevealMapHover()
    local minimap = Minimap
    if not minimap then return end
    local ffd = GetFFD(minimap)
    if not ffd.active then return end
    if not EBS._HoverStillOver(minimap) then
        -- OnEnter is SINGLE-SHOT per hover: if this check fails at the boundary, nothing
        -- re-attempts the reveal for the whole hover (slow entries dwelt there and
        -- failed consistently). Retry briefly and self-cancel when clearly gone.
        if not ffd.hvRetry then
            local tries = 0
            ffd.hvRetry = C_Timer.NewTicker(0.1, function()
                tries = tries + 1
                if EBS._HoverStillOver(minimap) then
                    ffd.hvRetry:Cancel(); ffd.hvRetry = nil
                    EBS._HVRevealMapHover()
                elseif tries >= 8 then
                    ffd.hvRetry:Cancel(); ffd.hvRetry = nil
                end
            end)
        end
        return
    end
    if ffd.hvRetry then ffd.hvRetry:Cancel(); ffd.hvRetry = nil end
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp then return end
    local function raiseZoom()
        local zi, zo = minimap.ZoomIn, minimap.ZoomOut
        if UIFrameFadeRemoveFrame then
            if zi then UIFrameFadeRemoveFrame(zi) end
            if zo then UIFrameFadeRemoveFrame(zo) end
        end
        if zi then zi:SetAlpha(1); zi:Show() end
        if zo then zo:SetAlpha(1); zo:Show() end
    end
    if not mp.hideZoomButtons then
        raiseZoom()
    end
    if GetOmniumFolioMode(mp) == "hover" and not IsFolioReplacedByAddOn() then
        local b = _G.ExpansionLandingPageMinimapButton
        if b then
            PositionOmniumFolio(b)
            if not b:IsShown() and b.RefreshButton then b:RefreshButton(true) end
        end
    end
    if GetCoordsModePos(mp) == "hover" then
        if coordFrame then coordFrame:Show() end
        if coordTicker then coordTicker:Show() end
        UpdateCoords()
    end
    -- Same "map region hovered" notion; MO_Evaluate self-guards when the feature is off.
    if MO_Evaluate then MO_Evaluate() end
    if ffd.hvWatcher then return end
    ffd.hvWatcher = C_Timer.NewTicker(0.2, function()
        if EBS._HoverStillOver(minimap) then
            -- Still over the map: keep defeating Blizzard's fader (an intervening
            -- OnLeave may have re-armed it).
            local m2 = EBS.db and EBS.db.profile.minimap
            if m2 and not m2.hideZoomButtons then
                raiseZoom()
            end
            return
        end
        EBS._HVHideNow()
    end)
end

local function ApplyOmniumFolio()
    -- No expansion landing page on WoW Forever: the button is left to
    -- Blizzard entirely (its own refresh path errors there), no hooks either.
    if EllesmereUI.IS_FOREVER then return end
    local btn = _G.ExpansionLandingPageMinimapButton
    if not btn or not Minimap then return end
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not mp then return end

    -- One-time persistent hooks: Blizzard re-anchors/rescales/reparents this button
    -- after loading screens (RefreshButton, edit-mode relayout) often WITHOUT calling
    -- Show(), so a Show-only hook would let it drift to the default TOPLEFT anchor
    -- inside the alpha-0 MinimapCluster (wrong position or missing button until
    -- /reload) -- re-assert on every parent/point/scale change too.
    if not _omniumFolioHooked then
        _omniumFolioHooked = true
        local function reassert(self)
            if _omniumFolioApplying then return end
            local m = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            if not m then return end
            local mode = GetOmniumFolioMode(m)
            -- Boundary-tolerant like the reveal path: RefreshButton Hide()/Show()s the button, and a raw IsMouseOver could veto that Show at the exact edge.
            if mode == "never"
               or IsFolioReplacedByAddOn()
               or (mode == "hover" and not (Minimap and EBS._HoverStillOver(Minimap))) then
                self:Hide()
            else
                PositionOmniumFolio(self)
            end
        end
        hooksecurefunc(btn, "Show", reassert)
        hooksecurefunc(btn, "SetParent", reassert)
        hooksecurefunc(btn, "SetPoint", reassert)
        hooksecurefunc(btn, "SetScale", reassert)
        -- Hovering the folio counts as hovering the map region (also covers entering the map directly onto it).
        btn:HookScript("OnEnter", function() EBS._HVRevealMapHover() end)
    end

    local mode = GetOmniumFolioMode(mp)
    if mode == "never" then
        btn:Hide()
        return
    end
    -- Replacement on screen: leave Blizzard's alone rather than resurrecting it beside the replacement (see IsFolioReplacedByAddOn).
    if IsFolioReplacedByAddOn() then return end
    if mode == "hover" and not Minimap:IsMouseOver() then
        btn:Hide()
        return
    end
    -- Enabled: position/raise, then ensure visible. Blizzard Shows this button when the
    -- ExpansionLandingPage overlay applies, but "OverlayChanged" can fire before the
    -- button registers its callback (after /reload and zoning), leaving it at its XML
    -- hidden default. When hidden, nudge Blizzard's own RefreshButton instead of a raw
    -- Show(): it re-runs the real show/hide decision (hides when ShouldShow is false or
    -- in an empty Garrison) and repaints the current expansion icon, so this never forces
    -- a stale button unlike a raw Show(). Its Show() re-fires our reposition hook.
    PositionOmniumFolio(btn)
    if not btn:IsShown() and btn.RefreshButton then
        btn:RefreshButton(true)
    end
end

I.ApplyOmniumFolio, I.CaptureBlizzardMinimap = ApplyOmniumFolio, CaptureBlizzardMinimap
I.LayoutIndicatorFrames = LayoutIndicatorFrames
I.SyncIndicatorVisibility = SyncIndicatorVisibility
I.broken = false
