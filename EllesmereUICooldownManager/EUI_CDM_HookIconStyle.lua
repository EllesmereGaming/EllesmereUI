if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookIconStyle.lua
--
--  The active aura cache, IsFrameIncluded, hiding Blizzard's decorations, stock
--  icon art and the charge cooldown style.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local _ecmeFC = ns._ecmeFC
local FC = ns.FC

local hookFrameData, ResolveSpellSettings = I.hookFrameData, I.ResolveSpellSettings

-------------------------------------------------------------------------------
--  Active aura cache (consumed by bar glow overlays)
--  Maintained by the 0.1s buff ticker, NOT here: it walks viewer pools cheaply
--  and writes spellID->true for any frame whose Blizzard-set
--  wasSetFromAura/auraInstanceID indicates an active aura. Bar glows read
--  ns._tickBlizzActiveCache.
-------------------------------------------------------------------------------
local _activeCache = {}
ns._tickBlizzActiveCache = _activeCache

-- Per-spellID application count, same population pass as _activeCache above,
-- same sid/baseSID/linked resolution (so it matches whatever spellID a Bar
-- Glow entry was saved against). Value is a plain number, a SECRET number,
-- or nil (no stack data). Consumed by Bar Glows' stack-threshold gate --
-- forwarded straight into a StatusBar:SetValue, never compared in Lua.
local _activeStacksCache = {}
ns._tickBlizzAuraStacks = _activeStacksCache

-------------------------------------------------------------------------------
--  IsFrameIncluded
--  Include if shown OR has cooldownInfo (catches transitional frames).
-------------------------------------------------------------------------------
local function IsFrameIncluded(frame)
    if not frame then return false end
    return frame:IsShown() or (frame.cooldownInfo ~= nil)
end

-------------------------------------------------------------------------------
--  HideBlizzardDecorations
--  Strip Blizzard visual chrome from a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function HideBlizzardDecorations(frame)
    local fc = FC(frame)
    if fc.blizzHidden then return end
    fc.blizzHidden = true

    local function alphaZero(child)
        if child then child:SetAlpha(0) end
    end
    alphaZero(frame.Border)
    if frame.SpellActivationAlert then
        frame.SpellActivationAlert:SetAlpha(0)
        frame.SpellActivationAlert:Hide()
    end
    alphaZero(frame.Shadow)
    alphaZero(frame.IconShadow)
    alphaZero(frame.DebuffBorder)
    alphaZero(frame.CooldownFlash)

    local iconWidget = frame.Icon
    local regions = { frame:GetRegions() }
    -- Blizzard Style keeps the viewer's rounded icon mask; only the ring
    -- overlay is replaced (ns.CdmApplyBlizzIconArt redraws it at the icon's
    -- live size, since the viewer's fixed inset only fits its stock sizes).
    -- Classic WoW UI icons are square, so they take the swap like the EUI look.
    local keepMask = ns.CdmIconStyle() == "blizzard"
    for ri = 1, #regions do
        local rgn = regions[ri]
        if not keepMask and rgn and rgn.IsObjectType and rgn:IsObjectType("MaskTexture") then
            pcall(function() rgn:SetTexture("Interface\\Buttons\\WHITE8X8") end)
        end
    end
    if frame.Cooldown and not keepMask then
        local cdRegions = { frame.Cooldown:GetRegions() }
        for ri = 1, #cdRegions do
            local rgn = cdRegions[ri]
            if rgn and rgn.IsObjectType and rgn:IsObjectType("MaskTexture") then
                pcall(function() rgn:SetTexture("Interface\\Buttons\\WHITE8X8") end)
            end
        end
    end

    -- The ring overlay, matched by atlas or by its sheet file. The rounded
    -- MASK lives in the same sheet, so the file match must skip masks: a
    -- hidden mask masks nothing (Blizzard Style needs it; the EUI look has
    -- already squared it above).
    local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
    local OVERLAY_FILE  = 6707800
    for ri = 1, #regions do
        local rgn = regions[ri]
        if rgn and rgn ~= iconWidget and rgn.GetObjectType and rgn:GetObjectType() == "Texture" then
            local atlas = rgn.GetAtlas and rgn:GetAtlas()
            local tex = rgn.GetTexture and rgn:GetTexture()
            if atlas == OVERLAY_ATLAS or tex == OVERLAY_FILE then
                rgn:SetAlpha(0)
                rgn:Hide()
            end
        end
    end

    -- Do NOT call SetHideCountdownNumbers here; SetCountdownFont controls CD text.
end

-------------------------------------------------------------------------------
--  Stock style icon art (Global Settings > Style)
--  Blizzard Style: the viewer's look on every icon we lay out: rounded mask,
--  bevel ring and rounded swipe. Pooled viewer frames keep Blizzard's own mask
--  (HideBlizzardDecorations leaves it under this style); frames we create
--  (trinkets, placeholders, custom buffs, item presets) get an equivalent one.
--  Classic WoW UI: the vanilla action button ring round a square icon (no
--  mask, EUI's own square swipe).
--  The ring is our own texture on a child frame, so it survives pool reuse and
--  follows the icon's live size instead of the viewer's fixed stock inset.
--  Idempotent and cheap: structural work once per frame, then a size memo
--  gates the re-anchor. Never runs unless a stock style is on.
-------------------------------------------------------------------------------
function ns.CdmApplyBlizzIconArt(frame)
    if not frame then return end
    local fc = FC(frame)
    local classic = ns.CdmClassicIcons()
    local host = fc.blizzHost
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        host:EnableMouse(false)
        fc.blizzHost = host
        local ov = host:CreateTexture(nil, "OVERLAY", nil, 5)
        if classic then ov:SetTexture(ns.CDM_CLASSIC_RING) else ns.CdmStockAtlas(ov, ns.CDM_BLIZZ_OVERLAY) end
        if ov.SetSnapToPixelGrid then ov:SetSnapToPixelGrid(false); ov:SetTexelSnappingBias(0) end
        fc.blizzOverlay = ov
        -- Own frames carry no viewer mask or swipe art: the rounded kit adds
        -- both (classic icons stay square on the default swipe).
        if not frame.viewerFrame and not classic then
            local fd = hookFrameData[frame]
            local tex = (fd and fd.tex) or frame._tex or frame.Icon
            if tex and tex.AddMaskTexture then
                local mask = frame:CreateMaskTexture()
                mask:SetAtlas(ns.CDM_BLIZZ_MASK)
                mask:SetAllPoints(frame)
                tex:AddMaskTexture(mask)
                fc.blizzMask = mask
            end
            local cd = (fd and fd.cooldown) or frame._cooldown or frame.Cooldown
            if cd and cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, ns.CDM_BLIZZ_SWIPE) end
        end
    end
    -- Viewer frames: the viewer's own rounded mask, re-asserted once (shown,
    -- on the atlas) so no earlier pass can have left it hidden or squared.
    -- Classic keeps the square mask HideBlizzardDecorations gave it.
    if frame.viewerFrame and not classic and not fc.blizzMaskOK then
        fc.blizzMaskOK = true
        local fd = hookFrameData[frame]
        local tex = (fd and fd.tex) or frame.Icon
        local n = tex and tex.GetNumMaskTextures and tex:GetNumMaskTextures() or 0
        for i = 1, n do
            local m = tex:GetMaskTexture(i)
            if m then
                pcall(m.SetAtlas, m, ns.CDM_BLIZZ_MASK)
                pcall(m.SetAlpha, m, 1)
                pcall(m.Show, m)
            end
        end
    end
    -- Ring above the art and swipe (+14), below glows (+16) and text (+23).
    local lvl = frame:GetFrameLevel() + 15
    if host:GetFrameLevel() ~= lvl then host:SetFrameLevel(lvl) end
    local w, h = frame:GetSize()
    if fc.blizzArtW ~= w or fc.blizzArtH ~= h then
        fc.blizzArtW, fc.blizzArtH = w, h
        local ov = fc.blizzOverlay
        if classic then
            ns.CdmPlaceClassicRing(ov, host, w, h)
        else
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT", host, "TOPLEFT", -w * ns.CDM_BLIZZ_RING_X, h * ns.CDM_BLIZZ_RING_Y)
            ov:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", w * ns.CDM_BLIZZ_RING_X, -h * ns.CDM_BLIZZ_RING_Y)
        end
    end
end
-- The rounded mask an icon's art carries under Blizzard Style (the viewer's
-- own on pooled frames, ours on own frames), for overlays that copy the art
-- (fake-active, press flash) so they round off with it. Nil under Classic
-- WoW UI, whose icons are square.
function ns.CdmBlizzIconMask(frame)
    if ns.CdmClassicIcons() then return nil end
    local fc = frame and _ecmeFC[frame]
    if fc and fc.blizzMask then return fc.blizzMask end
    local fd = frame and hookFrameData[frame]
    local tex = (fd and fd.tex) or (frame and (frame.Icon or frame._tex))
    if tex and tex.GetNumMaskTextures and tex:GetNumMaskTextures() > 0 then
        return tex:GetMaskTexture(1)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Charge cooldown style
--  BASELINE: every charge spell draws the cooldown edge (spark) like the action
--  bars -- follows the icon shape's square/circular path at the shape's scale,
--  masked by the CDM shape system. Always on for charge spells, no setting.
--  PER-SPELL: "Hide Swipe (Charges)" also hides the radial swipe (edge only),
--  resolved only when in use (ns._cdmAnyChargeStyle) so others pay ~0.
-------------------------------------------------------------------------------
-- Game-indexed on purpose: the 12.1 edge channel renders game-indexed files
-- ONLY -- loose addon art (png/tga/blp) draws nothing, silently, with clean
-- state readbacks.
local CDM_EDGE_TEXTURE = "Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown"

-- NOTE (probed 2026-08-12): the Cooldown widget clips ALL edge drawing at
-- the frame's own rect -- scales past flush render identically, so the edge
-- can never reach a square's corners without enlarging the cooldown frame
-- itself. Do not re-attempt corner coverage via SetEdgeScale.

-- Thin wrapper: frame spell/bar identity -> ResolveSpellSettings, the same
-- Hero-talent-aware resolver the SetSwipeColor / cdState / desat hooks use, so
-- the charge "Hide Swipe" path resolves override spells identically.
function ns._ResolveCdmSS(frame)
    local fc2 = _ecmeFC[frame]
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then return nil end
    return ResolveSpellSettings(frame, sid2, false)
end

-- Draw the styled cooldown edge -- one texture for every edge lane: the
-- always-on charge recharge edge and the bar-wide Always Show Cooldown Edge
-- re-assert both land here. The shape system owns the mask + circular-edge
-- flag; this applies texture, color, scale and draw flag.
local function ApplyCdmEdge(cd, bk2)
    if not cd then return end
    local bd = barDataByKey and barDataByKey[bk2]
    local shape = (bd and bd.iconShape) or "none"
    -- SetEdgeScale is frame-relative so the edge tracks icon size: plain icons
    -- use the action bars' baseline size, custom shapes the per-shape scale.
    local scale
    if shape == "none" or shape == "cropped" then
        scale = 1.8
    else
        scale = (ns.CDM_SHAPE_EDGE_SCALES and ns.CDM_SHAPE_EDGE_SCALES[shape]) or 0.75
    end
    -- Color rides SetEdgeTexture: the documented signature is
    -- (texture, r, g, b, a) with the color args required.
    if cd.SetEdgeTexture then
        cd:SetEdgeTexture(CDM_EDGE_TEXTURE, 1, 1, 1, 1)
    end
    if cd.SetEdgeScale then cd:SetEdgeScale(scale) end
    if cd.SetDrawEdge then cd:SetDrawEdge(true) end
end

-- Live active-state read from Blizzard's swipe color (fd._wasActive is stale on
-- falloffs). Secret-safe: a secret red channel reads as not active. Lets charge
-- "Hide Swipe" keep the active-state colored swipe visible.
local function CdmFrameIsActive(frame)
    local swipeColor = frame and frame.cooldownSwipeColor
    if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
        local r = swipeColor:GetRGBA()
        if r and type(r) == "number" and not issecretvalue(r) then
            return r ~= 0
        end
    end
    return false
end

-- Blizzard resolves a cooldown item's spell through GetSpellID(), whose
-- precedence is aura > linkedSpellID > overrideTooltip > override > base
-- (CooldownViewerItemData.lua). When an aura ends without the item receiving the
-- UNIT_AURA removal, cooldownInfo.linkedSpellID keeps pointing at the aura, so
-- CheckCacheCooldownValuesFromSpellCooldown reads the cooldown from a spell that
-- HAS none: start/dur come back 0, IsExpired() answers true, and
-- RefreshSpellCooldownInfo takes its CooldownFrame_Clear branch on every refresh
-- -- no swipe, no countdown text -- while RefreshIconDesaturation leaves the icon
-- saturated. The ability is still on cooldown, so the icon reads as "never
-- pressed" until a target switch (OnNewTarget clears the link), a re-cast of the
-- base spell, or a cooldownID re-set. Blizzard's own repair for this,
-- RefreshLinkedSpell, is only called from OnCooldownIDSet, never from RefreshData.
--
-- How the link outlives the aura: ClearAuraInstanceInfo() drops the instance but
-- NOT the link, and the only path that drops both is OnUnitAuraRemovedEvent,
-- which is dispatched through auraInstanceIDToItemFramesMap and is therefore
-- missable. Any later RefreshData then clears the instance via RefreshAuraInstance
-- and leaves the link standing.
--
-- Detected with nil-compares and never-secret bools ONLY. In instanced combat
-- Cooldown:GetCooldownDuration answers a SECRET value, which is exactly why
-- ReAssertRealCooldown's "widget reads ~0" proof fails closed there -- i.e. in
-- the content where this is reported.
--
-- We repair OUR rendering only; Blizzard's item stays wrong, so its own alerts
-- and isOnActualCooldown keep answering against the linked spell.
--
-- Ordered cheapest-first: linkedSpellID is nil for nearly every icon, so the
-- common case costs two table lookups and no API call. Returns the STRUCTURAL
-- verdict only; callers add their own "is on a real cooldown" test.
local function CdmStaleLinkedSpell(frame)
    local info = frame and frame.cooldownInfo
    if info == nil or info.linkedSpellID == nil then return false end
    -- An aura that is actually being displayed owns the widget; never fight it.
    -- Covers the transient where UpdateLinkedSpell has set the link a moment
    -- before RefreshAuraInstance attaches the matching instance.
    if frame.auraInstanceID ~= nil or frame.wasSetFromAura then return false end
    return true
end

-- Charge info for a CDM frame, resolved the way BLIZZARD resolves it.
--
-- We were resolving the charge spell with C_SpellBook.FindSpellOverrideByID and
-- Blizzard resolves it from the CooldownViewer's OWN override record --
-- CooldownViewerItemDataMixin:GetSpellChargeInfo reads
-- `info.overrideSpellID or info.spellID`, deliberately, "to ensure that charges
-- work correctly for cooldown items that are actively cast, apply auras, and
-- have charges". Those are two different sources and they disagree in the field:
-- captured on a Mage, base Blink 1953 with FindSpellOverrideByID resolving to
-- Shimmer 212653, our read returned isActive=false (no recharge) while Blizzard's
-- own HasVisualDataSource_Charges was true (a recharge running with charges in
-- hand) on the very same frame in the very same call.
--
-- That disagreement is not cosmetic: chargeRecharging false is what lets the
-- Suppress GCD block alpha-0 a swipe, so with Suppress GCD on, an override
-- spell's recharge swipe gets blanked for the whole GCD every time another
-- ability is pressed -- the exact failure the charge carve-out exists to
-- prevent. Asking Blizzard removes the whole class rather than special-casing
-- Shimmer.
--
-- Falls back to the old resolution for frames without the accessor (preset,
-- custom-spell and item frames are ours, not CooldownViewer items), so those
-- keep exactly today's behaviour.
local function CdmChargeInfoFor(frame, sid)
    if frame and type(frame.GetSpellChargeInfo) == "function" then
        local ci = frame:GetSpellChargeInfo()
        if ci then return ci end
    end
    if not (sid and C_Spell and C_Spell.GetSpellCharges) then return nil end
    local effID = sid
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ovr = C_SpellBook.FindSpellOverrideByID(sid)
        if ovr and ovr > 0 and ovr ~= sid then effID = ovr end
    end
    return C_Spell.GetSpellCharges(effID) or C_Spell.GetSpellCharges(sid)
end
ns.CdmChargeInfoFor = CdmChargeInfoFor

-- Apply charge cooldown style. Returns true for charge spells (caller skips its
-- own swipe forcing). Edge always drawn; the swipe hides only with per-spell
-- Hide Swipe (resolved only while ns._cdmAnyChargeStyle). Caller MUST guard with
-- fd._isProcessingOverride so the SetDrawSwipe sibling hook cannot recurse.
-- Secret-safe: HasVisualDataSource_Charges is a clean bool, the ss flag is ours.
local function ApplyCdmChargeStyle(frame, cd)
    -- Icon art suppressed (Only Show Numbers / Charges/Stacks Only): nothing for
    -- a swipe/edge to decorate. Report "handled" so callers skip their own
    -- swipe/edge defaults. The reentry guard is SAVED and restored, never forced
    -- false: ReapplyChargeStyle
    -- sets it before calling us and clearing it would drop its guard.
    local fdOsn = hookFrameData[frame]
    if fdOsn and fdOsn._osnOn then
        local prevGuard = fdOsn._isProcessingOverride
        fdOsn._isProcessingOverride = true
        if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        fdOsn._isProcessingOverride = prevGuard
        return true
    end
    if type(frame.HasVisualDataSource_Charges) ~= "function"
       or not frame:HasVisualDataSource_Charges() then
        return false
    end
    local fc2 = _ecmeFC[frame]
    ApplyCdmEdge(cd, fc2 and fc2.barKey)
    local hide = false
    if ns._cdmAnyChargeStyle then
        local ss2 = ns._ResolveCdmSS(frame)
        if ss2 then
            -- Hide Recharge Edge (per-spell): drop the edge ApplyCdmEdge just
            -- drew. Secret-safe: ss flag is ours, SetDrawEdge takes no secret.
            if ss2.hideRechargeEdge and cd.SetDrawEdge then
                cd:SetDrawEdge(false)
            end
            if ss2.chargeHideSwipe then
                -- Hide only the recharge swipe: the active-state overlay IS the
                -- colored swipe, so keep it while active.
                local showActive = ss2.activeSwipeMode ~= "none" and CdmFrameIsActive(frame)
                hide = not showActive
            end
        end
    end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(not hide) end
    return true
end

-- Immediately re-assert the charge style (Hide Recharge Edge + Hide Swipe) on one
-- icon instead of waiting for Blizzard's next cooldown re-push. Called from
-- RefreshCDMIconAppearance so toggling either setting (per-icon OR Apply to Bar)
-- updates a CURRENTLY recharging spell now. No-op on non-charge frames
-- (ApplyCdmChargeStyle self-skips); reentry-guarded so siblings cannot recurse.
function ns.ReapplyChargeStyle(frame)
    local fd = frame and hookFrameData[frame]
    local cd = fd and fd.cooldown
    if not cd or fd._isProcessingOverride then return end
    fd._isProcessingOverride = true
    ApplyCdmChargeStyle(frame, cd)
    fd._isProcessingOverride = false
end

-- Max Stacks Glow (per-spell): glow a charge spell at max charges. 1:1 with
-- Active State Glow but on its own overlay (the two never fight), driven by
-- charge state. ss2.maxStacksGlow is the STYLE, color is unified ss.glowColor.
-- atMax is a CLEAN bool from GetSpellCharges().isActive (recharge-active flag,
-- false only at max) -- never the secret currentCharges.
local function ApplyMaxStacksGlow(frame, fd, ss2, atMax)
    if not fd then return end
    local has = ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0
    if has and atMax then
        if not fd._maxStacksGlowOn then
            -- Lazy-create (unused feature adds no frame). Own overlay never
            -- fights the active glow (StartNativeGlow is per-overlay).
            local mo = fd.maxStacksGlowOverlay
            if not mo and frame then
                mo = CreateFrame("Frame", nil, frame)
                mo:SetAllPoints(frame)
                mo:SetAlpha(0)
                mo:EnableMouse(false)
                fd.maxStacksGlowOverlay = mo
            end
            if mo then
                if frame then mo:SetFrameLevel(frame:GetFrameLevel() + 16) end
                local gr, gg, gb = ns.ResolveGlowColor(ss2)
                ns.StartNativeGlow(mo, ss2.maxStacksGlow, gr, gg, gb)
                fd._maxStacksGlowOn = true
            end
        end
    elseif fd._maxStacksGlowOn then
        if fd.maxStacksGlowOverlay then ns.StopNativeGlow(fd.maxStacksGlowOverlay) end
        fd._maxStacksGlowOn = false
    end
end

-- Driven by SPELL_UPDATE_CHARGES, NOT the cooldown-widget hooks: those fire when
-- a charge is SPENT but not when the last charge REFILLS to max. That event
-- fires on BOTH charge transitions and nothing else (far cheaper than
-- SPELL_UPDATE_COOLDOWN, every GCD) and isActive only flips with a charge-count
-- change, so one event catches both edges. The watch set holds only glow-enabled
-- icons; the event frame is created only once the feature is on (0 cost).
ns._maxStacksWatch = ns._maxStacksWatch or setmetatable({}, { __mode = "k" })

-- Re-derive at-max from CLEAN charge state and (un)glow. Self-unwatches when the
-- per-icon setting is off or the frame lost its spell, so the set drains itself.
local function EvalMaxStacksFrame(frame, fd)
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not sidw or not bkw then
        ApplyMaxStacksGlow(frame, fd, nil, false)
        ns._maxStacksWatch[frame] = nil
        return
    end
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if not (ssw and ssw.maxStacksGlow and ssw.maxStacksGlow > 0) then
        ApplyMaxStacksGlow(frame, fd, ssw, false)
        ns._maxStacksWatch[frame] = nil
        return
    end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    -- atMax derives PURELY from charge data (maxCharges + recharge isActive),
    -- NEVER HasVisualDataSource_Charges: that is false while the icon draws a GCD
    -- swipe, dropping the glow whenever a charge tops off mid-GCD. maxCharges>1
    -- is itself the charge-spell test (nil/1 for non-charge -> atMax false).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local atMax = ci ~= nil and (ci.maxCharges or 0) > 1 and not ci.isActive
    ApplyMaxStacksGlow(frame, fd, ssw, atMax)
end

local function WatchMaxStacksFrame(frame, fd)
    ns._maxStacksWatch[frame] = fd
    if not ns._maxStacksEventFrame then
        local ef = ns.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(ns._maxStacksWatch) do
                EvalMaxStacksFrame(f, d)
            end
        end)
        ns._maxStacksEventFrame = ef
    end
end

-- Called from RefreshCDMIconAppearance (login + settings changes) so an at-max
-- charge spell (no swipe, so it never fires the swipe hook) still gets watched.
-- Early-outs on non-charge icons (cheap capability check, no settings lookup);
-- once watched SPELL_UPDATE_CHARGES keeps it current. Self-cleans when disabled.
function ns.WatchMaxStacksIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then return end
    -- Charge-spell test via static charge data (stable). HasVisualDataSource_Charges
    -- flips false during a GCD swipe and would wrongly skip the spell here too.
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local isCharge = ci ~= nil and (ci.maxCharges or 0) > 1
    local ssw = isCharge and ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw)) or nil
    if ssw and ssw.maxStacksGlow and ssw.maxStacksGlow > 0 then
        ns._cdmAnyMaxStacksGlow = true
        WatchMaxStacksFrame(frame, fd)
        EvalMaxStacksFrame(frame, fd)
    elseif ns._maxStacksWatch[frame] then
        ns._maxStacksWatch[frame] = nil
        ApplyMaxStacksGlow(frame, fd, nil, false)
    end
end

I._activeCache, I._activeStacksCache = _activeCache, _activeStacksCache
I.ApplyCdmChargeStyle, I.ApplyCdmEdge = ApplyCdmChargeStyle, ApplyCdmEdge
I.ApplyMaxStacksGlow, I.CdmChargeInfoFor = ApplyMaxStacksGlow, CdmChargeInfoFor
I.CdmFrameIsActive, I.CdmStaleLinkedSpell = CdmFrameIsActive, CdmStaleLinkedSpell
I.EvalMaxStacksFrame, I.HideBlizzardDecorations = EvalMaxStacksFrame, HideBlizzardDecorations
I.IsFrameIncluded, I.WatchMaxStacksFrame = IsFrameIncluded, WatchMaxStacksFrame
I.broken = false
