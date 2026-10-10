if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Apply.lua
--
--  The apply methods the options UI and ApplyAll call: borders, shapes,
--  layout passthroughs, fonts and keybind text, cooldown countdown fonts,
--  bar and icon backgrounds, Always Show Buttons and the main bar page sync.
--  Loads after the main file and EUI_ActionBars_ButtonArt.lua and reads them
--  through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, pcall = ipairs, pairs, pcall
local max = math.max
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local GetBindingKey = GetBindingKey
local EFD = ns.EFD

local EAB, EAB_VTABLE, BAR_LOOKUP = ns.EAB, ns.EAB_VTABLE, ns.BAR_LOOKUP
local ResolveBorderThickness, ButtonHasAction, barButtons = ns.ResolveBorderThickness, ns.ButtonHasAction, ns.barButtons
local I = ns._internals
local BAR_CONFIG, BINDING_MAP, FONT_PATH = I.BAR_CONFIG, I.BINDING_MAP, I.FONT_PATH
local NUM_ACTIONBAR_BUTTONS = I.NUM_ACTIONBAR_BUTTONS
local barFrames, buttonToBar, _fadeAlpha = I.barFrames, I.buttonToBar, I._fadeAlpha
local _gridState, _quickKeybindState = I._gridState, I._quickKeybindState
local LayoutBar, SyncPagingAlpha, FormatHotkeyText = I.LayoutBar, I.SyncPagingAlpha, I.FormatHotkeyText
local ApplyButtonBorders, ApplyShapeToButton = I.ApplyButtonBorders, I.ApplyShapeToButton
local SafeEnableMouse, SafeEnableMouseMotionOnly = I.SafeEnableMouse, I.SafeEnableMouseMotionOnly
local ShouldQuickKeybindSurfaceBar = I.ShouldQuickKeybindSurfaceBar
local SHOWGRID, SetShowGridInsecure = I.SHOWGRID, I.SetShowGridInsecure

-------------------------------------------------------------------------------
--  EAB Methods Apply functions called by the options UI
-------------------------------------------------------------------------------
function EAB:ApplyBordersForBar(barKey)
    if not self.db then return end
    -- Border reach counts in size matching (the bar's getMatchPad reads these
    -- settings): re-push the bar's matches when it moved. At entry so the look
    -- and square-icon returns below report too; the re-push is deferred.
    if EllesmereUI.MatchPadChanged then EllesmereUI.MatchPadChanged(barKey) end
    if not self.db.profile.squareIcons then return end
    if ns.AB_Style() ~= "eui" then return end
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local c = s.borderColor or { r=0, g=0, b=0, a=1 }
    local sz, px = ResolveBorderThickness(s)
    local on = sz > 0
    local cr, cg, cb, ca = c.r, c.g, c.b, c.a or 1
    if s.borderClassColor then
        local _, classToken = UnitClass("player")
        if classToken then
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
    end
    local zoom = ((s.iconZoom or self.db.profile.iconZoom or 5.5)) / 100
    local textureKey = s.borderTexture or "solid"
    local texOffset = s.borderTextureOffset
    local texOffsetY = s.borderTextureOffsetY
    local texShiftX = s.borderTextureShiftX
    local texShiftY = s.borderTextureShiftY
    local thicknessKey = s.borderThickness or "thin"
    local behind = s.borderBehind
    local above = s.borderAboveEffects
    local buttons = barButtons[barKey]
    if not buttons then return end
    local masqueOwns = ns.MasqueOwnsBar(barKey)
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            EFD(btn).barKey = barKey
            if masqueOwns then
                local fd = EFD(btn)
                EllesmereUI.HideBorderStyle(btn)
                if EllesmereUI._bdBorderData then
                    local bdFrame = EllesmereUI._bdBorderData[btn]
                    if bdFrame then bdFrame:Hide() end
                end
                if fd.shapeBorder then
                    fd.shapeBorder:Hide()
                    EFD(fd.shapeBorder).wantsShow = false
                end
            else
                ApplyButtonBorders(btn, on, cr, cg, cb, ca, sz, zoom, textureKey, texOffset, texOffsetY, texShiftX, texShiftY, "actionbars", thicknessKey, behind, px, above)
            end
        end
    end
    -- Match Bar Border copies follow the bar border (one boolean read while off).
    ns._ixBarSync(barKey)
end

function EAB:ApplyBorders()
    if not self.db then return end
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyBordersForBar(info.key)
    end
end


function EAB:ApplyShapesForBar(barKey)
    if InCombatLockdown() then ns._eabApplyDeferred = true return end
    if not self.db then return end
    if ns.AB_Style() ~= "eui" then return end
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local shape = s.buttonShape or "none"
    local zoom = ((s.iconZoom or self.db.profile.iconZoom or 5.5)) / 100
    local brdSz = ResolveBorderThickness(s)
    local brdOn = brdSz > 0
    local brdColor = s.shapeBorderColor or s.borderColor or { r=0, g=0, b=0, a=1 }
    local brdR, brdG, brdB, brdA = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end end
    end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local masqueOwns = ns.MasqueOwnsBar(barKey)
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            if masqueOwns then
                btn:SetHitRectInsets(0, 0, 0, 0)
                local fd = EFD(btn)
                if fd.shapeApplied or fd.cropped then
                    ApplyShapeToButton(btn, "none", false, brdR, brdG, brdB, brdA, brdSz, zoom)
                elseif fd.shapeBorder then
                    fd.shapeBorder:Hide()
                    EFD(fd.shapeBorder).wantsShow = false
                end
            else
                ApplyShapeToButton(btn, shape, brdOn, brdR, brdG, brdB, brdA, brdSz, zoom)
            end
        end
    end
    LayoutBar(barKey)
    -- A shape change moves the bar in or out of Match Bar Border eligibility;
    -- the copies' style inputs all go through ApplyBordersForBar's own sync.
    ns._ixBarSync(barKey, true)
end

function EAB:ApplyShapes()
    if not self.db then return end
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyShapesForBar(info.key)
    end
end

function EAB:ApplyPaddingForBar(barKey)
    LayoutBar(barKey)
end

function EAB:ApplyButtonSizeForBar(barKey)
    LayoutBar(barKey)
end

function EAB:ApplyIconRowOverrides(barKey)
    LayoutBar(barKey)
    self:ApplyAlwaysShowButtons(barKey)
end

function EAB:ApplyBarOpacity(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end
    -- In mouseover mode the hover system owns alpha (0 when unhovered,
    -- mouseoverAlpha when hovered). Don't override it here.
    if not s.mouseoverEnabled then
        local a = s.mouseoverAlpha or 1
        frame:SetAlpha(a)
        _fadeAlpha[frame] = a
        if barKey == "MainBar" then SyncPagingAlpha(s.mouseoverAlpha or 1) end
    end
end

function EAB:BarSupportsOrientation(barKey)
    local info = BAR_LOOKUP[barKey]
    return info and info.count ~= nil or false
end

function EAB:GetOrientationForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return true end
    return s.orientation ~= "vertical"
end

function EAB:LayoutAnchoredBarsFrom(targetKey, depth)
    if not targetKey or (depth or 0) > 12 then return end
    local adb = _G.EllesmereUIDB and _G.EllesmereUIDB.unlockAnchors
    if not adb then return end
    local nextDepth = (depth or 0) + 1
    for childKey, ai in pairs(adb) do
        if ai.target == targetKey and childKey ~= targetKey
            and self.db.profile.bars[childKey] and barFrames[childKey] then
            LayoutBar(childKey)
            self:LayoutAnchoredBarsFrom(childKey, nextDepth)
        end
    end
end

function EAB:SetOrientationForBar(barKey, isHorizontal)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    s.orientation = isHorizontal and "horizontal" or "vertical"
    -- Reset growth direction to orientation-appropriate default when switching
    local g = (s.growDirection or "up"):upper()
    if isHorizontal then
        -- Switching to horizontal: if current growth is vertical-only, reset
        if g == "UP" or g == "DOWN" then s.growDirection = "center" end
    else
        -- Switching to vertical: if current growth is horizontal-only, reset
        if g == "LEFT" or g == "RIGHT" then s.growDirection = "up" end
    end
    LayoutBar(barKey)
    self:LayoutAnchoredBarsFrom(barKey, 0)
end

function EAB:SetGrowDirectionForBar(barKey, dir)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    s.growDirection = dir or "up"
    LayoutBar(barKey)
    self:LayoutAnchoredBarsFrom(barKey, 0)
end

-------------------------------------------------------------------------------
--  Font / Keybind Text
-------------------------------------------------------------------------------
-- Button text anchoring (keybind / charges / macro name). Opt-in per bar via
-- <text>Anchor; nil or false = stock placement, handled by the caller, which only
-- calls in here once an anchor is set. Returns false for an anchor it does not
-- know (a hand-edited profile), so the caller falls back to stock. The text is
-- stretched across the chosen edge (both corners anchored, same as the stock
-- keybind placement) and JustifyH does the alignment, so it holds regardless
-- of the font string's own width. Shared with
-- the options preview, hence on EAB not a local.
EAB.TEXT_ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
-- The spacing each stock placement carries (keybind -1/-3, charges -1/+4,
-- macro +1/+4). It lives in a text's offset boxes while a position is set: a
-- position pick swaps the old corner's spacing for the new one's and keeps the
-- user's own nudge on top, so no pick ever moves the text by the spacing alone.
-- Not applied on the drawing side: there, 0/0 is the corner itself.
EAB.TEXT_INSET_X = 1
EAB.TEXT_INSET_Y = { keybind = 3, count = 4, macro = 4 }

-- Offsets that reproduce a text's stock spacing at the position just picked.
-- 0/0 for a position PlaceButtonText does not know (hand-edited, or from a newer
-- build): that text draws at the stock placement, which carries its own spacing.
function EAB.StockTextOffsets(kind, anchor)
    if not EAB.TEXT_ANCHOR_JUSTIFY[anchor] then return 0, 0 end
    local x = 0
    if anchor:find("LEFT", 1, true) then x = EAB.TEXT_INSET_X
    elseif anchor:find("RIGHT", 1, true) then x = -EAB.TEXT_INSET_X end
    local y = EAB.TEXT_INSET_Y[kind] or 0
    if anchor:find("TOP", 1, true) then y = -y end
    return x, y
end

-- Writes a button-shape preset's keybind / charges offsets onto bar settings `bs`.
-- The preset values are relative to the stock placement; a text with a position
-- also carries that corner's stock spacing, as a position pick gives it.
function EAB.ApplyShapeTextOffsets(bs, kbX, kbY, ctX, ctY)
    local ax, ay = 0, 0
    if bs.keybindAnchor then ax, ay = EAB.StockTextOffsets("keybind", bs.keybindAnchor) end
    bs.keybindOffsetX, bs.keybindOffsetY = kbX + ax, kbY + ay
    ax, ay = 0, 0
    if bs.countAnchor then ax, ay = EAB.StockTextOffsets("count", bs.countAnchor) end
    bs.countOffsetX, bs.countOffsetY = ctX + ax, ctY + ay
end
EAB.TEXT_ANCHOR_JUSTIFY = {
    TOPLEFT = "LEFT", TOP = "CENTER", TOPRIGHT = "RIGHT",
    BOTTOMLEFT = "LEFT", BOTTOM = "CENTER", BOTTOMRIGHT = "RIGHT",
}
function EAB.PlaceButtonText(fs, parent, anchor, ox, oy)
    local justify = anchor and EAB.TEXT_ANCHOR_JUSTIFY[anchor]
    if not justify then return false end
    -- Offset 0/0 is the corner the position names, with no inset of its own: the
    -- boxes are the only thing between the text and the edge, and they read the
    -- same at all six positions. The spacing the three stock placements carry
    -- (EAB.TEXT_INSET_*) rides in those boxes (see EAB.TEXT_INSET_X).
    local edge = (anchor:find("TOP", 1, true) and "TOP") or "BOTTOM"
    local y = oy or 0
    ox = ox or 0
    fs:ClearAllPoints()
    fs:SetPoint(edge .. "LEFT", parent, edge .. "LEFT", ox, y)
    fs:SetPoint(edge .. "RIGHT", parent, edge .. "RIGHT", ox, y)
    local prevJustify = fs:GetJustifyH()
    fs:SetJustifyH(justify)
    -- A justification change alone does not re-lay the string out (SetPoint with
    -- unchanged values and SetText with unchanged text are no-ops), so only then
    -- clear and restore the text. issecretvalue first: a secret count must not be
    -- compared.
    if prevJustify ~= justify then
        local text = fs:GetText()
        if (issecretvalue and issecretvalue(text)) or (text and text ~= "") then
            fs:SetText("")
            fs:SetText(text)
        end
    end
    return true
end

function EAB:ApplyFontsForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local fontPath = EllesmereUI.GetFontPath("actionBars") or FONT_PATH
    local hideKB = s.hideKeybind
    local kbSize = s.keybindFontSize or 12
    -- Stance/pet bar buttons are smaller (30px vs 45px) shrink keybind text
    -- by 2px so it doesn't overwhelm the icon.
    local info = BAR_LOOKUP[barKey]
    if info and (info.isStance or info.isPetBar) then kbSize = max(kbSize - 2, 6) end
    local kbColor = s.keybindFontColor or { r=1, g=1, b=1 }
    local ctSize = s.countFontSize or 12
    local ctColor = s.countFontColor or { r=1, g=1, b=1 }
    local kbOX = s.keybindOffsetX or 0
    local kbOY = s.keybindOffsetY or 0
    local kbAnchor = s.keybindAnchor
    local ctOX = s.countOffsetX or 0
    local ctOY = s.countOffsetY or 0
    local ctAnchor = s.countAnchor
    local hideMacro = s.hideMacroText
    local macroSize = s.macroFontSize or 12
    if info and (info.isStance or info.isPetBar) then macroSize = max(macroSize - 2, 6) end
    local macroColor = s.macroFontColor or { r=1, g=1, b=1 }
    local macroOX = s.macroOffsetX or 0
    local macroOY = s.macroOffsetY or 0
    local macroAnchor = s.macroAnchor
    local RANGE_INDICATOR = RANGE_INDICATOR or "\226\128\162"

    for i = 1, #buttons do
        local btn = buttons[i]
        if not btn then break end

        -- Keybind text
        local hk = btn.HotKey
        if hk then
            if hideKB then
                hk:SetText("")
                hk:Hide()
            else
                -- Get binding text
                local bindingAction
                local info = BAR_LOOKUP[barKey]
                if info and not info.isStance and not info.isPetBar then
                    if barKey == "MainBar" then
                        bindingAction = "ACTIONBUTTON" .. i
                    else
                        local bindPrefix = BINDING_MAP[barKey]
                        if bindPrefix then
                            bindingAction = bindPrefix .. i
                        end
                    end
                elseif info and info.isStance then
                    bindingAction = "SHAPESHIFTBUTTON" .. i
                elseif info and info.isPetBar then
                    bindingAction = "BONUSACTIONBUTTON" .. i
                end

                local key1 = bindingAction and GetBindingKey(bindingAction)
                local text = key1 and FormatHotkeyText(key1) or ""
                if text == RANGE_INDICATOR or text == "\226\128\162" then text = "" end
                hk:SetText(text)
                hk:Show()
                EllesmereUI.ApplyIconTextFont(hk, fontPath, kbSize, "actionBars")
                hk:SetTextColor(kbColor.r, kbColor.g, kbColor.b)
                -- Anchor unset (the default) = the stock placement below; the
                -- nil test is the whole cost of the feature while it is off.
                if not (kbAnchor and EAB.PlaceButtonText(hk, btn, kbAnchor, kbOX, kbOY)) then
                    hk:ClearAllPoints()
                    hk:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1 + kbOX, -3 + kbOY)
                    hk:SetPoint("TOPLEFT", btn, "TOPLEFT", 4 + kbOX, -3 + kbOY)
                    hk:SetJustifyH("RIGHT")
                end
            end
        end

        -- Count / charges text
        local ct = btn.Count
        if ct then
            EllesmereUI.ApplyIconTextFont(ct, fontPath, ctSize, "actionBars")
            ct:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
            if not (ctAnchor and EAB.PlaceButtonText(ct, btn, ctAnchor, ctOX, ctOY)) then
                ct:ClearAllPoints()
                ct:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
                ct:SetJustifyH("RIGHT")
            end
        end

        -- Macro name text
        local nm = btn.Name
        if nm then
            if hideMacro then
                nm:SetAlpha(0)
            else
                nm:SetAlpha(1)
                EllesmereUI.PrimeFontShadow(nm, false)
                nm:SetFont(fontPath, macroSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                nm:SetTextColor(macroColor.r, macroColor.g, macroColor.b)
                if not (macroAnchor and EAB.PlaceButtonText(nm, btn, macroAnchor, macroOX, macroOY)) then
                    nm:ClearAllPoints()
                    nm:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1 + macroOX, 4 + macroOY)
                    nm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1 + macroOX, 4 + macroOY)
                    nm:SetJustifyH("CENTER")
                end
            end
        end
    end
end

function EAB:ApplyFonts()
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyFontsForBar(info.key)
    end
    self:ApplyCooldownFonts()
end

-- Color-only re-assert for custom keybind text colors. Blizzard's button
-- refreshes (UpdateAction/UpdateHotkeys, usable-state recolor) reset HotKey's
-- text color, reverting a custom color to white on target change, combat
-- transitions, drag-and-drop, and usability flips until the next full
-- ApplyFonts. Re-applies ONLY the color -- no fonts, no anchors -- and does no
-- button work at all for bars on the default white.
function EAB:ReapplyHotkeyColors()
    local bars = self.db and self.db.profile and self.db.profile.bars
    if not bars then return end
    for barKey, buttons in pairs(barButtons) do
        local s = bars[barKey]
        local c = s and not s.hideKeybind and s.keybindFontColor
        if c and (c.r ~= 1 or c.g ~= 1 or c.b ~= 1) then
            for i = 1, #buttons do
                local hk = buttons[i] and buttons[i].HotKey
                if hk then hk:SetTextColor(c.r, c.g, c.b) end
            end
        end
    end
end

-- One deferred color pass per event burst: the dispatcher can see dozens of
-- ACTIONBAR_SLOT_CHANGED per second while mouseover-conditional macros
-- re-resolve, and the pending flag coalesces the burst into one next-frame
-- pass. State lives on EAB.
function EAB:QueueHotkeyColorReassert()
    if self._kbColorPending then return end
    self._kbColorPending = true
    self._kbColorRunner = self._kbColorRunner or function()
        EAB._kbColorPending = false
        EAB:ReapplyHotkeyColors()
    end
    C_Timer_After(0, self._kbColorRunner)
end

-------------------------------------------------------------------------------
--  Cooldown Countdown Font Override
-------------------------------------------------------------------------------
function EAB_VTABLE.CooldownFonts.GetSettings(s)
    return (EllesmereUI.GetFontPath("actionBars")) or FONT_PATH,
        s.cooldownFontSize or 12,
        s.cooldownTextXOffset or 0,
        s.cooldownTextYOffset or 0,
        s.cooldownTextColor or { r = 1, g = 1, b = 1 },
        s.cooldownFontFit or false
end

-- Cap the configured countdown size against the button it must fit inside. The size is
-- absolute while the countdown string is Blizzard's, formatted in the CLIENT locale:
-- the two-character "5m" of an English client is five characters on other locales, so
-- one setting fits one client and overflows another. A textured border only HIDES the
-- spill (frame anchors OUTSIDE the button -- see ApplyBorderStyle); a solid border sits
-- on the edge and covers nothing. OPT-IN per bar (cdFit, "Fit Size to Button"): the
-- configured size wins unless the bar opts in, so the off path returns it untouched.
function EAB_VTABLE.CooldownFonts.EffectiveSize(cdFrame, cdSize, cdFit)
    if not cdFit then return cdSize end
    local host = cdFrame and (cdFrame:GetParent() or cdFrame)
    if not (host and host.GetWidth and host.GetHeight) then return cdSize end
    local w, h = host:GetWidth(), host:GetHeight()
    if not w or not h or w <= 0 or h <= 0 then
        return cdSize   -- not laid out yet; re-applied on the next layout pass
    end
    -- Smaller dimension, not width: buttonWidth and buttonHeight are separate
    -- settings, so a wide short button still overflows vertically. The tighter
    -- axis is the one that constrains.
    local dim = (w < h) and w or h
    local cap = math.floor(dim * 0.40)
    if cap < 5 then cap = 5 end                 -- never shrink to illegibility
    return (cdSize > cap) and cap or cdSize
end

function EAB_VTABLE.CooldownFonts.ApplyToFrame(cdFrame, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
    if not cdFrame then return false end

    -- Stamp on the EFFECTIVE size, not requested: keyed to the request, a bar
    -- resize would leave the setting unchanged, match the stamp, and freeze
    -- the old size. Toggling the fit option changes eff too, so that flip re-applies.
    local eff = EAB_VTABLE.CooldownFonts.EffectiveSize(cdFrame, cdSize, cdFit)

    -- Skip if these exact settings were already applied to this frame
    local cdfd = EFD(cdFrame)
    local stamp = cdfd.cdFontStamp
    local cr, cg, cb = cdColor.r, cdColor.g, cdColor.b
    if stamp and stamp[1] == fontPath and stamp[2] == eff
       and stamp[3] == cdOX and stamp[4] == cdOY
       and stamp[5] == cr and stamp[6] == cg and stamp[7] == cb then
        return true
    end

    local regions = { cdFrame:GetRegions() }
    for ri = 1, #regions do
        local region = regions[ri]
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            EllesmereUI.ApplyIconTextFont(region, fontPath, eff, "actionBars")
            region:SetTextColor(cr, cg, cb)
            region:ClearAllPoints()
            region:SetPoint("CENTER", cdFrame, "CENTER", cdOX, cdOY)
            cdfd.cdFontStamp = { fontPath, eff, cdOX, cdOY, cr, cg, cb }
            return true
        end
    end

    return false
end

function EAB_VTABLE.CooldownFonts.ApplyToButton(btn, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
    if not btn then return end

    local applied = EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.cooldown, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
    -- Retry when EITHER frame failed: the charge cooldown's FontString is
    -- created later than the main one's, so a main-only gate would strand the
    -- recharge countdown in Blizzard's default font permanently.
    local appliedCharge = (not btn.chargeCooldown)
        or EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.chargeCooldown, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
    if applied and appliedCharge then return end

    -- Some cooldown frames create their countdown FontString lazily on the
    -- first update after SetCooldown(). Retry once on the next frame.
    C_Timer_After(0, function()
        EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.cooldown, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
        EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.chargeCooldown, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
    end)
end

function EAB:ApplyCooldownFontsForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local fontPath, cdSize, cdOX, cdOY, cdColor, cdFit = EAB_VTABLE.CooldownFonts.GetSettings(s)

    C_Timer.After(0, function()
        for i = 1, #buttons do
            local btn = buttons[i]
            if not btn then break end
            EAB_VTABLE.CooldownFonts.ApplyToButton(btn, fontPath, cdSize, cdOX, cdOY, cdColor, cdFit)
        end
    end)
end

function EAB:ApplyCooldownFonts()
    EAB_VTABLE.CooldownFonts.HookAll()
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyCooldownFontsForBar(info.key)
    end
end

-- Show Equipped Item Color, live: every square button's Border takes the look
-- (and shows on an equipped item's button, in its rarity color) or hides
-- again. The Blizzard and Classic styles keep their own equipped border, so
-- EllesmereUI style only. changedOnly (ApplyAll: profile / spec switches,
-- imports) repaints only when the value differs from the one last painted;
-- the first pass just records it, as button setup painted from it.
function EAB:ApplyEquippedBorder(changedOnly)
    local on = self.db.profile.showEquippedBorder and true or false
    local was = ns._eabEqBorderOn
    ns._eabEqBorderOn = on
    if changedOnly and (was == nil or was == on) then return end
    if ns.AB_Style() ~= "eui" then return end
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                local bd = btn.Border
                if bd and EFD(btn).squared then
                    if on then
                        ns.AB_SyncEquippedBorder(btn, btn:GetAttribute("action"))
                    else
                        bd:Hide()
                        bd:SetAlpha(0)
                    end
                end
            end
        end
    end
end

-- Immediate re-apply of the Hide Count at 0 alpha on every button, so the options
-- toggle applies on click instead of waiting for the next count event. Alpha only --
-- the count TEXT stays whatever its owners last wrote. Cold path: options clicks only.
function EAB:RefreshAllCounts()
    if not (C_ActionBar and C_ActionBar.GetActionDisplayCount) then return end
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local btns = barButtons[info.key]
            if btns then
                for _, btn in ipairs(btns) do
                    if btn.Count then
                        local action = btn:GetAttribute("action")
                        if action and HasAction(action) then
                            ns._EABZeroCountAlpha(EFD(btn), btn.Count,
                                C_ActionBar.GetActionDisplayCount(action), action)
                        end
                    end
                end
            end
        end
    end
end

-- Re-apply "Alpha when on CD" across every action button: on setting change (immediate
-- feedback plus a clean restore to full alpha at 100) and on the main apply. Same
-- secret-safe curve detection as the live ACTIONBAR_UPDATE_COOLDOWN handler.
function EAB:ApplyCDAlphaAll()
    local pdb = self.db and self.db.profile
    local cdAlpha = (pdb and pdb.alphaWhenOnCD) or 100
    local on = cdAlpha ~= 100
    -- This used to carry its own copy of the on-cooldown test, and the copy
    -- drifted: it treated ANY charge spell as being on a real cooldown, so
    -- touching the slider (or any full apply) during a GCD dimmed every charge
    -- spell sitting at full charges. Delegate to the live classifier instead,
    -- which owns the GCD threshold and the charge rules in one place. Restore
    -- to full alpha first so setting the slider back to 100 -- and every button
    -- the classifier declines to dim -- lands on a clean icon.
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local btns = barButtons[info.key]
            if btns then
                for _, btn in ipairs(btns) do
                    local icon = btn and btn.icon
                    if icon then
                        icon:SetAlpha(1)
                        if on and EAB._RefreshCooldownVisuals then
                            EAB._RefreshCooldownVisuals(btn)
                        end
                    end
                end
            end
        end
    end
end

function EAB:ApplySlotBackgroundColor()
    local pdb = self.db and self.db.profile
    if not pdb then return end
    local c = pdb.slotBgColor or { r = 0.15, g = 0.15, b = 0.15 }
    local a = pdb.slotBgOpacity
    if a == nil then a = 50 end
    a = a / 100
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                local bfd = btn and EFD(btn)
                if bfd and bfd.slotBG then
                    bfd.slotBG:SetColorTexture(c.r or 0.15, c.g or 0.15, c.b or 0.15, a)
                end
            end
        end
    end
end

-- Custom cooldown-swipe color + opacity on every button's cooldown. Cheap and
-- idempotent (SetSwipeColor persists on the frame), so it runs on the main apply
-- and on setting change. Defaults mirror the Blizzard look.
function EAB:ApplyCooldownSwipeColor()
    local pdb = self.db and self.db.profile
    if not pdb then return end
    local c = pdb.cdSwipeColor or { r = 0, g = 0, b = 0 }
    local a = (pdb.cdSwipeAlpha or 80) / 100
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                local cd = btn and btn.cooldown
                if cd and cd.SetSwipeColor then
                    pcall(cd.SetSwipeColor, cd, c.r or 0, c.g or 0, c.b or 0, a)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Bar Background
-------------------------------------------------------------------------------
local barBackgrounds = {}  -- [barKey] = { fill = Texture, border = Frame }

function EAB:ApplyBackgroundForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end

    if not s.bgEnabled then
        local background = barBackgrounds[barKey]
        if background then
            background.fill:Hide()
            if EllesmereUI and EllesmereUI.ApplyBorderStyle then
                EllesmereUI.ApplyBorderStyle(background.border, 0, 0, 0, 0, s.bgBorderTexture or "solid")
            else
                background.border:Hide()
            end
        end
        return
    end

    local background = barBackgrounds[barKey]
    if not background then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        border:EnableMouse(false)
        border:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
        background = { fill = fill, border = border }
        barBackgrounds[barKey] = background
    end

    local c = s.bgColor or { r=0, g=0, b=0, a=0.5 }
    local alpha = s.bgOpacity ~= nil and s.bgOpacity / 100 or c.a
    background.fill:SetColorTexture(c.r, c.g, c.b, alpha)
    -- bgPadX/bgPadY remain as fallbacks for profiles predating bgPadding.
    local padding = s.bgPadding
    local padX = padding ~= nil and padding or (s.bgPadX or 0)
    local padY = padding ~= nil and padding or (s.bgPadY or 0)
    local multiplierX = math.max(1, math.min(4, math.floor((s.bgMultiplierX or 1) + 0.5)))
    local multiplierY = math.max(1, math.min(4, math.floor((s.bgMultiplierY or 1) + 0.5)))
    local directionX = s.bgExpandDirectionX or "right"
    local directionY = s.bgExpandDirectionY or "up"
    local iconPadding = s.buttonPadding or 0
    local growX = (multiplierX - 1) * ((frame:GetWidth() or 0) + iconPadding)
    local growY = (multiplierY - 1) * ((frame:GetHeight() or 0) + iconPadding)
    local left, right, top, bottom = -padX, padX, padY, -padY
    if directionX == "left" then left = left - growX else right = right + growX end
    if directionY == "down" then bottom = bottom - growY else top = top + growY end
    background.fill:ClearAllPoints()
    background.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    background.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    background.fill:Show()

    local border = background.border
    border:SetFrameLevel(s.bgBorderBehind and math.max(0, frame:GetFrameLevel() - 1) or frame:GetFrameLevel())
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    if EllesmereUI and EllesmereUI.ApplyBorderStyle then
        local bc = s.bgBorderColor or { r=0, g=0, b=0, a=1 }
        local thicknessKey = s.bgBorderThickness or "none"
        local thickness = ns.BORDER_THICKNESS and ns.BORDER_THICKNESS[thicknessKey]
        local borderSize = thickness and thickness.regular or 0
        -- Exact size (bgBorderThicknessPx) while it pairs with this step and texture; nil = legacy path.
        local bgPx = EllesmereUI.BorderPx(s.bgBorderThicknessPx, borderSize, s.bgBorderTexture)
        EllesmereUI.ApplyBorderStyle(border, borderSize,
            bc.r, bc.g, bc.b, bc.a or 1, s.bgBorderTexture or "solid",
            s.bgBorderOffsetX, s.bgBorderOffsetY,
            s.bgBorderShiftX, s.bgBorderShiftY,
            "actionbars", thicknessKey, nil, bgPx)
    else
        border:Hide()
    end
end

-------------------------------------------------------------------------------
--  Blizzard Icon Background (per-button slot texture)
-------------------------------------------------------------------------------
function EAB:ApplyIconBackgroundForBar(barKey)
    local pr = self.db.profile
    local buttons = barButtons[barKey]
    if not buttons then return end
    local show = pr.showBlizzIconBg or false
    -- Session gate for the per-button OnEvent hook below: feature defaults
    -- OFF and the hook rides every event every button receives, so the
    -- disabled path must cost one boolean. This apply pass owns the visuals
    -- on every settings edge, so the flag can't go stale.
    ns._iconBgOn = show
    local alpha = pr.blizzIconBgAlpha or 1
    local blizzStyle = ns.AB_Style() ~= "eui"
    local inset = blizzStyle and 0 or 4
    for i = 1, #buttons do
        local btn = buttons[i]
        if not btn then break end
        local bfd = EFD(btn)
        if not show then
            -- Disabled (the default): build nothing. Only a clip left over
            -- from an earlier ON has anything to hide; every other reader of
            -- iconBg / iconBgClip (slot sync, shape masks) nil-checks.
            if bfd.iconBgClip then bfd.iconBgClip:Hide() end
        else
            -- Only show icon background on empty slots
            local okHA, hasAction = pcall(btn.HasAction, btn)
            hasAction = okHA and hasAction
            if not bfd.iconBgClip then
                local clip = CreateFrame("Frame", nil, btn)
                clip:SetAllPoints(btn)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(math.max(1, btn:GetFrameLevel() - 1))
                clip:EnableMouse(false)
                local bg = clip:CreateTexture(nil, "BACKGROUND", nil, -1)
                -- Built once; the look is reload-gated, so the stock looks
                -- take the retail slot art here for the session.
                if blizzStyle then
                    ns.AB_StockAtlas(bg, "UI-HUD-ActionBar-IconFrame-Slot")
                else
                    bg:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
                end
                bfd.iconBgClip = clip
                bfd.iconBg = bg
            end
            -- Auto-update on button events. ACTIONBAR_SLOT_CHANGED is not
            -- delivered to buttons (central dispatcher owns it and syncs the
            -- clip there); this hook covers the remaining per-button events.
            -- Installed on the first ON edge only: a script hook rides every
            -- event every button receives and cannot be removed, so a
            -- session that never enables the feature never pays even its
            -- early-return. The EFD flag survives bar rebuilds that reuse
            -- the button frame, so the hook never stacks.
            if not bfd.iconBgHooked then
                bfd.iconBgHooked = true
                btn:HookScript("OnEvent", function(self)
                    -- Feature gate FIRST: turned off later in the session, the
                    -- hook must cost one boolean. The apply pass hides a
                    -- freshly-disabled clip on the settings edge, never this hook.
                    if not ns._iconBgOn then return end
                    local sfd = EFD(self)
                    local c = sfd.iconBgClip
                    if c then
                        local okHA, ha = pcall(self.HasAction, self)
                        c:SetShown(not (okHA and ha))
                    end
                end)
            end
            bfd.iconBg:ClearAllPoints()
            bfd.iconBg:SetPoint("TOPLEFT", btn, "TOPLEFT", -inset, inset)
            bfd.iconBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", inset, -inset)
            bfd.iconBg:SetAlpha(alpha)
            -- Apply custom shape mask if active (shapes run before this)
            if bfd.shapeMask and bfd.shapeApplied then
                pcall(bfd.iconBg.AddMaskTexture, bfd.iconBg, bfd.shapeMask)
            end
            bfd.iconBgClip:SetShown(not hasAction)
        end
    end
end

-------------------------------------------------------------------------------
--  Always Show Buttons
-------------------------------------------------------------------------------
function EAB:ApplyAlwaysShowButtons(barKey)
    -- Hard-dormant bars skip the whole pass; the dormancy reveal reconcile
    -- runs it once when a settings edge brings the bar back.
    if ns._eabBarNever[barKey] then return end
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local info = BAR_LOOKUP[barKey]
    if not info then return end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    -- Stance bar always hides empty slots (count is dynamic per class)
    if info.isStance then showEmpty = false end

    -- Respect icon cutoff (hoisted above the grid half so the signature
    -- below sees every input)
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
    if numIcons < 1 then numIcons = 1 end

    local quickKeybindVisible = ShouldQuickKeybindSurfaceBar(s)
    local clickable = quickKeybindVisible or not s.clickThrough

    -- Default-config fast path. With Always Show Buttons ON, per-button visibility is
    -- CONSTANT (visible regardless of slot contents), so a pass that already asserted
    -- this configuration has nothing content-dependent left to do -- yet form/page
    -- flips queue it per tick at ~140 secure-attribute reads plus idempotent writes.
    -- The signature covers every input; settings changes alter it, drag restores wipe
    -- the stamp table, and combat passes never stamp (skipped writes heal on the next
    -- unlocked pass). Hide-empty bars always run: visibility tracks slot contents.
    local asbSig = (showEmpty and 1 or 0) + (quickKeybindVisible and 2 or 0)
        + (clickable and 4 or 0) + numIcons * 8
    local asbSt = ns._asbStamp
    if not asbSt then asbSt = {}; ns._asbStamp = asbSt end
    if showEmpty and asbSt[barKey] == asbSig and not _gridState.shown
        and not InCombatLockdown() then
        return
    end

    -- Update the SHOWGRID.ALWAYS flag on managed action buttons
    if not InCombatLockdown() and not info.isStance and not info.isPetBar then
        for _, btn in ipairs(buttons) do
            if btn then
                SetShowGridInsecure(btn, showEmpty, SHOWGRID.ALWAYS)
                -- Heal transient drag/spellbook bits. A COMBAT drag reveals
                -- empty slots through the secure path (which honors these bits),
                -- but its HIDEGRID can land while the insecure handler is
                -- combat-gated, leaving a stuck bit that keeps empty slots
                -- visible after combat. Runs from the post-drag re-assert and
                -- the regen-deferred ApplyAll, both outside any live drag.
                if not _gridState.shown then
                    SetShowGridInsecure(btn, false, SHOWGRID.GAME_EVENT)
                    SetShowGridInsecure(btn, false, SHOWGRID.SPELLBOOK)
                end
            end
        end
    end

    -- During a spell drag, we leave the controller's secure visibility path
    -- alone. QuickKeybind still needs the normal visibility refresh so its
    -- dedicated KEYBOUND flag can show empty slots on EAB-owned bars.
    if _gridState.shown and not _quickKeybindState.open then return end
    local lastVisible = 0
    for i = 1, numIcons do
        local btn = buttons[i]
        if btn then
            if info.nativeMainBar then
                EAB_VTABLE.MainBarPageSync.SetButtonConfig(btn, true, showEmpty)
            end
            local hasAction = ButtonHasAction(btn, info.blizzBtnPrefix)
            local visible = showEmpty or hasAction or quickKeybindVisible

            local bfd = EFD(btn)
            if bfd.slotBG then
                bfd.slotBG:SetShown(visible)
            end
            if bfd.borders and not (bfd.shapeMask and bfd.shapeMask:IsShown()) then
                bfd.borders:SetShown(visible)
            end
            if bfd.shapeBorder then
                bfd.shapeBorder:SetShown(visible and EFD(bfd.shapeBorder).wantsShow == true)
            end

            -- Stamp the secure-side facts the restricted reveal needs
            -- (see the SetShowGrid snippet): this button is within the icon
            -- cutoff, whether empty slots are shown at all, and whether a
            -- reveal may enable mouse clicks. eab-showempty is what lets the
            -- paging snippet (ns._eabPageVisSnippet) re-evaluate a parked slot
            -- during combat on every bar, not just MainBar -- without it a
            -- custom-paged bar 2-10 leaves the slot statehidden for the whole
            -- fight.
            if not InCombatLockdown() then
                btn:SetAttributeNoHandler("eab-withincutoff", 1)
                btn:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
                btn:SetAttributeNoHandler("eab-click", clickable and 1 or 0)
            end
            if not visible then
                btn:SetAlpha(0)
                -- Invisible empty slots must not catch mouse events; statehidden
                -- makes the secure UpdateShown snippet keep them hidden.
                SafeEnableMouse(btn, false)
                if not InCombatLockdown() then
                    btn:SetAttributeNoHandler("statehidden", true)
                    btn:Hide()
                    ns._eabMarkParked(btn, info, true)
                else
                    ns._eabMarkParked(btn, info)
                end
            else
                if not InCombatLockdown() then
                    btn:SetAttributeNoHandler("statehidden", nil)
                    btn:SetAttribute("showgrid", 1)
                    btn:Show()
                end
                -- Always restore button alpha to 1. The bar frame's own
                -- alpha (via mouseover fade) handles overall visibility.
                btn:SetAlpha(1)
                bfd.parkA0 = nil
                -- Restore mouse state based on bar's click-through setting.
                -- When click-through is on but mouseover is enabled, keep
                -- mouse motion so OnEnter/OnLeave still fire for hover fade.
                if clickable then
                    SafeEnableMouse(btn, true)
                elseif s.mouseoverEnabled then
                    SafeEnableMouseMotionOnly(btn, true)
                else
                    SafeEnableMouse(btn, false)
                end
                lastVisible = i
            end
        end
    end
    -- Hide buttons beyond cutoff
    for i = numIcons + 1, #buttons do
        local btn = buttons[i]
        if btn then
            if info.nativeMainBar then
                EAB_VTABLE.MainBarPageSync.SetButtonConfig(btn, false, showEmpty)
            end
            btn:SetAlpha(0)
            SafeEnableMouse(btn, false)
            if not InCombatLockdown() then
                -- Cutoff buttons are excluded from the secure drag reveal:
                -- revealing them would paint slots the user configured away.
                btn:SetAttributeNoHandler("eab-withincutoff", 0)
                btn:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
                btn:SetAttributeNoHandler("statehidden", true)
                btn:Hide()
                ns._eabMarkParked(btn, info, true)
            else
                ns._eabMarkParked(btn, info)
            end
        end
    end

    -- Stamp only fully-applied passes: a combat pass skipped its secure
    -- writes and must not suppress the healing re-run.
    if not InCombatLockdown() then
        asbSt[barKey] = asbSig
    else
        asbSt[barKey] = nil
    end

    -- Frame size stays as LayoutBar left it: the mouseover OnEnter handler
    -- already checks cursor proximity to visible buttons, and shrinking the
    -- frame can misposition bars whose anchor point is not TOPLEFT.
end

-------------------------------------------------------------------------------
--  Main Bar Page Sync: EAB owns MainBar paging via a custom secure parent, so
--  Blizzard's stock ActionBarController never runs its "set actionpage, then
--  refresh every button" sequence for ActionButton1-12 (the actionpage half is
--  mirrored onto MainActionBar by the MainBar _onstate-page handler). Restored by tracking
--  page-sensitive visibility inputs on the buttons, then using a secure
--  child-update from the MainBar frame to drive the buttons' normal
--  OnAttributeChanged -> UpdateAction path in combat.
-------------------------------------------------------------------------------
function EAB_VTABLE.MainBarPageSync.SetButtonConfig(btn, withinCutoff, showEmpty)
    if not btn then return end
    if InCombatLockdown() then ns._eabApplyDeferred = true return end
    btn:SetAttributeNoHandler("eab-withincutoff", withinCutoff and 1 or 0)
    btn:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
end

function EAB_VTABLE.MainBarPageSync.Queue()
    local state = EAB_VTABLE.MainBarPageSync
    if state.pending then return end
    state.pending = true
    C_Timer_After(0, function()
        state.pending = false
        if InCombatLockdown() then ns._eabApplyDeferred = true return end
        if not EAB or not EAB.db then return end
        EAB:ApplyAlwaysShowButtons("MainBar")
    end)
end

function EAB_VTABLE.MainBarPageSync.InstallAll()
    if InCombatLockdown() then ns._eabApplyDeferred = true return end
    local buttons = barButtons["MainBar"]
    if not buttons then return end
    for _, btn in ipairs(buttons) do
        EAB_VTABLE.MainBarPageSync.InstallButton(btn)
    end
end

function EAB_VTABLE.MainBarPageSync.InstallButton(btn)
    if not btn or btn:GetAttribute("_eabPageSyncInstalled") or InCombatLockdown() then return end

    -- Bake the base index directly into the snippet as a literal so it
    -- doesn't depend on attribute reads in the restricted environment.
    local info = buttonToBar[btn]
    local baseIdx = info and info.index or 1

    -- Only the slot arithmetic is interpolated. The body is concatenated raw:
    -- it contains a modulo, and string.format eats a bare "%" as a broken
    -- conversion spec.
    btn:SetAttributeNoHandler("_childupdate-eab-page", ([[
        local page = tonumber(message) or 1
        local slot = %d + (page - 1) * %d
        self:SetAttribute("action", slot)
    ]]):format(baseIdx, NUM_ACTIONBAR_BUTTONS) .. [[
        local withinCutoff = self:GetAttribute("eab-withincutoff") ~= 0
        local visible = withinCutoff

        if visible and self:GetAttribute("eab-showempty") == 0 then
            visible = HasAction(slot)
        end

        -- Transient grid reveal outranks the empty-slot park (see
        -- ns._eabPageVisSnippet, which carries the same rule for bars 2-10):
        -- a page flip during a combat spell drag must not delete the drop
        -- targets. Bits 2+ only -- bit 1 is Blizzard's CVAR reason.
        local grid = self:GetAttribute("showgrid") or 0
        local transient = withinCutoff and (grid % 32) >= 2

        local hidden = self:GetAttribute("statehidden")
        local changed = false

        if visible or transient then
            if visible and hidden then
                self:SetAttribute("statehidden", nil)
                changed = true
            end
    ]] .. ns._eabPageUnparkSnippet .. [[
            self:Show(true)
        else
            if not hidden then
                self:SetAttribute("statehidden", true)
                changed = true
            end
            self:Hide(true)
        end

        if not changed then
            local token = self:GetAttribute("eab-pagesync-token") or 0
            self:SetAttribute("eab-pagesync-token", token == 0 and 1 or 0)
        end
    ]])

    btn:SetAttributeNoHandler("_eabPageSyncInstalled", true)
end
