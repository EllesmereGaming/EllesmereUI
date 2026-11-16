-- Stub harness: the Nameplates options pages (EUI_Nameplates_Options.lua and
-- Nameplates_Options\): five tabs, Enemy, Enemy Colors, Target, Focus & Hover,
-- Friendly and Extras (the pages Display, Colors, Target, Focus & Hover, Friendly
-- Plates and General). The real files are loaded whole under stub
-- widgets that record what a page builds: the module registration from the main
-- file, the Target, Focus & Hover page, the Friendly Plates page with its sample
-- plates, and the General page (the Extras tab). The header of the Target, Focus
-- & Hover page is cut from NameplatePreview_Options.lua and built over a stand-in
-- for the preview's painter, which this harness does not run. The runtime's
-- defaults, effect getters and class colour CVar rule are cut from the module.
-- Checked on retail and on WoW Forever, in a live build and in the search
-- pre-build (the real absorber widgets, cut from EllesmereUI_GlobalSearch.lua):
--   the registration: pages, tab labels, dispatch, header builders, TOC and build list;
--   each page's sections and rows in order;
--   every control of the Target, Focus & Hover and Friendly Plates pages and three
--     rows of the Extras tab (Show Enemy Pet Nameplates and the two enemy scales):
--     the saved keys it reads and writes, what a write stores, calls and repaints,
--     and when it is greyed out, with which tooltip, over every combination of the
--     settings that gate it;
--   the saved keys these controls drive (DRIVER), each written by the controls
--     named there and by no other;
--   what the pages must not hold: Target Preview and Focus Preview rows, an eye on
--     Target Effect, a cog on Scale Target Nameplate, a header for a section name
--     that is a search word only;
--   the previews' wiring: the mode picker, which preview a write repaints, the
--     sample plates' repaint, and that nothing listens or ticks;
--   the Global Search words of the rows and sections;
--   the click navigation of the three header previews (the kit env.Nav of the
--     main file, the real overlay factory and hint dismissal cut from
--     EllesmereUI_Widgets.lua): which preview parts carry an overlay in each
--     state and form, the section a click scrolls to and the row half it
--     highlights, the hint line's rule on each header, and what a state pick, a
--     write, a rebuild, a cached page, the panel's show and the search pre-build
--     make (no second set of overlays anywhere). The Enemies preview and
--     its two section builders are stand-ins with every part the navigation
--     reads; the Target, Focus & Hover preview is a stand-in whose state parts
--     are made and painted by code cut from NameplatePreview_Options.lua.
--   saved override entries of the rows that left a page (the module's
--     movedSections, the real EUI_NS.EntryPage and tab label cut from
--     EllesmereUI_Panel.lua, the crumb from EUI_SpecOverrides_Session.lua, the
--     override list's row from EUI_SpecOverrides_ListPage.lua): every row the three
--     old sections held is on the page the list shows and Go to Setting opens, the
--     one row still on its page stays there, and no entry is written.
--   lua .tools/tests/test_np_options_pages.lua        (from the repository root)
local OPT = "EllesmereUIOptions/"
local NPO = OPT .. "Nameplates_Options/"
local RT = "EllesmereUINameplates/"
local FOLDER = "EllesmereUINameplates"

local function ReadSource(name)
    local f = io.open(name, "rb")
    if not f then return nil end
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 60 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
-- One part of the run: an error in it is a failed check, and the parts after it still run.
local function Part(name, fn)
    local ok, err = xpcall(fn, function(m) return debug.traceback(tostring(m), 2) end)
    if not ok then check(false, name .. " raised: " .. tostring(err):sub(1, 900)) end
end

-------------------------------------------------------------------------------
-- Recording frames. Every method exists; the ones the checks read keep state.
-------------------------------------------------------------------------------
local LOG          -- what the code under test did since the last reset (H.ResetLog)
local EVER = { events = {}, onUpdate = 0, tickers = 0, frames = 0, badOwner = 0 }  -- never reset
local M = {}
local FrameMeta = { __index = function(t, k)
    -- a texture or a font string makes no regions (an overlay over one hangs on its parent)
    if (k == "CreateTexture" or k == "CreateFontString") and (rawget(t, "_kind") == "Texture" or rawget(t, "_kind") == "FontString") then
        return nil
    end
    local m = M[k]
    if m then return m end
    if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
    return function() end
end }
local function Frame(kind, parent)
    EVER.frames = EVER.frames + 1
    return setmetatable({ _kind = kind, _parent = parent, _shown = true, _alpha = 1, _mouse = true,
        _scale = 1, _level = 1, _scripts = {}, _points = {} }, FrameMeta)
end
function M:Show() self._shown = true end
function M:Hide() self._shown = false end
function M:SetShown(v) self._shown = v and true or false end
function M:IsShown() return self._shown end
function M:IsVisible()
    local o = self
    while o do
        if not o._shown then return false end
        o = o._parent
    end
    return true
end
function M:SetAlpha(a) self._alpha = a end
function M:GetAlpha() return self._alpha end
function M:EnableMouse(v) self._mouse = v and true or false end
function M:SetMouseClickEnabled(v) self._mouse = v and true or false end
function M:SetScript(name, fn)
    self._scripts[name] = fn
    if name == "OnUpdate" and fn then EVER.onUpdate = EVER.onUpdate + 1 end
end
function M:GetScript(name) return self._scripts[name] end
function M:HookScript(name, fn)
    if name == "OnUpdate" then EVER.onUpdate = EVER.onUpdate + 1 end
end
function M:RegisterEvent(ev) EVER.events[#EVER.events + 1] = ev end
function M:RegisterUnitEvent(ev) EVER.events[#EVER.events + 1] = ev end
function M:SetFont(path, size, flags) self._font = { path, size, flags } end
function M:SetText(t)
    if self._kind == "FontString" then assert(self._font, "text set on a font string with no font") end
    self._text = t
end
function M:SetFormattedText(f, ...) self:SetText(f:format(...)) end
function M:GetText() return self._text end
function M:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
function M:SetParent(p) self._parent = p end
function M:GetParent() return self._parent end
function M:SetFrameLevel(l) self._level = l end
function M:GetFrameLevel() return self._level end
function M:SetScale(s) self._scale = s end
function M:GetScale() return self._scale end
function M:GetEffectiveScale() return self._scale * (self._parent and self._parent:GetEffectiveScale() or 1) end
function M:SetSize(w, h)
    self._w, self._h = w, h
    if self._logSize and LOG then LOG.calls[#LOG.calls + 1] = self._logSize .. "=" .. w .. "x" .. h end
end
function M:SetWidth(w) self._w = w end
function M:SetHeight(h) self._h = h end
function M:GetWidth() return self._w or 0 end
function M:GetHeight() return self._h or 0 end
function M:GetStringWidth() return 6 * #(self._text or "") end
function M:GetStringHeight() return self._font and self._font[2] or 0 end
function M:SetJustifyH(j) self._justify = j end
function M:SetWordWrap(v) self._wrap = v end
function M:SetMaxLines(n) self._maxLines = n end
function M:GetJustifyH() return self._justify end
function M:RegisterForClicks(...) self._clicks = table.concat({ ... }, ",") end
function M:SetPoint(point, rel, relPoint, x, y) self._points[#self._points + 1] = { point, rel, relPoint, x, y } end
-- SetAllPoints reads as one point, "ALL" on the frame it spans.
function M:SetAllPoints(rel) self._points = { { "ALL", rel or self._parent } } end
function M:ClearAllPoints() self._points = {} end
function M:GetPoint(i) local p = self._points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function M:CreateFontString()
    local fs = Frame("FontString", self)
    local made = rawget(self, "_fontStrings")
    if not made then made = {}; rawset(self, "_fontStrings", made) end
    made[#made + 1] = fs
    return fs
end
function M:CreateTexture()
    local tx = Frame("Texture", self)
    local made = rawget(self, "_textures")
    if not made then made = {}; rawset(self, "_textures", made) end
    made[#made + 1] = tx
    return tx
end
function M:SetTexture(tex) self._tex = tex end

-------------------------------------------------------------------------------
-- H: the harness. One world per client (the files read the client flag as they
-- load). A page is built on an empty profile; its controls are then read and
-- driven under each scenario (H.SetState).
-------------------------------------------------------------------------------
local H = { root = "" }   -- root: the tree the files are read from (the repository root)
-- The profile: one table for the whole run (the runtime getters keep it as their
-- alias), every read and write traced, its content swapped per scenario.
local STORE, READS, WRITES = {}, {}, {}
local PROFILE = setmetatable({}, {
    __index = function(_, k) READS[k] = true; return STORE[k] end,
    __newindex = function(_, k, v)
        STORE[k] = v
        WRITES[#WRITES + 1] = k
    end,
})
local STYLE = { active = "eui", forever = false }
local function CopyState(src)
    local t = {}
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            local c = {}
            for a, b in pairs(v) do c[a] = b end
            v = c
        end
        t[k] = v
    end
    return t
end
-- A scenario: the saved settings (unset keys read their defaults) and the style.
function H.SetState(state, style)
    STORE = CopyState(state)
    STYLE.active = style and style.active or "eui"
    STYLE.forever = style and style.forever or false
end
function H.ResetLog()
    LOG = { calls = {}, cvars = {}, refresh = 0, rebuild = 0, popups = {}, timers = {}, after = {}, fpv = 0 }
    READS, WRITES = {}, {}
end
H.ResetLog()

local function Rec(name) return function() LOG.calls[#LOG.calls + 1] = name end end

-- A value as the signatures print it.
local function Val(v)
    local t = type(v)
    if t == "number" then
        local s = ("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")
        return s
    elseif t == "string" then
        return '"' .. v .. '"'
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. Val(v[k]) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return tostring(v)
end
local function Vals(...)
    local n, out = select("#", ...), {}
    for i = 1, n do out[i] = Val((select(i, ...))) end
    return table.concat(out, ",")
end

-- The search index: the first entry of a label on a page stays, as in
-- EllesmereUI._RegisterSearchEntry.
local INDEX
local function RegisterSearch(label, labelLoc, tooltip, folder, page, section, setter, key, isSection)
    if label then label = label:match("^%s*(.-)%s*$") end
    if not label or label == "" or not folder or not page then return end
    local p = INDEX[page]
    if not p then p = { order = {}, by = {} }; INDEX[page] = p end
    if p.by[label] then return end
    if type(tooltip) ~= "string" or tooltip == "" then tooltip = nil end
    p.by[label] = { label = label, tip = tooltip, section = section, isSection = isSection, folder = folder }
    p.order[#p.order + 1] = label
end

-- The page being built: what the recording widgets and builders saw.
local PAGE
local function NewPage(name, prebuild)
    return { name = name, prebuild = prebuild, items = {}, headers = {}, rows = {}, cogs = {}, inline = {},
        swatches = {}, checks = {}, refreshers = {}, spacers = 0, header = nil, cleared = 0, dropdowns = {},
        syncs = 0, cogStates = 0, made = {}, sections = {}, noteRows = {} }
end
local function Region(cfg, row)
    local r = Frame("Region", row)
    r._cfg = cfg
    r._control = Frame("Control", r)
    r._stockControl = r._control   -- (the row's own control, which a checklist takes the place of)
    r._label = Frame("Label", r)
    r._label._text = cfg and cfg.text or ""
    r._nSwatch = 0
    return r
end
local W = {}
function W:SectionHeader(parent, text, y, tooltip)
    PAGE.headers[#PAGE.headers + 1] = text
    PAGE.items[#PAGE.items + 1] = "# " .. tostring(text)
    PAGE.section = text
    local f = Frame("SectionHeader", parent)
    f._sectionName = text
    -- placed at its y, as the real header (the click navigation scrolls by it)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    PAGE.sections[text] = f
    parent._currentSection = f
    RegisterSearch(text, nil, nil, EllesmereUI._buildingModule, EllesmereUI._buildingPage, text, nil, nil, true)
    return f, 40
end
function W:DualRow(parent, y, l, r)
    check(type(l) == "table" and type(r) == "table", PAGE.name .. ": a DualRow half is not a table (a single widget's other half is BlankRowCfg())")
    l, r = type(l) == "table" and l or {}, type(r) == "table" and r or {}
    local row = Frame("Row", parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row._leftRegion, row._rightRegion = Region(l, row), Region(r, row)
    local sec = parent._currentSection and parent._currentSection._sectionName
    for _, c in ipairs({ l, r }) do
        RegisterSearch(c.text, nil, c.tooltip, EllesmereUI._buildingModule, EllesmereUI._buildingPage, sec)
    end
    PAGE.rows[#PAGE.rows + 1] = { l = l, r = r, section = PAGE.section, row = row }
    local function T(c) return (c.text == nil or c.text == "") and "blank" or c.text end
    PAGE.items[#PAGE.items + 1] = T(l) .. " | " .. T(r)
    return row, 50
end
function W:Spacer(parent, y, height)
    PAGE.spacers = PAGE.spacers + 1
    return Frame("Spacer", parent), height or 20
end

-- The module namespace: an unknown name raises (a name the page files read
-- must be one the runtime gives), except its own state fields.
local nsData = {}
local ns = setmetatable({}, {
    __index = function(_, k)
        local v = nsData[k]
        if v == nil and not (type(k) == "string" and k:sub(1, 1) == "_") then
            error("the stub ns has no " .. tostring(k), 2)
        end
        return v
    end,
    __newindex = function(_, k, v) nsData[k] = v end,
})

-- EllesmereUI: an unknown name raises too.
local EUI = {}
local EUI_OPTIONAL = { _mainFrame = true, _presetState = true, _scrollFrame = true, _sliderDragging = true,
    ApplyPandemicGlowToAll = true, IsPandemicGlowSyncedToAll = true, PandemicPayloadFromNameplate = true,
    _buildingModule = true, _buildingPage = true, _buildingSelector = true, _prebuilding = true, _panelCollapsed = true }

-- The tooltip a greyed control shows, resolved as EllesmereUI.ResolveDisabledTip
-- resolves it: "raw:" as written, "req:" wrapped, "req-off:" wrapped the other way.
local function Tip(cfg)
    local tt = cfg.disabledTooltip
    if type(tt) == "function" then tt = tt() end
    if tt == nil then return "notip" end
    local raw = cfg.rawTooltip
    if type(raw) == "function" then raw = raw() end
    if raw then return "raw:" .. tt end
    local state = cfg.requireState
    if type(state) == "function" then state = state() end
    return "req" .. (state == "disabled" and "-off" or "") .. ":" .. tt
end

-- The real code of NameplatePreview_Options.lua the stand-in preview runs (see
-- FakePreview in H.NewWorld): the effect's border (previewGlow.fxBorder), the
-- block that makes and paints a state's parts (if mode then ... previewGlow.state),
-- the parts' table the Target, Focus & Hover page's overlays sit on with the
-- effect's edge test (pf._fxEdge), the border flag, the hash line and the end of a
-- repaint (the header's height with the click hint, the text overlays, the page's
-- overlay sync). Returns Bind(pf, parent, mode, parts...) -> Paint(self), Tail(self).
function H.PreviewCuts(pvns, newFrame, setFont)
    local src = assert(ReadSource(H.root .. NPO .. "NameplatePreview_Options.lua"), "NameplatePreview_Options.lua")
    local function Part(first, last, what) return Cut(src, first, last, what) .. "\n" end
    local body = "local ns, EllesmereUI, CreateFrame, PP, DBVal, DB, defaults, SetPVFont = ...\n"
        .. "return function(pf, parent, mode, health, healthWrapper, healthTextFrame, previewGlow, nameFS, lvlText, hpNumber, hpText, previewHashLine)\n"
        .. "local previewScale, parentW, localParentW, _cachedRawBarW = 1, 1030, 1030, nil\n"
        .. Part("    previewGlow.fxBorder = function(m)\n", "\n    if mode then\n        -- Scale Target Nameplate", "the effect's border")
        .. Part("    if mode then\n        -- Scale Target Nameplate", "\n\n    -------------------------------------------------------------------\n    --  Update re-reads DB", "the state's parts and painter")
        .. Part("    -- The parts of a state the Target, Focus & Hover page's click overlays sit on\n", "\n\n    -- Each page's header keeps its own preview", "the parts' table")
        .. "local function Paint(self)\nlocal barW = 150\n"
        -- (the arrows: the line "local showArrows = ..." the source checks pin, and its if)
        .. "local showArrows = self._mode == \"target\" and DBVal(\"showTargetArrows\") == true\n"
        .. "pf._arrows.left:SetShown(showArrows); pf._arrows.right:SetShown(showArrows)\n"
        .. Part("        local customOn = DBVal(\"customBorderEnabled\")\n", "\n        local pcb = healthWrapper._customBorder", "the custom border flag")
        .. Part("        local borderVisible\n        if customOn then\n", "\n        local wrapActive = wrapOn and borderVisible", "the border flag")
        .. Part("        local hlEnabled = self._mode == \"target\" and DBVal(\"hashLineEnabled\")\n", "\n\n        -- Preview bar texture", "the hash line")
        .. "if self._mode then previewGlow.state(self._mode, \"font.ttf\", \"OUTLINE\") end\nend\n"
        .. "local function Tail(self)\nlocal totalH = self._standInH or 60\n"
        .. Part("        if self:IsVisible() then\n            local headerExtra = pf._headerExtra or 0\n", "\n    end\n\n    -- Expose preview elements for click-navigation hit overlays", "the end of a repaint")
        .. "end\nreturn Paint, Tail\nend\n"
    local factory = assert(loadstring(body, "=NameplatePreview_Options.lua"))
    return factory(pvns, EllesmereUI, newFrame, EllesmereUI.PanelPP, nsData._NPO_OptEnv.DBVal, nsData._NPO_OptEnv.DB,
        nsData.defaults, setFont)
end

-- Builds the stubs of one client and loads the files.
function H.NewWorld(forever)
    local root = H.root
    local Wd = { forever = forever, onShow = {}, sites = {}, previews = {}, loadErrors = {}, notes = {}, events = {},
        rootless = {}, snaps = 0, display = {}, created = {},
        -- the click navigation: every overlay the factory made (and the frames it made
        -- for them), the glows made and played, the scrolls, the hint dismissals and
        -- their fades (the shared helper's ticker, run by H.RunFades)
        nav = { ovs = {}, frames = 0, glowsMade = 0, glowOpts = {}, glows = {}, scrolls = {}, dismiss = {}, fades = {} } }
    local events0 = #EVER.events
    INDEX = {}
    H.SetState({})
    H.ResetLog()
    for k in pairs(nsData) do nsData[k] = nil end
    for k in pairs(EUI) do EUI[k] = nil end

    -- client globals
    EUI_CLIENT_BLOCKED = nil
    EllesmereUIDB = {}
    SlashCmdList = {}
    CreateFrame = function(kind, _, parent)
        if PAGE then PAGE.made[kind] = (PAGE.made[kind] or 0) + 1 end
        local f = Frame(kind, parent)
        Wd.created[#Wd.created + 1] = f
        -- made with no parent: the sample plates are among these
        if not parent then Wd.rootless[#Wd.rootless + 1] = f end
        return f
    end
    UIParent = Frame("UIParent")
    IsLoggedIn = function() return true end
    InCombatLockdown = function() return false end
    GetCVar = function() return "1" end
    GetCVarDefault = function(name) return "def:" .. name end
    C_CVar = { GetCVarInfo = function() return true end, GetCVarDefault = function() return "1" end }
    C_Timer = {
        After = function(delay, fn) LOG.after[#LOG.after + 1] = fn; Wd.lastAfter = delay end,
        NewTimer = function(sec, fn)
            local t = { sec = sec, fn = fn }
            function t:Cancel() self.cancelled = true end
            LOG.timers[#LOG.timers + 1] = t
            return t
        end,
        NewTicker = function() EVER.tickers = EVER.tickers + 1; return { Cancel = function() end } end,
    }
    UnitClass = function() return Wd.class or "Mage", Wd.classFile or "MAGE" end
    -- your character: Ellesmere Stormrage the Patient, unless a check sets another
    -- (Wd.unitName = { first, second }; Wd.pvpName = a string, or false for none)
    UnitName = function()
        if Wd.unitName then return Wd.unitName[1], Wd.unitName[2] end
        return "Ellesmere", "Stormrage"
    end
    UnitPVPName = function()
        if Wd.pvpName ~= nil then return Wd.pvpName or nil end
        return "Ellesmere the Patient"
    end
    GetGuildInfo = function() return "Knights of Ellesmere" end
    C_ClassColor = { GetClassColor = function() return { r = 0.25, g = 0.78, b = 0.92 } end }
    C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return Wd.specID or 62 end }
    C_Spell = { GetSpellInfo = function() return { iconID = 1 } end }
    SetRaidTargetIconTexture = function() end

    -- the runtime pieces
    local RUNTIME = assert(ReadSource(RT .. "EllesmereUINameplates.lua"), "the module's main file")
    local defaults = assert(loadstring("local EllesmereUI = ...\n" ..
        Cut(RUNTIME, "local defaults = {\n", "\n}\n", "the defaults table") .. "\n}\nreturn defaults", "=defaults"))({ IS_FOREVER = forever })
    local plate = setmetatable({ leftArrow = Frame("Arrow"), rightArrow = Frame("Arrow") },
        { __index = function(_, k) return Rec("plate:" .. k) end })
    plate.leftArrow._logSize, plate.rightArrow._logSize = "leftArrow", "rightArrow"
    local fplate = setmetatable({}, { __index = function(_, k) return Rec("fplate:" .. k) end })
    local N = nsData
    N.defaults, N.db, N.plates, N.friendlyPlates, N.BAR_W = defaults, { profile = PROFILE }, { plate }, { fplate }, 150
    N.textSlotKeys = { "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
        "textSlotBottomLeft", "textSlotBottomRight", "textSlotTopLeft", "textSlotTopRight" }
    N.NP_GetQuestTextSlot = function(db) return db.questTextSlot or "none" end
    N.healthBarTextureNames = { none = "None", smooth = "Smooth" }
    N.healthBarTextureOrder = { "none", "---", "smooth" }
    N.healthBarTextures = { smooth = "tex/smooth" }
    N.TARGET_ARROW_ORDER = { "simple", "double" }
    N.TARGET_ARROW_STYLES = { simple = { label = "Simple", l = "al", r = "ar", w = 11 }, double = { label = "Double", l = "al2", r = "ar2", w = 22 } }
    N.TARGET_ARROW_DIR = "arrows/"
    N.OVERLAY_STRIPE_KEYS = { ["striped-v2"] = true }
    N.NP_GLOW_VIEW, N.NP_CAST_ART_STYLE = {}, 4
    N.NP_PANDEMIC_NONE = forever
    N.NP_Forever = function() return STYLE.forever end
    N.SetFSFont = function(fs, size, flags) fs._font = { "fs", size, flags } end
    N.GetNPOutline = function() return "OUTLINE" end
    N.GetNPUseShadow = function() return false end
    N.GetFont = function() return "font.ttf" end
    N.GetEnemyNameTextSize = function() return 12 end
    N.GetDebuffTextColor = function() return 1, 1, 1 end
    N.IsCustomBorderEnabled = function() return PROFILE.customBorderEnabled == true end
    N.IsBorderEnabled = function() return true end
    N.GetBorderColor = function() return 0, 0, 0 end
    N.NP_BorderSize = function() return 1 end
    N.GetFriendlyHealthBarWidth = function() return PROFILE.friendlyHealthBarWidth or defaults.friendlyHealthBarWidth end
    N.GetFriendlyHealthBarHeight = function() return PROFILE.friendlyHealthBarHeight or defaults.friendlyHealthBarHeight end
    N.GetRaidMarkerPos = function() return PROFILE.raidMarkerPos or defaults.raidMarkerPos end
    N.GetRaidMarkerSize = function() return 24 end
    N.GetUnitLevelText = function() return "80" end
    N.NP_PaintFriendlyColors = function(s) s._painted = (s._painted or 0) + 1 end
    for _, name in ipairs({ "RefreshAllSettings", "NPC_ReloadAll", "ApplyHealthBarTexture", "ApplyCastBarTexture",
        "NT_RefreshSetting", "RangeText_Apply", "RangeText_Refresh", "RefreshHoverEffect", "ForceFriendlyPlayerCVarsOn",
        "NP_SyncFriendlyNameFormat", "RefreshAllNPCOverlays", "RefreshFriendlyBelowName", "RefreshFriendlyColors",
        "RefreshFriendlyHealthText", "RefreshFriendlyNameOnlyOffset", "RefreshFriendlyNameSize",
        "RefreshFriendlyNameTextSize", "RefreshFriendlyPlateSize", "RefreshFriendlyPlateYOffset",
        "RefreshNPCOverlayStyle", "RefreshStackingMotion", "UpdateFriendlyClickThrough",
        "UpdateFriendlyNameplateSystem", "ApplyOOCPlates", "KeepNameplateCVar", "NP_RefreshTypeScaleSetting",
        "RefreshHitboxSize", "RefreshStackingBounds", "SetHitboxOverlayShown", "NP_CastTintsDirty" }) do
        N[name] = Rec(name)
    end
    assert(loadstring("local ns, p, defaults = ...\n" ..
        Cut(assert(ReadSource(RT .. "EUI_Nameplates_Layout.lua"), "the layout file"),
            "local function GetTargetGlowStyle()", "local function GetShowTargetGlow()", "the effect getters"),
        "=EUI_Nameplates_Layout.lua"))(ns, PROFILE, defaults)
    assert(loadstring("local ns = ...\n" ..
        Cut(assert(ReadSource(RT .. "EUI_Nameplates_CastState.lua"), "the cast state file"),
            "function ns.FriendlyNameClass(db, nameOnly)", "\nlocal function SetupAuraCVars()", "the name colour rule and its CVar"),
        "=EUI_Nameplates_CastState.lua"))(ns)
    -- the runtime's own placer of the health percent text (the samples share it)
    assert(loadstring("local ns = ...\n" ..
        Cut(assert(ReadSource(RT .. "EllesmereUINameplatesFriendly.lua"), "the friendly runtime"),
            "local HP_TEXT_SIDE = {", "\n-- A plate's own text, placed again", "the health percent's placer"),
        "=EllesmereUINameplatesFriendly.lua"))(ns)
    -- The builders this harness does not load: stand-ins that record their call. The
    -- Display page's two hand back named section headers (placed at their y; one
    -- with no point while Wd.noClassHeaderPoint) and rows (each half a region; a few
    -- rows lack a half, so every branch of the navigation's half lookup runs), kept
    -- in Wd.display by name for the click navigation's checks.
    local function DHeader(parent, name, y)
        local f = Frame("SectionHeader", parent)
        f._name = name
        if y then f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y) end
        Wd.display[name] = f
        return f
    end
    local function DRow(parent, name, halves)
        local r = Frame("Row", parent)
        r._name = name
        if halves == "both" or halves == "left" then r._leftRegion = Frame("Region", r); r._leftRegion._name = name .. ".L" end
        if halves == "both" or halves == "right" then r._rightRegion = Frame("Region", r); r._rightRegion._name = name .. ".R" end
        Wd.display[name] = r
        return r
    end
    N.NPO_BuildDisplayLayout = function(parent, y, ctx)
        LOG.calls[#LOG.calls + 1] = "DisplayLayout"
        Wd.displayCtx, Wd.displayParent = ctx, parent
        local style, core = DHeader(parent, "STYLE", -140), DHeader(parent, "CORE POSITIONS", -380)
        local row1, row2, row3 = DRow(parent, "coreRow1", "both"), DRow(parent, "coreRow2", "both"), DRow(parent, "coreRow3", "right")
        local coreText = DHeader(parent, "CORE TEXT POSITIONS", -720)
        local textFirst = DRow(parent, "textFirstRow", "both")
        local tr1, tr2 = DRow(parent, "textRow1", "both"), DRow(parent, "textRow2", "both")
        local cells = {
            textSlotTop = { row = tr1, side = "_leftRegion" }, textSlotRight = { row = tr1, side = "_rightRegion" },
            textSlotLeft = { row = tr2, side = "_leftRegion" }, textSlotCenter = { row = tr2, side = "_rightRegion" },
            textSlotBottomLeft = { row = DRow(parent, "textRow3", "none"), side = "_rightRegion" },
        }
        ctx.corePosToRegion = {
            top = { row1, "_leftRegion" }, left = { row1, "_rightRegion" }, right = { row2, "_leftRegion" },
            topleft = { row2, "_rightRegion" }, topright = { row3, "_leftRegion" }, bottom = { row3, "_rightRegion" },
        }
        if Wd.displayStockRows then
            parent._classicPlateRow = DRow(parent, "classicPlateRow", "both")
            parent._foreverBoxRow = DRow(parent, "foreverBoxRow", "right")
        end
        return y, style, core, row1, row2, row3, coreText, cells, textFirst, function() end, function() end
    end
    N.NPO_BuildDisplayBars = function(parent, y, ctx)
        LOG.calls[#LOG.calls + 1] = "DisplayBars"
        check(ctx == Wd.displayCtx and parent == Wd.displayParent, "the Display page hands its two builders different parents or contexts")
        local hb = DHeader(parent, "HEALTH BAR", -1040)
        local hbRow, castRow, iconRow, timerRow = DRow(parent, "healthBarHeightRow", "both"), DRow(parent, "castBarHeightRow", "right"),
            DRow(parent, "showCastIconRow", "both"), DRow(parent, "castTimerRow", "left")
        local cr = DHeader(parent, "CLASS RESOURCE", not Wd.noClassHeaderPoint and -1500 or nil)
        local crRow = DRow(parent, "classResourceSection", "none")
        local gt = DHeader(parent, "TEXT", -1880)
        return y, hb, hbRow, castRow, iconRow, timerRow, cr, crRow, gt,
            DRow(parent, "auraDurPosRow", "both"), DRow(parent, "auraTimerStackRow", "both"), DRow(parent, "spellNameRow", "both")
    end
    N.NPO_BuildColorsPage = function(pageName) LOG.calls[#LOG.calls + 1] = "ColorsPage"; return 123 end
    -- The preview's painter: a stand-in, kept as the real one keeps itself, that counts
    -- its repaints. It carries every part the click navigation reads, under the real
    -- preview's names: the Enemies parts (Wd.pvVariant: "barPips", "noPips",
    -- "noFaction") and, in a state (mode), the state's parts, made, painted and handed
    -- out by the real code (H.PreviewCuts) as the repaint's end is.
    local function FakePreview(parent, w, mode)
        local pf = Frame("Preview", parent)
        pf._updates = 0
        local function El(kind, owner, shown, level)
            local e = Frame(kind, owner or pf)
            e._shown = shown ~= false
            if level then e:SetFrameLevel(level) end
            if kind == "FontString" then e:SetFont("fs", 10) end
            return e
        end
        local health = El("StatusBar", pf, true, pf:GetFrameLevel() + 10)
        local healthWrapper = El("Frame")
        local cast = El("StatusBar", El("Frame"), true, pf:GetFrameLevel() + 12)
        pf._health, pf._healthWrapper, pf._cast = health, healthWrapper, cast
        pf._arrows = { left = El("Texture", pf, false), right = El("Texture", pf, false) }
        local variant = Wd.pvVariant
        local function Aura(dur, stack)
            local a = El("Frame", pf, true, health:GetFrameLevel() + 9)
            a.durationText = dur and El("FontString", a) or false
            a.stackText = stack and El("FontString", a) or false
            return a
        end
        pf._ccs, pf._buffs, pf._debuffs = { Aura(true), Aura(true) }, { Aura(true) }, { Aura(true, true), Aura(true), Aura() }
        pf._castIconFrame = El("Frame", cast:GetParent())
        pf._castNameFS, pf._castTargetFS, pf._castTimerFS = El("FontString", cast), El("FontString", cast, false), El("FontString", cast)
        pf._nameFS, pf._hpText, pf._hpNumber = El("FontString", health), El("FontString", health), El("FontString", health)
        pf._lvlText, pf._totFS = El("FontString", health, false), El("FontString", health)
        pf._customFS = { textSlotTop = El("FontString", health), textSlotRight = El("FontString", health, false) }
        pf._classicLevel, pf._fvLevelBox = El("FontString", health), El("Frame", health)
        pf._raidFrame, pf._classIcon, pf._factionIcon = El("Frame"), El("Texture"), El("Texture", pf, variant ~= "noFaction")
        pf._questTextFrame = El("Frame")
        if variant ~= "noPips" then
            local bar = variant == "barPips"
            pf._cpPips = { El("Frame", pf, not bar), El("Frame", pf, not bar), El("Frame", pf, false) }
            pf._cpBar, pf._cpMax = El("StatusBar", pf, bar), 3
        end
        -- the state's own parts and the real code over them
        local previewGlow = { extend = 6, frame = El("Frame", pf, false, pf:GetFrameLevel() + 1), texs = {},
            highlight = El("Texture", health, false), classic = EllesmereUI.BlizzStyle.Active("nameplates") == "classic" }
        local hashLine = El("Texture", health, false)
        local Paint, Tail = Wd.pvBind(pf, parent, mode, health, healthWrapper, El("Frame", health), previewGlow,
            pf._nameFS, pf._lvlText, pf._hpNumber, pf._hpText, hashLine)
        -- each part named by what it is (the checks' lists and messages)
        local function Tag(e, name) if e then e._part = name end end
        for i, a in ipairs(pf._ccs) do Tag(a, "cc" .. i); Tag(a.durationText, "cc" .. i .. ".dur") end
        for i, a in ipairs(pf._buffs) do Tag(a, "buff" .. i); Tag(a.durationText, "buff" .. i .. ".dur") end
        for i, a in ipairs(pf._debuffs) do
            Tag(a, "debuff" .. i); Tag(a.durationText, "debuff" .. i .. ".dur"); Tag(a.stackText, "debuff" .. i .. ".stack")
        end
        for k, e in pairs({ health = health, healthWrapper = healthWrapper, cast = cast, arrowL = pf._arrows.left,
            arrowR = pf._arrows.right, castIcon = pf._castIconFrame, castName = pf._castNameFS, castTarget = pf._castTargetFS,
            castTimer = pf._castTimerFS, name = pf._nameFS, hpText = pf._hpText, hpNumber = pf._hpNumber, lvlText = pf._lvlText,
            tot = pf._totFS, customTop = pf._customFS.textSlotTop, customRight = pf._customFS.textSlotRight,
            classicLevel = pf._classicLevel, fvLevelBox = pf._fvLevelBox, raid = pf._raidFrame, classIcon = pf._classIcon,
            faction = pf._factionIcon, questText = pf._questTextFrame, cpBar = pf._cpBar or false,
            hash = hashLine, wash = previewGlow.highlight, texture = previewGlow.ovFill or false, glow = previewGlow.frame,
            letter = previewGlow.focusLetter or false, range = previewGlow.rangeText or false }) do
            Tag(e, k)
        end
        for i, p in ipairs(pf._cpPips or {}) do Tag(p, "pip" .. i) end
        pf.Update = function(self)
            self._updates = self._updates + 1
            Paint(self)
            Tail(self)
        end
        pf._mode = mode
        N._NPO_OptEnv.optState[mode and "tfhPreview" or "activePreview"] = pf
        Wd.previews[#Wd.previews + 1] = { parent = parent, w = w, mode = mode, pf = pf, glow = previewGlow, hash = hashLine }
        pf:Update()
        return 60
    end
    N.NPO_BuildNameplatePreview = FakePreview

    -- EllesmereUI
    local E = EUI
    E._ModuleNS = { [FOLDER] = ns }
    -- The page pool: a frame's generation is its _gen (set by a check that dresses a
    -- row again); a kept frame is marked.
    E._Pool = { CreateFrame = CreateFrame, Gen = function(o) return type(o) == "table" and rawget(o, "_gen") or nil end,
        Keep = function(x) if type(x) == "table" then x._kept = true end; return x end }
    E.L = function(s)
        if s == "Friendly NPC" then Wd.npcPaints = (Wd.npcPaints or 0) + 1 end
        return s
    end
    E.Lf = function(fmt, ...) return fmt:format(...) end
    E.IS_FOREVER = forever
    E._prebuilding = false
    E.Widgets = W
    E.PanelPP = {
        Point = function(f, point, rel, relPoint, x, y)
            if getmetatable(f) == FrameMeta then f._anchor = rel end
            f:SetPoint(point, rel, relPoint, x, y)
        end,
        Size = function(f, w, h) f:SetSize(w, h) end,
        Scale = function(v) return v end,
    }
    -- PP.SnapForES: whole physical pixels at the given effective scale (one pixel per unit at scale 1 here)
    E.PP = { perfect = 1, SnapForES = function(x, es)
        Wd.snaps, Wd.snapES = Wd.snaps + 1, es
        return math.floor(x * es + 0.5) / es
    end }
    -- a border frame (the overlays' hover borders)
    E.PP.CreateBorder = function(f, r, g, b, a, size)
        local brd = Frame("Border", f)
        brd._color, brd._size = { r, g, b, a }, size
        return brd
    end
    E.BlizzStyle = {
        Get = function() return STYLE.active ~= "eui" end,
        Active = function() return STYLE.active end,
        Forever = function() return STYLE.forever end,
        Label = function() return STYLE.forever and "WoW Forever" or (STYLE.active == "classic" and "Classic WoW UI" or "Blizzard Style") end,
        Gate = function(_, cfg) return cfg end,
    }
    E.GetFontOutlineFlag = function() return "OUTLINE" end
    E.EXPRESSWAY = "expressway.ttf"
    E.EnKey = function(s) return s end
    E.ELLESMERE_GREEN = { r = 0, g = 1, b = 0 }
    E.EYE_VISIBLE_ICON, E.EYE_INVISIBLE_ICON = "eye", "noeye"
    E.SetGlyphAlpha = function(btn, a) btn._glyphA = a end
    E.DisabledTooltip = function(s) return "requires " .. tostring(s) end
    E.AppendSharedMediaTextures = function() end
    E.ShowWidgetTooltip = function(_, text) LOG.tip = text end
    E.HideWidgetTooltip = function() end
    E.BlankRowCfg = function() return { type = "label", text = "" } end
    E.Range_GetAttackCutoff = function() return 30 end
    -- The click navigation's shared helpers: the glow (each one made is numbered, and
    -- each play is recorded with its target), the scroll and its frame; the overlay
    -- factory and the hint's dismissal are the real ones (below).
    E.MakeSettingGlow = function(opts)
        local nav = Wd.nav
        nav.glowsMade = nav.glowsMade + 1
        local id = nav.glowsMade
        nav.glowOpts[id] = opts
        return function(target, holdWhile) nav.glows[#nav.glows + 1] = { id = id, target = target, hold = holdWhile } end
    end
    E.SmoothScrollTo = function(pos) Wd.nav.scrolls[#Wd.nav.scrolls + 1] = pos end
    E._scrollFrame = Frame("ScrollFrame")
    E.MakeFont = function(parent, size, flags, r, g, b, a)
        local fs = parent:CreateFontString()
        fs._font, fs._color = { "make", size }, { r, g, b, a }
        Wd.notes[#Wd.notes + 1] = fs
        return fs
    end
    E.SetCVar = function(name, value, owner)
        LOG.cvars[#LOG.cvars + 1] = name .. "=" .. tostring(value)
        if owner ~= FOLDER then EVER.badOwner = EVER.badOwner + 1 end
    end
    E._RegisterSearchEntry = RegisterSearch
    E.RegisterWidgetRefresh = function(fn) if PAGE then PAGE.refreshers[#PAGE.refreshers + 1] = fn end end
    function E:RefreshPage(force)
        LOG.refresh = LOG.refresh + 1
        if force == true then LOG.rebuild = LOG.rebuild + 1 end
    end
    function E:RegisterOnShow(fn) Wd.onShow[#Wd.onShow + 1] = fn end
    function E:RegisterModule(folder, cfg) Wd.folder, Wd.cfg = folder, cfg end
    function E:SetContentHeader(builder)
        check(type(builder) == "function", PAGE.name .. ": SetContentHeader without a builder")
        local hdr = Frame("Header")
        hdr._scale, hdr._h = 0.8, 0
        PAGE.header = { builder = builder, frame = hdr }
        if type(builder) == "function" then
            -- what the header builder makes with CreateFrame is the header's, not the page's
            local page, pageMade = PAGE, PAGE.made
            page.made = {}
            PAGE.header.height = builder(hdr, 1030)
            page.header.made, page.made = page.made, pageMade
            hdr._h = PAGE.header.height or 0
        end
    end
    function E:ClearContentHeader() PAGE.cleared = PAGE.cleared + 1 end
    function E:SetContentHeaderHeightSilent(h) Wd.silentH = h; if PAGE and PAGE.header then PAGE.header.frame._h = h end end
    -- a preview's repaint resizes the header it is on
    function E:UpdateContentHeaderHeight(h) Wd.updateH = h end
    function E:IsShown() return true end
    -- The real overlay factory and hint dismissal of EllesmereUI_Widgets.lua. The
    -- factory's frames are counted apart from the page's (Wd.nav.frames) and every
    -- overlay is recorded (Wd.nav.ovs) with the page, the build and the preview it
    -- was made on; the dismissal's fade ticker is the helper's (Wd.nav.fades, run by
    -- H.RunFades), not a page's.
    do
        local widgets = assert(ReadSource(root .. OPT .. "EllesmereUI_Widgets.lua"), "EllesmereUI_Widgets.lua")
        local nav = Wd.nav
        local function HelperFrame(kind, _, parent)
            nav.frames = nav.frames + 1
            return Frame(kind, parent)
        end
        local fadeTimer = { NewTicker = function(_, fn)
            local t = { fn = fn }
            function t:Cancel() self.cancelled = true end
            nav.fades[#nav.fades + 1] = t
            return t
        end }
        assert(loadstring("local CreateFrame, EllesmereUI = ...\n"
            .. Cut(widgets, "EllesmereUI.CreatePreviewHitOverlay = function(", "\n-- DismissPreviewHint:", "the overlay factory"),
            "=EllesmereUI_Widgets.lua"))(HelperFrame, E)
        assert(loadstring("local PoolGen, C_Timer, EllesmereUI = ...\n"
            .. Cut(widgets, "EllesmereUI.DismissPreviewHint = function(", "\nEllesmereUI.BuildSliderCore", "the hint's dismissal"),
            "=EllesmereUI_Widgets.lua"))(E._Pool.Gen, fadeTimer, E)
        local factory, dismiss = E.CreatePreviewHitOverlay, E.DismissPreviewHint
        E.CreatePreviewHitOverlay = function(element, navigate, key, isText, level, opts, style)
            local btn, hlBase, hlCont = factory(element, navigate, key, isText, level, opts, style)
            nav.ovs[#nav.ovs + 1] = { btn = btn, element = element, navigate = navigate, key = key, isText = isText, level = level,
                opts = opts, style = style, hlBase = hlBase, hlCont = hlCont, page = PAGE and PAGE.name,
                prebuild = E._prebuilding, tfh = N._NPO_OptEnv.optState.tfhPreview, enemy = N._NPO_OptEnv.optState.activePreview }
            return btn, hlBase, hlCont
        end
        E.DismissPreviewHint = function(hint, base, hintH, y)
            nav.dismiss[#nav.dismiss + 1] = { hint = hint, base = base, hintH = hintH, y = y,
                shown = hint and hint:IsShown(), flag = EllesmereUIDB and EllesmereUIDB.previewHintDismissed }
            return dismiss(hint, base, hintH, y)
        end
    end
    -- The real note row of EllesmereUI_Widgets_PageParts.lua over this helper's frames.
    -- Every row a page asks for is recorded on it (PAGE.noteRows) and in its items.
    do
        local parts = assert(ReadSource(root .. OPT .. "EllesmereUI_Widgets_PageParts.lua"), "EllesmereUI_Widgets_PageParts.lua")
        E.CONTENT_PAD = 40
        E.RowBg = function(row) row._rowBg = true end
        local function RowFrame(kind, _, parent)
            Wd.noteFrames = (Wd.noteFrames or 0) + 1
            return Frame(kind, parent)
        end
        assert(loadstring("local CreateFrame, EllesmereUI = ...\n"
            .. Cut(parts, "function EllesmereUI.BuildNoteRow(parent, y, text, opts)", "\nlocal MC_ARROW_DOWN", "the note row"),
            "=EllesmereUI_Widgets_PageParts.lua"))(RowFrame, E)
        local real = E.BuildNoteRow
        E.BuildNoteRow = function(parent, y, text, opts)
            local n0, f0 = #Wd.notes, Wd.noteFrames or 0
            local y2 = real(parent, y, text, opts)
            local fs = Wd.notes[n0 + 1]
            local rec = { parent = parent, y = y, y2 = y2, text = text, opts = opts, fs = fs, row = fs and fs._parent,
                texts = #Wd.notes - n0, frames = (Wd.noteFrames or 0) - f0 }
            if PAGE then
                PAGE.noteRows[#PAGE.noteRows + 1] = rec
                PAGE.items[#PAGE.items + 1] = "note: " .. tostring(text)
            end
            return y2, rec
        end
    end
    function E:ShowConfirmPopup(t) LOG.popups[#LOG.popups + 1] = t end
    -- glows
    E.Glows = { STEALABLE_BORDER = -2, PANDEMIC_BORDER = -3, DEFAULT_COLOR = { r = 1, g = 0.8, b = 0 },
        FlatKeys = function(prefix) return { color = prefix .. "Color", style = prefix .. "Style", mode = prefix .. "ColorMode" } end }
    E.GlowOptions = {
        RegisterSite = function(site) Wd.sites[#Wd.sites + 1] = site end,
        FlatGet = function() end, FlatSet = function() end,
        DropdownSpec = function(desc, label, tooltip) return { type = "dropdown", text = label, tooltip = tooltip } end,
        AttachInline = function() end, BuildPreview = function() end, Renders = function() return true end,
    }
    -- the inline builders
    E.BuildInlineCog = function(rgn, o)
        if E._prebuilding then return nil end
        local host = rgn._cfg
        if o.disabled and not (o.disabledTooltip or (host and host.disabledTooltip)) then
            check(false, PAGE.name .. ": the cog '" .. tostring(o.title) .. "' is greyed with no tooltip to say why")
        end
        local btn = Frame("Cog", rgn)
        local page = PAGE
        btn._euiCogState = function() page.cogStates = page.cogStates + 1 end
        btn._anchor = o.anchorTo or (o.chain ~= false and rgn._lastInline) or rgn._control
        PAGE.cogs[#PAGE.cogs + 1] = { opts = o, rgn = rgn, host = host, btn = btn, section = PAGE.section }
        if o.chain ~= false then rgn._lastInline = btn end
        return btn
    end
    E.BuildInlineSwatches = function(rgn, list, o)
        if E._prebuilding then return end
        local f
        for i = #list, 1, -1 do
            f = Frame("Swatch", rgn)
            f._anchor = rgn._lastInline or rgn._control
            f._eabOrigClick = Rec("picker")
            list[i]._frame = f
            rgn._lastInline = f
        end
        PAGE.inline[#PAGE.inline + 1] = { list = list, opts = o or {}, rgn = rgn, host = rgn._cfg, section = PAGE.section }
    end
    E.BuildColorSwatch = function(rgn, level, get, set, hasAlpha, size)
        if E._prebuilding then
            local s = rgn.prebuildStandIn
            return s, s
        end
        local s = Frame("Swatch", rgn)
        s._scripts.OnClick = Rec("picker")
        s._stockClick = s._scripts.OnClick
        rgn._nSwatch = (rgn._nSwatch or 0) + 1
        PAGE.swatches[#PAGE.swatches + 1] = { get = get, set = set, hasAlpha = hasAlpha, size = size, rgn = rgn,
            host = rgn._cfg, frame = s, n = rgn._nSwatch, section = PAGE.section }
        return s, function() end
    end
    E.BuildVisOptsCBDropdown = function(rgn, w, level, items, get, set, onChanged, maxVisible, searchable, closeButton, onMenuClosed, opts)
        if E._prebuilding then
            local s = rgn.prebuildStandIn
            return s, s
        end
        local dd = Frame("Checklist", rgn)
        PAGE.checks[#PAGE.checks + 1] = { items = items, get = get, set = set, rgn = rgn, host = rgn._cfg, section = PAGE.section,
            opts = opts or {}, w = w, level = level, frame = dd,
            extra = onChanged ~= nil or maxVisible ~= nil or searchable ~= nil or closeButton ~= nil or onMenuClosed ~= nil }
        return dd, function() end
    end
    E.BuildSyncIcon = function() PAGE.syncs = PAGE.syncs + 1 end
    E.BuildDropdownControl = function(parent, w, level, values, order, get, set)
        local dd = Frame("Dropdown", parent)
        dd:SetFrameLevel(level)
        local rec = { parent = parent, w = w, values = values, order = order, get = get, set = set, frame = dd }
        if PAGE then PAGE.dropdowns[#PAGE.dropdowns + 1] = rec end
        return dd
    end
    -- The Name Format choices, as EllesmereUI.NameFormatMenu hands them out
    -- (the Character Count entry stands for a saved count of 12).
    E.NameFormatMenu = function(get, set, opts)
        check(opts == nil, "a Name Format row of these pages takes no opts")
        local values = { full = "Full Name", first = "First Name", last = "Last Name", abbr = "Abbreviated" }
        values._inputs = { "full", "first", "last", "abbr", 12 }
        return values, { "full", "first", "last", "abbr", "custom" }, function() return get() or "full" end, function(v) set(v) end
    end
    -- the sample plates
    E.ApplyBorderStyle = function(bf, size) bf._border = size end
    E.BorderPx = function() return nil end
    E.GetClassColor = function() return { r = 0.25, g = 0.78, b = 0.92 } end
    E.HexColor = function() return "|cffffffff" end
    -- (a check names one value secret: Wd.secret)
    E.IsSecret = function(v) return Wd.secret ~= nil and v == Wd.secret end
    E.ResolveTexturePath = function(_, key, fallback) return key == "none" and fallback or ("tex/" .. key) end
    E.SetFontFamily = function(fs, path, size) fs._font = { path, size } end
    -- The real Name Format shapes and surname join (EllesmereUI_UICore.lua), under this
    -- world's client: the player sample's name is cut by them.
    do
        local core = assert(ReadSource(root .. "EllesmereUI_UICore.lua"), "EllesmereUI_UICore.lua")
        local body = "local EllesmereUI, IS_FOREVER = ...\nlocal SEP, joined = \" \", {}\n"
            .. Cut(core, "    function EllesmereUI.WithSurname(name, surname, ignorePreference)\n",
                "\n    -- True for your own unit on WoW Forever while", "WithSurname") .. "\ndo\n"
            .. Cut(core, "        local floor = math.floor\n", "\n        -- The Name Format a unit's name takes:", "ShortName") .. "\nend\n"
        local names = {}
        setfenv(assert(loadstring(body, "=EllesmereUI_UICore.lua")), setmetatable({
            issecretvalue = function(v) return Wd.secret ~= nil and v == Wd.secret end,
            wipe = function(tb) for k in pairs(tb) do tb[k] = nil end end,
        }, { __index = _G }))(names, forever)
        E.ShortName, E.WithSurname = names.ShortName, names.WithSurname
    end
    EllesmereUI = setmetatable(E, { __index = function(_, k)
        if EUI_OPTIONAL[k] then return nil end
        error("EllesmereUI." .. tostring(k) .. " is not stubbed", 2)
    end })

    -- The files. The page files only define; the main file registers the module
    -- as it loads. A file that is missing or raises is a load error, not a crash.
    local function Load(name, chunkPrefix, cutFrom)
        local src = ReadSource(root .. name)
        if not src then
            Wd.loadErrors[#Wd.loadErrors + 1] = name .. ": no such file"
            return false
        end
        if cutFrom then
            local a = src:find(cutFrom, 1, true)
            if not a then
                Wd.loadErrors[#Wd.loadErrors + 1] = name .. ": '" .. cutFrom .. "' not found"
                return false
            end
            src = src:sub(a)
        end
        local fn, err = loadstring((chunkPrefix or "") .. src, "=" .. name:match("[^/]+$"))
        if not fn then
            Wd.loadErrors[#Wd.loadErrors + 1] = tostring(err)
            return false
        end
        local ok, e2 = pcall(fn, ns, FakePreview)
        if not ok then Wd.loadErrors[#Wd.loadErrors + 1] = tostring(e2) end
        return ok
    end
    local before = EVER.frames
    for _, name in ipairs({ "FriendlyPage_Options.lua", "FriendlyPreview_Options.lua", "GeneralPage_Options.lua",
        "TargetFocusHoverPage_Options.lua" }) do
        Load(NPO .. name)
    end
    Wd.partFrames, Wd.partOnShow, Wd.partEvents = EVER.frames - before, #Wd.onShow, #EVER.events - events0
    -- The header of the Target, Focus & Hover page, over the stand-in painter.
    Load(NPO .. "NameplatePreview_Options.lua", "local ns, BuildNameplatePreview = ...\n",
        "function ns.NPO_BuildTFHHeader(headerParent, headerW)")
    Load(OPT .. "EUI_Nameplates_Options.lua")
    Wd.env = nsData._NPO_OptEnv
    Wd.optState = Wd.env and Wd.env.optState
    -- The stand-in preview's real code, over the runtime pieces it reads that the
    -- page files do not (the rest from the strict ns).
    if Wd.env then
        local pvns = setmetatable({
            ResolveOverlayTexPath = function(key) return "ovtex/" .. tostring(key) end,
            GetHealthBarWidth = function() return 150 end,
            GetFocusLetterAnchor = function() return "CENTER" end,
            IsNameElement = function(el) return el == "enemyName" or el == "levelName" or el == "nameLevel" end,
            NP_ForeverSide = function() return 0 end,
        }, { __index = ns })
        local ok, bind = pcall(H.PreviewCuts, pvns, function(kind, _, parent) return Frame(kind, parent) end,
            function(fs, path, size, flags) fs._font = { path, size, flags } end)
        if ok then
            Wd.pvBind = bind
        else
            -- a load error (the registration's first check); the stand-in stays plain
            Wd.loadErrors[#Wd.loadErrors + 1] = "the preview's code: " .. tostring(bind)
            Wd.pvBind = function() return function() end, function() end end
        end
    end
    Wd.onShowAtLoad = #Wd.onShow
    for i = events0 + 1, #EVER.events do Wd.events[#Wd.events + 1] = EVER.events[i] end
    -- count the sample plates' repaints
    if nsData.NPO_FriendlyPreviewUpdate then
        local real = nsData.NPO_FriendlyPreviewUpdate
        nsData.NPO_FriendlyPreviewUpdate = function(...) LOG.fpv = LOG.fpv + 1; return real(...) end
    end
    return Wd
end

-- The real absorber widgets of the search pre-build.
function H.AbsorberW()
    local src = assert(ReadSource("EllesmereUI_GlobalSearch.lua"), "EllesmereUI_GlobalSearch.lua")
    return assert(loadstring(Cut(src, "local _absSection = nil", "-- Any factory method NOT stubbed above", "the absorber widgets")
        .. "\nreturn AbsorberW", "=EllesmereUI_GlobalSearch.lua"))()
end

-- Builds a page as the panel does (live) or as the search pre-build does.
function H.Build(Wd, name, prebuild)
    local builder = Wd.cfg.buildPage
    local page = NewPage(name, prebuild)
    PAGE = page
    EUI._buildingModule, EUI._buildingPage = FOLDER, name
    INDEX[name] = nil
    local parent = Frame("Page")
    local frames = EVER.frames
    local ok, res
    if prebuild then
        -- EllesmereUI_GlobalSearch.lua, PrebuildOnce and PrebuildJob: the absorber
        -- widgets, the header methods switched off.
        local saved = { EUI.SetContentHeader, EUI.ClearContentHeader, EUI.SetContentHeaderHeightSilent }
        EUI.SetContentHeader, EUI.ClearContentHeader, EUI.SetContentHeaderHeightSilent = function() end, function() end, function() end
        EUI._prebuilding = true
        EUI.Widgets = H.absorberW
        ok, res = pcall(builder, name, parent, -6)
        EUI.Widgets = W
        EUI._prebuilding = false
        EUI.SetContentHeader, EUI.ClearContentHeader, EUI.SetContentHeaderHeightSilent = saved[1], saved[2], saved[3]
    else
        ok, res = pcall(builder, name, parent, -6)
    end
    EUI._buildingModule, EUI._buildingPage = nil, nil
    page.ok, page.result, page.parent, page.framesMade = ok, res, parent, EVER.frames - frames
    page.index = INDEX[name] or { order = {}, by = {} }
    return page
end

-- Every control a page built, in build order. A control: id (section | row
-- label, then what it is inside the row), kind, get, set, gate (nil while it
-- is live, else why it is greyed), the inputs the signature drives it with,
-- and inside ("cog" for a row of a cog popup, "menu" for a checklist entry;
-- nil for what the page itself shows).
local function AddControl(list, c)
    list[#list + 1] = c
    list[c.id] = c
end
local function SliderInput(c)
    local min, max, step = c.min, c.max, c.step or 1
    local n = math.floor((max - min) / step * 0.37 + 0.5)
    return min + step * n
end
local function RowKind(cfg)
    local t = cfg.type
    if t == "colorpicker" then return "color" end
    return t
end
local function Inputs(kind, c)
    if kind == "toggle" then return { { true }, { false } } end
    if kind == "slider" then return { { SliderInput(c) } } end
    if kind == "color" then return { c.hasAlpha and { 0.25, 0.5, 0.75, 0.4 } or { 0.25, 0.5, 0.75 } } end
    if kind == "dropdown" then
        local out = {}
        for _, k in ipairs(c.values and c.values._inputs or c.order or {}) do
            if k ~= "---" then out[#out + 1] = { k } end
        end
        -- a long list: its first, middle and last entries
        if #out > 5 then out = { out[1], out[math.floor((#out + 1) / 2)], out[#out] } end
        return out
    end
    return {}
end
function H.Controls(page)
    local list = {}
    local function FromCfg(prefix, cfg, cogGate)
        local kind = RowKind(cfg)
        local inside = cogGate and "cog" or nil
        local get, set = cfg.getValue or cfg.get, cfg.setValue or cfg.set
        local label = cfg.text or cfg.label
        if kind == "multiSwatch" then
            for i, sc in ipairs(cfg.swatches or {}) do
                local sw = Frame("Swatch")
                sw._eabOrigClick = Rec("picker")
                local id = prefix .. label .. "|ms:" .. tostring(sc.tooltip or i)
                local function Gate()
                    if cfg.disabled and cfg.disabled() then return Tip(cfg) end
                    if sc.refreshAlpha then
                        local a = sc.refreshAlpha()
                        if a ~= 1 then return "dim" .. Val(a) end
                    end
                end
                AddControl(list, { id = id, kind = "color", hasAlpha = sc.hasAlpha, get = sc.getValue, set = sc.setValue,
                    gate = Gate, inputs = Inputs("color", sc) })
                if sc.onClick then
                    AddControl(list, { id = id .. "|click", kind = "click", set = function() sc.onClick(sw) end, gate = Gate, inputs = { {} } })
                end
            end
        elseif kind == "label" then
            if label and label ~= "" then AddControl(list, { id = prefix .. label, kind = "label", inputs = {} }) end
        elseif kind == "toggle" or kind == "slider" or kind == "dropdown" or kind == "color" then
            local c = { id = prefix .. tostring(label), kind = kind, get = get, set = set, cfg = cfg, inside = inside,
                min = cfg.min, max = cfg.max, step = cfg.step, values = cfg.values, order = cfg.order, hasAlpha = cfg.hasAlpha }
            c.placeholder = kind == "dropdown" and cfg.values and cfg.values.__placeholder ~= nil
            c.inputs = c.placeholder and {} or Inputs(kind, c)
            c.gate = function()
                local g = cogGate and cogGate()
                if g then return g end
                if cfg.disabled and cfg.disabled() then return Tip(cfg) end
            end
            AddControl(list, c)
        else
            check(false, page.name .. ": a control of an unknown type, " .. tostring(kind) .. " (" .. tostring(label) .. ")")
        end
    end
    local function HostLabel(host) return tostring(host and host.text ~= "" and host.text or "blank") end
    local cogsOf, inlineOf, swatchOf, checkOf = {}, {}, {}, {}
    local function Push(t, rgn, v) t[rgn] = t[rgn] or {}; t[rgn][#t[rgn] + 1] = v end
    for _, c in ipairs(page.cogs) do Push(cogsOf, c.rgn, c) end
    for _, c in ipairs(page.inline) do Push(inlineOf, c.rgn, c) end
    for _, c in ipairs(page.swatches) do Push(swatchOf, c.rgn, c) end
    for _, c in ipairs(page.checks) do Push(checkOf, c.rgn, c) end
    for _, r in ipairs(page.rows) do
        for _, side in ipairs({ "_leftRegion", "_rightRegion" }) do
            local rgn = r.row[side]
            local cfg = rgn._cfg
            local prefix = tostring(r.section) .. "|"
            FromCfg(prefix, cfg)
            local host = prefix .. HostLabel(cfg)
            for _, ck in ipairs(checkOf[rgn] or {}) do
                for _, item in ipairs(ck.items) do
                    AddControl(list, { id = host .. "|check:" .. item.key, kind = "check", inside = "menu",
                        label = tostring(item.label) .. (item.tooltip and " (" .. item.tooltip .. ")" or ""),
                        get = function() return ck.get(item.key) end,
                        set = function(v) ck.set(item.key, v) end,
                        gate = function()
                            -- the checklist's own gate (greyed whole), then the entry's lock
                            if ck.opts and ck.opts.disabled and ck.opts.disabled() then return Tip(ck.opts) end
                            if item.lockedFn and item.lockedFn() then
                                local tt = item.lockedTooltip
                                if type(tt) == "function" then tt = tt() end
                                return "locked:" .. tostring(tt)
                            end
                        end,
                        inputs = { { true }, { false } } })
                end
            end
            for _, cog in ipairs(cogsOf[rgn] or {}) do
                local o = cog.opts
                local function CogGate()
                    if o.disabled and o.disabled() then
                        return Tip(o.disabledTooltip and o or (cfg or {}))
                    end
                end
                AddControl(list, { id = host .. "|cog:" .. tostring(o.title), kind = "cog", gate = CogGate, inputs = {},
                    rows = #(o.rows or {}), cog = cog })
                for _, row in ipairs(o.rows or {}) do
                    FromCfg(host .. "|cog:" .. tostring(o.title) .. "|", row, CogGate)
                end
            end
            for _, il in ipairs(inlineOf[rgn] or {}) do
                for i, sc in ipairs(il.list) do
                    local id = host .. "|inline:" .. tostring(sc.tooltip or i)
                    local function Gate()
                        local o = il.opts
                        if o.disabled and o.disabled() then return Tip(sc.disabledTooltip ~= nil and sc or o) end
                        local d = sc.disabled
                        if type(d) == "function" then d = d() end
                        if d then return Tip(sc.disabledTooltip ~= nil and sc or o) end
                        -- a mode pair's unlit swatch
                        if sc.refreshAlpha then
                            local a = sc.refreshAlpha()
                            if a ~= 1 then return "dim" .. Val(a) end
                        end
                    end
                    AddControl(list, { id = id, kind = "color", hasAlpha = sc.hasAlpha, get = sc.getValue, set = sc.setValue,
                        gate = Gate, inputs = Inputs("color", sc) })
                    if sc.onClick then
                        AddControl(list, { id = id .. "|click", kind = "click", set = function() sc.onClick(sc._frame) end, gate = Gate, inputs = { {} } })
                    end
                end
            end
            for _, sw in ipairs(swatchOf[rgn] or {}) do
                local id = host .. "|swatch#" .. sw.n
                local f = sw.frame
                -- A hand-placed swatch greys itself in its page refresher.
                local function Gate()
                    if not f._mouse then return "off" .. Val(f._alpha) end
                    if f._alpha ~= 1 then return "dim" .. Val(f._alpha) end
                end
                AddControl(list, { id = id, kind = "color", hasAlpha = sw.hasAlpha, get = sw.get, set = sw.set, gate = Gate,
                    inputs = Inputs("color", sw), hand = true, frame = f })
                if f._scripts.OnClick ~= f._stockClick then
                    AddControl(list, { id = id .. "|click", kind = "click", set = function() f._scripts.OnClick(f) end, gate = Gate,
                        inputs = { {} }, hand = true })
                end
            end
        end
    end
    return list
end

-- The three settings every signature starts from: nothing saved; every gated
-- control live with Name Only on; the same with Name Only off.
H.STATES = {
    {},
    { showFriendlyNPCs = true, friendlyBelowName = "both", friendlyShowLevel = true, showTargetArrows = true,
      targetGlowHighlight = true, targetGlowBorderSize = true, targetGlowBorderColor = true,
      targetOverlayTexture = "striped-v2", hoverOverlayTexture = "striped-v2", hashLineEnabled = true,
      rangeTextEnabled = true, focusLetterEnabled = true, nonTargetAlpha = 50, targetColorEnabled = true,
      hoverGlowEllesmereUI = true, hoverGlowBorderColor = true, hoverGlowBorderSize = true,
      targetArrowClassColor = true, friendlyBelowNameClassColor = true, targetBorderSizeValue = 2, hoverBorderSizeValue = 2 },
}
H.STATES[3] = CopyState(H.STATES[2])
H.STATES[3].friendlyNameOnly, H.STATES[3].classColorFriendly = false, false
H.STATES[3].targetArrowClassColor, H.STATES[3].friendlyBelowNameClassColor = false, false

-- What a control does: its kind (a slider's range, a dropdown's entries, a
-- checklist entry's label and tooltip), then one line for its getter and one
-- per input, each over the three starting settings ("*" where they agree).
--   tip <the tooltip a hand-placed swatch shows on hover>
--   get <value> <keys read>
--   <input> > <key=value written> ! <runtime calls> $ <CVars> => <the getter after> # <flags>
-- (the getter after a write is printed only where it does not read the input back).
-- Flags: R the page refreshes, P a popup, T a timer, A a call put off to a
-- later frame, U the nameplate preview on screen repaints (u: one that is not
-- on screen), F the sample plates repaint.
function H.Signature(Wd, page, c)
    local function Run()
        for _, fn in ipairs(page.refreshers) do fn() end
    end
    local function Merge(per)
        if per[1] == per[2] and per[2] == per[3] then return { "*: " .. per[1] } end
        local out = {}
        for i = 1, 3 do out[#out + 1] = "S" .. i .. ": " .. per[i] end
        return out
    end
    local lines = {}
    local head = c.kind
    if c.kind == "slider" then head = head .. " " .. Val(c.min) .. ".." .. Val(c.max) .. "/" .. Val(c.step or 1) end
    if c.kind == "dropdown" and not c.placeholder then
        local ks = {}
        for _, k in ipairs(c.order or {}) do
            local label = c.values and rawget(c.values, k)
            ks[#ks + 1] = tostring(k) .. (type(label) == "string" and "=" .. label or "")
        end
        head = head .. " [" .. table.concat(ks, ",") .. "]"
    end
    if c.kind == "check" then head = head .. " " .. c.label end
    if c.kind == "color" and c.hasAlpha then head = head .. " rgba" end
    if c.kind == "cog" then head = head .. " of " .. c.rows .. (c.rows == 1 and " row" or " rows") end
    lines[1] = head
    if c.frame and c.frame._scripts.OnEnter then
        local per = {}
        for i = 1, 3 do
            H.SetState(H.STATES[i]); H.ResetLog(); Run()
            LOG.tip = nil
            c.frame._scripts.OnEnter(c.frame)
            per[i] = "tip " .. tostring(LOG.tip)
        end
        for _, l in ipairs(Merge(per)) do lines[#lines + 1] = l end
    end
    if c.get then
        local per = {}
        for i = 1, 3 do
            H.SetState(H.STATES[i]); H.ResetLog(); Run(); H.ResetLog()
            local v = Vals(c.get())
            local keys = {}
            for k in pairs(READS) do keys[#keys + 1] = k end
            table.sort(keys)
            per[i] = "get " .. v .. " <" .. table.concat(keys, ",") .. ">"
        end
        for _, l in ipairs(Merge(per)) do lines[#lines + 1] = l end
    end
    for _, input in ipairs(c.inputs or {}) do
        local per = {}
        for i = 1, 3 do
            H.SetState(H.STATES[i]); H.ResetLog(); Run(); H.ResetLog()
            local tfh, enemy = Wd.optState.tfhPreview, Wd.optState.activePreview
            local shown, hidden = Frame("Preview"), Frame("Preview")
            shown._n, hidden._n = 0, 0
            shown.Update = function(self) self._n = self._n + 1 end
            hidden.Update = shown.Update
            hidden._shown = false
            Wd.optState.tfhPreview, Wd.optState.activePreview = shown, hidden
            c.set(unpack(input))
            for _, t in ipairs(LOG.timers) do if not t.cancelled then t.fn() end end
            Wd.optState.tfhPreview, Wd.optState.activePreview = tfh, enemy
            local seen, w = {}, {}
            for _, k in ipairs(WRITES) do
                if not seen[k] then seen[k] = true; w[#w + 1] = k .. "=" .. Val(STORE[k]) end
            end
            local given = #input > 0 and Vals(unpack(input)) or "click"
            local s = given .. " > " .. table.concat(w, ",")
            if #LOG.calls > 0 then s = s .. " ! " .. table.concat(LOG.calls, ",") end
            if #LOG.cvars > 0 then s = s .. " $ " .. table.concat(LOG.cvars, ",") end
            local flags = (LOG.refresh > 0 and "R" or "") .. (#LOG.popups > 0 and "P" or "") .. (#LOG.timers > 0 and "T" or "")
                .. (#LOG.after > 0 and "A" or "")
                .. (shown._n > 0 and "U" or "") .. (hidden._n > 0 and "u" or "") .. (LOG.fpv > 0 and "F" or "")
            local after = c.get and Vals(c.get())
            if after and after ~= given then s = s .. " => " .. after end
            if flags ~= "" then s = s .. " # " .. flags end
            per[i] = s
        end
        for _, l in ipairs(Merge(per)) do lines[#lines + 1] = l end
    end
    return lines
end

-- The saved keys a control writes, over every input and starting setting.
function H.KeysWritten(Wd, page, c)
    local keys = {}
    for _, input in ipairs(c.inputs or {}) do
        for i = 1, 3 do
            H.SetState(H.STATES[i]); H.ResetLog()
            for _, fn in ipairs(page.refreshers) do fn() end
            H.ResetLog()
            c.set(unpack(input))
            for _, k in ipairs(WRITES) do keys[k] = true end
        end
    end
    return keys
end

-- A control's gate in the scenario that is set: nil while it is live. A
-- hand-placed swatch shows the state its page refresher last gave it, so the
-- page's refreshers run first (H.Refresh), as a page refresh runs them.
function H.GateOf(c)
    if not c.gate then return nil end
    return c.gate()
end
function H.Refresh(page)
    for _, fn in ipairs(page.refreshers) do fn() end
end

-- The settings a gate of these pages can depend on, each with the values it
-- takes beside "not saved", and the stock styles.
H.FLAGS = {
    ["Friendly Plates"] = {
        { "showFriendlyPlayers", false }, { "friendlyNameOnly", false }, { "classColorFriendly", false },
        { "friendlyBelowName", "title", "guild", "both" }, { "friendlyShowLevel", true }, { "showFriendlyNPCs", true },
        { "showNPCTitles", false }, { "raidMarkerPos", "none" }, { "targetGlowBorderColor", true },
        { "targetGlowBorderSize", true }, { "friendlyBelowNameClassColor", true },
    },
    ["Target, Focus & Hover"] = {
        { "showTargetArrows", true }, { "targetArrowClassColor", true }, { "targetGlowEllesmereUI", false },
        { "targetGlowHighlight", true }, { "targetGlowBorderSize", true }, { "targetGlowBorderColor", true },
        { "targetColorEnabled", true }, { "targetOverlayTexture", "striped-v2" }, { "targetOverlayNoTint", true },
        { "hashLineEnabled", true }, { "nonTargetAlpha", 50 }, { "outOfCombatAlpha", 50 }, { "rangeTextEnabled", true },
        { "focusColorEnabled", false }, { "focusOverlayTexture", "none" }, { "focusOverlayNoTint", true },
        { "focusLetterEnabled", true }, { "hoverOverlayTexture", "striped-v2" }, { "hoverGlowHighlight", false },
        { "hoverGlowEllesmereUI", true }, { "hoverGlowBorderSize", true }, { "hoverGlowBorderColor", true },
    },
}
H.STYLES = { { active = "blizzard" }, { active = "blizzard", forever = true }, { active = "classic" } }
-- How many of its flags a scenario saves at once: any number on the Friendly
-- Plates page (its gates stack), up to three on the Target, Focus & Hover page.
H.DEEP = { ["Friendly Plates"] = 99, ["Target, Focus & Hover"] = 3 }
-- Calls fn(state) for every setting of the flags that saves at most maxPick of them.
local function Combos(flags, maxPick, fn)
    local state = {}
    local function Next(i, picked)
        if i > #flags then return fn(state) end
        Next(i + 1, picked)
        if picked < maxPick then
            local f = flags[i]
            for v = 2, #f do
                state[f[1]] = f[v]
                Next(i + 1, picked + 1)
            end
            state[f[1]] = nil
        end
    end
    Next(1, 0)
end
-- The scenarios a page's gates are read in: under the EllesmereUI style every
-- setting of up to deep flags at once, under each stock style of up to two.
-- fn(state, style, n) runs with the scenario already set.
function H.EachMode(flags, deep, fn)
    local n = 0
    Combos(flags, deep, function(state)
        n = n + 1
        H.SetState(state)
        fn(state, STYLE, n)
    end)
    for _, style in ipairs(H.STYLES) do
        Combos(flags, 2, function(state)
            n = n + 1
            H.SetState(state, style)
            fn(state, STYLE, n)
        end)
    end
    return n
end

H.absorberW = H.AbsorberW()

-------------------------------------------------------------------------------
-- GATE: when a control is greyed and what its tooltip says, as a function of
-- the saved settings s (an unset key reads its default, written out here) and
-- the style st. nil = live. A tooltip reads "raw:<sentence>" (shown as
-- written), "req:<setting>" (wrapped as "requires ... to be enabled") or
-- "req-off:<setting>" (to be disabled). A hand-placed swatch has no tooltip:
-- "off<alpha>" (takes no click) or "dim<alpha>" (the other one of its pair is
-- the active one). A checklist entry reads "locked:<tooltip>".
-------------------------------------------------------------------------------
local GATE = {}
do
    -- Friendly Plates
    local PLAYERS = "raw:Requires Friendly Nameplate Style set to Name Only or Nameplate"
    local PLATE = "raw:Requires Friendly Nameplate Style set to Nameplate"
    local NAMEONLY = "raw:Requires Friendly Nameplate Style set to Name Only"
    local function playersOff(s) return s.showFriendlyPlayers == false end
    local function plateOff(s) return playersOff(s) or s.friendlyNameOnly ~= false end
    local function nameOnlyOff(s) return playersOff(s) or s.friendlyNameOnly == false end
    local function Guild(s)
        if playersOff(s) then return PLAYERS end
        if s.friendlyBelowName ~= "guild" and s.friendlyBelowName ~= "both" then
            return "raw:This option requires Subtitle Text to include the Guild Name"
        end
    end
    local function NPC(s)
        if s.showFriendlyNPCs ~= true then return "raw:Requires Show Friendly NPC Nameplates to be enabled" end
        if nameOnlyOff(s) then return NAMEONLY end
    end
    -- the target effects, as the runtime reads them (EUI Glow is on until saved off)
    local function tGlow(s, st) return not st.forever and s.targetGlowEllesmereUI ~= false end
    local function tBorderColor(s, st) return not st.forever and s.targetGlowBorderColor == true end
    local function tBorderSize(s, st) return not st.forever and s.targetGlowBorderSize == true end
    local function StyleName(st)
        return st.forever and "WoW Forever" or (st.active == "classic" and "Classic WoW UI" or "Blizzard Style")
    end
    function GATE.players(s) return playersOff(s) and PLAYERS or nil end
    function GATE.plate(s) return plateOff(s) and PLATE or nil end
    -- Health Bar Color: the Custom | Class pair over Class Colored Health Bar's key
    function GATE.barCustom(s) return (plateOff(s) and PLATE) or (s.classColorFriendly ~= false and "dim0.3" or nil) end
    function GATE.barClass(s) return (plateOff(s) and PLATE) or (s.classColorFriendly == false and "dim0.3" or nil) end
    function GATE.borderFx(s, st)
        if plateOff(s) then return PLATE end
        if st.active ~= "eui" then return "req-off:" .. StyleName(st) end
        if not (tBorderColor(s, st) or tBorderSize(s, st)) then
            return "raw:This option requires the Border Color or Border Size target effect."
        end
    end
    function GATE.nameOnly(s) return nameOnlyOff(s) and NAMEONLY or nil end
    -- Name Color: the pick, else the older key of the style in use (Name Only: Class
    -- Colored Health Bar's; the health bar plates: Class Colored Names')
    local function nameClass(s)
        if s.friendlyNameColorMode == "class" then return true end
        if s.friendlyNameColorMode == "custom" then return false end
        if s.friendlyNameOnly ~= false then return s.classColorFriendly ~= false end
        return s.friendlyNameClassColor == true
    end
    GATE.NameClass = nameClass
    function GATE.nameCustom(s) return (playersOff(s) and PLAYERS) or (nameClass(s) and "dim0.3" or nil) end
    function GATE.nameClass(s) return (playersOff(s) and PLAYERS) or (not nameClass(s) and "dim0.3" or nil) end
    GATE.guild = Guild
    function GATE.guildCustom(s) return Guild(s) or (s.friendlyBelowNameClassColor == true and "dim0.3" or nil) end
    function GATE.guildClass(s) return Guild(s) or (s.friendlyBelowNameClassColor ~= true and "dim0.3" or nil) end
    -- Guild Text Size: the guild line is a text of its own only on the health bar plate
    function GATE.guildSize(s) return (plateOff(s) and PLATE) or Guild(s) end
    function GATE.npcColor(s) return (s.showFriendlyNPCs ~= true or plateOff(s)) and "off0.3" or nil end
    GATE.npc = NPC
    function GATE.npcMarker(s) return NPC(s) or (s.raidMarkerPos == "none" and "req:Raid Marker" or nil) end
    function GATE.npcTitle(s) return NPC(s) or (s.showNPCTitles == false and "req:Show NPC Titles" or nil) end

    -- Target, Focus & Hover
    local FV = "Not available in the WoW Forever style."
    local function Effects(s, st)
        if not (s.targetGlowHighlight == true or tGlow(s, st) or tBorderSize(s, st)) then return "req:a Target Effect" end
    end
    function GATE.fvLocked(s, st) return st.forever and "locked:" .. FV or nil end
    GATE.effects = Effects
    function GATE.effectsGlow(s, st) return Effects(s, st) or (st.forever and "raw:" .. FV or nil) end
    function GATE.effectsSize(s, st)
        return Effects(s, st) or (not tBorderSize(s, st) and (st.forever and "raw:" .. FV or "req:Border Size Target Effect") or nil)
    end
    function GATE.borderColorOn(s, st) return not tBorderColor(s, st) and "off0.15" or nil end
    function GATE.glowOn(s, st) return not tGlow(s, st) and "off0.15" or nil end
    function GATE.arrows(s) return s.showTargetArrows ~= true and "req:Target Arrows" or nil end
    function GATE.arrowCustom(s)
        if s.showTargetArrows ~= true then return "off0.15" end
        return s.targetArrowClassColor == true and "dim0.3" or nil
    end
    function GATE.arrowClass(s)
        if s.showTargetArrows ~= true then return "off0.15" end
        return s.targetArrowClassColor ~= true and "dim0.3" or nil
    end
    function GATE.targetColorOn(s) return s.targetColorEnabled ~= true and "off0.15" or nil end
    local function targetTexNone(s) return s.targetOverlayTexture == nil end
    function GATE.targetTex(s) return targetTexNone(s) and "req:a Target Texture" or nil end
    function GATE.targetTexColor(s) return (targetTexNone(s) or s.targetOverlayNoTint == true) and "off0.15" or nil end
    function GATE.hashOn(s) return s.hashLineEnabled ~= true and "off0.15" or nil end
    local function Fading(s)
        if (s.nonTargetAlpha or 100) >= 100 and (s.outOfCombatAlpha or 100) >= 100 then
            return "req:This option requires Non-Target Opacity or Out of Combat Opacity to be below 100"
        end
    end
    GATE.fading = Fading
    function GATE.fadingCast(s) return Fading(s) or ((s.nonTargetAlpha or 100) >= 100 and "req:Non-Target Opacity below 100" or nil) end
    function GATE.range(s) return s.rangeTextEnabled ~= true and "req:Distance to Target Text" or nil end
    function GATE.rangeOn(s) return s.rangeTextEnabled ~= true and "off0.15" or nil end
    function GATE.focusColorOn(s) return s.focusColorEnabled == false and "off0.15" or nil end
    function GATE.focusTex(s) return s.focusOverlayTexture == "none" and "req:a Focus Texture" or nil end
    function GATE.focusTexColor(s) return (s.focusOverlayTexture == "none" or s.focusOverlayNoTint == true) and "off0.15" or nil end
    function GATE.letter(s) return s.focusLetterEnabled ~= true and "req:Focus Letter" or nil end
    function GATE.hoverTex(s) return s.hoverOverlayTexture == nil and "req:a Hover Texture" or nil end
    local function HoverEffects(s)
        if not (s.hoverGlowHighlight ~= false or s.hoverGlowEllesmereUI == true or s.hoverGlowBorderSize == true) then
            return "req:a Hover Effect"
        end
    end
    GATE.hoverEffects = HoverEffects
    function GATE.hoverSize(s) return HoverEffects(s) or (s.hoverGlowBorderSize ~= true and "req:Border Size Hover Effect" or nil) end
    function GATE.hoverBorderColorOn(s) return s.hoverGlowBorderColor ~= true and "off0.15" or nil end
    function GATE.hoverGlowOn(s) return s.hoverGlowEllesmereUI ~= true and "off0.15" or nil end
end

-------------------------------------------------------------------------------
-- THE CHECKS
-------------------------------------------------------------------------------
local DISPLAY, COLORS, TFH, FRIENDLY, GENERAL = "Display", "Colors", "Target, Focus & Hover", "Friendly Plates", "General"
-- The Friendly Plates page is built by the style in use: FRIENDLY names the page (and its
-- build under Nameplate, with every row), FRIENDLY_NO its build under Name Only or Blizzard
-- Default (no health bar rows, the Name Only name size).
local FRIENDLY_NO = "Friendly Plates built under Name Only"
local PLATE_BUILD = { friendlyNameOnly = false }
H.FLAGS[FRIENDLY_NO], H.DEEP[FRIENDLY_NO] = H.FLAGS[FRIENDLY], H.DEEP[FRIENDLY]

-- Two lists of lines, in order: one check, the first differences printed.
local function Compare(what, got, want)
    local same = #got == #want
    for i = 1, math.max(#got, #want) do
        if got[i] ~= want[i] then same = false end
    end
    count = count + 1
    if not same then
        fails = fails + 1
        if fails <= 60 then
            print("  FAIL: " .. what)
            local shown = 0
            for i = 1, math.max(#got, #want) do
                if got[i] ~= want[i] and shown < 5 then
                    shown = shown + 1
                    print(("      %-3d got  %s"):format(i, tostring(got[i])))
                    print(("          want %s"):format(tostring(want[i])))
                end
            end
        end
    end
    return same
end

-------------------------------------------------------------------------------
-- What the pages hold. A page's layout: "# SECTION", then its rows as
-- "left | right" (a blank half reads "blank"). Target, Focus & Hover is listed
-- as built with Show Hash Line on Target on: its Hash Line Location row is
-- built only then (HASH_ROW, CheckHashRow).
-------------------------------------------------------------------------------
local HASH_ROW = "Hash Line Location | blank"
local LAYOUT = {
    [TFH] = {
        "# TARGET",
        "Target Effect | Target Arrows",
        "Target Color | Target Texture",
        "Scale Target Nameplate | Non-Target Opacity",
        "Distance to Target Text | Show Hash Line on Target",
        "Hash Line Location | blank",
        "# FOCUS",
        "Focus Color | Focus Texture",
        "Focus Cast Height | Focus Letter",
        "# HOVER",
        "Hover Texture | Hover Effect",
    },
    [FRIENDLY] = {
        "note: Friendly Nameplate customization is disabled in instances due to Blizzard limitations",
        "# FRIENDLY PLAYERS",
        "Friendly Nameplate Style | Name Color",
        "Health Bar Width | Health Bar Height",
        "Health Bar Color | Show Health Percent",
        "Friendly Name Size | Player Name Format",
        "Level Text | Subtitle Text",
        "Friendly Names Not Clickable | Target Border Effects",
        "# FRIENDLY NPCS",
        "Show Friendly NPC Nameplates | Friendly NPC Name Format",
        "Show NPC Titles | Show Raid Marker",
        "Friendly NPC Name Size | Friendly NPC Title Size",
    },
}
-- Under Name Only or Blizzard Default the health bar plate's two rows are not on the page.
LAYOUT[FRIENDLY_NO] = {}
for _, line in ipairs(LAYOUT[FRIENDLY]) do
    if line ~= "Health Bar Width | Health Bar Height" and line ~= "Health Bar Color | Show Health Percent" then
        LAYOUT[FRIENDLY_NO][#LAYOUT[FRIENDLY_NO] + 1] = line
    end
end
-- The Extras tab. classRow: the last half of EXTRAS, a row only one class gets.
local function GeneralLayout(forever, classRow)
    local t = {
        "# NAMEPLATE SPACING",
        "Stacking Nameplates | Stacked Nameplate Spacing",
        "Hitbox Size X | Hitbox Size Y",
        "Stacking Speed | Top Screen Inset",
        "# EXTRA AURA OPTIONS",
        "Max Debuffs | Show Buff / Debuff Tooltips",
    }
    if not forever then t[#t + 1] = "Pandemic Glow Style | Pandemic Glow Preview" end
    for _, row in ipairs({
        "Enemy Buff Filter | Dispel Glow Style",
        "# EXTRAS",
        "Scale Nameplate On Cast | Hide Enemy Name While Casting",
        "Name Raid Marker | Experimental: Cast Lockout as CC Icon",
        "Out of Combat Opacity | Line of Sight Opacity",
        "Range Check | Out of Range Opacity",
        "Execute Pulse Glow | Hide Enemy Nameplates out of Combat",
        "Minor Enemy Scale (Percent) | Non-Elite Enemy Scale (Percent)",
        "Show Enemy Pet Nameplates | " .. (classRow or "blank"),
    }) do t[#t + 1] = row end
    return t
end

-- Every control of a page, in build order: its id (section | row label, then
-- what it is inside the row: a cog and its rows, check:<entry> of a checklist,
-- swatch#n hand-placed in the row, inline:<name> and ms:<name> swatches, and
-- |click where a swatch has a click of its own), the GATE that greys it, and
-- its signature (H.Signature). The rows the Extras tab always had carry their
-- id only.
local function C(id, gate, ...) return { id = id, gate = gate, sig = { ... } } end
local function RetailOnly(row) row.retail = true; return row end
local EXPECT = {}
EXPECT[TFH] = {
    C("TARGET|Target Effect", nil,
        "dropdown",
        "*: get \"__placeholder\" <targetGlowBorderColor,targetGlowBorderSize,targetGlowEllesmereUI,targetGlowHighlight>"),
    C("TARGET|Target Effect|check:ellesmereui", "fvLocked",
        "check EUI Glow",
        "*: get true <targetGlowEllesmereUI,targetGlowStyle>",
        "*: true > targetGlowEllesmereUI=true ! plate:ApplyTarget,fplate:ApplyTarget # U",
        "*: false > targetGlowEllesmereUI=false ! plate:ApplyTarget,fplate:ApplyTarget # U"),
    C("TARGET|Target Effect|check:borderColor", "fvLocked",
        "check Border Color",
        "S1: get false <targetGlowBorderColor,targetGlowStyle>",
        "S2: get true <targetGlowBorderColor>",
        "S3: get true <targetGlowBorderColor>",
        "*: true > targetGlowBorderColor=true ! plate:ApplyTarget,fplate:ApplyTarget # U",
        "*: false > targetGlowBorderColor=false ! plate:ApplyTarget,fplate:ApplyTarget # U"),
    C("TARGET|Target Effect|check:highlight", nil,
        "check Highlight",
        "S1: get false <targetGlowHighlight>",
        "S2: get true <targetGlowHighlight>",
        "S3: get true <targetGlowHighlight>",
        "*: true > targetGlowHighlight=true ! plate:ApplyTarget,fplate:ApplyTarget # U",
        "*: false > targetGlowHighlight=false ! plate:ApplyTarget,fplate:ApplyTarget # U"),
    C("TARGET|Target Effect|check:borderSize", "fvLocked",
        "check Border Size (Change Size in the Cogwheel)",
        "S1: get false <targetGlowBorderSize>",
        "S2: get true <targetGlowBorderSize>",
        "S3: get true <targetGlowBorderSize>",
        "S1: true > targetGlowBorderSize=true,targetBorderSizeValue=1 ! plate:ApplyTarget,fplate:ApplyTarget # U",
        "S2: true > targetGlowBorderSize=true ! plate:ApplyTarget,fplate:ApplyTarget # U",
        "S3: true > targetGlowBorderSize=true ! plate:ApplyTarget,fplate:ApplyTarget # U",
        "*: false > targetGlowBorderSize=false ! plate:ApplyTarget,fplate:ApplyTarget # U"),
    C("TARGET|Target Effect|cog:More Effects", "effects",
        "cog of 4 rows"),
    C("TARGET|Target Effect|cog:More Effects|Highlight Color", "effects",
        "color",
        "*: get 1,1,1 <targetHighlightColor>",
        "*: 0.25,0.5,0.75 > targetHighlightColor={b=0.75,g=0.5,r=0.25} ! plate:ApplyTarget # U"),
    C("TARGET|Target Effect|cog:More Effects|Highlight Opacity", "effects",
        "slider 0..100/1",
        "*: get 20 <targetHighlightAlpha>",
        "*: 37 > targetHighlightAlpha=0.37 ! plate:ApplyTarget # U"),
    C("TARGET|Target Effect|cog:More Effects|Glow Opacity", "effectsGlow",
        "slider 0..100/1",
        "*: get 100 <targetGlowAlpha>",
        "*: 37 > targetGlowAlpha=0.37 ! plate:ApplyTarget # U"),
    C("TARGET|Target Effect|cog:More Effects|Border Size", "effectsSize",
        "slider 0..4/1",
        "S1: get 1 <borderSize,customBorderEnabled,targetBorderSizeValue>",
        "S2: get 2 <targetBorderSizeValue>",
        "S3: get 2 <targetBorderSizeValue>",
        "*: 1 > targetBorderSizeValue=1 ! plate:ApplyTarget,fplate:ApplyTarget # U"),
    C("TARGET|Target Effect|swatch#1", "borderColorOn",
        "color",
        "*: tip Border Color",
        "*: get 1,1,1 <targetBorderColor>",
        "*: 0.25,0.5,0.75 > targetBorderColor={b=0.75,g=0.5,r=0.25} ! plate:ApplyTarget,fplate:ApplyTarget # U"),
    C("TARGET|Target Effect|swatch#2", "glowOn",
        "color",
        "*: tip Glow Color",
        "*: get 0.4117,0.6667,1 <targetGlowColor>",
        "*: 0.25,0.5,0.75 > targetGlowColor={b=0.75,g=0.5,r=0.25} ! plate:ApplyTarget # U"),
    C("TARGET|Target Arrows", nil,
        "dropdown [none=None,simple=Simple,double=Double]",
        "S1: get \"none\" <showTargetArrows>",
        "S2: get \"simple\" <showTargetArrows,targetArrowDouble,targetArrowStyle>",
        "S3: get \"simple\" <showTargetArrows,targetArrowDouble,targetArrowStyle>",
        "*: \"none\" > showTargetArrows=false ! plate:ApplyTarget # RU",
        "*: \"simple\" > showTargetArrows=true,targetArrowStyle=\"simple\" ! plate:ApplyTarget # RU",
        "*: \"double\" > showTargetArrows=true,targetArrowStyle=\"double\" ! plate:ApplyTarget # RU"),
    C("TARGET|Target Arrows|cog:Arrow Scale", "arrows",
        "cog of 1 row"),
    C("TARGET|Target Arrows|cog:Arrow Scale|Scale", "arrows",
        "slider 0.5..3/0.1",
        "*: get 1 <targetArrowScale>",
        "*: 1.4 > targetArrowScale=1.4 ! leftArrow=15x22,rightArrow=15x22 # U"),
    C("TARGET|Target Arrows|swatch#1", "arrowCustom",
        "color",
        "*: tip Custom Color",
        "*: get 1,1,1 <targetArrowColor>",
        "*: 0.25,0.5,0.75 > targetArrowColor={b=0.75,g=0.5,r=0.25},targetArrowClassColor=false ! plate:ApplyTarget # U"),
    C("TARGET|Target Arrows|swatch#1|click", "arrowCustom",
        "click",
        "S1: click > ",
        "S2: click > targetArrowClassColor=false ! plate:ApplyTarget # U",
        "S3: click >  ! picker"),
    C("TARGET|Target Arrows|swatch#2", "arrowClass",
        "color",
        "*: tip Class Color",
        "*: get 0.25,0.78,0.92 <>",
        "*: 0.25,0.5,0.75 >  => 0.25,0.78,0.92"),
    C("TARGET|Target Arrows|swatch#2|click", "arrowClass",
        "click",
        "S1: click > ",
        "S2: click > targetArrowClassColor=true ! plate:ApplyTarget # U",
        "S3: click > targetArrowClassColor=true ! plate:ApplyTarget # U"),
    C("TARGET|Target Color", nil,
        "toggle",
        "S1: get false <targetColorEnabled>",
        "S2: get true <targetColorEnabled>",
        "S3: get true <targetColorEnabled>",
        "*: true > targetColorEnabled=true ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: false > targetColorEnabled=false ! NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("TARGET|Target Color|swatch#1", "targetColorOn",
        "color",
        "*: get 0.459,0.89,0.58 <target>",
        "*: 0.25,0.5,0.75 > target={b=0.75,g=0.5,r=0.25} ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("TARGET|Target Texture", nil,
        "dropdown [striped-v2=Stripes,striped-wide-v2=Wide Stripes,stripes-medium=Medium Stripes,stripes-small-close=Small Dense Stripes,stripes-small-spread=Small Spread Stripes,striped-tiny=Tiny Stripes,---,none=None,---,smooth=Smooth]",
        "S1: get \"none\" <targetOverlayTexture>",
        "S2: get \"striped-v2\" <targetOverlayTexture>",
        "S3: get \"striped-v2\" <targetOverlayTexture>",
        "*: \"striped-v2\" > targetOverlayTexture=\"striped-v2\" ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: \"stripes-small-close\" > targetOverlayTexture=\"stripes-small-close\" ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: \"smooth\" > targetOverlayTexture=\"smooth\" ! NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("TARGET|Target Texture|cog:Target Texture", "targetTex",
        "cog of 3 rows"),
    C("TARGET|Target Texture|cog:Target Texture|Opacity", "targetTex",
        "slider 5..100/1",
        "*: get 100 <targetOverlayAlpha>",
        "*: 40 > targetOverlayAlpha=0.4 ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("TARGET|Target Texture|cog:Target Texture|Full alpha on empty part of bar", "targetTex",
        "toggle",
        "*: get false <targetOverlayFullBgAlpha>",
        "*: true > targetOverlayFullBgAlpha=true ! NP_CastTintsDirty,plate:UpdateHealth # U",
        "*: false > targetOverlayFullBgAlpha=false ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("TARGET|Target Texture|cog:Target Texture|Don't tint (keep bar's own color)", "targetTex",
        "toggle",
        "*: get false <targetOverlayNoTint>",
        "*: true > targetOverlayNoTint=true ! RefreshAllSettings,ApplyHealthBarTexture,ApplyCastBarTexture # RU",
        "*: false > targetOverlayNoTint=false ! RefreshAllSettings,ApplyHealthBarTexture,ApplyCastBarTexture # RU"),
    C("TARGET|Target Texture|swatch#1", "targetTexColor",
        "color",
        "*: get 1,1,1 <targetOverlayColor>",
        "*: 0.25,0.5,0.75 > targetOverlayColor={b=0.75,g=0.5,r=0.25} ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("TARGET|Scale Target Nameplate", nil,
        "slider 50..200/5",
        "*: get 100 <targetScale>",
        "*: 105 > targetScale=105 ! plate:ApplyScale # U"),
    C("TARGET|Non-Target Opacity", nil,
        "slider 0..100/1",
        "S1: get 100 <nonTargetAlpha>",
        "S2: get 50 <nonTargetAlpha>",
        "S3: get 50 <nonTargetAlpha>",
        "*: 37 > nonTargetAlpha=37 ! NT_RefreshSetting # R"),
    C("TARGET|Non-Target Opacity|cog:Non-Target Opacity", "fading",
        "cog of 2 rows"),
    C("TARGET|Non-Target Opacity|cog:Non-Target Opacity|Keep Focus Full Opacity", "fading",
        "toggle",
        "*: get true <nonTargetKeepFocus>",
        "*: true > nonTargetKeepFocus=true ! NT_RefreshSetting",
        "*: false > nonTargetKeepFocus=false ! NT_RefreshSetting"),
    C("TARGET|Non-Target Opacity|cog:Non-Target Opacity|Full Opacity While Casting", "fadingCast",
        "dropdown [off=Off,all=All Casts,important=Important Casts]",
        "*: get \"off\" <nonTargetCastFull>",
        "*: \"off\" > nonTargetCastFull=false,nonTargetCastImportantOnly=false ! NT_RefreshSetting",
        "*: \"all\" > nonTargetCastFull=true,nonTargetCastImportantOnly=false ! NT_RefreshSetting",
        "*: \"important\" > nonTargetCastFull=true,nonTargetCastImportantOnly=true ! NT_RefreshSetting"),
    C("TARGET|Distance to Target Text", nil,
        "toggle",
        "S1: get false <rangeTextEnabled>",
        "S2: get true <rangeTextEnabled>",
        "S3: get true <rangeTextEnabled>",
        "*: true > rangeTextEnabled=true ! RangeText_Apply # RU",
        "*: false > rangeTextEnabled=false ! RangeText_Apply # RU"),
    C("TARGET|Distance to Target Text|cog:Distance Text", "range",
        "cog of 3 rows"),
    C("TARGET|Distance to Target Text|cog:Distance Text|Text Size", "range",
        "slider 6..32/1",
        "*: get 11 <rangeTextSize>",
        "*: 16 > rangeTextSize=16 ! RangeText_Refresh # U"),
    C("TARGET|Distance to Target Text|cog:Distance Text|Offset X", "range",
        "slider -200..200/1",
        "*: get 0 <rangeTextOffsetX>",
        "*: -52 > rangeTextOffsetX=-52 ! RangeText_Refresh # U"),
    C("TARGET|Distance to Target Text|cog:Distance Text|Offset Y", "range",
        "slider -200..200/1",
        "*: get 0 <rangeTextOffsetY>",
        "*: -52 > rangeTextOffsetY=-52 ! RangeText_Refresh # U"),
    C("TARGET|Distance to Target Text|swatch#1", "rangeOn",
        "color",
        "*: get 0.816,0.357,0.22 <rangeTextColor>",
        "*: 0.25,0.5,0.75 > rangeTextColor={b=0.75,g=0.5,r=0.25} ! RangeText_Refresh # U"),
    C("TARGET|Show Hash Line on Target", nil,
        "toggle",
        "S1: get false <hashLineEnabled>",
        "S2: get true <hashLineEnabled>",
        "S3: get true <hashLineEnabled>",
        "*: true > hashLineEnabled=true ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: false > hashLineEnabled=false ! NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("TARGET|Show Hash Line on Target|swatch#1", "hashOn",
        "color",
        "*: get 1,1,1 <hashLineColor>",
        "*: 0.25,0.5,0.75 > hashLineColor={b=0.75,g=0.5,r=0.25} ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("TARGET|Hash Line Location", nil,
        "slider 0..100/1",
        "*: get 30 <hashLinePercent>",
        "*: 37 > hashLinePercent=37 ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Color", nil,
        "toggle",
        "*: get true <focusColorEnabled>",
        "*: true > focusColorEnabled=true ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: false > focusColorEnabled=false ! NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("FOCUS|Focus Color|swatch#1", "focusColorOn",
        "color",
        "*: get 0.051,0.82,0.62 <focus>",
        "*: 0.25,0.5,0.75 > focus={b=0.75,g=0.5,r=0.25} ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Texture", nil,
        "dropdown [striped-v2=Stripes,striped-wide-v2=Wide Stripes,stripes-medium=Medium Stripes,stripes-small-close=Small Dense Stripes,stripes-small-spread=Small Spread Stripes,striped-tiny=Tiny Stripes,---,none=None,---,smooth=Smooth]",
        "*: get \"striped-v2\" <focusOverlayTexture>",
        "*: \"striped-v2\" > focusOverlayTexture=\"striped-v2\" ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: \"stripes-small-close\" > focusOverlayTexture=\"stripes-small-close\" ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: \"smooth\" > focusOverlayTexture=\"smooth\" ! NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("FOCUS|Focus Texture|cog:Focus Texture", "focusTex",
        "cog of 3 rows"),
    C("FOCUS|Focus Texture|cog:Focus Texture|Opacity", "focusTex",
        "slider 5..100/1",
        "*: get 100 <focusOverlayAlpha>",
        "*: 40 > focusOverlayAlpha=0.4 ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Texture|cog:Focus Texture|Full alpha on empty part of bar", "focusTex",
        "toggle",
        "*: get false <focusOverlayFullBgAlpha>",
        "*: true > focusOverlayFullBgAlpha=true ! NP_CastTintsDirty,plate:UpdateHealth # U",
        "*: false > focusOverlayFullBgAlpha=false ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Texture|cog:Focus Texture|Don't tint (keep bar's own color)", "focusTex",
        "toggle",
        "*: get false <focusOverlayNoTint>",
        "*: true > focusOverlayNoTint=true ! RefreshAllSettings,ApplyHealthBarTexture,ApplyCastBarTexture,NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: false > focusOverlayNoTint=false ! RefreshAllSettings,ApplyHealthBarTexture,ApplyCastBarTexture,NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("FOCUS|Focus Texture|swatch#1", "focusTexColor",
        "color",
        "*: get 1,1,1 <focusOverlayColor>",
        "*: 0.25,0.5,0.75 > focusOverlayColor={b=0.75,g=0.5,r=0.25} ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Cast Height", nil,
        "slider 100..200/5",
        "*: get 100 <focusCastHeight>",
        "*: 135 > focusCastHeight=135 ! RefreshAllSettings # U"),
    -- one dropdown over focusLetterEnabled and focusLetterAnchor: None first, then where
    -- the letter sits; None keeps the saved anchor, a spot turns the letter on
    C("FOCUS|Focus Letter", nil,
        "dropdown [none=None,CENTER=Center,LEFT=Left,RIGHT=Right,TOP=Top,BOTTOM=Bottom,TOPLEFT=Top Left,TOPRIGHT=Top Right,BOTTOMLEFT=Bottom Left,BOTTOMRIGHT=Bottom Right]",
        "S1: get \"none\" <focusLetterAnchor,focusLetterEnabled>",
        "S2: get \"CENTER\" <focusLetterAnchor,focusLetterEnabled>",
        "S3: get \"CENTER\" <focusLetterAnchor,focusLetterEnabled>",
        "*: \"none\" > focusLetterEnabled=false ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: \"TOP\" > focusLetterEnabled=true,focusLetterAnchor=\"TOP\" ! NP_CastTintsDirty,plate:UpdateHealth # RU",
        "*: \"BOTTOMRIGHT\" > focusLetterEnabled=true,focusLetterAnchor=\"BOTTOMRIGHT\" ! NP_CastTintsDirty,plate:UpdateHealth # RU"),
    C("FOCUS|Focus Letter|cog:Focus Letter", "letter",
        "cog of 3 rows"),
    C("FOCUS|Focus Letter|cog:Focus Letter|Size", "letter",
        "slider 6..40/1",
        "*: get 18 <focusLetterSize>",
        "*: 19 > focusLetterSize=19 ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Letter|cog:Focus Letter|X", "letter",
        "slider -100..100/1",
        "*: get 0 <focusLetterX>",
        "*: -26 > focusLetterX=-26 ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("FOCUS|Focus Letter|cog:Focus Letter|Y", "letter",
        "slider -100..100/1",
        "*: get 0 <focusLetterY>",
        "*: -26 > focusLetterY=-26 ! NP_CastTintsDirty,plate:UpdateHealth # U"),
    C("HOVER|Hover Texture", nil,
        "dropdown [none=None,---,striped-v2=Stripes,striped-wide-v2=Wide Stripes,stripes-medium=Medium Stripes,stripes-small-close=Small Dense Stripes,stripes-small-spread=Small Spread Stripes,striped-tiny=Tiny Stripes,---,---,smooth=Smooth]",
        "S1: get \"none\" <hoverOverlayTexture>",
        "S2: get \"striped-v2\" <hoverOverlayTexture>",
        "S3: get \"striped-v2\" <hoverOverlayTexture>",
        "*: \"none\" > hoverOverlayTexture=\"none\" ! RefreshHoverEffect # RU",
        "*: \"stripes-medium\" > hoverOverlayTexture=\"stripes-medium\" ! RefreshHoverEffect # RU",
        "*: \"smooth\" > hoverOverlayTexture=\"smooth\" ! RefreshHoverEffect # RU"),
    C("HOVER|Hover Texture|cog:Hover Texture", "hoverTex",
        "cog of 1 row"),
    C("HOVER|Hover Texture|cog:Hover Texture|Full alpha on empty part of bar", "hoverTex",
        "toggle",
        "*: get false <hoverOverlayFullBgAlpha>",
        "*: true > hoverOverlayFullBgAlpha=true ! RefreshHoverEffect # U",
        "*: false > hoverOverlayFullBgAlpha=false ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect", nil,
        "dropdown",
        "*: get \"__placeholder\" <hoverGlowBorderColor,hoverGlowBorderSize,hoverGlowEllesmereUI,hoverGlowHighlight>"),
    C("HOVER|Hover Effect|check:ellesmereui", nil,
        "check EUI Glow",
        "S1: get false <hoverGlowEllesmereUI>",
        "S2: get true <hoverGlowEllesmereUI>",
        "S3: get true <hoverGlowEllesmereUI>",
        "*: true > hoverGlowEllesmereUI=true ! RefreshHoverEffect # U",
        "*: false > hoverGlowEllesmereUI=false ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|check:borderColor", nil,
        "check Border Color",
        "S1: get false <hoverGlowBorderColor>",
        "S2: get true <hoverGlowBorderColor>",
        "S3: get true <hoverGlowBorderColor>",
        "*: true > hoverGlowBorderColor=true ! RefreshHoverEffect # U",
        "*: false > hoverGlowBorderColor=false ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|check:highlight", nil,
        "check Highlight",
        "*: get true <hoverGlowHighlight>",
        "*: true > hoverGlowHighlight=true ! RefreshHoverEffect # U",
        "*: false > hoverGlowHighlight=false ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|check:borderSize", nil,
        "check Border Size (Change Size in the Cogwheel)",
        "S1: get false <hoverGlowBorderSize>",
        "S2: get true <hoverGlowBorderSize>",
        "S3: get true <hoverGlowBorderSize>",
        "S1: true > hoverGlowBorderSize=true,hoverBorderSizeValue=1 ! RefreshHoverEffect # U",
        "S2: true > hoverGlowBorderSize=true ! RefreshHoverEffect # U",
        "S3: true > hoverGlowBorderSize=true ! RefreshHoverEffect # U",
        "*: false > hoverGlowBorderSize=false ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|cog:More Effects", "hoverEffects",
        "cog of 4 rows"),
    C("HOVER|Hover Effect|cog:More Effects|Highlight Color", "hoverEffects",
        "color",
        "*: get 1,1,1 <hoverColor>",
        "*: 0.25,0.5,0.75 > hoverColor={b=0.75,g=0.5,r=0.25} ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|cog:More Effects|Highlight Opacity", "hoverEffects",
        "slider 0..100/1",
        "*: get 30 <hoverAlpha>",
        "*: 37 > hoverAlpha=0.37 ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|cog:More Effects|Glow Opacity", "hoverEffects",
        "slider 0..100/1",
        "*: get 100 <hoverGlowAlpha>",
        "*: 37 > hoverGlowAlpha=0.37 ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|cog:More Effects|Border Size", "hoverSize",
        "slider 0..4/1",
        "S1: get 1 <borderSize,customBorderEnabled,hoverBorderSizeValue>",
        "S2: get 2 <hoverBorderSizeValue>",
        "S3: get 2 <hoverBorderSizeValue>",
        "*: 1 > hoverBorderSizeValue=1 ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|swatch#1", "hoverBorderColorOn",
        "color",
        "*: tip Border Color",
        "*: get 1,1,1 <hoverBorderColor>",
        "*: 0.25,0.5,0.75 > hoverBorderColor={b=0.75,g=0.5,r=0.25} ! RefreshHoverEffect # U"),
    C("HOVER|Hover Effect|swatch#2", "hoverGlowOn",
        "color",
        "*: tip Glow Color",
        "*: get 0.4117,0.6667,1 <hoverGlowColor>",
        "*: 0.25,0.5,0.75 > hoverGlowColor={b=0.75,g=0.5,r=0.25} ! RefreshHoverEffect # U"),
}
EXPECT[FRIENDLY] = {
    -- One dropdown over showFriendlyPlayers and friendlyNameOnly. The three starting
    -- settings are EUI styles (Name Only twice, then Nameplate), so a pick of the style
    -- in use writes nothing; CheckStyleAndNameColor drives every change of style.
    C("FRIENDLY PLAYERS|Friendly Nameplate Style", nil,
        "dropdown [blizzard=Blizzard Default,nameonly=Name Only,plate=Nameplate]",
        "S1: get \"nameonly\" <friendlyNameOnly,showFriendlyPlayers>",
        "S2: get \"nameonly\" <friendlyNameOnly,showFriendlyPlayers>",
        "S3: get \"plate\" <friendlyNameOnly,showFriendlyPlayers>",
        "*: \"blizzard\" > showFriendlyPlayers=false ! UpdateFriendlyNameplateSystem,RefreshStackingMotion $ nameplateShowOnlyNameForFriendlyPlayerUnits=def:nameplateShowOnlyNameForFriendlyPlayerUnits,ShowClassColorInFriendlyNameplate=def:ShowClassColorInFriendlyNameplate,nameplateUseClassColorForFriendlyPlayerUnitNames=def:nameplateUseClassColorForFriendlyPlayerUnitNames # RF",
        "S1: \"nameonly\" > ",
        "S2: \"nameonly\" > ",
        "S3: \"nameonly\" > friendlyNameOnly=true ! ForceFriendlyPlayerCVarsOn,UpdateFriendlyNameplateSystem $ nameplateShowOnlyNameForFriendlyPlayerUnits=1,nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S1: \"plate\" > friendlyNameOnly=false ! UpdateFriendlyNameplateSystem $ nameplateShowOnlyNameForFriendlyPlayerUnits=0,nameplateUseClassColorForFriendlyPlayerUnitNames=1 # RF",
        "S2: \"plate\" > friendlyNameOnly=false ! UpdateFriendlyNameplateSystem $ nameplateShowOnlyNameForFriendlyPlayerUnits=0,nameplateUseClassColorForFriendlyPlayerUnitNames=1 # RF",
        "S3: \"plate\" > "),
    C("FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings", nil,
        "cog of 2 rows"),
    C("FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings|Blizzard Nameplate Size", nil,
        "slider 1..5/1",
        "*: get 3 <nameplateSize>",
        "*: 2 > nameplateSize=2 $ nameplateSize=2 # PT"),
    C("FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings|Show [] Around Group/Raid", "players",
        "toggle",
        "*: get false <friendlyGroupBrackets>",
        "*: true > friendlyGroupBrackets=true ! RefreshFriendlyBelowName # F",
        "*: false > friendlyGroupBrackets=false ! RefreshFriendlyBelowName # F"),
    -- Name Color: the Custom | Class pair. Under the first two starting settings (Name
    -- Only, nothing picked) Class is lit; under the third (Nameplate) Custom is.
    C("FRIENDLY PLAYERS|Name Color|ms:Custom Color", "nameCustom",
        "color",
        "*: get 1,1,1 <friendlyNameColor>",
        "S1: 0.25,0.5,0.75 > friendlyNameColor={b=0.75,g=0.5,r=0.25},friendlyNameColorMode=\"custom\" ! RefreshFriendlyColors,RefreshFriendlyBelowName $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S2: 0.25,0.5,0.75 > friendlyNameColor={b=0.75,g=0.5,r=0.25},friendlyNameColorMode=\"custom\" ! RefreshFriendlyColors,RefreshFriendlyBelowName $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S3: 0.25,0.5,0.75 > friendlyNameColor={b=0.75,g=0.5,r=0.25},friendlyNameColorMode=\"custom\" ! RefreshFriendlyColors,RefreshFriendlyBelowName $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # F"),
    C("FRIENDLY PLAYERS|Name Color|ms:Custom Color|click", "nameCustom",
        "click",
        "S1: click > friendlyNameColorMode=\"custom\" ! RefreshFriendlyColors,RefreshFriendlyBelowName $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S2: click > friendlyNameColorMode=\"custom\" ! RefreshFriendlyColors,RefreshFriendlyBelowName $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S3: click >  ! picker"),
    C("FRIENDLY PLAYERS|Name Color|ms:Class Color", "nameClass",
        "color",
        "*: get 0.25,0.78,0.92 <>",
        "*: 0.25,0.5,0.75 >  => 0.25,0.78,0.92"),
    C("FRIENDLY PLAYERS|Name Color|ms:Class Color|click", "nameClass",
        "click",
        "*: click > friendlyNameColorMode=\"class\" ! RefreshFriendlyColors,RefreshFriendlyBelowName $ nameplateUseClassColorForFriendlyPlayerUnitNames=1 # RF"),
    C("FRIENDLY PLAYERS|Health Bar Width", "plate",
        "slider 80..250/1",
        "*: get 150 <friendlyHealthBarWidth>",
        "*: 143 > friendlyHealthBarWidth=143 ! RefreshFriendlyPlateSize # F"),
    C("FRIENDLY PLAYERS|Health Bar Height", "plate",
        "slider 6..40/1",
        "*: get 17 <friendlyHealthBarHeight>",
        "*: 19 > friendlyHealthBarHeight=19 ! RefreshFriendlyPlateSize # F"),
    -- Health Bar Color: the Custom | Class pair over classColorFriendly and friendlyBarColor.
    -- Under the first two starting settings the bar is class colored, under the third not.
    C("FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color", "barCustom",
        "color",
        "*: get 0.314,0.8,0.408 <friendlyBarColor>",
        "S1: 0.25,0.5,0.75 > friendlyBarColor={b=0.75,g=0.5,r=0.25},classColorFriendly=false ! RefreshAllSettings $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S2: 0.25,0.5,0.75 > friendlyBarColor={b=0.75,g=0.5,r=0.25},classColorFriendly=false ! RefreshAllSettings $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S3: 0.25,0.5,0.75 > friendlyBarColor={b=0.75,g=0.5,r=0.25} ! RefreshFriendlyColors # F"),
    C("FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color|click", "barCustom",
        "click",
        "S1: click > classColorFriendly=false ! RefreshAllSettings $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S2: click > classColorFriendly=false ! RefreshAllSettings $ nameplateUseClassColorForFriendlyPlayerUnitNames=0 # RF",
        "S3: click >  ! picker"),
    C("FRIENDLY PLAYERS|Health Bar Color|ms:Class Color", "barClass",
        "color",
        "*: get 0.25,0.78,0.92 <>",
        "*: 0.25,0.5,0.75 >  => 0.25,0.78,0.92"),
    C("FRIENDLY PLAYERS|Health Bar Color|ms:Class Color|click", "barClass",
        "click",
        "*: click > classColorFriendly=true ! RefreshAllSettings $ nameplateUseClassColorForFriendlyPlayerUnitNames=1 # RF"),
    -- Show Health Percent: off, or its side of the bar (the right is saved as no side)
    C("FRIENDLY PLAYERS|Show Health Percent", "plate",
        "dropdown [none=None,right=Right,left=Left,center=Center]",
        "*: get \"right\" <friendlyHealthTextPos,friendlyHideHealthText>",
        "*: \"none\" > friendlyHideHealthText=true ! RefreshFriendlyHealthText # F",
        "*: \"right\" > friendlyHideHealthText=false,friendlyHealthTextPos=nil ! RefreshFriendlyHealthText # F",
        "*: \"left\" > friendlyHideHealthText=false,friendlyHealthTextPos=\"left\" ! RefreshFriendlyHealthText # F",
        "*: \"center\" > friendlyHideHealthText=false,friendlyHealthTextPos=\"center\" ! RefreshFriendlyHealthText # F"),
    -- Friendly Name Size: under this build the health bar plates' (FRIENDLY_NO: Name Only's)
    C("FRIENDLY PLAYERS|Friendly Name Size", "plate",
        "slider 6..30/1",
        "*: get 12 <friendlyNameTextSize>",
        "*: 15 > friendlyNameTextSize=15 ! RefreshFriendlyNameTextSize # F"),
    C("FRIENDLY PLAYERS|Friendly Name Size|cog:Nameplate Offset", "plate",
        "cog of 1 row"),
    C("FRIENDLY PLAYERS|Friendly Name Size|cog:Nameplate Offset|Distance", "plate",
        "slider -50..50/1",
        "*: get 0 <friendlyPlateYOffset>",
        "*: -13 > friendlyPlateYOffset=-13 ! RefreshFriendlyPlateYOffset"),
    C("FRIENDLY PLAYERS|Player Name Format", "players",
        "dropdown [full=Full Name,first=First Name,last=Last Name,abbr=Abbreviated,custom]",
        "*: get \"full\" <friendlyNameFormat>",
        "*: \"full\" > friendlyNameFormat=nil ! NP_SyncFriendlyNameFormat # F",
        "*: \"first\" > friendlyNameFormat=\"first\" ! NP_SyncFriendlyNameFormat # F",
        "*: \"last\" > friendlyNameFormat=\"last\" ! NP_SyncFriendlyNameFormat # F",
        "*: \"abbr\" > friendlyNameFormat=\"abbr\" ! NP_SyncFriendlyNameFormat # F",
        "*: 12 > friendlyNameFormat=12 ! NP_SyncFriendlyNameFormat # F"),
    -- Level Text: one dropdown over friendlyShowLevel and friendlyLevelDiffColor
    C("FRIENDLY PLAYERS|Level Text", "players",
        "dropdown [none=None,plain=Plain Colored,diff=Difficulty Colored]",
        "S1: get \"none\" <friendlyShowLevel>",
        "S2: get \"plain\" <friendlyLevelDiffColor,friendlyShowLevel>",
        "S3: get \"plain\" <friendlyLevelDiffColor,friendlyShowLevel>",
        "*: \"none\" > friendlyShowLevel=false ! RefreshFriendlyBelowName # F",
        "*: \"plain\" > friendlyShowLevel=true,friendlyLevelDiffColor=false ! RefreshFriendlyBelowName # F",
        "*: \"diff\" > friendlyShowLevel=true,friendlyLevelDiffColor=true ! RefreshFriendlyBelowName # F"),
    -- Subtitle Text: a checklist; its stand-in dropdown reads the keys the checklist writes
    C("FRIENDLY PLAYERS|Subtitle Text", nil,
        "dropdown",
        "*: get \"__placeholder\" <friendlyBelowName,friendlyBelowNameGuildBrackets>"),
    C("FRIENDLY PLAYERS|Subtitle Text|check:title", "players",
        "check Player Title",
        "S1: get false <friendlyBelowName>",
        "S2: get true <friendlyBelowName>",
        "S3: get true <friendlyBelowName>",
        "S1: true > friendlyBelowName=\"title\" ! RefreshFriendlyBelowName # RF",
        "S2: true > friendlyBelowName=\"both\" ! RefreshFriendlyBelowName # RF",
        "S3: true > friendlyBelowName=\"both\" ! RefreshFriendlyBelowName # RF",
        "S1: false > friendlyBelowName=\"none\" ! RefreshFriendlyBelowName # RF",
        "S2: false > friendlyBelowName=\"guild\" ! RefreshFriendlyBelowName # RF",
        "S3: false > friendlyBelowName=\"guild\" ! RefreshFriendlyBelowName # RF"),
    -- the guild line's two forms: a tick of one saves its brackets and shows the line
    C("FRIENDLY PLAYERS|Subtitle Text|check:guild", "players",
        "check Guild Name",
        "S1: get false <friendlyBelowName>",
        "S2: get false <friendlyBelowName,friendlyBelowNameGuildBrackets>",
        "S3: get false <friendlyBelowName,friendlyBelowNameGuildBrackets>",
        "S1: true > friendlyBelowNameGuildBrackets=false,friendlyBelowName=\"guild\" ! RefreshFriendlyBelowName # RF",
        "S2: true > friendlyBelowNameGuildBrackets=false,friendlyBelowName=\"both\" ! RefreshFriendlyBelowName # RF",
        "S3: true > friendlyBelowNameGuildBrackets=false,friendlyBelowName=\"both\" ! RefreshFriendlyBelowName # RF",
        "S1: false > friendlyBelowName=\"none\" ! RefreshFriendlyBelowName # RF",
        "S2: false > friendlyBelowName=\"title\" ! RefreshFriendlyBelowName # RF",
        "S3: false > friendlyBelowName=\"title\" ! RefreshFriendlyBelowName # RF"),
    C("FRIENDLY PLAYERS|Subtitle Text|check:guildB", "players",
        "check <Guild Name>",
        "S1: get false <friendlyBelowName>",
        "S2: get true <friendlyBelowName,friendlyBelowNameGuildBrackets>",
        "S3: get true <friendlyBelowName,friendlyBelowNameGuildBrackets>",
        "S1: true > friendlyBelowNameGuildBrackets=true,friendlyBelowName=\"guild\" ! RefreshFriendlyBelowName # RF",
        "S2: true > friendlyBelowNameGuildBrackets=true,friendlyBelowName=\"both\" ! RefreshFriendlyBelowName # RF",
        "S3: true > friendlyBelowNameGuildBrackets=true,friendlyBelowName=\"both\" ! RefreshFriendlyBelowName # RF",
        "S1: false > friendlyBelowName=\"none\" ! RefreshFriendlyBelowName # RF",
        "S2: false > friendlyBelowName=\"title\" ! RefreshFriendlyBelowName # RF",
        "S3: false > friendlyBelowName=\"title\" ! RefreshFriendlyBelowName # RF"),
    -- Subtitle Text's cog: the guild line's size, nearest the checklist
    C("FRIENDLY PLAYERS|Subtitle Text|cog:Subtitle Text Settings", "guildSize",
        "cog of 1 row"),
    C("FRIENDLY PLAYERS|Subtitle Text|cog:Subtitle Text Settings|Guild Text Size", "guildSize",
        "slider 6..30/1",
        "*: get 12 <friendlyBelowNameSize>",
        "*: 15 > friendlyBelowNameSize=15 ! RefreshFriendlyBelowName # F"),
    -- the guild line's colour: the Custom | Class pair, inline left of the cog
    C("FRIENDLY PLAYERS|Subtitle Text|inline:Custom Guild Color", "guildCustom",
        "color",
        "*: get 0.8,0.8,0.8 <friendlyBelowNameColor>",
        "*: 0.25,0.5,0.75 > friendlyBelowNameColor={b=0.75,g=0.5,r=0.25} ! RefreshFriendlyBelowName # F"),
    C("FRIENDLY PLAYERS|Subtitle Text|inline:Custom Guild Color|click", "guildCustom",
        "click",
        "S1: click >  ! picker",
        "S2: click > friendlyBelowNameClassColor=false ! RefreshFriendlyBelowName # RF",
        "S3: click >  ! picker"),
    C("FRIENDLY PLAYERS|Subtitle Text|inline:Class Guild Color", "guildClass",
        "color",
        "*: get 0.25,0.78,0.92 <>",
        "*: 0.25,0.5,0.75 >  => 0.25,0.78,0.92"),
    C("FRIENDLY PLAYERS|Subtitle Text|inline:Class Guild Color|click", "guildClass",
        "click",
        "*: click > friendlyBelowNameClassColor=true ! RefreshFriendlyBelowName # RF"),
    C("FRIENDLY PLAYERS|Friendly Names Not Clickable", nil,
        "toggle",
        "*: get false <friendlyClickThrough>",
        "*: true > friendlyClickThrough=true ! UpdateFriendlyClickThrough",
        "*: false > friendlyClickThrough=false ! UpdateFriendlyClickThrough"),
    C("FRIENDLY PLAYERS|Target Border Effects", "borderFx",
        "toggle",
        "*: get false <friendlyTargetBorderFx>",
        "*: true > friendlyTargetBorderFx=true ! fplate:ApplyTarget # U",
        "*: false > friendlyTargetBorderFx=false ! fplate:ApplyTarget # U"),
    C("FRIENDLY NPCS|Show Friendly NPC Nameplates", nil,
        "toggle",
        "S1: get false <showFriendlyNPCs>",
        "S2: get true <showFriendlyNPCs>",
        "S3: get true <showFriendlyNPCs>",
        "*: true > showFriendlyNPCs=true ! UpdateFriendlyNameplateSystem $ nameplateShowFriendlyNPCs=1,nameplateShowFriendlyNpcs=1 # RF",
        "*: false > showFriendlyNPCs=false ! UpdateFriendlyNameplateSystem $ nameplateShowFriendlyNPCs=0,nameplateShowFriendlyNpcs=0 # RF"),
    C("FRIENDLY NPCS|Show Friendly NPC Nameplates|swatch#1", "npcColor",
        "color",
        "S1: tip Requires Show Friendly NPC Nameplates to be enabled",
        "S2: tip Requires Friendly Nameplate Style set to Nameplate",
        "S3: tip NPC Bar & Name Color",
        "*: get 0,1,0 <friendlyNPCColor>",
        "*: 0.25,0.5,0.75 > friendlyNPCColor={b=0.75,g=0.5,r=0.25} ! RefreshFriendlyColors # F"),
    C("FRIENDLY NPCS|Show Friendly NPC Nameplates|swatch#1|click", "npcColor",
        "click",
        "S1: click > ",
        "S2: click > ",
        "S3: click >  ! picker"),
    C("FRIENDLY NPCS|Friendly NPC Name Format", "npc",
        "dropdown [full=Full Name,first=First Name,last=Last Name,abbr=Abbreviated,custom]",
        "*: get \"full\" <friendlyNPCNameFormat>",
        "*: \"full\" > friendlyNPCNameFormat=nil ! RefreshAllNPCOverlays # F",
        "*: \"first\" > friendlyNPCNameFormat=\"first\" ! RefreshAllNPCOverlays # F",
        "*: \"last\" > friendlyNPCNameFormat=\"last\" ! RefreshAllNPCOverlays # F",
        "*: \"abbr\" > friendlyNPCNameFormat=\"abbr\" ! RefreshAllNPCOverlays # F",
        "*: 12 > friendlyNPCNameFormat=12 ! RefreshAllNPCOverlays # F"),
    C("FRIENDLY NPCS|Show NPC Titles", "npc",
        "toggle",
        "*: get true <showNPCTitles>",
        "*: true > showNPCTitles=true ! RefreshAllNPCOverlays # RF",
        "*: false > showNPCTitles=false ! RefreshAllNPCOverlays # RF"),
    C("FRIENDLY NPCS|Show Raid Marker", "npcMarker",
        "toggle",
        "*: get true <showNPCRaidMarker>",
        "*: true > showNPCRaidMarker=true ! RefreshAllNPCOverlays # RF",
        "*: false > showNPCRaidMarker=false ! RefreshAllNPCOverlays # RF"),
    C("FRIENDLY NPCS|Friendly NPC Name Size", "npc",
        "slider 6..30/1",
        "*: get 13 <friendlyNPCNameSize>",
        "*: 15 > friendlyNPCNameSize=15 ! RefreshNPCOverlayStyle # F"),
    C("FRIENDLY NPCS|Friendly NPC Name Size|inline:Name Color", "npc",
        "color",
        "*: get 0,1,0 <friendlyNPCNameColor>",
        "*: 0.25,0.5,0.75 > friendlyNPCNameColor={b=0.75,g=0.5,r=0.25} ! RefreshNPCOverlayStyle # F"),
    C("FRIENDLY NPCS|Friendly NPC Title Size", "npcTitle",
        "slider 6..30/1",
        "*: get 10 <friendlyNPCTitleSize>",
        "*: 15 > friendlyNPCTitleSize=15 ! RefreshNPCOverlayStyle # F"),
    C("FRIENDLY NPCS|Friendly NPC Title Size|inline:Title Color", "npcTitle",
        "color rgba",
        "*: get 0,1,0,0.7 <friendlyNPCTitleColor>",
        "*: 0.25,0.5,0.75,0.4 > friendlyNPCTitleColor={a=0.4,b=0.75,g=0.5,r=0.25} ! RefreshNPCOverlayStyle # F"),
}
EXPECT[GENERAL] = {
    C("NAMEPLATE SPACING|Stacking Nameplates"),
    C("NAMEPLATE SPACING|Stacking Nameplates|check:enemy"),
    C("NAMEPLATE SPACING|Stacking Nameplates|check:friendly"),
    C("NAMEPLATE SPACING|Stacked Nameplate Spacing"),
    C("NAMEPLATE SPACING|Hitbox Size X"),
    C("NAMEPLATE SPACING|Hitbox Size Y"),
    C("NAMEPLATE SPACING|Stacking Speed"),
    C("NAMEPLATE SPACING|Top Screen Inset"),
    C("EXTRA AURA OPTIONS|Max Debuffs"),
    C("EXTRA AURA OPTIONS|Show Buff / Debuff Tooltips"),
    RetailOnly(C("EXTRA AURA OPTIONS|Pandemic Glow Style")),
    RetailOnly(C("EXTRA AURA OPTIONS|Pandemic Glow Preview")),
    C("EXTRA AURA OPTIONS|Enemy Buff Filter"),
    RetailOnly(C("EXTRA AURA OPTIONS|Enemy Buff Filter|cog:Enemy Buff Filter")),
    RetailOnly(C("EXTRA AURA OPTIONS|Enemy Buff Filter|cog:Enemy Buff Filter|Dispellable By Me")),
    C("EXTRA AURA OPTIONS|Dispel Glow Style"),
    C("EXTRAS|Scale Nameplate On Cast"),
    C("EXTRAS|Hide Enemy Name While Casting"),
    C("EXTRAS|Name Raid Marker"),
    C("EXTRAS|Name Raid Marker|cog:Name Raid Marker"),
    C("EXTRAS|Name Raid Marker|cog:Name Raid Marker|Size"),
    C("EXTRAS|Experimental: Cast Lockout as CC Icon"),
    C("EXTRAS|Out of Combat Opacity"),
    C("EXTRAS|Line of Sight Opacity"),
    C("EXTRAS|Range Check"),
    C("EXTRAS|Range Check|cog:Range Check"),
    C("EXTRAS|Range Check|cog:Range Check|Custom Range"),
    C("EXTRAS|Out of Range Opacity"),
    C("EXTRAS|Execute Pulse Glow"),
    C("EXTRAS|Hide Enemy Nameplates out of Combat"),
    C("EXTRAS|Minor Enemy Scale (Percent)", nil,
        "slider 25..125/5",
        "*: get 100 <minorEnemyScale>",
        "*: 60 > minorEnemyScale=60 ! NP_RefreshTypeScaleSetting"),
    C("EXTRAS|Non-Elite Enemy Scale (Percent)", nil,
        "slider 25..125/5",
        "*: get 100 <nonEliteEnemyScale>",
        "*: 60 > nonEliteEnemyScale=60 ! NP_RefreshTypeScaleSetting"),
    C("EXTRAS|Show Enemy Pet Nameplates", nil,
        "toggle",
        "*: get false <showEnemyPets>",
        "*: true > showEnemyPets=true $ nameplateShowEnemyPets=1",
        "*: false > showEnemyPets=false $ nameplateShowEnemyPets=0"),
}
EXPECT[FRIENDLY_NO] = {}
do
    local SWAP = {
        ["FRIENDLY PLAYERS|Friendly Name Size"] = C("FRIENDLY PLAYERS|Friendly Name Size", "nameOnly",
            "slider 8..30/1",
            "*: get 15 <friendlyNameSize>",
            "*: 16 > friendlyNameSize=16 ! RefreshFriendlyNameSize # F"),
        ["FRIENDLY PLAYERS|Friendly Name Size|cog:Nameplate Offset"] = C("FRIENDLY PLAYERS|Friendly Name Size|cog:Name Distance", "nameOnly",
            "cog of 1 row"),
        ["FRIENDLY PLAYERS|Friendly Name Size|cog:Nameplate Offset|Distance"] = C("FRIENDLY PLAYERS|Friendly Name Size|cog:Name Distance|Distance", "nameOnly",
            "slider -50..50/1",
            "*: get -20 <friendlyNameOnlyYOffset>",
            "*: -13 > friendlyNameOnlyYOffset=-13 ! RefreshFriendlyNameOnlyOffset"),
    }
    local n = 0
    for _, row in ipairs(EXPECT[FRIENDLY]) do
        local barRow = row.id == "FRIENDLY PLAYERS|Health Bar Width" or row.id == "FRIENDLY PLAYERS|Health Bar Height"
            or row.id == "FRIENDLY PLAYERS|Show Health Percent" or row.id:find("FRIENDLY PLAYERS|Health Bar Color|", 1, true) == 1
        if barRow then n = n + 1 else EXPECT[FRIENDLY_NO][#EXPECT[FRIENDLY_NO] + 1] = SWAP[row.id] or row end
    end
    assert(n == 7 and #EXPECT[FRIENDLY_NO] == #EXPECT[FRIENDLY] - 7, "the health bar rows' controls are not the seven the test leaves out")
end
local function Rows(name, forever)
    local out = {}
    for _, row in ipairs(EXPECT[name]) do
        if not (forever and row.retail) then out[#out + 1] = row end
    end
    return out
end

-- The saved keys the three sections these pages were made from wrote (OTHER
-- NAMEPLATES and TARGET AND FOCUS EFFECTS of the General page, TARGET, FOCUS &
-- HOVER EFFECTS of the Display page), each with the control that writes it
-- now: T, F or E (Target, Focus & Hover, Friendly Plates, Extras) | its id. A
-- key several controls write lists them all; no other control writes one.
local DRIVER = {
    -- OTHER NAMEPLATES
    classColorFriendly = { "F|FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color", "F|FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color|click",
        "F|FRIENDLY PLAYERS|Health Bar Color|ms:Class Color|click" },
    friendlyBarColor = "F|FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color",
    friendlyBelowName = { "F|FRIENDLY PLAYERS|Subtitle Text|check:title", "F|FRIENDLY PLAYERS|Subtitle Text|check:guild",
        "F|FRIENDLY PLAYERS|Subtitle Text|check:guildB" },
    friendlyBelowNameClassColor = { "F|FRIENDLY PLAYERS|Subtitle Text|inline:Custom Guild Color|click",
        "F|FRIENDLY PLAYERS|Subtitle Text|inline:Class Guild Color|click" },
    friendlyBelowNameColor = "F|FRIENDLY PLAYERS|Subtitle Text|inline:Custom Guild Color",
    friendlyBelowNameSize = "F|FRIENDLY PLAYERS|Subtitle Text|cog:Subtitle Text Settings|Guild Text Size",
    friendlyBelowNameGuildBrackets = { "F|FRIENDLY PLAYERS|Subtitle Text|check:guild", "F|FRIENDLY PLAYERS|Subtitle Text|check:guildB" },
    friendlyClickThrough = "F|FRIENDLY PLAYERS|Friendly Names Not Clickable",
    friendlyGroupBrackets = "F|FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings|Show [] Around Group/Raid",
    friendlyHealthBarHeight = "F|FRIENDLY PLAYERS|Health Bar Height",
    friendlyHealthBarWidth = "F|FRIENDLY PLAYERS|Health Bar Width",
    -- (new with the dropdown: the side of the bar, saved only for the left and the centre)
    friendlyHealthTextPos = "F|FRIENDLY PLAYERS|Show Health Percent",
    friendlyHideHealthText = "F|FRIENDLY PLAYERS|Show Health Percent",
    friendlyLevelDiffColor = "F|FRIENDLY PLAYERS|Level Text",
    friendlyNPCColor = "F|FRIENDLY NPCS|Show Friendly NPC Nameplates|swatch#1",
    friendlyNPCNameColor = "F|FRIENDLY NPCS|Friendly NPC Name Size|inline:Name Color",
    friendlyNPCNameFormat = "F|FRIENDLY NPCS|Friendly NPC Name Format",
    friendlyNPCNameSize = "F|FRIENDLY NPCS|Friendly NPC Name Size",
    friendlyNPCTitleColor = "F|FRIENDLY NPCS|Friendly NPC Title Size|inline:Title Color",
    friendlyNPCTitleSize = "F|FRIENDLY NPCS|Friendly NPC Title Size",
    -- (friendlyNameClassColor is read, never written: Name Color's older key for the health bar plates)
    friendlyNameColor = "F|FRIENDLY PLAYERS|Name Color|ms:Custom Color",
    friendlyNameColorMode = { "F|FRIENDLY PLAYERS|Name Color|ms:Custom Color", "F|FRIENDLY PLAYERS|Name Color|ms:Custom Color|click",
        "F|FRIENDLY PLAYERS|Name Color|ms:Class Color|click" },
    friendlyNameFormat = "F|FRIENDLY PLAYERS|Player Name Format",
    friendlyNameOnly = "F|FRIENDLY PLAYERS|Friendly Nameplate Style",
    -- (N: the page as built under Name Only, whose name size row holds that style's slider)
    friendlyNameOnlyYOffset = "N|FRIENDLY PLAYERS|Friendly Name Size|cog:Name Distance|Distance",
    friendlyNameSize = "N|FRIENDLY PLAYERS|Friendly Name Size",
    friendlyNameTextSize = "F|FRIENDLY PLAYERS|Friendly Name Size",
    friendlyPlateYOffset = "F|FRIENDLY PLAYERS|Friendly Name Size|cog:Nameplate Offset|Distance",
    friendlyShowLevel = "F|FRIENDLY PLAYERS|Level Text",
    friendlyTargetBorderFx = "F|FRIENDLY PLAYERS|Target Border Effects",
    nameplateSize = "F|FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings|Blizzard Nameplate Size",
    showEnemyPets = "E|EXTRAS|Show Enemy Pet Nameplates",
    showFriendlyNPCs = "F|FRIENDLY NPCS|Show Friendly NPC Nameplates",
    showFriendlyPlayers = "F|FRIENDLY PLAYERS|Friendly Nameplate Style",
    showNPCRaidMarker = "F|FRIENDLY NPCS|Show Raid Marker",
    showNPCTitles = "F|FRIENDLY NPCS|Show NPC Titles",
    -- TARGET AND FOCUS EFFECTS
    focusCastHeight = "T|FOCUS|Focus Cast Height",
    focusLetterAnchor = "T|FOCUS|Focus Letter",
    focusLetterEnabled = "T|FOCUS|Focus Letter",
    focusLetterSize = "T|FOCUS|Focus Letter|cog:Focus Letter|Size",
    focusLetterX = "T|FOCUS|Focus Letter|cog:Focus Letter|X",
    focusLetterY = "T|FOCUS|Focus Letter|cog:Focus Letter|Y",
    hashLineColor = "T|TARGET|Show Hash Line on Target|swatch#1",
    hashLineEnabled = "T|TARGET|Show Hash Line on Target",
    hashLinePercent = "T|TARGET|Hash Line Location",
    minorEnemyScale = "E|EXTRAS|Minor Enemy Scale (Percent)",
    nonEliteEnemyScale = "E|EXTRAS|Non-Elite Enemy Scale (Percent)",
    nonTargetAlpha = "T|TARGET|Non-Target Opacity",
    nonTargetCastFull = "T|TARGET|Non-Target Opacity|cog:Non-Target Opacity|Full Opacity While Casting",
    nonTargetCastImportantOnly = "T|TARGET|Non-Target Opacity|cog:Non-Target Opacity|Full Opacity While Casting",
    nonTargetKeepFocus = "T|TARGET|Non-Target Opacity|cog:Non-Target Opacity|Keep Focus Full Opacity",
    rangeTextColor = "T|TARGET|Distance to Target Text|swatch#1",
    rangeTextEnabled = "T|TARGET|Distance to Target Text",
    rangeTextOffsetX = "T|TARGET|Distance to Target Text|cog:Distance Text|Offset X",
    rangeTextOffsetY = "T|TARGET|Distance to Target Text|cog:Distance Text|Offset Y",
    rangeTextSize = "T|TARGET|Distance to Target Text|cog:Distance Text|Text Size",
    targetScale = "T|TARGET|Scale Target Nameplate",
    -- TARGET, FOCUS & HOVER EFFECTS
    focus = "T|FOCUS|Focus Color|swatch#1",
    focusColorEnabled = "T|FOCUS|Focus Color",
    focusOverlayAlpha = "T|FOCUS|Focus Texture|cog:Focus Texture|Opacity",
    focusOverlayColor = "T|FOCUS|Focus Texture|swatch#1",
    focusOverlayFullBgAlpha = "T|FOCUS|Focus Texture|cog:Focus Texture|Full alpha on empty part of bar",
    focusOverlayNoTint = "T|FOCUS|Focus Texture|cog:Focus Texture|Don't tint (keep bar's own color)",
    focusOverlayTexture = "T|FOCUS|Focus Texture",
    hoverAlpha = "T|HOVER|Hover Effect|cog:More Effects|Highlight Opacity",
    hoverBorderColor = "T|HOVER|Hover Effect|swatch#1",
    hoverBorderSizeValue = { "T|HOVER|Hover Effect|check:borderSize",
        "T|HOVER|Hover Effect|cog:More Effects|Border Size" },
    hoverColor = "T|HOVER|Hover Effect|cog:More Effects|Highlight Color",
    hoverGlowAlpha = "T|HOVER|Hover Effect|cog:More Effects|Glow Opacity",
    hoverGlowBorderColor = "T|HOVER|Hover Effect|check:borderColor",
    hoverGlowBorderSize = "T|HOVER|Hover Effect|check:borderSize",
    hoverGlowColor = "T|HOVER|Hover Effect|swatch#2",
    hoverGlowEllesmereUI = "T|HOVER|Hover Effect|check:ellesmereui",
    hoverGlowHighlight = "T|HOVER|Hover Effect|check:highlight",
    hoverOverlayFullBgAlpha = "T|HOVER|Hover Texture|cog:Hover Texture|Full alpha on empty part of bar",
    hoverOverlayTexture = "T|HOVER|Hover Texture",
    showTargetArrows = "T|TARGET|Target Arrows",
    target = "T|TARGET|Target Color|swatch#1",
    targetArrowClassColor = { "T|TARGET|Target Arrows|swatch#1",
        "T|TARGET|Target Arrows|swatch#1|click",
        "T|TARGET|Target Arrows|swatch#2|click" },
    targetArrowColor = "T|TARGET|Target Arrows|swatch#1",
    targetArrowScale = "T|TARGET|Target Arrows|cog:Arrow Scale|Scale",
    targetArrowStyle = "T|TARGET|Target Arrows",
    targetBorderColor = "T|TARGET|Target Effect|swatch#1",
    targetBorderSizeValue = { "T|TARGET|Target Effect|check:borderSize",
        "T|TARGET|Target Effect|cog:More Effects|Border Size" },
    targetColorEnabled = "T|TARGET|Target Color",
    targetGlowAlpha = "T|TARGET|Target Effect|cog:More Effects|Glow Opacity",
    targetGlowBorderColor = "T|TARGET|Target Effect|check:borderColor",
    targetGlowBorderSize = "T|TARGET|Target Effect|check:borderSize",
    targetGlowColor = "T|TARGET|Target Effect|swatch#2",
    targetGlowEllesmereUI = "T|TARGET|Target Effect|check:ellesmereui",
    targetGlowHighlight = "T|TARGET|Target Effect|check:highlight",
    targetHighlightAlpha = "T|TARGET|Target Effect|cog:More Effects|Highlight Opacity",
    targetHighlightColor = "T|TARGET|Target Effect|cog:More Effects|Highlight Color",
    targetOverlayAlpha = "T|TARGET|Target Texture|cog:Target Texture|Opacity",
    targetOverlayColor = "T|TARGET|Target Texture|swatch#1",
    targetOverlayFullBgAlpha = "T|TARGET|Target Texture|cog:Target Texture|Full alpha on empty part of bar",
    targetOverlayNoTint = "T|TARGET|Target Texture|cog:Target Texture|Don't tint (keep bar's own color)",
    targetOverlayTexture = "T|TARGET|Target Texture",
}

-- The tooltips of the rows that changed page or left a cog (their labels and
-- their gates' tooltips are in EXPECT and GATE).
local TIPS = {
    [TFH] = {
        ["TARGET|Scale Target Nameplate"] = "Scales your current target's nameplate. 100% = no change.",
        ["TARGET|Non-Target Opacity"] = "Fades enemy nameplates that are not your current target or focus while you have a target. 100 = no fading.",
        ["TARGET|Non-Target Opacity|cog:Non-Target Opacity|Keep Focus Full Opacity"] = "Your focus target's nameplate never fades with Non-Target Opacity or Out of Combat Opacity.",
        ["TARGET|Non-Target Opacity|cog:Non-Target Opacity|Full Opacity While Casting"] = "A casting enemy's nameplate skips Non-Target Opacity while the cast lasts.",
        ["TARGET|Distance to Target Text"] = "Shows the approximate distance to your current target on its nameplate as a range bracket, e.g. 15+ when the target is 15-20 yards away.",
        ["TARGET|Target Texture|cog:Target Texture|Don't tint (keep bar's own color)"] = "Tints the pattern with the bar's current color instead of the custom overlay color.",
        ["FOCUS|Focus Texture|cog:Focus Texture|Don't tint (keep bar's own color)"] = "Tints the pattern with the bar's current color instead of the custom overlay color.",
        ["FOCUS|Focus Cast Height"] = "Increases the cast bar height on your focus target's nameplate. 100% = normal height.",
        ["FOCUS|Focus Letter"] = "Draws a white letter F on your current focus target's nameplate.",
        ["HOVER|Hover Texture"] = "Uses the Hover Effect color and opacity. Set to None for the flat hover highlight.",
    },
    [FRIENDLY] = {
        ["FRIENDLY PLAYERS|Subtitle Text|cog:Subtitle Text Settings|Guild Text Size"] = "Size of the guild line under friendly player names.",
        ["FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings|Blizzard Nameplate Size"] = "Size of Blizzard's own nameplates, which still show for friendly players inside instances. Default is 3.",
        ["FRIENDLY PLAYERS|Target Border Effects"] = "Also applies the target Border Color and Border Size effects to friendly nameplates.",
        ["FRIENDLY PLAYERS|Subtitle Text"] = "Show the player's title inline with their name, and/or their guild on a line below it, on friendly nameplates.",
        ["FRIENDLY PLAYERS|Friendly Nameplate Style|cog:Friendly Nameplate Settings|Show [] Around Group/Raid"] = "Blue [Name] for party members and your raid subgroup, orange for other raid members. Not inside instances.",
        ["FRIENDLY PLAYERS|Friendly Names Not Clickable"] = "Make friendly player and NPC nameplates click-through so their names never block your mouse or cause accidental friendly targeting.\n\nUse this when friendly names get in the way of clicking the world or the enemy nameplates behind them.",
    },
    [FRIENDLY_NO] = {
        ["FRIENDLY PLAYERS|Friendly Name Size"] = "Adjusts the size of friendly player names shown in Name Only mode. Default is 15.",
    },
    [GENERAL] = {
        ["EXTRAS|Minor Enemy Scale (Percent)"] = "Scales the nameplates of minor and trivial enemies; 100% = no change.",
        ["EXTRAS|Non-Elite Enemy Scale (Percent)"] = "Scales the nameplates of non-elite enemies in dungeons only; 100% = no change.",
        ["EXTRAS|Show Enemy Pet Nameplates"] = "Toggle visibility of enemy pet nameplates.",
    },
}

local function StateText(state, style)
    local t = {}
    for k, v in pairs(state) do t[#t + 1] = k .. "=" .. tostring(v) end
    table.sort(t)
    return "{" .. table.concat(t, ",") .. "} " .. style.active .. (style.forever and "+forever" or "")
end

-------------------------------------------------------------------------------
-- 1. The registration: pages, tab labels, dispatch, header builders
-------------------------------------------------------------------------------
local function CheckRegistration(Wd, tag, forever)
    eq(#Wd.loadErrors, 0, tag .. ": the options files do not all load: " .. tostring(Wd.loadErrors[1]))
    if not check(Wd.cfg ~= nil, tag .. ": the module is not registered") then return false end
    eq(Wd.partFrames, 0, tag .. ": frames made by loading the page files (definitions only)")
    eq(Wd.partOnShow, 0, tag .. ": panel-show callbacks registered by loading the page files")
    eq(Wd.partEvents, 0, tag .. ": events registered by loading the page files")
    eq(table.concat(Wd.events, ","), "PLAYER_LOGIN,PLAYER_SPECIALIZATION_CHANGED", tag .. ": the events the main file listens to")
    eq(Wd.onShowAtLoad, 1, tag .. ": panel-show callbacks at load (the nameplate preview's)")
    eq(Wd.folder, FOLDER, tag .. ": the module's folder")
    eq(table.concat(Wd.cfg.pages, " / "), "Display / Colors / Target, Focus & Hover / Friendly Plates / General", tag .. ": the pages, in tab order")
    local labels = {}
    for k, v in pairs(Wd.cfg.tabLabels or {}) do labels[#labels + 1] = k .. "=" .. v end
    table.sort(labels)
    eq(table.concat(labels, ","), "Colors=Enemy Colors,Display=Enemy,Friendly Plates=Friendly,General=Extras", tag .. ": the tab labels")
    -- each page is built by its own builder, handed the page's arguments
    local BUILDERS = { [GENERAL] = "NPO_BuildGeneralPage", [COLORS] = "NPO_BuildColorsPage",
        [TFH] = "NPO_BuildTargetFocusHoverPage", [FRIENDLY] = "NPO_BuildFriendlyPage" }
    local real, seen = {}, nil
    for _, fnName in pairs(BUILDERS) do
        real[fnName] = nsData[fnName]
        check(type(real[fnName]) == "function", tag .. ": ns." .. fnName .. " is not defined")
        nsData[fnName] = function(a, b, c) seen = { fnName, a, b, c }; return "built:" .. fnName end
    end
    for page, fnName in pairs(BUILDERS) do
        local parent = {}
        seen = nil
        local res = Wd.cfg.buildPage(page, parent, -6)
        check(res == "built:" .. fnName and seen and seen[1] == fnName and seen[2] == page and seen[3] == parent and seen[4] == -6,
            tag .. ": the " .. page .. " page is not built by ns." .. fnName .. " with the page's own arguments (" .. tostring(seen and seen[1]) .. ")")
    end
    for fnName, fn in pairs(real) do nsData[fnName] = fn end
    eq(Wd.cfg.buildPage("Nameplates", {}, -6), nil, tag .. ": a page that does not exist builds something")
    H.SetState({})
    H.ResetLog()
    local d = H.Build(Wd, DISPLAY)
    check(d.ok, tag .. ": the Display page does not build: " .. tostring(d.result))
    eq(table.concat(LOG.calls, ","), "DisplayLayout,DisplayBars", tag .. ": the builders the Display page calls")
    local pv = Wd.previews[#Wd.previews]
    check(pv and d.header and pv.mode == nil and pv.parent == d.header.frame,
        tag .. ": the Enemies header does not build the preview as an untargeted plate (no mode)")
    check(d.header and type(d.header.height) == "number" and Wd.cfg.getHeaderBuilder(DISPLAY) == d.header.builder,
        tag .. ": getHeaderBuilder does not hand out the Display page's header builder")
    check(type(nsData.NPO_BuildTFHHeader) == "function" and Wd.cfg.getHeaderBuilder(TFH) == nsData.NPO_BuildTFHHeader,
        tag .. ": getHeaderBuilder does not hand out ns.NPO_BuildTFHHeader for Target, Focus & Hover")
    check(type(nsData.NPO_BuildFriendlyHeader) == "function" and Wd.cfg.getHeaderBuilder(FRIENDLY) == nsData.NPO_BuildFriendlyHeader,
        tag .. ": getHeaderBuilder does not hand out ns.NPO_BuildFriendlyHeader for Friendly Plates")
    check(Wd.cfg.getHeaderBuilder(COLORS) == nil and Wd.cfg.getHeaderBuilder(GENERAL) == nil,
        tag .. ": the Colors or the General page has a header builder")
    -- the glow sites still point at the pages by their identities
    local sites = {}
    for _, s in ipairs(Wd.sites) do sites[#sites + 1] = s.id .. "@" .. tostring(s.page) end
    eq(table.concat(sites, " "), "np_dispel@General " .. (forever and "" or "np_pandemic@General ") .. "np_importantcast@Display np_casttarget@Display",
        tag .. ": the glow sites and their pages")
    return true
end

-------------------------------------------------------------------------------
-- 2. A page: it builds, its layout, the widget rules, its header
-------------------------------------------------------------------------------
local function CheckPage(Wd, tag, name, want, state)
    H.SetState(state or {})
    H.ResetLog()
    local page = H.Build(Wd, name)
    H.SetState({})
    if not check(page.ok, tag .. ": the " .. name .. " page does not build: " .. tostring(page.result):sub(1, 400)) then return nil end
    check(type(page.result) == "number" and page.result > 0, tag .. ": " .. name .. " does not return its height")
    check(page.parent._showRowDivider == true, tag .. ": " .. name .. " does not switch the row divider on")
    Compare(tag .. ": the sections and rows of " .. name, page.items, want)
    -- a blank half only as the last half of a section
    for i, r in ipairs(page.rows) do
        local lb, rb = r.l.text == nil or r.l.text == "", r.r.text == nil or r.r.text == ""
        local last = not page.rows[i + 1] or page.rows[i + 1].section ~= r.section
        check(not lb and (not rb or last), tag .. ": " .. name .. ", row " .. i .. " of " .. tostring(r.section) .. " has a blank half inside its section")
    end
    -- a cog sits nearest its control; the row's swatches chain left of it
    local cogOf = {}
    for _, cog in ipairs(page.cogs) do
        cogOf[cog.rgn] = cog.btn
        check(cog.btn._anchor == cog.rgn._control, tag .. ": " .. name .. ", the cog '" .. tostring(cog.opts.title) .. "' is not the inline item nearest its control")
        check(type(cog.opts.title) == "string" and #(cog.opts.rows or {}) > 0, tag .. ": " .. name .. ", a cog has no title or no rows")
    end
    for _, sw in ipairs(page.swatches) do
        check(sw.frame._anchor ~= nil and (not cogOf[sw.rgn] or sw.frame._anchor ~= sw.rgn._control),
            tag .. ": " .. name .. ", a swatch of '" .. tostring(sw.host and sw.host.text) .. "' is not placed, or sits between its control and the row's cog")
    end
    -- Friendly Plates: a half's hand-placed swatches end as its last inline item (the
    -- leftmost one, which the half's label is kept clear of)
    if name == FRIENDLY then
        for _, sw in ipairs(page.swatches) do
            local last, leftmost = sw.rgn._lastInline, true
            for _, other in ipairs(page.swatches) do
                if other.rgn == sw.rgn and other.frame._anchor == last then leftmost = false end
            end
            check(last ~= nil and last._kind == "Swatch" and last._parent == sw.rgn and leftmost,
                tag .. ": " .. name .. ", the swatches of '" .. tostring(sw.host and sw.host.text) .. "' do not end as their half's last inline item")
        end
    end
    for _, il in ipairs(page.inline) do
        for _, sc in ipairs(il.list) do
            check(not cogOf[il.rgn] or sc._frame._anchor ~= il.rgn._control,
                tag .. ": " .. name .. ", an inline swatch of '" .. tostring(il.host and il.host.text) .. "' sits between its control and the row's cog")
        end
    end
    return page
end

-------------------------------------------------------------------------------
-- 3. The controls of a page: which, their signatures, their tooltips
-------------------------------------------------------------------------------
local function CheckControls(Wd, tag, page, name, forever)
    local rows = Rows(name, forever)
    local list = H.Controls(page)
    local got, want = {}, {}
    for i, c in ipairs(list) do got[i] = c.id end
    for i, r in ipairs(rows) do want[i] = r.id end
    Compare(tag .. ": the controls of " .. name, got, want)
    local offScreen = 0
    for _, r in ipairs(rows) do
        local c = list[r.id]
        if c and #r.sig > 0 then
            local sig = H.Signature(Wd, page, c)
            Compare(tag .. ": " .. name .. " | " .. r.id, sig, r.sig)
            for _, l in ipairs(sig) do
                local flags = l:match(" # (%a+)$")
                if flags and flags:find("u", 1, true) then offScreen = offScreen + 1 end
            end
        end
    end
    eq(offScreen, 0, tag .. ": " .. name .. ", writes that repaint a preview which is not on screen")
    for id, tip in pairs(TIPS[name] or {}) do
        local c = list[id]
        check(c and c.cfg and c.cfg.tooltip == tip, tag .. ": " .. name .. " | " .. id .. " does not carry its tooltip: " .. tostring(c and c.cfg and c.cfg.tooltip))
    end
    -- the style dropdown explains itself through its entries: it carries no tooltip
    if name == FRIENDLY or name == FRIENDLY_NO then
        local c = list["FRIENDLY PLAYERS|Friendly Nameplate Style"]
        check(c and c.cfg and c.cfg.tooltip == nil, tag .. ": " .. name .. ", Friendly Nameplate Style carries a tooltip")
    end
    -- the Extras tab's pets row and two enemy scale rows are never greyed
    if name == GENERAL then
        for _, r in ipairs(rows) do
            local c = list[r.id]
            if c and #r.sig > 0 then check(c.cfg.disabled == nil, tag .. ": " .. r.id .. " has a gate") end
        end
    end
    return list
end

-------------------------------------------------------------------------------
-- 4. The gates of a page, over every scenario of its flags
-------------------------------------------------------------------------------
local function CheckGates(Wd, tag, page, name, list, forever)
    local rows = Rows(name, forever)
    for _, r in ipairs(rows) do
        check(r.gate == nil or GATE[r.gate], "no GATE named " .. tostring(r.gate))
    end
    local bad, first = {}, {}
    local n = H.EachMode(H.FLAGS[name], H.DEEP[name], function(state, style)
        H.Refresh(page)
        for _, r in ipairs(rows) do
            local c = list[r.id]
            if c then
                local wantGate = r.gate and GATE[r.gate] and GATE[r.gate](state, style) or nil
                local gotGate = H.GateOf(c)
                if gotGate ~= wantGate then
                    bad[r.id] = (bad[r.id] or 0) + 1
                    first[r.id] = first[r.id] or (StateText(state, style) .. ": is " .. tostring(gotGate) .. ", must be " .. tostring(wantGate))
                end
            end
        end
    end)
    for _, r in ipairs(rows) do
        check(not bad[r.id], ("%s: %s | %s is greyed wrongly in %s of %d scenarios; the first, %s"):format(
            tag, name, r.id, tostring(bad[r.id]), n, tostring(first[r.id])))
    end
    return n
end

-------------------------------------------------------------------------------
-- 5. The saved keys: each key of DRIVER is written by its controls and no other
-------------------------------------------------------------------------------
local function CheckKeys(Wd, tag, pages, lists)
    local drivers = {}
    -- (N: the Friendly Plates page as built under Name Only, read for the one row that differs
    -- there, the name size with its cog; its other controls are the F build's, by their signatures)
    for _, spec in ipairs({ { "T", TFH }, { "F", FRIENDLY }, { "N", FRIENDLY_NO, "FRIENDLY PLAYERS|Friendly Name Size" }, { "E", GENERAL } }) do
        local page, list = pages[spec[2]], lists[spec[2]]
        for _, c in ipairs(list or {}) do
            if not spec[3] or c.id:find(spec[3], 1, true) == 1 then
                for k in pairs(H.KeysWritten(Wd, page, c)) do
                    drivers[k] = drivers[k] or {}
                    drivers[k][#drivers[k] + 1] = spec[1] .. "|" .. c.id
                end
            end
        end
    end
    local n = 0
    for key, want in pairs(DRIVER) do
        n = n + 1
        local w = type(want) == "table" and want or { want }
        Compare(tag .. ": the controls that write " .. key, drivers[key] or {}, w)
    end
    eq(n, 98, "the saved keys DRIVER names")
    -- the two new pages write nothing else
    local extra = {}
    for key, d in pairs(drivers) do
        if not DRIVER[key] then
            for _, id in ipairs(d) do
                if id:sub(1, 1) ~= "E" then extra[#extra + 1] = key .. " by " .. id end
            end
        end
    end
    table.sort(extra)
    eq(#extra, 0, tag .. ": keys the two pages write that DRIVER does not name (" .. table.concat(extra, "; "):sub(1, 300) .. ")")
end

-------------------------------------------------------------------------------
-- 6. A write that changes what another control on the page shows as greyed
--    refreshes the page, or repaints the swatch or cog it changes itself. Read
--    from every toggle, dropdown, swatch, checklist entry and cog row (a
--    slider's own drag end refreshes the page), over the three starting
--    settings, against what the page shows: its rows, swatches and cog buttons.
-------------------------------------------------------------------------------
local function CheckRefresh(Wd, tag, page, name, list)
    local stale = {}
    for _, x in ipairs(list) do
        if x.set and x.kind ~= "slider" then
            for _, input in ipairs(x.inputs or {}) do
                for i = 1, 3 do
                    H.SetState(H.STATES[i])
                    H.ResetLog()
                    H.Refresh(page)
                    local before = {}
                    for _, v in ipairs(list) do
                        if not v.inside and v ~= x and v.gate then before[v] = v.gate() or "-" end
                    end
                    local cogStates = page.cogStates
                    H.ResetLog()
                    x.set(unpack(input))
                    if LOG.refresh == 0 then
                        local shown = {}
                        for v in pairs(before) do shown[v] = v.gate() or "-" end
                        H.Refresh(page)
                        for v, was in pairs(before) do
                            local now = v.gate() or "-"
                            local isStale
                            if v.hand then isStale = shown[v] ~= now          -- its refresher had to run
                            elseif v.kind == "cog" then isStale = now ~= was and page.cogStates == cogStates
                            else isStale = now ~= was end
                            if isStale then stale[x.id .. " -> " .. v.id] = true end
                        end
                    end
                end
            end
        end
    end
    local out = {}
    for k in pairs(stale) do out[#out + 1] = k end
    table.sort(out)
    eq(#out, 0, tag .. ": " .. name .. ", writes that change another control's greyed state and refresh nothing (" .. table.concat(out, "; "):sub(1, 400) .. ")")
end

-------------------------------------------------------------------------------
-- 7. The previews' wiring
-------------------------------------------------------------------------------
local function FakePreviews(Wd)
    local function New(shown)
        local f = Frame("Preview")
        f._n, f._shown = 0, shown
        f.Update = function(self) self._n = self._n + 1 end
        return f
    end
    return New(true), New(true)
end
local function CheckPreviews(Wd, tag)
    local os = Wd.optState
    local cfg = Wd.cfg
    -- the nameplate preview: only the one on screen is repainted
    local enemy, tfh = FakePreviews(Wd)
    os.activePreview, os.tfhPreview = enemy, tfh
    for _, case in ipairs({ { true, false }, { false, true }, { false, false }, { true, true } }) do
        enemy._shown, tfh._shown, enemy._n, tfh._n = case[1], case[2], 0, 0
        Wd.env.UpdatePreview()
        check(enemy._n == (case[1] and 1 or 0) and tfh._n == (case[2] and 1 or 0),
            tag .. ": UpdatePreview does not repaint exactly the preview on screen (Enemies shown " .. tostring(case[1]) .. ", Target, Focus & Hover shown " .. tostring(case[2]) .. ")")
        enemy._n, tfh._n = 0, 0
        Wd.onShow[1]()
        check(enemy._n == (case[1] and 1 or 0) and tfh._n == (case[2] and 1 or 0),
            tag .. ": the panel's show does not repaint exactly the preview on screen")
    end
    -- a page shown again from the cache repaints its own preview, and only that
    enemy._shown, tfh._shown, enemy._n, tfh._n = true, true, 0, 0
    H.ResetLog()
    cfg.onPageCacheRestore(TFH)
    check(tfh._n == 1 and enemy._n == 0 and LOG.fpv == 0, tag .. ": Target, Focus & Hover shown again does not repaint its preview alone")
    enemy._n, tfh._n = 0, 0
    cfg.onPageCacheRestore(DISPLAY)
    check(enemy._n == 1 and tfh._n == 0 and LOG.fpv == 0, tag .. ": Enemies shown again does not repaint its preview alone")
    enemy._n, tfh._n = 0, 0
    cfg.onPageCacheRestore(FRIENDLY)
    check(enemy._n == 0 and tfh._n == 0 and LOG.fpv == 1, tag .. ": Friendly Plates shown again does not repaint the sample plates alone")
    H.ResetLog()
    cfg.onPageCacheRestore(COLORS)
    cfg.onPageCacheRestore(GENERAL)
    check(enemy._n == 0 and tfh._n == 0 and LOG.fpv == 0, tag .. ": a page with no preview repaints one when it is shown again")

    -- the Target, Focus & Hover header: the preview as the target, and the picker under it
    -- (built on an account that has dismissed the click hint; the hint's own checks are
    -- in section 11)
    os.tfhMode, os.tfhPreview = nil, nil
    H.SetState({})
    H.ResetLog()
    EllesmereUIDB = { previewHintDismissed = true }
    local page = H.Build(Wd, TFH)
    EllesmereUIDB = {}
    local made = Wd.previews[#Wd.previews]
    local hdr = page.header
    check(hdr and hdr.builder == nsData.NPO_BuildTFHHeader and page.cleared == 0, tag .. ": the page does not show ns.NPO_BuildTFHHeader as its header")
    if hdr and check(made and made.parent == hdr.frame and made.w == 1030, tag .. ": the header does not build the preview on its own frame, at its width") then
        eq(made.mode, "target", tag .. ": the state the preview starts in")
        eq(os.tfhPreview, made.pf, tag .. ": the preview the page keeps")
        eq(hdr.height, 115, tag .. ": the header's height (the preview's 60, the picker's row under it and the pads: 5 + 2 + 30 + 18)")
        local at = made.pf._points[#made.pf._points]
        check(at and at[1] == "TOP" and at[2] == hdr.frame and at[3] == "TOP" and at[5] == -5
            and made.pf._topPad == 5 and made.pf._headerExtra == 55,
            tag .. ": the header does not place the preview under its top pad, or does not hand the preview its pads")
        eq(#page.dropdowns, 1, tag .. ": pickers in the header")
        local dd = page.dropdowns[1]
        if dd then
            eq(dd.parent, hdr.frame, tag .. ": the picker's parent")
            eq(table.concat(dd.order, ","), "target,focus,hover", tag .. ": the picker's entries")
            check(dd.values.target == "Target" and dd.values.focus == "Focus" and dd.values.hover == "Hover", tag .. ": the picker's labels")
            eq(dd.get(), "target", tag .. ": the picker's value")
            -- centred under the preview, whose bottom it follows: one point, 2 under it
            local p = dd.frame._points[#dd.frame._points]
            check(p and p[1] == "TOP" and p[2] == made.pf and p[3] == "BOTTOM" and p[4] == 0 and p[5] == -2 and #dd.frame._points == 1,
                tag .. ": the picker is not placed under the preview, on its middle")
            eq(dd.w, 170, tag .. ": the picker's width")
            for _, mode in ipairs({ "focus", "hover", "target", "hover" }) do
                local n0 = made.pf._updates
                H.ResetLog()
                dd.set(mode)
                check(made.pf._mode == mode and dd.get() == mode and os.tfhMode == mode, tag .. ": a pick of " .. mode .. " does not set the preview's state")
                eq(made.pf._updates - n0, 1, tag .. ": repaints after a pick of " .. mode)
                check(#WRITES == 0 and next(EllesmereUIDB) == nil, tag .. ": a pick saves something (it is the session's only)")
            end
            -- a later build of the header (a page rebuild) keeps the session's pick
            local again = H.Build(Wd, TFH)
            local made2 = Wd.previews[#Wd.previews]
            check(made2 ~= made and made2.mode == "hover" and again.dropdowns[1] and again.dropdowns[1].get() == "hover",
                tag .. ": a header built again does not keep the picked state")
        end
    end
    eq(next(page.made), nil, tag .. ": frames the Target, Focus & Hover page makes with CreateFrame (an eye button on Target Effect would be one)")
    -- its header makes one frame of its own, the click hint's host (whether the hint shows or not)
    local hm = {}
    for kind, n in pairs(page.header and page.header.made or {}) do hm[#hm + 1] = kind .. "=" .. n end
    table.sort(hm)
    eq(table.concat(hm, ","), "Frame=1", tag .. ": frames the Target, Focus & Hover header makes with CreateFrame")
    EllesmereUIDB = {}

    -- the Friendly Plates header: the two sample plates (the instance note is the page's first row)
    H.SetState({})
    H.ResetLog()
    local onShow0 = #Wd.onShow
    local paints0 = Wd.npcPaints or 0
    local f = H.Build(Wd, FRIENDLY)
    local fh = f.header
    check(fh and fh.builder == nsData.NPO_BuildFriendlyHeader and f.cleared == 0, tag .. ": the page does not show ns.NPO_BuildFriendlyHeader as its header")
    if fh then
        check(type(fh.height) == "number" and fh.height >= 60, tag .. ": the Friendly Plates header's height: " .. tostring(fh.height))
        eq((Wd.npcPaints or 0) - paints0, 1, tag .. ": paints of the samples by a header build")
        check(#Wd.onShow - onShow0 <= 1 and #Wd.onShow == 2, tag .. ": the samples' panel-show callback is not registered once (" .. #Wd.onShow .. " callbacks in all)")
        -- the header's one text is the kit's click hint: the instance note is not on it
        local own = 0
        local hint = Wd.env.Nav and Wd.env.Nav.Page(FRIENDLY).fs
        for _, fr in ipairs(Wd.notes) do
            if fr._parent == fh.frame and fr ~= hint then own = own + 1 end
        end
        eq(own, 0, tag .. ": texts on the Friendly Plates header besides the hint")
        -- the note: the page's first row, over the first section, in the shared note row's warning form
        local NOTE = "Friendly Nameplate customization is disabled in instances due to Blizzard limitations"
        local nr = f.noteRows[1]
        if check(#f.noteRows == 1 and nr, tag .. ": the Friendly Plates page does not hold one note row (" .. #f.noteRows .. ")") then
            eq(nr.text, NOTE, tag .. ": the note's text")
            check(type(nr.opts) == "table" and nr.opts.warn == true and nr.opts.banner == nil, tag .. ": the note is not asked for as a warning")
            eq(f.items[1], "note: " .. NOTE, tag .. ": the page's first item")
            eq(f.items[2], "# FRIENDLY PLAYERS", tag .. ": the item under the note")
            local sec = f.sections["FRIENDLY PLAYERS"]
            check(nr.y2 == nr.y - 34 and sec and sec._points[1] and sec._points[1][5] == nr.y2 and sec._parent == nr.parent,
                tag .. ": the first section does not start right under the note's 34 px row")
            -- the row as the real helper makes it: one frame, one line, centred, the warning red at full strength
            local fs, row = nr.fs, nr.row
            if check(nr.frames == 1 and nr.texts == 1 and fs and row, tag .. ": the note row is not one frame with one text") then
                local rp = row._points[1]
                check(row._parent == nr.parent and row._h == 34 and row._w == nr.parent:GetWidth() - 80 and row._skipRowDivider == true
                    and #row._points == 1 and rp[1] == "TOPLEFT" and rp[2] == nr.parent and rp[3] == "TOPLEFT" and rp[4] == 40 and rp[5] == nr.y
                    and not row._rowBg, tag .. ": the note row's frame (size, spot, no row divider, no row background)")
                eq(fs._text, NOTE, tag .. ": the note row's text")
                check(fs._font and fs._font[2] == 13 and fs._color[1] == 0.9 and fs._color[2] == 0.3 and fs._color[3] == 0.3 and fs._alpha == 1,
                    tag .. ": the note is not the 13 px warning red at full strength")
                local np = fs._points[1]
                check(#fs._points == 1 and np[1] == "CENTER" and np[2] == row and np[3] == "CENTER" and np[4] == 0 and np[5] == 0
                    and fs._wrap == nil, tag .. ": the note is not one line centred on its row")
            end
        end
        -- no other page of the module opens with a note row
        for _, other in ipairs({ DISPLAY, COLORS, TFH, GENERAL }) do
            eq(#H.Build(Wd, other).noteRows, 0, tag .. ": note rows on " .. other)
        end
        -- the search pre-build: the same advance, no frame and no text
        local npre = H.Build(Wd, FRIENDLY, true)
        local pr = npre.noteRows[1]
        check(#npre.noteRows == 1 and pr and pr.frames == 0 and pr.texts == 0 and pr.y2 == pr.y - 34 and pr.text == NOTE,
            tag .. ": the note row in the search pre-build")
        -- the shared row's two other forms are as they were: the dim aside, and the banner
        local host = Frame("Frame")
        host._w = 1000
        local _, plain = EllesmereUI.BuildNoteRow(host, -10, "An aside")
        local pp = plain.fs and plain.fs._points[1]
        check(plain.y2 == -44 and plain.fs and plain.fs._font[2] == 12 and plain.fs._alpha == 0.45 and plain.fs._color[1] == 1 and plain.fs._color[2] == 1
            and #plain.fs._points == 1 and pp[1] == "LEFT" and pp[4] == 20 and not plain.row._rowBg and plain.fs._wrap == nil,
            tag .. ": the plain note row (dim, left, one point)")
        local _, banner = EllesmereUI.BuildNoteRow(host, -10, "A banner", { banner = true })
        check(banner.y2 == -50 and banner.fs and banner.fs._font[2] == 12 and banner.fs._alpha == 0.6 and #banner.fs._points == 2 and banner.row._rowBg == true
            and banner.fs._wrap == true and banner.fs._maxLines == 2 and banner.row._h == 40, tag .. ": the banner note row")
        f = H.Build(Wd, FRIENDLY)
        fh = f.header
        -- painted by a write, the page's show and the panel's show; only while on screen
        local function Paints(fn)
            local n0 = Wd.npcPaints or 0
            fn()
            return (Wd.npcPaints or 0) - n0
        end
        eq(Paints(nsData.NPO_FriendlyPreviewUpdate), 1, tag .. ": paints by an update while the header is on screen")
        eq(Paints(Wd.onShow[2]), 1, tag .. ": paints by the panel's show")
        fh.frame:Hide()
        eq(Paints(nsData.NPO_FriendlyPreviewUpdate), 0, tag .. ": paints by an update while the header is not on screen")
        eq(Paints(Wd.onShow[2]), 0, tag .. ": paints by the panel's show while the header is not on screen")
        fh.frame:Show()
        -- the two samples: the player left and the NPC right of the header's middle, their
        -- offsets snapped to whole pixels at the samples' own scale
        local TALL = { friendlyNameOnly = false, friendlyHealthBarHeight = 40, friendlyNameTextSize = 30, friendlyBelowName = "both" }
        local player, npc
        for _, fr in ipairs(Wd.rootless) do
            local name = fr._parent == fh.frame and rawget(fr, "name")
            local text = name and name._text or ""
            if text:find("Friendly Player", 1, true) then player = fr elseif text == "Friendly NPC" then npc = fr end
        end
        if not check(player and npc, tag .. ": the header does not hold the player sample and the NPC sample") then return end
        Wd.snaps = 0
        nsData.NPO_FriendlyPreviewUpdate()
        local pp, np = player._points[1], npc._points[1]
        check(pp and np and pp[1] == "CENTER" and np[1] == "CENTER" and pp[2] == fh.frame and np[2] == fh.frame and pp[3] == "TOP" and np[3] == "TOP"
            and np[4] > 0 and pp[4] == -np[4] and pp[5] == np[5] and np[5] < 0,
            tag .. ": the player sample is not left and the NPC sample right of the header's middle, at one height")
        check(Wd.snaps == 2 and Wd.snapES == player:GetEffectiveScale() and Wd.snapES ~= fh.frame:GetEffectiveScale(),
            tag .. ": the samples' two offsets are not snapped at the samples' own scale (" .. Wd.snaps .. " snaps at " .. tostring(Wd.snapES) .. ")")
        -- the header without the hint's band: its least height at the default settings (the
        -- samples and the 16 px above and under them fit in it, no band under them for a
        -- note), the samples' middles on its middle
        local hintFS = Wd.env.Nav.Page(FRIENDLY).fs
        local last = fh.height
        local function BaseAt(state)
            H.SetState(state)
            Wd.silentH = nil
            nsData.NPO_FriendlyPreviewUpdate()
            last = Wd.silentH or last
            return last - ((hintFS and hintFS:IsShown()) and 29 or 0)
        end
        local function Mid(base)
            local es = player:GetEffectiveScale()
            return math.floor(-base / 2 / player:GetScale() * es + 0.5) / es
        end
        local small = BaseAt({ friendlyNameSize = 8, friendlyNPCNameSize = 8, showNPCTitles = false })
        eq(small, 60, tag .. ": the Friendly Plates header's least height (small samples fit in it with their pads)")
        eq(player._points[1][5], Mid(small), tag .. ": the small samples' middle (the header's)")
        -- over the least height: the taller sample (a 50 px Name Only name) and 16 px above and under it
        local big = BaseAt({ friendlyNameSize = 50, friendlyNPCNameSize = 8, showNPCTitles = false })
        eq(big, math.ceil(16 + 50 * player:GetScale() + 16), tag .. ": the header's height round a taller sample")
        eq(player._points[1][5], Mid(big), tag .. ": the taller samples' middle (the header's)")
        check(npc._points[1][5] == player._points[1][5], tag .. ": the two samples leave one height")
        BaseAt({})
        -- the panel drops the samples from a header it clears (hidden, no parent): nothing is
        -- painted then and no header is resized, though the frame they hung on shows
        for _, s in ipairs({ player, npc }) do s:Hide(); s:SetParent(nil) end
        H.SetState(TALL)
        Wd.silentH = nil
        eq(Paints(nsData.NPO_FriendlyPreviewUpdate), 0, tag .. ": paints by an update while the samples are dropped from a header that shows")
        eq(Paints(Wd.onShow[2]), 0, tag .. ": paints by the panel's show while the samples are dropped from a header that shows")
        eq(Wd.silentH, nil, tag .. ": dropped samples resize the header that shows")
        H.SetState({})
        -- built once: a second header takes the samples back, shown, on its own frame
        local f2 = H.Build(Wd, FRIENDLY)
        local h2 = f2.header and f2.header.frame
        eq(#Wd.onShow, 2, tag .. ": panel-show callbacks after a second header build")
        check(f2.header and next(f2.header.made) == nil, tag .. ": a second header build makes the sample plates again")
        local pm = {}
        for kind, n in pairs(f2.made) do pm[#pm + 1] = kind .. "=" .. n end
        eq(table.concat(pm, ","), "Button=1", tag .. ": frames the Friendly Plates page makes with CreateFrame (the eye beside Show Raid Marker)")
        if not check(h2 and h2 ~= fh.frame and player._parent == h2 and npc._parent == h2 and player:IsVisible() and npc:IsVisible(),
            tag .. ": a second header build does not take the dropped samples back, shown, on its own frame") then return end
        eq(Paints(nsData.NPO_FriendlyPreviewUpdate), 1, tag .. ": paints by an update after the second header build")
        -- the panel snaps the height it is given to its pixel grid: a repaint that changes
        -- no height leaves the header alone
        Wd.silentH = nil
        h2._h = h2._h + 0.75
        nsData.NPO_FriendlyPreviewUpdate()
        eq(Wd.silentH, nil, tag .. ": a repaint that changes no height sets the header's height again")
        -- the header follows the taller sample
        H.SetState(TALL)
        Wd.silentH = nil
        nsData.NPO_FriendlyPreviewUpdate()
        check(type(Wd.silentH) == "number" and Wd.silentH > fh.height, tag .. ": a taller sample does not grow the header: " .. tostring(Wd.silentH))
        H.SetState({})
        nsData.NPO_FriendlyPreviewUpdate()
        eq(Wd.silentH, fh.height, tag .. ": the header's height back at the default settings")
    end
end

-------------------------------------------------------------------------------
-- 8. Blizzard Nameplate Size, in the cog of Friendly Nameplate Style
-------------------------------------------------------------------------------
local RowLabeled   -- (defined with the checks of the Hash Line Location row)
local function CheckNameplateSize(Wd, tag, page, list)
    local cog
    for _, c in ipairs(page.cogs) do
        if c.host and c.host.text == "Friendly Nameplate Style" then cog = c end
    end
    if not check(cog ~= nil, tag .. ": Friendly Nameplate Style has no cog") then return end
    eq(cog.opts.title, "Friendly Nameplate Settings", tag .. ": the cog's title")
    eq(cog.opts.disabled, nil, tag .. ": the cog's gate (it is never greyed)")
    -- a quiet cog: the toggle's writes never light its dot or bring the cog tip up. The shared
    -- helper leaves a quiet cog out of its region's write notice, and the notice finds no cog there.
    eq(cog.opts.quiet, true, tag .. ": the cog is a quiet one")
    for _, c in ipairs(page.cogs) do
        check(c == cog or c.opts.quiet == nil, tag .. ": another cog is quiet (" .. tostring(c.opts.title) .. ")")
    end
    local helper = ReadSource(OPT .. "EllesmereUI_Widgets_RowAddons.lua") or ""
    check(helper:find("\n        if not opts.quiet then rgn._euiCog = btn end\n", 1, true) and not helper:find("\n        rgn._euiCog = btn\n", 1, true),
        tag .. ": the shared cog helper registers a quiet cog for its region's write notice")
    check(helper:find("\n        cog = frame._euiCog\n", 1, true) and helper:find("\n    if not cog then return end\n", 1, true),
        tag .. ": the write notice no longer finds its cog on the region, or goes on without one")
    local row = cog.opts.rows[1]
    check(#cog.opts.rows == 2 and row.type == "slider" and row.label == "Blizzard Nameplate Size" and row.min == 1 and row.max == 5 and row.step == 1
        and row.disabled == nil, tag .. ": the cog's first row is not the 1 to 5 slider")
    -- its second row: Show [] Around Group/Raid, greyed by itself under Blizzard Default
    local br = cog.opts.rows[2]
    if check(br and br.type == "toggle" and br.label == "Show [] Around Group/Raid" and type(br.disabled) == "function"
        and br.rawTooltip == true and br.disabledTooltip == "Requires Friendly Nameplate Style set to Name Only or Nameplate",
        tag .. ": the cog's second row is not Show [] Around Group/Raid with its own gate") then
        H.SetState({})
        check(br.disabled() == false and br.get() == false, tag .. ": Show [] Around Group/Raid is greyed or on with nothing saved")
        H.SetState({ showFriendlyPlayers = false, friendlyGroupBrackets = true })
        check(br.disabled() == true and br.get() == true, tag .. ": Show [] Around Group/Raid is live under Blizzard Default, or does not read its key")
        H.SetState({})
    end
    check(RowLabeled(page, "Show [] Around Group/Raid") == nil, tag .. ": Show [] Around Group/Raid is still a row of the page")
    local function Popups(...)
        H.SetState({})
        H.ResetLog()
        for i = 1, select("#", ...) do row.set((select(i, ...))) end
        local timers = #LOG.timers
        for _, t in ipairs(LOG.timers) do if not t.cancelled then t.fn() end end
        return #LOG.popups, timers
    end
    eq(Popups(3), 0, tag .. ": reload popups after the size the page was built with is set again")
    eq(Popups(4), 1, tag .. ": reload popups after a new size")
    local pop = LOG.popups[1]
    check(pop and pop.reload == true and pop.title == "Reload Required" and pop.message == "Changing Blizzard Nameplate Size requires a UI reload to take effect."
        and pop.confirmText == "Reload Now" and pop.cancelText == "Later", tag .. ": the reload popup's texts and its reload")
    eq(table.concat(LOG.cvars, ","), "nameplateSize=4", tag .. ": the CVar written with the size")
    eq(Popups(2, 4, 5), 1, tag .. ": reload popups after a drag over three sizes (one, after the drag)")
    eq(Popups(4, 3), 0, tag .. ": reload popups after a drag that ends on the size the page was built with")
    -- the cog of Friendly Name Size (the health bar plates' here) names what it holds; one cog
    -- only is titled Friendly Nameplate Settings
    local offset
    for _, c in ipairs(page.cogs) do
        if c.host and c.host.text == "Friendly Name Size" then offset = c end
    end
    check(offset and offset.opts.title == "Nameplate Offset" and #offset.opts.rows == 1 and offset.opts.rows[1].label == "Distance",
        tag .. ": the cog of Friendly Name Size is not Nameplate Offset with its Distance row")
    local n = 0
    for _, c in ipairs(page.cogs) do
        if c.opts.title == "Friendly Nameplate Settings" then n = n + 1 end
    end
    eq(n, 1, tag .. ": cogs titled Friendly Nameplate Settings")
end

-------------------------------------------------------------------------------
-- 8b. Target, Focus & Hover: Hash Line Location is a row only while Show Hash
--     Line on Target is on (the toggle builds the page again, and it alone);
--     the small grey suffixes after three row labels
-------------------------------------------------------------------------------
RowLabeled = function(page, label)
    for _, r in ipairs(page.rows) do
        if r.l.text == label then return r.row._leftRegion end
        if r.r.text == label then return r.row._rightRegion end
    end
end
-- The one font string made on a row half beside its label: its text, look and spot.
local function Suffix(rgn)
    local made = rgn and rawget(rgn, "_fontStrings") or {}
    local fs = made[1]
    if #made ~= 1 or not fs then return "made " .. #made end
    local pt = fs._points[1] or {}
    return ("%s | size %s | color %s | %s of the label's %s at %s,%s"):format(tostring(fs._text), tostring(fs._font and fs._font[2]),
        fs._color and table.concat(fs._color, ",") or "none", tostring(pt[1]), pt[2] == rgn._label and tostring(pt[3]) or "?",
        tostring(pt[4]), tostring(pt[5]))
end
local function CheckHashRow(Wd, tag, full, list)
    local msg = tag .. ": Target, Focus & Hover"
    -- built with the hash line off: every row but that one, and no such control
    H.SetState({})
    H.ResetLog()
    local off = H.Build(Wd, TFH)
    if not check(off.ok, msg .. ", hash line off: the page does not build: " .. tostring(off.result):sub(1, 300)) then return end
    local want = {}
    for _, line in ipairs(LAYOUT[TFH]) do
        if line ~= HASH_ROW then want[#want + 1] = line end
    end
    eq(#want, #LAYOUT[TFH] - 1, msg .. ": the layout lists the Hash Line Location row once")
    Compare(msg .. ", built with Show Hash Line on Target off: its sections and rows", off.items, want)
    local offList = H.Controls(off)
    check(offList["TARGET|Hash Line Location"] == nil and RowLabeled(off, "Hash Line Location") == nil,
        msg .. ", hash line off: Hash Line Location is still built")
    check(full.result - off.result > 0 and off.spacers == 2, msg .. ", hash line off: the page is not one row shorter ("
        .. tostring(full.result) .. " against " .. tostring(off.result) .. ")")
    -- every other control is there in both forms, in the same order
    local a, b = {}, {}
    for _, c in ipairs(list) do if c.id ~= "TARGET|Hash Line Location" then a[#a + 1] = c.id end end
    for _, c in ipairs(offList) do b[#b + 1] = c.id end
    Compare(msg .. ": the controls with the hash line off, against the full page less the one row", b, a)
    -- built with it saved false: the same as not saved
    H.SetState({ hashLineEnabled = false })
    local off2 = H.Build(Wd, TFH)
    check(off2.ok and #off2.items == #want, msg .. ", hash line saved off: the row is built")
    H.SetState({})
    -- the row itself: never greyed (it is not there while it could not be used), a blank right half
    local loc = list["TARGET|Hash Line Location"]
    if check(loc ~= nil, msg .. ": no Hash Line Location control on the page built with the hash line on") then
        check(loc.cfg.disabled == nil and loc.cfg.disabledTooltip == nil, msg .. ": Hash Line Location has a gate")
    end
    -- the toggle builds the page again, both ways and from every starting setting; no other
    -- control of the page does
    for _, pg in ipairs({ { full, list, "on" }, { off, offList, "off" } }) do
        local rebuilders = {}
        for _, c in ipairs(pg[2]) do
            if c.set then
                local n = 0
                for _, input in ipairs(c.inputs or {}) do
                    for i = 1, 3 do
                        H.SetState(H.STATES[i]); H.ResetLog()
                        c.set(unpack(input))
                        for _, tm in ipairs(LOG.timers) do if not tm.cancelled then tm.fn() end end
                        if LOG.rebuild > 0 then n = n + 1 end
                        if c.id == "TARGET|Show Hash Line on Target" then
                            check(LOG.rebuild == 1 and LOG.refresh == 1, msg .. ", built " .. pg[3] .. ": Show Hash Line on Target " .. tostring(input[1])
                                .. " does not build the page again exactly once (" .. LOG.rebuild .. " of " .. LOG.refresh .. " refreshes)")
                        end
                    end
                end
                if n > 0 then rebuilders[#rebuilders + 1] = c.id end
            end
        end
        eq(table.concat(rebuilders, "; "), "TARGET|Show Hash Line on Target", msg .. ", built " .. pg[3] .. ": the controls that build the page again")
    end
    H.SetState({})
    -- the suffixes: small and grey, right after their label, on these three halves alone
    eq(Suffix(RowLabeled(full, "Distance to Target Text")), "(Range) | size 11 | color 1,1,1,0.35 | LEFT of the label's RIGHT at 5,-1",
        msg .. ": the (Range) after Distance to Target Text")
    eq(Suffix(RowLabeled(off, "Distance to Target Text")), "(Range) | size 11 | color 1,1,1,0.35 | LEFT of the label's RIGHT at 5,-1",
        msg .. ", hash line off: the (Range) after Distance to Target Text")
    for _, label in ipairs({ "Scale Target Nameplate", "Hash Line Location", "Focus Cast Height" }) do
        eq(Suffix(RowLabeled(full, label)), "(Percent) | size 11 | color 1,1,1,0.35 | LEFT of the label's RIGHT at 5,-1",
            msg .. ": the (Percent) after " .. label)
    end
    local others = {}
    for _, r in ipairs(full.rows) do
        for _, side in ipairs({ { r.l, r.row._leftRegion }, { r.r, r.row._rightRegion } }) do
            local label, made = side[1].text, rawget(side[2], "_fontStrings")
            if made and #made > 0 and label ~= "Distance to Target Text" and label ~= "Scale Target Nameplate"
                and label ~= "Hash Line Location" and label ~= "Focus Cast Height" then
                others[#others + 1] = tostring(label)
            end
        end
    end
    eq(table.concat(others, "; "), "", msg .. ": other halves with a font string of the page's own")
    -- the labels themselves carry no bracket
    for _, r in ipairs(full.rows) do
        for _, cfg in ipairs({ r.l, r.r }) do
            check(not (cfg.text or ""):find("(", 1, true), msg .. ": the label " .. tostring(cfg.text) .. " carries a bracket")
        end
    end
    -- the search pre-build makes none
    H.SetState({ hashLineEnabled = true })
    local pre = H.Build(Wd, TFH, true)
    H.SetState({})
    check(pre.ok and pre.framesMade == 0, msg .. ": the search pre-build makes a frame (" .. tostring(pre.framesMade) .. ")")
end

-------------------------------------------------------------------------------
-- 8c. Friendly Plates: Friendly Nameplate Style is a view over the two saved
--     switches, and every change of style does what the two toggles did; Name
--     Color is one pick for both styles, and until it is made each style shows
--     what its older key says
-------------------------------------------------------------------------------
local function CheckStyleAndNameColor(Wd, tag, page, list)
    local msg = tag .. ": Friendly Plates"
    local style = list["FRIENDLY PLAYERS|Friendly Nameplate Style"]
    local custom, customClick = list["FRIENDLY PLAYERS|Name Color|ms:Custom Color"], list["FRIENDLY PLAYERS|Name Color|ms:Custom Color|click"]
    local class, classClick = list["FRIENDLY PLAYERS|Name Color|ms:Class Color"], list["FRIENDLY PLAYERS|Name Color|ms:Class Color|click"]
    if not check(style and custom and customClick and class and classClick, msg .. ": no Friendly Nameplate Style or no Name Color pair") then return end
    -- the style a profile shows, for every saved form of the two switches (nothing is migrated)
    for _, c in ipairs({ { nil, nil, "nameonly" }, { true, nil, "nameonly" }, { nil, true, "nameonly" }, { true, true, "nameonly" },
                         { nil, false, "plate" }, { true, false, "plate" },
                         { false, nil, "blizzard" }, { false, true, "blizzard" }, { false, false, "blizzard" } }) do
        H.SetState({ showFriendlyPlayers = c[1], friendlyNameOnly = c[2] })
        eq(style.get(), c[3], msg .. ": the style of showFriendlyPlayers=" .. tostring(c[1]) .. ", friendlyNameOnly=" .. tostring(c[2]))
    end
    -- every change of style: what is saved, called and sent to the game, and the refreshes
    -- (page refreshes / page rebuilds / sample repaints): a change builds the page again,
    -- once, since the rows on it follow the style
    local function Pick(state, v)
        H.SetState(state); H.ResetLog()
        style.set(v)
        local w = {}
        for _, k in ipairs(WRITES) do w[#w + 1] = k .. "=" .. Val(STORE[k]) end
        return table.concat(w, ",") .. " ! " .. table.concat(LOG.calls, ",") .. " $ " .. table.concat(LOG.cvars, ",")
            .. " # " .. LOG.refresh .. "/" .. LOG.rebuild .. "/" .. LOG.fpv
    end
    local NOTHING = " !  $  # 0/0/0"
    local DEFAULTS = "nameplateShowOnlyNameForFriendlyPlayerUnits=def:nameplateShowOnlyNameForFriendlyPlayerUnits,"
        .. "ShowClassColorInFriendlyNameplate=def:ShowClassColorInFriendlyNameplate,"
        .. "nameplateUseClassColorForFriendlyPlayerUnitNames=def:nameplateUseClassColorForFriendlyPlayerUnitNames"
    local OFF = "showFriendlyPlayers=false ! UpdateFriendlyNameplateSystem,RefreshStackingMotion $ " .. DEFAULTS .. " # 1/1/1"
    -- the style in use, picked again: nothing
    eq(Pick({}, "nameonly"), NOTHING, msg .. ": Name Only picked under Name Only")
    eq(Pick({ friendlyNameOnly = false }, "plate"), NOTHING, msg .. ": Nameplate picked under Nameplate")
    eq(Pick({ showFriendlyPlayers = false }, "blizzard"), NOTHING, msg .. ": Blizzard Default picked under Blizzard Default")
    -- between the two EUI styles: what the Name Only toggle did, plus the names' class colour CVar
    eq(Pick({}, "plate"), "friendlyNameOnly=false ! UpdateFriendlyNameplateSystem $ nameplateShowOnlyNameForFriendlyPlayerUnits=0,"
        .. "nameplateUseClassColorForFriendlyPlayerUnitNames=1 # 1/1/1", msg .. ": Name Only to Nameplate")
    eq(Pick({ friendlyNameOnly = false }, "nameonly"), "friendlyNameOnly=true ! ForceFriendlyPlayerCVarsOn,UpdateFriendlyNameplateSystem $ "
        .. "nameplateShowOnlyNameForFriendlyPlayerUnits=1,nameplateUseClassColorForFriendlyPlayerUnitNames=1 # 1/1/1", msg .. ": Nameplate to Name Only")
    eq(Pick({ friendlyNameOnly = false, classColorFriendly = false, friendlyNameClassColor = true }, "nameonly"),
        "friendlyNameOnly=true ! ForceFriendlyPlayerCVarsOn,UpdateFriendlyNameplateSystem $ "
        .. "nameplateShowOnlyNameForFriendlyPlayerUnits=1,nameplateUseClassColorForFriendlyPlayerUnitNames=0 # 1/1/1",
        msg .. ": Nameplate to Name Only, the two styles' older name colour keys apart")
    -- to Blizzard Default: what the players toggle did when turned off; the saved Name Only choice stays
    eq(Pick({}, "blizzard"), OFF, msg .. ": Name Only to Blizzard Default")
    eq(Pick({ friendlyNameOnly = false }, "blizzard"), OFF, msg .. ": Nameplate to Blizzard Default")
    eq(STORE.friendlyNameOnly, false, msg .. ": Blizzard Default does not keep the saved Name Only choice")
    -- from Blizzard Default: what the players toggle did when turned on, with the picked form
    eq(Pick({ showFriendlyPlayers = false }, "nameonly"), "friendlyNameOnly=true,showFriendlyPlayers=true ! "
        .. "ForceFriendlyPlayerCVarsOn,UpdateFriendlyNameplateSystem,RefreshStackingMotion $ UnitNameFriendlyPlayerName=1,"
        .. "nameplateShowOnlyNameForFriendlyPlayerUnits=1,ShowClassColorInFriendlyNameplate=1,nameplateUseClassColorForFriendlyPlayerUnitNames=1 # 1/1/1",
        msg .. ": Blizzard Default to Name Only")
    eq(Pick({ showFriendlyPlayers = false, friendlyNameOnly = true }, "plate"), "friendlyNameOnly=false,showFriendlyPlayers=true ! "
        .. "ForceFriendlyPlayerCVarsOn,UpdateFriendlyNameplateSystem,RefreshStackingMotion $ UnitNameFriendlyPlayerName=1,"
        .. "nameplateShowOnlyNameForFriendlyPlayerUnits=0,ShowClassColorInFriendlyNameplate=1,nameplateUseClassColorForFriendlyPlayerUnitNames=1 # 1/1/1",
        msg .. ": Blizzard Default to Nameplate")
    eq(Pick({ showFriendlyPlayers = false, classColorFriendly = false }, "plate"), "friendlyNameOnly=false,showFriendlyPlayers=true ! "
        .. "ForceFriendlyPlayerCVarsOn,UpdateFriendlyNameplateSystem,RefreshStackingMotion $ UnitNameFriendlyPlayerName=1,"
        .. "nameplateShowOnlyNameForFriendlyPlayerUnits=0,ShowClassColorInFriendlyNameplate=0,nameplateUseClassColorForFriendlyPlayerUnitNames=0 # 1/1/1",
        msg .. ": Blizzard Default to Nameplate, Class Colored Health Bar off")
    -- the style is never greyed and has its three entries in this order
    check(style.cfg.disabled == nil, msg .. ": Friendly Nameplate Style has a gate")
    eq(table.concat(style.order, ","), "blizzard,nameonly,plate", msg .. ": the style's entries, in order")
    -- the rows each style builds: the health bar plate's two only under Nameplate; the name size
    -- row holds the slider of the style in use (Blizzard Default: of the style it goes back to)
    for _, b in ipairs({ { {}, false, "friendlyNameSize", "Name Distance", "friendlyNameOnlyYOffset" },
                         { { friendlyNameOnly = true }, false, "friendlyNameSize", "Name Distance", "friendlyNameOnlyYOffset" },
                         { { friendlyNameOnly = false }, true, "friendlyNameTextSize", "Nameplate Offset", "friendlyPlateYOffset" },
                         { { showFriendlyPlayers = false }, false, "friendlyNameSize", "Name Distance", "friendlyNameOnlyYOffset" },
                         { { showFriendlyPlayers = false, friendlyNameOnly = false }, false, "friendlyNameTextSize", "Nameplate Offset", "friendlyPlateYOffset" } }) do
        local what = msg .. ", built under " .. StateText(b[1], STYLE)
        H.SetState(b[1])
        local built = H.Build(Wd, FRIENDLY)
        if check(built.ok, what .. ": the page does not build: " .. tostring(built.result)) then
            local bl = H.Controls(built)
            for _, label in ipairs({ "Health Bar Width", "Health Bar Height", "Health Bar Color", "Show Health Percent" }) do
                check((RowLabeled(built, label) ~= nil) == b[2], what .. ": the row " .. label .. (b[2] and " is not" or " is") .. " on the page")
            end
            for _, label in ipairs({ "Friendly Nameplate Style", "Name Color", "Friendly Name Size", "Player Name Format", "Level Text", "Subtitle Text",
                "Friendly Names Not Clickable", "Target Border Effects" }) do
                check(RowLabeled(built, label) ~= nil, what .. ": the row " .. label .. " is not on the page")
            end
            local size = bl["FRIENDLY PLAYERS|Friendly Name Size"]
            local cogRow = bl["FRIENDLY PLAYERS|Friendly Name Size|cog:" .. b[4] .. "|Distance"]
            if check(size and cogRow, what .. ": no Friendly Name Size with a " .. b[4] .. " cog") then
                H.ResetLog(); size.get()
                check(READS[b[3]] and next(READS, next(READS)) == nil, what .. ": Friendly Name Size does not read " .. b[3] .. " alone")
                H.ResetLog(); cogRow.get()
                check(READS[b[5]] and next(READS, next(READS)) == nil, what .. ": the cog's Distance does not read " .. b[5] .. " alone")
            end
            local sizes = 0
            for _, r in ipairs(built.rows) do
                for _, cfg in ipairs({ r.l, r.r }) do
                    if cfg.text and cfg.text:find("Friendly Name Size", 1, true) then sizes = sizes + 1 end
                end
            end
            eq(sizes, 1, what .. ": name size sliders of the players on the page")
        end
    end
    H.SetState({})

    -- Name Color over every setting it reads: which swatch is lit (or both greyed under Blizzard
    -- Default), the runtime's rule for each style, and the class colour CVar. With no pick, each
    -- style reads its older key and the CVar is what it was before the setting.
    local env = nsData._NPO_OptEnv
    local PLAYERS = "raw:Requires Friendly Nameplate Style set to Name Only or Nameplate"
    local n, bad, first = 0, 0, nil
    local function Wrong(what, state)
        bad = bad + 1
        first = first or (StateText(state, STYLE) .. ": " .. what)
    end
    for _, players in ipairs({ "nil", false }) do
      for _, nameOnly in ipairs({ "nil", false }) do
        for _, mode in ipairs({ "nil", "class", "custom" }) do
          for _, ccf in ipairs({ "nil", false }) do
            for _, fncc in ipairs({ "nil", true }) do
                local state = {}
                if players ~= "nil" then state.showFriendlyPlayers = players end
                if nameOnly ~= "nil" then state.friendlyNameOnly = nameOnly end
                if mode ~= "nil" then state.friendlyNameColorMode = mode end
                if ccf ~= "nil" then state.classColorFriendly = ccf end
                if fncc ~= "nil" then state.friendlyNameClassColor = fncc end
                n = n + 1
                H.SetState(state)
                H.Refresh(page)
                local only = state.friendlyNameOnly ~= false
                -- what each style shows: the pick, else its older key
                local wantOnly, wantPlate = state.classColorFriendly ~= false, state.friendlyNameClassColor == true
                if mode == "class" then wantOnly, wantPlate = true, true end
                if mode == "custom" then wantOnly, wantPlate = false, false end
                local lit = only and wantOnly or (not only and wantPlate)
                local db = env.DB()
                if nsData.FriendlyNameClass(db, true) ~= wantOnly then Wrong("the rule for Name Only", state) end
                if nsData.FriendlyNameClass(db, false) ~= wantPlate then Wrong("the rule for the health bar plates", state) end
                -- the CVar: the pick; with none, on with Class Colored Health Bar, or under Nameplate with Class Colored Names
                local cvar
                if mode == "nil" then
                    cvar = (state.classColorFriendly ~= false or (state.friendlyNameOnly == false and state.friendlyNameClassColor == true)) and 1 or 0
                else
                    cvar = mode == "class" and 1 or 0
                end
                if nsData.FriendlyNameClassCVar(db) ~= cvar then Wrong("the class colour CVar", state) end
                local off = state.showFriendlyPlayers == false
                local wantCustom = off and PLAYERS or (lit and "dim0.3" or nil)
                local wantClass = off and PLAYERS or (not lit and "dim0.3" or nil)
                if H.GateOf(custom) ~= wantCustom or H.GateOf(customClick) ~= wantCustom then Wrong("the Custom swatch is " .. tostring(H.GateOf(custom)), state) end
                if H.GateOf(class) ~= wantClass or H.GateOf(classClick) ~= wantClass then Wrong("the Class swatch is " .. tostring(H.GateOf(class)), state) end
                -- the pair writes its own two keys and nothing else, whatever is clicked or picked
                for _, c in ipairs({ custom, customClick, classClick }) do
                    for _, input in ipairs(c.inputs or {}) do
                        H.SetState(state); H.ResetLog()
                        c.set(unpack(input))
                        for _, k in ipairs(WRITES) do
                            if k ~= "friendlyNameColor" and k ~= "friendlyNameColorMode" then Wrong(c.id .. " writes " .. k, state) end
                        end
                        if STORE.classColorFriendly ~= state.classColorFriendly or STORE.friendlyNameClassColor ~= state.friendlyNameClassColor then
                            Wrong(c.id .. " changes an older key", state)
                        end
                    end
                end
            end
          end
        end
      end
    end
    check(bad == 0, msg .. ": Name Color wrong in " .. bad .. " checks over " .. n .. " settings; the first, " .. tostring(first))
    eq(n, 48, msg .. ": the settings Name Color was read in")
    -- a profile with no settings table at all: Name Only class colored, the health bar plates not
    check(nsData.FriendlyNameClass(nil, true) == true and nsData.FriendlyNameClass(nil, false) == false, msg .. ": the rule with no profile")
    -- a click sets one pick for both styles
    H.SetState({}); H.ResetLog()
    customClick.set()
    check(STORE.friendlyNameColorMode == "custom" and nsData.FriendlyNameClass(env.DB(), true) == false and nsData.FriendlyNameClass(env.DB(), false) == false,
        msg .. ": a click on Custom under Name Only does not set both styles")
    H.SetState({ friendlyNameOnly = false }); H.ResetLog()
    classClick.set()
    check(STORE.friendlyNameColorMode == "class" and nsData.FriendlyNameClass(env.DB(), true) == true and nsData.FriendlyNameClass(env.DB(), false) == true,
        msg .. ": a click on Class under Nameplate does not set both styles")
    -- a colour picked while Custom is lit by the older key alone becomes the pick, with no page refresh
    H.SetState({ friendlyNameOnly = false }); H.ResetLog()
    custom.set(0.2, 0.4, 0.6)
    check(STORE.friendlyNameColorMode == "custom" and STORE.friendlyNameColor.g == 0.4 and LOG.refresh == 0 and LOG.fpv == 1,
        msg .. ": a colour picked under an unpicked Custom does not become the pick, or refreshes the page")
    -- once picked, Health Bar Color's Class swatch no longer moves the names
    local barClass = list["FRIENDLY PLAYERS|Health Bar Color|ms:Class Color|click"]
    local barCustom, barCustomClick = list["FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color"], list["FRIENDLY PLAYERS|Health Bar Color|ms:Custom Color|click"]
    if not check(barClass and barCustom and barCustomClick, msg .. ": no Health Bar Color pair") then return end
    H.SetState({ friendlyNameColorMode = "custom", classColorFriendly = false }); H.ResetLog()
    barClass.set()
    check(STORE.classColorFriendly == true and nsData.FriendlyNameClass(env.DB(), true) == false
        and LOG.cvars[#LOG.cvars] == "nameplateUseClassColorForFriendlyPlayerUnitNames=0",
        msg .. ": Health Bar Color's Class swatch still colours Name Only's names after a Name Color pick")
    -- Health Bar Color over every saved form of its two keys: a profile shows what it showed
    -- (the toggle's key picks the lit swatch, the swatch's key is the Custom colour), and the
    -- pair writes those two keys alone
    for _, ccf in ipairs({ "nil", true, false }) do
        for _, col in ipairs({ "nil", "saved" }) do
            local state = { friendlyNameOnly = false }
            if ccf ~= "nil" then state.classColorFriendly = ccf end
            if col == "saved" then state.friendlyBarColor = { r = 0.1, g = 0.2, b = 0.3 } end
            local what = msg .. ", " .. StateText(state, STYLE)
            H.SetState(state); H.Refresh(page)
            local class = ccf ~= false
            eq(H.GateOf(barCustom), class and "dim0.3" or nil, what .. ": the Custom swatch of Health Bar Color")
            eq(H.GateOf(list["FRIENDLY PLAYERS|Health Bar Color|ms:Class Color"]), not class and "dim0.3" or nil, what .. ": the Class swatch of Health Bar Color")
            eq(Vals(barCustom.get()), col == "saved" and "0.1,0.2,0.3" or "0.314,0.8,0.408", what .. ": the Custom swatch's colour")
            for _, c in ipairs({ barCustom, barCustomClick, barClass }) do
                for _, input in ipairs(c.inputs or {}) do
                    H.SetState(state); H.ResetLog()
                    c.set(unpack(input))
                    for _, k in ipairs(WRITES) do
                        check(k == "classColorFriendly" or k == "friendlyBarColor", what .. ": " .. c.id .. " writes " .. k)
                    end
                end
            end
        end
    end
    -- a click on the unlit Custom swatch only selects it (the saved colour stays); a click on the
    -- lit one opens the picker
    H.SetState({ friendlyNameOnly = false, friendlyBarColor = { r = 0.1, g = 0.2, b = 0.3 } }); H.ResetLog()
    barCustomClick.set()
    check(STORE.classColorFriendly == false and STORE.friendlyBarColor.g == 0.2 and #LOG.calls == 1 and LOG.calls[1] == "RefreshAllSettings"
        and LOG.refresh == 1, msg .. ": a click on the unlit Custom swatch of Health Bar Color")
    H.SetState({ friendlyNameOnly = false, classColorFriendly = false }); H.ResetLog()
    barCustomClick.set()
    check(#WRITES == 0 and LOG.calls[1] == "picker", msg .. ": a click on the lit Custom swatch of Health Bar Color does not open the picker")
    -- in combat the CVar waits (the game refuses it); the pick is saved and the page refreshed
    do
        local was = InCombatLockdown
        InCombatLockdown = function() return true end
        H.SetState({ friendlyNameOnly = false }); H.ResetLog()
        barCustomClick.set()
        InCombatLockdown = was
        check(STORE.classColorFriendly == false and #LOG.cvars == 0 and LOG.refresh == 1 and LOG.fpv == 1,
            msg .. ": a Health Bar Color pick in combat writes the CVar, or is not saved")
    end
    -- Show Health Percent over every saved form: the toggle's key decides None, the new key the side
    local hp = list["FRIENDLY PLAYERS|Show Health Percent"]
    if check(hp ~= nil, msg .. ": no Show Health Percent") then
        for _, c in ipairs({ { nil, nil, "right" }, { false, nil, "right" }, { true, nil, "none" }, { nil, "left", "left" }, { false, "center", "center" },
                             { true, "left", "none" }, { nil, "right", "right" }, { nil, "top", "right" } }) do
            H.SetState({ friendlyNameOnly = false, friendlyHideHealthText = c[1], friendlyHealthTextPos = c[2] })
            eq(hp.get(), c[3], msg .. ": Show Health Percent with friendlyHideHealthText=" .. tostring(c[1]) .. ", friendlyHealthTextPos=" .. tostring(c[2]))
        end
        -- None keeps the saved side for the next time it is shown
        H.SetState({ friendlyNameOnly = false, friendlyHealthTextPos = "left" }); H.ResetLog()
        hp.set("none")
        check(STORE.friendlyHideHealthText == true and STORE.friendlyHealthTextPos == "left", msg .. ": None does not keep the saved side")
        eq(table.concat(hp.order, ","), "none,right,left,center", msg .. ": the entries of Show Health Percent, in order")
    end
    -- Level Text over every saved form of its two keys
    local lvl = list["FRIENDLY PLAYERS|Level Text"]
    if check(lvl ~= nil, msg .. ": no Level Text") then
        for _, c in ipairs({ { nil, nil, "none" }, { false, true, "none" }, { true, nil, "plain" }, { true, false, "plain" }, { true, true, "diff" } }) do
            H.SetState({ friendlyShowLevel = c[1], friendlyLevelDiffColor = c[2] })
            eq(lvl.get(), c[3], msg .. ": Level Text with friendlyShowLevel=" .. tostring(c[1]) .. ", friendlyLevelDiffColor=" .. tostring(c[2]))
        end
        -- None keeps the saved colouring
        H.SetState({ friendlyShowLevel = true, friendlyLevelDiffColor = true }); H.ResetLog()
        lvl.set("none")
        check(STORE.friendlyShowLevel == false and STORE.friendlyLevelDiffColor == true, msg .. ": None does not keep the saved level colouring")
        eq(table.concat(lvl.order, ","), "none,plain,diff", msg .. ": the entries of Level Text, in order")
    end
    -- Subtitle Text: the checklist over every saved form (the mode, and the brackets toggle its
    -- cog held); the two guild entries are never both ticked, and ticking one unticks the other
    local sTitle, sGuild, sGuildB = list["FRIENDLY PLAYERS|Subtitle Text|check:title"], list["FRIENDLY PLAYERS|Subtitle Text|check:guild"],
        list["FRIENDLY PLAYERS|Subtitle Text|check:guildB"]
    if check(sTitle and sGuild and sGuildB, msg .. ": no Subtitle Text checklist") then
        for _, mode in ipairs({ "nil", "none", "title", "guild", "both" }) do
            for _, br in ipairs({ "nil", true, false }) do
                local state = {}
                if mode ~= "nil" then state.friendlyBelowName = mode end
                if br ~= "nil" then state.friendlyBelowNameGuildBrackets = br end
                local what = msg .. ", " .. StateText(state, STYLE)
                H.SetState(state)
                local title, guild = mode == "title" or mode == "both", mode == "guild" or mode == "both"
                eq(Vals(sTitle.get(), sGuild.get(), sGuildB.get()), Vals(title, guild and br == false, guild and br ~= false), what .. ": the ticked entries of Subtitle Text")
                -- a tick of either guild form: that form alone, the title as it was
                for _, pick in ipairs({ { sGuild, false }, { sGuildB, true } }) do
                    H.SetState(state); H.ResetLog()
                    pick[1].set(true)
                    check(STORE.friendlyBelowName == (title and "both" or "guild") and STORE.friendlyBelowNameGuildBrackets == pick[2]
                        and sGuild.get() == not pick[2] and sGuildB.get() == pick[2] and sTitle.get() == title,
                        what .. ": a tick of " .. pick[1].id .. " does not leave that guild form alone ticked")
                end
                -- unticking the ticked guild form hides the line and keeps the saved brackets
                if guild then
                    H.SetState(state); H.ResetLog()
                    local ticked = (br == false) and sGuild or sGuildB
                    ticked.set(false)
                    check(STORE.friendlyBelowName == (title and "title" or "none") and STORE.friendlyBelowNameGuildBrackets == state.friendlyBelowNameGuildBrackets
                        and not sGuild.get() and not sGuildB.get(), what .. ": unticking the guild entry does not hide the guild line alone")
                end
                -- the title, with the guild line as it was
                H.SetState(state); H.ResetLog()
                sTitle.set(not title)
                check(STORE.friendlyBelowName == ((not title) and (guild and "both" or "title") or (guild and "guild" or "none"))
                    and STORE.friendlyBelowNameGuildBrackets == state.friendlyBelowNameGuildBrackets, what .. ": Player Title toggled changes the guild line")
            end
        end
        -- the checklist as it is asked for: three entries, a selection (never "All"), its writes
        -- sent to the overrides' capture, greyed whole under Blizzard Default, in the control's place
        local ck
        for _, c in ipairs(page.checks) do
            if c.host and c.host.text == "Subtitle Text" then ck = c end
        end
        if check(ck ~= nil, msg .. ": Subtitle Text has no checklist") then
            local labels = {}
            for _, item in ipairs(ck.items) do labels[#labels + 1] = item.key .. "=" .. tostring(item.label) end
            eq(table.concat(labels, ","), "title=Player Title,guild=Guild Name,guildB=<Guild Name>", msg .. ": the entries of Subtitle Text")
            local o = ck.opts
            check(o.noAllLabel == true and o.notifyWrites == true and type(o.disabled) == "function" and o.rawTooltip == true
                and o.disabledTooltip == "Requires Friendly Nameplate Style set to Name Only or Nameplate" and not ck.extra and ck.w == 170,
                msg .. ": the options Subtitle Text's checklist is asked for with")
            local pt = ck.frame._points[#ck.frame._points]
            check(ck.rgn._control == ck.frame and pt and pt[1] == "RIGHT" and pt[2] == ck.rgn and pt[3] == "RIGHT" and pt[4] == -20,
                msg .. ": the checklist is not in its half's control place")
            check(ck.rgn._stockControl ~= ck.frame and ck.rgn._stockControl._shown == false, msg .. ": the stand-in dropdown still shows under the checklist")
            -- Level Text has no cog; Subtitle Text has one, nearest the checklist, with the guild
            -- line's size as its one row, greyed with a sentence of its own
            local sc, nsc = nil, 0
            for _, c in ipairs(page.cogs) do
                check(not (c.host and c.host.text == "Level Text"), msg .. ": Level Text has a cog")
                if c.host and c.host.text == "Subtitle Text" then sc, nsc = c, nsc + 1 end
            end
            if check(nsc == 1, msg .. ": Subtitle Text carries " .. nsc .. " cogs") then
                local o = sc.opts
                check(o.title == "Subtitle Text Settings" and #o.rows == 1 and o.rows[1].label == "Guild Text Size" and not o.quiet,
                    msg .. ": the Subtitle Text cog's title and rows")
                check(type(o.disabled) == "function" and type(o.disabledTooltip) == "function" and o.rawTooltip == true,
                    msg .. ": the Subtitle Text cog is not greyed with a sentence of its own")
                check(sc.rgn == ck.rgn and sc.btn._anchor == ck.frame, msg .. ": the Subtitle Text cog does not sit beside the checklist")
                -- its sentence: the style first, then the guild line
                local keep = {}
                for _, k in ipairs({ "showFriendlyPlayers", "friendlyNameOnly", "friendlyBelowName" }) do keep[k] = STORE[k] end
                local function Tip(players, nameOnly, mode)
                    STORE.showFriendlyPlayers, STORE.friendlyNameOnly, STORE.friendlyBelowName = players, nameOnly, mode
                    return o.disabled() and o.disabledTooltip() or nil
                end
                eq(Tip(true, false, "guild"), nil, msg .. ": the cog is greyed on the health bar plate with a guild line")
                eq(Tip(true, false, "both"), nil, msg .. ": the cog is greyed on the health bar plate with a title and a guild line")
                eq(Tip(true, false, "title"), "This option requires Subtitle Text to include the Guild Name", msg .. ": the cog's sentence with no guild line")
                eq(Tip(true, false, "none"), "This option requires Subtitle Text to include the Guild Name", msg .. ": the cog's sentence with no subtitle")
                eq(Tip(true, true, "guild"), "Requires Friendly Nameplate Style set to Nameplate", msg .. ": the cog's sentence under Name Only")
                eq(Tip(true, nil, "guild"), "Requires Friendly Nameplate Style set to Nameplate", msg .. ": the cog's sentence under an unset style (Name Only)")
                eq(Tip(false, false, "guild"), "Requires Friendly Nameplate Style set to Nameplate", msg .. ": the cog's sentence under Blizzard Default")
                for k in pairs({ showFriendlyPlayers = 1, friendlyNameOnly = 1, friendlyBelowName = 1 }) do STORE[k] = keep[k] end
            end
            -- the guild colour pair: two inline swatches left of the cog, the leftmost last
            local il
            for _, c in ipairs(page.inline) do
                if c.host and c.host.text == "Subtitle Text" then il = c end
            end
            if check(il and #il.list == 2, msg .. ": Subtitle Text does not carry two inline swatches") then
                check(il.list[1].tooltip == "Custom Guild Color" and il.list[2].tooltip == "Class Guild Color", msg .. ": the guild swatches' names")
                check(sc and il.list[2]._frame._anchor == sc.btn and il.list[1]._frame._anchor == il.list[2]._frame and il.rgn._lastInline == il.list[1]._frame,
                    msg .. ": the guild swatches do not chain left of the cog")
            end
        end
    end
    for _, gone in ipairs({ "Class Colored Health Bar", "Guild Text Color", "Show Level", "Friendly Name Size (Bar Mode)" }) do
        check(RowLabeled(page, gone) == nil, msg .. ": " .. gone .. " is still a row")
    end
    -- in combat the CVar waits (the game refuses it), the pick is still saved and painted
    local was = InCombatLockdown
    InCombatLockdown = function() return true end
    H.SetState({}); H.ResetLog()
    customClick.set()
    InCombatLockdown = was
    check(STORE.friendlyNameColorMode == "custom" and #LOG.cvars == 0 and LOG.fpv == 1, msg .. ": a Name Color pick in combat writes the CVar, or is not saved")
    -- neither toggle the two controls took the place of is still on the page
    for _, gone in ipairs({ "Show EUI Friendly Player Nameplates", "Make Friendly Nameplates Name Only", "Class Colored Names" }) do
        check(RowLabeled(page, gone) == nil, msg .. ": " .. gone .. " is still a row")
    end
    eq(#page.swatches, 1, msg .. ": hand-placed swatches on the page (the friendly NPC colour alone)")
    H.SetState({})
end

-------------------------------------------------------------------------------
-- 9. Global Search: the pre-build indexes what the live page does, and the
--    settings answer to the other names they are known by
-------------------------------------------------------------------------------
local function IndexLines(index)
    local out = {}
    for _, label in ipairs(index.order) do
        local e = index.by[label]
        out[#out + 1] = (e.isSection and "# " or "") .. label .. " [" .. tostring(e.section) .. "] " .. tostring(e.tip)
    end
    return out
end
local function CheckSearch(Wd, tag, pages, forever)
    for _, name in ipairs({ TFH, FRIENDLY, GENERAL }) do
        local live = pages[name]
        H.SetState(name == TFH and { hashLineEnabled = true } or (name == FRIENDLY and PLATE_BUILD or {}))
        local pre = H.Build(Wd, name, true)
        H.SetState({})
        if check(pre.ok, tag .. ": the search pre-build of " .. name .. " raises: " .. tostring(pre.result):sub(1, 400)) and live then
            Compare(tag .. ": what the pre-build of " .. name .. " indexes, against the live page", IndexLines(pre.index), IndexLines(live.index))
            check(#pre.cogs == 0 and #pre.inline == 0 and #pre.swatches == 0 and #pre.checks == 0 and pre.framesMade == 0,
                tag .. ": the pre-build of " .. name .. " builds a cog, a swatch, a checklist or a frame")
            check(pre.header == nil and pre.cleared == 0, tag .. ": the pre-build of " .. name .. " touches the content header")
        end
        if live then
            -- every row is indexed under its section, a header as a section
            for _, r in ipairs(live.rows) do
                for _, cfg in ipairs({ r.l, r.r }) do
                    if cfg.text and cfg.text ~= "" then
                        local e = live.index.by[cfg.text]
                        check(e and e.section == r.section and not e.isSection, tag .. ": " .. name .. ", the row " .. cfg.text .. " is not indexed under " .. tostring(r.section))
                    end
                end
            end
            for _, h in ipairs(live.headers) do
                local e = live.index.by[h]
                check(e and e.isSection and e.section == h, tag .. ": " .. name .. ", the section " .. h .. " is not indexed as a section")
            end
        end
    end
    local function Words(name, label, ...)
        local e = pages[name] and pages[name].index.by[label]
        if not check(e ~= nil, tag .. ": " .. name .. " has no search entry for " .. label) then return end
        for i = 1, select("#", ...) do
            local w = select(i, ...)
            check(e.tip and e.tip:find(w, 1, true), tag .. ": " .. label .. " is not found by '" .. w:sub(1, 60) .. "'")
        end
    end
    Words(TFH, "TARGET", "TARGET, FOCUS & HOVER EFFECTS", "TARGET AND FOCUS EFFECTS")
    Words(TFH, "FOCUS", "TARGET, FOCUS & HOVER EFFECTS", "TARGET AND FOCUS EFFECTS")
    Words(TFH, "HOVER", "TARGET, FOCUS & HOVER EFFECTS")
    -- the rows that were renamed answer to their old names; the hash line's toggle to the
    -- row it brings and to its swatch
    Words(TFH, "Target Color", "Enable Target Color")
    Words(TFH, "Focus Color", "Enable Focus Color")
    Words(TFH, "Distance to Target Text", "Distance to Target Text (Range)", TIPS[TFH]["TARGET|Distance to Target Text"])
    Words(TFH, "Show Hash Line on Target", "Show Hash Line on Target at Percent", "Hash Line Location", "Hash Line Color")
    -- with the hash line off the toggle still answers to Hash Line Location, which has no entry
    do
        H.SetState({})
        local off = H.Build(Wd, TFH, true)
        local e = off.ok and off.index.by["Show Hash Line on Target"]
        check(e and e.tip and e.tip:find("Hash Line Location", 1, true) and off.index.by["Hash Line Location"] == nil,
            tag .. ": with the hash line off, Hash Line Location is not found through its toggle alone")
    end
    Words(FRIENDLY, "FRIENDLY PLAYERS", "OTHER NAMEPLATES")
    Words(FRIENDLY, "FRIENDLY NPCS", "OTHER NAMEPLATES")
    -- the dropdown answers to the two switches it took the place of, Name Color to the toggle
    Words(FRIENDLY, "Friendly Nameplate Style",
        "Show EUI Friendly Player Nameplates", "Make Friendly Nameplates Name Only",
        "Blizzard Nameplate Size", "Size of Blizzard's own nameplates, which still show for friendly players inside instances. Default is 3.")
    Words(FRIENDLY, "Name Color", "Class Colored Names", "Class Color", "Custom Color")
    Words(FRIENDLY, "Friendly Nameplate Style", "Show [] Around Group/Raid",
        "Blue [Name] for party members and your raid subgroup, orange for other raid members. Not inside instances.")
    Words(FRIENDLY, "Health Bar Color", "Class Colored Health Bar", "Class Color", "Custom Color")
    Words(FRIENDLY, "Friendly Name Size", "Friendly Name Size (Bar Mode)", "Nameplate Offset", "Distance")
    Words(FRIENDLY, "Level Text", "Show Level", "Color Level by Difficulty")
    Words(FRIENDLY, "Subtitle Text", TIPS[FRIENDLY]["FRIENDLY PLAYERS|Subtitle Text"], "Player Title", "Guild Name", "Title & Guild",
        "Guild Text Color", "Show <> Around Guild", "Name Text Settings",
        "Guild Text Size", "Size of the guild line under friendly player names.")
    -- the health bar plate's rows answer for themselves while they are on the page; under Name
    -- Only or Blizzard Default they have no entry and the style row answers to their names
    do
        local OFF_PAGE = { "Health Bar Width", "Health Bar Height", "Health Bar Color", "Class Colored Health Bar", "Show Health Percent" }
        local on = pages[FRIENDLY] and pages[FRIENDLY].index.by["Friendly Nameplate Style"]
        if check(on ~= nil, tag .. ": no search entry for Friendly Nameplate Style") then
            for _, w in ipairs(OFF_PAGE) do
                check(not on.tip:find(w, 1, true), tag .. ": under Nameplate, Friendly Nameplate Style also answers to " .. w)
            end
        end
        for _, state in ipairs({ {}, { showFriendlyPlayers = false }, { showFriendlyPlayers = false, friendlyNameOnly = false } }) do
            H.SetState(state)
            local pre = H.Build(Wd, FRIENDLY, true)
            local e = pre.ok and pre.index.by["Friendly Nameplate Style"]
            if check(e and e.tip, tag .. ": no search entry for Friendly Nameplate Style under " .. StateText(state, STYLE)) then
                for _, w in ipairs(OFF_PAGE) do
                    check(e.tip:find(w, 1, true), tag .. ": under " .. StateText(state, STYLE) .. ", " .. w .. " is not found through Friendly Nameplate Style")
                end
                for _, label in ipairs({ "Health Bar Width", "Health Bar Height", "Health Bar Color", "Show Health Percent" }) do
                    check(pre.index.by[label] == nil, tag .. ": under " .. StateText(state, STYLE) .. ", " .. label .. " has a search entry of its own")
                end
            end
        end
        -- the name size row under Name Only answers to its own tooltip and cog
        H.SetState({})
        local pre = H.Build(Wd, FRIENDLY, true)
        local e = pre.ok and pre.index.by["Friendly Name Size"]
        check(e and e.tip and e.tip:find("Adjusts the size of friendly player names shown in Name Only mode. Default is 15.", 1, true)
            and e.tip:find("Name Distance", 1, true) and not e.tip:find("Bar Mode", 1, true),
            tag .. ": under Name Only, Friendly Name Size is not found by its tooltip and its cog")
        H.SetState({})
    end
    Words(FRIENDLY, "Friendly NPC Name Size", "Name Color")
    Words(FRIENDLY, "Friendly NPC Title Size", "Title Color")
    Words(GENERAL, "Minor Enemy Scale (Percent)", TIPS[GENERAL]["EXTRAS|Minor Enemy Scale (Percent)"], "TARGET AND FOCUS EFFECTS", "Scale Target Nameplate")
    Words(GENERAL, "Non-Elite Enemy Scale (Percent)", TIPS[GENERAL]["EXTRAS|Non-Elite Enemy Scale (Percent)"], "TARGET AND FOCUS EFFECTS", "Scale Target Nameplate")
    Words(GENERAL, "Show Enemy Pet Nameplates", TIPS[GENERAL]["EXTRAS|Show Enemy Pet Nameplates"], "OTHER NAMEPLATES")
    -- Player Name Format explains itself on WoW Forever alone
    local pnf = pages[FRIENDLY] and pages[FRIENDLY].index.by["Player Name Format"]
    eq(pnf and pnf.tip, forever and "Friendly player names on nameplates, in both modes." or nil, tag .. ": the tooltip of Player Name Format")
end

-------------------------------------------------------------------------------
-- 11. The click navigation of the three header previews: the kit (env.Nav), then
--     each page: which parts carry an overlay, where a click lands, the hint line,
--     and what makes overlays (only a build whose preview is new)
-------------------------------------------------------------------------------
-- A frame in a message: its name, the part of the preview it is, or its row half's label.
local function Nm(f)
    if type(f) ~= "table" then return tostring(f) end
    local n = rawget(f, "_name") or rawget(f, "_part")
    if n then return n end
    local cfg = rawget(f, "_cfg")
    if cfg then return "the half " .. tostring(cfg.text) end
    return "a " .. tostring(rawget(f, "_kind"))
end
-- Runs fn (a press, or a call of a page's navigator), then the timers it started (the
-- highlight's wait): what it scrolled to, highlighted and dismissed, and the fades.
function H.Press(Wd, fn)
    local nav = Wd.nav
    local s0, g0, d0, f0 = #nav.scrolls, #nav.glows, #nav.dismiss, #nav.fades
    H.ResetLog()
    fn()
    local timers = LOG.after
    LOG.after = {}
    for _, t in ipairs(timers) do t() end
    local r = { scrolls = {}, glows = {}, dismiss = {}, timers = #timers, fades = #nav.fades - f0 }
    for i = s0 + 1, #nav.scrolls do r.scrolls[#r.scrolls + 1] = nav.scrolls[i] end
    for i = g0 + 1, #nav.glows do r.glows[#r.glows + 1] = nav.glows[i] end
    for i = d0 + 1, #nav.dismiss do r.dismiss[#r.dismiss + 1] = nav.dismiss[i] end
    return r
end
-- The hint's fade (the shared helper's ticker), run to its end.
function H.RunFades(Wd)
    for _, t in ipairs(Wd.nav.fades) do
        local n = 0
        while not t.cancelled and n < 100 do t.fn(); n = n + 1 end
    end
end
-- Where a click must land: 40 above its section header (never above the page's top),
-- and the row half named (left: the left half, or the right one on a row with no left
-- half; right: the right half), or the row itself (no half named, or none to take).
local function Landing(section, row, side)
    local _, _, _, _, y = section:GetPoint(1)
    local target = row
    if side == "left" then target = rawget(row, "_leftRegion") or rawget(row, "_rightRegion") or row
    elseif side == "right" then target = rawget(row, "_rightRegion") or row end
    return y and math.max(0, math.abs(y) - 40), target
end
-- A click scrolls once, and after its wait plays glow glowId once on its target; with
-- no section it does nothing at all.
local function CheckLanding(msg, r, section, row, side, glowId)
    if not section then
        check(#r.scrolls == 0 and #r.glows == 0 and r.timers == 0, msg .. ": does something (a scroll, a timer or a highlight)")
        return
    end
    local y, target = Landing(section, row, side)
    check(y ~= nil and #r.scrolls == 1 and r.scrolls[1] == y,
        msg .. ": scrolls to " .. tostring(r.scrolls[1]) .. " (" .. #r.scrolls .. " scroll(s)), want " .. tostring(y))
    local g = r.glows[1]
    check(#r.glows == 1 and g.target == target and g.id == glowId,
        msg .. ": highlights " .. Nm(g and g.target) .. " with glow " .. tostring(g and g.id) .. " (" .. #r.glows .. " in all), want "
        .. Nm(target) .. " with glow " .. tostring(glowId))
end
-- The row of a page holding a label, and the side of the half that holds it.
local function RowOf(page, label)
    for _, r in ipairs(page.rows) do
        if r.l.text == label then return r, "left" end
        if r.r.text == label then return r, "right" end
    end
end
-- A click on a key of a new page lands on the half holding the label, in its section.
local function CheckPageLanding(msg, r, page, want, glowId)
    local row, side = RowOf(page, want[2])
    if not check(row and row.section == want[1], msg .. ": no row " .. want[2] .. " under " .. want[1]) then return end
    CheckLanding(msg, r, page.sections[want[1]], row.row, side, glowId)
end
-- The overlays the factory made since mark.
local function OvsSince(Wd, mark)
    local out = {}
    for i = mark + 1, #Wd.nav.ovs do out[#out + 1] = Wd.nav.ovs[i] end
    return out
end
local function Under(f, root)
    while f do
        if f == root then return true end
        f = rawget(f, "_parent")
    end
    return false
end
local HINT_TEXT = "Click elements to scroll to and highlight their options"
-- The kit's hint on a page: shown on host, its bottom y above hdr's bottom.
local function CheckHint(msg, fs, host, hdr, y)
    check(fs and fs:IsShown() and fs._parent == host and fs._text == HINT_TEXT and fs._alpha == 0.45 and fs._kept == true
        and fs._font and fs._font[2] == 11 and fs._color and fs._color[1] == 1 and fs._color[2] == 1 and fs._color[3] == 1
        and #fs._points == 1 and fs._points[1][1] == "BOTTOM" and fs._points[1][2] == hdr and fs._points[1][3] == "BOTTOM"
        and fs._points[1][4] == 0 and fs._points[1][5] == y,
        msg .. ": the hint line is not shown on its host, kept, at " .. tostring(y) .. " over the header's bottom (" .. Nm(fs and fs._parent) .. ")")
end

-- 11a. The kit, on a page id of its own
local function CheckNavKit(Wd, tag)
    local env, nav = Wd.env, Wd.nav
    local Nav = env.Nav
    if not check(type(Nav) == "table" and type(Nav.Page) == "function" and type(Nav.Hint) == "function"
        and type(Nav.HintH) == "function" and type(Nav.HintRestore) == "function", tag .. ": the options env hands out no click navigation kit (env.Nav)") then
        return
    end
    check(env.PAGE_DISPLAY == DISPLAY and env.PAGE_TFH == TFH and env.PAGE_FRIENDLY == FRIENDLY, tag .. ": the kit's page ids are not the page names")
    EllesmereUIDB = {}
    local ID, msg = "a kit check page", tag .. ": the kit"
    -- no page is being built
    PAGE = nil
    local P = Nav.Page(ID)
    check(type(P.Go) == "function" and type(P.Overlay) == "function" and Nav.Page(ID) == P, msg .. ": Nav.Page(id) is not one navigator with Go and Overlay")
    local g0 = nav.glowsMade
    Nav.Page(ID)
    eq(nav.glowsMade, g0, msg .. ": glows made by Nav.Page(id) with no map")
    local r = H.Press(Wd, function() P.Go("row") end)
    check(#r.scrolls == 0 and #r.glows == 0 and #r.dismiss == 0 and r.timers == 0, msg .. ": a click before the page mapped its keys does something")
    -- a map: one glow, green, 2 px through the panel's pixel scale, not snapped
    local parent = Frame("Page")
    local function Sec(y) local s = Frame("SectionHeader", parent); s._name = "section at " .. y; s:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y); return s end
    local function Row(name) local w = Frame("Row", parent); w._name = name; w._leftRegion, w._rightRegion = Frame("Region", w), Frame("Region", w)
        w._leftRegion._name, w._rightRegion._name = name .. ".L", name .. ".R"; return w end
    local secA, rowA, secTop, noPoint = Sec(-500), Row("rowA"), Sec(-25), Frame("SectionHeader", parent)
    local P1 = Nav.Page(ID, { row = { section = secA, target = rowA, slotSide = "right" }, whole = { section = secA, target = rowA },
        left = { section = secA, target = rowA, slotSide = "left" }, top = { section = secTop, target = rowA, slotSide = "left" },
        fn = function() return { section = secA, target = rowA, slotSide = "left" } end, nofn = function() return nil end,
        nosec = { target = rowA }, norow = { section = secA }, nopoint = { section = noPoint, target = rowA } })
    local opts = nav.glowOpts[nav.glowsMade]
    local px = opts and opts.thickness
    if type(px) == "function" then px = px() end
    check(P1 == P and nav.glowsMade == g0 + 1 and opts and opts.color == EllesmereUI.ELLESMERE_GREEN and opts.noSnap == true and px == 2,
        msg .. ": Nav.Page(id, map) does not keep its navigator and make one green glow, 2 px through the panel's scale, unsnapped")
    local glow = nav.glowsMade
    CheckLanding(msg .. ", a key on a right half", H.Press(Wd, function() P.Go("row") end), secA, rowA, "right", glow)
    CheckLanding(msg .. ", a key on a left half", H.Press(Wd, function() P.Go("left") end), secA, rowA, "left", glow)
    CheckLanding(msg .. ", a key on a whole row", H.Press(Wd, function() P.Go("whole") end), secA, rowA, nil, glow)
    CheckLanding(msg .. ", a key read through a function", H.Press(Wd, function() P.Go("fn") end), secA, rowA, "left", glow)
    CheckLanding(msg .. ", a section near the top", H.Press(Wd, function() P.Go("top") end), secTop, rowA, "left", glow)
    for _, key in ipairs({ "unknown", "nofn", "nosec", "norow" }) do
        r = H.Press(Wd, function() P.Go(key) end)
        check(#r.scrolls == 0 and #r.glows == 0 and #r.dismiss == 0 and r.timers == 0, msg .. ": the key " .. key .. " (nothing to land on) does something")
    end
    -- a section header with no point: nothing scrolls or glows
    CheckLanding(msg .. ", a section with no point", H.Press(Wd, function() P.Go("nopoint") end))
    -- the glow waits 0.15 s, and plays on no half dressed again meanwhile (a page built again)
    H.ResetLog()
    local gl0 = #nav.glows
    rowA._rightRegion._gen = 1
    P.Go("row")
    check(#LOG.after == 1 and Wd.lastAfter == 0.15 and #nav.glows == gl0, msg .. ": the highlight does not wait 0.15 s")
    rowA._rightRegion._gen = 2
    for _, t in ipairs(LOG.after) do t() end
    eq(#nav.glows, gl0, msg .. ": highlights played on a half dressed again before the wait ended")
    rowA._rightRegion._gen = nil
    -- no scroll frame: nothing scrolls or glows
    local sf = EllesmereUI._scrollFrame
    EllesmereUI._scrollFrame = nil
    CheckLanding(msg .. ", with no scroll frame", H.Press(Wd, function() P.Go("row") end))
    EllesmereUI._scrollFrame = sf

    -- an overlay: the shared factory over the page's navigator, its key, level and options
    local host = Frame("Frame", parent)
    host:SetFrameLevel(7)
    local el = Frame("Frame", host)
    el:SetFrameLevel(9)
    local n0, f0 = #nav.ovs, nav.frames
    local btn, hlBase, hlCont = P.Overlay(el, "row", false, 40)
    local rec = nav.ovs[#nav.ovs]
    check(#nav.ovs == n0 + 1 and rec.navigate == P.Go and rec.key == "row" and rec.isText == false and rec.level == 40 and rec.opts == nil
        and rec.style and rec.style.container == true and nav.frames == f0 + 2,
        msg .. ": P.Overlay is not the shared factory over P.Go, its key and level, its border on a frame of its own")
    check(btn._parent == el and btn._level == 40 and btn._clicks == "LeftButtonDown" and hlBase == btn and hlCont and hlCont._parent == btn
        and hlCont._level == 41 and btn._points[1] and btn._points[1][1] == "ALL" and btn._points[1][2] == el, msg .. ": the overlay's frames")
    local tbtn = P.Overlay(Frame("FontString", el), "row", true, 12, { hlBehindText = true })
    rec = nav.ovs[#nav.ovs]
    check(rec.isText == true and rec.level == 12 and rec.opts and rec.opts.hlBehindText == true and tbtn._parent == el and type(tbtn._resizeToText) == "function",
        msg .. ": P.Overlay does not hand a text overlay its options")
    -- a later build's map: the same overlay lands on the newer rows, with the newer glow
    local secB, rowB = Sec(-900), Row("rowB")
    Nav.Page(ID, { row = { section = secB, target = rowB, slotSide = "left" } })
    CheckLanding(msg .. ", an overlay made before a later map", H.Press(Wd, function() btn._scripts.OnMouseDown(btn) end), secB, rowB, "left", nav.glowsMade)

    -- the hint: made once on its host, kept, at its spot; 29 px while it shows
    EllesmereUIDB = {}
    local hostH, hdr = Frame("Frame"), Frame("Header")
    local notes0 = #Wd.notes
    local h, fs = Nav.Hint(ID, hostH, hdr, 17, 70)
    check(h == 99 and #Wd.notes == notes0 + 1, msg .. ": Nav.Hint returns " .. tostring(h) .. " for a 70 px header, or did not make one hint")
    CheckHint(msg, fs, hostH, hdr, 17)
    eq(Nav.HintH(ID), 29, msg .. ": Nav.HintH while the hint shows")
    local h2, fs2 = Nav.Hint(ID, Frame("Frame"), hdr, 21, 80)
    check(h2 == 109 and fs2 == fs and #Wd.notes == notes0 + 1 and fs._points[1][5] == 21, msg .. ": a later header build does not take the same hint to its host and spot")
    -- a hint whose host was dropped is made again
    fs._parent = nil
    local h3, fs3 = Nav.Hint(ID, hostH, hdr, 17, 80)
    check(h3 == 109 and fs3 ~= fs and #Wd.notes == notes0 + 2, msg .. ": a hint whose host was dropped is not made again")
    fs = fs3
    -- the cache restore: the header at its base and the hint's line
    Wd.silentH = nil
    Nav.HintRestore(ID)
    eq(Wd.silentH, 109, msg .. ": the header's height on a cache restore while the hint shows")
    eq(Nav.HintH(ID, 90), 29, msg .. ": Nav.HintH with a new base")
    Nav.HintRestore(ID)
    eq(Wd.silentH, 119, msg .. ": the header's height on a cache restore after a new base")
    -- the first click dismisses its page's hint with that base and spot; the fade takes the
    -- header back to the base
    r = H.Press(Wd, function() P.Go("row") end)
    local d = r.dismiss[1]
    check(#r.dismiss == 1 and d.hint == fs and d.shown and not d.flag and d.base == 90 and d.hintH == 29 and d.y == 17 and r.fades == 1,
        msg .. ": the first click does not dismiss this page's hint with its base, spot and height")
    H.RunFades(Wd)
    check(not fs:IsShown() and EllesmereUIDB.previewHintDismissed == true and Wd.silentH == 90, msg .. ": the dismissed hint does not fade out, or the header does not end at its base")
    eq(Nav.HintH(ID), 0, msg .. ": Nav.HintH once the hint is gone")
    r = H.Press(Wd, function() P.Go("row") end)
    eq(r.fades, 0, msg .. ": fades started by a click after the dismissal")
    -- dismissed: a restore hides it and sets the base; a header build shows none and adds nothing
    fs:Show()
    Wd.silentH = nil
    Nav.HintRestore(ID)
    check(not fs:IsShown() and Wd.silentH == 90, msg .. ": a cache restore after the dismissal")
    local h4, fs4 = Nav.Hint(ID, hostH, hdr, 17, 70)
    check(h4 == 70 and fs4 == fs and not fs:IsShown() and #Wd.notes == notes0 + 2, msg .. ": a header built after the dismissal")
    -- dismissed before any hint was made: none is made
    local h5, fs5 = Nav.Hint("another kit check page", hostH, hdr, 17, 70)
    check(h5 == 70 and fs5 == nil and #Wd.notes == notes0 + 2, msg .. ": a hint made for an account that dismissed it")
    -- that page has no hint: with the dismissal cleared again, a cache restore adds no line for one
    EllesmereUIDB = {}
    Wd.silentH = nil
    Nav.HintRestore("another kit check page")
    eq(Wd.silentH, 70, msg .. ": the header's height on a cache restore of a page that has no hint")
    -- pages with no navigator, or no hint base: nothing
    EllesmereUIDB = nil
    local h6 = Nav.Hint("a third kit check page", hostH, hdr, 17, 50)
    eq(h6, 79, msg .. ": the hint with no account table")
    EllesmereUIDB = {}
    eq(Nav.HintH("a page never built"), 0, msg .. ": Nav.HintH of a page with no navigator")
    Wd.silentH = nil
    Nav.HintRestore("a page never built")
    Nav.Page("a page with no hint")
    Nav.HintRestore("a page with no hint")
    eq(Wd.silentH, nil, msg .. ": a cache restore of a page with no hint sets a height")
    EllesmereUIDB = {}
end

-- 11b. Enemies (the Display page): the overlays it has always made, and where each
-- key lands (rows of the stand-in section builders, by name)
local DISPLAY_STATIC = {
    debuffDuration = { "TEXT", "auraDurPosRow", "left" }, buffDuration = { "TEXT", "auraDurPosRow", "right" },
    ccDuration = { "TEXT", "auraTimerStackRow", "left" }, auraStack = { "TEXT", "auraTimerStackRow", "right" },
    castBar = { "HEALTH BAR", "castBarHeightRow", "left" }, castIcon = { "HEALTH BAR", "showCastIconRow", "right" },
    castTimer = { "HEALTH BAR", "castTimerRow", "left" }, castName = { "TEXT", "spellNameRow", "left" },
    castTarget = { "TEXT", "spellNameRow", "right" }, healthBar = { "HEALTH BAR", "healthBarHeightRow" },
    classResource = { "CLASS RESOURCE", "classResourceSection" },
}
local DISPLAY_CORE = { top = { "coreRow1", "left" }, left = { "coreRow1", "right" }, right = { "coreRow2", "left" },
    topleft = { "coreRow2", "right" }, topright = { "coreRow3", "left" }, bottom = { "coreRow3", "right" } }
local DISPLAY_TEXT = { textSlotTop = { "textRow1", "left" }, textSlotRight = { "textRow1", "right" },
    textSlotLeft = { "textRow2", "left" }, textSlotCenter = { "textRow2", "right" }, textSlotBottomLeft = { "textRow3", "right" } }
local DISPLAY_KEYS = { "debuffDuration", "buffDuration", "ccDuration", "auraStack", "castBar", "castIcon", "castTimer", "castName",
    "castTarget", "healthBar", "classResource", "classicLevel", "foreverLevelBox", "debuffIcon", "buffIcon", "ccIcon", "raidMarker",
    "classIcon", "questText", "factionIcon", "enemyName", "healthText", "healthNumber", "levelText", "targetOfTarget", "nope",
    "custom_textSlotTop", "custom_textSlotRight", "custom_textSlotLeft", "custom_textSlotCenter", "custom_textSlotBottomLeft",
    "custom_textSlotBottomRight", "custom_textSlotTopLeft", "custom_textSlotTopRight" }
-- { section, row, side } for a key under the saved settings, or nil: a click does nothing.
local function DisplayWant(Wd, key)
    if DISPLAY_STATIC[key] then return DISPLAY_STATIC[key] end
    local d = nsData.defaults
    local function V(k) local v = STORE[k]; if v == nil then v = d[k] end; return v end
    local function Core(pos)
        local cell = pos and pos ~= "none" and DISPLAY_CORE[pos]
        if not cell then return { "CORE POSITIONS", "coreRow1" } end
        return { "CORE POSITIONS", cell[1], cell[2] }
    end
    -- the first text position holding one of the elements (in the elements' order)
    local function Slot(...)
        for i = 1, select("#", ...) do
            local el = select(i, ...)
            for _, slot in ipairs(nsData.textSlotKeys) do
                if V(slot) == el then return slot end
            end
        end
    end
    local function Text(slot)
        local cell = slot and DISPLAY_TEXT[slot]
        if not cell then return { "CORE TEXT POSITIONS", "textFirstRow" } end
        return { "CORE TEXT POSITIONS", cell[1], cell[2] }
    end
    local SLOT = { debuffIcon = "debuffSlot", buffIcon = "buffSlot", ccIcon = "ccSlot", raidMarker = "raidMarkerPos", classIcon = "classificationSlot" }
    if SLOT[key] then return Core(V(SLOT[key])) end
    if key == "questText" then return Core(STORE.questTextSlot or "none") end
    if key == "factionIcon" then return Core(STORE.classificationIncludeFaction and V("classificationSlot") or V("factionSlot")) end
    if key == "enemyName" then return Text(Slot("enemyName", "levelName", "nameLevel")) end
    if key == "healthText" then
        return Text(Slot("healthPercent", "healthPercentNoSign", "healthPctNum", "healthNumPct", "healthPctNumDash", "healthNumPctDash"))
    end
    if key == "healthNumber" then return Text(Slot("healthNumber")) end
    if key == "levelText" then return Text(Slot("level")) end
    if key == "targetOfTarget" then return Text(Slot("targetOfTarget")) end
    local custom = key:match("^custom_(.+)$")
    if custom then return Text(custom) end
    if key == "classicLevel" and Wd.displayStockRows then return { "STYLE", "classicPlateRow", "left" } end
    if key == "foreverLevelBox" and Wd.displayStockRows then return { "STYLE", "foreverBoxRow", "left" } end
    return nil
end
local function CheckDisplayKey(Wd, msg, r, key, glowId)
    local w = DisplayWant(Wd, key)
    if w then
        CheckLanding(msg .. " " .. key, r, Wd.display[w[1]], Wd.display[w[2]], w[3], glowId)
    else
        CheckLanding(msg .. " " .. key, r)
    end
end
-- The overlays the Display page makes on its preview: part > key (sorted), as it always made them.
local DISPLAY_OVERLAYS = { "buff1.dur>buffDuration", "buff1>buffIcon", "castName>castName", "castTimer>castTimer", "cc1.dur>ccDuration",
    "cc1>ccIcon", "cc2.dur>ccDuration", "cc2>ccIcon", "classIcon>classIcon", "classicLevel>classicLevel", "customRight>custom_textSlotRight",
    "customTop>custom_textSlotTop", "debuff1.dur>debuffDuration", "debuff1.stack>auraStack", "debuff1>debuffIcon", "debuff2.dur>debuffDuration",
    "debuff2>debuffIcon", "debuff3>debuffIcon", "faction>factionIcon", "fvLevelBox>foreverLevelBox", "health>healthBar", "hpNumber>healthNumber",
    "hpText>healthText", "lvlText>levelText", "name>enemyName", "questText>questText", "raid>raidMarker", "tot>targetOfTarget" }
local function OverlayList(recs)
    local out = {}
    for _, o in ipairs(recs) do out[#out + 1] = Nm(o.element) .. ">" .. tostring(o.key) end
    table.sort(out)
    return out
end
local function CheckNavDisplay(Wd, tag)
    local nav, os, Nav = Wd.nav, Wd.optState, Wd.env.Nav
    local msg = tag .. ": Enemies"
    EllesmereUIDB = {}
    H.SetState({ showClassPower = true })
    Wd.pvVariant, Wd.displayStockRows, Wd.noClassHeaderPoint = nil, nil, nil
    local o0, g0, c0 = #nav.ovs, nav.glowsMade, #Wd.created
    local page = H.Build(Wd, DISPLAY)
    if not check(page.ok, msg .. ": the page does not build: " .. tostring(page.result)) then return end
    local pv = os.activePreview
    local recs = OvsSince(Wd, o0)
    Compare(msg .. ": the overlays on the preview (part > key)", OverlayList(recs), DISPLAY_OVERLAYS)
    eq(nav.glowsMade, g0 + 1, msg .. ": glows made by a build")
    local glow = nav.glowsMade
    local P = Nav.Page(DISPLAY)
    -- each made over this build's preview, clicking the kit's Display navigator, in the kit's style;
    -- aura icons at the health bar + 15 with the border behind their texts, their texts 10 over
    -- that, the cast bar's texts over the cast bar's buttons
    local hl = pv._health:GetFrameLevel()
    for _, o in ipairs(recs) do
        local n = Nm(o.element)
        check(Under(o.element, pv) and o.navigate == P.Go and o.style and o.style.container == true and o.page == DISPLAY,
            msg .. ": the overlay of " .. n .. " is not the kit's, over this build's preview")
        local want
        if n:match("^cc%d$") or n:match("^buff%d$") or n:match("^debuff%d$") then
            want = hl + 15
            check(o.opts and o.opts.hlBehindText == true and o.isText == false, msg .. ": the overlay of " .. n .. " does not draw its border behind the icon's texts")
        elseif n:match("%.dur$") or n:match("%.stack$") then want = hl + 25
        elseif n == "castName" or n == "castTimer" then want = pv._cast:GetFrameLevel() + 25
        end
        eq(o.level, want, msg .. ": the level of the overlay of " .. n)
    end
    -- shown with what they cover: the raid marker and the Rare/Quest icon only while their eyes
    -- are on, the faction badge, the level and the custom text while they show
    local shown = {}
    for _, o in ipairs(recs) do if o.btn:IsShown() then shown[#shown + 1] = Nm(o.element) end end
    table.sort(shown)
    eq(table.concat(shown, ","), "buff1,buff1.dur,castName,castTimer,cc1,cc1.dur,cc2,cc2.dur,classicLevel,customTop,debuff1,debuff1.dur,"
        .. "debuff1.stack,debuff2,debuff2.dur,debuff3,faction,fvLevelBox,health,hpNumber,hpText,name,questText,tot", msg .. ": the overlays that show")
    check(pv._raidOverlay and pv._raidOverlay._parent == pv._raidFrame and pv._classOverlay and pv._factionOverlay
        and pv._textOverlays and #pv._textOverlays == 16, msg .. ": the overlays the preview keeps for its repaint")
    -- the hand-made buttons: the cast icon, the cast bar and the class resource
    local buttons = {}
    for i = c0 + 1, #Wd.created do
        local f = Wd.created[i]
        if f._kind == "Button" and f._scripts.OnMouseDown then buttons[#buttons + 1] = f end
    end
    eq(#buttons, 3, msg .. ": the hand-made buttons (cast icon, cast bar, class resource)")
    local cp = buttons[3]
    -- a click on every overlay and button, with every key under three sets of positions
    for _, o in ipairs(recs) do
        CheckDisplayKey(Wd, msg .. ", a click on " .. Nm(o.element) .. " >", H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end), o.key, glow)
    end
    for i, key in ipairs({ "castIcon", "castBar", "classResource" }) do
        local b = buttons[i]
        if b then CheckDisplayKey(Wd, msg .. ", a click on its button >", H.Press(Wd, function() b._scripts.OnMouseDown(b) end), key, glow) end
    end
    local SETS = {
        { showClassPower = true },
        { showClassPower = true, classificationIncludeFaction = true, factionSlot = "bottom", questTextSlot = "left", textSlotTop = "none",
          textSlotLeft = "levelName", textSlotCenter = "healthNumber", textSlotRight = "healthPctNumDash", textSlotBottomLeft = "targetOfTarget",
          textSlotTopLeft = "level", debuffSlot = "topleft", buffSlot = "bottom", ccSlot = "none", raidMarkerPos = "left", classificationSlot = "right" },
        { showClassPower = true, debuffSlot = "none", buffSlot = "none", ccSlot = "none", raidMarkerPos = "none", classificationSlot = "none",
          factionSlot = "none", questTextSlot = "bottom", textSlotTop = "none", textSlotRight = "none", textSlotLeft = "none", textSlotCenter = "none",
          textSlotBottomLeft = "none", textSlotBottomRight = "none", textSlotTopLeft = "none", textSlotTopRight = "none" },
    }
    for i, set in ipairs(SETS) do
        H.SetState(set)
        for _, key in ipairs(DISPLAY_KEYS) do
            CheckDisplayKey(Wd, msg .. ", positions " .. i .. ", the key", H.Press(Wd, function() P.Go(key) end), key, glow)
        end
    end
    -- the class resource's button takes no click while the class resource is off
    H.SetState({ showClassPower = false })
    H.Refresh(page)
    check(cp and cp._mouse == false and cp._alpha == 0, msg .. ": the class resource's button takes clicks while the class resource is off")
    H.SetState({ showClassPower = true })
    H.Refresh(page)
    check(cp and cp._mouse == true and cp._alpha == 1, msg .. ": the class resource's button takes no clicks while the class resource is on")

    -- the hint: on the preview, 17 over the header's bottom; the header 29 taller while it shows
    -- (the preview's 60 and its pads' 10 without it). The clicks above dismissed it: build anew.
    EllesmereUIDB = {}
    local hb = H.Build(Wd, DISPLAY)
    pv = os.activePreview
    local fs = Nav.Page(DISPLAY).fs
    eq(hb.header and hb.header.height, 99, msg .. ": the header's height with the hint")
    CheckHint(msg, fs, pv, hb.header.frame, 17)
    pv:Update()
    eq(Wd.updateH, 99, msg .. ": the header's height a repaint gives while the hint shows")
    Wd.silentH = nil
    Wd.cfg.onPageCacheRestore(DISPLAY)
    check(Wd.silentH == 99 and fs:IsShown(), msg .. ": a cache restore while the hint shows")
    -- the page shown again and the panel's show: repainted (the overlays of the texts a
    -- position may hold follow their texts), nothing made
    local built = OvsSince(Wd, #nav.ovs - #DISPLAY_OVERLAYS)
    local function OvOf(el) for _, o in ipairs(built) do if o.element == el then return o.btn end end end
    local o4, f4, c4 = #nav.ovs, nav.frames, #Wd.created
    pv._hpNumber:Hide()
    pv._lvlText:Show()
    Wd.cfg.onPageCacheRestore(DISPLAY)
    check(not OvOf(pv._hpNumber):IsShown() and OvOf(pv._lvlText):IsShown(), msg .. ": a cache restore does not take the text overlays to their texts")
    pv._hpNumber:Show()
    pv._lvlText:Hide()
    Wd.onShow[1]()
    check(OvOf(pv._hpNumber):IsShown() and not OvOf(pv._lvlText):IsShown(), msg .. ": the panel's show does not take the text overlays to their texts")
    check(#nav.ovs == o4 and nav.frames == f4 and #Wd.created == c4, msg .. ": a cache restore or the panel's show makes overlays or buttons")
    -- the first click dismisses it: the header back to 70, the height the header was built
    -- with (a repaint since, here of a taller plate, moves no base on this page), and a
    -- repaint counts no hint
    pv._standInH = 80
    pv:Update()
    eq(Wd.updateH, 119, msg .. ": the header's height a taller plate's repaint gives while the hint shows")
    local hit
    for _, o in ipairs(built) do if o.key == "healthBar" then hit = o end end
    local r = H.Press(Wd, function() hit.btn._scripts.OnMouseDown(hit.btn) end)
    local d = r.dismiss[1]
    check(d and d.hint == fs and d.shown and not d.flag and d.base == 70 and d.hintH == 29 and d.y == 17 and r.fades == 1,
        msg .. ": the first click does not dismiss the hint with the header's base")
    H.RunFades(Wd)
    check(not fs:IsShown() and Wd.silentH == 70 and EllesmereUIDB.previewHintDismissed == true, msg .. ": the hint's fade")
    pv:Update()
    eq(Wd.updateH, 90, msg .. ": the header's height a taller plate's repaint gives after the dismissal")
    pv._standInH = nil
    pv:Update()
    eq(Wd.updateH, 70, msg .. ": the header's height a repaint gives after the dismissal")
    Wd.cfg.onPageCacheRestore(DISPLAY)
    check(Wd.silentH == 70 and not fs:IsShown(), msg .. ": a cache restore after the dismissal")
    local hd = H.Build(Wd, DISPLAY)
    check(hd.header and hd.header.height == 70 and not fs:IsShown(), msg .. ": a header built after the dismissal")

    -- the search pre-build: no overlay, button, glow or hint; a click still lands on the live rows
    local live = {}
    for k, v in pairs(Wd.display) do live[k] = v end
    local o1, g1, f1, n1 = #nav.ovs, nav.glowsMade, nav.frames, #Wd.notes
    local pre = H.Build(Wd, DISPLAY, true)
    check(pre.ok and #nav.ovs == o1 and nav.glowsMade == g1 and nav.frames == f1 and #Wd.notes == n1 and next(pre.made) == nil,
        msg .. ": the search pre-build makes overlays, buttons, a glow or a hint")
    local again = H.Press(Wd, function() P.Go("healthBar") end)
    check(#again.glows == 1 and again.glows[1].target == live.healthBarHeightRow and again.glows[1].id == g1,
        msg .. ": a click after the search pre-build does not land on the live page's row")

    -- a rebuild: one new set, on the new preview; the old preview's set is left alone
    local old = os.activePreview
    local o2 = #nav.ovs
    H.Build(Wd, DISPLAY)
    local recs2 = OvsSince(Wd, o2)
    local onOld = 0
    for _, o in ipairs(recs2) do if Under(o.element, old) then onOld = onOld + 1 end end
    check(#recs2 == #DISPLAY_OVERLAYS and onOld == 0 and os.activePreview ~= old, msg .. ": a rebuild makes " .. #recs2 .. " overlays, " .. onOld .. " of them on the old preview")
    -- other previews: the stock styles' rows, a section with no point, the class resource as a bar or none, no badge
    Wd.displayStockRows = true
    H.SetState({ showClassPower = true })
    H.Build(Wd, DISPLAY)
    for _, key in ipairs({ "classicLevel", "foreverLevelBox" }) do
        CheckDisplayKey(Wd, msg .. ", stock styles' rows, the key", H.Press(Wd, function() P.Go(key) end), key, nav.glowsMade)
    end
    Wd.displayStockRows, Wd.noClassHeaderPoint = nil, true
    H.Build(Wd, DISPLAY)
    CheckLanding(msg .. ", a class resource section with no point", H.Press(Wd, function() P.Go("classResource") end))
    Wd.noClassHeaderPoint = nil
    for _, v in ipairs({ "barPips", "noPips", "noFaction" }) do
        Wd.pvVariant = v
        local c1 = #Wd.created
        local o3 = #nav.ovs
        H.Build(Wd, DISPLAY)
        local nb = 0
        for i = c1 + 1, #Wd.created do if Wd.created[i]._kind == "Button" then nb = nb + 1 end end
        eq(#nav.ovs - o3, #DISPLAY_OVERLAYS, msg .. ", preview " .. v .. ": overlays")
        local fo = os.activePreview._factionOverlay
        check(fo and fo:IsShown() == (v ~= "noFaction"), msg .. ", preview " .. v .. ": the faction badge's overlay does not show with the badge")
        eq(nb, v == "noPips" and 2 or 3, msg .. ", preview " .. v .. ": hand-made buttons")
    end
    Wd.pvVariant = nil
    EllesmereUIDB = {}
end

-- 11c. Target, Focus & Hover: the overlays of every state on the header's preview
-- One entry per overlay, in build order: the part it sits on, its key, its state, its
-- level over the health bar's + 15, and what shows it (nil: always in its state; edge:
-- while the state's effect draws at the bar's edge; else while one of these parts shows).
local TFH_OVERLAYS = {
    { "healthWrapper", "targetEffect", "target", 0, "edge" }, { "healthWrapper", "hoverEffect", "hover", 0, "edge" },
    { "health", "targetColor", "target", 1 }, { "health", "focusColor", "focus", 1 },
    { "wash", "targetEffect", "target", 2, { "wash" } }, { "health", "targetTexture", "target", 3, { "texture" } },
    { "health", "focusTexture", "focus", 3, { "texture" } }, { "health", "hoverTexture", "hover", 3, { "texture", "wash" } },
    { "hash", "hashLine", "target", 4, { "hash" } }, { "arrowL", "targetArrows", "target", 5, { "arrowL" } },
    { "arrowR", "targetArrows", "target", 5, { "arrowR" } }, { "range", "rangeText", "target", 5, { "range" } },
    { "letter", "focusLetter", "focus", 5, { "letter" } },
}
-- Where each key lands: section, the label of the half holding its control.
local TFH_WANT = {
    targetEffect = { "TARGET", "Target Effect" }, targetArrows = { "TARGET", "Target Arrows" },
    targetColor = { "TARGET", "Target Color" }, targetTexture = { "TARGET", "Target Texture" },
    hashLine = { "TARGET", "Show Hash Line on Target" }, rangeText = { "TARGET", "Distance to Target Text" },
    focusColor = { "FOCUS", "Focus Color" }, focusTexture = { "FOCUS", "Focus Texture" },
    focusLetter = { "FOCUS", "Focus Letter" },
    hoverTexture = { "HOVER", "Hover Texture" }, hoverEffect = { "HOVER", "Hover Effect" },
}
-- The settings the overlays' parts follow, each with the value it takes beside its default.
local TFH_NAV_FLAGS = {
    { "targetOverlayTexture", "striped-v2" }, { "targetGlowHighlight", true }, { "targetGlowEllesmereUI", false },
    { "targetGlowBorderColor", true }, { "targetGlowBorderSize", true }, { "targetBorderSizeValue", 2 }, { "showBorder", false },
    { "customBorderEnabled", true }, { "showTargetArrows", true }, { "hashLineEnabled", true }, { "hashLinePercent", 0 },
    { "rangeTextEnabled", true }, { "focusOverlayTexture", "none" }, { "focusLetterEnabled", true }, { "hoverOverlayTexture", "striped-v2" },
    { "hoverGlowHighlight", false }, { "hoverGlowEllesmereUI", true }, { "hoverGlowBorderColor", true }, { "hoverGlowBorderSize", true },
    { "hoverBorderSizeValue", 2 },
}
-- Whether the state's effect draws at the bar's edge: its glow, or (on a plate drawing its own
-- border, not a stock style's) its Border Size with a size or its Border Color.
local function EdgeWant(m)
    local P = m == "target" and "Target" or "Hover"
    if nsData["Get" .. P .. "GlowEllesmereUI"]() then return true end
    if STYLE.active ~= "eui" then return false end
    local d = nsData.defaults
    local custom, border = STORE.customBorderEnabled, STORE.showBorder
    if custom == nil then custom = d.customBorderEnabled end
    if border == nil then border = d.showBorder end
    if not (custom or border) then return false end
    return (nsData["Get" .. P .. "GlowBorderSize"]() and nsData["Get" .. P .. "BorderSizeValue"]() ~= nil) or nsData["Get" .. P .. "GlowBorderColor"]() == true
end
-- The parts of a state preview by name, and its overlays (this build's) with their specs.
local function TFHParts(pv)
    return { healthWrapper = pv._healthWrapper, health = pv._health, cast = pv._cast, wash = pv._wash, texture = pv._texture,
        hash = pv._hashLine, arrowL = pv._arrows.left, arrowR = pv._arrows.right, range = pv._rangeText, letter = pv._focusLetter }
end
local function TFHShownWant(o, pv, parts)
    local spec = o.spec
    if spec[3] ~= pv._mode then return false end
    local rule = spec[5]
    if rule == nil then return true end
    if rule == "edge" then return EdgeWant(spec[3]) end
    for _, p in ipairs(rule) do if parts[p]:IsShown() then return true end end
    return false
end
local function TFHShown(list)
    local out = {}
    for _, o in ipairs(list) do if o.btn:IsShown() then out[#out + 1] = o.spec[2] .. "@" .. o.spec[1] end end
    table.sort(out)
    return table.concat(out, " ")
end
-- Every overlay against what shows it; returns the first that is wrong.
local function TFHSyncWrong(list, pv)
    local parts = TFHParts(pv)
    for _, o in ipairs(list) do
        local want = TFHShownWant(o, pv, parts)
        if o.btn:IsShown() ~= want then return o.spec[2] .. "@" .. o.spec[1] .. (want and " hidden" or " shown") end
    end
end
local function CheckNavTFH(Wd, tag, forever)
    local nav, os, Nav = Wd.nav, Wd.optState, Wd.env.Nav
    local msg = tag .. ": Target, Focus & Hover"
    EllesmereUIDB = {}
    H.SetState({})
    os.tfhMode = nil
    local o0, g0, f0 = #nav.ovs, nav.glowsMade, nav.frames
    local page = H.Build(Wd, TFH)
    if not check(page.ok and page.header, msg .. ": the page does not build: " .. tostring(page.result)) then return end
    local pv = os.tfhPreview
    local list = OvsSince(Wd, o0)
    -- the parts: the real preview's, by what they are
    local parts = TFHParts(pv)
    for name, want in pairs({ wash = "wash", texture = "texture", hash = "hash", range = "range", letter = "letter" }) do
        eq(Nm(parts[name]), want, msg .. ": the preview hands out as its " .. name .. " part")
    end
    eq(Nm(pv._glowFrame), "glow", msg .. ": the preview hands out as its glow frame")
    check(type(pv._fxEdge) == "function", msg .. ": the preview hands out no edge test")
    -- the glow frame outlines its reach round the bar at build (the band's rect), shown or not
    local gp = pv._glowFrame._points
    check(#gp == 2 and gp[1][1] == "TOPLEFT" and gp[1][2] == pv._healthWrapper and gp[1][4] == -6 and gp[1][5] == 6
        and gp[2][1] == "BOTTOMRIGHT" and gp[2][2] == pv._healthWrapper and gp[2][4] == 6 and gp[2][5] == -6,
        msg .. ": the glow frame does not outline its reach round the bar")
    -- the overlays: one per entry, in order, over this build's preview, the kit's, at their levels
    eq(#list, #TFH_OVERLAYS, msg .. ": overlays made by a build")
    eq(nav.glowsMade, g0 + 1, msg .. ": glows made by a build")
    local glow = nav.glowsMade
    local P = Nav.Page(TFH)
    local base = pv._health:GetFrameLevel() + 15
    local top = 0
    for i, o in ipairs(list) do
        local spec = TFH_OVERLAYS[i]
        o.spec = spec
        if spec then
            check(o.element == parts[spec[1]] and o.key == spec[2] and o.navigate == P.Go and o.page == TFH and o.tfh == pv
                and o.style and o.style.container == true and o.opts == nil and o.isText == (spec[1] == "range" or spec[1] == "letter"),
                msg .. ": overlay " .. i .. " is " .. tostring(o.key) .. " on " .. Nm(o.element) .. ", want " .. spec[2] .. " on " .. spec[1])
            eq(o.btn._level, base + spec[4], msg .. ": the level of " .. spec[2] .. " on " .. spec[1])
            top = math.max(top, o.btn._level, o.hlCont and o.hlCont._level or 0)
        end
    end
    for _, o in ipairs(list) do
        check(o.element ~= pv._cast and o.key ~= "focusCast", msg .. ": an overlay sits on the cast bar (" .. tostring(o.key) .. ")")
    end
    -- right after the build, before any repaint: the target's overlays whose part shows
    eq(TFHShown(list), "targetColor@health targetEffect@healthWrapper", msg .. ": the overlays that show after a build")
    -- the band takes the glow frame's rect; the hash line's hit is 8 wide, the line's height
    for _, o in ipairs(list) do
        if o.spec and o.spec[1] == "healthWrapper" then
            check(#o.btn._points == 1 and o.btn._points[1][1] == "ALL" and o.btn._points[1][2] == pv._glowFrame,
                msg .. ": the band of " .. o.key .. " is not the glow's reach")
        elseif o.spec and o.spec[1] == "hash" then
            local p = o.btn._points
            check(#p == 2 and p[1][1] == "TOP" and p[1][2] == pv._hashLine and p[1][3] == "TOP" and p[2][1] == "BOTTOM"
                and p[2][2] == pv._hashLine and p[2][3] == "BOTTOM" and o.btn._w == 8, msg .. ": the hash line's hit")
        end
    end
    -- the picker over every overlay
    local dd = page.dropdowns[1]
    check(dd and dd.frame._level == pv:GetFrameLevel() + 40 and dd.frame._level > top, msg .. ": the picker is not above every overlay")
    -- the hint: on a host of the header's (its size, at the plates' own scale), 17 over the
    -- header's bottom; the header 29 taller while it shows
    local hdr = page.header.frame
    local fs = Nav.Page(TFH).fs
    local host = fs and fs._parent
    eq(page.header.height, 144, msg .. ": the header's height with the hint")
    CheckHint(msg, fs, host, hdr, 17)
    check(host and host._parent == hdr and host._points[1] and host._points[1][1] == "ALL" and host._points[1][2] == hdr
        and math.abs(host:GetEffectiveScale() - UIParent:GetEffectiveScale()) < 1e-9, msg .. ": the hint's host")
    pv:Update()
    eq(Wd.updateH, 144, msg .. ": the header's height a repaint gives while the hint shows")

    -- what shows in each state: a few settings by hand (the EllesmereUI look: the target's glow
    -- on by default), then every combination against the parts
    local glowT = true
    local function Pick(mode) dd.set(mode); return TFHShown(list) end
    eq(Pick("target"), "targetColor@health" .. (glowT and " targetEffect@healthWrapper" or ""), msg .. ": the target's overlays, defaults")
    eq(Pick("focus"), "focusColor@health focusTexture@health", msg .. ": the focus' overlays, defaults")
    eq(Pick("hover"), "hoverTexture@health", msg .. ": the hovered plate's overlays, defaults (the flat wash)")
    H.SetState({ targetOverlayTexture = "striped-v2", targetGlowHighlight = true, showTargetArrows = true, hashLineEnabled = true,
        rangeTextEnabled = true, focusLetterEnabled = true, focusOverlayTexture = "none", hoverGlowEllesmereUI = true, hoverGlowHighlight = false })
    eq(Pick("target"), "hashLine@hash rangeText@range targetArrows@arrowL targetArrows@arrowR targetColor@health "
        .. (glowT and "targetEffect@healthWrapper " or "") .. "targetEffect@wash targetTexture@health", msg .. ": the target's overlays, every part")
    eq(Pick("focus"), "focusColor@health focusLetter@letter", msg .. ": the focus' overlays, the letter, no texture")
    eq(Pick("hover"), "hoverEffect@healthWrapper", msg .. ": the hovered plate's overlays, the glow alone")
    local n = 0
    local bad, first = 0, nil
    local o1, f1 = #nav.ovs, nav.frames
    -- (this plate was built under the EllesmereUI look, which it keeps; each stock look is
    -- read on a plate built under it, at the end)
    Combos(TFH_NAV_FLAGS, 3, function(state)
        H.SetState(state)
        for _, m in ipairs({ "target", "focus", "hover" }) do
            n = n + 1
            dd.set(m)
            local wrong = TFHSyncWrong(list, pv)
            if wrong then
                bad = bad + 1
                first = first or (StateText(state, STYLE) .. " " .. m .. ": " .. wrong)
            end
        end
    end)
    check(bad == 0, msg .. ": overlays shown wrongly in " .. bad .. " of " .. n .. " states; the first, " .. tostring(first))
    check(n > 4000, msg .. ": the overlays were read in " .. n .. " states only")
    check(#nav.ovs == o1 and nav.frames == f1, msg .. ": state picks and repaints made overlays")
    H.SetState({})
    -- a text's overlay follows its size
    H.SetState({ focusLetterEnabled = true, focusLetterSize = 30 })
    dd.set("focus")
    local letter
    for _, o in ipairs(list) do if o.spec and o.spec[1] == "letter" then letter = o end end
    check(letter and letter.btn._h == 34 and letter.btn._w == 10, msg .. ": the Focus Letter's overlay does not follow its size")

    -- writes through the page's own controls: what shows follows, nothing is made
    H.SetState({ showTargetArrows = true, hashLineEnabled = true, rangeTextEnabled = true, targetOverlayTexture = "striped-v2",
        focusLetterEnabled = true })
    dd.set("target")
    local function Ctl(label) local r, side = RowOf(page, label); return r and (side == "left" and r.l or r.r) end
    local function Check(label, what)
        local wrong = TFHSyncWrong(list, pv)
        check(not wrong, msg .. ": after " .. what .. ", " .. tostring(wrong))
    end
    local function Shows(key, part) for _, o in ipairs(list) do if o.key == key and o.spec[1] == part then return o.btn:IsShown() end end end
    check(Shows("targetArrows", "arrowL") and Shows("hashLine", "hash") and Shows("rangeText", "range") and Shows("targetTexture", "health"),
        msg .. ": the target's parts before the writes")
    Ctl("Target Arrows").setValue("none")
    check(not Shows("targetArrows", "arrowL") and not Shows("targetArrows", "arrowR"), msg .. ": Target Arrows None leaves their overlays")
    Ctl("Target Arrows").setValue("double")
    check(Shows("targetArrows", "arrowL") and Shows("targetArrows", "arrowR"), msg .. ": Target Arrows back does not show their overlays")
    Ctl("Show Hash Line on Target").setValue(false)
    check(not Shows("hashLine", "hash"), msg .. ": the hash line off leaves its overlay")
    Ctl("Target Texture").setValue("none")
    check(not Shows("targetTexture", "health"), msg .. ": Target Texture None leaves its overlay")
    Ctl("Distance to Target Text").setValue(false)
    check(not Shows("rangeText", "range"), msg .. ": the distance text off leaves its overlay")
    dd.set("focus")
    Ctl("Focus Letter").setValue("none")
    check(not Shows("focusLetter", "letter"), msg .. ": Focus Letter None leaves its overlay")
    Ctl("Focus Letter").setValue("TOPLEFT")
    check(Shows("focusLetter", "letter"), msg .. ": a Focus Letter spot does not show its overlay")
    Ctl("Focus Letter").setValue("none")
    Ctl("Focus Texture").setValue("none")
    check(not Shows("focusTexture", "health") and Shows("focusColor", "health"), msg .. ": Focus Texture None leaves its overlay")
    dd.set("hover")
    local hoverChecks
    for _, ck in ipairs(page.checks) do if ck.host and ck.host.text == "Hover Effect" then hoverChecks = ck end end
    if check(hoverChecks, msg .. ": no Hover Effect checklist") then
        hoverChecks.set("highlight", false)
        check(not Shows("hoverTexture", "health"), msg .. ": the hover Highlight off leaves the wash's overlay")
        hoverChecks.set("ellesmereui", true)
        check(Shows("hoverEffect", "healthWrapper"), msg .. ": the hover glow on shows no band")
    end
    Check("", "the writes")
    check(#nav.ovs == o1 and nav.frames == f1, msg .. ": writes made overlays")

    -- every overlay clicked in its state: the half holding its control, under its section (the
    -- plate grown since the header was built: the hint's base follows it)
    H.SetState({ targetColorEnabled = true, targetOverlayTexture = "striped-v2", targetGlowHighlight = true, showTargetArrows = true,
        hashLineEnabled = true, rangeTextEnabled = true, focusLetterEnabled = true, hoverGlowEllesmereUI = true, targetGlowBorderColor = true })
    pv._standInH = 80
    local clicked = {}
    for _, m in ipairs({ "target", "focus", "hover" }) do
        dd.set(m)
        for _, o in ipairs(list) do
            if o.btn:IsShown() then
                CheckPageLanding(msg .. ", " .. m .. ", a click on " .. o.key .. "@" .. o.spec[1],
                    H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end), page, TFH_WANT[o.key], glow)
                clicked[o.key .. "@" .. o.spec[1]] = true
            end
        end
    end
    local nClicked = 0
    for _ in pairs(clicked) do nClicked = nClicked + 1 end
    eq(nClicked, #TFH_OVERLAYS, msg .. ": overlays clicked (all of them)")
    -- the clicks dismissed the hint: the header at the plate and its pads, a repaint counts no hint
    local d = nav.dismiss[#nav.dismiss - nClicked + 1]
    check(d and d.hint == fs and d.base == 135 and d.y == 17 and d.hintH == 29, msg .. ": the first click does not dismiss this page's hint with the plate's height")
    H.RunFades(Wd)
    check(not fs:IsShown() and Wd.silentH == 135, msg .. ": the hint's fade")
    pv._standInH = nil
    pv:Update()
    eq(Wd.updateH, 115, msg .. ": the header's height a repaint gives after the dismissal")
    -- the page shown again, the panel shown: repainted, the hint's rule, nothing made
    Wd.silentH = nil
    Wd.cfg.onPageCacheRestore(TFH)
    check(Wd.silentH == 115 and not fs:IsShown(), msg .. ": a cache restore after the dismissal")
    EllesmereUIDB.previewHintDismissed = nil
    Wd.cfg.onPageCacheRestore(TFH)
    check(Wd.silentH == 144 and fs:IsShown(), msg .. ": a cache restore while the hint shows")
    -- a setting changed behind the cached page: the restore's repaint takes the overlays to it
    dd.set("target")
    H.SetState({})
    pv:Update()
    H.SetState({ showTargetArrows = true, hashLineEnabled = true })
    Wd.cfg.onPageCacheRestore(TFH)
    check(Shows("targetArrows", "arrowL") and Shows("hashLine", "hash") and not TFHSyncWrong(list, pv) and #nav.ovs == o1 and nav.frames == f1,
        msg .. ": a cache restore does not take the overlays to what the plate draws, or makes overlays")
    local u0 = pv._updates
    Wd.onShow[1]()
    check(pv._updates == u0 + 1 and #nav.ovs == o1 and nav.frames == f1, msg .. ": the panel's show does not repaint the preview, or makes overlays")
    check(not TFHSyncWrong(list, pv), msg .. ": the overlays after the panel's show")

    -- the search pre-build: no overlay, glow or sync; a click still lands on the live rows
    local liveRow = RowOf(page, "Target Arrows")
    local sync, g1 = pv._navSync, nav.glowsMade
    local pre = H.Build(Wd, TFH, true)
    check(pre.ok and #nav.ovs == o1 and nav.frames == f1 and nav.glowsMade == g1 and pv._navSync == sync and os.tfhPreview == pv,
        msg .. ": the search pre-build makes overlays, a glow or a sync")
    dd.set("target")
    H.SetState({ showTargetArrows = true })
    pv:Update()
    for _, o in ipairs(list) do
        if o.key == "targetArrows" and o.btn:IsShown() then
            local r = H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end)
            check(r.glows[1] and r.glows[1].target == liveRow.row._rightRegion, msg .. ": a click after the search pre-build does not land on the live page's row")
            break
        end
    end

    -- a rebuild: one new set on the new preview; the old one keeps its set and is not repainted
    local o2 = #nav.ovs
    local page2 = H.Build(Wd, TFH)
    local pv2 = os.tfhPreview
    local list2 = OvsSince(Wd, o2)
    local onNew = 0
    for _, o in ipairs(list2) do if o.tfh == pv2 and Under(o.element, pv2) then onNew = onNew + 1 end end
    check(page2.ok and pv2 ~= pv and #list2 == #TFH_OVERLAYS and onNew == #list2 and pv2._navSync ~= sync and pv._navSync == sync,
        msg .. ": a rebuild makes " .. #list2 .. " overlays (" .. onNew .. " on the new preview)")
    u0 = pv._updates
    Wd.env.UpdatePreview()
    eq(pv._updates, u0, msg .. ": repaints of the old preview after a rebuild")
    -- each stock look on a plate built under it: the target's overlays by default (the WoW
    -- Forever look draws no target glow), then every setting of up to two flags at once
    for _, style in ipairs(H.STYLES) do
        H.SetState({}, style)
        os.tfhMode = nil
        local o6 = #nav.ovs
        local pg = H.Build(Wd, TFH)
        local pvS, listS, ddS = os.tfhPreview, OvsSince(Wd, o6), pg.dropdowns[1]
        for i, o in ipairs(listS) do o.spec = TFH_OVERLAYS[i] end
        local tagS = msg .. ", " .. StateText({}, style)
        if check(#listS == #TFH_OVERLAYS and ddS and pvS ~= pv, tagS .. ": the build does not make its own plate and overlays") then
            ddS.set("target")
            eq(TFHShown(listS), "targetColor@health" .. (style.forever and "" or " targetEffect@healthWrapper"), tagS .. ": the target's overlays, defaults")
            local nS, badS, firstS = 0, 0, nil
            Combos(TFH_NAV_FLAGS, 2, function(state)
                H.SetState(state, style)
                for _, m in ipairs({ "target", "focus", "hover" }) do
                    nS = nS + 1
                    ddS.set(m)
                    local wrong = TFHSyncWrong(listS, pvS)
                    if wrong then
                        badS = badS + 1
                        firstS = firstS or (StateText(state, style) .. " " .. m .. ": " .. wrong)
                    end
                end
            end)
            check(badS == 0, tagS .. ": overlays shown wrongly in " .. badS .. " of " .. nS .. " states; the first, " .. tostring(firstS))
            check(nS > 600, tagS .. ": the overlays were read in " .. nS .. " states only")
            eq(#nav.ovs, o6 + #TFH_OVERLAYS, tagS .. ": overlays made by its build and the state picks")
        end
    end
    -- a build in a state whose effect draws no glow (the hovered plate, by default): the glow
    -- frame still outlines its reach round the bar, so the band has its rect
    os.tfhMode = "hover"
    H.SetState({})
    local o5 = #nav.ovs
    H.Build(Wd, TFH)
    local pv3 = os.tfhPreview
    local gp3 = pv3._glowFrame._points
    check(pv3._mode == "hover" and not pv3._glowFrame:IsShown() and #gp3 == 2 and gp3[1][1] == "TOPLEFT" and gp3[1][2] == pv3._healthWrapper
        and gp3[1][4] == -6 and gp3[1][5] == 6 and gp3[2][1] == "BOTTOMRIGHT" and gp3[2][2] == pv3._healthWrapper and gp3[2][4] == 6 and gp3[2][5] == -6,
        msg .. ": the glow frame has no rect while its glow is off")
    local bands = 0
    for _, o in ipairs(OvsSince(Wd, o5)) do
        if o.element == pv3._healthWrapper and #o.btn._points == 1 and o.btn._points[1][2] == pv3._glowFrame then bands = bands + 1 end
    end
    eq(bands, 2, msg .. ": bands on the glow frame of a build whose glow is off")
    os.tfhMode = nil
    -- the Enemies preview carries none of this page's parts or sync
    H.Build(Wd, DISPLAY)
    local ep = os.activePreview
    check(ep._glowFrame == nil and ep._navSync == nil and ep._fxEdge == nil and ep._wash == nil and ep._hashLine == nil,
        msg .. ": the Enemies preview carries this page's navigation")
    H.SetState({})
    EllesmereUIDB = {}
end

-- 11d. Friendly Plates: the overlays made once with the two samples
-- In each sample, in order: the part, its key, a text overlay or not, its level over the sample's.
local FRIENDLY_OVERLAYS = {
    player = { { "health", "playerBar", false, 10 }, { "hpText", "healthPercent", true, 16 }, { "name", "playerName", true, 15 },
        { "sub", "playerGuild", true, 16 } },
    npc = { { "health", "npcBar", false, 10 }, { "hpText", "healthPercent", true, 16 }, { "name", "npcName", true, 15 },
        { "sub", "npcTitle", true, 16 }, { "raid", "npcMarker", false, 15 } },
}
-- Where a key lands: section, the label of the half holding its control (a name: the name
-- size of the form it shows in; the NPC's on the health bar plate takes the bar plate's).
-- (the bar's two rows are on the page only as built under Nameplate: on a page built under
-- another style their keys land nowhere)
local function FriendlyWant(key, nameOnly, plateBuild)
    if key == "playerBar" then return plateBuild and { "FRIENDLY PLAYERS", "Health Bar Width" } or nil end
    if key == "healthPercent" then return plateBuild and { "FRIENDLY PLAYERS", "Show Health Percent" } or nil end
    if key == "playerGuild" then return { "FRIENDLY PLAYERS", "Subtitle Text" } end
    if key == "npcBar" then return { "FRIENDLY NPCS", "Show Friendly NPC Nameplates" } end
    if key == "npcTitle" then return { "FRIENDLY NPCS", "Friendly NPC Title Size" } end
    if key == "npcMarker" then return { "FRIENDLY NPCS", "Show Raid Marker" } end
    if key == "playerName" then return { "FRIENDLY PLAYERS", "Friendly Name Size" } end
    if key == "npcName" then return nameOnly and { "FRIENDLY NPCS", "Friendly NPC Name Size" } or { "FRIENDLY PLAYERS", "Friendly Name Size" } end
end
-- Which overlays a sample shows: the bar's with the health bar plate, the percent text while
-- shown, the guild line with the bar plate's guild subtitle, the NPC title and marker in Name Only.
local function FriendlyActiveWant(who, part, marked)
    local d = nsData.defaults
    local function V(k) local v = STORE[k]; if v == nil then v = d[k] end; return v end
    local nameOnly = V("friendlyNameOnly") ~= false
    if part == "name" then return true end
    if part == "health" then return not nameOnly end
    if part == "hpText" then return not nameOnly and not V("friendlyHideHealthText") end
    if who == "player" and part == "sub" then
        local m = V("friendlyBelowName") or "none"
        return not nameOnly and (m == "guild" or m == "both")
    end
    if part == "sub" then return nameOnly and V("showNPCTitles") ~= false end
    if part == "raid" then
        return marked == true and nameOnly and V("showNPCRaidMarker") ~= false and (STORE.raidMarkerPos or d.raidMarkerPos) ~= "none"
    end
end
local FRIENDLY_NAV_FLAGS = {
    { "friendlyNameOnly", false }, { "friendlyBelowName", "title", "guild", "both" }, { "friendlyHideHealthText", true },
    { "showNPCTitles", false }, { "showNPCRaidMarker", false }, { "raidMarkerPos", "none" }, { "showFriendlyPlayers", false },
    { "showFriendlyNPCs", true }, { "friendlyShowLevel", true },
}
local function CheckNavFriendly(Wd, tag)
    local nav, Nav = Wd.nav, Wd.env.Nav
    local msg = tag .. ": Friendly Plates"
    EllesmereUIDB = {}
    H.SetState({})
    local o0, f0, g0 = #nav.ovs, nav.frames, nav.glowsMade
    local page = H.Build(Wd, FRIENDLY)
    if not check(page.ok and page.header, msg .. ": the page does not build: " .. tostring(page.result)) then return end
    local hdr = page.header.frame
    check(#nav.ovs == o0 and nav.frames == f0, msg .. ": a header build after the first makes overlays")
    eq(nav.glowsMade, g0 + 1, msg .. ": glows made by a page build")
    local glow = nav.glowsMade
    local P = Nav.Page(FRIENDLY)
    -- the samples, and the overlays made once with them, at the first header build
    local S = {}
    for _, f in ipairs(Wd.rootless) do
        local name = rawget(f, "name")
        local text = name and name._text or ""
        if f._parent == hdr and text:find("Friendly Player", 1, true) then S.player = f elseif f._parent == hdr and text == "Friendly NPC" then S.npc = f end
    end
    if not check(S.player and S.npc, msg .. ": the header does not hold the two samples") then return end
    local recs = {}
    for _, o in ipairs(nav.ovs) do if o.page == FRIENDLY then recs[#recs + 1] = o end end
    -- (made over the samples' parts)
    for _, o in ipairs(recs) do
        check(Under(o.element, S.player) or Under(o.element, S.npc), msg .. ": an overlay made by a page build over " .. Nm(o.element))
    end
    eq(#recs, 9, msg .. ": overlays made for the samples over the whole run (once, at the first header build)")
    local all = {}
    local i = 0
    for _, who in ipairs({ "player", "npc" }) do
        local s = S[who]
        for _, spec in ipairs(FRIENDLY_OVERLAYS[who]) do
            i = i + 1
            local o = recs[i]
            if o then
                o.who, o.spec = who, spec
                check(o.element == rawget(s, spec[1]) and o.key == spec[2] and (o.isText == true) == spec[3] and o.navigate == P.Go
                    and o.style and o.style.container == true and o.opts == nil and o.level == nil,
                    msg .. ": overlay " .. i .. " is " .. tostring(o.key) .. ", want " .. spec[2] .. " on the " .. who .. "'s " .. spec[1])
                -- over the sample, at its level over the sample's, the hover border one above
                check(Under(o.btn, s) and o.btn._level == s._level + spec[4] and o.hlCont and o.hlCont._level == s._level + spec[4] + 1,
                    msg .. ": the level of " .. spec[2] .. " on the " .. who .. "'s " .. spec[1] .. " (" .. tostring(o.btn._level) .. " over " .. tostring(s._level) .. ")")
                all[#all + 1] = o
            end
        end
    end
    -- the hint: on the header, 17 over its bottom; 29 px more
    local fs = P.fs
    CheckHint(msg, fs, hdr, hdr, 17)
    local shownH = page.header.height
    EllesmereUIDB = { previewHintDismissed = true }
    local pd = H.Build(Wd, FRIENDLY)
    check(pd.header and pd.header.height == shownH - 29 and not fs:IsShown(), msg .. ": the header with the hint is not 29 px taller than without it ("
        .. tostring(shownH) .. ", " .. tostring(pd.header and pd.header.height) .. ")")
    EllesmereUIDB = {}
    page = H.Build(Wd, FRIENDLY)
    hdr = page.header.frame
    check(#nav.ovs == o0 + 0 and nav.frames == f0 and fs:IsShown() and fs._parent == hdr, msg .. ": a header build again makes overlays, or leaves the hint behind")
    glow = nav.glowsMade

    -- what shows, in every combination of the settings the samples follow; a click on each in
    -- a sample of them
    local n, bad, first = 0, 0, nil
    local os = Wd.optState
    check(os.showNPCMarkerPreview == false, msg .. ": the marker's eye is not off at first (" .. tostring(os.showNPCMarkerPreview) .. ")")
    Combos(FRIENDLY_NAV_FLAGS, 99, function(state)
      -- (each setting with the marker's eye off, then on)
      for _, marked in ipairs({ false, true }) do
        n = n + 1
        H.SetState(state)
        os.showNPCMarkerPreview = marked
        nsData.NPO_FriendlyPreviewUpdate()
        local nameOnly = (STORE.friendlyNameOnly == nil and nsData.defaults.friendlyNameOnly or STORE.friendlyNameOnly) ~= false
        for _, o in ipairs(all) do
            local want = FriendlyActiveWant(o.who, o.spec[1], marked)
            local got = o.btn:IsVisible()
            local text = o.spec[3] and o.element._text
            if got ~= want or (got and text and (o.btn._w ~= 6 * #text + 4 or o.btn._h ~= o.element:GetStringHeight() + 4)) then
                bad = bad + 1
                first = first or (StateText(state, STYLE) .. ": " .. o.key .. " on the " .. o.who .. "'s " .. o.spec[1] .. (want and " is not" or " is") .. " active, or not its text's size")
            end
            if got and want and n % 7 == 1 then
                -- (this page was built under Name Only: a style changed behind it leaves the
                -- bar's keys with no row to land on)
                local what = msg .. ", " .. StateText(state, STYLE) .. ", a click on " .. o.key .. " (the " .. o.who .. "'s " .. o.spec[1] .. ")"
                local r = H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end)
                local land = FriendlyWant(o.key, nameOnly, false)
                if land then CheckPageLanding(what, r, page, land, glow) else CheckLanding(what, r, nil) end
            end
        end
      end
    end)
    os.showNPCMarkerPreview = true
    check(bad == 0, msg .. ": overlays active wrongly in " .. bad .. " of " .. n .. " settings; the first, " .. tostring(first))
    check(n >= 2000, msg .. ": the samples were read in " .. n .. " settings only")
    check(#nav.ovs == o0 and nav.frames == f0, msg .. ": repaints made overlays")
    -- the clicks dismissed the hint, with the samples' height as the base; its fade takes the
    -- header back to it
    local d
    for k = #nav.dismiss, 1, -1 do if nav.dismiss[k].hint == fs and not nav.dismiss[k].flag then d = nav.dismiss[k] end end
    check(d and d.hintH == 29 and d.y == 17 and d.base > 0, msg .. ": no click dismissed this page's hint with its spot")
    H.RunFades(Wd)
    check(not fs:IsShown() and EllesmereUIDB.previewHintDismissed == true and Wd.silentH == d.base, msg .. ": the hint's fade")
    -- the samples' height is the base the kit holds: the restore sets it, plus the hint while it shows
    H.SetState({ friendlyNameOnly = false, friendlyBelowName = "both" })
    nsData.NPO_FriendlyPreviewUpdate()
    local tall = Wd.silentH
    Wd.cfg.onPageCacheRestore(FRIENDLY)
    eq(Wd.silentH, tall, msg .. ": a cache restore after the dismissal")
    EllesmereUIDB.previewHintDismissed = nil
    Wd.cfg.onPageCacheRestore(FRIENDLY)
    check(Wd.silentH == tall + 29 and fs:IsShown(), msg .. ": a cache restore while the hint shows")
    -- the panel's show: repainted, nothing made
    Wd.onShow[2]()
    check(#nav.ovs == o0 and nav.frames == f0, msg .. ": the panel's show makes overlays")
    -- writes through the page's own controls: the overlays follow, nothing is made
    -- (the marker's eye on from here: the writes below turn the marker's overlay off and on)
    local function Active()
        for _, o in ipairs(all) do
            if o.btn:IsVisible() ~= FriendlyActiveWant(o.who, o.spec[1], os.showNPCMarkerPreview) then return o.key .. " on the " .. o.who .. "'s " .. o.spec[1] end
        end
    end
    H.SetState({})
    nsData.NPO_FriendlyPreviewUpdate()
    -- (a pick of the style builds the page again: the page is built anew after each, as the
    -- panel does, and every click then lands on that build's rows)
    local glowNow = glow
    for _, w in ipairs({ { "Friendly Nameplate Style", "plate", true }, { "Show Health Percent", "none" }, { "Subtitle Text|check:guild", true },
        { "Show Health Percent", "left" }, { "Friendly Nameplate Style", "nameonly", true }, { "Show NPC Titles", false },
        { "Show Raid Marker", false }, { "Show NPC Titles", true } }) do
        local c = H.Controls(page)[(w[1]:find("NPC", 1, true) or w[1] == "Show Raid Marker") and ("FRIENDLY NPCS|" .. w[1]) or ("FRIENDLY PLAYERS|" .. w[1])]
        if check(c and c.set, msg .. ": no control " .. w[1]) then
            H.ResetLog()
            c.set(w[2])
            if w[3] then
                check(LOG.rebuild >= 1, msg .. ": " .. w[1] .. " set to " .. tostring(w[2]) .. " does not build the page again")
                page = H.Build(Wd, FRIENDLY)
                glowNow = nav.glowsMade
            end
            local wrong = Active()
            check(not wrong, msg .. ": after " .. w[1] .. " set to " .. tostring(w[2]) .. ", " .. tostring(wrong) .. " is active wrongly")
            -- every active overlay lands on a row of the page as it is built now
            local plateBuild = STORE.friendlyNameOnly == false
            for _, o in ipairs(all) do
                if o.btn:IsVisible() then
                    local what = msg .. ", after " .. w[1] .. " set to " .. tostring(w[2]) .. ", a click on " .. o.key .. " (the " .. o.who .. "'s " .. o.spec[1] .. ")"
                    local land = FriendlyWant(o.key, not plateBuild, plateBuild)
                    if check(land ~= nil, what .. ": lands nowhere on a page built for the style in use") then
                        CheckPageLanding(what, H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end), page, land, glowNow)
                    end
                end
            end
        end
    end
    check(#nav.ovs == o0 and nav.frames == f0, msg .. ": writes make overlays")
    -- built under Nameplate, with every part of both samples shown: each key's row
    H.SetState({ friendlyNameOnly = false, friendlyBelowName = "both", showFriendlyNPCs = true })
    page = H.Build(Wd, FRIENDLY)
    glowNow = nav.glowsMade
    local landed = {}
    for _, o in ipairs(all) do
        if o.btn:IsVisible() then
            CheckPageLanding(msg .. ", built under Nameplate, a click on " .. o.key .. " (the " .. o.who .. "'s " .. o.spec[1] .. ")",
                H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end), page, FriendlyWant(o.key, false, true), glowNow)
            landed[o.key] = true
        end
    end
    check(landed.playerBar and landed.healthPercent and landed.playerName and landed.playerGuild and landed.npcBar and landed.npcName,
        msg .. ": built under Nameplate, a part of the samples has no overlay to click")
    -- a setting changed behind the cached page: the restore's repaint takes the overlays to it
    H.SetState({ friendlyNameOnly = false, friendlyBelowName = "both" })
    Wd.cfg.onPageCacheRestore(FRIENDLY)
    check(not Active(), msg .. ": a cache restore does not take the overlays to what the samples draw")

    -- the search pre-build: no overlay or glow; a click still lands on the live rows
    -- (the page is the build under Nameplate from above)
    H.SetState({ friendlyNameOnly = false, friendlyBelowName = "both", showFriendlyNPCs = true })
    nsData.NPO_FriendlyPreviewUpdate()
    local liveRow = RowOf(page, "Health Bar Width")
    local g1 = nav.glowsMade
    local pre = H.Build(Wd, FRIENDLY, true)
    check(pre.ok and #nav.ovs == o0 and nav.frames == f0 and nav.glowsMade == g1, msg .. ": the search pre-build makes overlays or a glow")
    for _, o in ipairs(all) do
        if o.key == "playerBar" then
            local r = H.Press(Wd, function() o.btn._scripts.OnMouseDown(o.btn) end)
            check(r.glows[1] and r.glows[1].target == liveRow.row._leftRegion, msg .. ": a click after the search pre-build does not land on the live page's row")
        end
    end
    -- a rebuild puts the overlays' levels back over the samples (a new parent sets a level anew)
    for _, o in ipairs(all) do o.btn._level, o.hlCont._level = 1, 1 end
    local page3 = H.Build(Wd, FRIENDLY)
    local wrong = 0
    for _, o in ipairs(all) do
        local s = S[o.who]
        if o.btn._level ~= s._level + o.spec[4] or o.hlCont._level ~= s._level + o.spec[4] + 1 then wrong = wrong + 1 end
    end
    check(page3.ok and wrong == 0 and #nav.ovs == o0 and nav.frames == f0, msg .. ": a rebuild leaves " .. wrong .. " overlays below their sample, or makes overlays")
    os.showNPCMarkerPreview = false
    H.SetState({})
    EllesmereUIDB = {}
end

-- 11d-2. The friendly samples: the player sample's name, and the eye beside Show Raid
-- Marker that puts a raid marker on the sample NPC
local function CheckFriendlySamples(Wd, tag, forever)
    local msg = tag .. ": Friendly Plates"
    local os = Wd.optState
    EllesmereUIDB = {}
    H.SetState({})
    os.showNPCMarkerPreview = false
    local c0 = #Wd.created
    local page = H.Build(Wd, FRIENDLY)
    if not check(page.ok and page.header, msg .. ": the page does not build: " .. tostring(page.result)) then return end
    local hdr = page.header.frame
    local S = {}
    for _, f in ipairs(Wd.rootless) do
        local name = rawget(f, "name")
        if f._parent == hdr and name and rawget(f, "raid") then
            if name._text == "Friendly NPC" then S.npc = f else S.player = f end
        end
    end
    if not check(S.player and S.npc, msg .. ": the header does not hold the two samples") then return end
    local function Name(state, unitName, pvpName, secret)
        H.SetState(state or {})
        Wd.unitName, Wd.pvpName, Wd.secret = unitName, pvpName, secret
        nsData.NPO_FriendlyPreviewUpdate()
        Wd.unitName, Wd.pvpName, Wd.secret = nil, nil, nil
        return S.player.name._text
    end
    -- the name: Friendly Player, never your character's
    eq(Name(), "Friendly Player", msg .. ": the player sample's name")
    eq(Name({ friendlyNameOnly = false }), "Friendly Player", msg .. ": the player sample's name on the health bar plate")
    -- a set title after it where the Subtitle Text shows titles, in both styles: never your
    -- own title, whatever the game says of yours (a title before the name, none, a secret one)
    for _, mode in ipairs({ "title", "both" }) do
        for _, nameOnly in ipairs({ false, true }) do
            local got = Name({ friendlyNameOnly = nameOnly, friendlyBelowName = mode })
            eq((got:gsub("\n.*", "")), "Friendly Player The Immortal",
                msg .. ": the sample's name with the set title (" .. mode .. (nameOnly and ", Name Only)" or ", health bar plate)"))
        end
    end
    eq(Name({ friendlyBelowName = "title" }, nil, "Private Ellesmere"), "Friendly Player The Immortal", msg .. ": the sample's title while yours stands before your name")
    eq(Name({ friendlyBelowName = "title" }, nil, "Ellesmere"), "Friendly Player The Immortal", msg .. ": the sample's title while you wear none")
    eq(Name({ friendlyBelowName = "title" }, nil, false), "Friendly Player The Immortal", msg .. ": the sample's title while the game hands out no titled name")
    eq(Name({ friendlyBelowName = "title" }, nil, "Ellesmere the Patient", "Ellesmere the Patient"), "Friendly Player The Immortal",
        msg .. ": the sample's title while your titled name is secret")
    eq(Name({ friendlyBelowName = "title" }, {}), "Friendly Player The Immortal", msg .. ": the sample's title while the game hands out no name of yours")
    eq(Name({ friendlyBelowName = "none" }), "Friendly Player", msg .. ": the sample's name while the Subtitle Text shows nothing")
    -- a set guild where the Subtitle Text shows guilds, never your own (the game's stand-in
    -- guild here is Knights of Ellesmere): a second line of the name in Name Only, a line of
    -- its own on the health bar plate
    eq(Name({ friendlyBelowName = "guild" }), "Friendly Player\n|cffffffff<Guild>|r", msg .. ": the sample's name with the guild line, no title (Name Only)")
    eq(Name({ friendlyBelowName = "both" }), "Friendly Player The Immortal\n|cffffffff<Guild>|r", msg .. ": the sample's name with title and guild (Name Only)")
    eq(Name({ friendlyBelowName = "guild", friendlyBelowNameGuildBrackets = false }), "Friendly Player\n|cffffffffGuild|r",
        msg .. ": the sample's guild line without its brackets (Name Only)")
    for _, mode in ipairs({ "guild", "both" }) do
        Name({ friendlyNameOnly = false, friendlyBelowName = mode })
        eq(S.player.sub._text, "<Guild>", msg .. ": the sample's guild line on the health bar plate (" .. mode .. ")")
    end
    Name({ friendlyNameOnly = false, friendlyBelowName = "title" })
    eq(S.player.sub._text, "", msg .. ": the health bar sample's second line while the Subtitle Text shows titles alone")
    -- the Name Format: a retail name is one word, which only a Character Count cuts; a WoW
    -- Forever name has a surname, as the sample's two words
    for _, c in ipairs({ { "first", "Friendly" }, { "last", "Player" }, { "abbr", "F. Player" } }) do
        eq(Name({ friendlyNameFormat = c[1] }), forever and c[2] or "Friendly Player", msg .. ": the sample's name under the Name Format " .. c[1])
    end
    eq(Name({ friendlyNameFormat = 8 }), "Friendly", msg .. ": the sample's name under a Character Count of 8")
    eq(Name({ friendlyNameFormat = 10 }), "Friendly P", msg .. ": the sample's name under a Character Count of 10")
    eq(Name({ friendlyNameFormat = 40 }), "Friendly Player", msg .. ": the sample's name under a Character Count longer than it")
    eq(Name({ friendlyNameFormat = "last", friendlyBelowName = "title" }), forever and "Player The Immortal" or "Friendly Player The Immortal",
        msg .. ": the sample's short name with the set title")
    eq(Name({ friendlyNameFormat = 8, friendlyBelowName = "title" }), "Friendly The Immortal", msg .. ": the title stays whole under a Character Count")
    -- the brackets and the level around it, as on a live plate
    eq(Name({ friendlyGroupBrackets = true }), "|cffaaaaff[|rFriendly Player|cffaaaaff]|r", msg .. ": the sample's name in the group brackets")
    eq(Name({ friendlyShowLevel = true }), "80 | Friendly Player", msg .. ": the sample's name with the level")
    eq(Name({ friendlyShowLevel = true, friendlyGroupBrackets = true, friendlyBelowName = "title" }),
        "80 | |cffaaaaff[|rFriendly Player The Immortal|cffaaaaff]|r", msg .. ": the sample's name with level, brackets and title")
    -- Name Color on the Name Only sample: the class colour, or the Custom colour (white until
    -- one is picked); a pick outranks the older key
    local function NameRGB(state)
        H.SetState(state)
        nsData.NPO_FriendlyPreviewUpdate()
        local c = S.player.name._color or {}
        return tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3])
    end
    eq(NameRGB({}), "0.25,0.78,0.92", msg .. ": the Name Only sample's name colour, nothing saved (class colored)")
    eq(NameRGB({ classColorFriendly = false }), "1,1,1", msg .. ": the Name Only sample's name colour with the older key off (white)")
    eq(NameRGB({ friendlyNameColorMode = "custom" }), "1,1,1", msg .. ": the Name Only sample's name colour, Custom with no colour picked")
    eq(NameRGB({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }), "0.2,0.4,0.6",
        msg .. ": the Name Only sample's name colour, Custom")
    eq(NameRGB({ friendlyNameColorMode = "class", classColorFriendly = false, friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }), "0.25,0.78,0.92",
        msg .. ": the Name Only sample's name colour, Class picked over the older key")
    eq(NameRGB({ friendlyNameClassColor = true, classColorFriendly = false }), "1,1,1",
        msg .. ": the Name Only sample reads the health bar plates' older key")
    -- the health percent on the player sample's bar: on the side Show Health Percent saves (the
    -- runtime's own placer, one point), no text while it is off
    local function HpAt(state)
        state.friendlyNameOnly = false
        H.SetState(state)
        nsData.NPO_FriendlyPreviewUpdate()
        local fs = S.player.hpText
        local pt = fs._points[#fs._points]
        return tostring(fs._text) .. " | " .. #fs._points .. " point: " .. tostring(pt and pt[1]) .. "," .. tostring(pt and pt[2] == S.player.health)
            .. "," .. tostring(pt and pt[3]) .. "," .. tostring(pt and pt[4]) .. "," .. tostring(pt and pt[5])
    end
    eq(HpAt({}), "100% | 1 point: RIGHT,true,RIGHT,-2,0", msg .. ": the sample's health percent with no side saved")
    eq(HpAt({ friendlyHealthTextPos = "left" }), "100% | 1 point: LEFT,true,LEFT,2,0", msg .. ": the sample's health percent on the left")
    eq(HpAt({ friendlyHealthTextPos = "center" }), "100% | 1 point: CENTER,true,CENTER,0,0", msg .. ": the sample's health percent on the centre")
    eq(HpAt({ friendlyHealthTextPos = "top" }), "100% | 1 point: RIGHT,true,RIGHT,-2,0", msg .. ": the sample's health percent with a side that is none")
    eq(HpAt({ friendlyHideHealthText = true, friendlyHealthTextPos = "left" }), " | 1 point: LEFT,true,LEFT,2,0", msg .. ": the sample's health percent while off")
    eq(HpAt({}), "100% | 1 point: RIGHT,true,RIGHT,-2,0", msg .. ": the sample's health percent back on the right")
    H.SetState({})
    -- your character's name shows nowhere on either sample, in any setting
    local leaks, n = 0, 0
    Combos(FRIENDLY_NAV_FLAGS, 99, function(state)
        n = n + 1
        H.SetState(state)
        nsData.NPO_FriendlyPreviewUpdate()
        for _, s in ipairs({ S.player, S.npc }) do
            for _, part in ipairs({ "name", "sub", "hpText" }) do
                local text = rawget(s, part) and s[part]._text or ""
                if text:find("Ellesmere", 1, true) or text:find("Stormrage", 1, true) then leaks = leaks + 1 end
            end
        end
    end)
    check(leaks == 0 and n > 500, msg .. ": your character's name shows on a sample in " .. leaks .. " of " .. n .. " settings")
    H.SetState({})

    -- the eye: one hand-made button, on the Show Raid Marker half, nearest its toggle
    local rgn
    for _, r in ipairs(page.rows) do
        if r.r.text == "Show Raid Marker" then rgn = r.row._rightRegion end
    end
    local buttons = {}
    for i = c0 + 1, #Wd.created do
        if Wd.created[i]._kind == "Button" then buttons[#buttons + 1] = Wd.created[i] end
    end
    local eye = buttons[1]
    if not check(rgn and #buttons == 1 and eye._parent == rgn, msg .. ": the page does not make one button, on the Show Raid Marker half (" .. #buttons .. " made)") then return end
    local pt = eye._points[1]
    check(eye._w == 26 and eye._h == 26 and #eye._points == 1 and pt[1] == "RIGHT" and pt[2] == rgn._control and pt[3] == "LEFT" and pt[4] == -8 and pt[5] == 0
        and eye._level == rgn._level + 5 and rgn._lastInline == eye, msg .. ": the eye's size, spot (left of its toggle), level or place as the half's last inline item")
    -- its one texture: the closed eye while the marker is hidden, the open one while it shows
    local icons = rawget(eye, "_textures") or {}
    local icon = icons[1]
    if not check(#icons == 1 and icon, msg .. ": the eye does not carry one texture (" .. #icons .. ")") then return end
    local function Shown() return S.npc.raid:IsShown() end
    local function Paints(fn)
        local n0 = Wd.npcPaints or 0
        fn()
        return (Wd.npcPaints or 0) - n0
    end
    local function Click() H.ResetLog(); return Paints(function() eye._scripts.OnClick(eye) end) end
    local function Enter() H.ResetLog(); eye._scripts.OnEnter(eye); return tostring(LOG.tip) .. " @" .. tostring(eye._glyphA) end
    local function Leave() eye._scripts.OnLeave(eye); return eye._glyphA end
    -- off at first: no marker on the sample NPC, though Show Raid Marker is on by default
    nsData.NPO_FriendlyPreviewUpdate()
    check(os.showNPCMarkerPreview == false and not Shown() and eye._glyphA == 0.4 and icon._tex == "eye",
        msg .. ": at first the eye is on, greyed, or the sample NPC wears a marker")
    check(nsData.defaults.showNPCRaidMarker == true, msg .. ": Show Raid Marker is no longer on by default (the eye is about the sample alone)")
    eq(Enter(), "Show/Hide on Preview @0.7", msg .. ": the eye's tooltip and look under the pointer")
    eq(Leave(), 0.4, msg .. ": the eye's look once the pointer leaves")
    -- a click: the marker on the sample, one repaint of the samples, no page refresh, nothing saved
    eq(Click(), 1, msg .. ": repaints of the samples by a click on the eye")
    check(os.showNPCMarkerPreview == true and Shown() and icon._tex == "noeye" and LOG.refresh == 0 and #WRITES == 0,
        msg .. ": a click on the eye does not show the marker, or refreshes the page, or saves something")
    local p2 = S.npc.raid._points[1]
    check(p2 and p2[1] == "BOTTOM" and p2[2] == S.npc.name and p2[3] == "TOP" and S.npc.raid._w == 24, msg .. ": the marker is not over the sample NPC's name at the Raid Marker's size")
    eq(Click(), 1, msg .. ": repaints of the samples by a second click on the eye")
    check(os.showNPCMarkerPreview == false and not Shown() and icon._tex == "eye", msg .. ": a second click on the eye leaves the marker")
    -- while Show Friendly NPC Nameplates is off (the default) its row is greyed, the eye is not
    Click()
    check(Shown() and eye._glyphA == 0.4, msg .. ": the eye does not work while friendly NPC nameplates are off")
    H.SetState({ showFriendlyNPCs = true, showFriendlyPlayers = false })
    H.Refresh(page)
    nsData.NPO_FriendlyPreviewUpdate()
    check(Shown() and eye._glyphA == 0.4, msg .. ": the eye or the marker goes with the Blizzard Default style (the samples only dim)")
    -- greyed, and a click does nothing, while the sample could not wear one
    for _, c in ipairs({ { { friendlyNameOnly = false }, "Requires Friendly Nameplate Style set to Name Only" }, { { raidMarkerPos = "none" }, "requires Raid Marker" },
                         { { showNPCRaidMarker = false }, "requires Show Raid Marker" } }) do
        H.SetState(c[1])
        H.Refresh(page)
        nsData.NPO_FriendlyPreviewUpdate()
        local what = msg .. ", " .. StateText(c[1], STYLE)
        check(eye._glyphA == 0.15 and not Shown(), what .. ": the eye is not greyed, or the marker shows")
        eq(Enter(), c[2] .. " @0.15", what .. ": the greyed eye's tooltip and look under the pointer")
        eq(Leave(), 0.15, what .. ": the greyed eye's look once the pointer leaves")
        eq(Click(), 0, what .. ": repaints by a click on the greyed eye")
        check(os.showNPCMarkerPreview == true, what .. ": a click on the greyed eye changes its state")
    end
    -- back to settings that allow it: the marker is back with no click (the eye kept its state)
    H.SetState({})
    H.Refresh(page)
    nsData.NPO_FriendlyPreviewUpdate()
    check(eye._glyphA == 0.4 and Shown(), msg .. ": the marker does not come back with the settings")
    -- the row's own toggle: off hides the marker and refreshes the page (the eye greys), on shows it again
    local toggle
    for _, r in ipairs(page.rows) do if r.r.text == "Show Raid Marker" then toggle = r.r end end
    H.ResetLog()
    toggle.setValue(false)
    check(LOG.refresh == 1 and not Shown(), msg .. ": Show Raid Marker off leaves the marker on the sample, or does not refresh the page")
    H.Refresh(page)
    eq(eye._glyphA, 0.15, msg .. ": the eye after Show Raid Marker off and the page's refresh")
    toggle.setValue(true)
    H.Refresh(page)
    check(Shown() and eye._glyphA == 0.4, msg .. ": Show Raid Marker on again does not bring the marker and the eye back")
    -- the health bar NPC plate wears none, whatever the eye says
    H.SetState({ friendlyNameOnly = false })
    nsData.NPO_FriendlyPreviewUpdate()
    check(not Shown(), msg .. ": the health bar NPC sample wears a marker")
    -- a page built again: a new eye, in the state the first was left in
    H.SetState({})
    local c1 = #Wd.created
    local page2 = H.Build(Wd, FRIENDLY)
    local eye2
    for i = c1 + 1, #Wd.created do if Wd.created[i]._kind == "Button" then eye2 = Wd.created[i] end end
    check(page2.ok and eye2 and eye2 ~= eye and os.showNPCMarkerPreview == true and Shown(), msg .. ": a page built again loses the eye or its state")
    eye2._scripts.OnClick(eye2)
    check(os.showNPCMarkerPreview == false and not Shown(), msg .. ": the new eye does not turn the marker off")
    -- the search pre-build makes no eye
    local c2 = #Wd.created
    local pre = H.Build(Wd, FRIENDLY, true)
    check(pre.ok and #Wd.created == c2, msg .. ": the search pre-build makes a frame")
    os.showNPCMarkerPreview = false
    H.SetState({})
    EllesmereUIDB = {}
end

-- 11e. The hint is the account's: dismissed on one page, it shows on none
local function CheckNavHintAcross(Wd, tag)
    local nav, Nav = Wd.nav, Wd.env.Nav
    local msg = tag .. ": the hint across the pages"
    EllesmereUIDB = {}
    H.SetState({})
    local d = H.Build(Wd, DISPLAY)
    local t = H.Build(Wd, TFH)
    local f = H.Build(Wd, FRIENDLY)
    check(d.header.height == 99 and t.header.height == 144 and Nav.Page(FRIENDLY).fs:IsShown(), msg .. ": the hint does not show on every header")
    -- a click on the Target, Focus & Hover preview dismisses it for the others too
    local list = OvsSince(Wd, #nav.ovs - #TFH_OVERLAYS)
    local r = H.Press(Wd, function() list[3].btn._scripts.OnMouseDown(list[3].btn) end)
    eq(#r.dismiss, 1, msg .. ": dismissals by a click")
    H.RunFades(Wd)
    local d2, t2, f2 = H.Build(Wd, DISPLAY), H.Build(Wd, TFH), H.Build(Wd, FRIENDLY)
    check(d2.header.height == 70 and t2.header.height == 115 and f2.header.height == f.header.height - 29
        and not Nav.Page(DISPLAY).fs:IsShown() and not Nav.Page(TFH).fs:IsShown() and not Nav.Page(FRIENDLY).fs:IsShown(),
        msg .. ": a header built after the dismissal shows the hint")
    EllesmereUIDB = {}
end

-------------------------------------------------------------------------------
-- 12. Saved override entries filed under a section whose rows are on another page
-------------------------------------------------------------------------------
-- The rows the three sections held, as a saved entry names them: its page, its
-- section, the page that holds those rows, their labels. NOW: what a row reads
-- today where that changed (a saved entry keeps its label until its row is
-- edited again, which takes the entry over by the keys it holds).
local NOW = { ["Enable Target Color"] = "Target Color", ["Enable Focus Color"] = "Focus Color",
    ["Show Hash Line on Target at Percent"] = "Show Hash Line on Target", ["Distance to Target Text (Range)"] = "Distance to Target Text",
    ["Show EUI Friendly Player Nameplates"] = "Friendly Nameplate Style", ["Make Friendly Nameplates Name Only"] = "Friendly Nameplate Style",
    ["Guild Text Color"] = "Subtitle Text" }
local MOVED_ROWS = {
    { DISPLAY, "TARGET, FOCUS & HOVER EFFECTS", TFH, { "Target Effect", "Target Arrows", "Enable Target Color", "Enable Focus Color",
        "Target Texture", "Focus Texture", "Hover Texture", "Hover Effect" } },
    { GENERAL, "TARGET AND FOCUS EFFECTS", TFH, { "Show Hash Line on Target at Percent", "Hash Line Location", "Scale Target Nameplate",
        "Non-Target Opacity", "Focus Cast Height", "Focus Letter", "Distance to Target Text (Range)" } },
    { GENERAL, "OTHER NAMEPLATES", FRIENDLY, { "Show EUI Friendly Player Nameplates", "Make Friendly Nameplates Name Only",
        "Friendly Name Size", "Subtitle Text", "Guild Text Color", "Show Friendly NPC Nameplates", "Friendly Names Not Clickable" } },
}
local function CheckMovedSections(Wd, tag, pages)
    -- the module's table
    local got = {}
    for page, secs in pairs(Wd.cfg.movedSections or {}) do
        for sec, to in pairs(secs) do
            local stay = {}
            for label, v in pairs(type(to) == "table" and to.stay or {}) do stay[#stay + 1] = label .. "=" .. tostring(v) end
            table.sort(stay)
            got[#got + 1] = page .. " / " .. sec .. " -> " .. tostring(type(to) == "table" and to.page or to)
                .. (#stay > 0 and " (" .. table.concat(stay, ",") .. " stays)" or "")
        end
    end
    table.sort(got)
    eq(table.concat(got, "; "), "Display / TARGET, FOCUS & HOVER EFFECTS -> Target, Focus & Hover; "
        .. "General / OTHER NAMEPLATES -> Friendly Plates (Show Enemy Pet Nameplates=true stays); "
        .. "General / TARGET AND FOCUS EFFECTS -> Target, Focus & Hover", tag .. ": the sections the module lists on another page")
    -- The real helpers, cut by their first and last lines: the page of an entry's row and the tab
    -- label (the panel file), the crumb (the session file), the override list's row (the list
    -- file). A second module outside the suite carries the same table.
    local went, fonts = {}, {}
    local E = { TAB_LABEL_OVERRIDES = {}, CONTENT_PAD = 40,
        _Pool = { CreateFrame = function(kind, _, parent) return Frame(kind, parent) end },
        MakeFont = function(parent, size)
            local fs = Frame("FontString", parent)
            fs._font = { "font", size }
            fonts[#fonts + 1] = fs
            return fs
        end,
        SolidTex = function(parent) return Frame("Texture", parent) end,
        MakeRoundedBorder = function() return { SetColor = function() end } end }
    function E:GetModuleTitle(m) return m == FOLDER and Wd.cfg.title or nil end
    function E:SelectModule(m) went[#went + 1] = "module " .. tostring(m) end
    function E:SelectPage(p) went[#went + 1] = "page " .. tostring(p) end
    local NS = { IsSuiteKey = function(k) return k == FOLDER end }
    local env = setmetatable({ EllesmereUI = E, EUI_NS = NS,
        modules = { [FOLDER] = Wd.cfg, Plugin = { movedSections = Wd.cfg.movedSections } },
        L = function(s) return s end, Cond = { GetStore = function() return nil end } }, { __index = _G })
    local function Load(file, first, last, tail)
        local src = ReadSource(file)
        if not check(src ~= nil, tag .. ": " .. file .. " is missing") then return nil end
        local fn = assert(loadstring(Cut(src, first, last, file) .. (tail or ""), "=" .. file))
        return setfenv(fn, env)()
    end
    Load("EllesmereUI_Panel.lua", "function EUI_NS.GetTabLabel(", "\n-- Tab buttons are pooled by position")
    env.BuildEntryCrumb = Load("EUI_SpecOverrides_Session.lua", "local function BuildEntryCrumb(",
        "\n-- The entry a slot with no entry under its name", "\nreturn BuildEntryCrumb")
    local BuildListRow = Load("EUI_SpecOverrides_ListPage.lua", "local function TitleCase(s)",
        "\n-- Row for one STRANDED per-spec value", "\nreturn BuildListRow")
    if not check(type(NS.EntryPage) == "function" and type(env.BuildEntryCrumb) == "function" and type(BuildListRow) == "function",
        tag .. ": the page helper, the crumb builder or the override list's row is not where the test cuts it") then return end
    -- one override list row for a saved entry: its crumb, and where Go to Setting goes
    local function Row(entry)
        for i = #fonts, 1, -1 do fonts[i] = nil end
        for i = #went, 1, -1 do went[i] = nil end
        local parent = Frame("Frame")
        parent._w = 800
        BuildListRow(parent, -10, entry)
        local go
        for _, fs in ipairs(fonts) do
            if fs._text == "Go to Setting" then go = fs._parent end
        end
        local click = go and go:GetScript("OnClick")
        if click then click(go) end
        return tostring(fonts[2] and fonts[2]._text) .. " | " .. table.concat(went, ", ")
    end
    local SAVED = "the crumb the entry was saved with"
    local function Entry(page, section, label, noSlot)
        return { label = label, slotLabel = not noSlot and label or nil, module = FOLDER, page = page, section = section,
            crumb = SAVED, values = { default = {} } }
    end
    local TAB = { [TFH] = "Target, Focus & Hover", [FRIENDLY] = "Friendly" }
    for _, m in ipairs(MOVED_ROWS) do
        local from, section, to, labels = m[1], m[2], m[3], m[4]
        -- the section is no section of its first page (no edit files a new entry under the pair)
        if pages[from] then
            check(pages[from].sections[section] == nil, tag .. ": " .. section .. " is still a section of " .. from)
        end
        for _, label in ipairs(labels) do
            local msg = tag .. ": a saved entry of " .. label .. " (" .. from .. " / " .. section .. ")"
            local page, moved = NS.EntryPage(FOLDER, from, section, label)
            check(page == to and moved == true, msg .. " is on " .. tostring(page) .. ", want " .. to)
            check(pages[to] and RowOf(pages[to], NOW[label] or label) ~= nil, msg .. ": " .. to .. " has no such row")
            check(not (pages[from] and (RowOf(pages[from], label) or RowOf(pages[from], NOW[label] or label))),
                msg .. ": " .. from .. " still has that row")
            eq(Row(Entry(from, section, label)), "Nameplates  >  " .. TAB[to] .. " | module " .. FOLDER .. ", page " .. to,
                msg .. ": its crumb in the override list, and where Go to Setting goes")
        end
    end
    -- an entry saved with no slot label is known by its label
    eq(Row(Entry(GENERAL, "TARGET AND FOCUS EFFECTS", "Focus Letter", true)),
        "Nameplates  >  Target, Focus & Hover | module " .. FOLDER .. ", page " .. TFH, tag .. ": a moved entry with no slot label")
    -- Show Enemy Pet Nameplates is still on the Extras tab
    local page, moved = NS.EntryPage(FOLDER, GENERAL, "OTHER NAMEPLATES", "Show Enemy Pet Nameplates")
    check(page == GENERAL and moved == false, tag .. ": Show Enemy Pet Nameplates is on " .. tostring(page) .. " (it is still on the Extras tab)")
    check(pages[GENERAL] and RowOf(pages[GENERAL], "Show Enemy Pet Nameplates") ~= nil
        and pages[FRIENDLY] and not RowOf(pages[FRIENDLY], "Show Enemy Pet Nameplates"), tag .. ": Show Enemy Pet Nameplates is not a row of the Extras tab alone")
    eq(Row(Entry(GENERAL, "OTHER NAMEPLATES", "Show Enemy Pet Nameplates")),
        "Nameplates  >  Extras  >  Other Nameplates | module " .. FOLDER .. ", page " .. GENERAL, tag .. ": a saved entry of Show Enemy Pet Nameplates")
    -- the row is known by the entry's slot label, and by its label where it has none
    eq(Row(Entry(GENERAL, "OTHER NAMEPLATES", "Show Enemy Pet Nameplates", true)),
        "Nameplates  >  Extras  >  Other Nameplates | module " .. FOLDER .. ", page " .. GENERAL, tag .. ": Show Enemy Pet Nameplates with no slot label")
    local named = Entry(GENERAL, "OTHER NAMEPLATES", "Show Enemy Pet Nameplates")
    named.label = "Subtitle Text"
    eq(Row(named), "Nameplates  >  Extras  >  Other Nameplates | module " .. FOLDER .. ", page " .. GENERAL,
        tag .. ": an entry whose label is another row's (its slot label names the row)")
    -- entries of rows that are where they were, the old names on a page that lists nothing included
    for _, e in ipairs({ { DISPLAY, "HEALTH AND CAST BAR", "Health Bar Height", "Enemy  >  Health And Cast Bar" },
                         { GENERAL, "EXTRAS", "Execute Pulse Glow", "Extras  >  Extras" },
                         { COLORS, "OTHER NAMEPLATES", "Focus Letter", "Enemy Colors  >  Other Nameplates" },
                         { DISPLAY, "TARGET AND FOCUS EFFECTS", "Focus Letter", "Enemy  >  Target And Focus Effects" },
                         { GENERAL, "TARGET, FOCUS & HOVER EFFECTS", "Target Effect", "Extras  >  Target, Focus & Hover Effects" },
                         { TFH, "TARGET", "Target Effect", "Target, Focus & Hover  >  Target" },
                         { FRIENDLY, "FRIENDLY NPCS", "Show NPC Titles", "Friendly  >  Friendly Npcs" } }) do
        eq(Row(Entry(e[1], e[2], e[3])), "Nameplates  >  " .. e[4] .. " | module " .. FOLDER .. ", page " .. e[1],
            tag .. ": a saved entry of " .. e[1] .. " / " .. e[2])
    end
    -- an entry with no page keeps the crumb it was saved with, and Go to Setting opens the module
    eq(Row(Entry(nil, "TARGET AND FOCUS EFFECTS", "Focus Letter")), "The Crumb The Entry Was Saved With | module " .. FOLDER,
        tag .. ": a saved entry with no page")
    -- a module that is not the suite's own is not read
    local p2, m2 = NS.EntryPage("Plugin", GENERAL, "TARGET AND FOCUS EFFECTS", "Focus Letter")
    check(p2 == GENERAL and m2 == false, tag .. ": a module outside the suite moves an entry (" .. tostring(p2) .. ")")
    -- the list reads the entry and writes nothing into it
    local e = Entry(GENERAL, "TARGET AND FOCUS EFFECTS", "Focus Letter")
    Row(e)
    local n = 0
    for _ in pairs(e) do n = n + 1 end
    check(n == 7 and e.page == GENERAL and e.section == "TARGET AND FOCUS EFFECTS" and e.label == "Focus Letter"
        and e.slotLabel == "Focus Letter" and e.crumb == SAVED and next(e.values.default) == nil, tag .. ": the override list changed a saved entry")
end

-------------------------------------------------------------------------------
-- The run: both clients
-------------------------------------------------------------------------------
for _, client in ipairs({ { "retail", false }, { "WoW Forever", true } }) do
    local tag, forever = client[1], client[2]
    local Wd
    Part(tag .. ": the world", function() Wd = H.NewWorld(forever) end)
    local ready = false
    if Wd then
        Part(tag .. ": the registration", function() ready = CheckRegistration(Wd, tag, forever) end)
    end
    if ready then
        local pages, lists = {}, {}
        Part(tag .. ": the pages", function()
            pages[TFH] = CheckPage(Wd, tag, TFH, LAYOUT[TFH], { hashLineEnabled = true })
            pages[FRIENDLY] = CheckPage(Wd, tag, FRIENDLY, LAYOUT[FRIENDLY], PLATE_BUILD)
            pages[FRIENDLY_NO] = CheckPage(Wd, tag .. ", built under Name Only", FRIENDLY, LAYOUT[FRIENDLY_NO])
            -- Blizzard Default: the rows of Name Only, whichever EUI style it would go back to
            CheckPage(Wd, tag .. ", built under Blizzard Default", FRIENDLY, LAYOUT[FRIENDLY_NO], { showFriendlyPlayers = false })
            CheckPage(Wd, tag .. ", built under Blizzard Default over Nameplate", FRIENDLY, LAYOUT[FRIENDLY_NO],
                { showFriendlyPlayers = false, friendlyNameOnly = false })
            pages[GENERAL] = CheckPage(Wd, tag, GENERAL, GeneralLayout(forever))
            local g = pages[GENERAL]
            check(g and g.header == nil and g.cleared == 1, tag .. ": the General page does not clear the content header")
            check(pages[TFH] and pages[TFH].spacers == 2 and pages[FRIENDLY] and pages[FRIENDLY].spacers == 1 and g and g.spacers == 2,
                tag .. ": the spacers between the sections of the three pages")
        end)
        for _, name in ipairs({ TFH, FRIENDLY, FRIENDLY_NO, GENERAL }) do
            if pages[name] then
                Part(tag .. ": the controls of " .. name, function()
                    lists[name] = CheckControls(Wd, tag, pages[name], name, forever)
                end)
            end
        end
        for _, name in ipairs({ TFH, FRIENDLY, FRIENDLY_NO }) do
            if lists[name] then
                Part(tag .. ": the gates of " .. name, function()
                    local n = CheckGates(Wd, tag, pages[name], name, lists[name], forever)
                    check(n > 2000, tag .. ": " .. name .. " was read in " .. n .. " scenarios only")
                end)
                Part(tag .. ": the refreshes of " .. name, function() CheckRefresh(Wd, tag, pages[name], name, lists[name]) end)
            end
        end
        if lists[TFH] and lists[FRIENDLY] and lists[FRIENDLY_NO] and lists[GENERAL] then
            Part(tag .. ": the saved keys", function() CheckKeys(Wd, tag, pages, lists) end)
        end
        if lists[FRIENDLY] then
            Part(tag .. ": Blizzard Nameplate Size", function() CheckNameplateSize(Wd, tag, pages[FRIENDLY], lists[FRIENDLY]) end)
            Part(tag .. ": Friendly Nameplate Style and Name Color", function()
                CheckStyleAndNameColor(Wd, tag, pages[FRIENDLY], lists[FRIENDLY])
            end)
        end
        if pages[TFH] and lists[TFH] then
            Part(tag .. ": the Hash Line Location row and the row labels' suffixes", function()
                CheckHashRow(Wd, tag, pages[TFH], lists[TFH])
            end)
        end
        Part(tag .. ": Global Search", function() CheckSearch(Wd, tag, pages, forever) end)
        Part(tag .. ": saved override entries of the moved rows", function() CheckMovedSections(Wd, tag, pages) end)
        -- the class rows of the Extras tab: its last half
        Part(tag .. ": the Extras tab's class row", function()
            Wd.classFile, Wd.specID = "DEATHKNIGHT", 250
            CheckPage(Wd, tag .. ", Blood Death Knight", GENERAL, GeneralLayout(forever, "Hide Copies of Blood Plague"))
            Wd.classFile, Wd.specID = "WARRIOR", 71
            CheckPage(Wd, tag .. ", Warrior", GENERAL, GeneralLayout(forever, forever and "Show Sunder Armor" or nil))
            Wd.classFile, Wd.specID = nil, nil
        end)
        Part(tag .. ": the previews", function() CheckPreviews(Wd, tag) end)
        -- the click navigation
        Part(tag .. ": the click navigation kit", function() CheckNavKit(Wd, tag) end)
        Part(tag .. ": the Enemies click navigation", function() CheckNavDisplay(Wd, tag) end)
        Part(tag .. ": the Target, Focus & Hover click navigation", function() CheckNavTFH(Wd, tag, forever) end)
        Part(tag .. ": the Friendly Plates click navigation", function() CheckNavFriendly(Wd, tag) end)
        Part(tag .. ": the friendly samples' name and the marker's eye", function() CheckFriendlySamples(Wd, tag, forever) end)
        Part(tag .. ": the hint across the pages", function() CheckNavHintAcross(Wd, tag) end)
    end
end

-------------------------------------------------------------------------------
-- 10. What the files must not hold, and what they say (the same on both clients)
-------------------------------------------------------------------------------
Part("the sources", function()
    local FILES = { "ColorsPage_Options.lua", "CoreTextColoring_Options.lua", "DisplayBars_Options.lua", "DisplayLayout_Options.lua",
        "FriendlyPage_Options.lua", "FriendlyPreview_Options.lua", "GeneralPage_Options.lua", "NameplatePreview_Options.lua",
        "TargetFocusHoverPage_Options.lua" }
    local src = { main = ReadSource(OPT .. "EUI_Nameplates_Options.lua") or "" }
    local all = src.main
    for _, name in ipairs(FILES) do
        src[name] = ReadSource(NPO .. name)
        check(src[name] ~= nil, "the options file " .. name .. " is missing")
        src[name] = src[name] or ""
        all = all .. src[name]
    end
    for _, gone in ipairs({ '"Target Preview"', '"Focus Preview"', "showTargetGlowPreview", "LazyColorPreviewBar", "MakeColorPreviewBar",
        "SECTION_FRIENDLY", 'W:SectionHeader(parent, "TARGET AND FOCUS EFFECTS"', 'W:SectionHeader(parent, "TARGET, FOCUS & HOVER EFFECTS"',
        '"Friendly NPC Settings"', "TAB_LABEL_OVERRIDES" }) do
        check(not all:find(gone, 1, true), "the Nameplates options still hold " .. gone)
    end
    -- these three section names are search words, and each one key of the module's movedSections
    for _, old in ipairs({ "OTHER NAMEPLATES", "TARGET AND FOCUS EFFECTS", "TARGET, FOCUS & HOVER EFFECTS" }) do
        local n, inWords, inMoved = 0, 0, 0
        for line in all:gmatch("[^\n]+") do
            if line:find('"' .. old .. '"', 1, true) then
                n = n + 1
                if line:find("SearchWords(", 1, true) then inWords = inWords + 1 end
                if line:find('["' .. old .. '"] = ', 1, true) then inMoved = inMoved + 1 end
            end
        end
        check(inWords > 0 and inMoved == 1 and n == inWords + 1,
            old .. " is named " .. n .. " times: " .. inWords .. " as a search word, " .. inMoved .. " as a moved section")
    end
    -- no eye button on the Target, Focus & Hover page (the hitbox eye is the Extras tab's)
    check(not src["TargetFocusHoverPage_Options.lua"]:find("EYE_", 1, true), "the Target, Focus & Hover page has an eye button")
    -- the preview keeps itself by its mode, and the header hands the picked mode in
    local pv = src["NameplatePreview_Options.lua"]
    check(pv:find("\n    pf._mode = mode\n", 1, true) and pv:find('\n    optState[mode and "tfhPreview" or "activePreview"] = pf\n', 1, true),
        "the preview does not keep itself under its page's name (activePreview for no mode, tfhPreview for a mode)")
    check(pv:find('BuildNameplatePreview(headerParent, headerW, optState.tfhMode or "target")', 1, true),
        "the Target, Focus & Hover header does not build the preview in the picked state, the target at first")
    -- the Enemies plate (no mode) is a plain one: the target arrows and the hash line are
    -- the target state's, and the state's effects are drawn for a state only
    check(pv:find('\n        local showArrows = self._mode == "target" and DBVal("showTargetArrows") == true\n', 1, true),
        "the preview draws the target arrows outside the target state")
    check(pv:find('\n        local hlEnabled = self._mode == "target" and DBVal("hashLineEnabled")\n', 1, true),
        "the preview draws the hash line outside the target state")
    -- the plate on the header's middle: the bar, and on a state plate under the WoW Forever
    -- style the bar with the level box right of it as one body (the line itself, run over
    -- stand-ins: a 1000 wide header, a 150 wide bar, a level box that takes 33)
    do
        local line = pv:match("\n            (xOff = Snap%(%(pfW %- barW[^\n]*)\n            _cachedRawBarW = rawBarW\n")
        if check(line, "the preview's centring line is not found") then
            local fn = assert(loadstring("local self, previewGlow, ns, pfW, barW = ...\nlocal xOff\nlocal function Snap(v) return v end\n"
                .. line .. "\nreturn xOff"))
            local box, noBox = { NP_ForeverSide = function() return 33 end }, { NP_ForeverSide = function() return 0 end }
            for _, mode in ipairs({ "target", "focus", "hover" }) do
                eq(fn({ _mode = mode }, { forever = true }, box, 1000, 150), 408.5,
                    "the " .. mode .. " plate under the WoW Forever style: the bar's left edge (bar and level box centred together)")
                eq(fn({ _mode = mode }, { forever = false }, box, 1000, 150), 425, "the " .. mode .. " plate under another style: the bar on the middle")
                eq(fn({ _mode = mode }, { forever = true }, noBox, 1000, 150), 425, "the " .. mode .. " plate with the level box off: the bar on the middle")
            end
            eq(fn({}, { forever = true }, box, 1000, 150), 425, "the Display page's plate under the WoW Forever style keeps its bar on the middle")
            eq(fn({}, { forever = false }, box, 1000, 150), 425, "the Display page's plate: the bar on the middle")
        end
    end
    check(pv:find("\n        if self._mode then previewGlow.state(self._mode, fontPath, npOutline) end\n", 1, true),
        "the preview draws a state's effects on the plate with no state")
    -- the state painting inside the preview's Update, a line each (the harness's Target, Focus &
    -- Hover preview is a stand-in for it), and the friendly samples' level over their header
    for _, pin in ipairs({
        { '\n        previewGlow.cpOn = DBVal("showClassPower") == true and not self._mode\n',
          "the class resource on the Display page's plate alone" },
        -- the bare state preview: no cast bar, no Core Positions element (each reads as in no
        -- slot), the bottom texts under the health bar, the cast bar out of the height
        { '\n        cast:SetShown(not self._mode)\n', "no cast bar on a state's plate" },
        { '\n        local debuffSlotVal = self._mode and "none" or DBVal("debuffSlot") or defaults.debuffSlot\n'
            .. '        local buffSlotVal   = self._mode and "none" or DBVal("buffSlot")   or defaults.buffSlot\n'
            .. '        local ccSlotVal     = self._mode and "none" or DBVal("ccSlot")     or defaults.ccSlot\n',
          "no aura row on a state's plate" },
        { '\n        local rmPos = self._mode and "none" or DBVal("raidMarkerPos") or defaults.raidMarkerPos\n', "no raid marker on a state's plate" },
        { '\n        local clPos = self._mode and "none" or DBVal("classificationSlot") or defaults.classificationSlot\n',
          "no Rare/Quest indicator on a state's plate" },
        { '\n        local fcPos = self._mode and "none" or (fcCombined and clPos or (DBVal("factionSlot") or defaults.factionSlot or "none"))\n',
          "no faction badge on a state's plate" },
        { '\n            local pos = self._mode and "none" or ns.NP_GetQuestTextSlot(DB())\n', "no Quest Objective Text on a state's plate" },
        { '\n            local by = (self._mode and 0 or math.min(0, pCastY - castH)) - 2\n', "the bottom texts under the health bar of a state's plate" },
        { '\n        local totalH = Snap(healthFromTop + barH + (self._mode and 0 or castH) + cpExtraH + 15)\n',
          "a state's plate as tall as it draws (no cast bar)" },
        { '\n        local wrapActive = wrapOn and borderVisible and not self._mode\n', "no border wrapped round a cast bar a state's plate lacks" },
        { '\n                if DBVal("cornerJoinCast") and not self._mode then\n', "a state's plate with its own corners (no cast bar to join)" },
        { '\n            if self._mode or previewGlow.classic or not (showIcon and fullSize) or (side == "right") ~= onRight then return 0 end\n',
          "no full-size spell icon push on a state's plate" },
        { '\n        if (self._mode == "target" or self._mode == "focus") and DBVal(self._mode .. "ColorEnabled") then\n'
            .. '            eic = DBVal(self._mode) or eic\n        end\n',
          "the target and the focus colour on their plates' bars" },
        { '\n        if self._mode then\n            previewGlow.plateScale(self._mode == "target" and ns.GetTargetScale() / 100 or 1)\n        end\n',
          "the target's plate at Scale Target Nameplate" },
        { '\n        local fxSz, fxCol = previewGlow.fxBorder(self._mode)\n', "the effects' Border Size and Border Color on the border" },
        { '\n                if state == "target" then c = NAMEPLATE_BORDER_TARGET_COLOR else c = NAMEPLATE_BORDER_FOCUS_TARGET_COLOR end\n',
          "Blizzard Style's ring in the target's or the focus' colour" },
        { '\n                    roots = { previewGlow.ovFill, previewGlow.ovBg }, rect = health, border = pcb, style = style,\n',
          "the texture clips under Corner Radius" },
        { '\n                box._sel:SetShown(sc ~= nil)\n', "the WoW Forever level box's state border" },
    }) do
        check(pv:find(pin[1], 1, true), "the preview does not paint " .. pin[2])
    end
    for _, key in ipairs({ "debuffSlot", "buffSlot", "ccSlot", "raidMarkerPos", "classificationSlot", "factionSlot" }) do
        local n = 0
        for _ in pv:gmatch('DBVal%("' .. key .. '"%)') do n = n + 1 end
        eq(n, 1, "the preview's reads of " .. key .. " (one, behind the state's gate)")
    end
    do
        local n = 0
        for _ in pv:gmatch("NP_GetQuestTextSlot%(") do n = n + 1 end
        eq(n, 1, "the preview's reads of the Quest Objective Text's slot")
        n = 0
        for _ in pv:gmatch("cast:SetShown%(") do n = n + 1 end
        eq(n, 1, "the places the preview shows or hides its cast bar")
        check(not pv:find("cast:Hide()", 1, true) and not pv:find("cast:Show()", 1, true), "the preview shows or hides its cast bar outside the state's gate")
    end
    -- no plate of the preview sizes a cast bar at Focus Cast Height (the focus plate draws none)
    check(not pv:find("GetFocusCastHeight", 1, true) and pv:find('\n        local castH      = Snap(DBVal("castBarHeight") or defaults.castBarHeight)\n', 1, true),
        "the preview sizes its cast bar by Focus Cast Height, which no plate of it shows")
    -- the friendly samples: the player sample reads no name, title or guild of yours (its own
    -- are set words), and the runtime hands the options no name formatter for it
    local fpv = src["FriendlyPreview_Options.lua"]
    check(not fpv:find("UnitName", 1, true) and not fpv:find("UnitPVPName", 1, true) and not fpv:find("GetGuildInfo", 1, true)
        and not fpv:find("NP_FormatFriendlyName", 1, true) and fpv:find('local name = EllesmereUI.L("Friendly Player")', 1, true)
        and fpv:find('return EllesmereUI.Lf("%s The Immortal", shown)', 1, true)
        and fpv:find('local guild = (mode == "guild" or mode == "both") and EllesmereUI.L("Guild") or nil', 1, true),
        "the player sample reads your character's name, title or guild, or is not Friendly Player The Immortal of Guild")
    local friendlyRT = ReadSource(RT .. "EllesmereUINameplatesFriendly.lua")
    check(friendlyRT and not friendlyRT:find("NP_FormatFriendlyName", 1, true), "the runtime still hands out a name formatter no options file calls")
    -- the page: one Focus Letter control (no Anchor row in its cog), no overlay on the cast bar
    local tfhSrc = src["TargetFocusHoverPage_Options.lua"]
    check(not tfhSrc:find('label="Anchor"', 1, true) and not tfhSrc:find('"focusCast"', 1, true) and not tfhSrc:find("focusCast ", 1, true)
        and not tfhSrc:find("pv._cast", 1, true),
        "the Target, Focus & Hover page keeps an Anchor cog row or an overlay on the cast bar")
    check(src["FriendlyPreview_Options.lua"]:find("\n    s:SetParent(hdr)\n    s:SetFrameLevel(hdr:GetFrameLevel() + 2)\n", 1, true),
        "the friendly samples do not hang two levels over their header")
    -- a preview that is not on screen leaves the header's height alone: its one resize is
    -- inside its own visibility test
    local vis = pv:find("\n        if self:IsVisible() then\n", 1, true)
    local visEnd = vis and pv:find("\n        end\n", vis, true)
    local resize = pv:find("EllesmereUI:UpdateContentHeaderHeight(", 1, true)
    check(vis and visEnd and resize and vis < resize and resize < visEnd
        and not pv:find("EllesmereUI:UpdateContentHeaderHeight(", resize + 1, true) and not pv:find("SetContentHeaderHeightSilent", 1, true),
        "the preview resizes the content header outside its own visibility test")
    -- TOC and the standalone build list: the three new files, before the main file. The build
    -- script is kept out of git: on a checkout without it only the TOC is checked.
    local toc = ReadSource(OPT .. "EllesmereUIOptions.toc") or ""
    local build = ReadSource("build-standalone.ps1")
    local mainAt = toc:find("\nEUI_Nameplates_Options.lua\n", 1, true)
    local line = build and build:match('childFiles = @%("EllesmereUINameplates%.lua"[^\n]*') or ""
    local buildMain = line:find('"EUI_Nameplates_Options.lua"', 1, true)
    for _, name in ipairs({ "TargetFocusHoverPage_Options.lua", "FriendlyPage_Options.lua", "FriendlyPreview_Options.lua" }) do
        local at = toc:find("\nNameplates_Options\\" .. name .. "\n", 1, true)
        check(at and mainAt and at < mainAt, "the options TOC does not list " .. name .. " before the main file")
        if build then
            local b = line:find('"Nameplates_Options\\' .. name .. '"', 1, true)
            check(b and buildMain and b < buildMain, "build-standalone.ps1 does not list " .. name .. " before the main file")
        end
    end
end)

-- nothing listens, ticks or writes a CVar under another owner
eq(table.concat(EVER.events, ","), "PLAYER_LOGIN,PLAYER_SPECIALIZATION_CHANGED,PLAYER_LOGIN,PLAYER_SPECIALIZATION_CHANGED",
    "the events registered over the whole run (the main file's two, per client)")
eq(EVER.onUpdate, 0, "OnUpdate scripts set over the whole run")
eq(EVER.tickers, 0, "tickers started over the whole run")
eq(EVER.badOwner, 0, "CVars written without the module as their owner")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_options_pages (%d checks)"):format(count))
