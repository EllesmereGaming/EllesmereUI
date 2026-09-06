if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_UnitFrames_WeaponEnchants.lua
-- Weapon oils/imbues are temporary weapon ENCHANTS, not auras: nothing with
-- a spell ID ever exists on the player (the API struct carries an enchantID,
-- an item-enchant identifier), so the engine aura containers behind the
-- Player Aura Bars Buffs bar and the player unit frame's buffs can never
-- render them -- containers only render auras that exist in the aura stream.
-- Blizzard's own BuffFrame hand-injects "TempEnchant" buttons in Lua for the
-- same reason (and may read secrets untainted; we cannot copy that path).
--
-- Integration model -- first-class citizens of BOTH displays:
--   * IN-GRID CELLS: while N enchants are active, the display's engine
--     container is SHIFTED inward by N cells (the producers own that shift;
--     this file exposes ns.WeaponEnchants_Count and pokes them on change),
--     and the enchant buttons occupy the bar's actual first cells -- main
--     hand adjacent to the run, Blizzard's temp-enchants-first ordering.
--     No oils = zero shift = byte-identical layout.
--   * LIVE STYLE: buttons render from the display's own AK.styles table and
--     speak both style dialects (PAB BuildStyle and the unit-frame
--     BuildStyle: texCoord rect vs iconCrop/iconZoom, cdText* vs duration*,
--     stackPos vs stackPoint, noTooltips) -- customizations follow
--     automatically.
--   * FILTER SEMANTICS: producers publish a record only while their
--     broad-content mode admits generic duration buffs (All Buffs OR Has
--     Duration on); curated-only configs render and shift nothing.
--   * TOOLTIP + CANCEL: the inventory-item tooltip mirrors Blizzard's
--     TempEnchant button (GameTooltip:SetInventoryItem -- item data only
--     GameTooltip can render, same pattern as Bags). PAB buttons cancel on
--     right-click through the SECURE path: CancelTemporaryEnchantment is
--     hard-protected for addon code (ADDON_ACTION_FORBIDDEN), so the PAB
--     trio are SecureActionButtons with type2="cancelaura" +
--     target-slot2=<fixed slot>, which SECURE_ACTIONS.cancelaura resolves
--     to the protected call engine-side. UF buttons never cancel (spec).
--
-- COMBAT MODEL (the secure trio cannot be moved/shown/hidden/re-attributed
-- in lockdown): each PAB button is SLOT-FIXED (attributes set once at
-- creation), pre-warmed shown at alpha 0 out of combat, and in-combat
-- transitions touch only alpha + content (icon/cooldown/texts -- all legal
-- on protected frames). Geometry, mouse flags and the producers' container
-- shifts are deferred to PLAYER_REGEN_ENABLED, then one full pass repacks.
--
-- Secrecy: GetTemporaryEnchantmentInfo's returns carry NO Secret* flags in
-- the generated API docs (equipment state, not unit-aura data) -- plain
-- numbers in restricted combat too.
--
-- Cost model: WEAPON_ENCHANT_CHANGED / WEAPON_SLOT_CHANGED (the pair
-- Blizzard's BuffFrame registers) are the only wake-ups, registered only
-- while a display publishes a record; the duration text runs on a shared
-- 0.5s ticker that exists ONLY while an enchant button is visible.
--
-- Producer records (nil = display inactive/filtered), poked via
-- ns.WeaponEnchants_Layout():
--   ns._weaponEnchPAB = { parent, corner, dir, pad, styleKey, canCancel }
--   ns._weaponEnchUF  = { frame, ia, fp, x, y, gX, pad, styleKey }

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

local SLOTS = { INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17, INVSLOT_RANGED or 18 }

local hosts = {}   -- "pab"/"uf" -> { frame, buttons = {}, rec }
local evFrame, regenFrame, textTicker
local activeInfos, activeCount = {}, 0   -- packed active list (MH first)
local activeBySlot = {}                  -- slot -> info

-- Raw active-enchant count. Producers gate on their own record/filters and
-- shift their container inward by this many cells.
function ns.WeaponEnchants_Count()
    return activeCount
end

local function Style(rec)
    local AK = EllesmereUI.AuraKit
    return (AK and AK.styles and rec and AK.styles[rec.styleKey]) or nil
end

local function OnButtonEnter(self)
    if self._noTooltip or not self._slot then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetInventoryItem("player", self._slot)
end

local function OnButtonLeave()
    GameTooltip:Hide()
end

-- host.secure: SecureActionButton trio, one per SLOT, cancel wired once at
-- creation (attribute writes are combat-blocked, so nothing is ever
-- re-attributed). Insecure hosts get plain frames.
local function MakeButton(host, index)
    local b
    if host.secure then
        b = CreateFrame("Button", nil, host.frame, "SecureActionButtonTemplate")
        b:SetAttribute("type2", "cancelaura")
        b:SetAttribute("target-slot2", SLOTS[index])
        -- BOTH phases: with the press-and-hold cvar (ActionButtonUseKeyDown,
        -- default on) the secure handler executes on the DOWN click and
        -- ignores the up -- an up-only registration never fires at all. The
        -- handler runs exactly one cvar-selected phase, so no double-fire.
        b:RegisterForClicks("RightButtonDown", "RightButtonUp")
    else
        b = CreateFrame("Frame", nil, host.frame)
    end
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    b.icon = icon
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetHideCountdownNumbers(true) -- duration text is ours, styled below
    b.cd = cd
    -- Text rides its own frame ABOVE the cooldown: FontStrings on the button
    -- itself render UNDER the Cooldown child frame's swipe.
    local tf = CreateFrame("Frame", nil, b)
    tf:SetAllPoints()
    tf:SetFrameLevel(cd:GetFrameLevel() + 5)
    b.duration = tf:CreateFontString(nil, "OVERLAY")
    b.charges = tf:CreateFontString(nil, "OVERLAY")
    b:SetScript("OnEnter", OnButtonEnter)
    b:SetScript("OnLeave", OnButtonLeave)
    return b
end

-- Mirrors the display's live style onto one of our buttons; the texcoord
-- cascade is AK ApplyStyleToRegions' exact order. Called out of combat only
-- for the secure trio (SetSize is geometry).
local function ApplyStyle(b, style)
    local w = style.width or 32
    b:SetSize(w, style.height or w)
    local tc = style.texCoord
    if tc then
        b.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    elseif style.iconCrop then
        local z = style.iconZoom or 0.07
        b.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    else
        b.icon:SetTexCoord(0, 1, 0, 1)
    end
    local PP = EllesmereUI.PP
    local bd = style.border
    if bd and PP then
        if not b._bdr then
            b._bdr = CreateFrame("Frame", nil, b)
            b._bdr:SetAllPoints()
            b._bdr:EnableMouse(false)
        end
        b._bdr:SetFrameLevel(bd.behind
            and math.max(0, b:GetFrameLevel() - 1)
            or (b.cd:GetFrameLevel() + 1))
        EllesmereUI.ApplyBorderStyle(b._bdr, bd.textureSize or bd.size or 1,
            bd[1] or 0, bd[2] or 0, bd[3] or 0, bd[4] or 1,
            bd.texture or "solid", bd.offsetX, bd.offsetY, bd.shiftX, bd.shiftY,
            bd.addonKey or "unitframes", bd.sizeKey or bd.size or 1)
    elseif b._bdr then
        if EllesmereUI.HideBorderStyle then EllesmereUI.HideBorderStyle(b._bdr) end
        b._bdr:Hide()
    end
    b.cd:SetReverse(style.cooldownReverse ~= false)
    b.cd:SetDrawEdge(style.cooldownDrawEdge == true)
    b.cd:SetShown(style.hideSwipe ~= true)

    local path = style.fontPath or STANDARD_TEXT_FONT
    local flag = style.fontFlag or "OUTLINE"
    if style.hideDurationText then
        b.duration:Hide()
    else
        if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(b.duration, flag == "") end
        b.duration:SetFont(path, style.durationFontSize or style.cdTextSize or 11, flag)
        b.duration:ClearAllPoints()
        b.duration:SetPoint(style.durationPoint or "CENTER", b,
            style.durationRelPoint or "CENTER",
            style.durationX or style.cdOffX or 0,
            style.durationY or style.cdOffY or 0)
        local c = style.durationColor or style.cdTextColor
        b.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        b.duration:Show()
    end
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(b.charges, flag == "") end
    b.charges:SetFont(path, style.stackFontSize or style.stackSize or 11, flag)
    b.charges:ClearAllPoints()
    local sp = style.stackPoint or style.stackPos or "BOTTOMRIGHT"
    b.charges:SetPoint(sp, b, sp,
        style.stackX or style.stackOffX or 0,
        style.stackY or style.stackOffY or 0)
    local sc = style.stackColor
    b.charges:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
end

-- Compact house duration format matching the engine aura text: bare seconds
-- under a minute (with the unit when the style's Show S for Seconds is on),
-- m/h above.
local function FormatRemaining(sec, showS)
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60 + 0.5)) end
    return string.format(showS and "%ds" or "%d", math.floor(sec + 0.5))
end

local function UpdateTexts()
    local now = GetTime()
    local anyShown = false
    for _, host in pairs(hosts) do
        local st = Style(host.rec)
        local showS = st and st.durationShowSeconds
        for _, b in pairs(host.buttons) do
            if b:IsShown() and b:GetAlpha() > 0 then
                anyShown = true
                if b._expire and b.duration:IsShown() then
                    local rem = b._expire - now
                    if rem > 0 then
                        b.duration:SetText(FormatRemaining(rem, showS))
                    else
                        b.duration:SetText("")
                    end
                end
            end
        end
    end
    if not anyShown and textTicker then
        textTicker:Cancel()
        textTicker = nil
    end
end

local function EnsureTicker(want)
    if want and not textTicker then
        textTicker = C_Timer.NewTicker(0.5, UpdateTexts)
    elseif not want and textTicker then
        textTicker:Cancel()
        textTicker = nil
    end
end

local function ReadEnchants()
    local n = 0
    for k in pairs(activeBySlot) do activeBySlot[k] = nil end
    for i = 1, #SLOTS do
        local info = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
            and C_PaperDollInfo.GetTemporaryEnchantmentInfo(SLOTS[i])
        if info and info.hasExpirationTime then
            n = n + 1
            activeInfos[n] = { slot = SLOTS[i], slotIndex = i, info = info }
            activeBySlot[SLOTS[i]] = info
        end
    end
    for i = n + 1, #activeInfos do activeInfos[i] = nil end
    activeCount = n
end

-- Fills one button's CONTENT (legal on protected frames in combat).
local function PaintContent(b, slot, info)
    b.icon:SetTexture(GetInventoryItemTexture("player", slot))
    local remaining = (info.remainingTimeMs or 0) / 1000
    b._expire = GetTime() + remaining
    b.cd:SetCooldown(GetTime(), remaining)
    local ch = info.chargesRemaining or 0
    if ch > 1 then b.charges:SetText(ch); b.charges:Show()
    else b.charges:Hide() end
    b._slot = slot
end

local function Paint()
    local n = activeCount
    local combat = InCombatLockdown()
    local anyShown = false
    for _, host in pairs(hosts) do
        local rec = host.rec
        local style = Style(rec)
        if host.secure then
            -- Slot-fixed secure trio. The host frame and every button stay
            -- PERMANENTLY SHOWN once created (Show/Hide on the buttons OR on
            -- any ancestor of them is combat-blocked); visibility rides
            -- button alpha exclusively. Out of combat: full geometry/style
            -- pass; in combat: alpha + content only. Cells pack active slots
            -- with MAIN HAND adjacent to the engine run.
            local active = rec and style or nil
            local cellIndex = {}
            if active then
                local ci = n - 1
                for i = 1, #SLOTS do
                    if activeBySlot[SLOTS[i]] then
                        cellIndex[i] = ci
                        ci = ci - 1
                    end
                end
            end
            local usedCells = {}
            for i = 1, #SLOTS do
                local b = host.buttons[i]
                if not b and not combat and active then
                    b = MakeButton(host, i)
                    b:Show() -- pre-warmed forever; visibility rides alpha
                    host.buttons[i] = b
                end
                if b then
                    local info = active and activeBySlot[SLOTS[i]] or nil
                    if not combat then
                        if active then
                            local w = style.width or 32
                            local cell = w + (rec.pad or 0)
                            ApplyStyle(b, style)
                            local idx = cellIndex[i] or 0
                            local dir = rec.dir or "LEFT"
                            local dx, dy = 0, 0
                            if dir == "RIGHT" then dx = 1 elseif dir == "LEFT" then dx = -1
                            elseif dir == "UP" then dy = 1 elseif dir == "DOWN" then dy = -1 end
                            b:ClearAllPoints()
                            local point = rec.point or rec.corner
                            b:SetPoint(point, rec.anchorTo or rec.parent, rec.relativePoint or rec.corner or point,
                                (rec.x or 0) + dx * idx * cell,
                                (rec.y or 0) + dy * idx * cell)
                            b._cell = idx
                            b._noTooltip = style.noTooltips == true
                        end
                        b:EnableMouse(info and true or false)
                    end
                    if info then
                        PaintContent(b, SLOTS[i], info)
                        -- In combat positions are frozen: a button whose
                        -- last-packed cell now belongs to the shifted engine
                        -- run (or to another enchant) goes alpha 0 instead
                        -- of overlapping; the regen pass repacks everything.
                        local cellBad = combat and (b._cell == nil
                            or b._cell > n - 1 or usedCells[b._cell])
                        if cellBad then
                            b:SetAlpha(0)
                        else
                            if combat then usedCells[b._cell] = true end
                            b:SetAlpha(1)
                            anyShown = true
                        end
                    else
                        b:SetAlpha(0)
                    end
                end
            end
        elseif rec and style and n > 0 then
            -- Insecure host (UF): packed dynamic buttons, plain frames.
            local w = style.width or 32
            local cell = w + (rec.pad or 0)
            for i = 1, n do
                local b = host.buttons[i]
                if not b then b = MakeButton(host, i); host.buttons[i] = b end
                ApplyStyle(b, style)
                local idx = n - i -- main hand (i=1) adjacent to the run
                local sign = (rec.gX == "RIGHT") and 1 or -1
                b:ClearAllPoints()
                b:SetPoint(rec.ia, rec.frame, rec.fp,
                    rec.x + sign * idx * cell, rec.y)
                PaintContent(b, activeInfos[i].slot, activeInfos[i].info)
                b._noTooltip = style.noTooltips == true
                b:EnableMouse(not b._noTooltip)
                b:SetAlpha(1)
                b:Show()
                anyShown = true
            end
            for i = n + 1, #host.buttons do host.buttons[i]:Hide() end
            host.frame:Show()
        elseif host.frame then
            host.frame:Hide()
        end
    end
    EnsureTicker(anyShown)
    if anyShown then UpdateTexts() end
end

-- Count changes re-anchor the displays (their containers shift inward by
-- the new count). Container re-seating is combat-legal and runs IMMEDIATELY
-- (the engine run repositions live); only the SECURE trio's geometry is
-- lockdown-blocked, so in combat PAB takes the minimal container-only path
-- (the full ApplyLiveConfig would trip the anchor-poisoned parent:SetSize)
-- and a regen pass repacks the buttons afterward.
local function PokeProducers(combat)
    if combat then
        if ns.PAB_ReShiftEnchants then ns.PAB_ReShiftEnchants() end
    else
        if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(true) end
    end
    if ns.UF_ReloadAllAuraContainers then ns.UF_ReloadAllAuraContainers() end
end

local function OnRegen(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ReadEnchants()
    PokeProducers(false)
    Paint()
end

local function OnEnchantEvent()
    local prev = activeCount
    ReadEnchants()
    if activeCount ~= prev then
        local combat = InCombatLockdown()
        PokeProducers(combat)
        if combat then
            -- Secure-button geometry can't follow until regen: repack then.
            if not regenFrame then
                regenFrame = CreateFrame("Frame")
                regenFrame:SetScript("OnEvent", OnRegen)
            end
            regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
    Paint()
end

local function LayoutHost(key, rec)
    local host = hosts[key]
    if not rec then
        -- Secure host: never Hide (protected descendants make even the
        -- insecure ancestor's Hide combat-blocked, and the always-shown
        -- model needs no visibility ops at all -- buttons go alpha 0).
        if host then
            host.rec = nil
            if not host.secure then host.frame:Hide() end
        end
        return
    end
    if not host then
        host = { frame = CreateFrame("Frame", nil, UIParent), buttons = {},
            secure = (key == "pab") }
        host.frame:Show()
        hosts[key] = host
    end
    host.rec = rec
    if host.secure and InCombatLockdown() then return end
    -- Parent from rec.parent ONLY -- rec.anchorTo can be an engine aura
    -- container, which carries forbidden aspects
    -- (UntrustedLayoutScriptExecution): SetParent into it hard-errors for
    -- the secure host ("child object would inherit forbidden aspects").
    -- Anchoring is legal, so the host RIDES the container's rect while
    -- living in the plain bar frame's tree.
    local function DoAnchor()
        local r = host.rec
        -- Cleared-rec guard, plus the outer skip mirrored: AuraKit jobs are
        -- combat-runnable, so a job enqueued OOC can drain in lockdown and
        -- these writes on the SECURE host would be blocked actions there.
        -- The rec stays, and the regen relayout heals it like the old skip.
        if not r or (host.secure and InCombatLockdown()) then return end
        host.frame:SetParent(r.parent or r.frame)
        host.frame:ClearAllPoints()
        host.frame:SetAllPoints(r.anchorTo or r.parent or r.frame)
    end
    if host.secure then
        -- Some callers (e.g. Unlock Mode's grow-direction dropdown) reach
        -- here from a live, insecure OnClick handler; anchoring the secure
        -- host straight onto an engine aura container from that stack throws
        -- UntrustedLayoutScriptExecution. AuraKit's own job queue gives the
        -- anchor write a fresh, untainted execution context instead.
        local AK = EllesmereUI.AuraKit
        if AK and AK.QueueLiveBuildJob then
            AK.QueueLiveBuildJob(DoAnchor, "uf:weaponench-anchor")
        else
            DoAnchor()
        end
    else
        DoAnchor()
    end
end

local function EnsureEvents()
    local want = false
    for _, host in pairs(hosts) do
        if host.rec then want = true; break end
    end
    if want then
        if not evFrame then
            evFrame = CreateFrame("Frame")
            evFrame:SetScript("OnEvent", OnEnchantEvent)
        end
        evFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
        evFrame:RegisterEvent("WEAPON_SLOT_CHANGED")
    elseif evFrame then
        evFrame:UnregisterAllEvents()
    end
end

function ns.WeaponEnchants_Layout()
    LayoutHost("pab", ns._weaponEnchPAB)
    LayoutHost("uf", ns._weaponEnchUF)
    EnsureEvents()
    ReadEnchants()
    Paint()
end

-- Producers that loaded (and published) before this file get picked up now;
-- later publishes arrive via their own Layout pokes.
ns.WeaponEnchants_Layout()
