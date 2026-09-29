if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local _, ns = ...

-- Shared by live icons and the options preview. No events, hooks or polling.
-- Decorations belong to EUI's text overlay, never to a Blizzard frame.
local PP = EllesmereUI.PP
local badges
local anchors = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Style pass (settings edges): builds the badge on first need, then places
-- and paints it for `bd`. It sits under the label's overlay so the label
-- always draws on top: the fill two levels down, its pixel border one down.
local function StyleBadge(text, bd, scale)
    local badge = badges and badges[text]
    local bgAlpha = bd and bd.keybindBackgroundA or 0
    local borderAlpha = bd and bd.keybindBorderA or 0
    local borderSize = bd and bd.keybindBorderSize or 1
    local on = bd and bd.showKeybind and (bgAlpha > 0 or (borderAlpha > 0 and borderSize > 0)) or false
    if not badge then
        if not on then return nil end
        if not badges then badges = setmetatable({}, { __mode = "k" }) end
        local f = CreateFrame("Frame", nil, text:GetParent())
        local fill = f:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        badge = { frame = f, fill = fill, rim = PP.CreateBorder(f, 1, 1, 1, 1, 1) }
        badges[text] = badge
    end
    badge.bd, badge.on = bd, on
    local f = badge.frame
    if not on then
        f:Hide()
        return badge
    end
    local level = text:GetParent():GetFrameLevel() - 2
    if level < 0 then level = 0 end
    f:SetFrameLevel(level)
    badge.rim:SetFrameLevel(level + 1)
    scale = scale or badge.scale or 1
    badge.scale = scale
    local padding = (bd.keybindPadding or 2) * scale
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", text, "TOPLEFT", -padding, padding)
    f:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", padding, -padding)
    badge.fill:SetColorTexture(bd.keybindBackgroundR or 0, bd.keybindBackgroundG or 0,
        bd.keybindBackgroundB or 0, bgAlpha)
    badge.fill:SetShown(bgAlpha > 0)
    if borderAlpha > 0 and borderSize > 0 then
        PP.UpdateBorder(f, borderSize, bd.keybindBorderR or 1, bd.keybindBorderG or 1,
            bd.keybindBorderB or 1, borderAlpha)
        badge.rim:Show()
    else
        badge.rim:Hide()
    end
    return badge
end

-- Visibility pass: the badge follows its label, so a recycled or unbound
-- icon never keeps an empty badge.
local function ShowBadge(text, badge)
    local shown = badge.on and text:IsShown()
    if shown then
        local value = text:GetText()
        shown = value ~= nil and value ~= ""
    end
    badge.frame:SetShown(shown)
end

-- Style + visibility: settings edges and the options preview.
local function RefreshBadge(text, bd, scale)
    local badge = StyleBadge(text, bd, scale)
    if badge then ShowBadge(text, badge) end
end
ns.RefreshCDMKeybindBadge = RefreshBadge

-- Visibility pass for the keybind apply paths (every CDM icon, the Rotation
-- Assist Icon). It restyles only when the label now belongs to other
-- settings than its last style pass (a recycled icon, a profile swap).
function ns.ShowCDMKeybindBadge(text, bd)
    local badge = badges and badges[text]
    if not badge then
        if not (bd and bd.showKeybind and (bd.keybindBackgroundA or bd.keybindBorderA)) then return end
        badge = StyleBadge(text, bd)
        if not badge then return end
    elseif badge.bd ~= bd then
        StyleBadge(text, bd)
    end
    ShowBadge(text, badge)
end

function ns.StyleCDMKeybind(text, bd, anchor, scale, fontPath)
    if not bd.showKeybind then
        -- Existing badges can survive a bar/profile switch; no allocation.
        text:Hide()
        if badges and badges[text] then RefreshBadge(text, bd) end
        return
    end
    scale = scale or 1
    local font = bd.keybindFont
    if font and font ~= "__global" then fontPath = EllesmereUI.ResolveFontName(font) end
    local size = (bd.keybindSize or 10) * scale
    local outline = bd.keybindOutline
    if outline == "NONE" then
        -- The suite's plain text: no outline token, drop shadow.
        EllesmereUI.ApplyModuleFont(text, fontPath, size, "cdm", "")
    elseif outline == "OUTLINE" or outline == "THICKOUTLINE" then
        EllesmereUI.ApplyModuleFont(text, fontPath, size, "cdm", EllesmereUI.SlugFlag(outline .. ", SLUG"))
    else
        EllesmereUI.ApplyIconTextFont(text, fontPath, size, "cdm")
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
        RefreshBadge(text, bd, scale)
    end
end
