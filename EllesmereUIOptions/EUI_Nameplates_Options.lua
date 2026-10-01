if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Options.lua: registers the Nameplates module with EllesmereUI.
--  All get/set calls go to ns.db.profile (centralized store); does NOT touch nameplate rendering logic.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUINameplates"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

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

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL   = "General"
local PAGE_DISPLAY   = "Display"
local PAGE_COLORS    = "Colors"

local SECTION_FRIENDLY  = "OTHER NAMEPLATES"
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
    THREAT_PCT_POSITIONS = { RIGHT = "Inside Right", LEFT = "Inside Left", CENTER = "Inside Center", BELOW = "Below Health Bar" }
    THREAT_PCT_POSITION_ORDER = { "RIGHT", "LEFT", "CENTER", "BELOW" }
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

    -- Preview font setter: mirrors SetFSFont shadow logic for direct SetFont calls
    local function SetPVFont(fs, fontPath, size, flags)
        EllesmereUI.ApplyModuleFont(fs, fontPath, size, "nameplates", flags)
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
        for _, plate in pairs(plates) do
            plate:UpdateHealth()
        end
    end

    local function RefreshAllAuras()
        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
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
    -- Nil until set: activePreview (preview frame), _previewHintFS (hint
    -- FontString), RefreshCoreEyes (Display page), _colorPreviewRefreshAll
    -- (Colors page, refreshes all color preview bars on cache restore).
    local optState = {}
    local _displayHeaderBuilder   -- stored for page cache re-use
    local _headerBaseH = 0               -- header height WITHOUT hint (for cache restore)

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    -- Raid marker hidden by default, toggled via eye icon; optState fields so both the preview and the Display page can access them.
    optState.showRaidMarkerPreview = false
    optState.showClassificationPreview = false
    optState.showTargetGlowPreview = false
    optState.showAbsorbPreview = false

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

    local function UpdatePreview()
        if optState.activePreview and optState.activePreview.Update then
            optState.activePreview:Update()
        end
    end

    -- Refresh the preview every time the panel is reopened
    EllesmereUI:RegisterOnShow(UpdatePreview)

    ---------------------------------------------------------------------------
    --  Glow sites: the Dispel and Important Cast glows as shared glow
    --  descriptors, used by the page rows and the Global Settings Glows page.
    ---------------------------------------------------------------------------
    local npDispelGlowDesc, npImpCastGlowDesc
    do
        local GO = EllesmereUI.GlowOptions
        local function RefreshDispel() RefreshAllAuras(); UpdatePreview() end
        -- Engine aura buttons (no Auto-Cast/Shape); an unset color is the
        -- suite default (gold).
        -- Blizzard Border: Blizzard's static stealable art, outside the view.
        local BLIZZ_BORDER = EllesmereUI.Glows.STEALABLE_BORDER
        npDispelGlowDesc = {
            view = ns.NP_GLOW_VIEW, host = "engine",
            extras = { { value = BLIZZ_BORDER, label = "Blizzard Border", style = BLIZZ_BORDER } },
            caps = { mode = true, params = true, bg = true },
            defaultColor = EllesmereUI.Glows.DEFAULT_COLOR,
            isOff = function() return DBVal("dispelGlow") ~= true end,
            -- Color by Type replaces the swatch color on every group.
            colorDisabled = function() return DBVal("dispelGlowUseTypeColor") == true end,
            colorDisabledTooltip = "Color by Type (Magic/Enrage)",
            onChange = RefreshDispel,
            get = function(f)
                local d = DB()
                if f == "style" then return ns.GetDispelGlowStyle and ns.GetDispelGlowStyle() or 2
                elseif f == "mode" then return d.dispelGlowColorMode or (d.dispelGlowColor and "custom" or "default")
                end
                return EllesmereUI.GlowOptions.FlatGet(d, "dispelGlow", f)
            end,
            set = function(f, a, b2, c2)
                local d = DB()
                if f == "style" then
                    if a == 0 then d.dispelGlow = false else d.dispelGlow = true; d.dispelGlowStyle = a end
                elseif f == "mode" then d.dispelGlowColorMode = a
                else EllesmereUI.GlowOptions.FlatSet(d, "dispelGlow", f, a, b2, c2)
                end
            end,
            -- off->on pays the per-plate aura-watcher cost -- prompt like other performance-priced enables; already-on style switches never prompt.
            confirm = function(v, commit)
                if v ~= 0 and DBVal("dispelGlow") ~= true then
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Dispel Glow",
                        message     = "Dispel Glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                        confirmText = "Enable",
                        cancelText  = "Cancel",
                        onConfirm   = commit,
                        onCancel    = function()
                            C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                        end,
                    })
                    return
                end
                commit()
            end,
            -- Magic buffs and enrages are separate groups in the buff row, so the
            -- color can follow the type; it overrides the color above per group.
            cogRows = {
                { type="toggle", label="Color by Type (Magic/Enrage)",
                  get=function() return DBVal("dispelGlowUseTypeColor") or false end,
                  set=function(v)
                      DB().dispelGlowUseTypeColor = v
                      RefreshDispel()
                      EllesmereUI:RefreshPage()
                  end },
            },
        }
        -- The cast bar is a bar host (no Shape).
        npImpCastGlowDesc = {
            view = ns.NP_GLOW_VIEW, host = "bar",
            caps = { mode = true, params = true, bg = true },
            defaultColor = { r = 1, g = 0.2, b = 0.2 },
            isOff = function()
                local d = DB()
                local on = d and d.importantCastGlow
                if on == nil then on = defaults.importantCastGlow end
                return not on
            end,
            onChange = RefreshAllPlates,
            get = function(f)
                local d = DB()
                if f == "style" then return d.importantCastGlowStyle or defaults.importantCastGlowStyle or 1
                elseif f == "mode" then return d.importantCastGlowColorMode or "custom"
                end
                return EllesmereUI.GlowOptions.FlatGet(d, "importantCastGlow", f, defaults)
            end,
            set = function(f, a, b2, c2)
                local d = DB()
                if f == "style" then
                    if a == 0 then d.importantCastGlow = false
                    else d.importantCastGlow = true; d.importantCastGlowStyle = a end
                elseif f == "mode" then d.importantCastGlowColorMode = a
                else EllesmereUI.GlowOptions.FlatSet(d, "importantCastGlow", f, a, b2, c2)
                end
            end,
        }
        GO.RegisterSite({ id = "np_dispel", label = "Dispel Glow", group = "module",
            module = "EllesmereUINameplates", page = PAGE_GENERAL, section = SECTION_AURA,
            highlight = "Dispel Glow Style", desc = npDispelGlowDesc })
        GO.RegisterSite({ id = "np_importantcast", label = "Important Cast Glow", group = "module",
            module = "EllesmereUINameplates", page = PAGE_DISPLAY, section = SECTION_CASTBAR,
            highlight = "Important Cast Glow", desc = npImpCastGlowDesc })
    end

    ---------------------------------------------------------------------------
    --  Display page  (preview in content header + settings in scroll area)
    ---------------------------------------------------------------------------
    local LazyColorPreviewBar -- forward declaration; defined with the Colors page helpers below

    local function BuildDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- Set content header with preview centered above nameplate preview
        _displayHeaderBuilder = function(headerParent, headerW)

            local PRESET_HEADER_H = 0
            local PREVIEW_TOP_PAD = 10
            local PREVIEW_BOTTOM_PAD = 5
            local previewH = ns.NPO_BuildNameplatePreview(headerParent, headerW)
            -- Position the preview at the top of the header area. pf's SetScale matches the UIParent/panel ratio, so SetPoint offsets (in that scaled space) must divide by the same ratio for the correct visual offset.
            if optState.activePreview then
                optState.activePreview:ClearAllPoints()
                local correction = UIParent:GetEffectiveScale() / headerParent:GetEffectiveScale()
                optState.activePreview:SetPoint("TOP", headerParent, "TOP", 0, -(PRESET_HEADER_H + PREVIEW_TOP_PAD) / correction)
                optState.activePreview._headerExtra = PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD
            end

            -- "Click elements" hint: parented to activePreview (not headerParent directly, which orphaned it via ClearContentHeaderInner on page switch) so the FontString travels through the content-header cache; if orphaned (parent gone), nil it to recreate.
            if optState._previewHintFS and not optState._previewHintFS:GetParent() then
                optState._previewHintFS = nil
            end
            local hintShown = not IsPreviewHintDismissed()
            if hintShown then
                if not optState._previewHintFS then
                    optState._previewHintFS = EllesmereUI.MakeFont(optState.activePreview or headerParent, 11, nil, 1, 1, 1)
                    optState._previewHintFS:SetAlpha(0.45)
                    optState._previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                optState._previewHintFS:SetParent(optState.activePreview or headerParent)
                optState._previewHintFS:ClearAllPoints()
                optState._previewHintFS:SetPoint("BOTTOM", headerParent, "BOTTOM", 0, 17)
                optState._previewHintFS:SetAlpha(0.45)
                optState._previewHintFS:Show()
            elseif optState._previewHintFS then
                optState._previewHintFS:Hide()
            end

            _headerBaseH = previewH + PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD
            return _headerBaseH + (hintShown and 29 or 0)
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
            if element == "none" then
                -- Clear: find whatever element is at this position and move it to "none"
                local db = DB()
                for _, key in ipairs(slotKeys) do
                    if (db[key] or defaults[key]) == pos then
                        db[key] = "none"
                    end
                end
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
                local ds, bs, cs = ns.GetAuraSlots()
                if bs ~= "none" then
                    local buffSz = ns.GetBuffIconSize()
                    local buffH = ns.GetAuraCropHeight(ns.GetAuraCrop("buffs"), buffSz)
                    local bxOff, byOff = ns.GetSlotOffsets(bs)
                    ns.PositionAuraSlot(plate.buffs, 4, bs, plate, buffSz, buffH, ns.GetAuraSpacing("buffs"), bxOff, byOff)
                else
                    for i = 1, 4 do plate.buffs[i]:Hide() end
                end
                if cs ~= "none" then
                    local ccSz = ns.GetCCIconSize()
                    local ccH = ns.GetAuraCropHeight(ns.GetAuraCrop("ccs"), ccSz)
                    local cxOff, cyOff = ns.GetSlotOffsets(cs)
                    ns.PositionAuraSlot(plate.cc, 2, cs, plate, ccSz, ccH, ns.GetAuraSpacing("ccs"), cxOff, cyOff)
                else
                    for i = 1, 2 do plate.cc[i]:Hide() end
                end
                if ds == "none" then
                    for i = 1, 4 do plate.debuffs[i]:Hide() end
                end
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
            if element ~= "none" then
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

        -- Shared helper: apply a timer position to live plates for one aura type
        local function LiveApplyTimerPos(auraFrames, count, v, kind)
            local durC = AuraDurationVal(kind, "Color")
            local durSz = AuraDurationVal(kind, "Size")
            local durX = AuraDurationVal(kind, "X")
            local durY = AuraDurationVal(kind, "Y")
            for _, plate in pairs(plates) do
                for i = 1, count do
                    local af = auraFrames(plate, i)
                    if af and af.cd then
                        if v == "none" then
                            if af.cd.SetHideCountdownNumbers then
                                af.cd:SetHideCountdownNumbers(true)
                            end
                        else
                            if af.cd.SetHideCountdownNumbers then
                                af.cd:SetHideCountdownNumbers(false)
                            end
                            if af.cd.text then
                                SetFSFont(af.cd.text, durSz, "OUTLINE, SLUG")
                                af.cd.text:SetTextColor(durC.r, durC.g, durC.b, 1)
                                af.cd.text:ClearAllPoints()
                                if v == "center" then
                                    af.cd.text:SetPoint("CENTER", af, "CENTER", durX, durY)
                                    af.cd.text:SetJustifyH("CENTER")
                                elseif v == "topright" then
                                    PP.Point(af.cd.text, "TOPRIGHT", af, "TOPRIGHT", 3 + durX, 4 + durY)
                                    af.cd.text:SetJustifyH("RIGHT")
                                elseif v == "bottomleft" then
                                    PP.Point(af.cd.text, "BOTTOMLEFT", af, "BOTTOMLEFT", -3 + durX, -4 + durY)
                                    af.cd.text:SetJustifyH("LEFT")
                                elseif v == "bottomright" then
                                    PP.Point(af.cd.text, "BOTTOMRIGHT", af, "BOTTOMRIGHT", 3 + durX, -4 + durY)
                                    af.cd.text:SetJustifyH("RIGHT")
                                else
                                    PP.Point(af.cd.text, "TOPLEFT", af, "TOPLEFT", -3 + durX, 4 + durY)
                                    af.cd.text:SetJustifyH("LEFT")
                                end
                            end
                        end
                    end
                end
            end
            -- 12.1 aura containers render the text through the style pass instead of the legacy frames above (fingerprint-guarded; nil on 12.0).
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end

        -- Shared helper: apply a stack-count position to live plates for one aura type
        local function LiveApplyStackPos(auraFrames, count, v)
            local stkC = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
            local stkSz = DBVal("auraStackTextSize") or defaults.auraStackTextSize
            local stkX = DBVal("auraStackTextX") or defaults.auraStackTextX
            local stkY = DBVal("auraStackTextY") or defaults.auraStackTextY
            for _, plate in pairs(plates) do
                for i = 1, count do
                    local af = auraFrames(plate, i)
                    if af and af.count then
                        if v == "none" then
                            af.count:Hide()
                        else
                            af.count:Show()
                            SetFSFont(af.count, stkSz, "OUTLINE, SLUG")
                            af.count:SetTextColor(stkC.r, stkC.g, stkC.b, 1)
                            af.count:ClearAllPoints()
                            if v == "center" then
                                af.count:SetPoint("CENTER", af, "CENTER", stkX, stkY)
                                af.count:SetJustifyH("CENTER")
                            elseif v == "topright" then
                                PP.Point(af.count, "TOPRIGHT", af, "TOPRIGHT", 3 + stkX, 4 + stkY)
                                af.count:SetJustifyH("RIGHT")
                            elseif v == "bottomleft" then
                                PP.Point(af.count, "BOTTOMLEFT", af, "BOTTOMLEFT", -3 + stkX, -4 + stkY)
                                af.count:SetJustifyH("LEFT")
                            elseif v == "topleft" then
                                PP.Point(af.count, "TOPLEFT", af, "TOPLEFT", -3 + stkX, 4 + stkY)
                                af.count:SetJustifyH("LEFT")
                            else
                                PP.Point(af.count, "BOTTOMRIGHT", af, "BOTTOMRIGHT", 3 + stkX, -4 + stkY)
                                af.count:SetJustifyH("RIGHT")
                            end
                        end
                    end
                end
            end
            -- 12.1 aura containers: stacks render through the style pass (fingerprint-guarded; nil on 12.0).
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end

        local atFallback = DBVal("auraTextPosition") or defaults.auraTextPosition
        local asFallback = DBVal("auraStackTextPosition") or defaults.auraStackTextPosition

        -- The sections live in Nameplates_Options\DisplayLayout_Options.lua and
        -- DisplayBars_Options.lua; they return the rows the click navigation
        -- below maps to.
        local ctx = {
            W = W, GetElementAtPosition = GetElementAtPosition, RefreshAllSlots = RefreshAllSlots,
            SetElementAtPosition = SetElementAtPosition,
            SetTextElementAtSlot = SetTextElementAtSlot, asFallback = asFallback,
            atFallback = atFallback, AuraDurationVal = AuraDurationVal,
            LiveApplyStackPos = LiveApplyStackPos, LiveApplyTimerPos = LiveApplyTimerPos,
            timerPosOrder = timerPosOrder, timerPosValues = timerPosValues,
        }
        local styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textRow1
        local textRow2, textRow3
        y, styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textRow1, textRow2,
            textRow3, ctx.ShowCogPopup, ctx.CogPopupOpen,
            ctx.RefreshAllTextures = ns.NPO_BuildDisplayLayout(parent, y, ctx)
        local healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow
        local tfxHeader, targetGlowRow, classResourceHeader, classResourceSection, generalTextHeader
        local auraDurPosRow, auraTimerStackRow, spellNameRow
        y, healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow,
            tfxHeader, targetGlowRow, classResourceHeader, classResourceSection, generalTextHeader,
            auraDurPosRow, auraTimerStackRow, spellNameRow = ns.NPO_BuildDisplayBars(parent, y, ctx)

        -----------------------------------------------------------------------
        --  CLICK NAVIGATION: glow, scroll, mapping, hit overlays
        -----------------------------------------------------------------------
        local PlaySettingGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN, thickness = function() return PP.Scale(2) end, noSnap = true })

        -- Maps Core Position slot keys to their row/region
        local corePosToRow = {
            top      = { row = coreRow1, side = "_leftRegion" },
            right    = { row = coreRow1, side = "_rightRegion" },
            left     = { row = coreRow2, side = "_leftRegion" },
            topright = { row = coreRow2, side = "_rightRegion" },
            topleft  = { row = coreRow3, side = "_leftRegion" },
        }

        -- Maps Core Text Position slot keys to their row/region
        local textSlotToRow = {
            textSlotTop    = { row = textRow1, side = "_leftRegion" },
            textSlotRight  = { row = textRow1, side = "_rightRegion" },
            textSlotLeft   = { row = textRow2, side = "_leftRegion" },
            textSlotCenter = { row = textRow2, side = "_rightRegion" },
            textSlotBottomLeft  = { row = textRow3, side = "_leftRegion" },
            textSlotBottomRight = { row = textRow3, side = "_rightRegion" },
        }

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

        -- Resolve a dynamic click mapping for icon elements Core Positions row
        local function ResolveCoreMapping(element)
            local pos = FindCorePosForElement(element)
            if not pos then return { section = coreHeader, target = coreRow1 } end
            local info = corePosToRow[pos]
            if not info then return { section = coreHeader, target = coreRow1 } end
            return { section = coreHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
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
            targetArrows = { section = tfxHeader,            target = targetGlowRow,       slotSide = "right" },
        }

        -- Dynamic resolvers for elements assigned to Core Positions / Core Text Positions
        local dynamicMappings = {
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
            -- Combined with Rare/Quest, the badge's settings live on that row.
            factionIcon  = function()
                if DB().classificationIncludeFaction then return ResolveCoreMapping("classification") end
                return ResolveCoreMapping("faction")
            end,
            enemyName    = function()
                -- The name FontString renders whichever name-family variant is slotted; resolve the row for any of them.
                local slot = FindTextSlotForElement("enemyName") or FindTextSlotForElement("levelName") or FindTextSlotForElement("nameLevel")
                if not slot then return { section = coreTextHeader, target = textRow1 } end
                local info = textSlotToRow[slot]
                if not info then return { section = coreTextHeader, target = textRow1 } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end,
            healthText   = function()
                local slot = FindTextSlotForElement("healthPercent") or FindTextSlotForElement("healthPercentNoSign") or FindTextSlotForElement("healthPctNum") or FindTextSlotForElement("healthNumPct") or FindTextSlotForElement("healthPctNumDash") or FindTextSlotForElement("healthNumPctDash")
                if not slot then return { section = coreTextHeader, target = textRow1 } end
                local info = textSlotToRow[slot]
                if not info then return { section = coreTextHeader, target = textRow1 } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end,
        }
        -- The font strings a single element owns: the row of the slot showing it.
        for mapKey, element in pairs({ healthNumber = "healthNumber", levelText = "level", targetOfTarget = "targetOfTarget" }) do
            dynamicMappings[mapKey] = function()
                local info = textSlotToRow[FindTextSlotForElement(element) or ""]
                if not info then return { section = coreTextHeader, target = textRow1 } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end
        end

        local function NavigateToSetting(key)
            local m = clickMappings[key]
            -- Check dynamic mappings (icon/text elements assigned to Core Positions)
            if not m then
                local resolver = dynamicMappings[key]
                if resolver then m = resolver() end
            end
            if not m or not m.section or not m.target then return end

            -- Header grows by 29 but shrinks by 39 (kept as shipped).
            EllesmereUI.DismissPreviewHint(optState._previewHintFS, _headerBaseH, 29, 17)

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
            C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
        end

        -- Hit overlay factory for preview elements. opts (optional): hlAnchor = frame to draw the highlight around (instead of btn); hlBehindText = true draws it on a child frame at icon level+1 (text lives at icon level+2).
        local function SnapPreview(val)
            local s = optState.activePreview and optState.activePreview:GetEffectiveScale() or 1
            if s <= 0 then s = 1 end
            return math.floor(val * s + 0.5) / s
        end
        -- Destroy any stale hit overlays from a previous BuildDisplayPage call (RefreshPage can re-call buildPage without cleaning the preview).
        if optState.activePreview and optState.activePreview._hitOverlays then
            for i = 1, #optState.activePreview._hitOverlays do
                local ov = optState.activePreview._hitOverlays[i]
                ov:EnableMouse(false)
                ov:Hide()
                ov:SetParent(nil)
            end
            wipe(optState.activePreview._hitOverlays)
        end

        local allOverlays = {}

        local hitStyle = { container = true }
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            local btn, hlBase, hlCont = EllesmereUI.CreatePreviewHitOverlay(element, NavigateToSetting, mappingKey, isText, frameLevelOverride, opts, hitStyle)
            allOverlays[#allOverlays + 1] = btn
            if hlBase ~= btn then allOverlays[#allOverlays + 1] = hlBase end
            allOverlays[#allOverlays + 1] = hlCont
            return btn
        end

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
                    allOverlays[#allOverlays + 1] = iconOv
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
                allOverlays[#allOverlays + 1] = castOverlay
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
                    allOverlays[#allOverlays + 1] = cpBtn
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
            -- Target arrows wrapper button spanning both arrow textures
            local arrowOverlay
            if pv._arrows then
                local arrowBtn = CreateFrame("Button", nil, pv)
                arrowBtn:SetPoint("TOPLEFT", pv._arrows.left, "TOPLEFT", -2, 2)
                arrowBtn:SetPoint("BOTTOMRIGHT", pv._arrows.right, "BOTTOMRIGHT", 2, -2)
                arrowBtn:SetFrameLevel((pv._health and pv._health:GetFrameLevel() or 20) + 15)
                arrowBtn:RegisterForClicks("LeftButtonDown")
                local cc = EllesmereUI.ELLESMERE_GREEN
                local function MkAHL()
                    local t = arrowBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(cc.r, cc.g, cc.b, 1)
                    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                    return t
                end
                -- Highlight on left arrow
                local aPx = SnapPreview(2)
                local alt = MkAHL(); alt:SetHeight(aPx); alt:SetPoint("TOPLEFT", pv._arrows.left, -2, 2); alt:SetPoint("TOPRIGHT", pv._arrows.left, 2, 2)
                local alb = MkAHL(); alb:SetHeight(aPx); alb:SetPoint("BOTTOMLEFT", pv._arrows.left, -2, -2); alb:SetPoint("BOTTOMRIGHT", pv._arrows.left, 2, -2)
                local all = MkAHL(); all:SetWidth(aPx); all:SetPoint("TOPLEFT", alt, "BOTTOMLEFT"); all:SetPoint("BOTTOMLEFT", alb, "TOPLEFT")
                local alr = MkAHL(); alr:SetWidth(aPx); alr:SetPoint("TOPRIGHT", alt, "BOTTOMRIGHT"); alr:SetPoint("BOTTOMRIGHT", alb, "TOPRIGHT")
                -- Highlight on right arrow
                local art = MkAHL(); art:SetHeight(aPx); art:SetPoint("TOPLEFT", pv._arrows.right, -2, 2); art:SetPoint("TOPRIGHT", pv._arrows.right, 2, 2)
                local arb = MkAHL(); arb:SetHeight(aPx); arb:SetPoint("BOTTOMLEFT", pv._arrows.right, -2, -2); arb:SetPoint("BOTTOMRIGHT", pv._arrows.right, 2, -2)
                local arl = MkAHL(); arl:SetWidth(aPx); arl:SetPoint("TOPLEFT", art, "BOTTOMLEFT"); arl:SetPoint("BOTTOMLEFT", arb, "TOPLEFT")
                local arr = MkAHL(); arr:SetWidth(aPx); arr:SetPoint("TOPRIGHT", art, "BOTTOMRIGHT"); arr:SetPoint("BOTTOMRIGHT", arb, "TOPRIGHT")
                arrowBtn._hlTextures = { alt, alb, all, alr, art, arb, arl, arr }
                local function ShowAHL() for _, t in ipairs(arrowBtn._hlTextures) do t:Show() end end
                local function HideAHL() for _, t in ipairs(arrowBtn._hlTextures) do t:Hide() end end
                HideAHL()
                arrowBtn:SetScript("OnEnter", function() ShowAHL() end)
                arrowBtn:SetScript("OnLeave", function() HideAHL() end)
                arrowBtn:SetScript("OnMouseDown", function() NavigateToSetting("targetArrows") end)
                -- Only show when arrows are visible
                if not pv._arrows.left:IsShown() then arrowBtn:Hide() end
                arrowOverlay = arrowBtn
                allOverlays[#allOverlays + 1] = arrowBtn
            end
            pv._arrowOverlay = arrowOverlay
            -- Store text overlays for size refresh on preview update
            pv._textOverlays = textOverlays
            -- Store all overlays for cleanup on next rebuild
            pv._hitOverlays = allOverlays
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Colors page
    ---------------------------------------------------------------------------

    -- Spell icon pool for cast bar previews, cycled in order
    local castIconPool = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local castIconIdx = 0
    local function NextCastIcon()
        castIconIdx = castIconIdx + 1
        if castIconIdx > #castIconPool then castIconIdx = 1 end
        return castIconPool[castIconIdx]
    end

    -- Cast fill values: each at least 5% apart, range 40 90%
    local castFillUsed = {}
    local function NextCastFill()
        for _ = 1, 50 do
            local v = 0.40 + math.random() * 0.20
            local ok = true
            for _, prev in ipairs(castFillUsed) do
                if math.abs(v - prev) < 0.05 then ok = false; break end
            end
            if ok then
                castFillUsed[#castFillUsed + 1] = v
                return v
            end
        end
        -- fallback if somehow can't find a valid value
        local v = 0.40 + math.random() * 0.20
        castFillUsed[#castFillUsed + 1] = v
        return v
    end

    -- Shared preview bar list and lazy builder (used by both Display and Colors pages)
    local _colorPagePreviews = {}

    LazyColorPreviewBar = function(parentRow, colorType, colorKey, anchorFrame)
        local real = nil
        local proxy = {}
        local _disabled = false
        local _colorOverrideFn = nil
        local function EnsureBuilt()
            if real then return real end
            real = ns.NPO_MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
            if _disabled and real._health then real._health:SetAlpha(0.3) end
            return real
        end
        proxy.UpdateColor = function()
            local r = EnsureBuilt()
            if r and r.UpdateColor then
                if _colorOverrideFn then
                    local cr, cg, cb = _colorOverrideFn()
                    if cr and r._health then
                        r._health:SetStatusBarColor(cr, cg, cb, 1)
                        return
                    end
                end
                r.UpdateColor()
            end
        end
        proxy.UpdateOverlay = function()
            local r = EnsureBuilt()
            if r and r.UpdateOverlay then r.UpdateOverlay() end
        end
        proxy.RefreshBorderStyle = function()
            if real and real.RefreshBorderStyle then real.RefreshBorderStyle() end
        end
        proxy.RefreshBorderColor = function()
            if real and real.RefreshBorderColor then real.RefreshBorderColor() end
        end
        proxy.Randomize = function()
            if real and real.Randomize then real.Randomize() end
        end
        proxy.RefreshHealthText = function()
            if real and real.RefreshHealthText then real.RefreshHealthText() end
        end
        proxy.SetDisabled = function(off)
            _disabled = off
            if real and real._health then
                real._health:SetAlpha(off and 0.3 or 1)
            end
        end
        proxy.SetColorOverride = function(fn)
            _colorOverrideFn = fn
        end
        parentRow:HookScript("OnShow", function()
            if not real then
                EnsureBuilt()
                _G._EUI_ColorPreviews[#_G._EUI_ColorPreviews + 1] = real
            end
            if real and real._health then
                real._health:SetAlpha(_disabled and 0.3 or 1)
            end
        end)
        if parentRow:IsVisible() then
            EnsureBuilt()
        end
        _colorPagePreviews[#_colorPagePreviews + 1] = proxy
        return proxy
    end

    -- Shared with the page builders under Nameplates_Options\ (read in their
    -- prologs). Every field is final here: optState holds the mutable state.
    ns._NPO_OptEnv = {
        _colorPagePreviews = _colorPagePreviews, ADDON_NAME = ADDON_NAME, BAR_W = BAR_W, DB = DB,
        DBColor = DBColor, DBVal = DBVal, defaults = defaults, displayCastIcons = displayCastIcons,
        FOCUS_LETTER_ANCHOR_ORDER = FOCUS_LETTER_ANCHOR_ORDER,
        FOCUS_LETTER_ANCHORS = FOCUS_LETTER_ANCHORS, GetFocusLetterAnchor = GetFocusLetterAnchor,
        GetNPOptOutline = GetNPOptOutline, hbtOrder = hbtOrder, hbtValues = hbtValues,
        LazyColorPreviewBar = LazyColorPreviewBar, NAME_RAID_MARKER_GAP = NAME_RAID_MARKER_GAP,
        NextCastFill = NextCastFill, NextCastIcon = NextCastIcon,
        npDispelGlowDesc = npDispelGlowDesc, npImpCastGlowDesc = npImpCastGlowDesc,
        optState = optState, pairs = pairs, pcall = pcall, plates = plates, PP = PP,
        RandomizePreviewValues = RandomizePreviewValues, RefreshAllAuras = RefreshAllAuras,
        RefreshAllPlates = RefreshAllPlates, SECTION_AURA = SECTION_AURA,
        SECTION_CASTBAR = SECTION_CASTBAR, SECTION_ENEMY = SECTION_ENEMY,
        SECTION_ENEMY_NP = SECTION_ENEMY_NP, SECTION_FRIENDLY = SECTION_FRIENDLY,
        SECTION_MISC = SECTION_MISC, SECTION_THREAT = SECTION_THREAT, SetFSFont = SetFSFont,
        SetPVFont = SetPVFont, THREAT_PCT_POSITION_ORDER = THREAT_PCT_POSITION_ORDER,
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
        end
    end)

    EllesmereUI:RegisterModule("EllesmereUINameplates", {
        title       = "Nameplates",
        description = "Custom nameplate design and behavior.",
        pages       = { PAGE_DISPLAY, PAGE_COLORS, PAGE_GENERAL },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL then
                return ns.NPO_BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_DISPLAY then
                return BuildDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return ns.NPO_BuildColorsPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _displayHeaderBuilder
            end
            return nil  -- General and Colors have no content header
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- Re-evaluate Set as Default button visibility (cache restore blanket-shows all children, which can ghost the button).
                local pState = EllesmereUI._presetState and EllesmereUI._presetState[""]
                if pState and pState.UpdateDefaultBtnState then pState.UpdateDefaultBtnState() end
                -- Randomize preview values when switching TO this tab
                RandomizePreviewValues()
                -- Refresh the preview after cache restore
                if optState.activePreview and optState.activePreview.Update then optState.activePreview:Update() end
                -- Refresh hint visibility only; never recreate here.
                local dismissed = IsPreviewHintDismissed()
                if optState._previewHintFS then
                    if dismissed then
                        optState._previewHintFS:Hide()
                    else
                        optState._previewHintFS:SetAlpha(0.45)
                        optState._previewHintFS:Show()
                    end
                end
                -- Set correct header height based on current hint state
                if _headerBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(_headerBaseH + (dismissed and 0 or 29))
                end
            elseif pageName == PAGE_COLORS then
                -- Refresh all color preview bars (colors from DB)
                if optState._colorPreviewRefreshAll then optState._colorPreviewRefreshAll() end
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
            EllesmereUI.RequestReload()
            return
        end

        EllesmereUI:ShowModule("EllesmereUINameplates")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
