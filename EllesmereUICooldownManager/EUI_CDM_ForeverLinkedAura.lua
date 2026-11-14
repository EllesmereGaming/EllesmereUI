if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_ForeverLinkedAura.lua
--
--  WoW Forever Mages: the swipe, countdown and stack count of the Arcane Blast
--  buff icon, which Blizzard's Cooldown Manager draws as a plain icon there,
--  with or without addons. The aura (400573) sits on the caster as a debuff,
--  so the item's own aura scan (helpful auras only on the player) never
--  returns it: each RefreshData clears the swipe and the count, and only the
--  activity check at its end finds the aura again, through the entry's linked
--  spells. The icon shows, holding aura data nothing draws.
--
--  After each such refresh the two skipped steps are done here from that aura
--  data, as Blizzard's RefreshCooldownInfo and RefreshApplications do them, on
--  the item's own cooldown and stack text: the bar's look and the per-spell
--  settings apply as on any buff icon. A secret count goes straight to the
--  text. Secret times (aura restrictions, i.e. combat) cannot arm a cooldown
--  from addon code, so then the swipe runs from the cast that applied the
--  aura (a recast while it is up adds a stack, its duration runs on), for the
--  aura's full duration.
--
--  Hand-over to Blizzard: a refresh in which Blizzard armed the cooldown
--  itself (its fix landed) is left alone. To retire it for good, drop this
--  file, its TOC line and the call at the end of CollectAndReanchor
--  (EUI_CDM_HookReanchor.lua).
-------------------------------------------------------------------------------
local _, ns = ...
if EllesmereUI.IS_FOREVER ~= true then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "MAGE" then return end

-- Blizzard's buff entries drawn here: entry spell -> the aura's full duration
-- (game data; a refreshed aura reads its time left as its duration).
-- Arcane Blast: aura 400573, 18 s.
local ENTRIES = { [400574] = 18 }
-- The casts that apply an entry's aura -> the entry. Arcane Blast: its
-- ranks, which the entry does not link (no override or base spell between).
local CASTS = {
    [400574] = 400574, [1239696] = 400574, [1239697] = 400574,
    [1239699] = 400574, [1239700] = 400574,
}

local IsSecret = EllesmereUI.IsSecret
local GetTime = GetTime

local entryOf = {}     -- cooldownID -> its ENTRIES spell, or false
local appliedAt = {}   -- entry spell -> GetTime() its aura was applied
local seen = {}        -- entry spell -> its aura was found since appliedAt was set
local listening = false
local hooked = setmetatable({}, { __mode = "k" })
-- [item] = its cooldown was armed since its last refresh
local armed = setmetatable({}, { __mode = "k" })

-- The item's ENTRIES spell, or nil. Blizzard's API copy of an entry's info
-- is never secret.
local function EntryOf(cdID)
    if type(cdID) ~= "number" or IsSecret(cdID) then return nil end
    local e = entryOf[cdID]
    if e == nil then
        local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        local info = gci and gci(cdID)
        if not info then return nil end
        e = (ENTRIES[info.spellID] and info.spellID)
            or (ENTRIES[info.overrideSpellID] and info.overrideSpellID) or false
        entryOf[cdID] = e
    end
    return e or nil
end

local function Arm(frame, cd, start, dur, rate)
    -- Blizzard's colour: our SetSwipeColor hook repaints it per the bar.
    local c = frame.GetCooldownSwipeColor and frame:GetCooldownSwipeColor()
    if c then cd:SetSwipeColor(c.r, c.g, c.b, c.a) end
    cd:SetCooldown(start, dur, rate)
    armed[frame] = nil
end

-- The aura the item holds, drawn on its own widgets. The cached aura can be a
-- secret table, and any of its values secret: probed before every other test.
local function Draw(frame, spell)
    local ad = frame.auraDataCached
    local now = GetTime()
    if IsSecret(ad) then
        -- Hidden whole (aura restrictions): it is held, nothing of it can be read.
        seen[spell] = true
        return
    end
    if not ad then
        -- Gone (consumed or expired): the next cast applies it anew. An aura
        -- that was never found may still follow a cast of the last second.
        local t = appliedAt[spell]
        if t and (seen[spell] or now - t > 1) then appliedAt[spell], seen[spell] = nil, nil end
        return
    end
    seen[spell] = true
    local cd = frame.Cooldown
    local exp, dur, rate = ad.expirationTime, ad.duration, ad.timeMod
    local start, len
    if not IsSecret(exp) and not IsSecret(dur) then
        if type(exp) == "number" and type(dur) == "number" and dur > 0 and exp > now then
            if IsSecret(rate) or type(rate) ~= "number" or rate <= 0 then rate = 1 end
            -- Against the full duration: a refreshed aura's is its time left.
            local full = ENTRIES[spell]
            if full < dur then full = dur end
            appliedAt[spell] = exp - full
            start, len = exp - full, full
        end
    else
        -- Restricted: time it from the cast that applied the aura. Re-armed
        -- with the same start after each refresh (Blizzard clears it), so the
        -- swipe does not jump.
        local t, d = appliedAt[spell], ENTRIES[spell]
        if t and t + d > now then start, len, rate = t, d, 1 end
    end
    if cd and start then Arm(frame, cd, start, len, rate) end
    local fs = frame.Applications and frame.Applications.Applications
    local apps = ad.applications
    if fs and (IsSecret(apps) or type(apps) == "number") then
        if not IsSecret(apps) and apps < 2 then apps = "" end
        fs:SetText(apps)
    end
end

-- A refresh in which Blizzard armed the cooldown drew the aura itself.
local function AfterRefresh(frame)
    local native = armed[frame]
    armed[frame] = nil
    if native then return end
    local spell = EntryOf(frame.cooldownID)
    if spell then Draw(frame, spell) end
end

-- A cast while the aura is down applies it: its spellID is never secret.
-- Drawn at once too, as the aura's own refresh may already have run. A recast
-- while it is up only adds a stack.
local function OnCast(_, _, _, _, spellID)
    local entry = not IsSecret(spellID) and CASTS[spellID]
    if not entry then return end
    local now = GetTime()
    local t, d = appliedAt[entry], ENTRIES[entry]
    if t and t + d > now then return end
    appliedAt[entry], seen[entry] = now, nil
    for frame in pairs(hooked) do
        if frame:IsShown() and EntryOf(frame.cooldownID) == entry then Draw(frame, entry) end
    end
end

local castFrame = ns.TakeShell()
castFrame:SetScript("OnEvent", OnCast)

-- After every reanchor: hook the buff icon items bound to an entry. Items are
-- pooled, so a hooked one bound to another entry later returns at EntryOf.
-- The player's casts are heard only while an entry's icon is tracked.
function ns.CDM_LinkedAuraPlaced()
    local viewer = _G.BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not pool then return end
    local tracked = false
    for frame in pool:EnumerateActive() do
        local spell = frame.RefreshData and frame.Cooldown and EntryOf(frame.cooldownID)
        if spell then
            tracked = true
            if not hooked[frame] then
                hooked[frame] = true
                hooksecurefunc(frame, "RefreshData", AfterRefresh)
                hooksecurefunc(frame.Cooldown, "SetCooldown", function() armed[frame] = true end)
                Draw(frame, spell)
            end
        end
    end
    if tracked ~= listening then
        listening = tracked
        if tracked then
            castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else
            castFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
    end
end
