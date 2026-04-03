-------------------------------------------------------------------------------
--  EllesmereUICdmBarGlows.lua
--  Bar Glows: Overlays glow effects on action bar buttons when configured
--  buff/aura spells become active (or inactive in MISSING mode).
--  Simplified v3: uses C_UnitAuras.GetPlayerAuraBySpellID for detection.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Glow functions from main file (available after main file loads)
local StartNativeGlow = function(...) if ns.StartNativeGlow then return ns.StartNativeGlow(...) end end
local StopNativeGlow  = function(...) if ns.StopNativeGlow then return ns.StopNativeGlow(...) end end

-- Slot offsets per bar index (matches EllesmereUIActionBars BAR_SLOT_OFFSETS)
local BAR_OFFSETS = { 0, 60, 48, 24, 36, 144, 156, 168 }

-- CDM bar key mapping for bar glow indices 101+
local CDM_GLOW_BAR_KEYS = { [101] = "cooldowns", [102] = "utility" }

-- Action bar / CDM bar button lookup
local function GetActionButton(barIdx, btnIdx)
    -- CDM bars: look up icon from cdmBarIcons
    local cdmKey = CDM_GLOW_BAR_KEYS[barIdx]
    if cdmKey then
        local icons = ns.cdmBarIcons and ns.cdmBarIcons[cdmKey]
        return icons and icons[btnIdx]
    end
    -- EllesmereUI action bar buttons: EABButton<slot> where slot = offset + btnIdx
    local offset = BAR_OFFSETS[barIdx] or 0
    local slot = offset + btnIdx
    local btn = _G["EABButton" .. slot]
    if btn then return btn end
    -- Fallback: Blizzard bar names
    local BLIZZ_PREFIXES = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
    }
    if barIdx >= 1 and barIdx <= #BLIZZ_PREFIXES then
        btn = _G[BLIZZ_PREFIXES[barIdx] .. btnIdx]
    end
    return btn
end

-------------------------------------------------------------------------------
--  Data Access
-------------------------------------------------------------------------------

--- Get barGlows data from SavedVariables (with lazy init)
function ns.GetBarGlows()
    -- Bar glows are fully spec-specific, stored in specProfiles[specKey].barGlows
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey() or "0"
    if specKey == "0" then return { enabled = true, selectedBar = 1, assignments = {} } end
    if not EllesmereUIDB then return { enabled = true, selectedBar = 1, assignments = {} } end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { specProfiles = {} }
    end
    local sa = EllesmereUIDB.spellAssignments
    if not sa.specProfiles then sa.specProfiles = {} end
    if not sa.specProfiles[specKey] then sa.specProfiles[specKey] = { barSpells = {} } end
    local prof = sa.specProfiles[specKey]
    if not prof.barGlows or not next(prof.barGlows) then
        prof.barGlows = {
            enabled = true,
            selectedBar = 101,
            assignments = {},
        }
    end
    return prof.barGlows
end

--- Get assignments for a specific action bar button
function ns.GetButtonAssignments(barIdx, btnIdx)
    local bg = ns.GetBarGlows()
    local key = barIdx .. "_" .. btnIdx
    return bg.assignments[key]
end

--- Returns true if the user has at least one bar glow assignment
function ns.HasBarGlowAssignments()
    local bg = ns.GetBarGlows()
    if not bg or not bg.assignments then return false end
    for _, buffList in pairs(bg.assignments) do
        if buffList and #buffList > 0 then return true end
    end
    return false
end

--- Collect all tracked buff spells across all CDM buff bars
--- Returns tracked (displayed in CDM) and untracked (known but not displayed)
function ns.GetAllCDMBuffSpells()
    local ECME = ns.ECME
    if not ECME or not ECME.db then return {}, {} end
    local p = ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return {}, {} end

    local trackedSet = {}
    local trackedOrder = {}

    for _, bar in ipairs(p.cdmBars.bars) do
        local isBuff = (bar.barType == "buffs") or (bar.key == "buffs")
        if isBuff then
            local spells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar(bar.key)
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

    -- Split by Blizzard BuffBar viewer presence (tracked bars).
    -- Only spells in the BuffBar viewer (vi=4) count as tracked for TBB.
    -- BuffIcon viewer spells go to untracked (fires popup to add to
    -- Blizzard's tracked bars first).
    -- Uses frame-based matching (IsSpellInBuffBarViewer) instead of
    -- spell-ID cache lookup for robust ID resolution.
    local IsInViewer = ns.IsSpellInBuffBarViewer
    local tracked, untracked = {}, {}
    for _, entry in ipairs(trackedOrder) do
        local sid = entry.spellID
        if sid and IsInViewer and IsInViewer(sid) then
            tracked[#tracked + 1] = entry
        else
            untracked[#untracked + 1] = entry
        end
    end

    return tracked, untracked
end

-------------------------------------------------------------------------------
--  Overlay System
-------------------------------------------------------------------------------
local overlayFrames = {}  -- [key] = overlay frame
local lastStates = {}     -- [key] = bool (last glow state for change detection)
local _cachedBG = nil     -- cached barGlows reference (refreshed on SetupOverlays)

--- Rebuild overlay frames from assignments
local function SetupOverlays()
    local bg = ns.GetBarGlows()
    _cachedBG = bg
    if not bg or not bg.enabled then
        -- Disabled: stop all glows
        for key, overlay in pairs(overlayFrames) do
            StopNativeGlow(overlay)
            overlay:Hide()
        end
        return
    end

    local activeKeys = {}
    for assignKey, buffList in pairs(bg.assignments) do
        if buffList and #buffList > 0 then
            local barIdx, btnIdx = assignKey:match("^(%d+)_(%d+)$")
            barIdx = tonumber(barIdx)
            btnIdx = tonumber(btnIdx)
            if barIdx and btnIdx then
                local btn = GetActionButton(barIdx, btnIdx)
                if btn then
                    for i, entry in ipairs(buffList) do
                        local key = assignKey .. "_" .. i
                        local overlay = overlayFrames[key]
                        if not overlay then
                            overlay = CreateFrame("Frame", "ECME_Glow_" .. key, btn)
                            overlayFrames[key] = overlay
                        end
                        if overlay:GetParent() ~= btn then
                            overlay:SetParent(btn)
                        end
                        overlay:SetAllPoints(btn)
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
                    end
                end
            end
        end
    end

    -- Hide overlays that are no longer assigned
    for key, overlay in pairs(overlayFrames) do
        if not activeKeys[key] then
            StopNativeGlow(overlay)
            overlay:Hide()
            lastStates[key] = nil
        end
    end

    -- Force re-evaluation on next tick
    wipe(lastStates)
end

--- Update glow visuals based on current aura state.
--- Called each CDM tick (~10Hz from UpdateAllCDMBars).
local function UpdateOverlayVisuals()
    local bg = _cachedBG
    if not bg or not bg.enabled then return end

    for key, overlay in pairs(overlayFrames) do
        if overlay:IsShown() and overlay._assignEntry then
            local entry = overlay._assignEntry
            local spellID = entry.spellID
            local mode = entry.mode or "ACTIVE"

            -- Check if aura/buff is active via the CDM active cache
            -- (populated each tick from viewer frames with auraInstanceID)
            local auraActive = false
            if spellID and spellID > 0 then
                local cache = ns._tickBlizzActiveCache
                if cache and cache[spellID] then
                    auraActive = true
                end
            end

            -- Determine if glow should be on
            local shouldGlow
            if mode == "MISSING" then
                shouldGlow = not auraActive
            else
                shouldGlow = auraActive
            end

            -- Only update on state change (avoids restarting animations)
            if shouldGlow ~= lastStates[key] then
                lastStates[key] = shouldGlow
                if shouldGlow then
                    StopNativeGlow(overlay)
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
                    StopNativeGlow(overlay)
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
ns.UpdateOverlayVisuals = UpdateOverlayVisuals

--- Rebuild overlays and force a visual update
function ns.RequestBarGlowUpdate()
    SetupOverlays()
    UpdateOverlayVisuals()
end
-- Alias for backward compatibility with options code
ns.RequestUpdate = ns.RequestBarGlowUpdate

-------------------------------------------------------------------------------
--  Integration: called from main file's UpdateAllCDMBars tick
-------------------------------------------------------------------------------

-- Called once during CDMFinishSetup
function ns.InitBarGlows()
    SetupOverlays()
end

-- No-ops for removed functionality (options may reference these)
ns.ApplyPerSlotHidingAndPackSoon = function() end
ns.HookAllCDMChildren = function() end
