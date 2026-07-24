-- EUI_ResourceBars_EbonMight121.lua
-- 12.1 ONLY: engine-slot driver for the Aug Evoker Ebon Might power bar.
--
-- Ebon Might (395296) is secret-flagged since build 68824, so the legacy
-- numeric countdown (GetPlayerAuraBySpellID expirationTime + OnUpdate
-- drain) can never run in restricted content. Same technique as the CDM
-- fake-active port: a hidden one-slot aura container on the player
-- (includeSpellIDs -- helpful-on-self passes the identity gate regardless
-- of secrecy) whose slot subtree IS the display, engine-driven end to end:
-- the button shows only while the aura is up, a slot-child StatusBar bound
-- via SetDurationBar renders remaining time (extensions included), and a
-- bound FontString renders the countdown text. Everything is styled INSIDE
-- the creation window -- the subtree is denied to addon code afterward,
-- reads and writes both (engine contract #7) -- baked from the live bar's
-- settings, so styling edits apply on the next /reload.
--
-- The main file's Ebon Might fill/text paths early-return under
-- ns.EMB121_Owns and call ns.EMB121_Sync from UpdatePrimaryBar's Ebon
-- Might branch -- which always runs with the live bar and resolved
-- settings in hand, so there is no build race: Sync IS the trigger.
-- ns.EMB121_Gate parks the overlay whenever the primary power type is no
-- longer Ebon Might (spec change).
--
-- Retail: this file self-gates on IS_121; every ns.EMB121_* consumer in
-- the main file is nil-dead there, so retail behavior is byte-identical.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_121) then return end

local EBON_AURA_ID = 395296

-- Load-time ownership flag: legacy paths gate on this, and it must exist
-- at FILE LOAD -- a construction-time flag would let legacy paths run (and
-- error under restriction) before the deferred build completes.
ns.EMB121_Owns = true

-- proxy, container, btn, bar, built, queued, armed, rbBar, pp, pc, fsErr
local S = {}

-- "18.4"-style remaining text (legacy parity: %.1f seconds; minutes floor
-- to "2m" if extensions ever push past 60). Falls back to the suite
-- duration formatter, then to the engine default.
local timeFmt
local function GetTimeFormatter()
    if timeFmt ~= nil then return timeFmt or nil end
    timeFmt = false
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding then
        local f = C_StringUtil.CreateNumericRuleFormatter()
        local Down = Enum.NumericRuleFormatRounding.Down
        local ok = pcall(f.SetBreakpoints, f, {
            { threshold = 0,  format = "%.1f", step = 0.1, rounding = Down },
            { threshold = 60, format = "%dm",  step = 1,   rounding = Down, components = { { div = 60 } } },
        })
        if ok then timeFmt = f end
    end
    if not timeFmt then
        local AK = EllesmereUI.AuraKit
        timeFmt = (AK and AK.GetDurationFormatter and AK.GetDurationFormatter()) or false
    end
    return timeFmt or nil
end

local function Build()
    local AK = EllesmereUI.AuraKit
    if S.built or not AK or not S.rbBar then return end
    local rb, pp, pc = S.rbBar, S.pp or {}, S.pc

    AK.styles["erb:emb121"] = AK.styles["erb:emb121"]
        or { noRegions = true, width = 1, height = 1 }
    if not S.proxy then
        S.proxy = CreateFrame("Frame", nil, UIParent)
        S.proxy:Hide()
    end

    -- Bake the live bar's visuals (our frames -- readable): fill texture
    -- path, then color per the legacy priority (custom = whatever the
    -- build pass painted on the fill; else the Ebon Might power color,
    -- flat or gradient per settings).
    local ft = rb.GetStatusBarTexture and rb:GetStatusBarTexture()
    local texPath = (ft and ft.GetTexture and ft:GetTexture()) or "Interface\\Buttons\\WHITE8x8"
    local r, g, b, a = 1, 1, 1, 1
    if pp.customColored and ft and ft.GetVertexColor then
        r, g, b, a = ft:GetVertexColor()
    elseif pc then
        r, g, b = pc[1] or 1, pc[2] or 1, pc[3] or 1
    end

    -- Text bake source: the bar's own text FS (font + anchor), so the
    -- engine text lands exactly where the legacy text sat.
    local tFont, tSize, tFlags, tPoint, tRelP, tX, tY
    local rbText = rb._text
    if rbText and rbText.GetFont then
        tFont, tSize, tFlags = rbText:GetFont()
        if rbText.GetPoint and rbText:GetNumPoints() > 0 then
            local p, _, rp, x, y = rbText:GetPoint(1)
            tPoint, tRelP, tX, tY = p, rp, x, y
        end
    end
    local showText = pp.textFormat and pp.textFormat ~= "none"

    local container = AK.CreateContainerShell(S.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(container, {
        key = "em",
        filter = { "HELPFUL" },
        candidateFilters = { includeSpellIDs = { [EBON_AURA_ID] = true } },
        style = "erb:emb121",
        extraInit = function(button)
            -- Creation window: the only legal moment to touch this
            -- subtree. Two-point anchoring sizes the button by anchors
            -- forever; all repositioning is proxy moves.
            button:SetAllPoints(S.proxy)
            if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end

            local bar = CreateFrame("StatusBar", nil, button)
            bar:SetAllPoints(button)
            bar:SetStatusBarTexture(texPath)
            local bft = bar:GetStatusBarTexture()
            if bft then
                if pp.gradientEnabled and not pp.customColored and bft.SetGradient then
                    -- Mirrors the legacy gradient applier: white vertex,
                    -- endpoint colors carry the gradient.
                    bft:SetVertexColor(1, 1, 1, 1)
                    bft:SetGradient(pp.gradientDir or "HORIZONTAL",
                        CreateColor(r, g, b, 1),
                        CreateColor(pp.gradientR or r, pp.gradientG or g,
                            pp.gradientB or b, pp.gradientA or 1))
                else
                    bft:SetVertexColor(r, g, b, a or 1)
                end
            end
            local opts = {}
            if Enum.StatusBarInterpolation then
                opts.interpolation = Enum.StatusBarInterpolation.Immediate
            end
            if Enum.StatusBarTimerDirection then
                opts.direction = Enum.StatusBarTimerDirection.RemainingTime
            end
            button:SetDurationBar(bar, opts)

            if showText then
                -- ARMORED: an uncaught error here aborts the engine's
                -- CreateFrameBatch and kills the slot. Text is optional
                -- polish; failures land in S.fsErr.
                local okFS, errFS = pcall(function()
                    local tc = CreateFrame("Frame", nil, button)
                    tc:SetAllPoints(button)
                    tc:SetFrameLevel(bar:GetFrameLevel() + 5)
                    local fs = tc:CreateFontString(nil, "OVERLAY")
                    -- Font BEFORE registration (the engine SetText()s every
                    -- registered string; an unfonted FS hard-errors).
                    if tFont then
                        fs:SetFont(tFont, tSize, tFlags)
                    else
                        fs:SetFont("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF", 12, "OUTLINE")
                    end
                    if rbText and rbText.GetTextColor then
                        fs:SetTextColor(rbText:GetTextColor())
                    end
                    fs:SetPoint(tPoint or "CENTER", button, tRelP or tPoint or "CENTER", tX or 0, tY or 0)
                    -- 68914 schema key (textFormatter); BuildDurationTextOpts
                    -- when available, bare table fallback otherwise.
                    local AK2 = EllesmereUI.AuraKit
                    local dopts
                    if AK2 and AK2.BuildDurationTextOpts then
                        dopts = AK2.BuildDurationTextOpts(GetTimeFormatter())
                    else
                        dopts = { textFormatter = GetTimeFormatter() }
                    end
                    if AK2 and AK2.SetDurationTextSafe then
                        AK2.SetDurationTextSafe(button, fs, dopts)
                    else
                        button:SetDurationText(fs, dopts)
                    end
                end)
                if not okFS then S.fsErr = errFS end
            end

            S.btn, S.bar = button, bar
        end,
    })
    AK.FinishContainer(container, "player")
    S.container = container
    S.built = true
end

local function EnsureBuilt()
    if S.built or S.queued then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.QueueBuildJob) then return end
    S.queued = true
    AK.QueueBuildJob(function()
        S.queued = nil
        Build()
        if S.built and S.armed and S.rbBar then
            ns.EMB121_Sync(S.rbBar, S.pp, S.pc)
        end
    end, "erb:emb121-shell")
end

-- Called from UpdatePrimaryBar whenever the primary power type resolves:
-- parks the overlay the moment the bar stops being Ebon Might (spec swap).
function ns.EMB121_Gate(isEbon)
    if not isEbon and S.armed then
        S.armed = nil
        if S.proxy then S.proxy:Hide() end
    end
end

-- Called from UpdatePrimaryBar's Ebon Might branch with the live bar and
-- resolved settings -- the build trigger AND the attach, race-free by
-- construction. Repositioning is always proxy moves (our frame).
function ns.EMB121_Sync(bar, pp, pc)
    S.rbBar, S.pp, S.pc = bar, pp, pc
    S.armed = true
    if not S.built then
        EnsureBuilt()
        return
    end
    S.proxy:SetParent(bar)
    S.proxy:ClearAllPoints()
    S.proxy:SetAllPoints(bar)
    S.proxy:Show()
    -- One container-level set lifts the whole engine subtree above the
    -- (empty) legacy fill.
    S.container:SetFrameLevel(bar:GetFrameLevel() + 1)
end
