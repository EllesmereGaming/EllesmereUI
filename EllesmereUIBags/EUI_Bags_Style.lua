if EUI_CLIENT_BLOCKED then return end
local ns = select(2, ...)
local EUI = EllesmereUI
local forever
local BAG_FRAME_SCALE = 0.8

--- The WoW Forever style a Bags profile p asks for: its own pick
--- (useForeverStyle true or false), else the look most of the profile's modules
--- use (EllesmereUI.ForeverLookMajority over addons, nil = the active
--- profile's), so a profile on the WoW Forever look gets it with no write.
function ns.BagsForeverWanted(p, addons)
    local pick = p and p.useForeverStyle
    if pick == nil then return EUI.ForeverLookMajority(addons) end
    return pick == true
end

-- Latched at the first read (0.5 s after login: every module has loaded), so a
-- change takes effect after the reload the Style page asks for.
function ns.BagsForever()
    if not EUI.IS_FOREVER then return false end
    if forever == nil then
        if not EUI.Lite.IsDBReady() then return false end
        forever = ns.BagsForeverWanted(EUI._bagsDB.profile)
    end
    return forever
end

local function InsetBagBackground(tex, owner)
    local inset = EUI.FOREVER_HEAVY.fill * BAG_FRAME_SCALE
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
end

function ns.SkinForeverBagWindow(owner, bg, overlay, hasTitle, hasPortrait)
    if not ns.BagsForever() then return end
    local nineSlice = hasPortrait and NineSliceUtil
    local layout = nineSlice and nineSlice.GetLayout and nineSlice.ApplyLayout and nineSlice.GetLayout("HeldBagLayout")
    local corner = layout and layout.TopLeftCorner
    local cornerInfo = corner and corner.atlas and C_Texture.GetAtlasInfo(corner.atlas)
    local heavyOK = EUI.ForeverHeavyOK()
    if cornerInfo and heavyOK then
        local border = CreateFrame("Frame", nil, owner)
        border:SetUsingParentLevel(true)
        border:SetScale(BAG_FRAME_SCALE)
        border.layoutType = "HeldBagLayout"
        nineSlice.ApplyLayout(border, layout)
        -- Let the straight rail cover the notch at the portrait corner's far end.
        local piece = border.TopLeftCorner
        local file = cornerInfo.file or cornerInfo.filename
        local width = 64
        if piece and file and cornerInfo.width > width then
            local left, right = cornerInfo.leftTexCoord, cornerInfo.rightTexCoord
            piece:SetTexture(file)
            piece:SetTexCoord(left, left + (right - left) * width / cornerInfo.width,
                cornerInfo.topTexCoord, cornerInfo.bottomTexCoord)
            piece:SetSize(width, cornerInfo.height)
        end
        if nineSlice.UpdateCornerCropping then
            local panel = { NineSlice = border }
            border:SetScript("OnSizeChanged", function(_, _, height)
                nineSlice.UpdateCornerCropping(panel, height)
            end)
        end
        -- Align the visible rim with the window; the native slices include a shadow.
        border:SetPoint("TOPLEFT", owner, "TOPLEFT", 1, -3)
        border:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -1, -4.5)
        owner._foreverBagPortraitFrame = border
    elseif heavyOK then
        local border = CreateFrame("Frame", nil, owner)
        border:SetUsingParentLevel(true)
        border:SetScale(BAG_FRAME_SCALE)
        border:SetAllPoints(owner)
        local heavy = EUI.ForeverHeavy(border, "ARTWORK", 1)
        EUI.ForeverHeavySeat(heavy, owner)
        EUI.ForeverHeavyTitle(heavy, hasTitle)
    else
        EUI.ForeverBorderSeat(EUI.ForeverBorder(owner, "ARTWORK", 1, nil, "slim"), owner)
    end
    if heavyOK then
        owner._foreverBagFrameScale = BAG_FRAME_SCALE
        InsetBagBackground(bg, owner)
        if overlay then InsetBagBackground(overlay, owner) end
    end
    bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    bg:SetVertexColor(0.55, 0.55, 0.55)
    return true
end

function ns.LayoutForeverBagHeader(header, height)
    local scale = header:GetParent()._foreverBagFrameScale or 1
    local trim = EUI.FOREVER_HEAVY.title.bottom * (1 - scale)
    -- The header starts one unit inside the window rim.
    header._foreverTitleY = 1 - 14 * scale
    header._foreverControlsY = 1 - 15 * scale
    header._foreverToolsY = -39 + trim
    header:SetHeight((height or 54) - trim)
end

function ns.SkinForeverBagTitle(title, count)
    local header = title:GetParent()
    local y = header._foreverTitleY
    title:ClearAllPoints()
    title:SetPoint("LEFT", header, "TOPLEFT", count and 55 or 40, y)
    title:SetPoint("RIGHT", header, "TOPRIGHT", count and -124 or -30, y)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    title:SetTextColor(1, 0.82, 0)
    if not count then return end
    count:ClearAllPoints()
    count:SetPoint("RIGHT", header, "TOPRIGHT", -31, y)
    count:SetWidth(85)
    count:SetJustifyH("RIGHT")
    count:SetWordWrap(false)
    count:SetTextColor(0.87, 0.77, 0.59)
end

function ns.ForeverBagSidebarInset(owner)
    return EUI.FOREVER_HEAVY.band * (owner._foreverBagFrameScale or 1)
end

function ns.AnchorBagSidebarIcon(icon, collapsed, left)
    icon:ClearAllPoints()
    if collapsed then
        icon:SetPoint("CENTER")
    else
        icon:SetPoint("LEFT", left, 0)
    end
end

function ns.SetForeverBagSectionColors(label, line, depth)
    local shade, alpha = 1, 0.5
    if depth == 1 then
        shade, alpha = 0.8, 0.25
    elseif depth and depth >= 2 then
        shade, alpha = 0.65, 0.15
    end
    label:SetTextColor(0.88 * shade, 0.77 * shade, 0.58 * shade)
    line:SetColorTexture(0.56, 0.41, 0.26, alpha)
end

function ns.AddForeverBagPortrait(header, texturePath)
    local border = header:GetParent()._foreverBagPortraitFrame
    local art = border or header
    local icon = art:CreateTexture(nil, "ARTWORK")
    local size = border and 36 or 28
    icon:SetSize(size, size)
    icon:SetTexture(texturePath)

    local mask = art:CreateMaskTexture()
    if border then
        icon:SetPoint("TOPLEFT", border, "TOPLEFT", -4, 1)
        mask:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, 0)
        mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 4)
    else
        icon:SetPoint("CENTER", header, "TOPLEFT", 16, -18)
        mask:SetAllPoints(icon)
    end
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    if not border and C_Texture.GetAtlasInfo("UI-Frame-Portrait") then
        local rim = header:CreateTexture(nil, "ARTWORK", nil, 1)
        rim:SetAtlas("UI-Frame-Portrait")
        rim:SetSize(40, 40)
        rim:SetPoint("CENTER", icon)
    end
end

function ns.PositionForeverBagClose(close)
    local header = close:GetParent()
    local scale = header:GetParent()._foreverBagFrameScale or 1
    close:ClearAllPoints()
    close:SetPoint("CENTER", header, "TOPRIGHT", -12, 1 - 13 * scale)
    local size = 25 * scale
    close:SetSize(size, size)
    if not C_Texture.GetAtlasInfo("RedButton-Exit") then return end
    close.icon:Hide()
    close:SetScript("OnEnter", nil)
    close:SetScript("OnLeave", nil)
    close:SetNormalAtlas("RedButton-Exit")
    if C_Texture.GetAtlasInfo("RedButton-exit-pressed") then
        close:SetPushedAtlas("RedButton-exit-pressed")
    end
    if C_Texture.GetAtlasInfo("RedButton-Highlight") then
        close:SetHighlightAtlas("RedButton-Highlight", "ADD")
    end
end

function ns.SkinForeverBagSearch(search, bg, placeholder, clear)
    local getAtlas = C_Texture.GetAtlasInfo
    search:SetHeight(20)
    if getAtlas("common-search-border-left") and getAtlas("common-search-border-middle")
        and getAtlas("common-search-border-right") then
        local left = search:CreateTexture(nil, "BACKGROUND")
        left:SetAtlas("common-search-border-left")
        left:SetSize(8, 20)
        left:SetPoint("LEFT", -5, 0)
        local right = search:CreateTexture(nil, "BACKGROUND")
        right:SetAtlas("common-search-border-right")
        right:SetSize(8, 20)
        right:SetPoint("RIGHT")
        bg:ClearAllPoints()
        bg:SetAtlas("common-search-border-middle")
        bg:SetPoint("TOPLEFT", left, "TOPRIGHT")
        bg:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    else
        bg:SetColorTexture(0.035, 0.03, 0.025, 0.92)
        local border = EUI.ForeverBorder(search, "ARTWORK", 1, nil, "slim")
        EUI.ForeverBorderSeat(border, search)
        EUI.ForeverBorderPaint(border, 0.65, 0.60, 0.52, 1, true)
    end

    local icon = search:CreateTexture(nil, "ARTWORK", nil, 2)
    if getAtlas("common-search-magnifyingglass") then
        icon:SetAtlas("common-search-magnifyingglass")
    else
        icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    end
    icon:SetSize(10, 10)
    icon:SetPoint("LEFT", 1, -1)
    icon:SetVertexColor(0.6, 0.6, 0.6)
    search:SetTextInsets(16, 20, 0, 0)
    placeholder:ClearAllPoints()
    placeholder:SetPoint("LEFT", search, "LEFT", 16, 0)
    placeholder:SetTextColor(0.35, 0.35, 0.35)
    if SEARCH then placeholder:SetText(SEARCH) end

    if getAtlas("common-search-clearbutton") then
        clear.tex:Hide()
        local glyph = clear:CreateTexture(nil, "ARTWORK")
        glyph:SetAtlas("common-search-clearbutton")
        glyph:SetSize(10, 10)
        glyph:SetPoint("CENTER")
        glyph:SetAlpha(0.7)
    end
end

function ns.SkinForeverBagFooter(footer, bg, separator)
    if separator then separator:Hide() end
    -- Keep the coin box on the bottom row when tracked currencies wrap.
    local rowCenter = footer:GetHeight() / 2
    bg:ClearAllPoints()
    bg:SetHeight(22)
    bg:SetPoint("LEFT", footer, "BOTTOMLEFT", 7, rowCenter)
    bg:SetPoint("RIGHT", footer, "BOTTOMRIGHT", -7, rowCenter)
    bg:SetColorTexture(0.025, 0.02, 0.015, 0.8)
    footer._coinBox = bg

    if not (C_Texture.GetAtlasInfo("common-coinbox-left")
        and C_Texture.GetAtlasInfo("common-coinbox-right")
        and C_Texture.GetAtlasInfo("_common-coinbox-center")) then return end

    local left = footer:CreateTexture(nil, "BACKGROUND", nil, 2)
    left:SetAtlas("common-coinbox-left")
    left:SetWidth(8)
    left:SetPoint("TOPLEFT", bg)
    left:SetPoint("BOTTOMLEFT", bg)
    local right = footer:CreateTexture(nil, "BACKGROUND", nil, 2)
    right:SetAtlas("common-coinbox-right")
    right:SetWidth(8)
    right:SetPoint("TOPRIGHT", bg)
    right:SetPoint("BOTTOMRIGHT", bg)
    local middle = footer:CreateTexture(nil, "BACKGROUND", nil, 2)
    middle:SetAtlas("_common-coinbox-center")
    middle:SetHorizTile(true)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end
