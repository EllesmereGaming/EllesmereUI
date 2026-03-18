--------------------------------------------------------------------------------
--  EllesmereUICdmBarGlows.lua
--  Bar Glows: Overlay system that reads CDM buff bars and overlays glows
--  on action buttons.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Forward references from main CDM file (set during init)
local ECME, GetTargetButton, GetActionButton, GetSortedSlots, StartNativeGlow, StopNativeGlow

function ns.InitBarGlows(ecme, getTarget, getAction, getSorted, startGlow, stopGlow)
    ECME = ecme
    GetTargetButton = getTarget
    GetActionButton = getAction
    GetSortedSlots = getSorted
    StartNativeGlow = startGlow
    StopNativeGlow = stopGlow
end

-------------------------------------------------------------------------------
--  Bar Glows v2: Collect all tracked buff spells across all CDM bars
--  Returns two lists: tracked (spells the user has in their CDM bars) and
--  untracked (known spells not currently in any CDM bar).
--  Each entry: { spellID, name, icon, barKey, barName }
-------------------------------------------------------------------------------
function ns.GetAllCDMBuffSpells()
    if not ECME or not ECME.db then return {}, {} end
    local p = ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return {}, {} end

    local trackedSet = {}
    local trackedOrder = {}

    for _, bar in ipairs(p.cdmBars.bars) do
        local isBuff = (bar.barType == "buffs") or (bar.key == "buffs")
        if isBuff then
            local spells = ns.GetCDMSpellsForBar(bar.key)
            if spells then
                for _, sp in ipairs(spells) do
                    if sp.isKnown and sp.spellID and sp.spellID > 0 and not trackedSet[sp.spellID] then
                        local entry = {
                            spellID = sp.spellID,
                            cdID = sp.cdID,
                            name = sp.name,
                            icon = sp.icon,
                            barKey = bar.key,
                            barName = bar.name or bar.key,
                            isDisplayed = sp.isDisplayed,
                        }
                        trackedSet[sp.spellID] = entry
                        trackedOrder[#trackedOrder + 1] = entry
                    end
                end
            end
        end
    end

    local tracked, untracked = {}, {}
    for _, entry in ipairs(trackedOrder) do
        if entry.isDisplayed then
            tracked[#tracked + 1] = entry
        else
            untracked[#untracked + 1] = entry
        end
    end

    return tracked, untracked
end

--- Get barGlows profile data (with lazy init)
function ns.GetBarGlows()
    if not ECME or not ECME.db then return { enabled = true, selectedBar = 1, assignments = {} } end
    local p = ECME.db.profile
    if not p.barGlows then
        p.barGlows = {
            enabled = true, selectedBar = 1, selectedButton = nil,
            selectedAssignment = 1, assignments = {},
        }
    end
    return p.barGlows
end

--- Get assignments for a specific action bar button
function ns.GetButtonAssignments(barIdx, btnIdx)
    local bg = ns.GetBarGlows()
    local key = barIdx .. "_" .. btnIdx
    return bg.assignments[key]
end

--- Returns true if the user has at least one bar glow assignment configured
function ns.HasBarGlowAssignments()
    if not ECME or not ECME.db then return false end
    local p = ECME.db.profile
    local bg = p and p.barGlows
    if not bg or not bg.assignments then return false end
    for _, buffList in pairs(bg.assignments) do
        if buffList and #buffList > 0 then return true end
    end
    return false
end

-- RequestUpdate and lastSourceStates are defined in the Bar Glows block below

-------------------------------------------------------------------------------
--  Bar Glows: Overlay System (reads CDM buff bars, overlays on action buttons)
-------------------------------------------------------------------------------

local overlayFrames = {}
local hasActiveOverlays = false
local hasHiddenSlots = false
local lastSourceStates = {}

local HIDDEN_ALPHA = 0.001
local PACK_SPACING = 6

local function SaveOrigPoints(slot)
    if slot.__ECMEOrigPoints then return end
    local n = slot:GetNumPoints()
    if not n or n == 0 then return end
    local pts = {}
    for i = 1, n do pts[i] = { slot:GetPoint(i) } end
    slot.__ECMEOrigPoints = pts
end

local function RestoreOrigPoints(slot)
    local pts = slot.__ECMEOrigPoints
    if not pts then return end
    slot:ClearAllPoints()
    for _, p in ipairs(pts) do slot:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

local function ApplyPerSlotAlpha(slots)
    if not slots then return end
    for _, slot in ipairs(slots) do
        if slot.__ECMEHideFromCDM then
            if slot.__ECMEPrevAlpha == nil then
                slot.__ECMEPrevAlpha = slot:GetAlpha() or 1
                slot:SetAlpha(HIDDEN_ALPHA)
            end
        else
            if slot.__ECMEPrevAlpha ~= nil then
                slot:SetAlpha(slot.__ECMEPrevAlpha)
                slot.__ECMEPrevAlpha = nil
            end
        end
    end
end

local lastPackLayout = {}
local shownBuffer = {}

local function PackVisibleSlots()
    local root = _G.BuffIconCooldownViewer
    if not root or not GetSortedSlots then return end
    local slots = GetSortedSlots()
    if not slots then return end

    local count = 0
    for _, slot in ipairs(slots) do
        if slot and slot.IsShown and slot:IsShown() and not slot.__ECMEHideFromCDM then
            count = count + 1
            shownBuffer[count] = slot
        end
    end
    for i = count + 1, #shownBuffer do shownBuffer[i] = nil end
    if count == 0 then lastPackLayout.count = 0; return end

    local iconSize = shownBuffer[1]:GetWidth() or 35
    if iconSize < 5 then iconSize = 35 end

    local layoutChanged = (count ~= lastPackLayout.count) or (iconSize ~= lastPackLayout.iconSize)
    if not layoutChanged then
        for idx = 1, count do
            if shownBuffer[idx] ~= lastPackLayout[idx] then layoutChanged = true; break end
        end
    end
    if not layoutChanged then return end

    for _, slot in ipairs(slots) do SaveOrigPoints(slot) end
    for _, slot in ipairs(slots) do RestoreOrigPoints(slot) end

    local totalW = (count * iconSize) + ((count - 1) * PACK_SPACING)
    local startX = -(totalW / 2) + (iconSize / 2)
    for idx = 1, count do
        local slot = shownBuffer[idx]
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", root, "CENTER", startX + (idx - 1) * (iconSize + PACK_SPACING), 0)
        lastPackLayout[idx] = slot
    end
    for i = count + 1, (lastPackLayout.count or 0) do lastPackLayout[i] = nil end
    lastPackLayout.count = count
    lastPackLayout.iconSize = iconSize
end

local function ApplyPerSlotHidingAndPack()
    if not GetSortedSlots then return end
    local slots = GetSortedSlots()
    if not slots then return end
    ApplyPerSlotAlpha(slots)
    PackVisibleSlots()
end

local function ApplyPerSlotHidingAndPackSoon()
    lastPackLayout.count = nil
    ApplyPerSlotHidingAndPack()
    C_Timer.After(0.2, function()
        lastPackLayout.count = nil
        ApplyPerSlotHidingAndPack()
    end)
end
ns.ApplyPerSlotHidingAndPackSoon = ApplyPerSlotHidingAndPackSoon

local hookedSlots = {}
local UpdateOverlayVisuals

local overlayVisualsPending = false
local function DeferredOverlayVisuals()
    overlayVisualsPending = false
    if UpdateOverlayVisuals then UpdateOverlayVisuals() end
end

local function OnSlotVisibilityChanged()
    lastPackLayout.count = nil
    ApplyPerSlotHidingAndPack()
    if not overlayVisualsPending then
        overlayVisualsPending = true
        C_Timer.After(0, DeferredOverlayVisuals)
    end
end

local function HookCDMSlot(slot)
    if not slot or hookedSlots[slot] then return end
    hookedSlots[slot] = true
    slot:HookScript("OnShow", OnSlotVisibilityChanged)
    slot:HookScript("OnHide", OnSlotVisibilityChanged)
end

local function HookAllCDMChildren(root)
    if not root or not root.GetChildren then return end
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then HookCDMSlot(c) end
    end
end
ns.HookAllCDMChildren = HookAllCDMChildren

local cdmHookFrame = CreateFrame("Frame")
cdmHookFrame:Hide()
local lastChildCount = 0
cdmHookFrame:SetScript("OnUpdate", function(self, elapsed)
    -- No assignments -- nothing to do
    if not ns.HasBarGlowAssignments() then self:Hide(); return end
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    local root = _G.BuffIconCooldownViewer
    if not root or not root.GetChildren then return end
    local children = root:GetNumChildren()
    if children ~= lastChildCount then
        lastChildCount = children
        HookAllCDMChildren(root)
    else
        self:Hide()
    end
end)

local function GetOrCreateOverlay(actionBar, actionButtonIndex, cdmSlotIndex)
    local key = actionBar .. "_" .. actionButtonIndex .. "_" .. cdmSlotIndex
    if overlayFrames[key] then return overlayFrames[key] end
    local btn = GetTargetButton(actionBar, actionButtonIndex)
    if not btn then return nil end
    local overlay = CreateFrame("Frame", "ECME_Overlay" .. key, btn)
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel() + 10)
    overlay:Hide()
    overlayFrames[key] = overlay
    return overlay
end

local function SetupOverlays()
    if not ECME or not ECME.db then return end
    local p = ECME.db.profile
    local bg = p.barGlows
    if not bg or not bg.enabled then
        hasActiveOverlays = false
        hasHiddenSlots = false
        for key, overlay in pairs(overlayFrames) do
            StopNativeGlow(overlay)
            overlay:Hide()
        end
        return
    end

    local activeKeys = {}
    local anyActive = false

    local assignCount = 0
    for assignKey, buffList in pairs(bg.assignments) do
        if buffList and #buffList > 0 then
            assignCount = assignCount + 1
        end
    end

    for assignKey, buffList in pairs(bg.assignments) do
        if buffList and #buffList > 0 then
            local barIdx, btnIdx = assignKey:match("^(%d+)_(%d+)$")
            barIdx = tonumber(barIdx)
            btnIdx = tonumber(btnIdx)
            if barIdx and btnIdx then
                for i, entry in ipairs(buffList) do
                    local key = assignKey .. "_" .. i
                    local btn = GetTargetButton(barIdx, btnIdx)
                    if btn then
                        if not entry.actionSpellID and btn.action then
                            local aType, aID = GetActionInfo(btn.action)
                            if aType == "spell" and aID then
                                entry.actionSpellID = aID
                            end
                        end
                        local existing = overlayFrames[key]
                        if existing then
                            -- If the button was reparented, follow it
                            if existing:GetParent() ~= btn then
                                existing:SetParent(btn)
                                existing:SetAllPoints(btn)
                                lastSourceStates[key] = nil
                            end
                        else
                            local overlay = CreateFrame("Frame", "ECME_GlowV2_" .. key, btn)
                            overlay:SetAllPoints(btn)
                            overlayFrames[key] = overlay
                        end
                        local overlay = overlayFrames[key]
                        overlay:SetFrameLevel(btn:GetFrameLevel() + 10)
                        overlay:SetAlpha(1)
                        overlay._assignEntry = entry
                        overlay:Show()

                        -- Duration text FontString (created once per overlay)
                        if not overlay._durationText then
                            local fs = overlay:CreateFontString(nil, "OVERLAY")
                            overlay._durationText = fs
                        end
                        do
                            local fs = overlay._durationText
                            local sz = entry.durationSize or 12
                            fs:SetFont(EllesmereUI.GetFontPath("cdm"), sz, "OUTLINE")
                            fs:SetShadowOffset(0, 0)
                            fs:ClearAllPoints()
                            fs:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT",
                                3 + (entry.durationOffsetX or 0), 4 + (entry.durationOffsetY or 0))
                            fs:SetTextColor(entry.durationR or 1, entry.durationG or 1, entry.durationB or 1)
                            fs:Hide()
                        end
                        activeKeys[key] = true
                        anyActive = true
                    end
                end
            end
        end
    end

    for key, overlay in pairs(overlayFrames) do
        if not activeKeys[key] then
            StopNativeGlow(overlay)
            overlay:Hide()
            lastSourceStates[key] = nil
        end
    end

    -- Reset all state so UpdateOverlayVisuals re-evaluates glows from scratch
    wipe(lastSourceStates)

    hasActiveOverlays = anyActive
    hasHiddenSlots = false
end

UpdateOverlayVisuals = function()
    for key, overlay in pairs(overlayFrames) do
        if overlay:IsShown() and overlay._assignEntry then
            local entry = overlay._assignEntry
            local spellID = entry.spellID
            local mode = entry.mode or "ACTIVE"

            local slotMismatch = false
            if entry.actionSpellID then
                local btn = overlay:GetParent()
                if btn and btn.action then
                    local aType, aID = GetActionInfo(btn.action)
                    if aType == "spell" and aID and aID ~= entry.actionSpellID then
                        slotMismatch = true
                    end
                end
            end

            local auraActive = false
            if not slotMismatch and spellID and spellID > 0 then
                local blizzCache = ns._tickBlizzActiveCache
                if blizzCache and blizzCache[spellID] then
                    auraActive = true
                end
            end

            local shouldGlow
            if mode == "MISSING" then
                shouldGlow = not slotMismatch and not auraActive
            else
                shouldGlow = auraActive
            end

            local prevState = lastSourceStates[key]
            if shouldGlow ~= prevState then
                lastSourceStates[key] = shouldGlow
                if shouldGlow then
                    if overlay._glowActive then
                        StopNativeGlow(overlay)
                    end
                    local style = entry.glowStyle or 1
                    local cr, cg, cb = 1, 0.82, 0.1
                    if entry.classColor then
                        local _, ct = UnitClass("player")
                        if ct then
                            local cc = RAID_CLASS_COLORS[ct]
                            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                        end
                    elseif entry.glowColor then
                        cr = entry.glowColor.r or 1
                        cg = entry.glowColor.g or 0.82
                        cb = entry.glowColor.b or 0.1
                    end
                    StartNativeGlow(overlay, style, cr, cg, cb)
                else
                    if overlay._glowActive then
                        StopNativeGlow(overlay)
                    end
                end
            end

            -- Duration text: update every tick when glow is active + showDuration on
            local dfs = overlay._durationText
            if dfs then
                if shouldGlow and entry.showDuration and mode ~= "MISSING" and spellID and spellID > 0 then
                    local blzChild = (ns._tickBlizzBuffChildCache and ns._tickBlizzBuffChildCache[spellID])
                                  or (ns._tickBlizzAllChildCache and ns._tickBlizzAllChildCache[spellID])
                    local durText
                    if blzChild then
                        local auraID = blzChild.auraInstanceID
                        local auraUnit = blzChild.auraDataUnit or "player"
                        if auraID then
                            local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraID)
                            if ok and durObj and durObj.GetRemainingDuration then
                                local rok, remaining = pcall(durObj.GetRemainingDuration, durObj)
                                if rok and remaining then
                                    if issecretvalue and issecretvalue(remaining) then
                                        -- Can't do math on secret values; %.0f rounds to
                                        -- nearest which is close enough to ceil
                                        local fok, fstr = pcall(string.format, "%.0f", remaining)
                                        if fok and fstr then
                                            durText = fstr
                                        end
                                    else
                                        durText = string.format("%d", math.ceil(remaining))
                                    end
                                end
                            end
                        end
                    end
                    if durText then
                        local isSecret = issecretvalue and issecretvalue(durText)
                        if isSecret or dfs._lastText ~= durText then
                            dfs._lastText = not isSecret and durText or nil
                            dfs:SetText(durText)
                        end
                        dfs:Show()
                    else
                        dfs._lastText = nil
                        dfs:Hide()
                    end
                else
                    dfs:Hide()
                end
            end
        end
    end
end
-- END BAR GLOWS
ns.UpdateOverlayVisuals = UpdateOverlayVisuals

-- BAR GLOWS MASTER UPDATE
local updatePending = false
local updateTimer = nil

local function DoUpdate()
    updatePending = false
    updateTimer = nil
    if ns.UpdateAllCDMBorders then ns.UpdateAllCDMBorders() end
    SetupOverlays()
end

local function RequestUpdate()
    if not ns.HasBarGlowAssignments() then return end
    wipe(lastSourceStates)
    if updateTimer then updateTimer:Cancel() end
    updatePending = true
    cdmHookFrame:Show()
    updateTimer = C_Timer.NewTimer(0.1, DoUpdate)
end
ns.RequestUpdate = RequestUpdate

local lastPackTime = 0
local PACK_THROTTLE = 0.5

-- Bar glow visuals are updated directly from UpdateAllCDMBars each tick
-- (same timing as CDM bars, using the same _tickBlizzActiveCache data).
-- No separate polling frame needed.
-- END BAR GLOWS MASTER UPDATE