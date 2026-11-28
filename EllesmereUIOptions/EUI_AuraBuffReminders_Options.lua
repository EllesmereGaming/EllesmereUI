if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Options.lua
--  Registers the AuraBuff Reminders module with EllesmereUI
--  Tabs: Auras, Buffs & Consumables | Talent Reminders (retail) | Loadout
--  Manager (EUI_AuraBuffReminders_Loadouts_Options.lua builds it)
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIAuraBuffReminders"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local PAGE_REMINDERS = "Auras, Buffs & Consumables"
local PAGE_TALENTS   = "Talent Reminders"
local PAGE_LOADOUTS  = "Loadout Manager"
local PAGE_UNLOCK    = "Unlock Mode"

-- WoW Forever: the page keeps CORE, DISPLAY and RAID BUFFS (that client's
-- locations and its own buffs) and swaps every other retail section for the two
-- Forever sections, SELF BUFFS and CONSUMABLES; the Talent Reminders page does
-- not exist there.
local FOREVER = EllesmereUI.IS_FOREVER == true
-- The Mage Armors and Class Buffs slots are the SELF BUFFS rows that are
-- class-only. Class never changes mid-session, so unlike the Beacon M+ row no
-- watcher is needed.
local MAGE = FOREVER and select(2, UnitClass("player")) == "MAGE"

local SECTION_CORE         = "CORE"
local SECTION_SELF_BUFFS   = "SELF BUFFS"
local SECTION_DISPLAY      = "DISPLAY"
local SECTION_RAID_BUFFS   = "RAID BUFFS"
local SECTION_AURAS        = "AURAS"
local SECTION_CONSUMABLES  = "CONSUMABLES"
local SECTION_ROGUE        = "ROGUE POISONS"
local SECTION_PALADIN      = "PALADIN RITES"
local SECTION_SHAMAN       = "SHAMAN IMBUES & SHIELDS"
local SECTION_WARLOCK      = "WARLOCK"
local SPECIAL_WHERE_TIP    = "Pick which content these reminders appear in.\nRested areas (cities and inns) always stay hidden."

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP
    -- Page reuse (EllesmereUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local Pool = EllesmereUI._Pool
    local CreateFrame = Pool.CreateFrame

    local function GetABROptOutline() return EllesmereUI.GetFontOutlineFlag("auraBuff") end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db
    C_Timer.After(0, function() db = _G._EABR_AceDB end)

    local function DB()
        if not db then db = _G._EABR_AceDB end
        return db and db.profile
    end
    local function DDB()  local p = DB(); return p and p.display end

    local function GetNameFontPath()
        local d = DDB()
        local fontName = d and d.nameFont
        if fontName and fontName ~= "__global" and EllesmereUI.ResolveFontName then
            local path = EllesmereUI.ResolveFontName(fontName)
            if path and path ~= "" then return path end
        end
        return (EllesmereUI.GetFontPath("auraBuff")) or "Fonts\\ARIALN.TTF"
    end

    local PREVIEW_TEXT_ANCHORS = _G._EABR_TEXT_ANCHORS
    local function GetPreviewTextAnchor(d)
        local m = PREVIEW_TEXT_ANCHORS[(d and d.textAnchor) or "BOTTOM"] or PREVIEW_TEXT_ANCHORS.BOTTOM
        return m[1], m[2]
    end
    local function RDB()  local p = DB(); return p and p.raidBuffs end
    local function ADB()  local p = DB(); return p and p.auras end
    local function CDB()  local p = DB(); return p and p.consumables end
    local function FDB()  local p = DB(); return p and p.forever end  -- WoW Forever section (nil on retail)

    ---------------------------------------------------------------------------
    --  Refresh
    ---------------------------------------------------------------------------
    local function RefreshAll()
        if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    end

    ---------------------------------------------------------------------------
    --  Preview Header shows potential buff/aura icons for current class/spec
    ---------------------------------------------------------------------------
    local _previewHeaderBuilder
    local _previewIcons = {}
    local _previewContainer
    local _previewHintFS

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    local Known = function(id)
        return id and (C_SpellBook.IsSpellKnown(id)
            or C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, false))
    end
    local Tex = function(id) return _G._EABR_Tex and _G._EABR_Tex(id) or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400 end

    --- Shorten a buff/aura label to its first word, with special overrides.
    local LABEL_OVERRIDES = {
        ["Battle Stance"]           = "Stance",
        ["Defensive Stance"]        = "Stance",
        ["Berserker Stance"]        = "Stance",
        ["Devotion Aura"]           = "Aura",
        ["Power Word: Fortitude"]   = "Fortitude",
        ["Arcane Intellect"]        = "Intellect",
        ["Battle Shout"]            = "Shout",
    }
    local LABEL_CLASS_OVERRIDES = {
        ROGUE  = "Poison",   -- all rogue poisons
        SHAMAN_IMBUE  = "Weapon",  -- all shaman weapon imbues
        SHAMAN_SHIELD = "Shield",  -- all shaman shields
    }
    local function ShortLabel(name, classOverride)
        if classOverride and LABEL_CLASS_OVERRIDES[classOverride] then
            return EllesmereUI.L(LABEL_CLASS_OVERRIDES[classOverride])
        end
        if LABEL_OVERRIDES[name] then return LABEL_OVERRIDES[name] end
        return name:match("^(%S+)") or name
    end

    --- Collect all potential preview icons for the player's class/spec
    local function CollectPreviewIcons()
        local icons = {}
        if FOREVER then return icons end  -- no preview on WoW Forever (and the spec lookups below are retail-only globals)
        local _, playerClass = UnitClass("player")
        local specIdx = GetSpecialization()
        local specID = specIdx and GetSpecializationInfo(specIdx) or nil
        local rb = RDB()
        local au = ADB()
        local co = CDB()

        -- 1) Raid buffs for this class (only enabled ones)
        local RAID_BUFFS = _G._EABR_RAID_BUFFS or {}
        for _, buff in ipairs(RAID_BUFFS) do
            if buff.class == playerClass and Known(buff.castSpell) then
                if rb and rb.enabled and rb.enabled[buff.key] then
                    icons[#icons+1] = { texture = Tex(buff.castSpell), label = ShortLabel(_G._EABR_SpellName(buff.castSpell, buff.name)), cat = "raidbuff", itemKey = buff.key }
                end
            end
        end

        -- 2) Auras valid for this class/spec (only enabled ones)
        local AURAS = _G._EABR_AURAS or {}
        local beaconAdded = false
        for _, aura in ipairs(AURAS) do
            if aura.class == playerClass and Known(aura.castSpell) then
                if au and au.enabled and au.enabled[aura.key] then
                    local specOk = true
                    if aura.specs then
                        specOk = false
                        for _, s in ipairs(aura.specs) do if s == specID then specOk = true; break end end
                    end
                    if specOk then
                        if aura.key == "bol" or aura.key == "bof" then
                            if not beaconAdded then
                                icons[#icons+1] = { texture = Tex(aura.castSpell), label = ShortLabel(_G._EABR_SpellName(aura.castSpell, aura.name)), cat = "aura", itemKey = aura.key }
                                beaconAdded = true
                            end
                        else
                            icons[#icons+1] = { texture = Tex(aura.castSpell), label = ShortLabel(_G._EABR_SpellName(aura.castSpell, aura.name)), cat = "aura", itemKey = aura.key }
                        end
                    end
                end
            end
        end

        -- 3) Consumables (only show enabled ones, one per type)
        -- Rogue poisons: show first enabled
        if playerClass == "ROGUE" then
            local POISONS = _G._EABR_ROGUE_POISONS or {}
            for _, poison in ipairs(POISONS) do
                if Known(poison.castSpell) and co and co.enabled and co.enabled[poison.key] then
                    icons[#icons+1] = { texture = Tex(poison.castSpell), label = ShortLabel(_G._EABR_SpellName(poison.castSpell, poison.name), "ROGUE"), cat = "consumable", itemKey = poison.key }
                    break
                end
            end
        end

        -- Paladin rites: show first enabled
        if playerClass == "PALADIN" then
            local RITES = _G._EABR_PALADIN_RITES or {}
            for _, rite in ipairs(RITES) do
                if Known(rite.castSpell) and co and co.enabled and co.enabled[rite.key] then
                    icons[#icons+1] = { texture = Tex(rite.castSpell), label = ShortLabel(_G._EABR_SpellName(rite.castSpell, rite.name)), cat = "consumable", itemKey = rite.key }
                    break
                end
            end
        end

        -- Shaman imbues: show first enabled
        if playerClass == "SHAMAN" then
            local IMBUES = _G._EABR_SHAMAN_IMBUES or {}
            for _, imbue in ipairs(IMBUES) do
                if Known(imbue.castSpell) and co and co.enabled and co.enabled[imbue.key] then
                    icons[#icons+1] = { texture = Tex(imbue.castSpell), label = ShortLabel(_G._EABR_SpellName(imbue.castSpell, imbue.name), "SHAMAN_IMBUE"), cat = "consumable", itemKey = imbue.key }
                    break
                end
            end
        end

        -- Weapon oil (if player doesn't have a class weapon imbue)
        if playerClass ~= "ROGUE" and playerClass ~= "PALADIN" and playerClass ~= "SHAMAN" then
            if co and co.enabled and co.enabled.weapon_enchant then
                local WEI = _G._EABR_WEAPON_ENCHANT_ITEMS or {}
                if #WEI > 0 then
                    icons[#icons+1] = { texture = WEI[1].icon or 134400, label = EllesmereUI.L("Weapon"), cat = "consumable", itemKey = "weapon_enchant" }
                end
            end
        end

        -- Flask
        if co and co.enabled and co.enabled.flask then
            icons[#icons+1] = { texture = 134830, label = EllesmereUI.L("Flask"), cat = "consumable", itemKey = "flask" }
        end

        -- Food
        if co and co.enabled and co.enabled.food then
            icons[#icons+1] = { texture = 134062, label = EllesmereUI.L("Food"), cat = "consumable", itemKey = "food" }
        end

        -- Augment Rune
        if co and co.enabled and co.enabled.augment_rune then
            icons[#icons+1] = { texture = C_Item.GetItemIconByID(259085) or 134400, label = EllesmereUI.L("Rune"), cat = "consumable", itemKey = "augment_rune" }
        end

        -- Healthstone (default-on: treat nil as enabled, matching the toggle)
        if co and co.enabled and co.enabled.healthstone ~= false then
            icons[#icons+1] = { texture = C_Item.GetItemIconByID(5512) or 134400, label = EllesmereUI.L("Stone"), cat = "consumable", itemKey = "healthstone" }
        end

        -- Inky Black Potion
        if co and co.enabled and co.enabled.inky_black then
            icons[#icons+1] = { texture = C_Item.GetItemIconByID(124640) or 136122, label = EllesmereUI.L("Inky"), cat = "consumable", itemKey = "inky_black" }
        end

        return icons
    end

    -- x of the first preview icon's center from the container's TOP, following the live grow
    -- direction: Grow Right pins the row's left end and Grow Left its right end to the page's
    -- content column (container edge + CONTENT_PAD); Grow Centered centers the row.
    local function PreviewStartX(d, count, sz, spacing, boxW)
        local growDir = d and d.growDirection
        local edgeX = boxW / 2 - EllesmereUI.CONTENT_PAD
        if growDir == "RIGHT" then return -edgeX + (sz / 2) end
        local totalW = (count * sz) + ((count - 1) * spacing)
        if growDir == "LEFT" then return edgeX - totalW + (sz / 2) end
        return -(totalW / 2) + (sz / 2)
    end

    local _eabrHeaderBaseH = 0

    local function UpdatePreviewHeader()
        if not _previewIcons or #_previewIcons == 0 then return end
        local d = DDB()
        if not d then return end
        local baseScale = d.scale or 1.0
        local ICON_SIZE = _G._EABR_ICON_SIZE or 40
        local sz = math.floor(ICON_SIZE * baseScale + 0.5)
        local iconH = sz
        if d.iconShape and d.iconShape ~= "none" then sz, iconH = ns.IconDimensions(sz, d) end
        local spacing = d.iconSpacing or 8
        -- The live renderer's own spec (nil = glow off), so the preview is the live look.
        local glowSpec = _G._EABR_GlowSpec and _G._EABR_GlowSpec(d, {})
        local showText = d.showText
        local tc = d.textColor or {r=1, g=1, b=1}
        local opacity = d.opacity or 1.0

        local startX = PreviewStartX(d, #_previewIcons, sz, spacing, _previewContainer:GetWidth())

        for i, pIcon in ipairs(_previewIcons) do
            local btn = pIcon.frame
            if not btn then break end
            btn:SetSize(sz, iconH)
            btn:SetAlpha(opacity)
            btn:ClearAllPoints()
            btn:SetPoint("TOP", btn:GetParent(), "TOP", startX + (i - 1) * (sz + spacing), 0)

            if _G._EABR_ApplyIconBorder then
                _G._EABR_ApplyIconBorder(btn, false)
            end

            -- Glow
            if not btn._glowWrapper then
                local w = CreateFrame("Frame", nil, btn)
                w:SetAllPoints(btn); w:SetFrameLevel(btn:GetFrameLevel() + 4)
                btn._glowWrapper = w
            end
            if glowSpec then
                EllesmereUI.Glows.StartSpecGlow(btn._glowWrapper, glowSpec, sz, iconH, "icon",
                    btn._eabrShape and ns.IconGlowExtra(btn, true) or EllesmereUI.Glows.PANEL_EXTRA)
                btn._glowWrapper:Show()
            else
                EllesmereUI.Glows.StopAllGlows(btn._glowWrapper)
                btn._glowWrapper:Hide()
            end

            -- Text
            if showText then
                local fontPath = GetNameFontPath()
                local textSize = d and d.textSize or 11
                local textXOff = d and d.textXOffset or 0
                local textYOff = d and d.textYOffset or -2
                EllesmereUI.ApplyModuleFont(btn._text, fontPath, textSize, "auraBuff")
                btn._text:ClearAllPoints()
                local tp, ip = GetPreviewTextAnchor(d)
                btn._text:SetPoint(tp, btn, ip, textXOff, textYOff)
                btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
                btn._text:Show()
            else
                btn._text:Hide()
            end

            btn:Show()
        end

        -- Recalculate total preview height: hardcoded 80px
        do
            local textYOff2 = d.textYOffset or -2
            local textSz2 = d.textSize or 11
            local textOverhang2 = showText and (math.abs(textYOff2) + textSz2) or 0
            local CONTAINER_H = iconH + textOverhang2
            if _previewContainer then
                _previewContainer:SetHeight(CONTAINER_H)
                _previewContainer:ClearAllPoints()
                _previewContainer:SetPoint("CENTER", _previewContainer:GetParent(), "CENTER", 0, 0)
            end
            local TOTAL_H = 80
            _eabrHeaderBaseH = TOTAL_H
            local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
            -- Use the silent variant so resizing the header never triggers
            -- scroll compensation (the height rarely changes here).
            EllesmereUI:SetContentHeaderHeightSilent(TOTAL_H + hintH)
        end
    end

    local function RefreshBorders()
        if _G._EABR_ApplyAllIconBorders then _G._EABR_ApplyAllIconBorders() end
        RefreshAll()
        UpdatePreviewHeader()
    end

    ---------------------------------------------------------------------------
    --  Preview click-to-scroll infrastructure
    ---------------------------------------------------------------------------

    --- Rebuild the preview header with scroll compensation.
    --- SetContentHeader tears down and rebuilds, which can cause scroll jumps.
    --- This wrapper saves the scroll position, rebuilds, then compensates.
    local function RebuildPreviewHeader()
        if FOREVER then return end  -- no preview header on WoW Forever
        EllesmereUI:SetContentHeader(_previewHeaderBuilder)
    end

    --- Lightweight relayout: reposition existing preview icons without
    --- tearing down and rebuilding the header (avoids scroll jumps).
    local function RelayoutPreviewIcons()
        if not _previewIcons or #_previewIcons == 0 then return end
        local d = DDB()
        local baseScale = d and d.scale or 1.0
        local ICON_SIZE = _G._EABR_ICON_SIZE or 40
        local sz = math.floor(ICON_SIZE * baseScale + 0.5)
        local spacing = d and d.iconSpacing or 8
        if d and d.iconShape and d.iconShape ~= "none" then sz = ns.IconDimensions(sz, d) end
        local startX = PreviewStartX(d, #_previewIcons, sz, spacing, _previewContainer:GetWidth())
        for i, pIcon in ipairs(_previewIcons) do
            local btn = pIcon.frame
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("TOP", btn:GetParent(), "TOP", startX + (i - 1) * (sz + spacing), 0)
            end
        end
    end

    local _eabrGlow   -- made on first click: Widgets helpers load with the panel
    local _eabrClickMappings = {}
    local _eabrHitOverlays = {}

    local function EABRPlaySettingGlow(targetFrame)
        _eabrGlow = _eabrGlow or EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })
        _eabrGlow(targetFrame)
    end

    local function EABRNavigateToSetting(key)
        local m = _eabrClickMappings[key]
        if not m or not m.section or not m.target then return end

        EllesmereUI.DismissPreviewHint(_previewHintFS, _eabrHeaderBaseH, 35, 5)

        local sf = EllesmereUI._scrollFrame
        if not sf then return end

        -- The glow plays a moment later: a target of the page pool that is
        -- dressed again for another row by then belongs to a newer build.
        local target = m.target
        local gen = Pool.Gen(target)
        local function PlayLater()
            if Pool.Gen(target) ~= gen or Pool.IsIdle(target) then return end
            EABRPlaySettingGlow(target)
        end

        local child = sf.GetScrollChild and sf:GetScrollChild()
        if child and target.GetTop and child.GetTop then
            local targetTop = target:GetTop()
            local childTop = child:GetTop()
            if targetTop and childTop then
                local scrollPos = math.max(0, childTop - targetTop - 40)
                EllesmereUI.SmoothScrollTo(scrollPos)
                C_Timer.After(0.15, PlayLater)
                return
            end
        end

        -- Fallback for layouts where the scroll child isn't ready yet.
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if headerY then
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            EllesmereUI.SmoothScrollTo(scrollPos)
        end
        C_Timer.After(0.15, PlayLater)
    end

    local function EABRCreateHitOverlay(element, mappingKey, frameLevelOverride)
        local btn = EllesmereUI.CreatePreviewHitOverlay(element, EABRNavigateToSetting, mappingKey, false, frameLevelOverride)
        _eabrHitOverlays[#_eabrHitOverlays + 1] = btn
        return btn
    end

    _previewHeaderBuilder = function(hdr, hdrW)
        local icons = CollectPreviewIcons()
        local d = DDB()
        local baseScale = d and d.scale or 1.0
        local ICON_SIZE = _G._EABR_ICON_SIZE or 40
        local sz = math.floor(ICON_SIZE * baseScale + 0.5)
        local iconH = sz
        if d and d.iconShape and d.iconShape ~= "none" then sz, iconH = ns.IconDimensions(sz, d) end
        local spacing = d and d.iconSpacing or 8
        local showText = d and d.showText
        local tc = d and d.textColor or {r=1, g=1, b=1}
        local opacity = d and d.opacity or 1.0

        -- Reuse existing container + icons if count matches (avoids
        -- full frame teardown/rebuild on tab switch which causes FPS dip)
        if _previewContainer and #_previewIcons == #icons then
            -- Re-parent and re-show (may have been orphaned by ClearContentHeader)
            _previewContainer:SetParent(hdr)
            -- The levels the first build gave the container and its icons (a
            -- kept header root's own dress can raise what it holds)
            _previewContainer:SetFrameLevel(hdr:GetFrameLevel() + 1)
            _previewContainer:ClearAllPoints()
            _previewContainer:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            _previewContainer:SetSize(hdrW, _previewContainer:GetHeight())
            _previewContainer:Show()
            -- Update textures/labels in case the icon set changed content
            for i, pIcon in ipairs(_previewIcons) do
                if pIcon.frame then pIcon.frame:SetFrameLevel(_previewContainer:GetFrameLevel() + 1) end
                if pIcon.frame and icons[i] then
                    if pIcon.frame._icon then pIcon.frame._icon:SetTexture(icons[i].texture or 134400) end
                    if pIcon.frame._text then pIcon.frame._text:SetText(icons[i].label or "") end
                    pIcon.data = icons[i]
                end
            end
            UpdatePreviewHeader()
            -- Must return the header height. A bare `return` (nil) made
            -- SetContentHeader collapse the content header to 0px, so the whole
            -- preview vanished whenever a toggle left the icon count unchanged
            -- (inky/healthstone, augment rune, pet, or a raid buff/aura not for
            -- this class). Match the full-build height (base 80 + hint row).
            return 80 + ((not IsPreviewHintDismissed()) and 35 or 0)
        end

        -- Container for icons (centered within hardcoded 80px header)
        local textYOff = d and d.textYOffset or -2
        local textSz = d and d.textSize or 11
        local textOverhang = showText and (math.abs(textYOff) + textSz) or 0

        -- Recycle or create container (kept across header builds: Pool.Keep
        -- takes it out of its host's pool, so a later build never hands it out
        -- as another frame)
        if _previewContainer then
            _previewContainer:SetParent(hdr)
            _previewContainer:ClearAllPoints()
        else
            _previewContainer = Pool.Keep(CreateFrame("Frame", nil, hdr))
        end
        -- (the level a new container gets: see the reuse branch above)
        _previewContainer:SetFrameLevel(hdr:GetFrameLevel() + 1)
        _previewContainer:SetSize(hdrW, iconH + textOverhang)
        _previewContainer:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        _previewContainer:Show()
        local container = _previewContainer

        -- The previous icon set goes before the new one is made: on a pool host
        -- the icons below are handed back in order and dressed again.
        Pool.Begin(container)

        -- Hide old icon frames before rebuilding
        for _, pIcon in ipairs(_previewIcons) do
            if pIcon.frame then pIcon.frame:Hide() end
        end
        wipe(_previewIcons)
        local startX = PreviewStartX(d, #icons, sz, spacing, hdrW)

        for i, iconData in ipairs(icons) do
            local btn = CreateFrame("Button", nil, container)
            btn:SetSize(sz, iconH)
            btn:EnableMouse(true)
            btn:SetPoint("TOP", container, "TOP", startX + (i - 1) * (sz + spacing), 0)
            btn:SetAlpha(opacity)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(iconData.texture or 134400)
            if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end
            btn._icon = icon

            -- The live border helper owns the preview border too, keeping the
            -- header byte-for-byte aligned with reminder icons.
            if _G._EABR_ApplyIconBorder then
                _G._EABR_ApplyIconBorder(btn, false)
            else
                local border = CreateFrame("Frame", nil, btn)
                border:SetAllPoints(); border:EnableMouse(false)
                btn._eabrBorderFrame = border
                local pd = DDB()
                local borderSize = (pd and pd.borderSize) or 1
                local borderTex = (pd and pd.borderTexture) or "solid"
                EllesmereUI.ApplyBorderStyle(border, borderSize,
                    (pd and pd.borderR) or 0, (pd and pd.borderG) or 0,
                    (pd and pd.borderB) or 0, (pd and pd.borderA) or 1,
                    borderTex,
                    pd and pd.borderTextureOffset, pd and pd.borderTextureOffsetY,
                    pd and pd.borderTextureShiftX, pd and pd.borderTextureShiftY,
                    "aurabuffreminders", borderSize, nil,
                    EllesmereUI.BorderPx(pd and pd.borderSizePx, borderSize, borderTex))
            end

            -- Text label below icon
            local fontPath = GetNameFontPath()
            local textSize = d and d.textSize or 11
            local textXOff = d and d.textXOffset or 0
            local textYOff = d and d.textYOffset or -2
            local textOverlay = CreateFrame("Frame", nil, btn)
            textOverlay:SetAllPoints()
            textOverlay:SetFrameLevel(btn:GetFrameLevel() + 5)
            local text = textOverlay:CreateFontString(nil, "OVERLAY")
            do
                local tp, ip = GetPreviewTextAnchor(d)
                text:SetPoint(tp, btn, ip, textXOff, textYOff)
            end
            EllesmereUI.ApplyModuleFont(text, fontPath, textSize, "auraBuff")
            text:SetTextColor(tc.r, tc.g, tc.b, 1)
            text:SetText(iconData.label or "")
            if not showText then text:Hide() end
            btn._text = text

            _previewIcons[i] = { frame = btn, data = iconData }
        end

        -- Apply glows
        UpdatePreviewHeader()

        -- Create hit overlays on each preview icon
        wipe(_eabrHitOverlays)
        local overlayLevel = container:GetFrameLevel() + 20
        for i, pIcon in ipairs(_previewIcons) do
            if pIcon.frame and pIcon.data then
                -- Use per-item key if available, fall back to category
                local mappingKey = pIcon.data.itemKey and ("item:" .. pIcon.data.itemKey) or (pIcon.data.cat or "display")
                EABRCreateHitOverlay(pIcon.frame, mappingKey, overlayLevel)
                -- Hit overlay on text label scrolls to the Show Name setting
                if pIcon.frame._text and showText then
                    EABRCreateHitOverlay(pIcon.frame._text, "showText", overlayLevel)
                end
            end
        end

        -- Hint text
        if _previewHintFS and not _previewHintFS:GetParent() then
            _previewHintFS = nil
        end
        local hintShown = not IsPreviewHintDismissed()
        local TOTAL_H = 80
        _eabrHeaderBaseH = TOTAL_H

        if hintShown then
            if not _previewHintFS then
                -- Kept across builds too (out of the container's pool).
                _previewHintFS = Pool.Keep(EllesmereUI.MakeFont(container, 11, nil, 1, 1, 1))
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
            end
            _previewHintFS:SetParent(container)
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 15)
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        return TOTAL_H
    end

    ---------------------------------------------------------------------------
    --  Per-section "Where to Show" + "Show When" multi-selects. The stored
    --  table keeps only unchecked buckets (value false); an absent bucket =
    --  shown. Buckets mirror EABR.CurrentWhereBucket in the core file.
    ---------------------------------------------------------------------------
    local WHERE_ITEMS = {
        { key="open_world",        label="Open World" },
        { key="raid_mythic",       label="Mythic Raid" },
        { key="raid_heroic",       label="Heroic Raid" },
        { key="raid_normal_lfr",   label="Normal/LFR Raid" },
        { key="dungeon_mythic",    label="Mythic Dungeons" },
        { key="dungeon_nonmythic", label="Non-Mythic Dungeons" },
        { key="timewalking",       label="Timewalking" },
        { key="delve",             label="Delve" },
        { key="lair",              label="Lair" },
        { key="scenario",          label="Scenario" },
        -- Orthogonal state gate (not a location): unchecking hides this
        -- section while in combat.
        { key="in_combat",         label="In Combat" },
    }
    -- WoW Forever buckets: vanilla dungeons report Normal difficulty and its
    -- raids the legacy 40/20-player ids (mapped in the core file), so Raid
    -- Buffs there offers three locations plus the combat gate.
    local FOREVER_WHERE_ITEMS = {
        { key="open_world",        label="Open World" },
        { key="dungeon_nonmythic", label="Dungeons" },
        { key="raid_normal_lfr",   label="Raids" },
        { key="in_combat",         label="In Combat" },
    }
    -- The WoW Forever section never shows in combat: no combat gate to offer
    local FOREVER_SECTION_WHERE_ITEMS = {
        { key="open_world",        label="Open World" },
        { key="dungeon_nonmythic", label="Dungeons" },
        { key="raid_normal_lfr",   label="Raids" },
    }
    local SHOWWHEN_ITEMS = {
        { key="othersMissing", label="Others are missing my buff" },
        { key="iAmMissing",    label="I am missing others' buffs" },
    }
    local GROW_DIR_VALUES = { CENTER = "Grow Centered", LEFT = "Grow Left", RIGHT = "Grow Right" }
    local GROW_DIR_ORDER  = { "CENTER", "LEFT", "RIGHT" }

    -- Values are stored explicitly (true/false) rather than nil-for-on: the
    -- SavedVariables layer re-merges default keys on load, so an absent
    -- bucket whose default is false would silently flip back off across a
    -- logout.
    local function WhereGet(store) return function(k) local t = store(); return not (t and t[k] == false) end end
    local function WhereSet(store, onChange)
        return function(k, v)
            local t = store(true); if not t then return end
            t[k] = v and true or false
            if onChange then onChange() end
        end
    end
    local function WhenGet(store) return function(k) local t = store(); return t and t[k] == true end end
    local function WhenSet(store, onChange)
        return function(k, v)
            local t = store(); if not t then return end
            t[k] = v and true or false
            if onChange then onChange() end
        end
    end

    -- Per-section "Where to Show" accessors (created on demand).
    local function RWhere() local r = RDB(); if not r then return nil end; r.whereToShow = r.whereToShow or {}; return r.whereToShow end
    local function AWhere() local a = ADB(); if not a then return nil end; a.whereToShow = a.whereToShow or {}; return a.whereToShow end
    local function CWhere() local c = CDB(); if not c then return nil end; c.whereToShow = c.whereToShow or {}; return c.whereToShow end
    -- Per-section sets, see EABR.SPECIALS. The first write stores a copy of
    -- the old shared specials set.
    local function CSpecialWhere(cls)
        return function(forWrite)
            local c, S = CDB(), _G._EABR_SPECIALS
            if not (c and S) then return nil end
            local field = S[cls].where
            if forWrite and type(c[field]) ~= "table" then
                local src = c.specialsWhereToShow
                c[field] = type(src) == "table" and CopyTable(src) or {}
            end
            return _G._EABR_SpecialsWhere(c, field)
        end
    end
    local function CWarlockWhere() local c = CDB(); if not c then return nil end; c.warlockWhereToShow = c.warlockWhereToShow or {}; return c.warlockWhereToShow end
    local function FWhere() local f = FDB(); if not f then return nil end; f.whereToShow = f.whereToShow or {}; return f.whereToShow end
    local function FSelfWhere() local f = FDB(); if not f then return nil end; f.selfWhereToShow = f.selfWhereToShow or {}; return f.selfWhereToShow end
    local function RShowWhen() local r = RDB(); if not r then return nil end; r.showWhen = r.showWhen or {}; return r.showWhen end

    -- Shared reminder-sound catalogue (built + LSM-populated by the QoL
    -- module and exposed on EllesmereUI). Falls back to just "None".
    local function SoundNamesOrder()
        local names = EllesmereUI._groupDeathSoundNames or { none = "None" }
        local order = EllesmereUI._groupDeathSoundOrder or { "none" }
        return names, order
    end

    -- Inline cog holding a single "Sound" dropdown bound to getSec()[field]
    -- ("none"/nil = silent). One reminder sound applies to the whole
    -- section; selecting a sound previews it once.
    local function AddSectionSoundCog(rgn, getSec, field, extraRows, title)
        local names, order = SoundNamesOrder()
        local rows = { {
            type="dropdown", label="Sound",
            tooltip="Play a sound once when a reminder in this section newly appears.",
            values=names, order=order,
            get=function() local t = getSec(); return (t and t[field]) or "none" end,
            set=function(v)
                local t = getSec(); if not t then return end
                if v == "none" then t[field] = nil else t[field] = v end
                local paths = EllesmereUI._groupDeathSoundPaths
                local p = paths and paths[v]
                if p then PlaySoundFile(p, "Master") end
            end,
        } }
        if extraRows then
            for i = 1, #extraRows do rows[#rows + 1] = extraRows[i] end
        end
        return EllesmereUI.BuildInlineCog(rgn, { title=title or "Reminder Sound", rows=rows, minWidth=extraRows and 320 or 220 })
    end

    -- Per-section control dual-row: a "Where to Show" checkbox dropdown on
    -- the left. Right slot: for raid buffs the "Show When" checkbox
    -- dropdown (+ reminder-sound cog beside it); for a section with a sound
    -- a full "Reminder Sound" dropdown fills the slot instead of a cog; else
    -- the section's own cfg.rightCfg (the caller dresses row._rightRegion).
    local function SectionControlRow(parent, y, cfg)
        local W = EllesmereUI.Widgets
        local rightCfg = cfg.rightCfg
        if cfg.showWhenStore then
            rightCfg = { type="dropdown", text="Show When", tooltip=cfg.showWhenTooltip,
                values={ _placeholder="..." }, order={ "_placeholder" },
                getValue=function() return "_placeholder" end, setValue=function() end }
        elseif cfg.soundSec then
            local names, order = SoundNamesOrder()
            local sec, field = cfg.soundSec, cfg.soundField or "sectionSound"
            -- Class-special sections look their field up per call (the map is
            -- exported in ABR's OnEnable), see EABR.SPECIALS.
            local special = cfg.specialClass
            local function Field()
                if not special then return field end
                local S = _G._EABR_SPECIALS
                return S and S[special].sound
            end
            rightCfg = { type="dropdown", text="Reminder Sound", dropdownWidth=220,
                tooltip="Play a sound once when a reminder in this section newly appears.",
                values=names, order=order,
                getValue=function()
                    local t = sec(); if not t then return "none" end
                    local f, read = Field(), special and _G._EABR_SpecialsSound
                    if not f then return "none" end
                    if read then return read(t, f) or "none" end
                    return t[f] or "none"
                end,
                setValue=function(v)
                    local t = sec(); if not t then return end
                    -- A special section stores "none" (see EABR.SpecialsSound).
                    local f = Field(); if not f then return end
                    if v == "none" and not special then t[f] = nil else t[f] = v end
                    local paths = EllesmereUI._groupDeathSoundPaths
                    local sp = paths and paths[v]
                    if sp then PlaySoundFile(sp, "Master") end
                end }
        end
        local row, h = W:DualRow(parent, y,
            { type="dropdown", text="Where to Show", tooltip=cfg.whereTooltip,
              values={ _placeholder="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end, setValue=function() end },
            rightCfg or { type="label", text="" })
        -- The dropdowns make frames; the sound cog stays outside so the index pass reads its rows.
        if not EllesmereUI._prebuilding then
            local lrgn = row._leftRegion
            if lrgn._control then lrgn._control:Hide() end
            local whereDD, whereRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                lrgn, 220, lrgn:GetFrameLevel() + 2, cfg.whereItems or WHERE_ITEMS,
                WhereGet(cfg.whereStore), WhereSet(cfg.whereStore, cfg.onChange))
            PP.Point(whereDD, "RIGHT", lrgn, "RIGHT", -20, 0)
            lrgn._control = whereDD
            lrgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(whereRefresh)

            if cfg.showWhenStore then
                local rrgn = row._rightRegion
                if rrgn._control then rrgn._control:Hide() end
                local whenDD, whenRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rrgn, 220, rrgn:GetFrameLevel() + 2, SHOWWHEN_ITEMS,
                    WhenGet(cfg.showWhenStore),
                    WhenSet(cfg.showWhenStore, function()
                        if cfg.onShowWhenChange then cfg.onShowWhenChange() end
                        if cfg.onChange then cfg.onChange() end
                    end))
                PP.Point(whenDD, "RIGHT", rrgn, "RIGHT", -20, 0)
                rrgn._control = whenDD
                rrgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(whenRefresh)
            end
        end
        if cfg.showWhenStore and cfg.soundSec then AddSectionSoundCog(row._rightRegion, cfg.soundSec, cfg.soundField or "sectionSound", cfg.cogRows, cfg.cogTitle) end
        return row, h
    end

    -- "(min)" suffix in smaller, dimmer text after a slider's label.
    local function AddMinSuffix(threshRow, leftLabel, rightLabel)
        if EllesmereUI._prebuilding then return end
        for _, rgn in ipairs({threshRow._leftRegion, threshRow._rightRegion}) do
            local labelText = rgn == threshRow._leftRegion and leftLabel or rightLabel
            local suffix = rgn:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local found
            local regions = { rgn:GetRegions() }
            for i = 1, #regions do
                local reg = regions[i]
                -- (an idle pooled region still holds the text of an earlier dress)
                if reg and reg.GetText and not Pool.IsIdle(reg) and EllesmereUI.EnKey(reg:GetText()) == labelText then
                    found = reg; break
                end
            end
            if found then
                suffix:SetPoint("LEFT", found, "RIGHT", 5, -1)
            end
            suffix:SetText(EllesmereUI.L("(min)"))
        end
    end

    ---------------------------------------------------------------------------
    --  4-column checkbox grid (DualRow-style rows with RowBg + dividers)
    --  items = { { label, classToken, getVal, setVal, tooltip? }, ... }
    ---------------------------------------------------------------------------
    local GRID_COLS     = 4
    local GRID_ROW_H    = 50
    local GRID_BOX_SZ   = 18
    local GRID_PAD      = EllesmereUI.CONTENT_PAD or 16
    local GRID_SIDE_PAD = 20

    local function BuildCheckboxGrid(parent, y, items, refreshFn, cellRefTable)
        local totalRows = math.ceil(#items / GRID_COLS)
        local totalW = parent:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)
        local eg = EllesmereUI.ELLESMERE_GREEN or {r=0, g=0.82, b=0.62}

        for row = 0, totalRows - 1 do
            -- Create one full-width row frame per grid row (like DualRow)
            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, GRID_ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", GRID_PAD, y - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            EllesmereUI.RowBg(rowFrame, parent)

            -- 1px dividers at column boundaries (full height, matching _showRowDivider style)
            for d = 1, GRID_COLS - 1 do
                local div = rowFrame:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
                div:SetWidth(1)
                local xPos = d * colW
                PP.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
            end

            -- Build each cell in this row
            for col = 0, GRID_COLS - 1 do
                local idx = row * GRID_COLS + col + 1
                local item = items[idx]
                if not item then break end

                local cell = CreateFrame("Frame", nil, rowFrame)
                cell:SetSize(colW, GRID_ROW_H)
                cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                -- Class color for label
                local cr, cg, cb = 1, 1, 1
                if item.classToken then
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classToken]
                    if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                end

                -- Label (left)
                local label = EllesmereUI.MakeFont(cell, 13, nil, cr, cg, cb)
                label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                label:SetText(item.label)

                -- Checkbox box (right)
                local box = CreateFrame("Frame", nil, cell)
                box:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
                box:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)

                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                if boxBg.SetSnapToPixelGrid then boxBg:SetSnapToPixelGrid(false); boxBg:SetTexelSnappingBias(0) end

                local boxBrd = EllesmereUI.MakeRoundedBorder(box, 0.224, 0.215, 0.207, 0.6, boxBg)

                local check = box:CreateTexture(nil, "ARTWORK")
                check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                check:SetColorTexture(eg.r, eg.g, eg.b, 1)
                EllesmereUI.RoundBody(box, check, 1)
                if check.SetSnapToPixelGrid then check:SetSnapToPixelGrid(false); check:SetTexelSnappingBias(0) end

                -- Click area covers the whole cell
                local btn = CreateFrame("Button", nil, cell)
                btn:SetAllPoints(cell)
                btn:SetFrameLevel(cell:GetFrameLevel() + 2)

                local function ApplyVisual()
                    local on = item.getVal()
                    if on then
                        check:Show()
                        label:SetAlpha(1)
                        boxBrd:SetColor(eg.r, eg.g, eg.b, 0.15)
                    else
                        check:Hide()
                        label:SetAlpha(0.5)
                        boxBrd:SetColor(0.224, 0.215, 0.207, 0.6)
                    end
                end
                ApplyVisual()

                btn:SetScript("OnClick", function()
                    item.setVal(not item.getVal())
                    ApplyVisual()
                    if refreshFn then refreshFn() end
                end)
                btn:SetScript("OnEnter", function()
                    if not item.getVal() then label:SetAlpha(0.8) end
                    if item.tooltip then EllesmereUI.ShowWidgetTooltip(cell, item.tooltip) end
                end)
                btn:SetScript("OnLeave", function()
                    if not item.getVal() then label:SetAlpha(0.5) end
                    if item.tooltip then EllesmereUI.HideWidgetTooltip() end
                end)

                -- Optional per-item cog (e.g. per-item conditions) just left
                -- of the checkbox, floating above the cell click area. No
                -- current item populates cogRows; the hook exists for
                -- per-item condition sets.
                if item.cogRows then
                    EllesmereUI.BuildInlineCog(cell, {
                        title = item.cogTitle or "Reminder Conditions",
                        rows = item.cogRows,
                        minWidth = 220,
                        anchorTo = box, chain = false, size = 16, gap = 10,
                    })
                end

                EllesmereUI.RegisterWidgetRefresh(ApplyVisual)

                -- Store cell reference for preview click navigation
                if cellRefTable and item.key then
                    cellRefTable[item.key] = cell
                end
            end
        end

        return totalRows * GRID_ROW_H
    end

    ---------------------------------------------------------------------------
    --  Auras, Buffs & Consumables page
    ---------------------------------------------------------------------------
    -- Adds the spell ID typed into an Add ... Spell input to list: digits only,
    -- a spell the client knows, no duplicates.
    local function AddSpellIDToList(list, text)
        local spellID = tonumber((text or ""):match("^%s*(%d+)%s*$"))
        if not (spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)) then return end
        for _, existingSpellID in ipairs(list) do
            if existingSpellID == spellID then return end
        end
        list[#list + 1] = spellID
        RefreshAll()
        -- Rebuilds the page once the edit box has finished its commit.
        C_Timer.After(0, function() EllesmereUI:RefreshPage(true) end)
    end

    -- Names a new spell group (group nil) or renames group.
    local function PromptSpellGroupName(group)
        EllesmereUI:ShowInputPopup({
            title = group and "Rename Spell Group" or "New Spell Group",
            message = "Enter a name for the group:",
            placeholder = "Group name",
            initialText = group and group.name or "",
            confirmText = group and "Rename" or "Create",
            onConfirm = function(text)
                local name = strtrim(text or "")
                local f = FDB()
                if name == "" or not f then return end
                if group then
                    group.name = name
                else
                    f.customGroups[#f.customGroups + 1] = { name = name, ids = {} }
                end
                RefreshAll()
                C_Timer.After(0, function() EllesmereUI:RefreshPage(true) end)
            end,
        })
    end

    ---------------------------------------------------------------------------
    --  WoW Forever spell groups: one section per group. Slots, left to right:
    --  Add Spell ID, Rename, one per spell, Remove Group last.
    ---------------------------------------------------------------------------
    local function BuildForeverGroupSections(parent, y)
        local f = FDB()
        local W = EllesmereUI.Widgets
        for groupIndex, group in ipairs(f.customGroups) do
            local slots = {
                { type="input", text="Add Spell ID", inputStyle="popup", placeholder="Spell ID", inputWidth=110,
                  tooltip="Type a spell ID and press Enter to add it to this group. Unknown IDs are ignored.\nThe reminder shows the icon of the first spell in the list that you know, or of the spell you picked with the Action Picker.",
                  getValue=function() return "" end,
                  setValue=function(text) AddSpellIDToList(group.ids, text) end },
                { type="labeledButton", text="Rename Group", buttonText="Rename", width=90,
                  tooltip="Change this group's name.",
                  onClick=function() PromptSpellGroupName(group) end },
            }
            for spellIndex, spellID in ipairs(group.ids) do
                slots[#slots + 1] = { type="labeledButton", buttonText="Remove", width=90,
                    text=_G._EABR_SpellName(spellID, tostring(spellID)) .. " " .. EllesmereUI.COLOR_CODES.DIM .. spellID .. "|r",
                    tooltip="Remove this spell from the group.",
                    onClick=function()
                        table.remove(group.ids, spellIndex)
                        if group.castSpellID == spellID then group.castSpellID = nil end
                        if group.castRanks then
                            group.castRanks[spellID] = nil
                            if not next(group.castRanks) then group.castRanks = nil end
                        end
                        RefreshAll()
                        EllesmereUI:RefreshPage(true)
                    end }
            end
            slots[#slots + 1] = { type="labeledButton", text="Remove Group", buttonText="Remove", width=90,
                tooltip="Deletes this group and its spells.",
                onClick=function()
                    table.remove(f.customGroups, groupIndex)
                    RefreshAll()
                    EllesmereUI:RefreshPage(true)
                end }
            local _, headerHeight = W:SectionHeader(parent, EllesmereUI.Lf("SPELL GROUP: %1$s", group.name), y)
            y = y - headerHeight
            for slotIndex = 1, #slots, 2 do
                local _, rowHeight = W:DualRow(parent, y, slots[slotIndex],
                    slots[slotIndex + 1] or EllesmereUI.BlankRowCfg())
                y = y - rowHeight
            end
        end
        return y
    end

    ---------------------------------------------------------------------------
    --  WoW Forever consumables: two per-class dropdowns with independent reminder settings.
    ---------------------------------------------------------------------------
    local SCROLL_STAT_KEYS = { "intellect", "strength", "agility", "stamina", "spirit", "protection" }
    local ELIXIR_STAT_KEYS = { "spellPower", "manaRegen", "healthRegen", "healingDone", "attackPower" }
    local function StatTicked(f, class, key, locks)
        if locks and locks[key] and locks[key]() then return false end
        local picks = f[key .. "ConsumableByClass"]
        return picks and picks[class] == true or false
    end
    local function AttachStatDropdown(rgn, class, slotCfg, items, locks)
        local profile = FDB()
        local dd, refresh = EllesmereUI.BuildVisOptsCBDropdown(rgn, 170, rgn:GetFrameLevel() + 2, items,
            function(key)
                local f = FDB()
                return f and class and StatTicked(f, class, key, locks) or false
            end,
            function(key, v)
                local f = FDB()
                if not (f and f == profile and class) then return end
                if locks and locks[key] and locks[key]() then return end
                local field = key .. "ConsumableByClass"
                local picks = f[field]
                if v then
                    if not picks then picks = {}; f[field] = picks end
                    picks[class] = true
                elseif picks then
                    picks[class] = nil
                end
                local cog = rgn._euiCog
                if cog then cog._euiCogState() end
                RefreshAll()
            end, nil, nil, nil, nil, nil, { dimLocked = true })
        EllesmereUI.PanelPP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
        dd._ttText = slotCfg.tooltip
        rgn._control = dd
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(refresh)
        return dd, refresh
    end
    local function BuildStatReminderCog(rgn, class, title, keys, prefix, locks)
        EllesmereUI.BuildInlineCog(rgn, {
            title = title,
            disabled = function()
                local f = FDB(); if not (f and class) then return true end
                for _, key in ipairs(keys) do
                    if StatTicked(f, class, key, locks) then return false end
                end
                return true
            end,
            disabledTooltip = title,
            minWidth = 320,
            rows = {
                { type="toggle", label=EllesmereUI.L("Separate Reminders"),
                  tooltip=EllesmereUI.L("Show a separate icon for each selected stat with an eligible scroll or elixir."),
                  get=function() local f = FDB(); return f and f[prefix .. "SeparateReminders"] == true end,
                  set=function(v) local f = FDB(); if f then f[prefix .. "SeparateReminders"] = v == true; RefreshAll() end end },
                { type="toggle", label=EllesmereUI.L("Show Stronger Buffs"),
                  tooltip=EllesmereUI.L("Suggest a usable scroll or elixir from your bags if it gives more of the stat than your current buff."),
                  get=function() local f = FDB(); return f and f[prefix .. "ShowUpgrades"] == true end,
                  set=function(v) local f = FDB(); if f then f[prefix .. "ShowUpgrades"] = v == true; RefreshAll() end end },
                { type="dropdown", label="Rank to Use", ddWidth=200,
                  values={ high = "Highest Owned", low = "Lowest Owned" }, order={ "high", "low" },
                  tooltip=EllesmereUI.L("Choose the highest or lowest eligible item for each stat. An eligible Action Picker choice takes priority."),
                  get=function() local f = FDB(); return f and f[prefix .. "LowRank"] and "low" or "high" end,
                  set=function(v) local f = FDB(); if f then f[prefix .. "LowRank"] = v == "low"; RefreshAll() end end },
                { type="slider", label="Show Below (Minutes)", min=0, max=10, step=1,
                  tooltip=EllesmereUI.L("Show a countdown before a tracked scroll or elixir buff expires. 0 = show only after it expires."),
                  get=function() local f = FDB(); return f and f[prefix .. "ShowBelow"] or 0 end,
                  set=function(v) local f = FDB(); if f then f[prefix .. "ShowBelow"] = v; RefreshAll() end end },
            },
        })
    end
    local function ElixirsSlot()
        return { type="label", text=EllesmereUI.L("Elixirs"),
            tooltip=EllesmereUI.L("Reminds you when a selected elixir buff is missing and an eligible elixir is in your bags. Click the icon to use it.\nOne reminder by default. The cog can show one per stat.\nWith Action Picker on, right-click to choose another item.") }
    end
    local function DressElixirsSlot(rgn, class, slotCfg)
        if not EllesmereUI._prebuilding then
            AttachStatDropdown(rgn, class, slotCfg, {
                { key = "spellPower", label = EllesmereUI.L("Spell Power"), tooltip = EllesmereUI.L("Arcane Elixirs") },
                { key = "manaRegen", label = EllesmereUI.L("Mana Regen"),
                  tooltip = EllesmereUI.L("Mageblood Elixirs") .. "\n" .. EllesmereUI.L("Elixir of Wicked Regeneration")
                      .. "\n\n" .. EllesmereUI.L("Mageblood Elixirs do not stack with Elixir of Wicked Regeneration.") },
                { key = "healthRegen", label = EllesmereUI.L("Health Regen"),
                  tooltip = EllesmereUI.L("Troll's Blood Elixirs") .. "\n" .. EllesmereUI.L("Elixir of Wicked Regeneration")
                      .. "\n\n" .. EllesmereUI.L("Health Regen from Troll's Blood and Elixir of Wicked Regeneration does not stack.") },
                { key = "healingDone", label = EllesmereUI.L("Healing Done"), tooltip = EllesmereUI.L("Cleric's Elixirs") },
                { key = "attackPower", label = EllesmereUI.L("Attack Power"),
                  tooltip = EllesmereUI.L("Distilled Firewater") .. "\n" .. EllesmereUI.L("Winterfall Firewater")
                      .. "\n\n" .. EllesmereUI.L("Can stack with Blessing of Might and Battle Shout.") },
            })
        end
        BuildStatReminderCog(rgn, class, slotCfg.text, ELIXIR_STAT_KEYS, "elixirConsumable")
    end
    local function ScrollsSlot()
        return { type="label", text=EllesmereUI.L("Scrolls and Elixirs"),
            tooltip=EllesmereUI.L("Reminds you when a ticked stat has no scroll or elixir buff while one is in your bags. Click the icon to use it.\nOne reminder by default; the cog can show one per stat.\nWith Action Picker on, right-click to choose another item.") }
    end
    local function DressScrollsSlot(rgn, class, slotCfg)
        local function IntellectLocked() return ns.FvStatConsumableLocked("ai", class) end
        local function StaminaLocked() return ns.FvStatConsumableLocked("fort", class) end
        local function SpiritLocked() return ns.FvStatConsumableLocked("spirit", class) end
        local locks = { intellect = IntellectLocked, stamina = StaminaLocked, spirit = SpiritLocked }
        if not EllesmereUI._prebuilding then
            local items = {
                { key = "intellect", label = EllesmereUI.L("Intellect"),
                  lockedFn = IntellectLocked,
                  lockedTooltip = EllesmereUI.L("Disabled because you already know Arcane Intellect."),
                  tooltip = EllesmereUI.L("Scrolls of Intellect I-IV") .. "\n" .. EllesmereUI.L("Intellect Elixirs") .. "\n\n"
                      .. EllesmereUI.L("Does not stack with Arcane Intellect, Arcane Brilliance and Incense Candle.") },
                { key = "strength", label = EllesmereUI.L("Strength"),
                  tooltip = EllesmereUI.L("Scrolls of Strength I-IV") .. "\n" .. EllesmereUI.L("Strength Elixirs") .. "\n\n"
                      .. EllesmereUI.L("Can stack with Sharpening Wheel and Strength of Earth Totem.") },
                { key = "agility", label = EllesmereUI.L("Agility"),
                  tooltip = EllesmereUI.L("Scrolls of Agility I-IV") .. "\n" .. EllesmereUI.L("Agility Elixirs") .. "\n\n"
                      .. EllesmereUI.L("Can stack with Grace of Air Totem.") },
                { key = "stamina", label = EllesmereUI.L("Stamina"),
                  lockedFn = StaminaLocked,
                  lockedTooltip = EllesmereUI.L("Disabled because you already know Power Word: Fortitude."),
                  tooltip = EllesmereUI.L("Scrolls of Stamina I-IV") .. "\n" .. EllesmereUI.L("Elixirs of Fortitude") .. "\n\n"
                      .. EllesmereUI.L("Stamina scrolls do not stack with Power Word: Fortitude, Prayer of Fortitude and First Aid Kit.\nElixirs of Fortitude stack with any Stamina buff.") },
                { key = "spirit", label = EllesmereUI.L("Spirit"),
                  lockedFn = SpiritLocked,
                  lockedTooltip = EllesmereUI.L("Disabled because you already know Divine Spirit."),
                  tooltip = EllesmereUI.L("Scrolls of Spirit I-IV") .. "\n" .. EllesmereUI.L("Spirit Elixirs") .. "\n\n"
                      .. EllesmereUI.L("Does not stack with Divine Spirit and Prayer of Spirit.") },
                { key = "protection", label = EllesmereUI.L("Protection"),
                  tooltip = EllesmereUI.L("Scrolls of Protection I-IV") .. "\n" .. EllesmereUI.L("Armor Elixirs") .. "\n\n"
                      .. EllesmereUI.L("Can stack with Devotion Aura.") },
            }
            for _, item in ipairs(items) do
                if item.lockedTooltip then
                    item.lockedTooltip = item.lockedTooltip .. "\n\n" .. item.tooltip
                end
            end
            local dd, refresh = AttachStatDropdown(rgn, class, slotCfg, items, locks)
            ns.RefreshStatConsumableOptions = function()
                if dd:IsVisible() then refresh() end
            end
        end
        BuildStatReminderCog(rgn, class, slotCfg.text, SCROLL_STAT_KEYS, "statConsumable", locks)
    end

    ---------------------------------------------------------------------------
    --  WoW Forever custom spells: the lead slot (the Add Custom Spell entry),
    --  the New Spell Group slot, then one slot per tracked spell (its icon,
    --  name and ID, and a checkbox dropdown of the classes it reminds, each
    --  ticked until unticked, forever.customClasses[id][CLASS] = false, with
    --  Remove at its top), filled left to right, a blank label in an odd last
    --  slot. The page rebuilds on add and remove, so the slots never need
    --  in-place updates.
    ---------------------------------------------------------------------------
    local function BuildForeverCustomRows(parent, y, lead)
        local f = FDB()
        local ids = f and f.customIDs
        local newGroupSlot = { type="labeledButton", text="New Spell Group", buttonText="Create", width=90,
            tooltip="Creates a group of spells. A reminder shows if none of the auras from the group are active.",
            onClick=function() PromptSpellGroupName() end }
        local n = 2 + (ids and #ids or 0)
        local W = EllesmereUI.Widgets
        local PPx = EllesmereUI.PanelPP
        local function Slot(id)
            return { type="label",
                text=_G._EABR_SpellName(id, tostring(id)) .. " " .. EllesmereUI.COLOR_CODES.DIM .. id .. "|r",
                tooltip="Reminds you whenever this buff is missing, on the classes ticked here." }
        end
        local function SlotAt(k)
            if k == 1 then return lead end
            if k == 2 then return newGroupSlot end
            local id = ids and ids[k - 2]
            return id and Slot(id) or EllesmereUI.BlankRowCfg()
        end
        local function Remove(id)
            local fo = FDB()
            local list = fo and fo.customIDs
            if not list then return end
            for j = #list, 1, -1 do
                if list[j] == id then table.remove(list, j) end
            end
            if fo.customClasses then fo.customClasses[id] = nil end
            RefreshAll()
            EllesmereUI:RefreshPage(true)
        end
        -- A tracked spell's slot: its icon before the name, and its classes
        -- (Remove at the top) on the right.
        local function DressSlot(rgn, id)
            if not id then return end
            local lbl = rgn._label
            if lbl then
                local ico = rgn:CreateTexture(nil, "ARTWORK")
                ico:SetSize(22, 22)
                ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                ico:SetTexture(Tex(id))
                PPx.Point(ico, "LEFT", rgn, "LEFT", 20, 0)
                lbl:ClearAllPoints()
                PPx.Point(lbl, "LEFT", ico, "RIGHT", 8, 0)
            end
            local items = { { key = "_remove", label = "Remove", isTopAction = true,
                onClick = function() Remove(id) end } }
            local classes = EllesmereUI.ForeverClasses()
            for i = 1, #classes do
                local token = classes[i]
                local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
                local name = EllesmereUI.ForeverClassName(token)
                items[#items + 1] = { key = token, label = c and c.colorStr and ("|c" .. c.colorStr .. name .. "|r") or name }
            end
            local dd, ddRefresh = EllesmereUI.BuildVisOptsCBDropdown(rgn, 170, rgn:GetFrameLevel() + 2, items,
                function(token)
                    local fo = FDB()
                    local off = fo and fo.customClasses and fo.customClasses[id]
                    return not (off and off[token] == false)
                end,
                function(token, v)
                    local fo = FDB(); if not fo then return end
                    local cc = fo.customClasses
                    if not cc then cc = {}; fo.customClasses = cc end
                    local off = cc[id]
                    if v then
                        if off then
                            off[token] = nil
                            if not next(off) then cc[id] = nil end
                        end
                    else
                        if not off then off = {}; cc[id] = off end
                        off[token] = false
                    end
                    RefreshAll()
                end)
            PPx.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = dd
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(ddRefresh)
        end
        for k = 1, n, 2 do
            local row, h = W:DualRow(parent, y, SlotAt(k), SlotAt(k + 1))
            if ids and not EllesmereUI._prebuilding then
                DressSlot(row._leftRegion, ids[k - 2])
                DressSlot(row._rightRegion, ids[k - 1])
            end
            y = y - h
        end
        return y
    end

    ---------------------------------------------------------------------------
    --  Glow site: the reminder icon glow as a shared glow descriptor, used by the
    --  Reminders page and the Global Settings Glows page.
    ---------------------------------------------------------------------------
    local abrGlowDesc
    do
        local GO = EllesmereUI.GlowOptions
        abrGlowDesc = _G._EABR_GLOW_VIEW and {
            view = _G._EABR_GLOW_VIEW, host = "icon", excludes = { [4] = true },
            caps = { mode = true, params = true, bg = true },
            defaultColor = { r = 1.0, g = 0.788, b = 0.137 },
            onChange = function() RefreshAll(); UpdatePreviewHeader() end,
            get = function(f)
                local d = DDB(); if not d then return nil end
                if f == "style" then return d.glowType or 0
                elseif f == "mode" then
                    -- Read-path migration: a profile activated mid-session may not
                    -- have a mode key yet; derive it from the stored color.
                    if _G._EABR_EnsureGlowModeMigrated then _G._EABR_EnsureGlowModeMigrated(d) end
                    return d.glowColorMode or "default"
                end
                return EllesmereUI.GlowOptions.FlatGet(d, "glow", f)
            end,
            set = function(f, a, b2, c2)
                local d = DDB(); if not d then return end
                if f == "style" then d.glowType = a
                elseif f == "mode" then d.glowColorMode = a
                else EllesmereUI.GlowOptions.FlatSet(d, "glow", f, a, b2, c2)
                end
            end,
        }
        if abrGlowDesc then
            GO.RegisterSite({ id = "abr_glow", label = "Reminder Glow", group = "module",
                module = "EllesmereUIAuraBuffReminders", page = PAGE_REMINDERS, section = SECTION_DISPLAY,
                highlight = "Glow Type", desc = abrGlowDesc })
        end
    end

    ---------------------------------------------------------------------------
    --  Beacon M+ row: the CORE toggle shows only for a retail Holy Paladin. A
    --  page built for one Holy state is rebuilt once the player's no longer
    --  matches it: on a spec change while the page is shown, or when the cached
    --  page is shown again after one. One event frame, re-parented into each
    --  build of the page, so its show and hide are the page's and the event is
    --  registered only while the page is shown. Other classes and WoW Forever
    --  never make it.
    ---------------------------------------------------------------------------
    local BeaconRowShown
    do
        local paladin = not FOREVER and select(2, UnitClass("player")) == "PALADIN"
        local watch, builtHoly, queued
        local function IsHoly()
            local spec = C_SpecializationInfo.GetSpecialization()
            return spec ~= nil and C_SpecializationInfo.GetSpecializationInfo(spec) == 65
        end
        -- One rebuild per burst, a frame later: a cached page has finished showing
        local function Flush()
            queued = nil
            if watch:IsVisible() and IsHoly() ~= builtHoly then EllesmereUI:RefreshPage(true) end
        end
        local function Queue()
            if queued then return end
            queued = true
            C_Timer.After(0, Flush)
        end
        -- Each build of the page: whether the toggle shows
        BeaconRowShown = function(parent)
            if not paladin then return false end
            local holy = IsHoly()
            if EllesmereUI._prebuilding then return holy end
            builtHoly = holy
            if not watch then
                watch = CreateFrame("Frame")
                watch._searchIgnore = true  -- the inline search never hides it
                watch:SetScript("OnEvent", Queue)
                watch:SetScript("OnShow", function(self)
                    self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
                    if IsHoly() ~= builtHoly then Queue() end
                end)
                watch:SetScript("OnHide", function(self)
                    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
                end)
            end
            watch:Hide()
            watch:SetParent(parent)
            -- On a kept page wrapper the watcher rides it as an attachment: the
            -- wrapper's next dress hides it (as dropping the page did) and
            -- never moves it to the pool's graveyard.
            Pool.Attach(parent, watch)
            watch:Show()
            return holy
        end
    end

    local function BuildRemindersPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h, row

        -- Cell reference table for preview icon specific toggle navigation
        local _gridCellRefs = {}

        -- Set up the preview header (retail only; WoW Forever has no preview)
        if not FOREVER then EllesmereUI:SetContentHeader(_previewHeaderBuilder) end

        parent._showRowDivider = true

        -- Click-action info label at the top of the page (below the preview area)
        do
            local fontPath = (EllesmereUI.GetFontPath("auraBuff")) or "Fonts\\FRIZQT__.TTF"
            local infoFrame = CreateFrame("Frame", nil, parent)
            infoFrame:SetSize(parent:GetWidth(), 20)
            infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 15)
            infoFrame._isSpacer = true
            local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
            line1:SetFont(fontPath, 15, "")
            line1:SetTextColor(1, 1, 1, 0.75)
            line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
            line1:SetJustifyH("CENTER")
            line1:SetText(EllesmereUI.L("Left Click to apply buffs (out of combat), Middle Click to hide until next load screen"))
            y = y - 32
        end

        -- WoW Forever: what this module is for, in the red of the suite's
        -- warning banners, right above CORE. "CDM module" (the template's %s)
        -- is its own button, like the patch notes' contributors link, and opens
        -- the Cooldown Manager's Buffs bar while that module is loaded. Not
        -- built in the search prebuild (nothing to index); y moves the same.
        if FOREVER then
            local GAP, WARN_H = 6, 44
            if not EllesmereUI._prebuilding then
                local PAD = EllesmereUI.CONTENT_PAD
                local w = parent:GetWidth() - PAD * 2
                local R, G, B = 1, 0.25, 0.25
                local host = CreateFrame("Frame", nil, parent)
                PP.Point(host, "TOPLEFT", parent, "TOPLEFT", PAD, y - GAP)
                local line1 = EllesmereUI.MakeFont(host, 16, nil, R, G, B, 1)
                line1:SetPoint("TOP", host, "TOP", 0, 0)
                line1:SetWidth(w)
                line1:SetWordWrap(true)
                line1:SetJustifyH("CENTER")
                line1:SetText(EllesmereUI.L("This module is for OUT OF COMBAT non-rotational buff/consumable reminders,"))
                local tmpl = EllesmereUI.L("for in combat aura/rotational reminders please use the %s") or ""
                local pre, post = tmpl:match("^(.-)%%s(.*)$")
                if not pre then pre, post = tmpl, "" end
                local line2 = CreateFrame("Frame", nil, host)
                local preFs = EllesmereUI.MakeFont(line2, 16, nil, R, G, B, 1)
                preFs:SetPoint("LEFT", line2, "LEFT", 0, 0)
                preFs:SetText(pre)
                local link = CreateFrame("Button", nil, line2)
                local linkFs = EllesmereUI.MakeFont(link, 16, nil, R, G, B, 1)
                linkFs:SetPoint("LEFT", link, "LEFT", 0, 0)
                linkFs:SetText(EllesmereUI.L("CDM module"))
                link:SetSize(math.ceil(linkFs:GetStringWidth() or 80) + 1, 20)
                link:SetPoint("LEFT", preFs, "RIGHT", 0, 0)
                local postFs = EllesmereUI.MakeFont(line2, 16, nil, R, G, B, 1)
                postFs:SetPoint("LEFT", link, "RIGHT", 0, 0)
                postFs:SetText(post)
                if EllesmereUI._ModuleNS["EllesmereUICooldownManager"] then
                    local EG = EllesmereUI.ELLESMERE_GREEN
                    linkFs:SetTextColor(EG.r, EG.g, EG.b, 1)
                    linkFs:SetAlpha(0.85)
                    link:SetScript("OnEnter", function(self)
                        linkFs:SetAlpha(1)
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Open the Cooldown Manager's Buffs bar"))
                    end)
                    link:SetScript("OnLeave", function()
                        linkFs:SetAlpha(0.85)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    link:SetScript("OnClick", function()
                        EllesmereUI.HideWidgetTooltip()
                        EllesmereUI:NavigateToElementSettings("EllesmereUICooldownManager", "CDM Bars", nil,
                            function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar("buffs") end end)
                    end)
                else
                    link:EnableMouse(false)
                end
                local w2 = (preFs:GetStringWidth() or 0) + link:GetWidth() + (postFs:GetStringWidth() or 0)
                PP.Size(line2, math.ceil(w2), 20)
                line2:SetPoint("TOP", line1, "BOTTOM", 0, -4)
                -- A translation long enough to wrap the first line pushes CORE down.
                WARN_H = math.max(WARN_H, math.ceil(line1:GetStringHeight() or 0) + 24)
                PP.Size(host, w, WARN_H)
            end
            y = y - (GAP + WARN_H + 14)
        end

        -----------------------------------------------------------------------
        --  CORE section
        -----------------------------------------------------------------------
        local coreSection
        coreSection, h = W:SectionHeader(parent, SECTION_CORE, y);  y = y - h
        EllesmereUI.BuildSectionUnlockJump(coreSection, { key = "EABR_Reminders" })

        -- Row 1: Enable AuraBuff Reminders | Attach Important Buffs to Cursor (+ cog)
        local row1
        row1, h = W:DualRow(parent, y,
            { type="toggle", text="Enable AuraBuff Reminders",
              tooltip="Master toggle for all aura, buff, and consumable reminders. Talent reminders are not affected.",
              getValue=function() local d = DDB(); return d and d.remindersEnabled ~= false end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.remindersEnabled = v
                  if _G._EABR_UpdateGroupAuraRegistration then _G._EABR_UpdateGroupAuraRegistration() end
                  RefreshAll()
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Attach Important Buffs to Cursor",
              tooltip="This option only affects Raid Buffs and Paladin Beacons",
              getValue=function() local d = DDB(); return d and d.cursorAttach end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.cursorAttach = v; RefreshAll()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        EllesmereUI.BuildInlineCog(row1._rightRegion, {
            title = "Cursor Settings",
            disabled = function() local d = DDB(); return not (d and d.cursorAttach) end,
            disabledTooltip = "Attach Important Buffs to Cursor",
            rows = {
                { type="toggle", label="Only on Cursor in Combat",
                  tooltip="Out of combat, important buffs show with your other reminders.",
                  get=function() local d = DDB(); return d and d.cursorAttachCombatOnly == true end,
                  set=function(v) local d = DDB(); if not d then return end; d.cursorAttachCombatOnly = v; RefreshAll() end },
            },
        })

        -- Row 2: Show Below | Show Below Pre-Key (global timing, minutes)
        -- No expiry thresholds on WoW Forever (its reminders are absence only): the row is not built there.
        if not FOREVER then
        local timingRow
        timingRow, h = W:DualRow(parent, y,
            { type="slider", text="Show Below", min=0, max=60, step=1,
              tooltip="Show reminders when remaining buff time is below this many minutes.\n0 = only when fully expired.\nIgnored in combat and during Mythic+ keys (then only when the buff is gone).",
              getValue=function() local d = DDB(); return d and d.showUnder or 5 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showUnder = v
                  RefreshAll()
              end },
            { type="slider", text="Show Below Pre-Key", min=0, max=60, step=1,
              tooltip="Reminder threshold while you are in a dungeon before a Mythic+ key starts (Mythic 0 / keystone lobby). Set it high enough that you top up buffs and food before pulling, so you begin the key with enough duration to last it.\n0 = only when fully expired.\nIgnored once the key is active or you are in combat (then only when the buff is fully gone).",
              getValue=function() local d = DDB(); return d and d.showUnderMPlus or 40 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showUnderMPlus = v
                  RefreshAll()
              end }
        );  y = y - h
        AddMinSuffix(timingRow, "Show Below", "Show Below Pre-Key")
        end -- not FOREVER

        -- Row 3: Show Tooltips | Beacon M+ Reminders (retail Holy Paladins only). WoW Forever has no
        -- Beacon, so its Action Picker takes the slot.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Tooltips",
              tooltip="Show item or spell tooltips when hovering reminder icons.",
              getValue=function() local d = DDB(); return not d or d.showTooltips ~= false end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showTooltips = v
              end },
            (function()
                if FOREVER then
                    return { type="toggle", text="Action Picker",
                      tooltip="Right-click a spell group or Class Buffs reminder to choose a spell, or an item reminder such as Well Fed or Scrolls and Elixirs to choose an item. Scroll over a spell to choose its rank.",
                      getValue=function() local f = FDB(); return f and f.pickerEnabled == true end,
                      setValue=function(v)
                          local f = FDB(); if not f then return end; f.pickerEnabled = v
                          RefreshAll()
                      end }
                end
                if not BeaconRowShown(parent) then return EllesmereUI.BlankRowCfg() end
                return { type="toggle", text="Beacon M+ Reminders",
                  tooltip="During Mythic+ boss fights, shows a glowing red Beacon on your tank's raid frame while they have your Beacon of Light or Beacon of Faith.",
                  disabled=function() return not EllesmereUI._ModuleNS["EllesmereUIRaidFrames"] end,
                  disabledTooltip=EllesmereUI.DisabledTooltip("EllesmereUI Raid & Party Frames"),
                  getValue=function() local d = DDB(); return d and d.beaconMPlus == true end,
                  setValue=function(v)
                      local d = DDB(); if not d then return end
                      d.beaconMPlus = v or nil
                      RefreshAll()
                  end }
            end)()
        );  y = y - h

        -----------------------------------------------------------------------
        --  DISPLAY section
        -----------------------------------------------------------------------
        local displaySection
        displaySection, h = W:SectionHeader(parent, SECTION_DISPLAY, y);  y = y - h

        -- Row 1: Icon Size | Icon Shape (+ cog: Icon Zoom, Adjust Crop)
        do
            local values, order = ns.IconShapeValues()
            local shapeRow
            shapeRow, h = W:DualRow(parent, y,
                -- A view over the saved scale (the base icon size x scale, the size the runtime draws):
                -- 20 to 120 px is the old 0.5 to 3.0, and nothing saved changes until the slider moves.
                { type="slider", text="Icon Size", min=20, max=120, step=1,
                  getValue=function()
                      local d = DDB()
                      return math.floor((_G._EABR_ICON_SIZE or 40) * (d and d.scale or 1.0) + 0.5)
                  end,
                  setValue=function(v)
                      local d = DDB(); if not d then return end; d.scale = v / (_G._EABR_ICON_SIZE or 40)
                      RefreshAll()
                      UpdatePreviewHeader()
                  end },
                { type="dropdown", text="Icon Shape", values=values, order=order,
                  itemDisabled=function(v)
                      local d = DDB()
                      return v ~= "none" and v ~= "cropped" and d and (d.borderTexture or "solid") ~= "solid"
                  end,
                  itemDisabledTooltip="This option requires Border Style to be set to Solid",
                  getValue=function() local d = DDB(); return (d and d.iconShape) or "none" end,
                  setValue=function(v)
                      local d = DDB(); if not d then return end
                      d.iconShape = v
                      ns.RefreshIconShapes(); UpdatePreviewHeader(); EllesmereUI:RefreshPage(true)
                  end }
            ); y = y - h
            EllesmereUI.BuildInlineCog(shapeRow._rightRegion, {
                title="Icon Shape",
                rows={
                    { type="slider", label="Icon Zoom", min=0, max=15, step=0.5,
                      get=function() local d = DDB(); return ((d and d.iconZoom) or 0.07) * 100 end,
                      set=function(v)
                          local d = DDB(); if not d then return end
                          d.iconZoom = v / 100
                          ns.RefreshIconShapes(); UpdatePreviewHeader()
                      end },
                    { type="slider", label="Adjust Crop", min=5, max=25, step=1,
                      tooltip="How much is trimmed from the icon's top and bottom, per side (10% is the classic cropped look).",
                      disabled=function() local d = DDB(); return not d or d.iconShape ~= "cropped" end,
                      disabledTooltip="This option requires Icon Shape to be set to Cropped",
                      get=function() return ns.CropPercent(DDB()) end,
                      set=function(v)
                          local d = DDB(); if not d then return end
                          d.iconCropPercent = v
                          ns.RefreshIconShapes(); UpdatePreviewHeader()
                      end },
                },
            })
        end

        -- Row 2: Grow Direction (+ cog: Frame Strata) | Icon Spacing
        do
            local growRow
            growRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Grow Direction",
                  values=GROW_DIR_VALUES, order=GROW_DIR_ORDER,
                  tooltip="Which part of the row stays in place as reminders appear and disappear.",
                  getValue=function() local d = DDB(); return d and d.growDirection or "CENTER" end,
                  setValue=function(v)
                      EllesmereUI.SetAuraBuffGrowDir(v)
                      RefreshAll()
                      RelayoutPreviewIcons()
                  end },
                { type="slider", pixel=true, text="Icon Spacing", min=0, max=50, step=1,
                  getValue=function() local d = DDB(); return d and d.iconSpacing or 8 end,
                  setValue=function(v)
                      local d = DDB(); if not d then return end; d.iconSpacing = v
                      RefreshAll()
                      RelayoutPreviewIcons()
                  end }
            );  y = y - h
            EllesmereUI.BuildInlineCog(growRow._leftRegion, {
                title = "Layout Settings",
                rows = {
                    { type="dropdown", label="Frame Strata",
                      values=_G._EABR_STRATA_VALUES or {MEDIUM="Medium"},
                      order=_G._EABR_STRATA_ORDER or {"MEDIUM"},
                      get=function() local d = DDB(); return d and d.frameStrata or "MEDIUM" end,
                      set=function(v)
                          local d = DDB(); if not d then return end; d.frameStrata = v
                          if _G._EABR_ApplyStrata then _G._EABR_ApplyStrata() end
                      end },
                },
            })
        end

        -- Row 3: Border Style (+ options cog) | Border Size (+ color swatch)
        local borderTextureValues, borderTextureOrder = EllesmereUI.GetBorderTextureDropdown()
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              disabled=function() return ns.IconShapeMasked(DDB()) end,
              disabledTooltip="This option requires Icon Shape to be set to None or Cropped",
              values=borderTextureValues, order=borderTextureOrder,
              getValue=function() local d = DDB(); return d and d.borderTexture or "solid" end,
              setValue=function(v)
                  local d = DDB(); if not d then return end
                  d.borderTexture = v
                  d.borderTextureOffset = nil
                  d.borderTextureOffsetY = nil
                  d.borderTextureShiftX = nil
                  d.borderTextureShiftY = nil
                  local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  d.borderR, d.borderG, d.borderB, d.borderA = color.r, color.g, color.b, 1
                  d.borderBehind = behind
                  local defaultSize = EllesmereUI.GetBorderDefaultSize("aurabuffreminders", v)
                  if defaultSize then d.borderSize = defaultSize end
                  if d.borderSizePx then d.borderSizePx = false end
                  RefreshBorders()
                  -- Rebuild: the Width | Height Offset row follows the Solid / textured pick.
                  EllesmereUI:RefreshPage(true)
              end },
            -- Exact pixels over borderSize (the number the icons render with) and its
            -- borderSizePx companion (EllesmereUI.BorderPx).
            (ns.IconShapeMasked(DDB()) and {
              type="dropdown", text="Border Size",
              values={ none="None", strong="Strong" }, order={ "none", "strong" },
              -- The ring shows at any size above 0, so a pick keeps the square
              -- border's own size for the way back to None or Cropped.
              getValue=function() local d = DDB(); return d and (d.borderSize or 1) > 0 and "strong" or "none" end,
              setValue=function(v)
                  local d = DDB(); if not d then return end
                  if v ~= "strong" then d.borderSize = 0
                  elseif (d.borderSize or 1) <= 0 then d.borderSize = 1 end
                  RefreshBorders()
              end,
            } or EllesmereUI.BorderPxSliderCfg{
              text="Border Size",
              getStep=function() local d = DDB(); return (d and d.borderSize) or 1 end,
              setStep=function(v) local d = DDB(); if d then d.borderSize = v end end,
              getTex=function() local d = DDB(); return (d and d.borderTexture) or "solid" end,
              getPx=function() local d = DDB(); return d and d.borderSizePx end,
              setPx=function(v) local d = DDB(); if d then d.borderSizePx = v end end,
              apply=RefreshBorders })
        );  y = y - h

        -- Row 3b: Width Offset | Height Offset. The textured border's outward offsets
        -- as their own row, present only while a textured style is selected (the style
        -- setter rebuilds the page). Each slider shows what is drawn (override, else the
        -- "aurabuffreminders" registry default for the step) and stores nothing while
        -- the value follows the default.
        do
            local d = DDB()
            local tex = (d and d.borderTexture) or "solid"
            if tex ~= "" and tex ~= "solid" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs{
                    addonKey = "aurabuffreminders",
                    getTex = function() local d = DDB(); return (d and d.borderTexture) or "solid" end,
                    getStep = function() local d = DDB(); return (d and d.borderSize) or 1 end,
                    getSizeKey = function() local d = DDB(); return (d and d.borderSize) or 1 end,
                    getPx = function() local d = DDB(); return d and d.borderSizePx end,
                    getX = function() local d = DDB(); return d and d.borderTextureOffset end,
                    setX = function(v) local d = DDB(); if d then d.borderTextureOffset = v end end,
                    getY = function() local d = DDB(); return d and d.borderTextureOffsetY end,
                    setY = function(v) local d = DDB(); if d then d.borderTextureOffsetY = v end end,
                    apply = RefreshBorders,
                }
                _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
            end
        end

        do
            do
                local rgn = borderRow._leftRegion
                local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
                    title = "Border Options",
                    rows = {
                        { type="slider", label="Shift X", min=-10, max=10, step=1,
                          get=function()
                              local d = DDB(); if not d then return 0 end
                              if d.borderTextureShiftX ~= nil then return d.borderTextureShiftX end
                              local _, _, value = EllesmereUI.GetBorderDefaults("aurabuffreminders", d.borderTexture or "solid", d.borderSize or 1)
                              return value
                          end,
                          set=function(v) local d=DDB(); if d then d.borderTextureShiftX=(v ~= 0) and v or nil; RefreshBorders() end end },
                        { type="slider", label="Shift Y", min=-10, max=10, step=1,
                          get=function()
                              local d = DDB(); if not d then return 0 end
                              if d.borderTextureShiftY ~= nil then return d.borderTextureShiftY end
                              local _, _, _, value = EllesmereUI.GetBorderDefaults("aurabuffreminders", d.borderTexture or "solid", d.borderSize or 1)
                              return value
                          end,
                          set=function(v) local d=DDB(); if d then d.borderTextureShiftY=(v ~= 0) and v or nil; RefreshBorders() end end },
                        { type="toggle", label="Show Behind",
                          get=function() local d=DDB(); return d and d.borderBehind == true end,
                          set=function(v) local d=DDB(); if d then d.borderBehind=v; RefreshBorders() end end },
                    },
                })
                if not EllesmereUI._prebuilding then
                    local function UpdateBorderCogVisibility()
                        local d = DDB()
                        cogBtn:SetShown(d and (d.borderTexture or "solid") ~= "solid")
                    end
                    UpdateBorderCogVisibility()
                    EllesmereUI.RegisterWidgetRefresh(UpdateBorderCogVisibility)
                end
            end

            if not EllesmereUI._prebuilding then
                local rgn = borderRow._rightRegion
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel()+5,
                    function()
                        local d = DDB()
                        return (d and d.borderR) or 0, (d and d.borderG) or 0,
                            (d and d.borderB) or 0, (d and d.borderA) or 1
                    end,
                    function(r, g, b, a)
                        local d = DDB(); if not d then return end
                        d.borderR, d.borderG, d.borderB, d.borderA = r, g, b, a or 1
                        RefreshBorders()
                    end, true, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = swatch
                EllesmereUI.RegisterWidgetRefresh(updateSwatch)
            end
        end

        -- Row 4: Show Name (+ inline cog + swatch) | Show Item Count (+ cog)
        local rowText
        rowText, h = W:DualRow(parent, y,
            { type="toggle", text="Show Name",
              getValue=function() local d = DDB(); return d and d.showText end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showText = v
                  RefreshAll()
                  UpdatePreviewHeader()
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Item Count",
              tooltip="Show how many of the consumable you have left in your bags.",
              getValue=function() local d = DDB(); return not d or d.showCount ~= false end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showCount = v
                  RefreshAll(); UpdatePreviewHeader()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline cog on Show Item Count (right of row 4): size + offsets
        do
            local rgn = rowText._rightRegion
            local countFontValues, countFontOrder = EllesmereUI.BuildFontDropdownData()
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Item Count Settings",
                disabled = function() local d = DDB(); return d and d.showCount == false end,
                disabledTooltip = "Show Item Count",
                rows = {
                    { type="dropdown", label="Item Count Font",
                      values=countFontValues, order=countFontOrder,
                      get=function() local d = DDB(); return (d and d.countFont) or "__global" end,
                      set=function(v)
                          local d = DDB(); if not d then return end
                          d.countFont = (v ~= "__global") and v or nil
                          RefreshAll()
                      end },
                    { type="slider", label="Text Size", min=6, max=30, step=1,
                      get=function() local d = DDB(); return d and d.countSize or 16 end,
                      set=function(v) local d = DDB(); if not d then return end; d.countSize = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() local d = DDB(); return d and d.countXOffset or 0 end,
                      set=function(v) local d = DDB(); if not d then return end; d.countXOffset = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() local d = DDB(); return d and d.countYOffset or 0 end,
                      set=function(v) local d = DDB(); if not d then return end; d.countYOffset = v; RefreshAll(); UpdatePreviewHeader() end },
                },
            })
        end

        -- Inline cog + color swatch on Show Name (left of row 4)
        do
            local rgn = rowText._leftRegion
            -- Inline cog for name settings (font, size, anchor, x/y offset)
            local nameFontValues, nameFontOrder = EllesmereUI.BuildFontDropdownData()
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Name Settings",
                disabled = function() local d = DDB(); return not d or not d.showText end,
                disabledTooltip = "Show Name",
                rows = {
                    { type="dropdown", label="Name Font",
                      values=nameFontValues, order=nameFontOrder,
                      get=function() local d = DDB(); return (d and d.nameFont) or "__global" end,
                      set=function(v)
                          local d = DDB(); if not d then return end
                          d.nameFont = (v ~= "__global") and v or nil
                          RefreshAll(); UpdatePreviewHeader()
                      end },
                    { type="slider", label="Text Size", min=6, max=30, step=1,
                      get=function() local d = DDB(); return d and d.textSize or 11 end,
                      set=function(v) local d = DDB(); if not d then return end; d.textSize = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="dropdown", label="Anchor",
                      values = {
                          BOTTOM = "Below Icon", TOP = "Above Icon",
                          CENTER = "On Icon", LEFT = "Left of Icon", RIGHT = "Right of Icon",
                      },
                      order = { "BOTTOM", "TOP", "CENTER", "LEFT", "RIGHT" },
                      get=function() local d = DDB(); return d and d.textAnchor or "BOTTOM" end,
                      set=function(v) local d = DDB(); if not d then return end; d.textAnchor = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() local d = DDB(); return d and d.textXOffset or 0 end,
                      set=function(v) local d = DDB(); if not d then return end; d.textXOffset = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() local d = DDB(); return d and d.textYOffset or -2 end,
                      set=function(v) local d = DDB(); if not d then return end; d.textYOffset = v; RefreshAll(); UpdatePreviewHeader() end },
                },
            })

            if not EllesmereUI._prebuilding then
                local swatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel()+5,
                    function()
                        local d = DDB()
                        local tc = d and d.textColor or {r=1, g=1, b=1}
                        return tc.r, tc.g, tc.b, 1
                    end,
                    function(r, g, b)
                        local d = DDB(); if not d then return end
                        d.textColor = {r=r, g=g, b=b}
                        RefreshAll(); UpdatePreviewHeader()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch

                -- Disabled overlay for swatch when Show Name is off
                local swatchBlock = CreateFrame("Frame", nil, swatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                swatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Show Name"))
                end)
                swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local function UpdateTextInlinesDisabled()
                    local d = DDB()
                    local off = not d or not d.showText
                    swatch:SetAlpha(off and 0.3 or 1)
                    swatchBlock:SetShown(off)
                end
                UpdateTextInlinesDisabled()
                EllesmereUI.RegisterWidgetRefresh(UpdateTextInlinesDisabled)
            end
        end

        -- Row 5: Glow Type (shared glow controls) | Opacity
        do
            local GO = EllesmereUI.GlowOptions
            local abrDesc = abrGlowDesc
            local rowGlow
            rowGlow, h = W:DualRow(parent, y,
                abrDesc and GO.DropdownSpec(abrDesc, "Glow Type") or EllesmereUI.BlankRowCfg(),
                { type="slider", text="Opacity", min=0, max=1, step=0.05,
                  getValue=function() local d = DDB(); return d and d.opacity or 1 end,
                  setValue=function(v)
                      local d = DDB(); if not d then return end; d.opacity = v
                      RefreshAll(); UpdatePreviewHeader()
                  end }
            );  y = y - h
            if abrDesc then GO.AttachInline(rowGlow._leftRegion, abrDesc) end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  RAID BUFFS section (WoW Forever: its own locations and its own
        --  buffs, which the module exports as the raid buff list there)
        -----------------------------------------------------------------------
        local raidBufHdr
        raidBufHdr, h = W:SectionHeader(parent, SECTION_RAID_BUFFS, y);  y = y - h

        -- Where to Show | Show When (+ reminder sound cog)
        _, h = SectionControlRow(parent, y, {
            whereStore = RWhere, whereItems = FOREVER and FOREVER_WHERE_ITEMS or nil,
            whereTooltip = "Pick which content this section's reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            showWhenStore = RShowWhen,
            showWhenTooltip = "Others are missing my buff: remind when a groupmate is missing a buff you can cast.\nI am missing others' buffs: remind when you are missing a buff a groupmate could give you (only shown when someone who can cast it is present). Off by default.",
            soundSec = RDB, soundField = "sectionSound",
            cogTitle = (not FOREVER) and "Raid Buff Options" or nil,
            cogRows = (not FOREVER) and {
                { type="toggle", label="Click to Request Buff",
                  tooltip="Click a buff or Healthstone to ask for it.",
                  get=function() local r = RDB(); return r and r.requestOnClick == true end,
                  set=function(v) local r = RDB(); if r then r.requestOnClick = v; RefreshAll() end end },
                { type="toggle", label="Custom Request Text",
                  tooltip="Send your own text instead of the default.",
                  disabled=function() local r = RDB(); return not (r and r.requestOnClick) end,
                  disabledTooltip="Click to Request Buff",
                  get=function() local r = RDB(); return r and r.requestCustom == true end,
                  set=function(v) local r = RDB(); if r then r.requestCustom = v end end },
                { type="input", label="Request Text", inputWidth=170, inputJustify="LEFT",
                  tooltip="Type [spell] where the buff's name goes.",
                  disabled=function() local r = RDB(); return not (r and r.requestOnClick and r.requestCustom) end,
                  disabledTooltip="Custom Request Text",
                  get=function()
                      local r = RDB(); if not r then return "" end
                      return r.requestText or _G._EABR_RequestExample()
                  end,
                  set=function(v)
                      local r = RDB(); if not r then return end
                      local clean = _G._EABR_CleanRequestText(v)
                      -- The untouched example stays unsaved, so it follows the client language.
                      if clean == _G._EABR_RequestExample() then clean = nil end
                      r.requestText = clean
                      if clean and not _G._EABR_HasRequestToken(clean) then
                          UIErrorsFrame:AddMessage(EllesmereUI.Lf("Request text must include %1$s", _G._EABR_REQUEST_TOKEN), 1.0, 0.3, 0.3, 1.0)
                      end
                  end },
            } or nil,
            onChange = RefreshAll,
            onShowWhenChange = function() if _G._EABR_UpdateGroupAuraRegistration then _G._EABR_UpdateGroupAuraRegistration() end end,
        });  y = y - h

        -- 4-column checkbox grid for individual raid buffs
        do
            local RAID_BUFFS = _G._EABR_RAID_BUFFS or {}
            local gridItems = {}
            for _, buff in ipairs(RAID_BUFFS) do
                gridItems[#gridItems+1] = {
                    label = _G._EABR_SpellName(buff.castSpell, buff.name),
                    classToken = buff.class,
                    key = buff.key,
                    getVal = function() local r = RDB(); return r and r.enabled and r.enabled[buff.key] end,
                    setVal = function(v) local r = RDB(); if r and r.enabled then r.enabled[buff.key] = v end end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function() RefreshAll(); RebuildPreviewHeader() end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  WoW Forever sections: on that client the rest of the page.
        --  SELF BUFFS: Mage Armors or Class Buffs | Weapon Imbues, Gathering
        --  Tracking | Find Treasure, then the custom spells and spell groups.
        --  CONSUMABLES: Camp Benefits | Sleeping Bag, Well Fed | Arcane Censer,
        --  Scrolls and Elixirs | Weapon Stones and Oils. The retail sections
        --  below never build.
        -----------------------------------------------------------------------
        if FOREVER then
            local class = select(2, UnitClass("player"))
            local classBuffs = not MAGE and _G._EABR_FvClassBuffs and _G._EABR_FvClassBuffs()[class]
            local rogue = class == "ROGUE"
            local offHand = not CanDualWield or CanDualWield()

            local function WeaponChoices(isImbue)
                local values, order = { auto = "Auto", off = "Off" }, { "auto", "off" }
                for _, b in ipairs(_G._EABR_FV_WEAPON_BUFFS or {}) do
                    if (b.imbue == true) == isImbue and (not b.class or b.class == class) then
                        values[b.key] = b.name or _G._EABR_SpellName(b.spells[#b.spells], b.key)
                        order[#order + 1] = b.key
                    end
                end
                return values, order
            end
            local function HandRow(label, field, values, order)
                return { type="dropdown", label=label, values=values, order=order, ddWidth=200,
                  get=function()
                      local f = FDB(); local t = f and f.weaponHands and f.weaponHands[class]
                      return t and t[field] or "auto"
                  end,
                  set=function(v)
                      local f = FDB(); if not f then return end
                      f.weaponHands = f.weaponHands or {}
                      local t = f.weaponHands[class]
                      if not t then t = {}; f.weaponHands[class] = t end
                      t[field] = v ~= "auto" and v or nil
                      RefreshAll()
                  end }
            end
            local function BuildWeaponCog(rgn, title, enabledField, rows)
                rows[#rows + 1] = { type="dropdown", label="Rank to Use", ddWidth=200,
                  values={ high = "Highest Owned", low = "Lowest Owned" }, order={ "high", "low" },
                  get=function() local f = FDB(); return f and f.weaponLowRank and "low" or "high" end,
                  set=function(v) local f = FDB(); if f then f.weaponLowRank = v == "low"; RefreshAll() end end }
                rows[#rows + 1] = { type="toggle", label="Hide When None in Bags",
                  tooltip="Hides a reminder when you have none of its item in your bags.\nOff: a chosen item still shows, greyed out. Auto only ever picks items you have.\nA warlock's Firestone or Spellstone shows its Create spell instead.",
                  get=function() local f = FDB(); return not f or f.weaponHideNoItem ~= false end,
                  set=function(v) local f = FDB(); if f then f.weaponHideNoItem = v; RefreshAll() end end }
                rows[#rows + 1] = { type="slider", label="Show Below (Minutes)", min=0, max=10, step=1,
                  tooltip="Show a reminder before a poison, imbue, stone or oil runs out.\n0 = only once it has run out.\n1-10 = when it has less than this many minutes left.",
                  get=function() local f = FDB(); return f and f.weaponShowBelow or 1 end,
                  set=function(v) local f = FDB(); if f then f.weaponShowBelow = v; RefreshAll() end end }
                EllesmereUI.BuildInlineCog(rgn, {
                    title = title,
                    disabled = function() local f = FDB(); return not (f and f[enabledField] == true) end,
                    disabledTooltip = title,
                    minWidth = 320,
                    rows = rows,
                })
            end
            local function WeaponToggle(text, tooltip, field)
                return { type="toggle", text=text, tooltip=tooltip,
                  getValue=function() local f = FDB(); return f and f[field] == true end,
                  setValue=function(v)
                      local f = FDB(); if not f then return end; f[field] = v
                      RefreshAll()
                      EllesmereUI:RefreshPage()
                  end }
            end
            local imbueValues, imbueOrder = WeaponChoices(true)
            local imbueLabel = rogue and "Poisons" or "Weapon Imbues"

            _, h = W:SectionHeader(parent, SECTION_SELF_BUFFS, y);  y = y - h
            _, h = SectionControlRow(parent, y, {
                whereStore = FSelfWhere, whereItems = FOREVER_SECTION_WHERE_ITEMS,
                whereTooltip = "Pick which content your own buffs and imbues remind you in.\nRested areas (cities and inns) always stay hidden.",
                soundSec = FDB, soundField = "selfSound",
                onChange = RefreshAll,
            });  y = y - h

            local selfSlots, classIdx, imbueIdx = {}, nil, nil
            if MAGE then
                selfSlots[1] = { type="toggle", text="Mage Armors",
                  tooltip="Reminds you when no Frost Armor, Ice Armor or Mage Armor is up.\nThe icon is the one you last had on; click it to cast it.",
                  getValue=function() local f = FDB(); return f and f.mageArmor == true end,
                  setValue=function(v)
                      local f = FDB(); if not f then return end; f.mageArmor = v
                      RefreshAll()
                  end }
                classIdx = 1
            elseif classBuffs then
                selfSlots[1] = { type="label", text="Class Buffs",
                  tooltip="Reminds you when one of your class's own buffs is missing.\nClick the icon to cast it.\nA custom spell or spell group for a ticked buff pauses meanwhile." }
                classIdx = 1
            end
            if #imbueOrder > 2 then
                selfSlots[#selfSlots + 1] = WeaponToggle(imbueLabel,
                    "Reminds you when a weapon has no poison or imbue.\nClick the icon to apply one.", "weaponImbue")
                imbueIdx = #selfSlots
            end
            local sacrificeIdx
            if class == "WARLOCK" then
                selfSlots[#selfSlots + 1] = { type="toggle", text=_G._EABR_SpellName(18788, "Demonic Sacrifice"),
                    tooltip="With the Demonic Sacrifice talent, reminds you when its buff is missing.\nClick the icon to summon the demon, then again to sacrifice it.",
                    getValue=function() local f = FDB(); return f and f.demonicSacrifice == true end,
                    setValue=function(v)
                        local f = FDB(); if not f then return end; f.demonicSacrifice = v
                        RefreshAll()
                        EllesmereUI:RefreshPage()
                    end }
                sacrificeIdx = #selfSlots
            end
            selfSlots[#selfSlots + 1] = { type="toggle", text="Gathering Tracking",
                tooltip="Reminds you when no gathering tracking is on.",
                getValue=function() local f = FDB(); return f and f.gather == true end,
                setValue=function(v)
                    local f = FDB(); if not f then return end; f.gather = v
                    RefreshAll()
                    EllesmereUI:RefreshPage()
                end }
            local gatherIdx = #selfSlots
            selfSlots[#selfSlots + 1] = { type="toggle", text=_G._EABR_SpellName(2481, "Find Treasure"),
                tooltip="Reminds Dwarves when Find Treasure is off.",
                getValue=function() local f = FDB(); return f and f.treasure == true end,
                setValue=function(v)
                    local f = FDB(); if not f then return end; f.treasure = v
                    RefreshAll()
                end }
            local selfRegions = {}
            for i = 1, #selfSlots, 2 do
                local row
                row, h = W:DualRow(parent, y, selfSlots[i], selfSlots[i + 1] or EllesmereUI.BlankRowCfg())
                selfRegions[i], selfRegions[i + 1] = row._leftRegion, row._rightRegion
                y = y - h
            end

            EllesmereUI.BuildInlineCog(selfRegions[gatherIdx], {
                title = "Gathering Tracking",
                disabled = function() local f = FDB(); return not (f and f.gather == true) end,
                disabledTooltip = "Gathering Tracking",
                rows = {
                    { type="toggle", label="Ignore If Class Tracking Is Active",
                      get=function() local f = FDB(); return not f or f.gatherClassTrack ~= false end,
                      set=function(v) local f = FDB(); if f then f.gatherClassTrack = v; RefreshAll() end end },
                },
            })
            if imbueIdx then
                local rows = { HandRow(rogue and "Main Hand Poison" or "Main Hand Imbue", "mhImbue", imbueValues, imbueOrder) }
                if offHand then rows[2] = HandRow(rogue and "Off Hand Poison" or "Off Hand Imbue", "ohImbue", imbueValues, imbueOrder) end
                BuildWeaponCog(selfRegions[imbueIdx], imbueLabel, "weaponImbue", rows)
            end
            if sacrificeIdx then
                local title = _G._EABR_SpellName(18788, "Demonic Sacrifice")
                EllesmereUI.BuildInlineCog(selfRegions[sacrificeIdx], {
                    title = title,
                    disabled = function() local f = FDB(); return not (f and f.demonicSacrifice == true) end,
                    disabledTooltip = title,
                    rows = {
                        { type="dropdown", label="Demon", ddWidth=200,
                          tooltip="Auto: any sacrifice buff counts, and the demon that is out is sacrificed (else the Imp is summoned).",
                          values={ auto = "Auto", imp = "Imp", voidwalker = "Voidwalker", succubus = "Succubus", felhunter = "Felhunter" },
                          order={ "auto", "imp", "voidwalker", "succubus", "felhunter" },
                          get=function() local f = FDB(); return f and f.sacrificeDemon or "auto" end,
                          set=function(v) local f = FDB(); if f then f.sacrificeDemon = v ~= "auto" and v or nil; RefreshAll() end end },
                    },
                })
            end

            -- Class Buffs: one checkbox per buff of the class (ticked: its own
            -- default until picked, EABR.FvClassBuffOn)
            if classBuffs and not EllesmereUI._prebuilding then
                local items, byKey = {}, {}
                for _, b in ipairs(classBuffs) do
                    local text, tip
                    if b.label then
                        local names, seen = {}, {}
                        for _, line in ipairs(b.lines) do
                            for _, id in ipairs({ line[1], line[#line] }) do
                                local n = _G._EABR_SpellName(id)
                                if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
                            end
                        end
                        text, tip = b.menu or b.label, table.concat(names, "\n")
                        if b.own then tip = tip .. "\n\n" .. EllesmereUI.L("Only your own counts.") end
                    else
                        local line = b.lines[1]
                        text = _G._EABR_SpellName(line[#line], b.key)
                    end
                    items[#items + 1] = { key = b.key, label = text, tooltip = tip }
                    byKey[b.key] = b
                end
                if class == "HUNTER" then
                    items[#items + 1] = { key = "hunterTracking", label = "Target Tracking",
                        tooltip = "In combat, shows the tracking that matches your hostile target's creature type." }
                end
                local isOn = _G._EABR_FvClassBuffOn
                local rgn = selfRegions[classIdx]
                local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 170, rgn:GetFrameLevel() + 2, items,
                    function(key)
                        local f = FDB()
                        if key == "hunterTracking" then return f and f.hunterTracking == true end
                        return isOn(byKey[key], f and f.classBuffPicks)
                    end,
                    function(key, v)
                        local f = FDB(); if not f then return end
                        if key == "hunterTracking" then
                            f.hunterTracking = v and true or false
                        else
                            f.classBuffPicks = f.classBuffPicks or {}
                            f.classBuffPicks[key] = v and true or false
                        end
                        RefreshAll()
                    end)
                EllesmereUI.PanelPP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD
                rgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            end

            y = BuildForeverCustomRows(parent, y,
                { type="input", text="Add Custom Spell", inputStyle="popup", placeholder="Spell ID", inputWidth=110,
                  tooltip="Type a spell ID and press Enter to be reminded whenever that buff is missing.\nUnknown IDs are ignored.",
                  getValue=function() return "" end,
                  setValue=function(text)
                      local f = FDB()
                      if not f then return end
                      f.customIDs = f.customIDs or {}
                      AddSpellIDToList(f.customIDs, text)
                  end })
            y = BuildForeverGroupSections(parent, y)

            _, h = W:Spacer(parent, y, 20);  y = y - h
            _, h = W:SectionHeader(parent, SECTION_CONSUMABLES, y);  y = y - h
            _, h = SectionControlRow(parent, y, {
                whereStore = FWhere, whereItems = FOREVER_SECTION_WHERE_ITEMS,
                whereTooltip = "Pick which content the consumable and world buff reminders appear in.\nRested areas (cities and inns) always stay hidden.",
                soundSec = FDB, soundField = "sectionSound",
                onChange = RefreshAll,
            });  y = y - h

            local campRow
            campRow, h = W:DualRow(parent, y,
                { type="toggle", text="Camp Benefits",
                  tooltip="Reminds you when the Camp Benefits campfire buff is missing.",
                  getValue=function() local f = FDB(); return not f or f.camp ~= false end,
                  setValue=function(v)
                      local f = FDB(); if not f then return end; f.camp = v
                      RefreshAll()
                  end },
                { type="toggle", text="Sleeping Bag",
                  tooltip="Reminds you when your Well-Rested buff is missing or under 3 stacks.\nOnly while a Cozy Sleeping Bag is in your bags and you are below max level.\nClick the icon to use it.",
                  getValue=function() local f = FDB(); return f and f.sleepingBag == true end,
                  setValue=function(v)
                      local f = FDB(); if not f then return end; f.sleepingBag = v
                      RefreshAll()
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - h

            local fedRow
            fedRow, h = W:DualRow(parent, y,
                -- The client's own name for the buff (19705, EABR.WELL_FED), so it reads localized.
                { type="toggle", text=_G._EABR_SpellName(19705, "Well Fed"),
                  tooltip="Reminds you when you have no Well Fed buff.\nClick the icon to eat.",
                  getValue=function() local f = FDB(); return f and f.wellFed == true end,
                  setValue=function(v)
                      local f = FDB(); if not f then return end; f.wellFed = v
                      RefreshAll()
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Arcane Censer",
                  tooltip="Reminds you in dungeons when Magical Awareness is missing.\nOnly while an Arcane Censer is in your bags.\nClick the icon to use it.",
                  getValue=function() local f = FDB(); return f and f.arcaneCenser == true end,
                  setValue=function(v)
                      local f = FDB(); if not f then return end; f.arcaneCenser = v
                      RefreshAll()
                  end }
            );  y = y - h

            local scrolls = ScrollsSlot()
            local stonesRow
            stonesRow, h = W:DualRow(parent, y, scrolls,
                WeaponToggle("Weapon Stones and Oils",
                    "Reminds you when a weapon has no stone or oil.\nClick the icon to apply one from your bags.", "weapon"))
            y = y - h
            DressScrollsSlot(stonesRow._leftRegion, class, scrolls)

            EllesmereUI.BuildInlineCog(campRow._rightRegion, {
                title = "Sleeping Bag",
                disabled = function() local f = FDB(); return not (f and f.sleepingBag) end,
                disabledTooltip = "Sleeping Bag",
                rows = {
                    { type="slider", label="Show Below (Minutes)", min=0, max=10, step=1,
                      tooltip="Also reminds you this many minutes before Well-Rested runs out. 0 = off.",
                      get=function() local f = FDB(); return f and f.sleepingBagShowBelow or 0 end,
                      set=function(v) local f = FDB(); if f then f.sleepingBagShowBelow = v > 0 and v or nil; RefreshAll() end end },
                    { type="toggle", label="Show Sleep Timer",
                      tooltip="Counts down to three Well-Rested stacks while you sleep in the bag.",
                      get=function() local f = FDB(); return not f or f.sleepingBagShowProgress ~= false end,
                      set=function(v) local f = FDB(); if f then f.sleepingBagShowProgress = v and true or false; RefreshAll() end end },
                },
            })
            EllesmereUI.BuildInlineCog(fedRow._leftRegion, {
                title = _G._EABR_SpellName(19705, "Well Fed"),
                disabled = function() local f = FDB(); return not (f and f.wellFed) end,
                disabledTooltip = _G._EABR_SpellName(19705, "Well Fed"),
                rows = {
                    { type="slider", label="Show Below (Minutes)", min=0, max=10, step=1,
                      tooltip="Also reminds you this many minutes before Well Fed runs out. 0 = off.",
                      get=function() local f = FDB(); return f and f.wellFedShowBelow or 0 end,
                      set=function(v) local f = FDB(); if f then f.wellFedShowBelow = v > 0 and v or nil; RefreshAll() end end },
                },
            })
            do
                local tempValues, tempOrder = WeaponChoices(false)
                local rows = { HandRow("Main Hand Stone or Oil", "mhTemp", tempValues, tempOrder) }
                if offHand then rows[2] = HandRow("Off Hand Stone or Oil", "ohTemp", tempValues, tempOrder) end
                BuildWeaponCog(stonesRow._rightRegion, "Weapon Stones and Oils", "weapon", rows)
            end

            local elixirs = ElixirsSlot()
            local elixirsRow
            elixirsRow, h = W:DualRow(parent, y, elixirs, EllesmereUI.BlankRowCfg())
            DressElixirsSlot(elixirsRow._leftRegion, class, elixirs)
            y = y - h

            -- No preview header here, so no click-to-scroll mappings to wire.
            return math.abs(y)
        end

        -----------------------------------------------------------------------
        --  AURAS section
        -----------------------------------------------------------------------
        local auraHdr
        auraHdr, h = W:SectionHeader(parent, SECTION_AURAS, y);  y = y - h

        -- Where to Show (+ reminder sound cog)
        _, h = SectionControlRow(parent, y, {
            whereStore = AWhere,
            whereTooltip = "Pick which content these aura reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = ADB, soundField = "sectionSound",
            onChange = RefreshAll,
        });  y = y - h

        -- 4-column checkbox grid for individual auras
        do
            local AURAS = _G._EABR_AURAS or {}
            local gridItems = {}
            for _, aura in ipairs(AURAS) do
                -- Soulstone is a Warlock-specific group utility reminder and
                -- is configured in the Warlock section below.
                if aura.key ~= "soulstone" then
                    gridItems[#gridItems+1] = {
                        label = _G._EABR_SpellName(aura.castSpell, aura.name),
                        classToken = aura.class,
                        key = aura.key,
                        tooltip = (aura.combatOnly and aura.isStance) and "Shows in combat only, while you are out of this form." or nil,
                        getVal = function() local a = ADB(); return a and a.enabled and a.enabled[aura.key] end,
                        setVal = function(v) local a = ADB(); if a and a.enabled then a.enabled[aura.key] = v end end,
                    }
                end
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                if _G._EABR_UpdateGroupAuraRegistration then _G._EABR_UpdateGroupAuraRegistration() end
                RefreshAll(); RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  ROGUE POISONS sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ROGUE, y);  y = y - h
        _, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("ROGUE"),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB, specialClass = "ROGUE",
            onChange = RefreshAll,
        });  y = y - h

        do
            local POISONS = _G._EABR_ROGUE_POISONS or {}
            local gridItems = {}
            for _, poison in ipairs(POISONS) do
                gridItems[#gridItems+1] = {
                    label = _G._EABR_SpellName(poison.castSpell, poison.name),
                    classToken = "ROGUE",
                    key = poison.key,
                    getVal = function() local c = CDB(); return c and c.enabled and c.enabled[poison.key] end,
                    setVal = function(v) local c = CDB(); if c and c.enabled then c.enabled[poison.key] = v end end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function() RefreshAll(); RebuildPreviewHeader() end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  PALADIN RITES sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_PALADIN, y);  y = y - h
        _, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("PALADIN"),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB, specialClass = "PALADIN",
            onChange = RefreshAll,
        });  y = y - h

        do
            local RITES = _G._EABR_PALADIN_RITES or {}
            local gridItems = {}
            for _, rite in ipairs(RITES) do
                gridItems[#gridItems+1] = {
                    label = _G._EABR_SpellName(rite.castSpell, rite.name),
                    classToken = "PALADIN",
                    key = rite.key,
                    getVal = function() local c = CDB(); return c and c.enabled and c.enabled[rite.key] end,
                    setVal = function(v) local c = CDB(); if c and c.enabled then c.enabled[rite.key] = v end end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function() RefreshAll(); RebuildPreviewHeader() end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  SHAMAN IMBUES & SHIELDS sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_SHAMAN, y);  y = y - h
        _, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("SHAMAN"),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB, specialClass = "SHAMAN",
            onChange = RefreshAll,
        });  y = y - h

        do
            local gridItems = {}
            local IMBUES = _G._EABR_SHAMAN_IMBUES or {}
            for _, imbue in ipairs(IMBUES) do
                gridItems[#gridItems+1] = {
                    label = _G._EABR_SpellName(imbue.castSpell, imbue.name),
                    classToken = "SHAMAN",
                    key = imbue.key,
                    getVal = function() local c = CDB(); return c and c.enabled and c.enabled[imbue.key] end,
                    setVal = function(v) local c = CDB(); if c and c.enabled then c.enabled[imbue.key] = v end end,
                }
            end
            local SHIELDS = _G._EABR_SHAMAN_SHIELDS or {}
            for _, shield in ipairs(SHIELDS) do
                gridItems[#gridItems+1] = {
                    label = EllesmereUI.L(shield.name),
                    classToken = "SHAMAN",
                    key = shield.key,
                    tooltip = shield.key == "es_ally"
                        and "Out of combat, reminds you when no groupmate has your Earth Shield (Elemental Orbit)."
                        or nil,
                    getVal = function() local c = CDB(); return c and c.enabled and c.enabled[shield.key] end,
                    setVal = function(v) local c = CDB(); if c and c.enabled then c.enabled[shield.key] = v end end,
                }
            end
            -- Earth Shield (Ally) turns group tracking on or off.
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                if _G._EABR_UpdateGroupAuraRegistration then _G._EABR_UpdateGroupAuraRegistration() end
                RefreshAll(); RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  PETS section
        -----------------------------------------------------------------------
        local petHdr
        petHdr, h = W:SectionHeader(parent, "PETS", y);  y = y - h

        local petFirstRow
        petFirstRow, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("PET"),
            whereTooltip = "Pick which content the Missing Pet and Passive Pet reminders appear in.\nWarlock's Wrong Demon reminder uses the Where to Show in the Warlock section.\nRested areas (cities and inns) always stay hidden.",
            onChange = RefreshAll,
            rightCfg = { type="toggle", text="Missing Pet",
              tooltip="Show a reminder when you don't have an active pet summoned. Only applies to pet classes (Hunter, Warlock, Death Knight, Mage).",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.pet ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.pet = v; RefreshAll(); RebuildPreviewHeader() end end },
        });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Passive Pet",
              tooltip="Show a reminder when your active pet is set to Passive stance. Only applies to pet classes (Hunter, Warlock, Death Knight, Mage).",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.pet_passive ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.pet_passive = v; RefreshAll(); RebuildPreviewHeader() end end },
            EllesmereUI.BlankRowCfg()
        );  y = y - h

        _eabrClickMappings.pet = { section = petHdr, target = petFirstRow }

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  WARLOCK section
        -----------------------------------------------------------------------
        local warlockHdr
        warlockHdr, h = W:SectionHeader(parent, SECTION_WARLOCK, y);  y = y - h

        -- Where to Show | Allowed Demons, then Wrong Demon | Soulstone.
        local warlockCtrlRow
        warlockCtrlRow, h = SectionControlRow(parent, y, {
            whereStore = CWarlockWhere,
            whereTooltip = "Pick which content these Warlock reminders appear in.\nMissing Pet and Passive Pet use the Where to Show in the Pets section.\nRested areas (cities and inns) always stay hidden.",
            onChange = RefreshAll,
            rightCfg = { type="dropdown", text="Allowed Demons",
              tooltip="Pick which demons count as correct for Wrong Demon. A demon only counts while its summon spell is known; with none picked (or everything picked), the reminder never fires.",
              values={ _placeholder="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end, setValue=function() end },
        });  y = y - h

        local WARLOCK_PET_ITEMS = {}
        for _, pet in ipairs(_G._EABR_WARLOCK_PETS or {}) do
            local unlearned = function() return not (_G._EABR_Known and _G._EABR_Known(pet.castSpell)) end
            WARLOCK_PET_ITEMS[#WARLOCK_PET_ITEMS+1] = {
                key = pet.key, label = pet.name,
                lockedFn = unlearned,
                excludeFromSummaryFn = unlearned,
                lockedTooltip = function()
                    local spellName = _G._EABR_SpellName and _G._EABR_SpellName(pet.castSpell, pet.name) or pet.name
                    return EllesmereUI.Lf("You have not learned %1$s.", spellName)
                end,
            }
        end
        local warlockRow
        warlockRow, h = W:DualRow(parent, y,
            { type="toggle", text="Wrong Demon",
              tooltip="Show a reminder when your Warlock's active pet isn't one of the demons picked in Allowed Demons. A demon only counts while its summon spell is known, so leaving only Felguard picked stays silent for specs/builds that haven't talented Summon Felguard.",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.wrong_pet ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.wrong_pet = v; RefreshAll(); RebuildPreviewHeader() end end },
            { type="toggle", text=_G._EABR_SpellName(20707, "Soulstone"),
              tooltip="Show a reminder until your own Soulstone is active on you or another group member.",
              getValue=function() local a = ADB(); return a and a.enabled and a.enabled.soulstone ~= false end,
              setValue=function(v)
                  local a = ADB()
                  if a and a.enabled then a.enabled.soulstone = v end
                  if _G._EABR_UpdateGroupAuraRegistration then _G._EABR_UpdateGroupAuraRegistration() end
                  RefreshAll(); RebuildPreviewHeader()
              end }
        );  y = y - h

        local wcc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.WARLOCK
        if wcc then
            if warlockCtrlRow._rightRegion._label then warlockCtrlRow._rightRegion._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1) end
            if warlockRow._leftRegion._label then warlockRow._leftRegion._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1) end
            if warlockRow._rightRegion._label then warlockRow._rightRegion._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1) end
        end

        if not EllesmereUI._prebuilding then
            local rrgn = warlockCtrlRow._rightRegion
            if rrgn._control then rrgn._control:Hide() end
            local petDD, petDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rrgn, 220, rrgn:GetFrameLevel() + 2, WARLOCK_PET_ITEMS,
                function(k) local c = CDB(); return c and c.wrongPetAllowed and c.wrongPetAllowed[k] end,
                function(k, v)
                    local c = CDB()
                    if c then
                        c.wrongPetAllowed = c.wrongPetAllowed or {}
                        c.wrongPetAllowed[k] = v
                    end
                    RefreshAll(); RebuildPreviewHeader()
                end,
                nil, nil, nil, nil, nil, { emptyLabel = "All" })
            PP.Point(petDD, "RIGHT", rrgn, "RIGHT", -20, 0)
            rrgn._control = petDD
            rrgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(petDDRefresh)
        end

        _eabrClickMappings.warlock_demons = { section = warlockHdr, target = warlockRow }

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  CONSUMABLES section
        -----------------------------------------------------------------------
        local consumHdr
        consumHdr, h = W:SectionHeader(parent, SECTION_CONSUMABLES, y);  y = y - h

        -- Where to Show (+ reminder sound cog)
        _, h = SectionControlRow(parent, y, {
            whereStore = CWhere,
            whereTooltip = "Pick which content these consumable reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = CDB, soundField = "sectionSound",
            onChange = RefreshAll,
        });  y = y - h

        -- Flask toggle | Preferred Click to Buff dropdown
        local consumFirstRow
        local flaskRow
        do
            local FLASK_ITEMS = _G._EABR_FLASK_ITEMS or {}
            local flaskValues = { last_used = "Last Used" }
            local flaskOrder = { "last_used" }
            for _, f in ipairs(FLASK_ITEMS) do
                flaskValues[f.key] = f.name
                flaskOrder[#flaskOrder+1] = f.key
            end
            flaskRow, h = W:DualRow(parent, y,
                { type="toggle", text="Flask",
                  getValue=function() local c = CDB(); return c and c.enabled and c.enabled.flask end,
                  setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.flask = v; RefreshAll(); RebuildPreviewHeader() end end },
                { type="dropdown", text="Preferred (Click to Buff)", dropdownWidth=220,
                  values=flaskValues, order=flaskOrder,
                  getValue=function() local c = CDB(); return c and c.preferredFlask or "last_used" end,
                  setValue=function(v) local c = CDB(); if c then c.preferredFlask = v; RefreshAll() end end }
            );  y = y - h
            consumFirstRow = flaskRow
        end

        -- Food toggle | Preferred Click to Buff dropdown
        local foodRow
        do
            local FOOD_ITEMS = _G._EABR_FOOD_ITEMS or {}
            local foodValues = { last_used = "Last Used" }
            local foodOrder = { "last_used" }
            for _, f in ipairs(FOOD_ITEMS) do
                foodValues[f.key] = f.name
                foodOrder[#foodOrder+1] = f.key
            end
            foodRow, h = W:DualRow(parent, y,
                { type="toggle", text="Food",
                  getValue=function() local c = CDB(); return c and c.enabled and c.enabled.food end,
                  setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.food = v; RefreshAll(); RebuildPreviewHeader() end end },
                { type="dropdown", text="Preferred (Click to Buff)", dropdownWidth=220,
                  values=foodValues, order=foodOrder,
                  getValue=function() local c = CDB(); return c and c.preferredFood or "last_used" end,
                  setValue=function(v) local c = CDB(); if c then c.preferredFood = v; RefreshAll() end end }
            );  y = y - h
        end

        -- Weapon Enhancement toggle | Preferred Click to Buff dropdown
        local weaponEnchantRow
        do
            local WE_CHOICES = _G._EABR_WEAPON_ENCHANT_CHOICES or {}
            local weValues = { last_used = "Last Used" }
            local weOrder = { "last_used" }
            for _, we in ipairs(WE_CHOICES) do
                weValues[we.key] = we.name
                weOrder[#weOrder+1] = we.key
            end
            weaponEnchantRow, h = W:DualRow(parent, y,
                { type="toggle", text="Weapon Enhancement",
                  getValue=function() local c = CDB(); return c and c.enabled and c.enabled.weapon_enchant end,
                  setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.weapon_enchant = v; RefreshAll(); RebuildPreviewHeader() end end },
                { type="dropdown", text="Preferred (Click to Buff)", dropdownWidth=220,
                  values=weValues, order=weOrder,
                  getValue=function() local c = CDB(); return c and c.preferredWeaponEnchant or "last_used" end,
                  setValue=function(v) local c = CDB(); if c then c.preferredWeaponEnchant = v; RefreshAll() end end }
            );  y = y - h
        end

        -- Augment Rune | Healthstone (neither has a per-item control)
        local runeRow
        runeRow, h = W:DualRow(parent, y,
            { type="toggle", text="Augment Rune",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.augment_rune end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.augment_rune = v; RefreshAll(); RebuildPreviewHeader() end end },
            { type="toggle", text="Healthstone",
              tooltip="Remind you to grab a Healthstone when a Warlock is in your group.",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.healthstone ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.healthstone = v; RefreshAll(); RebuildPreviewHeader() end end }
        );  y = y - h
        local healthstoneRow = runeRow

        -- Inky Black Potion | Choose Zones (inline on the right)
        local inkyRow
        inkyRow, h = W:DualRow(parent, y,
            { type="toggle", text="Inky Black Potion",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.inky_black end,
              setValue=function(v)
                  local c = CDB(); if c and c.enabled then c.enabled.inky_black = v; RefreshAll(); RebuildPreviewHeader() end
                  EllesmereUI:RefreshPage()
              end },
            { type="label", text="" }
        );  y = y - h
        row = inkyRow

        -- Inline "Choose Zones" button on the right region (Inky Black)
        if not EllesmereUI._prebuilding then
            local rgn = row._rightRegion
            local eg = EllesmereUI.ELLESMERE_GREEN or {r=0, g=0.82, b=0.62}
            local lerp = EllesmereUI.lerp
            local DARK_BG = EllesmereUI.DARK_BG

            local zoneBtn = CreateFrame("Button", nil, rgn)
            zoneBtn:SetSize(110, 24)
            -- Anchored to the REGION edge, never the slot control: this slot
            -- is an empty label, and anchoring to it while the deferred label
            -- clamp anchors the label back to _lastInline forms an anchor
            -- family cycle (hard client error).
            zoneBtn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
            zoneBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            rgn._lastInline = zoneBtn

            local zoneBg = EllesmereUI.SolidTex(zoneBtn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
            zoneBg:SetAllPoints()
            local zoneBrd = EllesmereUI.MakeRoundedBorder(zoneBtn, 1, 1, 1, 0.3, zoneBg)
            local zoneLbl = EllesmereUI.MakeFont(zoneBtn, 12, nil, 1, 1, 1)
            zoneLbl:SetPoint("CENTER")
            zoneLbl:SetText(EllesmereUI.L("Choose Zones"))

            -- Hover animation
            do
                local FADE_DUR = 0.1
                local progress, target = 0, 0
                local function Apply(t)
                    zoneLbl:SetTextColor(1, 1, 1, lerp(0.5, 0.8, t))
                    zoneBrd:SetColor(1, 1, 1, lerp(0.3, 0.5, t))
                end
                local function OnUpdate(self, elapsed)
                    local dir = (target == 1) and 1 or -1
                    progress = progress + dir * (elapsed / FADE_DUR)
                    if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                        progress = target; self:SetScript("OnUpdate", nil)
                    end
                    Apply(progress)
                end
                zoneBtn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
                zoneBtn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
            end

            zoneBtn:SetScript("OnClick", function()
                local c = CDB()
                local current = c and c.inkyBlackZones or ""
                EllesmereUI:ShowInputPopup({
                    title = "Inky Black Potion Zone IDs",
                    message = "Enter map zone IDs separated by commas.\nThe potion reminder will only show in these zones.",
                    placeholder = "e.g. 2248, 2339",
                    initialText = current,
                    maxLetters = 500,
                    confirmText = "Save",
                    extraButton = {
                        text = "Add Current Zone",
                        onClick = function(editBox)
                            local mapID = C_Map.GetBestMapForUnit("player")
                            if not mapID then return end
                            local txt = editBox:GetText() or ""
                            local idStr = tostring(mapID)
                            if txt == "" then
                                editBox:SetText(idStr)
                            else
                                editBox:SetText(txt .. ", " .. idStr)
                            end
                        end,
                    },
                    onConfirm = function(text)
                        local cc = CDB(); if cc then cc.inkyBlackZones = text or ""; RefreshAll() end
                    end,
                })
            end)

            -- Disabled overlay when Inky Black Potion is off
            local blockFrame = CreateFrame("Frame", nil, zoneBtn)
            blockFrame:SetAllPoints()
            blockFrame:SetFrameLevel(zoneBtn:GetFrameLevel() + 10)
            blockFrame:EnableMouse(true)
            blockFrame:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(zoneBtn, EllesmereUI.DisabledTooltip("Inky Black Potion"))
            end)
            blockFrame:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateZoneBtnDisabled()
                local c = CDB()
                local off = not c or not c.enabled or not c.enabled.inky_black
                if off then
                    zoneBtn:SetAlpha(0.3)
                    blockFrame:Show()
                else
                    zoneBtn:SetAlpha(1)
                    blockFrame:Hide()
                end
            end
            UpdateZoneBtnDisabled()
            EllesmereUI.RegisterWidgetRefresh(UpdateZoneBtnDisabled)
        end

        -- Show Without Item in Bags | Ready Check Mana Warning (eye | swatch | cog inline)
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Without Item in Bags",
              tooltip="When on, augment rune/flask/food/weapon reminders still show (dimmed) when you have no matching item in your bags, as a prompt to restock.\nWhen off, they are hidden entirely if you don't carry the item.",
              getValue=function() local c = CDB(); return not c or c.showWithoutItem ~= false end,
              setValue=function(v) local c = CDB(); if c then c.showWithoutItem = v; RefreshAll() end end },
            { type="toggle", text="Ready Check Mana Warning",
              tooltip="Flashes LOW MANA during an out-of-combat raid ready check while you are a healer under 80% mana.",
              getValue=function() local c = CDB(); return not c or c.rcManaWarn ~= false end,
              setValue=function(v)
                  local c = CDB(); if c then c.rcManaWarn = v end
                  if not v and _G._EABR_RCWarnHidePreview then _G._EABR_RCWarnHidePreview() end
                  if _G._EABR_RCWarnUpdateReg then _G._EABR_RCWarnUpdateReg() end
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline: eyeball | color swatch | cog on the mana warning toggle
        do
            local leftRgn = row._rightRegion
            local function rcwOff()
                local c = CDB()
                return c ~= nil and c.rcManaWarn == false
            end
            local rcwPreviewShown = false
            local RefreshRcwEye  -- assigned below; cog offset sliders flip the eye on

            -- Cog (rightmost inline, closest to toggle): Text Size + X/Y Offset.
            -- Offset edits force the preview on (and light the eye) so the
            -- warning is visible while moving it.
            local function ShowPreviewFromCog()
                rcwPreviewShown = true
                if RefreshRcwEye then RefreshRcwEye() end
                if _G._EABR_RCWarnPreview then _G._EABR_RCWarnPreview() end
            end
            leftRgn._rcwFontValues, leftRgn._rcwFontOrder = EllesmereUI.BuildFontDropdownData()
            EllesmereUI.BuildInlineCog(leftRgn, {
                title = "Mana Warning Settings",
                disabled = rcwOff,
                disabledTooltip = "Ready Check Mana Warning",
                rows = {
                    { type="dropdown", label="Mana Warning Font",
                      values=leftRgn._rcwFontValues, order=leftRgn._rcwFontOrder,
                      get=function() local c = CDB(); return (c and c.rcManaWarnFont) or "__global" end,
                      set=function(v)
                          local c = CDB(); if not c then return end
                          c.rcManaWarnFont = (v ~= "__global") and v or nil
                          if _G._EABR_RCWarnApply then _G._EABR_RCWarnApply() end
                          ShowPreviewFromCog()
                      end },
                    { type="slider", label="Text Size", min=10, max=72, step=1,
                      get=function() local c = CDB(); return c and c.rcManaWarnSize or 48 end,
                      set=function(v) local c = CDB(); if not c then return end; c.rcManaWarnSize = v
                          if _G._EABR_RCWarnApply then _G._EABR_RCWarnApply() end end },
                    { type="slider", label="X Offset", min=-600, max=600, step=1,
                      get=function() local c = CDB(); return c and c.rcManaWarnX or 0 end,
                      set=function(v) local c = CDB(); if not c then return end; c.rcManaWarnX = v
                          ShowPreviewFromCog() end },
                    { type="slider", label="Y Offset", min=-600, max=600, step=1,
                      get=function() local c = CDB(); return c and c.rcManaWarnY or 0 end,
                      set=function(v) local c = CDB(); if not c then return end; c.rcManaWarnY = v
                          ShowPreviewFromCog() end },
                },
            })

            if not EllesmereUI._prebuilding then
                -- Color swatch (left of the cog). Default shows the brightened
                -- mana color the warning uses when no custom is set.
                local swatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
                    function()
                        local c = CDB()
                        local col = c and c.rcManaWarnColor
                        if col then return col.r, col.g, col.b, 1 end
                        local mc = EllesmereUI.GetPowerColor("MANA")
                        if mc then
                            return math.min(mc.r * 1.5, 1), math.min(mc.g * 1.5, 1), math.min(mc.b * 1.5, 1), 1
                        end
                        return 0, 0.825, 1, 1
                    end,
                    function(r, g, b)
                        local c = CDB(); if not c then return end
                        c.rcManaWarnColor = { r = r, g = g, b = b }
                        if _G._EABR_RCWarnApply then _G._EABR_RCWarnApply() end
                    end, false, 20)
                swatch:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
                leftRgn._lastInline = swatch

                local swatchBlock = CreateFrame("Frame", nil, swatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                swatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Ready Check Mana Warning"))
                end)
                swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Eye icon toggles a live preview (left of the swatch)
                local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
                local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
                local eyeBtn = CreateFrame("Button", nil, leftRgn)
                eyeBtn:SetSize(26, 26)
                eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
                leftRgn._lastInline = eyeBtn
                eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                EllesmereUI.SetGlyphAlpha(eyeBtn, 0.4)
                local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                eyeTex:SetAllPoints()
                RefreshRcwEye = function()
                    eyeTex:SetTexture(rcwPreviewShown and EYE_INVISIBLE or EYE_VISIBLE)
                end
                RefreshRcwEye()
                eyeBtn:SetScript("OnEnter", function(self)
                    EllesmereUI.SetGlyphAlpha(self, 0.7)
                    EllesmereUI.ShowWidgetTooltip(self, "Preview mana warning")
                end)
                eyeBtn:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                    EllesmereUI.SetGlyphAlpha(self, 0.4)
                end)
                eyeBtn:SetScript("OnClick", function()
                    rcwPreviewShown = not rcwPreviewShown
                    RefreshRcwEye()
                    if rcwPreviewShown then
                        if _G._EABR_RCWarnPreview then _G._EABR_RCWarnPreview() end
                    else
                        if _G._EABR_RCWarnHidePreview then _G._EABR_RCWarnHidePreview() end
                    end
                end)

                local eyeBlock = CreateFrame("Frame", nil, eyeBtn)
                eyeBlock:SetAllPoints()
                eyeBlock:SetFrameLevel(eyeBtn:GetFrameLevel() + 10)
                eyeBlock:EnableMouse(true)
                eyeBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(eyeBtn, EllesmereUI.DisabledTooltip("Ready Check Mana Warning"))
                end)
                eyeBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Shared disabled-state refresh for all three inlines
                local function UpdateRcwInlinesDisabled()
                    local off = rcwOff()
                    if off then
                        rcwPreviewShown = false
                        RefreshRcwEye()
                        swatch:SetAlpha(0.3);  swatchBlock:Show()
                        EllesmereUI.SetGlyphAlpha(eyeBtn, 0.15); eyeBlock:Show()
                    else
                        swatch:SetAlpha(1)
                        swatchBlock:Hide()
                        EllesmereUI.SetGlyphAlpha(eyeBtn, 0.4); eyeBlock:Hide()
                    end
                end
                UpdateRcwInlinesDisabled()
                EllesmereUI.RegisterWidgetRefresh(UpdateRcwInlinesDisabled)
            end
        end

        -- Wire up click mappings for preview hit overlays.
        wipe(_eabrClickMappings)
        _eabrClickMappings.display = { section = displaySection, target = borderRow }
        _eabrClickMappings.showText = { section = displaySection, target = rowText }
        _eabrClickMappings.raidbuff = { section = raidBufHdr, target = raidBufHdr }
        _eabrClickMappings.aura = { section = auraHdr, target = auraHdr }
        _eabrClickMappings.consumable = { section = consumHdr, target = consumFirstRow }
        _eabrClickMappings["item:soulstone"] = { section = warlockHdr, target = warlockRow }

        -- Per-item mappings: grid cells for individual raid buffs / auras
        for k, cell in pairs(_gridCellRefs) do
            _eabrClickMappings["item:" .. k] = { section = cell, target = cell }
        end
        -- Per-item mappings: consumable toggle rows
        if flaskRow then _eabrClickMappings["item:flask"] = { section = flaskRow, target = flaskRow } end
        if foodRow then _eabrClickMappings["item:food"] = { section = foodRow, target = foodRow } end
        if weaponEnchantRow then _eabrClickMappings["item:weapon_enchant"] = { section = weaponEnchantRow, target = weaponEnchantRow } end
        if runeRow then _eabrClickMappings["item:augment_rune"] = { section = runeRow, target = runeRow } end
        if healthstoneRow then _eabrClickMappings["item:healthstone"] = { section = healthstoneRow, target = healthstoneRow } end
        if inkyRow then _eabrClickMappings["item:inky_black"] = { section = inkyRow, target = inkyRow } end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Talent Reminders Page
    ---------------------------------------------------------------------------
    -- Which Active Reminders cards are open (spec ID, "class:<CLASS>" or
    -- "any" -> true), for the session.
    local _trCardOpen = {}

    -- The share strings, one table (the page closure is near Lua's local
    -- cap). A share string is EllesmereUI.EncodeShareString with tag "TR"
    -- over { v = 2, r = { { s = spellID, n = spellName, a = { activity, ... },
    -- x = { Not Needed activity, ... }, c = class, p = specID }, ... } }. A
    -- first-version string names zones (z) and the Not Needed choice (m),
    -- read as a reminder saved with them is (ns.TRActs).
    local TRShare = { TAG = "TR", V = 2, MAX = 500 }

    -- A change to the reminder list the tab did not make (the runtime splits
    -- a class-wide reminder into one per spec): the tab's rows and cards hold
    -- reminders, so it builds again where it shows, or as it is next shown
    -- from the page cache (TRShare.listStale, onPageCacheRestore).
    ns.TR_ListChanged = function()
        if EllesmereUI:GetActiveModule() == "EllesmereUIAuraBuffReminders"
            and EllesmereUI:GetActivePage() == PAGE_TALENTS then
            EllesmereUI:RefreshPage(true)
        else
            TRShare.listStale = true
        end
    end

    -- The share string of these reminders.
    function TRShare.Export(reminders)
        local A, keys = ns.TRActs, ns.ActivityKeys()
        local out = {}
        for _, r in ipairs(reminders) do
            if r.spellID then
                local a, x = {}, {}
                for _, k in ipairs(keys) do
                    if A.Has(r, k) then a[#a + 1] = k
                    elseif A.NotNeededHas(r, k) then x[#x + 1] = k end
                end
                out[#out + 1] = { s = r.spellID, n = r.spellName, a = a, x = x, c = r.class, p = r.specID }
            end
        end
        return EllesmereUI.EncodeShareString(TRShare.TAG, { v = TRShare.V, r = out })
    end
    function TRShare.ShowExport(reminders)
        local str = TRShare.Export(reminders)
        if not str then return end
        EllesmereUI:ShowCopyPopup(EllesmereUI.L("Export Talent Reminders"),
            EllesmereUI.L("Copy the string below and share it"), str, { keep = "talentReminders" })
    end

    -- One entry of a share string as a reminder of this season, or nil: a
    -- talent that exists, a spec the game knows (its class read from it) or
    -- a class token or neither, and at least one activity the checklist
    -- lists now (valid: a set of them). v: the string's version.
    function TRShare.Entry(e, valid, v)
        if type(e) ~= "table" then return end
        local s = e.s
        if type(s) ~= "number" or s <= 0 or s >= 2147483648 or s ~= math.floor(s) then return end
        if C_Spell.DoesSpellExist and not C_Spell.DoesSpellExist(s) then return end
        local spec, class = e.p, e.c
        if spec ~= nil then
            if type(spec) ~= "number" or spec ~= math.floor(spec) then return end
            class = nil
            if GetSpecializationInfoByID then class = select(6, GetSpecializationInfoByID(spec)) end
            if not class then return end
        elseif class ~= nil then
            if type(class) ~= "string" or not (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) then return end
        end
        local A, acts, nn = ns.TRActs, {}, {}
        if v == 1 then
            -- Zones and the Not Needed choice, as a reminder saved with them reads.
            for _, zn in ipairs(type(e.z) == "table" and e.z or {}) do
                local za = type(zn) == "string" and A.ZoneActs(zn)
                if za then
                    for k in pairs(za) do
                        if valid[k] then acts[k] = true end
                    end
                end
            end
            local old = { notNeededMode = (e.m == "season" or e.m == "all") and e.m or "never" }
            for k in pairs(valid) do
                if not acts[k] and A.NotNeededHas(old, k) then nn[k] = true end
            end
        else
            for _, k in ipairs(type(e.a) == "table" and e.a or {}) do
                if type(k) == "string" and valid[k] then acts[k] = true end
            end
            for _, k in ipairs(type(e.x) == "table" and e.x or {}) do
                if type(k) == "string" and valid[k] and not acts[k] then nn[k] = true end
            end
        end
        if not next(acts) then return end
        local name = C_Spell.GetSpellName(s)
        if not name and type(e.n) == "string" and #e.n <= 100 then name = e.n end
        return { acts = acts, notNeededActs = nn, spellID = s, spellName = name,
            class = class, specID = spec, talentSource = spec and "spec" or nil }
    end

    -- Imports a share string: each talent already reminded for that spec
    -- takes the string's activities it lacks (as Add Reminder merges), every
    -- other one is added.
    function TRShare.Import(str)
        local data = EllesmereUI.DecodeShareString(TRShare.TAG, str)
        if not data or type(data.r) ~= "table" or (data.v ~= 1 and data.v ~= TRShare.V) then
            local newer = data and type(data.v) == "number" and data.v > TRShare.V
            EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Talent Reminders"),
                content = newer
                    and EllesmereUI.L("This string was made by a newer version of EllesmereUI. Please update your addon.")
                    or EllesmereUI.L("This is not a Talent Reminders string. Make sure you copied the whole string.") })
            return
        end
        local p = DB()
        if not p then return end
        if not p.talentReminders then p.talentReminders = {} end
        local list = p.talentReminders
        local valid = {}
        for _, k in ipairs(ns.ActivityKeys()) do valid[k] = true end
        local added, updated, skipped = 0, 0, 0
        for i, e in ipairs(data.r) do
            if i > TRShare.MAX then break end
            local new = TRShare.Entry(e, valid, data.v)
            if not new then
                skipped = skipped + 1
            else
                local held
                for _, r in ipairs(list) do
                    if r.spellID == new.spellID and r.specID == new.specID
                        and (r.class == nil or r.class == new.class) then
                        held = r
                        break
                    end
                end
                if held then
                    local acts, grew = ns.TRActs.Edit(held), false
                    for k in pairs(new.acts) do
                        if not acts[k] then
                            acts[k] = true
                            grew = true
                            -- an activity of its own is no Not Needed one
                            if type(held.notNeededActs) == "table" then held.notNeededActs[k] = nil end
                        end
                    end
                    if grew then updated = updated + 1 end
                else
                    list[#list + 1] = new
                    added = added + 1
                end
            end
        end
        if added + updated == 0 then
            EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Talent Reminders"),
                content = EllesmereUI.L("Nothing new to import: these reminders are here already, or their activities are not in this season.") })
            return
        end
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "
            .. EllesmereUI.Lf("Talent Reminders: %1$d added, %2$d updated, %3$d skipped.", added, updated, skipped))
        if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
        EllesmereUI:RefreshPage(true)
    end
    function TRShare.ShowImport()
        EllesmereUI:ShowImportPopup(TRShare.Import, EllesmereUI.L("Import Talent Reminders"),
            EllesmereUI.L("Paste a Talent Reminders string below"),
            { confirmLabel = "Import", rawPaste = true, keep = "talentReminders" })
    end

    local function BuildTalentRemindersPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        -- The index pass needs only the page's one section; the form and its
        -- talent tree scan are built live.
        if EllesmereUI._prebuilding then
            W:SectionHeader(parent, "ACTIVE REMINDERS", yOffset)
            return 0
        end
        TRShare.listStale = false
        local y = yOffset
        local _, h
        local fontPath = (EllesmereUI.GetFontPath("auraBuff"))
            or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\EUI Highway.ttf"

        parent._showRowDivider = true

        -- State for the add-reminder form: the picked activities, the talent
        local selectedActs = {}
        local selectedTalentSpellID = nil
        local selectedTalentName = nil

        -- A reminder's activities and where its Not Needed reminder shows
        -- (the runtime's view: ns.TRActs), and every activity the shared
        -- checklist lists (the Loadout Manager tab's).
        local TRActs, ActivityKeys = ns.TRActs, ns.ActivityKeys
        local DUNGEON_TIP = "On Mythic, before the key starts. Normal and Heroic runs show no reminder."

        -----------------------------------------------------------------------
        --  SECTION: ADD REMINDER (no header clean layout)
        -----------------------------------------------------------------------

        -- The Activities checklist (the Loadout Manager tab's, shared) and the
        -- talent dropdown side by side on one row, centred as a pair, no
        -- labels; Add Reminder under them.
        local CONTENT_PAD = 45
        local FORM_DD_H = 38
        local DD_GAP = 12  -- between the two dropdowns
        y = y - 30  -- 30px space above the dropdowns
        local FORM_ROW_H = FORM_DD_H + 12
        local formRow = CreateFrame("Frame", nil, parent)
        local formRowW = parent:GetWidth() - CONTENT_PAD * 2
        PP.Size(formRow, formRowW, FORM_ROW_H)
        PP.Point(formRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        -- Each 350 wide, narrower when the row cannot hold two.
        local FORM_DD_W = math.min(350, math.floor((formRowW - DD_GAP) / 2))
        local ddStartX = math.floor((formRowW - (FORM_DD_W * 2 + DD_GAP)) / 2)
        local actDD, actRefresh = ns.BuildActivityChecklist(formRow, FORM_DD_W, formRow:GetFrameLevel() + 2, {
            get = function(key) return selectedActs[key] == true end,
            set = function(key, on) selectedActs[key] = on or nil end,
            mplusTip = DUNGEON_TIP,
        })
        PP.Size(actDD, FORM_DD_W, FORM_DD_H)
        PP.Point(actDD, "TOPLEFT", formRow, "TOPLEFT", ddStartX, 0)
        actDD._ttText = "The activities this reminder shows in while you do not have the talent."

        -- The talent button, beside the activities at their size: the add form's
        -- dropdown look, and a click opens the shared talent picker (the
        -- Cooldown Manager's Talent Conditions popup, in its pick mode: your
        -- class tree and spec tree, a click picks the talent).
        local TALENT_DD_W = FORM_DD_W
        local TALENT_DD_H = FORM_DD_H

        local function MakeTalentButton(parentRow, xOff)
            local btn = CreateFrame("Button", nil, parentRow)
            PP.Size(btn, TALENT_DD_W, TALENT_DD_H)
            PP.Point(btn, "TOPLEFT", parentRow, "TOPLEFT", xOff, 0)
            btn:SetFrameLevel(parentRow:GetFrameLevel() + 1)
            local btnBg = btn:CreateTexture(nil, "BACKGROUND")
            btnBg:SetAllPoints()
            btnBg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
            EllesmereUI.MakeRoundedBorder(btn, 1, 1, 1, 0.20, btnBg)
            local btnLbl = btn:CreateFontString(nil, "OVERLAY")
            btnLbl:SetFont(fontPath, 13, GetABROptOutline())
            btnLbl:SetTextColor(1, 1, 1, 0.50)
            btnLbl:SetMaxLines(1)
            btnLbl:SetJustifyH("LEFT")
            btnLbl:SetWordWrap(false)
            btnLbl:SetText(EllesmereUI.L("Select a talent..."))
            local arrow = EllesmereUI.MakeDropdownArrow(btn, 14, EllesmereUI.PanelPP)
            btnLbl:SetPoint("LEFT", btn, "LEFT", 14, 0)
            btnLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
            btn:SetScript("OnEnter", function() btnBg:SetColorTexture(0.128, 0.120, 0.113, 1) end)
            btn:SetScript("OnLeave", function() btnBg:SetColorTexture(0.103, 0.095, 0.088, 0.9) end)
            btn:SetScript("OnClick", function()
                EllesmereUI.ShowTalentConditionsPopup({
                    title = EllesmereUI.L("Select a Talent"),
                    texts = { hint = EllesmereUI.L("Click the talent this reminder is for."), none = "" },
                    fontKey = "auraBuff",
                    pick = { spellID = selectedTalentSpellID, onPick = function(t)
                        local name = C_Spell.GetSpellName(t.spellID)
                        selectedTalentSpellID = t.spellID
                        selectedTalentName = name
                        btnLbl:SetText(name or EllesmereUI.L("Unknown"))
                        btnLbl:SetTextColor(1, 1, 1, 0.9)
                    end },
                })
            end)
            return btn, btnLbl
        end

        -- The talent button, right of the activities
        local talentDDBtn, talentDDLbl = MakeTalentButton(formRow, ddStartX + FORM_DD_W + DD_GAP)

        y = y - FORM_ROW_H

        -- "Add Reminder" button (styled like Done button)
        _, h = W:Spacer(parent, y, 10); y = y - h

        local addBtnFrame = CreateFrame("Frame", nil, parent)
        PP.Size(addBtnFrame, parent:GetWidth() or 400, 36)
        PP.Point(addBtnFrame, "TOPLEFT", parent, "TOPLEFT", 0, y)

        -- A 160 x 36 form button (the Done button's look), its text and outline
        -- brightening over 0.1 s on hover: in the accent, or gray (white at the
        -- house button's alphas, MakeStyledButton's) for a secondary action.
        local function FormButton(text, gray)
            local b = CreateFrame("Button", nil, addBtnFrame)
            b:SetSize(160, 36)
            local DARK_BG = EllesmereUI.DARK_BG
            local bg = EllesmereUI.SolidTex(b, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
            bg:SetAllPoints()
            local eg = EllesmereUI.ELLESMERE_GREEN
            local txtA, txtHA = 0.7, 1
            local brdA, brdHA = 0.7, 1
            if gray then
                txtA, txtHA = EllesmereUI.BTN_TXT_A, EllesmereUI.BTN_TXT_HA
                brdA, brdHA = EllesmereUI.BTN_BRD_A, EllesmereUI.BTN_BRD_HA
            end
            local function Paint(fs, brd, t)
                local r, g, bl = 1, 1, 1
                if not gray then r, g, bl = eg.r, eg.g, eg.b end
                fs:SetTextColor(r, g, bl, txtA + (txtHA - txtA) * t)
                brd:SetColor(r, g, bl, brdA + (brdHA - brdA) * t)
            end
            local brd = EllesmereUI.MakeRoundedBorder(b, 1, 1, 1, brdA, bg)
            local fs = b:CreateFontString(nil, "OVERLAY")
            fs:SetPoint("CENTER")
            fs:SetFont(fontPath, 13, GetABROptOutline())
            fs:SetText(text)
            Paint(fs, brd, 0)

            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Paint(fs, brd, progress)
            end
            b:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            b:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
            return b
        end

        -- Add Reminder and the gray Import Reminders beside it, centred as a pair.
        local addBtn = FormButton(EllesmereUI.L("Add Reminder"))
        local importBtn = FormButton(EllesmereUI.L("Import Reminders"), true)
        local PAIR_GAP = 10
        addBtn:SetPoint("LEFT", addBtnFrame, "CENTER",
            -math.floor((addBtn:GetWidth() + PAIR_GAP + importBtn:GetWidth()) / 2), 0)
        importBtn:SetPoint("LEFT", addBtn, "RIGHT", PAIR_GAP, 0)
        importBtn:SetScript("OnClick", function() TRShare.ShowImport() end)

        y = y - 36

        -----------------------------------------------------------------------
        --  Active reminders: one card per spec (owner 2026-11-17), the house
        --  module card as on Nameplates' Debuff Coloring. Every reminder is
        --  kept per spec (EllesmereUI.SplitTalentReminders); one with a class
        --  but no spec (a character with no spec yet) gets a card for its
        --  class, one with neither a card for every class. Adding or deleting
        --  a reminder builds the page again.
        -----------------------------------------------------------------------
        -- Both dropdowns of a reminder row; wide enough for the longest place name.
        local ROW_DD_W = 220
        -- Every activity the checklist lists, read once per build.
        local allKeys = ActivityKeys()
        local ROW_H = 50
        local SIDE_PAD = 20

        local Tex = function(id) return _G._EABR_Tex and _G._EABR_Tex(id) or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400 end

        -- One reminder's row: its talent and activities | where its Not Needed
        -- reminder shows. The row holds the reminder itself, never its place
        -- in the list (a split or a delete moves the others): every edit
        -- finds it in the list again, and one no longer there changes nothing.
        local function BuildReminderRow(reminder, cy, shade)
            local row = ns.CardRow(parent, cy, ROW_H, shade, true)
            local function ReminderAt()
                local p2 = DB()
                local list = p2 and p2.talentReminders
                if list then
                    for i = 1, #list do
                        if list[i] == reminder then return reminder, i end
                    end
                end
            end

            -- === LEFT HALF: talent icon + name | its activities ===

            local spellIcon = row:CreateTexture(nil, "ARTWORK")
            spellIcon:SetSize(22, 22)
            spellIcon:SetPoint("LEFT", row, "LEFT", SIDE_PAD, 0)
            spellIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            spellIcon:SetTexture(Tex(reminder.spellID))

            local spellFS = row:CreateFontString(nil, "OVERLAY")
            spellFS:SetFont(fontPath, 14, GetABROptOutline())
            spellFS:SetTextColor(1, 1, 1, 1)
            spellFS:SetJustifyH("LEFT")
            spellFS:SetWordWrap(false)
            spellFS:SetMaxLines(1)
            spellFS:SetPoint("LEFT", spellIcon, "RIGHT", 8, 0)
            spellFS:SetText(reminder.spellName or EllesmereUI.L("Unknown"))

            -- Its activities (the shared checklist), Delete Reminder above
            -- them. Its last activity stays checked: a reminder always has
            -- one, and Delete Reminder removes it.
            local function ActCount(r)
                local n = 0
                for _, k in ipairs(allKeys) do
                    if TRActs.Has(r, k) then n = n + 1 end
                end
                return n
            end
            local function Changed()
                if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
            end
            local nnRefresh, PaintNotNeededLabel  -- the Not Needed side, built below
            local actDD = ns.BuildActivityChecklist(row, ROW_DD_W, row:GetFrameLevel() + 3, {
                get = function(key)
                    local r = ReminderAt()
                    return (r and TRActs.Has(r, key)) and true or false
                end,
                set = function(key, on)
                    local r = ReminderAt()
                    if not r then return end
                    TRActs.Edit(r)[key] = on or nil
                    -- One of its own activities is no Not Needed one.
                    if on and type(r.notNeededActs) == "table" then r.notNeededActs[key] = nil end
                    if nnRefresh then nnRefresh() end
                    if PaintNotNeededLabel then PaintNotNeededLabel() end
                    Changed()
                end,
                locked = function(key)
                    local r = ReminderAt()
                    return (r and TRActs.Has(r, key) and ActCount(r) <= 1) and true or false
                end,
                lockedTooltip = function() return "A reminder needs at least one activity." end,
                -- A ticked "All" entry holding every activity of the reminder.
                groupLocked = function(keys)
                    local r = ReminderAt()
                    if not r then return false end
                    local inGroup = 0
                    for _, k in ipairs(keys) do
                        if TRActs.Has(r, k) then inGroup = inGroup + 1 end
                    end
                    return inGroup >= ActCount(r)
                end,
                groupLockedTooltip = "A reminder needs at least one activity.",
                top = { { label = "Delete Reminder", onClick = function()
                    local _, i = ReminderAt()
                    if not i then return end
                    table.remove(DB().talentReminders, i)
                    Changed()
                    EllesmereUI:RefreshPage(true)
                end } },
                mplusTip = DUNGEON_TIP,
                maxVisible = 10,
            })
            PP.Point(actDD, "RIGHT", row, "CENTER", -SIDE_PAD, 0)
            spellFS:SetPoint("RIGHT", actDD, "LEFT", -12, 0)

            -- === RIGHT HALF: "Show 'Not Needed' Reminder" label + its activities ===

            local toggleLabel = row:CreateFontString(nil, "OVERLAY")
            toggleLabel:SetFont(fontPath, 14, GetABROptOutline())
            toggleLabel:SetJustifyH("LEFT")
            toggleLabel:SetWordWrap(false)
            toggleLabel:SetMaxLines(1)
            toggleLabel:SetPoint("LEFT", row, "CENTER", SIDE_PAD, 0)
            toggleLabel:SetText(EllesmereUI.L("Show 'Not Needed' Reminder"))

            -- Where it shows: the activities the reminder does not use (its own
            -- rest locked). A reminder saved with the old choice reads through
            -- it until an edit here takes it over (TRActs.EditNotNeeded).
            local function NotNeeded(r, key)
                return (r and not TRActs.Has(r, key) and TRActs.NotNeededHas(r, key)) and true or false
            end
            -- The label dims while it shows nowhere, as it did under Never.
            PaintNotNeededLabel = function()
                local r, any = ReminderAt(), false
                for _, k in ipairs(allKeys) do
                    if NotNeeded(r, k) then any = true break end
                end
                toggleLabel:SetTextColor(1, 1, 1, any and 1 or 0.4)
            end
            PaintNotNeededLabel()
            local function NNSet(key, on)
                local r = ReminderAt()
                if not r then return end
                TRActs.EditNotNeeded(r, allKeys)[key] = on or nil
            end
            local notNeededDD
            notNeededDD, nnRefresh = ns.BuildActivityChecklist(row, ROW_DD_W, row:GetFrameLevel() + 3, {
                get = function(key) return NotNeeded(ReminderAt(), key) end,
                set = function(key, on)
                    NNSet(key, on)
                    PaintNotNeededLabel()
                    Changed()
                end,
                locked = function(key)
                    local r = ReminderAt()
                    return (r and TRActs.Has(r, key)) and true or false
                end,
                lockedTooltip = function() return "This reminder already uses this activity." end,
                top = { { label = "Select All", onClick = function()
                    local r = ReminderAt()
                    if not r then return end
                    for _, k in ipairs(allKeys) do
                        if not TRActs.Has(r, k) then NNSet(k, true) end
                    end
                    nnRefresh()
                    PaintNotNeededLabel()
                    Changed()
                end } },
                emptyLabel = "None",
                mplusTip = DUNGEON_TIP,
                maxVisible = 10,
            })
            PP.Point(notNeededDD, "RIGHT", row, "RIGHT", -SIDE_PAD, 0)
            notNeededDD._ttText = "Reminds you to remove this talent in the activities checked here."
            toggleLabel:SetPoint("RIGHT", notNeededDD, "LEFT", -12, 0)
            return ROW_H
        end

        -- The cards, from y; returns the y under them. listHdr is the
        -- section header over them: with two cards or more, Export All sits
        -- at its right end, over the top card's top right corner.
        local function BuildReminderCards(y, listHdr)
            local reminders = DB().talentReminders or {}

            -- Current-season filter: only reminders holding at least one
            -- activity the checklist lists now are shown. One for rotated-out
            -- zones or dungeons only keeps its stored reminder (hidden here,
            -- never deleted) -- the place back on the list revives it.
            local function Current(reminder)
                for _, k in ipairs(allKeys) do
                    if TRActs.Has(reminder, k) then return true end
                end
                return false
            end

            -- Group the shown reminders by card, in the list's order.
            local groups = {}
            for _, reminder in ipairs(reminders) do
                if Current(reminder) then
                    local key = reminder.specID or (reminder.class and ("class:" .. reminder.class)) or "any"
                    local g = groups[key]
                    if not g then
                        g = { key = key, specID = reminder.specID, class = reminder.class, items = {} }
                        groups[key] = g
                    end
                    g.items[#g.items + 1] = reminder
                end
            end

            if not next(groups) then
                local row = ns.CardRow(parent, y, ROW_H, false)
                local emptyFS = row:CreateFontString(nil, "OVERLAY")
                emptyFS:SetFont(fontPath, 13, GetABROptOutline())
                emptyFS:SetTextColor(0.5, 0.5, 0.5, 1)
                emptyFS:SetPoint("CENTER")
                emptyFS:SetText(EllesmereUI.L("No talent reminders configured"))
                return y - ROW_H
            end

            -- Card order: your current spec first, then every spec in class
            -- and spec order, then the class cards, then the one for every class.
            local _, playerClass = UnitClass("player")
            local specIdx = C_SpecializationInfo.GetSpecialization()
            local playerSpec = specIdx and C_SpecializationInfo.GetSpecializationInfo(specIdx) or nil
            local ordered = {}
            local function Take(key)
                local g = key and groups[key]
                if g and not g.taken then g.taken = true; ordered[#ordered + 1] = g end
            end
            Take(playerSpec)
            for _, cls in ipairs(EllesmereUI._SPEC_DATA or {}) do
                for _, s in ipairs(cls.specs) do Take(s.id) end
            end
            for _, cls in ipairs(EllesmereUI._SPEC_DATA or {}) do Take("class:" .. cls.class) end
            for _, g in pairs(groups) do
                if not g.taken then g.taken = true; ordered[#ordered + 1] = g end
            end

            -- Your current spec's card starts open, the others closed.
            local openKey = playerSpec or ("class:" .. tostring(playerClass))
            if _trCardOpen[openKey] == nil then _trCardOpen[openKey] = true end

            if #ordered >= 2 and listHdr then
                local all = {}
                for _, g in ipairs(ordered) do
                    for _, r in ipairs(g.items) do all[#all + 1] = r end
                end
                local exportAll = EllesmereUI.BuildAccentLink(listHdr, EllesmereUI.L("Export All"),
                    function() TRShare.ShowExport(all) end)
                -- Level with the section title's baseline, at the cards' right edge.
                PP.Point(exportAll, "BOTTOMRIGHT", listHdr, "BOTTOMRIGHT", 0, 6)
            end

            for _, g in ipairs(ordered) do
                local display, specIcon, class = nil, nil, g.class
                if g.specID then
                    local _, specName, icon, classFile, className
                    if GetSpecializationInfoByID then
                        _, specName, _, icon, _, classFile, className = GetSpecializationInfoByID(g.specID)
                    end
                    specIcon, class = icon, classFile or class
                    display = (specName and className) and (specName .. " " .. className) or tostring(g.specID)
                elseif class then
                    local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
                    display = className .. " - " .. EllesmereUI.L("All Specs")
                else
                    display = EllesmereUI.L("All Classes")
                end
                local tile = { key = g.key, display = display,
                    desc = EllesmereUI.L("Reminders") .. ": " .. #g.items,
                    buildContent = function(_, cy)
                        for i, r in ipairs(g.items) do
                            cy = cy - BuildReminderRow(r, cy, i % 2 == 0)
                        end
                        return cy
                    end }
                y = EllesmereUI.BuildModuleCard(parent, y, W, tile, {
                    enabled = true, expanded = _trCardOpen, descW = 440, noSearch = true,
                    glyph = function(hdr) ns.CardGlyph(hdr, specIcon, class) end,
                    -- Export | Delete: Export shares every reminder the card
                    -- lists; Delete removes them (one for rotated-out places
                    -- only, hidden, stays), after a confirm.
                    links = {
                        { text = EllesmereUI.L("Export"), onClick = function() TRShare.ShowExport(g.items) end },
                        { text = EllesmereUI.L("Delete"), color = { 1, 0.3, 0.3 }, onClick = function()
                        EllesmereUI:ShowConfirmPopup({
                            title = "Delete Reminders",
                            message = EllesmereUI.Lf("Delete all %1$d talent reminders for %2$s?", #g.items, display),
                            confirmText = "Delete",
                            cancelText = "Cancel",
                            onConfirm = function()
                                local list = DB().talentReminders
                                if not list then return end
                                -- The card's reminders that are still in the list.
                                local gone = {}
                                for _, r in ipairs(g.items) do gone[r] = true end
                                for i = #list, 1, -1 do
                                    if gone[list[i]] then table.remove(list, i) end
                                end
                                _trCardOpen[g.key] = nil
                                if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
                                EllesmereUI:RefreshPage(true)
                            end,
                        })
                        end },
                    } })
                ns.CardClassTitle(tile, class)
            end
            return y
        end

        -- Add button click handler
        addBtn:SetScript("OnClick", function()
            -- Validate: at least one activity, and a talent
            if not next(selectedActs) then
                ns.CardPulse(actDD)
                return
            end
            if not selectedTalentSpellID or selectedTalentSpellID == 0 then
                ns.CardPulse(talentDDBtn)
                return
            end

            local p = DB()
            if not p then return end
            if not p.talentReminders then p.talentReminders = {} end

            -- Your current spec (reminders are kept per spec): nil before the
            -- character has a spec, when the reminder holds for the whole class.
            local specIdx = C_SpecializationInfo.GetSpecialization()
            local curSpec = specIdx and C_SpecializationInfo.GetSpecializationInfo(specIdx) or nil
            local _, playerClass = UnitClass("player")

            -- An existing reminder of the same talent for this spec takes the
            -- activities it lacks; otherwise a new one, its Not Needed reminder
            -- showing nowhere until some are checked.
            local held
            for _, r in ipairs(p.talentReminders) do
                if r.spellID == selectedTalentSpellID and r.specID == curSpec
                    and (r.class == nil or r.class == playerClass) then
                    held = r
                    break
                end
            end
            if held then
                local acts = TRActs.Edit(held)
                for k in pairs(selectedActs) do
                    acts[k] = true
                    if type(held.notNeededActs) == "table" then held.notNeededActs[k] = nil end
                end
            else
                local acts = {}
                for k in pairs(selectedActs) do acts[k] = true end
                p.talentReminders[#p.talentReminders + 1] = {
                    acts = acts,
                    notNeededActs = {},
                    spellID = selectedTalentSpellID,
                    spellName = selectedTalentName,
                    class = playerClass,
                    specID = curSpec,
                    -- read by older versions, which keep a reminder per spec only with it
                    talentSource = curSpec and "spec" or nil,
                }
            end

            -- Reset selection
            wipe(selectedActs)
            selectedTalentSpellID = nil
            selectedTalentName = nil
            actRefresh()
            if talentDDLbl then talentDDLbl:SetText(EllesmereUI.L("Select a talent...")); talentDDLbl:SetTextColor(1, 1, 1, 0.50) end

            if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
            EllesmereUI:RefreshPage(true)
        end)

        -- Spacer before list
        _, h = W:Spacer(parent, y, 15); y = y - h

        -- Section header for the list
        local listHdr
        listHdr, h = W:SectionHeader(parent, "ACTIVE REMINDERS", y); y = y - h

        y = BuildReminderCards(y, listHdr)

        _, h = W:Spacer(parent, y, 20); y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIAuraBuffReminders", {
        title       = "Auras, Buffs & Consumables",
        description = "AuraBuff Reminders: Raid Buffs, Auras, and Consumables.",
        pages       = FOREVER and { PAGE_REMINDERS, PAGE_LOADOUTS } or { PAGE_REMINDERS, PAGE_TALENTS, PAGE_LOADOUTS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_REMINDERS then
                return BuildRemindersPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TALENTS then
                return BuildTalentRemindersPage(pageName, parent, yOffset)
            elseif pageName == PAGE_LOADOUTS then
                return ns._BuildLoadoutPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_REMINDERS and not FOREVER then
                return _previewHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            -- The reminder list changed under the kept Talent Reminders tab:
            -- build it again, a frame later (the Unit Frames tabs' rule).
            if pageName == PAGE_TALENTS and TRShare.listStale then
                TRShare.listStale = false
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == "EllesmereUIAuraBuffReminders"
                        and EllesmereUI:GetActivePage() == PAGE_TALENTS then
                        EllesmereUI:RefreshPage(true)
                    end
                end)
            end
            if pageName == PAGE_REMINDERS and not FOREVER then
                UpdatePreviewHeader()
                -- Refresh hint visibility never recreate here, just show/hide
                local dismissed = IsPreviewHintDismissed()
                if _previewHintFS then
                    if dismissed then
                        _previewHintFS:Hide()
                    else
                        _previewHintFS:SetAlpha(0.45)
                        _previewHintFS:Show()
                    end
                end
                -- Set correct header height based on current hint state
                if _eabrHeaderBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(_eabrHeaderBaseH + (dismissed and 0 or 35))
                end
            end
        end,
        onShow = function()
            if _G._EABR_HideAllIcons then _G._EABR_HideAllIcons() end
        end,
        onHide = function()
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        end,
        -- The Loadout Manager's General settings are account-wide and its
        -- loadouts each character's own (ns.Loadouts.ResetAll).
        resetDisclaimer = "The reminders are reset for the current profile, the Loadout Manager's General settings for every character and its loadouts for this one.",
        onReset = function()
            if _G._EABR_AceDB then
                _G._EABR_AceDB:ResetProfile()
            end
            if ns.Loadouts then ns.Loadouts.ResetAll() end
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        end,
        -- Tears down the Ready Check Mana Warning preview on module switch.
        onModuleLeave = function()
            if _G._EABR_RCWarnHidePreview then _G._EABR_RCWarnHidePreview() end
        end,
    })

    -- Register unlock elements after a short delay
    C_Timer.After(0.5, function()
        if _G._EABR_RegisterUnlock then _G._EABR_RegisterUnlock() end
    end)

    ---------------------------------------------------------------------------
    --  Slash commands
    ---------------------------------------------------------------------------
    SLASH_EABR1 = "/eabr"
    SLASH_EABR2 = "/ebr"
    SlashCmdList.EABR = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIAuraBuffReminders")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
