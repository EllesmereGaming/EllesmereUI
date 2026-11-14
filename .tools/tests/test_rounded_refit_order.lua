-- Stub harness: rounded outlines that must be fit again after their host's scale or place changed.
--   * the drag-to-reorder list of a cog popup sets its scale in its own OnShow: it is seated
--     (EllesmereUI.SeatDropdownMenu) and its outline refit after that scale, whichever of the two
--     OnShow scripts the game runs first (the list's or its outline layer's);
--   * the Spec Overrides popup's card rows are refit after the popup took its new height (a
--     screen clamp can move the popup then);
--   * the Conditional Overrides condition picker refits its key row and its two buttons when the
--     Keybind row changes its height while it shows;
--   * a refit reshapes the outline it has: no frame, texture or mask is made.
-- Loads the real EllesmereUI_RoundedCorners.lua and the real SeatDropdownMenu block, and cuts the
-- real OnShow lines of the reorder list, the real tail of RefreshCardsPopup and the real key row
-- sync out of their files, over fake frames whose rects come from their anchors, scales and a
-- screen clamp. An outline is sharp when its layer's four edges sit on whole physical pixels.
--   lua .tools/tests/test_rounded_refit_order.lua        (from the repository root)
local function Read(name)
    local f = assert(io.open(name, "rb"))
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local PX = 768 / 1080          -- the effective scale of one unit per physical pixel
local UI = 0.71                -- a UI Scale that does not match the screen
local created = { frame = 0, tex = 0, mask = 0 }

-------------------------------------------------------------------------------
-- Fake frames: a rect resolved from anchors, scales and a bottom screen clamp
-------------------------------------------------------------------------------
local Frame = {}
Frame.__index = Frame
local function NewFrame(parent)
    created.frame = created.frame + 1
    local f = setmetatable({ parent = parent, scale = 1, ignore = false, points = {},
        w = 0, h = 0, scripts = {}, children = {} }, Frame)
    if parent then parent.children[#parent.children + 1] = f end
    return f
end
function Frame:GetEffectiveScale()
    if self.absEff then return self.absEff end
    if self.ignore then return self.scale end
    return (self.parent and self.parent:GetEffectiveScale() or 1) * self.scale
end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale end
function Frame:SetIgnoreParentScale(v) self.ignore = v end
function Frame:SetAllPoints(rel)
    rel = rel or self.parent
    self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(pt, rel, rpt, x, y)
    for i, p in ipairs(self.points) do
        if p[1] == pt then table.remove(self.points, i) break end
    end
    self.points[#self.points + 1] = { pt, rel, rpt or pt, x or 0, y or 0 }
end
function Frame:GetNumPoints() return #self.points end
function Frame:GetPoint(i) local p = self.points[i]; return p[1], p[2], p[3], p[4], p[5] end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
local function AbsPoint(f, pt)
    local l, t, r, b = f:AbsRect()
    if not l then return nil end
    if pt == "TOPLEFT" then return l, t
    elseif pt == "BOTTOMLEFT" then return l, b
    elseif pt == "BOTTOMRIGHT" then return r, b
    elseif pt == "TOPRIGHT" then return r, t end
    error("point " .. tostring(pt))
end
function Frame:AbsRect()
    if self.abs then return self.abs[1], self.abs[2], self.abs[3], self.abs[4] end
    if #self.points == 0 then return nil end      -- unanchored: no rect, as in game
    local e = self:GetEffectiveScale()
    local l, t, r, b
    for _, p in ipairs(self.points) do
        local ax, ay = AbsPoint(p[2], p[3])
        if not ax then return nil end
        ax, ay = ax + p[4] * e, ay + p[5] * e
        if p[1] == "TOPLEFT" then l, t = ax, ay
        elseif p[1] == "BOTTOMRIGHT" then r, b = ax, ay
        elseif p[1] == "TOPRIGHT" then r, t = ax, ay end
    end
    if not l then l = r - self.w * e end
    if not r then r = l + self.w * e end
    if not b then b = t - self.h * e end
    if self.clamped and b < 0 then t, b = t - b, 0 end   -- SetClampedToScreen, screen bottom at 0
    return l, t, r, b
end
function Frame:GetLeft() local l = self:AbsRect(); return l and l / self:GetEffectiveScale() end
function Frame:GetTop() local l, t = self:AbsRect(); return l and t / self:GetEffectiveScale() end
function Frame:GetRight() local l, _, r = self:AbsRect(); return l and r / self:GetEffectiveScale() end
function Frame:GetBottom() local l, _, _, b = self:AbsRect(); return l and b / self:GetEffectiveScale() end
function Frame:GetSize()
    local l, t, r, b = self:AbsRect()
    if not l then return self.w, self.h end       -- the explicit size of an unanchored frame
    local e = self:GetEffectiveScale()
    return (r - l) / e, (t - b) / e
end
function Frame:SetFrameLevel() end
function Frame:GetFrameLevel() return 1 end
function Frame:EnableMouse() end
function Frame:SetScript(n, fn) self.scripts[n] = fn end
function Frame:IsVisible() return true end
function Frame:IsShown() return true end
function Frame:GetObjectType() return "Frame" end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetRegions() end

local Tex = {}
Tex.__index = Tex
local function NewTex(kind)
    created[kind] = created[kind] + 1
    return setmetatable({ masks = {} }, Tex)
end
for _, m in ipairs({ "SetAllPoints", "SetPoint", "SetVertexColor", "SetTextureSliceMargins",
    "SetTextureSliceMode", "SetColorTexture" }) do Tex[m] = function() end end
function Tex:SetTexture(p) self.path = p end
function Tex:AddMaskTexture(m) self.masks[#self.masks + 1] = m end
function Tex:RemoveMaskTexture(m)
    for i = #self.masks, 1, -1 do if self.masks[i] == m then table.remove(self.masks, i) end end
end
function Tex:IsObjectLoaded() return true end
function Tex:GetObjectType() return "Texture" end
function Frame:CreateTexture() return NewTex("tex") end
function Frame:CreateMaskTexture() return NewTex("mask") end

-------------------------------------------------------------------------------
-- The real pieces
-------------------------------------------------------------------------------
Enum = { UITextureSliceMode = { Stretched = 1 } }
issecretvalue = function() return false end
C_Timer = { After = function() end }
CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame(nil)
UIParent.scale = UI
EllesmereUI = {
    _Pool = { CreateFrame = function(_, _, parent) return NewFrame(parent) end, Gen = function() return 1 end },
    PP = { perfect = PX },
}
assert(loadstring(Read("EllesmereUI_RoundedCorners.lua"), "@EllesmereUI_RoundedCorners.lua"))()

local W = Read("EllesmereUIOptions/EllesmereUI_Widgets.lua")
local a = assert(W:find("do\n    local floor, abs = math.floor, math.abs\n    function EllesmereUI.SeatDropdownMenu", 1, true), "SeatDropdownMenu not found")
local endMark = "        menu._seatedX, menu._seatedY = x, y\n    end\nend\n"
local e = assert(W:find(endMark, a, true), "the end of SeatDropdownMenu not found")
assert(loadstring(W:sub(a, e + #endMark - 1), "@SeatDropdownMenu"))()

local C = Read("EllesmereUIOptions/EllesmereUI_Widgets_CogPopup.lua")
local s1 = assert(C:find("self:SetScale(ddBtn:GetEffectiveScale() / UIParent:GetEffectiveScale())", 1, true), "the reorder list's OnShow not found")
local s2 = assert(C:find("self:SetScript(\"OnUpdate\", function(m)", s1, true))
local MenuOnShow = assert(loadstring("local ddBtn, mBrd2 = ...\nreturn function(self)\n" .. C:sub(s1, s2 - 1) .. "\nend", "@the reorder list's OnShow"))

local S = Read("EUI_SpecOverrides_Popups.lua")
local t1 = assert(S:find("    p:SetHeight(-y + 12)\n", 1, true), "the tail of RefreshCardsPopup not found")
local t2 = assert(S:find("\nend\nSetRefreshCardsPopup(RefreshCardsPopup)", t1, true))
local CardsTail = assert(loadstring("return function(p, y)\n" .. S:sub(t1, t2) .. "end", "@the tail of RefreshCardsPopup"))()

local function Whole(v) return math.abs(v - math.floor(v + 0.5)) < 1e-6 end
local function Sharp(o)
    local l, t, r, b = o._frame:AbsRect()
    return Whole(l / PX) and Whole(t / PX) and Whole(r / PX) and Whole(b / PX)
end
local function Made() return created.frame + created.tex + created.mask end

-------------------------------------------------------------------------------
-- 1. the cog popup's reorder list, in both OnShow orders
-------------------------------------------------------------------------------
local function NewList()
    local ddBtn = NewFrame(nil)
    local menu = NewFrame(UIParent)
    menu:SetWidth(200)
    menu:SetHeight(150)
    local outline = EllesmereUI.MakeRoundedBorder(menu, 1, 1, 1, 0.5, menu:CreateTexture(), nil, true)
    menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
    local onShow = MenuOnShow(ddBtn, outline)
    local layer = outline._frame
    -- eff: the button's effective scale; bx, by: its bottom-left corner, off the pixel grid
    local function Open(eff, bx, by, layerFirst)
        ddBtn.absEff = eff
        ddBtn.abs = { bx, by + 24 * eff, bx + 180 * eff, by }
        if layerFirst then
            layer.scripts.OnShow(layer)
            onShow(menu)
        else
            onShow(menu)
            layer.scripts.OnShow(layer)
        end
        local ml, mt = menu:AbsRect()
        return Sharp(outline), Whole(ml / PX) and Whole(mt / PX)
    end
    return menu, Open
end
for _, layerFirst in ipairs({ true, false }) do
    local order = layerFirst and "the outline's OnShow first" or "the list's OnShow first"
    local menu, Open = NewList()
    local sharp, seated = Open(UI * 1.00, 512.337, 401.219, layerFirst)
    check(sharp and seated, order .. ": at Window Scale 100% the outline is soft or the list off the pixel grid")
    sharp, seated = Open(UI * 0.75, 498.113, 377.641, layerFirst)
    check(sharp, order .. ": after a change to 75% without a reload the outline is soft")
    check(seated, order .. ": after a change to 75% the list is off the pixel grid")
    local before = Made()
    for i = 1, 40 do Open(UI * (i % 2 == 0 and 0.75 or 0.80), 498.113 + i * 0.37, 377.641 - i * 0.11, layerFirst) end
    check(Made() == before, order .. ": 40 more opens made " .. (Made() - before) .. " frames, textures or masks")
    local _, _, _, x, y = menu:GetPoint(1)
    check(math.abs(x) < 1.5 and math.abs(y + 2) < 1.5, order .. ": the list drifted from its place under the button (" .. x .. ", " .. y .. ")")
end
-- a list never opened before, first opened at 75% (a /reload at that Window Scale)
do
    local _, Open = NewList()
    check((Open(PX * 0.75, 498.113, 377.641, true)), "a first open at Window Scale 75% leaves the outline soft")
end

-------------------------------------------------------------------------------
-- 2. the Spec Overrides popup: its cards after a height change under a clamp
-------------------------------------------------------------------------------
do
    local anchorBtn = NewFrame(nil)
    anchorBtn.absEff = UI * 0.75
    anchorBtn.abs = { 900.17, 230.29, 930.41, 200.37 }
    local p = NewFrame(UIParent)
    p.absEff = UI * 0.75
    p.clamped = true
    p:SetSize(280, 100)
    p:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 4, -8)
    p._brd = EllesmereUI.MakeRoundedBorder(p, 1, 1, 1, 0.15, p:CreateTexture())
    p._cards = {}
    local y = -40
    for i = 1, 12 do
        local row = NewFrame(p)
        row._brd = EllesmereUI.MakeRoundedBorder(row, 1, 1, 1, 0.08, row:CreateTexture())
        row:SetSize(260, 40)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y)
        p._cards[i] = row
        y = y - 44
    end
    p._cardN = 12
    -- the rows fit as they show, at the popup's old height
    for i = 1, 12 do
        local layer = p._cards[i]._brd._frame
        layer.scripts.OnShow(layer)
    end
    p._brd:Fit()
    local before = Made()
    CardsTail(p, y - 26)             -- the new height pushes the popup against the screen's bottom edge
    check(Made() == before, "the popup's refits made " .. (Made() - before) .. " frames, textures or masks")
    local _, _, _, bottom = p:AbsRect()
    check(bottom == 0, "the popup was not moved by its screen clamp (the case under test)")
    check(Sharp(p._brd), "the popup's own outline is soft after its new height")
    local sharp = 0
    for i = 1, 12 do if Sharp(p._cards[i]._brd) then sharp = sharp + 1 end end
    check(sharp == 12, "after the clamp moved the popup only " .. sharp .. " of 12 card outlines are sharp")
    -- a popup with no card laid out, and one whose cards were never built: no error
    p._cardN = 0
    check(pcall(CardsTail, p, -66), "a popup with no card laid out fails")
    p._cards = nil
    check(pcall(CardsTail, p, -66), "a popup whose cards were never built fails")
end

-------------------------------------------------------------------------------
-- 3. the condition picker: the key row and both buttons refit with the height
-------------------------------------------------------------------------------
do
    local k1 = assert(S:find("        p._syncKeyRow = function()\n", 1, true), "the key row sync not found")
    local k2 = assert(S:find("\n        end\n", k1, true))
    local fits = {}
    local function Outline(name)
        return { Fit = function() fits[#fits + 1] = name end }
    end
    local shownKeyRow, height
    local p = { _staged = {}, _brd = Outline("popup") }
    function p:SetHeight(h) height = h end
    local keyRow = { SetShown = function(_, v) shownKeyRow = v end }
    assert(loadstring("local p, keyRow, kbrd, y, ShowKeyText = ...\n" .. S:sub(k1, k2 + #"\n        end") .. "\n", "@the key row sync"))(
        p, keyRow, Outline("key"), -200, function() end)
    -- before the two buttons exist (the first call of a build order that syncs early): no error
    check(pcall(p._syncKeyRow), "the key row sync fails before the buttons are built")
    p._nextBrd, p._cancelBrd = Outline("next"), Outline("cancel")
    fits = {}
    p._staged.keybind = true
    p._syncKeyRow()
    check(shownKeyRow == true and height == 200 + 56 + 34, "the Keybind row does not show and add its height")
    local seen = table.concat(fits, " ")
    check(seen:find("popup", 1, true) ~= nil, "the popup outline is not refit with the height")
    check(seen:find("key", 1, true) ~= nil, "the key button's outline is not refit when its row shows")
    check(seen:find("next", 1, true) ~= nil and seen:find("cancel", 1, true) ~= nil, "the two buttons at the moved bottom edge are not refit (" .. seen .. ")")
    check(S:find("        p._nextBrd = nbrd\n", 1, true) ~= nil and S:find("        p._cancelBrd = xbrd2\n", 1, true) ~= nil,
        "the picker does not keep its two button outlines for the sync")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_rounded_refit_order (%d checks)"):format(count))
