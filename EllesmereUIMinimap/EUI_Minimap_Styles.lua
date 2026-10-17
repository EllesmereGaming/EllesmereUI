if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Styles.lua
--
--  The addon compartment and the stock styles (Blizzard Style, Classic WoW
--  UI).
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local ADDON_NAME, EBS, GetFFD, PP = I.ADDON_NAME, I.EBS, I.GetFFD, I.PP
local GetElementModes, _customIndicators = I.GetElementModes, I._customIndicators

-------------------------------------------------------------------------------
--  Addon Compartment
--  Blizzard's addon-compartment button is a child of MinimapCluster, which this
--  module alpha-zeroes and mouse-disables -- so it has to be reparented onto our
--  own Minimap to be visible at all. The old code parked it on a hidden frame
--  unconditionally, which is why hideAddonCompartment (default false) had no
--  effect and the compartment was simply gone with no way to get it back.
--  Handled exactly like the Omnium Folio: plain (non-secure) Blizzard button,
--  so SetParent/SetPoint/SetScale are safe, and the same re-assert hooks keep
--  Blizzard's own relayout from dragging it back into the hidden cluster.
--  Namespace-scoped (EBS fields, not locals).
-------------------------------------------------------------------------------
function EBS._ParkAddonCompartment(btn)
    if not EBS._hiddenFrame then
        EBS._hiddenFrame = CreateFrame("Frame")
        EBS._hiddenFrame:Hide()
    end
    EBS._compartmentApplying = true
    if btn:GetParent() ~= EBS._hiddenFrame then
        GetFFD(btn).origParent = GetFFD(btn).origParent or btn:GetParent()
        btn:SetParent(EBS._hiddenFrame)
    end
    EBS._compartmentApplying = false
end

function EBS._PositionAddonCompartment(btn)
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not mp or not Minimap then return end
    EBS._compartmentApplying = true
    if btn:GetParent() ~= Minimap then btn:SetParent(Minimap) end
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    btn:SetScale(mp.addonCompartmentScale or 0.9)
    btn:ClearAllPoints()
    -- Anchor the button's chosen corner to the minimap's same corner; X/Y nudge
    -- from there (positive X = right, positive Y = up), same as the folio.
    local corner = mp.addonCompartmentCorner or "TOPRIGHT"
    local placed = false
    if EBS._MinimapBlizz() then
        -- Stock styles: the stock spot is under the calendar (the button's
        -- top-left to the calendar's bottom-left; calendar hidden = right of the
        -- top bar); any other corner is that corner's diagonal on the compass
        -- ring. The nudges still apply.
        local nx, ny = mp.addonCompartmentX or 0, mp.addonCompartmentY or 0
        if corner == "TOPRIGHT" then
            local cal = _customIndicators.calendar
            local hdr = GetFFD(Minimap).blizzHeader
            if cal and cal:IsShown() and hdr and hdr._fvBar then
                -- WoW Forever's header: centred under the calendar, 1 up.
                btn:SetPoint("TOP", cal, "BOTTOM", nx, 1 + ny)
                placed = true
            elseif cal and cal:IsShown() then
                btn:SetPoint("TOPLEFT", cal, "BOTTOMLEFT", nx, ny)
                placed = true
            elseif hdr then
                btn:SetPoint("TOPLEFT", hdr, "TOPRIGHT", 1 + nx, ny)
                placed = true
            end
        else
            local mapW = Minimap:GetWidth() or (mp.mapSize or 140)
            local r = (mapW / 2 + 5 * (mapW / 198)) / (btn:GetScale() or 1)
            local dx = (corner == "BOTTOMLEFT" or corner == "TOPLEFT") and -0.7071 or 0.7071
            local dy = (corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT") and -0.7071 or 0.7071
            btn:SetPoint("CENTER", Minimap, "CENTER", r * dx + nx, r * dy + ny)
            placed = true
        end
    end
    if not placed then
        btn:SetPoint(corner, GetFFD(Minimap).layoutFrame or Minimap, corner, mp.addonCompartmentX or 0, mp.addonCompartmentY or 0)
    end
    -- The cluster's alpha/mouse state does not follow the reparent, and the
    -- pre-fix sessions left it parked on a hidden frame -- re-assert both.
    btn:SetAlpha(1)
    btn:EnableMouse(true)
    EBS._compartmentApplying = false
end

function EBS._ApplyAddonCompartment()
    local btn = _G.AddonCompartmentFrame
    if not btn then return end
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not mp then return end

    -- One-time persistent hooks, mirroring the folio's: Blizzard re-anchors and
    -- reparents this button on edit-mode relayouts and cluster updates, often
    -- without a Show(), which would otherwise drop it back into the alpha-0
    -- cluster until /reload.
    if not EBS._compartmentHooked then
        EBS._compartmentHooked = true
        local function reassert(self)
            if EBS._compartmentApplying then return end
            local m = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            if not m then return end
            if m.hideAddonCompartment then
                EBS._ParkAddonCompartment(self)
            else
                EBS._PositionAddonCompartment(self)
            end
        end
        hooksecurefunc(btn, "Show", reassert)
        hooksecurefunc(btn, "SetParent", reassert)
        hooksecurefunc(btn, "SetPoint", reassert)
        hooksecurefunc(btn, "SetScale", reassert)
        -- Hovering the compartment counts as hovering the map region, so the
        -- hover-reveal elements stay alive while the cursor is on it.
        btn:HookScript("OnEnter", function()
            if EBS._HVRevealMapHover then EBS._HVRevealMapHover() end
        end)
    end

    if mp.hideAddonCompartment then
        EBS._ParkAddonCompartment(btn)
        return
    end
    EBS._PositionAddonCompartment(btn)
    -- Blizzard shows/hides this button itself from the number of addons that
    -- registered a compartment entry -- only nudge it when at least one did, so
    -- an empty compartment is never forced on screen.
    if not btn:IsShown() then
        local reg = btn.registeredAddons
        if reg and #reg > 0 then btn:Show() end
    end
end

-- The square frames' crop masks (Media/crop, made by .tools/minimap-crop/
-- make_crop_masks.py): minimap-crop-<r>.tga cuts r of its 256 rows off the
-- top and the bottom, for r in CROP_MASK_MIN..CROP_MASK_MAX (both frames'
-- crops over the Map Size slider).
EBS.CROP_MASK_MIN, EBS.CROP_MASK_MAX = 5, 31
local cropMasks = {}
-- The strip cropped off the top and bottom of the square canvas, and the
-- canvas mask that cuts it: Rectangular's 4:3 (32/256 of the canvas each), or,
-- under a square frame on the Forever client with its title bar, half the
-- bar's extra height each, so the whole frame, bar included, is a square (the
-- nearest crop mask, and the crop that mask cuts). 0 keeps the canvas whole.
EBS._MapCrop = function(p, mapSize)
    if not p then return 0 end
    if EBS._MapShape(p) == "rectangular" then
        return mapSize * 32 / 256, "Interface\\AddOns\\EllesmereUIMinimap\\Media\\minimap_rectangular-crop-mask.tga"
    end
    if EBS._MinimapFvSquare() then
        local _, locationMode = GetElementModes(p)
        if locationMode ~= "none" then
            local r = math.floor((EBS._SqTitle() - EBS._SqOut()) / 2 * 256 / mapSize + 0.5)
            r = math.max(EBS.CROP_MASK_MIN, math.min(EBS.CROP_MASK_MAX, r))
            local mask = cropMasks[r]
            if not mask then
                mask = "Interface\\AddOns\\EllesmereUIMinimap\\Media\\crop\\minimap-crop-" .. r .. ".tga"
                cropMasks[r] = mask
            end
            return r * mapSize / 256, mask
        end
    end
    return 0
end

-- The mask that crops rectangular mode's square canvas covers the terrain only -- the
-- engine keeps drawing unit blips across the whole canvas, and the one thing that
-- confines the native render is the minimap's PARENT rect (ordinary child frames and
-- textures are not clipped by it, so our border and buttons still draw outside).
-- Parenting the canvas to the layout frame of the visible size is what crops the
-- blips, for every crop.
local function DesiredMapParent(minimap)
    local p = EBS.db and EBS.db.profile.minimap
    if p and EBS._MapCrop(p, p.mapSize or 140) > 0 then
        return GetFFD(minimap).layoutFrame or UIParent
    end
    return UIParent
end

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style): Blizzard Style and Classic WoW UI.
--  Both force the round map, drop the EUI border and put the zoom buttons,
--  indicators and button row where a stock layout puts them; only the art
--  differs. Blizzard Style wears the 12.1 kit: Blizzard's compass ring (its
--  own texture, so Rotate Minimap keeps turning it) sized onto the map and a
--  header of ours in the stock NineSlice kit. Classic WoW UI wears the
--  vanilla texture files: the UI-Minimap-Border ring and zone banner on
--  frames of ours, the vanilla zoom buttons, the ring-border indicators.
--  Every EUI feature keeps working. Reload-gated per-profile flags, read only
--  on apply passes; all of this is skipped while both are off.
-------------------------------------------------------------------------------
-- The style this module RENDERS this session: "eui" | "blizzard" | "classic".
-- Read from the profile once (first call with a profile present) and latched
-- for the session: a live profile switch never flips the look under the
-- one-time chrome setup; the profile system prompts for a reload instead.
EBS._MinimapStyle = function()
    local v = EBS._styleLatch
    if v == nil then
        local m = EBS.db and EBS.db.profile and EBS.db.profile.minimap
        if not m then return "eui" end
        v = (m.useClassicStyle and "classic") or (m.useBlizzardStyle and "blizzard") or "eui"
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        local fv = v == "blizzard" and EllesmereUI.IS_FOREVER == true
            and m.useForeverStyle == true
        -- Its Border Style Forever Square (where the heavy bronze art
        -- exists): the EllesmereUI look's square map in that frame, so the
        -- module renders "eui" and every stock site stands down, the
        -- variant's ring pieces with them. Forever Circle ("circle") is the
        -- variant as it is; anything else is Forever Square, the default.
        EBS._fvSquare = fv and m.foreverBorder ~= "circle" and EllesmereUI.ForeverHeavyOK() or false
        -- Plain Blizzard Style on the Forever client has a Border Style of
        -- its own (blizzBorder): Square, the default there, is the same
        -- square map in the slim bronze line (EBS._sqSlim) instead of the
        -- heavy frame; "circle" is the variant's Forever Circle exactly
        -- (EBS._bzCircle: the variant's pieces render, while the published
        -- getters still name Blizzard Style). EBS._fvSquare reads true under
        -- either square.
        EBS._sqSlim = v == "blizzard" and not fv and EllesmereUI.IS_FOREVER == true
            and m.blizzBorder ~= "circle" and EllesmereUI.ForeverBorderOK() or false
        EBS._bzCircle = v == "blizzard" and not fv and EllesmereUI.IS_FOREVER == true and not EBS._sqSlim
        if EBS._bzCircle then fv = true end
        if EBS._sqSlim then EBS._fvSquare = true end
        if EBS._fvSquare then v, fv = "eui", false end
        EBS._foreverLatch = fv
        EBS._styleLatch = v
    end
    return v
end
-- Stock-art mode: true for both stock styles (the geometry, gating and
-- placement they share).
EBS._MinimapBlizz = function() return EBS._MinimapStyle() ~= "eui" end
EBS._MinimapClassic = function() return EBS._MinimapStyle() == "classic" end
-- WoW Forever variant: the style still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces, Blizzard Style's
-- Circle on the Forever client included (it draws the variant's round map
-- exactly). False off Forever, and under either square.
EBS._MinimapForever = function()
    if EBS._styleLatch == nil then EBS._MinimapStyle() end
    return EBS._foreverLatch == true
end
-- A square frame on the Forever client, latched above: the WoW Forever look's
-- Forever Square or Blizzard Style's Square (EBS._sqSlim tells them apart).
-- False under every other look and off Forever.
EBS._MinimapFvSquare = function()
    if EBS._styleLatch == nil then EBS._MinimapStyle() end
    return EBS._fvSquare == true
end
-- The shape the map renders: the stock styles' round map, Forever Square's
-- square, else the stored Shape (read live).
EBS._MapShape = function(p)
    if EBS._MinimapBlizz() then return "circle" end
    if EBS._MinimapFvSquare() then return "square" end
    return (p and p.shape) or "square"
end
-- SetAtlas for a stock-look texture: EllesmereUI.StockAtlas (retail art
-- where the Forever client swaps the name), native under the WoW Forever
-- look. Plain SetAtlas on retail.
EBS._StockAtlas = function(tex, name, ...)
    if EBS._MinimapForever() then return tex:SetAtlas(name, ...) end
    return EllesmereUI.StockAtlas(tex, name, ...)
end
-- Published on the module ns for the Style page and the profile-switch check,
-- which compare the look the profile flags name: under either square that is
-- still the look its flags name (Blizzard Style, or Blizzard Style plus its
-- WoW Forever variant), whatever the module renders.
EllesmereUI._ModuleNS[ADDON_NAME].MinimapBlizz = EBS._MinimapBlizz
EllesmereUI._ModuleNS[ADDON_NAME].MinimapStyle = function()
    local v = EBS._MinimapStyle()
    if EBS._fvSquare then return "blizzard" end
    return v
end
EllesmereUI._ModuleNS[ADDON_NAME].MinimapForever = function()
    return (EBS._MinimapForever() and not EBS._bzCircle) or (EBS._MinimapFvSquare() and not EBS._sqSlim)
end
-- The options page: a square frame renders this session, and the shape the
-- map renders.
EllesmereUI._ModuleNS[ADDON_NAME].MinimapFvSquare = EBS._MinimapFvSquare
EllesmereUI._ModuleNS[ADDON_NAME].MinimapShape = function()
    return EBS._MapShape(EBS.db and EBS.db.profile and EBS.db.profile.minimap)
end
-- Profiles (ProfileChangesStyle's `extra`, handed the incoming minimap
-- table): true when that profile would render another square (or none) than
-- the one latched this session (the latch above, read off `m`), so the
-- switch asks for a reload. A stored profile keeps no default values, so an
-- unset Border Style is the square there too.
EllesmereUI._ModuleNS[ADDON_NAME].MinimapFvBorderChanged = function(m)
    local sq = nil
    if type(m) == "table" and not m.useClassicStyle and m.useBlizzardStyle
       and EllesmereUI.IS_FOREVER == true then
        if m.useForeverStyle == true then
            if m.foreverBorder ~= "circle" and EllesmereUI.ForeverHeavyOK() then sq = "heavy" end
        elseif m.blizzBorder ~= "circle" and EllesmereUI.ForeverBorderOK() then
            sq = "slim"
        end
    end
    local cur = EBS._MinimapFvSquare() and (EBS._sqSlim and "slim" or "heavy") or nil
    return sq ~= cur
end

-- Zoom button anchor, shared by the apply pass and the SetPoint re-assert
-- hooks: EUI stacks them at the bottom-right corner; the stock styles place
-- them where their stock map does (offsets scale with the map size).
EBS._ZoomAnchor = function(btn, isIn, minimap)
    local p = EBS.db and EBS.db.profile.minimap
    btn:ClearAllPoints()
    local style = p and EBS._MinimapStyle() or "eui"
    if style == "classic" then
        -- Vanilla: MinimapZoomIn CENTER 69,-37 and MinimapZoomOut CENTER 43,-65
        -- of the backdrop centred on the 140px map.
        local s = (p.mapSize or 140) / 140
        if isIn then
            btn:SetPoint("CENTER", minimap, "CENTER", 69 * s, -37 * s)
        else
            btn:SetPoint("CENTER", minimap, "CENTER", 43 * s, -65 * s)
        end
    elseif style == "blizzard" then
        local s = (p.mapSize or 140) / 198
        if isIn then
            btn:SetPoint("CENTER", minimap, "CENTER", 88 * s, -68 * s)
        else
            btn:SetPoint("CENTER", minimap, "CENTER", 72 * s, -84 * s)
        end
    else
        -- Forever Square steps them in past the heavy band and its shade, 6px
        -- from the edges as the texts inside the map sit (EBS._FvInsideXY);
        -- the slim square's line leaves them where they are.
        local x, y = -2, isIn and 20 or 2
        if EBS._fvSquare and not EBS._sqSlim then x, y = -6, isIn and 24 or 6 end
        btn:SetPoint("BOTTOMRIGHT", GetFFD(minimap).layoutFrame or minimap, "BOTTOMRIGHT", x, y)
    end
end

-- A button's spot on the ring round the map (stock-style button row):
-- radius r, angle t (radians, 0 = right, counter-clockwise), snapped to the
-- physical grid at the row's effective scale.
EBS._ArcPoint = function(btn, minimap, r, t, es)
    btn:SetPoint("CENTER", minimap, "CENTER",
        PP.SnapForES(r * math.cos(t), es), PP.SnapForES(r * math.sin(t), es))
end

-- Compass ring + top border bar. The compass lives on MinimapBackdrop, the
-- Minimap's own child, which stays put and is only sized onto the map
-- (method calls, no keys written). The bar is a frame of our own wearing the
-- stock header kit: the cluster's BorderTop is a NineSlice with this layout,
-- and moving Blizzard's frame here would drag the cluster children anchored
-- to it (tracking, indicator frame, clock) along and inflate the cluster's
-- Edit Mode layout rect. Idempotent per apply pass.
-- On WoW Forever the same compass atlas draws that client's square ring, and
-- Blizzard re-sizes the backdrop, the compass and its rotate-mode underlay to
-- the atlas (unscaled) on every Rotate Minimap change: there the backdrop and
-- compass are pinned by two corners round the map centre, which no SetSize
-- can undo, and the underlay follows the compass rect.
EBS._ApplyBlizzMinimapChrome = function(minimap, mapSize)
    local s = mapSize / 198
    local d = GetFFD(minimap)
    local compass = _G.MinimapCompassTexture
    -- WoW Forever look only: plain Blizzard Style keeps its own geometry everywhere.
    local fv = EBS._MinimapForever() == true
    local hw, hh, rh = nil, nil, nil
    if fv then
        local rw
        rw, rh = EBS._ForeverRingSize()
        hw, hh = rw * s / 2, rh * s / 2
    end
    -- MinimapBackdrop is the Minimap's own child frame carrying the compass ring
    -- (and the landing page button, which this module positions itself).
    local backdrop = _G.MinimapBackdrop
    if backdrop and backdrop ~= minimap then
        if backdrop:GetParent() ~= minimap then backdrop:SetParent(minimap) end
        backdrop:ClearAllPoints()
        if fv then
            backdrop:SetPoint("TOPLEFT", minimap, "CENTER", -hw, hh)
            backdrop:SetPoint("BOTTOMRIGHT", minimap, "CENTER", hw, -hh)
        else
            backdrop:SetPoint("CENTER", minimap, "CENTER", 0, 0)
            backdrop:SetSize(215 * s, 226 * s)
        end
        backdrop:SetFrameLevel(minimap:GetFrameLevel() + 3)
        backdrop:SetAlpha(1)
        backdrop:Show()
    end
    if compass then
        compass:ClearAllPoints()
        if fv then
            compass:SetPoint("TOPLEFT", minimap, "CENTER", -hw, hh)
            compass:SetPoint("BOTTOMRIGHT", minimap, "CENTER", hw, -hh)
            -- Rotate mode: the fixed circle under the turning chevron (a
            -- Forever-only region; Blizzard shows and hides it itself).
            local underlay = _G.MinimapCompassTextureUnderlay
            if underlay then
                underlay:ClearAllPoints()
                underlay:SetAllPoints(compass)
            end
        else
            compass:SetPoint("CENTER", minimap, "CENTER", 0, 0)
            compass:SetSize(215 * s, 226 * s)
        end
        compass:SetAlpha(1)
        compass:Show()
    end
    -- Top bar: the stock 175x16 kit, bottom edge 24px above the map's top,
    -- centred 5px right of the map centre in the stock cluster; scaled, so
    -- the offsets stay unscaled. WoW Forever's bar is its header button art
    -- (152x23) over the map's centre: its taller ring grows the stock
    -- container, which lifts the bar to (ring height / 2 - 92) above the map
    -- (34.5 for the 253px ring), clear of the north chevron. The zone text
    -- rides that bar's slot, 8 in from each end (the clock, Blizzard's tenant
    -- of its right end, stays the module's own element); a client without the
    -- art keeps the stock kit 3 higher.
    local header = d.blizzHeader
    if not header then
        header = CreateFrame("Frame", nil, minimap)
        header:EnableMouse(false)
        local bar = fv and C_Texture.GetAtlasInfo(EBS.FV_HEADER_ATLAS)
        if bar then
            local tex = header:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(header)
            tex:SetAtlas(EBS.FV_HEADER_ATLAS)
            header:SetSize(bar.width, bar.height)
            local slot = CreateFrame("Frame", nil, header)
            slot:EnableMouse(false)
            slot:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -1)
            slot:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, -1)
            header._zoneSlot = slot
            header._fvBar = true
        else
            header:SetSize(175, 16)
            if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
                pcall(NineSliceUtil.ApplyLayoutByName, header, "UniqueCornersLayout", "ui-hud-minimap-button")
            end
        end
        d.blizzHeader = header
    end
    local barY = 24
    if header._fvBar then
        barY = rh / 2 - 92
    elseif fv then
        barY = rh / 2 - 89
    end
    header:ClearAllPoints()
    header:SetPoint("BOTTOM", minimap, "TOP", header._fvBar and 0 or 5, barY)
    header:SetScale(s)
    header:SetFrameLevel(minimap:GetFrameLevel() + 4)
    header:Show()
end

-- WoW Forever's compass atlas size (a 253px square there), read once.
EBS._ForeverRingSize = function()
    if not EBS._fvRingW then
        local info = C_Texture.GetAtlasInfo("UI-HUD-Minimap-Frame")
        EBS._fvRingW = info and info.width or 253
        EBS._fvRingH = info and info.height or 253
    end
    return EBS._fvRingW, EBS._fvRingH
end

-- WoW Forever look, Border Style Forever Square: the EllesmereUI look's square
-- map wears the bronze frame of Forever's own windows (EllesmereUI.
-- ForeverHeavy at the window scale, as the chat and Damage Meters windows
-- wear it) in place of the EllesmereUI border. The rim's outer edge sits
-- EBS.FV_SQUARE_OUT past the map's edge, so the map's square corners lie
-- inside the rim's corner cuts; the map keeps its footprint (unlock mode)
-- and the elements inside it step in past the rim (EBS._FvInsideXY). While
-- the zone text shows, the frame keeps the windows' title bar over the map
-- (the rim's outer edge EBS.FV_SQUARE_TITLE above the map's top, the bar's
-- divider on that edge) and the zone text rides the bar's band (fvTitleSlot,
-- the band between the side rims); Zone Text Style None closes the frame at
-- the map's top. While the bar shows, the map loses half the bar's extra
-- height off its top and bottom each (EBS._MapCrop), so the whole frame, bar
-- included, is a square; the frame and its pieces anchor to the map as it
-- shows (the layout frame). The rows hang from the frame's outer edge (fvOuter), clear
-- of the rim's outer shadow by EBS.FV_ROW_AIR. Two levels over the map (the
-- housing overlay under it), under the text boxes and the buttons; every
-- piece mouse-transparent. Built once; re-anchored every pass, as the border
-- host is (the map's deferred reparent). A queue eye Action Bars parks off
-- the frame's corner follows a resize.
-- Blizzard Style's Square on the Forever client (EBS._sqSlim) is the same
-- map and layout in the slim bronze line (EllesmereUI.ForeverBorder, the
-- shipped art): the line's outer edge EBS.FV_SLIM_OUT past the map's sides
-- and bottom, so the map's square corners lie under the line's corner cuts,
-- and its title bar drawn in the line too: the line round the map and a
-- band above it (black at EBS.FV_SLIM_BAND, the line's outer edge
-- EBS.FV_SLIM_TITLE above the map's top) with the line's divider on the
-- map's top.
EBS.FV_SQUARE_OUT = 3
EBS.FV_SQUARE_TITLE = 27
EBS.FV_SLIM_OUT = EllesmereUI.FOREVER_BORDER.fill
EBS.FV_SLIM_TITLE = 24
EBS.FV_SLIM_BAND = 0.75
-- The square frame's outer edge past the map's sides and bottom (and its
-- top without the title bar), and past its top with the title bar.
function EBS._SqOut() return EBS._sqSlim and EBS.FV_SLIM_OUT or EBS.FV_SQUARE_OUT end
function EBS._SqTitle() return EBS._sqSlim and EBS.FV_SLIM_TITLE or EBS.FV_SQUARE_TITLE end
-- Rows outside the frame: the rim's outer shadow and 2px more past its outer
-- edge (Distance from Map adds to it), and between two ring buttons' rings
-- (Icon Spacing adds to it).
EBS.FV_ROW_AIR = 4
EBS.FV_RING_GAP = 3
EBS._ApplyForeverSquare = function(minimap)
    local d = GetFFD(minimap)
    local slim = EBS._sqSlim
    local frame = d.fvFrame
    if not frame then
        frame = CreateFrame("Frame", nil, minimap)
        frame:EnableMouse(false)
        if slim then
            local band = frame:CreateTexture(nil, "BACKGROUND")
            band:SetColorTexture(0, 0, 0, EBS.FV_SLIM_BAND)
            d.fvSlimBand = band
            d.fvSlimRing = EllesmereUI.ForeverBorder(frame, "ARTWORK")
            d.fvSlimRule = EllesmereUI.ForeverBorderDivider(frame, "ARTWORK", 1)
        else
            frame:SetScale(EllesmereUI.FOREVER_HEAVY.k)
            d.fvHeavyRim = EllesmereUI.ForeverHeavy(frame, "ARTWORK")
        end
        d.fvFrame = frame
        local slot = CreateFrame("Frame", nil, minimap)
        slot:EnableMouse(false)
        d.fvTitleSlot = slot
        local outer = CreateFrame("Frame", nil, minimap)
        outer:EnableMouse(false)
        d.fvOuter = outer
    end
    local _, locationMode = GetElementModes(EBS.db.profile.minimap)
    local title = locationMode ~= "none"
    EBS._fvTitleOn = title
    -- The map as it shows: the layout frame once the title bar crops the canvas.
    local vis = d.layoutFrame or minimap
    frame:SetFrameLevel(minimap:GetFrameLevel() + 2)
    frame:ClearAllPoints()
    frame:SetAllPoints(vis)
    local o = EBS._SqOut()
    local top = title and EBS._SqTitle() or o
    if slim then
        EllesmereUI.ForeverBorderSeat(d.fvSlimRing, vis, nil, -o, top, o, -o)
        local band, rule = d.fvSlimBand, d.fvSlimRule
        band:SetShown(title)
        rule:SetShown(title)
        if title then
            -- The band from FOREVER_BORDER.fill inside the line (its corners
            -- inside the corner cuts) down to the map's top; the divider
            -- between the side lines' inner edges, its bottom on the map's top.
            local B = EllesmereUI.FOREVER_BORDER
            band:ClearAllPoints()
            band:SetPoint("TOPLEFT", vis, "TOPLEFT", B.fill - o, top - B.fill)
            band:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", o - B.fill, 0)
            rule:ClearAllPoints()
            rule:SetPoint("BOTTOMLEFT", vis, "TOPLEFT", B.line - o, 0)
            rule:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", o - B.line, 0)
        end
    else
        EllesmereUI.ForeverHeavyTitle(d.fvHeavyRim, title)
        EllesmereUI.ForeverHeavySeat(d.fvHeavyRim, vis, nil, -o, top, o, -o)
    end
    frame:Show()
    d.fvOuter:ClearAllPoints()
    d.fvOuter:SetPoint("TOPLEFT", vis, "TOPLEFT", -o, top)
    d.fvOuter:SetPoint("BOTTOMRIGHT", vis, "BOTTOMRIGHT", o, -o)
    d.fvTitleSlot:ClearAllPoints()
    if slim then
        -- The band between the side lines (2px of air past the map's sides),
        -- from 1px under the top line's inner shadow down to 5 above the
        -- map's top, clear of the divider's line and outer shadow.
        d.fvTitleSlot:SetPoint("TOPLEFT", vis, "TOPLEFT", 2, top - 4)
        d.fvTitleSlot:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", -2, 5)
    else
        -- The band between the side rims (their inner edges 3 inside the map's
        -- sides), 2px of air at each end.
        local bar = EllesmereUI.FOREVER_HEAVY.title
        d.fvTitleSlot:SetPoint("TOPLEFT", vis, "TOPLEFT", o + 2, top - bar.band)
        d.fvTitleSlot:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", -o - 2, top - bar.bandEnd)
    end
    local ab = EllesmereUI._ModuleNS.EllesmereUIActionBars
    if ab then ab.AB_ForeverEyeRelayout() end
end

-- WoW Forever: the queue eye's stock spot on the ring (Blizzard's Forever
-- layout: 68 left of and 68 below the 198px map's centre, scaled with the
-- map), for Action Bars to park the eye on. The map frame and the offsets;
-- nil unless the map wears Blizzard's ring on that client (Blizzard Style or
-- its WoW Forever variant) or a square frame (the variant's Forever Square,
-- Blizzard Style's slim square), whose eye sits diagonally off the frame's
-- bottom-left corner (the 45px eye's top-right corner on the frame's outer
-- corner), clear of the rows the EllesmereUI layout hangs along the edges.
EBS._QueueEyeSpot = function()
    if not EllesmereUI.IS_FOREVER then return nil end
    local sq = EBS._MinimapFvSquare()
    if not sq and EBS._MinimapStyle() ~= "blizzard" then return nil end
    local size = EBS.db.profile.minimap.mapSize or 140
    if sq then
        local o = size / 2 + EBS._SqOut() + 22.5
        -- The frame's bottom rises with the map's crop.
        return Minimap, -o, -(o - EBS._MapCrop(EBS.db.profile.minimap, size))
    end
    local s = size / 198
    return Minimap, -68 * s, -68 * s
end
EllesmereUI._ModuleNS[ADDON_NAME].MinimapQueueEyeSpot = EBS._QueueEyeSpot

-- WoW Forever look: the day/night orb Blizzard hangs on the ring's upper
-- right (its own sits in the cluster this module hides). Stock geometry: a
-- 42px bronze rim over a 33px sun or moon disc, centred 55 right of and 86
-- above the 198px map's centre; always drawn at its native size, while the
-- offset scales with the map. Above the compass so the rotating chevron
-- passes under it, below the ping blocker, mouse-transparent like the stock
-- one; a child of the map, so it hides with it. Built once under the latch;
-- the disc repaints only on DIEL_CYCLE_CHANGED.
EBS._ApplyForeverDiel = function(minimap, mapSize)
    local d = GetFFD(minimap)
    local orb = d.foreverDiel
    if not orb then
        local rim = C_Texture.GetAtlasInfo("UI-HUD-Minimap-Frame-Cycle")
        if not rim then return end
        orb = CreateFrame("Frame", nil, minimap)
        orb:SetSize(rim.width, rim.height)
        orb:EnableMouse(false)
        local disc = orb:CreateTexture(nil, "BACKGROUND", nil, 0)
        disc:SetPoint("CENTER")
        local border = orb:CreateTexture(nil, "OVERLAY", nil, 1)
        border:SetAllPoints()
        border:SetAtlas("UI-HUD-Minimap-Frame-Cycle")
        local function Paint(isDay)
            disc:SetAtlas(isDay and "UI-HUD-Minimap-DayCycle" or "UI-HUD-Minimap-NightCycle", true)
        end
        orb:RegisterEvent("DIEL_CYCLE_CHANGED")
        orb:SetScript("OnEvent", function(_, _, isDay) Paint(isDay) end)
        Paint(C_DateAndTime.IsDayTime())
        d.foreverDiel = orb
    end
    local s = mapSize / 198
    orb:ClearAllPoints()
    orb:SetPoint("CENTER", minimap, "CENTER", 55 * s, 86 * s)
    orb:SetFrameLevel(minimap:GetFrameLevel() + 5)
    orb:Show()
end

-- Classic WoW UI: the stock zoom button wearing the vanilla button files at
-- the vanilla 32px size, scaled with the map. Texture setters and SetSize
-- only on this Blizzard button; the one-time skin is memoized in its lookup
-- record. The vanilla files fill the whole button, so the atlas coordinates
-- the stock art left behind are reset.
EBS._ClassicZoomButton = function(btn, isIn, s)
    btn:SetSize(32 * s, 32 * s)
    local d = GetFFD(btn)
    if d.classicSkin then return end
    d.classicSkin = true
    local base = isIn and "Interface\\Minimap\\UI-Minimap-ZoomInButton-" or "Interface\\Minimap\\UI-Minimap-ZoomOutButton-"
    btn:SetNormalTexture(base .. "Up")
    btn:SetPushedTexture(base .. "Down")
    btn:SetDisabledTexture(base .. "Disabled")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    local tex = btn:GetNormalTexture()
    if tex then tex:SetTexCoord(0, 1, 0, 1) end
    tex = btn:GetPushedTexture()
    if tex then tex:SetTexCoord(0, 1, 0, 1) end
    tex = btn:GetDisabledTexture()
    if tex then tex:SetTexCoord(0, 1, 0, 1); tex:SetDesaturated(false) end
    tex = btn:GetHighlightTexture()
    if tex then tex:SetTexCoord(0, 1, 0, 1); tex:SetBlendMode("ADD") end
end

-- Classic WoW UI chrome: the vanilla UI-Minimap-Border file on two frames of
-- ours. The ring: the 192x192 region the vanilla MinimapBorder draws, centred
-- 8 left and 24 below the map centre (the art's circle sits on the map, the
-- rest is the lower-left bulge), on a frame above the map like the vanilla
-- backdrop, scaled by mapSize/140. The banner: the MinimapBorderTop strip
-- (sheet rows 0..28, columns 80..256) on OUR header frame (the same header
-- record the indicators, compartment and zone text anchor to), drawn in
-- three pieces at the sheet's own pixel size -- the 36-column rounded left
-- end, the 16-column right end and the middle stretched between them -- so
-- it spans the map plus the vanilla 18 a side without growing taller on a
-- big map; its bottom sits 4 above the map's top, under the map and ring as
-- the cluster's own region is; its zone-text slot is a 12-tall box centred
-- on the banner between the ends. Created once, re-anchored per apply pass.
EBS._ApplyClassicMinimapChrome = function(minimap, mapSize)
    local s = mapSize / 140
    local d = GetFFD(minimap)
    local ring = d.classicRing
    if not ring then
        ring = CreateFrame("Frame", nil, minimap)
        ring:EnableMouse(false)
        local tex = ring:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(ring)
        tex:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
        tex:SetTexCoord(0.25, 1.0, 0.125, 0.875)
        d.classicRing = ring
    end
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", minimap, "CENTER", -8 * s, -24 * s)
    ring:SetSize(192 * s, 192 * s)
    ring:SetFrameLevel(minimap:GetFrameLevel() + 3)
    ring:Show()
    local header = d.blizzHeader
    if not header then
        header = CreateFrame("Frame", nil, minimap)
        header:EnableMouse(false)
        local file = "Interface\\Minimap\\UI-Minimap-Border"
        local capL = header:CreateTexture(nil, "ARTWORK")
        capL:SetTexture(file)
        capL:SetTexCoord(0.3125, 0.453125, 0.0, 0.109375)
        capL:SetSize(36, 28)
        capL:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        local capR = header:CreateTexture(nil, "ARTWORK")
        capR:SetTexture(file)
        capR:SetTexCoord(0.9375, 1.0, 0.0, 0.109375)
        capR:SetSize(16, 28)
        capR:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        local mid = header:CreateTexture(nil, "ARTWORK")
        mid:SetTexture(file)
        mid:SetTexCoord(0.453125, 0.9375, 0.0, 0.109375)
        mid:SetPoint("TOPLEFT", capL, "TOPRIGHT", 0, 0)
        mid:SetPoint("BOTTOMRIGHT", capR, "BOTTOMLEFT", 0, 0)
        local slot = CreateFrame("Frame", nil, header)
        slot:SetHeight(12)
        slot:SetPoint("CENTER", header, "CENTER", 0, 1)
        slot:EnableMouse(false)
        header._zoneSlot = slot
        d.blizzHeader = header
    end
    header:ClearAllPoints()
    header:SetSize(mapSize + 36, 28)
    header:SetPoint("BOTTOM", minimap, "TOP", 0, 4)
    header._zoneSlot:SetWidth(math.max(40, mapSize + 36 - 52))
    header:SetFrameLevel(math.max(0, minimap:GetFrameLevel() - 1))
    header:Show()
end

I.DesiredMapParent = DesiredMapParent
I.broken = false
