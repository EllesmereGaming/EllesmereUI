if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Apply.lua
--
--  ApplyMinimap, the full apply pass.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EBS, flyoutOwnedFrames = I.EBS, I.flyoutOwnedFrames
local GetBorderStyleColor, GetFFD = I.GetBorderStyleColor, I.GetFFD
local minimapDecorations, PP, QueueApplyAll = I.minimapDecorations, I.PP, I.QueueApplyAll
local TEMP_DISABLED, BuildFlyoutContents = I.TEMP_DISABLED, I.BuildFlyoutContents
local CollectFlyoutButtons, CreateFlyoutToggle = I.CollectFlyoutButtons, I.CreateFlyoutToggle
local HideFlyoutPanel, InvalidateFlyout = I.HideFlyoutPanel, I.InvalidateFlyout
local ApplyMinimapFont, GetCoordsModePos = I.ApplyMinimapFont, I.GetCoordsModePos
local GetDescColor, GetElementModes = I.GetDescColor, I.GetElementModes
local MAP_POS_ANCHORS, RefreshClockCVars = I.MAP_POS_ANCHORS, I.RefreshClockCVars
local ResolveElementAnchor, UpdateClock = I.ResolveElementAnchor, I.UpdateClock
local UpdateCoords, UpdateLocation = I.UpdateCoords, I.UpdateLocation
local HideAllMinimapButtons = I.HideAllMinimapButtons
local RestartZoomResetTimer, SaveZoomLevel = I.RestartZoomResetTimer, I.SaveZoomLevel
local HideVaultTooltip, ShowVaultTooltip = I.HideVaultTooltip, I.ShowVaultTooltip
local GetCalendarLockoutEntries = I.GetCalendarLockoutEntries
local HideCalendarTooltip, ShowCalendarTooltip = I.HideCalendarTooltip, I.ShowCalendarTooltip
local ApplyOmniumFolio, CaptureBlizzardMinimap = I.ApplyOmniumFolio, I.CaptureBlizzardMinimap
local LayoutIndicatorFrames = I.LayoutIndicatorFrames
local SyncIndicatorVisibility, DesiredMapParent = I.SyncIndicatorVisibility, I.DesiredMapParent

-- The setters are called as I.Set<Name> in this file: ApplyMinimap is close to
-- Lua's limit of 60 upvalues per function, and I costs one where a local per
-- setter costs six.

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local flyoutToggle
I.flyoutToggleSetters[#I.flyoutToggleSetters + 1] = function(v) flyoutToggle = v end
local flyoutPanel
I.flyoutPanelSetters[#I.flyoutPanelSetters + 1] = function(v) flyoutPanel = v end
local coordFrame
I.coordFrameSetters[#I.coordFrameSetters + 1] = function(v) coordFrame = v end
local coordTicker
I.coordTickerSetters[#I.coordTickerSetters + 1] = function(v) coordTicker = v end
local clockFrame
I.clockFrameSetters[#I.clockFrameSetters + 1] = function(v) clockFrame = v end
local clockBg
I.clockBgSetters[#I.clockBgSetters + 1] = function(v) clockBg = v end
local locationFrame
I.locationFrameSetters[#I.locationFrameSetters + 1] = function(v) locationFrame = v end
local locationBg
I.locationBgSetters[#I.locationBgSetters + 1] = function(v) locationBg = v end

local clockTicker
local fpsBg
local diffTextFrame
local addonButtonPoll = nil

-- Set while Blizzard's Toggle Minimap key has hidden the map (the hook, in EUI_Minimap_Lifecycle.lua, sits below
-- UpdateMinimapVisibility); every visibility pass then keeps the map hidden.
local _mmKeyHidden
I.mmKeyHiddenSetters[#I.mmKeyHiddenSetters + 1] = function(v) _mmKeyHidden = v end

local function ApplyMinimap()
    if TEMP_DISABLED.minimap then return end
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.minimap
    p.enabled = true
    local blizz = EBS._MinimapBlizz()

    -- Rotate Minimap: enforce the CVar to match our setting (out of combat only).
    EllesmereUI.SetCVar("rotateMinimap", p.rotateMinimap and "1" or "0", "EllesmereUIMinimap")
    -- Icon Size: nothing while unset (Edit Mode's value stands).
    EBS._ApplyMinimapIconScale()

    local minimap = Minimap
    if not minimap then return end

    if not p.enabled then
        -- Untouched this session: do nothing (zero interference with other addons).
        if not GetFFD(minimap).active then return end
        -- Was active, now disabled: only a reload hands control back to Blizzard cleanly; the options toggle prompts for it.
        return
    end

    -- Ensure Blizzard_TimeManager is loaded so GameTimeFrame (calendar) exists
    if not _G.GameTimeFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_TimeManager")
    end

    -- Snapshot Blizzard's native size/position before we modify anything
    CaptureBlizzardMinimap()

    -- Reparent out of MinimapCluster so its layout cannot override our size, and so the
    -- native render is clipped by the frame we own rather than by Blizzard's cluster.
    -- Deferred via C_Timer.After(0) to avoid tainting the secure frame environment when
    -- ApplyMinimap fires during a ShowUIPanel/World Map open -- that taint causes
    -- ADDON_ACTION_BLOCKED when the dungeon pin data provider later calls the protected SetPropagateMouseClicks() on map pins.
    local needsClusterHide = MinimapCluster and MinimapCluster:IsShown()
    -- A cropped canvas's parent is built later in this pass, so the first crop has
    -- to schedule the reparent on the layout frame's absence.
    local needsReparent = minimap:GetParent() ~= DesiredMapParent(minimap)
        or (EBS._MapCrop(p, p.mapSize or 140) > 0 and not GetFFD(minimap).layoutFrame)
    if needsReparent or needsClusterHide then
        C_Timer.After(0, function()
            if InCombatLockdown() then QueueApplyAll(); return end
            local want = DesiredMapParent(minimap)
            if minimap:GetParent() ~= want then
                minimap:SetParent(want)
            end
            if needsClusterHide and MinimapCluster then
                MinimapCluster:SetAlpha(0)
                MinimapCluster:EnableMouse(false)
            end
            -- The cluster's Edit Mode selection box ignores that alpha.
            EBS._SuppressMinimapSelection()
        end)
    end
    -- Blizzard reparents the minimap during housing transitions and other events; hook SetParent to force it back.
    if not GetFFD(minimap).parentGuard then
        GetFFD(minimap).parentGuard = true
        hooksecurefunc(minimap, "SetParent", function()
            local want = DesiredMapParent(minimap)
            if minimap:GetParent() ~= want then
                if InCombatLockdown() then
                    -- Dropping it would leave the map parented to -- and clipped by --
                    -- whatever reparented it (the cluster, on a battleground or housing
                    -- transition) for the rest of the session.
                    QueueApplyAll()
                else
                    minimap:SetParent(want)
                end
            end
        end)
        -- Lock strata/level so Blizzard can't change them during transitions
        if minimap.SetFixedFrameStrata then minimap:SetFixedFrameStrata(true) end
        if minimap.SetFixedFrameLevel then minimap:SetFixedFrameLevel(true) end
    end
    -- Visibility-aware terminal: an unconditional Show() here would force-show the
    -- minimap for a frame on EVERY rebuild (blink at visibility never/mouseover, e.g.
    -- settings-override transitions), before the deferred sweep corrects it. Render the profile's visibility directly instead.
    do
        local vis = EllesmereUI.EvalVisibility and p and EllesmereUI.EvalVisibility(p)
        -- Opacity in every state: a hidden map carries it into its next Show().
        EBS._WriteMapAlpha(minimap, p)
        if _mmKeyHidden then
            minimap:Hide()
        elseif not EllesmereUI.EvalVisibility or vis == true then
            minimap:Show()
        elseif vis == "mouseover" then
            -- Idle state is a real Hide(), not alpha 0 -- see UpdateMinimapVisibility.
            if minimap:IsMouseOver() then minimap:Show() else minimap:Hide() end
        elseif vis then
            minimap:Show()
        else
            minimap:Hide()
        end
    end

    -- Middle-click interceptor: transparent frame over the minimap passing left/right
    -- clicks through but routing middle-click to our micro menu instead of the ping
    -- (zero taint risk). Also the SQUARE mouse surface: the Minimap's own hit region
    -- stays circular, so wheel zoom dies in the square skin's corners -- this overlay covers the full rect and handles the wheel there.
    if not GetFFD(minimap).pingBlocker then
        local blocker = CreateFrame("Frame", nil, minimap)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(minimap:GetFrameLevel() + 10)
        blocker:SetPassThroughButtons("LeftButton", "RightButton")
        blocker:SetPropagateMouseMotion(true)
        blocker:SetScript("OnMouseUp", function(_, btn)
            if btn == "MiddleButton" and EBS._ToggleMicroMenu then
                -- Gated by the "Open Micro Menu on Middle Click" toggle (read live)
                local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
                if mp and mp.openMicroMenuOnMiddleClick == false then return end
                EBS._ToggleMicroMenu()
            end
        end)
        blocker:SetScript("OnMouseWheel", function(_, delta)
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.scrollZoom then return end
            local zoom = minimap:GetZoom()
            if delta > 0 then
                zoom = min(zoom + 1, 5)
            else
                zoom = max(zoom - 1, 0)
            end
            minimap:SetZoom(zoom)
            SaveZoomLevel()
            RestartZoomResetTimer()
        end)
        -- Map-region hover reveal, entry-path-proof: the Minimap's motion focus follows
        -- its CIRCULAR hit region, so entering the square skin through a corner (or
        -- directly onto an unhooked child) never fires its OnEnter. This overlay covers
        -- the FULL rect and, with SetPropagateMouseMotion, gets enter/leave while still
        -- passing motion through (_HVRevealMapHover self-guards via region + dedupe).
        blocker:HookScript("OnEnter", function()
            if EBS._HVRevealMapHover then EBS._HVRevealMapHover() end
        end)
        GetFFD(minimap).pingBlocker = blocker
    end

    for _, name in ipairs(minimapDecorations) do
        local frame = _G[name]
        -- Blizzard Style keeps the stock compass ring (placed once the map has
        -- its size); Classic WoW UI draws its own ring and hides it like EUI.
        if frame and not (blizz and not EBS._MinimapClassic() and name == "MinimapCompassTexture") then frame:Hide() end
    end
    -- WoW Forever's Rotate Minimap shows a fixed ring under the compass, and
    -- Blizzard re-shows it on every rotate change without touching its alpha;
    -- the looks that hide the compass keep it invisible the same way.
    if EllesmereUI.IS_FOREVER and EBS._MinimapStyle() ~= "blizzard" then
        local underlay = _G.MinimapCompassTextureUnderlay
        if underlay then underlay:SetAlpha(0) end
    end
    -- The addon compartment is placed (or parked) by EBS._ApplyAddonCompartment
    -- at the end of this pass, once the map has its final size and position.

    -- The stock map is round and Forever Square square; the stored shape waits for the EUI look.
    local shape = EBS._MapShape(p)
    local isCircle = (shape == "circle" or shape == "textured_circle")
    local isRectangular = (shape == "rectangular")

    if GetFFD(minimap).bg then GetFFD(minimap).bg:SetAlpha(0) end

    local r, g, b, borderA = GetBorderStyleColor(p)
    -- Hide the circular quest area ring on square minimaps
    if minimap.SetArchBlobRingScalar then
        minimap:SetArchBlobRingScalar(isCircle and 1 or 0)
    end
    if minimap.SetQuestBlobRingScalar then
        minimap:SetQuestBlobRingScalar(isCircle and 1 or 0)
    end

    minimap:SetScale(1.0)
    local mapSize = p.mapSize or 140
    -- Blizzard's map projection and native player arrow require a square Minimap
    -- canvas. Rectangular mode therefore crops that square canvas with a centered
    -- 4:3 mask; resizing the Blizzard frame itself makes the terrain slide away
    -- from the arrow as zoom changes. A square frame's title bar crops it the same
    -- way, with the crop mask cut for its size (EBS._MapCrop).
    minimap:SetSize(mapSize, mapSize)
    local crop, cropMask = EBS._MapCrop(p, mapSize)
    local maskID = isCircle and 186178 or cropMask or 130937
    minimap:SetMaskTexture(maskID)
    minimap:SetHitRectInsets(0, 0, crop, crop)
    if crop > 0 and not GetFFD(minimap).layoutFrame then
        local layout = CreateFrame("Frame", nil, UIParent)
        layout:EnableMouse(false)
        GetFFD(minimap).layoutFrame = layout
    end
    do
        local layout = GetFFD(minimap).layoutFrame
        if layout then
            -- Re-anchored every pass for the reason the border host below is: this
            -- anchor spans the deferred SetParent that hangs the canvas off it.
            layout:ClearAllPoints()
            layout:SetPoint("CENTER", minimap, "CENTER")
            layout:SetSize(mapSize, mapSize - 2 * crop)
            layout:SetFrameLevel(minimap:GetFrameLevel())
        end
    end
    do
        local blocker = GetFFD(minimap).pingBlocker
        if blocker then
            blocker:ClearAllPoints()
            blocker:SetAllPoints(GetFFD(minimap).layoutFrame or minimap)
        end
    end

    if blizz then
        -- Stock styles: the stock chrome (compass ring + top bar, or the vanilla
        -- ring + banner) instead of any EUI border.
        if EBS._MinimapClassic() then
            EBS._ApplyClassicMinimapChrome(minimap, mapSize)
        else
            EBS._ApplyBlizzMinimapChrome(minimap, mapSize)
            if EllesmereUI.IS_FOREVER and EBS._MinimapForever() then EBS._ApplyForeverDiel(minimap, mapSize) end
            -- WoW Forever: a queue eye Action Bars parks on the ring follows a
            -- resize (its anchor on the map already follows a move).
            if EllesmereUI.IS_FOREVER then
                local ab = EllesmereUI._ModuleNS.EllesmereUIActionBars
                if ab then ab.AB_ForeverEyeRelayout() end
            end
        end
        if GetFFD(minimap).borderHost then GetFFD(minimap).borderHost:Hide() end
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif EBS._fvSquare then
        -- A square frame on the Forever client (the WoW Forever look's heavy
        -- bronze frame, or Blizzard Style's slim line) in place of the
        -- EllesmereUI border (latched for the session, so no EUI border is
        -- ever built beside it).
        EBS._ApplyForeverSquare(minimap)
    elseif not isCircle then
        -- Square / Rectangular: shared border-style engine (solid = PP strips, textured =
        -- BackdropTemplate) on a dedicated host frame -- the engine shows/hides the host
        -- freely, so it must never be the Minimap itself.
        local bs = p.borderSize or 1
        local host = GetFFD(minimap).borderHost
        if not host then
            host = CreateFrame("Frame", nil, minimap)
            host:EnableMouse(false)
            GetFFD(minimap).borderHost = host
        end
        -- Re-anchor on EVERY apply, not just create: this pass queues the Minimap's
        -- reparent to UIParent a frame out (above), and a host anchored across that
        -- reparent keeps its stored points while the engine never resolves them --
        -- GetPoint still reports valid TOPLEFT/BOTTOMRIGHT, but the host comes out 0x0
        -- with IsRectValid false (draws nothing while every other property reads
        -- healthy) -- which is why this presented as a border setting that would not
        -- survive a reload even though the stored value was never lost; anchoring only at
        -- creation made it permanent for the session, tracking how much else was loading
        -- at login rather than the actual setting. Re-setting the points forces a layout recompute; harmless no-op otherwise.
        host:ClearAllPoints()
        host:SetAllPoints(GetFFD(minimap).layoutFrame or minimap)
        -- Same level as the minimap keeps the border under all child buttons; Show Behind drops it under the map surface for the Shadow style.
        host:SetFrameLevel(p.borderBehind and math.max(0, minimap:GetFrameLevel() - 1) or minimap:GetFrameLevel())
        host:SetAlpha(1)
        -- Exact size beside the legacy step (nil = the legacy path unchanged).
        local px = EllesmereUI.BorderPx(p.borderSizePx, bs, p.borderTexture or "solid")
        EllesmereUI.ApplyBorderStyle(host, bs, r, g, b, borderA,
            p.borderTexture or "solid",
            p.borderTextureOffset, p.borderTextureOffsetY,
            p.borderTextureShiftX, p.borderTextureShiftY,
            "minimap", bs, nil, px)
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif p.shape == "circle" then
        -- Circle: solid colored disc behind the minimap, slightly larger = border ring
        if GetFFD(minimap).borderHost then GetFFD(minimap).borderHost:Hide() end
        if not GetFFD(minimap).circBorder then
            local disc = CreateFrame("Frame", nil, minimap)
            disc:SetFrameLevel(minimap:GetFrameLevel() - 1)
            local tex = disc:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(disc)
            tex:SetTexture("Interface\\Common\\CommonMaskCircle")
            disc._tex = tex
            GetFFD(minimap).circBorder = disc
        end
        local bs = p.borderSize or 1
        local circBorder = GetFFD(minimap).circBorder
        circBorder:ClearAllPoints()
        circBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -bs, bs)
        circBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", bs, -bs)
        circBorder._tex:SetVertexColor(r, g, b, 1)
        circBorder:Show()
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif p.shape == "textured_circle" then
        -- Textured Circle: void ring border, hide the solid circle border
        if GetFFD(minimap).borderHost then GetFFD(minimap).borderHost:Hide() end
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if not GetFFD(minimap).texCircBorder then
            local ring = minimap:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("wowlabs_minimapvoid-ring-single")
            GetFFD(minimap).texCircBorder = ring
        end
        local inset = 2
        local texCircBorder = GetFFD(minimap).texCircBorder
        texCircBorder:ClearAllPoints()
        texCircBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -inset, inset)
        texCircBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", inset, -inset)
        texCircBorder:SetVertexColor(r, g, b, 1)
        texCircBorder:Show()
    end

    -- Live-update border on accent change, only while the border actually resolves to the accent (accent swatch active, no class colour override).
    -- Neither square frame on the Forever client draws an EUI border to recolour.
    if p.useClassColor and not p.borderUseClassColor and not EBS._fvSquare then
        if not GetFFD(minimap).accentBorderCB then
            GetFFD(minimap).accentBorderCB = function(ar, ag, ab)
                -- Registration outlives mode switches: re-check before recoloring.
                local mp = EBS.db and EBS.db.profile.minimap
                if not mp or not mp.useClassColor or mp.borderUseClassColor then return end
                local host = GetFFD(minimap).borderHost
                if host and host:IsShown() then
                    EllesmereUI.SetBorderStyleColor(host, ar, ag, ab, 1)
                end
                local cb = GetFFD(minimap).circBorder
                if cb and cb:IsShown() then
                    cb._tex:SetVertexColor(ar, ag, ab, 1)
                end
                local tcb = GetFFD(minimap).texCircBorder
                if tcb and tcb:IsShown() then
                    tcb:SetVertexColor(ar, ag, ab, 1)
                end
            end
        end
        EllesmereUI.RegAccent({ type = "callback", fn = GetFFD(minimap).accentBorderCB })
    end

    -- Custom housing overlay: our own texture behind the minimap showing the housing indoor map when Blizzard hides the real content. No Blizzard frame manipulation.
    if not GetFFD(minimap).housingTex then
        local frame = CreateFrame("Frame", nil, minimap)
        frame:SetAllPoints(GetFFD(minimap).layoutFrame or minimap)
        frame:SetFrameLevel(minimap:GetFrameLevel() + 1)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        if isCircle then
            local inset = -mapSize * 0.10
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        elseif crop > 0 then
            tex:SetSize(mapSize, mapSize)
            tex:SetPoint("CENTER", frame, "CENTER")
        else
            tex:SetAllPoints(frame)
        end
        if isCircle or crop > 0 then
            local mask = frame:CreateMaskTexture()
            mask:SetAllPoints(frame)
            -- The housing frame already has the visible size, so it takes a
            -- whole-frame mask: Rectangular's full rectangular one, a square
            -- frame's crop the plain square (the canvas takes the crop masks).
            mask:SetTexture(isRectangular
                and "Interface\\AddOns\\EllesmereUIMinimap\\Media\\minimap_rectangular-mask.blp"
                or (isCircle and maskID) or 130937)
            tex:AddMaskTexture(mask)
            frame._mask = mask
            frame._maskAttached = true
        end
        frame._isCircle = isCircle
        frame._tex = tex
        frame:Hide()
        GetFFD(minimap).housingFrame = frame
        GetFFD(minimap).housingTex = tex
        -- Watch for MinimapBackdrop atlas changes to detect housing
        local backdrop = _G.MinimapBackdrop
        if backdrop then
            local function CheckHousing()
                local housingAtlas
                local regions = { backdrop:GetRegions() }
                for ri = 1, #regions do
                    local rgn = regions[ri]
                    if rgn and rgn.GetAtlas then
                        local atlas = rgn:GetAtlas()
                        if atlas and atlas:find("housing") then
                            housingAtlas = atlas
                            break
                        end
                    end
                end
                if housingAtlas then
                    if frame._isCircle then
                        tex:SetAtlas(housingAtlas)
                    else
                        tex:SetTexture("Interface\\AddOns\\EllesmereUIMinimap\\Media\\housing-minimap.png")
                    end
                    frame:Show()
                else
                    frame:Hide()
                end
            end
            GetFFD(minimap).checkHousing = CheckHousing
            -- Check on zone transitions
            if not GetFFD(minimap).housingZoneHook then
                GetFFD(minimap).housingZoneHook = true
                local zf = CreateFrame("Frame")
                zf:RegisterEvent("PLAYER_ENTERING_WORLD")
                zf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
                zf:RegisterEvent("ZONE_CHANGED_INDOORS")
                zf:SetScript("OnEvent", function()
                    C_Timer.After(0.5, CheckHousing)
                end)
            end
        end
    else
        -- Update existing housing frame on reapply (shape/mask can change live).
        local frame = GetFFD(minimap).housingFrame
        if frame then
            frame:ClearAllPoints()
            frame:SetAllPoints(GetFFD(minimap).layoutFrame or minimap)
            frame:SetFrameLevel(minimap:GetFrameLevel() + 1)
            frame._isCircle = isCircle
            if frame._tex then
                frame._tex:ClearAllPoints()
                if isCircle then
                    local inset = -mapSize * 0.10
                    frame._tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
                    frame._tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
                elseif crop > 0 then
                    frame._tex:SetSize(mapSize, mapSize)
                    frame._tex:SetPoint("CENTER", frame, "CENTER")
                else
                    frame._tex:SetAllPoints(frame)
                end
            end
            if isCircle or crop > 0 then
                if not frame._mask then
                    local mask = frame:CreateMaskTexture()
                    mask:SetAllPoints(frame)
                    frame._mask = mask
                end
                if frame._tex and not frame._maskAttached then
                    frame._tex:AddMaskTexture(frame._mask)
                    frame._maskAttached = true
                end
                frame._mask:SetTexture(isRectangular
                    and "Interface\\AddOns\\EllesmereUIMinimap\\Media\\minimap_rectangular-mask.blp"
                    or (isCircle and maskID) or 130937)
                frame._mask:Show()
            elseif frame._mask then
                if frame._tex and frame._maskAttached then
                    pcall(frame._tex.RemoveMaskTexture, frame._tex, frame._mask)
                    frame._maskAttached = false
                end
                frame._mask:Hide()
            end
        end
    end
    -- Shape changes do not fire a zone event. Reuse the existing housing detector
    -- so atlas/texture selection follows the new shape immediately.
    if GetFFD(minimap).checkHousing then GetFFD(minimap).checkHousing() end
    -- Clamp to the visible shape. A cropped map keeps a square native canvas,
    -- so allow only its hidden top/bottom strips beyond the screen bounds.
    minimap:SetClampedToScreen(true)
    if crop > 0 then
        minimap:SetClampRectInsets(0, 0, -crop, crop)
    else
        local bInset = isCircle and (p.borderSize or 1) or 0
        minimap:SetClampRectInsets(-bInset, bInset, bInset, -bInset)
    end
    -- Force the engine to re-render at the new size: nudge zoom, restore same frame.
    local curZoom = minimap:GetZoom()
    minimap:SetZoom(curZoom > 0 and 0 or 1)
    minimap:SetZoom(curZoom)

    -- Zoom buttons: parent to the minimap bottom-right, raise above the map surface,
    -- hook SetPoint so Blizzard can't re-anchor them (Midnight uses Minimap.ZoomIn/
    -- ZoomOut, not global MinimapZoomIn). With Zoom +/- Icons unchecked they live under
    -- the hidden frame instead, so Blizzard's hover show/fade never renders them; re-checking reparents them back.
    local zoomIn = minimap.ZoomIn or _G.MinimapZoomIn
    local zoomOut = minimap.ZoomOut or _G.MinimapZoomOut
    local hideZoom = p.hideZoomButtons
    if hideZoom and (zoomIn or zoomOut) and not EBS._hiddenFrame then
        EBS._hiddenFrame = CreateFrame("Frame")
        EBS._hiddenFrame:Hide()
    end
    if zoomIn then
        zoomIn:SetParent(hideZoom and EBS._hiddenFrame or minimap)
        zoomIn:SetFrameLevel(minimap:GetFrameLevel() + 10)
        EBS._ZoomAnchor(zoomIn, true, minimap)
        if EBS._MinimapClassic() then EBS._ClassicZoomButton(zoomIn, true, mapSize / 140) end
        zoomIn:EnableMouse(true)
        zoomIn:SetAlpha(1)
        -- Start in Blizzard's between-hovers state (hidden; hover handlers Show/Hide on map enter/leave) so it is not visible from /reload until hovered.
        zoomIn:SetShown(minimap:IsMouseOver())
        if not GetFFD(zoomIn).hooked then
            hooksecurefunc(zoomIn, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                EBS._ZoomAnchor(self, true, minimap)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomIn).hooked = true
        end
    end
    if zoomOut then
        zoomOut:SetParent(hideZoom and EBS._hiddenFrame or minimap)
        zoomOut:SetFrameLevel(minimap:GetFrameLevel() + 10)
        EBS._ZoomAnchor(zoomOut, false, minimap)
        if EBS._MinimapClassic() then EBS._ClassicZoomButton(zoomOut, false, mapSize / 140) end
        zoomOut:EnableMouse(true)
        zoomOut:SetAlpha(1)
        -- Same between-hovers start as ZoomIn above
        zoomOut:SetShown(minimap:IsMouseOver())
        if not GetFFD(zoomOut).hooked then
            hooksecurefunc(zoomOut, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                EBS._ZoomAnchor(self, false, minimap)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomOut).hooked = true
        end
    end

    -- Map-region hover reveal (zoom buttons + hover-mode folio). Blizzard's fader hides
    -- the zoom buttons on the Minimap's OnLeave, which also fires when the mouse moves
    -- onto a mouse-enabled child (clock, FPS text, folio, buttons); OnEnter never fires
    -- when the cursor enters the region directly on such a child. Both route through
    -- EBS._HVRevealMapHover (no-ops off-region, self-cancelling exit watcher); hooked children's own OnEnter covers direct entry.
    if not GetFFD(minimap).hoverRevealHooked then
        GetFFD(minimap).hoverRevealHooked = true
        minimap:HookScript("OnEnter", function() EBS._HVRevealMapHover() end)
        -- Real exits hide instantly (matching Blizzard's zoom fade); moving onto a child keeps the reveal alive and the watcher covers the exit from there.
        minimap:HookScript("OnLeave", function(self)
            if EBS._HoverStillOver(self) then
                EBS._HVRevealMapHover()
            else
                EBS._HVHideNow()
            end
        end)
    end

    if zoomIn and not GetFFD(zoomIn).zoomSaveHooked then
        zoomIn:HookScript("OnClick", function() SaveZoomLevel(); RestartZoomResetTimer() end)
        GetFFD(zoomIn).zoomSaveHooked = true
    end
    if zoomOut and not GetFFD(zoomOut).zoomSaveHooked then
        zoomOut:HookScript("OnClick", function() SaveZoomLevel(); RestartZoomResetTimer() end)
        GetFFD(zoomOut).zoomSaveHooked = true
    end

    -- Mark zoom buttons so GatherMinimapButtons skips them
    if zoomIn then flyoutOwnedFrames[zoomIn] = true end
    if zoomOut then flyoutOwnedFrames[zoomOut] = true end

    -- Flyout toggle button (bottom-left corner) -- create before hiding children
    CreateFlyoutToggle()

    HideAllMinimapButtons()

    -- Show/hide flyout toggle based on whether any grouped buttons exist
    local groupedButtons = CollectFlyoutButtons()
    local mp2 = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    local hideGroupBtn = mp2 and mp2.hideExtraBtns and mp2.hideExtraBtns.groupButton
    if #groupedButtons > 0 and not hideGroupBtn then
        flyoutToggle:Show()
    else
        flyoutToggle:Hide()
    end

    -- Poll for late-loading addons that attach buttons after ADDON_LOADED
    if not addonButtonPoll then
        addonButtonPoll = CreateFrame("Frame")
        addonButtonPoll:RegisterEvent("ADDON_LOADED")
        local pollPending = false
        addonButtonPoll:SetScript("OnEvent", function()
            if pollPending then return end
            pollPending = true
            C_Timer.After(0.1, function()
                pollPending = false
                HideAllMinimapButtons()
                -- New buttons may have appeared: rebuild the grid on next open.
                InvalidateFlyout()
                -- If already open, rebuild now so they appear without a reopen.
                if flyoutPanel and flyoutPanel:IsShown() then
                    BuildFlyoutContents()
                end
            end)
        end)
    end
    addonButtonPoll:Show()

    -- Rebuild on next open so button-list changes (ungroup, new addon, profile swap) are picked up and buttons HideAllMinimapButtons just hid are re-shown.
    InvalidateFlyout()
    -- Close the flyout if it was open (layout may have changed)
    HideFlyoutPanel()

    -- Hide Blizzard zone text (we use our own location bar)
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then zoneBtn:Hide() end
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
    end
    if MinimapZoneText then MinimapZoneText:Hide() end

    RefreshClockCVars()

    -- Clock -- none, inside the map, or boxed on the map edge
    local clockMode, locationMode = GetElementModes(p)
    if clockMode ~= "none" then
        if not clockBg then
            I.SetClockBg(CreateFrame("Button", nil, minimap, "BackdropTemplate"))
            clockBg:SetSize(80, 16)
            clockBg:SetPoint("TOP", minimap, "TOP", 0, 7)
            clockBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            clockBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            clockBg:RegisterForClicks("AnyUp")
            clockBg:SetScript("OnClick", function()
                -- With the Great Vault hover tooltip assigned, clicking the clock opens the vault (same as the Great Vault button), not the clock config.
                -- WoW Forever has no Great Vault: a saved "vault" reads as none there.
                local mp = EBS.db and EBS.db.profile.minimap
                if mp and mp.clockHoverTooltip == "vault" and not EllesmereUI.IS_FOREVER then
                    EllesmereUI.ToggleGreatVault()
                    return
                end
                if ToggleTimeManager then ToggleTimeManager() end
            end)
        end
        if not clockFrame then
            I.SetClockFrame(clockBg:CreateFontString(nil, "OVERLAY"))
            clockFrame:SetPoint("CENTER", clockBg, "CENTER", 0, 0)
            clockFrame:SetTextColor(1, 1, 1, 0.9)
        end
        local cxOff = p.clockOffsetX or 0
        local cyOff = p.clockOffsetY or 0
        if clockMode == "inside" then
            clockBg:SetBackdropColor(0, 0, 0, 0)
        else
            local ar, ag, ab = EBS._EdgeBoxColor(p)
            clockBg:SetBackdropColor(ar, ag, ab, 1)
        end
        local cpt, crel, cbx, cby = ResolveElementAnchor(p.clockPosition or "top", clockMode, isCircle)
        clockBg:ClearAllPoints()
        clockBg:SetPoint(cpt, GetFFD(minimap).layoutFrame or minimap, crel, cbx + cxOff, cby + cyOff)
        -- Align the TEXT edge with the anchor so it lands where the coordinates text
        -- would: inside style pins text to the same wrapper corner the wrapper pins to
        -- the map (wrapper is wider, so centered text would drift toward the middle); edge style keeps it centered in the box.
        clockFrame:ClearAllPoints()
        if clockMode == "inside" then
            clockFrame:SetPoint(cpt, clockBg, cpt, 0, 0)
        else
            clockFrame:SetPoint("CENTER", clockBg, "CENTER", 0, 0)
        end
        ApplyMinimapFont(clockFrame, p.clockSize or 12)
        clockBg:Show()
        clockFrame:Show()
        if not clockTicker then
            clockTicker = CreateFrame("Frame")  -- kept for CVar event + Show/Hide API
            clockTicker._ticker = nil
            clockTicker.Show = function(self)
                if self._ticker then return end
                self._ticker = C_Timer.NewTicker(10, function()
                    UpdateClock()
                end)
            end
            clockTicker.Hide = function(self)
                if self._ticker then self._ticker:Cancel(); self._ticker = nil end
            end
            clockTicker:RegisterEvent("CVAR_UPDATE")
            clockTicker:SetScript("OnEvent", function(_, _, cvarName)
                if cvarName == "timeMgrUseMilitaryTime" or cvarName == "timeMgrUseLocalTime" then
                    RefreshClockCVars()
                    UpdateClock()
                end
            end)
        end
        clockTicker:Show()
        UpdateClock()
        -- Hover tooltip (Show on Clock Hover): lockouts or Great Vault, reusing the calendar/vault tooltips and their scaling. Mode read live on each hover.
        if not clockBg._euiHoverHooked then
            clockBg._euiHoverHooked = true
            clockBg:SetScript("OnEnter", function(self)
                EBS._HVRevealMapHover()
                local mp = EBS.db and EBS.db.profile.minimap
                local mode = (mp and mp.clockHoverTooltip) or "none"
                if EllesmereUI.IS_FOREVER and mode == "vault" then mode = "none" end
                if mode == "lockouts" then
                    if EllesmereUI.InProtectedInstance() then return end
                    local entries = GetCalendarLockoutEntries()
                    if entries then ShowCalendarTooltip(self, entries) end
                elseif mode == "vault" then
                    ShowVaultTooltip(self)
                end
            end)
            clockBg:SetScript("OnLeave", function()
                HideCalendarTooltip()
                HideVaultTooltip()
            end)
        end
    else
        if clockBg then clockBg:Hide() end
        if clockFrame then clockFrame:Hide() end
        if clockTicker then clockTicker:Hide() end
    end

    LayoutIndicatorFrames(minimap, p, isCircle)

    -- Hook Blizzard mail/crafting Show/Hide to sync our custom indicator visibility
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local craftingFrame = indicator and indicator.CraftingOrderFrame
    if mailFrame and not GetFFD(mailFrame).visHooked then
        GetFFD(mailFrame).visHooked = true
        local function onMailChange()
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.enabled then return end
            SyncIndicatorVisibility()
            local s = EBS._MapShape(mp)
            LayoutIndicatorFrames(minimap, mp, s == "circle" or s == "textured_circle")
        end
        hooksecurefunc(mailFrame, "Show", onMailChange)
        hooksecurefunc(mailFrame, "Hide", onMailChange)
    end
    if craftingFrame and not GetFFD(craftingFrame).visHooked then
        GetFFD(craftingFrame).visHooked = true
        local function onCraftChange()
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.enabled then return end
            SyncIndicatorVisibility()
            local s = EBS._MapShape(mp)
            LayoutIndicatorFrames(minimap, mp, s == "circle" or s == "textured_circle")
        end
        hooksecurefunc(craftingFrame, "Show", onCraftChange)
        hooksecurefunc(craftingFrame, "Hide", onCraftChange)
    end

    -- Location bar -- none, inside the map, or boxed on the map edge
    if locationMode ~= "none" then
        if not locationBg then
            I.SetLocationBg(CreateFrame("Frame", nil, minimap, "BackdropTemplate"))
            locationBg:SetSize(120, 18)
            locationBg:SetPoint("BOTTOM", minimap, "BOTTOM", 0, -7)
            locationBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            locationBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            locationBg:RegisterEvent("ZONE_CHANGED")
            locationBg:RegisterEvent("ZONE_CHANGED_INDOORS")
            locationBg:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            locationBg:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Ellesmere: moved unchanged by the file split; multi-event zone text listener, kept as is in the combat queue migration
            locationBg:SetScript("OnEvent", function() UpdateLocation() end)
        end
        if not locationFrame then
            I.SetLocationFrame(locationBg:CreateFontString(nil, "OVERLAY"))
            locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
            locationFrame:SetTextColor(1, 1, 1, 0.9)
        end
        local lxOff = p.locationOffsetX or 0
        local lyOff = p.locationOffsetY or 0
        if locationMode == "inside" then
            locationBg:SetBackdropColor(0, 0, 0, 0)
        else
            local ar, ag, ab = EBS._EdgeBoxColor(p)
            locationBg:SetBackdropColor(ar, ag, ab, 1)
        end
        local lpt, lrel, lbx, lby = ResolveElementAnchor(p.locationPosition or "bottom", locationMode, isCircle)
        locationBg:ClearAllPoints()
        locationBg:SetPoint(lpt, GetFFD(minimap).layoutFrame or minimap, lrel, lbx + lxOff, lby + lyOff)
        -- Align the TEXT edge with the anchor (see the clock block above): inside pins it to the wrapper corner matching the map anchor, edge keeps it centered.
        locationFrame:ClearAllPoints()
        if locationMode == "inside" then
            locationFrame:SetPoint(lpt, locationBg, lpt, 0, 0)
        else
            locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
        end
        if blizz and GetFFD(minimap).blizzHeader then
            -- Stock styles: the zone text rides the top bar -- the banner's text
            -- slot under Classic WoW UI, held to the slot by both ends on WoW
            -- Forever's bar (a longer name is cut short with an ellipsis), as
            -- that client's own zone text is (offsets still apply).
            local hdr = GetFFD(minimap).blizzHeader
            locationBg:SetBackdropColor(0, 0, 0, 0)
            locationBg:ClearAllPoints()
            locationBg:SetPoint("CENTER", hdr._zoneSlot or hdr, "CENTER", lxOff, lyOff)
            locationFrame:ClearAllPoints()
            if hdr._fvBar then
                locationFrame:SetPoint("LEFT", hdr._zoneSlot, "LEFT", lxOff, lyOff)
                locationFrame:SetPoint("RIGHT", hdr._zoneSlot, "RIGHT", lxOff, lyOff)
                locationFrame:SetWordWrap(false)
            else
                locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
            end
        elseif EBS._fvSquare and EBS._fvTitleOn then
            -- Either square: the zone text rides the frame's title bar, held
            -- to the bar's band by both ends (a longer name is cut short with
            -- an ellipsis); the offsets still apply.
            local slot = GetFFD(minimap).fvTitleSlot
            locationBg:SetBackdropColor(0, 0, 0, 0)
            locationBg:ClearAllPoints()
            locationBg:SetPoint("CENTER", slot, "CENTER", lxOff, lyOff)
            locationFrame:ClearAllPoints()
            locationFrame:SetPoint("LEFT", slot, "LEFT", lxOff, lyOff)
            locationFrame:SetPoint("RIGHT", slot, "RIGHT", lxOff, lyOff)
            locationFrame:SetWordWrap(false)
        end
        ApplyMinimapFont(locationFrame, p.locationSize or 12)
        locationBg:Show()
        locationFrame:Show()
        UpdateLocation()
    else
        if locationBg then locationBg:Hide() end
        if locationFrame then locationFrame:Hide() end
    end

    -- Coordinates -- mode (never/hover/always) + anchor position around the map
    if not coordFrame then
        I.SetCoordFrame(minimap:CreateFontString(nil, "OVERLAY"))
        coordFrame:SetTextColor(1, 1, 1, 0.9)
    end
    local coordsMode, coordsPos = GetCoordsModePos(p)
    local cpAnchor = MAP_POS_ANCHORS[coordsPos] or MAP_POS_ANCHORS.topLeft
    -- Base offsets (past the heavy band under Forever Square), then the nudges.
    local cpx, cpy = EBS._FvInsideXY(coordsPos, cpAnchor[3], cpAnchor[4])
    cpx = cpx + (p and p.coordsBelowOffsetX or 0)
    cpy = cpy + (p and p.coordsBelowOffsetY or 0)
    coordFrame:ClearAllPoints()
    coordFrame:SetPoint(cpAnchor[1], GetFFD(minimap).layoutFrame or minimap, cpAnchor[2], cpx, cpy)
    ApplyMinimapFont(coordFrame, (p and p.coordsSize) or 12)
    if not coordTicker then
        I.SetCoordTicker(CreateFrame("Frame"))  -- kept for Show/Hide API
        coordTicker._ticker = nil
        coordTicker.Show = function(self)
            if self._ticker then return end
            self._ticker = C_Timer.NewTicker(0.5, function()
                UpdateCoords()
            end)
        end
        coordTicker.Hide = function(self)
            if self._ticker then self._ticker:Cancel(); self._ticker = nil end
        end
    end
    if coordsMode == "always" then
        coordFrame:Show()
        coordTicker:Show()
        UpdateCoords()
    else
        coordFrame:Hide()
        coordTicker:Hide()
    end
    -- Hover mode (coords ticker runs only while the map region is hovered) is driven by EBS._HVRevealMapHover via the shared hover-reveal hooks installed above.

    -- FPS/MS readout (Text section): same format/options as the QoL FPS counter.
    if p.showFPS then
        if not fpsBg then
            fpsBg = CreateFrame("Frame", nil, minimap)
            fpsBg:SetSize(60, 20)
            fpsBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            fpsBg:EnableMouse(false)
            local function MakeFS(size)
                local fs = fpsBg:CreateFontString(nil, "OVERLAY")
                ApplyMinimapFont(fs, size)
                fs:SetTextColor(1, 1, 1, 1)
                return fs
            end
            local DIV_W = (PP.Snap and PP.Snap(1)) or 1
            local DIV_H = 10
            local DIV_PAD = 6
            local function MakeDivider()
                local d = fpsBg:CreateTexture(nil, "OVERLAY")
                d:SetColorTexture(1, 1, 1, 1)
                d:SetSize(DIV_W, DIV_H)
                return d
            end
            -- One FontString per SEGMENT ("58 FPS"): number+suffix rasterize in a single
            -- pass, so spacing can never wobble sub-pixel like two separately snapped
            -- strings. Suffix colour rides an inline escape (Accented Text); SetFormattedText keeps formatting C-side with no template rebuilds.
            local initSz = p.fpsTextSize or 12
            local fsFps, fsWorld, fsLocal = MakeFS(initSz), MakeFS(initSz), MakeFS(initSz)
            fpsBg._fsAll = { fsFps, fsWorld, fsLocal }
            local divWorld = MakeDivider()
            local divLocal = MakeDivider()

            local floor = math.floor
            local function UpdateFPS(self)
                local mp = EBS.db and EBS.db.profile.minimap
                -- Numbers render white; the "FPS"/"MS" suffixes take the description colour while FPS/MS is checked in Accented Text (default on).
                local hex = "ffffff"
                if (mp and mp.fpsColorSuffix) ~= false then
                    local _, _, _, h = GetDescColor(mp)
                    hex = h
                end

                local fps = floor(GetFramerate() + 0.5)
                local showWorld = mp and mp.fpsShowWorldMS
                local _localMS = mp and mp.fpsShowLocalMS
                local showLocal = (_localMS == nil) and true or _localMS
                local _, _, latHome, latWorld = GetNetStats()

                fsFps:ClearAllPoints()
                fsFps:SetPoint("LEFT", self, "LEFT", 0, 0)
                fsFps:SetFormattedText("%d |cff%sFPS|r", fps, hex)
                local totalW = fsFps:GetStringWidth() or 0
                local anchor = fsFps

                if showWorld then
                    divWorld:ClearAllPoints()
                    divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                    divWorld:Show()
                    fsWorld:ClearAllPoints()
                    fsWorld:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                    fsWorld:SetFormattedText("%d |cff%sMS|r", latWorld, hex)
                    fsWorld:Show()
                    totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + (fsWorld:GetStringWidth() or 0)
                    anchor = fsWorld
                else
                    divWorld:Hide(); fsWorld:Hide()
                end

                if showLocal then
                    divLocal:ClearAllPoints()
                    divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                    divLocal:Show()
                    fsLocal:ClearAllPoints()
                    fsLocal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                    fsLocal:SetFormattedText("%d |cff%sMS|r", latHome, hex)
                    fsLocal:Show()
                    totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + (fsLocal:GetStringWidth() or 0)
                else
                    divLocal:Hide(); fsLocal:Hide()
                end

                self:SetSize(totalW + 4, ((mp and mp.fpsTextSize) or 12) + 8)
            end

            local elapsed = 0
            fpsBg:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed < (self._interval or 3) then return end
                elapsed = 0
                UpdateFPS(self)
            end)
            fpsBg._updateNow = function() elapsed = 0; UpdateFPS(fpsBg) end

            -- Hover tooltip (Show on FPS/MS Hover): same dispatch as the clock
            fpsBg:SetScript("OnEnter", function(self)
                EBS._HVRevealMapHover()
                local mp = EBS.db and EBS.db.profile.minimap
                local mode = (mp and mp.fpsHoverTooltip) or "none"
                if EllesmereUI.IS_FOREVER and mode == "vault" then mode = "none" end
                if mode == "lockouts" then
                    if EllesmereUI.InProtectedInstance() then return end
                    local entries = GetCalendarLockoutEntries()
                    if entries then ShowCalendarTooltip(self, entries) end
                elseif mode == "vault" then
                    ShowVaultTooltip(self)
                end
            end)
            fpsBg:SetScript("OnLeave", function()
                HideCalendarTooltip()
                HideVaultTooltip()
            end)
            -- With the Great Vault hover tooltip assigned, clicking the readout opens
            -- the vault. Mouse is enabled only while a hover tooltip is assigned, so this never intercepts clicks otherwise.
            fpsBg:SetScript("OnMouseUp", function(_, button)
                if button ~= "LeftButton" then return end
                local mp = EBS.db and EBS.db.profile.minimap
                if mp and mp.fpsHoverTooltip == "vault" and not EllesmereUI.IS_FOREVER then
                    EllesmereUI.ToggleGreatVault()
                end
            end)
        end
        local fsz = p.fpsTextSize or 12
        for _, fs in ipairs(fpsBg._fsAll) do
            ApplyMinimapFont(fs, fsz)
        end
        fpsBg._interval = p.fpsUpdateInterval or 3
        local fAnchor = MAP_POS_ANCHORS[p.fpsPosition or "bottomLeft"] or MAP_POS_ANCHORS.bottomLeft
        -- Past the heavy band under Forever Square.
        local fx, fy = EBS._FvInsideXY(p.fpsPosition, fAnchor[3], fAnchor[4])
        -- One evenly spaced chain at natural widths; the anchored corner is the stable edge the row breathes from.
        fpsBg:ClearAllPoints()
        fpsBg:SetPoint(fAnchor[1], GetFFD(minimap).layoutFrame or minimap, fAnchor[2],
            fx + (p.fpsOffsetX or 0), fy + (p.fpsOffsetY or 0))
        -- Mouse only while a hover tooltip is assigned, so it never blocks map clicks
        -- (WoW Forever reads a saved "vault" as none).
        fpsBg:EnableMouse((p.fpsHoverTooltip or "none") ~= "none"
            and not (EllesmereUI.IS_FOREVER and p.fpsHoverTooltip == "vault"))
        fpsBg:Show()
        fpsBg._updateNow()
    else
        if fpsBg then fpsBg:Hide() end
    end

    -- Instance Difficulty as Text: compact "20M" readout replacing the Blizzard flag
    -- (suppressed above while enabled); event-driven, zero cost while disabled. Count renders white, letter follows the description colour (as FPS/MS suffixes).
    if p.diffTextEnabled then
        if not diffTextFrame then
            diffTextFrame = CreateFrame("Frame", nil, minimap)
            local fs = minimap:CreateFontString(nil, "OVERLAY")
            fs:SetTextColor(1, 1, 1, 1)
            diffTextFrame._text = fs
            -- Difficulty ID -> suffix letter; count prefix rules alongside.
            local SUFFIX = {
                [1] = "N", [2] = "H", [23] = "M",                         -- dungeons
                [14] = "N", [15] = "H", [16] = "M", [233] = "M",          -- raids
                [3] = "N", [4] = "N", [5] = "H", [6] = "H",               -- legacy raids
                [9] = "N", [148] = "N", [173] = "N", [174] = "H",
                [7] = "LFR", [17] = "LFR", [205] = "F",
            }
            local FLEX = { [14] = true, [15] = true, [233] = true }       -- size = current group
            local NOCOUNT = { [205] = true }                              -- letter only
            local TW   = { [24] = true, [33] = true, [151] = true }
            local EVT  = { [18] = true, [19] = true, [30] = true }
            local PVP  = { [25] = true, [29] = true, [32] = true, [34] = true, [45] = true }
            local SCEN = { [12] = "S", [38] = "S", [11] = "HS", [39] = "HS", [40] = "MS" }
            local GARRISON = {
                [1152] = true, [1153] = true, [1154] = true, [1158] = true,
                [1159] = true, [1160] = true, [1330] = true, [1331] = true,
            }
            -- Difficulty (Reactive): letter colours by tier (normal/scenarios bronze like delves, heroic blue, mythic purple, keystones legendary orange).
            local REACTIVE_HEX = {
                N = "c69b6d", H = "0070dd", M = "a335ee",
                S = "c69b6d", HS = "0070dd", MS = "a335ee",
                LFR = "9d9d9d", F = "9d9d9d",
                TW = "00ccff", EVT = "ffffff", PvP = "ffffff",
            }
            diffTextFrame._update = function(self)
                local out = self._text
                local mp2 = EBS.db and EBS.db.profile.minimap
                if not (mp2 and mp2.diffTextEnabled) then out:SetText("") return end
                local _, instanceType, diffID, _, maxPlayers, _, _, instanceID, groupSize = GetInstanceInfo()
                if not diffID or diffID == 0 or instanceType == "none" or GARRISON[instanceID] then
                    out:SetText("")
                    return
                end
                -- Letter colour follows Accented Text: Reactive = tier colour, plain Difficulty = flat accent/custom, neither = white; Reactive wins.
                local reactive = mp2.diffTextReactive
                local hex = "ffffff"
                if not reactive and mp2.diffTextAccent then
                    local _, _, _, h = GetDescColor(mp2)
                    hex = h
                end
                if diffID == 8 then
                    -- Active keystone: key level after the colored M+
                    if reactive then hex = "ff8000" end
                    local lvl = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
                        and C_ChallengeMode.GetActiveKeystoneInfo()
                    out:SetFormattedText("|cff%sM+|r%s", hex, (lvl and lvl > 0) and lvl or "")
                    return
                end
                if diffID == 208 then
                    -- Delve: tier number from the scenario header widget
                    if reactive then hex = "c69b6d" end
                    local tier
                    local ok, info = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, 6183)
                    if ok and info and info.tierText then
                        tier = tostring(info.tierText):match("%d+")
                    end
                    out:SetFormattedText("|cff%sT|r%s", hex, tier or "")
                    return
                end
                local letter
                if TW[diffID] then letter = "TW"
                elseif EVT[diffID] then letter = "EVT"
                elseif PVP[diffID] then letter = "PvP"
                elseif SCEN[diffID] then letter = SCEN[diffID]
                else letter = SUFFIX[diffID] end
                if not letter then out:SetText("") return end
                if reactive then hex = REACTIVE_HEX[letter] or "ffffff" end
                local count
                if SUFFIX[diffID] and not NOCOUNT[diffID] then
                    count = FLEX[diffID] and groupSize or maxPlayers
                end
                out:SetFormattedText("%s|cff%s%s|r", (count and count > 0) and count or "", hex, letter)
            end
            diffTextFrame:SetScript("OnEvent", function(self) self._update(self) end)
        end
        local fs = diffTextFrame._text
        ApplyMinimapFont(fs, p.diffTextSize or 12)
        local a = MAP_POS_ANCHORS[p.diffTextPosition or "topLeft"] or MAP_POS_ANCHORS.topLeft
        -- Past the heavy band under Forever Square.
        local dx, dy = EBS._FvInsideXY(p.diffTextPosition, a[3], a[4])
        fs:ClearAllPoints()
        fs:SetPoint(a[1], GetFFD(minimap).layoutFrame or minimap, a[2], dx + (p.diffTextOffsetX or 0), dy + (p.diffTextOffsetY or 0))
        fs:Show()
        diffTextFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        diffTextFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        diffTextFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
        diffTextFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        diffTextFrame:RegisterEvent("CHALLENGE_MODE_START")
        diffTextFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        diffTextFrame:RegisterEvent("CHALLENGE_MODE_RESET")
        diffTextFrame._update(diffTextFrame)
    elseif diffTextFrame then
        diffTextFrame:UnregisterAllEvents()
        diffTextFrame._text:Hide()
    end

    -- Mousewheel zoom lives on the square overlay (the Minimap's own hit region is
    -- circular, leaving the square skin's corners wheel-dead); Scroll to Zoom off leaves both wheel-disabled so the wheel falls through to camera zoom.
    do
        local blocker = GetFFD(minimap).pingBlocker
        if blocker then blocker:EnableMouseWheel(p.scrollZoom and true or false) end
        minimap:EnableMouseWheel(false)
    end

    if not GetFFD(minimap).active then
        local saved = p.savedZoom or 0
        if saved >= 0 and saved <= minimap:GetZoomLevels() then
            minimap:SetZoom(saved)
        end
    end

    -- Re-arm (or disarm) the Auto Zoom Reset timer on every apply, so
    -- enabling it or changing the seconds slider in the options takes
    -- effect immediately.
    RestartZoomResetTimer()

    -- Position: only set on first activation; after that, unlock mode owns positioning.
    if not GetFFD(minimap).active then
        minimap:ClearAllPoints()
        if p.position then
            local px, py = p.position.x, p.position.y
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and px and py then
                local es = minimap:GetEffectiveScale()
                local isCenterAnchor = (p.position.point == "CENTER")
                    and (p.position.relPoint == "CENTER" or p.position.relPoint == nil)
                if isCenterAnchor and PPa.SnapCenterForDim then
                    px = PPa.SnapCenterForDim(px, minimap:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, minimap:GetHeight() or 0, es)
                elseif PPa.SnapForES then
                    px = PPa.SnapForES(px, es)
                    py = PPa.SnapForES(py, es)
                end
            end
            minimap:SetPoint(p.position.point, UIParent, p.position.relPoint, px, py)
        else
            minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
        end
    end

    -- Mark module as active so persistent hooks know they can fire
    GetFFD(minimap).active = true

    ApplyOmniumFolio()
    EBS._ApplyAddonCompartment()
    EBS._ApplyExternalEventButton()
end

-- Blizzard's external event button (a link to an event outside the game,
-- shown and hidden by Blizzard while one runs; a child of MinimapBackdrop,
-- WoW Forever only) stays on the map with the backdrop. Blizzard Style and
-- the WoW Forever look give it the stock spot on the ring (its centre 101.5
-- left of and 0.5 above the map centre at the stock 198px map, scaled with
-- the map); the other looks the map's top-left corner at the folio's scale.
-- Above the ping blocker so it takes the mouse. Method calls on Blizzard's
-- plain button only, every apply pass (Blizzard anchors it once, at load).
function EBS._ApplyExternalEventButton()
    local backdrop = _G.MinimapBackdrop
    local btn = backdrop and backdrop.ExternalEventURLButton
    if not (btn and Minimap) then return end
    btn:ClearAllPoints()
    if EBS._MinimapBlizz() and not EBS._MinimapClassic() then
        btn:SetScale(1)
        local s = (Minimap:GetWidth() or 198) / 198
        btn:SetPoint("CENTER", Minimap, "CENTER", -101.5 * s, 0.5 * s)
    else
        -- Forever Square steps it in past the heavy band, as the texts inside the map.
        local x, y = EBS._FvInsideXY("top", 2, -2)
        btn:SetScale(0.75)
        btn:SetPoint("TOPLEFT", GetFFD(Minimap).layoutFrame or Minimap, "TOPLEFT", x, y)
    end
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 11)
end

I.SetApplyMinimap(ApplyMinimap)
I.ApplyMinimap = ApplyMinimap
I.broken = false
