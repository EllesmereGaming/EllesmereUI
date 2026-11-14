if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Options.lua: registers the Nameplates module with EllesmereUI.
--  All get/set calls go to ns.db.profile (centralized store); does NOT touch nameplate rendering logic.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUINameplates"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

-- The options page frame pool (EllesmereUI_FramePool.lua): frames made under a
-- pooled page or header part are handed back to its next build.
local CreateFrame = EllesmereUI._Pool.CreateFrame
local PoolGen, PoolKeep = EllesmereUI._Pool.Gen, EllesmereUI._Pool.Keep

-- Body-text preview flag, already slug-gated at the source (GetFontOutlineFlag).
local function GetNPOptOutline() return EllesmereUI.GetFontOutlineFlag("nameplates") end

-- Rows the Blizzard kit replaces but the classic plate leaves to the user
-- (bar background, cast bar texture, cast background and colours, the
-- border wrap): gated only while Blizzard Style renders, live under Classic
-- WoW UI. ns fields so the page builders gain no upvalue; the gate returns
-- cfg for inline use like BlizzStyle.Gate.
function ns.NP_BlizzOnly()
    return EllesmereUI.BlizzStyle.Active("nameplates") == "blizzard"
end
function ns.NP_BlizzOnlyGate(cfg)
    if ns.NP_BlizzOnly() then return EllesmereUI.BlizzStyle.Gate("nameplates", cfg) end
    return cfg
end

-- A row half's slider label, for a "(Percent)" suffix beside it: the half's own
-- label (a page built again keeps its earlier dresses' font strings, idle,
-- among the half's regions).
local function SliderLabel(rgn, text)
    local label = rgn._label
    if label and label.GetText and EllesmereUI.EnKey(label:GetText()) == text then return label end
end

-- Global Search words for a section header or a row, registered right before
-- it (the index keeps a label's first entry on a page): the other names its
-- settings are known by, what an inline swatch holds, and for a row its own
-- tooltip, each in English and in the client's language. section: the row's
-- section name; nil when label is a section header itself.
local function SearchWords(label, section, ...)
    if not EllesmereUI._RegisterSearchEntry then return end
    local L, text = EllesmereUI.L, {}
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        text[#text + 1] = s
        local loc = L(s)
        if loc ~= s then text[#text + 1] = loc end
    end
    local labelLoc = L(label)
    EllesmereUI._RegisterSearchEntry(label, labelLoc ~= label and labelLoc or nil, table.concat(text, " "),
        EllesmereUI._buildingModule, EllesmereUI._buildingPage, section or label, nil, nil, not section or nil)
end

-------------------------------------------------------------------------------
--  Page / section names. A page name is the page's identity (saved overrides,
--  search and links key on it); the Display, Colors, Friendly Plates and
--  General tabs read Enemy, Enemy Colors, Friendly and Extras through the
--  module's tabLabels.
-------------------------------------------------------------------------------
local PAGE_GENERAL   = "General"
local PAGE_DISPLAY   = "Display"
local PAGE_COLORS    = "Colors"
local PAGE_TFH       = "Target, Focus & Hover"
local PAGE_FRIENDLY  = "Friendly Plates"

local SECTION_ENEMY_NP  = "NAMEPLATE SPACING"
local SECTION_MISC      = "EXTRAS"
local SECTION_AURA      = "EXTRA AURA OPTIONS"

local SECTION_ENEMY     = "ENEMY COLORS"
local SECTION_CASTBAR   = "CAST COLORS AND EFFECTS"
local SECTION_THREAT    = "THREAT COLORS"
local SECTION_OTHER     = "OTHER COLORS"

-- Threat % Position dropdown (WoW Forever only, so nil on retail).
local THREAT_PCT_POSITIONS, THREAT_PCT_POSITION_ORDER
if EllesmereUI.IS_FOREVER then
    THREAT_PCT_POSITIONS = { RIGHT = "Inside Right", LEFT = "Inside Left", CENTER = "Inside Center" }
    THREAT_PCT_POSITION_ORDER = { "RIGHT", "LEFT", "CENTER" }
end

-- Wait for EllesmereUI to exist
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    ---------------------------------------------------------------------------
    --  Local references from the addon namespace
    ---------------------------------------------------------------------------
    local defaults             = ns.defaults
    local SetFSFont            = ns.SetFSFont
    local GetEnemyNameTextSize = ns.GetEnemyNameTextSize
    local GetDebuffTextColor   = ns.GetDebuffTextColor
    local BAR_W                = ns.BAR_W
    local plates               = ns.plates
    local GetNPOutline         = ns.GetNPOutline or function() return "OUTLINE, SLUG" end
    local GetNPUseShadow       = ns.GetNPUseShadow or function() return false end

    local pcall = pcall
    local pairs = pairs

    -- Preview font setter: the plates' own font families (SetFSFont), so a
    -- preview name, title or cast target draws as on a live plate. Every font
    -- write to a preview text goes through it, never a plain SetFont.
    local function SetPVFont(fs, fontPath, size, flags)
        EllesmereUI.ApplyModuleFontFamily(fs, fontPath, size, "nameplates", flags)
    end
    local floor = math.floor
    local NAME_RAID_MARKER_GAP = 3

    ---------------------------------------------------------------------------
    --  DB helper reads from the centralized profile via ns.db
    ---------------------------------------------------------------------------
    local function DB()
        return ns.db and ns.db.profile
    end

    local function DBVal(key)
        local db = DB()
        if db and db[key] ~= nil then return db[key] end
        return defaults[key]
    end

    local function DBColor(key)
        local db = DB()
        local c = (db and db[key]) or defaults[key]
        return c.r, c.g, c.b
    end

    local FOCUS_LETTER_ANCHORS = {
        CENTER = "Center",
        LEFT = "Left",
        RIGHT = "Right",
        TOP = "Top",
        BOTTOM = "Bottom",
        TOPLEFT = "Top Left",
        TOPRIGHT = "Top Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOMRIGHT = "Bottom Right",
    }
    local FOCUS_LETTER_ANCHOR_ORDER = {
        "CENTER", "LEFT", "RIGHT", "TOP", "BOTTOM",
        "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
    }
    local function GetFocusLetterAnchor()
        local anchor = DBVal("focusLetterAnchor") or defaults.focusLetterAnchor
        return FOCUS_LETTER_ANCHORS[anchor] and anchor or defaults.focusLetterAnchor
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshAllPlates()
        -- Color Casting Enemies repaints its tint colors (its swatches, Modify Out of Combat).
        if ns.NP_CastTintsDirty then ns.NP_CastTintsDirty() end
        for _, plate in pairs(plates) do
            plate:UpdateHealth()
        end
    end

    local function RefreshAllAuras()
        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    end

    -- Bar textures: the settings pass for the enemy plates, then the friendly
    -- plates' health and cast bars.
    local function RefreshAllTextures()
        ns.RefreshAllSettings()
        for _, plate in pairs(ns.friendlyPlates or {}) do
            if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(plate) end
            if ns.ApplyCastBarTexture then ns.ApplyCastBarTexture(plate) end
        end
    end

    ---------------------------------------------------------------------------
    --  Health bar texture dropdown values (built from ns tables)
    ---------------------------------------------------------------------------
    -- Append SharedMedia textures to the runtime ns tables first so both the dropdown AND the live nameplate rendering can resolve SM keys.
    EllesmereUI.AppendSharedMediaTextures(
        ns.healthBarTextureNames or {},
        ns.healthBarTextureOrder or {},
        nil,
        ns.healthBarTextures
    )

    local hbtValues = {}
    local hbtOrder = {}
    do
        local texNames = ns.healthBarTextureNames or {}
        local texOrder2 = ns.healthBarTextureOrder or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                hbtValues[key] = texNames[key] or key
            end
            hbtOrder[#hbtOrder + 1] = key
        end
        local texLookup = ns.healthBarTextures or {}
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texLookup[key]
            end,
        }
    end

    ---------------------------------------------------------------------------
    --  Live Preview System: cosmetic-only enemy nameplate preview built once
    --  and updated via :Update() (no rebuild/GC pressure), reading live DB settings for colors, sizes, font, etc.
    ---------------------------------------------------------------------------
    -- Mutable state shared with the page builders under Nameplates_Options\.
    -- A table instead of locals so every file reads and writes the live value.
    -- Nil until set: activePreview (the Display page's preview frame),
    -- tfhPreview (the Target, Focus & Hover page's) and tfhMode (the state it
    -- draws, picked for the session), RefreshCoreEyes (Display page).
    local optState = {}
    local _displayHeaderBuilder   -- stored for page cache re-use

    ---------------------------------------------------------------------------
    --  Preview click navigation, one kit for every page whose header preview
    --  takes clicks (Display, Target, Focus & Hover, Friendly Plates), handed
    --  to the page files as env.Nav. A page is known by its id: its page name
    --  (env.PAGE_DISPLAY, env.PAGE_TFH, env.PAGE_FRIENDLY). Nothing is built
    --  until a page asks, and nothing runs while no preview is clicked.
    --
    --  Nav.Page(id, map) -> P
    --    The page's navigator, one per id for the session. With map: map
    --    becomes the page's mapping and the page gets a new glow; call it on
    --    every live build of the page, after its header is built, never in
    --    the search pre-build. Without map, P as it is (for a header builder
    --    that makes overlays before the page body runs).
    --    map[key] = { section = section header, target = row, slotSide =
    --    "left" | "right" | nil }, or a function returning such a table or
    --    nil, called at click time.
    --  P.Go(key)
    --    Resolves map[key]. With a section and a target: dismisses the page's
    --    hint, scrolls the page to 40 px above the section header and 0.15 s
    --    later plays the green highlight on the row, or on its half when
    --    slotSide is set, unless the row was dressed again meanwhile (a page
    --    built again). Reads the page's map at click time, so an overlay made
    --    by an earlier build lands on this build's rows.
    --  P.Overlay(element, key, isText, level, opts) -> btn, hlBase, hlCont
    --    EllesmereUI.CreatePreviewHitOverlay over element, its hover border on
    --    a child frame of its own, clicking P.Go(key). Over the page pool's
    --    frames the overlay is the pool's too (parked and dressed again with
    --    the preview, so it is made on every build); over a frame of the
    --    page's own, make it once and keep it.
    --  Nav.Hint(id, host, hdr, y, baseH) -> height, fs
    --    In a header builder. Until the account dismisses the hint, the line
    --    "Click elements to scroll to and highlight their options" on host
    --    (made once, held across builds), its bottom y above hdr's bottom;
    --    after, hidden. baseH: the header's height without the hint. Returns
    --    the header's height with it, and the font string (nil until made).
    --  Nav.HintH(id, baseH) -> the height the page's hint adds while it shows
    --    (29), else 0. baseH (optional) is the header's new height without the
    --    hint, for a header whose height follows the settings.
    --  Nav.HintRestore(id)
    --    The page shown again from the page cache: its hint shows or hides by
    --    the account's choice, and once the page has given its base height
    --    (Nav.Hint, or Nav.HintH with baseH) the header takes that height,
    --    plus the hint's while the account has not dismissed it.
    --  The caller owns its map, its overlays (levels, which show, when they
    --    are made), where its hint sits and its header's height; the kit sets
    --    that height only on a cache restore and while a dismissed hint fades.
    ---------------------------------------------------------------------------
    local Nav = {}
    do
        local HINT_H = 29                       -- header px the hint line adds
        local HIT_STYLE = { container = true }  -- the hover border on its own child frame
        local pages = {}                        -- id -> P: the map, the glow, the hint

        local function HintDismissed()
            return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
        end
        local function GlowPx() return PP.Scale(2) end

        function Nav.Page(id, map)
            local P = pages[id]
            if not P then
                P = { base = 0 }
                function P.Go(key)
                    local m = P.map and P.map[key]
                    if type(m) == "function" then m = m() end
                    if not m or not m.section or not m.target then return end

                    -- The header shrinks by the hint's height back to the page's base.
                    EllesmereUI.DismissPreviewHint(P.fs, P.base, HINT_H, P.y)

                    local sf = EllesmereUI._scrollFrame
                    if not sf then return end
                    local _, _, _, _, headerY = m.section:GetPoint(1)
                    if not headerY then return end
                    local scrollPos = math.max(0, math.abs(headerY) - 40)
                    EllesmereUI.SmoothScrollTo(scrollPos)
                    local glowTarget = m.target
                    if m.slotSide and m.target then
                        local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                        if region then glowTarget = region end
                    end
                    -- A page built again before the glow plays dressed the row anew: no glow.
                    local glow, glowGen = P.glow, PoolGen(glowTarget)
                    C_Timer.After(0.15, function()
                        if PoolGen(glowTarget) ~= glowGen then return end
                        glow(glowTarget)
                    end)
                end
                function P.Overlay(element, key, isText, level, opts)
                    return EllesmereUI.CreatePreviewHitOverlay(element, P.Go, key, isText, level, opts, HIT_STYLE)
                end
                pages[id] = P
            end
            if map then
                P.map = map
                P.glow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN, thickness = GlowPx, noSnap = true })
            end
            return P
        end

        function Nav.Hint(id, host, hdr, y, baseH)
            local P = Nav.Page(id)
            -- A hint whose parent was dropped with an old header is made again.
            if P.fs and not P.fs:GetParent() then
                P.fs = nil
            end
            local shown = not HintDismissed()
            if shown then
                if not P.fs then
                    -- Held across builds: out of the frame pool for good (later
                    -- builds of its host only hide it with the host).
                    P.fs = PoolKeep(EllesmereUI.MakeFont(host, 11, nil, 1, 1, 1))
                    P.fs:SetAlpha(0.45)
                    P.fs:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                P.fs:SetParent(host)
                P.fs:ClearAllPoints()
                P.fs:SetPoint("BOTTOM", hdr, "BOTTOM", 0, y)
                P.fs:SetAlpha(0.45)
                P.fs:Show()
            elseif P.fs then
                P.fs:Hide()
            end
            P.y, P.base = y, baseH
            return baseH + (shown and HINT_H or 0), P.fs
        end

        function Nav.HintH(id, baseH)
            local P = pages[id]
            if not P then return 0 end
            if baseH then P.base = baseH end
            return (P.fs and P.fs:IsShown()) and HINT_H or 0
        end

        -- Refreshes the hint's visibility only; never makes one.
        function Nav.HintRestore(id)
            local P = pages[id]
            if not P then return end
            local dismissed = HintDismissed()
            if P.fs then
                if dismissed then
                    P.fs:Hide()
                else
                    P.fs:SetAlpha(0.45)
                    P.fs:Show()
                end
            end
            if P.base > 0 then
                -- the hint's line only where the page has a hint to show
                EllesmereUI:SetContentHeaderHeightSilent(P.base + ((P.fs and not dismissed) and HINT_H or 0))
            end
        end
    end

    -- Raid marker hidden by default, toggled via eye icon; optState fields so both the preview and the Display page can access them.
    optState.showRaidMarkerPreview = false
    optState.showClassificationPreview = false
    optState.showQuestTextPreview = false
    optState.showAbsorbPreview = false
    -- (the Friendly Plates page's eye: the raid marker on the sample NPC)
    optState.showNPCMarkerPreview = false

    -- Transient flags: force-show indicators during slider drag
    optState._sliderDragShowRaidMarker = false
    optState._sliderDragShowClassification = false

    -- Random preview values regenerate only on tab switch, not on profile changes or setting tweaks (those trigger fast-path RefreshPage rebuilds).
    -- optState._previewHpPct, _previewCastFill, _previewCastIconIdx: set below.
    local displayCastIcons = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local function RandomizePreviewValues()
        optState._previewHpPct = math.floor(60 + math.random() * 15)
        optState._previewCastFill = 0.40 + math.random() * 0.20
        optState._previewCastIconIdx = math.random(#displayCastIcons)
    end

    -- The Display page and the Target, Focus & Hover page each keep a preview in
    -- their own header. Only the one on screen is repainted: setters of other
    -- pages and the panel's show callback reach this from any page, and a page's
    -- cache restore updates its own preview when it shows again.
    local function UpdatePreview()
        for i = 1, 2 do
            local pv = optState[i == 1 and "activePreview" or "tfhPreview"]
            if pv and pv.Update and pv:IsVisible() then
                pv:Update()
            end
        end
    end

    -- Refresh the preview every time the panel is reopened
    EllesmereUI:RegisterOnShow(UpdatePreview)

    ---------------------------------------------------------------------------
    --  Glow sites: the Dispel, Pandemic, Important Cast and Cast Targets You glows as shared glow
    --  descriptors, used by the page rows and the Global Settings Glows page.
    ---------------------------------------------------------------------------
    local npDispelGlowDesc, npImpCastGlowDesc, npPandemicGlowDesc, npCastTargetGlowDesc
    do
        local GO = EllesmereUI.GlowOptions
        -- The aura glows (Dispel, Pandemic) share one refresh, so the Glows
        -- page runs it once per Apply.
        local function RefreshAuraGlows() RefreshAllAuras(); UpdatePreview() end
        -- Engine aura buttons (no Auto-Cast/Shape); an unset color is the
        -- suite default (gold).
        -- Blizzard Border: Blizzard's static stealable art, outside the view.
        local BLIZZ_BORDER = EllesmereUI.Glows.STEALABLE_BORDER
        -- Blizzard Pandemic Border: the Cooldown Manager's static pandemic
        -- art, outside the view, never tinted (noColor locks the swatches);
        -- the default of both aura glows.
        local PAN_BORDER = EllesmereUI.Glows.PANDEMIC_BORDER
        npDispelGlowDesc = {
            view = ns.NP_GLOW_VIEW, host = "engine",
            extras = {
                { value = PAN_BORDER, label = "Blizzard Pandemic Border", style = PAN_BORDER, noColor = true },
                { value = BLIZZ_BORDER, label = "Blizzard Border", style = BLIZZ_BORDER },
            },
            caps = { mode = true, params = true, bg = true },
            defaultColor = EllesmereUI.Glows.DEFAULT_COLOR,
            isOff = function() return DBVal("dispelGlow") ~= true end,
            -- Color by Type replaces the swatch color on every group.
            colorDisabled = function() return DBVal("dispelGlowUseTypeColor") == true end,
            colorDisabledTooltip = "Color by Type (Magic/Enrage)",
            onChange = RefreshAuraGlows,
            get = function(f)
                local d = DB()
                if f == "style" then return ns.GetDispelGlowStyle and ns.GetDispelGlowStyle() or defaults.dispelGlowStyle
                elseif f == "mode" then return d.dispelGlowColorMode or (d.dispelGlowColor and "custom" or "default")
                end
                return EllesmereUI.GlowOptions.FlatGet(d, "dispelGlow", f)
            end,
            set = function(f, a, b2, c2)
                local d = DB()
                if f == "style" then
                    if a == 0 then d.dispelGlow = false else d.dispelGlow = true; d.dispelGlowPick = a end
                elseif f == "mode" then d.dispelGlowColorMode = a
                else EllesmereUI.GlowOptions.FlatSet(d, "dispelGlow", f, a, b2, c2)
                end
            end,
            -- Magic buffs and enrages are separate groups in the buff row, so the
            -- color can follow the type; it overrides the color above per group.
            cogRows = {
                { type="toggle", label="Color by Type (Magic/Enrage)",
                  get=function() return DBVal("dispelGlowUseTypeColor") or false end,
                  set=function(v)
                      DB().dispelGlowUseTypeColor = v
                      RefreshAuraGlows()
                      EllesmereUI:RefreshPage()
                  end },
            },
        }
        -- The cast bar glows (flat <prefix>* keys, on/off in <prefix>): the cast bar is a
        -- bar host (no Shape). An edit reaches the casts already showing. Modern WoW Glow
        -- is drawn as Blizzard's nameplate cast bar art, so picking it selects the Default
        -- color: the art's own.
        local function RefreshCastGlows()
            if ns.NP_RefreshCastGlows then ns.NP_RefreshCastGlows() end
        end
        local function CastBarGlowDesc(prefix)
            local k = EllesmereUI.Glows.FlatKeys(prefix)
            return {
                view = ns.NP_GLOW_VIEW, host = "bar",
                caps = { mode = true, params = true, bg = true },
                defaultColor = defaults[k.color],
                defaultColorOnPick = ns.NP_CAST_ART_STYLE and { [ns.NP_CAST_ART_STYLE] = true } or nil,
                isOff = function() return DBVal(prefix) ~= true end,
                onChange = RefreshCastGlows,
                get = function(f)
                    local d = DB()
                    if f == "style" then return d[k.style] or defaults[k.style] or 1
                    elseif f == "mode" then return d[k.mode] or "custom"
                    end
                    return GO.FlatGet(d, prefix, f, defaults)
                end,
                set = function(f, a, b2, c2)
                    local d = DB()
                    if f == "style" then
                        if a == 0 then d[prefix] = false
                        else d[prefix] = true; d[k.style] = a end
                    elseif f == "mode" then d[k.mode] = a
                    else GO.FlatSet(d, prefix, f, a, b2, c2)
                    end
                end,
            }
        end
        npImpCastGlowDesc = CastBarGlowDesc("importantCastGlow")
        -- Casts targeting the player (off by default).
        npCastTargetGlowDesc = CastBarGlowDesc("castTargetGlow")
        -- Debuffs in their pandemic window (pandemicGlow* keys; the same mode
        -- key the CDM pandemic sync writes). An unset color mode is Custom:
        -- the swatch color this glow always drew (the profile merge fills it
        -- with the default gold).
        npPandemicGlowDesc = {
            view = ns.NP_GLOW_VIEW, host = "engine",
            extras = {
                { value = PAN_BORDER, label = "Blizzard Pandemic Border", style = PAN_BORDER, noColor = true },
            },
            caps = { mode = true, params = true, bg = true },
            defaultColor = defaults.pandemicGlowColor,
            isOff = function() return DBVal("pandemicGlow") ~= true end,
            onChange = RefreshAuraGlows,
            get = function(f)
                local d = DB()
                if f == "style" then return ns.GetPandemicGlowStyle()
                elseif f == "mode" then return d.pandemicGlowMode or "custom"
                end
                return EllesmereUI.GlowOptions.FlatGet(d, "pandemicGlow", f, defaults)
            end,
            set = function(f, a, b2, c2)
                local d = DB()
                if f == "style" then
                    if a == 0 then d.pandemicGlow = false else d.pandemicGlow = true; d.pandemicGlowPick = a end
                elseif f == "mode" then d.pandemicGlowMode = a
                else EllesmereUI.GlowOptions.FlatSet(d, "pandemicGlow", f, a, b2, c2)
                end
            end,
        }
        GO.RegisterSite({ id = "np_dispel", label = "Dispel Glow", group = "module",
            module = "EllesmereUINameplates", page = PAGE_GENERAL, section = SECTION_AURA,
            highlight = "Dispel Glow Style", desc = npDispelGlowDesc })
        -- (not on WoW Forever: no pandemic window there, ns.NP_PANDEMIC_NONE)
        if not ns.NP_PANDEMIC_NONE then
            GO.RegisterSite({ id = "np_pandemic", label = "Pandemic Glow", group = "module",
                module = "EllesmereUINameplates", page = PAGE_GENERAL, section = SECTION_AURA,
                highlight = "Pandemic Glow Style", desc = npPandemicGlowDesc })
        end
        GO.RegisterSite({ id = "np_importantcast", label = "Important Cast Glow", group = "module",
            module = "EllesmereUINameplates", page = PAGE_DISPLAY, section = SECTION_CASTBAR,
            highlight = "Important Cast Glow", desc = npImpCastGlowDesc })
        GO.RegisterSite({ id = "np_casttarget", label = "Cast Targets You Glow", group = "module",
            module = "EllesmereUINameplates", page = PAGE_DISPLAY, section = SECTION_CASTBAR,
            highlight = "Cast Targets You Glow", desc = npCastTargetGlowDesc })
    end

    ---------------------------------------------------------------------------
    --  Display page  (preview in content header + settings in scroll area)
    ---------------------------------------------------------------------------
    local function BuildDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- Set content header with preview centered above nameplate preview
        _displayHeaderBuilder = function(headerParent, headerW)

            local PRESET_HEADER_H = 0
            local PREVIEW_TOP_PAD = 5
            local PREVIEW_BOTTOM_PAD = 5
            local previewH = ns.NPO_BuildNameplatePreview(headerParent, headerW)
            -- Position the preview at the top of the header area. pf's SetScale matches the UIParent/panel ratio, so SetPoint offsets (in that scaled space) must divide by the same ratio for the correct visual offset.
            if optState.activePreview then
                optState.activePreview:ClearAllPoints()
                local correction = UIParent:GetEffectiveScale() / headerParent:GetEffectiveScale()
                optState.activePreview:SetPoint("TOP", headerParent, "TOP", 0, -(PRESET_HEADER_H + PREVIEW_TOP_PAD) / correction)
                optState.activePreview._headerExtra = PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD
            end

            -- "Click elements" hint: parented to activePreview (not headerParent directly, which orphaned it via ClearContentHeaderInner on page switch) so the FontString travels through the content-header cache.
            return (Nav.Hint(PAGE_DISPLAY, optState.activePreview or headerParent, headerParent, 17,
                previewH + PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD))
        end
        EllesmereUI:SetContentHeader(_displayHeaderBuilder)

        -- Enable per-row center divider for the dual-column layout
        parent._showRowDivider = true

        -----------------------------------------------------------------------
        --  AURA POSITIONS
        -----------------------------------------------------------------------
        local slotKeys = { "debuffSlot", "buffSlot", "ccSlot", "raidMarkerPos", "classificationSlot", "factionSlot" }

        -- Inverted mapping: position element (for CORE POSITIONS dropdowns)
        local elementToKey = {
            debuffs        = "debuffSlot",
            buffs          = "buffSlot",
            ccs            = "ccSlot",
            raidmarker     = "raidMarkerPos",
            classification = "classificationSlot",
            faction        = "factionSlot",
        }
        local keyToElement = {}
        for elem, key in pairs(elementToKey) do keyToElement[key] = elem end

        local function GetElementAtPosition(pos)
            local db = DB()
            for _, key in ipairs(slotKeys) do
                -- A leftover Faction slot is ignored while Rare/Quest + Faction is on
                -- (the badge rides the classification slot), so it is not shown here either.
                local ignored = key == "factionSlot" and db.classificationIncludeFaction
                if not ignored and (db[key] or defaults[key]) == pos then
                    -- "Debuffs + CC" is a VIEW over the debuff slot: same position key + the debuffIncludeCC flag.
                    if key == "debuffSlot" and db.debuffIncludeCC then
                        return "debuffsccs"
                    end
                    -- "Rare/Quest + Faction" is a VIEW over the classification slot + classificationIncludeFaction.
                    if key == "classificationSlot" and db.classificationIncludeFaction then
                        return "classfaction"
                    end
                    return keyToElement[key]
                end
            end
            return "none"
        end

        local function SetElementAtPosition(pos, element)
            -- The Quest Objective Text view reads the Rare/Quest slot and its Quest
            -- half: fix its own keys before either can move.
            ns.NP_MaterializeQuestText(DB())
            if element == "none" then
                -- Clear: find whatever element is at this position and move it to "none"
                local db = DB()
                for _, key in ipairs(slotKeys) do
                    if (db[key] or defaults[key]) == pos then
                        db[key] = "none"
                    end
                end
                if ns.NP_GetQuestTextSlot(db) == pos then db.questTextSlot = "none" end
                return
            end
            -- "Debuffs + CC" rides the debuff slot key; the two entries differ only by debuffIncludeCC.
            if element == "debuffsccs" then
                DB().debuffIncludeCC = true
                element = "debuffs"
            elseif element == "debuffs" then
                DB().debuffIncludeCC = false
            end
            -- "Rare/Quest + Faction" rides the classification slot key and takes the
            -- faction badge with it (its own Faction slot is cleared); picking either
            -- one alone splits them again.
            if element == "classfaction" then
                DB().classificationIncludeFaction = true
                DB().factionSlot = "none"
                element = "classification"
            elseif element == "classification" or element == "faction" then
                DB().classificationIncludeFaction = false
            end
            local key = elementToKey[element]
            if not key then return end
            local db = DB()
            -- Clear old holder of this position (set to "none"), no swapping
            for _, otherKey in ipairs(slotKeys) do
                if otherKey ~= key and (db[otherKey] or defaults[otherKey]) == pos then
                    db[otherKey] = "none"
                end
            end
            db[key] = pos
        end

        local slotValues = {
            ["top"]      = "Top",
            ["left"]     = "Left",
            ["right"]    = "Right",
            ["topleft"]  = "Top Left",
            ["topright"] = "Top Right",
            ["bottom"]   = "Bottom",
            ["none"]     = "None",
        }
        local slotOrder = { "top", "left", "right", "topleft", "topright", "bottom", "none" }
        local function RefreshAllSlots()
            RefreshAllAuras()
            for _, plate in pairs(plates) do
                plate:UpdateRaidIcon()
                plate:UpdateClassification()
                -- Rare/Quest + Faction: the classification pass already ran it.
                if not DBVal("classificationIncludeFaction") then plate:UpdateFaction() end
                if ns.ApplySlotStrata then ns.ApplySlotStrata(plate) end
            end
            ns.NP_RefreshFriendlyFaction()
            UpdatePreview()
            EllesmereUI:RefreshPage()
        end

        -----------------------------------------------------------------------
        --  Helpers for position-swapping dropdowns
        -----------------------------------------------------------------------

        -- Exclusive slot assignment for the new Core Text Positions system.
        local textSlotKeys = ns.textSlotKeys
        local function SetTextElementAtSlot(slotKey, element)
            local db = DB()
            -- Custom keeps its template per slot: any number of slots may show it.
            if element ~= "none" and element ~= "custom" then
                for _, key in ipairs(textSlotKeys) do
                    if key ~= slotKey then
                        local cur = db[key] or defaults[key]
                        -- Name-family variants (name and the level+name combos) all render through the plate's single name FontString, so slotting any of
                        -- them evicts whichever family member occupies another slot -- same rule as an exact match. STANDALONE level has its own FontString and only exact-match evicts, so name + level can coexist.
                        if cur == element
                           or (ns.IsNameElement(element) and ns.IsNameElement(cur)) then
                            db[key] = "none"
                        end
                    end
                end
            end
            db[slotKey] = element
        end

        local timerPosValues = {
            ["topleft"]  = "Top Left",
            ["center"]   = "Center",
            ["topright"]  = "Top Right",
            ["bottomleft"]  = "Bottom Left",
            ["bottomright"] = "Bottom Right",
            ["none"]      = "None",
        }
        local timerPosOrder = { "none", "topleft", "topright", "bottomleft", "bottomright", "center" }

        local function AuraDurationVal(kind, suffix)
            local db = DB()
            local key = kind .. "DurationText" .. suffix
            local oldKey = "auraDurationText" .. suffix
            if db and db[key] ~= nil then return db[key] end
            if db and db[oldKey] ~= nil then return db[oldKey] end
            return defaults[oldKey]
        end

        -- Aura duration and stack text draw through the aura containers' style
        -- pass, which a settings edit re-runs (fingerprint-guarded).
        local function LiveApplyAuraText()
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end

        local atFallback = DBVal("auraTextPosition") or defaults.auraTextPosition
        local asFallback = DBVal("auraStackTextPosition") or defaults.auraStackTextPosition

        -- The sections live in Nameplates_Options\DisplayLayout_Options.lua
        -- (which calls CoreTextColoring_Options.lua) and DisplayBars_Options.lua;
        -- they return the rows the click navigation below maps to.
        local ctx = {
            W = W, GetElementAtPosition = GetElementAtPosition, RefreshAllSlots = RefreshAllSlots,
            SetElementAtPosition = SetElementAtPosition,
            SetTextElementAtSlot = SetTextElementAtSlot, asFallback = asFallback,
            atFallback = atFallback, AuraDurationVal = AuraDurationVal,
            LiveApplyAuraText = LiveApplyAuraText,
            timerPosOrder = timerPosOrder, timerPosValues = timerPosValues,
        }
        local styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textSlotCells
        local textFirstRow
        y, styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textSlotCells,
            textFirstRow, ctx.ShowCogPopup, ctx.CogPopupOpen = ns.NPO_BuildDisplayLayout(parent, y, ctx)
        local healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow
        local classResourceHeader, classResourceSection, generalTextHeader
        local auraDurPosRow, auraTimerStackRow, spellNameRow
        y, healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow,
            classResourceHeader, classResourceSection, generalTextHeader,
            auraDurPosRow, auraTimerStackRow, spellNameRow = ns.NPO_BuildDisplayBars(parent, y, ctx)

        -- The search pre-build indexes rows only. The click navigation below
        -- rewires the live preview's hit overlays, which a hidden build of
        -- this page must leave alone.
        if EllesmereUI._prebuilding then return math.abs(y) end

        -----------------------------------------------------------------------
        --  CLICK NAVIGATION: mapping and hit overlays (the glow, the scroll and
        --  the overlay factory are the Nav kit's)
        -----------------------------------------------------------------------
        -- Maps Core Text Position slot keys to their row/region (the cells of
        -- the texts the list shows)
        local textSlotToRow = textSlotCells

        -- Reverse lookup: find which Core Position slot holds a given element
        local function FindCorePosForElement(element)
            local db = DB()
            local key = elementToKey[element]
            if not key then return nil end
            local pos = db[key] or defaults[key]
            if pos == "none" then return nil end
            return pos
        end

        -- Reverse lookup: find which text slot holds a given element
        local function FindTextSlotForElement(element)
            local db = DB()
            for _, key in ipairs(textSlotKeys) do
                if (db[key] or defaults[key]) == element then return key end
            end
            return nil
        end

        -- Resolve a dynamic click mapping to the Core Positions row of a position
        -- (the first row while the element sits in none)
        local function ResolveCorePos(pos)
            if not pos or pos == "none" then return { section = coreHeader, target = coreRow1 } end
            local info = ctx.corePosToRegion[pos]
            if not info then return { section = coreHeader, target = coreRow1 } end
            return { section = coreHeader, target = info[1], slotSide = (info[2] == "_leftRegion") and "left" or "right" }
        end
        -- The same for the slot holding an icon element
        local function ResolveCoreMapping(element)
            return ResolveCorePos(FindCorePosForElement(element))
        end

        local clickMappings = {
            debuffDuration = { section = generalTextHeader, target = auraDurPosRow,      slotSide = "left" },
            buffDuration = { section = generalTextHeader,   target = auraDurPosRow,      slotSide = "right" },
            ccDuration = { section = generalTextHeader,     target = auraTimerStackRow,  slotSide = "left" },
            auraStack    = { section = generalTextHeader,  target = auraTimerStackRow,   slotSide = "right" },
            castBar      = { section = healthBarHeader,  target = castBarHeightRow,    slotSide = "left" },
            castIcon     = { section = healthBarHeader,  target = showCastIconRow,     slotSide = "right" },
            castTimer    = { section = healthBarHeader,  target = castTimerRow,        slotSide = "left" },
            castName     = { section = generalTextHeader, target = spellNameRow,        slotSide = "left" },
            castTarget   = { section = generalTextHeader, target = spellNameRow,        slotSide = "right" },
            healthBar    = { section = healthBarHeader,  target = healthBarHeightRow },
            classResource = { section = classResourceHeader, target = classResourceSection },

            -- Resolvers, called at click time: the elements assigned to Core
            -- Positions / Core Text Positions, and the stock styles' levels.

            -- Classic WoW UI: the level in the health border's plate. Its row
            -- exists only on that style, so this resolves to nothing elsewhere.
            classicLevel = function()
                local row = parent._classicPlateRow
                if not row then return nil end
                return { section = styleHeader, target = row, slotSide = "left" }
            end,
            -- WoW Forever: the level box, whose row exists only under that
            -- variant.
            foreverLevelBox = function()
                local row = parent._foreverBoxRow
                if not row then return nil end
                return { section = styleHeader, target = row, slotSide = "left" }
            end,
            debuffIcon   = function() return ResolveCoreMapping("debuffs") end,
            buffIcon     = function() return ResolveCoreMapping("buffs") end,
            ccIcon       = function() return ResolveCoreMapping("ccs") end,
            raidMarker   = function() return ResolveCoreMapping("raidmarker") end,
            classIcon    = function() return ResolveCoreMapping("classification") end,
            -- The Quest Objective Text's effective slot.
            questText    = function() return ResolveCorePos(ns.NP_GetQuestTextSlot(DB())) end,
            -- Combined with Rare/Quest, the badge's settings live on that row.
            factionIcon  = function()
                if DB().classificationIncludeFaction then return ResolveCoreMapping("classification") end
                return ResolveCoreMapping("faction")
            end,
            enemyName    = function()
                -- The name FontString renders whichever name-family variant is slotted; resolve the row for any of them.
                local slot = FindTextSlotForElement("enemyName") or FindTextSlotForElement("levelName") or FindTextSlotForElement("nameLevel")
                if not slot then return { section = coreTextHeader, target = textFirstRow } end
                local info = textSlotToRow[slot]
                if not info then return { section = coreTextHeader, target = textFirstRow } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end,
            healthText   = function()
                local slot = FindTextSlotForElement("healthPercent") or FindTextSlotForElement("healthPercentNoSign") or FindTextSlotForElement("healthPctNum") or FindTextSlotForElement("healthNumPct") or FindTextSlotForElement("healthPctNumDash") or FindTextSlotForElement("healthNumPctDash")
                if not slot then return { section = coreTextHeader, target = textFirstRow } end
                local info = textSlotToRow[slot]
                if not info then return { section = coreTextHeader, target = textFirstRow } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end,
        }
        -- Custom texts: each position's own font string, that position's row.
        for _, slotKey in ipairs(ns.textSlotKeys) do
            clickMappings["custom_" .. slotKey] = function()
                local info = textSlotToRow[slotKey]
                if not info then return { section = coreTextHeader, target = textFirstRow } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end
        end
        -- The font strings a single element owns: the row of the slot showing it.
        for mapKey, element in pairs({ healthNumber = "healthNumber", levelText = "level", targetOfTarget = "targetOfTarget" }) do
            clickMappings[mapKey] = function()
                local info = textSlotToRow[FindTextSlotForElement(element) or ""]
                if not info then return { section = coreTextHeader, target = textFirstRow } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end
        end

        -- This build's map; a click on a key scrolls to its row and highlights it.
        local nav = Nav.Page(PAGE_DISPLAY, clickMappings)
        local NavigateToSetting = nav.Go

        local function SnapPreview(val)
            local s = optState.activePreview and optState.activePreview:GetEffectiveScale() or 1
            if s <= 0 then s = 1 end
            return math.floor(val * s + 0.5) / s
        end
        -- Hit overlays for preview elements. opts (optional): hlAnchor = frame to
        -- draw the highlight around (instead of the overlay); hlBehindText = true
        -- draws it on a child frame at icon level+1 (text lives at icon level+2).
        -- Every build of this page runs right after its header built the preview
        -- again (the SetContentHeader call above), so the overlays below go on a
        -- preview that has none: a new one, or (page reuse) the same frames dressed
        -- again with their overlays parked by the preview's pool.
        local CreateHitOverlay = nav.Overlay

        -- Create hit overlays for all interactive preview elements
        local textOverlays = {}  -- collect text overlays for size refresh
        if optState.activePreview then
            local pv = optState.activePreview
            -- Icon overlays need to be above the icon frames (health:GetFrameLevel() + 9, or + 13 with Raise Strata)
            local iconLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            -- Text overlays on icons need to be above the icon overlays
            local textOnIconLevel = iconLevel + 10
            -- Aura icons (all debuffs, buffs, ccs)
            local iconHlOpts = { hlBehindText = true }
            if pv._ccs then
                for i = 1, #pv._ccs do
                    if pv._ccs[i] then
                        CreateHitOverlay(pv._ccs[i], "ccIcon", false, iconLevel, iconHlOpts)
                        if pv._ccs[i].durationText then
                            local ov = CreateHitOverlay(pv._ccs[i].durationText, "ccDuration", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                    end
                end
            end
            if pv._buffs then
                for i = 1, #pv._buffs do
                    if pv._buffs[i] then
                        CreateHitOverlay(pv._buffs[i], "buffIcon", false, iconLevel, iconHlOpts)
                        if pv._buffs[i].durationText then
                            local ov = CreateHitOverlay(pv._buffs[i].durationText, "buffDuration", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                    end
                end
            end
            if pv._debuffs then
                for i = 1, #pv._debuffs do
                    if pv._debuffs[i] then
                        CreateHitOverlay(pv._debuffs[i], "debuffIcon", false, iconLevel, iconHlOpts)
                        if pv._debuffs[i].durationText then
                            local ov = CreateHitOverlay(pv._debuffs[i].durationText, "debuffDuration", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                        if pv._debuffs[i].stackText then
                            local ov = CreateHitOverlay(pv._debuffs[i].stackText, "auraStack", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                    end
                end
            end
            -- Cast icon overlay (separate from cast bar navigates to Show Spell Icon row)
            local castOverlayLevel
            if pv._cast then
                castOverlayLevel = pv._cast:GetFrameLevel() + 20
                local cc = EllesmereUI.ELLESMERE_GREEN
                -- Cast icon overlay
                if pv._castIconFrame then
                    local iconOv = CreateFrame("Button", nil, pv._cast:GetParent())
                    iconOv:SetAllPoints(pv._castIconFrame)
                    iconOv:SetFrameLevel(castOverlayLevel)
                    iconOv:RegisterForClicks("LeftButtonDown")
                    local ioBrd = EllesmereUI.PP.CreateBorder(iconOv, cc.r, cc.g, cc.b, 1, 2, "OVERLAY", 7)
                    ioBrd:Hide()
                    iconOv:SetScript("OnEnter", function() ioBrd:Show() end)
                    iconOv:SetScript("OnLeave", function() ioBrd:Hide() end)
                    iconOv:SetScript("OnMouseDown", function() NavigateToSetting("castIcon") end)
                end
                -- Cast bar overlay (bar only, not icon)
                local castOverlay = CreateFrame("Button", nil, pv._cast:GetParent())
                castOverlay:SetAllPoints(pv._cast)
                castOverlay:SetFrameLevel(castOverlayLevel)
                castOverlay:RegisterForClicks("LeftButtonDown")
                local coBrd = EllesmereUI.PP.CreateBorder(castOverlay, cc.r, cc.g, cc.b, 1, 2, "OVERLAY", 7)
                coBrd:Hide()
                castOverlay:SetScript("OnEnter", function() coBrd:Show() end)
                castOverlay:SetScript("OnLeave", function() coBrd:Hide() end)
                castOverlay:SetScript("OnMouseDown", function() NavigateToSetting("castBar") end)
            end
            -- Cast spell name and target text (above the cast bar overlay)
            local castTextLevel = (castOverlayLevel or 30) + 5
            if pv._castNameFS and pv._castNameFS:IsShown() then
                local ov = CreateHitOverlay(pv._castNameFS, "castName", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            if pv._castTargetFS and pv._castTargetFS:IsShown() then
                local ov = CreateHitOverlay(pv._castTargetFS, "castTarget", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            if pv._castTimerFS and pv._castTimerFS:IsShown() then
                local ov = CreateHitOverlay(pv._castTimerFS, "castTimer", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            -- Enemy name text
            if pv._nameFS then
                local ov = CreateHitOverlay(pv._nameFS, "enemyName", true)
                textOverlays[#textOverlays + 1] = ov
            end
            -- Health text
            if pv._hpText then
                local ov = CreateHitOverlay(pv._hpText, "healthText", true)
                textOverlays[#textOverlays + 1] = ov
            end
            -- Health #, standalone level and Target of Target: each on its own font
            -- string, shown only while a slot holds it, so the overlay follows the
            -- text's shown state (_syncFS, re-read on every preview update).
            for fsKey, mapKey in pairs({ _hpNumber = "healthNumber", _lvlText = "levelText", _totFS = "targetOfTarget" }) do
                local fs = pv[fsKey]
                if fs then
                    local ov = CreateHitOverlay(fs, mapKey, true)
                    ov._syncFS = fs
                    ov:SetShown(fs:IsShown())
                    textOverlays[#textOverlays + 1] = ov
                end
            end
            -- Custom texts: one font string per position, shown while it holds one.
            if pv._customFS then
                for slotKey, fs in pairs(pv._customFS) do
                    local ov = CreateHitOverlay(fs, "custom_" .. slotKey, true)
                    ov._syncFS = fs
                    ov:SetShown(fs:IsShown())
                    textOverlays[#textOverlays + 1] = ov
                end
            end
            -- Classic WoW UI: the level in the health border's plate
            if pv._classicLevel then
                local ov = CreateHitOverlay(pv._classicLevel, "classicLevel", true)
                textOverlays[#textOverlays + 1] = ov
            end
            -- WoW Forever: the level box (its child, so it hides with it)
            if pv._fvLevelBox then
                CreateHitOverlay(pv._fvLevelBox, "foreverLevelBox")
            end
            -- Health bar
            if pv._health then
                CreateHitOverlay(pv._health, "healthBar")
            end
            -- Raid marker
            local raidOverlay
            if pv._raidFrame then
                raidOverlay = CreateHitOverlay(pv._raidFrame, "raidMarker")
                if not optState.showRaidMarkerPreview then raidOverlay:Hide() end
            end
            -- Rare/elite icon
            local classOverlay
            if pv._classIcon then
                classOverlay = CreateHitOverlay(pv._classIcon, "classIcon")
                if not optState.showClassificationPreview then classOverlay:Hide() end
            end
            -- Faction badge: shown and hidden with the badge by the preview update.
            if pv._factionIcon then
                pv._factionOverlay = CreateHitOverlay(pv._factionIcon, "factionIcon")
                pv._factionOverlay:SetShown(pv._factionIcon:IsShown())
            end
            -- Quest Objective Text sample (its child, so it shows and hides with it)
            if pv._questTextFrame then
                CreateHitOverlay(pv._questTextFrame, "questText")
            end
            -- Class resource pips wrapper button spanning all visible pips
            local cpOverlay
            if pv._cpPips then
                local firstVis, lastVis
                for i = 1, pv._cpMax do
                    if pv._cpPips[i] and pv._cpPips[i]:IsShown() then
                        if not firstVis then firstVis = pv._cpPips[i] end
                        lastVis = pv._cpPips[i]
                    end
                end
                -- Bar-type resource: use the bar frame as anchor
                local useBar = (not firstVis) and pv._cpBar and pv._cpBar:IsShown()
                local anchorFirst = firstVis or (useBar and pv._cpBar)
                local anchorLast  = lastVis  or (useBar and pv._cpBar)
                if anchorFirst and anchorLast then
                    local cpBtn = CreateFrame("Button", nil, pv)
                    cpBtn:SetPoint("TOPLEFT", anchorFirst, "TOPLEFT", -2, 2)
                    cpBtn:SetPoint("BOTTOMRIGHT", anchorLast, "BOTTOMRIGHT", 2, -2)
                    cpBtn:SetFrameLevel((pv._health and pv._health:GetFrameLevel() or 20) + 15)
                    cpBtn:RegisterForClicks("LeftButtonDown")
                    local cc = EllesmereUI.ELLESMERE_GREEN
                    local function MkCPHL()
                        local t = cpBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                        t:SetColorTexture(cc.r, cc.g, cc.b, 1)
                        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                        return t
                    end
                    local cpPx = SnapPreview(2)
                    local cpt = MkCPHL(); cpt:SetHeight(cpPx); cpt:SetPoint("TOPLEFT"); cpt:SetPoint("TOPRIGHT")
                    local cpb = MkCPHL(); cpb:SetHeight(cpPx); cpb:SetPoint("BOTTOMLEFT"); cpb:SetPoint("BOTTOMRIGHT")
                    local cpl = MkCPHL(); cpl:SetWidth(cpPx); cpl:SetPoint("TOPLEFT", cpt, "BOTTOMLEFT"); cpl:SetPoint("BOTTOMLEFT", cpb, "TOPLEFT")
                    local cpr = MkCPHL(); cpr:SetWidth(cpPx); cpr:SetPoint("TOPRIGHT", cpt, "BOTTOMRIGHT"); cpr:SetPoint("BOTTOMRIGHT", cpb, "TOPRIGHT")
                    cpBtn._hlTextures = { cpt, cpb, cpl, cpr }
                    local function ShowCPHL() for _, t in ipairs(cpBtn._hlTextures) do t:Show() end end
                    local function HideCPHL() for _, t in ipairs(cpBtn._hlTextures) do t:Hide() end end
                    HideCPHL()
                    cpBtn:SetScript("OnEnter", function() ShowCPHL() end)
                    cpBtn:SetScript("OnLeave", function() HideCPHL() end)
                    cpBtn:SetScript("OnMouseDown", function() NavigateToSetting("classResource") end)
                    cpOverlay = cpBtn
                    -- Disable hover/click when class resource setting is off
                    local function UpdateCPOverlay()
                        local off = DBVal("showClassPower") ~= true
                        cpBtn:EnableMouse(not off)
                        cpBtn:SetAlpha(off and 0 or 1)
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateCPOverlay)
                    UpdateCPOverlay()
                end
            end
            -- Sync overlay visibility with preview toggles
            pv._raidOverlay = raidOverlay
            pv._classOverlay = classOverlay
            -- Store text overlays for size refresh on preview update
            pv._textOverlays = textOverlays
        end

        return math.abs(y)
    end

    -- Textured Background: the Texture Settings cog row, shared by the Display
    -- page and Global Settings > Textures. kind: "health" or "cast"; apply: the
    -- page's own refresh after a write.
    local function TexBgRowCfg(kind, apply)
        local cast = kind == "cast"
        local key = cast and "castTextureBg" or "healthTextureBg"
        local texKey = cast and "castBarTexture" or "healthBarTexture"
        return ns.NP_BlizzOnlyGate({ type = "toggle", label = "Textured Background",
            tooltip = cast and "Draws the bar texture on the cast bar background too."
                or "Draws the bar texture on the health bar background too.",
            disabled = function() return (DBVal(texKey) or "none") == "none" end,
            disabledTooltip = cast and "This option requires a Cast Bar Texture other than None."
                or "This option requires a Bar Texture other than None.",
            get = function() return DBVal(key) == true end,
            set = function(v) DB()[key] = v and true or false; apply() end })
    end
    -- Shared with the page builders under Nameplates_Options\ (read in their
    -- prologs). Every field is final here: optState holds the mutable state.
    ns._NPO_OptEnv = {
        TexBgRowCfg = TexBgRowCfg,
        ADDON_NAME = ADDON_NAME, BAR_W = BAR_W, DB = DB,
        DBColor = DBColor, DBVal = DBVal, defaults = defaults, displayCastIcons = displayCastIcons,
        FOCUS_LETTER_ANCHOR_ORDER = FOCUS_LETTER_ANCHOR_ORDER,
        FOCUS_LETTER_ANCHORS = FOCUS_LETTER_ANCHORS, GetFocusLetterAnchor = GetFocusLetterAnchor,
        GetNPOptOutline = GetNPOptOutline, hbtOrder = hbtOrder, hbtValues = hbtValues,
        NAME_RAID_MARKER_GAP = NAME_RAID_MARKER_GAP, Nav = Nav,
        npDispelGlowDesc = npDispelGlowDesc, npImpCastGlowDesc = npImpCastGlowDesc,
        npPandemicGlowDesc = npPandemicGlowDesc, npCastTargetGlowDesc = npCastTargetGlowDesc,
        optState = optState, PAGE_DISPLAY = PAGE_DISPLAY, PAGE_FRIENDLY = PAGE_FRIENDLY, PAGE_TFH = PAGE_TFH,
        pairs = pairs, pcall = pcall, plates = plates, PP = PP,
        RandomizePreviewValues = RandomizePreviewValues, RefreshAllAuras = RefreshAllAuras,
        RefreshAllPlates = RefreshAllPlates, RefreshAllTextures = RefreshAllTextures,
        SearchWords = SearchWords,
        SECTION_AURA = SECTION_AURA, SECTION_CASTBAR = SECTION_CASTBAR,
        SECTION_ENEMY = SECTION_ENEMY, SECTION_ENEMY_NP = SECTION_ENEMY_NP,
        SECTION_MISC = SECTION_MISC, SECTION_THREAT = SECTION_THREAT, SetFSFont = SetFSFont,
        SetPVFont = SetPVFont, SliderLabel = SliderLabel,
        THREAT_PCT_POSITION_ORDER = THREAT_PCT_POSITION_ORDER,
        THREAT_PCT_POSITIONS = THREAT_PCT_POSITIONS, UpdatePreview = UpdatePreview,
    }

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    -- Rebuild preview when spec changes (class resource pips may appear/disappear)
    local npOptSpecFrame = CreateFrame("Frame")
    npOptSpecFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    npOptSpecFrame:SetScript("OnEvent", function(_, _, unit)
        if unit ~= "player" then return end
        -- Only invalidate + rebuild when the panel is open; invalidating while closed destroys all cached pages, causing a blank panel on next open.
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            EllesmereUI:InvalidatePageCache()
            C_Timer.After(0.2, function()
                EllesmereUI:RefreshPage(true)
            end)
        elseif EllesmereUI:GetActiveModule() == "EllesmereUINameplates"
           and EllesmereUI:GetActivePage() == PAGE_DISPLAY then
            -- Closed on the Display page: a spec preset can rewrite the texts, and
            -- a reopen shows the cached page without a restore. RefreshPage only
            -- flags a hidden panel, so the next open rebuilds this page once.
            EllesmereUI:RefreshPage(true)
        end
    end)

    EllesmereUI:RegisterModule("EllesmereUINameplates", {
        title       = "Nameplates",
        description = "Custom nameplate design and behavior.",
        pages       = { PAGE_DISPLAY, PAGE_COLORS, PAGE_TFH, PAGE_FRIENDLY, PAGE_GENERAL },
        tabLabels   = { [PAGE_DISPLAY] = "Enemy", [PAGE_COLORS] = "Enemy Colors", [PAGE_FRIENDLY] = "Friendly",
                        [PAGE_GENERAL] = "Extras" },
        -- Sections whose rows are on another page: a saved Spec or Conditional Override
        -- entry filed under one is listed, and opened by Go to Setting, on the page that
        -- holds its row (EUI_NS.EntryPage). Show Enemy Pet Nameplates is still on this page.
        movedSections = {
            [PAGE_DISPLAY] = { ["TARGET, FOCUS & HOVER EFFECTS"] = PAGE_TFH },
            [PAGE_GENERAL] = {
                ["TARGET AND FOCUS EFFECTS"] = PAGE_TFH,
                ["OTHER NAMEPLATES"] = { page = PAGE_FRIENDLY, stay = { ["Show Enemy Pet Nameplates"] = true } },
            },
        },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL then
                return ns.NPO_BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_DISPLAY then
                return BuildDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return ns.NPO_BuildColorsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TFH then
                return ns.NPO_BuildTargetFocusHoverPage(pageName, parent, yOffset)
            elseif pageName == PAGE_FRIENDLY then
                return ns.NPO_BuildFriendlyPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _displayHeaderBuilder
            elseif pageName == PAGE_TFH then
                return ns.NPO_BuildTFHHeader
            elseif pageName == PAGE_FRIENDLY then
                return ns.NPO_BuildFriendlyHeader
            end
            return nil  -- Colors and General have no content header
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- Rebuild when the texts' structure changed behind the cached
                -- page (a spec change while the panel was closed, a preset, a
                -- Style swap), so Core Text Positions and Core Text Coloring
                -- match the profile.
                if optState._npTextFP and ns.NPO_TextStructureFP() ~= optState._npTextFP then
                    C_Timer.After(0, function()
                        if EllesmereUI:GetActiveModule() == "EllesmereUINameplates"
                           and EllesmereUI:GetActivePage() == PAGE_DISPLAY then
                            EllesmereUI:RefreshPage(true)
                        end
                    end)
                end
                -- Re-evaluate Set as Default button visibility (cache restore blanket-shows all children, which can ghost the button).
                local pState = EllesmereUI._presetState and EllesmereUI._presetState[""]
                if pState and pState.UpdateDefaultBtnState then pState.UpdateDefaultBtnState() end
                -- Randomize preview values when switching TO this tab
                RandomizePreviewValues()
                -- Refresh the preview after cache restore
                if optState.activePreview and optState.activePreview.Update then optState.activePreview:Update() end
                -- The hint and the header's height by the hint's state
                Nav.HintRestore(PAGE_DISPLAY)
            elseif pageName == PAGE_TFH then
                -- Repaint the preview (settings can change behind the cached page)
                if optState.tfhPreview then optState.tfhPreview:Update() end
                Nav.HintRestore(PAGE_TFH)
            elseif pageName == PAGE_FRIENDLY then
                -- Repaint the sample plates (settings can change behind the cached page)
                ns.NPO_FriendlyPreviewUpdate()
                Nav.HintRestore(PAGE_FRIENDLY)
            end
        end,
        onReset     = function()
            -- Invalidate page cache so pages are rebuilt with fresh defaults
            EllesmereUI:InvalidatePageCache()
            -- Preserve user-saved presets (display + color), Custom presets, AND spec assignments across reset
            local old = DB()
            if old then
                local pD = old._presets
                local oD = old._presetOrder
                local pC = old._color_presets
                local oC = old._color_presetOrder
                local cD = old._customPreset
                local cC = old._color_customPreset
                local sA = old._specAssignments
                local sCA = old._color_specAssignments
                local sDP = old._specDefaultPreset
                for k in pairs(old) do old[k] = nil end
                if pD and next(pD) then old._presets = pD; old._presetOrder = oD end
                if pC and next(pC) then old._color_presets = pC; old._color_presetOrder = oC end
                if cD then old._customPreset = cD end
                if cC then old._color_customPreset = cC end
                if sA and next(sA) then old._specAssignments = sA end
                if sCA and next(sCA) then old._color_specAssignments = sCA end
                if sDP then old._specDefaultPreset = sDP end
                -- Explicitly activate EllesmereUI for both preset systems
                old._activePreset = "ellesmereui"
                old._color_activePreset = "ellesmereui"
            end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /enp  opens EllesmereUI to the Nameplates module
    ---------------------------------------------------------------------------
    SLASH_ELLESMERENAMEPLATES1 = "/enp"
    SlashCmdList.ELLESMERENAMEPLATES = function(msg)
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end

        if msg == "reset" then
            -- The reload first (RequestReload); the reset below lands before it.
            EllesmereUI.RequestReload()
            local _db = DB()
            if _db then
                local pD = _db._presets
                local oD = _db._presetOrder
                local pC = _db._color_presets
                local oC = _db._color_presetOrder
                local cD = _db._customPreset
                local cC = _db._color_customPreset
                local sA = _db._specAssignments
                local sCA = _db._color_specAssignments
                local sDP = _db._specDefaultPreset
                for k in pairs(_db) do _db[k] = nil end
                if pD and next(pD) then _db._presets = pD; _db._presetOrder = oD end
                if pC and next(pC) then _db._color_presets = pC; _db._color_presetOrder = oC end
                if cD then _db._customPreset = cD end
                if cC then _db._color_customPreset = cC end
                if sA and next(sA) then _db._specAssignments = sA end
                if sCA and next(sCA) then _db._color_specAssignments = sCA end
                if sDP then _db._specDefaultPreset = sDP end
                _db._activePreset = "ellesmereui"
                _db._color_activePreset = "ellesmereui"
            end
            return
        end

        EllesmereUI:ShowModule("EllesmereUINameplates")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
