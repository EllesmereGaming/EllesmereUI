if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Patch Notes and EUI Legends page builders; their content tables stay in EUI__General_Options.lua.

-------------------------------------------------------------------------------
--  What's New page -- one expandable card per patch (the shared module card),
--  newest first. A card's header counts the patch's major features,
--  additional features and bug fixes; open, it shows the three tiers: hero
--  cards (2/row), small clickable listings, fix lines. Content:
--  EllesmereUI._WHATSNEW_PATCHES (newest first). Entry `nav` deep-links via
--  NavigateToElementSettings (opens page, pulses control); no `nav` = static
--  non-clickable card. File-scope fn so it adds no locals/upvalues to the
--  deferred options closure. whatsNewOpen: the open cards by version, for the
--  session (the newest starts open).
-------------------------------------------------------------------------------
local whatsNewOpen = {}
local NOTES_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\notes-off.png"
-- The EUI Legends sidebar module (LEGENDS_KEY in EUI__General_Options.lua).
local LEGENDS_KEY = "_EUILegends"
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
    -- (changes that apply on WoW Forever only), or the game patch in violet on
    -- entries that apply from one retail patch on (`patch = "12.1.5"`), so the
    -- note text itself never has to say where it applies. Sorting stays by
    -- module, so a module's lines sit together whatever their tag.
    local FOREVER_TAG = "|cffdca77f" .. EllesmereUI.L("WoW Forever") .. "|r - "
    local function PrefixOf(e)
        local tag = (e.forever and FOREVER_TAG) or (e.patch and ("|cffa88bff" .. e.patch .. "|r - ")) or ""
        return tag .. ((e.module and EllesmereUI.L(e.module) .. ": ") or "")
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

    -- An entry's nav target: its nav while the nav's module is registered, else nil.
    -- A module that is off (or not on this client) has no page to open, and the
    -- nav's preSelect may call that module's own setters; such a card renders static.
    local function NavTarget(nav)
        if nav and nav.module and EllesmereUI:GetModuleTitle(nav.module) then return nav end
    end

    -- Deep-link to a setting (opens the page; highlights the control if mapped).
    local function GoTo(nav)
        nav = NavTarget(nav)
        if nav then
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
        if entry.onClick or NavTarget(entry.nav) then
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

        if entry.onClick or NavTarget(entry.nav) then
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
    local function MakeListing(x, cy, w, entry)
        local ROW_H = 48
        local row = CreateFrame("Button", nil, parent)
        PP.Size(row, w, ROW_H)
        PP.Point(row, "TOPLEFT", parent, "TOPLEFT", x, cy)
        row:SetFrameLevel(parent:GetFrameLevel() + 2)

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
        if entry.onClick or NavTarget(entry.nav) then
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

    -- Tier 3: a plain bug-fix line (bullet + wrapping text, not clickable),
    -- drawn on `host` (above the patch card's fill) from x to the card's inset.
    local function MakeFixLine(host, x, rightInset, cy, text)
        local dot = MakeFont(host, 12, nil, EG.r, EG.g, EG.b, 0.55)
        PP.Point(dot, "TOPLEFT", parent, "TOPLEFT", x + 2, cy - 1)
        dot:SetText("\226\128\162")  -- bullet glyph (ASCII-safe UTF-8 escape)
        local fs = MakeFont(host, 12, nil, 1, 1, 1, 0.5)
        PP.Point(fs, "TOPLEFT", parent, "TOPLEFT", x + 18, cy)
        PP.Point(fs, "RIGHT", parent, "RIGHT", -rightInset, 0)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
        fs:SetText(text or "")
        local th = fs:GetStringHeight() or 14
        return math.max(22, math.ceil(th) + 8)
    end

    -- A patch's closing thank-you (patch.thanks): its "contributors" word is a
    -- link in the accent colour that opens the EUI Legends page with the team
    -- wall scrolled to the contributor groups and outlined.
    local function MakeThanksLine(host, x, cy)
        local tmpl = EllesmereUI.L("Thank you to all of our %s!") or ""
        local pre, post = tmpl:match("^(.-)%%s(.*)$")
        if not pre then pre, post = "Thank you to all of our ", "!" end
        local preFs = MakeFont(host, 12, nil, 1, 1, 1, 0.5)
        PP.Point(preFs, "TOPLEFT", parent, "TOPLEFT", x, cy)
        preFs:SetText(pre)
        local link = CreateFrame("Button", nil, host)
        local linkFs = MakeFont(link, 12, nil, EG.r, EG.g, EG.b, 0.9)
        linkFs:SetPoint("LEFT", link, "LEFT", 0, 0)
        linkFs:SetText(EllesmereUI.L("contributors"))
        link:SetSize(math.ceil(linkFs:GetStringWidth() or 60) + 1, 18)
        link:SetPoint("LEFT", preFs, "RIGHT", 0, 0)
        local postFs = MakeFont(host, 12, nil, 1, 1, 1, 0.5)
        postFs:SetPoint("LEFT", link, "RIGHT", 0, 0)
        postFs:SetText(post)
        link:SetScript("OnEnter", function(self)
            linkFs:SetAlpha(1)
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("View EUI Legends"))
        end)
        link:SetScript("OnLeave", function()
            linkFs:SetAlpha(0.9)
            EllesmereUI.HideWidgetTooltip()
        end)
        link:SetScript("OnClick", function()
            EllesmereUI.HideWidgetTooltip()
            EllesmereUI:SelectModule(LEGENDS_KEY)
            -- After the page is shown, as the deep links do (NavigateToElementSettings).
            C_Timer.After(0.05, function()
                if EllesmereUI._LegendsFocusContributors then EllesmereUI._LegendsFocusContributors() end
            end)
        end)
        return 22
    end

    -- A tier's title (already localized) inside a patch card: the section label
    -- colour and a faint rule under it, inset with the card's content.
    local function TierHeader(host, x, cy, w, text)
        local ts = EllesmereUI.TEXT_SECTION
        local label = MakeFont(host, 12, nil, ts.r, ts.g, ts.b, ts.a)
        PP.Point(label, "TOPLEFT", parent, "TOPLEFT", x, cy - 16)
        label:SetText(text)
        local rule = host:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.07)
        PP.Size(rule, w, 1)
        PP.Point(rule, "TOPLEFT", parent, "TOPLEFT", x, cy - 34)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(rule) end
        return 40
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

    -- A patch card's content sits inset from the card's edges.
    local INSET = 16
    local innerX, innerW = PAD + INSET, totalW - INSET * 2

    -- One patch's tiers inside its open card, from cy down; returns the new cy.
    -- Text goes on a holder above the card's fill (frames already sit above it).
    local function BuildPatchContent(patch, cy)
        -- A "mini" patch is bugfix-only: just a `fixes` tier.
        local isMini = patch.mini
        local host = CreateFrame("Frame", nil, parent)
        host:SetAllPoints(parent)
        host:SetFrameLevel(parent:GetFrameLevel() + 2)
        cy = cy - 6

        -- Tier 1: hero cards, two per row, AUTHORED order (not module-sorted like features/fixes) -- reorder entries in _WHATSNEW_PATCHES to reorder cards.
        local heroes = patch.heroes or {}
        if #heroes > 0 then
            local cardW = math.floor((innerW - CARD_GAP) / 2)
            local CARD_H = 96
            -- Column state: heroes flow 2/row in authored order; a `banner` hero takes a full row, breaking then resuming the flow.
            local col = 0
            for _, hero in ipairs(heroes) do
                if hero.videoBanner then
                    if col == 1 then cy = cy - CARD_H - CARD_GAP; col = 0 end
                    local bh = MakeVideoBannerCard(innerX, cy, innerW, hero)
                    cy = cy - bh - CARD_GAP
                elseif hero.banner then
                    if col == 1 then cy = cy - CARD_H - CARD_GAP; col = 0 end
                    local bh = MakeBannerCard(innerX, cy, innerW, hero)
                    cy = cy - bh - CARD_GAP
                else
                    local cx = innerX + col * (cardW + CARD_GAP)
                    MakeHeroCard(cx, cy, cardW, CARD_H, hero)
                    col = col + 1
                    if col == 2 then cy = cy - CARD_H - CARD_GAP; col = 0 end
                end
            end
            if col == 1 then cy = cy - CARD_H - CARD_GAP end
            cy = cy + CARD_GAP - 4
        end

        -- Tier 2: small listings.
        local feats = SortByModule(patch.features or {})
        if #feats > 0 then
            cy = cy - TierHeader(host, innerX, cy, innerW, EllesmereUI.L("ADDITIONAL FEATURES"))
            cy = cy - 5  -- extra spacing below the divider
            for _, f in ipairs(feats) do
                local rh = MakeListing(innerX, cy, innerW, f); cy = cy - rh
            end
            cy = cy - 6
        end

        -- Tier 3: bug-fix lines. Full patches get a "BUG FIXES" header; a fixes-only mini patch drops it (the whole block is fixes), but a mini that also lists features keeps it so the fixes do not run on under them.
        local fixes = SortByModule(patch.fixes or {})
        if #fixes > 0 then
            if not isMini or #feats > 0 then
                cy = cy - TierHeader(host, innerX, cy, innerW, EllesmereUI.L("BUG FIXES"))
                cy = cy - 10  -- extra spacing below the divider
            end
            for _, fx in ipairs(fixes) do
                local fh = MakeFixLine(host, innerX, PAD + INSET, cy, PrefixOf(fx) .. (EllesmereUI.L(fx.text) or "")); cy = cy - fh
            end
        end
        if patch.thanks then
            cy = cy - 8
            cy = cy - MakeThanksLine(host, innerX, cy)
        end
        return cy - 4
    end

    -- One card per patch, newest first: the newest starts open. Show only the
    -- newest MAX_PATCHES entries; older ones may stay in the data table unshown.
    local MAX_PATCHES = 10
    local shown = math.min(#patches, MAX_PATCHES)
    local newestKey = patches[1].version or 1
    if whatsNewOpen[newestKey] == nil then whatsNewOpen[newestKey] = true end
    for pi = 1, shown do
        local patch = patches[pi]
        -- Header counts: hero cards (a launch-video banner is no feature), listings, fix lines.
        local heroN = 0
        for _, hero in ipairs(patch.heroes or {}) do
            if not hero.videoBanner then heroN = heroN + 1 end
        end
        local featN, fixN = #(patch.features or {}), #(patch.fixes or {})
        local parts = {}
        if patch.mini then parts[#parts + 1] = EllesmereUI.L("Mini Patch") end
        if heroN > 0 then parts[#parts + 1] = EllesmereUI.L("Major Features") .. ": " .. heroN end
        if featN > 0 then parts[#parts + 1] = EllesmereUI.L("Additional Features") .. ": " .. featN end
        if fixN > 0 then parts[#parts + 1] = EllesmereUI.L("Bug Fixes") .. ": " .. fixN end
        local tile = { key = patch.version or pi, display = "EllesmereUI " .. (patch.version or ""),
            desc = table.concat(parts, "    "),
            buildContent = function(_, cy) return BuildPatchContent(patch, cy) end }
        local newest = pi == 1
        y = EllesmereUI.BuildModuleCard(parent, y, W, tile, {
            enabled = true, expanded = whatsNewOpen, descW = 560, noSearch = true,
            glyph = function(hdr)
                local icon = hdr:CreateTexture(nil, "ARTWORK")
                PP.Size(icon, 28, 20)
                PP.Point(icon, "LEFT", hdr, "LEFT", 14, 0)
                icon:SetTexture(NOTES_ICON)
                if PP.DisablePixelSnap then PP.DisablePixelSnap(icon) end
                if newest then
                    icon:SetVertexColor(EG.r, EG.g, EG.b, 0.9)
                else
                    icon:SetVertexColor(1, 1, 1, 0.45)
                end
            end })
        -- "Latest" beside the newest card's title (its description hangs off the title).
        if newest then
            local _, title = tile._descFS:GetPoint(1)
            if title then
                local tag = MakeFont(tile._hdr, 11, nil, EG.r, EG.g, EG.b, 0.9)
                PP.Point(tag, "LEFT", title, "RIGHT", 10, 0)
                tag:SetText(EllesmereUI.L("Latest"))
            end
        end
    end

    return math.abs(y) + 20
end

-- The EUI Legends page: a celebration of the donors and team. Free-form
-- chrome (no settings widgets): the thank-you line, the Seasonal Legend and
-- the All-Time Legend in two open spotlight columns (each with its #2 and #3
-- beneath), then the donor and team walls.
-- Built once per session and kept: the panel drops its cached pages on
-- profile switches, resets and some settings changes and then asks for the
-- page again, and that call moves the kept root into the new wrapper
-- instead of building a copy (WoW never frees the frames of an old one).
local legendsRoot, legendsY0, legendsSpan
function EllesmereUI._BuildLegendsPage(pageName, parent, yOffset)
    -- Nothing here is searchable, so the search index pass builds none of it.
    if EllesmereUI._prebuilding then return 0 end
    parent._showRowDivider = nil
    if legendsRoot then
        -- Hidden across the move, so the Show below always replays OnShow
        -- (the animation driver) once the new wrapper is on screen.
        local dy = yOffset - legendsY0
        legendsRoot:Hide()
        legendsRoot:SetParent(parent)
        legendsRoot:ClearAllPoints()
        legendsRoot:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, dy)
        legendsRoot:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, dy)
        legendsRoot:Show()
        return math.abs(yOffset - legendsSpan)
    end
    local PP  = EllesmereUI.PanelPP
    local EG  = EllesmereUI.ELLESMERE_GREEN
    local PAD = EllesmereUI.CONTENT_PAD
    local L   = EllesmereUI.L
    local MakeFont   = EllesmereUI.MakeFont
    local MakeBorder = EllesmereUI.MakeBorder

    local data   = EllesmereUI._LEGENDS or {}
    local y      = yOffset - 14
    local totalW = parent:GetWidth() - PAD * 2
    local CARD_GAP = 14
    local colW   = (totalW - CARD_GAP) / 2
    local SEASONS = EllesmereUI._LEGENDS_SEASONS or {}
    local season  = SEASONS[data.season or ""]
    local lead    = season and season.colors[1]

    -- Every piece of the page hangs on this root, which later builds move.
    local root = CreateFrame("Frame", nil, parent)
    root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    root:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    -- Rank metals: gold / silver / bronze.
    local METALS = {
        { r = 1.00, g = 0.80, b = 0.28 },
        { r = 0.74, g = 0.78, b = 0.84 },
        { r = 0.83, g = 0.54, b = 0.28 },
    }
    local DIM   = EllesmereUI.COLOR_CODES.DIM

    -- The page's animations: played while it shows, stopped when it hides.
    local groups = {}

    -- A band brightest along its centre line and fading out toward both
    -- ends: two halves, each a horizontal gradient over a white base (the
    -- gradient's vertex colours multiply it). The caller anchors the halves.
    local function CenterBand(host, layer, w, h, c, a)
        local edge, mid = CreateColor(c.r, c.g, c.b, 0), CreateColor(c.r, c.g, c.b, a)
        local left = host:CreateTexture(nil, layer)
        left:SetColorTexture(1, 1, 1, 1)
        left:SetGradient("HORIZONTAL", edge, mid)
        local right = host:CreateTexture(nil, layer)
        right:SetColorTexture(1, 1, 1, 1)
        right:SetGradient("HORIZONTAL", mid, edge)
        PP.Size(left, w / 2, h)
        PP.Size(right, w / 2, h)
        PP.DisablePixelSnap(left)
        PP.DisablePixelSnap(right)
        return left, right
    end

    -- Small tumbling squares drifting through a column's outer thirds:
    -- leaves in fall, snow in winter, petals in spring and rising sparks in
    -- summer for the Seasonal Legend, rising gold motes for the All-Time
    -- Legend. x: 0..1 across the lane; y: start depth into the band; s/d: 0..1
    -- picks within the size and duration ranges; w: idle seconds before each
    -- pass (also staggers the first pass).
    local SLOTS = {
        { x = 0.18, y = 0,  s = 0.6, d = 0.2, w = 0.0 },
        { x = 0.58, y = 16, s = 0.2, d = 0.7, w = 2.6 },
        { x = 0.86, y = 6,  s = 0.9, d = 0.4, w = 5.2 },
        { x = 0.38, y = 32, s = 0.4, d = 0.9, w = 1.3 },
        { x = 0.72, y = 24, s = 0.7, d = 0.1, w = 6.4 },
        { x = 0.06, y = 44, s = 0.3, d = 0.5, w = 3.9 },
    }
    local GOLD_MOTES = { dir = 1, size = { 2, 4 }, dur = { 9, 13 }, spin = 90, alpha = 0.6,
        colors = { { 1.00, 0.84, 0.36 }, { 1.00, 0.93, 0.62 }, { 0.92, 0.70, 0.26 } } }
    local function Particles(host, w, h, fx, perSide)
        local laneW = w * 0.3 - 20
        local nColors = #fx.colors
        local idx = 0
        for side = 1, 2 do
            for i = 1, perSide do
                idx = idx + 1
                local sl = SLOTS[i]
                local xf = (side == 1) and sl.x or (1 - sl.x)
                local df = (side == 1) and sl.d or (1 - sl.d)
                local size = fx.size[1] + (fx.size[2] - fx.size[1]) * sl.s
                local dur  = fx.dur[1] + (fx.dur[2] - fx.dur[1]) * df
                local wait = sl.w + (side == 2 and 1.7 or 0)
                local travel = math.max(40, h - sl.y - 10)
                local x0 = (side == 1) and (10 + xf * laneW) or (w - 10 - laneW + xf * laneW)
                local c = fx.colors[(idx - 1) % nColors + 1]

                local p = host:CreateTexture(nil, "ARTWORK")
                p:SetColorTexture(c[1], c[2], c[3], 1)
                PP.Size(p, size, size)
                if fx.dir < 0 then
                    PP.Point(p, "TOP", host, "TOPLEFT", x0, -sl.y)
                else
                    PP.Point(p, "BOTTOM", host, "BOTTOMLEFT", x0, sl.y)
                end
                p:SetAlpha(0)

                local ag = p:CreateAnimationGroup()
                ag:SetLooping("REPEAT")
                local sway = (idx % 2 == 0) and 10 or -10
                local drift = ag:CreateAnimation("Translation")
                drift:SetOffset(sway * 0.6, fx.dir * travel)
                drift:SetDuration(dur); drift:SetStartDelay(wait); drift:SetSmoothing("NONE")
                local swayOut = ag:CreateAnimation("Translation")
                swayOut:SetOffset(sway, 0)
                swayOut:SetDuration(dur / 2); swayOut:SetStartDelay(wait); swayOut:SetSmoothing("IN_OUT")
                local swayBack = ag:CreateAnimation("Translation")
                swayBack:SetOffset(-sway, 0)
                swayBack:SetDuration(dur / 2); swayBack:SetStartDelay(wait + dur / 2); swayBack:SetSmoothing("IN_OUT")
                local spin = ag:CreateAnimation("Rotation")
                spin:SetDegrees((idx % 3 == 0) and -fx.spin or fx.spin)
                spin:SetDuration(dur); spin:SetStartDelay(wait)
                -- Back-to-back alpha steps (in, hold, out) so one is always
                -- driving the alpha for the whole pass; idle waits sit at the
                -- texture's own alpha of 0.
                local fadeIn = ag:CreateAnimation("Alpha")
                fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(fx.alpha)
                fadeIn:SetDuration(dur * 0.2); fadeIn:SetStartDelay(wait)
                local hold = ag:CreateAnimation("Alpha")
                hold:SetFromAlpha(fx.alpha); hold:SetToAlpha(fx.alpha)
                hold:SetDuration(dur * 0.45); hold:SetStartDelay(wait + dur * 0.2)
                local fadeOut = ag:CreateAnimation("Alpha")
                fadeOut:SetFromAlpha(fx.alpha); fadeOut:SetToAlpha(0)
                fadeOut:SetDuration(dur * 0.35); fadeOut:SetStartDelay(wait + dur * 0.65)
                groups[#groups + 1] = ag
            end
        end
    end

    -- Slow breathing: the region's alpha dips and comes back. Used on frames
    -- only: on a gradient texture an alpha animation drew it as a plain white
    -- block, so tinted art breathes through the frame that holds it.
    local function Breathe(region)
        local ag = region:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local dim = ag:CreateAnimation("Alpha")
        dim:SetFromAlpha(1); dim:SetToAlpha(0.5)
        dim:SetDuration(2.4); dim:SetSmoothing("IN_OUT"); dim:SetOrder(1)
        local back = ag:CreateAnimation("Alpha")
        back:SetFromAlpha(0.5); back:SetToAlpha(1)
        back:SetDuration(2.4); back:SetSmoothing("IN_OUT"); back:SetOrder(2)
        groups[#groups + 1] = ag
    end

    ---------------------------------------------------------------------------
    --  The thank-you line.
    ---------------------------------------------------------------------------
    local thanks = MakeFont(root, 16, nil, 1, 1, 1, 0.75)
    thanks:SetWidth(760)
    thanks:SetJustifyH("CENTER")
    thanks:SetWordWrap(true)
    PP.Point(thanks, "TOP", root, "TOP", 0, y)
    thanks:SetText(L("Thank you to all who support EllesmereUI and its incredible support team"))
    y = y - 26

    -- The invitation under it: its "Ellesmere's Twitch stream" is a link that
    -- opens the footer Twitch icon's copy box, centred as one line.
    local invite = EllesmereUI.L("Want to join the Legends? Check the leaderboard and donate through %s!") or ""
    local pre, post = invite:match("^(.-)%%s(.*)$")
    if not pre then pre, post = "Want to join the Legends? Check the leaderboard and donate through ", "!" end
    local preFs = MakeFont(root, 14, nil, 1, 1, 1, 0.5)
    preFs:SetText(pre)
    local link = CreateFrame("Button", nil, root)
    local linkFs = MakeFont(link, 14, nil, EG.r, EG.g, EG.b, 0.9)
    linkFs:SetPoint("LEFT", link, "LEFT", 0, 0)
    linkFs:SetText(EllesmereUI.L("Ellesmere's Twitch stream"))
    link:SetSize(math.ceil(linkFs:GetStringWidth() or 120) + 1, 18)
    local postFs = MakeFont(root, 14, nil, 1, 1, 1, 0.5)
    postFs:SetText(post)
    local inviteW = (preFs:GetStringWidth() or 0) + link:GetWidth() + (postFs:GetStringWidth() or 0)
    PP.Point(preFs, "TOPLEFT", root, "TOP", -math.floor(inviteW / 2 + 0.5), y)
    link:SetPoint("LEFT", preFs, "RIGHT", 0, 0)
    postFs:SetPoint("LEFT", link, "RIGHT", 0, 0)
    link:SetScript("OnEnter", function() linkFs:SetAlpha(1) end)
    link:SetScript("OnLeave", function() linkFs:SetAlpha(0.9) end)
    link:SetScript("OnClick", function(self)
        EllesmereUI.ShowLinkPopup(EllesmereUI.TWITCH_URL, self)
    end)
    y = y - 34

    ---------------------------------------------------------------------------
    --  Spotlights: the Seasonal Legend (left) and the All-Time Legend (right),
    --  open on the page over the walls' two columns. Each stacks the Legends
    --  crest in a breathing aura of its colour, the eyebrow between short
    --  rules, the name large on a fading underline, and the #2 and #3.
    --  Particles drift through each column's outer thirds. A rank nobody holds
    --  yet shows a dim placeholder.
    ---------------------------------------------------------------------------
    local BAND_H  = 160
    -- The names' centre line, which the split between the columns also meets.
    local NAME_Y  = 90
    local bandTop = y
    local CREST_ART  = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\eui-legends-off.png"
    local CREST_GLOW = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\eui-legends-on.png"
    -- Art and text sit on one frame above both particle layers.
    local band = CreateFrame("Frame", nil, root)
    band:SetFrameLevel(root:GetFrameLevel() + 3)
    PP.Size(band, totalW, BAND_H)
    PP.Point(band, "TOPLEFT", root, "TOPLEFT", PAD, bandTop)
    local function Spotlight(x, c, eyebrowText, ranked, fx, perSide)
        -- The column's centre on the band.
        local cx = x - PAD + colW / 2

        -- Particles on a clipped layer of the column's own, under the band.
        local clip = CreateFrame("Frame", nil, root)
        clip:SetFrameLevel(root:GetFrameLevel() + 1)
        PP.Size(clip, colW, BAND_H)
        PP.Point(clip, "TOPLEFT", root, "TOPLEFT", x, bandTop)
        clip:SetClipsChildren(true)
        local motion = CreateFrame("Frame", nil, clip)
        motion:SetAllPoints(clip)
        Particles(motion, colW, BAND_H, fx, perSide)

        -- The crest at its own size: the glow art tinted in the column's
        -- colour on a frame that breathes, the white crest on a frame above.
        local aura = CreateFrame("Frame", nil, band)
        aura:SetFrameLevel(band:GetFrameLevel() + 1)
        PP.Size(aura, 52, 37)
        PP.Point(aura, "TOPLEFT", band, "TOPLEFT", math.floor(cx - 26 + 0.5), 0)
        local glow = aura:CreateTexture(nil, "ARTWORK")
        glow:SetAllPoints()
        glow:SetTexture(CREST_GLOW)
        glow:SetDesaturated(true)
        glow:SetVertexColor(c.r, c.g, c.b, 1)
        Breathe(aura)
        local crestHolder = CreateFrame("Frame", nil, band)
        crestHolder:SetFrameLevel(band:GetFrameLevel() + 2)
        crestHolder:SetAllPoints(aura)
        local crest = crestHolder:CreateTexture(nil, "ARTWORK")
        crest:SetAllPoints()
        crest:SetTexture(CREST_ART)

        -- Eyebrow between short rules that warm toward it.
        local eyebrow = MakeFont(band, 13, nil, c.r, c.g, c.b, 0.95)
        PP.Point(eyebrow, "TOP", band, "TOPLEFT", cx, -46)
        eyebrow:SetText(eyebrowText)
        local near, far = CreateColor(c.r, c.g, c.b, 0.55), CreateColor(c.r, c.g, c.b, 0)
        for side = -1, 1, 2 do
            local rule = band:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(1, 1, 1, 1)
            if side < 0 then
                rule:SetGradient("HORIZONTAL", far, near)
            else
                rule:SetGradient("HORIZONTAL", near, far)
            end
            PP.Size(rule, 44, 1)
            PP.Point(rule, side < 0 and "RIGHT" or "LEFT", eyebrow, side < 0 and "LEFT" or "RIGHT", side * 10, 0)
            PP.DisablePixelSnap(rule)
        end

        -- The name on a fading underline, its letters centred in the space
        -- between the eyebrow and the line (a name wider than the column ends
        -- in an ellipsis).
        local first = ranked[1]
        local open = not first or first == ""
        local name = MakeFont(band, 30, nil, 1, 1, 1, open and 0.3 or 1)
        PP.Point(name, "CENTER", band, "TOPLEFT", cx, -NAME_Y)
        name:SetWordWrap(false)
        name:SetText(open and L("Unclaimed") or first)
        local nameW = name:GetStringWidth() or 0
        if nameW > colW - 32 then
            name:SetWidth(colW - 32)
            nameW = colW - 32
        end
        local lineL, lineR = CenterBand(band, "ARTWORK", math.min(colW - 40, nameW + 140), 1, c, 0.6)
        PP.Point(lineL, "RIGHT", band, "TOPLEFT", cx, -122)
        PP.Point(lineR, "LEFT", band, "TOPLEFT", cx, -122)

        -- The #2 and #3, tagged in their metals.
        local function Runner(rank)
            local m, who = METALS[rank], ranked[rank]
            local tag = EllesmereUI.HexColor(m.r, m.g, m.b) .. "#" .. rank .. "|r  "
            if not who or who == "" then return tag .. DIM .. L("Unclaimed") .. "|r" end
            return tag .. who
        end
        local runners = MakeFont(band, 13, nil, 1, 1, 1, 0.85)
        PP.Point(runners, "TOP", band, "TOPLEFT", cx, -134)
        runners:SetWordWrap(false)
        runners:SetText(Runner(2) .. "      " .. DIM .. "\226\128\162|r      " .. Runner(3))
        if (runners:GetStringWidth() or 0) > colW - 32 then runners:SetWidth(colW - 32) end
    end

    Spotlight(PAD, lead and { r = lead[1], g = lead[2], b = lead[3] } or EG,
        L("SEASONAL LEGEND"), data.topSeasonal or {}, season or GOLD_MOTES, 6)
    Spotlight(PAD + colW + CARD_GAP, METALS[1],
        L("ALL-TIME LEGEND"), data.donors or {}, GOLD_MOTES, 4)

    -- The split between the columns: a line fading toward both ends, an
    -- accent diamond at its middle, level with the names.
    local midX, DIV_H = colW + CARD_GAP / 2, 130
    local clear, lit = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.12)
    local upper = band:CreateTexture(nil, "ARTWORK")
    upper:SetColorTexture(1, 1, 1, 1)
    upper:SetGradient("VERTICAL", lit, clear)
    PP.Size(upper, 1, DIV_H / 2)
    PP.Point(upper, "BOTTOM", band, "TOPLEFT", midX, -NAME_Y)
    PP.DisablePixelSnap(upper)
    local lower = band:CreateTexture(nil, "ARTWORK")
    lower:SetColorTexture(1, 1, 1, 1)
    lower:SetGradient("VERTICAL", clear, lit)
    PP.Size(lower, 1, DIV_H / 2)
    PP.Point(lower, "TOP", band, "TOPLEFT", midX, -NAME_Y)
    PP.DisablePixelSnap(lower)
    local gem = band:CreateTexture(nil, "ARTWORK")
    gem:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
    PP.Size(gem, 6, 6)
    PP.Point(gem, "CENTER", band, "TOPLEFT", midX, -NAME_Y)
    local gemMask = band:CreateMaskTexture()
    gemMask:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\portraits\\diamond_mask.tga",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    gemMask:SetAllPoints(gem)
    gem:AddMaskTexture(gemMask)
    y = y - BAND_H - 16

    -- One driver plays every animation while the page shows and stops them
    -- (back to their idle frames) when it hides.
    local driver = CreateFrame("Frame", nil, root)
    driver:SetAllPoints(root)
    driver:SetScript("OnShow", function()
        for i = 1, #groups do groups[i]:Play() end
    end)
    driver:SetScript("OnHide", function()
        for i = 1, #groups do groups[i]:Stop() end
    end)
    if driver:IsVisible() then
        for i = 1, #groups do groups[i]:Play() end
    end

    ---------------------------------------------------------------------------
    --  The walls: all-time donors (left) and the team (right). FIXED height from
    --  the page budget; the name lists scroll INSIDE each card with smooth
    --  wheel scrolling and the thin custom thumb (the sidebar-nav pattern),
    --  so the page itself never scrolls.
    ---------------------------------------------------------------------------
    -- FIXED wall height (the Export Profile addon-list pattern: a constant
    -- clip height, the list scrolls inside it) so the page itself always
    -- fits the panel and never scrolls.
    local wallH = 344

    local WALL_STEP, WALL_SPEED = 48, 12
    local function MakeWall(x, headerText, subText)
        local card = CreateFrame("Frame", nil, root)
        card:SetFrameLevel(root:GetFrameLevel() + 2)
        PP.Size(card, colW, wallH)
        PP.Point(card, "TOPLEFT", root, "TOPLEFT", x, y)
        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
        MakeBorder(card, 1, 1, 1, 0.12, PP)
        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(EG.r, EG.g, EG.b, 0.6)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        PP.DisablePixelSnap(accent)

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
        PP.DisablePixelSnap(div)

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

        -- Glide the list to an offset (clamped by the smoother), snapped to the
        -- pixel grid like a wheel target: the smoother's steps land on that
        -- grid, so an offset between two of its rows would be stepped past
        -- from either side and never settle.
        local function ScrollTo(offset)
            local scale = sf:GetEffectiveScale()
            target = math.floor(offset * scale + 0.5) / scale
            if not smoothing then
                smoothing = true
                smoother:Show()
            end
        end

        return child, function(contentH)
            child:SetHeight(math.max(contentH, 1))
            UpdateThumb()
        end, card, ScrollTo
    end

    -- Left wall: every donor, numbered in all-time order on alternating row
    -- strips (ranks 1-3 take the rank metals on number and name, the rest
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
    local staffList, staffFin, staffCard, staffScrollTo = MakeWall(PAD + colW + CARD_GAP, L("EUI STAFF"))
    local STAFF_ROW_H = 22
    local sy = 0
    local contribY
    for gi = 1, #staff do
        local grp = staff[gi]
        if gi > 1 then sy = sy - 10 end
        if not contribY and grp.group and grp.group:find("Contributors", 1, true) then contribY = -sy end
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

    -- The patch notes' thank-you link lands here: glide the team wall to its
    -- first contributor group and outline the card the way a deep link
    -- outlines a setting (one outline, replayed on a repeat click).
    local staffHL
    EllesmereUI._LegendsFocusContributors = function()
        if not staffCard:IsVisible() then return end
        if contribY then staffScrollTo(contribY) end
        if not (staffHL and staffHL:IsShown() and staffHL:GetParent() == staffCard) then
            staffHL = EllesmereUI.GetSearchHighlight()
        end
        EllesmereUI.PlaySearchHighlight(staffHL, staffCard)
    end

    y = y - wallH - 18

    local footer = MakeFont(root, 12, nil, 1, 1, 1, 0.35)
    PP.Point(footer, "TOP", root, "TOP", 0, y)
    footer:SetText(L("Thank you for making EllesmereUI possible."))
    y = y - 22

    root:SetHeight(math.abs(y))
    legendsRoot, legendsY0, legendsSpan = root, yOffset, yOffset - y
    return math.abs(y)
end
