if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\LDB.lua
-- LibDataBroker plugin block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local type             = type
local pcall            = pcall
local floor            = math.floor
local max              = math.max

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf

-------------------------------------------------------------------------------
--  BROKER PLUGIN (LibDataBroker) -- one block type for every data source
-------------------------------------------------------------------------------
-- The only block whose content is written by code we do not own, and three
-- rules follow from that:
--   1. Never write to the data object. A display READS; the plugin owns its own
--      text, and a stray write would fight whoever set it.
--   2. Every call into the plugin (OnEnter/OnLeave/OnClick/OnTooltipShow/
--      OnMouseWheel) goes through pcall. A plugin that errors inside our hover
--      or refresh path would otherwise take the bar's layout down with it.
--   3. Width is never assumed stable. The other text blocks reserve width from
--      a stable template so neighbours never shift; broker text has no shape we
--      can predict, so this one measures live and offers a Max Width clamp.
--
-- Tooltips route three ways, in the plugin's own order of preference:
--   OnEnter        the plugin draws its own tooltip (LibQTip, usually) into the
--                  frame we hand it, and OnLeave takes it away. The owned
--                  tooltip stays out of it -- two tooltips for one block, and
--                  the plugin's is the one carrying the data.
--   OnTooltipShow  the broker contract's GameTooltip path, and the one place in
--                  this addon that still uses GameTooltip: the plugin writes
--                  into it directly, which we cannot re-render.
--   neither        name + text in the owned tooltip, so hover is never dead.

-- Attributes worth a repaint. The library fires a per-NAME event carrying the
-- changed key, so one registration covers the whole plugin and this set decides
-- what is worth redrawing: a bar full of broker blocks never wakes for each
-- other's updates, and a plugin parking its own state on the data object does
-- not drag us through a re-measure for a key we never render.
local LDB_WATCH = {
    text = true, value = true, suffix = true, label = true,
    icon = true, iconR = true, iconG = true, iconB = true, iconCoords = true,
}

-- Broker text arrives full of the plugin's own color codes, which silently beat
-- this block's Text Color and its accent hover. Stripping them (default on)
-- hands the color back to the block; leaving them keeps the plugin's palette.
local function LDBStripColors(str)
    if not str then return str end
    str = str:gsub("|c%x%x%x%x%x%x%x%x", "")
    str = str:gsub("|cn[%a%d_]+:", "")   -- named-color form (|cnGREEN_FONT_COLOR:)
    str = str:gsub("|r", "")
    return str
end

-- text is the display string; value+suffix is the fallback pair for plugins
-- that publish the number and its unit separately.
local function LDBDisplayText(obj)
    if not obj then return nil end
    local t = obj.text
    if type(t) == "string" and t ~= "" then return t end
    local v = obj.value
    if v ~= nil then
        local str = tostring(v)
        local suf = obj.suffix
        if type(suf) == "string" and suf ~= "" then str = str .. " " .. suf end
        return str
    end
    return nil
end

ns.BlockFactories.ldb = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local mouseOver = false
    local bound        -- source name we currently hold attribute callbacks for
    local tipMode      -- "own" | "gametip" | nil; picked at hover, read at leave

    -- The collapse flip below is a Show/Hide, which lockdown can refuse. A block
    -- built or re-sourced mid-combat therefore settles here rather than waiting
    -- for a plugin update that may never come.
    inst.events = { "PLAYER_REGEN_ENABLED" }

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local icon = button:CreateTexture(nil, "OVERLAY")
    local text = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, text)

    -- The chosen source, or nil while its addon has not registered it yet.
    local function Obj()
        local name = D().source
        if not name then return nil end
        local LDB = ns.GetLDB()
        if not LDB then return nil end
        return LDB:GetDataObjectByName(name)
    end

    local function Unbind()
        local LDB = ns.GetLDB()
        if LDB and bound then
            pcall(LDB.UnregisterCallback, inst, "LibDataBroker_AttributeChanged_" .. bound)
        end
        bound = nil
    end

    -- Idempotent: re-binds only when the chosen source actually changed.
    local function Bind()
        local name = D().source
        if bound == name then return end
        Unbind()
        if not name then return end
        local LDB = ns.GetLDB()
        if not LDB then return end
        -- Args are (event, sourceName, key, value, obj); only the key matters.
        local function OnAttr(_, _, key)
            if LDB_WATCH[key] and not inst._dead then inst:Refresh() end
        end
        pcall(LDB.RegisterCallback, inst, "LibDataBroker_AttributeChanged_" .. name, OnAttr)
        bound = name
    end

    -- Untouched Icon Color leaves the plugin's artwork alone, honouring the
    -- iconR/G/B tint if it declares one; any explicit choice in the options wins,
    -- exactly as on every other icon-bearing block.
    local function IconTint(obj)
        local b = blockCfg
        if b.iconColor or b.useIconClassColor or b.useIconAccentColor or b.useIconDefaultColor then
            return IconColorOf(b)
        end
        if obj and type(obj.iconR) == "number" then
            return obj.iconR, obj.iconG or 1, obj.iconB or 1
        end
        return 1, 1, 1
    end

    function inst:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP
        Bind()

        local obj = Obj()

        -- A source picked on a session where its addon WAS loaded, opened on one
        -- where it is not: collapse rather than show a dead slot. GetAutoLength
        -- reports 0 and the solver drops the block and its gaps entirely.
        local collapsed = (s.source ~= nil) and (obj == nil)
        -- Show/Hide can be protected (another block on this bar may hold a
        -- secure child): flip only on a real state change, never in lockdown.
        if content:IsShown() == collapsed and not InCombatLockdown() then
            if collapsed then content:Hide() else content:Show() end
        end
        if collapsed then
            MaybeRelayout(inst)
            return
        end

        local str
        local placeholder = false
        if not s.source then
            -- Bar text goes straight through SetText, which does not route
            -- through the locale like the Tip_* helpers do, so translate by hand.
            str = EllesmereUI.L(L["SELECT_PLUGIN"])
            placeholder = true
        else
            local body = LDBDisplayText(obj)
            if s.showText == false then body = nil end
            local lbl = obj.label
            if s.showLabel and type(lbl) == "string" and lbl ~= "" then
                if body then str = lbl .. ": " .. body else str = lbl end
            else
                str = body
            end
            if s.stripColors ~= false then str = LDBStripColors(str) end
            if not str then str = "" end
        end

        local iconSz = 0
        local tex = obj and obj.icon
        if s.showIcon ~= false and tex then
            iconSz = fontSize + 2
            icon:SetTexture(tex)
            local c = obj.iconCoords
            if type(c) == "table" and #c == 4 then
                icon:SetTexCoord(c[1], c[2], c[3], c[4])
            else
                icon:SetTexCoord(0, 1, 0, 1)
            end
            icon:SetSize(iconSz, iconSz)
            local ir, ig, ib = IconTint(obj)
            icon:SetVertexColor(ir, ig, ib, 1)
            icon:Show()
        else
            icon:Hide()
        end

        -- Only steal the wheel for a plugin that asked for it.
        button:EnableMouseWheel((obj and obj.OnMouseWheel) ~= nil)

        if placeholder then
            text:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif mouseOver then
            local ar, ag, ab = ns.GetAccent()
            text:SetTextColor(ar, ag, ab, 1)
        else
            local tr, tg, tb = BlockColorOf(blockCfg)
            text:SetTextColor(tr, tg, tb, 1)
        end

        ns.SetFont(text, fontSize, barCfg)

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            local totalH = 8
            if iconSz > 0 then
                icon:ClearAllPoints()
                icon:SetPoint("TOP", button, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            ns.SetWrappedText(text, innerW, "CENTER")
            text:SetText(str)
            text:ClearAllPoints()
            if iconSz > 0 then
                text:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                text:SetPoint("TOP", button, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(text:GetStringHeight() or fontSize) + 4
            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            ns.ResetInlineText(text, "LEFT")
            text:SetText(str)
            local iconPad = 0
            if iconSz > 0 then
                iconPad = iconSz + gap
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", button, "LEFT", 0, 0)
            end
            text:ClearAllPoints()
            text:SetPoint("LEFT", button, "LEFT", iconPad, 0)
            local w = s.maxWidth
            if w then
                -- Max Width: the block holds this width whatever the plugin
                -- publishes, and longer strings clip. The setting that stops a
                -- chatty broker from shoving its neighbours on every update.
                text:SetWidth(max(20, w - iconPad - 2))
                text:SetWordWrap(false)
            else
                w = iconPad + ns.SnapToPixelGrid(text:GetStringWidth() or 40) + 2
            end
            if w < 24 then w = 24 end
            content:SetSize(w, barH)
            button:SetSize(w, barH)
        end

        button:ClearAllPoints()
        button:SetPoint("CENTER", content, "CENTER", 0, 0)
        MaybeRelayout(inst)
    end

    local function HideTip()
        if tipMode == "own" then
            local obj = Obj()
            if obj and obj.OnLeave then pcall(obj.OnLeave, button) end
        elseif tipMode == "gametip" then
            if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        else
            ns.Tip_Hide(button)
        end
        tipMode = nil
    end

    local function ShowTip()
        local s = D()
        local ar, ag, ab = ns.GetAccent()
        -- Cleared up front so every early return below leaves the LAST hover's
        -- route behind: HideTip reads this to decide whose tooltip to take away.
        tipMode = nil
        -- Unconfigured: the placeholder is the whole block, so the tooltip has
        -- to say where a plugin is actually picked.
        if not s.source then
            ns.Tip_Begin(button)
            ns.Tip_AddLine(L["SELECT_PLUGIN"], 1, 1, 1)
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_SETTINGS"], 1, 1, 1, ar, ag, ab)
            ns.Tip_Show()
            return
        end
        local obj = Obj()
        if not obj then return end
        if obj.OnEnter then
            tipMode = "own"
            pcall(obj.OnEnter, button)
            return
        end
        if obj.OnTooltipShow then
            tipMode = "gametip"
            GameTooltip:SetOwner(button, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            -- Same flip the owned tooltip does: a top bar drops its tooltip
            -- below itself, a bottom bar lifts it above.
            if barCtx.IsBarAtTop() then
                GameTooltip:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -6)
            else
                GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 6)
            end
            GameTooltip:ClearLines()
            if pcall(obj.OnTooltipShow, GameTooltip) then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
                tipMode = nil
            end
            return
        end
        ns.Tip_Begin(button)
        ns.Tip_AddLine(ns.LDBLabel(s.source, obj), 1, 1, 1)
        local body = LDBDisplayText(obj)
        if body then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(LDBStripColors(body), 0.8, 0.8, 0.8)
        end
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        ShowTip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        HideTip()
        inst:Refresh()
    end)
    button:SetScript("OnClick", function(_, mb)
        -- No plugin picked yet: nothing to forward the click to, so send the
        -- player to the picker instead of dead-ending there.
        if not D().source then
            -- Options surface is LoadOnDemand; load it so OpenBlockSettings exists.
            if not ns.OpenBlockSettings then EllesmereUI:EnsureLoaded() end
            if ns.OpenBlockSettings then
                ns.OpenBlockSettings(barCtx.id, blockCfg.id, "ldb")
            end
            return
        end
        local obj = Obj()
        if obj and obj.OnClick then pcall(obj.OnClick, button, mb) end
    end)
    button:SetScript("OnMouseWheel", function(_, delta)
        local obj = Obj()
        if obj and obj.OnMouseWheel then pcall(obj.OnMouseWheel, button, delta) end
    end)

    -- A source whose plugin registers later -- its addon loads after us, or on
    -- demand -- binds the moment it appears; without this the block would sit
    -- collapsed until something else happened to force a Refresh.
    local function OnCreated(_, name)
        if name == D().source and not inst._dead then
            Bind()
            inst:Refresh()
        end
    end

    function inst:Enable()
        content:Show()
        if not self.eventFrame then
            self.eventFrame = MakeEventFrame(self, function(me)
                if not me._dead then me:Refresh() end
            end)
        end
        RegisterInstEvents(self)
        local LDB = ns.GetLDB()
        if LDB then
            pcall(LDB.RegisterCallback, inst, "LibDataBroker_DataObjectCreated", OnCreated)
        end
        Bind()
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        local LDB = ns.GetLDB()
        if LDB then
            pcall(LDB.UnregisterCallback, inst, "LibDataBroker_DataObjectCreated")
        end
        Unbind()
        content:Hide()
    end

    function inst:GetAutoLength()
        if not content:IsShown() then return 0 end
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        local LDB = ns.GetLDB()
        if LDB then
            pcall(LDB.UnregisterCallback, inst, "LibDataBroker_DataObjectCreated")
        end
        Unbind()
        HideTip()
        content:Hide()
    end

    return inst
end
