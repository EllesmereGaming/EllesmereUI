if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
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

-------------------------------------------------------------------------------
--  Stack-threshold gate (secret-safe)
--  Applications counts read SECRET even in open-world content, so the
--  threshold compare can never happen in Lua (a hard error on a secret).
--  Same trick -- and same 5-operator support -- as the per-icon Glow at
--  Stacks feature (EllesmereUICdmHooks.lua's StackGlow_Configure/Feed):
--  one-unit StatusBar windows perform lower/upper bounds C-side via
--  SetValue; equality intersects one of each (two gates). A fixed-size
--  CLAMPTOBLACKADDITIVE mask rides each gate's fill edge and is handed to
--  StartNativeGlow so the glow texture itself is cropped by the fill(s) --
--  Lua never reads the count, just forwards it.
-------------------------------------------------------------------------------
local stackGates = {}  -- [key] = { gate,mask,fill, gate2,mask2,fill2, pad, threshold, operator, closeValue, openValue, closeValue2 }

local function StackGateSize(overlay)
    local w, h = overlay:GetWidth(), overlay:GetHeight()
    if not w or w < 5 then w = 36 end
    if not h or h < 5 then h = w end
    return w, h
end

local function NewStackGate(overlay, pad)
    local gate = CreateFrame("StatusBar", nil, overlay)
    gate:SetPoint("TOPLEFT", overlay, "TOPLEFT", -pad, pad)
    gate:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", pad, -pad)
    gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fill = gate:GetStatusBarTexture()
    if fill then fill:SetAlpha(0) end
    gate:EnableMouse(false)
    local mask = gate:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8x8",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    return gate, mask, fill
end

local function SizeStackGateMasks(st, width, height)
    local w, h = width + st.pad * 2, height + st.pad * 2
    st.mask:SetSize(w, h)
    if st.mask2 then st.mask2:SetSize(w, h) end
end

local function StackGlowMatches(value, operator, threshold)
    if operator == "lt" then return value < threshold end
    if operator == "lte" then return value <= threshold end
    if operator == "eq" then return value == threshold end
    if operator == "gt" then return value > threshold end
    return value >= threshold
end

local function EnsureStackGate(overlay, key)
    local st = stackGates[key]
    if not st then
        st = {}
        stackGates[key] = st
        local w, h = StackGateSize(overlay)
        local pad = math.ceil(math.max(w, h) * 0.4)
        if pad < 12 then pad = 12 end
        st.pad = pad
        st.gate, st.mask, st.fill = NewStackGate(overlay, pad)
        SizeStackGateMasks(st, w, h)
    end
    return st
end

-- (Re)configure the gate(s) for the current threshold/operator. Mirrors
-- StackGlow_Configure's edge math exactly: lower bounds park the mask left
-- and open at max; upper bounds open at min and park right; equality
-- intersects one lower + one upper gate (both masks applied to the glow).
local function ConfigureStackGate(overlay, key, threshold, operator)
    local st = EnsureStackGate(overlay, key)
    if st.threshold == threshold and st.operator == operator then return st end
    st.threshold, st.operator = threshold, operator

    local upper = operator == "lt" or operator == "lte"
    local edge = (operator == "gt" or operator == "lte") and threshold + 1 or threshold
    st.gate:SetMinMaxValues(edge - 1, edge)
    st.mask:ClearAllPoints()
    st.mask:SetPoint(upper and "LEFT" or "RIGHT", st.fill or st.gate, "RIGHT", 0, 0)
    st.closeValue = upper and edge or edge - 1
    st.openValue = upper and edge - 1 or edge

    if operator == "eq" and not st.gate2 then
        local w, h = StackGateSize(overlay)
        st.gate2, st.mask2, st.fill2 = NewStackGate(overlay, st.pad)
        SizeStackGateMasks(st, w, h)
    end
    if st.gate2 then
        local equality = operator == "eq"
        st.gate2:SetMinMaxValues(equality and threshold or 0, equality and threshold + 1 or 1)
        st.mask2:ClearAllPoints()
        st.mask2:SetPoint(equality and "LEFT" or "RIGHT", st.fill2 or st.gate2, "RIGHT", 0, 0)
        st.closeValue2 = equality and threshold + 1 or 0
    end
    return st
end

-- Equality needs a SECOND mask (lower + upper gate intersect). StartNativeGlow's
-- opts.maskWith already applies gateSt.mask; this adds gateSt.mask2 on top of
-- the same fresh textures (must run right after the Start call).
local function ApplySecondStackGateMask(overlay, gateSt)
    if not (gateSt and gateSt.mask2 and EllesmereUI.Glows and EllesmereUI.Glows.ApplyMaskWith) then return end
    EllesmereUI.Glows.ApplyMaskWith(overlay, gateSt.mask2)
end

--- Rebuild overlay frames from assignments
local function SetupOverlays()
    local bg = ns.GetBarGlows()
    _cachedBG = bg
    if not bg or not bg.enabled then
        for key, overlay in pairs(overlayFrames) do
            StopNativeGlow(overlay)
            overlay:Hide()
        end
        ns._anyBarGlowStackGate = false
        return
    end

    -- Whether the buff-tick's aura pool-walk should bother reading applications
    -- at all (EllesmereUICdmHooks.lua). Zero At Stacks assignments means zero
    -- extra work there -- no ReadBuffApplications call, no stack cache writes.
    local anyStack = false

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
                    if entry.stackEnabled then anyStack = true end
                end
            end
        end
    end
    ns._anyBarGlowStackGate = anyStack

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

            -- At Stacks (ACTIVE mode only): fed to the gate(s) every tick
            -- regardless of state-change dedupe below, so the mask tracks a
            -- live stack count while the glow keeps running. A KNOWN count
            -- that fails the comparison stops the glow outright (Lua-side,
            -- cheap); an UNKNOWN/SECRET count never blocks it -- the gate's
            -- open value / the engine-side clamp decide instead.
            local gateSt
            local applyMask2 = false
            if shouldGlow and mode ~= "MISSING" and entry.stackEnabled and spellID and spellID > 0 then
                local threshold = tonumber(entry.stackThreshold) or 2
                local operator = entry.stackOperator or "gte"
                gateSt = ConfigureStackGate(overlay, key, threshold, operator)
                -- Same sid/baseSID/linked resolution as auraActive above, so
                -- this matches whatever spellID the entry was saved against
                -- (a raw GetPlayerAuraBySpellID(spellID) query missed on the
                -- override/linked-id drift these tracked buffs can have).
                local stacks = ns._tickBlizzAuraStacks and ns._tickBlizzAuraStacks[spellID]
                -- Secret probe FIRST: any truthy/nil/relational test on a
                -- secret value hard-errors, not just `<`/`>=`.
                local secret = issecretvalue and issecretvalue(stacks)
                local feedValue
                if secret then
                    feedValue = stacks
                elseif stacks == nil then
                    feedValue = gateSt.openValue
                elseif not StackGlowMatches(stacks, operator, threshold) then
                    shouldGlow = false
                else
                    feedValue = stacks
                end
                if shouldGlow then
                    gateSt.gate:SetValue(feedValue)
                    if gateSt.gate2 then
                        gateSt.gate2:SetValue(operator == "eq" and feedValue or 1)
                    end
                    applyMask2 = gateSt.mask2 ~= nil
                end
            end

            -- Only update start/stop on state change (avoids restarting animations)
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
                    if gateSt then
                        StartNativeGlow(overlay, style, cr, cg, cb, { maskWith = gateSt.mask })
                        if applyMask2 then ApplySecondStackGateMask(overlay, gateSt) end
                    else
                        StartNativeGlow(overlay, style, cr, cg, cb)
                    end
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
