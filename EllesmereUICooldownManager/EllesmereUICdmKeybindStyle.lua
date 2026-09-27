if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local _, ns = ...

-- Shared by live icons and the options preview. No events, hooks or polling.
-- Decorations belong to EUI's text overlay, never to a Blizzard frame.
local badges
local anchors = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

function ns.RefreshCDMKeybindBadge(text, bd, scale)
    local badge = badges and badges[text]
    local bgAlpha = bd and bd.keybindBackgroundA or 0
    local borderAlpha = bd and bd.keybindBorderA or 0
    local borderSize = bd and bd.keybindBorderSize or 1
    local enabled = bd and bd.showKeybind and (bgAlpha > 0 or (borderAlpha > 0 and borderSize > 0))
    if not enabled then
        if badge then
            badge.background:Hide()
            for i = 1, 4 do badge.edges[i]:Hide() end
        end
        return
    end

    if not badge then
        if not badges then badges = setmetatable({}, { __mode = "k" }) end
        local parent = text:GetParent()
        badge = { background = parent:CreateTexture(nil, "BACKGROUND"), edges = {} }
        for i = 1, 4 do badge.edges[i] = parent:CreateTexture(nil, "BORDER") end
        badges[text] = badge
    end
    scale = scale or badge.scale or 1
    badge.scale = scale
    local padding = (bd.keybindPadding or 2) * scale
    local bg = badge.background
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", text, "TOPLEFT", -padding, padding)
    bg:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", padding, -padding)
    bg:SetColorTexture(bd.keybindBackgroundR or 0, bd.keybindBackgroundG or 0,
        bd.keybindBackgroundB or 0, bgAlpha)

    local edges = badge.edges
    for i = 1, 4 do
        edges[i]:ClearAllPoints()
        edges[i]:SetColorTexture(bd.keybindBorderR or 1, bd.keybindBorderG or 1,
            bd.keybindBorderB or 1, borderAlpha)
    end
    edges[1]:SetPoint("TOPLEFT", bg, "TOPLEFT"); edges[1]:SetPoint("TOPRIGHT", bg, "TOPRIGHT")
    edges[2]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT", bg, "TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
    edges[4]:SetPoint("TOPRIGHT", bg, "TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
    local thickness = math.max(0, borderSize) * scale
    edges[1]:SetHeight(thickness); edges[2]:SetHeight(thickness)
    edges[3]:SetWidth(thickness); edges[4]:SetWidth(thickness)

    -- A recycled/unbound icon must never leave an empty badge behind.
    local value = text:GetText()
    local visible = text:IsShown() and value and value ~= ""
    bg:SetShown(visible and bgAlpha > 0 or false)
    for i = 1, 4 do
        edges[i]:SetShown(visible and borderAlpha > 0 and borderSize > 0 or false)
    end
end

function ns.StyleCDMKeybind(text, bd, anchor, scale, fontPath)
    if not bd.showKeybind then
        -- Existing textures can survive a bar/profile switch; no allocation.
        text:Hide()
        if badges and badges[text] then ns.RefreshCDMKeybindBadge(text, bd) end
        return
    end
    scale = scale or 1
    local font = bd.keybindFont
    if font and font ~= "__global" then fontPath = EllesmereUI.ResolveFontName(font) end
    local outline = bd.keybindOutline
    if outline == "NONE" or outline == "OUTLINE" or outline == "THICKOUTLINE" then
        EllesmereUI.PrimeFontShadow(text, false)
        text:SetFont(fontPath, (bd.keybindSize or 10) * scale,
            EllesmereUI.SlugFlag(outline == "NONE" and "SLUG" or outline .. ", SLUG"))
    else
        EllesmereUI.ApplyIconTextFont(text, fontPath, (bd.keybindSize or 10) * scale, "cdm")
    end
    local point = bd.keybindAnchor
    if not anchors[point] then point = bd.keybindAlign == "right" and "TOPRIGHT" or "TOPLEFT" end
    local right = point:find("RIGHT", 1, true)
    text:SetJustifyH(right and "RIGHT" or (point:find("LEFT", 1, true) and "LEFT" or "CENTER"))
    local x = (bd.keybindOffsetX or 2) * scale
    text:ClearAllPoints()
    text:SetPoint(point, anchor, point, right and -x or x, (bd.keybindOffsetY or -2) * scale)
    text:SetTextColor(bd.keybindR or 1, bd.keybindG or 1, bd.keybindB or 1, bd.keybindA or 0.9)
    if bd.keybindBackgroundA or bd.keybindBorderA or (badges and badges[text]) then
        ns.RefreshCDMKeybindBadge(text, bd, scale)
    end
end
