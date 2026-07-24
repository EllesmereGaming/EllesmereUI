local _, ns = ...

-- ===========================================================================
--  EllesmereUI CDM -- Custom Active State engine (isolated)
-- ===========================================================================
-- Draws OUR OWN icon (saturated, with its own duration swipe) on top of an
-- existing CDM icon while a custom "active window" is open, then hides it. It
-- NEVER modifies the underlying icon -- no desaturation, no swipe, no cooldown
-- changes; the underlying icon just sits beneath, covered while we are active.
--
-- Two rule sources:
--   1. Built-in rules (FAKE_ACTIVE_RULES) -- class/spec gated, can use an aura's
--      live remaining time (e.g. Aug Evoker Ebon Might).
--   2. User rules -- any cd/utility preset (trinket / potion / racial / custom
--      spell id) the player gives an "Active State" + timer to in the per-spell
--      menu. Stored at the PROFILE level keyed by spell (ns.GetCustomActiveStates),
--      so it travels with the spell across bars and specs. Triggered on use
--      (UNIT_SPELLCAST_SUCCEEDED); the entry's own Active Swipe / Active Glow /
--      Glow Effect Color fields style the overlay.
--
-- ISOLATION / ZERO-COST
--   * Built-in rules live in FAKE_ACTIVE_RULES below (one row each).
--   * Re-armed on every CDM full rebuild. If nothing is active for this spec /
--     profile, no events register and the engine is inert.
--
-- TAINT: trigger is a plain event; the overlay is entirely our own frames,
-- toggled by alpha (never Show/Hide). No Blizzard frame tables are written.
-- ===========================================================================

local GetTime                = GetTime
local UnitClass              = UnitClass
local GetSpecialization      = GetSpecialization
local GetInventoryItemID     = GetInventoryItemID
local CreateFrame            = CreateFrame
local C_Timer                = C_Timer
local C_Item                 = C_Item
local C_SpellBook            = C_SpellBook
local wipe                   = wipe
local pcall                  = pcall
local type                   = type
local RAID_CLASS_COLORS      = RAID_CLASS_COLORS
local C_Container            = C_Container
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

-- 12.1 ONLY: engine-slot driver for aura-triggered built-in rules. Ebon Might
-- (395296) was removed from the never-secret list in build 68824, so
-- GetPlayerAuraBySpellID returns nothing for it in restricted content and the
-- numeric expirationTime window can never open mid-combat. The replacement
-- rides a hidden one-slot aura container (includeSpellIDs on the player --
-- helpful-on-assistable passes the identity gate regardless of secrecy)
-- whose slot subtree IS the active display, engine-driven end to end: the
-- button shows only while the aura is up, SetIcon binds the aura's own
-- texture, SetDurationCooldown renders the swipe from the real duration
-- object (extensions included), and SetDurationText drives the countdown
-- text -- all styled inside the creation window (the subtree is denied to
-- addon code afterward, reads and writes both). The legacy overlay frame
-- stays permanently dark on 12.1; it survives only for border raising and
-- the shared settings plumbing in ApplyToFrame.
-- FA121 stays nil on 12.0: every consumer site guards on it, so retail
-- behavior is byte-identical. Declared here (above ApplyToFrame) so the
-- gated sites capture it as an upvalue; defined after ApplyRule below.
local FA121

-- ---------------------------------------------------------------------------
--  BUILT-IN RULES
-- ---------------------------------------------------------------------------
-- spellID        the CDM icon to decorate (the ability icon's spellID)
-- class / spec   optional gates (spec = index 1..4)
-- trigger        "aura" | "cast" | function(api) -> expiry|true|nil
-- auraSpellID    (aura)  player buff whose expirationTime drives the window
-- triggerSpellID (cast)  spell whose cast opens the window (default = spellID)
-- duration       window seconds ("aura": fallback when the aura reports none)
local FAKE_ACTIVE_RULES = {
    -- Augmentation Evoker -- Ebon Might (real buff window, extend/drop aware).
    {
        spellID     = 395152,
        class       = "EVOKER",
        spec        = 3,
        trigger     = "aura",
        auraSpellID = 395296,
        duration    = 20,
    },
}

-- ---------------------------------------------------------------------------
--  State
-- ---------------------------------------------------------------------------
local _armed     = false
local _rules     = {}                                  -- all live rules this spec/profile
local _auraRules = {}                                  -- subset: aura trigger
local _customRules = {}                                -- subset: function trigger
local _castMap   = {}                                  -- castSpellID -> { rule, ... }
local _needAura  = false
local _needCast  = false
local _windows   = setmetatable({}, { __mode = "k" })  -- rule -> { start, dur, expiry }
local _lastCast
local _events
local _ticker
local _api       = {}
local _overlays  = setmetatable({}, { __mode = "k" })  -- iconFrame -> overlay data

-- Cooldown-state effects (continuous, cooldown-driven; presets only).
local _cdStateRules = {}                                -- subset: cas.cdStateEffect set
local _cdStateTicker
local _hasUserRules = false                             -- any profile (user) rule armed

-- CD-ready sound "armed" state, keyed by ability so it survives the rule-object
-- churn of FakeActive_Rearm (rebuilds are frequent in M+ and would otherwise eat
-- the ready edge). Empty at login, so an already-ready preset never false-fires.
local _cdrArmedByKey = {}

-- Forward declarations
local GetOverlay, ResolveSwipeColor, IconTexture, ApplyToFrame, ApplyRule, RaiseOverlayBorders, RestoreOverlayBorders
local EnsureTicker, OpenWindow, CloseWindow, CloseAll, CastWindow
local OpenFromAura, EvalCustom, InitialStamp, OnEvent, UpdateListeners
local ResolveCastSpells
local PresetOnCD, ApplyCdState, RestoreAllCdState, EnsureCdStateTicker, EvalCdStateNow

-- ---------------------------------------------------------------------------
--  Overlay icon: one per underlying icon frame, pooled. Toggled by alpha only.
-- ---------------------------------------------------------------------------
GetOverlay = function(iconFrame)
    local o = _overlays[iconFrame]
    if o then return o end
    o = {}
    local lvl = (iconFrame:GetFrameLevel() or 0) + 20

    local f = CreateFrame("Frame", nil, iconFrame)
    f:SetAllPoints(iconFrame)
    f:SetFrameLevel(lvl)
    f:SetAlpha(0)
    o.frame = f

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    o.icon = icon

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetFrameLevel(lvl + 1)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(false)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    o.cd = cd

    -- Own glow frame for ns.ApplyActiveOverlays (never collides with the real
    -- active-state path's fd.glowOverlay).
    local glow = CreateFrame("Frame", nil, f)
    glow:SetAllPoints(f)
    glow:SetFrameLevel(lvl + 4)
    glow:SetAlpha(0)
    o.glowOverlay = glow

    _overlays[iconFrame] = o
    return o
end

-- ---------------------------------------------------------------------------
--  While an overlay is open it sits ABOVE the underlying icon (so it covers the
--  real icon + its swipe). Temporarily lift the icon's border frame(s) above the
--  overlay so the active swipe never paints over the border; restore on close.
--  "Show Behind" borders (bd.borderBehind) are intentionally behind the icon, so
--  leave those alone.
-- ---------------------------------------------------------------------------
RaiseOverlayBorders = function(iconFrame, o, bd)
    if o._brdRaised then return end
    local lvl = o.frame:GetFrameLevel() + 2
    local fd  = ns._hookFrameData and ns._hookFrameData[iconFrame]
    local ifc = ns._ecmeFC and ns._ecmeFC[iconFrame]
    if fd and fd.borderFrame and not (bd and bd.borderBehind) then
        o._brdSavedLvl = fd.borderFrame:GetFrameLevel()
        pcall(fd.borderFrame.SetFrameLevel, fd.borderFrame, lvl)
    end
    if ifc and ifc.shapeBorderFrame then
        o._sbSavedLvl = ifc.shapeBorderFrame:GetFrameLevel()
        pcall(ifc.shapeBorderFrame.SetFrameLevel, ifc.shapeBorderFrame, lvl)
    end
    o._brdRaised = true
end

RestoreOverlayBorders = function(iconFrame, o)
    if not o._brdRaised then return end
    local fd  = ns._hookFrameData and ns._hookFrameData[iconFrame]
    local ifc = ns._ecmeFC and ns._ecmeFC[iconFrame]
    if fd and fd.borderFrame and o._brdSavedLvl then
        pcall(fd.borderFrame.SetFrameLevel, fd.borderFrame, o._brdSavedLvl)
    end
    if ifc and ifc.shapeBorderFrame and o._sbSavedLvl then
        pcall(ifc.shapeBorderFrame.SetFrameLevel, ifc.shapeBorderFrame, o._sbSavedLvl)
    end
    o._brdSavedLvl, o._sbSavedLvl, o._brdRaised = nil, nil, false
end

-- Active swipe colour: class, custom, or default gold. Drives our own swipe.
ResolveSwipeColor = function(ss)
    local cr, cg, cb
    if ss and ss.activeSwipeClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
    end
    cr = cr or (ss and ss.activeSwipeR) or 1
    cg = cg or (ss and ss.activeSwipeG) or 0.776
    cb = cb or (ss and ss.activeSwipeB) or 0.376
    local ca = (ss and ss.activeSwipeA) or 0.7
    return cr, cg, cb, ca
end

-- Copy the underlying icon's texture + crop so the overlay looks identical
-- (works for both Blizzard pool frames .Icon and our preset frames ._tex).
IconTexture = function(iconFrame, o, rule)
    local src = iconFrame.Icon or iconFrame._tex
    if src and src.GetTexture then
        local t = src:GetTexture()
        if t then
            o.icon:SetTexture(t)
            o.icon:SetTexCoord(src:GetTexCoord())
            return
        end
    end
    if rule.spellID and rule.spellID > 0 and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(rule.spellID)
        o.icon:SetTexture(info and info.iconID)
        o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- ---------------------------------------------------------------------------
--  Show / hide the overlay on a single icon frame.
-- ---------------------------------------------------------------------------
ApplyToFrame = function(iconFrame, rule, win)
    local o = GetOverlay(iconFrame)
    -- Bar data + per-spell settings. User rules carry their own styling entry
    -- (profile-level, travels with the spell); built-in rules (e.g. Ebon Might)
    -- read the bar's per-spell settings. barData is needed either way for the
    -- overlay's shape geometry, so resolve it unconditionally.
    local fc = ns._ecmeFC and ns._ecmeFC[iconFrame]
    local barKey = fc and fc.barKey
    local bd = barKey and ns.barDataByKey and ns.barDataByKey[barKey]
    local ss = rule.cas
    if not ss then
        local sd = barKey and ns.GetBarSpellData and ns.GetBarSpellData(barKey)
        if ns.ResolveSpellSettings then
            ss = ns.ResolveSpellSettings(iconFrame, rule.spellID, sd, barKey)
        end
    end

    -- "Hide Active State" dropdown -> never show the overlay.
    local hidden = ss and ss.activeSwipeMode == "none"

    if win and not hidden then
        o._rule = rule  -- remembered so a live restyle can re-sync this overlay
        IconTexture(iconFrame, o, rule)
        -- Mirror the underlying icon's custom shape onto our overlay so a shaped
        -- icon stays shaped (mask + swipe), then lift the border above us.
        if ns.ApplyShapeToOverlay then ns.ApplyShapeToOverlay(iconFrame, o.icon, o.cd, bd) end
        RaiseOverlayBorders(iconFrame, o, bd)
        o.icon:SetDesaturated(false)
        local cr, cg, cb, ca = ResolveSwipeColor(ss)
        o.cd:SetSwipeColor(cr, cg, cb, ca)
        -- Per-spell Reverse Swipe: flip our active swipe's fill direction, the
        -- same setting the underlying icon honors (ss covers both sources: the
        -- resolved per-spell block for built-in rules, the customActiveStates
        -- entry for user rules). Gated by the session flag so it stays zero
        -- cost for anyone who never enables it; the flag is monotonic, so a
        -- toggle-off still passes through here and resets the pooled overlay.
        if ns._cdmAnyReverseSwipe then
            o.cd:SetReverse((ss and ss.reverseSwipe) and true or false)
        end
        o.cd:SetCooldown(win.start, win.dur)
        o._ss = ss
        -- Match the icon's Duration Text settings on our own countdown number;
        -- otherwise it renders in Blizzard's default font.
        if ns.StyleOverlayCooldownText then
            ns.StyleOverlayCooldownText(o.cd, bd, ss, iconFrame:GetScale())
        end
        -- Per-spell Threshold Text: the overlay countdown renders through the
        -- engine formatter (decimals / color change below the spell's Threshold
        -- Seconds). ss is the same block the swipe styling reads -- the user
        -- rule's customActiveStates entry, or the resolved per-spell settings
        -- for built-in rules. Gated = zero cost when unused; the apply helper
        -- only touches widgets it manages, and StyleOverlayCooldownText (above)
        -- already set the countdown numbers per the Duration Text state.
        if ns._cdmAnyThresholdText and ns.ApplyThresholdFormatter then
            ns.ApplyThresholdFormatter(o.cd, ss)
        end
        -- Feed the active glow + border the underlying icon's shape / border so
        -- Shape Glow masks to the shape (it reads the shape from its glow frame's
        -- parent FC) and Active Border can recolour the real (now-raised) border.
        local ufd  = ns._hookFrameData and ns._hookFrameData[iconFrame]
        local uifc = ns._ecmeFC and ns._ecmeFC[iconFrame]
        o.borderFrame = (ufd and ufd.borderFrame) or nil
        local gfc = ns.FC and ns.FC(o.frame)
        if gfc then
            gfc.shapeApplied = (uifc and uifc.shapeApplied) or nil
            gfc.shapeName    = (uifc and uifc.shapeName) or nil
            gfc.shapeMask    = (uifc and uifc.shapeMask) or nil
            gfc.shapeBorder  = (uifc and uifc.shapeBorder) or nil
        end
        if ns.ApplyActiveOverlays then ns.ApplyActiveOverlays(o.frame, o, ss, true, bd) end
        if win.fa121 and FA121 then
            -- 12.1 slot mode: the slot subtree renders the active display;
            -- Attach positions it and parks this legacy overlay at alpha 0.
            FA121.Attach(iconFrame, o, rule, ss, bd)
        else
            o.frame:SetAlpha(1)
        end
    else
        o._rule = nil
        o._ss = nil
        RestoreOverlayBorders(iconFrame, o)
        if ns.ApplyActiveOverlays then ns.ApplyActiveOverlays(o.frame, o, ss, false, bd) end
        o.cd:Clear()
        o.frame:SetAlpha(0)
        if FA121 then FA121.Detach(o) end
    end
end

-- Apply (or clear) a rule on every matching live icon. A rule with .barKey only
-- matches icons on that bar (user rules are per-bar); built-in rules match any.
ApplyRule = function(rule, win)
    local icons = ns.cdmBarIcons
    local FCt = ns._ecmeFC
    if not icons or not FCt then return end
    local sid = rule.spellID
    for _, list in pairs(icons) do
        for i = 1, #list do
            local f = list[i]
            local fc = f and FCt[f]
            if fc and fc.spellID == sid and (not rule.barKey or fc.barKey == rule.barKey) then
                ApplyToFrame(f, rule, win)
                if ns._fakeActiveDebug then
                    print(("|cff0cd29fEUI FakeActive|r %s sid=%s"):format(
                        win and "ON " or "off", tostring(sid)))
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  FA121 (12.1 only; see the declaration comment near the top). One state
--  entry per aura rule: { proxy, container, btn, cd, built, queued, armed,
--  o, iconFrame }. The container is built ONCE per rule through the AuraKit
--  scheduler (container shells are OOC-only; a job queued in combat holds to
--  regen) and parked by hiding the proxy -- a hidden container fully
--  unregisters its events, so the parked state costs nothing.
-- ---------------------------------------------------------------------------
if EllesmereUI and EllesmereUI.IS_121 then
    FA121 = { byRule = {} }
    local FA121_WIN = { fa121 = true, start = 0, dur = 0, expiry = 0 }

    local function St(rule)
        local st = FA121.byRule[rule]
        if not st then st = {}; FA121.byRule[rule] = st end
        return st
    end

    -- NO Lua presence signal exists: the button AND every child created in
    -- its creation window are denied to addon code afterward (field-mapped
    -- 2026-07-22 -- reads and writes both). The design therefore keeps the
    -- entire active display INSIDE the slot subtree, engine-driven end to
    -- end: visibility (button shown only while the aura is up), icon
    -- (SetIcon) and swipe (SetDurationCooldown) all render without any
    -- addon code running. The legacy overlay (o.frame) stays alpha 0 on
    -- 12.1 -- it exists only so RaiseOverlayBorders and settings plumbing
    -- keep working through the shared ApplyToFrame path.

    function FA121.Attach(iconFrame, o, rule, ss, bd)
        local st = St(rule)
        st.o, st.iconFrame = o, iconFrame
        if not st.built then
            -- Slot not built yet (queued; held to regen when queued in
            -- combat): stay dark until the build tail re-arms.
            o.frame:SetAlpha(0)
            return
        end
        -- Repositioning is ALWAYS a proxy move: the slot button anchored
        -- SetAllPoints(proxy) once in its creation window, and the proxy is
        -- our frame -- legal any time, icon churn included.
        -- Parent to the ICON FRAME, never to o.frame: the legacy overlay is
        -- held at alpha 0 on 12.1 and children inherit EFFECTIVE alpha -- a
        -- proxy under o.frame renders the whole engine subtree invisible
        -- (field-hit 2026-07-22: everything worked, at alpha 0).
        st.proxy:SetParent(iconFrame)
        st.proxy:ClearAllPoints()
        st.proxy:SetAllPoints(iconFrame)
        st.proxy:Show()
        -- One container-level set lifts the whole engine subtree (buttons
        -- keep relative levels), seating the swipe in the overlay band.
        st.container:SetFrameLevel(o.frame:GetFrameLevel() + 1)
        -- Best-effort live restyle of the engine-bound cooldown. FIELD
        -- LESSON (68824): SetDurationCooldown takes ownership -- touching
        -- the region outside the creation window is forbidden-object
        -- access, so the cooldown was fully styled at build time and this
        -- block is optional polish: attempted once, abandoned on denial.
        if st.cd and not st.cdLocked then
            local ok = pcall(st.cd.SetSwipeColor, st.cd, ResolveSwipeColor(ss))
            if ok then
                if ns._cdmAnyReverseSwipe then
                    pcall(st.cd.SetReverse, st.cd, (ss and ss.reverseSwipe) and true or false)
                end
                if ns.ApplyShapeToOverlay then
                    pcall(ns.ApplyShapeToOverlay, iconFrame, o.icon, st.cd, bd)
                end
                if ns.StyleOverlayCooldownText then
                    pcall(ns.StyleOverlayCooldownText, st.cd, bd, ss, iconFrame:GetScale())
                end
                if ns._cdmAnyThresholdText and ns.ApplyThresholdFormatter then
                    pcall(ns.ApplyThresholdFormatter, st.cd, ss)
                end
            else
                st.cdLocked = true
                if ns._fakeActiveDebug then
                    print("|cff0cd29fEUI FakeActive|r fa121 cd engine-locked (build-time styling only)")
                end
            end
        end
        -- The legacy overlay never renders on 12.1 (the slot subtree IS the
        -- active display); keep it dark regardless of what earlier paths
        -- set. Plain write -- always legal on our frame.
        o.frame:SetAlpha(0)
    end

    -- Close-branch handoff from ApplyToFrame: park the proxy so the engine
    -- subtree renders nothing (covers rule unarm AND "Hide Active State").
    function FA121.Detach(o)
        for _, st in pairs(FA121.byRule) do
            if st.o == o then
                st.o, st.iconFrame = nil, nil
                if st.proxy then st.proxy:Hide() end
            end
        end
    end

    local function Build(rule, st)
        local AK = EllesmereUI.AuraKit
        if st.built or not AK then return end
        AK.styles["cdm:fa121"] = AK.styles["cdm:fa121"]
            or { noRegions = true, width = 1, height = 1 }
        if not st.proxy then
            st.proxy = CreateFrame("Frame", nil, UIParent)
            st.proxy:Hide()
        end
        -- Resolve the rule's styling NOW (build runs at rearm time, when the
        -- icon usually exists) so the slot cooldown can be styled INSIDE the
        -- creation window. FIELD LESSON (68824): a region handed to an
        -- engine binding (SetDurationCooldown) is forbidden to addon code
        -- after initializeFrame returns -- even out of combat -- so
        -- creation-window styling is the only guaranteed styling.
        local ss, bd, scale = nil, nil, 1
        do
            local icons, FCt = ns.cdmBarIcons, ns._ecmeFC
            if icons and FCt then
                for _, list in pairs(icons) do
                    for i = 1, #list do
                        local f = list[i]
                        local fc = f and FCt[f]
                        if fc and fc.spellID == rule.spellID then
                            local barKey = fc.barKey
                            bd = barKey and ns.barDataByKey and ns.barDataByKey[barKey]
                            ss = rule.cas
                            if not ss and ns.ResolveSpellSettings then
                                local sd = barKey and ns.GetBarSpellData and ns.GetBarSpellData(barKey)
                                ss = ns.ResolveSpellSettings(f, rule.spellID, sd, barKey)
                            end
                            scale = f:GetScale() or 1
                            -- Bake the underlying icon's crop for the engine
                            -- icon (and remember the frame for shape masks).
                            st.srcFrame = f
                            local src = f.Icon or f._tex
                            if src and src.GetTexCoord then
                                local ok, a1, a2, a3, a4, a5, a6, a7, a8 = pcall(src.GetTexCoord, src)
                                if ok and a1 then
                                    st.srcCoords = { a1, a2, a3, a4, a5, a6, a7, a8 }
                                end
                            end
                            break
                        end
                    end
                    if ss or bd then break end
                end
            end
        end
        -- No icon found = CDM bars not built yet (login race) OR the spell
        -- is not on any bar. Do NOT build: every baked decision (the text
        -- gate, fonts, swipe color, crop) resolved nil and would be wrong
        -- for the whole session (built latches). The rescan retries
        -- re-queue the build; once the icon exists, everything bakes from
        -- real settings. Field-hit as "swipe works, no text" in sessions
        -- where the build outran bar construction.
        if not st.srcFrame then return end
        local container = AK.CreateContainerShell(st.proxy, { point = { "CENTER" } })
        AK.AddSlotToContainer(container, {
            key = "fa",
            filter = { "HELPFUL" },
            -- Helpful spellID includes on the player pass the identity gate
            -- regardless of the spell's secrecy flag.
            candidateFilters = { includeSpellIDs = { [rule.auraSpellID] = true } },
            style = "cdm:fa121",
            extraInit = function(button)
                -- Creation window: the only legal moment for button-level
                -- wiring AND (per the field lessons above) the only reliable
                -- window for touching ANYTHING in this subtree -- post-window
                -- reads AND writes on the button and its children are denied.
                -- Therefore the subtree is entirely self-sufficient: the
                -- ENGINE drives visibility (button shown only while the aura
                -- is up), the icon (SetIcon binds the aura's own texture)
                -- and the swipe (SetDurationCooldown from the real duration
                -- object, extensions included). No Lua signal, no slave.
                -- Two-point anchoring sizes the button by anchors forever.
                button:SetAllPoints(st.proxy)
                if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                -- Saturated icon: engine-bound, engine-shown. Zoom baked
                -- from the underlying CDM icon when it existed at build.
                local tex = button:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints(button)
                if st.srcCoords then
                    -- 8-value corner form, straight from the source icon.
                    tex:SetTexCoord(unpack(st.srcCoords))
                else
                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                cd:SetAllPoints(button)
                cd:SetDrawEdge(false)
                cd:SetDrawBling(false)
                cd:SetHideCountdownNumbers(false)
                cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
                cd:SetFrameLevel(button:GetFrameLevel() + 1)
                local cr, cg, cb, ca = ResolveSwipeColor(ss)
                cd:SetSwipeColor(cr, cg, cb, ca)
                if ss and ss.reverseSwipe then cd:SetReverse(true) end
                if ns.StyleOverlayCooldownText then
                    pcall(ns.StyleOverlayCooldownText, cd, bd, ss, scale)
                end
                if ns.ApplyThresholdFormatter then
                    pcall(ns.ApplyThresholdFormatter, cd, ss)
                end
                if ns.ApplyShapeToOverlay and st.srcFrame then
                    pcall(ns.ApplyShapeToOverlay, st.srcFrame, tex, cd, bd)
                end
                -- Duration text: engine-bound cooldowns render NO widget
                -- countdown (time display belongs to the SetDurationText
                -- binding -- the AuraKit rule), so register a dedicated
                -- FontString styled like the icon's cooldown text. Only
                -- when the resolved cooldown-text setting is on: the engine
                -- SetText()s every REGISTERED string, and a no-text config
                -- should carry no binding at all. Fonted BEFORE
                -- registration (an unfonted registered FS hard-errors
                -- inside the engine).
                local showCD = bd and bd.showCooldownText
                if ss and ss.showCooldownText ~= nil then showCD = ss.showCooldownText end
                if bd and bd.onlyShowNumbers then showCD = true end
                if showCD then
                    -- ARMORED: an uncaught error inside initializeFrame
                    -- aborts the engine's whole CreateFrameBatch and kills
                    -- the slot declaration (and every declaration after
                    -- it). Text is optional polish -- it must never take
                    -- the swipe down with it. Failures land in st.fsErr
                    -- for the debug dump.
                    local okFS, errFS = pcall(function()
                        -- Text CARRIER above the cooldown: regions created
                        -- on a Cooldown render UNDER its swipe (the classic
                        -- gotcha -- field-hit here as "healthy dump, no
                        -- text"). Same pattern as AuraKit's stackCarrier.
                        local tc = CreateFrame("Frame", nil, button)
                        tc:SetAllPoints(button)
                        tc:SetFrameLevel(cd:GetFrameLevel() + 5)
                        local fs = tc:CreateFontString(nil, "OVERLAY")
                        local cdFont = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm"))
                            or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
                        local fsScale = (scale and scale > 0.01) and scale or 1
                        local cdSize = ((ss and ss.cooldownFontSize) or (bd and bd.cooldownFontSize) or 12) / fsScale
                        if EllesmereUI.ApplyIconTextFont then
                            EllesmereUI.ApplyIconTextFont(fs, cdFont, cdSize, "cdm")
                        else
                            fs:SetFont(cdFont, cdSize, "OUTLINE")
                        end
                        fs:SetTextColor(
                            (ss and ss.cooldownTextR) or (bd and bd.cooldownTextR) or 1,
                            (ss and ss.cooldownTextG) or (bd and bd.cooldownTextG) or 1,
                            (ss and ss.cooldownTextB) or (bd and bd.cooldownTextB) or 1)
                        fs:SetPoint("CENTER", cd, "CENTER",
                            (ss and ss.cooldownTextX) or (bd and bd.cooldownTextX) or 0,
                            (ss and ss.cooldownTextY) or (bd and bd.cooldownTextY) or 0)
                        local AK2 = EllesmereUI.AuraKit
                        local fmt = AK2 and AK2.GetDurationFormatter and AK2.GetDurationFormatter()
                        -- 68914 schema key (textFormatter); BuildDurationTextOpts
                        -- when available, bare table fallback otherwise.
                        local opts
                        if AK2 and AK2.BuildDurationTextOpts then
                            opts = AK2.BuildDurationTextOpts(fmt)
                        else
                            opts = { textFormatter = fmt }
                        end
                        if AK2 and AK2.SetDurationTextSafe then
                            AK2.SetDurationTextSafe(button, fs, opts)
                        else
                            button:SetDurationText(fs, opts)
                        end
                    end)
                    if not okFS then st.fsErr = errFS end
                end
                button:SetIcon(tex)
                button:SetDurationCooldown(cd)
                st.btn, st.cd = button, cd
            end,
        })
        AK.FinishContainer(container, "player")
        st.container = container
        st.built = true
    end

    local function EnsureBuilt(rule)
        local st = St(rule)
        if st.built or st.queued then return end
        local AK = EllesmereUI.AuraKit
        if not (AK and AK.QueueBuildJob) then return end
        st.queued = true
        AK.QueueBuildJob(function()
            st.queued = nil
            Build(rule, st)
            if st.armed then FA121.Rescan() end
        end, "cdm:fa121-shell")
    end

    function FA121.Rescan()
        for rule, st in pairs(FA121.byRule) do
            if st.armed then
                -- A build that bailed (icon not yet created) retries here;
                -- EnsureBuilt's queued flag dedupes in-flight jobs.
                if not st.built then EnsureBuilt(rule) end
                ApplyRule(rule, FA121_WIN)
            end
        end
    end

    local function AnyArmed()
        for _, st in pairs(FA121.byRule) do
            if st.armed then return true end
        end
        return false
    end

    -- Rearm integration: BeginSweep marks every entry unwanted, Want re-marks
    -- (and builds) the rules the new spec keeps, EndSweep parks the rest and
    -- re-arms the wanted ones. The delayed rescan mirrors InitialStamp's 3s
    -- login retry, which never covers slot rules (they are not in _rules).
    function FA121.BeginSweep()
        for _, st in pairs(FA121.byRule) do st.armed = nil end
    end

    function FA121.Want(rule)
        local st = St(rule)
        st.armed = true
        EnsureBuilt(rule)
    end

    function FA121.EndSweep()
        for rule, st in pairs(FA121.byRule) do
            if not st.armed then
                ApplyRule(rule, nil)
                if st.proxy then st.proxy:Hide() end
                st.o, st.iconFrame = nil, nil
            end
        end
        if AnyArmed() then
            FA121.Rescan()
            if C_Timer then
                C_Timer.After(3, FA121.Rescan)
                C_Timer.After(8, FA121.Rescan)
            end
        end
    end

    -- Login/zone robustness: CDM icon frames can materialize AFTER the last
    -- rearm's rescans (deferred reanchor queues) -- a missed attach leaves
    -- the proxy parked and nothing renders all session (the field-observed
    -- working/dark flip-flop across identical reloads). World entry re-scans
    -- with staggered retries; Rescan is idempotent and armed-guarded, so
    -- quiet sessions cost three no-op walks of a one-entry table.
    local pew = CreateFrame("Frame")
    pew:RegisterEvent("PLAYER_ENTERING_WORLD")
    pew:SetScript("OnEvent", function()
        FA121.Rescan()
        if C_Timer then
            C_Timer.After(3, FA121.Rescan)
            C_Timer.After(8, FA121.Rescan)
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Expiry ticker (self-hides when idle).
-- ---------------------------------------------------------------------------
EnsureTicker = function()
    if not _ticker then
        _ticker = CreateFrame("Frame")
        _ticker:Hide()
        _ticker._acc = 0
        _ticker:SetScript("OnUpdate", function(self, elapsed)
            self._acc = self._acc + elapsed
            if self._acc < 0.1 then return end
            self._acc = 0
            local now = GetTime()
            local anyOpen = false
            for i = 1, #_rules do
                local rule = _rules[i]
                local win = _windows[rule]
                if win then
                    if now >= win.expiry then CloseWindow(rule)
                    else anyOpen = true end
                end
            end
            if not anyOpen then self:Hide() end
        end)
    end
    _ticker:Show()
end

OpenWindow = function(rule, win)
    _windows[rule] = win
    ApplyRule(rule, win)
    EnsureTicker()
end

CloseWindow = function(rule)
    _windows[rule] = nil
    ApplyRule(rule, nil)
end

CloseAll = function()
    for i = 1, #_rules do
        local rule = _rules[i]
        if _windows[rule] ~= nil then
            _windows[rule] = nil
            ApplyRule(rule, nil)
        end
    end
    if _ticker then _ticker:Hide() end
end

CastWindow = function(rule)
    local now = GetTime()
    local dur = rule.duration or 0
    if dur <= 0 then return nil end
    return { start = now, dur = dur, expiry = now + dur }
end

-- ---------------------------------------------------------------------------
--  Trigger evaluators
-- ---------------------------------------------------------------------------
OpenFromAura = function(rule)
    local aura = GetPlayerAuraBySpellID and GetPlayerAuraBySpellID(rule.auraSpellID)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
        local expiry = aura.expirationTime
        local dur = aura.duration
        if not dur or dur <= 0 then dur = rule.duration or (expiry - GetTime()) end
        OpenWindow(rule, { start = expiry - dur, dur = dur, expiry = expiry })
    elseif _windows[rule] ~= nil then
        CloseWindow(rule)
    end
end

EvalCustom = function(rule)
    _api.now           = GetTime()
    _api.lastCast      = _lastCast
    _api.GetPlayerAura = GetPlayerAuraBySpellID
    local ok, r = pcall(rule.trigger, _api)
    if not ok then return end
    local now = GetTime()
    local win
    if r == true then
        local dur = rule.duration or 0
        if dur > 0 then win = { start = now, dur = dur, expiry = now + dur } end
    elseif type(r) == "number" and r > now then
        local dur = rule.duration or (r - now)
        win = { start = r - dur, dur = dur, expiry = r }
    end
    if win then OpenWindow(rule, win)
    elseif _windows[rule] ~= nil then CloseWindow(rule) end
end

InitialStamp = function()
    for i = 1, #_auraRules do OpenFromAura(_auraRules[i]) end
    for i = 1, #_customRules do EvalCustom(_customRules[i]) end
end

OnEvent = function(self, event, unit, _, spellID)
    if event == "UNIT_AURA" then
        for i = 1, #_auraRules do OpenFromAura(_auraRules[i]) end
        for i = 1, #_customRules do EvalCustom(_customRules[i]) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        _lastCast = spellID
        local hits = spellID and _castMap[spellID]
        if hits then
            for i = 1, #hits do
                local win = CastWindow(hits[i])
                if win then OpenWindow(hits[i], win) end
            end
        end
        for i = 1, #_customRules do EvalCustom(_customRules[i]) end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- A trinket swap re-points a slot's settings to a different item; re-arm
        -- so the slot picks up the newly-equipped trinket's rule (or none).
        if unit == 13 or unit == 14 then
            ns.FakeActive_Rearm()
        end
    end
end

UpdateListeners = function()
    if _needAura or _needCast or _hasUserRules then
        if not _events then
            _events = CreateFrame("Frame")
            _events:SetScript("OnEvent", OnEvent)
        end
        if _needAura then _events:RegisterUnitEvent("UNIT_AURA", "player")
        else _events:UnregisterEvent("UNIT_AURA") end
        if _needCast then _events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else _events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
        -- Trinket swaps only matter when the player actually uses custom states.
        if _hasUserRules then _events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        else _events:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED") end
    elseif _events then
        _events:UnregisterAllEvents()
    end
end

-- Spell ids whose successful cast should open a rule's window. For positive
-- keys: the spell (and its live override). For negative keys (item presets):
-- the item's on-use spell. -13 / -14 are the equipped trinket slots.
ResolveCastSpells = function(key)
    local out = {}
    if key > 0 then
        out[#out + 1] = key
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local ov = C_SpellBook.FindSpellOverrideByID(key)
            if ov and ov > 0 and ov ~= key then out[#out + 1] = ov end
        end
    else
        local itemID
        local slot = ns.SlotIDFromKey and ns.SlotIDFromKey(key)
        if slot then
            itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
        else
            itemID = -key
        end
        if itemID and C_Item and C_Item.GetItemSpell then
            -- Pot presets: map EVERY variant's on-use spell so drinking any
            -- rank / Fleeting / (swap toggle on) other-family pot opens the
            -- window, not just the primary item. Different variants can share
            -- an on-use spell, hence the dedupe.
            local chain = ns.GetPresetPotChain and ns.GetPresetPotChain(itemID)
            if chain then
                local seen = {}
                for i = 1, #chain do
                    local _, spID = C_Item.GetItemSpell(chain[i])
                    if spID and not seen[spID] then
                        seen[spID] = true
                        out[#out + 1] = spID
                    end
                end
            else
                local _, spID = C_Item.GetItemSpell(itemID)
                if spID then out[#out + 1] = spID end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
--  Cooldown State effects (presets): hide or glow the icon based on whether the
--  ability is on cooldown. A cooldown ENDING has no reliable event, so this is a
--  throttled poll -- but only while at least one preset actually uses it.
-- ---------------------------------------------------------------------------
-- Read an item's real (non-GCD) cooldown, container query first then C_Item,
-- mirroring ProcessPresetCooldowns. Returns start,dur (dur nil / <=1.5 = ready).
-- Secret Values are dropped HERE, before any truth-test or comparison: both
-- this helper and the alt-walk in PresetOnCD compare dur ahead of PresetOnCD's
-- tail guard, and comparing a secret raises a Lua error inside the poll ticker.
local function ReadItemCD(itemID)
    local start, dur
    if C_Container and C_Container.GetItemCooldown then start, dur = C_Container.GetItemCooldown(itemID) end
    if issecretvalue and (issecretvalue(start) or issecretvalue(dur)) then start, dur = nil, nil end
    if not (start and dur and dur > 1.5) and C_Item and C_Item.GetItemCooldown then
        start, dur = C_Item.GetItemCooldown(itemID)
        if issecretvalue and (issecretvalue(start) or issecretvalue(dur)) then start, dur = nil, nil end
    end
    return start, dur
end

-- itemID -> its preset's alternate item IDs. A preset (e.g. Light's Potential)
-- covers several ranks of the same consumable; the player owns one alternate and
-- the cooldown ticks on THAT id, not the primary. ProcessPresetCooldowns already
-- walks these, so PresetOnCD must too or the "CD Ready" glow never turns off.
local _presetAltMap
local function PresetAltItemIDs(itemID)
    if not _presetAltMap then
        _presetAltMap = {}
        for _, pr in ipairs(ns.CDM_ITEM_PRESETS or {}) do
            if pr.itemID and pr.altItemIDs then _presetAltMap[pr.itemID] = pr.altItemIDs end
        end
    end
    return _presetAltMap[itemID]
end

-- Unified "is this preset on a real (non-GCD) cooldown right now?" read.
-- Trinkets/items read the ITEM cooldown (its on-use spell can have a shorter
-- cooldown that would fire the ready edge early). Bail on nil / Secret Values.
PresetOnCD = function(key)
    local now = GetTime()
    if key > 0 then
        -- A transform's real CD ticks on the override ID (e.g. Rushing Wind
        -- Kick over Rising Sun Kick); the base-ID query reads not-on-CD
        -- through that whole CD.
        local effKey = key
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local ov = C_SpellBook.FindSpellOverrideByID(key)
            if ov and ov > 0 and ov ~= key then effKey = ov end
        end
        local ci = C_Spell and C_Spell.GetSpellCooldown
            and (C_Spell.GetSpellCooldown(effKey) or C_Spell.GetSpellCooldown(key))
        return (ci and ci.isActive and not ci.isOnGCD) or false
    end

    local start, dur, enable
    local invSlot = ns.SlotIDFromKey and ns.SlotIDFromKey(key)
    if invSlot then
        if GetInventoryItemCooldown then start, dur, enable = GetInventoryItemCooldown("player", invSlot) end
    else
        local itemID = -key
        -- Pot presets walk the swap-aware variant chain (partner family
        -- included while the toggle is on) -- only the owned/used id reports
        -- the shared potion cooldown. Everything else keeps the legacy
        -- primary-then-alts walk.
        local chain = ns.GetPresetPotChain and ns.GetPresetPotChain(itemID)
        if chain then
            for i = 1, #chain do
                start, dur = ReadItemCD(chain[i])
                if start and dur and dur > 1.5 then break end
            end
        else
            start, dur = ReadItemCD(itemID)
            -- The primary id often reads ready because the player owns one of the
            -- preset's alternates and the cooldown ticks on THAT id -- walk them,
            -- matching ProcessPresetCooldowns, so the glow can turn off.
            if not (start and dur and dur > 1.5) then
                local alts = PresetAltItemIDs(itemID)
                if alts then
                    for i = 1, #alts do
                        start, dur = ReadItemCD(alts[i])
                        if start and dur and dur > 1.5 then break end
                    end
                end
            end
        end
    end
    if start == nil or dur == nil then return false end
    if issecretvalue and (issecretvalue(start) or issecretvalue(dur)
        or (enable ~= nil and issecretvalue(enable))) then return false end
    if enable ~= nil and enable ~= 1 then return false end
    return (dur > 1.5 and now < start + dur) or false
end

-- Normal (shown) alpha for a frame, from its bar's opacity (out-of-combat
-- fade folded in via EffectiveBarAlpha so restores don't clobber the fade).
-- Overflow-diverted frames render inside the target bar, so their restore
-- alpha follows that bar's opacity (same source the visibility/layout
-- passes use), not the identity bar's.
local function FrameBaseAlpha(fc)
    -- IconShownAlpha = EffectiveBarAlpha of the painted bar, forced to 0
    -- while that bar is visibility-hidden -- a restore here must never
    -- resurrect an icon the visibility engine has hidden.
    return ns.IconShownAlpha(fc)
end

-- cas is the rule's styling entry (passed in so a trinket, whose frame key is a
-- slot, still gets the per-item glow colour). Marks the frame "touched" so the
-- restore pass below can find it even after the trinket has been swapped out.
ApplyCdState = function(frame, fc, cas, eff, onCD)
    local fd = ns._hookFrameData and ns._hookFrameData[frame]
    if fd then fd._presetCdTouched = true end
    if eff == "hiddenOnCD" or eff == "hiddenReady"
       or eff == "hiddenOnCDShift" or eff == "hiddenReadyShift" then
        local isShift = (eff == "hiddenOnCDShift" or eff == "hiddenReadyShift")
        local hide
        if eff == "hiddenOnCD" or eff == "hiddenOnCDShift" then
            hide = onCD
        else
            hide = not onCD
        end
        frame:SetAlpha(hide and 0 or FrameBaseAlpha(fc))
        -- Set the SAME flag the layout / visibility / refresh code already honors,
        -- so a relayout (mount, dismount, settings change) keeps it hidden instead
        -- of flashing it visible until the next tick.
        fc._cdStateHidden = hide or false
        -- Shift variants also maintain the bar-relayout flag (only relayouts
        -- on an actual transition; steady-state calls return immediately).
        if ns.SetCdStateShiftHidden then
            ns.SetCdStateShiftHidden(fc, isShift and hide or false)
        end
        return
    end
    if eff == "lowerAlphaOnCD" then
        -- Identical to hiddenOnCD but with a customizable opacity instead of 0.
        -- Reuse the _cdStateHidden flag as "cd-state owns this alpha" so a relayout
        -- keeps the lowered value instead of flashing back to full opacity.
        -- A visibility-hidden bar (base 0) stays at 0 in both states.
        local faBase = FrameBaseAlpha(fc)
        frame:SetAlpha(faBase == 0 and 0
            or (onCD and ((cas and cas.cdStateLowerAlpha) or 0.5) or faBase))
        fc._cdStateHidden = onCD or false
        if ns.SetCdStateShiftHidden then ns.SetCdStateShiftHidden(fc, false) end
        return
    end
    -- Glow modes: glow while the ability is READY (off cooldown). Not a hide.
    fc._cdStateHidden = false
    if ns.SetCdStateShiftHidden then ns.SetCdStateShiftHidden(fc, false) end
    local glow = fd and fd.glowOverlay
    if not glow then return end
    if not onCD then
        if not fd._presetCdGlowOn then
            local gr, gg, gb = ns.ResolveGlowColor and ns.ResolveGlowColor(cas or {})
            ns.StartNativeGlow(glow, eff == "pixelGlowReady" and 1 or 3, gr or 1, gg or 1, gb or 1)
            fd._presetCdGlowOn = true
        end
    elseif fd._presetCdGlowOn then
        ns.StopNativeGlow(glow)
        fd._presetCdGlowOn = false
    end
end

-- Clear cd-state visuals on every icon we have touched (before a re-arm, so a
-- removed effect -- or a trinket swapped out of a slot -- un-hides / un-glows).
RestoreAllCdState = function()
    local icons = ns.cdmBarIcons
    local FCt = ns._ecmeFC
    if not icons or not FCt then return end
    for _, list in pairs(icons) do
        for i = 1, #list do
            local f = list[i]
            local fd = ns._hookFrameData and ns._hookFrameData[f]
            if fd and fd._presetCdTouched then
                local fc = FCt[f]
                f:SetAlpha(FrameBaseAlpha(fc))
                if fc then
                    fc._cdStateHidden = false
                    if ns.SetCdStateShiftHidden then ns.SetCdStateShiftHidden(fc, false) end
                end
                if fd._presetCdGlowOn and fd.glowOverlay then
                    ns.StopNativeGlow(fd.glowOverlay)
                    fd._presetCdGlowOn = false
                end
                fd._presetCdTouched = nil
            end
        end
    end
end

-- One full evaluation pass. Driven by the ticker (continuous) AND called
-- synchronously at the end of a re-arm, so a settings change does not leave the
-- icon shown for a tick before the next poll re-hides it.
EvalCdStateNow = function()
    local icons = ns.cdmBarIcons
    local FCt = ns._ecmeFC
    if not icons or not FCt then return end
    for r = 1, #_cdStateRules do
        local rule = _cdStateRules[r]
        local cas = rule.cas
        local eff = cas and cas.cdStateEffect
        -- Blocking-false (per-trinket "None" over a slot-level bar apply) is
        -- render-equivalent to nil: no effect, but the sound may still be set.
        if eff == false then eff = nil end
        local soundKey = cas and cas.cdReadySoundKey
        if soundKey == "none" then soundKey = nil end
        if eff or soundKey then
            local onCD = PresetOnCD(rule.spellID)
            local sid = rule.spellID
            -- Sound only fires while the ability's icon is present on a bar.
            local hasIcon = false
            for _, list in pairs(icons) do
                for i = 1, #list do
                    local f = list[i]
                    local fc = f and FCt[f]
                    if fc and fc.spellID == sid then
                        hasIcon = true
                        if eff then ApplyCdState(f, fc, cas, eff, onCD) end
                    end
                end
            end
            -- Audio Effect on CD Ready: arm while on cooldown, fire once on the ready
            -- edge. A missing icon leaves the armed state untouched so a rebuild at
            -- cooldown-end can't swallow the edge (armed state persists by key).
            if soundKey then
                local akey = rule.srcKey or sid
                if onCD then
                    if hasIcon then _cdrArmedByKey[akey] = true end
                elseif hasIcon and _cdrArmedByKey[akey] then
                    _cdrArmedByKey[akey] = nil
                    if not (ns._cdmSoundSuppressed and ns._cdmSoundSuppressed()) then
                        local path = ns.FOCUSKICK_SOUND_PATHS and ns.FOCUSKICK_SOUND_PATHS[soundKey]
                        if path then PlaySoundFile(path, "Master") end
                    end
                end
            end
        end
    end
end

EnsureCdStateTicker = function()
    if not _cdStateTicker then
        _cdStateTicker = CreateFrame("Frame")
        _cdStateTicker:Hide()
        _cdStateTicker._acc = 0
        _cdStateTicker:SetScript("OnUpdate", function(self, elapsed)
            self._acc = self._acc + elapsed
            if self._acc < 0.12 then return end
            self._acc = 0
            EvalCdStateNow()
        end)
    end
    _cdStateTicker:Show()
end

local function MapCast(rule)
    local spells = ResolveCastSpells(rule.triggerSpellID or rule.spellID)
    for i = 1, #spells do
        local sp = spells[i]
        local list = _castMap[sp]
        if not list then list = {}; _castMap[sp] = list end
        list[#list + 1] = rule
    end
    _needCast = true
end

local function AddRule(rule)
    _rules[#_rules + 1] = rule
    local tr = rule.trigger
    if tr == "aura" then
        _auraRules[#_auraRules + 1] = rule; _needAura = true
    elseif type(tr) == "function" then
        _customRules[#_customRules + 1] = rule; _needCast = true
    else  -- "cast"
        MapCast(rule)
    end
end

-- ---------------------------------------------------------------------------
--  Re-sync a single overlay after its underlying icon was restyled.
-- ---------------------------------------------------------------------------
-- Called from RefreshCDMIconAppearance (via ApplyShapeToCDMIcon) whenever an icon
-- is re-shaped / re-bordered / re-zoomed -- including a settings change made WHILE
-- a fake-active window is open. That restyle re-textures the shared shapeMask and
-- resets the icon's border frame back to its normal level (below our overlay), so
-- without this the overlay would show the old/stale shape and the border would sit
-- hidden beneath us until the window next reopened. Re-applies our shape (new
-- mask + geometry + swipe) and forces a fresh border raise. No-op unless an
-- overlay is currently shown on this icon.
function ns.FakeActive_OnIconRestyled(iconFrame)
    local o = _overlays[iconFrame]
    if not o or not o._rule then return end           -- no overlay / no open window
    local st121 = FA121 and FA121.byRule[o._rule]
    if st121 then
        -- 12.1 slot mode: the legacy overlay is permanently dark (alpha 0 --
        -- the slot subtree renders the active state), so the alpha gate
        -- below would always skip; resync whenever the rule is armed
        -- instead (covers the pcall'd best-effort cd mirror at the tail).
        if not st121.armed then return end
    elseif o.frame:GetAlpha() == 0 then return end     -- overlay not currently shown
    local fc = ns._ecmeFC and ns._ecmeFC[iconFrame]
    local barKey = fc and fc.barKey
    local bd = barKey and ns.barDataByKey and ns.barDataByKey[barKey]
    IconTexture(iconFrame, o, o._rule)
    if ns.ApplyShapeToOverlay then ns.ApplyShapeToOverlay(iconFrame, o.icon, o.cd, bd) end
    -- Re-apply Duration Text styling too (the font/size/colour may have changed).
    if ns.StyleOverlayCooldownText then
        ns.StyleOverlayCooldownText(o.cd, bd, o._ss, iconFrame:GetScale())
    end
    -- Re-assert Reverse Swipe as well: o._ss is the live chained settings
    -- block, so a toggle made while the window is open takes effect on this
    -- restyle pass instead of waiting for the next window.
    if ns._cdmAnyReverseSwipe then
        o.cd:SetReverse((o._ss and o._ss.reverseSwipe) and true or false)
    end
    -- The restyle reset the border to its normal level; clear the stale flag so
    -- RaiseOverlayBorders re-captures that level and lifts it above us again.
    o._brdRaised = false
    RaiseOverlayBorders(iconFrame, o, bd)
    -- Re-feed the active glow / border the underlying shape + border refs, then
    -- re-apply so a glow-colour / active-border edit takes effect live (the glow
    -- only restarts if its style/colour actually changed). ApplyShapeToCDMIcon
    -- just reset the shape border to its configured colour, so drop the stale
    -- saved colour first to re-capture it for restore-on-falloff.
    local ufd  = ns._hookFrameData and ns._hookFrameData[iconFrame]
    local uifc = ns._ecmeFC and ns._ecmeFC[iconFrame]
    o.borderFrame = (ufd and ufd.borderFrame) or nil
    local gfc = ns.FC and ns.FC(o.frame)
    if gfc then
        gfc.shapeApplied = (uifc and uifc.shapeApplied) or nil
        gfc.shapeName    = (uifc and uifc.shapeName) or nil
        gfc.shapeMask    = (uifc and uifc.shapeMask) or nil
        gfc.shapeBorder  = (uifc and uifc.shapeBorder) or nil
    end
    if o._ss and ns.ApplyActiveOverlays then
        o._sbColorSaved = false
        ns.ApplyActiveOverlays(o.frame, o, o._ss, true, bd)
    end
    -- 12.1 slot mode: the live swipe is the slot-child cooldown, not o.cd.
    -- Best-effort mirror only: the engine binding owns that region (field
    -- lesson, 68824), so these are pcall'd and skipped once known-denied.
    if st121 and st121.cd and not st121.cdLocked then
        if ns.StyleOverlayCooldownText then
            pcall(ns.StyleOverlayCooldownText, st121.cd, bd, o._ss, iconFrame:GetScale())
        end
        if ns._cdmAnyReverseSwipe then
            pcall(st121.cd.SetReverse, st121.cd, (o._ss and o._ss.reverseSwipe) and true or false)
        end
        if ns.ApplyShapeToOverlay then
            pcall(ns.ApplyShapeToOverlay, iconFrame, o.icon, st121.cd, bd)
        end
    end
end

-- ---------------------------------------------------------------------------
--  Re-arm for the current class + spec + profile. Called after every rebuild.
-- ---------------------------------------------------------------------------
function ns.FakeActive_Rearm()
    RestoreAllCdState()  -- un-hide / un-glow icons from the outgoing rule set
    CloseAll()
    wipe(_rules); wipe(_auraRules); wipe(_customRules); wipe(_castMap); wipe(_cdStateRules)
    _needAura, _needCast, _armed, _hasUserRules = false, false, false, false
    if FA121 then FA121.BeginSweep() end

    -- 1. Built-in rules (class/spec gated).
    local _, classFile = UnitClass("player")
    local specIdx = GetSpecialization and GetSpecialization() or nil
    for i = 1, #FAKE_ACTIVE_RULES do
        local rule = FAKE_ACTIVE_RULES[i]
        if (not rule.class or rule.class == classFile)
           and (not rule.spec or rule.spec == specIdx) then
            if FA121 and rule.trigger == "aura" then
                -- 12.1: aura rules ride the engine slot, never the numeric
                -- GetPlayerAuraBySpellID window (dead for secret-flagged
                -- spells like Ebon Might since build 68824).
                FA121.Want(rule)
            else
                AddRule(rule)
            end
        end
    end
    if FA121 then FA121.EndSweep() end

    -- 2. User rules: profile-level custom active states, keyed by spell. These
    --    travel with the spell across every bar and spec, so no barKey scope --
    --    the overlay shows on whichever bar currently hosts the icon.
    -- A spell may have a cast-triggered active overlay (duration), a continuous
    -- cooldown-state effect (cdStateEffect), or both.
    local store = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
    if store then
        -- Shared rule constructor. matchKey is the icon-identity key live frames
        -- carry (fc.spellID): positive spell id, -itemID item preset, or a trinket
        -- slot (-13/-14). srcKey keys the persistent CD-ready-sound armed state.
        -- cas is the styling entry the rule reads -- for trinket slots a chained
        -- item-over-slot view (see below).
        local function AddUserRule(matchKey, srcKey, cas)
            local hasDur = (cas.duration or 0) > 0
            -- Explicit false = a per-trinket "None" blocking the slot's bar-apply
            -- value from showing through; render-equivalent to nil.
            local eff = cas.cdStateEffect
            if eff == false then eff = nil end
            local hasCd = eff ~= nil
            local hasSound = cas.cdReadySoundKey ~= nil and cas.cdReadySoundKey ~= "none"
            if not (hasDur or hasCd or hasSound) then return end
            local rule = { spellID = matchKey, srcKey = srcKey, cas = cas, user = true }
            _rules[#_rules + 1] = rule
            _hasUserRules = true
            if hasDur then
                rule.trigger  = "cast"
                rule.duration = cas.duration
                MapCast(rule)
            end
            if hasCd or hasSound then
                -- Both effects ride the same cooldown poll (EvalCdStateNow).
                _cdStateRules[#_cdStateRules + 1] = rule
            end
        end
        local eq13 = GetInventoryItemID and GetInventoryItemID("player", 13) or nil
        local eq14 = GetInventoryItemID and GetInventoryItemID("player", 14) or nil
        for key, cas in pairs(store) do
            -- Skip trinket-SLOT keys (dedicated pass below) and the EQUIPPED
            -- trinkets' item keys (they ride their slot's rule as the own-value
            -- layer -- a second rule here would fight it on the same frame). An
            -- UNEQUIPPED trinket's item entry still becomes a rule; its key
            -- matches no frame, which is correct (dormant until equipped).
            if type(cas) == "table" and key ~= -13 and key ~= -14
               and not (eq13 and key == -eq13) and not (eq14 and key == -eq14) then
                AddUserRule(key, key, cas)
            end
        end
        -- Trinket slots: ONE rule per slot. The slot entry (-13/-14) is the
        -- "Apply to Bar" stamp -- slot-keyed so a bar application covers
        -- whatever trinket is equipped, before and after swaps. The equipped
        -- item's own entry (per-spell menu settings) chains over it per key,
        -- so per-trinket choices win. Cast + cooldown already resolve the
        -- slot's CURRENT item via ResolveCastSpells / PresetOnCD.
        for slot = 13, 14 do
            local slotE = store[-slot]
            if type(slotE) ~= "table" then slotE = nil end
            local itemID = (slot == 13) and eq13 or eq14
            local itemE = itemID and store[-itemID] or nil
            if type(itemE) ~= "table" then itemE = nil end
            local eff = itemE or slotE
            if eff then
                if itemE and ns.ChainSettings then ns.ChainSettings(itemE, slotE) end
                AddUserRule(-slot, -slot, eff)
            end
        end
    end

    _armed = #_rules > 0
    UpdateListeners()
    if #_cdStateRules > 0 then
        EnsureCdStateTicker()
        EvalCdStateNow()  -- apply now so the rebuild doesn't flash the icon visible
    elseif _cdStateTicker then
        _cdStateTicker:Hide()
    end

    if not _armed then return end
    InitialStamp()
    if C_Timer then
        C_Timer.After(3, function()
            if not _armed then return end
            InitialStamp()
            EvalCdStateNow()  -- frames may not have existed at re-arm (login)
        end)
    end
end

-- Re-arm on every CDM full rebuild, kept out of the (large) rebuild function.
local _origFullCDMRebuild = ns.FullCDMRebuild
ns.FullCDMRebuild = function(reason)
    -- Rebuilds read transient cooldown states while re-rendering; open the
    -- sound settle window first so re-primes can't false-arm ready sounds.
    if ns._cdmBumpSoundSettle then ns._cdmBumpSoundSettle() end
    -- Rebuilds are also the moments the tracked buff catalog can change
    -- (talents/spec/settings) -- let the next reanchor reconcile the buff
    -- display order.
    ns._cdmBuffOrderDirty = true
    if _origFullCDMRebuild then _origFullCDMRebuild(reason) end
    ns.FakeActive_Rearm()
end

-- Debug toggle: /run EllesmereUI.FakeActiveDebug()
if EllesmereUI then
    function EllesmereUI.FakeActiveDebug()
        ns._fakeActiveDebug = not ns._fakeActiveDebug
        print(("|cff0cd29fEUI FakeActive|r debug %s | armed=%s rules=%d"):format(
            ns._fakeActiveDebug and "ON" or "off", tostring(_armed), #_rules))
    end
end
