if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Pushed.lua
--
--  Pushed and highlight textures, the border edge lines they draw, the
--  Match Bar Border copies and the pushed-state flash. Loads after the main
--  file and reads it through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local GetBindingKey = GetBindingKey
local EFD = ns.EFD

local EAB, barButtons = ns.EAB, ns.barButtons
local HIGHLIGHT_TEXTURES, ResolveBorderThickness = ns.HIGHLIGHT_TEXTURES, ns.ResolveBorderThickness
local I = ns._internals
local BAR_CONFIG, _quickKeybindState = I.BAR_CONFIG, I._quickKeybindState
local SetSquareTexture, _controllerButtons, allButtons = I.SetSquareTexture, I._controllerButtons, I.allButtons

-------------------------------------------------------------------------------
--  Pushed / Highlight Textures
--  These are global settings that apply to ALL action bar buttons.
-------------------------------------------------------------------------------
local PUSHED_TYPES = {
    [1] = "light",   -- Light overlay
    [2] = "medium",  -- Medium overlay
    [3] = "strong",  -- Strong overlay
    [4] = "solid",   -- Solid color fill
    [5] = "border",  -- Border only
    [6] = "none",    -- No pushed effect
}

do
local function _setupBorderEdges(btn, storeKey, driverTex)
    -- Edge state lives in EFD, never on the button table: StanceBar/PetBar
    -- flow through here with BLIZZARD-owned buttons (StanceButton/
    -- PetActionButton), which must never receive custom keys.
    local edges = EFD(btn)[storeKey]
    if not edges then
        edges = {}
        for j = 1, 4 do
            local t = btn:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(1, 1, 1, 1)
            t:Hide()
            edges[j] = t
        end
        EFD(btn)[storeKey] = edges
        if driverTex then
            hooksecurefunc(driverTex, "Show", function()
                if not edges._active then return end
                for j = 1, 4 do edges[j]:Show() end
            end)
            hooksecurefunc(driverTex, "Hide", function()
                for j = 1, 4 do edges[j]:Hide() end
            end)
        end
    end
    return edges
end

local function _applyBorderEdges(edges, btn, brdSize, cr, cg, cb)
    edges._active = true
    local anchor = btn.icon or btn.Icon or btn
    local PP = EllesmereUI.PP
    local fd = EFD(btn)
    local mask = fd.masqueOwned and (fd.masquePushedTextureMask or fd.masqueHighlightTextureMask)
    for j = 1, 4 do
        edges[j]:SetVertexColor(cr, cg, cb, 1)
        if edges._masqueMask ~= mask then
            if edges._masqueMask then edges[j]:RemoveMaskTexture(edges._masqueMask) end
            if mask then edges[j]:AddMaskTexture(mask) end
        end
    end
    edges._masqueMask = mask
    edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", anchor); edges[1]:SetPoint("TOPRIGHT", anchor)
    if PP then PP.Height(edges[1], brdSize) else edges[1]:SetHeight(brdSize) end
    edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", anchor); edges[2]:SetPoint("BOTTOMRIGHT", anchor)
    if PP then PP.Height(edges[2], brdSize) else edges[2]:SetHeight(brdSize) end
    edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT"); edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
    if PP then PP.Width(edges[3], brdSize) else edges[3]:SetWidth(brdSize) end
    edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
    if PP then PP.Width(edges[4], brdSize) else edges[4]:SetWidth(brdSize) end
end

local function _hideBorderEdges(btn, storeKey)
    local edges = EFD(btn)[storeKey]
    if not edges then return end
    edges._active = false
    for j = 1, 4 do edges[j]:Hide() end
end
ns._setupBorderEdges = _setupBorderEdges
ns._applyBorderEdges = _applyBorderEdges
ns._hideBorderEdges  = _hideBorderEdges
end

-------------------------------------------------------------------------------
--  Match Bar Border (the Pushed / Highlight Border Settings cogs and the Spell
--  Cast Highlight cog). On bars with a textured Border Style, a press, a hover
--  or the active spell lights up a tinted copy of the button's own border in
--  place of the flat edge lines (pushed / hover) or the checked fill (cast).
--  One copy per button, built the first time a role arms it on an eligible
--  bar, never for players who leave the options off: EFD(btn).ixBorder is a
--  wrapper frame and the only Show/Hide target, EFD(btn).ixHost inside it
--  carries the backdrop and stays shown, so neither a restyle nor the UI-scale
--  re-apply (EllesmereUI.ReapplyPxBorders) can flash or drop the copy. Roles
--  (EFD ixPush / ixHover / ixCast) are armed by the three Apply*Textures
--  passes; the live states (ixPressed / ixOver / ixChecked) come from hooks
--  whose bodies return at once unless their role is armed. ONE painter picks
--  pressed > spell cast > hover. While the copy shows, the bar border hides
--  through its own backdrop's alpha (our frame), never Hide(); the button's
--  own alpha is never read or written. All on ns: the main file and the
--  glow file reach them there.
-------------------------------------------------------------------------------

-- Tint slots (r, g, b, a), refilled in place by the pushed and highlight passes
-- while their role is on, so a paint allocates nothing.
ns._ixPushC = { 1, 1, 1, 1 }
ns._ixHlC   = { 1, 1, 1, 1 }
-- [barKey] = the bar's last computed eligibility (GetCheckedAlpha reads it).
ns._ixElig  = {}

-- Which roles are on, from the profile alone: each needs its own opt-in plus
-- the setting it restyles (Border pushed / highlight type, cast highlight on).
ns._ixRolesOn = function(p)
    return (p.pushedBorderMatchBar and (p.pushedTextureType or 2) == 5) or false,
        (p.highlightBorderMatchBar and (p.highlightTextureType or 2) == 5) or false,
        (p.castHighlightBorder and p.showCastHighlight ~= false) or false
end

-- Bar eligibility: EllesmereUI style, square icons, a None or Cropped shape, a
-- textured Border Style that resolves to a file, Border Size above 0. Returns
-- it and whether it differs from the stored value (stored here).
ns._ixBarEligible = function(barKey)
    local p = EAB.db.profile
    local s = p.bars[barKey]
    local ok = false
    if s and not ns.MasqueOwnsBar(barKey) and p.squareIcons and ns.AB_Style() == "eui" then
        local shape = s.buttonShape or "none"
        local tex = s.borderTexture or "solid"
        if (shape == "none" or shape == "cropped") and tex ~= "" and tex ~= "solid"
           and EllesmereUI.ResolveBorderTexture(tex) then
            ok = ResolveBorderThickness(s) > 0
        end
    end
    local changed = ns._ixElig[barKey] ~= ok
    ns._ixElig[barKey] = ok
    return ok, changed
end

-- Styles the copy exactly like the bar border: texture, step, exact size,
-- offsets, shifts, and the bar border's frame level (Show Behind / Border
-- Above Effects; ApplyBorderStyle resets the backdrop to the host's level, so
-- it is set again after). Keeps the current tint. Unmemoized, like the bar
-- border's own textured path. Callers keep it out of combat.
ns._ixStyle = function(btn, fd, s)
    local host = fd.ixHost
    local sz, px = ResolveBorderThickness(s)
    EllesmereUI.ApplyBorderStyle(host, sz, fd.ixR or 1, fd.ixG or 1, fd.ixB or 1, fd.ixA or 1,
        s.borderTexture, s.borderTextureOffset, s.borderTextureOffsetY,
        s.borderTextureShiftX, s.borderTextureShiftY, "actionbars",
        s.borderThickness or "thin", nil, px)
    local bd = EllesmereUI._bdBorderData[host]
    if bd then bd:SetFrameLevel(ns._eabBorderLevel(btn, s.borderBehind, s.borderAboveEffects)) end
    fd.ixStyled = true
end

-- The one painter: pressed > spell cast > hover (cast and hover share the
-- highlight tint). Recolours only on a real change, shows and hides only on an
-- edge. Runs from hooks in and out of combat: our own frames only.
ns._ixPaint = function(btn, fd)
    local w = fd.ixBorder
    if not w then return end
    local bdData = EllesmereUI._bdBorderData
    local bd = bdData[fd.ixHost]
    local c
    if bd then
        if fd.ixPressed and fd.ixPush then
            c = ns._ixPushC
        elseif (fd.ixChecked and fd.ixCast) or (fd.ixOver and fd.ixHover) then
            c = ns._ixHlC
        end
    end
    if c then
        local r, g, b, a = c[1], c[2], c[3], c[4]
        if fd.ixR ~= r or fd.ixG ~= g or fd.ixB ~= b or fd.ixA ~= a then
            fd.ixR, fd.ixG, fd.ixB, fd.ixA = r, g, b, a
            bd:SetBackdropBorderColor(r, g, b, a)
        end
        if not fd.ixLit then
            fd.ixLit = true
            local base = bdData[btn]
            if base then
                fd.ixBaseA = base:GetAlpha()
                base:SetAlpha(0)
            end
            w:Show()
        end
    elseif fd.ixLit then
        fd.ixLit = nil
        w:Hide()
        local base = bdData[btn]
        if base then base:SetAlpha(fd.ixBaseA or 1) end
    end
end

-- Pressed-state drivers, one shared function each. Bodies return unless the
-- pushed role is armed (or, to release, a press is recorded).
ns._ixPressOn = function(btn)
    local fd = ns._eabFD[btn]
    if fd and fd.ixPush and not fd.ixPressed then
        fd.ixPressed = true
        ns._ixPaint(btn, fd)
    end
end
ns._ixPressOff = function(btn)
    local fd = ns._eabFD[btn]
    if fd and fd.ixPressed then
        fd.ixPressed = nil
        ns._ixPaint(btn, fd)
    end
end

-- Installed once per button, the first time the pushed role arms it. The
-- keybind flash path shows and hides PushedTexture from Lua; a mouse press is
-- drawn by the engine with no Lua call, so the button's own mouse scripts
-- drive that half, and OnHide drops a press a hidden bar would strand. A drag
-- off the button may never deliver OnMouseUp, so OnDragStart drops it too, on
-- our own action buttons only (the Stance and Pet bars reuse Blizzard's).
ns._ixHookPress = function(btn, fd)
    fd.ixPressHooked = true
    local pt = btn.PushedTexture
    if pt then
        hooksecurefunc(pt, "Show", function() ns._ixPressOn(btn) end)
        hooksecurefunc(pt, "Hide", function() ns._ixPressOff(btn) end)
    end
    btn:HookScript("OnMouseDown", ns._ixPressOn)
    btn:HookScript("OnMouseUp", ns._ixPressOff)
    btn:HookScript("OnHide", ns._ixPressOff)
    if _controllerButtons[btn] then btn:HookScript("OnDragStart", ns._ixPressOff) end
end

-- Reads the checked state and paints only when it really changed. A secret
-- value is skipped without a retry; the next SetChecked samples again.
ns._ixSampleChecked = function(btn, fd)
    local c = btn:GetChecked()
    if issecretvalue and issecretvalue(c) then return end
    c = c and true or nil
    if fd.ixChecked ~= c then
        fd.ixChecked = c
        ns._ixPaint(btn, fd)
    end
end

-- Installed once per button, the first time the cast role arms it. Blizzard's
-- UpdateState and our own dispatcher both set the checked state through
-- SetChecked. The hooked argument is never read (it can be secret).
ns._ixHookChecked = function(btn, fd)
    fd.ixCheckHooked = true
    hooksecurefunc(btn, "SetChecked", function()
        local d = ns._eabFD[btn]
        if d and d.ixCast then ns._ixSampleChecked(btn, d) end
    end)
end

-- Arms (on) or disarms one role ("ixPush" / "ixHover" / "ixCast") on one
-- button; returns whether it is armed. The first arm builds and styles the
-- copy and installs the role's driver, out of combat only: a combat arm defers
-- to the regen ApplyAll and returns false, so the caller keeps its own look.
-- Dropping the last role hides the copy, restores the bar border's alpha and
-- takes the host out of the px re-apply registry (HideBorderStyle).
ns._ixRole = function(btn, s, role, on)
    local fd = EFD(btn)
    if on then
        local needHook = (role == "ixPush" and not fd.ixPressHooked)
            or (role == "ixCast" and not fd.ixCheckHooked)
        if not fd.ixStyled or needHook then
            if InCombatLockdown() then
                ns._eabApplyDeferred = true
                return false
            end
            if not fd.ixBorder then
                local w = CreateFrame("Frame", nil, btn)
                w:SetAllPoints(btn)
                w:Hide()
                local host = CreateFrame("Frame", nil, w)
                host:SetAllPoints(w)
                fd.ixBorder, fd.ixHost = w, host
                ns._ixEver = true
            end
            if not fd.ixStyled then ns._ixStyle(btn, fd, s) end
            if role == "ixPush" and not fd.ixPressHooked then ns._ixHookPress(btn, fd) end
            if role == "ixCast" and not fd.ixCheckHooked then ns._ixHookChecked(btn, fd) end
        end
        fd[role] = true
        -- A (re)armed cast role starts from the button's real state.
        if role == "ixCast" then ns._ixSampleChecked(btn, fd) end
        ns._ixPaint(btn, fd)
        return true
    elseif fd[role] then
        fd[role] = nil
        if role == "ixPush" then
            fd.ixPressed = nil
        elseif role == "ixHover" then
            fd.ixOver = nil
        else
            fd.ixChecked = nil
        end
        ns._ixPaint(btn, fd)
        if fd.ixStyled and not (fd.ixPush or fd.ixHover or fd.ixCast) then
            EllesmereUI.HideBorderStyle(fd.ixHost)
            fd.ixStyled = nil
        end
    end
    return false
end

-- Use separate hover and press textures so Masque won't overwrite them on reskin.
-- HIGHLIGHT handles hover and locked highlights; the press texture follows
-- mouse clicks and EUI's keyboard flash.
function ns.MasqueInteractionTexture(btn, role)
    local fd = EFD(btn)
    local native = btn[role]
    local key = "masque" .. role
    local tex = fd[key]
    if not tex then
        tex = btn:CreateTexture(nil, role == "HighlightTexture" and "HIGHLIGHT" or "OVERLAY", nil, 7)
        tex:SetBlendMode("ADD")
        fd[key] = tex
        if role == "PushedTexture" then
            tex:Hide()
            hooksecurefunc(native, "Show", function() tex:Show() end)
            hooksecurefunc(native, "Hide", function() tex:Hide() end)
            btn:HookScript("OnMouseDown", function() tex:Show() end)
            btn:HookScript("OnMouseUp", function() tex:Hide() end)
            btn:HookScript("OnHide", function() tex:Hide() end)
        end
        hooksecurefunc(native, "SetAlpha", function(self, alpha)
            if alpha ~= 0 then self:SetAlpha(0) end
        end)
    end
    native:SetAlpha(0)
    local cfg = btn._MSQ_CFG
    local mask = cfg and cfg.ButtonMask
    local icon = btn.icon or btn.Icon
    if not mask and icon and icon.GetMaskTexture then
        local ok, iconMask = pcall(icon.GetMaskTexture, icon, 1)
        if ok then mask = iconMask end
    end
    if fd[key .. "Mask"] ~= mask then
        if fd[key .. "Mask"] then tex:RemoveMaskTexture(fd[key .. "Mask"]) end
        if mask then tex:AddMaskTexture(mask) end
        fd[key .. "Mask"] = mask
    end
    return tex
end

function ns.AnchorMasqueInteraction(btn, tex)
    tex:ClearAllPoints()
    tex:SetAllPoints(btn.icon or btn.Icon or btn)
end

function EAB:ApplyPushedTextures()
    local p = self.db.profile
    local abStyle = ns.AB_Style()
    local pType = p.pushedTextureType or 2
    local useCC = p.pushedUseClassColor
    local customC = p.pushedCustomColor or { r=0.973, g=0.839, b=0.604, a=1 }
    local brdSize = p.pushedBorderSize or 4

    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    -- Match Bar Border (pushed): eligible bars trade the flat edges for the
    -- button's own border copy, tinted with this colour and its alpha. Once a
    -- copy exists (ixEver), every path that does not arm the role disarms it.
    local ixOn = abStyle == "eui" and (ns._ixRolesOn(p))
    if ixOn then
        local t = ns._ixPushC
        t[1], t[2], t[3], t[4] = cr, cg, cb, customC.a or 1
    end
    local ixEver = ns._ixEver

    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            local s = p.bars[info.key]
            local ixBar = ixOn and ns._ixBarEligible(info.key)
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.PushedTexture then
                    local masque = ns.MasqueOwnsBar(info.key) and abStyle == "eui"
                    local pushed = masque and ns.MasqueInteractionTexture(btn, "PushedTexture") or btn.PushedTexture
                    if ns.MasqueOwnsBar(info.key) and abStyle ~= "eui" then
                        ns._hideBorderEdges(btn, "_pushedBorder")
                    elseif abStyle ~= "eui" then
                        if abStyle == "classic" then
                            -- Classic WoW UI: the vanilla depress art over the button.
                            pushed:SetAtlas(nil)
                            pushed:SetTexture(ns.AB_CLASSIC.pushed)
                            pushed:SetTexCoord(0, 1, 0, 1)
                        elseif info.isStance or info.isPetBar then
                            -- Blizzard's buttons: its own art pass re-atlases them.
                            pushed:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", true)
                        else
                            ns.AB_StockAtlas(btn.PushedTexture, "UI-HUD-ActionBar-IconFrame-Down", true)
                        end
                        pushed:SetDrawLayer("OVERLAY", 7)
                        pushed:ClearAllPoints()
                        pushed:SetAllPoints(btn)
                        pushed:SetVertexColor(1, 1, 1, 1)
                        pushed:SetAlpha(1)
                        ns._hideBorderEdges(btn, "_pushedBorder")
                    elseif pType == 6 then
                        pushed:SetAlpha(0)
                        ns._hideBorderEdges(btn, "_pushedBorder")
                    elseif pType == 5 then
                        pushed:SetAlpha(0)
                        if ixBar and ns._ixRole(btn, s, "ixPush", true) then
                            ns._hideBorderEdges(btn, "_pushedBorder")
                        else
                            local edges = ns._setupBorderEdges(btn, "_pushedBorder", pushed)
                            ns._applyBorderEdges(edges, btn, brdSize, cr, cg, cb)
                        end
                    else
                        pushed:SetAlpha(1)
                        ns._hideBorderEdges(btn, "_pushedBorder")
                        if pType <= 3 then
                            SetSquareTexture(pushed, HIGHLIGHT_TEXTURES[pType] or HIGHLIGHT_TEXTURES[2])
                            pushed:SetVertexColor(cr, cg, cb, 1)
                        elseif pType == 4 then
                            pushed:SetVertexColor(1, 1, 1, 1)
                            pushed:SetColorTexture(cr, cg, cb, 0.35)
                        end
                    end
                    if masque then ns.AnchorMasqueInteraction(btn, pushed) end
                    -- Stock styles, other pushed types, the option off and
                    -- bars that left eligibility all land here.
                    if ixEver and not ixBar then ns._ixRole(btn, s, "ixPush", false) end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Pushed-State Flash: SetOverrideBinding routes keybinds to native engine
--  commands (ACTIONBUTTON1 etc.) so the engine fires the action directly
--  without clicking our buttons, so they never enter PUSHED state from
--  keyboard. Fix: hook UseAction to show PushedTexture, global keyup watcher
--  to hide all active textures.
-------------------------------------------------------------------------------
do
    local _pushedHooked = false
    local _activePushed = {}  -- btn -> true
    local _activePushedN = 0
    local _btnKeys = {}       -- btn -> { k1, k2 } (reused, no alloc per press)
    local _pollFrame
    function EAB:HookPushedFlash()
        if _pushedHooked then return end
        _pushedHooked = true
        _pollFrame = ns.TakeShell()
        _pollFrame:SetScript("OnUpdate", function()
            if _activePushedN == 0 then
                _pollFrame:Hide()
                return
            end
            for btn in pairs(_activePushed) do
                local keys = _btnKeys[btn]
                local held = false
                if keys then
                    for i = 1, #keys do
                        if IsKeyDown(keys[i]) then held = true; break end
                    end
                end
                if not held then
                    if btn.PushedTexture then btn.PushedTexture:Hide() end
                    _activePushed[btn] = nil
                    _activePushedN = _activePushedN - 1
                end
            end
            if _activePushedN == 0 then _pollFrame:Hide() end
        end)
        _pollFrame:Hide()
        -- Extract the base key from a compound binding ("SHIFT-1" -> "1",
        -- "CTRL-Q" -> "Q"): IsKeyDown only accepts raw key names.
        local function BaseKey(binding)
            if not binding then return nil end
            -- The minus key's name is the literal "-", so "-" and modifier
            -- combos like "SHIFT--" END in "-": the trailing char IS the key,
            -- and the pattern below would find no non-hyphen run (nil).
            if binding:sub(-1) == "-" then return "-" end
            return binding:match("[^%-]+$")
        end
        local function ShowPushedForSlot(slot)
            local prof = EAB.db and EAB.db.profile
            if not prof then return end
            if ns.AB_Style() == "eui" and (prof.pushedTextureType or 2) == 6 then return end
            local btn = allButtons[slot]
            if not btn or not btn.PushedTexture then return end
            local cmd = btn.commandName
            if not cmd then return end
            local k1, k2 = GetBindingKey(cmd)
            if not k1 then return end
            local keys = _btnKeys[btn]
            if not keys then keys = {}; _btnKeys[btn] = keys end
            keys[1] = BaseKey(k1); keys[2] = BaseKey(k2); keys[3] = nil
            btn.PushedTexture:Show()
            if not _activePushed[btn] then
                _activePushed[btn] = true
                _activePushedN = _activePushedN + 1
            end
            _pollFrame:Show()
        end
        -- ActionButtonDown/MultiActionButtonDown fire on key press regardless
        -- of "cast on key down" CVar. This ensures pushed texture shows while
        -- the key is held for both key-down and key-up casting modes.
        hooksecurefunc("ActionButtonDown", function(id) ShowPushedForSlot(id) end)
        if MultiActionButtonDown then
            local multiBarPage = {
                MultiBarBottomLeft  = 6,
                MultiBarBottomRight = 5,
                MultiBarRight       = 3,
                MultiBarLeft        = 4,
                MultiBar5           = 13,
                MultiBar6           = 14,
                MultiBar7           = 15,
            }
            hooksecurefunc("MultiActionButtonDown", function(barName, id)
                local page = multiBarPage[barName]
                if not page then return end
                local slot = (page - 1) * 12 + id
                ShowPushedForSlot(slot)
            end)
        end
    end
end

function EAB:ApplyHighlightTextures()
    local p = self.db.profile
    local abStock = ns.AB_Style() ~= "eui"
    local hType = p.highlightTextureType or 2
    local useCC = p.highlightUseClassColor
    local customC = p.highlightCustomColor or { r=0.973, g=0.839, b=0.604, a=1 }
    local brdSize = p.highlightBorderSize or 4

    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    -- Match Bar Border (hover), plus the tint the spell-cast copy shares with
    -- it (this colour and its alpha). Once a copy exists (ixEver), every path
    -- that does not arm the hover role disarms it, and a lit cast copy picks
    -- up a colour change here. The tint is refreshed on every pass, options
    -- off included: the Spell Cast Highlight toggles arm the cast role through
    -- ApplyCheckedTextures alone, which paints with this slot as it stands.
    local _, ixOn, ixCast = ns._ixRolesOn(p)
    ixOn = ixOn and not abStock
    do
        local t = ns._ixHlC
        t[1], t[2], t[3], t[4] = cr, cg, cb, customC.a or 1
    end
    local ixEver = ns._ixEver

    for _, info in ipairs(BAR_CONFIG) do
        if abStock then
            -- skip -- the stock kit owns the highlight (classic paints its
            -- own in ns.AB_PaintClassicButton)
            local buttons = ixEver and barButtons[info.key]
            if buttons then
                for i = 1, #buttons do
                    local btn = buttons[i]
                    if btn then ns._ixRole(btn, nil, "ixHover", false) end
                end
            end
        else
        local buttons = barButtons[info.key]
        if buttons then
            local s = p.bars[info.key]
            local ixBar = ixOn and ns._ixBarEligible(info.key)
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.HighlightTexture then
                    local masque = ns.MasqueOwnsBar(info.key)
                    local highlight = masque and ns.MasqueInteractionTexture(btn, "HighlightTexture") or btn.HighlightTexture
                    if hType == 6 then
                        highlight:SetAlpha(0)
                        ns._hideBorderEdges(btn, "_highlightBorder")
                    elseif hType == 5 then
                        highlight:SetAlpha(0)
                        if ixBar and ns._ixRole(btn, s, "ixHover", true) then
                            ns._hideBorderEdges(btn, "_highlightBorder")
                        else
                            local edges = ns._setupBorderEdges(btn, "_highlightBorder")
                            ns._applyBorderEdges(edges, btn, brdSize, cr, cg, cb)
                        end
                        if not EFD(btn).hlBorderHooked then
                            EFD(btn).hlBorderHooked = true
                            -- Hover driver for both looks: the armed copy, else
                            -- today's edges.
                            btn:HookScript("OnEnter", function(self)
                                local fd = EFD(self)
                                if fd.ixHover then
                                    fd.ixOver = true
                                    ns._ixPaint(self, fd)
                                    return
                                end
                                local be = fd._highlightBorder
                                if be and be._active then for j = 1, 4 do be[j]:Show() end end
                            end)
                            btn:HookScript("OnLeave", function(self)
                                local fd = EFD(self)
                                if fd.ixOver then
                                    fd.ixOver = nil
                                    ns._ixPaint(self, fd)
                                end
                                local be = fd._highlightBorder
                                if be then for j = 1, 4 do be[j]:Hide() end end
                            end)
                        end
                    else
                        highlight:SetAlpha(1)
                        ns._hideBorderEdges(btn, "_highlightBorder")
                        if hType <= 3 then
                            SetSquareTexture(highlight, HIGHLIGHT_TEXTURES[hType] or HIGHLIGHT_TEXTURES[1])
                            highlight:SetVertexColor(cr, cg, cb, 1)
                        elseif hType == 4 then
                            highlight:SetVertexColor(1, 1, 1, 1)
                            highlight:SetColorTexture(cr, cg, cb, 0.35)
                        end
                    end
                    if masque then ns.AnchorMasqueInteraction(btn, highlight) end
                    if ixEver and not ixBar then ns._ixRole(btn, s, "ixHover", false) end
                end
                if ixCast and ixEver and btn then
                    local fd = ns._eabFD[btn]
                    if fd and fd.ixCast then ns._ixPaint(btn, fd) end
                end
                _quickKeybindState.art.RefreshButton(btn)
            end
        end
        end -- abStock
    end

    -- Blizzard-owned special buttons do not flow through the standard bar
    -- button setup, but QuickKeybind still resets their overlay atlas.
    -- Keep their QuickKeybind highlight aligned with the EUI button art too.
    _quickKeybindState.art.ForEachSpecialButton(_quickKeybindState.art.InitializeButton)
end

