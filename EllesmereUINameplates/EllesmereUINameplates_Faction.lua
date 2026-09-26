if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUINameplates_Faction.lua
--  Faction badge (Horde/Alliance) on friendly nameplates. Enemy plates carry it
--  as a Core Positions slot element (NameplateFrame:UpdateFaction); friendly
--  plates have no slots, so the badge sits just left of the FriendlyFrame's
--  name (full plates only: name-only plates stay just the name). This matters
--  most for unflagged opposite-faction players, who cannot be attacked and so
--  get friendly plates. Which badge (if any) and whether it is dimmed come from
--  ns.NP_FactionBadge, shared with enemy plates; the badge shows while the
--  faction slot is set (not "None").
-------------------------------------------------------------------------------
local _, ns = ...

local badges = {} -- nameplate -> badge frame (reused with the nameplate)

local function GetBadge(nameplate)
    local b = badges[nameplate]
    if not b then
        b = CreateFrame("Frame", nil, nameplate)
        b:SetFrameStrata("MEDIUM")
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:Hide()
        badges[nameplate] = b
    end
    return b
end

-- The target's left arrow sits just left of the name; while the badge is up it
-- moves out past the badge instead of under it. Same fully-anchored form as
-- the friendly plate builds (point+size regions drift inside plate subtrees).
local function ArrowTo(fp, anchor)
    local la = fp.leftArrow
    if not la or fp._facArrowTo == anchor then return end
    fp._facArrowTo = anchor
    local x = -(2 + la:GetWidth() / 2)
    la:ClearAllPoints()
    la:SetPoint("TOP", anchor, "LEFT", x, 8)
    la:SetPoint("BOTTOM", anchor, "LEFT", x, -8)
end

-- Draw (or hide) the badge beside a friendly full plate's name. No events of
-- its own: the friendly plate's SetUnit, the main file's shared UNIT_FACTION
-- dispatch and settings passes call it. A friendly plate exists only in
-- full-plate mode and is released before its unit becomes an enemy plate.
local function Refresh(fp)
    local nameplate, unit = fp.nameplate, fp.unit
    if not (nameplate and unit) then return end
    local b = badges[nameplate]
    local atlas, dim
    -- Slot None: no unit queries, only a badge left up from before is hidden.
    if ns.NP_GetFactionSlot() ~= "none" then atlas, dim = ns.NP_FactionBadge(unit) end
    local fs = fp.name
    if not (atlas and fs) then
        if b then b:Hide() end
        if fs then ArrowTo(fp, fs) end
        return
    end
    b = b or GetBadge(nameplate)
    local sz = ns.NP_GetFactionIconSize()
    b:SetSize(sz, sz)
    b:SetFrameLevel(nameplate:GetFrameLevel() + 5)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", fs, "LEFT", -2, 0)
    -- Repaint only when the art or the dim changes (inputs: faction, Icon Style, dim).
    local style = ns.NP_GetFactionStyle()
    if b.facArt ~= atlas or b.facStyle ~= style then
        EllesmereUI.SetFactionArt(b.tex, style, atlas)
        b.facArt, b.facStyle = atlas, style
    end
    if b.facDim ~= dim then
        b.tex:SetDesaturated(dim)
        b.tex:SetAlpha(dim and 0.6 or 1)
        b.facDim = dim
    end
    b:Show()
    ArrowTo(fp, b)
end

ns.NP_FriendlyFactionRefresh = Refresh

-- The friendly plate is released (plate removed, switch to name-only) or its
-- unit promoted to an enemy plate, which draws its own badge.
function ns.NP_FriendlyFactionHide(fp)
    local b = fp.nameplate and badges[fp.nameplate]
    if b then b:Hide() end
    if fp.name then ArrowTo(fp, fp.name) end
end

-- Every friendly full plate: runs after a settings change or profile switch.
function ns.NP_RefreshFriendlyFaction()
    -- Slot None costs one compare per plate: Refresh hides and puts arrows back.
    for _, fp in pairs(ns.friendlyPlates) do Refresh(fp) end
end
