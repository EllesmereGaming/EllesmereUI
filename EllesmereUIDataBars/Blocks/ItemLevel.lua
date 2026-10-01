if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\ItemLevel.lua
-- Item level block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local _G               = _G
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local format           = string.format
local floor            = math.floor
local max              = math.max
local min              = math.min

local ICON_GAP             = K.ICON_GAP
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
local IconColorOf          = K.IconColorOf
local ParkSecureFrame      = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  ITEM LEVEL (equipped / total, with an optional prefix)
-------------------------------------------------------------------------------
ns.BlockFactories.ilvl = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    -- PLAYER_REGEN_ENABLED: geometry and the secure click overlay both wait for regen, so the block needs a pass there.
    inst.events = { "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
                    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }

    local mouseOver = false

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local icon = button:CreateTexture(nil, "OVERLAY")
    local ilvlText = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, ilvlText)

    local clickBtn
    local EnsureClickButton -- defined below, after the hover scripts it reuses

    -- Item level returns can be secret values, which detonate the moment they
    -- reach format() or a tooltip width measure (see the micro menu's char
    -- stats block). Strip them here, once, and every consumer below is safe.
    local function AvgIlvl()
        local total, equipped, pvp = GetAverageItemLevel()
        if issecretvalue then
            if issecretvalue(total) then total = nil end
            if issecretvalue(equipped) then equipped = nil end
            if issecretvalue(pvp) then pvp = nil end
        end
        return total, equipped, pvp
    end

    local function Fmt(v, p)
        if not v then return "-" end
        return format("%." .. p .. "f", v)
    end

    local function LongLabel()
        return STAT_AVERAGE_ITEM_LEVEL or EllesmereUI.L(L["ITEM_LEVEL"])
    end

    function inst:Refresh()
        EnsureClickButton()

        local s = D()
        K.SetBlockIcon(icon, blockCfg)
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP

        local total, equipped = AvgIlvl()
        -- Published for the "Band" text swatch (and its options preview).
        K.lastAvgIlvl = equipped or total

        local p = s.precision
        if p == nil then p = 0 end
        local mode = s.value or "equipped"
        local body
        if mode == "total" then
            body = Fmt(total, p)
        elseif mode == "both" then
            body = Fmt(equipped, p) .. " / " .. Fmt(total, p)
        else
            body = Fmt(equipped, p)
        end

        -- Bar text goes straight through SetText, which does not route through
        -- the locale like the Tip_* helpers, so the short prefix is translated
        -- by hand; the long one rides Blizzard's own localized global.
        local prefix = s.prefix or "short"
        local text = body
        if prefix == "short" then
            text = EllesmereUI.L(L["ILVL"]) .. " " .. body
        elseif prefix == "long" then
            text = LongLabel() .. " " .. body
        end

        local iconSz = 0
        if prefix == "icon" then
            iconSz = fontSize + 2
            icon:Show()
        else
            icon:Hide()
        end

        ns.SetFont(ilvlText, fontSize, barCfg)
        do
            local ir, ig, ib = IconColorOf(blockCfg)
            icon:SetVertexColor(ir, ig, ib, 1)
        end
        if mouseOver then
            ilvlText:SetTextColor(ns.GetAccent())
        else
            ilvlText:SetTextColor(BlockColorOf(blockCfg))
        end
        -- Sizing and anchoring are protected once the secure click overlay exists
        -- (it puts this block's whole bar under protection): in lockdown only the
        -- text updates, geometry waits for PLAYER_REGEN_ENABLED.
        if InCombatLockdown() then
            ilvlText:SetText(text)
            return
        end
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            ilvlText:SetText(text)
            local totalH = 8
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("TOP", button, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            ns.SetWrappedText(ilvlText, innerW, "CENTER")
            ilvlText:ClearAllPoints()
            if iconSz > 0 then
                ilvlText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                ilvlText:SetPoint("TOP", button, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(ilvlText:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 120)
            ns.ResetInlineText(ilvlText, "LEFT")
            ilvlText:SetText(text)
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", button, "LEFT", 0, 0)
            end
            ilvlText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then xOff = iconSz + gap end
            ilvlText:SetPoint("LEFT", button, "LEFT", xOff, 0)
            local tw = ns.SnapToPixelGrid(ilvlText:GetStringWidth())
            local totalW = min(slotW, xOff + tw + 4)
            content:SetSize(max(totalW, 10), barH)
            button:SetSize(max(totalW, 10), barH)
        end

        MaybeRelayout(inst)
    end

    local function ShowIlvlTooltip()
        local ar, ag, ab = ns.GetAccent()
        local total, equipped, pvp = AvgIlvl()
        ns.Tip_Begin(button)
        ns.Tip_AddLine(LongLabel(), 1, 1, 1)
        ns.Tip_AddLine(" ")
        if equipped then
            ns.Tip_AddDouble(L["EQUIPPED"], format("%.2f", equipped), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        if total then
            ns.Tip_AddDouble(L["TOTAL"], format("%.2f", total), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        -- PvP item level only exists in PvP-scaled gear; hide the row otherwise.
        if pvp and pvp > 0 then
            ns.Tip_AddDouble(L["PVP_ITEM_LEVEL"], format("%.2f", pvp), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CHARACTER"], 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        ShowIlvlTooltip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    -- Fallback only: used until the secure overlay exists (block built mid-combat,
    -- or no CharacterMicroButton). ToggleCharacter from addon Lua taints
    -- CharacterFrame's show path (secret health values -> TextStatusBar error).
    button:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" and ToggleCharacter then
            ToggleCharacter("PaperDollFrame")
        end
    end)

    -- Secure click passthrough to Blizzard's CharacterMicroButton, same mechanism as
    -- the location and micro menu blocks: the click runs inside Blizzard's own
    -- handler, so the character sheet opens untainted. Created lazily, never in
    -- lockdown; PLAYER_REGEN_ENABLED drives Refresh's retry.
    EnsureClickButton = function()
        if clickBtn or InCombatLockdown() then return clickBtn end
        local micro = _G.CharacterMicroButton
        if not micro then return nil end
        clickBtn = CreateFrame("Button", "EWB_ILVL_" .. inst.key, button,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate")
        clickBtn:SetAllPoints(button)
        clickBtn:SetAttribute("*clickbutton1", micro)
        -- Without this, the ActionButtonUseKeyDown CVar makes the secure handler act on key-down only, discarding our "AnyUp" clicks.
        clickBtn:SetAttribute("useOnKeyDown", false)
        clickBtn:SetAttribute("*type1", "click")
        clickBtn:EnableMouse(true)
        clickBtn:RegisterForClicks("AnyUp")
        -- Combat: drop the click ACTION only, from inside the secure env. Stays mouse-enabled so hover works; a click while *type1 is nil does nothing.
        RegisterStateDriver(clickBtn, "combatlock", "[combat] combat; nocombat")
        clickBtn:SetAttribute("_onstate-combatlock", [[
            if newstate == 'combat' then
                self:SetAttribute('*type1', nil)
            else
                self:SetAttribute('*type1', 'click')
            end
        ]])
        -- Overlay covers the block and owns hover from here.
        clickBtn:SetScript("OnEnter", button:GetScript("OnEnter"))
        clickBtn:SetScript("OnLeave", button:GetScript("OnLeave"))
        return clickBtn
    end

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        if not content:IsShown() and not InCombatLockdown() then content:Show() end
        EnsureClickButton()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        -- Protected once the secure click overlay exists.
        if not InCombatLockdown() then content:Hide() end
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        if clickBtn then
            ParkSecureFrame(clickBtn, self.key .. "_ilvl")
            clickBtn = nil
        end
        if not InCombatLockdown() then content:Hide() end
    end

    return inst
end
