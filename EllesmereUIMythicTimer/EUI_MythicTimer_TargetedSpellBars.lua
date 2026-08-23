if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_TargetedSpellBars.lua
--  Targeted Spell Bars (Mythic+ Tools): one movable group of plain cast bars,
--  one per enemy nameplate currently casting -- a replica of the nameplate
--  cast display (spell name, spell target, timer) collected in one place so
--  every active cast reads at a glance.
--
--  Zero cost while disabled: no events are registered and no frames are built
--  until the feature is enabled. All cast reads follow the nameplate module's
--  secret discipline: type() existence checks, duration objects into
--  SetTimerDuration, secret strings straight into SetText, never a Lua branch
--  on a secret value.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local db  -- Lite DB handle, handed over by ns.TSB_OnEnable

local function Cfg()
    local p = db and db.profile
    return p and p.tsb
end

--------------------------------------------------------------------------------
--  Fonts: module-wide family/outline/shadow (surface key "mythicTimer"), only
--  per-text sizes are settings -- same contract as every other bar surface.
--------------------------------------------------------------------------------
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function SetFSFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("mythicTimer")) or FONT_FALLBACK
    local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("mythicTimer")) or ""
    local useShadow = EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("mythicTimer")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, useShadow) end
    fs:SetFont(path, size, outline)
end

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local container            -- anchor frame the unlock mover drags; built lazily
local bars = {}            -- frame pool (holder frames, reused forever)
local shown = {}           -- active entries in display order
local unitEntry = {}       -- unit token -> entry while its bar is shown
local plateUnits = {}      -- unit token -> true while its nameplate exists
local active = false       -- events registered / feature live
local previewOn = false    -- sample bars forced on (options eyeball / unlock)
local timerTicker          -- shared 10Hz text ticker, self-stops when idle

local DEFAULT_X, DEFAULT_Y = -340, 60

--------------------------------------------------------------------------------
--  Container + position (unlock interchange = raw UIParent-logical center
--  delta, same contract as the timer frame -- scale division never leaves the
--  module's own SetPoint).
--------------------------------------------------------------------------------
local function ApplyContainerPosition()
    if not container then return end
    local cfg = Cfg()
    local pos = cfg and cfg.pos
    container:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        container:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    end
end

local function EnsureContainer()
    if container then return container end
    container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(240, 20)
    ApplyContainerPosition()
    return container
end

--------------------------------------------------------------------------------
--  Bar construction: holder > bg + icon + StatusBar fill + text zones.
--  Built once per pool slot, restyled by ApplyStyle.
--------------------------------------------------------------------------------
local function BuildBar()
    local holder = CreateFrame("Frame", nil, EnsureContainer())
    holder:Hide()

    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints(holder)

    holder.iconFrame = CreateFrame("Frame", nil, holder)
    holder.iconFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    holder.iconFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints(holder.iconFrame)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    holder.sb = CreateFrame("StatusBar", nil, holder)
    holder.sb:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 0, 0)
    holder.sb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    holder.sb:SetMinMaxValues(0, 1)
    holder.sb:SetValue(0)

    -- Text zones ride a child frame so they draw above the fill and any border.
    holder.textFrame = CreateFrame("Frame", nil, holder.sb)
    holder.textFrame:SetAllPoints(holder.sb)
    -- Fonts applied at BUILD as well as in StyleBar: SetText on a fontless
    -- FontString errors, and build/paint ordering must not be load-bearing.
    holder.name = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.name:SetJustifyH("LEFT")
    holder.name:SetWordWrap(false)
    holder.name:SetMaxLines(1)
    SetFSFont(holder.name, 10)
    holder.target = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.target:SetJustifyH("RIGHT")
    holder.target:SetWordWrap(false)
    holder.target:SetMaxLines(1)
    SetFSFont(holder.target, 10)
    holder.timer = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.timer:SetJustifyH("RIGHT")
    holder.timer:SetWordWrap(false)
    holder.timer:SetMaxLines(1)
    SetFSFont(holder.timer, 10)

    return holder
end

local function AcquireBarFrame()
    for i = 1, #bars do
        if not bars[i]._tsbInUse then
            bars[i]._tsbInUse = true
            return bars[i]
        end
    end
    local b = BuildBar()
    bars[#bars + 1] = b
    b._tsbInUse = true
    return b
end

--------------------------------------------------------------------------------
--  Style pass: sizes, texture, colors, fonts, text layout. Runs on enable and
--  on any settings change (options call ns.TSB_Refresh). Cheap: <= pool size.
--------------------------------------------------------------------------------
local function StyleBar(holder, cfg)
    local w = cfg.width or 240
    local h = cfg.height or 20
    holder:SetSize(w, h)

    local bg = cfg.bgColor
    if bg then holder.bg:SetColorTexture(bg.r, bg.g, bg.b, bg.a or 0.45)
    else holder.bg:SetColorTexture(0, 0, 0, 0.45) end

    local showIcon = cfg.showIcon ~= false
    holder.iconFrame:SetWidth(showIcon and h or 0.001)
    holder.iconFrame:SetShown(showIcon)

    local texPath = EllesmereUI.ResolveTexturePath
        and EllesmereUI.ResolveTexturePath(ns.barTextures, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
        or "Interface\\Buttons\\WHITE8x8"
    holder.sb:SetStatusBarTexture(texPath)
    local pp = EllesmereUI.PP
    if pp and pp.DisablePixelSnap then pp.DisablePixelSnap(holder.sb:GetStatusBarTexture()) end
    local c = cfg.barColor
    if c then holder.sb:SetStatusBarColor(c.r, c.g, c.b) end

    -- Solid black border on the holder; size 0 removes it.
    local bsz = cfg.borderSize
    if bsz == nil then bsz = 1 end
    if pp and pp.CreateBorder then
        if bsz > 0 then
            if not holder._tsbBorder then
                holder._tsbBorder = true
                pp.CreateBorder(holder, 0, 0, 0, 1, bsz, "OVERLAY", 7)
            elseif pp.UpdateBorder then
                pp.UpdateBorder(holder, bsz)
            end
            if pp.ShowBorder then pp.ShowBorder(holder) end
        elseif holder._tsbBorder and pp.HideBorder then
            pp.HideBorder(holder)
        end
    end

    SetFSFont(holder.name, cfg.nameSize or 10)
    SetFSFont(holder.target, cfg.targetSize or 10)
    SetFSFont(holder.timer, cfg.timerSize or 10)

    local showTimer = cfg.showTimer ~= false
    local timerReserve = showTimer and ((cfg.timerSize or 10) * 2.2) or 0
    holder.name:ClearAllPoints()
    holder.name:SetPoint("LEFT", holder.sb, "LEFT", 4 + (cfg.nameX or 0), cfg.nameY or 0)
    holder.name:SetWidth((w - h) * 0.48)
    holder.timer:ClearAllPoints()
    holder.timer:SetPoint("RIGHT", holder.sb, "RIGHT", -3 + (cfg.timerX or 0), cfg.timerY or 0)
    holder.target:ClearAllPoints()
    holder.target:SetPoint("RIGHT", holder.sb, "RIGHT",
        -3 - timerReserve + (cfg.targetX or 0), cfg.targetY or 0)
    holder.target:SetWidth((w - h) * 0.40)

    holder.name:SetShown(cfg.showSpellName ~= false)
    holder.timer:SetShown(showTimer)
    -- target visibility is per-cast (hasTarget); the paint pass owns it
end

local function PositionBar(holder, slot, cfg)
    holder:ClearAllPoints()
    local off = (slot - 1) * ((cfg.height or 20) + (cfg.spacing or 4))
    if cfg.growUp then
        holder:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, off)
    else
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -off)
    end
end

local function Reflow()
    local cfg = Cfg()
    if not cfg then return end
    for i = 1, #shown do
        PositionBar(shown[i].bar, i, cfg)
    end
end

--------------------------------------------------------------------------------
--  Shared 10Hz timer text: one ticker for the whole group, armed while any
--  bar is live, self-stops when the last releases (engine sleeps between
--  fires). Remaining time comes from the duration object -- cast start/end
--  times are secret and unusable in arithmetic.
--------------------------------------------------------------------------------
local function TimerBody()
    local n = #shown
    if n == 0 then return false end
    if not UnitCastingDuration then return false end
    for i = 1, n do
        local e = shown[i]
        if not e.preview then
            local fs = e.bar.timer
            local durObj = UnitCastingDuration(e.unit)
                or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(e.unit, true))
                or (UnitChannelDuration and UnitChannelDuration(e.unit))
            if durObj then
                fs:SetFormattedText("%.1f", durObj:GetRemainingDuration())
            else
                fs:SetText("")
            end
        end
    end
    return true
end

local function ArmTimerTicker()
    if not timerTicker and EllesmereUI.Tick and EllesmereUI.Tick.NewAnimTicker then
        timerTicker = EllesmereUI.Tick.NewAnimTicker(EnsureContainer(), TimerBody, 0.1)
    end
    if timerTicker then
        TimerBody()
        timerTicker.Start()
    end
end

--------------------------------------------------------------------------------
--  Cast lifecycle
--------------------------------------------------------------------------------
local function ArmFill(e, isChannel)
    local sb = e.bar.sb
    if not (UnitCastingDuration and sb.SetTimerDuration) then return end
    local dur, isEmp
    if isChannel then
        if UnitEmpoweredChannelDuration then
            dur = UnitEmpoweredChannelDuration(e.unit, true)
            if dur then isEmp = true end
        end
        if not dur then dur = UnitChannelDuration(e.unit) end
        if dur then
            sb:SetReverseFill(false)
            -- Empowered channels build forward; normal channels drain.
            local dirn = isEmp and Enum.StatusBarTimerDirection.ElapsedTime
                or Enum.StatusBarTimerDirection.RemainingTime
            sb:SetTimerDuration(dur, nil, dirn)
        end
    else
        dur = UnitCastingDuration(e.unit)
        if dur then
            sb:SetReverseFill(false)
            sb:SetTimerDuration(dur, nil, Enum.StatusBarTimerDirection.ElapsedTime)
        end
    end
end

local function PaintTarget(e, cfg)
    local fs = e.bar.target
    if cfg.showTarget == false then
        fs:SetText("")
        fs:Hide()
        return
    end
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(e.unit) then
        -- Names may be SECRET: type() is the safe existence check, and
        -- SetText accepts secret strings without exposing them to Lua.
        local raw = UnitSpellTargetName and UnitSpellTargetName(e.unit)
        if type(raw) ~= "nil" then
            spellTarget = raw
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(e.unit)
        end
    end
    if type(spellTarget) == "nil" then
        fs:SetText("")
        fs:Hide()
        return
    end
    if cfg.targetClassColor ~= false and type(spellTargetClass) ~= "nil" and C_ClassColor then
        local col = C_ClassColor.GetClassColor(spellTargetClass)
        if col then fs:SetTextColor(col:GetRGB()) else fs:SetTextColor(1, 1, 1, 1) end
    else
        local tc = cfg.targetColor
        if tc then fs:SetTextColor(tc.r, tc.g, tc.b, 1) else fs:SetTextColor(1, 1, 1, 1) end
    end
    fs:SetText(spellTarget)
    fs:Show()
end

local function Release(unit)
    local e = unitEntry[unit]
    if not e then return end
    unitEntry[unit] = nil
    for i = 1, #shown do
        if shown[i] == e then
            table.remove(shown, i)
            break
        end
    end
    e.bar._tsbInUse = nil
    e.bar:Hide()
    Reflow()
end

-- Only CLEANLY-friendly plates are excluded (friendly NPC nameplates). The
-- attackable flag can be SECRET in instanced combat; a secret answer fail-
-- OPENS (the cast shows) rather than ever branching on the secret.
local function IsTrackableUnit(unit)
    local ok, att = pcall(UnitCanAttack, "player", unit)
    if ok and not (issecretvalue and issecretvalue(att)) and att == false then
        return false
    end
    return true
end

local PromoteWaiting -- forward: StartCast <-> PromoteWaiting recursion

local function StartCast(unit)
    local cfg = Cfg()
    if not cfg then return end
    local name, _, texture, _, _, _, _, _, castSpellID = UnitCastingInfo(unit)
    local isChannel = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, _, castSpellID = UnitChannelInfo(unit)
        isChannel = true
    end
    if type(name) == "nil" then
        Release(unit)
        if PromoteWaiting then PromoteWaiting() end
        return
    end
    if not IsTrackableUnit(unit) then return end

    local e = unitEntry[unit]
    if not e then
        if #shown >= (cfg.maxBars or 5) then return end -- promoted when a slot frees
        e = { unit = unit, bar = AcquireBarFrame() }
        unitEntry[unit] = e
        shown[#shown + 1] = e
        StyleBar(e.bar, cfg)
        PositionBar(e.bar, #shown, cfg)
    end
    e.isChannel = isChannel
    e.preview = nil

    -- Icon and name MUST describe the SAME cast: both come from this
    -- snapshot. The live texture may be SECRET -- SetTexture accepts it.
    if cfg.showIcon ~= false then
        if type(texture) ~= "nil" then
            e.bar.icon:SetTexture(texture)
        elseif type(castSpellID) ~= "nil" then
            local okInfo, info = pcall(C_Spell.GetSpellInfo, castSpellID)
            if okInfo and type(info) == "table" then
                e.bar.icon:SetTexture(info.iconID)
            else
                e.bar.icon:SetTexture(nil)
            end
        else
            e.bar.icon:SetTexture(nil)
        end
    end
    if cfg.showSpellName ~= false then
        e.bar.name:SetText(name)
    end
    PaintTarget(e, cfg)
    e.bar.timer:SetText("")
    ArmFill(e, isChannel)
    e.bar:Show()
    ArmTimerTicker()
end

-- Fill freed slots from plates that were casting while the group was full.
-- Bounded: runs only on release-while-full, over the live plate set.
PromoteWaiting = function()
    local cfg = Cfg()
    if not cfg then return end
    if #shown >= (cfg.maxBars or 5) then return end
    for unit in pairs(plateUnits) do
        if not unitEntry[unit] then
            local nm = UnitCastingInfo(unit)
            if type(nm) == "nil" then nm = UnitChannelInfo(unit) end
            if type(nm) ~= "nil" then
                StartCast(unit)
                if #shown >= (cfg.maxBars or 5) then return end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Events: registered ONLY while enabled. One frame; unit filtering is the
--  plateUnits hash (nameplate tokens only -- party/raid cast chatter costs
--  one failed lookup).
--------------------------------------------------------------------------------
local evt = CreateFrame("Frame")

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local UPDATE_EVENTS = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}
local PROBE_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
}
-- These release directly instead of re-probing: in restricted execution the
-- cast-info reads can return secret values (not nil) for a stale channel or
-- empowered cast, making a probe think it is still active (nameplate lesson).
local RELEASE_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

evt:SetScript("OnEvent", function(_, event, unit)
    if previewOn then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        if unit then
            plateUnits[unit] = true
            -- Probe the delta: only this plate, only if it is mid-cast.
            local nm = UnitCastingInfo(unit)
            if type(nm) == "nil" then nm = UnitChannelInfo(unit) end
            if type(nm) ~= "nil" then StartCast(unit) end
        end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if unit then
            plateUnits[unit] = nil
            Release(unit)
            PromoteWaiting()
        end
        return
    end
    -- Spellcast family: nameplate units only.
    if not unit or not plateUnits[unit] then return end
    if START_EVENTS[event] then
        StartCast(unit)
    elseif UPDATE_EVENTS[event] then
        local e = unitEntry[unit]
        if e then ArmFill(e, e.isChannel) end
    elseif PROBE_EVENTS[event] then
        if unitEntry[unit] then StartCast(unit) end
    elseif RELEASE_EVENTS[event] then
        Release(unit)
        PromoteWaiting()
    end
end)

local ALL_EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
}

local function ReleaseAll()
    for i = #shown, 1, -1 do
        local e = shown[i]
        unitEntry[e.unit] = nil
        e.bar._tsbInUse = nil
        e.bar:Hide()
        shown[i] = nil
    end
end

-- Seed from plates that already exist (mid-session enable).
local function SeedFromLivePlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for i = 1, #plates do
        local unit = plates[i] and plates[i].namePlateUnitToken
        if unit then
            plateUnits[unit] = true
            local nm = UnitCastingInfo(unit)
            if type(nm) == "nil" then nm = UnitChannelInfo(unit) end
            if type(nm) ~= "nil" then StartCast(unit) end
        end
    end
end

local function Activate()
    if active then return end
    active = true
    EnsureContainer()
    for i = 1, #ALL_EVENTS do evt:RegisterEvent(ALL_EVENTS[i]) end
    SeedFromLivePlates()
end

local function Deactivate()
    if not active then return end
    active = false
    evt:UnregisterAllEvents()
    ReleaseAll()
    wipe(plateUnits)
end

--------------------------------------------------------------------------------
--  Preview: sample bars for options / unlock placement. Static content --
--  plain SetValue (cancels timer mode) so nothing animates or reads units.
--------------------------------------------------------------------------------
local PREVIEW_ROWS = {
    { name = "Shadow Bolt",   fill = 0.65, timer = "1.2" },
    { name = "Mending",       fill = 0.35, timer = "2.4" },
    { name = "Terrifying Roar", fill = 0.85, timer = "0.6" },
}

local function ShowPreview()
    local cfg = Cfg()
    if not cfg then return end
    ReleaseAll()
    EnsureContainer()
    local rows = math.min(#PREVIEW_ROWS, cfg.maxBars or 5)
    for i = 1, rows do
        local sample = PREVIEW_ROWS[i]
        local e = { unit = "preview" .. i, bar = AcquireBarFrame(), preview = true }
        shown[#shown + 1] = e
        StyleBar(e.bar, cfg)
        PositionBar(e.bar, i, cfg)
        e.bar.icon:SetTexture(134400)
        if cfg.showSpellName ~= false then e.bar.name:SetText(sample.name) end
        if cfg.showTarget ~= false then
            local tc = cfg.targetColor
            if cfg.targetClassColor ~= false and C_ClassColor and UnitClassBase then
                local col = C_ClassColor.GetClassColor(UnitClassBase("player"))
                if col then e.bar.target:SetTextColor(col:GetRGB()) end
            elseif tc then
                e.bar.target:SetTextColor(tc.r, tc.g, tc.b, 1)
            end
            e.bar.target:SetText(UnitName("player") or "Target")
            e.bar.target:Show()
        else
            e.bar.target:SetText("")
            e.bar.target:Hide()
        end
        e.bar.timer:SetText(cfg.showTimer ~= false and sample.timer or "")
        e.bar.sb:SetValue(sample.fill)
        e.bar:Show()
    end
end

function ns.TSB_SetPreview(on)
    previewOn = on == true
    if previewOn then
        ShowPreview()
    else
        ReleaseAll()
        if active then SeedFromLivePlates() end
    end
end

function ns.TSB_IsPreview()
    return previewOn
end

--------------------------------------------------------------------------------
--  Refresh: the one entry point for enable/disable + live restyle. Options
--  call this after every settings write.
--------------------------------------------------------------------------------
function ns.TSB_Refresh()
    local cfg = Cfg()
    local want = cfg and cfg.enabled == true
    if want and not active then
        Activate()
    elseif not want and active then
        Deactivate()
        previewOn = false
    end
    if not cfg then return end
    if container then
        container:SetSize(cfg.width or 240, cfg.height or 20)
        ApplyContainerPosition()
    end
    if previewOn then
        ShowPreview()
        return
    end
    -- Restyle live bars in place; trim overflow if Max Bars shrank.
    local maxBars = cfg.maxBars or 5
    for i = #shown, maxBars + 1, -1 do
        local e = shown[i]
        unitEntry[e.unit] = nil
        e.bar._tsbInUse = nil
        e.bar:Hide()
        shown[i] = nil
    end
    for i = 1, #shown do
        StyleBar(shown[i].bar, cfg)
        PositionBar(shown[i].bar, i, cfg)
    end
end

--------------------------------------------------------------------------------
--  Unlock mode: one group element. Registered once at init (a stored table);
--  the mover is hidden while the feature is disabled.
--------------------------------------------------------------------------------
local function RegisterUnlock()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EMT_TargetedSpellBars",
            label = "Targeted Spell Bars",
            group = "Mythic+",
            order = 521,
            -- Sized by the options sliders (no drag-resize handle), but the
            -- group can size-MATCH another element and be matched TO: the match
            -- apply pushes through setWidth/setHeight into the same cfg keys
            -- the sliders write (per-bar size; the container relayouts).
            noResize = true,
            allowMatchSource = true,
            isHidden = function()
                local cfg = Cfg()
                return not (cfg and cfg.enabled == true)
            end,
            getFrame = function()
                return EnsureContainer()
            end,
            getSize = function()
                local cfg = Cfg()
                return (cfg and cfg.width) or 240, (cfg and cfg.height) or 20
            end,
            setWidth = function(_, w)
                local cfg = Cfg()
                if not cfg then return end
                cfg.width = math.floor(w + 0.5)
                ns.TSB_Refresh()
            end,
            setHeight = function(_, h)
                local cfg = Cfg()
                if not cfg then return end
                cfg.height = math.floor(h + 0.5)
                ns.TSB_Refresh()
            end,
            savePos = function()
                local cfg = Cfg()
                local f = container
                if not (cfg and f and f:GetCenter()) then return end
                -- Raw UIParent-logical center delta; the effective-scale ratio
                -- normalizes GetCenter's frame-scaled units (timer lesson:
                -- scale division must never live in the interchange format).
                local cx, cy = f:GetCenter()
                local upX, upY = UIParent:GetCenter()
                local fes = f:GetEffectiveScale() or 1
                local ues = UIParent:GetEffectiveScale() or 1
                local ratio = fes / ues
                cfg.pos = { centerX = cx * ratio - upX, centerY = cy * ratio - upY }
                if not (EllesmereUI._unlockActive) then ApplyContainerPosition() end
            end,
            loadPos = function()
                local cfg = Cfg()
                local pos = cfg and cfg.pos
                if not (pos and pos.centerX and pos.centerY) then return nil end
                return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
            end,
            clearPos = function()
                local cfg = Cfg()
                if cfg then cfg.pos = nil end
            end,
            applyPos = function()
                ApplyContainerPosition()
            end,
        }),
    }, "EllesmereUIMythicTimer")

    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EMT_TargetedSpellBars", function(unlockActive)
            local cfg = Cfg()
            if not (cfg and cfg.enabled == true) then return end
            -- Sample bars while placing; back to live content on exit.
            ns.TSB_SetPreview(unlockActive == true)
            local anchored = EllesmereUI.IsUnlockAnchored
                and EllesmereUI.IsUnlockAnchored("EMT_TargetedSpellBars")
            if not anchored then ApplyContainerPosition() end
        end)
    end
end

--------------------------------------------------------------------------------
--  Init: called from EMT:OnEnable (before the timer's own enable guard).
--------------------------------------------------------------------------------
function ns.TSB_OnEnable(database)
    db = database
    if not db then return end
    RegisterUnlock()
    ns.TSB_Refresh()
end
