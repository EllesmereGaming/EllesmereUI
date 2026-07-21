-------------------------------------------------------------------------------
--  EllesmereUICdmBarGlows.lua
--  Bar Glows: Overlays glow effects on action bar / CDM bar buttons when
--  configured buff/aura spells become active (or inactive in MISSING mode).
--  v4: CDM bar assignments keyed by cooldownID for stability across reanchors.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Glow functions from main file (available after main file loads)
local StartNativeGlow = function(...) if ns.StartNativeGlow then return ns.StartNativeGlow(...) end end
local StopNativeGlow  = function(...) if ns.StopNativeGlow then return ns.StopNativeGlow(...) end end

-- Slot offsets per bar index (matches EllesmereUIActionBars BAR_SLOT_OFFSETS)
local BAR_OFFSETS = { 0, 60, 48, 24, 36, 144, 156, 168 }

-------------------------------------------------------------------------------
--  Button Lookup
-------------------------------------------------------------------------------

-- Action bar button lookup (stable slot-based)
local function GetActionBarButton(barIdx, btnIdx)
    local offset = BAR_OFFSETS[barIdx] or 0
    local slot = offset + btnIdx
    local btn = _G["EABButton" .. slot]
    if btn then return btn end
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

-- CDM bar icon lookup by cooldownID (stable across reanchors).
-- Walks all CDM bars (default + extras) since the 1-spell-per-bar invariant
-- guarantees a cooldownID can only live on one bar at a time.
local function FindCDMButtonByCooldownID(cooldownID)
    if not ns.cdmBarIcons then return nil end
    for _, icons in pairs(ns.cdmBarIcons) do
        for i = 1, #icons do
            local icon = icons[i]
            if icon and icon.cooldownID == cooldownID then
                return icon
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Data Access
-------------------------------------------------------------------------------

--- Get barGlows data from SavedVariables (with lazy init)
function ns.GetBarGlows()
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey then return { enabled = true, selectedBar = "cooldowns", assignments = {} } end
    -- Bar glows are spec-specific and per-profile: specProfiles[specKey].barGlows
    -- under the active profile's bucket (ns.GetActiveSpecProfiles).
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return { enabled = true, selectedBar = "cooldowns", assignments = {} } end
    if not sp[specKey] then sp[specKey] = { barSpells = {} } end
    local prof = sp[specKey]
    if not prof.barGlows or not next(prof.barGlows) then
        prof.barGlows = {
            enabled = true,
            selectedBar = "cooldowns",
            assignments = {},
        }
    end
    -- Live migration: colorMode replaced classColor + "glowColor set" nil check
    if not prof.barGlows._colorModeMigrated then
        prof.barGlows._colorModeMigrated = true
        for _, buffList in pairs(prof.barGlows.assignments) do
            for _, entry in ipairs(buffList) do
                if not entry.colorMode then
                    if entry.classColor then
                        entry.colorMode = "class"
                    elseif entry.glowColor then
                        entry.colorMode = "custom"
                    else
                        entry.colorMode = "default"
                    end
                end
            end
        end
    end
    return prof.barGlows
end

--- Get assignments for an action bar button (index-based)
function ns.GetButtonAssignments(barIdx, btnIdx)
    local bg = ns.GetBarGlows()
    local key = barIdx .. "_" .. btnIdx
    return bg.assignments[key]
end

--- Get assignments for a CDM bar icon (cooldownID-based)
function ns.GetCDMButtonAssignments(cooldownID)
    local bg = ns.GetBarGlows()
    local key = "cdm_" .. cooldownID
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
        if ns.IsBarBuffFamily(bar) then
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
                        }
                        trackedSet[sp.spellID] = entry
                        trackedOrder[#trackedOrder + 1] = entry
                    end
                end
            end
        end
    end

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
        for key, overlay in pairs(overlayFrames) do
            StopNativeGlow(overlay)
            overlay:Hide()
        end
        return
    end

    local activeKeys = {}
    for assignKey, buffList in pairs(bg.assignments) do
        if buffList and #buffList > 0 then
            local btn

            -- CDM bar assignment: "cdm_<cooldownID>"
            local cdID = assignKey:match("^cdm_(%d+)$")
            if cdID then
                cdID = tonumber(cdID)
                -- Find which CDM bar has this cooldownID (walks all bars)
                btn = FindCDMButtonByCooldownID(cdID)
            else
                -- Action bar assignment: "<barIdx>_<btnIdx>"
                local barIdx, btnIdx = assignKey:match("^(%d+)_(%d+)$")
                barIdx = tonumber(barIdx)
                btnIdx = tonumber(btnIdx)
                if barIdx and btnIdx then
                    btn = GetActionBarButton(barIdx, btnIdx)
                end
            end

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
                    overlay:SetFrameLevel(btn:GetFrameLevel() + 15)
                    overlay:SetAlpha(1)
                    overlay._assignEntry = entry
                    overlay:Show()
                    activeKeys[key] = true
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
--- Called each CDM tick (~10Hz from BuffTicker).
local function UpdateOverlayVisuals()
    local bg = _cachedBG
    if not bg or not bg.enabled then return end

    for key, overlay in pairs(overlayFrames) do
        if overlay:IsShown() and overlay._assignEntry then
            local entry = overlay._assignEntry
            local spellID = entry.spellID
            local mode = entry.mode or "ACTIVE"
            local onlyInCombat = entry.onlyInCombat == true

            local auraActive = false
            if spellID and spellID > 0 then
                local cache = ns._tickBlizzActiveCache
                if cache and cache[spellID] then
                    auraActive = true
                end
            end

            local shouldGlow
            if mode == "MISSING" then
                shouldGlow = not auraActive
            else
                shouldGlow = auraActive
            end

            if shouldGlow and onlyInCombat then
                shouldGlow = (InCombatLockdown and InCombatLockdown()) or UnitAffectingCombat("player") or false
            end

            -- Only update on state change (avoids restarting animations)
            if shouldGlow ~= lastStates[key] then
                lastStates[key] = shouldGlow
                if shouldGlow then
                    StopNativeGlow(overlay)
                    local style = entry.glowStyle or 1
                    -- Force Custom Shape Glow for custom-shaped icons
                    local glowParent = overlay:GetParent()
                    local gpfc = glowParent and ns._ecmeFC and ns._ecmeFC[glowParent]
                    local shapeName = gpfc and gpfc.shapeName
                    if shapeName and shapeName ~= "square" and shapeName ~= "csquare" and shapeName ~= "none" then
                        style = 2
                    end
                    local cr, cg, cb
                    if entry.colorMode == "class" then
                        local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                        cr, cg, cb = cc.r, cc.g, cc.b
                    elseif entry.colorMode == "custom" and entry.glowColor then
                        cr = entry.glowColor.r or 1
                        cg = entry.glowColor.g or 0.788
                        cb = entry.glowColor.b or 0.137
                    end
                    StartNativeGlow(overlay, style, cr, cg, cb)
                else
                    StopNativeGlow(overlay)
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

-------------------------------------------------------------------------------
--  Debug: /euibgdebug [spellID]
--  Diagnoses why a bar glow does/doesn't fire. Run WHILE the buff in question
--  is active (e.g. a pet-summon "buff" Blizzard shows on the CDM). Dumps:
--    1. bar glow assignments (the spellID each glow watches)
--    2. ns._tickBlizzActiveCache (the spellIDs we currently consider "active")
--    3. every live overlay + its last glow decision
--    4. every ACTIVE CDM viewer frame's state -- the key comparison is whether
--       Blizzard set the AURA flags (wasSetFromAura / auraInstanceID, which our
--       cache keys off) versus only a COOLDOWN/duration. Pet-summon "buffs" are
--       suspected to show via the cooldown, not an aura, so they never land in
--       the cache. The dump makes that visible.
-------------------------------------------------------------------------------
local function _sname(id) return (id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or "?" end
local function _safe(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

SLASH_EUIBGDEBUG1 = "/euibgdebug"
SlashCmdList.EUIBGDEBUG = function(msg)
    local focus = tonumber(msg)
    print("|cff00ccff== EUI Bar Glow Debug ==|r" .. (focus and (" focus spellID=" .. focus .. " (" .. _sname(focus) .. ")") or ""))

    -- 1. Assignments
    local bg = ns.GetBarGlows()
    print(("|cffffd200Assignments|r (enabled=%s):"):format(tostring(bg and bg.enabled)))
    if bg and bg.assignments then
        for key, list in pairs(bg.assignments) do
            if type(list) == "table" then
                for i = 1, #list do
                    local e = list[i]
                    print(("  [%s#%d] spellID=%s (%s) mode=%s"):format(
                        key, i, tostring(e.spellID), _sname(e.spellID), tostring(e.mode or "ACTIVE")))
                end
            end
        end
    end

    -- 2. Active cache (what we think is up right now)
    local cache = ns._tickBlizzActiveCache or {}
    print("|cffffd200_tickBlizzActiveCache (active spellIDs):|r")
    local any = false
    for sid in pairs(cache) do
        any = true
        local mark = (focus and sid == focus) and "  <-- FOCUS" or ""
        print(("  %s (%s)%s"):format(tostring(sid), _sname(sid), mark))
    end
    if not any then print("  (empty)") end

    -- 3. Live overlays + last glow decision
    print("|cffffd200Overlays:|r")
    for key, overlay in pairs(overlayFrames) do
        local e = overlay._assignEntry
        print(("  %s shown=%s sid=%s lastGlow=%s"):format(
            key, tostring(overlay:IsShown()), tostring(e and e.spellID), tostring(lastStates[key])))
    end

    -- 4. Walk the 4 CDM viewers; dump each ACTIVE frame's active-state signals.
    local viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    for _, vn in ipairs(viewers) do
        local vf = _G[vn]
        if vf and vf.itemFramePool and vf.itemFramePool.EnumerateActive then
            for frame in vf.itemFramePool:EnumerateActive() do
                local cdID = frame.cooldownID or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
                local sid, baseSid = ns.ResolveFrameSpellID(frame)
                if (not focus) or sid == focus or baseSid == focus then
                    print(("|cff88ff88[%s]|r cdID=%s sid=%s base=%s (%s)"):format(
                        vn, tostring(cdID), tostring(sid), tostring(baseSid), _sname(sid)))
                    -- THE aura flags our cache keys off:
                    print(("    AURA: wasSetFromAura=%s auraInstanceID=%s  shown=%s"):format(
                        _safe(frame.wasSetFromAura), _safe(frame.auraInstanceID), tostring(frame:IsShown())))
                    -- COOLDOWN/duration: pet-summons may show "active" only via this.
                    if frame.Cooldown and frame.Cooldown.GetCooldownTimes then
                        local ok, s, d = pcall(frame.Cooldown.GetCooldownTimes, frame.Cooldown)
                        if ok then print(("    COOLDOWN: start=%s dur=%s"):format(_safe(s), _safe(d))) end
                    end
                    -- Blizzard cooldown-info struct (hasAura / isBuff / linked etc.)
                    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        if info then
                            local parts = {}
                            for k, v in pairs(info) do
                                if type(v) ~= "table" then parts[#parts + 1] = k .. "=" .. _safe(v) end
                            end
                            print("    INFO: " .. table.concat(parts, " "))
                        end
                    end
                end
            end
        end
    end
    print("|cff00ccff== end ==|r")
end
