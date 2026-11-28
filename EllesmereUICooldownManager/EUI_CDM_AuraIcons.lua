if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_AuraIcons.lua
--
--  Aura icons of our own on cooldown and utility bars, for entries no
--  Blizzard frame draws. Each is an icon frame of ours, built once per bar and
--  entry and laid out, decorated, reparented and parked like a racial's (an
--  injected frame, _isPresetFrame), with one engine aura slot (AuraKit) inside
--  it: the slot shows while a matching aura is up, with the aura's own icon,
--  swipe and countdown in the bar's custom-aura look (_AC.BuildStyle), so it
--  works while aura data is hidden from addon code. Under it the frame shows
--  the entry's idle icon.
--
--  The entry: a custom buff spell ID on a cooldown or utility bar (the Add
--  Buff menu's Custom Spell ID, stored as a hosted-buff marker), drawn here
--  while no Blizzard frame or placeholder claims it, its idle icon grey, as a
--  hosted buff keeps its slot on such a bar.
--
--  One slot per entry, moved between bars through its proxy: a frame of ours
--  the slot button fills, parented to the host frame, so the slot takes the
--  host's visibility, opacity and strata, and a hidden host hides the
--  container, which then registers no events. The slot is built again only
--  when its include set changes (engine buttons are never freed).
--
--  Also the kept slots of buff bars (see "Kept slots" below): a custom buff
--  spell ID on a buff bar that keeps every slot takes its place in the bar's
--  order, with a slot of its own drawn over a placeholder.
--
--  Reached from: EUI_CDM_HookReanchor.lua (Phase 3 injection, the buff bar
--  injection, and the end of every reanchor), EUI_CDM_Icons.lua
--  (RefreshCDMIconAppearance) and ns._AuraCustomPoke (bar layout, opacity and
--  visibility).
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
if not I or I.broken or not I._AC then return end
local _AC, _presetFrames = I._AC, I._presetFrames
local GetOrCreatePlaceholderFrame = I.GetOrCreatePlaceholderFrame
local ResolveSpellSettings = I.ResolveSpellSettings
local barDataByKey = ns.barDataByKey
local cdmBarFrames = ns.cdmBarFrames
local IsSecret = EllesmereUI.IsSecret

local AKWorker = EllesmereUI.AuraKit.NewBuildWorker()

-- The slot sits over the host's art, border and swipe (border +13/+14, swipe
-- +14), under its glows (+16) and text (+23), as DecorateFrame levels them.
local SLOT_LEVEL = 14

local entries = {}         -- provider key -> entry
local placed = {}          -- entries attached since the last post-reanchor pass
local buffProviders = {}   -- custom buff spell ID -> its provider
-- host frame -> the entry it holds (one frame per bar and entry)
local hostEntry = setmetatable({}, { __mode = "k" })
-- Kept slots on buff bars: every entry (entry -> true), and barKey -> spell
-- ID -> entry
local kept, keptByBar = {}, {}

-------------------------------------------------------------------------------
--  Providers (BuffProvider below)
--
--  provider = {
--    key,           unique entry key
--    tip,           the spell ID the idle frame's tooltip shows
--    Include(),     -> the aura spell IDs (a set, never empty) and a signature
--    Icon(),        -> the idle art
--    Desaturate(),  -> whether the idle art is grey
--  }
-------------------------------------------------------------------------------
--  The engine slot
-------------------------------------------------------------------------------
-- A learned spell can widen an include set (a WoW Forever rank) and a talent
-- change can move a spell's override: each set is read again at its next
-- placement. Registered only while an entry is placed.
local listening = false
local events = ns.TakeShell()
events:SetScript("OnEvent", function()
    for _, E in pairs(entries) do E.dirty = true end
    for E in pairs(kept) do E.dirty = true end
    if ns.QueueReanchor then ns.QueueReanchor() end
end)

local function Listen(on)
    if on == listening then return end
    listening = on
    if on then
        events:RegisterEvent("TRAIT_CONFIG_UPDATED")
        if EllesmereUI.IS_FOREVER == true then
            events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
        end
    else
        events:UnregisterAllEvents()
    end
end

local function Entry(provider)
    local E = entries[provider.key]
    if E then return E end
    E = { provider = provider, styleKey = "cdm:auraicon:" .. provider.key }
    local proxy = CreateFrame("Frame", nil, UIParent)
    proxy:Hide()
    proxy:EnableMouse(false)
    E.proxy = proxy
    -- Creation window: the CDM look's own regions, then the button fills the
    -- proxy (two-point anchors size it by the proxy for good).
    E.init = function(button, d)
        _AC.InitExtra(button, d)
        button:SetAllPoints(proxy)
    end
    entries[provider.key] = E
    return E
end

-- The host's laid-out size. The bar layout sizes every icon itself (Width or
-- Height Match, the per-row size offset, the spare pixels it spreads), and
-- AuraKit sizes the slot's border host from the style, not from the button,
-- so the look is cut for the host rather than for the bar's Icon Size. nil
-- before the first layout (the bar's Icon Size stands in).
local function HostSize(E)
    local host = E.host
    if not host then return nil end
    local w, h = host:GetSize()
    if type(w) ~= "number" or type(h) ~= "number" or IsSecret(w) or IsSecret(h)
       or w <= 0 or h <= 0 then
        return nil
    end
    return w, h
end

-- The slot's look: the bar's custom-aura look, cut for the host's size. E.ci:
-- a kept slot's Custom Icon (a file ID), drawn in place of the aura's icon.
local function HostStyle(E, bd)
    local style = _AC.BuildStyle(bd, E.ci)
    local w, h = HostSize(E)
    if w then
        style.width, style.height = w, h
        if style.cdm then style.cdm.size = w end
    end
    return style
end

-- The look's fingerprint: the bar settings a restyle carries, and the size
-- the look's own regions are cut for.
local function StyleSig(E, bd)
    local w, h = HostSize(E)
    return _AC.StyleSig(bd) .. "|" .. tostring(bd.iconSize or 36) .. "|"
        .. tostring(w) .. "x" .. tostring(h)
        .. (E.ci and ("|ci" .. E.ci) or "")
end

local function Restyle(E, barKey)
    local bd = barDataByKey[barKey]
    if not bd then return end
    local sig = StyleSig(E, bd)
    if E.styleBar == barKey and E.styleSig == sig then return end
    local AK = EllesmereUI.AuraKit
    AK.styles[E.styleKey] = HostStyle(E, bd)
    E.styleBar, E.styleSig = barKey, sig
    if AK.RestyleSoon then AK.RestyleSoon(E.styleKey) end
end

-- Levels follow the host: DecorateFrame levels its regions off the frame's
-- own level, which the reanchor's reparent moves.
local function Level(E)
    local host, container = E.host, E.container
    if not (host and container) then return end
    local lvl = host:GetFrameLevel() + SLOT_LEVEL
    if E.level == lvl then return end
    E.level = lvl
    E.proxy:SetFrameLevel(lvl)
    container:SetFrameLevel(lvl + 1)
end

local function Build(E, include, sig)
    local bd = E.hostBar and barDataByKey[E.hostBar]
    if not bd then return end
    local AK = EllesmereUI.AuraKit
    AK.styles[E.styleKey] = HostStyle(E, bd)
    E.styleBar, E.styleSig = E.hostBar, StyleSig(E, bd)
    if E.container then AK.ReleaseContainer(E.container) end
    local container = AK.CreateContainerShell(E.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(container, {
        key = "aura",
        filter = { "HELPFUL" },
        -- Helpful spell id includes on the player pass the identity gate
        -- whatever the spell's secrecy flag.
        candidateFilters = { includeSpellIDs = include },
        style = E.styleKey,
        extraInit = E.init,
    })
    AK.FinishContainer(container, "player")
    E.container, E.sig, E.level = container, sig, nil
    Level(E)
end

-- The reanchor placed the entry's frame on a bar: the slot follows it, and is
-- built (or built again for a new include set) on the AuraKit worker.
local function Attach(E, f, barKey)
    E.host, E.hostBar = f, barKey
    hostEntry[f] = E
    placed[E] = true
    Listen(true)
    local proxy = E.proxy
    if proxy:GetParent() ~= f then
        proxy:SetParent(f)
        proxy:ClearAllPoints()
        proxy:SetAllPoints(f)
        E.level = nil
    end
    if not proxy:IsShown() then proxy:Show() end
    if (not E.container or E.dirty) and not E.queued then
        E.dirty = nil
        local include, sig = E.provider.Include()
        if not E.container or sig ~= E.sig then
            E.queued = true
            AKWorker:Queue(function()
                E.queued = nil
                Build(E, include, sig)
            end, "cdm:auraicon")
        end
    end
    if E.container and E.styleBar ~= barKey then Restyle(E, barKey) end
end

-------------------------------------------------------------------------------
--  The host frame
-------------------------------------------------------------------------------
local function OnEnter(self)
    local fc = ns._ecmeFC[self]
    local bd = fc and fc.barKey and barDataByKey[fc.barKey]
    local sid = self._auraIconTip
    if not (bd and bd.showTooltip and sid) then return end
    -- Honor the global "Show Tooltips" mode (Blizzard Skin).
    if EllesmereUI._tooltipSuppressedByMode
       and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    GameTooltip:SetSpellByID(sid)
    if EllesmereUI._repointTooltipAtCursor then
        EllesmereUI._repointTooltipAtCursor(GameTooltip)
    end
    GameTooltip:Show()
end

-- The layout resized a host (a Width Match target moved, the bar's icon count
-- changed): its slot's look follows.
local function OnHostSize(self)
    local E = hostEntry[self]
    if E and E.host == self and E.container then Restyle(E, E.hostBar) end
end

-- Built once per bar and entry, kept in the preset frame map, so the reanchor
-- and every rebuild park it with the other injected frames.
local function HostFrame(barKey, key)
    local fkey = barKey .. ":auraicon:" .. key
    local f = _presetFrames[fkey]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36); f:Hide()
    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(); ns.CdmOwnIconCrop(tex)
    f.Icon = tex; f._tex = tex
    -- Never armed (the slot draws the aura's swipe); the decoration styles it
    -- like any icon's.
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    f.Cooldown = cd; f._cooldown = cd
    f._isPresetFrame = true
    f._isAuraIconFrame = true
    f.cooldownID = nil; f.cooldownInfo = nil
    f.layoutIndex = 99999
    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:SetScript("OnSizeChanged", OnHostSize)
    _presetFrames[fkey] = f
    return f
end

local function PaintIdle(f, provider)
    local art = provider.Icon()
    if art and f._auraIconArt ~= art then
        f._auraIconArt = art
        f._tex:SetTexture(art)
    end
    local grey = provider.Desaturate() and true or false
    if f._auraIconGrey ~= grey then
        f._auraIconGrey = grey
        f._tex:SetDesaturated(grey)
    end
    f._auraIconTip = provider.tip
end

local function Place(barKey, provider)
    local f = HostFrame(barKey, provider.key)
    -- Attach first: the include read is what tells the idle paint whether
    -- the entry's spell is known.
    Attach(Entry(provider), f, barKey)
    PaintIdle(f, provider)
    return f
end

-------------------------------------------------------------------------------
--  Phase 3 entry points
-------------------------------------------------------------------------------
-- One provider per custom buff spell ID, made on first use. Its aura IDs are
-- the spell's own forms (typed, override, base), as on a buff bar, and on WoW
-- Forever every other rank of it (_AC.AddSpellForms).
local function BuffProvider(sid)
    local p = buffProviders[sid]
    if p then return p end
    p = {
        key = "buff:" .. sid,
        tip = sid,
        Include = function()
            local set = _AC.AddSpellForms({}, sid)
            local ids = {}
            for id in pairs(set) do ids[#ids + 1] = id end
            table.sort(ids)
            return set, table.concat(ids, ",")
        end,
        Icon = function()
            if not p.art then p.art = C_Spell.GetSpellTexture(sid) end
            return p.art
        end,
        Desaturate = function() return true end,
    }
    buffProviders[sid] = p
    return p
end

-- A custom buff's hosted marker no Blizzard frame or placeholder claimed: its
-- frame on this bar.
function ns.CDM_AuraIconForBuff(barKey, sid)
    return Place(barKey, BuffProvider(sid))
end

-------------------------------------------------------------------------------
--  Kept slots on buff bars
--
--  A custom buff spell ID with no duration of its own (the game tracks its
--  aura) renders in the custom-aura strip at a buff bar's end (_AC): in
--  restricted combat our code cannot tell whether the aura is up, so it can
--  never make room for it inside the row. A buff bar that keeps every slot
--  (Always Show Buffs or Keep Buffs in Same Place) never closes a gap, so
--  there the custom takes its place in the bar's order instead: the buff bar
--  injection lays out a placeholder for it exactly like an inactive Blizzard
--  buff's (greyed, or drawn invisible, by the existing passes), and a slot of
--  its own draws the aura over that placeholder while it is up. Nothing reads
--  whether the aura is up, and the row stays put whatever it does.
--
--  The slot's proxy is placed by number like the strip's holder
--  (EUI_CDM_HookPresetFrames.lua), never inside the bar's frame tree: a Keep
--  in Place placeholder is drawn at alpha 0, which would hide a slot parented
--  to it, and the bar's layout must stay free to move in combat. It follows
--  the placeholder one coalesced frame after the placeholder or its bar moves,
--  resizes, shows or hides, and takes the bar's alpha, as the holder does.
-------------------------------------------------------------------------------
-- A buff bar whose slots never close: every tracked buff holds its place
-- whether it is up or not. FocusKick orders by nameplate state.
function ns.CdmBuffBarKeepsSlots(bd)
    return bd ~= nil and bd.barType == "buffs" and bd.key ~= ns.FOCUSKICK_BAR_KEY
        and (bd.showInactiveBuffIcons or bd.hidePlaceholderIcon) and true or false
end

local keptHost = setmetatable({}, { __mode = "k" })    -- placeholder -> its entry
local keptHooked = setmetatable({}, { __mode = "k" })  -- frames whose moves we follow
local keptBarOf = setmetatable({}, { __mode = "k" })   -- bar frame -> its bar key
local keptPlaced = {}  -- entries the running reanchor placed
local keptDue = {}     -- entries to place on the next frame

local follow = CreateFrame("Frame")
follow:Hide()

-- A frame that parents an engine container cannot show or hide in lockdown:
-- in combat alpha stands in for a hide, and every slot is placed again once
-- combat ends.
local function AfterCombat()
    for E in pairs(kept) do keptDue[E] = true end
    follow:Show()
end

local function ProxyShown(E, on)
    local proxy = E.proxy
    if proxy:IsShown() == on then return end
    if InCombatLockdown() then
        if not on and E.alpha ~= 0 then
            E.alpha = 0
            proxy:SetAlpha(0)
        end
        ns.CombatQueue.Defer("CDMKeptAuraShown", AfterCombat)
        return
    end
    proxy:SetShown(on)
end

local function KeptPlace(E)
    local host, proxy = E.host, E.proxy
    local barFrame = E.hostBar and cdmBarFrames[E.hostBar]
    local show = (host and barFrame and host:IsVisible()) and true or false
    local l, b, w, h
    if show then
        local ok
        ok, l, b, w, h = pcall(host.GetRect, host)
        show = ok and not (IsSecret(l) or IsSecret(b) or IsSecret(w) or IsSecret(h))
            and type(l) == "number" and type(b) == "number"
            and type(w) == "number" and type(h) == "number" and w > 0
    end
    if not show then
        ProxyShown(E, false)
        return
    end
    local s = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l, b, w, h = l * s, b * s, w * s, h * s
    if E.pl ~= l or E.pb ~= b or E.pw ~= w or E.ph ~= h then
        E.pl, E.pb, E.pw, E.ph = l, b, w, h
        proxy:ClearAllPoints()
        proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
        proxy:SetSize(w, h)
    end
    local strata = host:GetFrameStrata()
    if E.strata ~= strata then
        E.strata = strata
        proxy:SetFrameStrata(strata)
        E.level = nil
    end
    Level(E)
    local a = barFrame._visHidden and 0
        or ((ns.EffectiveBarAlpha and ns.EffectiveBarAlpha(barDataByKey[E.hostBar])) or 1)
    if E.alpha ~= a then
        E.alpha = a
        proxy:SetAlpha(a)
    end
    ProxyShown(E, true)
end

follow:SetScript("OnUpdate", function(self)
    self:Hide()
    for E in pairs(keptDue) do
        keptDue[E] = nil
        KeptPlace(E)
    end
end)

local function Due(E)
    keptDue[E] = true
    follow:Show()
end

local function DueOnBar(barKey)
    local byBar = keptByBar[barKey]
    if not byBar then return end
    for _, E in pairs(byBar) do Due(E) end
end

local function OnKeptHostMoved(self)
    local E = keptHost[self]
    if E then Due(E) end
end

-- The layout resized the placeholder: the slot's look follows its size.
local function OnKeptHostSized(self)
    local E = keptHost[self]
    if not E then return end
    if E.container then Restyle(E, E.hostBar) end
    Due(E)
end

local function OnKeptBarMoved(self)
    local barKey = keptBarOf[self]
    if barKey then DueOnBar(barKey) end
end

-- Hooks on frames of ours, installed once per frame.
local function Follow(f, onMove, onSize)
    if keptHooked[f] then return end
    keptHooked[f] = true
    hooksecurefunc(f, "SetPoint", onMove)
    f:HookScript("OnSizeChanged", onSize)
    f:HookScript("OnShow", onMove)
    f:HookScript("OnHide", onMove)
end

local function KeptEntry(barKey, sid)
    local byBar = keptByBar[barKey]
    if not byBar then
        byBar = {}
        keptByBar[barKey] = byBar
    end
    local E = byBar[sid]
    if E then return E end
    E = {
        provider = BuffProvider(sid),
        styleKey = "cdm:keptaura:" .. barKey .. ":" .. sid,
        identKey = "aura:" .. sid,
    }
    local proxy = CreateFrame("Frame", nil, UIParent)
    proxy:Hide()
    proxy:EnableMouse(false)
    E.proxy = proxy
    E.init = function(button, d)
        _AC.InitExtra(button, d)
        button:SetAllPoints(proxy)
    end
    byBar[sid] = E
    kept[E] = true
    return E
end

-- The buff bar injection (EUI_CDM_HookReanchor.lua), on a bar that keeps its
-- slots: the placeholder that holds custom buff sid's place on barKey, with the
-- slot that draws its aura following it. sd: the bar's spell data.
function ns.CDM_KeptAuraFrame(barKey, sid, sd)
    -- A per-spell Custom Icon draws in place of the aura's own icon, as in the
    -- strip. Resolved only once anyone has set one.
    local ci
    if ns._cdmAnyCustomIcon and ResolveSpellSettings then
        local ss = ResolveSpellSettings(nil, sid, sd, barKey)
        ci = ss and ss.customIcon
        if not (type(ci) == "number" and ci > 0) then ci = nil end
    end
    local E = KeptEntry(barKey, sid)
    if not E.art or E.artCi ~= ci then
        E.art = ci or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
        E.artCi = ci
    end
    local ph = GetOrCreatePlaceholderFrame(barKey, sid, E.art, E.identKey)
    -- Our own spell, never a viewer slot: the sort keys it "s"..sid.
    ph.cooldownID = nil
    if E.host ~= ph then
        if E.host and keptHost[E.host] == E then keptHost[E.host] = nil end
        E.host = ph
        keptHost[ph] = E
        Follow(ph, OnKeptHostMoved, OnKeptHostSized)
    end
    local barFrame = cdmBarFrames[barKey]
    if barFrame and not keptBarOf[barFrame] then
        keptBarOf[barFrame] = barKey
        Follow(barFrame, OnKeptBarMoved, OnKeptBarMoved)
    end
    E.hostBar = barKey
    keptPlaced[E] = true
    Listen(true)
    local ciChanged = E.ci ~= ci
    E.ci = ci
    if (not E.container or E.dirty) and not E.queued then
        E.dirty = nil
        local include, sig = E.provider.Include()
        if not E.container or sig ~= E.sig then
            E.queued = true
            AKWorker:Queue(function()
                E.queued = nil
                Build(E, include, sig)
                Due(E)
            end, "cdm:keptaura")
        end
    end
    if E.container and (ciChanged or E.styleBar ~= barKey) then Restyle(E, barKey) end
    Due(E)
    return ph
end

-- ns._AuraCustomPoke: the bar's layout, opacity or visibility changed.
function ns.CDM_KeptAuraPoke(barKey)
    if keptByBar[barKey] then DueOnBar(barKey) end
end

-- WoW Forever: the rank families were read again (ns.CDMRankFamily: a spell
-- learned, talents, Blizzard's cooldown data): each custom buff's include set
-- is read again at its next placement, and built again only if it changed.
function ns.CDM_AuraIconsRanksChanged()
    local any = false
    for sid in pairs(buffProviders) do
        local E = entries["buff:" .. sid]
        if E then
            E.dirty = true
            any = true
        end
    end
    for E in pairs(kept) do
        E.dirty = true
        any = true
    end
    if any and ns.QueueReanchor then ns.QueueReanchor() end
end

-------------------------------------------------------------------------------
--  After every reanchor; on a bar's look change
-------------------------------------------------------------------------------
-- Level the slots the pass placed (the reparent can move a host's level), and
-- let the listener go once nothing is placed.
function ns.CDM_AuraIconsPlaced()
    local any = false
    for E in pairs(placed) do
        placed[E] = nil
        any = true
        Level(E)
    end
    for E in pairs(keptPlaced) do
        keptPlaced[E] = nil
        any = true
    end
    if not any and listening then Listen(false) end
end

-- RefreshCDMIconAppearance: the slots on this bar take its new look.
function ns.CDM_AuraIconsRestyle(barKey)
    for _, E in pairs(entries) do
        if E.container and E.hostBar == barKey then
            Restyle(E, barKey)
            Level(E)
        end
    end
    local byBar = keptByBar[barKey]
    if byBar then
        for _, E in pairs(byBar) do
            if E.container and E.hostBar == barKey then
                Restyle(E, barKey)
                Due(E)
            end
        end
    end
end
