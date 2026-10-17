if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Flyout.lua
--
--  The addon button flyout: junk filter, decoration strip and restore, the
--  grid layout, the Grow table, the panel, the toggle button and the button
--  row sizes and modes.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local _addonVisible, cachedAddonButtons, EBS = I._addonVisible, I.cachedAddonButtons, I.EBS
local EG, flyoutOwnedFrames, GetFFD = I.EG, I.flyoutOwnedFrames, I.GetFFD
local QueueApplyAll, SetFlyoutPanel = I.QueueApplyAll, I.SetFlyoutPanel
local SetFlyoutToggle = I.SetFlyoutToggle

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
-- Assigned in EUI_Minimap_Layout.lua (see SetMOEvaluate), so the flyout
-- panels created here can fire it from OnShow/OnHide.
local MO_Evaluate
I.moEvaluateSetters[#I.moEvaluateSetters + 1] = function(v) MO_Evaluate = v end

-------------------------------------------------------------------------------
--  Minimap Button Flyout
-------------------------------------------------------------------------------
local flyoutToggle = nil   -- the square trigger button
local flyoutPanel  = nil   -- the popup grid container
I.flyoutToggleSetters[#I.flyoutToggleSetters + 1] = function(v) flyoutToggle = v end
I.flyoutPanelSetters[#I.flyoutPanelSetters + 1] = function(v) flyoutPanel = v end
local flyoutSavedParents = {}  -- original parent/point data for restore
local flyoutSavedRegions = {}  -- original region states for restore

local FLYOUT_BTN_SIZE = 24
local FLYOUT_PADDING  = 4
local FLYOUT_COLS     = 4

-- Textures that are decorative borders/backgrounds on minimap buttons
local MINIMAP_BTN_JUNK = {
    [136467] = true,  -- UI-Minimap-Background
    [136430] = true,  -- MiniMap-TrackingBorder
    [136477] = true,  -- UI-Minimap-ZoomButton-Highlight (used on some buttons)
}
local MINIMAP_BTN_JUNK_PATH = {
    ["Interface\\Minimap\\MiniMap%-TrackingBorder"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-Background"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-ZoomButton%-Highlight"] = true,
}

local function IsJunkTexture(region)
    if not region or not region.IsObjectType or not region:IsObjectType("Texture") then
        return false
    end
    local texID = region.GetTextureFileID and region:GetTextureFileID()
    if texID and MINIMAP_BTN_JUNK[texID] then return true end
    local texPath = region:GetTexture()
    if texPath and type(texPath) == "string" then
        for pattern in pairs(MINIMAP_BTN_JUNK_PATH) do
            if texPath:match(pattern) then return true end
        end
    end
    return false
end

local function StripButtonDecorations(btn)
    if not flyoutSavedRegions[btn] then
        local saved = { junk = {} }
        for _, region in ipairs({ btn:GetRegions() }) do
            if IsJunkTexture(region) then
                saved.junk[#saved.junk + 1] = { region = region, alpha = region:GetAlpha(), shown = region:IsShown() }
            end
        end
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if hl and IsJunkTexture(hl) then
            saved.junk[#saved.junk + 1] = { region = hl, alpha = hl:GetAlpha(), shown = hl:IsShown() }
        end
        -- Snapshot icon anchors/texcoord/size for RestoreButtonDecorations.
        local icon = btn.icon or btn.Icon
        if icon then
            local nPts = icon:GetNumPoints()
            local pts = {}
            for i = 1, nPts do
                pts[i] = { icon:GetPoint(i) }
            end
            saved.icon = icon
            saved.iconPoints = pts
            saved.iconTC = { icon:GetTexCoord() }
        end
        saved.btnW, saved.btnH = btn:GetWidth(), btn:GetHeight()
        flyoutSavedRegions[btn] = saved
    end
    -- Junk hiding runs on every call; the snapshot above only once.
    for _, info in ipairs(flyoutSavedRegions[btn].junk) do
        info.region:SetAlpha(0)
        info.region:Hide()
    end
end

local function RestoreButtonDecorations(btn)
    local saved = flyoutSavedRegions[btn]
    if not saved then return end
    for _, info in ipairs(saved.junk) do
        info.region:SetAlpha(info.alpha)
        if info.shown then info.region:Show() end
    end
    if saved.icon and saved.iconPoints then
        saved.icon:ClearAllPoints()
        for _, pt in ipairs(saved.iconPoints) do
            saved.icon:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
        end
        if saved.iconTC and #saved.iconTC >= 8 then
            saved.icon:SetTexCoord(unpack(saved.iconTC))
        end
    end
    if saved.btnW and saved.btnH then
        btn:SetSize(saved.btnW, saved.btnH)
    end
    flyoutSavedRegions[btn] = nil
end

local function IsUngrouped(btn)
    -- A group of one has nothing to open: the only grouped button stands on
    -- the row by itself (decided per scan, see GatherMinimapButtons).
    if btn == EBS._soloAddonButton then return true end
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp or not mp.ungroupedButtons then return false end
    local name = btn:GetName()
    return name and mp.ungroupedButtons[name]
end

local function GetMinimapButtonLabel(btn)
    local name = btn:GetName() or ""
    return name:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", ""):gsub("MinimapButton$", ""):gsub("_MinimapButton$", "")
end

local function CollectFlyoutButtons()
    local collected = {}
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and not IsUngrouped(btn) then
            collected[#collected + 1] = btn
        end
    end
    table.sort(collected, function(a, b)
        return GetMinimapButtonLabel(a):lower() < GetMinimapButtonLabel(b):lower()
    end)
    return collected
end

local function GetAddonBtnSize()
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.addonBtnSize or FLYOUT_BTN_SIZE
end

-- EUI-look black box behind an addon button, on the button row and in the flyout grid alike.
-- A child frame of the button, so it is re-pinned just below the button on every layout:
-- the flyout's child loop lifts every child above the button, which would bury the icon.
-- EBS field, not local.
function EBS._ShowAddonBtnBox(btn)
    local d = GetFFD(btn)
    if not d.ungroupBg then
        local ubg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        ubg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
        ubg:SetBackdropColor(0, 0, 0, 0.8)
        ubg:SetAllPoints(btn)
        d.ungroupBg = ubg
    end
    local ubg = d.ungroupBg
    ubg:SetFrameStrata(btn:GetFrameStrata())
    ubg:SetFrameLevel(btn:GetFrameLevel() - 1)
    ubg:Show()
end

-- Raise popups an addon parents to its button after layout above the grid.
function EBS._RaiseLateFlyoutChildren(btn)
    if not flyoutPanel or btn:GetParent() ~= flyoutPanel then return end
    local combat = InCombatLockdown()
    local function raise(frame, level)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not (combat and child:IsProtected()) then
                child:SetFrameStrata("DIALOG")
                child:SetFrameLevel(level)
                raise(child, level + 1)
            end
        end
    end
    raise(btn, flyoutPanel:GetFrameLevel() + 6)
end

-- Keep the grid open for a press on anything parented under it (forbidden frames never).
function EBS._MouseOverFlyoutChild(panel)
    local focus = GetMouseFoci()[1]
    while focus do
        if focus:IsForbidden() then return false end
        if focus == panel then return true end
        focus = focus:GetParent()
    end
    return false
end

local function LayoutFlyoutButtons()
    if not flyoutPanel then return end
    local buttons = CollectFlyoutButtons()
    -- Same lockdown rule as HideMinimapChild: every per-button call in the loop below
    -- (SetParent/SetFrameStrata/SetPoint/SetSize/Show/SetFrameLevel) is protected and
    -- is blocked silently for a protected button, which would leave it half-moved with
    -- a flyoutSavedParents entry claiming it was placed. Drop those buttons from THIS
    -- pass -- before the saved-parent capture, so nothing is recorded for a move that
    -- never happened -- and queue the re-apply. ApplyMinimap invalidates and closes the
    -- flyout, so the next open rebuilds the full grid. The list is a fresh table per
    -- call, so compacting it in place is safe.
    if InCombatLockdown() then
        local kept = 0
        for i = 1, #buttons do
            local btn = buttons[i]
            if btn:IsProtected() then
                QueueApplyAll()
            else
                kept = kept + 1
                buttons[kept] = btn
            end
        end
        for i = #buttons, kept + 1, -1 do buttons[i] = nil end
    end
    local count = #buttons
    if count == 0 then
        flyoutPanel:SetSize(1, 1)
        return
    end

    local btnSize = GetAddonBtnSize()
    -- EUI look: each cell gets the flat black box the ungrouped row buttons wear, so a
    -- button looks the same in the grid and on the row. Stock styles (and Button
    -- Backgrounds off) keep the stock-map ring around each icon.
    local mp = EBS.db and EBS.db.profile.minimap
    local boxes = not EBS._MinimapBlizz() and not (mp and mp.btnBackgrounds == false)
    -- Boxes: the outer margin matches the gaps. Ring: margin=8, since the ring overlay
    -- overhangs each button by 3px, leaving 5px of visible clearance.
    local margin = boxes and FLYOUT_PADDING or 8
    local cols = math.min(count, FLYOUT_COLS)
    local rows = math.ceil(count / cols)
    local pw = margin * 2 + cols * btnSize + (cols - 1) * FLYOUT_PADDING
    local ph = margin * 2 + rows * btnSize + (rows - 1) * FLYOUT_PADDING
    flyoutPanel:SetSize(pw, ph)

    for i, btn in ipairs(buttons) do
        if not flyoutSavedParents[btn] then
            local p1, rel, p2, ox, oy = btn:GetPoint(1)
            flyoutSavedParents[btn] = {
                parent = btn:GetParent(),
                strata = btn:GetFrameStrata(),
                point = p1, relTo = rel, relPoint = p2, x = ox, y = oy,
            }
        end

        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local xOff = margin + col * (btnSize + FLYOUT_PADDING)
        local yOff = -(margin + row * (btnSize + FLYOUT_PADDING))

        btn:SetParent(flyoutPanel)
        -- Unlock fixed strata/level first (LibDBIcon locks these)
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetFrameStrata("DIALOG")
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(true) end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", flyoutPanel, "TOPLEFT", xOff, yOff)
        btn:SetSize(btnSize, btnSize)
        EBS._suppressVisTrack = true
        btn:SetAlpha(1)
        btn:Show()
        EBS._suppressVisTrack = false
        btn:SetFrameLevel(flyoutPanel:GetFrameLevel() + 5)
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(true) end
        StripButtonDecorations(btn)
        -- Overlays left over from a previous ungroup cycle (or the other cell style)
        if not boxes and GetFFD(btn).ungroupBg then GetFFD(btn).ungroupBg:Hide() end
        if boxes and GetFFD(btn).flyoutRing then GetFFD(btn).flyoutRing:Hide() end
        if btn._ungroupRing then btn._ungroupRing:Hide() end
        -- Children must ride the same strata/level as the button.
        for _, child in ipairs({ btn:GetChildren() }) do
            child:SetFrameStrata("DIALOG")
            child:SetFrameLevel(flyoutPanel:GetFrameLevel() + 6)
        end
        if not GetFFD(btn).lateChildHook then
            GetFFD(btn).lateChildHook = true
            if btn:HasScript("OnClick") then btn:HookScript("OnClick", EBS._RaiseLateFlyoutChildren) end
        end
        local icon = btn.icon or btn.Icon
        if not icon then
            for _, region in ipairs({ btn:GetRegions() }) do
                if region:IsObjectType("Texture") and region:IsShown()
                   and region:GetAlpha() > 0 and not IsJunkTexture(region) then
                    icon = region
                    break
                end
            end
        end
        if icon then
            -- Same inset as the row: 3px inside the box, 2px inside the ring
            local inset = boxes and 3 or 2
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
            pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95)
            -- Foreign icon: no global SetTexCoord snap hook, so disable snap once here.
            if EllesmereUI.PP then EllesmereUI.PP.DisablePixelSnap(icon) end
        end
        if boxes then
            -- After the child loop above, which lifted the box over the icon
            EBS._ShowAddonBtnBox(btn)
        else
            if not GetFFD(btn).flyoutRing then
                local ring = btn:CreateTexture(nil, "OVERLAY", nil, 7)
                ring:SetAtlas("AdventureMap-combatally-ring")
                ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
                ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
                GetFFD(btn).flyoutRing = ring
            end
            GetFFD(btn).flyoutRing:Show()
        end
    end
end

-- Grow Tooltip/Popup: shared open-direction for all popups/tooltips off minimap
-- buttons (M+ portals, group flyout, custom tooltips). Auto follows Button Row
-- Position: vertical rows open left, horizontal rows open down. Namespace-scoped
-- (EBS field, not local). edge = anchor tuples (tooltip point,
-- anchor point, x, y) for corner-hung popups; center = centered on the facing edge
-- (vault tooltip); tt = named sides for ShowWidgetTooltip labels.
EBS._Grow = {
    edge = {
        left  = { "TOPRIGHT",   "TOPLEFT",    -4, 0 },
        right = { "TOPLEFT",    "TOPRIGHT",    4, 0 },
        up    = { "BOTTOMLEFT", "TOPLEFT",     0, 4 },
        down  = { "TOPLEFT",    "BOTTOMLEFT",  0, -4 },
    },
    center = {
        left  = { "RIGHT",  "LEFT",   -4, 0 },
        right = { "LEFT",   "RIGHT",   4, 0 },
        up    = { "BOTTOM", "TOP",     0, 4 },
        down  = { "TOP",    "BOTTOM",  0, -4 },
    },
    tt = { left = "left", right = "right", up = "above", down = "below" },
}

function EBS._Grow.Dir()
    local mp = EBS.db and EBS.db.profile.minimap
    local g = (mp and mp.flyoutGrowDir) or "auto"
    if g ~= "auto" then return g end
    local rp = (mp and mp.btnRowPosition) or "blUp"
    if rp == "blUp" or rp == "tlDown" or rp == "brUp" or rp == "trDown" then
        return "left"
    end
    return "down"
end

function EBS._Grow.TT()
    return EBS._Grow.tt[EBS._Grow.Dir()] or "left"
end

local _flyoutBuilt = false

local function EnsureFlyoutPanel()
    if not flyoutPanel then
        -- Controller cursor: the shared overlay parent (UIParent without a
        -- controller UI, so nothing changes then); tracked once scripts are set.
        local overlayParent = EllesmereUI.OverlayParent()
        SetFlyoutPanel(CreateFrame("Frame", nil, overlayParent, "BackdropTemplate"))
        flyoutPanel:SetFrameStrata("DIALOG")
        flyoutPanel:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        flyoutPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        flyoutPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        -- Anchored per Grow Tooltip/Popup on every open (see ShowFlyoutPanel)
        flyoutPanel:SetClampedToScreen(true)
        flyoutOwnedFrames[flyoutPanel] = true
        -- Keep the mouseover stack in sync while this flyout opens/closes.
        flyoutPanel:HookScript("OnShow", function() if MO_Evaluate then MO_Evaluate() end end)
        flyoutPanel:HookScript("OnHide", function() if MO_Evaluate then MO_Evaluate() end end)
        -- Start hidden: frames spawn SHOWN and OnShow fires only on a real hide->show,
        -- so without this the first open never installs the watcher below.
        flyoutPanel:Hide()
        -- Click-away dismiss (matches options-panel dropdowns): closes on any left press
        -- outside the grid+toggle while shown. IsMouseButtonDown polls raw input state
        -- so clicks still land normally; the toggle is excluded so its own OnClick
        -- closes without a reopen race.
        flyoutPanel:HookScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(m)
                if IsMouseButtonDown("LeftButton")
                   and not m:IsMouseOver()
                   and not (flyoutToggle and flyoutToggle:IsMouseOver())
                   and not EBS._MouseOverFlyoutChild(m) then
                    m:Hide()
                end
            end)
        end)
        flyoutPanel:HookScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        -- Controller cursor: its cancel button presses the toggle (closing the
        -- grid); the layer shows exactly while the grid does.
        if overlayParent ~= UIParent then
            flyoutPanel.CloseButton = flyoutToggle
            EllesmereUI.TrackOverlay(flyoutPanel)
        end
    end
end

-- Built once; buttons stay reparented into the grid permanently. Rebuilds only when the button list changes (new addon loaded, button ungrouped).
local function BuildFlyoutContents()
    EnsureFlyoutPanel()
    LayoutFlyoutButtons()
    _flyoutBuilt = true
end

local function InvalidateFlyout()
    _flyoutBuilt = false
end

-- Profile-swap refresh: invalidate for the next open, re-show buttons re-init hid.
_G._EMIN_RefreshFlyout = function()
    InvalidateFlyout()
    if flyoutPanel and flyoutPanel:IsShown() then
        BuildFlyoutContents()
    end
    -- Re-assert alpha (profile swap re-hides via HideMinimapChild during re-init)
    for _, btn in ipairs(cachedAddonButtons) do
        if btn:GetParent() == flyoutPanel then
            btn:SetAlpha(1)
            btn:Show()
        end
    end
end

local function ShowFlyoutPanel()
    EnsureFlyoutPanel()
    -- Re-anchor per Grow Tooltip/Popup on every open (setting or Auto's row position can change). Left/right keep the toggle's bottom edge, up/down its left; 2px gap.
    local dir = EBS._Grow.Dir()
    flyoutPanel:ClearAllPoints()
    if dir == "right" then
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "BOTTOMRIGHT", 2, 0)
    elseif dir == "up" then
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "TOPLEFT", 0, 2)
    elseif dir == "down" then
        flyoutPanel:SetPoint("TOPLEFT", flyoutToggle, "BOTTOMLEFT", 0, -2)
    else
        flyoutPanel:SetPoint("BOTTOMRIGHT", flyoutToggle, "BOTTOMLEFT", -2, 0)
    end
    -- Show BEFORE layout: the addon-button Show hook checks IsShown() to skip the
    -- alpha-zero path.
    flyoutPanel:Show()
    if not _flyoutBuilt then
        BuildFlyoutContents()
    end
end

local function HideFlyoutPanel()
    if flyoutPanel then
        flyoutPanel:Hide()
        -- Do NOT restore buttons or wipe saved parents; they stay parented here.
    end
end

local function ToggleFlyoutPanel()
    if flyoutPanel and flyoutPanel:IsShown() then
        HideFlyoutPanel()
    else
        ShowFlyoutPanel()
    end
end

local function GetInteractableBtnSize()
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.interactableBtnSize or 22
end

-- Row modes keyed by [MAP corner]+[growth dir] (blUp = left edge, bottom corner,
-- upward); vertical rows hug the outside of the left/right edge, horizontal rows run
-- above/below. point/rel = per-button anchor -> map anchor; dirX/dirY = growth vector;
-- awayX/awayY = Distance from Map push. PlaceRowButton/PlaceElement advance a cursor in snapped physical-pixel steps so icons stay flush at 0 spacing with equal gaps.
-- arc/arcDir: Blizzard Style walks the same row round the compass ring instead --
-- arc = the corner's angle on the circle (degrees, 0 = right, counter-clockwise),
-- arcDir = which way the row walks from it (+1 counter-clockwise, -1 clockwise).
local BTN_ROW_MODES = {
    -- Left edge (vertical)
    blUp    = { point = "BOTTOMRIGHT", rel = "BOTTOMLEFT",  dirX = 0,  dirY = 1,  awayX = -1, awayY = 0,  arc = 225, arcDir = -1 },
    tlDown  = { point = "TOPRIGHT",    rel = "TOPLEFT",     dirX = 0,  dirY = -1, awayX = -1, awayY = 0,  arc = 135, arcDir = 1 },
    -- Right edge (vertical)
    brUp    = { point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", dirX = 0,  dirY = 1,  awayX = 1,  awayY = 0,  arc = 315, arcDir = 1 },
    trDown  = { point = "TOPLEFT",     rel = "TOPRIGHT",    dirX = 0,  dirY = -1, awayX = 1,  awayY = 0,  arc = 45,  arcDir = -1 },
    -- Above the map (horizontal)
    tlRight = { point = "BOTTOMLEFT",  rel = "TOPLEFT",     dirX = 1,  dirY = 0,  awayX = 0,  awayY = 1,  arc = 135, arcDir = -1 },
    trLeft  = { point = "BOTTOMRIGHT", rel = "TOPRIGHT",    dirX = -1, dirY = 0,  awayX = 0,  awayY = 1,  arc = 45,  arcDir = 1 },
    -- Below the map (horizontal)
    blRight = { point = "TOPLEFT",     rel = "BOTTOMLEFT",  dirX = 1,  dirY = 0,  awayX = 0,  awayY = -1, arc = 225, arcDir = 1 },
    brLeft  = { point = "TOPRIGHT",    rel = "BOTTOMRIGHT", dirX = -1, dirY = 0,  awayX = 0,  awayY = -1, arc = 315, arcDir = -1 },
}

local function GetBtnRowMode(mp)
    return BTN_ROW_MODES[mp and mp.btnRowPosition or "blUp"] or BTN_ROW_MODES.blUp
end

-- Blizzard element row (tracking/calendar/mail/crafting): reuses BTN_ROW_MODES;
-- square shape only -- circle layout wraps around the clock instead.
local function GetElementRowMode(mp)
    return BTN_ROW_MODES[mp and mp.elementRowPosition or "tlDown"] or BTN_ROW_MODES.tlDown
end

-- Distance from Map push: left/right rows move horizontally, above/below vertically.
-- Icon Spacing is applied per link at placement. Forever Square's rows hang
-- from the frame's outer edge and start EBS.FV_ROW_AIR clear of it.
local function GetRowBase(mode, distance)
    local d = (distance or 0) + (EBS._fvSquare and EBS.FV_ROW_AIR or 0)
    return d * mode.awayX, d * mode.awayY
end

-- Scale for the custom tooltips on the unique minimap buttons (vault, friends,
-- calendar, mail, tracking, crafting, flyout toggle, portals).
local function GetCustomTooltipScale()
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.customTooltipScale or 1.0
end

local function CreateFlyoutToggle()
    if flyoutToggle then
        -- Re-apply the current accent so a later ApplyAll (e.g. at PLAYER_ENTERING_WORLD,
        -- after theme resolution mutated ELLESMERE_GREEN) picks up the right color.
        local EG2 = EllesmereUI.ELLESMERE_GREEN
        if flyoutToggle._norm   then flyoutToggle._norm:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)   end
        if flyoutToggle._pushed then flyoutToggle._pushed:SetVertexColor(EG2.r, EG2.g, EG2.b, 1) end
        if flyoutToggle._hl     then flyoutToggle._hl:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)     end
        return flyoutToggle
    end

    local btn = CreateFrame("Button", nil, Minimap)
    local iconSize = GetInteractableBtnSize()
    btn:SetSize(iconSize, iconSize)
    btn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local norm = btn:CreateTexture(nil, "ARTWORK")
    norm:SetAllPoints()
    norm:SetAtlas("Map-Filter-Button")
    norm:SetDesaturated(true)
    norm:SetVertexColor(EG.r, EG.g, EG.b, 1)
    btn:SetNormalTexture(norm)
    btn._norm = norm

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetAtlas("Map-Filter-Button-down")
    pushed:SetDesaturated(true)
    pushed:SetVertexColor(EG.r, EG.g, EG.b, 1)
    btn:SetPushedTexture(pushed)
    btn._pushed = pushed

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Map-Filter-Button")
    hl:SetDesaturated(true)
    hl:SetVertexColor(EG.r, EG.g, EG.b, 1)
    hl:SetAlpha(0.3)
    btn:SetHighlightTexture(hl)
    btn._hl = hl

    -- Keep the three textures synced to the accent. Vertex alpha stays 1; the highlight's SetAlpha(0.3) still applies on top since the two multiply.
    EllesmereUI.RegAccent({ type = "vertex", obj = norm })
    EllesmereUI.RegAccent({ type = "vertex", obj = pushed })
    EllesmereUI.RegAccent({ type = "vertex", obj = hl })

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        -- Opening the grid replaces the label tooltip (same as M+ Portals)
        EllesmereUI.HideWidgetTooltip(true)
        ToggleFlyoutPanel()
    end)
    btn:SetScript("OnEnter", function(self)
        if flyoutPanel and flyoutPanel:IsShown() then return end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Addon Buttons", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    btn:SetScript("OnLeave", function(self)
        EllesmereUI.HideWidgetTooltip()
    end)

    -- Blizzard/addon hooks on minimap children can disable mouse; re-assert on Show.
    btn:HookScript("OnShow", function(self)
        if not self:IsMouseEnabled() then
            self:EnableMouse(true)
        end
    end)

    SetFlyoutToggle(btn)
    flyoutOwnedFrames[btn] = true
    return btn
end

I.BuildFlyoutContents, I.CollectFlyoutButtons = BuildFlyoutContents, CollectFlyoutButtons
I.CreateFlyoutToggle, I.flyoutSavedParents = CreateFlyoutToggle, flyoutSavedParents
I.flyoutSavedRegions, I.GetBtnRowMode = flyoutSavedRegions, GetBtnRowMode
I.GetCustomTooltipScale, I.GetElementRowMode = GetCustomTooltipScale, GetElementRowMode
I.GetInteractableBtnSize, I.GetRowBase = GetInteractableBtnSize, GetRowBase
I.HideFlyoutPanel, I.InvalidateFlyout = HideFlyoutPanel, InvalidateFlyout
I.IsJunkTexture, I.IsUngrouped = IsJunkTexture, IsUngrouped
I.RestoreButtonDecorations = RestoreButtonDecorations
I.StripButtonDecorations = StripButtonDecorations
I.broken = false
