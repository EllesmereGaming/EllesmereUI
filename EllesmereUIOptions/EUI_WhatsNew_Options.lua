if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Patch Notes and EUI Legends page builders; their content tables stay in EUI__General_Options.lua.

-------------------------------------------------------------------------------
--  What's New page -- three tiers: hero cards (2/row), small clickable
--  listings, fix lines. Content: EllesmereUI._WHATSNEW_PATCHES (newest
--  first). Entry `nav` deep-links via NavigateToElementSettings (opens page,
--  pulses control); no `nav` = static non-clickable card. File-scope fn so
--  it adds no locals/upvalues to the deferred options closure.
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
            if am ~= bm then
                -- Localization always closes the list.
                if am == "Localization" or bm == "Localization" then return bm == "Localization" end
                return am < bm
            end
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
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
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
                bg:SetColorTexture(0.119, 0.111, 0.104, 0.50); brd:SetColor(1, 1, 1, 0.22)
                titleFs:SetAlpha(1)
            end)
            card:SetScript("OnLeave", function()
                bg:SetColorTexture(0.077, 0.068, 0.058, 0.50); brd:SetColor(1, 1, 1, 0.12)
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
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
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
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.95)
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
        wbg:SetColorTexture(0.045, 0.035, 0.027, 1)
        -- Neutral border: the link-blue text carries the "this is the link" read.
        MakeBorder(urlWell, 1, 1, 1, 0.22, PP)

        -- Play badge standing left of the URL well (announcement-popup chip).
        local badge = CreateFrame("Frame", nil, card)
        badge:SetFrameLevel(card:GetFrameLevel() + 3)
        PP.Size(badge, 44, 44)
        PP.Point(badge, "RIGHT", urlWell, "LEFT", -16, 0)
        local chip = badge:CreateTexture(nil, "BACKGROUND")
        chip:SetAllPoints()
        chip:SetColorTexture(0.062, 0.050, 0.039, 0.95)
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
        boxBg:SetColorTexture(0.103, 0.095, 0.088, 1)
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
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Show a pulsing dot on the Patch Notes button whenever EllesmereUI updates to a new version."))
        end)
        row:SetScript("OnLeave", function()
            lbl:SetAlpha(0.5)
            EllesmereUI.HideWidgetTooltip()
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

        -- Tier 3: bug-fix lines. Full patches get a "BUG FIXES" header; a fixes-only mini patch drops it (the whole block is fixes), but a mini that also lists features keeps it so the fixes do not run on under them.
        local fixes = SortByModule(patch.fixes or {})
        if #fixes > 0 then
            if not isMini or #feats > 0 then
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
        seasonText = string.format("%s%s|r", EllesmereUI.HexColor(lead[1], lead[2], lead[3]), seasonText)
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
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.55)
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
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
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
            local maxScroll = EllesmereUI.SafeScrollRange(sf) or 0
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
            local maxScroll = EllesmereUI.SafeScrollRange(sf) or 0
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
            if EllesmereUI._ShiftWheelScale(delta) then return end
            local maxScroll = EllesmereUI.SafeScrollRange(self) or 0
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
