-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_WindowPacks.lua
--  Per-window skin packs for the Blizzard Window Skins system. Every pack
--  builds on the shared engine (EllesmereUIBlizzardSkin_WindowEngine.lua):
--  style-aware shell, flat panels, buttons with subtle white hovers, tabs
--  with accent underlines, squared icons, flat scroll bars.
--
--  Each pack is registered with the engine boot (WSkin.RegisterWindow) which
--  gates it on the window's style ("off" = never runs, zero cost), applies it
--  when its load-on-demand Blizzard addon arrives, and pcall-isolates it.
--
--  Frame paths and repaint points below were verified against the live client
--  frame tree. Repaint hooks are debounced and early-out while the window is
--  hidden, so navigation spam costs one pass per frame at most.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local WSkin = ns.WSkin
if not WSkin then return end

local Theme = WSkin.Theme
local GetFFD = WSkin.GetFFD
local FFD = WSkin.FFD
local SolidTex = WSkin.SolidTex

-------------------------------------------------------------------------------
--  Collections (Mounts / Pets / Toys / Heirlooms / Appearances / Campsites)
-------------------------------------------------------------------------------
local PREVIEW_JOURNALS = { WarbandSceneJournal = true }  -- texture previews are content

-- Tabs whose filter dropdown height should track the search box beside it.
local MATCH_FILTER_HEIGHT = {
    MountJournal = true, HeirloomsJournal = true, WardrobeCollectionFrame = true,
}

-- The collection journals (Appearances, Heirlooms, Toys) each carry a
-- collected-count progress bar with the same ornate art. Full house-bar
-- treatment: 2px taller, ornate chrome + every non-fill region faded, flat
-- accent fill (Blizzard's fill kept as the driver, just re-textured), a dark
-- trough, and the visible themed border -- a black BorderRegion would vanish
-- against the dark collections backplate. Any bar text goes white.
local function SkinCollectionsProgressBar(pb)
    if not pb then return end
    local pd = GetFFD(pb)
    if not pd.heightBumped then
        pd.heightBumped = true
        pb:SetHeight(pb:GetHeight() + 2)
    end
    if pb.border and pb.border.SetAlpha then pb.border:SetAlpha(0) end
    local fill = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
    for i = 1, select("#", pb:GetRegions()) do
        local r = select(i, pb:GetRegions())
        if r and r ~= fill and r ~= pd.bg and r.IsObjectType then
            if r:IsObjectType("Texture") and r:GetDrawLayer() ~= "HIGHLIGHT" then
                r:SetAlpha(0)
            elseif r:IsObjectType("FontString") then
                WSkin.White(r)
            end
        end
    end
    if pb.SetStatusBarTexture then
        pb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        WSkin.ApplyBarFill(pb)
    end
    if not pd.bg then
        local trough = pb:CreateTexture(nil, "BACKGROUND", nil, -1)
        trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        trough:SetAllPoints(pb)
        pd.bg = trough
    end
    WSkin.AddBorder(pb)
end

-- Filter dropdown at the top of a collection tab: pin the "Filter" label left,
-- clear of the arrow (matches the achievement/housing/professions filters).
-- The appearances FilterButton re-anchors (or re-creates) its label through the
-- tab-show path, so a one-shot anchor drifts left after a tab switch. Re-assert
-- on the dropdown's OnShow, re-deriving the label each time in case Blizzard
-- swapped the fontstring. To avoid a one-frame blink we also hook the current
-- label's SetPoint so any re-anchor is corrected synchronously (before render);
-- the next-frame pass is only a safety net for a re-created fontstring.
local function LeftAlignFilterLabel(dd)
    if not dd then return end
    local fd = GetFFD(dd)
    if fd.labHooked then return end
    fd.labHooked = true
    local guard = false
    local hooked = setmetatable({}, { __mode = "k" })
    local function apply()
        if guard then return end
        guard = true
        local lab = dd.Text or (dd.GetFontString and dd:GetFontString())
        if lab and lab.ClearAllPoints then
            lab:ClearAllPoints()
            lab:SetPoint("LEFT", dd, "LEFT", 8, 0)
            lab:SetPoint("RIGHT", dd, "RIGHT", -22, 0)
            if lab.SetJustifyH then lab:SetJustifyH("LEFT") end
            if not hooked[lab] then
                hooked[lab] = true
                hooksecurefunc(lab, "SetPoint", apply)
            end
        end
        guard = false
    end
    apply()
    if dd.HookScript then
        dd:HookScript("OnShow", function()
            apply()
            if C_Timer then C_Timer.After(0, apply) end
        end)
    end
end

-- Active-filter reset "X" on a filter dropdown/button (shown when a filter is
-- applied so the user can clear it): strip Blizzard's clear glyph and draw the
-- house uitools-icon-close instead, lifted above the dropdown's border strips,
-- white 0.9 -> 1 on hover. `host` is the dropdown the reset button rides (for
-- frame-level layering). Idempotent (guarded by FFD .x).
local function SkinFilterResetX(rb, host)
    if not rb or rb:IsForbidden() then return end
    local rd = GetFFD(rb)
    if rd.x then return end
    for i = 1, select("#", rb:GetRegions()) do
        local r = select(i, rb:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = rb[g] and rb[g](rb)
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    if host then rb:SetFrameLevel(host:GetFrameLevel() + 5) end
    local x = rb:CreateTexture(nil, "OVERLAY", nil, 7)
    x:SetAtlas("uitools-icon-close", false)
    x:SetSize(10, 10)
    x:SetPoint("CENTER", rb, "CENTER", 0, 0)
    x:SetVertexColor(1, 1, 1, 0.9)
    rd.x = x
    rb:HookScript("OnEnter", function() x:SetVertexColor(1, 1, 1, 1) end)
    rb:HookScript("OnLeave", function() x:SetVertexColor(1, 1, 1, 0.9) end)
end

local _mountRowHook = false
local function Skin_Collections()
    local f = _G.CollectionsJournal
    if not f then return end
    WSkin.Shell("collections", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    local cTabs = {}
    for _, key in ipairs({ "MountsTab", "PetsTab", "ToysTab", "HeirloomsTab",
                           "WardrobeTab", "WarbandScenesTab" }) do
        local t = f[key]
        if t then WSkin.Tab(t); cTabs[#cTabs + 1] = t end
    end
    -- Collections re-anchors its bottom tabs to native spacing whenever the
    -- window (or a load-on-demand tab like Appearances/Campsites) is shown,
    -- which flashed the last tabs at the wide native gap for a frame before our
    -- debounced re-skin caught up. Re-normalize synchronously off each tab's
    -- SetPoint (reentry-guarded) so the 1px seam is restored in the same frame
    -- Blizzard moves it. Scoped to this window; the shared helper is untouched.
    local cd = GetFFD(f)
    if not cd.tabNormHook then
        cd.tabNormHook = true
        local guard = false
        local function ReNorm()
            if guard then return end
            guard = true
            WSkin.NormalizeTabRow(cTabs)
            guard = false
        end
        cd.tabReNorm = ReNorm
        for _, t in ipairs(cTabs) do
            hooksecurefunc(t, "SetPoint", ReNorm)
        end
    end
    if cd.tabReNorm then cd.tabReNorm() end
    -- The wardrobe's inner Items/Sets tabs are real tabs; treat them before
    -- the journal button sweep below can flatten them into plain blocks.
    local wardrobe = _G.WardrobeCollectionFrame
    if wardrobe then
        local wTabs = {}
        if wardrobe.ItemsTab then WSkin.Tab(wardrobe.ItemsTab, { darkActive = true }); wTabs[#wTabs + 1] = wardrobe.ItemsTab end
        if wardrobe.SetsTab then WSkin.Tab(wardrobe.SetsTab, { darkActive = true }); wTabs[#wTabs + 1] = wardrobe.SetsTab end
        WSkin.NormalizeTabRow(wTabs)
    end
    -- The mount-equipment slot (BottomLeftInset.SlotButton) is its own art --
    -- slot border + equipped item icon -- NOT journal chrome. Exempt it BEFORE
    -- the art sweeps below run, so they skip it and its Blizzard artwork stays
    -- intact instead of being blanked.
    local _mj = _G.MountJournal
    if _mj and _mj.BottomLeftInset and _mj.BottomLeftInset.SlotButton then
        WSkin.ExemptArt(_mj.BottomLeftInset.SlotButton)
    end
    for _, name in ipairs({ "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal",
                            "WardrobeCollectionFrame", "WarbandSceneJournal" }) do
        local j = _G[name]
        if j then
            for _, k in ipairs({ "RightInset", "LeftInset", "Inset" }) do
                if j[k] then WSkin.Inset(j[k]) end
            end
            -- The tiled diagonal background + ornate corners live on the
            -- journal's icons frame; fade its chrome, never the grid content.
            local icons = j.iconsFrame or j.IconsFrame
            if icons then
                WSkin.FadeRegions(icons)
                WSkin.FadeKeyedArt(icons)
                WSkin.Register(icons, true)
            end
            WSkin.PagingIn(j)
            WSkin.ScrollBarsIn(j)
            if not PREVIEW_JOURNALS[name] then
                WSkin.ButtonsIn(j)
                WSkin.FadeKeyedArt(j)
                WSkin.FadeArtIn(j)
            end
            -- Appearances/Heirlooms/Toys each carry a collected-count bar;
            -- applied last so the keyed-art sweep above can't re-fade it.
            if j.progressBar then SkinCollectionsProgressBar(j.progressBar) end
            -- Left-align the "Filter" label. For appearances/heirlooms/mounts
            -- also match the filter height to the search box beside it.
            local filter = j.FilterDropdown or j.FilterButton
                or _G[name .. "FilterDropdown"] or _G[name .. "FilterButton"]
            LeftAlignFilterLabel(filter)
            -- Active-filter clear "X": house glyph, same as the AH filter.
            if filter then
                SkinFilterResetX(filter.ResetButton or filter.ClearFiltersButton, filter)
            end
            if MATCH_FILTER_HEIGHT[name] and filter and filter.SetHeight then
                local sb = j.SearchBox or j.searchBox or _G[name .. "SearchBox"]
                local h = sb and sb.GetHeight and sb:GetHeight()
                if h and h > 0 then filter:SetHeight(h) end
            end
        end
    end

    -- Mount list rows recycle; restyle in the row initializer.
    if MountJournal_InitMountButton and not _mountRowHook then
        _mountRowHook = true
        hooksecurefunc("MountJournal_InitMountButton", function(button)
            if not button or button:IsForbidden() then return end
            if button.background then button.background:SetAlpha(0) end
            local d = GetFFD(button)
            if not d.bg then
                local bg = button:CreateTexture(nil, "BACKGROUND")
                bg:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                bg:SetPoint("TOPLEFT", 1, -1)
                bg:SetPoint("BOTTOMRIGHT", -1, 1)
                d.bg = bg
                WSkin.AddBorder(button)
            end
            if button.name then WSkin.White(button.name) end
        end)
    end

    -- Warband campsites: the Show Owned filter sits outside the button sweep
    -- (preview journal), so its checkbox + label are treated directly.
    local wj = _G.WarbandSceneJournal
    local so = wj and wj.IconsFrame and wj.IconsFrame.Icons
        and wj.IconsFrame.Icons.Controls and wj.IconsFrame.Icons.Controls.ShowOwned
    if so then
        if so.Checkbox then WSkin.Checkbox(so.Checkbox) end
        if so.Text then WSkin.White(so.Text) end
    end

    -- Remove the vignette framing the mount model.
    local mj = _G.MountJournal
    if mj and mj.MountDisplay then
        local md = mj.MountDisplay
        if md.ShadowOverlay then md.ShadowOverlay:SetAlpha(0) end
        if md.ModelScene and md.ModelScene.ShadowOverlay then md.ModelScene.ShadowOverlay:SetAlpha(0) end
        for _, k in ipairs({ "Border", "BorderFrame", "NineSlice" }) do
            if md[k] then WSkin.FadeRegions(md[k]); WSkin.Register(md[k], true) end
        end
        -- Replace the scenic model backdrop with a flat 3% white fill (behind
        -- the 3D model). SetAlpha(0) survives Blizzard's Yes/No show toggle.
        for _, k in ipairs({ "YesMountsTex", "NoMountsTex" }) do
            if md[k] and md[k].SetAlpha then md[k]:SetAlpha(0) end
        end
        local mdd = GetFFD(md)
        if not mdd.modelFill then
            local fill = md:CreateTexture(nil, "BACKGROUND")
            fill:SetColorTexture(1, 1, 1, 0.03)
            fill:SetAllPoints(md.YesMountsTex or md.ModelScene or md)
            mdd.modelFill = fill
        end
    end

    WSkin.ButtonsIn(f)
    WSkin.FadeKeyedArt(f)
    -- The appearances main area keeps a faint 50% backing instead of being
    -- fully stripped. The keyed-art sweep above zeroes ItemsCollectionFrame's
    -- Bg + BackgroundTile, so re-assert them here (runs on every skin pass).
    -- Frame chrome (NineSlice) and corner shadows stay stripped.
    local icf = wardrobe and wardrobe.ItemsCollectionFrame
    if icf then
        if icf.Bg then icf.Bg:SetAlpha(0.5) end
        if icf.BackgroundTile then icf.BackgroundTile:SetAlpha(0.5) end
    end
    -- Battle pet loadout (active team): card backing + every border piece kept
    -- at a matched faint 25%. Alpha survives Blizzard re-texturing on pet swaps.
    for i = 1, 3 do
        local bg = _G["PetJournalLoadoutPet" .. i .. "BG"]
        if bg and bg.SetAlpha then bg:SetAlpha(0.25) end
    end
    local ploadBorder = _G.PetJournalLoadoutBorder
    if ploadBorder and ploadBorder.GetRegions then
        for ri = 1, select("#", ploadBorder:GetRegions()) do
            local r = select(ri, ploadBorder:GetRegions())
            if r and r.SetAlpha and r.IsObjectType and r:IsObjectType("Texture") then
                r:SetAlpha(0.25)
            end
        end
    end
    -- Bottom-bar action buttons: Blizzard leaves these gold; force white text
    -- (color only). Mounts tab: Mount; Pets tab: Summon + Find Battle. These
    -- re-apply their gold font object when re-enabled (mount/pet selected), so
    -- re-white on every OnEnable as well as now.
    for _, bn in ipairs({ "MountJournalMountButton", "PetJournalSummonButton",
                          "PetJournalFindBattle" }) do
        local btn = _G[bn]
        local lab = btn and (btn.Text or (btn.GetFontString and btn:GetFontString()))
        if lab then
            WSkin.White(lab)
            local bd = GetFFD(btn)
            if not bd.whiteHook then
                bd.whiteHook = true
                btn:HookScript("OnEnable", function() WSkin.White(lab) end)
            end
        end
    end
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then Skin_Collections(); WSkin.Restrip(); WSkin.UpdateAllTabs() end
    end))
end

WSkin.RegisterWindow({
    key = "collections",
    addons = { Blizzard_Collections = true },
    apply = Skin_Collections,
})

-------------------------------------------------------------------------------
--  Talents & Spellbook (PlayerSpellsFrame)
-------------------------------------------------------------------------------
-- The spellbook parchment backplate + gilded item frame are re-raised by
-- Blizzard on every populate and mouseover, so we re-fade them in post-hooks.
-- Visual-only (SetAlpha), never the item's own alpha knobs or click path.
local function FadeSpellItem(item)
    if not item or item:IsForbidden() then return end
    if item.Backplate and item.Backplate.SetAlpha then item.Backplate:SetAlpha(0) end
    local b = item.Button
    if b then
        -- The per-icon ring stays, at half strength and half color.
        if b.Border and b.Border.SetAlpha then
            b.Border:SetAlpha(0.5)
            if b.Border.SetDesaturation then b.Border:SetDesaturation(0.5) end
        end
        if b.BorderSheen and b.BorderSheen.SetAlpha then b.BorderSheen:SetAlpha(0) end
        if b.IconHighlight and b.IconHighlight.SetAlpha then b.IconHighlight:SetAlpha(0) end
    end
    if item.Name then WSkin.White(item.Name) end
    if item.SubName then WSkin.White(item.SubName) end
end

local function FadeSpellItemsIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 10 or not frame.GetChildren or frame:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(frame) then return end
    if frame.Backplate and frame.Button then FadeSpellItem(frame) end
    for i = 1, select("#", frame:GetChildren()) do
        FadeSpellItemsIn(select(i, frame:GetChildren()), depth + 1)
    end
end

-- Talents tab: the tree art stays, dimmed to 75%. Lower-only (never raise),
-- BACKGROUND draw layer only, shallow -- talent buttons live deeper and their
-- icons are ARTWORK, so neither is touched. Re-runs are no-ops.
local function DimTalentArt(host, depth)
    depth = depth or 0
    if not host or depth > 2 or not host.GetRegions or host:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(host) then return end
    for i = 1, select("#", host:GetRegions()) do
        local r = select(i, host:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and r:GetDrawLayer() == "BACKGROUND" then
            local a = r:GetAlpha() or 1
            if a > 0.75 then r:SetAlpha(0.75) end
        end
    end
    for i = 1, select("#", host:GetChildren()) do
        DimTalentArt(select(i, host:GetChildren()), depth + 1)
    end
end

-- Spellbook page chrome: category headers become plain white text in the
-- house font, their gold glow washes go, the ornate divider lines stay but
-- render white, and the "Page X/Y" counter matches. Header decoration lives
-- in two places -- OVERLAY regions on the page views and textures on the
-- pooled header elements -- so both are swept with the same rule: wide-short
-- strips are dividers (kept, whitened), everything else is wash (faded).
local function SkinSpellBookChrome(sb)
    local paged = sb and sb.PagedSpellsFrame
    if not paged then return end
    local pc = paged.PagingControls
    if pc and pc.PageText then WSkin.Font(pc.PageText); WSkin.White(pc.PageText) end
    -- Any texture layer: the divider is an anonymous non-OVERLAY region on
    -- the view. Wide-short strips = dividers (kept, whitened); the rest of
    -- the decoration (glow washes) fades.
    local function SweepDeco(host)
        for i = 1, select("#", host:GetRegions()) do
            local r = select(i, host:GetRegions())
            if r and r.IsObjectType then
                if r:IsObjectType("FontString") then
                    WSkin.Font(r)
                    WSkin.White(r)
                elseif r:IsObjectType("Texture") and not (FFD[r] and FFD[r].isOurLine) then
                    -- (Our own replacement lines are skipped above -- they are
                    -- wide-short textures on this same frame, and the divider
                    -- branch would otherwise hide each one and chain a new
                    -- line onto it, 20px shorter per sweep.)
                    -- Skip rects not computed yet (hidden first pass): an
                    -- anchor-stretched divider measures 0x0 there and would
                    -- land in the fade bucket. The next sweep sees real sizes.
                    local w, h = r:GetSize()
                    if w and h and w > 0 and h > 0 then
                        if h <= 30 and w > 80 then
                            -- Divider: the ornate art is too dark to ever
                            -- read as white, so it goes and a clean 1px
                            -- white 25% line spans the same rect.
                            r:SetAlpha(0)
                            local rd = GetFFD(r)
                            if not rd.line then
                                local line = r:GetParent():CreateTexture(nil, "OVERLAY")
                                line:SetColorTexture(1, 1, 1, 0.25)
                                local PPx = EllesmereUI and EllesmereUI.PanelPP
                                if PPx and PPx.DisablePixelSnap then
                                    PPx.DisablePixelSnap(line)
                                    line:SetHeight(PPx.mult or 1)
                                else
                                    line:SetHeight(1)
                                end
                                line:SetPoint("LEFT", r, "LEFT", 20, 0)
                                line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
                                rd.line = line
                                GetFFD(line).isOurLine = true
                            end
                        else
                            r:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end
    for _, k in ipairs({ "View1", "View2" }) do
        if paged[k] then SweepDeco(paged[k]) end
    end
    -- Pooled elements: items answer HasValidData; headers/spacers do not.
    -- The header's gold "card" wash is its keyed Backplate texture (sits on
    -- a lower draw layer, so the OVERLAY sweep never saw it).
    pcall(function()
        for _, el in paged:EnumerateFrames() do
            if not (el.HasValidData and el:HasValidData()) and el.GetRegions then
                if el.Backplate and el.Backplate.SetAlpha then el.Backplate:SetAlpha(0) end
                SweepDeco(el)
            end
        end
    end)
end

-- Talent loadout popups (import / edit): keep it simple -- dark panel + border,
-- white title, house buttons + inputs. Separate top-level frames in the
-- PlayerSpells addon; created with it, so skinning them on the talent pass
-- sticks even though they only show on demand.
local function SkinTalentDialog(dialog)
    if not dialog or dialog:IsForbidden() then return end
    -- Use the STYLE-AWARE shell (not a flat WSkin.Panel) so the popup follows
    -- the Talents window's theme: the EllesmereUI atlas "glass" backdrop, or
    -- the Modern flat color. A plain Panel is style-agnostic, which is why it
    -- read as opaque next to the atlas-backed window on the EllesmereUI theme.
    WSkin.Shell("playerspells", dialog)
    -- Leftover Blizzard border sub-frame (its own Bg + corners): the shell's
    -- atlas border replaces it. Alpha 0 inherits to all its pieces.
    if dialog.Border and dialog.Border.SetAlpha then dialog.Border:SetAlpha(0) end
    local title = dialog.Title or (dialog.TitleContainer and dialog.TitleContainer.TitleText) or dialog.TitleText
    if title then
        WSkin.Font(title); WSkin.White(title)
        -- Seat the title on the shell's top bar (the shell adds a 25px top
        -- strip that the native title anchor lands below), 1px above center.
        local sd = WSkin.FFD and WSkin.FFD[dialog]
        local td = GetFFD(title)
        if sd and sd.topBar and title.ClearAllPoints and not td.centered then
            td.centered = true
            title:ClearAllPoints()
            title:SetPoint("CENTER", sd.topBar, "CENTER", 0, 1)
        end
    end
    for _, k in ipairs({ "AcceptButton", "CancelButton", "DeleteButton" }) do
        local b = dialog[k]
        if b then
            WSkin.Button(b)
            local fs = b.GetFontString and b:GetFontString()
            if fs then WSkin.White(fs) end
        end
    end
    -- Shared loadout-name input: shifted DOWN 15px and 20px SHORTER (top+bottom
    -- anchored, so SetHeight is ignored -- move the anchors instead). Top edges
    -- go -15 (shift down); bottom edges go +5 (shift down -15, raised +20 to
    -- shrink). Falls back to SetHeight for a box with no bottom anchor. One-shot.
    local nc = dialog.NameControl
    if nc and nc.EditBox then
        WSkin.EditBox(nc.EditBox)
        local eb = nc.EditBox
        local ed = GetFFD(eb)
        if not ed.shorter then
            ed.shorter = true
            local n = eb:GetNumPoints() or 0
            local pts, hasBottom = {}, false
            for i = 1, n do
                local p, rel, rp, x, y = eb:GetPoint(i)
                if p and p:find("BOTTOM") then
                    pts[i] = { p, rel, rp, x or 0, (y or 0) + 5 }
                    hasBottom = true
                elseif p then
                    -- TOP / LEFT / RIGHT / CENTER: shift down 15.
                    pts[i] = { p, rel, rp, x or 0, (y or 0) - 15 }
                end
            end
            eb:ClearAllPoints()
            for i = 1, #pts do local t = pts[i]; eb:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            if not hasBottom then
                local h = eb:GetHeight()
                if h and h > 20 then eb:SetHeight(h - 20) end
            end
        end
    end
end

local _spellItemHook = false
local function Skin_PlayerSpells()
    local f = _G.PlayerSpellsFrame
    if not f then return end
    WSkin.Shell("playerspells", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    WSkin.TabSystem(f.TabSystem)
    -- Spellbook's class/general tabs get the real tab treatment BEFORE the
    -- button sweep below can flatten them: our label is always centered,
    -- where Blizzard's own seats inactive-tab text far lower.
    if f.SpellBookFrame and f.SpellBookFrame.CategoryTabSystem then
        WSkin.TabSystem(f.SpellBookFrame.CategoryTabSystem, { darkActive = true })
    end
    -- Collapse/restore control (top right): the quest tracker module
    -- headers' collapse/expand atlas pair, hardcoded, 16x16, desaturated so
    -- it renders white. Atlas-guarded: a missing name keeps Blizzard's art.
    local function MaxMinGlyph(btn, atlas)
        if not btn or btn:IsForbidden() then return end
        if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then return end
        local d = GetFFD(btn)
        if d.glyph then return end
        for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local t = btn[g] and btn[g](btn)
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        WSkin.FadeRegions(btn)
        local glyph = btn:CreateTexture(nil, "OVERLAY")
        glyph:SetAtlas(atlas)
        glyph:SetSize(16, 16)
        glyph:SetPoint("CENTER", -2, 0)
        glyph:SetDesaturated(true)
        glyph:SetVertexColor(1, 1, 1, 0.75)
        d.glyph = glyph
        btn:HookScript("OnEnter", function() glyph:SetVertexColor(1, 1, 1, 1) end)
        btn:HookScript("OnLeave", function() glyph:SetVertexColor(1, 1, 1, 0.75) end)
    end
    local mm = f.MaximizeMinimizeButton or f.MaxMinButtonFrame
    if mm then
        MaxMinGlyph(mm.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
        MaxMinGlyph(mm.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
    end
    for _, key in ipairs({ "SpellBookFrame", "TalentsFrame", "InspectFrame" }) do
        local sub = f[key]
        if sub then
            WSkin.ButtonsIn(sub)
            WSkin.ScrollBarsIn(sub)
            if key == "SpellBookFrame" then
                -- Book page art comes back dimmed (the halved page is the
                -- minimized layout's art); the center bookmark stays full
                -- opacity, and the rest of the book chrome (top bar strip,
                -- page-corner flipbook) stays off.
                WSkin.ExemptArt(sub)
                for _, bk in ipairs({ "BookBGLeft", "BookBGRight", "BookBGHalved" }) do
                    local t = sub[bk]
                    if t and t.SetAlpha then t:SetAlpha(0.1) end
                end
                if sub.TopBar and sub.TopBar.SetAlpha then sub.TopBar:SetAlpha(0) end
                if sub.BookCornerFlipbook and sub.BookCornerFlipbook.SetAlpha then sub.BookCornerFlipbook:SetAlpha(0) end
                -- Assisted-rotation frame's separator line: the art sweeps
                -- faded it before the exemption; fade it directly (its
                -- button is a child and survives a direct-region fade).
                if sub.AssistedCombatRotationSpellFrame then
                    WSkin.FadeRegions(sub.AssistedCombatRotationSpellFrame)
                    WSkin.Register(sub.AssistedCombatRotationSpellFrame, true)
                end
            elseif key == "TalentsFrame" then
                -- Tree background is content here: exempt from the art
                -- sweeps, shown at 75%.
                WSkin.ExemptArt(sub)
                DimTalentArt(sub)
                -- Search box matches the loadout dropdown's height (one-shot;
                -- retries until the dropdown has a laid-out height).
                local dd = sub.LoadSystem and sub.LoadSystem.Dropdown
                local sbx = sub.SearchBox
                if dd and sbx and not GetFFD(sbx).hMatched then
                    local dh = dd:GetHeight()
                    if dh and dh > 0 then
                        GetFFD(sbx).hMatched = true
                        sbx:SetHeight(dh)
                    end
                end
            else
                WSkin.FadeKeyedArt(sub)
                WSkin.FadeArtIn(sub)
            end
        end
    end

    -- Spec page: the per-spec tile artwork IS the content, so the whole pane
    -- is exempt from the art sweeps and the tiles keep their backgrounds.
    -- Only the page-level black underlay + page background still go (they
    -- fight the shell); both are direct sf regions, not tile art.
    local sf = f.SpecFrame
    if sf then
        WSkin.ExemptArt(sf)
        if sf.BlackBG and sf.BlackBG.SetAlpha then sf.BlackBG:SetAlpha(0) end
        if sf.Background and sf.Background.SetAlpha then sf.Background:SetAlpha(0) end
        WSkin.ButtonsIn(sf)
        WSkin.ScrollBarsIn(sf)
    end

    if f.SpellBookFrame then
        FadeSpellItemsIn(f.SpellBookFrame)
        local sb = f.SpellBookFrame
        SkinSpellBookChrome(sb)
        -- Headers are pooled and re-realized on tab changes and page flips;
        -- re-sweep the chrome one debounced frame after each.
        local sd = GetFFD(sb)
        if not sd.chromeHooked then
            sd.chromeHooked = true
            local re = WSkin.Debounce(function()
                if f:IsVisible() then SkinSpellBookChrome(sb) end
            end)
            if sb.SetTab then hooksecurefunc(sb, "SetTab", re) end
            -- Returning from the Spec/Talents top tabs re-realizes pooled
            -- headers but only fires the spellbook subframe's own OnShow
            -- (the window never hid, so the window-level hook stays quiet).
            sb:HookScript("OnShow", re)
            local paged = sb.PagedSpellsFrame
            local pc = paged and paged.PagingControls
            if pc and pc.PrevPageButton then pc.PrevPageButton:HookScript("OnClick", re) end
            if pc and pc.NextPageButton then pc.NextPageButton:HookScript("OnClick", re) end
            if paged then paged:HookScript("OnMouseWheel", re) end
        end
    end
    if SpellBookItemMixin and not _spellItemHook then
        _spellItemHook = true
        if SpellBookItemMixin.UpdateVisuals then
            hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", FadeSpellItem)
        end
        -- Both hover edges re-fade the full art set: enter raises highlight
        -- art, and LEAVE restores Blizzard's baseline (backplate/border back
        -- to full alpha) -- that restore was the "stuck" texture that stayed
        -- behind items after hovering off.
        if SpellBookItemMixin.OnIconEnter then
            hooksecurefunc(SpellBookItemMixin, "OnIconEnter", FadeSpellItem)
        end
        if SpellBookItemMixin.OnIconLeave then
            hooksecurefunc(SpellBookItemMixin, "OnIconLeave", FadeSpellItem)
        end
    end

    -- Loadout popups.
    local importD = _G.ClassTalentLoadoutImportDialog
    if importD then
        SkinTalentDialog(importD)
        -- Import-string box.
        local ic = importD.ImportControl
        if ic and ic.InputContainer then WSkin.Panel(ic.InputContainer) end
    end
    local createD = _G.ClassTalentLoadoutCreateDialog
    if createD then SkinTalentDialog(createD) end
    local editD = _G.ClassTalentLoadoutEditDialog
    if editD then
        SkinTalentDialog(editD)
        if editD.LoadoutName then WSkin.EditBox(editD.LoadoutName) end
        local chk = editD.UsesSharedActionBars and editD.UsesSharedActionBars.CheckButton
        if chk then WSkin.Checkbox(chk) end
    end

    WSkin.ButtonsIn(f)
    WSkin.ScrollBarsIn(f)
    WSkin.FadeKeyedArt(f)
    WSkin.FadeArtIn(f)
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then Skin_PlayerSpells(); WSkin.Restrip(); WSkin.UpdateAllTabs() end
    end))
end

WSkin.RegisterWindow({
    key = "playerspells",
    addons = { Blizzard_PlayerSpells = true },
    apply = Skin_PlayerSpells,
})

-------------------------------------------------------------------------------
--  Adventure Guide (EncounterJournal)
-------------------------------------------------------------------------------
local EJ_ART_MATCH = {
    "journalbg", "ui-ej-cataclysm", "abilitytextbg", "paperoverlay",
    "activities-background", "adventureguide-pane",
}
local function ejKeepTex(hay)
    if not hay then return false end
    if WSkin.TexIsIcon(hay) then return true end
    if hay:find("ui-ej-lorebg", 1, true) then return true end   -- instance picture
    if hay:find("ui-ej-boss", 1, true) then return true end     -- boss render
    if hay:find("ui-ej-icons", 1, true) then return true end
    return false
end
local function FadeEJArt(frame, depth)
    depth = depth or 0
    if not frame or depth > 11 or not frame.GetRegions or frame:IsForbidden() then return end
    if WSkin.IsArtExempt(frame) then return end
    if depth > 0 and WSkin.IsForeignFrame(frame) then return end
    local mybg = FFD[frame] and FFD[frame].bg
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r ~= mybg and r.IsObjectType and r:IsObjectType("Texture") and (r:GetAlpha() or 0) > 0 then
            local hay = WSkin.TexHay(r)
            if hay and not ejKeepTex(hay) then
                for _, m in ipairs(EJ_ART_MATCH) do
                    if hay:find(m, 1, true) then r:SetAlpha(0); break end
                end
            end
        end
    end
    for i = 1, select("#", frame:GetChildren()) do
        FadeEJArt(select(i, frame:GetChildren()), depth + 1)
    end
end

-- Some Blizzard text bakes a |cff000000 black or |cff414141 dark grey run INTO
-- the string (gossip/quest option titles, and localized quest reward/greeting
-- blurbs on non-English clients); a plain SetTextColor cannot lighten those --
-- the embedded run wins. Rewrite just those two tones to readable light ones in
-- place, leaving every other color (links, quest difficulty) untouched.
-- Idempotent: once rewritten the source codes are gone, so re-runs are no-ops.
local DARK_TEXT_RECOLOR = { ["000000"] = "ffffff", ["414141"] = "b0b8bc" }
local function RecolorDarkText(fs)
    if not fs or not fs.GetText then return end
    local txt = fs:GetText()
    if not txt or txt == "" or not txt:find("|cff", 1, true) then return end
    local new, n = txt:gsub("|c[fF][fF](%x%x%x%x%x%x)", function(hex)
        local repl = DARK_TEXT_RECOLOR[hex:lower()]
        if repl then return "|cff" .. repl end
    end)
    if n > 0 and new ~= txt then fs:SetText(new) end
end

-- Force encounter text white so it reads on the dark panel once the parchment
-- is gone. SimpleHTML bodies take per-element colors. Embedded ability/gear
-- hyperlinks carry baked-in |c color codes; those are rewritten in place to
-- the Global Options link color (the |H payload is untouched, so clicking
-- still works, and the rewrite is idempotent -- rerunning matches our own
-- color and produces an identical string).
local function RecolorLinks(fs)
    local txt = fs.GetText and fs:GetText()
    if not txt or txt == "" or not txt:find("|H", 1, true) then return end
    local new, n = txt:gsub("|c%x%x%x%x%x%x%x%x|H", "|cff" .. WSkin.LinkColorHex() .. "|H")
    if n > 0 and new ~= txt then fs:SetText(new) end
end

local function WhitenTextIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 9 or frame:IsForbidden() then return end
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local r = select(i, frame:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("FontString") and r.SetTextColor then
                r:SetTextColor(1, 1, 1)
                RecolorLinks(r)
                RecolorDarkText(r)
            end
        end
    end
    if frame.GetChildren then
        for i = 1, select("#", frame:GetChildren()) do
            local c = select(i, frame:GetChildren())
            if c and not WSkin.IsForeignFrame(c, frame) then
                if c.GetObjectType and c:GetObjectType() == "SimpleHTML" and c.SetTextColor then
                    for _, el in ipairs({ "P", "H1", "H2", "H3" }) do
                        pcall(c.SetTextColor, c, el, 1, 1, 1)
                    end
                end
                WhitenTextIn(c, depth + 1)
            end
        end
    end
end

-- Breadcrumb nav button: art gone, white text, a 1px divider on its right
-- edge (hidden on the last crumb), and the subnav caret drawn with the house
-- arrow. Crumbs are resized to their content -- |pad| text (gap arrow) |pad|
-- -- and re-chained seamlessly in RefreshNav, so spacing against the dividers
-- is even on both sides and Home is no wider than its text.
local NAV_PAD       = 14   -- even padding on each side of a crumb's content
local NAV_ARROW_GAP = 4    -- gap between text and the subnav arrow
local NAV_ARROW_W   = 12   -- arrow width (62x44 atlas at 12x8.5)
local _navReflow           -- assigned to RefreshNav once the nav is skinned
local function SkinNavButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if not d.navskin then
        d.navskin = true
        -- Rewinding (clicking an earlier crumb / Home) relayouts the
        -- surviving crumbs inside the click handler; reflow synchronously so
        -- they never render a frame at Blizzard's layout.
        btn:HookScript("OnClick", function()
            local nv = btn:GetParent()
            local rf = nv and FFD[nv] and FFD[nv].reflow
            if rf then
                rf()
            elseif _navReflow then
                _navReflow()
            end
        end)
        for _, g in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture" }) do
            local fn = btn[g]; local t = fn and fn(btn)
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        WSkin.FadeRegions(btn)
        local hov = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
        hov:SetPoint("TOPLEFT", 2, -3)
        hov:SetPoint("BOTTOMRIGHT", -2, 3)
        d.hover = hov
        local div = btn:CreateTexture(nil, "OVERLAY")
        div:SetColorTexture(1, 1, 1, 0.15)
        div:SetWidth(1)
        div:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -5)
        div:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 5)
        d.divider = div
    end
    if btn.text then WSkin.White(btn.text) end

    local ma = btn.MenuArrowButton
    if ma and not d.arrow then
        -- Our own arrow ON the caret button, so it follows Blizzard's
        -- show/hide for crumbs that actually have a subnav menu.
        local arrow = ma:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas("Azerite-PointingArrow")
        arrow:SetSize(12, 8.5)   -- native 62x44 aspect
        arrow:SetPoint("CENTER")
        d.arrow = arrow
    end
    if ma then
        -- Blizzard re-applies the caret, border, and glow art whenever the
        -- nav rebuilds its buttons AND raises hover art from its OnEnter, so
        -- fade ALL of the button's native art on every pass and again from
        -- enter/leave hooks, keeping only our arrow.
        local md = GetFFD(ma)
        local function FadeArrowArt()
            local keep = { [d.arrow] = true }
            WSkin.FadeRegions(ma, keep)
            for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                local fn = ma[g]; local t = fn and fn(ma)
                if t and not keep[t] and t.SetAlpha then t:SetAlpha(0) end
            end
            if ma.Art and ma.Art.SetAlpha then ma.Art:SetAlpha(0) end
        end
        FadeArrowArt()
        if not md.hoverHooked then
            md.hoverHooked = true
            ma:HookScript("OnEnter", FadeArrowArt)
            ma:HookScript("OnLeave", FadeArrowArt)
        end
    end

    -- |pad| text (gap arrow) |pad| -- even spacing against the dividers.
    if btn.text then
        btn.text:ClearAllPoints()
        btn.text:SetPoint("LEFT", btn, "LEFT", NAV_PAD, 0)
        if ma and not d.maMoved then
            d.maMoved = true
            ma:ClearAllPoints()
            -- 5px left of the nominal gap position (arrow hugs the text).
            ma:SetPoint("LEFT", btn.text, "RIGHT", NAV_ARROW_GAP - 5, 0)
        end
    end
end

-- Breadcrumb bar restyle (adventure guide + world map): faint wash spanning
-- only the crumbs, white crumb text with 1px dividers, house subnav arrows,
-- content-driven crumb widths in a seamless chain. dx/dy reseat from
-- Blizzard's spot (captured once); the bar also runs 6px slimmer. bgColor
-- {r,g,b,a} sets the crumb wash (default 5% white; the map uses 20% black).
local function RestyleNavGeneric(nav, dx, dy, bgColor)
    if not nav then return end
    for _, k in ipairs({ "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
                         "InsetBorderLeft", "InsetBorderRight" }) do
        local t = nav[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    local nd = GetFFD(nav)
    if not nd.bg then
        local wash = nav:CreateTexture(nil, "BACKGROUND", nil, -6)
        wash:SetAllPoints(nav)
        nd.bg = wash
    end
    local bc = bgColor or { 1, 1, 1, 0.05 }
    nd.bg:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    if nd.origP == nil then
        local p, rel, rp, x, y = nav:GetPoint(1)
        if p then
            nd.origP, nd.origRel, nd.origRP = p, rel, rp
            nd.origX, nd.origY = x or 0, y or 0
        end
    end
    if nd.origP then
        nav:ClearAllPoints()
        nav:SetPoint(nd.origP, nd.origRel, nd.origRP,
            nd.origX + (dx or 0), nd.origY + (dy or 0))
    end
    if nd.origH == nil then
        local h = nav:GetHeight()
        if h and h > 0 then nd.origH = h end
    end
    if nd.origH then nav:SetHeight(nd.origH - 6) end
    local keep = { [nd.bg] = true }
    WSkin.FadeRegions(nav, keep)
    WSkin.Register(nav, true)
    if nav.overlay then
        -- Decorative overlay frame: alpha the whole frame so its anonymous
        -- textures can never resurface.
        WSkin.FadeRegions(nav.overlay)
        local nt = nav.overlay.GetNormalTexture and nav.overlay:GetNormalTexture()
        if nt and nt.SetAlpha then nt:SetAlpha(0) end
        if nav.overlay.SetAlpha then nav.overlay:SetAlpha(0) end
        WSkin.Register(nav.overlay, true)
    end
    if nav.navList then
        local n = #nav.navList
        -- The wash covers only the crumbs, not the nav's full width: left
        -- edges ride the nav, the right edge rides the last crumb.
        local last = nav.navList[n]
        if last and nd.bg then
            nd.bg:ClearAllPoints()
            nd.bg:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
            nd.bg:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 0, 0)
            nd.bg:SetPoint("RIGHT", last, "RIGHT", 0, 0)
        end
        for i = 1, n do
            local b = nav.navList[i]
            if b then
                SkinNavButton(b)
                -- Content-driven width + seamless chain: each crumb is
                -- exactly |pad|text (gap arrow)|pad| wide and butts up
                -- against its neighbour, so the divider sits precisely on
                -- the boundary with even spacing on both sides.
                local tw = (b.text and b.text.GetStringWidth and b.text:GetStringWidth()) or 0
                local ma = b.MenuArrowButton
                local hasArrow = ma and ma:IsShown()
                b:SetWidth(NAV_PAD + tw + (hasArrow and (NAV_ARROW_GAP + NAV_ARROW_W) or 0) + NAV_PAD)
                if i > 1 and nav.navList[i - 1] then
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", nav.navList[i - 1], "RIGHT", 0, 0)
                end
                local bd = FFD[b]
                if bd and bd.divider then bd.divider:SetShown(i < n) end
            end
        end
    end
end

-- Boss-list row: keep the creature render, 10% white block behind, white name.
local function SkinBossButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if not d.bossbtn then
        d.bossbtn = true
        for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local fn = btn[g]; local t = fn and fn(btn)
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        local fill = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
        fill:SetColorTexture(1, 1, 1, 0.1)
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        d.bg = fill
        -- No border: the creature render overflows the row and a border would
        -- draw a line across the model.
    end
    if btn.text then WSkin.White(btn.text) end
    if btn.name then WSkin.White(btn.name) end
    -- The actively displayed boss keeps the full plate; the rest read at
    -- half. With no boss selected (instance overview), all stay full.
    local ejID = _G.EncounterJournal and _G.EncounterJournal.encounterID
    local active = not ejID or (btn.encounterID and btn.encounterID == ejID)
    d.bg:SetAlpha(active and 1 or 0.5)
end
local function FlattenBossButtons(frame, depth)
    depth = depth or 0
    if not frame or depth > 8 or frame:IsForbidden() or not frame.GetChildren then return end
    for i = 1, select("#", frame:GetChildren()) do
        local c = select(i, frame:GetChildren())
        if c and not WSkin.IsForeignFrame(c, frame) then
            if c.creature and (c.text or c.name) and c.GetObjectType and c:GetObjectType() == "Button" then
                SkinBossButton(c)
            end
            FlattenBossButtons(c, depth + 1)
        end
    end
end

-- Instance-select tile: keep the splash image, square it, frame it with the
-- auction house item-header atlas (sized to the image) + white hover. Raid
-- tiles carry extra baked border art the getter fades miss, so every texture
-- region except the splash, the frame art, and our hover is faded, re-asserted
-- per pass (tiles are pooled and repainted).
local function SkinInstanceButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if not d.instbtn then
        d.instbtn = true
        local frameArt = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        frameArt:SetAtlas("shop-card-wide-frame-default")
        frameArt:SetAlpha(0.5)
        if btn.bgImage then
            frameArt:SetAllPoints(btn.bgImage)
        else
            frameArt:SetAllPoints(btn)
        end
        d.frameArt = frameArt
        local hov = btn:CreateTexture(nil, "HIGHLIGHT")
        hov:SetAtlas("shop-card-wide-frame-hover")
        hov:SetAllPoints(frameArt)
        d.hover = hov
    end
    -- Blizzard re-anchors the splash on pool updates; re-assert a 1px inset
    -- every pass so the frame art following it clears the clipping viewport.
    if btn.bgImage and btn.bgImage.SetPoint then
        btn.bgImage:ClearAllPoints()
        btn.bgImage:SetPoint("TOPLEFT", 1, -1)
        btn.bgImage:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    -- Blend: Blizzard's native tile art shows at half strength under our
    -- frame art (splash, frame, and hover stay full). Only the native
    -- highlight stays fully faded -- our hover atlas replaces it.
    local keep = {}
    if btn.bgImage then keep[btn.bgImage] = true end
    if d.frameArt then keep[d.frameArt] = true end
    if d.hover then keep[d.hover] = true end
    for j = 1, select("#", btn:GetRegions()) do
        local r = select(j, btn:GetRegions())
        if r and not keep[r] and r.IsObjectType and r:IsObjectType("Texture") then
            r:SetAlpha(0.5)
        end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local fn = btn[g]; local t = fn and fn(btn)
        if t and not keep[t] and t.SetAlpha then t:SetAlpha(0.5) end
    end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl and not keep[hl] and hl.SetAlpha then hl:SetAlpha(0) end
end
local function FlattenInstanceButtons(frame, depth)
    depth = depth or 0
    if not frame or depth > 8 or frame:IsForbidden() or not frame.GetChildren then return end
    for i = 1, select("#", frame:GetChildren()) do
        local c = select(i, frame:GetChildren())
        if c and not WSkin.IsForeignFrame(c, frame) then
            if c.bgImage and c.name and c.GetObjectType and c:GetObjectType() == "Button" then
                SkinInstanceButton(c)
            end
            FlattenInstanceButtons(c, depth + 1)
        end
    end
end

-- Side icon tab (overview/loot/boss/model): a smaller dark box behind the
-- glyph (icon keeps its size) with a black border, pushed right so the tabs
-- hang off the window's side, with extra spacing between them. Blizzard's own
-- hover glow (HighlightTexture) is re-faded on every detail pass since the
-- journal re-raises tab art on navigation.
local SIDE_TAB_X     = 16   -- push right so the box sits flush on the panel edge
local SIDE_TAB_GAP   = 2    -- extra vertical space between tabs
local SIDE_TAB_INSET = 3    -- how much smaller the dark box is than the tab

-- Idempotent: original anchor offsets are captured once, then the shift is
-- always original + constants (never compounds). Handles both anchoring
-- shapes: chained (tab -> previous tab) and flat (every tab -> shared host).
local function PositionSideTab(tab, index)
    if not tab or tab:IsForbidden() then return end
    local d = GetFFD(tab)
    local p, rel, rp, x, y = tab:GetPoint(1)
    if not p then return end
    if d.origX == nil then d.origX, d.origY = x or 0, y or 0 end
    local relIsTab = rel and FFD[rel] and FFD[rel].sidetab
    local xAdd = relIsTab and 0 or SIDE_TAB_X
    local yMult = relIsTab and 1 or ((index or 1) - 1)
    tab:ClearAllPoints()
    tab:SetPoint(p, rel, rp, d.origX + xAdd, d.origY - SIDE_TAB_GAP * yMult)
end

local function SkinSideTab(tab, index)
    if not tab or tab:IsForbidden() then return end
    local d = GetFFD(tab)
    if not d.sidetab then
        d.sidetab = true
        -- The box sits two levels below the tab so its fill AND its border
        -- container (box level + 1) both draw beneath the tab's glyph.
        local box = CreateFrame("Frame", nil, tab)
        box:SetPoint("TOPLEFT", SIDE_TAB_INSET, -SIDE_TAB_INSET)
        box:SetPoint("BOTTOMRIGHT", -SIDE_TAB_INSET, SIDE_TAB_INSET)
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 2))
        local fill = SolidTex(box, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        fill:SetAllPoints(box)
        WSkin.AddBorder(box, 0, 0, 0, 1)
        d.box = box
        d.bg = fill
        local hov = SolidTex(tab, "HIGHLIGHT", 1, 1, 1, 0.1)
        hov:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        hov:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        d.hover = hov
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local fn = tab[g]; local t = fn and fn(tab)
        if t and t ~= d.hover and t.SetAlpha then t:SetAlpha(0) end
    end
    -- Pin the glyph to its original anchor. The old 3px-left nudge is gone
    -- (icons read off-center with it), and Blizzard re-seats the icon on
    -- click/selection -- the pin re-asserts synchronously inside that very
    -- SetPoint (reentry-guarded), so the icon never hops. Single-point
    -- regions only; all-points state textures are left alone.
    for j = 1, select("#", tab:GetRegions()) do
        local r = select(j, tab:GetRegions())
        if r and r ~= d.hover and r.IsObjectType and r:IsObjectType("Texture")
           and r.GetNumPoints and r:GetNumPoints() == 1 then
            local rd = GetFFD(r)
            if not rd.pinned then
                local p, rel, rp, x, y = r:GetPoint(1)
                if p then
                    rd.pinned = true
                    rd.pin = { p, rel, rp, x or 0, y or 0 }
                    hooksecurefunc(r, "SetPoint", function()
                        if rd.inPin then return end
                        rd.inPin = true
                        r:ClearAllPoints()
                        r:SetPoint(rd.pin[1], rd.pin[2], rd.pin[3], rd.pin[4], rd.pin[5])
                        rd.inPin = false
                    end)
                end
            end
        end
    end
    -- Grayed-out (disabled) tabs read at half opacity across the board:
    -- plate, border, and icon dim together via the tab's own alpha.
    local enabled = not tab.IsEnabled or tab:IsEnabled()
    tab:SetAlpha(enabled and 1 or 0.5)
    -- Tab 10% smaller (one-shot; the box follows its insets, the glyph keeps
    -- its native size).
    if not d.shrunk then
        local w, h = tab:GetSize()
        if w and h and w > 0 and h > 0 then
            d.shrunk = true
            tab:SetSize(w * 0.9, h * 0.9)
        end
    end
    PositionSideTab(tab, index)
end

-- Loot row: parchment art gone, flat block, squared item icon, light subtext.
local function SkinLootRow(btn)
    if not btn or btn:IsForbidden() then return end
    if btn.bossTexture and btn.bossTexture.SetAlpha then btn.bossTexture:SetAlpha(0) end
    if btn.bosslessTexture and btn.bosslessTexture.SetAlpha then btn.bosslessTexture:SetAlpha(0) end
    local d = GetFFD(btn)
    if not d.lootrow then
        d.lootrow = true
        local fill = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
        fill:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        d.bg = fill
        WSkin.AddBorder(btn)
        if btn.icon then WSkin.SquareIcon(btn.icon, btn) end
    end
    for _, k in ipairs({ "slot", "armorType", "boss" }) do
        local fs = btn[k]
        if fs then WSkin.White(fs, 0.82, 0.82, 0.82) end
    end
end
local function FlattenLootRows(frame, depth)
    depth = depth or 0
    if not frame or depth > 8 or frame:IsForbidden() or not frame.GetChildren then return end
    for i = 1, select("#", frame:GetChildren()) do
        local c = select(i, frame:GetChildren())
        if c and not WSkin.IsForeignFrame(c, frame) then
            if c.bossTexture and c.slot and c.GetObjectType and c:GetObjectType() == "Button" then
                SkinLootRow(c)
            end
            FlattenLootRows(c, depth + 1)
        end
    end
end

-- Gear-tab filter dropdowns: native caret faded, the house arrow seated just
-- past the label's actual text end (measured, and re-seated when the text
-- changes -- the label rect is wider than the text, which is why anchoring to
-- Blizzard's caret position sat the arrow too far away).
local function SwapFilterArrow(filt)
    if not filt then return end
    local fd = GetFFD(filt)
    if filt.Arrow and filt.Arrow.SetAlpha then filt.Arrow:SetAlpha(0) end
    if fd.arrow then return end
    local arrow = filt:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("Azerite-PointingArrow")
    arrow:SetSize(12, 8.5)
    fd.arrow = arrow
    local label = filt.Text or (filt.GetFontString and filt:GetFontString())
    if label and label.GetStringWidth then
        local function seat()
            arrow:ClearAllPoints()
            -- GetStringWidth is the FULL untruncated text width; when the label
            -- is width-constrained and truncates with an ellipsis, the visible
            -- text ends at the label's own width. Hug the visible edge, not the
            -- phantom full-text edge.
            local sw = label:GetStringWidth() or 0
            local lw = (label.GetWidth and label:GetWidth()) or 0
            if lw > 0 and sw > lw then sw = lw end
            arrow:SetPoint("LEFT", label, "LEFT", sw + 4, 0)
        end
        seat()
        hooksecurefunc(label, "SetText", seat)
    elseif filt.Arrow then
        arrow:SetPoint("CENTER", filt.Arrow, "CENTER", 0, 0)
    else
        arrow:SetPoint("RIGHT", filt, "RIGHT", -6, 0)
    end
end

-- Ability / overview section header: paper header art gone, flat block,
-- white title, and the hover glow replaced by the standard subtle whiten
-- wash. Covers both the encounter-info headers (title + expandedIcon) and
-- the Overview tab's headers (Title only, separate Glow child frame). All
-- native art is re-faded per pass since Blizzard repaints on expand/collapse.
local function SkinAbilityHeaders(frame, depth)
    depth = depth or 0
    if not frame or depth > 9 or frame:IsForbidden() or not frame.GetChildren then return end
    for i = 1, select("#", frame:GetChildren()) do
        local c = select(i, frame:GetChildren())
        if c and not WSkin.IsForeignFrame(c, frame) then
            if c.descriptionBG and c.descriptionBG.SetAlpha then c.descriptionBG:SetAlpha(0) end
            if c.descriptionBGBottom and c.descriptionBGBottom.SetAlpha then c.descriptionBGBottom:SetAlpha(0) end
            -- Description line bullets -> the round status orb (first cell of
            -- the lootroll reveal sheet, same as the friends list), in white.
            local blt = c.Bullet
            if blt and blt.SetTexture and not GetFFD(blt).orbed then
                GetFFD(blt).orbed = true
                local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
                if info and info.file then
                    local aL, aR = info.leftTexCoord or 0, info.rightTexCoord or 1
                    local aT, aB = info.topTexCoord or 0, info.bottomTexCoord or 1
                    blt:SetTexture(info.file)
                    blt:SetTexCoord(aL, aL + (aR - aL) / 6, aT, aT + (aB - aT) / 2)
                else
                    blt:SetAtlas("lootroll-animreveal-a")
                    blt:SetTexCoord(0, 1 / 6, 0, 0.5)
                end
                blt:SetVertexColor(1, 1, 1, 1)
                local bw, bh = blt:GetSize()
                if bw and bh and bw > 0 and bh > 0 then blt:SetSize(bw + 2, bh + 2) end
            end
            local b = c.button
            local bTitle = b and (b.title or b.Title)
            if b and bTitle then
                local d = GetFFD(b)
                if not d.abilrow then
                    d.abilrow = true
                    local fill = b:CreateTexture(nil, "BACKGROUND", nil, -2)
                    fill:SetColorTexture(Theme.bgR + 0.02, Theme.bgG + 0.02, Theme.bgB + 0.02, Theme.bgA)
                    fill:SetPoint("TOPLEFT", 0, -1)
                    fill:SetPoint("BOTTOMRIGHT", 0, 1)
                    d.bg = fill
                    WSkin.AddBorder(b)
                    local hov = SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.05)
                    hov:SetPoint("TOPLEFT", 0, -1)
                    hov:SetPoint("BOTTOMRIGHT", 0, 1)
                    d.hover = hov
                end
                -- Every native texture region goes (paper caps, highlight
                -- strips, anonymous art), keeping only our fill + wash -- AND
                -- the boss ability's spell icon (<button>AbilityIcon), which is
                -- a real texture region on the header button, so the blanket
                -- fade below was stripping it. Preserve it by name/parentKey.
                local keep = { [d.bg] = true, [d.hover] = true }
                local abIcon = b.AbilityIcon
                    or (b.GetName and b:GetName() and _G[b:GetName() .. "AbilityIcon"])
                if abIcon then keep[abIcon] = true end
                WSkin.FadeRegions(b, keep)
                local hl = b.GetHighlightTexture and b:GetHighlightTexture()
                if hl and not keep[hl] and hl.SetAlpha then hl:SetAlpha(0) end
                -- Glow lives on a child frame (found by name; parentKey varies).
                for j = 1, select("#", b:GetChildren()) do
                    local ch = select(j, b:GetChildren())
                    if ch and ch.GetName then
                        local nm = ch:GetName()
                        if nm and nm:find("Glow", 1, true) and ch.SetAlpha then
                            WSkin.FadeRegions(ch)
                            ch:SetAlpha(0)
                        end
                    end
                end
                WSkin.White(bTitle)
                if b.expandedIcon and b.expandedIcon.SetTextColor then b.expandedIcon:SetTextColor(1, 1, 1) end
                -- Role icons (tank/healer/dps sections): 4px smaller. They
                -- hang off the header button by GLOBAL name only (no parent
                -- key): <button>Icon1..4 frames, each with an <icon>Icon
                -- texture inside (shrunk too when explicitly sized;
                -- all-points ones just follow the frame).
                if not d.iconShrunk then
                    d.iconShrunk = true
                    local bn = b.GetName and b:GetName()
                    local seen = {}
                    for j = 0, 4 do
                        local ic
                        if j == 0 then
                            ic = b.icon or b.Icon
                        else
                            ic = b["Icon" .. j] or (bn and _G[bn .. "Icon" .. j])
                        end
                        if ic and ic.GetSize then
                            local w, h = ic:GetSize()
                            if w and h and w > 4 and h > 4 then
                                ic:SetSize(w - 4, h - 4)
                                local inner = ic.Icon or (ic.GetName and ic:GetName() and _G[ic:GetName() .. "Icon"])
                                if inner and inner.GetSize then
                                    local iw, ih = inner:GetSize()
                                    if iw and ih and iw > 4 and ih > 4 then
                                        inner:SetSize(iw - 4, ih - 4)
                                    end
                                end
                            end
                            -- 3px left. Icons chained to a previous icon keep
                            -- their relative anchor (shifting the chain root
                            -- moves the whole group); only non-chained ones
                            -- get the offset directly.
                            local p, rel, rp, x, y = ic:GetPoint(1)
                            if p and not seen[rel] then
                                ic:ClearAllPoints()
                                ic:SetPoint(p, rel, rp, (x or 0) - 3, y or 0)
                            end
                            seen[ic] = true
                        end
                    end
                end
            end
            SkinAbilityHeaders(c, depth + 1)
        end
    end
end

-- The instance-select pane scene (shared by the Tutorials and Dungeons/Raids
-- views) drops to 50% alpha so the shell shows through -- true translucency,
-- not a darken. The art is the $parentBG texture plus anonymous BACKGROUND
-- regions on the pane, so every BACKGROUND-layer texture there above 50% is
-- lowered (never raised: art we faded stays faded). Re-applied on each
-- refresh pass in case Blizzard re-asserts it.
local function RestyleInstanceScene(isel)
    if not isel then return end
    for i = 1, select("#", isel:GetRegions()) do
        local r = select(i, isel:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and r:GetDrawLayer() == "BACKGROUND" then
            local a = r:GetAlpha() or 1
            if a > 0.5 then r:SetAlpha(0.25) end
        end
    end
end

-- The Great Vault shortcut (instanceSelect.GreatVaultButton, top right of the
-- Journeys/instance views) gets the same vault art as the minimap's Great
-- Vault button: its state textures are retextured in place (geometry,
-- anchors, and hover untouched).
local VAULT_BUTTON_ATLAS = "greatVault-whole-normal"
local function RestyleGreatVaultButton(gv)
    if not gv or gv:IsForbidden() then return end
    local d = GetFFD(gv)
    -- 14px smaller (one-shot; retries until the button has a laid-out size).
    if not d.shrunk then
        local w, h = gv:GetSize()
        if w and h and w > 14 and h > 14 then
            d.shrunk = true
            gv:SetSize(w - 14, h - 14)
        end
    end
    -- 4px right of wherever Blizzard seats it. Applied relative to the
    -- current anchor via a SetPoint post-hook, so any per-view repositioning
    -- Blizzard does is kept (a fixed captured anchor here bled the Journeys
    -- position onto the other tabs).
    if not d.nudged then
        d.nudged = true
        local function nudge()
            if d.inNudge then return end
            local p, rel, rp, x, y = gv:GetPoint(1)
            if not p then return end
            d.inNudge = true
            gv:ClearAllPoints()
            gv:SetPoint(p, rel, rp, (x or 0) + 4, y or 0)
            d.inNudge = false
        end
        hooksecurefunc(gv, "SetPoint", nudge)
        nudge()
    end
    if d.vaultSwapped then return end
    local swapped = false
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local t = gv[g] and gv[g](gv)
        if t and t.SetAtlas then
            t:SetAtlas(VAULT_BUTTON_ATLAS)
            swapped = true
        end
    end
    for j = 1, select("#", gv:GetRegions()) do
        local r = select(j, gv:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            local hay = WSkin.TexHay(r)
            if hay and hay:find("vault", 1, true) then
                r:SetAtlas(VAULT_BUTTON_ATLAS)
                swapped = true
            end
        end
    end
    if swapped then d.vaultSwapped = true end
end

-- Round creature portraits on the encounter page: the delve companion ring
-- as the circle border, sized 2px outside the creature texture itself (not
-- the frame around it), no plate (their field shape matches the boss-row
-- pass, which is what gave them the light background). No active/inactive
-- state styling -- all portraits render normally.
local function RingCreatureFrame(cb, creature)
    if not cb or cb:IsForbidden() then return end
    local d = GetFFD(cb)
    creature = creature or cb.creature or cb.Creature
    if not creature then
        local n = cb.GetName and cb:GetName()
        creature = n and _G[n .. "Creature"] or nil
    end
    if not d.ring then
        local ring = cb:CreateTexture(nil, "OVERLAY", nil, 7)
        ring:SetAtlas("UI-Journeys-Delve-Companion-Ring")
        -- 2px outset per side (4px larger than the portrait).
        local anchor = creature or cb
        ring:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
        ring:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
        d.ring = ring
        d.creature = creature
    end
    -- Neutralize the white plate the boss-row pass laid on it.
    if d.bg then d.bg:SetColorTexture(0, 0, 0, 0) end
end

local function SkinCreatureButtons()
    for i = 1, 9 do
        local cb = _G["EncounterJournalEncounterFrameInfoCreatureButton" .. i]
        if not cb then break end
        RingCreatureFrame(cb)
    end
    -- The main creature display: an anonymous child frame of info carrying a
    -- CircleMask; its portrait is the info-named Creature texture.
    local info = _G.EncounterJournalEncounterFrameInfo
    if info then
        for i = 1, select("#", info:GetChildren()) do
            local ch = select(i, info:GetChildren())
            if ch and ch.CircleMask and not GetFFD(ch).ring then
                local creature = _G.EncounterJournalEncounterFrameInfoCreature
                if creature and creature.GetParent and creature:GetParent() ~= ch then
                    creature = nil
                end
                RingCreatureFrame(ch, creature)
            end
        end
    end
end

local _ejHooked = false
local function Skin_EncounterJournal()
    local f = _G.EncounterJournal
    if not f then return end
    WSkin.Shell("adventureguide", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "EncounterJournal")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.EncounterJournalBg then _G.EncounterJournalBg:SetAlpha(0) end
    for _, k in ipairs({ "inset", "Inset" }) do
        if f[k] then WSkin.Inset(f[k]) end
    end

    -- The main-area scene background (instanceSelect.evergreenBg) is shared by
    -- the Tutorials tab AND the Dungeons/Raids instance-select views -- it IS
    -- the content there, so every art sweep skips those subtrees. The instance
    -- tiles inside still get squared by FlattenInstanceButtons (a targeted
    -- pass, not an art sweep).
    if f.TutorialsFrame then WSkin.ExemptArt(f.TutorialsFrame) end
    if f.instanceSelect then WSkin.ExemptArt(f.instanceSelect) end

    -- Breadcrumb bar: a faint 5% white wash (no border), seated 8px lower and
    -- 35px left of Blizzard's spot -- white crumbs with dividers between
    -- entries. The reseat is idempotent: original anchors are captured once.
    local nav = f.navBar
    local function RefreshNav()
        RestyleNavGeneric(nav, -37, -8)
    end
    _navReflow = RefreshNav
    if nav then GetFFD(nav).reflow = RefreshNav end
    RefreshNav()

    if f.LootJournalViewDropdown then WSkin.Dropdown(f.LootJournalViewDropdown) end
    if f.searchBox then
        WSkin.EditBox(f.searchBox)
        -- Seat 2px lower than Blizzard's spot (idempotent: original anchor
        -- captured once).
        local sd = GetFFD(f.searchBox)
        if sd.origP == nil then
            local p, rel, rp, x, y = f.searchBox:GetPoint(1)
            if p then
                sd.origP, sd.origRel, sd.origRP = p, rel, rp
                sd.origX, sd.origY = x or 0, y or 0
            end
        end
        if sd.origP then
            f.searchBox:ClearAllPoints()
            f.searchBox:SetPoint(sd.origP, sd.origRel, sd.origRP, sd.origX, sd.origY - 2)
        end
    end
    -- Search autocomplete preview dropdown + full results window. The popout
    -- under the search box (searchPreviewContainer + showAllResults) was
    -- unskinned -- Blizzard corner art on a bright container. Container -> flat
    -- dark panel; preview rows + "show all results" -> subtle hover + white
    -- text; results window -> panel + slim scrollbar + house close button.
    local sbox = f.searchBox
    local prevC = sbox and sbox.searchPreviewContainer
    if prevC then
        WSkin.Panel(prevC)
        -- framed = the button is its OWN panel (bg + border). The preview rows
        -- sit inside the container's panel so they need none, but showAllResults
        -- is a SIBLING below the container (no backdrop of its own), so it gets
        -- its own dark fill + border to close off the dropdown.
        local function SkinEJSearchBtn(btn, framed)
            if not btn or btn:IsForbidden() then return end
            local d = GetFFD(btn)
            if not d.ejSearchSkinned then
                d.ejSearchSkinned = true
                local icon = btn.icon or btn.Icon
                local keep = icon and { [icon] = true } or nil
                WSkin.FadeRegions(btn, keep)
                if framed then
                    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                    bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                    bg:SetAllPoints(btn)
                    d.bg = bg
                    WSkin.AddBorder(btn)
                end
                local hov = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
                hov:SetAllPoints(btn)
                d.hover = hov
                WSkin.Register(btn, keep or true)
                if icon then WSkin.SquareIcon(icon, btn) end
            end
            if btn.selectedTexture and btn.selectedTexture.SetColorTexture then
                btn.selectedTexture:SetColorTexture(1, 1, 1, 0.12)
            end
            for _, k in ipairs({ "name", "text", "resultType" }) do
                local fs = btn[k]
                if fs and fs.SetTextColor then WSkin.White(fs) end
            end
        end
        local function SkinAllEJSearch()
            -- Re-assert the container panel too: Blizzard re-raises its corner
            -- art when the popout is shown, which was hiding our border.
            WSkin.Panel(prevC)
            for i = 1, (_G.EJ_NUM_SEARCH_PREVIEWS or 5) do
                SkinEJSearchBtn(sbox["searchPreview" .. i])
            end
            SkinEJSearchBtn(sbox.showAllResults, true)
        end
        SkinAllEJSearch()
        -- Preview rows are re-populated as you type; re-white after each update.
        if not GetFFD(sbox).searchHook and type(_G.EncounterJournal_SetSearchPreview) == "function" then
            GetFFD(sbox).searchHook = true
            hooksecurefunc("EncounterJournal_SetSearchPreview", SkinAllEJSearch)
        end
    end
    local sr = _G.EncounterJournalSearchResults
    if sr then
        WSkin.Panel(sr)
        if sr.ScrollBar then WSkin.ScrollBar(sr.ScrollBar) end
        local cb = _G.EncounterJournalSearchResultsCloseButton or sr.CloseButton
        if cb then WSkin.CloseButton(cb) end
    end
    if f.instanceSelect then
        if f.instanceSelect.ExpansionDropdown then WSkin.Dropdown(f.instanceSelect.ExpansionDropdown) end
        if f.instanceSelect.Title then WSkin.White(f.instanceSelect.Title) end
        FlattenInstanceButtons(f.instanceSelect)
    end
    if f.encounter and f.encounter.info and f.encounter.info.difficulty then
        local diff = f.encounter.info.difficulty
        WSkin.Dropdown(diff)
        -- Seat 4px left of Blizzard's spot (idempotent: original anchor
        -- captured once).
        local dd = GetFFD(diff)
        if dd.origP == nil then
            local p, rel, rp, x, y = diff:GetPoint(1)
            if p then
                dd.origP, dd.origRel, dd.origRP = p, rel, rp
                dd.origX, dd.origY = x or 0, y or 0
            end
        end
        if dd.origP then
            diff:ClearAllPoints()
            diff:SetPoint(dd.origP, dd.origRel, dd.origRP, dd.origX - 6, dd.origY)
        end
    end

    local ejTabs = {}
    for _, k in ipairs({ "JourneysTab", "MonthlyActivitiesTab", "suggestTab",
                         "dungeonsTab", "raidsTab", "LootJournalTab", "TutorialsTab" }) do
        local t = f[k]
        if t then WSkin.Tab(t); ejTabs[#ejTabs + 1] = t end
    end
    WSkin.NormalizeTabRow(ejTabs)

    if f.instanceSelect then
        RestyleGreatVaultButton(f.instanceSelect.GreatVaultButton)
        RestyleInstanceScene(f.instanceSelect)
    end

    local function RefreshSuggest()
        local sf = f.suggestFrame
        if not sf then return end
        WhitenTextIn(sf)
        -- The three suggestion panels keep their big artwork: exempt their
        -- subtrees from the art fade and restore the bg it already zeroed.
        for i = 1, 3 do
            local s = sf["Suggestion" .. i]
            if s then
                WSkin.ExemptArt(s)
                if s.bg then s.bg:SetAlpha(0.4) end
            end
        end
        local s1 = sf.Suggestion1
        if s1 then
            if s1.prevButton then WSkin.PageButton(s1.prevButton, "<", 12) end
            if s1.nextButton then WSkin.PageButton(s1.nextButton, ">", 12) end
            -- Hero suggestion's action button label 2px smaller (target size
            -- captured once, re-asserted since Blizzard can re-apply its font
            -- object on refresh).
            local bfs = s1.button and s1.button.GetFontString and s1.button:GetFontString()
            if bfs then
                local path, sz, flags = bfs:GetFont()
                if path and sz then
                    local bd = GetFFD(bfs)
                    if not bd.size then bd.size = sz - 2 end
                    if math.abs(sz - bd.size) > 0.01 then bfs:SetFont(path, bd.size, flags) end
                end
            end
        end
    end
    RefreshSuggest()

    -- Traveler's Log: seat the info (help) button on the window's left edge,
    -- keeping its vertical spot. Anchored to the window itself, not the
    -- activities pane -- the pane is inset, so its left edge is not the
    -- window's. Retries until the pane has been laid out.
    local function SeatMonthlyHelp()
        local ma = f.MonthlyActivitiesFrame
        local hb = ma and ma.HelpButton
        if not hb or GetFFD(hb).moved then return end
        local top, fTop = hb:GetTop(), f:GetTop()
        if top and fTop then
            GetFFD(hb).moved = true
            hb:ClearAllPoints()
            hb:SetPoint("TOPLEFT", f, "TOPLEFT", 4, top - fTop)
        end
    end
    SeatMonthlyHelp()

    -- Boss detail "book": strip parchment, flatten rows, white the text.
    local function RefreshDetail()
        local e = f.encounter
        if not e then return end
        if _G.EncounterJournalEncounterFrameInfoBG then _G.EncounterJournalEncounterFrameInfoBG:SetAlpha(0) end
        local info = e.info
        if info then
            for _, k in ipairs({ "leftShadow", "rightShadow", "titleBG" }) do
                local t = info[k]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            -- Model tab: remove the scene backdrop + vignette behind the boss
            -- model (re-textured per encounter, so re-fade each pass).
            for _, n in ipairs({ "EncounterJournalEncounterFrameInfoModelFrameDungeonBG",
                                 "EncounterJournalEncounterFrameInfoModelFrameShadow" }) do
                local t = _G[n]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            local lc = info.LootContainer
            if lc then
                for _, k in ipairs({ "bossTexture", "bosslessTexture" }) do
                    local t = lc[k]
                    if t and t.SetAlpha then t:SetAlpha(0) end
                end
                FlattenLootRows(lc)
                -- Pooled rows: scrolling realizes new frames and re-inits
                -- recycled ones through paths that fire no journal repaint,
                -- which intermittently brought Blizzard's row art back on
                -- scroll-up. Re-skin realized rows on every ScrollBox update
                -- (cost scales with visible rows only).
                local sb = lc.ScrollBox
                if sb and sb.ForEachFrame then
                    pcall(sb.ForEachFrame, sb, SkinLootRow)
                    if sb.Update and not GetFFD(sb).rowHook then
                        GetFFD(sb).rowHook = true
                        hooksecurefunc(sb, "Update", function(box)
                            pcall(box.ForEachFrame, box, SkinLootRow)
                        end)
                    end
                end
                -- Gear tab filters: house arrows hugging the label text.
                SwapFilterArrow(lc.filter)
                SwapFilterArrow(lc.slotFilter)
            end
            local sideTabs = { "overviewTab", "lootTab", "bossTab", "modelTab" }
            for i = 1, #sideTabs do
                SkinSideTab(info[sideTabs[i]], i)
            end
            -- Vertical divider down the center of the detail view. The info
            -- frame spans the whole detail area (the boss list lives INSIDE
            -- it), so the true split is the boss list's right edge.
            local ed = GetFFD(info)
            local bossList = info.BossesScrollBox
            if bossList and not ed.centerDivider then
                local div = info:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.15)
                div:SetWidth(1)
                div:SetPoint("TOPLEFT", bossList, "TOPRIGHT", 24, 8)
                div:SetPoint("BOTTOMLEFT", bossList, "BOTTOMRIGHT", 24, 12)
                ed.centerDivider = div
            end
            if info.overviewScroll and info.overviewScroll.child and info.overviewScroll.child.header
               and info.overviewScroll.child.header.SetAlpha then
                info.overviewScroll.child.header:SetAlpha(0)
            end
        end
        if e.instance and e.instance.titleBG and e.instance.titleBG.SetAlpha then
            e.instance.titleBG:SetAlpha(0)
        end
        SkinAbilityHeaders(e)
        FadeEJArt(e)
        FlattenBossButtons(e)
        SkinCreatureButtons()
        WhitenTextIn(e)
    end
    RefreshDetail()

    FadeEJArt(f)
    WSkin.ButtonsIn(f)
    WSkin.ScrollBarsIn(f)
    WSkin.FadeKeyedArt(f)

    -- Blizzard repopulates the detail panes on navigation; the hooks fire many
    -- times per click, so the pass is debounced and skipped while hidden.
    if not _ejHooked then
        _ejHooked = true
        local refresh = WSkin.Debounce(function()
            if not f:IsVisible() then return end
            RefreshDetail()
            RefreshNav()
            if f.instanceSelect then
                FlattenInstanceButtons(f.instanceSelect)
                RestyleGreatVaultButton(f.instanceSelect.GreatVaultButton)
                RestyleInstanceScene(f.instanceSelect)
            end
            SeatMonthlyHelp()
            WSkin.Restrip()
        end)
        local function deferRefresh()
            -- Kill the biggest parchment synchronously so it cannot flash for
            -- a frame before the debounced pass runs.
            if _G.EncounterJournalEncounterFrameInfoBG then _G.EncounterJournalEncounterFrameInfoBG:SetAlpha(0) end
            refresh()
        end
        for _, fn in ipairs({ "EncounterJournal_DisplayInstance", "EncounterJournal_DisplayEncounter",
                              "EncounterJournal_SetUpOverview", "EncounterJournal_ToggleHeaders",
                              "EncounterJournal_SetTab", "EJ_ContentTab_Select", "NavBar_AddButton" }) do
            if type(_G[fn]) == "function" then hooksecurefunc(fn, deferRefresh) end
        end
        -- The debounced pass runs a frame late, which let a new crumb render
        -- one frame at Blizzard's layout before ours (a visible text snap).
        -- Reflow the nav synchronously the moment a crumb is added. Cheap:
        -- a handful of buttons, text measure + anchors only.
        if type(_G.NavBar_AddButton) == "function" then
            hooksecurefunc("NavBar_AddButton", function(bar)
                if bar == nav then RefreshNav() end
            end)
        end
        if type(_G.EJSuggestFrame_RefreshDisplay) == "function" then
            hooksecurefunc("EJSuggestFrame_RefreshDisplay", WSkin.Debounce(RefreshSuggest))
        end
        -- Global Options edits (link color) re-run the text passes live.
        WSkin.OnLooksChanged(function()
            if f:IsVisible() then
                deferRefresh()
                RefreshSuggest()
            end
        end)
    end

    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then
            RefreshDetail()
            RefreshNav()
            if f.instanceSelect then
                RestyleGreatVaultButton(f.instanceSelect.GreatVaultButton)
                RestyleInstanceScene(f.instanceSelect)
            end
            WSkin.Restrip()
            WSkin.UpdateAllTabs()
        end
    end))
end

WSkin.RegisterWindow({
    key = "adventureguide",
    addons = { Blizzard_EncounterJournal = true },
    apply = Skin_EncounterJournal,
})

-------------------------------------------------------------------------------
--  Professions Book (ProfessionsBookFrame)
-------------------------------------------------------------------------------
local PROF_FRAMES = { "PrimaryProfession1", "PrimaryProfession2",
                      "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }

-- Settle gate: Shifter applies the user's scale on OnShow, AFTER the book has
-- shown, so Blizzard's content reflows across several passes on a scaled
-- reopen. If the per-pass text seating runs mid-reflow it nudges strings from
-- a transient baseline, then the layout settles under it and the correction
-- stacks -- text ends up flung 60-70px off. We seat ONLY when the content's
-- geometry signature matches the previous pass (settled); while it is still
-- moving we skip seating and schedule one trailing pass so the settled state
-- always gets a clean seat.
local _profSettleSig, _profSettlePending
local function ProfContentSig()
    local sig = 0
    for _, n in ipairs(PROF_FRAMES) do
        local fr = _G[n]
        if fr then
            local t = fr.GetTop and fr:GetTop()
            local sb = fr.statusBar
            local bt = sb and sb.GetTop and sb:GetTop()
            sig = sig + (t or 0) * 7 + (bt or 0) * 13
        end
    end
    return sig
end

local function SkinProfSpellButton(b)
    if not b then return end
    local bn = b.GetName and b:GetName()
    if bn then
        local nf = _G[bn .. "NameFrame"]
        if nf and nf.SetAlpha then nf:SetAlpha(0) end
    end
    for _, k in ipairs({ "Border", "FlyoutBorder", "FlyoutBorderShadow", "Background", "Flash" }) do
        local t = b[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt and nt.SetAlpha then nt:SetAlpha(0) end
    local icon = b.IconTexture or (bn and _G[bn .. "IconTexture"])
    if icon then WSkin.SquareIcon(icon, b) end
    if b.spellString then WSkin.Font(b.spellString); WSkin.White(b.spellString) end
    if b.subSpellString then WSkin.Font(b.subSpellString); WSkin.White(b.subSpellString, 0.8, 0.8, 0.8) end
end

local function SkinProfStatusBar(sb)
    if not sb then return end
    local n = sb.GetName and sb:GetName()
    if n then
        for _, suf in ipairs({ "Left", "Right", "BGLeft", "BGMiddle", "BGRight" }) do
            local t = _G[n .. suf]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
    end
    if sb.capRight and sb.capRight.SetAlpha then sb.capRight:SetAlpha(0) end
    if sb.SetStatusBarTexture then
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        WSkin.ApplyBarFill(sb)
    end
    local d = GetFFD(sb)
    -- Blizzard's bar VISUAL (cap + middle + cap art) is wider than the
    -- StatusBar frame itself; the flat fill only covers the frame, which
    -- reads shorter and skews text anchored around the bar. Stretch the
    -- frame to the art's measured span -- but ONLY when the art sits a
    -- plausible cap-width from the frame. The art is laid out relative to
    -- the bar/row, so a big delta means the row's art uses a different
    -- layout (secondary rows); moving the bar by that delta yanked those
    -- bars clean off their tiles.
    if not d.stretched and n and not InCombatLockdown() then
        local bgl, bgr = _G[n .. "BGLeft"], _G[n .. "BGRight"]
        local L = bgl and bgl.GetLeft and bgl:GetLeft()
        local R = bgr and bgr.GetRight and bgr:GetRight()
        local sL = sb.GetLeft and sb:GetLeft()
        if L and R and sL and R > L then
            d.stretched = true
            local delta = L - sL
            if math.abs(delta) <= 20 then
                local p, rel, rp, x, y = sb:GetPoint(1)
                if p and p:find("LEFT", 1, true) then
                    sb:ClearAllPoints()
                    sb:SetPoint(p, rel, rp, (x or 0) + delta, y or 0)
                end
                sb:SetWidth(R - L)
            end
        end
    end
    if not d.bg then
        local bg = sb:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        bg:SetAllPoints(sb)
        d.bg = bg
        WSkin.AddBorder(sb)
    end
    if sb.rankText then
        WSkin.Font(sb.rankText)
        WSkin.White(sb.rankText)
        -- Sit the bar text 3px lower (one-shot).
        local rd = GetFFD(sb.rankText)
        if not rd.lowered then
            local p, rel, rp, x, y = sb.rankText:GetPoint(1)
            if p then
                rd.lowered = true
                sb.rankText:ClearAllPoints()
                sb.rankText:SetPoint(p, rel, rp, x or 0, (y or 0) - 3)
            end
        end
    end
end

local function RecolorProfessions()
    -- Profession frames chain to each other; a chained frame inherits the
    -- shift of the frame it hangs from, so only chain roots get the x offset
    -- (shifting every frame compounds 30px per row down the chain).
    local profSet = {}
    for _, n in ipairs(PROF_FRAMES) do
        local fr = _G[n]
        if fr then profSet[fr] = true end
    end
    -- Text seating runs only on a settled layout (signature matches the prior
    -- pass). While the content is still reflowing -- e.g. a Shifter-scaled
    -- reopen -- skip seating and queue one trailing pass so the settled frame
    -- still gets seated. The one-shot geometry below is idempotent and can run
    -- every pass; only the delta-nudge seating is gated.
    local sig = ProfContentSig()
    local seatOK = (_profSettleSig ~= nil) and (math.abs(sig - _profSettleSig) <= 0.5)
    _profSettleSig = sig
    if not seatOK and not _profSettlePending then
        _profSettlePending = true
        C_Timer.After(0.05, function()
            _profSettlePending = false
            local pf = _G.ProfessionsBookFrame
            if pf and pf:IsVisible() then RecolorProfessions() end
        end)
    end
    for _, n in ipairs(PROF_FRAMES) do
        local fr = _G[n]
        if fr then
            -- Content reaches 30px further left: left edge out, right edge
            -- unchanged (one-shot; left-anchored roots shift + widen,
            -- right-anchored ones just widen leftward). The row frames are
            -- PROTECTED (they host the secure profession spell buttons):
            -- geometry writes in combat are blocked, so skip without setting
            -- the one-shot flag and the next out-of-combat repaint applies.
            local gd = GetFFD(fr)
            if not gd.extended and not InCombatLockdown() then
                local p, rel, rp, x, y = fr:GetPoint(1)
                local w = fr:GetWidth()
                if p and w and w > 0 then
                    gd.extended = true
                    if p:find("LEFT", 1, true) and not profSet[rel] then
                        fr:ClearAllPoints()
                        fr:SetPoint(p, rel, rp, (x or 0) - 30, y or 0)
                    end
                    fr:SetWidth(w + 30)
                    -- Rects are stale right after the re-anchor; let the text
                    -- alignment below measure on the NEXT pass instead.
                    gd.skipAlignOnce = true
                end
            end
            -- Primary tiles: big left icon 12px smaller and seated 10px lower
            -- (one-shot; the icon's black border lines follow its rect).
            -- Secondary tiles: icon 2px smaller.
            local isPrimary = n:find("Primary", 1, true) ~= nil
            if fr.icon and not gd.iconAdj then
                local iw, ih = fr.icon:GetSize()
                if iw and ih and iw > 12 and ih > 12 then
                    gd.iconAdj = true
                    local shrink = isPrimary and 12 or 2
                    fr.icon:SetSize(iw - shrink, ih - shrink)
                    if isPrimary then
                        local p, rel, rp, x, y = fr.icon:GetPoint(1)
                        if p then
                            fr.icon:ClearAllPoints()
                            fr.icon:SetPoint(p, rel, rp, x or 0, (y or 0) - 10)
                        end
                    end
                end
            end
            -- Bar cluster rises 20px on learned primaries to close the gap
            -- the title drop opens. Runs BEFORE the text seating so targets
            -- capture post-raise geometry (a bar-anchored skill line would
            -- otherwise double-shift -- what broke the first attempt).
            SkinProfStatusBar(fr.statusBar, isPrimary and 20 or 0)
            if isPrimary then
                local ub = fr.unlearn or fr.UnlearnButton or _G[n .. "Unlearn"] or _G[n .. "UnlearnButton"]
                if ub and not GetFFD(ub).raised and not InCombatLockdown() then
                    local p, rel, rp, x, y = ub:GetPoint(1)
                    if p then
                        GetFFD(ub).raised = true
                        if rel ~= fr.statusBar and rel ~= fr.rank then
                            ub:ClearAllPoints()
                            ub:SetPoint(p, rel, rp, x or 0, (y or 0) + 20)
                        end
                    end
                end
            end
            -- Text seating, re-run every pass: Blizzard's update re-anchors
            -- these strings, so one-shots got stomped on the next repaint.
            -- Delta-based against measured targets (bar-left for x, captured
            -- original top minus the drop for y), so an already-seated string
            -- is a no-op (no compounding). Learned primary titles drop 20px;
            -- the unlearned header stays put (dropping it left a blank band
            -- above "Second Profession"). The skill line rises 20 only when
            -- it does NOT ride the bar (bar-anchored ones followed the raise).
            if gd.skipAlignOnce then
                gd.skipAlignOnce = nil
            elseif seatOK then
                local sbL = fr.statusBar and fr.statusBar.GetLeft and fr.statusBar:GetLeft()
                -- The Y target is stored as a gap from the FRAME top, not an
                -- absolute local-Y. A frame and its strings share one effective
                -- scale, so their GetTop difference is a scale-invariant local
                -- offset -- an absolute local-Y is NOT (the whole local origin
                -- shifts with scale), which flung every string ~300px when the
                -- user shifted to a very different scale and reopened.
                local frameTop = fr.GetTop and fr:GetTop()
                if sbL and frameTop then
                    local rankRel = fr.rank and fr.rank.GetPoint and select(2, fr.rank:GetPoint(1))
                    -- Anything the BAR hangs from (directly or up its anchor
                    -- chain) must not be aligned TO the bar: moving such a
                    -- string drags the bar with it and the constant gap
                    -- re-applies every pass -- the primaries' whole cluster
                    -- crept 1px left per open from exactly this loop.
                    local barChain = {}
                    do
                        local node = fr.statusBar
                        for _ = 1, 4 do
                            if not (node and node.GetPoint) then break end
                            local _, rel2 = node:GetPoint(1)
                            if not rel2 then break end
                            barChain[rel2] = true
                            node = rel2
                        end
                    end
                    local strings = {
                        { fs = fr.professionName, alignX = true,  drop = isPrimary and 20 or 0 },
                        { fs = fr.rank,           alignX = true,
                          drop = (isPrimary and rankRel ~= fr.statusBar) and -20 or 0 },
                        { fs = fr.missingHeader,  alignX = false, drop = 0 },
                    }
                    for _, s in ipairs(strings) do
                        local fs = s.fs
                        if fs and fs.GetLeft then
                            local l, t = fs:GetLeft(), fs:GetTop()
                            if l and t then
                                local td = GetFFD(fs)
                                -- Title capture sanity: the profession name
                                -- always sits ABOVE its bar. A capture taken
                                -- from a mid-relayout pass (name measured at
                                -- or below the bar) locks a bogus gap -- skip
                                -- capturing until a settled pass measures it
                                -- above the bar (the Archaeology tile hit
                                -- this).
                                if fs == fr.professionName and td.gapTop == nil
                                    and fr.statusBar and fr.statusBar.GetTop then
                                    local barTop = fr.statusBar:GetTop()
                                    if barTop and t <= barTop then
                                        l = nil -- stale measure; skip this pass
                                    end
                                end
                                -- Capture the string's default gap from the
                                -- frame top once (scale-invariant), then drive
                                -- to frameTop + gap - drop every pass.
                                if l and td.gapTop == nil then td.gapTop = t - frameTop end
                                local targetTop = td.gapTop and (frameTop + td.gapTop - s.drop)
                                if l and targetTop then
                                    -- WHOLE pixels only: rects are quantized
                                    -- but point offsets are continuous, so
                                    -- applying fractional residuals
                                    -- re-measured the same sub-pixel every
                                    -- pass and crept the whole anchored
                                    -- cluster ~1px left per open.
                                    local wantX = s.alignX and not barChain[fs]
                                    local dx = math.floor((wantX and (sbL - l) or 0) + 0.5)
                                    local dy = math.floor((targetTop - t) + 0.5)
                                    if dx ~= 0 or dy ~= 0 then
                                        local p, rel, rp, x, y = fs:GetPoint(1)
                                        if p then
                                            fs:ClearAllPoints()
                                            fs:SetPoint(p, rel, rp, (x or 0) + dx, (y or 0) + dy)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- Tile backdrop: dialog sheet art at half strength, padded past
            -- the frame so the content never crowds the card edges. Top pad
            -- stays small -- rows sit close together and a tall card overlaps
            -- the row above (the seam that cut through the Alchemy tile).
            if not gd.bg then
                local bg = fr:CreateTexture(nil, "BACKGROUND", nil, -6)
                bg:SetAtlas("Ui-Dialog-New-Background")
                -- Primary tiles are taller than their content: pinched card,
                -- with the bottom pulled up further now that the bar cluster
                -- rides 20px higher -- this is what keeps a visible gap
                -- between the two primary cards. Secondary rows instead get
                -- 6px extra card height above and below.
                local topY = isPrimary and -4 or 10
                local botY = isPrimary and 6 or -16
                bg:SetPoint("TOPLEFT", fr, "TOPLEFT", -16, topY)
                bg:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 16, botY)
                bg:SetAlpha(0.5)
                gd.bg = bg
                gd.bgBottomY = botY
            end
            -- Secondary rows lay their rank bar BELOW the frame's own rect;
            -- drop the card bottom under the bar once geometry is readable.
            if gd.bg and not gd.bgFit then
                local fb = fr.GetBottom and fr:GetBottom()
                local bb = fr.statusBar and fr.statusBar.GetBottom and fr.statusBar:GetBottom()
                if fb then
                    gd.bgFit = true
                    if bb and bb < fb then
                        gd.bg:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 16, (bb - fb) - 16)
                    end
                end
            end
            if fr.professionName then WSkin.Font(fr.professionName); WSkin.White(fr.professionName) end
            if fr.missingHeader then WSkin.Font(fr.missingHeader); WSkin.White(fr.missingHeader) end
            if fr.rank then WSkin.Font(fr.rank); WSkin.White(fr.rank) end
            if fr.missingText then WSkin.Font(fr.missingText); WSkin.White(fr.missingText) end

            local ib = _G[n .. "IconBorder"]
            if ib and ib.SetAlpha then ib:SetAlpha(0) end
            if fr.icon then
                if fr.CircleMask and fr.icon.RemoveMaskTexture then
                    pcall(fr.icon.RemoveMaskTexture, fr.icon, fr.CircleMask)
                end
                if fr.icon.SetBlendMode then fr.icon:SetBlendMode("BLEND") end
                if fr.icon.SetDesaturated then fr.icon:SetDesaturated(false) end
                WSkin.SquareIcon(fr.icon, fr)
            end

            SkinProfSpellButton(fr.SpellButton1)
            SkinProfSpellButton(fr.SpellButton2)
        end
    end

    -- The two primary tiles' cards render at the same height: the frames can
    -- differ, so once both cards are measurable the shorter one's bottom
    -- extends by the difference (one-shot).
    local p1, p2 = _G.PrimaryProfession1, _G.PrimaryProfession2
    local d1, d2 = p1 and FFD[p1], p2 and FFD[p2]
    if d1 and d2 and d1.bg and d2.bg and not d1.eqDone then
        local h1, h2 = d1.bg:GetHeight(), d2.bg:GetHeight()
        if h1 and h2 and h1 > 0 and h2 > 0 then
            d1.eqDone = true
            if math.abs(h1 - h2) > 0.5 then
                local sd = (h1 < h2) and d1 or d2
                local sf = (h1 < h2) and p1 or p2
                -- Never extend past 2px below the frame -- an uncapped match
                -- ran the card into the next tile and ate the gap.
                sd.bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 16,
                    math.max((sd.bgBottomY or 6) - math.abs(h1 - h2), -2))
            end
        end
    end
end

local _profHook = false
local function Skin_ProfessionsBook()
    local f = _G.ProfessionsBookFrame
    if not f then return end
    WSkin.Shell("professionsbook", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.ProfessionsBookFrameBg then _G.ProfessionsBookFrameBg:SetAlpha(0) end
    for _, n in ipairs({ "ProfessionsBookPage1", "ProfessionsBookPage2" }) do
        local p = _G[n]
        if p and p.GetObjectType then
            if p:GetObjectType() == "Texture" then p:SetAlpha(0) else WSkin.FadeRegions(p) end
        end
    end
    for _, k in ipairs({ "Inset", "RightInset", "LeftInset" }) do
        if f[k] then WSkin.Inset(f[k]) end
    end
    WSkin.FadeKeyedArt(f)

    -- Info (help plate) button: seat it on the window's left edge, keeping
    -- its vertical spot -- same treatment as the Adventure Guide Traveler's
    -- Log. It has no parent key, so it is found by its help-i button art.
    -- Retries until the frame has been laid out.
    local function SeatProfHelp(host, depth)
        host = host or f
        depth = depth or 0
        if depth > 3 or not host.GetChildren then return end
        for i = 1, select("#", host:GetChildren()) do
            local c = select(i, host:GetChildren())
            if c and not WSkin.IsForeignFrame(c, host) and c.GetObjectType and c:GetObjectType() == "Button" then
                if not GetFFD(c).moved then
                    local nt = c.GetNormalTexture and c:GetNormalTexture()
                    local hay = nt and WSkin.TexHay(nt)
                    if hay and hay:find("help-i", 1, true) then
                        local top, fTop = c:GetTop(), f:GetTop()
                        if top and fTop then
                            GetFFD(c).moved = true
                            c:ClearAllPoints()
                            c:SetPoint("TOPLEFT", f, "TOPLEFT", 4, top - fTop)
                        end
                    end
                end
            elseif c then
                SeatProfHelp(c, depth + 1)
            end
        end
    end
    SeatProfHelp()

    RecolorProfessions()
    if not _profHook and type(_G.ProfessionsBookFrame_Update) == "function" then
        _profHook = true
        hooksecurefunc("ProfessionsBookFrame_Update", WSkin.Debounce(function()
            if f:IsVisible() then RecolorProfessions() end
        end))
    end

    WSkin.ButtonsIn(f)
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then RecolorProfessions(); SeatProfHelp(); WSkin.Restrip() end
    end))
end

WSkin.RegisterWindow({
    key = "professionsbook",
    addons = { Blizzard_ProfessionsBook = true },
    apply = Skin_ProfessionsBook,
})

-------------------------------------------------------------------------------
--  Archaeology (ArchaeologyFrame). Opened from the professions book, so it
--  rides the professionsbook style key. First-pass chrome: shell, close,
--  title, dropdown, keyed page art; page internals iterate later.
-------------------------------------------------------------------------------
local function Skin_Archaeology()
    local f = _G.ArchaeologyFrame
    if not f then return end
    WSkin.Shell("professionsbook", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.ArchaeologyFrameNineSlice then
        WSkin.FadeNineSlice(_G.ArchaeologyFrameNineSlice)
    end
    for _, g in ipairs({ "ArchaeologyFrameBg", "ArchaeologyFrameBgLeft",
                         "ArchaeologyFrameBgRight", "ArchaeologyFrameInset",
                         "ArchaeologyFrameportrait", "ArchaeologyFramePortrait" }) do
        local t = _G[g]
        if t then
            if t.IsObjectType and t:IsObjectType("Texture") then
                t:SetAlpha(0)
            elseif t.GetObjectType then
                if t.NineSlice then WSkin.FadeNineSlice(t.NineSlice) end
                WSkin.FadeRegions(t)
                WSkin.Register(t, true)
            end
        end
    end
    -- Old-template art lives all over the child tree: keyed bg pieces +
    -- keyword art (parchment/corner/frametexture family) both swept.
    WSkin.FadeKeyedArt(f)
    WSkin.FadeArtIn(f)
    -- Direct fontstrings on the frame and its pages: white (color-only;
    -- this is a profession-specific window, not the font-exempt book).
    WhitenTextIn(f)
    if f.CloseButton then WSkin.CloseButton(f.CloseButton) end
    if f.raceFilterDropdown then WSkin.Dropdown(f.raceFilterDropdown) end
    if f.RaceFilterDropdown then WSkin.Dropdown(f.RaceFilterDropdown) end
    for _, k in ipairs({ "summaryPage", "SummaryPage", "artifactPage",
                         "ArtifactPage", "completedPage", "CompletedPage",
                         "helpPage", "HelpPage" }) do
        local pg = f[k]
        if pg then
            WSkin.FadeKeyedArt(pg)
            WhitenTextIn(pg)
        end
    end
    -- Help page scroll text lives a level deeper than the page sweeps.
    local helpText = _G.ArchaeologyFrameHelpPageHelpScrollHelpText
    if helpText and helpText.SetTextColor then WSkin.White(helpText) end
    -- Page-nav arrows -> house page buttons (their old icon art faded).
    for _, base in ipairs({ "ArchaeologyFrameSummaryPage", "ArchaeologyFrameCompletedPage" }) do
        for suffix, ch in pairs({ PrevPageButton = "<", NextPageButton = ">" }) do
            local pb = _G[base .. suffix]
            if pb then
                WSkin.PageButton(pb, ch)
                -- These old buttons repaint their arrow art on every state
                -- change; sweep all non-house art per repaint, and clamp
                -- the icon's alpha against Blizzard's re-raises.
                local ic = _G[base .. suffix .. "Icon"]
                local function SweepArrowArt()
                    if ic and ic.SetAlpha then ic:SetAlpha(0) end
                    -- Spare OUR pieces by identity (the arrow path resolves
                    -- to a fileID later, so name matching is unreliable).
                    local own = GetFFD(pb)
                    for i = 1, select("#", pb:GetRegions()) do
                        local r = select(i, pb:GetRegions())
                        if r and r ~= own.arrow and r ~= own.bg and r ~= own.hover
                            and r.IsObjectType and r:IsObjectType("Texture")
                            and r:GetDrawLayer() ~= "HIGHLIGHT" then
                            r:SetAlpha(0)
                        end
                    end
                end
                SweepArrowArt()
                local pd = GetFFD(pb)
                if not pd.arrowHooks then
                    pd.arrowHooks = true
                    local function Deferred()
                        if C_Timer then
                            C_Timer.After(0, SweepArrowArt)
                        else
                            SweepArrowArt()
                        end
                    end
                    pb:HookScript("OnClick", Deferred)
                    pb:HookScript("OnEnable", Deferred)
                    pb:HookScript("OnDisable", Deferred)
                    pb:HookScript("OnShow", Deferred)
                    if ic and ic.SetAlpha then
                        hooksecurefunc(ic, "SetAlpha", function(_, a)
                            if pd.inIcAlpha then return end
                            if a and not issecretvalue(a) and a > 0 then
                                pd.inIcAlpha = true
                                ic:SetAlpha(0)
                                pd.inIcAlpha = false
                            end
                        end)
                    end
                end
            end
        end
    end
    -- Skill/rank bar -> full house bar: its chrome uses its own names
    -- (Background/Border + anonymous pieces), so fade everything that is
    -- not the fill, flatten the fill, and seat the house trough + border.
    local arb = f.rankBar or f.RankBar or _G.ArchaeologyFrameRankBar
    if arb then
        local abd = GetFFD(arb)
        for _, g in ipairs({ "ArchaeologyFrameRankBarBackground",
                             "ArchaeologyFrameRankBarBorder" }) do
            local t = _G[g]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        local fill = arb.GetStatusBarTexture and arb:GetStatusBarTexture()
        for i = 1, select("#", arb:GetRegions()) do
            local r = select(i, arb:GetRegions())
            if r and r ~= fill and r ~= abd.bg and r.IsObjectType
                and r:IsObjectType("Texture")
                and r:GetDrawLayer() ~= "HIGHLIGHT" then
                r:SetAlpha(0)
            end
        end
        if arb.SetStatusBarTexture then
            arb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            WSkin.ApplyBarFill(arb)
        end
        if not abd.bg then
            local trough = arb:CreateTexture(nil, "BACKGROUND", nil, -1)
            trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            trough:SetAllPoints(arb)
            abd.bg = trough
            WSkin.BorderRegion(arb, trough)
        end
        for i = 1, select("#", arb:GetRegions()) do
            local r = select(i, arb:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("FontString") then
                WSkin.White(r)
            end
        end
    end
    WSkin.ScrollBarsIn(f)
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then WSkin.Restrip() end
    end))
end

WSkin.RegisterWindow({
    key = "professionsbook",
    addons = { Blizzard_ArchaeologyUI = true },
    apply = Skin_Archaeology,
})

-------------------------------------------------------------------------------
--  Guild & Communities (CommunitiesFrame)
-------------------------------------------------------------------------------
-- Custom themed checkbox: Blizzard's atlas check art on these templates
-- resists the generic checkbox skin, so every texture region clears outright
-- and a 14px bordered box with an accent tick draws in its place, whitening
-- 10% while hovered or checked.
local function SkinGuildCheck(cb)
    if not cb or cb:IsForbidden() then return end
    local d = GetFFD(cb)
    if d.custom then return end
    d.custom = true
    for i = 1, select("#", cb:GetRegions()) do
        local r = select(i, cb:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetTexture then
            r:SetTexture("")
        end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture",
                         "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        local t = cb[g] and cb[g](cb)
        if t and t.SetTexture then t:SetTexture("") end
    end
    local boxF = CreateFrame("Frame", nil, cb)
    boxF:SetSize(14, 14)
    boxF:SetPoint("LEFT", cb, "LEFT", 4, 0)
    local fill = SolidTex(boxF, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fill:SetAllPoints(boxF)
    WSkin.AddBorder(boxF, 0.25, 0.25, 0.25, 1)
    local EG2 = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local tick = boxF:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(EG2.r or 0.047, EG2.g or 0.824, EG2.b or 0.616, 1)
    local wash = SolidTex(boxF, "ARTWORK", 1, 1, 1, 0.1)
    wash:SetAllPoints(boxF)
    wash:Hide()
    local hovering = false
    local function updState()
        local checked = cb:GetChecked() and true or false
        tick:SetShown(checked)
        wash:SetShown(hovering or checked)
    end
    cb:HookScript("OnEnter", function() hovering = true; updState() end)
    cb:HookScript("OnLeave", function() hovering = false; updState() end)
    cb:HookScript("OnClick", updState)
    hooksecurefunc(cb, "SetChecked", updState)
    updState()
    local lbl = cb.Text or (cb.GetFontString and cb:GetFontString())
    if lbl then WSkin.White(lbl) end
end

-- Max/Min glyph matching the transmog / dressing-room look: the quest-tracker
-- collapse/expand chevron (up = maximize/Expand, down = minimize/Collapse),
-- desaturated white at 0.75, brightening on hover.
local function CaretGlyph(btn, up)
    if not btn then return end
    local atlas = up and "UI-QuestTrackerButton-Secondary-Expand"
                      or "UI-QuestTrackerButton-Secondary-Collapse"
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then return end
    local d = GetFFD(btn)
    -- The glyph is a texture region on the button itself; keep it out of the
    -- region fade on re-runs.
    WSkin.FadeRegions(btn, d.caret and { [d.caret] = true } or nil)
    for _, m in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = btn[m] and btn[m](btn)
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    if not d.caret then
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetAtlas(atlas, false)
        t:SetSize(16, 16)
        t:SetPoint("CENTER", -2, 0)
        t:SetDesaturated(true)
        t:SetVertexColor(1, 1, 1, 0.75)
        d.caret = t
        btn:HookScript("OnEnter", function() t:SetVertexColor(1, 1, 1, 1) end)
        btn:HookScript("OnLeave", function() t:SetVertexColor(1, 1, 1, 0.75) end)
    end
end

-- Community list entry: flat block + accent selection. Blizzard repaints the
-- entry background per type, so this re-runs from the list update hook.
local function SkinCommunityEntry(entry)
    if not entry then return end
    -- Each entry reads as a defined tile: the same dialog-sheet card art the
    -- professions tiles use, at half strength, pulled in 2px top and bottom
    -- so neighbouring tiles never sit flush. The selection + hover washes
    -- clamp to the same card rect (the native regions run past it).
    -- extra: additional inset for the flat washes -- the card atlas bakes in
    -- soft transparent edges, so a wash on the same rect reads bigger than
    -- the visible art.
    local function CardRect(tex, extra)
        extra = extra or 0
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", entry, "TOPLEFT", extra, -2 - extra)
        tex:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", -extra, 2 + extra)
    end
    if entry.Background and entry.Background.SetAtlas then
        local tex = entry.Background
        local bgd = GetFFD(tex)
        -- Self-guarding card: Blizzard re-sets this texture per entry type
        -- from several paths (pooled entries carry mixin COPIES, so mixin
        -- table hooks miss them). Post-hooks on the texture object itself
        -- re-assert the card synchronously against every caller.
        if not bgd.guard then
            bgd.guard = true
            local function reapply()
                if bgd.inSet then return end
                bgd.inSet = true
                tex:SetAtlas("Ui-Dialog-New-Background")
                tex:SetTexCoord(0, 1, 0, 1)
                tex:SetVertexColor(1, 1, 1, 1)
                tex:SetAlpha(0.5)
                bgd.inSet = false
            end
            bgd.reapply = reapply
            hooksecurefunc(tex, "SetAtlas", reapply)
            hooksecurefunc(tex, "SetTexture", reapply)
            hooksecurefunc(tex, "SetAlpha", reapply)
        end
        bgd.reapply()
        CardRect(tex)
    end
    -- Selected entry = the same subtle white wash as the hover (never
    -- accent, and no brighter than hovering).
    if entry.Selection and entry.Selection.SetTexture then
        entry.Selection:SetTexture("Interface\\Buttons\\WHITE8X8")
        entry.Selection:SetVertexColor(1, 1, 1, 0.05)
        entry.Selection:SetTexCoord(0, 1, 0, 1)
        CardRect(entry.Selection, 3)
    end
    if entry.IconRing and entry.IconRing.SetAlpha then entry.IconRing:SetAlpha(0) end
    local hl = entry.GetHighlightTexture and entry:GetHighlightTexture()
    if hl and hl.SetTexture then
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.05)
        hl:SetTexCoord(0, 1, 0, 1)
        CardRect(hl, 3)
    end
end

-- Side tab (Chat/Roster/Benefits/Info): square the icon, drop the gold ring.
local function SquareTabIcon(tab)
    if not tab then return end
    local d = GetFFD(tab)
    local icon = tab.Icon
    local overlay = tab.IconOverlay
    if icon then
        WSkin.SquareIcon(icon)
        if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK") end
    end
    if tab.GetRegions then
        for i = 1, select("#", tab:GetRegions()) do
            local r = select(i, tab:GetRegions())
            if r and r ~= icon and r ~= overlay and r ~= d.hover and r.IsObjectType
               and r:IsObjectType("Texture") and r.SetAlpha then
                r:SetAlpha(0)
            end
        end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture" }) do
        local fn = tab[g]; local t = fn and fn(tab)
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
end

-- Guild dialog popouts (member detail, request-to-join): their chrome lives
-- in child FRAMES ("BG"/"Border" wrappers holding the bg + nine-slice), which
-- the keyed art sweeps cannot see -- flatten to a house panel.
local function SkinGuildPopup(pop)
    -- Frames only: some same-named globals are FUNCTIONS (the create-dialog
    -- name resolves to one in this client).
    if type(pop) ~= "table" or not pop.IsForbidden or pop:IsForbidden() then return end
    local d = GetFFD(pop)
    if d.popupSkinned then return end
    d.popupSkinned = true
    WSkin.FadeRegions(pop)
    if pop.NineSlice then WSkin.FadeNineSlice(pop.NineSlice) end
    for _, k in ipairs({ "BG", "Border" }) do
        local piece = pop[k]
        if piece then
            if piece.IsObjectType and piece:IsObjectType("Texture") then
                piece:SetAlpha(0)
            else
                WSkin.FadeRegions(piece)
                if piece.NineSlice then WSkin.FadeNineSlice(piece.NineSlice) end
                WSkin.Register(piece, true)
            end
        end
    end
    local bg = pop:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    bg:SetAllPoints(pop)
    d.bg = bg
    WSkin.AddBorder(pop)
    WSkin.Register(pop, true)
    if pop.CloseButton then WSkin.CloseButton(pop.CloseButton) end
    for i = 1, select("#", pop:GetRegions()) do
        local r = select(i, pop:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            WSkin.Font(r)
            WSkin.White(r)
        end
    end
end

-- Popup inputs get 6px of left padding: the BOX edge moves left (left-edge
-- anchors shift, or centered fixed-width boxes widen +6 and recenter), and a
-- matching text inset keeps the text's on-screen start unchanged.
local function PadPopupInput(eb)
    if not eb or not eb.GetNumPoints then return end
    local d = GetFFD(eb)
    if d.padLeft then return end
    local np = eb:GetNumPoints() or 0
    if np == 0 then return end
    local pts, ok, hasLeft = {}, true, false
    for i = 1, np do
        local p, rel, rp, x, y = eb:GetPoint(i)
        if not p then ok = false break end
        if p:find("LEFT", 1, true) then hasLeft = true end
        pts[i] = { p, rel, rp, x or 0, y or 0 }
    end
    if not ok then return end
    d.padLeft = true
    if hasLeft then
        for i = 1, #pts do
            if pts[i][1]:find("LEFT", 1, true) then
                pts[i][4] = pts[i][4] - 6
            end
        end
    else
        local w = eb:GetWidth()
        if w and w > 0 then eb:SetWidth(w + 6) end
        for i = 1, #pts do pts[i][4] = pts[i][4] - 3 end
    end
    eb:ClearAllPoints()
    for i = 1, #pts do
        local t = pts[i]
        eb:SetPoint(t[1], t[2], t[3], t[4], t[5])
    end
    if eb.GetTextInsets and eb.SetTextInsets then
        local l, r, t2, b = eb:GetTextInsets()
        eb:SetTextInsets((l or 0) + 6, r or 0, t2 or 0, b or 0)
    end
end
EllesmereUI._WSkinPadInput = PadPopupInput

local function PopupEditBox(eb)
    if not eb then return end
    WSkin.EditBox(eb)
    PadPopupInput(eb)
end

local _guildNewsHook = false
local function Skin_Guild()
    local f = _G.CommunitiesFrame
    if not f then return end
    WSkin.Shell("guild", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.PortraitOverlay then
        WSkin.FadeRegions(f.PortraitOverlay)
        if f.PortraitOverlay.SetAlpha then f.PortraitOverlay:SetAlpha(0) end
        WSkin.Register(f.PortraitOverlay, true)
    end
    if f.StreamDropdown then
        if f.StreamDropdown.NotificationOverlay then
            WSkin.FadeRegions(f.StreamDropdown.NotificationOverlay)
            f.StreamDropdown.NotificationOverlay:SetAlpha(0)
        end
        WSkin.Dropdown(f.StreamDropdown)
        -- Chat tab's stream picker: 10% smaller, seated 10px left (one-shot).
        local sdd = GetFFD(f.StreamDropdown)
        if not sdd.adjusted then
            sdd.adjusted = true
            f.StreamDropdown:SetScale(0.9)
            local p, rel, rp, x, y = f.StreamDropdown:GetPoint(1)
            if p then
                f.StreamDropdown:ClearAllPoints()
                f.StreamDropdown:SetPoint(p, rel, rp, (x or 0) - 10, y or 0)
            end
        end
    end
    -- Minimized view swaps the community-list sidebar for a dropdown; style it.
    if f.CommunitiesListDropdown then WSkin.Dropdown(f.CommunitiesListDropdown) end
    -- Side tabs, EJ-style plates without geometry fights: the dark box +
    -- black border anchor AROUND THE ICON (never the tab), so wherever
    -- Blizzard's display-mode layout seats the tab, the plate rides along --
    -- tab size, icon anchors, and the native tab chain are never touched.
    -- Only the root tab re-anchors, flush to the window edge; the others
    -- natively chain to it.
    for _, k in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        local tab = f[k]
        if tab and not tab:IsForbidden() then
            SquareTabIcon(tab)
            local icon = tab.Icon
            local td = GetFFD(tab)
            if icon and not td.box then
                local box = CreateFrame("Frame", nil, tab)
                box:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
                box:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
                box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 2))
                local fill = SolidTex(box, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                fill:SetAllPoints(box)
                WSkin.AddBorder(box, 0, 0, 0, 1)
                td.box = box
                td.bg = fill
                local hov = SolidTex(tab, "HIGHLIGHT", 1, 1, 1, 0.1)
                hov:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
                hov:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
                td.hover = hov
            end
            -- Tighter icon zoom than the standard crop (re-applied per pass;
            -- SquareTabIcon resets it to the 0.08 standard above).
            if icon and icon.SetTexCoord then icon:SetTexCoord(0.12, 0.88, 0.12, 0.88) end
            local enabled = not tab.IsEnabled or tab:IsEnabled()
            tab:SetAlpha(enabled and 1 or 0.5)
            -- Chain gap 10px tighter (one-shot): the native anchor to the
            -- previous tab is kept, only its y offset closes.
            if k ~= "ChatTab" and not td.gapAdj then
                local p, rel, rp, x, y = tab:GetPoint(1)
                if p then
                    td.gapAdj = true
                    tab:ClearAllPoints()
                    tab:SetPoint(p, rel, rp, x or 0, (y or 0) + 10)
                end
            end
        end
    end
    local chat = f.ChatTab
    if chat and not GetFFD(chat).rooted then
        GetFFD(chat).rooted = true
        chat:ClearAllPoints()
        chat:SetPoint("TOPLEFT", f, "TOPRIGHT", 1, -36)
    end

    -- Club finder (Guild Finder / Find a Community): the search input ships
    -- far taller than the search button; both become the same slim size,
    -- stacked input-over-button.
    for _, finder in ipairs({ _G.ClubFinderGuildFinderFrame, _G.ClubFinderCommunityAndGuildFinderFrame }) do
        if finder and finder.InsetFrame then WSkin.Inset(finder.InsetFrame) end
        -- Card pagers carry PreviousPage/NextPage keys -- names the generic
        -- paging sweep does not match.
        if finder then
            for _, ck in ipairs({ "GuildCards", "CommunityCards", "PendingGuildCards", "PendingCommunityCards" }) do
                local cards = finder[ck]
                if cards then
                    if cards.PreviousPage then WSkin.PageButton(cards.PreviousPage, "<", 13) end
                    if cards.NextPage then WSkin.PageButton(cards.NextPage, ">", 13) end
                end
            end
        end
        local ol = finder and finder.OptionsList
        if ol and ol.SearchBox and ol.Search then
            local od = GetFFD(ol)
            if not od.searchFit then
                od.searchFit = true
                ol.SearchBox:SetSize(118, 20)
                ol.Search:SetSize(120, 22)
            end
            -- Blizzard's options layout re-anchors these controls after us
            -- (one-shot moves never showed): both PIN their seats via
            -- synchronous SetPoint post-hooks. Box = Blizzard's base 10px
            -- left and 3px up (absolute captured set); button = stacked
            -- under the box.
            local sbx2 = ol.SearchBox
            local sd2 = GetFFD(sbx2)
            if not sd2.pinHooked then
                sd2.pinHooked = true
                local function capture()
                    local numPts = sbx2:GetNumPoints()
                    if not numPts or numPts == 0 then return false end
                    local pts = {}
                    for i = 1, numPts do
                        local p, rel, rp, x, y = sbx2:GetPoint(i)
                        if not p then return false end
                        pts[i] = { p, rel, rp, (x or 0) - 10, (y or 0) + 6 }
                    end
                    sd2.pin = pts
                    return true
                end
                local function reseat()
                    if not sd2.pin then return end
                    sd2.inPin = true
                    sbx2:ClearAllPoints()
                    for i = 1, #sd2.pin do
                        local t = sd2.pin[i]
                        sbx2:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                    sd2.inPin = false
                end
                if capture() then reseat() end
                hooksecurefunc(sbx2, "SetPoint", function()
                    if sd2.inPin then return end
                    if not sd2.pin then
                        if capture() then reseat() end
                    else
                        reseat()
                    end
                end)
            end
            local sBtn = ol.Search
            local bd2 = GetFFD(sBtn)
            if not bd2.pinHooked then
                bd2.pinHooked = true
                local function reseatBtn()
                    bd2.inPin = true
                    sBtn:ClearAllPoints()
                    sBtn:SetPoint("TOP", sbx2, "BOTTOM", 1, -3)
                    bd2.inPin = false
                end
                reseatBtn()
                hooksecurefunc(sBtn, "SetPoint", function()
                    if bd2.inPin then return end
                    reseatBtn()
                end)
            end
            -- Filter/sort dropdowns carry finder-specific keys the generic
            -- controls sweep does not match.
            if ol.ClubFilterDropdown then WSkin.Dropdown(ol.ClubFilterDropdown) end
            if ol.SortByDropdown then WSkin.Dropdown(ol.SortByDropdown) end
            if ol.ClubSizeDropdown then WSkin.Dropdown(ol.ClubSizeDropdown) end
            WSkin.EditBox(ol.SearchBox)
            WSkin.Button(ol.Search)
            local bfs = ol.Search.GetFontString and ol.Search:GetFontString()
            if bfs then WSkin.White(bfs) end
        end
        -- These views' top controls run 20px deeper than the chat view's
        -- band: a band extension parented to the FINDER (so it shows and
        -- hides with the view) with its own bottom separator, while the
        -- main band's separator hides so no line cuts mid-bar.
        -- Request-to-join dialog hangs off the finder; see SkinGuildPopup
        -- below for the member detail popout treatment.
        if finder and finder.RequestToJoinFrame then
            SkinGuildPopup(finder.RequestToJoinFrame)
        end
        if finder and not GetFFD(finder).bandExt then
            local fd2 = GetFFD(finder)
            fd2.bandExt = true
            -- The zone-band FFD entry on f (declared further down in this
            -- function; same table either way via GetFFD).
            local gz = GetFFD(f)
            local sbw = gz.sbw or 170
            local ext = finder:CreateTexture(nil, "BACKGROUND", nil, -4)
            ext:SetColorTexture(0, 0, 0, 0.10)
            ext:SetPoint("TOPLEFT", f, "TOPLEFT", sbw, -59)
            ext:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -59)
            ext:SetHeight(20)
            local extSep = finder:CreateTexture(nil, "ARTWORK")
            extSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            extSep:SetHeight(gz.sepPx or 1)
            extSep:SetPoint("BOTTOMLEFT", ext, "BOTTOMLEFT", 0, 0)
            extSep:SetPoint("BOTTOMRIGHT", ext, "BOTTOMRIGHT", 0, 0)
            finder:HookScript("OnShow", function()
                if gz.topSep then gz.topSep:Hide() end
            end)
            finder:HookScript("OnHide", function()
                local a2 = _G.ClubFinderGuildFinderFrame
                local b2 = _G.ClubFinderCommunityAndGuildFinderFrame
                if gz.topSep and not ((a2 and a2:IsShown()) or (b2 and b2:IsShown())) then
                    gz.topSep:Show()
                end
            end)
            if finder:IsShown() and gz.topSep then gz.topSep:Hide() end
        end
    end

    -- Zone bands laid out like the bags window (secondary top bar below the
    -- shell's 25px title bar, bottom bar, sidebar column + 1px separator),
    -- lightening with 3% white washes. All band art lives on OUR OWN child
    -- frame: as direct f regions, the shell's region fade wiped the bands on
    -- every re-skin pass (they never survived to be seen).
    local gzd = GetFFD(f)
    if not gzd.zoneBands then
        gzd.zoneBands = true
        -- Separator sizing: exactly one PHYSICAL pixel in this frame's own
        -- units, default pixel snapping. PP.mult is one physical pixel in
        -- UIParent units -- when the host's effective scale differs, the raw
        -- mult is slightly over a pixel here and snapping rounds the line
        -- onto two rows.
        local PPz = EllesmereUI.PanelPP
        local px = (PPz and PPz.mult) or 1
        do
            local es = f:GetEffectiveScale()
            local uiScale = UIParent and UIParent:GetScale() or 1
            if es and es > 0 and uiScale > 0 then
                px = px * uiScale / es
            end
        end
        local GUILD_SIDEBAR_W = 170   -- hardcoded sidebar column width
        local host = CreateFrame("Frame", nil, f)
        host:SetAllPoints(f)
        host:SetFrameLevel(f:GetFrameLevel())
        gzd.zoneHost = host
        -- Secondary top bar: starts AFTER the sidebar column (never over it).
        local topBand = host:CreateTexture(nil, "BACKGROUND")
        topBand:SetColorTexture(0, 0, 0, 0.10)
        topBand:SetPoint("TOPLEFT", f, "TOPLEFT", GUILD_SIDEBAR_W, -25)
        topBand:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -25)
        topBand:SetHeight(34)
        local topSep = host:CreateTexture(nil, "ARTWORK")
        topSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        topSep:SetHeight(px)
        topSep:SetPoint("BOTTOMLEFT", topBand, "BOTTOMLEFT", 0, 0)
        topSep:SetPoint("BOTTOMRIGHT", topBand, "BOTTOMRIGHT", 0, 0)
        gzd.topSep = topSep
        gzd.sbw = GUILD_SIDEBAR_W
        gzd.sepPx = px
        local botBand = host:CreateTexture(nil, "BACKGROUND")
        botBand:SetColorTexture(0, 0, 0, 0.10)
        botBand:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        botBand:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        botBand:SetHeight(30)
        local botSep = host:CreateTexture(nil, "ARTWORK")
        botSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        botSep:SetHeight(px)
        botSep:SetPoint("TOPLEFT", botBand, "TOPLEFT", 0, 0)
        botSep:SetPoint("TOPRIGHT", botBand, "TOPRIGHT", 0, 0)
        -- Sidebar wash + separator on OUR host with fixed geometry. Earlier
        -- these anchored to the list's ScrollBox, whose rect Blizzard
        -- rebuilds on view churn -- the art vanished whenever the box's
        -- anchors were momentarily invalid and popped back on relayout.
        -- Column: window left edge to GUILD_SIDEBAR_W, title bar to bottom
        -- band.
        local wash = host:CreateTexture(nil, "BACKGROUND")
        wash:SetColorTexture(0, 0, 0, 0.07)
        wash:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -25)
        wash:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", GUILD_SIDEBAR_W, 30)
        local sideSep = host:CreateTexture(nil, "ARTWORK")
        sideSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        sideSep:SetWidth(px)
        sideSep:SetPoint("TOPRIGHT", f, "TOPLEFT", GUILD_SIDEBAR_W, -25)
        sideSep:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", GUILD_SIDEBAR_W, 30)
    end

    -- Left community list: filigrees + bluemenu bg gone, flat entries.
    -- Cleared via SetTexture("") -- NOT alpha: Blizzard's list repaints
    -- re-raise this art after our show pass, which kept covering the
    -- sidebar wash until the next skin pass. A cleared texture file
    -- survives every repaint.
    local list = f.CommunitiesList or _G.CommunitiesFrameCommunitiesList
    if list then
        for _, k in ipairs({ "TopFiligree", "BottomFiligree", "Bg" }) do
            local t = list[k]
            if t and t.SetTexture then t:SetTexture("") end
        end
        if list.FilligreeOverlay then
            for i = 1, select("#", list.FilligreeOverlay:GetRegions()) do
                local r = select(i, list.FilligreeOverlay:GetRegions())
                if r and r.IsObjectType and r:IsObjectType("Texture") and r.SetTexture then
                    r:SetTexture("")
                end
            end
            list.FilligreeOverlay:SetAlpha(0)
        end
        if list.InsetFrame then WSkin.Inset(list.InsetFrame) end
        WSkin.FadeKeyedArt(list)
        -- Entries re-skin from the ENTRY MIXIN's own setters: Blizzard
        -- re-inits pooled entries through these on every toggle/list build
        -- (paths that never fire ScrollBox Update), which kept reverting the
        -- card art to Blizzard's.
        if _G.CommunitiesListEntryMixin and not GetFFD(list).entryHook then
            GetFFD(list).entryHook = true
            local function reskinEntry(entryFrame)
                if entryFrame and not (entryFrame.IsForbidden and entryFrame:IsForbidden()) then
                    SkinCommunityEntry(entryFrame)
                end
            end
            for _, m in ipairs({ "SetClubInfo", "SetAddCommunity", "SetFindCommunity", "SetGuildFinder" }) do
                if _G.CommunitiesListEntryMixin[m] then
                    hooksecurefunc(_G.CommunitiesListEntryMixin, m, reskinEntry)
                end
            end
        end
        local sb = list.ScrollBox
        if sb then
            if sb.ForEachFrame then pcall(sb.ForEachFrame, sb, SkinCommunityEntry) end
            if sb.Update and not GetFFD(sb).reHooked then
                GetFFD(sb).reHooked = true
                hooksecurefunc(sb, "Update", function()
                    if sb.ForEachFrame then pcall(sb.ForEachFrame, sb, SkinCommunityEntry) end
                end)
            end
        end
        -- Scrollbar flush with the sidebar's inner right edge (one-shot).
        local lsb = list.ScrollBar
        if lsb and not GetFFD(lsb).seated then
            GetFFD(lsb).seated = true
            lsb:ClearAllPoints()
            lsb:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -8)
            lsb:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 8)
        end
    end

    local chat = f.Chat
    if chat then
        local ci = chat.ChatInsetFrame or chat.InsetFrame
        if ci then WSkin.Inset(ci) end
    end
    -- Input skin ONLY -- all geometry meddling (slim, lift, pins) is
    -- reverted: after the pin experiments the input stopped rendering at
    -- all, so the box runs stock Blizzard geometry until proven visible
    -- again. Re-apply size tweaks incrementally from a working state.
    -- Blizzard re-raises the input's art on chat layout passes, so the art
    -- re-fades EVERY pass (our fill is protected) and the box registers for
    -- restrips.
    if f.ChatEditBox then
        local eb = f.ChatEditBox
        WSkin.EditBox(eb)
        local ebd = GetFFD(eb)
        local keep = {}
        if ebd.bg then keep[ebd.bg] = true end
        WSkin.FadeRegions(eb, keep)
        for _, k in ipairs({ "Left", "Right", "Middle", "Mid" }) do
            local r = eb[k]
            if r and r.SetAlpha then r:SetAlpha(0) end
        end
        WSkin.Register(eb, true)
        -- Height-only slim (safe; it was the position pin that lost the
        -- box). One-shot, no anchor writes.
        if not ebd.slimmed then
            local hh = eb:GetHeight()
            if hh and hh > 26 then
                ebd.slimmed = true
                eb:SetHeight(hh - 12)
            end
        end
    end

    local ml = f.MemberList
    if ml and ml.InsetFrame then WSkin.Inset(ml.InsetFrame) end
    -- "N/M Online" count above the roster: white.
    if ml and ml.MemberCount and ml.MemberCount.SetTextColor then
        WSkin.White(ml.MemberCount)
    end
    -- Member-list view dropdowns (guild + community variants): scaled-down
    -- with slightly smaller text, seated 8px lower (one-shot; label keeps
    -- its stock font size, the 0.85 scale is the only text shrink).
    for _, ddKey in ipairs({ "GuildMemberListDropdown", "CommunityMemberListDropdown" }) do
        local dd2 = f[ddKey]
        if dd2 then
            WSkin.Dropdown(dd2)
            local gdd = GetFFD(dd2)
            if not gdd.scaled then
                gdd.scaled = true
                dd2:SetScale(0.85)
                local p, rel, rp, x, y = dd2:GetPoint(1)
                if p then
                    dd2:ClearAllPoints()
                    dd2:SetPoint(p, rel, rp, x or 0, (y or 0) - 8)
                end
            end
        end
    end
    if ml and ml.ShowOfflineButton then SkinGuildCheck(ml.ShowOfflineButton) end
    SkinGuildPopup(f.GuildMemberDetailFrame)
    SkinGuildPopup(_G.CommunitiesAddDialog)
    SkinGuildPopup(_G.CommunitiesCreateCommunityDialog)
    -- Add/Create Community dialogs: their globals are NOT live frames at
    -- addon load (the real frame appears when the dialog first opens), so
    -- catch it from StaticPopupSpecial_Show, which receives the frame
    -- itself. The BG is a layout-KIT frame whose chrome pieces are not
    -- plain regions -- container alpha suppresses all of it at once.
    if type(_G.StaticPopupSpecial_Show) == "function" and not GetFFD(f).addDlgHook then
        GetFFD(f).addDlgHook = true
        local wanted = {
            CommunitiesAddDialog = true,
            CommunitiesCreateCommunityDialog = true,
        }
        hooksecurefunc("StaticPopupSpecial_Show", function(dlg)
            if type(dlg) ~= "table" or not dlg.GetName then return end
            local ok, nm2 = pcall(dlg.GetName, dlg)
            if not ok or not nm2 or not wanted[nm2] then return end
            SkinGuildPopup(dlg)
            local d2 = GetFFD(dlg)
            if dlg.BG and not d2.bgKilled then
                d2.bgKilled = true
                pcall(dlg.BG.SetAlpha, dlg.BG, 0)
            end
            for _, k in ipairs({ "InviteLinkBox", "NameEdit", "ShortNameEdit" }) do
                if dlg[k] then PopupEditBox(dlg[k]) end
            end
            if dlg.JoinButton then
                WSkin.Button(dlg.JoinButton)
                local jfs = dlg.JoinButton.Text
                    or (dlg.JoinButton.GetFontString and dlg.JoinButton:GetFontString())
                if jfs then WSkin.White(jfs) end
            end
        end)
    end
    -- Community settings dialog (name/description/MOTD editor).
    local csd = _G.CommunitiesSettingsDialog
    if csd and type(csd) == "table" and not GetFFD(csd).csdSkinned then
        GetFFD(csd).csdSkinned = true
        SkinGuildPopup(csd)
        for _, k in ipairs({ "Accept", "AcceptButton", "Cancel", "CancelButton",
                             "Delete", "DeleteButton", "ChangeAvatarButton" }) do
            local b = csd[k]
            if b and b.GetObjectType and b:GetObjectType() == "Button" then
                WSkin.Button(b)
                local bfs = b.GetFontString and b:GetFontString()
                if bfs then WSkin.White(bfs) end
            end
        end
        for _, k in ipairs({ "NameEdit", "ShortNameEdit" }) do
            if csd[k] then PopupEditBox(csd[k]) end
        end
        for _, k in ipairs({ "ClubFocusDropdown", "LookingForDropdown", "LanguageDropdown" }) do
            if csd[k] then WSkin.Dropdown(csd[k]) end
        end
        WSkin.ScrollBarsIn(csd)
    end
    -- Create/Edit Channel dialog. Its fill vanished because it is parented
    -- INSIDE CommunitiesFrame: the recursive art sweeps that strip the
    -- window's decorative Bg-family art reach every dialog living in the
    -- tree (standalone dialogs parented to UIParent are untouched). The
    -- house popup pass gives it our own backdrop.
    local esd = f.EditStreamDialog
    if esd and not GetFFD(esd).esdSkinned then
        GetFFD(esd).esdSkinned = true
        SkinGuildPopup(esd)
        for _, k in ipairs({ "Accept", "AcceptButton", "Cancel", "CancelButton",
                             "Delete", "DeleteButton" }) do
            local b = esd[k]
            if b and b.GetObjectType and b:GetObjectType() == "Button" then
                WSkin.Button(b)
                local bfs = b.GetFontString and b:GetFontString()
                if bfs then WSkin.White(bfs) end
            end
        end
        if esd.NameEdit then PopupEditBox(esd.NameEdit) end
        if esd.Description then PopupEditBox(esd.Description) end
        local modCheck = esd.TypeCheckBox or esd.ModeratorsOnlyCheckBox
            or esd.ModeratorsOnlyCheckbox
        if modCheck then SkinGuildCheck(modCheck) end
    end
    -- Notification settings dialog (chat bell): house popup + its extras.
    local nsd = f.NotificationSettingsDialog
    if nsd then
        SkinGuildPopup(nsd)
        if nsd.Selector then
            WSkin.FadeRegions(nsd.Selector)
            WSkin.Register(nsd.Selector, true)
            for _, k in ipairs({ "OkayButton", "AllButton", "NoneButton" }) do
                if nsd.Selector[k] then WSkin.Button(nsd.Selector[k]) end
            end
        end
        for _, k in ipairs({ "OkayButton", "AllButton", "NoneButton" }) do
            if nsd[k] then WSkin.Button(nsd[k]) end
        end
        if nsd.CommunitiesListDropdown then WSkin.Dropdown(nsd.CommunitiesListDropdown) end
        WSkin.ScrollBarsIn(nsd)
    end
    -- Ticket frame (community invite ticket pane): inset chrome off.
    local tkf = f.TicketFrame
    if tkf then
        WSkin.FadeRegions(tkf)
        WSkin.Register(tkf, true)
        if tkf.InsetFrame then
            WSkin.Inset(tkf.InsetFrame)
            if tkf.InsetFrame.NineSlice then
                WSkin.FadeNineSlice(tkf.InsetFrame.NineSlice)
            end
        end
        for _, k in ipairs({ "AcceptButton", "DeclineButton" }) do
            local b = tkf[k]
            if b then
                WSkin.Button(b)
                local bfs = b.GetFontString and b:GetFontString()
                if bfs then WSkin.White(bfs) end
            end
        end
    end
    -- Roster click-to-sort column headers: flat plates with white labels and
    -- the standard hover. Columns are pooled 3-slice buttons under the
    -- ColumnDisplay and rebuild per club/view, so the pass re-runs from the
    -- display's OnShow.
    local function SkinRosterColumns()
        local cd = ml and ml.ColumnDisplay
        if not cd then return end
        WSkin.FadeRegions(cd)
        WSkin.Register(cd, true)
        for i = 1, select("#", cd:GetChildren()) do
            local col = select(i, cd:GetChildren())
            if col and col.GetObjectType and col:GetObjectType() == "Button" then
                local d2 = GetFFD(col)
                if not d2.bg then
                    for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                        local t2 = col[k2]
                        if t2 and t2.SetTexture then t2:SetTexture("") end
                    end
                    WSkin.FadeRegions(col)
                    local bg2 = SolidTex(col, "BACKGROUND",
                        Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                    bg2:SetPoint("TOPLEFT", 1, -1)
                    bg2:SetPoint("BOTTOMRIGHT", -1, 1)
                    d2.bg = bg2
                    local hov = SolidTex(col, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hov:SetAllPoints(col)
                    d2.hover = hov
                    WSkin.Register(col, true)
                end
                local fs2 = col.GetFontString and col:GetFontString()
                if fs2 then WSkin.White(fs2) end
            end
        end
    end
    SkinRosterColumns()
    -- Re-skin roster columns when Blizzard rebuilds them (per club / view change)
    -- via hooksecurefunc on the list refresh -- NOT a HookScript on the secure
    -- ColumnDisplay. A HookScript OnShow/OnHide on ColumnDisplay fires INSIDE the
    -- secure roster refresh that a protected guild action (SetNote /
    -- SetGuildRankOrder) triggers, tainting that action -> ADDON_ACTION_FORBIDDEN
    -- (root-caused by bisection; @Halt57/@woaw guild-note reports). hooksecurefunc
    -- post-hooks are taint-safe by design -- the pattern ElvUI uses here.
    if ml and ml.RefreshListDisplay and not GetFFD(ml).colRefreshHooked then
        GetFFD(ml).colRefreshHooked = true
        hooksecurefunc(ml, "RefreshListDisplay", WSkin.Debounce(SkinRosterColumns))
    end
    -- Member-name list rides up 2px (one-shot, every anchor preserved).
    local mlBox = ml and ml.ScrollBox
    if mlBox and not GetFFD(mlBox).lifted then
        local numPts = mlBox:GetNumPoints()
        if numPts and numPts > 0 then
            local pts, ok = {}, true
            for i = 1, numPts do
                local p, rel, rp, x, y = mlBox:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) + 2 }
            end
            if ok then
                GetFFD(mlBox).lifted = true
                mlBox:ClearAllPoints()
                for i = 1, #pts do
                    local t = pts[i]
                    mlBox:SetPoint(t[1], t[2], t[3], t[4], t[5])
                end
            end
        end
    end

    -- Roster-view widening, applied ONLY while the roster is up. The
    -- MemberList is SHARED with the chat view's narrow names column, where
    -- an unconditional widen overflowed the scrollbar and covered the chat
    -- input. The sort-header row exists only on the roster view, so its
    -- visibility gates the swap between the stock and widened anchor sets.
    local cd2 = ml and ml.ColumnDisplay
    local box2 = ml and ml.ScrollBox
    if cd2 and box2 and not GetFFD(cd2).widenGate then
        GetFFD(cd2).widenGate = true
        local function capturePts(part)
            local n2 = part:GetNumPoints()
            if not n2 or n2 == 0 then return nil end
            local pts2 = {}
            for i = 1, n2 do
                local p, rel, rp, x, y = part:GetPoint(i)
                if not p then return nil end
                pts2[i] = { p, rel, rp, x or 0, y or 0 }
            end
            return pts2
        end
        local function widePts(pts2, dl, dr)
            local w2 = {}
            for i = 1, #pts2 do
                local t = pts2[i]
                local nx = t[4]
                if t[1]:find("LEFT", 1, true) then
                    nx = nx - dl
                elseif t[1]:find("RIGHT", 1, true) then
                    nx = nx + dr
                end
                w2[i] = { t[1], t[2], t[3], nx, t[5] }
            end
            return w2
        end
        local function applyPts(part, pts2)
            if not pts2 then return end
            part:ClearAllPoints()
            for i = 1, #pts2 do
                local t = pts2[i]
                part:SetPoint(t[1], t[2], t[3], t[4], t[5])
            end
        end
        local boxStock = capturePts(box2)
        local cdStock = capturePts(cd2)
        local boxWide = boxStock and widePts(boxStock, 23, 20)
        local cdWide = cdStock and widePts(cdStock, 23, 23)
        -- Also widen `ml` (MemberList) itself at the source, since Blizzard's
        -- own row-sizing below (SetWidth(GetMemberList():GetWidth())) reads
        -- ml's width directly. RefreshLayout only ever gives `ml` a single
        -- positional anchor (not a LEFT+RIGHT pair like box2/cd2), so it's
        -- resized with a plain SetWidth rather than the capturePts/widePts
        -- anchor-nudge technique above. This works alongside the per-row
        -- SetWidth override below, not instead of it: the two are
        -- belt-and-braces, so rows stay correctly sized whether Blizzard's
        -- layout picks up the widened ml on its own or not.
        local mlStockWidth = ml:GetWidth()
        local mlWideWidth = mlStockWidth + 23 + 20
        -- Every roster row is sized by Blizzard to MemberList's own width
        -- (CommunitiesMemberListEntryMixin:SetExpanded -> SetWidth(GetMemberList()
        -- :GetWidth())), a frame this pass never touches -- only its ScrollBox
        -- and ColumnDisplay children get widened above. Left alone, rows stay
        -- stock width while the header grows, so each row's GuildInfo text
        -- (RIGHT-anchored to the row, -4) sits in a box that ends well short of
        -- the widened header -- the Achievement Points / M+ Rating value renders
        -- under the Note column instead of the far-right stat column. Re-stamp
        -- every live row to the ScrollBox's actual current width so it always
        -- matches. GuildInfo is also LEFT-justified in that box by default, so
        -- widening it alone never moves the visible text -- center it and nudge
        -- it left while the roster is showing, and put both back to Blizzard's
        -- stock LEFT/20/-4 layout when it's not, since MemberList/ScrollBox is
        -- shared with the Chat tab's narrower names column and a row must not
        -- stay stranded in the roster's styling after the swap.
        local GUILD_INFO_NUDGE = 20
        local function ApplyRowLayout(row)
            if not row then return end
            if row.SetWidth then row:SetWidth(box2:GetWidth()) end
            local gi = row.GuildInfo
            if gi and row.Note and gi.SetJustifyH and gi.ClearAllPoints then
                gi:ClearAllPoints()
                if cd2:IsShown() then
                    gi:SetJustifyH("CENTER")
                    gi:SetPoint("LEFT", row.Note, "RIGHT", 20 - GUILD_INFO_NUDGE, 0)
                    gi:SetPoint("RIGHT", row, "RIGHT", -4 - GUILD_INFO_NUDGE, 0)
                else
                    gi:SetJustifyH("LEFT")
                    gi:SetPoint("LEFT", row.Note, "RIGHT", 20, 0)
                    gi:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end
            end
        end
        -- Same uninitialized-ScrollBox guard used for the AH summary/rail rows
        -- elsewhere in this file: ForEachFrame errors inside Blizzard's code
        -- if the view doesn't exist yet (e.g. this pass runs at ADDON_LOADED,
        -- before the roster has ever been shown).
        --
        -- box2:ForEachFrame walks Blizzard's secure row pool internally; a
        -- hooksecurefunc post-hook only guarantees Blizzard won't block the
        -- *call*, not that we've left the secure chain that triggered the
        -- Update (guild-frame open, tab switch) -- calling ForEachFrame here
        -- still runs nested inside it and taints later secret-value reads on
        -- the roster (confirmed via bisection). So this only flags dirty; the
        -- OnUpdate watcher below applies it on its own tick, outside any
        -- secure call chain.
        local rowsDirty = false
        local function ApplyRowSync()
            if box2.ForEachFrame and box2.GetView and box2:GetView() then
                pcall(box2.ForEachFrame, box2, ApplyRowLayout)
            end
        end
        local function SyncRowWidths()
            rowsDirty = true
        end
        hooksecurefunc(box2, "Update", WSkin.Debounce(SyncRowWidths))
        -- Swap column widths on roster<->chat view change WITHOUT a HookScript
        -- on the secure ColumnDisplay (cd2): its OnShow/OnHide fires inside the
        -- secure roster refresh a protected guild action triggers, tainting
        -- SetNote / SetGuildRankOrder (the guild-note ADDON_ACTION_FORBIDDEN,
        -- root-caused via bisection). A self-driven throttled OnUpdate on OUR
        -- OWN frame polls cd2's shown state and applies the swap, so it never
        -- runs inside that secure execution. Idles when the window is closed.
        -- Row-width sync (above) rides the same OnUpdate for the same reason.
        if not GetFFD(cd2)._euiWidthWatcher then
            GetFFD(cd2)._euiWidthWatcher = true
            -- Parented to the window: the OnUpdate handler stops entirely
            -- while the guild window is closed (hidden parents don't tick).
            local watcher = CreateFrame("Frame", nil, f)
            local wasShown, acc = nil, 0
            watcher:SetScript("OnUpdate", function(_, elapsed)
                if f and not f:IsShown() then return end
                if rowsDirty then
                    rowsDirty = false
                    ApplyRowSync()
                end
                acc = acc + elapsed
                if acc < 0.1 then return end
                acc = 0
                local shown = cd2:IsShown()
                if shown == wasShown then return end
                wasShown = shown
                if shown then
                    applyPts(box2, boxWide); applyPts(cd2, cdWide); ml:SetWidth(mlWideWidth)
                else
                    applyPts(box2, boxStock); ml:SetWidth(mlStockWidth)
                end
                ApplyRowSync()
            end)
        end
        if cd2:IsShown() then
            applyPts(box2, boxWide)
            applyPts(cd2, cdWide)
            ml:SetWidth(mlWideWidth)
        else
            applyPts(box2, boxStock)
            ml:SetWidth(mlStockWidth)
        end
        SyncRowWidths()
    end

    -- Chat view's names-column scrollbar sits 5px right (one-shot, every
    -- anchor preserved).
    local mlSB = ml and ml.ScrollBar
    if mlSB and not GetFFD(mlSB).nudged then
        local numPts = mlSB:GetNumPoints()
        if numPts and numPts > 0 then
            local pts, ok = {}, true
            for i = 1, numPts do
                local p, rel, rp, x, y = mlSB:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, (x or 0) + 5, y or 0 }
            end
            if ok then
                GetFFD(mlSB).nudged = true
                mlSB:ClearAllPoints()
                for i = 1, #pts do
                    local t = pts[i]
                    mlSB:SetPoint(t[1], t[2], t[3], t[4], t[5])
                end
            end
        end
    end

    local mm = f.MaximizeMinimizeFrame
    if mm then
        CaretGlyph(mm.MaximizeButton, true)
        CaretGlyph(mm.MinimizeButton, false)
    end
    -- Zone bands (top/bottom/side bars + their 3 separator lines) belong to the
    -- full layout only -- there's no sidebar column or top/bottom bars in the
    -- minimized view. Hide the whole band host while minimized (the Maximize
    -- button shows only when minimized), re-toggling on minimize/maximize.
    if gzd.zoneHost then
        local function UpdateZoneBands()
            local minimized = mm and mm.MaximizeButton and mm.MaximizeButton:IsShown()
            gzd.zoneHost:SetShown(not minimized)
        end
        UpdateZoneBands()
        if mm and not gzd.mmHook then
            gzd.mmHook = true
            for _, b in ipairs({ mm.MaximizeButton, mm.MinimizeButton }) do
                if b and b.HookScript then
                    b:HookScript("OnClick", function()
                        if C_Timer then C_Timer.After(0, UpdateZoneBands) else UpdateZoneBands() end
                    end)
                end
            end
        end
    end
    -- Raise the chat input 7px ONLY when minimized. Its stock position is
    -- view-dependent, so we can't capture a fixed original (it would bleed
    -- across views). Instead, add the offset relative to Blizzard's LIVE
    -- position: hook the box's SetPoint and re-apply +7 the next frame (once,
    -- after Blizzard finishes setting every point -- deferring avoids the
    -- multi-point compounding an immediate re-apply would cause). Reads
    -- Blizzard's just-set stock each time, so it never stacks.
    local eb = f.ChatEditBox
    if eb and mm and not GetFFD(eb).raiseHook then
        GetFFD(eb).raiseHook = true
        local applying, pending = false, false
        local function ApplyOffset()
            pending = false
            if not (mm.MaximizeButton and mm.MaximizeButton:IsShown()) then return end  -- maximized: leave stock
            local np = eb:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = eb:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) + 7 }
            end
            if ok then
                applying = true
                eb:ClearAllPoints()
                for i = 1, #pts do local t = pts[i]; eb:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                applying = false
            end
        end
        hooksecurefunc(eb, "SetPoint", function()
            if applying or pending then return end
            pending = true
            if C_Timer then C_Timer.After(0, ApplyOffset) else ApplyOffset() end
        end)
        -- Initial apply (box is at its stock position at load).
        pending = true
        if C_Timer then C_Timer.After(0, ApplyOffset) else ApplyOffset() end
    end

    -- Perks (Guild Benefits) tab: parchment inset borders + section art
    -- gone, section titles in the house font, slim scrollbars, flat rows,
    -- and the reputation bar as a flat accent fill on a dark trough.
    local gb = f.GuildBenefitsFrame
    if gb then
        for _, k in ipairs({ "InsetBorderLeft", "InsetBorderRight", "InsetBorderBottomRight",
                             "InsetBorderBottomLeft", "InsetBorderTopRight", "InsetBorderTopLeft",
                             "InsetBorderLeft2", "InsetBorderBottomLeft2", "InsetBorderTopLeft2" }) do
            local t = gb[k]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        local function SkinBenefitRow(row)
            if not row or row:IsForbidden() then return end
            local rd = GetFFD(row)
            if not rd.bg then
                local keep = {}
                if row.Icon then keep[row.Icon] = true end
                WSkin.FadeRegions(row, keep)
                local bg = row:CreateTexture(nil, "BACKGROUND", nil, -3)
                bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                bg:SetPoint("TOPLEFT", 1, -1)
                bg:SetPoint("BOTTOMRIGHT", -1, 1)
                rd.bg = bg
                WSkin.AddBorder(row)
                if row.Icon then WSkin.SquareIcon(row.Icon, row) end
                WSkin.Register(row, keep)
            end
            for i = 1, select("#", row:GetRegions()) do
                local r = select(i, row:GetRegions())
                if r and r.IsObjectType and r:IsObjectType("FontString") then
                    WSkin.Font(r)
                    WSkin.White(r)
                end
            end
        end
        for _, sec in ipairs({ gb.Perks, gb.Rewards }) do
            if sec then
                WSkin.FadeRegions(sec)
                WSkin.Register(sec, true)
                if sec.Bg and sec.Bg.SetAlpha then sec.Bg:SetAlpha(0) end
                if sec.TitleText then WSkin.Font(sec.TitleText); WSkin.White(sec.TitleText) end
                if sec.ScrollBar then WSkin.ScrollBar(sec.ScrollBar) end
                local sbx3 = sec.ScrollBox
                if sbx3 and sbx3.ForEachFrame then
                    pcall(sbx3.ForEachFrame, sbx3, SkinBenefitRow)
                    if sbx3.Update and not GetFFD(sbx3).rowHook then
                        GetFFD(sbx3).rowHook = true
                        hooksecurefunc(sbx3, "Update", function(box)
                            pcall(box.ForEachFrame, box, SkinBenefitRow)
                        end)
                    end
                end
            end
        end
        -- Reputation bar: the bar FRAME is taller than the visual fill, so
        -- the trough + border wrap the fill's measured vertical band at full
        -- width (the fill itself cannot be the anchor -- its width IS the
        -- progress). Retries from the pane's OnShow until laid out.
        local function FlattenRepBar()
            local rep = gb.FactionFrame and gb.FactionFrame.Bar
            if not rep or GetFFD(rep).flat then return end
            local prog = rep.Progress
            local rt, pt2 = rep:GetTop(), prog and prog:GetTop()
            local rb, pb = rep:GetBottom(), prog and prog:GetBottom()
            if not (rt and pt2 and rb and pb) then return end
            local bd3 = GetFFD(rep)
            bd3.flat = true
            for _, k in ipairs({ "Middle", "Right", "Left", "BG" }) do
                local t = rep[k]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            if rep.Shadow and rep.Shadow.SetAlpha then rep.Shadow:SetAlpha(0) end
            prog:SetTexture("Interface\\Buttons\\WHITE8X8")
            local fr2, fg2, fb2, fa2 = WSkin.BarFillColor()
            prog:SetVertexColor(fr2, fg2, fb2, fa2)
            local trough = rep:CreateTexture(nil, "BACKGROUND", nil, -1)
            trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            trough:SetPoint("TOPLEFT", rep, "TOPLEFT", 0, -(rt - pt2))
            trough:SetPoint("BOTTOMRIGHT", rep, "BOTTOMRIGHT", 0, pb - rb)
            bd3.bg = trough
            WSkin.BorderRegion(rep, trough)
            -- "Guild Reputation" label + on-bar text in white house font.
            for _, host2 in ipairs({ gb.FactionFrame, rep }) do
                if host2 and host2.GetRegions then
                    for i = 1, select("#", host2:GetRegions()) do
                        local r = select(i, host2:GetRegions())
                        if r and r.IsObjectType and r:IsObjectType("FontString") then
                            WSkin.Font(r)
                            WSkin.White(r)
                        end
                    end
                end
            end
        end
        FlattenRepBar()
        if not GetFFD(gb).repHook then
            GetFFD(gb).repHook = true
            gb:HookScript("OnShow", WSkin.Debounce(FlattenRepBar))
        end
    end

    -- Guild Info tab: inset borders + parchment gone, section titles in the
    -- house font, slim scrollbars, themed news-filter popout + checkboxes,
    -- and the per-row news header strips cleared as rows populate.
    local gdet = _G.CommunitiesFrameGuildDetailsFrame
    if gdet then
        for _, k in ipairs({ "InsetBorderLeft", "InsetBorderRight", "InsetBorderBottomRight",
                             "InsetBorderBottomLeft", "InsetBorderTopRight", "InsetBorderTopLeft",
                             "InsetBorderLeft2", "InsetBorderBottomLeft2", "InsetBorderTopLeft2" }) do
            local t = gdet[k]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
    end
    -- "View Log" button: white label, 2px smaller.
    local logBtn = f.GuildLogButton
    if logBtn then
        local lfs = logBtn.GetFontString and logBtn:GetFontString()
        if lfs then
            WSkin.White(lfs)
            local ld = GetFFD(lfs)
            if not ld.shrunk then
                local pth, sz, fl = lfs:GetFont()
                if pth and sz then
                    ld.shrunk = true
                    lfs:SetFont(pth, sz - 2, fl)
                end
            end
        end
    end
    -- Guild log popup (old-style dialog: named Bg/corner pieces, corner X
    -- "<name>Close", bottom text button "<name>CloseButton", old scrollbar).
    local function SkinGuildLog()
        local gl = _G.CommunitiesGuildLogFrame
        if not gl or type(gl) ~= "table" or GetFFD(gl).logSkinned then return end
        GetFFD(gl).logSkinned = true
        local n = (gl.GetName and gl:GetName()) or "CommunitiesGuildLogFrame"
        -- TWO buttons here can carry the CloseButton name (corner X + bottom
        -- text button; the global resolves to only one of them). Classify
        -- every button by label -- text -> house button, blank -> house X --
        -- BEFORE the popup pass so its own CloseButton call can't glyph the
        -- text button.
        local function TreatClose(cand)
            if not cand or type(cand) ~= "table" or not cand.GetObjectType then return end
            local cd = GetFFD(cand)
            if cd.closeTreated then return end
            cd.closeTreated = true
            local bfs = cand.GetFontString and cand:GetFontString()
            local btxt = bfs and bfs.GetText and bfs:GetText()
            if btxt and btxt ~= "" then
                WSkin.Button(cand)
                if bfs then WSkin.White(bfs) end
                -- Sentinel: blocks any later WSkin.CloseButton on this frame
                -- (its guard key). No hover hooks exist to read it.
                if not cd.x then cd.x = true end
            else
                WSkin.CloseButton(cand)
            end
        end
        TreatClose(gl.Close)
        TreatClose(gl.CloseButton)
        TreatClose(_G[n .. "Close"])
        TreatClose(_G[n .. "CloseButton"])
        for i = 1, select("#", gl:GetChildren()) do
            local ch = select(i, gl:GetChildren())
            if ch and not WSkin.IsForeignFrame(ch, gl)
               and ch.GetObjectType and ch:GetObjectType() == "Button" then
                TreatClose(ch)
            end
        end
        SkinGuildPopup(gl)
        -- Inner container carries its own NineSlice chrome.
        local cont = gl.Container
        if cont then
            WSkin.FadeRegions(cont)
            if cont.NineSlice then WSkin.FadeNineSlice(cont.NineSlice) end
            WSkin.Register(cont, true)
        end
        local tt = gl.Title or gl.TitleText or _G[n .. "Title"] or _G[n .. "TitleText"]
        if tt and tt.SetTextColor then
            WSkin.Font(tt)
            WSkin.White(tt)
        end
        WSkin.ScrollBarsIn(gl)
        -- Old-style scrollbar: arrows faded, thumb -> 4px house strip.
        local sb = _G[n .. "ScrollFrameScrollBar"]
        if sb and not GetFFD(sb).slim then
            GetFFD(sb).slim = true
            local sbn = (sb.GetName and sb:GetName()) or ""
            for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
                local b = sb[suffix] or _G[sbn .. suffix]
                if b then
                    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                                         "GetDisabledTexture", "GetHighlightTexture" }) do
                        local t = b[g] and b[g](b)
                        if t and t.SetAlpha then t:SetAlpha(0) end
                    end
                end
            end
            local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
            if thumb then
                thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
                thumb:SetVertexColor(1, 1, 1, 0.3)
                thumb:SetWidth(4)
            end
        end
    end
    SkinGuildLog()
    if logBtn and not GetFFD(logBtn).logHook then
        GetFFD(logBtn).logHook = true
        logBtn:HookScript("OnClick", SkinGuildLog)
    end
    -- "Add to Chat" button: house caret + white label.
    local atc = f.AddToChatButton
    if atc and not GetFFD(atc).atcSkinned then
        GetFFD(atc).atcSkinned = true
        -- The label may be the fontstring, a Text key, or an anonymous
        -- region; collect them deduped, then white (color only, stock font
        -- kept) and seat 2px lower (one-shot, all anchors preserved).
        local labels = {}
        local afs = atc.GetFontString and atc:GetFontString()
        if afs then labels[afs] = true end
        if atc.Text and atc.Text.SetTextColor then labels[atc.Text] = true end
        for i = 1, select("#", atc:GetRegions()) do
            local r = select(i, atc:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("FontString") then
                labels[r] = true
            end
        end
        for fsr in pairs(labels) do
            WSkin.White(fsr)
            local ld = GetFFD(fsr)
            if not ld.dropped then
                local np = fsr:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = fsr:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) - 2 }
                end
                if ok then
                    ld.dropped = true
                    fsr:ClearAllPoints()
                    for i = 1, #pts do
                        local t = pts[i]
                        fsr:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                end
            end
        end
        local arrow = atc.Arrow
        if arrow then
            local tex = arrow
            if arrow.IsObjectType and not arrow:IsObjectType("Texture") then
                tex = nil
                if arrow.GetRegions then
                    for i = 1, select("#", arrow:GetRegions()) do
                        local r = select(i, arrow:GetRegions())
                        if r and r.IsObjectType and r:IsObjectType("Texture") then
                            tex = r
                            break
                        end
                    end
                end
            end
            if tex and tex.SetAtlas then
                -- Blizzard repaints the arrow on hover/press state changes;
                -- self-guarding hooks keep the house caret in place.
                local td = GetFFD(tex)
                local function ApplyCaret()
                    if td.inSet then return end
                    td.inSet = true
                    tex:SetAtlas("Azerite-PointingArrow", false)
                    tex:SetSize(14, 10)
                    tex:SetVertexColor(1, 1, 1, 1)
                    td.inSet = false
                end
                if not td.hooked then
                    td.hooked = true
                    hooksecurefunc(tex, "SetAtlas", ApplyCaret)
                    hooksecurefunc(tex, "SetTexture", ApplyCaret)
                    hooksecurefunc(tex, "SetTexCoord", ApplyCaret)
                end
                ApplyCaret()
            end
        end
    end
    -- Settings + Invite buttons: white labels, 1px smaller text.
    local function SlimWhiteLabel(b)
        if not b then return end
        local lfs2 = b.GetFontString and b:GetFontString()
        if not lfs2 then return end
        WSkin.White(lfs2)
        local ld2 = GetFFD(lfs2)
        if not ld2.shrunk then
            local pth, sz, fl = lfs2:GetFont()
            if pth and sz then
                ld2.shrunk = true
                lfs2:SetFont(pth, sz - 1, fl)
            end
        end
    end
    SlimWhiteLabel(f.CommunitiesControlFrame and f.CommunitiesControlFrame.CommunitiesSettingsButton)
    SlimWhiteLabel(f.InviteButton)
    local infoFrame = _G.CommunitiesFrameGuildDetailsFrameInfo
    local newsFrame = _G.CommunitiesFrameGuildDetailsFrameNews
    for _, sub in ipairs({ infoFrame, newsFrame }) do
        if sub then
            -- Keep our own divider (stored as the pane's protected fill):
            -- this direct fade on re-skin passes was eating it -- Restrip
            -- honors the protect keys, but a plain FadeRegions does not.
            local keepSub = {}
            local sd4 = FFD[sub]
            if sd4 and sd4.fill then keepSub[sd4.fill] = true end
            WSkin.FadeRegions(sub, keepSub)
            WSkin.Register(sub, true)
            if sub.TitleText then WSkin.Font(sub.TitleText); WSkin.White(sub.TitleText) end
            if sub.ScrollBar then WSkin.ScrollBar(sub.ScrollBar) end
            if sub.DetailsFrame and sub.DetailsFrame.ScrollBar then
                WSkin.ScrollBar(sub.DetailsFrame.ScrollBar)
            end
        end
    end
    -- Info tab dividers: a vertical line between the info and news columns,
    -- and a horizontal line above the Guild Information section. The
    -- horizontal one is stored as the info pane's protected fill -- that
    -- pane is registered for restrips, which would fade an unprotected
    -- anonymous region.
    if gdet and infoFrame and newsFrame and not GetFFD(gdet).dividers then
        GetFFD(gdet).dividers = true
        local mid = gdet:CreateTexture(nil, "OVERLAY")
        mid:SetColorTexture(1, 1, 1, 0.15)
        mid:SetWidth(1)
        mid:SetPoint("TOP", newsFrame, "TOPLEFT", -7, -4)
        mid:SetPoint("BOTTOM", newsFrame, "BOTTOMLEFT", -7, 4)
        local above = infoFrame:CreateTexture(nil, "OVERLAY")
        above:SetColorTexture(1, 1, 1, 0.15)
        above:SetHeight(1)
        above:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 14, -194)
        above:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", -7, -194)
        GetFFD(infoFrame).fill = above
    end

    local filters = _G.CommunitiesGuildNewsFiltersFrame
    if filters and not GetFFD(filters).skinned then
        GetFFD(filters).skinned = true
        WSkin.Panel(filters)
        local fcb = filters.CloseButton or _G.CommunitiesGuildNewsFiltersFrameCloseButton
        if fcb then WSkin.CloseButton(fcb) end
        for _, k in ipairs({ "GuildAchievement", "Achievement", "DungeonEncounter",
                             "EpicItemLooted", "EpicItemCrafted", "EpicItemPurchased",
                             "LegendaryItemLooted" }) do
            if filters[k] then SkinGuildCheck(filters[k]) end
        end
    end
    if type(_G.GuildNewsButton_SetNews) == "function" and not _guildNewsHook then
        _guildNewsHook = true
        hooksecurefunc("GuildNewsButton_SetNews", function(button)
            if button and button.header and button.header.SetAlpha then
                button.header:SetAlpha(0)
            end
        end)
    end

    for _, k in ipairs({ "Inset", "LeftInset", "RightInset" }) do
        if f[k] then WSkin.Inset(f[k]) end
    end
    WSkin.FadeKeyedArt(f)
    WSkin.ButtonsIn(f)
    WSkin.ScrollBarsIn(f)
    WSkin.PagingIn(f)
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then Skin_Guild(); WSkin.Restrip(); WSkin.UpdateAllTabs() end
    end))
end

WSkin.RegisterWindow({
    key = "guild",
    addons = { Blizzard_Communities = true },
    apply = Skin_Guild,
})

-------------------------------------------------------------------------------
--  Calendar (CalendarFrame)
-------------------------------------------------------------------------------
local _calendarHook = false
local function SkinCalendarDays()
    for i = 1, 42 do
        local day = _G["CalendarDayButton" .. i]
        if day then
            local d = GetFFD(day)
            if not d.bg then
                if day.SetNormalTexture then day:SetNormalTexture("") end
                local nt = day.GetNormalTexture and day:GetNormalTexture()
                if nt then nt:SetAlpha(0) end
                local bg = day:CreateTexture(nil, "BACKGROUND", nil, -8)
                bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                bg:SetAllPoints(day)
                d.bg = bg
                WSkin.AddBorder(day)
            end
        end
    end
end

-- Shift a frame up by dyUp px, preserving EVERY anchor point (idempotent:
-- captured + re-applied once). Preserving all points avoids the width-collapse
-- trap a single-point reseat causes on multi-anchored frames.
local function CalReseat(frame, dyUp)
    if not frame then return end
    local d = GetFFD(frame)
    if d.reseated then return end
    local n = frame:GetNumPoints() or 0
    if n < 1 then return end
    local pts = {}
    for i = 1, n do
        local p, rel, rp, x, y = frame:GetPoint(i)
        if not p then return end
        pts[i] = { p, rel, rp, x or 0, (y or 0) + dyUp }
    end
    d.reseated = true
    frame:ClearAllPoints()
    for i = 1, #pts do local t = pts[i]; frame:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
end

local function Skin_Calendar()
    local f = _G.CalendarFrame
    if not f then return end
    WSkin.Shell("calendar", f)
    -- Drop the shell's black top-bar strip on the calendar (it clashes with the
    -- month header row) -- the shell stores it in the engine's own FFD.
    local ed = WSkin.FFD and WSkin.FFD[f]
    if ed and ed.topBar and ed.topBar.SetAlpha then ed.topBar:SetAlpha(0) end
    WSkin.CommonChrome(f, "Calendar")
    if _G.CalendarCloseButton then WSkin.CloseButton(_G.CalendarCloseButton) end
    if _G.CalendarPrevMonthButton then WSkin.PageButton(_G.CalendarPrevMonthButton, "<", 16) end
    if _G.CalendarNextMonthButton then WSkin.PageButton(_G.CalendarNextMonthButton, ">", 16) end
    SkinCalendarDays()
    WSkin.ButtonsIn(f)
    WSkin.ScrollBarsIn(f)
    WSkin.FadeArtIn(f)

    -- Filter dropdown: left-align its "Filters" label, and shift it (and the
    -- close button) up 10px -- both were seated low against the shell top bar.
    if f.FilterButton then
        LeftAlignFilterLabel(f.FilterButton)
        CalReseat(f.FilterButton, 10)
    end
    if _G.CalendarCloseButton then CalReseat(_G.CalendarCloseButton, 10) end

    -- Holiday view popup (opens when a holiday event is clicked): style-aware
    -- shell backdrop (EllesmereUI atlas / Modern flat -- NOT a flat black
    -- panel), header art gone, no screen-dimming modal overlay, house close.
    local hf = _G.CalendarViewHolidayFrame
    if hf then
        local function SkinHoliday()
            WSkin.Shell("calendar", hf)
            if hf.Border and hf.Border.SetAlpha then hf.Border:SetAlpha(0) end
            if hf.Header then WSkin.FadeRegions(hf.Header) end
            local ov = _G.CalendarViewHolidayFrameModalOverlay
            if ov and ov.SetAlpha then ov:SetAlpha(0) end
            -- Header text: white, shifted down 5px (one-shot).
            local ht = hf.HeaderText or _G.CalendarViewHolidayFrameHeaderText
                or (hf.Header and hf.Header.Text)
            if ht then WSkin.Font(ht); WSkin.White(ht); CalReseat(ht, -5) end
            local cb = _G.CalendarViewHolidayCloseButton
            if cb then
                WSkin.CloseButton(cb)
                -- Nudge the house X glyph up 6px (one-shot).
                local xd = GetFFD(cb)
                if xd.x and not xd.xNudged then
                    xd.xNudged = true
                    xd.x:SetPoint("CENTER", -2, 6)
                end
            end
        end
        SkinHoliday()
        WSkin.HookShow(hf, WSkin.Debounce(SkinHoliday))
    end

    -- Create Event popup: STYLE-AWARE shell backdrop (was a flat WSkin.Panel --
    -- the reason it "did its own thing" vs the other calendar popups), 4
    -- time/type dropdowns, title + invite inputs, top-right close button, title
    -- nudged down 5px, class-icon column nudged right 3px, and the leftover
    -- Blizzard border sub-frame + divider hidden.
    local cef = _G.CalendarCreateEventFrame
    if cef then
        local function SkinCreateEvent()
            WSkin.Shell("calendar", cef)
            if cef.Header then WSkin.FadeRegions(cef.Header) end
            -- The two stray textures: the border sub-frame (Bg + edges, hidden
            -- via alpha inheritance) and the divider.
            if cef.Border and cef.Border.SetAlpha then cef.Border:SetAlpha(0) end
            if _G.CalendarCreateEventDivider and _G.CalendarCreateEventDivider.SetAlpha then
                _G.CalendarCreateEventDivider:SetAlpha(0)
            end
            -- Dropdowns (event type + hour/minute/AM-PM + difficulty when shown).
            for _, k in ipairs({ "EventTypeDropdown", "HourDropdown", "MinuteDropdown",
                                 "AMPMDropdown", "DifficultyOptionDropdown" }) do
                if cef[k] then WSkin.Dropdown(cef[k]) end
            end
            -- Inputs.
            if _G.CalendarCreateEventTitleEdit then WSkin.EditBox(_G.CalendarCreateEventTitleEdit) end
            if _G.CalendarCreateEventInviteEdit then WSkin.EditBox(_G.CalendarCreateEventInviteEdit) end
            -- Close button (top right): house X glyph nudged up 6px (one-shot).
            local cceCB = _G.CalendarCreateEventCloseButton
            if cceCB then
                WSkin.CloseButton(cceCB)
                local xd = GetFFD(cceCB)
                if xd.x and not xd.xNudged then
                    xd.xNudged = true
                    xd.x:SetPoint("CENTER", -2, 6)
                end
            end
            -- Action buttons + lock checkbox.
            for _, k in ipairs({ "CalendarCreateEventCreateButton", "CalendarCreateEventMassInviteButton",
                                 "CalendarCreateEventInviteButton", "CalendarCreateEventRaidInviteButton" }) do
                if _G[k] then WSkin.Button(_G[k]) end
            end
            -- borderInset 4 so the border hugs the visible box (the frame is
            -- larger than its check graphic) instead of sitting proud of it.
            if _G.CalendarCreateEventLockEventCheck then
                WSkin.Checkbox(_G.CalendarCreateEventLockEventCheck, { borderInset = 4 })
            end
            local il = _G.CalendarCreateEventInviteList
            if il and il.ScrollBar then WSkin.ScrollBar(il.ScrollBar) end
            -- Title down 5px (find the header's title FontString).
            local titleFS = (cef.Header and cef.Header.Text) or _G.CalendarCreateEventTitle
            if not titleFS and cef.Header and cef.Header.GetRegions then
                for i = 1, select("#", cef.Header:GetRegions()) do
                    local r = select(i, cef.Header:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then titleFS = r; break end
                end
            end
            if titleFS then CalReseat(titleFS, -5) end
            -- Class-icon column: button 1 anchors to the container and the rest
            -- chain off it, so nudging the container right 3px shifts the whole
            -- column (one-shot, all anchor points preserved).
            local ccc = _G.CalendarClassButtonContainer
            if ccc and not GetFFD(ccc).nudgedRight then
                local np = ccc:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = ccc:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, (x or 0) + 3, y or 0 }
                end
                if ok then
                    GetFFD(ccc).nudgedRight = true
                    ccc:ClearAllPoints()
                    for i = 1, #pts do local t = pts[i]; ccc:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                end
            end
        end
        SkinCreateEvent()
        WSkin.HookShow(cef, WSkin.Debounce(SkinCreateEvent))
    end

    -- Event picker popup (opens on a day with multiple events): style-aware
    -- shell backdrop, leftover Blizzard border + bottom button-bar texture +
    -- close-button border gone, house close button + scrollbar, title down 8px.
    local pf = _G.CalendarEventPickerFrame
    if pf then
        local function SkinEventPicker()
            WSkin.Shell("calendar", pf)
            if pf.Border and pf.Border.SetAlpha then pf.Border:SetAlpha(0) end
            for _, n in ipairs({ "CalendarEventPickerFrameButtonBackground",
                                 "CalendarEventPickerCloseButtonBorder" }) do
                local t = _G[n]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            if pf.Header then WSkin.FadeRegions(pf.Header) end
            -- This is a text "Close" button (bottom), NOT a corner X -- skin it
            -- as a plain button + white its label, so no stray X glyph is drawn.
            local pcb = _G.CalendarEventPickerCloseButton
            if pcb then
                WSkin.Button(pcb)
                local cfs = pcb.GetFontString and pcb:GetFontString()
                if cfs then WSkin.White(cfs) end
            end
            local sb = pf.ScrollBar or _G.CalendarEventPickerFrameScrollBar
                or (pf.ScrollBox and pf.ScrollBox.ScrollBar)
            if sb then WSkin.ScrollBar(sb) end
            -- Title down 8px (header title FontString).
            local titleFS = (pf.Header and pf.Header.Text) or _G.CalendarEventPickerFrameTitle or pf.Title
            if not titleFS and pf.Header and pf.Header.GetRegions then
                for i = 1, select("#", pf.Header:GetRegions()) do
                    local r = select(i, pf.Header:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then titleFS = r; break end
                end
            end
            if titleFS then CalReseat(titleFS, -8) end
        end
        SkinEventPicker()
        WSkin.HookShow(pf, WSkin.Debounce(SkinEventPicker))
    end

    if not _calendarHook and type(_G.CalendarFrame_Update) == "function" then
        _calendarHook = true
        hooksecurefunc("CalendarFrame_Update", WSkin.Debounce(function()
            if f:IsVisible() then SkinCalendarDays(); WSkin.Restrip() end
        end))
    end
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then SkinCalendarDays(); WSkin.Restrip() end
    end))
end

WSkin.RegisterWindow({
    key = "calendar",
    addons = { Blizzard_Calendar = true },
    apply = Skin_Calendar,
})

-------------------------------------------------------------------------------
--  Achievements (AchievementFrame)
-------------------------------------------------------------------------------
-- White house-font text on a frame's direct FontString regions.
local function AchWhiteTexts(host)
    if not host or not host.GetRegions then return end
    for i = 1, select("#", host:GetRegions()) do
        local r = select(i, host:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            WSkin.Font(r)
            WSkin.White(r)
        end
    end
end

local function AchWhiteTextsIn(host, depth)
    depth = depth or 0
    if not host or depth > 5 or host:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(host) then return end
    AchWhiteTexts(host)
    if not host.GetChildren then return end
    for i = 1, select("#", host:GetChildren()) do
        AchWhiteTextsIn(select(i, host:GetChildren()), depth + 1)
    end
end

-- Progress bar -> the flat accent bar (the professions-window look): cap and
-- trough art gone, accent fill, dark trough, 1px border, white labels.
local function AchAccentBar(bar)
    if not bar or bar:IsForbidden() then return end
    local d = GetFFD(bar)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill then d.fill = fill end
    local keep = {}
    if d.fill then keep[d.fill] = true end
    if d.bg then keep[d.bg] = true end
    WSkin.FadeRegions(bar, keep)
    WSkin.Register(bar, true)
    if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        WSkin.ApplyBarFill(bar)
    end
    if not d.bg then
        local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        bg:SetAllPoints(bar)
        d.bg = bg
        WSkin.AddBorder(bar)
    end
    local n = bar.GetName and bar:GetName()
    for _, key in ipairs({ "Title", "Label", "Text" }) do
        local fs = bar[key] or (n and _G[n .. key])
        if fs and fs.SetTextColor then
            WSkin.Font(fs)
            WSkin.White(fs)
            -- Sit the bar text 3px lower (one-shot), same as the professions
            -- bars -- the house font rides high on these.
            local rd = GetFFD(fs)
            if not rd.lowered then
                local p, rel, rp, x, y = fs:GetPoint(1)
                if p then
                    rd.lowered = true
                    fs:ClearAllPoints()
                    fs:SetPoint(p, rel, rp, x or 0, (y or 0) - 3)
                end
            end
        end
    end
end

-- Title tinted like the row art Blizzard ships (and this pack strips):
-- account-wide rows are the blue variant, character rows the gold parchment;
-- rows without a completion date render the dimmed take on the same hue.
local function AchTitleColor(row)
    local fs = row.Label
    if not fs or not fs.SetTextColor then return end
    local done = row.DateCompleted and row.DateCompleted.IsShown and row.DateCompleted:IsShown()
    if row.accountWide then
        if done then fs:SetTextColor(0.35, 0.75, 1) else fs:SetTextColor(0.24, 0.46, 0.6) end
    else
        if done then fs:SetTextColor(1, 0.85, 0.35) else fs:SetTextColor(0.64, 0.56, 0.3) end
    end
end

-- Hold a texture permanently invisible against Blizzard's re-raises: a SetAlpha
-- post-hook forces it back to 0 (reentry-guarded). A plain SetAlpha(0) is
-- reverted on the next row re-init (expand/select); a hooked one is not.
-- Taint-safe (hooksecurefunc only).
local function KillTex(t)
    if not t or not t.SetAlpha then return end
    t:SetAlpha(0)
    local td = GetFFD(t)
    if td.killed then return end
    td.killed = true
    hooksecurefunc(t, "SetAlpha", function(self)
        local dd = GetFFD(self)
        if dd.inKill then return end
        dd.inKill = true
        self:SetAlpha(0)
        dd.inKill = false
    end)
end

-- Lock a fontstring to the house font + a color, re-applied whenever Blizzard
-- swaps its font object or recolors it. The achievement list reverts BOTH the
-- font and the color on expand/select, so we re-assert both here. colorFn(fs)
-- applies the wanted color; nil = white. Taint-safe, one-time hooks per string.
local function LockAchText(fs, colorFn)
    if not fs or not fs.SetFont then return end
    local fd = GetFFD(fs)
    fd.colorFn = colorFn
    local function reapply()
        if fd.inLock then return end
        fd.inLock = true
        WSkin.Font(fs)
        if fd.colorFn then fd.colorFn(fs) else WSkin.White(fs) end
        fd.inLock = false
    end
    reapply()
    if not fd.textLocked then
        fd.textLocked = true
        if fs.SetFontObject then hooksecurefunc(fs, "SetFontObject", reapply) end
        hooksecurefunc(fs, "SetFont", reapply)
        if fs.SetTextColor then hooksecurefunc(fs, "SetTextColor", reapply) end
    end
end

-- Kill every Blizzard TEXTURE on the row (keyed + anon), sparing our own bg +
-- hover and all fontstrings. The NineSlice is a child frame (not a direct
-- region), so kill it whole -- alpha inherits to its Center + edge pieces.
local function KillAchRowArt(row, d)
    for i = 1, select("#", row:GetRegions()) do
        local r = select(i, row:GetRegions())
        if r and r ~= d.bg and r ~= d.hover and r.IsObjectType and r:IsObjectType("Texture") then
            KillTex(r)
        end
    end
    if row.NineSlice then KillTex(row.NineSlice) end
    if row.Icon and row.Icon.frame then KillTex(row.Icon.frame) end
    if row.Check then KillTex(row.Check) end
end

-- Achievement row (main list + summary list): parchment/glow art gone, flat
-- block + subtle hover, squared icon, white house-font text. The art + text are
-- LOCKED (KillTex / LockAchText) so Blizzard's re-init on expand/select can't
-- revert them -- the previous per-pass re-fade lost that race.
local function SkinAchRow(row)
    if not row or row:IsForbidden() then return end
    local d = GetFFD(row)
    if not d.bg then
        local bg = row:CreateTexture(nil, "BACKGROUND", nil, -3)
        bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
        d.bg = bg
        WSkin.AddBorder(row)
        local hov = SolidTex(row, "HIGHLIGHT", 1, 1, 1, 0.08)
        hov:SetAllPoints(row)
        d.hover = hov
        WSkin.Register(row, true)
        if row.Icon and row.Icon.texture then WSkin.SquareIcon(row.Icon.texture, row.Icon) end
        -- Text locks: Label keeps its per-state color, the rest go white.
        -- HiddenDescription is the FULL description swapped in on expand (the
        -- collapsed row shows the truncated Description) -- it reverted to
        -- Blizzard's font on click because it was never locked.
        LockAchText(row.Label, function() AchTitleColor(row) end)
        LockAchText(row.Description, nil)
        LockAchText(row.HiddenDescription, nil)
        LockAchText(row.DateCompleted, nil)
        if row.Shield and row.Shield.Points then LockAchText(row.Shield.Points, nil) end
        if row.DisplayObjectives then
            hooksecurefunc(row, "DisplayObjectives", function(rw)
                -- Expand rebuilds the row art; re-kill it + re-color the title
                -- (the completed state can flip on expand). Font/color locks
                -- hold the rest. Immediate + next frame for a deferred re-show.
                local rd = GetFFD(rw)
                KillAchRowArt(rw, rd)
                AchTitleColor(rw)
                if C_Timer then C_Timer.After(0, function()
                    KillAchRowArt(rw, rd); AchTitleColor(rw)
                end) end
                local ok, of = pcall(rw.GetObjectiveFrame, rw)
                if ok and of and of.progressBars then
                    for _, b in pairs(of.progressBars) do AchAccentBar(b) end
                end
            end)
        end
    end
    KillAchRowArt(row, d)
    AchTitleColor(row)
end

-- Category list row (left side): the clickable is the child's Button.
local function SkinCategoryRow(child)
    local btn = child and child.Button
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if not d.bg then
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
        bg:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
        d.bg = bg
        WSkin.AddBorder(btn)
        local hov = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
        hov:SetAllPoints(btn)
        d.hover = hov
        WSkin.Register(btn, true)
    end
    -- Pooled rows: re-fade the native art every pass (see SkinAchRow).
    if btn.Background and btn.Background.SetAlpha then btn.Background:SetAlpha(0) end
    local keep = {}
    if d.bg then keep[d.bg] = true end
    if d.hover then keep[d.hover] = true end
    WSkin.FadeRegions(btn, keep)
    if btn.Label then
        WSkin.White(btn.Label)
        -- Category labels sit low in the house font; raise 3px (one-shot).
        -- The label is pinned by BOTH edges -- every anchor must survive the
        -- shift, or the text collapses onto its remaining pin (it snapped
        -- right-aligned when only the first point was re-applied).
        local rd = GetFFD(btn.Label)
        if not rd.raised then
            local fsn = btn.Label
            local numPts = fsn:GetNumPoints()
            if numPts and numPts > 0 then
                local pts, ok = {}, true
                for i = 1, numPts do
                    local p, rel, rp, x, y = fsn:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) + 3 }
                end
                if ok then
                    rd.raised = true
                    fsn:ClearAllPoints()
                    for i = 1, #pts do
                        local t = pts[i]
                        fsn:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                end
            end
        end
    end
end

-- Statistics row: art gone, subtle hover, white text.
local function SkinStatRow(child)
    if not child or child:IsForbidden() then return end
    local d = GetFFD(child)
    if not d.statSkinned then
        d.statSkinned = true
        WSkin.FadeRegions(child)
        WSkin.Register(child, true)
        local hov = SolidTex(child, "HIGHLIGHT", 1, 1, 1, 0.08)
        hov:SetAllPoints(child)
        d.hover = hov
    end
    AchWhiteTexts(child)
end

-- Search result row (popout list): flat + hover, squared icon, white text.
local function SkinResultRow(child)
    if not child or child:IsForbidden() then return end
    local d = GetFFD(child)
    if not d.bg then
        local bg = child:CreateTexture(nil, "BACKGROUND", nil, -3)
        bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        bg:SetAllPoints(child)
        d.bg = bg
        local hov = SolidTex(child, "HIGHLIGHT", 1, 1, 1, 0.1)
        hov:SetAllPoints(child)
        d.hover = hov
        WSkin.Register(child, true)
        if child.Icon then WSkin.SquareIcon(child.Icon) end
    end
    -- Pooled rows: re-fade the native art every pass (see SkinAchRow).
    local keep = {}
    if d.bg then keep[d.bg] = true end
    if d.hover then keep[d.hover] = true end
    WSkin.FadeRegions(child, keep)
    AchWhiteTexts(child)
end

-- Search preview button (dropdown under the search box).
local function SkinPreviewBtn(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if not d.bg then
        local icon = btn.icon or btn.Icon
        local keep = icon and { [icon] = true } or nil
        WSkin.FadeRegions(btn, keep)
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
        bg:SetAllPoints(btn)
        d.bg = bg
        WSkin.AddBorder(btn)
        local hov = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
        hov:SetAllPoints(btn)
        d.hover = hov
        WSkin.Register(btn, keep or true)
        if icon then WSkin.SquareIcon(icon, btn) end
    end
    AchWhiteTexts(btn)
end

local _achSummaryHook = false
local _achCritHook = false
local function Skin_Achievements()
    local f = _G.AchievementFrame
    if not f then return end
    -- The frame rect extends above the visible panel (floating points header),
    -- so the shell skips its border to avoid a line across mid-air.
    WSkin.Shell("achievements", f, { noBorder = true })
    WSkin.CommonChrome(f, "AchievementFrame")

    -- Header banner: art gone, title + points in the house font on a flat
    -- plate. The plate anchors to the text so it resizes with the tab's
    -- title, and sits at a lower frame level so it draws under the strings.
    local host = f.Header or _G.AchievementFrameHeader
    if host then
        WSkin.FadeRegions(host)
        WSkin.Register(host, true)
        local title = host.Title or _G.AchievementFrameHeaderTitle
        local points = host.Points or _G.AchievementFrameHeaderPoints
        if title then WSkin.Font(title); WSkin.White(title) end
        if points then WSkin.Font(points); WSkin.White(points) end
        local hd = GetFFD(host)
        if not hd.plate and title and points then
            local plate = CreateFrame("Frame", nil, host)
            plate:SetFrameLevel(math.max(0, host:GetFrameLevel() - 1))
            plate:SetPoint("TOP", title, "TOP", 0, 9)
            plate:SetPoint("BOTTOM", points, "BOTTOM", 0, -9)
            plate:SetPoint("LEFT", title, "LEFT", -28, 0)
            plate:SetPoint("RIGHT", title, "RIGHT", 28, 0)
            local fill = SolidTex(plate, "BACKGROUND", 0, 0, 0, 1)
            fill:SetAllPoints(plate)
            hd.plateFill = fill
            WSkin.AddBorder(plate)
            hd.plate = plate
        end
    end
    -- Plate fill per style: eui = #070604 opaque; Modern = #050505 at the
    -- user's Modern backdrop opacity. Re-tinted on every show so style and
    -- opacity edits carry over.
    local function RetintHeaderPlate()
        local hd2 = host and FFD[host]
        local fillTex = hd2 and hd2.plateFill
        if not fillTex then return end
        if WSkin.GetStyle("achievements") == "modern" then
            local _, _, _, ma = WSkin.GetModernBG()
            fillTex:SetColorTexture(0.0196, 0.0196, 0.0196, ma or 1)
        else
            fillTex:SetColorTexture(0.0275, 0.0235, 0.0157, 1)
        end
    end
    RetintHeaderPlate()
    for _, name in ipairs({
        "AchievementFrameMetalBorderTop", "AchievementFrameMetalBorderBottom",
        "AchievementFrameMetalBorderLeft", "AchievementFrameMetalBorderRight",
        "AchievementFrameMetalBorderTopLeft", "AchievementFrameMetalBorderTopRight",
        "AchievementFrameMetalBorderBottomLeft", "AchievementFrameMetalBorderBottomRight",
        "AchievementFrameWoodBorderTopLeft", "AchievementFrameWoodBorderTopRight",
        "AchievementFrameWoodBorderBottomLeft", "AchievementFrameWoodBorderBottomRight",
        "AchievementFrameWaterMark", "AchievementFrameStatsBG" }) do
        local t = _G[name]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    for _, name in ipairs({ "AchievementFrameSummary", "AchievementFrameAchievements",
                            "AchievementFrameAchievementsContainer", "AchievementFrameCategories",
                            "AchievementFrameCategoriesContainer", "AchievementFrameStats",
                            "AchievementFrameComparison" }) do
        local sub = _G[name]
        if sub then WSkin.FadeRegions(sub); WSkin.Register(sub, true) end
    end
    -- Every list pane wraps its content in an anonymous inset child whose
    -- NineSlice is the box art (summary, stats, ...); fade any such child.
    -- Swept again on show: some panes only build theirs when first opened.
    local function SweepInsetChildren()
        for _, name in ipairs({ "AchievementFrameSummary", "AchievementFrameStats",
                                "AchievementFrameAchievements", "AchievementFrameCategories",
                                "AchievementFrameComparison" }) do
            local sub = _G[name]
            if sub then
                for i = 1, select("#", sub:GetChildren()) do
                    local c = select(i, sub:GetChildren())
                    if c and c.NineSlice and not WSkin.IsForeignFrame(c, sub) then
                        WSkin.FadeNineSlice(c.NineSlice)
                        WSkin.FadeRegions(c)
                        WSkin.Register(c, true)
                    end
                end
            end
        end
    end
    SweepInsetChildren()

    -- Search box: tucked into the top bar's right side at a sane width, with
    -- the filter dropdown seated to its left.
    local sbx = f.SearchBox
    if sbx then
        WSkin.EditBox(sbx)
        local sd = GetFFD(sbx)
        if not sd.moved then
            sd.moved = true
            sbx:ClearAllPoints()
            sbx:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -3)
            sbx:SetSize(150, 19)
        end
    end
    local filt = f.FilterDropdown or _G.AchievementFrameFilterDropdown
    if filt then
        WSkin.Dropdown(filt)
        local fd = GetFFD(filt)
        if not fd.moved then
            fd.moved = true
            filt:ClearAllPoints()
            filt:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -3)
        end
        -- Label pinned left (this dropdown only), clear of the arrow.
        local lab = filt.Text or (filt.GetFontString and filt:GetFontString())
        if lab and not fd.labLeft then
            fd.labLeft = true
            lab:ClearAllPoints()
            lab:SetPoint("LEFT", filt, "LEFT", 8, 0)
            lab:SetPoint("RIGHT", filt, "RIGHT", -22, 0)
            if lab.SetJustifyH then lab:SetJustifyH("LEFT") end
        end
    end

    -- Search preview popout + full results panel.
    local pv = f.SearchPreviewContainer
    if pv then
        WSkin.FadeRegions(pv)
        WSkin.Register(pv, true)
        for i = 1, 5 do SkinPreviewBtn(pv["SearchPreview" .. i]) end
        SkinPreviewBtn(pv.ShowAllSearchResults)
    end
    local sr = f.SearchResults
    if sr then
        WSkin.Panel(sr)
        local rb = sr.ScrollBox
        if rb and rb.ForEachFrame then
            pcall(rb.ForEachFrame, rb, SkinResultRow)
            if rb.Update and not GetFFD(rb).rowHook then
                GetFFD(rb).rowHook = true
                hooksecurefunc(rb, "Update", function(box) pcall(box.ForEachFrame, box, SkinResultRow) end)
            end
        end
    end

    local sweepOnTab = WSkin.Debounce(function()
        if f:IsVisible() then SweepInsetChildren(); WSkin.Restrip() end
    end)
    local achTabs = {}
    for i = 1, 3 do
        local t = _G["AchievementFrameTab" .. i]
        if t then
            WSkin.Tab(t)
            achTabs[#achTabs + 1] = t
            if not GetFFD(t).sweepHook then
                GetFFD(t).sweepHook = true
                t:HookScript("OnClick", sweepOnTab)
            end
        end
    end
    WSkin.NormalizeTabRow(achTabs)
    -- Comparison mode toggles tabs in this row (a hidden tab is skipped by
    -- the normalize pass, then Blizzard seats it with stock anchors when it
    -- shows -- landing on top of the tab our chain already put there).
    -- Re-chain the shown tabs synchronously whenever Blizzard moves or
    -- toggles any of them.
    do
        local fd = GetFFD(f)
        if not fd.tabNormHook then
            fd.tabNormHook = true
            local guard = false
            local function ReNorm()
                if guard then return end
                guard = true
                WSkin.NormalizeTabRow(achTabs)
                guard = false
            end
            for _, t in ipairs(achTabs) do
                hooksecurefunc(t, "SetPoint", ReNorm)
                t:HookScript("OnShow", ReNorm)
                t:HookScript("OnHide", ReNorm)
            end
        end
    end
    WSkin.ScrollBarsIn(f)

    -- List rows are ScrollBox-pooled; restyle realized rows on every list
    -- update (cost scales with visible rows only).
    local function HookRows(hostFrame, fn)
        local sb = hostFrame and hostFrame.ScrollBox
        if not (sb and sb.ForEachFrame) then return end
        pcall(sb.ForEachFrame, sb, fn)
        if sb.Update and not GetFFD(sb).rowHook then
            GetFFD(sb).rowHook = true
            hooksecurefunc(sb, "Update", function(box) pcall(box.ForEachFrame, box, fn) end)
        end
    end
    HookRows(_G.AchievementFrameCategories, SkinCategoryRow)
    HookRows(_G.AchievementFrameAchievements, SkinAchRow)
    HookRows(_G.AchievementFrameStats, SkinStatRow)

    -- Category sidebar sits 10px lower as a unit: shift its ScrollBox once,
    -- preserving every anchor (the box is corner-anchored, so both points
    -- carry the offset).
    local catBox = _G.AchievementFrameCategories and _G.AchievementFrameCategories.ScrollBox
    if catBox and not GetFFD(catBox).shifted then
        local numPts = catBox:GetNumPoints()
        if numPts and numPts > 0 then
            local pts, ok = {}, true
            for i = 1, numPts do
                local p, rel, rp, x, y = catBox:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 10 }
            end
            if ok then
                GetFFD(catBox).shifted = true
                catBox:ClearAllPoints()
                for i = 1, #pts do
                    local t = pts[i]
                    catBox:SetPoint(t[1], t[2], t[3], t[4], t[5])
                end
            end
        end
    end

    -- Achievement list (non-summary pages) sits 10px lower as a unit, same
    -- treatment as the sidebar: every anchor keeps its offset minus 10.
    local achBox = _G.AchievementFrameAchievements and _G.AchievementFrameAchievements.ScrollBox
    if achBox and not GetFFD(achBox).shifted then
        local numPts = achBox:GetNumPoints()
        if numPts and numPts > 0 then
            local pts, ok = {}, true
            for i = 1, numPts do
                local p, rel, rp, x, y = achBox:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 10 }
            end
            if ok then
                GetFFD(achBox).shifted = true
                achBox:ClearAllPoints()
                for i = 1, #pts do
                    local t = pts[i]
                    achBox:SetPoint(t[1], t[2], t[3], t[4], t[5])
                end
            end
        end
    end

    -- Summary page: heading strips to faint white, all summary text white in
    -- the house font, the recent-achievement cards through the row skin, and
    -- the 12 category bars + total bar as flat accent bars.
    for _, tn in ipairs({ "AchievementFrameSummaryAchievementsHeaderHeader",
                          "AchievementFrameSummaryCategoriesHeaderTexture" }) do
        local t = _G[tn]
        if t and t.SetVertexColor then t:SetVertexColor(1, 1, 1, 0.25) end
    end
    for i = 1, 12 do
        local bar = _G["AchievementFrameSummaryCategoriesCategory" .. i]
        if bar then
            AchAccentBar(bar)
            local hl = _G["AchievementFrameSummaryCategoriesCategory" .. i .. "ButtonHighlight"]
            if hl and hl.SetAlpha then hl:SetAlpha(0) end
        end
    end
    AchAccentBar(_G.AchievementFrameSummaryCategoriesStatusBar)
    if _G.AchievementFrameSummary then AchWhiteTextsIn(_G.AchievementFrameSummary) end
    if not _achSummaryHook and type(_G.AchievementFrameSummary_UpdateAchievements) == "function" then
        _achSummaryHook = true
        hooksecurefunc("AchievementFrameSummary_UpdateAchievements", WSkin.Debounce(function()
            local maxSum = _G.ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS or 4
            for i = 1, maxSum do SkinAchRow(_G["AchievementFrameSummaryAchievement" .. i]) end
        end))
    end

    -- Comparison view (Compare Achievements): header art gone, both summary
    -- bars as accent bars, the dual player/friend cards + stat rows through
    -- pooled-row skins, slim scrollbars.
    local comp = _G.AchievementFrameComparison
    if comp then
        for _, tn in ipairs({ "AchievementFrameComparisonHeaderBG",
                              "AchievementFrameComparisonHeaderPortrait",
                              "AchievementFrameComparisonHeaderPortraitBg" }) do
            local t = _G[tn]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        local compHdr = _G.AchievementFrameComparisonHeader
        if compHdr then
            WSkin.FadeRegions(compHdr)
            WSkin.Register(compHdr, true)
            AchWhiteTexts(compHdr)
        end
        -- Compared character's name sits in the top bar, left of the search
        -- box (one-shot).
        local compName = _G.AchievementFrameComparisonHeaderName
        if compName and f.SearchBox and not GetFFD(compName).moved then
            GetFFD(compName).moved = true
            compName:ClearAllPoints()
            compName:SetPoint("RIGHT", f.SearchBox, "LEFT", -10, 0)
        end
        -- Their points ride NEXT TO the name (not under it), in the user's
        -- link color -- retinted whenever Blizzard rewrites the value.
        local compPts = _G.AchievementFrameComparisonHeaderPoints
        if compPts and compName and not GetFFD(compPts).moved then
            GetFFD(compPts).moved = true
            compPts:ClearAllPoints()
            compPts:SetPoint("LEFT", compName, "RIGHT", 6, 0)
            local function TintComparePoints()
                local lr, lg, lb = WSkin.LinkColor()
                compPts:SetTextColor(lr, lg, lb)
            end
            TintComparePoints()
            hooksecurefunc(compPts, "SetText", TintComparePoints)
            if compPts.SetFormattedText then
                hooksecurefunc(compPts, "SetFormattedText", TintComparePoints)
            end
        end
        local function SkinCompareCard(card)
            if not card or card:IsForbidden() then return end
            local cdd = GetFFD(card)
            if not cdd.bg then
                local bg = card:CreateTexture(nil, "BACKGROUND", nil, -3)
                bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                bg:SetPoint("TOPLEFT", 1, -1)
                bg:SetPoint("BOTTOMRIGHT", -1, 1)
                cdd.bg = bg
                WSkin.AddBorder(card)
                WSkin.Register(card, true)
                if card.Icon and card.Icon.texture then
                    WSkin.SquareIcon(card.Icon.texture, card.Icon)
                end
            end
            -- Pooled: re-fade the native art + retint text every pass.
            for _, k in ipairs({ "Background", "TitleBar", "Glow", "Highlight" }) do
                local t = card[k]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            local keep = {}
            if cdd.bg then keep[cdd.bg] = true end
            WSkin.FadeRegions(card, keep)
            if card.Icon and card.Icon.frame and card.Icon.frame.SetAlpha then
                card.Icon.frame:SetAlpha(0)
            end
            AchWhiteTexts(card)
            for _, key in ipairs({ "Label", "Description", "DateCompleted" }) do
                local fs = card[key]
                if fs and fs.SetTextColor then WSkin.Font(fs); WSkin.White(fs) end
            end
        end
        local function SkinCompareRow(child)
            if not child then return end
            SkinCompareCard(child.Player)
            SkinCompareCard(child.Friend)
        end
        local ac = comp.AchievementContainer
        if ac then
            if ac.ScrollBar then WSkin.ScrollBar(ac.ScrollBar) end
            local box = ac.ScrollBox
            if box and box.ForEachFrame then
                pcall(box.ForEachFrame, box, SkinCompareRow)
                if box.Update and not GetFFD(box).rowHook then
                    GetFFD(box).rowHook = true
                    hooksecurefunc(box, "Update", function(b2)
                        pcall(b2.ForEachFrame, b2, SkinCompareRow)
                    end)
                end
            end
        end
        local sc = comp.StatContainer
        if sc then
            if sc.ScrollBar then WSkin.ScrollBar(sc.ScrollBar) end
            local box = sc.ScrollBox
            if box and box.ForEachFrame then
                pcall(box.ForEachFrame, box, SkinStatRow)
                if box.Update and not GetFFD(box).rowHook then
                    GetFFD(box).rowHook = true
                    hooksecurefunc(box, "Update", function(b2)
                        pcall(b2.ForEachFrame, b2, SkinStatRow)
                    end)
                end
            end
        end
        local summ = comp.Summary
        if summ then
            WSkin.FadeRegions(summ)
            WSkin.Register(summ, true)
            for _, side in ipairs({ summ.Player, summ.Friend }) do
                if side then
                    WSkin.FadeRegions(side)
                    WSkin.Register(side, true)
                    if side.StatusBar then AchAccentBar(side.StatusBar) end
                end
            end
        end
    end

    -- Criteria lines default to dark ink (parchment assumption); recolor on
    -- display: completed = white, incomplete = gray.
    if not _achCritHook and type(_G.AchievementObjectives_DisplayCriteria) == "function" then
        _achCritHook = true
        hooksecurefunc("AchievementObjectives_DisplayCriteria", function(of, id)
            if not (of and id) or (of.IsForbidden and of:IsForbidden()) then return end
            local num = GetAchievementNumCriteria and GetAchievementNumCriteria(id)
            if not num then return end
            local texts, metas = 0, 0
            local barFlag = _G.EVALUATION_TREE_FLAG_PROGRESS_BAR or 1
            for i = 1, num do
                local _, cType, completed, _, _, _, flags, assetID = GetAchievementCriteriaInfo(id, i)
                local fs
                if assetID and cType == _G.CRITERIA_TYPE_ACHIEVEMENT then
                    metas = metas + 1
                    local ok, m = pcall(of.GetMeta, of, metas)
                    fs = ok and m and m.Label
                elseif bit.band(flags or 0, barFlag) ~= barFlag then
                    texts = texts + 1
                    local ok, c = pcall(of.GetCriteria, of, texts)
                    fs = ok and c and c.Name
                end
                if fs and fs.SetTextColor then
                    -- Criteria lines are (re)created in Blizzard's font on
                    -- display; force the house font here too, not just color.
                    WSkin.Font(fs)
                    if completed then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.65, 0.65, 0.65) end
                end
            end
        end)
    end

    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then
            -- Re-run the realized-row passes: the first population can land
            -- before any ScrollBox Update our hooks see.
            HookRows(_G.AchievementFrameCategories, SkinCategoryRow)
            HookRows(_G.AchievementFrameAchievements, SkinAchRow)
            HookRows(_G.AchievementFrameStats, SkinStatRow)
            if _G.AchievementFrameSummary then AchWhiteTextsIn(_G.AchievementFrameSummary) end
            SweepInsetChildren()
            RetintHeaderPlate()
            WSkin.Restrip()
            WSkin.UpdateAllTabs()
        end
    end))
end

WSkin.RegisterWindow({
    key = "achievements",
    addons = { Blizzard_AchievementUI = true },
    apply = Skin_Achievements,
})

-------------------------------------------------------------------------------
--  Mail (MailFrame + OpenMailFrame)
-------------------------------------------------------------------------------
-- Square a mail ItemButton (letter/attachment slots).
-- Labeled prev/next page button (mail inbox, merchant): the house page-arrow
-- block, box shrunk 4px (the 13px arrow re-centers), shifted left 3px (+ any
-- per-button nudge), and the native "Prev"/"Next" label hidden -- it's a
-- font-string region on the button, not the designated GetFontString, so every
-- font string fades. Size/shift are one-shot; the label fade re-runs per pass.
local function SkinLabeledPageButton(btn, ch, extraX)
    if not btn then return end
    WSkin.PageButton(btn, ch, 13)
    local pd = GetFFD(btn)
    if not pd.adjusted then
        pd.adjusted = true
        local w, h = btn:GetSize()
        if w and h and w > 4 and h > 4 then btn:SetSize(w - 4, h - 4) end
        local np = btn:GetNumPoints() or 0
        local pts, ok = {}, np > 0
        for i = 1, np do
            local p, rel, rp, x, y = btn:GetPoint(i)
            if not p then ok = false break end
            pts[i] = { p, rel, rp, (x or 0) - 3 + (extraX or 0), y or 0 }
        end
        if ok then
            btn:ClearAllPoints()
            for i = 1, #pts do local t = pts[i]; btn:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
        end
    end
    -- Per-pass: hide the label font strings AND any plain texture regions
    -- (the merchant buttons carry their box art as anonymous regions, which
    -- PageButton's Normal/Pushed/Highlight fade never touches). Our own
    -- arrow/fill/hover are spared by identity.
    for i = 1, select("#", btn:GetRegions()) do
        local r = select(i, btn:GetRegions())
        if r and r ~= pd.arrow and r ~= pd.bg and r ~= pd.hover and r.IsObjectType
           and (r:IsObjectType("FontString") or r:IsObjectType("Texture")) then
            r:SetAlpha(0)
        end
    end
end

local function SkinMailItemButton(b)
    if not b or b:IsForbidden() then return end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt and nt.SetAlpha then nt:SetAlpha(0) end
    local bn = b.GetName and b:GetName()
    local slot = bn and _G[bn .. "Slot"]
    if slot and slot.SetAlpha then slot:SetAlpha(0) end
    -- IconBorder is the item-quality color ring -- leave it for Blizzard to
    -- manage (shown/colored per item rarity, hidden on common items).
    local icon = b.Icon or b.icon or (bn and _G[bn .. "IconTexture"])
    if icon then WSkin.SquareIcon(icon, b) end
end

-- Inbox row: parchment gone, flat block, white sender/subject, squared icon.
local function SkinMailRow(row)
    if not row or row:IsForbidden() then return end
    local d = GetFFD(row)
    if not d.bg then
        WSkin.FadeRegions(row)
        local bg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        bg:SetPoint("TOPLEFT", 2, -1)
        bg:SetPoint("BOTTOMRIGHT", -2, 3)
        d.bg = bg
        WSkin.AddBorder(row)
    end
    local name = row.GetName and row:GetName()
    if name then
        local sender = _G[name .. "Sender"]
        if sender then WSkin.Font(sender); WSkin.White(sender) end
        -- Subject is the item name for item mail -- font only so Blizzard's
        -- item-quality color shows (no forced white).
        local subject = _G[name .. "Subject"]
        if subject then WSkin.Font(subject) end
    end
    if row.Button then SkinMailItemButton(row.Button) end
end

-- Auction-house invoices and crafting-order mail don't use the letter body --
-- they're their own panels drawn in InvoiceTextFontNormal, a dark brown meant
-- to sit on the stationery parchment we fade out. Re-font and whiten them.
local INVOICE_TEXT = {
    "OpenMailInvoiceItemLabel", "OpenMailInvoicePurchaser", "OpenMailInvoiceSalePrice",
    "OpenMailInvoiceDeposit", "OpenMailInvoiceHouseCut", "OpenMailInvoiceAmountReceived",
    "OpenMailInvoiceNotYetSent", "OpenMailInvoiceMoneyDelay",
}
local CONSORTIUM_TEXT = {
    "OpeningText", "CrafterText", "CommissionReceived", "CrafterNote", "ConsortiumNote",
}
-- Only the money frames that declare an inline +/-/count font string; the
-- amounts themselves live on child frames (see SkinMoneyFrameText).
local INVOICE_MONEY = {
    "OpenMailDepositMoneyFrame", "OpenMailHouseCutMoneyFrame", "OpenMailSalePriceMoneyFrame",
}

local function SkinInvoiceFS(fs)
    if not fs or (fs.IsForbidden and fs:IsForbidden()) then return end
    WSkin.Font(fs)
    WSkin.White(fs)
end

-- The +/- arithmetic signs and the stack count are unnamed font strings
-- parented straight to the money frames; sweeping direct regions gets those and
-- nothing else. The amounts live on Gold/Silver/CopperButton children and are
-- driven by SetNormalFontObject, which SetMoneyFrameColor re-applies on every
-- update -- so they stay in Blizzard's number font (any SetFont here would be
-- clobbered), and, deliberately, so does the red on the house cut/commission.
local function SkinMoneyFrameText(mf)
    if not mf or mf:IsForbidden() then return end
    for i = 1, select("#", mf:GetRegions()) do
        local r = select(i, mf:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then SkinInvoiceFS(r) end
    end
end

-- The invoice's arithmetic rule is parchment art (a thin line inside a mostly
-- transparent 256x32 box) and AMOUNT_RECEIVED anchors to that box, so it can't
-- be recolored (a multiply keeps the orange) or turned into a color texture
-- (the whole box would fill, and resizing it would drag the anchor). Fade the
-- art, keep the box as an invisible spacer, and run our own rule through it.
local function SkinArithmeticLine()
    local art = _G.OpenMailArithmeticLine
    if not art or art:IsForbidden() then return end
    art:SetAlpha(0)
    local d = GetFFD(art)
    if d.rule then return end
    local parent = art:GetParent()
    if not parent then return end
    d.rule = SolidTex(parent, "OVERLAY", Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA)
    d.rule:SetHeight(1)
    d.rule:SetPoint("LEFT", art, "LEFT", 0, 0)
    d.rule:SetPoint("RIGHT", art, "RIGHT", 0, 0)
end

local function SkinInvoiceText()
    for _, n in ipairs(INVOICE_TEXT) do SkinInvoiceFS(_G[n]) end
    for _, n in ipairs(INVOICE_MONEY) do SkinMoneyFrameText(_G[n]) end
    SkinArithmeticLine()
    local cm = _G.ConsortiumMailFrame
    if not cm or cm:IsForbidden() then return end
    for _, k in ipairs(CONSORTIUM_TEXT) do SkinInvoiceFS(cm[k]) end
    local paid = cm.CommissionPaidDisplay
    if paid then
        SkinInvoiceFS(paid.CommissionPaidText)
        SkinMoneyFrameText(paid.MoneyDisplayFrame)
        -- Plain 1px color texture, so it themes in place. Matches the rule above.
        if paid.Separator then
            paid.Separator:SetColorTexture(Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA)
        end
    end
end

-- Letter body: force readable white + skin font on the SimpleHTML elements.
local function WhitenMailText()
    local html = _G.OpenMailBodyText
    if html and html.SetTextColor then
        local fp = Theme.fontPath
        local ff = Theme.fontFlag or ""
        for _, el in ipairs({ "P", "H1", "H2", "H3" }) do
            pcall(html.SetTextColor, html, el, 1, 1, 1)
            if fp and html.GetFont then
                local ok, _, sz = pcall(html.GetFont, html, el)
                if ok and sz and not issecretvalue(sz) then
                    pcall(html.SetFont, html, el, fp, sz, ff)
                end
            end
        end
    end
    if _G.OpenMailSubject then WSkin.Font(_G.OpenMailSubject); WSkin.White(_G.OpenMailSubject) end
    local sender = _G.OpenMailSender
    if sender and sender.Name then WSkin.Font(sender.Name); WSkin.White(sender.Name) end
    SkinInvoiceText()
end

local function Skin_OpenMail()
    local f = _G.OpenMailFrame
    if not f then return end
    WSkin.Shell("mail", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "OpenMailFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.OpenMailFrameBg then _G.OpenMailFrameBg:SetAlpha(0) end
    if f.Inset then WSkin.Inset(f.Inset) end
    WSkin.FadeKeyedArt(f)
    for _, n in ipairs({ "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight", "OpenMailHorizontalBarLeft" }) do
        local t = _G[n]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    for _, n in ipairs({ "OpenMailReplyButton", "OpenMailDeleteButton",
                         "OpenMailCancelButton", "OpenMailReportSpamButton" }) do
        local b = _G[n]
        if b then WSkin.Button(b) end
    end
    SkinMailItemButton(_G.OpenMailLetterButton)
    SkinMailItemButton(_G.OpenMailMoneyButton)
    for i = 1, 16 do SkinMailItemButton(_G["OpenMailAttachmentButton" .. i]) end
    WhitenMailText()
end

local _mailHook = false
local function Skin_Mail()
    local f = _G.MailFrame
    if not f then return end
    WSkin.Shell("mail", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "MailFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.MailFrameBg then _G.MailFrameBg:SetAlpha(0) end
    if f.Inset then WSkin.Inset(f.Inset) end

    -- Inbox
    if _G.InboxFrameBg then _G.InboxFrameBg:SetAlpha(0) end
    for i = 1, 7 do SkinMailRow(_G["MailItem" .. i]) end
    -- Raise the whole inbox item list: MailItem1 is the chain root (2-7 anchor
    -- below it), so lifting it lifts the list. One-shot capture + offset.
    local m1 = _G.MailItem1
    if m1 and not GetFFD(m1).raised then
        local np = m1:GetNumPoints() or 0
        local pts, ok = {}, np > 0
        for i = 1, np do
            local p, rel, rp, x, y = m1:GetPoint(i)
            if not p then ok = false break end
            pts[i] = { p, rel, rp, x or 0, (y or 0) + 20 }
        end
        if ok then
            GetFFD(m1).raised = true
            m1:ClearAllPoints()
            for i = 1, #pts do local t = pts[i]; m1:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
        end
    end
    if _G.OpenAllMail then WSkin.Button(_G.OpenAllMail); WSkin.WhiteButtonLabel(_G.OpenAllMail) end
    SkinLabeledPageButton(_G.InboxPrevPageButton, "<")
    SkinLabeledPageButton(_G.InboxNextPageButton, ">", 2)   -- right arrow 2px back to the right
    if _G.InboxCurrentPage then WSkin.Font(_G.InboxCurrentPage); WSkin.White(_G.InboxCurrentPage) end

    -- Send Mail
    if _G.SendMailNameEditBox then WSkin.EditBox(_G.SendMailNameEditBox) end
    if _G.SendMailSubjectEditBox then WSkin.EditBox(_G.SendMailSubjectEditBox) end
    if _G.SendMailFrame then WSkin.FadeRegions(_G.SendMailFrame); WSkin.Register(_G.SendMailFrame, true) end
    if _G.SendMailMoneyInset then WSkin.Inset(_G.SendMailMoneyInset) end
    if _G.SendMailMoneyBg then WSkin.FadeRegions(_G.SendMailMoneyBg); WSkin.Register(_G.SendMailMoneyBg, true) end
    if _G.SendMailMailButton then WSkin.Button(_G.SendMailMailButton) end
    if _G.SendMailCancelButton then WSkin.Button(_G.SendMailCancelButton) end
    for i = 1, 16 do
        local a = _G["SendMailAttachment" .. i]
        if a and not GetFFD(a).sock then
            local d = GetFFD(a)
            d.sock = true
            local nt = a.GetNormalTexture and a:GetNormalTexture()

            -- Fade every direct texture on the button. The SendMailAttachment
            -- button has a static placeholder texture (returned by the item API)
            -- plus a separate dynamic icon texture that Blizzard creates/updates
            -- when items are placed. Fading everything initially prevents the
            -- placeholder from clipping through; the hook below re-shows the
            -- actual icon when an item is dropped in.
            WSkin.FadeRegions(a)
            if nt and nt.SetAlpha then nt:SetAlpha(0) end
            if a.IconBorder then a.IconBorder:SetAlpha(0) end

            -- Background at a very low sublevel so it cannot cover the icon.
            local bg = a:CreateTexture(nil, "BACKGROUND", nil, -8)
            bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            bg:SetAllPoints(a)
            d.bg = bg
            WSkin.AddBorder(a)

            -- If the slot already contains an item when the frame is shown (e.g.
            -- reopening the mailbox), the icon texture exists at ARTWORK/OVERLAY
            -- with a real item texture. Re-show it here because the hook below
            -- only fires on later SetItemButtonTexture calls.
            local countFS = a.Count or (a.GetName and _G[a:GetName() .. "Count"])
            local countText = countFS and countFS.GetText and countFS:GetText()
            if countText and countText ~= "" and countText ~= "0" then
                for j = 1, select("#", a:GetRegions()) do
                    local r = select(j, a:GetRegions())
                    if r and r:IsObjectType("Texture") and r.GetDrawLayer and r.GetTexture then
                        local layer = ({r:GetDrawLayer()})[1]
                        if (layer == "ARTWORK" or layer == "OVERLAY") and r:GetTexture() then
                            r:SetAlpha(1)
                            r:Show()
                            if r.SetTexCoord then r:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                        end
                    end
                end
            end

            -- Hook SetItemButtonTexture: when an item is placed, find the region
            -- that actually received the item texture and show only that. When
            -- the slot is cleared, hide all icon textures again.
            if a.SetItemButtonTexture and not d.texHook then
                d.texHook = true
                hooksecurefunc(a, "SetItemButtonTexture", function(self, texture)
                    -- Our themed background is a direct region of this button;
                    -- the sweeps below must never fade it or the slot loses its
                    -- backdrop the first time an item is set or cleared.
                    if not texture then
                        for j = 1, select("#", self:GetRegions()) do
                            local r = select(j, self:GetRegions())
                            if r and r ~= d.bg and r:IsObjectType("Texture") then
                                r:SetAlpha(0)
                            end
                        end
                        return
                    end
                    for j = 1, select("#", self:GetRegions()) do
                        local r = select(j, self:GetRegions())
                        if r and r ~= d.bg and r:IsObjectType("Texture") then
                            local match = (r.GetTexture and r:GetTexture() == texture) or (r.GetAtlas and r:GetAtlas() == texture)
                            if match then
                                r:SetAlpha(1)
                                r:Show()
                                if r.SetTexCoord then r:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                            else
                                r:SetAlpha(0)
                            end
                        end
                    end
                end)
            end
        end
    end

    local mailTabs = {}
    for i = 1, 2 do
        local tab = _G["MailFrameTab" .. i]
        if tab then WSkin.Tab(tab); mailTabs[#mailTabs + 1] = tab end
    end
    WSkin.NormalizeTabRow(mailTabs)
    WSkin.ScrollBarsIn(f)

    if not _mailHook then
        _mailHook = true
        if type(_G.InboxFrame_Update) == "function" then
            hooksecurefunc("InboxFrame_Update", WSkin.Debounce(function()
                if f:IsVisible() then
                    for i = 1, 7 do SkinMailRow(_G["MailItem" .. i]) end
                    WSkin.Restrip()
                end
            end))
        end
        if type(_G.OpenMail_Update) == "function" then
            hooksecurefunc("OpenMail_Update", WSkin.Debounce(function()
                SkinMailItemButton(_G.OpenMailLetterButton)
                for i = 1, 16 do SkinMailItemButton(_G["OpenMailAttachmentButton" .. i]) end
                WhitenMailText()
            end))
        end
    end

    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then
            for i = 1, 7 do SkinMailRow(_G["MailItem" .. i]) end
            WSkin.Restrip()
            WSkin.UpdateAllTabs()
        end
    end))
    Skin_OpenMail()
end

WSkin.RegisterWindow({
    key = "mail",
    addons = { Blizzard_MailFrame = true },
    apply = Skin_Mail,
})

-------------------------------------------------------------------------------
--  Catalyst / Item Interaction (ItemInteractionFrame)
--  Chrome only: the input slot's green "+" is its NormalAtlas, so the item
--  slots stay stock.
-------------------------------------------------------------------------------
local function Skin_Catalyst()
    local f = _G.ItemInteractionFrame
    if not f then return end
    WSkin.Shell("catalyst", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "ItemInteractionFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Bg and f.Bg.SetAlpha then f.Bg:SetAlpha(0) end
    if _G.ItemInteractionFrameBg then _G.ItemInteractionFrameBg:SetAlpha(0) end
    if f.Inset then WSkin.Inset(f.Inset) end
    if f.Background and f.Background.SetAlpha then f.Background:SetAlpha(0) end
    if f.Description then WSkin.White(f.Description) end

    local bf = f.ButtonFrame
    if bf then
        for _, k in ipairs({ "BlackBorder", "ButtonBorder", "ButtonBottomBorder" }) do
            local t = bf[k]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        if bf.ActionButton then WSkin.Button(bf.ActionButton) end
        if bf.MoneyFrameEdge then WSkin.FadeRegions(bf.MoneyFrameEdge); WSkin.Register(bf.MoneyFrameEdge, true) end
    end
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then WSkin.Restrip() end
    end))
end

WSkin.RegisterWindow({
    key = "catalyst",
    addons = { Blizzard_ItemInteractionUI = true },
    apply = Skin_Catalyst,
})

-------------------------------------------------------------------------------
--  Gem Socketing (ItemSocketingFrame)
-------------------------------------------------------------------------------
local function SkinSocket(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    -- Lock detection runs every pass: lock state changes per inspected item,
    -- and LOCKED sockets keep ALL Blizzard art (the closed ring + padlock).
    local isLocked = false
    for i = 1, select("#", btn:GetRegions()) do
        local r = select(i, btn:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            local hay = WSkin.TexHay(r)
            if hay and hay:find("lock", 1, true) then isLocked = true break end
        end
    end
    local kids = {}
    for i = 1, select("#", btn:GetChildren()) do
        local c = select(i, btn:GetChildren())
        if c and c.SetAlpha then
            kids[#kids + 1] = c
            if not isLocked and c.GetRegions then
                for j = 1, select("#", c:GetRegions()) do
                    local r2 = select(j, c:GetRegions())
                    if r2 and r2.IsObjectType and r2:IsObjectType("Texture") then
                        local hay2 = WSkin.TexHay(r2)
                        if hay2 and hay2:find("lock", 1, true) then isLocked = true break end
                    end
                end
            end
        end
    end
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if isLocked then
        -- Un-stripped: the whole locked presentation (icon border art
        -- included) stays Blizzard's.
        for i = 1, select("#", btn:GetRegions()) do
            local r = select(i, btn:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(1) end
        end
        for _, c in ipairs(kids) do c:SetAlpha(1) end
        if nt and nt.SetAlpha then nt:SetAlpha(1) end
    else
        -- Blizzard's socket presentation stays whole (icon, ring, border,
        -- bracket art) -- only the decorative spark/shine CHILDREN dim; the
        -- house glow replaces them. Spared children: the bracket frame
        -- (border art) and any child carrying a fileID-backed texture (the
        -- gem holder -- decor art is atlas/path-based).
        for _, c in ipairs(kids) do
            local spare = (c == btn.BracketFrame)
            if not spare and c.GetRegions then
                for j = 1, select("#", c:GetRegions()) do
                    local r2 = select(j, c:GetRegions())
                    if r2 and r2.IsObjectType and r2:IsObjectType("Texture")
                        and not WSkin.TexHay(r2) then
                        local tx = r2.GetTexture and r2:GetTexture()
                        if type(tx) == "number" then
                            spare = true
                            break
                        end
                    end
                end
            end
            c:SetAlpha(spare and 1 or 0)
        end
    end
    -- The side filigree flourishes stay off in every state. Multi-piece and
    -- partly anonymous, so sweep by texture identity as well as the keys.
    for _, k in ipairs({ "LeftFiligree", "RightFiligree" }) do
        local t = btn[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    -- The flourish pieces are the only regions that overhang the button's
    -- sides; anything protruding past the edges fades (rects only exist
    -- while shown -- the update-pass re-runs catch it).
    local bl, br2 = btn:GetLeft(), btn:GetRight()
    if bl and br2 then
        for i = 1, select("#", btn:GetRegions()) do
            local r = select(i, btn:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                local rl, rr = r:GetLeft(), r:GetRight()
                if rl and rr and (rl < bl - 6 or rr > br2 + 6) then
                    r:SetAlpha(0)
                end
            end
        end
    end
    if d.sock then return end
    d.sock = true
    -- House Modern WoW glow (gold) on our own wrapper frame.
    if EllesmereUI.Glows and EllesmereUI.Glows.StartGlow then
        local gw = CreateFrame("Frame", nil, btn)
        local w2, h2 = btn:GetSize()
        if not w2 or w2 == 0 then w2, h2 = 36, 36 end
        gw:SetSize(w2, h2)
        gw:SetPoint("CENTER")
        EllesmereUI.Glows.StartGlow(gw, 6, w2, 1, 0.91, 0.5, nil, h2)
        d.glow = gw
    end
end


local function Skin_Socket()
    local f = _G.ItemSocketingFrame
    if not f then return end
    WSkin.Shell("socket", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "ItemSocketingFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.ItemSocketingFrameBg then _G.ItemSocketingFrameBg:SetAlpha(0) end
    if f.Inset then WSkin.Inset(f.Inset) end
    WSkin.FadeKeyedArt(f)
    WSkin.FadeArtIn(f)
    -- Tighter window: 40 narrower, 80 shorter than stock (one-shot).
    local fd5 = GetFFD(f)
    if not fd5.hCut then
        local ww, hh = f:GetSize()
        if ww and hh and hh > 140 and ww > 100 then
            fd5.hCut = true
            f:SetSize(ww - 40, hh - 80)
        end
    end
    -- Owned layout: a FIXED, scrollable tooltip viewport between the title
    -- bar and a dedicated gem section at the bottom (above the apply
    -- button). The tooltip text keeps its native scroll-child anchors; only
    -- the scrollframe and the gem container are positioned. Absolute
    -- anchors, re-applied on every update pass -- idempotent.
    local function LayoutSocketing()
        local sf2 = _G.ItemSocketingScrollFrame or f.ScrollFrame
        local c = f.SocketingContainer
        if sf2 then
            sf2:ClearAllPoints()
            sf2:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
            sf2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 100)
        end
        if c then
            c:ClearAllPoints()
            c:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
        end
        -- The SOCKETS anchor relative to the tooltip content, not the
        -- container -- moving the container alone left the gems mid-text.
        -- Keep Blizzard's horizontal arrangement (measured), own the
        -- vertical: bottoms pinned to the gem section. Re-measuring the
        -- x-delta each pass is idempotent.
        local fcx = f:GetCenter()
        if fcx and c then
            local sockets = { c.Socket1, c.Socket2, c.Socket3 }
            if c.SocketFrames then
                for _, s3 in ipairs(c.SocketFrames) do sockets[#sockets + 1] = s3 end
            end
            for _, s2 in ipairs(sockets) do
                if s2 and s2:IsShown() then
                    local scx = s2:GetCenter()
                    if scx then
                        s2:ClearAllPoints()
                        s2:SetPoint("BOTTOM", f, "BOTTOM", scx - fcx, 40)
                    end
                end
            end
        end
        -- Old-style scrollbar -> slim house strip (arrow buttons dark),
        -- seated 15px right of Blizzard's spot.
        local sbr = _G.ItemSocketingScrollFrameScrollBar or (sf2 and sf2.ScrollBar)
        if sbr and not GetFFD(sbr).slim then
            GetFFD(sbr).slim = true
            local numPts = sbr:GetNumPoints()
            if numPts and numPts > 0 then
                local pts, ok = {}, true
                for i = 1, numPts do
                    local p, rel, rp, x, y = sbr:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, (x or 0) + 15, y or 0 }
                end
                if ok then
                    sbr:ClearAllPoints()
                    for i = 1, #pts do
                        local t = pts[i]
                        sbr:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                end
            end
            local sbrName = sbr.GetName and sbr:GetName() or ""
            for _, b in ipairs({ sbr.ScrollUpButton or _G[sbrName .. "ScrollUpButton"],
                                 sbr.ScrollDownButton or _G[sbrName .. "ScrollDownButton"] }) do
                if b then
                    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                                         "GetDisabledTexture", "GetHighlightTexture" }) do
                        local t = b[g] and b[g](b)
                        if t and t.SetAlpha then t:SetAlpha(0) end
                    end
                end
            end
            local thumb = sbr.GetThumbTexture and sbr:GetThumbTexture()
            if thumb then
                thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
                thumb:SetVertexColor(1, 1, 1, 0.3)
                thumb:SetWidth(4)
            end
        end
    end
    -- Skin every realized socket (art only; layout is separate).
    local function SkinSocketsArt()
        local c = f.SocketingContainer
        if not c then return end
        for _, k in ipairs({ "Socket1", "Socket2", "Socket3" }) do SkinSocket(c[k]) end
        if c.SocketFrames then
            for _, sock in ipairs(c.SocketFrames) do SkinSocket(sock) end
        end
        if c.ApplySocketsButton then WSkin.Button(c.ApplySocketsButton) end
    end
    -- Full pass: reposition + reskin + restrip. Idempotent, safe to repeat.
    local function FullPass()
        if not f:IsVisible() then return end
        LayoutSocketing()
        SkinSocketsArt()
        WSkin.Restrip()
    end

    LayoutSocketing()
    SkinSocketsArt()
    WSkin.ScrollBarsIn(f)

    -- Blizzard repaints the sockets on every item change. LAYOUT runs
    -- SYNCHRONOUSLY: Blizzard re-anchors the sockets to its own positions
    -- inside the update, so a debounced reposition would render one frame at
    -- Blizzard's spot then snap to ours -- the gem-click bounce. The debounced
    -- FullPass ALSO re-layouts, which is what fixes the FIRST open: on the
    -- initial populate the sockets aren't laid out yet, so the sync pass
    -- measured nothing -- the deferred pass catches them once realized.
    if type(_G.ItemSocketingFrame_Update) == "function" and not GetFFD(f).updHook then
        GetFFD(f).updHook = true
        local deferred = WSkin.Debounce(FullPass)
        hooksecurefunc("ItemSocketingFrame_Update", function()
            if not f:IsVisible() then return end
            LayoutSocketing()
            deferred()
        end)
    end

    -- On (re)show, run the full pass now AND once the sockets have realized.
    -- First open loads this LoD addon with the frame already showing, so the
    -- sockets are neither laid out nor fully built on the initial pass -- the
    -- icons render shifted with un-faded art until a deferred pass lands.
    WSkin.HookShow(f, WSkin.Debounce(function()
        FullPass()
        if C_Timer then
            C_Timer.After(0, FullPass)
            C_Timer.After(0.1, FullPass)
        end
    end))
end

WSkin.RegisterWindow({
    key = "socket",
    addons = { Blizzard_ItemSocketingUI = true },
    apply = Skin_Socket,
})

-------------------------------------------------------------------------------
--  Reputation & Currency tabs (CharacterFrame sub-panes). Rides the charsheet
--  style key but touches ONLY content inside ReputationFrame/TokenFrame --
--  the character page chrome and the pane backdrops are owned by the
--  CharacterSheet skin and are never faded here. Taint notes: the currency
--  transfer log toggle is never restyled (restyling it breaks currency
--  transfers), and all scrollbar work is texture-only.
-------------------------------------------------------------------------------
local function RCWhiteTextsIn(host)
    if not host or not host.GetRegions then return end
    for i = 1, select("#", host:GetRegions()) do
        local r = select(i, host:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            WSkin.Font(r)
            WSkin.White(r)
        end
    end
end

-- Collapse state straight from the row's element data -- painted atlas names
-- differ between the rep and token lists and between nesting levels, so they
-- are only a fallback.
local function RCCollapsedIn(t)
    if type(t) ~= "table" then return nil end
    if t.isCollapsed ~= nil then return t.isCollapsed and true or false end
    if t.isHeaderExpanded ~= nil then return (not t.isHeaderExpanded) and true or false end
    return nil
end

local function RCRowCollapsed(row)
    if not row.GetElementData then return nil end
    local ok, dt = pcall(row.GetElementData, row)
    if not ok or type(dt) ~= "table" then return nil end
    local c = RCCollapsedIn(dt)
    if c == nil then c = RCCollapsedIn(dt.factionData) end
    if c == nil then c = RCCollapsedIn(dt.data) end
    return c
end

local RC_STRIP_KEYS = { "Left", "Middle", "HighlightLeft", "HighlightMiddle",
                        "HighlightRight" }
local function SkinRCRow(child, isCurrency)
    if not child or child:IsForbidden() then return end
    -- Currency (TokenFrame) rows are left 100% STOCK. Skinning them at all -- even
    -- the band-strip fade -- taints Blizzard's warband currency transfer (forbidding
    -- the protected RequestCurrencyFromAccountCharacter) and blanks the currency
    -- column headers we can't safely restyle. Reputation rows below are unaffected.
    if isCurrency then return end
    local d = GetFFD(child)
    -- Per-pass: pooled rows get re-initialized by Blizzard, so the header
    -- band fades must re-assert on every list update.
    for _, k in ipairs(RC_STRIP_KEYS) do
        local t = child[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    -- Header +/- toggle: strip Blizzard's paint and drive the spellbook
    -- max/min glyph off the state Blizzard painted. Runs per pass so the
    -- strip survives pooled-row repaints.
    local tcb = child.ToggleCollapseButton
    if tcb then
        local bd = GetFFD(tcb)
        if not bd.glyph then
            local glyph = tcb:CreateTexture(nil, "OVERLAY")
            glyph:SetSize(16, 16)
            glyph:SetPoint("CENTER", tcb, "CENTER", 0, 0)
            bd.glyph = glyph
            -- The stock button is a tiny click target; pad the hit rect.
            tcb:SetHitRectInsets(-6, -6, -6, -6)
            local function classify(a)
                if type(a) ~= "string" then return nil end
                a = a:lower()
                if a:find("expanded", 1, true) then return true end
                if a:find("minus", 1, true) or a:find("collapse", 1, true) then return true end
                if a:find("plus", 1, true) or a:find("expand", 1, true) then return false end
                return nil
            end
            local function repaint()
                local expanded
                local collapsed = RCRowCollapsed(child)
                if collapsed ~= nil then expanded = not collapsed end
                for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                                     "GetHighlightTexture", "GetDisabledTexture" }) do
                    local t = tcb[g] and tcb[g](tcb)
                    if t then
                        if expanded == nil and t.GetAtlas then
                            expanded = classify(t:GetAtlas())
                        end
                        t:SetAlpha(0)
                    end
                end
                for i = 1, select("#", tcb:GetRegions()) do
                    local r = select(i, tcb:GetRegions())
                    if r and r ~= glyph and r.IsObjectType and r:IsObjectType("Texture") then
                        if expanded == nil and r.GetAtlas then
                            expanded = classify(r:GetAtlas())
                        end
                        r:SetAlpha(0)
                    end
                end
                if expanded == nil then expanded = true end
                glyph:SetAtlas(expanded and "UI-QuestTrackerButton-Secondary-Collapse"
                                        or "UI-QuestTrackerButton-Secondary-Expand", false)
                glyph:SetDesaturated(true)
                glyph:SetVertexColor(1, 1, 1, tcb:IsMouseOver() and 1 or 0.75)
            end
            bd.repaint = repaint
            if tcb.RefreshIcon then hooksecurefunc(tcb, "RefreshIcon", repaint) end
            tcb:HookScript("OnClick", repaint)
            tcb:HookScript("OnEnter", function() glyph:SetVertexColor(1, 1, 1, 1) end)
            tcb:HookScript("OnLeave", function() glyph:SetVertexColor(1, 1, 1, 0.75) end)
            repaint()
        else
            bd.repaint()
        end
    end
    -- Rep-style header rows carry Blizzard's boxed +/- directly in the Right
    -- texture slot (the Options_ListExpand atlases). Hide that art and drive
    -- the spellbook max/min glyph in its place; rows that instead have a
    -- ToggleCollapseButton get their glyph from the button handler above.
    -- Runs per pass: collapse toggles rebuild rows without always re-setting
    -- the atlas.
    local chev = child.Right
    if chev and chev.GetAtlas then
        local cd = GetFFD(chev)
        if not cd.styleRight then
            cd.styleRight = function()
                local a = chev:GetAtlas()
                local isExpandArt = a == "Options_ListExpand_Right"
                    or a == "Options_ListExpand_Right_Expanded"
                chev:SetAlpha(0)
                if not isExpandArt or child.ToggleCollapseButton then
                    if cd.glyph then cd.glyph:Hide() end
                    return
                end
                local g = cd.glyph
                if not g then
                    g = child:CreateTexture(nil, "OVERLAY")
                    g:SetSize(16, 16)
                    g:SetPoint("CENTER", chev, "CENTER", 0, 0)
                    cd.glyph = g
                end
                local collapsed = RCRowCollapsed(child)
                if collapsed == nil then
                    collapsed = a == "Options_ListExpand_Right"
                end
                g:SetAtlas(collapsed and "UI-QuestTrackerButton-Secondary-Expand"
                    or "UI-QuestTrackerButton-Secondary-Collapse", false)
                g:SetDesaturated(true)
                g:SetVertexColor(1, 1, 1, 0.75)
                g:Show()
            end
            hooksecurefunc(chev, "SetAtlas", cd.styleRight)
        end
        cd.styleRight()
    end
    if d.rcSkinned then return end
    d.rcSkinned = true
    -- Header rows (the ones carrying the band art) get a subtle house plate
    -- and a white hover in place of the faded highlight band.
    if child.Middle and not d.plate then
        local plate = SolidTex(child, "BACKGROUND", 1, 1, 1, 0.05)
        plate:SetAllPoints(child)
        d.plate = plate
        local hov = SolidTex(child, "HIGHLIGHT", 1, 1, 1, 0.05)
        hov:SetAllPoints(child)
        d.hover = hov
    end
    RCWhiteTextsIn(child)
    local content = child.Content
    if content then
        RCWhiteTextsIn(content)
        local icon = content.CurrencyIcon
        if icon then WSkin.SquareIcon(icon) end
        local rb = content.ReputationBar
        if rb and rb.GetStatusBarTexture then
            local keep = {}
            local fill = rb:GetStatusBarTexture()
            if fill then keep[fill] = true end
            WSkin.FadeRegions(rb, keep)
            rb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            WSkin.ApplyBarFill(rb)
            local rd = GetFFD(rb)
            if not rd.bg then
                local trough = rb:CreateTexture(nil, "BACKGROUND", nil, -1)
                trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                trough:SetAllPoints(rb)
                rd.bg = trough
                WSkin.AddBorder(rb)
            end
            RCWhiteTextsIn(rb)
        end
    end
end

local function HookRCScrollBox(box, isCurrency)
    if not box or not box.ForEachFrame then return end
    local skin = function(row) SkinRCRow(row, isCurrency) end
    pcall(box.ForEachFrame, box, skin)
    local d = GetFFD(box)
    if box.Update and not d.rowHook then
        d.rowHook = true
        hooksecurefunc(box, "Update", function(b)
            pcall(b.ForEachFrame, b, skin)
        end)
    end
end

local function Skin_RepCurrency()
    local rep = _G.ReputationFrame
    if rep then
        if rep.filterDropdown then WSkin.Dropdown(rep.filterDropdown) end
        WSkin.ScrollBarsIn(rep)
        HookRCScrollBox(rep.ScrollBox)
        local det = rep.ReputationDetailFrame
        if det then
            SkinGuildPopup(det)
            for _, k in ipairs({ "AtWarCheckbox", "MakeInactiveCheckbox",
                                 "WatchFactionCheckbox" }) do
                if det[k] then SkinGuildCheck(det[k]) end
            end
            if det.ViewRenownButton then WSkin.Button(det.ViewRenownButton) end
            if det.ScrollingDescriptionScrollBar then
                WSkin.ScrollBar(det.ScrollingDescriptionScrollBar)
            end
        end
    end

    local tok = _G.TokenFrame
    if tok then
        if tok.filterDropdown then WSkin.Dropdown(tok.filterDropdown) end
        WSkin.ScrollBarsIn(tok)
        HookRCScrollBox(tok.ScrollBox, true)  -- currency rows: band-fade only, no collapse/content skin (taints transfer)
        -- tok.CurrencyTransferLogToggleButton stays 100% stock: restyling it
        -- taints currency transfers.
        local pop = _G.TokenFramePopup
        if pop then
            SkinGuildPopup(pop)
            local pcb = pop["$parent.CloseButton"]
            if pcb then WSkin.CloseButton(pcb) end
            for _, k in ipairs({ "InactiveCheckbox", "BackpackCheckbox" }) do
                if pop[k] then SkinGuildCheck(pop[k]) end
            end
            -- pop.CurrencyTransferToggleButton is left 100% stock -- same as
            -- CurrencyTransferLogToggleButton above. Skinning it taints the
            -- warband currency-transfer path, so the protected
            -- RequestCurrencyFromAccountCharacter() call was being forbidden
            -- for users who actually transfer currency (ADDON_ACTION_FORBIDDEN).
        end
    end
end

WSkin.RegisterWindow({
    key = "charsheet",
    apply = Skin_RepCurrency,
})

-------------------------------------------------------------------------------
--  Housing Dashboard. Chrome only by request: shell backdrop/border, top
--  bar, title, close button. The dashboard CONTENT (house info, catalog,
--  initiatives) stays 100% stock.
-------------------------------------------------------------------------------
local function Skin_Housing()
    local f = _G.HousingDashboardFrame
    if not f then return end
    WSkin.Shell("housing", f)
    WSkin.RemovePortrait(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if title then
        WSkin.Font(title)
        WSkin.White(title)
    end
    local cb = f.CloseButton or (f.GetName and _G[(f:GetName() or "") .. "CloseButton"])
    if cb then WSkin.CloseButton(cb) end
    -- Requested content controls: the top tab row, the house finder button,
    -- and the neighborhood dropdown. Everything else in the content stays
    -- stock.
    local info = f.HouseInfoContent
    if info then
        -- Finder button + house dropdown sit 8px lower (one-shot, anchors
        -- preserved).
        local function DropInfoControl(ctrl)
            if not ctrl then return end
            local cd2 = GetFFD(ctrl)
            if cd2.dropped8 then return end
            local np = ctrl:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = ctrl:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 8 }
            end
            if not ok then return end
            cd2.dropped8 = true
            ctrl:ClearAllPoints()
            for i = 1, #pts do
                local t = pts[i]
                ctrl:SetPoint(t[1], t[2], t[3], t[4], t[5])
            end
        end
        if info.HouseFinderButton then
            WSkin.Button(info.HouseFinderButton)
            local hfs = info.HouseFinderButton.GetFontString
                and info.HouseFinderButton:GetFontString()
            if hfs then WSkin.White(hfs) end
        end
        if info.HouseDropdown then
            WSkin.Dropdown(info.HouseDropdown)
            local hdd = GetFFD(info.HouseDropdown)
            if not hdd.scaled then
                hdd.scaled = true
                info.HouseDropdown:SetScale(0.86)
            end
            DropInfoControl(info.HouseDropdown)
        end
        local cf = info.ContentFrame
        if cf and cf.TabSystem then
            WSkin.TabSystem(cf.TabSystem, { darkActive = true })
            -- 1px up: the accent underline sits on the tabs' bottom edge and
            -- gets clipped at the stock seat.
            local tsd = GetFFD(cf.TabSystem)
            if not tsd.lifted then
                local np = cf.TabSystem:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = cf.TabSystem:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) + 1 }
                end
                if ok then
                    tsd.lifted = true
                    cf.TabSystem:ClearAllPoints()
                    for i = 1, #pts do
                        local t = pts[i]
                        cf.TabSystem:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                end
            end
            -- Blizzard rebuilds these tabs; restyle new ones as they appear.
            if cf.UpdateTabs and not GetFFD(cf).tabHook then
                GetFFD(cf).tabHook = true
                hooksecurefunc(cf, "UpdateTabs", function(cf2)
                    if cf2.TabSystem then
                        WSkin.TabSystem(cf2.TabSystem, { darkActive = true })
                    end
                end)
            end
        end
    end
    local cat = f.CatalogContent
    if cat then
        local sbx = cat.SearchBox
        local fdd = cat.Filters and cat.Filters.FilterDropdown
        if sbx then WSkin.EditBox(sbx) end
        if fdd then
            WSkin.Dropdown(fdd)
            -- Left-aligned label (this dropdown only, not engine wide).
            local lab = fdd.Text or (fdd.GetFontString and fdd:GetFontString())
            local fdData = GetFFD(fdd)
            if lab and not fdData.labLeft then
                fdData.labLeft = true
                lab:ClearAllPoints()
                lab:SetPoint("LEFT", fdd, "LEFT", 8, 0)
                lab:SetPoint("RIGHT", fdd, "RIGHT", -22, 0)
                if lab.SetJustifyH then lab:SetJustifyH("LEFT") end
            end
        end
        -- Search box matches the filter dropdown's height (one-shot; retries
        -- on catalog show until the dropdown has a laid-out height).
        if sbx and fdd then
            local function MatchSearchHeight()
                if GetFFD(sbx).hMatched then return end
                local dh = fdd:GetHeight()
                if dh and dh > 0 then
                    GetFFD(sbx).hMatched = true
                    sbx:SetHeight(dh)
                end
            end
            MatchSearchHeight()
            if not GetFFD(cat).hHook then
                GetFFD(cat).hHook = true
                cat:HookScript("OnShow", MatchSearchHeight)
            end
        end
    end
end

WSkin.RegisterWindow({
    key = "housing",
    addons = { Blizzard_HousingDashboard = true },
    apply = Skin_Housing,
})

-------------------------------------------------------------------------------
--  Profession Crafting window (the per-profession window with the recipe
--  list, schematic form, specializations, and crafting orders). First-pass
--  base skin: shell chrome, tabs, lists, buttons, rank bar, gear slots.
--  Reagent slot art stays stock for now. All work is visual-only.
-------------------------------------------------------------------------------
local function SkinProfMaxMin(btn, atlas)
    if not btn or GetFFD(btn).mm then return end
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then return end
    GetFFD(btn).mm = true
    for i = 1, select("#", btn:GetRegions()) do
        local r = select(i, btn:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                         "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = btn[g] and btn[g](btn)
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    local glyph = btn:CreateTexture(nil, "OVERLAY")
    glyph:SetSize(16, 16)
    glyph:SetPoint("CENTER", btn, "CENTER", -2, 0)
    glyph:SetAtlas(atlas, false)
    glyph:SetDesaturated(true)
    glyph:SetVertexColor(1, 1, 1, 0.75)
    btn:HookScript("OnEnter", function() glyph:SetVertexColor(1, 1, 1, 1) end)
    btn:HookScript("OnLeave", function() glyph:SetVertexColor(1, 1, 1, 0.75) end)
end

-- Profession rank bar (crafting page + order view): house trough + border
-- behind Blizzard's own fill (the fill itself is kept).
local function ProfFlatBar(bar)
    if not bar then return end
    local d = GetFFD(bar)
    if d.flat then return end
    d.flat = true
    for _, k in ipairs({ "Border", "Background" }) do
        local t = bar[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    if not d.bg then
        local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        -- The bar FRAME already matches the band's size; only its origin is
        -- off. The Fill's fixed top-left corner IS the band origin, so:
        -- frame size + fill origin = the exact band (right 8px cut off).
        local w, h = bar:GetSize()
        if bar.Fill and w and w > 8 and h and h > 0 then
            trough:SetSize(w - 8, h)
            trough:SetPoint("TOPLEFT", bar.Fill, "TOPLEFT", 0, 0)
        else
            trough:SetAllPoints(bar)
        end
        d.bg = trough
        WSkin.BorderRegion(bar, trough)
    end
    local rankText = bar.Rank and bar.Rank.Text
    if rankText then
        WSkin.Font(rankText)
        WSkin.White(rankText)
    end
    -- Expansion picker: strip the stock arrow art, seat the house dropdown
    -- arrow with the standard 5% hover wash.
    local edb = bar.ExpansionDropdownButton
    if edb and not GetFFD(edb).arrow then
        local ed = GetFFD(edb)
        ed.arrow = true
        for i = 1, select("#", edb:GetRegions()) do
            local r = select(i, edb:GetRegions())
            if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
        end
        for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                             "GetHighlightTexture", "GetDisabledTexture" }) do
            local t = edb[g] and edb[g](edb)
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        local ar = edb:CreateTexture(nil, "OVERLAY")
        ar:SetAtlas("Azerite-PointingArrow", false)
        ar:SetSize(14, 10)
        ar:SetPoint("CENTER", edb, "CENTER", 0, 0)
        ed.caret = ar
        local hov = edb:CreateTexture(nil, "HIGHLIGHT")
        hov:SetColorTexture(1, 1, 1, 0.05)
        hov:SetAllPoints(edb)
    end
end

local function SkinSchematic(form)
    if not form or form:IsForbidden() then return end
    local d = GetFFD(form)
    if d.schem then return end
    d.schem = true
    WSkin.FadeRegions(form)
    WSkin.Register(form, true)
    if form.Background then form.Background:SetAlpha(0) end
    if form.MinimalBackground then form.MinimalBackground:SetAlpha(0) end
    if not d.bg then
        local bg = SolidTex(form, "BACKGROUND", 0, 0, 0, 0.25, -6)
        bg:SetAllPoints(form)
        d.bg = bg
    end
    for _, k in ipairs({ "TrackRecipeCheckbox", "AllocateBestQualityCheckbox" }) do
        if form[k] then SkinGuildCheck(form[k]) end
    end
    local qd = form.QualityDialog
    if qd then
        SkinGuildPopup(qd)
        if qd.ClosePanelButton then WSkin.CloseButton(qd.ClosePanelButton) end
        if qd.AcceptButton then WSkin.Button(qd.AcceptButton) end
        if qd.CancelButton then WSkin.Button(qd.CancelButton) end
    end
end

local function SkinOutputLog(log)
    if not log or GetFFD(log).outLog then return end
    GetFFD(log).outLog = true
    SkinGuildPopup(log)
    if log.ClosePanelButton then WSkin.CloseButton(log.ClosePanelButton) end
    WSkin.ScrollBarsIn(log)
end

local PROF_GEAR_SLOTS = {
    "Prof0ToolSlot", "Prof0Gear0Slot", "Prof0Gear1Slot",
    "Prof1ToolSlot", "Prof1Gear0Slot", "Prof1Gear1Slot",
    "CookingToolSlot", "CookingGear0Slot",
    "FishingToolSlot", "FishingGear0Slot", "FishingGear1Slot",
}
local function SkinProfGearSlot(btn)
    if not btn then return end
    local d = GetFFD(btn)
    if d.slot then return end
    d.slot = true
    local icon = btn.icon or btn.Icon
    local keep = {}
    if icon then keep[icon] = true end
    if btn.IconBorder then keep[btn.IconBorder] = true end
    WSkin.FadeRegions(btn, keep)
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
        local t = btn[g] and btn[g](btn)
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    if icon then WSkin.SquareIcon(icon, btn) end
    -- 2px smaller than stock (top-right tool/gear icons).
    if not InCombatLockdown() then
        local w, h = btn:GetSize()
        if w and w > 4 and h and h > 4 then
            btn:SetSize(w - 2, h - 2)
        end
    end
end

-- Sortable column header over the crafting orders list (roster-columns
-- treatment: 3-slice art gone, slightly-raised plate, border-free, white
-- labels, 10% hover).
local function SkinOrderColumns(cd)
    if not cd then return end
    WSkin.FadeRegions(cd)
    WSkin.Register(cd, true)
    for i = 1, select("#", cd:GetChildren()) do
        local col = select(i, cd:GetChildren())
        if col and col.GetObjectType and col:GetObjectType() == "Button" then
            local d2 = GetFFD(col)
            if not d2.bg then
                for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                    local t2 = col[k2]
                    if t2 and t2.SetTexture then t2:SetTexture("") end
                end
                WSkin.FadeRegions(col)
                local bg2 = SolidTex(col, "BACKGROUND",
                    Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                bg2:SetPoint("TOPLEFT", 1, -1)
                bg2:SetPoint("BOTTOMRIGHT", -1, 1)
                d2.bg = bg2
                local hov = SolidTex(col, "HIGHLIGHT", 1, 1, 1, 0.1)
                hov:SetAllPoints(col)
                d2.hover = hov
                WSkin.Register(col, true)
            end
            local fs2 = col.GetFontString and col:GetFontString()
            if fs2 then WSkin.White(fs2) end
        end
    end
end

local function SkinOrderView(ov)
    if not ov then return end
    for _, k in ipairs({ "CreateButton", "StartRecraftButton", "CompleteOrderButton" }) do
        if ov[k] then WSkin.Button(ov[k]) end
    end
    ProfFlatBar(ov.RankBar)
    SkinOutputLog(ov.CraftingOutputLog)
    local oi = ov.OrderInfo
    if oi then
        WSkin.FadeRegions(oi)
        WSkin.Register(oi, true)
        for _, k in ipairs({ "BackButton", "StartOrderButton",
                             "DeclineOrderButton", "ReleaseOrderButton" }) do
            if oi[k] then WSkin.Button(oi[k]) end
        end
    end
    local od = ov.OrderDetails
    if od then
        WSkin.FadeRegions(od)
        WSkin.Register(od, true)
        if od.Background then od.Background:SetAlpha(0) end
        SkinSchematic(od.SchematicForm)
    end
    local dd = ov.DeclineOrderDialog
    if dd then
        SkinGuildPopup(dd)
        if dd.ConfirmButton then WSkin.Button(dd.ConfirmButton) end
        if dd.CancelButton then WSkin.Button(dd.CancelButton) end
    end
end

local function Skin_Professions()
    local f = _G.ProfessionsFrame
    if not f then return end
    WSkin.Shell("professions", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if title then
        WSkin.Font(title)
        WSkin.White(title)
    end
    if f.CloseButton then WSkin.CloseButton(f.CloseButton) end
    local mm = f.MaximizeMinimize
    if mm then
        SkinProfMaxMin(mm.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
        SkinProfMaxMin(mm.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
    end
    if f.TabSystem then WSkin.TabSystem(f.TabSystem) end

    local cp = f.CraftingPage
    if cp then
        for _, k in ipairs({ "CreateButton", "CreateAllButton", "ViewGuildCraftersButton" }) do
            if cp[k] then WSkin.Button(cp[k]) end
        end
        if cp.MinimizedSearchBox then WSkin.EditBox(cp.MinimizedSearchBox) end
        ProfFlatBar(cp.RankBar)
        SkinSchematic(cp.SchematicForm)
        SkinOutputLog(cp.CraftingOutputLog)
        local rl = cp.RecipeList
        if rl then
            WSkin.FadeRegions(rl)
            WSkin.Register(rl, true)
            if rl.BackgroundNineSlice then WSkin.FadeNineSlice(rl.BackgroundNineSlice) end
            local d = GetFFD(rl)
            if not d.bg then
                local bg = SolidTex(rl, "BACKGROUND", 0, 0, 0, 0.25, -6)
                bg:SetAllPoints(rl)
                d.bg = bg
            end
            -- Sidebar filter dropdown: 2px taller, label left-aligned (this
            -- dropdown only, not engine wide).
            local fdd = rl.FilterDropdown
            if fdd then
                local fd = GetFFD(fdd)
                if not fd.hTuned then
                    local h0 = fdd:GetHeight()
                    if h0 and h0 > 0 then
                        fd.hTuned = true
                        fdd:SetHeight(h0 + 2)
                        -- Nudged up 1px (one-shot, all points preserved).
                        local pts = {}
                        local ok = true
                        for i = 1, fdd:GetNumPoints() do
                            local p, rel, rp, x, y = fdd:GetPoint(i)
                            if not p then ok = false break end
                            pts[i] = { p, rel, rp, x or 0, (y or 0) + 1 }
                        end
                        if ok and #pts > 0 then
                            fdd:ClearAllPoints()
                            for i = 1, #pts do
                                local t = pts[i]
                                fdd:SetPoint(t[1], t[2], t[3], t[4], t[5])
                            end
                        end
                    end
                end
                local lab = fdd.Text or (fdd.GetFontString and fdd:GetFontString())
                if lab and not fd.labLeft then
                    fd.labLeft = true
                    lab:ClearAllPoints()
                    lab:SetPoint("LEFT", fdd, "LEFT", 8, 0)
                    lab:SetPoint("RIGHT", fdd, "RIGHT", -22, 0)
                    if lab.SetJustifyH then lab:SetJustifyH("LEFT") end
                end
                -- Active-filter reset X (house glyph).
                SkinFilterResetX(fdd.ResetButton, fdd)
            end
        end
        for _, k in ipairs(PROF_GEAR_SLOTS) do SkinProfGearSlot(cp[k]) end
    end

    local sp = f.SpecPage
    if sp then
        for _, k in ipairs({ "ViewTreeButton", "UnlockTabButton", "ApplyButton",
                             "ViewPreviewButton", "BackToFullTreeButton",
                             "BackToPreviewButton" }) do
            if sp[k] then WSkin.Button(sp[k]); WSkin.WhiteButtonLabel(sp[k]) end
        end
        if sp.PanelFooter then WSkin.FadeRegions(sp.PanelFooter) end
        local tv = sp.TreeView
        if tv then
            -- Tree background art is content: keep it, dimmed (talents
            -- treatment).
            local keep = {}
            if tv.Background then keep[tv.Background] = true end
            WSkin.FadeRegions(tv, keep)
            if tv.Background then tv.Background:SetAlpha(0.75) end
            -- The tree art bleeds past the center divider; clamp its right
            -- edge to the detail pane's left edge.
            local dv0 = sp.DetailedView
            if tv.Background and dv0 and not GetFFD(tv).bgClamped then
                GetFFD(tv).bgClamped = true
                tv.Background:ClearAllPoints()
                tv.Background:SetPoint("TOPLEFT", tv, "TOPLEFT", 0, 0)
                tv.Background:SetPoint("BOTTOMRIGHT", dv0, "BOTTOMLEFT", 0, 0)
            end
        end
        local dv = sp.DetailedView
        if dv then
            WSkin.FadeRegions(dv)
            WSkin.Register(dv, true)
            for _, k in ipairs({ "UnlockPathButton", "SpendPointsButton" }) do
                if dv[k] then WSkin.Button(dv[k]); WSkin.WhiteButtonLabel(dv[k]) end
            end
        end
        -- Spec tabs are pooled and rebuilt; skin now and on every rebuild.
        local function SkinSpecTabs(sp2)
            if sp2.tabsPool then
                for tab in sp2.tabsPool:EnumerateActive() do
                    WSkin.Tab(tab, { darkActive = true })
                end
            end
        end
        if sp.UpdateTabs and not GetFFD(sp).tabHook then
            GetFFD(sp).tabHook = true
            hooksecurefunc(sp, "UpdateTabs", SkinSpecTabs)
        end
        SkinSpecTabs(sp)
    end

    local op = f.OrdersPage
    if op then
        local bf = op.BrowseFrame
        if bf then
            -- Order-type tabs populate LAZILY -- some aren't created until you
            -- click through the types -- so a one-time pass leaves the
            -- later-created ones unstyled until a full re-skin. Re-run after
            -- each tab click (deferred, once the new tabs exist) and on the
            -- browse OnShow. WSkin.Tab is guarded, so re-runs only skin NEW
            -- tabs; each tab's OnClick is hooked once to trigger the re-run.
            local ORDER_TAB_KEYS = { "PublicOrdersButton", "NpcOrdersButton",
                                     "GuildOrdersButton", "PersonalOrdersButton" }
            local function SkinOrderTabs()
                for _, k in ipairs(ORDER_TAB_KEYS) do
                    local b = bf[k]
                    if b then
                        WSkin.Tab(b, { darkActive = true })
                        if not GetFFD(b).clickReskin then
                            GetFFD(b).clickReskin = true
                            b:HookScript("OnClick", function()
                                if C_Timer then C_Timer.After(0, SkinOrderTabs) end
                            end)
                        end
                    end
                end
            end
            SkinOrderTabs()
            if C_Timer then C_Timer.After(0, SkinOrderTabs) end
            -- Tab row starts where the sort header starts: shift the chain
            -- root right by the measured delta (one-shot; the other three
            -- tabs chain off it). Rects only exist once the browse frame has
            -- been laid out, so retry on show.
            local firstTab = bf.PublicOrdersButton
            local function AlignOrderTabs()
                if GetFFD(bf).tabsAligned or not firstTab then return end
                local ol2 = bf.OrderList
                local tl = firstTab.GetLeft and firstTab:GetLeft()
                local ll = ol2 and ol2.GetLeft and ol2:GetLeft()
                if not tl or not ll then return end
                local dx = math.floor((ll - tl) + 0.5)
                if dx == 0 then
                    GetFFD(bf).tabsAligned = true
                    return
                end
                local pts, ok = {}, true
                for i = 1, firstTab:GetNumPoints() do
                    local p, rel, rp, x, y = firstTab:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, (x or 0) + dx, y or 0 }
                end
                if ok and #pts > 0 then
                    GetFFD(bf).tabsAligned = true
                    firstTab:ClearAllPoints()
                    for i = 1, #pts do
                        local t = pts[i]
                        firstTab:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                end
            end
            AlignOrderTabs()
            if not GetFFD(bf).alignHook then
                GetFFD(bf).alignHook = true
                bf:HookScript("OnShow", function()
                    SkinOrderTabs()
                    if C_Timer then
                        C_Timer.After(0, function() SkinOrderTabs(); AlignOrderTabs() end)
                    else
                        AlignOrderTabs()
                    end
                end)
            end
            local searchBar = bf.SearchBox or bf.searchBox
            if bf.SearchButton then
                WSkin.Button(bf.SearchButton)
                local sfs = bf.SearchButton.GetFontString and bf.SearchButton:GetFontString()
                if sfs then WSkin.White(sfs) end
                local sbtn = bf.SearchButton
                local sd = GetFFD(sbtn)
                if not sd.shrunk then
                    local w, h = sbtn:GetSize()
                    if w and w > 2 and h and h > 2 then
                        sd.shrunk = true
                        sbtn:SetSize(w - 1, h - 1)
                    end
                end
                -- Left edge flush with the search box's left (keep its Y).
                -- Measured, retried on show until the search bar has laid out.
                local function AlignSearchBtn()
                    if not searchBar or GetFFD(sbtn).leftAligned then return end
                    local bl, sl = sbtn:GetLeft(), searchBar:GetLeft()
                    if not bl or not sl then return end
                    local dx = sl - bl
                    if math.abs(dx) < 0.5 then GetFFD(sbtn).leftAligned = true; return end
                    local np = sbtn:GetNumPoints() or 0
                    local pts, ok = {}, np > 0
                    for i = 1, np do
                        local p, rel, rp, x, y = sbtn:GetPoint(i)
                        if not p then ok = false break end
                        pts[i] = { p, rel, rp, (x or 0) + dx, y or 0 }
                    end
                    if ok then
                        GetFFD(sbtn).leftAligned = true
                        sbtn:ClearAllPoints()
                        for i = 1, #pts do local t = pts[i]; sbtn:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                    end
                end
                AlignSearchBtn()
                if not GetFFD(sbtn).alignHook then
                    GetFFD(sbtn).alignHook = true
                    bf:HookScript("OnShow", function()
                        if C_Timer then C_Timer.After(0, AlignSearchBtn) else AlignSearchBtn() end
                    end)
                end
            end
            if bf.FavoritesSearchButton then
                -- Keep the star art: the Icon key survives the strip and the
                -- state textures are restored after.
                local fav = bf.FavoritesSearchButton
                WSkin.Button(fav, { "Icon" })
                for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
                    local t = fav[g] and fav[g](fav)
                    if t and t.SetAlpha then t:SetAlpha(1) end
                end
                -- Seat to the right of the search box, 10px gap (direct anchor,
                -- no rects needed). One-shot.
                if searchBar and not GetFFD(fav).reseated then
                    GetFFD(fav).reseated = true
                    fav:ClearAllPoints()
                    fav:SetPoint("LEFT", searchBar, "RIGHT", 10, 0)
                end
            end
            if bf.BackButton then WSkin.Button(bf.BackButton) end
            local ord = bf.OrdersRemainingDisplay
            if ord then
                WSkin.FadeRegions(ord)
                WSkin.Register(ord, true)
                -- Seated top-right: 20px from the right edge, 10px below the
                -- top bar. Pinned via SetPoint post-hook so Blizzard's browse
                -- layout can't reseat it.
                local od = GetFFD(ord)
                if not od.pinned then
                    od.pinned = true
                    local function Pin()
                        if od.inPin then return end
                        od.inPin = true
                        ord:ClearAllPoints()
                        ord:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -35)
                        od.inPin = false
                    end
                    hooksecurefunc(ord, "SetPoint", function()
                        if not od.inPin then Pin() end
                    end)
                    Pin()
                end
                -- Trailing count in accent (display-time recolor, idempotent:
                -- skips any text that already carries a color code).
                local fs
                for i = 1, select("#", ord:GetRegions()) do
                    local r = select(i, ord:GetRegions())
                    if r and r.IsObjectType and r:IsObjectType("FontString") then
                        fs = r
                        break
                    end
                end
                if fs and not GetFFD(fs).accentNum then
                    local fsd = GetFFD(fs)
                    fsd.accentNum = true
                    WSkin.Font(fs)
                    WSkin.White(fs)
                    local function Recolor()
                        if fsd.inSet then return end
                        local txt = fs:GetText()
                        if type(txt) ~= "string" or txt == "" then return end
                        if txt:find("|c", 1, true) then return end
                        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
                        local hex = string.format("%02x%02x%02x",
                            (EG.r or 0) * 255, (EG.g or 0) * 255, (EG.b or 0) * 255)
                        local new, n = txt:gsub("(%d+%s*)$", "|cff" .. hex .. "%1|r")
                        if n > 0 then
                            fsd.inSet = true
                            fs:SetText(new)
                            fsd.inSet = false
                        end
                    end
                    hooksecurefunc(fs, "SetText", Recolor)
                    hooksecurefunc(fs, "SetFormattedText", Recolor)
                    Recolor()
                end
            end
            local brl = bf.RecipeList
            if brl then
                WSkin.FadeRegions(brl)
                WSkin.Register(brl, true)
                if brl.BackgroundNineSlice then WSkin.FadeNineSlice(brl.BackgroundNineSlice) end
            end
            local ol = bf.OrderList
            if ol then
                WSkin.FadeRegions(ol)
                WSkin.Register(ol, true)
                if ol.BackgroundNineSlice then WSkin.FadeNineSlice(ol.BackgroundNineSlice) end
                -- Sort header: AH-style near-black strip over the
                -- HeaderContainer (this list uses HeaderContainer, not the
                -- older ColumnDisplay), and SortHeaderBar also strips each
                -- clickable column header's 3-slice art and whites its label.
                -- The column SET changes per order-type (Public / Guild /
                -- Personal / NPC): Blizzard rebuilds the header buttons IN
                -- PLACE via the table builder without re-showing the container,
                -- so the plain OnShow hook never caught the freshly built
                -- columns and they stayed stock. Re-run from the table rebuild
                -- (SetupTable) and the list refresh -- the same signals the AH
                -- sort headers ride -- so every new column set is skinned the
                -- instant it is built.
                if ol.HeaderContainer then
                    local function ReskinHeaders() WSkin.SortHeaderBar(ol) end
                    ReskinHeaders()
                    local hc = ol.HeaderContainer
                    if not GetFFD(hc).showHooked then
                        GetFFD(hc).showHooked = true
                        hc:HookScript("OnShow", WSkin.Debounce(ReskinHeaders))
                    end
                    -- Column-rebuild triggers: the table builder's SetupTable
                    -- (fires on every order-type switch / view rebuild) and the
                    -- scroll refresh. Hook whichever exist on the browse frame
                    -- or the list; all guarded, all idempotent, deferred a
                    -- frame so the new column rects have laid out.
                    for _, pair in ipairs({ { bf, "SetupTable" }, { ol, "SetupTable" },
                                            { ol, "RefreshScrollFrame" } }) do
                        local host, method = pair[1], pair[2]
                        if host and type(host[method]) == "function" then
                            local hd = GetFFD(host)
                            local flag = "hdrHook_" .. method
                            if not hd[flag] then
                                hd[flag] = true
                                hooksecurefunc(host, method, WSkin.Debounce(ReskinHeaders))
                            end
                        end
                    end
                    -- Guaranteed trigger regardless of Blizzard method names:
                    -- the order-type tabs (Public / Npc / Guild / Personal) are
                    -- exactly what the user clicks to repopulate the column set.
                    -- Re-skin the headers a frame after each click (once the
                    -- rebuilt columns exist).
                    for _, k in ipairs(ORDER_TAB_KEYS) do
                        local tb = bf[k]
                        if tb and not GetFFD(tb).hdrReskin then
                            GetFFD(tb).hdrReskin = true
                            tb:HookScript("OnClick", WSkin.Debounce(ReskinHeaders))
                        end
                    end
                end
                -- Legacy ColumnDisplay fallback (no-op when the list uses
                -- HeaderContainer instead).
                local ocd = ol.ColumnDisplay
                if ocd then
                    SkinOrderColumns(ocd)
                    if not GetFFD(ocd).showHooked then
                        GetFFD(ocd).showHooked = true
                        ocd:HookScript("OnShow", WSkin.Debounce(function()
                            SkinOrderColumns(ocd)
                        end))
                    end
                end
            end
        end
        SkinOrderView(op.OrderView)
    end

    WSkin.ScrollBarsIn(f)
    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then WSkin.Restrip() end
    end))
end

WSkin.RegisterWindow({
    key = "professions",
    addons = { Blizzard_Professions = true },
    apply = Skin_Professions,
})

-------------------------------------------------------------------------------
--  World Map & Quest Log. First-pass base skin: flat window chrome, nav bar
--  strip, quest log panel, details/campaign/events/legend panes, side tabs.
--  Deliberately hands-off: QuestMapFrame's own scripts (Objective Tracker
--  taint path), the session-sync command button, the map overlay buttons
--  (tracking/pin/floor), and the pooled quest rows stay stock this pass.
--  Visual-only throughout.
-------------------------------------------------------------------------------
-- Quest log side tabs: the exact guild sidebar-tab treatment (squared icon
-- on a black-bordered box, 10% hover, 0.12-0.88 icon crop per pass,
-- disabled at half alpha, no active overlay).
local function SkinMapSideTab(tab)
    if not tab or tab:IsForbidden() then return end
    SquareTabIcon(tab)
    local icon = tab.Icon
    local td = GetFFD(tab)
    if icon and not td.box then
        local box = CreateFrame("Frame", nil, tab)
        box:SetPoint("TOPLEFT", icon, "TOPLEFT", -5, 5)
        box:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 5, -5)
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 2))
        local fill = SolidTex(box, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        fill:SetAllPoints(box)
        WSkin.AddBorder(box, 0, 0, 0, 1)
        td.box = box
        td.bg = fill
        local hov = SolidTex(tab, "HIGHLIGHT", 1, 1, 1, 0.1)
        hov:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        hov:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        td.hover = hov
    end
    -- Tighter icon zoom than the standard crop (re-applied per pass;
    -- SquareTabIcon resets it to the 0.08 standard above).
    if icon and icon.SetTexCoord then icon:SetTexCoord(0.12, 0.88, 0.12, 0.88) end
    local enabled = not tab.IsEnabled or tab:IsEnabled()
    tab:SetAlpha(enabled and 1 or 0.5)
end

-- Quest log collapsible header rows (rep-tab treatment: band art gone,
-- house plate + hover, white text). Blizzard's +/- stays -- it is the small
-- square texture, told apart from the wide band art by width. Pooled rows,
-- so everything re-asserts per pass.
local function SkinQuestHeader(btn, kind)
    if not btn or btn:IsForbidden() then return end
    local withCard = kind == "campaign"
    local d = GetFFD(btn)
    for i = 1, select("#", btn:GetRegions()) do
        local r = select(i, btn:GetRegions())
        if r and r ~= d.plate and r ~= d.hover and r ~= d.card
            and r ~= d.divider
            and r.IsObjectType and r:IsObjectType("Texture") then
            local w = r:GetWidth()
            if w and not issecretvalue(w) and w > 40 then r:SetAlpha(0) end
        end
    end
    -- Campaign card: the guild-sidebar tile sheet behind the big header.
    -- Bottom edge rides 6px up for extra breathing room above the first
    -- campaign quest title.
    if withCard and not d.card then
        local card = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
        card:SetAtlas("Ui-Dialog-New-Background")
        card:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        card:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 6)
        card:SetAlpha(0.5)
        d.card = card
    end
    -- Section headers get a divider line above: separates the campaign
    -- block from the regular quest sections.
    if kind == "header" and not d.divider then
        local div = btn:CreateTexture(nil, "OVERLAY")
        div:SetColorTexture(1, 1, 1, 0.15)
        local PPd = EllesmereUI and EllesmereUI.PanelPP
        if PPd and PPd.DisablePixelSnap then
            PPd.DisablePixelSnap(div)
            div:SetHeight(PPd.mult or 1)
        else
            div:SetHeight(1)
        end
        div:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 12)
        div:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 12)
        d.divider = div
    end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl and hl ~= d.hover then hl:SetAlpha(0) end
    local bt = btn.ButtonText
        or (btn.GetName and btn:GetName() and _G[btn:GetName() .. "ButtonText"])
    if bt and bt.SetTextColor then WSkin.White(bt) end
    if btn.Text and btn.Text.SetTextColor then WSkin.White(btn.Text) end
    -- Blizzard recolors the label gray on hover; re-white after its
    -- enter/leave handlers.
    if not d.hoverTextHook then
        d.hoverTextHook = true
        local function ReWhite()
            local bt2 = btn.ButtonText
                or (btn.GetName and btn:GetName() and _G[btn:GetName() .. "ButtonText"])
            if bt2 and bt2.SetTextColor then WSkin.White(bt2) end
            if btn.Text and btn.Text.SetTextColor then WSkin.White(btn.Text) end
        end
        btn:HookScript("OnEnter", ReWhite)
        btn:HookScript("OnLeave", ReWhite)
    end
    if not d.plate then
        d.plate = SolidTex(btn, "BACKGROUND", 1, 1, 1, 0.05)
        local hov = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.05)
        if withCard then
            -- The dialog-sheet art has soft edges; the washes sit 3px
            -- inside so they match its visible card (guild-tile treatment).
            -- Bottom follows the card's raised edge (6px) plus the inset.
            d.plate:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
            d.plate:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 9)
            hov:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
            hov:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 9)
        else
            d.plate:SetAllPoints(btn)
            hov:SetAllPoints(btn)
        end
        d.hover = hov
    end
end

local function Skin_WorldMap()
    local f = _G.WorldMapFrame
    if not f then return end
    -- Style-aware shell like every other window: the canvas covers the
    -- middle, but the quest log flank, top bar, and borders all show it,
    -- and the EllesmereUI/Modern swap follows the style dropdown.
    WSkin.Shell("worldmap", f)

    WSkin.RemovePortrait(f)
    local bf = f.BorderFrame
    if bf then
        WSkin.RemovePortrait(bf)
        WSkin.FadeRegions(bf)
        WSkin.Register(bf, true)
        if bf.NineSlice then WSkin.FadeNineSlice(bf.NineSlice) end
        if bf.PortraitContainer then
            WSkin.FadeRegions(bf.PortraitContainer)
            WSkin.Register(bf.PortraitContainer, true)
        end
        if _G.WorldMapFramePortrait and _G.WorldMapFramePortrait.SetAlpha then
            _G.WorldMapFramePortrait:SetAlpha(0)
        end
        if bf.CloseButton then WSkin.CloseButton(bf.CloseButton) end
        local mm = bf.MaximizeMinimizeFrame
        if mm then
            SkinProfMaxMin(mm.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
            SkinProfMaxMin(mm.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
        end
        local title = (bf.TitleContainer and bf.TitleContainer.TitleText) or bf.TitleText
        if title then
            WSkin.Font(title)
            WSkin.White(title)
        end
    end

    -- Breadcrumb nav bar. Keep Blizzard's NATIVE crumb layout: re-widthing or
    -- re-anchoring the crumbs (as the Adventure Guide restyle does) flings the
    -- map's text off-window -- the map nav has a home button + overflow button
    -- and arrow-shaped crumb geometry that the chain logic breaks. Both
    -- reference addons only flatten the art, lay one dark bar, white the text,
    -- and give the carets house arrows. Wash is 20% black per request.
    local nav = f.NavBar
    if nav then
        local nd = GetFFD(nav)
        -- One crumb (home + navList): fade native art, subtle hover, white
        -- text, and the SAME caret treatment as the Adventure Guide -- our
        -- aspect-correct arrow, with Blizzard's caret art re-faded on hover so
        -- it can't resurface on OnEnter. No width/anchor changes.
        local function SkinMapCrumb(btn)
            if not btn or btn:IsForbidden() then return end
            local d = GetFFD(btn)
            if not d.mapNav then
                d.mapNav = true
                for _, g in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture" }) do
                    local fn = btn[g]; local t = fn and fn(btn); if t and t.SetAlpha then t:SetAlpha(0) end
                end
                WSkin.FadeRegions(btn)
                local hov = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
                hov:SetPoint("TOPLEFT", 2, -3); hov:SetPoint("BOTTOMRIGHT", -2, 3)
                d.hover = hov
                WSkin.Register(btn, true)
                -- Rewinding (clicking an earlier crumb) hides the later ones,
                -- so re-anchor the capped bar to the new last crumb.
                btn:HookScript("OnClick", function()
                    if nd.reflow then nd.reflow() end
                end)
            end
            if btn.text then WSkin.White(btn.text) end
            local ma = btn.MenuArrowButton
            if ma then
                local md = GetFFD(ma)
                if not md.arrow then
                    local arrow = ma:CreateTexture(nil, "OVERLAY")
                    arrow:SetAtlas("Azerite-PointingArrow")
                    arrow:SetSize(12, 8.5)   -- native 62x44 aspect
                    arrow:SetPoint("CENTER")
                    md.arrow = arrow
                end
                -- Fade ALL native caret art, keeping only our arrow; re-run on
                -- hover so Blizzard's caret can't resurface on OnEnter.
                local function FadeArrowArt()
                    local keep = { [md.arrow] = true }
                    WSkin.FadeRegions(ma, keep)
                    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                        local fn = ma[g]; local t = fn and fn(ma); if t and not keep[t] and t.SetAlpha then t:SetAlpha(0) end
                    end
                    if ma.Art and ma.Art.SetAlpha then ma.Art:SetAlpha(0) end
                end
                FadeArrowArt()
                if not md.hoverHooked then
                    md.hoverHooked = true
                    ma:HookScript("OnEnter", FadeArrowArt)
                    ma:HookScript("OnLeave", FadeArrowArt)
                end
            end
        end
        local function RefreshMapNav()
            -- Move the whole bar 4px lower WITHOUT collapsing its width. The
            -- nav is anchored with MORE THAN ONE point (e.g. TOPLEFT + a right
            -- edge); re-applying only point 1 dropped the right anchor, shrank
            -- the bar to one crumb's width, and forced every parent into the
            -- overflow (the "1 layer deep" cap). Preserve EVERY original point,
            -- each offset -4 in y, so the bar keeps its full span and Blizzard's
            -- native overflow shows as many crumbs as fit.
            if nd.origPts == nil then
                local n = nav:GetNumPoints() or 0
                local pts, ok = {}, n > 0
                for i = 1, n do
                    local p, rel, rp, x, y = nav:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) - 4 }
                end
                if ok then nd.origPts = pts end
            end
            if nd.origPts then
                nav:ClearAllPoints()
                for i = 1, #nd.origPts do
                    local t = nd.origPts[i]
                    nav:SetPoint(t[1], t[2], t[3], t[4], t[5])
                end
            end
            for _, k in ipairs({ "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
                                 "InsetBorderLeft", "InsetBorderRight" }) do
                local t = nav[k]; if t and t.SetAlpha then t:SetAlpha(0) end
            end
            local keep = nd.bg and { [nd.bg] = true } or nil
            WSkin.FadeRegions(nav, keep)
            WSkin.Register(nav, true)
            if nav.overlay then
                WSkin.FadeRegions(nav.overlay)
                local nt = nav.overlay.GetNormalTexture and nav.overlay:GetNormalTexture()
                if nt and nt.SetAlpha then nt:SetAlpha(0) end
                if nav.overlay.SetAlpha then nav.overlay:SetAlpha(0) end
                WSkin.Register(nav.overlay, true)
            end
            if nav.homeButton then SkinMapCrumb(nav.homeButton) end
            if nav.navList then
                for i = 1, #nav.navList do SkinMapCrumb(nav.navList[i]) end
            end
            -- 20% black bar: left edge to the nav, right edge a little (8px)
            -- past the LAST crumb -- capped, not spanning the whole frame.
            if not nd.bg then
                local bar = nav:CreateTexture(nil, "BACKGROUND", nil, -6)
                bar:SetColorTexture(0, 0, 0, 0.2)
                nd.bg = bar
            end
            local last = (nav.navList and #nav.navList > 0 and nav.navList[#nav.navList]) or nav.homeButton
            nd.bg:ClearAllPoints()
            nd.bg:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
            nd.bg:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 0, 0)
            if last then
                nd.bg:SetPoint("RIGHT", last, "RIGHT", 8, 0)
            else
                nd.bg:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
            end
            -- Overflow ("...") button: flatten + aspect-correct arrow + hover,
            -- with Blizzard's art re-faded on hover.
            local ovf = nav.overflowButton
            if ovf then
                local od = GetFFD(ovf)
                if not od.mapOvf then
                    od.mapOvf = true
                    local arrow = ovf:CreateTexture(nil, "OVERLAY")
                    arrow:SetAtlas("Azerite-PointingArrow")
                    arrow:SetSize(12, 8.5)
                    arrow:SetPoint("CENTER")
                    od.arrow = arrow
                    od.hover = SolidTex(ovf, "HIGHLIGHT", 1, 1, 1, 0.1)
                    od.hover:SetAllPoints(ovf)
                end
                local function FadeOvfArt()
                    local keep = { [od.arrow] = true }
                    if od.hover then keep[od.hover] = true end
                    WSkin.FadeRegions(ovf, keep)
                    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                        local fn = ovf[g]; local t = fn and fn(ovf); if t and not keep[t] and t.SetAlpha then t:SetAlpha(0) end
                    end
                end
                FadeOvfArt()
                if not od.hoverHooked then
                    od.hoverHooked = true
                    ovf:HookScript("OnEnter", FadeOvfArt)
                    ovf:HookScript("OnLeave", FadeOvfArt)
                end
            end
        end
        nd.reflow = RefreshMapNav
        RefreshMapNav()
        if not nd.addBtnHook and type(_G.NavBar_AddButton) == "function" then
            nd.addBtnHook = true
            hooksecurefunc("NavBar_AddButton", function(bar)
                if bar == nav then RefreshMapNav() end
            end)
        end
    end

    local spt = f.SidePanelToggle
    if spt then
        if spt.CloseButton then WSkin.PageButton(spt.CloseButton, "<") end
        if spt.OpenButton then WSkin.PageButton(spt.OpenButton, ">") end
    end

    ---------------------------------------------------------------------------
    --  Quest log panel
    ---------------------------------------------------------------------------
    local qm = _G.QuestMapFrame
    if qm then
        if qm.VerticalSeparator then qm.VerticalSeparator:SetAlpha(0) end
        if qm.Background then qm.Background:SetAlpha(0) end

        local qs = _G.QuestScrollFrame
        if qs then
            for _, k in ipairs({ "Edge", "Background", "Center" }) do
                local t = qs[k]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            if qs.BorderFrame then qs.BorderFrame:SetAlpha(0) end
            if qs.Contents and qs.Contents.Separator then
                qs.Contents.Separator:SetAlpha(0)
            end
            local sh = qs.Contents and qs.Contents.StoryHeader
            if sh then
                if sh.TopFiligree then sh.TopFiligree:SetAlpha(0) end
                if sh.Divider then sh.Divider:SetAlpha(0) end
            end
            if qs.SearchBox then WSkin.EditBox(qs.SearchBox) end
            if qs.ScrollBar then WSkin.ScrollBar(qs.ScrollBar) end
            -- Collapsible section headers (pooled; re-skinned on every quest
            -- log update).
            local function SkinQuestHeaders()
                for _, poolKey in ipairs({ "headerFramePool",
                                           "campaignHeaderFramePool",
                                           "campaignHeaderMinimalFramePool" }) do
                    local pool = qs[poolKey]
                    if pool and pool.EnumerateActive then
                        local kind = (poolKey == "campaignHeaderFramePool" and "campaign")
                            or (poolKey == "headerFramePool" and "header")
                            or "minimal"
                        pcall(function()
                            for btn in pool:EnumerateActive() do
                                SkinQuestHeader(btn, kind)
                            end
                        end)
                    end
                end
                -- ONE divider only: the topmost regular header marks the
                -- campaign/regular boundary; all other headers hide theirs.
                local hp = qs.headerFramePool
                if hp and hp.EnumerateActive then
                    pcall(function()
                        local topBtn, topY
                        for btn in hp:EnumerateActive() do
                            local t = btn.GetTop and btn:GetTop()
                            if t and not issecretvalue(t)
                                and (not topY or t > topY) then
                                topY = t
                                topBtn = btn
                            end
                        end
                        if topBtn then
                            for btn in hp:EnumerateActive() do
                                local bd2 = FFD[btn]
                                local div = bd2 and bd2.divider
                                if div then div:SetShown(btn == topBtn) end
                            end
                        end
                    end)
                end
            end
            SkinQuestHeaders()
            if type(_G.QuestLogQuests_Update) == "function"
                and not GetFFD(qs).qhHook then
                GetFFD(qs).qhHook = true
                hooksecurefunc("QuestLogQuests_Update", SkinQuestHeaders)
            end
        end

        -- Midnight nests the details frame under QuestsFrame; older layouts
        -- had it directly on QuestMapFrame. (qm.DetailsFrame was nil, so this
        -- whole block -- including the quest-text fix -- never ran.)
        local det = qm.DetailsFrame or (qm.QuestsFrame and qm.QuestsFrame.DetailsFrame)
        if det then
            if det.BorderFrame then det.BorderFrame:SetAlpha(0) end
            if det.SealMaterialBG then det.SealMaterialBG:SetAlpha(0) end
            WSkin.FadeRegions(det)
            WSkin.Register(det, true)
            if det.BackFrame then
                WSkin.FadeRegions(det.BackFrame)
                WSkin.Register(det.BackFrame, true)
                if det.BackFrame.BackButton then WSkin.Button(det.BackFrame.BackButton) end
            end
            for _, k in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do
                local b = det[k]
                if b then
                    WSkin.FadeRegions(b)
                    WSkin.Button(b)
                end
            end
            local rfc = det.RewardsFrameContainer
            if rfc and rfc.RewardsFrame then
                WSkin.FadeRegions(rfc.RewardsFrame)
                WSkin.Register(rfc.RewardsFrame, true)
                -- Rewards area backdrop: solid #050505 base + the guild/
                -- community sidebar card texture over it, full width/height.
                -- Stored under protected keys so a Restrip never fades them.
                local rd = GetFFD(rfc)
                if not rd.bg then
                    local base = rfc:CreateTexture(nil, "BACKGROUND", nil, -7)
                    base:SetColorTexture(0.0196, 0.0196, 0.0196, 1)   -- #050505 @ 100%
                    base:SetAllPoints(rfc)
                    rd.bg = base
                    local card = rfc:CreateTexture(nil, "BACKGROUND", nil, -6)
                    card:SetAtlas("Ui-Dialog-New-Background")
                    card:SetTexCoord(0, 1, 0, 1)
                    card:SetAlpha(0.5)
                    card:SetAllPoints(rfc)
                    rd.fill = card
                end
            end
            -- Quest detail text: section headers (title / description /
            -- objectives / rewards) = quest yellow; body text (description,
            -- objectives, group size) + the pooled objective lines = white.
            -- Re-applied whenever a quest is displayed into the map.
            local function StyleQuestText()
                for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionHeader",
                                     "QuestInfoObjectivesHeader" }) do
                    local fs = _G[n]
                    if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
                end
                local rw = _G.QuestInfoRewardsFrame
                if rw then
                    WhitenTextIn(rw)  -- catch nested spell/effect + SimpleHTML reward blurbs
                    if rw.Header and rw.Header.SetTextColor then rw.Header:SetTextColor(1, 0.82, 0) end
                end
                for _, n in ipairs({ "QuestInfoDescriptionText", "QuestInfoObjectivesText",
                                     "QuestInfoGroupSize" }) do
                    local fs = _G[n]
                    if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end
                end
                local of = _G.QuestInfoObjectivesFrame
                if of and of.Objectives then
                    for _, obj in ipairs(of.Objectives) do
                        if obj and obj.SetTextColor then obj:SetTextColor(1, 1, 1) end
                    end
                end
            end
            if not GetFFD(det).questTextHook and type(_G.QuestInfo_Display) == "function" then
                GetFFD(det).questTextHook = true
                hooksecurefunc("QuestInfo_Display", function(_, parentFrame)
                    -- Only when the quest info is displayed into the MAP (its
                    -- parent chain reaches QuestMapFrame) -- QuestInfo_Display
                    -- also drives the NPC quest window, which we must not touch.
                    if not parentFrame then return end
                    local p, isMap = parentFrame, false
                    for _i = 1, 8 do
                        if p == qm then isMap = true break end
                        p = p.GetParent and p:GetParent()
                        if not p then break end
                    end
                    if not isMap then return end
                    StyleQuestText()
                    -- Re-assert next frame: Blizzard colours objectives after
                    -- this call.
                    if C_Timer then C_Timer.After(0, StyleQuestText) end
                end)
            end
            if qm:IsShown() then StyleQuestText() end
        end
        local dsf = _G.QuestMapDetailsScrollFrame
        if dsf and dsf.ScrollBar then WSkin.ScrollBar(dsf.ScrollBar) end

        local co = qm.QuestsFrame and qm.QuestsFrame.CampaignOverview
        if co then
            if co.BorderFrame then co.BorderFrame:SetAlpha(0) end
            WSkin.FadeRegions(co)
            WSkin.Register(co, true)
            if co.ScrollFrame and co.ScrollFrame.ScrollBar then
                WSkin.ScrollBar(co.ScrollFrame.ScrollBar)
            end
        end

        if qm.QuestSessionManagement then
            WSkin.FadeRegions(qm.QuestSessionManagement)
            WSkin.Register(qm.QuestSessionManagement, true)
        end

        -- 11.1 side tabs (quests / events / map legend)
        for _, k in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
            SkinMapSideTab(qm[k])
        end
        -- Chain seat: box edge flush with the window edge (measured once on
        -- first laid-out show), gaps 8px tighter down the chain.
        local function SeatSideTabs()
            local gd2 = GetFFD(qm)
            if gd2.sideSeated then return end
            local qt = qm.QuestsTab
            local icon = qt and qt.Icon
            local qmR = qm.GetRight and qm:GetRight()
            local iL = icon and icon.GetLeft and icon:GetLeft()
            if not qmR or not iL then return end
            gd2.sideSeated = true
            local dx = math.floor((qmR - (iL - 5)) + 0.5) + 2
            if dx ~= 0 then
                local np = qt:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = qt:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, (x or 0) + dx, y or 0 }
                end
                if ok then
                    qt:ClearAllPoints()
                    for i = 1, #pts do
                        local t = pts[i]
                        qt:SetPoint(t[1], t[2], t[3], t[4], t[5])
                    end
                end
            end
            for _, k2 in ipairs({ "EventsTab", "MapLegendTab" }) do
                local tb = qm[k2]
                if tb then
                    local td2 = GetFFD(tb)
                    if not td2.gapAdj then
                        local p, rel, rp, x, y = tb:GetPoint(1)
                        if p then
                            td2.gapAdj = true
                            tb:ClearAllPoints()
                            tb:SetPoint(p, rel, rp, x or 0, (y or 0) + 8)
                        end
                    end
                end
            end
        end
        SeatSideTabs()
        if not GetFFD(qm).sideSeatHook then
            GetFFD(qm).sideSeatHook = true
            qm:HookScript("OnShow", function()
                if C_Timer then
                    C_Timer.After(0, SeatSideTabs)
                else
                    SeatSideTabs()
                end
            end)
        end

        local ev = qm.EventsFrame
        if ev then
            -- Direct region fade also kills the frame's stray yellow box
            -- texture (a Blizzard oddity on this pane).
            WSkin.FadeRegions(ev)
            WSkin.Register(ev, true)
            if ev.TitleText then WSkin.Font(ev.TitleText); WSkin.White(ev.TitleText) end
            if ev.BorderFrame then ev.BorderFrame:SetAlpha(0) end
            if ev.ScrollBox and ev.ScrollBox.Background then ev.ScrollBox.Background:SetAlpha(0) end
            if ev.ScrollBar then WSkin.ScrollBar(ev.ScrollBar) end
            -- Row styling via the acquired-frame callback (headers get the
            -- house plate + white label; event tiles get the flat white
            -- hover).
            if ev.ScrollBox and _G.ScrollUtil
                and _G.ScrollUtil.AddAcquiredFrameCallback
                and not GetFFD(ev).rowCb then
                GetFFD(ev).rowCb = true
                local function StyleEventRow(_, row, elementData)
                    if not row or type(elementData) ~= "table" then return end
                    local et = elementData.data and elementData.data.entryType
                    local rd = GetFFD(row)
                    if et == 1 or et == 3 then
                        if row.Background and row.Background.SetAlpha then
                            row.Background:SetAlpha(0)
                        end
                        if not rd.plate then
                            rd.plate = SolidTex(row, "BACKGROUND", 1, 1, 1, 0.05)
                            rd.plate:SetAllPoints(row)
                        end
                        if row.Label and row.Label.SetTextColor then
                            WSkin.White(row.Label)
                        end
                    else
                        if row.Highlight and row.Highlight.SetColorTexture then
                            row.Highlight:SetColorTexture(1, 1, 1, 0.1)
                            row.Highlight:SetAllPoints(row)
                        end
                    end
                end
                pcall(_G.ScrollUtil.AddAcquiredFrameCallback,
                    ev.ScrollBox, StyleEventRow, ev, true)
            end
        end

        local ml = qm.MapLegend
        if ml then
            if ml.TitleText then WSkin.Font(ml.TitleText); WSkin.White(ml.TitleText) end
            if ml.BorderFrame then ml.BorderFrame:SetAlpha(0) end
            local mls = ml.ScrollFrame
            if mls then
                if mls.Background then mls.Background:SetAlpha(0) end
                if mls.Center then mls.Center:SetAlpha(0) end
                if mls.ScrollBar then WSkin.ScrollBar(mls.ScrollBar) end
            end
        end
    end

    WSkin.HookShow(f, WSkin.Debounce(function()
        if f:IsVisible() then WSkin.Restrip() end
    end))
end

WSkin.RegisterWindow({
    key = "worldmap",
    addons = { Blizzard_WorldMap = true },
    apply = Skin_WorldMap,
})

-------------------------------------------------------------------------------
--  Micro Menu & Bags. The glyph IS the button's Normal/Pushed/Disabled atlas,
--  so it is never hidden -- the raised plate goes, the bevel ring is cropped
--  off, and a flat box frames it. All work is combat-guarded: micro buttons
--  are secure, so their visuals are only touched out of combat.
--  Blizzard container frames are skipped entirely when the EllesmereUI Bags
--  addon is active (they never show).
-------------------------------------------------------------------------------
local MICRO_BUTTONS = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "GuildMicroButton",
    "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
    "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
    "HousingMicroButton",
}
local MICRO_DECO  = { "Background", "PushedBackground", "FlashBorder", "Shadow", "PushedShadow", "Border", "Backdrop" }
local MICRO_TRIM  = 0.08
local MICRO_INSET = 1
local MICRO_GAP   = 2
local MICRO_BG_A  = 0.45

local function TrimMicroTex(tex, box)
    if not tex or not tex.SetTexCoord then return end
    if tex.SetDrawLayer then tex:SetDrawLayer("ARTWORK") end
    if MICRO_TRIM > 0 then tex:SetTexCoord(MICRO_TRIM, 1 - MICRO_TRIM, MICRO_TRIM, 1 - MICRO_TRIM) end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", box, "TOPLEFT", MICRO_INSET, -MICRO_INSET)
    tex:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -MICRO_INSET, MICRO_INSET)
end

local function SkinMicroButtonInner(btn)
        for _, k in ipairs(MICRO_DECO) do
            local r = btn[k]
            if r and r.SetAlpha then r:SetAlpha(0) end
        end
        local d = GetFFD(btn)
        if not d.box then
            local box = CreateFrame("Frame", nil, btn)
            box:SetPoint("TOPLEFT", MICRO_GAP, -MICRO_GAP)
            box:SetPoint("BOTTOMRIGHT", -MICRO_GAP, MICRO_GAP)
            local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
            bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, MICRO_BG_A)
            bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
            WSkin.AddBorder(box)
            d.box, d.bg = box, bg
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
            if hl and hl.SetColorTexture then
                hl:SetColorTexture(1, 1, 1, 0.1)
                if hl.SetTexCoord then hl:SetTexCoord(0, 1, 0, 1) end
                hl:ClearAllPoints()
                hl:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
                hl:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
            end
        end
        if btn.GetNormalTexture then TrimMicroTex(btn:GetNormalTexture(), d.box) end
        if btn.GetPushedTexture then TrimMicroTex(btn:GetPushedTexture(), d.box) end
        if btn.GetDisabledTexture then TrimMicroTex(btn:GetDisabledTexture(), d.box) end
        if btn.Portrait then TrimMicroTex(btn.Portrait, d.box) end
end

-- Named wrapper so the hot UpdateMicroButtons path never allocates a fresh
-- closure per call (13 buttons x every fire = real GC churn otherwise).
local function SkinMicroButton(btn)
    if not btn or btn:IsForbidden() then return end
    pcall(SkinMicroButtonInner, btn)
end

local _microHook = false
local function Skin_MicroMenu()
    if InCombatLockdown() then return end
    for _, name in ipairs(MICRO_BUTTONS) do SkinMicroButton(_G[name]) end
    if not _microHook and _G.UpdateMicroButtons then
        _microHook = true
        -- UpdateMicroButtons is a global Blizzard function fired on many routine
        -- out-of-combat events, and often several times within a single frame.
        -- Debounce collapses each burst into ONE repaint per frame instead of
        -- re-trimming all 13 buttons on every fire.
        local repaint = WSkin.Debounce(function()
            if InCombatLockdown() then return end
            for _, name in ipairs(MICRO_BUTTONS) do SkinMicroButton(_G[name]) end
        end)
        hooksecurefunc("UpdateMicroButtons", repaint)
    end
end

WSkin.RegisterWindow({
    key = "micromenu",
    apply = function()
        -- Micro buttons are secure; if this runs mid-combat (reload during a
        -- fight), defer the pass to the end of combat.
        if InCombatLockdown() then
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            w:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                pcall(Skin_MicroMenu)
            end)
            return
        end
        pcall(Skin_MicroMenu)
    end,
})

-------------------------------------------------------------------------------
--  Dressing Room (DressUpFrame)
--  Chrome + action buttons; the 3D model scene and custom-set detail panel
--  stay stock content.
-------------------------------------------------------------------------------
local _dressHooked = false
local function Skin_DressUp()
    local f = _G.DressUpFrame
    if not f then return end
    WSkin.Shell("dressup", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "DressUpFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    for _, k in ipairs({ "Bg", "Background" }) do
        if f[k] and f[k].SetAlpha then f[k]:SetAlpha(0) end
    end
    -- The window backdrop is the global DressUpFrameBg, not a parentKey.
    if _G.DressUpFrameBg and _G.DressUpFrameBg.SetAlpha then _G.DressUpFrameBg:SetAlpha(0) end
    -- The model sits inside DressUpFrameInset, which carries its OWN backdrop
    -- (Bg) and border (NineSlice) -- the chrome behind/around the model, which
    -- is separate from the window's and is what was still showing.
    local inset = f.Inset or _G.DressUpFrameInset
    if inset then WSkin.Inset(inset) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.DressUpFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    -- The 3D model area's backdrop + border sit on child frames the shell's
    -- region-fade can't reach (it only touches textures directly on the
    -- window). Fade the flat model background and the model scene's own
    -- textures/border; the model renders via actors, not textures, so it stays.
    if f.ModelBackground and f.ModelBackground.SetAlpha then f.ModelBackground:SetAlpha(0) end
    local ms = f.ModelScene
    if ms then
        WSkin.FadeRegions(ms)
        if ms.NineSlice then WSkin.FadeNineSlice(ms.NineSlice) end
        WSkin.Register(ms, true)
    end
    -- Max/Min button: spellbook-style +/- glyph (collapse/expand chevrons).
    local mm = f.MaximizeMinimizeFrame
    if mm then
        SkinProfMaxMin(mm.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
        SkinProfMaxMin(mm.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
    end
    -- Action buttons (Reset/Cancel are globals; Link/Toggle are parentKeys) get
    -- the flat treatment with white labels.
    local function SkinBtn(b)
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end
    SkinBtn(_G.DressUpFrameResetButton)
    SkinBtn(_G.DressUpFrameCancelButton)
    SkinBtn(f.LinkButton)
    -- ToggleCustomSetDetailsButton (opens the appearance list) stays fully
    -- stock -- no box, border, or hover of ours.
    -- Saved-outfit dropdown (10% smaller), shifted down 4px (its child save
    -- button rides along); save button 3px taller. Blizzard re-anchors the
    -- dropdown per view (minimize/maximize), so re-apply the 4px offset on
    -- every SetPoint (reentry-guarded) rather than once.
    local dd = f.CustomSetDropdown or _G.DressUpFrameCustomSetDropdown
    if dd then
        WSkin.Dropdown(dd)
        local ddd = GetFFD(dd)
        if not ddd.scaled then
            ddd.scaled = true
            dd:SetScale(0.9)
        end
        if not ddd.shiftHook then
            ddd.shiftHook = true
            local guard = false
            hooksecurefunc(dd, "SetPoint", function(self)
                if guard then return end
                guard = true
                local p, rel, rp, x, y = self:GetPoint(1)
                if p then
                    self:ClearAllPoints()
                    self:SetPoint(p, rel, rp, x or 0, (y or 0) - 4)
                end
                guard = false
            end)
            local p, rel, rp, x, y = dd:GetPoint(1)
            if p then dd:SetPoint(p, rel, rp, x or 0, y or 0) end
        end
        local sb = dd.SaveButton
        if sb then
            SkinBtn(sb)
            local sbd = GetFFD(sb)
            if not sbd.heightBumped and sb.GetHeight then
                sbd.heightBumped = true
                sb:SetHeight(sb:GetHeight() + 3)
            end
        end
    end
    -- Outfit selection list: fade its framed chrome, theme the scrollbar.
    local ssp = f.SetSelectionPanel
    if ssp then
        if ssp.NineSlice then WSkin.FadeNineSlice(ssp.NineSlice) end
        if ssp.Bg and ssp.Bg.SetAlpha then ssp.Bg:SetAlpha(0) end
        WSkin.ScrollBarsIn(ssp)
    end
    -- Custom-set details panel: replace ONLY its border. Fade the border art
    -- (OVERLAY/BORDER layers) but spare the named black/class backdrops by
    -- identity so they stay, then seat a themed border sized to the backdrop
    -- so it hugs the content area instead of the padded frame edge.
    local dp = f.CustomSetDetailsPanel
    if dp then
        local dd = GetFFD(dp)
        if not dd.bordered then
            dd.bordered = true
            local keep = {}
            if dp.BlackBackground then keep[dp.BlackBackground] = true end
            if dp.ClassBackground then keep[dp.ClassBackground] = true end
            for i = 1, select("#", dp:GetRegions()) do
                local r = select(i, dp:GetRegions())
                if r and not keep[r] and r.IsObjectType and r:IsObjectType("Texture") then
                    local layer = r:GetDrawLayer()
                    if layer == "OVERLAY" or layer == "BORDER" then r:SetAlpha(0) end
                end
            end
            if dp.NineSlice then WSkin.FadeNineSlice(dp.NineSlice) end
            local bg = dp.BlackBackground or dp.ClassBackground
            if bg then
                local host = CreateFrame("Frame", nil, dp)
                host:SetAllPoints(bg)
                dd.borderHost = host
                WSkin.AddBorder(host)
            end
        end
        WSkin.ScrollBarsIn(dp)
    end
    -- Blizzard re-shows the window chrome (NineSlice / Bg / model backdrop)
    -- every time the frame opens, so re-run the full skin on show rather than
    -- only a Restrip. Install once.
    if not _dressHooked then
        _dressHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_DressUp() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "dressup",
    apply = Skin_DressUp,
})

-------------------------------------------------------------------------------
--  Transmogrifier (TransmogFrame)
--  Chrome + action controls; the model, transmog slot buttons, and embedded
--  appearance list stay stock content for this first pass.
-------------------------------------------------------------------------------
local _transmogHooked = false
local function Skin_Transmog()
    local f = _G.TransmogFrame
    if not f then return end
    WSkin.Shell("transmog", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "TransmogFrame")   -- close + paging + controls
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Inset then WSkin.Inset(f.Inset) end
    for _, k in ipairs({ "Bg", "Background" }) do
        if f[k] and f[k].SetAlpha then f[k]:SetAlpha(0) end
    end
    if _G.TransmogFrameBg and _G.TransmogFrameBg.SetAlpha then _G.TransmogFrameBg:SetAlpha(0) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.TransmogFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    if f.ApplyButton then WSkin.Button(f.ApplyButton); WSkin.WhiteButtonLabel(f.ApplyButton) end
    local od = f.OutfitDropdown
    if od then
        WSkin.Dropdown(od)
        if od.SaveButton then WSkin.Button(od.SaveButton); WSkin.WhiteButtonLabel(od.SaveButton) end
    end
    -- Save Outfit button: flat treatment, but its label mirrors the native
    -- enabled/disabled states -- white when clickable, gray when not (a plain
    -- WhiteButtonLabel would leave a disabled button reading as active).
    local oc = f.OutfitCollection
    if oc and oc.SaveOutfitButton then
        local b = oc.SaveOutfitButton
        WSkin.Button(b)
        -- Borderless + 2px shorter (this button only).
        local PPb = EllesmereUI.PP
        if PPb and PPb.GetBorders and PPb.HideBorder and PPb.GetBorders(b) then
            PPb.HideBorder(b)
        end
        local bd0 = GetFFD(b)
        if not bd0.slimmed then
            bd0.slimmed = true
            local h = b:GetHeight()
            if h and h > 2 then b:SetHeight(h - 2) end
        end
        local lab = b.Text or (b.GetFontString and b:GetFontString())
        if lab then
            local function reflect()
                if b:IsEnabled() then WSkin.White(lab) else lab:SetTextColor(0.5, 0.5, 0.5) end
            end
            local bd = GetFFD(b)
            if not bd.stateHook then
                bd.stateHook = true
                b:HookScript("OnEnable", reflect)
                b:HookScript("OnDisable", reflect)
            end
            reflect()
        end
    end
    -- Right-side appearance browser: flatten the tab headers (standard
    -- lighter-active look) and left-align the Sources filter label on both
    -- the items and sets views. The header row sits 10px higher than stock.
    local wc = f.WardrobeCollection
    if wc then
        if wc.TabHeaders then
            for i = 1, select("#", wc.TabHeaders:GetChildren()) do
                local tab = select(i, wc.TabHeaders:GetChildren())
                if tab and tab.GetObjectType and tab:GetObjectType() == "Button" then
                    WSkin.Tab(tab)
                    -- Blizzard's own active-line effect is a SelectedHighlight
                    -- CHILD frame (the tab region sweep can't reach it);
                    -- container alpha suppresses it and its textures.
                    if tab.SelectedHighlight and tab.SelectedHighlight.SetAlpha then
                        tab.SelectedHighlight:SetAlpha(0)
                    end
                end
            end
            local th = wc.TabHeaders
            if not GetFFD(th).raised then
                local np = th:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = th:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) + 6 }
                end
                if ok then
                    GetFFD(th).raised = true
                    th:ClearAllPoints()
                    for i = 1, #pts do local t = pts[i]; th:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                end
            end
        end
        local tc = wc.TabContent
        if tc then
            for _, k in ipairs({ "ItemsFrame", "SetsFrame" }) do
                local sub = tc[k]
                if sub and sub.FilterButton then LeftAlignFilterLabel(sub.FilterButton) end
            end
            local csf = tc.CustomSetsFrame
            if csf and csf.NewCustomSetButton then
                WSkin.Button(csf.NewCustomSetButton)
                WSkin.WhiteButtonLabel(csf.NewCustomSetButton)
            end
            local sif = tc.SituationsFrame
            if sif and sif.DefaultsButton then
                WSkin.Button(sif.DefaultsButton)
                WSkin.WhiteButtonLabel(sif.DefaultsButton)
            end
            -- Swap Blizzard's content border for the themed one. The frame's
            -- rect runs a few px past the visible list; its Background region
            -- spans the true content area, so the border seats on a host
            -- pinned to that (details-panel pattern).
            local bd = tc.Border
            if bd then
                if bd.IsObjectType and bd:IsObjectType("Texture") then
                    bd:SetAlpha(0)
                else
                    WSkin.FadeRegions(bd)
                    WSkin.Register(bd, true)
                    if bd.SetAlpha then bd:SetAlpha(0) end
                end
            end
            local tcd = GetFFD(tc)
            if not tcd.borderHost then
                local host = CreateFrame("Frame", nil, tc)
                host:SetAllPoints(tc.Background or tc)
                tcd.borderHost = host
                WSkin.AddBorder(host)
            end
        end
    end
    -- Blizzard re-shows the window chrome on open (learned from DressUpFrame),
    -- so re-run the full skin on show. Install once.
    if not _transmogHooked then
        _transmogHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Transmog() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "transmog",
    addons = { Blizzard_Transmog = true },
    apply = Skin_Transmog,
})

-------------------------------------------------------------------------------
--  Merchant (MerchantFrame)
--  Shell + tabs + item tiles as flat cards (mail-row treatment). The repair /
--  sell-junk icon buttons and the buyback money display stay stock content.
-------------------------------------------------------------------------------
-- Completely hide Blizzard's native pagination and 10-slot grid.
-- Permanence via the achievements-pack Kill pattern: a reentry-safe
-- hooksecurefunc that re-hides on every Blizzard Show (MerchantFrame_Update
-- re-Shows the tiles each pass) -- never a method overwrite on a Blizzard
-- frame table. Registry lives on WSkin so re-runs of Skin_Merchant cannot
-- double-hook.
local function KillFrameShow(frame)
    if not frame then return end
    local killed = WSkin._merchantKilledShow
    if not killed then
        killed = setmetatable({}, { __mode = "k" })
        WSkin._merchantKilledShow = killed
    end
    if killed[frame] then frame:Hide() return end
    killed[frame] = true
    frame:Hide()
    hooksecurefunc(frame, "Show", function(self) self:Hide() end)
end

local function HideNativeMerchantGrid()
    for i = 1, 12 do
        local item = _G["MerchantItem" .. i]
        if item then
            item:SetAlpha(0)
            KillFrameShow(item)
        end
    end

    local controls = {
        _G.MerchantPrevPageButton,
        _G.MerchantNextPageButton,
        _G.MerchantPageText
    }
    for _, ctrl in ipairs(controls) do
        KillFrameShow(ctrl)
    end
end

-- Initialize the ScrollFrame (Run once)
local function CreateMerchantScrollList(parent)
    local sf = CreateFrame("ScrollFrame", "WSkinMerchantScrollFrame", parent, "UIPanelScrollFrameTemplate")
    -- Anchor to fit within MerchantFrame, leaving room for repair/buyback... buttons
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -70)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -32, 80)

    local child = CreateFrame("Frame", "WSkinMerchantScrollChild", sf)
    child:SetPoint("TOPLEFT")
    child:SetPoint("TOPRIGHT")
    child:SetSize(1, 1)
    sf:SetScrollChild(child)

    sf.rows = {}
    return sf, child
end

-- This is the same function as the default UI, only the frameName is changed to allow our custom buttons
function EUI_MerchantFrame_UpdateAltCurrency(index, indexOnPage, canAfford)
	local itemCount = GetMerchantItemCostInfo(index);
	local frameName = "EUI_MerchantItem"..indexOnPage.."AltCurrencyFrame";
	local usedCurrencies = 0;
	local width = 0;

	-- update Alt Currency Frame with itemValues
	if ( itemCount > 0 ) then
		for i=1, MAX_ITEM_COST do
			local itemTexture, itemValue, itemLink = GetMerchantItemCostItem(index, i);
			if ( itemTexture ) then
				usedCurrencies = usedCurrencies + 1;
				local button = _G[frameName.."Item"..usedCurrencies];
				button.index = index;
				button.item = i;
				button.itemLink = itemLink;
				AltCurrencyFrame_Update(frameName.."Item"..usedCurrencies, itemTexture, itemValue, canAfford);
				width = width + button:GetWidth();
				if ( usedCurrencies > 1 ) then
					-- button spacing;
					width = width + 4;
				end
				button:Show();
			end
		end
		for i = usedCurrencies + 1, MAX_ITEM_COST do
			_G[frameName.."Item"..i]:Hide();
		end
	else
		for i=1, MAX_ITEM_COST do
			_G[frameName.."Item"..i]:Hide();
		end
	end
	return width;
end

local function SkinMerchantListItem(item)
    if not item or item:IsForbidden() then return end

    -- Background & Theme
    item.bg = item.bg or item:CreateTexture(nil, "BACKGROUND", nil, -7)
    item.bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    item.bg:SetPoint("TOPLEFT", 0, 0)
    item.bg:SetPoint("BOTTOMRIGHT", 0, 0)
    WSkin.AddBorder(item)

    -- Item Icon
    item.SlotTexture:SetSize(item:GetHeight(), item:GetHeight()) --Square shape
    item.SlotTexture:ClearAllPoints()
    item.SlotTexture:SetPoint("LEFT", item, "LEFT", 0, 0)
    item.SlotTexture:SetTexCoord(0, 1, 0, 1)

    -- Highlight on hover
    item.highlight = item.highlight or item.ItemButton:CreateTexture(nil, "HIGHLIGHT")
    item.highlight:SetColorTexture(1, 1, 1, 0.1)
    item.highlight:SetAllPoints(item.bg)

    -- Buy button: As a list, this is the whole row
    item.ItemButton:SetSize(item:GetWidth(), item:GetHeight())
    item.ItemButton.PushedTexture:SetTexture(nil)
    item.ItemButton.NormalTexture:SetTexture(nil)
    item.ItemButton.HighlightTexture:SetTexture(item.highlight)

    -- Borders: Quality border, azerite armor overlay...
    -- Repositionned on the icon
    item.ItemButton.IconBorder:ClearAllPoints()
    item.ItemButton.IconBorder:SetPoint("CENTER", item.SlotTexture, "CENTER", 0, 0)
    item.ItemButton.IconBorder:SetSize(item.SlotTexture:GetWidth(), item.SlotTexture:GetHeight())
    item.ItemButton.IconOverlay:ClearAllPoints()
    item.ItemButton.IconOverlay:SetPoint("CENTER", item.SlotTexture, "CENTER", 0, 0)
    item.ItemButton.IconOverlay:SetSize(item.SlotTexture:GetWidth(), item.SlotTexture:GetHeight())

    -- Quest item overlay
    -- Repositionned on the icon
    item.ItemButton.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG);
    item.ItemButton.IconQuestTexture:ClearAllPoints()
    item.ItemButton.IconQuestTexture:SetPoint("CENTER", item.SlotTexture, "CENTER", 0, 0)
    item.ItemButton.IconQuestTexture:SetSize(item.SlotTexture:GetWidth(), item.SlotTexture:GetHeight())

    -- Item stack
    -- Bottom right of the icon
    item.ItemButton.Count:ClearAllPoints()
    item.ItemButton.Count:SetPoint("BOTTOMRIGHT", item.SlotTexture, "BOTTOMRIGHT", -2, 2)

    -- Item stock
    -- Top left of the icon
    item.ItemButton.Stock:ClearAllPoints()
    item.ItemButton.Stock:SetPoint("TOPLEFT", item.SlotTexture, "TOPLEFT", 2, -2)

    -- Item Name
    -- Position is set dynamically in UpdateCustomMerchantList so that it never collides with
    -- either the money frame or alt currency frame. If the text is too long, it will be cut (...)
    _G[item:GetName().."NameFrame"]:Hide()
    item.Name:ClearAllPoints()
    item.Name:SetPoint("LEFT", item.SlotTexture, "RIGHT", 10, 0)
    item.Name:SetMaxLines(1)
    item.Name:SetJustifyH("LEFT")
end

-- Update loop to populate our custom scrolling list
local function UpdateCustomMerchantList(sf, child)
    local isBuyback = MerchantFrame.selectedTab == 2
    local numItems = isBuyback and GetNumBuybackItems() or GetMerchantNumItems()

    local rowHeight = (EllesmereUIDB and EllesmereUIDB.merchantListRowHeight) or 32
    local rowSpacing = 4
    local playerMoney = GetMoney()
    local MAX_MONEY_DISPLAY_WIDTH = 120

    for i = 1, numItems do
        local row = sf.rows[i]
        if not row then
            row = CreateFrame("Button", "EUI_MerchantItem"..i, child, "MerchantItemTemplate")
            row:SetSize(sf:GetWidth(), rowHeight)
            if i == 1 then
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", sf.rows[i-1], "BOTTOMLEFT", 0, -rowSpacing)
            end

            SkinMerchantListItem(row)
            sf.rows[i] = row
        end

        local name, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost, isBound, isQuestStartItem

        if isBuyback then
            name, texture, price, quantity, numAvailable, isUsable, isBound = GetBuybackItemInfo(i)
            isPurchasable = true -- Buyback items are always implicitly purchasable
        else
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then
                if info.currencyID then
                    name, texture, numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(info.currencyID, info.numAvailable, info.name, info.texture, nil);
                else
                    name, texture, numAvailable = info.name, info.texture, info.numAvailable
                end

                price, quantity, isPurchasable, isUsable, extendedCost, isQuestStartItem =
                    info.price, info.stackCount, info.isPurchasable, info.isUsable, info.hasExtendedCost, info.isQuestStartItem
            end
        end

        if name then
            local itemLink = isBuyback and GetBuybackItemLink(i) or GetMerchantItemLink(i)

            row.Name:SetText(name)
            row.SlotTexture:SetTexture(texture)

            row.ItemButton:SetID(i)
            row.ItemButton.link = itemLink
            row.ItemButton.name = name
            row.ItemButton.texture = texture
            row.ItemButton.price = ((extendedCost and (price > 0)) or not extendedCost) and price or nil
            row.ItemButton.extendedCost = (extendedCost and type(price) == "number") or nil
            row.ItemButton.hasItem = true
            row.ItemButton.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(i)

            -- Text color and reagent quality overlay
            MerchantFrameItem_UpdateQuality(row, row.ItemButton.link, isBound)

            -- Stack & Stock
            SetItemButtonCount(row.ItemButton, quantity)
            SetItemButtonStock(row.ItemButton, numAvailable)

            -- Quest item overlay
            if isQuestStartItem then
				row.ItemButton.IconQuestTexture:Show();
			else
				row.ItemButton.IconQuestTexture:Hide();
			end

            -- Money & currency cost
            local moneyFrame = _G["EUI_MerchantItem"..i.."MoneyFrame"]
            local altCurrencyFrame = _G["EUI_MerchantItem"..i.."AltCurrencyFrame"]
            local canAfford = true
            if isBuyback then
                canAfford = playerMoney >= price
            else
                canAfford = CanAffordMerchantItem(i)
            end

            -- Reset all dynamic anchors to prevent layout conflicts
            row.Name:ClearAllPoints()
            row.Name:SetPoint("LEFT", row.SlotTexture, "RIGHT", 10, 0)
            moneyFrame:ClearAllPoints()
            altCurrencyFrame:ClearAllPoints()

            if (extendedCost and (price <= 0)) then
                -- Case 1: Alt currency only
                local altCurrencyWidth = EUI_MerchantFrame_UpdateAltCurrency(i, i, canAfford)
                altCurrencyFrame:SetWidth(altCurrencyWidth)

                altCurrencyFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)

                altCurrencyFrame:Show()
                moneyFrame:Hide()

                row.Name:SetPoint("RIGHT", altCurrencyFrame, "LEFT", -10, 0)
            elseif (extendedCost and (price > 0)) then
                -- Case 2: Both Money and Alt currency
                local altCurrencyWidth = EUI_MerchantFrame_UpdateAltCurrency(i, i, canAfford)
                altCurrencyFrame:SetWidth(altCurrencyWidth)

                MoneyFrame_SetMaxDisplayWidth(moneyFrame, MAX_MONEY_DISPLAY_WIDTH - altCurrencyWidth)
                MoneyFrame_Update(moneyFrame:GetName(), price)

                local color = (canAfford == false) and "gray" or nil
                SetMoneyFrameColor(moneyFrame:GetName(), color)

                -- Sometimes, altCurrencyWidth can be 0, indicating no alt currency cost even though hasExtendedCost is true
                -- When this happen, fallback to the anchors we do in case 3
                if altCurrencyWidth > 0 then
                    -- Both exist: Anchor money to alt currency
                    altCurrencyFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                    moneyFrame:SetPoint("RIGHT", altCurrencyFrame, "LEFT", -5, 0)
                    row.Name:SetPoint("RIGHT", altCurrencyFrame, "LEFT", -10, 0)
                    altCurrencyFrame:Show()
                else
                    -- Only money exists: fallback to case 3
                    moneyFrame:SetPoint("RIGHT", row, "RIGHT", 3, 0)
                    row.Name:SetPoint("RIGHT", moneyFrame, "LEFT", -10, 0)
                    altCurrencyFrame:Hide()
                end
                moneyFrame:Show()
            else
                -- Case 3: Money only
                MoneyFrame_SetMaxDisplayWidth(moneyFrame, MAX_MONEY_DISPLAY_WIDTH)
                MoneyFrame_Update(moneyFrame:GetName(), price)

                local color = (canAfford == false) and "gray" or nil
                SetMoneyFrameColor(moneyFrame:GetName(), color)

                moneyFrame:SetPoint("RIGHT", row, "RIGHT", 3, 0)

                altCurrencyFrame:Hide()
                moneyFrame:Show()

                row.Name:SetPoint("RIGHT", moneyFrame, "LEFT", -10, 0)
            end

            local merchantItemID = GetMerchantItemID(i)
            local isHeirloom = merchantItemID and C_Heirloom.IsItemHeirloom(merchantItemID)
			local isKnownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(merchantItemID)

            local redTint = (not isUsable and not isHeirloom) or (not isBuyback and not isPurchasable)

            -- Fade if not usable/affordable/already known heirloom
            row.SlotTexture:SetDesaturated(not isBuyback and isKnownHeirloom)
            if not isBuyback and (numAvailable == 0 or isKnownHeirloom) then
                -- If not available and not usable
                if redTint then
                    row.SlotTexture:SetVertexColor(0.5, 0, 0)
                else
                    row.SlotTexture:SetVertexColor(0.5, 0.5, 0.5)
                end
            elseif redTint then
                row.SlotTexture:SetVertexColor(1, 0, 0)
            else
                row.SlotTexture:SetVertexColor(1, 1, 1)
            end

            row:Show()
        else
            row:Hide()
        end
    end

    -- Hide unused rows
    for i = numItems + 1, #sf.rows do
        sf.rows[i]:Hide()
    end
end

-- Options toggle entry point: re-sync height
EllesmereUI._Merchant_RefreshRowHeight = function()
    local f = _G.MerchantFrame
    if not f then return end
    if not EllesmereUIDB.merchantShowAsList or not (f.wSkinScrollFrame and f.wSkinScrollChild) then return end

    local rowHeight = (EllesmereUIDB and EllesmereUIDB.merchantListRowHeight) or 32
    -- Rows are cached so update manually each existing rows
    -- New rows created after will have the correct height by default.
    for _, row in ipairs(f.wSkinScrollFrame.rows or {}) do
        row:SetHeight(rowHeight)
        SkinMerchantListItem(row)
    end

    -- Force a full update if change is done while merchant frame is open
    if f:IsVisible() then
        UpdateCustomMerchantList(f.wSkinScrollFrame, f.wSkinScrollChild)
    end
end

-- Vendor item tile: parchment gone, flat card, white name, squared icon.
local function SkinMerchantTile(item)
    if not item or item:IsForbidden() then return end
    local d = GetFFD(item)
    if not d.bg then
        WSkin.FadeRegions(item)
        local bg = item:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        bg:SetPoint("TOPLEFT", 2, -1)
        bg:SetPoint("BOTTOMRIGHT", -2, 1)
        d.bg = bg
        WSkin.AddBorder(item)
    end
    local name = item.GetName and item:GetName()
    -- Blizzard repaints the slot/tile art per page flip; re-fade each pass,
    -- sparing our card fill.
    local keep = { [d.bg] = true }
    WSkin.FadeRegions(item, keep)
    local nameFS = item.Name or (name and _G[name .. "Name"])
    if nameFS then
        -- Leave the font AND color alone -- keep Blizzard's native item-quality
        -- coloring and font on the name. Only apply the 2-line wrap/truncate.
        if nameFS.SetWordWrap then nameFS:SetWordWrap(true) end
        if nameFS.SetMaxLines then nameFS:SetMaxLines(2) end
    end
    local btn = item.ItemButton or (name and _G[name .. "ItemButton"])
    if btn then SkinMailItemButton(btn) end
end

-- Lift a tile's currency display (money / alt-currency frame) 6px above
-- Blizzard's seat. Blizzard re-anchors these inside MerchantFrame_Update
-- (anchor depends on price vs extended cost), so a one-shot capture would be
-- wiped per update: instead hook SetPoint and re-apply the offset relative to
-- the LIVE just-set position (reads fresh stock each time). Applied
-- SYNCHRONOUSLY inside the hook -- deferring to the next frame rendered the
-- currency at Blizzard's spot for one frame, then visibly shifted it up. These
-- frames are single-anchor, so the reentry guard alone prevents a double-lift.
local function LiftMerchantCurrency(fr)
    if not fr or GetFFD(fr).liftHook then return end
    GetFFD(fr).liftHook = true
    local applying = false
    local function Apply()
        if applying then return end
        local np = fr:GetNumPoints() or 0
        local pts, ok = {}, np > 0
        for i = 1, np do
            local p, rel, rp, x, y = fr:GetPoint(i)
            if not p then ok = false break end
            pts[i] = { p, rel, rp, x or 0, (y or 0) + 6 }
        end
        if ok then
            applying = true
            fr:ClearAllPoints()
            for i = 1, #pts do local t = pts[i]; fr:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            applying = false
        end
    end
    hooksecurefunc(fr, "SetPoint", Apply)
    Apply()
end

-- Bottom-left icon buttons (repair item / repair all / guild repair / sell
-- junk): the pictured icon is the button's FIRST texture region, cropped out
-- of a shared sheet -- its texcoords must be kept (no SquareIcon). Fade the
-- box art around it, seat the flat fill + themed border + white hover.
local function SkinMerchantIconButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    local icon = btn.Icon or select(1, btn:GetRegions())
    if not d.bg then
        local fill = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        fill:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        fill:SetAllPoints(btn)
        d.bg = fill
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetColorTexture(1, 1, 1, 0.1)
        hover:SetAllPoints(btn)
        d.hover = hover
        if icon and icon.ClearAllPoints then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
        end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                         "GetDisabledTexture", "GetHighlightTexture" }) do
        local t = btn[g] and btn[g](btn)
        if t and t ~= icon and t.SetAlpha then t:SetAlpha(0) end
    end
    for i = 1, select("#", btn:GetRegions()) do
        local r = select(i, btn:GetRegions())
        if r and r ~= icon and r ~= d.bg and r ~= d.hover
           and r.IsObjectType and r:IsObjectType("Texture") then
            r:SetAlpha(0)
        end
    end
end

local _merchantHooked = false
local function Skin_Merchant()
    local f = _G.MerchantFrame
    if not f then return end
    WSkin.Shell("merchant", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "MerchantFrame")   -- close + FilterDropdown
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Inset then WSkin.Inset(f.Inset) end
    if _G.MerchantFrameBg then _G.MerchantFrameBg:SetAlpha(0) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.MerchantNameText
    if title then WSkin.Font(title); WSkin.White(title) end

    -- Money / alt-currency wells along the bottom.
    for _, n in ipairs({ "MerchantMoneyInset", "MerchantExtraCurrencyInset" }) do
        if _G[n] then WSkin.Inset(_G[n]) end
    end
    for _, n in ipairs({ "MerchantMoneyBg", "MerchantExtraCurrencyBg" }) do
        local el = _G[n]
        if el then WSkin.FadeRegions(el); WSkin.Register(el, true) end
    end

    if EllesmereUIDB.merchantShowAsList then
        HideNativeMerchantGrid()

        if not f.wSkinScrollFrame then
            local sf, child = CreateMerchantScrollList(f)
            f.wSkinScrollFrame = sf
            f.wSkinScrollChild = child
        end
    else
        -- Item tiles (10 merchant + the buyback page reuses up to 12) and the
        -- most-recent-buyback slot on the merchant tab.
        for i = 1, 12 do SkinMerchantTile(_G["MerchantItem" .. i]) end
        SkinMerchantTile(_G.MerchantBuyBackItem)
        -- Main grid 3px lower: MerchantItem1 is the chain root (the other tiles
        -- anchor off it), so one shift moves the grid. MerchantBuyBackItem anchors
        -- to the frame separately and stays put. One-shot, all points preserved.
        local it1 = _G.MerchantItem1
        if it1 and not GetFFD(it1).shifted then
            local np = it1:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = it1:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 3 }
            end
            if ok then
                GetFFD(it1).shifted = true
                it1:ClearAllPoints()
                for i = 1, #pts do local t = pts[i]; it1:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            end
        end
        -- Currency text/icons ride 10px higher on every tile (not the buyback slot).
        for i = 1, 12 do
            LiftMerchantCurrency(_G["MerchantItem" .. i .. "MoneyFrame"])
            LiftMerchantCurrency(_G["MerchantItem" .. i .. "AltCurrencyFrame"])
        end

        SkinLabeledPageButton(_G.MerchantPrevPageButton, "<")
        SkinLabeledPageButton(_G.MerchantNextPageButton, ">", 2)
    end

    -- Bottom-left icon buttons (guild repair only exists in a guild).
    for _, n in ipairs({ "MerchantRepairItemButton", "MerchantRepairAllButton",
                         "MerchantGuildBankRepairButton", "MerchantSellAllJunkButton" }) do
        SkinMerchantIconButton(_G[n])
    end
    if _G.MerchantPageText then WSkin.Font(_G.MerchantPageText); WSkin.White(_G.MerchantPageText) end

    -- Tabs
    local mTabs = {}
    for i = 1, 2 do
        local tab = _G["MerchantFrameTab" .. i]
        if tab then WSkin.Tab(tab); mTabs[#mTabs + 1] = tab end
    end
    WSkin.NormalizeTabRow(mTabs)

    if not _merchantHooked then
        _merchantHooked = true
        -- Blizzard re-textures the tiles on every page flip / tab swap /
        -- vendor open; re-run the tile pass (idempotent) on its repaint.
        if type(_G.MerchantFrame_Update) == "function" then
            hooksecurefunc("MerchantFrame_Update", WSkin.Debounce(function()
                if f:IsVisible() then
                    if EllesmereUIDB.merchantShowAsList and f.wSkinScrollFrame then
                        UpdateCustomMerchantList(f.wSkinScrollFrame, f.wSkinScrollChild)
                    else
                        for i = 1, 12 do SkinMerchantTile(_G["MerchantItem" .. i]) end
                        SkinMerchantTile(_G.MerchantBuyBackItem)
                    end
                end
            end))
        end
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Merchant() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "merchant",
    apply = Skin_Merchant,
})

-------------------------------------------------------------------------------
--  Merchant item-level overlay (QoL, independent of the Merchant reskin).
--  Shows the item level on the top-left of each vendor tile for gear
--  (weapons/armor) when EllesmereUIDB.merchantShowItemLevel is set. Buttons
--  carry their merchant slot index as their ID (Blizzard's MerchantFrame_Update
--  sets it), so we resolve the link straight from GetMerchantItemLink.
-------------------------------------------------------------------------------
local MERCHANT_ILVL_WEAPON = Enum.ItemClass.Weapon
local MERCHANT_ILVL_ARMOR  = Enum.ItemClass.Armor

local function UpdateMerchantItemLevels()
    local f = _G.MerchantFrame
    if not f then return end
    local show = EllesmereUIDB and EllesmereUIDB.merchantShowItemLevel == true
    local onSellTab = (f.selectedTab or 1) == 1
    local numItems
    if EllesmereUIDB.merchantShowAsList then
        -- No need to check GetNumBuybackItems as the text is only visible on the sell tab
        numItems = GetMerchantNumItems()
    else
        numItems = 12
    end
    local render = show and onSellTab and f:IsVisible()
    for i = 1, numItems do
        local btn
        if EllesmereUIDB.merchantShowAsList then
            btn = _G["EUI_MerchantItem" .. i .. "ItemButton"]
        else
            btn = _G["MerchantItem" .. i .. "ItemButton"]
        end
        if btn then
            -- FontString ref lives in the engine FFD, never on Blizzard's
            -- button table. Read without creating so the disabled path costs
            -- one weak-table lookup per slot.
            local fd = FFD[btn]
            local fs = fd and fd.merchantILvl
            if not render then
                if fs then fs:SetText("") end
            else
                if not fs then
                    fs = btn:CreateFontString(nil, "OVERLAY", nil, 7)
                    if EllesmereUIDB.merchantShowAsList then
                        fs:SetPoint("TOPLEFT", _G["EUI_MerchantItem" .. i .. "SlotTexture"], "TOPLEFT", 1, -1)
                    else
                        fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                    end
                    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                    local flag = (EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE"
                    fs:SetFont(path, 12, flag)
                    GetFFD(btn).merchantILvl = fs
                end
                fs:SetText("")
                local index = btn:GetID()
                local link = index and index > 0 and GetMerchantItemLink(index)
                if link then
                    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
                    if classID == MERCHANT_ILVL_WEAPON or classID == MERCHANT_ILVL_ARMOR then
                        local ilvl = C_Item.GetDetailedItemLevelInfo(link)
                        if ilvl and ilvl > 0 then
                            fs:SetText(ilvl)
                            local quality = select(3, C_Item.GetItemInfo(link))
                            local r, g, b = 1, 1, 1
                            if EllesmereUI.GetItemLevelColor then
                                local c = EllesmereUI.GetItemLevelColor(link, quality)
                                if c then r, g, b = c.r or 1, c.g or 1, c.b or 1 end
                            elseif quality then
                                r, g, b = C_Item.GetItemQualityColor(quality)
                            end
                            fs:SetTextColor(r, g, b, 1)
                        end
                    end
                end
            end
        end
    end
end

local _merchantILvlHooked = false
local function EnsureMerchantILvlHook()
    if _merchantILvlHooked then return end
    _merchantILvlHooked = true
    if type(_G.MerchantFrame_Update) == "function" then
        hooksecurefunc("MerchantFrame_Update", WSkin.Debounce(UpdateMerchantItemLevels))
    end
end

-- The MerchantFrame_Update hook is what renders the item levels; it installs
-- once the toggle is on and stays (cheap: MerchantFrame_Update only fires
-- while a merchant is up, and the updater no-ops when the toggle is off). It
-- must NOT be gated on MerchantFrame:IsVisible(): MERCHANT_SHOW fires before
-- Blizzard shows the frame, so IsVisible() is false there and the hook would
-- never install. GET_ITEM_INFO_RECEIVED fires on every item-cache resolve
-- suite-wide, so it is registered ONLY while a merchant is actually open
-- (tracked by an explicit flag, not visibility) AND the toggle is on.
local mILvlBoot = CreateFrame("Frame")
local _merchantOpen = false
local function SyncMerchantILvlEvents()
    local on = EllesmereUIDB and EllesmereUIDB.merchantShowItemLevel == true
    if on then EnsureMerchantILvlHook() end
    if on and _merchantOpen then
        mILvlBoot:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        mILvlBoot:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

-- Options toggle entry point: re-sync listeners, then render or clear.
EllesmereUI._Merchant_RefreshItemLevels = function()
    SyncMerchantILvlEvents()
    UpdateMerchantItemLevels()
end

mILvlBoot:RegisterEvent("MERCHANT_SHOW")
mILvlBoot:RegisterEvent("MERCHANT_CLOSED")
mILvlBoot:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        _merchantOpen = true
        SyncMerchantILvlEvents()
        UpdateMerchantItemLevels()
    elseif event == "MERCHANT_CLOSED" then
        _merchantOpen = false
        SyncMerchantILvlEvents()
    else -- GET_ITEM_INFO_RECEIVED: an item's data resolved while shopping
        UpdateMerchantItemLevels()
    end
end)

-------------------------------------------------------------------------------
--  Class / Profession Trainer (ClassTrainerFrame, Blizzard_TrainerUI)
--  Portrait frame: flat chrome, squared skill-row icons, native availability
--  text color kept (green/red/gray -- like item rarity, we never force white),
--  flat train button.
-------------------------------------------------------------------------------
-- One skill row: squared icon, font-only text (keep Blizzard's availability
-- color), box art off, flat selection + hover washes.
local function SkinTrainerRow(row)
    if not row or row:IsForbidden() then return end
    if row.icon then WSkin.SquareIcon(row.icon, row) end
    if row.name then WSkin.Font(row.name) end
    if row.subText then WSkin.Font(row.subText) end
    local nt = row.GetNormalTexture and row:GetNormalTexture()
    if nt and nt.SetAlpha then nt:SetAlpha(0) end
    if row.disabledBG and row.disabledBG.SetAlpha then row.disabledBG:SetAlpha(0) end
    if row.selectedTex and row.selectedTex.SetColorTexture then
        row.selectedTex:SetColorTexture(1, 1, 1, 0.15)
    end
    local hl = row.GetHighlightTexture and row:GetHighlightTexture()
    if hl and hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.1) end
end

local _trainerHooked = false
local function Skin_Trainer()
    local f = _G.ClassTrainerFrame
    if not f then return end
    WSkin.Shell("trainer", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "ClassTrainerFrame")   -- close + FilterDropdown + scrollbar
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.ClassTrainerFrameBg then _G.ClassTrainerFrameBg:SetAlpha(0) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.ClassTrainerFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    -- Insets: the top content panel (ClassTrainerFrameInset -- its Bg +
    -- NineSlice carry the leftover Blizzard chrome) and the bottom well.
    local topInset = _G.ClassTrainerFrameInset or f.Inset
    if topInset then WSkin.Inset(topInset) end
    local inset = f.BottomInset or _G.ClassTrainerFrameBottomInset
    if inset then WSkin.Inset(inset) end
    -- Filter dropdown label left-aligned.
    if f.FilterDropdown then LeftAlignFilterLabel(f.FilterDropdown) end
    -- Train button.
    local tb = _G.ClassTrainerTrainButton
    if tb then
        WSkin.Button(tb)
        local tfs = tb.GetFontString and tb:GetFontString()
        if tfs then WSkin.White(tfs) end
    end
    -- Top "current profession" tab: strip Blizzard chrome (bg + NineSlice
    -- border), keep the profession icon, wash the guild/community sidebar card
    -- texture over the WHOLE tab at 50%, and border the icon tight to its
    -- edges. NOT restrip-registered -- that would fade the icon + card we keep.
    local step = _G.ClassTrainerFrameSkillStepButton
    if step then
        local sdt = GetFFD(step)
        local icon = step.icon or step.Icon
        if step.NineSlice then WSkin.FadeNineSlice(step.NineSlice) end
        local keep = {}
        if icon then keep[icon] = true end
        if sdt.tabTex then keep[sdt.tabTex] = true end
        WSkin.FadeRegions(step, keep)
        -- Span the full window width and run 15px taller (measured one-shot,
        -- keeps the current top; retried on show until rects exist).
        if not sdt.resized then
            local st, ft, h = step:GetTop(), f:GetTop(), step:GetHeight()
            if st and ft and h then
                sdt.resized = true
                local dy = (st - ft) + 5   -- 5px up
                step:ClearAllPoints()
                step:SetPoint("TOPLEFT", f, "TOPLEFT", 0, dy)
                step:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, dy)
                step:SetHeight(h + 15)
            end
        end
        -- Full-tab background: the guild/community sidebar card atlas at 50%.
        if not sdt.tabTex then
            local t = step:CreateTexture(nil, "BACKGROUND", nil, -2)
            t:SetAtlas("Ui-Dialog-New-Background")
            t:SetTexCoord(0, 1, 0, 1)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetAlpha(0.5)
            t:SetAllPoints(step)
            sdt.tabTex = t
        end
        -- Profession icon: squared with a 1px border hugging its edges.
        if icon then WSkin.SquareIcon(icon, step) end
        if step.selectedTex and step.selectedTex.SetColorTexture then
            step.selectedTex:SetColorTexture(1, 1, 1, 0.15)
        end
        local shl = _G.ClassTrainerFrameSkillStepButtonHighlight
        if shl and shl.SetColorTexture then shl:SetColorTexture(1, 1, 1, 0.1) end
    end
    -- Skill rank status bar (profession trainers only).
    local sbar = _G.ClassTrainerStatusBar
    if sbar then
        WSkin.FadeRegions(sbar)
        WSkin.ApplyBarFill(sbar)
        if sbar.rankText then WSkin.Font(sbar.rankText); WSkin.White(sbar.rankText) end
    end
    -- Scroll list rows.
    local sb = f.ScrollBox
    if sb then
        if sb.ForEachFrame and sb:IsVisible() then sb:ForEachFrame(SkinTrainerRow) end
        if not GetFFD(sb).rowHook then
            GetFFD(sb).rowHook = true
            hooksecurefunc(sb, "Update", WSkin.Debounce(function()
                if sb.ForEachFrame and sb:IsVisible() then sb:ForEachFrame(SkinTrainerRow) end
            end))
        end
    end

    if not _trainerHooked then
        _trainerHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Trainer() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "trainer",
    addons = { Blizzard_TrainerUI = true },
    apply = Skin_Trainer,
})

-------------------------------------------------------------------------------
--  Delves Companion (Blizzard_DelvesCompanionConfiguration LoD addon)
--  Brann's configuration window: a portrait frame with three option slots
--  (combat role + two trinkets), a "Show Abilities" button, and the paginated
--  ability-list popout. Both frames live in the same addon and share the
--  "delves" winKey.
-------------------------------------------------------------------------------
-- One pooled option-slot flyout button: drop the gold border, square the icon.
local function SkinDelvesOptionButton(btn)
    if not btn or btn:IsForbidden() then return end
    if btn.Border and btn.Border.SetAlpha then btn.Border:SetAlpha(0) end
    local icon = btn.Icon or btn.icon
    if icon then WSkin.SquareIcon(icon, btn) end
end

-- One option slot's flyout list (the popout shown when the slot is clicked):
-- flat panel + slim scrollbar + squared icons on its pooled buttons.
local function SkinDelvesOptionSlot(slot)
    if not slot or slot:IsForbidden() then return end
    local list = slot.OptionsList
    if not list then return end
    WSkin.Panel(list)
    WSkin.ScrollBarsIn(list)
    local sb = list.ScrollBox
    if sb then
        if sb.ForEachFrame and sb:IsVisible() then pcall(sb.ForEachFrame, sb, SkinDelvesOptionButton) end
        if sb.Update and not GetFFD(sb).rowHook then
            GetFFD(sb).rowHook = true
            hooksecurefunc(sb, "Update", function(box)
                if box.ForEachFrame then pcall(box.ForEachFrame, box, SkinDelvesOptionButton) end
            end)
        end
    end
end

local _delvesAbilityHooked = false
local function Skin_DelvesCompanion()
    local f = _G.DelvesCompanionConfigurationFrame
    if f then
        WSkin.Shell("delves", f)
        WSkin.RemovePortrait(f)
        WSkin.CommonChrome(f)
        if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
        if f.Bg and f.Bg.SetAlpha then f.Bg:SetAlpha(0) end
        -- Leftover Blizzard border sub-frame (its own Bg + edges): our atlas
        -- border replaces it. Alpha 0 inherits to all its edge children.
        if f.Border and f.Border.SetAlpha then f.Border:SetAlpha(0) end
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
        if title then WSkin.Font(title); WSkin.White(title) end
        local ab = f.CompanionConfigShowAbilitiesButton
        if ab then
            WSkin.Button(ab)
            local lab = ab.GetFontString and ab:GetFontString()
            if lab then WSkin.White(lab) end
        end
        SkinDelvesOptionSlot(f.CompanionCombatRoleSlot)
        SkinDelvesOptionSlot(f.CompanionUtilityTrinketSlot)
        SkinDelvesOptionSlot(f.CompanionCombatTrinketSlot)
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_DelvesCompanion() end
        end))
    end

    -- Companion ability list popout (same addon), opened from Show Abilities.
    local al = _G.DelvesCompanionAbilityListFrame
    if al then
        WSkin.Shell("delves", al)
        WSkin.RemovePortrait(al)
        WSkin.CommonChrome(al)
        if al.NineSlice then WSkin.FadeNineSlice(al.NineSlice) end
        if al.Border and al.Border.SetAlpha then al.Border:SetAlpha(0) end
        local atitle = (al.TitleContainer and al.TitleContainer.TitleText) or al.TitleText
        if atitle then WSkin.Font(atitle); WSkin.White(atitle) end
        if al.DelvesCompanionRoleDropdown then WSkin.Dropdown(al.DelvesCompanionRoleDropdown) end
        local pc = al.DelvesCompanionAbilityListPagingControls
        if pc then
            if pc.PrevPageButton then WSkin.PageButton(pc.PrevPageButton, "<", 13) end
            if pc.NextPageButton then WSkin.PageButton(pc.NextPageButton, ">", 13) end
        end
        -- Ability tiles repaint on page flips: square their icons each rebuild.
        if not _delvesAbilityHooked and al.UpdatePaginatedButtonDisplay then
            _delvesAbilityHooked = true
            hooksecurefunc(al, "UpdatePaginatedButtonDisplay", function(self)
                if not self.buttons then return end
                for _, b in next, self.buttons do
                    local icon = b.Icon or b.icon
                    if icon then WSkin.SquareIcon(icon, b) end
                end
            end)
        end
        WSkin.HookShow(al, WSkin.Debounce(function()
            if al:IsVisible() then Skin_DelvesCompanion() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "delves",
    addons = { Blizzard_DelvesCompanionConfiguration = true },
    apply = Skin_DelvesCompanion,
})

-------------------------------------------------------------------------------
--  Gossip (GossipFrame) -- NPC dialog window. Base UI, always loaded.
-------------------------------------------------------------------------------
local function SkinGossipOption(btn)
    if not btn or btn:IsForbidden() then return end
    -- Recolor ONLY -- keep Blizzard's native font on gossip text (its buttons
    -- follow the color-only widget font policy). No WSkin.Font here.
    if btn.GreetingText then WSkin.White(btn.GreetingText); RecolorDarkText(btn.GreetingText) end
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then WSkin.White(fs); RecolorDarkText(fs) end
    -- The NPC greeting body text is a FontString nested inside the element (not
    -- the named GreetingText field or the button label), so it slips past both
    -- checks above and renders black on the dark panel. Whiten every FontString
    -- in the row subtree and rewrite embedded link colors, same as the other
    -- dark panels. The debounced ScrollBox.Update hook re-runs this per refresh,
    -- which re-asserts white after Blizzard recolors on each update.
    WhitenTextIn(btn)
end

local _gossipHooked = false
local function Skin_Gossip()
    local f = _G.GossipFrame
    if not f then return end
    WSkin.Shell("gossip", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "GossipFrame")   -- close + scrollbar
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if _G.GossipFrameBg then _G.GossipFrameBg:SetAlpha(0) end
    -- QuestLog atlas washed over the whole frame at 50%: sublevel -6 sits above
    -- the shell backdrop (-8/-7) and below the title bar (-5) + content. Stored
    -- under the protected "fill" key so a Restrip never fades it.
    if not GetFFD(f).fill then
        local qbg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
        qbg:SetAtlas("QuestLog-main-background", false)
        qbg:SetAllPoints(f)
        qbg:SetAlpha(0.5)
        GetFFD(f).fill = qbg
    end
    -- NPC scene / parchment background: re-textured per NPC, so self-guard the
    -- fade against its SetAtlas/SetTexture repaints.
    local bgTex = f.Background
    if bgTex and bgTex.SetAlpha then
        bgTex:SetAlpha(0)
        if not GetFFD(bgTex).atlasHook then
            GetFFD(bgTex).atlasHook = true
            hooksecurefunc(bgTex, "SetAtlas", function() bgTex:SetAlpha(0) end)
            if bgTex.SetTexture then
                hooksecurefunc(bgTex, "SetTexture", function() bgTex:SetAlpha(0) end)
            end
        end
    end
    local inset = f.Inset or _G.GossipFrameInset
    if inset then WSkin.Inset(inset) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.GossipFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    local gp = f.GreetingPanel
    if gp then
        if gp.GoodbyeButton then
            WSkin.Button(gp.GoodbyeButton)
            local gfs = gp.GoodbyeButton.GetFontString and gp.GoodbyeButton:GetFontString()
            if gfs then WSkin.White(gfs) end
        end
        local sb = gp.ScrollBox
        if sb then
            if sb.ForEachFrame and sb:IsVisible() then sb:ForEachFrame(SkinGossipOption) end
            if not GetFFD(sb).rowHook then
                GetFFD(sb).rowHook = true
                hooksecurefunc(sb, "Update", WSkin.Debounce(function()
                    if sb.ForEachFrame and sb:IsVisible() then sb:ForEachFrame(SkinGossipOption) end
                end))
            end
        end
    end
    -- Friendship rep bar (some NPCs): thin black notches, white text.
    local fsb = f.FriendshipStatusBar
    if fsb then
        for i = 1, 4 do
            local notch = fsb["Notch" .. i]
            if notch and notch.SetColorTexture then notch:SetColorTexture(0, 0, 0, 1) end
        end
        local ft = fsb.Text or (fsb.GetFontString and fsb:GetFontString())
        if ft then WSkin.Font(ft); WSkin.White(ft) end
    end

    if not _gossipHooked then
        _gossipHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Gossip() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "gossip",
    apply = Skin_Gossip,
})

-------------------------------------------------------------------------------
--  Quest (QuestFrame) -- the NPC quest dialog: detail / progress / reward /
--  greeting panels. Base UI, always loaded. Skinned to match the gossip
--  window: dark shell, faded parchment, yellow headers + white body text,
--  flat action buttons. Helpers are nested to keep the file's chunk-local
--  count clear of the Lua 5.1 cap.
-------------------------------------------------------------------------------
local _questHooked = false
local function Skin_Quest()
    local f = _G.QuestFrame
    if not f then return end
    WSkin.Shell("quest", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "QuestFrame")   -- close button + centered title
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Inset then WSkin.Inset(f.Inset) end

    -- Title bar / NPC name.
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.QuestFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    if _G.QuestFrameNpcNameText then
        WSkin.Font(_G.QuestFrameNpcNameText); WSkin.White(_G.QuestFrameNpcNameText)
    end

    -- Panels + scroll frames: fade every parchment texture (FadeRegions only
    -- alphas Textures, never FontStrings, so body text is untouched), register
    -- for restrip so Blizzard repaints get re-faded, slim the scrollbars.
    for _, pn in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel",
                          "QuestFrameRewardPanel", "QuestFrameGreetingPanel" }) do
        local p = _G[pn]
        if p then
            WSkin.FadeRegions(p)
            WSkin.Register(p, true)
            if p.NineSlice then WSkin.FadeNineSlice(p.NineSlice) end
        end
    end
    for _, sn in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame",
                          "QuestRewardScrollFrame", "QuestGreetingScrollFrame",
                          "QuestDetailScrollChildFrame", "QuestRewardScrollChildFrame" }) do
        local s = _G[sn]
        if s then
            WSkin.FadeRegions(s)
            WSkin.Register(s, true)
            if s.ScrollBar then WSkin.ScrollBar(s.ScrollBar) end
        end
    end
    -- Lift the whole quest scroll viewport up 40px and grow it 30px taller.
    -- CalReseat preserves every anchor point (no width collapse) and is
    -- idempotent; the height bump is FFD-guarded separately because SetHeight
    -- is cumulative and the skin re-runs on every show.
    for _, sn in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame",
                          "QuestRewardScrollFrame", "QuestGreetingScrollFrame" }) do
        local s = _G[sn]
        if s then
            CalReseat(s, 40)
            local d = GetFFD(s)
            if not d.heightBumped and s.GetHeight and s.SetHeight then
                local h = s:GetHeight()
                if h and h > 0 then
                    d.heightBumped = true
                    s:SetHeight(h + 30)
                end
            end
        end
    end

    -- Action buttons: flat block + white label (color-only, keeps Blizz font).
    for _, bn in ipairs({ "QuestFrameAcceptButton", "QuestFrameDeclineButton",
                          "QuestFrameCompleteButton", "QuestFrameGoodbyeButton",
                          "QuestFrameCompleteQuestButton", "QuestFrameCancelButton",
                          "QuestFrameGreetingGoodbyeButton" }) do
        local b = _G[bn]
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end

    -- Shared QuestInfo body/header coloring (detail + reward panels). The
    -- QuestInfo* frames are global and reparent between the NPC window and the
    -- map, so only recolor when displayed into THIS window (the world-map pack
    -- owns the map case); the colors match either way (both are dark).
    local function StyleQuestNPCText()
        for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionHeader",
                             "QuestInfoObjectivesHeader" }) do
            local fs = _G[n]
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end
        local rw = _G.QuestInfoRewardsFrame
        for _, n in ipairs({ "QuestInfoDescriptionText", "QuestInfoObjectivesText",
                             "QuestInfoGroupSize", "QuestInfoRewardText", "QuestInfoQuestType" }) do
            local fs = _G[n]
            if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end
        end
        if rw then
            WhitenTextIn(rw)  -- catch nested spell/effect + SimpleHTML reward blurbs the fields below miss
            for _, k in ipairs({ "ItemChooseText", "ItemReceiveText",
                                 "PlayerTitleText", "SpellLearnText" }) do
                local fs = rw[k]
                if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end
            end
            if rw.XPFrame and rw.XPFrame.ReceiveText and rw.XPFrame.ReceiveText.SetTextColor then
                rw.XPFrame.ReceiveText:SetTextColor(1, 1, 1)
            end
            -- Reward item tiles: drop the parchment name plate, white the name.
            if rw.RewardButtons then
                for _, btn in ipairs(rw.RewardButtons) do
                    if btn.NameFrame and btn.NameFrame.SetAlpha then btn.NameFrame:SetAlpha(0) end
                    if btn.Name and btn.Name.SetTextColor then btn.Name:SetTextColor(1, 1, 1) end
                end
            end
            if rw.Header and rw.Header.SetTextColor then rw.Header:SetTextColor(1, 0.82, 0) end
        end
        local of = _G.QuestInfoObjectivesFrame
        if of and of.Objectives then
            for _, obj in ipairs(of.Objectives) do
                if obj and obj.SetTextColor then obj:SetTextColor(1, 1, 1) end
            end
        end
    end

    -- One greeting-panel quest title button: keep the icon, white the text.
    -- Available quests bake a |cff000000 black color code into the string that
    -- a plain SetTextColor cannot override, so rewrite it to white in place.
    local function SkinQuestGreetingButton(btn)
        if not btn or btn:IsForbidden() then return end
        if btn.Icon and btn.Icon.SetDrawLayer then btn.Icon:SetDrawLayer("ARTWORK") end
        local fs = btn.GetFontString and btn:GetFontString()
        if fs then
            WSkin.Font(fs); WSkin.White(fs)
            local txt = fs.GetText and fs:GetText()
            if txt and txt:find("|cff000000", 1, true) then
                fs:SetText((txt:gsub("|cff000000", "|cffffffff")))
            end
        end
    end
    -- Greeting text + section labels + quest title buttons. Blizzard re-applies
    -- the dark parchment material colour in the greeting panel OnShow after our
    -- skin runs, so re-white on every show (hooked below), not just once here.
    local function StyleQuestGreeting()
        if _G.QuestGreetingText then WSkin.White(_G.QuestGreetingText); RecolorDarkText(_G.QuestGreetingText) end
        for _, n in ipairs({ "CurrentQuestsText", "AvailableQuestsText" }) do
            local fs = _G[n]
            if fs then WSkin.White(fs); RecolorDarkText(fs) end
        end
        local gp = _G.QuestFrameGreetingPanel
        if gp and gp.titleButtonPool then
            for btn in gp.titleButtonPool:EnumerateActive() do
                SkinQuestGreetingButton(btn)
            end
        end
    end

    if _G.QuestGreetingText then WSkin.Font(_G.QuestGreetingText) end
    for _, n in ipairs({ "CurrentQuestsText", "AvailableQuestsText" }) do
        local fs = _G[n]
        if fs then WSkin.Font(fs) end
    end
    if _G.QuestGreetingFrameHorizontalBreak and _G.QuestGreetingFrameHorizontalBreak.SetAlpha then
        _G.QuestGreetingFrameHorizontalBreak:SetAlpha(0)
    end
    StyleQuestGreeting()

    -- Progress panel static text.
    if _G.QuestProgressTitleText then
        WSkin.Font(_G.QuestProgressTitleText); _G.QuestProgressTitleText:SetTextColor(1, 0.82, 0)
    end
    if _G.QuestProgressText then WSkin.Font(_G.QuestProgressText); WSkin.White(_G.QuestProgressText) end

    if not _questHooked then
        _questHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Quest() end
        end))
        -- Greeting rows repopulate on QUEST_GREETING / QUEST_LOG_UPDATE.
        local gp = _G.QuestFrameGreetingPanel
        if gp then gp:HookScript("OnShow", WSkin.Debounce(StyleQuestGreeting)) end
        if type(_G.QuestFrameGreetingPanel_OnShow) == "function" then
            hooksecurefunc("QuestFrameGreetingPanel_OnShow", function()
                StyleQuestGreeting()
                if C_Timer then C_Timer.After(0, StyleQuestGreeting) end
            end)
        end
        -- Body text: Blizzard re-colors it on each display, so re-assert in the
        -- hook (and once more next frame -- objectives are colored after this).
        if type(_G.QuestInfo_Display) == "function" then
            hooksecurefunc("QuestInfo_Display", function(_, parentFrame)
                if not parentFrame then return end
                local p, isQuest = parentFrame, false
                for _i = 1, 8 do
                    if p == f then isQuest = true break end
                    p = p.GetParent and p:GetParent()
                    if not p then break end
                end
                if not isQuest then return end
                StyleQuestNPCText()
                if C_Timer then C_Timer.After(0, StyleQuestNPCText) end
            end)
        end
        if type(_G.QuestFrameProgressItems_Update) == "function" then
            hooksecurefunc("QuestFrameProgressItems_Update", function()
                local ri = _G.QuestProgressRequiredItemsText
                if ri and ri.SetTextColor then ri:SetTextColor(1, 0.82, 0) end
                local rm = _G.QuestProgressRequiredMoneyText
                if rm and rm.SetTextColor then rm:SetTextColor(1, 1, 1) end
            end)
        end
    end
    StyleQuestNPCText()
end

WSkin.RegisterWindow({
    key = "quest",
    apply = Skin_Quest,
})

-------------------------------------------------------------------------------
--  Inspect Recipe (InspectRecipeFrame, Blizzard_Professions) -- the small
--  recipe preview from a linked recipe / inspected crafter.
-------------------------------------------------------------------------------
local _inspectRecipeHooked = false
local function Skin_InspectRecipe()
    local f = _G.InspectRecipeFrame
    if not f then return end
    WSkin.Shell("inspectrecipe", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "InspectRecipeFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.InspectRecipeFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    -- Leave the recipe background/art alone (per request); just the form chrome.
    local sf = f.SchematicForm
    if sf and sf.NineSlice then WSkin.FadeNineSlice(sf.NineSlice) end
    if not _inspectRecipeHooked then
        _inspectRecipeHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_InspectRecipe() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "inspectrecipe",
    addons = { Blizzard_Professions = true },
    apply = Skin_InspectRecipe,
})

-------------------------------------------------------------------------------
--  Auction House (AuctionHouseFrame, Blizzard_AuctionHouseUI)
--  Broad first pass: shell, tabs, search bar, category rail, list panels +
--  column headers, buy/sell panels' inputs + action buttons, token panel,
--  buy dialog, multisell progress. Item icons in the lists, item-display
--  buttons, and the small refresh icon buttons stay stock content -- iterate
--  by fstack. Visual-only throughout (alpha/FFD); the commerce paths are
--  never touched.
-------------------------------------------------------------------------------
local _ahHooked = false
local function Skin_AuctionHouse()
    local f = _G.AuctionHouseFrame
    if not f then return end
    WSkin.Shell("auctionhouse", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)   -- close button, SearchBox/FilterButton, scrollbars
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    for _, k in ipairs({ "MoneyFrameBorder", "MoneyFrameInset" }) do
        local el = f[k]
        if el then
            WSkin.FadeRegions(el)
            if el.NineSlice then WSkin.FadeNineSlice(el.NineSlice) end
            WSkin.Register(el, true)
        end
    end

    local function WhiteBtn(b)
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end
    -- State-driven action buttons (bid/buyout/cancel): label mirrors the
    -- native enabled/disabled states instead of reading white while disabled.
    local function StateBtn(b)
        if b then WSkin.Button(b); WSkin.StateButtonLabel(b) end
    end
    -- Money edit box: the classic template's box art is GLOBAL-suffixed
    -- (<name>Left/Middle/Right), which the engine's keyed fade misses -- it
    -- sat over our fill and the input read unskinned.
    local function MoneyBox(eb)
        if not eb then return end
        WSkin.EditBox(eb)
        local n = eb.GetName and eb:GetName()
        if n then
            for _, suf in ipairs({ "Left", "Middle", "Right" }) do
                local t = _G[n .. suf]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
        end
    end
    local function MoneyInputs(mi)
        if not mi then return end
        MoneyBox(mi.GoldBox)
        MoneyBox(mi.SilverBox)
    end
    -- Click-to-sort column headers: the guild-roster treatment, copied
    -- exactly -- 3-slice art cleared, flat plate with white label and the
    -- standard hover. Headers pool/rebuild per list refresh, so this re-runs
    -- from the RefreshScrollFrame hook.
    local function Headers(list)
        local hc = list and list.HeaderContainer
        if not hc then return end
        -- Top-anchored views (browse, all-auctions, bids, sell lists) seat
        -- their header row against the STATIC wash top -- never a moving
        -- target, so a hidden list refreshing mid-view-swap cannot mis-seat
        -- (that bug shifted the browse scroll area down and hid its labels).
        -- Item-detail views keep Blizzard's stock header position below
        -- their item display. Measured, epsilon-gated, converges.
        -- Lists carry a washRef override (sell tab: the 50/50 right-half
        -- wash); default is the rail wash.
        local wash2 = GetFFD(list).washRef or GetFFD(f).wash
        if GetFFD(list).seatTop and wash2 and wash2.GetTop then
            local wt0, ht0 = wash2:GetTop(), hc:GetTop()
            if wt0 and ht0 and math.abs((wt0 - 2) - ht0) > 0.5 then
                local dy0 = (wt0 - 2) - ht0
                local np = hc:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = hc:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) + dy0 }
                end
                if ok then
                    hc:ClearAllPoints()
                    for i = 1, #pts do local t = pts[i]; hc:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                end
            end
        end
        -- Per-list sort strip: rides THIS list's header row (2px above it),
        -- spanning the wash's width. Parented to the list, so it shows and
        -- hides with its own view -- no shared strip, no cross-view state.
        local sd = GetFFD(list)
        if not sd.strip then
            local sTex = list:CreateTexture(nil, "BACKGROUND", nil, 1)
            sTex:SetColorTexture(0.02, 0.02, 0.02, 0.5)
            sTex:SetHeight(24)
            sd.strip = sTex
            -- Stored under a PROTECTED key too: the strip is a region OF the
            -- list, so the list's restrip registration would otherwise fade
            -- our own strip on every global Restrip pass.
            sd.fill = sTex
        end
        -- Re-assert alpha: any fade pass that caught the strip zeroed the
        -- region alpha (the color's own 50% lives in SetColorTexture).
        sd.strip:SetAlpha(1)
        -- Seat-top views ride the header row. Detail views anchor to the
        -- LIST TOP instead: their "top bar" row sits there, while their
        -- HeaderContainer can be vestigial and parked far down the list
        -- (commodities view), which dragged the strip down with it.
        local anchorTo, ay = hc, 2
        if not GetFFD(list).seatTop then anchorTo, ay = list, 0 end
        local wl0 = wash2 and wash2.GetLeft and wash2:GetLeft()
        local wr0 = wash2 and wash2.GetRight and wash2:GetRight()
        local al0 = anchorTo:GetLeft()
        if wl0 and wr0 and al0 then
            sd.strip:ClearAllPoints()
            sd.strip:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", wl0 - al0, ay)
            sd.strip:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", wr0 - al0, ay)
        end
        for i = 1, select("#", hc:GetChildren()) do
            local col = select(i, hc:GetChildren())
            if col and col.GetObjectType and col:GetObjectType() == "Button" then
                local hd = GetFFD(col)
                if not hd.bg then
                    for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                        local t2 = col[k2]
                        if t2 and t2.SetTexture then t2:SetTexture("") end
                    end
                    WSkin.FadeRegions(col)
                    -- Invisible plate: the full-width sortBar strip below is
                    -- the row's one background (a filled plate would STACK on
                    -- the 50% strip and read darker wherever a column sits).
                    -- The texture stays as the skinned-guard + keep marker.
                    local bg = SolidTex(col, "BACKGROUND", 0.02, 0.02, 0.02, 0)
                    bg:SetPoint("TOPLEFT", 1, -1)
                    bg:SetPoint("BOTTOMRIGHT", -1, 1)
                    hd.bg = bg
                    local hov = SolidTex(col, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hov:SetAllPoints(col)
                    hd.hover = hov
                    WSkin.Register(col, true)
                end
                local fs = col.GetFontString and col:GetFontString()
                if fs then WSkin.White(fs) end
                -- Hover wash spans the full sort-strip height (the button is
                -- shorter than the strip): re-seat against the strip's live
                -- rect each pass. Visual only -- the hit rect stays Blizzard's.
                local strip = GetFFD(list).strip
                if hd.hover and strip and strip.GetTop then
                    local st, sbot = strip:GetTop(), strip:GetBottom()
                    local ct, cbot = col:GetTop(), col:GetBottom()
                    if st and sbot and ct and cbot then
                        hd.hover:ClearAllPoints()
                        hd.hover:SetPoint("TOPLEFT", col, "TOPLEFT", 0, st - ct)
                        hd.hover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, sbot - cbot)
                    end
                end
            end
        end
    end
    -- Refresh corner (item lists): the reload button becomes the flat
    -- UI-RefreshButton glyph in white (desaturated + white vertex), and the
    -- total-quantity readout goes white.
    local function SkinRefresh(rf)
        if not rf then return end
        if rf.TotalQuantity then WSkin.White(rf.TotalQuantity) end
        local rb = rf.RefreshButton
        if rb and not GetFFD(rb).glyph
           and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-RefreshButton") then
            local d = GetFFD(rb)
            for i = 1, select("#", rb:GetRegions()) do
                local r = select(i, rb:GetRegions())
                if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
            for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                                 "GetHighlightTexture", "GetDisabledTexture" }) do
                local t = rb[g] and rb[g](rb)
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            local glyph = rb:CreateTexture(nil, "OVERLAY")
            glyph:SetAtlas("UI-RefreshButton", false)
            glyph:SetSize(16, 16)
            glyph:SetPoint("CENTER")
            glyph:SetDesaturated(true)
            glyph:SetVertexColor(1, 1, 1, 0.9)
            d.glyph = glyph
            rb:HookScript("OnEnter", function() glyph:SetVertexColor(1, 1, 1, 1) end)
            rb:HookScript("OnLeave", function() glyph:SetVertexColor(1, 1, 1, 0.9) end)
        end
    end
    -- List panel: framed chrome off, slim scrollbar, headers when present.
    -- seatTop: top-anchored views seat their header row at the wash top;
    -- item-detail views (display above the list) keep stock header position.
    local function List(list, hasHeader, seatTop)
        if not list then return end
        local ld = GetFFD(list)
        ld.seatTop = seatTop and true or nil
        -- Spare our own strip: it's a region of this list, and an unspared
        -- fade here (every skin pass) is what blanked the sort bar.
        WSkin.FadeRegions(list, ld.strip and { [ld.strip] = true } or nil)
        if list.NineSlice then WSkin.FadeNineSlice(list.NineSlice) end
        WSkin.Register(list, true)
        WSkin.ScrollBarsIn(list)
        SkinRefresh(list.RefreshFrame)
        if hasHeader then
            Headers(list)
            if list.RefreshScrollFrame and not GetFFD(list).hdrHook then
                GetFFD(list).hdrHook = true
                hooksecurefunc(list, "RefreshScrollFrame", function(l) Headers(l) end)
            end
            -- The strip's anchors need live rects; a pass that ran while the
            -- view was hidden leaves it unanchored (invisible). Re-run on the
            -- list's own show so the strip seats when the view opens.
            if not GetFFD(list).hdrShowHook then
                GetFFD(list).hdrShowHook = true
                list:HookScript("OnShow", WSkin.Debounce(function() Headers(list) end))
            end
        end
    end
    -- Item display plate (buy/sell/auctions detail): chrome off, item button
    -- stays stock content.
    local function ItemDisplay(host)
        local idp = host and host.ItemDisplay
        if not idp then return end
        WSkin.FadeRegions(idp)
        if idp.NineSlice then WSkin.FadeNineSlice(idp.NineSlice) end
        WSkin.Register(idp, true)
    end
    -- Sell panel: inputs, duration dropdown, post button, buyout checkbox.
    -- Sell-tab inputs run 5px shorter (scoped here: SellFrame only serves
    -- the two sell views).
    local function SlimInput(eb)
        if not eb or GetFFD(eb).slimmed then return end
        GetFFD(eb).slimmed = true
        local h = eb:GetHeight()
        if h and h > 5 then eb:SetHeight(h - 5) end
    end
    local function SellFrame(sf)
        if not sf then return end
        WSkin.FadeRegions(sf)
        WSkin.Register(sf, true)
        ItemDisplay(sf)
        if sf.QuantityInput then
            if sf.QuantityInput.InputBox then
                WSkin.EditBox(sf.QuantityInput.InputBox)
                SlimInput(sf.QuantityInput.InputBox)
            end
            WhiteBtn(sf.QuantityInput.MaxButton)
        end
        for _, pk in ipairs({ "PriceInput", "SecondaryPriceInput" }) do
            local mi = sf[pk] and sf[pk].MoneyInputFrame
            if mi then
                MoneyInputs(mi)
                SlimInput(mi.GoldBox)
                SlimInput(mi.SilverBox)
            end
        end
        if sf.Duration and sf.Duration.Dropdown then WSkin.Dropdown(sf.Duration.Dropdown) end
        WhiteBtn(sf.PostButton)
        local bmc = sf.BuyoutModeCheckButton
        if bmc then
            WSkin.Checkbox(bmc)
            -- 25% box shrink REVERTED for now: box + label vanished when an
            -- item was placed (the sell form re-lays out then) -- testing
            -- whether the explicit resize inside Blizzard's layout pass was
            -- the cause before re-doing the shrink another way.
            -- Label rides 6px right of the box (one-shot, points preserved).
            local lab = bmc.Text or (bmc.GetFontString and bmc:GetFontString())
            if lab and not GetFFD(lab).shifted then
                local np = lab:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = lab:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, (x or 0) + 6, y or 0 }
                end
                if ok then
                    GetFFD(lab).shifted = true
                    lab:ClearAllPoints()
                    for i = 1, #pts do local t = pts[i]; lab:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                end
            end
        end
    end

    -- Search bar: search button white; favorites star keeps its art (the
    -- professions favorites-button treatment). Filter dropdown matches the
    -- search button's height, label pinned left, and its active-filter clear
    -- X is the house glyph lifted above the dropdown's border strips.
    local sb = f.SearchBar
    if sb then
        WhiteBtn(sb.SearchButton)
        -- Favorites button: the star is its Icon key (unlike the professions
        -- favorites button, where the star is the Normal texture -- no
        -- restore here). Favoriting an item re-raises the button's state art,
        -- so every non-Icon texture gets a self-guarding fade: re-hidden the
        -- moment Blizzard re-textures or re-shows it.
        local fsb = sb.FavoritesSearchButton
        if fsb then
            WSkin.Button(fsb, { "Icon" })
            local fd2 = GetFFD(fsb)
            if not fd2.favPinned then
                fd2.favPinned = true
                for i = 1, select("#", fsb:GetRegions()) do
                    local r = select(i, fsb:GetRegions())
                    if r and r ~= fsb.Icon and r ~= fd2.bg and r ~= fd2.hover
                       and r.IsObjectType and r:IsObjectType("Texture") then
                        r:SetAlpha(0)
                        for _, m in ipairs({ "SetAtlas", "SetTexture", "Show" }) do
                            if type(r[m]) == "function" then
                                hooksecurefunc(r, m, function(rr) rr:SetAlpha(0) end)
                            end
                        end
                    end
                end
            end
        end
        local fb = sb.FilterButton
        if fb then
            LeftAlignFilterLabel(fb)
            local sbtn = sb.SearchButton
            local h = sbtn and sbtn.GetHeight and sbtn:GetHeight()
            if h and h > 0 and fb.SetHeight then fb:SetHeight(h) end
            SkinFilterResetX(fb.ClearFiltersButton, fb)
        end
    end

    -- Category rail: framed chrome off; the pooled category buttons restyle
    -- from the setup hook below (white selection/hover washes, never accent).
    -- The rail's TOP edge drops 10px (links start lower; bottom edge stays),
    -- and chained buttons pull 1px into each other (-1 spacing).
    local cats = f.CategoriesList
    if cats then
        WSkin.FadeRegions(cats)
        if cats.NineSlice then WSkin.FadeNineSlice(cats.NineSlice) end
        WSkin.Register(cats, true)
        WSkin.ScrollBarsIn(cats)
        if not GetFFD(cats).topShift then
            local np = cats:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = cats:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - (p:find("TOP", 1, true) and 10 or 0) }
            end
            if ok then
                GetFFD(cats).topShift = true
                cats:ClearAllPoints()
                for i = 1, #pts do local t = pts[i]; cats:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            end
        end
    end
    -- Rail row spacing -1: the rail is a ScrollBox, so spacing lives in the
    -- scroll view's padding (per-button anchor surgery is a no-op -- the view
    -- recomputes positions). Official padding setter, pcall-isolated, then a
    -- full update relays out the visible rows. One-shot.
    local function TightenCatButtons()
        if not cats or GetFFD(cats).spacingSet then return end
        local box = cats.ScrollBox
        local view = box and box.GetView and box:GetView()
        if not (view and view.SetPadding) then return end
        GetFFD(cats).spacingSet = true
        pcall(function()
            local t, b, l, r = 0, 0, 0, 0
            local pad = view.GetPadding and view:GetPadding()
            if pad then
                t = (pad.GetTop and pad:GetTop()) or 0
                b = (pad.GetBottom and pad:GetBottom()) or 0
                l = (pad.GetLeft and pad:GetLeft()) or 0
                r = (pad.GetRight and pad:GetRight()) or 0
            end
            view:SetPadding(t, b, l, r, -1)
            if box.FullUpdate then box:FullUpdate(true) end
        end)
    end
    TightenCatButtons()

    -- Zone lines, guild-window treatment: 1-physical-px 0.15 separators at
    -- the top seam (below the search row), the rail's right edge, and the
    -- bottom seam -- plus a 2% white wash over the results region. All on OUR
    -- OWN host frame (direct f regions would be wiped by the shell's region
    -- fade on every re-skin pass). The vertical line and wash anchor to the
    -- CategoriesList frame (stable container), so they track the rail.
    local ad = GetFFD(f)
    if not ad.zoneLines and cats then
        ad.zoneLines = true
        local px = 1
        do
            local PPx = EllesmereUI.PP
            local es = f:GetEffectiveScale()
            if PPx and PPx.perfect and es and es > 0 then px = PPx.perfect / es end
        end
        local host = CreateFrame("Frame", nil, f)
        host:SetAllPoints(f)
        host:SetFrameLevel(f:GetFrameLevel())
        ad.zoneHost = host
        local topSep = host:CreateTexture(nil, "ARTWORK")
        topSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        topSep:SetHeight(px)
        topSep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -77)
        topSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -77)
        local botSep = host:CreateTexture(nil, "ARTWORK")
        botSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        botSep:SetHeight(px)
        botSep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 30)
        botSep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30)
        -- RAIL-based wash + divider (buy + auctions tabs: sidebar column on
        -- the left). On their own sub-host so the SELL tab -- which has no
        -- rail and splits 50/50 -- can swap in its own set (visibility is
        -- driven from the displayMode sync below).
        local railHost = CreateFrame("Frame", nil, host)
        railHost:SetAllPoints(host)
        railHost:SetFrameLevel(host:GetFrameLevel())
        ad.railHost = railHost
        -- The wash (and everything anchored to it) rides the rail's top,
        -- which sits 10px lower for the link shift -- lift the zone's top
        -- back up so the results area stays flush with the top divider.
        local wash = railHost:CreateTexture(nil, "BACKGROUND")
        wash:SetColorTexture(1, 1, 1, 0.02)
        wash:SetPoint("TOPLEFT", cats, "TOPRIGHT", 2 + px, 5)
        wash:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30 + px)
        -- (The sort strip is PER LIST -- created in Headers, riding each
        -- list's own header row -- after the global moving strip caused
        -- cross-view bleed: hidden lists refreshing while another view had
        -- the strip lowered seated themselves against the wrong position.)
        ad.zonePx = px         -- one physical pixel, for wash-edge math
        ad.wash = wash         -- header seats + strip widths measure this
        -- Left border of the washed region: flush with the wash's top AND
        -- bottom (the rail frame runs lower than the wash, so its bottom
        -- corner is the wrong anchor -- the wash itself is the truth).
        local sideSep = railHost:CreateTexture(nil, "ARTWORK")
        sideSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        sideSep:SetWidth(px)
        sideSep:SetPoint("TOPLEFT", wash, "TOPLEFT", -px, 0)
        sideSep:SetPoint("BOTTOMLEFT", wash, "BOTTOMLEFT", -px, 0)
        -- SELL-tab zone: 50/50 split -- center divider, wash over the right
        -- half only. Hidden until the displayMode sync shows it.
        local sellHost = CreateFrame("Frame", nil, host)
        sellHost:SetAllPoints(host)
        sellHost:SetFrameLevel(host:GetFrameLevel())
        sellHost:Hide()
        ad.sellHost = sellHost
        local sellWash = sellHost:CreateTexture(nil, "BACKGROUND")
        sellWash:SetColorTexture(1, 1, 1, 0.02)
        sellWash:SetPoint("TOPLEFT", f, "TOP", px - 30, -77 - px)
        sellWash:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30 + px)
        ad.sellWash = sellWash
        local sellSep = sellHost:CreateTexture(nil, "ARTWORK")
        sellSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        sellSep:SetWidth(px)
        sellSep:SetPoint("TOPLEFT", sellWash, "TOPLEFT", -px, 0)
        sellSep:SetPoint("BOTTOMLEFT", sellWash, "BOTTOMLEFT", -px, 0)
    end

    -- Bottom clamp: rail + list frames natively run BELOW the bottom divider;
    -- pull each element's bottom edge up to the seam. Measured (rects needed),
    -- guarded one-shot per element, re-attempted every skin pass until rects
    -- exist. Elements with a BOTTOM anchor get the anchor raised; pure
    -- height-sized elements shrink instead.
    local function ClampBottom(el)
        if not el or GetFFD(el).botClamped then return end
        local fb, eb2 = f:GetBottom(), el:GetBottom()
        if not (fb and eb2) then return end
        local dy = (fb + 30 + (ad.zonePx or 1)) - eb2
        if dy < 0.5 then GetFFD(el).botClamped = true; return end
        local np = el:GetNumPoints() or 0
        local pts, ok, touched = {}, np > 0, false
        for i = 1, np do
            local p, rel, rp, x, y = el:GetPoint(i)
            if not p then ok = false break end
            local isBottom = p:find("BOTTOM", 1, true) and true or false
            if isBottom then touched = true end
            pts[i] = { p, rel, rp, x or 0, (y or 0) + (isBottom and dy or 0) }
        end
        if ok and touched then
            GetFFD(el).botClamped = true
            el:ClearAllPoints()
            for i = 1, #pts do local t2 = pts[i]; el:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5]) end
        elseif ok then
            local h = el:GetHeight()
            if h and h > dy then
                GetFFD(el).botClamped = true
                el:SetHeight(h - dy)
            end
        end
    end
    ClampBottom(cats)

    -- Browse results (Buy tab).
    local br = f.BrowseResultsFrame
    if br then List(br.ItemList, true, true) end
    if br then ClampBottom(br.ItemList) end

    -- Commodities buy view.
    local cbf = f.CommoditiesBuyFrame
    if cbf then
        WhiteBtn(cbf.BackButton)
        -- Back button rides 3px lower (one-shot, all points preserved).
        if cbf.BackButton and not GetFFD(cbf.BackButton).dropped then
            local bb = cbf.BackButton
            local np = bb:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = bb:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 3 }
            end
            if ok then
                GetFFD(bb).dropped = true
                bb:ClearAllPoints()
                for i = 1, #pts do local t = pts[i]; bb:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            end
        end
        -- Commodities layout is the SIDE-BY-SIDE one: buy panel left, price
        -- list right, NO sort captions -- so no header treatment and no
        -- strip (a wash-wide strip cut across the buy panel). The item-buy
        -- layout (display above, headered list below) is the one that gets
        -- the strip.
        List(cbf.ItemList, false)
        local bd = cbf.BuyDisplay
        if bd then
            WSkin.FadeRegions(bd)
            WSkin.Register(bd, true)
            ItemDisplay(bd)
            local qib = bd.QuantityInput and bd.QuantityInput.InputBox
            if qib then
                WSkin.EditBox(qib)
                if not GetFFD(qib).slimmed then
                    GetFFD(qib).slimmed = true
                    local h = qib:GetHeight()
                    if h and h > 5 then qib:SetHeight(h - 5) end
                end
            end
            StateBtn(bd.BuyButton)
        end
    end

    -- Single-item buy view.
    local ibf = f.ItemBuyFrame
    if ibf then
        WhiteBtn(ibf.BackButton)
        if ibf.BuyoutFrame then StateBtn(ibf.BuyoutFrame.BuyoutButton) end
        if ibf.BidFrame then
            StateBtn(ibf.BidFrame.BidButton)
            -- Bid button rides 20px right on the bottom bar (one-shot).
            local bb = ibf.BidFrame.BidButton
            if bb and not GetFFD(bb).shiftedX then
                local np = bb:GetNumPoints() or 0
                local pts, ok = {}, np > 0
                for i = 1, np do
                    local p, rel, rp, x, y = bb:GetPoint(i)
                    if not p then ok = false break end
                    pts[i] = { p, rel, rp, (x or 0) + 20, y or 0 }
                end
                if ok then
                    GetFFD(bb).shiftedX = true
                    bb:ClearAllPoints()
                    for i = 1, #pts do local t = pts[i]; bb:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                end
            end
        end
        ItemDisplay(ibf)
        List(ibf.ItemList, true)
    end
    local function ReFadeMoney()
        for _, n in ipairs({ "AuctionHouseFrameGold", "AuctionHouseFrameSilver",
                             "BidAmountGold", "BidAmountSilver" }) do
            MoneyBox(_G[n])
        end
    end
    ReFadeMoney()
    -- The bid views initialize their money-box art on THEIR show, and
    -- sub-view swaps never re-fire the window's OnShow (our re-skin driver)
    -- -- so re-fade from the views' own OnShow.
    for _, host2 in ipairs({ ibf, f.AuctionsFrame or _G.AuctionHouseFrameAuctionsFrame }) do
        if host2 and not GetFFD(host2).moneyHook then
            GetFFD(host2).moneyHook = true
            host2:HookScript("OnShow", WSkin.Debounce(ReFadeMoney))
            if host2.BidFrame and host2.BidFrame.HookScript then
                host2.BidFrame:HookScript("OnShow", WSkin.Debounce(ReFadeMoney))
            end
        end
    end

    -- Sell tab.
    SellFrame(f.ItemSellFrame)
    SellFrame(f.CommoditiesSellFrame)
    List(f.ItemSellList, true, true)
    List(f.CommoditiesSellList, true, true)
    -- Sell lists measure against the sell tab's 50/50 wash, not the rail one.
    if f.ItemSellList then GetFFD(f.ItemSellList).washRef = ad.sellWash end
    if f.CommoditiesSellList then GetFFD(f.CommoditiesSellList).washRef = ad.sellWash end
    local tsf = f.WoWTokenSellFrame
    if tsf then
        WSkin.FadeRegions(tsf)
        WSkin.Register(tsf, true)
        ItemDisplay(tsf)
        WhiteBtn(tsf.PostButton)
        if tsf.DummyItemList then
            WSkin.FadeRegions(tsf.DummyItemList)
            WSkin.Register(tsf.DummyItemList, true)
            WSkin.ScrollBarsIn(tsf)
        end
    end

    -- My auctions tab.
    local af = f.AuctionsFrame or _G.AuctionHouseFrameAuctionsFrame
    if af then
        WSkin.FadeRegions(af)
        WSkin.Register(af, true)
        ItemDisplay(af)
        -- Selected-item spot: the guild-sidebar tile sheet behind it. (The
        -- sort strip's make-room reseat is unified below for ALL item
        -- displays -- auctions, item-buy, commodities-buy.)
        local idp = af.ItemDisplay
        if idp then
            local idd = GetFFD(idp)
            if not idd.card then
                local card = idp:CreateTexture(nil, "BACKGROUND", nil, -5)
                card:SetAtlas("Ui-Dialog-New-Background")
                card:SetPoint("TOPLEFT", idp, "TOPLEFT", 0, 0)
                card:SetPoint("BOTTOMRIGHT", idp, "BOTTOMRIGHT", 0, 0)
                card:SetAlpha(0.5)
                idd.card = card
            end
        end
        if af.BuyoutFrame then StateBtn(af.BuyoutFrame.BuyoutButton) end
        if af.BidFrame then StateBtn(af.BidFrame.BidButton) end
        StateBtn(af.CancelAuctionButton)
        List(af.CommoditiesList, true)
        List(af.ItemList, true)
        List(af.SummaryList, false)
        List(af.AllAuctionsList, true, true)
        List(af.BidsList, true, true)
        -- Auctions sidebar (SummaryList): its rows are a separate ScrollBox
        -- pool -- the buy tab's category-rail setup hook never touches them.
        -- Same tile treatment: flat card + border, white label, white washes
        -- spanning the full tile.
        local sum = af.SummaryList
        local sumBox = sum and sum.ScrollBox
        if sumBox and not GetFFD(sum).rowHook then
            GetFFD(sum).rowHook = true
            local function SkinSummaryRow(row)
                if not row or (row.IsForbidden and row:IsForbidden()) then return end
                -- Rows run narrower than the column; match the box width
                -- (re-asserted per Update pass, after the view lays out).
                local bw = sumBox.GetWidth and sumBox:GetWidth()
                if bw and bw > 1 and row.GetWidth and math.abs((row:GetWidth() or 0) - bw) > 1 then
                    row:SetWidth(bw)
                end
                local rd = GetFFD(row)
                if not rd.bg then
                    local bg = row:CreateTexture(nil, "BACKGROUND", nil, -3)
                    bg:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                    bg:SetPoint("TOPLEFT", 1, -1)
                    bg:SetPoint("BOTTOMRIGHT", -1, 1)
                    rd.bg = bg
                    WSkin.AddBorder(row)
                    -- NEVER restrip-register content rows: a global Restrip
                    -- (any window's show pass -- opening bags during the sell
                    -- flow fires one) would fade the item ICON and the
                    -- hover/selection washes. The Update hook re-passes these
                    -- rows; that is their only upkeep.
                end
                if row.HighlightTexture then
                    row.HighlightTexture:SetColorTexture(1, 1, 1, 0.1)
                    row.HighlightTexture:ClearAllPoints()
                    row.HighlightTexture:SetAllPoints(row)
                end
                if row.SelectedHighlight then
                    row.SelectedHighlight:SetColorTexture(1, 1, 1, 0.15)
                    row.SelectedHighlight:ClearAllPoints()
                    row.SelectedHighlight:SetAllPoints(row)
                end
                if row.Text then WSkin.White(row.Text) end
            end
            hooksecurefunc(sumBox, "Update", WSkin.Debounce(function()
                if sumBox.ForEachFrame and sumBox:IsVisible() then
                    sumBox:ForEachFrame(SkinSummaryRow)
                end
            end))
            -- Initial pass only once the box has a view: ForEachFrame on an
            -- uninitialized ScrollBox errors inside Blizzard's code at addon
            -- load. The Update hook covers everything after init anyway.
            if sumBox.ForEachFrame and sumBox.GetView and sumBox:GetView() then
                pcall(sumBox.ForEachFrame, sumBox, SkinSummaryRow)
            end
        end
        -- Measured seats (rects only exist once the auctions view lays out,
        -- so each is a guarded one-shot retried from af's OnShow):
        --  * SummaryList column matches the buy rail's exact left/right edges
        --    so the sidebar tiles line up between tabs.
        --  * The main lists span the full washed region (wash left edge to
        --    the window's right edge) and sit 4px lower.
        local function SeatSummary()
            if not sum or GetFFD(sum).seated then return end
            local cl2, cr2 = cats and cats:GetLeft(), cats and cats:GetRight()
            local sl2, sr2 = sum:GetLeft(), sum:GetRight()
            if not (cl2 and cr2 and sl2 and sr2) then return end
            GetFFD(sum).seated = true
            local dxL, dxR = cl2 - sl2, cr2 - sr2
            local np = sum:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = sum:GetPoint(i)
                if not p then ok = false break end
                local dx = p:find("RIGHT", 1, true) and dxR or dxL
                pts[i] = { p, rel, rp, (x or 0) + dx, y or 0 }
            end
            if ok then
                sum:ClearAllPoints()
                for i = 1, #pts do local t2 = pts[i]; sum:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5]) end
            end
        end
        local function SeatMainList(l)
            if not l or GetFFD(l).seated then return end
            local fr2 = f:GetRight()
            local cr2 = cats and cats:GetRight()
            local ll2, lr2 = l:GetLeft(), l:GetRight()
            if not (fr2 and cr2 and ll2 and lr2) then return end
            GetFFD(l).seated = true
            local dxL = (cr2 + 2 + (ad.zonePx or 1)) - ll2
            local dxR = fr2 - lr2
            local np = l:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = l:GetPoint(i)
                if not p then ok = false break end
                local dx = p:find("RIGHT", 1, true) and dxR or dxL
                pts[i] = { p, rel, rp, (x or 0) + dx, (y or 0) - 7 }
            end
            if ok then
                l:ClearAllPoints()
                for i = 1, #pts do local t2 = pts[i]; l:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5]) end
            end
        end
        -- Item rows' white backing spans the full washed width: (a) the
        -- ScrollBox reserves a right gutter inside the list -- stretch it to
        -- the list's right edge (the slim scrollbar overlays fine); (b) each
        -- row's backing/hover textures are sized to the table columns, not
        -- the row -- stretch every row-level texture to the row (cell content
        -- lives on child frames and is untouched). Rows pool: per-Update.
        local function WidenRows(l)
            local box2 = l and l.ScrollBox
            if not box2 then return end
            if not GetFFD(box2).widened then
                local lr3, br3 = l:GetRight(), box2:GetRight()
                if lr3 and br3 and lr3 > br3 then
                    GetFFD(box2).widened = true
                    local np = box2:GetNumPoints() or 0
                    local pts, ok = {}, np > 0
                    for i = 1, np do
                        local p, rel, rp, x, y = box2:GetPoint(i)
                        if not p then ok = false break end
                        pts[i] = { p, rel, rp,
                            (x or 0) + (p:find("RIGHT", 1, true) and (lr3 - br3) or 0), y or 0 }
                    end
                    if ok then
                        box2:ClearAllPoints()
                        for i = 1, #pts do local t2 = pts[i]; box2:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5]) end
                    end
                end
            end
            if not GetFFD(box2).rowStretch then
                GetFFD(box2).rowStretch = true
                local function StretchRow(row)
                    if not row or (row.IsForbidden and row:IsForbidden()) then return end
                    if GetFFD(row).stretched then return end
                    GetFFD(row).stretched = true
                    for i = 1, select("#", row:GetRegions()) do
                        local r = select(i, row:GetRegions())
                        if r and r.IsObjectType and r:IsObjectType("Texture") then
                            r:ClearAllPoints()
                            r:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                            r:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
                hooksecurefunc(box2, "Update", WSkin.Debounce(function()
                    if box2.ForEachFrame and box2:IsVisible() then
                        box2:ForEachFrame(StretchRow)
                    end
                end))
                -- Same uninitialized-ScrollBox guard as the summary rows.
                if box2.ForEachFrame and box2.GetView and box2:GetView() then
                    pcall(box2.ForEachFrame, box2, StretchRow)
                end
            end
        end
        local function SeatAuctionsTab()
            SeatSummary()
            SeatMainList(af.AllAuctionsList)
            SeatMainList(af.BidsList)
            WidenRows(af.AllAuctionsList)
            WidenRows(af.BidsList)
            -- These also run past the bottom divider (the seat drops them
            -- further). Deferred a frame: the seats just moved anchors, and
            -- clamping against same-frame stale rects would mis-measure.
            -- The summary ScrollBox also stretches to the reseated list's
            -- edges here -- widening the LIST doesn't move the box's own
            -- stock anchors, and the rows follow the box.
            local function clamp()
                ClampBottom(af.AllAuctionsList)
                ClampBottom(af.BidsList)
                ClampBottom(af.SummaryList)
                if sum and sumBox and not GetFFD(sumBox).stretched then
                    local ll2, lr2 = sum:GetLeft(), sum:GetRight()
                    local bl2, br2 = sumBox:GetLeft(), sumBox:GetRight()
                    if ll2 and lr2 and bl2 and br2 then
                        GetFFD(sumBox).stretched = true
                        local np = sumBox:GetNumPoints() or 0
                        local pts, ok = {}, np > 0
                        for i = 1, np do
                            local p, rel, rp, x, y = sumBox:GetPoint(i)
                            if not p then ok = false break end
                            local dx = p:find("RIGHT", 1, true) and (lr2 - br2) or (ll2 - bl2)
                            pts[i] = { p, rel, rp, (x or 0) + dx, y or 0 }
                        end
                        if ok then
                            sumBox:ClearAllPoints()
                            for i = 1, #pts do
                                local t2 = pts[i]
                                sumBox:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                            end
                        end
                    end
                end
            end
            if C_Timer then C_Timer.After(0, clamp) else clamp() end
        end
        SeatAuctionsTab()
        if not GetFFD(af).seatHook then
            GetFFD(af).seatHook = true
            af:HookScript("OnShow", WSkin.Debounce(SeatAuctionsTab))
        end
        -- Sub-tabs: dark-active (spellbook look), seated 1px lower. Only the
        -- chain root moves -- NormalizeTabRow re-chains the rest off it.
        local afTabs = {}
        for _, n in ipairs({ "AuctionHouseFrameAuctionsFrameAuctionsTab",
                             "AuctionHouseFrameAuctionsFrameBidsTab" }) do
            local t = _G[n]
            if t then WSkin.Tab(t, { darkActive = true }); afTabs[#afTabs + 1] = t end
        end
        local root = afTabs[1]
        if root and not GetFFD(root).dropped then
            local np = root:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = root:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 1 }
            end
            if ok then
                GetFFD(root).dropped = true
                root:ClearAllPoints()
                for i = 1, #pts do local t2 = pts[i]; root:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5]) end
            end
        end
        WSkin.NormalizeTabRow(afTabs)
    end

    -- WoW Token results panel.
    local tr = f.WoWTokenResults
    if tr then
        WSkin.FadeRegions(tr)
        WSkin.Register(tr, true)
        WhiteBtn(tr.Buyout)
        WSkin.ScrollBarsIn(tr)
        local td = tr.TokenDisplay
        if td then
            WSkin.FadeRegions(td)
            if td.NineSlice then WSkin.FadeNineSlice(td.NineSlice) end
            WSkin.Register(td, true)
        end
        local tut = tr.GameTimeTutorial
        if tut then
            if tut.NineSlice then WSkin.FadeNineSlice(tut.NineSlice) end
            if tut.Bg and tut.Bg.SetAlpha then tut.Bg:SetAlpha(0) end
            if tut.CloseButton then WSkin.CloseButton(tut.CloseButton) end
            if tut.RightDisplay then
                WhiteBtn(tut.RightDisplay.StoreButton)
                if tut.RightDisplay.Label then WSkin.White(tut.RightDisplay.Label) end
            end
            if tut.LeftDisplay and tut.LeftDisplay.Label then WSkin.White(tut.LeftDisplay.Label) end
        end
    end

    -- Confirm-purchase dialog. Its border is a CHILD frame (Bg/edge pieces),
    -- out of reach of the panel's own region fade -- suppress it wholesale.
    local dlg = f.BuyDialog
    if dlg then
        WSkin.Panel(dlg)
        if dlg.Border then
            WSkin.FadeNineSlice(dlg.Border)
            WSkin.Register(dlg.Border, true)
        end
        WhiteBtn(dlg.BuyNowButton)
        WhiteBtn(dlg.CancelButton)
    end

    -- Multisell progress popup: house bar (flat fill on a dark trough).
    local ms = _G.AuctionHouseMultisellProgressFrame
    if ms then
        WSkin.FadeRegions(ms)
        WSkin.Register(ms, true)
        local pb = ms.ProgressBar
        if pb then
            local pd = GetFFD(pb)
            local fill = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
            for i = 1, select("#", pb:GetRegions()) do
                local r = select(i, pb:GetRegions())
                if r and r ~= fill and r ~= pd.bg and r.IsObjectType
                   and r:IsObjectType("Texture") and r:GetDrawLayer() ~= "HIGHLIGHT" then
                    r:SetAlpha(0)
                end
            end
            if pb.SetStatusBarTexture then
                pb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                WSkin.ApplyBarFill(pb)
            end
            if not pd.bg then
                local trough = pb:CreateTexture(nil, "BACKGROUND", nil, -1)
                trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                trough:SetAllPoints(pb)
                pd.bg = trough
            end
            if pb.Text then WSkin.White(pb.Text) end
        end
    end

    -- Bottom tabs (Buy / Sell / My Auctions). The AH has no PanelTemplates /
    -- selectedTabID tab state -- selection is its displayMode -- so the
    -- engine's checks all miss and no tab ever read as active. Sync the
    -- FFD selection override from the display mode instead (tab.displayMode
    -- is compared by reference), refreshed on every SetDisplayMode.
    local ahTabs = {}
    for _, n in ipairs({ "AuctionHouseFrameBuyTab", "AuctionHouseFrameSellTab",
                         "AuctionHouseFrameAuctionsTab" }) do
        local t = _G[n]
        if t then WSkin.Tab(t); ahTabs[#ahTabs + 1] = t end
    end
    WSkin.NormalizeTabRow(ahTabs)
    local function SyncTabSel()
        if type(f.GetDisplayMode) ~= "function" then return end
        local ok, dm = pcall(f.GetDisplayMode, f)
        if not ok or dm == nil then return end
        local any = false
        for _, t in ipairs(ahTabs) do
            if t.displayMode ~= nil then
                any = true
                GetFFD(t).selOverride = (t.displayMode == dm)
            end
        end
        if any then WSkin.UpdateAllTabs() end
        -- Zone swap: rail wash/divider on buy + auctions, the 50/50 center
        -- set on sell. Placing an item flips displayMode to a sell SUB-mode
        -- (item-sell / commodities-sell) that no longer equals the tab's own
        -- mode, so also treat any visible sell view as "on the sell tab" --
        -- and keep the Sell tab's underline lit through the sub-modes.
        local sellTab = _G.AuctionHouseFrameSellTab
        local isSell = sellTab and sellTab.displayMode ~= nil and sellTab.displayMode == dm
        if not isSell then
            for _, k in ipairs({ "ItemSellFrame", "CommoditiesSellFrame", "WoWTokenSellFrame" }) do
                local v = f[k]
                if v and v:IsShown() then isSell = true break end
            end
        end
        if ad.railHost then ad.railHost:SetShown(not isSell) end
        if ad.sellHost then ad.sellHost:SetShown(isSell and true or false) end
        if isSell and sellTab and not GetFFD(sellTab).selOverride then
            GetFFD(sellTab).selOverride = true
            WSkin.UpdateAllTabs()
        end
    end
    if type(f.SetDisplayMode) == "function" and not ad.dmHook then
        ad.dmHook = true
        hooksecurefunc(f, "SetDisplayMode", WSkin.Debounce(SyncTabSel))
    end
    SyncTabSel()

    if not _ahHooked then
        _ahHooked = true
        -- Pooled category rail buttons: the standard sidebar tile (flat card
        -- + border + white label -- the achievements-rail treatment), with
        -- Blizzard's selected/highlight textures recolored to the house white
        -- washes. Re-runs from Blizzard's setup function since the rows pool.
        if type(_G.AuctionHouseFilterButton_SetUp) == "function" then
            hooksecurefunc("AuctionHouseFilterButton_SetUp", function(button)
                if not button or button:IsForbidden() then return end
                local d = GetFFD(button)
                if not d.bg then
                    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -3)
                    bg:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                    bg:SetPoint("TOPLEFT", 1, -1)
                    bg:SetPoint("BOTTOMRIGHT", -1, 1)
                    d.bg = bg
                    WSkin.AddBorder(button)
                    -- No restrip registration: it would fade the recolored
                    -- selection/hover washes on any global Restrip pass (the
                    -- SetUp hook is these buttons' upkeep).
                end
                if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
                -- Selection/hover washes span the FULL tile (Blizzard sizes
                -- them to the old art, short of the button edges).
                if button.SelectedTexture then
                    button.SelectedTexture:SetColorTexture(1, 1, 1, 0.15)
                    button.SelectedTexture:ClearAllPoints()
                    button.SelectedTexture:SetAllPoints(button)
                end
                if button.HighlightTexture then
                    button.HighlightTexture:SetColorTexture(1, 1, 1, 0.1)
                    button.HighlightTexture:ClearAllPoints()
                    button.HighlightTexture:SetAllPoints(button)
                end
                local fs = button.Text or (button.GetFontString and button:GetFontString())
                if fs then WSkin.White(fs) end
            end)
            hooksecurefunc("AuctionHouseFilterButton_SetUp", WSkin.Debounce(TightenCatButtons))
        end
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_AuctionHouse() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "auctionhouse",
    addons = { Blizzard_AuctionHouseUI = true },
    apply = Skin_AuctionHouse,
})

-------------------------------------------------------------------------------
--  Macros (MacroFrame, Blizzard_MacroUI)
--  Shell + tabs + action buttons + text/icon wells. The icon grid and the
--  selected-macro icon stay stock content; the icon-picker popup is its own
--  frame and stays stock for this pass.
-------------------------------------------------------------------------------
-- Name-and-icon picker popup (IconSelectorPopupFrameTemplate): house panel,
-- themed name input + buttons + type dropdown, white texts, icon grid slot
-- art at 50% (matching the main selector grid).
local _macroPopupHooked = false
local function Skin_MacroPopup()
    local p = _G.MacroPopupFrame
    if not p then return end
    WSkin.Panel(p)
    if p.NineSlice then WSkin.FadeNineSlice(p.NineSlice) end
    if p.Bg and p.Bg.SetAlpha then p.Bg:SetAlpha(0) end
    local bb = p.BorderBox
    if bb then
        WSkin.FadeRegions(bb)
        if bb.NineSlice then WSkin.FadeNineSlice(bb.NineSlice) end
        WSkin.Register(bb, true)
        local eb = bb.IconSelectorEditBox
        if eb then
            WSkin.EditBox(eb)
            local n = eb.GetName and eb:GetName()
            if n then
                for _, suf in ipairs({ "Left", "Middle", "Right" }) do
                    local t = _G[n .. suf]
                    if t and t.SetAlpha then t:SetAlpha(0) end
                end
            end
        end
        for _, k in ipairs({ "OkayButton", "CancelButton" }) do
            local b = bb[k]
            if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
        end
        for _, k in ipairs({ "IconTypeDropdown", "IconFilterDropdown" }) do
            if bb[k] then WSkin.Dropdown(bb[k]) end
        end
        for _, k in ipairs({ "EditBoxHeaderText", "IconSelectionText", "SelectedIconText" }) do
            local fs = bb[k]
            if fs then WSkin.Font(fs); WSkin.White(fs) end
        end
    end
    local grid = p.IconSelector
    local gBox = grid and (grid.ScrollBox or (grid.ForEachFrame and grid))
    if grid then
        WSkin.FadeRegions(grid)
        WSkin.Register(grid, true)
        WSkin.ScrollBarsIn(p)
    end
    if gBox then
        local gd = GetFFD(p)
        if not gd.iconDim then
            gd.iconDim = function()
                if gBox.ForEachFrame and gBox:IsVisible() then
                    gBox:ForEachFrame(function(btn)
                        for i = 1, select("#", btn:GetRegions()) do
                            local r = select(i, btn:GetRegions())
                            if r and r ~= btn.Icon and r ~= btn.Highlight
                               and r ~= btn.SelectedTexture
                               and r.IsObjectType and r:IsObjectType("Texture") then
                                r:SetAlpha(0.5)
                            end
                        end
                    end)
                end
            end
            hooksecurefunc(gBox, "Update", WSkin.Debounce(gd.iconDim))
        end
        if gBox.GetView and gBox:GetView() then pcall(gd.iconDim) end
    end
    if not _macroPopupHooked then
        _macroPopupHooked = true
        WSkin.HookShow(p, WSkin.Debounce(function()
            if p:IsVisible() then Skin_MacroPopup() end
        end))
    end
end

local _macroHooked = false
local function Skin_Macros()
    local f = _G.MacroFrame
    if not f then return end
    WSkin.Shell("macros", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "MacroFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Inset then WSkin.Inset(f.Inset) end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.MacroFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end

    for _, n in ipairs({ "MacroSaveButton", "MacroCancelButton", "MacroDeleteButton",
                         "MacroNewButton", "MacroExitButton", "MacroEditButton" }) do
        local b = _G[n]
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end

    local mTabs = {}
    for i = 1, 2 do
        local t = _G["MacroFrameTab" .. i]
        if t then WSkin.Tab(t, { darkActive = true }); mTabs[#mTabs + 1] = t end
    end
    -- Left-align the row: the chain root reseats so its left edge sits 12px
    -- from the window's left (measured one-shot, rect-gated -- retried by
    -- the show re-run). Tab2 chains off it via the seam normalization.
    local mt1 = mTabs[1]
    if mt1 and not GetFFD(mt1).leftAligned then
        local fl, tl = f:GetLeft(), mt1:GetLeft()
        if fl and tl then
            local dx = (fl + 12) - tl
            local np = mt1:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = mt1:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, (x or 0) + dx, y or 0 }
            end
            if ok then
                GetFFD(mt1).leftAligned = true
                mt1:ClearAllPoints()
                for i = 1, #pts do local t2 = pts[i]; mt1:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5]) end
            end
        end
    end
    WSkin.NormalizeTabRow(mTabs)

    -- Icon selector grid panel: framed chrome off, slim scrollbar (the icon
    -- buttons themselves stay stock).
    local sel = f.MacroSelector
    if sel then
        local seld = GetFFD(sel)
        WSkin.FadeRegions(sel)
        if sel.ScrollBox then
            WSkin.FadeRegions(sel.ScrollBox)
            WSkin.Register(sel.ScrollBox, true)
        end
        WSkin.Register(sel, true)
        WSkin.ScrollBarsIn(sel)
        -- Grid buttons are pooled: halve each slot's backdrop art (every
        -- texture that isn't the icon itself, the hover, or the selection),
        -- re-asserted per Update. Absolute alpha -- never compounds.
        local sBox = sel.ScrollBox
        if sBox then
            if not seld.iconDim then
                seld.iconDim = function()
                    if sBox.ForEachFrame and sBox:IsVisible() then
                        sBox:ForEachFrame(function(btn)
                            for i = 1, select("#", btn:GetRegions()) do
                                local r = select(i, btn:GetRegions())
                                if r and r ~= btn.Icon and r ~= btn.Highlight
                                   and r ~= btn.SelectedTexture
                                   and r.IsObjectType and r:IsObjectType("Texture") then
                                    r:SetAlpha(0.5)
                                end
                            end
                        end)
                    end
                end
                hooksecurefunc(sBox, "Update", WSkin.Debounce(seld.iconDim))
            end
            if sBox.GetView and sBox:GetView() then pcall(seld.iconDim) end
        end
    end

    -- Macro body text well: input-style near-black fill + themed border.
    local tb = _G.MacroFrameTextBackground
    if tb then
        local td = GetFFD(tb)
        WSkin.FadeRegions(tb)
        if tb.NineSlice then WSkin.FadeNineSlice(tb.NineSlice) end
        WSkin.Register(tb, true)
        if not td.bg then
            local fill = tb:CreateTexture(nil, "BACKGROUND", nil, -6)
            fill:SetColorTexture(0.02, 0.02, 0.02, 1)
            fill:SetAllPoints(tb)
            td.bg = fill
            WSkin.AddBorder(tb)
        end
    end
    if _G.MacroFrameSelectedMacroName then
        WSkin.Font(_G.MacroFrameSelectedMacroName)
        WSkin.White(_G.MacroFrameSelectedMacroName)
    end
    if _G.MacroFrameCharLimitText then WSkin.White(_G.MacroFrameCharLimitText) end
    if _G.MacroFrameScrollFrame then WSkin.ScrollBarsIn(_G.MacroFrameScrollFrame) end

    -- Layout nudges (all one-shot, points preserved): the selected-macro
    -- cluster between the icon grid and the text well rides up 7px --
    -- shifting only cluster members anchored OUTSIDE the cluster, so
    -- chained members don't double-move -- the text well up 3px (its
    -- scrollframe/input ride inside), and Save down 4px.
    local function ShiftOnce(el, dx, dy, cluster)
        if not el or GetFFD(el).nudged then return end
        local np = el:GetNumPoints() or 0
        local pts, ok = {}, np > 0
        for i = 1, np do
            local p, rel, rp, x, y = el:GetPoint(i)
            if not p then ok = false break end
            if cluster and rel and cluster[rel] then return end   -- chained inside: rides its root
            pts[i] = { p, rel, rp, (x or 0) + dx, (y or 0) + dy }
        end
        if ok then
            GetFFD(el).nudged = true
            el:ClearAllPoints()
            for i = 1, #pts do local t = pts[i]; el:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
        end
    end
    local cluster = {}
    for _, el in ipairs({ _G.MacroFrameSelectedMacroButton, _G.MacroFrameSelectedMacroName,
                          _G.MacroEditButton, _G.MacroFrameEnterMacroText }) do
        if el then cluster[el] = true end
    end
    for el in pairs(cluster) do ShiftOnce(el, 0, 7, cluster) end
    ShiftOnce(tb, 0, 3)
    -- Save/Cancel ride up 5 from the earlier seat (Save had -4 -> net +1
    -- from stock; Cancel +5 from stock). Pair-guarded: if Cancel chains off
    -- Save it rides along instead of double-shifting.
    local scPair = {}
    if _G.MacroSaveButton then scPair[_G.MacroSaveButton] = true end
    if _G.MacroCancelButton then scPair[_G.MacroCancelButton] = true end
    ShiftOnce(_G.MacroSaveButton, 0, 1, scPair)
    ShiftOnce(_G.MacroCancelButton, 0, 5, scPair)

    Skin_MacroPopup()

    if not _macroHooked then
        _macroHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Macros() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "macros",
    addons = { Blizzard_MacroUI = true },
    apply = Skin_Macros,
})

-------------------------------------------------------------------------------
--  Blizzard Options (SettingsPanel)
--  Chrome-level pass: shell, close X, search, bottom buttons, top tabs,
--  category rail, list scrollbars. The per-setting controls (checkboxes,
--  sliders, dropdowns in the list) stay stock -- that surface is huge and
--  taint-adjacent, iterate only if asked. NOTE: SettingsPanel.CloseButton is
--  the bottom TEXT button, so CommonChrome (which would X-glyph any
--  .CloseButton) is not used here; the pieces run individually.
-------------------------------------------------------------------------------
local _settingsHooked = false
local function Skin_Settings()
    local f = _G.SettingsPanel
    if not f then return end
    WSkin.Shell("settings", f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Bg and f.Bg.SetAlpha then f.Bg:SetAlpha(0) end
    if f.ClosePanelButton then WSkin.CloseButton(f.ClosePanelButton) end
    if f.SearchBox then WSkin.EditBox(f.SearchBox) end
    for _, k in ipairs({ "ApplyButton", "CloseButton" }) do
        local b = f[k]
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end
    local sTabs = {}
    for _, k in ipairs({ "GameTab", "AddOnsTab" }) do
        local t = f[k]
        if t then WSkin.Tab(t, { darkActive = true }); sTabs[#sTabs + 1] = t end
    end
    WSkin.NormalizeTabRow(sTabs)
    -- These tabs repaint their state art on hover/click (atlas re-sets on
    -- their own regions after our one-time clear): pin every Blizzard
    -- texture down with self-guarding fades, sparing our own pieces by
    -- identity. Selection isn't exposed the standard way either, so drive
    -- the FFD override from clicks (+ isSelected when Blizzard provides it).
    local function SyncSettingsTabs(clicked)
        for _, t in ipairs(sTabs) do
            local td = GetFFD(t)
            if clicked then
                td.selOverride = (t == clicked)
            elseif t.isSelected ~= nil then
                td.selOverride = t.isSelected and true or false
            elseif td.selOverride == nil then
                td.selOverride = (t == sTabs[1])   -- Game tab default
            end
        end
        WSkin.UpdateAllTabs()
    end
    for _, t in ipairs(sTabs) do
        local td = GetFFD(t)
        if not td.pinned then
            td.pinned = true
            for i = 1, select("#", t:GetRegions()) do
                local r = select(i, t:GetRegions())
                if r and r ~= td.bg and r ~= td.activeHL and r ~= td.underline
                   and r.IsObjectType and r:IsObjectType("Texture") then
                    r:SetAlpha(0)
                    for _, m in ipairs({ "SetAtlas", "SetTexture", "Show" }) do
                        if type(r[m]) == "function" then
                            hooksecurefunc(r, m, function(rr) rr:SetAlpha(0) end)
                        end
                    end
                end
            end
            t:HookScript("OnClick", function(self) SyncSettingsTabs(self) end)
        end
    end
    SyncSettingsTabs()

    -- Category rail: chrome off; pooled rows just lose their backdrop art
    -- (their select/hover washes stay Blizzard's).
    local cl = f.CategoryList
    if cl then
        WSkin.FadeRegions(cl)
        if cl.NineSlice then WSkin.FadeNineSlice(cl.NineSlice) end
        WSkin.Register(cl, true)
        WSkin.ScrollBarsIn(cl)
        local clBox = cl.ScrollBox
        if clBox then
            local cld = GetFFD(cl)
            if not cld.fadeRows then
                -- Box captured in the closure: Debounce invokes with NO args,
                -- so taking it as a parameter left it nil (rows never faded).
                cld.fadeRows = function()
                    if clBox.ForEachFrame and clBox:IsVisible() then
                        clBox:ForEachFrame(function(child)
                            if child.Background and child.Background.SetAlpha then
                                child.Background:SetAlpha(0)
                            end
                        end)
                    end
                end
                hooksecurefunc(clBox, "Update", WSkin.Debounce(cld.fadeRows))
            end
            -- Run on EVERY skin pass (each panel open re-runs Skin_Settings):
            -- the box populates at login and the first open fires no Update,
            -- so hook-only fading left the first view stock until a tab swap
            -- forced a rebuild.
            if clBox.GetView and clBox:GetView() then pcall(cld.fadeRows) end
        end
    end

    -- Settings list container: chrome off, defaults button, slim scrollbar.
    local ct = f.Container
    if ct then
        WSkin.FadeRegions(ct)
        WSkin.Register(ct, true)
        local sl = ct.SettingsList
        if sl then
            WSkin.FadeRegions(sl)
            if sl.NineSlice then WSkin.FadeNineSlice(sl.NineSlice) end
            WSkin.Register(sl, true)
            WSkin.ScrollBarsIn(sl)
            local hdr = sl.Header
            if hdr then
                if hdr.DefaultsButton then
                    WSkin.Button(hdr.DefaultsButton)
                    WSkin.WhiteButtonLabel(hdr.DefaultsButton)
                end
                if hdr.Title then WSkin.Font(hdr.Title); WSkin.White(hdr.Title) end
            end
        end
    end

    if not _settingsHooked then
        _settingsHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_Settings() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "settings",
    apply = Skin_Settings,
})

-------------------------------------------------------------------------------
--  AddOn List (AddonList)
--  Shell + buttons + dropdown/search + force-load checkbox; pooled rows get
--  the house checkbox and white title from Blizzard's row initializer.
-------------------------------------------------------------------------------
local _addonListHooked = false
local function Skin_AddonList()
    local f = _G.AddonList
    if not f then return end
    WSkin.Shell("addonlist", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "AddonList")   -- close X, SearchBox, Dropdown, scrollbar
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Inset then WSkin.Inset(f.Inset) end
    -- NO text coloring anywhere in this window (user call): Blizzard owns
    -- every label color -- title, buttons, checkbox labels, row texts.
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.AddonListTitleText
    if title then WSkin.Font(title) end
    for _, k in ipairs({ "EnableAllButton", "DisableAllButton", "OkayButton", "CancelButton" }) do
        local b = f[k]
        if b then WSkin.Button(b) end
    end
    if f.ForceLoad then
        WSkin.Checkbox(f.ForceLoad, { stockCheck = true })
        -- Tight border: the standard checkbox border spans the whole button,
        -- ~2px outside the dark box (the fill is inset 4px). Re-border a host
        -- pinned to the fill so the border hugs the black box exactly.
        local fld = GetFFD(f.ForceLoad)
        if not fld.tightBorder and fld.bg then
            fld.tightBorder = true
            local PPb = EllesmereUI.PP
            if PPb and PPb.GetBorders and PPb.HideBorder and PPb.GetBorders(f.ForceLoad) then
                PPb.HideBorder(f.ForceLoad)
            end
            local host = CreateFrame("Frame", nil, f.ForceLoad)
            host:SetAllPoints(fld.bg)
            host:SetFrameLevel(f.ForceLoad:GetFrameLevel())
            WSkin.AddBorder(host)
        end
    end

    -- Bottom bar: the shell top bar's exact black 0.5, covering the button
    -- row. On its own child frame so the shell's region fades never touch it.
    local ald = GetFFD(f)
    if not ald.botBar then
        local bhost = CreateFrame("Frame", nil, f)
        bhost:SetAllPoints(f)
        bhost:SetFrameLevel(f:GetFrameLevel())
        local bar = bhost:CreateTexture(nil, "BACKGROUND", nil, -5)
        bar:SetColorTexture(0, 0, 0, 0.5)
        bar:SetPoint("BOTTOMLEFT")
        bar:SetPoint("BOTTOMRIGHT")
        bar:SetHeight(30)
        ald.botBar = bar
    end
    -- The addon list must stop at the bar's top edge (measured one-shot,
    -- rect-gated -- retried by the show re-run).
    local abox = f.ScrollBox
    if abox and not GetFFD(abox).botClamped then
        local fb, bb2 = f:GetBottom(), abox:GetBottom()
        if fb and bb2 then
            local dy = (fb + 30) - bb2
            if dy > 0.5 then
                local np = abox:GetNumPoints() or 0
                local pts, ok, touched = {}, np > 0, false
                for i = 1, np do
                    local p, rel, rp, x, y = abox:GetPoint(i)
                    if not p then ok = false break end
                    local isBottom = p:find("BOTTOM", 1, true) and true or false
                    if isBottom then touched = true end
                    pts[i] = { p, rel, rp, x or 0, (y or 0) + (isBottom and dy or 0) }
                end
                if ok and touched then
                    GetFFD(abox).botClamped = true
                    abox:ClearAllPoints()
                    for i = 1, #pts do local t = pts[i]; abox:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
                end
            else
                GetFFD(abox).botClamped = true
            end
        end
    end

    if not _addonListHooked then
        _addonListHooked = true
        -- Pooled rows: house checkbox only -- ALL row text colors (title,
        -- status, reload, load-button label) stay Blizzard's.
        if type(_G.AddonList_InitAddon) == "function" then
            hooksecurefunc("AddonList_InitAddon", function(entry)
                if not entry or (entry.IsForbidden and entry:IsForbidden()) then return end
                if entry.Enabled then WSkin.Checkbox(entry.Enabled, { stockCheck = true }) end
                if entry.LoadAddonButton and not GetFFD(entry.LoadAddonButton).skinned then
                    WSkin.Button(entry.LoadAddonButton)
                end
            end)
        end
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_AddonList() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "addonlist",
    apply = Skin_AddonList,
})

-------------------------------------------------------------------------------
--  Crafting Orders, customer side (ProfessionsCustomerOrdersFrame,
--  Blizzard_ProfessionsCustomerOrders). Near-identical layout to the auction
--  house, so this replicates the AH treatments: zone lines + wash on the
--  browse view, tile rail, AH search bar (favorites star, filter with house
--  X + left label), per-list sort strips with full-height hovers, refresh
--  glyph, state-aware action buttons, money boxes with global-suffix art.
-------------------------------------------------------------------------------
local _craftHooked = false
local function Skin_CraftOrders()
    local f = _G.ProfessionsCustomerOrdersFrame
    if not f then return end
    WSkin.Shell("craftorders", f)
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    for _, k in ipairs({ "MoneyFrameBorder", "MoneyFrameInset" }) do
        local el = f[k]
        if el then
            WSkin.FadeRegions(el)
            if el.NineSlice then WSkin.FadeNineSlice(el.NineSlice) end
            WSkin.Register(el, true)
        end
    end

    local function WhiteBtn(b)
        if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
    end
    local function StateBtn(b)
        if b then WSkin.Button(b); WSkin.StateButtonLabel(b) end
    end
    local function MoneyBox(eb)
        if not eb then return end
        WSkin.EditBox(eb)
        local n = eb.GetName and eb:GetName()
        if n then
            for _, suf in ipairs({ "Left", "Middle", "Right" }) do
                local t = _G[n .. suf]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
        end
        -- Tip gold/silver inputs run 6px shorter (one-shot).
        if not GetFFD(eb).slimmed then
            GetFFD(eb).slimmed = true
            local h = eb:GetHeight()
            if h and h > 6 then eb:SetHeight(h - 6) end
        end
    end
    -- AH sort headers: invisible plates over a 50% near-black strip riding
    -- the header row (strip spans the LIST's width here -- this window has
    -- no shared wash rect per list), white labels, hover stretched to the
    -- strip. Strip spared from our fades via identity + the fill key.
    local function Headers(list)
        local hc = list and list.HeaderContainer
        if not hc then return end
        local sd = GetFFD(list)
        if not sd.strip then
            local sTex = list:CreateTexture(nil, "BACKGROUND", nil, 1)
            sTex:SetColorTexture(0.02, 0.02, 0.02, 0.5)
            sTex:SetHeight(24)
            sd.strip = sTex
            sd.fill = sTex
        end
        sd.strip:SetAlpha(1)
        local ll0, lr0 = list:GetLeft(), list:GetRight()
        local hl0 = hc:GetLeft()
        if ll0 and lr0 and hl0 then
            sd.strip:ClearAllPoints()
            sd.strip:SetPoint("TOPLEFT", hc, "TOPLEFT", ll0 - hl0, 2)
            sd.strip:SetPoint("TOPRIGHT", hc, "TOPLEFT", lr0 - hl0, 2)
        end
        for i = 1, select("#", hc:GetChildren()) do
            local col = select(i, hc:GetChildren())
            if col and col.GetObjectType and col:GetObjectType() == "Button" then
                local hd = GetFFD(col)
                if not hd.bg then
                    for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                        local t2 = col[k2]
                        if t2 and t2.SetTexture then t2:SetTexture("") end
                    end
                    WSkin.FadeRegions(col)
                    local bg = SolidTex(col, "BACKGROUND", 0.02, 0.02, 0.02, 0)
                    bg:SetPoint("TOPLEFT", 1, -1)
                    bg:SetPoint("BOTTOMRIGHT", -1, 1)
                    hd.bg = bg
                    local hov = SolidTex(col, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hov:SetAllPoints(col)
                    hd.hover = hov
                end
                local fs = col.GetFontString and col:GetFontString()
                if fs then WSkin.White(fs) end
                local strip = sd.strip
                if hd.hover and strip and strip.GetTop then
                    local st, sbot = strip:GetTop(), strip:GetBottom()
                    local ct, cbot = col:GetTop(), col:GetBottom()
                    if st and sbot and ct and cbot then
                        hd.hover:ClearAllPoints()
                        hd.hover:SetPoint("TOPLEFT", col, "TOPLEFT", 0, st - ct)
                        hd.hover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, sbot - cbot)
                    end
                end
            end
        end
    end
    local function SkinRefreshBtn(rb)
        if rb and not GetFFD(rb).glyph
           and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-RefreshButton") then
            local d = GetFFD(rb)
            for i = 1, select("#", rb:GetRegions()) do
                local r = select(i, rb:GetRegions())
                if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
            for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture",
                                 "GetHighlightTexture", "GetDisabledTexture" }) do
                local t = rb[g] and rb[g](rb)
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            local glyph = rb:CreateTexture(nil, "OVERLAY")
            glyph:SetAtlas("UI-RefreshButton", false)
            glyph:SetSize(16, 16)
            glyph:SetPoint("CENTER")
            glyph:SetDesaturated(true)
            glyph:SetVertexColor(1, 1, 1, 0.9)
            d.glyph = glyph
            rb:HookScript("OnEnter", function() glyph:SetVertexColor(1, 1, 1, 1) end)
            rb:HookScript("OnLeave", function() glyph:SetVertexColor(1, 1, 1, 0.9) end)
        end
    end
    local function List(list)
        if not list then return end
        local ld = GetFFD(list)
        WSkin.FadeRegions(list, ld.strip and { [ld.strip] = true } or nil)
        if list.NineSlice then WSkin.FadeNineSlice(list.NineSlice) end
        WSkin.Register(list, true)
        WSkin.ScrollBarsIn(list)
        Headers(list)
        if not ld.hdrShowHook then
            ld.hdrShowHook = true
            list:HookScript("OnShow", WSkin.Debounce(function() Headers(list) end))
        end
    end

    local ad = GetFFD(f)
    local browse = f.BrowseOrders
    -- Zone lines (AH treatment): top/bottom seams on the window; rail-edge
    -- divider + 2% wash parented to the BROWSE view so they vanish with it
    -- (my-orders + form have no rail).
    if not ad.zoneLines and browse and browse.CategoryList then
        ad.zoneLines = true
        local px = 1
        do
            local PPx = EllesmereUI.PP
            local es = f:GetEffectiveScale()
            if PPx and PPx.perfect and es and es > 0 then px = PPx.perfect / es end
        end
        ad.zonePx = px
        local host = CreateFrame("Frame", nil, f)
        host:SetAllPoints(f)
        host:SetFrameLevel(f:GetFrameLevel())
        local topSep = host:CreateTexture(nil, "ARTWORK")
        topSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        topSep:SetHeight(px)
        topSep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -77)
        topSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -77)
        ad.topSep = topSep
        local botSep = host:CreateTexture(nil, "ARTWORK")
        botSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        botSep:SetHeight(px)
        botSep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 30)
        botSep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30)
        local railHost = CreateFrame("Frame", nil, browse)
        railHost:SetAllPoints(browse)
        railHost:SetFrameLevel(browse:GetFrameLevel())
        local cl2 = browse.CategoryList
        local wash = railHost:CreateTexture(nil, "BACKGROUND")
        wash:SetColorTexture(1, 1, 1, 0.02)
        wash:SetPoint("TOPLEFT", cl2, "TOPRIGHT", px, 2)   -- 2px wider than the AH gap; top 3px lower
        wash:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30 + px)
        ad.wash = wash
        local sideSep = railHost:CreateTexture(nil, "ARTWORK")
        sideSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        sideSep:SetWidth(px)
        sideSep:SetPoint("TOPLEFT", wash, "TOPLEFT", -px, 0)
        sideSep:SetPoint("BOTTOMLEFT", wash, "BOTTOMLEFT", -px, 0)
        -- FORM zone: split-section wash on the right + vertical divider,
        -- mirroring the AH sell tab. The divider seats a few px right of the
        -- recipe favorite star (measured off the right panel's left edge).
        -- Hidden until the order form shows.
        local formHost = CreateFrame("Frame", nil, host)
        formHost:SetAllPoints(host)
        formHost:SetFrameLevel(host:GetFrameLevel())
        formHost:Hide()
        ad.formHost = formHost
        local formWash = formHost:CreateTexture(nil, "BACKGROUND")
        formWash:SetColorTexture(1, 1, 1, 0.02)
        -- TOPLEFT seated later (needs the panel rect); centre keeps it valid.
        formWash:SetPoint("TOPLEFT", f, "TOP", 0, -77 - px)
        formWash:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30 + px)
        ad.formWash = formWash
        local formSep = formHost:CreateTexture(nil, "ARTWORK")
        formSep:SetColorTexture(0.15, 0.15, 0.15, 1)
        formSep:SetWidth(px)
        formSep:SetPoint("TOPLEFT", formWash, "TOPLEFT", -px, 0)
        formSep:SetPoint("BOTTOMLEFT", formWash, "BOTTOMLEFT", -px, 0)
    end
    -- Rail 2px wider (left edge out; the right edge stays, so the divider and
    -- wash anchored off it don't move). One-shot, points preserved.
    local cl0 = browse and browse.CategoryList
    if cl0 and not GetFFD(cl0).widened then
        local np = cl0:GetNumPoints() or 0
        local pts, ok = {}, np > 0
        for i = 1, np do
            local p, rel, rp, x, y = cl0:GetPoint(i)
            if not p then ok = false break end
            pts[i] = { p, rel, rp, (x or 0) - (p:find("LEFT", 1, true) and 2 or 0), y or 0 }
        end
        if ok then
            GetFFD(cl0).widened = true
            cl0:ClearAllPoints()
            for i = 1, #pts do local t = pts[i]; cl0:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
        end
    end
    -- Top divider rides the ACTIVE view's top bar: the browse wash top on the
    -- Browse tab, or the My Orders list header top on My Orders (the browse
    -- wash is hidden there, so its rect is stale). Re-measured every pass while
    -- that anchor is visible (a one-shot could latch a stale early measurement)
    -- and frame-anchored (full width) so it holds across tab swaps.
    if ad.topSep then
        local ft = f:GetTop()
        local topY, off
        if ad.wash and ad.wash:IsVisible() then
            topY, off = ad.wash:GetTop(), 4          -- +4px wash visual-flush offset
        else
            local mo0 = f.MyOrdersPage
            local hc = mo0 and mo0:IsVisible() and mo0.OrderList and mo0.OrderList.HeaderContainer
            local hct = hc and hc:GetTop()
            if hct then topY, off = hct + 2, 0 end   -- +2 = the header strip's own lift above hc
        end
        if ft and topY then
            local y = (topY - ft) + (ad.zonePx or 1) + off
            ad.topSep:ClearAllPoints()
            ad.topSep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
            ad.topSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        end
    end

    -- Seat the form split divider a few px right of the recipe favorite star
    -- (measured off the right panel's left edge). One-shot, retried per skin
    -- pass until the form has laid out (the form OnShow hook re-runs us).
    do
        local rp = f.Form and f.Form.RightPanelBackground
        if ad.formWash and ad.topSep and rp and not ad.formSeated then
            local rl, flx = rp:GetLeft(), f:GetLeft()
            if rl and flx then
                ad.formSeated = true
                -- Top rides the top divider's bottom edge (flush, live), X is
                -- the panel boundary + 6 (topSep BOTTOMLEFT X == frame left).
                ad.formWash:ClearAllPoints()
                ad.formWash:SetPoint("TOPLEFT", ad.topSep, "BOTTOMLEFT", (rl - flx) + 6, 0)
                ad.formWash:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 30 + (ad.zonePx or 1))
            end
        end
    end

    if browse then
        -- Re-run on tab show so the top divider re-seats to the browse wash
        -- when switching back from My Orders (bottom-tab switches don't
        -- otherwise re-trigger the skin).
        if not ad.browseShowHook then
            ad.browseShowHook = true
            browse:HookScript("OnShow", WSkin.Debounce(function() Skin_CraftOrders() end))
        end
        -- Search bar: AH treatment verbatim.
        local sb = browse.SearchBar
        if sb then
            WhiteBtn(sb.SearchButton)
            if sb.FavoritesSearchButton then
                WSkin.Button(sb.FavoritesSearchButton, { "Icon" })
                for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
                    local t = sb.FavoritesSearchButton[g] and sb.FavoritesSearchButton[g](sb.FavoritesSearchButton)
                    if t and t.SetAlpha then t:SetAlpha(1) end
                end
            end
            local fb = sb.FilterDropdown or sb.FilterButton
            if fb then
                LeftAlignFilterLabel(fb)
                local sbtn = sb.SearchButton
                local h = sbtn and sbtn.GetHeight and sbtn:GetHeight()
                if h and h > 0 and fb.SetHeight then fb:SetHeight(h) end
                SkinFilterResetX(fb.ResetButton or fb.ClearFiltersButton, fb)
            end
        end
        -- Category rail: chrome off + pooled rows as sidebar tiles (AH rail
        -- treatment; NOT restrip-registered -- the Update hook is upkeep).
        local cl = browse.CategoryList
        if cl then
            WSkin.FadeRegions(cl)
            if cl.NineSlice then WSkin.FadeNineSlice(cl.NineSlice) end
            WSkin.Register(cl, true)
            WSkin.ScrollBarsIn(cl)
            -- Rail row spacing -1 via the scroll view's padding (the AH rail
            -- treatment; per-row anchor surgery is a no-op on ScrollBox rows).
            if not GetFFD(cl).spacingSet then
                local box0 = cl.ScrollBox
                local view0 = box0 and box0.GetView and box0:GetView()
                if view0 and view0.SetPadding then
                    GetFFD(cl).spacingSet = true
                    pcall(function()
                        local t, b, l, r = 0, 0, 0, 0
                        local pad = view0.GetPadding and view0:GetPadding()
                        if pad then
                            t = (pad.GetTop and pad:GetTop()) or 0
                            b = (pad.GetBottom and pad:GetBottom()) or 0
                            l = (pad.GetLeft and pad:GetLeft()) or 0
                            r = (pad.GetRight and pad:GetRight()) or 0
                        end
                        view0:SetPadding(t, b, l, r, -1)
                        if box0.FullUpdate then box0:FullUpdate(true) end
                    end)
                end
            end
            local clBox = cl.ScrollBox
            if clBox and not GetFFD(cl).rowHook then
                GetFFD(cl).rowHook = true
                local function SkinRailRow(row)
                    if not row or (row.IsForbidden and row:IsForbidden()) then return end
                    local rd = GetFFD(row)
                    if not rd.bg then
                        local bg = row:CreateTexture(nil, "BACKGROUND", nil, -3)
                        bg:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                        bg:SetPoint("TOPLEFT", 1, -1)
                        bg:SetPoint("BOTTOMRIGHT", -1, 1)
                        rd.bg = bg
                        WSkin.AddBorder(row)
                    end
                    for _, k in ipairs({ "NormalTexture", "SelectedTexture", "SelectedHighlight" }) do
                        local t = row[k]
                        if t then
                            if k == "NormalTexture" then t:SetAlpha(0)
                            else
                                t:SetColorTexture(1, 1, 1, 0.15)
                                t:ClearAllPoints()
                                t:SetAllPoints(row)
                            end
                        end
                    end
                    if row.HighlightTexture then
                        row.HighlightTexture:SetColorTexture(1, 1, 1, 0.1)
                        row.HighlightTexture:ClearAllPoints()
                        row.HighlightTexture:SetAllPoints(row)
                    end
                    local fs = row.Text or (row.GetFontString and row:GetFontString())
                    if fs then WSkin.White(fs) end
                end
                local function SkinRailRows()
                    if clBox.ForEachFrame and clBox:IsVisible() then
                        clBox:ForEachFrame(SkinRailRow)
                    end
                end
                GetFFD(cl).railRows = SkinRailRows
                hooksecurefunc(clBox, "Update", WSkin.Debounce(SkinRailRows))
            end
            local rr = GetFFD(cl).railRows
            if rr and clBox and clBox.GetView and clBox:GetView() then pcall(rr) end
        end
        -- Results list; headers rebuild via SetupTable.
        List(browse.RecipeList)
        if browse.SetupTable and not GetFFD(browse).tableHook then
            GetFFD(browse).tableHook = true
            hooksecurefunc(browse, "SetupTable", WSkin.Debounce(function()
                Headers(browse.RecipeList)
            end))
        end
    end

    -- Order form (item-detail equivalent).
    local form = f.Form
    if form then
        -- Toggle the form split zone with the form, and re-run the skin on
        -- show so the divider seats once the panels have laid out.
        if not ad.formShowHook then
            ad.formShowHook = true
            local function SyncFormZone()
                if ad.formHost then ad.formHost:SetShown(form:IsShown() and true or false) end
            end
            form:HookScript("OnShow", WSkin.Debounce(function()
                SyncFormZone(); Skin_CraftOrders()
            end))
            form:HookScript("OnHide", SyncFormZone)
            SyncFormZone()
        end
        WhiteBtn(form.BackButton)
        for _, k in ipairs({ "RecipeHeader", "LeftPanelBackground", "RightPanelBackground" }) do
            local el = form[k]
            if el then
                if el.IsObjectType and el:IsObjectType("Texture") then
                    el:SetAlpha(0)
                else
                    WSkin.FadeRegions(el)
                    WSkin.Register(el, true)
                end
            end
        end
        if form.TrackRecipeCheckbox and form.TrackRecipeCheckbox.Checkbox then
            WSkin.Checkbox(form.TrackRecipeCheckbox.Checkbox, { borderInset = 2 })
        end
        if form.AllocateBestQualityCheckbox then WSkin.Checkbox(form.AllocateBestQualityCheckbox) end
        local ddRecip = form.OrderRecipientDropdown
        local tgtRecip = form.OrderRecipientTarget
        if tgtRecip then WSkin.EditBox(tgtRecip) end
        if ddRecip then WSkin.Dropdown(ddRecip) end
        -- Recipient dropdown + its "To:" target input drop 10px (idempotent
        -- capture). Shift the dropdown; shift the target too only when it isn't
        -- anchored to the dropdown (else it already followed).
        local function ShiftDown10(fr)
            if not fr or GetFFD(fr).shift10 then return end
            local np = fr:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = fr:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, x or 0, (y or 0) - 10 }
            end
            if ok then
                GetFFD(fr).shift10 = true
                fr:ClearAllPoints()
                for i = 1, #pts do local t = pts[i]; fr:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            end
        end
        ShiftDown10(ddRecip)
        if tgtRecip then
            local anchoredToDD = false
            for i = 1, (tgtRecip:GetNumPoints() or 0) do
                local _, rel = tgtRecip:GetPoint(i)
                if rel == ddRecip then anchoredToDD = true break end
            end
            if not anchoredToDD then ShiftDown10(tgtRecip) end
        end
        if form.MinimumQuality and form.MinimumQuality.Dropdown then
            WSkin.Dropdown(form.MinimumQuality.Dropdown)
        end
        local pay = form.PaymentContainer
        if pay then
            if pay.NoteEditBox then
                WSkin.FadeRegions(pay.NoteEditBox)
                WSkin.Register(pay.NoteEditBox, true)
                -- 50% black backing on the actual scrolling field (NoteEditBox
                -- is only a wrapper; its bounds don't cover the visible box).
                -- Stored under the protected "bg" key so a Restrip never fades.
                local seb = pay.NoteEditBox.ScrollingEditBox
                local sbox = seb and seb.ScrollBox
                if sbox and not GetFFD(sbox).bg then
                    local bg = sbox:CreateTexture(nil, "BACKGROUND", nil, -7)
                    bg:SetColorTexture(0, 0, 0, 0.5)
                    bg:SetAllPoints(sbox)
                    GetFFD(sbox).bg = bg
                end
            end
            if pay.TipMoneyInputFrame then
                MoneyBox(pay.TipMoneyInputFrame.GoldBox)
                MoneyBox(pay.TipMoneyInputFrame.SilverBox)
            end
            if pay.DurationDropdown then WSkin.Dropdown(pay.DurationDropdown) end
            StateBtn(pay.ListOrderButton)
            StateBtn(pay.CancelOrderButton)
        end
        local cls = form.CurrentListings
        if cls then
            WSkin.Panel(cls)
            if cls.CloseButton then WSkin.CloseButton(cls.CloseButton) end
            List(cls.OrderList)
        end
        local qd = form.QualityDialog
        if qd then
            WSkin.Panel(qd)
            if qd.Bg and qd.Bg.SetAlpha then qd.Bg:SetAlpha(0) end
            if qd.ClosePanelButton then WSkin.CloseButton(qd.ClosePanelButton) end
            WhiteBtn(qd.AcceptButton)
            WhiteBtn(qd.CancelButton)
            for i = 1, 3 do
                local c = qd["Container" .. i]
                if c and c.EditBox then WSkin.EditBox(c.EditBox) end
            end
        end
    end

    -- My orders page.
    local mo = f.MyOrdersPage
    if mo then
        -- Re-run on tab show so the top divider re-seats to this list's top
        -- (nothing else re-triggers the skin on a bottom-tab switch).
        if not ad.moShowHook then
            ad.moShowHook = true
            mo:HookScript("OnShow", WSkin.Debounce(function() Skin_CraftOrders() end))
        end
        SkinRefreshBtn(mo.RefreshButton)
        List(mo.OrderList)
    end

    -- Bottom tabs (frame.Tabs table, AH-style). Confirmed via live dump these
    -- carry none of the standard selection fields (tabID/selectedTabID,
    -- isSelected, displayMode are all nil, and there's no GetDisplayMode API
    -- either) so the engine's TabIsSelected() never matches and neither tab
    -- ever shows active. Selection here is purely which content page is
    -- shown, so sync the FFD override from BrowseOrders/MyOrdersPage
    -- visibility instead (mirrors the Auction House's displayMode-based
    -- SyncTabSel). Runs every Skin_CraftOrders() pass, which the browse/mo
    -- OnShow hooks below already re-trigger on every tab switch.
    local coTabs = {}
    if type(f.Tabs) == "table" then
        for _, t in ipairs(f.Tabs) do
            if t then WSkin.Tab(t); coTabs[#coTabs + 1] = t end
        end
    end
    WSkin.NormalizeTabRow(coTabs)
    for _, t in ipairs(coTabs) do
        local name = t.GetName and t:GetName()
        if name and name:find("BrowseTab", 1, true) then
            GetFFD(t).selOverride = (f.BrowseOrders and f.BrowseOrders:IsShown()) and true or false
        elseif name and name:find("OrdersTab", 1, true) then
            GetFFD(t).selOverride = (f.MyOrdersPage and f.MyOrdersPage:IsShown()) and true or false
        end
    end
    WSkin.UpdateAllTabs()

    if not _craftHooked then
        _craftHooked = true
        WSkin.HookShow(f, WSkin.Debounce(function()
            if f:IsVisible() then Skin_CraftOrders() end
        end))
    end
end

WSkin.RegisterWindow({
    key = "craftorders",
    addons = { Blizzard_ProfessionsCustomerOrders = true },
    apply = Skin_CraftOrders,
})
