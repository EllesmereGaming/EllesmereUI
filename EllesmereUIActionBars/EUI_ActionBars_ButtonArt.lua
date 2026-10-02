if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_ButtonArt.lua
--
--  Button appearance: stripping the stock art, the classic button art, the
--  button borders and the shape masks. Loads right after the main file, reads
--  it through ns only, and hands its entry points to the files after it
--  through ns._internals (bottom of this file).
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pcall = ipairs, pcall
local max = math.max
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local PP = EllesmereUI.PP
local EFD = ns.EFD

local EAB, EAB_VTABLE = ns.EAB, ns.EAB_VTABLE
local HIGHLIGHT_TEXTURES, ResolveBorderThickness, ButtonHasAction = ns.HIGHLIGHT_TEXTURES, ns.ResolveBorderThickness, ns.ButtonHasAction
local SHAPE_MASKS, SHAPE_BORDERS, SHAPE_INSETS = ns.SHAPE_MASKS, ns.SHAPE_BORDERS, ns.SHAPE_INSETS
local SHAPE_ZOOM_DEFAULTS, SHAPE_ICON_EXPAND, SHAPE_ICON_EXPAND_OFFSETS = ns.SHAPE_ZOOM_DEFAULTS, ns.SHAPE_ICON_EXPAND, ns.SHAPE_ICON_EXPAND_OFFSETS
local I = ns._internals
local SHAPE_EDGE_SCALES, _quickKeybindState, HideSlotArt = I.SHAPE_EDGE_SCALES, I._quickKeybindState, I.HideSlotArt

-------------------------------------------------------------------------------
--  Visual Customization Button Appearance
-------------------------------------------------------------------------------
local function HideSelfDeferred(self)
    -- Reuse a cached closure per frame to avoid allocation on every OnShow
    local fd = EFD(self)
    if not fd.hideFn then
        fd.hideFn = function()
            if self and not self:IsForbidden() then self:Hide() end
        end
    end
    C_Timer_After(0, fd.hideFn)
end

local function HideBorder(button)
    if button.NormalTexture then
        button.NormalTexture:Hide()
        button.NormalTexture:SetAlpha(0)
    end
    if button.Border then
        -- Show Equipped Border (Icon Effects) keeps Blizzard's equipped-item
        -- border, in our square art; its shown state stays with the updates.
        if EAB.db.profile.showEquippedBorder then
            ns.AB_EquippedBorderLook(button.Border)
        else
            button.Border:Hide()
            button.Border:SetAlpha(0)
        end
    end
    if button.icon and button.IconMask then
        button.icon:RemoveMaskTexture(button.IconMask)
        -- Neutralize IconMask: UpdateButtonArt re-applies it via
        -- icon:AddMaskTexture on combat transitions, page changes, etc.
        button.IconMask:Hide()
        button.IconMask:SetTexture(nil)
        button.IconMask:ClearAllPoints()
        button.IconMask:SetSize(0.001, 0.001)
    end
end

local function SetSquareTexture(texture, texPath)
    if not texture then return end
    texture:SetAtlas(nil)
    texture:SetTexture(texPath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:ClearAllPoints()
    texture:SetAllPoints(texture:GetParent())
end

-- Show Equipped Border (Icon Effects, profile.showEquippedBorder): Blizzard's
-- equipped-item border on a square button, in our square highlight art and
-- Blizzard's own green at half opacity. The art swap fires the Border's
-- SetAtlas hook (MakeButtonSquare) again, which `busy` turns away.
do
    local busy = false
    function ns.AB_EquippedBorderLook(bd)
        if busy then return end
        busy = true
        SetSquareTexture(bd, HIGHLIGHT_TEXTURES[1])
        busy = false
        bd:SetVertexColor(0, 1, 0, 0.5)
        bd:SetAlpha(1)
    end
end

-------------------------------------------------------------------------------
--  Classic WoW UI button art (ns.AB_Style() == "classic")
--  The vanilla 36-button ring on a button, scaled by the button's own size:
--  NormalTexture UI-Quickslot2 (66/36 of the button, CENTER 0,-1/36), or
--  UI-Quickslot on an empty slot; PushedTexture UI-Quickslot-Depress over the
--  button; HighlightTexture ButtonHilight-Square ADD; CheckedTexture
--  CheckButtonHilight ADD; equipped Border UI-ActionButton-Border ADD (62/36,
--  CENTER 0,1/36). Square icon with full art: the stock IconMask is
--  neutralised the way HideBorder does it, the stock slot background kept
--  transparent, the cooldown swipe spans the icon. Idempotent: a layout pass
--  re-runs it per native size (our buttons' UpdateButtonArt is a noop, so
--  nothing of Blizzard's repaints the ring behind it).
-------------------------------------------------------------------------------
ns.AB_CLASSIC = {
    slot     = "Interface\\Buttons\\UI-Quickslot2",
    empty    = "Interface\\Buttons\\UI-Quickslot",
    pushed   = "Interface\\Buttons\\UI-Quickslot-Depress",
    hilight  = "Interface\\Buttons\\ButtonHilight-Square",
    checked  = "Interface\\Buttons\\CheckButtonHilight",
    equipped = "Interface\\Buttons\\UI-ActionButton-Border",
}

-- Slot ring or empty-slot art on the NormalTexture. Memo per button: the
-- content edges (slot change, page flip) cost one comparison when unchanged.
function ns.AB_ClassicSlotRing(btn, filled)
    filled = filled and true or false
    local fd = EFD(btn)
    if fd.classicFilled == filled then return end
    fd.classicFilled = filled
    local nt = btn.NormalTexture
    if nt then
        nt:SetTexture(filled and ns.AB_CLASSIC.slot or ns.AB_CLASSIC.empty)
        nt:SetTexCoord(0, 1, 0, 1)
    end
end

-- Plain Blizzard Style on the Forever client: the border the template's
-- OnLoad left on our button's NormalTexture (IconFrame-AddRow, as our
-- buttons have no .bar; IconFrame on a bar-art button) is redrawn once from
-- its retail sheet, where the client's atlas would draw Forever art.
function ns.AB_StockNormal(btn)
    local fd = EFD(btn)
    if fd.stockNT then return end
    fd.stockNT = true
    if ns.AB_Forever() then return end
    local nt = btn.NormalTexture
    local a = nt and nt:GetAtlas()
    if not a then return end
    local l = strlower(a)
    if l == "ui-hud-actionbar-iconframe-addrow" or l == "ui-hud-actionbar-iconframe" then
        EllesmereUI.StockAtlas(nt, a)
    end
end

-- Paints the whole kit on `btn` for a `w` x `h` button (its own size when
-- omitted). Our bar buttons pass their native size; flyout buttons pass none.
function ns.AB_PaintClassicButton(btn, w, h)
    local fd = EFD(btn)
    local art = ns.AB_CLASSIC
    if not w then w, h = btn:GetSize() end
    if not w or w <= 0 then w = 45 end
    if not h or h <= 0 then h = w end
    local sw, sh = w / 36, h / 36
    local icon = btn.icon
    if icon then
        if btn.IconMask then
            icon:RemoveMaskTexture(btn.IconMask)
            btn.IconMask:Hide()
            btn.IconMask:SetTexture(nil)
            btn.IconMask:ClearAllPoints()
            btn.IconMask:SetSize(0.001, 0.001)
        end
        icon:SetTexCoord(0, 1, 0, 1)
    end
    -- The 12.1 rounded slot background stays transparent (the square ring
    -- below is the slot); alpha, so Blizzard's own art passes keep working.
    if btn.SlotBackground then btn.SlotBackground:SetAlpha(0) end
    if btn.cooldown then
        btn.cooldown:ClearAllPoints()
        btn.cooldown:SetAllPoints(btn)
    end
    -- Seeded from the same source the content edges use (the action
    -- attribute); buttons without one (flyout popups) ask the mixin.
    if fd.classicFilled == nil then
        local a = btn.GetAttribute and btn:GetAttribute("action")
        if a then
            fd.classicFilled = HasAction(a) and true or false
        else
            fd.classicFilled = ButtonHasAction(btn) and true or false
        end
    end
    local nt = btn.NormalTexture
    if nt then
        nt:SetAtlas(nil)
        nt:SetTexture(fd.classicFilled and art.slot or art.empty)
        nt:SetTexCoord(0, 1, 0, 1)
        nt:ClearAllPoints()
        nt:SetPoint("CENTER", btn, "CENTER", 0, -sh)
        nt:SetSize(66 * sw, 66 * sh)
    end
    local pt = btn.PushedTexture
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture(art.pushed)
        pt:SetTexCoord(0, 1, 0, 1)
        pt:SetDrawLayer("OVERLAY", 7)
        pt:ClearAllPoints()
        pt:SetAllPoints(btn)
        pt:SetVertexColor(1, 1, 1, 1)
        pt:SetAlpha(1)
    end
    local ht = btn.HighlightTexture
    if ht then
        ht:SetAtlas(nil)
        ht:SetTexture(art.hilight)
        ht:SetTexCoord(0, 1, 0, 1)
        ht:SetBlendMode("ADD")
        ht:ClearAllPoints()
        ht:SetAllPoints(btn)
    end
    local ct = btn.CheckedTexture
    if ct then
        ct:SetAtlas(nil)
        ct:SetTexture(art.checked)
        ct:SetTexCoord(0, 1, 0, 1)
        ct:SetBlendMode("ADD")
        ct:ClearAllPoints()
        ct:SetAllPoints(btn)
    end
    local bd = btn.Border
    if bd then
        bd:SetAtlas(nil)
        bd:SetTexture(art.equipped)
        bd:SetTexCoord(0, 1, 0, 1)
        bd:SetBlendMode("ADD")
        bd:ClearAllPoints()
        bd:SetPoint("CENTER", btn, "CENTER", 0, sh)
        bd:SetSize(62 * sw, 62 * sh)
    end
    fd.classicArt = true
end

_quickKeybindState.art.ApplyButtonHighlight = function(btn)
    local tex = btn and btn.QuickKeybindHighlightTexture
    if not tex then return end

    local p = EAB and EAB.db and EAB.db.profile
    local useCC = p and p.highlightUseClassColor
    local customC = (p and p.highlightCustomColor) or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                cr, cg, cb = cc.r, cc.g, cc.b
            end
        end
    end

    -- QuickKeybind manages hover/idle opacity itself. We only replace the
    -- Blizzard atlas with EUI's square highlight art and matching color.
    SetSquareTexture(tex, HIGHLIGHT_TEXTURES[1])
    tex:SetVertexColor(cr, cg, cb, 1)
end

_quickKeybindState.art.RefreshButton = function(btn, show)
    if not btn or btn:IsForbidden() then return end
    _quickKeybindState.art.ApplyButtonHighlight(btn)
    if show ~= nil then
        _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
    end
end

_quickKeybindState.art.InitializeButton = function(btn, show)
    _quickKeybindState.art.RefreshButton(btn, show)
    _quickKeybindState.art.HookButton(btn)
end

_quickKeybindState.art.HookButton = function(btn)
    if not btn or btn:IsForbidden() or EFD(btn).quickKeybindArtHooked then return end
    if btn.QuickKeybindHighlightTexture and btn.DoModeChange then
        hooksecurefunc(btn, "DoModeChange", function(self, isInQuickbindMode)
            _quickKeybindState.art.RefreshButton(self, isInQuickbindMode)
        end)
        EFD(btn).quickKeybindArtHooked = true
    end
end

_quickKeybindState.art.ApplyButtonHighlightAlpha = function(btn, show)
    local tex = btn and btn.QuickKeybindHighlightTexture
    if not tex then return end

    if show then
        local idleAlpha = 0.5
        if btn.IsMouseOver and btn:IsMouseOver() then
            tex:SetAlpha(1)
        else
            tex:SetAlpha(idleAlpha)
        end
    else
        tex:SetAlpha(1)
    end
end

_quickKeybindState.art.ForEachSpecialButton = function(fn)
    if not fn then return end
    if ExtraActionButton1 then
        fn(ExtraActionButton1)
    end
end

_quickKeybindState.ReassertButtonsAfterCombatChange = function()
    if not _quickKeybindState.open then return end
    C_Timer_After(0, function()
        if _quickKeybindState.open and ns.EAB_UpdateQuickKeybindButtons then
            ns.EAB_UpdateQuickKeybindButtons(true)
        end
    end)
end

local function HideTexture(texture)
    if not texture then return end
    texture:SetAlpha(0)
end

function EAB_VTABLE.HideRegionDeferred(region, resetAlpha)
    if not region then return end
    local fd = EFD(region)
    if not fd.hideFn then
        fd.hideFn = function()
            if region and not region:IsForbidden() then
                region:Hide()
                if resetAlpha then
                    region:SetAlpha(resetAlpha)
                end
            end
        end
    end
    C_Timer_After(0, fd.hideFn)
end

local function MakeButtonSquare(btn)
    if EFD(btn).squared then return end
    -- Always hide SlotBackground regardless of style (our own icon
    -- background toggle controls slot backgrounds for all bars).
    HideSlotArt(btn)
    -- Skip the rest of Blizzard texture stripping for the stock styles
    local _p = EAB.db and EAB.db.profile
    if ns.AB_Style() ~= "eui" then return end
    HideBorder(btn)
    -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system.
    -- ActionBarButtonTemplate may not always inherit this from FlyoutButtonMixin.
    if not btn.GetPopupDirection then
        btn.GetPopupDirection = function(self)
            return self:GetAttribute("flyoutDirection") or "UP"
        end
    end
    local fd = EFD(btn)
    if btn.NormalTexture and not fd.ntHooked then
        btn.NormalTexture:HookScript("OnShow", HideSelfDeferred)
        fd.ntHooked = true
    end
    if not fd.showHooked then
        -- Cache the deferred closure per button to avoid allocation on every OnShow
        local hideBorderFn = function()
            if btn and not btn:IsForbidden() then HideBorder(btn) end
        end
        btn:HookScript("OnShow", function() C_Timer_After(0, hideBorderFn) end)
        fd.showHooked = true
    end
    -- Re-neutralize IconMask after Blizzard re-adds it (combat transitions,
    -- page changes, bonus bar swaps). Deferred via C_Timer to avoid tainting
    -- Blizzard's secure call chains.
    if not fd.artHooked and btn.UpdateButtonArt then
        hooksecurefunc(btn, "UpdateButtonArt", function(self)
            local sfd = EFD(self)
            -- Coalesce: UpdateAction storms (mouseover-conditional macros) call
            -- this many times per frame; one deferred HideBorder covers them all.
            if sfd.artPending then return end
            sfd.artPending = true
            if not sfd.artFn then
                sfd.artFn = function()
                    sfd.artPending = nil
                    if self and not self:IsForbidden() then
                        HideBorder(self)
                    end
                end
            end
            C_Timer_After(0, sfd.artFn)
        end)
        fd.artHooked = true
    end
    -- Hook UpdateAssistedCombatRotationFrame to scale the rotation frame
    -- when Blizzard creates it lazily (default 45x45, needs our button size).
    if not fd.rotHooked and btn.UpdateAssistedCombatRotationFrame then
        hooksecurefunc(btn, "UpdateAssistedCombatRotationFrame", function(self)
            -- Fires at Blizzard's combat cadence while a rotation action is on
            -- a bar: change-guard so steady-state fires cost only the reads.
            local rtf = self.AssistedCombatRotationFrame
            if rtf and EFD(self).squared then
                local s = (self:GetWidth() or 45) / 45
                if rtf:GetScale() ~= s then rtf:SetScale(s) end
            end
            -- Blizzard's swirl frame stays permanently hidden (its Lua OnUpdate polls
            -- every render frame while shown); our script-free spinner clone replaces
            -- it. UpdateState (the caller we hook behind) re-Shows it every call and
            -- this hook runs right after, synchronously, so it never renders.
            if rtf then
                if rtf:IsShown() then rtf:Hide() end
                local spin = ns.EnsureAssistSpinner(self, rtf)
                local p2 = EAB.db and EAB.db.profile
                local enabled = not p2 or p2.obaIconEnabled ~= false
                local action = self.GetAttribute and self:GetAttribute("action") or self.action
                local isAssist = action and C_ActionBar and C_ActionBar.IsAssistedCombatAction
                    and C_ActionBar.IsAssistedCombatAction(action) or false
                spin:SetShown(enabled and isAssist)
                -- Suggested-spell icon updates ride the assist ticker, armed
                -- here on the only signal that identifies an assist button (see
                -- ns._ArmAssistTicker for cost discipline). When the assist
                -- action leaves, stop the ticker if no assist button remains.
                if isAssist then
                    if ns._ArmAssistTicker then ns._ArmAssistTicker() end
                elseif ns._assistTicker and ns._assistTicker.IsPlaying() then
                    if ns.RepaintAssistIcons() == 0 then ns._assistTicker.Stop() end
                end
            end
        end)
        fd.rotHooked = true
    end
    SetSquareTexture(btn.HighlightTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.NewActionTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.PushedTexture, HIGHLIGHT_TEXTURES[2])
    SetSquareTexture(btn.Flash, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.CheckedTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.Border, HIGHLIGHT_TEXTURES[1])
    _quickKeybindState.art.InitializeButton(btn)
    HideTexture(btn.FlyoutBorderShadow)
    if btn.BorderShadow then
        if EllesmereUI and EllesmereUI._hiddenParent then
            btn.BorderShadow:SetParent(EllesmereUI._hiddenParent)
        else
            HideTexture(btn.BorderShadow)
        end
    end
    if btn.cooldown then
        btn.cooldown:ClearAllPoints()
        btn.cooldown:SetAllPoints(btn)
    end
    -- Cast-anim suppression (SpellCastAnimFrame + InterruptDisplay): Hide the ANIMATED
    -- frame synchronously -- its animation group re-drives alpha on the next render
    -- tick, so SetAlpha(0) plus a deferred Hide leaks a one-frame blink of the cast
    -- sweep, while a hidden frame renders no animations. The deferred Hide stays as a
    -- fallback reset. Insecure UNIT_SPELLCAST/OnShow context, IsForbidden-guarded.
    if (btn.SpellCastAnimFrame and not fd.castHooked)
       or (btn.InterruptDisplay and not fd.intHooked) then
        local hideCastAnim = function(self)
            local prof = EAB.db and EAB.db.profile
            if not prof then return end
            local bfd = EFD(btn)
            if not prof.hideCastingAnimations and not bfd.shapeApplied and not bfd.cropped then return end
            self:SetAlpha(0)
            if not self:IsForbidden() then self:Hide() end
            EAB_VTABLE.HideRegionDeferred(self, 1)
        end
        if btn.SpellCastAnimFrame and not fd.castHooked then
            btn.SpellCastAnimFrame:HookScript("OnShow", hideCastAnim)
            fd.castHooked = true
        end
        if btn.InterruptDisplay and not fd.intHooked then
            btn.InterruptDisplay:HookScript("OnShow", hideCastAnim)
            fd.intHooked = true
        end
    end
    -- The cast-on-button anim's OnHide resets the swipe to opaque black on the
    -- button that hard-cast, clobbering the CD Swipe color/opacity setting there
    -- (cast-time spells only; instants never play the anim, and the suppression
    -- hook above trips the same OnHide at cast START). HookScript runs after the
    -- reset, so re-assert ours on the same edge -- fires only when a cast anim
    -- frame hides, nothing at idle.
    if btn.SpellCastAnimFrame and not fd.castSwipeHooked then
        fd.castSwipeHooked = true
        btn.SpellCastAnimFrame:HookScript("OnHide", function()
            local pdb = EAB.db and EAB.db.profile
            local cd = btn.cooldown
            if not pdb or not (cd and cd.SetSwipeColor) then return end
            local c = pdb.cdSwipeColor or { r = 0, g = 0, b = 0 }
            pcall(cd.SetSwipeColor, cd, c.r or 0, c.g or 0, c.b or 0, (pdb.cdSwipeAlpha or 80) / 100)
        end)
    end
    if btn.SlotBackground then
        btn.SlotBackground:SetAlpha(0)
        if not fd.slotBgHooked then
            fd.slotBgHooked = true
            hooksecurefunc(btn.SlotBackground, "SetAlpha", function(self, a)
                if (issecretvalue and issecretvalue(a)) or a ~= 0 then self:SetAlpha(0) end
            end)
        end
    end
    if not fd.slotBG then
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetAllPoints(btn)
        local sc = (_p and _p.slotBgColor) or { r = 0.15, g = 0.15, b = 0.15 }
        local so = _p and _p.slotBgOpacity
        if so == nil then so = 50 end
        bg:SetColorTexture(sc.r or 0.15, sc.g or 0.15, sc.b or 0.15, so / 100)
        fd.slotBG = bg
    end
    if btn.SlotArt then
        btn.SlotArt:SetAlpha(0)
        if not fd.slotArtHooked then
            fd.slotArtHooked = true
            hooksecurefunc(btn.SlotArt, "SetAlpha", function(self, a)
                if (issecretvalue and issecretvalue(a)) or a ~= 0 then self:SetAlpha(0) end
            end)
        end
    end
    -- Blizzard's equipped-item Border: it calls Border:SetAtlas()/Show() on
    -- refreshes and EAB owns the visible border, so it is suppressed, unless
    -- Show Equipped Border keeps it (in our square art).
    if btn.Border and not fd.borderHooked then
        local function BorderRefresh(self)
            if EAB.db.profile.showEquippedBorder then
                ns.AB_EquippedBorderLook(self)
            else
                self:SetAlpha(0)
                EAB_VTABLE.HideRegionDeferred(self)
            end
        end
        hooksecurefunc(btn.Border, "SetAtlas", BorderRefresh)
        hooksecurefunc(btn.Border, "Show", BorderRefresh)
        fd.borderHooked = true
    end
    fd.squared = true
end

local function EnsureBorders(btn)
    local fd = EFD(btn)
    if fd.borders then return fd.borders end
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 2)
        fd.borders = PP.GetBorders(btn)
        -- Reparent the flyout arrow INTO the border frame and lift it above the
        -- strips (OVERLAY sublevel 2, from PP.CreateBorder above): sharing the
        -- frame is not enough, without a higher sublevel the arrow draws under.
        if btn.Arrow then
            btn.Arrow:SetParent(fd.borders)
            if btn.Arrow.SetDrawLayer then
                btn.Arrow:SetDrawLayer("OVERLAY", 7)
            elseif btn.Arrow.SetFrameLevel then
                btn.Arrow:SetFrameLevel(fd.borders:GetFrameLevel() + 1)
            end
        end
    end
    return fd.borders
end

-- Frame level of a button's textured border backdrop (the bar border and its
-- Match Bar Border copy). "Show Behind": level-1 draws behind the icon.
-- "Border Above Effects": +20 clears the proc glow wrapper (+10), the assist
-- overlay (+14) and ring (+15), the cooldown swipe and the item-rank diamond
-- (+18). Otherwise the button's own level, in front of the icon. Show Behind
-- wins. On ns: EUI_ActionBars_Pushed.lua calls it too.
ns._eabBorderLevel = function(btn, behind, above)
    local lvl = btn:GetFrameLevel()
    if behind then return max(0, lvl - 1) end
    if above then return lvl + 20 end
    return lvl
end

-- edgePx: the bar's exact size from ResolveBorderThickness (nil = legacy path).
-- above: the bar's "Border Above Effects" (textured borders only).
local function ApplyButtonBorders(btn, on, cr, cg, cb, ca, sz, zoom, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, behind, edgePx, above)
    MakeButtonSquare(btn)
    local PP = EllesmereUI and EllesmereUI.PP
    local fd = EFD(btn)
    if not on then
        if fd.borders then
            PP.HideBorder(btn)
        end
        -- Also hide textured border if present
        if EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[btn]
            if bdFrame then bdFrame:Hide() end
        end
        fd.borderKey = nil
    else
        local texKey = textureKey or "solid"
        if texKey ~= "solid" then
            -- Textured borders: always apply (cheap SetBackdropBorderColor call)
            fd.borderKey = nil
        else
            -- Solid borders: cache to avoid redundant PP updates (the exact size is
            -- a memo input of its own: a number or nil, compared as is)
            local es = btn:GetEffectiveScale()
            local stateKey = cr * 1000000 + cg * 10000 + cb * 100 + ca + sz * 0.001 + zoom * 10000000 + es * 0.0001
            if fd.borderKey == stateKey and fd.borderTexKey == texKey and fd.borderPxKey == edgePx then return end
            fd.borderKey = stateKey
        end
        fd.borderTexKey = texKey
        fd.borderPxKey = edgePx
        if texKey == "solid" then
            EnsureBorders(btn)
        elseif fd.borders then
            -- Switching from solid to textured: hide existing PP borders
            PP.HideBorder(btn)
            local ppC = PP.GetBorders(btn)
            if ppC then
                if ppC._top then ppC._top:SetAlpha(0) end
                if ppC._bottom then ppC._bottom:SetAlpha(0) end
                if ppC._left then ppC._left:SetAlpha(0) end
                if ppC._right then ppC._right:SetAlpha(0) end
            end
        end
        EllesmereUI.ApplyBorderStyle(btn, sz, cr, cg, cb, ca, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, nil, edgePx)
        -- "Show Behind": textured border frame is a child of btn; equal level draws
        -- in front of the icon, level-1 draws behind it. "Border Above Effects"
        -- raises it over the effects; turning it off lands back on the rule
        -- above on the next apply. Solid borders unaffected.
        if texKey ~= "solid" and EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[btn]
            if bdFrame then
                bdFrame:SetFrameLevel(ns._eabBorderLevel(btn, behind, above))
            end
        end
        if fd.borders and fd.shapeMask and fd.shapeMask:IsShown() then
            PP.HideBorder(btn)
            if EllesmereUI._bdBorderData then
                local bdFrame = EllesmereUI._bdBorderData[btn]
                if bdFrame then bdFrame:Hide() end
            end
        end
    end
    if zoom > 0 then
        local icon = btn.icon or btn.Icon
        if icon and icon.SetTexCoord and not (fd.shapeMask and fd.shapeMask:IsShown()) and not fd.cropped then
            icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
end

-------------------------------------------------------------------------------
--  Shape Masking
-------------------------------------------------------------------------------
local function MaskFrameTextures(frame, mask)
    if not frame or not mask then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region.AddMaskTexture then
            pcall(region.AddMaskTexture, region, mask)
        end
    end
end

local function UnmaskFrameTextures(frame, mask)
    if not frame or not mask then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region.RemoveMaskTexture then
            pcall(region.RemoveMaskTexture, region, mask)
        end
    end
end

local function ApplyShapeToButton(btn, shape, brdOn, brdR, brdG, brdB, brdA, brdSize, zoom)
    _quickKeybindState.art.RefreshButton(btn)
    local fd = EFD(btn)

    if shape == "none" or shape == "cropped" then
        -- Remove shape mask if previously applied
        if fd.shapeMask then
            local mask = fd.shapeMask
            local icon = btn.icon or btn.Icon
            if icon then pcall(icon.RemoveMaskTexture, icon, mask) end
            -- Unmask slot BG and icon BG from main mask
            if fd.slotBG then pcall(fd.slotBG.RemoveMaskTexture, fd.slotBG, mask) end
            if fd.iconBg then pcall(fd.iconBg.RemoveMaskTexture, fd.iconBg, mask) end
            -- Unmask cooldown frames and restore default swipe
            if btn.cooldown and not btn.cooldown:IsForbidden() then
                pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
                pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, "")
            end
            if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
                pcall(btn.chargeCooldown.RemoveMaskTexture, btn.chargeCooldown, mask)
                pcall(btn.chargeCooldown.SetSwipeTexture, btn.chargeCooldown, "")
            end
            -- Neutralize the mask so a stale reference cannot clip anything
            mask:SetTexture(nil)
            mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001)
            mask:Hide()
        end
        -- Remove overlay mask if it existed
        if fd.overlayMask then
            local omask = fd.overlayMask
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, omask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, omask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, omask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, omask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, omask) end
            if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, omask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, omask) end
            local nt = btn.NormalTexture or btn:GetNormalTexture()
            if nt then pcall(nt.RemoveMaskTexture, nt, omask) end
            if btn.SpellActivationAlert then
                UnmaskFrameTextures(btn.SpellActivationAlert, omask)
                EFD(btn.SpellActivationAlert).shapeMasked = nil
            end
            omask:SetTexture(nil)
            omask:ClearAllPoints()
            omask:SetSize(0.001, 0.001)
            omask:Hide()
        elseif fd.shapeMask then
            -- Overlays were on the main mask (no border case) clean them off
            local mask = fd.shapeMask
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, mask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, mask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, mask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, mask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, mask) end
            if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, mask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, mask) end
            local nt = btn.NormalTexture or btn:GetNormalTexture()
            if nt then pcall(nt.RemoveMaskTexture, nt, mask) end
            if btn.SpellActivationAlert then
                UnmaskFrameTextures(btn.SpellActivationAlert, mask)
                EFD(btn.SpellActivationAlert).shapeMasked = nil
            end
        end
        -- Clean up glow wrapper mask
        if fd.glowWrapper then
            local mask = fd.shapeMask
            if mask then UnmaskFrameTextures(fd.glowWrapper, mask) end
            local wfd = EFD(fd.glowWrapper)
            if wfd.ownMask then
                UnmaskFrameTextures(fd.glowWrapper, wfd.ownMask)
                wfd.ownMask:Hide()
            end
        end
        if fd.shapeBorder then
            fd.shapeBorder:Hide()
            EFD(fd.shapeBorder).wantsShow = false
            fd.shapeBorder:SetTexture(nil)
        end
        -- Clear shape tracking flags
        fd.shapeApplied = nil
        fd.shapeName = nil
        fd.shapeMaskPath = nil
        -- Restore cooldown edge to default (non-circular, not forced on)
        if btn.cooldown and not btn.cooldown:IsForbidden() then
            if btn.cooldown.SetUseCircularEdge then pcall(btn.cooldown.SetUseCircularEdge, btn.cooldown, false) end
        end
        if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
            if btn.chargeCooldown.SetUseCircularEdge then pcall(btn.chargeCooldown.SetUseCircularEdge, btn.chargeCooldown, false) end
        end
        -- Restore icon
        local icon = btn.icon or btn.Icon
        if icon then
            icon:ClearAllPoints()
            icon:SetSize(0, 0)
            icon:SetAllPoints(btn)
            if shape == "cropped" then
                local z = (zoom or 0)
                icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                fd.cropped = true
            else
                fd.cropped = false
                if zoom and zoom > 0 then
                    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                else
                    icon:SetTexCoord(0, 1, 0, 1)
                end
            end
        end
        -- Show square borders only if border is enabled
        if fd.borders and brdOn then
            -- Re-apply border style to restore correct type (PP or textured)
            local barKey = fd.barKey
            local texKey = barKey and EAB.db and EAB.db.profile.bars[barKey] and EAB.db.profile.bars[barKey].borderTexture or "solid"
            if texKey ~= "solid" then
                local s = EAB.db.profile.bars[barKey]
                local c = s and s.borderColor or { r=0, g=0, b=0, a=1 }
                local sz, px = ResolveBorderThickness(s)
                local thKey = s.borderThickness or "thin"
                EllesmereUI.ApplyBorderStyle(btn, sz, c.r, c.g, c.b, c.a or 1, texKey, s.borderTextureOffset, s.borderTextureOffsetY, s.borderTextureShiftX, s.borderTextureShiftY, "actionbars", thKey, nil, px)
                if EllesmereUI._bdBorderData then
                    local bdFrame = EllesmereUI._bdBorderData[btn]
                    if bdFrame then
                        bdFrame:SetFrameLevel(ns._eabBorderLevel(btn, s.borderBehind, s.borderAboveEffects))
                    end
                end
            else
                PP.ShowBorder(btn)
            end
        elseif fd.borders then
            PP.HideBorder(btn)
            if EllesmereUI._bdBorderData then
                local bdFrame = EllesmereUI._bdBorderData[btn]
                if bdFrame then bdFrame:Hide() end
            end
        end
        -- Re-enable Blizzard's Border texture (was hidden for custom shapes)
        if btn.Border then
            SetSquareTexture(btn.Border, HIGHLIGHT_TEXTURES[1])
        end
        return
    end

    -- Custom shape
    local maskTex = SHAPE_MASKS[shape]
    if not maskTex then return end

    if not fd.shapeMask then
        fd.shapeMask = btn:CreateMaskTexture()
    end
    local mask = fd.shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    local icon = btn.icon or btn.Icon

    -- Always remove existing mask references before re-adding
    -- (AddMaskTexture is additive; stale references cause shape-inside-shape)
    if icon then pcall(icon.RemoveMaskTexture, icon, mask) end
    if fd.slotBG then pcall(fd.slotBG.RemoveMaskTexture, fd.slotBG, mask) end
    if fd.iconBg then pcall(fd.iconBg.RemoveMaskTexture, fd.iconBg, mask) end
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
    end
    if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
        pcall(btn.chargeCooldown.RemoveMaskTexture, btn.chargeCooldown, mask)
    end
    do
        -- Remove overlay textures from whichever mask they were on
        local omask = fd.overlayMask or mask
        if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, omask) end
        if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, omask) end
        if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, omask) end
        if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, omask) end
        if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, omask) end
        if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, omask) end
        if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, omask) end
        local nt2 = btn.NormalTexture or btn:GetNormalTexture()
        if nt2 then pcall(nt2.RemoveMaskTexture, nt2, omask) end
        if btn.SpellActivationAlert then
            UnmaskFrameTextures(btn.SpellActivationAlert, omask)
            EFD(btn.SpellActivationAlert).shapeMasked = nil
        end
        -- Also clean from main mask if overlay mask was separate
        if fd.overlayMask and fd.overlayMask ~= mask then
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, mask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, mask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, mask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, mask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, mask) end
            if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, mask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, mask) end
            if nt2 then pcall(nt2.RemoveMaskTexture, nt2, mask) end
        end
        if fd.glowWrapper then
            UnmaskFrameTextures(fd.glowWrapper, mask)
            local wfd = EFD(fd.glowWrapper)
            if wfd.ownMask then
                UnmaskFrameTextures(fd.glowWrapper, wfd.ownMask)
            end
        end
    end

    -- Apply mask to icon
    if icon then icon:AddMaskTexture(mask) end

    -- Overlay/animation mask: with a border (brdSize >= 1) use a separate inset
    -- mask so animations stop at the border edge instead of bleeding past it.
    local overlayMask
    if brdSize and brdSize >= 1 then
        if not fd.overlayMask then
            fd.overlayMask = btn:CreateMaskTexture()
        end
        overlayMask = fd.overlayMask
        overlayMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        overlayMask:ClearAllPoints()
        local inset = 3
        PP.Point(overlayMask, "TOPLEFT", btn, "TOPLEFT", inset, -inset)
        PP.Point(overlayMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
        overlayMask:Show()
    else
        -- No border overlays share the main mask, hide overlay mask if it exists
        if fd.overlayMask then fd.overlayMask:Hide() end
        overlayMask = mask
    end

    -- Apply overlay mask to all button overlay textures
    if btn.HighlightTexture then pcall(btn.HighlightTexture.AddMaskTexture, btn.HighlightTexture, overlayMask) end
    if btn.PushedTexture then pcall(btn.PushedTexture.AddMaskTexture, btn.PushedTexture, overlayMask) end
    if btn.CheckedTexture then pcall(btn.CheckedTexture.AddMaskTexture, btn.CheckedTexture, overlayMask) end
    if btn.NewActionTexture then pcall(btn.NewActionTexture.AddMaskTexture, btn.NewActionTexture, overlayMask) end
    if btn.Flash then pcall(btn.Flash.AddMaskTexture, btn.Flash, overlayMask) end
    if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.AddMaskTexture, btn.QuickKeybindHighlightTexture, overlayMask) end
    -- Blizzard's item-quality Border uses a round atlas that does not match
    -- non-square shapes, so hide it whenever a custom shape is on.
    if btn.Border then
        btn.Border:Hide()
    end
    if fd.slotBG then pcall(fd.slotBG.AddMaskTexture, fd.slotBG, mask) end
    if fd.iconBg then pcall(fd.iconBg.AddMaskTexture, fd.iconBg, mask) end
    local nt = btn.NormalTexture or btn:GetNormalTexture()
    if nt then pcall(nt.AddMaskTexture, nt, overlayMask) end

    -- Expand icon beyond button frame
    local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = (SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
    local iconExp = SHAPE_ICON_EXPAND + shapeOffset + ((zoom or 0) - shapeDefault) * 200
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if icon then
        icon:ClearAllPoints()
        PP.Point(icon, "TOPLEFT", btn, "TOPLEFT", -halfIE, halfIE)
        PP.Point(icon, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask inset for border
    mask:ClearAllPoints()
    if brdSize and brdSize >= 1 then
        PP.Point(mask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(mask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(btn)
    end

    -- Expand texcoords
    local insetPx = SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if icon then icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Hide square borders (both PP and textured)
    if fd.borders then
        PP.HideBorder(btn)
        if EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[btn]
            if bdFrame then bdFrame:Hide() end
        end
    end

    -- Shape border texture
    if not fd.shapeBorder then
        fd.shapeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = fd.shapeBorder
    pcall(borderTex.RemoveMaskTexture, borderTex, mask)
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(btn)
    local btfd = EFD(borderTex)
    if brdOn and SHAPE_BORDERS[shape] then
        borderTex:SetTexture(SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:Show()
        btfd.wantsShow = true
    else
        borderTex:Hide()
        btfd.wantsShow = false
    end

    -- Apply mask to cooldown frames so swipe follows the shape
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.AddMaskTexture, btn.cooldown, mask)
        if btn.cooldown.SetSwipeTexture then
            pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, maskTex)
        end
    end
    if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
        pcall(btn.chargeCooldown.AddMaskTexture, btn.chargeCooldown, mask)
        if btn.chargeCooldown.SetSwipeTexture then
            pcall(btn.chargeCooldown.SetSwipeTexture, btn.chargeCooldown, maskTex)
        end
    end

    -- Mask proc glow animation frames
    if btn.SpellActivationAlert then
        MaskFrameTextures(btn.SpellActivationAlert, overlayMask)
        EFD(btn.SpellActivationAlert).shapeMasked = true
    end
    if fd.glowWrapper then
        local w = fd.glowWrapper
        local wfd = EFD(w)
        if not wfd.ownMask then
            wfd.ownMask = w:CreateMaskTexture()
        end
        wfd.ownMask:ClearAllPoints()
        PP.Point(wfd.ownMask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(wfd.ownMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        wfd.ownMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wfd.ownMask:Show()
        MaskFrameTextures(w, wfd.ownMask)
    end

    -- Store shape tracking flags for cooldown edge system
    fd.shapeApplied = true
    fd.shapeName = shape
    fd.shapeMaskPath = maskTex

    -- Apply shape-specific cooldown edge: circular edge for non-square shapes,
    -- per-shape scale, custom texture + current color.
    local shapeEdgeScale = SHAPE_EDGE_SCALES[shape] or 0.60
    local useCircular = (shape ~= "square" and shape ~= "csquare")
    do
        local edgeTex = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\edge.png"
        local p = EAB.db and EAB.db.profile
        local cr, cg, cb, ca = 0.973, 0.839, 0.604, 1
        if p then
            if p.cooldownEdgeUseClassColor then
                local _, cls = UnitClass("player")
                local cc = RAID_CLASS_COLORS[cls]
                if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                ca = (p.cooldownEdgeColor and p.cooldownEdgeColor.a) or 1
            elseif p.cooldownEdgeColor then
                cr = p.cooldownEdgeColor.r or cr
                cg = p.cooldownEdgeColor.g or cg
                cb = p.cooldownEdgeColor.b or cb
                ca = p.cooldownEdgeColor.a or ca
            end
        end
        for _, cd in ipairs({btn.cooldown, btn.chargeCooldown}) do
            if cd and not cd:IsForbidden() then
                if cd.SetEdgeTexture then pcall(cd.SetEdgeTexture, cd, edgeTex) end
                if cd.SetEdgeColor then pcall(cd.SetEdgeColor, cd, cr, cg, cb, ca) end
                if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, useCircular) end
                if cd.SetEdgeScale then pcall(cd.SetEdgeScale, cd, shapeEdgeScale) end
            end
        end
    end

    fd.cropped = false
end

-- Entry points the files after this one re-import by name.
I.SetSquareTexture = SetSquareTexture
I.ApplyButtonBorders = ApplyButtonBorders
I.ApplyShapeToButton = ApplyShapeToButton
I.MaskFrameTextures = MaskFrameTextures
