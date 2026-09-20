if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Style_Options.lua
--
--  Global Settings > Style: per-module choice between the EllesmereUI look
--  and a Blizzard-style look that keeps every EllesmereUI feature. Each row
--  is a write-through mirror of the module's own profile flag (Action Bars
--  mirrors its existing "Blizzard Style Action Bars" button; the other
--  modules carry a matching default-off flag). Every flag is reload-gated:
--  the value is written ONLY inside the reload popup's confirm handler, so a
--  cancelled popup leaves the profile untouched and the runtime never sees a
--  half-applied style mid-session. A set-all dropdown + Apply to All above
--  the rows pushes one style to every enabled module through the same single
--  prompt.
--
--  EllesmereUI.BlizzStyle is the shared helper set the module options pages
--  use to gate rows that only apply to the EllesmereUI look (Gate) and to
--  show the "Blizzard Style is active" banner (Note). Both are build-time
--  decisions: each module latches its style once per session (the flag it
--  read at load), so the rendered look cannot change without a reload. The
--  helpers read that latched value; the Style rows show the profile's flag.
-------------------------------------------------------------------------------

local GLOBAL_KEY     = "_EUIGlobal"
local PAGE_STYLE     = "Style"
local SECTION_STYLES = "MODULE STYLES"

local function NS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end

-------------------------------------------------------------------------------
--  Module registry: one entry per styleable surface. get/set read and write
--  the module's own per-profile flag and are nil-safe while the module is
--  disabled (get returns nil, set is a no-op).
-------------------------------------------------------------------------------

local function ABProfile()
    local ns = NS("EllesmereUIActionBars")
    local EAB = ns and ns.EAB
    return EAB and EAB.db and EAB.db.profile
end
local function UFProfile()
    local ns = NS("EllesmereUIUnitFrames")
    return ns and ns.db and ns.db.profile
end
local function PABProfile()
    local p = UFProfile()
    return p and p.playerAuraBars
end
local function NPProfile()
    local ns = NS("EllesmereUINameplates")
    return ns and ns.db and ns.db.profile
end
local function CDMProfile()
    local d = _G._ECME_AceDB
    return d and d.profile
end
local function CastBarProfile()
    local d = _G._ERB_AceDB
    return d and d.profile and d.profile.castBar
end
local function ERBProfile()
    local d = _G._ERB_AceDB
    return d and d.profile
end
local function MinimapProfile()
    local d = _G._EMM_DB
    return d and d.profile and d.profile.minimap
end
local function DMProfile()
    local d = _G._EDM_DB
    return d and d.profile and d.profile.dm
end

local function FlagAccessors(profileFn, key)
    return function()
        local p = profileFn()
        return p and p[key] and true or false
    end, function(on)
        local p = profileFn()
        if p then p[key] = on and true or false end
    end
end

-- The style a module is RENDERING this session: its latched getter on the
-- module ns (false while the module is not loaded). Action Bars has no latch
-- and passes its profile accessor instead.
local function ActiveFn(folder, fnName)
    return function()
        local n = NS(folder)
        local fn = n and n[fnName]
        return fn and fn() and true or false
    end
end

local MODULES = {}
local BY_KEY  = {}
-- onEnable (optional): runs on the profile the moment the style is switched
-- ON from this page (before the reload), for one-time seeding of settings
-- that only make sense under the style.
local function Register(key, folder, display, tooltip, profileFn, flag, activeFnName, onEnable)
    local get, set = FlagAccessors(profileFn, flag)
    local m = { key = key, folder = folder, display = display, tooltip = tooltip, get = get, set = set,
                active = activeFnName and ActiveFn(folder, activeFnName) or get,
                profile = profileFn, onEnable = onEnable }
    MODULES[#MODULES + 1] = m
    BY_KEY[key] = m
end

Register("actionbars",   "EllesmereUIActionBars",      "Action Bars",
    "Blizzard's rounded button art with every EllesmereUI bar feature.",
    ABProfile, "useBlizzardStyle")
Register("unitframes",   "EllesmereUIUnitFrames",      "Unit Frames",
    "Blizzard's frame art, portraits and bar shapes with every EllesmereUI frame feature.",
    UFProfile, "useBlizzardStyle", "UF_Blizz")
Register("playerauras",  "EllesmereUIUnitFrames",      "Player Aura Bars",
    "Blizzard's aura borders on the buffs, debuffs and weapon enchants, with every EllesmereUI bar feature.",
    PABProfile, "useBlizzardStyle", "PAB_Blizz")
Register("nameplates",   "EllesmereUINameplates",      "Nameplates",
    "Blizzard's health and cast bar art with every EllesmereUI nameplate feature.",
    NPProfile, "useBlizzardStyle", "NP_Blizz")
Register("cdmicons",     "EllesmereUICooldownManager", "Cooldown Manager Icons",
    "Blizzard's rounded cooldown icons with every EllesmereUI icon feature.",
    CDMProfile, "useBlizzardStyle", "CdmBlizzIcons")
Register("cdmbars",      "EllesmereUICooldownManager", "Tracked Buff Bars",
    "Blizzard's buff bar art with every EllesmereUI tracked bar feature.",
    CDMProfile, "useBlizzardStyleBars", "CdmBlizzBars")
Register("castbar",      "EllesmereUIResourceBars",    "Player Cast Bar",
    "Blizzard's cast bar art with every EllesmereUI cast bar feature.",
    CastBarProfile, "useBlizzardStyle", "ERB_CastBlizz")
Register("resourcebars", "EllesmereUIResourceBars",    "Resource Bars",
    "The personal resource display's bar frame on the health, power and class resource bars, with every EllesmereUI bar feature.",
    ERBProfile, "useBlizzardStyleBars", "ERB_BarsBlizz")
Register("minimap",      "EllesmereUIMinimap",         "Minimap",
    "Blizzard's round minimap and header with every EllesmereUI minimap feature.",
    MinimapProfile, "useBlizzardStyle", "MinimapBlizz")
Register("damagemeters", "EllesmereUIDamageMeters",    "Damage Meters",
    "Blizzard's meter window and bar art with every EllesmereUI meter feature.",
    DMProfile, "useBlizzardStyle", "DMBlizz",
    -- The stock panel reads best lighter: the first switch to the style seeds
    -- Background Opacity at 0.4 (once per profile; the slider stays the user's).
    function(p)
        if not p.blizzBgAlphaSeeded then
            p.blizzBgAlphaSeeded = true
            p.bgAlpha = 0.4
        end
    end)

-------------------------------------------------------------------------------
--  Shared helpers (EllesmereUI.BlizzStyle)
-------------------------------------------------------------------------------

local BlizzStyle = {}
EllesmereUI.BlizzStyle = BlizzStyle

-- True when the module currently RENDERS Blizzard Style (its session latch,
-- not the profile flag). False for unknown keys and for disabled modules.
function BlizzStyle.Get(key)
    local m = BY_KEY[key]
    return m and m.active() or false
end
-- Every loaded module to one style at once, no prompt: the first-install
-- style picker (EllesmereUI_StyleChoicePopup.lua) writes the flags and
-- reloads itself. The same writes as Apply to All's confirm; a module with
-- no profile (disabled at the picker) is left alone.
function BlizzStyle.ApplyAll(on)
    for i = 1, #MODULES do
        local m = MODULES[i]
        local p = m.profile()
        if p then
            m.set(on)
            if on and m.onEnable then m.onEnable(p) end
        end
    end
end

-- The rendered style never changes during a session, so gating a row is a
-- build-time decision: when Blizzard Style is active the row is disabled
-- with the standard requirement tooltip. Returns cfg for inline use.
function BlizzStyle.Gate(key, cfg, keepRow)
    if not cfg or not BlizzStyle.Get(key) then return cfg end
    cfg.disabled        = function() return true end
    cfg.disabledTooltip = "Blizzard Style"
    cfg.requireState    = "disabled"
    cfg.rawTooltip      = nil
    cfg._blizzGated     = true
    -- keepRow: an inline control hung on this slot (a cog) still works under
    -- the style, so the row must stay on the page even if fully gated.
    cfg._blizzKeepRow   = keepRow or nil
    return cfg
end

-- A slot's gate state: nil = blank (no control: nil, spacer, empty label),
-- true = gated for the active style (a multiSwatch counts when every swatch
-- is), false = a live control.
local function SlotGated(cfg)
    if not cfg then return nil end
    local t = cfg.type
    if t == "spacer" or (t == "label" and (cfg.text == nil or cfg.text == "")) then return nil end
    if cfg._blizzGated then return true end
    if t == "multiSwatch" and cfg.swatches then
        local n = #cfg.swatches
        for i = 1, n do
            if not cfg.swatches[i]._blizzGated then return false end
        end
        return n > 0
    end
    return false
end

-- A row whose every control is gated for the active style is not shown at
-- all: the widget factory builds it (callers still hang cogs and sync icons
-- on its regions) but hides it and gives it no height. Blank slots do not
-- count; one live control keeps the row, its gated neighbour disabled.
function BlizzStyle.RowHidden(a, b, c)
    if (a and a._blizzKeepRow) or (b and b._blizzKeepRow) or (c and c._blizzKeepRow) then return false end
    local ga, gb, gc = SlotGated(a), SlotGated(b), SlotGated(c)
    if ga == false or gb == false or gc == false then return false end
    return (ga or gb or gc) and true or false
end

-- Inline widget (swatch, cog) with no disabled state of its own: dims it and
-- blocks clicks with the standard requirement tooltip while Blizzard Style is
-- active for the module. No-op otherwise, so existing pages are untouched.
function BlizzStyle.BlockInline(key, widget, dimAlpha)
    if not widget or not BlizzStyle.Get(key) then return false end
    widget:SetAlpha(dimAlpha or 0.3)
    local block = CreateFrame("Frame", nil, widget)
    block:SetAllPoints()
    block:SetFrameLevel(widget:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:SetScript("OnEnter", function()
        EllesmereUI.ShowWidgetTooltip(widget, EllesmereUI.DisabledTooltip("Blizzard Style", "disabled"))
    end)
    block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    return true
end

-- Banner row under a section header: explains why rows are disabled and
-- links back to the Style page. Adds nothing (returns y unchanged) while
-- the module renders the EllesmereUI look, so existing pages are untouched.
function BlizzStyle.Note(parent, y, key)
    local m = BY_KEY[key]
    -- The latched rendering state, like Gate: a profile whose flag differs
    -- from the running look (reload declined) must not banner live rows.
    if not m or not m.active() then return y end
    local ROW_H = 40
    -- The search prebuild only indexes rows: same y advance, no frames.
    if EllesmereUI._prebuilding then return y - ROW_H end
    local PP = EllesmereUI.PanelPP
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    if EllesmereUI.RowBg then EllesmereUI.RowBg(row, parent) end

    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.6)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", -160, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(EllesmereUI.L("Blizzard Style is active. Settings that only apply to the EllesmereUI look are hidden."))

    local btn = CreateFrame("Button", nil, row)
    PP.Size(btn, 122, 26)
    btn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 2)
    local display = m.display
    EllesmereUI.MakeStyledButton(btn, "Open Style", 11, EllesmereUI.WB_COLOURS, function()
        EllesmereUI:NavigateToElementSettings(GLOBAL_KEY, PAGE_STYLE, SECTION_STYLES, nil, display)
    end)
    return y - ROW_H
end

-- Reload prompt: the flags are written only on confirm, right before the
-- reload, so cancelling (button, escape or click-outside) changes nothing.
-- `changes` lists { m = module, on = bool } pairs: one for a row's dropdown,
-- every differing module for Apply to All (one prompt for the batch).
local function PromptStyleChanges(changes)
    if #changes == 0 then return end
    EllesmereUI:ShowConfirmPopup({
        title       = "Reload Required",
        message     = "Changing the style requires a UI reload to apply.",
        confirmText = "Reload Now",
        cancelText  = "Cancel",
        reload      = true,
        onConfirm   = function()
            for i = 1, #changes do
                local m, on = changes[i].m, changes[i].on
                m.set(on)
                if on and m.onEnable then
                    local p = m.profile and m.profile()
                    if p then m.onEnable(p) end
                end
            end
        end,
    })
end
local function PromptStyleChange(m, on)
    if m.get() == on then return end
    PromptStyleChanges({ { m = m, on = on } })
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------

local STYLE_VALUES = { eui = "EllesmereUI Style", blizzard = "Blizzard Style" }
local STYLE_ORDER  = { "eui", "blizzard" }
local _styleApplyAll = "eui"  -- set-all dropdown pick (session-only)

local function StyleRowCfg(m)
    local loaded = NS(m.folder) ~= nil
    return {
        type = "dropdown", text = m.display, tooltip = m.tooltip,
        values = STYLE_VALUES, order = STYLE_ORDER,
        -- Reload-gated and per-profile: never captured into spec overrides.
        noCapture = true,
        getValue = function() return m.get() and "blizzard" or "eui" end,
        setValue = function(v) PromptStyleChange(m, v == "blizzard") end,
        disabled = function() return not loaded end,
        disabledTooltip = function()
            return EllesmereUI.Lf("Enable %1$s to change its style.", EllesmereUI.L(m.display))
        end,
        rawTooltip = true,
    }
end

function _G._EUI_BuildStylePage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Orientation note above the section title. Sized host + single TOPLEFT
    -- point per the search framework's geometry contract.
    local introHost = CreateFrame("Frame", nil, parent)
    PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 44)
    introHost:SetPoint("TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 20)
    local intro = EllesmereUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
    intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("CENTER")
    intro:SetWordWrap(true)
    intro:SetText(EllesmereUI.L("Choose the look of each module.") .. "\n"
        .. EllesmereUI.L("Blizzard Style keeps every EllesmereUI feature and setting; only the art changes. Changing a style reloads the UI."))
    y = y - 48

    -- Set-all row (as on the Window Skins page): pick a style, then push it
    -- to every enabled module below in ONE reload prompt. The pick is
    -- session-only; nothing is written until that prompt is confirmed. The
    -- search prebuild only needs the y advance.
    y = y - 12
    if not EllesmereUI._prebuilding then
        local allDD = EllesmereUI.BuildDropdownControl(parent, 170, parent:GetFrameLevel() + 3,
            STYLE_VALUES, STYLE_ORDER,
            function() return _styleApplyAll end,
            function(v)
                _styleApplyAll = v
                EllesmereUI:RefreshPage()
            end)
        PP.Point(allDD, "TOPLEFT", parent, "TOP", -115, y)
        allDD._ttText = "Style to apply to every module below."

        local applyBtn = CreateFrame("Button", nil, parent)
        PP.Size(applyBtn, 110, 30)
        PP.Point(applyBtn, "LEFT", allDD, "RIGHT", 10, 0)
        applyBtn:SetFrameLevel(parent:GetFrameLevel() + 3)
        EllesmereUI.MakeStyledButton(applyBtn, "Apply to All", 12, EllesmereUI.WB_COLOURS, function()
            local on = _styleApplyAll == "blizzard"
            local changes = {}
            for i = 1, #MODULES do
                local m = MODULES[i]
                -- Disabled modules have no profile to write; already-matching
                -- ones need no reload.
                if NS(m.folder) ~= nil and m.get() ~= on then
                    changes[#changes + 1] = { m = m, on = on }
                end
            end
            PromptStyleChanges(changes)
        end)
    end
    y = y - 30 - 26

    _, h = W:SectionHeader(parent, SECTION_STYLES, y);  y = y - h

    local i = 1
    while i <= #MODULES do
        local left = StyleRowCfg(MODULES[i])
        local rightM = MODULES[i + 1]
        local right = rightM and StyleRowCfg(rightM) or { type = "label", text = "" }
        _, h = W:DualRow(parent, y, left, right);  y = y - h
        i = i + 2
    end

    -- Framework contract: return the positive total content height.
    return math.abs(y)
end
