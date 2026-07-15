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
local ADDON_NAME, ns = ...
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
--  Enable gate. Independent toggle, default on (not tied to any master reskin).
-------------------------------------------------------------------------------
local function SkinEnabled()
    return not EllesmereUIDB or EllesmereUIDB.reskinLFGMenu ~= false
end

-------------------------------------------------------------------------------
--  Theme tokens. Resolved once at apply time; the accent is theme-driven and
--  re-registered via RegAccent so it tracks the user's accent color live.
-------------------------------------------------------------------------------
local Theme = {}
local function ResolveTheme()
    local EG = (EUI and EUI.ELLESMERE_GREEN) or { r = 0.047, g = 0.824, b = 0.616 }
    Theme.accR, Theme.accG, Theme.accB = EG.r or 0.047, EG.g or 0.824, EG.b or 0.616
    -- Neutral dark gray glass (no color cast).
    Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA = 0.08, 0.08, 0.08, 0.92
    -- Darker gray for nested insets so sub-panels melt into the main backdrop.
    Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA = 0.04, 0.04, 0.04, 0.85
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
            -- Protect every texture we created ourselves: the backdrop pieces,
            -- the hover highlight, and state bars. Without this the re-strip
            -- pass zeroes our own hover/selection art along with Blizzard's.
            if d then
                k = k or {}
                if d.bg then k[d.bg] = true end
                if d.bgOverlay then k[d.bgOverlay] = true end
                if d.topBar then k[d.topBar] = true end
                if d.hover then k[d.hover] = true end
                if d.selWash then k[d.selWash] = true end
                if d.leftWash then k[d.leftWash] = true end
                if d.leftSep then k[d.leftSep] = true end
            end
            -- The Modern flat backdrop (AdoptShell) lives in the ENGINE's FFD,
            -- not ours -- protect it too, or every restrip blanks the Modern
            -- style's only background on this window.
            local ed = ns.WSkin and ns.WSkin.FFD and ns.WSkin.FFD[frame]
            if ed and ed.modernBg then
                k = k or {}
                k[ed.modernBg] = true
            end
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
    if d.topBar then keep[d.topBar] = true end
    if d.leftWash then keep[d.leftWash] = true end
    if d.leftSep then keep[d.leftSep] = true end
    -- Spare the engine-owned Modern flat backdrop (see Restrip).
    local ed0 = ns.WSkin and ns.WSkin.FFD and ns.WSkin.FFD[frame]
    if ed0 and ed0.modernBg then keep[ed0.modernBg] = true end
    FadeRegions(frame, keep)
    Register(frame, true)
    if not d.bg then
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
        bg:SetAllPoints(frame)
        d.bg = bg
        local overlay = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        overlay:SetColorTexture(0, 0, 0, 0.62)
        overlay:SetAllPoints(frame)
        d.bgOverlay = overlay

        -- Black top bar behind the window title, matching the engine shell's
        -- strip. Sits above both style backdrops (-8/-7/-6) and below content.
        local topBar = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        topBar:SetColorTexture(0, 0, 0, 0.5)
        topBar:SetPoint("TOPLEFT")
        topBar:SetPoint("TOPRIGHT")
        topBar:SetHeight(25)
        d.topBar = topBar

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
    -- Window border: the shared atlas frame border every other reskinned
    -- window uses (1px line fallback if the engine is unavailable).
    if ns.WSkin and ns.WSkin.AtlasBorder then
        ns.WSkin.AtlasBorder(frame)
    else
        AddBorder(frame)
    end
    -- Register with the window-style system so the Modern flat backdrop can
    -- live-swap in for the atlas when the user picks Modern for this window.
    if ns.WSkin and ns.WSkin.AdoptShell then
        ns.WSkin.AdoptShell("lfg", frame, d.bg, d.bgOverlay)
    end
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

    local hover = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(btn)
    d.hover = hover

    -- Button labels keep Blizzard's font (no-font widget policy).
    Register(btn, keep)
end

-- Seat a button 5px higher (one-shot: captured original anchors + fixed lift,
-- so repeated skin passes never compound it). Handles multi-point anchoring by
-- lifting every point, not just the first.
local function LiftButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if d.lifted then return end
    local n = btn:GetNumPoints() or 0
    if n < 1 then return end
    local pts = {}
    for i = 1, n do
        local p, rel, rp, x, y = btn:GetPoint(i)
        if not p then return end
        pts[i] = { p, rel, rp, x or 0, (y or 0) + 5 }
    end
    d.lifted = true
    btn:ClearAllPoints()
    for i = 1, #pts do local t = pts[i]; btn:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
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

-- Checkbox -> the guild-roster "Show Offline Members" treatment: strip ALL
-- native art (regions + state textures) and drop a dedicated 14x14 bordered
-- box on the left, with a green tick when checked and a soft wash on
-- hover-or-checked. State is driven off the Blizzard checkbox via hooks so it
-- always mirrors the real value (no writing to the Blizzard frame's table).
local function SkinCheckbox(cb)
    if not cb or cb:IsForbidden() then return end
    local d = GetFFD(cb)
    if d.skinned then return end
    d.skinned = true
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
    d.bg = fill
    AddBorder(boxF, 0.25, 0.25, 0.25, 1)
    local tick = boxF:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(Theme.accR, Theme.accG, Theme.accB, 1)
    local wash = SolidTex(boxF, "ARTWORK", 1, 1, 1, 0.1)
    wash:SetAllPoints(boxF)
    wash:Hide()
    local hovering = false
    local function updState()
        local checked = cb:GetChecked()
        if issecretvalue(checked) then
            -- LFGList apply-phase data can make the checked state SECRET, and
            -- boolean-testing it throws. Bind the tick straight off the secret
            -- via the boolean-accepting alpha setter; the wash tracks hover
            -- only while the state is unreadable.
            if tick.SetAlphaFromBoolean then
                tick:Show()
                tick:SetAlphaFromBoolean(checked, 1, 0)
            end
            wash:SetShown(hovering)
            return
        end
        checked = checked and true or false
        tick:SetAlpha(1)
        tick:SetShown(checked)
        wash:SetShown(hovering or checked)
    end
    cb:HookScript("OnEnter", function() hovering = true; updState() end)
    cb:HookScript("OnLeave", function() hovering = false; updState() end)
    cb:HookScript("OnClick", updState)
    hooksecurefunc(cb, "SetChecked", updState)
    updState()
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
    local fill = SolidTex(dd, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fill:SetAllPoints(dd)
    d.bg = fill
    AddBorder(dd, 0.25, 0.25, 0.25, 1)
    -- Slight lighten on hover.
    local hover = SolidTex(dd, "HIGHLIGHT", 1, 1, 1, 0.05)
    hover:SetAllPoints(dd)
    d.hover = hover
    -- Our own arrow on the right (Blizzard's is faded with the rest).
    -- Sized to the atlas's native 62x44 aspect.
    local arrow = dd:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("Azerite-PointingArrow")
    arrow:SetSize(14, 10)
    arrow:SetPoint("RIGHT", dd, "RIGHT", -6, 0)
    d.arrow = arrow
end

-- MinimalScrollBar -> strip track/arrows; the thumb becomes a slim 5px white
-- strip centered in the thumb's hit area (the house scrollbar look).
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
        local t = SolidTex(thumb, "ARTWORK", 1, 1, 1, 0.3)
        t:SetPoint("TOP", thumb, "TOP", 0, 0)
        t:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
        t:SetWidth(4)
        GetFFD(thumb).bg = t
    end
end

-- Close (X) button -> strip art, draw the house close glyph.
local function SkinCloseButton(btn)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if d.x then return end
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    FadeRegions(btn)
    local x = btn:CreateTexture(nil, "OVERLAY")
    x:SetAtlas("uitools-icon-close")
    x:SetSize(14, 14)
    x:SetPoint("CENTER", -2, 0)
    x:SetVertexColor(1, 1, 1, 0.75)
    d.x = x
    btn:HookScript("OnEnter", function() if d.x then d.x:SetVertexColor(1, 1, 1, 1) end end)
    btn:HookScript("OnLeave", function() if d.x then d.x:SetVertexColor(1, 1, 1, 0.75) end end)
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
    -- Color + visibility follow the Blizzard Window Skins "Global Options"
    -- accent-bar setting; the window-skin engine recolors registered
    -- underlines on option edits and accent changes.
    local wsk = ns.WSkin
    if wsk and wsk.AccentBarColor then
        local ur, ug, ub = wsk.AccentBarColor()
        underline:SetColorTexture(ur, ug, ub, 1)
        if wsk.RegisterAccentUnderline then wsk.RegisterAccentUnderline(underline) end
    else
        underline:SetColorTexture(Theme.accR, Theme.accG, Theme.accB, 1)
        if EUI and EUI.RegAccent then EUI.RegAccent({ type = "solid", obj = underline, a = 1 }) end
    end
    underline:Hide()
    d.underline = underline
end

local _gfLooksHooked = false
-- The left rail zone (wash + divider) belongs only to tabs that HAVE a left
-- category rail: Dungeons & Raids (GroupFinderFrame) and PvP (PVPUIFrame). It
-- is anchored to PVEFrame, so without this it persists onto the Mythic+ tab
-- (which has no rail). Gate its visibility on a rail-owning frame being shown.
local function UpdateRailZone()
    local d = PVEFrame and FFD[PVEFrame]
    if not d then return end
    local show = (GroupFinderFrame and GroupFinderFrame:IsShown())
        or (_G.PVPUIFrame and _G.PVPUIFrame:IsShown()) or false
    if d.leftWash then d.leftWash:SetShown(show and true or false) end
    if d.leftSep then d.leftSep:SetShown(show and true or false) end
end

local function UpdateTabVisuals()
    if not PVEFrame then return end
    UpdateRailZone()
    local sel = PVEFrame.selectedTab or 1
    local barsOn = not (ns.WSkin and ns.WSkin.AccentBarShown) or ns.WSkin.AccentBarShown()
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        local d = tab and FFD[tab]
        if d then
            local isActive = (sel == i)
            if d.label then d.label:SetTextColor(1, 1, 1, isActive and 1 or 0.5) end
            if d.underline then d.underline:SetShown(isActive and barsOn) end
            if d.activeHL then d.activeHL:SetShown(isActive) end
        end
    end
    -- Registered lazily: the engine file loads after this one, so ns.WSkin
    -- is only reachable at runtime.
    if not _gfLooksHooked and ns.WSkin and ns.WSkin.OnLooksChanged then
        _gfLooksHooked = true
        ns.WSkin.OnLooksChanged(UpdateTabVisuals)
    end
end

-- Left category rail buttons use the parentKey form GroupFinderFrame.groupButtonN
-- in modern clients; fall back to the older global name if absent.
local function CategoryButton(i)
    return (GroupFinderFrame and GroupFinderFrame["groupButton" .. i]) or _G["GroupFinderFrameGroupButton" .. i]
end

-- Left category rail button (GroupFinderGroupButtonTemplate): keep the icon,
-- flatten the rest, add a selected-state accent border. opts.keepRing spares
-- the icon's ring border (PvP rail keeps it per user; D&R strips it).
-- Re-apply a rail button's converted anchors from its stored spec. Chained
-- buttons hang off the previous button; the chain root pins to the rail wash.
local function ApplyRailAnchors(btn)
    local d = FFD[btn]
    local a = d and d.railAnchors
    if not a then return end
    btn:ClearAllPoints()
    if a.rel then
        btn:SetPoint("TOPLEFT", a.rel, "BOTTOMLEFT", 0, a.y)
        btn:SetPoint("TOPRIGHT", a.rel, "BOTTOMRIGHT", 0, a.y)
    else
        btn:SetPoint("TOPLEFT", a.wash, "TOPLEFT", 0, a.y)
        btn:SetPoint("TOPRIGHT", a.wash, "TOPRIGHT", 0, a.y)
    end
end

local function SkinCategoryButton(btn, opts)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    d.isRail = true
    -- Full-width cards: pin both side edges to the rail-column wash so every
    -- card runs edge-to-edge (offset guesses always left a gap against the
    -- stock insets). One-shot per button, retries until laid out. The chain
    -- root keeps its exact vertical seat; chained buttons keep their vertical
    -- gap (closed 10px) and ride the 12px-taller previous button down.
    if not d.railWide then
        local h = btn:GetHeight()
        local pd = PVEFrame and FFD[PVEFrame]
        local wash = pd and pd.leftWash
        if h and h > 10 and wash and btn:GetTop() and wash:GetTop() then
            d.railWide = true
            btn:SetHeight(h + 12)
            local p, rel, rp, x, y = btn:GetPoint(1)
            if p and rel and FFD[rel] and FFD[rel].isRail then
                d.railAnchors = { rel = rel, y = (y or 0) + 10 }
            else
                d.railAnchors = { wash = wash, y = btn:GetTop() - wash:GetTop() }
            end
            ApplyRailAnchors(btn)
            -- Blizzard re-anchors these buttons from its own layout passes
            -- (the PvP rail re-seats on every show), stomping a one-shot
            -- conversion: re-assert ours synchronously, reentry-guarded.
            hooksecurefunc(btn, "SetPoint", function()
                if d.inPin then return end
                d.inPin = true
                ApplyRailAnchors(btn)
                d.inPin = false
            end)
        end
    end
    -- Icon (and its ring, so the border keeps hugging it) 10px smaller and
    -- shifted 3px right; the BUTTON keeps its stock size. Outside the skinned
    -- guard so it retries per pass until the icon has a laid-out size.
    local icon0 = btn.icon or btn.Icon
    if icon0 and not GetFFD(icon0).shrunk then
        local w, h = icon0:GetSize()
        if w and h and w > 10 and h > 10 then
            GetFFD(icon0).shrunk = true
            icon0:SetSize(w - 10, h - 10)
            local np = icon0:GetNumPoints() or 0
            local pts, ok = {}, np > 0
            for i = 1, np do
                local p, rel, rp, x, y = icon0:GetPoint(i)
                if not p then ok = false break end
                pts[i] = { p, rel, rp, (x or 0) + 3, y or 0 }
            end
            if ok then
                icon0:ClearAllPoints()
                for i = 1, #pts do local t = pts[i]; icon0:SetPoint(t[1], t[2], t[3], t[4], t[5]) end
            end
            local ring0 = btn.ring or btn.Ring
            if ring0 and ring0.GetSize then
                local rw, rh = ring0:GetSize()
                if rw and rh and rw > 10 and rh > 10 then
                    ring0:SetSize(rw - 10, rh - 10)
                end
            end
        end
    end
    if d.skinned then return end
    d.skinned = true

    local keep = {}
    -- D&R buttons use lowercase keys (icon/ring); the PvP queue buttons use
    -- capitalized ones (Icon/Ring). Same template family otherwise.
    local icon = btn.icon or btn.Icon
    if icon then keep[icon] = true end
    if btn.bgGlow then btn.bgGlow:SetAlpha(0) end
    local ring = btn.ring or btn.Ring
    if ring then
        if opts and opts.keepRing then
            keep[ring] = true
        else
            ring:SetAlpha(0)
        end
    end
    FadeRegions(btn, keep)
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end

    -- Card look matches the Guild & Communities sidebar entries: the same
    -- dialog-sheet card atlas at half strength, pulled in 2px top and bottom
    -- so stacked tabs never sit flush. No border -- the card art carries its
    -- own soft edge.
    -- The stock template clips child regions to the button rect, which
    -- swallows any card overhang -- unclip so the art can reach the edges.
    if btn.SetClipsChildren then btn:SetClipsChildren(false) end
    local card = btn:CreateTexture(nil, "BACKGROUND")
    card:SetAtlas("Ui-Dialog-New-Background")
    card:SetAlpha(0.5)
    -- Horizontal overhang compensates for the atlas's baked-in transparent
    -- margins (and the rail column's own inset from the window edge) so the
    -- VISIBLE art reads edge-to-edge (user-measured offsets).
    card:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, -2)
    card:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, 2)
    d.bg = card

    -- Hover + active wash: subtle white clamped 3px inside the card rect
    -- (the card atlas bakes in soft transparent edges, so a wash on the full
    -- rect reads bigger than the visible art).
    local hover = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.05)
    hover:SetPoint("TOPLEFT", card, "TOPLEFT", 3, -3)
    hover:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 3)
    d.hover = hover

    -- Held on while this category is selected.
    local selWash = SolidTex(btn, "ARTWORK", 1, 1, 1, 0.05)
    selWash:SetPoint("TOPLEFT", card, "TOPLEFT", 3, -3)
    selWash:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 3)
    selWash:Hide()
    d.selWash = selWash

    -- Re-derive the selection visuals after Blizzard's own click handler has
    -- processed the category change.
    if opts and opts.onSelect then
        btn:HookScript("OnClick", opts.onSelect)
    end

    -- Category button labels keep Blizzard's font (no-font widget policy).
    Register(btn, keep)
end

-- Latest selection captured from Blizzard's own select call (authoritative
-- when available; the frame state fields proved unreliable in Midnight).
local _gfSelIndex
local _pvpSel

-- Resolve the selected rail entry from the strongest available signal:
-- captured select-call arg > CheckButton checked state > Blizzard's own
-- selection glow (we alpha-0 it, but Blizzard still Show/Hides it; only
-- trusted when exactly one is shown, i.e. it behaves like a selection) >
-- legacy holder-frame selection fields. Returns an index or a button.
local function ResolveRailSelection(getBtn, captured, holder)
    if captured ~= nil then return captured end
    for i = 1, 4 do
        local b = getBtn(i)
        if b and b.GetChecked then
            local c = b:GetChecked()
            -- Secret checked state is unreadable; fall through to the next
            -- signal in the cascade instead of boolean-testing it.
            if not issecretvalue(c) and c then return i end
        end
    end
    local glowSel, glowCount = nil, 0
    for i = 1, 4 do
        local b = getBtn(i)
        local g = b and (b.bgGlow or b.bg or b.SelectedTexture)
        if g and g.IsShown and g:IsShown() then
            glowCount = glowCount + 1
            glowSel = i
        end
    end
    if glowCount == 1 then return glowSel end
    return holder and (holder.selection or holder.selectionIndex) or nil
end

local function UpdateCategorySelection()
    local sel = ResolveRailSelection(CategoryButton, _gfSelIndex, _G.GroupFinderFrame)
    for i = 1, 4 do
        local btn = CategoryButton(i)
        local d = btn and FFD[btn]
        if d and d.selWash then
            d.selWash:SetShown((sel == i or sel == btn) and true or false)
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

    -- Rail zone: 10% black wash over the LEFT sidebar column + a
    -- 1-physical-px divider on its right edge, between the rail tabs and the
    -- content. Rides the left inset's rect (the definitive rail column).
    local d = GetFFD(PVEFrame)
    if not d.leftWash then
        local px = 1
        local PPx = EUI and EUI.PP
        local es = PVEFrame:GetEffectiveScale()
        if PPx and PPx.perfect and es and es > 0 then px = PPx.perfect / es end
        local wash = PVEFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        wash:SetColorTexture(0, 0, 0, 0.1)
        if leftInset then
            wash:SetAllPoints(leftInset)
        else
            wash:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", 7, -62)
            wash:SetPoint("BOTTOMRIGHT", PVEFrame, "BOTTOMLEFT", 206, 7)
        end
        d.leftWash = wash
        local sep = PVEFrame:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(0.15, 0.15, 0.15, 1)
        sep:SetWidth(px)
        sep:SetPoint("TOPLEFT", wash, "TOPRIGHT", 0, 0)
        sep:SetPoint("BOTTOMLEFT", wash, "BOTTOMRIGHT", 0, 0)
        d.leftSep = sep
    end

    local pveTabs = {}
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then SkinTab(tab); pveTabs[#pveTabs + 1] = tab end
    end
    if ns.WSkin and ns.WSkin.NormalizeTabRow then ns.WSkin.NormalizeTabRow(pveTabs) end
    UpdateTabVisuals()
end

local function Skin_GroupFinder()
    for i = 1, 4 do
        local gb = CategoryButton(i)
        if gb then SkinCategoryButton(gb, { keepRing = true, onSelect = UpdateCategorySelection }) end
    end
    UpdateCategorySelection()

    -- Dungeon Finder (LFD)
    if LFDParentFrame then SkinPanel(LFDParentFrame, { noBg = true, noBorder = true }) end
    if _G.LFDParentFrameInset then FadeInset(_G.LFDParentFrameInset) end
    if LFDQueueFrame then SkinPanel(LFDQueueFrame, { noBg = true, noBorder = true }) end
    if LFDQueueFrameRandomScrollFrame then SkinPanel(LFDQueueFrameRandomScrollFrame, { noBg = true, noBorder = true }) end
    if LFDQueueFrameFindGroupButton then
        SkinButton(LFDQueueFrameFindGroupButton)
        LiftButton(LFDQueueFrameFindGroupButton)
    end
    if _G.LFDQueueFrameTypeDropdown then SkinDropdown(_G.LFDQueueFrameTypeDropdown) end
    local lfdSB = _G["LFDQueueFrameRandomScrollFrameScrollBar"]
        or (LFDQueueFrameRandomScrollFrame and LFDQueueFrameRandomScrollFrame.ScrollBar)
    if lfdSB then SkinScrollBar(lfdSB) end
    if _G.LFDQueueFrameSpecific and _G.LFDQueueFrameSpecific.ScrollBar then SkinScrollBar(_G.LFDQueueFrameSpecific.ScrollBar) end
end

-- Premade Groups category buttons (Dungeons / Raids / Arenas / ...): the base
-- button skin plus a white selection wash held on while that category is the
-- active pick, matching the left sidebar rail's active state.
local function SkinLFGCategoryButton(btn)
    if not btn or btn:IsForbidden() then return end
    SkinButton(btn)
    local d = GetFFD(btn)
    if not d.selWash then
        -- ARTWORK below the button label (sublevel -1) and above the fill.
        local selWash = SolidTex(btn, "ARTWORK", 1, 1, 1, 0.05, -1)
        selWash:SetAllPoints(btn)
        selWash:Hide()
        d.selWash = selWash
    end
    -- Match the sidebar rail: hover + active both 0.05 white.
    if d.hover then d.hover:SetColorTexture(1, 1, 1, 0.05) end
end

-- Is this category button the active pick? Blizzard's authoritative state is
-- CategorySelection.selectedCategory (+ selectedFilters), matched against each
-- button's own categoryID/filters. This is why SelectedTexture:IsShown() failed
-- for the first button: Blizzard HIDES that texture in the AddButton rebuild
-- and re-derives selection from the ID, and the first category is auto-selected
-- by default (never passing through the click hook).
local function IsLFGCategorySelected(cs, btn)
    return cs.selectedCategory ~= nil
        and btn.categoryID == cs.selectedCategory
        and btn.filters == cs.selectedFilters
end

local function UpdateLFGCategorySelection()
    local CS = LFGListFrame and LFGListFrame.CategorySelection
    if not (CS and CS.CategoryButtons) then return end
    for _, btn in ipairs(CS.CategoryButtons) do
        local d = FFD[btn]
        if d and d.selWash then
            d.selWash:SetShown(IsLFGCategorySelected(CS, btn) and true or false)
        end
    end
end

-- Refresh button -> strip art, draw the house white UI-RefreshButton glyph
-- (desaturated + white vertex, 0.9 -> 1 on hover). Matches the Auction House
-- refresh button.
local function SkinRefreshGlyph(rb)
    if not rb or rb:IsForbidden() then return end
    local d = GetFFD(rb)
    if d.glyph then return end
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-RefreshButton")) then return end
    for i = 1, select("#", rb:GetRegions()) do
        local r = select(i, rb:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
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

local function Skin_LFGList()
    if not LFGListFrame then return end

    local CS = LFGListFrame.CategorySelection
    if CS then
        SkinPanel(CS, { noBg = true, noBorder = true })
        if CS.Inset then FadeInset(CS.Inset) end
        if CS.CategoryButtons then
            for _, b in ipairs(CS.CategoryButtons) do SkinLFGCategoryButton(b) end
            UpdateLFGCategorySelection()
        end
        -- Blizzard rebuilds every category button through AddButton on the
        -- initial show AND on every selection change (SelectButton ->
        -- UpdateCategoryButtons -> AddButton per button), so this is the one
        -- hook that catches the default selection and every click alike.
        if LFGListCategorySelection_AddButton and not GetFFD(CS).addBtnHook then
            GetFFD(CS).addBtnHook = true
            hooksecurefunc("LFGListCategorySelection_AddButton", function(cs, btnIndex, categoryID, filters)
                local b = cs and cs.CategoryButtons and cs.CategoryButtons[btnIndex]
                if not b or b:IsForbidden() then return end
                SkinLFGCategoryButton(b)
                local d = FFD[b]
                if d and d.selWash then
                    local sel = (cs.selectedCategory == categoryID) and (cs.selectedFilters == filters)
                    d.selWash:SetShown(sel and true or false)
                end
            end)
        end
        if CS.FindGroupButton then SkinButton(CS.FindGroupButton); LiftButton(CS.FindGroupButton) end
        if CS.StartGroupButton then SkinButton(CS.StartGroupButton); LiftButton(CS.StartGroupButton) end
    end

    local SP = LFGListFrame.SearchPanel
    if SP then
        SkinPanel(SP, { noBg = true, noBorder = true })
        if SP.ResultsInset then FadeInset(SP.ResultsInset) end
        if SP.SearchBox then SkinEditBox(SP.SearchBox) end
        if SP.FilterButton then SkinButton(SP.FilterButton) end
        if SP.RefreshButton then SkinRefreshGlyph(SP.RefreshButton) end
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
        if AV.RefreshButton then SkinRefreshGlyph(AV.RefreshButton) end
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

    -- Search result rows are left FULLY stock. We used to skin the per-row
    -- CancelButton (shown while you're applied/queued to that group), but that
    -- made the queued-state button read wrong, so it stays Blizzard's. We never
    -- read row data (secret in Midnight) or blanket-strip the row either.
end

-- Raid Finder leftover art. Blizzard re-raises the role inset's backdrop from
-- a path that fires when the panel shows (none of our restrip hooks cover that
-- transition), so this runs from both the skin pass AND an OnShow refade.
local _rbGuard = false
local function FadeRaidFinderArt()
    local ri = _G.RaidFinderFrameRoleInset
    if ri then
        FadeInset(ri)
        -- Explicit by key too: survives the case where Bg is not a direct
        -- region the sweep reaches.
        if ri.Bg and ri.Bg.SetAlpha then ri.Bg:SetAlpha(0) end
    end
    if _G.RaidFinderFrameBottomInset then FadeInset(_G.RaidFinderFrameBottomInset) end
    -- Role background (orange gradient behind the role buttons): Blizzard's
    -- rewards updaters (RaidFinderQueueFrameRewards_UpdateFrame and the shared
    -- LFGRewardsFrame_UpdateFrame) re-raise this art on every rewards/role/raid
    -- update, which is why one-shot fades never stuck. This helper is hooked to
    -- those updaters below, AND the art image itself is cleared so nothing
    -- shows even if a raise path slips through.
    local rb = _G.RaidFinderFrameRoleBackground
    if rb and rb.SetAlpha then
        _rbGuard = true
        rb:SetAlpha(0)
        _rbGuard = false
        if rb.SetTexture then rb:SetTexture("") end
        if rb.SetAtlas then rb:SetAtlas("") end
        local rd = GetFFD(rb)
        if not rd.alphaGuarded then
            rd.alphaGuarded = true
            hooksecurefunc(rb, "SetAlpha", function(t)
                if _rbGuard then return end
                _rbGuard = true
                t:SetAlpha(0)
                _rbGuard = false
            end)
        end
    end
    -- Questpaper scenic art behind the rewards list: re-textured by the same
    -- updaters.
    local qb = _G.RaidFinderQueueFrameBackground
    if qb and qb.SetAlpha then qb:SetAlpha(0) end
end

local _rfShowHooked = false
local function Skin_RaidFinder()
    if RaidFinderFrame then SkinPanel(RaidFinderFrame, { noBg = true, noBorder = true }) end
    FadeRaidFinderArt()
    if RaidFinderFrame and not _rfShowHooked then
        _rfShowHooked = true
        RaidFinderFrame:HookScript("OnShow", FadeRaidFinderArt)
    end
    if RaidFinderQueueFrame then SkinPanel(RaidFinderQueueFrame, { noBg = true, noBorder = true }) end
    if RaidFinderFrameFindRaidButton then
        SkinButton(RaidFinderFrameFindRaidButton)
        LiftButton(RaidFinderFrameFindRaidButton)
    end
    if _G.RaidFinderQueueFrameSelectionDropdown then SkinDropdown(_G.RaidFinderQueueFrameSelectionDropdown) end
    local rfSB = (_G.RaidFinderQueueFrameScrollFrame and _G.RaidFinderQueueFrameScrollFrame.ScrollBar)
        or _G.RaidFinderQueueFrameScrollFrameScrollBar
    if rfSB then SkinScrollBar(rfSB) end
end

local function Skin_Challenges()
    if not _G.ChallengesFrame then return end
    local cf = _G.ChallengesFrame
    SkinPanel(cf, { noBg = true, noBorder = true })
    -- The M+ main-area scenic backdrop (ChallengesFrame.Background + an anon
    -- BG texture) defeated every ALPHA approach we tried -- Blizzard re-raises
    -- their alpha from paths we never caught. Disabling the whole BACKGROUND
    -- draw LAYER kills them regardless of alpha (Blizzard would have to
    -- re-ENABLE the layer to bring them back, which it doesn't). Re-asserted
    -- each pass as a belt-and-braces against a future re-enable.
    if cf.DisableDrawLayer then cf:DisableDrawLayer("BACKGROUND") end
    if _G.ChallengesFrameInset then FadeInset(_G.ChallengesFrameInset) end
    local kf = _G.ChallengesKeystoneFrame
    if kf then
        SkinPanel(kf, { inset = true })
        if kf.StartButton then SkinButton(kf.StartButton) end
        if kf.CloseButton then SkinCloseButton(kf.CloseButton) end
    end
end

-- PvP tab (PVPUIFrame, Blizzard_PVPUI -- separate LoD addon): the D&R
-- treatment mirrored. Category rail buttons share SkinCategoryButton; panels
-- stripped so the shell backdrop shows through.
local function PVPCategoryButton(i)
    return _G.PVPQueueFrame and _G.PVPQueueFrame["CategoryButton" .. i]
end

local function UpdatePVPCategorySelection()
    local sel = ResolveRailSelection(PVPCategoryButton, _pvpSel, _G.PVPQueueFrame)
    for i = 1, 4 do
        local btn = PVPCategoryButton(i)
        local d = btn and FFD[btn]
        if d and d.selWash then
            d.selWash:SetShown((sel == i or sel == btn) and true or false)
        end
    end
end

local function Skin_PVP()
    local pvp = _G.PVPUIFrame
    if not pvp then return end
    -- The PvP rail lays out late: at Blizzard_PVPUI load (and even inside the
    -- tab-switch hooks) the category buttons can still report no geometry, so
    -- the one-shot full-width conversion has nothing to measure and skips --
    -- leaving stock anchors that hang the card overhang off the rail edge.
    -- Re-run one frame after the window shows, when layout is real.
    if not GetFFD(pvp).showHook then
        GetFFD(pvp).showHook = true
        pvp:HookScript("OnShow", function()
            C_Timer.After(0, function()
                if pvp:IsShown() and SkinEnabled() then Skin_PVP() end
            end)
        end)
    end
    SkinPanel(pvp, { noBg = true, noBorder = true })
    local pq = _G.PVPQueueFrame
    if pq then
        SkinPanel(pq, { noBg = true, noBorder = true })
        for i = 1, 4 do
            local b = PVPCategoryButton(i)
            if b then SkinCategoryButton(b, { keepRing = true, onSelect = UpdatePVPCategorySelection }) end
        end
        UpdatePVPCategorySelection()
    end
    -- Casual (Honor) panel.
    local hf = _G.HonorFrame
    if hf then
        SkinPanel(hf, { noBg = true, noBorder = true })
        local inset = hf.Inset or _G.HonorFrameInset
        if inset then FadeInset(inset) end
        if hf.QueueButton then SkinButton(hf.QueueButton); LiftButton(hf.QueueButton) end
        if hf.TypeDropdown then SkinDropdown(hf.TypeDropdown) end
        local sfr = hf.SpecificScrollBox or hf.SpecificFrame
        local sb = (sfr and sfr.ScrollBar) or hf.ScrollBar
        if sb then SkinScrollBar(sb) end
        if hf.BonusFrame then SkinPanel(hf.BonusFrame, { noBg = true, noBorder = true }) end
    end
    -- Rated (Conquest) panel.
    local cf = _G.ConquestFrame
    if cf then
        SkinPanel(cf, { noBg = true, noBorder = true })
        local inset = cf.Inset or _G.ConquestFrameInset
        if inset then FadeInset(inset) end
        if cf.JoinButton then SkinButton(cf.JoinButton); LiftButton(cf.JoinButton) end
    end
    -- Training Grounds panel (PvP practice queue; mirrors the Honor panel).
    local tg = _G.TrainingGroundsFrame
    if tg then
        SkinPanel(tg, { noBg = true, noBorder = true })
        local inset = tg.Inset or _G.TrainingGroundsFrameInset
        if inset then FadeInset(inset) end
        if tg.QueueButton then SkinButton(tg.QueueButton); LiftButton(tg.QueueButton) end
        if tg.TypeDropdown then SkinDropdown(tg.TypeDropdown) end
        local spec = tg.SpecificTrainingGroundList
        if spec then
            SkinPanel(spec, { noBg = true, noBorder = true })
            local sb = spec.ScrollBar or (spec.ScrollBox and spec.ScrollBox.ScrollBar)
            if sb then SkinScrollBar(sb) end
        end
        local bonus = tg.BonusTrainingGroundList
        if bonus then
            SkinPanel(bonus, { noBg = true, noBorder = true })
            -- Leftover scenic art the panel sweep does not reach by region.
            if bonus.ShadowOverlay and bonus.ShadowOverlay.SetAlpha then bonus.ShadowOverlay:SetAlpha(0) end
            if bonus.WorldBattlesTexture and bonus.WorldBattlesTexture.SetAlpha then bonus.WorldBattlesTexture:SetAlpha(0) end
            if bonus.RandomTrainingGroundButton then SkinButton(bonus.RandomTrainingGroundButton) end
        end
    end
end

-- Selection/repaint hooks for the PvP tab; installable only once its addon
-- has loaded (the globals don't exist before Blizzard_PVPUI).
local _pvpHooksInstalled = false
local function InstallPVPHooks()
    if _pvpHooksInstalled then return end
    _pvpHooksInstalled = true
    if _G.PVPQueueFrame_SelectButton then
        hooksecurefunc("PVPQueueFrame_SelectButton", function(sel)
            -- Arg is an index on some builds, the button itself on others.
            if type(sel) == "number" or type(sel) == "table" then _pvpSel = sel end
            Restrip(); UpdatePVPCategorySelection()
        end)
    end
    if _G.PVPQueueFrame_ShowFrame then
        hooksecurefunc("PVPQueueFrame_ShowFrame", Restrip)
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
    Skin_PVP()
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
        hooksecurefunc("GroupFinderFrame_SelectGroupButton", function(index)
            if type(index) == "number" then _gfSelIndex = index end
            Restrip(); UpdateCategorySelection()
        end)
    end
    if GroupFinderFrameGroupButton_OnClick then
        hooksecurefunc("GroupFinderFrameGroupButton_OnClick", function() Restrip(); UpdateCategorySelection() end)
    end
    if LFGListCategorySelectionButton_OnClick then
        -- Selection wash is driven by the AddButton rebuild hook (fires on
        -- every pick); here we only re-flatten art after the click.
        hooksecurefunc("LFGListCategorySelectionButton_OnClick", Restrip)
    end
    -- Blizzard's rewards updaters re-apply the questpaper background (LFD /
    -- Raid Finder / Scenario) and the Raid Finder role-row gradient on every
    -- rewards/role/raid update; one-shot fades never stick against them, so
    -- re-fade from the updaters themselves.
    if LFGRewardsFrame_UpdateFrame then
        hooksecurefunc("LFGRewardsFrame_UpdateFrame", function(_, _, background)
            if background and not issecretvalue(background) and background.SetAlpha then
                background:SetAlpha(0)
            end
        end)
    end
    if RaidFinderQueueFrameRewards_UpdateFrame then
        hooksecurefunc("RaidFinderQueueFrameRewards_UpdateFrame", FadeRaidFinderArt)
    end
end

-------------------------------------------------------------------------------
--  QoL features. Independent of the skin toggle (a user may want either without
--  the dark style). Each self-gates on its own DB flag and costs nothing when
--  off. All reads here are of the addon's own data, the player's own character
--  data, or clean control APIs -- never per-result/member search data.
-------------------------------------------------------------------------------

-- REMEMBER SIGN-UP ROLES ------------------------------------------------------
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
    local function chk(btn)
        local c = btn and btn.CheckButton and btn.CheckButton:GetChecked()
        if issecretvalue(c) then return nil end
        return c and true or false
    end
    local tank, healer, damager = chk(dialog.TankButton), chk(dialog.HealerButton), chk(dialog.DamagerButton)
    -- Any secret checked state means we cannot read what the user picked;
    -- keep the previous save rather than writing wrong roles.
    if tank == nil or healer == nil or damager == nil then return end
    EllesmereUIDB.lfgSavedRoles = {
        tank    = tank,
        healer  = healer,
        damager = damager,
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

-- CHARACTER / PVEFRAME OVERLAP ------------------------------------------------
-- Stock Blizzard has no docking relationship between CharacterFrame and
-- PVEFrame (Dungeons & Raids); both anchor near the same default screen
-- position, so opening one while the other is open overlaps them. Any addon
-- that docks its own panel to PVEFrame's edge (e.g. RaiderIO's Mythic+ panel)
-- is unaware of CharacterFrame, so it gets partially covered by CharacterFrame
-- in turn. PVEFrame is PROTECTED (it parents the LFGList applicant viewer,
-- which throws on tainted secret-value comparisons -- see
-- EllesmereUIQoL_Shifter.lua's SecureSetPoint), so it is never repositioned
-- here; CharacterFrame is not protected, so it docks beside PVEFrame instead.
-- Reading PVEFrame's position does not taint it -- only writing to it would.
-- Independent of reskinLFGMenu: a positioning fix, not part of the skin.
local PVE_DOCK_MARGIN = 4

local function CharacterFrameIsUserPinned()
    return EllesmereUIDB and EllesmereUIDB.shifterPositions
        and EllesmereUIDB.shifterPositions["CharacterFrame"] ~= nil
end

-- Third-party panels known to dock themselves beside PVEFrame with no
-- awareness of CharacterFrame (RaiderIO's Mythic+/profile panel, confirmed
-- via /fstack). Checked by name -- cheap and reliable -- instead of scanning
-- every frame in the UI: that approach kept missing the actual frame, once
-- matched CharacterFrame's own child and produced a circular anchor, and was
-- slow enough on its own to cause a visible hitch. Add another name here if
-- a different addon is reported doing the same thing.
local KNOWN_PVE_COMPANIONS = { "RaiderIO_ProfileTooltip" }

local function FindOutermostFrame(pve, side)
    local outFrame = pve
    local pveScale = pve:GetEffectiveScale() or 1
    local outEdgeAbs = ((side == "right" and pve:GetRight() or pve:GetLeft()) or 0) * pveScale
    local pveTop, pveBottom = pve:GetTop(), pve:GetBottom()
    if not pveTop or not pveBottom then return outFrame, outEdgeAbs end
    local topAbs, bottomAbs = pveTop * pveScale, pveBottom * pveScale

    for _, name in ipairs(KNOWN_PVE_COMPANIONS) do
        local checkFrame = _G[name]
        if checkFrame and checkFrame:IsVisible() then
            local fLeft, fRight = checkFrame:GetLeft(), checkFrame:GetRight()
            local fTop, fBottom = checkFrame:GetTop(), checkFrame:GetBottom()
            if fLeft and fRight and fTop and fBottom then
                local fScale = checkFrame:GetEffectiveScale() or 1
                local fLeftAbs, fRightAbs = fLeft * fScale, fRight * fScale
                local fTopAbs, fBottomAbs = fTop * fScale, fBottom * fScale
                if fTopAbs > bottomAbs and fBottomAbs < topAbs then
                    if side == "right" and fRightAbs > outEdgeAbs then
                        outFrame, outEdgeAbs = checkFrame, fRightAbs
                    elseif side == "left" and fLeftAbs < outEdgeAbs then
                        outFrame, outEdgeAbs = checkFrame, fLeftAbs
                    end
                end
            end
        end
    end
    return outFrame, outEdgeAbs
end

-- Guards our own SetPoint call below from re-triggering itself through the
-- hooksecurefunc on CharacterFrame's own SetPoint (needed so a Shifter
-- scale change, which always ends by re-applying position, re-docks too).
local _dockingCharacterFrame = false

local function DockCharacterFrame()
    if _dockingCharacterFrame then return end
    local cf = _G.CharacterFrame
    local pve = PVEFrame
    if not cf or not pve then return end
    if not cf:IsShown() or not pve:IsShown() then return end
    -- No pin check here: PVEFrame is protected, so it can never get even the
    -- strata-only fallback Shifter gives its other managed windows (that
    -- write would taint it -- see EllesmereUIQoL_Shifter.lua). Repositioning
    -- CharacterFrame is the only way PVEFrame is ever kept from being buried
    -- under it, so this must run even when the user has Shifter-scaled or
    -- -pinned CharacterFrame -- their chosen SCALE is untouched, only the
    -- anchor point moves.

    local cs  = cf:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local wAbs = (cf:GetWidth() or 0) * cs
    local leftFrame,  leftEdgeAbs  = FindOutermostFrame(pve, "left")
    local rightFrame, rightEdgeAbs = FindOutermostFrame(pve, "right")
    local leftRoom  = leftEdgeAbs
    local rightRoom = (GetScreenWidth() or 0) * ues - rightEdgeAbs
    local dockLeft = leftRoom >= wAbs + PVE_DOCK_MARGIN * cs or leftRoom >= rightRoom

    local targetPoint, targetRel, targetRelPoint, targetX, targetY, expectedEdgeAbs
    if dockLeft then
        targetPoint, targetRel, targetRelPoint, targetX, targetY = "TOPRIGHT", leftFrame, "TOPLEFT", -PVE_DOCK_MARGIN, 0
        expectedEdgeAbs = leftEdgeAbs - PVE_DOCK_MARGIN * cs
    else
        targetPoint, targetRel, targetRelPoint, targetX, targetY = "TOPLEFT", rightFrame, "TOPRIGHT", PVE_DOCK_MARGIN, 0
        expectedEdgeAbs = rightEdgeAbs + PVE_DOCK_MARGIN * cs
    end

    -- PVEFrame's own internal layout re-anchors it (and RaiderIO's tooltip)
    -- repeatedly while it settles, and Shifter re-applies CharacterFrame's
    -- own saved/temp position on every scale step -- both re-trigger this
    -- constantly. Skip the write only when CharacterFrame's ACTUAL current
    -- edge already matches where we'd put it -- not by reading GetPoint()
    -- back (SetClampedToScreen can silently rewrite the stored anchor once
    -- it adjusts a frame to fit on screen) and not by caching our own last
    -- decision (Shifter's scale step can reposition CharacterFrame away from
    -- our dock via ITS OWN saved-position math without leftFrame/rightFrame/
    -- dockLeft ever changing, which a decision-only cache can't detect).
    local curEdgeAbs = (dockLeft and (cf:GetRight() or 0) or (cf:GetLeft() or 0)) * cs
    if math.abs(curEdgeAbs - expectedEdgeAbs) < 1 then
        return
    end

    _dockingCharacterFrame = true
    -- Shifter installs its own hooksecurefunc(CharacterFrame, "SetPoint", ...)
    -- (on every frame it manages, independent of the docking-companions
    -- system) that re-applies a saved/temp Shifter position on every
    -- SetPoint call. Once a scale action has saved ANY position for
    -- CharacterFrame, that hook fires synchronously right after ours and
    -- snaps it straight back -- undoing this dock entirely. _shIgnoreSP is
    -- the exact flag Shifter sets around its OWN writes for the same reason;
    -- set it here too so our write isn't immediately reverted. This hook can
    -- itself fire NESTED inside a SetPoint call Shifter's own ApplyPosition
    -- made (with the flag already true) -- restore the PRIOR value rather
    -- than hardcoding false, or we'd clear it while still nested inside that
    -- call, letting Shifter's own SetPoint hook see it false and recurse.
    local shifterFFD = EllesmereUI._GetFFD and EllesmereUI._GetFFD(cf)
    local prevIgnoreSP = shifterFFD and shifterFFD._shIgnoreSP
    if shifterFFD then shifterFFD._shIgnoreSP = true end
    cf:ClearAllPoints()
    cf:SetPoint(targetPoint, targetRel, targetRelPoint, targetX, targetY)
    if shifterFFD then shifterFFD._shIgnoreSP = prevIgnoreSP end
    _dockingCharacterFrame = false
end

-- Blizzard's native anchor, captured before we ever dock, so it can be
-- restored once PVEFrame is no longer there to dock beside.
local _defaultCharacterPoint

local function CaptureDefaultCharacterPoint()
    if _defaultCharacterPoint or not _G.CharacterFrame then return end
    local point, relativeTo, relativePoint, x, y = _G.CharacterFrame:GetPoint(1)
    if point then
        _defaultCharacterPoint = { point, relativeTo, relativePoint, x, y }
    end
end

local function RestoreDefaultCharacterPoint()
    if not _defaultCharacterPoint or not _G.CharacterFrame then return end
    if CharacterFrameIsUserPinned() then return end
    _G.CharacterFrame:ClearAllPoints()
    _G.CharacterFrame:SetPoint(unpack(_defaultCharacterPoint))
end

local _pveDockHooksInstalled = false
local function InstallPVEDockHooks()
    if _pveDockHooksInstalled or not PVEFrame or not _G.CharacterFrame then return end
    _pveDockHooksInstalled = true

    CaptureDefaultCharacterPoint()

    -- Direct everywhere: DockCharacterFrame already no-ops safely if either
    -- frame isn't shown yet, so there's no unsettled-state risk to defer
    -- for, and FindOutermostFrame is cheap now (named lookups, not a frame
    -- scan). Deferring a SetPoint-triggered re-dock to next frame (e.g. if
    -- Blizzard's layout system repositions CharacterFrame again after it's
    -- already rendering) is exactly what shows one frame at the wrong
    -- position before snapping into place.
    -- Blizzard's OWN UIParentPanelManager treats CharacterFrame and PVEFrame
    -- as part of the same "managed panel" group, and repositions CharacterFrame
    -- itself (via its own SetPoint calls) whenever PVEFrame opens -- the exact
    -- native behavior this whole feature works around. Left alone, every one
    -- of those calls also re-triggers Shifter's saved-position restore (if
    -- CharacterFrame has one) AND our own dock, and each of THOSE writes reads
    -- to Blizzard's manager as "a managed panel moved," so it reasserts itself
    -- again -- three systems endlessly re-triggering each other. Opting out
    -- permanently (rather than only while PVEFrame is open) closes this for
    -- good: CharacterFrame's position is already fully covered by our own
    -- dock logic, Shifter's saved/temp positions, and the native-default
    -- capture/restore below, so there's no case left where Blizzard's
    -- automatic management is actually needed. ignoreFramePositionManager is
    -- the sanctioned opt-out -- already used the same way for the loot
    -- windows in EllesmereUIQoL_Shifter.lua.
    _G.CharacterFrame.ignoreFramePositionManager = true

    _G.CharacterFrame:HookScript("OnShow", DockCharacterFrame)
    hooksecurefunc(_G.CharacterFrame, "SetPoint", DockCharacterFrame)

    PVEFrame:HookScript("OnShow", DockCharacterFrame)
    hooksecurefunc(PVEFrame, "SetPoint", DockCharacterFrame)
    PVEFrame:HookScript("OnHide", function()
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
            RestoreDefaultCharacterPoint()
        end
    end)
end

-- INIT. Idempotent + existence-guarded; safe to call on PLAYER_LOGIN and again on
-- Blizzard_GroupFinder load (frames/globals only exist after that addon). Each
-- feature's hooks are installed ONLY when that feature is enabled, so a disabled
-- feature attaches no hooks and creates no frames.
EllesmereUI._GroupFinder_InitQoL = function()
    if RememberRolesOn() then InstallRememberRolesHooks() end
    InstallPVEDockHooks()
end

-- Called by the options toggle when a QoL flag flips: installs that feature's
-- hooks lazily on first enable. No reload needed.
EllesmereUI._GroupFinder_RefreshQoL = function()
    if RememberRolesOn() then InstallRememberRolesHooks() end
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
    Blizzard_PVPUI = function()
        if not SkinEnabled() then return end
        if not Theme.bgR then ResolveTheme() end
        Skin_PVP(); InstallPVPHooks(); Restrip()
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
