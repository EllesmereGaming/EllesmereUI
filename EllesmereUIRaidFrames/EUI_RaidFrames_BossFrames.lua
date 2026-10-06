if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_BossFrames.lua
--
--  Friendly Boss Frames: five secure unit buttons for boss1 to boss5.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs       = ipairs
local wipe         = wipe
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitIsUnit            = UnitIsUnit
local IsInRaid              = IsInRaid
local InCombatLockdown      = InCombatLockdown
local GetNumGroupMembers    = GetNumGroupMembers
local C_Timer               = C_Timer
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame

local ApplyFont, GetFFD, PixelSnap = I.ApplyFont, I.GetFFD, I.PixelSnap
local ResolveHealthTexture, separatedHdrs = I.ResolveHealthTexture, I.separatedHdrs
local GetHealthTextColor, GetNameColor = I.GetHealthTextColor, I.GetNameColor
local GetSafeHealthPercent, ResolveDisplayName = I.GetSafeHealthPercent, I.ResolveDisplayName

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local PP
I.PPSetters[#I.PPSetters + 1] = function(v) PP = v end

-------------------------------------------------------------------------------
--  Friendly Boss Frames (any group): five standalone secure unit buttons for
--  boss1-boss5. A secure visibility driver on [@bossN,help] is the entire
--  detection (encounters expose healable friendly NPCs as boss units) -- no
--  NPC database, fully combat safe. Dungeon encounters use the same boss unit
--  tokens as raids, so the group gate can cover party too -- behind the Show
--  in Dungeons opt-in (fb.showInDungeons, default off); attached positions
--  slot in beside the party container there. Buttons render ONLY health bar +
--  name/health text, following the RAID frame settings in a party too (one
--  styled group, and the indicator containers are built once). Excluded from preview and
--  unlock mode (Free Move uses its own drag overlay). Display "healers"
--  builds/activates only on a healer spec.
-------------------------------------------------------------------------------
-- do/end scope; closures below keep FB alive after the block closes.
do
local FB = { buttons = {}, trackers = {} }
ns._FB = FB

-- Settings source per button for the other groups these helpers style (the pet frames beside the
-- party frames read the party settings). Unregistered buttons, the boss group's own among them,
-- read the raid settings.
FB.src = setmetatable({}, { __mode = "k" })
FB.Source = function(b)
    local get = FB.src[b]
    return (get and get()) or ns._scaledProfile or db.profile
end

-- Target store: true while a button shows your target, read by the border painter. Re-read by the
-- full paint and on target changes, so a target change repaints only the buttons that flipped.
-- UnitIsUnit can be secret: read as not targeted. Returns true when the button's state flipped.
FB.tgt = setmetatable({}, { __mode = "k" })
FB.ReadTarget = function(b, unit)
    local t = unit and UnitIsUnit(unit, "target")
    if issecretvalue(t) then t = false end
    t = t and true or nil
    if FB.tgt[b] == t then return false end
    FB.tgt[b] = t
    return true
end

-- Hover store: true while the mouse is over a button, read by the border painter.
FB.hov = setmetatable({}, { __mode = "k" })

-- Baseline heal per healer class for NPC range checks. Boss units sit outside UnitInRange's
-- group-member domain and never fire UNIT_IN_RANGE_UPDATE, so range is measured against a known
-- helpful spell instead -- healer specs only; everyone else keeps full alpha (no range check).
FB.RANGE_HEAL = {
    PRIEST  = 2061,   -- Flash Heal
    PALADIN = 19750,  -- Flash of Light
    SHAMAN  = 8004,   -- Healing Surge
    DRUID   = 8936,   -- Regrowth
    MONK    = 116670, -- Vivify
    EVOKER  = 361469, -- Living Flame (25yd: native Evoker range)
}

-- WoW Forever: the class's best heal the spellbook holds (EllesmereUI.FOREVER_HEAL_SPELLS, best
-- first); nil when the class has none or has not learned one yet.
FB.ForeverKnownHeal = function(pClass)
    local list = EllesmereUI.FOREVER_HEAL_SPELLS[pClass]
    if not list then return nil end
    local bank = C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank
    for i = 1, #list do
        local id = list[i]
        local known
        if bank then
            known = C_SpellBook.IsSpellInSpellBook(id, bank.Player, true)
        else
            known = IsSpellKnown and IsSpellKnown(id)
        end
        if known then return id end
    end
    return nil
end

-- Secret-safe alpha application (result may be secret in instances, which SetAlphaFromBoolean
-- accepts natively). The result can also be NIL (unit not range-checkable / spell momentarily not
-- evaluable), which it rejects -- treat NIL as in range. issecretvalue runs FIRST so the nil check
-- never touches a secret.
FB.ApplyRange = function(b)
    if not FB.rangeSpell then return end
    local s = ns._scaledProfile or db.profile
    local inRange = C_Spell.IsSpellInRange(FB.rangeSpell, FB.UnitOf(b))
    if issecretvalue(inRange) or inRange ~= nil then
        b:SetAlphaFromBoolean(inRange, 1, s.oorAlpha or 0.4)
    else
        b:SetAlpha(1)
    end
end

FB.RangeTick = function()
    for _, b in ipairs(FB.buttons) do
        if b:IsVisible() then FB.ApplyRange(b) end
    end
end

-- The ticker exists only while a range spell is resolved AND at least one boss button is visible -- zero idle cost.
FB.UpdateRangeTicker = function()
    local want = FB.rangeSpell and (FB.visCount or 0) > 0
    if want and not FB.rangeTicker then
        FB.rangeTicker = C_Timer.NewTicker(0.4, FB.RangeTick)
    elseif not want and FB.rangeTicker then
        FB.rangeTicker:Cancel()
        FB.rangeTicker = nil
    end
end

-- Current unit for a button. The slot controller collapses friendly bosses into the FIRST slots
-- (slot 1 may show boss2), so the secure "unit" attribute is truth; _fbUnit is the build default.
FB.UnitOf = function(b)
    return b:GetAttribute("unit") or b._fbUnit
end

FB.Settings = function()
    return db and db.profile and db.profile.friendlyBoss
end

FB.ShouldBeActive = function()
    local fb = FB.Settings()
    if not fb then return false end
    if fb.display == "always" then return true end
    if fb.display == "healers" then
        -- WoW Forever: a class that can heal counts as its healing spec.
        if EllesmereUI.IS_FOREVER then
            local _, pClass = UnitClass("player")
            return EllesmereUI.FOREVER_HEAL_SPELLS[pClass] ~= nil
        end
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        return role == "HEALER"
    end
    return false
end

-- Anchor a FontString using the same position vocabulary as AnchorNameText/AnchorHealthText.
FB.AnchorText = function(fs, health, pos, ox, oy)
    fs:ClearAllPoints()
    if pos == "topleft" then
        fs:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    elseif pos == "top" then
        fs:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    elseif pos == "topright" then
        fs:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("TOP")
    elseif pos == "left" then
        fs:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "right" then
        fs:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "bottomleft" then
        fs:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottom" then
        fs:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottomright" then
        fs:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("BOTTOM")
    else -- "center"
        fs:SetPoint("CENTER", health, "CENTER", ox, oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    end
    -- Force re-render after a JustifyH change
    local txt = fs:GetText()
    fs:SetText("")
    fs:SetText(txt or "")
end

-- Recolor the border for the current state. Mirrors the raid buttons' single recolored border:
-- hover (raised) > target (raised) > normal, using the button's border settings (FB.Source: the raid
-- ones for the boss group) -- nothing separate.
FB.ApplyBorderColor = function(b)
    if not PP or not b._borderFrame or not db then return end
    local s = FB.Source(b)
    local targeted = FB.tgt[b] and s.targetBorderEnabled ~= false
    if b.stockEdge then
        local hover = FB.hov[b] and s.hoverBorderEnabled ~= false
        local lvl = b:GetFrameLevel() + (hover and ns.LVL_RAISE or 8)
        if b._borderFrame:GetFrameLevel() ~= lvl then
            b._borderFrame:SetFrameLevel(lvl)
            local container = PP.GetBorders(b._borderFrame)
            if container then container:SetFrameLevel(lvl + 1) end
        end
        ns.RF_StockHighlight(b, b._borderFrame, s, hover, targeted)
        return
    end
    local r, g, bcol, a
    local raised, hlSize, hlPx = false, nil, nil
    if FB.hov[b] and s.hoverBorderEnabled ~= false then
        local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
        r, g, bcol, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
        raised, hlSize = true, s.hoverBorderSize or 1
        hlPx = EllesmereUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
    elseif targeted then
        local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
        r, g, bcol, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
        raised, hlSize = true, s.targetBorderSize or 1
        hlPx = EllesmereUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
    else
        local c = s.borderColor or { r = 0, g = 0, b = 0 }
        r, g, bcol, a = c.r, c.g, c.b, s.borderAlpha or 1
    end
    -- Raise above neighbors while highlighted (as the raid buttons: overlapping frames would cover it).
    local pl = b:GetFrameLevel()
    local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
    -- The container too, like ApplyBorderLevel: FB.StyleBorder moves only the border
    -- frame, so a Show Behind flip would otherwise leave the strips on the old level.
    local container = PP.GetBorders(b._borderFrame)
    if b._borderFrame:GetFrameLevel() ~= lvl
       or (container and container:GetFrameLevel() ~= lvl + 1) then
        b._borderFrame:SetFrameLevel(lvl)
        if container then container:SetFrameLevel(lvl + 1) end
        -- Textured styles: the backdrop child too (see ApplyBorderLevel).
        local bd = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[b._borderFrame]
        if bd then bd:SetFrameLevel(lvl) end
    end
    if (s.borderSize or 1) <= 0 then
        ns.ApplyHighlightBorder(b._borderFrame, s, hlSize, r, g, bcol, a, hlPx)
        return
    end
    if hlSize then r, g, bcol = ns.RF_VisibleHighlight(s, r, g, bcol) end
    b._borderFrame._hlBorderSize = nil
    EllesmereUI.SetBorderStyleColor(b._borderFrame, r, g, bcol, a)
end

-- Apply the border style (size/color/texture/offsets) to one button, from its FB.Source.
FB.StyleBorder = function(b)
    if not PP or not b._borderFrame then return end
    local s = FB.Source(b)
    local bs = s.borderSize or 1
    local bc = s.borderColor or { r = 0, g = 0, b = 0 }
    local pl = b:GetFrameLevel()
    if b.stockEdge then
        b._borderFrame:SetFrameLevel(pl + 8)
        EllesmereUI.ApplyBorderStyle(b._borderFrame, 0, 0, 0, 0, 0, "solid")
        b._borderFrame._hlBorderSize = nil
        ns.RF_StockSeat(b)
        FB.ApplyBorderColor(b)
        return
    end
    b._borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
    EllesmereUI.ApplyBorderStyle(b._borderFrame, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
        s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
        s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs, nil,
        EllesmereUI.BorderPx(s.borderSizePx, bs, s.borderTexture or "solid"))
    FB.ApplyBorderColor(b)
end

-- Bar colour: the owner's own colour setting (default #17AC31). The raid color modes mislead here:
-- gradient modes read as damage states, and many NPCs carry real class tokens (a friendly add can
-- come out yellow).
FB.PaintBarColor = function(b, owner, s)
    local health = b._health
    local fbc = (owner.ColorSettings or owner.Settings)()
    fbc = fbc and fbc.healthColor
    local fillTex = health:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(1) end
    health:SetStatusBarColor(fbc and fbc.r or 23/255, fbc and fbc.g or 172/255,
        fbc and fbc.b or 49/255, (s.healthBarOpacity or 100) / 100)
end

FB.PaintName = function(b, unit, s)
    local fs = b._nameText
    if not fs then return end
    fs:SetText(ResolveDisplayName(unit, true, s))
    local nr, ng, nb = GetNameColor(unit, s)
    fs:SetTextColor(nr, ng, nb)
end

-- Health value, health text and heal absorb text. A text set to None is blank: the full paint (full)
-- clears it, and the health events after it skip it.
FB.PaintHealth = function(b, unit, s, full)
    local health = b._health
    local pct = GetSafeHealthPercent(unit)
    health:SetMinMaxValues(0, 100)
    local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut
    -- Missing health under Inverted Fill (the _euiInv stamp FB.StyleVisuals leaves);
    -- the texts keep the current-health pct. Dead units are not special-cased: there
    -- is no status colour here, so a full bar is what tells a dead unit apart.
    local barPct = pct
    if health._euiInv then barPct = GetSafeHealthPercent(unit, true) end
    if smooth then health:SetValue(barPct, smooth) else health:SetValue(barPct) end

    local ht, hat = b._healthText, b._healAbsorbText
    local mode = s.healthTextMode or "none"
    if ht and mode == "none" then
        if full then ht:SetText("") end
        ht = nil
    end
    if hat and (s.healAbsorbTextMode or "none") == "none" then
        if full then hat:SetText("") end
        hat = nil
    end
    if not (ht or hat) then return end
    local dead = UnitIsDeadOrGhost(unit)

    if ht then
        if dead then
            ht:SetText("")
        else
            ns.RF_HealthTextInto(ht, mode, pct, unit)
        end
        local htr, htg, htb = GetHealthTextColor(unit, s)
        ht:SetTextColor(htr, htg, htb, 0.9)
    end

    if hat then
        if dead then hat:SetText("")
        else ns.SetHealAbsorbText(hat, unit, s) end
    end
end

-- Refresh one boss button: health value/color, health text, name text, target state and border.
-- Mirrors the corresponding slices of UpdateButton/_UpdateButtonHealth; boss units are not group
-- units, so no roster paths. Returns true when it painted (border included); without a unit only a
-- flipped target state repaints the border.
FB.Update = function(b, owner)
    local unit = FB.UnitOf(b)
    local flipped = FB.ReadTarget(b, unit)
    if not db or not UnitExists(unit) then
        if flipped then FB.ApplyBorderColor(b) end
        return
    end
    local s = FB.Source(b)
    FB.PaintBarColor(b, owner or FB, s)
    FB.PaintName(b, unit, s)
    FB.PaintHealth(b, unit, s, true)
    FB.ApplyBorderColor(b)
    return true
end

-- Background, health bar, the three texts and the border frame of one button, kept on the button
-- itself with the stock styles' edge and highlight state. Shared with the pet frames and their
-- preview. The pet header's buttons are made by the pet header, not by us: these keys on them are
-- the one known exception to keeping state off header buttons (the rest lives in weak tables and
-- GetFFD).
FB.BuildVisuals = function(b)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if PP then PP.DisablePixelSnap(bg) end
    b._bg = bg

    local health = CreateFrame("StatusBar", nil, b)
    health:SetFrameLevel(b:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    if PP then PP.DisablePixelSnap(health) end
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    b._health = health

    local carrier = CreateFrame("Frame", nil, b)
    carrier:SetAllPoints(health)
    carrier:SetFrameLevel(b:GetFrameLevel() + ns.LVL_TEXT)
    local nameFS = carrier:CreateFontString(nil, "OVERLAY")
    nameFS:SetWordWrap(false)
    b._nameText = nameFS
    local healthFS = carrier:CreateFontString(nil, "OVERLAY")
    healthFS:SetWordWrap(false)
    b._healthText = healthFS
    local healAbsorbFS = carrier:CreateFontString(nil, "OVERLAY")
    healAbsorbFS:SetWordWrap(false)
    b._healAbsorbText = healAbsorbFS

    -- Border frame (same construction as the raid buttons; styled from the shared raid border settings in FB.StyleBorder)
    local bdr = CreateFrame("Frame", nil, b)
    bdr:SetAllPoints(b)
    bdr:SetFrameLevel(b:GetFrameLevel() + 8)
    b._borderFrame = bdr
    -- Stock styles: the stock edge and highlights.
    if ns.RF_Stock() then ns.RF_StockBuild(b, b) end
end

-- One-time construction of the container, the five buttons, click-cast registration and per-unit
-- trackers. Buttons are created hidden; the secure visibility drivers own show/hide after that.
FB.EnsureBuilt = function()
    if FB.built then return end
    FB.built = true

    local container = CreateFrame("Frame", "ERFFriendlyBossContainer", UIParent)
    container:Hide()
    FB.container = container

    for i = 1, 5 do
        local b = CreateFrame("Button", "ERFFriendlyBoss" .. i, container, "SecureUnitButtonTemplate")
        b._fbUnit = "boss" .. i
        b:SetAttribute("unit", b._fbUnit)
        b:SetAttribute("*type1", "target")
        b:RegisterForClicks("AnyUp")
        -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
        if EllesmereUI.AttachSecureUnitMenu then
            EllesmereUI.AttachSecureUnitMenu(b)
        else
            b:SetAttribute("*type2", "togglemenu")
        end
        b:Hide()
        FB.BuildVisuals(b)

        -- Refresh as soon as the driver shows the button; visible-count drives the ticker lifecycle.
        b:HookScript("OnShow", function(self)
            FB.visCount = (FB.visCount or 0) + 1
            -- Containers first: an error in the legacy refresh must not starve the unit assignment.
            if ns.RFC_OnUnitAssigned then
                local d = GetFFD(self)
                local unit = FB.UnitOf(self)
                if d and unit then ns.RFC_OnUnitAssigned(self, d, unit) end
            end
            FB.Update(self)
            FB.ApplyRange(self)
            FB.UpdateRangeTicker()
        end)
        b:HookScript("OnHide", function(self)
            FB.visCount = math.max(0, (FB.visCount or 0) - 1)
            FB.UpdateRangeTicker()
        end)

        -- Hover highlight (these are our own buttons; hooks are safe)
        b:HookScript("OnEnter", function(self)
            FB.hov[self] = true
            FB.ApplyBorderColor(self)
        end)
        b:HookScript("OnLeave", function(self)
            FB.hov[self] = nil
            FB.ApplyBorderColor(self)
        end)

        -- Re-render when the slot controller reassigns this slot's unit mid-combat (a boss
        -- spawning/despawning reflows the slots without an OnShow on already-visible buttons).
        b:HookScript("OnAttributeChanged", function(self, name)
            if name == "unit" and self:IsVisible() then
                -- Containers first (same rationale as the OnShow hook).
                if ns.RFC_OnUnitAssigned then
                    local d = GetFFD(self)
                    local unit = FB.UnitOf(self)
                    if d and unit then ns.RFC_OnUnitAssigned(self, d, unit) end
                end
                FB.Update(self)
                FB.ApplyRange(self)
            end
        end)

        -- Full click-cast / hovercast binding suite (mouseover heals included)
        if ns.CC_RegisterFrame then ns.CC_RegisterFrame(b) end

        -- Boss units are outside the roster trackers; track here. The slot controller may have
        -- assigned this unit to ANY slot, so route the event to whichever button shows it.
        local unitId = "boss" .. i
        local t = ns.TakeShell()
        t:RegisterUnitEvent("UNIT_HEALTH", unitId)
        t:RegisterUnitEvent("UNIT_MAXHEALTH", unitId)
        t:RegisterUnitEvent("UNIT_NAME_UPDATE", unitId)
        t:SetScript("OnEvent", function()
            for _, btn in ipairs(FB.buttons) do
                if btn:IsVisible() and btn:GetAttribute("unit") == unitId then
                    FB.Update(btn)
                    break
                end
            end
        end)
        FB.trackers[i] = t

        FB.buttons[i] = b

        if ns.RFC_SetupButton then
            local d = GetFFD(b)
            ns.RFC_SetupButton(b, b._health, d)
        end
    end

    -- Slot controller: collapses friendly bosses into the FIRST slots (button positions fixed;
    -- units assigned in bossN order, buttons shown/hidden). Runs in the restricted environment so
    -- mid-combat spawns/despawns reflow safely (insecure code cannot Show/Hide or re-unit protected
    -- buttons in combat). Drivers registered in FB_Apply feed state-ingroup / state-fb1..5. One
    -- shared body per attribute; FB_Apply also force-runs it via SecureHandlerExecute because the
    -- driver manager skips the handler when a re-registered driver's value is unchanged.
    FB.RELAYOUT = [[
        local ingroup = self:GetAttribute("state-ingroup")
        local slot = 0
        if ingroup == 1 or ingroup == "1" then
            for i = 1, 5 do
                local v = self:GetAttribute("state-fb" .. i)
                if v == 1 or v == "1" then
                    slot = slot + 1
                    local b = self:GetFrameRef("slot" .. slot)
                    if b then
                        b:SetAttribute("unit", "boss" .. i)
                        b:Show()
                    end
                end
            end
        end
        for j = slot + 1, 5 do
            local b = self:GetFrameRef("slot" .. j)
            if b then b:Hide() end
        end
    ]]
    local controller = CreateFrame("Frame", "ERFFriendlyBossController", nil, "SecureHandlerAttributeTemplate")
    for i = 1, 5 do
        controller:SetFrameRef("slot" .. i, FB.buttons[i])
    end
    -- The template's handler attribute is "_onattributechanged" (wildcard receiving name/value).
    -- The relayout body lives in its own attribute so the handler and the force-run share it.
    controller:SetAttributeNoHandler("fb_relayout", FB.RELAYOUT)
    controller:SetAttributeNoHandler("_onattributechanged", [[
        if name == "state-ingroup" or name == "state-fb1" or name == "state-fb2"
           or name == "state-fb3" or name == "state-fb4" or name == "state-fb5" then
            self:RunAttribute("fb_relayout")
        end
    ]])
    FB.controller = controller
end

-- Re-apply all setting-derived properties (size, slots, texture, fonts, text anchors). OOC only;
-- callers gate. The owner parameter lets the Extra Frames duplicates (ns._XF) share this verbatim:
-- an owner carries buttons/container/Settings and defaults to FB itself.
FB.ApplyStyle = function(owner)
    owner = owner or FB
    if not owner.built then return end
    local s = ns._scaledProfile or db.profile
    local fbset = owner.Settings()
    -- Per-group size offset on the shared raid frame size (Extra Width/Height sliders; clamped so a negative offset can't invert a small frame).
    local w = PixelSnap(math.max(10, (s.frameWidth or 125) + ((fbset and fbset.extraWidth) or 0)))
    local h = PixelSnap(math.max(10, (s.frameHeight or 60) + ((fbset and fbset.extraHeight) or 0)))
    local sp = s.cellSpacing or -1
    -- Free Move ignores the raid growth settings: vertical stack by default, horizontal via the
    -- Horizontal Frames cog. Attached modes keep stacking like a real group (unitGrowth).
    local grow
    if fbset and fbset.position == "free" then
        grow = fbset.freeHorizontal and "RIGHT" or "DOWN"
    else
        grow = s.unitGrowth or "DOWN"
    end
    local texPath = ResolveHealthTexture()
    local bgc = s.customBgColor or { r = 17/255, g = 17/255, b = 17/255 }

    local stepW, stepH = 0, 0
    if grow == "DOWN" or grow == "UP" then
        owner.container:SetSize(w, h * 5 + sp * 4)
        stepH = h + sp
    else
        owner.container:SetSize(w * 5 + sp * 4, h)
        stepW = w + sp
    end

    for i, b in ipairs(owner.buttons) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        local off = i - 1
        if grow == "UP" then
            b:SetPoint("BOTTOMLEFT", owner.container, "BOTTOMLEFT", 0, off * stepH)
        elseif grow == "LEFT" then
            b:SetPoint("TOPRIGHT", owner.container, "TOPRIGHT", -off * stepW, 0)
        elseif grow == "RIGHT" then
            b:SetPoint("TOPLEFT", owner.container, "TOPLEFT", off * stepW, 0)
        else -- DOWN
            b:SetPoint("TOPLEFT", owner.container, "TOPLEFT", 0, -off * stepH)
        end

        FB.StyleVisuals(b, s, w, h, texPath, bgc)
    end
end

-- The size-dependent part of FB.StyleVisuals (the health bar's height, the text widths): all a
-- resize of an already styled button needs.
FB.SizeVisuals = function(b, w, h)
    -- No power bar / top name bar here: health fills the button.
    b._health:SetHeight(h)
    b._nameText:SetWidth(w * ns.RF_NAME_WIDTH_FRACTION)
    b._healthText:SetWidth(w * 0.75)
    if b._healAbsorbText then b._healAbsorbText:SetWidth(w * 0.75) end
end

-- Texture, fonts, text anchors and border of one button at w x h. Shared with the pet frames.
FB.StyleVisuals = function(b, s, w, h, texPath, bgc)
    b._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    b._health:SetStatusBarTexture(texPath)
    local ft = b._health:GetStatusBarTexture()
    if ft then ft:SetHorizTile(false) end
    -- Fill axis follows the raid Health Bar setting. The bg is a full-button texture (not fill-tracking), so nothing else re-anchors.
    ns.RF_ApplyHealthOrientation(b._health, s)
    -- These carry aura containers (RFC_SetupButton below) and so can carry
    -- Health Bar Color overlays, but they have no absorb cluster and never
    -- build ReanchorAbsorbToFill, where every other frame picks the swap up.
    b._health._euiFillOpacity = (s.healthBarOpacity or 100) / 100
    ns.RF_RefreshBarTints(b._health)
    FB.SizeVisuals(b, w, h)

    ApplyFont(b._nameText, s.nameSize or 10)
    ApplyFont(b._healthText, s.healthTextSize or 9)
    b._nameText:SetHeight(0)
    b._healthText:SetHeight(0)
    local namePos = s.namePosition or "center"
    if namePos == "none" then
        b._nameText:Hide()
    else
        b._nameText:Show()
        FB.AnchorText(b._nameText, b._health, namePos, s.nameOffsetX or 0, s.nameOffsetY or 0)
    end
    FB.AnchorText(b._healthText, b._health, s.healthTextPosition or "center",
        s.healthTextOffsetX or 0, s.healthTextOffsetY or 0)
    if b._healAbsorbText then
        ApplyFont(b._healAbsorbText, s.healAbsorbTextSize or 9)
        b._healAbsorbText:SetHeight(0)
        FB.AnchorText(b._healAbsorbText, b._health, s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0)
    end
    FB.StyleBorder(b)
end

-- A container's one anchor point, left alone when it already sits exactly there: the roster and
-- layout passes re-anchor with unchanged targets, and rewriting a protected frame's point re-lays
-- it and every button under it. A secret point always rewrites.
FB.Pin = function(c, point, rel, relPoint, x, y)
    if c:GetNumPoints() == 1 then
        local p, r, rp, px, py = c:GetPoint(1)
        if not (issecretvalue(p) or issecretvalue(r) or issecretvalue(rp)
                or issecretvalue(px) or issecretvalue(py))
           and p == point and r == rel and rp == relPoint and px == x and py == y then
            return
        end
    end
    c:ClearAllPoints()
    c:SetPoint(point, rel, relPoint, x, y)
end

-- Position the container per the position setting. The container inherits protection from its
-- secure children, so SetPoint is OOC-only. Owner-parameterized like ApplyStyle. Every placement
-- goes through FB.Pin (owner.FreeAnchor included).
FB.Anchor = function(owner)
    owner = owner or FB
    if not owner.built then return end
    if InCombatLockdown() then owner.anchorDirty = true; return end
    local s = db.profile
    local fb = owner.Settings()
    local c = owner.container

    if fb.position ~= "free" then
        local anchorHdr
        -- Chain rule: when the boss group (owner == FB) and Extra Frames attach to the SAME side,
        -- the boss group anchors to the extra container instead of the raid -- order raid -> extra
        -- -> boss (mirrored on "left"). Extra Frames always anchor to the raid; ns.XF_Apply re-runs
        -- this anchor when that container shows/hides/moves.
        if owner == FB then
            local xf = ns._XF
            local xs = xf and xf.Settings and xf.Settings()
            if xs and xs.position == fb.position and xf.built
               and xf.container and xf.container:IsShown() then
                anchorHdr = xf.container
            end
        end
        -- Owners placed after other attached groups on the same side (the pet frames), which
        -- remember the group they followed (owner.chainTgt).
        if not anchorHdr and owner.ChainAnchor then
            anchorHdr = owner.ChainAnchor(fb)
            owner.chainTgt = anchorHdr or false
            -- Beside the party frames the chain runs on the party attach axis, not the raid growth,
            -- with the same kit side and clearance, and the corner the party stack grows from.
            if anchorHdr and owner.attachParty then
                local gap = s.groupSpacing or -1
                local before = (fb.position == "left")
                if ns.RF_PartyKit() then
                    local extra
                    before, extra = ns.RF_KitAttach(s, before)
                    gap = gap + extra
                end
                local grow = ns._PartyGrowth(s)
                if grow == "UP" then
                    if before then FB.Pin(c, "BOTTOMRIGHT", anchorHdr, "BOTTOMLEFT", -gap, 0)
                    else FB.Pin(c, "BOTTOMLEFT", anchorHdr, "BOTTOMRIGHT", gap, 0) end
                elseif grow == "LEFT" then
                    if before then FB.Pin(c, "BOTTOMRIGHT", anchorHdr, "TOPRIGHT", 0, gap)
                    else FB.Pin(c, "TOPRIGHT", anchorHdr, "BOTTOMRIGHT", 0, -gap) end
                elseif s.partyHorizontal then
                    if before then FB.Pin(c, "BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap)
                    else FB.Pin(c, "TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap) end
                else
                    if before then FB.Pin(c, "TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0)
                    else FB.Pin(c, "TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0) end
                end
                return
            end
        end
        -- Party/dungeon: every raid group header is hidden there, so the boss group slots in beside
        -- the party container as if it were the next group -- along the axis the party frames do NOT
        -- stack on, the way "before first / after last group" reads in a raid. Extra Frames is raid
        -- only and keeps the raid path. Party frames off screen leaves nothing to attach to: this
        -- branch anchors nothing and the free position below takes over.
        if not anchorHdr and (not IsInRaid() or ns._PartyInRaid())
           and ((owner == FB and fb.showInDungeons == true) or owner.attachParty) then
            local pc = ns._partyContainerFrame
            if pc and pc:IsShown() then
                local gap = s.groupSpacing or -1
                local before = (fb.position == "left")
                -- Party Frames kit: clear the auras it draws outside the frames.
                if ns.RF_PartyKit() then
                    local extra
                    before, extra = ns.RF_KitAttach(s, before)
                    gap = gap + extra
                end
                -- The group clears the party target frames on its side, and the boss group the
                -- Beside Owner pets there too (the pet header is down while those are up).
                gap = gap + ns.PT_Reserve(s.partyHorizontal, before,
                    (owner == FB) and ns.PF_OwnerReserve(s.partyHorizontal, before) or nil)
                -- Pets line up with the first party frame: Flip Frame Growth and Centered start
                -- the stack away from the container's top-left.
                if owner ~= FB then
                    local first = ns._partyFirstSlot or pc
                    local grow = ns._PartyGrowth(s)
                    if grow == "UP" then
                        if before then FB.Pin(c, "BOTTOMRIGHT", first, "BOTTOMLEFT", -gap, 0)
                        else FB.Pin(c, "BOTTOMLEFT", first, "BOTTOMRIGHT", gap, 0) end
                        return
                    elseif grow == "LEFT" then
                        if before then FB.Pin(c, "BOTTOMRIGHT", first, "TOPRIGHT", 0, gap)
                        else FB.Pin(c, "TOPRIGHT", first, "BOTTOMRIGHT", 0, -gap) end
                        return
                    end
                    pc = first
                end
                -- Party growth axis comes from partyHorizontal alone (_LayoutPartyFrames): the flip
                -- and "centered" variants only reverse it, and the container spans all five slots
                -- either way, so the perpendicular attach point is the same.
                if s.partyHorizontal then
                    if before then FB.Pin(c, "BOTTOMLEFT", pc, "TOPLEFT", 0, gap)
                    else FB.Pin(c, "TOPLEFT", pc, "BOTTOMLEFT", 0, -gap) end
                else
                    if before then FB.Pin(c, "TOPRIGHT", pc, "TOPLEFT", -gap, 0)
                    else FB.Pin(c, "TOPLEFT", pc, "TOPRIGHT", gap, 0) end
                end
                return
            end
        elseif not anchorHdr and s.mergeGroups then
            anchorHdr = ns._flatHeader
        elseif not anchorHdr then
            -- The boss group slots in before the first / after the last group that is BOTH enabled
            -- in Show Groups AND populated. With none populated (not in a raid yet), fall back to
            -- the Show Groups bounds alone.
            local vg = ns._VisibleGroups() or {}
            -- One reused set across calls (the roster edges anchor every group).
            local occupied = FB.occ
            if occupied then wipe(occupied) else occupied = {}; FB.occ = occupied end
            for ri = 1, GetNumGroupMembers() or 0 do
                local _, _, sub = GetRaidRosterInfo(ri)
                if sub then occupied[sub] = true end
            end
            local first, last
            local groupOrder = s.customGroupOrder and ns._RFValidatedGroupOrder(s.groupOrder)
            for slot = 1, 8 do
                local gi = groupOrder and groupOrder[slot] or slot
                if vg[gi] ~= false and separatedHdrs[gi] and occupied[gi] then
                    if not first then first = separatedHdrs[gi] end
                    last = separatedHdrs[gi]
                end
            end
            if not first then
                for slot = 1, 8 do
                    local gi = groupOrder and groupOrder[slot] or slot
                    if vg[gi] ~= false and separatedHdrs[gi] then
                        if not first then first = separatedHdrs[gi] end
                        last = separatedHdrs[gi]
                    end
                end
            end
            anchorHdr = (fb.position == "left") and first or last
        end
        if anchorHdr then
            -- Slot in along the group growth axis exactly like a real group.
            local gap = s.groupSpacing or -1
            local grow = s.groupGrowth or "RIGHT"
            local before = (fb.position == "left")
            if grow == "RIGHT" or grow == "DOWNRIGHT" then
                -- The grid flow's last group also ends in the rightmost column,
                -- so it slots in along the same edge as a plain RIGHT run.
                if before then FB.Pin(c, "TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0)
                else FB.Pin(c, "TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0) end
            elseif grow == "LEFT" then
                if before then FB.Pin(c, "TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0)
                else FB.Pin(c, "TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0) end
            elseif grow == "DOWN" then
                if before then FB.Pin(c, "BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap)
                else FB.Pin(c, "TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap) end
            else -- UP
                if before then FB.Pin(c, "TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap)
                else FB.Pin(c, "BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap) end
            end
            return
        end
        -- No usable group header: fall through to the free position.
    end

    -- Owner-specific free anchoring (Extra Frames pins the grid's growth corner so the group grows away from it); CENTER pin otherwise.
    if owner.FreeAnchor and owner.FreeAnchor(c, fb) then return end
    local p = fb.freePos or {}
    FB.Pin(c, "CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
end

-- Re-anchor only (no restyle): the party visibility pass calls this on the party container's
-- show/hide edge, since attached positions hang off that container outside a raid. Gated on
-- the Show in Dungeons opt-in: with it off the party attach branch is inert, so the party
-- layout/visibility hooks skip the re-anchor entirely (zero added work for raid-only users).
function ns.FB_ReAnchor()
    ns.PF_PartyRelayout()
    if not FB.built then return end
    local fb = FB.Settings and FB.Settings()
    if fb and fb.showInDungeons == true then FB.Anchor() end
end

-- Master apply: activates, deactivates and refreshes the whole feature. Called from OnEnable, the
-- options dropdowns, spec changes, profile swaps (_ERF_RefreshAll) and the post-combat dirty pass.
function ns.FB_Apply()
    if not db or not db.profile then return end
    local fb = FB.Settings()
    if not fb then return end
    if InCombatLockdown() then FB.applyDirty = true; return end

    if not FB.ShouldBeActive() then
        if FB.built then
            if FB.controller then
                UnregisterAttributeDriver(FB.controller, "state-ingroup")
                for i = 1, 5 do
                    UnregisterAttributeDriver(FB.controller, "state-fb" .. i)
                end
            end
            for _, b in ipairs(FB.buttons) do
                b:Hide()
            end
            FB.container:Hide()
        end
        if FB.mover then FB.mover:Hide() end
        FB.rangeSpell = nil
        FB.UpdateRangeTicker()
        return
    end

    FB.EnsureBuilt()
    FB.ApplyStyle()
    FB.Anchor()
    FB.container:Show()
    -- Drivers feed the slot controller, which assigns bosses to the first slots in bossN order and shows/hides buttons securely.
    -- Group gate: raid only by default; raid OR party with Show in Dungeons on (the cog on
    -- Add Friendly Boss Group -- opt-in, so existing users keep raid-only behavior). Dungeon
    -- encounters expose the same healable bossN tokens. The toggle's setter re-runs FB_Apply,
    -- so re-registering here applies the flip live in either direction.
    local groupCond = (fb.showInDungeons == true)
        and "[@raid1,exists][@party1,exists] 1; 0"
        or "[@raid1,exists] 1; 0"
    RegisterAttributeDriver(FB.controller, "state-ingroup", groupCond)
    for i = 1, 5 do
        RegisterAttributeDriver(FB.controller, "state-fb" .. i, "[@boss" .. i .. ",help] 1; 0")
    end
    -- Force one relayout now: the driver manager fires attribute handlers only on VALUE CHANGES, so
    -- a (re)apply with unchanged states would never run the initial layout. FB_Apply is OOC-only,
    -- so the insecure Execute is always legal here.
    if SecureHandlerExecute then
        SecureHandlerExecute(FB.controller, FB.RELAYOUT)
    end
    for _, b in ipairs(FB.buttons) do
        if b:IsVisible() then FB.Update(b) end
    end

    -- Range dimming: healer specs only (regardless of display mode).
    local spec = GetSpecialization and GetSpecialization()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    local _, pClass = UnitClass("player")
    FB.rangeSpell = (role == "HEALER") and FB.RANGE_HEAL[pClass] or nil
    -- WoW Forever: a healing class range-checks with its best known heal.
    if EllesmereUI.IS_FOREVER then FB.rangeSpell = FB.ForeverKnownHeal(pClass) end
    if not FB.rangeSpell then
        for _, b in ipairs(FB.buttons) do b:SetAlpha(1) end
    else
        for _, b in ipairs(FB.buttons) do
            if b:IsVisible() then FB.ApplyRange(b) end
        end
    end
    FB.UpdateRangeTicker()
end

function ns.FB_IsMoverShown()
    return FB.mover and FB.mover:IsShown() or false
end

-- Free Move corner pin (Extra Frames, Pet Frames): the corner a grid grows from (hDir, vDir: its
-- horizontal and vertical growth), so its first frame stays put as frames come and go, and with a
-- saved rect r (FB.SaveMoverRect) that corner's offset from UIParent's centre.
FB.CornerPin = function(hDir, vDir, r)
    local corner
    if vDir == "UP" then
        corner = (hDir == "LEFT") and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        corner = (hDir == "LEFT") and "TOPRIGHT" or "TOPLEFT"
    end
    if not r then return corner end
    return corner, (hDir == "LEFT") and r.right or r.left, (vDir == "UP") and r.bottom or r.top
end

-- The shared mover's drag stop, for corner-pinned owners: the dropped rect, relative to UIParent's
-- centre, into set.freeRect.
FB.SaveMoverRect = function(mover, set)
    if not set then return end
    local ux, uy = UIParent:GetCenter()
    local l, b, mw, mh = mover:GetRect()
    if not (ux and l) then return end
    set.freeRect = { left = l - ux, right = l + mw - ux, bottom = b - uy, top = b + mh - uy }
end

-- Free Move drag overlay (unlock-mode look, TOOLTIP strata so it floats above the options panel).
-- Deliberately independent of unlock mode. Owner-parameterized: the Extra Frames and pet groups
-- build their own movers through this exact code with their own name/label (stored at owner.mover).
FB.SetMoverShown = function(owner, show, frameName, labelText)
    if not show then
        if owner.mover then owner.mover:Hide() end
        return
    end
    -- Owners whose overlay can place another context's spot (the pet frames' Party and Raid tabs)
    -- read the overlay's settings, and bring their live group up to date themselves.
    local moverSettings = owner.MoverSettings or owner.Settings
    local fb = moverSettings()
    if not fb or fb.position ~= "free" then return end
    if owner.MoverPrep then
        owner.MoverPrep()
    else
        owner.EnsureBuilt()
        -- Owners with their own geometry pass (Extra Frames) restyle through it; FB-built buttons use the FB styler.
        if owner.Layout then owner.Layout() else FB.ApplyStyle(owner) end
        FB.Anchor(owner)
    end

    if not owner.mover then
        local m = CreateFrame("Frame", frameName, UIParent)
        m:SetFrameStrata("TOOLTIP")
        m:SetClampedToScreen(true)
        m:SetMovable(true)
        m:EnableMouse(true)
        m:RegisterForDrag("LeftButton")
        local mbg = m:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints()
        mbg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
        local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
        EllesmereUI.MakeBorder(m, ar or 1, ag or 1, ab or 1, 0.6)
        local lbl = m:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(lbl, true)
        lbl:SetFont(EllesmereUI.GetFontPath("raidFrames"), 11, "")
        lbl:SetTextColor(1, 1, 1, 0.75)
        lbl:SetPoint("CENTER", m, "CENTER")
        lbl:SetWordWrap(false)
        lbl:SetText(labelText)
        m:SetScript("OnDragStart", function(self) self:StartMoving() end)
        m:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                local set = (owner.MoverSettings or owner.Settings)()
                if set then
                    set.freePos = {
                        x = math.floor(cx - ux + 0.5),
                        y = math.floor(cy - uy + 0.5),
                    }
                end
            end
            -- Corner-pinned owners also capture the dropped rect
            if owner.SaveFreeRect then owner.SaveFreeRect(self) end
            FB.Anchor(owner)
        end)
        owner.mover = m
        -- Close the mover with the options panel so it can't be stranded.
        if EllesmereUI._mainFrame then
            EllesmereUI._mainFrame:HookScript("OnHide", function() m:Hide() end)
        end
    end

    owner.mover:ClearAllPoints()
    local oset = moverSettings() or {}
    if owner.PlaceMover then
        owner.PlaceMover(owner.mover, oset)
    else
        owner.mover:SetSize(owner.container:GetWidth(), owner.container:GetHeight())
        if owner.FreeAnchor and oset.freeRect then
            -- Corner-pinned owners: mirror the container's placement so the overlay always covers the live grid (FB.Anchor just ran).
            owner.mover:SetPoint("CENTER", owner.container, "CENTER")
        else
            local p = oset.freePos or {}
            owner.mover:SetPoint("CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
        end
    end
    owner.mover:Show()
end

function ns.FB_SetMoverShown(show)
    FB.SetMoverShown(FB, show, "ERFFriendlyBossMover", "Friendly Boss Frames")
end

-- Standing event frame: exists even while inactive so a spec change can activate display="healers" without a /reload.
do
    local ev = ns.TakeShell()
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", function(_, event)
        if not db then return end
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            ns.FB_Apply()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if FB.applyDirty then FB.applyDirty = nil; ns.FB_Apply() end
            if FB.anchorDirty then FB.anchorDirty = nil; FB.Anchor() end
        elseif not FB.built or not FB.container or not FB.container:IsShown() then
            return
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            for _, b in ipairs(FB.buttons) do
                if b:IsVisible() then FB.Update(b) end
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Only the border state can change here, and only on the buttons that flipped
            for _, b in ipairs(FB.buttons) do
                if b:IsVisible() and FB.ReadTarget(b, FB.UnitOf(b)) then FB.ApplyBorderColor(b) end
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            -- First/last visible group (and the size tier) can shift with
            -- the roster; restyle + re-anchor, deferred through combat.
            if InCombatLockdown() then
                FB.applyDirty = true
            else
                FB.ApplyStyle()
                FB.Anchor()
            end
        end
    end)
    FB.eventFrame = ev
end

end -- FB scope block

I.broken = false
