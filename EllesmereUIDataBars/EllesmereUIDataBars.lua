-- EllesmereUIDataBars: user-created multi-bar engine.
--
-- ENGINE FILE. Owns:
--   * DB + fresh profile shape (bars array, monotonic never-reused ids)
--   * shared infra: fonts, formatters, heartbeat, OOC deferral, frame pool,
--     popup helper, text fit cache
--   * the owned rich tooltip (replaces every GameTooltip call site)
--   * the layout solver (auto-fit px + pct weight partition of the remainder)
--   * the bar factory: frame, theme (eui atlas cover-fit / modern flat),
--     slots, per-block background + hover overlay, teardown
--   * visibility runtime (multi-select engine + legacy scalar fallback +
--     per-bar mouseover poll proxies)
--   * unlock-mode registration (one element per bar, key "EDB_<id>")
--   * the bar/block CRUD API on `ns` consumed by the options file
--
-- Block factories (clock, fps, ms, gold, xprep, spec, profession, travel,
-- micromenu, currency, spacer) live in EllesmereUIDataBars_Blocks.lua and
-- attach themselves to ns.BlockFactories.
--
-- API HANDOFF (everything the options file may call; nothing else):
--   ns.GetProfile() -> profile
--   ns.BarsInOrder() -> ordered array of barCfg (live table; read-only)
--   ns.GetBar(id) -> barCfg | nil
--   ns.CreateBar(templateKey) -> barCfg    "bottom"|"minimapc"|"microstrip"|"empty"
--   ns.DeleteBar(id)                       no confirm (UI confirms)
--   ns.RenameBar(id, name)
--   ns.SetBarEnabled(id, on)
--   ns.ApplyBar(id)                        idempotent cfg -> runtime
--   ns.ApplyTheme(id)                      theme-only fast path
--   ns.RequestLayout(id)                   coalesced relayout
--   ns.AddBlock(barId, typeKey) -> blockCfg
--   ns.RemoveBlock(barId, blockId)
--   ns.MoveBlock(barId, blockId, delta)    delta = -1 | 1
--   ns.MoveBlockTo(barId, blockId, index)  drag-reorder commit (pre-removal index)
--   ns.BarSizingMode(barCfg) -> "auto" | "even"
--   ns.EnsureFillBlock(barCfg) -> fill block id (healed to last block)
--   ns.SetFillBlock(barId, blockId)
--   ns.SetCenterBlock(barId, blockId | nil)   Force Centered designation
--   ns.NormalizedShare(barCfg, blockId) -> number
--   ns.SolveLayout(barCfg, L, measureFn) -> segments (pure)
--   ns.GetLiveAutoLength(barId, blockId) -> px | nil
--   ns.BuildCurrencyList() -> values, order
--   ns.UpdateAllBarVisibility()
--   ns.MakePreviewBackdrop(host, themeCfg)
--   ns.BLOCK_TYPES / ns.BLOCK_DEFAULTS / ns.EDB_VIS_CAPS / ns.EDGE_PAD

local ADDON_NAME, ns = ...

local WB = EllesmereUI.Lite.NewAddon("EllesmereUIDataBars")
ns.WB = WB

-- Localized-ish string table shared with the blocks file.
local L = {
    LEFT_CLICK           = "|cffFFFFFFLeft Click:|r",
    RIGHT_CLICK          = "|cffFFFFFFRight Click:|r",
    SHIFT_MIDDLE_CLICK   = "|cffFFFFFFShift + Middle Click:|r",
    SHIFT_LEFT_CLICK     = "|cffFFFFFFShift + Left Click:|r",
    CTRL_RIGHT_CLICK     = "|cffFFFFFFCtrl + Right Click:|r",
    YOU_HAVE_MAIL        = "You've Got Mail!",
    SERVER_TIME          = "Server time",
    SAVED_INSTANCES      = "Saved Raid(s)",
    DAILY_RESET          = "Daily reset",
    WEEKLY_RESET         = "Weekly reset",
    TOGGLE_CALENDAR      = "Toggle Calendar",
    TOGGLE_CLOCK         = "Toggle Clock",
    RELOAD_UI            = "Reload UI",
    FPS                  = "FPS",
    HOME                 = "Home",
    WORLD                = "World",
    MEMORY_USAGE         = "Memory Usage",
    REFRESH_STATS        = "Refresh stats / print memory snapshot",
    FORCE_GC             = "Force garbage collection",
    GOLD                 = "Gold",
    SESSION              = "Session",
    EARNED               = "Earned",
    SPENT                = "Spent",
    PROFIT               = "Profit",
    DEFICIT              = "Deficit",
    WARBANK              = "Warbank",
    TOTAL                = "Total",
    WOW_TOKEN            = "WoW Token",
    OPEN_BAGS            = "Open Bags",
    OPEN_CURRENCIES      = "Open Currencies",
    RESET_SESSION        = "Reset Session",
    GOLD_SUFFIX          = "g",
    SILVER_SUFFIX        = "s",
    COPPER_SUFFIX        = "c",
    TRAVEL_COOLDOWNS     = "Travel Cooldowns",
    HEARTHSTONE          = "Hearthstone",
    READY                = "Ready",
    MYTHIC_TELEPORTS     = "Mythic+ Teleports",
    USE_HEARTHSTONE      = "Use Hearthstone",
    CURRENT_SPEC         = "Current Specialization",
    CHANGE_SPEC          = "Change Specialization",
    CHANGE_LOOT_SPEC     = "Change Loot Spec",
    CHANGE_LOADOUT       = "Change Loadout",
    OPEN_PROFESSION      = "Open Profession",
    OPEN_PROFESSION_BOOK = "Open Profession Book",
    START_CAMPFIRE       = "Start a Campfire",
    ACH_POINTS           = "Achievement Points",
    DELVE_JOURNEY        = "Delver's Journey",
    COMPANION_LEVEL      = "Companion Level",
    SELECT_CURRENCY      = "Select a currency",
}
ns.L = L

-- Upvalues
local _G                = _G
local CreateFrame       = CreateFrame
local UIParent          = UIParent
local InCombatLockdown  = InCombatLockdown
local C_Timer           = C_Timer
local pairs, ipairs     = pairs, ipairs
local type, select      = type, select
local pcall             = pcall
local wipe              = wipe
local format            = string.format
local tinsert, tremove  = table.insert, table.remove
local tconcat           = table.concat
local floor             = math.floor
local max, min, abs     = math.max, math.min, math.abs

local PP = EllesmereUI.PP

local MEDIA = "Interface\\AddOns\\EllesmereUIDataBars\\media\\"
ns.MEDIA = MEDIA

-------------------------------------------------------------------------------
--  Defaults (fresh profile shape; the old single-bar keys are abandoned)
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        nextBarId  = 0,   -- monotonic bar id counter; only ever incremented
        bars       = {},  -- ordered array of barCfg
        characters = {},  -- cross-character gold store, keyed "Name-Realm"
    },
}

-------------------------------------------------------------------------------
--  Block type registry
-------------------------------------------------------------------------------
ns.BLOCK_TYPES = {
    { key = "clock",      label = "Clock" },
    { key = "fps",        label = "FPS" },
    { key = "ms",         label = "Latency" },
    { key = "gold",       label = "Gold" },
    { key = "durability", label = "Durability" },
    { key = "xprep",      label = "XP / Reputation Bar" },
    { key = "spec",       label = "Spec & Loot Spec" },
    { key = "profession", label = "Professions" },
    { key = "profession2", label = "Secondary Professions" },
    { key = "travel",     label = "Travel Cooldowns" },
    { key = "micromenu",  label = "Micro Menu" },
    { key = "currency",   label = "Currency" },
    { key = "spacer",     label = "Spacer" },
}

ns.BLOCK_DEFAULTS = {
    clock      = { localTime = true, twentyFour = true, showMail = true, showResting = true, fontSizeClock = nil, fontSizeInfo = nil },
    fps        = {},
    ms         = { useWorldLatency = false },
    gold       = { showIcons = true, showBagSpace = false, showSmall = false },
    durability = { showIcon = true },
    xprep      = { mode = "auto" },
    spec       = { showLoadout = true, useUppercase = false },
    profession = {},
    profession2 = {},
    travel     = { randomizeHs = true },
    micromenu  = { disableBlizzardMicroMenu = false, hideSocialText = false, charStatsTooltip = false, mainMenuSpacing = 4, iconSpacing = 2,
                   menu = true, guild = true, social = true, char = true, spell = true, ach = true, quest = true, lfg = true,
                   pvp = true, housing = true, journal = true, pet = true, shop = true, help = true },
    currency   = { currencyId = nil, showIcon = true },
    spacer     = {},
}

-- Factories are registered by EllesmereUIDataBars_Blocks.lua.
ns.BlockFactories = {}

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do
        if type(v) == "table" then dst[k] = DeepCopy(v) else dst[k] = v end
    end
    return dst
end

-------------------------------------------------------------------------------
--  Profile access
-------------------------------------------------------------------------------
function ns.GetProfile()
    return WB.db and WB.db.profile
end

function ns.BarsInOrder()
    local profile = ns.GetProfile()
    if profile then return profile.bars end
    return {}
end

function ns.GetBar(id)
    local profile = ns.GetProfile()
    if not profile then return nil end
    local bars = profile.bars
    for i = 1, #bars do
        if bars[i].id == id then return bars[i] end
    end
    return nil
end

local function GetBlock(barCfg, blockId)
    if not barCfg then return nil end
    for i = 1, #barCfg.blocks do
        if barCfg.blocks[i].id == blockId then return barCfg.blocks[i], i end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Fonts
-------------------------------------------------------------------------------
function ns.SetFont(fs, size, barCfg)
    if not (fs and fs.SetFont) then return end
    local path  = EllesmereUI.GetFontPath("dataBars")
    local flags = EllesmereUI.GetFontOutlineFlag()
    local scale = 100
    if barCfg and barCfg.fontScale then scale = barCfg.fontScale end
    local sz = max(6, floor((size or 11) * scale / 100 + 0.5))
    -- Runtime SetShadowOffset no longer renders on 12.x; shadows must be
    -- carried by a FontObject. Prime BEFORE SetFont -- the inherited shadow
    -- survives the typeface call.
    if EllesmereUI.PrimeFontShadow then
        local useShadow = flags == "" and EllesmereUI.GetFontUseShadow
            and EllesmereUI.GetFontUseShadow()
        EllesmereUI.PrimeFontShadow(fs, useShadow and true or false)
    end
    fs:SetFont(path, sz, flags)
end

function ns.GetAccent()
    if EllesmereUI.GetAccentColor then
        return EllesmereUI.GetAccentColor()
    end
    local theme = EllesmereUI.ELLESMERE_GREEN
    if theme then return theme.r, theme.g, theme.b end
    return 0.047, 0.824, 0.616
end

-- Colour gradient (bad -> caution -> good)
function ns.SlowColorGradient(perc)
    perc = max(0, min(1, perc))
    local function smoothstep(t) return t * t * (3 - 2 * t) end
    if perc < 0.5 then
        local t = smoothstep(perc * 2)
        return 1, t, 0.08 * (1 - t)
    else
        local t = smoothstep((perc - 0.5) * 2)
        return 1, 1, t
    end
end

-- Snap a measurement to an even whole pixel, min 2 (text height rounding).
function ns.SnapToPixelGrid(v)
    local r = floor((v or 0) + 0.5)
    return max(2, r + (r % 2))
end

-------------------------------------------------------------------------------
--  Money / time formatting (pure)
-------------------------------------------------------------------------------
local DENOMINATIONS = {
    { divisor = 10000, suffix = "GOLD_SUFFIX",   color = "|cffffd700" },
    { divisor = 100,   suffix = "SILVER_SUFFIX", color = "|cffc7c7cf" },
    { divisor = 1,     suffix = "COPPER_SUFFIX", color = "|cffeda55f" },
}

function ns.FormatMoneyPlain(amount, showSmall)
    amount = floor(abs(amount or 0))
    local parts, foundGold = {}, false
    for i, denom in ipairs(DENOMINATIONS) do
        local val = floor(amount / denom.divisor)
        amount = amount % denom.divisor
        if i == 1 and val > 0 then
            foundGold = true
            local display = BreakUpLargeNumbers and BreakUpLargeNumbers(val) or tostring(val)
            parts[#parts + 1] = display .. L[denom.suffix]
        elseif i > 1 and (not foundGold or showSmall ~= false) and (val > 0 or (i == 3 and #parts == 0)) then
            parts[#parts + 1] = val .. L[denom.suffix]
        end
    end
    if #parts > 0 then return tconcat(parts, " ") end
    return "0" .. L["COPPER_SUFFIX"]
end

function ns.FormatMoney(amount, useColors, showSmall)
    amount = floor(abs(amount or 0))
    local coloured = useColors ~= false
    local parts, foundGold = {}, false
    for i, denom in ipairs(DENOMINATIONS) do
        local val = floor(amount / denom.divisor)
        amount = amount % denom.divisor
        if i == 1 and val > 0 then
            foundGold = true
            local display = BreakUpLargeNumbers and BreakUpLargeNumbers(val) or tostring(val)
            local cOpen, cClose = "", ""
            if coloured then cOpen = denom.color; cClose = "|r" end
            parts[#parts + 1] = display .. cOpen .. L[denom.suffix] .. cClose
        elseif i > 1 and (not foundGold or showSmall ~= false) and (val > 0 or (i == 3 and #parts == 0)) then
            local cOpen, cClose = "", ""
            if coloured then cOpen = denom.color; cClose = "|r" end
            parts[#parts + 1] = val .. cOpen .. L[denom.suffix] .. cClose
        end
    end
    if #parts == 0 then
        local cOpen, cClose = "", ""
        if coloured then cOpen = DENOMINATIONS[3].color; cClose = "|r" end
        return "0" .. cOpen .. L["COPPER_SUFFIX"] .. cClose
    end
    return tconcat(parts, " ")
end

local TIME_UNITS = { { 86400, "d" }, { 3600, "h" }, { 60, "min" } }
function ns.FormatTimeLeft(seconds)
    seconds = floor(seconds or 0)
    local parts = {}
    for _, unit in ipairs(TIME_UNITS) do
        local val = floor(seconds / unit[1])
        seconds = seconds % unit[1]
        if val > 0 then parts[#parts + 1] = val .. unit[2] end
    end
    if #parts > 0 then return tconcat(parts, " ") end
    return "0min"
end

function ns.FormatCooldown(cd)
    if cd <= 0 then return nil end
    cd = floor(cd)
    if cd >= 3600 then
        return format("%d:%02d:%02d", floor(cd / 3600), floor(cd % 3600 / 60), cd % 60)
    end
    return format("%d:%02d", floor(cd / 60), cd % 60)
end

function ns.GetFPSSuffix() local s = FPS_ABBR; if s then return s end return " fps" end
function ns.GetMSSuffix()  local s = MILLISECONDS_ABBR; if s then return s end return " ms" end

-------------------------------------------------------------------------------
--  Combat deferral (last caller per key wins; runs on regen)
-------------------------------------------------------------------------------
do
    local deferFrames = {}
    function ns.DeferUntilOOC(key, fn)
        if not InCombatLockdown() then fn(); return end
        local f = deferFrames[key]
        if not f then
            f = CreateFrame("Frame")
            deferFrames[key] = f
        end
        f._fn = fn
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if self._fn then self._fn(); self._fn = nil end
        end)
    end
end

-------------------------------------------------------------------------------
--  Shared 1-second heartbeat. Ticker exists only while listeners exist.
--  Keys are instance-scoped ("clock:EDB3_2") so two blocks never collide.
-------------------------------------------------------------------------------
do
    local listeners = {}
    local ticker
    function ns.RegisterHeartbeat(key, fn)
        listeners[key] = fn
        if not ticker then
            ticker = C_Timer.NewTicker(1, function()
                -- Isolate listeners: one erroring block must not starve the rest.
                for _, callback in pairs(listeners) do
                    local ok, err = pcall(callback)
                    if not ok then geterrorhandler()(err) end
                end
            end)
        end
    end
    function ns.UnregisterHeartbeat(key)
        listeners[key] = nil
        if ticker and next(listeners) == nil then
            ticker:Cancel()
            ticker = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Frame pool (popup rows). Per-instance pools are built with this too.
-------------------------------------------------------------------------------
function ns.CreateFramePool(frameType, parent, template)
    local pool = { _type = frameType, _parent = parent, _template = template }
    pool._active = {}
    pool._inactive = {}

    function pool:Acquire()
        local f = tremove(self._inactive)
        if not f then
            f = CreateFrame(self._type, nil, self._parent, self._template)
        end
        f:SetParent(self._parent)
        f:Show()
        self._active[#self._active + 1] = f
        return f
    end

    local function ResetPooledFrame(f)
        if not f then return end
        f:Hide()
        f:ClearAllPoints()
        f:SetParent(pool._parent)
        f:SetAlpha(1)
        f:SetScale(1)
        f:SetWidth(1)
        f:SetHeight(1)
        f:EnableMouse(false)
        f:RegisterForClicks()
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:SetScript("OnClick", nil)
        f:SetScript("OnMouseDown", nil)
        f:SetScript("OnMouseUp", nil)
        f:SetScript("OnUpdate", nil)
        f:SetScript("OnShow", nil)
        f:SetScript("OnHide", nil)
        if f.GetNormalTexture and f:GetNormalTexture() and f:GetNormalTexture().SetTexture then f:GetNormalTexture():SetTexture(nil) end
        if f.GetPushedTexture and f:GetPushedTexture() and f:GetPushedTexture().SetTexture then f:GetPushedTexture():SetTexture(nil) end
        if f.GetHighlightTexture and f:GetHighlightTexture() and f:GetHighlightTexture().SetTexture then f:GetHighlightTexture():SetTexture(nil) end
        if f.GetDisabledTexture and f:GetDisabledTexture() and f:GetDisabledTexture().SetTexture then f:GetDisabledTexture():SetTexture(nil) end
        if f.GetCheckedTexture and f:GetCheckedTexture() and f:GetCheckedTexture().SetTexture then f:GetCheckedTexture():SetTexture(nil) end
        if f.SetButtonState then f:SetButtonState("NORMAL") end
        if f.SetChecked then f:SetChecked(false) end
        if f.SetText then f:SetText("") end
        if f.SetAttribute then
            pcall(f.SetAttribute, f, "type", nil)
            pcall(f.SetAttribute, f, "macrotext", nil)
            pcall(f.SetAttribute, f, "clickbutton", nil)
        end
        if f.GetNumRegions then
            -- select() avoids allocating a throwaway table per released frame.
            for i = 1, f:GetNumRegions() do
                local r = select(i, f:GetRegions())
                if r and r.Hide then r:Hide() end
                if r and r.SetAlpha then r:SetAlpha(1) end
                if r and r.ClearAllPoints then r:ClearAllPoints() end
                if r and r.SetText then r:SetText("") end
                if r and r.SetTexture then r:SetTexture(nil) end
                if r and r.SetVertexColor then r:SetVertexColor(1, 1, 1, 1) end
                if r and r.SetTexCoord then r:SetTexCoord(0, 1, 0, 1) end
            end
        end
    end

    function pool:ReleaseAll()
        for i = #self._active, 1, -1 do
            local f = tremove(self._active, i)
            ResetPooledFrame(f)
            self._inactive[#self._inactive + 1] = f
        end
    end

    function pool:GetActive() return self._active end

    return pool
end

-------------------------------------------------------------------------------
--  Popup helper: single shared click-catcher closes whichever popup is open.
--  True singleton by design (only one popup open app-wide at a time).
-------------------------------------------------------------------------------
do
    local sharedClickCatcher
    local activePopup

    local function GetClickCatcher()
        if not sharedClickCatcher then
            sharedClickCatcher = CreateFrame("Button", nil, UIParent)
            sharedClickCatcher:SetAllPoints(UIParent)
            sharedClickCatcher:SetFrameStrata("DIALOG")
            sharedClickCatcher:SetFrameLevel(100)
            sharedClickCatcher:Hide()
            sharedClickCatcher:EnableMouse(true)
            sharedClickCatcher:RegisterForClicks("AnyDown", "AnyUp")
            sharedClickCatcher:SetScript("OnClick", function()
                if activePopup and activePopup:IsShown() then activePopup:Hide() end
            end)
        end
        return sharedClickCatcher
    end

    function ns.CreatePopupFrame(parent)
        -- House tooltip styling (same recipe as ns.Tip_*'s EnsureTip), NOT
        -- Blizzard's TooltipBackdropTemplate -- the popups must look like
        -- every other EllesmereUI tooltip.
        local popup = CreateFrame("Frame", nil, UIParent)
        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if PP and PP.CreateBorder then
            PP.CreateBorder(popup, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        popup:SetFrameStrata("TOOLTIP")
        popup:SetClampedToScreen(true)
        popup:Hide()
        popup:EnableKeyboard(false)
        popup:SetToplevel(true)

        local cc = GetClickCatcher()
        popup._wbClickCatcher = cc
        popup:SetFrameLevel(cc:GetFrameLevel() + 10)
        popup:SetScript("OnShow", function(self)
            activePopup = self
            local catcher = self._wbClickCatcher
            -- Hover-driven popups dismiss on mouse-leave instead; arming the
            -- full-screen catcher for them would eat unrelated clicks.
            if catcher and not self._wbNoCatcher then
                catcher:ClearAllPoints()
                catcher:SetAllPoints(UIParent)
                catcher:Show()
                catcher:SetFrameStrata(self:GetFrameStrata())
                catcher:SetFrameLevel(max(1, self:GetFrameLevel() - 1))
            end
        end)
        popup:SetScript("OnHide", function(self)
            if activePopup == self then activePopup = nil end
            local catcher = self._wbClickCatcher
            if catcher and (not activePopup or not activePopup:IsShown()) then catcher:Hide() end
            if self._wbOnHide then self:_wbOnHide() end
        end)
        return popup
    end
end

-------------------------------------------------------------------------------
--  Text fitting helpers + fit cache
-------------------------------------------------------------------------------
function ns.SetWrappedText(fs, width, justify)
    if not fs then return end
    fs:SetWidth(max(1, width or 1))
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
    if fs.SetJustifyH then fs:SetJustifyH(justify or "CENTER") end
end

function ns.ResetInlineText(fs, justify)
    if not fs then return end
    fs:SetWidth(0)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    if fs.SetJustifyH then fs:SetJustifyH(justify or "LEFT") end
end

local _fitCache, _fitCacheCount = {}, 0
local _measureFS
local _fitKeyParts = {}

function ns.MeasureFS()
    if not _measureFS and UIParent then
        _measureFS = UIParent:CreateFontString(nil, "OVERLAY")
    end
    return _measureFS
end

-- FitFontToLines: largest font size in [minSize..startSize] at which every
-- line fits within maxWidth. Cache key includes the bar's font scale so two
-- bars at different scales never share entries.
function ns.FitFontToLines(lines, startSize, minSize, maxWidth, barCfg)
    local fs = ns.MeasureFS()
    if not fs then return startSize end
    local width = max(1, maxWidth or 1)
    local start = startSize or 14
    local floorSize = minSize or max(8, start - 6)
    local scale = 100
    if barCfg and barCfg.fontScale then scale = barCfg.fontScale end

    wipe(_fitKeyParts)
    _fitKeyParts[1] = start; _fitKeyParts[2] = floorSize; _fitKeyParts[3] = width; _fitKeyParts[4] = scale
    for i, line in ipairs(lines or {}) do _fitKeyParts[i + 4] = line or "" end
    local cacheKey = tconcat(_fitKeyParts, "\1")
    local cached = _fitCache[cacheKey]
    if cached then return cached end

    for size = start, floorSize, -1 do
        ns.SetFont(fs, size, barCfg)
        local widest = 0
        for _, line in ipairs(lines or {}) do
            fs:SetText(line or "")
            local w = fs:GetStringWidth() or 0
            if w > widest then widest = w end
        end
        if widest <= width then
            if _fitCacheCount > 200 then _fitCache = {}; _fitCacheCount = 0 end
            _fitCache[cacheKey] = size
            _fitCacheCount = _fitCacheCount + 1
            return size
        end
    end
    if _fitCacheCount > 200 then _fitCache = {}; _fitCacheCount = 0 end
    _fitCache[cacheKey] = floorSize
    _fitCacheCount = _fitCacheCount + 1
    return floorSize
end

function ns.WipeFitCache()
    _fitCache = {}
    _fitCacheCount = 0
end

-------------------------------------------------------------------------------
--  Owned rich tooltip (single frame, pooled FontStrings, two columns)
--  Replaces every GameTooltip site in the old module code.
-------------------------------------------------------------------------------
do
    local tip
    local owner
    local rows = {}       -- rows[i] = { left = fs, right = fs }
    local data = {}       -- data[i] = { l, r, lr, lg, lb, rr, rg, rb }
    local dataCount = 0
    local PAD = 10
    local ROW_GAP = 3
    local COL_GAP = 18
    local FONT_SIZE = 12

    -- Interactive rows: a pool of secure spell buttons overlaid on rows that
    -- declared an action (Tip_AddActionDouble). Casting mechanism matches the
    -- QoL teleport prompt: SecureActionButtonTemplate, type="spell" fed a
    -- STATIC INTEGER spellID, attributes written out of combat only (the
    -- overlay build is combat-skipped). The buttons live on a secure host
    -- under UIParent whose visibility state driver yanks them the moment
    -- lockdown starts (covers a tip left open across a pull); the tip itself
    -- keeps no protected children, so Tip_Hide stays combat-legal. A
    -- keep-alive poll lets the cursor travel off the owner onto the tip to
    -- click a row without the tip closing under it.
    local actionPool = {}
    local activeActions = 0
    local actionHost           -- secure container, built with the first button
    local actionsDirty = false -- a teardown landed in combat; regen finishes it
    local interactive = false
    local keepAlive

    local function EnsureTip()
        if tip then return tip end
        tip = CreateFrame("Frame", "EllesmereUIDataBarsTip", UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        tip:Hide()
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if PP and PP.CreateBorder then
            PP.CreateBorder(tip, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        return tip
    end

    local function EnsureRow(i)
        local row = rows[i]
        if not row then
            row = {}
            row.left = tip:CreateFontString(nil, "OVERLAY")
            row.right = tip:CreateFontString(nil, "OVERLAY")
            rows[i] = row
        end
        return row
    end

    -- Hide/detach every overlay button. The buttons are PROTECTED
    -- (SecureActionButtonTemplate), so touching them is OOC-only: a teardown
    -- that lands mid-combat sets the dirty flag and the host's regen handler
    -- finishes it (the state driver has already pulled the host off screen at
    -- lockdown start, so nothing stays clickable meanwhile).
    local function HideActionButtons()
        if activeActions == 0 and not actionsDirty then return end
        if InCombatLockdown() then actionsDirty = true; return end
        actionsDirty = false
        for i = 1, #actionPool do
            local b = actionPool[i]
            b:Hide()
            b:ClearAllPoints()
            b:SetScript("OnEnter", nil)
            b:SetScript("OnLeave", nil)
        end
        activeActions = 0
    end

    local function EnsureActionHost()
        if actionHost then return actionHost end
        actionHost = CreateFrame("Frame", "EllesmereUIDataBarsTipActions", UIParent, "SecureHandlerStateTemplate")
        actionHost:SetFrameStrata("TOOLTIP")
        actionHost:SetFrameLevel(250)
        actionHost:SetAllPoints(tip)
        -- No clickable overlays in combat, ever: the driver hides the host
        -- securely the instant lockdown starts and re-shows it on regen for
        -- the next out-of-combat tip.
        RegisterStateDriver(actionHost, "visibility", "[combat] hide; show")
        local regen = CreateFrame("Frame")
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
        regen:RegisterEvent("PLAYER_REGEN_DISABLED")
        regen:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                if actionsDirty then HideActionButtons() end
                return
            end
            -- PLAYER_REGEN_DISABLED: InCombatLockdown() already reports true
            -- here, but protected-frame writes are still legal until the
            -- handler returns -- the last window to act. A PROTECTED frame
            -- (host or button) left anchored to the tip turns tip:SetSize()
            -- into a blocked call for the whole fight, so hovering ANY plain
            -- tooltip (clock etc.) fires ADDON_ACTION_BLOCKED. Sever every
            -- protected anchor on the tip now; the next out-of-combat
            -- Tip_Show re-attaches the host.
            actionsDirty = false
            for i = 1, #actionPool do
                local b = actionPool[i]
                b:Hide()
                b:ClearAllPoints()
                b:SetScript("OnEnter", nil)
                b:SetScript("OnLeave", nil)
            end
            activeActions = 0
            actionHost:ClearAllPoints()
        end)
        return actionHost
    end

    -- Grow-only pool; buttons are configured fresh on every Tip_Show. Creation
    -- and reconfiguration only ever run out of combat (the overlay build is
    -- combat-skipped), so the secure attribute writes are always legal.
    local function AcquireActionButton()
        activeActions = activeActions + 1
        local b = actionPool[activeActions]
        if not b then
            b = CreateFrame("Button", nil, EnsureActionHost(), "SecureActionButtonTemplate")
            b:SetFrameLevel(250)
            b:EnableMouse(true)
            -- AnyUp only + useOnKeyDown=false: registering both click phases
            -- lets the ActionButtonUseKeyDown CVar fire the cast twice, and
            -- the second press cancels the teleport cast the first one
            -- started -- same rule as the travel block's hearth button.
            b:RegisterForClicks("AnyUp")
            b:SetAttribute("useOnKeyDown", false)
            b:SetAttribute("type", "spell")
            -- Static handler, installed once; pooled reuse only swaps the
            -- spell attribute and the hover recolor scripts.
            b:HookScript("PostClick", function() ns.Tip_Hide() end)
            actionPool[activeActions] = b
        end
        return b
    end

    local function StopKeepAlive()
        if keepAlive then keepAlive:Cancel(); keepAlive = nil end
    end

    -- Dismiss the interactive tip once the cursor is over neither the owner nor
    -- the tip. IsMouseOver tests rectangles (ignores the overlay buttons on
    -- top), so hovering a clickable row still counts as "over the tip". Both
    -- rects are tested EXPANDED: the tip anchors with a 6px gap off the bar
    -- (plus the block's inset from the bar edge), and an unexpanded test hides
    -- the tip the instant a tick lands while the cursor is crossing that dead
    -- zone -- the expansions overlap across the gap so the crossing always
    -- counts as "over". The two-tick grace covers slow diagonal exits past a
    -- corner without making a real leave feel sticky (~0.2s).
    local KA_SLACK = 12
    local function StartKeepAlive()
        if keepAlive then return end
        local missed = 0
        keepAlive = C_Timer.NewTicker(0.1, function()
            if not (tip and tip:IsShown()) then StopKeepAlive(); return end
            local overOwner = owner and owner.IsMouseOver
                and owner:IsMouseOver(KA_SLACK, -KA_SLACK, -KA_SLACK, KA_SLACK)
            local overTip = tip:IsMouseOver(KA_SLACK, -KA_SLACK, -KA_SLACK, KA_SLACK)
            if overOwner or overTip then
                missed = 0
            else
                missed = missed + 1
                if missed >= 2 then ns.Tip_Hide() end
            end
        end)
    end

    function ns.Tip_Begin(ownerFrame)
        EnsureTip()
        owner = ownerFrame
        dataCount = 0
    end

    -- Secret text must never enter a row: SetText would display it, but
    -- Tip_Show sizes the tooltip from GetStringWidth, which returns a SECRET
    -- number for secret-fed FontStrings, and the max-width compare errors.
    -- Rows carrying a secret are dropped at this single chokepoint, so the
    -- tooltip shortens in restricted content instead of erroring. Add
    -- functions return true when the row was actually added.
    function ns.Tip_AddLine(text, r, g, b)
        if not tip then return end
        if text ~= nil and issecretvalue(text) then return end
        dataCount = dataCount + 1
        local d = data[dataCount]
        if not d then d = {}; data[dataCount] = d end
        d.l = text or " "
        d.lr = r; d.lg = g; d.lb = b
        d.r = nil
        d.wrap = nil
        d.action = nil
        return true
    end

    -- Long prose (currency descriptions etc.): word-wraps at maxWidth px
    -- instead of blowing the tooltip out to the widest single line.
    function ns.Tip_AddWrappedLine(text, maxWidth, r, g, b)
        if not tip then return end
        if ns.Tip_AddLine(text, r, g, b) then
            data[dataCount].wrap = maxWidth or 280
        end
    end

    function ns.Tip_AddDouble(left, right, lr, lg, lb, rr, rg, rb)
        if not tip then return end
        if (left ~= nil and issecretvalue(left))
        or (right ~= nil and issecretvalue(right)) then return end
        dataCount = dataCount + 1
        local d = data[dataCount]
        if not d then d = {}; data[dataCount] = d end
        d.l = left or " "
        d.lr = lr; d.lg = lg; d.lb = lb
        d.r = right or ""
        d.rr = rr; d.rg = rg; d.rb = rb
        d.wrap = nil
        d.action = nil
        return true
    end

    -- Click-to-cast row: identical to Tip_AddDouble, but Tip_Show overlays a
    -- secure spell button over it and keeps the tip alive while hovered.
    -- spellID MUST be a static integer spell ID (never an API-derived name or
    -- secret-capable value -- same contract as the QoL teleport prompt).
    -- Degrades to a plain double line in combat.
    function ns.Tip_AddActionDouble(left, right, spellID, lr, lg, lb, rr, rg, rb)
        if ns.Tip_AddDouble(left, right, lr, lg, lb, rr, rg, rb) and spellID then
            data[dataCount].action = spellID
        end
    end

    function ns.Tip_Show()
        if not tip or not owner then return end
        local maxLeft, maxRight, totalH = 0, 0, 0
        local anyRight = false
        for i = 1, dataCount do
            local d = data[i]
            local row = EnsureRow(i)
            ns.SetFont(row.left, FONT_SIZE)
            -- The right FS needs a font even on left-only rows: SetText("")
            -- on a never-fonted FontString is a hard error, and a pooled
            -- row's FIRST use can be a plain line.
            ns.SetFont(row.right, FONT_SIZE)
            -- Rows are pooled: reset wrap state every pass so a wrapped row
            -- reused as a plain one measures naturally again.
            if d.wrap then
                row.left:SetWordWrap(true)
                row.left:SetWidth(d.wrap)
            else
                row.left:SetWordWrap(false)
                row.left:SetWidth(0)
            end
            row.left:SetText(d.l)
            row.left:SetTextColor(d.lr or 1, d.lg or 1, d.lb or 1, 1)
            row.left:Show()
            local lw = row.left:GetStringWidth() or 0
            if d.wrap and lw > d.wrap then lw = d.wrap end
            if lw > maxLeft then maxLeft = lw end
            if d.r then
                anyRight = true
                row.right:SetText(d.r)
                row.right:SetTextColor(d.rr or 1, d.rg or 1, d.rb or 1, 1)
                row.right:Show()
                local rw = row.right:GetStringWidth() or 0
                if rw > maxRight then maxRight = rw end
            else
                row.right:SetText("")
                row.right:Hide()
            end
            local h = row.left:GetStringHeight() or FONT_SIZE
            if d.r then
                local rh = row.right:GetStringHeight() or 0
                if rh > h then h = rh end
            end
            totalH = totalH + h + (i > 1 and ROW_GAP or 0)
            d._h = h
        end
        for i = dataCount + 1, #rows do
            rows[i].left:Hide()
            rows[i].right:Hide()
        end

        local innerW = maxLeft
        if anyRight then innerW = maxLeft + COL_GAP + maxRight end
        local w = innerW + PAD * 2
        local h = totalH + PAD * 2
        tip:SetSize(max(60, w), max(24, h))

        local y = -PAD
        for i = 1, dataCount do
            local d = data[i]
            local row = rows[i]
            row.left:ClearAllPoints()
            row.left:SetPoint("TOPLEFT", tip, "TOPLEFT", PAD, y)
            if d.r then
                row.right:ClearAllPoints()
                row.right:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -PAD, y)
            end
            d._y = y
            y = y - d._h - ROW_GAP
        end

        -- Interactive overlay: one secure spell button per row that declared an
        -- action, spanning the full row rect. Skipped in combat -- rows degrade
        -- to plain text and no protected-frame touches fire. Rebuilt from
        -- scratch each show (HideActionButtons first) so a reused tip never
        -- carries stale buttons.
        HideActionButtons()
        interactive = false
        if not InCombatLockdown() then
            local ar, ag, ab = ns.GetAccent()
            for i = 1, dataCount do
                local d = data[i]
                if d.action then
                    interactive = true
                    -- Re-attach the host: the REGEN_DISABLED handler detaches
                    -- it (and the buttons) from the tip at every combat start.
                    if activeActions == 0 then
                        local host = EnsureActionHost()
                        host:ClearAllPoints()
                        host:SetAllPoints(tip)
                    end
                    local b = AcquireActionButton()
                    b:SetAttribute("spell", d.action)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", tip, "TOPLEFT", PAD, d._y)
                    b:SetSize(max(1, innerW), max(1, d._h))
                    local row = rows[i]
                    local lr, lg, lb = d.lr or 1, d.lg or 1, d.lb or 1
                    b:SetScript("OnEnter", function() row.left:SetTextColor(ar, ag, ab, 1) end)
                    b:SetScript("OnLeave", function() row.left:SetTextColor(lr, lg, lb, 1) end)
                    b:Show()
                end
            end
        end
        tip:EnableMouse(interactive)
        if interactive then StartKeepAlive() else StopKeepAlive() end

        -- Smart anchoring: the tooltip opens off the BAR's roomier side --
        -- above/below for horizontal bars, left/right for vertical bars --
        -- with a 6px gap from the bar edge so it can never overlap the bar,
        -- centered on the hovered block along the bar's axis and clamped to
        -- the screen. Screen-px normalization: block content can be scaled
        -- (per-block Content Scale), so owner coords are converted through
        -- effective scale before comparing with the bar's.
        tip:ClearAllPoints()
        local bar = owner:GetParent()
        while bar do
            local n = bar.GetName and bar:GetName()
            if n and n:find("^EllesmereUIDataBarsBar%d+$") then break end
            bar = bar:GetParent()
        end
        local ocx, ocy = owner:GetCenter()
        if bar and ocx then
            local os = owner:GetEffectiveScale()
            local ts = tip:GetEffectiveScale()
            local bcx, bcy = bar:GetCenter()
            local bs = bar:GetEffectiveScale()
            local uiScale = UIParent:GetEffectiveScale()
            local halfW = UIParent:GetWidth() * uiScale / 2
            local halfH = UIParent:GetHeight() * uiScale / 2
            if bar:GetHeight() > bar:GetWidth() then
                -- Vertical bar: open toward the roomier horizontal side.
                local oy = (ocy * os - bcy * bs) / ts
                if bcx * bs < halfW then
                    tip:SetPoint("LEFT", bar, "RIGHT", 6, oy)
                else
                    tip:SetPoint("RIGHT", bar, "LEFT", -6, oy)
                end
            else
                local ox = (ocx * os - bcx * bs) / ts
                if bcy * bs < halfH then
                    tip:SetPoint("BOTTOM", bar, "TOP", ox, 6)
                else
                    tip:SetPoint("TOP", bar, "BOTTOM", ox, -6)
                end
            end
        else
            -- Owner not inside a live bar: fall back to above/below by the
            -- owner's own screen half.
            local half = UIParent:GetHeight() / 2
            if ocy and ocy < half then
                tip:SetPoint("BOTTOM", owner, "TOP", 0, 6)
            else
                tip:SetPoint("TOP", owner, "BOTTOM", 0, -6)
            end
        end
        tip:Show()
    end

    function ns.Tip_Hide(ownerFrame)
        if not tip then return end
        if ownerFrame and owner ~= ownerFrame then return end
        owner = nil
        HideActionButtons()
        StopKeepAlive()
        interactive = false
        tip:EnableMouse(false)
        tip:Hide()
    end

    -- Owner OnLeave hook: an interactive tip is dismissed by its own keep-alive
    -- poll (so the cursor can move onto the tip to click a row), a plain tip
    -- hides immediately -- exactly the old behavior for every non-interactive
    -- block.
    function ns.Tip_HideUnlessInteractive(ownerFrame)
        if not tip then return end
        if ownerFrame and owner ~= ownerFrame then return end
        if interactive then return end
        ns.Tip_Hide(ownerFrame)
    end

    function ns.Tip_IsOwned(ownerFrame)
        if not tip then return false end
        return tip:IsShown() and owner == ownerFrame
    end
end

-------------------------------------------------------------------------------
--  Layout solver (pure)
--
--  Semantics: the bar is ALWAYS exactly filled -- segments sum to the usable
--  length L on every solve, live bar and preview alike. Sizing is a
--  PER-BAR mode (cfg.sizingMode, ns.BarSizingMode):
--    "even"  every block gets an equal share of L. No per-block options.
--    "auto"  every block is content-sized: measured extent + per-side gaps
--            (contentGapL/contentGapR, legacy contentGap fallback, then
--            10). Spacers have no content, so their width IS their two
--            gaps. Exactly ONE block per bar (cfg.fillBlockId, healed to
--            the LAST block) is the Fill Remaining block: it absorbs the
--            slack, so the bar exactly fills; over-full bars scale the
--            sized blocks down (fill gets 0).
--  Vertical bars run the identical solver with L = bar height.
-------------------------------------------------------------------------------
-- Inset between the bar's ends and the outermost blocks. ZERO: blocks run
-- flush edge to edge (a nonzero pad leaves the bar background visibly
-- extending past the first/last block -- user-reported as a defect). Kept
-- as the single tunable ALL layout math derives from.
local EDGE_PAD = 0
ns.EDGE_PAD = EDGE_PAD

-- Per-BAR sizing mode; absent = "auto".
function ns.BarSizingMode(barCfg)
    if barCfg and barCfg.sizingMode == "even" then return "even" end
    return "auto"
end

-- The auto-mode Fill Remaining block id, healed to the LAST block whenever
-- the stored id is missing or no longer in the bar (removed block, fresh
-- bar). Returns nil only for empty bars.
function ns.EnsureFillBlock(barCfg)
    local blocks = barCfg and barCfg.blocks
    local n = blocks and #blocks or 0
    if n == 0 then return nil end
    local id = barCfg.fillBlockId
    if id ~= nil then
        for i = 1, n do
            if blocks[i].id == id then return id end
        end
    end
    id = blocks[n].id
    barCfg.fillBlockId = id
    return id
end

-- Per-side Auto Sized gaps (leading = left/top, trailing = right/bottom).
-- View over the keys: contentGapL/contentGapR each fall back to the legacy
-- single contentGap (then 10), so old data keeps its symmetric gap.
local function ContentGapsOf(b)
    local base = b.contentGap
    if base == nil then base = 10 end
    local l = b.contentGapL
    if l == nil then l = base end
    local r = b.contentGapR
    if r == nil then r = base end
    return l, r
end
ns.ContentGapsOf = ContentGapsOf

-- L = usable content length (px). measure(b) returns the block's live
-- content extent along the bar axis (consulted in auto mode only).
-- Every segment carries seg.at (start offset from the bar start) as well
-- as seg.px: segments normally chain seamlessly, but a Force Centered
-- block leaves uncovered bar background beside it, so consumers must
-- position from seg.at, never from a running cursor.
function ns.SolveLayout(barCfg, L, measure)
    local segs = {}
    local n = #barCfg.blocks
    if n == 0 then return segs end

    if ns.BarSizingMode(barCfg) == "even" then
        -- Equal shares; cumulative rounding telescopes to EXACTLY L.
        local prevEdge = 0
        for i = 1, n do
            local edge = floor(i * L / n + 0.5)
            segs[i] = { block = barCfg.blocks[i], at = prevEdge, px = edge - prevEdge }
            prevEdge = edge
        end
        return segs
    end

    -- AUTO: content + per-side gaps everywhere; the single fill block
    -- absorbs the remainder. An optional Force Centered block
    -- (cfg.centerBlockId) pins its CONTENT at exactly L/2 and splits the
    -- solve: blocks before it pack toward the LEFT edge, blocks after it
    -- pack toward the RIGHT edge. When the centered block is ALSO the
    -- fill block, its slot absorbs the entire middle span (bar exactly
    -- fills; content stays pinned via seg.contentShift). Otherwise a
    -- region containing the fill spans edge-to-edge and any leftover
    -- beside the center is plain bar background.
    local fillId = ns.EnsureFillBlock(barCfg)
    local centerIdx
    do
        local cid = barCfg.centerBlockId
        if cid ~= nil then
            for i = 1, n do
                if barCfg.blocks[i].id == cid then centerIdx = i break end
            end
        end
    end

    -- desired slot px for a sized (non-fill) block; also its leading gap
    -- and bare content width (for exact content-centering).
    local function SizedPx(b)
        local w = 0
        if b.type ~= "spacer" and measure then w = measure(b) or 0 end
        if w < 0 then w = 0 end
        local gl, gr = ContentGapsOf(b)
        return w + gl + gr, gl, w
    end

    for i = 1, n do
        local b = barCfg.blocks[i]
        local seg = { block = b, at = 0, px = 0 }
        if b.id == fillId then
            seg.isFill = true
        else
            seg.desired = SizedPx(b)
        end
        segs[i] = seg
    end

    -- Lays a contiguous run of segments into [regionStart, regionEnd]:
    -- packs left (or right), with cumulative edge rounding so the run
    -- telescopes; a fill segment in the run absorbs the slack so the run
    -- spans the whole region. Both region bounds may be fractional; the
    -- pinned edge always rounds onto the region bound.
    local function SolveRegion(first, last, regionStart, regionEnd, packRight)
        if first > last then return end
        local regionLen = regionEnd - regionStart
        if regionLen < 0 then regionLen = 0 end
        local sumFixed, hasFill = 0, false
        for i = first, last do
            if segs[i].isFill then hasFill = true
            else sumFixed = sumFixed + segs[i].desired end
        end
        local scale, fillPx = 1, 0
        if sumFixed > regionLen then
            if sumFixed > 0 then scale = regionLen / sumFixed end
        elseif hasFill then
            fillPx = regionLen - sumFixed
        end
        if packRight and not hasFill then
            -- Anchor flush to the region's RIGHT edge: cumulate from the
            -- right so the last block's edge lands exactly on regionEnd.
            local cum, prevEdge = 0, 0
            local rEnd = floor(regionEnd + 0.5)
            for i = last, first, -1 do
                cum = cum + segs[i].desired * scale
                local edge = floor(cum + 0.5)
                segs[i].px = edge - prevEdge
                segs[i].at = rEnd - edge
                prevEdge = edge
            end
            return
        end
        local base = floor(regionStart + 0.5)
        local cum, prevEdge = 0, 0
        for i = first, last do
            local s = segs[i]
            local w
            if s.isFill then w = fillPx else w = s.desired * scale end
            cum = cum + w
            local edge = floor(cum + 0.5)
            if hasFill and i == last then
                -- Pin the run's far edge exactly onto the region bound.
                edge = floor(regionEnd + 0.5) - base
            end
            s.px = edge - prevEdge
            s.at = base + prevEdge
            prevEdge = edge
        end
    end

    if not centerIdx then
        SolveRegion(1, n, 0, L, false)
        return segs
    end

    -- Center geometry: the MINIMUM slot spans content + gaps, positioned
    -- so the bare CONTENT midpoint sits at exactly L/2 (gap-aware,
    -- matching the AnchorContent gap stepping).
    local cB = barCfg.blocks[centerIdx]
    local cIsFill = cB.id == fillId
    local cDesired, cGl, cW = SizedPx(cB)
    local cPx = floor(cDesired + 0.5)
    local cAt = floor(L / 2 - cW / 2 - cGl + 0.5)
    if cAt < 0 then cAt = 0 end
    if cAt + cPx > L then cAt = floor(max(0, L - cPx) + 0.5) end
    local cSeg = segs[centerIdx]
    cSeg.desired = nil

    SolveRegion(1, centerIdx - 1, 0, cAt, false)
    SolveRegion(centerIdx + 1, n, cAt + cPx, L, true)

    if cIsFill then
        -- Centered fill: the slot stretches over the whole middle span
        -- (sides packed to the edges, nothing left uncovered); the slot
        -- is generally asymmetric around L/2, so the content pins to the
        -- true center via seg.contentShift (consumed by AnchorContent).
        local leftEnd = 0
        if centerIdx > 1 then
            local ls = segs[centerIdx - 1]
            leftEnd = ls.at + ls.px
        end
        local rightStart = floor(L + 0.5)
        if centerIdx < n then
            rightStart = segs[centerIdx + 1].at
        end
        cSeg.isFill = true
        cSeg.at = leftEnd
        cSeg.px = max(0, rightStart - leftEnd)
        cSeg.contentShift = (L / 2) - (cSeg.at + cSeg.px / 2)
    else
        cSeg.at = cAt
        cSeg.px = cPx
    end
    return segs
end

-------------------------------------------------------------------------------
--  Theme rendering (self-contained window-skin recipe; no BlizzardSkin dep)
--  Three pre-built textures per host, swapped by alpha only:
--    bgAtlas   modern_blizz.png cover-fit          (eui style)
--    bgOverlay black overlay, alpha = theme.euiAlpha (eui style)
--    modernBg  flat user color                      (modern style)
-------------------------------------------------------------------------------
local BG_ASPECT = 561 / 433
local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T

local function EnsureThemeTextures(host)
    if host._edbBgAtlas then return end
    local bgAtlas = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgAtlas:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bgAtlas:SetAllPoints(host)
    local bgOverlay = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgOverlay:SetColorTexture(0, 0, 0, 0.5)
    bgOverlay:SetAllPoints(host)
    local modernBg = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    modernBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
    modernBg:SetAllPoints(host)
    host._edbBgAtlas   = bgAtlas
    host._edbBgOverlay = bgOverlay
    host._edbModernBg  = modernBg

    -- Cover-fit: crop the atlas so it fills the host without stretching.
    local function UpdateBgTexCoords()
        local fw, fh = host:GetSize()
        if not fw or fw == 0 or not fh or fh == 0 then return end
        local fa = fw / fh
        if fa > BG_ASPECT then
            local visV = BASE_V * (BG_ASPECT / fa)
            local trimV = (BASE_V - visV) / 2
            bgAtlas:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            local visU = BASE_U * (fa / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            bgAtlas:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    host:HookScript("OnSizeChanged", UpdateBgTexCoords)
    UpdateBgTexCoords()
end

local function ApplyThemeToHost(host, theme)
    EnsureThemeTextures(host)
    theme = theme or {}
    local op
    if theme.style == "modern" then
        host._edbBgAtlas:SetAlpha(0)
        host._edbBgOverlay:SetAlpha(0)
        local c = theme.modernColor or {}
        host._edbModernBg:SetColorTexture(c.r or 0.067, c.g or 0.067, c.b or 0.067, c.a or 0.95)
        host._edbModernBg:SetAlpha(1)
        op = c.a
        if op == nil then op = 0.95 end
    else
        -- euiOpacity fades the WHOLE background stack (art + dim overlay);
        -- euiAlpha stays the darkening amount of the overlay itself.
        op = theme.euiOpacity
        if op == nil then op = 1 end
        host._edbBgAtlas:SetAlpha(op)
        host._edbBgOverlay:SetColorTexture(0, 0, 0, theme.euiAlpha or 0.5)
        host._edbBgOverlay:SetAlpha(op)
        host._edbModernBg:SetAlpha(0)
    end
    -- Bar Opacity carries the border with it: the base border alpha (0.8)
    -- is baked into the strip textures, frame alpha multiplies on top.
    -- SetAlpha is combat-legal even on implicitly protected bars.
    if host._edbBorder then host._edbBorder:SetAlpha(op) end
end

-- Exposed so the options preview strip renders the exact same recipe.
function ns.MakePreviewBackdrop(host, themeCfg)
    ApplyThemeToHost(host, themeCfg)
end

-------------------------------------------------------------------------------
--  Live registry + bar factory
-------------------------------------------------------------------------------
local live = {}
ns._live = live
ns._moEligible = {}

-- Hidden park for retired secure frames (never reused, never destroyed).
local parkFrame = CreateFrame("Frame")
parkFrame:Hide()
ns._park = parkFrame

-- Forward declarations
local ApplyLayout
local AfterBarStateChange
local RegisterBarMouseoverProxy

local function MakeBarCtx(id)
    local ctx = { id = id }
    function ctx.IsVertical()
        local c = ctx.cfg
        return c ~= nil and c.orientation == "V"
    end
    function ctx.GetThickness()
        local c = ctx.cfg
        if c and c.thickness then return c.thickness end
        return 30
    end
    function ctx.GetLengthPx()
        local rec = live[id]
        if rec and rec.bar then
            if ctx.IsVertical() then return rec.bar:GetHeight() end
            return rec.bar:GetWidth()
        end
        local c = ctx.cfg
        if c and c.length then return c.length end
        return 400
    end
    function ctx.RequestLayout()
        ns.RequestLayout(id)
    end
    function ctx.IsBarAtTop()
        local rec = live[id]
        if not (rec and rec.bar) then return false end
        local _, cy = rec.bar:GetCenter()
        if not cy then return false end
        return cy > (UIParent:GetHeight() / 2)
    end
    return ctx
end

-- Offset of an anchor point from a rect's BOTTOMLEFT corner.
local function PointXY(point, w, h)
    if point == "TOPLEFT" then return 0, h end
    if point == "TOP" then return w / 2, h end
    if point == "TOPRIGHT" then return w, h end
    if point == "LEFT" then return 0, h / 2 end
    if point == "RIGHT" then return w, h / 2 end
    if point == "BOTTOMLEFT" then return 0, 0 end
    if point == "BOTTOM" then return w / 2, 0 end
    if point == "BOTTOMRIGHT" then return w, 0 end
    return w / 2, h / 2
end

local function ApplyBarPosition(id)
    local rec = live[id]
    local cfg = ns.GetBar(id)
    if not (rec and rec.bar and cfg) then return end
    local bar = rec.bar
    -- Implicitly protected bar (secure children): repositioning is blocked
    -- in combat. Keep the current position and re-apply once on regen.
    if InCombatLockdown() and bar:IsProtected() then
        ns.DeferUntilOOC("pos:" .. id, function() ApplyBarPosition(id) end)
        return
    end
    local vertical = cfg.orientation == "V"
    local full = cfg.lengthMode == "full"
    local sp = cfg.savedPos

    -- Edge snap, ignoring an edge that does not match the orientation
    -- (the options page keeps the setting valid; defense for stale data).
    local edge = cfg.snapEdge
    if edge == "none" then edge = nil end
    if edge then
        if vertical then
            if edge ~= "left" and edge ~= "right" then edge = nil end
        else
            if edge ~= "bottom" and edge ~= "top" then edge = nil end
        end
    end

    bar:ClearAllPoints()
    if not (full or edge) then
        -- Plain saved position: keep the stored anchor semantics as-is.
        if sp and sp.point then
            bar:SetPoint(sp.point, UIParent, sp.relPoint or sp.point, sp.x or 0, sp.y or 0)
        else
            bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        return
    end

    -- Full-screen length: pin BOTH ends to UIParent so the ENGINE keeps the
    -- bar exactly full through every resolution/UI-scale change -- a
    -- computed-width snapshot goes stale whenever it is taken before the
    -- final screen metrics land (field-reported as not-full bars). Only the
    -- cross-axis coordinate is computed below; the explicit SetSize from
    -- ApplyBar remains as a fallback if anything ever strips the anchors
    -- (the anchor rect overrides it while both points are set).

    -- Full-screen length and/or edge snap: compute the final center
    -- ANALYTICALLY and anchor once. Never read GetCenter here -- when the
    -- size or orientation changed earlier in this same apply, GetCenter
    -- still returns the previous layout's rect and the bar lands offset
    -- by the old geometry. The bar was explicitly SetSize'd just before
    -- this call, so GetSize is trustworthy.
    -- Along-axis: screen-centered when full, else from the saved position.
    -- Cross-axis: flush to the snapped edge, else from the saved position.
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local bw, bh = bar:GetSize()
    local cx, cy = uw / 2, uh / 2
    if sp and sp.point then
        local rx, ry = PointXY(sp.relPoint or sp.point, uw, uh)
        local px, py = PointXY(sp.point, bw, bh)
        cx = rx + (sp.x or 0) - px + bw / 2
        cy = ry + (sp.y or 0) - py + bh / 2
    end
    if vertical then
        if full then cy = uh / 2 end
        if edge == "left" then
            cx = bw / 2
        elseif edge == "right" then
            cx = uw - bw / 2
        end
    else
        if full then cx = uw / 2 end
        if edge == "bottom" then
            cy = bh / 2
        elseif edge == "top" then
            cy = uh - bh / 2
        end
    end
    if full then
        if vertical then
            bar:SetPoint("TOP", UIParent, "TOPLEFT", cx, 0)
            bar:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, 0)
        else
            bar:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, cy)
            bar:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, cy)
        end
    else
        bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    end
end

local function EnsureSlot(rec, blockCfg)
    local slot = rec.slots[blockCfg.id]
    if not slot then
        slot = CreateFrame("Frame", nil, rec.bar)
        slot:SetSize(10, 10)
        local content = CreateFrame("Frame", nil, slot)
        content:SetSize(10, 10)
        slot._edbContent = content
        rec.slots[blockCfg.id] = slot
    end
    return slot
end

local function ApplyBlockDecor(slot, blockCfg, barCfg)
    -- Optional block background
    if blockCfg.bg then
        if not slot._edbBg then
            slot._edbBg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
            slot._edbBg:SetAllPoints(slot)
        end
        local c = blockCfg.bg
        slot._edbBg:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.5)
        slot._edbBg:Show()
    elseif slot._edbBg then
        slot._edbBg:Hide()
    end
    -- Optional hover highlight (4% white), one bar-wide switch. Mouse
    -- MOTION only: clicks pass through to the block's own buttons; motion
    -- is off entirely when the option is disabled (zero cost).
    if barCfg and barCfg.hoverHighlight then
        if not slot._edbHover then
            slot._edbHover = slot:CreateTexture(nil, "OVERLAY", nil, 6)
            slot._edbHover:SetAllPoints(slot)
            slot._edbHover:SetColorTexture(1, 1, 1, 0.04)
            slot._edbHover:Hide()
        end
        if slot.EnableMouseMotion then slot:EnableMouseMotion(true) end
        slot:SetScript("OnEnter", function(s) if s._edbHover then s._edbHover:Show() end end)
        slot:SetScript("OnLeave", function(s) if s._edbHover then s._edbHover:Hide() end end)
    else
        if slot._edbHover then slot._edbHover:Hide() end
        if slot.EnableMouseMotion then slot:EnableMouseMotion(false) end
        slot:SetScript("OnEnter", nil)
        slot:SetScript("OnLeave", nil)
    end
end

local function AnchorContent(slot, blockCfg, vertical, barCfg)
    local content = slot._edbContent
    if not content then return end
    -- Per-block content scale: the whole content tree (icons + texts)
    -- scales as a group inside its slot. Offsets divide by the scale so
    -- stored X/Y stay screen-true regardless of it.
    local s = (blockCfg.scale or 100) / 100
    if s < 0.25 then s = 0.25 elseif s > 3 then s = 3 end
    content:SetScale(s)
    content:ClearAllPoints()
    local a = blockCfg.align or "CENTER"
    local x = (blockCfg.xOff or 0) / s
    local y = (blockCfg.yOff or 0) / s
    -- Centered-fill slot: the solver pins the CONTENT to the bar's true
    -- center via this along-axis shift (the slot itself is asymmetric).
    -- Align is forced CENTER -- pinning is the block's whole point.
    local cShift = slot._edbCenterShift
    if cShift then
        a = "CENTER"
        if vertical then y = y - cShift / s else x = x + cShift / s end
    end
    -- Auto-mode slots reserve per-side gaps around the content; the align
    -- anchor must step inward by the LEADING gap (align LEFT otherwise
    -- piles the whole reserve on the far side), and CENTER shifts by half
    -- the gap DIFFERENCE so asymmetric gaps land on their sides. Gaps are
    -- slot-space px, so they divide by the content scale like the offsets.
    -- The fill block's slot is the remainder, not gap-sized: plain align.
    if barCfg and ns.BarSizingMode(barCfg) == "auto"
       and blockCfg.id ~= ns.EnsureFillBlock(barCfg) then
        local gl, gr = ns.ContentGapsOf(blockCfg)
        gl, gr = gl / s, gr / s
        if vertical then
            if a == "LEFT" then y = y - gl
            elseif a == "RIGHT" then y = y + gr
            else y = y - (gl - gr) / 2 end
        else
            if a == "LEFT" then x = x + gl
            elseif a == "RIGHT" then x = x - gr
            else x = x + (gl - gr) / 2 end
        end
    end
    if vertical then
        -- On vertical bars align maps to TOP/CENTER/BOTTOM (same stored keys).
        if a == "LEFT" then
            content:SetPoint("TOP", slot, "TOP", x, y)
        elseif a == "RIGHT" then
            content:SetPoint("BOTTOM", slot, "BOTTOM", x, y)
        else
            content:SetPoint("CENTER", slot, "CENTER", x, y)
        end
    else
        if a == "LEFT" then
            content:SetPoint("LEFT", slot, "LEFT", x, y)
        elseif a == "RIGHT" then
            content:SetPoint("RIGHT", slot, "RIGHT", x, y)
        else
            content:SetPoint("CENTER", slot, "CENTER", x, y)
        end
    end
end

-- Forces every block to fully re-render (inst:Refresh) on the next layout
-- pass by forgetting the assigned widths. For options that change how the
-- factories anchor their internals (e.g. the text-only offset, injected by
-- each re-anchor), where a plain ApplyBar would see unchanged px and skip.
function ns.ReflowBlocks(id)
    local rec = live and live[id]
    if not rec then return end
    wipe(rec.assigned)
    ns.RequestLayout(id)
end

-- Coalesced re-layout: one pass per bar per frame at most.
function ns.RequestLayout(id)
    local rec = live[id]
    if not rec then return end
    if rec.layoutQueued then return end
    rec.layoutQueued = true
    C_Timer.After(0, function()
        local r = live[id]
        if r then r.layoutQueued = false end
        ApplyLayout(id)
    end)
end

ApplyLayout = function(id)
    local rec = live[id]
    local cfg = ns.GetBar(id)
    if not (rec and rec.bar and cfg) then return end
    if not rec.enabled then return end
    -- A bar holding secure children (profession/micromenu passthrough
    -- buttons) is implicitly protected, and so is every ancestor of those
    -- buttons: slot geometry on it is blocked in combat (raid-reported
    -- ADDON_ACTION_BLOCKED on slot:ClearAllPoints). Freeze the current
    -- layout for the fight and run ONE deferred pass on regen.
    if InCombatLockdown() and rec.bar:IsProtected() then
        ns.DeferUntilOOC("layout:" .. id, function() ApplyLayout(id) end)
        return
    end
    local vertical = cfg.orientation == "V"
    local barLen
    if vertical then barLen = rec.bar:GetHeight() else barLen = rec.bar:GetWidth() end
    local L2 = (barLen or 0) - 2 * EDGE_PAD
    if L2 < 1 then L2 = 1 end

    local function measure(b)
        local inst = rec.insts[b.id]
        if inst and inst.GetAutoLength then
            local w = inst:GetAutoLength()
            return w or 0
        end
        return 0
    end

    local segs = ns.SolveLayout(cfg, L2, measure)
    for i = 1, #segs do
        local seg = segs[i]
        local slot = rec.slots[seg.block.id]
        if slot then
            local px = seg.px
            if px < 1 then px = 1 end
            -- Positions come from the solver (seg.at), never a running
            -- cursor: a Force Centered block leaves uncovered background
            -- beside it, so segments are not guaranteed contiguous.
            local at = EDGE_PAD + (seg.at or 0)
            slot:ClearAllPoints()
            if vertical then
                slot:SetSize(max(1, rec.bar:GetWidth()), px)
                slot:SetPoint("TOP", rec.bar, "TOP", 0, -at)
            else
                slot:SetSize(px, max(1, rec.bar:GetHeight()))
                slot:SetPoint("LEFT", rec.bar, "LEFT", at, 0)
            end
            -- Respect the visibility engine's content gate: a layout pass on
            -- a visibility-hidden bar must not resurrect click-catchers.
            slot:SetShown(rec.contentShown ~= false)
            -- Centered-fill content pinning: re-anchor when the solver's
            -- shift changes (or clears) so the content tracks true center
            -- while its slot spans the whole middle.
            if slot._edbCenterShift ~= seg.contentShift then
                slot._edbCenterShift = seg.contentShift
                AnchorContent(slot, seg.block, vertical, cfg)
            end
            -- EVERY block renders INTO its assigned share (sizing is purely
            -- share-based); re-render whenever the assignment changes, e.g.
            -- on a bar resize, so content re-fits its new slot.
            local prev = rec.assigned[seg.block.id]
            if prev == nil or abs(prev - px) > 0.5 then
                rec.assigned[seg.block.id] = px
                local inst = rec.insts[seg.block.id]
                if inst and inst.Refresh then inst:Refresh() end
            end
        end
    end
end

-- Idempotent create-or-update of one bar from its cfg.
function ns.ApplyBar(id)
    local profile = ns.GetProfile()
    if not profile then return end
    local cfg = ns.GetBar(id)
    local rec = live[id]

    -- An existing implicitly-protected bar (secure children) cannot be
    -- sized, positioned, or hidden in combat. Defer the whole apply to
    -- regen; the bar keeps its current state for the fight (runtime
    -- visibility stays alpha-based and unaffected).
    if rec and rec.bar and InCombatLockdown() and rec.bar:IsProtected() then
        ns.DeferUntilOOC("applybar:" .. id, function() ns.ApplyBar(id) end)
        return
    end

    -- "Never" visibility = fully disabled: the bar does NO work (no
    -- instances, no events, no ticks), identical to enabled == false.
    if not cfg or cfg.enabled == false or cfg.visibility == "never" then
        if rec and rec.enabled then
            for _, inst in pairs(rec.insts) do
                if inst.Disable then inst:Disable() end
            end
            rec.bar:Hide()
            rec.enabled = false
        end
        if AfterBarStateChange then AfterBarStateChange() end
        return
    end

    if not rec then
        rec = { slots = {}, insts = {}, assigned = {}, enabled = false }
        rec.bar = CreateFrame("Frame", "EllesmereUIDataBarsBar" .. id, UIParent)
        rec.bar:SetFrameStrata("MEDIUM")
        rec.bar:SetFrameLevel(10)
        rec.bar:SetMovable(true)
        rec.bar:EnableMouse(false)
        rec.bar:SetClampedToScreen(true)
        rec.bar._edbBorder = PP.CreateBorder(rec.bar, 0, 0, 0, 0.8, 1, "OVERLAY", 7)
        -- Anchor-driven size changes (full-length bars stretching with the
        -- screen) re-solve the block layout; RequestLayout coalesces and
        -- the combat gate defers protected bars to regen.
        rec.bar:HookScript("OnSizeChanged", function() ns.RequestLayout(id) end)
        rec.ctx = MakeBarCtx(id)
        rec.ctx.frame = rec.bar
        live[id] = rec
        RegisterBarMouseoverProxy(id)
    end

    local wasDisabled = not rec.enabled
    rec.enabled = true
    rec.ctx.cfg = cfg

    -- Size (raw px; the border pixel-snaps itself)
    local vertical = cfg.orientation == "V"
    local thickness = cfg.thickness or 30
    local length
    if cfg.lengthMode == "full" then
        if vertical then length = UIParent:GetHeight() else length = UIParent:GetWidth() end
    else
        length = cfg.length or 400
    end
    if vertical then
        rec.bar:SetSize(thickness, length)
    else
        rec.bar:SetSize(length, thickness)
    end

    ApplyBarPosition(id)
    ApplyThemeToHost(rec.bar, cfg.theme)

    -- Reconcile block instances against cfg.blocks
    local want = {}
    for i = 1, #cfg.blocks do
        want[cfg.blocks[i].id] = cfg.blocks[i]
    end
    for blockId, inst in pairs(rec.insts) do
        local b = want[blockId]
        if not b or b.type ~= inst._edbType then
            if inst.Disable then inst:Disable() end
            if inst.Destroy then inst:Destroy() end
            rec.insts[blockId] = nil
            rec.assigned[blockId] = nil
            local slot = rec.slots[blockId]
            if slot then slot:Hide() end
        end
    end
    for blockId, slot in pairs(rec.slots) do
        if not want[blockId] then slot:Hide() end
    end

    for i = 1, #cfg.blocks do
        local b = cfg.blocks[i]
        local slot = EnsureSlot(rec, b)
        ApplyBlockDecor(slot, b, cfg)
        AnchorContent(slot, b, vertical, cfg)
        local inst = rec.insts[b.id]
        if not inst then
            local factory = ns.BlockFactories[b.type]
            if factory then
                inst = factory(b, slot, slot._edbContent, rec.ctx)
                if inst then
                    inst._edbType = b.type
                    rec.insts[b.id] = inst
                    if inst.Enable then inst:Enable() end
                end
            end
        elseif wasDisabled then
            -- Re-enabling a previously disabled bar: instance Enable is
            -- idempotent (re-registers events + heartbeat under the same key).
            if inst.Enable then inst:Enable() end
        end
    end

    rec.bar:Show()

    for i = 1, #cfg.blocks do
        local inst = rec.insts[cfg.blocks[i].id]
        if inst and inst.Refresh then inst:Refresh() end
    end

    ns.RequestLayout(id)
    if AfterBarStateChange then AfterBarStateChange() end
end

-- Theme-only fast path (live slider / swatch feedback).
function ns.ApplyTheme(id)
    local rec = live[id]
    local cfg = ns.GetBar(id)
    if not (rec and rec.bar and cfg) then return end
    ApplyThemeToHost(rec.bar, cfg.theme)
end

function ns.GetLiveAutoLength(barId, blockId)
    local rec = live[barId]
    if not rec then return nil end
    local inst = rec.insts[blockId]
    if inst and inst.GetAutoLength then return inst:GetAutoLength() end
    return nil
end

-- Effective share of the TOTAL bar for one block in percentage points,
-- matching SolveLayout. Lives below the live table (unlike the pure solver)
-- because Auto Sized blocks need the real bar length and live content
-- measurements; falls back to the configured length for unbuilt bars.
function ns.NormalizedShare(barCfg, blockId)
    if not barCfg or #barCfg.blocks == 0 then return 0 end
    local rec = live[barCfg.id]
    local L
    if rec and rec.bar then
        if barCfg.orientation == "V" then
            L = rec.bar:GetHeight()
        else
            L = rec.bar:GetWidth()
        end
    end
    if not L or L < 2 then
        if barCfg.lengthMode == "full" then
            if barCfg.orientation == "V" then
                L = UIParent:GetHeight()
            else
                L = UIParent:GetWidth()
            end
        else
            L = barCfg.length or 400
        end
    end
    L = L - 2 * EDGE_PAD
    if L < 1 then L = 1 end
    local function measure(b)
        local inst = rec and rec.insts[b.id]
        if inst and inst.GetAutoLength then return inst:GetAutoLength() or 0 end
        return 0
    end
    local segs = ns.SolveLayout(barCfg, L, measure)
    for i = 1, #segs do
        if segs[i].block.id == blockId then
            return segs[i].px * 100 / L
        end
    end
    return 0
end

-------------------------------------------------------------------------------
--  Visibility runtime
--  ERB model: one engine-owned event frame, registered only while at least
--  one enabled bar exists. Mouseover reveal goes through per-bar plain-table
--  poll proxies (never EnableMouse on the real bar).
-------------------------------------------------------------------------------
ns.EDB_VIS_CAPS = { partyIncludesRaid = true, luaDragonriding = true }

-- Bar visibility = ALPHA ONLY, applied directly. A bar hosting a secure
-- block (micromenu passthrough buttons, travel hearth) is an IMPLICITLY
-- PROTECTED ancestor: EnableMouse/Show/Hide on it during combat is
-- ADDON_ACTION_BLOCKED (the parent SetElementVisibility helper toggles
-- EnableMouse, so it must never touch these bars). SetAlpha is combat-legal
-- on protected frames, and the bar never has mouse enabled anyway.
local function SetBarAlphaVisible(rec, visible)
    if rec and rec.bar then
        rec.bar:SetAlpha(visible and 1 or 0)
    end
end

-- Alpha alone would leave block children (including the SECURE
-- travel/micromenu buttons) fully click-interactive while invisible.
-- Slots are OUR insecure frames, so toggling their shown state suppresses
-- every child in one stroke; the bar frame itself stays shown so the
-- mouseover poll can keep measuring it. The layout pass reads
-- rec.contentShown for the same gate, so relayouts while hidden cannot
-- resurrect click-catchers. Slots hosting secure blocks are implicitly
-- protected in combat -- those flips defer (rec.contentDeferred) and the
-- REGEN_ENABLED visibility pass re-applies them; meanwhile alpha 0 covers
-- the visual and the micromenu buttons self-disable via their combatlock
-- driver.
local function SetBarContentShown(id, shown)
    local rec = live[id]
    if not rec then return end
    shown = shown and true or false
    if (rec.contentShown ~= false) == shown and not rec.contentDeferred then
        return
    end
    rec.contentShown = shown
    rec.contentDeferred = nil
    local inCombat = InCombatLockdown()
    local function apply(slot, s)
        if inCombat and slot:IsProtected() then
            rec.contentDeferred = true
        elseif slot:IsShown() ~= s then
            slot:SetShown(s)
        end
    end
    if not shown then
        for _, slot in pairs(rec.slots) do apply(slot, false) end
    else
        -- Re-show only the slots belonging to CURRENT blocks; slots orphaned
        -- by block removal stay hidden.
        local cfg = rec.ctx and rec.ctx.cfg
        if cfg and cfg.blocks then
            for i = 1, #cfg.blocks do
                local slot = rec.slots[cfg.blocks[i].id]
                if slot then apply(slot, true) end
            end
        end
    end
end

-- 8 percent white wash on a block's LIVE slot while its settings section is
-- hovered in the options (the options page drives this; nil clears).
local _editHL
function ns.SetBlockEditHighlight(barId, blockId)
    if _editHL then
        local rec = live[_editHL.barId]
        local slot = rec and rec.slots[_editHL.blockId]
        if slot and slot._edbEditHL then slot._edbEditHL:Hide() end
        _editHL = nil
    end
    if not (barId and blockId) then return end
    local rec = live[barId]
    local slot = rec and rec.slots[blockId]
    if not slot then return end
    if not slot._edbEditHL then
        local t = slot:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetAllPoints(slot)
        t:SetColorTexture(1, 1, 1, 0.15)
        slot._edbEditHL = t
    end
    slot._edbEditHL:Show()
    _editHL = { barId = barId, blockId = blockId }
end

local visRuntime = {}
do
    local visFrame
    local _inCombat = false
    local st = {}

    local VIS_EVENTS = {
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE",
        "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CAN_GLIDE_CHANGED",
        "ZONE_CHANGED_NEW_AREA", "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
    }

    -- Legacy scalar evaluation for the modes the multi engine declines.
    -- in_party matches party-or-raid (caps.partyIncludesRaid semantics).
    local function LegacyScalar(mode)
        mode = mode or "always"
        if mode == "always" then return true end
        if mode == "never" then return false end
        if mode == "mouseover" then return "mouseover" end
        if mode == "in_combat" then return _inCombat end
        if mode == "out_of_combat" then return not _inCombat end
        local inRaid = IsInRaid()
        local inGroup = IsInGroup()
        if mode == "in_raid" then return inRaid end
        if mode == "in_party" then return inGroup end
        if mode == "solo" then return not inGroup end
        return true
    end

    function ns.UpdateAllBarVisibility()
        local profile = ns.GetProfile()
        if not profile then return end
        local bars = profile.bars
        for i = 1, #bars do
            local cfg = bars[i]
            local rec = live[cfg.id]
            if rec and rec.enabled and cfg.enabled ~= false then
                local vis
                if EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(cfg) then
                    vis = false
                else
                    st.inCombat = _inCombat
                    st.inRaid = IsInRaid()
                    st.inParty = (not st.inRaid) and IsInGroup()
                    local ext
                    if EllesmereUI.EvalVisibilityExtended then
                        ext = EllesmereUI.EvalVisibilityExtended(cfg, "visibility", st, ns.EDB_VIS_CAPS)
                    end
                    if ext ~= nil then vis = ext else vis = LegacyScalar(cfg.visibility) end
                end
                if vis == "mouseover" then
                    ns._moEligible[cfg.id] = true
                    SetBarAlphaVisible(rec, false)
                    SetBarContentShown(cfg.id, false)
                else
                    ns._moEligible[cfg.id] = nil
                    SetBarAlphaVisible(rec, vis and true or false)
                    SetBarContentShown(cfg.id, vis and true or false)
                end
            else
                ns._moEligible[cfg.id] = nil
            end
        end
    end

    local function OnVisEvent(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            _inCombat = false
        elseif event == "PLAYER_ENTERING_WORLD" then
            _inCombat = InCombatLockdown() and true or false
        end
        ns.UpdateAllBarVisibility()
    end

    local function AnyEnabledBar()
        local profile = ns.GetProfile()
        if not profile then return false end
        local bars = profile.bars
        for i = 1, #bars do
            if bars[i].enabled ~= false and bars[i].visibility ~= "never" then
                return true
            end
        end
        return false
    end

    function visRuntime.UpdateEventRegistration()
        if AnyEnabledBar() then
            if not visFrame then
                visFrame = CreateFrame("Frame")
                visFrame:SetScript("OnEvent", OnVisEvent)
            end
            for _, e in ipairs(VIS_EVENTS) do visFrame:RegisterEvent(e) end
            if EllesmereUI._hasGlidingEvent then
                visFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
            end
            _inCombat = InCombatLockdown() and true or false
        elseif visFrame then
            visFrame:UnregisterAllEvents()
        end
    end

    -- Per-bar mouseover poll proxy: plain table, registered once per bar id.
    -- The shared poll only touches the proxy; Show/Hide route through
    -- SetBarAlphaVisible (alpha-only), never EnableMouse on the bar.
    local moRegistered = {}
    RegisterBarMouseoverProxy = function(id)
        if moRegistered[id] then return end
        if not EllesmereUI.RegisterMouseoverTarget then return end
        moRegistered[id] = true
        local proxy = {}
        proxy.GetRect = function()
            local rec = live[id]
            if rec and rec.bar then return rec.bar:GetRect() end
            return nil
        end
        proxy.GetEffectiveScale = function()
            local rec = live[id]
            if rec and rec.bar then return rec.bar:GetEffectiveScale() end
            return 1
        end
        proxy.SetAlpha = function() end
        proxy.EnableMouse = function() end
        proxy.Show = function()
            local rec = live[id]
            if rec and rec.bar then
                SetBarAlphaVisible(rec, true)
                SetBarContentShown(id, true)
            end
        end
        proxy.Hide = function()
            local rec = live[id]
            if rec and rec.bar then
                SetBarAlphaVisible(rec, false)
                SetBarContentShown(id, false)
            end
        end
        EllesmereUI.RegisterMouseoverTarget(proxy, function()
            if ns._moEligible[id] then return true end
            return false
        end)
    end
end

-------------------------------------------------------------------------------
--  Display-size events (full-screen-length bars only)
-------------------------------------------------------------------------------
local dispRuntime = {}
do
    local dispFrame

    local function AnyFullBar()
        local profile = ns.GetProfile()
        if not profile then return false end
        local bars = profile.bars
        for i = 1, #bars do
            if bars[i].enabled ~= false and bars[i].visibility ~= "never"
               and bars[i].lengthMode == "full" then
                return true
            end
        end
        return false
    end

    local function OnDispEvent()
        local profile = ns.GetProfile()
        if not profile then return end
        ns.WipeFitCache()
        local bars = profile.bars
        for i = 1, #bars do
            if bars[i].enabled ~= false and bars[i].lengthMode == "full" then
                ns.ApplyBar(bars[i].id)
            end
        end
    end

    function dispRuntime.UpdateEventRegistration()
        if AnyFullBar() then
            if not dispFrame then
                dispFrame = CreateFrame("Frame")
                dispFrame:SetScript("OnEvent", OnDispEvent)
            end
            dispFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
            dispFrame:RegisterEvent("UI_SCALE_CHANGED")
        elseif dispFrame then
            dispFrame:UnregisterAllEvents()
        end
    end
end

-- Recompute every cross-cutting gate after any bar state change.
AfterBarStateChange = function()
    visRuntime.UpdateEventRegistration()
    dispRuntime.UpdateEventRegistration()
    ns.UpdateAllBarVisibility()
    if ns.RefreshMicroMenuHider then ns.RefreshMicroMenuHider() end
end

-------------------------------------------------------------------------------
--  Unlock mode
--  One element per bar in the profile, key "EDB_<id>". Elements are NEVER
--  unregistered: a bar deleted mid-session leaves its element registered
--  with isHidden true / getFrame nil (mover goes dormant, anchors survive).
--  Next login the retired id simply is not registered again.
-------------------------------------------------------------------------------
local function MakeBarElement(barId, orderIdx)
    local function cfgOf() return ns.GetBar(barId) end
    local cfgNow = cfgOf()
    local label = "DataBar " .. barId
    if cfgNow and cfgNow.name then label = cfgNow.name end
    return EllesmereUI.MakeUnlockElement({
        key      = "EDB_" .. barId,
        label    = label,
        group    = "DataBars",
        order    = 700 + orderIdx,
        -- ApplyBarPosition is the sole position authority: full-screen
        -- centering and edge snap recompute the anchor from cfg, so the
        -- centralized init loop re-applying the stored CENTER position
        -- (captured under whatever footprint was live at save time) would
        -- clobber it -- e.g. a bar switched H->V got re-pinned at the old
        -- horizontal bar's center on every login and size change. The
        -- resize/init paths delegate to applyPosition instead; mover,
        -- save/load, and anchors are unaffected.
        noInitHook = true,
        getFrame = function()
            local rec = live[barId]
            local cfg = cfgOf()
            if rec and rec.enabled and cfg and cfg.enabled ~= false then
                return rec.bar
            end
            return nil
        end,
        getSize  = function()
            local rec = live[barId]
            if rec and rec.bar then return rec.bar:GetSize() end
            return 0, 0
        end,
        savePos  = function(_, pt, rpt, x, y)
            local cfg = cfgOf()
            if not cfg then return end
            cfg.savedPos = { point = pt, relPoint = rpt, x = x, y = y }
            -- Any manual move un-snaps the bar: it is no longer flush to
            -- the edge, so the setting reverting to None reflects reality
            -- (and applyPos would otherwise fight the drag).
            if cfg.snapEdge and cfg.snapEdge ~= "none" then
                cfg.snapEdge = "none"
            end
        end,
        loadPos  = function()
            local cfg = cfgOf()
            local sp = cfg and cfg.savedPos
            if not (sp and sp.point) then return nil end
            return { point = sp.point, relPoint = sp.relPoint, x = sp.x, y = sp.y }
        end,
        clearPos = function()
            local cfg = cfgOf()
            if cfg then cfg.savedPos = nil end
        end,
        applyPos = function()
            ApplyBarPosition(barId)
        end,
        -- Width/height matches NEVER override full-screen mode on the
        -- along-axis: ApplyAllWidthHeightMatches re-applies stored matches
        -- on EVERY login, and the old "flip lengthMode to custom so the
        -- match sticks" here silently reverted users' Full Screen bars on
        -- each /reload (field-reported; a match stored on the bar from
        -- unlock mode re-fired forever). Full wins; a user who wants the
        -- match must turn Full Screen off first. Cross-axis (thickness)
        -- always applies.
        setWidth = function(_, w)
            local cfg = cfgOf()
            if not cfg then return end
            w = floor((w or 0) + 0.5)
            if w < 16 then w = 16 end
            if cfg.orientation == "V" then
                cfg.thickness = w
            else
                if cfg.lengthMode == "full" then return end
                cfg.length = w
            end
            ns.ApplyBar(barId)
        end,
        setHeight = function(_, h)
            local cfg = cfgOf()
            if not cfg then return end
            h = floor((h or 0) + 0.5)
            if h < 16 then h = 16 end
            if cfg.orientation == "V" then
                if cfg.lengthMode == "full" then return end
                cfg.length = h
            else
                cfg.thickness = h
            end
            ns.ApplyBar(barId)
        end,
        isHidden = function()
            local cfg = cfgOf()
            if not cfg then return true end
            return cfg.enabled == false
        end,
        allowMatchSource = true,
    })
end

function ns.RegisterAllUnlockElements()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local profile = ns.GetProfile()
    if not profile then return end
    local elements = {}
    for i = 1, #profile.bars do
        local barId = profile.bars[i].id
        elements[#elements + 1] = MakeBarElement(barId, i)
        -- Cog deep-link: unlock cog on this element opens the DataBars page.
        EllesmereUI._ELEMENT_SETTINGS_MAP = EllesmereUI._ELEMENT_SETTINGS_MAP or {}
        EllesmereUI._ELEMENT_SETTINGS_MAP["EDB_" .. barId] = { module = "EllesmereUIDataBars", page = "DataBars" }
    end
    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIDataBars")
    end
end

-------------------------------------------------------------------------------
--  Templates + CRUD
-------------------------------------------------------------------------------
local TEMPLATES = {
    bottom = {
        name = "Bottom Info Bar", orientation = "H", lengthMode = "full",
        length = 1200, thickness = 30, theme = "eui", snapEdge = "bottom",
        sizingMode = "auto", fillType = "clock", centerType = "clock",
        savedPos = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 0 },
        blocks = {
            { type = "micromenu" },
            { type = "xprep", contentGapL = 30, contentGapR = 30 },
            { type = "spec", contentGapL = 20, contentGapR = 20 },
            { type = "durability" },
            { type = "clock" },
            { type = "profession", contentGapL = 30, contentGapR = 30 },
            { type = "gold", contentGapL = 30, contentGapR = 30,
              color = { r = 0.9075, g = 0.7125, b = 0.3804 } },
            { type = "fps", contentGapL = 30, contentGapR = 0 },
            { type = "ms", contentGapL = 0, contentGapR = 30 },
            { type = "travel", align = "RIGHT", xOff = -5 },
        },
    },
    minimapc = {
        name = "Minimap Companion", orientation = "H", lengthMode = "custom",
        length = 220, thickness = 24, theme = "modern",
        sizingMode = "even",
        savedPos = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -4, y = -240 },
        blocks = { { type = "clock" }, { type = "fps" }, { type = "ms" } },
    },
    microstrip = {
        name = "Micro Menu Strip", orientation = "H", lengthMode = "custom",
        length = 420, thickness = 28, theme = "modern",
        sizingMode = "auto",
        savedPos = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -4, y = 4 },
        blocks = { { type = "micromenu" } },
    },
    empty = {
        name = "New DataBar", orientation = "H", lengthMode = "custom",
        length = 400, thickness = 30, theme = "eui",
        sizingMode = "auto",
        savedPos = nil,
        blocks = {},
    },
}

local function UniqueBarName(base)
    local profile = ns.GetProfile()
    if not profile then return base end
    local function taken(n)
        for i = 1, #profile.bars do
            if profile.bars[i].name == n then return true end
        end
        return false
    end
    if not taken(base) then return base end
    local n = 2
    while taken(base .. " " .. n) do n = n + 1 end
    return base .. " " .. n
end

-- Appends a block of typeKey to the bar and applies. Returns the blockCfg.
function ns.AddBlock(barId, typeKey)
    local cfg = ns.GetBar(barId)
    if not cfg then return nil end
    if not ns.BLOCK_DEFAULTS[typeKey] then return nil end
    cfg.nextBlockId = (cfg.nextBlockId or 0) + 1
    local b = {
        id       = cfg.nextBlockId,
        type     = typeKey,
        align    = "CENTER",
        xOff     = 0,
        yOff     = 0,
        bg       = nil,
        settings = DeepCopy(ns.BLOCK_DEFAULTS[typeKey]),
    }
    -- Micro menu counters default 8px above their buttons -- via the SAME
    -- textYOff the Text Position cog edits, so the slider starts at 8 and
    -- ONE value owns the counter position (the old osSocialText offset +
    -- top-bar sign flip are dead; the anchor is plain button-center).
    if typeKey == "micromenu" then b.textYOff = 8 end
    cfg.blocks[#cfg.blocks + 1] = b
    ns.ApplyBar(barId)
    return b
end

function ns.RemoveBlock(barId, blockId)
    local cfg = ns.GetBar(barId)
    if not cfg then return end
    for i = 1, #cfg.blocks do
        if cfg.blocks[i].id == blockId then
            tremove(cfg.blocks, i)
            break
        end
    end
    -- Center is optional: removing the centered block just clears the
    -- designation (fill heals to the last block via EnsureFillBlock).
    if cfg.centerBlockId == blockId then cfg.centerBlockId = nil end
    ns.ApplyBar(barId)
end

function ns.MoveBlock(barId, blockId, delta)
    local cfg = ns.GetBar(barId)
    if not cfg then return end
    local _, idx = GetBlock(cfg, blockId)
    if not idx then return end
    local target = idx + (delta or 0)
    if target < 1 or target > #cfg.blocks then return end
    cfg.blocks[idx], cfg.blocks[target] = cfg.blocks[target], cfg.blocks[idx]
    ns.ApplyBar(barId)
end

-- Designates blockId as the bar's Fill Remaining block (auto mode). The
-- previous fill block simply stops being it -- one fill per bar always.
-- A block may fill AND be Force Centered: its slot then absorbs the whole
-- middle span with the content pinned at true center.
function ns.SetFillBlock(barId, blockId)
    local cfg = ns.GetBar(barId)
    local b = GetBlock(cfg, blockId)
    if not b then return end
    cfg.fillBlockId = blockId
    ns.ApplyBar(barId)
end

-- Designates blockId as the bar's Force Centered block (auto mode; nil
-- clears). At most one per bar.
function ns.SetCenterBlock(barId, blockId)
    local cfg = ns.GetBar(barId)
    if not cfg then return end
    if blockId ~= nil then
        local b = GetBlock(cfg, blockId)
        if not b then return end
    end
    cfg.centerBlockId = blockId
    ns.ApplyBar(barId)
end

-- Drag-reorder commit: move a block to boundary index newIndex (1-based,
-- in the PRE-removal indexing of the blocks array, n+1 = after the last).
function ns.MoveBlockTo(barId, blockId, newIndex)
    local cfg = ns.GetBar(barId)
    if not cfg then return end
    local from
    for i = 1, #cfg.blocks do
        if cfg.blocks[i].id == blockId then from = i break end
    end
    if not from then return end
    local b = table.remove(cfg.blocks, from)
    local to = newIndex or (from + 1)
    if to > from then to = to - 1 end
    if to < 1 then to = 1 end
    if to > #cfg.blocks + 1 then to = #cfg.blocks + 1 end
    table.insert(cfg.blocks, to, b)
    ns.ApplyBar(barId)
end

-- Divider commit: A gets newAWeight, B gets (frozen pair budget - A).
function ns.TransferPct(barId, aBlockId, bBlockId, newAWeight)
    local cfg = ns.GetBar(barId)
    local a = GetBlock(cfg, aBlockId)
    local b = GetBlock(cfg, bBlockId)
    if not (a and b) then return end
    local budget = (a.widthPct or 10) + (b.widthPct or 10)
    local w = newAWeight or (budget / 2)
    if w < 0 then w = 0 end
    if w > budget then w = budget end
    a.widthPct = w
    b.widthPct = budget - w
    ns.RequestLayout(barId)
end

-- Creates a bar from a template ("bottom"|"minimapc"|"microstrip"|"empty"),
-- applies it, registers its unlock element and selects it.
function ns.CreateBar(templateKey)
    local profile = ns.GetProfile()
    if not profile then return nil end
    local t = TEMPLATES[templateKey]
    if not t then t = TEMPLATES.empty end
    profile.nextBarId = (profile.nextBarId or 0) + 1
    local id = profile.nextBarId
    local sp = nil
    if t.savedPos then
        sp = { point = t.savedPos.point, relPoint = t.savedPos.relPoint, x = t.savedPos.x, y = t.savedPos.y }
    end
    local cfg = {
        id          = id,
        name        = UniqueBarName(t.name),
        enabled     = true,
        orientation = t.orientation,
        lengthMode  = t.lengthMode,
        length      = t.length,
        thickness   = t.thickness,
        snapEdge    = t.snapEdge,
        sizingMode  = t.sizingMode,
        fontScale   = 100,
        theme = {
            style       = t.theme,
            euiAlpha    = 0.5,
            modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 },
        },
        visibility  = "always",
        savedPos    = sp,
        nextBlockId = 0,
        blocks      = {},
    }
    profile.bars[#profile.bars + 1] = cfg
    -- Template block entries may carry per-block overrides beyond the
    -- seeded defaults (gaps, align, offsets, color, settings tweaks).
    for _, bt in ipairs(t.blocks) do
        local b = ns.AddBlock(id, bt.type)
        if b then
            for k, v in pairs(bt) do
                if k == "settings" then
                    for sk, sv in pairs(v) do b.settings[sk] = DeepCopy(sv) end
                elseif k ~= "type" then
                    b[k] = DeepCopy(v)
                end
            end
        end
    end
    -- Template-designated Fill Remaining block (first block of fillType);
    -- otherwise EnsureFillBlock heals to the last block on first solve.
    if t.fillType then
        for i = 1, #cfg.blocks do
            if cfg.blocks[i].type == t.fillType then
                cfg.fillBlockId = cfg.blocks[i].id
                break
            end
        end
    end
    -- Template-designated Force Centered block (first block of centerType).
    -- Center and fill are combinable, so the fill block is a legal pick.
    if t.centerType then
        for i = 1, #cfg.blocks do
            local tb = cfg.blocks[i]
            if tb.type == t.centerType then
                cfg.centerBlockId = tb.id
                break
            end
        end
    end
    profile.selectedBarId = id
    ns.ApplyBar(id)
    ns.RegisterAllUnlockElements()
    return cfg
end

-- Removes the bar's cfg and tears the runtime down. Does NOT confirm (the
-- options UI shows the confirmation popup). The unlock element stays
-- registered and goes dormant; the id is never reused.
function ns.DeleteBar(id)
    local profile = ns.GetProfile()
    if not profile then return end
    for i = 1, #profile.bars do
        if profile.bars[i].id == id then
            tremove(profile.bars, i)
            break
        end
    end
    local rec = live[id]
    if rec then
        for _, inst in pairs(rec.insts) do
            if inst.Disable then inst:Disable() end
            if inst.Destroy then inst:Destroy() end
        end
        wipe(rec.insts)
        rec.bar:Hide()
        rec.enabled = false
        live[id] = nil
    end
    ns._moEligible[id] = nil
    if profile.selectedBarId == id then profile.selectedBarId = nil end
    AfterBarStateChange()
end

function ns.RenameBar(id, name)
    local cfg = ns.GetBar(id)
    if not cfg then return end
    if type(name) ~= "string" then return end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    cfg.name = name
    -- Re-registration is a safe overwrite; it refreshes the mover label.
    ns.RegisterAllUnlockElements()
end

function ns.SetBarEnabled(id, on)
    local cfg = ns.GetBar(id)
    if not cfg then return end
    cfg.enabled = on and true or false
    ns.ApplyBar(id)
end

-------------------------------------------------------------------------------
--  Currency discovery (searchable picker source)
--  Expand collapsed headers, scan, restore in reverse order.
-------------------------------------------------------------------------------
function ns.BuildCurrencyList()
    local values, order = {}, {}
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then
        return values, order
    end
    local collapsed = {}
    local idx = 1
    while idx <= C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(idx)
        if info and info.isHeader and not info.isHeaderExpanded then
            collapsed[#collapsed + 1] = idx
            C_CurrencyInfo.ExpandCurrencyList(idx, true)
        end
        idx = idx + 1
    end
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and not info.isHeader then
            local link = C_CurrencyInfo.GetCurrencyListLink(i)
            local cID = nil
            if link then cID = C_CurrencyInfo.GetCurrencyIDFromLink(link) end
            if cID and not values[cID] then
                local cInfo = C_CurrencyInfo.GetCurrencyInfo(cID)
                local cName = info.name
                if cInfo and cInfo.name then cName = cInfo.name end
                if not cName then cName = tostring(cID) end
                values[cID] = cName
                order[#order + 1] = cID
            end
        end
    end
    for i = #collapsed, 1, -1 do
        C_CurrencyInfo.ExpandCurrencyList(collapsed[i], false)
    end
    return values, order
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function WB:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUIDataBarsDB", defaults)
end

function WB:OnEnable()
    local profile = ns.GetProfile()
    if not profile then return end
    for i = 1, #profile.bars do
        ns.ApplyBar(profile.bars[i].id)
    end
    -- Mid-combat /reload: lockdown has NOT re-engaged during this early
    -- login window (the same trick the suite uses to position elements
    -- during the load screen), but RequestLayout's next-frame timer fires
    -- AFTER it does -- the protected-bar gate would then freeze bars whose
    -- slots were never placed (field report: blank bar until regen). Lay
    -- out synchronously NOW while geometry is still legal; the queued
    -- pass coalesces into a harmless re-run.
    for i = 1, #profile.bars do
        ApplyLayout(profile.bars[i].id)
    end
    ns.RegisterAllUnlockElements()
    -- Zero-bars case: ApplyBar never ran, so recompute the gates once here.
    AfterBarStateChange()
end

function WB:OnDisable()
    local profile = ns.GetProfile()
    if not profile then return end
    for i = 1, #profile.bars do
        local rec = live[profile.bars[i].id]
        if rec and rec.enabled then
            for _, inst in pairs(rec.insts) do
                if inst.Disable then inst:Disable() end
            end
            rec.bar:Hide()
            rec.enabled = false
        end
    end
end

-------------------------------------------------------------------------------
--  Profile-swap apply hook. The profile system re-points db.profile in
--  place then calls this: retire live records whose bar ids do not exist in
--  the incoming profile (ApplyBar treats missing cfg as disable), build the
--  incoming set, re-register unlock movers, and re-sync every gate.
-------------------------------------------------------------------------------
_G._EDB_Apply = function()
    if not (WB.db and WB.db.profile) then return end
    if ns.WipeFitCache then ns.WipeFitCache() end
    for id in pairs(live) do
        ns.ApplyBar(id)
    end
    local profile = ns.GetProfile()
    for i = 1, #profile.bars do
        ns.ApplyBar(profile.bars[i].id)
    end
    ns.RegisterAllUnlockElements()
    AfterBarStateChange()
end

_G._EDB_RegisterUnlock = function()
    ns.RegisterAllUnlockElements()
end
