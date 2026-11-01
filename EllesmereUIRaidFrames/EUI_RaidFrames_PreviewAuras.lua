if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewAuras.lua
--
--  The preview aura cycling: the active-preview resolvers, the effective-value
--  overlay, and the ticker that places fake debuffs and defensives.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._previewInternals
-- EUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs        = pairs
local ipairs       = ipairs
local wipe         = wipe
local type         = type
local C_Timer               = C_Timer

local RF = ns._internals -- the table of the Raid Frames chain
local PixelSnap = RF.PixelSnap

local previewClassTokens, previewFrames = I.previewClassTokens, I.previewFrames

-- Shared state from the raid-frame and preview chains.
local db
RF.dbSetters[#RF.dbSetters + 1] = function(v) db = v end
local previewActive = false
I.previewActiveSetters[#I.previewActiveSetters + 1] = function(v) previewActive = v end

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
-- Class tokens for icon selection: ApplyPartyPreviewData hands the party tokens
-- to ApplyPreviewData only, so the ticker must resolve them itself.
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
--  live/override stores.
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
    if auraType == "def" then
        ns.RFC_PreviewAuraBorder(icon, icon._borderFrame, s2, "defBorder")
    else
        ns.RFC_PreviewAuraBorder(icon, icon._borderFrame, s2, "debuffBorder")
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
                    ns.RFC_PreviewAuraBorder(icon, icon._borderFrame, s2, "debuffBorder")
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

I.PvActive, I.PvAuraReanchorFrame, I.PvFrames = PvActive, PvAuraReanchorFrame, PvFrames
I.PvSettings, I.StartPvAuraTicker = PvSettings, StartPvAuraTicker
I.StopPvAuraTicker = StopPvAuraTicker
I.broken = false
