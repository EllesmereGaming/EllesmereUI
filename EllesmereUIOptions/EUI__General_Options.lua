if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI__General_Options.lua -- Global Settings module (CVar-based settings
--  shared by all EllesmereUI addons).
--
--  Default-application policy: EUI preferred defaults apply ONLY while
--  C_CVar.GetCVarInfo shows the CVar still at Blizzard's default (untouched
--  by player/other addon). Widgets always read the live CVar to stay in sync.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL      = "General"
local PAGE_FONTS       = "Fonts"     -- centralized fonts page; body lives in EUI_Fonts_Options.lua
local PAGE_TEXTURES    = "Textures"  -- centralized textures page; body lives in EUI_Textures_Options.lua
local PAGE_STYLE       = "Style"     -- per-module EllesmereUI / Blizzard Style page; body lives in EUI_Style_Options.lua
local PAGE_COLORS      = "Colors"    -- the color half of the old "Fonts & Colors" page
local PAGE_PROFILES    = "Profiles"
local PAGE_PRESETS     = "Presets"   -- navigation tab over the presets subpage of the profiles page
local PAGE_WHATSNEW    = "Patch Notes"
local PAGE_LEGENDS     = "EUI Legends"

-- Profiles/Patch Notes are their own sidebar pages (single-page modules), not tabs under Global Settings. Keys match the sidebar buttons in EllesmereUI.lua.
local PROFILES_KEY     = "_EUIProfiles"
local PATCHNOTES_KEY   = "_EUIPatchNotes"

-- Standalone single-module builds rename the host addon to contain "Standalone". The What's New tab is suite-only, so it is never added to the page list there.
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil

-------------------------------------------------------------------------------
--  Shared CDM spell-layout export flow (full-profile AND per-addon export).
--  Asks to bundle the CDM spell layout (bar assignments + per-spell settings);
--  Yes opens the spec picker, then calls exportFn(includeCDM, cdmSpecs).
--  Exports ONLY on explicit "No" or a completed picker pick -- escaping
--  either popup produces NO export.
-------------------------------------------------------------------------------
function EllesmereUI.RunCDMSpellExportFlow(activeName, exportFn)
    local function pickThenExport()
        local specs = {}
        local sp = EllesmereUIDB and EllesmereUIDB.spellAssignments
            and EllesmereUIDB.spellAssignments.profiles
            and EllesmereUIDB.spellAssignments.profiles[activeName]
            and EllesmereUIDB.spellAssignments.profiles[activeName].specProfiles
        local n = (GetNumSpecializations and GetNumSpecializations()) or 0
        for i = 1, n do
            local specID = GetSpecializationInfo and GetSpecializationInfo(i)
            if specID then
                local key = tostring(specID)
                local d = sp and sp[key]
                specs[#specs + 1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true or false,
                }
            end
        end
        EllesmereUI:ShowCDMSpecPickerPopup({
            title         = EllesmereUI.L("Export CDM Spells"),
            subtitle      = EllesmereUI.L("This can't change which spells the user tracks in Blizzard's CDM.\nIt's recommended to also share your Blizzard CDM layout for any spec you choose here."),
            subtitleColor = { 1, 0.82, 0.2 },
            subtitleAtBottom = true,
            confirmText   = EllesmereUI.L("Export"),
            specs         = specs,
            onConfirm     = function(selectedSpecs) exportFn(true, selectedSpecs) end,
            onCancel      = function() end,  -- cancel / Esc / click-off: just close, NO export
        })
    end
    EllesmereUI:ShowConfirmPopup({
        title       = EllesmereUI.L("Include CDM Spell Layout?"),
        message     = EllesmereUI.L("Include your Cooldown Manager spell layout (which spells sit on which bars) plus all per-spell settings for any specs you choose."),
        confirmText = EllesmereUI.L("Yes"),
        cancelText  = EllesmereUI.L("No"),
        onConfirm   = function() pickThenExport() end,
        onCancel    = function() exportFn(false, nil) end,  -- "No": export WITHOUT layout
        onDismiss   = function() end,  -- Esc / click-off: just close, NO export
    })
end

-------------------------------------------------------------------------------
--  What's New page -- three tiers: hero cards (2/row), small clickable
--  listings, fix lines. Content: EllesmereUI._WHATSNEW_PATCHES (newest
--  first). Entry `nav` deep-links via NavigateToElementSettings (opens page,
--  pulses control); no `nav` = static non-clickable card. File-scope fn so
--  it adds no locals/upvalues to the deferred options closure below.
-------------------------------------------------------------------------------
function EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
    local PP  = EllesmereUI.PanelPP
    local EG  = EllesmereUI.ELLESMERE_GREEN
    local PAD = EllesmereUI.CONTENT_PAD
    local W   = EllesmereUI.Widgets
    local MakeFont   = EllesmereUI.MakeFont
    local MakeBorder = EllesmereUI.MakeBorder

    -- This page is a free-form feed, not a DualRow split layout.
    parent._showRowDivider = nil

    local y = yOffset
    local totalW = parent:GetWidth() - PAD * 2
    local CARD_GAP = 14

    -- Display prefix: "Module: " on every entry, and "WoW Forever - " in the
    -- Forever theme's bronze ahead of it on entries flagged `forever = true`
    -- (changes that apply on WoW Forever only), so the note text itself never
    -- has to say where it applies. Sorting stays by module, so a module's
    -- retail and Forever lines sit together.
    local FOREVER_TAG = "|cffdca77f" .. EllesmereUI.L("WoW Forever") .. "|r - "
    local function PrefixOf(e)
        return (e.forever and FOREVER_TAG or "") .. ((e.module and EllesmereUI.L(e.module) .. ": ") or "")
    end
    -- Display title: "Module: Title" (see PrefixOf).
    local function TitleOf(e)
        return PrefixOf(e) .. (EllesmereUI.L(e.title) or "")
    end

    -- Stable sort by module display name; preserves authored order per module.
    local function SortByModule(list)
        local idx = {}
        for i, e in ipairs(list) do idx[i] = { e, i } end
        table.sort(idx, function(a, b)
            local am, bm = a[1].module or "", b[1].module or ""
            if am ~= bm then return am < bm end
            return a[2] < b[2]
        end)
        local out = {}
        for i = 1, #idx do out[i] = idx[i][1] end
        return out
    end

    -- Deep-link to a setting (opens the page; highlights the control if mapped).
    local function GoTo(nav)
        if nav and nav.module then
            EllesmereUI:NavigateToElementSettings(nav.module, nav.page, nav.section, nav.preSelect, nav.highlight)
        end
    end

    -- Tier 1: clickable hero card -- dark fill, faint border, green top accent, title + wrapping description, hover lift.
    local function MakeHeroCard(x, cy, w, hgt, entry)
        local card = CreateFrame("Button", nil, parent)
        PP.Size(card, w, hgt)
        PP.Point(card, "TOPLEFT", parent, "TOPLEFT", x, cy)
        card:SetFrameLevel(parent:GetFrameLevel() + 2)

        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        local brd = MakeBorder(card, 1, 1, 1, 0.12, PP)

        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(EG.r, EG.g, EG.b, 0.6)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(accent) end

        local titleFs = MakeFont(card, 14, nil, EG.r, EG.g, EG.b, 0.9)
        PP.Point(titleFs, "TOPLEFT", card, "TOPLEFT", 16, -14)
        PP.Point(titleFs, "RIGHT", card, "RIGHT", -16, 0)
        titleFs:SetJustifyH("LEFT"); titleFs:SetWordWrap(false)
        titleFs:SetText(TitleOf(entry))

        local descFs = MakeFont(card, 12, nil, 1, 1, 1, 0.45)
        PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -7)
        PP.Point(descFs, "RIGHT", card, "RIGHT", -16, 0)
        descFs:SetJustifyH("LEFT"); descFs:SetJustifyV("TOP"); descFs:SetWordWrap(true)
        descFs:SetText(EllesmereUI.L(entry.desc) or "")

        -- Clickable only with a nav target. No nav renders a static card: no hover lift, no click, mouse disabled so nothing invites a dead click.
        if entry.onClick or (entry.nav and entry.nav.module) then
            card:SetScript("OnEnter", function()
                bg:SetColorTexture(0.11, 0.13, 0.15, 0.50); brd:SetColor(1, 1, 1, 0.22)
                titleFs:SetAlpha(1)
            end)
            card:SetScript("OnLeave", function()
                bg:SetColorTexture(0.06, 0.08, 0.10, 0.50); brd:SetColor(1, 1, 1, 0.12)
                titleFs:SetAlpha(0.9)
            end)
            card:SetScript("OnClick", function()
            if entry.onClick then entry.onClick() else GoTo(entry.nav) end
        end)
        else
            card:EnableMouse(false)
        end
    end

    -- Tier 1b: full-width banner hero (entry.banner = true), styled after our
    -- own announcement popups: solid fill, white 1px border, green top accent, eyebrow
    -- + large centered title/description, plus mirrored mini bar-chart art flanking the
    -- text (cost stepping down left, fps stepping up right). Takes a whole row; height
    -- follows description. Static unless the entry carries a nav.
    local function MakeBannerCard(x, cy, w, entry)
        local card = CreateFrame("Button", nil, parent)
        -- Width set FIRST (height provisional): description anchors L+R to the card, so a width-0 card would truncate it to one line instead of wrapping.
        PP.Size(card, w, 100)
        PP.Point(card, "TOPLEFT", parent, "TOPLEFT", x, cy)
        card:SetFrameLevel(parent:GetFrameLevel() + 2)

        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
        local brd = MakeBorder(card, 1, 1, 1, 0.15, PP)

        -- Per-entry accent (entry.accent = {r,g,b}); the theme accent otherwise.
        local ac = entry.accent or EG
        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(accent) end

        -- Flanking decorative bar-charts: dim white steps, accent "now" bar, faint baseline.
        -- They are the performance banner's art; a banner that carries its own
        -- logo (entry.logo) keeps its flanks clean instead.
        local BAR_W, BAR_GAP2 = 8, 4
        local function MakeChart(anchorSide, inset, heights, alphas)
            local groupW = #heights * BAR_W + (#heights - 1) * BAR_GAP2
            local base = card:CreateTexture(nil, "ARTWORK")
            base:SetColorTexture(1, 1, 1, 0.12)
            PP.Size(base, groupW, 1)
            if anchorSide == "LEFT" then
                PP.Point(base, "LEFT", card, "LEFT", inset, -12)
            else
                PP.Point(base, "RIGHT", card, "RIGHT", -inset, -12)
            end
            if PP.DisablePixelSnap then PP.DisablePixelSnap(base) end
            for i = 1, #heights do
                local bar = card:CreateTexture(nil, "ARTWORK")
                local a = alphas[i]
                if a == "green" then
                    bar:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
                else
                    bar:SetColorTexture(1, 1, 1, a)
                end
                PP.Size(bar, BAR_W, heights[i])
                PP.Point(bar, "BOTTOMLEFT", base, "TOPLEFT", (i - 1) * (BAR_W + BAR_GAP2), 1)
                if PP.DisablePixelSnap then PP.DisablePixelSnap(bar) end
            end
        end
        if not entry.logo then
            -- Left: cost falling to a low accent bar. Right: fps rising to a tall one.
            MakeChart("LEFT",  36, { 34, 26, 19, 13, 8 },  { 0.28, 0.23, 0.18, 0.14, "green" })
            MakeChart("RIGHT", 36, { 8, 13, 19, 26, 34 },  { 0.14, 0.18, 0.23, 0.28, "green" })
        end

        local eyebrow = MakeFont(card, 11, nil, ac.r, ac.g, ac.b, 0.9)
        PP.Point(eyebrow, "TOP", card, "TOP", 0, -18)
        eyebrow:SetJustifyH("CENTER"); eyebrow:SetWordWrap(false)
        eyebrow:SetText(EllesmereUI.L(entry.eyebrow or "SPECIAL UPDATE"))

        -- Headline: banner titles stand alone (no "Module:" prefix), rendered
        -- LARGE like popup headlines -- or a logo texture stands in for the
        -- title (entry.logo = { path, coords = {l,r,t,b}, w, h }), the way the
        -- Forever launch popup uses the Forever wordmark as its headline.
        local headline, headH
        if entry.logo then
            local lg = card:CreateTexture(nil, "ARTWORK")
            lg:SetTexture(entry.logo.path)
            local c = entry.logo.coords
            if c then lg:SetTexCoord(c[1], c[2], c[3], c[4]) end
            PP.Size(lg, entry.logo.w or 250, entry.logo.h or 100)
            PP.Point(lg, "TOP", eyebrow, "BOTTOM", 0, -8)
            headline, headH = lg, entry.logo.h or 100
        else
            local titleFs = MakeFont(card, 24, nil, 1, 1, 1, 1)
            PP.Point(titleFs, "TOP", eyebrow, "BOTTOM", 0, -8)
            titleFs:SetJustifyH("CENTER"); titleFs:SetWordWrap(false)
            titleFs:SetText(EllesmereUI.L(entry.title) or "")
            headline, headH = titleFs, 24
        end

        local descFs = MakeFont(card, 13, nil, 1, 1, 1, 0.5)
        PP.Point(descFs, "TOP", headline, "BOTTOM", 0, -10)
        PP.Point(descFs, "LEFT", card, "LEFT", 110, 0)
        PP.Point(descFs, "RIGHT", card, "RIGHT", -110, 0)
        descFs:SetJustifyH("CENTER"); descFs:SetJustifyV("TOP"); descFs:SetWordWrap(true)
        descFs:SetText(EllesmereUI.L(entry.desc) or "")

        local dh = math.ceil(descFs:GetStringHeight() or 14)
        local bh = 18 + 11 + 8 + headH + 10 + dh + 28
        PP.Size(card, w, bh)

        if entry.onClick or (entry.nav and entry.nav.module) then
            card:SetScript("OnEnter", function()
                brd:SetColor(1, 1, 1, 0.30)
                descFs:SetAlpha(0.65)
            end)
            card:SetScript("OnLeave", function()
                brd:SetColor(1, 1, 1, 0.15)
                descFs:SetAlpha(0.5)
            end)
            card:SetScript("OnClick", function()
            if entry.onClick then entry.onClick() else GoTo(entry.nav) end
        end)
        else
            card:EnableMouse(false)
        end
        return bh
    end

    -- Tier 1a: full-width VIDEO banner (entry.videoBanner = true) -- the biggest
    -- card the page renders: launch-video callouts. Same announcement chrome as
    -- the banner hero but taller type, a 3px accent, a play badge, mirrored
    -- play-glyph streams, and a read-only URL box that pre-selects itself so
    -- Ctrl+C is the only keystroke a user needs. URL: entry.url, else the
    -- shared EllesmereUI.MIDNIGHT_VIDEO_URL (EllesmereUI_VideoGuides.lua).
    local function MakeVideoBannerCard(x, cy, w, entry)
        local card = CreateFrame("Frame", nil, parent)
        -- Width FIRST (height provisional): the desc anchors L+R to the card.
        PP.Size(card, w, 200)
        PP.Point(card, "TOPLEFT", parent, "TOPLEFT", x, cy)
        card:SetFrameLevel(parent:GetFrameLevel() + 2)

        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.95)
        MakeBorder(card, 1, 1, 1, 0.18, PP)

        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(3)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(accent) end

        -- Right-pointing play triangle: collapse the right edge of a color
        -- texture to its vertical midpoint (vertex 3 = UpperRight, 4 = LowerRight).
        local function Tri(host, pw, ph, r, g, b, a)
            local t = host:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(r, g, b, a or 1)
            PP.Size(t, pw, ph)
            t:SetVertexOffset(3, 0, -ph / 2)
            t:SetVertexOffset(4, 0, ph / 2)
            return t
        end

        -- Mirrored flanking streams: three play glyphs swelling toward the text.
        local defs = { { 16, 0.10 }, { 22, 0.16 }, { 28, 0.24 } }  -- outermost -> innermost
        for _, side in ipairs({ "LEFT", "RIGHT" }) do
            local off = 40
            for i = 1, 3 do
                local sz, a = defs[i][1], defs[i][2]
                local t = Tri(card, math.floor(sz * 0.8), sz, EG.r, EG.g, EG.b, a)
                if side == "LEFT" then
                    PP.Point(t, "LEFT", card, "LEFT", off, 0)
                else
                    PP.Point(t, "RIGHT", card, "RIGHT", -off, 0)
                end
                off = off + math.floor(sz * 0.8) + 10
            end
        end

        local eyebrow = MakeFont(card, 12, nil, EG.r, EG.g, EG.b, 0.95)
        PP.Point(eyebrow, "TOP", card, "TOP", 0, -22)
        eyebrow:SetJustifyH("CENTER"); eyebrow:SetWordWrap(false)
        eyebrow:SetText(EllesmereUI.L(entry.eyebrow or "WATCH FIRST"))

        local titleFs = MakeFont(card, 30, nil, 1, 1, 1, 1)
        PP.Point(titleFs, "TOP", eyebrow, "BOTTOM", 0, -8)
        titleFs:SetJustifyH("CENTER"); titleFs:SetWordWrap(false)
        titleFs:SetText(EllesmereUI.L(entry.title) or "")

        local descFs = MakeFont(card, 13, nil, 1, 1, 1, 0.55)
        PP.Point(descFs, "TOP", titleFs, "BOTTOM", 0, -10)
        PP.Point(descFs, "LEFT", card, "LEFT", 120, 0)
        PP.Point(descFs, "RIGHT", card, "RIGHT", -120, 0)
        descFs:SetJustifyH("CENTER"); descFs:SetJustifyV("TOP"); descFs:SetWordWrap(true)
        descFs:SetText(EllesmereUI.L(entry.desc) or "")

        local url = entry.url or EllesmereUI.MIDNIGHT_VIDEO_URL or ""
        local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")

        local urlWell = CreateFrame("Frame", nil, card)
        urlWell:SetFrameLevel(card:GetFrameLevel() + 2)
        PP.Size(urlWell, 400, 36)
        PP.Point(urlWell, "TOP", descFs, "BOTTOM", 0, -16)
        local wbg = urlWell:CreateTexture(nil, "BACKGROUND")
        wbg:SetAllPoints()
        wbg:SetColorTexture(0.03, 0.045, 0.06, 1)
        -- Neutral border: the link-blue text carries the "this is the link" read.
        MakeBorder(urlWell, 1, 1, 1, 0.22, PP)

        -- Play badge standing left of the URL well (announcement-popup chip).
        local badge = CreateFrame("Frame", nil, card)
        badge:SetFrameLevel(card:GetFrameLevel() + 3)
        PP.Size(badge, 44, 44)
        PP.Point(badge, "RIGHT", urlWell, "LEFT", -16, 0)
        local chip = badge:CreateTexture(nil, "BACKGROUND")
        chip:SetAllPoints()
        chip:SetColorTexture(0.05, 0.06, 0.08, 0.95)
        MakeBorder(badge, EG.r, EG.g, EG.b, 0.85, PP)
        local btri = Tri(badge, 16, 18, 1, 1, 1, 0.95)
        PP.Point(btri, "CENTER", badge, "CENTER", 2, 0)

        -- Hint under the well; doubles as the Ctrl+C confirmation line.
        local hintFs = MakeFont(card, 11, nil, 1, 1, 1, 0.45)
        PP.Point(hintFs, "TOP", urlWell, "BOTTOM", 0, -8)
        hintFs:SetJustifyH("CENTER")
        hintFs:SetText(EllesmereUI.L("Click the link, then Ctrl+C to copy it"))

        local eb = CreateFrame("EditBox", nil, urlWell)
        eb:SetAllPoints(urlWell)
        eb:SetMultiLine(false)
        eb:SetAutoFocus(false)
        eb:SetFont(FONT, 13, "")
        eb:SetJustifyH("CENTER")
        eb:SetTextInsets(12, 12, 0, 0)
        eb:SetTextColor(0.55, 0.75, 1.0, 1)   -- link blue
        eb._readOnly = url
        eb:SetText(url)
        eb:SetCursorPosition(0)
        eb:SetScript("OnMouseUp", function(self)
            C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
        end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        -- Read-only: typing/paste/cut restore the URL and re-select.
        eb:SetScript("OnChar", function(self)
            self:SetText(self._readOnly or ""); self:HighlightText()
        end)
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(self._readOnly or ""); self:HighlightText() end
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnKeyDown", function(self, key)
            if key == "C" and IsControlKeyDown() then
                hintFs:SetText(EllesmereUI.L("Link copied - paste it into your browser"))
                hintFs:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            end
        end)

        local dh = math.ceil(descFs:GetStringHeight() or 14)
        local bh = 22 + 12 + 8 + 30 + 10 + dh + 16 + 36 + 8 + 11 + 22
        PP.Size(card, w, bh)
        return bh
    end

    -- Tier 2: clickable small listing -- title + subtitle, no card chrome, faint row highlight on hover.
    local function MakeListing(cy, w, entry)
        local ROW_H = 48
        local row = CreateFrame("Button", nil, parent)
        PP.Size(row, w, ROW_H)
        PP.Point(row, "TOPLEFT", parent, "TOPLEFT", PAD, cy)

        local hov = row:CreateTexture(nil, "BACKGROUND")
        hov:SetAllPoints()
        hov:SetColorTexture(1, 1, 1, 0.07)
        hov:SetAlpha(0)

        local titleFs = MakeFont(row, 13, nil, 1, 1, 1, 0.9)
        PP.Point(titleFs, "TOPLEFT", row, "TOPLEFT", 6, -5)
        titleFs:SetJustifyH("LEFT"); titleFs:SetWordWrap(false)
        titleFs:SetText(TitleOf(entry))

        local subFs = MakeFont(row, 11, nil, 1, 1, 1, 0.4)
        PP.Point(subFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
        PP.Point(subFs, "RIGHT", row, "RIGHT", -10, 0)
        subFs:SetJustifyH("LEFT"); subFs:SetWordWrap(false)
        subFs:SetText(EllesmereUI.L(entry.desc) or "")

        -- Clickable only with a nav target (see MakeHeroCard); else static.
        if entry.onClick or (entry.nav and entry.nav.module) then
            row:SetScript("OnEnter", function()
                hov:SetAlpha(1); titleFs:SetAlpha(1)
            end)
            row:SetScript("OnLeave", function()
                hov:SetAlpha(0); titleFs:SetAlpha(0.9)
            end)
            row:SetScript("OnClick", function()
            if entry.onClick then entry.onClick() else GoTo(entry.nav) end
        end)
        else
            row:EnableMouse(false)
        end
        return ROW_H
    end

    -- Tier 3: a plain bug-fix line (bullet + wrapping text, not clickable).
    local function MakeFixLine(cy, text)
        local dot = MakeFont(parent, 12, nil, EG.r, EG.g, EG.b, 0.55)
        PP.Point(dot, "TOPLEFT", parent, "TOPLEFT", PAD + 2, cy - 1)
        dot:SetText("\226\128\162")  -- bullet glyph (ASCII-safe UTF-8 escape)
        local fs = MakeFont(parent, 12, nil, 1, 1, 1, 0.5)
        PP.Point(fs, "TOPLEFT", parent, "TOPLEFT", PAD + 18, cy)
        PP.Point(fs, "RIGHT", parent, "RIGHT", -PAD, 0)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
        fs:SetText(text or "")
        local th = fs:GetStringHeight() or 14
        return math.max(22, math.ceil(th) + 8)
    end

    local patches = EllesmereUI._WHATSNEW_PATCHES
    if not patches or #patches == 0 then
        local none = MakeFont(parent, 13, nil, 1, 1, 1, 0.5)
        PP.Point(none, "TOPLEFT", parent, "TOPLEFT", PAD, y - 20)
        none:SetText (EllesmereUI.L("No patch notes yet."))
        return math.abs(y) + 60
    end

    -- Intro hint: centered, with 20px of breathing room above and below.
    y = y - 20
    local hint = MakeFont(parent, 14, nil, 1, 1, 1, 0.5)
    PP.Point(hint, "TOP", parent, "TOP", 0, y)
    hint:SetJustifyH("CENTER")
    hint:SetText (EllesmereUI.L("Click any new feature to go directly to the setting"))

    -- "New Patch Reminder Dot" opt-out for the pulsing sidebar dot shown when the account version increases (Patch Notes button in EllesmereUI.lua).
    do
        local BOX = 14
        local row = CreateFrame("Button", nil, parent)
        row:SetFrameLevel(parent:GetFrameLevel() + 2)
        local box = CreateFrame("Frame", nil, row)
        PP.Size(box, BOX, BOX)
        PP.Point(box, "LEFT", row, "LEFT", 0, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.075, 0.113, 0.141, 1)
        local boxBrd = MakeBorder(box, 1, 1, 1, 0.25, PP)
        local check = box:CreateTexture(nil, "ARTWORK")
        PP.Point(check, "TOPLEFT", box, "TOPLEFT", 3, -3)
        PP.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
        check:SetColorTexture(EG.r, EG.g, EG.b, 1)
        local lbl = MakeFont(row, 12, nil, 1, 1, 1, 0.5)
        PP.Point(lbl, "LEFT", box, "RIGHT", 7, 0)
        lbl:SetText(EllesmereUI.L("New Patch Reminder Dot"))
        row:SetSize(BOX + 10 + (lbl:GetStringWidth() or 130), 20)
        PP.Point(row, "TOPRIGHT", parent, "TOPRIGHT", -PAD, y + 2)
        local function Paint()
            local on = not (EllesmereUIDB and EllesmereUIDB.patchDotDisabled)
            check:SetShown(on)
            if on then
                boxBrd:SetColor(EG.r, EG.g, EG.b, 0.85)
            else
                boxBrd:SetColor(1, 1, 1, 0.25)
            end
        end
        Paint()
        row:SetScript("OnClick", function()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.patchDotDisabled = (not EllesmereUIDB.patchDotDisabled) and true or nil
            Paint()
            if EllesmereUI._UpdatePatchDot then EllesmereUI._UpdatePatchDot() end
        end)
        row:SetScript("OnEnter", function(self)
            lbl:SetAlpha(0.85)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Show a pulsing dot on the Patch Notes button whenever EllesmereUI updates to a new version."))
            end
        end)
        row:SetScript("OnLeave", function()
            lbl:SetAlpha(0.5)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
    end

    y = y - math.ceil(hint:GetStringHeight() or 14) - 20

    -- Show only the newest MAX_PATCHES entries; older ones may stay in the data table unshown.
    local MAX_PATCHES = 10
    local shown = math.min(#patches, MAX_PATCHES)
    for pi = 1, shown do
        local patch = patches[pi]
        -- A "mini" patch is bugfix-only: just a `fixes` tier, compact style.
        local isMini = patch.mini
        -- Version header: full = 20px title + divider; mini = 15px title with a green "MINI PATCH" tag + tighter divider.
        if isMini then
            local ver = MakeFont(parent, 15, nil, 1, 1, 1, 0.9)
            PP.Point(ver, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            ver:SetText("EllesmereUI " .. (patch.version or ""))
            local tag = MakeFont(parent, 10, nil, EG.r, EG.g, EG.b, 0.85)
            PP.Point(tag, "LEFT", ver, "RIGHT", 10, -1)
            tag:SetText("MINI PATCH")
            local uline = parent:CreateTexture(nil, "ARTWORK")
            uline:SetColorTexture(1, 1, 1, 0.10)
            PP.Size(uline, totalW, 1)
            PP.Point(uline, "TOPLEFT", parent, "TOPLEFT", PAD, y - 24)
            if PP.DisablePixelSnap then PP.DisablePixelSnap(uline) end
            y = y - 34
        else
            local ver = MakeFont(parent, 20, nil, 1, 1, 1, 0.95)
            PP.Point(ver, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            ver:SetText("EllesmereUI " .. (patch.version or ""))
            local uline = parent:CreateTexture(nil, "ARTWORK")
            uline:SetColorTexture(1, 1, 1, 0.12)
            PP.Size(uline, totalW, 1)
            PP.Point(uline, "TOPLEFT", parent, "TOPLEFT", PAD, y - 32)
            if PP.DisablePixelSnap then PP.DisablePixelSnap(uline) end
            y = y - 48
        end

        -- Tier 1: hero cards, two per row, AUTHORED order (not module-sorted like features/fixes) -- reorder entries in _WHATSNEW_PATCHES to reorder cards.
        local heroes = patch.heroes or {}
        if #heroes > 0 then
            local cardW = math.floor((totalW - CARD_GAP) / 2)
            local CARD_H = 96
            -- Column state: heroes flow 2/row in authored order; a `banner` hero takes a full row, breaking then resuming the flow.
            local col = 0
            for _, hero in ipairs(heroes) do
                if hero.videoBanner then
                    if col == 1 then y = y - CARD_H - CARD_GAP; col = 0 end
                    local bh = MakeVideoBannerCard(PAD, y, totalW, hero)
                    y = y - bh - CARD_GAP
                elseif hero.banner then
                    if col == 1 then y = y - CARD_H - CARD_GAP; col = 0 end
                    local bh = MakeBannerCard(PAD, y, totalW, hero)
                    y = y - bh - CARD_GAP
                else
                    local cx = PAD + col * (cardW + CARD_GAP)
                    MakeHeroCard(cx, y, cardW, CARD_H, hero)
                    col = col + 1
                    if col == 2 then y = y - CARD_H - CARD_GAP; col = 0 end
                end
            end
            if col == 1 then y = y - CARD_H - CARD_GAP end
            y = y + CARD_GAP - 18
        end

        -- Tier 2: small listings.
        local feats = SortByModule(patch.features or {})
        if #feats > 0 then
            local _, sh = W:SectionHeader(parent, "ADDITIONAL FEATURES", y); y = y - sh
            y = y - 5  -- extra spacing below the divider
            for _, f in ipairs(feats) do
                local rh = MakeListing(y, totalW, f); y = y - rh
            end
            y = y - 6
        end

        -- Tier 3: bug-fix lines. Full patches get a "BUG FIXES" header; a mini patch is entirely fixes, so no redundant section label.
        local fixes = SortByModule(patch.fixes or {})
        if #fixes > 0 then
            if not isMini then
                local _, sh = W:SectionHeader(parent, "BUG FIXES", y); y = y - sh
                y = y - 10  -- extra spacing below the divider
            end
            for _, fx in ipairs(fixes) do
                local fh = MakeFixLine(y, PrefixOf(fx) .. (EllesmereUI.L(fx.text) or "")); y = y - fh
            end
        end

        if pi < shown then
            local _, gap = W:Spacer(parent, y, 24); y = y - gap
        end
    end

    return math.abs(y) + 20
end

-------------------------------------------------------------------------------
--  EUI LEGENDS content.
--  The block between the GENERATED DONORS markers is written by the
--  update-donors.ps1 dev tool from the internal donor list: change the list
--  and rerun the tool instead of editing the block by hand.
--    season      : "spring" / "summer" / "fall" / "winter" (page accents)
--    seasonYear  : shown after the season name over the podium
--    topSeasonal : rank-ordered top three donors this season (1st, 2nd, 3rd)
--    donors      : the all-time donor wall, numbered in this order
--  The staff table below the block is edited by hand:
--    staff       : grouped team sections ({ group, members } tables)
-------------------------------------------------------------------------------
-- BEGIN GENERATED DONORS
EllesmereUI._LEGENDS = {
    season      = "fall",
    seasonYear  = "2026",
    topSeasonal = { "Lurn", "BeaKusch", "Schamicha" },
    donors = {
        "Thias", "StickyMittens", "Xeno", "Delasteve",
        "Toxik", "Lily", "Pelleas", "Kulia",
        "GamingGrammers", "Cartridgebros", "Lurn", "fizzle_crunk",
        "Tzahal", "Ani", "Venalis", "Natasi",
        "Khardi", "Quiim", "Capa", "e_luvin",
        "ccpoppin1", "Arjax", "Excelvior", "Marple_V",
        "shy_x00",
    },
}
-- END GENERATED DONORS
EllesmereUI._LEGENDS.staff = {
    { group = "Support Leads", members = {
        "Burne", "Mudd", "Kulia", "Dookie", "Lily",
    } },
    { group = "Support Team", members = {
        "Mantis", "Kned", "Zylann", "Svart", "Meza",
        "Tzahal", "Spaze", "Terrible", "Mohkan", "Groukh",
        "Freschi", "Twilight", "Bierbauch",
    } },
    { group = "Major Bugfix/Feature Contributors", members = {
        "Glyalith", "Derek", "JuJu", "Kneeul", "Kiri",
        "Stoley", "Stormspren", "Xanax", "DNL",
        "Svart", "Nnoggie",
        "Filpet96", "Snsei987", "JensBaumannDev", "Absol3m",
        "SamJin98", "RedAces", "liamcooper", "uNBEx", "natty",
        "Ricoder92", "0x963D", "Barbiero", "Lyrex", "Delasteve",
        "andybergon", "TF0rd",
    } },
    { group = "Multi-language Support Contributors", members = {
        "LoChinAn", "Crazyyoungs", "Barbiero", "Dlarge", "labrie75",
        "tenngoxars", "Shiyan66666", "Absol3m",
    } },
}

-- Seasonal accents: a palette (first entry leads, tinting the season name) and
-- the drift of the small particles around the hero head and podium. dir -1
-- falls, dir 1 rises; size/dur are {min, max} ranges; spin is total degrees.
EllesmereUI._LEGENDS_SEASONS = {
    spring = { name = "Spring", dir = -1, size = { 4, 7 }, dur = { 11, 15 }, spin = 200, alpha = 0.50,
        colors = { { 1.00, 0.70, 0.82 }, { 0.98, 0.86, 0.91 }, { 0.66, 0.88, 0.55 } } },
    summer = { name = "Summer", dir = 1, size = { 3, 4 }, dur = { 8, 11 }, spin = 45, alpha = 0.60,
        colors = { { 1.00, 0.84, 0.34 }, { 1.00, 0.64, 0.40 }, { 1.00, 0.93, 0.62 } } },
    fall   = { name = "Fall", dir = -1, size = { 5, 8 }, dur = { 10, 14 }, spin = 320, alpha = 0.55,
        colors = { { 0.96, 0.58, 0.20 }, { 0.84, 0.34, 0.15 }, { 0.98, 0.78, 0.30 }, { 0.70, 0.42, 0.18 } } },
    winter = { name = "Winter", dir = -1, size = { 3, 5 }, dur = { 12, 17 }, spin = 90, alpha = 0.60,
        colors = { { 0.72, 0.86, 1.00 }, { 0.90, 0.95, 1.00 }, { 0.62, 0.74, 0.95 } } },
}

-- Weighted pick for the options header's thanks line. Ranking = this season's
-- podium, then the rest of the all-time wall (so an empty podium falls back to
-- the all-time order). Slots 1-3 carry 50/25/15; everyone after shares 10.
local _thanksRanked, _thanksSeen = {}, {}
function EllesmereUI._PickLegendsThanks()
    local data = EllesmereUI._LEGENDS
    if not data then return nil end
    local ranked, seen = _thanksRanked, _thanksSeen
    wipe(ranked); wipe(seen)
    local top, donors = data.topSeasonal or {}, data.donors or {}
    for i = 1, #top do
        local n = top[i]
        if n and n ~= "" and not seen[n] then seen[n] = true; ranked[#ranked + 1] = n end
    end
    for i = 1, #donors do
        local n = donors[i]
        if n and n ~= "" and not seen[n] then seen[n] = true; ranked[#ranked + 1] = n end
    end
    local count = #ranked
    if count == 0 then return nil end
    local restW = count > 3 and (10 / (count - 3)) or 0
    local total = 0
    for i = 1, count do
        total = total + ((i == 1 and 50) or (i == 2 and 25) or (i == 3 and 15) or restW)
    end
    local roll = math.random() * total
    for i = 1, count do
        roll = roll - ((i == 1 and 50) or (i == 2 and 25) or (i == 3 and 15) or restW)
        if roll <= 0 then return ranked[i] end
    end
    return ranked[count]
end

-- Language-picker font: each entry is entirely one script (the CJK stock fonts
-- also cover the trailing "(Korean)"-style Latin text), so a plain per-entry
-- font from the locale system's own glyph table beats a multi-script family.
local function LP_FontFor(locale)
    local fn = EllesmereUI.LocaleGlyphFont
    return (fn and fn(locale)) or (EllesmereUI.MEDIA_PATH .. "fonts\\Expressway.TTF")
end

-- The EUI Legends page: a celebration of the donors and team. Free-form
-- chrome (no settings widgets) in the Patch Notes / Window Skins hero
-- design language: dark cards, faint borders, accent bars, alpha hierarchy.
function EllesmereUI._BuildLegendsPage(pageName, parent, yOffset)
    local PP  = EllesmereUI.PanelPP
    local EG  = EllesmereUI.ELLESMERE_GREEN
    local PAD = EllesmereUI.CONTENT_PAD
    local L   = EllesmereUI.L
    local MakeFont   = EllesmereUI.MakeFont
    local MakeBorder = EllesmereUI.MakeBorder

    parent._showRowDivider = nil

    local data   = EllesmereUI._LEGENDS or {}
    local y      = yOffset - 14
    local totalW = parent:GetWidth() - PAD * 2
    local CARD_GAP = 14
    local SEASONS = EllesmereUI._LEGENDS_SEASONS or {}
    local season  = SEASONS[data.season or ""]
    local lead    = season and season.colors[1]

    -- Podium metal palette: gold / silver / bronze.
    local METALS = {
        { r = 1.00, g = 0.80, b = 0.28 },
        { r = 0.74, g = 0.78, b = 0.84 },
        { r = 0.83, g = 0.54, b = 0.28 },
    }

    ---------------------------------------------------------------------------
    --  Hero head: title / description / flourish divider.
    ---------------------------------------------------------------------------
    local title = MakeFont(parent, 25, nil, 1, 1, 1, 1)
    PP.Point(title, "TOP", parent, "TOP", 0, y)
    title:SetText(L("EUI Legends"))

    local desc = MakeFont(parent, 15, nil, 1, 1, 1, 0.5)
    desc:SetWidth(600)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText(L("Thank you to all who support EllesmereUI and its incredible support team!"))

    -- Flourish: two faint lines meeting a green diamond dot. In season the
    -- lines warm to the season's lead colour near the dot and fade outward.
    local fy = y - 76
    local dot = parent:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
    PP.Size(dot, 5, 5)
    PP.Point(dot, "TOP", parent, "TOP", 0, fy)
    for side = -1, 1, 2 do
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.12)
        if lead then
            -- White base: the gradient's vertex colours multiply the texture.
            line:SetColorTexture(1, 1, 1, 1)
            local near = CreateColor(lead[1], lead[2], lead[3], 0.38)
            local far  = CreateColor(lead[1], lead[2], lead[3], 0.04)
            if side < 0 then
                line:SetGradient("HORIZONTAL", far, near)
            else
                line:SetGradient("HORIZONTAL", near, far)
            end
        end
        PP.Size(line, 150, 1)
        PP.Point(line, side < 0 and "RIGHT" or "LEFT", dot, side < 0 and "LEFT" or "RIGHT", side * 10, 0)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(line) end
    end
    local bandTop = y + 8
    y = fy - 28

    ---------------------------------------------------------------------------
    --  Seasonal podium: #1 center and elevated, #2 left, #3 right. A rank
    --  nobody holds yet keeps its card with a dim placeholder.
    ---------------------------------------------------------------------------
    local podiumLabel = MakeFont(parent, 13, nil, EG.r, EG.g, EG.b, 0.9)
    PP.Point(podiumLabel, "TOP", parent, "TOP", 0, y)
    local seasonText = season and ((L(season.name) .. " " .. (data.seasonYear or "")):gsub("%s+$", "")) or (data.seasonYear or "")
    if lead and seasonText ~= "" then
        seasonText = string.format("|cff%02x%02x%02x%s|r",
            math.floor(lead[1] * 255 + 0.5), math.floor(lead[2] * 255 + 0.5),
            math.floor(lead[3] * 255 + 0.5), seasonText)
    end
    podiumLabel:SetText(seasonText ~= "" and (L("Seasonal Top Donors") .. "  -  " .. seasonText) or L("Seasonal Top Donors"))
    y = y - 30

    local top3 = data.topSeasonal or {}
    local CENTER_W, CENTER_H = 200, 78
    local SIDE_W, SIDE_H     = 172, 66
    -- Sides drop exactly the height difference so all three BOTTOMS align;
    -- #1 still reads elevated purely by being taller.
    local SIDE_DROP          = CENTER_H - SIDE_H
    -- rank -> horizontal slot: #2 left, #1 center, #3 right.
    local SLOT_DX = { 0, -(CENTER_W / 2 + CARD_GAP + SIDE_W / 2), (CENTER_W / 2 + CARD_GAP + SIDE_W / 2) }
    for rank = 1, 3 do
        local name = top3[rank]
        local open = not name or name == ""
        local isFirst = (rank == 1)
        local m = METALS[rank]
        local w = isFirst and CENTER_W or SIDE_W
        local h = isFirst and CENTER_H or SIDE_H
        local card = CreateFrame("Frame", nil, parent)
        PP.Size(card, w, h)
        PP.Point(card, "TOP", parent, "TOP", SLOT_DX[rank], y - (isFirst and 0 or SIDE_DROP))
        card:SetFrameLevel(parent:GetFrameLevel() + 2)

        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.55)
        -- Soft metal wash: barely-there tint that makes each podium card
        -- read gold/silver/bronze without leaving the dark aesthetic.
        local wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetAllPoints()
        wash:SetColorTexture(m.r, m.g, m.b, isFirst and 0.07 or 0.04)
        MakeBorder(card, 1, 1, 1, isFirst and 0.16 or 0.10, PP)

        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(m.r, m.g, m.b, isFirst and 0.95 or 0.7)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(accent) end

        local rankFs = MakeFont(card, isFirst and 14 or 12, nil, m.r, m.g, m.b, 0.95)
        PP.Point(rankFs, "TOP", card, "TOP", 0, isFirst and -16 or -13)
        rankFs:SetText("#" .. rank)

        local nameFs = MakeFont(card, isFirst and 17 or 15, nil, 1, 1, 1,
            open and 0.3 or (isFirst and 1 or 0.92))
        PP.Point(nameFs, "TOP", rankFs, "BOTTOM", 0, isFirst and -10 or -8)
        PP.Point(nameFs, "LEFT", card, "LEFT", 10, 0)
        PP.Point(nameFs, "RIGHT", card, "RIGHT", -10, 0)
        nameFs:SetJustifyH("CENTER")
        nameFs:SetWordWrap(false)
        nameFs:SetText(open and L("Unclaimed") or name)
    end
    y = y - (SIDE_DROP + math.max(CENTER_H, SIDE_H + SIDE_DROP)) - 26

    ---------------------------------------------------------------------------
    --  Seasonal particles: a few small tumbling squares drifting through the
    --  side margins beside the hero head and podium (leaves in fall, snow in
    --  winter, petals in spring, rising sparks in summer). Engine animations
    --  on a host that plays them only while the page is visible.
    ---------------------------------------------------------------------------
    if season then
        local bandBot = y + 14
        local bandH   = bandTop - bandBot
        -- Side margin: outside the centred description (600) and podium.
        local marginW = math.max(60, (totalW - 600) / 2)
        local fx = CreateFrame("Frame", nil, parent)
        fx:SetAllPoints(parent)
        fx:SetFrameLevel(parent:GetFrameLevel() + 1)
        local groups = {}
        -- x: 0..1 across the margin; y: start depth into the band; s/d: 0..1
        -- picks within the season's size/duration ranges; w: idle seconds
        -- before each pass (also staggers the first pass).
        local SLOTS = {
            { x = 0.18, y = 0,  s = 0.6, d = 0.2, w = 0.0 },
            { x = 0.58, y = 26, s = 0.2, d = 0.7, w = 2.6 },
            { x = 0.86, y = 8,  s = 0.9, d = 0.4, w = 5.2 },
            { x = 0.38, y = 52, s = 0.4, d = 0.9, w = 1.3 },
            { x = 0.72, y = 40, s = 0.7, d = 0.1, w = 6.4 },
            { x = 0.06, y = 70, s = 0.3, d = 0.5, w = 3.9 },
        }
        local nColors = #season.colors
        local idx = 0
        for side = 1, 2 do
            for i = 1, #SLOTS do
                idx = idx + 1
                local sl = SLOTS[i]
                local xf = (side == 1) and sl.x or (1 - sl.x)
                local df = (side == 1) and sl.d or (1 - sl.d)
                local size = season.size[1] + (season.size[2] - season.size[1]) * sl.s
                local dur  = season.dur[1] + (season.dur[2] - season.dur[1]) * df
                local wait = sl.w + (side == 2 and 1.7 or 0)
                local travel = math.max(40, bandH - sl.y - 10)
                local x0 = (side == 1) and (PAD + 8 + xf * (marginW - 24))
                                       or (PAD + totalW - marginW + 16 + xf * (marginW - 24))
                local c = season.colors[(idx - 1) % nColors + 1]

                local leaf = fx:CreateTexture(nil, "ARTWORK")
                leaf:SetColorTexture(c[1], c[2], c[3], 1)
                PP.Size(leaf, size, size)
                if season.dir < 0 then
                    PP.Point(leaf, "TOP", parent, "TOPLEFT", x0, bandTop - sl.y)
                else
                    PP.Point(leaf, "BOTTOM", parent, "TOPLEFT", x0, bandBot + sl.y)
                end
                leaf:SetAlpha(0)

                local ag = leaf:CreateAnimationGroup()
                ag:SetLooping("REPEAT")
                local sway = (idx % 2 == 0) and 10 or -10
                local drift = ag:CreateAnimation("Translation")
                drift:SetOffset(sway * 0.6, season.dir * travel)
                drift:SetDuration(dur); drift:SetStartDelay(wait); drift:SetSmoothing("NONE")
                local swayOut = ag:CreateAnimation("Translation")
                swayOut:SetOffset(sway, 0)
                swayOut:SetDuration(dur / 2); swayOut:SetStartDelay(wait); swayOut:SetSmoothing("IN_OUT")
                local swayBack = ag:CreateAnimation("Translation")
                swayBack:SetOffset(-sway, 0)
                swayBack:SetDuration(dur / 2); swayBack:SetStartDelay(wait + dur / 2); swayBack:SetSmoothing("IN_OUT")
                local spin = ag:CreateAnimation("Rotation")
                spin:SetDegrees((idx % 3 == 0) and -season.spin or season.spin)
                spin:SetDuration(dur); spin:SetStartDelay(wait)
                -- Back-to-back alpha steps (in, hold, out) so one is always
                -- driving the alpha for the whole pass; idle waits sit at the
                -- texture's own alpha of 0.
                local fadeIn = ag:CreateAnimation("Alpha")
                fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(season.alpha)
                fadeIn:SetDuration(dur * 0.2); fadeIn:SetStartDelay(wait)
                local hold = ag:CreateAnimation("Alpha")
                hold:SetFromAlpha(season.alpha); hold:SetToAlpha(season.alpha)
                hold:SetDuration(dur * 0.45); hold:SetStartDelay(wait + dur * 0.2)
                local fadeOut = ag:CreateAnimation("Alpha")
                fadeOut:SetFromAlpha(season.alpha); fadeOut:SetToAlpha(0)
                fadeOut:SetDuration(dur * 0.35); fadeOut:SetStartDelay(wait + dur * 0.65)
                groups[#groups + 1] = ag
            end
        end
        fx:SetScript("OnShow", function()
            for i = 1, #groups do groups[i]:Play() end
        end)
        fx:SetScript("OnHide", function()
            for i = 1, #groups do groups[i]:Stop() end
        end)
        if fx:IsVisible() then
            for i = 1, #groups do groups[i]:Play() end
        end
    end

    ---------------------------------------------------------------------------
    --  The walls: all-time donors (left) and the team (right). FIXED height from
    --  the page budget; the name lists scroll INSIDE each card with smooth
    --  wheel scrolling and the thin custom thumb (the sidebar-nav pattern),
    --  so the page itself never scrolls.
    ---------------------------------------------------------------------------
    local colW = (totalW - CARD_GAP) / 2
    -- FIXED wall height (the Export Profile addon-list pattern: a constant
    -- clip height, the list scrolls inside it) so the page itself always
    -- fits the panel and never scrolls.
    local wallH = 330

    local WALL_STEP, WALL_SPEED = 48, 12
    local function MakeWall(x, headerText, subText)
        local card = CreateFrame("Frame", nil, parent)
        card:SetFrameLevel(parent:GetFrameLevel() + 2)
        PP.Size(card, colW, wallH)
        PP.Point(card, "TOPLEFT", parent, "TOPLEFT", x, y)
        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        MakeBorder(card, 1, 1, 1, 0.12, PP)
        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(EG.r, EG.g, EG.b, 0.6)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(accent) end

        local header = MakeFont(card, 13, nil, EG.r, EG.g, EG.b, 0.9)
        PP.Point(header, "TOPLEFT", card, "TOPLEFT", 16, -16)
        header:SetText(headerText)
        -- Optional small grey qualifier after the header on its baseline.
        if subText then
            local sub = MakeFont(card, 11, nil, 1, 1, 1, 0.4)
            PP.Point(sub, "BOTTOMLEFT", header, "BOTTOMRIGHT", 6, 0)
            sub:SetText(subText)
        end

        local div = card:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.08)
        PP.Point(div, "TOPLEFT", card, "TOPLEFT", 16, -38)
        PP.Point(div, "TOPRIGHT", card, "TOPRIGHT", -16, -38)
        div:SetHeight(1)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(div) end

        -- Clipped list viewport under the header.
        local sf = CreateFrame("ScrollFrame", nil, card)
        PP.Point(sf, "TOPLEFT", card, "TOPLEFT", 0, -46)
        PP.Point(sf, "BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 8)
        sf:SetClipsChildren(true)
        sf:EnableMouseWheel(true)
        sf:SetFrameLevel(card:GetFrameLevel() + 1)
        local child = CreateFrame("Frame", nil, sf)
        child:SetWidth(colW)
        child:SetHeight(1)
        sf:SetScrollChild(child)

        -- Thin custom scrollbar on the card's right edge.
        local track = CreateFrame("Frame", nil, card)
        track:SetWidth(3)
        PP.Point(track, "TOPRIGHT", sf, "TOPRIGHT", -3, -2)
        PP.Point(track, "BOTTOMRIGHT", sf, "BOTTOMRIGHT", -3, 2)
        track:SetFrameLevel(sf:GetFrameLevel() + 3)
        local tbg = track:CreateTexture(nil, "BACKGROUND")
        tbg:SetAllPoints()
        tbg:SetColorTexture(1, 1, 1, 0.03)
        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.25)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)
        thumb:SetWidth(3)
        thumb:SetHeight(40)

        local function UpdateThumb()
            local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(sf) or 0
            if maxScroll <= 0 then track:Hide(); return end
            track:Show()
            local trackH = track:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(24, trackH * ratio)
            thumb:SetHeight(thumbH)
            local sr = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(sr * (trackH - thumbH)))
        end

        -- Smooth wheel scroll: lerp towards a pixel-snapped target (the
        -- sidebar-nav recipe; snapping keeps glyphs off sub-pixel rows).
        local target, smoothing = 0, false
        local smoother = CreateFrame("Frame", nil, card)
        smoother:Hide()
        smoother:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(sf) or 0
            local scale = sf:GetEffectiveScale()
            maxScroll = math.floor(maxScroll * scale) / scale
            target = math.max(0, math.min(maxScroll, target))
            local diff = target - cur
            if math.abs(diff) < 0.3 then
                sf:SetVerticalScroll(target)
                UpdateThumb()
                smoothing = false
                smoother:Hide()
                return
            end
            local stepTo = cur + diff * math.min(1, WALL_SPEED * elapsed)
            stepTo = math.max(0, math.min(maxScroll, stepTo))
            if diff > 0 then
                stepTo = math.ceil(stepTo * scale) / scale
            else
                stepTo = math.floor(stepTo * scale) / scale
            end
            sf:SetVerticalScroll(math.max(0, math.min(maxScroll, stepTo)))
            UpdateThumb()
        end)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(self) or 0
            if maxScroll <= 0 then return end
            local scale = self:GetEffectiveScale()
            maxScroll = math.floor(maxScroll * scale) / scale
            local base = smoothing and target or self:GetVerticalScroll()
            local t = math.max(0, math.min(maxScroll, base - delta * WALL_STEP))
            t = math.floor(t * scale + 0.5) / scale
            target = math.min(t, maxScroll)
            if not smoothing then
                smoothing = true
                smoother:Show()
            end
        end)
        sf:SetScript("OnScrollRangeChanged", UpdateThumb)

        return child, function(contentH)
            child:SetHeight(math.max(contentH, 1))
            UpdateThumb()
        end
    end

    -- Left wall: every donor, numbered in all-time order on alternating row
    -- strips (ranks 1-3 take the podium metals on number and name, the rest
    -- an accent number and a white name).
    local donors = data.donors or {}
    local donorList, donorFin = MakeWall(PAD, L("ALL-TIME DONORS"), L("($100 or more)"))
    local DONOR_ROW_H = 24
    for i = 1, #donors do
        local rowF = CreateFrame("Frame", nil, donorList)
        rowF:SetSize(colW, DONOR_ROW_H)
        rowF:SetPoint("TOPLEFT", donorList, "TOPLEFT", 0, -(i - 1) * DONOR_ROW_H)
        local rbg = rowF:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.12 or 0.06)
        local m = METALS[i]
        local nameFs = MakeFont(rowF, 14, nil, m and m.r or 1, m and m.g or 1, m and m.b or 1, m and 0.95 or 0.85)
        PP.Point(nameFs, "LEFT", rowF, "LEFT", 40, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetText(donors[i])
        local numFs = MakeFont(rowF, 12, nil, m and m.r or EG.r, m and m.g or EG.g, m and m.b or EG.b, m and 0.95 or 0.8)
        PP.Point(numFs, "RIGHT", nameFs, "LEFT", -8, 0)
        numFs:SetJustifyH("RIGHT")
        numFs:SetText(i .. ".")
    end
    donorFin(#donors * DONOR_ROW_H)

    -- Right wall: the team, grouped by role section (green group header,
    -- then dot-bulleted member rows on alternating strips, as the donors).
    local staff = data.staff or {}
    local staffList, staffFin = MakeWall(PAD + colW + CARD_GAP, L("EUI STAFF"))
    local STAFF_ROW_H = 22
    local sy = 0
    for gi = 1, #staff do
        local grp = staff[gi]
        if gi > 1 then sy = sy - 10 end
        local hdr = MakeFont(staffList, 12, nil, EG.r, EG.g, EG.b, 0.9)
        PP.Point(hdr, "TOPLEFT", staffList, "TOPLEFT", 16, sy - 8)
        hdr:SetJustifyH("LEFT")
        hdr:SetText(L(grp.group or ""))
        sy = sy - 28
        local members = grp.members or {}
        for i = 1, #members do
            local rowF = CreateFrame("Frame", nil, staffList)
            rowF:SetSize(colW, STAFF_ROW_H)
            rowF:SetPoint("TOPLEFT", staffList, "TOPLEFT", 0, sy)
            local rbg = rowF:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            rbg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.12 or 0.06)
            local nameFs = MakeFont(rowF, 14, nil, 1, 1, 1, 0.9)
            PP.Point(nameFs, "LEFT", rowF, "LEFT", 34, 0)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetText(members[i])
            local bdot = rowF:CreateTexture(nil, "OVERLAY")
            bdot:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            PP.Size(bdot, 4, 4)
            PP.Point(bdot, "RIGHT", nameFs, "LEFT", -10, 0)
            sy = sy - STAFF_ROW_H
        end
    end
    staffFin(math.abs(sy) + 6)

    y = y - wallH - 18

    local footer = MakeFont(parent, 12, nil, 1, 1, 1, 0.35)
    PP.Point(footer, "TOP", parent, "TOP", 0, y)
    footer:SetText(L("Thank you for making EllesmereUI possible."))
    y = y - 22

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Patch-notes content for the What's New page (newest first). Entry `nav`
--  deep-links via NavigateToElementSettings(module, page, section, preSelect, highlight).
-------------------------------------------------------------------------------
EllesmereUI._WHATSNEW_PATCHES = {
    {
        version = "9.2.5",
        heroes = {
            {
                module = "General",
                title  = "Classic WoW UI Style",
                desc   = "Vanilla WoW art joins EllesmereUI Style and Blizzard Style as a third look, keeping EllesmereUI's features. Raid Frames, Chat, Quest Tracker, Friends List and the Character Sheet gain the stock looks too; pick per module or for the whole UI under Global Settings > Style.",
                nav    = { module = "_EUIGlobal", page = "Style", section = "MODULE STYLES", highlight = "" },
            },
            {
                module = "General",
                title  = "Pixel-Exact Borders",
                desc   = "Border Size is now an exact pixel slider across the suite, so Shadow, Glow and Blizzard borders take any size. Width and Height Match now line up by the visible border edge, so an existing match to a textured border may resize slightly.",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "ICONS", highlight = "Border Size",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
            {
                module = "Raid Frames",
                title  = "Party Frame Portraits",
                desc   = "Party frames can show a 2D or 3D portrait or class art in seven sets, attached beside the bars or detached from the frame. Off by default on the Party tab and works with every style; Detached adds seven shapes, and 3D can also sit inside the frame.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Party", section = "PORTRAIT", highlight = "Portrait Mode" },
            },
            {
                -- Static card: the Travel page only exists on WoW Forever.
                forever = true,
                module = "QoL",
                title  = "Flight Timer",
                desc   = "A flight path bar that names your destination and counts down the time left, from the route's length, Frequent Flier and a flight speed refined by each flight. Off by default on the new Travel tab, with size, texture, border, fill colour, text and font options plus Unlock Mode placement.",
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Button Text Position",
                desc   = "Place keybind, charges and macro name text at any corner or edge of the button from the Text cogs",
                -- The Position dropdowns live in the Text cogs; land on their owning row.
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "TEXT", highlight = "Keybind Text Size",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
            {
                -- Use Letters lives in this row's cog.
                module = "Chat",
                title  = "Channel Numbers",
                desc   = "Shortened Channel Names shows world channels as numbers like [2]; Use Letters in its cog keeps [T]",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "EXTRAS", highlight = "Shortened Channel Names" },
            },
            {
                -- Static card: Unlock Mode has no options page.
                module = "General",
                title  = "Extra Width and Height",
                desc   = "Nudge a Width or Height Match by a few pixels from the Unlock Mode cog without breaking the link",
            },
            {
                module = "General",
                title  = "New Options Theme Art",
                desc   = "The EllesmereUI theme has new background art; the previous art stays available as EllesmereUI Original",
                nav    = { module = "_EUIGlobal", page = "General",
                           section = "DISPLAY", highlight = "EUI Options Theme" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Show Current Pull in Bar",
                desc   = "The enemy forces bar previews the forces the pull you are fighting will add; off by default",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer",
                           section = "FORCES", highlight = "Show Current Pull in Bar" },
            },
            {
                module = "Party Mode",
                title  = "Level Up Trigger",
                desc   = "Start a Party Mode celebration automatically every time you gain a level",
                nav    = { module = "EllesmereUIPartyMode", page = "Party Mode",
                           section = "CELEBRATION TRIGGERS", highlight = "Level Up" },
            },
            {
                module = "QoL",
                title  = "Grey Out Unavailable Icons",
                desc   = "Battle Res and Bloodlust icons grey out with no charges or while Sated; on by default, with an off switch in each cog",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "BATTLE RES", highlight = "Display Style" },
            },
            {
                -- Page only: the Show In picker sits in each indicator's card.
                module = "Raid Frames",
                title  = "Indicator Show In",
                desc   = "Limit a Buff Manager indicator to raid frames or party frames only",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager" },
            },
            {
                -- The toggle lives in the Absorb Rendering cog on this row.
                module = "Raid Frames",
                title  = "Blizzard Glow Line",
                desc   = "Add the Default Blizz Frames shield glow line to any absorb style from the Absorb Rendering cog",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "ABSORBS", highlight = "Absorb Style" },
            },
            {
                -- Dispel toggle: the Dispel Border cog on this row; the aggro one sits in the
                -- Threat Borders cog (HEALTH BAR, same page).
                module = "Raid Frames",
                title  = "Color Custom Borders",
                desc   = "Tint your custom frame border in the dispel type color, or red on aggro, instead of a second border",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "DISPELS", highlight = "Frame Border" },
            },
            {
                -- Prioritize Class and Class Order live in the Sort By cog.
                module = "Raid Frames",
                title  = "Raid Class Sorting",
                desc   = "Sort raid frames by class inside Group or Role order with your own Class Order, from the Sort By cog",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "LAYOUT", highlight = "Sort By" },
            },
            {
                -- The FrameSort choice appears in Sort By only while that addon is enabled.
                module = "Raid Frames",
                title  = "FrameSort Support",
                desc   = "Sort By offers FrameSort while that addon is enabled, so party and raid frames follow its order",
                nav    = { module = "EllesmereUIRaidFrames", page = "Party", section = "FRAMES", highlight = "Sort By" },
            },
            {
                module = "Resource Bars",
                title  = "Border Around All",
                desc   = "Under a Blizzard or Classic style, frame the stacked health, power and class resource bars as one group",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "BAR DISPLAY", highlight = "Border Around All" },
            },
            {
                module = "Resource Bars",
                title  = "Choose Texture Per Bar",
                desc   = "Give the health and power bars their own textures from the Texture cog",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "BAR DISPLAY", highlight = "Texture" },
            },
            {
                module = "Resource Bars",
                title  = "Blizzard Class Resource Art",
                desc   = "Show Blizzard's own class resource frame, such as Holy Power or Runes, in the class resource bar's place",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars",
                           section = "BAR DISPLAY", highlight = "Blizzard Class Resource Art" },
            },
            {
                module = "Unit & Raid Frames",
                title  = "Match All Debuff Filters",
                desc   = "Raid, party and player frame debuff filters and Player Aura Bars can require every checked filter to match",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "BUFFS AND DEBUFFS", highlight = "Player Debuff Filter",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
            {
                module = "Unit Frames",
                title  = "Blizz Colored Target Header",
                desc   = "Turn off the reaction color behind the target's name on the Blizzard Style target frame",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Blizz Colored Target Header",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("target"); EllesmereUI._pendingUnitSelect = "target" end },
            },
            {
                module = "Unit Frames",
                title  = "Cast Bar Texture",
                desc   = "Give cast bars their own texture or Blizzard's fill from Global Settings > Textures",
                -- Texture cards register their header as display .. " " .. desc
                -- (EUI_Textures_Options.lua BuildTexCard); renaming either breaks this link.
                nav    = { module = "_EUIGlobal", page = "Textures",
                           section = "Unit Frames Bar and absorb textures for the main frames", highlight = "Cast Bar Texture" },
            },
            {
                -- The toggle lives in the Visibility row's cog.
                module = "Unit Frames",
                title  = "Show When Health Missing",
                desc   = "Keep the player, target or focus frame visible while that unit is hurt, from the Visibility cog",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Visibility",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "The XP, Reputation and House Favor bars no longer show a tooltip while Click Through is on; turn Click Through off to keep the tooltip." },
            { module = "Action Bars", text = "Mouseover fades no longer cause Lua errors when another addon also fades your action bars." },
            { forever = true, module = "Action Bars", text = "Bars now act on key release so shift-dragging a spell or item off a bar picks it up instead of using it, and Cast Actions on Key Down shows as unavailable." },
            { forever = true, module = "Action Bars", text = "Removing EllesmereUI no longer leaves Blizzard's action bars 2 to 8 hidden, and an update to its Edit Mode layout no longer moves a character off a layout of its own." },
            { module = "Action Bars", text = "Icon Size and Unlock Mode size matching now work with Blizzard and Classic style action bars, and a Custom Button Shape picked under EllesmereUI Style no longer changes their size or click area." },
            { module = "Aura Buff Reminders", text = "The Augment Rune reminder now recognizes the Tidesworn Augment Rune (China region)." },
            { module = "Bags", text = "The bag window no longer opens empty during combat after a /reload in combat." },
            { module = "Blizz UI Enhanced", text = "Raid leaders no longer get Lua errors from the Group Finder applicant list, which now keeps Blizzard's own look." },
            { module = "Blizz UI Enhanced", text = "The character sheet's Equipment tab now shows Blizzard's own Equipment Manager in place of the custom Gear Sets panel, so item flyouts offer Ignore This Slot for the selected set." },
            { module = "Blizz UI Enhanced", text = "The socket strip now also shows on the Blizzard and Classic character sheets, as a tab at the bottom right." },
            { module = "Blizz UI Enhanced", text = "Turning off a single addon under Third-Party Addons now keeps that addon's skin off after the reload." },
            { forever = true, module = "Blizz UI Enhanced", text = "The inspect window is now skinned instead of showing Lua errors." },
            { module = "Chat", text = "With Hide Borders on, the sidebar divider no longer comes back after a sidebar setting changes or a profile switch." },
            { module = "Chat", text = "Changing Sidebar Visibility now takes full effect right away instead of after a reload." },
            { module = "Cooldown Manager", text = "Custom aura buff icons on a cursor-anchored bar no longer block mouseover casts when Show Tooltip is on." },
            { module = "Cooldown Manager", text = "The spell settings menu for a buff hosted on a cooldown bar now shows the values that buff actually uses." },
            { module = "Cooldown Manager", text = "Cooldown bars now rebuild when a server hotfix changes the cooldown tables, so icons no longer go missing until a talent change or reload." },
            { module = "Cooldown Manager", text = "The Show Charges checkbox in the Essential and Utility Custom Spell ID popup no longer goes missing after a buff bar's Custom Spell ID is opened first." },
            { module = "Damage Meters", text = "Spell icons show in the spell breakdown during combat again." },
            { module = "Friends", text = "Auto-Accept Friend Invites and its guild invite option now work with Blizzard's new Social window too." },
            { module = "General", text = "Textured borders, and the borders around unit frame and resource bar fills, now draw the same thickness on all four sides at every UI scale." },
            { module = "General", text = "Custom border Width Offset and Height Offset sliders now go from -25 to +25." },
            { module = "General", text = "Switching a module from Blizzard Style to Classic WoW UI and then back to EllesmereUI Style now restores your own minimap placement, meter background opacity and resource bar textures." },
            { module = "Mythic+ Tools", text = "The Targeted Spell Bars border now draws at the size its Border Size slider shows at every UI scale." },
            { module = "Party Mode", text = "Reloading or logging out during an automatic celebration no longer leaves the celebration stuck on at the next login." },
            { forever = true, module = "Party Mode", text = "Celebration Triggers now lists only the triggers that can fire, dropping the keystone, Mythic 0, rated PvP and boss kill options." },
            { module = "Player Aura Bars", text = "Bars anchored to another element in Unlock Mode stay on it after a reload, spec or talent switch instead of jumping back to an old position." },
            { module = "QoL", text = "The Bloodlust Tracker's active-lust swipe now starts bright and darkens as the buff runs out, and the icon keeps its border while the buff shows." },
            { module = "QoL", text = "The Raid Tools marker bar works in dungeons, raids and Mythic+ again after a Blizzard change; there, Quick Fire places markers in order and starts over at Star in each new instance." },
            { module = "Quickdraw", text = "Menus with world marker entries open again in dungeons, raids and Mythic+ after a Blizzard change, and their placed-marker pips stay accurate." },
            { module = "Raid Frames", text = "Boss, Role, Important and Can Apply debuffs now show on Friendly Boss frames and other units you cannot assist instead of staying hidden." },
            { module = "Raid Frames", text = "The Extra Frames Auto Resize Indicators option can be switched back on after being turned off." },
            { module = "Raid Frames", text = "Default Blizz Frames is listed right after None in the absorb style dropdowns, and its preview matches the in-game look." },
            { module = "Raid Frames", text = "Debuff and dispel settings changed while solo or in a party now take effect on your raid frames when you join a raid." },
            { module = "Raid Frames", text = "Border layering is more reliable: party frames with their own Show Behind setting and Friendly Boss frames layer correctly, and textured hover and target borders draw above neighbouring frames." },
            { module = "Raid Frames", text = "Changing Sort By in a raid no longer shows groups hidden in Show Groups." },
            { module = "Resource Bars", text = "Under Blizzard Style, vertical bars now keep an even, thin frame instead of a stretched one that slid under the fill." },
            { module = "Spec Overrides", text = "Deleting a conditional override no longer leaves a setting that had no value of its own holding a placeholder value." },
            { module = "Unit & Raid Frames", text = "A debuff that matches more than one filter, such as Important and Non-Player, no longer shows more than once." },
            { module = "Unit Frames", text = "Width and Height Matches to a unit frame, such as a cast bar matched to the player frame, no longer disappear when Unlock Mode opens under Blizzard Style." },
            { module = "Unit Frames", text = "A frame or cast bar that is turned off, or set to another Frame Source, keeps its Unlock Mode anchor and size match for when it comes back." },
            { module = "Unit Frames", text = "On a friendly target or focus, debuff Tracked Auras no longer let every debuff through, often twice; they filter only on units you cannot assist, and Only Tracked Auras shows debuffs cast by players there." },
            { module = "Unit Frames", text = "The portrait Size slider now goes down to -50." },
            { module = "Unit Frames & Nameplates", text = "Units tagged by another player now show the Tapped color on unit frames, and nameplates switch to it the moment the tag happens." },
            { module = "Unit Frames & Nameplates", text = "Under Blizzard Style, nameplates switch once to the Blizzard bar texture and the player frame's combat indicator to the Dungeoneer icon on its portrait; switching back to the EllesmereUI look restores your picks." },
            { module = "Localization", text = "German translations were expanded and corrected throughout, and Korean, Brazilian Portuguese and Traditional Chinese caught up on the latest strings." },
        },
    },
    {
        version = "9.2.2",
        heroes = {},
        features = {
            {
                -- Static card: Unlock Mode has no options page.
                module = "General",
                title  = "Anchor Offsets and Corner Anchors",
                desc   = "Type an anchored element's X and Y offset in its Unlock Mode cog menu, and anchor cooldown or action bars to a target's corner with the matching grow direction",
            },
            {
                module = "Mythic+ Tools",
                title  = "Fastest Run Splits",
                desc   = "Compare your splits against your fastest completed run instead of your best individual splits",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer",
                           section = "BOSS OBJECTIVES", highlight = "Fastest Run Splits" },
            },
            {
                -- Static card: the page only exists on WoW Forever.
                forever = true,
                module = "Resource Bars",
                title  = "Swing Timer",
                desc   = "The swing timer is now a Resource Bars bar with anchoring, visibility rules, textures, borders, range dimming and queued-attack colour; off by default",
            },
        },
        fixes = {
            { module = "Action Bars", text = "Inside dungeons and raids, changing an action slot or reloading no longer logs cooldown errors, and empower keybinds keep Hold-and-Release after a reload or talent change there." },
            { forever = true, module = "Action Bars", text = "Action Bar 1 keybinds now fire the button they show while in a stance, form or stealth." },
            { forever = true, module = "Action Bars", text = "Reloading or opening Edit Mode no longer shows a blocked-action error on the main action bar." },
            { module = "Aura Buff Reminders & Mythic+ Tools", text = "Sections and Targeted Spell Bars limited to specific content no longer show inside Lairs, and Lair is a new Where to Show choice." },
            { module = "Blizz UI Enhanced", text = "The Choose Your Roles sign-up dialog is skinned whenever the Queue Popup skin is on, as the option already said." },
            { forever = true, module = "Blizz UI Enhanced", text = "The character sheet's ammo slot is skinned like the other slots." },
            { module = "Cooldown Manager", text = "The spell picker now opens on a bar whose Blizzard list is empty, so custom spell and item IDs and the presets can still be added." },
            { module = "DataBars & Damage Meters", text = "The social tooltip no longer errors on a cross-faction Battle.net friend, and the damage breakdown no longer errors on spells from players outside your group." },
            { module = "Minimap", text = "The Tracking button is shown by default; turn it off under Show Blizzard Elements." },
            { forever = true, module = "Nameplates", text = "Replace Quest Icon with Objective is on by default." },
            { forever = true, module = "Nameplates", text = "The class resource shows combo points on the target's nameplate for rogues and druids, follows the current target, and starts at a larger size." },
            { forever = true, module = "Resource Bars", text = "The Power Bar now tracks the resource the class actually uses, so hunters read mana." },
            { module = "Unit Frames", text = "Health text at a Y offset of 0 now sits exactly on the bar's centre, matching the options preview." },
            { module = "Unit Frames", text = "Name > Target text colours a boss's target by class again in instanced content, and updates the moment a unit's target changes." },
            { forever = true, module = "Unit Frames", text = "Combo points show on the player frame, and the classic combo point art no longer floats beside the frame." },
            { module = "Localization", text = "More Korean and Traditional Chinese translations: module style cards, Run Summary, Swing Timer, chat bubbles, Rotation Assist and the launch popup." },
        },
    },
    {
        version = "9.2.1",
        heroes = {
            {
                -- Full-width banner card (banner = true, see MakeBannerCard) above
                -- the hero cards: the Forever wordmark stands in for the title and
                -- the Forever theme's bronze replaces the accent. Static.
                banner  = true,
                accent  = { r = 220 / 255, g = 167 / 255, b = 127 / 255 },
                eyebrow = "NOW ON WOW FOREVER",
                title   = "EllesmereUI Forever",
                logo    = { path = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-forever-logo.png",
                            coords = { 12 / 384, 377 / 384, 64 / 256, 210 / 256 }, w = 250, h = 100 },
                desc    = "Everything from retail, ported to WoW Forever and tuned for the vanilla client, with a clean base layout the moment you log in. One EllesmereUI: the same install runs on either game.",
            },
            {
                module = "General",
                title  = "Blizzard Style",
                desc   = "Give any module the default Blizzard look while keeping EllesmereUI features and customization: Unit Frames, Auras, Nameplates, CDM, Resource Bars, Minimap and Damage Meters all join the Action Bars, each with its own switch under Global Settings > Style.",
                nav    = { module = "_EUIGlobal", page = "Style", section = "MODULE STYLES", highlight = "" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Run Summary",
                desc   = "An end-of-key overview of your group with one row per member: spec, item level, score and score gain, loot, damage, damage taken, interrupts and deaths, sortable by column. Off by default; a per-character run history keeps your recent keys, and /ov reopens the panel.",
                nav    = { module = "EllesmereUIMythicTimer", page = "Run Summary",
                           section = "RUN SUMMARY", highlight = "Enable Run Summary" },
            },
        },
        features = {
            {
                -- Static card: Unlock Mode has no options page.
                module = "General",
                title  = "Screen Edge Anchors",
                desc   = "Anchor an element to a screen edge in Unlock Mode so it holds its edge distance across resolutions and UI scales",
            },
            {
                module = "General",
                title  = "EllesmereUI Forever Theme",
                desc   = "A new options panel theme in soft bronze, the default on WoW Forever and available on retail from the EUI Options Theme dropdown",
                nav    = { module = "_EUIGlobal", page = "General",
                           section = "DISPLAY", highlight = "EUI Options Theme" },
            },
            {
                module = "Damage Meters",
                title  = "Unsafe Refresh Rate",
                desc   = "A cog beside Refresh Rate unlocks refresh rates down to 0.2 seconds",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters",
                           section = "DISPLAY", highlight = "Refresh Rate" },
            },
            {
                module = "Bags",
                title  = "Currency Icons in Pickers",
                desc   = "The Enabled Currencies picker now shows each currency's icon",
                nav    = { module = "EllesmereUIBags", page = "Bags",
                           section = "DISPLAY", highlight = "Enabled Currencies" },
            },
            {
                -- Static card: the page only exists on WoW Forever.
                module = "Quality of Life",
                title  = "Swing Timer (WoW Forever)",
                desc   = "Main-hand, off-hand and ranged swing bars driven by the Forever client's own swing event, with queued-attack highlighting and Unlock Mode placement; off by default",
            },
        },
        fixes = {
            { module = "Aura Buff Reminders", text = "The main-hand weapon enchant reminder no longer disappears when only the off-hand is enchanted." },
            { module = "Aura Buff Reminders", text = "Feast of Knowledge and Hearty Feast of Knowledge are now offered by the food reminder." },
            { module = "Bags", text = "Crafted Hero and Myth gear now shows its track colour and sorts with that track instead of falling back to the rarity colour." },
            { module = "Blizz UI Enhanced", text = "Socket icons on the character sheet now follow the sheet's equipment slot order." },
            { module = "Blizz UI Enhanced", text = "The character sheet's socket strip now pages instead of overflowing the sheet when many gems are equipped." },
            { module = "Blizz UI Enhanced", text = "The role check popup's Accept and Decline buttons now match the skin." },
            { module = "Chat", text = "The tab layout and tab border disabled tooltips now state the correct requirement." },
            { module = "Chat", text = "The Edit Box Font Size slider now starts from the chat window's current size instead of 12." },
            { module = "Cooldown Manager", text = "A removed custom spell's Custom Active State no longer hides or overlays the same spell when it is tracked normally." },
            { module = "Cooldown Manager", text = "Custom Icon now applies to custom aura buffs on Buffs bars." },
            { module = "Cooldown Manager", text = "When a spell is bound on more than one action bar, the keybind label shows the lowest-numbered bar's key." },
            { module = "Cooldown Manager", text = "The button settings tip no longer lingers on other pages after you leave the CDM Bars page." },
            { module = "Damage Meters", text = "Bar Height and Spell History icon and bar sizes now scale with the UI like the rest of the window, so a shared profile shows the same proportions for everyone." },
            { module = "Damage Meters", text = "The mode picker no longer opens with collapsed cards on a window placed by a screen or element anchor, and it re-flows when the window is resized." },
            { module = "General", text = "The Instances visibility option now applies in battlegrounds and arenas." },
            { module = "General", text = "Escape closes the Great Vault window reliably from both the minimap and data bar shortcuts." },
            { module = "General", text = "In Unlock Mode, an element moved by its anchor cascade no longer jumps to the screen centre after its anchor link is removed." },
            { module = "General", text = "Reset All no longer leaves the character sheet on Blizzard's default look." },
            { module = "Minimap", text = "A lone addon button now shows on the map by itself; the group button only appears once a second button joins it." },
            { module = "Nameplates", text = "Friendly name-only player names now show an outline on the Classic nameplate style, matching the other styles." },
            { module = "Player Aura Bars", text = "Weapon enchant icons now sit flush with the buff run in every grow direction, count against Max Icons, and stay in place in combat." },
            { module = "Player Aura Bars", text = "Weapon enchants now show whenever the Buffs bar is on All Buffs or Has Duration; the separate Weapon Enchants filter row is gone." },
            { module = "Player Aura Bars", text = "Bars keep the same place across resolutions and UI scales, and icons and gaps snap to the nearest pixel instead of rounding down." },
            { module = "Player Aura Bars", text = "Bars now build reliably at login instead of sometimes leaving Blizzard's buff frame up until an options change." },
            { module = "QoL", text = "Raid Tools Quick Fire hotkeys can now be bound to mouse buttons and mouse-button chords." },
            { module = "Quest Tracker", text = "A hidden tracker (in combat, by visibility rules, or while idle in mouseover mode) no longer catches clicks meant for the world." },
            { module = "Raid Frames", text = "Raider.IO scores no longer show twice on unit tooltips (requires a current Raider.IO)." },
            { module = "Raid Frames", text = "The Offensive CDs preset, shared with Player Aura Bars, is updated for Midnight: new Mage, Rogue and Warlock cooldowns, with Icy Veins and Storm, Earth, and Fire retired." },
            { module = "Unit Frames", text = "Class-coloured name text now recolours when a unit turns hostile or friendly, matching the health bar." },
            { module = "Unit Frames", text = "Name > Target text on boss, target-of-target and focus-target frames now colours the target by class in instanced content instead of using the unit's reaction colour." },
            { module = "Localization", text = "Korean and Brazilian Portuguese caught up on the latest strings, and choosing a Chinese, Korean or Russian display language on an English client no longer shows garbled text." },
        },
    },
    {
        version = "9.1.8",
        heroes = {
            {
                module = "Chat",
                title  = "Chat Bubbles",
                desc   = "Restyle the chat bubbles over players' and NPCs' heads with your own background, border, font and colors for the channels you pick. Inside instances the game's own bubbles stay, with an option to hide them there; the whole feature is off by default.",
                nav    = { module = "EllesmereUIChat", page = "Chat Bubbles",
                           section = "DISPLAY", highlight = "Enable Chat Bubbles Customization" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title  = "Rotation Assist Style",
                desc   = "Pick a solid border or any glow style, color mode, thickness and outset for the Assisted Combat suggestion on your CDM icons",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           section = "EXTRAS", highlight = "Rotation Assist Style",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Swapping a talent loadout while action bars use Mouseover visibility no longer causes a stall or a script execution error." },
            { module = "Action Bars", text = "The stance bar's active highlight now follows the game's form state, so Shadowform shows as active again after Voidform ends." },
            { module = "Action Bars", text = "Inside dungeons and raids, showing an Extra Action Button or a vehicle bar no longer produces repeated cooldown errors in the error log." },
            { module = "Bags", text = "Looting or selling many items in a row with the bag window open no longer rebuilds the bag contents over and over, which could cause FPS drops during loot and vendor bursts." },
            { module = "Bags", text = "Item tooltips now refresh when the item under the cursor changes during a sale or sort." },
            { module = "Blizz UI Enhanced", text = "Socketing several gems in a row from the character sheet's socket strip no longer leaves an empty socketing window open after the first swap, and the socketing window no longer pushes the character sheet aside." },
            { module = "Blizz UI Enhanced", text = "Hovering world objects and NPCs no longer throws a Lua error when the tooltip uses a fixed position or a forced growth direction." },
            { module = "Chat", text = "Chat tab labels now use the chat outline style." },
            { module = "Chat", text = "Moving a channel to a new window from the chat link menu no longer errors and leaves the new tab empty." },
            { module = "Cooldown Manager", text = "Preset and trinket icons no longer glow when their Cooldown State Effect is set to None, and a Class Color or Custom color picked for a preset's ready glow now shows in that color instead of cyan." },
            { module = "Cooldown Manager", text = "A buff's per-icon Show Duration setting now survives every bar re-layout, so a duration you switched off no longer reappears when the bar reflows." },
            { module = "Cooldown Manager", text = "Buffs added by spell ID now follow their bar's visibility rules and opacity, so a buff bar hidden while mounted or out of combat no longer keeps showing those buffs." },
            { module = "Cooldown Manager", text = "Bar Glows now use the bar's Pixel Glow thickness, lines and speed for stack-gated entries and on buff bars." },
            { module = "Cooldown Manager", text = "The CD Ready sound no longer plays when a tracked buff of the same ability is gained." },
            { module = "Cooldown Manager", text = "Trinket slots no longer stay invisible after a login or reload until the trinket is re-equipped." },
            { module = "Cooldown Manager", text = "Macros using an equipment slot number (such as /use 13) now show their hotkey on the trinket icon." },
            { module = "Cooldown Manager", text = "A Tracking Bar now picks up a debuff you applied to your target when the game's own viewer misses it, such as after a macro that clears and restores your target." },
            { module = "Damage Meters", text = "Hovering another player's bar in combat no longer shows the secrecy notice when Show Breakdown on Hover is off." },
            { module = "General", text = "Searching the options no longer loses the results when a section toggle rebuilds the page." },
            { module = "Nameplates", text = "Friendly player nameplates set to Name Only no longer regain their health bars inside instances or after a fight starts." },
            { module = "Nameplates", text = "Nameplates no longer stay at the cast scale after an enemy's cast ends in combat." },
            { module = "QoL", text = "The Brez tracker's text size no longer changes when unlock mode is cancelled." },
            { module = "QoL", text = "The Target Distance Text now shows whole yards." },
            { module = "Raid Frames", text = "Custom raid-size width and height no longer snap back to a spec override's values while editing with Real preview on." },
            { module = "Raid Frames", text = "The Debuff Manager preview now shows a tile's own Display settings (duration text, stacks, swipe, border, zoom) instead of always drawing the Base Icons values, so what you see on the page matches the frames." },
            { module = "Raid Frames", text = "Raid and Party Show When Solo can both be switched off again when a profile has both enabled." },
            { module = "Raid Frames", text = "The party preview now centers a Hide Self layout like the live frames." },
            { module = "Resource Bars", text = "Centered cast-bar spell names now use the bar's full width instead of truncating at 60 percent." },
            { module = "Unit Frames", text = "The Focus Target frame now appears as soon as your focus picks a target, instead of staying invisible until you changed your own target." },
            { module = "Unit Frames", text = "Boss frames disabled by a profile switch no longer reappear on the next boss." },
            { module = "Unit Frames", text = "The Player Aura Bars preview now draws the dispel-type icon above the duration swipe." },
            { module = "Localization", text = "Traditional Chinese, Korean and Brazilian Portuguese caught up on the latest strings." },
        },
    },
    {
        version = "9.1.7",
        heroes = {
            {
                module = "Bags",
                title  = "Stack Splitter",
                desc   = "Shift-clicking a stack in All Items / Category views lets you split it up or even Auto Split to keep splitting into empty slots until only the amount you chose remains. Split stacks in All Items / Category views re-merge once the bags close and reopen (they stay split in OneBag/MultiBag).",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "EXTRAS", highlight = "Stack Splitter" },
            },
            {
                module = "Cooldown Manager",
                title  = "Replace with Buff",
                desc   = "A cooldown icon can show a tracked buff in its slot while that buff is active, then return to the cooldown when it ends. Pick the buff from the icon's right-click menu on any cooldown or utility bar.",
                -- The row lives in the per-icon right-click menu (cannot pulse): page-only with the cooldowns bar selected.
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
        },
        features = {
            {
                module = "AuraBuff Reminders",
                title  = "Borders, Fonts and a Soulstone Reminder",
                desc   = "Border Style and Size for reminder icons, per-text fonts, and an optional Soulstone reminder for Warlocks",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "DISPLAY", highlight = "Border Style" },
            },
            {
                module = "AuraBuff Reminders",
                title  = "Warlock Where to Show",
                desc   = "The Warlock section gets its own Where to Show, so Soulstone and Wrong Demon pick their content independently",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "WARLOCK", highlight = "Where to Show" },
            },
            {
                module = "Cooldown Manager",
                title  = "Bar Glow At Stacks",
                desc   = "Bar Glow entries can wait for a stack count comparison before glowing, like the per-icon Glow at Stacks",
                -- The toggle renders only for a selected button's entries (dynamic header): page-only.
                nav    = { module = "EllesmereUICooldownManager", page = "Bar Glows" },
            },
            {
                module = "Cooldown Manager",
                title  = "Partial Charge Shade",
                desc   = "Charge hash bars can darken the segment still recharging, in the Charge Hash Lines cog",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars",
                           section = "BAR LAYOUT", highlight = "Charge Hash Lines" },
            },
            {
                module = "Cooldown Manager",
                title  = "Show Glows Only in Combat",
                desc   = "A global option that hides every glow out of combat and brings them back when you pull (bar Extras, off by default)",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           section = "EXTRAS", highlight = "Show Glows Only in Combat",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end end },
            },
            {
                module = "Damage Meters",
                title  = "Show/Hide Windows Keybind",
                desc   = "Bind a key to hide and show every meter window at once, optionally including the combat timer and Spell History",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters",
                           section = "EXTRAS", highlight = "Show/Hide Windows Keybind" },
            },
            {
                -- Static card: the work is automatic, nothing to open.
                module = "General",
                title  = "Performance Patch Follow-Up",
                desc   = "The UI loads noticeably faster at login and after a reload, hidden action bars skip their button build, and the guild window refreshes only its own controls",
            },
            {
                module = "Nameplates",
                title  = "No Aggro Override Boss Colors",
                desc   = "The No Aggro cog gains an Override Boss colors toggle; untick it to keep the Bosses color when a DPS or healer engages",
                -- Toggle lives in the No Aggro cog: pulse the owning DPS No Aggro row.
                nav    = { module = "EllesmereUINameplates", page = "Colors",
                           section = "THREAT COLORS (INSTANCES ONLY)", highlight = "DPS: Show Special" },
            },
            {
                module = "QoL",
                title  = "Bloodlust Ready Display",
                desc   = "The Bloodlust Tracker can keep its icon up with a Ready label once Sated expires and shows your own lust spell's icon",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "BLOODLUST TRACKER", highlight = "Show Icon with Ready Text" },
            },
            {
                module = "QoL",
                title  = "Cursor Center Reticle",
                desc   = "An optional filled dot at the center of the cursor circle, in the circle's own color and opacity",
                nav    = { module = "EllesmereUIQoL", page = "Cursor", section = "CURSOR", highlight = "Center Reticle" },
            },
            {
                module = "QoL",
                title  = "Persistent Signup Note",
                desc   = "Save a signup note that a Copy button drops into the Sign Up dialog",
                nav    = { module = "EllesmereUIQoL", page = "QoL",
                           section = "GROUP FINDER", highlight = "Persistent Signup Note" },
            },
            {
                module = "Quickdraw",
                title  = "Outfits",
                desc   = "Saved transmog outfits can be Quickdraw entries or a full menu from the new Outfits preset, cooldown shown, no undress on a repeat press",
                -- Preset lives in the Add Action Menu picker: pulse that row.
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw",
                           section = "GENERAL", highlight = "Add Action Menu" },
            },
            {
                module = "Raid Frames",
                title  = "Party Frames in Small Raids",
                desc   = "Show group 1 as party frames and hide everyone else while your raid has fewer than 10 players",
                nav    = { module = "EllesmereUIRaidFrames", page = "Party",
                           section = "FRAMES", highlight = "Party Frames in Small Raids" },
            },
            {
                module = "Unit Frames",
                title  = "Player Aura Bar Border Styles",
                desc   = "Buff and debuff bars can use the built-in and shared-media border textures, with offset, shift and layer controls and a sync to all bars",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars",
                           section = "DISPLAY", highlight = "Border Style" },
            },
            {
                module = "Unit Frames",
                title  = "Player Aura Bars Element Options",
                desc   = "The unlock mode cog on any Player Aura Bar opens that bar's settings directly",
                -- Unlock-mode cog, no on-page row: page-only.
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "After a form or stance change in combat, Action Bar 1 keybinds now cast the ability the button shows instead of the caster page's spell." },
            { module = "Action Bars", text = "The Extra Action Button and Encounter Bar come back on their own when a visibility condition that hid them clears, instead of waiting for a reload." },
            { module = "AuraBuff Reminders", text = "Middle-clicking a reminder to dismiss it no longer uses the item or casts the spell, and dismiss now works in combat too." },
            { module = "Bags", text = "Items returned from the mailbox, such as unsold auctions, now count as Recent Items." },
            { module = "Blizz UI Enhanced", text = "The character sheet no longer keeps flagging an enchanted weapon as missing its enchant when the first scan ran before the item data had loaded." },
            { module = "Blizz UI Enhanced", text = "The character sheet no longer flags a one-handed weapon as an upgrade over your shield or off-hand when your spec cannot dual wield." },
            { module = "Blizz UI Enhanced", text = "The Auction House Buy, Sell and My Auctions tabs no longer drift after another Auction House skin is closed." },
            { module = "Blizz UI Enhanced", text = "The Accept and Decline labels on group invite popups no longer break onto a second line." },
            { module = "Blizz UI Enhanced", text = "Fixed a forbidden-object error when a tooltip opened on a nameplate inside a dungeon or raid." },
            { module = "Chat", text = "The Tab Spacing slider works again, and the gap before the first scrolling tab now matches the others." },
            { module = "Chat", text = "Fixed a Lua error from the tab strip during raid combat." },
            { module = "Chat", text = "Item and player links in chat history restored after a reload work again, and the mouse wheel can scroll up into the restored lines." },
            { module = "Cooldown Manager", text = "The FocusKick cast sound no longer fires for Warlocks while the active pet interrupt is on cooldown." },
            { module = "Damage Meters", text = "Bar spacing now renders evenly on every row at any UI scale, and the meter re-lays out immediately when the UI scale changes." },
            { module = "Data Bars", text = "Hovering the system block mid-pull no longer risks a script-ran-too-long error from the addon memory scan." },
            { module = "Friends", text = "Inviting or whispering a friend no longer fails when the character name already carries its realm." },
            { module = "General", text = "Searching the options for Skyriding now finds the Dragon Riding settings." },
            { module = "General", text = "The first-install setup popup now shows readable text on Chinese, Korean and Cyrillic clients." },
            { module = "General", text = "The Macro Factory no longer offers the Nature's Swiftness + Convoke macro for Restoration Druids; existing copies are left in place." },
            { module = "General", text = "Party and raid player menus opened by the fallback no longer risk a blocked action from the range-checked entries." },
            { module = "General", text = "Range fading: gap-closer spells no longer fade a target standing in melee, an item you do not own no longer blanks the range answer, and the crosshair cutoff now lands at the distance it is set to." },
            { module = "Minimap", text = "Switching the minimap to Mouseover visibility now hides it right away instead of leaving the map icons showing until the first hover." },
            { module = "Minimap", text = "Hiding the Tracking button no longer leaves an invisible click spot at the corner of the screen." },
            { module = "Mythic+ Tools", text = "Textured bar fills no longer bleed past the bar border." },
            { module = "Mythic+ Tools", text = "Threshold time labels no longer overlap the clock with the Gaps bar style and Enemy Forces at the bottom." },
            { module = "Nameplates", text = "Bosses that use mana now take the Bosses color instead of Spell Caster." },
            { module = "Nameplates", text = "Target arrows no longer sit out at the wide fallback position after a target swap or a cast bar change." },
            { module = "QoL", text = "The keystone popup's dungeon teleport buttons no longer stay hidden for the session when dungeon data loaded late at login." },
            { module = "QoL", text = "Disable Right Click Targeting no longer leaves right-click stuck on camera turning after hovering an enemy, and a mouselook it started can no longer get stuck on." },
            { module = "QoL", text = "The Auction House Current Expansion Only option now actually applies the filter." },
            { module = "QoL", text = "The combat right-click protection for allies no longer blocks using your own Demonic Gateway." },
            { module = "QoL", text = "Bloodlust and Battle Res icons, text offsets and saved positions now sit on the pixel grid at every UI scale." },
            { module = "Quickdraw", text = "A radial menu can now hold up to 20 entries, up from 16." },
            { module = "Quickdraw", text = "Opening a palette that holds an item during a pull no longer logs a blocked action; the out-of-range tint still shows outside that case." },
            { module = "Raid Frames", text = "With debuff tooltips set to Shown on Modifier, the hover highlight and clicks no longer bleed onto the frames above and below." },
            { module = "Raid Frames", text = "A group member whose name changes mid-combat (for example from the Forgotten Memento toy) no longer vanishes from the party or raid frames until combat ends." },
            { module = "Raid Frames", text = "Click-Casting: when two spells share a key, the one your current talents give you is the one that casts; untalented spells dim in the sidebar and no longer raise conflict warnings." },
            { module = "Raid Frames", text = "Custom buff icon borders line up at every icon size on party and raid frames." },
            { module = "Raid Frames", text = "A profile with an incomplete absorb color no longer throws a Lua error on every repaint." },
            { module = "Raid Frames", text = "The party Show AFK toggle now works independently when Party Indicators are unsynced from raid." },
            { module = "Raid Frames", text = "Glows and reminders from addons that locate raid frames through a shared frame library now find our frames reliably after roster and role changes." },
            { module = "Raid Frames", text = "Debuff Manager tiles now follow Auto Resize Indicators like Base Icons do, so equal configured sizes show equal on raid, party and extra frames, and typed dispel routing stays in the configured tile after live filter changes." },
            { module = "Raid Frames", text = "The Offensive CDs buff preset now covers every class, including the talent variants that replace a cooldown." },
            { module = "Raid Frames", text = "Other addons can ask EllesmereUI.GetUnitFrame(unit) for the frame showing a unit, a fallback for glow addons whose frame lookup returns nothing." },
            { module = "Resource Bars", text = "Disintegrate tick marks on chained recasts now sit on the actual damage ticks instead of drifting late." },
            { module = "Resource Bars", text = "The player cast bar no longer blanks and restarts when a channel is re-issued mid-flight, such as Hover during Disintegrate." },
            { module = "Unit Frames", text = "A unit that dies with a heal in flight now shows an empty health bar and 0% next to DEAD instead of the last predicted value." },
            { module = "Unit Frames", text = "Boss frames no longer lose their name and health text for the rest of a pull after a brief flicker in the unit's existence." },
            { module = "Unit Frames", text = "Show Duration Swipe now applies to the weapon enchant cells on Player Aura Bars, and they restyle with font and profile changes." },
            { module = "Localization", text = "Korean, Brazilian Portuguese, Simplified Chinese and Traditional Chinese caught up on the 9.1.6 strings (Less Common Filters, Warlock demons, Stack Splitter, combat-only glows and more)." },
        },
    },
    {
        version = "9.1.6",
        heroes = {
            {
                module = "Unit & Raid Frames",
                title  = "Max Duration and Less Common Filters",
                desc   = "Debuff filters on Player Aura Bars, Raid Frames and the player frame gain a Less Common Filters section: Cast By Me, Any Player, Magic, Curse, Poison, Disease, Bleed and Can Apply. A new Max Duration dropdown beside Filters keeps long debuffs off Player Aura Bars and Raid Frames.",
                -- Manager views cannot pulse a row: page-only, same as the earlier Debuff Manager entries.
                nav    = { module = "EllesmereUIRaidFrames", page = "Debuff Manager" },
            },
        },
        features = {
            {
                module = "AuraBuff Reminders",
                title  = "Warlock Demon Reminder",
                desc   = "Allowed Demons picks which demons count as correct for any Warlock spec, and the Missing Pet reminder now summons on click",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables",
                           section = "WARLOCK", highlight = "Wrong Demon" },
            },
            {
                module = "Blizz UI Enhanced",
                title  = "Friend Notifications Skin",
                desc   = "The Battle.net friend online and offline toast gets a window skin, with its own Friend Notifications card",
                -- Card list, no pulse target: page-only like the other window-skin entries.
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
            {
                module = "Cooldown Manager",
                title  = "Glow at Stacks Comparisons",
                desc   = "Glow at Stacks can now fire Below, At Most, Exactly, At Least or Above the stack count you set, still secret-safe in combat",
                -- Rows live in each spell's dropdown (cannot pulse): same route as the 9.1.1 Glow at Stacks card.
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end end },
            },
            {
                -- Static card: the work is automatic, nothing to open.
                module = "General",
                title  = "Performance Patch Follow-Up",
                desc   = "Raid frame absorbs and health ticks, nameplate health updates, tracking bar pairing and unit frame absorbs all do less work per event",
            },
            {
                module = "QoL",
                title  = "Crosshair Frame Strata",
                desc   = "A Frame Strata dropdown in the Character Crosshair cog controls whether the crosshair draws above or below other UI",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "CROSSHAIR", highlight = "Character Crosshair" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Opening Myslot again forces every bar visible, including bars using Match Any, Hide with Target or the mounted visibility conditions." },
            { module = "Cooldown Manager", text = "Glow at Stacks no longer shows a faint glow before the buff reaches the set stack count, and the Shape Glow style now respects the threshold." },
            { module = "Cooldown Manager", text = "Liquid Luster is available as a Custom Buff Bar potion preset alongside Light's Potential and Potion of Recklessness." },
            { module = "Damage Meters", text = "Deaths show their real time of death during the fight instead of 0:00 until combat ends." },
            { module = "Damage Meters", text = "The refresh rate now bottoms out at 0.5s (lower saved values move up to it), trimming memory churn during combat." },
            { module = "General", text = "Entering an instance with the taintLog or scriptProfile debug CVars enabled shows a one-time reminder with a button to disable them, since they cost performance." },
            { module = "General", text = "Keybinds set in EllesmereUI's own key fields now fire when two or more modifiers are held (for example Ctrl+Alt+1); re-bind any that never triggered." },
            { module = "QoL", text = "The LFG Reminder popup now matches dungeon names on every client language, not only English and Russian." },
            { module = "Quest Tracker", text = "Quest objective progress no longer stops updating until a reload (a fishing count or summon bar stuck mid-way)." },
            { module = "Raid Frames", text = "Tracked buffs no longer randomly stay hidden on some group members' frames." },
            { module = "Raid Frames", text = "Max Health Style shows on its own again when Absorb Style is set to None." },
            { module = "Resource Bars", text = "Death Knight rune pips now honor Border on Individual Pips like every other pip type." },
            { module = "Resource Bars", text = "The Whirlwind and Sweeping Strikes bar honors the Empty Bar Overlay again so spent charges show in Dark Mode, no longer draws a second set of divider lines with Bar Spacing set, hides its threshold strip while thresholds are disabled, and accepts a stack threshold up to 20." },
            { module = "Unit Frames", text = "The pet frame updates its name and portrait when you swap pets (for example Voidwalker to Felhunter)." },
            { module = "Unit Frames", text = "A spec override setting Visibility to Never no longer leaves the frame missing after switching back to another spec." },
            { module = "Unit Frames", text = "Class Resource pips no longer widen after a zone change on positions other than Above Health Bar." },
            { module = "Localization", text = "Brazilian Portuguese, Korean and Traditional Chinese caught up on the 9.1.4 strings (bank grouping, visibility overrides, the queue timer style and more)." },
        },
    },
    {
        version = "9.1.4",
        heroes = {
            {
                module = "Bags",
                title  = "Bank Organization",
                desc   = "The bank window catches up to the bags: nest OneBank and OneWarbank by expansion, group items by your bag categories with automatic splits by equipment slot, profession and material, and browse a category sidebar that spans your character bank and warband together.",
                nav    = { module = "EllesmereUIBags", page = "Bank" },
            },
        },
        features = {
            {
                module = "Blizz UI Enhanced",
                title  = "Queue Timer Style",
                desc   = "Configurable text color, size, bar height and text position for the queue accept countdown, via a swatch and cog beside Show Queue Timer",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups",
                           section = "BLIZZARD POPUPS & GAME MENU", highlight = "Show Queue Timer" },
            },
            {
                module = "Nameplates",
                title  = "Friendly NPC Name Styling",
                desc   = "Name-only friendly NPC plates gain configurable name color, title color and title size in the Friendly NPC Settings cog",
                nav    = { module = "EllesmereUINameplates", page = "General",
                           section = "OTHER NAMEPLATES", highlight = "Show Friendly NPC Nameplates" },
            },
            {
                module = "Resource Bars",
                title  = "Whirlwind and Sweeping Strikes Thresholds",
                desc   = "Threshold and band colors work on the Whirlwind and Sweeping Strikes charge bar again, drawn as color ranges along the fill",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars" },
            },
            {
                module = "Unit Frames",
                title  = "Hide Trailing Zeros",
                desc   = "With health decimals on, full health renders 100% instead of 100.0% while real decimals like 99.5% stay",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                           section = "DISPLAY", highlight = "Show Decimal on Health Text" },
            },
        },
        fixes = {
            { module = "Blizz UI Enhanced", text = "Hovering names in the Guild & Communities roster no longer errors, and member tooltips keep their race and class lines." },
            { module = "Cooldown Manager", text = "Out-of-range coloring now tracks the spell actually on the icon while a proc or talent override replaces it, instead of the base spell's range." },
            { module = "Cooldown Manager", text = "Apply to This Spell and Apply to Bar no longer reset a picked Active State color (or other value-carrying settings on preset icons, trinkets and racials) back to defaults." },
            { module = "Damage Meters", text = "In-combat ally breakdowns are now dungeon-only, cutting Damage Meters memory use in raids where duplicate specs blocked most of them anyway." },
            { module = "General", text = "A checked Hide visibility condition now always hides its element in both match modes, and every condition has its own Show and Hide row, with new Out of Combat and Not Skyriding (Airborne) rows." },
            { module = "General", text = "Spec and conditional overrides can now hold the Visibility setting itself, replacing it with Never, Always or Mouseover for those specs." },
            { module = "General", text = "Picking a raid marker from the fallback unit menu (shown for group members whose data has not streamed in) is now greyed out like the other unavailable actions there instead of throwing a blocked-action error." },
            { module = "Minimap", text = "With the Rectangular shape, player and party arrows no longer draw in the hidden bands above and below the map, and combat transitions no longer leave the map cut off wrong." },
            { module = "Mythic+ Tools", text = "Target, Focus and Targeted Spell cast bars no longer truncate spell names when there is no target text sharing the bar." },
            { module = "Nameplates", text = "The target effect's border size no longer snaps back to normal while a cast bar is shown with Border Wraps Around Cast Bar enabled." },
            { module = "Localization", text = "Simplified Chinese caught up on the recent additions (chat recall, the performance reminder, Ignore Pain tracking and more)." },
        },
    },
    {
        version = "9.1.3",
        mini = true,
        fixes = {
            { module = "Cooldown Manager", text = "Duration text no longer randomly disappears on bar icons during dungeon and raid combat." },
            { module = "Localization", text = "Traditional Chinese, Korean and Brazilian Portuguese gained the 9.1 option strings (Quick Fire, the Broker Plugin block, Glow at Stacks and more)." },
        },
    },
    {
        version = "9.1.1",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Glow at Stacks",
                desc   = "A per-spell toggle that holds the Buff Glow back until the buff reaches the stack count you set, in your chosen glow style. Set it from the spell's dropdown on the CDM Bars tab; it replaces the normal presence glow on that spell.",
                -- Rows live in each spell's dropdown (cannot pulse): land on CDM Bars with the
                -- default Buffs bar selected, the same _setCDMBar route global search uses.
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                           preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end end },
            },
            {
                module = "DataBars",
                title  = "Broker Plugin",
                desc   = "A new block type that displays any LibDataBroker addon (SavedInstances, Titan plugins, and more) as a native Data Bars block with icon, text, clicks, and tooltips forwarded. Strip Colors and Max Width controls keep plugins matching your bar.",
                -- Block settings only exist once the block is on a bar: page-only nav, same as the Gold and Crests entries.
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
        },
        features = {
            {
                module = "Damage Meters",
                title  = "Live Ally Breakdowns",
                desc   = "Click any group member on the meter during combat to open their spell breakdown live; identical class-and-spec twins unlock when combat ends",
                -- Meter window behavior, no dedicated options row: page-only nav.
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters" },
            },
            {
                module = "QoL",
                title  = "Raid Tools Quick Fire",
                desc   = "Three optional keybinds to place the next free world marker at your cursor, undo the last one, or clear them all, usable in combat",
                nav    = { module = "EllesmereUIQoL", page = "Raid Tools", section = "QUICK FIRE", highlight = "Enable Quick Fire" },
            },
            {
                module = "Resource Bars",
                title  = "Exact Warrior Charges",
                desc   = "Whirlwind and Sweeping Strikes charges are now read straight from the game engine on the Resource Bar, Unit Frames and Nameplates class power: exact server counts everywhere, with shaped and icon pip styles showing these two as a segmented bar",
                -- Behavior rework with no single setting row: page-only nav to the class bars page.
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars" },
            },
            {
                module = "General",
                title  = "Resting and In Vehicle Visibility",
                desc   = "The Visibility checklist across the suite gains Resting and In Vehicle conditions, updating the moment you enter or leave rest areas or vehicles",
                -- The rows live inside every module's Visibility checklist; land on the Main Bar row like the Match Mode entry.
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY", highlight = "Visibility",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
            {
                module = "Mythic+ Tools",
                title  = "Always Show Split Times",
                desc   = "A Split Compare cog option that shows your reference split on bosses you have not killed yet",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer", section = "BOSS OBJECTIVES", highlight = "Split Compare" },
            },
            {
                module = "Bags",
                title  = "Clear Recent Items",
                desc   = "An optional Clear button on the Recent Items header empties the list on demand",
                -- The Clear toggle sits in the Show Recent Items cog popup: highlight the host row.
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "EXTRAS", highlight = "Show Recent Items" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "The out-of-range tint no longer disappears from buttons whose spell swaps itself with another, like Raptor Strike." },
            { module = "Action Bars", text = "The Micro Menu no longer comes back empty after pet battles." },
            { module = "Action Bars", text = "Pulling a boss with an assisted-combat action on a hidden or mouseover bar no longer causes blocked-action errors." },
            { module = "Aura Buff Reminders", text = "Middle-clicking a reminder to dismiss it no longer also casts the buff." },
            { module = "Bags", text = "Recent Items now re-flags items you re-loot after selling or using them, catches loot that is used up right away, holds 15 entries, and no longer mistakes mail or bank traffic for new pickups." },
            { module = "Bags", text = "Pinning one upgrade track of an item no longer pins or unpins every other track of the same item." },
            { module = "Bags", text = "The keystone level shown on the bag slot now updates right after a key is downgraded, including by Lindormi, while the bags are open." },
            { module = "Blizz UI Enhanced", text = "The Show Tooltips combat modes now also hide bag, character panel and other explicitly-anchored tooltips, matching what the option says; the Peek Modifier reveals them as usual." },
            { module = "Blizz UI Enhanced", text = "With combat tooltip modes, an allowed tooltip's item-comparison window no longer flashes or vanishes from a leftover cleanup of an earlier suppressed tooltip." },
            { module = "Chat", text = "Messages typed in Rated Battlegrounds, Mythic+ and raids are no longer silently blocked; chat message recall in those places moves to Alt+Up and Alt+Down with a one-time hint." },
            { module = "Cooldown Manager", text = "On-use trinkets that also carry a passive equip effect (like Hex Lord's Dooming Idol) now show and track in the trinket slot." },
            { module = "Cooldown Manager", text = "Charge counters now update the moment a charge is gained, including bonus charges from tier set procs, instead of waiting for the next refresh." },
            { module = "Damage Meters", text = "Chinese and Korean clients keep the thousands grouping on values under ten thousand." },
            { module = "Friends", text = "Fixed repeated stutters while the friends list is open; the list now updates only the rows on screen and only when something actually changes." },
            { module = "General", text = "Under Visibility Match Any, Mouseover now combines as a true OR: another passing condition shows the element outright, and when none pass it stays hover-revealable instead of hiding." },
            { module = "General", text = "Option-page previews (raid frame previews, boss preview, meter windows, alert previews) now clean up when you switch to another module instead of lingering behind it." },
            { module = "Minimap", text = "The mail and Crafting Orders icons no longer vanish on the Circle and Textured Circle shapes when the tracking button is hidden." },
            { module = "Minimap", text = "Third-party raid tools that read the player's facing through the minimap compass work again with the EUI minimap enabled." },
            { module = "Mythic+ Tools", text = "Targeted Spell Bars' Where to Show now works with In Combat selected, including bars for enemies already on screen when combat starts." },
            { module = "Nameplates", text = "The dispel glow's Action Button Glow style now draws its full halo instead of thin marching ants, colored like the real thing: white ants with the glow color riding the halo, gold by default." },
            { module = "Profiles", text = "Editing Buff or Debuff Manager settings inside an override group now confirms the change saved to that override instead of showing a refusal message." },
            { module = "QoL", text = "Cursor Trail now follows every visibility rule on the cursor circle, including Combat Only and the shared Visibility options." },
            { module = "QoL", text = "A GCD or Cast circle switched back to Attach to Cursor no longer keeps a stale mover, and attached circles no longer chase the mouse while Unlock Mode is open." },
            { module = "Quest Tracker", text = "The background no longer throws repeated errors after leaving an arena, no longer blanks out when minimizing a section, and follows collapse and add/remove animations smoothly." },
            { module = "Raid Frames", text = "Buff and debuff displays no longer freeze on a group member after roster changes, and hidden buff monitors no longer show stale icons when reused." },
            { module = "Raid Frames", text = "The Dispel and External click-cast presets now cast the right spell on every spec (Holy Priest, Elemental Shaman and Shadow Priest included), and Dynamic Rez works out of combat for Death Knights and Warlocks and can pre-cast Soulstone on a living ally." },
            { module = "Raid Frames", text = "Guardian of Ancient Kings with Glyph of the Queen applied now counts for the Defensives filter, with a distinguishable name in the spell pickers; picker rows show a hover tooltip for long or duplicate names." },
            { module = "Raid Frames", text = "Hover and Target borders now work on frames with Border Size 0, drawing their own outline at a configurable thickness (new cog on the Hover Borders row)." },
            { module = "Raid Frames", text = "Dead players now fade by the distance to their corpse (your resurrection spell's range) instead of where their ghost is standing, for classes that can resurrect." },
            { module = "Resource Bars", text = "The Protection Warrior Ignore Pain bar no longer fills from other absorbs like trinket shields: with Ignore Pain tracked in the Blizzard CDM it shows exactly your Ignore Pain amount, and otherwise only fills while Ignore Pain is up." },
            { module = "Resource Bars", text = "The Arcane Soul Helper no longer shows for Spellslinger Arcane Mages after a hero talent swap; it is Sunfury only." },
            { module = "Resource Bars", text = "The Whirlwind and Sweeping Strikes charge bar honors the Empty Bar Overlay again, so spent charges stay visible in Dark Mode." },
            { module = "Unit Frames", text = "Changing the weapon enchant bar's grow direction in Unlock Mode no longer triggers a blocked-action error." },
            { module = "Localization", text = "Korean gained the Arcane Soul Helper, house-visit menu and Visibility Match Mode strings; Brazilian Portuguese gained the Visibility Match Mode strings and Buff Manager preset names; Traditional Chinese gained the unified Visibility checklist, Arcane Soul Helper, Crests and Item Level blocks, Compact Band, Debuff Filter modes, Ping Marker and Strict Comparison Mode strings." },
        },
    },
    {
        version = "9.0.8",
        heroes = {},
        features = {
            {
                module = "DataBars",
                title  = "Gold Abbreviate Amount",
                desc   = "Show large gold balances as 284.2Kg instead of the full number; the tooltip keeps the exact amount",
                -- Block settings only exist once the block is on a bar: page-only nav, same as the Crests and Item Level entries.
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "General",
                title  = "Visibility Match Mode",
                desc   = "Choose whether an element needs every checked condition (Match All) or just one of them (Match Any) to show",
                -- The Match Mode rows live inside every module's Visibility checklist; land on the Main Bar row like the Unified Visibility card.
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY", highlight = "Visibility",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Bars hidden by a Druid travel or flight form, or by the Skyriding Mount condition, no longer stay hidden for the whole fight when combat starts before you dismount." },
            { module = "Aura Buff Reminders", text = "The Augment Rune reminder now shows dimmed with a red 0 when you have no runes, following Show Without Item in Bags like flask, food and weapon enchants." },
            { module = "Blizz UI Enhanced", text = "The dungeon role-check popup is now skinned when another party member queues, not only when you queue yourself." },
            { module = "Chat", text = "Chat is visible again inside the housing House Editor." },
            { module = "Chat", text = "Fixed a repeating error during raid combat from the chat fade-out click passthrough." },
            { module = "Cooldown Manager", text = "The Bloodlust/Heroism preset bar and icon arm again after a death, so the second lust after a wipe shows its 40s window." },
            { module = "Cooldown Manager", text = "The Bloodlust/Heroism preset shows the correct faction name and icon (Horde no longer sees Heroism), including on a profile shared between a Horde and an Alliance character." },
            { module = "Cooldown Manager", text = "Mirror Key Presses now lights up potion icons when you press the current-tier potion (Concentrated Health, Light's Potential, Recklessness, Liquid Luster, Lightfused Mana, Invisibility)." },
            { module = "Cooldown Manager", text = "Turning off Hide in Housing on the Cooldowns, Utility and Buffs bars now stays off after a reload." },
            { module = "DataBars", text = "The spec block no longer shows a loadout that a combat-interrupted swap never applied." },
            { module = "General", text = "The Visibility checklist now switches off Never when you check a Show or Hide condition, and Always no longer shows as checked alongside a Show condition." },
            { module = "Nameplates", text = "Fixed a 'script ran too long' error when reconnecting mid-pull in a Mythic+." },
            { module = "QoL", text = "Unlock Mode no longer shows an FPS Counter mover while Show FPS Counter is off, and toggling the counter during Unlock Mode adds or removes the mover immediately." },
            { module = "Quickdraw", text = "Palette entries no longer show as question marks on the first open of a session." },
            { module = "Raid Frames", text = "Buff Manager and debuff icons no longer stay stuck on an expired aura after a group member comes back into view or from a loading screen." },
            { module = "Raid Frames", text = "Sense Power can now be tracked in the Augmentation Evoker Buff Manager, and its two same-named spells are told apart in the pickers." },
            { module = "Raid Frames", text = "The options preview no longer shows status text when Status Text is set to None." },
            { module = "Raid Frames", text = "Ready check and resurrection icons now use Blizzard's sharper modern artwork." },
            { module = "Unit & Raid Frames", text = "The dispel Fill Overlay now follows the health fill on vertical and reverse-fill bars instead of covering the whole bar." },
            { module = "Unit Frames", text = "The Blizzard-style class resource bar no longer disappears after in-game cutscenes." },
            { module = "Unit Frames", text = "Player Aura Bars come back right after a vehicle ride that ends in combat (Kings' Rest Entomb) and no longer stay hidden until combat drops." },
            { module = "Unit Frames", text = "Player Aura Bars filters now track every state of multi-state buffs such as Aspect of Harmony instead of only the first." },
            { module = "Localization", text = "Simplified Chinese, Korean and Brazilian Portuguese gained the latest option strings (the Fonts and Textures hubs, Ping Marker, Arcane Soul Helper, Crests and Item Level blocks, Debuff Filter modes, Compact Band, unified Visibility checklist, house-visit menu and marker entries)." },
        },
    },
}

-------------------------------------------------------------------------------
--  FCT font -- handled by EllesmereUI_Startup.lua which runs earlier.
-------------------------------------------------------------------------------

-- Wait for EllesmereUI to exist
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local GLOBAL_KEY = EllesmereUI.GLOBAL_KEY or "_EUIGlobal"
    local floor = math.floor
    local ceil  = math.ceil
    local max   = math.max

    ---------------------------------------------------------------------------
    --  CVar helpers
    ---------------------------------------------------------------------------
    local function GetCVarNum(cvar)
        return tonumber(GetCVar(cvar)) or 0
    end

    local function GetCVarBool(cvar)
        return GetCVar(cvar) == "1"
    end

    local function SetCVarSafe(cvar, value)
        if InCombatLockdown() then return end
        SetCVar(cvar, value)
    end

    --- Returns current, default as strings (nil-safe)
    local function CVarInfo(cvar)
        local cur, def = C_CVar.GetCVarInfo(cvar)
        return cur or "", def or ""
    end

    --- True while the CVar sits at Blizzard's built-in default (untouched by player or addon).
    local function IsAtBlizzardDefault(cvar)
        local cur, def = CVarInfo(cvar)
        return cur == def
    end

    ---------------------------------------------------------------------------
    --  EUI preferred defaults -- only applied when CVar == Blizzard default
    --
    --  { cvarName, euiPreferred }
    ---------------------------------------------------------------------------
    local EUI_DEFAULTS = {
        { "cameraDistanceMaxZoomFactor",                    "2.6" },
        { "ActionButtonUseKeyDown",                         "1"   },
    }

    --- Walk the table once at login and apply only where safe.
    local function ApplySmartDefaults()
        for _, entry in ipairs(EUI_DEFAULTS) do
            local cvar, preferred = entry[1], entry[2]
            if IsAtBlizzardDefault(cvar) then
                SetCVarSafe(cvar, preferred)
            end
        end
    end
    ApplySmartDefaults()

    -- Apply suppress lua errors on login (default: ON)
    if not EllesmereUIDB or EllesmereUIDB.suppressErrors ~= false then
        SetCVarSafe("scriptErrors", "0")
    end

    -- Optimized graphics settings are NOT re-applied on login: SetCVar already persists, so re-applying would override the user's manual adjustments.

    ---------------------------------------------------------------------------
    --  General page
    ---------------------------------------------------------------------------
    local function BuildGeneralPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  Optimized graphics CVar table + buttons (above all sections)
        -------------------------------------------------------------------
        local OPTIMIZED_CVARS = {
            { "graphicsShadowQuality",      "1" },
            { "graphicsLiquidDetail",       "0" },
            { "graphicsParticleDensity",    "5" },
            { "graphicsSSAO",              "0" },
            { "graphicsDepthEffects",       "0" },
            { "graphicsComputeEffects",     "0" },
            { "graphicsOutlineMode",        "0" },
            { "graphicsTextureResolution",  "2" },
            { "graphicsSpellDensity",       "0" },
            { "graphicsProjectedTextures",  "1" },
            { "graphicsViewDistance",        "0" },
            { "graphicsEnvironmentDetail",  "0" },
            { "graphicsGroundClutter",      "0" },
            { "RAIDsettingsEnabled",        "0" },
            { "ResampleAlwaysSharpen",      "1" },
            -- Reverb runs a full effect bus over the mix; disabling it trims audio DSP work and keeps spell/interrupt cues dry and crisp.
            { "Sound_EnableReverb",         "0" },
        }

        local function ApplyOptimizedGfx()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            -- One-time store: only snapshot if no backup exists yet
            if not EllesmereUIDB.gfxBackup then
                local backup = {}
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    backup[entry[1]] = GetCVar(entry[1])
                end
                backup["Contrast"] = GetCVar("Contrast")
                EllesmereUIDB.gfxBackup = backup
            else
                -- Backfill CVars added to the list after the original snapshot so Restore covers them too.
                local backup = EllesmereUIDB.gfxBackup
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    if backup[entry[1]] == nil then
                        backup[entry[1]] = GetCVar(entry[1])
                    end
                end
            end
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                SetCVarSafe(entry[1], entry[2])
            end
            local curContrast = tonumber(GetCVar("Contrast")) or 50
            if curContrast <= 55 then
                SetCVarSafe("Contrast", curContrast + 10)
            end
            local rl = EllesmereUI._widgetRefreshList
            if rl then for i = 1, #rl do rl[i]() end end
        end

        local function RestoreGfxSettings()
            if not EllesmereUIDB or not EllesmereUIDB.gfxBackup then return end
            local backup = EllesmereUIDB.gfxBackup
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                local saved = backup[entry[1]]
                if saved then SetCVarSafe(entry[1], saved) end
            end
            if backup["Contrast"] then SetCVarSafe("Contrast", backup["Contrast"]) end
            EllesmereUIDB.gfxBackup = nil
            local rl2 = EllesmereUI._widgetRefreshList
            if rl2 then for i = 1, #rl2 do rl2[i]() end end
        end

        do
            local ROW_H = 52
            local gfxFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(gfxFrame, totalW, ROW_H)
            PP.Point(gfxFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            -- Optimize button (always visible)
            local optBtn = CreateFrame("Button", nil, gfxFrame)
            local OPT_W = 300
            PP.Size(optBtn, OPT_W, 42)
            PP.Point(optBtn, "TOP", gfxFrame, "TOP", 0, 0)
            optBtn:SetFrameLevel(gfxFrame:GetFrameLevel() + 1)
            EllesmereUI.MakeStyledButton(optBtn, "Optimize My FPS and Graphics", 14,
                EllesmereUI.WB_COLOURS, ApplyOptimizedGfx)
            optBtn:HookScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(optBtn, "Optimizes your graphics settings for maximum FPS and visual clarity.")
            end)
            optBtn:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Restore button (only visible when backup exists)
            local restBtn = CreateFrame("Button", nil, gfxFrame)
            local REST_W = 128
            PP.Size(restBtn, REST_W, 29)
            PP.Point(restBtn, "LEFT", optBtn, "RIGHT", 30, 0)
            restBtn:SetFrameLevel(gfxFrame:GetFrameLevel() + 1)
            restBtn:SetAlpha(0.7)
            local _, _, restLbl = EllesmereUI.MakeStyledButton(restBtn, "Restore My Settings", 10,
                EllesmereUI.RB_COLOURS, RestoreGfxSettings)
            restBtn:HookScript("OnEnter", function() restBtn:SetAlpha(1) end)
            restBtn:HookScript("OnLeave", function() restBtn:SetAlpha(0.7) end)

            local function RefreshRestoreVisibility()
                if EllesmereUIDB and EllesmereUIDB.gfxBackup then
                    restBtn:Show()
                    -- Shift optimize button left to make room
                    optBtn:ClearAllPoints()
                    PP.Point(optBtn, "TOP", gfxFrame, "TOP", -(REST_W / 2 + 15), 0)
                else
                    restBtn:Hide()
                    optBtn:ClearAllPoints()
                    PP.Point(optBtn, "TOP", gfxFrame, "TOP", 0, 0)
                end
            end
            RefreshRestoreVisibility()
            EllesmereUI.RegisterWidgetRefresh(RefreshRestoreVisibility)

            -- "More Information" accent-colored clickable text
            local infoBtn = CreateFrame("Button", nil, gfxFrame)
            infoBtn:SetFrameLevel(gfxFrame:GetFrameLevel() + 1)
            local EG = EllesmereUI.ELLESMERE_GREEN
            local infoFS = infoBtn:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(EllesmereUI.EXPRESSWAY, 12, EllesmereUI.GetFontOutlineFlag())
            infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70)
            infoFS:SetText(EllesmereUI.L("More Information"))
            infoFS:SetPoint("CENTER")
            infoBtn:SetSize(infoFS:GetStringWidth() + 10, 18)
            PP.Point(infoBtn, "TOP", optBtn, "BOTTOM", 0, -4)
            infoBtn:SetScript("OnEnter", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            infoBtn:SetScript("OnLeave", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70) end)
            infoBtn:SetScript("OnClick", function()
                EllesmereUI:ShowInfoPopup({
                    title = "FPS & Graphics Optimization",
                    content = "This feature optimizes your in-game graphics settings to give you the best combination of high FPS and visual clarity.\n\nYou can revert all changes at any time by clicking \"Restore My Settings\" which will appear after optimizing.\n\n\nWhat we change:\n\n"
                        .. "Shadow Quality - Fair (balanced quality/FPS)\n"
                        .. "Liquid Detail - Disabled\n"
                        .. "Particle Density - Set to Ultra (keeps important spell effects)\n"
                        .. "SSAO (Ambient Occlusion) - Disabled\n"
                        .. "Depth Effects - Disabled\n"
                        .. "Compute Effects - Disabled\n"
                        .. "Outline Mode - Disabled\n"
                        .. "Texture Resolution - Set to High\n"
                        .. "Spell Density - Set to Essential\n"
                        .. "Projected Textures - Enabled (needed for ground effects)\n"
                        .. "View Distance - Reduced to 1\n"
                        .. "Environment Detail - Reduced to 1\n"
                        .. "Ground Clutter - Reduced to 1\n"
                        .. "Raid/Dungeon Settings - Uses same settings everywhere\n"
                        .. "Resample Sharpening - Enabled (crisper image)\n"
                        .. "Contrast - Boosted by +10 (if currently 55 or below)\n"
                        .. "Enable Reverb - Disabled (spell and interrupt audio cues stay crisp)\n\n"
                        .. "These settings prioritize frame rate and visual clarity over environmental detail. Textures stay high quality so your character and the world still look perfect.",
                })
            end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        local themeValues = {}
        for _, name in ipairs(EllesmereUI.THEME_ORDER) do
            themeValues[name] = name
        end

        -- Row 1: UI Accent Color | EUI Options Theme
        local themeRow
        themeRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="UI Accent Color",
              tooltip="Sets the accent color used across all EllesmereUI elements (tabs, glows, highlights, borders). Defaults to your theme color.",
              swatches = {
                { tooltip = "Class Color",
                  getValue = function()
                      local cr, cg, cb = EllesmereUI.GetPlayerClassColor()
                      return cr, cg, cb, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      -- Per-profile: set use-class, then re-resolve + apply live.
                      EllesmereUI.SetActiveProfileAccent(nil, true)
                      EllesmereUI.RefreshAccent()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return (select(1, EllesmereUI.GetActiveAccentState())) and 1 or 0.3
                  end },
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local _, ca = EllesmereUI.GetActiveAccentState()
                      if ca then return ca.r, ca.g, ca.b, 1 end
                      return EllesmereUI.DEFAULT_ACCENT_R, EllesmereUI.DEFAULT_ACCENT_G, EllesmereUI.DEFAULT_ACCENT_B, 1
                  end,
                  setValue = function(r, g, b)
                      -- Persists per-profile (custom + useClass=false), applies live.
                      EllesmereUI.SetAccentColor(r, g, b)
                  end,
                  onClick = function(self)
                      if select(1, EllesmereUI.GetActiveAccentState()) then
                          -- Switch class -> custom: clear the per-profile class flag and re-resolve (profile custom -> global -> theme).
                          EllesmereUI.SetActiveProfileAccent(nil, false)
                          EllesmereUI.RefreshAccent()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return (select(1, EllesmereUI.GetActiveAccentState())) and 0.3 or 1
                  end },
              } },
            { type="dropdown", text="EUI Options Theme",
              values=themeValues,
              order=EllesmereUI.THEME_ORDER,
              getValue=function()
                return EllesmereUI.GetActiveTheme()
              end,
              setValue=function(v)
                EllesmereUI.SetActiveTheme(v)
                -- Re-resolve the accent so the sidebar highlight tracks the theme.
                if EllesmereUI.RefreshAccent then
                    EllesmereUI.RefreshAccent()  -- ApplyAccentLive already refreshes the page
                else
                    EllesmereUI:RefreshPage()
                end
              end }
        );  y = y - h

        -- Inline color swatch on EUI Options Theme (right region)
        if not EllesmereUI._prebuilding then
            local rightRgn = themeRow._rightRegion
            local function isCustomColorOff()
                return EllesmereUI.GetActiveTheme() ~= "Custom Color"
            end

            local tcGet = function()
                local db = EllesmereUIDB
                local sa = db and db.accentColor
                if sa then return sa.r, sa.g, sa.b, 1 end
                return EllesmereUI.GetAccentColor()
            end
            local tcSet = function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.accentColor = { r = r, g = g, b = b }
                -- Only update the window background, not the accent color
                if EllesmereUI._applyBgTint then
                    EllesmereUI._applyBgTint(r, g, b)
                end
            end
            local tcSwatch, tcUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, tcGet, tcSet, nil, 20)
            PP.Point(tcSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = tcSwatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isCustomColorOff()
                tcSwatch:SetAlpha(off and 0.15 or 1)
                tcSwatch:EnableMouse(not off)
                tcUpdateSwatch()
            end)
            tcSwatch:SetAlpha(isCustomColorOff() and 0.15 or 1)
            tcSwatch:EnableMouse(not isCustomColorOff())
            tcSwatch:SetScript("OnEnter", function(self)
                if isCustomColorOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "This option is only available for the Custom Color Theme")
                end
            end)
            tcSwatch:SetScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
            end)
        end

        -- Row 2: UI Scale (with cog: "Set UI Scale to 0.5333")
        local uiScaleRow
        uiScaleRow, h = W:DualRow(parent, y,
            { type="slider", text="UI Scale",
              min=0.40, max=1.00, step=0.01,
              tooltip="Sets the scale of the entire game UI. Lower values make everything smaller, higher values make everything larger.",
              disabled=function() return EllesmereUIDB and EllesmereUIDB.ppFixedScale end,
              disabledTooltip="Set UI Scale to 0.5333", requireState="disabled",
              getValue=function()
                if EllesmereUI._uiScaleDragVal then
                    return EllesmereUI._uiScaleDragVal
                end
                return EllesmereUIDB and EllesmereUIDB.ppUIScale or EllesmereUI.PP.PixelBestSize()
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                -- Snap 0.53 to exact pixel-perfect 0.5333... (768/1440)
                if math.abs(v - 0.53) < 0.005 then v = 0.5333333333 end
                -- Snap 0.71 to exact pixel-perfect 0.7111... (768/1080)
                if math.abs(v - 0.71) < 0.005 then v = 0.7111111111 end
                EllesmereUI._uiScaleDragVal = v
                EllesmereUIDB.ppUIScaleAuto = false
                local mf = EllesmereUI._mainFrame
                local panelScaleBefore
                if mf then panelScaleBefore = mf:GetEffectiveScale() end
                EllesmereUI.PP.SetUIScale(v)
                if mf and panelScaleBefore then
                    local newEff = UIParent:GetEffectiveScale()
                    if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
                end
                if not EllesmereUI._uiScaleCleanup then
                    EllesmereUI._uiScaleCleanup = true
                    C_Timer.After(0, function()
                        if not EllesmereUI._sliderDragging then
                            EllesmereUI._uiScaleDragVal = nil
                            EllesmereUI:ShowConfirmPopup({
                                title = "UI Scale Changed",
                                message = "Blizzard's Edit Mode snapping may not work correctly until you reload your UI.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload    = true,
                            })
                        end
                        EllesmereUI._uiScaleCleanup = false
                    end)
                end
              end },
            { type="dropdown", text="EUI Options Panel Scale",
              values={ ["Tiny (75%)"]="Tiny (75%)", ["Small (90%)"]="Small (90%)", ["Normal (100%)"]="Normal (100%)", ["Large (110%)"]="Large (110%)", ["Huge (125%)"]="Huge (125%)", ["Giant (150%)"]="Giant (150%)", ["Massive (200%)"]="Massive (200%)" },
              order={ "Tiny (75%)", "Small (90%)", "Normal (100%)", "Large (110%)", "Huge (125%)", "Giant (150%)", "Massive (200%)" },
              getValue=function()
                local raw = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
                local pct = floor(raw * 100 + 0.5)
                if pct == 75  then return "Tiny (75%)"    end
                if pct == 90  then return "Small (90%)"   end
                if pct == 110 then return "Large (110%)"  end
                if pct == 125 then return "Huge (125%)"   end
                if pct == 150 then return "Giant (150%)"  end
                if pct == 200 then return "Massive (200%)" end
                return "Normal (100%)"
              end,
              setValue=function(v)
                local scale = 1.0
                if v == "Tiny (75%)"     then scale = 0.75
                elseif v == "Small (90%)"    then scale = 0.90
                elseif v == "Large (110%)"  then scale = 1.10
                elseif v == "Huge (125%)"   then scale = 1.25
                elseif v == "Giant (150%)"  then scale = 1.50
                elseif v == "Massive (200%)" then scale = 2.00 end
                if EllesmereUI.SetPanelScale then
                    EllesmereUI:SetPanelScale(scale)
                end
              end }
        );  y = y - h
        -- Cog with "Set UI Scale to 0.5333" toggle
        if not EllesmereUI._prebuilding then
            local rgn = uiScaleRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "UI Scale Options",
                rows = {
                    { type="toggle", label="Set UI Scale to 0.5333",
                      tooltip="Sets the UI scale to the exact pixel-perfect value used by other addons. EllesmereUI does not require this to be pixel perfect.",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.ppFixedScale or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.ppFixedScale = v
                          if v then
                              EllesmereUIDB.ppUIScaleAuto = false
                              EllesmereUIDB.ppUIScale = 0.5333333333
                              local mf = EllesmereUI._mainFrame
                              local panelScaleBefore
                              if mf then panelScaleBefore = mf:GetEffectiveScale() end
                              EllesmereUI.PP.SetUIScale(0.5333333333)
                              if mf and panelScaleBefore then
                                  local newEff = UIParent:GetEffectiveScale()
                                  if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
                              end
                              EllesmereUI:ShowConfirmPopup({
                                  title = "UI Scale Changed",
                                  message = "UI scale set to 0.5333. A reload is recommended.",
                                  confirmText = "Reload Now",
                                  cancelText = "Later",
                                  reload    = true,
                              })
                          end
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            EllesmereUI.MakeCogBtn(rgn, cogShow)
        end

        -- Row 3: EUI Buttons (merged button toggles) | Disable Sync Icons (+ cog)
        -- "EUI Buttons" merges the Pause Menu, Unlock Mode Menu and Minimap
        -- toggles into one checkbox-dropdown over the SAME backend variables: front-end grouping only, settings/defaults unchanged.
        local euiBtnItems = {
            { key = "pause",   label = "Hide Pause Menu Button",
              tooltip = "Hides the EllesmereUI button from the game's Escape/pause menu." },
            { key = "unlock",  label = "Hide Unlock Mode Menu Button",
              tooltip = "Hides the Unlock Mode button from the game's Escape/pause menu. You can still toggle Unlock Mode from the EUI options panel." },
            { key = "minimap", label = "Show Minimap Button" },
        }
        local euiBtnRow
        euiBtnRow, h = W:DualRow(parent, y,
            { type="dropdown", text="EUI Buttons",
              tooltip="Toggle EllesmereUI's optional buttons: the Escape menu buttons and the minimap button.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Disable Sync Icons",
              tooltip="Hides the sync icons on the sidebar module list.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideSyncIcons or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideSyncIcons = v
                  if EllesmereUI._refreshAllSyncIcons then EllesmereUI._refreshAllSyncIcons() end
              end }
        );  y = y - h
        -- EUI Buttons checkbox-dropdown (left region)
        if not EllesmereUI._prebuilding then
            local rgn = euiBtnRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                euiBtnItems,
                function(k)
                    if k == "pause" then
                        return EllesmereUIDB and EllesmereUIDB.hideGameMenuButton or false
                    elseif k == "unlock" then
                        return not EllesmereUIDB or EllesmereUIDB.hideUnlockMenuButton ~= false
                    elseif k == "minimap" then
                        return not (EllesmereUIDB and EllesmereUIDB.showMinimapButton == false)
                    end
                    return false
                end,
                function(k, v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if k == "pause" then
                        EllesmereUIDB.hideGameMenuButton = v
                    elseif k == "unlock" then
                        EllesmereUIDB.hideUnlockMenuButton = v
                    elseif k == "minimap" then
                        EllesmereUIDB.showMinimapButton = v
                        if v then EllesmereUI.ShowMinimapButton() else EllesmereUI.HideMinimapButton() end
                    end
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        -- Cog with "Only Hide Fully Synced" toggle on Disable Sync Icons (right region)
        if not EllesmereUI._prebuilding then
            local rgn = euiBtnRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Sync Icon Options",
                rows = {
                    { type="toggle", label="Only Hide Fully Synced",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.hideSyncIconsOnlyFull or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.hideSyncIconsOnlyFull = v
                          if EllesmereUI._refreshAllSyncIcons then EllesmereUI._refreshAllSyncIcons() end
                      end },
                },
            })
            EllesmereUI.MakeCogBtn(rgn, cogShow)
        end

        -- EUI Options Language: options-panel display language (auto-detects the client; untranslated text falls back to English).
        do
            -- _noLoc: the language list itself is never translated, so a player who booted the wrong language can always read and change it.
            local langValues = {
                _noLoc = true,
                ["auto"] = { text = EllesmereUI.L("Automatic (Client)") },
                ["enUS"] = { text = "English" },
                ["deDE"] = { text = "Deutsch" },
                ["frFR"] = { text = "Français" },
                ["esES"] = { text = "Español (EU)" },
                ["esMX"] = { text = "Español (LatAm)" },
                ["itIT"] = { text = "Italiano" },
                ["ptBR"] = { text = "Português (BR)" },
                ["ruRU"] = { text = "Русский" },
                ["koKR"] = { text = "한국어 (Korean)" },
                ["zhCN"] = { text = "简体中文 (Simplified Chinese)" },
                ["zhTW"] = { text = "繁體中文 (Traditional Chinese)" },
            }
            local langOrder = { "auto", "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
            -- Pin each entry to the plain font its own script needs, independent
            -- of whichever display locale is currently active.
            for _, key in ipairs(langOrder) do
                langValues[key].font = LP_FontFor(key)
            end
            -- "auto"'s own text is translated, not a fixed native-script name, so
            -- its script follows the ACTIVE locale rather than its own key.
            langValues["auto"].font = LP_FontFor(EllesmereUI.LOCALE)

            local function LanguageReload()
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reload Required",
                    message     = "Changing the language requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText  = "Later",
                    reload      = true,
                })
            end

            _, h = W:DualRow(parent, y,
                { type="dropdown", text="EUI Options Language",
                  tooltip="The display language for the EllesmereUI options panel. Auto follows your game client. Untranslated text falls back to English.",
                  values=langValues, order=langOrder,
                  getValue=function() return (EllesmereUIDB and EllesmereUIDB.displayLocale) or "auto" end,
                  setValue=function(v)
                      if v == "auto" then v = nil end
                      if EllesmereUIDB then EllesmereUIDB.displayLocale = v end
                      LanguageReload()
                  end },
                { type="toggle", text="Enable Tutorial Tips",
                  tooltip="Show one-time video guide badges next to new or complex features. Each badge disappears forever once clicked.",
                  getValue=function()
                      return not (EllesmereUIDB and EllesmereUIDB.tutorialTipsDisabled)
                  end,
                  setValue=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.tutorialTipsDisabled = (not v) and true or nil
                      if EllesmereUI.VideoGuides and EllesmereUI.VideoGuides.RefreshTips then
                          EllesmereUI.VideoGuides.RefreshTips()
                      end
                  end });  y = y - h
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Expand Less Common Settings",
              tooltip="Always show less common settings instead of collapsing them behind a Show Less Common link.",
              getValue=function() return (EllesmereUIDB and EllesmereUIDB.autoExpandLessCommon) == true end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoExpandLessCommon = v and true or nil
                  -- Cached pages hold the old expand state; drop them all so they rebuild on next visit, then rebuild this page in place.
                  EllesmereUI:InvalidatePageCache()
                  EllesmereUI:RefreshPage(true)
              end },
            { type="label", text="" });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "COMBAT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Camera Distance",
              min=1, max=2.6, step=0.1,
              getValue=function() return GetCVarNum("cameraDistanceMaxZoomFactor") end,
              setValue=function(v)
                v = floor(v * 10 + 0.5) / 10
                SetCVarSafe("cameraDistanceMaxZoomFactor", v)
              end },
            { type="toggle", text="Increase Game Image Quality",
              tooltip="Enables sharpening to improve image clarity. Especially noticeable at lower render scales.",
              getValue=function() return GetCVarBool("ResampleAlwaysSharpen") end,
              setValue=function(v)
                SetCVarSafe("ResampleAlwaysSharpen", v and "1" or "0")
              end });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Cast Actions on Key Down",
              tooltip="Keybinds respond on key down instead of key up. This helps make your abilities feel more responsive.",
              -- Without secure snippets the bars force key up (see
              -- ns.UseKeyDownEffective); the row shows that effective state.
              disabled=function() return not EllesmereUI.SecureSnippetsOK() end,
              disabledTooltip="This client cannot run the safeguard that stops a drag from casting the spell, so actions stay on key up until Blizzard fixes it.",
              rawTooltip=true,
              getValue=function() return GetCVarBool("ActionButtonUseKeyDown") and EllesmereUI.SecureSnippetsOK() end,
              setValue=function(v)
                SetCVarSafe("ActionButtonUseKeyDown", v and "1" or "0")
                if _G._EAB_ApplyKeyDown then _G._EAB_ApplyKeyDown() end
              end },
            { type="slider", text="Lag Tolerance",
              tooltip="This is the Spell Queue Window, it helps with making sure you can't queue up too many spells at once which makes the game feel laggy. Recommended settings are generally a minimum of 200 + your local ping. If you are unsure of exactly what this setting does, leave it at 400.",
              min=0, max=400, step=1,
              getValue=function() return GetCVarNum("SpellQueueWindow") end,
              setValue=function(v)
                SetCVarSafe("SpellQueueWindow", v)
              end });  y = y - h

        local FCT_FONT_DIR = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
        local fctFontValues = {
            ["default"]                                = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" },
            [FCT_FONT_DIR .. "Expressway.TTF"]         = { text = "Expressway",            font = FCT_FONT_DIR .. "Expressway.TTF" },
            [FCT_FONT_DIR .. "Avant Garde Naowh.ttf"]        = { text = "Avant Garde",   font = FCT_FONT_DIR .. "Avant Garde Naowh.ttf" },
            [FCT_FONT_DIR .. "Arial Bold.TTF"]         = { text = "Arial Bold",            font = FCT_FONT_DIR .. "Arial Bold.TTF" },
            [FCT_FONT_DIR .. "Poppins.ttf"]            = { text = "Poppins",               font = FCT_FONT_DIR .. "Poppins.ttf" },
            [FCT_FONT_DIR .. "FiraSans Medium.ttf"]    = { text = "Fira Sans Medium",      font = FCT_FONT_DIR .. "FiraSans Medium.ttf" },
            [FCT_FONT_DIR .. "Arial Narrow.ttf"]       = { text = "Arial Narrow",          font = FCT_FONT_DIR .. "Arial Narrow.ttf" },
            [FCT_FONT_DIR .. "Changa.ttf"]             = { text = "Changa",                font = FCT_FONT_DIR .. "Changa.ttf" },
            [FCT_FONT_DIR .. "Cinzel Decorative.ttf"]  = { text = "Cinzel Decorative",     font = FCT_FONT_DIR .. "Cinzel Decorative.ttf" },
            [FCT_FONT_DIR .. "Exo.otf"]                = { text = "Exo",                   font = FCT_FONT_DIR .. "Exo.otf" },
            [FCT_FONT_DIR .. "FiraSans Bold.ttf"]      = { text = "Fira Sans Bold",        font = FCT_FONT_DIR .. "FiraSans Bold.ttf" },
            [FCT_FONT_DIR .. "FiraSans Light.ttf"]     = { text = "Fira Sans Light",       font = FCT_FONT_DIR .. "FiraSans Light.ttf" },
            [FCT_FONT_DIR .. "Future X Black.otf"]     = { text = "Future X Black",        font = FCT_FONT_DIR .. "Future X Black.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow Ultra.otf"] = { text = "Gotham Narrow Ultra",  font = FCT_FONT_DIR .. "Gotham Narrow Ultra.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow.otf"]      = { text = "Gotham Narrow",         font = FCT_FONT_DIR .. "Gotham Narrow.otf" },
            [FCT_FONT_DIR .. "Russo One.ttf"]          = { text = "Russo One",             font = FCT_FONT_DIR .. "Russo One.ttf" },
            [FCT_FONT_DIR .. "Ubuntu.ttf"]             = { text = "Ubuntu",                font = FCT_FONT_DIR .. "Ubuntu.ttf" },
            [FCT_FONT_DIR .. "Homespun.ttf"]           = { text = "Homespun",              font = FCT_FONT_DIR .. "Homespun.ttf" },
            ["Fonts\\FRIZQT__.TTF"]                    = { text = "Friz Quadrata",         font = "Fonts\\FRIZQT__.TTF" },
            ["Fonts\\ARIALN.TTF"]                      = { text = "Arial",                 font = "Fonts\\ARIALN.TTF" },
            ["Fonts\\MORPHEUS.TTF"]                    = { text = "Morpheus",              font = "Fonts\\MORPHEUS.TTF" },
            ["Fonts\\skurri.ttf"]                      = { text = "Skurri",                font = "Fonts\\skurri.ttf" },
        }
        local fctFontOrder = {
            "default",
            FCT_FONT_DIR .. "Expressway.TTF",
            FCT_FONT_DIR .. "Avant Garde Naowh.ttf",
            FCT_FONT_DIR .. "Arial Bold.TTF",
            FCT_FONT_DIR .. "Poppins.ttf",
            FCT_FONT_DIR .. "FiraSans Medium.ttf",
            "---",
            FCT_FONT_DIR .. "Arial Narrow.ttf",
            FCT_FONT_DIR .. "Changa.ttf",
            FCT_FONT_DIR .. "Cinzel Decorative.ttf",
            FCT_FONT_DIR .. "Exo.otf",
            FCT_FONT_DIR .. "FiraSans Bold.ttf",
            FCT_FONT_DIR .. "FiraSans Light.ttf",
            FCT_FONT_DIR .. "Future X Black.otf",
            FCT_FONT_DIR .. "Gotham Narrow Ultra.otf",
            FCT_FONT_DIR .. "Gotham Narrow.otf",
            FCT_FONT_DIR .. "Russo One.ttf",
            FCT_FONT_DIR .. "Ubuntu.ttf",
            FCT_FONT_DIR .. "Homespun.ttf",
            "Fonts\\FRIZQT__.TTF",
            "Fonts\\ARIALN.TTF",
            "Fonts\\MORPHEUS.TTF",
            "Fonts\\skurri.ttf",
        }
        if EllesmereUI.AppendSharedMediaFonts then
            EllesmereUI.AppendSharedMediaFonts(fctFontValues, fctFontOrder)
        end
        _, h = W:DualRow(parent, y,
            { type="slider", text="Combat Text Size",
              min=0.5, max=2.5, step=0.1,
              getValue=function() return GetCVarNum("WorldTextScale_v2") end,
              setValue=function(v)
                v = floor(v * 10 + 0.5) / 10
                SetCVarSafe("WorldTextScale_v2", v)
              end },
            { type="dropdown", text="Combat Text Font",
              tooltip="WARNING: This feature requires you to re-log or restart WoW to take effect.",
              tooltipOpts={ color={1, 0.3, 0.3} },
              values = fctFontValues, order = fctFontOrder,
              getValue=function()
                return (EllesmereUIDB and EllesmereUIDB.fctFont) or "default"
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                if v == "default" then
                    EllesmereUIDB.fctFont = nil
                    EllesmereUIDB.fctFontPath = nil
                    EllesmereUIDB.fctFontPathFor = nil
                else
                    EllesmereUIDB.fctFont = v
                    -- smf: keys cache their resolved path for the next login's
                    -- early window; see ApplyCombatTextFont in Startup.
                    local e = v:match("^smf:") and fctFontValues[v]
                    EllesmereUIDB.fctFontPath = e and e.font
                    EllesmereUIDB.fctFontPathFor = e and v
                end
                EllesmereUI:ShowConfirmPopup({
                    title   = "Logout Required",
                    message = "Combat text font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                    confirmText = "Okay",
                    cancelText  = "Later",
                })
              end });  y = y - h

        local showDmgRow
        showDmgRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Combat Damage Text",
              getValue=function()
                return GetCVarBool("floatingCombatTextCombatDamage_v2")
              end,
              setValue=function(v)
                SetCVarSafe("floatingCombatTextCombatDamage_v2", v and "1" or "0")
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Combat Healing Text",
              getValue=function() return GetCVarBool("floatingCombatTextCombatHealing_v2") end,
              setValue=function(v)
                SetCVarSafe("floatingCombatTextCombatHealing_v2", v and "1" or "0")
              end });  y = y - h

        -- Inline cog on "Show Combat Damage Text" left region for pet damage sub-settings
        if not EllesmereUI._prebuilding then
            local dmgOff = function() return not GetCVarBool("floatingCombatTextCombatDamage_v2") end
            local leftRgn = showDmgRow._leftRegion

            local _, dmgCogShow = EllesmereUI.BuildCogPopup({
                title = "Damage Text Settings",
                rows = {
                    { type="toggle", label="Show Periodic Damage",
                      get=function() return GetCVarBool("floatingCombatTextCombatLogPeriodicSpells_v2") end,
                      set=function(v) SetCVarSafe("floatingCombatTextCombatLogPeriodicSpells_v2", v and "1" or "0") end },
                    { type="toggle", label="Show Pet Melee Damage",
                      get=function() return GetCVarBool("floatingCombatTextPetMeleeDamage_v2") end,
                      set=function(v) SetCVarSafe("floatingCombatTextPetMeleeDamage_v2", v and "1" or "0") end },
                    { type="toggle", label="Show Pet Spell Damage",
                      get=function() return GetCVarBool("floatingCombatTextPetSpellDamage_v2") end,
                      set=function(v) SetCVarSafe("floatingCombatTextPetSpellDamage_v2", v and "1" or "0") end },
                },
            })

            EllesmereUI.MakeCogBtn(leftRgn, dmgCogShow, nil, nil, dmgOff, "Show Combat Damage Text")
        end

        -- Swiftmend Brightness Fix (Druid only)
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Prevent Swiftmend Icon Dim",
                  tooltip="Prevents Blizzard from dimming Swiftmend on action bars and CDM based on Efflorescence state.",
                  getValue=function()
                      return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
                  end,
                  setValue=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.brightenSwiftmend = v
                      if v then
                          if _G._EAB_ScanSwiftmend then _G._EAB_ScanSwiftmend() end
                          if _G._ECDM_ScanSwiftmend then _G._ECDM_ScanSwiftmend() end
                      end
                  end },
                { type="label", text="" }
            ); y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  DEVELOPER -- both toggles are duplicated in Quality of Life
        --  (Suppress Lua Errors) and Blizzard UI Enhanced (Show Spell ID on
        --  Tooltip): hidden here when BOTH modules are loaded, shown if either is missing so the settings stay reachable.
        -------------------------------------------------------------------
        local _devDupesAvailable = C_AddOns and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("EllesmereUIQoL")
            and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
        if not _devDupesAvailable then
            _, h = W:SectionHeader(parent, "DEVELOPER", y);  y = y - h

            _, h = W:DualRow(parent, y,
                { type="toggle", text="Suppress Lua Errors",
                  getValue=function()
                    return not (EllesmereUIDB and EllesmereUIDB.suppressErrors == false)
                  end,
                  setValue=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.suppressErrors = v
                    SetCVarSafe("scriptErrors", v and "0" or "1")
                  end },
                { type="toggle", text="Show Spell ID on Tooltip",
                  getValue=function()
                    return EllesmereUIDB and EllesmereUIDB.showSpellID or false
                  end,
                  setValue=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.showSpellID = v
                    -- Engine-side combat aura-ID CVar rides this setting.
                    if EllesmereUI.SyncAuraSpellIDCVar then EllesmereUI.SyncAuraSpellIDCVar() end
                  end });  y = y - h

            _, h = W:Spacer(parent, y, 20);  y = y - h
        end

        -- Reset ALL EUI Addon Settings (wide warning button)
        y = y - 30  -- spacer
        do
            local BTN_W, BTN_H = 300, 38
            local lerp = EllesmereUI.lerp
            local DARK_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("TOP", parent, "TOP", 0, y)
            btn:SetFrameLevel(parent:GetFrameLevel() + 5)
            btn:SetAlpha(0.85)
            local brd = EllesmereUI.MakeBorder(btn, 0.8, 0.2, 0.2, 0.5, EllesmereUI.PanelPP)
            local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
            bg:SetAllPoints()
            local lbl = EllesmereUI.MakeFont(btn, 13, nil, 0.9, 0.3, 0.3)
            lbl:SetAlpha(0.7)
            lbl:SetPoint("CENTER")
            lbl:SetText(EllesmereUI.L("Reset ALL EUI Addon Settings"))
            do
                local FADE_DUR = 0.1
                local progress, target = 0, 0
                local function Apply(t)
                    lbl:SetTextColor(lerp(0.9, 1, t), lerp(0.3, 0.35, t), lerp(0.3, 0.35, t), lerp(0.7, 1, t))
                    brd:SetColor(0.8, 0.2, 0.2, lerp(0.5, 0.8, t))
                end
                local function OnUpdate(self, elapsed)
                    local dir = (target == 1) and 1 or -1
                    progress = progress + dir * (elapsed / FADE_DUR)
                    if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                        progress = target; self:SetScript("OnUpdate", nil)
                    end
                    Apply(progress)
                end
                btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
                btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
            end
            btn:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reset ALL Settings",
                    message     = "Are you sure you want to reset ALL EUI addon settings to their defaults? This will reload your UI.",
                    disclaimer  = "This resets every EUI addon, not just the current one.",
                    confirmText = "Reset All & Reload",
                    cancelText  = "Cancel",
                    onConfirm   = function()
                        -- Nuclear wipe: same logic as the beta-exit popup
                        local svNames = {
                            "EllesmereUIActionBarsDB",
                            "EllesmereUIAuraBuffRemindersDB",
                            "EllesmereUICooldownManagerDB",
                            "EllesmereUINameplatesDB",
                            "EllesmereUIResourceBarsDB",
                            "EllesmereUIUnitFramesDB",
                        }
                        for _, name in ipairs(svNames) do
                            _G[name] = {}
                        end
                        local oldScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
                        local oldScaleAuto = EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto
                        -- Preserve friend group data across reset
                        local oldGlobal = EllesmereUIDB and EllesmereUIDB.global
                        local savedFriends
                        if oldGlobal then
                            savedFriends = {
                                friendGroups = oldGlobal.friendGroups,
                                friendAssignments = oldGlobal.friendAssignments,
                                friendGroupOrder = oldGlobal.friendGroupOrder,
                                friendGroupColors = oldGlobal.friendGroupColors,
                                friendNotes = oldGlobal.friendNotes,
                                friendFavCollapsed = oldGlobal.friendFavCollapsed,
                                friendPendingCollapsed = oldGlobal.friendPendingCollapsed,
                                friendUngroupedCollapsed = oldGlobal.friendUngroupedCollapsed,
                            }
                        end
                        -- Preserve QoL settings (stored on EllesmereUIDB root)
                        local qolKeys = {
                            "autoOpenContainers", "autoSellJunk", "autoRepair",
                            "autoRepairGuild", "hideScreenshotStatus", "autoUnwrapCollections",
                            "trainAllButton", "ahCurrentExpansion", "quickLoot",
                            "autoFillDelete", "skipCinematics", "skipCinematicsAuto",
                            "autoInsertKeystone", "quickSignup",
                            "persistSignupNote", "signupNote", "hideBlizzardPartyFrame",
                            "instanceResetAnnounce", "instanceResetAnnounceMsg",
                            "healthMacroEnabled", "healthMacroPrio1", "healthMacroPrio2",
                            "healthMacroPrio3", "foodMacroEnabled", "macroFactory",
                        }
                        local savedQoL = {}
                        for _, k in ipairs(qolKeys) do
                            if EllesmereUIDB[k] ~= nil then
                                savedQoL[k] = EllesmereUIDB[k]
                            end
                        end
                        _G["EllesmereUIDB"] = {}
                        EllesmereUIDB = _G["EllesmereUIDB"]
                        if oldScale then EllesmereUIDB.ppUIScale = oldScale end
                        if oldScaleAuto ~= nil then EllesmereUIDB.ppUIScaleAuto = oldScaleAuto end
                        if savedFriends then
                            if not EllesmereUIDB.global then EllesmereUIDB.global = {} end
                            for k, v in pairs(savedFriends) do
                                EllesmereUIDB.global[k] = v
                            end
                        end
                        for k, v in pairs(savedQoL) do
                            EllesmereUIDB[k] = v
                        end
                        ReloadUI()
                    end,
                })
            end)
            y = y - BTN_H
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Quick Setup page (curated quick-access to key settings per addon).
    --  Action Bars rows are live; rest are placeholders until those addons register their core settings.
    ---------------------------------------------------------------------------
    local function BuildCoreOptionsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- ACTION BARS
        _, h = W:SectionHeader(parent, "ACTION BARS", y);  y = y - h

        local EAB = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local function EAB_db()
            if EAB and EAB.db then return EAB.db.profile end
            return nil
        end

        _, h = W:Toggle(parent, "Modern Icons", y,
            function()
                local db = EAB_db()
                return db and db.squareIcons or false
            end,
            function(v)
                local db = EAB_db()
                if not db then return end
                db.squareIcons = v
                if EAB and EAB.ApplyShapes then EAB:ApplyShapes() end
                if EAB and EAB.ApplyBorders then EAB:ApplyBorders() end
            end);  y = y - h

        _, h = W:Slider(parent, "Icon Zoom", y, 0, 10, 0.5,
            function()
                local db = EAB_db()
                return db and (db.iconZoom or 5.5) or 5.5
            end,
            function(v)
                local db = EAB_db()
                if not db then return end
                db.iconZoom = v
                if EAB and EAB.ApplyBorders then
                    EAB:ApplyBorders()
                end
                if EAB and EAB.ApplyShapes then
                    EAB:ApplyShapes()
                end
            end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- NAMEPLATES
        _, h = W:SectionHeader(parent, "NAMEPLATES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- UNIT FRAMES
        _, h = W:SectionHeader(parent, "UNIT FRAMES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- BAR GLOWS
        _, h = W:SectionHeader(parent, "BAR GLOWS", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- CONSUMABLES
        _, h = W:SectionHeader(parent, "CONSUMABLES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- CURSOR CIRCLE
        _, h = W:SectionHeader(parent, "CURSOR CIRCLE", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- BEACON REMINDERS
        _, h = W:SectionHeader(parent, "BEACON REMINDERS", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Re-read live CVars on panel open: widgets call their getter on each build, so a rebuild picks up external changes (addons, /console).
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI:GetActiveModule() == GLOBAL_KEY then
            EllesmereUI:RefreshPage()
        end
    end)

    ---------------------------------------------------------------------------
    --  Colors Page
    ---------------------------------------------------------------------------
    local CLASS_ORDER = EllesmereUI.CLASS_TOKEN_ORDER
    local CLASS_LABELS = {
        WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
        ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
        SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
        MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "Demon Hunter",
        EVOKER = "Evoker",
    }
    local POWER_LABELS = {
        MANA = "Mana", RAGE = "Rage", FOCUS = "Focus", ENERGY = "Energy",
        RUNIC_POWER = "Runic Power", LUNAR_POWER = "Astral Power",
        INSANITY = "Insanity", MAELSTROM = "Maelstrom", FURY = "Fury",
        PAIN = "Pain", EBON_MIGHT = "Ebon Might",
    }
    local RESOURCE_LABELS = {
        ComboPoints = "Combo Points", HolyPower = "Holy Power",
        Chi = "Chi", SoulShards = "Soul Shards",
        ArcaneCharges = "Arcane Charges", Essence = "Essence",
        Runes = "Runes",
        SoulFragments = "Soul Fragments",
    }
    local GRADIENT_DIR_VALUES = {
        ["HORIZONTAL"] = "Left to Right",
        ["HORIZONTAL_REV"] = "Right to Left",
        ["VERTICAL"] = "Top to Bottom",
        ["VERTICAL_REV"] = "Bottom to Top",
    }
    local GRADIENT_DIR_ORDER = { "HORIZONTAL", "HORIZONTAL_REV", "VERTICAL", "VERTICAL_REV" }

    local function BuildColorsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local MakeFont = EllesmereUI.MakeFont
        -- Swatches read/write the EFFECTIVE palette (per-profile -> active
        -- profile's own; global -> shared source profile's). Every editable
        -- case IS the active profile's table; the one locked case (global mode on a non-source profile) is gated by an overlay below.
        local GetCustomColorsDB = EllesmereUI.GetCustomColorsDB
        local CLASS_COLOR_MAP = EllesmereUI.CLASS_COLOR_MAP
        local DEFAULT_POWER_COLORS = EllesmereUI.DEFAULT_POWER_COLORS
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 20

        parent._showRowDivider = true

        -- Helper to save a color entry
        local function SaveColorEntry(category, key, data)
            local db = GetCustomColorsDB()
            if not db[category] then db[category] = {} end
            db[category][key] = data
            EllesmereUI.ApplyColorsToOUF()
        end

        -------------------------------------------------------------------
        --  Shared 4-column color grid builder
        -------------------------------------------------------------------
        local GRID_COLS     = 4
        local GRID_ROW_H    = 50
        local GRID_PAD      = CONTENT_PAD
        local GRID_SIDE_PAD = 20
        local SWATCH_SZ     = 20

        -- items = { { label, classToken, getColor, setColor, resetFn }, ... }
        local function BuildColorGrid(par, yPos, items)            local totalRows = math.ceil(#items / GRID_COLS)
            local totalW = par:GetWidth() - GRID_PAD * 2
            local colW = math.floor(totalW / GRID_COLS)

            for row = 0, totalRows - 1 do
                local rowFrame = CreateFrame("Frame", nil, par)
                PP.Size(rowFrame, totalW, GRID_ROW_H)
                PP.Point(rowFrame, "TOPLEFT", par, "TOPLEFT", GRID_PAD, yPos - row * GRID_ROW_H)
                rowFrame._skipRowDivider = true
                EllesmereUI.RowBg(rowFrame, par)

                -- Column dividers
                for d = 1, GRID_COLS - 1 do
                    local div = rowFrame:CreateTexture(nil, "ARTWORK")
                    div:SetColorTexture(1, 1, 1, 0.06)
                    if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
                    div:SetWidth(1)
                    local xPos = d * colW
                    PP.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                    PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
                end

                for col = 0, GRID_COLS - 1 do
                    local idx = row * GRID_COLS + col + 1
                    local item = items[idx]
                    if not item then break end

                    local cell = CreateFrame("Frame", nil, rowFrame)
                    cell:SetSize(colW, GRID_ROW_H)
                    cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                    -- Class-colored label (or white for power colors)
                    local cr, cg, cb = 1, 1, 1
                    if item.classToken then
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classToken]
                        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                    end
                    local label = MakeFont(cell, 13, nil, cr, cg, cb)
                    label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                    label:SetText(item.label)

                    -- Color swatch (right side)
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(cell, cell:GetFrameLevel() + 2,
                        function()
                            local c = item.getColor()
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            local c = item.getColor()
                            c.r = r; c.g = g; c.b = b
                            item.setColor(c)
                            local rl = EllesmereUI._widgetRefreshList
                            if rl then for i2 = 1, #rl do rl[i2]() end end
                        end, false, SWATCH_SZ)
                    swatch:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
                    -- Repaint on page refresh/show (SelectPage re-runs the refresh list on show) so swatches survive a profile/global-source change.
                    EllesmereUI.RegisterWidgetRefresh(updateSwatch)

                    -- Undo (reset) button
                    local undoBtn = CreateFrame("Button", nil, cell)
                    undoBtn:SetSize(18, 18)
                    undoBtn:SetPoint("RIGHT", swatch, "LEFT", -10, 0)
                    undoBtn:SetFrameLevel(cell:GetFrameLevel() + 3)
                    undoBtn:SetAlpha(0.3)
                    local undoTex = undoBtn:CreateTexture(nil, "ARTWORK")
                    undoTex:SetAllPoints()
                    undoTex:SetTexture(EllesmereUI.UNDO_ICON)
                    undoBtn:SetScript("OnEnter", function(self)
                        self:SetAlpha(0.6)
                        EllesmereUI.ShowWidgetTooltip(self, "Reset to default")
                    end)
                    undoBtn:SetScript("OnLeave", function(self)
                        self:SetAlpha(0.3)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    undoBtn:SetScript("OnClick", function()
                        item.resetFn()
                        EllesmereUI.ApplyColorsToOUF()
                        updateSwatch()
                        local rl = EllesmereUI._widgetRefreshList
                        if rl then for i2 = 1, #rl do rl[i2]() end end
                    end)
                end
            end

            return totalRows * GRID_ROW_H
        end

        -------------------------------------------------------------------
        --  DARK MODE section (per-profile, never subject to "Apply to All
        --  Profiles"). One palette drives Unit Frames, Raid Frames and
        --  Resource Bars (RB ignores the opacity sliders). "Darken" sliders
        --  blacken class/power/class-resource colours inside the colour getters, reaching every module with no extra wiring.
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DARK MODE", y);  y = y - h
        do
            local DM_DEF = EllesmereUI.DEFAULT_DARK_MODE

            -- Master switches: pure views over their group of per-module providers (on only when every provider is on). Left drives Unit
            -- Frames + Raid Frames, right the class resource bar alone.
            local function _dmIsRB(p) return p.id == "resourceBars" end
            local function _dmNotRB(p) return p.id ~= "resourceBars" end
            local dmMasterRow
            dmMasterRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Dark Mode",
                  tooltip = "Turns Dark Mode on or off for Unit Frames and Raid Frames at once.",
                  getValue = function() return EllesmereUI.IsDarkModeAllOn(_dmNotRB) end,
                  setValue = function(v)
                      EllesmereUI.SetDarkModeAll(v, _dmNotRB)
                      EllesmereUI:RefreshPage()
                  end },
                { type = "toggle", text = "Dark Mode (Class Resource Bar)",
                  tooltip = "Turns Dark Mode on or off for the class resource bar.",
                  getValue = function() return EllesmereUI.IsDarkModeAllOn(_dmIsRB) end,
                  setValue = function(v)
                      EllesmereUI.SetDarkModeAll(v, _dmIsRB)
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            -- MAIN master writes the UF+RF dark flags = the Dark Mode conditional-override condition's inputs, so it locks during a Dark Mode
            -- conditional edit session (an override must not capture a change that flips its own condition). Class Resource Bar master is NOT
            -- a condition input (DarkModeMasterOn excludes it) and stays editable. SetDarkModeAll's tail rechecks the condition live for both.
            if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
                EllesmereUI.SpecOverrides_AttachEditLock(dmMasterRow._leftRegion,
                    "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override",
                    EllesmereUI.SpecOverrides_DarkCondEditActive)
            end

            -- Row 1: Dark Mode Fill Color | Dark Mode Fill Opacity
            _, h = W:DualRow(parent, y,
                { type = "colorpicker", text = "Dark Mode Fill Color", hasAlpha = false,
                  tooltip = "The flat fill colour bars use when Dark Mode is enabled (Unit Frames, Raid Frames, Resource Bars).",
                  getValue = function()
                      local d = EllesmereUI.GetDarkModeDB()
                      return d.fillR or DM_DEF.fillR, d.fillG or DM_DEF.fillG, d.fillB or DM_DEF.fillB, 1
                  end,
                  setValue = function(r, g, b)
                      local d = EllesmereUI.GetDarkModeDB()
                      d.fillR, d.fillG, d.fillB = r, g, b
                      EllesmereUI.RefreshDarkMode()
                  end },
                { type = "slider", text = "Dark Mode Fill Opacity",
                  min = 0, max = 100, step = 5,
                  tooltip = "Fill opacity for Dark Mode bars. Applies to Unit Frames and Raid Frames only (Resource Bars ignore it).",
                  getValue = function()
                      local d = EllesmereUI.GetDarkModeDB()
                      return math.floor((d.fillA or DM_DEF.fillA) * 100 + 0.5)
                  end,
                  setValue = function(v)
                      local d = EllesmereUI.GetDarkModeDB()
                      d.fillA = v / 100
                      EllesmereUI.RefreshDarkMode()
                  end });  y = y - h

            -- Row 2: Background Color | Background Opacity
            _, h = W:DualRow(parent, y,
                { type = "colorpicker", text = "Background Color", hasAlpha = false,
                  tooltip = "The background colour behind Dark Mode bars (Unit Frames, Raid Frames, Resource Bars).",
                  getValue = function()
                      local d = EllesmereUI.GetDarkModeDB()
                      return d.bgR or DM_DEF.bgR, d.bgG or DM_DEF.bgG, d.bgB or DM_DEF.bgB, 1
                  end,
                  setValue = function(r, g, b)
                      local d = EllesmereUI.GetDarkModeDB()
                      d.bgR, d.bgG, d.bgB = r, g, b
                      EllesmereUI.RefreshDarkMode()
                  end },
                { type = "slider", text = "Background Opacity",
                  min = 0, max = 100, step = 5,
                  tooltip = "Background opacity for Dark Mode bars. Applies to Unit Frames and Raid Frames only (Resource Bars ignore it).",
                  getValue = function()
                      local d = EllesmereUI.GetDarkModeDB()
                      return math.floor((d.bgA or DM_DEF.bgA) * 100 + 0.5)
                  end,
                  setValue = function(v)
                      local d = EllesmereUI.GetDarkModeDB()
                      d.bgA = v / 100
                      EllesmereUI.RefreshDarkMode()
                  end });  y = y - h

            -- Row 3: Class Color Darken | Power Color Darken
            _, h = W:DualRow(parent, y,
                { type = "slider", text = "Class Color Darken",
                  min = 0, max = 100, step = 5,
                  tooltip = "Blackens every class colour by this amount, everywhere class colours are used.",
                  getValue = function() return EllesmereUI.GetDarkModeDB().classDarken or 0 end,
                  setValue = function(v)
                      EllesmereUI.GetDarkModeDB().classDarken = v
                      EllesmereUI.RefreshDarkMode()
                  end },
                { type = "slider", text = "Power Color Darken",
                  min = 0, max = 100, step = 5,
                  tooltip = "Blackens every power colour by this amount, everywhere power colours are used.",
                  getValue = function() return EllesmereUI.GetDarkModeDB().powerDarken or 0 end,
                  setValue = function(v)
                      EllesmereUI.GetDarkModeDB().powerDarken = v
                      EllesmereUI.RefreshDarkMode()
                  end });  y = y - h

            -- Row 4: Resource Color Darken | BG Power Color Darken
            _, h = W:DualRow(parent, y,
                { type = "slider", text = "Resource Color Darken",
                  min = 0, max = 100, step = 5,
                  tooltip = "Blackens every class-resource colour by this amount, everywhere class-resource colours are used.",
                  getValue = function() return EllesmereUI.GetDarkModeDB().resourceDarken or 0 end,
                  setValue = function(v)
                      EllesmereUI.GetDarkModeDB().resourceDarken = v
                      EllesmereUI.RefreshDarkMode()
                  end },
                { type = "slider", text = "BG Power Color Darken",
                  min = 0, max = 100, step = 5,
                  tooltip = "Blackens power-colored Power Bar backgrounds (Unit Frames and Raid Frames) by this amount, on top of Power Color Darken.",
                  getValue = function() return EllesmereUI.GetDarkModeDB().powerBgDarken or 0 end,
                  setValue = function(v)
                      EllesmereUI.GetDarkModeDB().powerBgDarken = v
                      EllesmereUI.RefreshDarkMode()
                  end });  y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  GLOBAL COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GLOBAL COLORS", y);  y = y - h
        do
            local profileOrder = select(1, EllesmereUI.GetProfileList()) or {}
            local pullValues = {}
            for _, n in ipairs(profileOrder) do pullValues[n] = n end
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Apply to All Profiles",
                  tooltip="On (default): one profile's palette is shared across every profile (chosen via Pull Colors From). Off: each profile keeps its own custom colors (Power, Class Resource, Class, Resource).",
                  -- Default ON (nil treated as on) = global colours for all profiles.
                  getValue=function() return EllesmereUIDB.colorsApplyToAllProfiles ~= false end,
                  setValue=function(v)
                      EllesmereUIDB.colorsApplyToAllProfiles = v
                      EllesmereUI.ApplyColorsToOUF()
                      -- Force rebuild: toggle flips the dropdown's enabled state and the editing-gate, which a fast-path refresh won't redo.
                      EllesmereUI:RefreshPage(true)
                  end },
                -- Global-mode source: which single profile's palette all profiles use. Enabled only while "Apply to All Profiles" is ON.
                { type="dropdown", text="Pull Colors From",
                  values=pullValues, order=profileOrder,
                  disabled=function() return EllesmereUIDB.colorsApplyToAllProfiles == false end,
                  disabledTooltip="Apply to All Profiles",
                  getValue=function() return EllesmereUIDB.colorsPullFrom or profileOrder[1] end,
                  setValue=function(v)
                      EllesmereUIDB.colorsPullFrom = v
                      EllesmereUI.ApplyColorsToOUF()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
        end
        -- Colour-edit gate: when this profile mirrors another's colours (GLOBAL mode on a different profile), each section grid gets its OWN
        -- click-blocking overlay (built at the end of this builder). Grid bounds {top, bot} are captured into _colorGates as sections lay out.
        local _colorGates = {}
        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CLASS COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CLASS COLORS", y);  y = y - h
        _colorGates[1] = { top = y }

        local classItems = {}
        for _, token in ipairs(CLASS_ORDER) do
            -- Class names are Blizzard-localized in every client language; use the client's own names, falling back to our English labels.
            local lbl = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or CLASS_LABELS[token]
            local def = CLASS_COLOR_MAP[token] or { r = 1, g = 1, b = 1 }
            classItems[#classItems + 1] = {
                label = EllesmereUI.L(lbl),
                classToken = token,
                getColor = function()
                    local db = GetCustomColorsDB()
                    if db.class and db.class[token] then return db.class[token] end
                    return { r = def.r, g = def.g, b = def.b }
                end,
                setColor = function(c)
                    SaveColorEntry("class", token, c)
                end,
                resetFn = function()
                    local db = GetCustomColorsDB()
                    if db.class then db.class[token] = nil end
                end,
            }
        end

        h = BuildColorGrid(parent, y, classItems)
        y = y - h
        _colorGates[1].bot = y

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  POWER COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "POWER COLORS", y);  y = y - h
        _colorGates[2] = { top = y }

        local POWER_ORDER = {
            "MANA", "RAGE", "FOCUS", "ENERGY", "RUNIC_POWER", "FURY",
            "LUNAR_POWER", "INSANITY", "MAELSTROM", "EBON_MIGHT",
        }
        local powerItems = {}
        for _, pk in ipairs(POWER_ORDER) do
            -- Power names are Blizzard global strings (already localized); fall back to our English labels for non-standard entries (e.g. Ebon Might).
            local lbl = _G[pk] or POWER_LABELS[pk] or pk
            local def = DEFAULT_POWER_COLORS[pk] or { r = 1, g = 1, b = 1 }
            powerItems[#powerItems + 1] = {
                label = EllesmereUI.L(lbl),
                classToken = nil,
                getColor = function()
                    local db = GetCustomColorsDB()
                    if db.power and db.power[pk] then return db.power[pk] end
                    return { r = def.r, g = def.g, b = def.b }
                end,
                setColor = function(c)
                    SaveColorEntry("power", pk, c)
                end,
                resetFn = function()
                    EllesmereUI.ResetPowerColor(pk)
                end,
            }
        end

        h = BuildColorGrid(parent, y, powerItems)
        y = y - h
        _colorGates[2].bot = y

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CLASS RESOURCE COLORS section -- standalone swatches mirroring the
        --  POWER COLORS pattern, saved under the "classResource" custom-colors category (not yet consumed).
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CLASS RESOURCE COLORS", y);  y = y - h
        _colorGates[3] = { top = y }
        do
            -- Order + labels only; defaults live in the shared DEFAULT_CLASS_RESOURCE_COLORS, the source the resource bar's "Class Resource
            -- Color" fill mode reads.
            local items = {
                { key = "ComboPoints",     label = "Combo Points"     },
                { key = "Runes",           label = "Runes"            },
                { key = "SoulShards",      label = "Soul Shards"      },
                { key = "HolyPower",       label = "Holy Power"       },
                { key = "ArcaneCharges",   label = "Arcane Charges"   },
                { key = "Icicles",         label = "Icicles"          },
                { key = "Chi",             label = "Chi"              },
                { key = "Essence",         label = "Essence"          },
                { key = "SoulFragments",   label = "Soul Fragments"   },
                { key = "MaelstromWeapon", label = "Maelstrom Weapon" },
                { key = "TipOfTheSpear",   label = "Tip of the Spear" },
                { key = "WhirlwindStacks", label = "Whirlwind Stacks" },
                { key = "SweepingStrikes", label = "Sweeping Strikes" },
            }
            local resourceItems = {}
            for _, it in ipairs(items) do
                local key = it.key
                resourceItems[#resourceItems + 1] = {
                    label = EllesmereUI.L(it.label),
                    getColor = function()
                        return EllesmereUI.GetClassResourceColor(key)
                            or { r = 1, g = 1, b = 1 }
                    end,
                    setColor = function(c)
                        SaveColorEntry("classResource", key, c)
                    end,
                    resetFn = function()
                        local cdb = GetCustomColorsDB()
                        if cdb.classResource then cdb.classResource[key] = nil end
                    end,
                }
            end
            h = BuildColorGrid(parent, y, resourceItems)
        end
        y = y - h
        _colorGates[3].bot = y

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- Colour-edit gate: in GLOBAL mode the shared palette comes from ONE profile, so editing is blocked while viewing any other. ONE overlay
        -- PER SECTION, sized to that section's grid. Always created; a shared refresh callback shows/hides them and updates the message, so they
        -- stay correct after a profile or global-source change even on a cached page.
        do
            local gates = {}
            local CPAD = EllesmereUI.CONTENT_PAD or 20  -- side inset so the overlay matches the grid content width
            local function MakeColorGate(topY, botY)
                if not topY or not botY then return end
                local ov = CreateFrame("Frame", nil, parent)
                ov:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD, topY)
                ov:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CPAD, topY)
                ov:SetHeight(math.abs(botY - topY))
                ov:SetFrameLevel(parent:GetFrameLevel() + 100)
                ov:EnableMouse(true)
                ov:Hide()
                local tex = ov:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                tex:SetColorTexture(13/255, 17/255, 25/255, 0.98)
                local msg = EllesmereUI.MakeFont(ov, 13, nil, 1, 1, 1)
                msg:SetTextColor(1, 1, 1, 0.56)
                msg:SetWidth(parent:GetWidth() - 100)
                msg:SetJustifyH("CENTER")
                msg:SetPoint("CENTER", ov, "CENTER", 0, 0)
                ov._msg = msg
                gates[#gates + 1] = ov
            end
            for _, g in ipairs(_colorGates) do MakeColorGate(g.top, g.bot) end
            local function UpdateColorGate()
                local locked = EllesmereUI.IsColorEditingLocked and EllesmereUI.IsColorEditingLocked()
                local text
                if locked then
                    local p = EllesmereUI.GetProfilesDB()
                    local srcName = EllesmereUIDB.colorsPullFrom or (p.profileOrder and p.profileOrder[1]) or ""
                    text = EllesmereUI.Lf("Colors are shared globally from the \"%1$s\" profile.\nSwitch to it (or set Pull Colors From to this profile) to edit.", srcName)
                end
                for _, ov in ipairs(gates) do
                    if locked then
                        ov._msg:SetText(text)
                        ov:Show()
                    else
                        ov:Hide()
                    end
                end
            end
            UpdateColorGate()
            EllesmereUI.RegisterWidgetRefresh(UpdateColorGate)
        end

        return math.abs(y)
    end



    ---------------------------------------------------------------------------
    --  Profiles page
    ---------------------------------------------------------------------------

    -- Red warning string from a decoded payload's meta vs the current client; nil when nothing mismatches. skipScale = user already accepted
    -- the scale-match popup, so omit the UI-scale line (resolution line still shows).
    local function BuildScaleWarning(payload, skipScale)
        if not payload or not payload.meta then return nil end
        local m = payload.meta
        local warnings = {}
        local myScale  = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
        local expScale = m.euiScale or m.uiScale
        if not skipScale and expScale and math.abs(myScale - expScale) > 0.02 then
            local expPct = math.floor(expScale * 100 + 0.5)
            local myPct  = math.floor(myScale  * 100 + 0.5)
            warnings[#warnings + 1] = EllesmereUI.Lf("UI Scale Issue: Profile was made at %1$d%%, yours is %2$d%%", expPct, myPct)
        end
        local sw, sh = GetPhysicalScreenSize()
        local mySW  = sw and math.floor(sw) or 0
        local mySH  = sh and math.floor(sh) or 0
        local expSW = m.screenW or 0
        local expSH = m.screenH or 0
        if expSW > 0 and expSH > 0 and (mySW ~= expSW or mySH ~= expSH) then
            warnings[#warnings + 1] = EllesmereUI.Lf("Resolution Issue: Profile was made at %1$dx%2$d, yours is %3$dx%4$d", expSW, expSH, mySW, mySH)
        end
        if #warnings == 0 then return nil end
        return EllesmereUI.L("WARNING: Frame positions may be off.") .. "\n" .. table.concat(warnings, "\n")
    end

    -- Between the string/preset page and the import options page: if the string carries a different UI scale, ask ONCE whether to adopt it.
    -- cont(applyScale) ALWAYS runs -- true = apply the imported scale (options page then omits its UI-scale warning), false = keep the user's
    -- own. ShowConfirmPopup routes ESC/click-outside to onCancel, so the page transition can never strand.
    local function MaybeConfirmUIScale(payload, cont)
        local expScale = payload and payload.data
            and type(payload.data.uiScale) == "number" and payload.data.uiScale or nil
        local myScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
            or (UIParent and UIParent:GetScale()) or 1
        if not expScale or math.abs(myScale - expScale) <= 0.02 then
            cont(false)
            return
        end
        local expPct = math.floor(expScale * 100 + 0.5)
        local myPct  = math.floor(myScale * 100 + 0.5)
        EllesmereUI:ShowConfirmPopup({
            title = EllesmereUI.L("UI Scale Mismatch"),
            message = EllesmereUI.Lf("This profile was made at %1$d%% UI scale; yours is %2$d%%. Change your UI scale to match the imported profile? This will show all profiles at this scale as UI Scale is not a per-profile setting, but can be changed at any time back to your original value.", expPct, myPct),
            confirmText = EllesmereUI.L("Match Scale"),
            cancelText = EllesmereUI.L("Keep Mine"),
            onConfirm = function() cont(true) end,
            onCancel = function() cont(false) end,
        })
    end

    local function BuildProfilesPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local FONT = EllesmereUI.EXPRESSWAY
        local EG = EllesmereUI.ELLESMERE_GREEN
        local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"

        -- Safety net: if the active profile does not match the current spec assignment (e.g. spec info was unavailable at login), correct it now.
        do
            local si = GetSpecialization and GetSpecialization() or 0
            local sid = si and si > 0 and GetSpecializationInfo(si) or nil
            if sid then
                local assigned = EllesmereUI.GetSpecProfile(sid)
                if assigned then
                    local current = EllesmereUI.GetActiveProfileName()
                    if assigned ~= current then
                        local _, profiles = EllesmereUI.GetProfileList()
                        if profiles and profiles[assigned] then
                            local fontWillChange = EllesmereUI.ProfileChangesFont(profiles[assigned])
                            local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins
                                and EllesmereUI.ProfileChangesWindowSkins(profiles[assigned])
                            local styleWillChange = EllesmereUI.ProfileChangesStyle
                                and EllesmereUI.ProfileChangesStyle(profiles[assigned])
                            EllesmereUI.SwitchProfile(assigned)
                            -- true = budgeted: manual apply (no spec change
                            -- in flight), watchdog-sliced module refresh.
                            EllesmereUI.RefreshAllAddons(true)
                            if fontWillChange or skinsWillChange or styleWillChange then
                                EllesmereUI:ShowConfirmPopup({
                                    title       = EllesmereUI.L("Reload Required"),
                                    message     = fontWillChange
                                        and EllesmereUI.L("Font changed. A UI reload is needed to apply the new font.")
                                        or skinsWillChange
                                        and EllesmereUI.L("Window skins changed for this profile. A UI reload is needed to apply them.")
                                        or EllesmereUI.L("Style changed for this profile. A UI reload is needed to apply it."),
                                    confirmText = EllesmereUI.L("Reload Now"),
                                    cancelText  = EllesmereUI.L("Later"),
                                    reload      = true,
                                })
                            end
                        end
                    end
                end
            end
        end

        if parent then parent._showRowDivider = false end

        -- Bypass scroll child: parent everything to scrollFrame directly
        local scrollFrame = EllesmereUI._scrollFrame
        if not scrollFrame then return 0 end

        if EllesmereUI._profilesRoot then
            EllesmereUI._profilesRoot:Hide()
            EllesmereUI._profilesRoot:SetParent(nil)
        end

        local root = CreateFrame("Frame", nil, scrollFrame)
        root:SetAllPoints(scrollFrame)
        root:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
        EllesmereUI._profilesRoot = root

        -- Page containers: main profiles page vs import flow
        local mainPage = CreateFrame("Frame", nil, root)
        mainPage:SetAllPoints(root)
        mainPage:SetFrameLevel(root:GetFrameLevel())

        local importPage = CreateFrame("Frame", nil, root)
        importPage:SetAllPoints(root)
        importPage:SetFrameLevel(root:GetFrameLevel())
        importPage:Hide()

        local pastePage = CreateFrame("Frame", nil, root)
        pastePage:SetAllPoints(root)
        pastePage:SetFrameLevel(root:GetFrameLevel())
        pastePage:Hide()

        -- Use mainPage for all main content
        parent = mainPage
        y = -10

        -- Button colours matching dropdown border style
        local _c = EllesmereUI.WB_COLOURS
        local PROF_BTN_COLOURS = {
            _c[1],  _c[2],  _c[3],  _c[4],   _c[5],  _c[6],  _c[7],  _c[8],
            1, 1, 1, EllesmereUI.DD_BRD_A,   1, 1, 1, EllesmereUI.DD_BRD_HA,
            _c[17], _c[18], _c[19], _c[20],  _c[21], _c[22], _c[23], _c[24],
        }

        -- Accent button colours (green-tinted)
        local ACCENT_BTN_COLOURS = {
            EG.r * 0.15, EG.g * 0.15, EG.b * 0.15, 0.85,
            EG.r * 0.22, EG.g * 0.22, EG.b * 0.22, 0.95,
            EG.r, EG.g, EG.b, 0.35,
            EG.r, EG.g, EG.b, 0.65,
            EG.r, EG.g, EG.b, 0.90,
            1, 1, 1, 1,
        }

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -- Shared dropdown builder (reused for profile dd and spec dd)
        local function MakeDropdown(parentFrame, w, ddH, getLabel)
            local btn = CreateFrame("Button", nil, parentFrame)
            PP.Size(btn, w, ddH)
            btn:SetFrameLevel(parentFrame:GetFrameLevel() + 2)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            local lbl = EllesmereUI.MakeFont(btn, 13, nil, 1, 1, 1)
            lbl:SetAlpha(EllesmereUI.DD_TXT_A)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetMaxLines(1)
            lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
            local arrow = EllesmereUI.MakeDropdownArrow(btn, 12, PP)
            lbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
            lbl:SetText(getLabel())
            local s = EllesmereUI.RD_DD_COLOURS
            btn:SetScript("OnEnter", function()
                lbl:SetTextColor(s[21], s[22], s[23], s[24])
                brd:SetColor(s[13], s[14], s[15], s[16])
                bg:SetColorTexture(s[5], s[6], s[7], s[8])
            end)
            btn:SetScript("OnLeave", function()
                lbl:SetTextColor(s[17], s[18], s[19], s[20])
                brd:SetColor(s[9], s[10], s[11], s[12])
                bg:SetColorTexture(s[1], s[2], s[3], s[4])
            end)
            btn._getLabel = getLabel
            return btn, lbl, bg, brd
        end

        local function MakeDropdownMenu(anchor, w)
            local menuFrame = CreateFrame("Frame", nil, UIParent)
            menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            menuFrame:SetFrameLevel(200)
            menuFrame:SetClampedToScreen(true)
            menuFrame:SetSize(w, 4)
            menuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
            menuFrame:Hide()
            local bg = menuFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
            EllesmereUI.MakeBorder(menuFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            menuFrame:SetScript("OnShow", function(self)
                local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
                self:SetScale(s)
                self:SetScript("OnUpdate", function(m)
                    if not anchor:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                    end
                end)
            end)
            menuFrame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
            return menuFrame
        end

        local function MakeMenuItems(menuFrame, items, onSelect)
            local btns = {}
            for i, item in ipairs(items) do
                local itm = CreateFrame("Button", nil, menuFrame)
                itm:SetHeight(26)
                itm:SetFrameLevel(menuFrame:GetFrameLevel() + 1)
                local lbl = itm:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 13, EllesmereUI.GetFontOutlineFlag())
                lbl:SetPoint("LEFT", itm, "LEFT", 10, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                itm._lbl = lbl
                local hl = itm:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                itm._hl = hl
                itm:SetScript("OnEnter", function() lbl:SetTextColor(1,1,1,1); hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A) end)
                itm:SetScript("OnLeave", function()
                    lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                    hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                end)
                itm._lbl:SetText(item.label)
                local idx = i
                itm:SetScript("OnClick", function() menuFrame:Hide(); onSelect(idx, item) end)
                btns[i] = itm
            end
            return btns
        end

        local function LayoutMenuItems(menuFrame, btns, selIdx)
            local mH = 4
            for i, itm in ipairs(btns) do
                itm:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, -mH)
                itm:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, -mH)
                itm._isSel = (i == selIdx)
                itm._hl:SetAlpha(itm._isSel and 0.04 or 0)
                itm:Show()
                mH = mH + 26
            end
            menuFrame:SetHeight(mH + 4)
        end

        -- Hoisted so the import callback can update it
        local ddLabel

        -------------------------------------------------------------------
        --  Shared helpers
        -------------------------------------------------------------------

        local ShowImportPage  -- forward declaration (defined after import page builder)

        local function FormatKey(key)
            if not key then return EllesmereUI.L("Not Bound") end
            local parts = {}
            for mod in key:gmatch("(%u+)%-") do
                parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
            end
            local actualKey = key:match("[^%-]+$") or key
            parts[#parts + 1] = actualKey
            return table.concat(parts, " + ")
        end

        local _kbPopup
        local function ShowProfileKeybindPopup(profileName)
            if _kbPopup then _kbPopup:Hide() end

            local POPUP_W, POPUP_H = 320, 130

            local dimmer = CreateFrame("Frame", nil, UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetFrameLevel(100)
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)

            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.25)

            local popup = CreateFrame("Frame", nil, dimmer)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:SetSize(POPUP_W, POPUP_H)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:EnableMouse(true)
            popup:SetClampedToScreen(true)
            _kbPopup = popup
            popup._dimmer = dimmer

            dimmer:SetScript("OnMouseDown", function()
                if not popup:IsMouseOver() then
                    dimmer:Hide()
                end
            end)

            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints()
            popBg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.20, PP)

            local title = EllesmereUI.MakeFont(popup, 14, nil, 1, 1, 1)
            title:SetPoint("TOP", popup, "TOP", 0, -14)
            title:SetText(EllesmereUI.Lf("Keybind: %1$s", profileName))

            local KB_W, KB_H = 160, 30
            local kbBtn = CreateFrame("Button", nil, popup)
            PP.Size(kbBtn, KB_W, KB_H)
            kbBtn:SetPoint("CENTER", popup, "CENTER", 0, -2)
            kbBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            kbBg:SetAllPoints()
            kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            local kbLbl = EllesmereUI.MakeFont(kbBtn, 13, nil, 1, 1, 1)
            kbLbl:SetAlpha(EllesmereUI.DD_TXT_A or 0.85)
            kbLbl:SetPoint("CENTER")

            local function RefreshLabel()
                local kkey = EllesmereUI.GetProfileKeybind(profileName)
                kbLbl:SetText(FormatKey(kkey))
            end
            RefreshLabel()

            local hint = EllesmereUI.MakeFont(popup, 10, nil, 1, 1, 1, 0.35)
            hint:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
            hint:SetText(EllesmereUI.L("Left-click to set  |  Right-click to unbind  |  Esc to close"))

            local listening = false

            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if listening then
                        listening = false
                        self:EnableKeyboard(false)
                    end
                    EllesmereUI.SetProfileKeybind(profileName, nil)
                    RefreshLabel()
                    return
                end
                if listening then return end
                listening = true
                kbLbl:SetText(EllesmereUI.L("Press a key..."))
                kbBtn:EnableKeyboard(true)
            end)

            kbBtn:SetScript("OnKeyDown", function(self, kkey)
                if not listening then
                    if kkey == "ESCAPE" then
                        self:SetPropagateKeyboardInput(false)
                        dimmer:Hide()
                        return
                    end
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                if kkey == "LSHIFT" or kkey == "RSHIFT" or kkey == "LCTRL" or kkey == "RCTRL"
                   or kkey == "LALT" or kkey == "RALT" or kkey == "LMETA" or kkey == "RMETA" then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                self:SetPropagateKeyboardInput(false)
                if kkey == "ESCAPE" then
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                    return
                end
                -- Blizzard's canonical chord order is ALT-CTRL-SHIFT-KEY, and
                -- CreateKeyChordStringUsingMetaKeyState is what produces it.
                -- Hand-rolling the modifiers built SHIFT-CTRL-ALT-KEY, a chord
                -- string the engine never generates, so any bind using more
                -- than one modifier was stored in a form nothing could match.
                -- Single-modifier binds happen to agree, which is why this
                -- survived.
                local fullKey
                if CreateKeyChordStringUsingMetaKeyState then
                    fullKey = CreateKeyChordStringUsingMetaKeyState(kkey)
                else
                    local mods = ""
                    if IsAltKeyDown() then mods = mods .. "ALT-" end
                    if IsControlKeyDown() then mods = mods .. "CTRL-" end
                    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                    if IsMetaKeyDown and IsMetaKeyDown() then
                        mods = mods .. "META-"
                    end
                    fullKey = mods .. kkey
                end

                EllesmereUI.SetProfileKeybind(profileName, fullKey)
                listening = false
                self:EnableKeyboard(false)
                RefreshLabel()
            end)

            kbBtn:SetScript("OnEnter", function()
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.98)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, 0.3)
                end
                EllesmereUI.ShowWidgetTooltip(kbBtn, EllesmereUI.L("Left-click to set a keybind.\nRight-click to unbind."))
            end)
            kbBtn:SetScript("OnLeave", function()
                if listening then return end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                end
                EllesmereUI.HideWidgetTooltip()
            end)

            popup:SetScript("OnHide", function()
                if listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                end
                if popup._dimmer then popup._dimmer:Hide() end
                _kbPopup = nil
            end)

            popup:EnableKeyboard(true)
            popup:SetScript("OnKeyDown", function(self, kkey)
                if kkey == "ESCAPE" and not listening then
                    self:SetPropagateKeyboardInput(false)
                    dimmer:Hide()
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)

            dimmer:Show()
        end

        local function BuildErrorFlash(btn, brd)
            local flashFrame = CreateFrame("Frame", nil, btn)
            flashFrame:Hide()
            local elapsed = 0
            local FLASH_DUR = 0.7
            local lerp = EllesmereUI.lerp
            flashFrame:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed >= FLASH_DUR then
                    self:Hide()
                    brd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                    return
                end
                local t = elapsed / FLASH_DUR
                brd:SetColor(lerp(0.9, 1, t), lerp(0.15, 1, t), lerp(0.15, 1, t), lerp(0.7, EllesmereUI.DD_BRD_A, t))
            end)
            return function()
                elapsed = 0
                brd:SetColor(0.9, 0.15, 0.15, 0.7)
                flashFrame:Show()
            end
        end

        -------------------------------------------------------------------
        --  IMPORT PAGE BUILDER (shared by presets + import profile)
        -------------------------------------------------------------------
        ShowImportPage = function(exportString, payload, defaultName, editModeString, editModeLayoutName, applyImportedScale)
            -- Clear any previous import page content
            for _, child in ipairs({ importPage:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end

            -- Optional Blizzard Edit Mode layout to apply alongside this import (preset path only; the manual paste path leaves these nil).
            importPage._editModeString     = editModeString
            importPage._editModeLayoutName = editModeLayoutName

            local scaleWarnText = BuildScaleWarning(payload, applyImportedScale)
            local includedAddons = {}
            if payload and payload.data and payload.data.addons then
                for folder in pairs(payload.data.addons) do
                    includedAddons[folder] = true
                end
            end

            -- Spec->profile assignments in the string gate the "Auto Assign to Specs" toggle (and grow the footer by one stacked row); without
            -- them the footer stays a compact single row.
            local hasSpecAssign = payload and payload.data
                and type(payload.data.assignedSpecs) == "table"
                and #payload.data.assignedSpecs > 0

            -- Does the string carry a UI scale? The adopt/keep decision was already made by MaybeConfirmUIScale before this page
            -- (applyImportedScale); this flag only gates the commit marker.
            local hasUIScale = payload and payload.data
                and type(payload.data.uiScale) == "number"

            local ADDON_DB_MAP_LOCAL = EllesmereUI.VisibleProfileAddons(EllesmereUI._ADDON_DB_MAP)
            local PAD        = EllesmereUI.CONTENT_PAD
            local totalW     = importPage:GetWidth() - PAD * 2
            local SIDE_PAD   = 26
            local ROW_H_A    = 48
            local CHK_SZ     = 18
            local STATUS_W   = 70
            local HDR_H      = 72
            local COL_HDR_H  = 28
            -- The optional Auto Assign toggle stacks below the count row.
            local nFooterStack = (hasSpecAssign and 1 or 0)
            local FOOTER_H   = 50 + nFooterStack * 24
            local READY_R, READY_G, READY_B = 0.196, 0.737, 0.325
            local INCLUDE_CENTER_X = -(SIDE_PAD + STATUS_W + 30 + CHK_SZ / 2)

            local ADDON_DESCS = {
                EllesmereUIActionBars        = "Modern action bars built for performance and clarity.",
                EllesmereUINameplates        = "Clean, lightweight nameplates with endless customization.",
                EllesmereUIUnitFrames        = "Simple unit frames with a modern visual style.",
                EllesmereUICooldownManager   = "A CDM replacement focused on performance, customizations and alerts.",
                EllesmereUIResourceBars      = "Custom Resource Bars with thresholds, hash lines and more.",
                EllesmereUIRaidFrames        = "Incredibly light performance, modern raid frames with endless flexibility.",
                EllesmereUIAuraBuffReminders = "Simple raid buff, auras, consumables and talent reminders.",
                EllesmereUIQoL               = "Lightweight quality of life tools and enhancements.",
                EllesmereUIDragonRiding      = "Skyriding HUD with speed, vigor and second wind tracking.",
                EllesmereUIBlizzardSkin       = "Clean and beautiful visual refreshes for Blizzard UI elements.",
                EllesmereUIFriends           = "A modern friends list with built-in organization tools.",
                EllesmereUIMythicTimer       = "Mythic+ timer, targeted spell bars, and standalone cast bars.",
                EllesmereUIQuestTracker      = "A clean, updated reskin of Blizzard's Quest Tracker.",
                EllesmereUIMinimap           = "A new age minimap with clean styling and square layout options.",
                EllesmereUIDamageMeters      = "Lightweight damage meters with simple but powerful customization.",
                EllesmereUIChat              = "Modern chat enhancements with useful utilities.",
                EllesmereUIBags              = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
                EllesmereUIQuickdraw         = "Hold a key to open a menu of actions; point or scroll to choose, release to fire.",
            }

            local iy = -30

            local BACK_W, BACK_H = 80, 32
            local backBtn = CreateFrame("Button", nil, importPage)
            PP.Size(backBtn, BACK_W, BACK_H)
            PP.Point(backBtn, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            backBtn:SetFrameLevel(importPage:GetFrameLevel() + 2)

            local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
            backBg:SetAllPoints()
            backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            local backBrd = EllesmereUI.MakeBorder(backBtn, 1, 1, 1, 0.12, PP)

            local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
            backIcon:SetSize(14, 14)
            PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
            backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
            backIcon:SetVertexColor(EG.r, EG.g, EG.b)
            backIcon:SetAlpha(0.6)
            if backIcon.SetSnapToPixelGrid then backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0) end

            local backLbl = EllesmereUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
            PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
            backLbl:SetText(EllesmereUI.L("Back"))

            backBtn:SetScript("OnEnter", function()
                backBg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                backBrd:SetColor(1, 1, 1, 0.22)
                backIcon:SetAlpha(0.85)
                backLbl:SetAlpha(0.85)
            end)
            backBtn:SetScript("OnLeave", function()
                backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
                backBrd:SetColor(1, 1, 1, 0.12)
                backIcon:SetAlpha(0.6)
                backLbl:SetAlpha(0.55)
            end)
            backBtn:SetScript("OnClick", function()
                importPage:Hide()
                mainPage:Show()
            end)

            local titleFs = EllesmereUI.MakeFont(importPage, 16, nil, 1, 1, 1, 0.95)
            PP.Point(titleFs, "TOP", importPage, "TOP", 0, iy - BACK_H / 2 + 8)
            titleFs:SetText(EllesmereUI.Lf("Importing %1$s", (defaultName or EllesmereUI.L("Profile"))))
            titleFs:SetJustifyH("CENTER")

            iy = iy - BACK_H - 8

            if scaleWarnText then
                local warnFs = EllesmereUI.MakeFont(importPage, 13, nil, 0.9, 0.2, 0.2, 0.85)
                PP.Point(warnFs, "TOP", importPage, "TOP", 0, iy)
                PP.Point(warnFs, "LEFT", importPage, "LEFT", PAD, 0)
                PP.Point(warnFs, "RIGHT", importPage, "RIGHT", -PAD, 0)
                warnFs:SetText(scaleWarnText)
                warnFs:SetJustifyH("CENTER")
                warnFs:SetWordWrap(true)
                iy = iy - 48
            end

            local editBox
            do
                local INPUT_H = 30
                local INPUT_W = 300
                local nameLabel = EllesmereUI.MakeFont(importPage, 12, nil, 1, 1, 1, 0.45)
                PP.Point(nameLabel, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
                nameLabel:SetText(EllesmereUI.L("Profile Name"))
                nameLabel:SetJustifyH("LEFT")

                iy = iy - 22

                local inputFrame = CreateFrame("Frame", nil, importPage)
                PP.Size(inputFrame, INPUT_W, INPUT_H)
                PP.Point(inputFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
                local iBg = inputFrame:CreateTexture(nil, "BACKGROUND")
                iBg:SetAllPoints()
                iBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                local inputBrd = EllesmereUI.MakeBorder(inputFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                importPage._nameFlash = BuildErrorFlash(inputFrame, inputBrd)

                editBox = CreateFrame("EditBox", nil, inputFrame)
                editBox:SetPoint("TOPLEFT", 12, -1)
                editBox:SetPoint("BOTTOMRIGHT", -12, 1)
                editBox:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
                editBox:SetTextColor(1, 1, 1, 0.9)
                editBox:SetAutoFocus(false)
                editBox:SetMaxLetters(30)
                if defaultName then editBox:SetText(defaultName) end

                local placeholder = editBox:CreateFontString(nil, "ARTWORK")
                placeholder:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
                placeholder:SetTextColor(1, 1, 1, 0.25)
                placeholder:SetPoint("LEFT", editBox, "LEFT", 0, 0)
                placeholder:SetText(EllesmereUI.L("Profile name..."))

                editBox:SetScript("OnTextChanged", function(self)
                    if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
                    if importPage._nameError then importPage._nameError:Hide() end
                end)
                editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

                iy = iy - INPUT_H - 14
            end

            -- Import Addons section (mirrors per-addon export layout)
            local selectedImports = {}
            local includeLayoutImport = true     -- "Include layout" toggle (default on)
            -- "Include Overrides" is all-or-nothing: the exporter's COMPLETE
            -- override system (values + groups + custom unlock modes + BM forks) either replaces yours wholesale or none of it comes. Offered
            -- only when the string carries override data; ON for full strings (or subsets exported with Overrides included), OFF otherwise.
            local stringHasOverrides = false
            do
                local d = payload and payload.data
                if d then
                    stringHasOverrides = d.specOverrides ~= nil or d.condOverrides ~= nil
                        or d.specOverrideGroups ~= nil or d.condOverrideGroups ~= nil
                        or d.specUnlockOverrides ~= nil or d.condUnlockOverrides ~= nil
                        or d.specBmOverrides ~= nil or d.condBmOverrides ~= nil
                        or d.specDmOverrides ~= nil or d.condDmOverrides ~= nil
                end
            end
            local includeOverridesImport = stringHasOverrides
                and (payload.data.overridesIncluded == true
                    or (payload.data.partialImport ~= true and payload.data.overridesExcluded ~= true))
                or false
            -- "Include Window Skins": the exporter's Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups).
            -- Default OFF and confirmation-gated -- it overwrites the recipient's settings across ALL profiles. Grayed out when string has none.
            local stringHasBlizzSkin = (payload and payload.data
                and type(payload.data.blizzSkinGlobals) == "table") or false
            local includeWindowSkinsImport = false
            -- "Global Settings": the exporter's global appearance (fonts, custom colours, dark mode, accent) and UI scale. Presence = deliberate
            -- include; this toggle is the recipient's opt-out. ON when carried, inert when the string has none.
            local stringHasGlobals = false
            do
                local d = payload and payload.data
                if d then
                    stringHasGlobals = d.fonts ~= nil or d.customColors ~= nil
                        or d.darkMode ~= nil or d.euiAccent ~= nil or d.uiScale ~= nil
                end
            end
            local includeGlobalsImport = stringHasGlobals
            local autoAssignImport = false       -- "Auto Assign to Specs" toggle (default off)
            local importVisuals = {}
            local importCountFs
            local importComponents   -- canon folder -> { component member set }, set below
            local importCanImport = {}
            local CANON_DISPLAY = {}  -- canon folder -> display name (for the linked tooltip)

            local addonItems = {}
            for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
                local folder = entry.folder
                -- Payload keys are CANONICAL (suite folder names); selectedImports is keyed by canon so it matches the payload + the strip loop
                -- in both suite and standalone builds. "loaded"/"desc" stay on the LOCAL folder so only this build's installed module is checkable.
                local canon = entry.canon or folder
                local loaded = EllesmereUI.IsModuleAddonLoaded(folder)
                local inPayload = includedAddons[canon] or false
                local canImport = loaded and inPayload
                importCanImport[canon] = canImport
                CANON_DISPLAY[canon] = entry.display
                addonItems[#addonItems + 1] = {
                    folder    = folder,
                    canon     = canon,
                    display   = entry.display,
                    desc      = ADDON_DESCS[folder] or "",
                    loaded    = loaded,
                    inPayload = inPayload,
                    canImport = canImport,
                    getVal    = function() return selectedImports[canon] or false end,
                    -- Hard-couple: (un)checking a module sets its whole connected component (anchor/size-match links), importable members only.
                    setVal    = function(v)
                        -- Layout OFF: relationships aren't imported, so skip the hard-couple and let each linked module be picked alone.
                        local members = includeLayoutImport and importComponents and importComponents[canon]
                        if members then
                            for f in pairs(members) do
                                if importCanImport[f] then selectedImports[f] = v or nil end
                            end
                        else
                            selectedImports[canon] = v or nil
                        end
                    end,
                }
                if canImport then selectedImports[canon] = true end
            end

            -- Module connectivity from the payload's layout + meta (both CANONICAL, matching selectedImports' keyspace). Drives the hard-couple
            -- above and the "linked" row affordance. stale={} -- sender already pruned dead edges.
            do
                local ul   = payload and payload.data and payload.data.unlockLayout
                local meta = payload and payload.data and payload.data.unlockLayoutMeta
                importComponents = EllesmereUI.BuildModuleComponents(
                    ul, EllesmereUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder))
            end

            local function RefreshImportCount()
                if not importCountFs then return end
                local count = 0
                for _ in pairs(selectedImports) do count = count + 1 end
                importCountFs:SetText(EllesmereUI.Lf("Import will include %1$s of %2$s addons.", count, #addonItems))
            end

            local function RefreshAllImportVisuals()
                for _, fn in ipairs(importVisuals) do fn() end
                RefreshImportCount()
            end

            local SCROLL_MAX_H = 285
            local contentH = #addonItems * ROW_H_A
            local scrollH = math.min(contentH, SCROLL_MAX_H)
            local SECTION_H = HDR_H + COL_HDR_H + scrollH + 8 + FOOTER_H

            local sectionBg = CreateFrame("Frame", nil, importPage)
            sectionBg:SetFrameLevel(importPage:GetFrameLevel())
            PP.Size(sectionBg, totalW, SECTION_H)
            PP.Point(sectionBg, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            sectionBg:EnableMouse(false)
            local sBgTex = sectionBg:CreateTexture(nil, "BACKGROUND")
            sBgTex:SetAllPoints()
            sBgTex:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(sectionBg, 1, 1, 1, 0.10, PP)

            local hdrFrame = CreateFrame("Frame", nil, importPage)
            PP.Size(hdrFrame, totalW, HDR_H)
            PP.Point(hdrFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)

            local hdrTitle = EllesmereUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
            PP.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
            hdrTitle:SetText(EllesmereUI.L("Import Addons"))
            hdrTitle:SetJustifyH("LEFT")

            local hdrDesc = EllesmereUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
            PP.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
            PP.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
            hdrDesc:SetText(EllesmereUI.L("Choose which addons to import. Any addons not included will use your active profile's settings in the new profile."))
            hdrDesc:SetJustifyH("LEFT")
            hdrDesc:SetWordWrap(true)

            local hdrDiv = hdrFrame:CreateTexture(nil, "ARTWORK")
            hdrDiv:SetColorTexture(1, 1, 1, 0.10)
            hdrDiv:SetHeight(1)
            PP.Point(hdrDiv, "BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", SIDE_PAD, 0)
            PP.Point(hdrDiv, "BOTTOMRIGHT", hdrFrame, "BOTTOMRIGHT", -SIDE_PAD, 0)
            if hdrDiv.SetSnapToPixelGrid then hdrDiv:SetSnapToPixelGrid(false); hdrDiv:SetTexelSnappingBias(0) end

            do
                local LINK_GAP = 12
                local selAllBtn = CreateFrame("Button", nil, hdrFrame)
                selAllBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
                local selAllLbl = selAllBtn:CreateFontString(nil, "OVERLAY")
                selAllLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
                selAllLbl:SetText(EllesmereUI.L("Select All"))
                selAllLbl:SetTextColor(1, 1, 1, 0.40)
                selAllLbl:SetPoint("CENTER")
                selAllBtn:SetSize(selAllLbl:GetStringWidth() + 4, 18)
                selAllBtn:SetPoint("RIGHT", hdrFrame, "RIGHT", -(STATUS_W + LINK_GAP + SIDE_PAD), 0)
                selAllBtn:SetPoint("TOP", hdrDesc, "TOP", 0, 0)

                local function IAllSelected()
                    for _, item in ipairs(addonItems) do
                        if item.canImport and not item.getVal() then return false end
                    end
                    return true
                end
                local function RefreshISelColor()
                    if IAllSelected() then
                        selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
                    else
                        selAllLbl:SetTextColor(1, 1, 1, 0.40)
                    end
                end

                local origRefresh = RefreshAllImportVisuals
                RefreshAllImportVisuals = function()
                    origRefresh()
                    RefreshISelColor()
                end

                selAllBtn:SetScript("OnEnter", function()
                    if IAllSelected() then selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                    else selAllLbl:SetTextColor(1, 1, 1, 0.80) end
                end)
                selAllBtn:SetScript("OnLeave", function() RefreshISelColor() end)
                selAllBtn:SetScript("OnClick", function()
                    for _, item in ipairs(addonItems) do
                        if item.canImport then item.setVal(true) end
                    end
                    RefreshAllImportVisuals()
                end)
                RefreshISelColor()

                local linkDiv = hdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                linkDiv:SetColorTexture(1, 1, 1, 0.15)
                if linkDiv.SetSnapToPixelGrid then linkDiv:SetSnapToPixelGrid(false); linkDiv:SetTexelSnappingBias(0) end
                PP.Point(linkDiv, "LEFT", selAllBtn, "RIGHT", LINK_GAP / 2, 0)
                linkDiv:SetWidth(1)
                linkDiv:SetHeight(10)

                local deselBtn = CreateFrame("Button", nil, hdrFrame)
                deselBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
                local deselLbl = deselBtn:CreateFontString(nil, "OVERLAY")
                deselLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
                deselLbl:SetText(EllesmereUI.L("Deselect All"))
                deselLbl:SetTextColor(1, 1, 1, 0.40)
                deselLbl:SetPoint("CENTER")
                deselBtn:SetSize(deselLbl:GetStringWidth() + 4, 18)
                PP.Point(deselBtn, "LEFT", selAllBtn, "RIGHT", LINK_GAP, 0)
                deselBtn:SetScript("OnEnter", function() deselLbl:SetTextColor(1, 1, 1, 0.80) end)
                deselBtn:SetScript("OnLeave", function() deselLbl:SetTextColor(1, 1, 1, 0.40) end)
                deselBtn:SetScript("OnClick", function()
                    for _, item in ipairs(addonItems) do
                        item.setVal(false)
                    end
                    RefreshAllImportVisuals()
                end)
            end

            iy = iy - HDR_H

            local colHdrFrame = CreateFrame("Frame", nil, importPage)
            PP.Size(colHdrFrame, totalW, COL_HDR_H)
            PP.Point(colHdrFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)

            local colAddon = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(colAddon, "LEFT", colHdrFrame, "LEFT", SIDE_PAD, 0)
            colAddon:SetText(EllesmereUI.L("Addon"))
            colAddon:SetJustifyH("LEFT")

            local colStatus = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(colStatus, "RIGHT", colHdrFrame, "RIGHT", -SIDE_PAD, 0)
            colStatus:SetText(EllesmereUI.L("Status"))
            colStatus:SetJustifyH("RIGHT")

            local colInclude = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(colInclude, "CENTER", colHdrFrame, "RIGHT", INCLUDE_CENTER_X, 0)
            colInclude:SetText(EllesmereUI.L("Include"))
            colInclude:SetJustifyH("CENTER")

            iy = iy - COL_HDR_H

            -- Scrollable addon list
            local scrollClip = CreateFrame("Frame", nil, importPage)
            PP.Size(scrollClip, totalW, scrollH)
            PP.Point(scrollClip, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            scrollClip:SetClipsChildren(true)

            local scrollFr = CreateFrame("ScrollFrame", nil, scrollClip)
            scrollFr:SetAllPoints()

            local scrollChild = CreateFrame("Frame", nil, scrollFr)
            scrollChild:SetSize(totalW, contentH)
            scrollFr:SetScrollChild(scrollChild)

            local scrollOffset = 0
            scrollClip:EnableMouseWheel(true)
            scrollClip:SetScript("OnMouseWheel", function(_, delta)
                local maxScroll = math.max(0, contentH - scrollH)
                scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - delta * ROW_H_A))
                scrollFr:SetVerticalScroll(scrollOffset)
            end)

            -- Addon rows
            local rowY = 0
            for i, item in ipairs(addonItems) do
                local rowFrame = CreateFrame("Frame", nil, scrollChild)
                rowFrame:SetSize(totalW, ROW_H_A)
                rowFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -rowY)

                local rowAlpha = (i % 2 == 0) and 0.12 or 0.06
                local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(0, 0, 0, rowAlpha)

                local nameFs = EllesmereUI.MakeFont(rowFrame, 13, nil, 1, 1, 1, 0.9)
                nameFs:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", SIDE_PAD, -10)
                nameFs:SetPoint("RIGHT", rowFrame, "RIGHT", -(CHK_SZ + STATUS_W + SIDE_PAD * 2 + 20), 0)
                nameFs:SetJustifyH("LEFT")
                nameFs:SetWordWrap(false)
                nameFs:SetText(EllesmereUI.L(item.display))

                local descFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.30)
                descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
                descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(EllesmereUI.L(item.desc))

                local statusFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.40)
                statusFs:SetPoint("RIGHT", rowFrame, "RIGHT", -SIDE_PAD, 0)
                statusFs:SetJustifyH("RIGHT")

                local chkFrame = CreateFrame("Frame", nil, rowFrame)
                chkFrame:SetSize(CHK_SZ, CHK_SZ)
                chkFrame:SetPoint("CENTER", rowFrame, "RIGHT", INCLUDE_CENTER_X, 0)

                local chkBg = chkFrame:CreateTexture(nil, "BACKGROUND")
                chkBg:SetAllPoints()
                chkBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                if chkBg.SetSnapToPixelGrid then chkBg:SetSnapToPixelGrid(false); chkBg:SetTexelSnappingBias(0) end

                local chkBrd = EllesmereUI.MakeBorder(chkFrame, 0.25, 0.25, 0.28, 0.6, PP)

                local chkMark = chkFrame:CreateTexture(nil, "ARTWORK")
                chkMark:SetPoint("TOPLEFT", chkFrame, "TOPLEFT", 3, -3)
                chkMark:SetPoint("BOTTOMRIGHT", chkFrame, "BOTTOMRIGHT", -3, 3)
                chkMark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                if chkMark.SetSnapToPixelGrid then chkMark:SetSnapToPixelGrid(false); chkMark:SetTexelSnappingBias(0) end

                local function ApplyRowVisual()
                    local on = item.getVal()
                    if not item.canImport then
                        nameFs:SetAlpha(0.30)
                        descFs:SetAlpha(0.15)
                        chkMark:Hide()
                        chkBg:SetAlpha(0.3)
                        if not item.inPayload then
                            statusFs:SetText(EllesmereUI.L("Not Included"))
                            statusFs:SetTextColor(0.9, 0.2, 0.2, 0.7)
                        else
                            statusFs:SetText(EllesmereUI.L("Not Loaded"))
                            statusFs:SetTextColor(1, 1, 1, 0.25)
                        end
                    elseif on then
                        nameFs:SetAlpha(0.9)
                        descFs:SetAlpha(0.30)
                        chkMark:Show()
                        chkBg:SetAlpha(1)
                        chkBrd:SetColor(EG.r, EG.g, EG.b, 0.15)
                        statusFs:SetText(EllesmereUI.L("Ready"))
                        statusFs:SetTextColor(READY_R, READY_G, READY_B, 1)
                    else
                        nameFs:SetAlpha(0.50)
                        descFs:SetAlpha(0.20)
                        chkMark:Hide()
                        chkBg:SetAlpha(1)
                        chkBrd:SetColor(0.25, 0.25, 0.28, 0.6)
                        statusFs:SetText(EllesmereUI.L("Skipped"))
                        statusFs:SetTextColor(1, 1, 1, 0.35)
                    end
                end
                ApplyRowVisual()
                importVisuals[#importVisuals + 1] = ApplyRowVisual

                local hoverTex = rowFrame:CreateTexture(nil, "ARTWORK")
                hoverTex:SetAllPoints()
                hoverTex:SetColorTexture(1, 1, 1, 0.05)
                hoverTex:Hide()

                if item.canImport then
                    local clickBtn = CreateFrame("Button", nil, rowFrame)
                    clickBtn:SetAllPoints(rowFrame)
                    clickBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
                    clickBtn:SetScript("OnClick", function()
                        item.setVal(not item.getVal())
                        ApplyRowVisual()
                        RefreshAllImportVisuals()
                    end)
                    clickBtn:SetScript("OnEnter", function()
                        hoverTex:Show()
                        if not item.getVal() then nameFs:SetAlpha(0.75) end
                        -- Linked-modules tooltip; suppressed while layout is off, since nothing couples then.
                        local members = includeLayoutImport and importComponents and importComponents[item.canon]
                        if members then
                            local names = {}
                            for f in pairs(members) do
                                if f ~= item.canon then
                                    names[#names + 1] = EllesmereUI.L(CANON_DISPLAY[f] or f)
                                end
                            end
                            if #names > 0 then
                                table.sort(names)
                                EllesmereUI.ShowWidgetTooltip(rowFrame,
                                    EllesmereUI.Lf("Linked by Anchor/Width/Height Matching to: %1$s. These import together.", table.concat(names, ", ")))
                            end
                        end
                    end)
                    clickBtn:SetScript("OnLeave", function()
                        hoverTex:Hide()
                        if not item.getVal() then nameFs:SetAlpha(0.50) end
                        EllesmereUI.HideWidgetTooltip()
                    end)
                else
                    local blockFrame = CreateFrame("Frame", nil, rowFrame)
                    blockFrame:SetAllPoints()
                    blockFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 5)
                    blockFrame:EnableMouse(true)
                    blockFrame:SetScript("OnEnter", function() end)
                    blockFrame:SetScript("OnLeave", function() end)
                end

                rowY = rowY + ROW_H_A
            end

            iy = iy - scrollH

            -- Footer
            iy = iy - 8
            local footerFrame = CreateFrame("Frame", nil, importPage)
            PP.Size(footerFrame, totalW, FOOTER_H)
            PP.Point(footerFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)

            local footerDiv = footerFrame:CreateTexture(nil, "ARTWORK")
            footerDiv:SetColorTexture(1, 1, 1, 0.10)
            footerDiv:SetHeight(1)
            PP.Point(footerDiv, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, 0)
            PP.Point(footerDiv, "TOPRIGHT", footerFrame, "TOPRIGHT", -SIDE_PAD, 0)
            if footerDiv.SetSnapToPixelGrid then footerDiv:SetSnapToPixelGrid(false); footerDiv:SetTexelSnappingBias(0) end

            importCountFs = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
            -- With Auto Assign present the footer has two rows, so the count sits on the upper one; otherwise it stays vertically centered.
            if nFooterStack > 0 then
                PP.Point(importCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
            else
                PP.Point(importCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
            end
            importCountFs:SetJustifyH("LEFT")
            RefreshImportCount()

            -- Overrides / Unlock Mode Layout / Global Settings / Window Skins live in the "Include:" dropdown beside the Import button; only
            -- Auto Assign stays inline, stacked below the count row.

            -- "Auto Assign to Specs": shown only when the string carries spec->profile assignments. Off (default) leaves the recipient's
            -- assignments alone; On points each exported spec at the new profile.
            if hasSpecAssign then
                local aaBtn = CreateFrame("Button", nil, footerFrame)
                aaBtn:SetSize(180, 24)
                PP.Point(aaBtn, "TOPLEFT", importCountFs, "BOTTOMLEFT", 0, -8)
                local box = CreateFrame("Frame", nil, aaBtn)
                box:SetSize(CHK_SZ, CHK_SZ)
                box:SetPoint("LEFT", aaBtn, "LEFT", 0, 0)
                local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
                bg:SetColorTexture(0.12, 0.12, 0.14, 1)
                EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                local mark = box:CreateTexture(nil, "ARTWORK")
                mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                local lbl = EllesmereUI.MakeFont(aaBtn, 12, nil, 1, 1, 1, 0.6)
                lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
                lbl:SetText(EllesmereUI.L("Auto Assign to Specs"))
                local function vis() mark:SetShown(autoAssignImport) end
                vis()
                aaBtn:SetScript("OnClick", function() autoAssignImport = not autoAssignImport; vis() end)
                aaBtn:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(aaBtn, EllesmereUI.L("Assign this profile to the same specializations it was assigned to on export. Off = your current spec assignments stay as they are."))
                end)
                aaBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end

            local IMP_BTN_W = 180
            local IMP_BTN_H = 30
            local importBtn = CreateFrame("Button", nil, footerFrame)
            PP.Size(importBtn, IMP_BTN_W, IMP_BTN_H)
            PP.Point(importBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)
            importBtn:SetFrameLevel(footerFrame:GetFrameLevel() + 2)

            local DB = EllesmereUI.DARK_BG
            local impBrd = EllesmereUI.MakeBorder(importBtn, EG.r, EG.g, EG.b, 0.7, PP)
            local impBg = EllesmereUI.SolidTex(importBtn, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
            impBg:SetAllPoints()
            local impLbl = EllesmereUI.MakeFont(importBtn, 12, nil, EG.r, EG.g, EG.b)
            impLbl:SetAlpha(0.7)
            impLbl:SetPoint("CENTER")
            impLbl:SetText(EllesmereUI.L("Import Selected Addons"))

            -- "Include:" checkbox dropdown -- same four rows as the export footer (Overrides / Unlock Mode Layout / Global Settings / Window
            -- & Tooltip Skins), left of the Import button. Rows the string has no data for are inert and excluded from the summary; Window
            -- Skins keeps its confirmation gate on enable.
            do
                local ddBtn, ddLabelFS = MakeDropdown(footerFrame, 190, IMP_BTN_H, function() return "" end)
                PP.Point(ddBtn, "RIGHT", importBtn, "LEFT", -12, 0)

                local incLbl = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.6)
                PP.Point(incLbl, "RIGHT", ddBtn, "LEFT", -8, 0)
                incLbl:SetText(EllesmereUI.L("Include:"))

                local rowDefs = {
                    { label = "Overrides", sum = "Overrides",
                      enabled = stringHasOverrides,
                      offTip = "This profile string does not carry any override data.",
                      tip   = "Import the sharer's complete override setup: spec and conditional override values, groups, their custom Unlock Mode layouts, and Buff Manager overrides. This replaces ALL of your own overrides. Off = keep yours untouched.",
                      get   = function() return includeOverridesImport end,
                      set   = function() includeOverridesImport = not includeOverridesImport end },
                    { label = "Unlock Mode Layout", sum = "Layout",
                      enabled = true,
                      tip   = "Import the anchor & size-match relationships from this profile. Off = keep your own layout; only the selected modules' own positions/settings come in.",
                      get   = function() return includeLayoutImport end,
                      set   = function() includeLayoutImport = not includeLayoutImport end },
                    { label = "Global Settings", sum = "Globals",
                      enabled = stringHasGlobals,
                      offTip = "This profile string does not carry any global settings.",
                      tip   = "Apply the sharer's fonts, custom colours, dark mode, accent colour and UI scale. Off = keep your own global look and scale; only the selected modules' settings come in.",
                      get   = function() return includeGlobalsImport end,
                      set   = function() includeGlobalsImport = not includeGlobalsImport end },
                    { label = "Window & Tooltip Skins", sum = "Window Skins",
                      enabled = stringHasBlizzSkin,
                      offTip = "This profile string does not carry any Window & Tooltip Skins settings.",
                      tip   = "Apply the sharer's Blizz UI Enhanced Window Skins and Tooltips, Menus & Popups settings. These are account-wide and will overwrite yours across ALL profiles. Off = keep your own.",
                      get   = function() return includeWindowSkinsImport end,
                      set   = function(refresh)
                          if includeWindowSkinsImport then
                              includeWindowSkinsImport = false
                              return
                          end
                          EllesmereUI:ShowConfirmPopup({
                              title       = EllesmereUI.L("Overwrite Window & Tooltip Settings?"),
                              message     = EllesmereUI.L("This will replace YOUR Blizz UI Enhanced settings (the Window Skins and Tooltips, Menus & Popups tabs) with the sharer's, across ALL of your profiles. Your current settings on those two tabs cannot be recovered afterward."),
                              confirmText = EllesmereUI.L("OK"),
                              cancelText  = EllesmereUI.L("Cancel"),
                              onConfirm   = function()
                                  includeWindowSkinsImport = true
                                  if refresh then refresh() end
                              end,
                          })
                      end },
                }

                local function Summary()
                    local parts, total = {}, 0
                    for _, def in ipairs(rowDefs) do
                        if def.enabled then
                            total = total + 1
                            if def.get() then parts[#parts + 1] = EllesmereUI.L(def.sum) end
                        end
                    end
                    if #parts == 0 then return EllesmereUI.L("Nothing Extra") end
                    if #parts == total then return EllesmereUI.L("Everything") end
                    return table.concat(parts, ", ")
                end
                local function RefreshSummary() ddLabelFS:SetText(Summary()) end

                local menu = MakeDropdownMenu(ddBtn, 240)
                menu:SetSize(240, #rowDefs * 26 + 8)
                local marks = {}
                local function RefreshMenu()
                    for i, def in ipairs(rowDefs) do
                        marks[i]:SetShown(def.enabled and def.get())
                    end
                end
                local function RefreshAll() RefreshMenu(); RefreshSummary() end
                for i, def in ipairs(rowDefs) do
                    local row = CreateFrame("Button", nil, menu)
                    row:SetHeight(26)
                    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (i - 1) * 26))
                    row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
                    row:SetFrameLevel(menu:GetFrameLevel() + 1)
                    local hl = row:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                    local box = CreateFrame("Frame", nil, row)
                    box:SetSize(CHK_SZ, CHK_SZ)
                    box:SetPoint("LEFT", row, "LEFT", 6, 0)
                    local bbg = box:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints()
                    bbg:SetColorTexture(0.12, 0.12, 0.14, 1)
                    EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                    local mark = box:CreateTexture(nil, "ARTWORK")
                    mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                    mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                    mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    marks[i] = mark
                    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1, 0.7)
                    lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                    lbl:SetText(EllesmereUI.L(def.label))
                    if def.enabled then
                        row:SetScript("OnEnter", function()
                            hl:SetAlpha(0.05)
                            EllesmereUI.ShowWidgetTooltip(row, EllesmereUI.L(def.tip))
                        end)
                        row:SetScript("OnLeave", function()
                            hl:SetAlpha(0)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        row:SetScript("OnClick", function()
                            def.set(RefreshAll)
                            RefreshAll()
                        end)
                    else
                        row:SetAlpha(0.35)
                        row:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(row, EllesmereUI.L(def.offTip))
                        end)
                        row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    end
                end
                -- HookScript: MakeDropdownMenu owns OnShow (scale + outside-click close); our mark refresh rides alongside it.
                menu:HookScript("OnShow", RefreshMenu)
                ddBtn:SetScript("OnClick", function()
                    RefreshSummary()
                    if menu:IsShown() then menu:Hide() else RefreshMenu(); menu:Show() end
                end)
                RefreshSummary()
            end

            local impProgress, impTarget = 0, 0
            local IMP_FADE = 0.1
            local impLerp = EllesmereUI.lerp
            local function ImpApply(t)
                impLbl:SetTextColor(EG.r, EG.g, EG.b, impLerp(0.7, 1, t))
                impBrd:SetColor(EG.r, EG.g, EG.b, impLerp(0.7, 1, t))
            end
            local function ImpOnUpdate(self, elapsed)
                local dir = (impTarget == 1) and 1 or -1
                impProgress = impProgress + dir * (elapsed / IMP_FADE)
                if (dir == 1 and impProgress >= 1) or (dir == -1 and impProgress <= 0) then
                    impProgress = impTarget; self:SetScript("OnUpdate", nil)
                end
                ImpApply(impProgress)
            end
            importBtn:SetScript("OnEnter", function(self) impTarget = 1; self:SetScript("OnUpdate", ImpOnUpdate) end)
            importBtn:SetScript("OnLeave", function(self) impTarget = 0; self:SetScript("OnUpdate", ImpOnUpdate) end)
            importBtn:SetScript("OnClick", function()
                -- Get profile name from the edit box
                local nameBox = importPage._nameEditBox
                local name = nameBox and strtrim(nameBox:GetText()) or ""
                if name == "" then
                    if importPage._nameFlash then importPage._nameFlash() end
                    if importPage._nameError then importPage._nameError:Show() end
                    if nameBox then nameBox:SetFocus() end
                    return
                end

                -- Block duplicate profile names. EXCEPTION: an interactive API import (ImportProfileInteractive) targeting the EXACT name the
                -- calling addon requested overwrites cleanly, like the silent API -- ImportProfile replaces the stored blob wholesale (the old
                -- same-name blob is never read, so nothing mixes) and unselected modules keep current values via merge-base-on-active. A name
                -- the USER edited into a collision keeps the protection below.
                local apiS = EllesmereUI._apiImportSession
                local apiOverwrite = apiS and apiS.state ~= "done" and apiS.name == name
                local _, existingProfiles = EllesmereUI.GetProfileList()
                if existingProfiles and existingProfiles[name] and not apiOverwrite then
                    EllesmereUI:ShowConfirmPopup({
                        title = EllesmereUI.L("Name Taken"),
                        message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                        confirmText = EllesmereUI.L("OK"),
                        hideCancel = true,
                        onConfirm = function() end,
                    })
                    return
                end

                -- Filter on a private deep copy of the already-decoded payload: the strips below mutate it and the page must stay re-importable
                -- after a failed attempt (re-decoding would re-run the codec).
                local filteredPayload = EllesmereUI._DeepCopy(payload)
                local isPartialImport = false
                if filteredPayload and filteredPayload.data and filteredPayload.data.addons then
                    for folder in pairs(filteredPayload.data.addons) do
                        if not selectedImports[folder] then
                            filteredPayload.data.addons[folder] = nil
                            isPartialImport = true
                        end
                    end
                end
                -- CDM spell allocation is top-level (the per-module loop misses it): kept ONLY when the CDM module is selected, and then every
                -- spec in the string imports as-is (no spec picker).
                if filteredPayload and filteredPayload.data then
                    if not selectedImports["EllesmereUICooldownManager"] then
                        filteredPayload.data.cdmSpells = nil
                    end
                end
                -- Spec->profile assignments: top-level, applied by ImportProfile when present. Dropped wholesale unless "Auto Assign to Specs"
                -- is on (default off leaves the recipient's assignments alone).
                if filteredPayload and filteredPayload.data and not autoAssignImport then
                    filteredPayload.data.assignedSpecs = nil
                end
                -- UI scale (account-wide): applied by ImportProfile ONLY on the opt-in from MaybeConfirmUIScale. PRESENCE IS CONSENT at
                -- ImportProfile -- accepted keeps the payload's uiScale; declined or matching scales STRIP it so the user's own scale stands.
                if filteredPayload and filteredPayload.data and hasUIScale and not applyImportedScale then
                    filteredPayload.data.uiScale = nil
                    filteredPayload.data.applyUIScale = nil
                end
                -- Layout relationships: keep only anchor/size-match edges with BOTH endpoints in the selected modules (per-element graph filter)
                -- via the payload's keyToFolder meta. selectedImports and the meta values are both CANONICAL, so they compare directly.
                -- stale={}: the sender pruned dead edges at export and the recipient's registry is irrelevant here; the "Include layout" toggle drops the whole thing separately.
                if filteredPayload and filteredPayload.data then
                    local ul = filteredPayload.data.unlockLayout
                    if ul and includeLayoutImport then
                        local meta = filteredPayload.data.unlockLayoutMeta
                        -- payload meta wins; the static resolver fills gaps (and ALL keys for a meta-less string) so we never drop the layout.
                        local k2f = EllesmereUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
                        filteredPayload.data.unlockLayout =
                            EllesmereUI.FilterLayoutToFolders(ul, selectedImports, k2f)
                    else
                        filteredPayload.data.unlockLayout = nil
                    end
                    -- Meta is transient -- never overlay/persist it into the profile.
                    filteredPayload.data.unlockLayoutMeta = nil
                end
                -- Global appearance (fonts, customColors, darkMode, euiAccent) and scale ride the Include dropdown's "Global Settings" row (on
                -- by default when carried): unchecked strips them all so the merge keeps the recipient's look. Module deselection alone never
                -- strips them -- the store merge takes each key only when present.
                if filteredPayload and filteredPayload.data and not includeGlobalsImport then
                    filteredPayload.data.fonts        = nil
                    filteredPayload.data.customColors = nil
                    filteredPayload.data.darkMode     = nil
                    filteredPayload.data.euiAccent    = nil
                    filteredPayload.data.uiScale      = nil
                    filteredPayload.data.applyUIScale = nil
                end
                if isPartialImport and filteredPayload and filteredPayload.data then
                    -- Overrides (values AND forks) are governed solely by the Include Overrides checkbox; module deselection never strips them
                    -- here. partialImport gates the override legacy keep-mine default at the store merge.
                    filteredPayload.data.partialImport = true
                end
                -- Unlock-layer FORKS are whole cross-module position layers, so "Include layout" must gate them exactly like unlockLayout above
                -- or the exporter's forks replace the recipient's group layouts (ApplyLayer rewrites live anchors and CDM/AB bar positions from
                -- them on the next apply). layoutExcluded tells the store merge to KEEP the recipient's forks (nil incoming must not read as wipe).
                if filteredPayload and filteredPayload.data and not includeLayoutImport then
                    -- Baseline layout excluded; fork stores belong to the Include Overrides decision below, so they are not stripped here.
                    filteredPayload.data.layoutExcluded = true
                end
                -- Include Overrides (all-or-nothing): checked -> stamp the marker so ImportProfile takes the exporter's whole override system
                -- even on subset strings; unchecked -> strip every override store and stamp the exclusion so nils read as "keep mine", not "wipe".
                if filteredPayload and filteredPayload.data then
                    if includeOverridesImport then
                        filteredPayload.data.overridesIncluded = true
                        filteredPayload.data.overridesExcluded = nil
                    else
                        filteredPayload.data.specOverrides       = nil
                        filteredPayload.data.specOverrideGroups  = nil
                        filteredPayload.data.specOverrideNextId  = nil
                        filteredPayload.data.condOverrides       = nil
                        filteredPayload.data.condOverrideGroups  = nil
                        filteredPayload.data.condOverrideNextId  = nil
                        filteredPayload.data.specUnlockOverrides = nil
                        filteredPayload.data.condUnlockOverrides = nil
                        filteredPayload.data.specBmOverrides     = nil
                        filteredPayload.data.condBmOverrides     = nil
                        filteredPayload.data.specDmOverrides     = nil
                        filteredPayload.data.condDmOverrides     = nil
                        filteredPayload.data.unlockOverrideAnchors = nil
                        filteredPayload.data.overridesExcluded   = true
                        filteredPayload.data.overridesIncluded   = nil
                    end
                end
                -- Include Window Skins: checked -> stamp the opt-in so ImportProfile applies the Blizz UI Enhanced account-global bundle before
                -- the reload; unchecked -> strip the bundle so nothing can apply and the recipient keeps their settings.
                if filteredPayload and filteredPayload.data then
                    if includeWindowSkinsImport and stringHasBlizzSkin then
                        filteredPayload.data.applyBlizzSkinGlobals = true
                    else
                        filteredPayload.data.blizzSkinGlobals      = nil
                        filteredPayload.data.applyBlizzSkinGlobals = nil
                    end
                end

                local function commit()
                    -- The payload table goes to ImportProfile directly (no encode-to-string round trip on already-decoded data). An
                    -- interactive-API session marks itself as committing so ImportProfile's stale-session cancellation (which guards
                    -- CONCURRENT silent imports) never cancels the committing one.
                    local apiSession = EllesmereUI._apiImportSession
                    if apiSession and apiSession.state == "done" then apiSession = nil end
                    if apiSession then apiSession.committing = true end
                    local ok, err, status = EllesmereUI.ImportProfile(filteredPayload, name)
                    if apiSession then apiSession.committing = nil end
                    -- Apply the preset's Blizzard Edit Mode layout (if supplied) right before the reload so profile + layout land together.
                    -- pcall-guarded so a Blizzard Edit Mode error cannot block the reload. No-op on the manual paste path (no stored string).
                    if ok and importPage._editModeString then
                        pcall(EllesmereUI.ApplyPresetEditMode, importPage._editModeString, importPage._editModeLayoutName)
                    end
                    if ok and apiSession then
                        -- Interactive-API import: hand control back to the caller instead of reloading (the caller owns ReloadUI()). Finish
                        -- BEFORE hiding so the panel's OnHide decline hook sees a completed session and stays silent.
                        if status == "spec_locked" then
                            EllesmereUI.Print(EllesmereUI.Lf("\"%1$s\" was saved but cannot be loaded because this spec has an assigned profile.", name))
                        end
                        EllesmereUI._FinishApiImportSession(true)
                        if EllesmereUI._ProfilesResetToMain then pcall(EllesmereUI._ProfilesResetToMain) end
                        EllesmereUI:Hide()
                    elseif ok and status == "spec_locked" then
                        EllesmereUI:ShowInfoPopup({
                            title   = EllesmereUI.L("Profile Imported"),
                            content = EllesmereUI.Lf("\"%1$s\" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.", name),
                        })
                        ReloadUI()
                    elseif ok then
                        ReloadUI()
                    else
                        EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Failed"), content = err or EllesmereUI.L("Unknown error") })
                    end
                end

                -- CDM spell layouts (gated above) import as-is, no spec picker: they are per-profile (spellAssignments.profiles[profileName]),
                -- so only the NEW profile's store is populated (others untouched) and any spec not in the string falls back to default bars.
                commit()
            end)
            importBtn._flashError = BuildErrorFlash(importBtn, impBrd)

            -- Red error message shown directly below the button when no name is entered
            local nameErrorFs = EllesmereUI.MakeFont(footerFrame, 11, nil, 0.9, 0.2, 0.2)
            nameErrorFs:SetJustifyH("RIGHT")
            PP.Point(nameErrorFs, "TOPRIGHT", importBtn, "BOTTOMRIGHT", 0, -14)
            nameErrorFs:SetText(EllesmereUI.L("*Please enter a profile name"))
            nameErrorFs:Hide()
            importPage._nameError = nameErrorFs

            -- Store edit box reference for the import button callback
            importPage._nameEditBox = editBox

            -- Hide every other page so the import page never overlaps the one it was opened from (the main paste flow).
            mainPage:Hide()
            pastePage:Hide()
            importPage:Show()
        end

        -------------------------------------------------------------------
        --  PASTE PAGE (Import Profile step 1: paste string)
        -------------------------------------------------------------------
        local function ShowPastePage()
            for _, child in ipairs({ pastePage:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end

            local PAD = EllesmereUI.CONTENT_PAD
            local totalW = pastePage:GetWidth() - PAD * 2
            local py = -30

            local BACK_W, BACK_H = 80, 32
            local backBtn = CreateFrame("Button", nil, pastePage)
            PP.Size(backBtn, BACK_W, BACK_H)
            PP.Point(backBtn, "TOPLEFT", pastePage, "TOPLEFT", PAD, py)
            backBtn:SetFrameLevel(pastePage:GetFrameLevel() + 2)

            local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
            backBg:SetAllPoints()
            backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            local backBrd = EllesmereUI.MakeBorder(backBtn, 1, 1, 1, 0.12, PP)

            local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
            backIcon:SetSize(14, 14)
            PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
            backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
            backIcon:SetVertexColor(EG.r, EG.g, EG.b)
            backIcon:SetAlpha(0.6)
            if backIcon.SetSnapToPixelGrid then backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0) end

            local backLbl = EllesmereUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
            PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
            backLbl:SetText(EllesmereUI.L("Back"))

            backBtn:SetScript("OnEnter", function()
                backBg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                backBrd:SetColor(1, 1, 1, 0.22)
                backIcon:SetAlpha(0.85)
                backLbl:SetAlpha(0.85)
            end)
            backBtn:SetScript("OnLeave", function()
                backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
                backBrd:SetColor(1, 1, 1, 0.12)
                backIcon:SetAlpha(0.6)
                backLbl:SetAlpha(0.55)
            end)
            backBtn:SetScript("OnClick", function()
                pastePage:Hide()
                mainPage:Show()
            end)

            local titleFs = EllesmereUI.MakeFont(pastePage, 16, nil, 1, 1, 1, 0.95)
            PP.Point(titleFs, "TOP", pastePage, "TOP", 0, py - BACK_H / 2 + 8)
            titleFs:SetText(EllesmereUI.L("Import Profile"))
            titleFs:SetJustifyH("CENTER")

            py = py - BACK_H - 20

            -- Big paste panel
            local PANEL_H = 200
            local panelFrame = CreateFrame("Frame", nil, pastePage)
            PP.Size(panelFrame, totalW, PANEL_H)
            PP.Point(panelFrame, "TOPLEFT", pastePage, "TOPLEFT", PAD, py)
            local panelBg = panelFrame:CreateTexture(nil, "BACKGROUND")
            panelBg:SetAllPoints()
            panelBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(panelFrame, 1, 1, 1, 0.10, PP)

            local pasteSF = CreateFrame("ScrollFrame", nil, panelFrame)
            pasteSF:SetPoint("TOPLEFT", 16, -12)
            pasteSF:SetPoint("BOTTOMRIGHT", -16, 12)

            local pasteBox = CreateFrame("EditBox", nil, pasteSF)
            pasteBox:SetWidth(totalW - 32)
            pasteBox:SetFont(FONT, 11, EllesmereUI.GetFontOutlineFlag())
            pasteBox:SetTextColor(1, 1, 1, 0.8)
            pasteBox:SetAutoFocus(false)
            pasteBox:SetMultiLine(true)
            pasteSF:SetScrollChild(pasteBox)

            -- Click anywhere on the panel to refocus the edit box
            panelFrame:EnableMouse(true)
            panelFrame:SetScript("OnMouseDown", function() pasteBox:SetFocus() end)

            local pastePlaceholder = pasteSF:CreateFontString(nil, "ARTWORK")
            pastePlaceholder:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            pastePlaceholder:SetTextColor(1, 1, 1, 0.20)
            pastePlaceholder:SetPoint("TOPLEFT", pasteSF, "TOPLEFT", 0, 0)
            pastePlaceholder:SetText(EllesmereUI.L("Paste your profile string here..."))

            pasteBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then pastePlaceholder:Show() else pastePlaceholder:Hide() end
            end)
            pasteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            pasteBox:SetScript("OnCursorChanged", function(self, _, cursorY, _, cursorH)
                local vs = pasteSF:GetVerticalScroll()
                local h = pasteSF:GetHeight()
                local bottom = -(cursorY) + cursorH
                if bottom > vs + h then
                    pasteSF:SetVerticalScroll(bottom - h)
                elseif -(cursorY) < vs then
                    pasteSF:SetVerticalScroll(-(cursorY))
                end
            end)

            -- Large pastes go into a buffer (attached AFTER the handlers above so their scripts survive): the box only ever holds a short
            -- summary line, keeping paste instant with no letter-cap truncation.
            local pasteAbsorber = EllesmereUI.AttachImportPasteAbsorber(pasteBox, function()
                EllesmereUI:ShowInfoPopup({
                    title   = EllesmereUI.L("Paste Interrupted"),
                    content = EllesmereUI.L("The pasted string could not be read completely. Please paste it again."),
                })
            end)

            py = py - PANEL_H - 16

            -- Continue button (Done-style)
            local CONT_W, CONT_H = 160, 34
            local contBtn = CreateFrame("Button", nil, pastePage)
            PP.Size(contBtn, CONT_W, CONT_H)
            PP.Point(contBtn, "TOPRIGHT", pastePage, "TOPRIGHT", -PAD, py)
            contBtn:SetFrameLevel(pastePage:GetFrameLevel() + 2)

            local cDB = EllesmereUI.DARK_BG
            local contBrd = EllesmereUI.MakeBorder(contBtn, EG.r, EG.g, EG.b, 0.7, PP)
            local contBg = EllesmereUI.SolidTex(contBtn, "BACKGROUND", cDB.r, cDB.g, cDB.b, 0.92)
            contBg:SetAllPoints()
            local contLbl = EllesmereUI.MakeFont(contBtn, 13, nil, EG.r, EG.g, EG.b)
            contLbl:SetAlpha(0.7)
            contLbl:SetPoint("CENTER")
            contLbl:SetText(EllesmereUI.L("Continue"))

            local contProgress, contTarget = 0, 0
            local CONT_FADE = 0.1
            local contLerp = EllesmereUI.lerp
            local function ContApply(t)
                contLbl:SetTextColor(EG.r, EG.g, EG.b, contLerp(0.7, 1, t))
                contBrd:SetColor(EG.r, EG.g, EG.b, contLerp(0.7, 1, t))
            end
            local function ContOnUpdate(self, elapsed)
                local dir = (contTarget == 1) and 1 or -1
                contProgress = contProgress + dir * (elapsed / CONT_FADE)
                if (dir == 1 and contProgress >= 1) or (dir == -1 and contProgress <= 0) then
                    contProgress = contTarget; self:SetScript("OnUpdate", nil)
                end
                ContApply(contProgress)
            end
            contBtn:SetScript("OnEnter", function(self) contTarget = 1; self:SetScript("OnUpdate", ContOnUpdate) end)
            contBtn:SetScript("OnLeave", function(self) contTarget = 0; self:SetScript("OnUpdate", ContOnUpdate) end)
            local decodeRun
            contBtn:SetScript("OnClick", function()
                if decodeRun then return end
                local importStr = pasteAbsorber.GetText()
                if importStr == "" then return end
                -- Decode across frames: lock the button and show progress so the client stays responsive on very large strings.
                contBtn:Disable()
                contBtn:SetScript("OnUpdate", nil)
                contProgress, contTarget = 0, 0
                ContApply(0)
                contLbl:SetText(EllesmereUI.L("Processing") .. "...")
                local function Restore()
                    decodeRun = nil
                    contBtn:Enable()
                    contLbl:SetText(EllesmereUI.L("Continue"))
                    contProgress, contTarget = 0, 0
                    ContApply(0)
                end
                decodeRun = EllesmereUI.DecodeImportStringAsync(importStr,
                    function(payload, err)
                        Restore()
                        -- The user may have navigated away mid-decode; a stale run's result is simply dropped.
                        if not pastePage:IsVisible() then return end
                        if not payload then
                            EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Failed"), content = err or EllesmereUI.L("Invalid import string.") })
                            return
                        end
                        -- FULL ACCOUNT string: its own flow, routed BEFORE the normal import machinery sees the payload (no module selection,
                        -- include toggles, or store merging). Typed confirmation: it overwrites account-wide settings.
                        if EllesmereUI.IsFullAccountPayload
                           and EllesmereUI.IsFullAccountPayload(payload) then
                            pastePage:Hide()
                            EllesmereUI:ShowConfirmPopup({
                                title = EllesmereUI.L("Import Full Account Data"),
                                message = EllesmereUI.L("This string is a FULL ACCOUNT export. It replaces your account-wide settings with the sender's, including Quality of Life, HoverCast bindings, Cooldown Manager spell setups, unlock anchors, UI scale, and profile keybinds -- not just a profile. Your other profiles are kept, but a profile with the same name is replaced."),
                                disclaimer = EllesmereUI.L("This cannot be undone. Export your own profile as a backup first."),
                                typeToConfirm = "Confirm",
                                confirmText = EllesmereUI.L("Import & Reload"),
                                cancelText = EllesmereUI.L("Cancel"),
                                onConfirm = function()
                                    if EllesmereUI.ImportFullAccountData then
                                        EllesmereUI.ImportFullAccountData(payload)
                                    end
                                end,
                            })
                            return
                        end
                        pastePage:Hide()
                        MaybeConfirmUIScale(payload, function(applyScale)
                            ShowImportPage(importStr, payload, nil, nil, nil, applyScale)
                        end)
                    end,
                    function(frac)
                        contLbl:SetFormattedText("%s %d%%", EllesmereUI.L("Processing"), frac * 100)
                    end)
            end)

            mainPage:Hide()
            pastePage:Show()
            pasteBox:SetFocus()
        end


        -------------------------------------------------------------------
        --  TOP SECTION: Import | Popular Presets (2 action cards)
        --  Exporting lives solely in the per-addon "Export Profile" section below -- all modules checked is the full export.
        -------------------------------------------------------------------
        _, h = W:Spacer(parent, y, 10);  y = y - h

        do
            local CARD_H     = 66
            local CARD_GAP   = 14
            local CARD_ICON  = 26
            local totalW     = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            local CARD_W     = math.floor((totalW - CARD_GAP) / 2)

            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, CARD_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            -- Builds one action card: icon + title + description
            local function MakeActionCard(parentRow, xOff, iconPath, cardTitle, cardDesc, onClick)
                local card = CreateFrame("Button", nil, parentRow)
                PP.Size(card, CARD_W, CARD_H)
                PP.Point(card, "TOPLEFT", parentRow, "TOPLEFT", xOff, 0)
                card:SetFrameLevel(parentRow:GetFrameLevel() + 2)

                local bg = card:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)

                local brd = EllesmereUI.MakeBorder(card, 1, 1, 1, 0.12, PP)

                -- Accent top edge
                local accentLine = card:CreateTexture(nil, "ARTWORK", nil, 7)
                accentLine:SetColorTexture(EG.r, EG.g, EG.b, 0.6)
                PP.Point(accentLine, "TOPLEFT", card, "TOPLEFT", 1, -1)
                PP.Point(accentLine, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
                accentLine:SetHeight(2)
                if accentLine.SetSnapToPixelGrid then accentLine:SetSnapToPixelGrid(false); accentLine:SetTexelSnappingBias(0) end

                local icon = card:CreateTexture(nil, "ARTWORK")
                icon:SetSize(CARD_ICON, CARD_ICON)
                PP.Point(icon, "LEFT", card, "LEFT", 24, 0)
                icon:SetTexture(iconPath)
                icon:SetVertexColor(EG.r, EG.g, EG.b)
                icon:SetAlpha(0.6)
                if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end

                local titleFs = EllesmereUI.MakeFont(card, 13, nil, 1, 1, 1, 0.9)
                PP.Point(titleFs, "TOPLEFT", icon, "TOPRIGHT", 20, 2)
                PP.Point(titleFs, "RIGHT", card, "RIGHT", -14, 0)
                titleFs:SetJustifyH("LEFT")
                titleFs:SetWordWrap(false)
                titleFs:SetText(EllesmereUI.L(cardTitle))

                local descFs = EllesmereUI.MakeFont(card, 11, nil, 1, 1, 1, 0.35)
                PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
                PP.Point(descFs, "RIGHT", card, "RIGHT", -14, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(EllesmereUI.L(cardDesc))

                card:SetScript("OnEnter", function()
                    bg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                    brd:SetColor(1, 1, 1, 0.22)
                    titleFs:SetAlpha(1)
                    icon:SetAlpha(0.85)
                end)
                card:SetScript("OnLeave", function()
                    bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
                    brd:SetColor(1, 1, 1, 0.12)
                    titleFs:SetAlpha(0.9)
                    icon:SetAlpha(0.6)
                end)
                if onClick then
                    card:SetScript("OnClick", onClick)
                end

                return card
            end

            -- Import Profile
            local cardX = 0
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\import.png",
                EllesmereUI.L("Import Profile"), EllesmereUI.L("Import a profile from string."), function()
                    ShowPastePage()
                end)

            -- Popular Presets: the in-game browser is retired; presets live on
            -- the EllesmereUI website. The card opens the announcement-style
            -- popup with the copyable link (same one the Presets tab shows).
            cardX = cardX + CARD_W + CARD_GAP
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\dark-overlay.png",
                EllesmereUI.L("Popular Presets"), EllesmereUI.L("Browse community presets."), function()
                    if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                end)

            y = y - CARD_H
        end

        -------------------------------------------------------------------
        --  MIDDLE SECTION: Active Profile | Assign to Spec | Create New
        -------------------------------------------------------------------
        _, h = W:Spacer(parent, y, 14);  y = y - h

        do
            local LABEL_H = 16
            local CTRL_H  = 30
            local PAD_X   = 40
            local PAD_Y   = 20
            local GAP     = 40
            local ROW_H   = PAD_Y + LABEL_H + 4 + CTRL_H + PAD_Y

            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            local innerW = totalW - PAD_X * 2
            local DD_W   = math.floor(innerW * 0.38)
            local BTN_W  = math.floor((innerW - DD_W - GAP * 2) / 2)

            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            -- Background panel
            local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            local rowBrd = EllesmereUI.MakeBorder(rowFrame, 1, 1, 1, 0.10, PP)

            -- "Active Profile" label
            local profLabel = EllesmereUI.MakeFont(rowFrame, 12, nil, EG.r, EG.g, EG.b, 0.7)
            PP.Point(profLabel, "TOPLEFT", rowFrame, "TOPLEFT", PAD_X, -PAD_Y)
            profLabel:SetText(EllesmereUI.L("Active Profile"))
            profLabel:SetJustifyH("LEFT")

            -- Active Profile dropdown
            local ddBtn, ddLabelFS, ddBg, ddBrd = MakeDropdown(rowFrame, DD_W, CTRL_H, function()
                return EllesmereUI.GetActiveProfileName()
            end)
            EllesmereUI._profileDDBtn = ddBtn
            ddLabel = ddLabelFS
            PP.Point(ddBtn, "TOPLEFT", profLabel, "BOTTOMLEFT", 0, -6)

            -- Profile dropdown menu with inline rename/delete/keybind
            local aS = EllesmereUI.RD_DD_COLOURS
            local menu = MakeDropdownMenu(ddBtn, DD_W)
            local X_SZ = 14
            local menuItems = {}

            local function RebuildProfileMenu()
                for _, itm in ipairs(menuItems) do itm:Hide() end
                local order, profiles = EllesmereUI.GetProfileList()
                local mH = 4
                local idx = 0
                local activeName = EllesmereUI.GetActiveProfileName()
                local specAssigned
                do
                    local si = GetSpecialization and GetSpecialization() or 0
                    local sid = si and si > 0 and GetSpecializationInfo(si) or nil
                    if sid then specAssigned = EllesmereUI.GetSpecProfile(sid) end
                end
                for _, name in ipairs(order) do
                    if profiles[name] then
                        idx = idx + 1
                        local itm = menuItems[idx]
                        if not itm then
                            itm = CreateFrame("Button", nil, menu)
                            itm:SetHeight(26)
                            itm:SetFrameLevel(menu:GetFrameLevel() + 1)

                            local lbl = itm:CreateFontString(nil, "OVERLAY")
                            lbl:SetFont(FONT, 13, EllesmereUI.GetFontOutlineFlag())
                            lbl:SetPoint("LEFT",  itm, "LEFT",  10, 0)
                            lbl:SetPoint("RIGHT", itm, "RIGHT", -(X_SZ * 3 + 30), 0)
                            lbl:SetJustifyH("LEFT")
                            lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            itm._lbl = lbl

                            local hl = itm:CreateTexture(nil, "ARTWORK")
                            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                            itm._hl = hl

                            local xBtn = CreateFrame("Button", nil, itm)
                            xBtn:SetSize(X_SZ, X_SZ)
                            xBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                            xBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                            local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
                            xIcon:SetAllPoints()
                            if xIcon.SetSnapToPixelGrid then xIcon:SetSnapToPixelGrid(false); xIcon:SetTexelSnappingBias(0) end
                            xIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
                            xBtn:SetAlpha(0.4)
                            itm._xBtn = xBtn

                            local editBtn = CreateFrame("Button", nil, itm)
                            editBtn:SetSize(X_SZ, X_SZ)
                            editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
                            editBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                            local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
                            editIcon:SetAllPoints()
                            if editIcon.SetSnapToPixelGrid then editIcon:SetSnapToPixelGrid(false); editIcon:SetTexelSnappingBias(0) end
                            editIcon:SetTexture(MEDIA .. "icons\\eui-edit.png")
                            editBtn:SetAlpha(0.4)
                            itm._editBtn = editBtn

                            local kbBtnI = CreateFrame("Button", nil, itm)
                            kbBtnI:SetSize(X_SZ, X_SZ)
                            kbBtnI:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)
                            kbBtnI:SetFrameLevel(itm:GetFrameLevel() + 2)
                            local kbIconI = kbBtnI:CreateTexture(nil, "OVERLAY")
                            kbIconI:SetAllPoints()
                            if kbIconI.SetSnapToPixelGrid then kbIconI:SetSnapToPixelGrid(false); kbIconI:SetTexelSnappingBias(0) end
                            kbIconI:SetTexture(MEDIA .. "icons\\eui-keybind-2.png")
                            kbBtnI:SetAlpha(0.4)
                            itm._kbBtn = kbBtnI

                            local function IsOverInlineBtn()
                                return xBtn:IsMouseOver() or editBtn:IsMouseOver() or kbBtnI:IsMouseOver()
                            end

                            local function SetAllInlineAlpha(a)
                                xBtn:SetAlpha(a); editBtn:SetAlpha(a); kbBtnI:SetAlpha(a)
                            end

                            itm:SetScript("OnEnter", function()
                                lbl:SetTextColor(1, 1, 1, 1)
                                hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                                SetAllInlineAlpha(0.8)
                            end)
                            itm:SetScript("OnLeave", function()
                                if IsOverInlineBtn() then return end
                                lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                                hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                                SetAllInlineAlpha(0.4)
                            end)

                            local function InlineBtnEnter(self)
                                lbl:SetTextColor(1, 1, 1, 1)
                                hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                                SetAllInlineAlpha(0.8)
                                self:SetAlpha(1)
                            end
                            local function InlineBtnLeave(hoveredSelf)
                                if itm:IsMouseOver() or IsOverInlineBtn() then
                                    hoveredSelf:SetAlpha(0.8)
                                    return
                                end
                                lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                                hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                                SetAllInlineAlpha(0.4)
                            end

                            xBtn:SetScript("OnEnter", function(self)
                                InlineBtnEnter(self)
                                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Delete"))
                            end)
                            xBtn:SetScript("OnLeave", function(self)
                                InlineBtnLeave(self)
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            editBtn:SetScript("OnEnter", function(self)
                                InlineBtnEnter(self)
                                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Rename"))
                            end)
                            editBtn:SetScript("OnLeave", function(self)
                                InlineBtnLeave(self)
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            kbBtnI:SetScript("OnEnter", function(self)
                                InlineBtnEnter(self)
                                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Keybind"))
                            end)
                            kbBtnI:SetScript("OnLeave", function(self)
                                InlineBtnLeave(self)
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            menuItems[idx] = itm
                        end

                        itm:SetPoint("TOPLEFT",  menu, "TOPLEFT",  1, -mH)
                        itm:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                        itm._lbl:SetText(name)
                        itm._isSel = (name == activeName)
                        itm._hl:SetAlpha(itm._isSel and 0.04 or 0)

                        local capName = name
                        local specLocked = specAssigned and specAssigned ~= capName

                        if specLocked then
                            itm._lbl:SetTextColor(1, 1, 1, 0.25)
                            itm._xBtn:Hide()
                            itm._editBtn:Hide()
                            itm._kbBtn:Hide()
                            itm:SetScript("OnClick", nil)
                            itm:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(itm, EllesmereUI.L("Your current spec has an assigned profile so you cannot switch to another. Please unassign to switch."))
                            end)
                            itm:SetScript("OnLeave", function()
                                EllesmereUI.HideWidgetTooltip()
                            end)
                        else
                            local iLbl, iHl, iXBtn, iEditBtn, iKbBtnL = itm._lbl, itm._hl, itm._xBtn, itm._editBtn, itm._kbBtn
                            iLbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            iEditBtn:Show()
                            iKbBtnL:Show()
                            if capName == activeName then
                                iXBtn:Hide()
                                iEditBtn:ClearAllPoints()
                                iEditBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                            else
                                iXBtn:Show()
                                iEditBtn:ClearAllPoints()
                                iEditBtn:SetPoint("RIGHT", iXBtn, "LEFT", -4, 0)
                            end
                            local function IsOverInline()
                                return iXBtn:IsMouseOver() or iEditBtn:IsMouseOver() or iKbBtnL:IsMouseOver()
                            end
                            local function SetAllAlpha(a)
                                iXBtn:SetAlpha(a); iEditBtn:SetAlpha(a); iKbBtnL:SetAlpha(a)
                            end
                            itm:SetScript("OnEnter", function()
                                iLbl:SetTextColor(1, 1, 1, 1)
                                iHl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                                SetAllAlpha(0.8)
                            end)
                            itm:SetScript("OnLeave", function()
                                if IsOverInline() then return end
                                iLbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                                iHl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                                SetAllAlpha(0.4)
                            end)
                            itm:SetScript("OnClick", function()
                                if capName == activeName then return end
                                menu:Hide()
                                local _, profs = EllesmereUI.GetProfileList()
                                local fontWillChange = EllesmereUI.ProfileChangesFont(profs and profs[capName])
                                local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins
                                    and EllesmereUI.ProfileChangesWindowSkins(profs and profs[capName])
                                local styleWillChange = EllesmereUI.ProfileChangesStyle
                                    and EllesmereUI.ProfileChangesStyle(profs and profs[capName])
                                EllesmereUI.SwitchProfile(capName)
                                ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                -- true = budgeted: manual swap site,
                                -- watchdog-sliced module refresh.
                                EllesmereUI.RefreshAllAddons(true)
                                if fontWillChange or skinsWillChange or styleWillChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = EllesmereUI.L("Reload Required"),
                                        message     = fontWillChange
                                            and EllesmereUI.L("Font changed. A UI reload is needed to apply the new font.")
                                            or skinsWillChange
                                            and EllesmereUI.L("Window skins changed for this profile. A UI reload is needed to apply them.")
                                            or EllesmereUI.L("Style changed for this profile. A UI reload is needed to apply it."),
                                        confirmText = EllesmereUI.L("Reload Now"),
                                        cancelText  = EllesmereUI.L("Later"),
                                        reload      = true,
                                    })
                                else
                                    -- Invalidate cached pages so per-profile lists (e.g. the CDM bar dropdown) rebuild: a live swap only
                                    -- re-points db.profile, so cached pages would show the old profile until reload.
                                    EllesmereUI:InvalidatePageCache()
                                    EllesmereUI:RefreshPage(true)
                                end
                            end)
                            iXBtn:SetScript("OnClick", function()
                                if capName == activeName then return end
                                menu:Hide()
                                EllesmereUI:ShowConfirmPopup({
                                    title       = EllesmereUI.L("Delete Profile"),
                                    message     = EllesmereUI.Lf("Delete \"%1$s\"?", capName),
                                    confirmText = EllesmereUI.L("Delete"),
                                    cancelText  = EllesmereUI.L("Cancel"),
                                    onConfirm   = function()
                                        EllesmereUI.DeleteProfile(capName)
                                        ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                        EllesmereUI:InvalidatePageCache()
                                        EllesmereUI:RefreshPage(true)
                                    end,
                                })
                            end)
                            iEditBtn:SetScript("OnClick", function()
                                menu:Hide()
                                EllesmereUI:ShowInputPopup({
                                    title       = EllesmereUI.L("Rename Profile"),
                                    message     = EllesmereUI.Lf("Enter a new name for \"%1$s\":", capName),
                                    placeholder = capName,
                                    confirmText = EllesmereUI.L("Rename"),
                                    cancelText  = EllesmereUI.L("Cancel"),
                                    onConfirm   = function(newName)
                                        newName = newName and strtrim(newName) or ""
                                        if newName == "" or newName == capName then return end
                                        if newName == "Default" then
                                            print(EllesmereUI.L("|cffff6060[EllesmereUI]|r Cannot rename to \"Default\"."))
                                            return
                                        end
                                        local _, profs = EllesmereUI.GetProfileList()
                                        if profs and profs[newName] then
                                            print(EllesmereUI.Lf("|cffff6060[EllesmereUI]|r A profile named \"%1$s\" already exists.", newName))
                                            return
                                        end
                                        EllesmereUI.RenameProfile(capName, newName)
                                        ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                        EllesmereUI:InvalidatePageCache()
                                        EllesmereUI:RefreshPage(true)
                                    end,
                                })
                            end)
                            iKbBtnL:SetScript("OnClick", function()
                                menu:Hide()
                                ShowProfileKeybindPopup(capName)
                            end)
                        end

                        itm:Show()
                        mH = mH + 26
                    end
                end
                menu:SetHeight(mH + 4)
            end

            local function ActiveApplyNormal()
                ddLabelFS:SetTextColor(aS[17], aS[18], aS[19], aS[20])
                ddBrd:SetColor(aS[9], aS[10], aS[11], aS[12])
                ddBg:SetColorTexture(aS[1], aS[2], aS[3], aS[4])
            end
            local function ActiveApplyHover()
                ddLabelFS:SetTextColor(aS[21], aS[22], aS[23], aS[24])
                ddBrd:SetColor(aS[13], aS[14], aS[15], aS[16])
                ddBg:SetColorTexture(aS[5], aS[6], aS[7], aS[8])
            end

            ddBtn:SetScript("OnClick", function()
                if menu:IsShown() then menu:Hide()
                else RebuildProfileMenu(); menu:Show() end
            end)
            ddBtn:SetScript("OnEnter", function() ActiveApplyHover() end)
            ddBtn:SetScript("OnLeave", function()
                if not menu:IsShown() then ActiveApplyNormal() end
            end)
            ddBtn:HookScript("OnHide", function() menu:Hide() end)
            menu:HookScript("OnShow", function()
                ActiveApplyHover()
            end)
            menu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if ddBtn:IsMouseOver() then ActiveApplyHover()
                else ActiveApplyNormal() end
            end)

            -- "Assign to Spec" label
            local specLabel = EllesmereUI.MakeFont(rowFrame, 12, nil, 1, 1, 1, 0.45)
            PP.Point(specLabel, "LEFT", profLabel, "LEFT", DD_W + GAP, 0)
            specLabel:SetText(EllesmereUI.L("Assign to Spec"))
            specLabel:SetJustifyH("LEFT")

            -- Assign to Spec button
            local assignBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(assignBtn, BTN_W, CTRL_H)
            PP.Point(assignBtn, "TOPLEFT", specLabel, "BOTTOMLEFT", 0, -6)
            assignBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(assignBtn, "Assign to Spec", 11, PROF_BTN_COLOURS, function()
                local db = EllesmereUIDB or {}
                if not db.specProfiles then db.specProfiles = {} end
                local tempDB = { _profileSpecs = {} }
                local order, profiles = EllesmereUI.GetProfileList()
                for _, pName in ipairs(order) do tempDB._profileSpecs[pName] = {} end
                for specID, pName in pairs(db.specProfiles) do
                    if tempDB._profileSpecs[pName] then
                        tempDB._profileSpecs[pName][specID] = true
                    end
                end
                local curActiveName = EllesmereUI.GetActiveProfileName()
                EllesmereUI:ShowSpecAssignPopup({
                    db = tempDB,
                    dbKey = "_profileSpecs",
                    presetKey = curActiveName,
                    allPresetKeys = function()
                        local list = {}
                        for _, n in ipairs(order) do
                            if profiles[n] then list[#list + 1] = { key = n, name = n } end
                        end
                        return list
                    end,
                    onDone = function()
                        db.specProfiles = {}
                        for pName, specSet in pairs(tempDB._profileSpecs) do
                            for specID in pairs(specSet) do
                                db.specProfiles[specID] = pName
                            end
                        end
                        EllesmereUI:RefreshPage()
                    end,
                })
            end)

            -- "New Profile" label
            local newLabel = EllesmereUI.MakeFont(rowFrame, 12, nil, 1, 1, 1, 0.45)
            PP.Point(newLabel, "LEFT", specLabel, "LEFT", BTN_W + GAP, 0)
            newLabel:SetText(EllesmereUI.L("New Profile"))
            newLabel:SetJustifyH("LEFT")

            -- "Create New (Copy)" button
            local copyBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(copyBtn, BTN_W, CTRL_H)
            PP.Point(copyBtn, "TOPLEFT", newLabel, "BOTTOMLEFT", 0, -6)
            copyBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(copyBtn, "Create New (Copy)", 11, PROF_BTN_COLOURS, function()
                EllesmereUI:ShowInputPopup({
                    title       = EllesmereUI.L("Copy Profile"),
                    message     = EllesmereUI.L("Enter a name for the new profile:"),
                    placeholder = EllesmereUI.L("My Profile"),
                    confirmText = EllesmereUI.L("Save"),
                    cancelText  = EllesmereUI.L("Cancel"),
                    onConfirm   = function(name)
                        if not name or name == "" then return end
                        local _, profiles = EllesmereUI.GetProfileList()
                        if profiles and profiles[name] then
                            EllesmereUI:ShowConfirmPopup({
                                title = EllesmereUI.L("Name Taken"),
                                message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                                confirmText = EllesmereUI.L("OK"),
                                hideCancel = true,
                                onConfirm = function() end,
                            })
                            return
                        end
                        EllesmereUI.SaveCurrentAsProfile(name)
                        ReloadUI()
                    end,
                })
            end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  PER-ADDON EXPORT
        -------------------------------------------------------------------
        _, h = W:Spacer(parent, y, 18);  y = y - h

        do
            local ADDON_DB_MAP_LOCAL = EllesmereUI.VisibleProfileAddons(EllesmereUI._ADDON_DB_MAP)
            local PAD        = EllesmereUI.CONTENT_PAD
            local totalW     = parent:GetWidth() - PAD * 2
            local ROW_H_A    = 48
            local CHK_SZ     = 18
            local STATUS_W   = 70
            local SIDE_PAD   = 26
            local HDR_H      = 72
            local COL_HDR_H  = 28
            -- Single footer row: count + "Include layout" + "Include Global Settings" side by side, Export button on the right.
            local FOOTER_H   = 50
            local READY_R, READY_G, READY_B = 0.196, 0.737, 0.325
            local SKIP_A     = 0.35

            -- Short descriptions per addon folder
            local ADDON_DESCS = {
                EllesmereUIActionBars        = "Modern action bars built for performance and clarity.",
                EllesmereUINameplates        = "Clean, lightweight nameplates with endless customization.",
                EllesmereUIUnitFrames        = "Simple unit frames with a modern visual style.",
                EllesmereUICooldownManager   = "A CDM replacement focused on performance, customizations and alerts.",
                EllesmereUIResourceBars      = "Custom Resource Bars with thresholds, hash lines and more.",
                EllesmereUIRaidFrames        = "Incredibly light performance, modern raid frames with endless flexibility.",
                EllesmereUIAuraBuffReminders = "Simple raid buff, auras, consumables and talent reminders.",
                EllesmereUIQoL               = "Lightweight quality of life tools and enhancements.",
                EllesmereUIDragonRiding      = "Skyriding HUD with speed, vigor and second wind tracking.",
                EllesmereUIBlizzardSkin       = "Clean and beautiful visual refreshes for Blizzard UI elements.",
                EllesmereUIFriends           = "A modern friends list with built-in organization tools.",
                EllesmereUIMythicTimer       = "Mythic+ timer, targeted spell bars, and standalone cast bars.",
                EllesmereUIQuestTracker      = "A clean, updated reskin of Blizzard's Quest Tracker.",
                EllesmereUIMinimap           = "A new age minimap with clean styling and square layout options.",
                EllesmereUIDamageMeters      = "Lightweight damage meters with simple but powerful customization.",
                EllesmereUIChat              = "Modern chat enhancements with useful utilities.",
                EllesmereUIBags              = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
                EllesmereUIQuickdraw         = "Hold a key to open a menu of actions; point or scroll to choose, release to fire.",
            }

            local SCROLL_MAX_H = 285
            local contentH = #ADDON_DB_MAP_LOCAL * ROW_H_A
            local scrollH = math.min(contentH, SCROLL_MAX_H)
            local SECTION_H = HDR_H + COL_HDR_H + scrollH + 8 + FOOTER_H

            -- Non-interactive panel behind the whole section.
            local sectionBg = CreateFrame("Frame", nil, parent)
            sectionBg:SetFrameLevel(parent:GetFrameLevel())
            PP.Size(sectionBg, totalW, SECTION_H)
            PP.Point(sectionBg, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            sectionBg:EnableMouse(false)
            local sBg = sectionBg:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(sectionBg, 1, 1, 1, 0.10, PP)

            local hdrFrame = CreateFrame("Frame", nil, parent)
            PP.Size(hdrFrame, totalW, HDR_H)
            PP.Point(hdrFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

            local hdrTitle = EllesmereUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
            PP.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
            hdrTitle:SetText(EllesmereUI.L("Export Profile"))
            hdrTitle:SetJustifyH("LEFT")

            local hdrDesc = EllesmereUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
            PP.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
            PP.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
            hdrDesc:SetText(EllesmereUI.L("Choose which addons to include in your exported profile. Check everything for a full profile export."))
            hdrDesc:SetJustifyH("LEFT")
            hdrDesc:SetWordWrap(true)

            local hdrDiv = hdrFrame:CreateTexture(nil, "ARTWORK")
            hdrDiv:SetColorTexture(1, 1, 1, 0.10)
            hdrDiv:SetHeight(1)
            PP.Point(hdrDiv, "BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", SIDE_PAD, 0)
            PP.Point(hdrDiv, "BOTTOMRIGHT", hdrFrame, "BOTTOMRIGHT", -SIDE_PAD, 0)
            if hdrDiv.SetSnapToPixelGrid then hdrDiv:SetSnapToPixelGrid(false); hdrDiv:SetTexelSnappingBias(0) end

            -- Build addon item list
            local selectedAddons = {}
            local includeLayoutExport = true     -- "Unlock Mode Layout" include (default on)
            local includeGlobalsExport = true    -- "Global Settings" include (default on)
            -- "Overrides" include: nil = AUTO -- ON when every loaded module is checked, OFF for subsets, until the user toggles it in the
            -- Include dropdown. Resolved via EffectiveIncludeOverrides (footer block).
            local includeOverridesExport = nil
            local EffectiveIncludeOverrides
            -- "Window & Tooltip Skins": the Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups). Default OFF --
            -- an importer who opts in gets them across ALL of their profiles.
            local includeWindowSkinsExport = false
            local addonItems = {}
            local addonVisuals = {}
            local footerCountFs
            -- Module connectivity from the LIVE active-profile layout (LOCAL folders, matching selectedAddons' keyspace). Drives the hard-couple + affordance.
            local exportComponents = EllesmereUI.BuildModuleComponents({
                anchors     = EllesmereUIDB and EllesmereUIDB.unlockAnchors,
                widthMatch  = EllesmereUIDB and EllesmereUIDB.unlockWidthMatch,
                heightMatch = EllesmereUIDB and EllesmereUIDB.unlockHeightMatch,
            })
            local FOLDER_DISPLAY = {}
            for _, e in ipairs(ADDON_DB_MAP_LOCAL) do FOLDER_DISPLAY[e.folder] = e.display end

            for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
                local loaded = EllesmereUI.IsModuleAddonLoaded(entry.folder)
                local folder = entry.folder
                addonItems[#addonItems + 1] = {
                    folder  = folder,
                    display = entry.display,
                    desc    = ADDON_DESCS[folder] or "",
                    loaded  = loaded,
                    getVal  = function() return selectedAddons[folder] or false end,
                    -- Hard-couple: (un)checking a module sets its whole connected component, gated to loaded (exportable) members.
                    setVal  = function(v)
                        -- Layout OFF: relationships aren't exported, so skip the hard-couple and let each linked module be picked alone.
                        local members = includeLayoutExport and exportComponents and exportComponents[folder]
                        if members then
                            for f in pairs(members) do
                                if EllesmereUI.IsModuleAddonLoaded(f) then selectedAddons[f] = v or nil end
                            end
                        else
                            selectedAddons[folder] = v or nil
                        end
                    end,
                }
                if loaded then selectedAddons[folder] = true end
            end

            local function RefreshFooterCount()
                if not footerCountFs then return end
                local count = 0
                for _ in pairs(selectedAddons) do count = count + 1 end
                footerCountFs:SetText(EllesmereUI.Lf("Export will include %1$s of %2$s addons.", count, #addonItems))
            end

            local _refreshSelAllColor
            local function RefreshAllAddonVisuals()
                for _, fn in ipairs(addonVisuals) do fn() end
                RefreshFooterCount()
                if _refreshSelAllColor then _refreshSelAllColor() end
            end

            do
                local LINK_GAP = 12
                local selAllBtn = CreateFrame("Button", nil, hdrFrame)
                selAllBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
                local selAllLbl = selAllBtn:CreateFontString(nil, "OVERLAY")
                selAllLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
                selAllLbl:SetText(EllesmereUI.L("Select All"))
                selAllLbl:SetTextColor(1, 1, 1, 0.40)
                selAllLbl:SetPoint("CENTER")
                selAllBtn:SetSize(selAllLbl:GetStringWidth() + 4, 18)
                selAllBtn:SetPoint("RIGHT", hdrFrame, "RIGHT", -(STATUS_W + LINK_GAP + SIDE_PAD), 0)
                selAllBtn:SetPoint("TOP", hdrDesc, "TOP", 0, 0)

                local function AllSelected()
                    for _, item in ipairs(addonItems) do
                        if item.loaded and not item.getVal() then return false end
                    end
                    return true
                end

                local function RefreshSelAllColor()
                    if AllSelected() then
                        selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
                    else
                        selAllLbl:SetTextColor(1, 1, 1, 0.40)
                    end
                end

                _refreshSelAllColor = RefreshSelAllColor
                RefreshSelAllColor()

                selAllBtn:SetScript("OnEnter", function()
                    if AllSelected() then
                        selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                    else
                        selAllLbl:SetTextColor(1, 1, 1, 0.80)
                    end
                end)
                selAllBtn:SetScript("OnLeave", function() RefreshSelAllColor() end)
                selAllBtn:SetScript("OnClick", function()
                    for _, item in ipairs(addonItems) do
                        if item.loaded then item.setVal(true) end
                    end
                    RefreshAllAddonVisuals()
                end)

                local linkDiv = hdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                linkDiv:SetColorTexture(1, 1, 1, 0.15)
                if linkDiv.SetSnapToPixelGrid then linkDiv:SetSnapToPixelGrid(false); linkDiv:SetTexelSnappingBias(0) end
                PP.Point(linkDiv, "LEFT", selAllBtn, "RIGHT", LINK_GAP / 2, 0)
                linkDiv:SetWidth(1)
                linkDiv:SetHeight(10)

                local deselBtn = CreateFrame("Button", nil, hdrFrame)
                deselBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
                local deselLbl = deselBtn:CreateFontString(nil, "OVERLAY")
                deselLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
                deselLbl:SetText(EllesmereUI.L("Deselect All"))
                deselLbl:SetTextColor(1, 1, 1, 0.40)
                deselLbl:SetPoint("CENTER")
                deselBtn:SetSize(deselLbl:GetStringWidth() + 4, 18)
                PP.Point(deselBtn, "LEFT", selAllBtn, "RIGHT", LINK_GAP, 0)
                deselBtn:SetScript("OnEnter", function() deselLbl:SetTextColor(1, 1, 1, 0.80) end)
                deselBtn:SetScript("OnLeave", function() deselLbl:SetTextColor(1, 1, 1, 0.40) end)
                deselBtn:SetScript("OnClick", function()
                    for _, item in ipairs(addonItems) do
                        item.setVal(false)
                    end
                    RefreshAllAddonVisuals()
                end)
            end

            y = y - HDR_H

            local colHdrFrame = CreateFrame("Frame", nil, parent)
            PP.Size(colHdrFrame, totalW, COL_HDR_H)
            PP.Point(colHdrFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

            local colAddon = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(colAddon, "LEFT", colHdrFrame, "LEFT", SIDE_PAD, 0)
            colAddon:SetText(EllesmereUI.L("Addon"))
            colAddon:SetJustifyH("LEFT")

            local colStatus = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(colStatus, "RIGHT", colHdrFrame, "RIGHT", -SIDE_PAD, 0)
            colStatus:SetText(EllesmereUI.L("Status"))
            colStatus:SetJustifyH("RIGHT")

            -- Include column: centered at a fixed X so checkboxes can align to it
            local INCLUDE_CENTER_X = -(SIDE_PAD + STATUS_W + 30 + CHK_SZ / 2)
            local colInclude = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(colInclude, "CENTER", colHdrFrame, "RIGHT", INCLUDE_CENTER_X, 0)
            colInclude:SetText(EllesmereUI.L("Include"))
            colInclude:SetJustifyH("CENTER")

            y = y - COL_HDR_H

            -- Scrollable addon list (max 300px)
            local scrollClip = CreateFrame("Frame", nil, parent)
            PP.Size(scrollClip, totalW, scrollH)
            PP.Point(scrollClip, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            scrollClip:SetClipsChildren(true)

            local scrollFrame = CreateFrame("ScrollFrame", nil, scrollClip)
            scrollFrame:SetAllPoints()

            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetSize(totalW, contentH)
            scrollFrame:SetScrollChild(scrollChild)

            -- Mouse wheel scrolling
            local scrollOffset = 0
            scrollClip:EnableMouseWheel(true)
            scrollClip:SetScript("OnMouseWheel", function(_, delta)
                local maxScroll = math.max(0, contentH - scrollH)
                scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - delta * ROW_H_A))
                scrollFrame:SetVerticalScroll(scrollOffset)
            end)

            -- Addon rows (parented to scrollChild)
            local rowY = 0
            for i, item in ipairs(addonItems) do
                local rowFrame = CreateFrame("Frame", nil, scrollChild)
                rowFrame:SetSize(totalW, ROW_H_A)
                rowFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -rowY)

                -- Alternating row bg
                local rowAlpha = (i % 2 == 0) and 0.12 or 0.06
                local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(0, 0, 0, rowAlpha)

                -- Addon name
                local nameFs = EllesmereUI.MakeFont(rowFrame, 13, nil, 1, 1, 1, 0.9)
                nameFs:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", SIDE_PAD, -10)
                nameFs:SetPoint("RIGHT", rowFrame, "RIGHT", -(CHK_SZ + STATUS_W + SIDE_PAD * 2 + 20), 0)
                nameFs:SetJustifyH("LEFT")
                nameFs:SetWordWrap(false)
                nameFs:SetText(EllesmereUI.L(item.display))

                -- Addon description
                local descFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.30)
                descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
                descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(EllesmereUI.L(item.desc))

                -- Status badge
                local statusFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.40)
                statusFs:SetPoint("RIGHT", rowFrame, "RIGHT", -SIDE_PAD, 0)
                statusFs:SetJustifyH("RIGHT")

                -- Checkbox (centered under Include column header)
                local chkFrame = CreateFrame("Frame", nil, rowFrame)
                chkFrame:SetSize(CHK_SZ, CHK_SZ)
                chkFrame:SetPoint("CENTER", rowFrame, "RIGHT", INCLUDE_CENTER_X, 0)

                local chkBg = chkFrame:CreateTexture(nil, "BACKGROUND")
                chkBg:SetAllPoints()
                chkBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                if chkBg.SetSnapToPixelGrid then chkBg:SetSnapToPixelGrid(false); chkBg:SetTexelSnappingBias(0) end

                local chkBrd = EllesmereUI.MakeBorder(chkFrame, 0.25, 0.25, 0.28, 0.6, PP)

                local chkMark = chkFrame:CreateTexture(nil, "ARTWORK")
                chkMark:SetPoint("TOPLEFT", chkFrame, "TOPLEFT", 3, -3)
                chkMark:SetPoint("BOTTOMRIGHT", chkFrame, "BOTTOMRIGHT", -3, 3)
                chkMark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                if chkMark.SetSnapToPixelGrid then chkMark:SetSnapToPixelGrid(false); chkMark:SetTexelSnappingBias(0) end

                local function ApplyRowVisual()
                    local on = item.getVal()
                    if not item.loaded then
                        nameFs:SetAlpha(0.30)
                        descFs:SetAlpha(0.15)
                        chkMark:Hide()
                        chkBg:SetAlpha(0.3)
                        statusFs:SetText(EllesmereUI.L("Not Loaded"))
                        statusFs:SetTextColor(1, 1, 1, 0.25)
                    elseif on then
                        nameFs:SetAlpha(0.9)
                        descFs:SetAlpha(0.30)
                        chkMark:Show()
                        chkBg:SetAlpha(1)
                        chkBrd:SetColor(EG.r, EG.g, EG.b, 0.15)
                        statusFs:SetText(EllesmereUI.L("Ready"))
                        statusFs:SetTextColor(READY_R, READY_G, READY_B, 1)
                    else
                        nameFs:SetAlpha(0.50)
                        descFs:SetAlpha(0.20)
                        chkMark:Hide()
                        chkBg:SetAlpha(1)
                        chkBrd:SetColor(0.25, 0.25, 0.28, 0.6)
                        statusFs:SetText(EllesmereUI.L("Skipped"))
                        statusFs:SetTextColor(1, 1, 1, SKIP_A)
                    end
                end
                ApplyRowVisual()
                addonVisuals[#addonVisuals + 1] = ApplyRowVisual

                -- Hover highlight overlay
                local hoverTex = rowFrame:CreateTexture(nil, "ARTWORK")
                hoverTex:SetAllPoints()
                hoverTex:SetColorTexture(1, 1, 1, 0.05)
                hoverTex:Hide()

                if item.loaded then
                    local clickBtn = CreateFrame("Button", nil, rowFrame)
                    clickBtn:SetAllPoints(rowFrame)
                    clickBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
                    clickBtn:SetScript("OnClick", function()
                        item.setVal(not item.getVal())
                        -- Hard-couple co-toggles a whole component, so repaint EVERY row -- siblings lighting up is the "linked" affordance.
                        RefreshAllAddonVisuals()
                    end)
                    clickBtn:SetScript("OnEnter", function()
                        hoverTex:Show()
                        if not item.getVal() then nameFs:SetAlpha(0.75) end
                        -- Linked-modules tooltip; suppressed while layout is off, since nothing couples then.
                        local members = includeLayoutExport and exportComponents and exportComponents[item.folder]
                        if members then
                            local names = {}
                            for f in pairs(members) do
                                if f ~= item.folder then
                                    names[#names + 1] = (EllesmereUI.L(FOLDER_DISPLAY[f] or f))
                                end
                            end
                            if #names > 0 then
                                table.sort(names)
                                EllesmereUI.ShowWidgetTooltip(rowFrame,
                                    EllesmereUI.Lf("Linked by Anchor/Width/Height Matching to: %1$s. These export together.", table.concat(names, ", ")))
                            end
                        end
                    end)
                    clickBtn:SetScript("OnLeave", function()
                        hoverTex:Hide()
                        if not item.getVal() then nameFs:SetAlpha(0.50) end
                        EllesmereUI.HideWidgetTooltip()
                    end)
                else
                    local blockFrame = CreateFrame("Frame", nil, rowFrame)
                    blockFrame:SetAllPoints()
                    blockFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 5)
                    blockFrame:EnableMouse(true)
                    blockFrame:SetScript("OnEnter", function()
                        hoverTex:Show()
                        EllesmereUI.ShowWidgetTooltip(rowFrame, EllesmereUI.L("Addon not loaded"))
                    end)
                    blockFrame:SetScript("OnLeave", function()
                        hoverTex:Hide()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                rowY = rowY + ROW_H_A
            end

            y = y - scrollH

            -- Footer (inside the background panel)
            y = y - 8

            local footerFrame = CreateFrame("Frame", nil, parent)
            PP.Size(footerFrame, totalW, FOOTER_H)
            PP.Point(footerFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

            local footerDiv = footerFrame:CreateTexture(nil, "ARTWORK")
            footerDiv:SetColorTexture(1, 1, 1, 0.10)
            footerDiv:SetHeight(1)
            PP.Point(footerDiv, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, 0)
            PP.Point(footerDiv, "TOPRIGHT", footerFrame, "TOPRIGHT", -SIDE_PAD, 0)
            if footerDiv.SetSnapToPixelGrid then footerDiv:SetSnapToPixelGrid(false); footerDiv:SetTexelSnappingBias(0) end

            footerCountFs = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
            -- Selection count, top-left of the footer. The Include dropdown and Export Profile button sit right-aligned on the same row.
            PP.Point(footerCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
            footerCountFs:SetJustifyH("LEFT")
            RefreshFooterCount()

            local EXPORT_BTN_W = 180
            local EXPORT_BTN_H = 30
            local exportSelBtn = CreateFrame("Button", nil, footerFrame)
            PP.Size(exportSelBtn, EXPORT_BTN_W, EXPORT_BTN_H)
            PP.Point(exportSelBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)
            exportSelBtn:SetFrameLevel(footerFrame:GetFrameLevel() + 2)

            -- Styled to match the Done button: green border + text, dark bg, fade hover
            local DB = EllesmereUI.DARK_BG
            local eaBrd = EllesmereUI.MakeBorder(exportSelBtn, EG.r, EG.g, EG.b, 0.7, PP)
            local eaBg = EllesmereUI.SolidTex(exportSelBtn, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
            eaBg:SetAllPoints()
            local eaLbl = EllesmereUI.MakeFont(exportSelBtn, 12, nil, EG.r, EG.g, EG.b)
            eaLbl:SetAlpha(0.7)
            eaLbl:SetPoint("CENTER")
            eaLbl:SetText(EllesmereUI.L("Export Profile"))

            -- "Include:" checkbox dropdown -- Overrides / Unlock Mode Layout / Global Settings, immediately left of the Export Profile button.
            -- Overrides defaults to AUTO: on when every loaded module is checked, off for subsets, until explicitly toggled. Marks recompute
            -- on every open so the auto state is current whenever the menu is visible.
            do
                local function AllLoadedSelected()
                    for _, item in ipairs(addonItems) do
                        if item.loaded and not selectedAddons[item.folder] then return false end
                    end
                    return true
                end
                EffectiveIncludeOverrides = function()
                    if includeOverridesExport ~= nil then return includeOverridesExport end
                    return AllLoadedSelected()
                end

                local ddBtn, ddLabelFS = MakeDropdown(footerFrame, 190, EXPORT_BTN_H, function() return "" end)
                PP.Point(ddBtn, "RIGHT", exportSelBtn, "LEFT", -12, 0)

                local incLbl = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.6)
                PP.Point(incLbl, "RIGHT", ddBtn, "LEFT", -8, 0)
                incLbl:SetText(EllesmereUI.L("Include:"))

                -- The Window & Tooltip Skins row only exists when the Blizz UI Enhanced module is loaded (its bundle can't be built otherwise).
                local hasBlizzSkinRow = EllesmereUI.IsModuleAddonLoaded("EllesmereUIBlizzardSkin")

                local function Summary()
                    local parts = {}
                    local total = hasBlizzSkinRow and 4 or 3
                    if EffectiveIncludeOverrides() then parts[#parts + 1] = EllesmereUI.L("Overrides") end
                    if includeLayoutExport then parts[#parts + 1] = EllesmereUI.L("Layout") end
                    if includeGlobalsExport then parts[#parts + 1] = EllesmereUI.L("Globals") end
                    if hasBlizzSkinRow and includeWindowSkinsExport then parts[#parts + 1] = EllesmereUI.L("Window Skins") end
                    if #parts == 0 then return EllesmereUI.L("Nothing Extra") end
                    if #parts == total then return EllesmereUI.L("Everything") end
                    return table.concat(parts, ", ")
                end
                local function RefreshSummary() ddLabelFS:SetText(Summary()) end

                local rowDefs = {
                    { label = "Overrides",
                      tip   = "Include your complete override setup: spec and conditional override values, groups, their custom Unlock Mode layouts, and Buff Manager overrides. On import this replaces the recipient's overrides entirely.",
                      get   = function() return EffectiveIncludeOverrides() end,
                      set   = function() includeOverridesExport = not EffectiveIncludeOverrides() end },
                    { label = "Unlock Mode Layout",
                      tip   = "Include the anchor & size-match relationships between modules. Off = export each module's own positions only, with no cross-module tying.",
                      get   = function() return includeLayoutExport end,
                      set   = function() includeLayoutExport = not includeLayoutExport end },
                    { label = "Global Settings",
                      tip   = "Include fonts, custom colours, dark mode, accent colour and UI scale with this export. Off = only the selected modules' own settings export, keeping the recipient's global look.",
                      get   = function() return includeGlobalsExport end,
                      set   = function() includeGlobalsExport = not includeGlobalsExport end },
                }
                if hasBlizzSkinRow then
                    rowDefs[#rowDefs + 1] = {
                        label = "Window & Tooltip Skins",
                        tip   = "Include your Blizz UI Enhanced settings from the Window Skins and Tooltips, Menus & Popups tabs. These are account-wide: if the importer opts in, they overwrite that player's settings across ALL of their profiles.",
                        get   = function() return includeWindowSkinsExport end,
                        set   = function() includeWindowSkinsExport = not includeWindowSkinsExport end }
                end
                local menu = MakeDropdownMenu(ddBtn, 240)
                menu:SetSize(240, #rowDefs * 26 + 8)
                local marks = {}
                local function RefreshMenu()
                    for i, def in ipairs(rowDefs) do marks[i]:SetShown(def.get()) end
                end
                for i, def in ipairs(rowDefs) do
                    local row = CreateFrame("Button", nil, menu)
                    row:SetHeight(26)
                    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (i - 1) * 26))
                    row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
                    row:SetFrameLevel(menu:GetFrameLevel() + 1)
                    local hl = row:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                    local box = CreateFrame("Frame", nil, row)
                    box:SetSize(CHK_SZ, CHK_SZ)
                    box:SetPoint("LEFT", row, "LEFT", 6, 0)
                    local bbg = box:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints()
                    bbg:SetColorTexture(0.12, 0.12, 0.14, 1)
                    EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                    local mark = box:CreateTexture(nil, "ARTWORK")
                    mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                    mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                    mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    marks[i] = mark
                    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1, 0.7)
                    lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                    lbl:SetText(EllesmereUI.L(def.label))
                    row:SetScript("OnEnter", function()
                        hl:SetAlpha(0.05)
                        EllesmereUI.ShowWidgetTooltip(row, EllesmereUI.L(def.tip))
                    end)
                    row:SetScript("OnLeave", function()
                        hl:SetAlpha(0)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    row:SetScript("OnClick", function()
                        def.set()
                        RefreshMenu()
                        RefreshSummary()
                    end)
                end
                -- HookScript: MakeDropdownMenu owns OnShow (scale + outside-click close); our mark refresh rides alongside it.
                menu:HookScript("OnShow", RefreshMenu)
                ddBtn:SetScript("OnClick", function()
                    RefreshSummary()
                    if menu:IsShown() then menu:Hide() else RefreshMenu(); menu:Show() end
                end)
                -- Keep the AUTO-mode summary honest after module toggles.
                ddBtn:HookScript("OnEnter", RefreshSummary)
                RefreshSummary()
            end

            local eaProgress, eaTarget = 0, 0
            local EA_FADE = 0.1
            local eaLerp = EllesmereUI.lerp
            local function EAApply(t)
                eaLbl:SetTextColor(EG.r, EG.g, EG.b, eaLerp(0.7, 1, t))
                eaBrd:SetColor(EG.r, EG.g, EG.b, eaLerp(0.7, 1, t))
            end
            local function EAOnUpdate(self, elapsed)
                local dir = (eaTarget == 1) and 1 or -1
                eaProgress = eaProgress + dir * (elapsed / EA_FADE)
                if (dir == 1 and eaProgress >= 1) or (dir == -1 and eaProgress <= 0) then
                    eaProgress = eaTarget; self:SetScript("OnUpdate", nil)
                end
                EAApply(eaProgress)
            end
            exportSelBtn:SetScript("OnEnter", function(self) eaTarget = 1; self:SetScript("OnUpdate", EAOnUpdate) end)
            exportSelBtn:SetScript("OnLeave", function(self) eaTarget = 0; self:SetScript("OnUpdate", EAOnUpdate) end)
            exportSelBtn:SetScript("OnClick", function()
                local folders = {}
                local hasAny = false
                for folder in pairs(selectedAddons) do
                    folders[folder] = true
                    hasAny = true
                end
                if not hasAny then
                    if exportSelBtn._flashError then exportSelBtn._flashError() end
                    return
                end
                local activeName = EllesmereUI.GetActiveProfileName()
                -- Every loaded module checked = FULL export: pass nil folders so the string is a plain full-profile string (no subset stamps),
                -- keeping import defaults and API strings identical.
                local allSelected = true
                for _, item in ipairs(addonItems) do
                    if item.loaded and not selectedAddons[item.folder] then allSelected = false; break end
                end
                local exportFolders = (not allSelected) and folders or nil
                local includeOverrides = EffectiveIncludeOverrides and EffectiveIncludeOverrides() or false
                local function finishExport(includeCDM, cdmSpecs)
                    local str = EllesmereUI.ExportProfile(activeName, exportFolders, includeLayoutExport, includeCDM, cdmSpecs, includeGlobalsExport, includeOverrides, includeWindowSkinsExport)
                    if str then EllesmereUI:ShowExportPopup(str) end
                end
                -- If the CDM module is selected, run the shared flow (ask -> spec picker); otherwise export straight away with no CDM spell layout.
                if folders["EllesmereUICooldownManager"] then
                    EllesmereUI.RunCDMSpellExportFlow(activeName, finishExport)
                else
                    finishExport(false, nil)
                end
            end)
            exportSelBtn._flashError = BuildErrorFlash(exportSelBtn, eaBrd)

            y = y - FOOTER_H
        end

        -------------------------------------------------------------------
        --  Interactive Import API hookup (EllesmereUI.ImportProfileInteractive)
        -------------------------------------------------------------------
        -- Reset the sub-page stack to the main Profiles view. The page wrapper is cached across tab switches, so a declined/replaced API
        -- session would otherwise leave its import page showing on the next visit.
        EllesmereUI._ProfilesResetToMain = function()
            importPage:Hide()
            pastePage:Hide()
            mainPage:Show()
        end

        -- Continue an API session with its decoded payload: UI-scale prompt (at most once), then the normal selection page. Registered per
        -- build (latest wins) and re-resolved from the namespace by every async continuation, so decode + scale popup land on THIS build's live frames.
        EllesmereUI._ProfilesApiProceed = function(payload)
            local s = EllesmereUI._apiImportSession
            if not s or s.state == "done" then return end
            if s.scaleAsked then
                ShowImportPage(s.str, payload, s.name, nil, nil, s.applyScale)
            else
                MaybeConfirmUIScale(payload, function(applyScale)
                    s.scaleAsked = true
                    s.applyScale = applyScale
                    local go = EllesmereUI._ProfilesApiProceed
                    if go then go(payload) end
                end)
            end
        end

        -- Enter (or re-enter) a pending API import session: decode the string once, then proceed. Called by ImportProfileInteractive after it
        -- navigates here, and self-invoked at each build end so a session survives page rebuilds.
        EllesmereUI._ProfilesConsumeApiImport = function()
            local s = EllesmereUI._apiImportSession
            if not s or s.state == "done" then return end
            if EllesmereUI._EnsureApiImportCloseHook then EllesmereUI._EnsureApiImportCloseHook() end
            s.state = "active"
            if s.payload then
                EllesmereUI._ProfilesApiProceed(s.payload)
            elseif not s.decoding then
                s.decoding = true
                EllesmereUI.DecodeImportStringAsync(s.str, function(payload, err)
                    s.decoding = nil
                    -- The session may have been declined or replaced while the decode was in flight; drop a stale result.
                    if EllesmereUI._apiImportSession ~= s or s.state == "done" then return end
                    if not payload then
                        EllesmereUI:ShowInfoPopup({
                            title   = EllesmereUI.L("Import Failed"),
                            content = err or EllesmereUI.L("Invalid import string."),
                        })
                        EllesmereUI._FinishApiImportSession(false)
                        return
                    end
                    s.payload = payload
                    local go = EllesmereUI._ProfilesApiProceed
                    if go then go(payload) end
                end)
            end
        end
        EllesmereUI._ProfilesConsumeApiImport()

        return 0
    end

    ---------------------------------------------------------------------------
    --  Enabled Addons page
    ---------------------------------------------------------------------------

    -- Cleanup helper for profiles root (parented to scrollFrame, persists across page changes)
    local function CleanupProfilesRoot()
        if EllesmereUI._profilesRoot then
            EllesmereUI._profilesRoot:Hide()
            EllesmereUI._profilesRoot:SetParent(nil)
            EllesmereUI._profilesRoot = nil
        end
    end

    -- Profiles and Patch Notes are now their own sidebar pages (registered below), so Global Settings only owns General + Style + Fonts + Textures + Colors (Style second, beside General).
    local globalPages = { PAGE_GENERAL, PAGE_STYLE, PAGE_FONTS, PAGE_TEXTURES, PAGE_COLORS }

    EllesmereUI:RegisterModule(GLOBAL_KEY, {
        title       = "Global Settings",
        description = "General options for all EllesmereUI addons.",
        pages       = globalPages,
        buildPage   = function(pageName, parent, yOffset)
            -- CleanupProfilesRoot hides/nils the LIVE _profilesRoot, not anything scoped to this pageName. An off-screen search pre-build
            -- cycles pageName through PAGE_GENERAL/PAGE_FONTS/PAGE_TEXTURES/PAGE_COLORS regardless of what the player has open, so it would yank their real Profiles
            -- page away. This module's config.pages never includes PAGE_PROFILES anyway.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_GENERAL then
                    return BuildGeneralPage(pageName, parent, yOffset)
                elseif pageName == PAGE_FONTS then
                    return _G._EUI_BuildFontsPage and _G._EUI_BuildFontsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_TEXTURES then
                    return _G._EUI_BuildTexturesPage and _G._EUI_BuildTexturesPage(pageName, parent, yOffset)
                elseif pageName == PAGE_STYLE then
                    return _G._EUI_BuildStylePage and _G._EUI_BuildStylePage(pageName, parent, yOffset)
                elseif pageName == PAGE_COLORS then
                    return BuildColorsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_WHATSNEW then
                    return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
                end
                return
            end
            -- Clean up profiles root when switching to a non-Profiles tab
            if pageName ~= PAGE_PROFILES then
                CleanupProfilesRoot()
            end
            if pageName == PAGE_GENERAL then
                return BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_FONTS then
                return _G._EUI_BuildFontsPage and _G._EUI_BuildFontsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TEXTURES then
                return _G._EUI_BuildTexturesPage and _G._EUI_BuildTexturesPage(pageName, parent, yOffset)
            elseif pageName == PAGE_STYLE then
                return _G._EUI_BuildStylePage and _G._EUI_BuildStylePage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return BuildColorsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PROFILES then
                return BuildProfilesPage(pageName, parent, yOffset)
            elseif pageName == PAGE_WHATSNEW then
                return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end
        end,
        onPageCacheRestore = function(pageName)
            if pageName ~= PAGE_PROFILES then
                CleanupProfilesRoot()
            elseif pageName == PAGE_PROFILES and not EllesmereUI._profilesRoot then
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == GLOBAL_KEY then
                        BuildProfilesPage(PAGE_PROFILES, nil, -6)
                    end
                end)
            end
        end,
        onReset     = function()
            -- Reset CVars to EUI preferred defaults (ignoring current state)
            for _, entry in ipairs(EUI_DEFAULTS) do
                SetCVarSafe(entry[1], entry[2])
            end
            -- Reset style/theme settings (accent color, custom theme, class-colored)
            EllesmereUI.ResetTheme()
            -- Reset all custom class, power, and resource colors to defaults
            if EllesmereUIDB then
                EllesmereUIDB.customColors = nil
            end
            -- Reset fonts to defaults
            if EllesmereUIDB then
                EllesmereUIDB.fonts = nil
            end
            EllesmereUI.InvalidateFontCache()
            EllesmereUI.ApplyColorsToOUF()
            -- Reset panel scale to 100%
            if EllesmereUI.SetPanelScale then
                EllesmereUI:SetPanelScale(1.0)
            end
            -- Reset right-click targeting to default (disabled = off)
            if EllesmereUIDB then
                EllesmereUIDB.disableRightClickTarget = false
                EllesmereUIDB.disableRightClickTargetAllyCombat = false
                -- FPS + Secondary Stats are per-profile now; turn them off for the active profile (QoLExtrasSet) so the visible widgets actually clear.
                if EllesmereUI.QoLExtrasSet then
                    EllesmereUI.QoLExtrasSet("showFPS", false)
                    EllesmereUI.QoLExtrasSet("showSecondaryStats", false)
                end
                EllesmereUIDB.guildChatPrivacy = false
                EllesmereUIDB.repairWarning = nil
                -- Reset UI scale so next reload re-snapshots from Blizzard default
                EllesmereUIDB.ppUIScale = nil
                EllesmereUIDB.ppUIScaleAuto = nil
                -- Developer settings defaults
                EllesmereUIDB.showSpellID = false
                if EllesmereUI.SyncAuraSpellIDCVar then EllesmereUI.SyncAuraSpellIDCVar() end
                EllesmereUIDB.suppressErrors = true
                -- Crosshair: the root is the inherited global default, reset here (per-profile overrides clear with the profile's own reset).
                -- Root off = profiles without an override inherit "None".
                EllesmereUIDB.crosshairSize = "None"
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
                -- Reset unlock mode layout data
                EllesmereUIDB.unlockAnchors = nil
                EllesmereUIDB.unlockWidthMatch = nil
                EllesmereUIDB.unlockHeightMatch = nil
                EllesmereUIDB.unlockWidthMatchExtra = nil
                EllesmereUIDB.unlockHeightMatchExtra = nil
                -- QoL Features are NOT reset here; they have their own module reset
            end
            if EllesmereUI._applyRightClickTarget then
                EllesmereUI._applyRightClickTarget()
            end
            if EllesmereUI._applyHideBlizzardPartyFrame then
                EllesmereUI._applyHideBlizzardPartyFrame()
            end
            -- One call for both: the FPS readout may be drawn by the Secondary
            -- Stats block, so the two owners have to re-evaluate together.
            if EllesmereUI._applyFPSDisplay then
                EllesmereUI._applyFPSDisplay()
            elseif EllesmereUI._applySecondaryStats then
                EllesmereUI._applySecondaryStats()
            end
            if EllesmereUI._applyCrosshair then
                EllesmereUI._applyCrosshair()
            end
            if EllesmereUI._applyGuildChatPrivacy then
                EllesmereUI._applyGuildChatPrivacy()
            end
            -- Apply suppress errors default (on)
            SetCVarSafe("scriptErrors", "0")
            EllesmereUI:SelectPage(PAGE_GENERAL)
        end,
    })

    -- Profiles & Presets: its own sidebar module, reusing the profiles page builder; the profiles-root lifecycle rides the shared
    -- CleanupProfilesRoot hooks below (keyed to PROFILES_KEY). Second tab: the Overrides management list (built by EllesmereUI_SpecOverrides.lua).
    --
    -- ONE tab, TWO pages: "Spec Overrides" and "Conditional Overrides" stay completely separate page builders with their own stores, prune
    -- passes and row logic. The tab strip shows one "Overrides" entry and a centered segmented toggle picks the builder (the same control
    -- Raid Frames uses for Simple Setup / Custom Buff Display). The mode is runtime-only, defaulting to the spec list.
    local PAGE_OVERRIDES = "Overrides"

    -- Builds the centered mode toggle, returning the vertical space used. Plain local closure on purpose: no widget row, no capture config, no saved state.
    local function BuildOverridesModeToggle(parent, y)
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath())
            or "Fonts\\FRIZQT__.TTF"
        -- Wider than the Raid Frames pair (162): "Conditional Overrides" is a longer label than "Custom Buff Display" and must not clip.
        local BTN_W, BTN_H = 180, 31
        local wrap = CreateFrame("Frame", nil, parent)
        wrap:SetSize(BTN_W * 2, BTN_H)
        wrap:SetPoint("TOP", parent, "TOP", 0, y - 14)
        wrap:SetFrameLevel(parent:GetFrameLevel() + 1)
        if EllesmereUI.PP then
            EllesmereUI.PP.CreateBorder(wrap, 1, 1, 1, 0.10, 1)
        end
        local MODES = {
            { key = "spec", label = "Spec Overrides" },
            { key = "cond", label = "Conditional Overrides" },
        }
        local cur = EllesmereUI._overridesTabMode or "spec"
        for i, m in ipairs(MODES) do
            local btn = CreateFrame("Button", nil, wrap)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("LEFT", wrap, "LEFT", (i - 1) * BTN_W, 0)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetPoint("CENTER")
            lbl:SetText(EllesmereUI.L(m.label))
            if cur == m.key then
                bg:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                lbl:SetTextColor(1, 1, 1, 1)
            else
                bg:SetColorTexture(0.10, 0.10, 0.11, 0.85)
                lbl:SetTextColor(1, 1, 1, 0.55)
                btn:SetScript("OnEnter", function()
                    bg:SetColorTexture(0.16, 0.16, 0.17, 0.9); lbl:SetTextColor(1, 1, 1, 0.85)
                end)
                btn:SetScript("OnLeave", function()
                    bg:SetColorTexture(0.10, 0.10, 0.11, 0.85); lbl:SetTextColor(1, 1, 1, 0.55)
                end)
                btn:SetScript("OnClick", function()
                    EllesmereUI._overridesTabMode = m.key
                    -- Forced: the two builders render entirely different rows.
                    EllesmereUI:RefreshPage(true)
                end)
            end
        end
        -- 14 above + 15 below the buttons.
        return BTN_H + 29
    end

    -- FULL EXPORT tab: a warning and one button, with its own exporter (EllesmereUI.ExportFullAccountData) sharing NO code path with the
    -- Profiles tab's export flow, so nothing here changes a normal profile string.
    local PAGE_FULLEXPORT = "Full Export"

    local function BuildFullExportPage(parent, yOffset)
        local PAD = EllesmereUI.CONTENT_PAD or 40
        local y = yOffset - 10
        local width = parent:GetWidth() - PAD * 2

        -- Warning card (red-bordered, full width).
        local warn = CreateFrame("Frame", nil, parent)
        warn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        warn:SetWidth(width)
        warn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local wbg = EllesmereUI.SolidTex(warn, "BACKGROUND", 0.10, 0.04, 0.04, 0.55)
        wbg:SetAllPoints()
        EllesmereUI.MakeBorder(warn, 0.8, 0.2, 0.2, 0.55)
        local wtext = EllesmereUI.MakeFont(warn, 13, nil, 1, 0.55, 0.55, 1)
        wtext:SetPoint("TOPLEFT", warn, "TOPLEFT", 16, -14)
        wtext:SetWidth(width - 32)
        wtext:SetJustifyH("LEFT")
        wtext:SetSpacing(3)
        wtext:SetText(EllesmereUI.L("This export includes cross profile settings that will overwrite the importing user's settings including Quality of Life, Hovercast and more that should typically not be shared with standard profiles. THIS IS NOT RECOMMENDED for public sharing of profiles."))
        warn:SetHeight((wtext:GetStringHeight() or 40) + 28)
        y = y - warn:GetHeight() - 40

        -- Centered export button.
        local BTN_W, BTN_H = 300, 38
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", parent, "TOP", 0, y)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local DARK_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }
        local bbg = EllesmereUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bbg:SetAllPoints()
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local bbrd = EllesmereUI.MakeBorder(btn, EG.r, EG.g, EG.b, 0.5)
        local blbl = EllesmereUI.MakeFont(btn, 13, nil, EG.r, EG.g, EG.b, 1)
        blbl:SetAlpha(0.8)
        blbl:SetPoint("CENTER")
        blbl:SetText(EllesmereUI.L("Export All Data with Profile"))
        btn:SetScript("OnEnter", function()
            blbl:SetAlpha(1)
            if bbrd and bbrd.SetColor then bbrd:SetColor(EG.r, EG.g, EG.b, 0.9) end
        end)
        btn:SetScript("OnLeave", function()
            blbl:SetAlpha(0.8)
            if bbrd and bbrd.SetColor then bbrd:SetColor(EG.r, EG.g, EG.b, 0.5) end
        end)
        btn:SetScript("OnClick", function()
            local str = EllesmereUI.ExportFullAccountData and EllesmereUI.ExportFullAccountData()
            if str then
                EllesmereUI:ShowExportPopup(str)
            else
                EllesmereUI:ShowInfoPopup({
                    title = EllesmereUI.L("Export Failed"),
                    content = EllesmereUI.L("Could not build the export string."),
                })
            end
        end)
        y = y - BTN_H - 20

        return -y + 40
    end

    -- Runs the toggle, then the selected mode's builder. Builders return total content height measured from the ORIGINAL page top (they
    -- accumulate from the startY handed in), so the toggle's space is already included.
    local function BuildOverridesPage(parent, yOffset)
        local y = yOffset - BuildOverridesModeToggle(parent, yOffset)
        if (EllesmereUI._overridesTabMode or "spec") == "cond" then
            if EllesmereUI.Conditions_BuildListPage then
                return EllesmereUI.Conditions_BuildListPage(parent, y)
            end
        elseif EllesmereUI.SpecOverrides_BuildListPage then
            return EllesmereUI.SpecOverrides_BuildListPage(parent, y)
        end
        return 200
    end
    -- PAGE_PRESETS is a NAVIGATION tab only: the in-game browser is retired, so the tab shows the presets-website popup over the normal Profiles page.
    -- The tab builds the profiles page and flips it to the presets subpage via the pending flag consumed at the end of BuildProfilesPage.
    EllesmereUI:RegisterModule(PROFILES_KEY, {
        title       = "Profiles & Presets",
        description = "Import, export, and switch EllesmereUI profiles and presets.",
        pages       = { PAGE_PROFILES, PAGE_PRESETS, PAGE_OVERRIDES, PAGE_FULLEXPORT },
        buildPage   = function(pageName, parent, yOffset)
            -- BuildProfilesPage bypasses `parent` and builds onto the live shared _scrollFrame, and first checks the active profile against the
            -- current spec -- it can call SwitchProfile/RefreshAllAddons and pop a "Reload Required" confirmation. None of that is safe from a
            -- hidden indexing pass, so skip PAGE_PROFILES; it indexes on the player's first visit.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_OVERRIDES then
                    -- Index the spec list only: the conditional builder is not part of the hidden pre-build pass, and the toggle is chrome.
                    if EllesmereUI.SpecOverrides_BuildListPage then
                        return EllesmereUI.SpecOverrides_BuildListPage(parent, yOffset)
                    end
                    return 200
                end
                return
            end
            if pageName == PAGE_OVERRIDES then
                CleanupProfilesRoot()
                return BuildOverridesPage(parent, yOffset)
            end
            if pageName == PAGE_FULLEXPORT then
                CleanupProfilesRoot()
                return BuildFullExportPage(parent, yOffset)
            end
            if pageName == PAGE_PRESETS then
                -- The in-game presets browser is retired: the tab opens the
                -- website popup (copyable link) over the normal Profiles page.
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                return BuildProfilesPage(PAGE_PROFILES, parent, yOffset)
            end
            return BuildProfilesPage(pageName, parent, yOffset)
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_FULLEXPORT then
                -- The Profiles page builds onto the SHARED profiles root, which outlives page switches, so a cached Full Export page would show
                -- profiles content layered over it. The page itself is static, so cleanup is enough -- no rebuild.
                CleanupProfilesRoot()
            elseif pageName == PAGE_OVERRIDES then
                CleanupProfilesRoot()
                -- The override list changes while the page is cached; rebuild.
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY
                       and EllesmereUI:GetActivePage() == pageName then
                        EllesmereUI:RefreshPage(true)
                    end
                end)
            elseif pageName == PAGE_PRESETS then
                -- Retired browser: the tab shows the website popup over the
                -- normal Profiles view. An active API import session wins --
                -- re-enter it instead of hiding its import page.
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                if EllesmereUI._profilesRoot then
                    local s = EllesmereUI._apiImportSession
                    if s and s.state ~= "done" then
                        if EllesmereUI._ProfilesConsumeApiImport then
                            EllesmereUI._ProfilesConsumeApiImport()
                        end
                    elseif EllesmereUI._ProfilesResetToMain then
                        EllesmereUI._ProfilesResetToMain()
                    end
                else
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == PROFILES_KEY
                           and EllesmereUI:GetActivePage() == PAGE_PRESETS then
                            BuildProfilesPage(PAGE_PROFILES, nil, -6)
                        end
                    end)
                end
            elseif not EllesmereUI._profilesRoot then
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY then
                        BuildProfilesPage(PAGE_PROFILES, nil, -6)
                    end
                end)
            else
                -- Shared root is alive but the Presets tab may have left its subpage showing; the Profiles tab lands on main. An active API
                -- import session wins -- re-enter instead of hiding its page.
                local s = EllesmereUI._apiImportSession
                if s and s.state ~= "done" then
                    if EllesmereUI._ProfilesConsumeApiImport then
                        EllesmereUI._ProfilesConsumeApiImport()
                    end
                elseif EllesmereUI._ProfilesResetToMain then
                    EllesmereUI._ProfilesResetToMain()
                end
            end
        end,
    })

    -- The Presets tab is a dummy trigger: clicking it opens the website popup
    -- and must NOT become the active page (no tab underline, current page
    -- stays). All tab clicks route through SelectPage, so intercept it here;
    -- the PAGE_PRESETS buildPage/cache-restore branches above remain only as
    -- fallbacks for programmatic selects that bypass this wrapper.
    do
        local origSelectPage = EllesmereUI.SelectPage
        function EllesmereUI:SelectPage(pageName, ...)
            if pageName == PAGE_PRESETS and self.GetActiveModule
               and self:GetActiveModule() == PROFILES_KEY then
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                return
            end
            return origSelectPage(self, pageName, ...)
        end
    end

    -- Patch Notes: its own sidebar module (patch notes + the EUI Legends
    -- donor celebration page). Suite-only, never registered in standalone builds.
    if not IS_STANDALONE then
        EllesmereUI:RegisterModule(PATCHNOTES_KEY, {
            title       = "Patch Notes",
            description = EllesmereUI.L("What's new in EllesmereUI."),
            pages       = { PAGE_WHATSNEW, PAGE_LEGENDS },
            buildPage   = function(pageName, parent, yOffset)
                if pageName == PAGE_LEGENDS then
                    return EllesmereUI._BuildLegendsPage(pageName, parent, yOffset)
                end
                return EllesmereUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end,
        })

        -- "Special thanks to: <donor>" beside the header's close button, re-rolled
        -- on every panel open (weighted by _PickLegendsThanks); a click opens
        -- the EUI Legends page. Built on the first open.
        local thanksBtn
        local function RollThanks()
            local ca = EllesmereUI._clickArea
            if not ca then return end
            local name = EllesmereUI._PickLegendsThanks()
            if not name then
                if thanksBtn then thanksBtn:Hide() end
                return
            end
            if not thanksBtn then
                thanksBtn = CreateFrame("Button", nil, ca)
                thanksBtn:SetFrameLevel(ca:GetFrameLevel() + 20)
                thanksBtn:SetHeight(20)
                -- Vertically centred on the close X, 12px left of its box.
                thanksBtn:SetPoint("RIGHT", ca, "TOPRIGHT", -62, -31)
                local nameFs = EllesmereUI.MakeFont(thanksBtn, 13, nil, 1, 1, 1, 0.9)
                nameFs:SetPoint("RIGHT", thanksBtn, "RIGHT", 0, 0)
                local prefixFs = EllesmereUI.MakeFont(thanksBtn, 13, nil, 1, 1, 1, 0.45)
                prefixFs:SetPoint("RIGHT", nameFs, "LEFT", -4, 0)
                prefixFs:SetText(EllesmereUI.L("Special thanks to:"))
                thanksBtn._nameFs, thanksBtn._prefixFs = nameFs, prefixFs
                thanksBtn:SetScript("OnEnter", function(self)
                    self._prefixFs:SetAlpha(0.75)
                    self._nameFs:SetAlpha(1)
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("View EUI Legends"))
                end)
                thanksBtn:SetScript("OnLeave", function(self)
                    self._prefixFs:SetAlpha(0.45)
                    self._nameFs:SetAlpha(0.9)
                    EllesmereUI.HideWidgetTooltip()
                end)
                thanksBtn:SetScript("OnClick", function()
                    EllesmereUI.HideWidgetTooltip()
                    EllesmereUI:SelectModule(PATCHNOTES_KEY)
                    EllesmereUI:SelectPage(PAGE_LEGENDS)
                end)
            end
            local EG = EllesmereUI.ELLESMERE_GREEN
            thanksBtn._nameFs:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            thanksBtn._nameFs:SetText(name)
            thanksBtn:SetWidth(thanksBtn._nameFs:GetStringWidth() + 4 + thanksBtn._prefixFs:GetStringWidth())
            thanksBtn:Show()
        end
        EllesmereUI:RegisterOnShow(RollThanks)
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then RollThanks() end
    end

    -- Clean up profiles root when panel closes
    EllesmereUI:RegisterOnHide(function()
        CleanupProfilesRoot()
    end)

    -- Clean up profiles root when switching to any module other than Profiles
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName ~= PROFILES_KEY then
                CleanupProfilesRoot()
            end
        end)
    end

    -- Hook for HideAllChildren (framework calls this on page rebuilds)
    local origHideRoots = EllesmereUI._hideScrollFrameRoots
    EllesmereUI._hideScrollFrameRoots = function()
        if origHideRoots then origHideRoots() end
        CleanupProfilesRoot()
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
