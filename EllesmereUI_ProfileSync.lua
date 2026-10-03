if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_ProfileSync.lua
--  Profile sync mirror groups, per-module sync exclusions, and the sync
--  popup anchored to the sidebar. Loads after EllesmereUI_Fonts.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
-- Private namespace shared with EllesmereUI.lua (sidebar buttons).
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)

-------------------------------------------------------------------------------
--  Profile Sync System (mirror groups)
--  A module's sync set is a MEMBERSHIP group (popup adds the configuring profile too).
--  Two-way: active member pushes a selective copy to others on sync click, logout, and
--  profile switch; outside profiles never push in. Storage: EllesmereUIDB.syncedModules
--  = { [folder] = { [profileName] = true } }. Exclusions: EllesmereUI._syncExclusions
--  [folder] = { key = true }; dot-wildcard "bars.*.growDirection" skips that key in any sub-table of bars.
-------------------------------------------------------------------------------
do
    -- Modules that should NOT get a sync icon (no per-profile settings)
    local SYNC_EXEMPT = { EllesmereUIPartyMode = true }
    EllesmereUI._syncExempt = SYNC_EXEMPT

    -- Modules with a sync icon but no per-profile data (always "synced"). BlizzardSkin hosts
    -- Dragon Riding's per-profile DB; its sync icon routes to EllesmereUIDragonRiding via syncFolder.
    local SYNC_GLOBAL_ONLY = { EllesmereUIForeverEssentials = true }
    EllesmereUI._syncGlobalOnly = SYNC_GLOBAL_ONLY

    -- Exclusion registry: keys NOT copied during sync (flat or dot-wildcard, see banner)
    local syncExclusions = {}
    EllesmereUI._syncExclusions = syncExclusions

    function EllesmereUI.RegisterSyncExclusions(folder, keys)
        if not syncExclusions[folder] then syncExclusions[folder] = {} end
        local ex = syncExclusions[folder]
        for _, k in ipairs(keys) do
            ex[k] = true
        end
    end

    -- Merged exclusions for ONE src->dst copy: static registry plus every setting EITHER
    -- profile holds a spec/conditional OVERRIDE entry for (override-owned keys never sync --
    -- the override system owns them; a pushed blob would drift from the dest's recorded values).
    -- PURE READ of profile tables only (no override store creation/harvest/apply/capture).
    -- Returns staticEx unchanged (zero alloc) when neither profile has override data, else a
    -- fresh table (shared registry never mutated); callers pcall and fall back to staticEx on error.
    -- fkey = folder.."\31"..path, segments joined by "\30" (mirrors SplitFKey in
    -- EllesmereUI_SpecOverrides.lua); matcher walks the tree dot-joined so gsub("\30",".") is exact.
    EllesmereUI._SyncExclusionsWithOverrides = function(folder, staticEx, srcProf, dstProf)
        local merged
        local function ensure()
            if not merged then
                merged = {}
                if staticEx then for k in pairs(staticEx) do merged[k] = true end end
            end
        end
        local function addStore(store)
            if type(store) ~= "table" then return end
            for _, entry in ipairs(store) do
                local vals = type(entry) == "table" and entry.values
                if type(vals) == "table" then
                    for _, m in pairs(vals) do  -- default map + every spec/gid map
                        if type(m) == "table" then
                            for fkey in pairs(m) do
                                if type(fkey) == "string" then
                                    local f, path = fkey:match("^([^\31]+)\31(.*)$")
                                    if f == folder and path and path ~= "" then
                                        ensure()
                                        merged[path:gsub("\30", ".")] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        local function addProf(prof)
            if type(prof) ~= "table" then return end
            addStore(prof.specOverrides)
            addStore(prof.condOverrides)
            if folder == "EllesmereUIRaidFrames" then
                -- BM forks are layer-shaped, not fkey-shaped: the fork system writes
                -- bmIndicators/bmSimple/bmDisplayMode/bmIconZoom straight into the live RF blob,
                -- so if EITHER profile carries ANY BM layer, those keys are fork territory and
                -- must not sync (emptiness check mirrors the BM harvest's zero-cost gate).
                local s, c = prof.specBmOverrides, prof.condBmOverrides
                if (type(s) == "table" and (s.active or s.baselineLayout
                        or (type(s.layouts) == "table" and next(s.layouts))))
                   or (type(c) == "table" and type(c.layouts) == "table"
                        and next(c.layouts)) then
                    ensure()
                    merged.bmIndicators  = true
                    merged.bmSimple      = true
                    merged.bmDisplayMode = true
                    merged.bmIconZoom    = true
                    merged.bm2           = true   -- v2 payload rides BM layers
                end
                -- Debuff Manager forks own the dmDebuff subtree the same way.
                local ds, dc = prof.specDmOverrides, prof.condDmOverrides
                if (type(ds) == "table" and (ds.active or ds.baselineLayout
                        or (type(ds.layouts) == "table" and next(ds.layouts))))
                   or (type(dc) == "table" and type(dc.layouts) == "table"
                        and next(dc.layouts)) then
                    ensure()
                    merged.dmDebuff = true
                end
            end
        end
        addProf(srcProf)
        addProf(dstProf)
        return merged or staticEx
    end

    -- Selective deep-copy: src minus excluded keys (flat "barPositions" or wildcard
    -- "bars.*.growDirection" = skip that key in any sub-table of "bars").
    local function SelectiveCopy(src, exclusions, parentPath)
        if type(src) ~= "table" then return src end
        local copy = {}
        for k, v in pairs(src) do
            local keyStr = tostring(k)
            local fullKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not exclusions[fullKey] then
                if type(v) == "table" then
                    -- Wildcard parent check (e.g. "bars" in "bars.*.X")
                    local isWildcardParent = false
                    local childExclusions = nil
                    for exKey in pairs(exclusions) do
                        local prefix, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (a bare-name collision is not a wildcard parent)
                        if prefix and fullKey == prefix then
                            isWildcardParent = true
                            if not childExclusions then childExclusions = {} end
                            childExclusions[childKey] = true
                        end
                    end
                    if isWildcardParent and childExclusions then
                        -- Copy the container but apply child exclusions to each sub-table
                        local containerCopy = {}
                        for ck, cv in pairs(v) do
                            if type(cv) == "table" then
                                local subCopy = {}
                                for sk, sv in pairs(cv) do
                                    if not childExclusions[tostring(sk)] then
                                        if type(sv) == "table" then
                                            subCopy[sk] = SelectiveCopy(sv, {})
                                        else
                                            subCopy[sk] = sv
                                        end
                                    end
                                end
                                containerCopy[ck] = subCopy
                            else
                                containerCopy[ck] = cv
                            end
                        end
                        copy[k] = containerCopy
                    else
                        copy[k] = SelectiveCopy(v, exclusions, fullKey)
                    end
                else
                    copy[k] = v
                end
            end
        end
        return copy
    end
    EllesmereUI._SelectiveCopy = SelectiveCopy

    -- Exclusion-aware deep overlay for destinations with existing data: writes src into dst
    -- leaf-by-leaf wherever an exclusion path (flat/dotted/wildcard) touches the subtree, so
    -- excluded keys keep dest values (replacing a parent whole would delete them).
    function EllesmereUI._SelectiveOverlay(src, dst, exclusions, deepCopy, parentPath)
        for k, v in pairs(src) do
            local keyStr = tostring(k)
            local fullKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not exclusions[fullKey] then
                if type(v) == "table" then
                    -- Wildcard parent and/or dotted exclusions deeper in this subtree
                    local childExclusions = nil
                    local hasNested = false
                    for exKey in pairs(exclusions) do
                        local prefix, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (same rule as SelectiveCopy)
                        if prefix and fullKey == prefix then
                            if not childExclusions then childExclusions = {} end
                            childExclusions[childKey] = true
                        elseif exKey:sub(1, #fullKey + 1) == (fullKey .. ".") then
                            hasNested = true
                        end
                    end
                    if childExclusions then
                        -- Merge each sub-table, preserving excluded child keys
                        if type(dst[k]) ~= "table" then dst[k] = {} end
                        local dstContainer = dst[k]
                        for ck, cv in pairs(v) do
                            if type(cv) == "table" then
                                if type(dstContainer[ck]) ~= "table" then dstContainer[ck] = {} end
                                local dstSub = dstContainer[ck]
                                for sk, sv in pairs(cv) do
                                    if not childExclusions[tostring(sk)] then
                                        dstSub[sk] = type(sv) == "table" and deepCopy(sv) or sv
                                    end
                                end
                            else
                                dstContainer[ck] = cv
                            end
                        end
                    elseif hasNested then
                        if type(dst[k]) ~= "table" then dst[k] = {} end
                        EllesmereUI._SelectiveOverlay(v, dst[k], exclusions, deepCopy, fullKey)
                    else
                        dst[k] = deepCopy(v)
                    end
                else
                    dst[k] = v
                end
            end
        end
    end

    function EllesmereUI.IsProfileSynced(folder, profileName)
        if not EllesmereUIDB then return false end
        local sm = EllesmereUIDB.syncedModules
        if not sm or not sm[folder] then return false end
        local targets = sm[folder]
        return type(targets) == "table" and targets[profileName] == true
    end

    function EllesmereUI.GetSyncedProfiles(folder)
        if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return {} end
        local targets = EllesmereUIDB.syncedModules[folder]
        if type(targets) == "table" then return targets end
        return {}
    end

    -- Check if ANY profile is synced for a module (for icon state)
    function EllesmereUI.IsModuleSynced(folder)
        if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return false end
        local targets = EllesmereUIDB.syncedModules[folder]
        if type(targets) ~= "table" then return false end
        for _, v in pairs(targets) do if v then return true end end
        return false
    end

    -- Sync one module from active profile to specific target profiles
    function EllesmereUI.SyncModuleToProfiles(folder, targetProfiles)
        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        local src = EllesmereUIDB.profiles[active]
        if not src or not src.addons or not src.addons[folder] then return end
        local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
        if not DeepCopy then return end

        local staticEx = syncExclusions[folder]
        local exFn = EllesmereUI._SyncExclusionsWithOverrides
        for profName in pairs(targetProfiles) do
            if profName ~= active then
                local prof = EllesmereUIDB.profiles[profName]
                if prof then
                    if not prof.addons then prof.addons = {} end
                    -- Merge both profiles' override-entry paths into the static set
                    -- (fail-open: any derive error keeps static-only behavior).
                    local exclusions = staticEx
                    if exFn then
                        local ok, m = pcall(exFn, folder, staticEx, src, prof)
                        if ok and m then exclusions = m end
                    end
                    if exclusions and next(exclusions) then
                        local dst = prof.addons[folder]
                        if not dst then
                            -- First sync to this profile: no dest values to preserve
                            prof.addons[folder] = SelectiveCopy(src.addons[folder], exclusions)
                        else
                            -- Overlay leaf-by-leaf so excluded keys keep dest values
                            EllesmereUI._SelectiveOverlay(src.addons[folder], dst, exclusions, DeepCopy)
                        end
                    else
                        -- Full blob copy (no exclusions)
                        prof.addons[folder] = DeepCopy(src.addons[folder])
                    end
                end
            end
        end
    end

    -- Equalize a module across group members from an explicit source ("seed"). Non-active dests
    -- get a selective copy; an ACTIVE dest is written IN PLACE (live db.profile refs stay valid),
    -- defaults re-merged (stored blobs are sparse), then UI refreshed. Excluded (layout) keys keep each dest's values.
    function EllesmereUI.SyncModuleFromProfile(folder, srcName, targets)
        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        if srcName == active then
            EllesmereUI.SyncModuleToProfiles(folder, targets)
            return
        end
        local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
        if not DeepCopy then return end
        local srcProf = EllesmereUIDB.profiles[srcName]
        local srcData = srcProf and srcProf.addons and srcProf.addons[folder]
        if not srcData then return end

        local staticEx = syncExclusions[folder]
        local exFn = EllesmereUI._SyncExclusionsWithOverrides
        for profName in pairs(targets) do
            if profName ~= srcName then
                local prof = EllesmereUIDB.profiles[profName]
                if prof then
                    if not prof.addons then prof.addons = {} end
                    -- Same override-ownership exclusions as SyncModuleToProfiles.
                    local exclusions = staticEx
                    if exFn then
                        local ok, m = pcall(exFn, folder, staticEx, srcProf, prof)
                        if ok and m then exclusions = m end
                    end
                    local dst = prof.addons[folder]
                    if profName == active then
                        -- Live profile: adopt in place, never replace the table
                        if type(dst) ~= "table" then
                            dst = {}
                            prof.addons[folder] = dst
                        end
                        if exclusions and next(exclusions) then
                            EllesmereUI._SelectiveOverlay(srcData, dst, exclusions, DeepCopy)
                        else
                            wipe(dst)
                            for k, v in pairs(srcData) do
                                dst[k] = type(v) == "table" and DeepCopy(v) or v
                            end
                        end
                    elseif not (exclusions and next(exclusions)) then
                        prof.addons[folder] = DeepCopy(srcData)
                    elseif type(dst) == "table" then
                        EllesmereUI._SelectiveOverlay(srcData, dst, exclusions, DeepCopy)
                    else
                        prof.addons[folder] = SelectiveCopy(srcData, exclusions)
                    end
                end
            end
        end

        if targets[active] then
            -- Re-merge defaults into the adopted live table, then refresh addons and any open options page
            local reg = EllesmereUI.Lite._dbRegistry
            if reg then
                for _, rdb in ipairs(reg) do
                    if rdb.folder == folder then
                        if rdb._profileDefaults and rdb.profile then
                            EllesmereUI.Lite.DeepMergeDefaults(rdb.profile, rdb._profileDefaults)
                        end
                        break
                    end
                end
            end
            if EllesmereUI.RefreshAllAddons then
                EllesmereUI.RefreshAllAddons()
            end
            if EllesmereUI.RefreshPage then
                EllesmereUI:RefreshPage()
            end
        end
    end

    -- Pre-logout push to other group members. Only a MEMBER pushes; an outside
    -- profile must never overwrite member data regardless of what is active.
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if EllesmereUI.Lite and EllesmereUI.Lite.RegisterPreLogout then
            EllesmereUI.Lite.RegisterPreLogout(function()
                if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return end
                local active = EllesmereUIDB.activeProfile or "Default"
                for folder, targets in pairs(EllesmereUIDB.syncedModules) do
                    if type(targets) == "table" and targets[active] then
                        EllesmereUI.SyncModuleToProfiles(folder, targets)
                    end
                end
            end)
        end
    end)
end


-------------------------------------------------------------------------------
--  Sync Exclusions per Module -- keys listed here are NOT copied when syncing between profiles.
-------------------------------------------------------------------------------
EllesmereUI.RegisterSyncExclusions("EllesmereUIActionBars", {
    "barPositions",
    "bars.*.growDirection",
    "bars.*.orientation",
    "bars.*.buttonWidth",
    "bars.*.buttonHeight",
    "bars.*.targetWidth",
    "bars.*.targetHeight",
    "bars.*.width",
    "bars.*.height",
    "bars.*.overrideNumIcons",
    "bars.*.overrideNumRows",
    "bars.*.numIcons",
    "bars.*.numRows",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIUnitFrames", {
    "positions",
    "player.frameWidth", "player.healthHeight",
    "target.frameWidth", "target.healthHeight",
    "playerTarget.frameWidth", "playerTarget.healthHeight",
    "targettarget.frameWidth", "targettarget.healthHeight",
    "focustarget.frameWidth", "focustarget.healthHeight",
    "pet.frameWidth", "pet.healthHeight",
    "focus.frameWidth", "focus.healthHeight",
    "boss.frameWidth", "boss.healthHeight",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUICooldownManager", {
    "cdmBarPositions",
    "cdmBars.bars.*.iconSize",
    "cdmBars.bars.*.numRows",
    "cdmBars.bars.*.anchorFirstRow",
    "cdmBars.bars.*.rowGrowDirection",
    "cdmBars.bars.*.spacing",
    "cdmBars.bars.*.verticalOrientation",
    "cdmBars.bars.*.anchorTo",
    "cdmBars.bars.*.anchorPosition",
    "cdmBars.bars.*.anchorOffsetX",
    "cdmBars.bars.*.anchorOffsetY",
    "cdmBars.bars.*.keybindOffsetX",
    "cdmBars.bars.*.keybindOffsetY",
    "cdmBars.bars.*.keybindAnchor",
    -- Rotation Assist Icon: unlock position, size and keybind placement
    "rotationAssistIcon.position",
    "rotationAssistIcon.iconSize",
    "rotationAssistIcon.keybindAnchor",
    "rotationAssistIcon.keybindOffsetX",
    "rotationAssistIcon.keybindOffsetY",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIResourceBars", {
    "health.width", "health.height", "health.offsetX", "health.offsetY", "health.orientation",
    "primary.width", "primary.height", "primary.offsetX", "primary.offsetY", "primary.orientation",
    "secondary.pipWidth", "secondary.pipHeight", "secondary.pipSpacing", "secondary.pipOrientation",
    "secondary.offsetX", "secondary.offsetY",
    "castBar.width", "castBar.height", "castBar.anchorX", "castBar.anchorY", "castBar.unlockPos",
    "totemBar.iconSize", "totemBar.spacing", "totemBar.unlockPos",
    "callTotemBar.iconSize", "callTotemBar.spacing", "callTotemBar.unlockPos",
    "general.anchorX", "general.anchorY", "general.orientation",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIAuraBuffReminders", {
    "unlockPos",
    "display.xOffset", "display.yOffset",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIRaidFrames", {
    "unlockPos",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIMythicTimer", {
    "standalonePos",
    "scale",
    "frameWidth",
})

-- Dragon Riding HUD position (unlockPos) stays per-profile on sync, like every module.
EllesmereUI.RegisterSyncExclusions("EllesmereUIDragonRiding", {
    "unlockPos",
})

-- QoL Secondary Stats/FPS positions and the cursor slice (GCD ring, cast circle, at
-- profile.cursor) stay per-profile on sync: exported intact, never push-overwritten.
EllesmereUI.RegisterSyncExclusions("EllesmereUIQoL", {
    "secondaryStatsPos",
    "fpsPos",
    "cursor.gcd.pos",
    "cursor.castCircle.pos",
})

-- Minimap settings nest under profile.minimap.
EllesmereUI.RegisterSyncExclusions("EllesmereUIMinimap", {
    "minimap.position",      -- unlock-element drag position
    "minimap.btnPositions",  -- per-button shift-drag offsets
})

-- Chat settings nest under profile.chat.
EllesmereUI.RegisterSyncExclusions("EllesmereUIChat", {
    "chat.chatPosition",   -- unlock drag position
    "chat.chatWidth",      -- unlock resize-handle width
    "chat.chatHeight",     -- unlock resize-handle height
    "chat.toastPosition",  -- BNet toast unlock position
    "chat.iconPositions",  -- per-sidebar-icon shift-drag offsets
})

-- Damage Meters settings nest under profile.dm.
EllesmereUI.RegisterSyncExclusions("EllesmereUIDamageMeters", {
    "dm.standaloneTimerPos",  -- drag-written standalone timer position
    "dm.windows.*.position",  -- per-window drag position
    "dm.windows.*.width",     -- per-window drag-resize width
    "dm.windows.*.height",    -- per-window drag-resize height
})

-- DataBars per-bar geometry lives in the top-level bars array (wildcard shape as ActionBars).
EllesmereUI.RegisterSyncExclusions("EllesmereUIDataBars", {
    "bars.*.savedPos",   -- unlock drag position
    "bars.*.length",     -- unlock resize owned
    "bars.*.thickness",  -- unlock resize owned
    "bars.*.snapEdge",   -- mutated by the drag save itself
})

-- Bags is the one auto-synced module: without this the bank position mirrors across profiles.
EllesmereUI.RegisterSyncExclusions("EllesmereUIBags", {
    "bankPosition",  -- bank window shift-drag position
})

-------------------------------------------------------------------------------
--  Sync Popup -- anchored flush to sidebar's right edge, centered on clicked sync icon,
--  clamped to the EUI window bottom.
-------------------------------------------------------------------------------
do
    local _syncPopup = nil

    function EllesmereUI.CloseSyncPopup()
        if _syncPopup then _syncPopup:Hide() end
        if EllesmereUI._syncConfirmFrame then EllesmereUI._syncConfirmFrame:Hide() end
    end

    -- Seed-picker confirm for create/update: user picks which member's settings the
    -- group starts from; after that first equalization the group is a mirror.
    function EllesmereUI._ShowSyncSeedConfirm(opts)
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local PP = EllesmereUI.PanelPP or EllesmereUI.PP
        local W, PAD = 360, 18

        if not EllesmereUI._syncConfirmFrame then
            -- Controller cursor: screen-level overlays hang off the overlay
            -- parent, which is UIParent unless a controller cursor is loaded.
            local overlayParent = EllesmereUI.OverlayParent()
            local nf = CreateFrame("Frame", nil, overlayParent)
            nf:SetFrameStrata("FULLSCREEN_DIALOG")
            -- Below 200: the shared dropdown menu (hardcoded level 200) must render above
            nf:SetFrameLevel(150)
            nf:EnableMouse(true)
            local bg = nf:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(15/255, 17/255, 22/255, 1)
            nf._bg = bg
            -- Fullscreen dimmer: darkens and click-blocks everything behind
            local dim = CreateFrame("Frame", nil, overlayParent)
            dim:SetFrameStrata("FULLSCREEN_DIALOG")
            dim:SetFrameLevel(140)
            dim:SetAllPoints(UIParent)
            dim:EnableMouse(true)
            dim:Hide()
            local dimTex = dim:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.55)
            nf._dimmer = dim
            nf:SetScript("OnHide", function(self) self._dimmer:Hide() end)
            EllesmereUI._syncConfirmFrame = nf
            -- Controller cursor: the dimmer and the panel block what is under
            -- them without being stops.
            EllesmereUI.TrackOverlay(nf)
            EllesmereUI.TrackOverlay(dim)
            EllesmereUI.PadHint(nf, "nodepass")
            EllesmereUI.PadHint(dim, "nodepass")
        end
        local f = EllesmereUI._syncConfirmFrame

        -- Clean old children/regions (recycled frame)
        for _, c in ipairs({f:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({f:GetRegions()}) do
            if r ~= f._bg then r:Hide(); r:SetParent(nil) end
        end

        local function MakeFont(parent, size, r, g, b, a)
            local fs = parent:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
            fs:SetFont(fontPath, size, "")
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        if PP then EllesmereUI.MakeBorder(f, 1, 1, 1, 0.15, PP) end
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

        local cy = -PAD

        local title = MakeFont(f, 14, 1, 1, 1, 0.9)
        title:SetPoint("TOP", f, "TOP", 0, cy)
        title:SetText(EllesmereUI.L(opts.hadGroup and "Update Sync Group" or "Create Sync Group"))
        cy = cy - 22 - 8

        local msg = MakeFont(f, 11, 1, 1, 1, 0.6)
        msg:SetPoint("TOP", f, "TOP", 0, cy)
        msg:SetWidth(W - PAD * 2)
        msg:SetJustifyH("CENTER")
        msg:SetText(EllesmereUI.Lf("All selected profiles will keep their %1$s settings in sync: changes made on any of them carry over to the others. Choose which profile's settings the group starts from.", EllesmereUI.L(opts.displayName)))
        cy = cy - (msg:GetStringHeight() or 42) - 14

        local ddLabel = MakeFont(f, 11, 1, 1, 1, 0.5)
        ddLabel:SetPoint("TOP", f, "TOP", 0, cy)
        ddLabel:SetText(EllesmereUI.L("Sync settings from:"))
        cy = cy - 16 - 6

        local seedChoice = opts.defaultSeed
        local ddValues = { _noLoc = true }  -- profile names: never translate
        for _, name in ipairs(opts.memberOrder) do ddValues[name] = name end
        local DD_W = 190
        local DD_SCALE = 0.85
        local ddVisW = math.floor(DD_W * DD_SCALE + 0.5)
        local ddVisH = math.floor(30 * DD_SCALE + 0.5)
        local ddHolder = CreateFrame("Frame", nil, f)
        ddHolder:SetSize(ddVisW, ddVisH)
        ddHolder:SetPoint("TOP", f, "TOP", 0, cy)
        ddHolder:SetFrameLevel(f:GetFrameLevel() + 1)
        local ddBtn = EllesmereUI.BuildDropdownControl(ddHolder, DD_W, ddHolder:GetFrameLevel() + 1,
            ddValues, opts.memberOrder,
            function() return seedChoice end,
            function(v) seedChoice = v end)
        ddBtn:SetScale(DD_SCALE)
        ddBtn:SetPoint("TOPLEFT", ddHolder, "TOPLEFT", 0, 0)
        -- Menu is created lazily at UIParent scale; match it to the scaled button once it exists
        ddBtn:HookScript("OnClick", function(self)
            if self._ddMenu and self._ddMenu:GetScale() ~= DD_SCALE then
                self._ddMenu:SetScale(DD_SCALE)
            end
        end)
        cy = cy - ddVisH - 14

        if opts.hasWarning then
            local warn = MakeFont(f, 10, 0.92, 0.3, 0.3, 1)
            warn:SetPoint("TOP", f, "TOP", 0, cy)
            warn:SetWidth(W - PAD * 2)
            warn:SetJustifyH("CENTER")
            warn:SetText(EllesmereUI.L("Position and size settings are not synced and keep each profile's own values."))
            cy = cy - (warn:GetStringHeight() or 26) - 14
        end

        local function MakeBtn(label, r, g, b, a, hr, hg, hb)
            local btn = CreateFrame("Button", nil, f)
            btn:SetSize(120, 26)
            btn:SetFrameLevel(f:GetFrameLevel() + 1)
            local bgT = btn:CreateTexture(nil, "BACKGROUND")
            bgT:SetAllPoints(); bgT:SetColorTexture(r, g, b, a)
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, false) end
            lbl:SetFont(fontPath, 10, "")
            lbl:SetTextColor(1, 1, 1, 1); lbl:SetPoint("CENTER"); lbl:SetText(label)
            btn:SetScript("OnEnter", function() bgT:SetColorTexture(hr, hg, hb, 1) end)
            btn:SetScript("OnLeave", function() bgT:SetColorTexture(r, g, b, a) end)
            return btn
        end

        local cancelBtn = MakeBtn(EllesmereUI.L("Cancel"), 0.18, 0.19, 0.22, 0.9, 0.25, 0.26, 0.3)
        cancelBtn:SetPoint("TOPRIGHT", f, "TOP", -6, cy)
        local confirmBtn = MakeBtn(EllesmereUI.L("Sync"), 0.05, 0.52, 0.39, 0.8, 0.07, 0.62, 0.49)
        confirmBtn:SetPoint("TOPLEFT", f, "TOP", 6, cy)
        cy = cy - 26

        f:SetSize(W, -cy + PAD)

        confirmBtn:SetScript("OnClick", function()
            f:Hide()
            if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
            EllesmereUIDB.syncedModules[opts.folder] = opts.targets
            if seedChoice then
                EllesmereUI.SyncModuleFromProfile(opts.folder, seedChoice, opts.targets)
            end
            if opts.onDone then opts.onDone() end
        end)
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
            if opts.onCancel then opts.onCancel() end
        end)
        -- Controller cursor: its cancel press backs out through Cancel.
        if EllesmereUI.PadCP() then f.CloseButton = cancelBtn end

        f._dimmer:Show()
        f:Show()
        -- Controller cursor: start on the safe button.
        EllesmereUI.PadFocus(cancelBtn)
    end

    function EllesmereUI.OpenSyncPopup(folder, displayName, anchorBtn)
        if EllesmereUI._syncConfirmFrame then EllesmereUI._syncConfirmFrame:Hide() end
        -- Toggle off if already open for this module
        if _syncPopup and _syncPopup:IsShown() and _syncPopup._folder == folder then
            _syncPopup:Hide()
            return
        end

        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        local profileOrder = EllesmereUIDB.profileOrder or {}

        -- Full profile list, profileOrder first then stragglers (active included: groups are explicit membership)
        local allProfiles = {}
        for _, name in ipairs(profileOrder) do
            if EllesmereUIDB.profiles[name] then
                allProfiles[#allProfiles + 1] = name
            end
        end
        for name in pairs(EllesmereUIDB.profiles) do
            local found = false
            for _, n in ipairs(allProfiles) do if n == name then found = true; break end end
            if not found then allProfiles[#allProfiles + 1] = name end
        end

        if #allProfiles <= 1 then
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(anchorBtn, "No other profiles to sync to")
                C_Timer.After(1.5, function() EllesmereUI.HideWidgetTooltip() end)
            end
            return
        end

        local MEDIA_PATH = "Interface\\AddOns\\EllesmereUI\\media\\"
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local accentColor = EllesmereUI.ACCENT_COLOR or EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local PP = EllesmereUI.PanelPP or EllesmereUI.PP

        local POPUP_W = 300
        local PAD = 16
        local ROW_H = 30
        local ROW_GAP = 2
        local HEADER_H = 26
        local WARN_MODULES = {
            EllesmereUIActionBars = true,
            EllesmereUIUnitFrames = true,
            EllesmereUICooldownManager = true,
            EllesmereUIResourceBars = true,
            EllesmereUIMythicTimer = true,
            EllesmereUIRaidFrames = true,
        }
        local hasWarning = WARN_MODULES[folder]
        local SUBTITLE_H = 30
        local popupH = PAD + HEADER_H + 7 + SUBTITLE_H + 14
            + #allProfiles * (ROW_H + ROW_GAP) - ROW_GAP + 16 + 30 + PAD

        if not _syncPopup then
            -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
            _syncPopup = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
            _syncPopup:SetFrameStrata("FULLSCREEN_DIALOG")
            _syncPopup:SetFrameLevel(200)
            _syncPopup:EnableMouse(true)
            local bg = _syncPopup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(15/255, 17/255, 22/255, 1)
            _syncPopup._bg = bg
            -- Born hidden, so the Show below runs its OnShow (the click-away)
            -- on the first open too.
            _syncPopup:Hide()
            EllesmereUI.TrackOverlay(_syncPopup)
            EllesmereUI.PadHint(_syncPopup, "nodepass")
        end
        local popup = _syncPopup
        popup._folder = folder
        popup:SetFrameLevel(200)

        -- Clean old children
        for _, c in ipairs({popup:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({popup:GetRegions()}) do
            if r ~= popup._bg then r:Hide(); r:SetParent(nil) end
        end

        popup:SetSize(POPUP_W, popupH)
        if PP then
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)
        end

        -- Position: flush right of sidebar, centered on the sync icon, clamped
        local sidebar = EllesmereUI._sidebar
        local root = EllesmereUI._mainFrame
        if sidebar and anchorBtn then
            local btnMidY = select(2, anchorBtn:GetCenter()) or 0
            local sidebarMidY = select(2, sidebar:GetCenter()) or 0
            local offsetY = btnMidY - sidebarMidY
            -- Clamp to EUI window bottom
            if root then
                local rootBot = root:GetBottom() or 0
                local popupBot = btnMidY - popupH / 2
                if popupBot < rootBot then offsetY = offsetY + (rootBot - popupBot) end
            end
            popup:ClearAllPoints()
            popup:SetPoint("LEFT", sidebar, "RIGHT", 0, offsetY)
        else
            popup:ClearAllPoints()
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end

        local function MakeFont(parent, size, r, g, b, a)
            local fs = parent:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
            fs:SetFont(fontPath, size, "")
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        local cy = -PAD

        -- Header: sync icon (left), title (centered), close X (right)
        local iconTex = popup:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(19, 19)
        iconTex:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD - 1, cy + 1)
        iconTex:SetTexture(MEDIA_PATH .. "icons\\linked.png")
        -- Accent when this module has an active sync group, gray otherwise
        if EllesmereUI.IsModuleSynced(folder) then
            iconTex:SetVertexColor(accentColor.r, accentColor.g, accentColor.b, 1)
        else
            iconTex:SetVertexColor(0.55, 0.55, 0.55, 1)
        end

        local title = MakeFont(popup, 14, 1, 1, 1, 0.9)
        title:SetPoint("TOP", popup, "TOP", 0, cy - 1)
        title:SetText(EllesmereUI.Lf("%1$s Sync", EllesmereUI.L(displayName)))
        cy = cy - HEADER_H - 7

        local subtitle = MakeFont(popup, 10, 1, 1, 1, 0.45)
        subtitle:SetPoint("TOP", popup, "TOP", 0, cy)
        subtitle:SetWidth(POPUP_W - PAD * 2)
        subtitle:SetJustifyH("CENTER")
        subtitle:SetText(EllesmereUI.L("Syncing allows you to auto update all profiles whenever you change settings. This can be enabled per module."))
        cy = cy - SUBTITLE_H - 14

        -- Toggle rows for every profile (the active one included)
        local currentSynced = EllesmereUI.GetSyncedProfiles(folder)
        local toggleState = {}
        local hadGroup = next(currentSynced) ~= nil
        local refreshSyncBtnLabel  -- defined with the button below

        local accentHex = string.format("%02x%02x%02x",
            math.floor(accentColor.r * 255 + 0.5),
            math.floor(accentColor.g * 255 + 0.5),
            math.floor(accentColor.b * 255 + 0.5))

        local BuildToggleControl = EllesmereUI.BuildToggleControl
        for _, profName in ipairs(allProfiles) do
            -- Card-style row: label left, toggle right, whole row clickable
            local row = CreateFrame("Button", nil, popup)
            row:SetSize(POPUP_W - PAD * 2, ROW_H)
            row:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, cy)
            row:SetFrameLevel(popup:GetFrameLevel() + 1)
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(1, 1, 1, 0.05)

            local isSynced = currentSynced[profName] == true
            toggleState[profName] = isSynced

            local tg, _, tgSnap = BuildToggleControl(row, row:GetFrameLevel() + 1,
                function() return toggleState[profName] end,
                function(v)
                    toggleState[profName] = v
                    if refreshSyncBtnLabel then refreshSyncBtnLabel() end
                end,
                { sizeRatio = 0.75 })
            tg:SetPoint("RIGHT", row, "RIGHT", -10, 0)

            row:SetScript("OnClick", function()
                toggleState[profName] = not toggleState[profName]
                tgSnap(toggleState[profName])
                if refreshSyncBtnLabel then refreshSyncBtnLabel() end
            end)
            row:SetScript("OnEnter", function() rowBg:SetColorTexture(1, 1, 1, 0.08) end)
            row:SetScript("OnLeave", function() rowBg:SetColorTexture(1, 1, 1, 0.05) end)
            -- Toggle hover fires the row's OnLeave (child frame); keep the card lit
            tg:HookScript("OnEnter", function() rowBg:SetColorTexture(1, 1, 1, 0.08) end)
            tg:HookScript("OnLeave", function() rowBg:SetColorTexture(1, 1, 1, 0.05) end)

            local lblText = MakeFont(row, 12, 1, 1, 1, 0.85)
            lblText:SetPoint("LEFT", row, "LEFT", 10, 0)
            if profName == active then
                lblText:SetText(profName .. " |cff" .. accentHex .. "(active)|r")
            else
                lblText:SetText(profName)
            end

            cy = cy - ROW_H - ROW_GAP
        end

        cy = cy - (16 - ROW_GAP)

        -- Action button: full-width accent outline; label tracks the toggle state
        local syncBtn = CreateFrame("Button", nil, popup)
        syncBtn:SetSize(POPUP_W - PAD * 2, 30)
        syncBtn:SetPoint("TOP", popup, "TOP", 0, cy)
        syncBtn:SetFrameLevel(popup:GetFrameLevel() + 1)
        local sBg = syncBtn:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        local sBrd
        if PP then
            sBrd = EllesmereUI.MakeBorder(syncBtn, accentColor.r, accentColor.g, accentColor.b, 0.7, PP)
        end
        local sLbl = syncBtn:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(sLbl, false) end
        sLbl:SetFont(fontPath, 11, "")
        sLbl:SetPoint("CENTER")

        -- Grayed out until the toggles actually differ from the saved group
        local function ApplyBtnState(dirty)
            syncBtn._dirty = dirty
            if dirty then
                sBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.08)
                if sBrd then sBrd:SetColor(accentColor.r, accentColor.g, accentColor.b, 0.7) end
                sLbl:SetTextColor(accentColor.r, accentColor.g, accentColor.b, 1)
            else
                sBg:SetColorTexture(1, 1, 1, 0.03)
                if sBrd then sBrd:SetColor(1, 1, 1, 0.15) end
                sLbl:SetTextColor(1, 1, 1, 0.35)
            end
        end
        syncBtn:SetScript("OnEnter", function()
            if not syncBtn._dirty then return end
            sBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.18)
        end)
        syncBtn:SetScript("OnLeave", function()
            ApplyBtnState(syncBtn._dirty)
        end)

        refreshSyncBtnLabel = function()
            local count = 0
            local dirty = false
            for profName, v in pairs(toggleState) do
                if v then count = count + 1 end
                if v ~= (currentSynced[profName] == true) then dirty = true end
            end
            if hadGroup and count == 0 then
                sLbl:SetText(EllesmereUI.L("Disband Sync Group"))
            elseif hadGroup then
                sLbl:SetText(EllesmereUI.L("Update Sync Group"))
            else
                sLbl:SetText(EllesmereUI.L("Create Sync Group"))
            end
            ApplyBtnState(dirty)
        end
        refreshSyncBtnLabel()

        local function RefreshSidebarSyncIcon()
            local sidebarBtns = EUI_NS.sidebarButtons
            if sidebarBtns and sidebarBtns[folder] and sidebarBtns[folder]._syncBtn then
                local sb = sidebarBtns[folder]._syncBtn
                if sb._refreshAlpha then sb._refreshAlpha() end
            end
        end

        syncBtn:SetScript("OnClick", function()
            if not syncBtn._dirty then return end
            -- The group is exactly the toggled-on profiles
            local targets = {}
            local count = 0
            local anyNew = false
            for profName, checked in pairs(toggleState) do
                if checked then
                    targets[profName] = true
                    count = count + 1
                    if not currentSynced[profName] then anyNew = true end
                end
            end

            if count == 0 then
                -- Disband (or nothing was ever configured)
                if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
                EllesmereUIDB.syncedModules[folder] = {}
                popup:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            if count == 1 then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(syncBtn, "A sync group needs at least two profiles")
                    C_Timer.After(1.5, function() EllesmereUI.HideWidgetTooltip() end)
                end
                return
            end

            if not anyNew then
                -- Pure removal / no change: nothing overwritten, save without confirmation
                if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
                EllesmereUIDB.syncedModules[folder] = targets
                popup:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            -- New members joining: confirm with a seed picker; default = an existing member
            -- on update (newcomers adopt group settings), active on create.
            local memberOrder = {}
            for _, name in ipairs(allProfiles) do
                if targets[name] then memberOrder[#memberOrder + 1] = name end
            end
            local defaultSeed
            if hadGroup then
                for _, name in ipairs(memberOrder) do
                    if currentSynced[name] then defaultSeed = name; break end
                end
            end
            if not defaultSeed then
                defaultSeed = targets[active] and active or memberOrder[1]
            end

            popup:SetFrameLevel(90)
            popup:SetScript("OnUpdate", nil)
            EllesmereUI._ShowSyncSeedConfirm({
                folder = folder,
                displayName = displayName,
                targets = targets,
                memberOrder = memberOrder,
                defaultSeed = defaultSeed,
                hadGroup = hadGroup,
                hasWarning = hasWarning,
                active = active,
                onDone = function()
                    popup:Hide()
                    RefreshSidebarSyncIcon()
                end,
                onCancel = function()
                    popup:Hide()
                end,
            })
        end)

        -- Click-off to close (OnUpdate poll like CC popups)
        popup:SetScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(self2)
                if IsMouseButtonDown("LeftButton") then
                    if not self2:IsMouseOver() and not (anchorBtn and anchorBtn:IsMouseOver()) then
                        self2:Hide()
                    end
                end
            end)
        end)
        popup:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        -- Controller cursor: its cancel press clicks the sync icon, which
        -- toggles this popup off.
        if EllesmereUI.PadCP() then popup.CloseButton = anchorBtn end
        popup:Show()
        -- Controller cursor: move it into the popup (its first row).
        EllesmereUI.PadFocus(popup)
    end
end
