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
        return ((e.module and e.module .. ": ") or "") .. (e.title or "")
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
        descFs:SetText(entry.desc or "")

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
        subFs:SetText(entry.desc or "")

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
        none:SetText("No patch notes yet.")
        return math.abs(y) + 60
    end

    -- Intro hint: centered, with 20px of breathing room above and below.
    y = y - 20
    local hint = MakeFont(parent, 14, nil, 1, 1, 1, 0.5)
    PP.Point(hint, "TOP", parent, "TOP", 0, y)
    hint:SetJustifyH("CENTER")
    hint:SetText("Click any new feature to go directly to the setting")
    y = y - math.ceil(hint:GetStringHeight() or 14) - 20

    for pi, patch in ipairs(patches) do
        -- Version header: large title + a full-width neutral divider (not accent).
        local ver = MakeFont(parent, 20, nil, 1, 1, 1, 0.95)
        PP.Point(ver, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        ver:SetText("EllesmereUI " .. (patch.version or ""))
        local uline = parent:CreateTexture(nil, "ARTWORK")
        uline:SetColorTexture(1, 1, 1, 0.12)
        PP.Size(uline, totalW, 1)
        PP.Point(uline, "TOPLEFT", parent, "TOPLEFT", PAD, y - 32)
        if PP.DisablePixelSnap then PP.DisablePixelSnap(uline) end
        y = y - 48

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

        -- Tier 3: bug-fix lines.
        local fixes = SortByModule(patch.fixes or {})
        if #fixes > 0 then
            local _, sh = W:SectionHeader(parent, "BUG FIXES", y); y = y - sh
            y = y - 10  -- extra spacing below the divider
            for _, fx in ipairs(fixes) do
                local fh = MakeFixLine(y, ((fx.module and fx.module .. ": ") or "") .. (fx.text or "")); y = y - fh
            end
        end

        if pi < #patches then
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
        version = "8.2.6",
        heroes = {
            {
                module = "Cooldown Manager",
                title = "Per-Icon Buff Customization",
                desc  = "Right-click any buff icon to give it its own glow, glow color, duration text, charge and stack text, and visibility, independent of the rest of the bar.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end
                    end },
            },
            {
                module = "Cooldown Manager",
                title = "Add Any Buff to a Buff Bar",
                desc  = "Buff bars now accept preset consumables and custom spell IDs directly. The separate Auras bar type has been merged in, and existing Auras bars convert to buff bars automatically.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end
                    end },
            },
            {
                title = "Performance Optimizations (Glows)",
                desc  = "Every glow effect across the suite now shares a single update driver and uses lighter texture-based animation, noticeably lowering CPU use when many glows are on screen at once.",
                -- No nav: suite-wide automatic improvement, not a single setting.
            },
            {
                module = "Aura Buff Reminders",
                title = "Performance Optimizations",
                desc  = "Aura Buff Reminders now scans your bags once and updates from game events instead of constant polling, lowering CPU use and making consumable and range reminders react instantly.",
                -- No nav: automatic improvement.
            },
        },
        features = {
            {
                module = "Unit Frames",
                title = "Smooth Health Bars",
                desc  = "Health bars can now animate smoothly when health changes instead of snapping, with a per-frame toggle.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "HEALTH BAR", highlight = "Smooth Health Bars",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Damage Meters",
                title = "DPS in Breakdowns",
                desc  = "Per-target and per-source breakdown views now show DPS next to total damage, following your Number Format setting.",
                nav   = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "BAR TEXT", highlight = "Number Format" },
            },
        },
        fixes = {
            { module = "Cooldown Manager", text = "Custom glow type and color now apply to abilities that proc into a second ability, such as a Demon Hunter's Eradicate becoming Reap or a Death Knight's Festering Strike becoming Festering Scythe, instead of falling back to the default glow." },
            { module = "Cooldown Manager", text = "Tracking bar fills now animate smoothly instead of jumping between values." },
            { module = "Resource Bars", text = "Vengeance Demon Hunter Soul Fragment pips show the threshold color again once the configured fragment count is reached." },
            { module = "Unit Frames", text = "Health bar backgrounds no longer turn transparent when Reverse Fill is enabled and the unit takes damage." },
        },
    },
    {
        version = "8.2.4",
        heroes = {
            {
                module = "Nameplates",
                title = "Nameplate Hover Textures",
                desc  = "Mousing over a nameplate can now show a striped or textured highlight overlay instead of a flat color, with several stripe styles to choose from.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "STYLE", highlight = "Hover Texture" },
            },
            {
                module = "Raid Frames",
                title = "Customizable Reduced Max Health",
                desc  = "The reduced max-health overlay on raid frames was a single fixed texture with no options; it now has full style, color, and opacity controls.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "ABSORBS", highlight = "Max Health Style" },
            },
        },
        features = {
            {
                module = "Damage Meters",
                title = "Class-Colored Bar Backgrounds",
                desc  = "A new class-color swatch tints each meter bar's background track with that player's class color, alongside the existing custom color.",
                nav   = { module = "EllesmereUIDamageMeters", page = "Damage Meters", section = "BARS", highlight = "Background" },
            },
            {
                module = "Nameplates",
                title = "Line of Sight Opacity",
                desc  = "A new slider controls how faded a nameplate becomes when its unit is out of your line of sight.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Line of Sight Opacity" },
            },
            {
                module = "General",
                title = "Profiles and Patch Notes Pages",
                desc  = "Profiles & Presets and Patch Notes are now their own entries in the options sidebar instead of tabs inside Global Settings.",
                -- No nav: these are top-level sidebar pages, not a single setting.
            },
            {
                module = "Raid Frames",
                title = "Dispel Overlay Preview",
                desc  = "Preview the raid-frame dispel overlay styling right in the options with a new eye button.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "DISPELS", highlight = "Dispel Overlay" },
            },
        },
        fixes = {
            { module = "Cooldown Manager", text = "Tracking bars for hero-talent override spells now keep showing after the talent is removed, such as a Death Charge bar that keeps tracking once you untalent and cast Death's Advance." },
            { module = "Nameplates", text = "Fixed a Lua error that could occur when mousing over friendly NPC nameplates that have titles such as innkeepers or flight masters." },
            { module = "Raid Frames", text = "Health bar backgrounds set to class color no longer revert to the custom color as a unit's health changes." },
            { module = "Unit Frames", text = "Health bar backgrounds no longer show through the filled portion when you lower the fill opacity, matching how raid frames already behaved." },
            { module = "Cooldown Manager", text = "Bars anchored to another cooldown bar now stay flush against it when you switch to a character or profile whose bar is a different width." },
            { module = "General", text = "The options sidebar addon list now shows a scroll-to-bottom arrow so it is clear the list can scroll." },
        },
    },
    {
        version = "8.2.3",
        heroes = {
            {
                module = "Raid Frames",
                title = "Debuff Wrapping",
                desc  = "Debuffs can wrap into multiple rows, with a set number of icons per row and a chosen wrap direction.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Auras", section = "DEBUFF DISPLAY", highlight = "Per Row" },
            },
            {
                module = "Character Sheet",
                title = "Diminishing Returns in Stat Tooltips",
                desc  = "A new toggle adds diminishing-returns detail to your secondary and tertiary stat tooltips.",
                nav   = { module = "EllesmereUIBlizzardSkin", page = "Character Sheet", section = "STAT DISPLAY", highlight = "Show Diminishing Returns" },
            },
            {
                module = "Unit Frames",
                title = "Upgraded Boss Frames Settings",
                desc  = "Boss frames add a single large side buff column, buff duration text, buff and debuff icon spacing sliders, and a sample cast bar in the preview.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Boss Frames", section = "Buffs and Debuffs", highlight = "Simple Buff Display" },
            },
            {
                module = "Cooldown Manager",
                title = "Always Show Buffs is now Per-Bar",
                desc  = "Always Show Buffs is now a per-bar toggle, so each buff bar can keep its tracked buffs on screen even when they are off cooldown.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "Icon Display", highlight = "Always Show Buffs",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end
                    end },
            },
            {
                module = "Nameplates",
                title = "More Target and Focus Textures",
                desc  = "Target and focus highlight textures can now use any SharedMedia bar texture, not just the built-in stripe patterns.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "TARGET & FOCUS EFFECTS", highlight = "Target Texture" },
            },
            {
                module = "Unit & Raid Frames",
                title = "Class-Colored Background",
                desc  = "Unit and raid frame backgrounds can now use each unit's class color instead of a flat custom color.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "HEALTH BAR", highlight = "Background" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title = "Target-Based Paging",
                desc  = "Action bars can switch pages automatically based on whether you have a friendly or hostile target.",
                nav   = { module = "EllesmereUIActionBars", page = "Bar Display", section = "PAGING", highlight = "Friendly Target",
                    preSelect = function()
                        if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey("MainBar") end
                        EllesmereUI._pendingActionBarSelect = "MainBar"
                    end },
            },
            {
                module = "Raid Frames",
                title = "Right Mouse Camera Unlock",
                desc  = "Hold and drag the right mouse button on a raid or party frame to turn the camera, while a quick right-click still opens the unit menu.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "EXTRAS", highlight = "Right Mouse Camera Unlock" },
            },
            {
                module = "Nameplates",
                title = "Separate Aura Duration Settings",
                desc  = "Debuff, buff, and crowd-control timers now have their own size, color, position, and offset controls.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "GENERAL TEXT", highlight = "Debuff Duration" },
            },
            {
                module = "General",
                title = "Disable Slug Outline",
                desc  = "A single global toggle now controls the slug outline on all UI text instead of separate per-module options.",
                nav   = { module = "_EUIGlobal", page = "Fonts & Colors", section = "GLOBAL FONT", highlight = "Disable Slug Outline" },
            },
            {
                module = "Cooldown Manager",
                title = "Charge Cooldown Edge",
                desc  = "Spells with charges now show a sweeping cooldown edge, with a per-spell option to hide the radial swipe and keep only the edge.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "", highlight = "" },
            },
            {
                module = "Cooldown Manager",
                title = "Active Border Color",
                desc  = "A new per-spell option recolors an icon's border while the tracked spell is active.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "", highlight = "" },
            },
            {
                module = "Nameplates",
                title = "Focus Letter Marker",
                desc  = "Shows a white letter F on your current focus target's nameplate, with options for its position and size.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Focus Letter" },
            },
            {
                module = "Nameplates",
                title = "Experimental: Cast Lockout as CC Icon",
                desc  = "An experimental option shows a successful interrupt's lockout in the crowd-control icon slot.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Experimental: Cast Lockout as CC Icon" },
            },
            {
                module = "Nameplates",
                title = "Hide Enemy Name While Casting",
                desc  = "A new option hides an enemy's name while its cast bar is showing.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Hide Enemy Name While Casting" },
            },
            {
                module = "Raid Frames",
                title = "Private Dispel Overlay Position",
                desc  = "Choose where the private dispel overlay icons grow: top, bottom, or left.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "DISPELS", highlight = "Private Dispel Overlay Position" },
            },
            {
                module = "Raid Frames",
                title = "Hide Private Auras",
                desc  = "A new None option in the private aura position lets you turn off private aura icons on the frames entirely.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Auras", section = "PRIVATE AURAS", highlight = "Position" },
            },
            {
                module = "Raid Frames",
                title = "Out-of-Combat Click Bindings",
                desc  = "Click bindings for the unit menu and for targeting can be limited to out of combat to avoid accidental opens or target changes.",
                -- No nav: lives in the click-cast binding rows (static card).
            },
            {
                module = "Raid Frames",
                title = "Hide All Unit Tooltips in Combat",
                desc  = "The Show in Combat tooltip option now covers every unit tooltip in combat, including nameplates, target, focus, and world mobs.",
                -- No nav: expands an existing toggle (static card).
            },
            {
                module = "Resource Bars",
                title = "Threshold Color Direction",
                desc  = "You can now set whether a resource bar's threshold color shows when the resource is below or above the value.",
                nav   = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "CLASS RESOURCE BAR", highlight = "Threshold & Hash Lines" },
            },
        },
        fixes = {
            { module = "General", text = "Party Mode now activates correctly on flexible Mythic raid boss encounters." },
            { module = "Aura Reminders", text = "Consumable and talent reminders now show in flexible Mythic raids, not just fixed 20-player ones." },
            { module = "Aura Reminders", text = "Talent reminders now cover the new Sporefall raid." },
            { module = "Chat", text = "Sidebar icons you have dragged to custom spots no longer drift out of place after a reload." },
            { module = "Chat", text = "Turning on a sidebar icon that was off now adds it correctly and prompts for a reload when one is needed." },
            { module = "Cooldown Manager", text = "The countdown number no longer gets partly hidden behind the icon border, and its position offset applies reliably." },
            { module = "Cooldown Manager", text = "Custom per-spell settings such as swipe color now save and apply for newly added and Hero talent spells instead of reverting to default." },
            { module = "Cooldown Manager", text = "Clicking a bar's custom border color swatch now turns off class color and opens the color picker in one click instead of leaving the border black." },
            { module = "Cooldown Manager", text = "Pixel glow ant settings are no longer greyed out for glow styles other than Auto-Cast Shine." },
            { module = "Nameplates", text = "Target arrows and side icons no longer leave a gap for the full-size cast icon when nothing is casting." },
            { module = "QoL", text = "The dungeon teleport prompt now closes correctly when you leave an instance while in combat." },
            { module = "Raid Frames", text = "Hovering or clicking a unit where a debuff icon overlaps now passes through correctly so casting and targeting keep working." },
            { module = "Raid Frames", text = "The live party preview now lines up with the real frame position when the growth direction is flipped." },
            { module = "Raid Frames", text = "Custom colors for targeted spell buff squares now show correctly in the preview." },
            { module = "Resource Bars", text = "Smart power text now correctly shows a percentage or a value based on your current power type." },
            { module = "Unit Frames", text = "Buffs and debuffs placed to the left or right of a frame now stay centered on the bar and no longer reserve empty vertical space." },
            { module = "Unit Frames", text = "Power text now matches the resource the bar is actually showing for Druids and Monks when shifting forms or specs." },
            { module = "Unit Frames", text = "Name and text on target-of-target and focus-target frames now show the correct class color instead of staying white." },
            { module = "Unit Frames", text = "Switching the health bar from class color to a custom color now shows the color right away instead of looking unchanged until the color picker is opened." },
            { module = "General", text = "A warning now appears when the Improved Talent Loadouts addon is installed, since it can conflict with the action bars." },
            { module = "Damage Meters", text = "Meter bars and text now follow your custom class colors and update instantly when you change them." },
            { module = "Minimap", text = "The size slider now adjusts in single steps for more precise sizing." },
            { module = "Nameplates", text = "The interrupter's name shown on an interrupted cast is now colored by their class instead of always white." },
            { module = "Quest Tracker", text = "Edit mode is no longer blocked from moving the tracker past the edge of the screen." },
            { module = "Unit Frames", text = "Bar Color and Bar Background controls now grey out while Dark Mode is on, since Dark Mode ignores them." },
            { module = "General", text = "Text size sliders across many modules now go up to 30 for larger, more readable text." },
            { module = "Action Bars", text = "A bar hidden with its visibility toggle keybind no longer reappears when you change targets." },
        },
    },
    {
        version = "8.2.2",
        heroes = {
            {
                module = "QoL",
                title = "LFG Teleport Reminder",
                desc  = "When you join a Group Finder group for a dungeon that has a teleport, a movable popup appears with the dungeon name and a one-click teleport button. It hides itself when you enter the dungeon, leave the group, or drop into combat.",
                nav   = { module = "EllesmereUIQoL", page = "Keys, Logs & Brez", section = "LFG REMINDER", highlight = "Enable LFG Reminder" },
            },
            {
                module = "Nameplates",
                title = "Friendly Plate Controls",
                desc  = "New name-size sliders for friendly players and NPCs in both name-only and full-plate modes, plus a custom bar and name color for friendly NPCs.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "OTHER NAMEPLATES", highlight = "Friendly Name Size" },
            },
            {
                module = "Nameplates",
                title = "Hitbox Upgrades",
                desc  = "A new eyeball button overlays the clickable area on live enemy plates so you can size the hitbox visually, and increasing the vertical size now grows the hitbox evenly above and below the bar instead of only upward.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "ENEMY NAMEPLATE SPACING", highlight = "Hitbox Size X" },
            },
            {
                module = "Nameplates",
                title = "Target Highlight & Textures",
                desc  = "Target highlighting is now three independent toggles (EUI Glow, Border Color, and a new translucent Highlight wash) with a fully colorable border glow, plus four new Target and Focus overlay stripe textures and a per-texture opacity cog.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "TARGET & FOCUS EFFECTS", highlight = "Target Glow Style" },
            },
            {
                module = "Unit & Raid Frames",
                title = "Absorb & Heal Absorb Bars",
                desc  = "New solid strip bars show shield-absorb and heal-absorb amounts, with selectable position, adjustable height, and custom color and transparency. Raid Frames' old absorb toggle is now a position dropdown to match.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "ABSORBS", highlight = "Absorb Bar",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Action Bars",
                title = "Toggle Bar Visibility Keybind",
                desc  = "Assign a key to show or hide an individual action bar on the fly. Bind one key to several bars and it toggles them all together as a synced group. Works out of combat.",
                nav   = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY", highlight = "Toggle Action Bar Visibility" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title = "Desaturate When Not Active",
                desc  = "A new per-spell icon state that greys out the icon whenever the spell is not in its active state.",
                -- No nav: lives in the per-spell cog, no options page to open (static card).
            },
            {
                module = "Cursor",
                title = "Only Show When Hidden",
                desc  = "A new toggle that shows the cursor circle only while you hold the mouse to pan the camera or steer your character.",
                nav   = { module = "EllesmereUIQoL", page = "Cursor", section = "CURSOR", highlight = "Only Show When Hidden" },
            },
            {
                module = "Damage Meters",
                title = "Default on M+ Start",
                desc  = "A per-window setting that switches a meter window to a chosen type, such as Damage, Healing, or Interrupts, when a Mythic+ key starts.",
                -- No nav: lives in the window's in-frame Settings menu (static card).
            },
            {
                module = "General",
                title = "Disable Slug Outline",
                desc  = "A new per-module control that drops the SLUG outline from non-aura text in Unit Frames, Nameplates, and Raid Frames. Aura icon text keeps its outline.",
                nav   = { module = "_EUIGlobal", page = "Fonts & Colors", section = "GLOBAL FONT", highlight = "Disable Slug Outline" },
            },
            {
                module = "Raid Frames",
                title = "Role Icon Upgrades",
                desc  = "A new Modern Light role-icon style and five new role-position anchors: Top, Left, Center, Right, and Bottom.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "INDICATORS", highlight = "Role Icons" },
            },
            {
                module = "Unit Frames",
                title = "New Aura Filters",
                desc  = "Buff and debuff filtering adds Crowd Control, Big Defensive, and External Defensive options.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "BUFFS AND DEBUFFS", highlight = "",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unlock Mode",
                title = "Unlock Mode Upgrades",
                desc  = "The element you are moving now gets a clear white selection overlay so you always know which one the arrow keys will nudge, and the X and Y position boxes move in exact pixels that stay in lockstep with arrow-key nudges.",
                -- No nav: in-world Unlock Mode UI, no options page to open (static card).
            },
        },
        fixes = {
            { module = "Nameplates", text = "Friendly plate borders now render pixel-perfect and follow the same show, size, and color settings as enemy plates." },
            { module = "Nameplates", text = "Mousing off a friendly nameplate now clears its highlight reliably." },
            { module = "Raid Frames", text = "Aura spacing sliders now allow -1 for tighter, overlapping layouts." },
            { module = "Resource Bars", text = "The rune background no longer shows while a rune is recharging, and restores when it is ready." },
        },
    },
    {
        version = "8.2.1",
        heroes = {
            {
                module = "Cooldown Manager",
                title = "Always Show Buffs, Now Per-Bar",
                desc  = "Always Show Buffs is now a per-bar toggle, so each buff bar can independently keep its tracked buffs on screen even when they are off cooldown, with its own option to grey out the inactive ones.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "Icon Display", highlight = "Always Show Buffs",
                    preSelect = function()
                        if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end
                    end },
            },
            {
                module = "Action Bars",
                title = "Two New Action Bars",
                desc  = "Action Bars has two new bars (9 + 10) for all of you demons that need more than 96 slots. Each has its own keybinds and stays hidden until you set its Visibility.",
                nav   = { module = "EllesmereUIActionBars", page = "Bar Display", section = "VISIBILITY", highlight = "Visibility" },
            },
            {
                module = "Unit Frames",
                title = "Heal Absorb Overhaul",
                desc  = "New heal absorb and absorb textures for Unit and Raid Frames: Large Stripes and Outlined Stripes. Unit Frames got a live preview toggle for heal absorbs, and Right/Left edge placement fixes.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "ABSORBS", highlight = "Heal Absorb Style",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Character Sheet",
                title = "Mastery Tooltip",
                desc  = "Hovering Mastery on the character sheet now shows your spec's real mastery (its name and effect, e.g. Mastery: Razor Claws) instead of a generic line.",
                nav   = { module = "EllesmereUIBlizzardSkin", page = "Character Sheet", section = "CORE OPTIONS", highlight = "Enable Character Sheet" },
            },
        },
        features = {
            {
                module = "Action Bars",
                title = "Menu, Bags & XP Bars Tab",
                desc  = "Micro Menu, Bag Bar, and XP and Reputation bar settings now live on their own dedicated options tab.",
                nav   = { module = "EllesmereUIActionBars", page = "Menu, Bags & XP Bars", section = "MICRO MENU & BAGS", highlight = "Micro Menu Visibility" },
            },
            {
                module = "Cooldown Manager",
                title = "Customizable Pixel Glow",
                desc  = "CD and Utility bars get a Pixel Glow Thickness slider plus a cog for Lines and Speed, and the Buff Glow's Pixel Glow gets a matching Lines, Thickness, and Speed cog.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "Icon Display", highlight = "Pixel Glow Thickness" },
            },
            {
                module = "Cooldown Manager",
                title = "Charge & Stack Text Positioning",
                desc  = "Place the charge or stack count in any corner or the center, and preset potions and healthstones now show a sample count in the preview.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "Icon Display", highlight = "Charge/Stack Size" },
            },
            {
                module = "Raid Frames",
                title = "Max Name Length",
                desc  = "A new cog on Name Size caps how many characters of a long unit name show on raid frames.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "TEXT DISPLAY", highlight = "Name Size" },
            },
            {
                module = "Resource Bars",
                title = "Extra Shift Offset",
                desc  = "The Shift Elements if No Resource and No Power settings get a cog with an Extra Y Offset slider to fine-tune how far anchored elements move.",
                nav   = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "BAR DISPLAY", highlight = "Shift Elements if No Resource" },
            },
        },
        fixes = {
            { module = "Cooldown Manager", text = "Adding a tracked buff to a custom buff bar no longer shows a duplicate or a generic icon for talent transformed spells." },
            { module = "Action Bars", text = "A mouseover bar no longer vanishes the instant you drop a spell onto it while your cursor is still over it." },
            { module = "Action Bars", text = "The main bar's page-swap arrows now follow its mouseover fade and visibility settings." },
            { module = "Action Bars", text = "The Pet Bar no longer stays visible after exiting Quick Keybind mode." },
            { module = "Nameplates", text = "Cast bar spell text is no longer hidden behind the border, the unit name sits above aura icons, and raid and elite markers sit beneath them." },
            { module = "Nameplates", text = "Top Left and Top Right auras, raid markers, and classification icons now sit flush against the plate edge." },
            { module = "Aura Reminders", text = "The GCD, Modern, and Classic glow styles now render at the correct size." },
            { module = "Bags", text = "Shift-right-clicking a stack inside a category now shows the split-in-OneBag hint." },
            { module = "Profiles", text = "The profile sync popup now closes when you close the options window." },
        },
    },
    {
        version = "8.2.0",
        heroes = {
            {
                module = "Raid Frames",
                title = "Party Frames in Arena",
                desc  = "Your party frames now show in arenas instead of raid frames, so small-group styling applies and addons that anchor to party frames keep working.",
                -- No nav: automatic behavior with no setting to open (static card).
            },
            {
                module = "Cooldown Manager",
                title = "Tracking Bar Size-Matching",
                desc  = "Cooldown tracking bars can now match the width and height of other interface elements in Unlock Mode.",
                -- No nav: Unlock Mode action with no setting to open (static card).
            },
            {
                module = "Cooldown Manager",
                title = "Group Tracking Bars",
                desc  = "Pick which tracking bars chain together and share width and height, with a per-bar checklist.",
                nav   = { module = "EllesmereUICooldownManager", page = "Tracking Bars", section = "Bar Grouping", highlight = "Group Tracking" },
            },
            {
                module = "Nameplates",
                title = "Cropped Icons",
                desc  = "Make debuff, buff, and crowd-control aura icons rectangular instead of square.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS", highlight = "" },
            },
        },
        features = {
            {
                module = "Cooldown Manager",
                title = "Bloodlust & Heroism Bars",
                desc  = "Add Bloodlust or Heroism to a Custom Auras bar as a self-timed 40-second icon.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "Bar Layout", highlight = "" },
            },
            {
                module = "Nameplates",
                title = "Boss & Neutral Colors",
                desc  = "Bosses get their own color, split from mini-bosses, and neutral enemies get a custom one.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "ENEMY COLORS", highlight = "Enemy Types" },
            },
            {
                module = "Nameplates",
                title = "DPS \"No Aggro\" Color",
                desc  = "Highlight enemies you do not have threat on while in a group.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "THREAT COLORS (INSTANCES ONLY)", highlight = "No Aggro" },
            },
            {
                module = "Resource Bars",
                title = "Player Cast Bar Background",
                desc  = "Set the Player cast bar's background color and opacity.",
                nav   = { module = "EllesmereUIResourceBars", page = "Cast Bar", section = "DISPLAY", highlight = "Background" },
            },
            {
                module = "Nameplates",
                title = "Cast Bar Borders",
                desc  = "Outline enemy cast bars with an adjustable-thickness border in your own color.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "BARS", highlight = "Cast Bar Border" },
            },
        },
        fixes = {
            { module = "Nameplates", text = "Raid target markers now show behind aura icons instead of overlapping them." },
            { module = "Nameplates", text = "Neutral units now show in the enemy-in-combat color while actively in combat." },
            { module = "Nameplates", text = "Aggro color toggles are now clearly labeled \"Tank:\" and \"DPS:\"." },
            { module = "Unit Frames", text = "Cropped aura icons in the options preview now show at the correct height." },
            { module = "Unit Frames", text = "Clicking a buff or debuff icon in the preview to jump to its setting now works after turning buffs on or changing the debuff count." },
            { module = "Unlock Mode", text = "Movers for deleted or hidden elements no longer reappear as ghosts when opening Unlock Mode or after combat." },
            { module = "Unlock Mode", text = "Size-matching to an element that cannot be matched now shows a clear message instead of doing nothing." },
            { module = "Cooldown Manager", text = "Fixed a phantom 40-second Bloodlust bar appearing in the open world after leaving a dungeon while Sated." },
            { module = "Damage Meters", text = "Bars reserve more space for the amount text so numbers stay readable next to long names." },
            { module = "Bloodlust", text = "Fixed the active-buff overlay falsely reappearing when zoning or logging in while Sated." },
            { module = "Raid Frames", text = "Nicknames from raid-tracker addons now show in the standalone build." },
        },
    },
    {
        version = "8.1.9",
        heroes = {},
        features = {
            {
                module = "Bags",
                title = "Quest Item Highlight",
                desc  = "Quest items get a gold border; items that start a quest get a corner marker.",
                nav   = { module = "EllesmereUIBags", page = "Bags", section = "DISPLAY", highlight = "" },
            },
            {
                module = "Minimap",
                title = "Omnium Folio Button",
                desc  = "Adds the expansion landing page (Omnium Folio) button to the minimap, with scale and position controls.",
                nav   = { module = "EllesmereUIMinimap", page = "Minimap", section = "ICONS AND BUTTONS", highlight = "Show Omnium Folio" },
            },
            {
                module = "Nameplates",
                title = "Friendly Names Not Clickable",
                desc  = "Make friendly player and NPC nameplates click-through so their names never block your mouse or cause accidental targeting.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "OTHER NAMEPLATES", highlight = "Friendly Names Not Clickable" },
            },
        },
        fixes = {
            { module = "Action Bars", text = "Spells with charges and on-use trinkets now desaturate correctly while on cooldown." },
            { module = "Bags", text = "Dragging items no longer drops them in the wrong slot when the window scale isn't 100%." },
            { module = "Raid Frames", text = "Boss debuff countdown text now scales consistently with the icon size." },
            { module = "Raid Frames", text = "Non-Left Click bindings work for Targeting players via Hovercast again after the 12.0.7 change." },
            { module = "Nameplates", text = "Scale Target Nameplate is now the only control that resizes your target's plate; at 100% it no longer changes size." },
            { module = "Nameplates", text = "Full-height cast bar spell icon stays flush with the bars as nameplates move." },
            { module = "Auto Logging", text = "Auto combat logging now triggers for current Mythic (Flexible) raids." },
            { module = "Context Menu", text = "Fixed a Lua error when setting focus directly from the right-click menu." },
            { module = "Shifter", text = "Fixed an error sometimes thrown after leaving a group you joined via Group Finder." },
        },
    },
    {
        version = "8.1.7",
        heroes = {
            {
                module = "Raid Frames",
                title = "New Shield & Heal Absorb Styles",
                desc  = "Blizzard's modern layered shield and overshield spark for both damage and heal absorbs.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "ABSORBS", highlight = "Absorb Style" },
            },
            {
                module = "Bags",
                title = "MultiBag View",
                desc  = "Shows one section per equipped bag, with a Default Bag Type dropdown for how bags and the bank open.",
                nav   = { module = "EllesmereUIBags", page = "Bags", section = "DISPLAY", highlight = "Default Bag Type" },
            },
            {
                module = "Nameplates",
                title = "Interrupt-Ready Cast Highlight",
                desc  = "Enemy cast bars shade the moment your interrupt comes off cooldown.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "CAST BAR", highlight = "Cast Color" },
            },
            {
                module = "Bags",
                title = "Auto-Size to Fit",
                desc  = "Grows the bag window so the active tab's slots fit without scrolling, then resets on close.",
                nav   = { module = "EllesmereUIBags", page = "Bags", section = "DISPLAY", highlight = "Auto-Size to Fit" },
            },
            {
                module = "Cooldown Manager",
                title = "Hide Items if Missing",
                desc  = "Hide a bar's consumables entirely when you have none, instead of dimming them.",
                nav   = { module = "EllesmereUICooldownManager", page = "CDM Bars", section = "Extras", highlight = "Hide Items if Missing" },
            },
            {
                module = "Resource Bars",
                title = "Shift Elements if No Power",
                desc  = "Shift power-bar-anchored elements to close the gap when the Power Bar is hidden.",
                nav   = { module = "EllesmereUIResourceBars", page = "Class, Power and Health Bars", section = "BAR DISPLAY", highlight = "Shift Elements if No Power" },
            },
        },
        features = {
            {
                module = "Nameplates",
                title = "Cast Bar Spell Icon Placement",
                desc  = "Move the enemy cast icon to the right, or show it full-height across the bars.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "BARS", highlight = "Spell Icon" },
            },
            {
                module = "Nameplates",
                title = "Quest Objective on Quest Mobs",
                desc  = "Replace the quest crosshair on world quest mobs with the live objective count.",
                nav   = { module = "EllesmereUINameplates", page = "General", section = "EXTRAS", highlight = "Replace Quest Icon with Objective" },
            },
            {
                module = "Nameplates",
                title = "Uninterruptible Cast & Shield",
                desc  = "Give uninterruptible casts their own color, with an optional shield icon.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "CAST BAR", highlight = "Uninterruptible Cast" },
            },
            {
                module = "Nameplates",
                title = "Aura Stacks Text Styling",
                desc  = "Position, color, and size/offset controls for stack text, matching Aura Duration.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "GENERAL TEXT", highlight = "Aura Stacks" },
            },
            {
                module = "Nameplates",
                title = "Important Cast Color",
                desc  = "Tint the cast bar for spells the game flags as important.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "CAST BAR", highlight = "Cast Color" },
            },
            {
                module = "Nameplates",
                title = "Darken Enemies Out of Combat",
                desc  = "Dim enemy nameplate colors until they are in combat.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "ENEMY COLORS", highlight = "Darken Enemies Out of Combat" },
            },
            {
                module = "Nameplates",
                title = "Interrupted Cast Flash",
                desc  = "Flash an enemy's cast bar and show \"Interrupted\" when you kick it.",
                nav   = { module = "EllesmereUINameplates", page = "Colors", section = "CAST BAR", highlight = "Show Interrupted Flash Effect" },
            },
            {
                module = "Nameplates",
                title = "Per-Element Aura Spacing",
                desc  = "Separate icon spacing for debuffs, buffs, and crowd control.",
                nav   = { module = "EllesmereUINameplates", page = "Display", section = "CORE POSITIONS", highlight = "" },
            },
            {
                module = "Unit Frames",
                title = "Aura Max Per Row",
                desc  = "Cap how many buff and debuff icons show per row and wrap the rest onto new rows.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "BUFFS AND DEBUFFS", highlight = "Buff Display",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unit Frames",
                title = "Interrupt-Ready Mid-Cast Bar",
                desc  = "Tint the part of a cast where your interrupt comes off cooldown.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "CAST BAR", highlight = "Show Cast Bar",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("target") end
                        EllesmereUI._pendingUnitSelect = "target"
                    end },
            },
            {
                module = "Unit Frames",
                title = "Cast Bar Background",
                desc  = "Set the cast bar's background color and opacity per frame.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "CAST BAR", highlight = "Bar Background",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Unit Frames",
                title = "Boss Simple Debuff Display",
                desc  = "Stack boss debuffs into one large left- or right-anchored column.",
                nav   = { module = "EllesmereUIUnitFrames", page = "Boss Frames", section = "Buffs and Debuffs", highlight = "Simple Debuff Display" },
            },
            {
                module = "Unit Frames",
                title = "Absorb Short Health Text",
                desc  = "Show absorbs in compact form (e.g. 230k).",
                nav   = { module = "EllesmereUIUnitFrames", page = "Main Frames", section = "HEALTH BAR", highlight = "Left Text",
                    preSelect = function()
                        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit("player") end
                        EllesmereUI._pendingUnitSelect = "player"
                    end },
            },
            {
                module = "Raid Frames",
                title = "Targeted Spells: When Healing",
                desc  = "Auto-enable targeted spells only when you are a healer.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "TARGETED SPELLS", highlight = "Show Targeted Spells" },
            },
            {
                module = "Raid Frames",
                title = "Hide Empty Groups",
                desc  = "Collapse empty raid subgroups so the rest close ranks.",
                nav   = { module = "EllesmereUIRaidFrames", page = "Frames", section = "LAYOUT", highlight = "Show Groups" },
            },
            {
                module = "General",
                title = "Expanded Font Controls",
                desc  = "Apply your font to all game text, outline icon text, and set Raid Frame and Bag fonts.",
                nav   = { module = "_EUIGlobal", page = "Fonts & Colors", section = "GLOBAL FONT", highlight = "Apply to All Game Text" },
            },
            {
                module = "General",
                title = "Font Picker for CJK/Cyrillic",
                desc  = "A working font dropdown for glyph-restricted locales.",
                nav   = { module = "_EUIGlobal", page = "Fonts & Colors", section = "GLOBAL FONT", highlight = "Global Font" },
            },
        },
        fixes = {
            { module = "Nameplates",       text = "Health percent text can now show one decimal place (e.g. 72.4%)." },
            { module = "Nameplates",       text = "Fixed the interrupt tick and interrupt-ready marker flickering during your rotation." },
            { module = "Nameplates",       text = "Fixed the interrupt tick jittering by a pixel as a cast progressed." },
            { module = "Cooldown Manager", text = "Now shows the real spell's keybind when both a macro and the spell are bound." },
            { module = "Cooldown Manager", text = "Racial tracking simplified to a single entry that follows your character's race." },
            { module = "General",          text = "Profile and preset import failures now show a specific reason instead of a generic error." },
            { module = "General",          text = "Right-click unit and raid menus work again after the 12.0.7 change that suppressed them." },
            { module = "General",          text = "Text drop shadows render again across the UI after 12.0.7 stopped showing them." },
            { module = "General",          text = "The sync icon no longer silently skips a unit when reopened." },
            { module = "Chat",             text = "New option to keep chat clamped on-screen, or release it to drag off-screen." },
            { module = "Damage Meters",    text = "Combat timer no longer gets stuck or blanks on chain pulls, wipes, reloads, or when leaving an instance." },
            { module = "Raid Frames",      text = "HoverCast \"Context Menu\" and \"Target\" bindings now actually fire." },
            { module = "Raid Frames",      text = "Custom dispel border colors now show on other players' debuffs inside instances." },
            { module = "Raid Frames",      text = "Hid nuisance debuffs (Arcane Empowerment and Time Trial Practice)." },
            { module = "Resource Bars",    text = "Totem timer text now uses your chosen font instead of the default." },
            { module = "Unit Frames",      text = "Options now keep your scroll position when switching the previewed unit." },
            { module = "Quality of Life",  text = "Secondary Stat Display keeps its custom size when dragged." },
            { module = "Minimap",          text = "Vault and tracker tooltips now use your Minimap font." },
            { module = "Blizzard Skin",    text = "Great Vault now uses your Blizzard Skin font." },
            { module = "Buff Reminders",   text = "Talent Reminders now follow the Aura/Buff Reminders font settings." },
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
        { "floatingCombatTextCombatHealing_v2",             "1"   },
        { "floatingCombatTextCombatDamage_v2",              "1"   },
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
                EllesmereUI:RefreshPage()
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
                ["auto"] = { text = "Automatic (Client)" },
                ["enUS"] = { text = "English" },
                ["deDE"] = { text = "Deutsch" },
                ["frFR"] = { text = "Francais" },
                ["esES"] = { text = "Espanol (EU)" },
                ["esMX"] = { text = "Espanol (LatAm)" },
                ["itIT"] = { text = "Italiano" },
                ["ptBR"] = { text = "Portugues (BR)" },
                ["ruRU"] = { text = "Russian" },
                ["koKR"] = { text = "Korean" },
                ["zhCN"] = { text = "Chinese (Simplified)" },
                ["zhTW"] = { text = "Chinese (Traditional)" },
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
                { type="label", text="" });  y = y - h
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
                    local t = EllesmereUIDB and EllesmereUIDB.outlineIconText
                    return not (t and t[k] == false)
                end,
                function(k, v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not EllesmereUIDB.outlineIconText then EllesmereUIDB.outlineIconText = {} end
                    EllesmereUIDB.outlineIconText[k] = v and true or false
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

        -- Never Show Slug: single global toggle that drops the SLUG token from
        -- every outline the UI produces -- body text and icon/aura text across
        -- all modules, plus the global Outline Mode itself. Off by default, so
        -- slug outlines render as normal. Requires a UI reload.
        do
            local nssRow
            nssRow, h = W:DualRow(parent, y,
                { type="toggle", text="Disable Slug Outline",
                  tooltip="Slug outline renders higher quality outlines compared to the base WoW outline mode but may make outline effects appear slightly thicker.",
                  getValue=function() return EllesmereUIDB and EllesmereUIDB.neverShowSlug == true end,
                  setValue=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.neverShowSlug = v and true or false
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
                        names[#names + 1] = me.display
                    end
                end
                if #names == 0 then return "Select Module" end
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
                lbl2:SetText(me.display)

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
                        { type = "dropdown", text = entry.display .. " Font",
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
                        { type = "dropdown", text = entry.display .. " Outline",
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
        --  CLASS COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CLASS COLORS", y);  y = y - h

        local classItems = {}
        for _, token in ipairs(CLASS_ORDER) do
            local lbl = CLASS_LABELS[token]
            local def = CLASS_COLOR_MAP[token] or { r = 1, g = 1, b = 1 }
            classItems[#classItems + 1] = {
                label = lbl,
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

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  POWER COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "POWER COLORS", y);  y = y - h

        local POWER_ORDER = {
            "MANA", "RAGE", "FOCUS", "ENERGY", "RUNIC_POWER", "FURY",
            "LUNAR_POWER", "INSANITY", "MAELSTROM", "EBON_MIGHT",
        }
        local powerItems = {}
        for _, pk in ipairs(POWER_ORDER) do
            local lbl = POWER_LABELS[pk] or pk
            local def = DEFAULT_POWER_COLORS[pk] or { r = 1, g = 1, b = 1 }
            powerItems[#powerItems + 1] = {
                label = lbl,
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

        _, h = W:Spacer(parent, y, 20);  y = y - h

        return math.abs(y)
    end



    ---------------------------------------------------------------------------
    --  Profiles page
    ---------------------------------------------------------------------------

    -- Builds a red warning string from a decoded payload's meta vs current client.
    -- Returns nil if no mismatch.
    local function BuildScaleWarning(payload)
        if not payload or not payload.meta then return nil end
        local m = payload.meta
        local warnings = {}
        local myScale  = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
        local expScale = m.euiScale or m.uiScale
        if expScale and math.abs(myScale - expScale) > 0.02 then
            local expPct = math.floor(expScale * 100 + 0.5)
            local myPct  = math.floor(myScale  * 100 + 0.5)
            warnings[#warnings + 1] = "UI Scale Issue: Profile was made at " .. expPct .. "%, yours is " .. myPct .. "%"
        end
        local sw, sh = GetPhysicalScreenSize()
        local mySW  = sw and math.floor(sw) or 0
        local mySH  = sh and math.floor(sh) or 0
        local expSW = m.screenW or 0
        local expSH = m.screenH or 0
        if expSW > 0 and expSH > 0 and (mySW ~= expSW or mySH ~= expSH) then
            warnings[#warnings + 1] = "Resolution Issue: Profile was made at " .. expSW .. "x" .. expSH .. ", yours is " .. mySW .. "x" .. mySH
        end
        if #warnings == 0 then return nil end
        return "WARNING: Frame positions may be off.\n" .. table.concat(warnings, "\n")
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
                            EllesmereUI.SwitchProfile(assigned)
                            EllesmereUI.RefreshAllAddons()
                            if fontWillChange then
                                EllesmereUI:ShowConfirmPopup({
                                    title       = "Reload Required",
                                    message     = "Font changed. A UI reload is needed to apply the new font.",
                                    confirmText = "Reload Now",
                                    cancelText  = "Later",
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
            local payload, err = EllesmereUI.DecodeImportString(exportString)
            if not payload then
                EllesmereUI:ShowInfoPopup({ title = "Import Failed", content = err or "Invalid preset data." })
                return
            end
            ShowImportPage(exportString, payload, defaultName or "Preset Profile", editModeString, editModeLayoutName)
        end

        local function FormatKey(key)
            if not key then return "Not Bound" end
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
                EllesmereUI.ShowWidgetTooltip(kbBtn, "Left-click to set a keybind.\nRight-click to unbind.")
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
        ShowImportPage = function(exportString, payload, defaultName, editModeString, editModeLayoutName)
            -- Clear any previous import page content
            for _, child in ipairs({ importPage:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end

            -- Optional Blizzard Edit Mode layout to apply alongside this import
            -- (preset path only; the manual paste path leaves these nil).
            importPage._editModeString     = editModeString
            importPage._editModeLayoutName = editModeLayoutName

            local scaleWarnText = BuildScaleWarning(payload)
            local includedAddons = {}
            if payload and payload.data and payload.data.addons then
                for folder in pairs(payload.data.addons) do
                    includedAddons[folder] = true
                end
            end

            local ADDON_DB_MAP_LOCAL = EllesmereUI._ADDON_DB_MAP
            local PAD        = EllesmereUI.CONTENT_PAD
            local totalW     = importPage:GetWidth() - PAD * 2
            local SIDE_PAD   = 26
            local ROW_H_A    = 48
            local CHK_SZ     = 18
            local STATUS_W   = 70
            local HDR_H      = 72
            local COL_HDR_H  = 28
            local FOOTER_H   = 50
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
                local loaded = C_AddOns.IsAddOnLoaded(folder)
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
                        local members = importComponents and importComponents[canon]
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
                nameFs:SetText(item.display)

                local descFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.30)
                descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
                descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(item.desc)

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
                        local members = importComponents and importComponents[item.canon]
                        if members then
                            local names = {}
                            for f in pairs(members) do
                                if f ~= item.canon then
                                    names[#names + 1] = (CANON_DISPLAY[f] or f)
                                end
                            end
                            if #names > 0 then
                                table.sort(names)
                                EllesmereUI.ShowWidgetTooltip(rowFrame,
                                    "Linked by Anchor/Width/Height Matching to: " .. table.concat(names, ", ")
                                    .. ". These import together.")
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
            PP.Point(importCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
            importCountFs:SetJustifyH("LEFT")
            RefreshImportCount()

            -- "Include layout" toggle: off = don't import any anchor/size-match
            -- relationships (your existing layout is left untouched).
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
                    EllesmereUI.ShowWidgetTooltip(ilBtn, "Import the anchor & size-match relationships from this profile. Off = keep your own layout; only the selected modules' own positions/settings come in.")
                end)
                ilBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
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
                        title = "Name Taken",
                        message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                        confirmText = "OK",
                        hideCancel = true,
                        onConfirm = function() end,
                    })
                    return
                end

                -- Build filtered import string: strip unchecked addons
                local filteredPayload = EllesmereUI.DecodeImportString(exportString)
                local isPartialImport = false
                if filteredPayload and filteredPayload.data and filteredPayload.data.addons then
                    for folder in pairs(filteredPayload.data.addons) do
                        if not selectedImports[folder] then
                            filteredPayload.data.addons[folder] = nil
                            isPartialImport = true
                        end
                    end
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
                end

                local filteredStr = EllesmereUI.EncodePayload(filteredPayload)
                if not filteredStr then
                    EllesmereUI:ShowInfoPopup({ title = "Import Failed", content = "Failed to encode import data." })
                    return
                end

                local ok, err, status = EllesmereUI.ImportProfile(filteredStr, name)
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
                        title   = "Profile Imported",
                        content = "\"" .. name .. "\" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.",
                    })
                    ReloadUI()
                elseif ok then
                    ReloadUI()
                else
                    EllesmereUI:ShowInfoPopup({ title = "Import Failed", content = err or "Unknown error" })
                end
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
            pasteBox:SetMaxLetters(100000)
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
            contBtn:SetScript("OnClick", function()
                local importStr = strtrim(pasteBox:GetText())
                if importStr == "" then return end
                local payload, err = EllesmereUI.DecodeImportString(importStr)
                if not payload then
                    EllesmereUI:ShowInfoPopup({ title = "Import Failed", content = err or "Invalid import string." })
                    return
                end
                pastePage:Hide()
                ShowImportPage(importStr, payload, nil)
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
                lbl:SetText(text)
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

            local heroName = EllesmereUI.MakeFont(hero, 20, nil, 1, 1, 1, 0.95)
            PP.Point(heroName, "TOPLEFT", hero, "TOPLEFT", detailX, -22)
            heroName:SetJustifyH("LEFT")
            heroName:SetWordWrap(false)

            local heroByLbl = EllesmereUI.MakeFont(hero, 13, nil, 1, 1, 1, 0.40)
            PP.Point(heroByLbl, "TOPLEFT", heroName, "BOTTOMLEFT", 0, -7)
            heroByLbl:SetText(EllesmereUI.L("by"))
            local heroAuthor = EllesmereUI.MakeFont(hero, 13, nil, EG.r, EG.g, EG.b)
            PP.Point(heroAuthor, "LEFT", heroByLbl, "RIGHT", 5, 0)

            local heroDesc = EllesmereUI.MakeFont(hero, 12, nil, 1, 1, 1, 0.55)
            PP.Point(heroDesc, "TOPLEFT", heroByLbl, "BOTTOMLEFT", 0, -12)
            PP.Size(heroDesc, detailW, 32)
            heroDesc:SetJustifyH("LEFT")
            heroDesc:SetJustifyV("TOP")
            heroDesc:SetWordWrap(true)

            -- Tag pills row (rebuilt per selection)
            local tagRow = CreateFrame("Frame", nil, hero)
            PP.Size(tagRow, detailW, 22)
            PP.Point(tagRow, "TOPLEFT", heroDesc, "BOTTOMLEFT", 0, -12)
            local tagPills = {}
            local function BuildTagPills(tags)
                for _, p in ipairs(tagPills) do p:Hide(); p:SetParent(nil) end
                wipe(tagPills)
                local tx = 0
                for _, tag in ipairs(tags or {}) do
                    local pill = CreateFrame("Frame", nil, tagRow)
                    local pf = EllesmereUI.MakeFont(pill, 11, nil, 1, 1, 1, 0.6)
                    pf:SetPoint("CENTER")
                    pf:SetText(tag)
                    local pw = math.floor(pf:GetStringWidth() + 0.5) + 22
                    PP.Size(pill, pw, 22)
                    PP.Point(pill, "LEFT", tagRow, "LEFT", tx, 0)
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
                        EllesmereUI:ShowInfoPopup({ title = "Not Available Yet",
                            content = ((current and current.name) or "This preset") .. " is not available to import for that resolution yet." })
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
                local btn1080 = MakeImportBtn(not is1440, "Import 1080p", "p1080")
                PP.Point(btn1080, "BOTTOMLEFT", heroImgHolder, "BOTTOMLEFT", detailX - IMG_PAD, 0)
                local btn2k = MakeImportBtn(is1440, "Import 2K (1440p)", "p1440")
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
                nameFs:SetText(preset.name)

                -- Truncated one-line description under the name (matches the
                -- preset's full description; clips with an ellipsis to one line)
                local descFs = EllesmereUI.MakeFont(card, 11, nil, 1, 1, 1, 0.40)
                PP.Point(descFs, "TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
                PP.Point(descFs, "RIGHT", imgHolder, "BOTTOMRIGHT", -12, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetMaxLines(1)
                descFs:SetText(preset.description or "")

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
                heroName:SetText(preset.name or "")
                heroAuthor:SetText(preset.author or "")
                heroDesc:SetText(preset.description or "")
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
                titleFs:SetText(cardTitle)

                local descFs = EllesmereUI.MakeFont(card, 11, nil, 1, 1, 1, 0.35)
                PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
                PP.Point(descFs, "RIGHT", card, "RIGHT", -14, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(cardDesc)

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
                "Export Full Profile", "Export your current profile.", function()
                    local str = EllesmereUI.ExportCurrentProfile()
                    if str then EllesmereUI:ShowExportPopup(str) end
                end)

            -- Import Profile
            cardX = cardX + CARD_W + CARD_GAP
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\import.png",
                "Import Profile", "Import a profile from string.", function()
                    ShowPastePage()
                end)

            -- Popular Presets (opens the presets page)
            cardX = cardX + CARD_W + CARD_GAP
            MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\dark-overlay.png",
                "Popular Presets", "Browse community presets.", function()
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
                                EllesmereUI.ShowWidgetTooltip(self, "Delete")
                            end)
                            xBtn:SetScript("OnLeave", function(self)
                                InlineBtnLeave(self)
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            editBtn:SetScript("OnEnter", function(self)
                                InlineBtnEnter(self)
                                EllesmereUI.ShowWidgetTooltip(self, "Rename")
                            end)
                            editBtn:SetScript("OnLeave", function(self)
                                InlineBtnLeave(self)
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            kbBtnI:SetScript("OnEnter", function(self)
                                InlineBtnEnter(self)
                                EllesmereUI.ShowWidgetTooltip(self, "Keybind")
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
                                EllesmereUI.ShowWidgetTooltip(itm, "Your current spec has an assigned profile so you cannot switch to another. Please unassign to switch.")
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
                                EllesmereUI.SwitchProfile(capName)
                                ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                EllesmereUI.RefreshAllAddons()
                                if fontWillChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
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
                                    title       = "Delete Profile",
                                    message     = EllesmereUI.Lf("Delete \"%1$s\"?", capName),
                                    confirmText = "Delete",
                                    cancelText  = "Cancel",
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
                                    title       = "Rename Profile",
                                    message     = EllesmereUI.Lf("Enter a new name for \"%1$s\":", capName),
                                    placeholder = capName,
                                    confirmText = "Rename",
                                    cancelText  = "Cancel",
                                    onConfirm   = function(newName)
                                        newName = newName and strtrim(newName) or ""
                                        if newName == "" or newName == capName then return end
                                        if newName == "Default" then
                                            print("|cffff6060[EllesmereUI]|r Cannot rename to \"Default\".")
                                            return
                                        end
                                        local _, profs = EllesmereUI.GetProfileList()
                                        if profs and profs[newName] then
                                            print("|cffff6060[EllesmereUI]|r A profile named \"" .. newName .. "\" already exists.")
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
                    title       = "Copy Profile",
                    message     = "Enter a name for the new profile:",
                    placeholder = "My Profile",
                    confirmText = "Save",
                    cancelText  = "Cancel",
                    onConfirm   = function(name)
                        if not name or name == "" then return end
                        local _, profiles = EllesmereUI.GetProfileList()
                        if profiles and profiles[name] then
                            EllesmereUI:ShowConfirmPopup({
                                title = "Name Taken",
                                message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                                confirmText = "OK",
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
                local loaded = C_AddOns.IsAddOnLoaded(entry.folder)
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
                        local members = exportComponents and exportComponents[folder]
                        if members then
                            for f in pairs(members) do
                                if C_AddOns.IsAddOnLoaded(f) then selectedAddons[f] = v or nil end
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
                nameFs:SetText(item.display)

                -- Addon description
                local descFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.30)
                descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
                descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(item.desc)

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
                        local members = exportComponents and exportComponents[item.folder]
                        if members then
                            local names = {}
                            for f in pairs(members) do
                                if f ~= item.folder then
                                    names[#names + 1] = (FOLDER_DISPLAY[f] or f)
                                end
                            end
                            if #names > 0 then
                                table.sort(names)
                                EllesmereUI.ShowWidgetTooltip(rowFrame,
                                    "Linked by Anchor/Width/Height Matching to: " .. table.concat(names, ", ")
                                    .. ". These export together.")
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
                        EllesmereUI.ShowWidgetTooltip(rowFrame, "Addon not loaded")
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
            PP.Point(footerCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
            footerCountFs:SetJustifyH("LEFT")
            RefreshFooterCount()

            -- "Include layout" toggle: off = no anchor/size-match relationships are
            -- exported (each module lands at its own saved position, untied).
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
                    EllesmereUI.ShowWidgetTooltip(ilBtn, "Include the anchor & size-match relationships between modules. Off = export each module's own positions only, with no cross-module tying.")
                end)
                ilBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
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
                local str = EllesmereUI.ExportProfile(activeName, folders, includeLayoutExport)
                if str then EllesmereUI:ShowExportPopup(str) end
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
                EllesmereUIDB.showFPS = false
                EllesmereUIDB.showSecondaryStats = false
                EllesmereUIDB.guildChatPrivacy = false
                EllesmereUIDB.repairWarning = nil
                -- Reset UI scale so next reload re-snapshots from Blizzard default
                EllesmereUIDB.ppUIScale = nil
                EllesmereUIDB.ppUIScaleAuto = nil
                -- Developer settings defaults
                EllesmereUIDB.showSpellID = false
                EllesmereUIDB.suppressErrors = true
                EllesmereUIDB.crosshairSize = "None"
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

    -- Profiles & Presets: its own single-page sidebar module. Reuses the
    -- existing profiles page builder; the profiles-root lifecycle is handled by
    -- the shared CleanupProfilesRoot hooks below (now keyed to PROFILES_KEY).
    EllesmereUI:RegisterModule(PROFILES_KEY, {
        title       = "Profiles & Presets",
        description = "Import, export, and switch EllesmereUI profiles and presets.",
        pages       = { PAGE_PROFILES },
        buildPage   = function(pageName, parent, yOffset)
            return BuildProfilesPage(pageName, parent, yOffset)
        end,
        onPageCacheRestore = function()
            if not EllesmereUI._profilesRoot then
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
            description = "What's new in EllesmereUI.",
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
