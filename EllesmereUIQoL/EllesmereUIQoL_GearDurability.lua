if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_GearDurability.lua
--  Runtime for the standalone, independently movable Gear Durability display.
--  Shows a compact "[forge] 87%" readout of the LOWEST durability percent across
--  equipped repairable gear, so it is obvious at a glance when to repair.
--
--  Lightweight by design:
--    * Nothing is created and no events are registered unless the feature is on.
--    * Pure event driven: samples only on UPDATE_INVENTORY_DURABILITY and
--      PLAYER_ENTERING_WORLD. No OnUpdate, no ticker, no polling.
--
--  The durability maths and the white -> red warning gradient mirror the
--  DataBars durability block so the two readouts always agree; the icon reuses
--  the DataBars forge glyph (a plain file path, present on disk regardless of
--  whether the DataBars module is enabled). Its own settings live under
--  EllesmereUIQoLDB.profile.gearDurability, so no other feature's data is touched.
-------------------------------------------------------------------------------

local floor = math.floor
local max   = math.max

-- DataBars forge glyph. A texture path is a file reference, not an addon handle,
-- so this resolves whether or not the DataBars module is loaded/enabled.
local FORGE_ICON = "Interface\\AddOns\\EllesmereUIDataBars\\media\\forge.png"

local ICON_GAP = 3  -- px between the icon and the percent text

-- Inventory slots that can carry durability, mapped to Blizzard's already
-- localized slot-name globals (resolved at hover time). Rings, neck, cloak,
-- trinkets and cosmetic slots have no durability and never appear.
local SLOT_GLOBAL = {
    [1]  = "HEADSLOT",
    [3]  = "SHOULDERSLOT",
    [5]  = "CHESTSLOT",
    [6]  = "WAISTSLOT",
    [7]  = "LEGSSLOT",
    [8]  = "FEETSLOT",
    [9]  = "WRISTSLOT",
    [10] = "HANDSSLOT",
    [16] = "MAINHANDSLOT",
    [17] = "SECONDARYHANDSLOT",
}

-------------------------------------------------------------------------------
--  DB access. We register our own slice on the shared EllesmereUIQoLDB (the same
--  pattern Cursor / RaidTools / MovementAlert use); a fill-missing-only merge
--  leaves every other QoL feature's data untouched.
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        gearDurability = {
            visibility   = "NEVER",   -- ALWAYS | NEVER (default OFF: zero cost)
            showIcon     = true,
            showPercent  = true,
            dynamicColor = true,      -- white -> red warning gradient (mirrors DataBars)
            color        = { r = 1, g = 1, b = 1 },  -- static text color when dynamicColor is off
            hideAtFull   = false,     -- hide entirely while the lowest item is 100%
            fontSize     = 14,
            pos          = nil,       -- { centerX, centerY } stored after first move
        },
    },
}

local db
local function P()
    return db and db.profile and db.profile.gearDurability
end

local frame, iconTex, pctFS
local _eventFrame
local _lastPct = 100

-------------------------------------------------------------------------------
--  Durability sampling + colour (both copied from the DataBars durability block
--  so the standalone readout can never disagree with it).
-------------------------------------------------------------------------------
local function SampleDurability()
    local lowest = 100
    for slotId = 1, 18 do
        local cur, mx = GetInventoryItemDurability(slotId)
        if cur and mx and mx > 0 then
            local pct = cur / mx * 100
            if pct < lowest then lowest = pct end
        end
    end
    local pct = floor(lowest)
    _lastPct = pct
    return pct
end

-- White(100%) fades to soft red(1,.35,.35) over 20..100; <=20% is fully red.
local function DynamicColor(pct)
    local t = (pct - 20) * (100 / 80)
    if t < 0 then t = 0 elseif t > 100 then t = 100 end
    local gb = 0.35 + 0.65 * (t / 100)
    return 1, gb, gb
end

local function ResolveColor(pct)
    local p = P()
    if p and p.dynamicColor == false then
        local c = p.color
        if c then return c.r or 1, c.g or 1, c.b or 1 end
        return 1, 1, 1
    end
    return DynamicColor(pct)
end

-------------------------------------------------------------------------------
--  Tooltip: per-slot breakdown, built fresh on hover through the house widget
--  tooltip. Only durability-bearing, equipped slots are listed.
-------------------------------------------------------------------------------
local function DurabilityTooltipText()
    local lines = EllesmereUI.L("Gear Durability")
    for slotId = 1, 18 do
        local cur, mx = GetInventoryItemDurability(slotId)
        if cur and mx and mx > 0 then
            local name = SLOT_GLOBAL[slotId] and _G[SLOT_GLOBAL[slotId]]
            if name then
                lines = lines .. "\n" .. string.format("%s  %d%%", name, floor(cur / mx * 100))
            end
        end
    end
    return lines
end

-------------------------------------------------------------------------------
--  Layout. The frame auto-sizes to its content ([icon] + "87%"), so there is no
--  resize handle; the font-size slider drives the scale instead.
-------------------------------------------------------------------------------
local function Relayout()
    if not frame then return end
    local p = P()
    if not p then return end

    local fontSize    = p.fontSize or 14
    local showIcon    = p.showIcon ~= false
    local showPercent = p.showPercent ~= false
    local iconSz      = fontSize + 6

    pctFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        fontSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")

    local pct = _lastPct or 100
    pctFS:SetText(pct .. "%")
    local r, g, b = ResolveColor(pct)
    pctFS:SetTextColor(r, g, b)
    pctFS:SetShown(showPercent)

    iconTex:ClearAllPoints()
    pctFS:ClearAllPoints()

    if showIcon then
        iconTex:SetSize(iconSz, iconSz)
        iconTex:SetVertexColor(r, g, b)
        iconTex:SetPoint("LEFT", frame, "LEFT", 0, 0)
        iconTex:Show()
        if showPercent then
            pctFS:SetPoint("LEFT", iconTex, "RIGHT", ICON_GAP, 0)
        end
    else
        iconTex:Hide()
        if showPercent then
            pctFS:SetPoint("LEFT", frame, "LEFT", 0, 0)
        end
    end

    local w = 0
    if showIcon then w = w + iconSz end
    if showPercent then
        if showIcon then w = w + ICON_GAP end
        w = w + max(pctFS:GetStringWidth() or 0, 1)
    end
    local hgt = max(showIcon and iconSz or 0, showPercent and (fontSize + 2) or 0)
    if w < 1 then w = 1 end
    if hgt < 1 then hgt = 1 end
    frame:SetSize(w, hgt)
end

-------------------------------------------------------------------------------
--  Position (center-anchored, stored as an offset from UIParent's center).
-------------------------------------------------------------------------------
local function ApplyPosition()
    if not frame then return end
    local p = P()
    if not p then return end
    frame:ClearAllPoints()
    if p.pos and p.pos.centerX and p.pos.centerY then
        frame:SetPoint("CENTER", UIParent, "CENTER", p.pos.centerX, p.pos.centerY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

local function SavePosition()
    if not frame or not db then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    local fw, fh = frame:GetSize()
    local cx = left + fw / 2 - UIParent:GetWidth() / 2
    local cy = bottom + fh / 2 - UIParent:GetHeight() / 2
    local p = P(); if p then p.pos = { centerX = cx, centerY = cy } end
end

-- Seed a concrete starting position the first time the display is switched on,
-- so the mover has somewhere to sit. Does nothing if a position already exists.
local function SeedDefaultPos()
    local p = P(); if not p then return end
    if p.pos then return end
    if not frame then return end
    local cx = frame:GetLeft() and (frame:GetLeft() + frame:GetWidth() / 2 - UIParent:GetWidth() / 2) or 0
    local cy = frame:GetBottom() and (frame:GetBottom() + frame:GetHeight() / 2 - UIParent:GetHeight() / 2) or -150
    p.pos = { centerX = cx, centerY = cy }
    ApplyPosition()
end
_G._EUI_GearDurability_SeedPos = SeedDefaultPos

-------------------------------------------------------------------------------
--  Visibility + refresh
-------------------------------------------------------------------------------
local function ShouldShow()
    local p = P()
    if not p or p.visibility == "NEVER" then return false end
    if p.showIcon == false and p.showPercent == false then return false end
    if p.hideAtFull and (_lastPct or 100) >= 100 then return false end
    return true
end

local function UpdateVisibility()
    if not frame then return end
    if ShouldShow() then frame:Show() else frame:Hide() end
end

local function Refresh()
    if not frame then return end
    SampleDurability()
    Relayout()
    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  Events (armed only while enabled)
-------------------------------------------------------------------------------
local function _onEvent()
    Refresh()
end

local function _ensureEvents(enabled)
    if not _eventFrame then
        _eventFrame = CreateFrame("Frame")
        _eventFrame:SetScript("OnEvent", _onEvent)
    end
    if enabled then
        _eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
        _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        _eventFrame:UnregisterAllEvents()
    end
end

-------------------------------------------------------------------------------
--  Frame creation (once, on first enable)
-------------------------------------------------------------------------------
local function CreateGearDurabilityFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "EllesmereUIGearDurability", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)
    frame:Hide()

    iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetTexture(FORGE_ICON)

    pctFS = frame:CreateFontString(nil, "OVERLAY")
    pctFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        14, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    pctFS:SetText("")

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, DurabilityTooltipText, { justify = "LEFT" })
        end
    end)
    frame:SetScript("OnLeave", function()
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    return frame
end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local function Apply()
    if not db then return end
    local p = P()
    local enabled = p and p.visibility ~= "NEVER"
    if enabled then
        -- Build lazily on first enable: nothing above exists until this runs.
        if not frame then CreateGearDurabilityFrame() end
        _ensureEvents(true)
        ApplyPosition()
        SampleDurability()
        Relayout()
        UpdateVisibility()
    else
        -- Disabled (or never enabled): create nothing. Only tear down if a
        -- previous enable had already built the event frame / display.
        if _eventFrame then _ensureEvents(false) end
        if frame then frame:Hide() end
    end
end
_G._EUI_GearDurability_Apply = Apply

-------------------------------------------------------------------------------
--  Unlock mode registration (standalone movable element; no resize)
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_GearDurability",
            label = "Gear Durability",
            group = "Quality of Life",
            order = 602,
            noResize = true,          -- size follows content / font size
            noAnchorTarget = true,    -- content-sized; nothing should anchor to it
            isHidden = function()
                local p = P()
                return not p or p.visibility == "NEVER"
            end,
            getFrame = function()
                -- Never build here: ApplySavedPositions() calls getFrame for every
                -- registered element at login, so creating would defeat zero-cost
                -- while disabled. The frame is built by Apply() on first enable,
                -- and a disabled element's mover is skipped via isHidden anyway.
                return frame
            end,
            getSize = function()
                if frame and frame:GetWidth() then return frame:GetWidth(), frame:GetHeight() end
                return 40, 20
            end,
            savePos = function(_, point, relPoint, x, y)
                local p = P(); if not p then return end
                if frame and frame:GetLeft() then
                    SavePosition()
                else
                    p.pos = { centerX = x, centerY = y }
                end
            end,
            loadPos = function()
                local p = P()
                if p and p.pos then
                    return { point = "CENTER", relPoint = "CENTER", x = p.pos.centerX, y = p.pos.centerY }
                end
                return nil
            end,
            clearPos = function()
                local p = P(); if p then p.pos = nil end
            end,
            applyPos = function()
                ApplyPosition()
            end,
        }),
    })
end
_G._EUI_GearDurability_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not EllesmereUI or not EllesmereUI.Lite or not EllesmereUI.Lite.NewDB then
        return
    end
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true)
    _G._EUI_GearDurability_DB = function() return db end
    -- Zero cost while off: Apply builds the frame and arms events only when the
    -- display is enabled (visibility ~= NEVER).
    Apply()
    RegisterUnlock()
end)
