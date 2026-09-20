if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_PreyBar.lua
--  Custom Prey Hunt bar. Blizzard's native EncounterBar/UIWidgetPowerBarContainerFrame
--  is prone to jumping position (a Blizzard Edit Mode bug), so this reads the same
--  Prey Hunt widget data straight from C_UIWidgetManager and renders it on an
--  EUI-owned frame instead -- our frame's position is never touched by Blizzard's
--  layout system, so the jump bug can't reach it. Blizzard's own container is only
--  hidden (alpha), never reparented or repositioned.
--
--  No options: always on, movable only via unlock mode.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local defaults = { profile = { preyBar = { pos = nil, size = nil } } }
local db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults)
local function P() return db.profile.preyBar end

local L = EllesmereUI.L or function(s) return s end

-------------------------------------------------------------------------------
--  Widget plumbing: Enum members resolved with literal fallbacks so a stale
--  Enum table (e.g. on a fresh-boot race) can't hard-error the module.
-------------------------------------------------------------------------------
local PREY_WIDGET_TYPE  = (Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.PreyHuntProgress) or 31
local WIDGET_SHOWN       = (Enum.WidgetShownState and Enum.WidgetShownState.Shown) or 1

-- Tier -> fallback tooltip name + segment-bar color. At a given tier, ALL lit
-- segments (tierIndex + 1 of them) share that tier's color -- Warm shows two
-- orange segments, not one yellow + one orange.
local TIER = {
    [0] = { name = "Cold",  r = 0.95, g = 0.85, b = 0.10 },
    [1] = { name = "Warm",  r = 0.95, g = 0.55, b = 0.10 },
    [2] = { name = "Hot",   r = 0.85, g = 0.15, b = 0.10 },
    [3] = { name = "Final", r = 0.45, g = 0.02, b = 0.05 }, -- blood red
}
local SEGMENT_COUNT = 4
local SEGMENT_GAP = 3 -- 2px eaten by the 1px borders on each side + 1px visible gap
local BAR_Y_GAP = 7 -- vertical gap between icon and segment bar
local SEGMENT_BAR_RATIO = 0.18 -- bar height as a fraction of icon size
local UNLIT_COLOR = { 0.10, 0.10, 0.13, 0.9 }

local DEFAULT_POS = { x = 0, y = 200 }
local DEFAULT_ICON_SIZE = 60

local frame       -- built lazily by BuildFrame
local active = false   -- a real Prey Hunt widget is currently shown
local previewOn = false

local function GetIconSize() return P().size or DEFAULT_ICON_SIZE end

-------------------------------------------------------------------------------
--  Position
-------------------------------------------------------------------------------
local function ApplyPosition()
    if not frame then return end
    local pos = P().pos
    frame:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        frame:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_POS.x, DEFAULT_POS.y)
    end
end

-------------------------------------------------------------------------------
--  Layout: icon on top, a 4-segment tier bar underneath. Both scale together
--  off GetIconSize() so the unlock-mode resize handle drives the whole thing.
-------------------------------------------------------------------------------
local function ApplyLayout()
    if not frame then return end
    local size = GetIconSize()
    local barH = math.max(6, math.floor(size * SEGMENT_BAR_RATIO + 0.5))
    frame:SetSize(size, size + BAR_Y_GAP + barH)
    frame.icon:SetSize(size, size)

    local segW = (size - SEGMENT_GAP * (SEGMENT_COUNT - 1)) / SEGMENT_COUNT
    for i, seg in ipairs(frame.segments) do
        seg:SetSize(segW, barH)
        seg:ClearAllPoints()
        if i == 1 then
            seg:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -BAR_Y_GAP)
        else
            seg:SetPoint("LEFT", frame.segments[i - 1], "RIGHT", SEGMENT_GAP, 0)
        end
    end
end

-------------------------------------------------------------------------------
--  Frame construction (lazy, once). Large icon + a 4-segment tier bar under
--  it; detail text lives in the hover tooltip only.
-------------------------------------------------------------------------------
local function BuildFrame()
    if frame then return frame end

    local f = CreateFrame("Frame", "EllesmereUIPreyBar", UIParent)
    f:EnableMouse(true) -- hover tooltip only; unlock mode drags via its own overlay
    f:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOP", f, "TOP", 0, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:Hide()

    f.segments = {}
    for i = 1, SEGMENT_COUNT do
        local border = f:CreateTexture(nil, "BORDER")
        border:SetColorTexture(0, 0, 0, 1)

        local seg = f:CreateTexture(nil, "ARTWORK")
        seg:SetColorTexture(UNLIT_COLOR[1], UNLIT_COLOR[2], UNLIT_COLOR[3], UNLIT_COLOR[4])
        border:SetPoint("TOPLEFT", seg, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 1, -1)

        f.segments[i] = seg
    end

    frame = f
    ApplyLayout()

    f:SetScript("OnEnter", function(self)
        if EllesmereUI.ShowWidgetTooltip and self._tooltipText and self._tooltipText ~= "" then
            EllesmereUI.ShowWidgetTooltip(self, self._tooltipText, { anchor = "below" })
        end
    end)
    f:SetScript("OnLeave", function()
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Pulses only while the active widget reports hasTimer. Anchored to the
    -- icon corner, not the whole (taller, segment-bar-including) frame.
    f.timerDot = f:CreateTexture(nil, "OVERLAY")
    f.timerDot:SetColorTexture(1, 1, 1, 1)
    f.timerDot:SetSize(10, 10)
    f.timerDot:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", -2, 2)
    f.timerDot:Hide()
    f.timerAnim = f.timerDot:CreateAnimationGroup()
    f.timerAnim:SetLooping("BOUNCE")
    local a = f.timerAnim:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.15)
    a:SetDuration(0.6)
    a:SetSmoothing("IN_OUT")

    ApplyPosition()
    return f
end

-------------------------------------------------------------------------------
--  Icon mirroring: Blizzard's widget data (C_UIWidgetManager) carries no icon
--  field, only opaque texture-kit strings with an undocumented naming scheme.
--  Rather than guess an atlas name, copy whatever icon texture Blizzard's own
--  live widget frame is already showing for this widgetID.
-------------------------------------------------------------------------------
-- StateTexture is the widget's actual per-hunt/per-tier visual (confirmed via
-- the in-game diagnostic print below -- this widget has no separate "icon"
-- field, PriorStateTexture/Glow/HighlightTexture are transition-fade/mouseover
-- chrome, not content). Older generic names kept as a defensive fallback.
local ICON_FIELD_CANDIDATES = { "StateTexture", "Icon", "icon", "IconTexture", "iconTexture" }
local PREVIEW_ICON = 134400 -- generic placeholder (question mark), unlock-mode preview only
local _iconDebugPrinted = false

local function FindLiveWidgetFrame(widgetID)
    local uwb = UIWidgetPowerBarContainerFrame
    if not uwb then return nil end
    local frames = uwb.widgetFrames or uwb.WidgetFrames
    local f = frames and frames[widgetID]
    if f then return f end
    if uwb.GetChildren then
        for _, child in ipairs({ uwb:GetChildren() }) do
            if child.widgetID == widgetID then return child end
        end
    end
    return nil
end

local function DumpTextureFields(wf)
    local out = {}
    for k, v in pairs(wf) do
        if type(v) == "table" and v.GetObjectType then
            local ok, ot = pcall(v.GetObjectType, v)
            if ok and ot == "Texture" then out[#out + 1] = tostring(k) end
        end
    end
    return #out > 0 and table.concat(out, ", ") or "(none found)"
end

local function MirrorIcon(widgetID)
    local f = BuildFrame()
    local wf = FindLiveWidgetFrame(widgetID)
    if not wf then
        if not _iconDebugPrinted then
            _iconDebugPrinted = true
            print("|cff0cd29fEllesmereUI Prey Bar:|r could not locate the native widget frame for widgetID " .. tostring(widgetID) .. " -- icon left blank. Please report this.")
        end
        f.icon:Hide()
        return
    end
    for _, fname in ipairs(ICON_FIELD_CANDIDATES) do
        local tex = wf[fname]
        if type(tex) == "table" and tex.GetObjectType then
            local ok, ot = pcall(tex.GetObjectType, tex)
            if ok and ot == "Texture" then
                local atlas = tex.GetAtlas and tex:GetAtlas()
                if atlas then
                    f.icon:SetAtlas(atlas, false)
                    f.icon:Show()
                    return
                end
                local texFile = tex.GetTexture and tex:GetTexture()
                if texFile then
                    f.icon:SetTexture(texFile)
                    f.icon:Show()
                    return
                end
            end
        end
    end
    if not _iconDebugPrinted then
        _iconDebugPrinted = true
        print("|cff0cd29fEllesmereUI Prey Bar:|r found the widget frame but no icon texture on it -- icon left blank. Texture fields present: " .. DumpTextureFields(wf) .. ". Please report this.")
    end
    f.icon:Hide()
end

-------------------------------------------------------------------------------
--  Paint: tierIndex 0-3 (Cold..Final), tooltipText from Blizzard's own widget
--  data (raw game text, kept only as hover-tooltip content, never a permanent
--  label -- not an EUI UI string, so it's never run through the locale engine).
-------------------------------------------------------------------------------
local function Paint(tierIndex, tooltipText, hasTimer)
    local f = BuildFrame()
    local t = TIER[tierIndex] or TIER[0]
    f._tooltipText = (tooltipText and tooltipText ~= "" and tooltipText) or L(t.name)

    local lit = tierIndex + 1
    for i, seg in ipairs(f.segments) do
        if i <= lit then
            seg:SetColorTexture(t.r, t.g, t.b, 1)
        else
            seg:SetColorTexture(UNLIT_COLOR[1], UNLIT_COLOR[2], UNLIT_COLOR[3], UNLIT_COLOR[4])
        end
    end

    if hasTimer then
        f.timerDot:Show()
        f.timerAnim:Play()
    else
        f.timerAnim:Stop()
        f.timerDot:Hide()
    end

    f:Show()
end

-------------------------------------------------------------------------------
--  Blizzard's native container: hidden only while WE are actively showing a
--  Prey Hunt widget, so any other content it hosts (vigor, boss power bars)
--  is left completely alone the rest of the time.
-------------------------------------------------------------------------------
local function SetNativeHidden(hidden)
    local uwb = UIWidgetPowerBarContainerFrame
    if uwb then uwb:SetAlpha(hidden and 0 or 1) end
end

-------------------------------------------------------------------------------
--  Data: poll on demand, refresh on the targeted UPDATE_UI_WIDGET event.
-------------------------------------------------------------------------------
local function SetActive(isActive, info)
    active = isActive
    if previewOn then return end -- unlock-mode preview owns the display right now
    if isActive then
        Paint(info.progressState or 0, info.tooltip, info.hasTimer == true)
        SetNativeHidden(true)
    else
        if frame then frame:Hide(); frame.icon:Hide() end
        SetNativeHidden(false)
    end
end

local function RefreshWidget(widgetID)
    local info = widgetID and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widgetID)
    if info and info.shownState == WIDGET_SHOWN then
        MirrorIcon(widgetID)
        SetActive(true, info)
    else
        SetActive(false)
    end
end

local function PollPreyWidget()
    local setID = C_UIWidgetManager.GetPowerBarWidgetSetID and C_UIWidgetManager.GetPowerBarWidgetSetID()
    local widgets = setID and C_UIWidgetManager.GetAllWidgetsBySetID(setID)
    if widgets then
        for _, w in ipairs(widgets) do
            if w.widgetType == PREY_WIDGET_TYPE then
                RefreshWidget(w.widgetID)
                return
            end
        end
    end
    SetActive(false)
end

-------------------------------------------------------------------------------
--  Unlock mode: force a preview so the bar can be placed even with no hunt
--  currently active.
-------------------------------------------------------------------------------
local function SetPreview(on)
    previewOn = on
    if on then
        Paint(1, L("Prey Hunt"), false)
        frame.icon:SetTexture(PREVIEW_ICON)
        frame.icon:Show()
        ApplyPosition()
    elseif active then
        PollPreyWidget()
    else
        if frame then frame:Hide(); frame.icon:Hide() end
        SetNativeHidden(false)
    end
end

local function RegisterUnlock()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_PreyBar",
            label = "Prey Hunt Bar",
            group = "Quality of Life",
            order = 602,
            linkedDimensions = true, -- always square; one drag handle drives both
            noMatchSource = true, -- single Size value only; no separate width/height match targets
            isHidden = function() return false end,
            getFrame = function() return BuildFrame() end,
            getSize  = function() return GetIconSize(), GetIconSize() end,
            setWidth = function(_, w)
                P().size = math.max(24, math.floor(w + 0.5))
                ApplyLayout()
            end,
            setHeight = function(_, h)
                P().size = math.max(24, math.floor(h + 0.5))
                ApplyLayout()
            end,
            savePos = function()
                local f = BuildFrame()
                if not f:GetCenter() then return end
                local cx, cy = f:GetCenter()
                local upX, upY = UIParent:GetCenter()
                local ratio = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
                P().pos = { centerX = cx * ratio - upX, centerY = cy * ratio - upY }
            end,
            loadPos = function()
                local pos = P().pos
                if not (pos and pos.centerX and pos.centerY) then return nil end
                return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
            end,
            clearPos = function() P().pos = nil end,
            applyPos = function() ApplyPosition() end,
        }),
    }, "EllesmereUIQoL")

    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EUI_PreyBar", function(unlockActive)
            SetPreview(unlockActive == true)
        end)
    end
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        BuildFrame()
        RegisterUnlock()
        self:RegisterEvent("UPDATE_UI_WIDGET")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        PollPreyWidget()
    elseif event == "UPDATE_UI_WIDGET" then
        local widgetInfo = ...
        if widgetInfo and widgetInfo.widgetType == PREY_WIDGET_TYPE then
            RefreshWidget(widgetInfo.widgetID)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        PollPreyWidget()
    end
end)
