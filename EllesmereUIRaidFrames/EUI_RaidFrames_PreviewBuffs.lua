if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewBuffs.lua
--
--  The preview buff ticker (test mode) and the refresh of the preview aura
--  visuals.
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
local C_Timer               = C_Timer

local PixelSnap = ns._internals.PixelSnap

local previewFrames, PvActive = I.previewFrames, I.PvActive
local PvAuraReanchorFrame, PvFrames = I.PvAuraReanchorFrame, I.PvFrames
local PvSettings, StartPvAuraTicker = I.PvSettings, I.StartPvAuraTicker
local StopPvAuraTicker = I.StopPvAuraTicker

local previewActive = false
I.previewActiveSetters[#I.previewActiveSetters + 1] = function(v) previewActive = v end

-------------------------------------------------------------------------------
--  Preview Buff Ticker (test mode only: cycles configured buffs across frames)
-------------------------------------------------------------------------------
ns._pvBuffTicker = nil
ns._pvBuffAssignments = {}

local function GetConfiguredBuffSpells()
    -- The Buff Manager groups the live raid frames render for the player's
    -- spec (every bucket it draws from, Show In and per-spec disables applied,
    -- spell unions resolved), at the live frames' size.
    local indicators = ns.BM2_SpecIndicators and ns.BM2_SpecIndicators("raid")
    if not indicators then return {} end
    local iscale = ns._bmScale or 1
    local spells = {}
    local seen = {}
    for _, ind in ipairs(indicators) do
        if ind.enabled and ind.spells and (ind.type == "icon" or ind.type == "square") then
            for _, sid in ipairs(ind.spells) do
                if not seen[sid] then
                    seen[sid] = true
                    local iconTex
                    if ind.type == "icon" then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                        iconTex = info and info.iconID or 136243
                    end
                    spells[#spells + 1] = {
                        id = sid, icon = iconTex,
                        indType = ind.type,
                        color = (ind.spellColors and ind.spellColors[sid]) or ind.color,
                        size = ns.RFC_BmSize(ind, iscale),
                        position = ind.position or "TOPLEFT",
                        offsetX = ind.offsetX or 0,
                        offsetY = ind.offsetY or 0,
                        growDirection = ind.growDirection or "RIGHT",
                        spacing = ind.spacing or 0,
                        indicator = ind,
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
    ns.RFC_PreviewAuraBorder(icon, icon._borderFrame, spellInfo.indicator, "indBorder")

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
    local _pvFrames = PvFrames()
    local _reanchor = ns._PvAuraReanchorFrame
    local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

    local dbZ = s2.debuffIconZoom or 0.08
    local defZ = s2.defIconZoom or 0.08
    local dbShowSwipe = s2.debuffShowSwipe ~= false
    local dbShowDurText = s2.debuffShowDurText
    local dbDtC = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
    local dbDtSz = s2.debuffDurTextSize or 8
    local dbDtOX = s2.debuffDurTextOffsetX or 0
    local dbDtOY = s2.debuffDurTextOffsetY or 0
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
                    ns.RFC_PreviewAuraBorder(ic, ic._borderFrame, s2, "debuffBorder")
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
                    ns.RFC_PreviewAuraBorder(ic, ic._borderFrame, s2, "defBorder")
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

I.broken = false
