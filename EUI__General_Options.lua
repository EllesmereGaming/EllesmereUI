-------------------------------------------------------------------------------
--  EUI__General_Options.lua
--  Registers the Global Settings module with EllesmereUI
--  CVar-based settings that apply to all EllesmereUI addons
--
--  Default-application policy:
--    We use C_CVar.GetCVarInfo(name) to get both the current value and
--    Blizzard's built-in default.  Our preferred defaults are only applied
--    when the CVar is still sitting at Blizzard's default -- meaning
--    neither the player nor another addon has touched it.  If the value
--    differs from the Blizzard default in any way, we leave it alone.
--    Widgets always read the live CVar value so they stay in sync
--    regardless of who set it.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL      = "General"
local PAGE_COLORS      = "Fonts & Colors"
local PAGE_PROFILES    = "Profiles"
local PAGE_WHATSNEW    = "Patch Notes"

-- Profiles and Patch Notes are their own sidebar pages (single-page modules),
-- not tabs under Global Settings. These keys match the sidebar buttons created
-- in EllesmereUI.lua.
local PROFILES_KEY     = "_EUIProfiles"
local PATCHNOTES_KEY   = "_EUIPatchNotes"

-- Standalone single-module builds rename the host addon to contain "Standalone".
-- The What's New tab is suite-only, so it is never added to the page list there.
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil

-------------------------------------------------------------------------------
--  Shared CDM spell-layout export flow
--  Used by BOTH the full-profile export and the per-addon export. Asks whether
--  to bundle the CDM spell layout (which spells sit on which bars + per-spell
--  settings); on Yes, opens the spec picker so the user chooses which specs.
--  Calls exportFn(includeCDM, cdmSpecs) with the result. An export string is
--  produced ONLY on an explicit "No" (without layout) or a completed picker
--  selection -- closing/escaping either popup produces NO export.
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
--  What's New? page -- interactive patch notes in three tiers of importance:
--    1) hero cards (two per row), 2) small clickable listings, 3) fix lines.
--  Content lives in EllesmereUI._WHATSNEW_PATCHES (newest patch first). A
--  hero/listing entry with a `nav` deep-links to the setting it changed via
--  EllesmereUI:NavigateToElementSettings (opens the page + green-pulses the
--  control); an entry with NO `nav` renders as a static, non-clickable card
--  (for automatic behavior that has no setting to open). Defined at file scope
--  (namespace function) so it adds no locals or upvalues to the deferred
--  options closure below.
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

    -- Stable sort by module display name so same-module entries group together
    -- (preserves authored order within a module).
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

    -- Tier 1: a clickable hero card -- dark fill, faint border, green top accent,
    -- title + wrapping description, uniform hover lift.
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

        -- Clickable only when the entry has a nav target. An entry with no nav
        -- (automatic behavior with no setting to open -- e.g. party frames in
        -- arena) renders as a static card: no hover lift, no click, and mouse
        -- disabled so nothing invites a click that would go nowhere.
        if entry.nav and entry.nav.module then
            card:SetScript("OnEnter", function()
                bg:SetColorTexture(0.11, 0.13, 0.15, 0.50); brd:SetColor(1, 1, 1, 0.22)
                titleFs:SetAlpha(1)
            end)
            card:SetScript("OnLeave", function()
                bg:SetColorTexture(0.06, 0.08, 0.10, 0.50); brd:SetColor(1, 1, 1, 0.12)
                titleFs:SetAlpha(0.9)
            end)
            card:SetScript("OnClick", function() GoTo(entry.nav) end)
        else
            card:EnableMouse(false)
        end
    end

    -- Tier 2: a clickable small listing -- title + subtitle, no card chrome, a
    -- faint row highlight on hover.
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

        -- Clickable only when the entry has a nav target (see MakeHeroCard); a
        -- nav-less listing renders static with no hover or click.
        if entry.nav and entry.nav.module then
            row:SetScript("OnEnter", function()
                hov:SetAlpha(1); titleFs:SetAlpha(1)
            end)
            row:SetScript("OnLeave", function()
                hov:SetAlpha(0); titleFs:SetAlpha(0.9)
            end)
            row:SetScript("OnClick", function() GoTo(entry.nav) end)
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

    -- Top-left: "New Patch Reminder Dot" opt-out for the pulsing sidebar dot
    -- that appears when the account's version increases (see the Patch Notes
    -- button in EllesmereUI.lua). Small free-form checkbox on the hint line.
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

    -- Cap the page to the newest patches (max 10). Older entries may remain in
    -- the data table but are not shown; trim them on ship to keep the file tidy.
    local MAX_PATCHES = 10
    local shown = math.min(#patches, MAX_PATCHES)
    for pi = 1, shown do
        local patch = patches[pi]
        -- A "mini" patch is a bugfix-only release: it carries just a `fixes`
        -- tier and renders in a lighter, more compact style so a small patch
        -- does not take up as much room as a full feature release.
        local isMini = patch.mini
        -- Version header. Full patches: large 20px title + neutral divider.
        -- Mini patches: compact 15px title with a green "MINI PATCH" tag and a
        -- tighter divider.
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

        -- Tier 1: hero cards, two per row. Heroes render in AUTHORED order (the
        -- order they appear in the patch's `heroes` table) -- NOT module-sorted
        -- like features/fixes -- so each patch can headline whatever matters most
        -- first. Reorder the entries in _WHATSNEW_PATCHES to reorder the cards.
        local heroes = patch.heroes or {}
        if #heroes > 0 then
            local cardW = math.floor((totalW - CARD_GAP) / 2)
            local CARD_H = 96
            local rows = math.ceil(#heroes / 2)
            for i, hero in ipairs(heroes) do
                local col = (i - 1) % 2
                local rw  = math.floor((i - 1) / 2)
                local cx  = PAD + col * (cardW + CARD_GAP)
                local cy  = y - rw * (CARD_H + CARD_GAP)
                MakeHeroCard(cx, cy, cardW, CARD_H, hero)
            end
            local consumed = rows * CARD_H + (rows - 1) * CARD_GAP
            y = y - consumed - 18
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

        -- Tier 3: bug-fix lines. Full patches label them under a "BUG FIXES"
        -- header; a mini patch is entirely fixes, so the lines render directly
        -- beneath the compact header with no redundant section label.
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
--  Patch-notes content for the What's New page (newest patch first). Each hero
--  and listing entry's `nav` deep-links to the setting it changed via
--  EllesmereUI:NavigateToElementSettings(module, page, section, preSelect, highlight).
-------------------------------------------------------------------------------
EllesmereUI._WHATSNEW_PATCHES = {
    {
        version = "8.5.1",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Stack Based Tracking Bars",
                desc   = "Buff Tracking Bars can now fill by stack count instead of remaining time: turn on Stack Based Bar, set your Max Stacks, and the bar fills as your stacks build.",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "EXTRAS", highlight = "Stack Based Bar" },
            },
            {
                module = "Raid Frames",
                title  = "Show Your Buffs on All Specs",
                desc   = "Your own tracked buffs can now show on every spec of your class: flip one toggle in Simple Setup, or use the new cog on Own Only to opt in a single Custom Buff Display indicator.",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager", section = "BUFF DISPLAY", highlight = "Show Own on All Specs" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title  = "CD Tracking Bar Charge Lines",
                desc   = "Split multi-charge bars into per-charge segments with divider lines",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "BAR LAYOUT", highlight = "Charge Hash Lines" },
            },
            {
                module = "Unit Frames",
                title  = "More Combat Indicator Positions",
                desc   = "Anchor to any health bar corner, plus a wider offset range",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "EXTRAS", highlight = "Combat Indicator",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Independent Leader Indicator",
                desc   = "Player and Target set separately, with one-click sync",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "EXTRAS", highlight = "Leader Indicator",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                    end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Macro names and profession rank icons now update immediately after moving or swapping macros or switching loadouts." },
            { module = "Blizzard Windows", text = "Fixed the character stats scrollbar getting stuck after collapsing a section, and hidden stat categories reappearing after a reload." },
            { module = "Blizzard Windows", text = "Item quality, enchant, and socket borders no longer cover crafting order and catalyst slot highlights on the character sheet." },
            { module = "Cooldown Manager", text = "Fixed keybind text missing or wrong for abilities and items cast from a macro." },
            { module = "Cooldown Manager", text = "Fixed textured icon borders showing at different thicknesses on icons in the same bar." },
            { module = "Cooldown Manager", text = "Fixed charge and stack count text offsets not scaling with icon size." },
            { module = "Cooldown Manager", text = "Fixed custom colors being discarded when using Apply to Bar on an Active State color row." },
            { module = "Cooldown Manager", text = "Fixed Diabolist buffs that share a spell ID collapsing into one icon and sharing settings." },
            { module = "Cooldown Manager", text = "Raised the Tracking Bars Max Stacks slider cap from 50 to 100." },
            { module = "Cooldown Manager", text = "Fixed charge hash lines and stack tick marks not appearing on the Tracking Bars preview until settings were edited again." },
            { module = "Cooldown Manager", text = "Fixed stack tick marks never showing unless the Stack Threshold color was also enabled; they now only require Max Stacks." },
            { module = "General", text = "Spacing sliders across the whole suite now show and step in real screen pixels, so 1 always equals exactly one pixel on your monitor at any UI scale; saved layouts are unchanged." },
            { module = "General", text = "Fixed a rare rounding issue that could shave one pixel off some element sizes at certain UI scales." },
            { module = "General", text = "Fixed the French translation failing to load entirely, with all text falling back to English." },
            { module = "General", text = "Updated Korean, French, Simplified Chinese, and Traditional Chinese translations." },
            { module = "QoL", text = "The auto repair chat message is now translatable, with a new Coin Icons option to show the cost with coin icons instead of text." },
            { module = "Quest Tracker", text = "Removed the large empty gap at the top of the tracker and stopped it briefly dropping down when clicking a quest." },
            { module = "Raid Frames", text = "The Buff Manager's Editing Spec dropdown now opens on your class's tracked spec (or Holy Paladin) instead of blank when playing an untracked spec." },
            { module = "Resource Bars", text = "Fixed the Sweeping Strikes bar dropping to zero mid-combat and in Mythic+." },
            { module = "Resource Bars", text = "Restored Unlock Mode movers for bars still using an old Anchor To setting, keeping the bar's position." },
            { module = "Resource Bars", text = "Resource text no longer flips between value and percent when combat starts; a Show % option picks the display." },
        },
    },
    {
        version = "8.4.9",
        heroes = {
            {
                module = "Data Bars",
                title  = "Smarter Tooltips",
                desc   = "New Mythic Plus teleports in the Travel tooltip can now be left-clicked to cast, and a new opt-in Character button tooltip shows your item level, primary stat, and Crit, Haste, Mastery, and Versatility.",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
        },
        features = {
            {
                module = "Blizz UI Enhanced",
                title  = "Disable Window Skins Switch",
                desc   = "Turn off all window skinning with one per profile switch",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
            {
                module = "Cooldown Manager",
                title  = "Tracking Bar Strata",
                desc   = "Choose the screen layer Tracking Bars sit on",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "BAR LAYOUT", highlight = "Bar Strata" },
            },
            {
                module = "Damage Meters",
                title  = "Unlock Mode Support",
                desc   = "Windows now move, anchor, and size match through Unlock Mode",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters" },
            },
            {
                module = "Resource Bars",
                title  = "Hide Bars per Druid Form",
                desc   = "Hide the whole Health, Power, or Class Resource bar per form",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "HEALTH BAR", highlight = "Show Health Bar" },
            },
        },
        fixes = {
            { module = "Character Sheet", text = "Fixed the diminishing returns breakdown no longer showing for Critical Strike after a Blizzard internal stat rename." },
            { module = "Chat", text = "Fixed Up and Down arrow message history recall breaking protected commands like /ping during Mythic Plus keys and boss encounters." },
            { module = "Cooldown Manager", text = "Fixed untouched spells on the base bars being left out of profile exports and then hidden for anyone importing that profile." },
            { module = "Data Bars", text = "On-cooldown Hearthstone and teleport rows now dim to gray, with the remaining cooldown shown in the tooltip instead of under the icon." },
            { module = "General", text = "Fixed the settings search box and per-spec overrides icon appearing on pages where they do not apply." },
            { module = "General", text = "Updated koKR, zhTW, and deDE translations across several option pages." },
            { module = "Mail", text = "Fixed auction house invoice and crafting order mail text showing unreadable dark brown instead of themed white." },
            { module = "Nameplates", text = "Renamed Open World Basic Coloring to Full Coloring M+ Only; when enabled, full enemy type colors now show only in 5-man dungeons." },
            { module = "Profiles & Presets", text = "Fixed profile sync (mirror groups) overwriting per-profile window positions and settings owned by a spec or conditional override." },
            { module = "Profiles & Presets", text = "Fixed unchecking Include Layout on profile export or import still letting override-group layout layers overwrite the recipient's own layouts." },
            { module = "Profiles & Presets", text = "Fixed importing a profile while viewing an override group's layout leaking that group's positions into the imported profile." },
            { module = "Profiles & Presets", text = "Profiles now include their UI scale and users will be prompted during import if their UI scale doesn't match." },
            { module = "Profiles & Presets", text = "Removed the extra Cooldown Manager spec-assignment popup during profile import; spells now import directly before the reload." },
            { module = "Quest Tracker", text = "Fixed world quest map pin errors and quest icons briefly flashing visible while Show Quest Icons is turned off." },
            { module = "Raid Frames", text = "Fixed the raid frame container staying at its previous spec's or profile's position until manually moved." },
            { module = "Raid Frames", text = "Real Preview now shows your active spec's true effective override settings, with a gold marker on the Preview Mode control when an override is being previewed." },
            { module = "Raid Frames", text = "Friendly Boss Frames now show their debuff, defensive, and Buff Manager indicator icons, which previously never appeared." },
            { module = "Resource Bars", text = "Fixed resource percent text and class resource pips failing to update during Mythic Plus combat." },
            { module = "Resource Bars", text = "Fixed leftover highlight overlays sometimes staying visible on pips after a combat-hidden value became readable again." },
            { module = "Resource Bars", text = "Fixed a hidden bar briefly reappearing when its maximum value changed mid-fight, such as from a talent swap." },
            { module = "Resource Bars", text = "Fixed the Sweeping Strikes charge indicator drifting out of sync with your real charges." },
            { module = "Spec Overrides", text = "Fixed another case of width and height matched bars reverting to a stale size, this time shared across every spec in the group." },
            { module = "Spec Overrides", text = "Fixed cooldown and action bars created after an override layout group already existed ignoring the group's saved layout." },
            { module = "Spec Overrides", text = "Fixed adding a spec to an override group copying a stale matched bar width from another member onto the new spec." },
            { module = "Spec Overrides", text = "Fixed a remaining case where opening Unlock Mode while editing an override group could corrupt shared defaults like Show Power Bar and Resource Text." },
        },
    },
    {
        version = "8.4.8",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Bar Icon Overflow",
                desc   = "Cap how many icons a Cooldown or Utility bar shows with the new Max Icons slider. Extra icons overflow onto another bar of your choice, keeping your main rotation row clean.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "BAR LAYOUT", highlight = "Max Icons (0 = Off)",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "Spec Overrides",
                title  = "Stability Hotfixes",
                desc   = "A thorough pass at hardening the override system: override values can no longer corrupt your shared defaults or bleed onto specs outside their group, and settings controlled by an applied Conditional Override now show an Override overlay.",
                nav    = { module = "_EUIProfiles", page = "Spec Overrides" },
            },
        },
        features = {
            {
                module = "Nameplates",
                title  = "Non-Target Opacity",
                desc   = "Fade every enemy nameplate except your target and focus",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Non-Target Opacity" },
            },
            {
                module = "Profiles & Presets",
                title  = "Import UI Scale Control",
                desc   = "Choose whether an imported profile applies its UI scale",
                nav    = { module = "_EUIProfiles", page = "Profiles" },
            },
            {
                module = "Profiles & Presets",
                title  = "Export Without Global Look",
                desc   = "Per-addon exports can leave fonts and colors out",
                nav    = { module = "_EUIProfiles", page = "Profiles" },
            },
            {
                module = "Raid Frames",
                title  = "Extra Frames, Up to 20",
                desc   = "Up to 20 duplicate frames with grid wrap controls",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "EXTRA FRAMES", highlight = "Position" },
            },
            {
                module = "Raid Frames",
                title  = "Icons Ignore Power Bar",
                desc   = "Align icons and text as if no power bar existed",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "POWER BAR", highlight = "Power Height" },
            },
            {
                module = "Unit Frames",
                title  = "Custom Name > Target Separator",
                desc   = "Type your own separator and color it",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "HEALTH BAR", highlight = "Left Text",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Only Dispellable by You",
                desc   = "Show the dispel overlay only for debuffs you can dispel",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "BUFFS AND DEBUFFS", highlight = "Dispel Overlay",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                    end },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Fixed icons with Desaturate on Cooldown or Alpha when on CD returning to full color too early for charge spells and items, and staying dimmed after a charge regenerated." },
            { module = "Action Bars", text = "Fixed the Show Item Rank icon not updating right away when a different rank item replaces the item in an action bar slot." },
            { module = "Bags", text = "OneBag Sort now reorganizes items in the reagent bag along with your other bags." },
            { module = "Bags", text = "Depositing into One or All Warband Bank views now stacks onto matching items in any warband tab instead of only the first tab with an empty slot." },
            { module = "Bags", text = "Rapidly transferring items no longer causes clicks to fall through onto your action bars underneath." },
            { module = "Bags", text = "Right-clicking the Miscellaneous category and choosing Rename now actually renames it." },
            { module = "Character Sheet", text = "Secondary Stats now say Critical Strike instead of Crit, matching Blizzard's naming." },
            { module = "Character Sheet", text = "The gem socket panel now reliably closes after socketing, instead of occasionally staying open and blocking clicks." },
            { module = "Cooldown Manager", text = "The Pixel Glow and Button Glow CD Ready effects on trinkets, racials, potions, and custom spells now correctly turn off while the ability is on cooldown." },
            { module = "Cooldown Manager", text = "Buff bar countdown timers now round seconds up to match Blizzard's own aura timers instead of reading one second low." },
            { module = "Cooldown Manager", text = "Bars no longer disappear after entering or leaving an arena or battleground." },
            { module = "Cooldown Manager", text = "Trinket icons no longer disappear while browsing a crafting order vendor." },
            { module = "Cooldown Manager", text = "Buff icons shown for configuration no longer stay visible on screen after closing the options window." },
            { module = "General", text = "The module on/off icon in the sidebar stays dimmed for disabled modules instead of brightening on mouseover." },
            { module = "Global Search", text = "Typing a window's name (for example Mail or Achievements) into the sidebar search now finds that window's skin card." },
            { module = "Global Search", text = "Search results keep mixed-case section labels like LFG Menu intact instead of re-capitalizing them." },
            { module = "Mail", text = "Opened mail letters now render their text in the skin font." },
            { module = "Profiles & Presets", text = "Importing a profile with custom colors now displays the imported palette right away." },
            { module = "Profiles & Presets", text = "Importing a per-addon export without fonts no longer resets your global font to the default." },
            { module = "Quality of Life", text = "Auto Open Containers no longer leaves a container stuck greyed out and unopenable when opens overlap." },
            { module = "Quest Tracker", text = "The quest item hotkey now works for quest items from quests you are not tracking." },
            { module = "Raid Frames", text = "Extra Frames in Free Move no longer shift position when the number of shown frames changes." },
            { module = "Raid Frames", text = "Fixed the raid frame block not moving to its saved per-size position when the roster crossed a size tier in combat." },
            { module = "Spec Overrides", text = "Fixed width and height matched bars randomly reverting to a stale size on spec changes and options roundtrips." },
            { module = "Spec Overrides", text = "Adding your current spec to an existing override group no longer overwrites the group's stored values with your live settings." },
            { module = "Spec Overrides", text = "Custom per-tier raid size settings can now be captured into an override group." },
            { module = "Spec Overrides", text = "Creating a new override group now drops you straight into editing it." },
            { module = "Spec Overrides", text = "When two groups share a spec, the Unlock button locks on every group except the one that owns that spec's layout, with a tooltip naming the owner." },
            { module = "Tooltips", text = "Reskinned tooltips now size themselves correctly on their first show after changing the tooltip font scale." },
            { module = "Unit Frames", text = "Boss frame names with Class Colored enabled now recolor correctly when a new boss engages or your target changes." },
            { module = "Unit Frames", text = "Switching Power Bar Position to Detached now updates the bar's border and text immediately." },
            { module = "Unlock Mode", text = "Entering Unlock Mode from the minimap button or slash command now returns you to the options panel when you exit." },
            { module = "Unlock Mode", text = "Selected elements no longer keep their info label expanded after your cursor moves away." },
            { module = "Unlock Mode", text = "Bars linked by a fallback anchor no longer drift off their pinned edge when the linked bar is a different size on another spec." },
            { module = "Unlock Mode", text = "Size edits made from the inline cog inputs are no longer reverted the next time override values apply." },
        },
    },
    {
        version = "8.4.7",
        heroes = {
            {
                title  = "Data Bars",
                desc   = "A brand new module for building your own info bars. Add widgets like the clock, FPS, gold, durability, XP/Rep bars, spec, professions, travel cooldowns, currencies and the micro menu. Create as many bars as you want, drag blocks into any order, and place them anywhere on screen.",
                nav    = { module = "EllesmereUIDataBars", page = "DataBars" },
            },
            {
                module = "Cooldown Manager",
                title  = "Cooldown Tracking Bars",
                desc   = "Tracking Bars can now follow a spell's cooldown, not just a buff. Pick a spell from the new Cooldowns list in a bar's spell picker and the bar drains as the cooldown ticks, showing remaining time and a charge count that stay accurate through cooldown reduction and resets.",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title  = "Smooth Bars",
                desc   = "Toggle fill easing on or off for buff and cooldown bars",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "BAR LAYOUT", highlight = "Smooth Bars" },
            },
            {
                module = "Inspect Sheet",
                title  = "Hide Item Text",
                desc   = "An eyeball button hides item level, upgrade and enchant text",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "INSPECT SHEET" },
            },
            {
                module = "Merchant",
                title  = "Item Level",
                desc   = "Show item level on weapons and armor a vendor sells",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins" },
            },
            {
                module = "Raid Frames",
                title  = "Combat Icon",
                desc   = "An icon marks group members who are still in combat",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "INDICATORS", highlight = "Combat Icon" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "The Pushed and Highlight border styles now draw an actual border outline instead of recoloring the whole icon." },
            { module = "Action Bars", text = "The Micro Menu and Bag Bar now hide correctly when entering a pet battle." },
            { module = "Action Bars", text = "Keybinds no longer trigger the wrong spell for Druids and Rogues when a shapeshift or stealth swap changes which ability is on a button." },
            { module = "Action Bars", text = "The extra action button (delves and other zone abilities) now shows its cooldown swipe and keybind the moment it appears, and a rare vehicle/override bar combat error is fixed." },
            { module = "Action Bars", text = "Action bar keybinds no longer override the House Editor's own hotkeys while decorating." },
            { module = "Aura & Buff Reminders", text = "Rogue poison reminders now respect the Show Consumes Below timer, warning shortly before a poison expires instead of only after." },
            { module = "Character Sheet", text = "The character and inspect sheets now share the same window border as other skinned windows, and the inspect sheet's panel and dressing-room button line up with the character sheet." },
            { module = "Character Sheet", text = "The better-item indicator no longer flags off-hands as upgrades while a two-handed weapon is equipped, and now works on non-English clients." },
            { module = "Character Sheet", text = "The character sheet now moves beside the inspect window and the Dungeons and Raids window instead of overlapping them." },
            { module = "Character Sheet", text = "Hovering an empty gem socket now glows the matching gear slot and opens the gem list so one click sockets it, and the socketing window no longer sticks after a gem is applied." },
            { module = "Cooldown Manager", text = "Moving a Tracking Bar in Unlock Mode on one spec no longer drags the same bar's anchor on your other specs." },
            { module = "Cooldown Manager", text = "Icon keybind text no longer shows the wrong key while shapeshifted, in a vehicle, or on a bonus bar page, and updates immediately instead of waiting for combat to end." },
            { module = "Cooldown Manager", text = "Transform spells (such as Rising Sun Kick becoming Rushing Wind Kick) and certain Demon Hunter sigils no longer show a stuck or missing cooldown swipe." },
            { module = "Cooldown Manager", text = "Blizzard's Assisted Combat Highlight glow now appears reliably on icons for talent-swapped or overridden spells." },
            { module = "Cooldown Manager", text = "Threshold Text's Apply to Bar and Apply to All Specs now reliably push a custom seconds value, even on a spell excluded from the bar." },
            { module = "Guild", text = "Achievement Points and Mythic+ Rating now show in the far-right stat column instead of under the Note column in the widened roster." },
            { module = "Mythic+ Timer", text = "The Blizzard Quest Tracker no longer stays visible over the timer during combat; it now hides the instant combat ends." },
            { module = "Nameplates", text = "The pandemic glow on debuff icons is no longer dimmed by the cooldown swipe animation." },
            { module = "Nameplates", text = "The target, focus, and hover health bar overlay now covers the full bar width on plates wider than 200 pixels." },
            { module = "Profiles & Presets", text = "Pasting or importing a very large profile or preset string now processes across frames with a progress percentage instead of freezing the game, with nothing cut off." },
            { module = "Profiles & Presets", text = "Importing a profile that references a bar texture you do not have now shows Texture Not Found on those bars instead of silently swapping in another texture." },
            { module = "Quality of Life", text = "Auto Open Containers now pauses at a vendor so newly bought bags are not sold or opened, and Exclude Warbound Containers now applies by default." },
            { module = "Quality of Life", text = "Fixed a Lua error from Hide Tutorial Pop-ups that could interrupt other windows such as the House Editor." },
            { module = "Quality of Life", text = "Window Shifter can now move the Quest Log, and the Achievement window can be dragged from anywhere on its body, not just the header." },
            { module = "Quality of Life", text = "Companion windows (map, professions, item upgrade and more) keep their alignment beside a moved or resized Character panel, and the Group Finder no longer redocks over other addons' panels." },
            { module = "Quest Tracker", text = "Fixed errors when clicking a tracked quest or hovering quest pins and tooltips on the map afterward." },
            { module = "Raid Frames", text = "The buff manager's simple grid gained an Own Only toggle to show only buffs you applied." },
            { module = "Raid Frames", text = "Frame and power bar borders no longer keep an old color or style on party frames after a profile or spec override swap." },
            { module = "Resource Bars", text = "Pressing an off-GCD ability like Hover during a cast or channel no longer makes the cast bar snap to full or empty for a frame." },
            { module = "Spec Overrides", text = "Tracking Bar unlock and anchor links no longer carry over from the wrong spec after a profile or spec swap." },
            { module = "Spec Overrides", text = "Importing a profile you exported yourself no longer creates duplicate Spec Override or Conditional Override groups." },
            { module = "Tooltips", text = "The tooltip peek modifier no longer fails to reveal a suppressed tooltip in combat, and suppressed tooltips no longer briefly flash under the Out of Combat modes." },
            { module = "Unit Frames", text = "The leader icon on player and target frames now shows the correct icon and also lights up for raid assistants." },
            { module = "Unit Frames", text = "Power bar text is no longer hidden behind the power bar's border in some border layouts." },
        },
    },
    {
        version = "8.4.5",
        heroes = {
            {
                module = "Profiles & Presets",
                title  = "Settings Overrides",
                desc   = "Change any setting for a group of specs (all your tanks, your healers...) or based on a condition: Dungeon, Raid, Arena, Battleground, Solo, or an out-of-combat keybind toggle. Click the class glyph next to the search bar, pick who or when, and everything you change applies only there.",
                nav    = { module = "_EUIProfiles", page = "Spec Overrides" },
            },
            {
                title  = "Modular Visibility",
                desc   = "Every Visibility dropdown is now a checklist. Combine conditions - In Combat while In a Raid, only When Dragonriding, and more - and add Mouseover to reveal on hover only while they pass. Both Dragonriding options are now available for every module.",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY", highlight = "Visibility" },
            },
            {
                title  = "PTR Ready - One Version for Both",
                desc   = "EllesmereUI now ships as a single version that runs on both live retail and the Midnight 12.1 PTR. Install once, play anywhere - the same addon loads on either client, with full support for the PTR's reworked aura system. No separate PTR build to download or keep in sync.",
            },
            {
                module = "Character Sheet",
                title  = "Socket Panel",
                desc   = "Gem sockets from your equipped gear now line the bottom of the character sheet. Click a socket to see every socketable gem in your bags with its stats, and click a gem to socket it instantly - no Blizzard socketing window needed.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "CORE OPTIONS", highlight = "Socket Panel" },
            },
            {
                module = "Unit Frames",
                title  = "Player Private Auras",
                desc   = "Boss-mechanic icons (private auras) can now show directly on your player frame. Opt-in per-slot icons with size and position controls, so you see your assignment the instant it lands - no more hunting Blizzard's floating icons mid-pull.",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "PRIVATE AURAS", highlight = "Enable Private Auras",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Cooldown Manager",
                title  = "Global Tracking Bar Groups",
                desc   = "Tracking bar groups can now be Global: build the group once and its bars, layout and position follow you across every spec, instead of rebuilding the same setup thirteen times.",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title  = "Icon Order",
                desc   = "Start buttons from any corner, or reverse the order",
                nav    = { module = "EllesmereUIActionBars", page = "Bar Display", section = "LAYOUT", highlight = "Icon Order" },
            },
            {
                module = "Aura & Buff Reminders",
                title  = "Text Anchor",
                desc   = "Place the label above, on, or beside the icon",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "DISPLAY", highlight = "Show Text" },
            },
            {
                module = "Aura & Buff Reminders",
                title  = "Mana Warning Settings",
                desc   = "Toggle, recolor, resize and preview the ready-check warning",
                nav    = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", section = "CONSUMABLES", highlight = "Ready Check Mana Warning" },
            },
            {
                module = "Cooldown Manager",
                title  = "Threshold Text",
                desc   = "Per-spell decimal countdown and color below a threshold",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "General",
                title  = "Icon Zoom",
                desc   = "Crop icon borders: Bags, Character Sheet, Damage Meters, Unit Frames",
                nav    = { module = "EllesmereUIBags", page = "Bags", section = "DISPLAY", highlight = "Icon Zoom" },
            },
            {
                module = "General",
                title  = "Tutorial Tips & Video Guides",
                desc   = "Help badges on key features open a video guide popup",
                nav    = { module = "_EUIGlobal", page = "General", section = "DISPLAY", highlight = "Enable Tutorial Tips" },
            },
            {
                module = "General",
                title  = "New Patch Reminder Dot",
                desc   = "A dot on Patch Notes whenever your version increases",
            },
            {
                module = "Minimap",
                title  = "Readout Scale Sliders",
                desc   = "Resize the Coordinates and FPS/MS text independently",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "TEXT", highlight = "Show Coordinates" },
            },
            {
                module = "Nameplates",
                title  = "Rare/Quest Icon In Instances",
                desc   = "New toggle lifts the open-world-only restriction",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS" },
            },
            {
                module = "Nameplates",
                title  = "Open World Basic Coloring",
                desc   = "One flat enemy color outside instances",
                nav    = { module = "EllesmereUINameplates", page = "Colors", section = "ENEMY COLORS", highlight = "Enemy Types" },
            },
            {
                module = "Raid Frames",
                title  = "Buff Threshold Sounds",
                desc   = "Play a sound when a tracked buff hits its threshold",
                nav    = { module = "EllesmereUIRaidFrames", page = "Buff Manager" },
            },
            {
                module = "Raid Frames",
                title  = "Incoming Resurrection Icon",
                desc   = "See queued rezzes on dead players",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "INDICATORS", highlight = "Ready Check / Summon / Rez" },
            },
            {
                module = "Raid Frames",
                title  = "Buff Hover Tooltips",
                desc   = "Optional aura tooltips on Buff Manager icons",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "EXTRAS", highlight = "Show Raid Frames Tooltip" },
            },
            {
                module = "Raid Frames",
                title  = "Show Text Above Icons",
                desc   = "Render name and health text above aura icons",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "TEXT DISPLAY", highlight = "Name Size" },
            },
            {
                module = "Raid Frames",
                title  = "Dispellable Debuff Icon Size",
                desc   = "Independent size for split-location dispellables",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "DISPELS", highlight = "Dispellable Debuff Location" },
            },
            {
                module = "Resource Bars",
                title  = "Buff Colors",
                desc   = "Recolor the Class Resource bar while chosen buffs are active",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR", highlight = "Threshold & Hash Lines" },
            },
            {
                module = "Resource Bars",
                title  = "Per-Spec Setup Moved to Spec Overrides",
                desc   = "Advanced mode retired; setups migrate automatically",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "BAR DISPLAY" },
            },
            {
                module = "Resource Bars",
                title  = "Recolor Text Instead Of Bar",
                desc   = "Threshold colors can target the text",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "HEALTH BAR", highlight = "Health Text" },
            },
            {
                module = "Resource Bars",
                title  = "Bar Text Anchor",
                desc   = "Pin bar text left, center, or right",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "HEALTH BAR", highlight = "Health Text" },
            },
            {
                module = "Resource Bars",
                title  = "Stagger Full %",
                desc   = "Set where the Brewmaster bar reads as full",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR", highlight = "Threshold & Hash Lines" },
            },
            {
                module = "Resource Bars",
                title  = "Hide Bar Text per Druid Form",
                desc   = "Independent text visibility per form",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "HEALTH BAR", highlight = "Health Text" },
            },
            {
                module = "Resource Bars",
                title  = "Hide when Dragonriding",
                desc   = "New visibility option",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "BAR DISPLAY", highlight = "Visibility Options" },
            },
            {
                module = "Unit & Resource Bars",
                title  = "Out of Combat Fade",
                desc   = "Fade frames and bars to a chosen alpha out of combat",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "DISPLAY", highlight = "Visibility",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Frame Source",
                desc   = "Render each frame as EllesmereUI or Blizzard's default",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "DISPLAY", highlight = "Visibility",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Apply All Settings To",
                desc   = "Copy one frame's settings to another in one click",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Target Combat Indicator",
                desc   = "The combat indicator can now show on the target frame",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "EXTRAS", highlight = "Combat Indicator",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end
                        EllesmereUI._pendingUnitSelect = "target"
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Name Truncation",
                desc   = "Length limit and optional ellipsis on name text",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "HEALTH BAR", highlight = "Left Text",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Aura Duration Format",
                desc   = "New countdown styles for player buff text",
                nav    = { module = "EllesmereUIUnitFrames", page = "Blizzard Aura Frames", section = "PLAYER BUFFS & DEBUFFS", highlight = "Show Text" },
            },
            {
                module = "Unit Frames",
                title  = "Dispel Type Borders",
                desc   = "Recolor debuff borders by dispel type",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "BUFFS AND DEBUFFS", highlight = "Debuff Display",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end
                        EllesmereUI._pendingUnitSelect = "target"
                    end },
            },
            {
                module = "Unit Frames",
                title  = "Boss Frame Absorbs",
                desc   = "Absorb shields on Boss frames",
                nav    = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "ABSORBS", highlight = "Absorb Style",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end
                        EllesmereUI._pendingUnitSelect = "target"
                    end },
            },
            {
                module = "Unlock Mode",
                title  = "Fallback Anchors",
                desc   = "Anchored elements land safely when their target is missing",
            },
            {
                module = "Tooltips",
                title  = "Peek Modifier",
                desc   = "Hold Shift/Ctrl/Alt to reveal hidden tooltips on hover",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups", section = "BLIZZARD TOOLTIP", highlight = "Show Tooltips" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Vehicle ability cooldowns now show their swipe and timer immediately, instead of only after mouseover or entering combat." },
            { module = "Action Bars", text = "The Stance Bar now stays hidden for classes with no shapeshift forms." },
            { module = "Action Bars", text = "Custom keybind text color no longer reverts to white after target or combat changes." },
            { module = "Action Bars & Cooldown Manager", text = "Item macros no longer trigger a false spell proc glow." },
            { module = "Aura & Buff Reminders", text = "Clicking preview elements now jumps to the right settings section." },
            { module = "Bags", text = "The currency footer now grows with your tracked currencies instead of clipping." },
            { module = "Bags", text = "Collapsing the sidebar no longer drifts a right-anchored bag window." },
            { module = "Character Sheet", text = "Collapsed stat sections now stay collapsed after switching specs, and spec-restricted stats no longer flash back when expanding a section." },
            { module = "Character Sheet", text = "The item level tooltip's better-items list no longer misses cloaks, weapons, caster off-hands or slow-loading items, and now checks the reagent bag too." },
            { module = "Cooldown Manager", text = "Fixed icons from another spec lingering on bars after spec swaps or shapeshifting." },
            { module = "Cooldown Manager", text = "Per-trinket settings now follow the equipped trinket across swaps." },
            { module = "Cooldown Manager", text = "The default Buff Bar's custom order survives respecs and \"Repopulate from Blizzard\"." },
            { module = "Cooldown Manager", text = "Essence of the Blood Queen and similar untracked procs now appear on buff bars." },
            { module = "Cooldown Manager", text = "Pandemic glow now wraps the whole tracking bar instead of clipping under borders." },
            { module = "Cooldown Manager", text = "Tracking bar icons now always match Blizzard's resolved icon (e.g. Roll the Bones)." },
            { module = "Cooldown Manager", text = "Demonic Healthstone is no longer treated as unusable in combat." },
            { module = "Cooldown Manager", text = "CD Ready sound no longer false-triggers on loading screens or bar rebuilds." },
            { module = "Cooldown Manager", text = "Swiftmend brightness now applies reliably and its toggle works without a reload." },
            { module = "Cooldown Manager", text = "FocusKick info text now matches the Show on Target setting." },
            { module = "Cooldown Manager", text = "Tracking bar previews no longer linger after closing the options." },
            { module = "Cooldown Manager", text = "Charge text on custom spells now follows the bar's font and position settings." },
            { module = "Cooldown Manager", text = "Border style and background color now apply consistently across every icon on the Essential and Utility bars." },
            { module = "Crafting Orders", text = "The Place Order / My Orders tabs now show which one is active." },
            { module = "Dragon Riding", text = "The bar's height can now be adjusted from the Unlock Mode cog, and its width is no longer stuck above 96px." },
            { module = "Dragon Riding", text = "Fixed extra spacing between the charge pips and the Whirling Surge icon at certain UI scales." },
            { module = "Dragon Riding", text = "The HUD no longer stays stuck on screen after exiting Unlock Mode while dismounted." },
            { module = "General", text = "11 new alert sounds (Cat Meow, Kaching, Wilhelm, Warning Siren and more) in every sound picker." },
            { module = "General", text = "Hide when Mounted now counts druid Travel, Flight and Aquatic forms." },
            { module = "Group Finder", text = "Fixed errors clicking role and filter checkboxes in Premade Groups." },
            { module = "Mail", text = "The Send Mail attachment slot now reliably shows the attached item's icon." },
            { module = "Nameplates", text = "Fixed the Rare/Quest indicator not anchoring in the Bottom slot." },
            { module = "Nameplates", text = "Fixed border edges flickering or vanishing when plates rescale." },
            { module = "Profiles & Presets", text = "Spec pickers gained Check Tanks / Healers / DPS quick-select links." },
            { module = "Quality of Life", text = "Fixed a multi-second freeze opening /keys in large guilds." },
            { module = "Quality of Life", text = "Quick Loot, Auto Open Containers, LFG Reminder, Low Durability Warning and Shifter now apply instantly without a reload." },
            { module = "Quality of Life", text = "Train All no longer skips still-affordable trainer skills." },
            { module = "Quality of Life", text = "The secondary-stats display now refreshes on gear changes." },
            { module = "Quality of Life", text = "FPS counter labels now resize with the Text Size slider." },
            { module = "Quality of Life", text = "Fixed the wrong icon on the Ursol's Vortex cursor macro." },
            { module = "Quality of Life", text = "Item Upgrade, Transmog, sockets, vendors and other companion windows now dock beside a Shifter-moved Character window instead of hiding underneath it." },
            { module = "Quest Tracker", text = "Fixed tracked quests overlapping after focusing a quest or changing fonts." },
            { module = "Quests", text = "Fixed dark, unreadable text in quest dialogue and reward descriptions." },
            { module = "Raid Frames", text = "Buff Manager Simple Setup now shows buff stack counts, with a new Show Stacks toggle plus color, size and offset controls." },
            { module = "Raid Frames", text = "Hover and target highlights no longer cover name text or icons." },
            { module = "Raid Frames", text = "Fixed frames sizing for a too-small raid right after zoning in." },
            { module = "Raid Frames", text = "Fixed custom size-tier layouts drifting from their saved position." },
            { module = "Resource Bars", text = "Soul Fragments now respect Surrender to the Void's higher fragment cap." },
            { module = "Tooltips", text = "Show Mount now marks whether you've collected the mount." },
            { module = "Unit & Raid Frames", text = "New Gradient Sharp dispel overlay style." },
            { module = "Unit Frames", text = "The pet frame's Class Colored fill now works." },
            { module = "Unit Frames", text = "Fixed blank name/health/power text after a cold login." },
            { module = "Unit Frames", text = "Fixed a detached power bar rendering behind the frame border." },
            { module = "Unit Frames", text = "Frames hidden by visibility conditions no longer absorb mouse clicks." },
            { module = "Unit Frames", text = "Fixed the 3D portrait staying visible on its own while the rest of the frame was hidden." },
            { module = "Unit Frames", text = "Pet, Target-of-Target and Focus Target now follow their parent frame's visibility." },
        },
    },
    {
        version = "8.4.1",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Dynamic CDM Icons",
                desc   = "New per-spell Cooldown State Effect options can hide an icon while it is on cooldown or once it is ready, and the bar collapses the gap so the remaining icons stay tight.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "General",
                title  = "Raid Frames & Tracking Bars Anchoring",
                desc   = "Raid Frames, Party Frames, and Tracking Buff Bars can now be anchored to other elements in Unlock Mode, and other elements can anchor to them.",
            },
            {
                module = "Resource Bars",
                title  = "Sweeping Strikes Bar",
                desc   = "Arms Warriors can now show Sweeping Strikes charges as pips on the Resource Bar, with a new color swatch under Fonts & Colors. Charges also track on the player unit frame and the personal nameplate class resource.",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR" },
            },
            {
                module = "Cooldown Manager",
                title  = "Major CDM Bugfixes",
                desc   = "Hosted buffs no longer conflict with the same spell's cooldown icon, cooldown swipes no longer flicker or keep the wrong transparency/direction, and deleting a Tracking Buff Bar no longer breaks anchor links. Full list below.",
            },
        },
        fixes = {
            { module = "Cooldown Manager", text = "Fixed a buff hosted on a Cooldown or Utility bar conflicting with the same spell's cooldown icon on that bar, which could duplicate icons, make them vanish, or bleed settings between the two." },
            { module = "Cooldown Manager", text = "Buffs hosted on a Cooldown or Utility bar now show a gold border so they stand out from cooldown icons." },
            { module = "Cooldown Manager", text = "Fixed a buff icon losing its cooldown swipe when a neighboring buff on the same bar expired." },
            { module = "Cooldown Manager", text = "Fixed the cooldown swipe sometimes keeping the wrong bar's transparency on a reused icon." },
            { module = "Cooldown Manager", text = "Deleting a Tracking Buff Bar no longer breaks anchor or size-match links pointing at the remaining bars, and switching specs no longer wipes Tracking Bar links." },
            { module = "General", text = "When Include Layout is unchecked during profile import or export, anchored modules can now be selected independently instead of being force-checked together." },
            { module = "Nameplates", text = "New cog on the No Aggro color swatch lets that color override the Mini-Boss and Caster colors." },
            { module = "Quality of Life", text = "Resetting multiple instances at once now posts a single reset announcement to your group instead of one message per dungeon." },
            { module = "Resource Bars", text = "The Class Resource Bar preview in Settings now shows the correct number of pips for specs with non-standard charge counts." },
            { module = "Unit Frames", text = "The pet frame's Class Colored Fill option now works, coloring the bar by the pet's own class (it previously stayed green regardless)." },
        },
    },
    {
        version = "8.4",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Host Buffs on CD/Utility Bars",
                desc   = "Add any buff as its own aura-driven icon on a Cooldown or Utility bar, tracked live off your auras, with a per-icon cooldown swipe color so it fits right alongside your abilities.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "Quality of Life",
                title  = "Combat Alert",
                desc   = "Big customizable on-screen text that fires the moment you enter or leave combat, with your own message, size, colors, and screen position.",
                nav    = { module = "EllesmereUIQoL", page = "Quality of Life", section = "GENERAL", highlight = "Combat Alert" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title  = "Out of Combat Bar Fade",
                desc   = "Dim a bar's icons to a chosen alpha while out of combat",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "BAR LAYOUT", highlight = "Bar Opacity",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "Cooldown Manager",
                title  = "Buff Bar Tooltips",
                desc   = "Show Tooltip on Hover now works on buff-family bars",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "EXTRAS", highlight = "Show Tooltip on Hover",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end
                    end },
            },
            {
                module = "General",
                title  = "Dark Mode Master Toggle",
                desc   = "One switch for the dark theme across frames and resources",
                nav    = { module = "_EUIGlobal", page = "Fonts & Colors", section = "DARK MODE", highlight = "Dark Mode" },
            },
            {
                module = "Glows",
                title  = "Pixel Glow Backgrounds",
                desc   = "A solid background color behind glow effects on nameplates, raid frames, and cooldowns",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "EXTRA AURA OPTIONS", highlight = "Pandemic Glow Style" },
            },
            {
                module = "Mythic Timer",
                title  = "Custom Bar Borders",
                desc   = "Border style, size, offset, and color for the timer and forces bars",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer", section = "TIMER", highlight = "Bar Texture" },
            },
            {
                module = "Nameplates",
                title  = "Name Raid Marker",
                desc   = "Show the target raid marker right before the enemy name",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Name Raid Marker" },
            },
            {
                module = "Nameplates",
                title  = "Cast Icon Offset",
                desc   = "X and Y sliders to reposition the nameplate cast icon",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "HEALTH AND CAST BAR", highlight = "Spell Icon" },
            },
            {
                module = "Nameplates",
                title  = "Cast Icon Target Border",
                desc   = "Match the full-size cast icon border to your target color",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "HEALTH AND CAST BAR", highlight = "Spell Icon" },
            },
            {
                module = "Unit & Raid Frames",
                title  = "Icon Zoom",
                desc   = "New sliders crop tighter on aura icons across raid and unit frames",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "TARGETED SPELLS", highlight = "Icon Size" },
            },
            {
                module = "Unit Frames",
                title  = "Boss Aura Text Colors",
                desc   = "Color pickers for boss buff and debuff duration and stack text",
                nav    = { module = "EllesmereUIUnitFrames", page = "Boss Frames", section = "Buffs and Debuffs", highlight = "Buff Text Size" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Fixed the Hide without Target visibility condition sometimes missing mouseover, nameplate, and soft enemy or friend targets, so bars show and hide reliably." },
            { module = "Blizzard Skin", text = "Fixed profession window text (name, rank, and bar labels) sometimes jumping far out of place when reopening the Professions book after a UI scale change." },
            { module = "Cooldown Manager", text = "Tracking Bar name text can now wrap to two lines instead of always truncating, via a new Text Wrap toggle." },
            { module = "Cooldown Manager", text = "The Shape Glow effect (formerly Custom Shape Glow) now works on any icon instead of requiring a custom icon shape first." },
            { module = "Cooldown Manager", text = "Fixed icons staying desaturated after Desaturate When Not Active was turned off, instead of re-coloring right away." },
            { module = "Cooldown Manager", text = "Per-icon Apply to Bar overrides can now target or exclude a single spell, via new Apply to This Spell and Exclude This Spell options in an icon's right-click menu." },
            { module = "Cooldown Manager", text = "The Tracking Bar spell picker now also shows tracked but untalented spells (desaturated but still selectable), so you can arrange bars without swapping talents." },
            { module = "Mythic Timer", text = "Fixed the Forces (Enemy) bar's Bar Texture and Background Texture settings overwriting the main timer bar's textures instead of using their own." },
            { module = "Unit Frames", text = "Fixed custom Unit Frame fonts not applying on Korean, Chinese, and Cyrillic clients, so they now match the font choice used everywhere else." },
        },
    },
    {
        version = "8.3.9",
        heroes = {
            {
                module = "Cooldown Manager",
                title  = "Mirror Key Presses",
                desc   = "Cooldown Manager icons now show the same pressed-down look as your action buttons the moment you tap an ability's keybind, even while it is on cooldown, matched to your action bar's push effect.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "EXTRAS", highlight = "Mirror Key Presses",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "Character Sheet",
                title  = "Gear Flyout Item Levels",
                desc   = "Hovering an equipped slot on the character sheet now shows each item's level in the swap flyout, colored by quality so you can spot upgrades at a glance.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "CORE OPTIONS", highlight = "Gear Flyout Item Levels" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title  = "Exclude This Spec from Bar Apply",
                desc   = "Opt your spec out of an Apply to Bar (All Specs) setting",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "Damage Meters",
                title  = "Sync Segments Across Windows",
                desc   = "Share segment selection, auto-snap to Current in combat",
            },
            {
                module = "Nameplates",
                title  = "Raise Strata for Core Positions",
                desc   = "Render a slot's icon above the rest of the nameplate",
                nav    = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS", highlight = "Top" },
            },
            {
                module = "Raid Frames",
                title  = "Vertical Absorb Bars",
                desc   = "Anchor the Absorb and Heal Absorb bars on the frame edge",
                nav    = { module = "EllesmereUIRaidFrames", page = "Frames", section = "ABSORBS", highlight = "Absorb Bar" },
            },
            {
                module = "Unit Frames",
                title  = "Boss Cast Bar Width and Offset",
                desc   = "Resize boss cast bars and nudge them left or right",
                nav    = { module = "EllesmereUIUnitFrames", page = "Boss Frames", section = "CAST BAR", highlight = "Cast Bar Width" },
            },
        },
        fixes = {
            { module = "Blizzard Skin", text = "Fixed the reskinned Reputation and Currency panel blanking currency column headers and blocking currency transfers between characters." },
            { module = "Blizzard Skin", text = "Fixed boss ability rows in the reskinned Adventure Guide losing their spell icons." },
            { module = "Blizzard Skin", text = "Fixed vendor names in the Merchant window and dialog text in the Gossip window showing in the wrong font." },
            { module = "Cooldown Manager", text = "Added a Show Charges checkbox to the Add Custom Spell popup so manually added Cooldown and Utility spells can display a charge or cast count." },
            { module = "Cooldown Manager", text = "Removing an untalented spell from Blizzard's Cooldown Manager tracking now also clears it from your assigned spells instead of leaving a phantom entry." },
            { module = "Cooldown Manager", text = "Hide Swipe (Charges) and Hide Recharge Edge now take effect immediately on a spell that is already recharging." },
            { module = "Cooldown Manager", text = "Equipped trinkets and tracked items no longer stay briefly desaturated after their cooldown finishes once the ready glow has lit." },
            { module = "Damage Meters", text = "Added an Icon Zoom slider (in the cog next to Icon Style) to crop tighter on class and spec icons." },
            { module = "Damage Meters", text = "Fixed the Class Color swatch always previewing Paladin's color regardless of your class." },
            { module = "General", text = "Fixed accent color preview swatches across Damage Meters, Raid Frames, and Window Skins (and some Raid Frames Buff Manager and HoverCast buttons) not reflecting your custom or class-colored accent." },
            { module = "Mythic Timer", text = "Fixed the title and Enemy Forces bars showing the plain theme color instead of your custom or class-colored accent." },
            { module = "Nameplates", text = "Mini and neutral enemy coloring now applies everywhere by default, with a new Mini Coloring M+ Only toggle to limit it to dungeons." },
            { module = "Nameplates", text = "Added two combined health text formats that separate percent and value with a dash (Health % - # and Health # - %)." },
            { module = "Nameplates", text = "Fixed the Class Resource border color swatch and cog staying clickable when Border was turned off." },
            { module = "Profiles", text = "Fixed importing a profile sometimes erasing your current profile's saved bar anchors and width-match layout after you switched back to it or deleted the imported profile." },
            { module = "Quality of Life", text = "Holy Paladins get a new Show Melee Range for Hpal crosshair toggle that checks range at 5 yards instead of 40." },
            { module = "Quality of Life", text = "The crosshair's 40 yard range check now also works from The Decapitator toy, fixing false out-of-range coloring for players without the Happy Fun Rock toy." },
            { module = "Unit Frames", text = "The Buffs Max Count and Max Per Row sliders now go up to 40 (previously 20)." },
        },
    },
    {
        version = "8.3.8",
        mini = true,
        -- Mini-patch fixes render as plain bullets: no `module` field means no
        -- "Module: " prefix, and SortByModule keeps this authored order.
        fixes = {
            { text = "The NPC quest window is now skinned" },
            { text = "Fixed the black quest and greeting text in the NPC dialog window" },
            { text = "Added options to show your character level and raw XP values on the XP bar" },
            { text = "Health, power, class resource, and cast bars can now be widened up to 800px" },
            { text = "Fixed the Ironfur bar ignoring advanced-mode colours and showing stale stacks after leaving and re-entering Bear Form" },
            { text = "Tracked Buff Bar stack count offset sliders now reach up to 250 in either direction" },
            { text = "The Group Death alert text is now always outlined so it stays readable" },
            { text = "The character sheet no longer reloads your 3D model during combat while it's closed" },
            { text = "Fixed certain anchored bars re-positioning every frame instead of sitting still, fixing a performance issue introduced in 8.3.7" },
            { text = "Performance optimizations for Blizzard skins" },
        },
    },
    {
        version = "8.3.7",
        heroes = {
            {
                module = "Blizzard Skin",
                title  = "Blizzard Window Skinning",
                desc   = "Dozens of Blizzard windows now match EllesmereUI, including Collections, Professions, Auction House, Guild, Calendar, Achievements, Mail, World Map, and more. Each has its own style dropdown: EUI theme, Modern flat color, or off.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Blizzard Window Skins", section = "GLOBAL OPTIONS", highlight = "" },
            },
            {
                module = "Resource Bars",
                title  = "Threshold System Upgrade and More",
                desc   = "Class, power, and health bars get a new advanced mode allowing you to save every setting per spec, and create more advanced thresholds than ever before.",
                nav    = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR", highlight = "" },
            },
            {
                module = "CDM",
                title  = "Tracking Bars System Upgrade",
                desc   = "Tracking Bars now support multiple groups, each with its own grow direction, spacing, auto-add to bar, plus drag-and-drop between groups and style presets for one bar or a whole group.",
                nav    = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
            },
            {
                module = "CDM",
                title  = "Apply to All Specs",
                desc   = "Per-spell settings now travel with the spell instead of resetting when it moves between bars, and hovering any setting reveals one-click Apply to Bar and Apply to Bar (All Specs) buttons.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
            },
            {
                module = "Minimap",
                title  = "Full Settings Upgrades",
                desc   = "Start the addon and Blizzard icon rows from any minimap corner and grow them in any direction, with per-row spacing, distance, and popup-direction controls, plus the full EllesmereUI Border Style system with Class, Accent, and Custom color swatches.",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "MINIMAP & QOL BUTTONS", highlight = "Button Row Position" },
            },
            {
                module = "Quality of Life",
                title  = "Scale Blizzard Panels",
                desc   = "Shifter can now resize panels, not just move them: Shift+scroll over any Shifter-enabled Blizzard window to permanently rescale it, or Ctrl+scroll for a temporary zoom that resets when it closes.",
                nav    = { module = "EllesmereUIQoL", page = "Shifter", section = "SHIFTER", highlight = "" },
            },
        },
        features = {
            {
                module = "Blizzard Skin",
                title  = "Item Max Stack Tooltip",
                desc   = "Item tooltips can now show the item's max stack size, shown always or only while holding a modifier key of your choice (Shift, Control, or Alt).",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups", section = "BLIZZARD TOOLTIP", highlight = "Show Max Stack for Items" },
            },
            {
                module = "Blizzard Skin",
                title  = "Guild Rank & Mount Tooltips",
                desc   = "Unit tooltips can now show a player's guild rank next to their guild name, and the name of the mount they are currently riding.",
                nav    = { module = "EllesmereUIBlizzardSkin", page = "Tooltips, Menus & Popups", section = "BLIZZARD TOOLTIP", highlight = "" },
            },
            {
                module = "CDM",
                title  = "Arrange Without Talents",
                desc   = "The spell picker and the default cooldown and utility bar previews now include spells you track but have not talented into yet (shown desaturated), so you can lay out an entire spec's loadout ahead of time.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "CDM",
                title  = "Resource-Aware CD Ready Glow",
                desc   = "Pixel Glow and Button Glow CD Ready effects gain Resource Aware variants that also check whether you have enough resources to use the ability, so the glow no longer lights up on a spell you cannot yet afford.",
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "CDM",
                title  = "Decimal Countdowns for Custom Timers",
                desc   = "Presets and custom spell or item IDs can now show a 1-decimal countdown (like 2.7) once their active state or buff duration drops under a threshold you set, with an optional color change for those final seconds.",
                -- The bar-level toggle this note shipped with became the per-spell
                -- "Threshold Text" dropdown; land on the page without a highlight.
                nav    = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("cooldowns") end
                    end },
            },
            {
                module = "Chat",
                title  = "Durability Sidebar Icon",
                desc   = "Add an optional Durability icon to the chat sidebar showing your lowest equipment durability at a glance, with a hover tooltip and live updates.",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "SIDEBAR", highlight = "Sidebar Icons" },
            },
            {
                module = "Chat",
                title  = "Drag to Reorder Sidebar Icons",
                desc   = "The Sidebar Icons list now lets you drag rows to set the exact stacking order of your chat sidebar icons.",
                nav    = { module = "EllesmereUIChat", page = "Chat", section = "SIDEBAR", highlight = "Sidebar Icons" },
            },
            {
                module = "Damage Meters",
                title  = "Custom Icon Border",
                desc   = "Add a customizable border around each bar's class or spec icon, with its own texture style, size, offset, and color, independent of the bar's own border.",
                nav    = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "BARS", highlight = "" },
            },
            {
                module = "Minimap",
                title  = "FPS/MS Readout",
                desc   = "Add a live FPS and ping readout on the minimap. Choose its position, text size, update speed, whether it shows local and world latency, and an optional hover tooltip.",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "TEXT", highlight = "Show FPS/MS" },
            },
            {
                module = "Minimap",
                title  = "Instance Difficulty as Text",
                desc   = "Replace the small Blizzard difficulty icon with a compact text readout like 20M, M+12, or T4, freely positioned and resized, optionally colored by tier.",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "TEXT", highlight = "Show Instance Difficulty as Text" },
            },
            {
                module = "Minimap",
                title  = "More Text Placement Options",
                desc   = "Clock and zone text now support None, Inside Map, or Edge Box styles at any of nine positions, coordinates gain a Never option, zone text can show sub-zone and tint by PvP ruleset, and Omnium Folio can be hover-only.",
                nav    = { module = "EllesmereUIMinimap", page = "Minimap", section = "TEXT", highlight = "Clock Style" },
            },
            {
                module = "Mythic Timer",
                title  = "Key Level on Timer Line",
                desc   = "Move the lone +key title down onto the timer line (like +21 | 28:41) when the dungeon name is hidden, plus a Spacing slider for the gap.",
                nav    = { module = "EllesmereUIMythicTimer", page = "Mythic+ Timer", section = "TITLE", highlight = "" },
            },
            {
                module = "Nameplates",
                title  = "Friendly Nameplate Stacking",
                desc   = "Friendly nameplates can now stack vertically too, independent of enemy stacking, whenever EllesmereUI is managing friendly player plates.",
                nav    = { module = "EllesmereUINameplates", page = "General", section = "NAMEPLATE SPACING", highlight = "Stacking Nameplates" },
            },
            {
                module = "Quality of Life",
                title  = "Hide Item Transforms",
                desc   = "Automatically cancels cosmetic transform auras the moment they land (profession gear like the Chef's Hat, holiday costumes, toys, consumables). A picker chooses which categories get removed; anything gained in combat is cleared when combat ends.",
                nav    = { module = "EllesmereUIQoL", page = "Quality of Life", section = "GENERAL", highlight = "Hide Item Transforms" },
            },
            {
                module = "Quality of Life",
                title  = "Range-Aware Crosshair for Every Spec",
                desc   = "The crosshair's out-of-range coloring now works for every class and spec, with an auto-calculated cutoff distance for ranged and caster specs.",
                nav    = { module = "EllesmereUIQoL", page = "Quality of Life", section = "CROSSHAIR", highlight = "Color Out of Range" },
            },
            {
                module = "Quality of Life",
                title  = "Move Loot Windows",
                desc   = "Bonus Roll and Group Loot windows can now be repositioned from Unlock Mode, with a toggle to hide their movers while keeping saved positions.",
                nav    = { module = "EllesmereUIQoL", page = "Shifter", section = "LOOT WINDOWS", highlight = "Move Loot Windows in Unlock Mode" },
            },
        },
        fixes = {
            { module = "Blizzard Skin", text = "Character Sheet stat tooltips now break down how Crit, Strength, Agility, Armor, and Block translate into parry, dodge, and physical damage reduction, both against an even target and your current target." },
            { module = "Blizzard Skin", text = "Fixed Character Sheet primary attribute tooltips showing an incorrect base value that double-counted buffs." },
            { module = "Blizzard Skin", text = "Close buttons on the Character Sheet, Inspect Sheet, and Great Vault now use a clean icon glyph instead of a plain text x." },
            { module = "Blizzard Skin", text = "Static popups and the pause menu now highlight their buttons on hover, fully skin popups with a fifth action button, and give popup input boxes a matching border." },
            { module = "CDM", text = "Bars using a 2-row Custom Split can now anchor the first row so it stops re-centering, and the top and bottom rows can each have their own icon size offset." },
            { module = "CDM", text = "Custom spell and custom buff IDs gain Copy to Other Specs (and Remove from Other Specs) in their right-click menu." },
            { module = "CDM", text = "Trinket and item CD-ready sounds now fire correctly in Mythic+, and self-timed buffs like Bloodlust, potions, and custom buff IDs can now play a sound on loss, not just on gain." },
            { module = "CDM", text = "Cooldown-ready glows no longer briefly show the wrong state right after a loading screen, zone change, or login." },
            { module = "CDM", text = "Tracked buff bars no longer sit on an inactive placeholder for a moment after the buff procs." },
            { module = "CDM", text = "Vertical tracking bars now show duration text at your chosen position, thin vertical bars are no longer forced wider, and switching a bar to vertical flips its whole group together." },
            { module = "CDM", text = "Toggling a tracking bar's icon on or off now keeps the bar's overall footprint the same." },
            { module = "Damage Meters", text = "Added an option (CJK clients only) to force numbers into K/M/B units instead of localized 10k or 100M grouping." },
            { module = "Friends", text = "Auto-Accept Friend Invites now has a cog option to also automatically accept group invites from guildmates, not just friends." },
            { module = "General", text = "Fixed the sidebar highlight accent not updating immediately after switching the EUI Options Theme." },
            { module = "General", text = "Disable Slug Outline and Outline Icon Text are now saved per profile and travel with export and import." },
            { module = "General", text = "Expanded and corrected translations across Korean, Russian, Simplified Chinese, and Traditional Chinese." },
            { module = "Minimap", text = "Hover-only minimap elements (zoom buttons, hover-mode Omnium Folio, hover coordinates) now reveal reliably no matter which edge or icon the cursor enters through, and the Zoom In/Out buttons correctly hide when disabled and fade in on hover." },
            { module = "Minimap", text = "Scroll to Zoom now works reliably in the corners of the square minimap shape." },
            { module = "Minimap", text = "The mail indicator can now be pinned to any minimap corner instead of only the Blizzard icon row." },
            { module = "Minimap", text = "The Great Vault, Friends Online, and M+ Portals extra buttons, and ungrouped addon buttons, can now be drag-reordered from their checklists." },
            { module = "Minimap", text = "Clicking anywhere outside the addon button flyout now closes it." },
            { module = "Minimap", text = "M+ Portals flyout scale is now a separate slider from a new Custom Tooltip Size option for the Great Vault, Friends, and Calendar panels, which now stay clamped on-screen." },
            { module = "Minimap", text = "Mouseover Extra Buttons no longer fades the button row out while the Friends Online tooltip is open." },
            { module = "Mythic Timer", text = "Fixed the timer clock getting clipped on custom fonts whose digits render wider than 9." },
            { module = "Mythic Timer", text = "Fixed the +2 and +3 threshold time labels jittering horizontally as the seconds tick down." },
            { module = "Nameplates", text = "Fixed neutral-reaction trash in Mythic+ showing the plain neutral color instead of the correct Mini Enemies, Caster, or aggro color." },
            { module = "Nameplates", text = "Fixed nameplate vertical overlap spacing being force-reset on every login." },
            { module = "Nameplates", text = "Fixed the interrupted-cast flash not shrinking with a nameplate that scales down after the cast." },
            { module = "Quality of Life", text = "Added an adjustable update interval (1 to 5 seconds) for the FPS counter instead of it always refreshing once per second." },
            { module = "Quality of Life", text = "Auto Open Containers now skips warband bank deposit boxes by default, with a cog toggle to turn the exclusion off." },
            { module = "Quality of Life", text = "Group death alerts and the death sound no longer overlap into a spammy mess when several people die at once; the sound is throttled and only one alert shows per check." },
            { module = "Raid Frames", text = "Fixed a debuff icon briefly duplicating when its visibility was re-evaluated (duel start and end, phasing, or PvP flag changes)." },
            { module = "Raid Frames", text = "Fixed a duplicate dispel indicator appearing with an icon-only dispel display." },
            { module = "Raid Frames", text = "Fixed rare one-pixel border jitter on reload for certain frame sizes." },
            { module = "Raid Frames", text = "Improved localization coverage for Buff Manager display text." },
            { module = "Resource Bars", text = "Fixed the Guardian Druid Ironfur bar showing in every form; it now only appears in Bear Form." },
            { module = "Resource Bars", text = "Added an option to show Class Resource text only while the Power Bar is hidden, so the count does not double up." },
            { module = "Resource Bars", text = "Fixed smooth-animated bars settling just short of full or empty instead of landing exactly on the value." },
            { module = "Unit Frames", text = "Fixed the Empty Bar Color swatch on the Modern class resource bar not saving or applying, and it now applies live." },
            { module = "Unit Frames", text = "Fixed the power bar border on detached power bars failing to appear on the target and focus frames without a reload." },
            { module = "Unit Frames", text = "Fixed unlock-anchored frames and castbars snapping back to an old position after a reload." },
            { module = "Unit Frames", text = "Fixed the native Blizzard class power bar snapping back onto the player frame after a form or spec change." },
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

    -- Re-apply combat text font at login -- handled by EllesmereUI_Startup.lua.

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

    --- Returns true when the CVar is still at Blizzard's built-in default,
    --- meaning no addon or player has changed it.
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

    -- NOTE: Optimized graphics settings are NOT re-applied on login.
    -- SetCVar already persists to WoW's config, so re-applying would override
    -- any manual adjustments the user makes in WoW's graphics settings panel.

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
            { "graphicsSpellDensity",       "1" },
            { "graphicsProjectedTextures",  "1" },
            { "graphicsViewDistance",        "1" },
            { "graphicsEnvironmentDetail",  "1" },
            { "graphicsGroundClutter",      "1" },
            { "RAIDsettingsEnabled",        "0" },
            { "ResampleAlwaysSharpen",      "1" },
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
            end
            -- Apply optimized CVars
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                SetCVarSafe(entry[1], entry[2])
            end
            -- Contrast boost: if current contrast <= 55, add 10
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
                        .. "Contrast - Boosted by +10 (if currently 55 or below)\n\n"
                        .. "These settings prioritize frame rate and visual clarity over environmental detail. Textures stay high quality so your character and the world still look perfect.",
                })
            end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Build dropdown values table from THEME_ORDER
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
                      -- Per-profile: set use-class on the active profile, then
                      -- re-resolve + apply live (resolves to the class color).
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
                      -- SetAccentColor persists per-profile (custom + useClass=false)
                      -- and applies live.
                      EllesmereUI.SetAccentColor(r, g, b)
                  end,
                  onClick = function(self)
                      if select(1, EllesmereUI.GetActiveAccentState()) then
                          -- Switch class -> custom: clear the per-profile class
                          -- flag and re-resolve (profile custom -> global -> theme).
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
                -- Fix sidebar highlight accent not changing on theme change
                if EllesmereUI.RefreshAccent then
                    EllesmereUI.RefreshAccent()  -- ApplyAccentLive already refreshes the page
                else
                    EllesmereUI:RefreshPage()
                end
              end }
        );  y = y - h

        -- Inline color swatch on EUI Options Theme (right region)
        do
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
                -- Snap 0.53 to exact pixel-perfect 0.5333...
                if math.abs(v - 0.53) < 0.005 then v = 0.5333333333 end
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
            { type="dropdown", text="EUI Options Scale",
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
        do
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
        -- "EUI Buttons" is a checkbox-dropdown that merges the former Pause Menu,
        -- Unlock Mode Menu, and Minimap button toggles. Same backend variables --
        -- a purely front-end grouping, so user settings and defaults are unchanged.
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
        do
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
        do
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

        -- EUI Options Language: the display language for the EllesmereUI options
        -- panel (auto-detects the client; a manual choice falls back to English
        -- for anything not yet translated).
        do
            -- _noLoc: the language list itself is never translated, so a player
            -- who booted the wrong language can always read and change it.
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
                else
                    EllesmereUIDB.fctFont = v
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
        do
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
        --  DEVELOPER
        --  Both toggles are duplicated into Quality of Life (Suppress Lua
        --  Errors) and Blizzard UI Enhanced (Show Spell ID on Tooltip). When
        --  BOTH of those modules are enabled the user can reach each setting
        --  there, so this whole section is hidden to avoid redundancy. It stays
        --  visible if either module is missing so the settings remain reachable.
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
                            "EllesmereUIBasicsDB",
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
    --  Quick Setup page  (curated quick-access to key settings per addon)
    --  Action Bars options are live; others are temporary placeholders
    --  until those addons register their core settings.
    ---------------------------------------------------------------------------
    local function BuildCoreOptionsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -------------------------------------------------------------------
        --  ACTION BARS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "ACTION BARS", y);  y = y - h

        -- Access EAB through addon registry
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

        -------------------------------------------------------------------
        --  NAMEPLATES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "NAMEPLATES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  UNIT FRAMES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "UNIT FRAMES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  BAR GLOWS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "BAR GLOWS", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CONSUMABLES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CONSUMABLES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CURSOR CIRCLE
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CURSOR CIRCLE", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  BEACON REMINDERS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "BEACON REMINDERS", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Re-read live CVar values every time the panel is opened.
    --  Widgets call their getter on each build, so a page rebuild is enough
    --  to pick up any CVar changes made externally (other addons, /console).
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI:GetActiveModule() == GLOBAL_KEY then
            EllesmereUI:RefreshPage()
        end
    end)

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Colors Page
    ---------------------------------------------------------------------------
    local CLASS_ORDER = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
        "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
        "DRUID", "DEMONHUNTER", "EVOKER",
    }
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
        -- Swatches read/write the EFFECTIVE palette (per-profile -> active profile's
        -- own; global -> the shared source profile's). In every editable case that
        -- IS the active profile's table, so edits land correctly; the only locked
        -- case (global mode on a non-source profile) is gated by an overlay below.
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
                    -- Repaint from current colours whenever the page refreshes or is
                    -- shown (SelectPage re-runs the refresh list on show). Keeps the
                    -- swatches in sync after a profile change / global-source change
                    -- instead of showing the colours from when the page was built.
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
        --  GLOBAL FONT section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GLOBAL FONT", y);  y = y - h

        -- Glyph-restricted locales (CJK, Cyrillic): our bundled fonts are
        -- Latin-only and cannot render the script, so the picker below offers
        -- only "System Default" (the correct system font) plus any external
        -- SharedMedia fonts the user installed, which may carry the right
        -- glyphs. Per-module fonts and the game-text swap stay hidden (they
        -- operate on Latin faces).
        local localeRestricted = EllesmereUI.LOCALE_FONT_FALLBACK ~= nil

        local fontDropValues = {}
        local fontDropOrder  = {}
        if localeRestricted then
            -- System Default (correct glyph font) + external SharedMedia only;
            -- bundled Latin fonts are omitted (they would render as boxes here).
            fontDropValues[EllesmereUI.SYSTEM_FONT_KEY] = { text = "System Default", font = EllesmereUI.LOCALE_FONT_FALLBACK }
            fontDropOrder[#fontDropOrder + 1] = EllesmereUI.SYSTEM_FONT_KEY
            if EllesmereUI.AppendExternalSharedMediaFonts then
                EllesmereUI.AppendExternalSharedMediaFonts(fontDropValues, fontDropOrder)
            end
        else
            local FONT_DIR_GLOBAL = EllesmereUI.MEDIA_PATH .. "fonts\\"
            for _, name in ipairs(EllesmereUI.FONT_ORDER) do
                if name == "---" then
                    fontDropOrder[#fontDropOrder + 1] = "---"
                else
                    local path = EllesmereUI.FONT_BLIZZARD[name]
                        or (FONT_DIR_GLOBAL .. (EllesmereUI.FONT_FILES[name] or "Expressway.TTF"))
                    local displayName = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name
                    fontDropValues[name] = { text = displayName, font = path }
                    fontDropOrder[#fontDropOrder + 1] = name
                end
            end
            if EllesmereUI.AppendSharedMediaFonts then
                EllesmereUI.AppendSharedMediaFonts(fontDropValues, fontDropOrder, { keyByName = true })
            end
        end


        -- Reload popup for font changes
        local function FontReload()
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = "Font changed. A UI reload is needed to apply the new font.",
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        end

        local outlineModeValues = {
            ["none"]    = { text = "Drop Shadow" },
            ["outline"] = { text = "Outline" },
            ["thick"]   = { text = "Thick Outline" },
        }
        local outlineModeOrder = { "none", "outline", "thick" }

        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Global Font",
              values=fontDropValues, order=fontDropOrder,
              getValue=function()
                  local g = EllesmereUI.GetFontsDB().global or "Expressway"
                  -- In glyph-restricted locales the stored bundled-font default
                  -- maps to the System Default entry; a chosen SM font shows as-is.
                  if localeRestricted and not fontDropValues[g] then return EllesmereUI.SYSTEM_FONT_KEY end
                  return g
              end,
              setValue=function(v)
                  EllesmereUI.GetFontsDB().global = v
                  local rl = EllesmereUI._widgetRefreshList
                  if rl then for i2 = 1, #rl do rl[i2]() end end
                  FontReload()
              end },
            { type="dropdown", text="Outline Mode",
              tooltip="Controls the text rendering style used across all UI elements",
              values=outlineModeValues, order=outlineModeOrder,
              getValue=function()
                  local v = EllesmereUI.GetFontsDB().outlineMode or "none"
                  if v == "shadow" then v = "none" end
                  return v
              end,
              setValue=function(v)
                  EllesmereUI.GetFontsDB().outlineMode = v
                  local rl = EllesmereUI._widgetRefreshList
                  if rl then for i2 = 1, #rl do rl[i2]() end end
                  FontReload()
              end });  y = y - h

        -- Outline Icon Text: per-module control for whether icon-overlay text
        -- (stack counts, durations, keybinds) is forced to a crisp outline.
        -- Checked (default) forces the outline; unchecking a module makes its
        -- icon text follow the Outline Mode choice above instead. The left slot
        -- holds the per-module checkbox dropdown; the right slot is the
        -- "Apply to All Game Text" toggle.
        do
            local oitItems = {
                { key = "actionBars", label = "Action Bars Icons" },
                { key = "unitFrames", label = "Unit Frames Icons" },
                { key = "cdm",        label = "CDM Icons" },
                { key = "raidFrames", label = "Raid Frames Icons" },
                { key = "bags",       label = "Bags Icons" },
            }
            local oitRow
            oitRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Outline Icon Text",
                  tooltip="Forces a crisp outline on icon text (stack counts, durations, keybinds). Uncheck a module to make its icon text follow the Outline Mode setting above instead.",
                  values={ ["_placeholder"]="..." }, order={ "_placeholder" },
                  getValue=function() return "_placeholder" end,
                  setValue=function() end },
                { type="toggle", text="Apply to All Game Text",
                  tooltip="Applies your Global Font to Blizzard's default game text (menus, tooltips, quest log, character panes, and more). Requires a UI reload.",
                  getValue=function() return EllesmereUI.GetFontsDB().applyToAllGameText == true end,
                  setValue=function(v)
                      EllesmereUI.GetFontsDB().applyToAllGameText = v and true or false
                      FontReload()
                  end }
            );  y = y - h
            local rgn = oitRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 220, rgn:GetFrameLevel() + 2,
                oitItems,
                function(k)
                    local f = EllesmereUI.GetFontsDB()
                    local t = (f and f.outlineIconText) or (EllesmereUIDB and EllesmereUIDB.outlineIconText)
                    return not (t and t[k] == false)
                end,
                function(k, v)
                    -- Per-profile now (rides profile export). Seed the per-profile
                    -- table from the legacy account-global one on first write so
                    -- other modules' choices carry over unchanged.
                    local f = EllesmereUI.GetFontsDB()
                    if type(f.outlineIconText) ~= "table" then
                        local t = {}
                        local seed = EllesmereUIDB and EllesmereUIDB.outlineIconText
                        if type(seed) == "table" then
                            for kk, vv in pairs(seed) do t[kk] = vv end
                        end
                        f.outlineIconText = t
                    end
                    f.outlineIconText[k] = v and true or false
                    -- Prompt the reload from setFn rather than passing an
                    -- onChanged callback: a non-nil onChanged makes the CB
                    -- dropdown re-anchor the open menu to an absolute position
                    -- (meant for page rebuilds), which visibly shifts it here.
                    FontReload()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Never Show Slug: per-profile toggle (rides profile export/import) that
        -- drops the SLUG token from every outline the UI produces -- body text and
        -- icon/aura text across all modules, plus the global Outline Mode itself.
        -- Off by default, so slug outlines render as normal. Requires a UI reload.
        do
            local nssRow
            nssRow, h = W:DualRow(parent, y,
                { type="toggle", text="Disable Slug Outline",
                  tooltip="Slug outline renders higher quality outlines compared to the base WoW outline mode but may make outline effects appear slightly thicker.",
                  getValue=function() return EllesmereUI.IsSlugDisabled() end,
                  setValue=function(v)
                      EllesmereUI.GetFontsDB().neverShowSlug = v and true or false
                      FontReload()
                  end },
                { type="label", text="" }
            );  y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  PER ADDON FONTS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "PER ADDON FONTS", y);  y = y - h

        do
            local eg = EllesmereUI.ELLESMERE_GREEN or {r=0.047, g=0.824, b=0.624}
            local fontPath = EllesmereUI.EXPRESSWAY
            local outlineFlag = EllesmereUI.GetFontOutlineFlag()
            local RebuildModuleFontList  -- forward declaration

            -- Build module list from ADDON_ROSTER (exclude comingSoon)
            local moduleEntries = {}
            for _, entry in ipairs(EllesmereUI.ADDON_ROSTER) do
                if not entry.comingSoon then
                    moduleEntries[#moduleEntries + 1] = {
                        folder  = entry.folder,
                        display = entry.display,
                    }
                end
            end

            ---------------------------------------------------------------
            --  Row: Module checkbox dropdown + "Add Module Font" button
            ---------------------------------------------------------------
            local ROW_H    = 50
            local ITEM_H   = 30
            local GAP      = 15
            local BTN_W    = 160
            local DD_W     = 250
            local totalW   = parent:GetWidth() - CONTENT_PAD * 2

            local mfRow = CreateFrame("Frame", nil, parent)
            PP.Size(mfRow, totalW, ROW_H)
            PP.Point(mfRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

            local groupW = DD_W + GAP + BTN_W
            local startX = math.floor((totalW - groupW) / 2)
            local offsetY = -math.floor((ROW_H - ITEM_H) / 2)

            -- Dropdown button (checkbox multi-select)
            local ddBtn = CreateFrame("Button", nil, mfRow)
            PP.Size(ddBtn, DD_W, ITEM_H)
            PP.Point(ddBtn, "TOPLEFT", mfRow, "TOPLEFT", startX, offsetY)
            ddBtn:SetFrameLevel(mfRow:GetFrameLevel() + 2)

            local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints()
            ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

            local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
            ddLbl:SetFont(fontPath, 13, outlineFlag)
            ddLbl:SetTextColor(1, 1, 1, 0.50)
            ddLbl:SetMaxLines(1)
            ddLbl:SetJustifyH("LEFT")
            ddLbl:SetWordWrap(false)
            ddLbl:SetText(EllesmereUI.L("Select Module"))

            local ddArrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)
            ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 14, 0)
            ddLbl:SetPoint("RIGHT", ddArrow, "LEFT", -5, 0)

            -- Selected modules map (indexed by moduleEntries index)
            local selectedModuleMap = {}

            local function GetSelectedLabel()
                local names = {}
                for i, me in ipairs(moduleEntries) do
                    if selectedModuleMap[i] then
                        names[#names + 1] = EllesmereUI.L(me.display)
                    end
                end
                if #names == 0 then return EllesmereUI.L("Select Module") end
                return table.concat(names, ", ")
            end

            -----------------------------------------------------------
            --  Checkbox popup (matches ABR zone dropdown pattern)
            -----------------------------------------------------------
            local SEARCH_H = 26
            local POPUP_ITEM_H = 28
            local popupH = math.min(#moduleEntries * POPUP_ITEM_H + 8, 300) + SEARCH_H + 10
            local popup = CreateFrame("Frame", nil, UIParent)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(200)
            popup:SetClampedToScreen(true)
            popup:SetSize(DD_W, popupH)
            popup:Hide()

            local popupBg = popup:CreateTexture(nil, "BACKGROUND")
            popupBg:SetAllPoints()
            popupBg:SetColorTexture(0.10, 0.10, 0.12, 0.97)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.12, PP)

            -- Search box
            local searchBox = CreateFrame("EditBox", nil, popup)
            searchBox:SetSize(DD_W - 16, SEARCH_H)
            searchBox:SetPoint("TOP", popup, "TOP", 0, -6)
            searchBox:SetFrameLevel(popup:GetFrameLevel() + 3)
            searchBox:SetFont(fontPath, 11, "")
            searchBox:SetTextColor(1, 1, 1, 0.9)
            searchBox:SetJustifyH("LEFT")
            searchBox:SetAutoFocus(false)
            searchBox:SetMaxLetters(30)
            searchBox:SetTextInsets(4, 4, 0, 0)
            local sBg = searchBox:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0, 0, 0, 0.4)
            local sPlaceholder = searchBox:CreateFontString(nil, "OVERLAY")
            sPlaceholder:SetFont(fontPath, 11, "")
            sPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
            sPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
            sPlaceholder:SetText(EllesmereUI.L("Search..."))
            searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            -- Scroll frame
            local sf = CreateFrame("ScrollFrame", nil, popup)
            sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -(SEARCH_H + 10))
            sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 4)
            sf:SetFrameLevel(popup:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            local sfChild = CreateFrame("Frame", nil, sf)
            sfChild:SetWidth(DD_W)
            sf:SetScrollChild(sfChild)

            -- Thin scrollbar track
            local sTrack = CreateFrame("Frame", nil, sf)
            sTrack:SetWidth(4)
            sTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -4)
            sTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 4)
            sTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
            do local t = sTrack:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.02) end

            local sThumb = CreateFrame("Button", nil, sTrack)
            sThumb:SetWidth(4)
            sThumb:SetFrameLevel(sTrack:GetFrameLevel() + 1)
            sThumb:EnableMouse(true)
            sThumb:RegisterForDrag("LeftButton")
            sThumb:SetScript("OnDragStart", function() end)
            sThumb:SetScript("OnDragStop", function() end)
            do local t = sThumb:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.27) end

            local sScrollTarget = 0
            local sSmoothing = false
            local S_SCROLL_STEP = 40
            local S_SMOOTH_SPEED = 12
            local sSmoothFrame = CreateFrame("Frame")
            sSmoothFrame:Hide()

            local function UpdateSThumb()
                local maxScroll = math.max(0, sfChild:GetHeight() - sf:GetHeight())
                if maxScroll <= 0 then sTrack:Hide(); return end
                sTrack:Show()
                local trackH = sTrack:GetHeight()
                local visH = sf:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(20, trackH * ratio)
                sThumb:SetHeight(thumbH)
                local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
                local maxTravel = trackH - thumbH
                sThumb:ClearAllPoints()
                sThumb:SetPoint("TOP", sTrack, "TOP", 0, -(scrollRatio * maxTravel))
            end

            sSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                local maxScroll = math.max(0, sfChild:GetHeight() - sf:GetHeight())
                sScrollTarget = math.max(0, math.min(maxScroll, sScrollTarget))
                local diff = sScrollTarget - cur
                if math.abs(diff) < 0.3 then
                    sf:SetVerticalScroll(sScrollTarget)
                    UpdateSThumb()
                    sSmoothing = false
                    sSmoothFrame:Hide()
                    return
                end
                local newScroll = cur + diff * math.min(1, S_SMOOTH_SPEED * elapsed)
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateSThumb()
            end)

            local function SSmoothScrollTo(target)
                local maxScroll = math.max(0, sfChild:GetHeight() - sf:GetHeight())
                sScrollTarget = math.max(0, math.min(maxScroll, target))
                if not sSmoothing then
                    sSmoothing = true
                    sSmoothFrame:Show()
                end
            end

            sf:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = math.max(0, sfChild:GetHeight() - self:GetHeight())
                if maxScroll <= 0 then return end
                local base = sSmoothing and sScrollTarget or self:GetVerticalScroll()
                SSmoothScrollTo(base - delta * S_SCROLL_STEP)
            end)
            popup:SetScript("OnMouseWheel", function(_, delta)
                sf:GetScript("OnMouseWheel")(sf, delta)
            end)

            -- Thumb drag
            local sDragging = false
            local sDragStartY, sDragStartScroll
            sThumb:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                sDragging = true
                sSmoothing = false
                sSmoothFrame:Hide()
                local _, cursorY = GetCursorPosition()
                sDragStartY = cursorY / self:GetEffectiveScale()
                sDragStartScroll = sf:GetVerticalScroll()
            end)
            sThumb:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then sDragging = false end
            end)
            sThumb:SetScript("OnUpdate", function(self)
                if not sDragging then return end
                local _, cursorY = GetCursorPosition()
                cursorY = cursorY / self:GetEffectiveScale()
                local dy = sDragStartY - cursorY
                local trackH = sTrack:GetHeight()
                local thumbH = sThumb:GetHeight()
                local maxTravel = trackH - thumbH
                if maxTravel <= 0 then return end
                local maxScroll = math.max(0, sfChild:GetHeight() - sf:GetHeight())
                local newScroll = sDragStartScroll + (dy / maxTravel) * maxScroll
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateSThumb()
            end)

            -- Create checkbox items
            local checkItems = {}
            for i, me in ipairs(moduleEntries) do
                local item = CreateFrame("Button", nil, sfChild)
                item:SetHeight(POPUP_ITEM_H)
                item:SetPoint("TOPLEFT", sfChild, "TOPLEFT", 1, -(i - 1) * POPUP_ITEM_H)
                item:SetPoint("TOPRIGHT", sfChild, "TOPRIGHT", -1, -(i - 1) * POPUP_ITEM_H)

                local hl = item:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0)

                local cb = CreateFrame("Frame", nil, item)
                cb:SetSize(14, 14)
                cb:SetPoint("LEFT", item, "LEFT", 10, 0)
                local cbBg = cb:CreateTexture(nil, "BACKGROUND")
                cbBg:SetAllPoints()
                cbBg:SetColorTexture(0.06, 0.06, 0.08, 1)
                EllesmereUI.MakeBorder(cb, 1, 1, 1, 0.12, PP)
                local cbCheck = cb:CreateTexture(nil, "OVERLAY")
                cbCheck:SetSize(10, 10)
                cbCheck:SetPoint("CENTER")
                cbCheck:SetColorTexture(eg.r, eg.g, eg.b, 1)
                cbCheck:Hide()
                item._cbCheck = cbCheck

                local lbl2 = item:CreateFontString(nil, "OVERLAY")
                lbl2:SetFont(fontPath, 11, outlineFlag)
                lbl2:SetTextColor(0.75, 0.75, 0.78, 1)
                lbl2:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                lbl2:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                lbl2:SetJustifyH("LEFT")
                lbl2:SetWordWrap(false)
                lbl2:SetText(EllesmereUI.L(me.display))

                item:SetScript("OnClick", function()
                    selectedModuleMap[i] = not selectedModuleMap[i]
                    cbCheck:SetShown(selectedModuleMap[i] == true)
                    ddLbl:SetText(GetSelectedLabel())
                end)
                item:SetScript("OnEnter", function()
                    lbl2:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, 0.08)
                end)
                item:SetScript("OnLeave", function()
                    lbl2:SetTextColor(0.75, 0.75, 0.78, 1)
                    hl:SetColorTexture(1, 1, 1, 0)
                end)
                checkItems[i] = item
                item._moduleName = me.display
            end
            sfChild:SetHeight(math.max(1, #moduleEntries * POPUP_ITEM_H))

            -- Search filtering
            searchBox:SetScript("OnTextChanged", function(self)
                local t = strlower(strtrim(self:GetText()))
                sPlaceholder:SetShown(t == "")
                local visIdx = 0
                for idx, item in ipairs(checkItems) do
                    if t == "" or strfind(strlower(item._moduleName), t, 1, true) then
                        item:Show()
                        item:ClearAllPoints()
                        item:SetPoint("TOPLEFT", sfChild, "TOPLEFT", 1, -visIdx * POPUP_ITEM_H)
                        item:SetPoint("TOPRIGHT", sfChild, "TOPRIGHT", -1, -visIdx * POPUP_ITEM_H)
                        visIdx = visIdx + 1
                    else
                        item:Hide()
                    end
                end
                sfChild:SetHeight(math.max(1, visIdx * POPUP_ITEM_H))
                sf:SetVerticalScroll(0)
                sScrollTarget = 0
            end)

            popup:SetScript("OnShow", function()
                popup:ClearAllPoints()
                popup:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                searchBox:SetText("")
                searchBox:SetFocus()
                sScrollTarget = 0
                sSmoothing = false
                sSmoothFrame:Hide()
                sf:SetVerticalScroll(0)
                UpdateSThumb()
                for i, item in ipairs(checkItems) do
                    item._cbCheck:SetShown(selectedModuleMap[i] == true)
                end
            end)
            popup:SetScript("OnUpdate", function()
                if not popup:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    popup:Hide()
                end
            end)

            ddBtn:SetScript("OnClick", function()
                if popup:IsShown() then popup:Hide() else popup:Show() end
            end)
            ddBtn:SetScript("OnEnter", function()
                ddBg:SetColorTexture(0.095, 0.143, 0.181, 1)
            end)
            ddBtn:SetScript("OnLeave", function()
                ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            end)

            -----------------------------------------------------------
            --  "Add Module Font" button (profile-row style)
            -----------------------------------------------------------
            local _c = EllesmereUI.WB_COLOURS
            local MF_BTN_COLOURS = {
                _c[1],  _c[2],  _c[3],  _c[4],   _c[5],  _c[6],  _c[7],  _c[8],
                1, 1, 1, EllesmereUI.DD_BRD_A,   1, 1, 1, EllesmereUI.DD_BRD_HA,
                _c[17], _c[18], _c[19], _c[20],  _c[21], _c[22], _c[23], _c[24],
            }

            local addBtn = CreateFrame("Button", nil, mfRow)
            PP.Size(addBtn, BTN_W, ITEM_H)
            PP.Point(addBtn, "LEFT", ddBtn, "RIGHT", GAP, 0)
            addBtn:SetFrameLevel(mfRow:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(addBtn, "Add Module Font", 11, MF_BTN_COLOURS, function()
                -- Collect selected modules
                local toAdd = {}
                for i, me in ipairs(moduleEntries) do
                    if selectedModuleMap[i] then
                        toAdd[#toAdd + 1] = { folder = me.folder, display = me.display }
                    end
                end
                if #toAdd == 0 then
                    -- Pulse red border on dropdown to indicate nothing selected
                    if not ddBtn._redPulse then
                        local rf = CreateFrame("Frame", nil, ddBtn)
                        rf:SetAllPoints()
                        rf:SetFrameLevel(ddBtn:GetFrameLevel() + 10)
                        local border = EllesmereUI.MakeBorder(rf, 1, 0.2, 0.2, 1, PP)
                        rf._border = border
                        ddBtn._redPulse = rf
                    end
                    local rf = ddBtn._redPulse
                    rf:Show()
                    rf:SetAlpha(1)
                    local elapsed2 = 0
                    rf:SetScript("OnUpdate", function(self, dt)
                        elapsed2 = elapsed2 + dt
                        if elapsed2 < 0.8 then
                            self:SetAlpha(0.5 + 0.5 * math.sin(elapsed2 * 10))
                        elseif elapsed2 < 1.5 then
                            self:SetAlpha(math.max(0, 1 - (elapsed2 - 0.8) / 0.7))
                        else
                            self:SetScript("OnUpdate", nil)
                            self:Hide()
                        end
                    end)
                    return
                end

                -- Add each selected module (skip duplicates)
                local fontsDB = EllesmereUI.GetFontsDB()
                if not fontsDB.moduleFonts then fontsDB.moduleFonts = {} end
                for _, info in ipairs(toAdd) do
                    local exists = false
                    for _, existing in ipairs(fontsDB.moduleFonts) do
                        if existing.folder == info.folder then exists = true; break end
                    end
                    if not exists then
                        fontsDB.moduleFonts[#fontsDB.moduleFonts + 1] = {
                            folder  = info.folder,
                            display = info.display,
                            font    = "__global",
                            outline = "__global",
                        }
                    end
                end

                -- Reset selection
                wipe(selectedModuleMap)
                ddLbl:SetText(EllesmereUI.L("Select Module"))
                popup:Hide()

                -- Full page rebuild so content height updates
                EllesmereUI:RefreshPage(true)
            end)

            y = y - ROW_H

            -----------------------------------------------------------
            --  Module font override list (dynamic, rebuilt on add/remove)
            -----------------------------------------------------------
            local listContainer = CreateFrame("Frame", nil, parent)
            listContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
            listContainer:SetSize(parent:GetWidth() or 400, 1)

            local listRows = {}

            -- Assigned to forward-declared local above
            RebuildModuleFontList = function()
                for _, row in ipairs(listRows) do row:Hide() end
                wipe(listRows)

                local fontsDB = EllesmereUI.GetFontsDB()
                local mfList = fontsDB.moduleFonts or {}

                if #mfList == 0 then
                    listContainer:SetHeight(1)
                    return 0
                end

                local totalH = 0

                -- Font dropdown values/order (shared across all rows)
                local mfFontValues, mfFontOrder = EllesmereUI.BuildFontDropdownData()

                -- Outline dropdown values/order
                local outlineValues = {
                    ["__global"] = { text = "EUI Global Outline" },
                    ["none"]     = { text = "Drop Shadow" },
                    ["outline"]  = { text = "Outline" },
                    ["thick"]    = { text = "Thick Outline" },
                }
                local outlineOrder = { "__global", "none", "outline", "thick" }

                for idx, entry in ipairs(mfList) do
                    local capturedIdx = idx

                    -- Use W:DualRow for the standard label-left / dropdown-right layout
                    local dualRow, dualH
                    dualRow, dualH = W:DualRow(listContainer, -totalH,
                        { type = "dropdown", text = EllesmereUI.Lf("%1$s Font", EllesmereUI.L(entry.display)),
                          values = mfFontValues, order = mfFontOrder,
                          getValue = function()
                              local fdb = EllesmereUI.GetFontsDB()
                              if fdb.moduleFonts and fdb.moduleFonts[capturedIdx] then
                                  return fdb.moduleFonts[capturedIdx].font or "__global"
                              end
                              return "__global"
                          end,
                          setValue = function(v)
                              local fdb = EllesmereUI.GetFontsDB()
                              if fdb.moduleFonts and fdb.moduleFonts[capturedIdx] then
                                  fdb.moduleFonts[capturedIdx].font = v
                              end
                              FontReload()
                          end },
                        { type = "dropdown", text = EllesmereUI.Lf("%1$s Outline", EllesmereUI.L(entry.display)),
                          values = outlineValues, order = outlineOrder,
                          getValue = function()
                              local fdb = EllesmereUI.GetFontsDB()
                              if fdb.moduleFonts and fdb.moduleFonts[capturedIdx] then
                                  return fdb.moduleFonts[capturedIdx].outline or "__global"
                              end
                              return "__global"
                          end,
                          setValue = function(v)
                              local fdb = EllesmereUI.GetFontsDB()
                              if fdb.moduleFonts and fdb.moduleFonts[capturedIdx] then
                                  fdb.moduleFonts[capturedIdx].outline = v
                              end
                              FontReload()
                          end })

                    -- Add delete X button on the far left of the row
                    local ICON_SIZE = 14
                    local delBtn = CreateFrame("Button", nil, dualRow)
                    delBtn:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
                    PP.Point(delBtn, "LEFT", dualRow, "LEFT", 14, 0)
                    delBtn:SetFrameLevel(dualRow:GetFrameLevel() + 5)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    PP.Size(delIcon, ICON_SIZE, ICON_SIZE)
                    PP.Point(delIcon, "CENTER", delBtn, "CENTER", 0, 0)
                    if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
                    delIcon:SetTexture(EllesmereUI.MEDIA_PATH .. "icons\\eui-close.png")
                    delBtn:SetAlpha(0.75)
                    delBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
                    delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.75) end)
                    delBtn:SetScript("OnClick", function()
                        local fdb = EllesmereUI.GetFontsDB()
                        local needsReload = false
                        if fdb.moduleFonts then
                            -- Only a reload is needed when the removed entry actually
                            -- overrode the font/outline (reverting to global changes
                            -- rendering). A still-global row is a no-op.
                            local e = fdb.moduleFonts[capturedIdx]
                            if e and ((e.font and e.font ~= "__global") or (e.outline and e.outline ~= "__global")) then
                                needsReload = true
                            end
                            table.remove(fdb.moduleFonts, capturedIdx)
                        end
                        EllesmereUI:RefreshPage(true)
                        if needsReload then FontReload() end
                    end)

                    -- Shift left-half label right so it clears the X button
                    local leftLabel = dualRow._leftRegion and dualRow._leftRegion._label
                    if leftLabel then
                        leftLabel:ClearAllPoints()
                        PP.Point(leftLabel, "LEFT", delBtn, "RIGHT", 4, 0)
                    end

                    listRows[#listRows + 1] = dualRow
                    totalH = totalH + dualH
                end

                listContainer:SetHeight(totalH)
                return totalH
            end

            -- Initial build
            local listH = RebuildModuleFontList()
            y = y - (listH or 0)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  DARK MODE section (per-profile)
        --  One palette drives the Dark Mode look of Unit Frames, Raid Frames and
        --  Resource Bars (Resource Bars ignore the opacity sliders). The three
        --  "Darken" sliders blacken the class / power / class-resource colours set
        --  below; the adjustment is applied inside the colour getters so it reaches
        --  every module with no per-module wiring. Always per-profile (not subject
        --  to "Apply to All Profiles").
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DARK MODE", y);  y = y - h
        do
            local DM_DEF = EllesmereUI.DEFAULT_DARK_MODE

            -- Master switches, each a pure view over its group of per-module
            -- providers (on only when every provider in the group is on). The left
            -- toggle drives Unit Frames + Raid Frames; the right drives the class
            -- resource bar alone, so users can dark one without the other.
            local function _dmIsRB(p) return p.id == "resourceBars" end
            local function _dmNotRB(p) return p.id ~= "resourceBars" end
            _, h = W:DualRow(parent, y,
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
                      -- Force rebuild: the toggle flips the dropdown's enabled state
                      -- and the editing-gate, which a fast-path refresh won't redo.
                      EllesmereUI:RefreshPage(true)
                  end },
                -- Global-mode source: which single profile's palette every profile
                -- uses. Enabled only while "Apply to All Profiles" is ON; in
                -- per-profile mode each profile uses its own, so it's disabled.
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
        -- Colour-edit gate: when this profile mirrors another profile's colours
        -- (GLOBAL mode on a different profile), each section's grid below gets its
        -- OWN click-blocking overlay (built at the end of this page builder),
        -- mirroring the Raid Frames party-tab sync overlays. Per-section grid
        -- bounds {top, bot} are captured into _colorGates as the sections lay out.
        local _colorGates = {}
        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CLASS COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CLASS COLORS", y);  y = y - h
        _colorGates[1] = { top = y }

        local classItems = {}
        for _, token in ipairs(CLASS_ORDER) do
            -- Class names are Blizzard-localized in every client language; use
            -- the client's own names, falling back to our English labels.
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
            -- Power names are Blizzard global strings (already localized); fall
            -- back to our English labels for non-standard entries (e.g. Ebon Might).
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
        --  CLASS RESOURCE COLORS section
        --  Standalone swatches, mirrors the POWER COLORS pattern. Saved under
        --  the "classResource" custom-colors category; nothing consumes that
        --  category yet, so these are set up but not wired to anything.
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CLASS RESOURCE COLORS", y);  y = y - h
        _colorGates[3] = { top = y }
        do
            -- Order + labels only; default colors live in the shared
            -- EllesmereUI.DEFAULT_CLASS_RESOURCE_COLORS so the resource bar's
            -- "Class Resource Color" fill mode reads the same source.
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

        -- Colour-edit gate: in GLOBAL mode the shared palette comes from ONE
        -- profile; while viewing a different profile, block editing here (those
        -- colours aren't the ones in use). ONE overlay PER SECTION, each sized to
        -- that section's grid, mirroring the Raid Frames party-tab "Synced with
        -- Raid Settings" overlays (instead of a single sheet over all three).
        -- Always created; a shared refresh callback shows/hides them + updates the
        -- message, so they stay correct after a profile or global-source change
        -- even when the page is served from cache.
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

    -- Builds a red warning string from a decoded payload's meta vs current client.
    -- Returns nil if no mismatch. skipScale: the user already accepted the
    -- scale-mismatch popup (their scale will change to match on import), so
    -- the UI-scale line is omitted; the resolution line still shows.
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

    -- Between the string/preset page and the import options page: when the
    -- string carries a UI scale different from the user's, ask ONCE whether
    -- to adopt it. cont(applyScale) ALWAYS runs -- true = apply the imported
    -- scale on import (the options page then omits its UI-scale warning
    -- line), false = keep the user's own scale (warning still shows).
    -- ShowConfirmPopup routes ESC/click-outside to onCancel, so the page
    -- transition can never strand.
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

        -- Safety net: verify the active profile matches the current spec
        -- assignment. If the user opens settings while on the wrong profile
        -- (e.g. spec info was unavailable at login), correct it now.
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
                            EllesmereUI.RefreshAllAddons()
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

        local presetsPage = CreateFrame("Frame", nil, root)
        presetsPage:SetAllPoints(root)
        presetsPage:SetFrameLevel(root:GetFrameLevel())
        presetsPage:Hide()

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

        local function UniquePresetName(baseName)
            local _, profiles = EllesmereUI.GetProfileList()
            if not profiles[baseName] then return baseName end
            local n = 2
            while profiles[baseName .. " " .. n] do n = n + 1 end
            return baseName .. " " .. n
        end

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

        local function DoPresetImportFlow(exportString, defaultName, editModeString, editModeLayoutName)
            if not exportString then return end
            -- Preset strings decode across frames like the paste flow; a
            -- repeat click just restarts the (idempotent) decode.
            EllesmereUI.DecodeImportStringAsync(exportString, function(payload, err)
                if not payload then
                    EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Failed"), content = err or EllesmereUI.L("Invalid preset data.") })
                    return
                end
                MaybeConfirmUIScale(payload, function(applyScale)
                    ShowImportPage(exportString, payload, defaultName or "Preset Profile", editModeString, editModeLayoutName, applyScale)
                end)
            end)
        end

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

            -- Optional Blizzard Edit Mode layout to apply alongside this import
            -- (preset path only; the manual paste path leaves these nil).
            importPage._editModeString     = editModeString
            importPage._editModeLayoutName = editModeLayoutName

            local scaleWarnText = BuildScaleWarning(payload, applyImportedScale)
            local includedAddons = {}
            if payload and payload.data and payload.data.addons then
                for folder in pairs(payload.data.addons) do
                    includedAddons[folder] = true
                end
            end

            -- Does this string carry spec->profile assignments? Only then do we
            -- show the "Auto Assign to Specs" toggle (and grow the footer to fit a
            -- second stacked row). Strings without assignments keep the compact
            -- single-row footer.
            local hasSpecAssign = payload and payload.data
                and type(payload.data.assignedSpecs) == "table"
                and #payload.data.assignedSpecs > 0

            -- Does this string carry a UI scale? Only new-format full exports do
            -- (old profiles have none). The adopt/keep decision was already made
            -- via the MaybeConfirmUIScale popup shown before this page
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
            -- The optional Auto Assign toggle stacks below the
            -- count/Include-layout row and adds a row of height.
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
                EllesmereUIMythicTimer       = "A simple Mythic+ timer with full tracking customizations.",
                EllesmereUIQuestTracker      = "A clean, updated reskin of Blizzard's Quest Tracker.",
                EllesmereUIMinimap           = "A new age minimap with clean styling and square layout options.",
                EllesmereUIDamageMeters      = "Lightweight damage meters with simple but powerful customization.",
                EllesmereUIChat              = "Modern chat enhancements with useful utilities.",
                EllesmereUIBags              = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
            }

            local iy = -30

            -- Back button (arrow + "Back" label)
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

            -- Title (centered)
            local titleFs = EllesmereUI.MakeFont(importPage, 16, nil, 1, 1, 1, 0.95)
            PP.Point(titleFs, "TOP", importPage, "TOP", 0, iy - BACK_H / 2 + 8)
            titleFs:SetText(EllesmereUI.Lf("Importing %1$s", (defaultName or EllesmereUI.L("Profile"))))
            titleFs:SetJustifyH("CENTER")

            iy = iy - BACK_H - 8

            -- Scale/resolution warning (red, below title)
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

            -- Profile Name input row
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
            local autoAssignImport = false       -- "Auto Assign to Specs" toggle (default off)
            local importVisuals = {}
            local importCountFs
            local importComponents   -- canon folder -> { component member set }, set below
            local importCanImport = {}
            local CANON_DISPLAY = {}  -- canon folder -> display name (for the linked tooltip)

            local addonItems = {}
            for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
                local folder = entry.folder
                -- Payload keys are CANONICAL (suite folder names); selectedImports
                -- is keyed by canon so it matches the payload + the strip loop in
                -- both suite and standalone builds. "loaded"/"desc" stay on the
                -- LOCAL folder so only this build's installed module is checkable.
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
                    -- Hard-couple: checking/unchecking a module sets its whole
                    -- connected component together (modules linked by anchor/size-
                    -- match relationships), gated to importable members.
                    setVal    = function(v)
                        -- Layout OFF: relationships aren't being imported, so
                        -- don't hard-couple linked modules -- each module becomes
                        -- independently selectable, letting a single linked addon
                        -- be imported on its own.
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

            -- Module connectivity from the payload's layout + meta (both CANONICAL,
            -- matching selectedImports' keyspace). Drives the hard-couple above and
            -- the "linked" row affordance. stale={} -- sender already pruned dead edges.
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

            -- Pre-compute scroll height
            local SCROLL_MAX_H = 285
            local contentH = #addonItems * ROW_H_A
            local scrollH = math.min(contentH, SCROLL_MAX_H)
            local SECTION_H = HDR_H + COL_HDR_H + scrollH + 8 + FOOTER_H

            -- Background panel
            local sectionBg = CreateFrame("Frame", nil, importPage)
            sectionBg:SetFrameLevel(importPage:GetFrameLevel())
            PP.Size(sectionBg, totalW, SECTION_H)
            PP.Point(sectionBg, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            sectionBg:EnableMouse(false)
            local sBgTex = sectionBg:CreateTexture(nil, "BACKGROUND")
            sBgTex:SetAllPoints()
            sBgTex:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(sectionBg, 1, 1, 1, 0.10, PP)

            -- Section header
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

            -- Select All / Deselect All
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

                -- Hook into refresh cycle
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

            -- Column headers
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
                        -- Linked-modules tooltip so the co-toggle isn't mysterious.
                        -- Suppressed while layout is off, since nothing couples then.
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
            -- With any secondary toggle present the footer carries stacked rows, so
            -- the count + "Include layout" sit on the upper row; otherwise they stay
            -- vertically centered as before.
            if nFooterStack > 0 then
                PP.Point(importCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
            else
                PP.Point(importCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
            end
            importCountFs:SetJustifyH("LEFT")
            RefreshImportCount()

            -- "Include layout" toggle: off = don't import any anchor/size-match
            -- relationships (your existing layout is left untouched).
            local layoutChkBtn
            do
                local ilBtn = CreateFrame("Button", nil, footerFrame)
                ilBtn:SetSize(150, 24)
                PP.Point(ilBtn, "LEFT", importCountFs, "RIGHT", 24, 0)
                local box = CreateFrame("Frame", nil, ilBtn)
                box:SetSize(CHK_SZ, CHK_SZ)
                box:SetPoint("LEFT", ilBtn, "LEFT", 0, 0)
                local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
                bg:SetColorTexture(0.12, 0.12, 0.14, 1)
                EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                local mark = box:CreateTexture(nil, "ARTWORK")
                mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                local lbl = EllesmereUI.MakeFont(ilBtn, 12, nil, 1, 1, 1, 0.6)
                lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
                lbl:SetText(EllesmereUI.L("Include layout"))
                local function vis() mark:SetShown(includeLayoutImport) end
                vis()
                ilBtn:SetScript("OnClick", function() includeLayoutImport = not includeLayoutImport; vis() end)
                ilBtn:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(ilBtn, EllesmereUI.L("Import the anchor & size-match relationships from this profile. Off = keep your own layout; only the selected modules' own positions/settings come in."))
                end)
                ilBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                layoutChkBtn = ilBtn
            end

            -- Secondary toggles stack downward from the Include-layout row.
            local lastFooterStack = layoutChkBtn

            -- "Auto Assign to Specs" toggle: only shown when the string carries
            -- spec->profile assignments. Off (default) = the recipient's own spec
            -- assignments are left untouched. On = each spec the profile was
            -- assigned to on export is pointed at this newly imported profile.
            if hasSpecAssign and layoutChkBtn then
                local aaBtn = CreateFrame("Button", nil, footerFrame)
                aaBtn:SetSize(180, 24)
                PP.Point(aaBtn, "TOPLEFT", lastFooterStack, "BOTTOMLEFT", 0, -4)
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
                lastFooterStack = aaBtn
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

                -- Block duplicate profile names
                local _, existingProfiles = EllesmereUI.GetProfileList()
                if existingProfiles and existingProfiles[name] then
                    EllesmereUI:ShowConfirmPopup({
                        title = EllesmereUI.L("Name Taken"),
                        message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                        confirmText = EllesmereUI.L("OK"),
                        hideCancel = true,
                        onConfirm = function() end,
                    })
                    return
                end

                -- Build the filtered import payload on a private deep copy of
                -- the already-decoded payload: the strips below mutate it, and
                -- the page must stay re-importable after a failed attempt.
                -- (Re-decoding exportString here would re-run the whole codec.)
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
                -- CDM spell allocation is top-level (the per-module loop above doesn't
                -- catch it). Keep it ONLY if the CDM module is selected for import; if
                -- CDM is not being imported, spell layouts are never applied. When kept,
                -- every spec in the string imports as-is (no spec picker -- see commit below).
                if filteredPayload and filteredPayload.data then
                    if not selectedImports["EllesmereUICooldownManager"] then
                        filteredPayload.data.cdmSpells = nil
                    end
                end
                -- Spec->profile assignments: top-level, applied by ImportProfile
                -- when present. Drop wholesale unless the "Auto Assign to Specs"
                -- toggle is on (default off, so the recipient's own assignments are
                -- left untouched).
                if filteredPayload and filteredPayload.data and not autoAssignImport then
                    filteredPayload.data.assignedSpecs = nil
                end
                -- UI scale (account-wide): applied by ImportProfile ONLY when this
                -- opt-in marker is set -- the user accepted the scale-mismatch
                -- popup (MaybeConfirmUIScale) shown before this page. Declined
                -- or matching scales set nothing and keep the user's own scale.
                if filteredPayload and filteredPayload.data and hasUIScale and applyImportedScale then
                    filteredPayload.data.applyUIScale = true
                end
                -- Layout relationships: keep only the anchor/size-match
                -- relationships whose BOTH endpoints are in the selected modules
                -- (per-element graph filter), using the payload's keyToFolder meta.
                -- selectedImports and the meta values are both CANONICAL, so they
                -- compare directly. stale={} because the sender already pruned dead
                -- edges at export and the recipient's registry is irrelevant here.
                -- The "Include layout" toggle (includeLayoutImport) drops it wholesale.
                if filteredPayload and filteredPayload.data then
                    local ul = filteredPayload.data.unlockLayout
                    if ul and includeLayoutImport then
                        local meta = filteredPayload.data.unlockLayoutMeta
                        -- payload meta wins; static resolver fills any gaps (and ALL
                        -- keys for an old, meta-less string) so we never drop the
                        -- whole layout for lack of classification.
                        local k2f = EllesmereUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
                        filteredPayload.data.unlockLayout =
                            EllesmereUI.FilterLayoutToFolders(ul, selectedImports, k2f)
                    else
                        filteredPayload.data.unlockLayout = nil
                    end
                    -- Meta is transient -- never overlay/persist it into the profile.
                    filteredPayload.data.unlockLayoutMeta = nil
                end
                -- fonts, customColors, euiAccent are profile-global appearance the
                -- module checkboxes can't gate. On a partial import keep the
                -- recipient's by dropping them (a nil leaves the base copy intact).
                if isPartialImport and filteredPayload and filteredPayload.data then
                    filteredPayload.data.fonts        = nil
                    filteredPayload.data.customColors = nil
                    filteredPayload.data.euiAccent    = nil
                    -- Overrides are per-module (they ride with their addon):
                    -- the exporter's cross-module unlock layout forks never
                    -- come along on a subset import, and the marker tells the
                    -- store merge to keep the recipient's forks and partition
                    -- value entries by imported folder (see
                    -- SpecOverrides_MergeImportedStores).
                    filteredPayload.data.specUnlockOverrides = nil
                    filteredPayload.data.condUnlockOverrides = nil
                    filteredPayload.data.partialImport = true
                end
                -- The unlock-layer FORKS are whole cross-module position
                -- layers: the "Include layout" toggle must gate them exactly
                -- like unlockLayout above, or unchecking it still lets the
                -- exporter's forks wipe/replace the recipient's group layouts
                -- (ApplyLayer then rewrites live anchors and CDM/AB bar
                -- positions from the exporter's fork on the next apply).
                -- layoutExcluded tells the store merge to KEEP the
                -- recipient's forks (nil incoming must not read as "wipe").
                if filteredPayload and filteredPayload.data and not includeLayoutImport then
                    filteredPayload.data.specUnlockOverrides = nil
                    filteredPayload.data.condUnlockOverrides = nil
                    filteredPayload.data.layoutExcluded = true
                end

                local function commit()
                    -- The payload table goes to ImportProfile directly; the
                    -- old encode-to-string round trip re-ran the entire codec
                    -- on data that was already decoded.
                    local ok, err, status = EllesmereUI.ImportProfile(filteredPayload, name)
                    -- Apply the preset's Blizzard Edit Mode layout (if one was supplied)
                    -- right before the reload, so the profile + layout land together.
                    -- pcall-guarded so a Blizzard-side Edit Mode error can never block
                    -- the reload -- the EUI profile still applies. No-op for the manual
                    -- paste path (no stored edit-mode string).
                    if ok and importPage._editModeString then
                        pcall(EllesmereUI.ApplyPresetEditMode, importPage._editModeString, importPage._editModeLayoutName)
                    end
                    if ok and status == "spec_locked" then
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

                -- CDM spell layouts (when the CDM module is selected, gated above)
                -- import as-is. No spec picker: CDM spells are per-profile (stored
                -- under spellAssignments.profiles[profileName]), so the import only
                -- populates the NEW imported profile's store -- other profiles are
                -- untouched and nothing is overwritten. Importing every spec in the
                -- string is strictly beneficial -- any spec NOT in the string just
                -- falls back to default bars, which is what a fresh profile gets anyway.
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

            -- Hide every other page so the import page never overlaps the one it
            -- was opened from (main paste flow, or a preset card via DoPresetImportFlow).
            mainPage:Hide()
            pastePage:Hide()
            presetsPage:Hide()
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

            -- Back button (arrow + "Back" label)
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

            -- Title (centered)
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

            -- Large pastes are absorbed into a buffer (attached after the
            -- handlers above so their scripts are preserved): the box only
            -- ever holds a short summary line, which keeps the paste instant
            -- and removes the old letter-cap truncation on huge strings.
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
                -- Decode across frames: lock the button and show progress so
                -- the client stays responsive on very large strings.
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
                        -- The user may have navigated away mid-decode; a
                        -- stale run's result is simply dropped.
                        if not pastePage:IsVisible() then return end
                        if not payload then
                            EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Failed"), content = err or EllesmereUI.L("Invalid import string.") })
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
        --  PRESETS PAGE (Popular Presets browser)
        -------------------------------------------------------------------
        local function ShowPresetsPage()
            for _, child in ipairs({ presetsPage:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end

            local PAD = EllesmereUI.CONTENT_PAD
            local py = -30

            -- Back button (arrow + "Back" label)
            local BACK_W, BACK_H = 80, 32
            local backBtn = CreateFrame("Button", nil, presetsPage)
            PP.Size(backBtn, BACK_W, BACK_H)
            PP.Point(backBtn, "TOPLEFT", presetsPage, "TOPLEFT", PAD, py)
            backBtn:SetFrameLevel(presetsPage:GetFrameLevel() + 2)

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
                presetsPage:Hide()
                mainPage:Show()
            end)

            -- Title + subtitle (centered)
            local titleFs = EllesmereUI.MakeFont(presetsPage, 16, nil, 1, 1, 1, 0.95)
            PP.Point(titleFs, "TOP", presetsPage, "TOP", 0, py - BACK_H / 2 + 23)
            titleFs:SetText(EllesmereUI.L("Popular Presets"))
            titleFs:SetJustifyH("CENTER")

            local subFs = EllesmereUI.MakeFont(presetsPage, 12, nil, 1, 1, 1, 0.40)
            PP.Point(subFs, "TOP", titleFs, "BOTTOM", 0, -6)
            subFs:SetText(EllesmereUI.L("Handcrafted UI setups ready to import."))
            subFs:SetJustifyH("CENTER")

            local totalW  = presetsPage:GetWidth() - PAD * 2
            local DB      = EllesmereUI.DARK_BG
            local presets = EllesmereUI.POPULAR_PRESETS or {}

            -- Selected preset, shared by the hero card actions (built below) and
            -- the grid. Declared here so the hero import controls can read it.
            -- RefreshPresetActions is assigned inside the hero control do-block and
            -- called from UpdateHero to refresh the import/copy button enabled state.
            local current
            local RefreshPresetActions

            -- Green-accent action button (matches the import / continue buttons)
            local function MakeGreenButton(parent, w, btnH, text)
                local btn = CreateFrame("Button", nil, parent)
                PP.Size(btn, w, btnH)
                btn:SetFrameLevel(parent:GetFrameLevel() + 2)
                local brd = EllesmereUI.MakeBorder(btn, EG.r, EG.g, EG.b, 0.7, PP)
                local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
                bg:SetAllPoints()
                local lbl = EllesmereUI.MakeFont(btn, 12, nil, EG.r, EG.g, EG.b)
                lbl:SetAlpha(0.7)
                lbl:SetPoint("CENTER")
                lbl:SetText(EllesmereUI.L(text))
                local prog, target = 0, 0
                local FADE = 0.1
                local lerp = EllesmereUI.lerp
                local function Apply(t)
                    lbl:SetTextColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
                    brd:SetColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
                end
                local function OnUpd(self, elapsed)
                    local dir = (target == 1) and 1 or -1
                    prog = prog + dir * (elapsed / FADE)
                    if (dir == 1 and prog >= 1) or (dir == -1 and prog <= 0) then
                        prog = target; self:SetScript("OnUpdate", nil)
                    end
                    Apply(prog)
                end
                btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpd) end)
                btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpd) end)
                return btn
            end

            ----------------------------------------------------------------
            --  HERO CARD (always visible -- shows the selected preset)
            ----------------------------------------------------------------
            -- Shared image aspect ratio (width : height) for the hero preview and
            -- the grid tile previews, so the same screenshot shows identically in
            -- both. Each image's height is derived from its own width, then the
            -- card heights from those. ~2.15 balances a taller hero against shorter
            -- tiles while keeping the overall hero + 2-row stack height unchanged.
            local IMG_PAD    = 16
            local IMG_ASPECT = 2.15
            local heroImgW   = math.floor(totalW * 0.50)
            local heroImgH   = math.floor(heroImgW / IMG_ASPECT + 0.5)
            local HERO_H     = heroImgH + IMG_PAD * 2
            local heroTop    = py - BACK_H - 17
            local hero = CreateFrame("Frame", nil, presetsPage)
            PP.Size(hero, totalW, HERO_H)
            PP.Point(hero, "TOPLEFT", presetsPage, "TOPLEFT", PAD, heroTop)
            local heroBg = hero:CreateTexture(nil, "BACKGROUND")
            heroBg:SetAllPoints()
            heroBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(hero, 1, 1, 1, 0.12, PP)

            -- Hero image (left). Dimensions computed above from IMG_ASPECT.
            local heroImgHolder = CreateFrame("Frame", nil, hero)
            PP.Size(heroImgHolder, heroImgW, heroImgH)
            PP.Point(heroImgHolder, "TOPLEFT", hero, "TOPLEFT", IMG_PAD, -IMG_PAD)
            local heroImg = heroImgHolder:CreateTexture(nil, "ARTWORK")
            heroImg:SetAllPoints()
            if heroImg.SetSnapToPixelGrid then heroImg:SetSnapToPixelGrid(false); heroImg:SetTexelSnappingBias(0) end
            EllesmereUI.MakeBorder(heroImgHolder, 1, 1, 1, 0.12, PP)

            -- Hero detail column (right)
            local detailX = IMG_PAD + heroImgW + 28
            local detailW = totalW - 26 - detailX

            local isRussian = GetLocale() == "ruRU"
            local heroNameY = isRussian and -18 or -22
            local byLblGap = isRussian and -4 or -7
            local descGap = isRussian and -6 or -12
            local descHeight = isRussian and 50 or 32
            local tagGap = isRussian and -6 or -12

            local heroName = EllesmereUI.MakeFont(hero, 20, nil, 1, 1, 1, 0.95)
            PP.Point(heroName, "TOPLEFT", hero, "TOPLEFT", detailX, heroNameY)
            heroName:SetJustifyH("LEFT")
            heroName:SetWordWrap(false)

            local heroByLbl = EllesmereUI.MakeFont(hero, 13, nil, 1, 1, 1, 0.40)
            PP.Point(heroByLbl, "TOPLEFT", heroName, "BOTTOMLEFT", 0, byLblGap)
            heroByLbl:SetText(EllesmereUI.L("by"))
            local heroAuthor = EllesmereUI.MakeFont(hero, 13, nil, EG.r, EG.g, EG.b)
            PP.Point(heroAuthor, "LEFT", heroByLbl, "RIGHT", 5, 0)

            local heroDesc = EllesmereUI.MakeFont(hero, 12, nil, 1, 1, 1, 0.55)
            PP.Point(heroDesc, "TOPLEFT", heroByLbl, "BOTTOMLEFT", 0, descGap)
            PP.Size(heroDesc, detailW, descHeight)
            heroDesc:SetJustifyH("LEFT")
            heroDesc:SetJustifyV("TOP")
            heroDesc:SetWordWrap(true)

            -- Tag pills row (rebuilt per selection)
            local tagRow = CreateFrame("Frame", nil, hero)
            PP.Size(tagRow, detailW, 22)
            PP.Point(tagRow, "TOPLEFT", heroDesc, "BOTTOMLEFT", 0, tagGap)
            local tagPills = {}
            local function BuildTagPills(tags)
                for _, p in ipairs(tagPills) do p:Hide(); p:SetParent(nil) end
                wipe(tagPills)
                local tx = 0
                local ty = 0
                for _, tag in ipairs(tags or {}) do
                    local pill = CreateFrame("Frame", nil, tagRow)
                    local pf = EllesmereUI.MakeFont(pill, 11, nil, 1, 1, 1, 0.6)
                    pf:SetPoint("CENTER")
                    pf:SetText(EllesmereUI.L(tag))
                    local pw = math.floor(pf:GetStringWidth() + 0.5) + 22
                    if tx > 0 and tx + pw > detailW then
                        tx = 0
                        ty = ty - 28
                    end
                    PP.Size(pill, pw, 22)
                    PP.Point(pill, "TOPLEFT", tagRow, "TOPLEFT", tx, ty)
                    local pbg = pill:CreateTexture(nil, "BACKGROUND")
                    pbg:SetAllPoints()
                    pbg:SetColorTexture(0.06, 0.08, 0.10, 0.6)
                    EllesmereUI.MakeBorder(pill, 1, 1, 1, 0.15, PP)
                    tagPills[#tagPills + 1] = pill
                    tx = tx + pw + 8
                end
            end

            -- Hero import controls: two side-by-side import buttons -- "Import
            -- 1080p" (left) and "Import 2K (1440p)" (right) -- pinned flush with the
            -- bottom of the hero image. The button matching the user's physical
            -- resolution is accent-colored (green); the other is neutral. The
            -- UI-scale variant (.64 vs .53) is auto-picked from the user's scale.
            -- Wrapped in a do-block so its helper locals stay scoped here; current
            -- and RefreshPresetActions are upvalues declared at the top of this page.
            do
                local CTRL_H  = 28
                local BTN_GAP = 12
                local primW   = math.floor((detailW - BTN_GAP) / 2)

                local function UserUIScale()
                    return (EllesmereUIDB and EllesmereUIDB.ppUIScale) or (UIParent and UIParent:GetScale()) or 1
                end

                -- Closest usable UI-scale variant string from a { s64=, s53= } table.
                local function PickScale(tbl)
                    if type(tbl) ~= "table" then return nil end
                    local s = UserUIScale()
                    local d64, d53 = math.abs(s - 0.64), math.abs(s - 0.5333333333)
                    local firstK, secondK
                    if d64 <= d53 then firstK, secondK = "s64", "s53" else firstK, secondK = "s53", "s64" end
                    local function usable(v) return type(v) == "string" and v ~= "" end
                    if usable(tbl[firstK]) then return tbl[firstK]
                    elseif usable(tbl[secondK]) then return tbl[secondK] end
                    return nil
                end

                -- EUI profile import string for the current preset + a resolution key.
                local function ImportStringFor(resKey)
                    if not current or type(current.import) ~= "table" then return nil end
                    return PickScale(current.import[resKey])
                end

                -- Blizzard Edit Mode layout string for the current preset + resolution.
                local function EditModeStringFor(resKey)
                    if not current or type(current.editMode) ~= "table" then return nil end
                    return PickScale(current.editMode[resKey])
                end

                local function DoImport(resKey)
                    local str = ImportStringFor(resKey)
                    if not str then
                        EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Not Available Yet"),
                            content = EllesmereUI.Lf("%1$s is not available to import for that resolution yet.", (current and current.name) or EllesmereUI.L("This preset")) })
                        return
                    end
                    -- Apply the matching Blizzard Edit Mode layout alongside the EUI
                    -- profile -- it is applied at the import commit, just before the
                    -- single reload. The import page shows its own scale/resolution
                    -- warning from the string's embedded meta.
                    local editStr  = EditModeStringFor(resKey)
                    local editName = "EUI " .. current.name
                    DoPresetImportFlow(str, current.name, editStr, editName)
                end

                -- The button matching the user's physical resolution is accent-colored.
                local is1440
                do
                    local _, physH = GetPhysicalScreenSize()
                    physH = physH or 1080
                    is1440 = math.abs(physH - 1440) < math.abs(physH - 1080)
                end

                -- Build one import button, accent (green) or neutral, OnClick wired.
                local function MakeImportBtn(accent, text, resKey)
                    local b
                    if accent then
                        b = MakeGreenButton(hero, primW, CTRL_H, text)
                        b:SetScript("OnClick", function() DoImport(resKey) end)
                    else
                        b = CreateFrame("Button", nil, hero)
                        PP.Size(b, primW, CTRL_H)
                        b:SetFrameLevel(hero:GetFrameLevel() + 2)
                        EllesmereUI.MakeStyledButton(b, text, 11, PROF_BTN_COLOURS, function() DoImport(resKey) end)
                    end
                    return b
                end

                -- 1080p (left) + 2K (right), bottom flush with the hero image.
                local btn1080 = MakeImportBtn(not is1440, EllesmereUI.L("Import 1080p"), "p1080")
                PP.Point(btn1080, "BOTTOMLEFT", heroImgHolder, "BOTTOMLEFT", detailX - IMG_PAD, 0)
                local btn2k = MakeImportBtn(is1440, EllesmereUI.L("Import 2K (1440p)"), "p1440")
                PP.Point(btn2k, "LEFT", btn1080, "RIGHT", BTN_GAP, 0)

                -- Dim a button when the current preset has no string for its
                -- resolution. Called from UpdateHero on preset change.
                RefreshPresetActions = function()
                    btn1080:SetAlpha(ImportStringFor("p1080") and 1 or 0.4)
                    btn2k:SetAlpha(ImportStringFor("p1440") and 1 or 0.4)
                end
            end

            ----------------------------------------------------------------
            --  GRID (scrollable -- the other presets)
            ----------------------------------------------------------------
            local gridTop = heroTop - HERO_H - 16
            local gridClip = CreateFrame("Frame", nil, presetsPage)
            PP.Point(gridClip, "TOPLEFT", presetsPage, "TOPLEFT", PAD, gridTop)
            PP.Point(gridClip, "BOTTOMRIGHT", presetsPage, "BOTTOMRIGHT", -PAD, 10)
            gridClip:SetClipsChildren(true)

            local gridSF = CreateFrame("ScrollFrame", nil, gridClip)
            gridSF:SetAllPoints()
            local gridChild = CreateFrame("Frame", nil, gridSF)
            gridChild:SetSize(totalW, 10)
            gridSF:SetScrollChild(gridChild)

            local COLS       = 4
            local CARD_GAP   = 14
            local cardW      = math.floor((totalW - CARD_GAP * (COLS - 1)) / COLS)
            local CARD_IMG_H = math.floor(cardW / IMG_ASPECT + 0.5)  -- same aspect as the hero
            local CARD_H     = CARD_IMG_H + 46
            local GRID_BOT_PAD = 12

            local gridCards  = {}
            local UpdateHero, RebuildGrid, SelectPreset

            -- 30% black overlay on every card EXCEPT the selected one. Each tile
            -- fades its own overlay out over 0.25s on hover and back in on leave.
            local OVERLAY_MAX  = 0.30
            local OVERLAY_FADE = 0.25

            local function MakeGridCard(preset, col, row)
                local x  = col * (cardW + CARD_GAP)
                local yy = row * (CARD_H + CARD_GAP)
                local card = CreateFrame("Button", nil, gridChild)
                PP.Size(card, cardW, CARD_H)
                PP.Point(card, "TOPLEFT", gridChild, "TOPLEFT", x, -yy)
                card:SetFrameLevel(gridChild:GetFrameLevel() + 2)

                local bg = card:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
                local brd = EllesmereUI.MakeBorder(card, 1, 1, 1, 0.12, PP)

                local imgHolder = CreateFrame("Frame", nil, card)
                PP.Size(imgHolder, cardW - 2, CARD_IMG_H)
                PP.Point(imgHolder, "TOPLEFT", card, "TOPLEFT", 1, -1)
                local img = imgHolder:CreateTexture(nil, "ARTWORK")
                img:SetAllPoints()
                img:SetTexture(preset.image)
                if img.SetSnapToPixelGrid then img:SetSnapToPixelGrid(false); img:SetTexelSnappingBias(0) end

                -- Author (top-right of the text bar)
                local authFs = EllesmereUI.MakeFont(card, 11, nil, EG.r, EG.g, EG.b)
                PP.Point(authFs, "TOPRIGHT", imgHolder, "BOTTOMRIGHT", -12, -10)
                authFs:SetJustifyH("RIGHT")
                authFs:SetWordWrap(false)
                authFs:SetText(preset.author or "")

                -- Name (top-left), capped so it never collides with the author
                local nameFs = EllesmereUI.MakeFont(card, 14, nil, 1, 1, 1, 0.9)
                PP.Point(nameFs, "TOPLEFT", imgHolder, "BOTTOMLEFT", 12, -9)
                PP.Point(nameFs, "RIGHT", authFs, "LEFT", -8, 0)
                nameFs:SetJustifyH("LEFT")
                nameFs:SetWordWrap(false)
                nameFs:SetText(EllesmereUI.L(preset.name))

                -- Truncated one-line description under the name (matches the
                -- preset's full description; clips with an ellipsis to one line)
                local descFs = EllesmereUI.MakeFont(card, 11, nil, 1, 1, 1, 0.40)
                PP.Point(descFs, "TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
                PP.Point(descFs, "RIGHT", imgHolder, "BOTTOMRIGHT", -12, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetMaxLines(1)
                descFs:SetText(EllesmereUI.L(preset.description or ""))

                -- 40% black overlay above the whole card (image + text bar).
                -- Higher frame level so it covers the image's child frame too.
                local overlay = CreateFrame("Frame", nil, card)
                overlay:SetAllPoints(card)
                overlay:SetFrameLevel(card:GetFrameLevel() + 10)
                overlay:EnableMouse(false)
                local ovTex = overlay:CreateTexture(nil, "OVERLAY")
                ovTex:SetAllPoints()
                ovTex:SetColorTexture(0, 0, 0, 1)
                card.preset   = preset
                card._overlay = overlay

                -- Per-tile overlay fade (own OnUpdate, cleared once settled)
                local hovered  = false
                local ovAlpha  = (preset == current) and 0 or OVERLAY_MAX
                local ovTarget = ovAlpha
                overlay:SetAlpha(ovAlpha)
                local function OvOnUpdate(self, dt)
                    local rate = OVERLAY_MAX / OVERLAY_FADE
                    if ovAlpha < ovTarget then
                        ovAlpha = math.min(ovTarget, ovAlpha + rate * dt)
                    else
                        ovAlpha = math.max(ovTarget, ovAlpha - rate * dt)
                    end
                    overlay:SetAlpha(ovAlpha)
                    if ovAlpha == ovTarget then self:SetScript("OnUpdate", nil) end
                end

                -- Visual state: selected (green border) vs hovered vs idle,
                -- plus the per-tile overlay fade target.
                local function Refresh()
                    if preset == current then
                        brd:SetColor(EG.r, EG.g, EG.b, hovered and 0.9 or 0.7)
                        bg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                        nameFs:SetAlpha(1)
                    elseif hovered then
                        brd:SetColor(1, 1, 1, 0.22)
                        bg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                        nameFs:SetAlpha(1)
                    else
                        brd:SetColor(1, 1, 1, 0.12)
                        bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
                        nameFs:SetAlpha(0.9)
                    end
                    local t = (preset == current or hovered) and 0 or OVERLAY_MAX
                    if t ~= ovTarget then
                        ovTarget = t
                        overlay:SetScript("OnUpdate", OvOnUpdate)
                    end
                end
                card._refresh = Refresh

                card:SetScript("OnEnter", function() hovered = true; Refresh() end)
                card:SetScript("OnLeave", function() hovered = false; Refresh() end)
                card:SetScript("OnClick", function() SelectPreset(preset) end)
                Refresh()
                return card
            end

            RebuildGrid = function()
                for _, c in ipairs(gridCards) do c:Hide(); c:SetParent(nil) end
                wipe(gridCards)
                for i, preset in ipairs(presets) do
                    gridCards[#gridCards + 1] = MakeGridCard(preset, (i - 1) % COLS, math.floor((i - 1) / COLS))
                end
                local rows = math.ceil(#presets / COLS)
                local contentH = rows > 0 and (rows * (CARD_H + CARD_GAP) - CARD_GAP + GRID_BOT_PAD) or 10
                gridChild:SetSize(totalW, math.max(contentH, 10))
                gridSF:SetVerticalScroll(0)
            end

            -- Overlay scrollbar + smooth scroll (matches the options panels)
            local SCROLL_STEP  = 60
            local SMOOTH_SPEED = 12
            local scrollTarget = 0
            local isSmoothing  = false
            local smoothFrame  = CreateFrame("Frame")
            smoothFrame:Hide()

            -- Parented to presetsPage (not gridClip) so it isn't clipped, and
            -- sits just right of the tiles' edge with its top flush to the grid.
            local scrollTrack = CreateFrame("Frame", nil, presetsPage)
            scrollTrack:SetWidth(4)
            scrollTrack:SetPoint("TOPLEFT", gridClip, "TOPRIGHT", 6, 0)
            scrollTrack:SetPoint("BOTTOMLEFT", gridClip, "BOTTOMRIGHT", 6, 0)
            scrollTrack:SetFrameLevel(gridClip:GetFrameLevel() + 60)
            scrollTrack:Hide()
            local trackBg = EllesmereUI.SolidTex(scrollTrack, "BACKGROUND", 1, 1, 1, 0.02)
            trackBg:SetAllPoints()

            local scrollThumb = CreateFrame("Button", nil, scrollTrack)
            scrollThumb:SetWidth(4)
            scrollThumb:SetHeight(60)
            scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
            scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
            scrollThumb:EnableMouse(true)
            scrollThumb:RegisterForDrag("LeftButton")
            scrollThumb:SetScript("OnDragStart", function() end)
            scrollThumb:SetScript("OnDragStop", function() end)
            local thumbTex = EllesmereUI.SolidTex(scrollThumb, "ARTWORK", 1, 1, 1, 0.27)
            thumbTex:SetAllPoints()

            local isDragging = false
            local dragStartY, dragStartScroll

            local function UpdateThumb()
                local maxScroll = EllesmereUI.SafeScrollRange(gridSF)
                if maxScroll <= 0 then scrollTrack:Hide(); return end
                scrollTrack:Show()
                local trackH = scrollTrack:GetHeight()
                local visH = gridSF:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(30, trackH * ratio)
                scrollThumb:SetHeight(thumbH)
                local scrollRatio = (tonumber(gridSF:GetVerticalScroll()) or 0) / maxScroll
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
            end

            smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = gridSF:GetVerticalScroll()
                local maxScroll = EllesmereUI.SafeScrollRange(gridSF)
                scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                local diff = scrollTarget - cur
                if math.abs(diff) < 0.3 then
                    gridSF:SetVerticalScroll(scrollTarget)
                    UpdateThumb()
                    isSmoothing = false
                    smoothFrame:Hide()
                    return
                end
                local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                gridSF:SetVerticalScroll(newScroll)
                UpdateThumb()
            end)

            local function SmoothScrollTo(target)
                local maxScroll = EllesmereUI.SafeScrollRange(gridSF)
                scrollTarget = math.max(0, math.min(maxScroll, target))
                if not isSmoothing then
                    isSmoothing = true
                    smoothFrame:Show()
                end
            end

            gridClip:EnableMouseWheel(true)
            gridClip:SetScript("OnMouseWheel", function(_, delta)
                local maxScroll = EllesmereUI.SafeScrollRange(gridSF)
                if maxScroll <= 0 then return end
                local base = isSmoothing and scrollTarget or gridSF:GetVerticalScroll()
                SmoothScrollTo(base - delta * SCROLL_STEP)
            end)
            gridSF:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

            local function StopDrag()
                if not isDragging then return end
                isDragging = false
                scrollThumb:SetScript("OnUpdate", nil)
            end
            scrollThumb:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                isSmoothing = false; smoothFrame:Hide()
                isDragging = true
                local _, cy = GetCursorPosition()
                dragStartY = cy / self:GetEffectiveScale()
                dragStartScroll = gridSF:GetVerticalScroll()
                self:SetScript("OnUpdate", function(self2)
                    if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
                    isSmoothing = false; smoothFrame:Hide()
                    local _, cy2 = GetCursorPosition()
                    cy2 = cy2 / self2:GetEffectiveScale()
                    local deltaY = dragStartY - cy2
                    local trackH = scrollTrack:GetHeight()
                    local maxTravel = trackH - self2:GetHeight()
                    if maxTravel <= 0 then return end
                    local maxScroll = EllesmereUI.SafeScrollRange(gridSF)
                    local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxTravel) * maxScroll))
                    scrollTarget = newScroll
                    gridSF:SetVerticalScroll(newScroll)
                    UpdateThumb()
                end)
            end)
            scrollThumb:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then StopDrag() end
            end)


            UpdateHero = function(preset)
                if not preset then return end
                heroImg:SetTexture(preset.image)
                heroName:SetText(EllesmereUI.L(preset.name or ""))
                heroAuthor:SetText(preset.author or "")
                heroDesc:SetText(EllesmereUI.L(preset.description or ""))
                BuildTagPills(preset.tags)
                if RefreshPresetActions then RefreshPresetActions() end
            end

            SelectPreset = function(preset)
                current = preset
                UpdateHero(preset)
                for _, c in ipairs(gridCards) do
                    if c._refresh then c._refresh() end
                end
            end

            current = presets[1]
            UpdateHero(current)
            RebuildGrid()

            mainPage:Hide()
            presetsPage:Show()
        end

        -------------------------------------------------------------------
        --  TOP SECTION: Export | Import | Popular Presets (3 action cards)
        -------------------------------------------------------------------
        _, h = W:Spacer(parent, y, 10);  y = y - h

        do
            local CARD_H     = 66
            local CARD_GAP   = 14
            local CARD_ICON  = 26
            local totalW     = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            local CARD_W     = math.floor((totalW - CARD_GAP * 2) / 3)

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

            -- Export Profile
            local cardX = 0
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\export.png",
                EllesmereUI.L("Export Full Profile"), EllesmereUI.L("Export your current profile."), function()
                    local activeName = EllesmereUI.GetActiveProfileName()
                    -- A full-profile export always includes the CDM module, so always
                    -- ask whether to bundle the CDM spell layout (then pick specs).
                    EllesmereUI.RunCDMSpellExportFlow(activeName, function(includeCDM, cdmSpecs)
                        local str = EllesmereUI.ExportCurrentProfile(true, includeCDM, cdmSpecs)
                        if str then EllesmereUI:ShowExportPopup(str) end
                    end)
                end)

            -- Import Profile
            cardX = cardX + CARD_W + CARD_GAP
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\import.png",
                EllesmereUI.L("Import Profile"), EllesmereUI.L("Import a profile from string."), function()
                    ShowPastePage()
                end)

            -- Popular Presets (opens the presets page)
            cardX = cardX + CARD_W + CARD_GAP
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\dark-overlay.png",
                EllesmereUI.L("Popular Presets"), EllesmereUI.L("Browse community presets."), function()
                    ShowPresetsPage()
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
                                EllesmereUI.RefreshAllAddons()
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
                                    -- Invalidate cached option pages so per-profile
                                    -- lists (e.g. the CDM bar dropdown) rebuild from
                                    -- the new profile on next view. A live swap only
                                    -- re-points db.profile; without this the cached
                                    -- pages keep showing the old profile's bars until
                                    -- a /reload. Matches the delete/rename handlers.
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
            -- Single footer row: count + "Include layout" + "Include Global
            -- Settings" side by side, Export button on the right.
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
                EllesmereUIMythicTimer       = "A simple Mythic+ timer with full tracking customizations.",
                EllesmereUIQuestTracker      = "A clean, updated reskin of Blizzard's Quest Tracker.",
                EllesmereUIMinimap           = "A new age minimap with clean styling and square layout options.",
                EllesmereUIDamageMeters      = "Lightweight damage meters with simple but powerful customization.",
                EllesmereUIChat              = "Modern chat enhancements with useful utilities.",
                EllesmereUIBags              = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
            }

            -- Pre-compute scroll height for background panel sizing
            local SCROLL_MAX_H = 285
            local contentH = #ADDON_DB_MAP_LOCAL * ROW_H_A
            local scrollH = math.min(contentH, SCROLL_MAX_H)
            local SECTION_H = HDR_H + COL_HDR_H + scrollH + 8 + FOOTER_H

            -- Background panel for the entire section (non-interactive, behind content)
            local sectionBg = CreateFrame("Frame", nil, parent)
            sectionBg:SetFrameLevel(parent:GetFrameLevel())
            PP.Size(sectionBg, totalW, SECTION_H)
            PP.Point(sectionBg, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            sectionBg:EnableMouse(false)
            local sBg = sectionBg:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(sectionBg, 1, 1, 1, 0.10, PP)

            -- Section header frame
            local hdrFrame = CreateFrame("Frame", nil, parent)
            PP.Size(hdrFrame, totalW, HDR_H)
            PP.Point(hdrFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

            local hdrTitle = EllesmereUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
            PP.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
            hdrTitle:SetText(EllesmereUI.L("Per-Addon Export"))
            hdrTitle:SetJustifyH("LEFT")

            local hdrDesc = EllesmereUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
            PP.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
            PP.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
            hdrDesc:SetText(EllesmereUI.L("Export settings for specific addons only. You can choose which addons to include in your exported profile."))
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
            local includeLayoutExport = true     -- "Include layout" toggle (default on)
            local includeGlobalsExport = true    -- "Include Global Settings" toggle (default on)
            local addonItems = {}
            local addonVisuals = {}
            local footerCountFs
            -- Module connectivity from the LIVE active-profile layout (LOCAL folders,
            -- matching selectedAddons' keyspace). Drives the hard-couple + affordance.
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
                    -- Hard-couple: checking/unchecking a module sets its whole
                    -- connected component together, gated to loaded (exportable)
                    -- members.
                    setVal  = function(v)
                        -- Layout OFF: the anchor/size-match relationships aren't
                        -- being exported, so don't hard-couple linked modules --
                        -- each module becomes independently selectable, letting a
                        -- single linked addon be exported on its own.
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

            -- Select All / Deselect All links (right side of header)
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

            -- Column headers
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
                        -- Hard-couple co-toggles a whole connected component, so
                        -- repaint EVERY row (not just this one) -- the sibling
                        -- checkboxes lighting up together is the "linked" affordance.
                        RefreshAllAddonVisuals()
                    end)
                    clickBtn:SetScript("OnEnter", function()
                        hoverTex:Show()
                        if not item.getVal() then nameFs:SetAlpha(0.75) end
                        -- Linked-modules tooltip so the co-toggle isn't mysterious.
                        -- Suppressed while layout is off, since nothing couples then.
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
            -- Top row of the two stacked footer rows (count + Include layout).
            PP.Point(footerCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
            footerCountFs:SetJustifyH("LEFT")
            RefreshFooterCount()

            -- "Include layout" toggle: off = no anchor/size-match relationships are
            -- exported (each module lands at its own saved position, untied).
            local layoutChkBtn
            do
                local ilBtn = CreateFrame("Button", nil, footerFrame)
                ilBtn:SetSize(150, 24)
                PP.Point(ilBtn, "LEFT", footerCountFs, "RIGHT", 24, 0)
                local box = CreateFrame("Frame", nil, ilBtn)
                box:SetSize(CHK_SZ, CHK_SZ)
                box:SetPoint("LEFT", ilBtn, "LEFT", 0, 0)
                local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
                bg:SetColorTexture(0.12, 0.12, 0.14, 1)
                EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                local mark = box:CreateTexture(nil, "ARTWORK")
                mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                local lbl = EllesmereUI.MakeFont(ilBtn, 12, nil, 1, 1, 1, 0.6)
                lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
                lbl:SetText(EllesmereUI.L("Include layout"))
                local function vis() mark:SetShown(includeLayoutExport) end
                vis()
                ilBtn:SetScript("OnClick", function() includeLayoutExport = not includeLayoutExport; vis() end)
                ilBtn:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(ilBtn, EllesmereUI.L("Include the anchor & size-match relationships between modules. Off = export each module's own positions only, with no cross-module tying."))
                end)
                ilBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                layoutChkBtn = ilBtn
            end

            -- "Include Global Settings" toggle: on (default) = the profile-global
            -- appearance (fonts, custom colours, dark mode, accent colour) rides
            -- this per-addon export. Off = only the selected modules' own settings
            -- export, leaving the recipient's global look untouched.
            if layoutChkBtn then
                local gsBtn = CreateFrame("Button", nil, footerFrame)
                gsBtn:SetSize(200, 24)
                -- Beside "Include layout", same row (user directive
                -- 2026-07-16); the 150-wide layout button already carries
                -- its own trailing dead space, so a small gap suffices.
                PP.Point(gsBtn, "LEFT", layoutChkBtn, "RIGHT", 8, 0)
                local box = CreateFrame("Frame", nil, gsBtn)
                box:SetSize(CHK_SZ, CHK_SZ)
                box:SetPoint("LEFT", gsBtn, "LEFT", 0, 0)
                local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
                bg:SetColorTexture(0.12, 0.12, 0.14, 1)
                EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                local mark = box:CreateTexture(nil, "ARTWORK")
                mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                local lbl = EllesmereUI.MakeFont(gsBtn, 12, nil, 1, 1, 1, 0.6)
                lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
                lbl:SetText(EllesmereUI.L("Include Global Settings"))
                local function vis() mark:SetShown(includeGlobalsExport) end
                vis()
                gsBtn:SetScript("OnClick", function() includeGlobalsExport = not includeGlobalsExport; vis() end)
                gsBtn:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(gsBtn, EllesmereUI.L("Include fonts, custom colours, dark mode and accent colour with this export. Off = only the selected modules' own settings export, keeping the recipient's global look."))
                end)
                gsBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end


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
            eaLbl:SetText(EllesmereUI.L("Export Selected Addons"))

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
                local function finishExport(includeCDM, cdmSpecs)
                    local str = EllesmereUI.ExportProfile(activeName, folders, includeLayoutExport, includeCDM, cdmSpecs, includeGlobalsExport)
                    if str then EllesmereUI:ShowExportPopup(str) end
                end
                -- If the CDM module is selected, run the shared flow (ask -> spec
                -- picker); otherwise export straight away with no CDM spell layout.
                if folders["EllesmereUICooldownManager"] then
                    EllesmereUI.RunCDMSpellExportFlow(activeName, finishExport)
                else
                    finishExport(false, nil)
                end
            end)
            exportSelBtn._flashError = BuildErrorFlash(exportSelBtn, eaBrd)

            y = y - FOOTER_H
        end

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

    -- Profiles and Patch Notes are now their own sidebar pages (registered below),
    -- so Global Settings only owns General + Fonts & Colors.
    local globalPages = { PAGE_GENERAL, PAGE_COLORS }

    EllesmereUI:RegisterModule(GLOBAL_KEY, {
        title       = "Global Settings",
        description = "General options for all EllesmereUI addons.",
        pages       = globalPages,
        buildPage   = function(pageName, parent, yOffset)
            -- CleanupProfilesRoot hides/nils the LIVE EllesmereUI._profilesRoot,
            -- not anything scoped to this call's pageName. During an off-screen
            -- search pre-build, pageName cycles through PAGE_GENERAL/PAGE_COLORS
            -- regardless of what the player is really looking at, so this would
            -- otherwise hide the player's real Profiles page out from under them
            -- if it happened to be open. This module's config.pages never
            -- includes PAGE_PROFILES, so pre-build never needs to build it here.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_GENERAL then
                    return BuildGeneralPage(pageName, parent, yOffset)
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
            EllesmereUI.ApplyColorsToOUF()
            -- Reset panel scale to 100%
            if EllesmereUI.SetPanelScale then
                EllesmereUI:SetPanelScale(1.0)
            end
            -- Reset right-click targeting to default (disabled = off)
            if EllesmereUIDB then
                EllesmereUIDB.disableRightClickTarget = false
                EllesmereUIDB.disableRightClickTargetAllyCombat = false
                -- FPS + Secondary Stats are per-profile now; turn them off for the
                -- active profile (QoLExtrasSet) so the visible widgets actually clear.
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
                EllesmereUIDB.suppressErrors = true
                -- Crosshair: the root is the inherited global default, so reset it
                -- here (per-profile overrides are cleared by the profile's own
                -- reset). With the root off, profiles without an override inherit
                -- "None".
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
            if EllesmereUI._applyFPSCounter then
                EllesmereUI._applyFPSCounter()
            end
            if EllesmereUI._applySecondaryStats then
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

    -- Profiles & Presets: its own sidebar module. Reuses the existing
    -- profiles page builder; the profiles-root lifecycle is handled by the
    -- shared CleanupProfilesRoot hooks below (now keyed to PROFILES_KEY).
    -- Second tab: the Spec Overrides management list (built by
    -- EllesmereUI_SpecOverrides.lua).
    local PAGE_SPECOV = "Spec Overrides"
    local PAGE_CONDOV = "Conditional Overrides"
    EllesmereUI:RegisterModule(PROFILES_KEY, {
        title       = "Profiles & Presets",
        description = "Import, export, and switch EllesmereUI profiles and presets.",
        pages       = { PAGE_PROFILES, PAGE_SPECOV, PAGE_CONDOV },
        buildPage   = function(pageName, parent, yOffset)
            -- BuildProfilesPage bypasses `parent` entirely and builds directly
            -- onto the live, shared EllesmereUI._scrollFrame -- and, before it
            -- even gets there, unconditionally checks whether the active
            -- profile matches the player's current spec and, if not, can call
            -- SwitchProfile/RefreshAllAddons and pop a "Reload Required"
            -- confirmation. None of that is safe to trigger from a hidden
            -- indexing pass. Skip PAGE_PROFILES here; it gets indexed normally
            -- the first time the player actually visits it.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_SPECOV then
                    if EllesmereUI.SpecOverrides_BuildListPage then
                        return EllesmereUI.SpecOverrides_BuildListPage(parent, yOffset)
                    end
                    return 200
                end
                return
            end
            if pageName == PAGE_SPECOV then
                CleanupProfilesRoot()
                if EllesmereUI.SpecOverrides_BuildListPage then
                    return EllesmereUI.SpecOverrides_BuildListPage(parent, yOffset)
                end
                return 200
            end
            if pageName == PAGE_CONDOV then
                CleanupProfilesRoot()
                if EllesmereUI.Conditions_BuildListPage then
                    return EllesmereUI.Conditions_BuildListPage(parent, yOffset)
                end
                return 200
            end
            return BuildProfilesPage(pageName, parent, yOffset)
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_SPECOV or pageName == PAGE_CONDOV then
                CleanupProfilesRoot()
                -- The override list changes while the page is cached; rebuild.
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY
                       and EllesmereUI:GetActivePage() == pageName then
                        EllesmereUI:RefreshPage(true)
                    end
                end)
            elseif not EllesmereUI._profilesRoot then
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == PROFILES_KEY then
                        BuildProfilesPage(PAGE_PROFILES, nil, -6)
                    end
                end)
            end
        end,
    })

    -- Patch Notes: its own single-page sidebar module. Suite-only, mirroring the
    -- old suite-only tab (never registered in standalone builds).
    if not IS_STANDALONE then
        EllesmereUI:RegisterModule(PATCHNOTES_KEY, {
            title       = "Patch Notes",
            description = EllesmereUI.L("What's new in EllesmereUI."),
            pages       = { PAGE_WHATSNEW },
            buildPage   = function(pageName, parent, yOffset)
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
