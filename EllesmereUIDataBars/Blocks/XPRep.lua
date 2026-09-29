if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\XPRep.lua
-- XP / reputation bar block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local _G               = _G
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local type             = type
local rawget           = rawget
local floor            = math.floor
local max              = math.max
local min              = math.min

local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf

-------------------------------------------------------------------------------
--  XPREP (XP / Reputation bar)
--  Auto extent here means "reasonable fixed content size" (icon + 120px minimum bar); templates ship this type in pct mode.
-------------------------------------------------------------------------------
ns.BlockFactories.xprep = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_XP_UPDATE", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }

    local _dbFitBuf = { "" }
    local mode = "rep"

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    -- Max-level check with layered fallbacks, matching the Action Bars XP bar's:
    -- the Is* helpers are nil-guarded, so client API churn can silently disable
    -- them -- a plain numeric compare against the expansion max level backstops
    -- the check so XP mode can never show for a max-level character.
    local function XPAtMaxLevel()
        local level = UnitLevel("player") or 0
        if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
        if IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(level) then return true end
        local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
            or (GetMaxPlayerLevel and GetMaxPlayerLevel())
        return (maxLevel and level >= maxLevel) or false
    end

    local function UpdateMode()
        local d = D()
        if d.mode == "xp"  then mode = "xp";  return end
        if d.mode == "rep" then mode = "rep"; return end
        local atMax = XPAtMaxLevel()
        local xpOff = IsXPUserDisabled and IsXPUserDisabled()
        mode = "rep"
        if not atMax and not xpOff then mode = "xp" end
    end

    -- Compat: legacy GetWatchedFactionInfo vs C_Reputation.GetWatchedFactionData.
    local LegacyGetWatchedFactionInfo = rawget(_G, "GetWatchedFactionInfo")
    local C_Rep = C_Reputation
    local function GetWatchedFactionInfoCompat()
        if LegacyGetWatchedFactionInfo then return LegacyGetWatchedFactionInfo() end
        if C_Rep and C_Rep.GetWatchedFactionData then
            local d = C_Rep.GetWatchedFactionData()
            if d then
                return d.name, d.reaction, d.currentReactionThreshold,
                       d.nextReactionThreshold, d.currentStanding, d.factionID
            end
        end
        return nil
    end

    local function GetProgressValues(cur, minV, maxV)
        if type(minV) ~= "number" then minV = 0 end
        if type(maxV) ~= "number" then maxV = minV + 1 end
        if type(cur)  ~= "number" then cur = minV end
        local pCur = cur - minV
        local pMax = maxV - minV
        if pMax <= 0 then
            local n = 1
            if pCur > 0 then n = pCur end
            return n, n, 100
        end
        return pCur, pMax, max(0, min(100, floor((pCur / pMax) * 100)))
    end

    local barButton = CreateFrame("Button", nil, content)
    barButton:SetAllPoints()
    barButton:EnableMouse(true)
    barButton:RegisterForClicks("AnyUp")
    barButton:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" and not InCombatLockdown() then
            local d = D()
            if mode == "xp" then d.mode = "rep" else d.mode = "xp" end
            inst:Refresh()
        end
    end)
    local nameText = content:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, nameText)
    local bar = CreateFrame("StatusBar", nil, content)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local barTrack = content:CreateTexture(nil, "BACKGROUND")
    local restBar = CreateFrame("StatusBar", nil, content)
    restBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    restBar:SetStatusBarColor(0.3, 0.3, 1, 0.5)
    restBar:Hide()

    -- Shared value/label computation. Returns nil when nothing to show.
    local function ComputeState()
        UpdateMode()
        if mode == "xp" then
            -- At the level cap (or with XP gains off) there is no XP. AUTO mode
            -- collapses (return nil) -- but an EXPLICIT d.mode must always render:
            -- nil hides `content`, and barButton is a CHILD of content, so a
            -- collapsed block has no hitbox and the right-click that toggles the
            -- persisted mode back can never fire again -- the block stayed
            -- cleared across reloads (field report 2026-08-13). The placeholder
            -- keeps the block alive and names the way back.
            local atMax = XPAtMaxLevel()
            local xpOff = IsXPUserDisabled and IsXPUserDisabled()
            if atMax or xpOff then
                if D().mode ~= "xp" then return nil end
                return {
                    label = xpOff and "XP Off (Right-Click: Rep)"
                                   or "Max Level (Right-Click: Rep)",
                    minV = 0, maxV = 1, curV = 0,
                    r = 0.5, g = 0.5, b = 0.5, rested = 0,
                }
            end
            local curXP = UnitXP("player") or 0
            local maxXP = UnitXPMax("player") or 1
            if maxXP <= 0 then maxXP = 1 end
            local pct = floor((curXP / maxXP) * 100)
            local level = 0
            if UnitLevel then level = UnitLevel("player") end
            local label = pct .. "% to level " .. (level + 1)
            local ar, ag, ab = ns.GetAccent()
            local rested = GetXPExhaustion() or 0
            return {
                label = label, minV = 0, maxV = maxXP, curV = curXP,
                r = ar, g = ag, b = ab, rested = rested, isXP = true,
            }
        end
        local name, reaction, minV, maxV, curV, factionID = GetWatchedFactionInfoCompat()
        if not name then
            -- Same trap as the XP branch above: collapse only in AUTO mode. The
            -- reported repro is exactly this arm -- right-click on the XP bar
            -- forces d.mode="rep" with no watched faction, and the collapsed
            -- block ate every later click.
            if D().mode ~= "rep" then return nil end
            return {
                label = "No Rep Tracked",
                minV = 0, maxV = 1, curV = 0,
                r = 0.5, g = 0.5, b = 0.5, rested = 0,
            }
        end
        -- Friendship factions (Captain Tokka, Cursed Angler ranks, etc.): the
        -- watched-faction payload returns EQUAL reaction thresholds for these,
        -- which collapsed the range to zero and rendered a permanent 0% with a
        -- nonsense "8,400 / 8,401" tooltip (field report 2026-08-22). The
        -- friendship API carries the real rank window -- same handling as the
        -- Action Bars RepBar. Checked before renown, matching that code path.
        local isFriendship = false
        if factionID and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
            local fi = C_GossipInfo.GetFriendshipReputation(factionID)
            if fi and fi.friendshipFactionID and fi.friendshipFactionID > 0 then
                isFriendship = true
                minV = fi.reactionThreshold or 0
                curV = fi.standing or minV
                if fi.nextThreshold and fi.nextThreshold > minV then
                    maxV = fi.nextThreshold
                else
                    -- Maxed friendship rank: render a full bar.
                    minV, maxV, curV = 0, 1, 1
                end
            end
        end
        -- Major Factions (renown progress)
        if not isFriendship and factionID and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
            local mfd = C_MajorFactions.GetMajorFactionData(factionID)
            if mfd and type(mfd.renownLevelThreshold) == "number" and mfd.renownLevelThreshold > 0 then
                minV = 0; maxV = mfd.renownLevelThreshold; curV = mfd.renownReputationEarned or 0
            end
        end
        if type(minV) == "number" and type(maxV) == "number" and type(curV) == "number" then
            local nMax = maxV - minV
            local nCur = curV - minV
            if nMax > 0 then minV = 0; maxV = nMax; curV = nCur end
        end
        if type(minV) ~= "number" then minV = 0 end
        if type(maxV) ~= "number" then maxV = 1 end
        if type(curV) ~= "number" then curV = 0 end
        if maxV <= minV then maxV = minV + 1 end
        curV = max(minV, min(maxV, curV))
        local _, _, pct = GetProgressValues(curV, minV, maxV)
        local dname = name
        if #name > 20 then dname = name:sub(1, 20) .. "..." end
        local label = dname .. " " .. pct .. "%"
        local cr, cg, cb
        local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if color then cr, cg, cb = color.r, color.g, color.b
        else cr, cg, cb = ns.GetAccent() end
        return {
            label = label, minV = minV, maxV = maxV, curV = curV,
            r = cr, g = cg, b = cb, rested = 0,
        }
    end

    -- Tooltip parity with every other block (clock/FPS/gold): info + the
    -- action rows that document the mode toggle -- the toggle was invisible
    -- without it. Built from the SAME ComputeState the bar renders from, so
    -- the tip can never disagree with the bar (renown/paragon/placeholder
    -- labels all inherit). Built on hover only -- zero idle cost. Wired HERE,
    -- below ComputeState's declaration: at the barButton creation site above
    -- the name would compile as a nil global inside the closure.
    barButton:SetScript("OnEnter", function()
        local state = ComputeState()
        if not state then return end
        local ar, ag, ab = ns.GetAccent()
        ns.Tip_Begin(barButton)
        ns.Tip_AddLine(state.label, 1, 1, 1)
        if state.maxV and state.maxV > 1 then
            local bl = BreakUpLargeNumbers
            ns.Tip_AddDouble(L["PROGRESS"],
                (bl and bl(state.curV) or state.curV) .. " / " .. (bl and bl(state.maxV) or state.maxV),
                0.6, 0.6, 0.6, 1, 1, 1)
        end
        if state.rested and state.rested > 0 then
            local bl = BreakUpLargeNumbers
            ns.Tip_AddDouble(L["RESTED"], (bl and bl(state.rested) or state.rested),
                0.6, 0.6, 0.6, 0.3, 0.3, 1)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["RIGHT_CLICK"],
            mode == "xp" and L["SWITCH_TO_REP"] or L["SWITCH_TO_XP"],
            1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end)
    barButton:SetScript("OnLeave", function()
        ns.Tip_Hide(barButton)
    end)

    function inst:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local isSide = barCtx.IsVertical()
        local textHeight = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))

        local state = ComputeState()
        if not state then
            content:Hide()
            MaybeRelayout(inst)
            return
        end
        content:Show()
        -- Auto-size measure needs the XP-only bar extension (see below).
        inst._xpExtend = (state.isXP and 40) or 0

        -- Block color applies to the label; the bar keeps its accent/faction color.
        do
            local br, bgr, bb = BlockColorOf(blockCfg)
            nameText:SetTextColor(br, bgr, bb, 1)
        end

        restBar:Hide()
        bar:SetStatusBarColor(state.r, state.g, state.b, 1)
        bar:SetMinMaxValues(state.minV, state.maxV)
        bar:SetValue(state.curV)
        if state.rested > 0 then
            restBar:SetMinMaxValues(state.minV, state.maxV)
            restBar:SetValue(min(state.curV + state.rested, state.maxV))
            restBar:Show()
        end

        if isSide then
            -- Vertical branch: stacked label above the bar.
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            _dbFitBuf[1] = state.label
            local fitSize = textHeight
            ns.SetFont(nameText, fitSize, barCfg)
            nameText:SetText(state.label)
            ns.SetWrappedText(nameText, innerW, "CENTER")
            nameText:ClearAllPoints()
            nameText:SetPoint("TOP", content, "TOP", 0, -3)
            local textH = ns.SnapToPixelGrid(nameText:GetStringHeight())
            local bH = 4
            barTrack:ClearAllPoints()
            barTrack:SetPoint("TOP", content, "TOP", 0, -(3 + textH + 3))
            barTrack:SetSize(innerW, bH)
            barTrack:SetColorTexture(1, 1, 1, 0.1)
            bar:ClearAllPoints()
            bar:SetSize(innerW, bH)
            bar:SetPoint("TOP", content, "TOP", 0, -(3 + textH + 3))
            restBar:ClearAllPoints(); restBar:SetAllPoints(bar)
            content:SetSize(slotW, max(3 + textH + 3 + bH + 3, 40))
        else
            local slotW = HBudget(inst, 300)
            slotW = max(slotW, 60)
            local bH = max(2, floor(CONTENT_BASE * 0.2 + 0.5) - 1)

            -- No icon: text on top, bar underneath sharing the left edge, stack centered in the bar height. The bar tracks the TEXT width.
            _dbFitBuf[1] = state.label
            local fitSize = textHeight
            ns.SetFont(nameText, fitSize, barCfg)
            ns.ResetInlineText(nameText, "LEFT")
            nameText:SetText(state.label)

            local textW = nameText:GetStringWidth() or 0
            local maxTextW = max(20, slotW)
            if textW > maxTextW then
                textW = maxTextW
                nameText:SetWidth(textW)
            end
            if textW < 20 then textW = 20 end
            if ns.SnapToPixelGrid then textW = ns.SnapToPixelGrid(textW) end

            -- XP mode only: the bar runs 40px past the text's right edge (rep and professions keep bar width = text width).
            local barW = textW
            if state.isXP then barW = min(textW + 40, maxTextW) end

            local textH = ns.SnapToPixelGrid(nameText:GetStringHeight() or textHeight)
            local stackH = textH + 2 + bH
            local pad = max(0, floor((barH - stackH) / 2 + 0.5))
            content:SetSize(min(slotW, barW), barH)
            nameText:ClearAllPoints()
            nameText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -pad)
            barTrack:ClearAllPoints()
            barTrack:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(pad + textH + 2))
            barTrack:SetSize(barW, bH)
            barTrack:SetColorTexture(1, 1, 1, 0.1)
            bar:ClearAllPoints(); bar:SetSize(barW, bH)
            bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(pad + textH + 2))
            restBar:ClearAllPoints(); restBar:SetAllPoints(bar)
        end
        MaybeRelayout(inst)
    end

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        -- Nothing to render (rep with no watched faction, or below-max with no XP source):
        -- claim no length so the solver reserves no dead gap; the changed-extent relayout gate restores the width when content returns.
        if not content:IsShown() then return 0 end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 40)
        end
        -- Auto size tracks the live text width (the bar matches it, plus the XP-only 40px extension). No icon term: text + bar only.
        local tw = nameText:GetStringWidth() or 0
        if tw < 20 then tw = 120 end
        return tw + (self._xpExtend or 0)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end
