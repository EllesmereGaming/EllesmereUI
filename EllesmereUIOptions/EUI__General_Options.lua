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

    -- Display title: "Module: Title" -- the module name is prepended to every entry.
    local function TitleOf(e)
        return ((e.module and EllesmereUI.L(e.module) .. ": ") or "") .. (EllesmereUI.L(e.title) or "")
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

        local accent = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accent:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(accent) end

        -- Flanking decorative bar-charts: dim white steps, green "now" bar, faint baseline.
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
                    bar:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
                else
                    bar:SetColorTexture(1, 1, 1, a)
                end
                PP.Size(bar, BAR_W, heights[i])
                PP.Point(bar, "BOTTOMLEFT", base, "TOPLEFT", (i - 1) * (BAR_W + BAR_GAP2), 1)
                if PP.DisablePixelSnap then PP.DisablePixelSnap(bar) end
            end
        end
        -- Left: cost falling to a low green bar. Right: fps rising to a tall one.
        MakeChart("LEFT",  36, { 34, 26, 19, 13, 8 },  { 0.28, 0.23, 0.18, 0.14, "green" })
        MakeChart("RIGHT", 36, { 8, 13, 19, 26, 34 },  { 0.14, 0.18, 0.23, 0.28, "green" })

        local eyebrow = MakeFont(card, 11, nil, EG.r, EG.g, EG.b, 0.9)
        PP.Point(eyebrow, "TOP", card, "TOP", 0, -18)
        eyebrow:SetJustifyH("CENTER"); eyebrow:SetWordWrap(false)
        eyebrow:SetText(EllesmereUI.L(entry.eyebrow or "SPECIAL UPDATE"))

        -- Banner titles stand alone (no "Module:" prefix), rendered LARGE like popup headlines.
        local titleFs = MakeFont(card, 24, nil, 1, 1, 1, 1)
        PP.Point(titleFs, "TOP", eyebrow, "BOTTOM", 0, -8)
        titleFs:SetJustifyH("CENTER"); titleFs:SetWordWrap(false)
        titleFs:SetText(EllesmereUI.L(entry.title) or "")

        local descFs = MakeFont(card, 13, nil, 1, 1, 1, 0.5)
        PP.Point(descFs, "TOP", titleFs, "BOTTOM", 0, -10)
        PP.Point(descFs, "LEFT", card, "LEFT", 110, 0)
        PP.Point(descFs, "RIGHT", card, "RIGHT", -110, 0)
        descFs:SetJustifyH("CENTER"); descFs:SetJustifyV("TOP"); descFs:SetWordWrap(true)
        descFs:SetText(EllesmereUI.L(entry.desc) or "")

        local dh = math.ceil(descFs:GetStringHeight() or 14)
        local bh = 18 + 11 + 8 + 24 + 10 + dh + 28
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
                local fh = MakeFixLine(y, ((fx.module and EllesmereUI.L(fx.module) .. ": ") or "") .. (EllesmereUI.L(fx.text) or "")); y = y - fh
            end
        end

        if pi < shown then
            local _, gap = W:Spacer(parent, y, 24); y = y - gap
        end
    end

    return math.abs(y) + 20
end

-------------------------------------------------------------------------------
--  EUI LEGENDS -- curated content. EDIT THESE TABLES to update the page:
--    monthLabel : label shown over the monthly podium
--    topMonthly : rank-ordered top three donors for that month (1st, 2nd, 3rd)
--    donors     : the all-donors wall, rendered in this order
--    staff      : grouped team sections ({ group, members } tables)
-------------------------------------------------------------------------------
EllesmereUI._LEGENDS = {
    monthLabel = "August 2026",
    topMonthly = { "Thias", "StickyMittens", "Xeno" },
    donors = {
        "Thias", "StickyMittens", "Xeno",
        "delasteve", "Toxik", "Lily", "Pelleas", "Kulia",
        "GamingGrammers", "Cartridgebros", "fizzle_crunk", "Tzahal",
        "Ani", "Venalis", "Lurn", "Natasi", "Khardi", "Quiim",
        "Capa", "e_luvin", "ccpoppin1", "Arjax",
    },
    staff = {
        { group = "Support Leads", members = {
            "Burne", "Mudd", "Kulia", "Dookie", "Lily",
        } },
        { group = "Bug Hunters", members = {
            "Glyalith", "Derek", "Juju", "Kneeul", "Kiri",
            "Stoley", "Stormspren", "Xanax", "DNL",
        } },
        { group = "Support Team", members = {
            "Mantis", "Kned", "Zylann", "Svart", "Meza",
            "Tzahal", "Spaze", "Terrible", "Mohkan", "Groukh",
            "Freschi", "Twilight", "Bierbauch",
        } },
    },
}

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

    -- Flourish: two faint lines meeting a green diamond dot.
    local fy = y - 76
    local dot = parent:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
    PP.Size(dot, 5, 5)
    PP.Point(dot, "TOP", parent, "TOP", 0, fy)
    for side = -1, 1, 2 do
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.12)
        PP.Size(line, 150, 1)
        PP.Point(line, side < 0 and "RIGHT" or "LEFT", dot, side < 0 and "LEFT" or "RIGHT", side * 10, 0)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(line) end
    end
    y = fy - 28

    ---------------------------------------------------------------------------
    --  Monthly podium: #1 center and elevated, #2 left, #3 right.
    ---------------------------------------------------------------------------
    local podiumLabel = MakeFont(parent, 13, nil, EG.r, EG.g, EG.b, 0.9)
    PP.Point(podiumLabel, "TOP", parent, "TOP", 0, y)
    podiumLabel:SetText(L("Monthly Top Donors") .. "  -  " .. (data.monthLabel or ""))
    y = y - 30

    local top3 = data.topMonthly or {}
    local CENTER_W, CENTER_H = 200, 78
    local SIDE_W, SIDE_H     = 172, 66
    -- Sides drop exactly the height difference so all three BOTTOMS align;
    -- #1 still reads elevated purely by being taller.
    local SIDE_DROP          = CENTER_H - SIDE_H
    -- rank -> horizontal slot: #2 left, #1 center, #3 right.
    local SLOT_DX = { 0, -(CENTER_W / 2 + CARD_GAP + SIDE_W / 2), (CENTER_W / 2 + CARD_GAP + SIDE_W / 2) }
    for rank = 1, 3 do
        local name = top3[rank]
        if name and name ~= "" then
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

            local nameFs = MakeFont(card, isFirst and 17 or 15, nil, 1, 1, 1, isFirst and 1 or 0.92)
            PP.Point(nameFs, "TOP", rankFs, "BOTTOM", 0, isFirst and -10 or -8)
            PP.Point(nameFs, "LEFT", card, "LEFT", 10, 0)
            PP.Point(nameFs, "RIGHT", card, "RIGHT", -10, 0)
            nameFs:SetJustifyH("CENTER")
            nameFs:SetWordWrap(false)
            nameFs:SetText(name)
        end
    end
    y = y - (SIDE_DROP + math.max(CENTER_H, SIDE_H + SIDE_DROP)) - 26

    ---------------------------------------------------------------------------
    --  The walls: all donors (left) and the team (right). FIXED height from
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
    local function MakeWall(x, headerText)
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

    -- Left wall: every donor, dot-bulleted on alternating row strips.
    local donors = data.donors or {}
    local donorList, donorFin = MakeWall(PAD, L("ALL DONORS"))
    local DONOR_ROW_H = 24
    for i = 1, #donors do
        local rowF = CreateFrame("Frame", nil, donorList)
        rowF:SetSize(colW, DONOR_ROW_H)
        rowF:SetPoint("TOPLEFT", donorList, "TOPLEFT", 0, -(i - 1) * DONOR_ROW_H)
        local rbg = rowF:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.12 or 0.06)
        local nameFs = MakeFont(rowF, 14, nil, 1, 1, 1, 0.85)
        PP.Point(nameFs, "LEFT", rowF, "LEFT", 34, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetText(donors[i])
        local bdot = rowF:CreateTexture(nil, "OVERLAY")
        bdot:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        PP.Size(bdot, 4, 4)
        PP.Point(bdot, "RIGHT", nameFs, "LEFT", -10, 0)
    end
    donorFin(#donors * DONOR_ROW_H)

    -- Right wall: the team, grouped by role section (green group header,
    -- then plain member rows on alternating strips).
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
            PP.Point(nameFs, "LEFT", rowF, "LEFT", 16, 0)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetText(members[i])
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
    {
        version = "9.0.7",
        heroes = {
            {
                module = "Unit Frames",
                title  = "Debuff Filter Modes",
                desc   = "Target, Focus and Boss Debuff Filter is now a single choice: Show All, Only Tracked Auras, Own Only, Important Only, Important and Own, or the new Important or Own. Tracked Auras always show on top of the chosen filter; your current setup is carried over.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "BUFFS AND DEBUFFS", highlight = "Debuff Filter",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("target"); EllesmereUI._pendingUnitSelect = "target" end },
            },
            {
                module = "Raid Frames",
                title  = "Ping Markers",
                desc   = "When someone pings a group member, the ping mark now appears on their raid or party frame just like the default frames. Position, size and offset live under Indicators; it follows Blizzard's Show Pings on Raid Frames setting.",
                -- The row sits inside the Indicators less-common collapse; expand it for the session so the deep-link can reach the row.
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "INDICATORS", highlight = "Ping Marker",
                           preSelect = function()
                               local sess = EllesmereUI._lessCommonExpanded
                               if not sess then sess = {}; EllesmereUI._lessCommonExpanded = sess end
                               sess.rfIndicators = true
                           end },
            },
            {
                module = "Resource Bars",
                title  = "Arcane Soul Helper",
                desc   = "An opt-in countdown for Sunfury Arcane Mages that shows when Arcane Soul opens and how many Barrages fit inside it. Lives with the class bars under Class, Power and Health Bars.",
                -- Section is built for Mages only; other classes land on the page without a pulse.
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "ARCANE SOUL (SUNFURY)", highlight = "Arcane Soul Helper" },
            },
            {
                module = "General",
                title  = "Unified Visibility Controls",
                desc   = "Every module's Visibility and Visibility Options are now one Show/Hide checklist, with new Hide in Instances, Skyriding Mount, Hide with Target and Hide with Enemy Target conditions. Your existing choices carry over unchanged.",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY", highlight = "Visibility",
                           preSelect = function() if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end end },
            },
        },
        features = {
            {
                module = "DataBars",
                title  = "Crests Block",
                desc   = "The season's five Mistcrests in one readout with tier colors, optional icons, season progress and a full tooltip",
                -- Block settings only exist once the block is on a bar: page-only nav, same as the Combat Status block entry.
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "DataBars",
                title  = "Item Level Block",
                desc   = "Equipped or total item level with an optional prefix, decimals and an upgrade-track color band",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Targeted Spell Bars Icon Options",
                desc   = "The spell icon can sit on the right side of the bar, with an optional divider at the icon seam",
                nav    = { module = "EllesmereUIMythicTimer", page = "Targeted Spell Bars", section = "TARGETED SPELL BARS", highlight = "Show Icon" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Strict Split Compare",
                desc   = "A Split Compare cog option that compares boss splits only against runs at the same key level, so a new key level starts without a reference instead of using your dungeon best",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer", section = "BOSS OBJECTIVES", highlight = "Split Compare" },
            },
            {
                module = "Nameplates",
                title  = "Important Cast Glow Styles",
                desc   = "All six glow styles (Pixel, Action Button, Auto-Cast Shine, GCD, Modern WoW, Classic WoW) with a live preview",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CAST COLORS AND EFFECTS", highlight = "Important Cast Glow" },
            },
            {
                module = "QoL",
                title  = "Raid Tools Compact Band",
                desc   = "One resizable row with the eight raid markers, clear, Ready Check and pull timers, movable in Unlock Mode",
                nav    = { module = "EllesmereUIQoL", page = "Raid Tools", section = "GENERAL", highlight = "Show as" },
            },
        },
        fixes = {
            { module = "Action Bars & Cooldown Manager", text = "Gamepad keybinds now show the controller's button glyphs instead of raw names like PADDUP." },
            { module = "Action Bars", text = "Show All on Mouseover now only triggers when hovering a bar that is itself set to Mouseover, as its tooltip says." },
            { module = "Cooldown Manager", text = "Fixed the Cooldown Manager disappearing until a reload after leaving a battleground or arena." },
            { module = "Cooldown Manager", text = "Mirror Key Presses now flashes trinket, potion and healthstone icons when their action bar button is pressed." },
            { module = "Cooldown Manager", text = "A trinket added via the trinket slot preset no longer stays hidden on some logins until it is re-equipped." },
            { module = "Damage Meters", text = "Bar and icon spacing now show at the intended size on UI scales other than pixel-perfect, so a spacing of 1 no longer collapses to no gap." },
            { module = "DataBars", text = "The Currency block tooltip now shows season progress for capped currencies like crests instead of comparing your wallet total to the seasonal cap." },
            { module = "QoL", text = "Auto Open Containers' Exclude Warbound Containers now also holds back Warbound Until Equipped caches instead of opening them." },
            { module = "Quest Tracker", text = "Fixed an error during scenario objectives (e.g. Curse Surges) that could freeze the objective tracker until a reload." },
            { module = "Raid Frames", text = "Raid joins, leaves and group shuffles now repaint only the frames that changed instead of every frame several times, cutting the CPU spike while a raid forms." },
            { module = "Raid Frames", text = "A member who joined or was moved while dead no longer keeps showing DEAD after being resurrected." },
            { module = "Unit & Raid Frames", text = "Removed stray debug messages that appeared in chat when using the house-visit menu." },
            { module = "Unit Frames", text = "Target and Focus Tracked Auras entries gained the MINE tag boss frames already had, so a tracked debuff can be limited to your own casts." },
            { module = "Localization", text = "Korean, Traditional Chinese and Brazilian Portuguese gained the latest option strings (Targeted Spell Bars interrupt awareness, Raid Frames Shown on Modifier, the house-visit menu and Quickdraw marker entries)." },
        },
    },
    {
        version = "9.0.6",
        heroes = {
            {
                module = "Mythic+ Tools",
                title  = "Targeted Spell Bars Interrupt Awareness",
                desc   = "Kick-ready and uninterruptible cast colors on every bar, plus an optional Important Cast tint and glow. Also new and off by default: a fade when the caster is out of interrupt range, and raid target markers beside the spell name.",
                nav    = { module = "EllesmereUIMythicTimer", page = "Targeted Spell Bars", section = "INTERRUPT AND VISIBILITY", highlight = "Cast Colors" },
            },
        },
        features = {
            {
                module = "Mythic+ Tools",
                title  = "Targeted Spell Bars Where to Show",
                desc   = "Limit the bars to selected content types and combat states; nothing selected shows them everywhere",
                nav    = { module = "EllesmereUIMythicTimer", page = "Targeted Spell Bars", section = "TARGETED SPELL BARS", highlight = "Where to Show" },
            },
        },
        fixes = {
            { module = "AuraBuff Reminders", text = "Clicking a Paladin Rite reminder now casts the rite and applies it to your weapon in one click." },
            { module = "Blizz UI Enhanced", text = "Great Vault reward icons now show their item rarity border." },
            { module = "Cooldown Manager", text = "A Roll the Bones tracking bar now follows every re-roll instead of freezing on one outcome and disappearing." },
            { module = "DataBars", text = "The spec block no longer shows a talent loadout that failed to apply because combat interrupted the swap." },
            { module = "General", text = "Durability displays (Character Sheet, Chat sidebar, DataBars, repair warning) now update after using a repair item, not only after a vendor repair." },
            { module = "Raid Frames", text = "Fixed a niche blocked-action error at login when another addon refreshes the raid frames during combat." },
            { module = "Raid Frames", text = "Fixed a blocked-action error when a raid member moves onto a different frame during combat." },
            { module = "Unit & Raid Frames", text = "View Houses now works from the right-click menu of a group member who is in another zone (e.g. the host of a housewarming)." },
            { module = "Unit Frames", text = "The pet frame's class-colored name no longer shows the wrong color at login until the option is toggled." },
        },
    },
    {
        version = "9.0.5",
        mini = true,
        fixes = {
            { module = "Nameplates", text = "Friendly Name Size in Name Only mode now survives a reload." },
            { module = "Nameplates", text = "Raid markers on friendly player nameplates now update as soon as they are applied." },
            { module = "Resource Bars", text = "The Ebon Might bar no longer loses its countdown text for the rest of the session when its display overlay fails to build." },
            { module = "Damage Meters", text = "The unlock mode Element Options link now opens the right settings for the meter windows, Combat Timer and Icon History." },
            { module = "Blizz UI Enhanced", text = "The tooltip anchor's unlock mode Element Options link now opens the Tooltips settings." },
            { module = "Unit Frames", text = "Dynamic, Classic and Class Reactive health colors now follow health changes again instead of freezing." },
            { module = "Raid Frames", text = "Extra Frames no longer show a blank name after reconnecting mid-raid." },
            { module = "General", text = "The Macro Factory's Health / Recuperate macro now uses the 12.1 Concentrated Silvermoon Health Potions." },
            { module = "Unit & Raid Frames", text = "Avenging Wrath is now included in the offensive cooldowns buff preset." },
        },
    },
    {
        version = "9.0.2",
        heroes = {},
        features = {
            {
                -- Static card: the work is automatic, nothing to open.
                module = "General",
                title  = "Performance Patch Follow-Up",
                desc   = "Further CPU and memory reductions in combat, continuing the 12.1 Performance Patch: Cooldown Manager, Movement Alerts, Resource Bars, Raid Frames, Nameplates and Unit Frames all do less work per frame, and raids with many shields pace more smoothly",
            },
            {
                module = "Raid Frames",
                title  = "Shown on Modifier Tooltips",
                desc   = "New Shown on Modifier tooltip mode in the Debuff Manager: show debuff tooltips only while holding a chosen modifier key",
                nav    = { module = "EllesmereUIRaidFrames", page = "Debuff Manager", section = "DISPLAY", highlight = "Tooltips" },
            },
            {
                module = "Unit Frames",
                title  = "Boss Tracked Auras MINE Tag",
                desc   = "Boss Tracked Auras now show your own casts by default, with a per-spell MINE tag to allow any caster, matching nameplates",
                -- The tag lives inside the Tracked Auras popup behind the boss page's
                -- filter cog: land the page, then open the popup directly.
                onClick = function()
                    EllesmereUI:NavigateToElementSettings("EllesmereUIUnitFrames", "Boss Frames")
                    local uf = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
                    if uf and uf.UFOpt_ShowTrackedAuras then uf.UFOpt_ShowTrackedAuras("boss") end
                end,
            },
            {
                module = "Quality of Life",
                title  = "Target Distance Frame Strata",
                desc   = "Choose which frame strata the Target Distance text sits on",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "EXTRAS", highlight = "Target Distance Text" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Dragging a pet ability now reveals conditionally hidden and mouseover bars the same way a spell drag does." },
            { module = "AuraBuff Reminders", text = "Pet reminders now follow the class-specials Where to Show setting, so turning off Delves or any other zone hides them there too." },
            { module = "Bags", text = "Sorting no longer stutters or makes mouseover action bars flicker, and partial stacks merge in fewer passes." },
            { module = "Cooldown Manager", text = "The Shift Elements If No Bars Extra Y Offset and Additional Bar Offset sliders now work in screen pixels, so 1 means 1 pixel at any resolution or UI scale, and the unlock mover tooltip shows the same pixel values." },
            { module = "General", text = "The Macro Factory's Set Focus macro Ping Focus option now pings On My Way on non-English clients." },
            { module = "Nameplates", text = "The options preview now follows the Nameplates Module Outline override instead of always showing the global outline." },
            { module = "Quickdraw", text = "The Pings preset now sends the intended ping type on non-English clients." },
            { module = "Raid Frames", text = "Offline and dead members no longer flip back to their class color after a roster update or opening the options." },
            { module = "Raid Frames", text = "Dark Mode and custom health backgrounds no longer lose their color after joining a group or changing groups." },
            { module = "Raid Frames", text = "Single-target heals cast on a party member no longer show on the wrong frame after a roster change." },
            { module = "Resource Bars", text = "The Totem Bar now respects its Frame Strata setting instead of always sitting above other UI." },
            { module = "Resource Bars", text = "Hash lines set at the maximum value now sit flush with the bar edge instead of drawing past it." },
            { module = "Resource Bars", text = "Cast bar and GCD bar borders no longer vanish after the bar is re-anchored." },
            { module = "Unit Frames", text = "The power bar border no longer disappears until a reload after the bar passes through zero height." },
            { module = "Localization", text = "Traditional Chinese and Brazilian Portuguese gained the 9.0.0 option labels and tooltips (Assisted Highlight, Debuff Type Icon, Combat Status, combat-only circles, outline overrides, Moonkin)." },
        },
    },
    {
        version = "9.0.1",
        heroes = {
            {
                -- Full-width banner card (banner = true, see MakeBannerCard). Static: the speedup is automatic, nothing to open.
                banner  = true,
                eyebrow = "SUITE-WIDE OPTIMIZATION",
                title   = "The 12.1 Performance Patch",
                desc    = "CPU usage has been significantly reduced across the entire suite for 12.1, with a particular focus on Nameplates, Unit Frames and Raid Frames. Same look, same features, at a fraction of the cost.",
            },
        },
        features = {},
        fixes = {},
    },
    {
        version = "9.0.0",
        features = {
            {
                module = "Action Bars",
                title  = "Assisted Highlight Controls",
                desc   = "Resize the ring with an outset, or swap it for a tinted overlay",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Animations", section = "CUSTOM PROC GLOW", highlight = "Assisted Highlight Outset" },
            },
            {
                module = "DataBars",
                title  = "Combat Status Block",
                -- Toggle lives in the block's own settings popup: page-only nav.
                desc   = "Shows In Combat or Out of Combat, with an option to only appear in combat",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Damage Meters",
                title  = "Standalone Timer Styling",
                desc   = "Font, outline, alignment, size, background and border controls",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "STANDALONE COMBAT TIMER", highlight = "Standalone Combat Timer" },
            },
            {
                module = "Quality of Life",
                title  = "Combat Only Circles",
                desc   = "Cursor, GCD and cast circles can each show only in combat",
                nav    = { module = "EllesmereUIQoL", page = "Cursor", section = "CURSOR", highlight = "Combat Only" },
            },
            {
                module = "Unit Frames",
                title  = "Debuff Type Icons",
                desc   = "Debuff bars on Player Aura Bars can show a dispel type icon with position, size and offset",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars", section = "DEBUFF TYPE ICON", highlight = "Type Icon Position",
                           preSelect = function()
                               if EllesmereUI._setPABSelection then EllesmereUI._setPABSelection("debuff", "default") end
                           end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Fixed an error storm on action bar buttons when cooldowns updated during protected combat." },
            { module = "Action Bars", text = "The One Button Assist button's cooldown swipe no longer flickers to other abilities' cooldowns while chain-casting." },
            { module = "AuraBuff Reminders", text = "Blistering Scales and Source of Magic reminders no longer get stuck showing for the rest of a Mythic+ dungeon after the first pull." },
            { module = "AuraBuff Reminders", text = "Devourer Demon Hunters are now counted for Arcane Intellect instead of attack power buffs." },
            { module = "AuraBuff Reminders", text = "The Shadowform reminder no longer pops up in combat while a Voidweaver priest is in Voidform." },
            { module = "AuraBuff Reminders", text = "Reminders no longer stay hidden after a boss resets before you entered combat." },
            { module = "AuraBuff Reminders", text = "Clicking your own raid buff reminder now casts without needing a target selected." },
            { module = "AuraBuff Reminders", text = "The Healthstone reminder no longer shows during combat unless you are the warlock." },
            { module = "Bags", text = "Learnable recipes are no longer tinted red, and level-scaled gear now tints correctly for your level." },
            { module = "Bags", text = "Bank tab views now match item type and slot keywords in search, like the rest of the bank." },
            { module = "Bags", text = "Item levels in bags, bank and the gear flyout no longer show stale or base values after item upgrades." },
            { module = "Blizz UI Enhanced", text = "Holding the tooltip Peek Modifier over action buttons no longer causes blocked-action errors." },
            { module = "Chat", text = "The chat font option now applies to Korean and Chinese clients' own-language text instead of being locked to the stock font." },
            { module = "Cooldown Manager", text = "Fixed stuttering and a script-ran-too-long error during heavy combat when many cooldowns changed state at once." },
            { module = "Cooldown Manager", text = "Buff gain sounds now play when a proc lands the same moment the previous one is consumed." },
            { module = "Cooldown Manager", text = "Suppress GCD no longer lets the GCD sweep reappear on Hide Active State spells once their charges finish recharging." },
            { module = "Cooldown Manager", text = "Applying Threshold Text to a whole bar now also reaches buffs hosted on that bar." },
            { module = "Damage Meters", text = "Icon History now has its own Unlock Mode box sized to the full configured icon strip, instead of only loose Shift-drag placement." },
            { module = "DataBars", text = "The durability display no longer sticks at 100% until hovered." },
            { module = "DataBars", text = "The XP/Rep bar now shows correct progress for friendship reputations like Captain Tokka instead of 0%." },
            { module = "Friends List", text = "The Quick Join tab's Join Queue button no longer disappears." },
            { module = "General", text = "The Macro Factory's Wind Shear macro now shows its proper icon." },
            { module = "Minimap", text = "The rectangular minimap now keeps the player arrow and pings correctly positioned; it can no longer sit flush against the top or bottom screen edge." },
            { module = "Minimap", text = "The hidden difficulty flag no longer shows a ghost tooltip below the mail icon when Difficulty as Text is on." },
            { module = "Nameplates", text = "Target and hover border effects no longer stick to the wrong mob when nameplates get reassigned in packs." },
            { module = "Quality of Life", text = "Disable Right Click no longer blocks capturing wild battle pets." },
            { module = "Quality of Life", text = "Fixed chat errors triggered by protected system messages while Instance Reset Announce was enabled." },
            { module = "Quality of Life", text = "Auto-Open Containers now pauses at the mailbox and bank when using third-party mail or bank addons, not just the default windows." },
            { module = "Quality of Life", text = "Raid Tools marker buttons now work for players with the press-on-keyup input setting." },
            { module = "Quality of Life", text = "The Upgrade Calculator now opens docked beside the character sheet and follows it; drag it away to unpin for that open. Its character sheet button toggle also applies without a reload." },
            { module = "Raid Frames", text = "Merge Groups now renders correctly with every Group/Unit Growth combination, and the frames line up with the mover box." },
            { module = "Raid Frames", text = "The Poison dispel indicator now lights up for shamans using Poison Cleansing Totem when Only Dispellable is enabled, on raid frames and the unit frame dispel overlay." },
            { module = "Raid Frames", text = "Raid and party frames no longer flicker their power bar and layout at the start of a pull." },
            { module = "Raid Frames", text = "Your own role icon, role sorting, and tank nameplate coloring now follow your actual spec instead of a stale role left over from listing a group." },
            { module = "Resource Bars", text = "Moonkin Form is now its own entry in the per-form bar/text visibility and threshold options, separate from Caster." },
            { module = "Resource Bars", text = "Fixed a stray sliver of background color at the corner of bar-style class resources with border thickness 0." },
            { module = "Resource Bars", text = "Ironfur and Ignore Pain hash marks now follow the bar when it is set to vertical." },
            { module = "Resource Bars", text = "The cast bar's Arcane Missiles tick count now includes the extra missile from the tier set 2-piece." },
            { module = "Unit Frames", text = "The class resource bar no longer disappears when a group member changes spec." },
            { module = "Unit Frames", text = "Cast bars no longer lose their left border when the spell icon is disabled." },
            { module = "Localization", text = "Korean, Brazilian Portuguese and Traditional Chinese gained the Fonts and Textures page strings and the newest option labels." },
        },
    },
    {
        version = "8.9.8",
        mini = true,
        fixes = {
            { module = "AuraBuff Reminders", text = "Fixed invisible tooltips appearing over hidden reminder icons during boss encounters." },
            { module = "Blizz UI Enhanced", text = "Moving an item between trade slots now flashes the slot the item moved to instead of the one it left." },
        },
    },
    {
        version = "8.9.7",
        heroes = {
            {
                module = "Global Settings",
                title  = "New Fonts & Textures Pages",
                desc   = "Every font and texture setting in one place: a Fonts page and a Textures page in Global Settings, each with global options on top and a card per module; per-bar settings and border styles link straight to their module page. Fonts & Colors is now Colors.",
                nav    = { module = "_EUIGlobal", page = "Fonts" },
            },
        },
        features = {
            {
                module = "Global Settings",
                title  = "Blizzard Default Font",
                desc   = "Every font dropdown now offers the game's own standard font for your language",
                nav    = { module = "_EUIGlobal", page = "Fonts" },
            },
            {
                module = "Profiles",
                title  = "Presets Move to the Website",
                desc   = "Popular Presets now live at ellesmereui.com/presets with full previews; the Presets tab takes you there",
                -- Straight to the website popup: a page nav would land on
                -- Profiles and make the user click Presets themselves.
                onClick = function()
                    if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
                end,
            },
            {
                module = "DataBars",
                title  = "Hide Border",
                desc   = "Per-bar toggle to remove the 1px outline around a bar",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Minimap",
                title  = "Rectangular Shape",
                desc   = "A 4:3 minimap option alongside Square, Circle and Textured Circle",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap" },
            },
            {
                module = "Nameplates",
                title  = "Hide Icon Borders",
                desc   = "Hide Border toggles for the cast bar icon, buff, debuff and crowd-control icons",
                nav    = { module = "EllesmereUINameplates", page = "Display" },
            },
            {
                module = "Quickdraw",
                title  = "Interface Panels",
                desc   = "Add any interface panel to a menu, plus a preset that puts the whole micro menu on one keybind",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Raid Frames",
                title  = "Self Position with Merge Groups",
                desc   = "Show Self First / Last now works with Merge Groups enabled",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames" },
            },
            {
                module = "Resource Bars",
                title  = "Show Icon Divider",
                desc   = "Optional 1px line between the cast bar's icon and bar",
                nav    = { module = "EllesmereUIResourceBars", page = "Cast Bar", section = "LAYOUT", highlight = "Show Icon Divider" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Fixed a niche issue that could cause blocked-action errors during combat coming from Blizzard's hidden action bars." },
            { module = "Blizz UI Enhanced", text = "Reputation bars in the Character Sheet now keep Blizzard's standing colors instead of the accent tint." },
            { module = "Blizz UI Enhanced", text = "Fixed a tooltip crash when hiding tooltips for units carrying protected combat data." },
            { module = "Chat", text = "Korean chat lines now use the same line spacing as the default chat." },
            { module = "Cooldown Manager", text = "Tracking bars no longer show a different spell's name when gaining a buff, and buffs the game links together (like Spirit Walk and Spirit Wolf) no longer take over each other's bars." },
            { module = "Cooldown Manager", text = "Re-rolling a cycling buff like Roll the Bones no longer leaves the previous outcome's tracking bar up alongside the new one." },
            { module = "General", text = "Deleting or renaming the profile chosen in Pull Colors From no longer leaves the Colors page pointing at a profile that does not exist." },
            { module = "Nameplates", text = "Enemy cast bars no longer freeze at the end of empowered casts like Fire Breath in PvP." },
            { module = "Quality of Life", text = "Fixed an error when the Gateway Shard alert fired before its styling had loaded." },
            { module = "Raid Frames", text = "Right-click unit menus now open through Blizzard's own secure menu path, so entries like Set Focus no longer fail and distant raid members no longer show a pet menu." },
            { module = "Raid Frames", text = "Fixed a crash when a saved heal-absorb or max-health color was missing part of its data." },
            { module = "Resource Bars", text = "Cast and GCD bars no longer draw their border unevenly at some positions and UI scales." },
            { module = "Resource Bars", text = "Bar borders no longer disappear after opening the options panel until the border size was changed." },
            { module = "Resource Bars & Unit Frames", text = "Power bar height sliders now go up to 100 to match other frames." },
            { module = "Unit & Raid Frames", text = "Pinging a frame now pings its unit just like the default frames, enemies and bosses included, and no longer errors and jams the mouse." },
            { module = "Unit Frames", text = "The cast bar icon no longer draws a doubled border line where it meets the bar." },
            { module = "Unit Frames", text = "Health value and percent no longer stick to stale numbers after a max-health change, such as druid forms with stamina talents." },
            { module = "Unit Frames", text = "Class Resource pips no longer get stuck after a resource's maximum changes and changes back, such as Rogue combo point talents." },
            { module = "Localization", text = "Brazilian Portuguese gained the threshold badge tooltip and the profile import/export option tips." },
            { module = "Localization", text = "Simplified Chinese gained the 8.9.5-cycle option strings, the M+ portal short labels, and the Buff Manager popup translations." },
        },
    },
    {
        version = "8.9.6",
        mini = true,
        fixes = {
            { module = "AuraBuff Reminders", text = "Your own raid buff reminder now appears when it first goes missing mid-combat, such as after a combat res." },
            { module = "AuraBuff Reminders", text = "Fixed an invisible reminder icon that could stay stuck on screen after combat." },
            { module = "AuraBuff Reminders", text = "Reminders disabled for a location no longer flash briefly when entering it through a loading screen." },
            { module = "Bags", text = "Recent Items now flags pickups that merge into an existing stack." },
            { module = "Damage Meters", text = "Disable Snapping on a meter window now persists across reloads." },
            { module = "Raid Frames", text = "The incoming-res icon no longer stays stuck on a player after they revive (8.9.5 regression)." },
            { module = "Resource Bars", text = "The multi-band Amount/Percent toggle no longer showed Amount on fresh entries that were still capped as Percent, which made values above 100 snap back." },
            { module = "Unit Frames", text = "The Blizzard-style class power bar no longer turns invisible after portals, cutscenes or spec changes." },
            { module = "Unit Frames", text = "Player Aura Bars no longer stick showing every buff after a cinematic; the bars hide during the transition and repaint clean when it ends." },
        },
    },
    {
        version = "8.9.5",
        mini = true,
        fixes = {
            { module = "Action Bars", text = "The CD Swipe Opacity setting no longer resets to fully opaque on a button after hard-casting that spell." },
            { module = "Cooldown Manager", text = "Cooldown swipes on square icons no longer show a jagged sweep line at any angle." },
            { module = "Cooldown Manager", text = "Threshold Seconds, Color and Decimals now apply to tracked buff and debuff icons on cooldown bars, not just spell cooldowns." },
            { module = "Quality of Life", text = "Hide Tutorial Pop-ups no longer causes a multi-second login hitch on addon-heavy setups." },
            { module = "Raid Frames", text = "An icon indicator showing Non-Player Auras now reveals every debuff on a dead player, so persist-through-death debuffs stay visible for res decisions." },
            { module = "Raid Frames", text = "The incoming-res icon now stays up while a finished res waits to be accepted, instead of vanishing the moment the cast ends." },
            { module = "Raid Frames", text = "Absorb bars no longer draw a faint shadow fringe around their edges." },
            { module = "Resource Bars", text = "The Threshold Settings buttons now show an info badge whenever a threshold is configured, colored by whether your current spec is affected." },
            { module = "Resource Bars", text = "Devourer soul fragment thresholds now respect Threshold as: Percent -- re-check your threshold number if you had tuned it as a flat count." },
            { module = "Resource Bars", text = "The Shift Elements Extra Y Offset now counts in screen pixels, so 1 moves exactly one pixel at any UI scale." },
            { module = "Localization", text = "Korean gained the new season's M+ abbreviations and the 40-man frame size labels." },
            { module = "Localization", text = "German gained ~25 new entries and reworded many existing ones." },
            { module = "Localization", text = "Brazilian Portuguese and Traditional Chinese gained the widget bar size strings; Traditional Chinese also translated the new season's portal labels." },
        },
    },
    {
        version = "8.9.4",
        mini = true,
        fixes = {
            { module = "Action Bars", text = "Fixed a \"script ran too long\" error during keybind setup at login or reload on slower machines." },
            { module = "Action Bars & Cooldown Manager", text = "Options previews no longer cut the bottom icon row in half when the preview overflows at smaller UI scales." },
            { module = "Blizz UI Enhanced", text = "Reskin Widget Bars gained a cog to set a minimum size so bars on shrunken nameplates stay readable (off by default)." },
            { module = "Blizz UI Enhanced", text = "Character and Inspect sheets now flag a missing enchant on off-hand weapons." },
            { module = "Blizz UI Enhanced", text = "Dungeon Finder and Raid Finder rewards, the Extra Action Button icon and the Mythic+ dungeon icons now match the skin." },
            { module = "General", text = "M+ Portals (chat and minimap flyouts, /keys teleports and the DataBars travel tooltip) now list the new season's dungeons." },
            { module = "Localization", text = "German gained ~60 new entries and many rewordings; Brazilian Portuguese ~95, Traditional Chinese 34 and Korean 30 new entries." },
            { module = "Player Aura Bars", text = "Bars no longer show every buff after a cinematic -- the External Defensives bar was the most visible case." },
            { module = "Raid Frames", text = "Debuffs with Center growth and a Top position now anchor to the top of the frame and grow downward, fixing them landing mid-frame on raid-sized frames -- re-check your offset if you had compensated for it." },
            { module = "Unlock Mode", text = "The X/Y boxes and Center on Screen no longer land odd-width bars one pixel off (typing 0 put a bar at -1)." },
            { module = "Unlock Mode", text = "Exit and Save & Exit no longer overlap the toolbar toggles on languages with longer labels." },
        },
    },
    {
        version = "8.9.3",
        mini = true,
        fixes = {
            { module = "Aura Buff Reminders", text = "The Tidecaller's Guard imbue reminder now shows for Restoration Shamans; it and Thunderstrike Ward only remind while a shield is equipped." },
            { module = "Cooldown Manager", text = "Sacred Weapon / Holy Bulwark no longer disappears from the live bar while still listed in your bar settings." },
            { module = "Raid Frames", text = "Absorb shields no longer draw doubled over missing health on units below full health (8.9.2 regression)." },
        },
    },
    {
        version = "8.9.2",
        heroes = {},
        features = {
            {
                module = "Bags",
                title  = "Compact Slot Groups",
                desc   = "Pack the smaller equip-slot groups beside each other so Armory views take less vertical space; cog on Group Armory by Slot",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "EXTRAS", highlight = "Group Armory by Slot" },
            },
            {
                module = "Blizz UI Enhanced",
                title  = "Character Sheet Durability",
                desc   = "Opt-in durability display above the model, in the stats header or the footer, colored green to red",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "CORE OPTIONS", highlight = "Show Item Durability" },
            },
            {
                module = "Cooldown Manager",
                title  = "Tracking Bars Visibility",
                desc   = "Tracking Bars gain the CDM Bars Visibility mode and Visibility Options, reacting to changes instantly",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "Display", highlight = "Visibility" },
            },
            {
                module = "Player Aura Bars & Unit Frames",
                title  = "Precise Below Timers",
                desc   = "Show aura timers under your chosen threshold as minutes and seconds (4:37 instead of 4m)",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                module = "Quickdraw",
                title  = "Profession Specialization Abilities",
                desc   = "Overload Herbs, Overload Ore or Sharpen Your Knife resolve per character, with cooldowns shown",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Spec Overrides",
                title  = "Buff Manager Starting Point",
                desc   = "New override Buff Managers can start as a copy of main, a copy of another override, the default preset, or empty",
                nav    = { module = "_EUIProfiles", page = "Overrides" },
            },
            {
                module = "Spec Overrides",
                title  = "Override Info Icons",
                desc   = "Gold-bordered settings show which overrides adjust them; the first Default Editing Mode edit gets a one-time heads-up",
            },
            {
                module = "Visibility",
                title  = "Hide when Skyriding Mounted",
                desc   = "Formerly Resource Bars only; now in every module's Visibility Options dropdown",
            },
        },
        fixes = {
            { module = "Chat", text = "Clicking [Show Message] on a filtered whisper now reveals the message." },
            { module = "Chat", text = "Moving the main chat window in Unlock Mode no longer shrinks it to an old Edit Mode size or lands it slightly off after saving, and the resize corner icon is easier to see." },
            { module = "Cooldown Manager", text = "Reordering a spell no longer makes an unrelated potion or trinket icon vanish from its slot, and a potion's CD Ready glow now survives a reload." },
            { module = "Cooldown Manager", text = "Fixed icons that could render invisible in their slot -- buffs hosted on a cooldown or utility bar vanished while active if the Buffs bar was hidden, and a spell re-added through the spell picker could inherit an old hidden-when-ready state it no longer showed anywhere." },
            { module = "Cooldown Manager", text = "Cobra Shot (and other spells the game spuriously ties to an unrelated base spell) now keeps its assigned position instead of jumping to the front of the bar." },
            { module = "Player Aura Bars", text = "Default bar and filter names now show translated on non-English clients." },
            { module = "Profiles", text = "The Spec Overrides list now points out a conditional override that a spec override is holding back, naming the group, instead of showing it as live." },
            { module = "Quality of Life", text = "Auto Open Containers now correctly skips warbound containers like the Cache of Void-Touched when Exclude Warbound Containers is on, and no longer permanently ignores a container it first saw before its data had loaded." },
            { module = "Raid Frames", text = "Overshields no longer disappear in dungeons, raids and duels (they were hidden whenever restricted content was active -- most visibly under a dispel highlight)." },
            { module = "Raid Frames", text = "In the Debuff Manager the Base Icons grid now follows the Editing Spec dropdown like every indicator -- inherited from All Specs in each spec's view, with a toggle to switch it off for that spec only." },
            { module = "Resource Bars & Unit Frames", text = "The Power Type choice (Insanity, Astral Power, Maelstrom, Ebon Might, Mana alternates) no longer resets to mana on a slow login, and it is now stored per specialization instead of colliding across classes on a shared profile -- if you had an alternate Power Type selected, re-select it once." },
            { module = "Unit Frames", text = "The absorb shield overlay and absorb text now clear when a shield expires on its own timer instead of sticking until the next update." },
            { module = "Unit Frames", text = "The player frame's All Buffs, Has Duration and All Debuffs filter toggles can be turned off again; an empty selection is now flagged with the same red warning as Player Aura Bars." },
            { module = "Unit Frames", text = "Class Color on the Target of Target and Focus Target frames (name and background) no longer turns white in combat." },
            { module = "Localization", text = "Simplified Chinese, Korean, Traditional Chinese, German and Brazilian Portuguese all caught up with 8.9.1, and the custom raid size cog title now translates the tier name." },
        },
    },
    {
        version = "8.9.1",
        heroes = {},
        features = {
            {
                module = "Bags",
                title  = "Group Armory by Slot",
                desc   = "Nest The Armory and gear category views under equip-slot headers (Head, Chest, Trinket, 2H, 1H, ...); off by default",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "EXTRAS", highlight = "Group Armory by Slot" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Cast Bar Size Matching",
                desc   = "Target/Focus Cast Bars and Targeted Spell Bars can width and height match other elements in Unlock Mode",
                nav    = { module = "EllesmereUIMythicTimer", page = "Target/Focus Bars" },
            },
            {
                module = "Nameplates",
                title  = "Smarter Dispel Glow",
                desc   = "Glows only on buffs your character can actually dispel, updates live on talent swaps, plus a Color by Type cog",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "EXTRA AURA OPTIONS", highlight = "Dispel Glow Style" },
            },
            {
                module = "Nameplates",
                title  = "Hide Copies of Blood Plague",
                desc   = "Blood Death Knights get a toggle (on by default) that shows one Blood Plague icon instead of one per copy",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS" },
            },
            {
                module = "Performance",
                title  = "Suite-Wide Efficiency Pass",
                desc   = "Idle CPU cost cut by a third; several background systems now cost nothing until their feature is on screen",
            },
            {
                module = "Spec Overrides",
                title  = "Edit Custom Buff and Debuff Managers",
                desc   = "An Edit button on custom Buff and Debuff Manager overrides opens them for editing directly, in any context",
                nav    = { module = "_EUIProfiles", page = "Overrides" },
            },
            {
                module = "Quality of Life",
                title  = "Raid Tools Button Switches",
                desc   = "Hide Role Check, Convert to Raid or Disband, and drop pull timers by setting them to 0; the panel shrinks to fit",
                nav    = { module = "EllesmereUIQoL", page = "Raid Tools", section = "GROUP BUTTONS", highlight = "Show Role Check" },
            },
            {
                module = "Quickdraw",
                title  = "Dynamic Profession Entries",
                desc   = "Profession 1 and 2, Cooking, Fishing, Archaeology and their second abilities resolve per character, so one palette fits every alt",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Raid Frames",
                title  = "40 Man Raid Size",
                desc   = "A 40 Man custom raid size tier for open-world and 40-player content",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "FRAME SIZES" },
            },
            {
                module = "Raid Frames",
                title  = "Buff Manager Filter Colors",
                desc   = "Square indicators get a color swatch per assigned filter, coloring all of that filter's spells at once",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager" },
            },
            {
                module = "Raid Frames",
                title  = "Click-Cast Unit Types",
                desc   = "Frame clicks and items can be limited to friendly or enemy units, and a friendly + harmful spell can share one key",
                nav    = { module = "EllesmereUIRaidFrames", page = "HoverCast" },
            },
        },
        fixes = {
            { module = "Bags", text = "Right-clicking a bank tab to open its settings no longer errors when the options panel has not been opened yet this session." },
            { module = "Blizz UI Enhanced", text = "Widget-bar reskins over nameplates (boss and rare mechanic bars) are now open-world only; inside instances those bars keep Blizzard's default look." },
            { module = "Cooldown Manager", text = "Icons no longer come up missing (with a stretched racial) after a slow login." },
            { module = "Cooldown Manager", text = "Spells that only exist on a Blizzard cooldown layout you switch to later in the session now keep your assigned position instead of jumping to the front of the bar." },
            { module = "Cooldown Manager", text = "The Additional Bar Offset now stays applied after a spec swap or profile switch instead of snapping the bar back to its base position." },
            { module = "Cooldown Manager", text = "Tracking bars for spells that cycle through differently-named forms (such as Diabolist rituals) show the active form's name again instead of a fixed one." },
            { module = "Nameplates", text = "The Enemy Buff Filter's Important mode now always includes dispellable buffs (purges and enrages), so the Dispel Glow can no longer miss one; the Show All option was retired." },
            { module = "Nameplates", text = "The Dispel Glow color swatch and preview toggle now sit beside the Dispel Glow Style dropdown." },
            { module = "Player Aura Bars", text = "Fixed an \"attempted to call a protected function\" error when a bar was shown or hidden during combat (vehicle rides, cinematics, faction changes)." },
            { module = "Player Aura Bars", text = "Bars now appear immediately after a reload during combat instead of waiting for combat to end." },
            { module = "Quality of Life", text = "The Movement Alert gains a Text: Duration display mode that shows only the countdown number." },
            { module = "Raid Frames", text = "Fixed a Lua error on friendly boss frames when names or health text are set to class color." },
            { module = "Raid Frames", text = "The Buff Manager Icon Zoom slider now applies to the real frames (not just the preview), and Debuff Manager custom tiles pick up debuff style changes immediately instead of after a reload." },
            { module = "Raid Frames", text = "The CC tracker integration now recognizes MiniAuras (the renamed MiniCC), while older MiniCC installs keep working." },
            { module = "Raid Frames", text = "Fixed errors opening the party preview with an incomplete imported profile, and warning spam opening the Debuff Manager page with debuff stacks disabled." },
            { module = "Resource Bars", text = "The player cast bar and its channel tick marks no longer vanish when a channel is instantly recast mid-channel (such as Arcane Missiles with Clearcasting)." },
            { module = "Unit Frames", text = "The player power bar and its text now use the color of the power type you chose to display (Mana on Shadow, Balance, Feral, Guardian and Elemental) instead of the spec's real resource color." },
            { module = "Localization", text = "Brazilian Portuguese and Traditional Chinese translations caught up with everything added since 8.8.8." },
        },
    },
    {
        version = "8.9.0",
        heroes = {
            {
                module = "Unit Frames",
                title  = "Dynamic Health Color",
                desc   = "Color your health bars by how wounded you are. Classic runs green through yellow to red, Custom Colors blends your own three stops, and Class Reactive shows class color at full health bleeding into your chosen colors as damage comes in. Matches the party frame modes exactly.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames" },
            },
            {
                module = "Nameplates",
                title  = "Hover Effect",
                desc   = "The mouseover highlight now offers the full Target Effect set: EUI Glow, Border Color, Highlight, and Border Size, each with its own colors. Your current hover look is preserved exactly until you opt into more.",
                nav    = { module = "EllesmereUINameplates", page = "Display" },
            },
        },
        features = {
            {
                module = "Bags",
                title  = "Pawn Upgrade Arrows",
                desc   = "Upgrade arrows on bag and reagent items with Pawn's Bag Upgrade Advisor",
                nav    = { module = "EllesmereUIBags", page = "Bags" },
            },
            {
                module = "Cooldown Manager",
                title  = "Liquid Luster",
                desc   = "New potion preset, and the swap option now covers all three combat potions",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Nameplates",
                title  = "Enemy Buff Filter",
                desc   = "Important (new default), Dispellable, or all buffs; the Dispel Glow marks dispellable buffs under any filter",
                nav    = { module = "EllesmereUINameplates", page = "General" },
            },
            {
                module = "Raid Frames",
                title  = "Extra Frames Indicator Sizing",
                desc   = "A new cog on the Extra Frames size sliders can keep indicators and auras at their normal size",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames" },
            },
            {
                module = "Raid Frames & Unit Frames",
                title  = "Has Duration Filter",
                desc   = "Combines with any debuff selection to show only timed debuffs, hiding permanent ones",
                nav    = { module = "EllesmereUIRaidFrames", page = "Debuff Manager" },
            },
        },
        fixes = {
            { module = "Bags", text = "Bank search now matches tooltip content (armor type, upgrade track, stats) like bag search, instead of item names only." },
            { module = "Blizz UI Enhanced", text = "Starting a ready check no longer leaves an empty skinned box on the initiator's screen, and the prompt's title and layout are properly centered." },
            { module = "Chat", text = "Changing the font size from a chat tab's right-click menu now survives /reload." },
            { module = "Chat", text = "Saved chat history no longer shows Battle.net whispers under the wrong friend's name after logging in again." },
            { module = "Chat", text = "Hovering or right-clicking chat lines is no longer off by one message after receiving a message while scrolled up." },
            { module = "Cooldown Manager", text = "The Minimum Bar Size setting is available on every bar type again, not only buff bars." },
            { module = "Cooldown Manager", text = "Buffs hosted on cooldown bars no longer leak onto other specs' and classes' bars through the Generic CDs/Buffs sync, and removing a leaked icon now sticks." },
            { module = "Cooldown Manager", text = "The Health Potion preset now tracks the new Concentrated Health Potion first, falling back to Silvermoon potions." },
            { module = "Cooldown Manager", text = "Tracked trinket buffs now respect their custom buff bar assignment while the Trinket Slot presets are in use, and trinkets no longer occasionally jump from a custom bar back to the Cooldowns bar." },
            { module = "Nameplates", text = "Enemy buffs and the purge glow show again in arenas and battlegrounds." },
            { module = "Options", text = "Fixed a blank settings panel and an error when another addon opened EUI options via a deep link (such as a profile installer) before the panel's first open." },
            { module = "Player Aura Bars", text = "Filter spells with alternate ids (such as Divine Hymn) now track correctly when checked in the Filter Editor." },
            { module = "Raid Frames", text = "Metamorphosis now displays correctly for Havoc in the buff presets." },
            { module = "Raid Frames", text = "The Healer Mana Display mover no longer appears in Unlock Mode while the feature is disabled." },
            { module = "Raid Frames", text = "Debuff Manager indicators with Center growth at a top or bottom position no longer sit half an icon off the frame edge." },
            { module = "Raid Frames", text = "Debuff Manager indicators now use the full two-lane filter dropdown, with Show and Hide lanes, All Debuffs, and Non-Player Auras, instead of the old single list." },
            { module = "Raid Frames & Player Aura Bars", text = "Hovering a disabled filter checkbox now explains that All Debuffs is selected." },
            { module = "Raid Frames & Unit Frames", text = "The Movement buff preset now includes Piercing Howl and every class's Time Spiral buff." },
            { module = "Resource Bars", text = "The Rapid Fire cast bar now shows shot tick marks, including Quick Draw's extra shots." },
            { module = "Localization", text = "German translations massively expanded and corrected (including German search keywords), plus Korean and Traditional Chinese catch-ups for everything new in 8.8.9." },
        },
    },
    {
        version = "8.8.9",
        heroes = {
            {
                module = "Filters",
                title  = "Show & Hide Lanes",
                desc   = "Every aura filter dropdown across Player Aura Bars, Unit Frames and Raid Frames now has a green Show lane and a red Hide lane, so you can add and subtract filters at the same time in any mode.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                module = "Raid Frames & Player Aura Bars",
                title  = "Spec Groups",
                desc   = "The Buff/Debuff Manager and Player Aura Bars can now set indicators to All Specs, role groups, or a single spec, with group items appearing on each spec's list as inherited tiles you can toggle per spec. Right-click any indicator to copy it to another spec or group.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager" },
            },
            {
                module = "Blizz UI Enhanced",
                title  = "Reskins, Many Reskins",
                desc   = "Blizzard's on-screen widget bars (like event objectives) plus five more windows (Ready Check, Queue Status, the Delve tier picker, Choice windows and Trade) now match the EUI look, and quest, vendor, loot roll and trade icons carry square rarity-colored borders.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Bar Text Offsets",
                desc   = "X/Y offset cogs for XP, Reputation and House Favor bar text",
                nav    = { module = "EllesmereUIActionBars", page = "Menu, Bags & XP Bars" },
            },
            {
                module = "Bags",
                title  = "Equipment Set Categories",
                desc   = "Split set gear into per-set categories, with set names on icons",
                nav    = { module = "EllesmereUIBags", page = "Bags" },
            },
            {
                module = "Cooldown Manager",
                title  = "Minimum Bar Size",
                desc   = "Reserve a minimum width or height in icon slots via a new Icon Scale cog",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Cooldown Manager",
                title  = "Additional Bar Offset",
                desc   = "Extra X/Y offset on top of any bar position",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Cooldown Manager",
                title  = "Shift Elements If No Bars",
                desc   = "Global Tracking Bar groups can shift anchored elements into their empty slot",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
            {
                module = "General",
                title  = "Game Text Scale",
                desc   = "Resize Blizzard's default game text from 75-125%",
                nav    = { module = "_EUIGlobal", page = "Fonts", section = "GLOBAL FONT", highlight = "Game Text Scale" },
            },
            {
                module = "Nameplates",
                title  = "Color Name by Reaction",
                desc   = "Hostile or Neutral enemy name text with custom colors",
                nav    = { module = "EllesmereUINameplates", page = "Colors" },
            },
            {
                module = "Player Aura Bars",
                title  = "Icon Shapes",
                desc   = "Circle, Diamond, Hexagon, Shield and more, with matching borders and dispel rings",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                module = "Player Aura Bars",
                title  = "Use Blizzard Buffs & Bar Toggles",
                desc   = "Keep Blizzard's buff display while custom bars run; built-in bars can now be disabled",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                module = "Quality of Life",
                title  = "Hide Loot Rolls Window",
                desc   = "Hide it completely, or let it close itself after a delay",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "GENERAL", highlight = "Hide Loot Rolls Window" },
            },
            {
                module = "Quickdraw",
                title  = "Pings Preset",
                desc   = "A ready-made action menu for the ping system",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Raid Frames",
                title  = "Friendly Boss Frames in Dungeons",
                desc   = "New Show in Dungeons cog, attaching beside the party frames",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "FRIENDLY BOSS FRAMES", highlight = "Add Friendly Boss Group" },
            },
            {
                module = "Unit Frames",
                title  = "Small Frame Background Colors",
                desc   = "Own background swatches for target of target, focus target and pet",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames" },
            },
            {
                module = "Unlock Mode",
                title  = "Quick Hides",
                desc   = "Hold Shift to hide the top bar; Shift+Right-Click also hides anchor previews",
            },
        },
        fixes = {
            { module = "Action Bars", text = "XP, Reputation and House Favor bar text is no longer clipped by the bar border at larger text sizes." },
            { module = "Aura Buff Reminders", text = "Icon labels and item counts now render above icon borders and glows." },
            { module = "Blizz UI Enhanced", text = "Window skin borders no longer cover the text on skinned bars." },
            { module = "Blizz UI Enhanced", text = "Item comparison tooltips now hide correctly during combat when Show Tooltips is set to Out of Combat or Out of Boss Combat." },
            { module = "Cooldown Manager", text = "Trinket buffs tracked in Blizzard's Cooldown Manager can be added to buff bars and tracking bars again." },
            { module = "Cooldown Manager", text = "Tracking Bars no longer show the wrong spell name in combat." },
            { module = "Cooldown Manager", text = "Built-in active-state overlays (such as Ebon Might's) no longer paint onto the wrong icon on custom bars." },
            { module = "Cooldown Manager", text = "A global Tracking Bars group with no bars on the current spec can now be edited." },
            { module = "Cooldown Manager", text = "The Tracking Bars Decimal Threshold can now be set as low as 1 second." },
            { module = "Damage Meters", text = "Anchored meter windows no longer flash at the wrong position for a moment on login and reload." },
            { module = "General", text = "Fixed script ran too long errors during login, reload and profile switches on slower systems." },
            { module = "General", text = "Fixed the settings panel sometimes failing to open on the first try of a session on slower systems." },
            { module = "Nameplates", text = "Show Special Off-Tank Color works again in Mythic+ and raids." },
            { module = "Nameplates", text = "The soft-interact icon no longer appears over attackable enemies." },
            { module = "Player Aura Bars", text = "Bars no longer linger on screen after disabling the module or switching profiles." },
            { module = "Quality of Life", text = "The Burning Rush movement alert no longer shows the wrong buff after riding a vehicle." },
            { module = "Quest Tracker", text = "Fixed errors on the world map (blocked actions and secret-value errors on pins and tooltips) caused by quest icon suppression." },
            { module = "Quest Tracker", text = "Fixed an error in dungeons and raids triggered by collapsing tracker sections; section titles remain fully clickable." },
            { module = "Raid Frames", text = "The Max Character Name setting now uses its own party value when the party Text Display section is unsynced." },
            { module = "Raid Frames", text = "The buff presets now track Arcane Surge and Elemental Shaman Ascendance correctly." },
            { module = "Resource Bars", text = "Arcane Missiles channel ticks now match the real missile timing, and tick marks no longer vanish mid-channel." },
            { module = "Resource Bars", text = "Evoker empowered casts no longer randomly lose their stage ticks." },
            { module = "Unit Frames", text = "Class-colored health backgrounds now show reaction colors for NPCs instead of an incorrect class color." },
            { module = "Localization", text = "Korean and Brazilian Portuguese translations updated, Russian clients can now select every Cyrillic-capable bundled font, and several tooltips and labels now localize correctly on non-English clients." },
        },
    },
    {
        version = "8.8.8",
        features = {
            {
                module = "Quality of Life",
                title  = "Configurable Secondary Stats",
                desc   = "Percent, raw rating or both, abbreviated labels, and a reorderable list of which stats show, tertiaries included",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "EXTRAS", highlight = "Secondary Stat Display" },
            },
            {
                module = "Raid Frames",
                title  = "Frame Strata Control",
                desc   = "Lift raid and party frames above spell effects that overlapped them",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "EXTRAS", highlight = "Frame Strata" },
            },
            {
                module = "Cooldown Manager",
                title  = "Simpler Item Tracking",
                desc   = "Trinkets, potions and Healthstones come from EUI's own item system again; items tracked in Blizzard's Cooldown Manager render as plain unmanaged icons beside them",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
        },
        fixes = {
            { module = "Chat", text = "Input on Top now masks the chat text on every tab, not just the first." },
            { module = "Chat", text = "Links in restored chat history show as plain text instead of dead links that could misclick onto other lines." },
            { module = "Cooldown Manager", text = "Fixed spec swaps deleting spells from custom bars; re-add any lost spells once and they now stay." },
            { module = "Cooldown Manager", text = "Fixed unusable trinkets appearing and duplicate icons for one physical trinket." },
            { module = "Cooldown Manager", text = "The Buff Loss sound no longer fires when a buff is gained or refreshed by replacement." },
            { module = "General", text = "Fixed the dispel-type recolor on aura icons washing out and blending with the border color at large icon sizes, everywhere aura icons render." },
            { module = "General", text = "Fixed a script-ran-too-long error when logging into or reloading inside raid instances." },
            { module = "Nameplates", text = "The interact icon shows on nameplates again." },
            { module = "Quality of Life", text = "Fixed buff-based movement alerts such as Burning Rush erroring and never showing." },
            { module = "Quickdraw", text = "The Menu Cancel Action option stays hidden until a Toggled Menu Select Action key is bound." },
            { module = "Raid Frames", text = "Heal prediction renders when Absorb Style is set to none, and repaints when only incoming heals change." },
            { module = "Raid Frames", text = "Health Bar Color indicators keep the health bar's texture shading instead of painting a flat block, and inherit Fill Opacity." },
            { module = "Resource Bars", text = "The player cast bar no longer sticks on screen with its timer running after some channeled casts." },
            { module = "Resource Bars", text = "The channel end-tick line clears between channels when interior tick marks are off." },
            { module = "Resource Bars", text = "Fixed a thin background ring around the cast bar at Border Size 0, and a phantom icon-width gap with the icon disabled." },
            { module = "Unit Frames", text = "Bottom-anchored buffs and debuffs reserve cast bar space correctly on every login instead of randomly per session." },
            { module = "Unit Frames", text = "Player Aura Bars icon sizes now go up to 400 and duration/stack text up to 60." },
            { module = "Unit Frames", text = "Lower Player Aura Bars overhead for users who leave Show Duration Swipe on." },
            { module = "Unit Frames", text = "The player frame shows the vehicle's name again while you are in a vehicle." },
            { module = "Localization", text = "Traditional Chinese adds 125 strings; Brazilian Portuguese gets a major batch across QoL, Aura Buff Reminders, Resource Bars and more." },
        },
    },
    {
        version = "8.8.7",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Full Item & Racial Support",
                desc   = "Blizzard's native racial, trinket, potion and Healthstone entries now work fully on EUI bars: always rendered, styled by your settings, and ordered, moved, hidden or removed like any other icon. Equipment cooldowns draw properly and never double up with the EUI trinket icon.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Chat",
                title  = "Accurate Links & Persistent Size",
                desc   = "Hyperlinks are served by Blizzard's own click zones, so clicks land exactly on the text even with shortened channel names and timestamps on. Chat size now lives in Edit Mode itself and survives every loading screen without flicker.",
                nav    = { module = "EllesmereUIChat", page = "Chat" },
            },
        },
        features = {
            {
                module = "Unit Frames & Resource Bars",
                title  = "Pingable Frames & Resource Callouts",
                desc   = "Ping player, target, focus and friendly frames; health and power bars send the low-resource callout",
            },
            {
                module = "Unit Frames",
                title  = "Restricted-Unit Class Colors",
                desc   = "Custom class colors now reach target-of-target and focus-target frames when the restricted unit is you",
                nav    = { module = "_EUIGlobal", page = "Colors", section = "CLASS COLORS", highlight = "" },
            },
            {
                module = "Unit Frames",
                title  = "Aura Row Wrap Direction",
                desc   = "Player aura rows can wrap upward or downward",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars", section = "CORE", highlight = "Growth Direction" },
            },
            {
                module = "Quality of Life",
                title  = "Set Focus Macro Extras",
                desc   = "Optional Auto Mark, Ping and Announce lines, each with its own toggle and a raid marker picker",
                nav    = { module = "EllesmereUIQoL", page = "QoL" },
            },
            {
                module = "Raid Frames",
                title  = "Click Casting Binding Rules",
                desc   = "Each binding chooses where it is active (Solo, Party, Raid, PvP) and whether it casts on frames, mouseover, or both",
                nav    = { module = "EllesmereUIRaidFrames", page = "HoverCast" },
            },
            {
                module = "Quickdraw",
                title  = "By-Position Spec Entries",
                desc   = "Specialization 1-4 entries switch by position, so palettes carried to alts of any class still work",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Conditional bar visibility, like hide when mounted, no longer sticks after dragging a spell between bars." },
            { module = "Action Bars", text = "Settings changes can no longer reshape the Edit Mode layout list; custom layouts and the active layout are preserved." },
            { module = "Aura Buff Reminders", text = "Reminders in Mythic 0 and the keystone lobby use the pre-pull threshold only until the first pull, instead of nagging between packs." },
            { module = "Aura Buff Reminders", text = "The Devotion Aura reminder no longer false-fires when a second Paladin provides the aura." },
            { module = "Aura Buff Reminders", text = "The Earth Shield reminder from Elemental Orbit no longer sticks on screen through combat." },
            { module = "Aura Buff Reminders", text = "The Tidecaller's Guard weapon enchant gains its own reminder toggle." },
            { module = "Chat", text = "Chat no longer freezes and tabs stay clickable after leaving combat with Out of Combat visibility." },
            { module = "Chat", text = "Tabs of user-created chat windows clip at the chat edge when the tab row overflows." },
            { module = "Chat", text = "Resizing chat is disabled during combat, matching Edit Mode." },
            { module = "Chat", text = "Chat font no longer grows on Chinese, Japanese and Korean clients." },
            { module = "Chat", text = "The input-on-top text strip no longer reserves space while hidden." },
            { module = "Chat", text = "Whisper tab alerts animate when another addon replaces the tab flash system." },
            { module = "Cooldown Manager", text = "Tracking now syncs removals too: entries removed or hidden in Blizzard's Cooldown Manager clear from EUI bars automatically instead of accumulating per spec." },
            { module = "Cooldown Manager", text = "Removing a racial from a bar works again." },
            { module = "Cooldown Manager", text = "Custom spell IDs on buff bars follow every bar setting, update live, and their countdown matches Blizzard second for second." },
            { module = "Cooldown Manager", text = "A tracked spell with no saved position no longer jumps to the front of the bar after a Cooldown Manager layout switch." },
            { module = "Cooldown Manager", text = "Reverse Swipe stays applied on regular class spells." },
            { module = "Cooldown Manager", text = "Duration Text draws numbers on bars from imported profiles, matching what the toggle shows." },
            { module = "Cooldown Manager", text = "The Focus Kick reminder detects casters again on 12.1, works inside Mythic+, and no longer floods errors in keys." },
            { module = "Data Bars", text = "The experience bar no longer clears its tracking on right-click, and the XP block gains a click tooltip and a No Rep Tracked state." },
            { module = "General", text = "Width and height matches, such as a power bar matched to Essential Cooldowns, no longer revert after spec swaps." },
            { module = "Minimap", text = "Hiding protected buttons no longer errors." },
            { module = "Mythic+ Tools", text = "Target and Focus cast bars no longer error when their fill texture is missing." },
            { module = "Nameplates", text = "The Uninterruptible cast color holds at any plate opacity." },
            { module = "Nameplates", text = "Borders keep their bottom edge after a wrapped cast bar." },
            { module = "Nameplates", text = "Hide Enemy Nameplates out of Combat respects conditional overrides, profile switches and imports." },
            { module = "Quality of Life", text = "Movement alerts such as Burning Rush work identically everywhere, including Mythic+ and raids." },
            { module = "Quest Tracker", text = "Clicking group-finder entries no longer errors." },
            { module = "Quickdraw", text = "The Menu Cancel Action option stays hidden until a Toggled Menu Select Action key is bound." },
            { module = "Raid Frames", text = "Vertical Buff Manager bars fill vertically; a bar that drained the wrong way flips with Reverse Fill." },
            { module = "Raid Frames", text = "Retribution and Protection paladins use their own Buff Manager settings instead of Holy's." },
            { module = "Resource Bars", text = "The Ignore Pain tick refreshes when Shield Slam consumes Violent Outburst." },
            { module = "Resource Bars", text = "The player cast bar no longer sticks on screen with its timer running after some channeled casts." },
            { module = "Resource Bars", text = "The channel end-tick line clears between channels when interior tick marks are off." },
            { module = "Unit Frames", text = "Class Icon portraits render correctly in every art style, and target portraits follow target changes." },
            { module = "Unit Frames", text = "Enable Boss Frames applies live with the EllesmereUI source." },
            { module = "Unit Frames", text = "Player aura rows accept negative spacing, and aura bars no longer error when layouts change during combat." },
            { module = "Localization", text = "Major updates for Brazilian Portuguese, Simplified Chinese and Traditional Chinese, plus Chinese options-search keywords; the Quickdraw module is renamed on Simplified Chinese clients." },
        },
    },
    {
        version = "8.8.6",
        features = {
            {
                module = "Raid Frames",
                title  = "Fully Vertical Raid Frames",
                desc   = "Every growth combination allowed -- Up + Up lays the raid out in one straight line",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "LAYOUT", highlight = "Group Growth" },
            },
            {
                module = "Chat",
                title  = "Timestamp All Messages",
                desc   = "Stamps system messages, loot, achievements, and addon prints, not just player chat",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "EXTRAS", highlight = "Timestamp All Messages" },
            },
            {
                module = "Quickdraw",
                title  = "Bigger Menus & New Presets",
                desc   = "Menus hold up to 16 entries, plus Quest Items and Professions presets, a Last Used Mount entry, and a Menu Cancel Action keybind",
            },
            {
                module = "Quickdraw",
                title  = "Smarter Pickers",
                desc   = "Mount and toy pickers list everything you own and also search source and favorite fields",
            },
        },
        fixes = {
            { module = "General", text = "Reloading the UI while in combat no longer causes script-ran-too-long errors and half-loaded modules." },
            { module = "Raid Frames", text = "Party frame dispel overlays now follow the configured display mode, icons, and custom dispel colors." },
            { module = "Raid Frames", text = "Right-clicking a raid member who is in a different zone now opens the player menu instead of the pet menu." },
            { module = "Raid Frames", text = "Buff Manager effect indicators set to an unavailable Show When mode now display instead of showing nothing." },
            { module = "Chat", text = "Clickable links and player names on lines with shortened channel names now respond exactly where they appear, and the wheel scrolls into restored history right after a reload." },
            { module = "Cooldown Manager", text = "Racial spells assigned to a custom bar stay there through spec changes and relogs, and racials untracked in Blizzard's Cooldown Manager display again." },
            { module = "Cooldown Manager", text = "Pandemic Glow no longer flashes briefly when a tracked buff is freshly applied, and invisible reserved buff slots no longer show tooltips or block mouseover casts." },
            { module = "Quickdraw", text = "Nested menus open reliably when moving the pointer to a child entry, and stack counts render pixel-sharp at every scale." },
            { module = "Unit Frames", text = "Pinging over unit frames no longer errors in Mythic+ and raid combat; frame pings are temporarily world pings pending a Blizzard fix." },
            { module = "Aura Buff Reminders", text = "The Missing Pet reminder no longer appears while mounted or flashes on dismount." },
            { module = "Resource Bars", text = "All entries in the Threshold Settings spec dropdown are now clickable." },
            { module = "Blizz UI Enhanced", text = "Fixed errors when hovering certain event UI widgets and when receiving certain loot toasts, such as while fishing." },
            { module = "Localization", text = "Major catch-ups for German, Korean, Brazilian Portuguese, Simplified Chinese, and Traditional Chinese, plus Bags menus, prompts, and bank headers now translate." },
        },
    },
    {
        version = "8.8.5",
        heroes = {
            {
                module = "Mythic+ Tools",
                title  = "Targeted Spell Bars",
                desc   = "A movable group of cast bars, one for every enemy casting around you -- spell name, cast target, and timer, growing up or down with full styling control. Off by default, under the renamed Mythic+ Tools module.",
                nav    = { module = "EllesmereUIMythicTimer", page = "Targeted Spell Bars", section = "TARGETED SPELL BARS", highlight = "Enable Targeted Spell Bars" },
            },
            {
                module = "Mythic+ Tools",
                title  = "Target & Focus Cast Bars",
                desc   = "Standalone cast bars for your target and focus with the nameplates' full interrupt treatment -- kick-ready coloring, uninterruptible shield, and kick timing hints. Off by default.",
                nav    = { module = "EllesmereUIMythicTimer", page = "Target/Focus Bars", section = "TARGET CAST BAR", highlight = "Enable Target Cast Bar" },
            },
        },
        features = {
            {
                module = "Damage Meters",
                title  = "Lock Position & Disable Click",
                desc   = "Freeze the standalone combat timer in place",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "STANDALONE COMBAT TIMER", highlight = "Lock Position & Disable Click" },
            },
            {
                module = "General",
                title  = "New Visibility Options",
                desc   = "Only Show when Mounted and Only Show in Housing",
            },
            {
                module = "Minimap",
                title  = "Auto Zoom Reset",
                desc   = "Snap back to max zoom after a chosen delay",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "DISPLAY", highlight = "Reset Zoom" },
            },
            {
                module = "Nameplates",
                title  = "Out of Range Opacity",
                desc   = "Fade enemy plates beyond your attack range",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "EXTRAS", highlight = "Range Check" },
            },
            {
                module = "Nameplates",
                title  = "Hide Enemy Nameplates out of Combat",
                desc   = "Plates return the instant combat starts",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "EXTRAS", highlight = "Hide Enemy Nameplates out of Combat" },
            },
            {
                module = "QoL",
                title  = "FPS & Latency in Secondary Stats",
                desc   = "Attach the readout as rows in the stats block",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "EXTRAS", highlight = "Show FPS Counter" },
            },
            {
                module = "Unit Frames",
                title  = "Centered Aura Growth",
                desc   = "Player Aura Bars grow from the center, spacing can go negative",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars", section = "DISPLAY", highlight = "Spacing" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Charge Recharge Numbers now appear reliably the moment a charge starts recharging, instead of staying hidden until the next bar update." },
            { module = "Chat", text = "Clicking a player's name or channel tag in chat now lands where the name is drawn -- whisper reply-by-click works again." },
            { module = "Cooldown Manager", text = "Fixed severe FPS drops and high idle CPU on Augmentation Evokers at login and for several seconds after every combat." },
            { module = "General", text = "Aura displays across raid frames, the player frame, and Player Aura Bars no longer fill with the wrong buffs during vehicles, cinematics, or faction changes -- closing the cases the 8.8.4 fixes didn't cover." },
            { module = "General", text = "Show/Hide when Dragonriding visibility now applies in Druid Flight Form, Dracthyr Soar, and other flight forms." },
            { module = "Localization", text = "The Korean translation gained ~40 new entries." },
            { module = "Localization", text = "Brazilian Portuguese now covers Unlock Mode, Conditional Overrides, Quickdraw, and more, with terminology fixes." },
            { module = "Localization", text = "Traditional Chinese gained 328 new entries across Quickdraw, Healer Mana, Player Aura Bars, and more." },
            { module = "Localization", text = "Simplified Chinese caught up with ~400 new entries and terminology aligned with the CN client." },
            { module = "Nameplates", text = "Enemy nameplates are class-colored again in rated PvP and battlegrounds." },
            { module = "QoL", text = "Secondary Stats keep live values during combat and in instances instead of showing \"?\"." },
            { module = "QoL", text = "Fixed the remaining Skull Bash false alert and frozen Movement Alert countdown in Mythic+ and other content where cooldown data is secret." },
            { module = "Quickdraw", text = "Toys dragged in from the Toy Box are no longer dimmed as unusable, including previously saved ones." },
            { module = "Raid Frames", text = "The Buff Manager's Duration Swipe and Hide Icons settings now stick instead of being undone by aura updates." },
            { module = "Raid Frames", text = "The Healer Mana Display no longer keeps showing the previous group's content after leaving a raid." },
            { module = "Raid Frames", text = "Dispel color overlays no longer cover absorb shields, on raid frames and the player frame alike." },
            { module = "Resource Bars", text = "Sweeping Strikes pip displays now show all 18 charges instead of capping the readout at 12." },
            { module = "Resource Bars", text = "Ebon Might bar borders respect Border Size and Color again." },
            { module = "Resource Bars", text = "Hidden resource bars no longer reappear empty after item upgrades or max-health changes." },
            { module = "Unit Frames", text = "Right-Click to Cancel on player buffs works again after toggling the option or switching profiles." },
        },
    },
    {
        version = "8.8.4",
        -- No hero tier this patch (same shape as 8.7.7): features present,
        -- so the tiers render normally and this is not a mini patch.
        features = {
            {
                module = "Cooldown Manager",
                title  = "Show Charge/Stack Text",
                desc   = "Hide the stack counters on buff bars, per bar or per spell",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "ICON DISPLAY", highlight = "Charge/Stack Size" },
            },
            {
                module = "Quickdraw",
                title  = "Toggle Menu Open",
                desc   = "Keep a menu up and choose with a Select Key",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Quickdraw",
                title  = "Dynamic Rez Entry",
                desc   = "One entry casts the right resurrection for the moment",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Quickdraw",
                title  = "World Marker Toggling",
                desc   = "Entries pick their marker back up, with placed-marker pips",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Unit Frames",
                title  = "Standalone Weapon Enchants",
                desc   = "A Buffs bar filter shows oils and imbues on their own",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
        },
        fixes = {
            { module = "Bags", text = "Season 1 currencies that Blizzard delisted can now be untracked; they list under a new Retired group at the top of Enabled Currencies." },
            { module = "Blizz UI Enhanced", text = "The character sheet's Crests section now tracks the Season 2 Mistcrests." },
            { module = "Chat", text = "Chinese and Korean text now renders instead of showing empty boxes, sized to match your chat font." },
            { module = "Cooldown Manager", text = "Aura-tracking icons like Touch of the Magi no longer go blank for the rest of a long cooldown." },
            { module = "Cooldown Manager", text = "Tracking Bars with stacks disabled no longer show stack text whenever another bar has it enabled." },
            { module = "Localization", text = "Korean clients no longer lose the first letter of class names in spec override labels." },
            { module = "Localization", text = "Quickdraw is now fully translatable, and the Korean translation gained around 300 new entries." },
            { module = "Nameplates", text = "Tracked debuffs now show only your own applications by default; a MINE tag on each included spell lets it show from any caster instead." },
            { module = "Nameplates", text = "The preview eyeball for Raid Marker and Rare/Quest Indicator selections now sits beside its cog instead of floating off to the left." },
            { module = "QoL", text = "Secondary Stats no longer stick at \"?\" after loading in; values recover as soon as the game allows reading them." },
            { module = "QoL", text = "The Upgrade Calculator now counts Season 2 Mistcrests." },
            { module = "Quickdraw", text = "Macros with modifier conditions now respond to modifiers pressed during a hold." },
            { module = "Quickdraw", text = "Fixed a menu bound to a modified key also opening on the bare key, duplicate names after deleting a menu, and an error from nested world marker entries." },
            { module = "Raid Frames", text = "Debuff Manager Icon Effects tiles now render instead of erroring on every application." },
            { module = "Raid Frames", text = "Entering a vehicle no longer fills your own frame's aura displays with random buffs; filtered displays hide while boarded and return on exit." },
            { module = "Raid Frames", text = "The Healer Mana Display's Show Names in Raid and Class Colored Names toggles can be turned back on after being turned off." },
            { module = "Resource Bars", text = "Arms Warrior Sweeping Strikes now tracks 12.1's rules: Sweeping Strike adds 12 charges, Broad Strokes adds 6, capped at 18, and Rend consumes charges." },
            { module = "Resource Bars", text = "Rune recharge on vertical bars now fills vertically, and threshold hash lines on vertical bars sit at the correct height." },
            { module = "Resource Bars", text = "Opening the options on a Beast Mastery or Marksmanship Hunter no longer errors." },
            { module = "Unit Frames", text = "3D portraits no longer disappear after zone changes." },
            { module = "Unit Frames", text = "Custom Player Aura Bars no longer fill with default buffs after an addon-skipped cinematic." },
        },
    },
    {
        version = "8.8.3",
        -- No hero tier this patch (same shape as 8.7.7): features present,
        -- so the tiers render normally and this is not a mini patch.
        features = {
            {
                module = "Cooldown Manager",
                title  = "Always Show Cooldown Edge",
                desc   = "The rotating edge on every cooldown, per bar",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "EXTRAS", highlight = "Always Show Cooldown Edge" },
            },
            {
                module = "Quickdraw",
                title  = "Hide Unusable Entries",
                desc   = "One shared menu fits every class",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Resource Bars",
                title  = "Darken Partially Filled Resources",
                desc   = "Toggle the dimmed look of partial Soul Shards and Essence",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR", highlight = "Fill Color" },
            },
            {
                module = "Unit Frames",
                title  = "Show Weapon Enchants",
                desc   = "Weapon oils and imbues on the Player Aura Bars Buffs bar",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                module = "Unit Frames",
                title  = "Show S for Seconds",
                desc   = "Keep the \"s\" unit on sub-minute aura durations",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Dragonriding abilities with vigor left no longer grey out during the global cooldown under Desaturate on Cooldown." },
            { module = "Action Bars", text = "Custom keybind text colors no longer revert to white when hovering a button." },
            { module = "Blizz UI Enhanced", text = "Fixed a secret-value error from loot toast styling when certain other addons' frames are present." },
            { module = "Chat", text = "The main chat window can now be dragged and arrow-nudged fully into every screen corner in Unlock Mode." },
            { module = "Chat", text = "Undocking and dragging chat tabs works again, working around a 12.1 bug that crashed and hid the window." },
            { module = "Chat", text = "The main chat window keeps its resized size and position through /reload and login, and no longer snaps back on first hover." },
            { module = "Cooldown Manager", text = "The recharge edge on charge spells now shows a crisper, brighter edge style on all CDM bars." },
            { module = "Data Bars", text = "The Experience bar now hides at the level cap instead of showing \"0% to level 91\", matching the Action Bars XP bar." },
            { module = "General", text = "Opening the options for the first time via a slash command no longer errors with \"script ran too long\"." },
            { module = "General", text = "Spell IDs on aura tooltips now work at login without re-toggling the option." },
            { module = "General", text = "idTip added to the incompatible addons warning." },
            { module = "Localization", text = "Brazilian Portuguese translation completed, aligned with the ptBR game client." },
            { module = "Nameplates", text = "Quest progress text on nameplates now shows the real percent for progress-style quests instead of 0/1." },
            { module = "QoL", text = "Secondary Stats returned to the classic single-line layout; the new color options (Multicolored, Class Color, Custom, Colored Percentages) remain." },
            { module = "QoL", text = "Secondary Stats labels no longer turn invisible after login, and the display keeps updating after a /reload inside instanced content." },
            { module = "Quickdraw", text = "Menu entries for another class's specializations now show their real icon and name in the editor instead of a question mark." },
            { module = "Raid Frames", text = "Buffs, health bar colors, and dispel icons no longer vanish for party and raid members who are out of range; they now dim with the frame instead." },
            { module = "Resource Bars", text = "Fixed the Dragonriding HUD's doubled border lines at zero spacing, drifting pip dividers between the two charge rows, and the speed text hiding behind the pips." },
            { module = "Unit Frames", text = "Player Aura Bars now render the full Icons Per Row count instead of one fewer." },
            { module = "Unit Frames", text = "Custom Player Aura Bars no longer start showing every buff after a reload or cinematic." },
            { module = "Unit Frames", text = "Entering or leaving a vehicle no longer loses the player frame portrait." },
            { module = "Unit Frames", text = "The player cast bar's Spell Target no longer shows the previous cast's target during channeled spells." },
            { module = "Unit Frames", text = "Target and focus cast bars show the Uninterruptible Cast color tint again." },
        },
    },
    {
        version = "8.8",
        heroes = {
            {
                -- Full-width launch-video banner (videoBanner = true,
                -- MakeVideoBannerCard). URL comes from the shared
                -- EllesmereUI.MIDNIGHT_VIDEO_URL (EllesmereUI_VideoGuides.lua).
                videoBanner = true,
                eyebrow = "12.1 LAUNCH",
                title   = "Everything New in 12.1",
                desc    = "One video walks you through the most important changes in 12.1 and how to get the most out of EllesmereUI under them. Copy the link and give it a watch before you dive in.",
            },
            {
                module = "Quickdraw",
                title  = "Fast Action Menus",
                desc   = "Hold a keybind to open a menu of actions; point or scroll to choose, release to fire. Build up to 16 menus in Arc, Fan, or Grid layouts, nest menus inside menus, and tune every setting per menu.",
                nav    = { module = "EllesmereUIQuickdraw", page = "Quickdraw" },
            },
            {
                module = "Chat",
                title  = "Engine Rewrite + Upgrades",
                desc   = "Chat's internal engine has been rewritten to be significantly more customizable and stable. Move the main window in Unlock Mode, resize it with a drag grip, and enjoy new options including Shortened Channel Names, Class Colored Names in message text, and Chat History.",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "EXTRAS", highlight = "Shortened Channel Names" },
            },
            {
                module = "Unit Frames",
                title  = "Player Aura Bars",
                desc   = "Player buffs and debuffs now have a full manager: build custom bars showing exactly the auras you want, powered by the same filter editor as the Raid Frames managers. Add per-filter icon effects like glows, borders and sizing.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Player Aura Bars" },
            },
            {
                module = "Raid Frames",
                title  = "Custom Aura Filtering",
                desc   = "The Buff Manager and Debuff Manager have been rebuilt with significant customizability upgrades: build your own buff spell lists, assign them to any indicator, and tune them per spec. Drag buffs into your own display order, and show different debuff types in different ways.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager" },
            },
            {
                module = "Buff Reminders",
                title  = "Major Functionality Upgrades",
                desc   = "Track buffs you're missing from others, see how many allies are missing your raid buff, and choose exactly what content each reminder shows up in. Consumables gain count text, and every reminder section can now have audio cues.",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables" },
            },
            {
                module = "Damage Meters",
                title  = "In-Combat Dmg Breakdown + Deaths",
                desc   = "Your own damage breakdown, as well as all player death recaps can now be viewed during combat in raids and Mythic+ keys, instead of waiting for the fight to end.",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Hide Blizzard's Vehicle Bar",
                desc   = "Hide the stock vehicle bar, micro menu stays",
                nav    = { module = "EllesmereUIActionBars", page = "Menu, Bags & XP Bars", section = "VEHICLE BAR", highlight = "Hide Blizzard's Vehicle Bar" },
            },
            {
                module = "Action Bars",
                title  = "Show When Spellbook Is Open",
                desc   = "Reveal bars while the spellbook is open",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY" },
            },
            {
                module = "Cooldown Manager",
                title  = "Show Item Quality",
                desc   = "Crafted rank pips on tracked items",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "ICON DISPLAY", highlight = "Charge/Stack Size" },
            },
            {
                module = "Cooldown Manager",
                title  = "New Per-Spell Settings",
                desc   = "Suppress GCD and Hide Charge Text per spell",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Cooldown Manager",
                title  = "Show When Missing",
                desc   = "Show a buff's icon only while it is missing",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
            {
                module = "Damage Meters",
                title  = "Standalone Timer Strata",
                desc   = "Frame Strata for the combat timer",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "STANDALONE COMBAT TIMER", highlight = "Standalone Combat Timer" },
            },
            {
                module = "General",
                title  = "EUI Legends",
                desc   = "Meet the team and top supporters",
                nav    = { module = "_EUIPatchNotes", page = "EUI Legends" },
            },
            {
                module = "Nameplates",
                title  = "Out of Combat Recolor",
                desc   = "Recolor out-of-combat enemies instead of dimming",
                nav    = { module = "EllesmereUINameplates", page = "Colors", section = "ENEMY COLORS", highlight = "Darken Enemies Out of Combat" },
            },
            {
                module = "Nameplates",
                title  = "Near Aggro Glow",
                desc   = "Warning glow while close to pulling aggro",
                nav    = { module = "EllesmereUINameplates", page = "Colors", section = "THREAT COLORS (INSTANCES ONLY)", highlight = "Non-Tank Threat" },
            },
            {
                module = "Nameplates",
                title  = "Core Text Strata",
                desc   = "Layer each text slot independently",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE TEXT POSITIONS" },
            },
            {
                module = "QoL",
                title  = "Secondary Stats Redesign",
                desc   = "New label and value color options",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "EXTRAS", highlight = "Secondary Stat Display" },
            },
            {
                module = "Raid Frames",
                title  = "Healer Mana Display",
                desc   = "Mana text for every healer in the group",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "EXTRAS", highlight = "Healer Mana Display" },
            },
            {
                module = "Raid Frames",
                title  = "Custom Raid Size Thresholds",
                desc   = "Pick when each layout tier kicks in",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "FRAME SIZES" },
            },
            {
                module = "Raid Frames",
                title  = "Role Icons Behind Border",
                desc   = "Tuck role icons under the frame border",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "INDICATORS", highlight = "Role Icons" },
            },
            {
                module = "Raid Frames",
                title  = "Exclude Myself from Extra Frames",
                desc   = "Hide your own frame from Show Tanks",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "EXTRA FRAMES" },
            },
            {
                module = "Resource Bars",
                title  = "Pip Borders",
                desc   = "Border each resource pip individually",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR", highlight = "Border Style" },
            },
            {
                module = "Resource Bars",
                title  = "Spec Override Anchors",
                desc   = "Per-spec element anchoring in Unlock Mode",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars" },
            },
            {
                module = "Unit & Raid Frames",
                title  = "New Absorb Placements",
                desc   = "Overlay Reverse absorbs, From Left overshields",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "ABSORBS", highlight = "Absorb Style" },
            },
            {
                module = "Unit Frames",
                title  = "Per-Frame Strata",
                desc   = "Frame Strata per frame, plus Boss Frames",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "DISPLAY", highlight = "Frame Strata" },
            },
            {
                module = "Unit Frames",
                title  = "Boss Spell Target Offsets",
                desc   = "Move the boss cast target text",
                nav    = { module = "EllesmereUIUnitFrames", page = "Boss Frames" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "The pushed and held glow now recognizes keybinds ending in the minus key, including modifier combos." },
            { module = "Action Bars", text = "Buttons no longer go unclickable after changing stance or page in combat with Always Show Buttons off; bars 2-10 no longer leave those slots invisible for the rest of the fight, and combat spell-drag targets survive a form swap." },
            { module = "Action Bars", text = "Spell flyouts like Call Pet open from their keybind again." },
            { module = "Action Bars", text = "Empowered spells keep Hold and Release on keybinds after a spec change, and on login with Press and Hold Casting off." },
            { module = "Action Bars", text = "Charge and item counts no longer freeze at a stale number during raids and Mythic+ keys." },
            { module = "Bags", text = "Merge Duplicates no longer inflates stack counts on the raw bag grids (Main Bags, reagents, Recent)." },
            { module = "Blizz UI Enhanced", text = "The equipment tab's Save link dims while the selected gear set is already equipped." },
            { module = "Cooldown Manager", text = "Mirror Key Presses now follows custom icon shapes, and border style uses the shape's own outline." },
            { module = "Cooldown Manager", text = "Hosted buffs (DoTs on cooldown bars) now apply their per-spell settings like Reverse Swipe, and their Threshold rows no longer lock up after a bar-wide apply." },
            { module = "Cooldown Manager", text = "Sacred Weapon and Holy Bulwark show their recharge countdown at login instead of after the first cast." },
            { module = "Cooldown Manager", text = "Hide Active State no longer greys an ability that still has a charge banked inside dungeons and raids, and now works for override charge spells like Blink and Shimmer." },
            { module = "Cooldown Manager", text = "A potion rank added by hand via Custom Item ID tracks only that exact rank." },
            { module = "Cooldown Manager", text = "Custom buff spell IDs are now tracked as live auras and no longer ask for a manual duration." },
            { module = "Cooldown Manager", text = "Combat potions from Blizzard's Cooldown Viewer now appear on bars with Blizzard's own icon instead of failing to show." },
            { module = "Data Bars", text = "The spec switcher's loadout flyout opens level with the hovered spec row, so the cursor can reach it without the list closing." },
            { module = "Data Bars", text = "Bar thickness sliders now go up to 3000." },
            { module = "Friends List", text = "The new 12.1 Social UI friend cards get EllesmereUI styling: online-status gradients and class-color accents. The classic friends list keeps its full skin." },
            { module = "General", text = "Non-English clients now see translated disabled-widget tooltips everywhere." },
            { module = "General", text = "Fixed the 8.7.8 regression where SharedMedia combat text and unit name fonts could stop applying, mainly on macOS and Linux." },
            { module = "Nameplates", text = "Aura text offsets and the shared position offset sliders now travel much further." },
            { module = "QoL", text = "Movement Alert's countdown no longer shows 0.0 in combat; text and bar modes show a real countdown even while the cooldown is hidden by the game." },
            { module = "QoL", text = "Movement Alert no longer fires when a sibling ability's shared lockout briefly cools the tracked spell down, like Skull Bash locking Wild Charge." },
            { module = "Raid Frames", text = "The dispel type icon now draws above the debuff icons on its corner." },
            { module = "Raid Frames", text = "Custom raid size X and Y offsets now reach +-1000." },
            { module = "Raid Frames", text = "New Fill Color mode Class Color Reactive: class color at full health, blending toward your low-health colors as health drops." },
            { module = "Raid Frames", text = "The raid preview now shows a fixed roster of EUI legends." },
            { module = "Resource Bars", text = "The primary resource text no longer briefly shows a negative number while the bar reads empty." },
            { module = "Resource Bars", text = "The GCD bar's Only Instant Casts no longer fills on hard casts and channels under latency." },
            { module = "Resource Bars", text = "The cast bar no longer stays plain white for the rest of the session after an empowered cast." },
            { module = "Resource Bars", text = "A recharging rune's background stays visible when Fill Opacity is below 100." },
            { module = "Unit & Raid Frames", text = "Absorb texture dropdowns gained Striped Thick and Striped Thick Reversed styles." },
            { module = "Unit Frames", text = "Middle and thumb click-casting (Blizzard's built-in or Clique) now works on unit frames when EUI's own click-cast engine is off. Note: middle and thumb keybinds no longer fire while hovering a unit frame." },
            { module = "Unit Frames", text = "2D portraits no longer come back blank after a loading screen, including Target of Target and Focus Target." },
            { module = "Unit Frames", text = "Boss and mini frame text sizes now apply in the options preview." },
            { module = "Unit Frames", text = "Left and right anchored aura rows now center on the frame correctly and their icons sit pixel-perfect inside their borders." },
            { module = "Unit Frames", text = "Apply All Settings now copies FROM the frame you pick onto the frame you are editing; a one-time confirmation explains the direction change." },
        },
    },
    {
        version = "8.7.8",
        heroes = {
            {
                -- Input-behavior fix: nothing to open, renders static.
                module = "Action Bars",
                title  = "Empowered Casting Fixed",
                desc   = "Evoker empowered spells no longer release at Rank 1 when queued or when the key is pressed an extra time, and Hold and Release input no longer flips to Press and Tap mid-fight. Empowered keybinds now behave exactly like the default UI.",
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title  = "Fill Up",
                desc   = "Cooldown Tracking Bars can fill as they recover instead of draining",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "BAR LAYOUT", highlight = "Fill Up" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Hero-talent spells like Black Arrow no longer revert to their base spell's icon after entering or leaving an instance." },
            { module = "Action Bars", text = "Shift-clicking an action button works again: [mod:shift] macro branches cast on the click's release, matching the default UI." },
            { module = "Action Bars", text = "Alpha when on CD and Desaturate on Cooldown no longer randomly dim buttons that are ready while you cast." },
            { module = "Action Bars", text = "Cooldown swipes, desaturation, and on-CD alpha now survive a /reload taken during combat." },
            { module = "Bags", text = "Tracked currencies are now saved per character: picking currencies on one character no longer changes every other character's bag." },
            { module = "Blizz UI Enhanced", text = "Tooltip anchor settings (fixed position, cursor anchor, growth) now also apply to addon tooltips that ask to be treated like the game tooltip." },
            { module = "Cooldown Manager", text = "Keybind text on icons no longer disappears or jumps when your action bar pages for stealth, druid forms, or skyriding, or when a conditional macro switches branches; the key only changes when you move the ability or rebind it (toggle in Show Keybind's gear icon)." },
            { module = "Cooldown Manager", text = "A buff claimed by a custom buff group no longer shows up as a phantom copy in the default buff group's editor." },
            { module = "Cooldown Manager", text = "A charge spell's recharge swipe no longer goes blank for its last second when another ability is pressed with Suppress GCD on." },
            { module = "Cooldown Manager", text = "The charge count no longer hides itself in combat when a charge comes back with Hide at 0 Stacks enabled." },
            { module = "Cooldown Manager", text = "Spells with talent override forms like Shimmer no longer lose their recharge swipe under Suppress GCD." },
            { module = "Cooldown Manager", text = "The Tracking Bars preview now updates immediately when changing Height, Width, Grow Direction, or Bar Spacing." },
            { module = "Cooldown Manager", text = "Bar Strata now sits next to Stacks Text on the Tracking Bars page." },
            { module = "Damage Meters", text = "Fixed duplicate frozen ghost meter windows after login; closing a ghost could also delete the real window." },
            { module = "General", text = "Combat Text Font now applies for SharedMedia fonts after the relog, survives the font pack being disabled, and reverts safely if it is uninstalled." },
            { module = "General", text = "Updated Simplified Chinese translations and fixed the character sheet Mount tooltip label on zhCN clients." },
            { module = "Nameplates", text = "Fixed double nameplates when a friendly or neutral NPC turns hostile." },
            { module = "QoL", text = "The Frame Shifter can now move and zoom Blizzard's Combined Bags window." },
            { module = "Quest Tracker", text = "The Quest Item Hotkey now actually uses the quest item: it works with cast on key down, multi-modifier keys bind correctly, and the key frees up when no quest item exists." },
            { module = "Raid Frames", text = "Party frame settings no longer leak into the shared raid settings: Dispels, Threat Borders, and ready check sizing save their own party values, and editing an unsynced party setting can no longer permanently overwrite a raid value." },
            { module = "Resource Bars", text = "Custom Class Resource fill colors on a Spec Override now always re-apply after opening and closing the settings window." },
            { module = "Resource Bars", text = "Disintegrate's castbar hash lines now match the real damage cadence and follow chained recasts." },
            { module = "Resource Bars", text = "Castbar hash lines and empowered stage markers now render pixel perfect at every UI scale." },
        },
    },
    {
        version = "8.7.7",
        -- No hero tier this patch (same shape as 8.7.6): features present,
        -- so the tiers render normally and this is not a mini patch.
        features = {
            {
                module = "Cooldown Manager",
                title  = "Tracking Bar Text Colors",
                desc   = "Customize the name, duration, and stacks text colors per bar",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "BAR LAYOUT", highlight = "Name Text" },
            },
            {
                -- Non-clickable: the search box is chrome, not a settings row.
                module = "General",
                title  = "Complete Settings Search",
                desc   = "Search finds every setting without visiting its page first",
            },
            {
                module = "Minimap",
                title  = "Addon Compartment Button",
                desc   = "Show the addon compartment on the minimap, with corner, offset, and scale controls",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "BLIZZARD ELEMENTS", highlight = "Show Addon Compartment" },
            },
            {
                module = "Unit Frames",
                title  = "Player Castbar Spell Target",
                desc   = "Show who you are casting on, via the Spell Target dropdown",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "CAST BAR", highlight = "Spell Target",
                           preSelect = function() EllesmereUI._setUnitFrameUnit("player"); EllesmereUI._pendingUnitSelect = "player" end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Manual paging now works while skyriding: pages 2-6 show and fire on a dragonriding mount, and the Next/Previous Page keybinds work in forms." },
            { module = "Action Bars", text = "The Toggle Action Bar keybind (renamed from Toggle Action Bar Visibility) now fully pauses a hidden bar's background work; your keybinds still cast." },
            { module = "Action Bars", text = "Empty slots only light up during a drag that can actually place the spell." },
            { module = "Bags", text = "Custom categories no longer vanish on reload in the standalone bags addon." },
            { module = "Bags", text = "Fixed a red error printing at login from the Bags options." },
            { module = "Blizz UI Enhanced", text = "Fixed the paragon and renown reputation tooltips." },
            { module = "Cooldown Manager", text = "Keybind text and the press flash now work for spells on Action Bars 9 and 10, empower spells, and custom-paged bars." },
            { module = "Cooldown Manager", text = "Fixed icons that could vanish or stick after PvP and zone transitions, and newly added spells no longer jump to the front of bars." },
            { module = "Damage Meters", text = "Spec icons no longer swap between players of the same class when their ranks trade places." },
            { module = "Damage Meters", text = "Windows no longer glitch or jump while being resized on imported profiles." },
            { module = "Damage Meters", text = "The lock and grip buttons no longer hide behind the window." },
            { module = "Localization", text = "Expanded German, Korean, and Traditional Chinese translations, and more of the UI is now translatable." },
            { module = "Minimap", text = "The mail icon now hides when Mail is unchecked in Show Blizzard Elements." },
            { module = "QoL", text = "Auto Open Containers now pauses while the bank or warbank is open, and holds capped Artisan payout containers instead of wasting the shards." },
            { module = "QoL", text = "The cursor circle now matches your Accent Color at login and follows accent changes live." },
            { module = "QoL", text = "Raid Tools hides while you have no assist in a raid, and its keybind disables with it." },
            { module = "Quest Tracker", text = "Blizzard quest icons stay contained within the tracker background, and disabled quest buttons are now visually distinct." },
            { module = "Raid Frames", text = "Aura tier offsets now apply while the container is anchored to another element." },
            { module = "Resource Bars", text = "The cast bar fill now tracks the true cast timing and visibly completes instead of dying a few percent short; a new Smooth Bar Animation toggle in Cast Bar Layout can disable the easing entirely." },
            { module = "Resource Bars", text = "The GCD bar now starts the moment you press, fills on the true global cooldown timeline, and clears instantly on finish or when a cancelled cast refunds the GCD; the Always Show cog gains a Show Fill Color When Idle option." },
            { module = "Resource Bars", text = "The cast bar latency zone now shows on top of the fill during channels instead of being hidden under it." },
            { module = "Unit Frames", text = "Mouseover macros on mouse buttons (middle and thumb) now fire while hovering a unit frame." },
            { module = "Unit Frames", text = "Spec Overrides, profile switches, and imports now apply the Class Resource style at login without needing a spec swap." },
            { module = "Unit Frames", text = "Fixed combat errors from the castbar tint in instanced content." },
            { module = "Unit Frames", text = "Cast bar Spell Name, Spell Target, and Duration X and Y offsets now move the live player cast bar immediately instead of only after a reload." },
            { module = "Unlock Mode", text = "Exit Without Saving now reverts a moved fallback anchor." },
        },
    },
    {
        version = "8.7.6",
        -- No hero tier: features present, so not a mini patch; tiers render normally.
        features = {
            {
                -- Lives in the Show Sort Icon row's cog popup; cog rows have no highlightable label, so anchor on the owning row.
                module = "Bags",
                title  = "Sort to Bottom",
                desc   = "Pack items into the last slots",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "EXTRAS", highlight = "Show Sort Icon" },
            },
            {
                -- Page-only nav: the GOLD block section header uses a localized label, which nav section matching cannot target.
                module = "Data Bars",
                title  = "Gold Tooltip Rebuilt",
                desc   = "Top 10 characters, Warbank row, section toggles",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Nameplates",
                title  = "Standalone Level Text",
                desc   = "Show level and name together",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE TEXT POSITIONS", highlight = "Top Text" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Fixed empty action bar slots staying visible for players who have Blizzard's Always Show Action Bars setting turned on." },
            { module = "Action Bars", text = "Fixed form and stance paging not applying correctly when the paging dropdown was set to Default, which could leave the wrong page showing after shifting forms." },
            { module = "Action Bars", text = "Fixed occasional casts where the cooldown swipe never appeared, and abilities that stayed dimmed after they were already back up." },
            { module = "Blizz UI Enhanced", text = "Fixed loot and alert toast icons that use a mask shape, such as mount and profession recipe alerts, erroring instead of skinning." },
            { module = "Blizz UI Enhanced", text = "Fixed the selected tab underline in the Settings window and Talents tab staying on the old tab after reopening or switching with a keybind." },
            { module = "Blizz UI Enhanced", text = "Fixed the Delves companion window border overlapping Brann's portrait and its close button sitting in the wrong spot." },
            { module = "Blizz UI Enhanced", text = "Fixed an error when mousing over a mounted player in combat. The mount name line is now skipped while you are in combat, and for the duration of a Mythic+ key or rated PvP match." },
            { module = "Chat", text = "Fixed errors when whispering and when using items in the chat tab right-click menu. The Font Size list in that Blizzard menu is back to Blizzard's own sizes; EllesmereUI's own chat font size setting still covers the full range." },
            { module = "Chat", text = "Moving and resizing the chat window in Edit Mode now works." },
            { module = "Chat", text = "Whisper tab labels now line up evenly with the rest of the tab row." },
            { module = "Cooldown Manager", text = "Fixed the Resource Aware ready glow getting stuck off after a proc glow finished on the same icon." },
            { module = "Cooldown Manager", text = "Item counts now show at 1 instead of disappearing once you are down to your last one." },
            { module = "Cooldown Manager", text = "Horizontal tracked buff bars can now be narrowed to 1 pixel wide, matching vertical bars." },
            { module = "Cooldown Manager", text = "Fixed the Focus Cast interrupt alert pinging for an interrupt you can no longer cast after a talent swap, spec change, or profile import." },
            { module = "Cooldown Manager", text = "Fixed a tracked spell occasionally disappearing from its bar after untalenting a related override spell." },
            { module = "Data Bars", text = "Fixed the vertical bar preview in options showing two add buttons, hint text spilling outside the box, and the docked preview note sitting off center." },
            { module = "Data Bars", text = "Fixed possible errors with gold session totals and the WoW Token price in Mythic+ and rated PvP." },
            { module = "General", text = "Fixed options tooltips briefly resizing as they faded out when the options window scale was set away from 100 percent." },
            { module = "Minimap", text = "Saved raid and dungeon lockouts now read their difficulty from the game itself, so newer difficulties no longer go missing from the calendar tooltip. Dungeon lockouts list when the save tracks bosses." },
            { module = "Mythic Timer", text = "The Enemy Forces label and every line of the timer preview now translate for non-English clients." },
            { module = "Nameplates", text = "The pandemic glow now starts at 10 seconds remaining on long or extended DoTs, instead of arming as early as a third of an inflated duration." },
            { module = "Nameplates", text = "Fixed friendly player plates sometimes staying hidden after leaving a Delve or follower dungeon." },
            { module = "Raid Frames", text = "Show When Solo now takes effect right away when a spec override or profile switch changes it, instead of holding the old state until a reload." },
            { module = "Raid Frames", text = "The health bar Fill Opacity slider can now be lowered all the way to 0 instead of stopping at 10." },
            { module = "Resource Bars", text = "Warrior trackers count more accurately: Whirlwind no longer misses a stack when the attack lands while moving into range, and Sweeping Strikes no longer drains for enemies beyond cleave range (it can briefly read full when partners leave melee reach)." },
            { module = "Unit Frames", text = "Boss Simple Buff and Debuff Displays now stay on one row, and Max Per Row wraps at the value you set instead of wrapping early at the frame's width." },
        },
    },
    {
        version = "8.7.5",
        heroes = {
            {
                -- Perf + swipe-latency story: nothing to open, renders static.
                module = "Action Bars",
                title  = "Performance & Instant Swipes",
                desc   = "Another deep performance pass across the action bar engine, and cooldown swipes now start the moment you press the key instead of waiting on the server, with a fix for swipes starting late while spamming a keybind.",
            },
            {
                module = "Blizz UI Enhanced",
                title  = "Loot Reskin Suite",
                desc   = "The whole loot window collection in EllesmereUI style: the loot window with quality-colored icon borders and a clean hover, the need / greed roll popups, the pending-rolls window, and loot toasts with quality strips, and a scale slider.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Auto-Paging Opt-Outs",
                desc   = "Keep Bar 1 put through forms, stances, and skyriding",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "PAGING", highlight = "Disable Form Paging" },
            },
            {
                -- Window-skin style cards are hand-built chrome with no highlightable rows: page-only nav for all four.
                module = "Blizz UI Enhanced",
                title  = "Group Invite Popup Reskin",
                desc   = "The group invite dialogs, role checks included",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
            {
                module = "Party Mode",
                title  = "Spinning Action Bars",
                desc   = "Buttons orbit their bars; speed slider in the cog",
                nav    = { module = "EllesmereUIPartyMode", page = "Party Mode", highlight = "Spinning Action Bars" },
            },
            {
                module = "Quality of Life",
                title  = "Raid Tools Grow Direction",
                desc   = "Pick which way the windows open from the icon",
                nav    = { module = "EllesmereUIQoL", page = "Raid Tools", section = "GENERAL", highlight = "Menu Grow Direction" },
            },
            {
                module = "Unit Frames",
                title  = "Elite/Rare Indicator",
                desc   = "Dragon badge on elite and rare targets",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "EXTRAS", highlight = "Elite/Rare Indicator",
                           preSelect = function()
                               if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end
                           end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Buttons no longer stay red out of range while you stand in melee" },
            { module = "Action Bars", text = "Empowered spells no longer revert to Press-and-Tap after a loading screen" },
            { module = "Action Bars", text = "Dragging a spell in combat now reveals empty slots with Always Show Buttons off" },
            { module = "Blizz UI Enhanced", text = "Great Vault now wears the shared Window Skins border and buttons" },
            { module = "Chat", text = "Tab chrome no longer draws over the maximized world map" },
            { module = "Cooldown Manager", text = "Focus Kick cast sound no longer goes silent after loading screens" },
            { module = "Localization", text = "Updated Traditional Chinese, Simplified Chinese, German, and Korean translations" },
            { module = "Quality of Life", text = "FPS optimizer now sets Spell Density to Essential as intended" },
            { module = "Raid Frames", text = "Layout no longer drifts after leaving a raid with a custom raid-size override" },
        },
    },
    {
        version = "8.7.4",
        heroes = {
            {
                -- Pure performance work: nothing to open, renders static.
                module = "Action Bars",
                title  = "Performance Upgrade",
                desc   = "Hovering with Show All on Mouseover has been significantly optimized, and bars hidden by visibility conditions now cost zero CPU while hidden. Combat event handling across range, glows, stance, and pet bars was rebuilt to do the minimum work possible.",
            },
        },
        features = {
            {
                -- The toggle lives in the Cooldown Text cog on this row.
                module = "Action Bars",
                title  = "Fit Cooldown Text to Button",
                desc   = "Optional per-bar cap so countdown text stays inside small buttons",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "TEXT", highlight = "Cooldown Text Size" },
            },
            {
                -- Toggle lives in the currency block's settings popup: page-only nav.
                module = "Data Bars",
                title  = "Currency Description Toggle",
                desc   = "Hide the long description text in the currency block's tooltip",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                -- Toggle lives in the Background row's cog; that row's label
                -- goes dynamic ("Background (Class Resource)") while split, so highlight matches only the default state.
                module = "Resource Bars",
                title  = "Unique Backgrounds Per Bar",
                desc   = "Give Health and Power bars separate background colors and opacity",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "BAR DISPLAY", highlight = "Background" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Cancelling a cast now clears the cooldown swipe immediately instead of letting the full sweep play out." },
            { module = "Action Bars", text = "Out-of-range coloring now tracks correctly across page flips and slots shared between bars." },
            { module = "Action Bars", text = "Cooldown text renders at exactly your configured size again; the 8.7.3 small-button cap is now the opt-in Fit Size to Button toggle." },
            { module = "Action Bars & Cooldown Manager", text = "Hide Count at 0 no longer hides the charge number for spells that keep a cooldown while holding charges, such as Roll, Feint, and Survival of the Fittest." },
            { module = "Damage Meters", text = "Window titles no longer truncate against hidden header icons when Hide Icons Until Hover is on." },
            { module = "Data Bars", text = "Databar tooltips now layer above other tooltips, and description text uses the tooltip's full width." },
            { module = "Localization", text = "Updated Korean (koKR) translations for the latest options." },
            { module = "Minimap", text = "The expansion landing button no longer reappears next to a replacement button from another addon." },
            { module = "PTR Auras", text = "Buff duration text no longer flashes 0 for a moment when crossing under one minute." },
            { module = "Quality of Life", text = "Auto Open Containers no longer cancels your casts, and waits for the mailbox to close before opening deliveries." },
            { module = "Quality of Life", text = "Guild repair messages now report the true payer when Auto Sell Junk runs during the same visit." },
        },
    },
    {
        version = "8.7.3",
        heroes = {
            {
                -- Vertical Fill lives in the Health Bar Texture row's cog (cog-only controls have no _labelText): highlight the owner.
                module = "Raid & Unit Frames",
                title  = "Vertical Health Bars",
                desc   = "Health bars can now fill bottom-to-top on raid, party, and every unit frame. Absorbs, heal prediction, and the bar background follow the same axis, and Reverse Fill flips the direction to top-to-bottom.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "HEALTH BAR", highlight = "Health Bar Texture" },
            },
            {
                module = "Chat",
                title  = "True Hide & Click-Through",
                desc   = "Chat at Fade Strength 100 or hidden by visibility rules is now completely gone: clicks, camera drags, and targeting pass straight through to the world, and mouseover still wakes the faded chat.",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "IDLE FADE", highlight = "Fade Strength" },
            },
        },
        features = {
            {
                module = "Chat",
                title  = "Scroll Button on Chat Panel",
                desc   = "Anchor the scroll-to-bottom arrow to the chat's corner like default UI",
                nav    = { module = "EllesmereUIChat", page = "Sidebar", section = "ICONS", highlight = "Scroll Button on Chat Panel" },
            },
            {
                -- Tab Offset X is a cog-popup row (no _labelText); highlight targets the Inner Padding X row that owns the cog.
                module = "Chat",
                title  = "Tab Offset X",
                desc   = "Shift the tab strip so corner-flush chat never clips a tab",
                nav    = { module = "EllesmereUIChat", page = "Tabs", section = "LAYOUT", highlight = "Inner Padding X" },
            },
            {
                -- Anchor choices live in the Breakdown cog: highlight the owner.
                module = "Damage Meters",
                title  = "Breakdown Anchor Positions",
                desc   = "Show the hover breakdown beside the window or centered",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "BARS", highlight = "Show Breakdown on Hover" },
            },
            {
                -- No setting to open: pure interaction change, renders static.
                module = "Damage Meters",
                title  = "Header Right-Click",
                desc   = "Right-click the window header to switch meter type",
            },
            {
                -- Show Decimal lives in the Standalone Combat Timer cog.
                module = "Damage Meters",
                title  = "Standalone Timer Decimal",
                desc   = "Optional tenths display on the standalone combat timer",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "STANDALONE COMBAT TIMER", highlight = "Standalone Combat Timer" },
            },
            {
                module = "Mythic+ Timer",
                title  = "Count / Total + Remaining",
                desc   = "New enemy forces text format, e.g. 188/240 (52 left)",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer", section = "FORCES", highlight = "Enemy Text Format" },
            },
            {
                -- Slider lives in each aura slot's cog on the Core Positions grid (custom chrome, no highlightable rows): section-only nav.
                module = "Nameplates",
                title  = "Adjust Crop",
                desc   = "Set how much cropped aura icons trim, per element",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS" },
            },
            {
                -- The toggle lives in the Texture row's cog.
                module = "Resource Bars",
                title  = "Blizzard Bar Artwork",
                desc   = "Class Resource bar can use Blizzard's default bar art",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "BAR DISPLAY", highlight = "Texture" },
            },
            {
                -- Both toggles live in the Spell ID cog on this row.
                module = "Tooltips",
                title  = "Icon ID & Item ID Toggles",
                desc   = "Turn each tooltip ID line off individually",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups", section = "BLIZZARD TOOLTIP", highlight = "Show Spell ID on Tooltip" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Cooldown countdown text now scales down on small buttons instead of overflowing them." },
            { module = "Action Bars", text = "Empowered spells no longer flip to Press and Tap behavior after mounting between pulls." },
            { module = "Chat", text = "Clicks and camera drags pass through the visible chat like the default UI." },
            { module = "Chat", text = "Hidden sidebar icons are no longer clickable and no longer show tooltips." },
            { module = "Chat", text = "Panel border no longer draws above the EllesmereUI settings window." },
            { module = "Cooldown Manager", text = "Suppress GCD now covers the final moments of a charge recharge." },
            { module = "Damage Meters", text = "Combat timer ticks smoothly every second regardless of the refresh rate." },
            { module = "Localization", text = "Updated Korean (koKR) translations for the latest options." },
            { module = "Minimap", text = "The middle-click menu is now translated on every language and uses your minimap font." },
            { module = "Quality of Life", text = "Movement Alert countdown no longer snaps to 0.0 when combat starts in instances." },
            { module = "Unit Frames", text = "Kick tracking now follows the summoned demon's interrupt for Demonology Warlocks." },
            { module = "PTR Tooltips", text = "Buff tooltips no longer show the spell ID twice when no modifier is set." },
            { module = "PTR Unit Frames", text = "No more gap under the frame when the cast bar is moved away in unlock mode." },
        },
    },
    {
        version = "8.7.2",
        mini = true,
        fixes = {
            { module = "Cooldown Manager", text = "Fixed the Edit Mode update popup reappearing on every login for a small number of players, leaving them stuck in a reload loop. It now asks once, and if the change still cannot be saved it explains how to set it manually." },
            { module = "General", text = "The options panel and its popups now scale to your display, so they are no longer around half size on 4K and 5K monitors." },
            { module = "General", text = "Fixed popups being scaled twice, which made them bigger than intended and made them grow as you lowered your UI Scale. They are now a consistent size on every display, which can look slightly smaller than before at some UI Scale settings." },
            { module = "General", text = "The first install window can no longer open larger than your screen, which could put its buttons off display with no way to close it." },
            { module = "General", text = "The options panel scale is set once on displays above 1440p to match the corrected default. Any size you pick after that is kept." },
            { module = "Nameplates", text = "Long friendly player names no longer get cut off." },
            { module = "Nameplates", text = "Player titles now show inline with the name instead of on their own line below it." },
            { module = "Nameplates", text = "The guild name now sits on its own line below the name, with its own Guild Text Color control for custom or class color." },
            { module = "Nameplates", text = "Subtitle Text Size has been removed. The guild line now follows the name's font size." },
            { module = "Resource Bars", text = "Fixed Balance Druid hash lines disappearing after shifting to cat or bear form and back, staying gone until a reload." },
            { module = "Resource Bars", text = "Shift Elements if No Power now works when the power bar is hidden by Hide Power Bar if Resource, instead of leaving a gap where the bar would have been." },
        },
    },
    {
        version = "8.7.1",
        heroes = {
            {
                module = "Nameplates",
                title  = "Title and Guild Subtitles",
                desc   = "Friendly players can now show a smaller line under their name with their title, guild, or both, in both full health bar plates and Name Only mode. Text size, a custom or class color, and the angle brackets around guild names are all configurable.",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "OTHER NAMEPLATES", highlight = "Subtitle Text" },
            },
            {
                -- BATTLE RES header comes from the shared section builder
                -- (EUI_QoL_BattleRes_Options.lua) the QoL page embeds; that file's own duplicate builder has no callers so cannot shadow this one.
                module = "Battle Res",
                title  = "Text Display Style",
                desc   = "The tracker can now be shown as a compact text line with the charge count, a separator, and the time until the next charge, instead of the Rebirth icon. Timer color, count color, text size, font, and outline each get their own settings.",
                nav    = { module = "EllesmereUIQoL", page = "QoL", section = "BATTLE RES", highlight = "Display Style" },
            },
        },
        features = {
            {
                -- Same toggle also on CDM's ICON DISPLAY; one entry covers both.
                -- preSelect REQUIRED: BuildSharedBarSettings skips ICON EFFECTS entirely when the persisted bar selection is visibility-only.
                module = "Action Bars",
                title  = "Hide Charge Count at 0",
                desc   = "Also on Cooldown Manager bars",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "ICON EFFECTS", highlight = "Hide Charge Count at 0",
                           preSelect = function()
                               if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end
                           end },
            },
            {
                module = "Bags",
                title  = "Merge Duplicate Items",
                desc   = "Turn merging off to keep slots separate",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "DISPLAY", highlight = "Merge Duplicate Items" },
            },
            {
                -- Pet is selectable only on Mini Frames (Main Frames offers
                -- player/target/focus); toggle sits in the Enable Pet Frame row's Frame Source cog, so highlight that owning row.
                module = "Unit Frames",
                title  = "Always Show Pet Frame",
                desc   = "Pet ignores your frame visibility rules",
                nav    = { module = "EllesmereUIUnitFrames", page = "Mini Frames", section = "DISPLAY", highlight = "Enable Pet Frame",
                           preSelect = function()
                               if EllesmereUI._setMiniUnit then EllesmereUI._setMiniUnit("pet") end
                           end },
            },
            {
                -- Width % sliders are cog-popup rows built with label=, which DualRow never tags into _labelText: highlight the owning row.
                module = "Unit Frames",
                title  = "Text Width %",
                desc   = "Per slot width for name and text rows",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "HEALTH BAR", highlight = "Left Text",
                           preSelect = function()
                               if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                           end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Mac Command key bindings now abbreviate correctly in hotkey text on action buttons and Cooldown Manager icons, instead of showing the raw META prefix." },
            { module = "Bags", text = "Merged stacks now split back apart automatically while the Send Mail tab, a trade, the auction house, your bank, or a guild bank is open, then re-merge once those close, so you can reach every individual slot." },
            { module = "Blizz UI Enhanced", text = "Inspecting a new player right after someone else no longer leaves the previous target's item level, enchant, and upgrade track labels on the gear slots." },
            { module = "Cooldown Manager", text = "Only Show Numbers on buff bars now follows the bar's own Cooldown Text setting and any per icon override, instead of forcing the countdown on. If you had Cooldown Text turned off on one of those bars, those icons now show only the stack count, so turn Cooldown Text back on to bring the number back." },
            { module = "Data Bars", text = "The Travel block now shows a dash and treats a hearthstone or Mythic+ teleport as still cooling when its cooldown data is unreadable in restricted combat, instead of throwing an error." },
            { module = "General", text = "Long setting labels now truncate with an ellipsis and show their full text on hover, instead of wrapping onto a second line or running under the control beside them." },
            { module = "Movement Alert", text = "Icon display mode now shows the cooldown swipe and its countdown number reliably, including in the moment right after a cast, and no longer depends on Blizzard's Cooldown Timer Text setting being on." },
            { module = "Raid Frames", text = "Buff icons created for the first time during combat no longer swallow clicks and mouseover for the rest of that fight, so click casting works through them immediately. Their aura tooltip comes back when combat ends." },
            { module = "Unit Frames", text = "Auras removed at the same moment their data updates, such as dispels, trap breaks, and fully consumed absorbs, no longer leave a stuck icon behind with no tooltip, and reapplying the same aura no longer duplicates it." },
            { module = "Unit Frames", text = "Name Length and Show Ellipsis have been replaced by a per slot Width % setting, so text is now trimmed by how much room it has rather than by a character count. Any Name Length you had set no longer applies and names show at full length until you lower Width %." },
            { module = "Unit Frames", text = "The combat indicator custom color swatch now dims and blocks clicks when it does not apply, instead of disappearing and shifting the row spacing." },
        },
    },
    {
        version = "8.7",
        mini = true,
        fixes = {
            { module = "Cooldown Manager", text = "Hide Active State now greys transformed charge spells (e.g. Judgment under Avenging Wrath) at zero charges in real combat, reading the transformed spell's own cooldown." },
            { module = "Mythic+ Timer", text = "Fixed the floating timer appearing in the wrong place at the start of each key when the timer is scaled, drifting toward the center of the screen until Unlock Mode was opened." },
            { module = "Nameplates", text = "Pandemic and dispel glows no longer cover the duration and stack text on nameplate auras." },
            { module = "Quality of Life", text = "Hide Item Transformations no longer hides the Atomically Recalibrator and Atomically Regoblinator toy effects by default." },
            { module = "Raid Frames", text = "Frames now show OFFLINE instead of DEAD when a player is both disconnected and dead." },
            { module = "Raid Frames", text = "Fixed action blocked errors when buff indicators built their icons for the first time during combat, such as on delve trash pulls." },
            { module = "Unit Frames", text = "Fixed buffs and debuffs keeping the previous target's icons when switching targets." },
        },
    },
    {
        version = "8.6.8",
        heroes = {
            {
                -- Full-width banner card (banner = true, see MakeBannerCard). Static: the speedup is automatic, nothing to open.
                banner  = true,
                eyebrow = "SUITE-WIDE OPTIMIZATION",
                title   = "The Performance Patch",
                desc    = "The entire suite has been rebuilt for speed: CPU Usage has been cut by more than 70% while idle, and over 50% during M+/Raid combat. Same look, same features, at a fraction of the cost.",
            },
        },
        fixes = {
            { module = "Action Bars", text = "The micro menu and bag bar reappear on their own after wild pet battles." },
            { module = "Action Bars", text = "Clicking an empty stretch of an action bar no longer flips the main bar to another page." },
            { module = "Action Bars", text = "Cooldown swipes repaint when a proc modifies them, and an active GCD no longer greys out charge spells." },
            { module = "Blizz UI Enhanced", text = "Context menus keep their skin after the first menu of the session." },
            { module = "Blizz UI Enhanced", text = "Submenu flyouts (Loot Specialization, Raid Markers and friends) are skinned again." },
            { module = "Blizz UI Enhanced", text = "Fixed repeating errors when hovering enemy nameplate auras inside instances." },
            { module = "Cooldown Manager", text = "Replaced tracked buffs (e.g. Wither for Hellcaller) show the castable spell's icon instead of the aura's." },
            { module = "Cooldown Manager", text = "Transforming cooldowns like Holy Armaments stay on the bar you assigned them to." },
            { module = "Cooldown Manager", text = "Custom Active States (e.g. trinket glows) work after login without opening the settings first." },
            { module = "Cooldown Manager", text = "Pandemic Glow's None option is now selectable and actually hides Blizzard's pandemic glow." },
            { module = "Cooldown Manager", text = "Suppress GCD now covers racials and user-added spells." },
            { module = "Cooldown Manager", text = "Transformed charge spells (e.g. Judgment under Avenging Wrath) grey out at zero charges with Hide Active State." },
            { module = "Cooldown Manager", text = "Bar Glows light up when the aura is gained, not only after one is removed." },
            { module = "General", text = "Typing a value into a slider's number box now updates dependent controls the same as dragging it." },
            { module = "General", text = "Many missing translations now translate on non-English clients; Traditional Chinese and Korean translations expanded (community)." },
            { module = "Quality of Life", text = "The Upgrade Calculator works on non-English clients: crest totals, missing upgrades and the queue no longer read zero." },
            { module = "Quality of Life", text = "The Raid Tools window keeps its saved position correctly when scaled." },
            { module = "Unit Frames", text = "More absorb bar position options." },
            { module = "Unit Frames", text = "With Only Dispellable by You, dwarves now get the dispel overlay for bleeds (Stoneform clears them)." },
        },
    },
    {
        version = "8.6.6",
        heroes = {
            {
                -- Umbrella card: covers pull-timer boss-mod sync, combat-safe markers, and auto-show/collapse/keybind in one card.
                module = "Quality of Life",
                title  = "Raid Tools Panel",
                desc   = "A new movable panel with ready check, role check, convert or disband, one click pull timers, and target/world markers that work in combat. Show it as one or two windows at any scale, collapse it to an icon, and open it from a keybind.",
                nav    = { module = "EllesmereUIQoL", page = "Raid Tools", section = "GENERAL", highlight = "Show Raid Tools" },
            },
        },
        features = {
            {
                module = "Chat",
                title  = "Input Field Size and Font",
                desc   = "Set the chat box height, font and size",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "INPUT FIELD", highlight = "Edit Box Height" },
            },
            {
                module = "Chat",
                title  = "Sidebar Width",
                desc   = "Size the sidebar from 30 to 100 pixels",
                nav    = { module = "EllesmereUIChat", page = "Sidebar", section = "SIDEBAR", highlight = "Sidebar Width" },
            },
            {
                module = "General",
                title  = "Name Font",
                desc   = "Own font for floating names; needs a logout",
                nav    = { module = "_EUIGlobal", page = "Fonts", section = "GLOBAL FONT", highlight = "Name Font" },
            },
            {
                -- Title omits the module word: TitleOf prefixes "Party Mode: "
                -- and the label ends in "on Party Mode" (would read twice). Row is a direct W:Dropdown, so _labelText still matches its text arg.
                module = "Party Mode",
                title  = "Activation Sound",
                desc   = "Play a chosen sound when it turns on",
                nav    = { module = "EllesmereUIPartyMode", page = "Party Mode", section = "PARTY MODE", highlight = "Play Sound on Party Mode" },
            },
            {
                -- Lives as the "Anchor to Debuffs" VALUE inside the Buff Display
                -- dropdown; highlight that row (first under the header, so nothing intercepts the match). preSelect REQUIRED: BUFFS AND DEBUFFS
                -- only builds for player/target/focus, so a last-viewed pet/boss would land on a page without the section.
                module = "Unit Frames",
                title  = "Anchor to Debuffs",
                desc   = "Buffs show as the first rows of your debuff stack",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "BUFFS AND DEBUFFS", highlight = "Buff Display",
                           preSelect = function()
                               if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                           end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Reduced CPU usage while Assisted Combat (One Button Assist) is active: a new suggested spell now updates just that button, instead of running a full pass over every button on every bar each time the rotation moves on." },
            { module = "Bags", text = "TradeSkillMaster's Banking UI now detects when you switch between your character bank and the warbank from the sidebar, instead of staying on the wrong bank type." },
            { module = "Blizz UI Enhanced", text = "Fixed right-clicking a unit and choosing Whisper sometimes opening the chat box with a broken, unreadable recipient name and spamming repeated errors." },
            { module = "Chat", text = "Fixed undocked windows creeping toward the bottom-left corner of the screen on every login or reload." },
            { module = "Chat", text = "Turning on Input on Top now grows the chat panel upward to fit the input box, instead of placing it inside the panel and shrinking the area your chat text has to work with." },
            { module = "Chat", text = "Fixed windows you create and dock permanently sometimes being sized like a temporary whisper tab, and tabs losing their custom colors after moving or resizing the frame in Blizzard's Edit Mode." },
            { module = "Chat", text = "The Tab Texture option, renamed from Tab Background Texture, now works whether or not Sync Border with Chat Panel is on, instead of staying greyed out." },
            { module = "Chat", text = "A Mouseover sidebar now only takes up panel space while it is actually showing, so with Tabs Inside Chat Panel or Align Tabs to Full Panel the panel and tab alignment resize as you move the mouse on and off it, where before that space was reserved at all times." },
            { module = "Chat", text = "Tab borders, dividers and the active underline now line up again immediately after changing Tab Spacing, instead of staying at their old positions until something else redrew the tabs." },
            { module = "Chat", text = "Tab dividers now sit in the gap between tabs rather than on the tab's own edge, and temporary whisper tabs no longer draw one." },
            { module = "Chat", text = "Tab Background Color and Tab Background Color Active are now color swatches, with their opacity moved into the cog beside each row." },
            { module = "Chat", text = "Tab fonts, the active tab font and the active tab background can now be set to Accent Color or Class Color." },
            { module = "Chat", text = "The Active Underline's third color preset is now Class Color instead of Border Color, so an underline that was set to Border Color now shows your Custom Color instead." },
            { module = "Chat", text = "Fixed another source of repeating error messages when receiving a whisper, or when a Battle.net whisper toast appeared, while the sender's name was hidden by the game such as during a Mythic+ key." },
            { module = "Cooldown Manager", text = "Fixed an inactive tracked buff's placeholder icon showing the pre-talent spell's art, such as a Hellcaller Destruction Warlock's Immolate slot that actually casts Wither. The icon's tooltip follows the same correction, and the per-icon preview in the options page shows the corrected art." },
            { module = "Cooldown Manager", text = "Turning off a bar's Pandemic Glow now clears a glow already lit on an icon straight away, instead of leaving it stuck on screen until you turned the setting back on, let the buff expire, then turned it off again." },
            { module = "Cooldown Manager", text = "Custom and preset buff icons now use the Cooldown Swipe Color you picked for them, instead of falling back to the cooldown style swipe handling meant for ability cooldowns." },
            { module = "Cooldown Manager", text = "Setting up or editing a Generic CDs/Buffs sync now tells you in chat how many specs were included and that icon order is not synced, and says when confirming with only one spec ticked cleared an existing sync instead of creating one." },
            { module = "Cooldown Manager", text = "The Health Potion preset now shows and tracks the newest health potion first, falling back to the Silvermoon potions when you have none of the new ones." },
            { module = "General", text = "Tooltips inside the EllesmereUI options panel and its popups now follow your EUI Options Panel Scale setting, instead of always showing at the default size." },
            { module = "General", text = "The Mushroom hearthstone toy is now included, so it can be picked in the Data Bars Travel block and shows in the Chat and Minimap portal flyouts." },
            { module = "General", text = "Account Wide Interface Settings no longer triggers an Incompatible Addon Detected warning on login for Quest Tracker." },
            { module = "General", text = "Added and corrected translations across German, Spanish, French, Italian, Portuguese, Russian, Korean, Simplified Chinese and Traditional Chinese." },
            { module = "Nameplates", text = "Nameplate text slots can now show a unit's level, on its own or alongside the name." },
            { module = "PTR Nameplates", text = "Fixed the Caster nameplate color on PTR, it now applies to any unit with a mana bar." },
            { module = "PTR Unit Frames", text = "Focus, focus target and target of target frames show class colors for allied players again, instead of falling back to the plain green friendly color. Those three frames use Blizzard's standard class colors, so a custom class color addon cannot recolor them." },
            { module = "Quality of Life", text = "Auto Repair now uses whatever the guild bank can contribute and charges you only the remainder, instead of charging your own gold for the whole bill any time the guild bank could not cover it in full. It also no longer refuses to repair when your own gold is short but your gold plus guild funds would cover it." },
            { module = "Resource Bars", text = "Fixed vertical Health Bar, Power Bar and Class Resource bars showing a sideways box and swapped size numbers in Unlock Mode, so dragging a handle resized the wrong axis. On all four bars, including the GCD Bar, the Height and Width Match options now grey out the slider they actually control. Horizontal bars were not affected." },
            { module = "Resource Bars", text = "Fixed the Protection Warrior Ignore Pain bar's stack count text going blank and staying blank until Blizzard's tracked buff viewer happened to reuse the same icon slot." },
            { module = "Spec Overrides", text = "Fixed a spec or conditional override captured on a custom raid size (10, 15, 25 or 30 man) silently never taking effect, and continuing to fail on later edits to that tier. New overrides now save correctly, and profiles carrying the earlier ones repair themselves with nothing for you to do." },
            { module = "Spec Overrides", text = "Fixed old profile corruption that could cause switching to a different profile while a spec-specific Unlock Mode layout was active to leave the old layout's frame positions on screen and then save them over your regular layout. Positions now resync immediately instead." },
            { module = "Unit Frames", text = "Fixed the Absorb Short health text getting stuck on a leftover 0 on target, focus, boss and pet frames after the unit changed or died. The player frame was never affected." },
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
                                onConfirm = function() ReloadUI() end,
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
                                  onConfirm = function() ReloadUI() end,
                              })
                          end
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
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
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
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

            local function LanguageReload()
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reload Required",
                    message     = "Changing the language requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText  = "Later",
                    onConfirm   = function() ReloadUI() end,
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
              getValue=function() return GetCVarBool("ActionButtonUseKeyDown") end,
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

            local dmgCogBtn = CreateFrame("Button", nil, leftRgn)
            dmgCogBtn:SetSize(26, 26)
            dmgCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = dmgCogBtn
            dmgCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            dmgCogBtn:SetAlpha(dmgOff() and 0.15 or 0.4)
            local dmgCogTex = dmgCogBtn:CreateTexture(nil, "OVERLAY")
            dmgCogTex:SetAllPoints()
            dmgCogTex:SetTexture(EllesmereUI.COGS_ICON)
            dmgCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            dmgCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(dmgOff() and 0.15 or 0.4) end)
            dmgCogBtn:SetScript("OnClick", function(self) dmgCogShow(self) end)

            local dmgCogBlock = CreateFrame("Frame", nil, dmgCogBtn)
            dmgCogBlock:SetAllPoints()
            dmgCogBlock:SetFrameLevel(dmgCogBtn:GetFrameLevel() + 10)
            dmgCogBlock:EnableMouse(true)
            dmgCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(dmgCogBtn, EllesmereUI.DisabledTooltip("Show Combat Damage Text"))
            end)
            dmgCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if dmgOff() then
                    dmgCogBtn:SetAlpha(0.15)
                    dmgCogBlock:Show()
                else
                    dmgCogBtn:SetAlpha(0.4)
                    dmgCogBlock:Hide()
                end
            end)

            dmgCogBtn:SetAlpha(dmgOff() and 0.15 or 0.4)
            if dmgOff() then dmgCogBlock:Show() else dmgCogBlock:Hide() end
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
                            "persistSignupNote", "hideBlizzardPartyFrame",
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
                            EllesmereUI.SwitchProfile(assigned)
                            -- true = budgeted: manual apply (no spec change
                            -- in flight), watchdog-sliced module refresh.
                            EllesmereUI.RefreshAllAddons(true)
                            if fontWillChange or skinsWillChange then
                                EllesmereUI:ShowConfirmPopup({
                                    title       = EllesmereUI.L("Reload Required"),
                                    message     = fontWillChange
                                        and EllesmereUI.L("Font changed. A UI reload is needed to apply the new font.")
                                        or EllesmereUI.L("Window skins changed for this profile. A UI reload is needed to apply them."),
                                    confirmText = EllesmereUI.L("Reload Now"),
                                    cancelText  = EllesmereUI.L("Later"),
                                    onConfirm   = function() ReloadUI() end,
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
                   or kkey == "LALT" or kkey == "RALT" then
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
                local mods = ""
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                local fullKey = mods .. kkey

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

            local ADDON_DB_MAP_LOCAL = EllesmereUI._ADDON_DB_MAP
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
                                EllesmereUI.SwitchProfile(capName)
                                ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                -- true = budgeted: manual swap site,
                                -- watchdog-sliced module refresh.
                                EllesmereUI.RefreshAllAddons(true)
                                if fontWillChange or skinsWillChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = EllesmereUI.L("Reload Required"),
                                        message     = fontWillChange
                                            and EllesmereUI.L("Font changed. A UI reload is needed to apply the new font.")
                                            or EllesmereUI.L("Window skins changed for this profile. A UI reload is needed to apply them."),
                                        confirmText = EllesmereUI.L("Reload Now"),
                                        cancelText  = EllesmereUI.L("Later"),
                                        onConfirm   = function() ReloadUI() end,
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
            local ADDON_DB_MAP_LOCAL = EllesmereUI._ADDON_DB_MAP
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

    -- Profiles and Patch Notes are now their own sidebar pages (registered below), so Global Settings only owns General + Fonts + Textures + Colors.
    local globalPages = { PAGE_GENERAL, PAGE_FONTS, PAGE_TEXTURES, PAGE_COLORS }

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
