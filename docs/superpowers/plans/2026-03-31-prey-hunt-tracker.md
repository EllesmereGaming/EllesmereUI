# EllesmereUIPreyHunt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an EllesmereUI child addon that tracks Prey Hunt progress with three display modes (smooth bar, stage segments, compact indicator), auto-shows during active hunts, and integrates with unlock mode.

**Architecture:** Isolated child addon `EllesmereUIPreyHunt/` using `EUILite.NewAddon()`. Data layer reads `C_UIWidgetManager` for hunt stages (with stub detection until Midnight ships). Display frame auto-shows in prey zones, registers with unlock mode for positioning. Options page in EllesmereUI panel.

**Tech Stack:** WoW Lua, EllesmereUI framework (EUILite, Widgets, PP, MakeBorder, MakeFont, ShowWidgetTooltip, RegisterUnlockElements, RegisterModule)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `EllesmereUIPreyHunt/EllesmereUIPreyHunt.toc` | TOC, dependencies, load order |
| `EllesmereUIPreyHunt/EllesmereUIPreyHunt.lua` | Core: data layer, frame, 3 display modes, auto-show, unlock registration |
| `EllesmereUIPreyHunt/EUI_PreyHunt_Options.lua` | Options page: mode picker, size, opacity, label toggle |

---

### Task 1: Create branch and TOC file

**Files:**
- Create: `EllesmereUIPreyHunt/EllesmereUIPreyHunt.toc`

- [ ] **Step 1: Create feature branch from main**

```bash
cd c:/Users/danie/Documents/GitHub/EllesmereUI
git checkout main
git checkout -b prey-hunt
```

- [ ] **Step 2: Create the TOC file**

Create `EllesmereUIPreyHunt/EllesmereUIPreyHunt.toc`:

```
## Interface: 120000, 120001
## Title: |cff0cd29fEllesmereUI|r Prey Hunt
## Category: |cff0cd29fEllesmere|rUI
## Group: EllesmereUI
## Notes: Prey Hunt progress tracker in EllesmereUI style
## Author: bulshack
## Version: 1.0
## Dependencies: EllesmereUI
## SavedVariables: EllesmereUIPreyHuntDB
## IconTexture: Interface\AddOns\EllesmereUI\media\eg-logo.tga

EllesmereUIPreyHunt.lua
EUI_PreyHunt_Options.lua
```

- [ ] **Step 3: Add to .pkgmeta move-folders**

Add this line to the `move-folders:` section in `.pkgmeta`:

```yaml
  EllesmereUI/EllesmereUIPreyHunt: EllesmereUIPreyHunt
```

- [ ] **Step 4: Commit**

```bash
git add EllesmereUIPreyHunt/EllesmereUIPreyHunt.toc .pkgmeta
git commit -m "feat(prey-hunt): add TOC and pkgmeta entry"
```

---

### Task 2: Core addon scaffold — data layer and state

**Files:**
- Create: `EllesmereUIPreyHunt/EllesmereUIPreyHunt.lua`

- [ ] **Step 1: Write the full core addon file**

Create `EllesmereUIPreyHunt/EllesmereUIPreyHunt.lua`:

```lua
--------------------------------------------------------------------------------
--  EllesmereUIPreyHunt.lua
--  Prey Hunt progress tracker for EllesmereUI
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EPH = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.EPH = EPH

local PP = EllesmereUI.PP
local floor = math.floor

--------------------------------------------------------------------------------
--  Constants
--------------------------------------------------------------------------------
local FONT_PATH = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
local MEDIA_PATH = "Interface\\AddOns\\EllesmereUI\\media\\"

--------------------------------------------------------------------------------
--  Defaults
--------------------------------------------------------------------------------
local DEFAULTS = {
    profile = {
        enabled       = true,
        displayMode   = "bar",       -- "bar" | "segments" | "compact"
        barWidth      = 220,
        barHeight     = 16,
        opacity       = 1.0,
        showLabel     = true,
        animateFill   = true,
    },
}

--------------------------------------------------------------------------------
--  Hunt State
--------------------------------------------------------------------------------
local huntState = {
    active    = false,
    stage     = 0,
    maxStages = 5,
    zoneName  = "",
    difficulty = "",
    widgetID  = nil,
}

--------------------------------------------------------------------------------
--  Widget Detection (stub — will be wired to real IDs on Midnight PTR/launch)
--
--  The Prey Hunt system uses C_UIWidgetManager. Until Midnight ships, we
--  provide a stub that can be tested with /ephtest. Replace the body of
--  ScanForPreyHuntWidget() once real widget IDs are known.
--------------------------------------------------------------------------------

-- TODO: Replace with real widget type + ID detection when Midnight is live.
-- Expected approach:
--   1. On zone enter, iterate C_UIWidgetManager.GetAllWidgetsBySetID(
--        C_UIWidgetManager.GetTopCenterWidgetSetID())
--   2. Check each widget for prey-hunt-specific visualization type
--        (likely GetStatusBarWidgetVisualizationInfo or
--         GetFillUpFramesWidgetVisualizationInfo)
--   3. Store the widgetID and read stage/max from the widget data

local function ScanForPreyHuntWidget()
    -- STUB: Always returns nil until we have real widget IDs.
    -- When Midnight ships, this will scan C_UIWidgetManager for the
    -- prey hunt widget and return { widgetID, stage, maxStages, zoneName, difficulty }.
    return nil
end

local function UpdateHuntStateFromWidget()
    local data = ScanForPreyHuntWidget()
    if data then
        huntState.active    = true
        huntState.stage     = data.stage or 0
        huntState.maxStages = data.maxStages or 5
        huntState.zoneName  = data.zoneName or ""
        huntState.difficulty = data.difficulty or ""
        huntState.widgetID  = data.widgetID
        return true
    end
    huntState.active = false
    return false
end

--------------------------------------------------------------------------------
--  Debug / Test Commands
--------------------------------------------------------------------------------
local testMode = false
local testStage = 0
local testMax = 5

local function SetTestHunt(stage, maxStages, zone, diff)
    testMode = true
    huntState.active    = true
    huntState.stage     = stage or 3
    huntState.maxStages = maxStages or 5
    huntState.zoneName  = zone or "Dawnbreaker Crest"
    huntState.difficulty = diff or "Heroic"
end

local function ClearTestHunt()
    testMode = false
    huntState.active = false
    huntState.stage = 0
end

SLASH_EPHTEST1 = "/ephtest"
SlashCmdList.EPHTEST = function(msg)
    local args = msg and msg:trim():lower() or ""
    if args == "off" or args == "clear" then
        ClearTestHunt()
        EPH:Refresh()
        print("|cff0cd29f[PreyHunt]|r Test mode off.")
        return
    end
    local stage = tonumber(args)
    if stage then
        SetTestHunt(stage, testMax)
    else
        -- Toggle: advance stage or start at 1
        testStage = testStage + 1
        if testStage > testMax then testStage = 1 end
        SetTestHunt(testStage, testMax)
    end
    EPH:Refresh()
    print("|cff0cd29f[PreyHunt]|r Test: stage " .. huntState.stage .. "/" .. huntState.maxStages)
end

--------------------------------------------------------------------------------
--  Accent Color Helper
--------------------------------------------------------------------------------
local function GetAccent()
    if EllesmereUI.GetAccentColor then
        return EllesmereUI.GetAccentColor()
    end
    return 0.047, 0.824, 0.624
end

--------------------------------------------------------------------------------
--  Main Frame
--------------------------------------------------------------------------------
local mainFrame = nil
local fillBar, fillAnim
local segmentFrames = {}
local compactIcon, compactText
local stageLabel, infoLabel

local function GetDB()
    return EPH.db and EPH.db.profile
end

local function CreateMainFrame()
    if mainFrame then return end
    local db = GetDB()
    if not db then return end

    mainFrame = CreateFrame("Frame", "EllesmereUIPreyHuntFrame", UIParent)
    mainFrame:SetSize(db.barWidth, db.barHeight)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetFrameLevel(5)
    mainFrame:Hide()

    -- Background
    local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.07, 0.09, 0.80)
    mainFrame._bg = bg

    -- Border
    mainFrame._border = EllesmereUI.MakeBorder(mainFrame, 1, 1, 1, 0.10)

    -- Fill bar (smooth bar mode)
    fillBar = mainFrame:CreateTexture(nil, "ARTWORK")
    fillBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 1, -1)
    fillBar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 1, 1)
    local aR, aG, aB = GetAccent()
    fillBar:SetColorTexture(aR, aG, aB, 0.85)
    fillBar:SetWidth(0)
    mainFrame._fill = fillBar

    -- Stage label (inside bar, right side)
    stageLabel = mainFrame:CreateFontString(nil, "OVERLAY")
    stageLabel:SetFont(FONT_PATH, 10, "OUTLINE")
    stageLabel:SetPoint("RIGHT", mainFrame, "RIGHT", -6, 0)
    stageLabel:SetTextColor(1, 1, 1, 0.9)
    mainFrame._stageLabel = stageLabel

    -- Info label (above bar — zone + difficulty)
    infoLabel = mainFrame:CreateFontString(nil, "OVERLAY")
    infoLabel:SetFont(FONT_PATH, 10, "")
    infoLabel:SetPoint("BOTTOMLEFT", mainFrame, "TOPLEFT", 0, 4)
    infoLabel:SetTextColor(1, 1, 1, 0.45)
    mainFrame._infoLabel = infoLabel

    -- Compact mode: icon + text (hidden by default)
    compactIcon = mainFrame:CreateTexture(nil, "OVERLAY")
    compactIcon:SetSize(20, 20)
    compactIcon:SetPoint("LEFT", mainFrame, "LEFT", 4, 0)
    compactIcon:SetTexture(136814)  -- generic crosshair icon; replace with prey icon later
    compactIcon:SetVertexColor(aR, aG, aB, 0.9)
    compactIcon:Hide()
    mainFrame._compactIcon = compactIcon

    compactText = mainFrame:CreateFontString(nil, "OVERLAY")
    compactText:SetFont(FONT_PATH, 13, "")
    compactText:SetPoint("LEFT", compactIcon, "RIGHT", 6, 0)
    compactText:SetTextColor(aR, aG, aB, 1)
    compactText:Hide()
    mainFrame._compactText = compactText

    -- Tooltip on hover
    mainFrame:SetScript("OnEnter", function(self)
        if not huntState.active then return end
        local tip = "Prey Hunt"
        if huntState.zoneName ~= "" then
            tip = tip .. "\n" .. huntState.zoneName
        end
        if huntState.difficulty ~= "" then
            tip = tip .. "  |cff0cd29f(" .. huntState.difficulty .. ")|r"
        end
        tip = tip .. "\n\nProgress: Stage " .. huntState.stage .. " / " .. huntState.maxStages
        if huntState.stage >= huntState.maxStages then
            tip = tip .. "\n\n|cff0cd29fPrey location revealed!|r"
        else
            tip = tip .. "\n\nComplete quests, kill rares, loot treasures,\nand find traps to fill the bar."
        end
        EllesmereUI.ShowWidgetTooltip(self, tip, { anchor = "below" })
    end)
    mainFrame:SetScript("OnLeave", function()
        EllesmereUI.HideWidgetTooltip()
    end)
end

--------------------------------------------------------------------------------
--  Segment Frames (stage segment mode)
--------------------------------------------------------------------------------
local function CreateOrUpdateSegments()
    local db = GetDB()
    if not db or not mainFrame then return end
    local aR, aG, aB = GetAccent()
    local max = huntState.maxStages
    if max < 1 then max = 5 end
    local gap = 1
    local totalGaps = (max - 1) * gap + 2  -- 1px border each side
    local segW = (db.barWidth - totalGaps) / max
    local segH = db.barHeight - 2  -- 1px border top/bottom

    -- Hide extras
    for i = max + 1, #segmentFrames do
        segmentFrames[i]:Hide()
    end

    for i = 1, max do
        local seg = segmentFrames[i]
        if not seg then
            seg = mainFrame:CreateTexture(nil, "ARTWORK")
            segmentFrames[i] = seg
        end
        seg:ClearAllPoints()
        seg:SetSize(segW, segH)
        local xOff = 1 + (i - 1) * (segW + gap)
        seg:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, -1)

        if i <= huntState.stage then
            seg:SetColorTexture(aR, aG, aB, 0.85)
        else
            seg:SetColorTexture(1, 1, 1, 0.04)
        end
        seg:Show()
    end
end

--------------------------------------------------------------------------------
--  Display Refresh
--------------------------------------------------------------------------------
local targetFillWidth = 0
local currentFillWidth = 0

local function RefreshDisplay()
    local db = GetDB()
    if not db or not mainFrame then return end
    if not huntState.active then
        mainFrame:Hide()
        return
    end

    local aR, aG, aB = GetAccent()
    local mode = db.displayMode
    local barW = db.barWidth
    local barH = db.barHeight

    mainFrame:SetSize(barW, barH)
    mainFrame:SetAlpha(db.opacity)

    -- Info label
    if db.showLabel and huntState.zoneName ~= "" then
        local info = huntState.zoneName
        if huntState.difficulty ~= "" then
            info = info .. "  |cff0cd29f" .. huntState.difficulty .. "|r"
        end
        infoLabel:SetText(info)
        infoLabel:Show()
    else
        infoLabel:Hide()
    end

    -- Hide all mode-specific elements first
    fillBar:Hide()
    stageLabel:Hide()
    compactIcon:Hide()
    compactText:Hide()
    for _, seg in ipairs(segmentFrames) do seg:Hide() end
    mainFrame._bg:Show()
    mainFrame._border:Show()

    local pct = huntState.maxStages > 0 and (huntState.stage / huntState.maxStages) or 0

    if mode == "bar" then
        -- Smooth bar
        fillBar:SetColorTexture(aR, aG, aB, 0.85)
        targetFillWidth = (barW - 2) * pct
        if not db.animateFill then
            currentFillWidth = targetFillWidth
        end
        fillBar:SetWidth(math.max(currentFillWidth, 0.01))
        fillBar:Show()

        stageLabel:SetText(huntState.stage .. " / " .. huntState.maxStages)
        stageLabel:Show()

    elseif mode == "segments" then
        -- Stage segments
        CreateOrUpdateSegments()
        stageLabel:SetText(huntState.stage .. " / " .. huntState.maxStages)
        stageLabel:SetPoint("RIGHT", mainFrame, "RIGHT", -6, 0)
        stageLabel:Show()

    elseif mode == "compact" then
        -- Compact: smaller frame, icon + text
        mainFrame:SetSize(100, 28)
        mainFrame._bg:SetColorTexture(0.05, 0.07, 0.09, 0.70)

        compactIcon:SetVertexColor(aR, aG, aB, 0.9)
        compactIcon:Show()

        compactText:SetTextColor(aR, aG, aB, 1)
        compactText:SetText(huntState.stage .. " / " .. huntState.maxStages)
        compactText:Show()

        infoLabel:Hide()  -- too small for label in compact
    end

    mainFrame:Show()
end

-- Smooth fill animation
local function OnUpdateFill(self, dt)
    if not mainFrame or not mainFrame:IsShown() then return end
    local db = GetDB()
    if not db or db.displayMode ~= "bar" or not db.animateFill then return end

    if math.abs(currentFillWidth - targetFillWidth) > 0.5 then
        local speed = 8  -- pixels per second multiplier
        local delta = (targetFillWidth - currentFillWidth) * math.min(dt * speed, 1)
        currentFillWidth = currentFillWidth + delta
        fillBar:SetWidth(math.max(currentFillWidth, 0.01))
    end
end

--------------------------------------------------------------------------------
--  Public API
--------------------------------------------------------------------------------
function EPH:Refresh()
    if not testMode then
        UpdateHuntStateFromWidget()
    end
    RefreshDisplay()
end

--------------------------------------------------------------------------------
--  Event Handling
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    local db = GetDB()
    if not db or not db.enabled then
        if mainFrame then mainFrame:Hide() end
        return
    end

    if event == "UPDATE_UI_WIDGET" then
        local widgetInfo = ...
        -- If we're tracking a specific widget, only refresh on that one
        if huntState.widgetID and widgetInfo and widgetInfo.widgetID ~= huntState.widgetID then
            return
        end
    end

    EPH:Refresh()
end

--------------------------------------------------------------------------------
--  Unlock Mode Registration
--------------------------------------------------------------------------------
local function RegisterWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end

    local function S() return GetDB() or {} end

    local function savePos(key, point, relPoint, x, y)
        if not point then return end
        local db = S()
        db.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
        if not EllesmereUI._unlockActive and mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(point, UIParent, relPoint or point, x, y)
        end
    end

    local function loadPos()
        local pos = S().unlockPos
        if not pos then return nil end
        return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
    end

    local function clearPos()
        local db = S()
        db.unlockPos = nil
    end

    local function applyPos()
        local pos = S().unlockPos
        if not pos or not mainFrame then return end
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    end

    EllesmereUI:RegisterUnlockElements({
        {
            key       = "PreyHunt",
            label     = "Prey Hunt",
            group     = "Prey Hunt",
            order     = 600,
            getFrame  = function() return mainFrame end,
            getSize   = function()
                local db = S()
                return db.barWidth or 220, db.barHeight or 16
            end,
            setWidth  = function(_, w)
                local db = S()
                db.barWidth = floor(w + 0.5)
                EPH:Refresh()
            end,
            setHeight = function(_, h)
                local db = S()
                db.barHeight = floor(h + 0.5)
                EPH:Refresh()
            end,
            savePos  = savePos,
            loadPos  = loadPos,
            clearPos = clearPos,
            applyPos = applyPos,
        },
    })
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function EPH:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUIPreyHuntDB", DEFAULTS, true)

    _G._EPH_AceDB = self.db
    _G._EPH_Apply = function() EPH:Refresh() end
    _G._EPH_RegisterUnlock = RegisterWithUnlockMode
end

function EPH:OnEnable()
    CreateMainFrame()

    -- Apply saved position
    local db = GetDB()
    if db and db.unlockPos then
        local pos = db.unlockPos
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    end

    -- Fill animation ticker
    mainFrame:SetScript("OnUpdate", OnUpdateFill)

    -- Events
    eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Register with unlock mode (deferred)
    C_Timer.After(0.5, RegisterWithUnlockMode)

    -- Initial scan
    C_Timer.After(1, function() EPH:Refresh() end)
end
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUIPreyHunt/EllesmereUIPreyHunt.lua
git commit -m "feat(prey-hunt): core addon with data layer, 3 display modes, unlock registration"
```

---

### Task 3: Options page

**Files:**
- Create: `EllesmereUIPreyHunt/EUI_PreyHunt_Options.lua`

- [ ] **Step 1: Write the options page**

Create `EllesmereUIPreyHunt/EUI_PreyHunt_Options.lua`:

```lua
--------------------------------------------------------------------------------
--  EUI_PreyHunt_Options.lua
--  Options page for EllesmereUIPreyHunt
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_SETTINGS = "Settings"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local db
    C_Timer.After(0, function() db = _G._EPH_AceDB end)

    local function DB()
        if not db then db = _G._EPH_AceDB end
        return db and db.profile
    end

    local function Refresh()
        if _G._EPH_Apply then _G._EPH_Apply() end
    end

    ---------------------------------------------------------------------------
    --  Page Builder
    ---------------------------------------------------------------------------
    local function BuildSettingsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local _, h
        local y = yOffset

        ---------------------------------------------------------------
        --  DISPLAY section
        ---------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Row 1: Display Mode | Bar Opacity
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Display Mode",
              values = { bar = "Smooth Bar", segments = "Stage Segments", compact = "Compact" },
              order  = { "bar", "segments", "compact" },
              tooltip = "Smooth Bar: animated fill bar.\nStage Segments: divided chunks per stage.\nCompact: small icon with stage count.",
              getValue = function() return DB().displayMode end,
              setValue = function(v) DB().displayMode = v; Refresh(); EllesmereUI:RefreshPage() end },
            { type = "slider", text = "Opacity", min = 0.3, max = 1.0, step = 0.05,
              tooltip = "Overall opacity of the prey hunt tracker.",
              getValue = function() return DB().opacity end,
              setValue = function(v) DB().opacity = v; Refresh() end }
        );  y = y - h

        -- Row 2: Bar Width | Bar Height
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Bar Width", min = 100, max = 400, step = 1,
              tooltip = "Width of the prey hunt bar in pixels.",
              getValue = function() return DB().barWidth end,
              setValue = function(v) DB().barWidth = v; Refresh() end },
            { type = "slider", text = "Bar Height", min = 8, max = 32, step = 1,
              tooltip = "Height of the prey hunt bar in pixels.",
              getValue = function() return DB().barHeight end,
              setValue = function(v) DB().barHeight = v; Refresh() end }
        );  y = y - h

        ---------------------------------------------------------------
        --  OPTIONS section
        ---------------------------------------------------------------
        _, h = W:SectionHeader(parent, "OPTIONS", y);  y = y - h

        -- Row 3: Show Label | Animate Fill
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Zone Label",
              tooltip = "Display the zone name and difficulty above the bar.",
              getValue = function() return DB().showLabel end,
              setValue = function(v) DB().showLabel = v; Refresh() end },
            { type = "toggle", text = "Animate Fill",
              tooltip = "Smoothly animate the bar fill when the stage changes.",
              getValue = function() return DB().animateFill end,
              setValue = function(v) DB().animateFill = v; Refresh() end }
        );  y = y - h

        ---------------------------------------------------------------
        --  TEST section
        ---------------------------------------------------------------
        _, h = W:SectionHeader(parent, "TESTING", y);  y = y - h

        -- Info text
        do
            local CONTENT_PAD = 45
            local infoRow = CreateFrame("Frame", nil, parent)
            infoRow:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 40)
            infoRow:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

            local infoText = EllesmereUI.MakeFont(infoRow, 11, nil, 1, 1, 1)
            infoText:SetAlpha(0.45)
            infoText:SetPoint("LEFT", infoRow, "LEFT", 20, 0)
            infoText:SetText("Type  /ephtest  to simulate hunt progress.  /ephtest off  to stop.")
            y = y - 40
        end

        return y
    end

    ---------------------------------------------------------------------------
    --  Register Module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIPreyHunt", {
        title       = "Prey Hunt",
        description = "Track Prey Hunt progress in EllesmereUI style.",
        pages       = { PAGE_SETTINGS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_SETTINGS then
                return BuildSettingsPage(pageName, parent, yOffset)
            end
        end,
    })
end)
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUIPreyHunt/EUI_PreyHunt_Options.lua
git commit -m "feat(prey-hunt): options page with display mode, size, opacity, labels"
```

---

### Task 4: Deploy to live WoW and test

**Files:**
- No new files — copy to AddOns folder

- [ ] **Step 1: Copy addon to WoW AddOns**

```bash
mkdir -p "D:/World of Warcraft/_retail_/Interface/AddOns/EllesmereUIPreyHunt"
cp "c:/Users/danie/Documents/GitHub/EllesmereUI/EllesmereUIPreyHunt/"* "D:/World of Warcraft/_retail_/Interface/AddOns/EllesmereUIPreyHunt/"
```

- [ ] **Step 2: Verify files are in place**

```bash
ls "D:/World of Warcraft/_retail_/Interface/AddOns/EllesmereUIPreyHunt/"
```

Expected output: `EllesmereUIPreyHunt.lua  EllesmereUIPreyHunt.toc  EUI_PreyHunt_Options.lua`

- [ ] **Step 3: Test in-game**

1. `/reload` in WoW
2. Open EllesmereUI options — "Prey Hunt" should appear as a module
3. Type `/ephtest` — the bar should appear with stage 1/5
4. Type `/ephtest` again — advances to 2/5, 3/5, etc.
5. Type `/ephtest off` — bar hides
6. Change display mode in options — bar style should change
7. Enter unlock mode — "Prey Hunt" element should be draggable
8. Adjust sliders for width/height/opacity — bar updates live

- [ ] **Step 4: Commit any fixes needed**

```bash
git add -A
git commit -m "fix(prey-hunt): adjustments from in-game testing"
```

---

### Task 5: Push and final verification

- [ ] **Step 1: Push branch**

```bash
cd c:/Users/danie/Documents/GitHub/EllesmereUI
git push -u origin prey-hunt
```

- [ ] **Step 2: Verify branch on GitHub**

```bash
gh browse -b prey-hunt
```

- [ ] **Step 3: Verify module can be disabled**

In-game: disable "Prey Hunt" in EllesmereUI module list. Confirm the bar disappears and no Lua errors. Re-enable and confirm it comes back.
