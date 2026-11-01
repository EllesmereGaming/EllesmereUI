if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Borders.lua
--
--  Element contexts, profile snapshots and diffs, unlock-session value
--  banking, the golden borders and the edit locks.
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local BlacklistedFKey, ConflictSpec, DeepCopy = I.BlacklistedFKey, I.ConflictSpec, I.DeepCopy
local EntryOwning, FKeyLoaded, FS, GetGroups = I.EntryOwning, I.FKeyLoaded, I.FS, I.GetGroups
local GetStore, GOLD_B, GOLD_G, GOLD_R = I.GetStore, I.GOLD_B, I.GOLD_G, I.GOLD_R
local GroupById, L, MatchOwnedFKey, NIL_SENT = I.GroupById, I.L, I.MatchOwnedFKey, I.NIL_SENT
local PS, ReadLive, SpecName, Cond = I.PS, I.ReadLive, I.SpecName, I.Cond
local EXCLUDED_CONTEXTS, SetRequestGoldWalk = I.EXCLUDED_CONTEXTS, I.SetRequestGoldWalk

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _defaultView = false
I.defaultViewSetters[#I.defaultViewSetters + 1] = function(v) _defaultView = v end

-- Forward declarations (assigned further down in this file)
local RequestGoldWalk

-------------------------------------------------------------------------------
--  Element-context providers for selector pages ("which bar / frame is selected").
--  Options pages with an element selector register a provider so captured entries
--  carry their element, making labels and golden borders element-aware.
-------------------------------------------------------------------------------
local _captureContexts = {}

--- fn() -> display label of the module's currently selected element (or nil).
function EllesmereUI.RegisterCaptureContext(folder, fn)
    if type(folder) == "string" and type(fn) == "function" then
        _captureContexts[folder] = fn
    end
end

local function CurrentContext()
    local modFolder = EllesmereUI:GetActiveModule()
    local ctxFn = modFolder and _captureContexts[modFolder]
    if not ctxFn then return nil end
    local ok, ctx = pcall(ctxFn)
    if ok and type(ctx) == "string" and ctx ~= "" then return ctx end
    return nil
end

-------------------------------------------------------------------------------
--  Profile snapshots + diffs (the auto-capture watcher's engine)
-------------------------------------------------------------------------------
local function SnapshotProfiles()
    local snap = {}
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg then return snap end
    for _, db in ipairs(reg) do
        if db.folder and type(db.profile) == "table" then
            snap[db.folder] = DeepCopy(db.profile)
        end
    end
    return snap
end

local function DiffTables(old, new, prefix, out, numFlag)
    for k, nv in pairs(new) do
        local ov = old[k]
        local isNum = numFlag or (type(k) == "number")
        local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
        if type(nv) == "table" and type(ov) == "table" then
            DiffTables(ov, nv, path, out, isNum)
        elseif nv ~= ov then
            out[#out + 1] = { path = path, val = nv, num = isNum }
        end
    end
    for k in pairs(old) do
        if new[k] == nil then
            local isNum = numFlag or (type(k) == "number")
            local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
            out[#out + 1] = { path = path, removed = true, num = isNum }
        end
    end
end

local function DiffProfiles(snap)
    local out = {}
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg then return out end
    for _, db in ipairs(reg) do
        local old = db.folder and snap[db.folder]
        if old and type(db.profile) == "table" then
            local changes = {}
            DiffTables(old, db.profile, nil, changes)
            for _, c in ipairs(changes) do
                c.folder = db.folder
                c.fkey = db.folder .. FS .. c.path
                out[#out + 1] = c
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  Unlock-session value-edit banking: CAPTURED settings edited from unlock mode
--  (cog width/height inputs write the shared module store) happen panel-closed, so
--  no view owns them and the sticky harvest never adopts foreign live diffs --
--  without this the next value apply REVERTS the unlock-mode resize. A NORMAL
--  unlock session edits the shared baseline exactly like Default Editing Mode, so
--  Save & Exit banks captured diffs into values.default. Special (group fork)
--  sessions hide the size inputs and never bank here; Cancel discards.
-------------------------------------------------------------------------------
local _unlockValueSnap = nil

function EllesmereUI.SpecOverrides_UnlockValueSnapBegin()
    _unlockValueSnap = nil
    local store = GetStore()
    if not store or #store == 0 then return end
    if EllesmereUI._specialUnlockGroup then return end
    _unlockValueSnap = SnapshotProfiles()
end

function EllesmereUI.SpecOverrides_UnlockValueSnapDiscard()
    _unlockValueSnap = nil
end

function EllesmereUI.SpecOverrides_UnlockValueSnapCommit()
    local snap = _unlockValueSnap
    _unlockValueSnap = nil
    if not snap then return end
    -- Sessions/views cannot be live while unlock mode is open (the panel
    -- force-closes on entry); this guards any flow that changes that.
    if _editGroup or _defaultView or Cond._edit then return end
    local changed = false
    for _, c in ipairs(DiffProfiles(snap)) do
        local entry = EntryOwning(c.fkey)
        -- Match-owned size keys: an unlock-session diff on these is the match
        -- engine's write (re-pull on target resize), never a cog edit. Skip.
        if entry and not BlacklistedFKey(c.fkey) and not MatchOwnedFKey(c.fkey)
           and FKeyLoaded(c.fkey) then
            local live = ReadLive(c.fkey)
            if type(live) ~= "table" then
                entry.values.default[c.fkey] = (live == nil) and NIL_SENT or live
                changed = true
            end
        end
    end
    if changed then RequestGoldWalk() end
end

-- EXCLUDED_CONTEXTS is declared earlier, shared with the conditional-overrides
-- block. section is optional: callers with no section context (page overlay, gold
-- walk) treat a section-scoped page entry as NOT excluded -- only the listed
-- sections are outside the system, enforced where the section is known
-- (AutoCapture attribution and entry pruning).
local function IsExcludedContext(section)
    local module = EllesmereUI:GetActiveModule()
    local ex = module and EXCLUDED_CONTEXTS[module]
    if ex == true then return true end
    if type(ex) == "table" then
        local page = EllesmereUI:GetActivePage()
        local pex = page and ex[page]
        if pex == true then return true end
        if type(pex) == "table" then
            return (section and pex[section]) and true or false
        end
    end
    return false
end

--- True while a session is live AND the page in front of the user can actually bank a
--- value into it. A bespoke control that writes its own key on click (the Visibility
--- row's override marker) must gate on THIS, not on SpecOverrides_EditSessionActive:
--- session state is global, so on an excluded page that write would land in the shared
--- profile, be dropped by every capture gate as blacklisted, and strand there with
--- nothing owning it. The editing-as overlay is decoration only (EnableMouse(false)),
--- so nothing else stops such a click.
function EllesmereUI.SpecOverrides_SlotOverridable()
    if not EllesmereUI.SpecOverrides_EditSessionActive() then return false end
    return not IsExcludedContext()
end

-------------------------------------------------------------------------------
--  Golden borders: slots with an active override get a 1px gold PP border. Slots
--  match entries by READ-TRACING: getters are side-effect-free by convention (the
--  refresh system calls them constantly), so a walk swaps the addon profile tables
--  for read-tracking proxies, runs each visible slot's getters once, and matches
--  the recorded paths against entry fkeys. Needs no label metadata and is
--  inherently element-aware on selector pages (Bar 1 selected -> getters read
--  bar1 paths -> only Bar 1's entries match).
-------------------------------------------------------------------------------
local _traceSink = nil
local _traceReal = nil

local MakeReadProxy
do
    -- proxy -> the table it reads (weak). A getter that writes back a table it
    -- read under the trace (an accessor that ensures or compacts a structure)
    -- must store the tables behind the proxies: a proxy holds nothing of its
    -- own, so SavedVariables would save it empty, and the next trace would wrap
    -- it again, one layer per walk until reading it overflows the C stack.
    -- Writes unwrap the value, and the proxies one level inside a plain table
    -- built from them. (A do-block.)
    local proxyOf = setmetatable({}, { __mode = "k" })
    local function Unwrap(v)
        local r = proxyOf[v]
        while r do v = r; r = proxyOf[v] end
        if type(v) == "table" then
            for k, x in next, v do
                local rx = type(x) == "table" and proxyOf[x]
                if rx then rawset(v, k, Unwrap(rx)) end
            end
        end
        return v
    end

    MakeReadProxy = function(real, folder, prefix)
        local proxy = {}
        setmetatable(proxy, {
            __index = function(_, k)
                local v = real[k]
                local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
                if type(v) == "table" then
                    return MakeReadProxy(v, folder, path)
                end
                if _traceSink then
                    _traceSink[folder .. FS .. path] = true
                end
                return v
            end,
            __newindex = function(_, k, v) real[k] = Unwrap(v) end,
        })
        proxyOf[proxy] = real
        return proxy
    end
end

local function BeginTrace()
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg or _traceReal then return false end
    _traceReal = {}
    for _, db in ipairs(reg) do
        if db.folder and type(db.profile) == "table" then
            _traceReal[db] = db.profile
            db.profile = MakeReadProxy(db.profile, db.folder, nil)
        end
    end
    return true
end

local function EndTrace()
    if not _traceReal then return end
    for db, real in pairs(_traceReal) do
        db.profile = real
    end
    _traceReal = nil
end

-- Runs a slot's getters under the read proxies; returns the set of fkeys read.
local function TraceSlot(cfg)
    _traceSink = {}
    local accs = cfg.accessors or { cfg }
    for _, acc in ipairs(accs) do
        if acc.getValue then pcall(acc.getValue) end
    end
    local sink = _traceSink
    _traceSink = nil
    return sink
end


local function MakeBorderHost(region, r, g, b)
    local host = CreateFrame("Frame", nil, region)
    host:SetAllPoints()
    host:SetFrameLevel(region:GetFrameLevel() + 30)
    if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
        EllesmereUI.PP.CreateBorder(host, r, g, b, 0.9, 1, "OVERLAY", 7)
    end
    return host
end

-- mode: false (clear), "gold" (overridden), "red" (owned by a conflicting group
-- while editing: red border + click-blocking tooltip overlay), or "condActive" (the
-- APPLIED conditional owns this setting NOW -- the on-screen value is the
-- override's, an edit would bank into it at the next boundary, not the default;
-- labeled overlay + click blocker pointing at its edit mode).
-- tip: gold only -- the "Overridden by: ..." tooltip text (SlotTipFor), shown from
-- a small info badge in the slot's top-left corner (the only hover surface: the
-- widget's own label/control tooltips stay untouched).
-- A mark frame on a region of the options page pool rides on it (hidden at the
-- region's reset, its key kept) instead of being lost with the region's dress;
-- the region's next dress puts it at its new frame level (as a new mark would be).
local function SetSlotMark(region, mode, conflictSpecID, condName, tip)
    local m = region._specOvGold
    if m and m._soStale then m._soStale = nil; m:SetFrameLevel(region:GetFrameLevel() + 30) end
    m = region._specOvHover
    if m and m._soStale then m._soStale = nil; m:SetFrameLevel(region:GetFrameLevel() + 31) end
    m = region._specOvRed
    if m and m._soStale then
        m._soStale = nil
        m:SetFrameLevel(region:GetFrameLevel() + 30)
        m._blocker:SetFrameLevel(region:GetFrameLevel() + 45)
    end
    m = region._specOvCondActive
    if m and m._soStale then
        m._soStale = nil
        m:SetFrameLevel(region:GetFrameLevel() + 30)
        m._blocker:SetFrameLevel(region:GetFrameLevel() + 45)
    end
    local Pool = EllesmereUI._Pool
    if mode == "gold" and not region._specOvGold then
        region._specOvGold = MakeBorderHost(region, GOLD_R, GOLD_G, GOLD_B)
        if Pool and Pool.Gen and Pool.Gen(region) then
            Pool.Attach(region, region._specOvGold, "_specOvGold", function(h) h._soStale = true end)
        end
    end
    if mode == "gold" and tip and not region._specOvHover then
        -- Info badge: gold "i" bubble tucked inside the gold border's top-left
        -- corner (that corner is empty on every slot layout -- labels start at
        -- the side pad, vertically centered). Motion-only and click-through
        -- (same recipe as the widget label hit frames), one level above the
        -- border host so it renders on top; nothing else lives in that corner,
        -- so no control loses hover to it.
        local badge = CreateFrame("Frame", nil, region)
        badge:SetSize(14, 14)
        badge:SetPoint("TOPLEFT", region, "TOPLEFT", 3, -3)
        badge:SetFrameLevel(region:GetFrameLevel() + 31)
        local ico = badge:CreateTexture(nil, "OVERLAY")
        ico:SetAllPoints()
        if ico.SetSnapToPixelGrid then ico:SetSnapToPixelGrid(false); ico:SetTexelSnappingBias(0) end
        ico:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-info.png")
        ico:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.85)
        badge:SetScript("OnEnter", function()
            ico:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
            local t = region._specOvTip
            if t and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(badge, t)
            end
        end)
        badge:SetScript("OnLeave", function()
            ico:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.85)
            EllesmereUI.HideWidgetTooltip()
        end)
        badge:SetMouseClickEnabled(false)
        region._specOvHover = badge
        if Pool and Pool.Gen and Pool.Gen(region) then
            Pool.Attach(region, badge, "_specOvHover", function(h) h._soStale = true end)
        end
    end
    if mode == "red" and not region._specOvRed then
        local host = MakeBorderHost(region, 0.9, 0.2, 0.2)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(region:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local tint = blocker:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.9, 0.2, 0.2, 0.05)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            EllesmereUI.HideWidgetTooltip()
        end)
        host._blocker = blocker
        region._specOvRed = host
        if Pool and Pool.Gen and Pool.Gen(region) then
            Pool.Attach(region, host, "_specOvRed", function(h) h._soStale = true end)
        end
    end
    if mode == "condActive" and not region._specOvCondActive then
        -- Same look as the RF party-tab sync overlays (solid dark blue cover, centered
        -- label in the global font) plus override identity: gold border + gold label.
        -- The border goes on the BLOCKER at a high sublevel so it renders above the
        -- solid background (a border on the host would be covered).
        local host = CreateFrame("Frame", nil, region)
        host:SetAllPoints()
        host:SetFrameLevel(region:GetFrameLevel() + 30)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(region:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local bg = blocker:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints()
        bg:SetColorTexture(17/255, 15/255, 12/255, 1)
        if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
            EllesmereUI.PP.CreateBorder(blocker, GOLD_R, GOLD_G, GOLD_B, 0.9, 1, "OVERLAY", 7)
        end
        local font = (EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local flag = (EllesmereUI.GetFontOutlineFlag()) or ""
        local label = blocker:CreateFontString(nil, "OVERLAY")
        if EllesmereUI.PrimeFontShadow and EllesmereUI.GetFontUseShadow then
            EllesmereUI.PrimeFontShadow(label, EllesmereUI.GetFontUseShadow())
        end
        label:SetFont(font, 13, flag)
        label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
        label:SetPoint("LEFT", blocker, "LEFT", 4, 0)
        label:SetPoint("RIGHT", blocker, "RIGHT", -4, 0)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(false)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            EllesmereUI.HideWidgetTooltip()
        end)
        host._blocker = blocker
        host._label = label
        region._specOvCondActive = host
        if Pool and Pool.Gen and Pool.Gen(region) then
            Pool.Attach(region, host, "_specOvCondActive", function(h) h._soStale = true end)
        end
    end
    if region._specOvGold then region._specOvGold:SetShown(mode == "gold") end
    -- Tip lives only while the slot is gold; the label tooltips read it live.
    if mode == "gold" then region._specOvTip = tip else region._specOvTip = nil end
    if region._specOvHover then region._specOvHover:SetShown(region._specOvTip ~= nil) end
    if region._specOvRed then
        region._specOvRed:SetShown(mode == "red")
        if mode == "red" and region._specOvRed._blocker then
            region._specOvRed._blocker._tipText = string.format(
                L("This setting already has an override for %s"),
                conflictSpecID and SpecName(conflictSpecID) or "?")
        end
    end
    if region._specOvCondActive then
        region._specOvCondActive:SetShown(mode == "condActive")
        if mode == "condActive" then
            local host = region._specOvCondActive
            if host._label then
                host._label:SetText(string.format(L("Override Active: %s"), condName or "?"))
            end
            if host._blocker then
                host._blocker._tipText = string.format(
                    L("Showing the '%s' override's value. Edit it from that override's editing mode."),
                    condName or "?")
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Edit locks: regions that must be non-interactive while ANY Editing-as session is
--  active (same red prevention frame as cross-group conflicts). Used by hands-off
--  systems with their own per-spec handling (e.g. Resource Bars' Threshold & Hash
--  Lines slots). Regions register per page build; dead pages release their locks
--  via the weak table.
-------------------------------------------------------------------------------
local _editLocks = setmetatable({}, { __mode = "k" })

local function UpdateEditLocks()
    local specOn = _editGroup ~= nil
    for _, host in pairs(_editLocks) do
        -- A lock whose region the options page pool reset belongs to no row until
        -- the region is locked again (AttachEditLock): it stays hidden.
        if host._inactive then
            -- nothing
        -- Predicate locks decide their own visibility per session (e.g. the
        -- Dark Mode condition locks); plain locks show for any spec session.
        elseif host._predicate then
            host:SetShown(host._predicate() and true or false)
        else
            host:SetShown(specOn)
        end
    end
end

-- AttachEditLock predicate for widgets writing the dark-mode CONDITION's input
-- flags (UF darkTheme, RF healthColorMode: the Colors page's Dark Mode rows; the
-- Class Resource Bar row is NOT an input -- DarkModeMasterOn excludes it). True when
--   (a) the editing-as session is a CONDITIONAL group with the Dark Mode
--       condition: capturing a dark flag into it lets the override flip its own
--       activation condition (apply -> false -> restore -> true -> ...); or
--   (b) ANY conditional session is active AND a Dark Mode group exists: a dark
--       flag captured into a dungeon/keybind/solo group fights the Dark Mode
--       group through the resolution ladder (same oscillation, two groups).
-- Spec-group sessions never lock these: spec activation does not read dark
-- state, so a spec-captured dark flag settles in one apply.
function EllesmereUI.SpecOverrides_DarkCondEditActive()
    local g = Cond and Cond._edit
    if not g then return false end
    if g.conds and g.conds.darkmode then return true end
    local groups = EllesmereUI.Conditions_GetGroups and EllesmereUI.Conditions_GetGroups()
    if groups then
        for _, og in ipairs(groups) do
            if og.conds and og.conds.darkmode then return true end
        end
    end
    return false
end

function EllesmereUI.SpecOverrides_AttachEditLock(region, tip, predicate)
    if not region then return end
    local host = _editLocks[region]
    if not host then
        host = MakeBorderHost(region, 0.9, 0.2, 0.2)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(region:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local tint = blocker:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.9, 0.2, 0.2, 0.05)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            EllesmereUI.HideWidgetTooltip()
        end)
        host._blocker = blocker
        _editLocks[region] = host
        -- On a region of the options page pool the lock rides on it: the region's
        -- reset hides it and leaves it inactive until the region is locked again.
        local Pool = EllesmereUI._Pool
        if Pool and Pool.Gen and Pool.Gen(region) then
            Pool.Attach(region, host, nil, function(h)
                h._inactive = true
                h:Hide()
            end)
        end
    end
    if host._inactive then
        -- back on its region's new dress: at the region's new level
        host._inactive = nil
        host:SetFrameLevel(region:GetFrameLevel() + 30)
        host._blocker:SetFrameLevel(region:GetFrameLevel() + 45)
    end
    host._blocker._tipText = tip
    host._predicate = predicate
    if predicate then
        host:SetShown(predicate() and true or false)
    else
        host:SetShown(_editGroup ~= nil)
    end
end

-- "Overridden by: ..." tooltip for a gold slot, from the slot's traced fkeys:
-- every spec group with a member spec HOLDING a value on any of them (a spec in
-- several groups lists each -- the management list buckets the same way), held
-- values on ungrouped specs by spec name (legacy / stranded values still apply),
-- the creating group when nothing holds a value yet (a fresh session capture banks
-- at exit), and every conditional group holding a value. Holding, not differing:
-- a member value equal to the current default still pins that spec, which is
-- exactly what a base editor needs to know. Outside a session a second line says
-- what a base edit does. nil when no override names resolve.
local _tipNames = {}   -- array part = names in order; hash part = dedupe set
local function AddTipName(name)
    if name and not _tipNames[name] then
        _tipNames[name] = true
        _tipNames[#_tipNames + 1] = name
    end
end
local function SlotTipFor(sink)
    wipe(_tipNames)
    local groups = GetGroups()
    for fkey in pairs(sink) do
        local e = EntryOwning(fkey)
        if e and e.values then
            local held = false
            for k, m in pairs(e.values) do
                if type(k) == "number" and type(m) == "table" and m[fkey] ~= nil then
                    held = true
                    local grouped = false
                    for _, g in ipairs(groups or {}) do
                        for _, sid in ipairs(g.specs or {}) do
                            if sid == k then
                                AddTipName(g.name or "?")
                                grouped = true
                                break
                            end
                        end
                    end
                    if not grouped then AddTipName(SpecName(k)) end
                end
            end
            if not held and e.group then
                local g = GroupById(e.group)
                if g then AddTipName(g.name or "?") end
            end
        end
        local ce = Cond.EntryOwning(fkey)
        if ce and ce.values then
            -- A spec override on the same fkey evicts the conditional at runtime
            -- (Cond.WriteValues skips spec-owned fkeys outside a session); say so
            -- with the same "held by" wording the Overrides list row uses.
            local heldBy
            if e and e.group then
                local og = GroupById(e.group)
                heldBy = og and og.name
            end
            for k, m in pairs(ce.values) do
                if type(k) == "number" and type(m) == "table" and m[fkey] ~= nil then
                    local cg = EllesmereUI.Conditions_GroupById
                        and EllesmereUI.Conditions_GroupById(k)
                    if cg then
                        local tag = L("conditional")
                        if heldBy then
                            tag = tag .. ", " .. string.format(L("held by '%s'"), heldBy)
                        end
                        AddTipName((cg.name or "?") .. " |cff909090(" .. tag .. ")|r")
                    end
                end
            end
        end
    end
    if #_tipNames == 0 then return nil end
    local s = "|cffc7a65a" .. L("Overridden by:") .. "|r " .. table.concat(_tipNames, ", ")
    if not _editGroup and not Cond._edit then
        s = s .. "\n|cff909090"
            .. L("Changes here edit the shared default; overrides keep their own values.")
            .. "|r"
    end
    return s
end

local function GoldWalk(frame, forceOff, condGid, condName)
    local cfg = frame._captureCfg
    if cfg and not cfg.noCapture and not forceOff then
        local entry, condActive
        local sink = TraceSlot(cfg)
        for fkey in pairs(sink) do
            -- Applied-conditional context (no session): a slot whose fkey the
            -- LIVE conditional banks a value for shows that override's value
            -- right now -- labeled overlay instead of plain gold.
            if condGid and not condActive then
                local ce = Cond.EntryOwning(fkey)
                local m = ce and ce.values and ce.values[condGid]
                if m and m[fkey] ~= nil then condActive = true end
            end
            if not entry then
                entry = EntryOwning(fkey) or Cond.EntryOwning(fkey)
            end
            if entry and (condActive or not condGid) then break end
        end
        if condActive then
            SetSlotMark(frame, "condActive", nil, condName)
        elseif entry then
            local conflict = ConflictSpec(entry)
            if conflict then
                SetSlotMark(frame, "red", conflict)
            else
                SetSlotMark(frame, "gold", nil, nil, SlotTipFor(sink))
            end
        else
            SetSlotMark(frame, false)
        end
    else
        if frame._specOvGold then frame._specOvGold:Hide() end
        if frame._specOvRed then frame._specOvRed:Hide() end
        if frame._specOvCondActive then frame._specOvCondActive:Hide() end
        if frame._specOvHover then
            frame._specOvTip = nil
            frame._specOvHover:Hide()
        end
    end
    -- Only what is on screen: a hidden cached page is walked again when it
    -- shows (every page select requests a walk), and its getters never run
    -- under the trace meanwhile (another module's page may be excluded).
    local kids = { frame:GetChildren() }
    for i = 1, #kids do
        local kid = kids[i]
        if kid:IsShown() then GoldWalk(kid, forceOff, condGid, condName) end
    end
end

local _goldWalkQueued = false
RequestGoldWalk = function()
    if _goldWalkQueued then return end
    _goldWalkQueued = true
    C_Timer.After(0, function()
        _goldWalkQueued = false
        local root = _G.EllesmereUIFrame
        if not (root and root:IsShown()) then return end
        -- Excluded contexts never show slot marks (walk still clears stale ones)
        if IsExcludedContext() then
            GoldWalk(root, true)
            return
        end
        if BeginTrace() then
            -- Applied-conditional context for the walk: only outside every
            -- session (a session view shows session values, not the overlay).
            local condGid, condName
            if not _editGroup and not Cond._edit then
                condGid = EllesmereUI.Conditions_AppliedGid
                    and EllesmereUI.Conditions_AppliedGid() or nil
                local g = condGid and EllesmereUI.Conditions_GroupById
                    and EllesmereUI.Conditions_GroupById(condGid) or nil
                if g then condName = g.name else condGid = nil end
            end
            -- pcall is LOAD-BEARING: while the trace is active every db.profile
            -- in the Lite registry is a read-tracking PROXY that iterates EMPTY
            -- under pairs/next. An error escaping GoldWalk would skip EndTrace,
            -- strand the proxies for the session, and the next snapshot/logout
            -- write-back would PERSIST empty module profiles (total settings
            -- wipe). EndTrace must run on every path.
            local ok, err = pcall(GoldWalk, root, nil, condGid, condName)
            EndTrace()
            if not ok and err then geterrorhandler()(err) end
        end
    end)
end
SetRequestGoldWalk(RequestGoldWalk)

I.CurrentContext, I.DiffProfiles = CurrentContext, DiffProfiles
I.IsExcludedContext, I.RequestGoldWalk = IsExcludedContext, RequestGoldWalk
I.SnapshotProfiles, I.UpdateEditLocks = SnapshotProfiles, UpdateEditLocks
I.broken = false
