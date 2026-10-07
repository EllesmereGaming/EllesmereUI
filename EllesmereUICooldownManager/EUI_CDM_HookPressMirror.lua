if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookPressMirror.lua
--
--  Mirror Key Presses, and the queued-attack highlight (WoW Forever), both
--  drawn like the action bars' own buttons.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local cdmBarIcons = ns.cdmBarIcons
local _ecmeFC = ns._ecmeFC
local GetTime = GetTime

-------------------------------------------------------------------------------
--  Mirror Key Presses  (per-bar: barData.pressMirror -- set in CDM Bars > Extras)
--
--  Show the action-button "pushed down" look on a CDM bar icon whenever you
--  press that ability's keybind, even while on cooldown. Hooks the
--  action-button key-down path (ActionButtonDown/MultiActionButtonDown), which
--  fires on the physical press regardless of cooldown or the cast-on-key-
--  down/up CVar. Pushed texture + colour are read live from the EllesmereUI
--  action bars settings, so the CDM press matches real buttons (falling back
--  to a border-cropped Blizzard depress texture if that module isn't present).
--  On a custom-shape bar the press is masked to the shape, so a hexagon icon
--  flashes a hexagon rather than the full square it sits in.
--  Per-frame data lives in an external weak-keyed table.
-------------------------------------------------------------------------------
do
    local AB_MEDIA      = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
    local AB_HIGHLIGHT  = { AB_MEDIA .. "highlight-2.png", AB_MEDIA .. "highlight-3.png", AB_MEDIA .. "highlight-4.png" }
    local DEPRESS_TEX   = "Interface\\Buttons\\UI-Quickslot-Depress"
    local CHECKED_TEX   = "Interface\\Buttons\\CheckButtonHilight"
    local CHECKED_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
    local DEPRESS_INSET = 0.14   -- crop the beveled border off the fallback texture
    local MIN_VISIBLE   = 0.05   -- floor so ultra-fast taps still show a press
    local MAX_HOLD      = 2.0    -- safety: never leave an icon stuck "pressed"

    local _pushOverlay = setmetatable({}, { __mode = "k" })  -- [icon] = overlay frame
    local _held  = {}   -- [buttonFrame] = { overlays = {..}, keys = {..}, t = GetTime() }
    local _heldN = 0
    local _poll  = ns.TakeShell()
    _poll:Hide()

    -- Read the action bars' pushed settings live so the CDM press matches them.
    local function GetABProfile()
        local L = EllesmereUI and EllesmereUI.Lite
        if not (L and L.GetAddon) then return nil end
        local ok, eab = pcall(L.GetAddon, "EllesmereUIActionBars", true)
        if ok and eab and eab.db then return eab.db.profile end
        return nil
    end

    -- Style tex to match the bars' pushed look. Returns false when pushed is set
    -- to "None" (so the CDM press mirrors that), "border" for border mode, true otherwise.
    local function StylePush(tex)
        local p = GetABProfile()
        if p then
            local pType = p.pushedTextureType or 2
            local c = p.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604 }
            local cr, cg, cb = c.r, c.g, c.b
            if p.pushedUseClassColor then
                local _, ct = UnitClass("player")
                if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
            end
            tex:SetTexCoord(0, 1, 0, 1)
            if p.useClassicStyle then
                -- Classic WoW UI action bars: the vanilla pushed slot, uncropped.
                tex:SetAtlas(nil)
                tex:SetTexture(DEPRESS_TEX)
                tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
                return true
            elseif p.useBlizzardStyle then
                -- The bars' own pressed art: the retail sheet on WoW Forever
                -- (EllesmereUI.StockAtlas) unless the bars wear its own look.
                if EllesmereUI.IS_FOREVER == true and p.useForeverStyle == true then
                    tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
                else
                    EllesmereUI.StockAtlas(tex, "UI-HUD-ActionBar-IconFrame-Down", false)
                end
                tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
                return true
            elseif pType == 6 then
                tex:SetAlpha(0); return false
            elseif pType == 5 then
                tex:SetAlpha(0)
                return "border", cr, cg, cb, p.pushedBorderSize or 4
            end
            tex:SetAlpha(1)
            if pType <= 3 then
                tex:SetAtlas(nil); tex:SetTexture(AB_HIGHLIGHT[pType] or AB_HIGHLIGHT[2]); tex:SetVertexColor(cr, cg, cb, 1)
            elseif pType == 4 then
                tex:SetColorTexture(cr, cg, cb, 0.35)
            end
            return true
        end
        -- Fallback: interior of the Blizzard depress texture (border cropped off).
        tex:SetAtlas(nil)
        tex:SetTexture(DEPRESS_TEX)
        tex:SetTexCoord(DEPRESS_INSET, 1 - DEPRESS_INSET, DEPRESS_INSET, 1 - DEPRESS_INSET)
        tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
        return true
    end

    -- Style tex as the bars' spell cast highlight (their CheckedTexture, drawn
    -- additive in every look): EllesmereUI's highlight art, the Classic button
    -- art or Blizzard's own (WoW Forever's while the bars wear that look), and
    -- nothing while Show Highlight on Spell Cast is off. Show as Border swaps
    -- the fill only on bars with a textured border, so a fill stands here.
    -- Without the action bars: Blizzard's own art, as its bars show it.
    local function StyleChecked(tex)
        local p = GetABProfile()
        if p and p.showCastHighlight == false then tex:SetAlpha(0); return false end
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
        tex:SetBlendMode("ADD")
        if not p then
            tex:SetAtlas(CHECKED_ATLAS, false)
        elseif p.useClassicStyle then
            tex:SetAtlas(nil); tex:SetTexture(CHECKED_TEX)
        elseif p.useBlizzardStyle then
            if EllesmereUI.IS_FOREVER == true and p.useForeverStyle == true then
                tex:SetAtlas(CHECKED_ATLAS, false)
            else
                EllesmereUI.StockAtlas(tex, CHECKED_ATLAS, false)
            end
        else
            tex:SetAtlas(nil); tex:SetTexture(AB_HIGHLIGHT[1])
        end
        return true
    end

    local function EnsureBorderEdges(ov)
        if ov._borderEdges then return ov._borderEdges end
        local edges = {}
        for j = 1, 4 do
            local t = ov:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(1, 1, 1, 1)
            t:Hide()
            edges[j] = t
        end
        ov._borderEdges = edges
        return edges
    end

    -- Custom shape of a CDM icon (hexagon/circle/...), or nil for a square one.
    -- A square press drawn over a shaped icon spills past the shape, so the
    -- overlay has to follow it. We reuse the icon's own shapeMask -- masking is
    -- screen-space and the overlay covers the same rect -- exactly like the
    -- fake-active overlay does (ns.ApplyShapeToOverlay). none/cropped return
    -- nil: their icon art fills the frame rect, so a square press is correct.
    local function IconShape(icon)
        local ifc = _ecmeFC and _ecmeFC[icon]
        if not (ifc and ifc.shapeApplied and ifc.shapeMask) then return nil end
        local shape = ifc.shapeName
        if not shape or shape == "none" or shape == "cropped" then return nil end
        return shape, ifc.shapeMask
    end

    -- Ring art for "border" pushed mode on a shaped icon: four straight edges
    -- around a hexagon leave the corners hanging in space, so press-flash the
    -- shape's own border texture instead. Its thickness is baked into the art,
    -- so the bars' pushed border size doesn't apply -- colour still does.
    local function EnsureShapeRing(ov)
        if ov._shapeRing then return ov._shapeRing end
        local t = ov:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        t:Hide()
        ov._shapeRing = t
        return t
    end

    -- One overlay per icon in `store`, `level` above the icon (above the
    -- cooldown swipe), fitted to the icon's shape and styled by `style`, which
    -- returns false (nothing to show), "border" + r, g, b, size, or true.
    local function ShowOverlay(icon, store, level, style)
        local ov = store[icon]
        if not ov then
            ov = CreateFrame("Frame", nil, icon)
            ov:SetFrameLevel(icon:GetFrameLevel() + level)
            ov:Hide()
            local tex = ov:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(ov)
            ov._tex = tex
            store[icon] = ov
        end
        -- Re-sync the shape mask on every press: the shape can change or be
        -- cleared between presses, and a cleared shapeMask is emptied + hidden
        -- rather than destroyed -- left attached it would blank the overlay.
        -- A shape swap keeps the same mask object (re-textured), so it stays.
        local shape, mask = IconShape(icon)
        if ov._shapeMask and ov._shapeMask ~= mask then
            pcall(ov._tex.RemoveMaskTexture, ov._tex, ov._shapeMask)
            ov._shapeMask = nil
        end
        if mask and not ov._shapeMask then
            pcall(ov._tex.AddMaskTexture, ov._tex, mask)
            ov._shapeMask = mask
        end
        -- Blizzard Style: the flash rounds off with the icon's viewer mask.
        if ns.CdmBlizzIcons() then
            local bm = ns.CdmBlizzIconMask(icon)
            if bm and ov._blizzMask ~= bm then
                pcall(ov._tex.AddMaskTexture, ov._tex, bm)
                ov._blizzMask = bm
            end
        end
        local result, cr, cg, cb, bsz = style(ov._tex)
        if not result then ov:Hide(); return nil end
        -- Shaped icons expand their icon texture past the frame (and expand the
        -- texcoords to match), so anchor to the frame itself -- the rect the
        -- shapeMask covers -- rather than to the oversized texture.
        local region = (shape and icon) or icon.Icon or icon
        ov:ClearAllPoints()
        ov:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
        ov:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
        local ringTex = shape and ns.CDM_SHAPE_BORDERS and ns.CDM_SHAPE_BORDERS[shape]
        if result == "border" and ringTex then
            ov._tex:Hide()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
            local ring = EnsureShapeRing(ov)
            ring:SetTexture(ringTex)
            ring:SetVertexColor(cr, cg, cb, 1)
            ring:ClearAllPoints(); ring:SetAllPoints(ov)
            ring:Show()
        elseif result == "border" then
            ov._tex:Hide()
            if ov._shapeRing then ov._shapeRing:Hide() end
            local edges = EnsureBorderEdges(ov)
            for j = 1, 4 do edges[j]:SetVertexColor(cr, cg, cb, 1) end
            edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", ov); edges[1]:SetPoint("TOPRIGHT", ov); edges[1]:SetHeight(bsz); edges[1]:Show()
            edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", ov); edges[2]:SetPoint("BOTTOMRIGHT", ov); edges[2]:SetHeight(bsz); edges[2]:Show()
            edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT"); edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT"); edges[3]:SetWidth(bsz); edges[3]:Show()
            edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT"); edges[4]:SetWidth(bsz); edges[4]:Show()
        else
            ov._tex:Show()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
            if ov._shapeRing then ov._shapeRing:Hide() end
        end
        ov:Show()
        return ov
    end

    local function ShowPush(icon)
        return ShowOverlay(icon, _pushOverlay, 15, StylePush)
    end

    ---------------------------------------------------------------------------
    --  Spell matching (pressed button's spell vs. a CDM icon's spell)
    ---------------------------------------------------------------------------
    local GetOverrideSpell      = C_Spell and C_Spell.GetOverrideSpell
    local GetBaseSpell          = C_Spell and C_Spell.GetBaseSpell
    local FindSpellOverrideByID = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    local function safeNum(fn, arg)
        if type(fn) ~= "function" then return nil end
        local ok, res = pcall(fn, arg)
        if ok and type(res) == "number" and res > 0 then return res end
    end

    local function SpellIdSet(id)
        local t = { [id] = true }
        local a = safeNum(GetOverrideSpell, id);      if a then t[a] = true end
        local b = safeNum(GetBaseSpell, id);          if b then t[b] = true end
        local c = safeNum(FindBaseSpellByID, id);     if c then t[c] = true end
        local d = safeNum(FindSpellOverrideByID, id); if d then t[d] = true end
        return t
    end

    local function IconMatches(pressedSet, iconSid)
        if pressedSet[iconSid] then return true end
        local a = safeNum(GetOverrideSpell, iconSid); if a and pressedSet[a] then return true end
        local b = safeNum(GetBaseSpell, iconSid);     if b and pressedSet[b] then return true end
        return false
    end

    -- Reverse lookup: the primary itemID of the item preset that owns a given
    -- alt/current-tier itemID (e.g. Concentrated Health Potion 271884 ->
    -- 241304). Bar icons for these presets always key off the fixed primary
    -- id (see silvermoon_health's itemID/altItemIDs split), but a press can
    -- report any owned tier's itemID, so OnPress needs to resolve it back.
    local _presetPrimaryByAltID
    local function PresetPrimaryItemID(itemID)
        if not _presetPrimaryByAltID then
            _presetPrimaryByAltID = {}
            for _, pr in ipairs(ns.CDM_ITEM_PRESETS or {}) do
                if pr.altItemIDs then
                    for _, alt in ipairs(pr.altItemIDs) do
                        _presetPrimaryByAltID[alt] = pr.itemID
                    end
                end
            end
        end
        return _presetPrimaryByAltID[itemID]
    end

    local function IconSpellID(icon)
        local fc = _ecmeFC and _ecmeFC[icon]
        local sid = fc and fc.spellID
        if sid then return sid end
        local cdID = icon.cooldownID
        if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if info then return info.overrideSpellID or info.spellID end
        end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Press / hold / release. Release is driven by polling IsKeyDown on the
    --  button's binding keys, floored by MIN_VISIBLE and capped by MAX_HOLD.
    ---------------------------------------------------------------------------
    local function ReleaseEntry(btn, entry)
        local ovs = entry.overlays
        for i = 1, #ovs do ovs[i]:Hide() end
        _held[btn] = nil
        _heldN = _heldN - 1
        if _heldN <= 0 then _heldN = 0; _poll:Hide() end
    end

    _poll:SetScript("OnUpdate", function()
        if _heldN == 0 then _poll:Hide(); return end
        local now = GetTime()
        for btn, entry in pairs(_held) do
            local elapsed = now - entry.t
            local done = false
            if elapsed >= MAX_HOLD then
                done = true
            elseif elapsed >= MIN_VISIBLE then
                local anyDown = false
                local keys = entry.keys
                if keys then
                    for i = 1, #keys do
                        if keys[i] and IsKeyDown(keys[i]) then anyDown = true; break end
                    end
                end
                if not anyDown then done = true end
            end
            if done then ReleaseEntry(btn, entry) end
        end
    end)

    -- Cached enable-flag so OnPress can gate in O(1) instead of looping every
    -- bar on each key press (the ActionButtonDown hook fires for all users).
    -- Recomputed only when the bar list is rebuilt (RefreshCdmPressMirrorFlag,
    -- called from the CDM bar-rebuild pass) or when the toggle changes.
    local _anyPressMirror = false
    local function RefreshCdmPressMirrorFlag()
        _anyPressMirror = false
        if not barDataByKey then return end
        for _, bd in pairs(barDataByKey) do
            -- Buff-family bars never mirror presses (auto-tracked auras, not
            -- keybind-pressed), so ignore a stale/imported pressMirror on them.
            if bd and bd.pressMirror and not ns.IsBarBuffFamily(bd) then _anyPressMirror = true; return end
        end
    end
    ns.RefreshCdmPressMirrorFlag = RefreshCdmPressMirrorFlag
    RefreshCdmPressMirrorFlag()

    local function SlotSpellID(slot)
        if not slot then return nil end
        if HasAction and not HasAction(slot) then return nil end
        -- NOTE (Midnight): GetActionInfo is documented as usable only in the
        -- secure restricted environment. This runs from an insecure post-hook,
        -- so a future build could hand back nil/secret here and silently no-op
        -- the press mirror. Revisit via a secure route if that ever regresses.
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "spell" then
            return id
        elseif actionType == "item" then
            -- On-use trinkets/potions/healthstones placed directly on the
            -- action bar: hand back the itemID as a second return. Bar icons
            -- for these track by NEGATIVE identity (-itemID for item presets,
            -- -invSlot for "whatever's equipped in slot X" -- see
            -- ns.INV_SLOT_NAMES / the <= -100 item-preset branch above), not a
            -- resolved spellID, so the caller builds the matching keys itself.
            return nil, id
        elseif actionType == "macro" then
            if subType == "spell" then
                return id
            elseif subType == "item" then
                return nil
            end
            local macroName = GetActionText(slot)
            local macroIndex = macroName and GetMacroIndexByName(macroName)
            if macroIndex and macroIndex > 0 then
                if GetMacroItem and GetMacroItem(macroIndex) then
                    return nil
                end
                return GetMacroSpell(macroIndex)
            end
        end
        return nil
    end

    -- Base key of a (possibly modified) binding, e.g. "SHIFT-1" -> "1".
    local function BaseKey(binding)
        return binding and binding:match("[^%-]+$") or nil
    end

    local function OnPress(btn, bindCmd)
        if not btn or not _anyPressMirror then return end
        local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
        local sid, itemID = SlotSpellID(slot)
        if not sid and not itemID then return end

        local pressedSet = sid and SpellIdSet(sid) or {}
        if itemID then
            -- Item-preset icons (potions, healthstones, custom item ids) key
            -- off -itemID; equipment-slot icons (trinkets -13/-14, or any
            -- user-added slot) key off -invSlot for whatever's equipped there.
            -- Match both, plus the item's own on-use spell for the rarer case
            -- of it being tracked as a plain Custom Spell entry instead.
            pressedSet[-itemID] = true
            local primaryItemID = PresetPrimaryItemID(itemID)
            if primaryItemID then pressedSet[-primaryItemID] = true end
            for invSlot in pairs(ns.INV_SLOT_NAMES) do
                if GetInventoryItemID("player", invSlot) == itemID then
                    pressedSet[-invSlot] = true
                end
            end
            local _, useSpellID = C_Item.GetItemSpell(itemID)
            if useSpellID then
                for k in pairs(SpellIdSet(useSpellID)) do pressedSet[k] = true end
            end
        end
        local overlays
        if cdmBarIcons then
            for barKey, list in pairs(cdmBarIcons) do
                local bd = barDataByKey and barDataByKey[barKey]
                if bd and bd.pressMirror and not ns.IsBarBuffFamily(bd) then
                    for i = 1, #list do
                        local icon = list[i]
                        if icon and icon:IsShown() then
                            local isid = IconSpellID(icon)
                            if isid and IconMatches(pressedSet, isid) then
                                local ov = ShowPush(icon)
                                if ov then overlays = overlays or {}; overlays[#overlays + 1] = ov end
                            end
                        end
                    end
                end
            end
        end
        if not overlays then return end

        local keys
        if bindCmd then
            local k1, k2 = GetBindingKey(bindCmd)
            keys = { BaseKey(k1), BaseKey(k2) }
        end
        local entry = _held[btn]
        if entry then
            entry.overlays = overlays; entry.keys = keys; entry.t = GetTime()
        else
            _held[btn] = { overlays = overlays, keys = keys, t = GetTime() }
            _heldN = _heldN + 1
        end
        _poll:Show()
    end

    -- Public: clear active overlays (called from the CDM Bars > Extras toggle).
    function ns.ClearCdmPressPush()
        for _, entry in pairs(_held) do
            local ovs = entry.overlays
            for i = 1, #ovs do ovs[i]:Hide() end
        end
        wipe(_held); _heldN = 0; _poll:Hide()
        RefreshCdmPressMirrorFlag()
    end

    -- Click-routed keybinds (Bars 9/10, empower spells, custom paging) go
    -- through the button via SetOverrideBindingClick and never fire the native
    -- commands hooked below; the EAB PostClick hook publishes them here.
    -- PostClick runs after Blizzard's click handler returns, downstream of its
    -- protected item-use calls -- same taint posture as the native hooks.
    _G._EUI_OnActionButtonPress = function(btn, down, bindCmd)
        -- Down edge only: buttons register both edges, and in key-up mode the
        -- key is already released by the up click.
        if not down or not btn or not bindCmd or not _anyPressMirror then return end
        -- Keyboard evidence (a real mouse click must not mirror): a held
        -- binding key proves keyboard, but wheel binds are never IsKeyDown, so
        -- the cursor-rect test covers those. Only miss: a wheel bind pressed
        -- while the cursor rests on its own button.
        local k1, k2 = GetBindingKey(bindCmd)
        local b1, b2 = BaseKey(k1), BaseKey(k2)
        local keyHeld = (b1 and IsKeyDown(b1)) or (b2 and IsKeyDown(b2))
        if not keyHeld and btn.IsUnderMouse and btn:IsUnderMouse() then return end
        OnPress(btn, bindCmd)
    end

    ---------------------------------------------------------------------------
    --  Hook the action-button key-down path (fires on press, even on cooldown)
    ---------------------------------------------------------------------------
    local MULTIBAR_BINDING = {
        MultiBarBottomLeft  = "MULTIACTIONBAR1BUTTON",
        MultiBarBottomRight = "MULTIACTIONBAR2BUTTON",
        MultiBarRight       = "MULTIACTIONBAR3BUTTON",
        MultiBarLeft        = "MULTIACTIONBAR4BUTTON",
        MultiBar5           = "MULTIACTIONBAR5BUTTON",
        MultiBar6           = "MULTIACTIONBAR6BUTTON",
        MultiBar7           = "MULTIACTIONBAR7BUTTON",
    }

    local ev = ns.TakeShell()
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        if type(ActionButtonDown) == "function" then
            hooksecurefunc("ActionButtonDown", function(id)
                local btn = (GetActionButtonForID and GetActionButtonForID(id)) or _G["ActionButton" .. id]
                OnPress(btn, "ACTIONBUTTON" .. id)
            end)
        end
        if type(MultiActionButtonDown) == "function" then
            hooksecurefunc("MultiActionButtonDown", function(barName, id)
                local prefix = MULTIBAR_BINDING[barName]
                OnPress(_G[barName .. "Button" .. id], prefix and (prefix .. id) or nil)
            end)
        end
    end)

    ---------------------------------------------------------------------------
    --  Queued attacks (WoW Forever): while an on-next-swing attack is queued
    --  (EllesmereUI.FOREVER_NEXT_SWING: Heroic Strike, Cleave, Maul, Raptor
    --  Strike), its CDM icons show the action bars' spell cast highlight, as
    --  the bar button holding it does. ACTIONBAR_UPDATE_STATE, the edge those
    --  buttons check on, is registered only for a class that has such an
    --  attack; a burst folds into one pass on the next frame, which repaints
    --  only when the queued attack changed. A restricted answer counts as not
    --  queued.
    ---------------------------------------------------------------------------
    local _checkOverlay = setmetatable({}, { __mode = "k" })  -- [icon] = overlay frame
    local _queueNames       -- the class's attack names, resolved at login
    local _queued = false   -- the name painted, false = none
    local _lit = {}         -- the overlays showing it
    local _queueFlush = ns.TakeShell()
    _queueFlush:Hide()
    _queueFlush:SetScript("OnUpdate", function(self)
        self:Hide()
        local name = false
        for i = 1, #_queueNames do
            local cur = C_Spell.IsCurrentSpell(_queueNames[i])
            if not issecretvalue(cur) and cur then name = _queueNames[i]; break end
        end
        if name == _queued then return end
        _queued = name
        for i = #_lit, 1, -1 do _lit[i]:Hide(); _lit[i] = nil end
        if not (name and cdmBarIcons) then return end
        for barKey, list in pairs(cdmBarIcons) do
            local bd = barDataByKey and barDataByKey[barKey]
            if bd and not ns.IsBarBuffFamily(bd) then
                for i = 1, #list do
                    local icon = list[i]
                    if icon and icon:IsShown() then
                        local sid = IconSpellID(icon)
                        if not issecretvalue(sid) and sid and C_Spell.GetSpellName(sid) == name then
                            local ov = ShowOverlay(icon, _checkOverlay, 14, StyleChecked)
                            if ov then _lit[#_lit + 1] = ov end
                        end
                    end
                end
            end
        end
    end)

    local qev = ns.TakeShell()
    qev:RegisterEvent("PLAYER_LOGIN")
    qev:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_LOGIN" then
            _queueFlush:Show()
            return
        end
        self:UnregisterEvent("PLAYER_LOGIN")
        local lists = EllesmereUI.FOREVER_NEXT_SWING
        local _, classFile = UnitClass("player")
        local ids = lists and lists[classFile]
        if not (ids and C_Spell.IsCurrentSpell) then return end
        _queueNames = {}
        for i = 1, #ids do
            local n = C_Spell.GetSpellName(ids[i])
            if not issecretvalue(n) and n then _queueNames[#_queueNames + 1] = n end
        end
        if #_queueNames > 0 then self:RegisterEvent("ACTIONBAR_UPDATE_STATE") end
    end)
end
I.broken = false
