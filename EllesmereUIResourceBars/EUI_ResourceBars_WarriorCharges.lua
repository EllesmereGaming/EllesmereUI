if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_WarriorCharges.lua
-- ERB adapter for the engine-fed Warrior charge fills. The generic multi-host
-- core lives in the PARENT addon (EllesmereUI_WarriorCharges.lua, exported as
-- _G._EWC) so every consumer gets the feed regardless of enabled children;
-- this file only translates the class resource bar's resolved build into host
-- opts. BuildBars calls ns.WC_Sync with the resolved secondary build, the pip
-- painter calls ns.WC_Recolor with its fully resolved color every pass and
-- ns.WC_EngineOn to gate itself.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

local PLAYER_CLASS = select(2, UnitClass("player"))

local function FillTexPath()
    local ERB = ns.ERB
    local p = ERB and ERB.db and ERB.db.profile
    local key = (p and p.general and p.general.barTexture) or "none"
    return EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, key,
        "Interface\\Buttons\\WHITE8x8")
end

-- Belt only (the painter's stashed color is the primary source): mirrors the
-- pip painter's exact chain -- dark theme > resource color (falls back to
-- class) > power/class color > custom fill. GetPowerColor(powerKey) is what
-- the painter's POWER_COLORS memo resolves for these string keys; class color
-- comes from GetClassColor, the same source as its CLASS_COLORS memo.
local function FillColor(sp, powerKey)
    if sp.darkTheme and EllesmereUI.GetDarkModeFill then
        local r, g, b = EllesmereUI.GetDarkModeFill()
        return r or 1, g or 1, b or 1, 1
    end
    local ERB = ns.ERB
    if sp.resourceColored then
        if ERB and ERB.ResolveSecondaryResourceColor then
            local r, g, b = ERB.ResolveSecondaryResourceColor(powerKey)
            if r then return r, g, b, 1 end
        end
    elseif sp.classColored == false then
        return sp.fillR or 1, sp.fillG or 1, sp.fillB or 1, 1
    else
        local pc = EllesmereUI.GetPowerColor and EllesmereUI.GetPowerColor(powerKey)
        if pc then return pc.r, pc.g, pc.b, 1 end
    end
    local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(PLAYER_CLASS)
    if cc then return cc.r, cc.g, cc.b, 1 end
    return 1, 1, 1, 1
end

function ns.WC_EngineOn(powerKey)
    local ewc = _G._EWC
    return (ewc and ewc.EngineOn("erb", powerKey)) or false
end

function ns.WC_Recolor(powerKey, r, g, b, a)
    local ewc = _G._EWC
    if ewc then ewc.Recolor("erb", powerKey, r, g, b, a) end
end

-- Threshold/band inputs, handed raw each paint pass; the core change-gates
-- with alloc-free compares and renders them as engine-masked range strips.
function ns.WC_Thresholds(powerKey, mode, count, r, g, b, a,
                          bandOn, bands, bandReverse, reverse)
    local ewc = _G._EWC
    if ewc and ewc.Thresholds then
        ewc.Thresholds("erb", powerKey, mode, count, r, g, b, a,
            bandOn, bands, bandReverse, reverse)
    end
end

-- Called from BuildBars with the resolved secondary build in hand (race-free:
-- the frame is created, sized and styled by the time this runs). Any power
-- type other than the two warrior charge buffs parks the overlay.
function ns.WC_Sync(frame, sp, powerKey, gen)
    local ewc = _G._EWC
    if not ewc or PLAYER_CLASS ~= "WARRIOR" then return end
    if not ((powerKey == "WHIRLWIND_STACKS" or powerKey == "SWEEPING_STRIKES")
            and frame and sp) then
        ewc.Gate("erb")
        return
    end
    local fr, fg, fb, fa = FillColor(sp, powerKey)
    -- Empty Bar Overlay: the legacy pips painted every empty slot's backdrop
    -- through ERB.PipBgColor (bgR/G/B/A, dark theme -> opaque dark-mode bg,
    -- fill-opacity compositing). The engine fill renders over a transparent
    -- proxy, so without this strip the empty portion fell through to the
    -- near-black _barBg and dark mode lost all deduction contrast.
    local ebR, ebG, ebB, ebA = 0.1, 0.1, 0.1, 0.5
    local ERB2 = ns.ERB
    if ERB2 and ERB2.PipBgColor then
        ebR, ebG, ebB, ebA = ERB2.PipBgColor(sp)
    end
    local wantText = sp.showText and true or false
    if wantText and _G._ERB_TextHiddenByForm and ns.ERB and ns.ERB.db
       and _G._ERB_TextHiddenByForm(ns.ERB.db.profile.secondary, true) then
        wantText = false
    end
    ewc.Sync("erb", frame, powerKey, {
        texPath = FillTexPath(),
        r = fr, g = fg, b = fb, a = fa,
        fillAlpha = ((sp.fillOpacity or 100) < 100) and ((sp.fillOpacity or 100) / 100) or 1,
        ori = sp.pipOrientation or "HORIZONTAL",
        pipOrientation = sp.pipOrientation,
        pipSpacing = sp.pipSpacing,
        gapColorEnabled = sp.gapColorEnabled,
        gapR = sp.gapR, gapG = sp.gapG, gapB = sp.gapB, gapA = sp.gapA,
        darkTheme = sp.darkTheme,
        sep = { empty = { r = ebR, g = ebG, b = ebB, a = ebA } },
        barBgR = sp.barBgR, barBgG = sp.barBgG, barBgB = sp.barBgB, barBgA = sp.barBgA,
        text = {
            fontFrom = frame._countText,
            r = sp.textR, g = sp.textG, b = sp.textB,
            anchor = sp.textAnchor, x = sp.textXOffset, y = sp.textYOffset,
            shown = wantText,
        },
    })
end
