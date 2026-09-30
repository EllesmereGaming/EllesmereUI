if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end -- no season crests on WoW Forever: no factory, no ns.CrestColorMode (the main file drops the block from BLOCK_TYPES too)
-- Blocks\Crests.lua
-- Crests block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local wipe        = wipe
local format      = string.format
local tconcat     = table.concat
local floor       = math.floor
local max         = math.max
local min         = math.min

local CONTENT_BASE         = K.CONTENT_BASE
local CRESTS               = K.CRESTS
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
--  CRESTS (season upgrade currencies, one compact readout)
--
--  Renders into ONE FontString using inline |T|t icon and |cff color escapes
--  rather than a texture/fontstring pair per crest: the segment count is
--  variable (the checklist and Hide Empty both drop entries) and crest coloring
--  is per-segment anyway, so a single measured string beats up to fourteen
--  regions. Same reason its icons sit out of the Icon Color row -- see the note
--  by ICON_DEFAULTS in Blocks\Shared.lua.
-------------------------------------------------------------------------------

-- Separator glyph. A literal pipe has to be doubled or the text engine reads it
-- as the start of an escape sequence.
-- Dim tone for the tooltip's secondary (season progress) figure. Same value the
-- character stats tooltip uses for its parenthesized ratings, kept local so the
-- two sections stay independent.
local CREST_DIM = "|cffaaaaaa"

local CREST_SEPARATORS = {
    slash = " / ",
    line  = " || ",
    dash  = " - ",
    space = "   ",
}

-- Crest Colors is this block's nothing-stored default, so it resolves the same
-- way the Icon Color row's "Default" swatch does instead of Gold's forced
-- one-shot write: an untouched block is crest colored, and the first Custom
-- click seeds b.color, which takes over. Shared with the options page so the
-- 4th swatch lights on exactly this test.
function ns.CrestColorMode(b)
    if b.useCrestColor then return true end
    return not b.useClassColor and not b.useAccentColor
        and not b.useDynamicColor and b.color == nil
end

ns.BlockFactories.crests = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "CURRENCY_DISPLAY_UPDATE" }

    local mouseOver = false
    -- Reused across refreshes: the string is rebuilt on every currency event,
    -- so a fresh table per pass would allocate in a hot path.
    local _segBuf = {}

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local crestText = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, crestText)

    local function GetInfo(id)
        if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
        return C_CurrencyInfo.GetCurrencyInfo(id)
    end

    local function Num(v)
        if BreakUpLargeNumbers then return BreakUpLargeNumbers(v or 0) end
        return tostring(v or 0)
    end

    -- Bar figure. Off: the spendable amount. On: season progress, which for
    -- crests means totalEarned/maxQuantity -- a DIFFERENT number, which is why
    -- the option is labelled Show Season Progress rather than Show Cap.
    local function AmountText(info, seasonProgress)
        local qty = info.quantity or 0
        if not seasonProgress then return Num(qty) end
        local cap = info.maxQuantity
        if not cap or cap <= 0 then return Num(qty) end
        local shown = qty
        if info.useTotalEarnedForMaxQty then shown = info.totalEarned or qty end
        return Num(shown) .. "/" .. Num(cap)
    end

    -- Tooltip figure: the spendable amount first (what the bar shows), then the
    -- season cap progress dimmed in parentheses. Those two diverge as soon as
    -- you spend a crest, so showing only one of them is what made the tooltip
    -- read as contradicting the bar.
    local function TooltipAmount(info)
        local owned = Num(info.quantity or 0)
        local cap = info.maxQuantity
        if not cap or cap <= 0 then return owned end
        local earned = info.quantity or 0
        if info.useTotalEarnedForMaxQty then earned = info.totalEarned or earned end
        return owned .. " " .. CREST_DIM .. "(" .. Num(earned) .. "/" .. Num(cap) .. ")|r"
    end

    function inst:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local showIcons  = s.showIcons ~= false
        local seasonProg = s.showSeasonProgress == true
        local hideEmpty  = s.hideEmpty == true
        -- Crest tints are baked into the string, so hovering has to fall back
        -- to plain segments for the accent wash to read (same as Gold).
        local crestMode = ns.CrestColorMode(blockCfg) and not mouseOver
        local iconSz = fontSize + 2

        local from, to, step = 1, #CRESTS, 1
        if s.reverse == true then from, to, step = #CRESTS, 1, -1 end

        wipe(_segBuf)
        for i = from, to, step do
            local c = CRESTS[i]
            if s[c.key] ~= false then
                local info = GetInfo(c.id)
                local seg
                if info then
                    if not (hideEmpty and (info.quantity or 0) <= 0) then
                        seg = AmountText(info, seasonProg)
                        if showIcons and info.iconFileID then
                            seg = format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", info.iconFileID,
                                iconSz, iconSz) .. seg
                        end
                        if crestMode then seg = "|cff" .. c.hex .. seg .. "|r" end
                    end
                else
                    seg = "-"
                end
                if seg then _segBuf[#_segBuf + 1] = seg end
            end
        end

        local text
        if #_segBuf == 0 then
            -- Everything filtered out (Hide Empty on an empty wallet, or the
            -- whole checklist cleared): a placeholder keeps the block on the
            -- bar instead of silently collapsing to nothing.
            text = "-"
        elseif isSide then
            -- One crest per line on a side bar, like the Gold block's tokens.
            text = tconcat(_segBuf, "\n")
        else
            local sep = CREST_SEPARATORS[s.separator or "slash"] or CREST_SEPARATORS.slash
            if crestMode then sep = "|cff808080" .. sep .. "|r" end
            text = tconcat(_segBuf, sep)
        end

        ns.SetFont(crestText, fontSize, barCfg)
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            crestText:SetText(text)
            ns.SetWrappedText(crestText, innerW, "CENTER")
            crestText:ClearAllPoints()
            crestText:SetPoint("TOP", button, "TOP", 0, -4)
            local totalH = max(8 + ns.SnapToPixelGrid(crestText:GetStringHeight()), barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 200)
            ns.ResetInlineText(crestText, "LEFT")
            crestText:SetText(text)
            crestText:ClearAllPoints()
            crestText:SetPoint("LEFT", button, "LEFT", 0, 0)
            local tw = ns.SnapToPixelGrid(crestText:GetStringWidth())
            local totalW = min(slotW, tw + 4)
            content:SetSize(max(totalW, 10), barH)
            button:SetSize(max(totalW, 10), barH)
        end

        if mouseOver then
            crestText:SetTextColor(ns.GetAccent())
        elseif crestMode then
            -- Every segment carries its own escape; a white base keeps the
            -- separators and any placeholder neutral.
            crestText:SetTextColor(1, 1, 1, 1)
        else
            crestText:SetTextColor(BlockColorOf(blockCfg))
        end
        MaybeRelayout(inst)
    end

    local function ShowCrestTooltip()
        local ar, ag, ab = ns.GetAccent()
        ns.Tip_Begin(button)
        -- The header row doubles as the column legend: the parenthesized
        -- figure below is the same one Blizzard's currency tooltip prints
        -- under "Current season maximum", so naming it here costs no extra row.
        ns.Tip_AddDouble(L["CRESTS"], L["SEASON_MAXIMUM"], 1, 1, 1, 0.667, 0.667, 0.667)
        ns.Tip_AddLine(" ")
        -- All five, whatever the bar shows: the block is the compact view and
        -- the tooltip is the full one.
        for i = 1, #CRESTS do
            local c = CRESTS[i]
            local info = GetInfo(c.id)
            if info then
                ns.Tip_AddDouble(info.name or "?", TooltipAmount(info),
                    c.r, c.g, c.b, 1, 1, 1)
            end
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        ShowCrestTooltip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    button:SetScript("OnClick", function(_, mb)
        if mb ~= "LeftButton" then return end
        if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
            C_CurrencyInfo.OpenCurrencyPanel()
        elseif ToggleCharacter then
            ToggleCharacter("TokenFrame")
        end
    end)

    -- Payload-gated: a single-currency update that is not a crest is skipped;
    -- a nil currencyType (bulk update) refreshes.
    inst.eventFrame = MakeEventFrame(inst, function(self, _, currencyType)
        if currencyType and not ns.CREST_IDS[currencyType] then return end
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
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 120, 24)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end
