if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Profession.lua
-- Profession block factories (primary and secondary).

local ADDON_NAME, ns = ...
local L = ns.L
local MEDIA = ns.MEDIA
local K = ns.BlockKit

-- Upvalues
local _G               = _G
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
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
local ParkSecureFrame      = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  PROFESSION (SECURE right-click passthrough to ProfessionMicroButton)
-------------------------------------------------------------------------------
-- Skill-line ID -> icon file in media\profession\ (one PNG per profession; filenames follow the art set's own stems, e.g. "blacksmith"/"engineer").
local profIcons = {
    [164] = "prof-blacksmith",   [165] = "prof-leatherworking", [171] = "prof-alchemy",
    [182] = "prof-herbalism",    [186] = "prof-mining",         [202] = "prof-engineer",
    [333] = "prof-enchanting",   [755] = "prof-jewelcrafting",  [773] = "prof-inscription",
    [197] = "prof-tailoring",    [393] = "prof-skinning",       [185] = "prof-cooking",
    [356] = "prof-fishing",
}

-- Shared builder for both profession blocks. secondary=false shows the two primary
-- professions (right-click = profession book); secondary=true shows Cooking+Fishing (right-click = Basic Campfire, a secure spell cast).
local CAMPFIRE_SPELL = 818   -- Basic Campfire
local function MakeProfessionBlock(blockCfg, slot, content, barCtx, secondary)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "TRADE_SKILL_DETAILS_UPDATE", "SPELLS_CHANGED" }

    local MEDIA_PROF = MEDIA .. "profession\\"
    local prof1, prof2 = {}, {}

    local function BC() return barCtx.cfg end

    local built = false
    local prof1Frame, prof1Icon, prof1Text, prof1Bar, prof1BarBg
    local prof2Frame, prof2Icon, prof2Text, prof2Bar, prof2BarBg

    local function UpdateProfValues()
        local p1, p2
        if secondary then
            local _, _, _, fishing, cooking = GetProfessions()
            p1, p2 = cooking, fishing
        else
            p1, p2 = GetProfessions()
        end
        prof1 = {}; prof2 = {}
        if p1 then
            local name, icon, rank, maxRank, _, _, id = GetProfessionInfo(p1)
            name = name or ""
            prof1 = { idx = p1, name = name, nameUpper = name:upper(), icon = icon, rank = rank or 0, maxRank = maxRank or 0, id = id }
        end
        if p2 then
            local name, icon, rank, maxRank, _, _, id = GetProfessionInfo(p2)
            name = name or ""
            prof2 = { idx = p2, name = name, nameUpper = name:upper(), icon = icon, rank = rank or 0, maxRank = maxRank or 0, id = id }
        end
    end

    local function StyleProfFrame(profData, profFrame, profIcon, profText, profBar, profBarBg)
        if not profData or not profData.idx then profFrame:Hide(); return end
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local iconSize = fontSize + 8
        local isSide = barCtx.IsVertical()

        local iconTex = profData.icon
        if profIcons[profData.id] then
            iconTex = MEDIA_PROF .. profIcons[profData.id] .. ".png"
        end
        -- Show Icon (default ON): hidden drops the icon and its gap from the layout; the text/bar stack keeps the icon's vertical band.
        local showIcon = (blockCfg.settings or {}).showIcon ~= false
        profIcon:SetTexture(iconTex)
        if showIcon then
            profIcon:SetSize(iconSize, iconSize); profIcon:Show()
        else
            profIcon:Hide()
        end
        local pbr, pbg, pbb = BlockColorOf(blockCfg)
        do
            local ir, ig, ib = IconColorOf(blockCfg)
            profIcon:SetVertexColor(ir, ig, ib, 1)
        end

        -- Font derives from CONTENT_BASE like every other block: the bar Height setting must never resize content.
        ns.SetFont(profText, fontSize, barCfg)
        profText:SetTextColor(pbr, pbg, pbb, 1); profText:SetText(profData.name or "")

        if isSide then
            local frameW = VSlotW(inst)
            local innerW = max(30, frameW - 8)
            local totalH = 8 + iconSize + 2

            profIcon:ClearAllPoints()
            profIcon:SetPoint("TOP", profFrame, "TOP", 0, -4)

            if not showIcon then totalH = 8 + 2 end

            ns.SetWrappedText(profText, innerW, "CENTER")
            profText:ClearAllPoints()
            if showIcon then
                profText:SetPoint("TOP", profIcon, "BOTTOM", 0, -2)
            else
                profText:SetPoint("TOP", profFrame, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(profText:GetStringHeight())

            if profData.rank ~= profData.maxRank then
                local ar, ag, ab = ns.GetAccent()
                local bH = 3
                profBar:Show()
                profBar:SetMinMaxValues(1, profData.maxRank); profBar:SetValue(profData.rank)
                profBar:SetStatusBarColor(ar, ag, ab, 1); profBarBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                profBar:SetSize(innerW, bH)
                profBar:ClearAllPoints()
                profBar:SetPoint("TOP", profText, "BOTTOM", 0, -3)
                totalH = totalH + 3 + bH
            else
                profBar:Hide()
            end

            profFrame:SetSize(frameW, max(totalH, barH))
            profFrame:Show()
        else
            ns.ResetInlineText(profText, "LEFT")
            profIcon:ClearAllPoints(); profIcon:SetPoint("LEFT", profFrame, "LEFT", 0, 0)

            -- Hidden icon: the stack anchors to the frame's LEFT center with the icon rect's half-band offsets, keeping vertical rhythm flush left.
            local halfBand = iconSize / 2
            if profData.rank == profData.maxRank then
                profBar:Hide()
                profText:ClearAllPoints()
                if showIcon then
                    profText:SetPoint("LEFT", profIcon, "RIGHT", ICON_GAP, 0)
                else
                    profText:SetPoint("LEFT", profFrame, "LEFT", 0, 0)
                end
            else
                profBar:Show()
                profText:ClearAllPoints()
                if showIcon then
                    profText:SetPoint("TOPLEFT", profIcon, "TOPRIGHT", ICON_GAP, 0)
                else
                    profText:SetPoint("TOPLEFT", profFrame, "LEFT", 0, halfBand)
                end
                local ar, ag, ab = ns.GetAccent()
                profBar:SetMinMaxValues(1, profData.maxRank); profBar:SetValue(profData.rank)
                profBar:SetStatusBarColor(ar, ag, ab, 1); profBarBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                -- Icon left; text top-right; bar bottom-right, sharing the text's
                -- left edge and tracking TEXT width, bottom-aligned to the icon (same recipe as xprep).
                local textW = max(profText:GetStringWidth(), 20)
                local bH = max(2, iconSize - fontSize - 3)
                profBar:SetSize(textW, bH)
                profBar:ClearAllPoints()
                if showIcon then
                    profBar:SetPoint("BOTTOMLEFT", profIcon, "BOTTOMRIGHT", ICON_GAP, 0)
                else
                    profBar:SetPoint("BOTTOMLEFT", profFrame, "LEFT", 0, -halfBand)
                end
            end
            local textW = max(profText:GetStringWidth(), 20)
            local effIcon = showIcon and (iconSize + ICON_GAP) or 0
            profFrame:SetSize(effIcon + textW, barH); profFrame:Show()
        end
    end

    local function OpenProf(prof)
        if not prof or not prof.id or InCombatLockdown() then return end
        local currInfo = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        if currInfo and currInfo.professionID == prof.id and _G.ProfessionsFrame and _G.ProfessionsFrame:IsShown() then
            C_TradeSkillUI.CloseTradeSkill()
        elseif prof.id then
            C_TradeSkillUI.OpenTradeSkill(prof.id)
        end
    end

    local function Build()
        if built then return end
        built = true

        local function MakeProfFrame(name)
            local f = CreateFrame("Button", name, content, "SecureActionButtonTemplate")
            f:SetSize(1, barCtx.GetThickness()); f:EnableMouse(true); f:RegisterForClicks("AnyUp")
            f:SetAttribute("useOnKeyDown", false)
            if secondary then
                -- Right-click = Basic Campfire, cast securely.
                f:SetAttribute("*type2", "spell")
                f:SetAttribute("*spell2", CAMPFIRE_SPELL)
            elseif _G.ProfessionMicroButton then
                f:SetAttribute("*type2", "click")
                f:SetAttribute("*clickbutton2", _G.ProfessionMicroButton)
            end
            local icon = f:CreateTexture(nil, "OVERLAY")
            local text = f:CreateFontString(nil, "OVERLAY")
            local bar  = CreateFrame("StatusBar", nil, f); bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local bg   = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
            return f, icon, text, bar, bg
        end

        prof1Frame, prof1Icon, prof1Text, prof1Bar, prof1BarBg = MakeProfFrame("EllesmereUIDataBarsProf1_" .. inst.key)
        prof2Frame, prof2Icon, prof2Text, prof2Bar, prof2BarBg = MakeProfFrame("EllesmereUIDataBarsProf2_" .. inst.key)
        AttachTextOffset(inst, prof1Text)
        AttachTextOffset(inst, prof2Text)

        local frames = { prof1Frame, prof2Frame }
        for i = 1, 2 do
            local frame = frames[i]
            local isFirst = (i == 1)
            -- HookScript, NOT SetScript: SetScript("OnClick") would overwrite SecureActionButton_OnClick
            -- and kill the secure *clickbutton2 passthrough to ProfessionMicroButton (right-click).
            frame:HookScript("OnClick", function(_, button)
                if button == "LeftButton" then
                    if isFirst then OpenProf(prof1) else OpenProf(prof2) end
                end
            end)
            frame:SetScript("OnEnter", function(f)
                local txt, ic = prof2Text, prof2Icon
                if isFirst then txt, ic = prof1Text, prof1Icon end
                local ar, ag, ab = ns.GetAccent()
                txt:SetTextColor(ar, ag, ab, 1)
                if ic then ic:SetVertexColor(ar, ag, ab, 1) end
                ns.Tip_Begin(f)
                local title
                if secondary then
                    title = SECONDARY_SKILLS or "Secondary Professions"
                else
                    title = TRADE_SKILLS or "Professions"
                end
                ns.Tip_AddLine(title, 1, 1, 1)
                ns.Tip_AddLine(" ")
                local function AddLine(p)
                    if not p or not p.name then return end
                    ns.Tip_AddDouble(p.name, EllesmereUI.COLOR_CODES.WHITE .. p.rank .. "|r / " .. p.maxRank, 1, 1, 1, 1, 1, 1)
                end
                if prof1.idx then AddLine(prof1) end
                if prof2.idx then AddLine(prof2) end
                ns.Tip_AddLine(" ")
                local rightLabel = L["OPEN_PROFESSION_BOOK"]
                if secondary then rightLabel = L["START_CAMPFIRE"] end
                ns.Tip_AddDouble(L["LEFT_CLICK"],  L["OPEN_PROFESSION"], 1, 1, 1, 1, 1, 1)
                ns.Tip_AddDouble(L["RIGHT_CLICK"], rightLabel,           1, 1, 1, 1, 1, 1)
                ns.Tip_Show()
            end)
            frame:SetScript("OnLeave", function(f)
                local txt, ic = prof2Text, prof2Icon
                if isFirst then txt, ic = prof1Text, prof1Icon end
                local br, bgr, bb = BlockColorOf(blockCfg)
                txt:SetTextColor(br, bgr, bb, 1)
                -- Icon restores through ICON color (accent by default for professions), NOT the text color, which paints it white.
                if ic then
                    local ir, ig, ib = IconColorOf(blockCfg)
                    ic:SetVertexColor(ir, ig, ib, 1)
                end
                ns.Tip_Hide(f)
            end)
        end
    end

    if InCombatLockdown() then
        ns.DeferUntilOOC("edbbuild:" .. inst.key, function()
            if inst._dead then return end
            Build()
            inst:Refresh()
        end)
    else
        Build()
    end

    function inst:Refresh()
        if not built or InCombatLockdown() then return end
        UpdateProfValues()
        local barH, gap = barCtx.GetThickness(), 5
        local isSide = barCtx.IsVertical()

        StyleProfFrame(prof1, prof1Frame, prof1Icon, prof1Text, prof1Bar, prof1BarBg)
        StyleProfFrame(prof2, prof2Frame, prof2Icon, prof2Text, prof2Bar, prof2BarBg)

        if isSide then
            local slotW = VSlotW(inst)
            local totalH = 0
            if prof1.idx and prof1Frame:IsShown() then
                prof1Frame:ClearAllPoints()
                prof1Frame:SetPoint("TOP", content, "TOP", 0, 0)
                totalH = totalH + prof1Frame:GetHeight()
            end
            if prof2.idx and prof2Frame:IsShown() then
                prof2Frame:ClearAllPoints()
                if prof1.idx and prof1Frame:IsShown() then
                    prof2Frame:SetPoint("TOP", prof1Frame, "BOTTOM", 0, -4)
                    totalH = totalH + 4
                else
                    prof2Frame:SetPoint("TOP", content, "TOP", 0, 0)
                end
                totalH = totalH + prof2Frame:GetHeight()
            end
            content:SetSize(slotW, max(totalH, 1))
        else
            content:SetHeight(barH)
            if prof1.idx and prof1Frame:IsShown() then
                prof1Frame:ClearAllPoints(); prof1Frame:SetPoint("LEFT", content, "LEFT", 0, 0)
            end
            if prof2.idx and prof2Frame:IsShown() then
                prof2Frame:ClearAllPoints()
                if prof1.idx and prof1Frame:IsShown() then
                    prof2Frame:SetPoint("LEFT", prof1Frame, "RIGHT", gap, 0)
                else
                    prof2Frame:SetPoint("LEFT", content, "LEFT", 0, 0)
                end
            end

            local totalW = 0
            if prof1.idx and prof1Frame:IsShown() then totalW = totalW + prof1Frame:GetWidth() end
            if prof2.idx and prof2Frame:IsShown() then totalW = totalW + gap + prof2Frame:GetWidth() end
            content:SetWidth(max(totalW, 1))
        end
        if not prof1.idx and not prof2.idx then content:Hide() else content:Show() end
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
        if not built then return 40 end
        if barCtx.IsVertical() then
            local barH = barCtx.GetThickness()
            local p1H, p2H = 0, 0
            if prof1Frame and prof1Frame:IsShown() then p1H = prof1Frame:GetHeight() or 0 end
            if prof2Frame and prof2Frame:IsShown() then p2H = prof2Frame:GetHeight() or 0 end
            local gap = 0
            if p1H > 0 and p2H > 0 then gap = 5 end
            return max(p1H + gap + p2H, barH, 50)
        end
        return max(content:GetWidth() or 80, 30)
    end

    function inst:Destroy()
        self._dead = true
        if prof1Frame then ParkSecureFrame(prof1Frame, self.key .. "_prof1") end
        if prof2Frame then ParkSecureFrame(prof2Frame, self.key .. "_prof2") end
        content:Hide()
    end

    return inst
end

ns.BlockFactories.profession = function(blockCfg, slot, content, barCtx)
    return MakeProfessionBlock(blockCfg, slot, content, barCtx, false)
end

ns.BlockFactories.profession2 = function(blockCfg, slot, content, barCtx)
    return MakeProfessionBlock(blockCfg, slot, content, barCtx, true)
end
