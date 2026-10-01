if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Looking For Group on WoW Forever
--
--  Forever's Looking For Group window is the vanilla LFGParentFrame (from the
--  load-on-demand Blizzard_GroupFinder_VanillaStyle), not retail's PVEFrame, so
--  the retail Group Finder skin never reaches it. This skins it under the same
--  card and key ("lfg", enable key reskinLFGMenu): the listing, group browser
--  and who list views, their controls, result rows, side tabs, comment box,
--  row checkboxes and the group-entry tooltip. Forever only.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local WSkin = ns.WSkin
if not (WSkin and WSkin.RegisterWindow and WSkin.Shell) then return end

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

do
-- Chrome atlases covering the house shell: the metal frame and textured backdrops.
local LFG_FADE = {
    "ui-frame-metal", "ui-frame-portraitmetal", "toptilestreaks",
    "groupfinder-background", "groupfinder-stat-stonebg", "common-insideframe",
    "gamepad-uiframemetal", "groupfinder-button-cover",
}
local VIEWS = { "LFGBrowseFrame", "LFGListingFrame", "LFGWhoListFrame" }
-- Views whose plain grey BACKGROUND fill (no atlas) sits over the shell.
local FILL_VIEWS = { "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame",
    "LFGListingFrameCategoryView", "LFGListingFrameActivityView", "LFGListingFrameLockedView" }
-- Views that repaint the window when swapped in.
local SHOW_VIEWS = { "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame",
    "LFGListingFrameCategoryView", "LFGListingFrameActivityView" }
local BUTTONS = {
    "LFGBrowseFrameRefreshButton", "LFGBrowseFrameOptionsButton",
    "LFGBrowseFrameSendMessageButton", "LFGBrowseFrameGroupInviteButton",
    "LFGListingFrameBackButton", "LFGListingFramePostButton",
}
local DROPDOWNS = { "LFGBrowseFrameCategoryDropdown", "LFGBrowseFrameActivityDropdown" }
local SIDE_TABS = { "ListingTab", "BrowsingTab", "WhoListingTab" }
-- Border hugs the dark box; white hover over it.
local CHECK_OPTS = { borderInset = 4, hover = 0.18 }

-- FontStrings already given the house font (pooled lines are reused as is).
local fonted = setmetatable({}, { __mode = "k" })
local function FontOnce(fs)
    if fonted[fs] then return end
    fonted[fs] = true
    WSkin.Font(fs)
end

local function FadeLFGArt(fr, depth)
    if depth > 5 or not fr or fr:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(fr) then return end
    local regions = { fr:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local a = r.GetAtlas and r:GetAtlas()
        if a then
            local la = a:lower()
            for _, w in ipairs(LFG_FADE) do
                if la:find(w, 1, true) then r:SetAlpha(0); break end
            end
            -- The gold ring behind a role glyph goes a neutral grey; the glyph stays.
            if la:find("roleicon", 1, true) and la:find("background", 1, true) then
                r:SetVertexColor(0.32, 0.32, 0.34)
            end
        end
    end
    local children = { fr:GetChildren() }
    for i = 1, #children do FadeLFGArt(children[i], depth + 1) end
end

-- House font on the window's text. Buttons and edit boxes keep Blizzard's font;
-- browse rows get theirs from SkinBrowseFrame.
local function ApplyFont(fr, depth)
    if depth > 9 or not fr or fr:IsForbidden() then return end
    if depth > 0 then
        if fr:IsObjectType("Button") or fr:IsObjectType("EditBox") then return end
        if WSkin.IsForeignFrame(fr) then return end
    end
    local regions = { fr:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r:GetObjectType() == "FontString" then FontOnce(r) end
    end
    local children = { fr:GetChildren() }
    for i = 1, #children do ApplyFont(children[i], depth + 1) end
end

-- One pooled browse frame, skinned once (a pooled frame keeps its template).
-- Collapse headers (Groups / Players) get a dark fill in place of the ornate bar
-- and a gold title; result rows lose the light list stripe. Both get white hover
-- and selection washes. Role, leader, class and newcomer glyphs stay stock.
local function SkinBrowseFrame(row)
    if not row or row:IsForbidden() then return end
    local d = GetFFD(row)
    if d.skinned then return end
    d.skinned = true
    local bg, hl, sel = row.ResultBG, row.Highlight, row.Selected
    if row.CategoryLabel then
        if bg then
            bg:SetAlpha(0)
            local fill = row:CreateTexture(nil, "BACKGROUND")
            fill:SetColorTexture(0.08, 0.08, 0.08, 0.92)
            fill:SetAllPoints(bg)
        end
        if hl then hl:SetColorTexture(1, 1, 1, 0.05) end
        WSkin.Font(row.CategoryLabel, 0.95, 0.78, 0.32)
        return
    end
    local a = bg and bg.GetAtlas and bg:GetAtlas()
    if a and a:lower():find("button-list-", 1, true) then bg:SetAlpha(0) end
    if hl then hl:SetColorTexture(1, 1, 1, 0.1) end
    if sel then sel:SetColorTexture(1, 1, 1, 0.15) end
    local regions = { row:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r:GetObjectType() == "FontString" then FontOnce(r) end
    end
end

-- A pooled who list row: house font, once.
local function SkinWhoRow(row)
    if not row or row:IsForbidden() then return end
    local d = GetFFD(row)
    if d.skinned then return end
    d.skinned = true
    local regions = { row:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r:GetObjectType() == "FontString" then FontOnce(r) end
    end
end

-- Blizzard anchors the browse ScrollBox about 24px below the list's bottom
-- divider, so the last partial row overhangs the footer. Measured once the list
-- is laid out, then re-asserted on each repaint pass.
local function ClampBrowseBottom(sb)
    local sd = GetFFD(sb)
    if not sd.clampPt then
        local bf = _G.LFGBrowseFrame
        if not bf then return end
        local line
        local regions = { bf:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            local a = r.GetAtlas and r:GetAtlas()
            if a and a:lower():find("scrollline", 1, true)
               and (not line or (r:GetTop() or 0) < (line:GetTop() or 0)) then line = r end
        end
        local target = line and line:GetTop()
        local cur = sb:GetBottom()
        if not (target and cur and (target - cur) > 1) then return end
        for i = 1, sb:GetNumPoints() do
            local p, rel, rp, x, y = sb:GetPoint(i)
            if p and p:find("BOTTOM", 1, true) and y then
                sd.clampPt = { p, rel, rp, x, y + (target - cur) }
                break
            end
        end
    end
    local c = sd.clampPt
    if c then sb:SetPoint(c[1], c[2], c[3], c[4], c[5]) end
end

-- The group-entry tooltip is its own frame, not a GameTooltip, so the tooltip
-- skin never reaches it: same look on every show, plus the house font.
local function FontTip(fr, depth)
    if depth > 4 or not fr then return end
    if depth > 0 and WSkin.IsForeignFrame(fr) then return end
    local regions = { fr:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r:GetObjectType() == "FontString" then FontOnce(r) end
    end
    local children = { fr:GetChildren() }
    for i = 1, #children do FontTip(children[i], depth + 1) end
end
local function SkinLFGTooltip(t)
    if t:IsForbidden() or (EllesmereUIDB and EllesmereUIDB.customTooltips == false) then return end
    EllesmereUI._skinBlizzardTooltipFrame(t)
    FontTip(t, 0)
end

-- Checkboxes in the List Self view (roles, Show All Level Ranges, dungeon rows).
local function SkinChecksIn(fr, depth)
    if depth > 6 or not fr or fr:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(fr) then return end
    if fr:IsObjectType("CheckButton") then WSkin.Checkbox(fr, CHECK_OPTS) end
    local children = { fr:GetChildren() }
    for i = 1, #children do SkinChecksIn(children[i], depth + 1) end
end
-- A pooled dungeon row, once (a pooled frame keeps its template).
local function SkinActivityRow(row)
    local d = GetFFD(row)
    if d.checksSkinned then return end
    d.checksSkinned = true
    SkinChecksIn(row, 0)
end

-- 1px border hugging a tile's content (its Icon, else its largest visible art).
local function BorderContent(btn)
    local d = GetFFD(btn)
    if d.contentBorder then return end
    local anchor = btn.Icon
    if not anchor then
        local best, bestArea
        local regions = { btn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r:GetObjectType() == "Texture" and r:IsShown() and (r:GetAlpha() or 0) > 0.1 then
                local atl = r.GetAtlas and r:GetAtlas()
                if not (atl and atl:lower():find("background", 1, true)) then
                    local area = (r:GetWidth() or 0) * (r:GetHeight() or 0)
                    if area > 0 and (not bestArea or area > bestArea) then best, bestArea = r, area end
                end
            end
        end
        anchor = best
    end
    anchor = anchor or btn
    local host = CreateFrame("Frame", nil, btn)
    host:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    WSkin.AddBorder(host)
    d.contentBorder = host
end
-- Category tiles (the wide buttons only).
local function BorderTiles(fr, depth)
    if depth > 5 or not fr or fr:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(fr) then return end
    if fr:GetObjectType() == "Button" and (fr:GetWidth() or 0) >= 100 then BorderContent(fr) end
    local children = { fr:GetChildren() }
    for i = 1, #children do BorderTiles(children[i], depth + 1) end
end

local function Skin_LFGVanilla()
    local f = _G.LFGParentFrame
    if not f then return end
    WSkin.Shell("lfg", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "LFGParentFrame")
    FadeLFGArt(f, 0)
    for _, vn in ipairs(FILL_VIEWS) do
        local v = _G[vn]
        if v then
            local regions = { v:GetRegions() }
            for i = 1, #regions do
                local r = regions[i]
                if r:GetObjectType() == "Texture" and not r:GetAtlas()
                   and r:GetDrawLayer() == "BACKGROUND" then
                    r:SetAlpha(0)
                end
            end
        end
    end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.LFGParentFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end

    for _, n in ipairs(DROPDOWNS) do
        local dd = _G[n]
        if dd then WSkin.Dropdown(dd) end
    end
    for _, n in ipairs(BUTTONS) do
        local b = _G[n]
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end
    local who = _G.LFGWhoListFrame
    if who and who.EditBox then WSkin.EditBox(who.EditBox) end
    local wsb = who and who.ScrollBox
    if wsb and wsb.ForEachFrame then
        wsb:ForEachFrame(SkinWhoRow)
        local wd = GetFFD(wsb)
        if not wd.hooked then
            wd.hooked = true
            hooksecurefunc(wsb, "Update", function() wsb:ForEachFrame(SkinWhoRow) end)
        end
    end
    if _G.LFGBrowseFrameScrollBar then WSkin.ScrollBar(_G.LFGBrowseFrameScrollBar) end
    for _, vn in ipairs(VIEWS) do
        local v = _G[vn]
        if v then WSkin.ControlsIn(v) end
    end

    -- Side view tabs.
    for _, tn in ipairs(SIDE_TABS) do WSkin.SideTab(f[tn]) end

    -- "More details" comment box: its border is loose BACKGROUND textures on the
    -- ScrollFrame wrapper, so the wrapper gets the dark fill and border; the inner
    -- EditBox stays stock.
    local cmt = _G.LFGListingComment
    if cmt then
        local cd = GetFFD(cmt)
        local regions = { cmt:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r ~= cd.commentFill and r:GetObjectType() == "Texture"
               and r:GetDrawLayer() == "BACKGROUND" then
                r:SetAlpha(0)
            end
        end
        if not cd.commentFill then
            cd.commentFill = cmt:CreateTexture(nil, "BACKGROUND", nil, -8)
            cd.commentFill:SetColorTexture(0.08, 0.08, 0.08, 0.92)
            cd.commentFill:SetAllPoints(cmt)
            WSkin.AddBorder(cmt)
        end
    end

    if _G.LFGListingFrame then SkinChecksIn(_G.LFGListingFrame, 0) end
    local asb = _G.LFGListingFrameActivityViewScrollBox
    if asb and asb.ForEachFrame then
        local ad = GetFFD(asb)
        if not ad.hooked then
            ad.hooked = true
            hooksecurefunc(asb, "Update", function() asb:ForEachFrame(SkinActivityRow) end)
        end
    end
    if _G.LFGListingFrameCategoryView then BorderTiles(_G.LFGListingFrameCategoryView, 0) end
    ApplyFont(f, 0)

    local sb = _G.LFGBrowseFrameScrollBox
    if sb and sb.ForEachFrame then
        -- Clip so the last partial row cannot bleed into the footer.
        sb:SetClipsChildren(true)
        ClampBrowseBottom(sb)
        sb:ForEachFrame(SkinBrowseFrame)
        local sd = GetFFD(sb)
        if not sd.hooked then
            sd.hooked = true
            hooksecurefunc(sb, "Update", function()
                if not sd.clampPt then ClampBrowseBottom(sb) end
                sb:ForEachFrame(SkinBrowseFrame)
            end)
        end
    end

    local tip = _G.LFGBrowseSearchEntryTooltip
    if tip then
        local td = GetFFD(tip)
        if not td.hooked then
            td.hooked = true
            tip:HookScript("OnShow", SkinLFGTooltip)
        end
        if tip:IsShown() then SkinLFGTooltip(tip) end
    end

    -- Repaint (debounced) on the window's show and on each view swap.
    local d = GetFFD(f)
    if not d.hooked then
        d.hooked = true
        local repaint = WSkin.Debounce(function()
            if f:IsVisible() then Skin_LFGVanilla() end
        end)
        WSkin.HookShow(f, repaint)
        for _, vn in ipairs(SHOW_VIEWS) do
            local v = _G[vn]
            if v then WSkin.HookShow(v, repaint) end
        end
    end
end

WSkin.RegisterWindow({
    key = "lfg",
    apply = Skin_LFGVanilla,
    addons = { Blizzard_GroupFinder_VanillaStyle = true },
})
end
