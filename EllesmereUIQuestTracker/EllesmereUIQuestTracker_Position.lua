if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EllesmereUIQuestTracker_Position.lua: the tracker as an Unlock Mode element.
-- Its spot and height go into the tracker's entry of the active Edit Mode
-- layout, so Blizzard's own layout apply places it and lifts it out of the
-- right-side managed container. Edit Mode applies a saved layout only on
-- reload, so leaving the default spot or changing the height asks for one.
local _, ns = ...
local EQT = ns.EQT

-- Edit Mode's Height slider: the stored value is (height - min) / step.
local HEIGHT_MIN, HEIGHT_MAX, HEIGHT_STEP = 400, 1000, 10

local emAnchor = { relativeTo = "UIParent" }
local hooked, changed, reloadOffered, resetPending, syncQueued, standIn, standInPlaced, sessionHeight
local selectionOff

-- Until its Edit Mode layout applies, the managed container places it.
local function Held()
    local f = _G.ObjectiveTrackerFrame
    return not f:IsInitialized() or f:IsInDefaultPosition()
end

-- The container puts a held tracker back in its slot on every tracker
-- update, so an unlock session moves a stand-in of the moved tracker's size.
local function UnlockFrame()
    local f = _G.ObjectiveTrackerFrame
    if not (EllesmereUI._unlockActive and Held()) then return f end
    if not standInPlaced then
        standInPlaced = true
        local cfg = EQT.DB()
        standIn = standIn or CreateFrame("Frame", nil, UIParent)
        standIn:SetSize(f:GetWidth(), cfg.height or f.editModeHeight or 800)
        standIn:ClearAllPoints()
        local pos = cfg.position
        if pos then
            standIn:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
        elseif f:GetLeft() then
            standIn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", f:GetLeft(), f:GetTop())
        end
    end
    return standIn
end

-- The merged layout list, the active layout and its tracker entry, and
-- whether that layout is a read-only preset. nil while Edit Mode is open or
-- before its layouts have been applied.
local function ResolveLayout()
    local f = _G.ObjectiveTrackerFrame
    if not (f and f:IsInitialized()) or EllesmereUI.EditModeOpen() then return nil end
    local blob, numPresets = EllesmereUI.EditModeLayoutsForSave()
    if not blob or type(blob.activeLayout) ~= "number" then return nil end
    local entry = blob.layouts[blob.activeLayout]
    if type(entry) ~= "table" or type(entry.systems) ~= "table" then return nil end
    for _, sys in ipairs(entry.systems) do
        if sys.system == Enum.EditModeSystem.ObjectiveTracker then
            return blob, entry, sys, blob.activeLayout <= numPresets
        end
    end
end

local function HeightRow(sys)
    for _, row in ipairs(sys.settings) do
        if row.setting == Enum.EditModeObjectiveTrackerSetting.Height then return row end
    end
end

local function AnchorAgrees(sys)
    local ai = sys.anchorInfo
    return not sys.isInDefaultPosition and sys.anchorInfo2 == nil and type(ai) == "table"
        and ai.point == emAnchor.point and ai.relativeTo == emAnchor.relativeTo
        and ai.relativePoint == emAnchor.relativePoint
        and math.abs((ai.offsetX or 0) - emAnchor.offsetX) < 0.1
        and math.abs((ai.offsetY or 0) - emAnchor.offsetY) < 0.1
end

-- Writes the saved spot and height into the active layout where it holds
-- anything else. "preset" when that layout cannot be saved.
local function WriteLayout(cfg)
    local blob, entry, sys, isPreset = ResolveLayout()
    if not sys then return end
    local pos = cfg.position
    local scale = _G.ObjectiveTrackerFrame:GetScale()
    emAnchor.point, emAnchor.relativePoint = pos.point, pos.relPoint or pos.point
    emAnchor.offsetX, emAnchor.offsetY = pos.x * scale, pos.y * scale
    local row = HeightRow(sys)
    local value = cfg.height and (cfg.height - HEIGHT_MIN) / HEIGHT_STEP
    local anchorOK = AnchorAgrees(sys)
    local heightOK = not value or (row and row.value == value)
    if anchorOK and heightOK then return end
    if isPreset then return "preset" end
    if not anchorOK then
        EllesmereUI.NoteEditModeAnchor(entry, sys, emAnchor)
        sys.anchorInfo = {
            point = emAnchor.point, relativeTo = emAnchor.relativeTo, relativePoint = emAnchor.relativePoint,
            offsetX = emAnchor.offsetX, offsetY = emAnchor.offsetY,
        }
        sys.anchorInfo2 = nil
        sys.isInDefaultPosition = false
    end
    if not heightOK then
        if row then
            EllesmereUI.NoteEditModeSetting(entry, sys, row.setting, row.value, value)
            row.value = value
        else
            sys.settings[#sys.settings + 1] = { setting = Enum.EditModeObjectiveTrackerSetting.Height, value = value }
        end
    end
    C_EditMode.SaveLayouts(blob)
    return true
end

-- Back to Edit Mode's default spot, as its own Reset To Default Position.
local function ResetLayout()
    local blob, entry, sys, isPreset = ResolveLayout()
    if not sys or isPreset or sys.isInDefaultPosition then return false end
    local def = EditModePresetLayoutManager:GetDefaultSystemAnchorInfo(Enum.EditModeSystem.ObjectiveTracker)
    EllesmereUI.NoteEditModeAnchor(entry, sys, def)
    sys.anchorInfo = def
    sys.anchorInfo2 = nil
    sys.isInDefaultPosition = true
    C_EditMode.SaveLayouts(blob)
    return true
end

-- While we own the spot, Edit Mode's selection box cannot pick the tracker
-- up: a drag there would be overwritten by the next sync. Only a selection
-- turned off here is turned back on.
local function SetEditModeSelectable(on)
    if on and not selectionOff then return end
    selectionOff = not on
    EllesmereUI.SetEditModeChildInert(_G.ObjectiveTrackerFrame.Selection, not on)
end

local function OfferReload()
    if reloadOffered then return end
    reloadOffered = true
    EllesmereUI:ShowConfirmPopup({
        title = "Reload to Move the Quest Tracker",
        message = "The quest tracker's new position and height are saved to your Edit Mode layout. Blizzard applies them after a reload.",
        confirmText = "Reload",
        cancelText = "Not Now",
        reload = true,
    })
end

local function WarnPreset()
    EllesmereUI:ShowConfirmPopup({
        title = "Copy Your Edit Mode Layout",
        message = "Your active Edit Mode layout is one of Blizzard's presets, which cannot be changed. Copy it in Edit Mode, then move the quest tracker again.",
        confirmText = "Okay",
        hideCancel = true,
    })
end

function EQT.SyncPosition()
    syncQueued = nil
    local cfg = EQT.DB()
    if EllesmereUI._unlockActive then return end
    -- A profile with no spot of ours hands the selection back to Edit Mode.
    if not cfg.position then
        SetEditModeSelectable(true)
        return
    end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("QTPosition", EQT.SyncPosition)
        return
    end
    if not hooked then
        hooked = true
        -- Every layout apply (login, layout or spec switch, Edit Mode exit)
        -- re-checks the active layout against the saved spot.
        hooksecurefunc(_G.ObjectiveTrackerFrame, "ApplySystemAnchor", function()
            if syncQueued or not EQT.DB().position then return end
            syncQueued = true
            C_Timer.After(0, EQT.SyncPosition)
        end)
    end
    -- Leaving Edit Mode re-applies the layout, which syncs again.
    if EllesmereUI.EditModeOpen() then return end
    local userChange = changed
    changed = nil
    if WriteLayout(cfg) == "preset" then
        if userChange then WarnPreset() end
        return
    end
    local f = _G.ObjectiveTrackerFrame
    if not f:IsInitialized() then return end
    SetEditModeSelectable(false)
    -- Edit Mode has not applied the written spot or height yet.
    if f:IsInDefaultPosition() or (cfg.height and f.editModeHeight ~= cfg.height) then
        OfferReload()
        return
    end
    local pos = cfg.position
    EllesmereUI.ClearFramePoints(f)
    EllesmereUI.SetFramePoint(f, pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    -- The login anchor pass may have run while the tracker was still held.
    EllesmereUI.ReapplyUnlockAnchor("EQT_Tracker")
end

local function ApplyReset()
    resetPending = nil
    if InCombatLockdown() then
        ns.CombatQueue.Defer("QTPositionReset", ApplyReset)
        return
    end
    if EQT.DB().position then return end
    SetEditModeSelectable(true)
    if ResetLayout() then OfferReload() end
end

function EQT.InitPosition()
    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key   = "EQT_Tracker",
            label = "Quest Tracker",
            group = "Quest Tracker",
            order = 560,
            getFrame = UnlockFrame,
            getSize  = function()
                local f = UnlockFrame()
                return f:GetWidth(), EQT.DB().height or f:GetHeight()
            end,
            isHidden = function() return not EQT.Cfg("enabled") end,
            isPositionHeld = Held,
            -- The shared Edit Mode layout holds the spot, and a change takes a
            -- reload: one spot for every spec.
            noSpecLayout = true,
            setHeight = function(_, h)
                h = math.floor(h / HEIGHT_STEP + 0.5) * HEIGHT_STEP
                h = math.max(HEIGHT_MIN, math.min(HEIGHT_MAX, h))
                EQT.Set("height", h)
                if standInPlaced then standIn:SetHeight(h) end
                if EllesmereUI._unlockActive then changed = true else EQT.SyncPosition() end
            end,
            -- Saved by its top edge: the tracker grows down, and a moved
            -- tracker takes its Height setting.
            savePos = function(_, point, relPoint, x, y)
                if point == "CENTER" then
                    point, relPoint, y = "TOP", "CENTER", y + UnlockFrame():GetHeight() / 2
                end
                EQT.Set("position", { point = point, relPoint = relPoint or point, x = x, y = y })
                if EllesmereUI._unlockActive then changed = true else EQT.SyncPosition() end
            end,
            loadPos = function() return EQT.Cfg("position") end,
            clearPos = function()
                EQT.Set("position", nil)
                EQT.Set("height", nil)
                if EllesmereUI._unlockActive then
                    resetPending = true
                else
                    ApplyReset()
                end
            end,
            applyPos = function() EQT.SyncPosition() end,
        }),
    }, "EllesmereUIQuestTracker")

    -- Layout writes and reload prompts wait for the session to close.
    EllesmereUI:RegisterUnlockModeListener("EllesmereUIQuestTracker", function(active, closeAction)
        if active then
            sessionHeight = EQT.DB().height
            return
        end
        standInPlaced = nil
        -- The discard revert sets the snapshot height even when none was stored.
        if closeAction ~= "save" then EQT.Set("height", sessionHeight) end
        if closeAction ~= "save" or not EQT.DB().position then changed = nil end
        if resetPending then ApplyReset() end
        EQT.SyncPosition()
    end)

    EQT.SyncPosition()
end
