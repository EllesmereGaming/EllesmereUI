if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Gold.lua
-- Gold block factory and the shared session/character ledger.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local C_Timer     = C_Timer
local pairs       = pairs
local ipairs      = ipairs
local type        = type
local format      = string.format
local tinsert     = table.insert
local tconcat     = table.concat
local tsort       = table.sort
local floor       = math.floor
local max         = math.max
local min         = math.min
local abs         = math.abs

local ICON_GAP         = K.ICON_GAP
local CONTENT_BASE     = K.CONTENT_BASE
local InstKey          = K.InstKey
local HBudget          = K.HBudget
local VSlotW           = K.VSlotW
local MaybeRelayout    = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf     = K.BlockColorOf
local IconColorOf      = K.IconColorOf

-------------------------------------------------------------------------------
--  GOLD (engine-level session ledger + cross-character store)
-------------------------------------------------------------------------------
-- One PLAYER_MONEY ledger shared by every gold instance; instances render from it and ctrl-right-click resets the shared session.
local goldLedger = { profit = 0, spent = 0, lastMoney = nil, tokenPrice = nil }
local goldInstances = {}
local goldEventFrame

local function GoldCharKey()
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
end

-- ACCOUNT-level, NOT the profile: the ledger lists the player's characters and
-- balances, and profiles get shared -- inside a profile it rides export
-- strings, so importers would see the exporter's alts and gold. Top-level in
-- EllesmereUIDB next to the Bags gold ledger; also survives profile switches.
local function GoldStore()
    -- Throwaway fallback if the parent DB is somehow absent: never assign the global here, or a pre-SavedVariables call could shadow the real table.
    if type(EllesmereUIDB) ~= "table" then return {} end
    local store = EllesmereUIDB.dataBarsGold
    if type(store) ~= "table" then
        store = {}
        EllesmereUIDB.dataBarsGold = store
    end
    return store
end

-- Drop a character the player no longer has (renamed, deleted, transferred); sits next to the writer so both mutations of the store are in one place.
local function GoldForgetCharacter(key)
    GoldStore()[key] = nil
    for gi in pairs(goldInstances) do gi:QueueRefresh() end
end

local function GoldSaveCurrentMoney(money)
    local store = GoldStore()
    local _, class = UnitClass("player")
    store[GoldCharKey()] = { currentMoney = money, class = class, realm = GetRealmName(), name = UnitName("player") }
end

local function GoldLedgerUpdate()
    local money = GetMoney()
    -- Never let a secret into the ledger or the persisted store: every consumer (session math, roster threshold, sort, total) does arithmetic on it.
    if (issecretvalue and issecretvalue(money)) or type(money) ~= "number" then
        return
    end
    if goldLedger.lastMoney then
        local diff = money - goldLedger.lastMoney
        if diff > 0 then goldLedger.profit = goldLedger.profit + diff
        elseif diff < 0 then goldLedger.spent = goldLedger.spent + (-diff) end
    end
    goldLedger.lastMoney = money
    GoldSaveCurrentMoney(money)
end

local function GoldOnEvent(_, event)
    if event == "TOKEN_MARKET_PRICE_UPDATED" then
        if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then
            local price = C_WowTokenPublic.GetCurrentMarketPrice()
            if issecretvalue and issecretvalue(price) then price = nil end
            goldLedger.tokenPrice = price
        end
        return
    end
    -- BAG_UPDATE changes bag slots only, never money.
    if event ~= "BAG_UPDATE" then GoldLedgerUpdate() end
    for gi in pairs(goldInstances) do
        gi:QueueRefresh()
    end
end

local function UpdateGoldEvents()
    if next(goldInstances) then
        if not goldEventFrame then
            goldEventFrame = CreateFrame("Frame")
            goldEventFrame:SetScript("OnEvent", GoldOnEvent)
        end
        goldEventFrame:RegisterEvent("PLAYER_MONEY")
        goldEventFrame:RegisterEvent("BAG_UPDATE")
        goldEventFrame:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED")
    elseif goldEventFrame then
        goldEventFrame:UnregisterAllEvents()
    end
end

-- General-purpose bags only (family 0), like the Bags block: a quiver, soul
-- bag or profession bag cannot take ordinary loot.
local function GetFreeBagSlots()
    local free = 0
    for i = 0, 4 do
        local n, family = C_Container.GetContainerNumFreeSlots(i)
        if n and (not family or family == 0) then free = free + n end
    end
    return free
end

ns.BlockFactories.gold = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local GOLD_TEX = ns.MICROMENU_MEDIA .. "menu-bags.png"
    local _goldFitBuf = { "", "" }
    local mouseOver = false

    -- Coin Colored is the gold block's default text mode (white numbers,
    -- coin-tinted g/s/c letters), FORCED once onto existing blocks whatever
    -- mode they were on; the marker makes every later swatch choice stick.
    -- In the factory so every profile/import converges when its block builds.
    if not blockCfg.coinForced then
        blockCfg.coinForced = true
        blockCfg.useCoinColor = true
        blockCfg.useClassColor = nil
        blockCfg.useAccentColor = nil
    end

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local goldButton = CreateFrame("Button", nil, content)
    goldButton:SetSize(120, 20); goldButton:SetPoint("CENTER")
    goldButton:EnableMouse(true); goldButton:RegisterForClicks("AnyUp")

    local goldIcon = goldButton:CreateTexture(nil, "OVERLAY"); goldIcon:SetTexture(GOLD_TEX)
    local goldText = goldButton:CreateFontString(nil, "OVERLAY")
    local bagText  = goldButton:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, goldText)   -- bagText chains to goldText

    function inst:Refresh()
        local dg = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        -- 0.4333 ratio = 13px at the 30 base (matches the stat blocks).
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local iconSz = 0
        -- +4: the bag icon runs bigger than the text size (user-tuned).
        if dg.showIcons ~= false then iconSz = fontSize + 4 end
        -- -2: the coin icon sits tighter to its text than the shared default.
        local gap = ICON_GAP - 2
        local isSide = barCtx.IsVertical()

        ns.SetFont(goldText, fontSize, barCfg)
        ns.SetFont(bagText, fontSize, barCfg)

        local money = GetMoney()
        local ci = dg.coinIcons == true
        local ab = dg.abbreviate == true
        local fe = dg.forceEnglishUnits == true
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            -- One token per coin, one coin per line. Coin Colored tints the suffix letters
            -- (nothing to tint once Coin Icons is on, so the two compose); hovering drops it so the accent wash reads.
            local lines = ns.MoneyTokens(money, dg.showSmall == true, ci,
                blockCfg.useCoinColor == true and not mouseOver, ab, fe)
            local startSize = min(fontSize, max(10, floor(CONTENT_BASE * 0.52 + 0.5)))
            local goldFontSize = startSize
            ns.SetFont(goldText, goldFontSize, barCfg)
            goldText:SetText(tconcat(lines, "\n"))
            local r, g, b
            if mouseOver then r, g, b = ns.GetAccent()
            elseif blockCfg.useCoinColor then r, g, b = 1, 1, 1
            else r, g, b = BlockColorOf(blockCfg) end
            goldText:SetTextColor(r, g, b, 1)
        elseif mouseOver then
            goldText:SetText(ns.FormatMoney(money, false, dg.showSmall == true, ci, ab, fe))
            local r, g, b = ns.GetAccent()
            goldText:SetTextColor(r, g, b, 1)
        else
            goldText:SetText(ns.FormatMoney(money, blockCfg.useCoinColor == true, dg.showSmall == true, ci, ab, fe))
            if blockCfg.useCoinColor then
                goldText:SetTextColor(1, 1, 1, 1)
            else
                goldText:SetTextColor(BlockColorOf(blockCfg))
            end
        end

        if dg.showBagSpace == true then
            bagText:SetText("(" .. GetFreeBagSlots() .. ")"); bagText:Show()
        else
            bagText:Hide()
        end

        local r, g, b
        if mouseOver then r, g, b = ns.GetAccent()
        elseif blockCfg.useCoinColor then r, g, b = 1, 1, 1
        else r, g, b = BlockColorOf(blockCfg) end
        bagText:SetTextColor(r, g, b, 1)

        if dg.showIcons ~= false and iconSz > 0 then
            goldIcon:SetSize(iconSz, iconSz)
            if mouseOver then
                goldIcon:SetVertexColor(r, g, b, 1)
            else
                local ir, ig, ib = IconColorOf(blockCfg)
                goldIcon:SetVertexColor(ir, ig, ib, 1)
            end
            goldIcon:Show()
        else
            goldIcon:Hide(); iconSz = 0
        end

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8

            if iconSz > 0 then
                goldIcon:ClearAllPoints()
                goldIcon:SetPoint("TOP", goldButton, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end

            ns.SetWrappedText(goldText, innerW, "CENTER")
            goldText:ClearAllPoints()
            if iconSz > 0 then
                goldText:SetPoint("TOP", goldIcon, "BOTTOM", 0, -2)
            else
                goldText:SetPoint("TOP", goldButton, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(goldText:GetStringHeight())

            if bagText:IsShown() then
                ns.SetWrappedText(bagText, innerW, "CENTER")
                bagText:ClearAllPoints()
                bagText:SetPoint("TOP", goldText, "BOTTOM", 0, -2)
                totalH = totalH + 2 + ns.SnapToPixelGrid(bagText:GetStringHeight())
            end

            totalH = max(totalH, barH)
            goldButton:SetSize(slotW, totalH)
            content:SetSize(slotW, totalH)
            goldButton:ClearAllPoints(); goldButton:SetPoint("CENTER", content, "CENTER", 0, 0)
        else
            local slotW = HBudget(inst, 100)
            -- Fit against BOTH money formats so font/icon size and frame width stay identical hovered or not; otherwise it resizes on mouseover.
            local plainText = ns.FormatMoney(money, false, dg.showSmall == true, ci, ab, fe)
            local fancyText = ns.FormatMoney(money, blockCfg.useCoinColor == true, dg.showSmall == true, ci, ab, fe)
            local moneyText
            if mouseOver then moneyText = plainText else moneyText = fancyText end
            local bagTextValue = ""
            if dg.showBagSpace == true then bagTextValue = "(" .. GetFreeBagSlots() .. ")" end
            local bagPad = 8
            if bagTextValue ~= "" then bagPad = 26 end
            local textBudget = max(24, slotW - iconSz - bagPad)
            _goldFitBuf[1] = plainText; _goldFitBuf[2] = fancyText; _goldFitBuf[3] = bagTextValue
            local fitSize = fontSize
            ns.SetFont(goldText, fitSize, barCfg)
            ns.SetFont(bagText, fitSize, barCfg)
            goldText:SetText(moneyText)
            if bagTextValue ~= "" then bagText:SetText(bagTextValue) end
            ns.ResetInlineText(goldText, "LEFT")
            ns.ResetInlineText(bagText, "LEFT")
            iconSz = 0
            -- +4: matches the vertical branch (user-tuned bag icon size).
            if dg.showIcons ~= false then iconSz = fitSize + 4 end
            goldIcon:SetSize(iconSz, iconSz)
            goldIcon:ClearAllPoints(); goldIcon:SetPoint("LEFT", goldButton, "LEFT", 0, 0)
            goldText:ClearAllPoints(); goldText:SetPoint("LEFT", goldButton, "LEFT", iconSz + gap, 0)
            local bagW = 0
            if dg.showBagSpace == true then bagW = (bagText:GetStringWidth() or 0) + 4 end
            bagText:ClearAllPoints(); bagText:SetPoint("LEFT", goldText, "RIGHT", 4, 0)

            -- Width from the wider format so the frame never grows on hover.
            local moneyW = goldText:GetStringWidth() or 0
            local measureFS = ns.MeasureFS()
            if measureFS then
                ns.SetFont(measureFS, fitSize, barCfg)
                local other
                if mouseOver then other = fancyText else other = plainText end
                measureFS:SetText(other)
                moneyW = max(moneyW, measureFS:GetStringWidth() or 0)
            end
            local textW = min(slotW, iconSz + gap + moneyW + bagW + 4)
            goldButton:SetSize(textW, barH)
            content:SetSize(textW, barH)
            goldButton:ClearAllPoints(); goldButton:SetPoint("CENTER", content, "CENTER", 0, 0)
        end
        MaybeRelayout(inst)
    end

    function inst:QueueRefresh()
        if self._refreshQueued then return end
        self._refreshQueued = true
        C_Timer.After(0, function()
            inst._refreshQueued = false
            if goldInstances[inst] then inst:Refresh() end
        end)
    end

    goldButton:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        -- Tooltip money lines honor the block's Show Silver and Copper toggle.
        local sm = D().showSmall == true
        local ci = D().coinIcons == true
        -- Show Tooltip Data checklist: each section defaults ON.
        local showSession = D().tipSession ~= false
        local showChars   = D().tipCharacters ~= false
        local showToken   = D().tipToken ~= false
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(goldButton)
        ns.Tip_AddLine(L["GOLD"], ar, ag, ab)
        if showSession then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["SESSION"], 0.8, 0.8, 0.8)
            ns.Tip_AddDouble(L["EARNED"], ns.FormatMoney(goldLedger.profit, true, sm, ci), 0.6, 0.6, 0.6, 0, 1, 0)
            ns.Tip_AddDouble(L["SPENT"],  ns.FormatMoney(goldLedger.spent,  true, sm, ci), 0.6, 0.6, 0.6, 1, 0.3, 0.3)
            local net = goldLedger.profit - goldLedger.spent
            if net ~= 0 then
                local label
                if net > 0 then label = L["PROFIT"] else label = L["DEFICIT"] end
                local nr, ngr = 1, 0.3
                if net > 0 then nr, ngr = 0, 1 end
                ns.Tip_AddDouble(label, ns.FormatMoney(abs(net), true, sm, ci), 0.6, 0.6, 0.6, nr, ngr, 0.3)
            end
        end
        local charCount = 0
        if showChars then
            local store = GoldStore()
            -- The list holds store KEYS ("Name-Realm"): a delete needs the key, and the entry itself does not carry one.
            local selfKey = GoldCharKey()
            -- Roster shows only balances above 10,000 gold (copper threshold) plus the live char; filtered chars still count into the total.
            local minCopper = 10000 * 10000
            local total, charList = 0, {}
            for key, cdata in pairs(store) do
                -- issecretvalue-first: a stored value may be secret, and even a truthiness test on one is an error.
                local cm = cdata and cdata.currentMoney
                if issecretvalue and issecretvalue(cm) then cm = nil end
                if cm then
                    if cm > minCopper or key == selfKey then
                        tinsert(charList, key)
                    end
                    total = total + cm
                end
            end
            tsort(charList, function(a, b)
                return (store[a].currentMoney or 0) > (store[b].currentMoney or 0)
            end)
            charCount = #charList
            if charCount > 0 then
                ns.Tip_AddLine(" ")
                ns.Tip_AddLine(GetRealmName() or "?", 0.5, 0.78, 1)
                -- Cap roster rows so many alts cannot push the total and hint rows off
                -- screen. Sorted richest first, so the cap keeps the highest balances; the
                -- live character always shows; the total still sums EVERY stored character.
                local maxRows, shownRows, hiddenRows = 10, 0, 0
                for _, key in ipairs(charList) do
                    local char = store[key]
                    if shownRows >= maxRows and key ~= selfKey then
                        hiddenRows = hiddenRows + 1
                    else
                        shownRows = shownRows + 1
                        local cr, cg, cb = 1, 1, 1
                        if char.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class] then
                            local cc = RAID_CLASS_COLORS[char.class]; cr, cg, cb = cc.r, cc.g, cc.b
                        end
                        local label = char.name or "?"
                        local tokens = ns.MoneyTokens(char.currentMoney, sm, ci, true)
                        -- Every row gets the same hover affordance; the live character's
                        -- click is inert (it re-saves on every money event, so a delete returns instantly).
                        ns.Tip_AddClickableColumns(label, tokens, function(mouseButton)
                            if key == selfKey then return end
                            if mouseButton ~= "LeftButton" then return end
                            if not (IsControlKeyDown() and IsAltKeyDown()) then return end
                            GoldForgetCharacter(key)
                            ns.Tip_Hide(goldButton)
                        end, cr, cg, cb)
                    end
                end
                if hiddenRows > 0 then
                    ns.Tip_AddLine(format(L["PLUS_N_MORE"], hiddenRows), 0.6, 0.6, 0.6)
                end
            end
            -- Warbank rides the character list as its final row, no separator: it reads as one more entry.
            local bankType = 2
            if Enum and Enum.BankType and Enum.BankType.Account then bankType = Enum.BankType.Account end
            if C_Bank and C_Bank.FetchDepositedMoney then
                local wbank = C_Bank.FetchDepositedMoney(bankType)
                if issecretvalue and issecretvalue(wbank) then wbank = nil end
                if wbank and wbank > 0 then
                    ns.Tip_AddColumns(L["WARBANK"], ns.MoneyTokens(wbank, sm, ci, true), 1, 0.82, 0)
                    total = total + wbank
                end
            end
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble(L["TOTAL"], ns.FormatMoney(total, true, sm, ci), ar, ag, ab, 1, 1, 1)
        end
        if showToken and goldLedger.tokenPrice and goldLedger.tokenPrice > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble(L["WOW_TOKEN"], ns.FormatMoney(goldLedger.tokenPrice, true, sm, ci), 0, 0.8, 1, 1, 1, 1)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"],       L["OPEN_BAGS"],       1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["RIGHT_CLICK"],      L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["CTRL_RIGHT_CLICK"], L["RESET_SESSION"],   1, 1, 1, ar, ag, ab)
        if charCount > 1 then
            ns.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, ar, ag, ab)
        end
        ns.Tip_Show()
    end)
    goldButton:SetScript("OnLeave", function()
        mouseOver = false
        -- The character rows are clickable, so the tooltip has to survive the cursor leaving the block to be reachable at all.
        ns.Tip_HideUnlessInteractive(goldButton)
        inst:Refresh()
    end)
    goldButton:SetScript("OnClick", function(_, button)
        if IsControlKeyDown() and button == "RightButton" then
            goldLedger.profit = 0; goldLedger.spent = 0
            inst:Refresh()
        elseif button == "RightButton" then
            if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
                C_CurrencyInfo.OpenCurrencyPanel()
            elseif ToggleCharacter then
                ToggleCharacter("TokenFrame")
            end
        elseif button == "LeftButton" then
            ToggleAllBags()
        end
    end)

    function inst:Enable()
        content:Show()
        if goldLedger.lastMoney == nil then
            goldLedger.lastMoney = GetMoney()
            goldLedger.profit = 0
            goldLedger.spent = 0
            GoldSaveCurrentMoney(goldLedger.lastMoney)
        end
        if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
            C_WowTokenPublic.UpdateMarketPrice()
        end
        goldInstances[self] = true
        UpdateGoldEvents()
    end

    function inst:Disable()
        goldInstances[self] = nil
        UpdateGoldEvents()
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            local barH = barCtx.GetThickness()
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            -- Mirror Refresh: no icon budget when Show Icons is off, else the segment measures taller than its rendered content.
            local iconTerm = 0
            local dg = blockCfg.settings
            if not dg or dg.showIcons ~= false then iconTerm = fontSize + 2 end
            local textH = goldText:GetStringHeight() or fontSize
            local bagH = 0
            if bagText:IsShown() then bagH = (bagText:GetStringHeight() or 0) + 2 end
            return max(8 + iconTerm + textH + bagH + 4, barH, 50)
        end
        return max(content:GetWidth() or 100, 40)
    end

    function inst:Destroy()
        self._dead = true
        goldInstances[self] = nil
        UpdateGoldEvents()
        content:Hide()
    end

    return inst
end
