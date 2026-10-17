if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Buttons.lua
--
--  Free move offsets, the zoom memory, the folio and flyout blacklists and
--  the scan that collects and hides the addon buttons.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local _addonVisible, cachedAddonButtons, EBS = I._addonVisible, I.cachedAddonButtons, I.EBS
local flyoutOwnedFrames, GetFFD, QueueApplyAll = I.flyoutOwnedFrames, I.GetFFD, I.QueueApplyAll
local InvalidateFlyout, IsUngrouped = I.InvalidateFlyout, I.IsUngrouped

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local flyoutToggle
I.flyoutToggleSetters[#I.flyoutToggleSetters + 1] = function(v) flyoutToggle = v end
local flyoutPanel
I.flyoutPanelSetters[#I.flyoutPanelSetters + 1] = function(v) flyoutPanel = v end
-- Assigned when EUI_Minimap_Apply.lua loads (see SetApplyMinimap); the free
-- move release in EnableFreeMove runs it.
local ApplyMinimap
I.applyMinimapSetters[#I.applyMinimapSetters + 1] = function(v) ApplyMinimap = v end

-------------------------------------------------------------------------------
--  Free Move Button System
--  freeMoveBtns: shift+drag any minimap-area button. Offsets are stored in
--  DB.profile.minimap.btnPositions keyed by a stable identifier string.
-------------------------------------------------------------------------------
local function GetBtnPosKey(frame)
    -- Custom indicator buttons store their key directly
    if frame._indicatorKey then return frame._indicatorKey end
    local name = frame:GetName()
    if name then return name end
    if frame == flyoutToggle then return "_flyoutToggle" end
    return nil
end

local function GetBtnOffset(key)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp or not mp.freeMoveBtns or not mp.btnPositions then return 0, 0 end
    local pos = mp.btnPositions[key]
    if not pos then return 0, 0 end
    return pos.x or 0, pos.y or 0
end

local function SaveBtnOffset(key, x, y)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp then return end
    if not mp.btnPositions then mp.btnPositions = {} end
    mp.btnPositions[key] = { x = x, y = y }
end

local _freeMoveHooked = {}  -- [frame] = true, one-time hook guard

local function EnableFreeMove(frame)
    if not frame or _freeMoveHooked[frame] then return end
    _freeMoveHooked[frame] = true

    local key = GetBtnPosKey(frame)
    if not key then return end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Third-party buttons (LibDBIcon etc.) own OnClick: wrap it so the drag flag blocks click-through.
    if not frame._indicatorKey and frame ~= flyoutToggle then
        local origClick = frame:GetScript("OnClick")
        if origClick then
            frame:SetScript("OnClick", function(self, ...)
                if GetFFD(self).freeMoveJustDragged then return end
                origClick(self, ...)
            end)
        end
    end

    local isDragging = false
    local startX, startY, origOffX, origOffY

    local origPoint, origRel, origRelPoint, origX, origY

    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            self:SetScript("OnUpdate", nil)
            -- Clear the drag flag on the next frame (set in OnMouseDown)
            C_Timer.After(0, function() GetFFD(self).freeMoveJustDragged = nil end)
            local es = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es, cy / es
            local dx, dy = cx - startX, cy - startY
            SaveBtnOffset(key, origOffX + dx, origOffY + dy)
            if ApplyMinimap then ApplyMinimap() end
            return
        end
        -- Move the button directly during drag (no full relayout)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        if origPoint then
            self:ClearAllPoints()
            self:SetPoint(origPoint, origRel, origRelPoint, origX + origOffX + dx, origY + origOffY + dy)
        end
    end

    frame:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end
        local mp = EBS.db and EBS.db.profile.minimap
        if not mp or not mp.freeMoveBtns then return end
        isDragging = true
        -- Block clicks immediately so OnClick can never fire mid-drag whatever the event ordering; cleared on the frame after release.
        GetFFD(self).freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        origOffX, origOffY = GetBtnOffset(key)
        -- Snapshot the anchor, minus the current offset, to get the base position.
        origPoint, origRel, origRelPoint, origX, origY = self:GetPoint(1)
        origX = (origX or 0) - origOffX
        origY = (origY or 0) - origOffY
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    frame:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not isDragging then return end
        isDragging = false
        self:SetScript("OnUpdate", nil)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        SaveBtnOffset(key, origOffX + dx, origOffY + dy)
        C_Timer.After(0, function() GetFFD(frame).freeMoveJustDragged = nil end)
        if ApplyMinimap then ApplyMinimap() end
    end)

end

-- Apply saved offset to a button (called during layout)
local function ApplyBtnOffset(frame)
    if not frame then return end
    local key = GetBtnPosKey(frame)
    if not key then return end
    local ox, oy = GetBtnOffset(key)
    if ox == 0 and oy == 0 then return end
    local p1, rel, p2, x, y = frame:GetPoint(1)
    if p1 then
        frame:SetPoint(p1, rel, p2, (x or 0) + ox, (y or 0) + oy)
    end
end

local function SaveZoomLevel()
    local p = EBS.db and EBS.db.profile.minimap
    if not p then return end
    p.savedZoom = Minimap:GetZoom()
end

-- Auto Zoom Reset: (re)arms a one-shot timer on every manual zoom change (scroll wheel, zoom buttons) that snaps the map back to zoom level 0 (max distance) after zoomResetSeconds of inactivity. 0 = disabled.
local zoomResetTimer
local function RestartZoomResetTimer()
    if zoomResetTimer then
        zoomResetTimer:Cancel()
        zoomResetTimer = nil
    end
    local p = EBS.db and EBS.db.profile.minimap
    local secs = p and p.zoomResetSeconds or 0
    if not secs or secs <= 0 then return end
    zoomResetTimer = C_Timer.NewTimer(secs, function()
        zoomResetTimer = nil
        if Minimap:GetZoom() ~= 0 then
            Minimap:SetZoom(0)
            SaveZoomLevel()
        end
    end)
end

-- Global names of third-party buttons that REPLACE the expansion landing page button:
-- they hide Blizzard's (usually unregistering its events first) and parent their own to the minimap in the same corner.
local FOLIO_REPLACEMENT_BUTTONS = {
    "PlumberLandingPageMinimapButton",
}

-- Blizzard structural frames that should NOT go into the flyout
local flyoutBlacklist = {
    MinimapZoomIn    = true,
    MinimapZoomOut   = true,
    MinimapBackdrop  = true,
    GameTimeFrame    = true,
    -- Core Blizzard feature button; keep on the map surface, not in the flyout.
    ExpansionLandingPageMinimapButton = true,
    -- Same for the addon compartment: it is parented to the Minimap so it can
    -- be seen at all (see EBS._ApplyAddonCompartment), which puts it in reach
    -- of the child scan below -- and it is a menu of every addon's entries,
    -- not one addon's button, so it never belongs inside the group flyout.
    AddonCompartmentFrame = true,
}

-- A replacement landing button is a feature button, not a generic addon button, so it
-- belongs on the minimap surface. Sweeping one into the flyout RE-CREATES the
-- duplicate-button bug: HideMinimapChild hides it, our folio code sees none and resurrects Blizzard's via RefreshButton, which the addon never re-hides.
for _, name in ipairs(FOLIO_REPLACEMENT_BUTTONS) do
    flyoutBlacklist[name] = true
end

-- Persistently hide a minimap button via Show hook
local addonButtonHooks = {}

local function HideMinimapChild(btn)
    EBS._suppressVisTrack = true
    -- Hide() on a protected frame is blocked inside lockdown for ANY insecure caller,
    -- taint or not, and the block is silent (no Lua error) -- so the SetAlpha below
    -- still ran and the button just went invisible-but-shown. Skip only the blocked
    -- call and queue the re-apply, which performs the real Hide() on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() and btn:IsProtected() then
        QueueApplyAll()
    else
        btn:Hide()
    end
    btn:SetAlpha(0)
    EBS._suppressVisTrack = false
    if not addonButtonHooks[btn] then
        -- Track addon-intended visibility via Show/Hide hooks
        hooksecurefunc(btn, "Show", function(self)
            if not EBS._suppressVisTrack then
                -- Don't track addon Show() while the flyout is open: the button is
                -- visible in our grid and a later Hide() would mark it unwanted.
                if not (flyoutPanel and flyoutPanel:IsShown()) then
                    _addonVisible[self] = true
                    -- The grid is cached across opens; a wanted-state change must rebuild
                    -- it, or the button stays an alpha-0 gap in the old layout.
                    InvalidateFlyout()
                end
            end
            if InCombatLockdown() then return end
            -- Never zero alpha while the flyout is open: periodic addon Show() calls
            -- would blank buttons that are visible in the grid.
            if flyoutPanel and flyoutPanel:IsShown() then return end
            if IsUngrouped(self) then return end
            local mp = EBS.db and EBS.db.profile.minimap
            if mp and mp.enabled and not flyoutOwnedFrames[self] then
                self:SetAlpha(0)
            end
        end)
        hooksecurefunc(btn, "Hide", function(self)
            if not EBS._suppressVisTrack then
                -- Freeze tracking while open: addon refresh Hide() calls would otherwise
                -- blank buttons from the grid.
                if flyoutPanel and flyoutPanel:IsShown() then
                    self:Show()
                    return
                end
                _addonVisible[self] = false
                InvalidateFlyout()
            end
        end)
        addonButtonHooks[btn] = true
    end
end

-- Pin/POI frame patterns to exclude from the flyout (HandyNotes, TomTom, etc.)
local flyoutPinPatterns = {
    "^HandyNotes",
    "^TomTom",
    "^HereBeDragons",
    "^Questie",
    "^GatherMate",
    "^pin",
    "^Pin",
}

local function IsPinFrame(name)
    if not name then return false end
    for _, pat in ipairs(flyoutPinPatterns) do
        if name:match(pat) then return true end
    end
    return false
end

-- Third-party addon buttons show a game tooltip from their OnEnter: LibDBIcon buttons
-- use the lib's own LibDBIconTooltip (anchored by screen half, tooltips BELOW the
-- icons), everything else the global GameTooltip. Post-hook each collected button so
-- its tooltip follows Grow Tooltip/Popup -- by then the addon owned/anchored/shown it, so re-pointing wins. Namespace-scoped.
do
    local hooked = {}
    local function repoint(tt, btn)
        if tt and tt:IsShown() and tt:GetOwner() == btn then
            local gpt = EBS._Grow.edge[EBS._Grow.Dir()] or EBS._Grow.edge.left
            tt:ClearAllPoints()
            tt:SetPoint(gpt[1], btn, gpt[2], gpt[3], gpt[4])
        end
    end
    function EBS._HookAddonBtnTT(btn)
        if hooked[btn] then return end
        hooked[btn] = true
        btn:HookScript("OnEnter", function(self)
            repoint(_G.GameTooltip, self)
            repoint(_G.LibDBIconTooltip, self)
        end)
    end
end

-- Gather all minimap buttons (Blizzard + addon) into cachedAddonButtons
local function GatherMinimapButtons()
    wipe(cachedAddonButtons)
    if not Minimap then return end
    -- Also scan flyout panel children (buttons we already reparented)
    local sources = { Minimap }
    if flyoutPanel then sources[2] = flyoutPanel end
    for _, source in ipairs(sources) do
        for _, child in ipairs({ source:GetChildren() }) do
            if not flyoutOwnedFrames[child] then
                local name = child:GetName()
                if flyoutBlacklist[name] then
                    -- skip
                elseif IsPinFrame(name) then
                    -- skip pin/POI frames
                elseif child:IsObjectType("Button") and name
                    and not name:match("%d+$") then
                    local w = child:GetWidth() or 0
                    -- Width gate applies to first discovery only; once tracked in
                    -- _addonVisible a button is always re-collected, so our own SetSize (slider < 20) can't permanently drop it.
                    if w >= 20 or _addonVisible[child] ~= nil then
                        if _addonVisible[child] == nil then
                            _addonVisible[child] = child:IsShown()
                        end
                        cachedAddonButtons[#cachedAddonButtons + 1] = child
                        EBS._HookAddonBtnTT(child)
                    end
                elseif not child:IsObjectType("Button") and name and name:match("^LibDBIcon10_") then
                    if _addonVisible[child] == nil then
                        _addonVisible[child] = child:IsShown()
                    end
                    cachedAddonButtons[#cachedAddonButtons + 1] = child
                    EBS._HookAddonBtnTT(child)
                end
            end
        end
    end
    -- The only minimap button at all, if the scan found exactly one: it shows
    -- on the row ungrouped and no group toggle appears (IsUngrouped reads
    -- this). With two or more, grouping is the user's choice alone, even when
    -- they ungroup all but one. A second button ends the solo state on the
    -- next scan.
    local solo, count = nil, 0
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false then
            count = count + 1
            solo = btn
        end
    end
    EBS._soloAddonButton = (count == 1) and solo or nil
end

-- Expose for options UI
_G._EBS_CachedAddonButtons = cachedAddonButtons
_G._EBS_AddonVisible = _addonVisible

-- Hide all collected minimap buttons from the map surface. Ungrouped buttons are left
-- alone (positioned by LayoutIndicatorFrames); buttons inside the open flyout are
-- skipped too, since HideMinimapChild's EBS._suppressVisTrack bypasses the force-show protection in the Hide hook and would zero their alpha with no recovery.
local function HideAllMinimapButtons()
    GatherMinimapButtons()
    local flyoutOpen = flyoutPanel and flyoutPanel:IsShown()
    for _, btn in ipairs(cachedAddonButtons) do
        if not IsUngrouped(btn) then
            if flyoutOpen and btn:GetParent() == flyoutPanel then
                -- Button is visible in the flyout grid; leave it alone
            else
                HideMinimapChild(btn)
            end
        end
    end
end

I.ApplyBtnOffset, I.EnableFreeMove = ApplyBtnOffset, EnableFreeMove
I.FOLIO_REPLACEMENT_BUTTONS = FOLIO_REPLACEMENT_BUTTONS
I.HideAllMinimapButtons, I.RestartZoomResetTimer = HideAllMinimapButtons, RestartZoomResetTimer
I.SaveZoomLevel = SaveZoomLevel
I.broken = false
