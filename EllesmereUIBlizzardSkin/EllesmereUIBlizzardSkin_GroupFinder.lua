-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_GroupFinder.lua
--  Dark, minimal reskin of Blizzard's Group Finder window (PVEFrame): Dungeon
--  Finder, Premade Groups (LFGList), Raid Finder, and the Mythic+ panel, themed
--  to match the rest of EllesmereUI (CharacterSheet / Bags house style).
--
--  Scope: this file owns the PVEFrame WINDOW and everything docked inside it
--  (shell, bottom tabs, left category rail, the LFD / RaidFinder / LFGList /
--  Challenges panels and their widgets). Transient floating popups (the ready
--  dialog, the premade invite/application dialogs, the role-check popup) are
--  owned by the separate "Reskin Queue Popup" feature and are NOT touched here.
--
--  Taint / secret-value safety (read before editing):
--   - All per-frame skin state lives in an EXTERNAL weak-keyed table (FFD), never
--     as custom keys on Blizzard frame tables. (CLAUDE.md hard rule.)
--   - Visual-only: we SetAlpha(0) native textures and lay our own layers under
--     them. We NEVER Hide/Show/SetParent a Blizzard frame and never recurse
--     EnableMouse over the frame tree.
--   - Post-hooks only (hooksecurefunc) on globals/methods; HookScript (never
--     SetScript) on secure frames. The original secure handler always runs first.
--   - We NEVER read per-result/per-member search data. In Midnight the browse/
--     apply phase makes GetSearchResultInfo (and member/leader info) SECRET, and
--     reading it throws. We only restyle row regions, never inspect their data.
--   - The whole skin is gated on EllesmereUIDB.reskinLFGMenu; when off, no hooks
--     are installed and the file costs nothing.
-------------------------------------------------------------------------------
local ADDON_NAME = ...
local EUI = EllesmereUI
local issecretvalue = issecretvalue or function() return false end

-- Weak-keyed external state (prevents tainting Blizzard frames) ----------------
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Enable gate. Default seeds ON only if the user already runs the matching
--  Blizzard-skin toggles, then is stored fixed thereafter.
-------------------------------------------------------------------------------
local function SkinEnabled()
    if not EllesmereUIDB then return false end
    if EllesmereUIDB.reskinLFGMenu == nil then
        EllesmereUIDB.reskinLFGMenu = (EllesmereUIDB.customTooltips ~= false) and (EllesmereUIDB.reskinQueuePopup ~= false)
    end
    return EllesmereUIDB.reskinLFGMenu
end

-------------------------------------------------------------------------------
--  Theme tokens. Resolved once at apply time; the accent is theme-driven and
--  re-registered via RegAccent so it tracks the user's accent color live.
-------------------------------------------------------------------------------
local Theme = {}
local function ResolveTheme()
    local EG = (EUI and EUI.ELLESMERE_GREEN) or { r = 0.047, g = 0.824, b = 0.616 }
    Theme.accR, Theme.accG, Theme.accB = EG.r or 0.047, EG.g or 0.824, EG.b or 0.616
    -- Cool dark glass, matching the EUI-native popup family.
    Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA = 0.06, 0.08, 0.10, 0.92
    -- Darker fill for nested insets so sub-panels melt into the main backdrop.
    Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA = 0.03, 0.045, 0.05, 0.85
    -- Panel border (matches CharacterSheet grey).
    Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA = 0.2, 0.2, 0.2, 1
    Theme.fontPath = (EUI and EUI.GetFontPath and EUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
end

local function SolidTex(parent, layer, r, g, b, a, sublevel)
    if EUI and EUI.SolidTex and sublevel == nil then
        return EUI.SolidTex(parent, layer, r, g, b, a)
    end
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function AddBorder(frame, r, g, b, a)
    if GetFFD(frame).border then return end
    local PP = EUI and (EUI.PanelPP or EUI.PP)
    if PP and PP.CreateBorder then
        PP.CreateBorder(frame, r or Theme.brdR, g or Theme.brdG, b or Theme.brdB, a or Theme.brdA, 1, "OVERLAY", 7)
        GetFFD(frame).border = true
    end
end

-------------------------------------------------------------------------------
--  FadeRegions: alpha-out every direct texture region on a frame (+ NineSlice).
--  `keep` is a set of texture objects to leave alone. Visual-only, no Hide().
-------------------------------------------------------------------------------
local function FadeRegions(frame, keep)
    if not frame or frame:IsForbidden() then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.IsObjectType and r:IsObjectType("Texture") and not (keep and keep[r]) then
            r:SetAlpha(0)
        end
    end
    if frame.NineSlice then FadeRegions(frame.NineSlice, keep) end
end

-- Frames we have skinned; re-flattened whenever Blizzard repaints (tab switch,
-- category click). Strong refs are fine: these are all permanent frames.
local _restrip = {}
local function Register(frame, keep) if frame then _restrip[frame] = keep or true end end
local function Restrip()
    for frame, keep in pairs(_restrip) do
        if frame and not frame:IsForbidden() then
            local k = (type(keep) == "table") and keep or nil
            local d = FFD[frame]
            if d and d.bg then k = k or {}; k[d.bg] = true end
            if d and d.bgOverlay then k = k or {}; k[d.bgOverlay] = true end
            FadeRegions(frame, k)
        end
    end
end

-------------------------------------------------------------------------------
--  Primitive skinners
-------------------------------------------------------------------------------

-- Cover-fit modern_blizz atlas backdrop (matches CharacterSheet). Used for the
-- PVEFrame shell only.
local BG_ASPECT = 561 / 433
local function SkinAtlasPanel(frame)
    if not frame or frame:IsForbidden() then return end
    local d = GetFFD(frame)
    local keep = {}
    if d.bg then keep[d.bg] = true end
    if d.bgOverlay then keep[d.bgOverlay] = true end
    FadeRegions(frame, keep)
    Register(frame, true)
    if not d.bg then
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
        bg:SetAllPoints(frame)
        d.bg = bg
        local overlay = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        overlay:SetColorTexture(0, 0, 0, 0.55)
        overlay:SetAllPoints(frame)
        d.bgOverlay = overlay

        local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
        local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T
        local function UpdateBgTexCoords()
            local fw, fh = frame:GetSize()
            if fw == 0 or fh == 0 then return end
            local fa = fw / fh
            if fa > BG_ASPECT then
                local visV = BASE_V * (BG_ASPECT / fa)
                local trimV = (BASE_V - visV) / 2
                bg:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
            else
                local visU = BASE_U * (fa / BG_ASPECT)
                local trimU = (BASE_U - visU) / 2
                bg:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
            end
        end
        hooksecurefunc(frame, "SetSize", UpdateBgTexCoords)
        hooksecurefunc(frame, "SetWidth", UpdateBgTexCoords)
        hooksecurefunc(frame, "SetHeight", UpdateBgTexCoords)
        UpdateBgTexCoords()
    end
    AddBorder(frame)
end

-- Flat solid panel. opts.noBg = strip only (let the parent backdrop show through);
-- opts.inset = darker nested fill; opts.noBorder = skip border.
local function SkinPanel(frame, opts)
    if not frame or frame:IsForbidden() then return end
    opts = opts or {}
    local d = GetFFD(frame)
    local keep = {}
    if d.bg then keep[d.bg] = true end
    FadeRegions(frame, keep)
    Register(frame, true)
    if not d.bg and not opts.noBg then
        local r, g, b, a = Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA
        if opts.inset then r, g, b, a = Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA end
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetColorTexture(r, g, b, a)
        bg:SetAllPoints(frame)
        d.bg = bg
    end
    if not opts.noBorder then AddBorder(frame) end
end

-- Strip an InsetFrameTemplate child (its Bg + rounded box) so it blends into the
-- panel backdrop instead of showing a nested box.
local function FadeInset(inset)
    if not inset or inset:IsForbidden() then return end
    FadeRegions(inset)
    if inset.Bg then inset.Bg:SetAlpha(0) end
    if inset.NineSlice then FadeRegions(inset.NineSlice) end
    Register(inset, true)
end

local function SkinFontString(fs)
    if not fs or fs:IsForbidden() then return end
    local _, size = fs:GetFont()
    if size and issecretvalue(size) then return end
    fs:SetFont(Theme.fontPath, size or 12, "")
end

-- Generic action button -> flat dark block with hover. keepKeys preserves named
-- regions (e.g. {"Icon"}); never reads any data.
local function SkinButton(btn, keepKeys)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if d.skinned then return end
    d.skinned = true

    local keep = {}
    if keepKeys then
        for _, k in ipairs(keepKeys) do
            local r = btn[k]; if r then keep[r] = true end
        end
    end
    FadeRegions(btn, keep)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local fn = btn[getter]
        local t = fn and fn(btn)
        if t and not keep[t] then t:SetAlpha(0) end
    end
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        local r = btn[k]; if r and not keep[r] and r.SetAlpha then r:SetAlpha(0) end
    end

    local fill = SolidTex(btn, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fill:SetAllPoints(btn)
    d.bg = fill
    AddBorder(btn)

    local hover = SolidTex(btn, "HIGHLIGHT", Theme.accR, Theme.accG, Theme.accB, 0.18)
    hover:SetAllPoints(btn)

    local fs = btn.GetFontString and btn:GetFontString()
    if fs then SkinFontString(fs) end
    Register(btn, keep)
end

-- Search / input box -> flat block, keep the magnifier + clear button art.
local function SkinEditBox(eb)
    if not eb or eb:IsForbidden() then return end
    local d = GetFFD(eb)
    if d.bg then return end
    FadeRegions(eb)
    for _, k in ipairs({ "Left", "Right", "Middle" }) do
        local r = eb[k]; if r and r.SetAlpha then r:SetAlpha(0) end
    end
    local fill = SolidTex(eb, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fill:SetAllPoints(eb)
    d.bg = fill
    AddBorder(eb, 0.25, 0.25, 0.25, 1)
end

-- Checkbox -> strip native check art, keep the check tick, frame it.
local function SkinCheckbox(cb)
    if not cb or cb:IsForbidden() then return end
    local d = GetFFD(cb)
    if d.skinned then return end
    d.skinned = true
    if cb.SetNormalTexture then cb:SetNormalTexture("") end
    if cb.SetPushedTexture then cb:SetPushedTexture("") end
    if cb.SetHighlightTexture then cb:SetHighlightTexture("") end
    local fill = SolidTex(cb, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fill:SetPoint("TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", -4, 4)
    d.bg = fill
    AddBorder(cb, 0.25, 0.25, 0.25, 1)
    -- Tint the checked tick to the accent without touching its geometry.
    local checked = cb.GetCheckedTexture and cb:GetCheckedTexture()
    if checked then checked:SetVertexColor(Theme.accR, Theme.accG, Theme.accB, 1) end
end

-- Modern dropdown / selector -> flat block. Heavily nil-guarded because the
-- dropdown template changes shape across builds; a mismatch simply no-ops.
local function SkinDropdown(dd)
    if not dd or dd:IsForbidden() then return end
    local d = GetFFD(dd)
    if d.skinned then return end
    d.skinned = true
    FadeRegions(dd)
    -- Legacy UIDropDownMenu textures, if present.
    local name = dd.GetName and dd:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
            local r = _G[name .. suffix]; if r and r.SetAlpha then r:SetAlpha(0) end
        end
    end
    if dd.Background then dd.Background:SetAlpha(0) end
    if dd.Texture then dd.Texture:SetAlpha(0) end
    if dd.Arrow and dd.Arrow.SetVertexColor then dd.Arrow:SetVertexColor(0.8, 0.8, 0.8) end
    local fill = SolidTex(dd, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fill:SetAllPoints(dd)
    d.bg = fill
    AddBorder(dd, 0.25, 0.25, 0.25, 1)
end

-- MinimalScrollBar -> strip track/arrows, flat accent thumb.
local function SkinScrollBar(sb)
    if not sb or sb:IsForbidden() then return end
    local d = GetFFD(sb)
    if d.skinned then return end
    d.skinned = true
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = sb[k]
        if b then
            FadeRegions(b)
            if b.Texture then b.Texture:SetAlpha(0) end
        end
    end
    local track = sb.Track
    if track then FadeRegions(track) end
    local thumb = (track and track.Thumb) or (sb.GetThumb and sb:GetThumb())
    if thumb and not GetFFD(thumb).bg then
        FadeRegions(thumb)
        local t = SolidTex(thumb, "ARTWORK", Theme.accR, Theme.accG, Theme.accB, 0.5)
        t:SetAllPoints(thumb)
        GetFFD(thumb).bg = t
    end
end

-- Close (X) button -> CharacterSheet pattern: strip art, draw our own 'x'.
local function SkinCloseButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if d.x then return end
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    FadeRegions(btn)
    local x = btn:CreateFontString(nil, "OVERLAY")
    x:SetFont(Theme.fontPath, 16, "")
    x:SetText("x")
    x:SetTextColor(1, 1, 1, 0.75)
    x:SetPoint("CENTER", -2, -3)
    d.x = x
    btn:HookScript("OnEnter", function() if d.x then d.x:SetTextColor(1, 1, 1, 1) end end)
    btn:HookScript("OnLeave", function() if d.x then d.x:SetTextColor(1, 1, 1, 0.75) end end)
end

-- PVEFrame bottom tab -> CharacterSheet tab pattern (bg + accent underline when
-- active). Visuals driven by UpdateTabVisuals (reads PVEFrame.selectedTab).
local function SkinTab(tab)
    if not tab or tab:IsForbidden() then return end
    local d = GetFFD(tab)
    if d.bg then return end
    for j = 1, select("#", tab:GetRegions()) do
        local r = select(j, tab:GetRegions())
        if r and r:IsObjectType("Texture") then
            r:SetTexture("")
            if r.SetAtlas then r:SetAtlas("") end
        end
    end
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        if tab[k] then tab[k]:SetTexture("") end
    end
    local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if hl then hl:SetTexture("") end

    d.bg = SolidTex(tab, "BACKGROUND", 0.068, 0.056, 0.052, 1)
    d.bg:SetAllPoints()

    local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
    activeHL:SetAllPoints()
    activeHL:SetColorTexture(1, 1, 1, 0.02)
    activeHL:SetBlendMode("ADD")
    activeHL:Hide()
    d.activeHL = activeHL

    local blizLabel = tab.GetFontString and tab:GetFontString()
    local labelText = (blizLabel and blizLabel:GetText()) or ""
    if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
    if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end

    local label = tab:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fontPath, 11, "")
    label:SetPoint("CENTER", tab, "CENTER", 0, 0)
    label:SetText(labelText)
    d.label = label
    hooksecurefunc(tab, "SetText", function(_, newText)
        if newText and d.label then d.label:SetText(newText) end
    end)

    local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
    if EUI and EUI.PanelPP and EUI.PanelPP.DisablePixelSnap then
        EUI.PanelPP.DisablePixelSnap(underline)
        underline:SetHeight(EUI.PanelPP.mult or 1)
    else
        underline:SetHeight(1)
    end
    underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    underline:SetColorTexture(Theme.accR, Theme.accG, Theme.accB, 1)
    if EUI and EUI.RegAccent then EUI.RegAccent({ type = "solid", obj = underline, a = 1 }) end
    underline:Hide()
    d.underline = underline
end

local function UpdateTabVisuals()
    if not PVEFrame then return end
    local sel = PVEFrame.selectedTab or 1
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        local d = tab and FFD[tab]
        if d then
            local isActive = (sel == i)
            if d.label then d.label:SetTextColor(1, 1, 1, isActive and 1 or 0.5) end
            if d.underline then d.underline:SetShown(isActive) end
            if d.activeHL then d.activeHL:SetShown(isActive) end
        end
    end
end

-- Left category rail buttons use the parentKey form GroupFinderFrame.groupButtonN
-- in modern clients; fall back to the older global name if absent.
local function CategoryButton(i)
    return (GroupFinderFrame and GroupFinderFrame["groupButton" .. i]) or _G["GroupFinderFrameGroupButton" .. i]
end

-- Left category rail button (GroupFinderGroupButtonTemplate): keep the icon,
-- flatten the rest, add a selected-state accent border.
local function SkinCategoryButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if d.skinned then return end
    d.skinned = true

    local keep = {}
    if btn.icon then keep[btn.icon] = true end
    if btn.bgGlow then btn.bgGlow:SetAlpha(0) end
    if btn.ring then btn.ring:SetAlpha(0) end
    FadeRegions(btn, keep)
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end

    d.bg = SolidTex(btn, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    d.bg:SetAllPoints(btn)
    AddBorder(btn)

    local hover = SolidTex(btn, "HIGHLIGHT", Theme.accR, Theme.accG, Theme.accB, 0.18)
    hover:SetAllPoints(btn)

    -- Accent bar on the left edge, shown when this category is selected.
    local sel = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    sel:SetColorTexture(Theme.accR, Theme.accG, Theme.accB, 1)
    sel:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    sel:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    sel:SetWidth(2)
    sel:Hide()
    if EUI and EUI.RegAccent then EUI.RegAccent({ type = "solid", obj = sel, a = 1 }) end
    d.selBar = sel

    if btn.name then SkinFontString(btn.name) end
    Register(btn, keep)
end

local function UpdateCategorySelection()
    local gff = _G.GroupFinderFrame
    local selected = gff and gff.selection
    for i = 1, 4 do
        local btn = CategoryButton(i)
        local d = btn and FFD[btn]
        if d and d.selBar then
            d.selBar:SetShown(selected == btn)
        end
    end
end

-------------------------------------------------------------------------------
--  Frame-specific skins
-------------------------------------------------------------------------------

local function Skin_PVEFrame()
    if not PVEFrame then return end
    SkinAtlasPanel(PVEFrame)

    -- Portrait (top-left eye icon) lives in a child container the frame-level
    -- strip does not reach.
    local pc = PVEFrame.PortraitContainer
    if pc then FadeRegions(pc); Register(pc, true) end
    if PVEFrame.portrait and PVEFrame.portrait.SetAlpha then PVEFrame.portrait:SetAlpha(0) end
    if PVEFramePortrait and PVEFramePortrait.SetAlpha then PVEFramePortrait:SetAlpha(0) end
    if PVEFrame.shadows then FadeRegions(PVEFrame.shadows); Register(PVEFrame.shadows, true) end

    local closeBtn = PVEFrame.CloseButton or _G.PVEFrameCloseButton
    if closeBtn then SkinCloseButton(closeBtn) end

    -- Left column inset: strip its art so the shell backdrop shows through.
    local leftInset = PVEFrame.Inset or _G["PVEFrameLeftInset"]
    if leftInset then SkinPanel(leftInset, { noBg = true, noBorder = true }) end

    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then SkinTab(tab) end
    end
    UpdateTabVisuals()
end

local function Skin_GroupFinder()
    for i = 1, 4 do
        local gb = CategoryButton(i)
        if gb then SkinCategoryButton(gb) end
    end
    UpdateCategorySelection()

    -- Dungeon Finder (LFD)
    if LFDParentFrame then SkinPanel(LFDParentFrame, { noBg = true, noBorder = true }) end
    if _G.LFDParentFrameInset then FadeInset(_G.LFDParentFrameInset) end
    if LFDQueueFrame then SkinPanel(LFDQueueFrame, { noBg = true, noBorder = true }) end
    if LFDQueueFrameRandomScrollFrame then SkinPanel(LFDQueueFrameRandomScrollFrame, { noBg = true, noBorder = true }) end
    if LFDQueueFrameFindGroupButton then SkinButton(LFDQueueFrameFindGroupButton) end
    if _G.LFDQueueFrameTypeDropdown then SkinDropdown(_G.LFDQueueFrameTypeDropdown) end
    local lfdSB = _G["LFDQueueFrameRandomScrollFrameScrollBar"]
        or (LFDQueueFrameRandomScrollFrame and LFDQueueFrameRandomScrollFrame.ScrollBar)
    if lfdSB then SkinScrollBar(lfdSB) end
    if _G.LFDQueueFrameSpecific and _G.LFDQueueFrameSpecific.ScrollBar then SkinScrollBar(_G.LFDQueueFrameSpecific.ScrollBar) end
end

local function Skin_LFGList()
    if not LFGListFrame then return end

    local CS = LFGListFrame.CategorySelection
    if CS then
        SkinPanel(CS, { noBg = true, noBorder = true })
        if CS.Inset then FadeInset(CS.Inset) end
        if CS.CategoryButtons then
            for _, b in ipairs(CS.CategoryButtons) do SkinButton(b) end
        end
        if CS.FindGroupButton then SkinButton(CS.FindGroupButton) end
        if CS.StartGroupButton then SkinButton(CS.StartGroupButton) end
    end

    local SP = LFGListFrame.SearchPanel
    if SP then
        SkinPanel(SP, { noBg = true, noBorder = true })
        if SP.ResultsInset then FadeInset(SP.ResultsInset) end
        if SP.SearchBox then SkinEditBox(SP.SearchBox) end
        if SP.FilterButton then SkinButton(SP.FilterButton) end
        if SP.RefreshButton then SkinButton(SP.RefreshButton, { "Icon" }) end
        if SP.BackButton then SkinButton(SP.BackButton) end
        if SP.BackToGroupButton then SkinButton(SP.BackToGroupButton) end
        if SP.SignUpButton then SkinButton(SP.SignUpButton) end
        if SP.ScrollBar then SkinScrollBar(SP.ScrollBar) end
        if SP.FilterButton and SP.FilterButton.ResetButton then SkinCloseButton(SP.FilterButton.ResetButton) end
    end

    local EC = LFGListFrame.EntryCreation
    if EC then
        SkinPanel(EC, { noBg = true, noBorder = true })
        if EC.Inset then FadeInset(EC.Inset) end
        if EC.CancelButton then SkinButton(EC.CancelButton) end
        if EC.ListGroupButton then SkinButton(EC.ListGroupButton) end
        if EC.Name then SkinEditBox(EC.Name) end
        if EC.Description then SkinEditBox(EC.Description) end
        for _, k in ipairs({ "GroupDropdown", "ActivityDropdown", "PlayStyleDropdown" }) do
            if EC[k] then SkinDropdown(EC[k]) end
        end
        for _, k in ipairs({ "ItemLevel", "MythicPlusRating", "PVPRating", "PvpItemLevel", "VoiceChat" }) do
            local req = EC[k]
            if req then
                if req.EditBox then SkinEditBox(req.EditBox) end
                if req.CheckButton then SkinCheckbox(req.CheckButton) end
            end
        end
        for _, k in ipairs({ "PrivateGroup", "CrossFactionGroup" }) do
            if EC[k] and EC[k].CheckButton then SkinCheckbox(EC[k].CheckButton) end
        end
    end

    local AV = LFGListFrame.ApplicationViewer
    if AV then
        SkinPanel(AV, { noBg = true, noBorder = true })
        if AV.Inset then FadeInset(AV.Inset) end
        if AV.RefreshButton then SkinButton(AV.RefreshButton, { "Icon" }) end
        if AV.RemoveEntryButton then SkinButton(AV.RemoveEntryButton) end
        if AV.EditButton then SkinButton(AV.EditButton) end
        if AV.BrowseGroupsButton then SkinButton(AV.BrowseGroupsButton) end
        if AV.AutoAcceptButton then SkinCheckbox(AV.AutoAcceptButton) end
        for _, k in ipairs({ "NameColumnHeader", "RoleColumnHeader", "ItemLevelColumnHeader", "RatingColumnHeader" }) do
            if AV[k] then SkinButton(AV[k]) end
        end
        if AV.ScrollBar then SkinScrollBar(AV.ScrollBar) end
        if AV.InfoBackground then AV.InfoBackground:SetAlpha(0) end
    end

    -- Per-row hook: restyle ONLY the row's CancelButton. We never read result
    -- data (secret in Midnight) and never blanket-strip the row (would blank
    -- role/class/data-display art).
    if LFGListSearchEntry_Update and not GetFFD(LFGListFrame).rowHook then
        GetFFD(LFGListFrame).rowHook = true
        hooksecurefunc("LFGListSearchEntry_Update", function(entry)
            if not entry or entry:IsForbidden() then return end
            if entry.CancelButton then SkinButton(entry.CancelButton) end
        end)
    end
end

local function Skin_RaidFinder()
    if RaidFinderFrame then SkinPanel(RaidFinderFrame, { noBg = true, noBorder = true }) end
    if _G.RaidFinderFrameRoleInset then FadeInset(_G.RaidFinderFrameRoleInset) end
    if RaidFinderQueueFrame then SkinPanel(RaidFinderQueueFrame, { noBg = true, noBorder = true }) end
    if RaidFinderFrameFindRaidButton then SkinButton(RaidFinderFrameFindRaidButton) end
    if _G.RaidFinderQueueFrameSelectionDropdown then SkinDropdown(_G.RaidFinderQueueFrameSelectionDropdown) end
    local rfSB = (_G.RaidFinderQueueFrameScrollFrame and _G.RaidFinderQueueFrameScrollFrame.ScrollBar)
        or _G.RaidFinderQueueFrameScrollFrameScrollBar
    if rfSB then SkinScrollBar(rfSB) end
end

local function Skin_Challenges()
    if not _G.ChallengesFrame then return end
    SkinPanel(_G.ChallengesFrame, { noBg = true, noBorder = true })
    if _G.ChallengesFrameInset then FadeInset(_G.ChallengesFrameInset) end
    local kf = _G.ChallengesKeystoneFrame
    if kf then
        SkinPanel(kf, { inset = true })
        if kf.StartButton then SkinButton(kf.StartButton) end
        if kf.CloseButton then SkinCloseButton(kf.CloseButton) end
    end
end

-- Full pass + re-strip; safe to call repeatedly (idempotent skinners).
local function RefreshAll()
    if not SkinEnabled() then return end
    Skin_PVEFrame()
    Skin_GroupFinder()
    Skin_LFGList()
    Skin_RaidFinder()
    Skin_Challenges()
    Restrip()
end

-------------------------------------------------------------------------------
--  Hook installation. Repaint hooks keep the skin stable across tab switches
--  and category navigation; installed once.
-------------------------------------------------------------------------------
local _hooksInstalled = false
local function InstallHooks()
    if _hooksInstalled or not PVEFrame then return end
    _hooksInstalled = true
    hooksecurefunc(PVEFrame, "Show", RefreshAll)
    if PVEFrame_ShowFrame then hooksecurefunc("PVEFrame_ShowFrame", function() RefreshAll(); UpdateTabVisuals() end) end
    if PVEFrame_TabOnClick then hooksecurefunc("PVEFrame_TabOnClick", function() RefreshAll(); UpdateTabVisuals() end) end
    if GroupFinderFrame_SelectGroupButton then
        hooksecurefunc("GroupFinderFrame_SelectGroupButton", function() Restrip(); UpdateCategorySelection() end)
    end
    if GroupFinderFrameGroupButton_OnClick then
        hooksecurefunc("GroupFinderFrameGroupButton_OnClick", function() Restrip(); UpdateCategorySelection() end)
    end
    if LFGListCategorySelectionButton_OnClick then
        hooksecurefunc("LFGListCategorySelectionButton_OnClick", Restrip)
    end
end

-------------------------------------------------------------------------------
--  QoL features. Independent of the skin toggle (a user may want either without
--  the dark style). Each self-gates on its own DB flag and costs nothing when
--  off. All reads here are of the addon's own data, the player's own character
--  data, or clean control APIs -- never per-result/member search data.
-------------------------------------------------------------------------------

-- (1) AUTO-REFRESH -----------------------------------------------------------
-- Re-runs the active Premade Groups search on a steady interval while the
-- search panel is open. LFGListSearchPanel_DoSearch re-issues the player's own
-- query (it carries no secret payload). The ticker is HIDDEN when idle, so it
-- costs nothing unless you are actively browsing with the feature on.
local AUTO_REFRESH_INTERVAL = 5  -- seconds; stays clear of Blizzard's search throttle
local autoTicker

local function AutoRefreshOn()
    return EllesmereUIDB and EllesmereUIDB.lfgAutoRefresh == true
end

local function EnsureAutoTicker()
    if autoTicker then return end
    autoTicker = CreateFrame("Frame")
    autoTicker:Hide()
    autoTicker:SetScript("OnUpdate", function(self, e)
        self._elapsed = (self._elapsed or 0) + e
        if self._elapsed < AUTO_REFRESH_INTERVAL then return end
        self._elapsed = 0
        local SP = LFGListFrame and LFGListFrame.SearchPanel
        if not (AutoRefreshOn() and SP and SP:IsShown()) then self:Hide(); return end
        -- Only refresh an active search (categoryID set). Skip while the search
        -- box has focus so we never yank text the user is mid-typing.
        if SP.categoryID and LFGListSearchPanel_DoSearch then
            local box = SP.SearchBox
            if box and box.HasFocus and box:HasFocus() then return end
            pcall(LFGListSearchPanel_DoSearch, SP)
        end
    end)
end

-- Start/stop the ticker to match the current state. Lazily creates the ticker
-- frame only when auto-refresh is actually enabled (zero allocation when off).
local function EUI_RefreshAutoTicker()
    if not AutoRefreshOn() then
        if autoTicker then autoTicker:Hide() end
        return
    end
    EnsureAutoTicker()
    local SP = LFGListFrame and LFGListFrame.SearchPanel
    if SP and SP:IsShown() then
        autoTicker._elapsed = 0
        autoTicker:Show()
    else
        autoTicker:Hide()
    end
end

-- Install the search-panel show/hide hooks once, only on first enable.
local _autoHooksInstalled = false
local function InstallAutoRefreshHooks()
    if _autoHooksInstalled then return end
    local SP = LFGListFrame and LFGListFrame.SearchPanel
    if not SP then return end  -- frames not loaded yet; InitQoL retries on addon load
    _autoHooksInstalled = true
    SP:HookScript("OnShow", EUI_RefreshAutoTicker)
    SP:HookScript("OnHide", function() if autoTicker then autoTicker:Hide() end end)
end

-- (2) REMEMBER SIGN-UP ROLES -------------------------------------------------
-- Persists the Tank/Healer/DPS checkboxes you last applied with and restores
-- them when the sign-up dialog opens (intersected with the roles your spec can
-- actually fill, so it never checks an impossible role). Pure clean widget
-- state; reads/writes no search-result data.
local _restoringRoles = false

local function RememberRolesOn()
    return EllesmereUIDB and EllesmereUIDB.lfgRememberRoles == true
end

local function SaveAppRoles(dialog)
    if not (RememberRolesOn() and dialog and EllesmereUIDB) then return end
    local function chk(btn) return (btn and btn.CheckButton and btn.CheckButton:GetChecked()) and true or false end
    EllesmereUIDB.lfgSavedRoles = {
        tank    = chk(dialog.TankButton),
        healer  = chk(dialog.HealerButton),
        damager = chk(dialog.DamagerButton),
    }
end

local function RestoreAppRoles(dialog)
    if _restoringRoles then return end
    if not (RememberRolesOn() and dialog and EllesmereUIDB and EllesmereUIDB.lfgSavedRoles) then return end
    if InCombatLockdown() then return end
    _restoringRoles = true
    pcall(function()
        local saved = EllesmereUIDB.lfgSavedRoles
        local function apply(btn, want)
            local cb = btn and btn.CheckButton
            if cb and cb:IsEnabled() then cb:SetChecked(want and true or false) end
        end
        apply(dialog.TankButton, saved.tank)
        apply(dialog.HealerButton, saved.healer)
        apply(dialog.DamagerButton, saved.damager)
        -- Re-run Blizzard's role update so the Sign Up button reflects our
        -- restored selection. The reentry guard stops our own hook recursing.
        if LFGListApplicationDialog_UpdateRoles then LFGListApplicationDialog_UpdateRoles(dialog) end
    end)
    _restoringRoles = false
end

-- Install the role save/restore hooks once, only on first enable.
local _roleHooksInstalled = false
local function InstallRememberRolesHooks()
    if _roleHooksInstalled then return end
    local dialog = _G.LFGListApplicationDialog
    if not (dialog and LFGListApplicationDialog_UpdateRoles) then return end
    _roleHooksInstalled = true
    -- The dialog opens as: UpdateRoles(self) -> StaticPopupSpecial_Show(self)
    -- (which fires OnShow plus any Quick Signup auto-accept). The open-sequence
    -- UpdateRoles is the only one that runs while the dialog is still HIDDEN, so
    -- restoring there (a) applies BEFORE the dialog shows / auto-signs-up, and
    -- (b) never fights a user role click (clicks fire UpdateRoles while shown).
    hooksecurefunc("LFGListApplicationDialog_UpdateRoles", function(dlg)
        if _restoringRoles or not dlg then return end
        if dlg:IsShown() then return end
        RestoreAppRoles(dlg)
    end)
    for _, key in ipairs({ "TankButton", "HealerButton", "DamagerButton" }) do
        local btn = dialog[key]
        local cb = btn and btn.CheckButton
        if cb then cb:HookScript("OnClick", function() SaveAppRoles(dialog) end) end
    end
end

-- INIT. Idempotent + existence-guarded; safe to call on PLAYER_LOGIN and again on
-- Blizzard_GroupFinder load (frames/globals only exist after that addon). Each
-- feature's hooks are installed ONLY when that feature is enabled, so a disabled
-- feature attaches no hooks and creates no frames.
EllesmereUI._GroupFinder_InitQoL = function()
    if AutoRefreshOn() then InstallAutoRefreshHooks(); EUI_RefreshAutoTicker() end
    if RememberRolesOn() then InstallRememberRolesHooks() end
end

-- Called by the options toggles when a QoL flag flips: installs that feature's
-- hooks lazily on first enable and re-evaluates the ticker. No reload needed.
EllesmereUI._GroupFinder_RefreshQoL = function()
    if AutoRefreshOn() then InstallAutoRefreshHooks() end
    if RememberRolesOn() then InstallRememberRolesHooks() end
    EUI_RefreshAutoTicker()
end

-------------------------------------------------------------------------------
--  Boot orchestration. PVEFrame lives in Blizzard_GroupFinder (load-on-demand);
--  ChallengesFrame in Blizzard_ChallengesUI. Skin on each addon's ADDON_LOADED,
--  install repaint hooks once, and sweep at login.
-------------------------------------------------------------------------------
local function DoSkinPass()
    if not Theme.bgR then ResolveTheme() end
    RefreshAll()
    InstallHooks()
end

local ON_ADDON = {
    Blizzard_GroupFinder  = function() DoSkinPass() end,
    Blizzard_ChallengesUI = function()
        if not SkinEnabled() then return end
        if not Theme.bgR then ResolveTheme() end
        Skin_Challenges(); Restrip()
    end,
}

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        ResolveTheme()
        if SkinEnabled() then DoSkinPass() end
        if EllesmereUI._GroupFinder_InitQoL then EllesmereUI._GroupFinder_InitQoL() end
    elseif event == "ADDON_LOADED" then
        local fn = ON_ADDON[name]
        if fn and SkinEnabled() then fn() end
        -- QoL init also needs Blizzard_GroupFinder to exist; (re)try on its load.
        if name == "Blizzard_GroupFinder" and EllesmereUI._GroupFinder_InitQoL then
            EllesmereUI._GroupFinder_InitQoL()
        end
    end
end)
