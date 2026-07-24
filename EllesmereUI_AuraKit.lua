-- EllesmereUI_AuraKit.lua
-- Shared engine for the 12.1 aura container system. Every EllesmereUI module
-- consumes aura displays through this file; modules never call AddAuraGroup /
-- AddAuraSlot / button setters directly. Centralizing this gives us one place
-- for filter-string normalization (exact-string dedup inside the engine),
-- decoration presets, the restyle registry, and combat-safe creation.

local AK = {}
EllesmereUI.AuraKit = AK

local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue or function() return false end

------------------------------------------------------------------------------
-- Filter normalization
--
-- The engine batches aura parsing per container by EXACT filter string. Two
-- groups only share one scan if their strings are byte-identical, so every
-- filter in the suite is built through AK.Filter to guarantee one canonical
-- token order: base polarity first (HELPFUL/HARMFUL), then the remaining
-- tokens sorted alphabetically (negated tokens sort by their bare name).
------------------------------------------------------------------------------

local filterCache = {}

local function TokenSortKey(token)
    if token:sub(1, 1) == "!" then
        return token:sub(2) .. "!" -- negation sorts directly after its bare token
    end
    return token
end

function AK.Filter(...)
    local key = table.concat({ ... }, "|")
    local cached = filterCache[key]
    if cached then return cached end

    local base, rest = nil, {}
    for i = 1, select("#", ...) do
        local token = select(i, ...)
        if token == "HELPFUL" or token == "HARMFUL" then
            base = token
        else
            rest[#rest + 1] = token
        end
    end
    table.sort(rest, function(a, b) return TokenSortKey(a) < TokenSortKey(b) end)

    local out
    if base and #rest > 0 then
        out = base .. "|" .. table.concat(rest, "|")
    else
        out = base or table.concat(rest, "|")
    end

    filterCache[key] = out
    return out
end

------------------------------------------------------------------------------
-- Duration text formatters
--
-- SetDurationText accepts a NumericFormatter object evaluated engine-side
-- against the (possibly secret) remaining duration. The suite's duration
-- text has always been bare seconds under a minute ("10"), then floored
-- "2m"/"1h"/"1d" with no space -- a SecondsFormatter cannot drop the unit
-- on seconds, so this is a banded NumericRuleFormatter. Seconds round UP so
-- the text never reads 0 while time remains; larger units floor, matching
-- the legacy text exactly at the 60s boundary ("1m" at 60, "59" at 59).
------------------------------------------------------------------------------

local durationFormatter

local function BuildRuleDurationFormatter()
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Up = Enum.NumericRuleFormatRounding.Up
    local Down = Enum.NumericRuleFormatRounding.Down
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    -- Schema per the field-proven CDM threshold formatter: step/rounding
    -- live at the BREAKPOINT level; components carry only the divisor.
    -- (The original nested step/rounding inside components -- silently
    -- rejected or default-rounded depending on validation strictness.)
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0,     format = "%d",  step = 1, rounding = Up },
        { threshold = 60,    format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600,  format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
        { threshold = 86400, format = "%dd", step = 1, rounding = Down, components = { { div = 86400 } } },
    })
    if not ok then return nil end
    return formatter
end

-- Fallback if the rule formatter is unavailable/rejected: compact
-- one-letter units ("10s"/"2m") -- closest a SecondsFormatter gets.
local function BuildSecondsDurationFormatter()
    local curve = C_CurveUtil.CreateCurve()
    curve:AddPoint(61,        Enum.SecondsFormatterInterval.Minutes)
    curve:AddPoint(3601,      Enum.SecondsFormatterInterval.Hours)
    curve:AddPoint(86401,     Enum.SecondsFormatterInterval.Days)

    local formatter = C_StringUtil.CreateSecondsFormatter()
    formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
    formatter:SetMaxIntervalCurve(curve)
    formatter:SetDesiredUnitCount(1)
    if formatter.SetStripIntervalWhitespace and Enum.SecondsFormatterIntervalWhitespace then
        formatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)
    end
    return formatter
end

function AK.GetDurationFormatter()
    if not durationFormatter then
        durationFormatter = BuildRuleDurationFormatter() or BuildSecondsDurationFormatter()
    end
    return durationFormatter
end

------------------------------------------------------------------------------
-- Styles and the button registry
--
-- A style describes how a button is decorated. Buttons are Blizzard-owned
-- AuraButton frames, so per-button state lives in an external weak-keyed
-- table (never written onto the button itself). Regions we create are
-- children of the button, anchored inside it; that is a hard engine rule.
------------------------------------------------------------------------------

AK.styles = {}

-- Per-button region refs: bd[button] = { icon, cooldown, stackCarrier, stack,
-- duration, borderHost, styleKey }
local bd = setmetatable({}, { __mode = "k" })

-- styleButtons[styleKey][button] = true, weak keys, for restyling.
local styleButtons = {}

local function GetStyleSet(styleKey)
    local set = styleButtons[styleKey]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        styleButtons[styleKey] = set
    end
    return set
end

-- Style keys whose apply hit a denied button call while auras were secret.
-- 12.1 (build 68745+): engine aura buttons carry the
-- DenyTaintedAccessWhenAurasAreSecret access restriction, applied by the
-- engine immediately AFTER initializeFrame returns -- so creation-window
-- decoration is always legal, but post-creation reads/writes on the BUTTON
-- object from addon code are rejected in secret contexts (our own child
-- regions stay writable). Deferred keys re-queue when the restriction
-- lifts; see the lift watcher below the restyle worker.
local deferredRestyles = {}

local function ApplyStyleToRegions(button, style)
    local d = bd[button]
    if not d then return end

    -- The engine's flow layout only ANCHORS group buttons; their physical size
    -- is entirely ours to set (group layout elementWidth/Height feeds the flow
    -- math only). An unsized button renders nothing. SetSize on aura buttons
    -- is an engine-wrapped call, so restyles skip it when unchanged.
    local w = style.width or 32
    local h = style.height or style.width or 32
    if d.appliedW ~= w or d.appliedH ~= h then
        -- Stamp AFTER the call: SetSize on the button is denied while auras
        -- are secret, and a pre-stamped failure would make the
        -- restriction-lift retry skip the resize as "unchanged".
        button:SetSize(w, h)
        d.appliedW, d.appliedH = w, h
    end

    if d.icon then
        if style.texCoord then
            d.icon:SetTexCoord(style.texCoord[1], style.texCoord[2], style.texCoord[3], style.texCoord[4])
        elseif style.iconCrop then
            local z = style.iconZoom or 0.07
            d.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            d.icon:SetTexCoord(0, 1, 0, 1)
        end
    end

    if d.cooldown then
        d.cooldown:SetReverse(style.cooldownReverse ~= false)
        d.cooldown:SetDrawEdge(style.cooldownDrawEdge == true)
        d.cooldown:SetHideCountdownNumbers(true) -- duration text comes from the binding, not the swipe
        d.cooldown:SetShown(style.hideSwipe ~= true)
    end

    -- Modules with their own text pipeline (fonts, anchors, outline rules) set
    -- noDefaultFonts and do all text styling in style.applyExtra instead.
    -- Text anchors are change-guarded (stamp AFTER the calls): SetPoint
    -- with the button as the relative frame is policed by the 12.1 button
    -- access restriction while auras are secret, and unchanged anchors must
    -- make zero button-involving calls so restyles stay live in-instance.
    if d.stack and not style.noDefaultFonts then
        local f = style.stackFont or STANDARD_TEXT_FONT
        d.stack:SetFont(f, style.stackFontSize or 12, style.stackFontFlags or "OUTLINE")
        local sp = style.stackPoint or "BOTTOMRIGHT"
        local sKey = sp .. "|" .. (style.stackX or 2) .. "|" .. (style.stackY or -2)
        if d.akStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(sp, button, sp, style.stackX or 2, style.stackY or -2)
            d.akStackAnchor = sKey
        end
        local c = style.stackColor
        if c then d.stack:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end

    if d.duration then
        if not style.noDefaultFonts then
            local f = style.durationFont or STANDARD_TEXT_FONT
            d.duration:SetFont(f, style.durationFontSize or 11, style.durationFontFlags or "OUTLINE")
            local dp = style.durationPoint or "TOP"
            local drp = style.durationRelPoint or "BOTTOM"
            local aKey = dp .. "|" .. drp .. "|" .. (style.durationX or 0) .. "|" .. (style.durationY or -2)
            if d.akDurAnchor ~= aKey then
                d.duration:ClearAllPoints()
                d.duration:SetPoint(dp, button, drp, style.durationX or 0, style.durationY or -2)
                d.akDurAnchor = aKey
            end
        end
        -- The engine keeps writing the text either way; visibility is ours.
        d.duration:SetShown(not style.hideDurationText)
    end

    if d.borderHost then
        local PP = EllesmereUI.PP
        local b = style.border
        if PP and b then
            if b.texture and EllesmereUI.ApplyBorderStyle then
                -- Aura buttons can expose restricted geometry. Give the owned
                -- border host an explicit public size (change-guarded because
                -- anchoring to the aura button is denied while restricted).
                local borderRect = (style.width or 18) .. "|" .. (style.height or style.width or 18)
                if d.akBorderRect ~= borderRect then
                    d.borderHost:ClearAllPoints()
                    d.borderHost:SetPoint("CENTER", button, "CENTER")
                    d.borderHost:SetSize(style.width or 18, style.height or style.width or 18)
                    d.akBorderRect = borderRect
                end
                if b.behindUnitFrame then
                    d.borderHost:SetFrameLevel(math.max(0, (b.unitFrameLevel or 1) - 1))
                else
                    d.borderHost:SetFrameLevel(b.behind
                        and math.max(0, button:GetFrameLevel() - 1)
                        or (d.cooldown:GetFrameLevel() + 1))
                end
                EllesmereUI.ApplySecretSafeBorderStyle(d.borderHost, d, b.size or 1,
                    b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 1,
                    b.texture or "solid", b.offsetX, b.offsetY, b.shiftX, b.shiftY,
                    "unitframes", b.size or 1)
                d.borderMade = true
            elseif d.borderMade then
                PP.UpdateBorder(d.borderHost, b.size or 1, b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 1)
            else
                PP.CreateBorder(d.borderHost, b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 1,
                    b.size or 1, "OVERLAY", 7)
                d.borderMade = true
            end
            d.borderHost:Show()
        else
            d.borderHost:Hide()
        end
    end

    -- Engine dispel-type border (style.dispelBorder): one texture the engine
    -- shows only on typed (dispellable) auras and tints per dispel type --
    -- per-aura dispel data is secret, so show/hide and color are ENGINE
    -- decisions. The Color style never assigns a texture file, only vertex-
    -- tints: the ring ART is entirely ours (media/textures/square-ring.png,
    -- a flat white band flush to a 64px canvas, 16 texels thick), registered
    -- purely as a tint target, and the user's dispel palette rides in via
    -- customDispelColorMap (68824). The ring lives on a dedicated holder one
    -- frame level over the static border host so the recolor always draws ON
    -- TOP of the border strips; the text carrier sits one more above.
    -- Registration follows the static border: no border configured, no
    -- dispel recolor (live parity). 68914 reworked the border API into the
    -- dispel-type texture system: the tint-our-own-art style is now
    -- PreserveAsset on Enum.CustomAuraButtonDispelTypeTextureStyle (the old
    -- CustomAuraButtonBorderStyle enum is deleted; its Color value is the
    -- ancestor, kept as a fallback for stale PTR builds). The style MUST
    -- resolve: registering without it takes the BorderWithIcon default,
    -- which stamps Blizzard atlas art over our ring texture.
    local dispelTint = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
    if dispelTint == nil then
        local legacy = (Enum and Enum.CustomAuraButtonBorderStyle) or AuraButtonBorderStyle
        dispelTint = legacy and legacy.Color
    end
    if style.dispelBorder and not d.dispelBorder and d.dispelHolder
        and (button.AddDispelTypeTexture or button.SetAuraBorder) and dispelTint ~= nil then
        d.dispelBorder = d.dispelHolder:CreateTexture(nil, "OVERLAY")
        d.dispelBorder:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\square-ring.png")
        if d.dispelBorder.SetSnapToPixelGrid then
            d.dispelBorder:SetSnapToPixelGrid(false)
            d.dispelBorder:SetTexelSnappingBias(0)
        end
        d.dispelBorder:SetAllPoints(d.dispelHolder)
    end
    if d.dispelBorder then
        -- Level re-assert (change-guarded): a style can move the border
        -- host's level; the ring stays THREE levels above it (PP strip
        -- container at +1, DM fx border-override container at +2 -- the
        -- dispel recolor always wins over every border), the text carrier
        -- one more. All owned frames -- legal under restriction.
        local bl = d.borderHost and d.borderHost:GetFrameLevel() or 0
        if d.akDispelLvl ~= bl then
            d.dispelHolder:SetFrameLevel(bl + 3)
            if d.stackCarrier then d.stackCarrier:SetFrameLevel(bl + 4) end
            d.akDispelLvl = bl
        end
        -- Physical-pixel thickness by SOURCE CROPPING, never stretching:
        -- the art is a flush band of B = 16 texels on a C = 64 canvas
        -- (B/C = 1/4). Shrinking the sampled window inward by fraction a
        -- per side leaves (B - C*a) band texels over a C*(1-2a) span, so
        -- the rendered thickness at drawn size s is
        --   t = s*(B - C*a) / (C*(1-2a))   =>   a = (s - 4t) / (4*(s - 2t)).
        -- t converts the user's physical-pixel setting into this frame's
        -- units via the holder's effective scale (our frame -- readable);
        -- s is the style size, never a rect read (button rects are
        -- restricted). The cropped band stays solid at any icon size.
        local sw = style.width or 18
        local px = style.dispelBorderPx or 2
        local t = px
        local eff = d.dispelHolder:GetEffectiveScale()
        if eff and eff > 0 then
            local PPx = EllesmereUI.PP
            t = px * ((PPx and PPx.perfect) or 0.75) / eff
        end
        local a = 0
        if sw > 4 * t then a = (sw - 4 * t) / (4 * (sw - 2 * t)) end
        local cropKey = string.format("%s|%.4f", tostring(sw), a)
        if d.akDispelCrop ~= cropKey then
            d.dispelBorder:SetTexCoord(a, 1 - a, a, 1 - a)
            d.akDispelCrop = cropKey
        end
        -- Registration follows the static border AND a nonzero thickness
        -- (0 = the user disabled the dispel recolor outright).
        local want = (style.dispelBorder and style.border
            and (style.dispelBorderPx or 2) > 0) and true or false
        local mapFP = style.dispelColorFP or ""
        if d.dispelBorderOn ~= want or (want and d.akDispelMapFP ~= mapFP) then
            -- Stamp only on SUCCESS: these are button calls, denied while
            -- auras are secret; a pre-stamped failure would strand the
            -- registration in the wrong state after the restriction lifts.
            -- A restricted failure defers this style key to the lift drain.
            -- AddDispelTypeTexture APPENDS (unlike the old set-semantics
            -- alias), so a re-registration must clear first -- and if the
            -- clear is denied, the add is skipped too, or the button would
            -- accumulate duplicate entries.
            if want then
                local proceed = true
                if d.dispelBorderOn then
                    local clearFn = button.ClearDispelTypeTextures or button.ClearAuraBorder
                    proceed = (clearFn and pcall(clearFn, button)) and true or false
                end
                local addFn = button.AddDispelTypeTexture or button.SetAuraBorder
                if proceed and pcall(addFn, button, d.dispelBorder,
                    { style = dispelTint, showWhenHarmful = true, showWhenHelpful = false,
                      customDispelColorMap = style.dispelColorMap }) then
                    d.dispelBorderOn = want
                    d.akDispelMapFP = mapFP
                elseif d.styleKey and AK.AurasRestricted() then
                    deferredRestyles[d.styleKey] = true
                end
            else
                local clearFn = button.ClearDispelTypeTextures or button.ClearAuraBorder
                if clearFn and pcall(clearFn, button) then
                    d.dispelBorder:Hide()
                    d.dispelBorderOn = want
                elseif d.styleKey and AK.AurasRestricted() then
                    deferredRestyles[d.styleKey] = true
                end
            end
        end
    end

    -- Module-specific styling pass; runs at init and on every Restyle.
    if style.applyExtra then
        style.applyExtra(button, d, style)
    end
end

-- SetDurationText options, 68914 schema: formatter -> textFormatter,
-- textColorCurve -> textColor = { curve, property }, and binding-level knobs
-- (updateInterval, expiredText, zeroDurationText, timeModifier) no longer
-- exist as bare options -- they travel on a caller-configured
-- DurationTextBinding passed as options.binding (the engine copies it at
-- registration). The old one-arg SetTextColorCurve consumer bug is fixed
-- upstream in 68914, so color curves are live for the first time.

-- The curve property the engine recolors against; RemainingDuration is 0,
-- so resolve with an explicit nil check (never `and/or` an enum that can
-- legitimately be zero).
function AK.DurationTextColor(curve)
    if not curve then return nil end
    local e = Enum and Enum.DurationTextBindingProperty
    local prop = e and e.RemainingDuration
    if prop == nil then prop = 0 end
    return { curve = curve, property = prop }
end

-- Builds a SetDurationText options table in the 68914 schema. When a
-- binding-level knob (updateInterval) is requested, the formatter and the
-- knob are configured on a fresh binding and passed via options.binding;
-- otherwise the plain textFormatter key suffices.
function AK.BuildDurationTextOpts(formatter, colorCurve, updateInterval)
    local opts
    if updateInterval and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        local binding = C_DurationUtil.CreateDurationTextBinding()
        if formatter then binding:SetFormatter(formatter) end
        binding:SetUpdateInterval(updateInterval)
        opts = { binding = binding }
    else
        opts = { textFormatter = formatter }
    end
    if colorCurve then
        opts.textColor = AK.DurationTextColor(colorCurve)
    end
    return opts
end

-- Registration armor: an uncaught error inside SetDurationText aborts the
-- whole engine CreateFrameBatch (killing the AddAuraSlot/AddAuraGroup that
-- triggered it), so every attempt is pcall-wrapped and degrades in steps --
-- full options, then without the color binding, then bare. This is the
-- standing rule for novel engine option paths, kept even though the 68824
-- one-arg SetTextColorCurve bug this guard was born for is fixed.
-- Returns (registered, full): registered = some registration landed;
-- full = the complete option set landed. Callers that stamp-after-success
-- (BmRebindDurationCurve) key off these -- this function never throws, so
-- a denied button call under restriction must be visible in the returns.
function AK.SetDurationTextSafe(button, fontString, durationOpts)
    if pcall(button.SetDurationText, button, fontString, durationOpts) then
        return true, true
    end
    if durationOpts.textColor ~= nil then
        durationOpts.textColor = nil
        if pcall(button.SetDurationText, button, fontString, durationOpts) then
            return true, false
        end
    end
    if pcall(button.SetDurationText, button, fontString, {}) then
        return true, false
    end
    return false, false
end

-- Returns the initializeFrame callback for a style. It runs ONCE per created
-- button (buttons are pre-created in engine batches of 10, so it fires at
-- group-declare time, not per shown aura), and it receives the PUBLIC button
-- reference. All region wiring happens here.
function AK.MakeInitializer(styleKey, extra)
    return function(button)
        local style = AK.styles[styleKey] or {}
        local d = {}
        bd[button] = d
        d.styleKey = styleKey

        -- Bare mode: no standard regions at all. The button is a pure
        -- presence-driven host (engine still drives its visibility); the
        -- module builds whatever it wants in applyExtra/extra.
        if style.noRegions then
            ApplyStyleToRegions(button, style)
            GetStyleSet(styleKey)[button] = true
            if extra then extra(button, d, style) end
            return
        end

        -- Create every region first, style them, and only THEN register them
        -- with the button: each Set* registration immediately runs the engine's
        -- UpdateAuraDisplay, which SetText()s our font strings -- an unstyled
        -- FontString has no font assigned and hard-errors inside the engine.

        d.icon = button:CreateTexture(nil, "ARTWORK")
        d.icon:SetAllPoints(button)

        -- CooldownFrameTemplate supplies the swipe/edge textures; a bare
        -- Cooldown renders no swipe at all. The template carries no frame
        -- scripts, so it is aspect-safe on button children.
        d.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        d.cooldown:SetAllPoints(button)

        -- Level order above the swipe: border first (as close to the icon
        -- as possible), then the text carrier -- duration/stack text must
        -- never render behind the border strips.
        d.borderHost = CreateFrame("Frame", nil, button)
        d.borderHost:SetAllPoints(button)
        d.borderHost:SetFrameLevel(d.cooldown:GetFrameLevel() + 1)

        -- Dispel-ring holder: its own frame between the border host and the
        -- text carrier so the engine-tinted ring ALWAYS WINS over every
        -- border. +3, not +1: PP.CreateBorder parks its strips on a
        -- CONTAINER child at borderHost+1, and the DM per-filter border
        -- override's container lands at borderHost+2 -- the ring clears
        -- both. Created UNCONDITIONALLY here -- this is the only
        -- guaranteed-legal window for parenting a frame to the button, and
        -- a style can gain dispelBorder later via a settings toggle (UF)
        -- when the window is long closed.
        d.dispelHolder = CreateFrame("Frame", nil, button)
        d.dispelHolder:SetAllPoints(button)
        d.dispelHolder:SetFrameLevel(d.borderHost:GetFrameLevel() + 3)

        -- Stack and duration text ride a carrier frame above the cooldown,
        -- borders and dispel ring so none of them can cover the text.
        d.stackCarrier = CreateFrame("Frame", nil, button)
        d.stackCarrier:SetAllPoints(button)
        d.stackCarrier:SetFrameLevel(d.borderHost:GetFrameLevel() + 4)
        d.stack = d.stackCarrier:CreateFontString(nil, "OVERLAY")
        d.duration = d.stackCarrier:CreateFontString(nil, "OVERLAY")

        ApplyStyleToRegions(button, style)

        button:SetIcon(d.icon)
        button:SetDurationCooldown(d.cooldown)
        button:SetApplicationCount(d.stack, {})

        local durationOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(),
            style.durationColorCurve, style.durationUpdateInterval)
        AK.SetDurationTextSafe(button, d.duration, durationOpts)

        if style.cancelButtons then
            button:SetCancelAuraButtons(style.cancelButtons)
        end

        GetStyleSet(styleKey)[button] = true

        if extra then extra(button, d, style) end
    end
end

-- Re-applies a style to every registered button (settings changed). Geometry
-- owned by the container (element sizes, spacing, growth) is re-driven by the
-- caller through AK.ApplyContainerLayout / group setters, not here.
function AK.Restyle(styleKey)
    local style = AK.styles[styleKey]
    local set = styleButtons[styleKey]
    if not style or not set then return end
    for button in pairs(set) do
        ApplyStyleToRegions(button, style)
    end
end

-- Deferred, time-sliced restyle. Group frame pools are 10x their visible
-- count (engine count-obfuscation batches), so one style flip can cover
-- thousands of registered buttons -- synchronous restyles froze the client
-- on raid-frame settings changes. This queues the key and re-decorates a
-- bounded number of buttons per frame; re-queuing a key already in flight
-- re-processes it with the latest style table (resolved at apply time).
-- The worker frame is hidden whenever the queue is empty.
local RESTYLE_BUDGET = 200 -- buttons per frame

local restyleQueue = {}
local restyleWork
local restyler = CreateFrame("Frame")
restyler:Hide()
restyler:SetScript("OnUpdate", function(self)
    local budget = RESTYLE_BUDGET
    while budget > 0 do
        if not restyleWork then
            local key = next(restyleQueue)
            if not key then
                self:Hide()
                return
            end
            restyleQueue[key] = nil
            local set = styleButtons[key]
            if AK.styles[key] and set then
                local buttons = {}
                for b in pairs(set) do buttons[#buttons + 1] = b end
                restyleWork = { key = key, buttons = buttons, index = 1 }
            end
        end
        if restyleWork then
            local w = restyleWork
            local style = AK.styles[w.key]
            local n = #w.buttons
            local restricted = AK.AurasRestricted()
            while budget > 0 and w.index <= n do
                local button = w.buttons[w.index]
                -- Advance BEFORE applying: an error must never wedge the
                -- queue on one button. (Field incident, 12.1 build 68745:
                -- a denied button call under aura secrecy retried the same
                -- button every frame forever -- a 1298-error storm.)
                w.index = w.index + 1
                if style then
                    local ok, err = pcall(ApplyStyleToRegions, button, style)
                    if not ok then
                        if type(err) == "string" and w.wd ~= false
                            and string.find(err, "script ran too long", 1, true) then
                            -- The client watchdog killed the slice, not this
                            -- button: rewind, keep the work item, and resume
                            -- next frame on a fresh execution budget. Capped
                            -- so a pathological button still falls through to
                            -- the normal error handling below.
                            w.wd = (w.wd or 0) + 1
                            if w.wd > 3 then w.wd = false end
                            if w.wd then
                                w.index = w.index - 1
                                return
                            end
                        end
                        if restricted then
                            -- Expected under secrecy: button-object writes
                            -- are denied. Re-run the whole key at lift.
                            deferredRestyles[w.key] = true
                        else
                            geterrorhandler()(err)
                        end
                    end
                end
                budget = budget - 1
            end
            if w.index > n then restyleWork = nil end
        end
    end
end)

function AK.RestyleSoon(styleKey)
    restyleQueue[styleKey] = true
    restyler:Show()
end

-- Module hook: park a style key for the restriction-lift drain WITHOUT
-- queueing it now. For module-side pcall'd button calls that were denied
-- under secrecy -- re-queueing immediately would just spin while the
-- restriction holds; the lift watcher re-runs the key when it can succeed.
function AK.DeferRestyle(styleKey)
    if styleKey then deferredRestyles[styleKey] = true end
end

------------------------------------------------------------------------------
-- Restriction-lift watcher. Aura secrecy is instance-gated (combat end,
-- encounter end, zoning) plus the /euidev forced-restriction CVars; on each
-- edge, re-probe and drain the deferred restyles. Fail-open: still
-- restricted just means wait for the next edge. Modules with their own
-- deferred (skipped-without-stamping) work register a callback; callbacks
-- must self-guard with a dirty flag so idle firings cost one boolean test.
------------------------------------------------------------------------------

local liftCallbacks = {}
function AK.OnRestrictionLift(fn)
    liftCallbacks[#liftCallbacks + 1] = fn
end

local liftWatcher = CreateFrame("Frame")
liftWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
liftWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
liftWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
liftWatcher:RegisterEvent("ENCOUNTER_END")
liftWatcher:RegisterEvent("CVAR_UPDATE")
liftWatcher:SetScript("OnEvent", function(_, event, cvarName)
    if event == "CVAR_UPDATE" and cvarName
        and not string.find(cvarName, "RestrictionsForced", 1, true) then
        return
    end
    if not next(deferredRestyles) and #liftCallbacks == 0 then return end
    if AK.AurasRestricted() then return end
    for key in pairs(deferredRestyles) do
        deferredRestyles[key] = nil
        restyleQueue[key] = true
        restyler:Show()
    end
    for i = 1, #liftCallbacks do
        liftCallbacks[i]()
    end
end)

------------------------------------------------------------------------------
-- Container creation
--
-- spec = {
--   layout = { anchorPoint, growthH, growthV, padding = {l, r, t, b}, rowWidth },
--   groups = { { key, filter = {tokens...}, maxFrameCount, sortMethod,
--                sortDirection, candidateFilters, style, extraInit,
--                layout = { elementWidth, elementHeight, elementSpacing,
--                           lineSpacing, groupSpacing, groupLineSpacing,
--                           forceNewLine, layoutIndex } }, ... },  (68914 keys)
--   slots  = { { key, filter = {tokens...}, candidateFilters, sortMethod,
--                sortDirection, style, extraInit }, ... },
--   processAura = { ... } -- optional SetAuraProcessingPolicy options
-- }
--
-- Groups are ADD-ONLY on a container: declare everything up front; a disabled
-- group is maxFrameCount 0, never a removed one.
------------------------------------------------------------------------------

local containerData = setmetatable({}, { __mode = "k" })

-- Container-level layout setters. 68914 replaced the SetAuraLayout* family
-- with SetFlowLayout* (rowWidth generalized to maximumLineSize) and added a
-- flow axis; resolve per call with the old names as fallback so a stale PTR
-- build degrades to the previous behavior instead of erroring. Every module
-- goes through these instead of calling the container methods directly.
function AK.SetContainerAnchor(container, anchorPoint)
    local f = container.SetFlowLayoutAnchorPoint or container.SetAuraLayoutAnchorPoint
    if f then f(container, anchorPoint) end
end

function AK.SetContainerGrowth(container, growthH, growthV)
    local f = container.SetFlowLayoutGrowthDirection or container.SetAuraLayoutGrowthDirection
    if f then f(container, growthH, growthV) end
end

function AK.SetContainerPadding(container, l, r, t, b)
    local f = container.SetFlowLayoutPadding or container.SetAuraLayoutPadding
    if f then f(container, l, r, t, b) end
end

function AK.SetContainerRowWidth(container, rowWidth)
    -- nil resets to unlimited on both API generations
    local f = container.SetFlowLayoutMaximumLineSize or container.SetAuraLayoutRowWidth
    if f then f(container, rowWidth) end
end

-- Flow axis (68914+): Horizontal = lines are rows (the classic layout),
-- Vertical = lines are COLUMNS (fill down/up first, wrap sideways at the
-- line size). No-op on builds without the API -- callers degrade to the
-- old single-column vertical behavior there.
function AK.SetContainerAxis(container, vertical)
    local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local f = container.SetFlowLayoutAxis
    if not (axes and f) then return end
    f(container, vertical and axes.Vertical or axes.Horizontal)
end

function AK.ApplyContainerLayout(container, layout)
    if not layout then return end
    if layout.anchorPoint then AK.SetContainerAnchor(container, layout.anchorPoint) end
    if layout.growthH and layout.growthV then
        AK.SetContainerGrowth(container, layout.growthH, layout.growthV)
    end
    if layout.padding then
        local p = layout.padding
        AK.SetContainerPadding(container, p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0)
    end
    AK.SetContainerRowWidth(container, layout.rowWidth)
end

-- Incremental construction: each AddAuraGroup call eagerly creates a
-- 10-button engine batch through the full region initializer (~4-6ms), so
-- monolithic container builds produce frame spikes proportional to their
-- group count. Shell/AddGroup/AddSlot/Finish let builders spread that work
-- across the shared build scheduler below; CreateContainer composes them
-- for synchronous callers (settings-change swaps, small containers).

function AK.CreateContainerShell(parent, spec)
    -- Combat creation is legal since 68914 (PTR-7 notes; /euit3 field PASS
    -- 2026-07-23). The old in-combat zombie soft-fail -- and the OOC assert
    -- that guarded against it -- are gone.
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")

    -- Anchor and a provisional size up front: the engine drains its parse and
    -- layout phases from an OnUpdate armed in run-when-visible mode, so the
    -- container needs a renderable rect from the very first dirty mark. The
    -- engine replaces the size on every layout pass.
    if spec.point then
        container:SetPoint(unpack(spec.point))
    end
    container:SetSize(1, 1)

    if spec.processAura then
        container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, spec.processAura)
    end

    AK.ApplyContainerLayout(container, spec.layout)

    containerData[container] = { spec = spec, slotFrames = {} }
    return container
end

function AK.AddGroupToContainer(container, g)
    container:AddAuraGroup(g.key, AK.Filter(unpack(g.filter)), {
        maxFrameCount = g.maxFrameCount,
        sortMethod = g.sortMethod,
        sortDirection = g.sortDirection,
        candidateFilters = g.candidateFilters,
        initializeFrame = AK.MakeInitializer(g.style, g.extraInit),
        layout = g.layout,
    })
end

function AK.AddSlotToContainer(container, s)
    local f = container:AddAuraSlot(s.key, AK.Filter(unpack(s.filter)), {
        candidateFilters = s.candidateFilters,
        sortMethod = s.sortMethod,
        sortDirection = s.sortDirection,
        initializeFrame = AK.MakeInitializer(s.style, s.extraInit),
    })
    local cd = containerData[container]
    if cd then cd.slotFrames[s.key] = f end
    return f
end

-- Unit LAST: unit assignment re-evaluates event registrations, and those
-- are gated on the container having groups/slots. Setting the unit before
-- declaring content leaves UNIT_AURA unregistered (the Blizzard reference
-- consumer follows this same order). Finish with a full refresh request.
function AK.FinishContainer(container, unitToken)
    container:SetUnit(unitToken)
    container:UpdateAllAuras()
end

function AK.CreateContainer(parent, unitToken, spec)
    local container = AK.CreateContainerShell(parent, spec)

    if spec.groups then
        for i = 1, #spec.groups do
            AK.AddGroupToContainer(container, spec.groups[i])
        end
    end

    if spec.slots then
        for i = 1, #spec.slots do
            AK.AddSlotToContainer(container, spec.slots[i])
        end
    end

    AK.FinishContainer(container, unitToken)

    return container, containerData[container].slotFrames
end

------------------------------------------------------------------------------
-- Shared build scheduler
--
-- One time-budgeted queue for ALL deferred container construction (RF
-- buttons, NP bundle pool, UF units). Jobs run in FIFO order until the
-- per-frame budget is spent; a single queue means the modules' builders can
-- never stack their work into the same frame. OnUpdate never ticks during a
-- loading screen, so queued work always lands in rendered gameplay frames;
-- combat clamps the budget (client combat watchdog), never the work.
-- Explicit head/tail indices: consumed slots are nil'd and the length
-- operator is undefined on arrays with holes.
------------------------------------------------------------------------------

local BUILD_BUDGET_MS = 8
-- Login/reload window: module setup runs from timer-deferred OnEnable
-- chains that fire only AFTER the loading screen drops, so their build
-- jobs cannot be caught by the behind-the-screen burst -- they drain
-- through the worker on low, streaming-world fps. At the mid-session 8ms
-- budget that read as seconds of missing auras. Inside the window the
-- worker runs a near-burst budget instead: the whole post-login queue
-- lands in a handful of frames during the world fade-in (the user-stated
-- contract: "spread over a few frames on reload/login"), and the gentle
-- budget resumes for everything mid-session.
local BUILD_BUDGET_LOGIN_MS = 250
local LOGIN_WINDOW_S = 15
local loginStamp = -LOGIN_WINDOW_S
-- ONE queue, every job combat-runnable: 68914 made container creation
-- legal in combat (/euit3 field PASS), which retired the whole
-- hold-lane/oocOnly regime -- jobs run in FIFO order whenever the worker
-- ticks, and the only pacing is the per-frame budget (combat-clamped).
local buildQueue, buildHead, buildTail = {}, 1, 0

-- Job verdicts: nil = done; "again" = the job is a multi-atom stepper with
-- more bounded work left (front-requeued so it finishes before newer work,
-- with a budget check between atoms); "watchdog" = synthesized here, never
-- returned by jobs. The pcall exists for the client watchdog ("script ran too long"):
-- login contention can balloon one job's engine batches past the
-- per-execution limit, which previously aborted the whole tick AND lost the
-- dequeued job mid-flight (half-built unit). Jobs are written resumable
-- (existence-guarded stages), so a watchdog-killed job front-requeues and the
-- tick ends -- it resumes with a fresh execution budget next frame. Real
-- errors surface once and drop the job; the rest of the tick keeps draining.
local WATCHDOG_RETRIES = 3
local function RunJob(entry)
    local ok, verdict = pcall(entry.fn)
    if ok then return verdict end
    if type(verdict) == "string"
        and string.find(verdict, "script ran too long", 1, true) then
        entry.watchdogged = (entry.watchdogged or 0) + 1
        if entry.watchdogged <= WATCHDOG_RETRIES then return "watchdog" end
    end
    geterrorhandler()(verdict)
end

local buildWorker = CreateFrame("Frame")
buildWorker:Hide()
buildWorker:SetScript("OnUpdate", function(self)
    local inCombat = InCombatLockdown()
    -- The turbo budget is OOC-ONLY: combat frames run under the client's
    -- combat script watchdog (a 250ms drain tick after an in-combat
    -- /reload tripped "script ran too long"), and a quarter-second hitch
    -- is unacceptable while fighting anyway. In combat the backlog drains
    -- at the gentle budget; the regen wake re-arms the turbo (loginStamp)
    -- so whatever remains snaps in at regen.
    local budget = BUILD_BUDGET_MS
    if not inCombat and GetTime() - loginStamp < LOGIN_WINDOW_S then
        budget = BUILD_BUDGET_LOGIN_MS
    end
    local t0 = debugprofilestop()

    while buildHead <= buildTail do
        local entry = buildQueue[buildHead]
        buildQueue[buildHead] = nil
        buildHead = buildHead + 1
        if entry then
            local verdict = RunJob(entry)
            if verdict == "again" then
                buildHead = buildHead - 1
                buildQueue[buildHead] = entry
            elseif verdict == "watchdog" then
                buildHead = buildHead - 1
                buildQueue[buildHead] = entry
                return
            end
        end
        if debugprofilestop() - t0 >= budget then return end
    end
    buildQueue, buildHead, buildTail = {}, 1, 0
    self:Hide()
end)

-- Regen wake: a backlog that accrued under the combat-clamped budget
-- snaps in at the turbo budget instead of trickling.
buildWorker:RegisterEvent("PLAYER_REGEN_ENABLED")
buildWorker:SetScript("OnEvent", function(self)
    if buildHead <= buildTail then
        loginStamp = GetTime()
        self:Show()
    end
end)

function AK.QueueBuildJob(fn, label)
    buildTail = buildTail + 1
    buildQueue[buildTail] = { fn = fn, label = label }
    buildWorker:Show()
end

-- Back-compat name: a combat-runnable job (declarations/setters on
-- EXISTING containers). Back-compat alias; identical to QueueBuildJob.
function AK.QueueLiveBuildJob(fn, label)
    AK.QueueBuildJob(fn, label, nil)
end

-- NO synchronous loading-screen burst: a long drain inside the PEW
-- handler stacks onto every other addon's login work in ONE script
-- execution and trips the client watchdog ("script ran too long") --
-- field-hit at 1500ms. It also cannot reach the RF/UF jobs, which are
-- enqueued by timer-deferred module setup AFTER the screen drops. PEW
-- only opens the worker's login-window turbo budget: the whole demand-
-- architecture queue drains in a handful of 250ms frames DURING the
-- world fade-in (per-frame executions never approach the watchdog).
local burstFrame = CreateFrame("Frame")
burstFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
burstFrame:SetScript("OnEvent", function()
    loginStamp = GetTime()
    buildWorker:Show() -- in case jobs were queued behind the screen
end)

-- Combat-safe wrapper: fulfills immediately out of combat, otherwise queues
-- until PLAYER_REGEN_ENABLED. The listener frame is never handed to the
-- restricted environment, so its event registration is aspect-safe.
local pending = {}
local regenListener

function AK.RequestContainer(parent, unitToken, spec, callback)
    if not InCombatLockdown() then
        local container, slotFrames = AK.CreateContainer(parent, unitToken, spec)
        if callback then callback(container, slotFrames) end
        return
    end

    pending[#pending + 1] = { parent = parent, unit = unitToken, spec = spec, callback = callback }

    if not regenListener then
        regenListener = CreateFrame("Frame")
        regenListener:RegisterEvent("PLAYER_REGEN_ENABLED")
        regenListener:SetScript("OnEvent", function()
            local queue = pending
            pending = {}
            for i = 1, #queue do
                local q = queue[i]
                local container, slotFrames = AK.CreateContainer(q.parent, q.unit, q.spec)
                if q.callback then q.callback(container, slotFrames) end
            end
        end)
    end
end

function AK.GetContainerData(container)
    return containerData[container]
end

-- Releases a swapped-out container's tracked slot buttons from the restyle
-- registry. Abandoned containers can never be destroyed (frames are
-- permanent), so without this every swap leaves zombie buttons that all
-- future Restyle passes keep re-decorating -- restyle cost grows with every
-- swap. Group buttons are engine-created without a handle list and are not
-- individually tracked; group-based containers swap rarely (filter-class
-- changes), so their zombies are accepted for now.
function AK.ReleaseContainer(container)
    if not container then return end
    local data = containerData[container]
    if data and data.slotFrames then
        for _, slotButton in pairs(data.slotFrames) do
            local d = bd[slotButton]
            if d then
                if d.styleKey and styleButtons[d.styleKey] then
                    styleButtons[d.styleKey][slotButton] = nil
                end
                bd[slotButton] = nil
            end
        end
    end
    containerData[container] = nil
    container:Hide()
end

------------------------------------------------------------------------------
-- Restriction probe
--
-- There is no official "are auras secret" query. This is a best-effort helper
-- for the surviving spellID-lookup paths that want to know whether silent
-- absence semantics are in effect. Never treat it as a data source.
--
-- Cached per frame time: while restricted, the probe THROWS (and catches) a
-- real Lua error, and error construction is the expensive part -- callers
-- (ABR reminder evaluators, QoL sweeps) hit this several times per pass.
-- Restriction is instance-gated state that cannot flip mid-frame; the RF
-- containers' own copy of this probe has always relied on the same fact.
------------------------------------------------------------------------------

-- ASYMMETRIC cache: only the RESTRICTED answer is cached (that is the one
-- whose probe throws -- error construction is the cost being amortized).
-- The clear answer is re-probed on every call, because a stale "false"
-- sends callers into hard-erroring scans when restriction engages within
-- the frame window (field-hit: /euidev flips and zone edges); the success
-- probe is a cheap C call, so not caching it costs nothing. A stale
-- "true" merely suppresses a display for one frame -- safe.
local restrictedStamp = -1
function AK.AurasRestricted()
    local now = GetTime()
    if now == restrictedStamp then return true end
    if pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL") then
        return false
    end
    restrictedStamp = now
    return true
end
