-------------------------------------------------------------------------------
--  EllesmereUIUnitFrames_PlayerAuras.lua
--  Simple reskin of Blizzard's standalone BuffFrame / DebuffFrame icons.
--  No reparenting, no repositioning -- Blizzard controls layout via Edit Mode.
-------------------------------------------------------------------------------
local addon, ns = ...

local GetFFD = EllesmereUI._GetFFD

local ICON_ZOOM = 0.055  -- same crop used by totem bar

-------------------------------------------------------------------------------
--  Settings helper
-------------------------------------------------------------------------------
local function PA()
    local db = ns.db
    return db and db.profile and db.profile.playerAuras
end

-------------------------------------------------------------------------------
--  Per-button skinning
-------------------------------------------------------------------------------
local function SkinAuraButton(btn, isDebuff)
    local cfg = PA()
    if not cfg then return end
    -- Skip layout anchors
    if btn.isAuraAnchor then return end

    local ffd = GetFFD(btn)
    if not ffd then return end

    -- Icon zoom crop (btn.Icon is a Frame in Midnight; find the Texture inside)
    local iconFrame = btn.Icon
    local iconTex
    if iconFrame then
        -- Try known child names first
        iconTex = iconFrame.Texture or iconFrame.texture
        -- Fallback: scan for the first Texture region
        if not iconTex and iconFrame.GetRegions then
            for i = 1, iconFrame:GetNumRegions() do
                local r = select(i, iconFrame:GetRegions())
                if r and r:IsObjectType("Texture") and r.SetTexCoord then
                    iconTex = r
                    break
                end
            end
        end
        -- iconFrame itself might be a Texture (pre-Midnight)
        if not iconTex and iconFrame.SetTexCoord then
            iconTex = iconFrame
        end
    end
    if iconTex and iconTex.SetTexCoord then
        iconTex:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)
    end

    -- Hide Blizzard border (alpha, not Hide, to avoid taint)
    -- Keep it visible on debuffs when noBorderDebuffs is enabled (colored border)
    if btn.Border then
        if isDebuff and cfg.noBorderDebuffs then
            btn.Border:SetAlpha(1)
        else
            btn.Border:SetAlpha(0)
        end
    end

    -- Duration text styling (btn.Duration may be a Frame containing a FontString)
    local durFS = btn.Duration
    if durFS and not durFS.SetFont and durFS.GetRegions then
        -- Duration is a Frame; find the FontString inside
        for i = 1, durFS:GetNumRegions() do
            local r = select(i, durFS:GetRegions())
            if r and r.SetFont then durFS = r; break end
        end
    end
    if durFS and durFS.SetFont then
        if cfg.showText then
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local outline = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "OUTLINE"
            durFS:SetFont(fontPath, cfg.textSize or 11, outline)
            if outline == "" then
                durFS:SetShadowOffset(1, -1)
                durFS:SetShadowColor(0, 0, 0, 1)
            else
                durFS:SetShadowOffset(0, 0)
            end
            durFS:SetTextColor(1, 1, 1, 1)
        else
            durFS:SetTextColor(0, 0, 0, 0)
        end
    end

    -- Count text styling
    local countFS = btn.Count
    if countFS and not countFS.SetFont and countFS.GetRegions then
        for i = 1, countFS:GetNumRegions() do
            local r = select(i, countFS:GetRegions())
            if r and r.SetFont then countFS = r; break end
        end
    end
    if countFS and countFS.SetFont then
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
        local outline = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "OUTLINE"
        countFS:SetFont(fontPath, cfg.textSize or 11, outline)
        if outline == "" then
            countFS:SetShadowOffset(1, -1)
            countFS:SetShadowColor(0, 0, 0, 1)
        else
            countFS:SetShadowOffset(0, 0)
        end
    end

    -- Pixel-perfect border using raw texture edges. No BackdropTemplate,
    -- no GetWidth() calls, so no taint from the Blizzard frame hierarchy.
    local anchorFrame = iconFrame or btn
    local PP = EllesmereUI.PP
    local bs = cfg.borderSize or 1
    local skipBorder = isDebuff and cfg.noBorderDebuffs
    if bs > 0 and PP and not skipBorder then
        local edges = ffd._paEdges
        if not edges then
            edges = {}
            for _, key in ipairs({ "top", "bottom", "left", "right" }) do
                local tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
                edges[key] = tex
            end
            ffd._paEdges = edges
        end
        local scaledBS = PP.Scale(bs)
        local bR = cfg.borderR or 0
        local bG = cfg.borderG or 0
        local bB = cfg.borderB or 0
        local bA = cfg.borderA or 1

        local top = edges.top
        top:SetColorTexture(bR, bG, bB, bA)
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
        top:SetHeight(scaledBS)
        top:Show()

        local bottom = edges.bottom
        bottom:SetColorTexture(bR, bG, bB, bA)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(scaledBS)
        bottom:Show()

        local left = edges.left
        left:SetColorTexture(bR, bG, bB, bA)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
        left:SetWidth(scaledBS)
        left:Show()

        local right = edges.right
        right:SetColorTexture(bR, bG, bB, bA)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(scaledBS)
        right:Show()
    elseif ffd._paEdges then
        for _, tex in pairs(ffd._paEdges) do tex:Hide() end
    end

    ffd._paSkinned = true
end

-------------------------------------------------------------------------------
--  Iterate and skin all visible aura buttons on a frame
-------------------------------------------------------------------------------
local function SkinAllButtons(frame, isDebuff)
    if not frame or not frame.auraFrames then return end
    for _, btn in pairs(frame.auraFrames) do
        if btn and btn.Icon and not btn.isAuraAnchor then
            SkinAuraButton(btn, isDebuff)
        end
    end
end

-------------------------------------------------------------------------------
--  Full refresh (called on setting change or UNIT_AURA)
-------------------------------------------------------------------------------
local function RefreshAll()
    if not (PA() and PA().enabled) then return end
    SkinAllButtons(BuffFrame, false)
    SkinAllButtons(DebuffFrame, true)
end
ns.RefreshPlayerAuras = RefreshAll

-------------------------------------------------------------------------------
--  Scale helper (applies iconSize via SetScale on AuraContainer)
-------------------------------------------------------------------------------
local _appliedBuffScale, _appliedDebuffScale

local function ApplyScale()
    local cfg = PA()
    if not cfg or not cfg.enabled then return end
    local nativeSize = 32
    local scale = (cfg.iconSize or nativeSize) / nativeSize

    if BuffFrame and BuffFrame.AuraContainer then
        if _appliedBuffScale ~= scale then
            BuffFrame.AuraContainer:SetScale(scale)
            _appliedBuffScale = scale
        end
    end
    if DebuffFrame and DebuffFrame.AuraContainer then
        if _appliedDebuffScale ~= scale then
            DebuffFrame.AuraContainer:SetScale(scale)
            _appliedDebuffScale = scale
        end
    end
end
ns.ApplyPlayerAuraScale = ApplyScale


-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Delay to let UF db initialize
        C_Timer.After(1, function()
            local cfg = PA()
            if not cfg or not cfg.enabled then return end

            -- Apply scale
            ApplyScale()

            -- Initial skin pass
            RefreshAll()

            -- Hook aura updates to catch new/changed buttons
            if BuffFrame and BuffFrame.AuraContainer then
                hooksecurefunc(BuffFrame.AuraContainer, "UpdateGridLayout", function()
                    C_Timer.After(0, RefreshAll)
                end)
            end
            if DebuffFrame and DebuffFrame.AuraContainer then
                hooksecurefunc(DebuffFrame.AuraContainer, "UpdateGridLayout", function()
                    C_Timer.After(0, RefreshAll)
                end)
            end

        end)
    end
end)
