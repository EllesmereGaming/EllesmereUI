if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_ForeverMissingBuffs.lua  (WoW Forever only)
--
--  Missing Buffs indicator: on each raid, party and Extra Frames button, the
--  icon of every buff the member lacks that the PLAYER can cast --
--  Fortitude and Spirit (priest; Spirit needs the Divine Spirit talent),
--  Mark of the Wild and Thorns (druid), Paladin Blessings (paladin: any
--  blessing, normal or Greater, counts) -- i.e. a trained rank or the group
--  version is in the player's spellbook. On the member every rank and the
--  group version count (looked up by name). Settings (Indicators section,
--  same shape as the raid marker): showMissingBuffs, missingBuffsPosition,
--  missingBuffsSize, missingBuffsOffsetX/Y, one switch per buff
--  (missingBuffsFort/Mark/Spirit/Thorns/Blessing, the cog's checkbox list, nil = on),
--  and the icons' glow on the shared prefix schema (missingBuffsGlow*,
--  EllesmereUI.Glows.PrefixKeys); Forever-only defaults in the main file.
--
--  A member reads as unknown (no icon) while offline or out of sight (the
--  client has no aura data then), and under the game's aura restriction a
--  buff counts only if every rank of it is non-secret at that moment
--  (C_Secrets, asked again each frame: outside a restriction nothing is
--  secret); a secret one would read absent while up, so it shows nothing
--  rather than a false alarm.
--
--  Cost: off everywhere, every buff of the player's class switched off, or
--  a class that can cast none of these buffs = no events, no overlays.
--  On: UNIT_AURA and
--  UNIT_CONNECTION for the group tokens only, each aura event probing its
--  own added and removed auras against these buffs before a member is
--  looked up again (coalesced to one pass per frame); the roster, the world
--  and each aura restriction edge re-read everyone once. While auras are
--  restricted the payload is secret, so an event re-reads its member only
--  while a buff the player provides stays readable.
--
--  The main file calls ns.RF_FvMissingAnchor from each reload path and
--  ns.RF_FvMissingPreview from the preview pass, the containers file
--  ns.RF_FvMissingUnit from the secure header's unit assignment; on every
--  other client all three stay nil.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

-- One entry per buff, shown in this order. class: the one class that casts
-- it; setting: its own switch (the cog's checkbox list; nil = on); names:
-- spells whose (localized) names cover every rank and the group version;
-- ranks: the player ranks and the group version (the "player can cast it"
-- and restriction tests); ids: every spell that applies the buff (ranks,
-- group version, NPC casts) for the aura-event probe.
local FAMILIES = {
    { key = "fort", class = "PRIEST", setting = "missingBuffsFort", icon = 1243, names = { 1243, 21562 },
      ranks = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 },
      ids = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948,
              21562, 21564, 450086 } },
    { key = "mark", class = "DRUID", setting = "missingBuffsMark", icon = 1126, names = { 1126, 21849 },
      ranks = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 },
      ids = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752,
              364163, 1291335, 1310503, 21849, 21850 } },
    { key = "spirit", class = "PRIEST", setting = "missingBuffsSpirit", icon = 14752, names = { 14752, 27681 },
      ranks = { 14752, 14818, 14819, 27841, 27681 },
      ids = { 14752, 14818, 14819, 16875, 27841, 27681 } },
    -- Thorns: six druid ranks (Balance), no group version; ids = every spell
    -- named Thorns on the client, matching the by-name look-up.
    { key = "thorns", class = "DRUID", setting = "missingBuffsThorns", icon = 467, names = { 467 },
      ranks = { 467, 782, 1075, 8914, 9756, 9910 },
      ids = { 467, 782, 1075, 8914, 9756, 9910, 15438, 16877, 21335, 21337, 22128, 22351, 22696,
              25640, 25777, 438294, 438326, 1213813, 1213816, 1213834, 1236308, 1291338, 1312955 } },
    -- Paladin Blessings: one buff made of every blessing (Might, Wisdom, Kings,
    -- Salvation, Light and their Greater versions), missing only while the
    -- member has none of them; shown with the Kings icon. ranks = the trainable
    -- spells (SkillLineAbility); ids add the client's two non-trainable ones
    -- (1213408 Kings, 26650 Light).
    { key = "blessing", class = "PALADIN", setting = "missingBuffsBlessing", icon = 20217,
      names = { 19740, 19742, 20217, 1038, 19977, 25782, 25894, 25898, 25895, 25890 },
      ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291,
                19742, 19850, 19852, 19853, 19854, 25290,
                20217, 1038, 19977, 19978, 19979,
                25782, 25916, 25894, 25918, 25898, 25895, 25890 },
      ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291,
              19742, 19850, 19852, 19853, 19854, 25290,
              20217, 1213408, 1038, 19977, 19978, 19979, 26650,
              25782, 25916, 25894, 25918, 25898, 25895, 25890 } },
}
local NUM_FAMILIES = #FAMILIES
local FAMILY_BY_ID = {}  -- spell id -> family index
for i = 1, NUM_FAMILIES do
    for _, id in ipairs(FAMILIES[i].ids) do FAMILY_BY_ID[id] = i end
end

-- Only a priest, a druid or a paladin can ever cast one of these: every other
-- class keeps the whole indicator off (no events, no overlays).
local PLAYER_CLASS = select(2, UnitClass("player"))
local CAN_EVER = false
for i = 1, NUM_FAMILIES do
    if FAMILIES[i].class == PLAYER_CLASS then CAN_EVER = true end
end

-- Per group token: state[unit][key] = true (has it), false (lacks it) or nil
-- (unknown); inst[unit] = the aura instances found, for the removed-aura probe.
local state, inst = {}, {}
local provider = {}      -- key -> the player can cast it (a rank in the spellbook)
local wantFam = {}       -- key -> switched on where the indicator shows (raid, party or Extra Frames)
local enabled = false
local trusted = {}       -- key -> readable right now (Trusted rebuilds it once per frame)
local names = {}         -- family index -> { localized names }
local icons = {}         -- family index -> texture

local function SettingsFor(d)
    return d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
end

local function FamilyNames(i)
    local n = names[i]
    if n then return n end
    n = {}
    for _, id in ipairs(FAMILIES[i].names) do
        local name = C_Spell.GetSpellName(id)
        if name then n[#n + 1] = name end
    end
    -- Spell data can be cold this early: keep an empty answer uncached.
    if #n > 0 then names[i] = n end
    return n
end

local function FamilyIcon(i)
    local tex = icons[i]
    if not tex then
        tex = C_Spell.GetSpellTexture(FAMILIES[i].icon)
        icons[i] = tex
    end
    return tex or 134400
end

-- Whether every player rank of a buff reads non-secret right now. The
-- answer follows the current restriction (outside one no aura is secret),
-- so it is rebuilt once per frame and never kept across a restriction edge:
-- a lookup can only find a non-secret aura, so a stale "readable" turns a
-- secret buff into a false "missing".
local trustedAt
local function Trusted(i)
    local now = GetTime()
    if trustedAt ~= now then
        trustedAt = now
        local S = C_Secrets
        for fi = 1, NUM_FAMILIES do
            local ok = true
            if S and S.ShouldSpellAuraBeSecret then
                for _, id in ipairs(FAMILIES[fi].ranks) do
                    local good, secret = pcall(S.ShouldSpellAuraBeSecret, id)
                    if not good or issecretvalue(secret) or secret ~= false then ok = false; break end
                end
            end
            trusted[FAMILIES[fi].key] = ok
        end
    end
    return trusted[FAMILIES[i].key]
end

-- A buff's own switch in one settings table (nil = on).
local function FamOn(s, fam)
    return s[fam.setting] ~= false
end

-- Worth reading: the player can cast it and it is switched on somewhere.
local function Tracked(i)
    local key = FAMILIES[i].key
    return provider[key] and wantFam[key]
end

-------------------------------------------------------------------------------
--  Reading a member
-------------------------------------------------------------------------------
local function Evaluate(unit, restricted)
    local st = state[unit]
    if not st then st = {}; state[unit] = st end
    local found = inst[unit]
    if found then wipe(found) else found = {}; inst[unit] = found end
    local known = UnitExists(unit) and UnitIsConnected(unit) and UnitIsVisible(unit)
    for i = 1, NUM_FAMILIES do
        local key = FAMILIES[i].key
        local value
        -- A buff the player cannot cast, or switched off everywhere, is never
        -- looked up (it never shows).
        if known and Tracked(i) and not (restricted and not Trusted(i)) then
            local list = FamilyNames(i)
            if #list > 0 then
                value = false
                for n = 1, #list do
                    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, list[n], "HELPFUL")
                    if not ok or issecretvalue(aura) then value = nil; break end
                    if aura then
                        value = true
                        local iid = aura.auraInstanceID
                        if iid and not issecretvalue(iid) then found[iid] = true end
                        break
                    end
                end
            end
        end
        st[key] = value
    end
end

-- A buff counts only while the player can cast it: their class casts it and
-- a trained rank (or the group version) is in their spellbook. Divine Spirit
-- is a talent, so a priest without it gets no Spirit icons.
local function Knows(fam)
    if fam.class ~= PLAYER_CLASS then return false end
    local ranks = fam.ranks
    for r = 1, #ranks do
        if C_SpellBook.IsSpellKnown(ranks[r]) then return true end
    end
    return false
end

-- Re-reads what the player can cast; true when any buff changed.
local function ScanProviders()
    local changed = false
    for i = 1, NUM_FAMILIES do
        local fam = FAMILIES[i]
        local can = Knows(fam)
        if (provider[fam.key] == true) ~= can then
            provider[fam.key] = can
            changed = true
        end
    end
    return changed
end

-------------------------------------------------------------------------------
--  Overlay
-------------------------------------------------------------------------------
local function Overlay(host, level)
    local o = CreateFrame("Frame", nil, host)
    o:SetFrameLevel(level)
    o:EnableMouse(false)
    o.slots = {}
    for i = 1, NUM_FAMILIES do
        local bg = o:CreateTexture(nil, "ARTWORK", nil, 0)
        bg:SetColorTexture(0, 0, 0, 1)
        local tex = o:CreateTexture(nil, "ARTWORK", nil, 1)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bg:Hide(); tex:Hide()
        o.slots[i] = { bg = bg, tex = tex }
    end
    o:Hide()
    return o
end

-- The icons' glow (prefix keys missingBuffsGlow*, style 0 = none): one host
-- per shown icon. Every icon that goes, and every overlay that hides, stops
-- its glow, so nothing hidden stays in the shared glow driver.
local glowSpec = {}
local NO_SHAPE = { [4] = true } -- Shape Glow follows an icon shape; these cells have none

local function StopGlows(o, from)
    for i = from, NUM_FAMILIES do
        local g = o.slots[i].glow
        if g and g.fvOn then
            EllesmereUI.Glows.StopGlow(g)
            g.fvOn = nil
        end
    end
end

local function HideOverlay(o)
    StopGlows(o, 1)
    o:Hide()
end

local function ApplyGlows(o, s, n, size)
    local G = EllesmereUI.Glows
    local spec = G.SpecFromPrefix(glowSpec, s, "missingBuffsGlow")
    if not spec then
        StopGlows(o, 1)
        return
    end
    spec.excludes = NO_SHAPE
    for i = 1, n do
        local slot = o.slots[i]
        local g = slot.glow
        if not g then
            g = CreateFrame("Frame", nil, o)
            g:SetAllPoints(slot.bg)
            g:SetFrameLevel(o:GetFrameLevel() + 2)
            g:EnableMouse(false)
            slot.glow = g
        end
        G.StartSpecGlow(g, spec, size, size, "icon")
        g.fvOn = true
    end
    StopGlows(o, n + 1)
end

-- Lays out n icons (the family indices in list) at the configured position:
-- the overlay is exactly as wide as its icons, so a right-side position grows
-- leftward and a centred one stays centred. Same 9-point spots and edge inset
-- as the raid marker.
local function Layout(o, s, health, list, n)
    local snap = ns.PixelSnap or function(v) return v end
    local size = snap(s.missingBuffsSize or 22)
    -- One physical pixel: the icon edge and the gap between icons.
    local edge = snap(1)
    if edge <= 0 then edge = 1 end
    for i = 1, NUM_FAMILIES do
        local slot = o.slots[i]
        if i <= n then
            local x = (i - 1) * (size + edge)
            slot.bg:ClearAllPoints()
            slot.bg:SetPoint("TOPLEFT", o, "TOPLEFT", x, 0)
            slot.bg:SetSize(size, size)
            slot.tex:ClearAllPoints()
            slot.tex:SetPoint("TOPLEFT", slot.bg, "TOPLEFT", edge, -edge)
            slot.tex:SetPoint("BOTTOMRIGHT", slot.bg, "BOTTOMRIGHT", -edge, edge)
            slot.tex:SetTexture(FamilyIcon(list[i]))
            slot.bg:Show(); slot.tex:Show()
        else
            slot.bg:Hide(); slot.tex:Hide()
        end
    end
    if n == 0 then HideOverlay(o) return end
    o:SetSize(n * size + (n - 1) * edge, size)
    local host = ns.RF_AnchorHost(health, s)
    local pos = s.missingBuffsPosition or "top"
    local ox, oy = s.missingBuffsOffsetX or 0, s.missingBuffsOffsetY or 0
    o:ClearAllPoints()
    if pos == "topleft" then
        o:SetPoint("TOPLEFT", host, "TOPLEFT", 2 + ox, -2 + oy)
    elseif pos == "top" then
        o:SetPoint("TOP", host, "TOP", ox, -2 + oy)
    elseif pos == "topright" then
        o:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2 + ox, -2 + oy)
    elseif pos == "left" then
        o:SetPoint("LEFT", host, "LEFT", 2 + ox, oy)
    elseif pos == "right" then
        o:SetPoint("RIGHT", host, "RIGHT", -2 + ox, oy)
    elseif pos == "bottomleft" then
        o:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 2 + ox, 2 + oy)
    elseif pos == "bottom" then
        o:SetPoint("BOTTOM", host, "BOTTOM", ox, 2 + oy)
    elseif pos == "bottomright" then
        o:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2 + ox, 2 + oy)
    else
        o:SetPoint("CENTER", host, "CENTER", ox, oy)
    end
    ApplyGlows(o, s, n, size)
    o:Show()
end

local paintList = {}
local function PaintButton(btn, d)
    if not d.health then return end
    local s = SettingsFor(d)
    local on = enabled and s and s.showMissingBuffs ~= false
    local o = d.fvMissing
    if not on then
        if o then HideOverlay(o) end
        return
    end
    local unit = btn:GetAttribute("unit")
    local st = unit and state[unit]
    local n = 0
    if st then
        for i = 1, NUM_FAMILIES do
            local fam = FAMILIES[i]
            local key = fam.key
            -- This frame kind's own switch decides, so a buff turned off for
            -- party but on for raid shows on raid frames only.
            if st[key] == false and provider[key] and FamOn(s, fam) then
                n = n + 1
                paintList[n] = i
            end
        end
    end
    if n == 0 and not o then return end
    if not o then
        o = Overlay(btn, btn:GetFrameLevel() + ns.LVL_MARKER)
        d.fvMissing = o
    end
    Layout(o, s, d.health, paintList, n)
end

local function PaintUnit(unit)
    local GetFFD = ns.GetFFD
    local b = ns._raidUnitToButton and ns._raidUnitToButton[unit]
    if b then PaintButton(b, GetFFD(b)) end
    b = ns._partyUnitToButton and ns._partyUnitToButton[unit]
    if b then PaintButton(b, GetFFD(b)) end
    b = ns._xfUnitToButton and ns._xfUnitToButton[unit]
    if b then PaintButton(b, GetFFD(b)) end
end

local function PaintList(list)
    if not list then return end
    local GetFFD = ns.GetFFD
    for i = 1, #list do
        local b = list[i]
        PaintButton(b, GetFFD(b))
    end
end

local function PaintAll()
    PaintList(ns._allButtons)          -- raid + Extra Frames
    PaintList(ns._partyAllButtons)
end

local function Mapped(unit)
    return (ns._raidUnitToButton and ns._raidUnitToButton[unit])
        or (ns._partyUnitToButton and ns._partyUnitToButton[unit])
        or (ns._xfUnitToButton and ns._xfUnitToButton[unit])
end

-------------------------------------------------------------------------------
--  Passes (one per frame)
-------------------------------------------------------------------------------
-- dirty: members to look up again; pendingBtns: buttons that took a new unit
-- (painted directly: the unit maps may not have caught up with them yet).
local dirty, pendingBtns, flushArmed, fullArmed = {}, {}, false, false

-- Full pass: every button's own unit, read off the button itself.
local function EvaluateList(list, restricted)
    if not list then return end
    for i = 1, #list do
        local unit = list[i]:GetAttribute("unit")
        if unit and not state[unit] then Evaluate(unit, restricted) end
    end
end

local function Flush()
    flushArmed = false
    if not enabled then wipe(dirty); wipe(pendingBtns); fullArmed = false; return end
    local restricted = EllesmereUI.AuraKit.AurasRestricted()
    local full = fullArmed
    fullArmed = false
    if full then
        wipe(dirty); wipe(pendingBtns)
        ScanProviders()
        wipe(state); wipe(inst)
        EvaluateList(ns._allButtons, restricted)
        EvaluateList(ns._partyAllButtons, restricted)
        PaintAll()
        return
    end
    for unit in pairs(dirty) do Evaluate(unit, restricted) end
    for unit in pairs(dirty) do PaintUnit(unit) end
    local GetFFD = ns.GetFFD
    for b in pairs(pendingBtns) do PaintButton(b, GetFFD(b)) end
    wipe(dirty); wipe(pendingBtns)
end

local function Arm()
    if flushArmed then return end
    flushArmed = true
    C_Timer.After(0, Flush)
end

local function MarkDirty(unit)
    dirty[unit] = true
    Arm()
end

local function MarkAll()
    fullArmed = true
    Arm()
end

-------------------------------------------------------------------------------
--  Events (registered only while the indicator is on somewhere)
-------------------------------------------------------------------------------
-- The payload is secret while auras are restricted (UNIT_AURA is
-- SecretWhenAurasRestricted): nothing in it can be read, so the member is
-- looked up again, but only while a buff the player provides stays readable
-- under the restriction. The rest read unknown until it lifts, and the
-- restriction edge re-reads everyone then.
local function Unprobeable(unit)
    for i = 1, NUM_FAMILIES do
        if Tracked(i) and Trusted(i) then MarkDirty(unit) return end
    end
end

-- Probe the payload first: only an added or removed Missing Buffs aura
-- sends the member back for a look-up; a full update always does.
local function OnUnitAura(unit, info)
    if not Mapped(unit) then return end
    if not info then MarkDirty(unit) return end
    if issecretvalue(info) then Unprobeable(unit) return end
    local full = info.isFullUpdate
    if issecretvalue(full) then Unprobeable(unit) return end
    if full then MarkDirty(unit) return end
    local added = info.addedAuras
    if added then
        if issecretvalue(added) then Unprobeable(unit) return end
        for i = 1, #added do
            local aura = added[i]
            if issecretvalue(aura) then Unprobeable(unit) return end
            local sid = aura.spellId
            if issecretvalue(sid) then Unprobeable(unit) return end
            local fi = sid and FAMILY_BY_ID[sid]
            if fi and Tracked(fi) then MarkDirty(unit) return end
        end
    end
    local removed, found = info.removedAuraInstanceIDs, inst[unit]
    if removed and found and next(found) then
        if issecretvalue(removed) then Unprobeable(unit) return end
        for i = 1, #removed do
            local iid = removed[i]
            if issecretvalue(iid) then Unprobeable(unit) return end
            if found[iid] then MarkDirty(unit) return end
        end
    end
end

local function OnTrackerEvent(_, event, unit, info)
    if event == "UNIT_AURA" then
        OnUnitAura(unit, info)
    elseif Mapped(unit) then
        MarkDirty(unit)
    end
end

-- RegisterUnitEvent takes two units: the 45 group tokens ride 23 frames
-- (built here, so their events bill this module; registered only while on).
local TOKENS = { "player" }
for i = 1, 4 do TOKENS[#TOKENS + 1] = "party" .. i end
for i = 1, 40 do TOKENS[#TOKENS + 1] = "raid" .. i end
local trackers = {}
for i = 1, #TOKENS, 2 do
    local f = CreateFrame("Frame")
    f._u1, f._u2 = TOKENS[i], TOKENS[i + 1]
    f:SetScript("OnEvent", OnTrackerEvent)
    trackers[#trackers + 1] = f
end

local CHAT_RESTRICTION = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat

local world = CreateFrame("Frame")
world:SetScript("OnEvent", function(_, event, rtype)
    if event == "SPELLS_CHANGED" then
        -- A buff learned or lost (a rank trained, the Divine Spirit talent
        -- taken or dropped) re-reads everyone; anything else costs one scan.
        if ScanProviders() then MarkAll() end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- A restriction starting or lifting changes which buffs can be read.
        -- The pass runs next frame, after the activation dispatch, so it reads
        -- the settled state; addon chat restrictions never touch auras.
        if rtype ~= CHAT_RESTRICTION then MarkAll() end
    else
        MarkAll()
    end
end)

local function SetEvents(on)
    for i = 1, #trackers do
        local f = trackers[i]
        if on then
            f:RegisterUnitEvent("UNIT_AURA", f._u1, f._u2)
            f:RegisterUnitEvent("UNIT_CONNECTION", f._u1, f._u2)
        else
            f:UnregisterAllEvents()
        end
    end
    if on then
        world:RegisterEvent("GROUP_ROSTER_UPDATE")
        world:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Every aura restriction edge (combat, encounters, instances).
        world:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        -- What the player can cast (only a priest, druid or paladin gets here).
        world:RegisterEvent("SPELLS_CHANGED")
    else
        world:UnregisterAllEvents()
    end
end

-- Settles which buffs matter: a buff counts while its switch is on in a
-- raid, party or Extra Frames settings table whose indicator is on. Returns
-- whether any buff of the player's class counts (the indicator is on at
-- all), and whether any buff's answer changed.
local SETTINGS = {}      -- scratch: this pass's three settings tables
local function ScanWanted()
    SETTINGS[1], SETTINGS[2], SETTINGS[3] = ns._scaledProfile, ns._scaledPartyProxy, ns._scaledExtraProxy
    local any, changed = false, false
    for i = 1, NUM_FAMILIES do
        local fam = FAMILIES[i]
        local on = false
        for t = 1, 3 do
            local s = SETTINGS[t]
            if s and s.showMissingBuffs ~= false and FamOn(s, fam) then on = true; break end
        end
        if on and fam.class == PLAYER_CLASS then any = true end
        if (wantFam[fam.key] == true) ~= on then
            wantFam[fam.key] = on
            changed = true
        end
    end
    return any, changed
end

-- On (for a class that casts one of the buffs at all): events and a full
-- look-up; a buff switched on or off while on re-reads everyone for it.
local syncArmed = false
local function Sync()
    syncArmed = false
    local want, changed = false, false
    if CAN_EVER then want, changed = ScanWanted() end
    if want ~= enabled then
        enabled = want
        SetEvents(want)
        if want then
            MarkAll()
        else
            wipe(state); wipe(inst); wipe(dirty); wipe(pendingBtns)
            PaintAll()
        end
    elseif want and changed then
        MarkAll()
    end
end

-------------------------------------------------------------------------------
--  Main-file hooks
-------------------------------------------------------------------------------
-- Each reload path, per button: re-lay the icons from what is known (no
-- look-ups), then settle the on/off state once for the whole pass.
function ns.RF_FvMissingAnchor(btn, d)
    PaintButton(btn, d)
    if not syncArmed then
        syncArmed = true
        C_Timer.After(0, Sync)
    end
end

-- The secure header's unit assignment (every roster re-process, same unit
-- included): only a button whose unit really changed looks its member up.
function ns.RF_FvMissingUnit(btn, d, unit)
    if not enabled or d._fvUnit == unit then return end
    d._fvUnit = unit
    if not unit then
        -- An emptied button hides: its glows leave the driver with it.
        if d.fvMissing then HideOverlay(d.fvMissing) end
        return
    end
    pendingBtns[btn] = true
    MarkDirty(unit)
end

-- Options preview: a fixed spread of missing buffs while the indicators
-- preview (the Indicators eye) is on, minus the buffs switched off.
local PREVIEW = {
    [2] = { 1 }, [4] = { 1, 2 }, [7] = { 3, 5 }, [9] = { 1, 2, 3, 4, 5 },
    [12] = { 2, 4 }, [15] = { 1, 3 }, [18] = { 4, 5 },
}
local previewList = {}
function ns.RF_FvMissingPreview(f, index, s, indVis)
    local spread = indVis and s.showMissingBuffs ~= false and f._health and PREVIEW[index]
    local n = 0
    if spread then
        for k = 1, #spread do
            local i = spread[k]
            if FamOn(s, FAMILIES[i]) then
                n = n + 1
                previewList[n] = i
            end
        end
    end
    local o = f._fvMissing
    if n == 0 then
        if o then HideOverlay(o) end
        return
    end
    if not o then
        o = Overlay(f, f:GetFrameLevel() + ns.LVL_MARKER)
        f._fvMissing = o
    end
    Layout(o, s, f._health, previewList, n)
end

-- First look once the world is up (the reload paths may not run at login).
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Sync()
end)
