-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_WindowEngine.lua
--  Shared engine for the Blizzard Window Skins system: style-aware window
--  shells (EllesmereUI atlas style vs Modern flat color), the primitive
--  skinners every window pack builds from, and per-window boot orchestration
--  for load-on-demand Blizzard addons.
--
--  Style model (per window, chosen on the Blizzard Window Skins options page):
--    "eui"    -> the dungeons-and-raids shell: modern_blizz atlas backdrop
--                (cover-fit) + black overlay, full opacity.
--    "modern" -> identical skin, but the shell backdrop is a flat user-set
--                color + opacity (one global Modern color, applied live).
--    "off"    -> the window pack never runs (reload-gated).
--  EUI vs Modern differ ONLY in the shell backdrop; every other element
--  (buttons, tabs, borders, insets) is identical. eui<->modern applies LIVE
--  via RefreshStyles(); only off<->on needs a reload.
--
--  Safety rules (hard requirements, see CLAUDE.md):
--   - Per-frame state lives in a weak-keyed EXTERNAL table (FFD); we never
--     write custom keys onto Blizzard frames.
--   - Visual-only: SetAlpha(0) on textures. Never Hide/Show/SetParent a
--     Blizzard frame, never EnableMouse walks, never SetScript on Blizzard
--     frames (HookScript/hooksecurefunc only).
--   - No reads of protected/secret data anywhere in the skin path.
--   - Each window pack is pcall-isolated: one window breaking can never stop
--     the others from skinning.
--   - Zero cost when a window is off: hooks install only for enabled windows.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = EllesmereUI
local issecretvalue = issecretvalue or function() return false end

local WSkin = {}
ns.WSkin = WSkin

-- Weak-keyed external state (prevents tainting Blizzard frames) ---------------
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end
WSkin.GetFFD = GetFFD
WSkin.FFD = FFD

-------------------------------------------------------------------------------
--  Theme tokens. Matches the dungeons-and-raids reskin so every window reads
--  as one family. Accent tracks the user's live accent color.
-------------------------------------------------------------------------------
local Theme = {}
WSkin.Theme = Theme
local function ResolveTheme()
    local EG = (EUI and EUI.ELLESMERE_GREEN) or { r = 0.047, g = 0.824, b = 0.616 }
    Theme.accR, Theme.accG, Theme.accB = EG.r or 0.047, EG.g or 0.824, EG.b or 0.616
    -- Neutral dark grays (no color cast): panel/button/dropdown fill and the
    -- darker nested-inset variant.
    Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA = 0.08, 0.08, 0.08, 0.92
    Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA = 0.04, 0.04, 0.04, 0.85
    Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA = 0.2, 0.2, 0.2, 1
    Theme.fontPath = (EUI and EUI.GetFontPath and EUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
    Theme.fontFlag = (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("blizzardSkin")) or ""
    -- Drop shadow only in no-outline mode, honoring the user's shadow toggle.
    Theme.fontShadow = (Theme.fontFlag == "")
        and (not (EUI and EUI.GetFontUseShadow) or EUI.GetFontUseShadow("blizzardSkin"))
end
WSkin.ResolveTheme = ResolveTheme

local function SolidTex(parent, layer, r, g, b, a, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(r, g, b, a)
    return t
end
WSkin.SolidTex = SolidTex

local function AddBorder(frame, r, g, b, a)
    if GetFFD(frame).border then return end
    local PP = EUI and (EUI.PanelPP or EUI.PP)
    if PP and PP.CreateBorder then
        PP.CreateBorder(frame, r or Theme.brdR, g or Theme.brdG, b or Theme.brdB, a or Theme.brdA, 1, "OVERLAY", 7)
        GetFFD(frame).border = true
    end
end
WSkin.AddBorder = AddBorder

-------------------------------------------------------------------------------
--  Modern style storage. The enable booleans + style names live in the options
--  system; the engine only resolves the ONE global Modern backdrop color
--  (default #111111 at 97% opacity).
-------------------------------------------------------------------------------
local MODERN_FALLBACK = { r = 0.067, g = 0.067, b = 0.067, a = 0.97 }
function WSkin.GetModernBG()
    local db = EllesmereUIDB
    local c = db and db.blizzWindowModernDefault
    if not (c and c.r) then c = MODERN_FALLBACK end
    return c.r or MODERN_FALLBACK.r, c.g or MODERN_FALLBACK.g,
           c.b or MODERN_FALLBACK.b, c.a or MODERN_FALLBACK.a
end

function WSkin.GetStyle(winKey)
    if EUI and EUI.GetBlizzWindowStyle then return EUI.GetBlizzWindowStyle(winKey) end
    return "eui"
end

-------------------------------------------------------------------------------
--  FadeRegions: alpha-out every direct texture region on a frame (+ NineSlice).
--  `keep` is a set of texture objects to leave alone. Visual-only, no Hide().
-------------------------------------------------------------------------------
local function FadeRegions(frame, keep)
    if not frame or frame:IsForbidden() then return end
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and not (keep and keep[r]) then
            r:SetAlpha(0)
        end
    end
    if frame.NineSlice then FadeRegions(frame.NineSlice, keep) end
end
WSkin.FadeRegions = FadeRegions

-- NineSlice pieces get re-shown/re-laid-out by Blizzard on some updates; alpha
-- each named piece as well as the container so a relayout cannot resurrect it.
local NINESLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}
local function FadeNineSlice(nsl)
    if not nsl then return end
    FadeRegions(nsl)
    for _, k in ipairs(NINESLICE_PIECES) do
        local p = nsl[k]
        if p and p.SetAlpha then p:SetAlpha(0) end
    end
    if nsl.SetAlpha then nsl:SetAlpha(0) end
end
WSkin.FadeNineSlice = FadeNineSlice

-------------------------------------------------------------------------------
--  Restrip registry: frames Blizzard repaints get re-faded on demand. Every
--  texture the engine itself created is protected via the frame's FFD entry.
-------------------------------------------------------------------------------
local _restrip = {}
local function Register(frame, keep)
    if frame then _restrip[frame] = keep or true end
end
WSkin.Register = Register

local PROTECT_KEYS = { "bg", "bgOverlay", "modernBg", "hover", "selBar", "rightShade", "fill", "x", "topBar", "arrow", "caret" }
local function Restrip()
    for frame, keep in pairs(_restrip) do
        if frame and not frame:IsForbidden() then
            local k = (type(keep) == "table") and keep or nil
            local d = FFD[frame]
            if d then
                k = k or {}
                for _, key in ipairs(PROTECT_KEYS) do
                    if d[key] then k[d[key]] = true end
                end
            end
            FadeRegions(frame, k)
        end
    end
end
WSkin.Restrip = Restrip

-------------------------------------------------------------------------------
--  Style-aware window shell. Creates BOTH backdrop variants on the frame and
--  shows the one matching the window's current style:
--    eui    -> modern_blizz atlas (cover-fit) + black 0.62 overlay
--    modern -> flat user color + opacity
--  All shells register here so RefreshStyles() can live-swap and recolor.
-------------------------------------------------------------------------------
local _shells = {}   -- winKey -> { frame = f } (strong: permanent frames)

local BG_ASPECT = 561 / 433
local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T

local function ApplyShellStyle(winKey)
    local entry = _shells[winKey]
    if not entry then return end
    for frame in pairs(entry) do
        local d = FFD[frame]
        if d then
            local style = WSkin.GetStyle(winKey)
            if style == "modern" then
                if d.bg then d.bg:SetAlpha(0) end
                if d.bgOverlay then d.bgOverlay:SetAlpha(0) end
                if d.modernBg then
                    local r, g, b, a = WSkin.GetModernBG()
                    d.modernBg:SetColorTexture(r, g, b, a)
                    -- Re-raise the region alpha too: a foreign restrip pass may
                    -- have zeroed it (color alpha and region alpha multiply).
                    d.modernBg:SetAlpha(1)
                end
            else
                if d.bg then d.bg:SetAlpha(1) end
                -- Region alpha is show/hide only; the darken strength lives in
                -- the overlay's color alpha (they multiply).
                if d.bgOverlay then d.bgOverlay:SetAlpha(1) end
                if d.modernBg then d.modernBg:SetColorTexture(0, 0, 0, 0) end
            end
        end
    end
end

-- Re-resolve every registered shell (style switches + Modern color edits apply
-- live; no reload). Exposed on EllesmereUI so the options page can call it.
function WSkin.RefreshStyles()
    for winKey in pairs(_shells) do ApplyShellStyle(winKey) end
end
if EUI then EUI._WSkinRefreshStyles = WSkin.RefreshStyles end

-- Attach the style system to a frame that ALREADY has an atlas shell built.
-- Pass the shell's atlas texture + black overlay explicitly when they live in
-- another file's own state table (Character Sheet, Inspect, LFG shell).
function WSkin.AdoptShell(winKey, frame, atlasTex, overlayTex)
    if not frame then return end
    local d = GetFFD(frame)
    if atlasTex then d.bg = atlasTex end
    if overlayTex then d.bgOverlay = overlayTex end
    if not d.modernBg then
        d.modernBg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        d.modernBg:SetColorTexture(0, 0, 0, 0)
        d.modernBg:SetAllPoints(frame)
    end
    local entry = _shells[winKey]
    if not entry then entry = {}; _shells[winKey] = entry end
    entry[frame] = true
    ApplyShellStyle(winKey)
end

-- Full shell build for a window pack: fade Blizzard art, lay both backdrop
-- variants, border it, apply the current style. opts.noBorder skips the frame
-- border (for frames whose rect extends past their visible panel).
function WSkin.Shell(winKey, frame, opts)
    if not frame or frame:IsForbidden() then return end
    local d = GetFFD(frame)
    local keep = {}
    for _, key in ipairs(PROTECT_KEYS) do
        if d[key] then keep[d[key]] = true end
    end
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

        -- Cover-fit: crop the atlas so it fills the frame without stretching.
        local function UpdateBgTexCoords()
            local fw, fh = frame:GetSize()
            if not fw or fw == 0 or not fh or fh == 0 then return end
            if issecretvalue(fw) or issecretvalue(fh) then return end
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

        -- Black top bar behind the window title. Sits above both style
        -- backdrops (-8/-7/-6) and below all content and the border overlay.
        local topBar = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        topBar:SetColorTexture(0, 0, 0, 0.5)
        topBar:SetPoint("TOPLEFT")
        topBar:SetPoint("TOPRIGHT")
        topBar:SetHeight(25)
        d.topBar = topBar
    end
    if not (opts and opts.noBorder) then WSkin.AtlasBorder(frame) end
    WSkin.AdoptShell(winKey, frame)
end

-- Window border: AdventureMap_TopBorder is a complete window-frame atlas
-- (1002x668, transparent middle). It stretches to the window's size and lays
-- over the backdrop, replacing the 1px line border on shells. Falls back to
-- the 1px border if the atlas is ever missing.
local BORDER_ATLAS = "AdventureMap_TopBorder"
function WSkin.AtlasBorder(frame)
    if not frame or frame:IsForbidden() then return end
    local d = GetFFD(frame)
    if d.atlasBorder then return end
    d.atlasBorder = true
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS)
    if not info then
        AddBorder(frame)
        return
    end

    local ov = CreateFrame("Frame", nil, frame)
    ov:SetAllPoints(frame)
    ov:SetFrameLevel(frame:GetFrameLevel() + 6)
    d.atlasBorderFrame = ov

    local tex = ov:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetAtlas(BORDER_ATLAS)
    tex:SetAllPoints(ov)
end

-- Content shade: the 25% black wash the reskins lay behind their content areas
-- so text zones read darker than the shell art.
function WSkin.ContentShade(frame, p1, x1, y1, p2, x2, y2, alpha)
    if not frame or frame:IsForbidden() then return end
    local d = GetFFD(frame)
    if d.rightShade then return d.rightShade end
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    shade:SetColorTexture(0, 0, 0, alpha or 0.25)
    shade:SetPoint(p1 or "TOPLEFT", frame, p1 or "TOPLEFT", x1 or 0, y1 or 0)
    shade:SetPoint(p2 or "BOTTOMRIGHT", frame, p2 or "BOTTOMRIGHT", x2 or 0, y2 or 0)
    d.rightShade = shade
    return shade
end

-------------------------------------------------------------------------------
--  Primitive skinners. All idempotent (guarded via FFD), all visual-only.
-------------------------------------------------------------------------------

-- Flat solid panel. opts.noBg = strip only; opts.inset = darker nested fill;
-- opts.noBorder = skip border; opts.shade = translucent black content wash.
function WSkin.Panel(frame, opts)
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
        if opts.shade then r, g, b, a = 0, 0, 0, 0.25 end
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetColorTexture(r, g, b, a)
        bg:SetAllPoints(frame)
        d.bg = bg
    end
    if not opts.noBorder then AddBorder(frame) end
end

-- Strip an InsetFrameTemplate child (Bg + rounded NineSlice box) so it blends
-- into the shell instead of showing a nested box.
function WSkin.Inset(inset)
    if not inset or inset:IsForbidden() then return end
    FadeRegions(inset)
    if inset.Bg then inset.Bg:SetAlpha(0) end
    if inset.NineSlice then FadeNineSlice(inset.NineSlice) end
    Register(inset, true)
end

function WSkin.Font(fs, r, g, b)
    if not fs or not fs.GetFont or (fs.IsForbidden and fs:IsForbidden()) then return end
    local _, size = fs:GetFont()
    if size and issecretvalue(size) then return end
    -- 12.0.7: shadows only render from a FontObject, never from instance
    -- SetShadowOffset. Prime BEFORE SetFont (SetFont then restores the face).
    if EUI and EUI.PrimeFontShadow then EUI.PrimeFontShadow(fs, Theme.fontShadow) end
    fs:SetFont(Theme.fontPath, size or 12, Theme.fontFlag or "")
    if r then fs:SetTextColor(r, g, b or r) end
end

-- Force a FontString readable-white without touching its font file.
function WSkin.White(fs, r, g, b)
    if fs and fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1) end
end

-- Generic action button -> flat dark block with a subtle white hover.
-- keepKeys preserves named regions (e.g. {"Icon"}).
function WSkin.Button(btn, keepKeys)
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

    -- Label font stays Blizzard's (color-only text policy).
    Register(btn, keep)
end

-- Force a button's label white (color only, font untouched). Many action
-- buttons render their enabled text in Blizzard gold; this is opt-in per call
-- (WSkin.Button leaves labels alone). Buttons re-apply their font object when
-- re-enabled, so re-white on every OnEnable as well as now.
function WSkin.WhiteButtonLabel(btn)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) then return end
    local lab = btn.Text or (btn.GetFontString and btn:GetFontString())
    if not lab then return end
    WSkin.White(lab)
    local d = GetFFD(btn)
    if not d.whiteHook then
        d.whiteHook = true
        if btn.HookScript then btn:HookScript("OnEnable", function() WSkin.White(lab) end) end
    end
end

-- Like WhiteButtonLabel, but the label mirrors the native enabled/disabled
-- states: white when clickable, gray when not (a plain white label leaves a
-- disabled button reading as active, since our color write overrides the
-- disabled-font gray).
function WSkin.StateButtonLabel(btn)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) then return end
    local lab = btn.Text or (btn.GetFontString and btn:GetFontString())
    if not lab then return end
    local d = GetFFD(btn)
    if d.stateHook then return end
    d.stateHook = true
    local function reflect()
        if btn:IsEnabled() then WSkin.White(lab) else lab:SetTextColor(0.5, 0.5, 0.5) end
    end
    if btn.HookScript then
        btn:HookScript("OnEnable", reflect)
        btn:HookScript("OnDisable", reflect)
    end
    reflect()
end

-- Search / input box -> near-black block, border, art gone.
function WSkin.EditBox(eb)
    if not eb or eb:IsForbidden() then return end
    local d = GetFFD(eb)
    if d.bg then return end
    FadeRegions(eb)
    for _, k in ipairs({ "Left", "Right", "Middle", "Mid" }) do
        local r = eb[k]; if r and r.SetAlpha then r:SetAlpha(0) end
    end
    local fill = SolidTex(eb, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fill:SetAllPoints(eb)
    d.bg = fill
    -- Same border as WSkin.Button (theme defaults).
    AddBorder(eb)
end

-- Checkbox -> dark block + accent tick. opts.stockCheck leaves the checkmark
-- color to Blizzard (windows where check tint carries meaning, e.g. the
-- addon list's enabled states).
function WSkin.Checkbox(cb, opts)
    if not cb or cb:IsForbidden() then return end
    local d = GetFFD(cb)
    if d.skinned then return end
    d.skinned = true
    if cb.SetNormalTexture then cb:SetNormalTexture("") end
    if cb.SetPushedTexture then cb:SetPushedTexture("") end
    if cb.SetHighlightTexture then cb:SetHighlightTexture("") end
    -- Some checkbox templates draw the box border as a separate region rather
    -- than the Normal texture, so fade every existing texture except the
    -- checkmark before laying down our own flat box. (No-op for plain
    -- checkboxes: they carry nothing beyond Normal/Pushed/Highlight/Checked.)
    local checked = cb.GetCheckedTexture and cb:GetCheckedTexture()
    local dchecked = cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture()
    for i = 1, select("#", cb:GetRegions()) do
        local r = select(i, cb:GetRegions())
        if r and r ~= checked and r ~= dchecked
           and r.IsObjectType and r:IsObjectType("Texture") then
            r:SetAlpha(0)
        end
    end
    local fill = SolidTex(cb, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fill:SetPoint("TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", -4, 4)
    d.bg = fill
    -- Border rides the checkbox frame by default; when the frame is larger
    -- than its visible box (opts.borderInset), put the border on an inset
    -- child so it hugs the actual box instead of sitting proud of it.
    local bi = opts and opts.borderInset
    if bi and bi > 0 then
        local bh = CreateFrame("Frame", nil, cb)
        bh:SetPoint("TOPLEFT", bi, -bi)
        bh:SetPoint("BOTTOMRIGHT", -bi, bi)
        bh:SetFrameLevel(cb:GetFrameLevel() + 1)
        AddBorder(bh, 0.25, 0.25, 0.25, 1)
        d.borderHost = bh
    else
        AddBorder(cb, 0.25, 0.25, 0.25, 1)
    end
    if checked and not (opts and opts.stockCheck) then
        checked:SetVertexColor(Theme.accR, Theme.accG, Theme.accB, 1)
    end
end

-- Modern dropdown / legacy selector -> flat block. Nil-guarded per template.
function WSkin.Dropdown(dd)
    if not dd or dd:IsForbidden() then return end
    local d = GetFFD(dd)
    if d.skinned then return end
    d.skinned = true
    FadeRegions(dd)
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
    -- Label recolored white; the font itself stays Blizzard's.
    local label = dd.Text or (dd.GetFontString and dd:GetFontString())
    if label then WSkin.White(label) end
end

-- AH-style click-to-sort header bar over a list's HeaderContainer: a 50% near-
-- black strip spanning the LIST's own width and riding the header row, column
-- 3-slice art flattened to invisible plates with white labels and a
-- full-strip-height hover. Re-run from the list's refresh / OnShow hook since
-- columns pool and rebuild. No wash dependency (unlike the AH pack's own
-- wash-relative seating) -- the strip spans the list rect directly.
function WSkin.SortHeaderBar(list)
    local hc = list and list.HeaderContainer
    if not hc then return end
    local sd = GetFFD(list)
    if not sd.strip then
        local sTex = list:CreateTexture(nil, "BACKGROUND", nil, 1)
        sTex:SetColorTexture(0.02, 0.02, 0.02, 0.5)
        sTex:SetHeight(24)
        sd.strip = sTex
        sd.fill = sTex   -- protected key so a Restrip never fades our own strip
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

-- MinimalScrollBar -> strip track/arrows; the thumb becomes a slim 5px white
-- strip centered in the thumb's hit area (the house scrollbar look).
function WSkin.ScrollBar(sb)
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

-- Recursively flatten any MinimalScrollBar under a frame. Shallow + one-time
-- (guarded per bar); used at skin time only, never in per-update hooks.
function WSkin.ScrollBarsIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 7 or frame:IsForbidden() then return end
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and not WSkin.IsForeignFrame(child, frame) then
            if child.Track and (child.Back or child.Forward) then WSkin.ScrollBar(child) end
            WSkin.ScrollBarsIn(child, depth + 1)
        end
    end
end

-- Close (X) button -> strip art, draw the house close glyph.
function WSkin.CloseButton(btn)
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

-- Page-nav / arrow button -> flat block with a house arrow texture
-- (falls back to a text glyph for unmapped characters).
local PAGE_ARROWS = {
    ["<"] = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png",
    [">"] = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-right.png",
}
function WSkin.PageButton(btn, ch, size)
    if not btn or btn:IsForbidden() then return end
    local d = GetFFD(btn)
    if d.block then return end
    d.block = true
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local fn = btn[g]; local t = fn and fn(btn)
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    local bg = SolidTex(btn, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    bg:SetAllPoints(btn)
    d.bg = bg
    AddBorder(btn)
    local tex = PAGE_ARROWS[ch]
    if tex then
        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(tex)
        local s = size or 14
        arrow:SetSize(s, s)
        arrow:SetPoint("CENTER")
        arrow:SetAlpha(0.9)
        d.arrow = arrow
    else
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont(Theme.fontPath, size or 14, Theme.fontFlag or "")
        fs:SetPoint("CENTER")
        fs:SetText(ch)
        fs:SetTextColor(1, 1, 1, 0.9)
        d.arrow = fs
    end
    local hover = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(btn)
    d.hover = hover
    -- Disabled (can't page further) -> whole block at half opacity.
    local function reflect()
        btn:SetAlpha(btn:IsEnabled() and 1 or 0.5)
    end
    btn:HookScript("OnEnable", reflect)
    btn:HookScript("OnDisable", reflect)
    reflect()
end

-- Find PrevPageButton/NextPageButton anywhere shallow under a frame.
function WSkin.PagingIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 8 or not frame.GetChildren or frame:IsForbidden() then return end
    if depth > 0 and WSkin.IsForeignFrame(frame) then return end
    if frame.PrevPageButton then WSkin.PageButton(frame.PrevPageButton, "<") end
    if frame.NextPageButton then WSkin.PageButton(frame.NextPageButton, ">") end
    for i = 1, select("#", frame:GetChildren()) do
        WSkin.PagingIn(select(i, frame:GetChildren()), depth + 1)
    end
end

-- 1px black frame around a texture region (squared icons).
function WSkin.BorderRegion(parent, region)
    if not (parent and region) then return end
    local d = GetFFD(region)
    if d.bordered then return end
    d.bordered = true
    local function line()
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    local t, b, l, r = line(), line(), line(), line()
    t:SetPoint("TOPLEFT", region, "TOPLEFT", -1, 1);        t:SetPoint("TOPRIGHT", region, "TOPRIGHT", 1, 1);        t:SetHeight(1)
    b:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -1, -1); b:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 1, -1); b:SetHeight(1)
    l:SetPoint("TOPLEFT", region, "TOPLEFT", -1, 1);        l:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -1, -1);  l:SetWidth(1)
    r:SetPoint("TOPRIGHT", region, "TOPRIGHT", 1, 1);       r:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 1, -1); r:SetWidth(1)
end

-- Square an icon texture (crop the baked bevel) and optionally border it.
function WSkin.SquareIcon(icon, parent)
    if not icon or not icon.SetTexCoord then return end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if parent then WSkin.BorderRegion(parent, icon) end
end

-- Remove a PortraitFrameTemplate's corner portrait.
function WSkin.RemovePortrait(frame)
    if not frame then return end
    local pc = frame.PortraitContainer
    if pc then
        FadeRegions(pc)
        Register(pc, true)
        if pc.portrait and pc.portrait.SetAlpha then pc.portrait:SetAlpha(0) end
    end
    if frame.portrait and frame.portrait.SetAlpha then frame.portrait:SetAlpha(0) end
end

-------------------------------------------------------------------------------
--  Tabs. One shared PanelTemplates hook keeps selection state fresh across all
--  skinned tabs (bottom tabs and TabSystem top tabs both flow through here).
-------------------------------------------------------------------------------
local _skinnedTabs = setmetatable({}, { __mode = "k" })

local TAB_BG      = { 0.068, 0.056, 0.052 }
local TAB_BG_DARK = { 0.03, 0.03, 0.03 }

local function TabIsSelected(tab)
    -- FFD override first: windows with nonstandard tab systems (auction
    -- house displayMode) sync selection into FFD themselves -- never onto
    -- the Blizzard tab.
    local od = FFD[tab]
    if od and od.selOverride ~= nil then return od.selOverride end
    -- The tab system's selectedTabID is authoritative. Pool-rebuilt tab rows
    -- (housing content tabs) can carry a stale isSelected=false after their
    -- system re-inits them, so the per-button flag is only a fallback.
    local parent = tab:GetParent()
    if parent and parent.selectedTabID ~= nil and tab.tabID ~= nil then
        return parent.selectedTabID == tab.tabID
    end
    if tab.isSelected ~= nil then return tab.isSelected and true or false end
    if parent and PanelTemplates_GetSelectedTab and tab.GetID then
        local ok, s = pcall(PanelTemplates_GetSelectedTab, parent)
        if ok and s ~= nil then return s == tab:GetID() end
    end
    return false
end

local function UpdateTabVisual(tab)
    local d = FFD[tab]
    if not d or not d.underline then return end
    local sel = TabIsSelected(tab)
    if d.label then d.label:SetTextColor(1, 1, 1, sel and 1 or 0.5) end
    d.underline:SetShown(sel and WSkin.AccentBarShown())
    -- darkActive tabs deepen the fill when selected instead of the additive
    -- lighten wash.
    if d.activeHL then d.activeHL:SetShown(sel and not d.darkActive) end
    if d.bg and d.darkActive then
        local c = sel and TAB_BG_DARK or TAB_BG
        d.bg:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

local function UpdateAllTabs()
    for tab in pairs(_skinnedTabs) do
        if not tab:IsForbidden() then UpdateTabVisual(tab) end
    end
end
WSkin.UpdateAllTabs = UpdateAllTabs

local _tabHooked = false
local function EnsureTabHooks()
    if _tabHooked then return end
    _tabHooked = true
    if PanelTemplates_SetTab then hooksecurefunc("PanelTemplates_SetTab", UpdateAllTabs) end
    if PanelTemplates_UpdateTabs then hooksecurefunc("PanelTemplates_UpdateTabs", UpdateAllTabs) end
end

-- Tab -> the dungeons-and-raids tab pattern, copied exactly: native art
-- cleared permanently (SetTexture, so tabs never need a re-strip pass), flat
-- dark block, our own 11px label mirroring Blizzard's text, a faint additive
-- wash + a pixel-perfect full-width accent underline on the active tab.
-- Works for PanelTabButtonTemplate and TabSystem buttons.
function WSkin.Tab(tab, opts)
    if not tab or tab:IsForbidden() then return end
    local d = GetFFD(tab)
    if opts and opts.darkActive then d.darkActive = true end
    if d.bg then
        UpdateTabVisual(tab)
        if d.label and d.blizLabel and d.blizLabel.GetText then
            d.label:SetText(d.blizLabel:GetText() or "")
        end
        return
    end
    d.skinned = true   -- keeps the generic ButtonsIn sweep off skinned tabs
    for j = 1, select("#", tab:GetRegions()) do
        local r = select(j, tab:GetRegions())
        if r and r:IsObjectType("Texture") then
            r:SetTexture("")
            if r.SetAtlas then r:SetAtlas("") end
        end
    end
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        if tab[k] and tab[k].SetTexture then tab[k]:SetTexture("") end
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

    local blizLabel = tab.Text or (tab.GetFontString and tab:GetFontString())
    local labelText = (blizLabel and blizLabel.GetText and blizLabel:GetText()) or ""
    if blizLabel and blizLabel.SetTextColor then blizLabel:SetTextColor(0, 0, 0, 0) end
    if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end

    local label = tab:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fontPath, 11, Theme.fontFlag or "")
    label:SetPoint("CENTER", tab, "CENTER", 0, 0)
    label:SetText(labelText)
    d.label = label
    d.blizLabel = blizLabel
    -- Mirror the live Blizzard text onto our label. Read it back off the
    -- (hidden) original after each write so dynamic updates land -- some labels
    -- carry a trailing count like "Public Orders (4)" set via SetFormattedText
    -- or a direct FontString:SetText, neither of which routes through the
    -- button's SetText.
    local function SyncLabel()
        if d.label and d.blizLabel and d.blizLabel.GetText then
            d.label:SetText(d.blizLabel:GetText() or "")
        end
    end
    hooksecurefunc(tab, "SetText", SyncLabel)
    if blizLabel then
        hooksecurefunc(blizLabel, "SetText", SyncLabel)
        if blizLabel.SetFormattedText then hooksecurefunc(blizLabel, "SetFormattedText", SyncLabel) end
    end

    local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
    if EUI and EUI.PanelPP and EUI.PanelPP.DisablePixelSnap then
        EUI.PanelPP.DisablePixelSnap(underline)
        underline:SetHeight(EUI.PanelPP.mult or 1)
    else
        underline:SetHeight(1)
    end
    underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    -- Color resolves from the Global Options accent-bar setting; the engine's
    -- looks refresh (not per-texture accent registration) keeps it current.
    local ur, ug, ub = WSkin.AccentBarColor()
    underline:SetColorTexture(ur, ug, ub, 1)
    underline:Hide()
    d.underline = underline

    _skinnedTabs[tab] = true
    EnsureTabHooks()
    -- TabSystem buttons do not flow through PanelTemplates_SetTab; refresh all
    -- skinned tabs one frame after any tab click.
    tab:HookScript("OnClick", function()
        if C_Timer then C_Timer.After(0, UpdateAllTabs) else UpdateAllTabs() end
    end)
    UpdateTabVisual(tab)
end

-- Force a row of skinned tabs to a uniform one-physical-pixel seam. Each
-- Blizzard tab template bakes in its own transparent art padding + anchor
-- offsets, so once the art is replaced by an edge-to-edge flat block the raw
-- frame gaps (2-5px on some templates) show through as inconsistent spacing.
-- Re-chain each tab to the previous tab's right edge + 1px, matching the tight
-- seam a TabSystem produces. The first tab keeps Blizzard's seat; because the
-- chain is relative, it reflows automatically when Blizzard resizes a tab.
-- `tabs` is an ordered (left-to-right) array; nil/missing/hidden entries are
-- skipped so a conditionally-hidden tab (group finder, encounter journal)
-- never leaves a gap in the chain.
function WSkin.NormalizeTabRow(tabs)
    if not tabs then return end
    -- One physical pixel in the TAB's own coordinate space. Blizzard windows
    -- run at UIParent scale, NOT the EUI options-panel scale, so PanelPP.mult
    -- is the wrong multiplier -- it lands the gap between 1 and 2 physical
    -- pixels and rounds inconsistently. PP.perfect (= 1 physical pixel at
    -- scale 1) divided by the tab's effective scale is exact at any scale.
    local PP = EUI and EUI.PP
    -- Shave a few px off every skinned tab's height, ONCE per tab (guarded in
    -- the WSkin FFD so repeated re-skins never shrink it cumulatively). Applied
    -- here so every window's bottom tab row gets the same shorter profile.
    local TAB_TRIM_H = 2
    local prev
    for i = 1, #tabs do
        local t = tabs[i]
        if t and t.IsForbidden and not t:IsForbidden()
           and (not t.IsShown or t:IsShown()) then
            local d = GetFFD(t)
            if not d.heightTrimmed and t.SetHeight and t.GetHeight then
                d.heightTrimmed = true
                local h = t:GetHeight() or 0
                if h > TAB_TRIM_H then t:SetHeight(h - TAB_TRIM_H) end
            end
            if prev then
                local gap = (PP and PP.mult) or 1
                local es = t.GetEffectiveScale and t:GetEffectiveScale()
                if PP and PP.perfect and es and es > 0 then
                    gap = PP.perfect / es
                end
                t:ClearAllPoints()
                t:SetPoint("LEFT", prev, "RIGHT", gap, 0)
            end
            prev = t
        end
    end
end

-- Flatten every Button child of a TabSystemTemplate.
function WSkin.TabSystem(tsys, opts)
    if not tsys then return end
    -- Programmatic tab switches (SetTab) never pass through the
    -- PanelTemplates hooks or a tab's OnClick; repaint on them directly.
    local d = GetFFD(tsys)
    if tsys.SetTab and not d.setTabHook then
        d.setTabHook = true
        hooksecurefunc(tsys, "SetTab", UpdateAllTabs)
    end
    for i = 1, select("#", tsys:GetChildren()) do
        local child = select(i, tsys:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
            WSkin.Tab(child, opts)
        end
    end
end

-------------------------------------------------------------------------------
--  Global look settings (Blizzard Window Skins -> Global Options). Central
--  EllesmereUIDB keys, nil = defaults: accent bar shown + accent colored, bar
--  fills accent at full opacity, links accent colored. Accent-mode elements
--  re-resolve from the LIVE accent color; a RegAccent callback keeps them in
--  sync on accent changes, and RefreshLooks() applies option edits live.
-------------------------------------------------------------------------------
local function LiveAccent()
    local EG = EUI and EUI.ELLESMERE_GREEN
    if EG then return EG.r or 0.047, EG.g or 0.824, EG.b or 0.616 end
    return 0.047, 0.824, 0.616
end

function WSkin.AccentBarShown()
    local c = EllesmereUIDB and EllesmereUIDB.blizzWinAccentBar
    return not (c and c.enabled == false)
end

-- Custom mode with no stored color resolves to WHITE -- the same fallback
-- the custom swatch displays. (Requiring a stored color made a fresh switch
-- to custom silently fall back to accent until the picker first saved one.)
function WSkin.AccentBarColor()
    local c = EllesmereUIDB and EllesmereUIDB.blizzWinAccentBar
    if c and c.useCustom then
        local col = c.color
        if col then return col.r or 1, col.g or 1, col.b or 1 end
        return 1, 1, 1
    end
    return LiveAccent()
end

function WSkin.BarFillColor()
    local c = EllesmereUIDB and EllesmereUIDB.blizzWinBarFill
    local a = (c and c.alpha) or 0.95
    if c and c.useCustom then
        local col = c.color
        if col then return col.r or 1, col.g or 1, col.b or 1, a end
        return 1, 1, 1, a
    end
    local r, g, b = LiveAccent()
    return r * 0.8, g * 0.8, b * 0.8, a
end

function WSkin.LinkColor()
    local c = EllesmereUIDB and EllesmereUIDB.blizzWinLinks
    if c and c.useCustom then
        local col = c.color
        if col then return col.r or 1, col.g or 1, col.b or 1 end
        return 1, 1, 1
    end
    return LiveAccent()
end

function WSkin.LinkColorHex()
    local r, g, b = WSkin.LinkColor()
    return string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Bar fills (flat accent progress bars) + tab underlines owned by files
-- outside the engine register here so option edits and accent changes
-- recolor them without a reload.
local _fillBars = setmetatable({}, { __mode = "k" })
local _extUnderlines = setmetatable({}, { __mode = "k" })
local _lookCallbacks = {}

function WSkin.ApplyBarFill(bar)
    if not bar or not bar.SetStatusBarColor then return end
    _fillBars[bar] = true
    local r, g, b, a = WSkin.BarFillColor()
    bar:SetStatusBarColor(r, g, b, a)
end

function WSkin.RegisterAccentUnderline(tex)
    if tex then _extUnderlines[tex] = true end
end

function WSkin.OnLooksChanged(fn)
    _lookCallbacks[#_lookCallbacks + 1] = fn
end

function WSkin.RefreshLooks()
    local ur, ug, ub = WSkin.AccentBarColor()
    for tab in pairs(_skinnedTabs) do
        local d = FFD[tab]
        if d and d.underline then d.underline:SetColorTexture(ur, ug, ub, 1) end
        if not tab:IsForbidden() then UpdateTabVisual(tab) end
    end
    for tex in pairs(_extUnderlines) do
        tex:SetColorTexture(ur, ug, ub, 1)
    end
    local br, bgr, bb, ba = WSkin.BarFillColor()
    for bar in pairs(_fillBars) do
        if bar.SetStatusBarColor and not bar:IsForbidden() then
            bar:SetStatusBarColor(br, bgr, bb, ba)
        end
    end
    for _, fn in ipairs(_lookCallbacks) do pcall(fn) end
end
if EUI then EUI._WSkinRefreshLooks = WSkin.RefreshLooks end
if EUI and EUI.RegAccent then
    EUI.RegAccent({ type = "callback", fn = function() WSkin.RefreshLooks() end })
end

-------------------------------------------------------------------------------
--  Targeted art sweeps. Used at SKIN TIME (or debounced repaint hooks), never
--  per-frame-update. Depth-capped; icons/models/our textures always survive.
-------------------------------------------------------------------------------
-- Content subtrees a window pack wants left alone (backgrounds that ARE the
-- content, e.g. the Adventure Guide Tutorials pane). Every recursive art
-- sweep skips an exempt frame and everything under it.
function WSkin.ExemptArt(frame)
    if frame then GetFFD(frame).artExempt = true end
end
function WSkin.IsArtExempt(frame)
    local d = FFD[frame]
    return d and d.artExempt or false
end

-- Frame provenance: is this frame Blizzard's, or was it parented into the
-- window by another addon? Every recursive DISCOVERY sweep (art fades, button
-- flattening, control/scrollbar/paging finds) skips foreign frames and their
-- whole subtree, so third-party panels riding a Blizzard window keep their own
-- look. Explicit primitive calls (WSkin.Button(frame), Panel, ...) stay
-- ungated: naming a frame is opting in.
--
-- The signal: Blizzard's secure code leaves SECURE references behind -- a
-- named frame's global, or the parentKey slot on its parent -- while frames
-- created by any addon leave tainted ones. issecurevariable reads taint
-- without spreading it, so the whole check is side-effect free. Frames with
-- no name and no reference on their parent (pooled list rows) stay treated as
-- Blizzard's; only confirmed-foreign verdicts cache (a frame could gain its
-- addon-written reference key after we first see it).
local _foreign = setmetatable({}, { __mode = "k" })

function WSkin.IsForeignFrame(frame, parent)
    if _foreign[frame] then return true end
    local name = frame.GetName and frame:GetName()
    if name and _G[name] == frame then
        if issecurevariable(name) then return false end
        _foreign[frame] = true
        return true
    end
    parent = parent or (frame.GetParent and frame:GetParent())
    if not parent then return false end
    local insecureRef = false
    for k, v in pairs(parent) do
        if type(k) == "string" and not issecretvalue(v) and v == frame then
            if issecurevariable(parent, k) then return false end
            insecureRef = true
        end
    end
    if insecureRef then
        _foreign[frame] = true
        return true
    end
    return false
end

local BG_ART_KEYS = {
    "CustomBG", "InfoBackground", "BackgroundTexture", "DungeonBackground",
    "Background", "background", "Bg", "bg", "WaterMark", "Watermark",
    "BackgroundOverlay", "Backplate", "CategoriesBG", "BackgroundTile",
    "TopFiligree", "BottomFiligree", "FilligreeOverlay",
    "BorderTopLeft", "BorderTopMiddle", "BorderTopRight",
    "BorderLeftMiddle", "BorderRightMiddle",
    "BorderBottomLeft", "BorderBottomMiddle", "BorderBottomRight",
}
function WSkin.FadeKeyedArt(frame, depth)
    depth = depth or 0
    if not frame or depth > 6 or frame:IsForbidden() then return end
    if WSkin.IsArtExempt(frame) then return end
    if depth > 0 and WSkin.IsForeignFrame(frame) then return end
    for _, key in ipairs(BG_ART_KEYS) do
        local t = frame[key]
        if t and t.IsObjectType and t:IsObjectType("Texture") then t:SetAlpha(0) end
    end
    if not frame.GetChildren then return end
    for i = 1, select("#", frame:GetChildren()) do
        WSkin.FadeKeyedArt(select(i, frame:GetChildren()), depth + 1)
    end
end

local ART_KEYWORDS = {
    "background", "corner", "parchment", "watermark", "shadow",
    "divider", "nineslice", "wood", "metal", "modelbackground",
    "-bg", "bg-", "frametexture", "sheen", "plaque", "tile",
    "marble", "stone", "filigree",
}
local function texIsIcon(hay)
    return hay and (hay:find("interface\\icons", 1, true) or hay:find("interface/icons", 1, true))
end
local function texHay(tex)
    local atlas = tex.GetAtlas and tex:GetAtlas()
    if atlas and not issecretvalue(atlas) then return atlas:lower() end
    local file = tex.GetTexture and tex:GetTexture()
    if type(file) == "string" then return file:lower() end
    return nil
end
WSkin.TexHay = texHay
WSkin.TexIsIcon = texIsIcon

-- Alpha decorative art under a frame by keyword, keeping icons and our own
-- textures. Depth-capped; call at skin time or from debounced hooks only.
function WSkin.FadeArtIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 9 or not frame.GetRegions or frame:IsForbidden() then return end
    if WSkin.IsArtExempt(frame) then return end
    if depth > 0 and WSkin.IsForeignFrame(frame) then return end
    local mybg = FFD[frame] and FFD[frame].bg
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r ~= mybg and r.IsObjectType and r:IsObjectType("Texture") and (r:GetAlpha() or 0) > 0 then
            local hay = texHay(r)
            if hay and not texIsIcon(hay) then
                for _, kw in ipairs(ART_KEYWORDS) do
                    if hay:find(kw, 1, true) then r:SetAlpha(0); break end
                end
            end
        end
    end
    for i = 1, select("#", frame:GetChildren()) do
        WSkin.FadeArtIn(select(i, frame:GetChildren()), depth + 1)
    end
end

-- Flatten classic 3-slice buttons (Left+Middle+Right) under a frame. Never
-- touches icon buttons. One-time per button; call at skin time.
function WSkin.ButtonsIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 9 or not frame.GetChildren or frame:IsForbidden() then return end
    if depth > 0 and WSkin.IsArtExempt(frame) then return end
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and not WSkin.IsForeignFrame(child, frame) then
            if child.GetObjectType and child:GetObjectType() == "Button"
               and not GetFFD(child).skinned and not GetFFD(child).x
               and child.Left and child.Middle and child.Right then
                WSkin.Button(child)
            end
            WSkin.ButtonsIn(child, depth + 1)
        end
    end
end

-- Search boxes and filter/sort dropdowns are created with a parentKey and no
-- global name, so they are found by their parent's field name. EditBoxes get
-- the input treatment, everything else the flat dropdown block + house arrow.
local CONTROL_KEYS = {
    "SearchBox", "searchBox", "FilterDropdown", "FilterButton",
    "TypeDropdown", "Dropdown", "ClassDropdown", "WeaponDropdown",
}
function WSkin.ControlsIn(frame, depth)
    depth = depth or 0
    if not frame or depth > 9 or not frame.GetChildren or frame:IsForbidden() then return end
    if depth > 0 and WSkin.IsArtExempt(frame) then return end
    if depth > 0 and WSkin.IsForeignFrame(frame) then return end
    for _, key in ipairs(CONTROL_KEYS) do
        local el = frame[key]
        if el and el.IsObjectType and el.GetObjectType then
            if el:IsObjectType("EditBox") then WSkin.EditBox(el) else WSkin.Dropdown(el) end
        end
    end
    for i = 1, select("#", frame:GetChildren()) do
        WSkin.ControlsIn(select(i, frame:GetChildren()), depth + 1)
    end
end

-- Common chrome for a framed panel: close button, search/filter controls,
-- page nav, scroll bars.
function WSkin.CommonChrome(frame, prefix)
    if frame.CloseButton then WSkin.CloseButton(frame.CloseButton) end
    if prefix then
        local cb = _G[prefix .. "CloseButton"]
        if cb then WSkin.CloseButton(cb) end
    end
    WSkin.ControlsIn(frame)
    WSkin.PagingIn(frame)
    WSkin.ScrollBarsIn(frame)
    -- Re-center the title: PortraitFrameTemplate anchors it relative to the
    -- (removed) portrait + close button, so it lands a few px off the frame's
    -- true center. Center it on the shell top bar instead. One-shot.
    local d = GetFFD(frame)
    if not d.titleCentered and d.topBar then
        local title = (frame.TitleContainer and frame.TitleContainer.TitleText)
            or frame.TitleText
            or (prefix and _G[prefix .. "TitleText"])
        if title and title.ClearAllPoints then
            d.titleCentered = true
            title:ClearAllPoints()
            title:SetPoint("CENTER", d.topBar, "CENTER", 0, 0)
            if title.SetJustifyH then title:SetJustifyH("CENTER") end
        end
    end
end

-- One-time re-skin hook on a frame's Show (visual repaint catch-all).
function WSkin.HookShow(frame, fn)
    local d = GetFFD(frame)
    if d.showHook then return end
    d.showHook = true
    frame:HookScript("OnShow", fn)
end

-- Debounce: collapse many hook fires in one frame into a single pass.
function WSkin.Debounce(fn)
    local pending = false
    return function()
        if pending then return end
        pending = true
        if C_Timer then
            C_Timer.After(0, function() pending = false; fn() end)
        else
            pending = false
            fn()
        end
    end
end

-------------------------------------------------------------------------------
--  Per-window boot. Packs register { key, addons = {...}, apply = fn } and the
--  engine applies them when their Blizzard addon loads (or at login for ones
--  already loaded). Gated on the window style ("off" = never runs) and
--  pcall-isolated so one pack can never break another.
-------------------------------------------------------------------------------
local _windows = {}

local function WindowOn(winKey)
    return WSkin.GetStyle(winKey) ~= "off"
end

local function TryApply(entry)
    if not WindowOn(entry.key) then return end
    if not Theme.fontPath then ResolveTheme() end
    local ok, err = pcall(entry.apply)
    if not ok and err then
        -- Surface through the normal error pipeline (respects scriptErrors)
        -- without stopping the other window packs.
        geterrorhandler()(err)
    end
end

function WSkin.RegisterWindow(entry)
    _windows[#_windows + 1] = entry
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        ResolveTheme()
        for _, entry in ipairs(_windows) do
            -- Immediate windows (no LoD addon) and any LoD addon that is
            -- already loaded get skinned now.
            local ready = true
            if entry.addons then
                for addon in pairs(entry.addons) do
                    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon)) then
                        ready = false
                        break
                    end
                end
            end
            if ready then TryApply(entry) end
        end
        WSkin.RefreshStyles()
    elseif event == "ADDON_LOADED" then
        for _, entry in ipairs(_windows) do
            if entry.addons and entry.addons[name] then TryApply(entry) end
        end
    end
end)
