if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Preview.lua
--
--  Options preview for the raid and party frames: fake members, the preview
--  aura ticker, the real-frame overlay and the size preview. Loads right
--  after the main file and reads it through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local max          = math.max
local abs          = math.abs
local pairs        = pairs
local ipairs       = ipairs
local wipe         = wipe
local type         = type
local tostring     = tostring
local tinsert      = table.insert
local UnitName              = UnitName
local UnitClass             = UnitClass
local InCombatLockdown      = InCombatLockdown
local C_Timer               = C_Timer
local CreateFrame           = CreateFrame

local PixelSnap, UpdateVisibility = ns.PixelSnap, ns.UpdateVisibility
local I = ns._internals
local ApplyFont, ApplyRoleIcon, DISPEL_ICON_ATLAS = I.ApplyFont, I.ApplyRoleIcon, I.DISPEL_ICON_ATLAS
local GetDispelColor, IsPowerBarEnabled, LayoutGroups = I.GetDispelColor, I.IsPowerBarEnabled, I.LayoutGroups
local LayoutTopNameBar, MOVER_GROUPS, ResolveHealthTexture = I.LayoutTopNameBar, I.MOVER_GROUPS, I.ResolveHealthTexture
local defaults = I.defaults

-- Main-file locals assigned after load; the main file re-binds them on
-- every write (CreateHeaders, OnInitialize, OnEnable).
local db, PP, containerFrame
function ns._PreviewBind(d, p, c) db, PP, containerFrame = d, p, c end

-------------------------------------------------------------------------------
--  Options preview (fake raid members when options panel is open)
--  Shows 20 buttons with randomized class colors and names so the user
--  can see their settings applied without needing a real group.
-------------------------------------------------------------------------------
local previewActive = false
ns._PV_CLASS_TOKENS = EllesmereUI.CLASS_TOKEN_ORDER
ns._PV_TANK_CLASSES   = { "WARRIOR", "PALADIN", "DEATHKNIGHT", "MONK", "DRUID", "DEMONHUNTER" }
ns._PV_HEALER_CLASSES = { "PRIEST", "PALADIN", "SHAMAN", "MONK", "DRUID", "EVOKER" }
ns._PV_DPS_CLASSES    = ns._PV_CLASS_TOKENS
ns._PV_EXT_ICONS = {
    572025, 135936, 237542, 627485, 135964, 135966, 4622478,
}
ns._PV_DEF_ICONS = {
    DEATHKNIGHT = { 237525, 136120 }, DEMONHUNTER = { 1305150, 463284 },
    DRUID = { 136097, 236169 }, EVOKER = { 1394891 },
    HUNTER = { 132199, 136094 }, MAGE = { 135841, 609811 },
    MONK = { 615341, 620827 }, PALADIN = { 524353, 524354 },
    PRIEST = { 237550, 237563 }, ROGUE = { 136177, 132294 },
    SHAMAN = { 538565 }, WARLOCK = { 136146, 136150 }, WARRIOR = { 132336, 132361 },
}
ns._PV_NAMES = {
    "Thaldrin", "Kaelara", "Morgath", "Sylvaris", "Drakmoor",
    "Elyndra", "Bronthar", "Velisara", "Grimjaw", "Luneth",
    "Ashvane", "Tormund", "Ravynne", "Zulkhar", "Brightwing",
    "Fenwick", "Dawnforge", "Nighthollow", "Stormhelm", "Embertide",
}
-- EUI LEGENDS event roster (PERMANENT): the event winners + team members who
-- earned a spot on the raid preview, with class-balancing filler names.
-- Preview slot 1 is always the player; entries 1-19 fill slots 2-20. Name,
-- class and role travel together through the role sort (ns._pvNames).
ns._PV_ROSTER = {
    { name = "Xeno",          class = "MONK",        role = "TANK" },
    { name = "Grimjaw",       class = "WARRIOR",     role = "TANK" },
    { name = "Stickymittens", class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Toxik",         class = "MONK",        role = "HEALER" },
    { name = "Delasteve",     class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Burne",         class = "DRUID",       role = "HEALER" },
    { name = "Lily",          class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Kulia",         class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Thiaspriest",   class = "PRIEST",      role = "DAMAGER" },
    { name = "Pelleas",       class = "SHAMAN",      role = "DAMAGER" },
    { name = "Khardi",        class = "HUNTER",      role = "DAMAGER" },
    { name = "Morgath",       class = "DEATHKNIGHT", role = "DAMAGER" },
    { name = "Drakmoor",      class = "DEMONHUNTER", role = "DAMAGER" },
    { name = "Embertide",     class = "EVOKER",      role = "DAMAGER" },
    { name = "Elyndra",       class = "MAGE",        role = "DAMAGER" },
    { name = "Fenwick",       class = "ROGUE",       role = "DAMAGER" },
    { name = "Zulkhar",       class = "WARLOCK",     role = "DAMAGER" },
    { name = "Luneth",        class = "DRUID",       role = "DAMAGER" },
    { name = "Stormhelm",     class = "SHAMAN",      role = "DAMAGER" },
}
ns._PV_DISPEL_DB_ICONS = {
    Magic = 135735, Curse = 132291, Disease = 237535, Poison = 132106, [""] = 4547635,
}
ns._PV_DEBUFF_ICONS = { 135813, 136139, 132090, 136197, 135849, 136188 }
ns._pvActiveAuras = {}

-- Forward declarations for preview aura cycling (actual tables defined later)
local previewFrames
local previewClassTokens

-------------------------------------------------------------------------------
--  Preview aura cycling system
--  Manages fake debuffs/defensives on preview frames with real durations.
--  Maintains at least 1 per group for each enabled category.
-------------------------------------------------------------------------------
local pvAuraTicker = nil

-- Active-preview resolvers: the shared aura/animation tickers serve BOTH the
-- raid preview (previewFrames / previewActive) and the party preview
-- (ns._partyPvFrames / ns._partyPvActive). Keying off ns._partyPvActive at call
-- time lets one code path drive whichever preview is currently on screen.
local function PvFrames()
    return (ns._partyPvActive and ns._partyPvFrames) or previewFrames
end
local function PvActive()
    return previewActive or ns._partyPvActive
end
-- Party preview reads party-scaled / party-prefixed settings so aura icons match
-- the party frames (size, position, colors); raid preview reads the live profile
-- through the real-preview effective overlay (below) so an open panel's view
-- swap never leaks into the preview.
local function PvSettings()
    return (ns._partyPvActive and ns._scaledPartyProxy)
        or ns._pvOverlayProxy or db.profile
end
-- Class tokens for icon selection: the async ticker runs outside the synchronous
-- table swap in ApplyPartyPreviewData, so it must resolve party tokens itself.
local function PvClassTokens()
    return (ns._partyPvActive and ns._partyPvCT) or previewClassTokens
end

-------------------------------------------------------------------------------
--  Real-preview effective-value overlay: while the options panel holds a
--  value-swapped VIEW (Default Editing Mode or an editing-as session) and
--  preview mode is "real", preview reads must resolve the CURRENT SPEC's
--  panel-closed effective values (spec override, else applied conditional,
--  else defaults) -- never the view's swapped live values. The overlay is a
--  read-through proxy: captured RF keys resolve from the override stores,
--  everything else falls through to live db.profile, so options widgets
--  (which read live directly) keep showing the view. Rebuilt event-driven at
--  preview refresh entry points and the module-refresh tail; nil when no view
--  swap is active (byte-identical reads outside editing views). ZERO writes to
--  live/override stores. (ns fields + do-end locals only: 200-local cap.)
-------------------------------------------------------------------------------
do
    local proxy
    local proxyMT = {
        __index = function(_, key)
            local ov = ns._pvOverlay
            if ov ~= nil then
                local v = ov[key]
                if v ~= nil then
                    if v == EllesmereUI.SPECOV_NIL then return nil end
                    return v
                end
            end
            return db.profile[key]
        end,
    }
    -- Segment-key resolution mirrors the value system's live walk: prefer
    -- the string key when the table holds it, else numeric.
    local function SegKey(t, seg)
        if t[seg] ~= nil then return seg end
        local n = tonumber(seg)
        if n ~= nil and t[n] ~= nil then return n end
        return seg
    end

    function ns._RebuildPvOverlay()
        local active = (db.profile.previewMode == "real")
            and EllesmereUI.SpecOverrides_ViewActive()
            and EllesmereUI.SpecOverrides_PeekEffectiveValues
        local flat, specSrc, condSrc
        if active then
            flat, specSrc, condSrc =
                EllesmereUI.SpecOverrides_PeekEffectiveValues("EllesmereUIRaidFrames")
        end
        if not flat then
            ns._pvOverlay = nil
            ns._pvOverlayProxy = nil
            if ns._RefreshProxyModes then ns._RefreshProxyModes() end
            ns._pvOverlaySrc = nil
            if ns._UpdatePvModeChrome then ns._UpdatePvModeChrome() end
            return
        end
        local NIL_SENT = EllesmereUI.SPECOV_NIL
        local overlay = {}
        for fkey, v in pairs(flat) do
            local path = fkey:match("^[^\31]+\31(.*)$")
            if path and path ~= "" then
                local segs = { strsplit("\30", path) }
                if #segs == 1 then
                    -- Depth-1: NIL_SENT stays encoded; the proxy decodes it.
                    overlay[SegKey(db.profile, segs[1])] = v
                else
                    -- Deeper path: shallow-clone the LIVE parent chain along
                    -- the path once, then set (or remove) the leaf -- sibling
                    -- keys inside the cloned subtable keep their live values.
                    local liveT = db.profile
                    local dstParent = overlay
                    local ok = true
                    for i = 1, #segs - 1 do
                        local k = SegKey(liveT, segs[i])
                        local liveChild = liveT[k]
                        if type(liveChild) ~= "table" then ok = false; break end
                        local dstChild = dstParent[k]
                        -- A shallow parent copy still shares its live children.
                        -- Detach each shared child before writing preview values.
                        if type(dstChild) ~= "table" or dstChild == liveChild then
                            dstChild = {}
                            for ck, cv in pairs(liveChild) do dstChild[ck] = cv end
                            dstParent[k] = dstChild
                        end
                        dstParent = dstChild
                        liveT = liveChild
                    end
                    if ok then
                        local lk = SegKey(liveT, segs[#segs])
                        if v == NIL_SENT then
                            dstParent[lk] = nil
                        else
                            dstParent[lk] = v
                        end
                    end
                end
            end
        end
        ns._pvOverlay = overlay
        if not proxy then proxy = setmetatable({}, proxyMT) end
        ns._pvOverlayProxy = proxy
        if ns._RefreshProxyModes then ns._RefreshProxyModes() end
        ns._pvOverlaySrc = { spec = specSrc, cond = condSrc }
        if ns._UpdatePvModeChrome then ns._UpdatePvModeChrome() end
    end

    -- The preview-path settings accessor: overlay proxy while a view swap
    -- is active in real preview mode, else the live profile itself.
    function ns.PvEffectiveProfile()
        return ns._pvOverlayProxy or db.profile
    end

    -- Session unlock-layer element lookup: while an override session with a
    -- CUSTOM unlock mode is being edited in real preview mode, the preview
    -- mirrors that session's unlock positions -- the layer's recorded elem
    -- for the key, baseline fallback per element. nil in every other state
    -- (live positioning, today's behavior). Anchored containers resolve to
    -- their recorded bookkeeping coordinates, not a live anchor chain.
    function ns._PvSessionElem(key)
        if db.profile.previewMode ~= "real" then return nil end
        local layer, base
        local sfn = EllesmereUI.SpecOverrides_EditSessionUnlockLayer
        if sfn then layer, base = sfn() end
        if not layer then
            -- Default view: mirror the REAL spec's RESOLVED effective fork. Never the
            -- live pointer (s.active) -- it lags membership and unlock-mode edits made
            -- while the panel is open, and the preview must show the layer that WOULD
            -- apply on exit. Baseline-effective specs return nil here -> live
            -- positioning, byte-identical to before the feature.
            local vfn = EllesmereUI.SpecOverrides_ViewActive
            if vfn and vfn() and EllesmereUI.SpecOverrides_EffectiveUnlockLayer then
                layer, base = EllesmereUI.SpecOverrides_EffectiveUnlockLayer()
            end
        end
        if not layer then return nil end
        local e = layer.elems and layer.elems[key]
        if not e and base and base ~= layer then
            e = base.elems and base.elems[key]
        end
        return e
    end
end

local function PvAuraGetGroup(index)
    return math.ceil(index / 5)
end

-- Pick a random icon for the given type and frame index
local function PvAuraPickIcon(auraType, frameIndex)
    if auraType == "def" then
        local s2 = PvSettings()
        local showDef = s2 and s2.showDefensives
        local showExt = s2 and s2.showExternals
        local pool = {}
        local ct = PvClassTokens()[frameIndex] or "WARRIOR"
        if showDef then
            local ci = ns._PV_DEF_ICONS[ct]
            if ci then for _, ic in ipairs(ci) do pool[#pool + 1] = ic end end
        end
        if showExt then
            for _, ic in ipairs(ns._PV_EXT_ICONS) do pool[#pool + 1] = ic end
        end
        if #pool == 0 then return nil end
        return pool[math.random(#pool)]
    else
        return ns._PV_DEBUFF_ICONS[math.random(#ns._PV_DEBUFF_ICONS)]
    end
end

-- Position a preview aura icon on a frame (reuses anchor logic)
local function PvAuraAnchor(icon, f, auraType, slot, totalShown)
    local s2 = PvSettings()

    -- Debuffs use the shared grid layout (same DebuffGridPoint helper as the live
    -- frames) so the preview matches exactly -- including row wrapping and CENTER
    -- per-row centering. `slot` is the 0-based index among visible icons.
    if auraType ~= "def" then
        local sz = ns.RFC_DebuffSize(s2)
        icon:SetSize(sz, sz)
        icon:ClearAllPoints()
        local corner, fx, fy = ns.DebuffGridPoint(s2, slot, totalShown)
        icon:SetPoint(corner, ns.RF_AnchorHost(f._health, s2), corner, fx, fy)
        return
    end

    -- Defensives: single-line relative chaining (no wrapping).
    local pos, ox, oy, grow, sz, spc
    pos = s2.defPosition or "center"
    ox = s2.defOffsetX or 0
    oy = s2.defOffsetY or 0
    grow = s2.defGrowDirection or "CENTER"
    sz = s2.defSize or 22
    spc = PixelSnap(s2.defSpacing or 1)
    local spacing = sz + spc
    local centerOff = 0
    if grow == "CENTER" and totalShown > 0 then
        centerOff = -((totalShown - 1) * spacing) / 2
    end
    icon:SetSize(sz, sz)
    icon:ClearAllPoints()
    if slot == 0 then
        local fx = ox + (grow == "CENTER" and centerOff or 0)
        -- All aura icon previews (debuffs, defensives) anchor flush
        -- to the health bar edge -- no 1px inset -- matching the real frames.
        local pvHost = ns.RF_AnchorHost(f._health, s2)
        if pos == "topleft" then icon:SetPoint("TOPLEFT", pvHost, "TOPLEFT", fx, oy)
        elseif pos == "top" then icon:SetPoint("TOP", pvHost, "TOP", fx, oy)
        elseif pos == "topright" then icon:SetPoint("TOPRIGHT", pvHost, "TOPRIGHT", fx, oy)
        elseif pos == "left" then icon:SetPoint("LEFT", pvHost, "LEFT", fx, oy)
        elseif pos == "center" then icon:SetPoint("CENTER", pvHost, "CENTER", fx, oy)
        elseif pos == "right" then icon:SetPoint("RIGHT", pvHost, "RIGHT", fx, oy)
        elseif pos == "bottomright" then icon:SetPoint("BOTTOMRIGHT", pvHost, "BOTTOMRIGHT", fx, oy)
        elseif pos == "bottom" then icon:SetPoint("BOTTOM", pvHost, "BOTTOM", fx, oy)
        else icon:SetPoint("BOTTOMLEFT", pvHost, "BOTTOMLEFT", fx, oy)
        end
    else
        -- Chain from previous icon in same pool
        local pool = f._pvDefs
        local prev = pool[slot] -- slot is 0-based; current is slot+1, prev is pool[slot]
        if prev and prev:IsShown() then
            if grow == "RIGHT" or grow == "CENTER" then
                icon:SetPoint("LEFT", prev, "RIGHT", spc, 0)
            elseif grow == "LEFT" then
                icon:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
            elseif grow == "UP" then
                icon:SetPoint("BOTTOM", prev, "TOP", 0, spc)
            elseif grow == "DOWN" then
                icon:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
            end
        end
    end
end

-- Apply a fake aura to a preview frame slot
local function PvAuraApply(frameIndex, auraType, slotIndex)
    local f = PvFrames()[frameIndex]
    if not f or not f._health then return end
    local pool = auraType == "def" and f._pvDefs
        or f._pvDebuffs
    local icon = pool and pool[slotIndex]
    if not icon then return end

    local tex = PvAuraPickIcon(auraType, frameIndex)
    if not tex then icon:Hide(); return end

    local s2 = PvSettings()
    local dur = 8 + math.random() * 4  -- 8-12 seconds
    local startTime = GetTime()

    icon._tex:SetTexture(tex)
    if auraType == "db" then
        local _z = s2.debuffIconZoom or 0.08
        icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    elseif auraType == "def" then
        local _z = s2.defIconZoom or 0.08
        icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    end
    if icon._cooldown then
        local showSwipe, showDurText, dtColor, dtSize, dtOX, dtOY
        if auraType == "db" then
            showSwipe = s2.debuffShowSwipe ~= false
            showDurText = s2.debuffShowDurText
            dtColor = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
            dtSize = s2.debuffDurTextSize or 8
            dtOX = s2.debuffDurTextOffsetX or 0
            dtOY = s2.debuffDurTextOffsetY or 0
        else
            showSwipe = s2.defShowSwipe ~= false
            showDurText = s2.defShowDurText
            dtColor = s2.defDurTextColor or { r = 1, g = 1, b = 1 }
            dtSize = s2.defDurTextSize or 8
            dtOX = s2.defDurTextOffsetX or 0
            dtOY = s2.defDurTextOffsetY or 0
        end
        icon._cooldown:SetCooldown(startTime, dur)
        icon._cooldown:SetDrawSwipe(showSwipe)
        icon._cooldown:SetHideCountdownNumbers(not showDurText)
        icon._cooldown:Show()

        -- Style the built-in countdown text via GetCountdownFontString
        if showDurText and dtColor then
            local cdText = icon._cooldown.GetCountdownFontString and icon._cooldown:GetCountdownFontString()
            if cdText then
                local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                EllesmereUI.ApplyIconTextFont(cdText, fontPath, dtSize, "raidFrames")
                cdText:SetTextColor(dtColor.r, dtColor.g, dtColor.b)
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", icon, "CENTER", dtOX, dtOY)
            end
        end
    end

    -- Border
    local bdrSz, bdrC
    if auraType == "def" then
        bdrSz = s2.defBorderSize or 1
        bdrC = s2.defBorderColor or { r = 0, g = 0, b = 0 }
    else
        bdrSz = s2.debuffBorderSize or 1
        bdrC = s2.debuffBorderColor or { r = 0, g = 0, b = 0 }
    end
    if icon._borderFrame and PP and bdrSz > 0 then
        PP.UpdateBorder(icon._borderFrame, bdrSz, bdrC.r, bdrC.g, bdrC.b, 1)
        icon._borderFrame:Show()
    elseif icon._borderFrame then
        icon._borderFrame:Hide()
    end

    -- Stacks text (debuffs only: show "2" on exactly one random debuff)
    if icon._count then
        icon._count:SetText("")
    end

    icon:Show()

    -- Track expiration
    local key = frameIndex .. ":" .. auraType .. ":" .. slotIndex
    ns._pvActiveAuras[key] = { frameIndex = frameIndex, auraType = auraType,
        slot = slotIndex, expTime = startTime + dur }
end

-- Count active auras of a type in a group (optionally skip slots below minSlot)
local function PvAuraCountInGroup(group, auraType, minSlot)
    minSlot = minSlot or 1
    local count = 0
    for _, info in pairs(ns._pvActiveAuras) do
        if info.auraType == auraType and info.slot >= minSlot
            and PvAuraGetGroup(info.frameIndex) == group
            and info.expTime > GetTime() then
            count = count + 1
        end
    end
    return count
end

-- Pick a random frame in a group that doesn't have a random aura of this type
-- (ignores permanent slot 1 debuffs so random debuffs can still be assigned)
local function PvAuraPickFrame(group, auraType, minSlot)
    minSlot = minSlot or 1
    local candidates = {}
    local pf = PvFrames()
    local startIdx = (group - 1) * 5 + 1
    local endIdx = group * 5
    for i = startIdx, endIdx do
        if i <= #pf and pf[i] then
            local hasType = false
            for _, info in pairs(ns._pvActiveAuras) do
                if info.frameIndex == i and info.auraType == auraType
                    and info.slot >= minSlot and info.expTime > GetTime() then
                    hasType = true; break
                end
            end
            if not hasType then candidates[#candidates + 1] = i end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

-- Re-anchor all visible icons on a frame for CENTER growth
local function PvAuraReanchorFrame(frameIndex, auraType)
    local f = PvFrames()[frameIndex]
    if not f then return end
    local pool = auraType == "def" and f._pvDefs
        or f._pvDebuffs
    if not pool then return end
    local shown = 0
    for _, ic in ipairs(pool) do
        if ic:IsShown() then shown = shown + 1 end
    end
    local slotIdx = 0
    for _, ic in ipairs(pool) do
        if ic:IsShown() then
            PvAuraAnchor(ic, f, auraType, slotIdx, shown)
            slotIdx = slotIdx + 1
        end
    end
end

local function PvAuraTick()
    if not PvActive() then return end
    local now = GetTime()
    local s2 = PvSettings()
    local wantDef = ns._defensivesPreviewVisible and (s2.showDefensives or s2.showExternals)
    local wantDb = ns._debuffsPreviewVisible and s2.debuffFilter ~= "none"

    -- Expire finished auras. In Real/Overlay preview the random per-player auras
    -- (defensives and random debuffs in slot 2+) loop on the SAME frame with a fresh
    -- duration instead of being removed -- otherwise the per-group top-up below
    -- re-picks a new random player every cycle, so icons appear to "jump" between
    -- players. Full Preview (test mode) keeps rotating. The raid-wide pulse debuff (db
    -- slot 1) is never looped here; it hits every frame at once on its own pulse cycle.
    local loopSame = not ns._testMode
    for key, info in pairs(ns._pvActiveAuras) do
        if key ~= "_stackKey" and key ~= "raidwide:db" and info.expTime and info.expTime <= now then
            local isRandom = info.auraType == "def"
                or (info.auraType == "db" and info.slot >= 2)
            if loopSame and isRandom then
                -- Re-spawn on the same frame/slot (overwrites this same key, so the
                -- group count stays put and no new player is chosen). If it held the
                -- stacks marker, drop it so the stacks pass re-applies the count text.
                if ns._pvActiveAuras._stackKey == key then ns._pvActiveAuras._stackKey = nil end
                PvAuraApply(info.frameIndex, info.auraType, info.slot)
                PvAuraReanchorFrame(info.frameIndex, info.auraType)
            else
                local f = PvFrames()[info.frameIndex]
                if f then
                    local pool = info.auraType == "def" and f._pvDefs
                        or f._pvDebuffs
                    local ic = pool and pool[info.slot]
                    if ic then
                        ic:Hide()
                        if ic._cooldown then ic._cooldown:Clear() end
                        if ic._count then ic._count:SetText("") end
                    end
                end
                if ns._pvActiveAuras._stackKey == key then ns._pvActiveAuras._stackKey = nil end
                ns._pvActiveAuras[key] = nil
            end
        end
    end

    -- Raid-wide debuff pulse: 10s debuff on ALL frames, cycling every 25s
    if wantDb then
        -- Check if the raid-wide pulse is active or needs to start/restart
        local pulseKey = "raidwide:db"
        local pulseInfo = ns._pvActiveAuras[pulseKey]
        if not pulseInfo then
            -- First tick or after expiry gap: schedule next pulse
            ns._pvActiveAuras[pulseKey] = { nextPulse = now, active = false }
            pulseInfo = ns._pvActiveAuras[pulseKey]
        end
        if pulseInfo.active and pulseInfo.expTime and pulseInfo.expTime <= now then
            -- Pulse expired: hide slot 1 on all frames. While wrapping is on,
            -- skip the player frame (index 1) -- it's a dedicated full showcase
            -- (filled below) so its slots stay put instead of pulsing.
            local pf = PvFrames()
            for fi = (((s2.debuffPerRow or 1) > 1) and 2 or 1), #pf do
                local f = pf[fi]
                if f and f._pvDebuffs and f._pvDebuffs[1] then
                    f._pvDebuffs[1]:Hide()
                    if f._pvDebuffs[1]._cooldown then f._pvDebuffs[1]._cooldown:Clear() end
                    -- Re-pack remaining debuffs so a surviving slot-2+ icon shifts
                    -- into the vacated first position immediately, instead of only
                    -- when that icon itself refreshes.
                    PvAuraReanchorFrame(fi, "db")
                end
                ns._pvActiveAuras[fi .. ":db:1"] = nil
            end
            pulseInfo.active = false
            pulseInfo.nextPulse = now + 15  -- 15s gap before next pulse
        end
        if not pulseInfo.active and now >= (pulseInfo.nextPulse or 0) then
            -- Apply 10s debuff to all frames (skip the player showcase frame 1
            -- while wrapping is on; it owns its own debuff slots, filled below).
            local dur = 10
            local pf = PvFrames()
            for fi = (((s2.debuffPerRow or 1) > 1) and 2 or 1), #pf do
                local key = fi .. ":db:1"
                local f = pf[fi]
                if f and f._pvDebuffs and f._pvDebuffs[1] and f._health then
                    local icon = f._pvDebuffs[1]
                    icon._tex:SetTexture(5927657)
                    local _z = s2.debuffIconZoom or 0.08
                    icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
                    icon:SetSize(ns.RFC_DebuffSize(s2), ns.RFC_DebuffSize(s2))
                    if icon._cooldown then
                        icon._cooldown:SetCooldown(now, dur)
                        icon._cooldown:SetDrawSwipe(s2.debuffShowSwipe ~= false)
                        icon._cooldown:SetHideCountdownNumbers(not s2.debuffShowDurText)
                        icon._cooldown:Show()
                        if s2.debuffShowDurText then
                            local cdText = icon._cooldown.GetCountdownFontString and icon._cooldown:GetCountdownFontString()
                            if cdText then
                                local dtc = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                                local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                EllesmereUI.ApplyIconTextFont(cdText, fp, s2.debuffDurTextSize or 8, "raidFrames")
                                cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", icon, "CENTER",
                                    s2.debuffDurTextOffsetX or 0, s2.debuffDurTextOffsetY or 0)
                            end
                        end
                    end
                    local bdrSz = s2.debuffBorderSize or 1
                    local bdrC = s2.debuffBorderColor or { r = 0, g = 0, b = 0 }
                    if icon._borderFrame and PP and bdrSz > 0 then
                        PP.UpdateBorder(icon._borderFrame, bdrSz, bdrC.r, bdrC.g, bdrC.b, 1)
                        icon._borderFrame:Show()
                    elseif icon._borderFrame then
                        icon._borderFrame:Hide()
                    end
                    icon:Show()
                    -- Re-pack all shown debuffs so slot 1 takes the first position
                    -- and any random slot-2+ debuff shifts right, rather than the
                    -- two overlapping when the pulse returns.
                    PvAuraReanchorFrame(fi, "db")
                    ns._pvActiveAuras[key] = { frameIndex = fi, auraType = "db",
                        slot = 1, expTime = now + dur }
                end
            end
            pulseInfo.active = true
            pulseInfo.expTime = now + dur
        end

        -- Row-wrap showcase: when wrapping is enabled, fill the player frame
        -- (index 1) up to debuffCap so the full multi-row layout is actually
        -- visible -- the ambient pulse/random spawns only put 1-2 per frame,
        -- which can't demonstrate wrapping. Slots 2+ loop on their own (see the
        -- expiry pass); slot 1 is re-topped here since the pulse skips frame 1.
        if (s2.debuffPerRow or 1) > 1 then
            local cap = s2.debuffCap or 3
            local f1 = PvFrames()[1]
            if f1 and f1._pvDebuffs then
                local changed = false
                for slot = 1, cap do
                    if f1._pvDebuffs[slot] then
                        local key = "1:db:" .. slot
                        local info = ns._pvActiveAuras[key]
                        if not (info and info.expTime > now) then
                            PvAuraApply(1, "db", slot)
                            changed = true
                        end
                    end
                end
                if changed then PvAuraReanchorFrame(1, "db") end
            end
        end
    end

    -- Ensure minimum random auras per group for each enabled category.
    -- Party is a single group of 5, so it gets a higher per-group defensive
    -- count (3) to read as a populated showcase; raid keeps 1 per group.
    local defTarget = ns._partyPvActive and 3 or 1
    for group = 1, 4 do
        while wantDef and PvAuraCountInGroup(group, "def") < defTarget do
            local fi = PvAuraPickFrame(group, "def")
            if not fi then break end
            PvAuraApply(fi, "def", 1); PvAuraReanchorFrame(fi, "def")
        end
        -- Random debuffs use slot 2+
        if wantDb and PvAuraCountInGroup(group, "db", 2) < 1 then
            local fi = PvAuraPickFrame(group, "db", 2)
            if fi then PvAuraApply(fi, "db", 2); PvAuraReanchorFrame(fi, "db") end
        end
    end

    -- Assign stacks "2" to exactly one active debuff (slot 2+).
    -- Stays on the same icon until it expires, then the next new one gets it.
    if wantDb and s2.debuffShowStacks then
        -- Check if current stacks target is still alive
        local stackKey = ns._pvActiveAuras._stackKey
        local stackAlive = stackKey and ns._pvActiveAuras[stackKey] and ns._pvActiveAuras[stackKey].expTime > now
        if not stackAlive then
            -- Clear old stacks text
            if stackKey then
                local oldInfo = ns._pvActiveAuras[stackKey]
                -- oldInfo may have been wiped already
            end
            ns._pvActiveAuras._stackKey = nil
        end
        -- If no current target, assign to the next new debuff that appears
        -- (handled in PvAuraApply via _pvNeedStacks flag)
        if not ns._pvActiveAuras._stackKey then
            -- Find any active slot 2+ debuff to assign stacks to
            for key, info in pairs(ns._pvActiveAuras) do
                if key ~= "_stackKey" and info.auraType == "db" and info.slot >= 2 and info.expTime > now then
                    ns._pvActiveAuras._stackKey = key
                    local f = PvFrames()[info.frameIndex]
                    local ic = f and f._pvDebuffs and f._pvDebuffs[info.slot]
                    if ic and ic._count then
                        local stc = s2.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                        local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                        EllesmereUI.ApplyIconTextFont(ic._count, fp, s2.debuffStacksTextSize or 8, "raidFrames")
                        ic._count:SetTextColor(stc.r, stc.g, stc.b)
                        ic._count:ClearAllPoints()
                        ic._count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT",
                            1 + (s2.debuffStacksOffsetX or 0), -1 + (s2.debuffStacksOffsetY or 0))
                        ic._count:SetText("2")
                    end
                    break
                end
            end
        end
    end

end

local function StartPvAuraTicker()
    if not pvAuraTicker then
        -- Seed initial auras
        PvAuraTick()
        pvAuraTicker = C_Timer.NewTicker(0.5, PvAuraTick)
    end
end

local function StopPvAuraTicker()
    if pvAuraTicker then
        pvAuraTicker:Cancel()
        pvAuraTicker = nil
    end
    wipe(ns._pvActiveAuras)
    -- Hide all preview aura icons, reset cooldowns, unregister dur texts
    for _, f in ipairs(PvFrames()) do
        if f._pvDebuffs then
            for _, ic in ipairs(f._pvDebuffs) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:Clear() end
            end
        end
        if f._pvDefs then
            for _, ic in ipairs(f._pvDefs) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:Clear() end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Preview Buff Ticker (test mode only: cycles configured buffs across frames)
-------------------------------------------------------------------------------
ns._pvBuffTicker = nil
ns._pvBuffAssignments = {}

local function GetConfiguredBuffSpells()
    -- WoW Forever: this preview reads only the retired pre-v2 Buff Manager
    -- keys, which a profile there can still carry; it previews nothing there.
    if EllesmereUI.IS_FOREVER then return {} end
    if not db or not db.profile or not db.profile.bmIndicators then return {} end
    -- BM indicators are keyed by "CLASS_SPEC" strings (e.g. "PALADIN_HOLY").
    -- Resolve the player's spec via the shared, locale-independent helper (matches
    -- by spec ID, not the localized spec name) so indicators show on every client.
    local specKey = ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey()
    -- Untracked spec: preview only the class-fallback indicators flagged
    -- Show Own on All Specs (the ones that actually render live there).
    local flaggedOnly = false
    if not specKey then
        specKey = ns.BM_ClassFallbackSpecKey and ns.BM_ClassFallbackSpecKey()
        flaggedOnly = true
    end
    if not specKey then return {} end
    local indicators = db.profile.bmIndicators[specKey]
    if not indicators then return {} end
    local spells = {}
    local seen = {}
    for _, ind in ipairs(indicators) do
        if ind.enabled and ind.spells and (not flaggedOnly or ind.showOwnAllSpecs)
           and (ind.type == "icon" or ind.type == "square") then
            for _, sid in ipairs(ind.spells) do
                if not seen[sid] then
                    seen[sid] = true
                    local iconTex
                    if ind.type == "icon" then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                        iconTex = info and info.iconID or 136243
                    end
                    local baseSz = ind.size or 18
                    local soff = ind.sizeOffsets and ind.sizeOffsets[sid] or 0
                    local spellSz = baseSz + soff
                    if spellSz < 1 then spellSz = 1 end
                    spells[#spells + 1] = {
                        id = sid, icon = iconTex,
                        indType = ind.type,
                        color = (ind.spellColors and ind.spellColors[sid]) or ind.color,
                        size = ns.RFC_SnapSize(spellSz),
                        position = ind.position or "TOPLEFT",
                        offsetX = ind.offsetX or 0,
                        offsetY = ind.offsetY or 0,
                        growDirection = ind.growDirection or "RIGHT",
                        spacing = ind.spacing or 0,
                        borderSize = ind.indBorderSize or 1,
                        borderColor = ind.indBorderColor or { r = 0, g = 0, b = 0 },
                        permanent = ns.BM_PREVIEW_NO_DURATION and ns.BM_PREVIEW_NO_DURATION[sid],
                    }
                end
            end
        end
    end
    return spells
end

ns.PvBuffAnchor = function(icon, f, spellInfo, prevIcon)
    if not f._health then return end
    icon:SetSize(spellInfo.size, spellInfo.size)
    icon:ClearAllPoints()
    if prevIcon then
        -- Chain from previous icon using growth direction
        local spc = PixelSnap(spellInfo.spacing or 0)
        local grow = spellInfo.growDirection or "RIGHT"
        if grow == "RIGHT" then icon:SetPoint("LEFT", prevIcon, "RIGHT", spc, 0)
        elseif grow == "LEFT" then icon:SetPoint("RIGHT", prevIcon, "LEFT", -spc, 0)
        elseif grow == "UP" then icon:SetPoint("BOTTOM", prevIcon, "TOP", 0, spc)
        elseif grow == "DOWN" then icon:SetPoint("TOP", prevIcon, "BOTTOM", 0, -spc)
        end
    else
        local pos = spellInfo.position and spellInfo.position:upper() or "BOTTOMLEFT"
        local ox, oy = spellInfo.offsetX or 0, spellInfo.offsetY or 0
        icon:SetPoint(pos, ns.RF_AnchorHost(f._health, PvSettings()), pos, ox, oy)
    end
end

ns.PvBuffApply = function(spellInfo, frameIndex, slot)
    local f = previewFrames[frameIndex]
    if not f or not f._pvBuffs then return end
    local icon = f._pvBuffs[slot]
    if not icon then return end

    if spellInfo.indType == "icon" then
        icon._tex:SetTexture(spellInfo.icon or 136243)
        icon._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon._tex:SetVertexColor(1, 1, 1)
    else
        local c = spellInfo.color or { r = 0.05, g = 0.82, b = 0.62 }
        icon._tex:SetColorTexture(c.r, c.g, c.b, 1)
        icon._tex:SetTexCoord(0, 1, 0, 1)
    end

    ns.PvBuffAnchor(icon, f, spellInfo)

    -- Border
    if icon._borderFrame and PP and spellInfo.borderSize > 0 then
        PP.UpdateBorder(icon._borderFrame, spellInfo.borderSize,
            spellInfo.borderColor.r, spellInfo.borderColor.g, spellInfo.borderColor.b, 1)
        icon._borderFrame:Show()
    elseif icon._borderFrame then
        icon._borderFrame:Hide()
    end

    -- Cooldown
    if icon._cooldown then
        if not spellInfo.permanent then
            local dur = 15
            local startTime = GetTime() - math.random() * 10
            icon._cooldown:SetCooldown(startTime, dur)
            icon._cooldown:SetDrawSwipe(true)
            icon._cooldown:SetHideCountdownNumbers(true)
            icon._cooldown:Show()
        else
            icon._cooldown:Hide()
        end
    end

    icon:Show()
end

ns.PvBuffTick = function()
    if not previewActive or not ns._testBuffsVisible then return end
    local now = GetTime()
    local PREVIEW_COUNT2 = #previewFrames

    -- Loop cooldown swipes on player frame buffs (permanent, but swipe should cycle)
    local playerF = previewFrames[1]
    if playerF and playerF._pvBuffs then
        for _, info in pairs(ns._pvBuffAssignments) do
            if info.permanent and info.frameIndex == 1 and not info.spellInfo.permanent then
                if not info.cdEndTime or now >= info.cdEndTime then
                    local ic = playerF._pvBuffs[info.slot]
                    if ic and ic._cooldown then
                        local dur = 12 + math.random() * 8  -- 12-20s
                        ic._cooldown:SetCooldown(now, dur)
                        info.cdEndTime = now + dur
                    end
                end
            end
        end
    end

    -- Expire and reassign
    for sid, info in pairs(ns._pvBuffAssignments) do
        if not info.permanent and info.expTime and info.expTime <= now then
            -- Hide old
            local f = previewFrames[info.frameIndex]
            if f and f._pvBuffs and f._pvBuffs[info.slot] then
                local ic = f._pvBuffs[info.slot]
                ic:Hide()
                if ic._cooldown then ic._cooldown:SetCooldown(0, 0) end
            end
            -- Pick new frame (skip frame 1 = player)
            local newFi = math.random(2, PREVIEW_COUNT2)
            local tries = 0
            while newFi == info.frameIndex and tries < 5 do
                newFi = math.random(2, PREVIEW_COUNT2); tries = tries + 1
            end
            info.frameIndex = newFi
            info.expTime = now + 15
            ns.PvBuffApply(info.spellInfo, newFi, info.slot)
        end
    end
end

ns.StartPvBuffTicker = function()
    if ns._pvBuffTicker then return end
    wipe(ns._pvBuffAssignments)

    local spells = GetConfiguredBuffSpells()
    if #spells == 0 then return end

    local now = GetTime()
    local PREVIEW_COUNT2 = #previewFrames
    local playerSlot = 0

    -- Player frame (1): show all buffs, max 3 per position, chained
    local posCounts = {}   -- [position] = count
    local posLastIcon = {} -- [position] = last icon frame for chaining
    local playerF = previewFrames[1]
    if playerF and playerF._pvBuffs then
        for _, sp in ipairs(spells) do
            local pos = sp.position
            posCounts[pos] = (posCounts[pos] or 0) + 1
            if posCounts[pos] <= 3 then
                playerSlot = playerSlot + 1
                if playerSlot > 8 then break end
                local prev = posLastIcon[pos]
                ns.PvBuffApply(sp, 1, playerSlot)
                local icon = playerF._pvBuffs[playerSlot]
                if icon then
                    ns.PvBuffAnchor(icon, playerF, sp, prev)
                    posLastIcon[pos] = icon
                end
                ns._pvBuffAssignments[sp.id .. ":p"] = {
                    spellInfo = sp, frameIndex = 1, slot = playerSlot,
                    expTime = now + 99999, permanent = true,  -- always visible on player
                }
            end
        end
    end

    -- Other frames: spread spells across frames 2+, one each, cycling on expiry
    local frameSlotsUsed = {}
    for i, sp in ipairs(spells) do
        local fi = ((i - 1) % (PREVIEW_COUNT2 - 1)) + 2
        frameSlotsUsed[fi] = (frameSlotsUsed[fi] or 0) + 1
        local slot = frameSlotsUsed[fi]
        if slot > 4 then break end
        ns._pvBuffAssignments[sp.id] = {
            spellInfo = sp, frameIndex = fi, slot = slot,
            expTime = sp.permanent and (now + 99999) or (now + math.random(3, 15)),
            permanent = sp.permanent,
        }
        ns.PvBuffApply(sp, fi, slot)
    end

    ns._pvBuffTicker = C_Timer.NewTicker(0.5, ns.PvBuffTick)
end

ns.StopPvBuffTicker = function()
    if ns._pvBuffTicker then ns._pvBuffTicker:Cancel(); ns._pvBuffTicker = nil end
    wipe(ns._pvBuffAssignments)
    for _, f in ipairs(previewFrames) do
        if f._pvBuffs then
            for _, ic in ipairs(f._pvBuffs) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:SetCooldown(0, 0) end
            end
        end
    end
end

-- Restart: stop (instant clear) then start if any eyeball is on
local function RestartPvAuraTicker()
    StopPvAuraTicker()
    if PvActive() and (ns._defensivesPreviewVisible or ns._debuffsPreviewVisible) then
        StartPvAuraTicker()
    end
end
ns.RestartPvAuraTicker = RestartPvAuraTicker

-- Re-anchor + resize + re-border all active preview aura icons (settings changed, no icon swap)
-- Reads shared state via ns to stay under the 60-upvalue cap.
ns._PvAuraReanchorFrame = PvAuraReanchorFrame
ns.RefreshPvAuraVisuals = function()
    local s2 = PvSettings()
    if not s2 then return end
    local _PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local _pvFrames = PvFrames()
    local _reanchor = ns._PvAuraReanchorFrame
    local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

    local dbZ = s2.debuffIconZoom or 0.08
    local defZ = s2.defIconZoom or 0.08
    local dbBdrSz = s2.debuffBorderSize or 1
    local dbBdrC = s2.debuffBorderColor or { r = 0, g = 0, b = 0 }
    local dbShowSwipe = s2.debuffShowSwipe ~= false
    local dbShowDurText = s2.debuffShowDurText
    local dbDtC = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
    local dbDtSz = s2.debuffDurTextSize or 8
    local dbDtOX = s2.debuffDurTextOffsetX or 0
    local dbDtOY = s2.debuffDurTextOffsetY or 0
    local defBdrSz = s2.defBorderSize or 1
    local defBdrC = s2.defBorderColor or { r = 0, g = 0, b = 0 }
    local defShowSwipe = s2.defShowSwipe ~= false
    local defShowDurText = s2.defShowDurText
    local defDtC = s2.defDurTextColor or { r = 1, g = 1, b = 1 }
    local defDtSz = s2.defDurTextSize or 8
    local defDtOX = s2.defDurTextOffsetX or 0
    local defDtOY = s2.defDurTextOffsetY or 0
    local stc = s2.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
    local sSz = s2.debuffStacksTextSize or 8
    local sOX = s2.debuffStacksOffsetX or 0
    local sOY = s2.debuffStacksOffsetY or 0

    for fi, f in ipairs(_pvFrames) do
        if f._pvDebuffs then
            for _, ic in ipairs(f._pvDebuffs) do
                if ic:IsShown() then
                    ic:SetSize(ns.RFC_DebuffSize(s2), ns.RFC_DebuffSize(s2))
                    ic._tex:SetTexCoord(dbZ, 1 - dbZ, dbZ, 1 - dbZ)
                    if ic._borderFrame and _PP then
                        if dbBdrSz > 0 then
                            _PP.UpdateBorder(ic._borderFrame, dbBdrSz, dbBdrC.r, dbBdrC.g, dbBdrC.b, 1)
                            ic._borderFrame:Show()
                        else
                            ic._borderFrame:Hide()
                        end
                    end
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(dbShowSwipe)
                        ic._cooldown:SetHideCountdownNumbers(not dbShowDurText)
                        if dbShowDurText then
                            local cdText = ic._cooldown.GetCountdownFontString and ic._cooldown:GetCountdownFontString()
                            if cdText then
                                EllesmereUI.ApplyIconTextFont(cdText, fp, dbDtSz, "raidFrames")
                                cdText:SetTextColor(dbDtC.r, dbDtC.g, dbDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", dbDtOX, dbDtOY)
                            end
                        end
                    end
                    if ic._count and ic._count:GetText() ~= "" then
                        EllesmereUI.ApplyIconTextFont(ic._count, fp, sSz, "raidFrames")
                        ic._count:SetTextColor(stc.r, stc.g, stc.b)
                        ic._count:ClearAllPoints()
                        ic._count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1 + sOX, -1 + sOY)
                    end
                end
            end
            _reanchor(fi, "db")
        end
        if f._pvDefs then
            for _, ic in ipairs(f._pvDefs) do
                if ic:IsShown() then
                    ic:SetSize(s2.defSize or 22, s2.defSize or 22)
                    ic._tex:SetTexCoord(defZ, 1 - defZ, defZ, 1 - defZ)
                    if ic._borderFrame and _PP then
                        if defBdrSz > 0 then
                            _PP.UpdateBorder(ic._borderFrame, defBdrSz, defBdrC.r, defBdrC.g, defBdrC.b, 1)
                            ic._borderFrame:Show()
                        else
                            ic._borderFrame:Hide()
                        end
                    end
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(defShowSwipe)
                        ic._cooldown:SetHideCountdownNumbers(not defShowDurText)
                        if defShowDurText then
                            local cdText = ic._cooldown.GetCountdownFontString and ic._cooldown:GetCountdownFontString()
                            if cdText then
                                EllesmereUI.ApplyIconTextFont(cdText, fp, defDtSz, "raidFrames")
                                cdText:SetTextColor(defDtC.r, defDtC.g, defDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", defDtOX, defDtOY)
                            end
                        end
                    end
                end
            end
            _reanchor(fi, "def")
        end
    end
end

-- Preview frames: standalone frames NOT managed by SecureGroupHeaderTemplate.
-- Header-managed buttons can't be shown without real units, so we create
-- our own lightweight frames that look identical for the options preview.
previewFrames = {}
local previewGroupLabels = {}  -- [1..4] FontStrings showing group numbers
local previewContainer = nil   -- standalone anchor frame for preview (doesn't move with containerFrame)
local previewHiddenParent = nil -- hidden frame to reparent containerFrame into during preview

local function CreatePreviewFrame(index, party)
    local s = db.profile
    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    -- Party Frames kit (party preview only): the stock frame's own layout.
    local kit = party and ns.RF_PartyKit()
    local healthH = PixelSnap(h - ns.RF_HealthPowerInset(s, powerH))

    local f = CreateFrame("Frame", nil, previewContainer or containerFrame)
    f:SetSize(w, h)
    f:SetFrameStrata("HIGH")
    f:Hide()

    -- Background
    local bgc = s.customBgColor or defaults.customBgColor
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    if PP then PP.DisablePixelSnap(bg) end

    -- Health bar
    local health = CreateFrame("StatusBar", nil, f)
    health:SetFrameLevel(f:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    health:SetStatusBarTexture(ResolveHealthTexture())
    health:GetStatusBarTexture():SetHorizTile(false)
    if PP then PP.DisablePixelSnap(health) end
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so
    -- Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    f._uniformRef = CreateFrame("Frame", nil, f)
    f._uniformRef:SetFrameLevel(health:GetFrameLevel())
    f._uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    f._uniformRef:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = f._uniformRef
    f._uniformRef._euiHealth = health

    -- Absorb shield preview (dual clip-frame, matching real frames)
    -- Mask: constrains absorb rendering to health bar bounds
    local absorbMask = health:CreateMaskTexture()
    absorbMask:SetAllPoints(health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Current HP clip: bounds the backfill bar to the filled health area
    local curClip = CreateFrame("Frame", nil, health)
    curClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    curClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area
    local missClip = CreateFrame("Frame", nil, health)
    missClip:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
    missClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    missClip:SetClipsChildren(true)

    -- Backfill bar: grows into filled health from the right (overshield)
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask) end
    -- Modern compound absorb base (preview): mirrors the live frame's solid c6c8ff
    -- base drawn under the striped fill. Anchored to the fill at render time.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:Hide()
    backfillBar._modernBase = bfBase
    backfillBar:SetStatusBarColor(1, 1, 1, 0.3)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(health:GetWidth())
    backfillBar:SetHeight(health:GetHeight())
    -- Absorb on top of the HP cluster (above heal absorb/heal pred and max health).
    backfillBar:SetFrameLevel(health:GetFrameLevel() + 3)
    backfillBar:SetMinMaxValues(0, 100)
    backfillBar:Hide()

    -- Forward bar: grows into missing health from the HP edge
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    -- Modern compound absorb base (preview) for the forward bar.
    local fwBase = forwardBar:CreateTexture(nil, "ARTWORK", nil, 0)
    fwBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then fwBase:AddMaskTexture(absorbMask) end
    fwBase:Hide()
    forwardBar._modernBase = fwBase
    forwardBar:SetStatusBarColor(1, 1, 1, 0.3)
    forwardBar:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    forwardBar:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    forwardBar:SetWidth(health:GetWidth())
    forwardBar:SetHeight(health:GetHeight())
    -- Match backfill: absorb above heal absorb/heal pred and max health.
    forwardBar:SetFrameLevel(health:GetFrameLevel() + 3)
    forwardBar:SetMinMaxValues(0, 100)
    forwardBar:Hide()

    -- "Default Blizz Frames" spark (preview): mirrors live -- a fixed 16px cast_spark
    -- glow on a non-clipping host above the shield, CENTER pinned to the forward bar's
    -- LEFT edge (the seam). Gated by the preview's plain absorb compare in the renderer.
    local sparkHost = CreateFrame("Frame", nil, health)
    sparkHost:SetAllPoints(health)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(health:GetFrameLevel() + 4)
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, health:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark (preview): rides the backfill's left edge while overshielding.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, health:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Heal absorb bar (preview): red overlay eating into filled health from HP edge
    do
        -- Own clip frame (mirrors live): right/left span the full bar, overlay
        -- clips to filled health. Bounds set per healAbsorbEdgeMode in render.
        local healClip = CreateFrame("Frame", nil, health)
        healClip:SetClipsChildren(true)
        healClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        healClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        f._healClip = healClip
        local ha = CreateFrame("StatusBar", nil, healClip)
        ha:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = ha:GetStatusBarTexture()
        if hf then hf:SetDrawLayer("ARTWORK", 2); hf:AddMaskTexture(absorbMask) end
        ha:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
        ha:SetReverseFill(true)
        ha:SetPoint("TOPRIGHT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        ha:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        ha:SetWidth(health:GetWidth())
        ha:SetHeight(health:GetHeight())
        ha:SetFrameLevel(health:GetFrameLevel() + 1)
        ha:SetMinMaxValues(0, 100)
        ha._mask = absorbMask
        -- Black backing behind the heal-absorb texture (preview; mirrors live).
        local haBg = ha:CreateTexture(nil, "ARTWORK", nil, 1)
        haBg:SetColorTexture(0, 0, 0, 0.25)
        if absorbMask then haBg:AddMaskTexture(absorbMask) end
        haBg:Hide()
        ha._bg = haBg
        ha:Hide()
        f._healAbsorbBar = ha
    end

    -- Heal prediction bar (preview): extends from HP edge into missing health
    do
        local hp = CreateFrame("StatusBar", nil, missClip)
        hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = hp:GetStatusBarTexture()
        if hf then hf:SetDrawLayer("ARTWORK", 2); hf:AddMaskTexture(absorbMask) end
        hp:SetStatusBarColor(0.3, 0.8, 0.3, 0.4)
        hp:SetReverseFill(false)
        hp:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        hp:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        hp:SetWidth(health:GetWidth())
        hp:SetHeight(health:GetHeight())
        hp:SetFrameLevel(health:GetFrameLevel() + 1)
        hp:SetMinMaxValues(0, 100)
        hp:Hide()
        f._healPredBar = hp
    end

    -- Reduced max health bar (preview): black bg + red striped overlay on right side
    do
        local rmh = CreateFrame("StatusBar", nil, health)
        rmh:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png")
        local rmhFill = rmh:GetStatusBarTexture()
        if rmhFill then
            rmhFill:SetDrawLayer("ARTWORK", 3)
            rmhFill:SetHorizTile(true); rmhFill:SetVertTile(true)
        end
        rmh:SetStatusBarColor(0.7, 0.1, 0.1, 1)
        rmh:SetReverseFill(true)
        rmh:SetAllPoints(health)
        rmh:SetFrameLevel(health:GetFrameLevel() + 2)
        rmh:SetMinMaxValues(0, 1)
        rmh:Hide()
        -- Black background behind the stripes
        local rmhBg = rmh:CreateTexture(nil, "ARTWORK", nil, 2)
        rmhBg:SetAllPoints(rmhFill)
        rmhBg:SetColorTexture(0, 0, 0, 1)
        f._reducedMaxHealthBar = rmh
        f._reducedMaxHealthBg = rmhBg
    end

    -- Store absorb references on preview frame
    local absorbBar = backfillBar
    absorbBar._forward = forwardBar
    absorbBar._mask = absorbMask
    absorbBar._curClip = curClip
    absorbBar._missClip = missClip

    -- Absorb Bar (preview): solid bar above the frame, fills from the right
    do
        local tb = CreateFrame("StatusBar", nil, f)
        tb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        tb:SetStatusBarColor(1, 1, 1, 1)
        tb:SetReverseFill(true)
        tb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
        tb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
        tb:SetHeight(4)
        tb:SetFrameLevel(health:GetFrameLevel() + 3)
        tb:SetMinMaxValues(0, 100)
        tb:Hide()
        absorbBar._topBar = tb
    end

    -- Heal Absorb Bar (preview): mirrors the Absorb Bar strip above.
    do
        local thb = CreateFrame("StatusBar", nil, f)
        thb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        thb:SetStatusBarColor(200/255, 29/255, 29/255, 1)
        thb:SetReverseFill(true)
        thb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
        thb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
        thb:SetHeight(4)
        thb:SetFrameLevel(health:GetFrameLevel() + 3)
        thb:SetMinMaxValues(0, 100)
        thb:Hide()
        absorbBar._healTopBar = thb
    end

    -- Power bar (anchored to frame bottom for pixel alignment; the Party
    -- Frames kit always has its mana bar)
    local power
    if powerH > 0 or kit then
        power = CreateFrame("StatusBar", nil, f)
        power:SetFrameLevel(f:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(ResolveHealthTexture())
        power:GetStatusBarTexture():SetHorizTile(false)
        if PP then PP.DisablePixelSnap(power) end
        power:SetMinMaxValues(0, 100)
        power:SetValue(100)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
        if PP then PP.DisablePixelSnap(pwBg) end
        f._powerBg = pwBg

        -- Power border
        local pwBdr = CreateFrame("Frame", nil, f)
        pwBdr:SetAllPoints(power)
        pwBdr:SetFrameLevel(power:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(pwBdr, 0, 0, 0, 1, 1) end
        f._powerBorder = pwBdr
    end

    -- Border (single border styled via ApplyBorderStyle in ApplyPreviewData,
    -- recolored by state -- mirrors the real frames)
    local bdrFrame = CreateFrame("Frame", nil, f)
    bdrFrame:SetAllPoints(f)
    bdrFrame:SetFrameLevel(f:GetFrameLevel() + 8)

    local function PvApplyBorderColor()
        if not PP then return end
        -- Overlay ahead of _scaledProfile: border/hover/target keys are not
        -- tier-scaled, so the effective overlay may shadow them safely.
        local s = ns._previewSettingsOverride or (ns._partyPvActive and ns._scaledPartyProxy)
            or ns._pvOverlayProxy or ns._scaledProfile
        if f.kit then
            ns.RF_KitHighlight(f, bdrFrame, s, f._hovered and s.hoverBorderEnabled ~= false,
                f._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        if f.stockEdge then
            local hover = f._hovered and s.hoverBorderEnabled ~= false
            local lvl = f:GetFrameLevel() + (hover and ns.LVL_RAISE or 8)
            if bdrFrame:GetFrameLevel() ~= lvl then
                bdrFrame:SetFrameLevel(lvl)
                local container = PP.GetBorders(bdrFrame)
                if container then container:SetFrameLevel(lvl + 1) end
            end
            ns.RF_StockHighlight(f, bdrFrame, s, hover, f._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        local r, g, b, a
        local raised, hlSize, hlPx = false, nil, nil
        if f._pvDispelBdrC and s.borderBehind then
            -- Show Behind: the live copy sits over the never-raised base border, so the
            -- type color covers hover/target there too.
            local c = f._pvDispelBdrC
            r, g, b, a = c.r, c.g, c.b, c.a or 1
        elseif f._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised, hlSize = true, s.hoverBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif f._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised, hlSize = true, s.targetBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif f._pvAggroBdr then
            -- Threat Borders' Color Custom Borders (set by ApplyPreviewData): the threat
            -- color, raised like the real frames, below hover/target and above dispel.
            r, g, b, a = 1, 0, 0, 1
            raised = true
        elseif f._pvDispelBdrC then
            -- Color Custom Borders (set by ApplyPreviewData): the type color, below hover/target.
            local c = f._pvDispelBdrC
            r, g, b, a = c.r, c.g, c.b, c.a or 1
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        -- Match real frames: raise the inset border above overlapping neighbors
        -- while highlighted (handles negative Frame Spacing in the preview too).
        -- Guard the level writes so a refresh only touches them on a real change.
        local pl = f:GetFrameLevel()
        local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
        local container = PP.GetBorders(bdrFrame)
        if bdrFrame:GetFrameLevel() ~= lvl
           or (container and container:GetFrameLevel() ~= lvl + 1) then
            bdrFrame:SetFrameLevel(lvl)
            if container then container:SetFrameLevel(lvl + 1) end
            -- Textured styles: the backdrop child too, as on live frames.
            local bd = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[bdrFrame]
            if bd then bd:SetFrameLevel(lvl) end
        end
        if (s.borderSize or 1) <= 0 then
            ns.ApplyHighlightBorder(bdrFrame, s, hlSize, r, g, b, a, hlPx)
            return
        end
        if hlSize then r, g, b = ns.RF_VisibleHighlight(s, r, g, b) end
        bdrFrame._hlBorderSize = nil
        EllesmereUI.SetBorderStyleColor(bdrFrame, r, g, b, a)
    end
    f._ApplyBorderColor = PvApplyBorderColor

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() f._hovered = true; PvApplyBorderColor() end)
    f:SetScript("OnLeave", function() f._hovered = false; PvApplyBorderColor() end)

    -- Threat border (aggro indicator)
    local threatFrame = CreateFrame("Frame", nil, f)
    threatFrame:SetAllPoints(f)
    threatFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    threatFrame:Hide()
    if PP then PP.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Click to toggle target in test mode (recolors the single border)
    f:SetScript("OnMouseDown", function(self)
        if not PvActive() then return end
        for _, pf in ipairs(PvFrames()) do
            if pf ~= self and pf._isTarget then
                pf._isTarget = false
                if pf._ApplyBorderColor then pf._ApplyBorderColor() end
            end
        end
        f._isTarget = true
        PvApplyBorderColor()
    end)

    -- Dispel border
    local dispelBdrFrame = CreateFrame("Frame", nil, f)
    dispelBdrFrame:SetAllPoints(health)
    dispelBdrFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    dispelBdrFrame:Hide()
    if PP then PP.CreateBorder(dispelBdrFrame, 0.2, 0.6, 1, 1, 2) end

    -- Dispel overlay (texture on health bar at ARTWORK sublevel 3: above fill
    -- and above the BM health-color overlay (sublevel 2), below absorbs/text)
    local dispelOLTex = health:CreateTexture(nil, "ARTWORK", nil, 3)
    dispelOLTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    dispelOLTex:Hide()

    -- Dispel type icon. Preview parity with the real frames' dispel icon
    -- band: above the aura band so it covers debuff icons sharing its
    -- corner, below the marker band.
    local dispelIconFrame = CreateFrame("Frame", nil, f)
    dispelIconFrame:SetFrameLevel(f:GetFrameLevel() + ns.LVL_MARKER - 1)
    dispelIconFrame:SetSize(16, 16)
    dispelIconFrame:SetPoint("CENTER", health, "CENTER", 0, 0)
    dispelIconFrame:Hide()
    local dispelIconTex = dispelIconFrame:CreateTexture(nil, "ARTWORK")
    dispelIconTex:SetAllPoints()
    dispelIconTex:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Marker carrier: above the frame border (incl. hover/target raise) so the
    -- leader icon and raid marker render on top of it (mirrors real frames).
    local markerCarrier = CreateFrame("Frame", nil, f)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(f:GetFrameLevel() + ns.LVL_MARKER)

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(s.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:Hide()

    -- Ready check icon (position/size re-applied in the preview indicator pass)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(s.readyCheckSize or 20), PixelSnap(s.readyCheckSize or 20))
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    readyCheck:Hide()

    -- Combat icon (position/size/style re-applied in the preview indicator pass)
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    combatIcon:SetSize(PixelSnap(s.combatIndicatorSize or 16), PixelSnap(s.combatIndicatorSize or 16))
    combatIcon:Hide()

    -- Text carrier: text band (above every border incl. the raise, below auras).
    local textCarrier = CreateFrame("Frame", nil, f)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(f:GetFrameLevel() + ns.LVL_TEXT)

    -- Name text (anchoring done by ApplyPreviewData on every refresh)
    local nameFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(nameFS, s.nameSize or 10)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(false)
    nameFS:SetPoint("CENTER", health, "CENTER", 0, 0)

    -- Health text
    local healthFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healthFS, s.healthTextSize or 9)
    healthFS:SetJustifyH("CENTER")
    healthFS:SetPoint("CENTER", health, "CENTER", 0, 0)
    healthFS:SetTextColor(1, 1, 1, 0.9)

    -- Power text (anchored, sized, coloured and shown by ApplyPreviewData)
    local powerFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(powerFS, s.powerTextSize or 8)
    powerFS:SetWordWrap(false)
    powerFS:SetTextColor(1, 1, 1, 0.9)
    powerFS:Hide()

    -- Level text on its own spot (anchored, sized, coloured and shown by ApplyPreviewData)
    local levelFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(levelFS, s.levelTextSize or 10)
    levelFS:SetWordWrap(false)
    levelFS:Hide()

    -- Heal absorb text (preview)
    local healAbsorbFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healAbsorbFS, s.healAbsorbTextSize or 9)
    healAbsorbFS:SetWordWrap(false)
    healAbsorbFS:SetJustifyH("CENTER")
    healAbsorbFS:SetPoint("CENTER", health, "CENTER", 0, 0)

    -- Status text (DEAD / OFFLINE / AFK)
    local statusFS = textCarrier:CreateFontString(nil, "OVERLAY")
    local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
    statusFS:Hide()

    -- Role icon. Carrier sits just BELOW the aura band and above the base border
    -- (mirrors the real frames): clears the general border while auras draw over
    -- it; the hover/target border raise intentionally covers it.
    local roleCarrier = CreateFrame("Frame", nil, f)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(f:GetFrameLevel() + (ns.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)

    -- Leader icon: on the text carrier band (above the general border, below the
    -- aura layer) to mirror the real frames -- the hover/target raise covers it,
    -- the general border does not.
    local leaderIcon = textCarrier:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
    leaderIcon:Hide()

    -- Top Name Bar (preview; sized/styled by ApplyPreviewData)
    local tnb = CreateFrame("Frame", nil, f)
    tnb:SetFrameLevel(f:GetFrameLevel() + 4)
    tnb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tnb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tnb:SetHeight(PixelSnap(s.topNameBarHeight or 20))
    local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
    tnbBg:SetAllPoints()
    if PP then PP.DisablePixelSnap(tnbBg) end
    local tnbText = tnb:CreateFontString(nil, "OVERLAY")
    ApplyFont(tnbText, s.topNameBarTextSize or 11)
    tnbText:SetWordWrap(false)
    tnb:Hide()

    -- Store references
    f._bg = bg
    f._health = health
    f._absorbBar = absorbBar
    f._power = power
    f._border = bdrFrame
    f._threatFrame = threatFrame
    -- Stock styles: the stock edge, highlights and divider (our frame), or
    -- the Party Frames kit (host, art, portrait; stamps health._euiKitRef
    -- here, before any refresh anchors to the host).
    if kit then
        ns.RF_KitBuild(f, f, health, power, bdrFrame)
    elseif ns.RF_Stock() then
        ns.RF_StockBuild(f, f, power)
    end
    f._dispelBdrFrame = dispelBdrFrame
    f._dispelOLTex = dispelOLTex
    f._dispelIcon = dispelIconFrame
    f._dispelIconTex = dispelIconTex
    f._raidMarker = raidMarker
    f._readyCheck = readyCheck
    f._nameText = nameFS
    f._topNameBar = tnb
    f._topNameBarBg = tnbBg
    f._topNameBarText = tnbText
    f._healthText = healthFS
    f._powerText = powerFS
    f._levelText = levelFS
    f._healAbsorbText = healAbsorbFS
    f._statusText = statusFS
    f._roleIcon = roleIcon
    f._leaderIcon = leaderIcon
    f._combatIcon = combatIcon

    -- Helper: create a preview aura icon with texture, cooldown, border
    local function MakePreviewAuraIcon(parent, level, sz)
        local di = CreateFrame("Frame", nil, parent)
        di:SetFrameLevel(level)
        di:SetSize(sz, sz)
        di:Hide()
        local dt = di:CreateTexture(nil, "ARTWORK")
        dt:SetAllPoints(); dt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        di._tex = dt
        local cd = CreateFrame("Cooldown", nil, di, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 0.6); cd:SetReverse(true)
        cd:SetHideCountdownNumbers(true)
        di._cooldown = cd
        local dbdr = CreateFrame("Frame", nil, di)
        dbdr:SetAllPoints(); dbdr:SetFrameLevel(di:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(dbdr, 0, 0, 0, 1, 1) end
        di._borderFrame = dbdr
        local countCarrier = CreateFrame("Frame", nil, di)
        countCarrier:SetAllPoints()
        countCarrier:SetFrameLevel(math.max(cd:GetFrameLevel() + 2, dbdr:GetFrameLevel() + 1))
        local fpInit = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local countFS = countCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", di, "BOTTOMRIGHT", 1, -1)
        EllesmereUI.ApplyIconTextFont(countFS, fpInit, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        countFS:SetText("")
        di._count = countFS
        -- Duration text (on same carrier above cooldown swipe)
        local durFS = countCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", di, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(durFS, fpInit, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        di._durText = durFS
        return di
    end

    -- Debuff preview icons. Pool sized to the max debuffCap (8) so the player
    -- frame can showcase a full wrapping layout; only a few are shown otherwise.
    f._pvDebuffs = {}
    for i = 1, 8 do
        f._pvDebuffs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, ns.RFC_DebuffSize(s))
    end

    -- Static dispel debuff icon (shown when dispel eyeball is on)
    f._pvDispelDebuff = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, ns.RFC_DebuffSize(s))

    -- Defensive preview icons
    f._pvDefs = {}
    for i = 1, 4 do
        f._pvDefs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, s.defSize or 22)
    end

    -- Buff preview icons (test mode: configured buffs cycled across frames)
    f._pvBuffs = {}
    for i = 1, 8 do
        f._pvBuffs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, 18)
    end

    return f
end

local function GetOrCreatePreviewFrame(index)
    if not previewFrames[index] then
        previewFrames[index] = CreatePreviewFrame(index)
    end
    return previewFrames[index]
end

-- Preview role assignments: 2 tanks, 4 healers, 14 DPS.
-- Player (slot 1) uses their real role and counts toward the total.
local previewRoles = {}  -- [1..20] = "TANK"/"HEALER"/"DAMAGER"

previewClassTokens = {}  -- [1..20] class token per slot

local function BuildPreviewRoles()
    -- Clear numeric role assignments but preserve random state (underscore keys)
    for i = 1, 20 do previewRoles[i] = nil end
    wipe(previewClassTokens)

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = EllesmereUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
    end
    previewRoles[1] = playerRole
    local _, pct = UnitClass("player")
    previewClassTokens[1] = pct or "WARRIOR"

    -- EUI LEGENDS: slots 2-20 come from the permanent named roster (event
    -- winners + team) -- fixed name/class/role triples instead of the old
    -- round-robin class pools. ns._pvNames rides along through the sort.
    --
    -- The Holy Paladin problem (user design): of the four hpal Legends, TWO
    -- stay Holy Paladins and TWO re-roll to a random non-paladin DPS class
    -- (names kept). Rolled once per preview session -- the pick lives on
    -- previewRoles so it resets exactly with the other random picks.
    if not previewRoles._hpalPick then
        local hpals = {}
        for ri = 1, #ns._PV_ROSTER do
            if ns._PV_ROSTER[ri].hpal then hpals[#hpals + 1] = ri end
        end
        for i = #hpals, 2, -1 do
            local j = math.random(i)
            hpals[i], hpals[j] = hpals[j], hpals[i]
        end
        local pick = {}
        for k = 3, #hpals do
            local pool = {}
            for _, c in ipairs(ns._PV_DPS_CLASSES) do
                if c ~= "PALADIN" then pool[#pool + 1] = c end
            end
            pick[hpals[k]] = pool[math.random(#pool)]
        end
        previewRoles._hpalPick = pick
    end
    ns._pvNames = ns._pvNames or {}
    ns._pvNames[1] = nil  -- slot 1 = the player's real name
    for i = 2, 20 do
        local e = ns._PV_ROSTER[i - 1]
        local role, class = e.role, e.class
        local reroll = previewRoles._hpalPick[i - 1]
        if reroll then
            role, class = "DAMAGER", reroll
        end
        previewRoles[i] = role
        previewClassTokens[i] = class
        ns._pvNames[i] = e.name
    end

    -- Sort within each group based on sort settings
    local sortMode = db.profile.sortMode or "INDEX"
    -- Self ordering pins the player first (or last). Separated mode moves the
    -- player within each preview group; merged mode flows the whole grid in
    -- one sort, which the per-group preview approximates with the player at
    -- the first cell. showSelfFirst here means "self ordering active";
    -- selfLast picks the end.
    local selfLast = db.profile.showSelfLast
    local showSelfFirst = db.profile.showSelfFirst or db.profile.showSelfLast
    -- Same gate as the live headers: FrameSort's list wins only while it is loaded.
    local prioritizeClass = db.profile.prioritizeClass == true
        and not (sortMode == "FRAMESORT" and ns._FrameSortApi())
    previewRoles._playerSlot = 1  -- default: player is slot 1

    if sortMode == "ROLE" or showSelfFirst or prioritizeClass then
        for g = 0, 3 do
            local base = g * 5
            -- Build sortable list for this group
            local group = {}
            for u = 1, 5 do
                local idx = base + u
                group[u] = {
                    role = previewRoles[idx],
                    classToken = previewClassTokens[idx],
                    name = ns._pvNames and ns._pvNames[idx],
                    isPlayer = (idx == 1),
                    idx = u,
                }
            end

            if prioritizeClass then
                -- Mirror the live order (the CLASS grouping / ns._BuildRaidClassLists):
                -- role (Sort By = Role) -> class -> name; Self Position below.
                local sortByRole = (sortMode == "ROLE")
                local pName = UnitName("player") or ""
                local rolePri = {}
                for pri, role in ipairs(db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }) do
                    rolePri[role] = pri
                end
                local classPri = {}
                for pri, c in ipairs(db.profile.classOrder or ns._GetDefaultClassOrder()) do
                    classPri[c] = pri
                end
                table.sort(group, function(a, b)
                    if sortByRole then
                        local ra, rb = rolePri[a.role] or 99, rolePri[b.role] or 99
                        if ra ~= rb then return ra < rb end
                    end
                    local ca, cb = classPri[a.classToken] or 99, classPri[b.classToken] or 99
                    if ca ~= cb then return ca < cb end
                    -- Slot 1 (the player) carries no preview name.
                    local na, nb = a.name or pName, b.name or pName
                    if na ~= nb then return na < nb end
                    return a.idx < b.idx
                end)
            elseif sortMode == "ROLE" then
                local roleOrder = db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
                local rolePriority = {}
                for pri, role in ipairs(roleOrder) do
                    rolePriority[role] = pri
                end
                -- Stable sort by role priority
                local tmpGroup = {}
                for pri, role in ipairs(roleOrder) do
                    for _, entry in ipairs(group) do
                        if entry.role == role then
                            tmpGroup[#tmpGroup + 1] = entry
                        end
                    end
                end
                -- Any roles not in roleOrder (shouldn't happen, but safe)
                for _, entry in ipairs(group) do
                    if not rolePriority[entry.role] then
                        tmpGroup[#tmpGroup + 1] = entry
                    end
                end
                group = tmpGroup
            end

            if showSelfFirst then
                local playerPos
                for i, entry in ipairs(group) do
                    if entry.isPlayer then playerPos = i; break end
                end
                if playerPos then
                    if selfLast and playerPos < #group then
                        local playerEntry = table.remove(group, playerPos)
                        group[#group + 1] = playerEntry
                    elseif not selfLast and playerPos > 1 then
                        local playerEntry = table.remove(group, playerPos)
                        tinsert(group, 1, playerEntry)
                    end
                end
            end

            -- Write back sorted data
            for u = 1, 5 do
                local idx = base + u
                previewRoles[idx] = group[u].role
                previewClassTokens[idx] = group[u].classToken
                if ns._pvNames then ns._pvNames[idx] = group[u].name end
                if group[u].isPlayer then
                    previewRoles._playerSlot = idx
                end
            end
        end
    end

    -- Random element picks: only randomize once per preview session.
    -- Subsequent calls (from setting changes) reuse the same values.
    if not previewRoles._randomized then
        previewRoles._randomized = true

        -- Pick a random tank for the aggro indicator
        local tanks = {}
        for i = 1, 20 do
            if previewRoles[i] == "TANK" then tanks[#tanks + 1] = i end
        end
        previewRoles._threatIndex = tanks[math.random(#tanks)] or 1

        -- Pick random players for raid markers: 1 in group 1, 1 in group 4
        previewRoles._markerSlot1 = math.random(5)          -- slot 1-5 (group 1)
        previewRoles._markerSlot2 = 15 + math.random(5)     -- slot 16-20 (group 4)

        -- Ready check: 3 not ready, 11 ready, 6 pending (randomized)
        local rcStatuses = {}
        for i = 1, 3 do rcStatuses[#rcStatuses + 1] = "notready" end
        for i = 1, 8 do rcStatuses[#rcStatuses + 1] = "ready" end
        for i = 1, 6 do rcStatuses[#rcStatuses + 1] = "pending" end
        rcStatuses[#rcStatuses + 1] = "summon_pending"
        rcStatuses[#rcStatuses + 1] = "summon_accepted"
        rcStatuses[#rcStatuses + 1] = "summon_declined"
        -- Shuffle
        for i = #rcStatuses, 2, -1 do
            local j = math.random(i)
            rcStatuses[i], rcStatuses[j] = rcStatuses[j], rcStatuses[i]
        end
        -- Clear readycheck/summon on marker slots so they don't overlap
        local ms1, ms2 = previewRoles._markerSlot1, previewRoles._markerSlot2
        if ms1 then rcStatuses[ms1] = nil end
        if ms2 then rcStatuses[ms2] = nil end
        previewRoles._readyCheck = rcStatuses

        -- Dispel types: one of each in group 1 (slots 1-5)
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        local dispelMap = {}
        for i, dt in ipairs(dispelTypes) do
            dispelMap[i] = dt
        end
        previewRoles._dispelMap = dispelMap

        -- Dead/offline/rez: one of each, random non-player slots. Two of them are
        -- corpses -- a plain dead body and a separate one that's being resurrected --
        -- so the showcase shows both states side by side.
        local statePool = {}
        for i = 2, 20 do statePool[#statePool + 1] = i end
        for i = #statePool, 2, -1 do
            local j = math.random(i)
            statePool[i], statePool[j] = statePool[j], statePool[i]
        end
        previewRoles._deadSlot    = statePool[1]  -- plain corpse
        previewRoles._offlineSlot = statePool[2]
        previewRoles._rezSlot     = statePool[3]  -- corpse with an incoming-rez icon
        -- Plain dead + offline bodies carry no readycheck/summon icon (looks wrong there).
        if rcStatuses[statePool[1]] then rcStatuses[statePool[1]] = nil end
        if rcStatuses[statePool[2]] then rcStatuses[statePool[2]] = nil end
        -- The rez corpse gets the incoming-rez icon. But markers win the shared icon
        -- slot (same as the readycheck de-confliction above): if the rez slot landed
        -- on a marker slot, skip the icon (the frame is still shown as a dead body).
        if statePool[3] ~= ms1 and statePool[3] ~= ms2 then
            rcStatuses[statePool[3]] = "rez"
        else
            rcStatuses[statePool[3]] = nil
        end
    end
end

ns.previewAbsorbValues = ns.previewAbsorbValues or {}
local previewHealthValues = {}
local previewPowerValues = {}
ns.previewHealAbsorbValues = {}

local function ApplyPreviewData(f, index)
    -- The main raid preview is a base "20 Man" mockup: RefreshPreview lays out from the
    -- base frameWidth and CreatePreviewFrame sizes from it too, so per-button sizing here
    -- must also read the base profile. ns._scaledProfile would return the active raid-size
    -- tier override for frameWidth, freezing buttons at override size while layout used
    -- base width (the 20 Man Width slider would re-space without resizing whenever a
    -- custom raid size was active). Party preview passes its own override via
    -- _previewSettingsOverride. The real-preview effective overlay (when active) resolves
    -- captured keys to panel-closed values and is NOT tier-scaled, so this holds.
    local s = ns._previewSettingsOverride or ns._pvOverlayProxy or db.profile
    local classToken = previewClassTokens[index] or ns._PV_CLASS_TOKENS[((index - 1) % #ns._PV_CLASS_TOKENS) + 1]
    local playerSlot = previewRoles._playerSlot or 1
    local name
    if index == playerSlot then
        name = UnitName("player") or "Player"
        if Ambiguate then name = Ambiguate(name, "short") end
    else
        -- Legends roster names are RAID-preview-only (user directive): the
        -- party preview (which sandwiches this fn with _previewSettingsOverride
        -- set and its own class tokens) keeps the generic name pool.
        local legend = not ns._partyPvActive and not ns._previewSettingsOverride
            and ns._pvNames and ns._pvNames[index]
        name = legend or ns._PV_NAMES[((index - 1) % #ns._PV_NAMES) + 1]
    end
    local healthPct = previewHealthValues[index] or (40 + math.random(60))

    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(h - ns.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0

    local pvInvert = ns.RF_IsInvertedFill(s)

    f:SetSize(w, h)

    -- Health bar height/anchor + Top Name Bar (helper re-anchors health top to
    -- -topBarH; the per-unit power block below re-sets only the height)
    LayoutTopNameBar(s, h, powerH, f._health, f._topNameBar, f._topNameBarBg, f._topNameBarText, f._power)

    -- Health bar
    if f._health then
        f._health:SetStatusBarTexture(ResolveHealthTexture())
        f._health:GetStatusBarTexture():SetHorizTile(false)
        ns.RF_ApplyHealthOrientation(f._health, s)
        f._health:SetMinMaxValues(0, 100)
        -- Preview: honor invert setting by flipping the displayed fill percentage
        local healthBarPct = healthPct
        if pvInvert then healthBarPct = 100 - healthBarPct end
        f._health:SetValue(healthBarPct)
        f._healthPct = healthPct
        f._classToken = classToken

        local mode = s.healthColorMode or "class"
        local fillTex = f._health:GetStatusBarTexture()
        if mode == "dark" then
            local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
            f._health:SetStatusBarColor(dfr, dfg, dfb, 1)
            if fillTex then fillTex:SetAlpha(dfa) end
        elseif mode == "classic" then
            if fillTex then fillTex:SetAlpha(1) end
            local pct = healthPct / 100
            local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
            local g = pct > 0.5 and 1 or (pct * 2)
            f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
        elseif mode == "customDynamic" then
            if fillTex then fillTex:SetAlpha(1) end
            local r, g, b = ns.ResolveDynamicColor(s, healthPct / 100)
            f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        elseif mode == "classReactive" then
            if fillTex then fillTex:SetAlpha(1) end
            local r, g, b = ns.ResolveClassReactiveColor(s, classToken, healthPct / 100)
            f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        elseif mode == "custom" then
            if fillTex then fillTex:SetAlpha(1) end
            local c = s.customFillColor
            f._health:SetStatusBarColor(c.r, c.g, c.b, (s.healthBarOpacity or 100) / 100)
        else
            if fillTex then fillTex:SetAlpha(1) end
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._health:SetStatusBarColor(cc.r, cc.g, cc.b, (s.healthBarOpacity or 100) / 100) end
        end
    end

    -- Top Name Bar text (preview unit name + class/custom color)
    if f._topNameBarText and s.topNameBarEnabled then
        local attach = ns.RF_LEVEL_ATTACH[s.levelTextPosition or ns.RF_LEVEL_DEFAULT]
        if attach then
            f._topNameBarText:SetFormattedText(attach[1], ns._RFPreviewLevel(), name)
        else
            f._topNameBarText:SetText(name)
        end
        if (s.topNameBarTextColorMode or "class") == "custom" then
            local c = s.topNameBarTextColor or { r = 1, g = 1, b = 1 }
            f._topNameBarText:SetTextColor(c.r, c.g, c.b)
        else
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._topNameBarText:SetTextColor(cc.r, cc.g, cc.b)
            else f._topNameBarText:SetTextColor(1, 1, 1) end
        end
    end

    -- Background
    if f._bg then
        -- BG covers the missing-health portion only (never behind the fill), so
        -- it hangs off the far side of the fill -- its right edge normally, its
        -- top edge on a vertical bar. Mirrors the live UpdateHealthBg.
        local pvVert = ns.RF_IsVerticalFill(s)
        local function AnchorPreviewBg()
            f._bg:ClearAllPoints()
            if pvVert then
                if pvInvert then
                    f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                else
                    f._bg:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                end
            else
                if pvInvert then
                    f._bg:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
                else
                    f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
            end
        end
        if s.healthColorMode == "dark" then
            AnchorPreviewBg()
            f._bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
        else
            -- Matches the real-frame themed branch + Dark mode. Keeps the preview
            -- a 1:1 replica for reduced-fill-opacity setups.
            AnchorPreviewBg()
            local bgA = (s.bgDarkness or 50) / 100
            local cc = s.bgClassColored and classToken and EllesmereUI.GetClassColor(classToken)
            if cc then
                f._bg:SetColorTexture(cc.r, cc.g, cc.b, bgA)
            else
                local bgc = s.customBgColor or defaults.customBgColor
                f._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgA)
            end
        end
    end

    -- Absorb shield preview (dual clip-frame: backfill + forward)
    if f._absorbBar then
        local absStyle = s.absorbStyle or "none"
        if ns._indicatorsVisible then absStyle = "none"
        elseif ns._testMode then
            if ns._testAbsorbs == false then absStyle = "none"
            elseif ns._testAbsorbs and absStyle == "none" then absStyle = "striped" end
        elseif not ns._absorbsPreviewVisible then absStyle = "none"
        end
        local absorbAmt = ns.previewAbsorbValues[index] or 0
        local fw = f._absorbBar._forward
        -- Absorb Bar (solid bar above the frame): same preview gating as the
        -- shield styles (indicators / test mode / absorbs eyeball).
        local topBar = f._absorbBar._topBar
        if topBar then
            local barPos = ns.GetAbsorbBarPosition(s)
            local barOn = barPos ~= "none"
            if ns._indicatorsVisible then barOn = false
            elseif ns._testMode then
                if ns._testAbsorbs == false then barOn = false end
            elseif not ns._absorbsPreviewVisible then barOn = false
            end
            if barOn and absorbAmt > 0 then
                local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                -- (Party Frames kit: laid out on the kit bar and host, as live.)
                ns.ApplyStripBarLayout(topBar, f._absorbBar, ((f.kit or f._health._euiBarArea) and f._health) or f, barPos, s.absorbBarHeight or 4, nil, nil, s.absorbBarGrowDir or "up")
                topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                topBar:SetValue(absorbAmt)
                topBar:Show()
            else
                topBar:Hide()
            end
        end
        -- Heal Absorb Bar preview (mirrors the Absorb Bar; gated on the heal
        -- absorb preview toggles).
        do
            local healTopBarPv = f._absorbBar._healTopBar
            if healTopBarPv then
                local healBarPos = ns.GetHealAbsorbBarPosition(s)
                local healBarOn = healBarPos ~= "none"
                if ns._indicatorsVisible then healBarOn = false
                elseif ns._testMode then
                    if ns._testHealAbsorbs == false then healBarOn = false end
                elseif not ns._absorbsPreviewVisible then healBarOn = false
                end
                local haAmtPv = ns.previewHealAbsorbValues[index] or 0
                if healBarOn and haAmtPv > 0 then
                    local hbc = s.healAbsorbBarColor or { r = 200/255, g = 29/255, b = 29/255 }
                    ns.ApplyStripBarLayout(healTopBarPv, f._absorbBar, ((f.kit or f._health._euiBarArea) and f._health) or f, healBarPos, s.healAbsorbBarHeight or 4, ns.GetAbsorbBarPosition(s), s.absorbBarHeight or 4, s.healAbsorbBarGrowDir or "up")
                    healTopBarPv:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healTopBarPv:SetValue(haAmtPv)
                    healTopBarPv:Show()
                else
                    healTopBarPv:Hide()
                end
            end
        end
        if absStyle ~= "none" and absorbAmt > 0 then
            local modern = (absStyle == "blizzardModern")
            local tex = ns.ResolveAbsorbStyleTex(absStyle, "Interface\\Buttons\\WHITE8X8")
            local alpha = (s.absorbOpacity or 90) / 100
            local tiled = (absStyle == "striped" or absStyle == "stripedReversed" or absStyle == "stripedThick" or absStyle == "stripedThickR" or absStyle == "largeStripes" or absStyle == "largeStripesR" or absStyle == "largeOutlinedStripes" or absStyle == "largeOutlinedStripesR" or absStyle == "pixelsShieldFill")
            -- (the Party Frames kit's health bar is its own rect)
            local hpW = f.kitG and f.kitG.health.w or w
            local hpH = f.kitG and f.kitG.health.h or healthH
            local mask = f._absorbBar._mask
            local ac = s.absorbColor or { r = 1, g = 1, b = 1 }

            f._absorbBar:SetWidth(hpW)
            f._absorbBar:SetHeight(hpH)
            if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end

            if modern then
                -- Forward = modern texture; backfill = flat 10% white overshield (mirrors live).
                if fw then ns.ApplyModernAbsorbBar(fw, mask) end
                ns.HideModernAbsorbBase(f._absorbBar)
                f._absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                f._absorbBar:SetStatusBarColor(1, 1, 1, 0.10)
                local bfFill = f._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(false); bfFill:SetVertTile(false)
                    if mask then bfFill:AddMaskTexture(mask) end
                end
            else
                ns.HideModernAbsorbBase(f._absorbBar)
                if fw then ns.HideModernAbsorbBase(fw) end

                -- Apply style to backfill bar
                f._absorbBar:SetStatusBarTexture(tex)
                f._absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
                local bfFill = f._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(tiled)
                    bfFill:SetVertTile(tiled)
                    if mask then bfFill:AddMaskTexture(mask) end
                end

                -- Apply style to forward bar
                if fw then
                    fw:SetStatusBarTexture(tex)
                    fw:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
                    local fwFill = fw:GetStatusBarTexture()
                    if fwFill then
                        fwFill:SetDrawLayer("ARTWORK", 1)
                        fwFill:SetHorizTile(tiled)
                        fwFill:SetVertTile(tiled)
                        if mask then fwFill:AddMaskTexture(mask) end
                    end
                end
            end

            -- Feed both bars with the same absorb value; clip frames do the visual math.
            -- Mirror the live Show Overshield gate: when off (overlay-like modes) feed
            -- the backfill 0 so the overshield does not render in the preview.
            local pvOsm = s.overshieldMode
            if pvOsm == nil then pvOsm = (s.showOvershield == false) and "never" or "always" end
            local pvOvershieldOn = pvOsm ~= "never"
            local pvOverlayLike = modern or (s.absorbEdgeMode or "overlay") == "overlay"
            local pvAbValue = (not pvOvershieldOn and pvOverlayLike) and 0 or absorbAmt
            f._absorbBar:SetMinMaxValues(0, 100)
            f._absorbBar:SetValue(pvAbValue)
            f._absorbBar:Show()
            if fw then
                fw:SetMinMaxValues(0, 100)
                fw:SetValue(absorbAmt)
                fw:Show()
            end

            -- Blizzard Glow Line (mirrors live, placements included; preview values are plain
            -- numbers, so overshield is a normal compare instead of isClamped). Unset follows
            -- the style: on for Default Blizz Frames only. Vertical fill hides it (see live).
            local pvGlowVert = ns.RF_IsVerticalFill(s)
            if modern and fw and not pvGlowVert then
                local fmb = fw._modernBase
                if fmb then fmb:SetAllPoints(fw:GetStatusBarTexture()) end
            end
            local pvGlowSet = s.absorbGlowLine
            local pvEm = s.absorbEdgeMode or "overlay"
            if (pvGlowSet == true or (pvGlowSet == nil and modern)) and fw and not pvGlowVert
                and (modern or pvEm ~= "left") then
                local ge
                if modern then ge = 1
                elseif pvEm == "overlay" then ge = (pvOsm == "fromleft") and 2 or 1
                elseif pvEm == "right" then ge = 5
                else ge = 3 end
                local bft = f._absorbBar:GetStatusBarTexture()
                local previewOver = absorbAmt > (100 - (healthPct or 100))
                local g, sp = fw._edgeGate, fw._edgeSpark
                if g and sp then
                    g:SetHeight(hpH)
                    g:ClearAllPoints()
                    if ge >= 3 then
                        g:SetPoint("CENTER", bft, "LEFT", -1, 0)
                    else
                        g:SetPoint("CENTER", fw, "LEFT", -1, 0)
                    end
                    g:SetValue(absorbAmt)
                    sp:SetAllPoints(g:GetStatusBarTexture())
                    local spOn = true
                    if ge <= 2 then spOn = not previewOver elseif ge == 5 then spOn = previewOver end
                    sp:SetAlpha(spOn and 1 or 0)
                    sp:Show()
                end
                local bsp = fw._bfSpark
                if bsp then
                    if ge <= 2 then
                        bsp:SetSize(16, hpH)
                        bsp:ClearAllPoints()
                        if not pvOvershieldOn then
                            bsp:SetPoint("CENTER", f._absorbBar, "RIGHT", -1, 0)
                        elseif ge == 2 then
                            bsp:SetPoint("CENTER", bft, "RIGHT", 1, 0)
                        else
                            bsp:SetPoint("CENTER", bft, "LEFT", -1, 0)
                        end
                        bsp:SetAlpha(previewOver and 1 or 0)
                        bsp:Show()
                    else
                        bsp:Hide()
                    end
                end
            elseif fw and fw._edgeSpark then
                fw._edgeSpark:Hide()
                if fw._bfSpark then fw._bfSpark:Hide() end
            end
        else
            f._absorbBar:Hide()
            if fw then fw:Hide() end
            ns.HideModernAbsorbBase(f._absorbBar)
            if fw then ns.HideModernAbsorbBase(fw) end
            if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
            if fw and fw._bfSpark then fw._bfSpark:Hide() end
        end
        -- Position clip frames + backfill based on shield absorb placement
        -- (mirrors the live ReanchorAbsorbToFill).
        local cc = f._absorbBar._curClip
        local mc = f._absorbBar._missClip
        if cc and mc and f._health then
            local absorbMode = s.absorbEdgeMode or "overlay"
            -- Overlay Reverse (Full): Overlay Reverse plus the origin-edge forward bar for the
            -- excess (mirrors live; Default Blizz Frames keeps plain Overlay Reverse).
            local pvOrFull = absorbMode == "overlayReverseFull" and s.absorbStyle ~= "blizzardModern"
            -- Vertical fill: same layout with the axis swapped (the fill's right
            -- edge becomes its top edge). Mirrors the live vertical branch.
            local pvAbVert = ns.RF_IsVerticalFill(s)
            local hpA, hpB = ns.RF_HpEdge(pvAbVert, pvInvert)
            local pvAxisBars = { f._absorbBar, fw }
            for i = 1, 2 do
                local b = pvAxisBars[i]
                if b then
                    b:SetOrientation(pvAbVert and "VERTICAL" or "HORIZONTAL")
                    ns.RF_ApplyFillRotation(b)
                end
            end
            if pvAbVert then
                local vfill = f._health:GetStatusBarTexture()
                if absorbMode == "right" or absorbMode == "left" then
                    cc:ClearAllPoints()
                    cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    f._absorbBar:ClearAllPoints()
                    if absorbMode == "left" then
                        f._absorbBar:SetReverseFill(false)
                        f._absorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._absorbBar:SetReverseFill(true)
                        f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    end
                    if fw then fw:Hide() end
                elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
                    -- Whole absorb fills DOWN into the fill from its top edge;
                    -- the filled-region clip masks excess (mirrors live). Full
                    -- draws that excess through the forward bar instead.
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:ClearAllPoints()
                    f._absorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                    f._absorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    if pvOrFull then
                        mc:ClearAllPoints()
                        mc:SetPoint("BOTTOMLEFT", vfill, hpA, 0, 0)
                        mc:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    elseif fw then
                        fw:Hide()
                    end
                else
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    mc:ClearAllPoints()
                    mc:SetPoint("BOTTOMLEFT", vfill, hpA, 0, -1)
                    mc:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:ClearAllPoints()
                    local pvOsm2 = s.overshieldMode
                    if pvOsm2 == nil then pvOsm2 = (s.showOvershield == false) and "never" or "always" end
                    if pvOsm2 == "fromleft" and s.absorbStyle ~= "blizzardModern" then
                        f._absorbBar:SetReverseFill(false)
                        f._absorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    else
                        f._absorbBar:SetReverseFill(true)
                        f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    end
                end
                if fw then
                    fw:ClearAllPoints()
                    if pvOrFull then
                        fw:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        fw:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        fw:SetPoint("BOTTOMLEFT", vfill, hpA, 0, 0)
                        fw:SetPoint("BOTTOMRIGHT", vfill, hpB, 0, 0)
                    end
                end
            elseif absorbMode == "right" or absorbMode == "left" then
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                f._absorbBar:ClearAllPoints()
                if absorbMode == "left" then
                    f._absorbBar:SetReverseFill(false)
                    f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
                if fw then fw:Hide() end
            elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
                -- Whole absorb backfills from the fill's leading edge INTO the
                -- fill; the filled-region clip masks excess (mirrors live). Full
                -- draws that excess through the forward bar instead.
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                f._absorbBar:SetReverseFill(true)
                f._absorbBar:ClearAllPoints()
                f._absorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                f._absorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                if pvOrFull then
                    mc:ClearAllPoints()
                    mc:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                    mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                elseif fw then
                    fw:Hide()
                end
            else
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                mc:ClearAllPoints()
                mc:SetPoint("TOPLEFT", fill, hpA, -1, 0)
                mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                -- Overlay backfill: overshield "From Left" mirrors the live
                -- anchors (fill-edge + forward fill); else the classic
                -- right-anchored reverse fill.
                f._absorbBar:ClearAllPoints()
                local pvOsm2 = s.overshieldMode
                if pvOsm2 == nil then pvOsm2 = (s.showOvershield == false) and "never" or "always" end
                if pvOsm2 == "fromleft" and s.absorbStyle ~= "blizzardModern" then
                    f._absorbBar:SetReverseFill(false)
                    f._absorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                else
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
            end
            -- Restore the forward bar's horizontal anchors (the vertical branch
            -- above re-points it, and these are otherwise only set at creation).
            if not pvAbVert and fw then
                local hfill = f._health:GetStatusBarTexture()
                fw:ClearAllPoints()
                if pvOrFull then
                    fw:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    fw:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    fw:SetPoint("TOPLEFT", hfill, hpA, 0, 0)
                    fw:SetPoint("BOTTOMLEFT", hfill, hpB, 0, 0)
                end
            end
        end
    end

    -- Heal absorb preview
    if f._healAbsorbBar then
        local haStyle = s.healAbsorbStyle or "clean"
        if ns._indicatorsVisible then haStyle = "none"
        elseif ns._testMode then
            if ns._testHealAbsorbs == false then haStyle = "none"
            elseif ns._testHealAbsorbs and haStyle == "none" then haStyle = "clean" end
        elseif not ns._absorbsPreviewVisible then haStyle = "none"
        end
        local haAmt = ns.previewHealAbsorbValues[index] or 0
        if haStyle ~= "none" and haAmt > 0 then
            local haTex = ns.ResolveAbsorbStyleTex(haStyle, "Interface\\Buttons\\WHITE8X8")
            local haAlpha = (s.healAbsorbOpacity or 75) / 100
            local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            if haStyle == "healBlizzModern" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
            local tiled = (haStyle == "striped" or haStyle == "stripedReversed" or haStyle == "stripedThick" or haStyle == "stripedThickR" or haStyle == "largeStripes" or haStyle == "largeStripesR" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" or haStyle == "pixelsShieldFill")
            local hpW = f.kitG and f.kitG.health.w or w
            local hpH = f.kitG and f.kitG.health.h or healthH
            local mask = f._healAbsorbBar._mask
            f._healAbsorbBar:SetStatusBarTexture(haTex)
            f._healAbsorbBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, haAlpha)
            f._healAbsorbBar:SetWidth(hpW)
            f._healAbsorbBar:SetHeight(hpH)
            local haFillPv = f._healAbsorbBar:GetStatusBarTexture()
            if haFillPv then
                haFillPv:SetDrawLayer("ARTWORK", 2)
                haFillPv:SetHorizTile(tiled)
                haFillPv:SetVertTile(tiled)
                if mask then haFillPv:AddMaskTexture(mask) end
            end
            f._healAbsorbBar:SetMinMaxValues(0, 100)
            f._healAbsorbBar:SetValue(haAmt)
            f._healAbsorbBar:Show()
            local hbg = f._healAbsorbBar._bg
            if hbg then
                hbg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 25) / 100)
                hbg:SetAllPoints(f._healAbsorbBar:GetStatusBarTexture())
                hbg:Show()
            end
        else
            f._healAbsorbBar:Hide()
        end
        -- Heal absorb placement (independent of shield absorb; mirrors live).
        if f._health then
            local healMode = s.healAbsorbEdgeMode or "overlay"
            -- Vertical fill: same layout, axis swapped (mirrors the live branch).
            local pvHaVert = ns.RF_IsVerticalFill(s)
            local hpA, hpB = ns.RF_HpEdge(pvHaVert, pvInvert)
            f._healAbsorbBar:SetOrientation(pvHaVert and "VERTICAL" or "HORIZONTAL")
            ns.RF_ApplyFillRotation(f._healAbsorbBar)
            if pvHaVert then
                local vfill = f._health:GetStatusBarTexture()
                if f._healClip then
                    f._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._healClip:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        f._healClip:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    end
                end
                f._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                elseif healMode == "left" then
                    f._healAbsorbBar:SetReverseFill(false)
                    f._healAbsorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                else
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                end
            else
                if f._healClip then
                    f._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), hpB, 0, 0)
                    end
                end
                f._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                elseif healMode == "left" then
                    f._healAbsorbBar:SetReverseFill(false)
                    f._healAbsorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    local fill = f._health:GetStatusBarTexture()
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                end
            end
        end
    end

    -- Heal prediction preview
    if f._healPredBar then
        local predAmt = ns.previewHealPredValues and ns.previewHealPredValues[index] or 0
        local wantPred = s.healPrediction
        if ns._indicatorsVisible then wantPred = false
        elseif ns._testMode and ns._testHealPrediction ~= nil then wantPred = ns._testHealPrediction end
        if wantPred and predAmt > 0 then
            local pc = s.healPredColor or { r = 102/255, g = 243/255, b = 102/255 }
            local pAlpha = (s.healPredOpacity or 75) / 100
            f._healPredBar:SetStatusBarColor(pc.r, pc.g, pc.b, pAlpha)
            f._healPredBar:SetWidth(f.kitG and f.kitG.health.w or w)
            f._healPredBar:SetHeight(f.kitG and f.kitG.health.h or healthH)
            -- Grows from the HP edge into the missing health: the fill's right
            -- edge normally, its top edge on a vertical bar. Only set at creation
            -- otherwise, so both axes are re-applied here.
            do
                local pvPredVert = ns.RF_IsVerticalFill(s)
                local pFill = f._health and f._health:GetStatusBarTexture()
                f._healPredBar:SetOrientation(pvPredVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(f._healPredBar)
                if pFill then
                    local hpA, hpB = ns.RF_HpEdge(pvPredVert, pvInvert)
                    f._healPredBar:ClearAllPoints()
                    if pvPredVert then
                        f._healPredBar:SetPoint("BOTTOMLEFT", pFill, hpA, 0, 0)
                        f._healPredBar:SetPoint("BOTTOMRIGHT", pFill, hpB, 0, 0)
                    else
                        f._healPredBar:SetPoint("TOPLEFT", pFill, hpA, 0, 0)
                        f._healPredBar:SetPoint("BOTTOMLEFT", pFill, hpB, 0, 0)
                    end
                end
            end
            f._healPredBar:SetMinMaxValues(0, 100)
            f._healPredBar:SetValue(predAmt)
            f._healPredBar:Show()
        else
            f._healPredBar:Hide()
        end
    end

    -- Reduced max health preview
    if f._reducedMaxHealthBar then
        local rmhAmt = ns.previewReducedMaxHealth and ns.previewReducedMaxHealth[index] or 0
        local rmhStyle = s.maxHealthStyle or "maxHealthStripes"
        -- Show in the Full Preview (Reduced Max Health test toggle) AND in the
        -- Absorbs-section preview (the shield-effects eye), mirroring Heal Absorb.
        local rmhShow = ns._testReducedMaxHealth
            or (not ns._testMode and not ns._indicatorsVisible and ns._absorbsPreviewVisible)
        if rmhShow and rmhAmt > 0 and rmhStyle ~= "none" then
            ns.ApplyMaxHealthStyle(f._reducedMaxHealthBar, rmhStyle, s)
            do  -- eats the far end of the bar: the right edge, or the top when vertical
                local pvRmhVert = ns.RF_IsVerticalFill(s)
                f._reducedMaxHealthBar:SetOrientation(pvRmhVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(f._reducedMaxHealthBar)
            end
            f._reducedMaxHealthBar:SetValue(rmhAmt)
            local rmhBg = f._reducedMaxHealthBg
            if rmhBg then
                rmhBg:SetColorTexture(0, 0, 0, (s.maxHealthBgOpacity or 100) / 100)
                rmhBg:SetAllPoints(f._reducedMaxHealthBar:GetStatusBarTexture())
            end
            f._reducedMaxHealthBar:Show()
        else
            f._reducedMaxHealthBar:Hide()
        end
    end

    -- Power (filtered by role, hidden if class has no power)
    local role = previewRoles[index] or "DAMAGER"
    local showForRole = (role == "HEALER" and s.powerShowForHealer)
        or (role == "TANK" and s.powerShowForTank)
        or (role == "DAMAGER" and s.powerShowForDPS)
    local hidePower = powerH <= 0 or not showForRole
    -- Party Frames kit: the stock mana bar always shows (the kit pass sizes it).
    if f.kitG then hidePower = false end

    if f._power then
        if not hidePower then
            f._power:SetHeight(powerH)
            f._power:SetStatusBarTexture(ResolveHealthTexture())
            f._power:GetStatusBarTexture():SetHorizTile(false)
            local pwPct = previewPowerValues[index] or (60 + math.random(40))
            f._power:SetMinMaxValues(0, 100)
            f._power:SetValue(pwPct)
            f._powerPct = pwPct
            local pwToken = EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA"
            local pc = EllesmereUI.GetPowerColor(pwToken)
            if pc then
                f._power:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
            else
                f._power:SetStatusBarColor(0, 0.5, 1, 1)
            end
            f._power:Show()
        else
            f._power:Hide()
        end
    end

    -- Expand health to full frame when power is hidden (still reserving the Top
    -- Name Bar's height from the top; its anchor was set by LayoutTopNameBar)
    if f._health then
        if hidePower then
            f._health:SetHeight(h - topBarH)
        else
            f._health:SetHeight(healthH - topBarH)
        end
    end

    if f._powerBg then
        if hidePower then
            f._powerBg:Hide()
        else
            local bgc = EllesmereUI.GetPowerColor and s.powerBgPowerColored
                and EllesmereUI.GetPowerColor(EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA")
            local pf = bgc and EllesmereUI.GetPowerBgDarkenFactor() or 1
            bgc = bgc or s.powerBgColor
            f._powerBg:SetColorTexture(((bgc or {}).r or 0) * pf, ((bgc or {}).g or 0) * pf, ((bgc or {}).b or 0) * pf, (s.powerBgDarkness or 70) / 100)
            f._powerBg:Show()
        end
    end

    -- Power border (Classic WoW UI: the stock divider stands in, drawn with
    -- the frame border below)
    if f._powerBorder and PP then
        if hidePower or f.stockDiv or f.kitG then
            f._powerBorder:Hide()
        else
            local pbStyle = s.powerBorderStyle or "eui"
            if pbStyle == "eui" then
                PP.UpdateBorder(f._powerBorder, 1, 1, 1, 1, 0.2)
                f._powerBorder:Show()
                local ppC = PP.GetBorders(f._powerBorder)
                if ppC then
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                    if ppC._top then ppC._top:SetAlpha(0.2) end
                end
            else
                local pbSize = s.powerBorderSize or 1
                if pbSize <= 0 then
                    f._powerBorder:Hide()
                else
                    local pbc = s.powerBorderColor
                    local pba = s.powerBorderAlpha or 1
                    PP.UpdateBorder(f._powerBorder, pbSize, pbc.r, pbc.g, pbc.b, pba)
                    f._powerBorder:Show()
                    local ppC = PP.GetBorders(f._powerBorder)
                    if ppC then
                        if pbStyle == "divider" then
                            if ppC._bottom then ppC._bottom:SetAlpha(0) end
                            if ppC._left then ppC._left:SetAlpha(0) end
                            if ppC._right then ppC._right:SetAlpha(0) end
                            if ppC._top then ppC._top:SetAlpha(pba) end
                        else
                            if ppC._top then ppC._top:SetAlpha(pba) end
                            if ppC._bottom then ppC._bottom:SetAlpha(pba) end
                            if ppC._left then ppC._left:SetAlpha(pba) end
                            if ppC._right then ppC._right:SetAlpha(pba) end
                        end
                    end
                end
            end
        end
    end

    -- Border (style/size/texture/offsets via ApplyBorderStyle, then state recolor)
    if f._border and PP and f.kit then
        -- Party Frames kit: the art stands in for the border.
        f._border:SetFrameLevel(f:GetFrameLevel() + 8)
        EllesmereUI.ApplyBorderStyle(f._border, 0, 0, 0, 0, 0, "solid")
        f._border._hlBorderSize = nil
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    elseif f._border and PP and f.stockEdge then
        f._border:SetFrameLevel(f:GetFrameLevel() + 8)
        EllesmereUI.ApplyBorderStyle(f._border, 0, 0, 0, 0, 0, "solid")
        f._border._hlBorderSize = nil
        ns.RF_StockSeat(f)
        if f.stockDiv and f._power and f._power:IsShown() then ns.RF_StockDivider(f) end
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    elseif f._border and PP then
        local bs = s.borderSize or 1
        local bc = s.borderColor or { r = 0, g = 0, b = 0 }
        local pl = f:GetFrameLevel()
        f._border:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        EllesmereUI.ApplyBorderStyle(f._border, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
            s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
            s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs, nil,
            EllesmereUI.BorderPx(s.borderSizePx, bs, s.borderTexture or "solid"))
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    end

    -- Indicators visibility (eyeball toggle)
    local indVis = ns._indicatorsVisible ~= false

    -- Threat border (always visible in test mode, otherwise requires animation).
    -- Color Custom Borders recolors the frame border instead of drawing this one
    -- (PvApplyBorderColor), so the slider size does not gate it.
    if f._threatFrame and PP then
        local bs = s.threatBorderSize or 0
        local rc = s.threatCustomBorder == true and ns.RF_CustomBorderOn(s)
        local wantThreat = bs > 0 or rc
        if ns._testMode and ns._testThreat ~= nil then wantThreat = ns._testThreat end
        local showThreat = wantThreat and (ns._testMode or ns._healthAnimActive) and previewRoles._threatIndex == index
        local agg
        if f.stockHl then
            f._threatFrame:Hide()
            ns.RF_StockAggro(f, showThreat and 3 or nil)
        elseif showThreat and not rc then
            PP.UpdateBorder(f._threatFrame, bs > 0 and bs or 1, 1, 0, 0, 1)
            f._threatFrame:Show()
        else
            f._threatFrame:Hide()
            agg = (showThreat and rc) and true or nil
        end
        if f._pvAggroBdr ~= agg then
            f._pvAggroBdr = agg
            if f._ApplyBorderColor then f._ApplyBorderColor() end
        end
    end

    -- Dispel visuals (border, overlay, icon)
    local dispVis = ns._dispelsVisible ~= false
    local dispelMap = previewRoles._dispelMap
    local dispelType = dispelMap and dispelMap[index]
    local dispelDC = dispelType and GetDispelColor(dispelType, s)
    -- Color Custom Borders: the border takes the type color (PvApplyBorderColor,
    -- below hover/target and aggro), only over a custom border like the real
    -- frames; a change repaints it, the border pass above ran first.
    do
        local bdrC = dispVis and dispelDC and s.dispelCustomBorder == true
            and (dispelDC.a or 1) > 0 and ns.RF_CustomBorderOn(s) and dispelDC or nil
        if f._pvDispelBdrC ~= bdrC then
            f._pvDispelBdrC = bdrC
            if f._ApplyBorderColor then f._ApplyBorderColor() end
        end
    end
    if dispVis and dispelDC then
        -- Per-type alpha (plain saved value in the preview path)
        local dcA = dispelDC.a or 1
        -- Dispel border (PP.UpdateBorder handles physical pixel sizing internally)
        local dbs = s.dispelBorderSize or 2
        if f._dispelBdrFrame and PP and dbs > 0 then
            PP.UpdateBorder(f._dispelBdrFrame, dbs, dispelDC.r, dispelDC.g, dispelDC.b, dcA)
            f._dispelBdrFrame:Show()
        elseif f._dispelBdrFrame then
            f._dispelBdrFrame:Hide()
        end
        -- Dispel overlay
        local olMode = s.dispelOverlay or "fill"
        if olMode ~= "none" and f._dispelOLTex and f._health then
            local olAlpha = (s.dispelOverlayOpacity or 100) / 100 * dcA
            local olTex = f._dispelOLTex
            olTex:ClearAllPoints()
            -- Reset any prior vertex tint so fill/full render their explicit color cleanly.
            olTex:SetVertexColor(1, 1, 1, 1)
            if olMode == "fill" then
                -- Current health, as on the live frames (the fill, or the rest of
                -- the bar under Inverted Fill), off the bar oriented above.
                ns.RF_AnchorCurHealth(olTex, f._health, f._health:GetStatusBarTexture())
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "full" then
                olTex:SetAllPoints(f._health)
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "gradient" or olMode == "gradient_sharp" then
                -- Same pre-baked gradient textures as the live frames so the preview matches.
                olTex:SetAllPoints(f._health)
                olTex:SetTexture(olMode == "gradient_sharp"
                    and "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"
                    or "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
                olTex:SetVertexColor(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            end
            olTex:Show()
        elseif f._dispelOLTex then
            f._dispelOLTex:Hide()
        end
        -- Dispel type icon (positioned per setting)
        if s.showDispelIcons and f._dispelIcon and f._dispelIconTex then
            local atlas = DISPEL_ICON_ATLAS[dispelType]
            if atlas then f._dispelIconTex:SetAtlas(atlas) end
            f._dispelIcon:ClearAllPoints()
            local diSz = s.dispelIconSize or 16
            f._dispelIcon:SetSize(diSz, diSz)
            local diPos = s.dispelIconPosition or "center"
            local diOX = s.dispelIconOffsetX or 0
            local diOY = s.dispelIconOffsetY or 0
            -- Dispel icon anchors flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            local diHost = ns.RF_AnchorHost(f._health, s)
            if diPos == "topleft" then
                f._dispelIcon:SetPoint("TOPLEFT", diHost, "TOPLEFT", diOX, diOY)
            elseif diPos == "top" then
                f._dispelIcon:SetPoint("TOP", diHost, "TOP", diOX, diOY)
            elseif diPos == "topright" then
                f._dispelIcon:SetPoint("TOPRIGHT", diHost, "TOPRIGHT", diOX, diOY)
            elseif diPos == "left" then
                f._dispelIcon:SetPoint("LEFT", diHost, "LEFT", diOX, diOY)
            elseif diPos == "right" then
                f._dispelIcon:SetPoint("RIGHT", diHost, "RIGHT", diOX, diOY)
            elseif diPos == "bottomleft" then
                f._dispelIcon:SetPoint("BOTTOMLEFT", diHost, "BOTTOMLEFT", diOX, diOY)
            elseif diPos == "bottom" then
                f._dispelIcon:SetPoint("BOTTOM", diHost, "BOTTOM", diOX, diOY)
            elseif diPos == "bottomright" then
                f._dispelIcon:SetPoint("BOTTOMRIGHT", diHost, "BOTTOMRIGHT", diOX, diOY)
            else -- center
                f._dispelIcon:SetPoint("CENTER", diHost, "CENTER", diOX, diOY)
            end
            f._dispelIcon:Show()
        elseif f._dispelIcon then
            f._dispelIcon:Hide()
        end
    else
        if f._dispelBdrFrame then f._dispelBdrFrame:Hide() end
        if f._dispelOLTex then f._dispelOLTex:Hide() end
        if f._dispelIcon then f._dispelIcon:Hide() end
    end

    -- Static dispel debuff icon (shows a fake debuff matching user's debuff settings)
    if f._pvDispelDebuff then
        if dispVis and dispelType and ns._PV_DISPEL_DB_ICONS[dispelType] then
            local ddi = f._pvDispelDebuff
            -- When dispellable debuffs are routed to their own anchor, the
            -- preview icon follows that location, its offsets and its size.
            local dispSplit = (s.dispellableDebuffLocation or "same") ~= "same"
            local dbSz
            if dispSplit then dbSz = ns.RFC_SnapSize(ns.DispellableDebuffSize(s)) else dbSz = ns.RFC_DebuffSize(s) end
            ddi:SetSize(dbSz, dbSz)
            ddi._tex:SetTexture(ns._PV_DISPEL_DB_ICONS[dispelType])
            local _z = s.debuffIconZoom or 0.08
            ddi._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

            -- Position using debuff settings
            ddi:ClearAllPoints()
            local dbPos, dbOX, dbOY
            if dispSplit then
                dbPos = s.dispellableDebuffLocation
                dbOX = s.dispellableDebuffOffsetX or 0
                dbOY = s.dispellableDebuffOffsetY or 0
            else
                dbPos = s.debuffPosition or "bottomright"
                dbOX = s.debuffOffsetX or 0
                dbOY = s.debuffOffsetY or 0
            end
            local ddHost = ns.RF_AnchorHost(f._health, s)
            if dbPos == "topleft" then
                ddi:SetPoint("TOPLEFT", ddHost, "TOPLEFT", dbOX, dbOY)
            elseif dbPos == "top" then
                ddi:SetPoint("TOP", ddHost, "TOP", dbOX, dbOY)
            elseif dbPos == "topright" then
                ddi:SetPoint("TOPRIGHT", ddHost, "TOPRIGHT", dbOX, dbOY)
            elseif dbPos == "left" then
                ddi:SetPoint("LEFT", ddHost, "LEFT", dbOX, dbOY)
            elseif dbPos == "center" then
                ddi:SetPoint("CENTER", ddHost, "CENTER", dbOX, dbOY)
            elseif dbPos == "right" then
                ddi:SetPoint("RIGHT", ddHost, "RIGHT", dbOX, dbOY)
            elseif dbPos == "bottomleft" then
                ddi:SetPoint("BOTTOMLEFT", ddHost, "BOTTOMLEFT", dbOX, dbOY)
            elseif dbPos == "bottom" then
                ddi:SetPoint("BOTTOM", ddHost, "BOTTOM", dbOX, dbOY)
            else -- bottomright
                ddi:SetPoint("BOTTOMRIGHT", ddHost, "BOTTOMRIGHT", dbOX, dbOY)
            end

            -- Border (dispel-type colored)
            local dbBdrSz = s.debuffBorderSize or 1
            if ddi._borderFrame and PP and dbBdrSz > 0 then
                local dc = GetDispelColor(dispelType, s)
                if dc then
                    PP.UpdateBorder(ddi._borderFrame, dbBdrSz, dc.r, dc.g, dc.b, 1)
                else
                    local bc = s.debuffBorderColor or { r = 0, g = 0, b = 0 }
                    PP.UpdateBorder(ddi._borderFrame, dbBdrSz, bc.r, bc.g, bc.b, 1)
                end
                ddi._borderFrame:Show()
            elseif ddi._borderFrame then
                ddi._borderFrame:Hide()
            end

            if ddi._cooldown then ddi._cooldown:Hide() end
            if ddi._count then ddi._count:SetText("") end
            if ddi._durText then ddi._durText:Hide() end
            ddi:Show()
        else
            f._pvDispelDebuff:Hide()
        end
    end

    -- Hover/target are recolored onto the single border (f._ApplyBorderColor),
    -- applied above with the border style; no separate hover/target frames.

    -- Raid marker (1 random in group 1, 1 random in group 4)
    if f._raidMarker then
        local isMarked = indVis and s.showRaidMarker and
            (index == previewRoles._markerSlot1 or index == previewRoles._markerSlot2)
        if isMarked then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            f._raidMarker:SetSize(rmSz, rmSz)
            -- Use custom marker PNGs
            if index == previewRoles._markerSlot1 then
                f._raidMarker:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\marker.png")
                f._raidMarker:SetTexCoord(0, 1, 0, 1)
            else
                f._raidMarker:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\marker2.png")
                f._raidMarker:SetTexCoord(0, 1, 0, 1)
            end
            -- Anchor based on marker position setting
            f._raidMarker:ClearAllPoints()
            local pos = s.raidMarkerPosition or "center"
            local ox = s.raidMarkerOffsetX or 0
            local oy = s.raidMarkerOffsetY or 0
            local rmHost = ns.RF_AnchorHost(f._health, s)
            if pos == "topleft" then
                f._raidMarker:SetPoint("TOPLEFT", rmHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._raidMarker:SetPoint("TOP", rmHost, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._raidMarker:SetPoint("TOPRIGHT", rmHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._raidMarker:SetPoint("LEFT", rmHost, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._raidMarker:SetPoint("RIGHT", rmHost, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._raidMarker:SetPoint("BOTTOMLEFT", rmHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._raidMarker:SetPoint("BOTTOM", rmHost, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._raidMarker:SetPoint("BOTTOMRIGHT", rmHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._raidMarker:SetPoint("CENTER", rmHost, "CENTER", ox, oy)
            end
            f._raidMarker:Show()
        else
            f._raidMarker:Hide()
        end
    end

    -- WoW Forever: Missing Buffs (EUI_RaidFrames_ForeverMissingBuffs.lua).
    if ns.RF_FvMissingPreview then ns.RF_FvMissingPreview(f, index, s, indVis) end

    -- Ready check icon
    if f._readyCheck then
        local rcStatuses = previewRoles._readyCheck
        local rcStatus = rcStatuses and rcStatuses[index]
        local isSummon = rcStatus and rcStatus:sub(1, 6) == "summon"
        local isRez    = rcStatus == "rez"
        local showRC = indVis and rcStatus and (
            (isRez and s.showIncomingRez) or
            (isSummon and s.showSummonPending) or
            (not isSummon and not isRez and s.showReadyCheck)
        )
        if showRC then
            local rcSz = PixelSnap(s.readyCheckSize or 20)
            f._readyCheck:SetSize(rcSz, rcSz)
            -- Anchor based on ready-check position setting
            f._readyCheck:ClearAllPoints()
            local pos = s.readyCheckPosition or "center"
            local ox = s.readyCheckOffsetX or 0
            local oy = s.readyCheckOffsetY or 0
            local rcHost = ns.RF_AnchorHost(f._health, s)
            if pos == "topleft" then
                f._readyCheck:SetPoint("TOPLEFT", rcHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._readyCheck:SetPoint("TOP", rcHost, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._readyCheck:SetPoint("TOPRIGHT", rcHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._readyCheck:SetPoint("LEFT", rcHost, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._readyCheck:SetPoint("RIGHT", rcHost, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._readyCheck:SetPoint("BOTTOMLEFT", rcHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._readyCheck:SetPoint("BOTTOM", rcHost, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._readyCheck:SetPoint("BOTTOMRIGHT", rcHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._readyCheck:SetPoint("CENTER", rcHost, "CENTER", ox, oy)
            end
            if rcStatus == "ready" then
                f._readyCheck:SetAtlas("UI-LFG-ReadyMark-Raid")
            elseif rcStatus == "notready" then
                f._readyCheck:SetAtlas("UI-LFG-DeclineMark-Raid")
            elseif rcStatus == "pending" then
                f._readyCheck:SetAtlas("UI-LFG-PendingMark-Raid")
            elseif rcStatus == "summon_pending" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonPending")
            elseif rcStatus == "summon_accepted" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonAccepted")
            elseif rcStatus == "summon_declined" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonDeclined")
            elseif rcStatus == "rez" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-Rez")
            end
            f._readyCheck:Show()
        else
            f._readyCheck:Hide()
        end
    end

    -- Name (re-anchor position every refresh, single-point + width constraint)
    if f._nameText then
        -- Text band level: mirrors AnchorNameText on the live buttons ("Show
        -- Above Icons" lifts the carrier over the aura band).
        local pvCarrier = f._nameText:GetParent()
        if pvCarrier and pvCarrier.SetFrameLevel then
            pvCarrier:SetFrameLevel(f:GetFrameLevel()
                + (s.nameTextAboveIcons and (ns.LVL_AURA + 6) or ns.LVL_TEXT))
        end
        f._nameText:ClearAllPoints()
        local pos = s.namePosition or "center"
        if pos == "none" or s.topNameBarEnabled then
            f._nameText:Hide()
        else
        f._nameText:Show()
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        f._nameText:SetWidth((s.frameWidth or 72) * ns.RF_NAME_WIDTH_FRACTION)
        f._nameText:SetHeight(0)
        local ntHost = ns.RF_AnchorHost(f._health, s)
        if pos == "topleft" then
            f._nameText:SetPoint("TOPLEFT", ntHost, "TOPLEFT", 2 + ox, -2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "top" then
            f._nameText:SetPoint("TOP", ntHost, "TOP", ox, -2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("TOP")
        elseif pos == "topright" then
            f._nameText:SetPoint("TOPRIGHT", ntHost, "TOPRIGHT", -2 + ox, -2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "left" then
            f._nameText:SetPoint("LEFT", ntHost, "LEFT", 2 + ox, oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            f._nameText:SetPoint("RIGHT", ntHost, "RIGHT", -2 + ox, oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            f._nameText:SetPoint("BOTTOMLEFT", ntHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            f._nameText:SetPoint("BOTTOM", ntHost, "BOTTOM", ox, 2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            f._nameText:SetPoint("BOTTOMRIGHT", ntHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("BOTTOM")
        else -- center
            f._nameText:SetPoint("CENTER", ntHost, "CENTER", ox, oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        f._nameText:SetText("")
        local attach = ns.RF_LEVEL_ATTACH[s.levelTextPosition or ns.RF_LEVEL_DEFAULT]
        local pvName = ns.RF_FormatName and ns.RF_FormatName(name, s) or name
        if attach then
            f._nameText:SetFormattedText(attach[1], ns._RFPreviewLevel(), ns.CapName(pvName, s))
        else
            f._nameText:SetText(ns.CapName(pvName, s))
        end
        ApplyFont(f._nameText, s.nameSize or 10)
        f._nameText:SetTextColor(ns.RF_PreviewTextColor(s.nameColorMode or "class",
            s.nameCustomColor, classToken, 1, 1, 1))
        end -- pos ~= "none"
    end

    -- Level text on its own spot (preview): the player's level in the name's colour.
    if f._levelText then
        local lpos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
        if lpos == "none" or ns.RF_LEVEL_ATTACH[lpos] then
            f._levelText:Hide()
        else
            ApplyFont(f._levelText, s.levelTextSize or 10)
            ns.AnchorRFText(f._levelText, ns.RF_BarHost(f._health, s), lpos,
                s.levelTextOffsetX or 0, s.levelTextOffsetY or 0)
            f._levelText:SetFormattedText("%d", ns._RFPreviewLevel())
            f._levelText:SetTextColor(ns.RF_PreviewTextColor(s.nameColorMode or "class",
                s.nameCustomColor, classToken, 1, 1, 1))
            f._levelText:Show()
        end
    end

    -- Dead/offline/AFK states (only when indicators eyeball is on). The rez slot is
    -- a second corpse (dimmed, no "DEAD" text) that shows an incoming-rez icon in
    -- place of the status text -- mirrors the live "hide DEAD while rezzing" behavior.
    local isRezCorpse = indVis and index == previewRoles._rezSlot
    local isDead      = indVis and (index == previewRoles._deadSlot or isRezCorpse)
    local isOffline   = indVis and index == previewRoles._offlineSlot
    -- Mark dead/offline preview frames so the animated-preview ticker skips them
    -- (their health bar is emptied and health text hidden -- never animated).
    f._pvHideHealthText = (isDead or isOffline) or nil
    local isAfk     = indVis and index == previewRoles._afkSlot

    -- Health text
    if f._healthText then
        ApplyFont(f._healthText, s.healthTextSize or 9)
        -- Position
        f._healthText:ClearAllPoints()
        local htPos = s.healthTextPosition or "center"
        local htOX = s.healthTextOffsetX or 0
        local htOY = s.healthTextOffsetY or 0
        local htW = f.kitG and f.kitG.health.w or (s.frameWidth or 72) * 0.75
        f._healthText:SetWidth(htW)
        f._healthText:SetHeight(0)
        local htHost = ns.RF_BarHost(f._health, s)
        if htPos == "topleft" then
            f._healthText:SetPoint("TOPLEFT", htHost, "TOPLEFT", 2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "top" then
            f._healthText:SetPoint("TOP", htHost, "TOP", htOX, -2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "topright" then
            f._healthText:SetPoint("TOPRIGHT", htHost, "TOPRIGHT", -2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "left" then
            f._healthText:SetPoint("LEFT", htHost, "LEFT", 2 + htOX, htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "right" then
            f._healthText:SetPoint("RIGHT", htHost, "RIGHT", -2 + htOX, htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "bottomleft" then
            f._healthText:SetPoint("BOTTOMLEFT", htHost, "BOTTOMLEFT", 2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottom" then
            f._healthText:SetPoint("BOTTOM", htHost, "BOTTOM", htOX, 2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottomright" then
            f._healthText:SetPoint("BOTTOMRIGHT", htHost, "BOTTOMRIGHT", -2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("BOTTOM")
        else
            f._healthText:SetPoint("CENTER", htHost, "CENTER", htOX, htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        local htTxt = f._healthText:GetText()
        f._healthText:SetText("")
        f._healthText:SetText(htTxt or "")
        local mode = s.healthTextMode or "none"
        -- Dead and offline sample members keep only the missing amount.
        if (isDead or isOffline) and mode ~= "missing" then mode = "none" end
        if ns.RF_HealthTextInto(f._healthText, mode, healthPct, nil, 12000) then
            -- The preview's classToken stands in for the unit.
            local htr, htg, htb = ns.RF_PreviewTextColor(s.healthTextColorMode or "custom",
                s.healthTextCustomColor, classToken, 1, 1, 1)
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        end
    end

    -- Heal absorb text (preview): a representative value so the user can see
    -- and position it.
    if f._healAbsorbText then
        local haMode = s.healAbsorbTextMode or "none"
        ApplyFont(f._healAbsorbText, s.healAbsorbTextSize or 9)
        ns.AnchorRFText(f._healAbsorbText, ns.RF_BarHost(f._health, s), s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0,
            f.kitG and f.kitG.health.w or (s.frameWidth or 72) * 0.75)
        if haMode ~= "none" and not isDead and not isOffline then
            ns.FormatHealAbsorbInto(f._healAbsorbText, math.floor(healthPct * 3000), haMode)
            local hr, hg, hb = ns.RF_PreviewTextColor(s.healAbsorbTextColorMode or "custom",
                s.healAbsorbTextCustomColor, classToken, 1, 0.3, 0.3)
            f._healAbsorbText:SetTextColor(hr, hg, hb, 0.9)
        else
            f._healAbsorbText:SetText("")
        end
    end

    -- Power text (preview): the sample member's bar value, only where its power bar shows and
    -- (as Health Text) not on the dead or offline sample members.
    -- f._pwtMode / f._pwtPer (mode and made-up amount per percent, nil = hidden) let the
    -- Power Bar section's animated preview keep the text in step with the bar.
    if f._powerText then
        local pwtMode = s.powerTextMode or "none"
        if hidePower or pwtMode == "none" or isDead or isOffline then
            f._powerText:Hide()
            f._pwtMode = nil
        else
            ApplyFont(f._powerText, s.powerTextSize or 8)
            ns.AnchorRFText(f._powerText, ns.RF_BarHost(f._health, s), s.powerTextPosition or "bottom",
                s.powerTextOffsetX or 0, s.powerTextOffsetY or 0,
                f.kitG and f.kitG.health.w or (s.frameWidth or 72) * 0.75)
            local pwtTok = EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA"
            f._pwtPer = (pwtTok == "MANA") and 2500 or 1
            ns.RF_PowerTextInto(f._powerText, pwtMode, f._powerPct or 100, nil, nil, f._pwtPer)
            local pr, pg, pb = ns.RF_PreviewTextColor(s.powerTextColorMode or "custom",
                s.powerTextCustomColor, classToken, 1, 1, 1, pwtTok)
            f._powerText:SetTextColor(pr, pg, pb, 0.9)
            f._powerText:Show()
            f._pwtMode = pwtMode
        end
    end

    -- Status text (DEAD / OFFLINE / AFK)
    if f._statusText then
        local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        ApplyFont(f._statusText, s.statusTextSize or 14)
        f._statusText:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
        f._statusText:ClearAllPoints()
        local stPos = s.statusTextPosition or "center"
        local stOX = s.statusTextOffsetX or 0
        local stOY = s.statusTextOffsetY or 0
        local stHost = ns.RF_BarHost(f._health, s)
        if stPos == "topleft" then
            f._statusText:SetPoint("TOPLEFT", stHost, "TOPLEFT", 2 + stOX, -2 + stOY)
        elseif stPos == "top" then
            f._statusText:SetPoint("TOP", stHost, "TOP", stOX, -2 + stOY)
        elseif stPos == "topright" then
            f._statusText:SetPoint("TOPRIGHT", stHost, "TOPRIGHT", -2 + stOX, -2 + stOY)
        elseif stPos == "left" then
            f._statusText:SetPoint("LEFT", stHost, "LEFT", 2 + stOX, stOY)
        elseif stPos == "right" then
            f._statusText:SetPoint("RIGHT", stHost, "RIGHT", -2 + stOX, stOY)
        elseif stPos == "bottomleft" then
            f._statusText:SetPoint("BOTTOMLEFT", stHost, "BOTTOMLEFT", 2 + stOX, 2 + stOY)
        elseif stPos == "bottom" then
            f._statusText:SetPoint("BOTTOM", stHost, "BOTTOM", stOX, 2 + stOY)
        elseif stPos == "bottomright" then
            f._statusText:SetPoint("BOTTOMRIGHT", stHost, "BOTTOMRIGHT", -2 + stOX, 2 + stOY)
        else
            f._statusText:SetPoint("CENTER", stHost, "CENTER", stOX, stOY)
        end
        if stPos == "none" then
            -- Status text display is turned off
            f._statusText:Hide()
        elseif isRezCorpse then
            -- Being resurrected: the rez icon takes this spot, so no DEAD text.
            f._statusText:Hide()
        elseif isDead then
            f._statusText:SetText(EllesmereUI.L("DEAD"))
            f._statusText:Show()
        elseif isOffline then
            f._statusText:SetText(EllesmereUI.L("OFFLINE"))
            f._statusText:Show()
        elseif isAfk then
            f._statusText:SetText(EllesmereUI.L("AFK"))
            f._statusText:Show()
        else
            -- No status to show
            f._statusText:Hide()
        end
    end

    -- Dead/DC overlay (mirror the live-frame status tint: full-cover bg)
    if isDead then
        if f._health then
            -- Emptied under Inverted Fill too (a full missing-health bar), so the
            -- current-health area the dispel wash covers stays empty, as live.
            f._health:SetValue(pvInvert and 100 or 0)
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if f._bg then
            local c = s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 }
            f._bg:ClearAllPoints(); f._bg:SetAllPoints(f._health)
            f._bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
        -- Hide shield on dead players
        if f._absorbBar then
            f._absorbBar:Hide()
            if f._absorbBar._forward then f._absorbBar._forward:Hide() end
            if f._absorbBar._topBar then f._absorbBar._topBar:Hide() end
        end
    elseif isOffline then
        if f._health then
            f._health:SetValue(pvInvert and 100 or 0)  -- see the dead branch
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if f._bg then
            local c = s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 }
            f._bg:ClearAllPoints(); f._bg:SetAllPoints(f._health)
            f._bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
    end

    -- Role icon (not affected by indicators toggle)
    if f._roleIcon then
        local style = s.roleIconStyle or "modern"
        if style ~= "none" then
            local role = previewRoles[index] or "DAMAGER"
            local showForRole = (role == "TANK" and s.showRoleForTank)
                or (role == "HEALER" and s.showRoleForHealer)
                or (role == "DAMAGER" and s.showRoleForDPS)
            if showForRole ~= false and ApplyRoleIcon(f._roleIcon, role, style) then
                local riSz = PixelSnap(s.roleIconSize or 14)
                f._roleIcon:SetSize(riSz, riSz)
                -- Mirror the live carrier's "Show Behind Border" level (see AnchorRoleIcon).
                local rc = f._roleIcon:GetParent()
                if rc then
                    rc:SetFrameLevel(f:GetFrameLevel()
                        + (s.roleIconBehindBorder and (ns.LVL_RAISE - 1) or (ns.LVL_AURA - 1)))
                end
                f._roleIcon:ClearAllPoints()
                local pos = (s.roleIconPosition or "bottomleft"):upper()
                f._roleIcon:SetPoint(pos, ns.RF_AnchorHost(f._health, s), pos, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
                f._roleIcon:Show()
            else
                f._roleIcon:Hide()
            end
        else
            f._roleIcon:Hide()
        end
    end

    -- Leader icon: show on slot 1 (player = leader in preview)
    if f._leaderIcon then
        if s.showLeaderIcon and index == 1 then
            local liSz = PixelSnap(s.leaderIconSize or 14)
            f._leaderIcon:SetSize(liSz, liSz)
            f._leaderIcon:ClearAllPoints()
            local liPos = (s.leaderIconPosition or "top"):upper()
            f._leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(f._health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            f._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            f._leaderIcon:Show()
        else
            f._leaderIcon:Hide()
        end
    end

    -- Combat icon: on live alive members when the indicators eyeball is on.
    if f._combatIcon then
        if indVis and s.showCombatIndicator and not isDead and not isOffline then
            local cciSz = PixelSnap(s.combatIndicatorSize or 16)
            f._combatIcon:SetSize(cciSz, cciSz)
            f._combatIcon:ClearAllPoints()
            local ciPos = (s.combatIndicatorPosition or "right"):upper()
            f._combatIcon:SetPoint(ciPos, ns.RF_AnchorHost(f._health, s), ciPos, s.combatIndicatorOffsetX or 0, s.combatIndicatorOffsetY or 0)
            local style = s.combatIndicatorStyle or "standard"
            local MEDIA = ns._COMBAT_MEDIA
            if style:find("^combat%d") then
                f._combatIcon:SetTexture(MEDIA .. style .. ".tga")
                f._combatIcon:SetTexCoord(0, 1, 0, 1)
                if f._combatIcon.SetDesaturated then f._combatIcon:SetDesaturated(false) end
                f._combatIcon:SetVertexColor(1, 1, 1, 1)
            else
                if style == "class" then
                    f._combatIcon:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
                    local coords = classToken and ns._COMBAT_CLASS_COORDS[classToken]
                    if coords then f._combatIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    else f._combatIcon:SetTexCoord(0, 1, 0, 1) end
                else
                    f._combatIcon:SetTexture(MEDIA .. "combat-indicator-custom.png")
                    f._combatIcon:SetTexCoord(0, 1, 0, 1)
                end
                local colorMode = s.combatIndicatorColor or "custom"
                if colorMode == "classcolor" then
                    local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                    f._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                else
                    local cc = s.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                    f._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                end
            end
            f._combatIcon:Show()
        else
            f._combatIcon:Hide()
        end
    end

    -- Buff manager indicators only shown on the BM page preview, not here

    -- Debuff/defensive preview icons managed by PvAuraTicker (cycling system)

    f:Show()
end

ns._previewInitialized = false

local function InitPreviewHealthValues()
    if ns._previewInitialized then return end
    ns._previewInitialized = true
    for i = 1, 20 do
        previewHealthValues[i] = 40 + math.random(60)
        previewPowerValues[i] = 50 + math.random(50)
        ns.previewAbsorbValues[i] = 0
        ns.previewHealAbsorbValues[i] = 0
    end
    -- Assign shields: at least 1 per group of 5, plus a few random extras
    for g = 0, 3 do
        -- Guaranteed 1 per group
        local slot = g * 5 + math.random(5)
        ns.previewAbsorbValues[slot] = 5 + math.random(25)
        -- 50% chance of a second in the group
        if math.random() > 0.5 then
            local slot2 = g * 5 + math.random(5)
            if ns.previewAbsorbValues[slot2] == 0 then
                ns.previewAbsorbValues[slot2] = 3 + math.random(15)
            end
        end
    end
    -- Assign heal absorbs: 2 random slots
    local haPool = {}
    for i = 2, 20 do haPool[#haPool + 1] = i end
    for i = #haPool, 2, -1 do
        local j = math.random(i)
        haPool[i], haPool[j] = haPool[j], haPool[i]
    end
    ns.previewHealAbsorbValues[haPool[1]] = 20 + math.random(20)
    ns.previewHealAbsorbValues[haPool[2]] = 20 + math.random(20)

    -- Assign heal prediction: 2 random slots (non-full-health frames)
    ns.previewHealPredValues = {}
    for i = 1, 20 do ns.previewHealPredValues[i] = 0 end
    local hpPool = {}
    for i = 1, 20 do
        if previewHealthValues[i] < 95 then hpPool[#hpPool + 1] = i end
    end
    for i = #hpPool, 2, -1 do
        local j = math.random(i)
        hpPool[i], hpPool[j] = hpPool[j], hpPool[i]
    end
    if hpPool[1] then ns.previewHealPredValues[hpPool[1]] = 10 + math.random(20) end
    if hpPool[2] then ns.previewHealPredValues[hpPool[2]] = 10 + math.random(20) end

    -- Reduced max health: 2 random slots with 10-25% health loss
    ns.previewReducedMaxHealth = {}
    for i = 1, 20 do ns.previewReducedMaxHealth[i] = 0 end
    local rmhPool = {}
    for i = 2, 20 do rmhPool[#rmhPool + 1] = i end
    for i = #rmhPool, 2, -1 do
        local j = math.random(i)
        rmhPool[i], rmhPool[j] = rmhPool[j], rmhPool[i]
    end
    ns.previewReducedMaxHealth[rmhPool[1]] = 0.10 + math.random() * 0.15
    ns.previewReducedMaxHealth[rmhPool[2]] = 0.10 + math.random() * 0.15
end

-------------------------------------------------------------------------------
--  Overlay preview container
--  A black-background frame that holds the preview when in overlay mode.
--  Position is hardcoded (see RefreshPreview) -- it is NOT draggable and
--  nothing is saved to the profile.
-------------------------------------------------------------------------------
local overlayContainer = nil

local function GetOrCreateOverlayContainer()
    if overlayContainer then return overlayContainer end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    local bg = oc:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    oc._bg = bg

    -- Centered title at the top of the preview. Font/text/color/visibility are
    -- (re)applied each refresh in RefreshPreview so it tracks the active font.
    -- SetText is deferred until after ApplyFont there (a fontstring with no font
    -- set errors on SetText), matching how the group-number labels are built.
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", oc, "TOP", 0, -7)
    oc._title = title

    overlayContainer = oc
    ns._overlayContainer = oc
    return oc
end

local function RefreshPreview()
    if not previewActive then return end
    if not containerFrame then return end
    if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    BuildPreviewRoles()

    local s = ns._pvOverlayProxy or db.profile
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth  = s.unitGrowth or "DOWN"
    -- The same self-heal the live layout runs, so the preview cannot render a
    -- grid where merged mode lays out a row (Blizzard's flat header has one
    -- column axis and cannot wrap into one).
    unitGrowth, groupGrowth = ns._RFEffectiveGrowth(unitGrowth, groupGrowth, s.mergeGroups)
    local bw = PixelSnap(s.frameWidth or 72)
    local bh = PixelSnap(s.frameHeight or 46)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)

    -- Group bounding box
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Group slot origins along the growth flow (plain direction = one run,
    -- grid flow = ns._RF_GRID_ROWS per column), same helper the live layout
    -- places real groups through.
    local gSlots, minGX, maxGY = ns._RFGroupFlow(groupGrowth, groupW, groupH, gs, 4)

    -- Unit step within a group
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then
        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then
        uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then
        uStepX = (bw + cs)
    else -- LEFT
        uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (0-indexed)
    local rawUX, rawUY = {}, {}
    local minUX, maxUY = 0, 0
    for i = 0, 4 do
        rawUX[i] = i * uStepX
        rawUY[i] = i * uStepY
        if rawUX[i] < minUX then minUX = rawUX[i] end
        if rawUY[i] > maxUY then maxUY = rawUY[i] end
    end

    -- Overlay mode: anchor to overlay container with padding
    local isOverlay = (db.profile.previewMode == "overlay") or ns._testMode
    local anchor = previewContainer or containerFrame
    local anchorPad = 0
    local topExtra = 0   -- extra top space (overlay only): 25px gap above the
                         -- group numbers, leaving room for the centered title
    if isOverlay then
        local oc = GetOrCreateOverlayContainer()
        anchor = oc
        anchorPad = 20
        topExtra = 25
    end

    -- Container size, through the SAME ns._RFFootprint the live container is
    -- sized with. The old one-row formula drew a 4x1 box around the grid flow's
    -- 2x2 block.
    local totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Pets (Show Pets on the Raid tab) go before the first or after the last group. The overlay
    -- grows to hold them; at the real position the groups stay put and the pets hang off them.
    local petSpec = ns.PF_PreviewSpec(false, s, bw, bh, cs, groupW, groupH)
    local petX, petY, padL, padT, padR, padB = 0, 0, 0, 0, 0, 0
    if petSpec then
        local slot = petSpec.before and 0 or (MOVER_GROUPS - 1)
        petX = gSlots[slot][1] - minGX + petSpec.ox
        petY = gSlots[slot][2] - maxGY + petSpec.oy
        if isOverlay then
            padL = max(0, -petX)
            padT = max(0, petY)
            padR = max(0, petX + petSpec.bw - totalW)
            padB = max(0, petSpec.bh - petY - totalH)
        end
    end

    -- Hide all preview frames first
    for _, f in ipairs(previewFrames) do f:Hide() end

    -- The 20-player preview keeps subgroup identities while moving each
    -- group's five frames to its visual slot.
    local groupOrder = s.customGroupOrder and not s.mergeGroups
        and ns._RFValidatedGroupOrder(s.groupOrder)
    local previewSlotByGroup
    if groupOrder then
        previewSlotByGroup = {}
        local previewSlot = 0
        for _, group in ipairs(groupOrder) do
            if group <= 4 then
                previewSlotByGroup[group] = previewSlot
                previewSlot = previewSlot + 1
            end
        end
    end

    -- Place 20 preview frames: 4 groups x 5 units
    local frameIdx = 0
    for g = 0, 3 do
        local displaySlot = previewSlotByGroup and previewSlotByGroup[g + 1] or g
        local gx = gSlots[displaySlot][1] - minGX
        local gy = gSlots[displaySlot][2] - maxGY
        local firstFrame   -- the group's u == 0 frame, the group-number anchor
        for u = 0, 4 do
            frameIdx = frameIdx + 1
            local f = GetOrCreatePreviewFrame(frameIdx)
            f:ClearAllPoints()
            local fx = gx + (rawUX[u] - minUX)
            local fy = gy + (rawUY[u] - maxUY)
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT", fx + anchorPad + padL, fy - anchorPad - topExtra - padT)
            ApplyPreviewData(f, frameIdx)

            if f._health and previewHealthValues[frameIdx] then
                local barPct = ns.RF_IsInvertedFill(s) and (100 - previewHealthValues[frameIdx]) or previewHealthValues[frameIdx]
                f._health:SetValue(barPct)
                f._healthPct = previewHealthValues[frameIdx]
            end
            if f._power and previewPowerValues[frameIdx] then
                f._power:SetValue(previewPowerValues[frameIdx])
                f._powerPct = previewPowerValues[frameIdx]
            end
            if u == 0 then firstFrame = f end
        end

        -- Group number label anchored to the first unit of each group
        local lbl = previewGroupLabels[g + 1]
        if not lbl then
            lbl = anchor:CreateFontString(nil, "OVERLAY")
            previewGroupLabels[g + 1] = lbl
        end
        ApplyFont(lbl, s.groupNumberSize or 10)
        do
            -- Shared size/color with the real frames (group-number settings).
            -- Not gated by showGroupNumbers: the preview always shows numbers.
            local gc = s.groupNumberColor or {}
            lbl:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
        end
        lbl:SetText(tostring(g + 1))
        lbl:ClearAllPoints()
        -- Anchor based on unit growth: label goes "before" the first unit.
        -- The X/Y offset (shared group-number setting) shifts it from there.
        local gnox = s.groupNumberOffsetX or 0
        local gnoy = s.groupNumberOffsetY or 0
        if unitGrowth == "DOWN" then
            lbl:SetPoint("BOTTOM", firstFrame, "TOP", gnox, 4 + gnoy)
        elseif unitGrowth == "UP" then
            lbl:SetPoint("TOP", firstFrame, "BOTTOM", gnox, -4 + gnoy)
        elseif unitGrowth == "RIGHT" then
            lbl:SetPoint("RIGHT", firstFrame, "LEFT", -3 + gnox, gnoy)
        else -- LEFT
            lbl:SetPoint("LEFT", firstFrame, "RIGHT", 3 + gnox, gnoy)
        end
        lbl:Show()
    end

    -- Reparent after all frames are created (first load creates them in the loop above)
    local reparentTo = isOverlay and overlayContainer or (previewContainer or containerFrame)
    for _, f in ipairs(previewFrames) do f:SetParent(reparentTo) end
    -- Group-number labels go on a high-level overlay child of the same container
    -- so they draw ABOVE the preview bars (which are descendants of reparentTo);
    -- parenting them straight to reparentTo leaves them beneath the bars.
    if not ns._previewGroupNumberOverlay then
        ns._previewGroupNumberOverlay = CreateFrame("Frame", nil, reparentTo)
    end
    ns._previewGroupNumberOverlay:SetParent(reparentTo)
    ns._previewGroupNumberOverlay:SetAllPoints(reparentTo)
    ns._previewGroupNumberOverlay:SetFrameLevel(9000)
    ns._previewGroupNumberOverlay:Show()
    for _, lbl in ipairs(previewGroupLabels) do lbl:SetParent(ns._previewGroupNumberOverlay) end
    if petSpec then
        ns.PF_ShowPreview(petSpec, s, reparentTo, anchor,
            petX + anchorPad + padL, petY - anchorPad - topExtra - padT)
    else
        ns.PF_HidePreview()
    end

    local snapW = PixelSnap(max(totalW, 1))
    local snapH = PixelSnap(max(totalH, 1))
    if previewContainer then
        previewContainer:SetSize(snapW, snapH)
        -- Re-anchor from the saved position on EVERY refresh (mirrors the real
        -- container and the size preview; preserving a stale TOPLEFT here left the
        -- real-mode preview stranded after a growth change until the panel reopened).
        -- Anchored at the base footprint's top-left so size changes grow down/right
        -- exactly like the real container's _ApplyTierOffset scheme.
        local se = ns._PvSessionElem and ns._PvSessionElem("RF_RaidFrames")
        local bl, bt = ns._RFBaseTopLeft()
        previewContainer:ClearAllPoints()
        if se and se.point then
            -- Editing an override with a custom unlock mode: place the
            -- preview at the LAYER's recorded container position.
            previewContainer:SetPoint(se.point, UIParent, se.relPoint or se.point,
                PixelSnap(se.x or 0), PixelSnap(se.y or 0))
        elseif bl then
            previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(bl), PixelSnap(bt))
        else
            previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        -- Snap TOPLEFT to pixel grid (same fix as containerFrame in LayoutGroups)
        local l = previewContainer:GetLeft()
        local t = previewContainer:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                previewContainer:ClearAllPoints()
                previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Size and position overlay container
    if isOverlay and overlayContainer then
        overlayContainer:SetSize(totalW + padL + padR + anchorPad * 2,
            totalH + padT + padB + anchorPad * 2 + topExtra)
        if overlayContainer._title then
            ApplyFont(overlayContainer._title, 13)
            overlayContainer._title:SetText("Overlay Preview")
            overlayContainer._title:SetTextColor(1, 1, 1, 0.9)
            overlayContainer._title:Show()
        end
        if ns._testMode then
            -- Test mode: center on screen, above dimmer
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(55)
            overlayContainer:ClearAllPoints()
            overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 80, 0)
        else
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(10)
            overlayContainer:ClearAllPoints()
            -- Hardcoded default position (not draggable, not saved): docked to
            -- the left edge of the options panel, screen center as a fallback.
            local sf = EllesmereUI._scrollFrame
            if sf then
                overlayContainer:SetPoint("BOTTOMRIGHT", sf, "BOTTOMLEFT", 0, 0)
            else
                overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        overlayContainer:Show()
    end
end

-- Mouse-blocking overlays + alpha-based real-frame hide for the options preview.
-- Wrapped in a do-block, exposed via ns, so these add NO persistent main-chunk
-- locals (200-local cap); rfMouseBlock/partyMouseBlock survive as closure upvalues.
--
-- The overlays are OUR OWN non-secure frames, so EnableMouse is taint-free and
-- Hide() is combat-legal (no secure children) -- torn down instantly at combat
-- start, so they can never trap a healer's clicks during a pull. They track the
-- real containers directly (alpha-0 but correctly sized/positioned), covering
-- the now-invisible real unit buttons in both preview and size preview.
--
-- Real containers hide via ALPHA, not reparenting: they stay parented to
-- UIParent at their saved position, so SetAlpha(1) restore is always legal and
-- can never be deferred by combat (reparenting secure-header containers back
-- is combat-blocked -- the old cause of "no party frames for the whole first
-- pull"). Preview frames reparent to previewContainer/overlayContainer/partyOC/
-- UIParent before display, so container alpha 0 never hides the preview itself.
do
    local rfMouseBlock, partyMouseBlock
    local function setBlock(on)
        if on then
            if containerFrame then
                if not rfMouseBlock then
                    rfMouseBlock = CreateFrame("Frame", nil, UIParent)
                    rfMouseBlock:EnableMouse(true)
                end
                rfMouseBlock:SetAllPoints(containerFrame)
                rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
                rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
                rfMouseBlock:Show()
            end
            if ns._partyContainerFrame then
                if not partyMouseBlock then
                    partyMouseBlock = CreateFrame("Frame", nil, UIParent)
                    partyMouseBlock:EnableMouse(true)
                end
                partyMouseBlock:SetAllPoints(ns._partyContainerFrame)
                partyMouseBlock:SetFrameStrata(ns._partyContainerFrame:GetFrameStrata())
                partyMouseBlock:SetFrameLevel(ns._partyContainerFrame:GetFrameLevel() + 50)
                partyMouseBlock:Show()
            end
        else
            if rfMouseBlock then rfMouseBlock:Hide() end
            if partyMouseBlock then partyMouseBlock:Hide() end
        end
        -- The pet frames' own (their header, and the pets beside the party frames), and the
        -- party target frames' (outside the party container too).
        ns._PF_SetPreviewBlock(on)
        ns._PT_SetPreviewBlock(on)
    end
    ns._SetPreviewMouseBlock = setBlock
    ns._RefreshPreviewMouseBlockStrata = function()
        if rfMouseBlock and rfMouseBlock:IsShown() and containerFrame then
            rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
            rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
        end
        if partyMouseBlock and partyMouseBlock:IsShown() and ns._partyContainerFrame then
            partyMouseBlock:SetFrameStrata(ns._partyContainerFrame:GetFrameStrata())
            partyMouseBlock:SetFrameLevel(ns._partyContainerFrame:GetFrameLevel() + 50)
        end
        ns._PF_RefreshPreviewBlock()
        ns._PT_RefreshPreviewBlock()
    end
    function ns._SetRealFramesPreviewHidden(on)
        -- Overlay preview is a separate docked panel, so the real frames are NOT
        -- under it: leave them faintly visible (alpha 0.2) and DON'T mouse-block
        -- them. Real preview replaces the frames in place, so keep the original
        -- behavior there: hide fully (alpha 0) + block clicks.
        local isOverlay = (db.profile.previewMode == "overlay") or ns._testMode
        if isOverlay then
            local a = on and 0.2 or 1
            if containerFrame then containerFrame:SetAlpha(a) end
            if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
            if ns._ptModelOn then ns.RF_PtContainerAlpha(a) end
            if ns._PF.container then ns._PF.container:SetAlpha(a) end
            setBlock(false)
        else
            local a = on and 0 or 1
            if containerFrame then containerFrame:SetAlpha(a) end
            if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
            if ns._ptModelOn then ns.RF_PtContainerAlpha(a) end
            if ns._PF.container then ns._PF.container:SetAlpha(a) end
            setBlock(on)
        end
        -- The pets beside the party frames take the container's alpha through their own.
        ns._PF_AlphaSync()
    end
end

local function ShowPreview()
    -- Never engage the preview unless the options window is actually open (or test mode
    -- is active). A deferred C_Timer ShowPreview firing after the panel closed (combat
    -- auto-close, rapid close) would reparent the real containers under the hidden
    -- preview parent with nothing left to restore them -- the root cause of "frames
    -- vanish after closing options". Reparenting secure-header containers is also
    -- blocked/taint-prone in combat, so bail there too.
    if not ns._testMode and not (EllesmereUI:IsShown()) then return end
    if InCombatLockdown() then return end
    -- Kill any active size preview
    if ns._sizePreviewTier then
        ns._sizePreviewTier = nil
        if ns._HideSizePreview then ns._HideSizePreview() end
    end
    if previewActive then
        RefreshPreview()
        return
    end
    if not containerFrame then return end
    previewActive = true

    -- Preview container
    if not previewContainer then
        previewContainer = CreateFrame("Frame", nil, UIParent)
        previewContainer:SetFrameStrata("HIGH")
    end
    local pos = db.profile.unlockPos
    previewContainer:ClearAllPoints()
    if pos then
        previewContainer:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    previewContainer:SetSize(containerFrame:GetSize())
    previewContainer:Show()

    -- Hide the real containers for preview via alpha (combat-reversible) instead
    -- of reparenting. SetAlpha is not protected, so the restore can never be
    -- blocked or deferred by combat. The containers stay parented to UIParent at
    -- their saved position; preview frames are reparented out of the containers
    -- by RefreshPreview below, so container alpha 0 does not hide the preview.
    ns._SetRealFramesPreviewHidden(true)

    -- Initialize health values and role assignments
    InitPreviewHealthValues()
    BuildPreviewRoles()

    RefreshPreview()
    StartPvAuraTicker()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on tab swaps into the party tab, where ShowPartyPreview
-- re-hides them on the next frame -- restoring here would flash the real frames
-- for one frame first. Panel close restores explicitly.
local function HidePreview(skipRestore)
    if not previewActive then return end
    previewActive = false
    ns._previewInitialized = false
    previewRoles._randomized = nil  -- re-randomize on next preview open
    previewRoles._hpalPick = nil    -- re-roll the hpal Legends next open
    StopPvAuraTicker()
    ns.StopPvBuffTicker()
    -- Hide overlay container
    if overlayContainer then overlayContainer:Hide() end
    -- Hide preview container
    if previewContainer then previewContainer:Hide() end
    -- Reparent preview frames back to containerFrame
    for _, f in ipairs(previewFrames) do
        f:SetParent(containerFrame)
        f:Hide()
    end
    for _, lbl in ipairs(previewGroupLabels) do
        lbl:SetParent(containerFrame)
        lbl:Hide()
    end
    ns.PF_HidePreview()
    if skipRestore then return end
    -- The containers were only alpha-hidden (never reparented or moved), so the
    -- restore is a combat-legal SetAlpha(1) plus dropping the mouse blockers. No
    -- combat gate, no SetParent/SetPoint, no ns._restorePending deferral.
    ns._SetRealFramesPreviewHidden(false)
    -- Re-run layout out of combat in case frame sizes changed while previewing
    -- (LayoutGroups SetPoints secure headers, so out of combat only).
    if not InCombatLockdown() then LayoutGroups() end
    -- Re-derive the growth-corner anchor after the relayout (self-gates on
    -- combat) so a size change made while previewing can never strand the
    -- container at a stale position.
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

local function ApplyPreviewMode()
    local mode = db.profile.previewMode or "overlay"

    if mode == "none" then
        if previewActive then HidePreview() end
        return
    end
    if not previewActive then
        ShowPreview()
        return
    end
    local isOverlay = (mode == "overlay")
    if not isOverlay and overlayContainer then
        overlayContainer:Hide()
    end
    -- Re-apply the real-frame hide state for the (possibly just-changed) mode so a
    -- live Real<->Overlay switch updates alpha + mouse-block: overlay shows the
    -- real frames faintly with NO block; real hides them fully + blocks.
    ns._SetRealFramesPreviewHidden(true)
    -- RefreshPreview handles reparenting, anchoring, and overlay sizing
    RefreshPreview()
end

ns.ApplyPreviewMode = ApplyPreviewMode

-- Expose for options panel
ns.ShowPreview = ShowPreview
ns.HidePreview = HidePreview
ns.previewActive = function() return previewActive end
ns.ResetPreviewRandomization = function()
    previewRoles._randomized = nil
    previewRoles._hpalPick = nil
end
ns.previewFrames = previewFrames
ns.previewHealthValues = previewHealthValues
ns.previewPowerValues = previewPowerValues

-- Party-aware sibling of PvEffectiveProfile, for the shared options tickers:
-- party preview reads party-prefixed settings, raid preview reads the live
-- profile through the real-preview effective overlay.
ns.PvSettings = PvSettings

-- Active-preview accessors for the options eyeballs (resolve raid vs party at
-- call time so the health/power animations drive whichever preview is on screen).
ns.PvActiveFrames = PvFrames
ns.PvHealthValues = function() return (ns._partyPvActive and ns._partyPvHV) or previewHealthValues end
ns.PvPowerValues  = function() return (ns._partyPvActive and ns._partyPvPV) or previewPowerValues end
-- Re-render whichever preview is active (mirrors ShowPreview's refresh-if-active).
-- Uses the ns.* exports because ShowPartyPreview is declared later in the file.
ns.PvRefresh = function()
    if ns._partyPvActive then
        if ns.ShowPartyPreview then ns.ShowPartyPreview() end
    elseif ns.ShowPreview then
        ns.ShowPreview()
    end
end

-------------------------------------------------------------------------------
--  Size preview (simple: just health + power bars at the tier's dimensions)
--  Shows the correct number of frames for the tier (10/15/25/30/40).
--  Always screen-anchored exactly where the live frames land (shared
--  growth-corner origin ns._RFTierTopLeft), regardless of preview mode.
--  No indicators, no randomization.
-------------------------------------------------------------------------------
ns._sizePreviewTier = nil
ns._sizePreviewFrames = {}
ns._sizePreviewContainer = nil

ns._ShowSizePreview = function(tier)
    -- Preview only ever runs out of combat. A mid-combat alpha-0 here could not
    -- be undone by the PLAYER_REGEN_DISABLED safety net (it already fired at
    -- combat start), and would strand the real frames invisible for the rest of
    -- the pull -- the same game-breaking outcome the alpha rework prevents.
    if InCombatLockdown() then return end
    local s = db.profile
    local overrides = s.raidSizeOverrides
    if not overrides or not overrides[tier] then return end

    -- Hide any active previews (both real and overlay mode)
    if previewActive then
        HidePreview()  -- cleans up real-mode preview frames
    end
    if ns._partyPvActive then
        HidePartyPreview()
    end
    -- Hide real raid + party frames during size preview via alpha so a combat
    -- start can re-show them (Hide/Show are protected and cannot be undone in
    -- combat; SetAlpha is not). The size-preview frames live in their own
    -- UIParent child (ns._sizePreviewContainer), so container alpha does not
    -- affect them. The mouse blocker keeps the now-invisible real unit buttons
    -- from catching clicks while configuring out of combat.
    if containerFrame then containerFrame:SetAlpha(0) end
    if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(0) end
    if ns._ptModelOn then ns.RF_PtContainerAlpha(0) end
    if ns._PF.container then ns._PF.container:SetAlpha(0) end
    ns._PF_AlphaSync()
    ns._SetPreviewMouseBlock(true)

    local ov = overrides[tier]
    local bw = PixelSnap(ov.width or s.frameWidth or 125)
    local bh = PixelSnap(ov.height or s.frameHeight or 60)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local unitGrowth, groupGrowth = ns._RFEffectiveGrowth(
        ov.unitGrowth or s.unitGrowth or "DOWN", ov.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
    local frameCount  = tier
    local perGroup    = 5
    local numGroups   = math.ceil(frameCount / perGroup)

    -- Group bounding box (same logic as LayoutGroups)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = perGroup * bw + (perGroup - 1) * cs
        groupH = bh
    else
        groupW = bw
        groupH = perGroup * bh + (perGroup - 1) * cs
    end

    -- Unit step within a group along unitGrowth axis
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then      uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then   uStepX = (bw + cs)
    else                                uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (matches RefreshPreview pattern)
    local minUX, maxUY = 0, 0
    for u = 0, perGroup - 1 do
        local px = u * uStepX
        local py = u * uStepY
        if px < minUX then minUX = px end
        if py > maxUY then maxUY = py end
    end

    -- Total bounding box: the tier's group mover footprint via the SAME
    -- ns._RFFootprint the live container sizing and the corner origin use (one
    -- formula, so preview and live can never drift).
    local totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Tier offset
    local tierOX = ov.offsetX or 0
    local tierOY = ov.offsetY or 0

    -- Create or reuse container
    local container = ns._sizePreviewContainer
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container:SetFrameStrata("FULLSCREEN_DIALOG")
        container:SetFrameLevel(10)
        -- Never clamp: the preview must land exactly where the live
        -- container lands, including partially off-screen positions.
        container:SetClampedToScreen(false)
        ns._sizePreviewContainer = container
    end

    -- Always use real positioning (where frames actually sit)
    local pad = 0
    container:SetSize(totalW, totalH)
    if container._bg then container._bg:Hide() end
    container:SetFrameStrata("HIGH")
    container:ClearAllPoints()
    -- Same growth-corner origin as the live container (_ApplyTierOffset):
    -- the tier footprint's growth-derived corner pins at the base
    -- footprint's same corner plus the tier offset, via the shared
    -- ns._RFTierTopLeft -- the preview lands exactly where live lands.
    local px, py = ns._RFTierTopLeft(totalW, totalH, unitGrowth, groupGrowth, tierOX, tierOY)
    if px then
        container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(px), PixelSnap(py))
    else
        container:SetPoint("CENTER", UIParent, "CENTER", tierOX, tierOY)
    end

    -- Font for the unit-number label
    local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local nameSize = s.nameSize or 10

    -- Group slot origins along the growth flow, normalized over MOVER_GROUPS
    -- (matching the real LayoutGroups container). At least MOVER_GROUPS slots
    -- are generated even when the tier shows fewer groups: the normalization
    -- origin is what puts slot 0 at the growth corner, so normalizing over a
    -- 2- or 3-group prefix would place the preview on the wrong side of the
    -- box for LEFT/UP growth. The extra slots are simply not drawn.
    local gSlots, minX, maxY = ns._RFGroupFlow(groupGrowth, groupW, groupH, gs, max(numGroups, MOVER_GROUPS))

    local groupOrder = s.customGroupOrder and not s.mergeGroups
        and ns._RFValidatedGroupOrder(s.groupOrder)
    local sizePreviewSlotByGroup
    if groupOrder then
        sizePreviewSlotByGroup = {}
        local sizePreviewSlot = 0
        for _, group in ipairs(groupOrder) do
            if group <= numGroups then
                sizePreviewSlotByGroup[group] = sizePreviewSlot
                sizePreviewSlot = sizePreviewSlot + 1
            end
        end
    end

    for i = 1, frameCount do
        local f = ns._sizePreviewFrames[i]
        if not f then
            f = CreateFrame("Frame", nil, container)
            local health = CreateFrame("StatusBar", nil, f)
            health:SetPoint("TOPLEFT")
            health:SetPoint("TOPRIGHT")
            health:SetMinMaxValues(0, 100)
            health:SetValue(100)
            -- Pre-paint tint (see StyleButton's health bar note).
            health:SetStatusBarColor(0.12, 0.12, 0.12)
            if PP then PP.DisablePixelSnap(health) end
            f._health = health

            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if PP then PP.DisablePixelSnap(bg) end
            f._bg = bg

            local power = CreateFrame("StatusBar", nil, f)
            power:SetPoint("BOTTOMLEFT")
            power:SetPoint("BOTTOMRIGHT")
            power:SetMinMaxValues(0, 1)
            power:SetValue(1)
            if PP then PP.DisablePixelSnap(power) end
            f._power = power

            local bdr = CreateFrame("Frame", nil, f)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(f:GetFrameLevel() + 2)
            if PP then PP.CreateBorder(bdr, 0, 0, 0, 1, 1) end
            f._border = bdr

            -- Name text
            local nameFS = health:CreateFontString(nil, "OVERLAY")
            nameFS:SetJustifyH("CENTER")
            nameFS:SetWordWrap(false)
            f._nameText = nameFS

            -- Top Name Bar
            local tnb = CreateFrame("Frame", nil, f)
            tnb:SetFrameLevel(f:GetFrameLevel() + 4)
            tnb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
            tnbBg:SetAllPoints()
            if PP then PP.DisablePixelSnap(tnbBg) end
            local tnbText = tnb:CreateFontString(nil, "OVERLAY")
            tnbText:SetWordWrap(false)
            tnb:Hide()
            f._topNameBar = tnb
            f._topNameBarBg = tnbBg
            f._topNameBarText = tnbText

            -- Role icon
            local roleIcon = health:CreateTexture(nil, "OVERLAY")
            roleIcon:Hide()
            f._roleIcon = roleIcon

            ns._sizePreviewFrames[i] = f
        end

        f:SetParent(container)
        f:SetSize(bw, bh)
        -- GENERIC SIZING PLACEHOLDER (NOT a style preview):
        -- The custom raid-size previews (10/15/25/30) deliberately do NOT mimic the
        -- user's real raid-frame style. They render as plain blocks that only show
        -- each frame's footprint at the chosen width/height/spacing, so the size
        -- preview can never be mistaken for a live style preview when it does not
        -- match the user's customized frames. No class colors, textures, power bars,
        -- names, role icons or custom border -- just a flat fill, a thin neutral
        -- outline and the unit number.
        f._health:ClearAllPoints()
        f._health:SetAllPoints(f)
        f._health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        if f._health:GetStatusBarTexture() then f._health:GetStatusBarTexture():SetHorizTile(false) end
        f._health:SetStatusBarColor(0.24, 0.26, 0.30, 1)
        f._health:SetValue(100)
        f._bg:SetColorTexture(0.09, 0.09, 0.11, 1)
        if f._power then f._power:Hide() end
        if f._topNameBar then f._topNameBar:Hide() end
        if f._roleIcon then f._roleIcon:Hide() end

        -- Thin neutral outline so each block and the spacing between them reads clearly.
        if f._border and PP then
            f._border:SetFrameLevel(f:GetFrameLevel() + 2)
            EllesmereUI.ApplyBorderStyle(f._border, 1, 0.7, 0.7, 0.75, 0.8,
                "solid", nil, nil, nil, nil, "unitframes", 1)
        end

        -- Centered unit number.
        if f._nameText then
            EllesmereUI.ApplyModuleFont(f._nameText, fontPath, math.max(11, nameSize), "raidFrames")
            f._nameText:SetText(tostring(i))
            f._nameText:SetTextColor(0.9, 0.9, 0.9)
            f._nameText:SetWidth(bw)
            f._nameText:ClearAllPoints()
            f._nameText:SetPoint("CENTER", f._health, "CENTER", 0, 0)
            f._nameText:Show()
        end

        -- Position: group index + unit index within group
        local groupIdx = math.ceil(i / perGroup) - 1
        local unitIdx  = (i - 1) % perGroup

        -- Group origin (TOPLEFT-relative, adjusted for growth direction)
        local displaySlot = sizePreviewSlotByGroup and sizePreviewSlotByGroup[groupIdx + 1] or groupIdx
        local gx = gSlots[displaySlot][1] - minX
        local gy = gSlots[displaySlot][2] - maxY

        -- Unit offset within group (TOPLEFT-normalized, matching RefreshPreview)
        local ux = unitIdx * uStepX - minUX
        local uy = unitIdx * uStepY - maxUY

        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", container, "TOPLEFT", pad + gx + ux, -pad + gy + uy)
        f:Show()
    end

    -- Hide excess frames
    for i = frameCount + 1, #ns._sizePreviewFrames do
        ns._sizePreviewFrames[i]:Hide()
    end

    container:Show()
end

ns._HideSizePreview = function()
    if ns._sizePreviewContainer then
        ns._sizePreviewContainer:Hide()
    end
    for _, f in ipairs(ns._sizePreviewFrames) do
        f:Hide()
    end
    -- Restore real frame opacity (size preview only changed alpha, never the
    -- Shown state) and drop the mouse blocker. SetAlpha(1) is always legal, in
    -- or out of combat, so the frames can never be stranded invisible.
    if containerFrame then containerFrame:SetAlpha(1) end
    if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(1) end
    if ns._ptModelOn then ns.RF_PtContainerAlpha(1) end
    if ns._PF.container then ns._PF.container:SetAlpha(1) end
    ns._PF_AlphaSync()
    ns._SetPreviewMouseBlock(false)
    -- Recompute party visibility (only shows party frames if actually grouped /
    -- Show When Solo). Bails in combat; the alpha restore above suffices there.
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

-------------------------------------------------------------------------------
--  Party preview (5-player, 1 group)
--  Fully separate from raid preview -- shares CreatePreviewFrame and
--  ApplyPreviewData via temp-swap pattern but has its own frame pool,
--  health values, role assignments, layout, and overlay container.
-------------------------------------------------------------------------------
ns._partyPvFrames    = {}
ns._partyPvHV        = {}
ns._partyPvPV        = {}
ns._partyPvActive    = false
ns._partyPvInit      = false
ns.partyPvAbsorbValues     = {}
ns.partyPvHealAbsorbValues = {}
ns.partyPvHealPredValues   = {}
ns.partyPvReducedMaxHealth = {}
ns._partyPvRoles     = {}
ns._partyPvCT        = {}

local function BuildPartyPreviewRoles()
    for i = 1, 5 do ns._partyPvRoles[i] = nil end
    wipe(ns._partyPvCT)

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = EllesmereUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
    end

    -- Slot 1 = player
    ns._partyPvRoles[1] = playerRole
    local _, pct = UnitClass("player")
    ns._partyPvCT[1] = pct or "WARRIOR"
    ns._partyPvRoles._playerSlot = 1

    -- Fill remaining: 1 tank, 1 healer, 3 DPS total
    local needTank   = (playerRole ~= "TANK")   and 1 or 0
    local needHealer = (playerRole ~= "HEALER") and 1 or 0
    local tankIdx, healerIdx, dpsIdx = 1, 1, 1

    for i = 2, 5 do
        if needTank > 0 then
            ns._partyPvRoles[i] = "TANK"
            ns._partyPvCT[i] = ns._PV_TANK_CLASSES[tankIdx]
            tankIdx = (tankIdx % #ns._PV_TANK_CLASSES) + 1
            needTank = needTank - 1
        elseif needHealer > 0 then
            ns._partyPvRoles[i] = "HEALER"
            ns._partyPvCT[i] = ns._PV_HEALER_CLASSES[healerIdx]
            healerIdx = (healerIdx % #ns._PV_HEALER_CLASSES) + 1
            needHealer = needHealer - 1
        else
            ns._partyPvRoles[i] = "DAMAGER"
            ns._partyPvCT[i] = ns._PV_DPS_CLASSES[dpsIdx]
            dpsIdx = (dpsIdx % #ns._PV_DPS_CLASSES) + 1
        end
    end

    -- Sort by role order + self-first (reads party-specific settings)
    local sortMode = db.profile.partySortMode or db.profile.sortMode or "INDEX"
    local showSelfFirst = db.profile.partyShowSelfFirst
    if showSelfFirst == nil then showSelfFirst = db.profile.showSelfFirst end
    local selfLast = db.profile.partySelfLast
    if selfLast == nil then selfLast = db.profile.showSelfLast end
    if selfLast then showSelfFirst = true end  -- self ordering active either way
    local prioritizeClass = db.profile.partyPrioritizeClass
    if sortMode == "ROLE" or showSelfFirst or prioritizeClass then
        local group = {}
        for u = 1, 5 do
            group[u] = {
                role = ns._partyPvRoles[u],
                classToken = ns._partyPvCT[u],
                isPlayer = (u == 1),
                idx = u,
            }
        end
        if sortMode == "ROLE" or prioritizeClass then
            -- Mirror the live header order: role (optional primary) -> class (when
            -- Prioritize Class is on) -> original slot. Comparator matches
            -- _BuildPartyClassNameList so the preview replicates the real frames.
            local sortByRole = (sortMode == "ROLE")
            local roleOrder = db.profile.partyRoleOrder or db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
            local rolePri = {}
            for i, r in ipairs(roleOrder) do rolePri[r] = i end
            local classPri
            if prioritizeClass then
                classPri = {}
                local co = db.profile.partyClassOrder or ns._GetDefaultClassOrder()
                for i, c in ipairs(co) do classPri[c] = i end
            end
            table.sort(group, function(a, b)
                if sortByRole then
                    local ra, rb = rolePri[a.role] or 99, rolePri[b.role] or 99
                    if ra ~= rb then return ra < rb end
                end
                if classPri then
                    local ca, cb = classPri[a.classToken] or 99, classPri[b.classToken] or 99
                    if ca ~= cb then return ca < cb end
                end
                return a.idx < b.idx
            end)
        end
        if showSelfFirst then
            local playerPos
            for i, entry in ipairs(group) do
                if entry.isPlayer then playerPos = i; break end
            end
            if playerPos then
                if selfLast and playerPos < #group then
                    local playerEntry = table.remove(group, playerPos)
                    group[#group + 1] = playerEntry
                elseif not selfLast and playerPos > 1 then
                    local playerEntry = table.remove(group, playerPos)
                    tinsert(group, 1, playerEntry)
                end
            end
        end
        for u = 1, 5 do
            ns._partyPvRoles[u] = group[u].role
            ns._partyPvCT[u] = group[u].classToken
            if group[u].isPlayer then ns._partyPvRoles._playerSlot = u end
        end
    end

    -- Random picks (only once per session)
    if not ns._partyPvRoles._randomized then
        ns._partyPvRoles._randomized = true
        local tanks = {}
        for i = 1, 5 do
            if ns._partyPvRoles[i] == "TANK" then tanks[#tanks + 1] = i end
        end
        ns._partyPvRoles._threatIndex = tanks[math.random(#tanks)] or 1
        -- Marker on the player (slot 1) so each of the four status indicators
        -- gets its own non-player frame (clean 1-per-frame showcase, no overlap).
        ns._partyPvRoles._markerSlot1 = 1
        ns._partyPvRoles._markerSlot2 = nil  -- only 1 marker in 5-man
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        ns._partyPvRoles._dispelMap = {}
        for i, dt in ipairs(dispelTypes) do ns._partyPvRoles._dispelMap[i] = dt end
        -- Status showcase: 1 dead, 1 offline, 1 AFK, 1 summon-accepted, one each on
        -- the four non-player slots (2-5). No ready-check ticks. (Incoming-rez isn't
        -- previewed here: a 5-man has only four non-player slots and they're all
        -- taken, so there's no room for a separate rez corpse the way the raid
        -- preview has one. The live indicator still shows on party frames.)
        local statusSlots = { 2, 3, 4, 5 }
        for i = #statusSlots, 2, -1 do
            local j = math.random(i)
            statusSlots[i], statusSlots[j] = statusSlots[j], statusSlots[i]
        end
        ns._partyPvRoles._deadSlot    = statusSlots[1]
        ns._partyPvRoles._offlineSlot = statusSlots[2]
        ns._partyPvRoles._afkSlot     = statusSlots[3]
        ns._partyPvRoles._readyCheck  = { [statusSlots[4]] = "summon_accepted" }
    end
end

local function InitPartyPreviewHealthValues()
    if ns._partyPvInit then return end
    ns._partyPvInit = true
    for i = 1, 5 do
        ns._partyPvHV[i] = 40 + math.random(60)
        ns._partyPvPV[i] = 50 + math.random(50)
        ns.partyPvAbsorbValues[i] = 0
        ns.partyPvHealAbsorbValues[i] = 0
    end
    -- 1-2 shields
    local slot1 = math.random(5)
    ns.partyPvAbsorbValues[slot1] = 5 + math.random(25)
    if math.random() > 0.5 then
        local slot2 = math.random(5)
        if ns.partyPvAbsorbValues[slot2] == 0 then
            ns.partyPvAbsorbValues[slot2] = 3 + math.random(15)
        end
    end
    -- 1 heal absorb
    local haSlot = math.random(2, 5)
    ns.partyPvHealAbsorbValues[haSlot] = 20 + math.random(20)
    -- 1 heal prediction
    ns.partyPvHealPredValues = {}
    for i = 1, 5 do ns.partyPvHealPredValues[i] = 0 end
    for i = 1, 5 do
        if ns._partyPvHV[i] < 90 then
            ns.partyPvHealPredValues[i] = 10 + math.random(20)
            break
        end
    end
    -- 1 reduced max health
    ns.partyPvReducedMaxHealth = {}
    for i = 1, 5 do ns.partyPvReducedMaxHealth[i] = 0 end
    local rmhSlot = math.random(2, 5)
    ns.partyPvReducedMaxHealth[rmhSlot] = 0.10 + math.random() * 0.15
end

local function GetOrCreatePartyPvFrame(index)
    if ns._partyPvFrames[index] then return ns._partyPvFrames[index] end
    local f = CreatePreviewFrame(index, true)
    -- Reparent from raid preview container to party overlay container
    if ns._partyOC then f:SetParent(ns._partyOC) end
    ns._partyPvFrames[index] = f
    return f
end

-- Apply preview data with party-specific width/height override
local function ApplyPartyPreviewData(f, index)
    local s = db.profile
    -- Use party proxy so ApplyPreviewData reads party-specific settings
    ns._previewSettingsOverride = ns._scaledPartyProxy

    -- Sandwich values sourced through the effective overlay (panel-closed
    -- values while a view swap is active); s stays live db.profile so the
    -- mutation+restore semantics are unchanged.
    local eff = ns._pvOverlayProxy or db.profile
    local origW, origH = s.frameWidth, s.frameHeight
    -- The bars' width (a party portrait widens the frame after the restore).
    local ew, eh, _, eres = ns.RF_PartyDims(eff)
    s.frameWidth, s.frameHeight = ew - (eres or 0), eh

    -- Temporarily swap preview value tables so ApplyPreviewData reads party data
    local origHealth = previewHealthValues
    local origPower  = previewPowerValues
    local origAbsorb = ns.previewAbsorbValues
    local origHA     = ns.previewHealAbsorbValues
    local origHP     = ns.previewHealPredValues
    local origRMH    = ns.previewReducedMaxHealth
    local origRoles  = previewRoles
    local origCT     = previewClassTokens

    for i = 1, 5 do
        previewHealthValues[i] = ns._partyPvHV[i]
        previewPowerValues[i]  = ns._partyPvPV[i]
    end
    ns.previewAbsorbValues     = ns.partyPvAbsorbValues
    ns.previewHealAbsorbValues = ns.partyPvHealAbsorbValues
    ns.previewHealPredValues   = ns.partyPvHealPredValues
    ns.previewReducedMaxHealth = ns.partyPvReducedMaxHealth
    previewRoles       = ns._partyPvRoles
    previewClassTokens = ns._partyPvCT

    ApplyPreviewData(f, index)

    -- Re-apply BM indicators with the party proxy so Auto Resize scales the
    -- preview indicators/auras live. CreatePreviewFrame applies them only once
    -- (at creation, with the raid proxy), so without this the party preview
    -- would never reflect the party scale. Index 1 matches the creation call.
    if f._bmIconPool and ns.BM_ApplyPreviewIndicators then
        ns.BM_ApplyPreviewIndicators(f, 1, ns._scaledPartyProxy)
    end

    -- Restore everything
    ns._previewSettingsOverride = nil
    s.frameWidth  = origW
    s.frameHeight = origH
    for i = 1, 5 do
        previewHealthValues[i] = origHealth[i]
        previewPowerValues[i]  = origPower[i]
    end
    ns.previewAbsorbValues     = origAbsorb
    ns.previewHealAbsorbValues = origHA
    ns.previewHealPredValues   = origHP
    ns.previewReducedMaxHealth = origRMH
    previewRoles       = origRoles
    previewClassTokens = origCT

    -- Party Frames kit: bar rects, art, spots and a mock portrait, after the
    -- restore above (nothing here may run inside that swap window).
    if f.kit then
        -- Forced: the refresh above re-laid the bars out at the box's edges.
        ns.RF_ApplyPartyKit(f, f, ns._scaledPartyProxy, nil, true)
        local roles = ns._partyPvRoles
        -- (Greyed only while the preview actually shows that slot offline.)
        ns.RF_KitPreviewPortrait(f, ns._partyPvCT[index],
            index == (roles._playerSlot or 1),
            ns._indicatorsVisible ~= false and index == roles._offlineSlot)
    elseif ns.RF_PtPreview then
        -- Party portrait: the frame takes the box width, the bars move beside
        -- the portrait, then a mock paint (same slots as the kit's).
        local roles = ns._partyPvRoles
        ns.RF_PtPreview(f, ns._scaledPartyProxy, ns._partyPvCT[index],
            index == (roles._playerSlot or 1),
            ns._indicatorsVisible ~= false and index == roles._offlineSlot)
    end
end

-- Party overlay container (separate from raid overlay). Position is hardcoded
-- (see RefreshPartyPreview) -- not draggable, nothing saved to the profile.
ns._partyOC = nil

local function GetOrCreatePartyOverlayContainer()
    if ns._partyOC then return ns._partyOC end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    local bg = oc:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    oc._bg = bg

    -- Centered title at the top of the preview. Font/text/color/visibility are
    -- (re)applied each refresh in RefreshPartyPreview after ApplyFont (a
    -- fontstring with no font set errors on SetText).
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", oc, "TOP", 0, -7)
    oc._title = title

    ns._partyOC = oc
    return oc
end

local function RefreshPartyPreview()
    if not ns._partyPvActive then return end
    if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    -- Recompute party indicator/aura scale before applying preview data so the
    -- party preview reflects Auto Resize live (preview reads _scaledPartyProxy).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local s = ns._pvOverlayProxy or db.profile
    local pw, ph, pcs = ns.RF_PartyDims(s)
    local w, h, spacing = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)
    -- Party target frames along the stack open the frames' pitch, as on the real frames.
    local pitch = spacing + ns.PT_AlongPitch(s, s.partyShowTargets == true)
    local mode = db.profile.previewMode or "overlay"

    BuildPartyPreviewRoles()

    -- "Hide Self": mirror the real party frames (showPlayer=false) by hiding the
    -- player's preview frame and reflowing the remaining members to fill the gap.
    -- The player's slot is whatever BuildPartyPreviewRoles resolved it to after
    -- Sort By + Self First/Last (NOT assumed to be slot 1).
    local hideSelf = s.partyHideSelf
    local playerSlot = ns._partyPvRoles._playerSlot or 1
    local shownCount = hideSelf and 4 or 5

    local isOverlay = (mode == "overlay")
    local anchorPad = isOverlay and 10 or 0
    local topExtra = isOverlay and 25 or 0   -- top space for the centered "Preview" title
    local unitGrowth = ns._PartyGrowth(s)
    local isVert = (unitGrowth == "DOWN" or unitGrowth == "UP")
    local totalW, totalH
    if isVert then
        totalW = w
        totalH = h * shownCount + pitch * (shownCount - 1)
    else
        totalW = w * shownCount + pitch * (shownCount - 1)
        totalH = h
    end

    -- Pets (Show Pets on the Party tab) beside the party frames, or beside each frame (Beside
    -- Owner), and the party target frames beside each frame (after Beside Owner pets on their
    -- side; pets beside the party frames clear them); the overlay grows to hold them.
    local ptSpec = ns.PT_PreviewSpec(s, w, h)
    local petSpec = isOverlay and ns.PF_PreviewSpec(true, s, w, h, spacing, totalW, totalH, ptSpec)
    if ptSpec and petSpec and petSpec.owner then ptSpec = ns.PT_PreviewSpec(s, w, h, petSpec) end
    local padL, padT, padR, padB = 0, 0, 0, 0
    if petSpec and petSpec.owner then
        padL, padT, padR, padB = petSpec.padL, petSpec.padT, petSpec.padR, petSpec.padB
    elseif petSpec then
        padL = math.max(0, -petSpec.ox)
        padT = math.max(0, petSpec.oy)
        padR = math.max(0, petSpec.ox + petSpec.bw - totalW)
        padB = math.max(0, petSpec.bh - petSpec.oy - totalH)
    end
    if isOverlay and ptSpec then
        padL, padT = math.max(padL, ptSpec.padL), math.max(padT, ptSpec.padT)
        padR, padB = math.max(padR, ptSpec.padR), math.max(padB, ptSpec.padB)
    end
    -- Your own frame's target shows only with Include Own Target.
    local ptSkip = (not s.partyTargetIncludeSelf) and playerSlot or nil

    -- Determine parent frame: overlay container for overlay, UIParent for real
    local parentFrame
    if isOverlay then
        GetOrCreatePartyOverlayContainer()
        parentFrame = ns._partyOC
    else
        parentFrame = UIParent
        if ns._partyOC then ns._partyOC:Hide() end
    end

    local slot = 0  -- running layout position; skips the hidden player frame
    local lastF     -- the last frame along the growth
    for i = 1, 5 do
        local f = GetOrCreatePartyPvFrame(i)
        if hideSelf and i == playerSlot then
            f:Hide()
        else
            lastF = f
            if f:GetParent() ~= parentFrame then f:SetParent(parentFrame) end
            f:SetFrameStrata(isOverlay and "FULLSCREEN_DIALOG" or "HIGH")
            f:ClearAllPoints()
            if isVert then
                local yOff = slot * (h + pitch)
                if unitGrowth == "DOWN" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad + padL, -anchorPad - topExtra - padT - yOff)
                else
                    -- UP fills the same box from the bottom upward (positive
                    -- offsets); the container's extra top height creates the
                    -- title gap, so no per-frame correction is needed here.
                    f:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", anchorPad + padL, anchorPad + padB + yOff)
                end
            else
                local xOff = slot * (w + pitch)
                if unitGrowth == "LEFT" then xOff = -xOff end
                if unitGrowth == "RIGHT" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad + padL + xOff, -anchorPad - topExtra - padT)
                else
                    f:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -anchorPad - padR + xOff, -anchorPad - topExtra - padT)
                end
            end
            ApplyPartyPreviewData(f, i)
            f:Show()
            slot = slot + 1
        end
    end

    -- Size and position overlay container
    if isOverlay and ns._partyOC then
        ns._partyOC:SetSize(totalW + padL + padR + anchorPad * 2,
            totalH + padT + padB + anchorPad * 2 + topExtra)
        ns._partyOC:SetFrameStrata("FULLSCREEN_DIALOG")
        ns._partyOC:SetFrameLevel(10)
        if ns._partyOC._title then
            ApplyFont(ns._partyOC._title, 13)
            ns._partyOC._title:SetText("Preview")
            ns._partyOC._title:SetTextColor(1, 1, 1, 0.9)
            ns._partyOC._title:Show()
        end
        -- Hardcoded default position (not draggable, not saved): docked to the
        -- left edge of the options panel, screen center as a fallback.
        ns._partyOC:ClearAllPoints()
        local sf = EllesmereUI._scrollFrame
        if sf then
            ns._partyOC:SetPoint("BOTTOMRIGHT", sf, "BOTTOMLEFT", 0, 0)
        else
            ns._partyOC:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        ns._partyOC:Show()
        -- Styled from the party settings, as the preview's own frames are.
        if petSpec and petSpec.owner then
            ns.PF_ShowOwnerPreview(petSpec, ns._scaledPartyProxy, ns._partyOC, lastF)
        elseif petSpec then
            ns.PF_ShowPreview(petSpec, ns._scaledPartyProxy, ns._partyOC, ns._partyOC,
                anchorPad + padL + petSpec.ox, -anchorPad - topExtra - padT + petSpec.oy)
        else
            ns.PF_HidePreview()
        end
        ns.PT_ShowPreview(ptSpec, s, ns._partyOC, ptSkip)
    end

    -- Real mode: anchor frames to the actual party container, mirroring the
    -- real layout's basePoint logic (_PositionPartySlots). Slot 0 sits at the
    -- container corner the growth direction moves AWAY from, so Flip Frame
    -- Growth keeps the stack bounded by the container instead of growing past
    -- it. A plain TOPLEFT anchor misaligned the flipped preview by a full
    -- stack height/width versus the edit-mode location.
    if mode == "real" and ns._partyContainerFrame then
        local pos = s.partyUnlockPos
        -- Editing an override with a custom unlock mode: anchor the preview at the
        -- LAYER's recorded party-container position (a lightweight proxy frame stands
        -- in for the real container, which sits at the REAL spec's position).
        local anchorTo = ns._partyContainerFrame
        local se = ns._PvSessionElem and ns._PvSessionElem("RF_PartyFrames")
        if se and se.point then
            local proxy = ns._pvSessionPartyAnchor
            if not proxy then
                proxy = CreateFrame("Frame", nil, UIParent)
                ns._pvSessionPartyAnchor = proxy
            end
            proxy:SetSize(ns._partyContainerFrame:GetSize())
            proxy:ClearAllPoints()
            proxy:SetPoint(se.point, UIParent, se.relPoint or se.point,
                PixelSnap(se.x or 0), PixelSnap(se.y or 0))
            anchorTo = proxy
            pos = pos or se
        end
        local cw, ch = anchorTo:GetSize()
        local realPets = ns.PF_PreviewSpec(true, s, w, h, spacing, cw, ch, ptSpec)
        if realPets and realPets.owner then
            ns.PF_ShowOwnerPreview(realPets, ns._scaledPartyProxy, UIParent, lastF)
        elseif realPets then
            ns.PF_ShowPreview(realPets, ns._scaledPartyProxy, UIParent, anchorTo, realPets.ox, realPets.oy)
        else
            ns.PF_HidePreview()
        end
        if ptSpec and realPets and realPets.owner then ptSpec = ns.PT_PreviewSpec(s, w, h, realPets) end
        ns.PT_ShowPreview(ptSpec, s, UIParent, ptSkip)
        if pos then
            local stepX, stepY = 0, 0
            local basePoint = "TOPLEFT"
            if unitGrowth == "RIGHT" then
                stepX = w + pitch
            elseif unitGrowth == "LEFT" then
                stepX = -(w + pitch); basePoint = "TOPRIGHT"
            elseif unitGrowth == "UP" then
                stepY = h + pitch; basePoint = "BOTTOMLEFT"
            else -- DOWN
                stepY = -(h + pitch)
            end
            -- Centered growth: mirror _PositionPartySlots, which shifts the stack by
            -- (5 - shown)/2 slots so the shown frames sit centered in the 5-slot
            -- container. The preview always shows a full party, so shown is 5, or 4
            -- with Hide Self (the real layout subtracts the hidden self the same way).
            local centerShift = 0
            if s.partyFlipGrowth == "centered" then
                centerShift = (5 - shownCount) / 2
            end
            local cShiftX = PixelSnap(stepX * centerShift)
            local cShiftY = PixelSnap(stepY * centerShift)
            local idx = 0  -- running position; skips the hidden player frame
            for i = 1, 5 do
                local f = ns._partyPvFrames[i]
                if f then
                    if hideSelf and i == playerSlot then
                        f:Hide()
                    else
                        f:ClearAllPoints()
                        f:SetPoint(basePoint, anchorTo, basePoint,
                            PixelSnap(stepX * idx) + cShiftX, PixelSnap(stepY * idx) + cShiftY)
                        idx = idx + 1
                    end
                end
            end
        end
    end

end

local function ShowPartyPreview()
    -- See ShowPreview: never engage the preview (which reparents the real
    -- containers under a hidden frame) unless the options window is open and we
    -- are out of combat. Guards against deferred post-close ShowPartyPreview.
    if not ns._testMode and not (EllesmereUI:IsShown()) then return end
    if InCombatLockdown() then return end
    -- Kill any active size preview
    if ns._sizePreviewTier then
        ns._sizePreviewTier = nil
        if ns._HideSizePreview then ns._HideSizePreview() end
    end
    if ns._partyPvActive then
        RefreshPartyPreview()
        return
    end
    local mode = db.profile.previewMode or "overlay"
    if mode == "none" then return end

    ns._partyPvActive = true
    -- Hide the real containers via alpha (combat-reversible); see ShowPreview.
    -- Never reparent secure-header containers (the restore would be blocked in
    -- combat and strand the frames for the whole pull).
    ns._SetRealFramesPreviewHidden(true)
    if mode == "overlay" then
        GetOrCreatePartyOverlayContainer()
    end
    InitPartyPreviewHealthValues()
    BuildPartyPreviewRoles()
    RefreshPartyPreview()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on in-panel tab swaps where another preview shows on the
-- next frame -- restoring here would flash the real frames for one frame before
-- the deferred ShowPreview re-hides them. Panel close restores explicitly.
local function HidePartyPreview(skipRestore)
    if not ns._partyPvActive then return end
    -- Stop the aura ticker while still party-active so it clears the party aura
    -- icons (PvFrames resolves to the party set here), then deactivate.
    StopPvAuraTicker()
    ns._partyPvActive = false
    for i = 1, 5 do
        if ns._partyPvFrames[i] then ns._partyPvFrames[i]:Hide() end
    end
    if ns._partyOC then ns._partyOC:Hide() end
    ns.PF_HidePreview()
    ns.PT_HidePreview()
    if skipRestore then return end
    -- The containers were only alpha-hidden (never reparented or moved); restore
    -- is a combat-legal SetAlpha(1) plus dropping the mouse blockers. See
    -- HidePreview. No combat gate, no SetParent/SetPoint, no ns._restorePending.
    ns._SetRealFramesPreviewHidden(false)
    if not InCombatLockdown() then
        LayoutGroups()
        if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

ns.ShowPartyPreview = ShowPartyPreview
ns.HidePartyPreview = HidePartyPreview
ns.partyPvActive = function() return ns._partyPvActive end
ns.ResetPartyPreviewRandomization = function()
    ns._partyPvRoles._randomized = nil
    ns._partyPvInit = false
end

-- Guaranteed restore invariant. Ensures both real containers are parented to UIParent
-- and their visibility recomputed whenever no preview should be active (e.g. the
-- options panel just closed). Heals the "frames stuck hidden under the preview parent"
-- case even when the preview flags were left false by a skip-restore tab swap or a
-- post-close deferred ShowPreview. Defers to PLAYER_REGEN_ENABLED in combat
-- (reparenting secure-header containers is a protected action).
function ns.EnsureRealFramesRestored()
    if not containerFrame then return end
    -- Tear down any genuinely-active preview FIRST. HidePreview/HidePartyPreview
    -- now restore container alpha and drop the mouse blockers via combat-legal
    -- ops only (SetAlpha on our containers; Hide/SetParent on our own non-secure
    -- preview frames), so they never defer anything.
    if previewActive then HidePreview() end
    if ns._partyPvActive then HidePartyPreview() end
    -- Hard guarantee: force both real containers fully opaque and drop any mouse
    -- blockers, unconditionally. SetAlpha is not protected, so this is valid in
    -- combat and heals the "left alpha-hidden with the flags already false" cases
    -- (skip-restore tab swap, combat-cancelled deferred Show). The containers are
    -- never reparented or moved anymore, so nothing protected needs deferral.
    ns._SetRealFramesPreviewHidden(false)
    -- The layout/visibility recompute below SetPoints/Shows secure headers, so
    -- out of combat only. The alpha restore above already makes the frames
    -- visible during combat.
    if InCombatLockdown() then return end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

-- Fade out overlay previews when entering unlock mode
do
    local FADE_DUR = 0.1
    local function FadeOutFrame(frame)
        if not frame or not frame:IsShown() then return end
        local startAlpha = frame:GetAlpha()
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= FADE_DUR then
                self:SetAlpha(0)
                self:Hide()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(startAlpha)
                return
            end
            self:SetAlpha(startAlpha * (1 - elapsed / FADE_DUR))
        end)
    end
    _G._ERF_UnlockModeOpen = function()
        FadeOutFrame(overlayContainer)
        FadeOutFrame(ns._partyOC)
    end
end

