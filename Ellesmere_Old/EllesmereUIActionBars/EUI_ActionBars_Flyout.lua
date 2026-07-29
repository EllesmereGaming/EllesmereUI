-------------------------------------------------------------------------------
--  EllesmereUI Action Bars - Spell Flyout Reskin
--  Reskins Blizzard's native SpellFlyout buttons to match the parent bar's
--  shape, borders, and zoom. Purely visual -- no secure state is touched.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local SHAPE_MASKS              = ns.SHAPE_MASKS
local SHAPE_BORDERS            = ns.SHAPE_BORDERS
local SHAPE_ZOOM_DEFAULTS      = ns.SHAPE_ZOOM_DEFAULTS
local SHAPE_ICON_EXPAND        = ns.SHAPE_ICON_EXPAND
local SHAPE_ICON_EXPAND_OFFSETS = ns.SHAPE_ICON_EXPAND_OFFSETS
local SHAPE_INSETS             = ns.SHAPE_INSETS
local ResolveBorderThickness   = ns.ResolveBorderThickness
local EAB                      = ns.EAB
local EFD                      = ns.EFD

-------------------------------------------------------------------------------
--  SkinBlizzardFlyoutButton
--  Apply shape/border/zoom to a single SpellFlyout button.
-------------------------------------------------------------------------------
local function SkinBlizzardFlyoutButton(btn, shape, zoom, brdOn, cr, cg, cb, ca, sbR, sbG, sbB, sbA, brdSz)
    -- Strip default Blizzard art (one-time)
    local fd = EFD(btn)
    if not fd.blizzStripped then
        fd.blizzStripped = true
        local nt = btn.NormalTexture or btn:GetNormalTexture()
        if nt then nt:SetAlpha(0) end
        if btn.IconMask and EllesmereUI and EllesmereUI._hiddenParent then
            btn.IconMask:SetParent(EllesmereUI._hiddenParent)
        end
    end

    local icon = btn.icon or btn.Icon
    if not icon then return end

    if shape ~= "none" and shape ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[shape] then
        local maskTex = SHAPE_MASKS[shape]
        if not fd.shapeMask then
            fd.shapeMask = btn:CreateMaskTexture()
        end
        local mask = fd.shapeMask
        mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:ClearAllPoints()
        if brdSz and brdSz >= 1 then
            local PP = EllesmereUI and EllesmereUI.PP
            if PP then
                PP.Point(mask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
                PP.Point(mask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            else
                mask:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                mask:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            end
        else
            mask:SetAllPoints(btn)
        end
        mask:Show()
        pcall(icon.RemoveMaskTexture, icon, mask)
        icon:AddMaskTexture(mask)

        -- Expand icon for shape inset
        local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS and SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
        local shapeDefault = (SHAPE_ZOOM_DEFAULTS and SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
        local iconExp = (SHAPE_ICON_EXPAND or 0) + shapeOffset + ((zoom or 0) - shapeDefault) * 200
        if iconExp < 0 then iconExp = 0 end
        local halfIE = iconExp / 2
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then
            icon:ClearAllPoints()
            PP.Point(icon, "TOPLEFT", btn, "TOPLEFT", -halfIE, halfIE)
            PP.Point(icon, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", halfIE, -halfIE)
        end

        -- Shape texcoord expand
        local insetPx = SHAPE_INSETS and SHAPE_INSETS[shape] or 17
        local visRatio = (128 - 2 * insetPx) / 128
        local expand = ((1 / visRatio) - 1) * 0.5
        icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)

        -- Mask cooldown
        if btn.cooldown and not btn.cooldown:IsForbidden() then
            pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
            pcall(btn.cooldown.AddMaskTexture, btn.cooldown, mask)
            if btn.cooldown.SetSwipeTexture then
                pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, maskTex)
            end
            if btn.cooldown.SetUseCircularEdge then
                pcall(btn.cooldown.SetUseCircularEdge, btn.cooldown, true)
            end
        end

        -- Shape border
        if not fd.shapeBorder then
            fd.shapeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 6)
        end
        local borderTex = fd.shapeBorder
        pcall(borderTex.RemoveMaskTexture, borderTex, mask)
        borderTex:ClearAllPoints()
        borderTex:SetAllPoints(btn)
        if brdOn and SHAPE_BORDERS and SHAPE_BORDERS[shape] then
            borderTex:SetTexture(SHAPE_BORDERS[shape])
            borderTex:SetVertexColor(sbR, sbG, sbB, sbA)
            borderTex:Show()
        else
            borderTex:Hide()
        end

        if fd.borders and EllesmereUI and EllesmereUI.PP then
            EllesmereUI.PP.HideBorder(btn)
        end
    else
        -- Square / cropped / none
        if fd.shapeMask then
            pcall(icon.RemoveMaskTexture, icon, fd.shapeMask)
            if btn.cooldown and not btn.cooldown:IsForbidden() then
                pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, fd.shapeMask)
                pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, "")
            end
            fd.shapeMask:Hide()
        end
        if fd.shapeBorder then fd.shapeBorder:Hide() end

        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
        if shape == "cropped" then
            local z = zoom or 0
            icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif zoom and zoom > 0 then
            icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end

        local PP = EllesmereUI and EllesmereUI.PP
        if PP then
            if brdOn then
                if not fd.borders then
                    PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", -1)
                    fd.borders = PP.GetBorders(btn)
                end
                PP.UpdateBorder(btn, brdSz, cr, cg, cb, ca)
                PP.ShowBorder(btn)
            elseif fd.borders then
                PP.HideBorder(btn)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  OnBlizzardFlyoutShow
--  Fired via HookScript on SpellFlyout. Reads the parent button's bar
--  settings and applies styling to every visible flyout button.
-------------------------------------------------------------------------------
local function OnBlizzardFlyoutShow(flyout)
    local caller = flyout:GetParent()
    if not caller then return end

    local barKey = EFD(caller).barKey
    if not barKey then return end

    local prof = EAB and EAB.db and EAB.db.profile
    if not prof then return end
    local s = prof.bars and prof.bars[barKey]
    if not s then return end

    local shape = s.buttonShape or "none"
    local zoom = ((s.iconZoom or prof.iconZoom or 5.5)) / 100
    local brdSz = ResolveBorderThickness(s)
    local brdOn = brdSz > 0
    local brdColor = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
    end
    local shapeBrdColor = s.shapeBorderColor or brdColor
    local sbR, sbG, sbB, sbA = shapeBrdColor.r, shapeBrdColor.g, shapeBrdColor.b, shapeBrdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then sbR, sbG, sbB = cc.r, cc.g, cc.b end
        end
    end

    -- Hide Blizzard's flyout background art (re-applied every show,
    -- Blizzard resets these textures each time the flyout opens)
    if flyout.Background then
        if flyout.Background.End then flyout.Background.End:SetAlpha(0) end
        if flyout.Background.Start then flyout.Background.Start:SetAlpha(0) end
        if flyout.Background.HorizontalMiddle then flyout.Background.HorizontalMiddle:SetAlpha(0) end
        if flyout.Background.VerticalMiddle then flyout.Background.VerticalMiddle:SetAlpha(0) end
    end

    -- Skin each visible button
    for i = 1, flyout:GetNumChildren() do
        local child = select(i, flyout:GetChildren())
        if child and child:IsShown() and child.icon then
            SkinBlizzardFlyoutButton(child, shape, zoom, brdOn, cr, cg, cb, ca, sbR, sbG, sbB, sbA, brdSz)
        end
    end
end

-------------------------------------------------------------------------------
--  Hook Installation (deferred -- SpellFlyout may not exist at load time)
-------------------------------------------------------------------------------
local function InstallBlizzFlyoutHook()
    local sf = _G.SpellFlyout
    if not sf or not EFD then return false end
    if EFD(sf).hooked then return true end
    EFD(sf).hooked = true
    sf:HookScript("OnShow", OnBlizzardFlyoutShow)
    return true
end
if not InstallBlizzFlyoutHook() then
    -- Shell from the main file's pool: born at ActionBars' file scope so the
    -- handler work bills this addon (see the pool note there).
    local hookFrame = ns.TakeShell()
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        if InstallBlizzFlyoutHook() then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end

-------------------------------------------------------------------------------
--  EABFlyout API (thin wrapper over Blizzard's SpellFlyout)
--  The main file calls IsVisible/IsMouseOver/GetFrame for mouseover-fade
--  logic (keep bar visible while flyout is open). RegisterButton is now
--  a no-op since Blizzard handles flyout dispatch natively.
-------------------------------------------------------------------------------
local EABFlyout = {}

function EABFlyout:RegisterButton() end

function EABFlyout:IsVisible()
    local sf = _G.SpellFlyout
    return sf and sf:IsVisible()
end

function EABFlyout:IsMouseOver(...)
    local sf = _G.SpellFlyout
    return sf and sf:IsMouseOver(...)
end

function EABFlyout:GetFrame()
    return _G.SpellFlyout
end

function EABFlyout:GetParent()
    local sf = _G.SpellFlyout
    return sf and sf:GetParent()
end

ns.EABFlyout = EABFlyout
