if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICooldownManager_Options.lua
--  Registers CDM Effects module with EllesmereUI
--  Tab 1: CDM Bars  (Bar Glows + Tracking Bars disabled pending rewrite)
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUICooldownManager"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

-- Controller cursor: a hand-built popup (named dimmer over its panel) joins the
-- controller cursor and answers controller Back from its first open with a
-- controller in use; until then nothing is registered or hooked. The panel
-- stays a blocker without being a cursor stop, closeBtn is what the
-- controller's cancel button presses, and onEscape (nil = hide the dimmer) is
-- what Back runs. Call it just before the dimmer's Show. On ns: shared with the
-- Talent Conditions popup, and no main-chunk local.
function ns.PadPopupOpen(dimmer, panel, closeBtn, onEscape)
    if dimmer._padReg or not EllesmereUI.PadInUse() then return end
    dimmer._padReg = true
    EllesmereUI.PadHint(panel, "nodepass")
    if closeBtn then panel.CloseButton = closeBtn end
    EllesmereUI.RegisterEscapeClose(dimmer, { padOnly = true, onEscape = onEscape })
end

-- Gates a row under Blizzard Style only: the classic kit draws chrome round
-- the user's own fill and background, so those settings stay live there.
local function GateBlizzardOnly(key, cfg)
    if EllesmereUI.BlizzStyle.Active(key) == "blizzard" then
        return EllesmereUI.BlizzStyle.Gate(key, cfg)
    end
    return cfg
end

local PAGE_GENERAL = "General"
local PAGE_BAR_GLOWS    = "Bar Glows"
local PAGE_BUFF_BARS    = "Tracking Bars"
local PAGE_CDM_BARS     = "CDM Bars"
local PAGE_ROTATION_ICON = "Rotation Assist Icon"

local PAGE_UNLOCK       = "Unlock Mode"

local SEC_MAPPINGS   = "GLOW MAPPINGS"
local SEC_LAYOUT     = "LAYOUT"
local SEC_APPEARANCE = "APPEARANCE"
local SEC_FILTER     = "FILTER"
local SEC_BEHAVIOR   = "BEHAVIOR"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local db
    C_Timer.After(0, function() db = _G._ECME_AceDB end)

    local function DB()
        if not db then db = _G._ECME_AceDB end
        return db and db.profile
    end

    local function Refresh()
        if _G._ECME_Apply then _G._ECME_Apply() end
    end

    -- Add/RemoveTrackedSpell already rebuild routes + queue reanchor; force an immediate
    -- CollectAndReanchor (not the throttled queue), then rebuild the page with
    -- _skipNextApplyRebuild to skip the redundant FullCDMRebuild.
    local function RefreshCDPreview()
        if ns.CollectAndReanchor then ns.CollectAndReanchor() end
        ns._skipNextApplyRebuild = true
        C_Timer.After(0.05, function()
            if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
            if ns.ApplyCachedKeybinds then ns.ApplyCachedKeybinds() end
            EllesmereUI:RefreshPage(true)
        end)
    end

    -- Inline text input helper (no W:InputBox exists)
    local FONT_PATH = (EllesmereUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    local GetCDMOptOutline = EllesmereUI.GetFontOutlineFlag

    -- Auto-widens break-out menus (flyouts/Apply-to strip/item pickers) to the longest
    -- RENDERED caption so text doesn't overflow (option rows) or ellipsize (item rows):
    -- grow-only from nominal width, capped at MAX_W (tooltip/ellipsis fallback past cap).
    -- pad = text inset + right-edge furniture; hidden rows count too -- never resize mid-hover/typing.
    local function FitMenuWidth(labels, nominalW, pad)
        local MAX_W = 340
        local widest = 0
        for i = 1, #labels do
            local fs = labels[i]
            local w = fs and fs:GetStringWidth() or 0
            if w > widest then widest = w end
        end
        local fit = math.ceil(widest + (pad or 40))
        if fit < nominalW then fit = nominalW end
        if fit > MAX_W then fit = MAX_W end
        return fit
    end
    local SetPVFont = EllesmereUI.ApplyModuleFont

    ---------------------------------------------------------------------------
    --  Buff spell list from viewer pool (Bar Glows page glow assignments)
    ---------------------------------------------------------------------------
    local BAR_BUTTON_PREFIXES = {
        [1] = "ActionButton",
        [2] = "MultiBarBottomLeftButton",
        [3] = "MultiBarBottomRightButton",
        [4] = "MultiBarRightButton",
        [5] = "MultiBarLeftButton",
        [6] = "MultiBar5Button",
        [7] = "MultiBar6Button",
        [8] = "MultiBar7Button",
    }

    -- Action bar shape masks/borders (for preview rendering)
    local AB_SHAPE_MASKS = EllesmereUI.SHAPE_MASKS
    local AB_SHAPE_BORDERS = EllesmereUI.SHAPE_BORDERS

    -- Action bar entries (1-8) are stable; CDM bar entries are built dynamically via
    -- BuildBGTargetList since users can add extra cooldown/utility/buff bars beyond defaults.
    local BG_ACTION_BAR_LABELS = {
        [1] = "Action Bar 1 (Main)", [2] = "Action Bar 2", [3] = "Action Bar 3", [4] = "Action Bar 4",
        [5] = "Action Bar 5", [6] = "Action Bar 6", [7] = "Action Bar 7", [8] = "Action Bar 8",
    }

    -- Legacy installs saved selectedBar as 101/102 for the default cooldowns/
    -- utility CDM bars; normalize to the bar key string (new saves use the key).
    local function NormalizeSelectedBar(sel)
        if sel == 101 then return "cooldowns" end
        if sel == 102 then return "utility" end
        return sel
    end

    -- Live dropdown list: {value,label} in display order -- CDM bars from p.cdmBars.bars
    -- (skipping ghost/custom_buff) then action bars 1-8; value = bar key string or int 1-8.
    local function BuildBGTargetList()
        local list = {}
        local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.enabled and not bd.isGhostBar
                   and bd.barType ~= "custom_buff" then
                    list[#list + 1] = {
                        value = bd.key,
                        label = EllesmereUI.Lf("CDM Bar - %s", EllesmereUI.L(bd.name or bd.key)),
                    }
                end
            end
        end
        for i = 1, 8 do
            list[#list + 1] = { value = i, label = EllesmereUI.L(BG_ACTION_BAR_LABELS[i]) }
        end
        return list
    end

    local function GetBGTargetLabel(sel)
        sel = NormalizeSelectedBar(sel)
        if type(sel) == "number" then
            return EllesmereUI.L(BG_ACTION_BAR_LABELS[sel] or ("Action Bar " .. sel))
        end
        local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.key == sel then return EllesmereUI.Lf("CDM Bar - %s", EllesmereUI.L(bd.name or bd.key)) end
            end
        end
        return tostring(sel)
    end

    -- Presets/custom spell IDs/racials/trinkets/custom buffs are EllesmereUI-injected
    -- icons (no stable cooldownID), so they are NOT glow-assignable -- the Bar Glows preview leaves them inert.
    local function IsNonGlowableCDMIcon(frame)
        if not frame then return false end
        -- Overflow-diverted icons are session-only: their glow identity/slot-index
        -- fallback key belongs to the source bar, so they aren't listed while diverted
        -- (existing cdm_-keyed glows still RENDER -- the render pass is key-driven, not list-driven).
        if ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(frame) then return true end
        return (frame._isRacialFrame or frame._isTrinketFrame
            or frame._isPresetFrame or frame._isItemPresetFrame
            or frame._isCustomSpellFrame or frame._isCustomBuffFrame) and true or false
    end

    -- True if any icon on a buff bar has per-icon "Always Show Buff" = on (or
    -- "missing" -- Show When Missing also injects inactive placeholders), so
    -- it's mutually exclusive with "Keep Buffs in Same Place".
    local function AnyIconAlwaysShowOn(barKey)
        -- Per-spell entries live in the spec FAMILY store; rawget skips bar-tier
        -- inheritance (checked separately below).
        local st = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore(barKey)
        if st then
            for _, ss in pairs(st) do
                if type(ss) == "table" then
                    local as = rawget(ss, "alwaysShow")
                    if as == "on" or as == "missing" then return true end
                end
            end
        end
        local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
        local tier = ns.GetBarTierSettings and ns.GetBarTierSettings(sd, barKey)
        if tier and (tier.alwaysShow == "on" or tier.alwaysShow == "missing") then return true end
        return false
    end

    -- Build glow style dropdown values from ns.GLOW_STYLES
    local function GetGlowStyleValues()
        local labels, order = {}, {}
        if ns.GLOW_STYLES then
            for _, i in ipairs(ns.GLOW_VIEW.ordered) do local entry = ns.GLOW_STYLES[i]
                labels[i] = (entry.name and EllesmereUI.L(entry.name)) or ("Style " .. i)
                order[#order + 1] = i
            end
        end
        if #order == 0 then
            labels[1] = "Action Button Glow"
            order[1] = 1
        end
        return labels, order
    end

    ---------------------------------------------------------------------------
    --  Glow sites for Global Settings > Glows: per-bar Pandemic Glow, Buff Glow
    --  and Pixel Glow parameters, Tracked Buff Bars (active spec) and Rotation
    --  Assist, as shared glow descriptors over the bars' own keys.
    ---------------------------------------------------------------------------
    do
        local GO = EllesmereUI.GlowOptions
        local function CdmBars()
            local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
            return p and p.cdmBars
        end
        local function Rebuild() if ns.BuildAllCDMBars then ns.BuildAllCDMBars() end end
        -- Shared per-bar refreshes: the Glows page runs each distinct onChange once
        -- per Apply, so every bar's descriptor must hand out the same function.
        local function RebuildBuffGlows()
            Rebuild()
            if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
        end
        local function RebuildPixelGlows()
            Rebuild()
            if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
        end
        local function RebuildTBB() if ns.BuildTrackedBuffBars then ns.BuildTrackedBuffBars() end end
        local function ColorKeys(t, key)
            local c = t[key]
            if c then return c.r, c.g, c.b end
        end
        -- pandemicGlow* keys, shared by a bar's Pandemic Glow and the Tracked Buff
        -- Bars (style reads differ, see the descriptors).
        local function PandemicGet(bd, f)
            if f == "mode" then return bd.pandemicGlowMode or "default" end
            return EllesmereUI.GlowOptions.FlatGet(bd, "pandemicGlow", f)
        end
        local function PandemicSet(bd, f, a, b2, c2)
            if f == "style" then
                if a == 0 then bd.pandemicGlow = false else bd.pandemicGlow = true; bd.pandemicGlowStyle = a end
            elseif f == "mode" then
                bd.pandemicGlowMode = a
                -- Custom with no color stored draws the default look on the bar
                -- while the swatch and the preview show yellow: store it.
                if a == "custom" and not bd.pandemicGlowColor then
                    bd.pandemicGlowColor = { r = 1, g = 1, b = 0 }
                end
            else EllesmereUI.GlowOptions.FlatSet(bd, "pandemicGlow", f, a, b2, c2)
            end
        end

        -- Pandemic Glow of one CDM bar, shared by the Glows page and the CDM Bars
        -- page row. getBd resolves the bar at call time; onChange defaults to the
        -- shared rebuild (the bar page passes its own). nil pandemicGlow = never
        -- configured = Blizzard Default, not None: the built-in bars never seed the
        -- key (the templates that do ship true + -1) and Blizzard's PandemicIcon
        -- still draws for them, so only an explicit false reads as None.
        local function PandemicDesc(getBd, onChange)
            return {
                view = ns.GLOW_VIEW, host = "icon", excludes = { [4] = true },
                extras = { { value = -1, label = "Blizzard Default" } },
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 1, b = 0 },
                onChange = onChange or Rebuild,
                get = function(f)
                    local bd = getBd(); if not bd then return nil end
                    if f == "style" then
                        if bd.pandemicGlow == false then return 0 end
                        if bd.pandemicGlow == nil then return -1 end
                        return bd.pandemicGlowStyle or 1
                    end
                    return PandemicGet(bd, f)
                end,
                set = function(f, a, b2, c2)
                    local bd = getBd(); if bd then PandemicSet(bd, f, a, b2, c2) end
                end,
            }
        end
        ns._CDM_PandemicGlowDesc = PandemicDesc

        -- Buff Glow of one buff-family bar (flat buffGlow* keys); getBd and
        -- onChange as for PandemicDesc.
        local function BuffGlowDesc(getBd, onChange)
            return {
                view = ns.GLOW_VIEW, host = "icon", excludes = { [4] = true },
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 0.788, b = 0.137 },
                onChange = onChange or RebuildBuffGlows,
                get = function(f)
                    local bd = getBd(); if not bd then return nil end
                    if f == "style" then return bd.buffGlowType or 0
                    elseif f == "mode" then return bd.buffGlowMode or "default"
                    elseif f == "color" then
                        if bd.buffGlowR then return bd.buffGlowR, bd.buffGlowG, bd.buffGlowB end
                    -- Same fallbacks as the Buff Glow renderer (8/2/4), not the pixelGlow* keys.
                    elseif f == "lines" then return bd.buffGlowLines
                    elseif f == "thickness" then return bd.buffGlowThickness
                    elseif f == "speed" then return bd.buffGlowSpeed
                    elseif f == "bg" then return bd.buffGlowBackground == true
                    elseif f == "bgColor" then
                        if bd.buffGlowBackgroundR then return bd.buffGlowBackgroundR, bd.buffGlowBackgroundG, bd.buffGlowBackgroundB end
                    end
                end,
                set = function(f, a, b2, c2)
                    local bd = getBd(); if not bd then return end
                    if f == "style" then bd.buffGlowType = a
                    elseif f == "mode" then bd.buffGlowMode = a
                    elseif f == "color" then bd.buffGlowR, bd.buffGlowG, bd.buffGlowB = a, b2, c2
                    elseif f == "lines" then bd.buffGlowLines = a
                    elseif f == "thickness" then bd.buffGlowThickness = a
                    elseif f == "speed" then bd.buffGlowSpeed = a
                    elseif f == "bg" then bd.buffGlowBackground = a
                    elseif f == "bgColor" then bd.buffGlowBackgroundR, bd.buffGlowBackgroundG, bd.buffGlowBackgroundB = a, b2, c2
                    end
                end,
            }
        end
        ns._CDM_BuffGlowDesc = BuffGlowDesc

        -- Pixel Glow parameters of a cooldown bar: the per-spell glows assigned on
        -- its icons read these (no style or color of their own).
        local function PixelParamsDesc(bd)
            return {
                paramsOnly = true, host = "icon",
                caps = { params = true, bg = true },
                onChange = RebuildPixelGlows,
                get = function(f)
                    if f == "lines" then return bd.pixelGlowLines
                    elseif f == "thickness" then return bd.pixelGlowThickness
                    elseif f == "speed" then return bd.pixelGlowSpeed
                    elseif f == "bg" then return bd.pixelGlowBackground == true
                    elseif f == "bgColor" then
                        if bd.pixelGlowBackgroundR then return bd.pixelGlowBackgroundR, bd.pixelGlowBackgroundG, bd.pixelGlowBackgroundB end
                    elseif f == "mode" then return "default"
                    end
                end,
                set = function(f, a, b2, c2)
                    if f == "lines" then bd.pixelGlowLines = a
                    elseif f == "thickness" then bd.pixelGlowThickness = a
                    elseif f == "speed" then bd.pixelGlowSpeed = a
                    elseif f == "bg" then bd.pixelGlowBackground = a
                    elseif f == "bgColor" then bd.pixelGlowBackgroundR, bd.pixelGlowBackgroundG, bd.pixelGlowBackgroundB = a, b2, c2
                    end
                end,
            }
        end

        -- Pandemic Glow of one Tracked Buff Bar (rectangle: Pixel and Auto-Cast only;
        -- any other stored style or Blizzard Default shows and renders as Pixel, see
        -- ns.PG_TbbEffectiveStyle). getBd resolves the bar at call time, so the
        -- Tracking Bars page (selected bar) and the Glows page share this.
        local function TbbDesc(getBd, onChange)
            return {
                view = ns.GLOW_VIEW, host = "bar", excludes = EllesmereUI.Glows.RECT_EXCLUDES,
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 1, b = 0 },
                isOff = function() local bd = getBd(); return not bd or bd.pandemicGlow ~= true end,
                onChange = onChange,
                get = function(f)
                    local bd = getBd(); if not bd then return nil end
                    if f == "style" then return ns.PG_TbbEffectiveStyle(bd) end
                    return PandemicGet(bd, f)
                end,
                set = function(f, a, b2, c2)
                    local bd = getBd(); if bd then PandemicSet(bd, f, a, b2, c2) end
                end,
            }
        end
        ns._CDM_TbbGlowDesc = TbbDesc

        -- Rotation Assist (profile-wide): string-keyed styles; Blizzard Default and
        -- Solid Border are extras, never template targets.
        local ROT_TO_SHARED = { pixel = 1, button = 2, autocast = 3, shape = 4, gcd = 5, modern = 6, classic = 7 }
        local SHARED_TO_ROT = {}
        for k, v in pairs(ROT_TO_SHARED) do SHARED_TO_ROT[v] = k end
        -- Why the CDM highlight cannot show, nil while it can: Blizzard's
        -- Assisted Highlight off (always on Forever) or Show Rotation Helper off.
        local function RotationLockTip()
            if not ns.RotationAssistAvailable() then
                return "This option requires Blizzard's Assisted Highlight to be enabled"
            end
            local c = CdmBars()
            if c and c.hideRotationHelper then return "Show Rotation Helper" end
        end
        local function RotationHelperOff() return RotationLockTip() ~= nil end
        -- The CDM Bars page builds its Rotation Assist rows only while this is false.
        ns._CDM_RotationHelperOff = RotationHelperOff
        -- Blizzard's Assisted Highlight switched in its own options (fires only on
        -- a real change): those rows were built for the old state, and a cached
        -- page comes back without a rebuild. Drop the cached CDM pages and rebuild
        -- the one on screen (a closed panel rebuilds on its next show); the Glows
        -- page lists this site per build. Not on Forever.
        if not EllesmereUI.IS_FOREVER then
            EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
                EllesmereUI:InvalidateModulePageCache("EllesmereUICooldownManager")
                local m = EllesmereUI:GetActiveModule()
                if m == "EllesmereUICooldownManager"
                    or (m == EllesmereUI.GLOBAL_KEY and EllesmereUI:GetActivePage() == "Glows") then
                    EllesmereUI:RefreshPage(true)
                end
            end, "ECME_Options_AssistedHighlight")
        end
        local function RotationDesc()
            local desc = {
                host = "icon", noNone = true,
                toShared = function(v) return ROT_TO_SHARED[v] end,
                fromShared = function(i) return SHARED_TO_ROT[i] end,
                order = { "pixel", "shape", "button", "autocast", "gcd", "modern", "classic" },
                extras = { { value = "blizzard", label = "Blizzard Default" }, { value = "solid", label = "Solid Border", colored = true } },
                caps = { mode = true, params = true, bg = true }, thicknessMax = 8,
                defaultColor = { r = 1, g = 0, b = 0 },
                -- Off and locked while the highlight cannot show.
                isOff = RotationHelperOff, disabled = RotationHelperOff, disabledTooltip = RotationLockTip,
                onChange = function() if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end end,
                get = function(f)
                    local c = CdmBars(); if not c then return nil end
                    if f == "style" then return c.rotationAssistStyle or "blizzard"
                    elseif f == "mode" then return c.rotationAssistColorMode or "default"
                    elseif f == "color" then
                        return c.rotationAssistColorR or 1, c.rotationAssistColorG or 0, c.rotationAssistColorB or 0
                    elseif f == "lines" then return c.rotationAssistLines
                    -- The renderer draws 3 when unset and allows up to 8 (thicknessMax).
                    elseif f == "thickness" then return c.rotationAssistThickness or 3
                    elseif f == "speed" then return c.rotationAssistSpeed
                    elseif f == "bg" then return c.rotationAssistBackground == true
                    elseif f == "bgColor" then return ColorKeys(c, "rotationAssistBackgroundColor")
                    end
                end,
                set = function(f, a, b2, c2)
                    local c = CdmBars(); if not c then return end
                    if f == "style" then c.rotationAssistStyle = a
                    elseif f == "mode" then c.rotationAssistColorMode = a
                    elseif f == "color" then c.rotationAssistColorR, c.rotationAssistColorG, c.rotationAssistColorB = a, b2, c2
                    elseif f == "lines" then c.rotationAssistLines = a
                    elseif f == "thickness" then c.rotationAssistThickness = a
                    elseif f == "speed" then c.rotationAssistSpeed = a
                    elseif f == "bg" then c.rotationAssistBackground = a
                    elseif f == "bgColor" then c.rotationAssistBackgroundColor = { r = a, g = b2, b = c2 }
                    end
                end,
            }
            return desc
        end
        -- The CDM Bars page's Rotation Assist cog reuses the shared rows.
        ns._CDM_RotationGlowDesc = RotationDesc
        -- Which glow rows a bar shows on the CDM Bars page; the Glows page lists
        -- exactly these. EXTRAS (Pandemic Glow): not custom aura bars or FocusKick.
        function ns.CDM_BarHasExtras(bd)
            return bd.barType ~= "custom_buff" and bd.key ~= "focuskick"
        end
        -- Pixel Glow Thickness row: cooldown and utility bars (buff bars use Buff Glow).
        function ns.CDM_BarHasPixelRow(bd)
            return not (ns.IsBarBuffFamily and ns.IsBarBuffFamily(bd))
                and (bd.barType == "cooldowns" or bd.barType == "utility")
        end

        do
            -- Open Settings targets: the CDM Bars page with the bar selected first.
            local function BarNav(key, section, highlight)
                return { page = PAGE_CDM_BARS, section = section, highlight = highlight,
                    preSelect = function() if EllesmereUI._setCDMBar then EllesmereUI._setCDMBar(key) end end }
            end
            -- Rotation Assist, listed per page build: while the highlight cannot
            -- show, the row reads None and Off, stays locked and opens Show
            -- Rotation Helper (the style has no None of its own, so only that
            -- listing offers one). Not on Forever: no Assisted Highlight there.
            if not EllesmereUI.IS_FOREVER then
                local rotOn = { { label = "Rotation Assist Style", desc = RotationDesc() } }
                local offDesc = RotationDesc()
                offDesc.noNone = nil
                -- Locked for good: a cached page keeps this listing until it rebuilds.
                offDesc.disabled = function() return true end
                local rotOff = { { label = "Rotation Assist Style", desc = offDesc,
                    nav = BarNav("cooldowns", "EXTRAS", "Show Rotation Helper") } }
                -- sub: the group heading on the Glows page card (General, one
                -- per bar, Tracking Bars); labels stay short beneath it.
                GO.RegisterSite({ id = "cdm_rotation", label = "Rotation Assist Style", group = "bar",
                    sub = EllesmereUI.L("General"),
                    module = "EllesmereUICooldownManager",
                    page = PAGE_CDM_BARS, section = "EXTRAS", highlight = "Rotation Assist Style",
                    preSelect = BarNav("cooldowns").preSelect,
                    list = function() return RotationHelperOff() and rotOff or rotOn end })
            end
            -- Per-icon glows and Bar Glows stay per entry (never template targets):
            -- hint entries counting the active spec's own settings. Read-only, raw
            -- entry values only (inherited bar tiers and explicit false don't count).
            -- Style keys only: a glow style is a number > 0 (0 = explicit None); a
            -- color alone draws nothing.
            local PER_ICON_GLOW_KEYS = { "procGlow", "activeGlow", "maxStacksGlow", "buffGlow" }
            local PER_ICON_FAMILIES = { "cooldowns", "buffs" }
            local function HasOwnGlow(e)
                if type(e) ~= "table" then return false end
                for i = 1, #PER_ICON_GLOW_KEYS do
                    local v = rawget(e, PER_ICON_GLOW_KEYS[i])
                    if type(v) == "number" and v > 0 then return true end
                end
                local cse = rawget(e, "cdStateEffect")
                return type(cse) == "string"
                    and (cse == "glowOnCD" or cse:find("GlowReady", 1, true) ~= nil)
            end
            local function CountPerIconGlows()
                local n = 0
                for _, fam in ipairs(PER_ICON_FAMILIES) do
                    local st = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore(fam)
                    for _, e in pairs(st or {}) do
                        if HasOwnGlow(e) then n = n + 1 end
                    end
                end
                -- Preset and custom spells keep theirs in the profile-level
                -- customActiveStates store (read directly: its getter creates it).
                local prof = ns.ECME and ns.ECME.db and ns.ECME.db.profile
                for _, e in pairs((prof and prof.customActiveStates) or {}) do
                    if HasOwnGlow(e) then n = n + 1 end
                end
                return n
            end
            GO.RegisterSite({ id = "cdm_per_icon", label = "Per-Icon Glows",
                module = "EllesmereUICooldownManager", page = PAGE_CDM_BARS,
                info = {
                    glyph = "icon",
                    tooltip = "Proc Glow, Active State Glow, Max Charges Glow, Buff Glow, CD Ready Glow and Glow Effect Color can be set per icon: right-click an icon in the CDM Bars preview. Counted for the current specialization; the template never changes them.",
                    text = function() return EllesmereUI.Lf("%d icon(s) with their own glow settings", CountPerIconGlows()) end,
                } })
            GO.RegisterSite({ id = "cdm_bar_glows", label = "Bar Glows",
                module = "EllesmereUICooldownManager", page = PAGE_BAR_GLOWS,
                info = {
                    glyph = "bar",
                    tooltip = "Glows on action bar and CDM buttons while a tracked buff is active (or missing), set per entry on the Bar Glows page. Counted for the current specialization; the template never changes them.",
                    text = function()
                        -- Read-only: ns.GetBarGlows would create the spec's table.
                        local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                        local bg = specKey and sp and sp[specKey] and sp[specKey].barGlows
                        local n = 0
                        for _, list in pairs((bg and bg.assignments) or {}) do
                            if type(list) == "table" then n = n + #list end
                        end
                        if bg and bg.enabled == false then return EllesmereUI.Lf("%d bar glow(s), turned off", n) end
                        return EllesmereUI.Lf("%d bar glow(s)", n)
                    end,
                } })
            -- Per-bar sites are rebuilt on every page build (bars come and go).
            GO.RegisterSite({ id = "cdm_bars", label = "Cooldown Manager Bars", group = "bar",
                module = "EllesmereUICooldownManager",
                list = function()
                    local out = {}
                    local c = CdmBars()
                    for _, bd in ipairs((c and c.bars) or {}) do
                        -- Ghost and custom buff bars stay out, like the pandemic sync.
                        if not bd.isGhostBar and bd.barType ~= "custom_buff" then
                            local name = EllesmereUI.L(bd.name or bd.key or "?")
                            if ns.CDM_BarHasExtras(bd) then
                                out[#out + 1] = { label = "Pandemic Glow", sub = name, desc = PandemicDesc(function() return bd end),
                                    nav = BarNav(bd.key, "EXTRAS", "Pandemic Glow") }
                            end
                            if ns.IsBarBuffFamily and ns.IsBarBuffFamily(bd) then
                                out[#out + 1] = { label = "Buff Glow", sub = name, desc = BuffGlowDesc(function() return bd end),
                                    nav = BarNav(bd.key, "ICON DISPLAY", "Buff Glow") }
                            elseif ns.CDM_BarHasPixelRow(bd) then
                                out[#out + 1] = { label = "Pixel Glow", sub = name, desc = PixelParamsDesc(bd),
                                    nav = BarNav(bd.key, "ICON DISPLAY", "Pixel Glow Thickness") }
                            end
                        end
                    end
                    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
                    local tbbSub = EllesmereUI.L("Tracking Bars") .. " - " .. EllesmereUI.L("Pandemic Glow")
                    for i, bd in ipairs((tbb and tbb.bars) or {}) do
                        out[#out + 1] = { label = bd.name or "?", sub = tbbSub,
                            desc = TbbDesc(function() return bd end, RebuildTBB),
                            nav = { page = PAGE_BUFF_BARS, section = "EXTRAS", highlight = "Pandemic Glow",
                                preSelect = function() if ns._TBBSelectBar then ns._TBBSelectBar(i) end end } }
                    end
                    return out
                end })
        end
    end

    -- Cross-surface pandemic-glow sync (CDM bars + Nameplates) lives in CDM core as
    -- ApplyPandemicGlowToAll/IsPandemicGlowSyncedToAll (best-effort, name-based so styles
    -- never shift across surfaces); callers build a payload via PandemicPayloadFrom*.

    -- Check if a specific bar target uses a custom shape (not "none"/"cropped").
    -- barIdx can be a number 1-8 (action bar) or a string (CDM bar key).
    local function BarHasCustomShape(barIdx)
        barIdx = NormalizeSelectedBar(barIdx)
        if type(barIdx) == "string" then
            local cdmBd = ns.barDataByKey and ns.barDataByKey[barIdx]
            if cdmBd and cdmBd.iconShape and cdmBd.iconShape ~= "none" and cdmBd.iconShape ~= "cropped" then
                return true
            end
            return false
        end
        local barKeys = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
        local barKey = barKeys[barIdx]
        if not barKey then return false end
        local ok, EAB = pcall(EllesmereUI.Lite.GetAddon, "EllesmereUIActionBars")
        if ok and EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars then
            local s = EAB.db.profile.bars[barKey]
            if s and s.buttonShape and s.buttonShape ~= "none" and s.buttonShape ~= "cropped" then
                return true
            end
        end
        return false
    end

    -- Preview glow state tracking
    local _bgPreviewGlowActive = {}
    local _bgPreviewGlowOverlays = {}
    local _bgSpellPickerMenu

    EllesmereUI:RegisterOnHide(function()
        if _bgSpellPickerMenu then _bgSpellPickerMenu:Hide() end
    end)

    local function ShowBarGlowSpellPicker(anchorFrame, barIdx, btnIdx, onChanged, overrideAssignKey)
        local bg = ns.GetBarGlows()
        local assignKey = overrideAssignKey or (barIdx .. "_" .. btnIdx)
        local buffList = bg.assignments[assignKey] or {}

        local assignedSet = {}
        for _, entry in ipairs(buffList) do
            if entry.spellID then assignedSet[entry.spellID] = true end
        end

        -- Immediate update: save picker position, rebuild, re-anchor
        local function ImmediateUpdate()
            if not onChanged then return end
            local menuRef = _bgSpellPickerMenu
            if not menuRef then onChanged(); return end
            -- Save absolute screen position before rebuild
            local cx, cy = menuRef:GetCenter()
            local mScale = menuRef:GetEffectiveScale()
            onChanged()
            -- Re-anchor to saved absolute position so page rebuild doesn't shift us
            menuRef = _bgSpellPickerMenu
            if menuRef and menuRef:IsShown() then
                menuRef:ClearAllPoints()
                local uiScale = UIParent:GetEffectiveScale()
                menuRef:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * mScale / uiScale, cy * mScale / uiScale)
            end
        end

        -- The shared Bar Glows buff menu (EUI_CooldownManager_BarGlowConditions.lua):
        -- one reused frame, the boxes repainted after each toggle.
        local menu = ns.ShowBarGlowBuffMenu(anchorFrame, {
            isChecked = function(sid) return assignedSet[sid] end,
            onClick = function(sp, refreshChecks)
                if assignedSet[sp.spellID] then
                    assignedSet[sp.spellID] = nil
                    for idx = #buffList, 1, -1 do
                        if buffList[idx].spellID == sp.spellID then
                            table.remove(buffList, idx)
                            break
                        end
                    end
                else
                    -- Add with defaults
                    assignedSet[sp.spellID] = true
                    local newEntry = {
                        spellID = sp.spellID,
                        glowStyle = 1,
                        mode = "ACTIVE",
                        onlyInCombat = false,
                    }
                    local prefix = BAR_BUTTON_PREFIXES[barIdx]
                    local realBtn = prefix and _G[prefix .. btnIdx]
                    if realBtn and realBtn.action then
                        local aType, aID = GetActionInfo(realBtn.action)
                        if aType == "spell" and aID then
                            newEntry.actionSpellID = aID
                        end
                    end
                    buffList[#buffList + 1] = newEntry
                end
                refreshChecks()
                bg.assignments[assignKey] = buffList
                Refresh()
                ImmediateUpdate()
            end,
        })
        if not menu then return end
        menu._btnIdx = btnIdx
        _bgSpellPickerMenu = menu
    end

    ---------------------------------------------------------------------------
    --  Bar Glows: BuildBarGlowsPage
    ---------------------------------------------------------------------------
    local _glowHeaderBuilder  -- stored for cache restore via getHeaderBuilder
    local _glowSelectedButton = nil  -- UI-only selection state (not saved)
    local _glowBtnFrames = {}  -- button frames from last header build, indexed by button number

    local function BuildBarGlowsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local bg = ns.GetBarGlows()
        local curBar = NormalizeSelectedBar(bg.selectedBar or "cooldowns")
        local curBtn = _glowSelectedButton  -- nil = no selection

        local ACCENT = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

        -------------------------------------------------------------------
        --  Content Header: Live Action Bar Preview (replica of BuildLivePreview)
        -------------------------------------------------------------------
        EllesmereUI:ClearContentHeader()

        -- Stop any lingering preview glows
        for idx, ov in pairs(_bgPreviewGlowOverlays) do
            ns.StopNativeGlow(ov)
        end
        wipe(_bgPreviewGlowOverlays)
        wipe(_bgPreviewGlowActive)

        _glowHeaderBuilder = function(headerFrame, width)
            -- Re-read current state each build
            local bgData = ns.GetBarGlows()
            local sel = NormalizeSelectedBar(bgData.selectedBar or 1)
            local isCDMBar = (type(sel) == "string")
            -- For CDM bars: cdmBarKey is the bar key string. For action bars:
            -- barIdx is the integer 1-8 used for prefix lookup.
            local cdmBarKey = isCDMBar and sel or nil
            local barIdx = isCDMBar and nil or sel
            local ok, EAB_ADDON = pcall(EllesmereUI.Lite.GetAddon, "EllesmereUIActionBars")
            if not ok then EAB_ADDON = nil end
            local barKeyList = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
            local barKeyStr = (not isCDMBar) and (barKeyList[barIdx] or "MainBar") or nil
            local barSettings = nil
            if barKeyStr and EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile then
                barSettings = EAB_ADDON.db.profile.bars[barKeyStr]
            end

            -- CDM bars: count icons dynamically; action bars: always 12.
            -- Overflow-diverted icons are tail-appended to the target's array
            -- and excluded here, so every native icon keeps its slot index
            -- (stable glow-assignment fallback keys).
            local NUM_BUTTONS = 12
            if isCDMBar and ns.cdmBarIcons and ns.cdmBarIcons[cdmBarKey] then
                NUM_BUTTONS = 0
                for _, ic in ipairs(ns.cdmBarIcons[cdmBarKey]) do
                    if not (ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(ic)) then
                        NUM_BUTTONS = NUM_BUTTONS + 1
                    end
                end
                if NUM_BUTTONS == 0 then NUM_BUTTONS = 1 end
            end
            local prefix = (not isCDMBar) and (BAR_BUTTON_PREFIXES[barIdx] or "ActionButton") or nil

            -- Dropdown at top
            local DD_H = 34
            local ddW  = 350
            local DDS    = EllesmereUI.DD_STYLE
            local mBgR   = DDS.BG_R;  local mBgG  = DDS.BG_G;  local mBgB  = DDS.BG_B
            local mBgA   = DDS.BG_A;  local mBgHA = DDS.BG_HA
            local mBrdA  = DDS.BRD_A; local mBrdHA = DDS.BRD_HA or 0.30
            local mTxtA  = DDS.TXT_A; local mTxtHA = DDS.TXT_HA or 1
            local hlA    = DDS.ITEM_HL_A; local selA = DDS.ITEM_SEL_A
            local tDimR  = EllesmereUI.TEXT_DIM_R or 0.7
            local tDimG  = EllesmereUI.TEXT_DIM_G or 0.7
            local tDimB  = EllesmereUI.TEXT_DIM_B or 0.7
            local tDimA  = EllesmereUI.TEXT_DIM_A or 0.85
            local ITEM_H = 26

            local ddBtn = CreateFrame("Button", nil, headerFrame)
            PP.Size(ddBtn, ddW, DD_H)
            ddBtn:SetFrameLevel(headerFrame:GetFrameLevel() + 5)
            local ddBg  = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints(); ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, mBrdA, EllesmereUI.PanelPP)
            local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
            ddLbl:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            ddLbl:SetAlpha(mTxtA); ddLbl:SetJustifyH("LEFT")
            ddLbl:SetWordWrap(false); ddLbl:SetMaxLines(1)
            ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
            local ddArrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, EllesmereUI.PanelPP)
            ddLbl:SetPoint("RIGHT", ddArrow, "LEFT", -5, 0)
            ddLbl:SetText(GetBGTargetLabel(sel))

            local ddMenu
            local function BuildDDMenu()
                if ddMenu then ddMenu:Hide(); ddMenu = nil end
                local menu = CreateFrame("Frame", nil, UIParent)
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(300)
                menu:SetClampedToScreen(true)
                menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                menu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
                local bg2 = menu:CreateTexture(nil, "BACKGROUND")
                bg2:SetAllPoints(); bg2:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)
                local mH = 4
                local targets = BuildBGTargetList()
                for _, t in ipairs(targets) do
                    local entryVal = t.value
                    local item = CreateFrame("Button", nil, menu)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local iLbl = item:CreateFontString(nil, "OVERLAY")
                    iLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetJustifyH("LEFT"); iLbl:SetWordWrap(false); iLbl:SetMaxLines(1)
                    iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                    iLbl:SetText(t.label)
                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints(); iHl:SetColorTexture(1, 1, 1, 1)
                    local isCurrent = (entryVal == sel)
                    iHl:SetAlpha(isCurrent and selA or 0)
                    item:SetScript("OnEnter", function() iLbl:SetTextColor(1,1,1,1); iHl:SetAlpha(hlA) end)
                    item:SetScript("OnLeave", function() iLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); iHl:SetAlpha(isCurrent and selA or 0) end)
                    item:SetScript("OnClick", function()
                        menu:Hide()
                        bgData.selectedBar = entryVal
                        bgData.selectedButton = nil
                        _glowSelectedButton = nil
                        EllesmereUI:RefreshPage(true)
                    end)
                    mH = mH + ITEM_H
                end
                menu:SetHeight(mH + 4)
                menu:SetScript("OnUpdate", function(m)
                    if not m:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then m:Hide() end
                end)
                menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
                menu:Show()
                ddMenu = menu
            end

            ddBtn:SetScript("OnEnter", function() ddLbl:SetAlpha(mTxtHA); ddBrd:SetColor(1,1,1,mBrdHA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgHA) end)
            ddBtn:SetScript("OnLeave", function()
                if ddMenu and ddMenu:IsShown() then return end
                ddLbl:SetAlpha(mTxtA); ddBrd:SetColor(1,1,1,mBrdA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgA)
            end)
            ddBtn:SetScript("OnClick", function() if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildDDMenu() end end)
            ddBtn:HookScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)
            PP.Point(ddBtn, "TOP", headerFrame, "TOP", 0, -20)

            -- Button grid below dropdown
            local gridTopY = -(20 + DD_H + 20)

            local realBtnW, realBtnH = 36, 36
            if isCDMBar then
                local cdmBd = ns.barDataByKey and ns.barDataByKey[cdmBarKey]
                if cdmBd then
                    realBtnW = cdmBd.iconSize or 36
                    realBtnH = realBtnW
                end
                -- The live icon's on-screen size (width/height match, UI scale) in this panel's scale
                local liveW = ns.BarGlowPreviewIconSize(ns.cdmBarIcons and ns.cdmBarIcons[cdmBarKey], headerFrame)
                if liveW then realBtnW, realBtnH = liveW, liveW end
            else
                local btn1 = _G[prefix .. "1"]
                realBtnW = (btn1 and btn1:GetWidth() or 36)
                realBtnH = (btn1 and btn1:GetHeight() or 36)
            end
            if realBtnW < 1 then realBtnW = 36 end
            if realBtnH < 1 then realBtnH = 36 end

            -- Read bar size (no scale -- width/height based)
            local scaledBtnW = math.floor(realBtnW + 0.5)
            local scaledBtnH = math.floor(realBtnH + 0.5)

            -- CDM bar data reference (reused for shape, spacing, zoom, border)
            local cdmBd = isCDMBar and ns.barDataByKey and ns.barDataByKey[cdmBarKey] or nil

            -- Custom shape expansion
            local btnShape
            if isCDMBar then
                btnShape = (cdmBd and cdmBd.iconShape) or "none"
            else
                btnShape = (barSettings and barSettings.buttonShape) or "none"
            end
            if btnShape ~= "none" and btnShape ~= "cropped" then
                local shapeExp = 10
                scaledBtnW = scaledBtnW + shapeExp
                scaledBtnH = scaledBtnH + shapeExp
            end
            if btnShape == "cropped" then
                scaledBtnH = math.floor(scaledBtnH * (isCDMBar and ns.CdmCropFactor(cdmBd) or 0.80) + 0.5)
            end

            local spacing = isCDMBar and ((cdmBd and cdmBd.spacing) or 2) or ((barSettings and barSettings.buttonPadding) or 2)
            local scaledPad = spacing

            -- How many buttons visible
            local numVisible = NUM_BUTTONS
            if not isCDMBar and barSettings then
                local ov = barSettings.overrideNumIcons
                if ov and ov > 0 and ov < numVisible then numVisible = ov end
            end

            -- Read zoom
            local zoom = isCDMBar and ((cdmBd and cdmBd.iconZoom) or 0.08) or (((barSettings and barSettings.iconZoom) or 5.5) / 100)
            local square = (not isCDMBar) and EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile.squareIcons

            -- Read border settings
            local brdSize = 0
            local brdColor, brdClassColor
            if isCDMBar and cdmBd then
                brdSize = cdmBd.borderSize or 1
                -- This preview draws a solid border, so an exact size (borderSizePx)
                -- shows here only while the bar's style is Solid.
                local cdmTex = cdmBd.borderTexture or "solid"
                local cdmPx = EllesmereUI.BorderPx(cdmBd.borderSizePx, brdSize, cdmTex)
                if cdmPx and cdmTex == "solid" then brdSize = cdmPx end
                brdColor = { r = cdmBd.borderR or 0, g = cdmBd.borderG or 0, b = cdmBd.borderB or 0, a = cdmBd.borderA or 1 }
                brdClassColor = cdmBd.borderClassColor
            elseif not isCDMBar and barSettings then
                -- None..Strong are the steps 0-4; an unknown or numeric value renders as Thin, as the bar does.
                local thickness = barSettings.borderThickness or "thin"
                brdSize = EllesmereUI.BORDER_STEP_OF_LABEL[thickness] or 1
                local abTex = barSettings.borderTexture or "solid"
                local abPx = EllesmereUI.BorderPx(barSettings.borderThicknessPx, brdSize, abTex)
                if abPx and abTex == "solid" then brdSize = abPx end
                brdColor = barSettings.borderColor
                brdClassColor = barSettings.borderClassColor
            end
            if not brdColor then brdColor = { r = 0, g = 0, b = 0, a = 1 } end

            local gridW = numVisible * scaledBtnW + (numVisible - 1) * scaledPad
            -- Live-sized CDM icons can outgrow the preview width: shrink to fit
            if isCDMBar and width and width > 0 and gridW > width then
                local f = width / gridW
                scaledBtnW = math.floor(scaledBtnW * f)
                scaledBtnH = math.floor(scaledBtnH * f)
                scaledPad = scaledPad * f
                gridW = numVisible * scaledBtnW + (numVisible - 1) * scaledPad
            end
            local startX = math.max(0, math.floor((width - gridW) / 2))
            local startY = gridTopY

            local UnsnapTex = EllesmereUI.PP.DisablePixelSnap

            -- Clear button frame refs from previous build
            wipe(_glowBtnFrames)

            for i = 1, NUM_BUTTONS do
                if i > numVisible then break end

                local xOff = startX + (i - 1) * (scaledBtnW + scaledPad)
                local isSelected = (_glowSelectedButton == i)

                local bf = CreateFrame("Button", nil, headerFrame)
                bf:SetSize(scaledBtnW, scaledBtnH)
                bf:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", xOff, startY)
                _glowBtnFrames[i] = bf
                bf:RegisterForClicks("LeftButtonUp", "RightButtonDown")

                local bgTex = bf:CreateTexture(nil, "BACKGROUND")
                bgTex:SetAllPoints()
                bgTex:SetColorTexture(0.077, 0.068, 0.058, 0.5)

                -- Icon from real action button or CDM bar icon
                local realBtn
                if isCDMBar then
                    local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[cdmBarKey]
                    realBtn = cdmIcons and cdmIcons[i]
                    -- Native equipment frames are parked off the live bar (items
                    -- are preset-lane-only), but the icon registry can still hold
                    -- one from a prior pass -- never replicate it into the preview.
                    if realBtn and realBtn.cooldownID and C_CooldownViewer
                        and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local rinfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(realBtn.cooldownID)
                        if rinfo and rinfo.equipSlot then realBtn = nil end
                    end
                else
                    realBtn = prefix and _G[prefix .. i]
                end
                -- Non-glowable icons (see IsNonGlowableCDMIcon) are left inert -- no hover, clicks do nothing.
                local nonGlowable = isCDMBar and IsNonGlowableCDMIcon(realBtn)
                local _rbTex = realBtn and ((ns._hookFrameData[realBtn] and ns._hookFrameData[realBtn].tex) or realBtn._tex)
                local hasAction = realBtn and ((realBtn.icon and realBtn.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture()))
                local iconTex = bf:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                UnsnapTex(iconTex)
                if hasAction then
                    local srcTex = (realBtn.icon and realBtn.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture())
                    iconTex:SetTexture(srcTex)
                    -- Desaturate (preview only) non-glowable icons so it's visually clear they're not assignable.
                    if nonGlowable then iconTex:SetDesaturated(true) end
                    local z = zoom
                    if btnShape == "cropped" then
                        local t = isCDMBar and ns.CdmCropTrim(cdmBd) or 0.10
                        iconTex:SetTexCoord(z, 1 - z, z + t, 1 - z - t)
                    elseif z > 0 or square then
                        iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
                    else
                        iconTex:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    iconTex:SetColorTexture(0, 0, 0, 0.5)
                end

                -- Shape mask
                local SHAPE_MASKS = isCDMBar and ns.CDM_SHAPE_MASKS or AB_SHAPE_MASKS
                local SHAPE_BORDERS = isCDMBar and ns.CDM_SHAPE_BORDERS or AB_SHAPE_BORDERS
                if btnShape ~= "none" and btnShape ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[btnShape] then
                    local mask = bf:CreateMaskTexture()
                    mask:SetAllPoints(bf)
                    mask:SetTexture(SHAPE_MASKS[btnShape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    iconTex:AddMaskTexture(mask)
                    bgTex:AddMaskTexture(mask)
                    -- Store shape metadata for glow preview (StartNativeGlow reads these)
                    bf._shapeApplied = true
                    bf._shapeName = btnShape
                    bf._shapeMask = mask
                    -- Shape border (always created for hover/accent tinting; invisible when brdSize == 0)
                    if SHAPE_BORDERS and SHAPE_BORDERS[btnShape] then
                        local sbt = bf:CreateTexture(nil, "OVERLAY", nil, 6)
                        sbt:SetAllPoints(bf)
                        sbt:SetTexture(SHAPE_BORDERS[btnShape])
                        -- Direct ref for accent/hover tinting below. Never locate via a GetRegions
                        -- scan -- a freshly tracked CD's icon region carries secret values, and
                        -- GetDrawLayer comparisons on it error out mid page-build.
                        bf._sbt = sbt
                        if brdSize > 0 then
                            local cr, cg, cb = brdColor.r, brdColor.g, brdColor.b
                            if brdClassColor then
                                local _, ct = UnitClass("player")
                                if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                            end
                            sbt:SetVertexColor(cr, cg, cb, brdColor.a or 1)
                        else
                            sbt:SetVertexColor(0, 0, 0, 0)
                        end
                    end
                elseif brdSize > 0 then
                    -- Square borders via unified PP system
                    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                    if brdClassColor then
                        local _, ct = UnitClass("player")
                        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                    end
                    local PP = EllesmereUI and EllesmereUI.PP
                    if PP then PP.CreateBorder(bf, cr, cg, cb, ca, brdSize, "OVERLAY", 7) end
                end

                -- Accent border for buttons that have assignments
                local assignKey
                if isCDMBar and realBtn and realBtn.cooldownID then
                    assignKey = "cdm_" .. realBtn.cooldownID
                else
                    assignKey = barIdx .. "_" .. i
                end
                bf._assignKey = assignKey
                local assigns = bgData.assignments[assignKey]
                local hasAssign = assigns and #assigns > 0

                -- Pre-create accent border on every button (hidden unless needed)
                local accentCont = CreateFrame("Frame", nil, bf)
                accentCont:SetAllPoints()
                accentCont:SetFrameLevel(bf:GetFrameLevel() + 2)
                local PP2 = EllesmereUI and EllesmereUI.PP

                -- Active button gets accent border; assigned (non-active) buttons get white border
                -- For custom shapes, tint the shape border instead of showing square PP borders
                local isCustomShape = btnShape ~= "none" and btnShape ~= "cropped" and btnShape ~= "square" and btnShape ~= "csquare"
                    and SHAPE_MASKS and SHAPE_MASKS[btnShape]
                local accentBrd
                if not isCustomShape then
                    if isSelected then
                        accentBrd = PP2 and PP2.CreateBorder(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1, 2, "OVERLAY", 7)
                    else
                        accentBrd = PP2 and PP2.CreateBorder(accentCont, 1, 1, 1, 0.6, 2, "OVERLAY", 7)
                    end
                    if accentBrd then accentBrd:Hide() end
                end

                -- Show active state
                if isSelected then
                    if isCustomShape then
                        if bf._sbt then
                            bf._sbt:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                        end
                    elseif accentBrd then
                        accentBrd:Show()
                    end
                end

                -- Show white border for assigned buttons (even if not active)
                if hasAssign and not isSelected then
                    if isCustomShape then
                        if bf._sbt then
                            bf._sbt:SetVertexColor(1, 1, 1, 0.6)
                        end
                    elseif accentBrd then
                        accentBrd:Show()
                    end
                end

                -- Store refs so click handler can activate inline
                bf._accentBrd = accentBrd
                bf._accentCont = accentCont

                -- Button alpha: unassigned = 50%, assigned/active = 100%
                if isSelected or hasAssign then
                    bf:SetAlpha(1)
                else
                    bf:SetAlpha(0.50)
                end

                -- Hover swaps border to accent; active button needs none (already accent)
                bf._shapeBorderTex = isCustomShape and bf._sbt or nil
                local origBrdR, origBrdG, origBrdB, origBrdA = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                if isCDMBar and cdmBd then
                    origBrdR = cdmBd.borderR or 0
                    origBrdG = cdmBd.borderG or 0
                    origBrdB = cdmBd.borderB or 0
                    origBrdA = (cdmBd.borderSize or 1) > 0 and (cdmBd.borderA or 1) or 0
                elseif brdSize == 0 then
                    origBrdA = 0
                end
                if not isSelected and not nonGlowable then
                    if hasAssign then
                        bf:SetScript("OnEnter", function()
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            elseif PP2 and accentCont then
                                PP2.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            end
                        end)
                        bf:SetScript("OnLeave", function()
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(1, 1, 1, 0.6)
                            elseif PP2 and accentCont then
                                PP2.SetBorderColor(accentCont, 1, 1, 1, 0.6)
                            end
                        end)
                    else
                        bf:SetScript("OnEnter", function()
                            bf:SetAlpha(0.55)
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            else
                                if PP2 and accentCont then PP2.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                                if accentBrd then accentBrd:Show() end
                            end
                        end)
                        bf:SetScript("OnLeave", function()
                            bf:SetAlpha(0.50)
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(origBrdR, origBrdG, origBrdB, origBrdA)
                            else
                                if accentBrd then accentBrd:Hide() end
                            end
                        end)
                    end
                end

                -- Helper: visually activate this button without a full rebuild
                local function ActivateInline()
                    local PP3 = EllesmereUI and EllesmereUI.PP
                    -- Clear previous active button visuals
                    if headerFrame._activeBtnRef and headerFrame._activeBtnRef ~= bf then
                        local prev = headerFrame._activeBtnRef
                        -- Revert border: if prev has assignments, switch to white; otherwise hide
                        local prevKey = prev._assignKey or (barIdx .. "_" .. (prev._btnIdx or 0))
                        local prevAssigns = bgData.assignments[prevKey]
                        local prevHasAssign = prevAssigns and #prevAssigns > 0
                        if prevHasAssign then
                            if PP3 and prev._accentCont then PP3.SetBorderColor(prev._accentCont, 1, 1, 1, 0.6) end
                        else
                            if prev._accentBrd then prev._accentBrd:Hide() end
                            prev:SetAlpha(0.50)
                            -- Restore hover scripts
                            prev:SetScript("OnEnter", function()
                                prev:SetAlpha(0.55)
                                if PP3 and prev._accentCont then PP3.SetBorderColor(prev._accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                                if prev._accentBrd then prev._accentBrd:Show() end
                            end)
                            prev:SetScript("OnLeave", function()
                                prev:SetAlpha(0.50)
                                if prev._accentBrd then prev._accentBrd:Hide() end
                            end)
                        end
                    end
                    -- Show this button as active with accent color + full alpha
                    bf:SetAlpha(1)
                    if PP3 and accentCont then PP3.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                    if accentBrd then accentBrd:Show() end
                    -- Remove hover toggle since border is now permanent
                    bf:SetScript("OnEnter", nil)
                    bf:SetScript("OnLeave", nil)
                    headerFrame._activeBtnRef = bf
                end
                bf._btnIdx = i

                -- Track the initially active button
                if isSelected then headerFrame._activeBtnRef = bf end

                -- Left click: select this button. Right click: select + toggle spell picker.
                bf:SetScript("OnClick", function(self, button)
                    -- Non-glowable icons ignore both clicks so no glow can be added.
                    if nonGlowable then return end
                    local pickerOpen = _bgSpellPickerMenu and _bgSpellPickerMenu:IsShown()
                    local pickerOnThis = pickerOpen and _bgSpellPickerMenu._btnIdx == i

                    if button == "LeftButton" then
                        -- Close picker first if open (before rebuild destroys anchor)
                        if pickerOpen then _bgSpellPickerMenu:Hide() end
                        _glowSelectedButton = i
                        ActivateInline()
                        EllesmereUI:RefreshPage(true)
                    elseif button == "RightButton" then
                        if pickerOnThis then
                            _bgSpellPickerMenu:Hide()
                            return
                        end
                        if pickerOpen then _bgSpellPickerMenu:Hide() end
                        _glowSelectedButton = i
                        ActivateInline()
                        EllesmereUI:RefreshPage(true)
                        C_Timer.After(0, function()
                            local newBf = _glowBtnFrames[i]
                            if newBf then
                                ShowBarGlowSpellPicker(newBf, barIdx, i, function()
                                    _glowSelectedButton = i
                                    EllesmereUI:RefreshPage(true)
                                end, newBf._assignKey)
                            end
                        end)
                    end
                end)
            end

            -- Tip text below the button grid
            local tipFS = headerFrame:CreateFontString(nil, "OVERLAY")
            tipFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            tipFS:SetTextColor(1, 1, 1, 0.70)
            tipFS:SetPoint("TOP", headerFrame, "TOP", 0, -(20 + DD_H + 20 + scaledBtnH + 20))
            tipFS:SetText(EllesmereUI.L("Left click a button to edit its glow, right click to add a new glow"))

            return 20 + DD_H + 20 + scaledBtnH + 20 + 14 + 15
        end

        EllesmereUI:SetContentHeader(_glowHeaderBuilder)

        -- Live-updates preview icons on action-bar paging (stance/mount/vehicle). Skipped
        -- during a hidden search pre-build: cleanup relies on parent's OnHide, which may
        -- never fire under an already-hidden pre-build wrapper -- the listener (and its
        -- RefreshPage(true)) would leak for the session, and there's nothing to preview during indexing anyway.
        if not EllesmereUI._prebuilding then
            local pageListener = CreateFrame("Frame")
            local pagePending = false
            pageListener:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
            pageListener:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
            pageListener:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
            pageListener:SetScript("OnEvent", function()
                if pagePending then return end
                pagePending = true
                C_Timer.After(0.15, function()
                    pagePending = false
                    EllesmereUI:RefreshPage(true)
                end)
            end)
            parent:HookScript("OnHide", function()
                pageListener:UnregisterAllEvents()
            end)
        end

        -------------------------------------------------------------------
        --  Scrollable content area
        -------------------------------------------------------------------

        _, h = W:Spacer(parent, y, 8);  y = y - h

        -- A selected slot that is (now) non-glowable falls back to the hint instead of glow settings.
        if curBtn and type(curBar) == "string" then
            local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[curBar]
            if IsNonGlowableCDMIcon(cdmIcons and cdmIcons[curBtn]) then
                curBtn = nil
            end
        end

        if not curBtn then
            local hintFrame = CreateFrame("Frame", nil, parent)
            hintFrame:SetSize(parent:GetWidth(), 40)
            hintFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
            local hintText = hintFrame:CreateFontString(nil, "OVERLAY")
            hintText:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            hintText:SetTextColor(0.5, 0.5, 0.5, 1)
            hintText:SetPoint("CENTER")
            hintText:SetText(EllesmereUI.L("Left click a button to edit its glow, right click to add a new glow"))
            y = y - 40
        else
            local assignKey
            local isCurCDM = (type(curBar) == "string")
            if isCurCDM then
                local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[curBar]
                local icon = cdmIcons and cdmIcons[curBtn]
                if icon and icon.cooldownID then
                    assignKey = "cdm_" .. icon.cooldownID
                end
            end
            if not assignKey then assignKey = curBar .. "_" .. curBtn end
            local buffList = bg.assignments[assignKey] or {}
            parent._showRowDivider = true

            if #buffList == 0 then
                _, h = W:Spacer(parent, y, 8);  y = y - h
                local emptyFrame = CreateFrame("Frame", nil, parent)
                emptyFrame:SetSize(parent:GetWidth(), 30)
                emptyFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
                local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
                emptyText:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                emptyText:SetTextColor(0.5, 0.5, 0.5, 1)
                emptyText:SetPoint("LEFT", 22, 0)
                emptyText:SetText(EllesmereUI.L("No buffs assigned. Right click a button in the preview to assign buffs."))
                y = y - 30
            else
                local glowLabels, glowOrder = GetGlowStyleValues()

                for aIdx, entry in ipairs(buffList) do
                    -- Collapse bar across the top of the glow; collapsed shows the buff
                    -- icon and name and skips the rows below.
                    local expanded
                    y, expanded = ns.BuildBarGlowHeader(parent, y, entry, aIdx)
                    if expanded then

                        -- Row 1: When (icon) <buff> is [Active] | And [buff] is [Active] (toggle)
                        -- (EUI_CooldownManager_BarGlowConditions.lua)
                        local removeAIdx = aIdx
                        y = ns.BuildBarGlowWhenRow(W, parent, y, entry, Refresh)

                        -- Helper: resolve current glow color and restart preview if active
                        local pvKey = assignKey .. "_" .. aIdx
                        local function RefreshPreviewGlow()
                            if not _bgPreviewGlowActive[pvKey] then return end
                            local ov = _bgPreviewGlowOverlays[pvKey]
                            if not ov then return end
                            local style = BarHasCustomShape(curBar) and 2 or (entry.glowStyle or 1)
                            local cr, cg, cb
                            if entry.colorMode == "class" then
                                local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                                cr, cg, cb = cc.r, cc.g, cc.b
                            elseif entry.colorMode == "custom" and entry.glowColor then
                                cr, cg, cb = entry.glowColor.r, entry.glowColor.g, entry.glowColor.b
                            end
                            ns.StopNativeGlow(ov)
                            -- Blackout reads its fill opacity from the extras; every other
                            -- style takes the shared panel extras.
                            ns.StartNativeGlow(ov, style, cr, cg, cb,
                                style == 8 and { panel = true, alpha = entry.glowAlpha } or EllesmereUI.Glows.PANEL_EXTRA)
                        end

                        -- At Stacks (toggle) + gear (Comparison / Stack Count), paired with
                        -- Glow Type so every row stays filled. Same operator set and same
                        -- fail-open bias as the per-icon Glow at Stacks feature (Stack Text
                        -- and Glows cog): an unknown/secret application count never blocks
                        -- the glow.
                        local stackRow
                        stackRow, h = W:DualRow(parent, y,
                            { type = "toggle", text = "At Stacks",
                              tooltip = "Only glow once the buff's stack count matches the comparison set via the gear.",
                              disabled = function() return entry.mode == "MISSING" end,
                              disabledTooltip = "Not available in Buff Missing mode",
                              getValue = function() return entry.stackEnabled == true end,
                              setValue = function(v)
                                  entry.stackEnabled = v or nil
                                  Refresh()
                                  EllesmereUI:RefreshPage()
                              end,
                            },
                            { type = "dropdown", text = "Glow Type",
                              values = glowLabels, order = glowOrder,
                              disabled = function() return BarHasCustomShape(curBar) end,
                              disabledTooltip = "This option is not available for custom shaped icons",
                              getValue = function()
                                  if BarHasCustomShape(curBar) then return 2 end
                                  return entry.glowStyle or 1
                              end,
                              setValue = function(v)
                                  entry.glowStyle = tonumber(v) or 1
                                  Refresh()
                                  RefreshPreviewGlow()
                                  EllesmereUI:RefreshPage()
                              end,
                            }
                        );  y = y - h
                        do
                            local rgn = stackRow._leftRegion
                            EllesmereUI.BuildInlineCog(rgn, {
                                title = "At Stacks",
                                disabled = function() return entry.mode == "MISSING" or not entry.stackEnabled end,
                                disabledTooltip = function()
                                    return entry.mode == "MISSING" and "This option is not available in Buff Missing mode" or "At Stacks"
                                end,
                                frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                                rows = {
                                    { type = "dropdown", label = "Comparison",
                                      values = { lt = "Below (<)", lte = "At Most (<=)", eq = "Exactly (=)", gte = "At Least (>=)", gt = "Above (>)" },
                                      order = { "lt", "lte", "eq", "gte", "gt" },
                                      get = function() return entry.stackOperator or "gte" end,
                                      set = function(v)
                                          entry.stackOperator = v ~= "gte" and v or nil
                                          Refresh()
                                      end },
                                    { type = "input", label = "Stack Count", inputWidth = 42, commitOnBlur = true,
                                      get = function() return tostring(tonumber(entry.stackThreshold) or 2) end,
                                      set = function(v)
                                          local t = math.floor(tonumber(v) or 2)
                                          if t < 1 then t = 1 end
                                          if t > 99 then t = 99 end
                                          entry.stackThreshold = t
                                          Refresh()
                                      end },
                                },
                            })
                        end

                        -- Eyeball preview toggle (on right region of the At Stacks / Glow Type row)
                        if not EllesmereUI._prebuilding then
                            local EYE_VIS   = EllesmereUI.EYE_VISIBLE_ICON
                            local EYE_INVIS = EllesmereUI.EYE_INVISIBLE_ICON
                            local leftRgn = stackRow._rightRegion
                            if leftRgn and leftRgn._control then
                                local eyeBtn = CreateFrame("Button", nil, leftRgn)
                                eyeBtn:SetSize(26, 26)
                                eyeBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
                                eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                                eyeBtn:SetAlpha(0.4)
                                local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                                eyeTex:SetAllPoints()
                                local function RefreshEye()
                                    eyeTex:SetTexture(_bgPreviewGlowActive[pvKey] and EYE_INVIS or EYE_VIS)
                                end
                                RefreshEye()
                                eyeBtn:SetScript("OnClick", function()
                                    local previewBtn = _glowBtnFrames[curBtn]
                                    if not previewBtn then return end
                                    if not _bgPreviewGlowOverlays[pvKey] then
                                        local ov = CreateFrame("Frame", nil, previewBtn)
                                        ov:SetAllPoints(previewBtn)
                                        ov:SetFrameLevel(previewBtn:GetFrameLevel() + 10)
                                        ov._euiGlowPreview = true  -- exempt from Show Glows Only in Combat
                                        _bgPreviewGlowOverlays[pvKey] = ov
                                    end
                                    local ov = _bgPreviewGlowOverlays[pvKey]
                                    if _bgPreviewGlowActive[pvKey] then
                                        ns.StopNativeGlow(ov)
                                        _bgPreviewGlowActive[pvKey] = false
                                        -- Restore accent border
                                        if previewBtn._accentBrd then previewBtn._accentBrd:Show() end
                                    else
                                        local style = BarHasCustomShape(curBar) and 2 or (entry.glowStyle or 1)
                                        local cr, cg, cb
                                        if entry.colorMode == "class" then
                                            local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                                            cr, cg, cb = cc.r, cc.g, cc.b
                                        elseif entry.colorMode == "custom" and entry.glowColor then
                                            cr, cg, cb = entry.glowColor.r, entry.glowColor.g, entry.glowColor.b
                                        end
                                        ns.StartNativeGlow(ov, style, cr, cg, cb,
                                            style == 8 and { panel = true, alpha = entry.glowAlpha } or EllesmereUI.Glows.PANEL_EXTRA)
                                        _bgPreviewGlowActive[pvKey] = true
                                        -- Hide accent border so glow is visible
                                        if previewBtn._accentBrd then previewBtn._accentBrd:Hide() end
                                    end
                                    RefreshEye()
                                end)
                                eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                                eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)

                                -- Blackout fill opacity, in a cog chained left of the eye. Locked
                                -- unless the entry renders Blackout (custom-shaped bars always
                                -- draw Shape Glow); the Glow Type setter's page refresh re-checks it.
                                leftRgn._lastInline = eyeBtn
                                EllesmereUI.BuildInlineCog(leftRgn, {
                                    title = "Blackout",
                                    disabled = function()
                                        return (BarHasCustomShape(curBar) and 2 or (entry.glowStyle or 1)) ~= 8
                                    end,
                                    disabledTooltip = function()
                                        return BarHasCustomShape(curBar) and "This option is not available for custom shaped icons"
                                            or "This option requires the Blackout glow type"
                                    end,
                                    frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                                    rows = {
                                        { type = "slider", label = "Opacity", min = 1, max = 100, step = 1,
                                          get = function() return math.floor((entry.glowAlpha or 1) * 100 + 0.5) end,
                                          set = function(v)
                                              entry.glowAlpha = v / 100
                                              -- Restarts the lit Bar Glows with the new opacity (fires
                                              -- per drag step, so no full CDM rebuild here).
                                              if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
                                              RefreshPreviewGlow()
                                          end },
                                    },
                                })
                            end
                        end

                        -- Retail: Only In Combat | Hero Talent, then Glow Color (swatches) |
                        -- (icon) [Duplicate] [Remove]. WoW Forever has no Hero Talent half,
                        -- so the slots re-pair there: Only In Combat | Glow Color, then the
                        -- buttons in the left half of the last row.
                        local glowColorCfg = { type = "label", text = "Glow Color" }
                        local removeCfg = { type = "labeledButton", text = "", buttonText = "Remove", width = 150,
                            onClick = function()
                                table.remove(buffList, removeAIdx)
                                if #buffList == 0 then
                                    bg.assignments[assignKey] = nil
                                end
                                Refresh()
                                EllesmereUI:RefreshPage(true)
                            end,
                        }
                        local colorRow, colorRgn, removeRgn
                        if EllesmereUI.IS_FOREVER then
                            colorRow, h = W:DualRow(parent, y, ns.BarGlowCombatCfg(entry, Refresh), glowColorCfg);  y = y - h
                            colorRgn = colorRow._rightRegion
                            local removeRow
                            removeRow, h = W:DualRow(parent, y, removeCfg, EllesmereUI.BlankRowCfg());  y = y - h
                            removeRgn = removeRow._leftRegion
                        else
                            y = ns.BuildBarGlowCombatRow(W, parent, y, entry, Refresh)
                            colorRow, h = W:DualRow(parent, y, glowColorCfg, removeCfg);  y = y - h
                            colorRgn, removeRgn = colorRow._leftRegion, colorRow._rightRegion
                        end

                        -- Inline color swatch for glow color
                        if not EllesmereUI._prebuilding then
                            local leftRgn = colorRgn
                            if leftRgn and EllesmereUI.BuildTrioColorSwatch then
                                local glowSwatch, defaultSwatch, classSwatch = EllesmereUI.BuildTrioColorSwatch(
                                    leftRgn, colorRow:GetFrameLevel() + 3,
                                    {
                                        getMode = function() return entry.colorMode or "default" end,
                                        setMode = function(m) entry.colorMode = m end,
                                        getCustomRGB = function()
                                            local c = entry.glowColor or { r = 1.0, g = 0.788, b = 0.137 }
                                            return c.r, c.g, c.b
                                        end,
                                        setCustomRGB = function(r, g, b)
                                            entry.glowColor = { r = r, g = g, b = b }
                                        end,
                                        hasClassColor = true,
                                        onChange = function() Refresh(); RefreshPreviewGlow(); EllesmereUI:RefreshPage() end,
                                        overrideSize = 20,
                                    })
                                PP.Point(classSwatch, "RIGHT", leftRgn, "RIGHT", -20, 0)
                                PP.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                                PP.Point(defaultSwatch, "RIGHT", glowSwatch, "LEFT", -8, 0)
                            end
                        end

                        -- Duplicate, then the buff icon (spell tooltip on hover), LEFT of Remove
                        if not EllesmereUI._prebuilding then
                            local rightRgn = removeRgn
                            if rightRgn and rightRgn._control then
                                local btn = rightRgn._control
                                local dupBtn = ns.BarGlowDuplicateButton(rightRgn, btn, buffList, aIdx, function()
                                    Refresh()
                                    EllesmereUI:RefreshPage(true)
                                end)
                                local ico = ns.BarGlowSpellIcon(rightRgn, btn:GetHeight(), entry.spellID)
                                PP.Point(ico, "RIGHT", dupBtn or btn, "LEFT", -8, 0)
                            end
                        end
                    end
                end
            end
        end

        return math.abs(y)
    end

    -- Tracking Bars page with its state and hooks (CooldownManager_Options\
    -- BuffBarsPage_Options.lua), set up here so the hooks keep their order.
    local BuildBuffBarsPage, RefreshTBBPopout = ns.CDMO_InitBuffBarsPage(PP, DB, Refresh,
        FONT_PATH, GetCDMOptOutline, GateBlizzardOnly, PAGE_BUFF_BARS)

    ---------------------------------------------------------------------------
    --  CDM Bars page
    ---------------------------------------------------------------------------
    -- Mutable state shared with the pickers and page builders under
    -- CooldownManager_Options\. A table instead of locals so every file reads
    -- and writes the live value.
    local optState = {}
    local growValues = EllesmereUI.GROW_DIR_VALUES_BASE
    local growOrder  = { "RIGHT", "LEFT", "DOWN", "UP" } -- this dropdown's own sequence (DOWN before UP)
    local durationPositionValues = {
        center = "Center",
        top = "Above Icon",
        bottom = "Below Icon",
        left = "Left of Icon",
        right = "Right of Icon",
    }
    local durationPositionOrder = { "center", "top", "bottom", "left", "right" }

    -- Track which bar is selected in the CDM Bars tab
    optState.selectedCDMBarIndex = 1

    -- Deep-link helper: select a CDM bar by key or barType (used by the What's
    -- New "Always Show Buffs" card preSelect -- that per-bar toggle only renders
    -- when a buff-family bar is selected). Sets the index immediately, like
    -- EllesmereUI._setUnitFrameUnit, so header and rebuilt page both reflect it.
    function EllesmereUI._setCDMBar(keyOrType)
        local p = DB()
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return end
        for bi, bb in ipairs(bars) do
            if bb.key == keyOrType or bb.barType == keyOrType then
                optState.selectedCDMBarIndex = bi
                return
            end
        end
    end

    -- CDM Bars preview state, nil until built: optState._cdmPreview is the
    -- preview frame, optState._cdmHeaderBuilder the content header builder
    optState._cdmHeaderFixedH = 0

    local function UpdateCDMPreview()
        if not optState._cdmPreview and EllesmereUI._contentHeaderPreview then
            optState._cdmPreview = EllesmereUI._contentHeaderPreview
        end
        if optState._cdmPreview and optState._cdmPreview.Update then
            optState._cdmPreview:Update()
        end
    end

    local function UpdateCDMPreviewAndResize()
        UpdateCDMPreview()
        if optState._cdmPreview and optState._cdmHeaderFixedH > 0 then
            -- Wrapper height is already capped by the Update function's resize logic
            local wrapperH = optState._cdmPreview._wrapper and optState._cdmPreview._wrapper:GetHeight()
                             or math.min(optState._cdmPreview:GetHeight() * (optState._cdmPreview:GetScale() or 1), 200)
            EllesmereUI:UpdateContentHeaderHeight(optState._cdmHeaderFixedH + wrapperH)
        end
    end

    EllesmereUI:RegisterOnShow(UpdateCDMPreview)

    -- Refresh our preview when user closes Blizzard's CDM settings panel
    -- (they may have added/removed spells from the viewer)
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, function()
                if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
                    EllesmereUI:RefreshPage(true)
                end
            end)
        end)
    end

    --- Get the currently selected CDM bar data
    local function SelectedCDMBar()
        local p = DB()
        if not p or not p.cdmBars or not p.cdmBars.bars then return nil end
        local bars = p.cdmBars.bars
        if optState.selectedCDMBarIndex < 1 then optState.selectedCDMBarIndex = 1 end
        if optState.selectedCDMBarIndex > #bars then optState.selectedCDMBarIndex = #bars end
        return bars[optState.selectedCDMBarIndex]
    end

    -- Active state preview on first icon
    local _cdmActivePreviewOn = false
    local _cdmActivePreviewOverlay = nil  -- glow overlay frame on first preview slot
    local _cdmActivePreviewToken = 0     -- incremented each start to invalidate stale timers

    local function StopActiveStatePreview()
        if _cdmActivePreviewOverlay then
            ns.StopNativeGlow(_cdmActivePreviewOverlay)
        end
        -- Stop fake cooldown on preview slot
        if optState._cdmPreview and optState._cdmPreview._previewSlots then
            local slot = optState._cdmPreview._previewSlots[1]
            if slot and slot._previewCD then
                slot._previewCD:Clear()
                slot._previewCD:Hide()
            end
        end
    end

    local function StartActiveStatePreview()
        if not _cdmActivePreviewOn then return end
        _cdmActivePreviewToken = _cdmActivePreviewToken + 1
        local myToken = _cdmActivePreviewToken
        local bd = SelectedCDMBar()
        if not bd then return end
        local anim = bd.activeStateAnim or "blizzard"
        if not optState._cdmPreview or not optState._cdmPreview._previewSlots then return end
        local slot = optState._cdmPreview._previewSlots[1]
        if not slot or not slot:IsShown() then return end

        -- Ensure cooldown widget exists on preview slot
        if not slot._previewCD then
            local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
            cd:SetAllPoints()
            cd:SetDrawEdge(false)
            cd:SetDrawSwipe(true)
            cd:SetDrawBling(false)
            cd:SetReverse(false)
            cd:SetHideCountdownNumbers(false)
            -- Blizzard Style: the viewer's rounded swipe, matching its mask
            -- (classic icons are square and keep the plain swipe).
            cd:SetSwipeTexture((EllesmereUI.BlizzStyle.Active("cdmicons") == "blizzard" and ns.CDM_BLIZZ_SWIPE)
                or "Interface\\Buttons\\WHITE8x8")
            if cd.SetSnapToPixelGrid then cd:SetSnapToPixelGrid(false); cd:SetTexelSnappingBias(0) end
            slot._previewCD = cd
        end

        -- Always refresh font (smaller than the bar's cooldown font size, shadow style)
        C_Timer.After(0, function()
            if not slot._previewCD then return end
            local fSize = (bd.cooldownFontSize or 12) - 2
            if fSize < 6 then fSize = 6 end
            local fontPath = (EllesmereUI.GetFontPath("cdm")) or STANDARD_TEXT_FONT
            for _, region in ipairs({ slot._previewCD:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    SetPVFont(region, fontPath, fSize)
                    if ns.AnchorCooldownText then
                        ns.AnchorCooldownText(region, slot._previewCD,
                            bd.cooldownTextPosition or "center",
                            bd.cooldownTextX or 0, bd.cooldownTextY or 0)
                    end
                    break
                end
            end
        end)

        -- Ensure glow overlay exists
        if not slot._glowOverlay then
            local ov = CreateFrame("Frame", nil, slot)
            ov:SetAllPoints(slot)
            -- Above the Blizzard Style ring (+15) as on the live icons (+16).
            ov:SetFrameLevel(slot:GetFrameLevel() + (EllesmereUI.BlizzStyle.Get("cdmicons") and 16 or 3))
            ov:SetAlpha(0)
            ov._euiGlowPreview = true  -- exempt from Show Glows Only in Combat
            slot._glowOverlay = ov
        end
        _cdmActivePreviewOverlay = slot._glowOverlay

        -- Resolve active animation color
        local animR, animG, animB = 1.0, 0.85, 0.0
        if bd.activeAnimClassColor then
            local _, ct = UnitClass("player")
            if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
        elseif bd.activeAnimR then
            animR = bd.activeAnimR; animG = bd.activeAnimG or 0.85; animB = bd.activeAnimB or 0.0
        end

        local swAlpha = bd.swipeAlpha or 0.7
        local PREVIEW_DURATION = 5  -- seconds

        if anim == "none" then
            slot._previewCD:SetSwipeColor(0, 0, 0, swAlpha)
            slot._previewCD:SetCooldown(GetTime(), PREVIEW_DURATION)
            slot._previewCD:Show()
            ns.StopNativeGlow(_cdmActivePreviewOverlay)
        else
            slot._previewCD:SetSwipeColor(animR, animG, animB, swAlpha)
            slot._previewCD:SetCooldown(GetTime(), PREVIEW_DURATION)
            slot._previewCD:Show()

            if anim ~= "blizzard" then
                local glowIdx = tonumber(anim)
                if glowIdx then
                    ns.StartNativeGlow(_cdmActivePreviewOverlay, glowIdx, animR, animG, animB, EllesmereUI.Glows.PANEL_EXTRA)
                end
            else
                ns.StopNativeGlow(_cdmActivePreviewOverlay)
            end
        end

        -- Auto-stop glow after preview duration ends
        C_Timer.After(PREVIEW_DURATION, function()
            if myToken ~= _cdmActivePreviewToken then return end
            if _cdmActivePreviewOverlay then
                ns.StopNativeGlow(_cdmActivePreviewOverlay)
            end
            if slot._previewCD then
                slot._previewCD:Clear()
                slot._previewCD:Hide()
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Spell picker dropdown (right-click on icon or click "+" button)
    ---------------------------------------------------------------------------
    -- Close the spell picker when the main EUI options panel closes
    EllesmereUI:RegisterOnHide(function()
        if optState._spellPickerMenu and optState._spellPickerMenu:IsShown() then optState._spellPickerMenu:Hide() end
    end)
    -- Normalize a spell ID to its base (undo talent overrides), and resolve
    -- a base id to its current live version (talent overrides) -- both
    -- delegate to the resident module (EllesmereUICdmSpellPicker.lua) so
    -- every consumer, including the resident keep/drop reconcile pass,
    -- shares one implementation instead of a second local copy drifting out of sync.
    local NormalizeToBase = ns.NormalizeToBase
    local ResolveToLive = ns.ResolveToLive

    -- Texture-only sibling: tracked-buff slots hold AURA ids, which carry no override
    -- when a talent replaces the spell, so the icon needs the shared resolver's spellbook
    -- bridge (+ the slot's cdID to reach linked replacement ids). Deliberately NOT folded
    -- into ResolveToLive, which also feeds learned-state/catalog membership tests (incl.
    -- the keep/drop pass) -- a bridged id there could drop a spell from a saved bar.
    -- Only the art moves; identity stays untouched.
    local function ResolveIconArt(sid, cdID)
        if not sid or sid <= 0 then return sid end
        if ns.LustPresetIconSpellID then sid = ns.LustPresetIconSpellID(sid) end
        if ns.ResolvePlaceholderIconSID then
            local live = ns.ResolvePlaceholderIconSID(sid, cdID)
            if type(live) == "number" and live > 0 then return live end
        end
        return ResolveToLive(sid)
    end

    -- Keybind color swatch and text cog on a Show Keybind row. lockTip
    -- (optional): why the whole row is locked, nil while it is live; the
    -- swatch and cog give that reason first, then Show Keybind.
    local function BuildKeybindStyleControls(kbRow, BD, RefreshKeybindStyle, lockTip)
        if not EllesmereUI._prebuilding then
            local rgn = kbRow._rightRegion
            local kbFonts, kbFontOrder = EllesmereUI.BuildFontDropdownData()
            kbFonts.__global = { text = "CDM Font" }
            local function OffTip()
                local tip = lockTip and lockTip()
                if tip then return tip end
                if BD().showKeybind ~= true then return "Show Keybind" end
            end

            local kbSwatch, updateKbSwatch = EllesmereUI.BuildColorSwatch(
                rgn, kbRow:GetFrameLevel() + 3,
                function() return BD().keybindR or 1, BD().keybindG or 1, BD().keybindB or 1, BD().keybindA or 0.9 end,
                function(r, g, b, a)
                    BD().keybindR = r; BD().keybindG = g; BD().keybindB = b; BD().keybindA = a
                    RefreshKeybindStyle()
                end,
                true, 20)
            PP.Point(kbSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)

            EllesmereUI.BuildInlineCog(rgn, { anchorTo = kbSwatch, icon = EllesmereUI.RESIZE_ICON,
                title = "Keybind Text Settings",
                disabled = function() return OffTip() ~= nil end,
                disabledTooltip = OffTip,
                rows = {
                    { type = "dropdown", label = "Font", values = kbFonts, order = kbFontOrder,
                      get = function() return BD().keybindFont or "__global" end,
                      set = function(v) BD().keybindFont = v; RefreshKeybindStyle() end },
                    { type = "dropdown", label = "Text Outline",
                      values = { inherit = "CDM Outline", NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" },
                      order = { "inherit", "NONE", "OUTLINE", "THICKOUTLINE" },
                      get = function() return BD().keybindOutline or "inherit" end,
                      set = function(v) BD().keybindOutline = v; RefreshKeybindStyle() end },
                    { type = "slider", label = "Text Size", min = 6, max = 20, step = 1,
                      get = function() return BD().keybindSize or 10 end,
                      set = function(v) BD().keybindSize = v; RefreshKeybindStyle() end },
                    { type = "dropdown", label = "Anchor",
                      values = { TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
                          LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                          BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right" },
                      order = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
                      get = function() return BD().keybindAnchor or (BD().keybindAlign == "right" and "TOPRIGHT" or "TOPLEFT") end,
                      set = function(v) BD().keybindAnchor = v; RefreshKeybindStyle() end },
                    { type = "slider", label = "X Offset", min = -30, max = 30, step = 1,
                      get = function() return BD().keybindOffsetX or 2 end,
                      set = function(v) BD().keybindOffsetX = v; RefreshKeybindStyle() end },
                    { type = "slider", label = "Y Offset", min = -30, max = 30, step = 1,
                      get = function() return BD().keybindOffsetY or -2 end,
                      set = function(v) BD().keybindOffsetY = v; RefreshKeybindStyle() end },
                    { type = "colorpicker", label = "Background Color", hasAlpha = true,
                      tooltip = "Set opacity to 0% for text without a background.",
                      get = function() return BD().keybindBackgroundR or 0, BD().keybindBackgroundG or 0,
                          BD().keybindBackgroundB or 0, BD().keybindBackgroundA or 0 end,
                      set = function(r, g, b, a)
                          local d = BD(); d.keybindBackgroundR = r; d.keybindBackgroundG = g
                          d.keybindBackgroundB = b; d.keybindBackgroundA = a; RefreshKeybindStyle()
                      end },
                    { type = "colorpicker", label = "Border Color", hasAlpha = true,
                      tooltip = "Set opacity to 0% to hide the keybind badge border.",
                      get = function() return BD().keybindBorderR or 1, BD().keybindBorderG or 1,
                          BD().keybindBorderB or 1, BD().keybindBorderA or 0 end,
                      set = function(r, g, b, a)
                          local d = BD(); d.keybindBorderR = r; d.keybindBorderG = g
                          d.keybindBorderB = b; d.keybindBorderA = a; RefreshKeybindStyle()
                      end },
                    { type = "slider", label = "Border Size", min = 0, max = 4, step = 1,
                      get = function() return BD().keybindBorderSize or 1 end,
                      set = function(v) BD().keybindBorderSize = v; RefreshKeybindStyle() end },
                    { type = "slider", label = "Background Padding", min = 0, max = 8, step = 1,
                      get = function() return BD().keybindPadding or 2 end,
                      set = function(v) BD().keybindPadding = v; RefreshKeybindStyle() end },
                    -- Global, not per-bar: there is one shared keybind cache
                    -- for every CDM bar, so this toggle is labelled as such.
                    { type = "toggle", label = "Keep Keys on Bar Swap (global)",
                      tooltip = "Keep keybind text identical when your action bar swaps -- rogue stealth, druid forms, skyriding. Also covers conditional macros like \"/cast [bonusbar:1] Backstab; Shadow Dance\", where the key would otherwise jump to whichever branch is live.\n\nThe key then only changes when you actually move the ability or rebind it.\n\nOn by default. Applies to every CDM bar at once.",
                      get = function()
                          local p = DB()
                          return (p and p.cdmBars and p.cdmBars.stableKeybinds) == true
                      end,
                      set = function(v)
                          local p = DB()
                          if not p or not p.cdmBars then return end
                          p.cdmBars.stableKeybinds = v and true or false
                          -- Changes how the cache is built, not just how it is
                          -- drawn -- needs a full rebuild, not an apply pass.
                          if ns.UpdateCDMKeybinds then ns.UpdateCDMKeybinds() end
                          RefreshKeybindStyle()
                      end },
                },
            })

            local swatchBlock = CreateFrame("Frame", nil, kbSwatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(kbSwatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                local tip = OffTip()
                if tip then EllesmereUI.ShowWidgetTooltip(kbSwatch, EllesmereUI.DisabledTooltip(tip)) end
            end)
            swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function SwatchState()
                updateKbSwatch()
                local on = OffTip() == nil
                kbSwatch:SetAlpha(on and 1 or 0.3)
                swatchBlock:SetShown(not on)
            end
            EllesmereUI.RegisterWidgetRefresh(SwatchState)
            SwatchState()
        end
    end

    -- Shared helpers for the pickers and page builders under
    -- CooldownManager_Options\ (loaded before this file, read when a picker
    -- opens or a page is built).
    ns._CDMO_OptEnv = {
        _cdmActivePreviewOn = _cdmActivePreviewOn, AnyIconAlwaysShowOn = AnyIconAlwaysShowOn, BuildKeybindStyleControls = BuildKeybindStyleControls,
        DB = DB, durationPositionOrder = durationPositionOrder, durationPositionValues = durationPositionValues,
        FitMenuWidth = FitMenuWidth, FONT_PATH = FONT_PATH, GetCDMOptOutline = GetCDMOptOutline,
        NormalizeToBase = NormalizeToBase, optState = optState, PP = PP,
        Refresh = Refresh, RefreshCDPreview = RefreshCDPreview, ResolveIconArt = ResolveIconArt,
        ResolveToLive = ResolveToLive, SelectedCDMBar = SelectedCDMBar, SetPVFont = SetPVFont,
        StartActiveStatePreview = StartActiveStatePreview, StopActiveStatePreview = StopActiveStatePreview, UpdateCDMPreview = UpdateCDMPreview,
        UpdateCDMPreviewAndResize = UpdateCDMPreviewAndResize,
    }


    ---------------------------------------------------------------------------
    --  Standalone Rotation Assist Icon (independent of the selected CDM bar)
    ---------------------------------------------------------------------------
    local function BuildRotationAssistIconPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        parent._showRowDivider = true
        local function Settings() return DB().rotationAssistIcon end
        local function Apply()
            ns.RefreshRotationAssistIcon()
            EllesmereUI:RefreshPage()
        end
        -- Why the icon's rows are locked, nil while they are live: Blizzard's
        -- Assisted Highlight off, or the icon itself off.
        local function IconLockTip()
            if not ns.RotationAssistAvailable() then
                return "This option requires Blizzard's Assisted Highlight to be enabled"
            end
            if Settings().enabled ~= true then return "Show Rotation Assist Icon" end
        end
        local function IconOff() return IconLockTip() ~= nil end
        -- The saved position, else the runtime's default (read only).
        local function Position()
            return Settings().position or ns.CDM_ROTATION_ICON_DEFAULT_POS
        end
        local function SetOffset(axis, value)
            local s = Settings()
            local pos = s.position or CopyTable(ns.CDM_ROTATION_ICON_DEFAULT_POS)
            pos[axis] = EllesmereUI.PP.FromPixels(value)
            s.position = pos
            ns.RefreshRotationAssistIcon()
        end

        _, h = W:SectionHeader(parent, "ROTATION ASSIST ICON", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Rotation Assist Icon",
              tooltip="Show Blizzard's current recommendation in a separate icon. Requires Assisted Highlight to be enabled in Blizzard's options. Press the spell's normal keybind; this display never casts spells. Blizzard supplies one recommendation, not a queue of future casts.",
              -- Locked only while off: an icon left on after the highlight was
              -- switched off can always be turned off here.
              disabled=function() return not ns.RotationAssistAvailable() and Settings().enabled ~= true end,
              disabledTooltip="This option requires Blizzard's Assisted Highlight to be enabled",
              rawTooltip=true,
              getValue=function() return Settings().enabled == true end,
              setValue=function(v)
                  Settings().enabled = v
                  Apply()
              end },
            { type="slider", text="Icon Size", min=16, max=128, step=1,
              disabled=IconOff, disabledTooltip=IconLockTip,
              getValue=function() return Settings().iconSize or 48 end,
              setValue=function(v) Settings().iconSize = v; ns.RefreshRotationAssistIcon() end }
        );  y = y - h
        local kbRow
        kbRow, h = W:DualRow(parent, y,
            { type="toggle", text="Only in Combat",
              tooltip="Hide outside combat. Unlock Mode shows a placeholder when no recommendation is available.",
              disabled=IconOff, disabledTooltip=IconLockTip,
              getValue=function() return Settings().onlyInCombat == true end,
              setValue=function(v) Settings().onlyInCombat = v; Apply() end },
            { type="toggle", text="Show Keybind",
              tooltip="Use the CDM keybind mapping. Configure the font, outline, position, background and border with the cog.",
              disabled=IconOff, disabledTooltip=IconLockTip,
              getValue=function() return Settings().showKeybind == true end,
              setValue=function(v) Settings().showKeybind = v; Apply() end }
        );  y = y - h
        BuildKeybindStyleControls(kbRow, Settings, Apply, IconLockTip)
        _, h = W:DualRow(parent, y,
            { type="slider", text="X Offset", min=-2000, max=2000, step=1,
              tooltip="Horizontal screen offset. You can also drag the Rotation Assist Icon in Unlock Mode.",
              disabled=IconOff, disabledTooltip=IconLockTip,
              getValue=function() return EllesmereUI.PP.ToPixels(Position().x or 0) end,
              setValue=function(v) SetOffset("x", v) end },
            { type="slider", text="Y Offset", min=-1200, max=1200, step=1,
              tooltip="Vertical screen offset. You can also drag the Rotation Assist Icon in Unlock Mode.",
              disabled=IconOff, disabledTooltip=IconLockTip,
              getValue=function() return EllesmereUI.PP.ToPixels(Position().y or 0) end,
              setValue=function(v) SetOffset("y", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show GCD",
              tooltip="Show the global cooldown as a swipe over the recommended ability. The swipe shows when the GCD ends; casting, channeling and ability requirements can still delay your next action.",
              disabled=IconOff, disabledTooltip=IconLockTip,
              getValue=function() return Settings().showGCD == true end,
              setValue=function(v) Settings().showGCD = v; Apply() end },
            EllesmereUI.BlankRowCfg()
        );  y = y - h
        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (opens EllesmereUI Unlock Mode overlay)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        C_Timer.After(0, function()
            if EllesmereUI and EllesmereUI._openUnlockMode then
                EllesmereUI._openUnlockMode()
            end
        end)
        return 0
    end

    ---------------------------------------------------------------------------
    --  One-time CDM button settings tip (shown on first CDM Bars page open)
    ---------------------------------------------------------------------------
    local _cdmButtonTip
    local function ShowCDMButtonTip()
        if EllesmereUIDB and EllesmereUIDB.cdmButtonTipSeen then return end
        local preview = EllesmereUI._contentHeaderPreview
        if not preview then return end
        if _cdmButtonTip and _cdmButtonTip:IsShown() then return end

        if not _cdmButtonTip then
            local TIP_W, TIP_H = 360, 105
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local ar, ag, ab = EG.r, EG.g, EG.b
            local PP = EllesmereUI.PanelPP or EllesmereUI.PP

            local tip = CreateFrame("Frame", nil, EllesmereUI._panelBody)
            tip:SetFrameStrata("FULLSCREEN_DIALOG")
            tip:SetFrameLevel(200)
            if PP and PP.Size then PP.Size(tip, TIP_W, TIP_H) else tip:SetSize(TIP_W, TIP_H) end
            tip:EnableMouse(true)

            -- Background
            local bg = tip:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.077, 0.068, 0.058, 1)

            -- Border
            EllesmereUI.MakeBorder(tip, ar, ag, ab, 0.25, PP)

            -- Arrow pointing up
            local ARROW_SZ = 16
            local arrowClip = CreateFrame("Frame", nil, tip)
            arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
            arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
            arrowClip:SetClipsChildren(true)
            arrowClip:SetSize(ARROW_SZ * 2, ARROW_SZ)
            arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

            local arrowFrame = CreateFrame("Frame", nil, arrowClip)
            arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
            arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
            arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

            local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
            arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
            arrowBorder:SetPoint("CENTER")
            arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
            arrowBorder:SetRotation(math.rad(45))
            if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

            local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
            arrowFill:SetPoint("CENTER")
            arrowFill:SetColorTexture(0.077, 0.068, 0.058, 1)
            arrowFill:SetRotation(math.rad(45))
            if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

            -- Message
            local FONT_PATH2 = (EllesmereUI.GetFontPath("cdm"))
                or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
            local msg = tip:CreateFontString(nil, "OVERLAY")
            msg:SetFont(FONT_PATH2, 12, "")
            msg:SetTextColor(1, 1, 1, 0.85)
            msg:SetPoint("TOP", tip, "TOP", 0, -15)
            msg:SetWidth(TIP_W - 30)
            msg:SetJustifyH("CENTER")
            msg:SetSpacing(4)
            msg:SetText(EllesmereUI.L("CDM buttons can have their glow and active states\nset per icon or synced to the bar. Click a button\nto show its settings."))

            -- Okay button
            local okBtn = CreateFrame("Button", nil, tip)
            okBtn:SetSize(86, 26)
            okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 11)
            EllesmereUI.MakeStyledButton(okBtn, "Okay", 11,
                EllesmereUI.RB_COLOURS, function()
                    tip:Hide()
                    if EllesmereUIDB then EllesmereUIDB.cdmButtonTipSeen = true end
                end)

            _cdmButtonTip = tip
        end

        -- The preview is rebuilt with its page, so anchor on every show.
        _cdmButtonTip:ClearAllPoints()
        _cdmButtonTip:SetPoint("TOP", preview, "BOTTOM", 0, -12)
        _cdmButtonTip:Show()
    end
    -- Hidden whenever the player leaves the CDM Bars page (page switch, module
    -- switch, panel close); it returns on that page until dismissed with Okay.
    local function HideCDMButtonTip()
        if _cdmButtonTip then _cdmButtonTip:Hide() end
    end
    -- Shown a beat after the Bars page renders; the player may already have
    -- moved on by then, so the timer re-checks the page before showing.
    local function QueueCDMButtonTip()
        C_Timer.After(0.1, function()
            if ns._cdmBarsPageOpen then ShowCDMButtonTip() end
        end)
    end

    ---------------------------------------------------------------------------
    --  Buff bar overlay: REMOVED (no locator ghost over the live buff bar
    --  while options are open). ShowBuffBarOverlay is a no-op stub so the
    --  existing call sites (page open/close) need no changes.
    ---------------------------------------------------------------------------
    local _buffBarOverlay
    local function ShowBuffBarOverlay()
    end

    local function HideBuffBarOverlay()
        if _buffBarOverlay then _buffBarOverlay:Hide() end
    end
    ns.ShowBuffBarOverlay = ShowBuffBarOverlay
    ns.HideBuffBarOverlay = HideBuffBarOverlay

    -- Hook: show tip when CDM Bars page first renders with a preview visible
    local _cdmButtonTipQueued = false
    EllesmereUI:RegisterOnHide(function()
        HideCDMButtonTip()
        -- Hide overlay and custom aura preview when panel closes
        HideBuffBarOverlay()
        ns._cdmBarsPageOpen = false
        if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
    end)


    local function BuildGeneralPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y, h = yOffset, 0
        local function PromptReload()
            EllesmereUI:ShowConfirmPopup({
                title = "Reload Required",
                message = "Changing the Cooldown Manager command requires a reload to update slash command registration.",
                confirmText = "Reload",
                cancelText = "Later",
                reload = true,
            })
        end
        _, h = W:SectionHeader(parent, "SLASH COMMAND", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Blizzard CDM Command", inputWidth = 160,
              inputStyle = "popup",
              disabled = function() return not _G._ECME_AceDB.sv.cdmCommandSettings.blizzardCDMCommandEnabled end,
              disabledTooltip = "Enable Blizzard CDM Command",
              tooltip = "Command to open Blizzard's Cooldown Manager settings (for example /cd). Leave blank to disable. Account-wide; requires a UI reload. Use letters and numbers, starting with a letter.",
              getValue = function() return _G._ECME_AceDB.sv.cdmCommandSettings.blizzardCDMCommand end,
              setValue = function(text)
                  local command = ns.NormalizeBlizzardCDMCommand(text)
                  if not command then
                      EllesmereUI.PrintError(EllesmereUI.L("Enter a slash command such as /cd, or leave blank to disable."))
                      return
                  end
                  local settings = _G._ECME_AceDB.sv.cdmCommandSettings
                  if settings.blizzardCDMCommand == command then return end
                  settings.blizzardCDMCommand = command
                  PromptReload()
              end },
            { type = "toggle", text = "Enable Blizzard CDM Command",
              tooltip = "Enable the command that opens Blizzard's Cooldown Manager settings. Turning it off keeps your chosen command. Account-wide; requires a UI reload.",
              getValue = function() return _G._ECME_AceDB.sv.cdmCommandSettings.blizzardCDMCommandEnabled end,
              setValue = function(enabled)
                  local settings = _G._ECME_AceDB.sv.cdmCommandSettings
                  if settings.blizzardCDMCommandEnabled == enabled then return end
                  settings.blizzardCDMCommandEnabled = enabled
                  EllesmereUI:RefreshPage()
                  PromptReload()
              end }
        ); y = y - h
        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUICooldownManager", {
        title       = "Cooldown Manager",
        description = "CDM bar customization, action bar glows, and buff bars.",
        -- Rotation Assist Icon is absent on Forever (no Assisted
        -- Highlight there).
        pages       = EllesmereUI.IS_FOREVER and { PAGE_CDM_BARS, PAGE_BAR_GLOWS, PAGE_BUFF_BARS, PAGE_GENERAL }
                      or { PAGE_CDM_BARS, PAGE_BAR_GLOWS, PAGE_BUFF_BARS, PAGE_ROTATION_ICON, PAGE_GENERAL },
        disabledPages = {},
        disabledPageTooltips = {},
        buildPage   = function(pageName, parent, yOffset)
            -- ns._tbbPlaceholderMode / ns._cdmBarsPageOpen reflect the page the player
            -- is REALLY on, not the pageName being built. A hidden search pre-build
            -- cycles pageName through all three pages, so the "switched away" cleanup
            -- below (buff-bar injection/removal, placeholder toggling, settings tip)
            -- would fire against what the player is actually seeing -- during
            -- pre-build, only build content. PAGE_BUFF_BARS is skipped entirely: its
            -- builder unconditionally calls UpdateTBBPlaceholder() at its tail, which
            -- grabs the REAL tracked-buff-bar frames via ns.GetTBBFrame(i) (not scoped
            -- to `parent`) and forces them :Show() with unlock placeholders -- building
            -- it here would pop the live buff bars onto the screen. It's indexed
            -- normally the first time the player visits it live.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_GENERAL then
                    return BuildGeneralPage(pageName, parent, yOffset)
                elseif pageName == PAGE_CDM_BARS then
                    return ns.CDMO_BuildCDMBarsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_ROTATION_ICON then
                    return BuildRotationAssistIconPage(pageName, parent, yOffset)
                elseif pageName == PAGE_BAR_GLOWS then
                    return BuildBarGlowsPage(pageName, parent, yOffset)
                end
                return
            end
            -- Clear TBB placeholders when switching to any non-Tracking Bars page
            if pageName ~= PAGE_BUFF_BARS and ns._tbbPlaceholderMode then
                ns._tbbPlaceholderMode = false
                if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
            end
            -- Manage custom aura bar preview: flag-based, not GetActivePage
            if pageName ~= PAGE_CDM_BARS and ns._cdmBarsPageOpen then
                ns._cdmBarsPageOpen = false
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                -- Page closed: reanchor so buff-bar injected custom/preset buffs
                -- that were shown for configuration (cdmPageOpen) hide unless active.
                if ns.QueueReanchor then ns.QueueReanchor() end
                HideBuffBarOverlay()
                HideCDMButtonTip()
            end
            if pageName == PAGE_GENERAL then
                return BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CDM_BARS then
                ns._cdmBarsPageOpen = true
                local h2 = ns.CDMO_BuildCDMBarsPage(pageName, parent, yOffset)
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                ShowBuffBarOverlay()
                -- Show one-time button settings tip after preview renders
                QueueCDMButtonTip()
                return h2
            elseif pageName == PAGE_ROTATION_ICON then
                return BuildRotationAssistIconPage(pageName, parent, yOffset)
            elseif pageName == PAGE_BAR_GLOWS then
                return BuildBarGlowsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_BUFF_BARS then
                return BuildBuffBarsPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_CDM_BARS then
                return optState._cdmHeaderBuilder
            elseif pageName == PAGE_BAR_GLOWS then
                return _glowHeaderBuilder
            end
            -- Tracking Bars has no content header (popout preview instead)
            return nil
        end,
        -- CDM Bars content is gated on the selected bar (e.g. FocusKick-only
        -- rows render only while barData.key == "focuskick"), and the default
        -- selection is almost never FocusKick -- without this, a hidden pre-build only
        -- ever sees one bar's options and every other bar's unique settings stay
        -- unsearchable until the player visits them live. Build once per distinct bar
        -- SHAPE (cooldowns/utility/buffs/ custom_buff/focuskick), not per bar instance:
        -- several custom bars of one shape expose identical options, so indexing more
        -- than one of a shape would be a wasted rebuild.
        getPrebuildVariants = function(pageName)
            if pageName ~= PAGE_CDM_BARS then return nil end
            local p = DB()
            local bars = p and p.cdmBars and p.cdmBars.bars
            if not bars or #bars == 0 then return nil end
            local seenShapes = {}
            local keys = {}
            for _, b in ipairs(bars) do
                local shape = (b.key == "focuskick") and "focuskick" or b.barType
                if shape and not seenShapes[shape] then
                    seenShapes[shape] = true
                    keys[#keys + 1] = b.key
                end
            end
            if optState.selectedCDMBarIndex < 1 then optState.selectedCDMBarIndex = 1 end
            if optState.selectedCDMBarIndex > #bars then optState.selectedCDMBarIndex = #bars end
            local currentBar = bars[optState.selectedCDMBarIndex]
            return {
                setter = EllesmereUI._setCDMBar,
                keys = keys,
                currentKey = currentBar and currentBar.key,
            }
        end,
        onPageCacheRestore = function(pageName)
            -- Same flag management as buildPage
            if pageName ~= PAGE_BUFF_BARS and ns._tbbPlaceholderMode then
                ns._tbbPlaceholderMode = false
                if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
            end
            if pageName ~= PAGE_CDM_BARS and ns._cdmBarsPageOpen then
                ns._cdmBarsPageOpen = false
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                -- Page closed: reanchor so buff-bar injected custom/preset buffs
                -- that were shown for configuration (cdmPageOpen) hide unless active.
                if ns.QueueReanchor then ns.QueueReanchor() end
                HideBuffBarOverlay()
                HideCDMButtonTip()
            end
            if pageName == PAGE_BUFF_BARS then
                if ns.ShowTBBPlaceholders then ns.ShowTBBPlaceholders() end
                RefreshTBBPopout()
            end
            if pageName == PAGE_CDM_BARS then
                ns._cdmBarsPageOpen = true
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                ShowBuffBarOverlay()
                -- The undismissed tip returns with the Bars page
                QueueCDMButtonTip()
                -- Re-sync _cdmPreview after cache restore and refresh the preview
                if not optState._cdmPreview and EllesmereUI._contentHeaderPreview then
                    optState._cdmPreview = EllesmereUI._contentHeaderPreview
                end
                if optState._cdmPreview and optState._cdmPreview.Update then
                    optState._cdmPreview:Update()
                end
            end
        end,
        -- Leaving the module: the button settings tip is a child of the main
        -- frame, so nothing else would take it down with the page.
        onModuleLeave = function()
            HideCDMButtonTip()
        end,
        onReset = function()
            if _G._ECME_AceDB then
                _G._ECME_AceDB:ResetProfile()
                -- Clear the per-install capture flag so the snapshot re-runs
                -- after reload and picks up Blizzard's current CDM layout.
                if _G._ECME_AceDB.sv then
                    _G._ECME_AceDB.sv._capturedOnce_CDM = nil
                end
            end
            -- Learned variant->base pairs are game data rather than settings,
            -- but they sit on the SV root where StripDefaults and the profile
            -- system never reach, so a pair learned wrong would survive every
            -- other reset. This is the only path that clears them.
            if ns.ResetVariantBaseStore then ns.ResetVariantBaseStore() end
            -- Wipe spell assignments for the current spec so the init snapshot re-populates
            -- from Blizzard's CDM. Spell data lives in EllesmereUIDB (per-profile store), not the
            -- AceDB profile, so ResetProfile doesn't touch it. Only clear the ACTIVE profile's current spec to preserve other specs and other profiles.
            if ns and ns.GetActiveSpecProfiles then
                local sp = ns.GetActiveSpecProfiles()
                local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                if sp and specKey and specKey ~= "0" then
                    sp[specKey] = nil
                    -- WoW Forever: the class reads one of several keys (its
                    -- Forever spec key, then its retail specs); clear them all
                    -- so the reload starts the class fresh.
                    if EllesmereUI.IS_FOREVER then
                        local token = select(2, UnitClass("player"))
                        local ids = EllesmereUI.ForeverClassSpecIDs(token)
                        for i = 1, (ids and #ids or 0) do sp[tostring(ids[i])] = nil end
                        local lk = EllesmereUI.FOREVER_CLASS_SPEC[token]
                        if lk then sp[tostring(lk)] = nil end
                    end
                end
            end
            -- No reload here: the footer Reset popup (reload = true) reloads after this returns.
        end,
    })

    SLASH_ECMEOPT1 = "/ecmeopt"
    SlashCmdList.ECMEOPT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUICooldownManager")
    end

end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
