--------------------------------------------------------------------------------
--  EllesmereUICdmBuffBars.lua
--  Tracked Buff Bars (per-bar buff tracking with individual settings)
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Set to true to enable Tracked Buff Bars functionality
local TBB_ENABLED = true

-- Forward references from main CDM file (set during init)
local ECME

function ns.InitBuffBars(ecme)
    ECME = ecme
end

-------------------------------------------------------------------------------
--  Tracked Buff Bars v2: Per-bar buff tracking with individual settings
--  Each bar tracks a single buff/aura and has its own display settings.
-------------------------------------------------------------------------------
local TBB_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local TBB_TEXTURES = {
    ["none"]          = nil,
    ["beautiful"]     = TBB_TEX_BASE .. "beautiful.tga",
    ["plating"]       = TBB_TEX_BASE .. "plating.tga",
    ["atrocity"]      = TBB_TEX_BASE .. "atrocity.tga",
    ["divide"]        = TBB_TEX_BASE .. "divide.tga",
    ["glass"]         = TBB_TEX_BASE .. "glass.tga",
    ["gradient-lr"]   = TBB_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TBB_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TBB_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TBB_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = TBB_TEX_BASE .. "matte.tga",
    ["sheer"]         = TBB_TEX_BASE .. "sheer.tga",
}
local TBB_TEXTURE_ORDER = {
    "none", "beautiful", "plating",
    "atrocity", "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local TBB_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
ns.TBB_TEXTURES      = TBB_TEXTURES
ns.TBB_TEXTURE_ORDER = TBB_TEXTURE_ORDER
ns.TBB_TEXTURE_NAMES = TBB_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Popular Buffs: hardcoded entries shown in the spell picker.
--  spellIDs: list of all spell IDs that represent this buff (any match = active).
--  customDuration: fixed duration in seconds used to drive the bar fill.
--  icon: fileID to display (used when no spellID resolves an icon).
--  name: display name shown in the picker and on the bar.
-------------------------------------------------------------------------------
local TBB_POPULAR_BUFFS = {
    {
        key            = "bloodlust",
        name           = UnitFactionGroup("player") == "Horde" and "Bloodlust" or "Heroism",
        icon           = 132313,
        spellIDs       = { 2825, 32182, 80353, 264667, 390386, 381301, 444062, 444257 },
        customDuration = 40,
    },
    {
        key            = "lights_potential",
        name           = "Light's Potential",
        icon           = 7548911,
        spellIDs       = { 1236616, 431932 },
        customDuration = 30,
    },
    {
        key            = "potion_recklessness",
        name           = "Potion of Recklessness",
        icon           = 7548916,
        spellIDs       = { 1236994 },
        customDuration = 30,
    },
    {
        key            = "invis_potion",
        name           = "Invisibility Potion",
        icon           = 134764,
        spellIDs       = { 371125, 431424, 371133, 371134, 1236551 },
        customDuration = 18,
    },
    {
        key            = "time_spiral",
        name           = "Time Spiral",
        icon           = 4622479,
        -- No spellIDs: detected via SPELL_ACTIVATION_OVERLAY_GLOW on movement abilities
        glowBased      = true,
        glowSpellIDs   = {
            48265,   -- Death's Advance
            195072,  -- Fel Rush
            189110,  -- Infernal Strike
            1850,    -- Dash
            252216,  -- Tiger Dash
            358267,  -- Hover
            186257,  -- Aspect of the Cheetah
            1953,    -- Blink
            212653,  -- Shimmer
            361138,  -- Roll
            119085,  -- Chi Torpedo
            190784,  -- Divine Steed
            73325,   -- Leap of Faith
            2983,    -- Sprint
            192063,  -- Gust of Wind
            58875,   -- Spirit Walk
            79206,   -- Spiritwalker's Grace
            48020,   -- Demonic Circle: Teleport
            6544,    -- Heroic Leap
        },
        customDuration = 10,
    },
    ---------------------------------------------------------------------------
    --  Demonology Warlock Guardians
    --  These summons have no player aura; detection relies on the Blizzard CDM
    --  active-state / buff-viewer fallback (see EllesmereUICooldownManager.lua).
    ---------------------------------------------------------------------------
    {
        key            = "call_dreadstalkers",
        name           = "Call Dreadstalkers",
        icon           = 1378282,
        spellIDs       = { 104316 },
        customDuration = 12,
        class          = "WARLOCK",
    },
    {
        key            = "demonic_tyrant",
        name           = "Summon Demonic Tyrant",
        icon           = 2065628,
        spellIDs       = { 265187 },
        customDuration = 15,
        class          = "WARLOCK",
    },
    {
        key            = "summon_vilefiend",
        name           = "Summon Vilefiend",
        icon           = 1616211,
        spellIDs       = { 264119 },
        customDuration = 15,
        class          = "WARLOCK",
    },
    {
        key            = "grimoire_felguard",
        name           = "Grimoire: Felguard",
        icon           = 136216,
        spellIDs       = { 111898 },
        customDuration = 17,
        class          = "WARLOCK",
    },
}
ns.TBB_POPULAR_BUFFS = TBB_POPULAR_BUFFS

-- Build a fast lookup: spellID -> popular buff entry (for UNIT_AURA detection)
local _popularSpellIDMap = {}
for _, entry in ipairs(TBB_POPULAR_BUFFS) do
    if entry.spellIDs then
        for _, sid in ipairs(entry.spellIDs) do
            _popularSpellIDMap[sid] = entry
        end
    end
end

-- Build a fast lookup: glow spellID -> popular buff key (for SPELL_ACTIVATION_OVERLAY)
local _glowSpellIDMap = {}
for _, entry in ipairs(TBB_POPULAR_BUFFS) do
    if entry.glowSpellIDs then
        for _, sid in ipairs(entry.glowSpellIDs) do
            _glowSpellIDMap[sid] = entry.key
        end
    end
end

-- Forward declaration -- actual table is populated by BuildTrackedBuffBars below
local tbbFrames

--- Returns true if the user has at least one tracked buff bar configured
function ns.HasBuffBars()
    if not ECME or not ECME.db then return false end
    local tbb = ns.GetTrackedBuffBars()
    return tbb and tbb.bars and #tbb.bars > 0
end

-- Listen for spell casts to start duration timers for popular buffs that
-- don't leave a detectable aura (e.g. potions), and to reset placed-unit
-- timers for effects like Consecration on successful recast.
local tbbCastListener = CreateFrame("Frame")
tbbCastListener:SetScript("OnEvent", function(_, _, _, _, spellID)
    if not spellID then return end
    if not ECME or not ECME.db then return end
    local now = GetTime()

    -- Reset placed-unit timers on recast (e.g. Consecration, efflo)
    if ns.PLACED_UNIT_DURATIONS and ns.PLACED_UNIT_DURATIONS[spellID] then
        ns._placedUnitStartCache = ns._placedUnitStartCache or {}
        ns._placedUnitStartCache[spellID] = now
    end

    -- Start custom-duration timers for popular tracked buffs that do not
    -- leave a detectable aura duration object. (e.g Consecration, Efflo etc)
    local entry = _popularSpellIDMap[spellID]
    if not entry or not entry.customDuration then return end
    local tbb = ns.GetTrackedBuffBars()
    if not tbb or not tbb.bars then return end
    for i, cfg in ipairs(tbb.bars) do
        if cfg.popularKey == entry.key then
            local bar = tbbFrames[i]
            if bar and bar._tbbReady then
                bar._customStart    = now
                bar._activeDuration = entry.customDuration
            end
        end
    end
end)

-- Listen for spell activation overlay glow events to drive glow-based bars
-- (e.g. Time Spiral). SHOW starts the custom timer, HIDE clears it.
local tbbGlowListener = CreateFrame("Frame")
tbbGlowListener:SetScript("OnEvent", function(_, event, spellID)
    if not spellID then return end
    -- spellID can be a secret value in combat; bail to avoid taint spread
    if issecretvalue and issecretvalue(spellID) then return end
    local key = _glowSpellIDMap[spellID]
    if not key then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    if not tbb or not tbb.bars then return end
    local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    local now = GetTime()
    for i, cfg in ipairs(tbb.bars) do
        if cfg.popularKey == key then
            local bar = tbbFrames[i]
            if bar and bar._tbbReady then
                if isShow then
                    if not bar._customStart then
                        bar._customStart    = now
                        bar._activeDuration = cfg.customDuration or 10
                    end
                else
                    bar._customStart    = nil
                    bar._activeDuration = nil
                end
            end
        end
    end
end)

-- Resolve player class color for default fill
local _tbbClassR, _tbbClassG, _tbbClassB = 0.05, 0.82, 0.62
do
    local _, ct = UnitClass("player")
    if ct then
        local cc = RAID_CLASS_COLORS[ct]
        if cc then _tbbClassR, _tbbClassG, _tbbClassB = cc.r, cc.g, cc.b end
    end
end

local TBB_DEFAULT_BAR = {
    spellID   = 0,
    name      = "New Bar",
    enabled   = true,
    height    = 24,
    width     = 270,
    verticalOrientation = false,
    texture   = "none",
    fillR     = _tbbClassR, fillG = _tbbClassG, fillB = _tbbClassB, fillA = 1,
    bgR       = 0, bgG = 0, bgB = 0, bgA = 0.4,
    gradientEnabled = false,
    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
    gradientDir = "HORIZONTAL",
    opacity   = 1.0,
    showTimer = true,
    timerPosition = "right",
    timerSize = 11,
    timerX    = 0,
    timerY    = 0,
    showName  = true,
    namePosition = "left",
    nameSize  = 11,
    nameX     = 0,
    nameY     = 0,
    showSpark = true,
    iconDisplay = "none",
    iconSize    = 24,
    iconX       = 0,
    iconY       = 0,
    iconBorderSize = 0,
    stacksPosition = "center",
    stacksSize     = 11,
    stacksX        = 0,
    stacksY        = 0,
    stackThresholdEnabled = false,
    stackThreshold = 5,
    stackThresholdR = 0.8,
    stackThresholdG = 0.1,
    stackThresholdB = 0.1,
    stackThresholdA = 1,
    stackThresholdMaxEnabled = false,
    stackThresholdMax = 10,
    stackThresholdTicks = "",
}
ns.TBB_DEFAULT_BAR = TBB_DEFAULT_BAR

--- Get tracked buff bars profile data (with lazy init)
function ns.GetTrackedBuffBars()
    if not ECME or not ECME.db then return { selectedBar = 1, bars = {} } end
    local p = ECME.db.profile
    if not p.trackedBuffBars then
        p.trackedBuffBars = { selectedBar = 1, bars = {} }
    end
    return p.trackedBuffBars
end

--- Add a new tracked buff bar
function ns.AddTrackedBuffBar()
    local tbb = ns.GetTrackedBuffBars()
    local newBar = {}
    -- Copy settings from the last bar if one exists, otherwise use defaults.
    -- Stack-related settings are always reset to defaults (not copied).
    local source = (#tbb.bars > 0) and tbb.bars[#tbb.bars] or TBB_DEFAULT_BAR
    local STACK_KEYS = {
        stacksPosition = true, stacksSize = true, stacksX = true, stacksY = true,
        stackThresholdEnabled = true, stackThreshold = true,
        stackThresholdR = true, stackThresholdG = true, stackThresholdB = true, stackThresholdA = true,
        stackThresholdMaxEnabled = true, stackThresholdMax = true, stackThresholdTicks = true,
    }
    for k, v in pairs(TBB_DEFAULT_BAR) do
        if STACK_KEYS[k] then
            newBar[k] = v
        else
            newBar[k] = (source[k] ~= nil) and source[k] or v
        end
    end
    -- Always reset spell-specific fields
    newBar.spellID = 0
    newBar.name = "Bar " .. (#tbb.bars + 1)
    tbb.bars[#tbb.bars + 1] = newBar
    tbb.selectedBar = #tbb.bars

    -- Auto-position: place new bar adjacent to the previous one
    -- Horizontal: stack above; Vertical: place to the right
    local p = ECME and ECME.db and ECME.db.profile
    if p then
        if not p.tbbPositions then p.tbbPositions = {} end
        local prevIdx = #tbb.bars - 1
        if prevIdx >= 1 then
            local prevPosKey = tostring(prevIdx)
            local prevPos = p.tbbPositions[prevPosKey]
            local prevCfg = tbb.bars[prevIdx]
            local newPosKey = tostring(#tbb.bars)
            if prevPos and prevPos.point then
                local px = prevPos.x or 0
                local py = prevPos.y or 0
                if newBar.verticalOrientation then
                    -- Vertical bars: place to the right of previous
                    local barW = (prevCfg and prevCfg.height or 24) + 4
                    p.tbbPositions[newPosKey] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px + barW, y = py,
                    }
                else
                    -- Horizontal bars: place above previous
                    local barH = (prevCfg and prevCfg.height or 24) + 4
                    p.tbbPositions[newPosKey] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px, y = py + barH,
                    }
                end
            end
        end
    end

    ns.BuildTrackedBuffBars()
    return #tbb.bars
end

--- Remove a tracked buff bar by index
function ns.RemoveTrackedBuffBar(idx)
    local tbb = ns.GetTrackedBuffBars()
    if idx < 1 or idx > #tbb.bars then return end
    table.remove(tbb.bars, idx)
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = math.max(1, #tbb.bars) end
    ns.BuildTrackedBuffBars()
end

--- Tracked buff bar frames
tbbFrames = {}
local tbbTickFrame
local _tbbRebuildPending = false

function ns.GetTBBFrame(idx)
    return tbbFrames[idx]
end

local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetCDMFont()
    return (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm")) or CDM_FONT_FALLBACK
end
local function GetTBBOutline()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        return EllesmereUI.GetFontOutlineFlag()
    end
    return "OUTLINE"
end
local function GetTBBUseShadow()
    if EllesmereUI and EllesmereUI.GetFontUseShadow then
        return EllesmereUI.GetFontUseShadow()
    end
    return false
end
local function SetTBBFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local outline = GetTBBOutline()
    fs:SetFont(font, size, outline)
    if GetTBBUseShadow() then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function CreateTrackedBuffBarFrame(parent, idx)
    -- wrapFrame is the top-level container for bar + icon + border.
    -- Positioning, show/hide, and unlock mode all operate on wrapFrame.
    -- The StatusBar is a child of wrapFrame so the border can use SetAllPoints
    -- on wrapFrame for a pixel-perfect fit (same pattern as the cast bar).
    local wrapFrame = CreateFrame("Frame", "ECME_TBBWrap" .. idx, parent)
    wrapFrame:SetFrameStrata("MEDIUM")
    wrapFrame:SetFrameLevel(10)

    local bar = CreateFrame("StatusBar", "ECME_TBB" .. idx, wrapFrame)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.65)
    wrapFrame._bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    wrapFrame._bg = bg

    -- Spark
    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
    spark:SetBlendMode("ADD")
    spark:Hide()
    wrapFrame._spark = spark

    -- Gradient clip frame (full-bar gradient masked to fill width)
    wrapFrame._gradClip = nil
    wrapFrame._gradTex = nil

    -- Text overlay: always sits above the fill texture and gradient clip
    local textOverlay = CreateFrame("Frame", nil, bar)
    textOverlay:SetAllPoints(bar)
    textOverlay:SetFrameLevel(bar:GetFrameLevel() + 3)
    wrapFrame._textOverlay = textOverlay

    -- Timer text
    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetTBBFont(timerText, GetCDMFont(), 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    wrapFrame._timerText = timerText

    -- Name text (left side)
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetTBBFont(nameText, GetCDMFont(), 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    wrapFrame._nameText = nameText

    -- Stacks text (positioned relative to the StatusBar)
    local stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetTBBFont(stacksText, GetCDMFont(), 11)
    stacksText:SetTextColor(1, 1, 1, 0.9)
    stacksText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    stacksText:Hide()
    wrapFrame._stacksText = stacksText

    -- Icon: child of wrapFrame so it is part of the combined rect.
    local icon = CreateFrame("Frame", nil, wrapFrame)
    icon:SetSize(24, 24)
    icon:Hide()
    local iconTex = icon:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    icon._tex = iconTex
    wrapFrame._icon = icon

    -- Border: SetAllPoints(wrapFrame) so it covers bar + icon exactly.
    -- wrapFrame IS the combined rect, so this is always pixel-perfect.
    local bdrContainer = CreateFrame("Frame", nil, wrapFrame)
    bdrContainer:SetAllPoints(wrapFrame)
    bdrContainer:SetFrameLevel(wrapFrame:GetFrameLevel() + 5)
    bdrContainer:Hide()
    wrapFrame._barBorder = bdrContainer

    -- Hidden Cooldown widget for DurationObject mirroring
    local cd = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(false)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetAlpha(0)
    cd:Hide()
    wrapFrame._cooldown = cd

    wrapFrame:Hide()
    return wrapFrame
end

-- Stack threshold overlay: a StatusBar on top of the main fill whose
-- min/max are set so it fills completely at the threshold. The engine
-- handles secret value clamping internally -- no Lua comparison needed.
local function EnsureTBBThresholdOverlay(bar)
    if bar._threshOverlay then return bar._threshOverlay end
    local sb = bar._bar
    if not sb then return nil end
    local overlay = CreateFrame("StatusBar", nil, sb)
    overlay:SetAllPoints(sb:GetStatusBarTexture())
    overlay:SetFrameLevel(sb:GetFrameLevel() + 2)
    overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    bar._threshOverlay = overlay
    return overlay
end

local function SetupTBBThresholdOverlay(bar, cfg)
    if not cfg.stackThresholdEnabled then
        if bar._threshOverlay then bar._threshOverlay:Hide() end
        return
    end
    local overlay = EnsureTBBThresholdOverlay(bar)
    if not overlay then return end

    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    overlay:SetStatusBarTexture(texPath)
    overlay:SetOrientation(cfg.verticalOrientation and "VERTICAL" or "HORIZONTAL")
    overlay:GetStatusBarTexture():SetVertexColor(
        cfg.stackThresholdR or 0.8,
        cfg.stackThresholdG or 0.1,
        cfg.stackThresholdB or 0.1,
        cfg.stackThresholdA or 1)

    -- Anchor to the main fill texture so the overlay is clipped to the
    -- filled portion of the bar (matters for passive stack-fill bars).
    overlay:ClearAllPoints()
    overlay:SetAllPoints(bar._bar:GetStatusBarTexture())

    local threshold = cfg.stackThreshold or 5
    overlay:SetMinMaxValues(threshold - 1, threshold)
    overlay:SetValue(0)
    overlay:Show()
end

local function FeedTBBThresholdOverlay(bar)
    local overlay = bar._threshOverlay
    if not overlay or not overlay:IsShown() then return end
    overlay:SetValue(bar._stackCount or 0)
end

-- Parse comma-separated tick values string into a table of numbers.
local function ParseTickValues(str)
    if not str or str == "" then return nil end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local n = tonumber(s:match("^%s*(.-)%s*$"))
        if n and n > 0 then vals[#vals + 1] = n end
    end
    if #vals == 0 then return nil end
    return vals
end

-- Apply tick marks to a bar based on config.
-- sb: the StatusBar (actual bar or preview bar)
-- cfg: bar config table (needs stackThresholdTicks, stackThresholdMax)
-- tickCache: table to store tick textures
-- isVert: vertical orientation flag
-- tickParent: optional frame to parent ticks to (above overlay)
local function ApplyTBBTickMarks(sb, cfg, tickCache, isVert, tickParent)
    local maxStacks = cfg.stackThresholdMax or 10
    local vals = ParseTickValues(cfg.stackThresholdTicks)

    if tickCache then
        for i = 1, #tickCache do tickCache[i]:Hide() end
    end

    if not cfg.stackThresholdEnabled or not cfg.stackThresholdMaxEnabled or not vals or maxStacks < 1 then return end
    if not tickCache then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local parent = tickParent or sb
    while #tickCache < #vals do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    local onePx = PP and PP.Scale(1) or 1
    local barW = sb:GetWidth()
    local barH = sb:GetHeight()
    for i, v in ipairs(vals) do
        if v <= maxStacks then
            local t = tickCache[i]
            local frac = v / maxStacks
            t:ClearAllPoints()
            if isVert then
                local off = PP and PP.Scale(barH * frac) or (barH * frac)
                t:SetSize(barW, onePx)
                t:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, off)
            else
                local off = PP and PP.Scale(barW * frac) or (barW * frac)
                t:SetSize(onePx, barH)
                t:SetPoint("TOPLEFT", sb, "TOPLEFT", off, 0)
            end
            t:Show()
        end
    end
end
ns.ApplyTBBTickMarks = ApplyTBBTickMarks

local function ApplyTrackedBuffBarSettings(bar, cfg)
    -- bar = wrapFrame (top-level container). bar._bar = the StatusBar child.
    if not bar or not cfg then return end
    local sb = bar._bar  -- StatusBar
    if not sb then return end
    local w = cfg.width or 200
    local h = cfg.height or 18
    local isVert = cfg.verticalOrientation
    bar._lastVertical = isVert  -- cached for per-frame spark re-anchor in tick
    local iconMode = cfg.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = h  -- icon always matches bar height

    -- Size wrapFrame to cover bar + icon (same as cast bar's castBarFrame).
    -- Icon and bar are positioned inside wrapFrame so the border is pixel-perfect.
    if isVert then
        -- Vertical: bar is h wide x w tall; icon adds iSize to height
        local totalH = hasIcon and (w + iSize) or w
        bar:SetSize(h, totalH)
    else
        -- Horizontal: bar is w wide x h tall; icon adds iSize to width
        local totalW = hasIcon and (w + iSize) or w
        bar:SetSize(totalW, h)
    end

    -- Position StatusBar inside wrapFrame
    sb:ClearAllPoints()
    if hasIcon then
        if isVert then
            if iconMode == "left" then
                -- Icon at bottom, bar above it
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     0, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, iSize)
            else
                -- Icon at top, bar below it
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     0, -iSize)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            end
        else
            if iconMode == "left" then
                -- Icon on left, bar to the right
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     iSize, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0,     0)
            else
                -- Icon on right, bar to the left
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     0,      0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -iSize, 0)
            end
        end
    else
        sb:SetAllPoints(bar)
    end

    -- Orientation
    sb:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")

    -- Texture (only re-set if changed to avoid fill flash)
    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    if bar._lastTexPath ~= texPath then
        sb:SetStatusBarTexture(texPath)
        bar._lastTexPath = texPath
    end

    -- Fill color (user-defined, defaults to class color)
    local fR, fG, fB, fA = cfg.fillR or _tbbClassR, cfg.fillG or _tbbClassG, cfg.fillB or _tbbClassB, cfg.fillA or 1
    sb:GetStatusBarTexture():SetVertexColor(fR, fG, fB, fA)
    bar._baseFillR, bar._baseFillG, bar._baseFillB, bar._baseFillA = fR, fG, fB, fA

    -- Background color
    if bar._bg then
        bar._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
    end

    -- Gradient (clip frame approach: full-bar gradient masked to fill width)
    local fillTex = sb:GetStatusBarTexture()
    if cfg.gradientEnabled then
        local dir = cfg.gradientDir or "HORIZONTAL"

        fillTex:SetVertexColor(1, 1, 1, 0)

        if not bar._gradClip then
            local clip = CreateFrame("Frame", nil, sb)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(sb:GetFrameLevel() + 1)

            local tex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT",     sb, "TOPLEFT",     0, 0)
            tex:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)

            bar._gradClip = clip
            bar._gradTex = tex
        end

        -- Anchor the clip frame to the fill texture so it tracks
        -- automatically when Blizzard's SetTimerDuration animates the bar.
        -- The fill texture shrinks as the buff expires; anchoring to it
        -- means the clip follows without any per-tick width calculations.
        local clip = bar._gradClip
        clip:ClearAllPoints()
        clip:SetAllPoints(fillTex)

        bar._gradTex:SetTexture(texPath)
        bar._gradTex:SetVertexColor(1, 1, 1, 1)
        bar._gradTex:SetGradient(dir,
            CreateColor(fR, fG, fB, fA),
            CreateColor(cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1)
        )

        clip:Show()
        bar._gradientActive = true
    else
        if bar._gradClip then bar._gradClip:Hide() end
        bar._gradientActive = nil

        fillTex:SetVertexColor(fR, fG, fB, fA)
    end

    -- Opacity (target stored for smooth lerp in tick)
    bar._opacityTarget = cfg.opacity or 1.0
    if not bar._tbbReady then
        bar:SetAlpha(bar._opacityTarget)
    end

    -- Timer
    local timerPos = cfg.timerPosition or (cfg.showTimer and "right" or "none")
    if timerPos ~= "none" then
        bar._timerText:Show()
        local tSize = cfg.timerSize or 11
        SetTBBFont(bar._timerText, GetCDMFont(), tSize)
        bar._timerText:ClearAllPoints()
        if isVert then
            bar._timerText:SetPoint("TOP", sb, "TOP", cfg.timerX or 0, -8 + (cfg.timerY or 0))
            bar._timerText:SetJustifyH("CENTER")
        else
            local tX = cfg.timerX or 0
            local tY = cfg.timerY or 0
            if timerPos == "center" then
                bar._timerText:SetPoint("CENTER", sb, "CENTER", tX, tY)
                bar._timerText:SetJustifyH("CENTER")
            elseif timerPos == "top" then
                bar._timerText:SetPoint("BOTTOM", sb, "TOP", tX, 5 + tY)
                bar._timerText:SetJustifyH("CENTER")
            elseif timerPos == "bottom" then
                bar._timerText:SetPoint("TOP", sb, "BOTTOM", tX, -5 + tY)
                bar._timerText:SetJustifyH("CENTER")
            elseif timerPos == "left" then
                bar._timerText:SetPoint("LEFT", sb, "LEFT", 5 + tX, tY)
                bar._timerText:SetJustifyH("LEFT")
            else -- "right"
                bar._timerText:SetPoint("RIGHT", sb, "RIGHT", -5 + tX, tY)
                bar._timerText:SetJustifyH("RIGHT")
            end
        end
    else
        bar._timerText:Hide()
    end

    -- Spark
    if cfg.showSpark then
        local sparkAnchor = (bar._gradientActive and bar._gradClip) or sb:GetStatusBarTexture()
        bar._spark:SetSize(8, h)
        bar._spark:SetRotation(0)
        bar._spark:ClearAllPoints()
        if isVert then
            bar._spark:SetPoint("CENTER", sparkAnchor, "TOP", 0, 0)
        else
            bar._spark:SetPoint("CENTER", sparkAnchor, "RIGHT", 0, 0)
        end
        bar._spark:Show()
    else
        bar._spark:Hide()
    end

    -- Name text (hidden in vertical orientation)
    local namePos = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
    if namePos ~= "none" and not isVert then
        bar._nameText:Show()
        local nSize = cfg.nameSize or 11
        SetTBBFont(bar._nameText, GetCDMFont(), nSize)
        bar._nameText:ClearAllPoints()
        local nX = cfg.nameX or 0
        local nY = cfg.nameY or 0
        if namePos == "center" then
            bar._nameText:SetPoint("CENTER", sb, "CENTER", nX, nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "top" then
            bar._nameText:SetPoint("BOTTOM", sb, "TOP", nX, 5 + nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "bottom" then
            bar._nameText:SetPoint("TOP", sb, "BOTTOM", nX, -5 + nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "right" then
            bar._nameText:SetPoint("RIGHT", sb, "RIGHT", -5 + nX, nY)
            bar._nameText:SetJustifyH("RIGHT")
        else -- "left"
            bar._nameText:SetPoint("LEFT", sb, "LEFT", 5 + nX, nY)
            bar._nameText:SetJustifyH("LEFT")
        end
        bar._nameText:SetWidth(w - 12 - (cfg.showTimer and 50 or 0))
    else
        bar._nameText:Hide()
    end

    -- Icon: positioned inside wrapFrame
    if hasIcon and bar._icon then
        bar._icon:SetSize(iSize, iSize)
        bar._icon:ClearAllPoints()
        if isVert then
            if iconMode == "left" then
                bar._icon:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            else
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            end
        else
            if iconMode == "left" then
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                bar._icon:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            end
        end
        bar._icon:Show()
    elseif bar._icon then
        bar._icon:Hide()
    end

    -- Stacks text positioning
    if bar._stacksText then
        local sPos = cfg.stacksPosition or "center"
        if sPos == "none" then
            bar._stacksText:Hide()
            bar._stacksHidden = true
        else
            bar._stacksHidden = nil
            local sSize = cfg.stacksSize or 11
            local sX = cfg.stacksX or 0
            local sY = cfg.stacksY or 0
            SetTBBFont(bar._stacksText, GetCDMFont(), sSize)
            bar._stacksText:ClearAllPoints()
            if sPos == "top" then
                bar._stacksText:SetPoint("BOTTOM", sb, "TOP", sX, 5 + sY)
            elseif sPos == "bottom" then
                bar._stacksText:SetPoint("TOP", sb, "BOTTOM", sX, -5 + sY)
            elseif sPos == "left" then
                bar._stacksText:SetPoint("LEFT", sb, "LEFT", 5 + sX, sY)
            elseif sPos == "right" then
                bar._stacksText:SetPoint("RIGHT", sb, "RIGHT", -5 + sX, sY)
            else
                bar._stacksText:SetPoint("CENTER", sb, "CENTER", sX, sY)
            end
        end
    end

    -- Border: bdrContainer already has SetAllPoints(wrapFrame) from creation.
    -- wrapFrame IS the combined rect, so the border is always pixel-perfect.
    if bar._barBorder then
        local bSz = cfg.borderSize or 0
        if bSz > 0 then
            local PP = EllesmereUI and EllesmereUI.PP
            if PP then
                if not bar._barBorder._ppBorders then
                    PP.CreateBorder(bar._barBorder, cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1, bSz)
                else
                    PP.UpdateBorder(bar._barBorder, bSz, cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1)
                end
                bar._barBorder:Show()
            end
        else
            bar._barBorder:Hide()
        end
    end

    -- Stack threshold overlay (stacked StatusBar approach, secret-safe)
    SetupTBBThresholdOverlay(bar, cfg)

    -- Stack threshold tick marks (above the threshold overlay)
    if not bar._threshTicks then bar._threshTicks = {} end
    if not bar._tickOverlay then
        local to = CreateFrame("Frame", nil, sb)
        to:SetAllPoints(sb)
        to:SetFrameLevel(sb:GetFrameLevel() + 3)
        bar._tickOverlay = to
    end
    ApplyTBBTickMarks(sb, cfg, bar._threshTicks, isVert, bar._tickOverlay)
    bar._ticksDirty = true  -- bar may not have valid dimensions yet; re-apply once laid out
end

-- Reusable helpers for secret-safe aura field access (avoids closure allocation per tick)
local _tbbAura
local function _TBBGetDuration() return _tbbAura.duration end
local function _TBBGetExpiration() return _tbbAura.expirationTime end
local function _TBBGetName() return _tbbAura.name end
local function _TBBGetSpellId() return _tbbAura.spellId end

-- Scan player HELPFUL auras by name and return the matching auraData + spellId.
-- Cleans up _tbbAura after use so callers don't leak stale references.
-- Skips the scan entirely in combat since aura names are secret values.
local function _TBBScanByName(name)
    if InCombatLockdown() then return nil, nil end
    for ai = 1, 40 do
        local aData = C_UnitAuras.GetAuraDataByIndex("player", ai, "HELPFUL")
        if not aData then break end
        _tbbAura = aData
        local nOk, aName = pcall(_TBBGetName)
        if nOk and aName then
            -- Guard against secret values that slip through OOC edge cases.
            -- Wrap the comparison itself in pcall so tainted strings that
            -- bypass issecretvalue cannot propagate an error.
            if issecretvalue and issecretvalue(aName) then
                -- skip, can't compare
            else
                local cmpOk, matched = pcall(function() return aName == name end)
                if cmpOk and matched then
                    local sOk, sid = pcall(_TBBGetSpellId)
                    _tbbAura = nil
                    if sOk and sid and not (issecretvalue and issecretvalue(sid)) and sid > 0 then
                        return aData, sid
                    end
                    return nil, nil
                end
            end
        end
    end
    _tbbAura = nil
    return nil, nil
end

-- Scan current player buffs OOC to cache the real aura spellID for each TBB bar.
local function RefreshTBBResolvedIDs()
    if InCombatLockdown() then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and cfg.enabled ~= false and cfg.spellID and cfg.spellID > 0 and cfg.name and cfg.name ~= "" then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, cfg.spellID)
            if ok and aura then
                bar._resolvedAuraID = cfg.spellID
            else
                local _, sid = _TBBScanByName(cfg.name)
                if sid then bar._resolvedAuraID = sid end
            end
        end
    end
end
ns.RefreshTBBResolvedIDs = RefreshTBBResolvedIDs

-- Cache _customStart for popular buff bars on UNIT_AURA so the fill timer
-- starts at the right moment. Only needed for multi-ID (popular) bars that
-- use customDuration. Single-ID bars use the DurationObject path from the
-- Blizzard CDM child and need no event-driven caching.
local tbbAuraListener = CreateFrame("Frame")
tbbAuraListener:SetScript("OnEvent", function()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end
    local now = GetTime()
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and bar._tbbReady and cfg.enabled ~= false and cfg.spellIDs and cfg.customDuration then
            -- Only initialize _customStart if not already running
            if not bar._customStart then
                for _, sid in ipairs(cfg.spellIDs) do
                    local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                    if ok and result then
                        local dur = result.duration
                        local exp = result.expirationTime
                        local secretD = issecretvalue and issecretvalue(dur)
                        local secretE = issecretvalue and issecretvalue(exp)
                        if not secretD and not secretE and dur and exp and dur > 0 and exp > 0 then
                            bar._activeDuration = cfg.customDuration
                            bar._customStart = now - (cfg.customDuration - math.max(0, exp - now))
                        else
                            -- Secret or no duration: start timer from now
                            bar._activeDuration = cfg.customDuration
                            bar._customStart = now
                        end
                        break
                    end
                end
            end
        end
    end
end)

--- Register or unregister TBB event listeners based on whether any bars are configured.
--- Call this whenever bars are added or removed.
function ns.RefreshBuffBarGating()
    local hasBars = ns.HasBuffBars()
    if hasBars then
        if not tbbCastListener:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED") then
            tbbCastListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        if not tbbAuraListener:IsEventRegistered("UNIT_AURA") then
            tbbAuraListener:RegisterUnitEvent("UNIT_AURA", "player")
        end
        if not tbbGlowListener:IsEventRegistered("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") then
            tbbGlowListener:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            tbbGlowListener:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        end
    else
        tbbCastListener:UnregisterAllEvents()
        tbbAuraListener:UnregisterAllEvents()
        tbbGlowListener:UnregisterAllEvents()
    end
end

function ns.BuildTrackedBuffBars()
    if not TBB_ENABLED then return end
    if not ECME or not ECME.db then return end
    if InCombatLockdown() then
        _tbbRebuildPending = true
        return
    end
    _tbbRebuildPending = false

    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local p = ECME.db.profile
    if not p.tbbPositions then p.tbbPositions = {} end

    -- Hide bars beyond current count
    for i = #bars + 1, #tbbFrames do
        if tbbFrames[i] then tbbFrames[i]:Hide() end
    end

    local anyEnabled = false
    for i, cfg in ipairs(bars) do
        if not tbbFrames[i] then
            tbbFrames[i] = CreateTrackedBuffBarFrame(UIParent, i)
        end
        local bar = tbbFrames[i]

        if cfg.enabled == false then
            bar:Hide()
        else
            anyEnabled = true
            ApplyTrackedBuffBarSettings(bar, cfg)

            -- Icon texture: for popular buffs use the hardcoded icon, otherwise resolve from spell info
            if bar._icon and bar._icon._tex then
                local iconID = nil
                if cfg.popularKey then
                    -- Find the matching popular entry for its hardcoded icon
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then iconID = pe.icon; break end
                    end
                end
                if not iconID and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    if spInfo then iconID = spInfo.iconID end
                end
                if iconID then bar._icon._tex:SetTexture(iconID) end
            end

            -- Name text: prefer stored name (preserves custom item/spell names),
            -- fall back to spell info only when no name was stored.
            local namePos2 = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
            if namePos2 ~= "none" and bar._nameText then
                local displayName = cfg.name
                if (not displayName or displayName == "") and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    displayName = spInfo and spInfo.name or ""
                end
                bar._nameText:SetText(displayName or "")
            end

            -- Saved position
            local posKey = tostring(i)
            local pos = p.tbbPositions[posKey]
            if pos and pos.point then
                -- Skip for unlock-anchored bars (anchor system is authority)
                local unlockKey = "TBB_" .. posKey
                local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                if not anchored or not bar:GetLeft() then
                    bar:ClearAllPoints()
                    if pos.scale then pcall(function() bar:SetScale(pos.scale) end) end
                    bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                end
            else
                bar:ClearAllPoints()
                bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200 - (i - 1) * ((cfg.height or 24) + 4))
            end

            -- Mark bar as ready but keep hidden; the tick will show it
            -- when the tracked buff is actually active on the player.
            bar._tbbReady = true
            bar._isPassive = nil
            bar._resolvedAuraID = nil
            bar._blizzChild = nil
            bar._customStart = nil
            bar._activeDuration = nil
            bar._lastLiveIcon = nil
            bar._lastLiveName = nil
            bar:Hide()
        end
    end

    if anyEnabled then
        if not tbbTickFrame then
            tbbTickFrame = CreateFrame("Frame")
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                -- Run every frame for smooth bar fill and spark movement,
                -- same as the cast bar approach.
                -- Smooth opacity lerp for all active bars
                local lerpSpeed = elapsed * 8
                for _, f in ipairs(tbbFrames) do
                    if f and f._opacityTarget then
                        local cur = f:GetAlpha()
                        local tgt = f._opacityTarget
                        if math.abs(cur - tgt) > 0.005 then
                            f:SetAlpha(cur + (tgt - cur) * math.min(1, lerpSpeed))
                        elseif cur ~= tgt then
                            f:SetAlpha(tgt)
                        end
                    end
                end
                ns.UpdateTrackedBuffBarTimers()
            end)
        end
        tbbTickFrame:Show()
    elseif tbbTickFrame then
        tbbTickFrame:Hide()
    end

    -- Re-register all bars with unlock mode so new/removed bars are reflected
    if ns.RegisterTBBUnlockElements then
        ns.RegisterTBBUnlockElements()
    end
    -- Gate event listeners based on whether any bars are configured
    ns.RefreshBuffBarGating()
end

-------------------------------------------------------------------------------
--  TBB Applications hook: mirrors Blizzard CDM's Applications Show/Hide onto
--  our _stacksText, same pattern as the main CDM bars' HookBlizzChildApplications.
--  Blizzard only shows the Applications frame when stacks > 1, so we trust
--  its Show/Hide as the gate -- no value comparison needed.
-------------------------------------------------------------------------------
local _tbbStackHookedChildren = {}

local function HookTBBBlizzChildApplications(blizzChild)
    if not blizzChild or _tbbStackHookedChildren[blizzChild] then return end
    local appsFrame = blizzChild.Applications
    if not appsFrame then return end
    local appsText = appsFrame.Applications
    if not appsText then return end

    _tbbStackHookedChildren[blizzChild] = true

    hooksecurefunc(appsFrame, "Show", function()
        local tbbBar = blizzChild._tbbBar
        if not tbbBar or not tbbBar._stacksText then return end
        if tbbBar._blizzChild ~= blizzChild then return end
        if tbbBar._stacksHidden then return end
        local ok, txt = pcall(appsText.GetText, appsText)
        if ok and txt then
            tbbBar._stacksText:SetText(txt)
            tbbBar._stacksText:Show()
            local nOk, n = pcall(tonumber, txt)
            tbbBar._stackCount = (nOk and n) or 0
        end
    end)

    hooksecurefunc(appsFrame, "Hide", function()
        local tbbBar = blizzChild._tbbBar
        if tbbBar and tbbBar._stacksText and tbbBar._blizzChild == blizzChild then
            tbbBar._stacksText:Hide()
            tbbBar._stackCount = 0
        end
    end)
end

-- Secret-safe helper: returns true if apps should be displayed as stacks.
-- Non-secret: checks apps > 1. Secret: attempts comparison via pcall;
-- if it errors (truly opaque), returns true so FontString renders natively.
local function ShouldShowStacks(apps)
    if not apps then return false end
    local isSecret = issecretvalue and issecretvalue(apps)
    if not isSecret then return apps > 1 end
    local ok, gt1 = pcall(function() return apps > 1 end)
    if not ok then return true end
    return gt1
end

-- Helper: update stacks text and count for a TBB bar.
-- Display: passes Blizzard child Applications text directly (handles secrets).
-- Count: stores applications value on bar._stackCount for the threshold overlay.
-- Since the overlay uses SetValue (secret-safe), _stackCount can be secret.
--
-- Spells from Blizzard's "Tracked Buffs" (buff viewers, vi=3,4) have a native
-- Applications sub-frame that Blizzard manages -- we just read it directly.
-- Spells from "Tracked Bars" (CD/utility viewers, vi=1,2) lack that native
-- handling, so we hook Applications Show/Hide and fall back to aura API.
local function UpdateTBBStacks(bar, cfg)
    if not bar._stacksText then bar._stackCount = 0; return end
    if bar._stacksHidden then bar._stacksText:Hide(); bar._stackCount = 0; return end

    local buffChildCache = ns._tickBlizzBuffChildCache
    local allChildCache  = ns._tickBlizzAllChildCache
    local auraCache      = ns._tickAuraCache

    -- Multi-ID (popular) bars: check each spellID
    if cfg.spellIDs then
        for _, sid in ipairs(cfg.spellIDs) do
            -- Prefer buff viewer child (native Applications); fall back to bar viewer
            local isBuffViewer = buffChildCache[sid] ~= nil
            local blzChild = buffChildCache[sid] or allChildCache[sid]

            -- Only hook bar-viewer children (buff viewers handle stacks natively)
            if blzChild and not isBuffViewer then
                blzChild._tbbBar = bar
                bar._blizzChild = blzChild
                HookTBBBlizzChildApplications(blzChild)
            end
            if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
                local appsText = blzChild.Applications.Applications
                if appsText then
                    local ok, txt = pcall(appsText.GetText, appsText)
                    if ok and txt then
                        bar._stacksText:SetText(txt)
                        bar._stacksText:Show()
                        local nOk, n = pcall(tonumber, txt)
                        bar._stackCount = (nOk and n) or 0
                        return
                    end
                end
            end
            -- Aura fallback only for bar-viewer spells (no native Applications)
            if not isBuffViewer and auraCache then
                local aura = auraCache[sid]
                if aura == nil then
                    local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                    aura = (ok and res) or false
                    auraCache[sid] = aura
                end
                if aura and aura.applications and ShouldShowStacks(aura.applications) then
                    bar._stacksText:SetText(aura.applications)
                    bar._stacksText:Show()
                    bar._stackCount = aura.applications
                    return
                end
            end
        end
        bar._stacksText:Hide()
        bar._stackCount = 0
        return
    end

    -- Single-ID bars
    local resolvedID = bar._resolvedAuraID or cfg.spellID
    if not resolvedID or resolvedID <= 0 then
        bar._stacksText:Hide()
        bar._stackCount = 0
        return
    end

    -- Check if the spell lives in a buff viewer (native Applications handling)
    local isBuffViewer = buffChildCache[resolvedID] ~= nil or buffChildCache[cfg.spellID] ~= nil
    local blzChild = buffChildCache[resolvedID] or allChildCache[resolvedID]
                  or buffChildCache[cfg.spellID] or allChildCache[cfg.spellID]

    -- Only hook bar-viewer children (buff viewers handle stacks natively)
    if blzChild and not isBuffViewer then
        blzChild._tbbBar = bar
        bar._blizzChild = blzChild
        HookTBBBlizzChildApplications(blzChild)
    end

    -- Path 1: Blizzard child Applications frame (works for both viewer types)
    if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
        local appsText = blzChild.Applications.Applications
        if appsText then
            local ok, txt = pcall(appsText.GetText, appsText)
            if ok and txt then
                bar._stacksText:SetText(txt)
                bar._stacksText:Show()
                local apps
                if auraCache then
                    local aura = auraCache[resolvedID]
                    if aura == nil then
                        local aOk, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedID)
                        aura = (aOk and res) or false
                        auraCache[resolvedID] = aura
                    end
                    if aura and aura.applications then apps = aura.applications end
                end
                if not apps and blzChild.auraInstanceID then
                    local aOk, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, blzChild.auraDataUnit or "player", blzChild.auraInstanceID)
                    if aOk and ad and ad.applications then apps = ad.applications end
                end
                bar._stackCount = apps or 0
                if not apps then
                    local nOk, n = pcall(tonumber, txt)
                    if nOk and n then bar._stackCount = n end
                end
                return
            end
        end
    end

    -- Buff-viewer spells: if Applications frame isn't shown, no stacks to display.
    -- Skip aura fallbacks that can produce "0" for non-stacking buffs.
    if isBuffViewer then
        bar._stacksText:Hide()
        bar._stackCount = 0
        return
    end

    -- Path 2: aura cache lookup (bar-viewer children without Applications frame)
    if auraCache then
        local aura = auraCache[resolvedID]
        if aura == nil then
            local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedID)
            aura = (ok and res) or false
            auraCache[resolvedID] = aura
        end
        if aura and aura.applications then
            bar._stackCount = aura.applications
            if ShouldShowStacks(aura.applications) then
                bar._stacksText:SetText(aura.applications)
                bar._stacksText:Show()
            else
                bar._stacksText:Hide()
            end
            return
        end
    end

    -- Path 3: Blizzard child auraInstanceID fallback (bar-viewer only)
    if blzChild and blzChild.auraInstanceID then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, blzChild.auraDataUnit or "player", blzChild.auraInstanceID)
        if ok and ad and ad.applications then
            bar._stackCount = ad.applications
            if ShouldShowStacks(ad.applications) then
                bar._stacksText:SetText(ad.applications)
                bar._stacksText:Show()
            else
                bar._stacksText:Hide()
            end
            return
        end
    end

    bar._stacksText:Hide()
    bar._stackCount = 0
end

function ns.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local now = GetTime()
    local activeCache = ns._tickBlizzActiveCache
    local buffChildCache = ns._tickBlizzBuffChildCache
    local allChildCache = ns._tickBlizzAllChildCache
    local IsBufChildActive = ns.IsBufChildCooldownActive
    local inCombat = InCombatLockdown()

    -- Self-heal placeholder mode if user navigated away from Buff Bars
    if ns._tbbPlaceholderMode then
        local ap = EllesmereUI and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        if ap ~= "Buff Bars" then
            ns._tbbPlaceholderMode = false
            if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
        end
    end

    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if not bar or not bar._tbbReady then
            -- bar not configured or disabled, skip
        elseif ns._tbbPlaceholderMode then
            -- Buff Bars options tab is open; keep bars visible for placeholders
            if not bar:IsShown() then bar:Show() end
        elseif cfg.enabled == false then
            bar:Hide()
        elseif cfg.glowBased then
            -- Glow-based bar (e.g. Time Spiral). Active only while _customStart is set
            -- by the SPELL_ACTIVATION_OVERLAY_GLOW listener.
            local sb = bar._bar
            if bar._customStart then
                local activeDur = bar._activeDuration or cfg.customDuration or 10
                local elapsed = now - bar._customStart
                local remaining = math.max(0, activeDur - elapsed)
                if remaining > 0 then
                    if not bar:IsShown() then bar:Show() end
                    local frac = remaining / activeDur
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(frac)
                    if cfg.showTimer and bar._timerText then
                        local t
                        if remaining >= 10 then t = format("%d", floor(remaining))
                        else t = format("%.1f", remaining) end
                        bar._timerText:SetText(t)
                        bar._timerText:Show()
                    end
                else
                    bar._customStart    = nil
                    bar._activeDuration = nil
                    bar:Hide()
                end
                FeedTBBThresholdOverlay(bar)
                if bar._ticksDirty and sb then
                    local w = sb:GetWidth()
                    if w and w > 0 then
                        ApplyTBBTickMarks(sb, cfg, bar._threshTicks, cfg.verticalOrientation, bar._tickOverlay)
                        bar._ticksDirty = nil
                    end
                end
            else
                if bar:IsShown() then bar:Hide() end
                if bar._stacksText then bar._stacksText:Hide() end
            end
        elseif cfg.spellIDs then
            -- Multi-ID bar (popular buffs). Active if any ID is in the CDM active cache.
            local sb = bar._bar  -- StatusBar child of wrapFrame
            local isActive = false
            for _, sid in ipairs(cfg.spellIDs) do
                if activeCache[sid] then
                    isActive = true
                    break
                end
            end

            -- Fall back to cast-triggered custom timer (covers potions etc. that
            -- may not appear in CDM viewers at all)
            if not isActive and bar._customStart then
                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 then
                    local elapsed = now - bar._customStart
                    if elapsed < activeDur then
                        isActive = true
                    else
                        bar._customStart    = nil
                        bar._activeDuration = nil
                    end
                end
            end

            if isActive then
                if not bar:IsShown() then bar:Show() end
                UpdateTBBStacks(bar, cfg)

                -- All multi-ID bars use customDuration for the fill animation
                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 and bar._customStart then
                    local elapsed = now - bar._customStart
                    local remaining = math.max(0, activeDur - elapsed)
                    local frac = remaining / activeDur
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(frac)
                    if cfg.showTimer and bar._timerText then
                        if remaining <= 0 then
                            bar._timerText:Hide()
                        else
                            local t
                            if remaining >= 60 then t = format("%dm", floor(remaining / 60))
                            elseif remaining >= 10 then t = format("%d", floor(remaining))
                            else t = format("%.1f", remaining) end
                            bar._timerText:SetText(t)
                            bar._timerText:Show()
                        end
                    end
                    if remaining <= 0 then
                        bar._customStart    = nil
                        bar._activeDuration = nil
                        bar:Hide()
                    end
                else
                    -- Active but no custom timer started yet (or permanent)
                    sb:SetValue(1)
                    if cfg.showTimer and bar._timerText then bar._timerText:Hide() end
                end
                FeedTBBThresholdOverlay(bar)
                -- Re-apply tick marks once bar has valid dimensions after layout
                if bar._ticksDirty and bar._bar then
                    local w = bar._bar:GetWidth()
                    if w and w > 0 then
                        ApplyTBBTickMarks(bar._bar, cfg, bar._threshTicks, cfg.verticalOrientation, bar._tickOverlay)
                        bar._ticksDirty = nil
                    end
                end
            else
                if bar:IsShown() then bar:Hide() end
                if bar._stacksText then bar._stacksText:Hide() end
            end
        elseif not cfg.spellID or cfg.spellID == 0 then
            bar:Hide()
        else
            local spellID = cfg.spellID
            local resolvedID = bar._resolvedAuraID or spellID
            local sb = bar._bar  -- StatusBar child of wrapFrame

            -- Check active state using the same caches the core CDM builds
            local isActive = activeCache[resolvedID] or activeCache[spellID]
            local blzChild = buffChildCache[resolvedID] or buffChildCache[spellID]
                          or allChildCache[resolvedID] or allChildCache[spellID]
            if not isActive then
                if IsBufChildActive and IsBufChildActive(blzChild) then
                    isActive = true
                end
            end
            -- Fallback: check player auras directly (covers passives and
            -- buffs not tracked by Blizzard CDM)
            if not isActive then
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedID)
                if not ok or not aura then
                    ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
                end
                if ok and aura then isActive = true end
            end

            if not isActive and inCombat and (cfg.customDuration or bar._activeDuration) and bar._customStart then
                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 then
                    local elapsed = now - bar._customStart
                    if elapsed < activeDur then
                        isActive = true
                    else
                        bar._customStart    = nil
                        bar._activeDuration = nil
                    end
                end
            end

            if isActive then
                if not bar:IsShown() then bar:Show() end
                UpdateTBBStacks(bar, cfg)

                -- Dynamically update icon from Blizzard CDM child's live texture
                -- so aura-driven icon changes (e.g. Roll the Bones sub-buffs) are
                -- reflected each tick instead of staying on the static config icon.
                if blzChild and bar._icon and bar._icon._tex and blzChild.Icon and blzChild.Icon.GetTexture then
                    local liveIconTex = blzChild.Icon:GetTexture()
                    local isSecret = issecretvalue and issecretvalue(liveIconTex)
                    if not isSecret and liveIconTex and liveIconTex ~= bar._lastLiveIcon then
                        bar._icon._tex:SetTexture(liveIconTex)
                        bar._lastLiveIcon = liveIconTex
                    end
                end

                -- Dynamically update name text from the actual active aura so
                -- spells like Roll the Bones show the specific roll name instead
                -- of the generic parent spell name.
                if bar._nameText and bar._nameText:IsShown() and blzChild and blzChild.auraInstanceID then
                    local nOk, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, blzChild.auraDataUnit or "player", blzChild.auraInstanceID)
                    if nOk and ad and ad.name then
                        local isSecret = issecretvalue and issecretvalue(ad.name)
                        if not isSecret and ad.name ~= bar._lastLiveName then
                            bar._nameText:SetText(ad.name)
                            bar._lastLiveName = ad.name
                        end
                    end
                end

                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 and bar._customStart then
                    local elapsed = now - bar._customStart
                    local remaining = math.max(0, activeDur - elapsed)
                    local frac = remaining / activeDur
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(frac)

                    if cfg.showTimer and bar._timerText then
                        if remaining <= 0 then
                            bar._timerText:Hide()
                        else
                            local t
                            if remaining >= 3600 then t = format("%dh", floor(remaining / 3600))
                            elseif remaining >= 60 then t = format("%dm", floor(remaining / 60))
                            elseif remaining >= 10 then t = format("%d", floor(remaining))
                            else t = format("%.1f", remaining) end
                            bar._timerText:SetText(t)
                            bar._timerText:Show()
                        end
                    end

                    if remaining <= 0 then
                        bar._customStart    = nil
                        bar._activeDuration = nil
                        bar:Hide()
                    end
                else
                    -- Standard path: try DurationObject via Blizzard CDM child.
                    -- If no duration object is available (passives, permanent
                    -- buffs, or spells not tracked by Blizzard CDM), default
                    -- to a full bar with timer hidden.
                    local durObj = nil
                    if blzChild then
                        local auraID = blzChild.auraInstanceID
                        local auraUnit = blzChild.auraDataUnit or "player"
                        if auraID then
                            local ok, d = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraID)
                            if ok and d then durObj = d end
                        end
                    end

                    -- Totem/summon fallback: use the DurationObject or raw
                    -- start+dur that the main CDM already captured via its
                    -- SetCooldown / SetCooldownFromDurationObject hooks.
                    if not durObj and blzChild then
                        local cachedDurObj = ns._ecmeDurObjCache[blzChild]
                        if cachedDurObj then
                            durObj = cachedDurObj
                        end
                    end

                    -- Raw start+dur fallback (totems): drive the bar manually
                    -- from the plain numbers the main CDM hooks captured.
                    local rawRemaining, rawDur, rawIsSecret
                    if not durObj and blzChild then
                        local rs = ns._ecmeRawStartCache[blzChild]
                        local rd = ns._ecmeRawDurCache[blzChild]
                        if rs and rd then
                            local sRS = issecretvalue and issecretvalue(rs)
                            local sRD = issecretvalue and issecretvalue(rd)
                            if sRS or sRD then
                                rawIsSecret = true
                                local ok, calcRem = pcall(function() return (rs + rd) - now end)
                                if ok and calcRem then
                                    rawRemaining = calcRem
                                    rawDur = rd
                                end
                            elseif type(rs) == "number" and type(rd) == "number" and rd > 0 then
                                rawRemaining = math.max(0, (rs + rd) - now)
                                rawDur = rd
                            end
                        end
                    end

                    -- Placed unit fixed duration fallback (e.g. Consecration)
                    if not durObj and not rawRemaining then
                        local fixedDur = ns.PLACED_UNIT_DURATIONS[resolvedID]
                        if fixedDur then
                            local startCache = ns._placedUnitStartCache
                            if startCache then
                                if not startCache[resolvedID] then
                                    startCache[resolvedID] = now
                                end
                                rawRemaining = math.max(0, (startCache[resolvedID] + fixedDur) - now)
                                rawDur = fixedDur
                            end
                        end
                    end

                    -- Validate the duration object actually has remaining time.
                    -- Permanent/passive buffs may return a durObj that reads as
                    -- zero, which would render an empty bar.
                    -- We cache passive state on the bar so it persists into combat.
                    local useDurObj = false
                    if durObj then
                        local ok, rem = pcall(durObj.GetRemainingDuration, durObj)
                        if ok and rem then
                            local isSecret = issecretvalue and issecretvalue(rem)
                            if isSecret then
                                -- In combat: trust cached passive state if we have it
                                if bar._isPassive then
                                    useDurObj = false
                                else
                                    useDurObj = true
                                end
                            elseif rem > 0 then
                                useDurObj = true
                                bar._isPassive = false
                            else
                                -- rem == 0 out of combat means passive/permanent
                                bar._isPassive = true
                            end
                        end
                    else
                        -- No durObj: passive unless raw fallback available
                        if rawIsSecret then
                            if rawRemaining then
                                bar._isPassive = false
                            end
                        elseif not (rawRemaining and rawRemaining > 0) then
                            bar._isPassive = true
                        end
                    end

                    if useDurObj then
                        sb:SetMinMaxValues(0, 1)
                        sb:SetTimerDuration(durObj, Enum.StatusBarInterpolation.None, Enum.StatusBarTimerDirection.RemainingTime)
                        sb:SetToTargetValue()
                        if cfg.showSpark and bar._spark then bar._spark:Show() end

                        if cfg.showTimer and bar._timerText then
                            local ok, remaining = pcall(durObj.GetRemainingDuration, durObj)
                            if ok and remaining then
                                local isSecret = issecretvalue and issecretvalue(remaining)
                                if isSecret then
                                    local fok, fstr = pcall(format, "%.1f", remaining)
                                    if fok and fstr then
                                        bar._timerText:SetText(fstr)
                                    else
                                        bar._timerText:SetText(remaining)
                                    end
                                else
                                    local t
                                    if remaining >= 3600 then t = format("%dh", floor(remaining / 3600))
                                    elseif remaining >= 60 then t = format("%dm", floor(remaining / 60))
                                    elseif remaining >= 10 then t = format("%d", floor(remaining))
                                    else t = format("%.1f", remaining) end
                                    bar._timerText:SetText(t)
                                end
                                bar._timerText:Show()
                            else
                                bar._timerText:Hide()
                            end
                        end
                    elseif rawRemaining and (rawIsSecret or rawRemaining > 0) then
                        -- Raw start+dur path (totems/summons): manual bar fill
                        sb:SetMinMaxValues(0, 1)
                        if rawIsSecret then
                            pcall(sb.SetValue, sb, rawRemaining / rawDur)
                        else
                            sb:SetValue(rawRemaining / rawDur)
                        end
                        if cfg.showSpark and bar._spark then bar._spark:Show() end
                        if cfg.showTimer and bar._timerText then
                            if rawIsSecret then
                                local fok, fstr = pcall(format, "%.1f", rawRemaining)
                                if fok and fstr then
                                    bar._timerText:SetText(fstr)
                                else
                                    bar._timerText:SetText("")
                                end
                            else
                                local t
                                if rawRemaining >= 3600 then t = format("%dh", floor(rawRemaining / 3600))
                                elseif rawRemaining >= 60 then t = format("%dm", floor(rawRemaining / 60))
                                elseif rawRemaining >= 10 then t = format("%d", floor(rawRemaining))
                                else t = format("%.1f", rawRemaining) end
                                bar._timerText:SetText(t)
                            end
                            bar._timerText:Show()
                        end
                    else
                        -- Permanent/passive buff or no valid duration
                        local maxS = cfg.stackThresholdMax
                        if bar._isPassive and cfg.stackThresholdMaxEnabled and maxS and maxS > 0 then
                            sb:SetMinMaxValues(0, maxS)
                            sb:SetValue(bar._stackCount or 0)
                        else
                            sb:SetMinMaxValues(0, 1)
                            sb:SetValue(1)
                        end
                        if bar._timerText then bar._timerText:Hide() end
                        if bar._spark then bar._spark:Hide() end
                    end
                end
                -- Feed threshold overlay each tick (secret-safe, no comparison)
                FeedTBBThresholdOverlay(bar)
                -- Re-apply tick marks once bar has valid dimensions after layout
                if bar._ticksDirty and bar._bar then
                    local w = bar._bar:GetWidth()
                    if w and w > 0 then
                        ApplyTBBTickMarks(bar._bar, cfg, bar._threshTicks, cfg.verticalOrientation, bar._tickOverlay)
                        bar._ticksDirty = nil
                    end
                end
            else
                -- Buff not active, hide the bar and clear state
                if bar:IsShown() then bar:Hide() end
                if bar._stacksText then bar._stacksText:Hide() end
                bar._resolvedAuraID = nil
                bar._blizzChild = nil
                bar._customStart = nil
                bar._activeDuration = nil
                bar._isPassive = nil
                bar._lastLiveIcon = nil
                bar._lastLiveName = nil
                if bar._cooldown then bar._cooldown:Clear() end
            end
        end
    end

    -- Re-anchor sparks every frame so they track the fill edge smoothly,
    -- same as the cast bar approach.
    for _, bar in ipairs(tbbFrames) do
        if bar and bar._spark and bar._spark:IsShown() and bar._bar then
            local sb = bar._bar
            local cfg_isVert = bar._lastVertical  -- cached from ApplyTrackedBuffBarSettings
            bar._spark:ClearAllPoints()
            if bar._gradientActive and bar._gradClip then
                if cfg_isVert then
                    bar._spark:SetPoint("CENTER", bar._gradClip, "TOP", 0, 0)
                else
                    bar._spark:SetPoint("CENTER", bar._gradClip, "RIGHT", 0, 0)
                end
            else
                if cfg_isVert then
                    bar._spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "TOP", 0, 0)
                else
                    bar._spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "RIGHT", 0, 0)
                end
            end
        end
    end
end
function ns.IsTBBRebuildPending()
    return _tbbRebuildPending
end

-------------------------------------------------------------------------------
--  Register Tracked Buff Bars with unlock mode
-------------------------------------------------------------------------------
function ns.RegisterTBBUnlockElements()
    if not TBB_ENABLED then return end
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    if not ECME or not ECME.db then return end
    local MK = EllesmereUI.MakeUnlockElement
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then bars = {} end

    if not bars or #bars == 0 then return end

    local elements = {}
    for i, cfg in ipairs(bars) do
        local idx = i
        local posKey = tostring(idx)
        local bar = tbbFrames[idx]
        if bar then
            elements[#elements + 1] = MK({
                key = "TBB_" .. posKey,
                label = "Buff Bar: " .. (cfg.name or ("Bar " .. idx)),
                group = "Cooldown Manager",
                order = 650,
                isHidden = function()
                    -- If this index exceeds the current bar count, it is a
                    -- stale registration from a previous spec/profile.
                    local tbb2 = ns.GetTrackedBuffBars()
                    local b = tbb2 and tbb2.bars
                    return not b or idx > #b
                end,
                getFrame = function() return tbbFrames[idx] end,
                getSize = function()
                    local f = tbbFrames[idx]
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 200, 24
                end,
                setWidth = function(_, w)
                    local tbb2 = ns.GetTrackedBuffBars()
                    local c = tbb2.bars and tbb2.bars[idx]
                    if c then c.width = w; ns.BuildTrackedBuffBars() end
                end,
                setHeight = function(_, h)
                    local tbb2 = ns.GetTrackedBuffBars()
                    local c = tbb2.bars and tbb2.bars[idx]
                    if c then c.height = h; ns.BuildTrackedBuffBars() end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local p = ECME.db.profile
                    if not p.tbbPositions then p.tbbPositions = {} end
                    p.tbbPositions[posKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    local f = tbbFrames[idx]
                    if f then
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x, y)
                    end
                    ns.BuildTrackedBuffBars()
                end,
                loadPos = function()
                    local p = ECME.db.profile
                    return p.tbbPositions and p.tbbPositions[posKey]
                end,
                clearPos = function()
                    local p = ECME.db.profile
                    if p.tbbPositions then p.tbbPositions[posKey] = nil end
                end,
                applyPos = function()
                    ns.BuildTrackedBuffBars()
                end,
            })
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements)
    end
end
_G._ECME_RegisterTBBUnlock = ns.RegisterTBBUnlockElements


