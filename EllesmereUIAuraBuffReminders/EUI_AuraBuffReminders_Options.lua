-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Options.lua
--  Registers the AuraBuff Reminders module with EllesmereUI
--  Two pages: Auras, Buffs & Consumables | Talent Reminders | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_REMINDERS = "Auras, Buffs & Consumables"
local PAGE_TALENTS   = "Talent Reminders"
local PAGE_UNLOCK    = "Unlock Mode"

local SECTION_CORE         = "CORE"
local SECTION_DISPLAY      = "DISPLAY"
local SECTION_RAID_BUFFS   = "RAID BUFFS"
local SECTION_AURAS        = "AURAS"
local SECTION_CONSUMABLES  = "CONSUMABLES"
local SECTION_ROGUE        = "ROGUE POISONS"
local SECTION_PALADIN      = "PALADIN RITES"
local SECTION_SHAMAN       = "SHAMAN IMBUES & SHIELDS"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local function GetABROptOutline()
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    end
    local function GetABROptUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
    end
    local function SetPVFont(fs, font, size)
        if not (fs and fs.SetFont) then return end
        local f = GetABROptOutline()
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, f == "") end
        fs:SetFont(font, size, f)
    end

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
    local function RDB()  local p = DB(); return p and p.raidBuffs end
    local function ADB()  local p = DB(); return p and p.auras end
    local function CDB()  local p = DB(); return p and p.consumables end

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

    local Known = function(id) return id and (IsPlayerSpell(id) or IsSpellKnown(id)) end
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
                    icons[#icons+1] = { texture = WEI[1].icon or 134400, label = "Weapon", cat = "consumable", itemKey = "weapon_enchant" }
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

    local function UpdatePreviewHeader()
        if not _previewIcons or #_previewIcons == 0 then return end
        local d = DDB()
        if not d then return end
        local baseScale = d.scale or 1.0
        local ICON_SIZE = _G._EABR_ICON_SIZE or 40
        local sz = math.floor(ICON_SIZE * baseScale + 0.5)
        local spacing = d.iconSpacing or 8
        local glowType = d.glowType or 0
        local gc = d.glowColor or {r=1, g=0.776, b=0.376}
        local showText = d.showText
        local tc = d.textColor or {r=1, g=1, b=1}
        local opacity = d.opacity or 1.0
        local GT = _G._EABR_GLOW_TYPES
        local Stop = _G._EABR_StopAllGlows

        local count = #_previewIcons
        local totalW = (count * sz) + ((count - 1) * spacing)

        for i, pIcon in ipairs(_previewIcons) do
            local btn = pIcon.frame
            if not btn then break end
            btn:SetSize(sz, sz)
            btn:SetAlpha(opacity)
            btn:ClearAllPoints()
            local startX = -(totalW / 2) + (sz / 2)
            btn:SetPoint("TOP", btn:GetParent(), "TOP", startX + (i - 1) * (sz + spacing), 0)

            -- Glow
            if not btn._glowWrapper then
                local w = CreateFrame("Frame", nil, btn)
                w:SetAllPoints(btn); w:SetFrameLevel(btn:GetFrameLevel() + 3)
                btn._glowWrapper = w
            end
            if Stop then Stop(btn._glowWrapper) end

            if glowType > 0 and GT then
                local entry = GT[glowType]
                if entry then
                    if entry.procedural and _G._EABR_StartPixelGlow then
                        _G._EABR_StartPixelGlow(btn._glowWrapper, sz, gc.r, gc.g, gc.b)
                    elseif entry.buttonGlow and _G._EABR_StartButtonGlow then
                        _G._EABR_StartButtonGlow(btn._glowWrapper, sz, gc.r, gc.g, gc.b, 1.36)
                    elseif entry.autocast and _G._EABR_StartAutoCastShine then
                        _G._EABR_StartAutoCastShine(btn._glowWrapper, sz, gc.r, gc.g, gc.b, 1.0)
                    elseif _G._EABR_StartFlipBookGlow then
                        -- FlipBook glow (GCD, Modern WoW, Classic WoW) use shared live function
                        _G._EABR_StartFlipBookGlow(btn._glowWrapper, sz, entry, gc.r, gc.g, gc.b)
                    end
                    btn._glowWrapper:Show()
                end
            else
                btn._glowWrapper:Hide()
            end

            -- Text
            if showText then
                local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("auraBuff")) or "Fonts\\ARIALN.TTF"
                local textSize = d and d.textSize or 11
                local textXOff = d and d.textXOffset or 0
                local textYOff = d and d.textYOffset or -2
                SetPVFont(btn._text, fontPath, textSize)
                btn._text:ClearAllPoints()
                btn._text:SetPoint("TOP", btn, "BOTTOM", textXOff, textYOff)
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
            local CONTAINER_H = sz + textOverhang2
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

    ---------------------------------------------------------------------------
    --  Preview click-to-scroll infrastructure
    ---------------------------------------------------------------------------
    local _eabrHeaderBaseH = 0

    --- Rebuild the preview header with scroll compensation.
    --- SetContentHeader tears down and rebuilds, which can cause scroll jumps.
    --- This wrapper saves the scroll position, rebuilds, then compensates.
    local function RebuildPreviewHeader()
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
        local count = #_previewIcons
        local totalW = (count * sz) + ((count - 1) * spacing)
        local startX = -(totalW / 2) + (sz / 2)
        for i, pIcon in ipairs(_previewIcons) do
            local btn = pIcon.frame
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("TOP", btn:GetParent(), "TOP", startX + (i - 1) * (sz + spacing), 0)
            end
        end
    end

    local _eabrGlowFrame
    local _eabrClickMappings = {}
    local _eabrHitOverlays = {}

    local function EABRPlaySettingGlow(targetFrame)
        if not targetFrame then return end
        if not _eabrGlowFrame then
            _eabrGlowFrame = CreateFrame("Frame")
            local c = EllesmereUI.ELLESMERE_GREEN
            local function MkEdge()
                local t = _eabrGlowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(c.r, c.g, c.b, 1)
                return t
            end
            _eabrGlowFrame._top = MkEdge()
            _eabrGlowFrame._bot = MkEdge()
            _eabrGlowFrame._lft = MkEdge()
            _eabrGlowFrame._rgt = MkEdge()
            _eabrGlowFrame._top:SetHeight(2)
            _eabrGlowFrame._top:SetPoint("TOPLEFT"); _eabrGlowFrame._top:SetPoint("TOPRIGHT")
            _eabrGlowFrame._bot:SetHeight(2)
            _eabrGlowFrame._bot:SetPoint("BOTTOMLEFT"); _eabrGlowFrame._bot:SetPoint("BOTTOMRIGHT")
            _eabrGlowFrame._lft:SetWidth(2)
            _eabrGlowFrame._lft:SetPoint("TOPLEFT", _eabrGlowFrame._top, "BOTTOMLEFT")
            _eabrGlowFrame._lft:SetPoint("BOTTOMLEFT", _eabrGlowFrame._bot, "TOPLEFT")
            _eabrGlowFrame._rgt:SetWidth(2)
            _eabrGlowFrame._rgt:SetPoint("TOPRIGHT", _eabrGlowFrame._top, "BOTTOMRIGHT")
            _eabrGlowFrame._rgt:SetPoint("BOTTOMRIGHT", _eabrGlowFrame._bot, "TOPRIGHT")
        end
        _eabrGlowFrame:SetParent(targetFrame)
        _eabrGlowFrame:SetAllPoints(targetFrame)
        _eabrGlowFrame:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
        _eabrGlowFrame:SetAlpha(1)
        _eabrGlowFrame:Show()
        local elapsed = 0
        _eabrGlowFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.75 then
                self:Hide(); self:SetScript("OnUpdate", nil); return
            end
            self:SetAlpha(1 - elapsed / 0.75)
        end)
    end

    local function EABRNavigateToSetting(key)
        local m = _eabrClickMappings[key]
        if not m or not m.section or not m.target then return end

        -- Dismiss the hint text on first click
        if not IsPreviewHintDismissed() and _previewHintFS and _previewHintFS:IsShown() then
            EllesmereUIDB = EllesmereUIDB or {}
            EllesmereUIDB.previewHintDismissed = true
            local hint = _previewHintFS
            local _, anchorTo, _, _, startY = hint:GetPoint(1)
            startY = startY or 5
            anchorTo = anchorTo or hint:GetParent()
            local startHeaderH = _eabrHeaderBaseH + 35
            local targetHeaderH = _eabrHeaderBaseH
            local steps = 0
            local ticker
            ticker = C_Timer.NewTicker(0.016, function()
                steps = steps + 1
                local progress = steps * 0.016 / 0.3
                if progress >= 1 then
                    hint:Hide(); ticker:Cancel()
                    if targetHeaderH > 0 then
                        EllesmereUI:SetContentHeaderHeightSilent(targetHeaderH)
                    end
                    return
                end
                hint:SetAlpha(0.45 * (1 - progress))
                hint:ClearAllPoints()
                hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, startY + progress * 12)
                local hh = startHeaderH - 35 * progress
                if hh > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(hh)
                end
            end)
        end

        local sf = EllesmereUI._scrollFrame
        if not sf then return end

        local child = sf.GetScrollChild and sf:GetScrollChild()
        if child and m.target and m.target.GetTop and child.GetTop then
            local targetTop = m.target:GetTop()
            local childTop = child:GetTop()
            if targetTop and childTop then
                local scrollPos = math.max(0, childTop - targetTop - 40)
                EllesmereUI.SmoothScrollTo(scrollPos)
                C_Timer.After(0.15, function() EABRPlaySettingGlow(m.target) end)
                return
            end
        end

        -- Fallback for layouts where the scroll child isn't ready yet.
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if headerY then
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            EllesmereUI.SmoothScrollTo(scrollPos)
        end
        C_Timer.After(0.15, function() EABRPlaySettingGlow(m.target) end)
    end

    local function EABRCreateHitOverlay(element, mappingKey, frameLevelOverride)
        local anchor = element
        if not anchor.CreateTexture then anchor = anchor:GetParent() end
        local btn = CreateFrame("Button", nil, anchor)
        btn:SetAllPoints(element)
        btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
        btn:RegisterForClicks("LeftButtonDown")
        local c = EllesmereUI.ELLESMERE_GREEN
        local brd = EllesmereUI.PP.CreateBorder(btn, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
        brd:Hide()
        btn:SetScript("OnEnter", function() brd:Show() end)
        btn:SetScript("OnLeave", function() brd:Hide() end)
        btn:SetScript("OnMouseDown", function() EABRNavigateToSetting(mappingKey) end)
        _eabrHitOverlays[#_eabrHitOverlays + 1] = btn
        return btn
    end

    _previewHeaderBuilder = function(hdr, hdrW)
        local icons = CollectPreviewIcons()
        local d = DDB()
        local baseScale = d and d.scale or 1.0
        local ICON_SIZE = _G._EABR_ICON_SIZE or 40
        local sz = math.floor(ICON_SIZE * baseScale + 0.5)
        local spacing = d and d.iconSpacing or 8
        local showText = d and d.showText
        local tc = d and d.textColor or {r=1, g=1, b=1}
        local opacity = d and d.opacity or 1.0

        -- Reuse existing container + icons if count matches (avoids
        -- full frame teardown/rebuild on tab switch which causes FPS dip)
        if _previewContainer and #_previewIcons == #icons then
            -- Re-parent and re-show (may have been orphaned by ClearContentHeader)
            _previewContainer:SetParent(hdr)
            _previewContainer:ClearAllPoints()
            _previewContainer:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            _previewContainer:SetSize(hdrW, _previewContainer:GetHeight())
            _previewContainer:Show()
            -- Update textures/labels in case the icon set changed content
            for i, pIcon in ipairs(_previewIcons) do
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

        -- Recycle or create container
        if _previewContainer then
            _previewContainer:SetParent(hdr)
            _previewContainer:ClearAllPoints()
        else
            _previewContainer = CreateFrame("Frame", nil, hdr)
        end
        _previewContainer:SetSize(hdrW, sz + textOverhang)
        _previewContainer:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        _previewContainer:Show()
        local container = _previewContainer

        -- Hide old icon frames before rebuilding
        for _, pIcon in ipairs(_previewIcons) do
            if pIcon.frame then pIcon.frame:Hide() end
        end
        wipe(_previewIcons)
        local count = #icons
        local totalW = (count * sz) + ((count - 1) * spacing)

        for i, iconData in ipairs(icons) do
            local btn = CreateFrame("Button", nil, container)
            btn:SetSize(sz, sz)
            btn:EnableMouse(true)
            local startX = -(totalW / 2) + (sz / 2)
            btn:SetPoint("TOP", container, "TOP", startX + (i - 1) * (sz + spacing), 0)
            btn:SetAlpha(opacity)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(iconData.texture or 134400)
            if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end
            btn._icon = icon

            -- Pixel-perfect 1px black border
            EllesmereUI.MakeBorder(btn, 0, 0, 0, 1, EllesmereUI.PanelPP)

            -- Text label below icon
            local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("auraBuff")) or "Fonts\\ARIALN.TTF"
            local textSize = d and d.textSize or 11
            local textXOff = d and d.textXOffset or 0
            local textYOff = d and d.textYOffset or -2
            local text = btn:CreateFontString(nil, "OVERLAY")
            text:SetPoint("TOP", btn, "BOTTOM", textXOff, textYOff)
            SetPVFont(text, fontPath, textSize)
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
                -- Hit overlay on text label scrolls to Show Text setting
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
                _previewHintFS = EllesmereUI.MakeFont(container, 11, nil, 1, 1, 1)
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
    --  MakeCogBtn helper (inline cog button next to a DualRow region)
    ---------------------------------------------------------------------------
    local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", anchorTo or rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) showFn(self) end)
        return cogBtn
    end

    ---------------------------------------------------------------------------
    --  4-column checkbox grid (DualRow-style rows with RowBg + dividers)
    --  items = { { label, classToken, getVal, setVal }, ... }
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
                boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                if boxBg.SetSnapToPixelGrid then boxBg:SetSnapToPixelGrid(false); boxBg:SetTexelSnappingBias(0) end

                local boxBrd = EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, EllesmereUI.PanelPP)

                local check = box:CreateTexture(nil, "ARTWORK")
                check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                check:SetColorTexture(eg.r, eg.g, eg.b, 1)
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
                        boxBrd:SetColor(0.25, 0.25, 0.28, 0.6)
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
                end)
                btn:SetScript("OnLeave", function()
                    if not item.getVal() then label:SetAlpha(0.5) end
                end)

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
    local function BuildRemindersPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h, row

        -- Cell reference table for preview icon specific toggle navigation
        local _gridCellRefs = {}

        -- Set up the preview header
        EllesmereUI:SetContentHeader(_previewHeaderBuilder)

        parent._showRowDivider = true

        -- Click-action info label at the top of the page (below the preview area)
        do
            local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("auraBuff")) or "Fonts\\FRIZQT__.TTF"
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

        -----------------------------------------------------------------------
        --  CORE section
        -----------------------------------------------------------------------
        local coreSection
        coreSection, h = W:SectionHeader(parent, SECTION_CORE, y);  y = y - h

        -- Row 1: Enable Reminders | Scale
        local row1
        row1, h = W:DualRow(parent, y,
            { type="toggle", text="Enable AuraBuff Reminders",
              tooltip="Master toggle for all aura, buff, and consumable reminders. Talent reminders are not affected.",
              getValue=function() local d = DDB(); return d and d.remindersEnabled ~= false end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.remindersEnabled = v
                  RefreshAll()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Scale", min=0.5, max=3.0, step=0.05,
              getValue=function() local d = DDB(); return d and d.scale or 1.0 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.scale = v
                  RefreshAll()
                  UpdatePreviewHeader()
              end }
        );  y = y - h

        -- Row 2: Party Show Consumes Below | Raid Show Consumes Below
        local threshRow
        threshRow, h = W:DualRow(parent, y,
            { type="slider", text="Party: Show Consumes Below", min=0, max=60, step=1,
              trackWidth=120,
              tooltip="In Mythic Dungeons, show consumables reminders\nwhen the remaining buff time is less than this amount",
              getValue=function() local d = DDB(); return d and d.showUnderDurationDungeon or 0 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showUnderDurationDungeon = v
                  RefreshAll()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Raid: Show Consumes Below", min=0, max=15, step=1,
              trackWidth=120,
              tooltip="In Raids, show consumables reminders\nwhen the remaining buff time is less than this amount",
              getValue=function() local d = DDB(); return d and d.showUnderDurationRaid or 0 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showUnderDurationRaid = v
                  RefreshAll()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Add "(min)" suffix in smaller, dimmer text on both sliders
        for _, rgn in ipairs({threshRow._leftRegion, threshRow._rightRegion}) do
            local labelText = rgn == threshRow._leftRegion
                and "Party: Show Consumes Below" or "Raid: Show Consumes Below"
            local suffix = rgn:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local found
            for i = 1, rgn:GetNumRegions() do
                local reg = select(i, rgn:GetRegions())
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == labelText then
                    found = reg; break
                end
            end
            if found then
                suffix:SetPoint("LEFT", found, "RIGHT", 5, -1)
            end
            suffix:SetText(EllesmereUI.L("(min)"))
        end

        -----------------------------------------------------------------------
        --  DISPLAY section
        -----------------------------------------------------------------------
        local displaySection
        displaySection, h = W:SectionHeader(parent, SECTION_DISPLAY, y);  y = y - h

        -- Row 1: Show Text (+ inline swatch + cog) | Glow Type (+ inline swatch)
        local row2
        row2, h = W:DualRow(parent, y,
            { type="toggle", text="Show Text",
              getValue=function() local d = DDB(); return d and d.showText end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.showText = v
                  RefreshAll()
                  UpdatePreviewHeader()
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Glow Type",
              values=_G._EABR_GLOW_VALUES or {[0]="None"},
              order=_G._EABR_GLOW_ORDER or {0},
              getValue=function() local d = DDB(); return d and d.glowType or 0 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.glowType = v
                  RefreshAll(); UpdatePreviewHeader()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline color swatch on Glow Type (right of row 3)
        do
            local rgn = row2._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel()+5,
                function()
                    local d = DDB()
                    local gc = d and d.glowColor or {r=1, g=0.776, b=0.376}
                    return gc.r, gc.g, gc.b, 1
                end,
                function(r, g, b)
                    local d = DDB(); if not d then return end
                    d.glowColor = {r=r, g=g, b=b}
                    RefreshAll(); UpdatePreviewHeader()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch

            -- Disabled overlay when glow type is None
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("This option requires a Glow Type other than None"))
            end)
            swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSwatchDisabled()
                local d = DDB()
                local isNone = not d or (d.glowType or 0) == 0
                if isNone then
                    swatch:SetAlpha(0.3)
                    swatchBlock:Show()
                else
                    swatch:SetAlpha(1)
                    swatchBlock:Hide()
                end
            end
            UpdateSwatchDisabled()
            EllesmereUI.RegisterWidgetRefresh(UpdateSwatchDisabled)
        end

        -- Inline color swatch + cog on Show Text (left of row 2)
        do
            local rgn = row2._leftRegion
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
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch

            -- Disabled overlay for swatch when Show Text is off
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Show Text"))
            end)
            swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Inline cog for text settings (size, x/y offset)
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Text Settings",
                rows = {
                    { type="slider", label="Text Size", min=6, max=30, step=1,
                      get=function() local d = DDB(); return d and d.textSize or 11 end,
                      set=function(v) local d = DDB(); if not d then return end; d.textSize = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() local d = DDB(); return d and d.textXOffset or 0 end,
                      set=function(v) local d = DDB(); if not d then return end; d.textXOffset = v; RefreshAll(); UpdatePreviewHeader() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() local d = DDB(); return d and d.textYOffset or -2 end,
                      set=function(v) local d = DDB(); if not d then return end; d.textYOffset = v; RefreshAll(); UpdatePreviewHeader() end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)

            -- Disabled overlay for cog when Show Text is off
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints()
            cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
            cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Text"))
            end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Shared refresh for both swatch and cog disabled states
            local function UpdateTextInlinesDisabled()
                local d = DDB()
                local off = not d or not d.showText
                if off then
                    swatch:SetAlpha(0.3)
                    swatchBlock:Show()
                    cogBtn:SetAlpha(0.15)
                    cogBlock:Show()
                else
                    swatch:SetAlpha(1)
                    swatchBlock:Hide()
                    cogBtn:SetAlpha(0.4)
                    cogBlock:Hide()
                end
            end
            UpdateTextInlinesDisabled()
            EllesmereUI.RegisterWidgetRefresh(UpdateTextInlinesDisabled)
        end

        -- Row 4: Icon Spacing (+ directions cog) | Attach Important Buffs to Cursor
        local row3
        row3, h = W:DualRow(parent, y,
            { type="slider", text="Icon Spacing", min=0, max=50, step=1,
              getValue=function() local d = DDB(); return d and d.iconSpacing or 8 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.iconSpacing = v
                  RefreshAll()
                  RelayoutPreviewIcons()
              end },
            { type="toggle", text="Attach Important Buffs to Cursor",
              tooltip="This option only affects Raid Buffs and Paladin Beacons",
              getValue=function() local d = DDB(); return d and d.cursorAttach end,
              setValue=function(v) local d = DDB(); if not d then return end; d.cursorAttach = v; RefreshAll() end }
        );  y = y - h

        -- Inline DIRECTIONS cog on Icon Spacing (left of row 3) for Y offset
        do
            local rgn = row3._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Layout Settings",
                rows = {
                    { type="slider", label="Y Offset", min=-600, max=600, step=1,
                      get=function() local d = DDB(); return d and d.yOffset or 0 end,
                      set=function(v) local d = DDB(); if not d then return end; d.yOffset = v
                          if _G._EABR_ApplyUnlockPos then _G._EABR_ApplyUnlockPos() end end },
                },
            })
            MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
        end

        -- Row 5: Opacity | Frame Strata
        _, h = W:DualRow(parent, y,
            { type="slider", text="Opacity", min=0, max=1, step=0.05,
              getValue=function() local d = DDB(); return d and d.opacity or 1 end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.opacity = v
                  RefreshAll(); UpdatePreviewHeader()
              end },
            { type="dropdown", text="Frame Strata",
              values=_G._EABR_STRATA_VALUES or {MEDIUM="Medium"},
              order=_G._EABR_STRATA_ORDER or {"MEDIUM"},
              getValue=function() local d = DDB(); return d and d.frameStrata or "MEDIUM" end,
              setValue=function(v)
                  local d = DDB(); if not d then return end; d.frameStrata = v
                  if _G._EABR_ApplyStrata then _G._EABR_ApplyStrata() end
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  RAID BUFFS section
        -----------------------------------------------------------------------
        local raidBufHdr
        raidBufHdr, h = W:SectionHeader(parent, SECTION_RAID_BUFFS, y);  y = y - h

        -- Show Others Missing | Show Buffs In Open World
        local raidBufFirstRow
        raidBufFirstRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Others Missing",
              getValue=function() local r = RDB(); return r and r.showOthersMissing end,
              setValue=function(v) local r = RDB(); if r then r.showOthersMissing = v; if _G._EABR_UpdateGroupAuraRegistration then _G._EABR_UpdateGroupAuraRegistration() end; RefreshAll() end end },
            { type="toggle", text="Show Buffs In Open World",
              tooltip="Reminders are always hidden in rested areas (cities and inns).",
              getValue=function() local r = RDB(); return r and r.showNonInstanced end,
              setValue=function(v) local r = RDB(); if r then r.showNonInstanced = v; RefreshAll() end end }
        );  y = y - h

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
        --  AURAS section
        -----------------------------------------------------------------------
        local auraHdr
        auraHdr, h = W:SectionHeader(parent, SECTION_AURAS, y);  y = y - h

        -- Show Auras In Open World | Show Specials In Open World
        local auraFirstRow
        auraFirstRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Auras In Open World",
              tooltip="Reminders are always hidden in rested areas (cities and inns).",
              getValue=function() local a = ADB(); return a and a.showNonInstanced end,
              setValue=function(v) local a = ADB(); if a then a.showNonInstanced = v; RefreshAll() end end },
            { type="toggle", text="Show Specials In Open World",
              tooltip="Show special reminders while out in the open world.\nReminders are always hidden in rested areas (cities and inns).",
              getValue=function() local c = CDB(); return c and c.showSpecialsNonInstanced end,
              setValue=function(v) local c = CDB(); if c then c.showSpecialsNonInstanced = v; RefreshAll() end end }
        );  y = y - h

        -- 4-column checkbox grid for individual auras
        do
            local AURAS = _G._EABR_AURAS or {}
            local gridItems = {}
            for _, aura in ipairs(AURAS) do
                gridItems[#gridItems+1] = {
                    label = _G._EABR_SpellName(aura.castSpell, aura.name),
                    classToken = aura.class,
                    key = aura.key,
                    getVal = function() local a = ADB(); return a and a.enabled and a.enabled[aura.key] end,
                    setVal = function(v) local a = ADB(); if a and a.enabled then a.enabled[aura.key] = v end end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function() RefreshAll(); RebuildPreviewHeader() end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  ROGUE POISONS sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ROGUE, y);  y = y - h

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
                    getVal = function() local c = CDB(); return c and c.enabled and c.enabled[shield.key] end,
                    setVal = function(v) local c = CDB(); if c and c.enabled then c.enabled[shield.key] = v end end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function() RefreshAll(); RebuildPreviewHeader() end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  PETS section
        -----------------------------------------------------------------------
        local petHdr
        petHdr, h = W:SectionHeader(parent, "PETS", y);  y = y - h

        local petFirstRow
        petFirstRow, h = W:DualRow(parent, y,
            { type="toggle", text="Missing Pet Reminder",
              tooltip="Show a reminder when you don't have an active pet summoned. Only applies to pet classes (Hunter, Warlock, Death Knight, Mage).",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.pet ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.pet = v; RefreshAll(); RebuildPreviewHeader() end end },
            { type="toggle", text="Wrong Pet Reminder (Demo Lock)",
              tooltip="Show a reminder when your Demonology Warlock has the wrong pet summoned (not Felguard).",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.wrong_pet ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.wrong_pet = v; RefreshAll(); RebuildPreviewHeader() end end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Passive Pet Reminder",
              tooltip="Show a reminder when your active pet is set to Passive stance. Only applies to pet classes (Hunter, Warlock, Death Knight, Mage).",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.pet_passive ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.pet_passive = v; RefreshAll(); RebuildPreviewHeader() end end },
            { type="spacer" }
        );  y = y - h

        _eabrClickMappings.pet = { section = petHdr, target = petFirstRow }

        _, h = W:Spacer(parent, y, 10);  y = y - h

        -----------------------------------------------------------------------
        --  CONSUMABLES section
        -----------------------------------------------------------------------
        local consumHdr
        consumHdr, h = W:SectionHeader(parent, SECTION_CONSUMABLES, y);  y = y - h

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
                { type="dropdown", text="Preferred Click to Buff", dropdownWidth=220,
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
                { type="dropdown", text="Preferred Click to Buff", dropdownWidth=220,
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
                { type="dropdown", text="Preferred Click to Buff", dropdownWidth=220,
                  values=weValues, order=weOrder,
                  getValue=function() local c = CDB(); return c and c.preferredWeaponEnchant or "last_used" end,
                  setValue=function(v) local c = CDB(); if c then c.preferredWeaponEnchant = v; RefreshAll() end end }
            );  y = y - h
        end

        -- Augment Rune toggle | Display In dropdown
        local runeRow
        runeRow, h = W:DualRow(parent, y,
            { type="toggle", text="Augment Rune",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.augment_rune end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.augment_rune = v; RefreshAll(); RebuildPreviewHeader() end end },
            { type="dropdown", text="Augment Reminder Only In:",
              values={ mythic="Mythic Only", heroic_mythic="Heroic and Mythic", all="All Instanced Content" },
              order={ "mythic", "heroic_mythic", "all" },
              getValue=function() local c = CDB(); return c and c.runeDisplayMode or "mythic" end,
              setValue=function(v) local c = CDB(); if c then c.runeDisplayMode = v; RefreshAll() end end }
        );  y = y - h

        -- Healthstone toggle | Inky Black Potion toggle
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Healthstone",
              tooltip="Remind you to grab a Healthstone when a Warlock is in your group.",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.healthstone ~= false end,
              setValue=function(v) local c = CDB(); if c and c.enabled then c.enabled.healthstone = v; RefreshAll(); RebuildPreviewHeader() end end },
            { type="toggle", text="Inky Black Potion",
              getValue=function() local c = CDB(); return c and c.enabled and c.enabled.inky_black end,
              setValue=function(v)
                  local c = CDB(); if c and c.enabled then c.enabled.inky_black = v; RefreshAll(); RebuildPreviewHeader() end
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        local healthstoneRow = row

        -- Inline "Choose Zones" button on the right region (Inky Black)
        do
            local rgn = row._rightRegion
            local eg = EllesmereUI.ELLESMERE_GREEN or {r=0, g=0.82, b=0.62}
            local lerp = EllesmereUI.lerp
            local DARK_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }

            local zoneBtn = CreateFrame("Button", nil, rgn)
            zoneBtn:SetSize(110, 24)
            zoneBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -10, 0)
            zoneBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            rgn._lastInline = zoneBtn

            local zoneBrd = EllesmereUI.MakeBorder(zoneBtn, 1, 1, 1, 0.3, EllesmereUI.PanelPP)
            local zoneBg = EllesmereUI.SolidTex(zoneBtn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
            zoneBg:SetAllPoints()
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

        -- Wire up click mappings for preview hit overlays
        wipe(_eabrClickMappings)
        _eabrClickMappings.display = { section = displaySection, target = displayFirstRow }
        _eabrClickMappings.showText = { section = displaySection, target = showTextRow }
        _eabrClickMappings.raidbuff = { section = raidBufHdr, target = raidBufFirstRow }
        _eabrClickMappings.aura = { section = auraHdr, target = auraFirstRow }
        _eabrClickMappings.consumable = { section = consumHdr, target = consumFirstRow }

        -- Per-item mappings: grid cells for individual raid buffs / auras
        for k, cell in pairs(_gridCellRefs) do
            _eabrClickMappings["item:" .. k] = { section = cell, target = cell }
        end
        -- Per-item mappings: consumable toggle rows
        if flaskRow then _eabrClickMappings["item:flask"] = { section = flaskRow, target = flaskRow } end
        if foodRow then _eabrClickMappings["item:food"] = { section = foodRow, target = foodRow } end
        if weaponEnchantRow then _eabrClickMappings["item:weapon_enchant"] = { section = weaponEnchantRow, target = weaponEnchantRow } end
        if runeRow then _eabrClickMappings["item:augment_rune"] = { section = runeRow, target = runeRow } end
        if healthstoneRow then
            _eabrClickMappings["item:healthstone"] = { section = healthstoneRow, target = healthstoneRow }
            _eabrClickMappings["item:inky_black"] = { section = healthstoneRow, target = healthstoneRow }
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Talent Reminders Page
    ---------------------------------------------------------------------------
    local function BuildTalentRemindersPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("auraBuff"))
            or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

        parent._showRowDivider = true

        -- State for the add-reminder form
        local selectedZoneMap = {}  -- [zoneIdx] = true/false
        local selectedTalentSpellID = nil
        local selectedTalentName = nil
        local selectedTalentSource = nil  -- "class" or "spec"

        -- Zone data
        local zones = _G._EABR_TALENT_REMINDER_ZONES or {}

        local zoneByName = {}
        for _, z in ipairs(zones) do
            if z.name then zoneByName[z.name] = z end
        end

        local function GetZoneDisplayName(zoneName)
            if not zoneName or zoneName == "" then return EllesmereUI.L("Unknown") end
            local z = zoneByName[zoneName]
            local name = EllesmereUI.L(zoneName)
            if z and z.type == "raid" then
                return name .. EllesmereUI.L(" (Raid)")
            end
            return name
        end

        -----------------------------------------------------------------------
        --  Talent enumeration helpers (live from C_Traits)
        -----------------------------------------------------------------------
        local function GetAllTalents()
            local talents = {}
            local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
            if not configID then return talents end
            local configInfo = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
            if not configInfo or not configInfo.treeIDs or not configInfo.treeIDs[1] then return talents end
            local treeID = configInfo.treeIDs[1]
            local nodes = C_Traits.GetTreeNodes(treeID)
            if not nodes then return talents end

            local seenSpells = {}
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.ID and nodeInfo.ID > 0
                    and nodeInfo.entryIDs and #nodeInfo.entryIDs > 0
                    and not nodeInfo.subTreeID then
                    for _, entryID in ipairs(nodeInfo.entryIDs) do
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo and defInfo.spellID and not seenSpells[defInfo.spellID] then
                                local spellName = C_Spell.GetSpellName(defInfo.spellID)
                                if spellName and spellName ~= "" then
                                    seenSpells[defInfo.spellID] = true
                                    talents[#talents + 1] = { spellID = defInfo.spellID, name = spellName }
                                end
                            end
                        end
                    end
                end
            end

            table.sort(talents, function(a, b) return a.name < b.name end)
            return talents
        end

        -----------------------------------------------------------------------
        --  SECTION: ADD REMINDER (no header clean layout)
        -----------------------------------------------------------------------

        -- Helper: build comma-separated zone label from selectedZoneMap
        local function GetSelectedZoneLabel()
            local names = {}
            for idx in pairs(selectedZoneMap) do
                if selectedZoneMap[idx] then
                    local z = zones[idx]
                    if z then names[#names + 1] = GetZoneDisplayName(z.name) end
                end
            end
            if #names == 0 then return "Select Dungeon/Raid/PvP Zone" end
            table.sort(names)
            return table.concat(names, ", ")
        end

        -- Wide centered zone dropdown (no label, multi-select checkbox popup)
        local CONTENT_PAD = 45
        local ZONE_DD_W = 350
        local ZONE_DD_H = 38
        y = y - 30  -- 30px space above dropdown
        local ZONE_ROW_H = ZONE_DD_H + 30
        local zoneRow = CreateFrame("Frame", nil, parent)
        local zoneRowW = parent:GetWidth() - CONTENT_PAD * 2
        PP.Size(zoneRow, zoneRowW, ZONE_ROW_H)
        PP.Point(zoneRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

        local zoneDDBtn = CreateFrame("Button", nil, zoneRow)
        PP.Size(zoneDDBtn, ZONE_DD_W, ZONE_DD_H)
        PP.Point(zoneDDBtn, "TOP", zoneRow, "TOP", 0, 0)
        zoneDDBtn:SetFrameLevel(zoneRow:GetFrameLevel() + 1)
        local zoneDDBg = zoneDDBtn:CreateTexture(nil, "BACKGROUND")
        zoneDDBg:SetAllPoints()
        zoneDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        EllesmereUI.MakeBorder(zoneDDBtn, 1, 1, 1, 0.20, EllesmereUI.PanelPP)

        local zoneDDLbl = zoneDDBtn:CreateFontString(nil, "OVERLAY")
        zoneDDLbl:SetFont(fontPath, 13, GetABROptOutline())
        zoneDDLbl:SetTextColor(1, 1, 1, 0.50)
        zoneDDLbl:SetMaxLines(1)
        zoneDDLbl:SetJustifyH("LEFT")
        zoneDDLbl:SetWordWrap(false)
        zoneDDLbl:SetText(EllesmereUI.L("Select Dungeon/Raid/PvP Zone"))

        local zoneArrow = EllesmereUI.MakeDropdownArrow(zoneDDBtn, 14, EllesmereUI.PanelPP)
        zoneDDLbl:SetPoint("LEFT", zoneDDBtn, "LEFT", 14, 0)
        zoneDDLbl:SetPoint("RIGHT", zoneArrow, "LEFT", -5, 0)

        -- Multi-select checkbox popup
        local SEARCH_H = 26
        local ITEM_H = 28
        local zonePopup = CreateFrame("Frame", nil, UIParent)
        zonePopup:SetFrameStrata("FULLSCREEN_DIALOG")
        zonePopup:SetFrameLevel(200)
        zonePopup:SetClampedToScreen(true)
        local popupH = math.min(#zones * ITEM_H + 8, 300) + SEARCH_H + 10
        zonePopup:SetSize(ZONE_DD_W, popupH)
        zonePopup:Hide()

        local popupBg = zonePopup:CreateTexture(nil, "BACKGROUND")
        popupBg:SetAllPoints()
        popupBg:SetColorTexture(0.10, 0.10, 0.12, 0.97)
        EllesmereUI.MakeBorder(zonePopup, 1, 1, 1, 0.12, EllesmereUI.PanelPP)

        -- Search box at top of zone popup
        local zoneSearch = CreateFrame("EditBox", nil, zonePopup)
        zoneSearch:SetSize(ZONE_DD_W - 16, SEARCH_H)
        zoneSearch:SetPoint("TOP", zonePopup, "TOP", 0, -6)
        zoneSearch:SetFrameLevel(zonePopup:GetFrameLevel() + 3)
        zoneSearch:SetFont(fontPath, 11, "")
        zoneSearch:SetTextColor(1, 1, 1, 0.9)
        zoneSearch:SetJustifyH("LEFT")
        zoneSearch:SetAutoFocus(false)
        zoneSearch:SetMaxLetters(30)
        zoneSearch:SetTextInsets(4, 4, 0, 0)
        local zsBg = zoneSearch:CreateTexture(nil, "BACKGROUND")
        zsBg:SetAllPoints()
        zsBg:SetColorTexture(0, 0, 0, 0.4)
        local zsPlaceholder = zoneSearch:CreateFontString(nil, "OVERLAY")
        zsPlaceholder:SetFont(fontPath, 11, "")
        zsPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
        zsPlaceholder:SetPoint("LEFT", zoneSearch, "LEFT", 4, 0)
        zsPlaceholder:SetText(EllesmereUI.L("Search..."))
        zoneSearch:SetScript("OnTextChanged", function(self)
            local t = self:GetText()
            zsPlaceholder:SetShown(t == "")
        end)
        zoneSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        -- Scroll frame for items with smooth scroll + scrollbar
        local sf = CreateFrame("ScrollFrame", nil, zonePopup)
        sf:SetPoint("TOPLEFT", zonePopup, "TOPLEFT", 0, -(SEARCH_H + 10))
        sf:SetPoint("BOTTOMRIGHT", zonePopup, "BOTTOMRIGHT", 0, 4)
        sf:SetFrameLevel(zonePopup:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)
        local child = CreateFrame("Frame", nil, sf)
        child:SetWidth(ZONE_DD_W)
        sf:SetScrollChild(child)

        -- Thin scrollbar track
        local zTrack = CreateFrame("Frame", nil, sf)
        zTrack:SetWidth(4)
        zTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -4)
        zTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 4)
        zTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
        do local t = zTrack:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.02) end

        local zThumb = CreateFrame("Button", nil, zTrack)
        zThumb:SetWidth(4)
        zThumb:SetFrameLevel(zTrack:GetFrameLevel() + 1)
        zThumb:EnableMouse(true)
        zThumb:RegisterForDrag("LeftButton")
        zThumb:SetScript("OnDragStart", function() end)
        zThumb:SetScript("OnDragStop", function() end)
        do local t = zThumb:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.27) end

        local zScrollTarget = 0
        local zSmoothing = false
        local Z_SCROLL_STEP = 40
        local Z_SMOOTH_SPEED = 12
        local zSmoothFrame = CreateFrame("Frame")
        zSmoothFrame:Hide()

        local function UpdateZThumb()
            local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
            if maxScroll <= 0 then zTrack:Hide(); return end
            zTrack:Show()
            local trackH = zTrack:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(20, trackH * ratio)
            zThumb:SetHeight(thumbH)
            local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
            local maxTravel = trackH - thumbH
            zThumb:ClearAllPoints()
            zThumb:SetPoint("TOP", zTrack, "TOP", 0, -(scrollRatio * maxTravel))
        end

        zSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
            zScrollTarget = math.max(0, math.min(maxScroll, zScrollTarget))
            local diff = zScrollTarget - cur
            if math.abs(diff) < 0.3 then
                sf:SetVerticalScroll(zScrollTarget)
                UpdateZThumb()
                zSmoothing = false
                zSmoothFrame:Hide()
                return
            end
            local newScroll = cur + diff * math.min(1, Z_SMOOTH_SPEED * elapsed)
            newScroll = math.max(0, math.min(maxScroll, newScroll))
            sf:SetVerticalScroll(newScroll)
            UpdateZThumb()
        end)

        local function ZSmoothScrollTo(target)
            local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
            zScrollTarget = math.max(0, math.min(maxScroll, target))
            if not zSmoothing then
                zSmoothing = true
                zSmoothFrame:Show()
            end
        end

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
            if maxScroll <= 0 then return end
            local base = zSmoothing and zScrollTarget or self:GetVerticalScroll()
            ZSmoothScrollTo(base - delta * Z_SCROLL_STEP)
        end)
        zonePopup:SetScript("OnMouseWheel", function(_, delta)
            sf:GetScript("OnMouseWheel")(sf, delta)
        end)

        -- Thumb drag
        local zDragging = false
        local zDragStartY, zDragStartScroll
        zThumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            zDragging = true
            zSmoothing = false
            zSmoothFrame:Hide()
            local _, cursorY = GetCursorPosition()
            zDragStartY = cursorY / self:GetEffectiveScale()
            zDragStartScroll = sf:GetVerticalScroll()
        end)
        zThumb:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then zDragging = false end
        end)
        zThumb:SetScript("OnUpdate", function(self)
            if not zDragging then return end
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / self:GetEffectiveScale()
            local dy = zDragStartY - cursorY
            local trackH = zTrack:GetHeight()
            local thumbH = zThumb:GetHeight()
            local maxTravel = trackH - thumbH
            if maxTravel <= 0 then return end
            local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
            local newScroll = zDragStartScroll + (dy / maxTravel) * maxScroll
            newScroll = math.max(0, math.min(maxScroll, newScroll))
            sf:SetVerticalScroll(newScroll)
            UpdateZThumb()
        end)

        local eg = EllesmereUI.ELLESMERE_GREEN or {r=0.047, g=0.824, b=0.624}
        local checkItems = {}
        for i, z in ipairs(zones) do
            local item = CreateFrame("Button", nil, child)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -(i - 1) * ITEM_H)
            item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -(i - 1) * ITEM_H)

            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)

            -- Checkbox square
            local cb = CreateFrame("Frame", nil, item)
            cb:SetSize(14, 14)
            cb:SetPoint("LEFT", item, "LEFT", 10, 0)
            local cbBg = cb:CreateTexture(nil, "BACKGROUND")
            cbBg:SetAllPoints()
            cbBg:SetColorTexture(0.06, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(cb, 1, 1, 1, 0.12, EllesmereUI.PanelPP)
            local cbCheck = cb:CreateTexture(nil, "OVERLAY")
            cbCheck:SetSize(10, 10)
            cbCheck:SetPoint("CENTER")
            cbCheck:SetColorTexture(eg.r, eg.g, eg.b, 1)
            cbCheck:Hide()
            item._cbCheck = cbCheck

            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 11, GetABROptOutline())
            lbl:SetTextColor(0.75, 0.75, 0.78, 1)
            lbl:SetPoint("LEFT", cb, "RIGHT", 8, 0)
            lbl:SetPoint("RIGHT", item, "RIGHT", -8, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetText(GetZoneDisplayName(z.name))

            local function UpdateCheck()
                cbCheck:SetShown(selectedZoneMap[i] == true)
            end
            UpdateCheck()

            item:SetScript("OnClick", function()
                selectedZoneMap[i] = not selectedZoneMap[i]
                UpdateCheck()
                zoneDDLbl:SetText(GetSelectedZoneLabel())
            end)
            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, 0.08)
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(0.75, 0.75, 0.78, 1)
                hl:SetColorTexture(1, 1, 1, 0)
            end)
            checkItems[i] = item
            item._zoneName = z.name
        end
        child:SetHeight(math.max(1, #zones * ITEM_H))

        -- Wire zone search filtering
        zoneSearch:SetScript("OnTextChanged", function(self)
            local t = strlower(strtrim(self:GetText()))
            zsPlaceholder:SetShown(t == "")
            local visIdx = 0
            for idx, item in ipairs(checkItems) do
                if t == "" or strfind(strlower(item._zoneName), t, 1, true) then
                    item:Show()
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -visIdx * ITEM_H)
                    item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -visIdx * ITEM_H)
                    visIdx = visIdx + 1
                else
                    item:Hide()
                end
            end
            child:SetHeight(math.max(1, visIdx * ITEM_H))
            scrollOffset = 0
            sf:SetVerticalScroll(0)
        end)

        zonePopup:SetScript("OnShow", function()
            zonePopup:ClearAllPoints()
            zonePopup:SetPoint("TOPLEFT", zoneDDBtn, "BOTTOMLEFT", 0, -2)
            zoneSearch:SetText("")
            zoneSearch:SetFocus()
            zScrollTarget = 0
            zSmoothing = false
            zSmoothFrame:Hide()
            sf:SetVerticalScroll(0)
            UpdateZThumb()
            -- Refresh checks
            for i, item in ipairs(checkItems) do
                item._cbCheck:SetShown(selectedZoneMap[i] == true)
            end
        end)
        -- Close when clicking outside
        zonePopup:SetScript("OnUpdate", function()
            if not zonePopup:IsMouseOver() and not zoneDDBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                zonePopup:Hide()
            end
        end)

        zoneDDBtn:SetScript("OnClick", function()
            if zonePopup:IsShown() then zonePopup:Hide() else zonePopup:Show() end
        end)
        zoneDDBtn:SetScript("OnEnter", function()
            zoneDDBg:SetColorTexture(0.095, 0.143, 0.181, 1)
        end)
        zoneDDBtn:SetScript("OnLeave", function()
            zoneDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        end)

        y = y - ZONE_ROW_H

        -- Row 2: Single talent dropdown
        local allTalents = GetAllTalents()

        -- Talent dropdown: single centered
        local TALENT_DD_W = 350
        local TALENT_DD_H = 30
        local TALENT_LABEL_H = 16
        local TALENT_GAP_Y = 6
        local TALENT_ROW_H = TALENT_LABEL_H + TALENT_GAP_Y + TALENT_DD_H + 12
        local talentRow = CreateFrame("Frame", nil, parent)
        local talentRowW = parent:GetWidth() - CONTENT_PAD * 2
        PP.Size(talentRow, talentRowW, TALENT_ROW_H)
        PP.Point(talentRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

        local talentStartX = (talentRowW - TALENT_DD_W) / 2

        -- Helper: build a talent dropdown with search inside the popup
        local function MakeTalentDropdown(parentRow, xOff, labelText, allTalents)
            -- Label
            local lbl = parentRow:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 11, GetABROptOutline())
            lbl:SetTextColor(EllesmereUI.TEXT_SECTION_R or 0.45, EllesmereUI.TEXT_SECTION_G or 0.50, EllesmereUI.TEXT_SECTION_B or 0.55, EllesmereUI.TEXT_SECTION_A or 1)
            PP.Point(lbl, "TOP", parentRow, "TOPLEFT", xOff + TALENT_DD_W / 2, 0)
            lbl:SetText(labelText)

            -- Button (styled like zone dropdown)
            local btn = CreateFrame("Button", nil, parentRow)
            PP.Size(btn, TALENT_DD_W, TALENT_DD_H)
            PP.Point(btn, "TOPLEFT", parentRow, "TOPLEFT", xOff, -(TALENT_LABEL_H + TALENT_GAP_Y))
            btn:SetFrameLevel(parentRow:GetFrameLevel() + 1)
            local btnBg = btn:CreateTexture(nil, "BACKGROUND")
            btnBg:SetAllPoints()
            btnBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
            EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.20, EllesmereUI.PanelPP)
            local btnLbl = btn:CreateFontString(nil, "OVERLAY")
            btnLbl:SetFont(fontPath, 13, GetABROptOutline())
            btnLbl:SetTextColor(1, 1, 1, 0.50)
            btnLbl:SetMaxLines(1)
            btnLbl:SetJustifyH("LEFT")
            btnLbl:SetWordWrap(false)
            btnLbl:SetText(EllesmereUI.L("Select a talent..."))
            local arrow = EllesmereUI.MakeDropdownArrow(btn, 12, EllesmereUI.PanelPP)
            btnLbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
            btnLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
            btn:SetScript("OnEnter", function() btnBg:SetColorTexture(0.095, 0.143, 0.181, 1) end)
            btn:SetScript("OnLeave", function() btnBg:SetColorTexture(0.075, 0.113, 0.141, 0.9) end)

            -- Popup with search
            local T_ITEM_H = 26
            local popupH = math.min(#allTalents * T_ITEM_H + 8, 250) + SEARCH_H + 10
            local popup = CreateFrame("Frame", nil, UIParent)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(200)
            popup:SetClampedToScreen(true)
            popup:SetSize(TALENT_DD_W, popupH)
            popup:Hide()
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints()
            popBg:SetColorTexture(0.10, 0.10, 0.12, 0.97)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.12, EllesmereUI.PanelPP)

            -- Search
            local search = CreateFrame("EditBox", nil, popup)
            search:SetSize(TALENT_DD_W - 16, SEARCH_H)
            search:SetPoint("TOP", popup, "TOP", 0, -6)
            search:SetFrameLevel(popup:GetFrameLevel() + 3)
            search:SetFont(fontPath, 11, "")
            search:SetTextColor(1, 1, 1, 0.9)
            search:SetJustifyH("LEFT")
            search:SetAutoFocus(false)
            search:SetMaxLetters(30)
            search:SetTextInsets(4, 4, 0, 0)
            local sBg = search:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0, 0, 0, 0.4)
            local sPh = search:CreateFontString(nil, "OVERLAY")
            sPh:SetFont(fontPath, 11, "")
            sPh:SetTextColor(0.5, 0.5, 0.5, 0.6)
            sPh:SetPoint("LEFT", search, "LEFT", 4, 0)
            sPh:SetText(EllesmereUI.L("Search..."))
            search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            -- Scroll frame
            local sf = CreateFrame("ScrollFrame", nil, popup)
            sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -(SEARCH_H + 10))
            sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 4)
            sf:SetFrameLevel(popup:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            local child = CreateFrame("Frame", nil, sf)
            child:SetWidth(TALENT_DD_W)
            sf:SetScrollChild(child)

            -- Items
            local items = {}
            for i, t in ipairs(allTalents) do
                local item = CreateFrame("Button", nil, child)
                item:SetHeight(T_ITEM_H)
                item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -(i - 1) * T_ITEM_H)
                item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -(i - 1) * T_ITEM_H)
                local hl = item:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0)
                local iLbl = item:CreateFontString(nil, "OVERLAY")
                iLbl:SetFont(fontPath, 11, GetABROptOutline())
                iLbl:SetTextColor(0.75, 0.75, 0.78, 1)
                iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                iLbl:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                iLbl:SetJustifyH("LEFT")
                iLbl:SetWordWrap(false)
                iLbl:SetText(t.name)
                item._talentName = t.name
                item._spellID = t.spellID
                item:SetScript("OnClick", function()
                    selectedTalentSpellID = t.spellID
                    selectedTalentName = t.name
                    selectedTalentSource = nil
                    btnLbl:SetText(t.name)
                    btnLbl:SetTextColor(1, 1, 1, 0.9)
                    popup:Hide()
                end)
                item:SetScript("OnEnter", function() iLbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, 0.08) end)
                item:SetScript("OnLeave", function() iLbl:SetTextColor(0.75, 0.75, 0.78, 1); hl:SetColorTexture(1, 1, 1, 0) end)
                items[i] = item
            end
            child:SetHeight(math.max(1, #allTalents * T_ITEM_H))

            -- Search filter
            search:SetScript("OnTextChanged", function(self)
                local t = strlower(strtrim(self:GetText()))
                sPh:SetShown(t == "")
                local visIdx = 0
                for _, item in ipairs(items) do
                    if t == "" or strfind(strlower(item._talentName), t, 1, true) then
                        item:Show()
                        item:ClearAllPoints()
                        item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -visIdx * T_ITEM_H)
                        item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -visIdx * T_ITEM_H)
                        visIdx = visIdx + 1
                    else
                        item:Hide()
                    end
                end
                child:SetHeight(math.max(1, visIdx * T_ITEM_H))
                tScrollTarget = 0
                tSmoothing = false
                if tSmoothFrame then tSmoothFrame:Hide() end
                sf:SetVerticalScroll(0)
                if UpdateTThumb then UpdateTThumb() end
            end)

            -- Scrollbar + smooth scroll
            local tTrack = CreateFrame("Frame", nil, sf)
            tTrack:SetWidth(4)
            tTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -4)
            tTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 4)
            tTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
            do local t2 = tTrack:CreateTexture(nil, "BACKGROUND"); t2:SetAllPoints(); t2:SetColorTexture(1, 1, 1, 0.02) end

            local tThumb = CreateFrame("Button", nil, tTrack)
            tThumb:SetWidth(4)
            tThumb:SetFrameLevel(tTrack:GetFrameLevel() + 1)
            tThumb:EnableMouse(true)
            tThumb:RegisterForDrag("LeftButton")
            tThumb:SetScript("OnDragStart", function() end)
            tThumb:SetScript("OnDragStop", function() end)
            do local t2 = tThumb:CreateTexture(nil, "ARTWORK"); t2:SetAllPoints(); t2:SetColorTexture(1, 1, 1, 0.27) end

            local tScrollTarget = 0
            local tSmoothing = false
            local T_SCROLL_STEP = 40
            local T_SMOOTH_SPEED = 12
            local tSmoothFrame = CreateFrame("Frame")
            tSmoothFrame:Hide()

            local function UpdateTThumb()
                local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
                if maxScroll <= 0 then tTrack:Hide(); return end
                tTrack:Show()
                local trackH = tTrack:GetHeight()
                local visH = sf:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(20, trackH * ratio)
                tThumb:SetHeight(thumbH)
                local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
                local maxTravel = trackH - thumbH
                tThumb:ClearAllPoints()
                tThumb:SetPoint("TOP", tTrack, "TOP", 0, -(scrollRatio * maxTravel))
            end

            tSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
                tScrollTarget = math.max(0, math.min(maxScroll, tScrollTarget))
                local diff = tScrollTarget - cur
                if math.abs(diff) < 0.3 then
                    sf:SetVerticalScroll(tScrollTarget)
                    UpdateTThumb()
                    tSmoothing = false
                    tSmoothFrame:Hide()
                    return
                end
                local newScroll = cur + diff * math.min(1, T_SMOOTH_SPEED * elapsed)
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateTThumb()
            end)

            local function TSmoothScrollTo(target)
                local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
                tScrollTarget = math.max(0, math.min(maxScroll, target))
                if not tSmoothing then
                    tSmoothing = true
                    tSmoothFrame:Show()
                end
            end

            sf:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
                if maxScroll <= 0 then return end
                local base = tSmoothing and tScrollTarget or self:GetVerticalScroll()
                TSmoothScrollTo(base - delta * T_SCROLL_STEP)
            end)
            popup:SetScript("OnMouseWheel", function(_, delta)
                sf:GetScript("OnMouseWheel")(sf, delta)
            end)

            -- Thumb drag
            local tDragging = false
            local tDragStartY, tDragStartScroll
            tThumb:SetScript("OnMouseDown", function(self2, button)
                if button ~= "LeftButton" then return end
                tDragging = true
                tSmoothing = false
                tSmoothFrame:Hide()
                local _, cursorY = GetCursorPosition()
                tDragStartY = cursorY / self2:GetEffectiveScale()
                tDragStartScroll = sf:GetVerticalScroll()
            end)
            tThumb:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then tDragging = false end
            end)
            tThumb:SetScript("OnUpdate", function(self2)
                if not tDragging then return end
                local _, cursorY = GetCursorPosition()
                cursorY = cursorY / self2:GetEffectiveScale()
                local dy = tDragStartY - cursorY
                local trackH = tTrack:GetHeight()
                local thumbH = tThumb:GetHeight()
                local maxTravel = trackH - thumbH
                if maxTravel <= 0 then return end
                local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
                local newScroll = tDragStartScroll + (dy / maxTravel) * maxScroll
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateTThumb()
            end)

            -- Show/hide
            popup:SetScript("OnShow", function()
                popup:ClearAllPoints()
                popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
                search:SetText("")
                search:SetFocus()
                tScrollTarget = 0
                tSmoothing = false
                tSmoothFrame:Hide()
                sf:SetVerticalScroll(0)
                UpdateTThumb()
            end)
            popup:SetScript("OnUpdate", function()
                if not popup:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    popup:Hide()
                end
            end)
            btn:SetScript("OnClick", function()
                if popup:IsShown() then popup:Hide() else popup:Show() end
            end)
            btn:HookScript("OnHide", function() popup:Hide() end)

            return btn, btnLbl
        end

        -- Single talent dropdown
        local talentDDBtn, talentDDLbl = MakeTalentDropdown(
            talentRow, talentStartX, "Select Talent",
            allTalents)

        y = y - TALENT_ROW_H

        -- "Add Reminder" button (styled like Done button)
        _, h = W:Spacer(parent, y, 10); y = y - h

        local addBtnFrame = CreateFrame("Frame", nil, parent)
        PP.Size(addBtnFrame, parent:GetWidth() or 400, 36)
        PP.Point(addBtnFrame, "TOPLEFT", parent, "TOPLEFT", 0, y)

        local addBtn = CreateFrame("Button", nil, addBtnFrame)
        addBtn:SetSize(160, 36)
        addBtn:SetPoint("CENTER", addBtnFrame, "CENTER", 0, 0)

        local DARK_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }
        local addBtnBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        addBtnBg:SetAllPoints()

        local eg = EllesmereUI.ELLESMERE_GREEN or {r=0.047, g=0.824, b=0.624}
        local addBtnBorder = EllesmereUI.MakeBorder(addBtn, eg.r, eg.g, eg.b, 0.7, EllesmereUI.PanelPP)

        local addBtnText = addBtn:CreateFontString(nil, "OVERLAY")
        addBtnText:SetPoint("CENTER")
        addBtnText:SetFont(fontPath, 13, GetABROptOutline())
        addBtnText:SetTextColor(eg.r, eg.g, eg.b, 0.7)
        addBtnText:SetText(EllesmereUI.L("Add Reminder"))

        do
            local lerp = EllesmereUI.lerp
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                addBtnText:SetTextColor(eg.r, eg.g, eg.b, lerp(0.7, 1, t))
                addBtnBorder:SetColor(eg.r, eg.g, eg.b, lerp(0.7, 1, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            addBtn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            addBtn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        end

        y = y - 36

        -----------------------------------------------------------------------
        --  Red border pulse animation for validation
        -----------------------------------------------------------------------
        local pulseTarget = nil
        local pulseAG = nil

        local function PulseRedBorder(targetRow)
            if not targetRow then return end
            -- Create a red border overlay on the row
            if not targetRow._redPulse then
                local rf = CreateFrame("Frame", nil, targetRow)
                rf:SetAllPoints()
                rf:SetFrameLevel(targetRow:GetFrameLevel() + 10)
                local border = EllesmereUI.MakeBorder(rf, 1, 0.2, 0.2, 1, EllesmereUI.PanelPP)
                rf._border = border
                targetRow._redPulse = rf
            end
            local rf = targetRow._redPulse
            rf:Show()
            rf:SetAlpha(1)
            -- Fade out after 1.5 seconds
            local elapsed = 0
            rf:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed < 0.8 then
                    -- Pulse: oscillate alpha
                    local a = 0.5 + 0.5 * math.sin(elapsed * 10)
                    self:SetAlpha(a)
                elseif elapsed < 1.5 then
                    self:SetAlpha(math.max(0, 1 - (elapsed - 0.8) / 0.7))
                else
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                end
            end)
        end

        -----------------------------------------------------------------------
        --  Reminder list (dynamic, rebuilt on add/remove)
        -----------------------------------------------------------------------
        local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
        local listContainer = CreateFrame("Frame", nil, parent)
        listContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        listContainer:SetSize(parent:GetWidth() or 400, 1)  -- height grows dynamically

        local listRows = {}
        local listRowCount = 0  -- manual alternating row counter

        local function RebuildReminderList()
            -- Clear existing rows
            for _, row in ipairs(listRows) do row:Hide() end
            wipe(listRows)
            listRowCount = 0

            local p = DB()
            if not p then return 0 end
            local reminders = p.talentReminders or {}

            if #reminders == 0 then
                listRowCount = listRowCount + 1
                local ROW_H = 50
                local CONTENT_PAD = 45
                local totalW = listContainer:GetWidth() - CONTENT_PAD * 2
                local emptyRow = CreateFrame("Frame", nil, listContainer)
                PP.Size(emptyRow, totalW, ROW_H)
                PP.Point(emptyRow, "TOPLEFT", listContainer, "TOPLEFT", CONTENT_PAD, 0)
                local alpha = (listRowCount % 2 == 0) and 0.2 or 0.1
                local bg = emptyRow:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, alpha)
                local div = emptyRow:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetWidth(1)
                PP.Point(div, "TOP", emptyRow, "TOP", 0, 0)
                PP.Point(div, "BOTTOM", emptyRow, "BOTTOM", 0, 0)
                local emptyFS = emptyRow:CreateFontString(nil, "OVERLAY")
                emptyFS:SetFont(fontPath, 13, GetABROptOutline())
                emptyFS:SetTextColor(0.5, 0.5, 0.5, 1)
                emptyFS:SetPoint("CENTER")
                emptyFS:SetText(EllesmereUI.L("No talent reminders configured"))
                emptyRow:Show()
                listRows[1] = emptyRow
                listContainer:SetHeight(ROW_H)
                return ROW_H
            end

            local ROW_H = 50
            local SIDE_PAD = 20
            local CONTENT_PAD = 45
            local totalW = listContainer:GetWidth() - CONTENT_PAD * 2
            local totalH = 0

            -- Helper: create a DualRow-styled frame
            local function MakeListRow(yOff)
                listRowCount = listRowCount + 1
                local row = CreateFrame("Frame", nil, listContainer)
                PP.Size(row, totalW, ROW_H)
                PP.Point(row, "TOPLEFT", listContainer, "TOPLEFT", CONTENT_PAD, yOff)
                -- Alternating row background
                local alpha = (listRowCount % 2 == 0) and 0.2 or 0.1
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, alpha)
                -- Center divider
                local div = row:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetWidth(1)
                PP.Point(div, "TOP", row, "TOP", 0, 0)
                PP.Point(div, "BOTTOM", row, "BOTTOM", 0, 0)
                return row
            end

            -- Data rows (single row per reminder)
            local Tex = function(id) return _G._EABR_Tex and _G._EABR_Tex(id) or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400 end
            local eg2 = EllesmereUI.ELLESMERE_GREEN or {r=0.047, g=0.824, b=0.624}
            local ICON_SIZE = 14
            for idx, reminder in ipairs(reminders) do
                local row = MakeListRow(-totalH)
                local capturedIdx = idx

                -- === LEFT HALF: delete (—) | zone name | talent name + icon ===

                -- Delete button (far left)
                local delBtn = CreateFrame("Button", nil, row)
                delBtn:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
                PP.Point(delBtn, "LEFT", row, "LEFT", SIDE_PAD - 6, 0)
                delBtn:SetFrameLevel(row:GetFrameLevel() + 5)
                local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                PP.Size(delIcon, ICON_SIZE, ICON_SIZE)
                PP.Point(delIcon, "CENTER", delBtn, "CENTER", 0, 0)
                if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
                delIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
                delBtn:SetAlpha(0.75)
                delBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
                delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.75) end)
                delBtn:SetScript("OnClick", function()
                    local p2 = DB()
                    if not p2 then return end
                    table.remove(p2.talentReminders, capturedIdx)
                    RebuildReminderList()
                    RefreshAll()
                    if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
                end)

                -- Zone name (after delete icon, truncated to fit left portion)
                local zoneStr
                if reminder.zoneNames and #reminder.zoneNames > 0 then
                    local names = {}
                    for _, zoneName in ipairs(reminder.zoneNames) do
                        names[#names + 1] = GetZoneDisplayName(zoneName)
                    end
                    zoneStr = table.concat(names, ", ")
                else
                    zoneStr = GetZoneDisplayName(reminder.zoneName)
                end
                local zoneFS = row:CreateFontString(nil, "OVERLAY")
                zoneFS:SetFont(fontPath, 14, GetABROptOutline())
                zoneFS:SetTextColor(1, 1, 1, 1)
                zoneFS:SetPoint("LEFT", delBtn, "RIGHT", 6, 0)
                zoneFS:SetJustifyH("LEFT")
                zoneFS:SetWordWrap(false)
                zoneFS:SetMaxLines(1)

                -- Talent name + icon (right portion of left half, anchored to center)
                local spellName = reminder.spellName or "Unknown"
                local spellFS = row:CreateFontString(nil, "OVERLAY")
                spellFS:SetFont(fontPath, 14, GetABROptOutline())
                spellFS:SetTextColor(1, 1, 1, 1)
                spellFS:SetJustifyH("RIGHT")
                spellFS:SetWordWrap(false)
                spellFS:SetMaxLines(1)
                spellFS:SetText(spellName)

                local spellIcon = row:CreateTexture(nil, "ARTWORK")
                spellIcon:SetSize(22, 22)
                spellIcon:SetPoint("RIGHT", row, "CENTER", -SIDE_PAD, 0)
                spellIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                spellIcon:SetTexture(Tex(reminder.spellID))

                spellFS:SetPoint("RIGHT", spellIcon, "LEFT", -6, 0)

                -- Constrain zone text: from after delete to before talent name
                zoneFS:SetPoint("RIGHT", spellFS, "LEFT", -8, 0)
                zoneFS:SetText(zoneStr)

                -- === RIGHT HALF: "Show 'Not Needed' Reminder" label + checkbox ===

                -- Hit area covers the entire right half of the row
                local toggleHit = CreateFrame("Button", nil, row)
                toggleHit:SetPoint("LEFT", row, "CENTER", 0, 0)
                toggleHit:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
                toggleHit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                toggleHit:SetFrameLevel(row:GetFrameLevel() + 3)

                local toggleLabel = row:CreateFontString(nil, "OVERLAY")
                toggleLabel:SetFont(fontPath, 14, GetABROptOutline())
                toggleLabel:SetPoint("LEFT", row, "CENTER", SIDE_PAD, 0)
                toggleLabel:SetText(EllesmereUI.L("Show 'Not Needed' Reminder"))

                -- Checkbox (far right of right half)
                local toggleBox = CreateFrame("Frame", nil, row)
                toggleBox:SetSize(18, 18)
                toggleBox:SetPoint("RIGHT", row, "RIGHT", -SIDE_PAD, 0)
                local toggleBg = toggleBox:CreateTexture(nil, "BACKGROUND")
                toggleBg:SetAllPoints()
                toggleBg:SetColorTexture(0.06, 0.06, 0.08, 1)
                EllesmereUI.MakeBorder(toggleBox, 1, 1, 1, 0.12, EllesmereUI.PanelPP)
                local toggleCheck = toggleBox:CreateTexture(nil, "OVERLAY")
                toggleCheck:SetSize(12, 12)
                toggleCheck:SetPoint("CENTER")
                toggleCheck:SetColorTexture(eg2.r, eg2.g, eg2.b, 1)

                local isChecked = reminder.showNotNeeded == true
                toggleCheck:SetShown(isChecked)

                local function ApplyToggleVisual(checked, hovered)
                    if checked then
                        toggleLabel:SetTextColor(1, 1, 1, 1)
                    elseif hovered then
                        toggleLabel:SetTextColor(1, 1, 1, 0.8)
                    else
                        toggleLabel:SetTextColor(1, 1, 1, 0.4)
                    end
                end
                ApplyToggleVisual(isChecked, false)

                local function DoToggle()
                    local p2 = DB()
                    if not p2 or not p2.talentReminders[capturedIdx] then return end
                    p2.talentReminders[capturedIdx].showNotNeeded = not p2.talentReminders[capturedIdx].showNotNeeded
                    local nowChecked = p2.talentReminders[capturedIdx].showNotNeeded == true
                    toggleCheck:SetShown(nowChecked)
                    ApplyToggleVisual(nowChecked, true)
                    RefreshAll()
                    if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
                end

                toggleHit:SetScript("OnClick", DoToggle)
                toggleHit:SetScript("OnEnter", function()
                    local checked = false
                    local p2 = DB()
                    if p2 and p2.talentReminders[capturedIdx] then checked = p2.talentReminders[capturedIdx].showNotNeeded == true end
                    ApplyToggleVisual(checked, true)
                end)
                toggleHit:SetScript("OnLeave", function()
                    local checked = false
                    local p2 = DB()
                    if p2 and p2.talentReminders[capturedIdx] then checked = p2.talentReminders[capturedIdx].showNotNeeded == true end
                    ApplyToggleVisual(checked, false)
                end)

                -- Tooltip only on the label itself
                local tooltipHit = CreateFrame("Frame", nil, row)
                tooltipHit:SetPoint("LEFT", toggleLabel, "LEFT", 0, 0)
                tooltipHit:SetPoint("RIGHT", toggleLabel, "RIGHT", 0, 0)
                tooltipHit:SetPoint("TOP", toggleLabel, "TOP", 0, 4)
                tooltipHit:SetPoint("BOTTOM", toggleLabel, "BOTTOM", 0, -4)
                tooltipHit:SetFrameLevel(toggleHit:GetFrameLevel() + 1)
                tooltipHit:EnableMouse(true)
                tooltipHit:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(toggleLabel, "Enable this to display a reminder to untalent\nout of this when it is not needed\n(all other dungeons/raids not selected).")
                end)
                tooltipHit:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                end)

                listRows[#listRows + 1] = row
                totalH = totalH + ROW_H
            end

            listContainer:SetHeight(totalH)
            return totalH
        end

        -- Add button click handler
        addBtn:SetScript("OnClick", function()
            -- Validate: must have at least one zone selected
            local hasZone = false
            for idx, sel in pairs(selectedZoneMap) do
                if sel then hasZone = true; break end
            end
            if not hasZone then
                PulseRedBorder(zoneDDBtn)
                return
            end

            -- Validate: must have a talent selected
            if not selectedTalentSpellID or selectedTalentSpellID == 0 then
                PulseRedBorder(classDDBtn)
                PulseRedBorder(specDDBtn)
                return
            end

            local p = DB()
            if not p then return end
            if not p.talentReminders then p.talentReminders = {} end

            -- Collect selected zone IDs and names
            local selZoneNames = {}
            for idx, sel in pairs(selectedZoneMap) do
                if sel then
                    local z = zones[idx]
                    if z then
                        selZoneNames[#selZoneNames + 1] = z.name
                    end
                end
            end
            table.sort(selZoneNames)

            -- Check for existing reminder with same spellID: merge zones
            for _, r in ipairs(p.talentReminders) do
                if r.spellID == selectedTalentSpellID then
                    -- Merge new zones into existing reminder
                    local existingSet = {}
                    for _, zn in ipairs(r.zoneNames or {}) do existingSet[zn] = true end
                    local added = 0
                    for _, zn in ipairs(selZoneNames) do
                        if not existingSet[zn] then
                            r.zoneNames[#r.zoneNames + 1] = zn
                            added = added + 1
                        end
                    end
                    table.sort(r.zoneNames)
                    -- Reset selection
                    wipe(selectedZoneMap)
                    selectedTalentSpellID = nil
                    selectedTalentName = nil
                    selectedTalentSource = nil
                    zoneDDLbl:SetText(EllesmereUI.L("Select Dungeon/Raid/PvP Zone"))
                    if talentDDLbl then talentDDLbl:SetText(EllesmereUI.L("Select a talent...")); talentDDLbl:SetTextColor(1, 1, 1, 0.50) end
                    RebuildReminderList()
                    RefreshAll()
                    if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
                    return
                end
            end

            local _, playerClass = UnitClass("player")
            p.talentReminders[#p.talentReminders + 1] = {
                zoneNames = selZoneNames,
                spellID = selectedTalentSpellID,
                spellName = selectedTalentName,
                showNotNeeded = false,
                class = playerClass,
            }

            -- Reset selection
            wipe(selectedZoneMap)
            selectedTalentSpellID = nil
            selectedTalentName = nil
            selectedTalentSource = nil
            zoneDDLbl:SetText(EllesmereUI.L("Select Dungeon/Raid/PvP Zone"))
            if talentDDLbl then talentDDLbl:SetText(EllesmereUI.L("Select a talent...")); talentDDLbl:SetTextColor(1, 1, 1, 0.50) end

            RebuildReminderList()
            RefreshAll()
            if _G._EABR_TR_RequestRefresh then _G._EABR_TR_RequestRefresh() end
        end)

        -- Spacer before list
        _, h = W:Spacer(parent, y, 15); y = y - h

        -- Section header for the list
        _, h = W:SectionHeader(parent, "ACTIVE REMINDERS", y); y = y - h

        -- Position the list container
        listContainer:ClearAllPoints()
        listContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

        local listH = RebuildReminderList()
        y = y - listH

        _, h = W:Spacer(parent, y, 20); y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIAuraBuffReminders", {
        title       = "Auras, Buffs & Consumables",
        description = "AuraBuff Reminders: Raid Buffs, Auras, and Consumables.",
        pages       = { PAGE_REMINDERS, PAGE_TALENTS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_REMINDERS then
                return BuildRemindersPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TALENTS then
                return BuildTalentRemindersPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_REMINDERS then
                return _previewHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_REMINDERS then
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
        onReset = function()
            if _G._EABR_AceDB then
                _G._EABR_AceDB:ResetProfile()
            end
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
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
