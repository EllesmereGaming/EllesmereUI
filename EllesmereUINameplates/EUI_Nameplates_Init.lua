if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Init.lua
--
--  Spec preset login, OnInitialize, OnEnable, the range features and hiding
--  enemy plates out of combat.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, ipairs, type = pairs, ipairs, type
local PP = EllesmereUI.PP
local UnitCanAttack = UnitCanAttack

local defaults, ENP, GetNPOutline, SetFSFont = I.defaults, I.ENP, I.GetNPOutline, I.SetFSFont
local GetTextSlot, SetupAuraCVars = I.GetTextSlot, I.SetupAuraCVars
local ApplyClassPowerSetting = I.ApplyClassPowerSetting
local RefreshThreatCache, SetProfile = I.RefreshThreatCache, I.SetProfile
local SetRawSetTex = I.SetRawSetTex

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-------------------------------------------------------------------------------
--  SPEC PRESET LOGIN HANDLER
--  Applies the spec-assigned preset on login and spec change, even before the
--  options UI is ever opened. Once the UI opens and RegisterSpecAutoSwitch runs,
--  the framework handler takes over PLAYER_SPECIALIZATION_CHANGED.
-------------------------------------------------------------------------------
do
    -- True when any preset's assigned spec list holds spec id (the store
    -- test for the WoW Forever spec pick below).
    ns.NP_PresetHoldsSpec = function(id, specMap)
        if not specMap then return false end
        for _, specList in pairs(specMap) do
            if specList[id] then return true end
        end
        return false
    end

    local function ApplySpecPresetFromDB()
        if not p then return end

        local specIndex = GetSpecialization and GetSpecialization() or 0
        local specID = specIndex and specIndex > 0
                       and GetSpecializationInfo(specIndex) or nil
        -- WoW Forever: the class counts as each of its retail specs; the first
        -- one in class order that a preset is assigned to picks the preset.
        if EllesmereUI.IS_FOREVER then
            specID = EllesmereUI.ForeverClassSpec(nil, ns.NP_PresetHoldsSpec, p._specAssignments)
        end
        if not specID then return end

        local K_ASSIGN  = "_specAssignments"
        local K_ACTIVE  = "_activePreset"
        local K_DEFAULT = "_specDefaultPreset"
        local K_PRESETS = "_presets"
        local K_SNAP    = "_builtinSnapshot"
        local K_CUSTOM  = "_customPreset"

        local specMap = p[K_ASSIGN]
        if not specMap then return end

        -- Check if any spec assignment exists at all
        local hasAny = false
        for _, specList in pairs(specMap) do
            if next(specList) then hasAny = true; break end
        end
        if not hasAny then return end

        -- Find which preset owns this specID
        local targetKey
        for presetKey, specList in pairs(specMap) do
            if specList[specID] then targetKey = presetKey; break end
        end
        -- Fall back to default preset if no direct match
        if not targetKey and p[K_DEFAULT] then
            targetKey = p[K_DEFAULT]
        end
        if not targetKey then return end

        local currentActive = p[K_ACTIVE] or "ellesmereui"
        if currentActive == targetKey then return end  -- already correct

        -- Apply the snapshot for targetKey
        local presetKeys = ns._displayPresetKeys  -- set below
        if not presetKeys then return end

        if targetKey == "ellesmereui" then
            for _, key in ipairs(presetKeys) do
                local def = ns.defaults[key]
                if type(def) == "table" and def.r then
                    p[key] = { r = def.r, g = def.g, b = def.b }
                else
                    p[key] = def
                end
            end
            p[K_SNAP] = nil
        elseif targetKey == "custom" then
            if p[K_CUSTOM] then
                for _, key in ipairs(presetKeys) do
                    local v = p[K_CUSTOM][key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            p[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            p[key] = v
                        end
                    end
                end
            end
        elseif targetKey:sub(1, 5) == "user:" then
            local name = targetKey:sub(6)
            local snap = p[K_PRESETS] and p[K_PRESETS][name]
            if snap then
                for _, key in ipairs(presetKeys) do
                    local v = snap[key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            p[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            p[key] = v
                        end
                    end
                end
            end
        end

        p[K_ACTIVE] = targetKey
        p[K_SNAP] = nil
    end

    -- Preset keys for the login handler (set once, never changes). Split into two
    -- tables and concatenated to stay under Lua 5.1's per-function constant limit.
    ns._displayPresetKeys = {
        "showBorder", "borderSize", "borderColor", "castBorderSize", "castBorderColor", "targetGlowStyle", "showTargetArrows",
        "showClassPower", "classPowerPos", "classPowerYOffset", "classPowerXOffset", "classPowerScale",
        "classPowerClassColors", "classPowerCustomColor", "classPowerGap",
        "classPowerShape", "classPowerBorder", "classPowerBorderColor", "classPowerBorderSize",
        "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
        "textSlotBottomLeft", "textSlotBottomRight",
        "nameYOffset",
        "healthBarHeight", "healthBarWidth", "castBarHeight",
    }
    ns._appendDisplayPresetKeys(ns._displayPresetKeys)

    -- Also handle spec changes that happen before the UI is ever opened
    local specLoginFrame = CreateFrame("Frame")
    specLoginFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specLoginFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then return end
        -- Re-read the profile reference: a spec swap may have changed the active
        -- profile, and _C() color lookups would read the old spec's stale data.
        SetProfile(ENP.db.profile)
        RefreshThreatCache()
        -- If the framework handler is registered, let it handle this
        if EllesmereUI and EllesmereUI._specSwitchRegistry
           and #EllesmereUI._specSwitchRegistry > 0 then
            return
        end
        ApplySpecPresetFromDB()
        if ns.RefreshAllSettings then ns.RefreshAllSettings() end
    end)

    -- Expose for calling from OnEnable (login time)
    ns._ApplySpecPresetFromDB = ApplySpecPresetFromDB
    _G._ENP_RefreshAllSettings = function() if ns.RefreshAllSettings then ns.RefreshAllSettings() end end
end

local npAddon = ENP
function npAddon:OnInitialize()
    ENP.db = EllesmereUI.Lite.NewDB("EllesmereUINameplatesDB", { profile = defaults })
    SetProfile(ENP.db.profile)
    ns.db = ENP.db
    -- Non-Target Opacity: derive the cached value at login (no plates exist yet,
    -- so the apply loop no-ops; SetUnit fades new plates as they spawn).
    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
    -- Append SharedMedia textures to runtime tables so SM texture keys resolve at runtime
    EllesmereUI.AppendSharedMediaTextures(
        ns.healthBarTextureNames,
        ns.healthBarTextureOrder,
        nil,
        ns.healthBarTextures
    )
end
function npAddon:OnEnable()
    -- Re-read profile: PreSeedSpecProfile may have re-pointed db.profile between OnInitialize and OnEnable.
    SetProfile(ENP.db.profile)
    -- A profile already on a stock style gets its one-time bar texture seed
    -- before the first plate builds (the Style page seeds on the switch);
    -- its own textures go to the EllesmereUI slot first, so a switch back
    -- restores them.
    if ns.NP_Blizz() then
        if not p.stockBarTextureSeeded and EllesmereUI.BankEuiStyleSlot then
            EllesmereUI.BankEuiStyleSlot(p, ns._npStyleSlotKeys)
        end
        ns.NP_SeedStock(p)
    end
    -- The same for the Classic cast colours. An EllesmereUI slot banked before
    -- they rode the slots gains their current values first, so a switch back
    -- still restores the user's own.
    if ns.NP_Classic() and not p.classicCastSeeded then
        local slots = p._styleSlots
        local eui = type(slots) == "table" and slots.eui
        if type(eui) == "table" then
            local keys = ns._npClassicCastKeys
            for i = 1, #keys do
                local k = keys[i]
                if eui[k] == nil then eui[k] = p[k] end
            end
        elseif EllesmereUI.BankEuiStyleSlot then
            EllesmereUI.BankEuiStyleSlot(p, ns._npStyleSlotKeys)
        end
        ns.NP_SeedClassic(p)
    end
    -- WoW Forever: the same for its Left Text seed (the level box shows the
    -- level), the other looks' value going to its Forever-only slot first,
    -- and the level edges the box follows (armed only while it shows).
    if ns.NP_Forever() then
        if not p.foreverLevelSlotSeeded then
            local s = p._foreverStyleSlots
            if type(s) ~= "table" then s = {}; p._foreverStyleSlots = s end
            s.eui = { textSlotLeft = p.textSlotLeft }
            ns.NP_SeedForever(p)
        end
        ns.NP_ForeverWatchLevels()
    end
    SetRawSetTex((PP and PP.RawSetTexture) or function(t, v) t:SetTexture(v) end)
    SetupAuraCVars()
    ApplyClassPowerSetting()
    -- Apply spec-assigned preset on login (before UI is opened)
    if ns._ApplySpecPresetFromDB then ns._ApplySpecPresetFromDB() end
    -- Text Coloring slot (with Target of Target and the bottom slots), Threat %
    -- and Show Threat Colors flags for the first plates, after the seeds and the
    -- spec preset above rewrote the slots (RefreshAllSettings keeps them after).
    ns.NP_RefreshSlotClassFlags()
    ns.NP_RefreshThreatPctFlag()
    ns.NP_RefreshThreatColorFlag()
    if ns.RangeText_Apply then ns.RangeText_Apply() end
    -- Debuff coloring last: it reads the final profile, and Color Border reads
    -- the plate style, which latches for the session on its first read.
    if ns.DebuffColors_Refresh then ns.DebuffColors_Refresh() end
end

-------------------------------------------------------------------------------
--  Nameplate range features: target distance text plus out-of-range plate alpha.
--  Distance text is a range BUCKET on the target's nameplate -- "15+" =
--  beyond the 15yd rung, inside the next longer one. The API exposes no exact enemy distance;
--  the lower bound comes from the shared range engine's spell ladder (EllesmereUI_Range.lua),
--  active only while either feature is enabled. Distance-text anchoring: 5px left of whatever
--  text occupies the Right Text core slot, else just outside the health bar's right edge. Zero
--  cost while both are disabled; enabled, one OnUpdate driver ticks 5x/s. Secret range results
--  are skipped -- fail-open to no text or fade, never an error.
-------------------------------------------------------------------------------
do
    -- Single-table state: this file sits at Lua 5.1's 200-local cap, so the whole feature uses ONE chunk local (RT), everything else as table fields.
    local RT = { acc = 0 }

    function RT.Anchor(plate)
        RT.fs:ClearAllPoints()
        local offX = (p and p.rangeTextOffsetX) or 0
        local offY = (p and p.rangeTextOffsetY) or 0
        local rightEl = GetTextSlot("textSlotRight")
        local anchorTo
        if ns.IsNameElement(rightEl) then
            anchorTo = plate.name
        elseif rightEl == "level" then
            anchorTo = plate.levelText
        elseif rightEl == "targetOfTarget" then
            anchorTo = plate.totText
        elseif rightEl and rightEl ~= "none" then
            local ca = plate._cachedHealthSlots
            if ca then
                for i = 1, ca._count or 0 do
                    local e = ca[i]
                    if e and e.slotKey == "textSlotRight" and e.fs then
                        anchorTo = e.fs
                        break
                    end
                end
            end
        end
        if anchorTo and anchorTo.IsShown and anchorTo:IsShown() then
            RT.fs:SetPoint("RIGHT", anchorTo, "LEFT", -5 + offX, offY)
        else
            -- WoW Forever: past the level box right of the bar.
            RT.fs:SetPoint("LEFT", plate.health or plate, "RIGHT", 5 + offX + ns.NP_ForeverSide(), offY)
        end
    end

    function RT.Appearance()
        SetFSFont(RT.fs, (p and p.rangeTextSize) or defaults.rangeTextSize, GetNPOutline())
        local c = (p and p.rangeTextColor) or defaults.rangeTextColor
        RT.fs:SetTextColor(c.r, c.g, c.b, 1)
    end

    function RT.Detach()
        RT.plate = nil
        if RT.carrier then
            RT.carrier:Hide()
            RT.carrier:SetParent(nil)
        end
    end

    function RT.Tick()
        local plate = ns._cachedTargetPlate
        if not plate or not plate.unit or not plate:IsShown() then
            if RT.plate then RT.Detach() end
            return
        end
        if plate ~= RT.plate then
            if not RT.carrier then
                RT.carrier = CreateFrame("Frame")
                RT.carrier:SetSize(2, 2)
                RT.fs = RT.carrier:CreateFontString(nil, "OVERLAY")
            end
            RT.carrier:SetParent(plate)
            RT.carrier:SetPoint("CENTER", plate, "CENTER", 0, 0)
            -- Well above the health bar/text frames: with the Right Text slot occupied the
            -- text sits ON the bar, and a low frame level would draw it underneath the fill.
            RT.carrier:SetFrameLevel(plate:GetFrameLevel() + 30)
            RT.plate = plate
            RT.Appearance()
            RT.Anchor(plate)
            RT.carrier:Show()
        end
        -- "0+" (basically melee) shows nothing: the indicator only matters at distance. Queried
        -- as "target" rather than plate.unit -- this is the target's plate by definition, and
        -- the token lets the shared engine serve the QoL text from one cached walk.
        local lower = EllesmereUI.Range_LowerBound("target")
        if lower and lower > 0 then
            RT.fs:SetText(lower .. "+")
            RT.fs:Show()
        else
            RT.fs:Hide()
        end
    end

    -- Round-robin BUDGETED sweep: each range verdict is a multi-C-call probe
    -- walk, so classifying every plate every tick is unbounded in crowded
    -- scenes (40 plates x 5Hz x spell+item probes was thousands of C calls
    -- per second). 8 plates per 0.2s tick = full coverage inside ~1s at a
    -- full plate cap, imperceptible for a fade; small scenes still resolve
    -- every tick. Verdicts come from Range_SweepBeyond (per-unit short-TTL
    -- cache; never touches the crosshair/QoL single-slot target caches).
    -- Melee note: at cutoff 5 verdicts rely on the protection-gated item
    -- walk, so in instanced combat the fade can degrade to "no fade" for
    -- melee specs -- deliberate fail-open, never a blocked action.
    function RT.FadeTick()
        local customCutoff = p and p.outOfRangeMode == "custom" and p.outOfRangeCustomRange
        local cutoff = EllesmereUI.Range_GetAttackCutoff(customCutoff)
        local q = RT.fadeQ
        if not q then q = {}; RT.fadeQ = q end
        if not RT.fadeIdx or RT.fadeIdx > #q then
            -- New cycle: snapshot the live plate set (reused table, one wipe
            -- per cycle). Plates that detach mid-cycle are re-checked below.
            wipe(q)
            for _, plate in pairs(ns.plates) do q[#q + 1] = plate end
            RT.fadeIdx = 1
        end
        local budget = 8
        while RT.fadeIdx <= #q and budget > 0 do
            local plate = q[RT.fadeIdx]
            RT.fadeIdx = RT.fadeIdx + 1
            budget = budget - 1
            local unit = plate.unit
            if unit and ns.plates[unit] == plate then
                local beyond
                -- Cleanly-non-attackable plates (friendly/neutral NPCs) can
                -- never answer an attack-range probe; skip the whole walk.
                -- Only a READABLY-false flag skips -- a secret answer falls
                -- through to the probes, whose own gates fail open.
                local okAtt, att = pcall(UnitCanAttack, "player", unit)
                local skip = okAtt and not (issecretvalue and issecretvalue(att)) and att == false
                if not skip then
                    beyond = EllesmereUI.Range_SweepBeyond(unit, cutoff)
                end
                local alpha = beyond == true and ns._oorAlpha or 1
                if (plate._oorCurAlpha or 1) ~= alpha then
                    plate._oorCurAlpha = alpha
                    ns.NT_Apply(plate)
                end
            end
        end
    end

    function RT.ResetFade()
        -- Drop the round-robin cursor and its plate snapshot too: a disable
        -- mid-cycle must not pin recycled plates in the reused queue.
        if RT.fadeQ then wipe(RT.fadeQ) end
        RT.fadeIdx = nil
        for _, plate in pairs(ns.plates) do
            if plate._oorCurAlpha then
                plate._oorCurAlpha = nil
                ns.NT_Apply(plate)
            end
        end
    end

    -- Options: re-apply font/color/anchor on the live attachment.
    ns.RangeText_Refresh = function()
        if RT.plate and RT.fs then
            RT.Appearance()
            RT.Anchor(RT.plate)
        end
    end

    ns.RangeText_Apply = function()
        local alpha = tonumber(p and p.outOfRangeAlpha) or defaults.outOfRangeAlpha
        if alpha < 0 then alpha = 0 elseif alpha > 100 then alpha = 100 end
        ns._oorAlpha = alpha / 100
        local textEnabled = p and p.rangeTextEnabled
        ns._oorFadeEnabled = ((p and p.outOfRangeMode) or defaults.outOfRangeMode) ~= "disabled" and ns._oorAlpha < 1
        local fadeEnabled = ns._oorFadeEnabled
        if textEnabled or fadeEnabled then
            if not RT.drv then
                RT.drv = CreateFrame("Frame")
                RT.drv:Hide()
                RT.drv:SetScript("OnUpdate", function(_, dt)
                    RT.acc = RT.acc + dt
                    if RT.acc < 0.2 then return end
                    RT.acc = 0
                    if p and p.rangeTextEnabled then RT.Tick() end
                    if ns._oorFadeEnabled then RT.FadeTick() end
                end)
            end
            -- Ladder builds and invalidation live in the shared range engine.
            EllesmereUI.Range_SetActive("npRange", true)
            RT.drv:Show()
        else
            EllesmereUI.Range_SetActive("npRange", false)
            if RT.drv then RT.drv:Hide() end
        end
        if not textEnabled then RT.Detach() end
        if not fadeEnabled then RT.ResetFade() end
    end

end

-------------------------------------------------------------------------------
--  Hide Enemy Nameplates Out of Combat (EXTRAS): drives nameplateShowEnemies,
--  the same CVar behind Blizzard's combat-legal "Show Enemy Name Plates"
--  keybind, so plates flip cleanly at the combat edges. The combat events are
--  registered only while the setting is on (zero cost off); disabling the
--  setting restores plates ON only if this feature ever hid them. All state
--  lives on ns -- this chunk is at the 200-local cap.
-------------------------------------------------------------------------------
ns._oocPlatesCtl = CreateFrame("Frame")
ns.ApplyOOCPlates = function()
    local ctl = ns._oocPlatesCtl
    local on = p and p.hideEnemyPlatesOOC == true
    if on then
        ctl:RegisterEvent("PLAYER_REGEN_DISABLED")
        ctl:RegisterEvent("PLAYER_REGEN_ENABLED")
        ctl:RegisterEvent("PLAYER_ENTERING_WORLD")
        ns._oocPlatesOwned = true
        -- Read-guarded: RefreshAllSettings calls this on every nameplate settings
        -- change, and a redundant SetCVar broadcasts CVAR_UPDATE to the whole UI.
        local want = InCombatLockdown() and "1" or "0"
        if GetCVar("nameplateShowEnemies") ~= want then
            EllesmereUI.SetCVar("nameplateShowEnemies", want, "EllesmereUINameplates")
        end
    else
        ctl:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ctl:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ctl:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if ns._oocPlatesOwned then
            ns._oocPlatesOwned = nil
            EllesmereUI.SetCVar("nameplateShowEnemies", "1", "EllesmereUINameplates")
        end
    end
end
ns._oocPlatesCtl:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ns.ApplyOOCPlates()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        EllesmereUI.SetCVar("nameplateShowEnemies", "1", "EllesmereUINameplates")
    elseif not InCombatLockdown() then
        -- REGEN_ENABLED, or a world entry that lands out of combat.
        EllesmereUI.SetCVar("nameplateShowEnemies", "0", "EllesmereUINameplates")
    end
end)
ns._oocPlatesCtl:RegisterEvent("PLAYER_LOGIN")


I.broken = false
