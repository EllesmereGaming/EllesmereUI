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
--  Two kinds of entry:
--    * a custom buff spell ID on a cooldown or utility bar (the Add Buff
--      menu's Custom Spell ID, stored as a hosted-buff marker): drawn here
--      while no Blizzard frame or placeholder claims it, its idle icon grey,
--      as a hosted buff keeps its slot on such a bar;
--    * a spell ID a provider draws (ns.CDM_AuraIconProvider): the WoW Forever
--      Seals stand-in (EUI_CDM_ForeverSeals.lua). The drop pass and the
--      repopulate keep such an ID, and the options preview never dims it as
--      unlearned (ns.CDM_AuraIconKeeps).
--
--  One slot per entry, moved between bars through its proxy: a frame of ours
--  the slot button fills, parented to the host frame, so the slot takes the
--  host's visibility, opacity and strata, and a hidden host hides the
--  container, which then registers no events. The slot is built again only
--  when its include set changes (engine buttons are never freed).
--
--  Reached from: EUI_CDM_HookReanchor.lua (Phase 3 injection, and the end of
--  every reanchor), EUI_CDM_Icons.lua (RefreshCDMIconAppearance), and the
--  drop pass, the repopulate and the options preview (ns.CDM_AuraIconKeeps).
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
if not I or I.broken or not I._AC then return end
local _AC, _presetFrames = I._AC, I._presetFrames
local barDataByKey = ns.barDataByKey
local IsSecret = EllesmereUI.IsSecret

local AKWorker = EllesmereUI.AuraKit.NewBuildWorker()

-- The slot sits over the host's art, border and swipe (border +13/+14, swipe
-- +14), under its glows (+16) and text (+23), as DecorateFrame levels them.
local SLOT_LEVEL = 14

local entries = {}         -- provider key -> entry
local placed = {}          -- entries attached since the last post-reanchor pass
local byID = {}            -- spell ID -> the provider that draws it
local pendingAliases = {}  -- providers whose Aliases have not been read yet
local buffProviders = {}   -- custom buff spell ID -> its provider
-- host frame -> the entry it holds (one frame per bar and entry)
local hostEntry = setmetatable({}, { __mode = "k" })

-------------------------------------------------------------------------------
--  Providers
--
--  provider = {
--    key,           unique entry key
--    tip,           the spell ID the idle frame's tooltip shows
--    Include(),     -> the aura spell IDs (a set, never empty) and a signature
--    Icon(),        -> the idle art
--    Desaturate(),  -> whether the idle art is grey
--    Off(),         optional: true once the entry stands down
--    Aliases(),     optional: more spell IDs it draws, read once Blizzard's
--                   cooldown data has loaded
--    Placed(),      optional: after each reanchor that placed it
--  }
-------------------------------------------------------------------------------
function ns.CDM_AuraIconProvider(spellID, provider)
    byID[spellID] = provider
    if provider.Aliases then pendingAliases[#pendingAliases + 1] = provider end
end

local function ReadAliases()
    if not ns._cdmDataLoaded then return end
    for i = #pendingAliases, 1, -1 do
        local p = table.remove(pendingAliases, i)
        local ids = p.Aliases()
        if ids then
            for j = 1, #ids do
                if byID[ids[j]] == nil then byID[ids[j]] = p end
            end
        end
        -- What it read can widen the include set of an entry built earlier.
        local E = entries[p.key]
        if E then E.dirty = true end
    end
end

-- An assigned spell ID a provider draws: kept by the drop pass and the
-- repopulate, never dimmed as unlearned by the options preview.
function ns.CDM_AuraIconKeeps(id)
    if pendingAliases[1] then ReadAliases() end
    return byID[id] ~= nil
end

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

-- The slot's look: the bar's custom-aura look, cut for the host's size.
local function HostStyle(E, bd)
    local style = _AC.BuildStyle(bd)
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
    if provider.Off and provider.Off() then return nil end
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
-- A positive spell ID no Blizzard frame claimed: the frame of the provider
-- that draws it, or nil.
function ns.CDM_AuraIconFor(barKey, sid)
    if pendingAliases[1] then ReadAliases() end
    local p = byID[sid]
    if not p then return nil end
    return Place(barKey, p)
end

-- One provider per custom buff spell ID, made on first use. Its aura IDs are
-- the spell's own forms (typed, override, base), as on a buff bar.
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
--  After every reanchor; on a bar's look change
-------------------------------------------------------------------------------
-- Level the slots the pass placed (the reparent can move a host's level), run
-- their providers' checks, and let the listener go once nothing is placed.
function ns.CDM_AuraIconsPlaced()
    local any = false
    for E in pairs(placed) do
        placed[E] = nil
        any = true
        Level(E)
        local after = E.provider.Placed
        if after then after() end
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
end
