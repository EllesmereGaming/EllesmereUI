# Party Frames Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable party frames to EllesmereUIUnitFrames using oUF SpawnHeader, reusing existing component builders via the addon namespace.

**Architecture:** Hybrid Header — oUF:SpawnHeader manages group lifecycle (create/destroy/sort/visibility), while a new StylePartyFrame function reuses existing component builders (CreateHealthBar, CreatePowerBar, etc.) exposed via the `ns` namespace table. New code lives in EllesmereUIPartyFrames.lua, loaded after the main file.

**Tech Stack:** Lua (WoW addon), oUF unit frame framework, Blizzard SecureGroupHeaderTemplate

**Spec:** `docs/superpowers/specs/2026-03-17-party-frames-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua` | Modify | Add party defaults, extend UnitToSettingsKey/GetSettingsForUnit, expose builders via ns, call SpawnPartyHeader, register Unlock Mode |
| `EllesmereUIUnitFrames/EllesmereUIPartyFrames.lua` | Create | StylePartyFrame, SpawnPartyHeader, UpdatePartyLayout, role icon, aura filter, range fade, CDM registration |
| `EllesmereUIUnitFrames/EllesmereUIUnitFrames.toc` | Modify | Add EllesmereUIPartyFrames.lua to load order |
| `EllesmereUI.lua` | Modify | Add EllesmereUI party frames to PARTY_FRAME_SOURCES for CDM integration |

---

## Chunk 1: Foundation — Defaults, Mappings, and ns Exports

### Task 1: Add party defaults and enabledFrames entry

**Files:**
- Modify: `EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua:476-498`

- [ ] **Step 1: Add `party = true` to `enabledFrames`**

In `defaults.profile.enabledFrames` (line 477), add `party = true` after `boss = true`:

```lua
enabledFrames = {
    player = true,
    target = true,
    focus = true,
    pet = true,
    targettarget = true,
    focustarget = false,
    boss = true,
    party = true,
},
```

- [ ] **Step 2: Add `party` position to `positions`**

In `defaults.profile.positions` (line 486), add after the `classPower` entry:

```lua
party = { point = "TOPLEFT", x = 20, y = -40 },
```

- [ ] **Step 3: Add the full `party` defaults sub-table**

After the `boss` defaults sub-table (around line 476, before `enabledFrames`) add:

```lua
party = {
    frameWidth = 160,
    healthHeight = 36,
    powerPosition = "below",
    powerHeight = 4,
    leftTextContent = "name",
    rightTextContent = "perhp",
    centerTextContent = "none",
    textSize = 11,
    healthBarOpacity = 90,
    powerBarOpacity = 100,
    showPortrait = false,
    showRoleIcon = true,
    showCastbar = false,
    showThreat = true,
    enableRangeFade = true,
    rangeFadeAlpha = 0.4,
    showDebuffs = true,
    maxDebuffs = 3,
    showBuffs = false,
    maxBuffs = 0,
    highlightDispellable = true,
    growthDirection = "vertical",
    sortOrder = "role",
    spacing = 1,
    showPlayer = false,
},
```

- [ ] **Step 4: Add "party" to the opacity normalization list in ReloadFrames**

In `ReloadFrames()` (line 3981), add `"party"` to the UNITS table:

```lua
local UNITS = { "player", "target", "focus", "boss", "pet", "totPet", "party" }
```

- [ ] **Step 5: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua
git commit -m "feat(party): add party frame defaults and enabledFrames entry"
```

---

### Task 2: Extend UnitToSettingsKey and GetSettingsForUnit

**Files:**
- Modify: `EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua:610-868`

- [ ] **Step 1: Add party pattern to UnitToSettingsKey**

At line 612, **before** the `db.profile[unit]` fallback (line 615), add the party pattern match:

```lua
local function UnitToSettingsKey(unit)
    if not unit then return nil end
    if unit:match("^boss%d$") then return "boss" end
    if unit == "targettarget" or unit == "focustarget" then return "totPet" end
    if unit == "pet" then return "pet" end
    if unit:match("^party%d$") then return "party" end
    if db.profile[unit] then return unit end
    return nil
end
```

- [ ] **Step 2: Add party entries to GetSettingsForUnit**

In `GetSettingsForUnit` (line 856), add party entries **inside** the `if not unitSettingsMap then` lazy-init block, right after the boss loop (line 866):

```lua
        for i = 1, 5 do
            unitSettingsMap["boss" .. i] = db.profile.boss
        end
        for i = 1, 4 do
            unitSettingsMap["party" .. i] = db.profile.party
        end
        unitSettingsMap["party"] = db.profile.party
    end
    return unitSettingsMap[unit] or db.profile.player
```

This ensures party entries are part of the initial cache build, not appended after.

- [ ] **Step 3: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua
git commit -m "feat(party): extend UnitToSettingsKey and GetSettingsForUnit for party units"
```

---

### Task 3: Expose component builders via ns namespace

**Files:**
- Modify: `EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua`

The component builders are all `local function` declarations. We need to expose them on the `ns` table so the party frames file can access them. Add these assignments **after** all the builder function definitions but **before** `RegisterStylesOnce()` (around line 3459).

- [ ] **Step 1: Add ns exports block**

Find the area just before `RegisterStylesOnce()` (line 3459) and add:

```lua
-- Expose builders for party/raid frame files
ns.CreateHealthBar = CreateHealthBar
ns.CreateAbsorbBar = CreateAbsorbBar
ns.CreatePowerBar = CreatePowerBar
ns.CreatePortrait = CreatePortrait
ns.CreateCastBar = CreateCastBar
ns.CreateUnifiedBorder = CreateUnifiedBorder
ns.ReparentBarsToClip = ReparentBarsToClip
ns.UpdateBordersForScale = UpdateBordersForScale
ns.ApplyFramePosition = ApplyFramePosition
ns.SetFSFont = SetFSFont
ns.ContentToTag = ContentToTag
ns.EstimateUFTextWidth = EstimateUFTextWidth
ns.GetSettingsForUnit = GetSettingsForUnit
ns.SetupUnitMenu = nil -- will be set later inside spawn function
ns.GetCastbarColor = GetCastbarColor
ns.ApplyHealthBarTexture = ApplyHealthBarTexture
ns.ApplyDarkTheme = ApplyDarkTheme
ns.ApplyHealthBarAlpha = ApplyHealthBarAlpha
```

Note: `SetupUnitMenu` is defined as a local inside the spawn function scope (line 5403). It needs to be exported from there. Add this line inside the spawn function after `SetupUnitMenu` is defined (after line 5408):

```lua
ns.SetupUnitMenu = SetupUnitMenu
```

Also expose the `db`, `frames`, and `oUF` references the party file will need:

**Important:** `ns.PP` must be available at file-load time for the party file. Add this near the top of the file (after line 4, `local PP = EllesmereUI.PP`):

```lua
ns.PP = PP
```

Then add the remaining shared state exports in the same block near `RegisterStylesOnce()`:

```lua
ns.db = nil      -- set after DB init
ns.frames = frames
```

Then after `db = EUILite.NewDB(...)` runs (find the DB init line), add:

```lua
ns.db = db
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua
git commit -m "feat(party): expose component builders and shared state via ns namespace"
```

---

### Task 4: Update .toc file

**Files:**
- Modify: `EllesmereUIUnitFrames/EllesmereUIUnitFrames.toc`

- [ ] **Step 1: Add party frames file to load order**

Add `EllesmereUIPartyFrames.lua` after the main file:

```
# oUF
Libs\oUF\oUF.xml

# Main Luas
EllesmereUIUnitFrames.lua
EllesmereUIPartyFrames.lua

# Options
EUI_UnitFrames_Options.lua
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIUnitFrames.toc
git commit -m "feat(party): add EllesmereUIPartyFrames.lua to toc load order"
```

---

## Chunk 2: Core Party Frames File — StylePartyFrame and SpawnPartyHeader

### Task 5: Create EllesmereUIPartyFrames.lua with StylePartyFrame

**Files:**
- Create: `EllesmereUIUnitFrames/EllesmereUIPartyFrames.lua`

This is the core new file. It accesses all builders through `ns.*`.

- [ ] **Step 1: Write the complete party frames file**

Create `EllesmereUIUnitFrames/EllesmereUIPartyFrames.lua` with the following content:

```lua
local addonName, ns = ...

local oUF = ns.oUF
local PP = ns.PP

----------------------------------------------------------------------
--  Helpers
----------------------------------------------------------------------

-- Map sortOrder setting to SecureGroupHeader attributes
local SORT_CONFIGS = {
    role = { groupBy = "ASSIGNEDROLE", groupingOrder = "TANK,HEALER,DAMAGER" },
    group = { groupBy = nil, groupingOrder = nil },
    alphabetical = { groupBy = nil, groupingOrder = nil, sortMethod = "NAME" },
}

-- Map growthDirection to header point/offset
local function GetGrowthAttributes(direction, spacing)
    if direction == "horizontal" then
        return "LEFT", spacing, 0
    else -- vertical (default)
        return "TOP", 0, -spacing
    end
end

----------------------------------------------------------------------
--  Role Icon
----------------------------------------------------------------------

local ROLE_TEXCOORDS = {
    TANK    = { 0, 19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64, 20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

local function CreateRoleIcon(frame, settings)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    local sz = math.max(math.floor((settings.textSize or 11) + 2), 10)
    PP.Size(icon, sz, sz)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    icon:Hide()

    frame._roleIcon = icon
    return icon
end

local function UpdateRoleIcon(frame)
    local icon = frame._roleIcon
    if not icon then return end

    local db = ns.db
    local settings = db and db.profile and db.profile.party
    if not settings or settings.showRoleIcon == false then
        icon:Hide()
        return
    end

    local unit = frame.unit or frame:GetAttribute("unit")
    if not unit then icon:Hide(); return end

    local role = UnitGroupRolesAssigned(unit)
    local coords = ROLE_TEXCOORDS[role]
    if coords then
        icon:SetTexCoord(unpack(coords))
        icon:Show()
    else
        icon:Hide()
    end
end

----------------------------------------------------------------------
--  Party Aura Filter
----------------------------------------------------------------------

local function PartyAuraFilter(element, unit, data)
    -- Prioritize debuffs the player can dispel
    if data.isDebuff then
        return true
    end
    return false
end

local function CreatePartyAuras(frame, settings)
    if not settings.showDebuffs and not settings.showBuffs then return end

    if settings.showDebuffs then
        local debuffs = CreateFrame("Frame", nil, frame)
        debuffs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        debuffs.size = math.floor(settings.healthHeight * 0.5)
        debuffs.num = settings.maxDebuffs or 3
        debuffs["growth-x"] = "RIGHT"
        debuffs.FilterAura = PartyAuraFilter

        debuffs.PostCreateButton = function(self, button)
            button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            -- Dispellable glow
            if not button._dispelGlow then
                local glow = button:CreateTexture(nil, "OVERLAY")
                glow:SetAllPoints()
                glow:SetColorTexture(1, 1, 1, 0)
                button._dispelGlow = glow
            end
        end

        debuffs.PostUpdateButton = function(self, button, unit, data)
            if button._dispelGlow then
                local db = ns.db
                local s = db and db.profile and db.profile.party
                if s and s.highlightDispellable and data.isDebuff and data.dispelName then
                    button._dispelGlow:SetColorTexture(0, 0.8, 1, 0.3)
                else
                    button._dispelGlow:SetColorTexture(1, 1, 1, 0)
                end
            end
        end

        frame.Debuffs = debuffs
    end

    if settings.showBuffs and (settings.maxBuffs or 0) > 0 then
        local buffs = CreateFrame("Frame", nil, frame)
        buffs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        buffs.size = math.floor(settings.healthHeight * 0.5)
        buffs.num = settings.maxBuffs or 0
        buffs["growth-x"] = "LEFT"
        buffs.PostCreateButton = function(self, button)
            button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        frame.Buffs = buffs
    end
end

----------------------------------------------------------------------
--  StylePartyFrame
----------------------------------------------------------------------

local function StylePartyFrame(frame, unit)
    local db = ns.db
    if not db then return end

    local settings = db.profile.party
    if not settings then return end

    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local powerHeight = ppIsAtt and (settings.powerHeight or 4) or 0
    local totalHeight = settings.healthHeight + powerHeight
    local totalWidth = settings.frameWidth

    -- Portrait adds width when visible
    local showPortrait = settings.showPortrait ~= false
        and (db.profile.portraitStyle or "attached") ~= "none"
    if showPortrait then
        totalWidth = totalHeight + settings.frameWidth
    end

    PP.Size(frame, totalWidth, totalHeight)

    -- Health bar
    local healthRightInset = showPortrait and totalHeight or 0
    frame.Health = ns.CreateHealthBar(frame, unit, settings.healthHeight, 0, settings, healthRightInset)

    -- Absorb bar
    ns.CreateAbsorbBar(frame, unit, settings)

    -- Power bar
    if ppPos ~= "none" then
        frame.Power = ns.CreatePowerBar(frame, unit, settings)
    end

    -- Portrait (always create, hide backdrop when disabled — same pattern as boss)
    frame.Portrait = ns.CreatePortrait(frame, "left", totalHeight, unit)
    frame._portraitSide = "left"
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end

    -- Re-anchor health bar to portrait's snapped width (same fix as boss frames)
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and frame.Health then
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local powerAboveOff = (ppPos == "above") and (settings.powerHeight or 4) or 0
        frame.Health:ClearAllPoints()
        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", snappedPortW, -powerAboveOff)
        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", 0, 0)
        PP.Height(frame.Health, settings.healthHeight)
        frame.Health._xOffset = snappedPortW
        frame.Health._rightInset = 0
        frame.Health._topOffset = powerAboveOff
    end

    -- Border
    ns.CreateUnifiedBorder(frame, unit)
    ns.UpdateBordersForScale(frame, unit)

    -- Clip bars to prevent overflow
    ns.ReparentBarsToClip(frame)

    -- Text overlay
    local textOverlay = CreateFrame("Frame", nil, frame.Health)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local ts = settings.textSize or 11
    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    ns.SetFSFont(leftText, ts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    ns.SetFSFont(rightText, ts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    ns.SetFSFont(centerText, ts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Tag system (same pattern as boss frames)
    local function ApplyTextTags(lc, rc, cc)
        local ltag = ns.ContentToTag(lc)
        local rtag = ns.ContentToTag(rc)
        local ctag = ns.ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    -- Text positioning (same pattern as boss frames)
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local barW = s.frameWidth or 160

        -- Account for role icon width on the left
        local roleOffset = (s.showRoleIcon ~= false) and (ts + 6) or 0

        if cc ~= "none" then
            centerText:ClearAllPoints()
            centerText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
            centerText:SetWidth(0)
            centerText:Show()
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetPoint("LEFT", frame.Health, "LEFT", 5 + roleOffset, 0)
                leftText:SetJustifyH("LEFT")
                if rc ~= "none" then
                    local rightUsed = ns.EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10 - roleOffset, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
            else leftText:Hide() end
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetPoint("RIGHT", frame.Health, "RIGHT", -5, 0)
                rightText:SetJustifyH("RIGHT")
                if lc ~= "none" then
                    local leftUsed = ns.EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10 - roleOffset, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Role icon (anchored to left of health bar, before name text)
    local roleIcon = CreateRoleIcon(frame, settings)
    roleIcon:SetPoint("LEFT", frame.Health, "LEFT", 4, 0)

    -- Auras
    CreatePartyAuras(frame, settings)

    -- Range fading
    if settings.enableRangeFade ~= false then
        frame.Range = {
            insideAlpha = 1,
            outsideAlpha = settings.rangeFadeAlpha or 0.4,
        }
    end

    -- Threat indicator (border glow)
    if settings.showThreat ~= false then
        local threat = frame:CreateTexture(nil, "OVERLAY")
        threat:SetAllPoints()
        threat:Hide()
        frame.ThreatIndicator = threat
    end

    -- Ready check
    local readyCheck = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    readyCheck:SetSize(16, 16)
    readyCheck:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.ReadyCheckIndicator = readyCheck

    -- Leader indicator
    local leader = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    leader:SetSize(12, 12)
    leader:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.LeaderIndicator = leader

    -- Assistant indicator
    local assist = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    assist:SetSize(12, 12)
    assist:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.AssistantIndicator = assist

    -- Resurrection indicator
    local resurrect = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    resurrect:SetSize(20, 20)
    resurrect:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.ResurrectIndicator = resurrect

    -- Summon indicator
    local summon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    summon:SetSize(24, 24)
    summon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.SummonIndicator = summon

    -- Hook for role icon updates
    -- Note: WoW Frame:RegisterEvent takes only event name (no callback arg).
    -- Use OnEvent script + OnShow hook instead.
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    frame:HookScript("OnEvent", function(self, event)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
            UpdateRoleIcon(self)
        end
    end)
    frame:HookScript("OnShow", function(self)
        UpdateRoleIcon(self)
    end)

    -- Right-click menu
    if ns.SetupUnitMenu then
        ns.SetupUnitMenu(frame, unit or "party")
    end
end

----------------------------------------------------------------------
--  SpawnPartyHeader
----------------------------------------------------------------------

local partyHeader

local function SpawnPartyHeader()
    local db = ns.db
    if not db then return end

    local settings = db.profile.party
    if not settings then return end

    local point, xOff, yOff = GetGrowthAttributes(
        settings.growthDirection or "vertical",
        settings.spacing or 1
    )

    -- Sort config
    local sortCfg = SORT_CONFIGS[settings.sortOrder or "role"] or SORT_CONFIGS.role

    -- Guard: oUF errors on duplicate style registration (e.g. during ReloadFrames)
    if not oUF.styles or not oUF.styles["EllesmereParty"] then
        oUF:RegisterStyle("EllesmereParty", StylePartyFrame)
    end
    oUF:SetActiveStyle("EllesmereParty")

    local headerArgs = {
        "showPlayer", settings.showPlayer or false,
        "showParty", true,
        "showSolo", false,
        "point", point,
        "xOffset", xOff,
        "yOffset", yOff,
        "oUF-initialConfigFunction", ([[
            self:SetWidth(%d)
            self:SetHeight(%d)
        ]]):format(settings.frameWidth or 160, (settings.healthHeight or 36) + ((settings.powerPosition ~= "none") and (settings.powerHeight or 4) or 0)),
    }

    -- Add sort attributes
    if sortCfg.groupBy then
        headerArgs[#headerArgs + 1] = "groupBy"
        headerArgs[#headerArgs + 1] = sortCfg.groupBy
    end
    if sortCfg.groupingOrder then
        headerArgs[#headerArgs + 1] = "groupingOrder"
        headerArgs[#headerArgs + 1] = sortCfg.groupingOrder
    end
    if sortCfg.sortMethod then
        headerArgs[#headerArgs + 1] = "sortMethod"
        headerArgs[#headerArgs + 1] = sortCfg.sortMethod
    end

    partyHeader = oUF:SpawnHeader(
        "EllesmereUIPartyHeader",
        nil,
        "custom [@party1,exists] show;hide",
        unpack(headerArgs)
    )

    ns.ApplyFramePosition(partyHeader, "party")

    local enabled = db.profile.enabledFrames
    if enabled.party == false then
        RegisterAttributeDriver(partyHeader, "state-visibility", "hide")
    end

    -- Store reference
    ns.partyHeader = partyHeader

    return partyHeader
end

----------------------------------------------------------------------
--  UpdatePartyLayout (out of combat only)
----------------------------------------------------------------------

local function UpdatePartyLayout()
    if InCombatLockdown() or not partyHeader then return end

    local db = ns.db
    if not db then return end

    local settings = db.profile.party
    if not settings then return end

    local point, xOff, yOff = GetGrowthAttributes(
        settings.growthDirection or "vertical",
        settings.spacing or 1
    )

    partyHeader:SetAttribute("point", point)
    partyHeader:SetAttribute("xOffset", xOff)
    partyHeader:SetAttribute("yOffset", yOff)
    partyHeader:SetAttribute("showPlayer", settings.showPlayer or false)

    local sortCfg = SORT_CONFIGS[settings.sortOrder or "role"] or SORT_CONFIGS.role
    if sortCfg.groupBy then
        partyHeader:SetAttribute("groupBy", sortCfg.groupBy)
        partyHeader:SetAttribute("groupingOrder", sortCfg.groupingOrder)
    end
    if sortCfg.sortMethod then
        partyHeader:SetAttribute("sortMethod", sortCfg.sortMethod)
    end

    ns.ApplyFramePosition(partyHeader, "party")
end

----------------------------------------------------------------------
--  Public API
----------------------------------------------------------------------

ns.SpawnPartyHeader = SpawnPartyHeader
ns.UpdatePartyLayout = UpdatePartyLayout
ns.StylePartyFrame = StylePartyFrame
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIPartyFrames.lua
git commit -m "feat(party): create EllesmereUIPartyFrames.lua with StylePartyFrame and SpawnPartyHeader"
```

---

### Task 6: Call SpawnPartyHeader from main spawn section

**Files:**
- Modify: `EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua:5919-5920`

- [ ] **Step 1: Add SpawnPartyHeader call after boss frame spawning**

After the boss frame spawn loop (line 5919) and the blizzard boss hide loop (line 5927), add:

```lua
    -- Party frames (spawned via header in EllesmereUIPartyFrames.lua)
    if ns.SpawnPartyHeader then
        ns.SpawnPartyHeader()
    end
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua
git commit -m "feat(party): call SpawnPartyHeader from main spawn section"
```

---

## Chunk 3: Unlock Mode and CDM Integration

### Task 7: Register party header with Unlock Mode

**Files:**
- Modify: `EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua:6228-6392`

- [ ] **Step 1: Add "party" to UNIT_LABELS**

In the `UNIT_LABELS` table (line 6230), add `party`:

```lua
local UNIT_LABELS = {
    player = "Player", target = "Target", focus = "Focus",
    pet = "Pet", targettarget = "Target of Target",
    focustarget = "Focus Target", boss = "Boss Frames",
    party = "Party Frames",
    classPower = "Class Resource",
}
```

- [ ] **Step 2: Add party to element list**

After the boss element (line 6385), add:

```lua
elements[#elements + 1] = MakeUFElement("party", 8)
```

- [ ] **Step 3: Handle party in getFrame callback**

In the `getFrame` function (line 6247), add a party case before the default return:

```lua
if k == "party" then return ns.partyHeader end
```

- [ ] **Step 4: Handle party in getSize callback**

The party header's size for Unlock Mode should return the total group size. In `getSize` (line 6258), add:

```lua
if k == "party" then
    local s = db.profile.party
    if not s then return 160, 36 end
    local ppPos = s.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local ph = ppIsAtt and (s.powerHeight or 4) or 0
    local frameH = s.healthHeight + ph
    local frameW = s.frameWidth
    -- Account for portrait
    local showPortrait = s.showPortrait ~= false and (db.profile.portraitStyle or "attached") ~= "none"
    if showPortrait then frameW = frameW + frameH end
    return frameW, frameH
end
```

- [ ] **Step 5: Handle party in savePos callback**

In the `savePos` function (line 6324), add a party case:

```lua
elseif k == "party" then
    if ns.partyHeader then
        ns.partyHeader:ClearAllPoints()
        ns.partyHeader:SetPoint(point, UIParent, relPoint, x, y)
    end
```

- [ ] **Step 6: Handle party in applyPos callback**

In the `applyPos` function (line 6351), add:

```lua
elseif k == "party" then
    if ns.partyHeader then
        ns.partyHeader:ClearAllPoints()
        ns.partyHeader:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    end
```

- [ ] **Step 7: Commit**

```bash
git add EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua
git commit -m "feat(party): register party header with Unlock Mode"
```

---

### Task 8: CDM integration — add party frames to FindPlayerPartyFrame

**Files:**
- Modify: `EllesmereUI.lua:1700-1703`

- [ ] **Step 1: Add EllesmereUI party frames to PARTY_FRAME_SOURCES**

At the top of the `PARTY_FRAME_SOURCES` table (line 1700), add our party frames as the first entry so they take priority:

```lua
local PARTY_FRAME_SOURCES = {
    { addon = "EllesmereUIUnitFrames", prefix = "EllesmereUIPartyHeaderUnitButton", count = 5 },
    { addon = "ElvUI",  prefix = "ElvUF_PartyGroup1UnitButton", count = 5 },
    { addon = "Cell",   prefix = "CellPartyFrameMember",        count = 5 },
    { addon = nil,      prefix = "CompactPartyFrameMember",     count = 5 },
```

- [ ] **Step 2: Commit**

```bash
git add EllesmereUI.lua
git commit -m "feat(party): add native party frames to CDM FindPlayerPartyFrame sources"
```

---

## Out of Scope (Phase 4)

- **Options panel** (`EUI_UnitFrames_Options.lua`) — party settings UI deferred to Phase 4. Settings can be changed via SavedVariables or `/run` commands for testing.
- **Combat-queued layout updates** — `UpdatePartyLayout()` currently returns early in combat. A future enhancement should queue changes and apply on `PLAYER_REGEN_ENABLED`.
- **Castbar** — deferred to Phase 4.
- **`EllesmereUI.PartyFrames` registration table** — deferred to Phase 3. CDM integration currently uses `PARTY_FRAME_SOURCES` prefix matching instead.

---

## Chunk 4: Verification

### Task 9: Verify addon loads without errors

- [ ] **Step 1: Verify Lua syntax of the new file**

```bash
luac -p EllesmereUIUnitFrames/EllesmereUIPartyFrames.lua
```

If `luac` is not available, use:

```bash
lua -e "loadfile('EllesmereUIUnitFrames/EllesmereUIPartyFrames.lua')" 2>&1
```

Expected: no output (no syntax errors).

- [ ] **Step 2: Verify all modified files parse correctly**

```bash
luac -p EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua
```

Expected: no output (no syntax errors).

- [ ] **Step 3: Verify the .toc file lists all files in correct order**

Read the `.toc` and confirm `EllesmereUIPartyFrames.lua` appears after `EllesmereUIUnitFrames.lua` and before `EUI_UnitFrames_Options.lua`.

- [ ] **Step 4: Review: scan for common issues**

Grep for potential problems:
- Any reference to `CreateHealthBar` (without `ns.`) in the party file → should all use `ns.CreateHealthBar`
- Any `local db` shadowing in party file that might conflict
- Verify `ns.db` is set before `SpawnPartyHeader` is called

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(party): address any issues found during verification"
```
