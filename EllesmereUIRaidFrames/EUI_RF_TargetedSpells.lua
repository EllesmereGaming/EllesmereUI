-------------------------------------------------------------------------------
--  EUI_RF_TargetedSpells.lua
--  Targeted Spells: when an enemy nameplate starts a cast that has a
--  displayable player target, identify the targeted group member and show the
--  cast's spell icon on that member's frame, with a duration swipe.
--
--  Party and raid are the SAME feature in two contexts. A `raid` flag is
--  threaded through icon creation / styling / layout so each context reads its
--  own settings (ts* for party, tsRaid* for raid via Setting()) and its own
--  unit->button map (ns._partyUnitToButton / ns._raidUnitToButton). The
--  classifier, gates and timings are identical; raid is just a second roster.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local CreateFrame   = CreateFrame
local C_Timer       = C_Timer
local C_NamePlate    = C_NamePlate
local GetTime       = GetTime
local UnitExists    = UnitExists
local UnitClass     = UnitClass
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitRace      = UnitRace
local UnitSex       = UnitSex
local tremove       = table.remove
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitCanAttack = UnitCanAttack
local IsInGroup     = IsInGroup
local IsInRaid      = IsInRaid
local pairs         = pairs
local ipairs        = ipairs
local type          = type
local wipe          = wipe
local lower         = string.lower
local random        = math.random
local issecret      = issecretvalue or function() return false end

-- Roster token lists per context. Units() picks the active one so the roster
-- cache and classifier iterate raid1-40 in a raid and the party list otherwise.
local ROSTER_UNITS = { "player", "party1", "party2", "party3", "party4" }
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
local function Units()
    return IsInRaid() and RAID_UNITS or ROSTER_UNITS
end

-- Two deferred reads per cast/retarget. The first picks up the (now-linked)
-- target; the second catches the engine's tank-lock bug -- some abilities
-- report the TANK as the target for the first ~quarter second before flipping
-- to the real one, so a single early read lands mid-flip. The verify is cheap:
-- Classify short-circuits its race/sex reads once class (+role) already resolve
-- to one member, and an unchanged target early-returns before any teardown.
local PICKUP_DELAY = 0.1      -- engine target-link delay; first read
local VERIFY_DELAY = 0.15     -- second read, ~250ms after cast start (tank-lock)
local RETARGET_DELAY = 0.05   -- faster first read on a mid-cast target swap
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Dynamic profile access: never freeze ns.db.profile into an upvalue (profile
-- swaps replace the table).
local function S()
    return ns.db and ns.db.profile
end

-- Setting value, raid-aware: party reads ts<Key>, raid reads tsRaid<Key>. The
-- two contexts keep independent options (the raid* keys deliberately live
-- outside the raid/party section-sync system).
local function Setting(raid, key, dflt)
    local s = S()
    if not s then return dflt end
    local v = s[(raid and "tsRaid" or "ts") .. key]
    if v == nil then return dflt end
    return v
end

-------------------------------------------------------------------------------
--  Roster cache: class token (indexed by class for O(1) candidate gather) plus
--  assigned role + race + sex per roster unit.
-------------------------------------------------------------------------------
local rosterByClass = {} -- class file token -> { unitToken, ... }
local rosterRole  = {}   -- unitToken -> "TANK"/"HEALER"/"DAMAGER" (nil if NONE)
local rosterRace  = {}   -- unitToken -> race file token
local rosterSex   = {}   -- unitToken -> 2/3
local lastRosterSync = 0 -- GetTime() of the last rebuild (lazy-rebuild throttle)

local function RebuildRoster()
    wipe(rosterByClass)
    wipe(rosterRole)
    wipe(rosterRace)
    wipe(rosterSex)
    for _, u in ipairs(Units()) do
        local ex = UnitExists(u)
        if not issecret(ex) and ex == true then
            local _, token = UnitClass(u)
            if not issecret(token) and type(token) == "string" then
                local list = rosterByClass[token]
                if not list then list = {}; rosterByClass[token] = list end
                list[#list + 1] = u
            end
            local role = UnitGroupRolesAssigned(u)
            if not issecret(role) and type(role) == "string" and role ~= "NONE" then
                rosterRole[u] = role
            end
            local _, raceToken = UnitRace(u)
            if not issecret(raceToken) and type(raceToken) == "string" then
                rosterRace[u] = raceToken
            end
            local sex = UnitSex(u)
            if not issecret(sex) and type(sex) == "number" then
                rosterSex[u] = sex
            end
        end
    end
    lastRosterSync = GetTime()
end

-- Readable identity classifier. Candidates are gathered by class token (O(1)
-- via rosterByClass), then narrowed by each additional readable attribute
-- (role, race, sex). A narrowing pass applies only when at least one candidate
-- matches the target's value exactly -- and then it ALSO drops candidates whose
-- value is unknown, so a late-cached attribute can never widen the net. If more
-- than one candidate survives every pass the cast is AMBIGUOUS and we show
-- nothing: a false icon teaches hesitation, a missing icon is just the no-addon
-- baseline.
local matchBuf = {}

local function Narrow(targetVal, rosterMap)
    if targetVal == nil or #matchBuf <= 1 then return end
    local exact = 0
    for i = 1, #matchBuf do
        if rosterMap[matchBuf[i]] == targetVal then exact = exact + 1 end
    end
    if exact == 0 then return end  -- attribute unhelpful here; skip
    for i = #matchBuf, 1, -1 do
        if rosterMap[matchBuf[i]] ~= targetVal then
            tremove(matchBuf, i)
        end
    end
end

local function Classify(caster)
    local tgt = caster .. "target"
    local _, cls = UnitClass(tgt)
    if issecret(cls) or type(cls) ~= "string" then return nil end

    wipe(matchBuf)
    local cands = rosterByClass[cls]
    if cands then
        for i = 1, #cands do matchBuf[i] = cands[i] end
    end
    if #matchBuf == 0 then
        -- Stale cache (members/roles learned after the last rebuild). Throttled:
        -- an off-roster target (another enemy, a pet) matches no class and would
        -- otherwise force a full rebuild on every cast.
        if GetTime() - lastRosterSync > 1 then
            RebuildRoster()
            cands = rosterByClass[cls]
            if cands then
                for i = 1, #cands do matchBuf[i] = cands[i] end
            end
        end
        if #matchBuf == 0 then return nil end
    end

    -- Every attribute pass runs unconditionally. Narrow() no-ops cheaply once
    -- the set is down to one, BUT it is also a correctness filter: a pass only
    -- narrows when at least one candidate matches the target's value exactly,
    -- and otherwise leaves the set alone. Skipping a pass after class+role
    -- happen to single out one member (e.g. you + the tank both Paladins, role
    -- = TANK) would show that member without ever checking its race/sex matched
    -- -- which is how same-class twins started false-flagging onto the tank.
    local role = UnitGroupRolesAssigned(tgt)
    if issecret(role) or role == "NONE" then role = nil end
    Narrow(role, rosterRole)

    -- Race/sex on a COMPOUND token are pcall-guarded: some APIs reject compound
    -- tokens outright (UnitGUID does) and that rejection must degrade to
    -- "filter skipped", not an error per cast.
    local okR, _, raceToken = pcall(UnitRace, tgt)
    if not okR or issecret(raceToken) or type(raceToken) ~= "string" then raceToken = nil end
    Narrow(raceToken, rosterRace)

    local okS, sex = pcall(UnitSex, tgt)
    if not okS or issecret(sex) or type(sex) ~= "number" then sex = nil end
    Narrow(sex, rosterSex)

    -- Ambiguity rule: a single confirmed target or nothing at all
    if #matchBuf ~= 1 then return nil end
    return matchBuf
end

-------------------------------------------------------------------------------
--  Icon pool: our frames, parented to the group unit buttons. The buttons
--  themselves are header-created, so per-button state lives in an external
--  weak-keyed table rather than on the button. Each icon/pool remembers its
--  context (icon._tsRaid / icons._raid) so styling reads the right settings.
-------------------------------------------------------------------------------
local buttonIcons = setmetatable({}, { __mode = "k" })  -- btn -> { icon, ... }

local function StyleIcon(icon)
    local raid = icon._tsRaid
    -- Party Auto Resize: ns._partyIndicatorScale is the same factor the
    -- debuff/indicator pipeline multiplies through (1 when the toggle is off).
    -- Raid icons do not auto-resize, so their factor is a fixed 1.
    local k = raid and 1 or (ns._partyIndicatorScale or 1)
    local sz = Setting(raid, "IconSize", 24) * k
    icon:SetSize(sz, sz)
    local z = Setting(raid, "IconZoom", 0.08)
    icon._tex:SetTexCoord(z, 1 - z, z, 1 - z)
    if icon._borderFrame then
        local PP = EllesmereUI and (EllesmereUI.PanelPP or EllesmereUI.PP)
        if PP and PP.UpdateBorder then
            PP.UpdateBorder(icon._borderFrame, 1, 0, 0, 0, 1)
            icon._borderFrame:Show()
        end
    end
end

local function CreateIcon(btn, raid)
    local icon = CreateFrame("Frame", nil, btn)
    icon._tsRaid = raid or false
    -- Keep the icon AND its border (bdr, at icon +1) BELOW the name/health text
    -- carrier (button/preview-frame +12) so the health %/name stays readable
    -- when the icon is positioned over the center of the frame, while the border
    -- still sits above the icon's own texture. Stays above the frame's base
    -- border (+8) so the icon still renders over it.
    icon:SetFrameLevel(btn:GetFrameLevel() + 10)
    icon:Hide()

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon._tex = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.6)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    icon._cooldown = cd

    local bdr = CreateFrame("Frame", nil, icon)
    bdr:SetAllPoints()
    bdr:SetFrameLevel(icon:GetFrameLevel() + 1)
    local PP = EllesmereUI and (EllesmereUI.PanelPP or EllesmereUI.PP)
    if PP and PP.CreateBorder then
        PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
    end
    icon._borderFrame = bdr

    StyleIcon(icon)
    return icon
end

local function AcquireIcon(btn, raid)
    local icons = buttonIcons[btn]
    if not icons then
        icons = {}
        icons._raid = raid or false
        buttonIcons[btn] = icons
    end
    local maxIcons = Setting(raid, "MaxIcons", 3)
    for i = 1, #icons do
        if not icons[i]._tsCaster then return icons[i] end
    end
    if #icons >= maxIcons then return nil end
    local icon = CreateIcon(btn, raid)
    icons[#icons + 1] = icon
    return icon
end

-- 9-point anchor (same position vocabulary as the debuff display). The position
-- key is lowercased on read so pre-rework saved values ("CENTER", "TOP", ...)
-- map onto the new lowercase keys with no migration.
local function Place(icon, host, pos, fx, fy)
    if pos == "topleft" then
        icon:SetPoint("TOPLEFT", host, "TOPLEFT", fx, fy)
    elseif pos == "top" then
        icon:SetPoint("TOP", host, "TOP", fx, fy)
    elseif pos == "topright" then
        icon:SetPoint("TOPRIGHT", host, "TOPRIGHT", fx, fy)
    elseif pos == "left" then
        icon:SetPoint("LEFT", host, "LEFT", fx, fy)
    elseif pos == "right" then
        icon:SetPoint("RIGHT", host, "RIGHT", fx, fy)
    elseif pos == "bottomleft" then
        icon:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", fx, fy)
    elseif pos == "bottom" then
        icon:SetPoint("BOTTOM", host, "BOTTOM", fx, fy)
    elseif pos == "bottomright" then
        icon:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", fx, fy)
    else
        icon:SetPoint("CENTER", host, "CENTER", fx, fy)
    end
end

-- Anchor in-use icons by position + offsets + growth direction, mirroring the
-- debuff AnchorDebuffs pattern: the first shown icon sits at the position point
-- (plus offsets, plus a centering shift for CENTER growth), each subsequent
-- icon chains off the previous one in the growth direction.
local function LayoutButton(btn)
    local icons = buttonIcons[btn]
    if not icons then return end
    local raid = icons._raid
    -- Same Auto Resize factor as StyleIcon (raid = fixed 1); spacing and
    -- offsets scale with it so the multi-icon row keeps its proportions.
    local k = raid and 1 or (ns._partyIndicatorScale or 1)
    local sz = Setting(raid, "IconSize", 24) * k
    local pos = lower(Setting(raid, "Position", "center"))
    local grow = Setting(raid, "GrowDirection", "CENTER")
    local ox = Setting(raid, "OffsetX", 0) * k
    local oy = Setting(raid, "OffsetY", 0) * k
    local anchor = btn._health or btn
    local spc = 2 * k
    local spacing = sz + spc

    local shown = 0
    for i = 1, #icons do
        if icons[i]._tsCaster then shown = shown + 1 end
    end
    if shown == 0 then return end

    -- CENTER growth: shift the first icon so the visible row is centered on the
    -- anchor point (matches AnchorDebuffs)
    local centerOff = 0
    if grow == "CENTER" and shown > 0 then
        centerOff = -((shown - 1) * spacing) / 2
    end

    local prev
    for i = 1, #icons do
        local icon = icons[i]
        if icon._tsCaster then
            icon:ClearAllPoints()
            if not prev then
                Place(icon, anchor, pos, ox + (grow == "CENTER" and centerOff or 0), oy)
            else
                if grow == "RIGHT" or grow == "CENTER" then
                    icon:SetPoint("LEFT", prev, "RIGHT", spc, 0)
                elseif grow == "LEFT" then
                    icon:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
                elseif grow == "UP" then
                    icon:SetPoint("BOTTOM", prev, "TOP", 0, spc)
                else
                    icon:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
                end
            end
            prev = icon
        end
    end
end

-------------------------------------------------------------------------------
--  Active cast tracking
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local gen = {}          -- casterUnit -> generation counter (stale-timer guard)
local activeIcons = {}  -- casterUnit -> { icon, ... } currently shown for it
local tracked = {}      -- casterUnit -> true while a cast is being followed

local function ClearCaster(caster)
    gen[caster] = (gen[caster] or 0) + 1
    tracked[caster] = nil
    local icons = activeIcons[caster]
    if not icons then return end
    activeIcons[caster] = nil
    local touched = {}
    for i = 1, #icons do
        local icon = icons[i]
        icon._tsCaster = nil
        icon:Hide()
        if icon._cooldown then
            icon._cooldown:Clear()
            icon._cooldown:Hide()
        end
        touched[icon:GetParent()] = true
    end
    for btn in pairs(touched) do LayoutButton(btn) end
end

local function ClearAll()
    for caster in pairs(activeIcons) do ClearCaster(caster) end
    wipe(tracked)
end

local function ShowFor(caster, matches, texture, durObj)
    -- Pick the active context's unit->button map. The classifier already
    -- produced tokens in this context (Units()), so they line up with the map.
    local raid = IsInRaid()
    local map = raid and ns._raidUnitToButton or ns._partyUnitToButton
    if not map then return end
    local shownAny = false
    local list
    for _, unitToken in ipairs(matches) do
        local btn = map[unitToken]
        if btn and btn:IsShown() then
            local icon = AcquireIcon(btn, raid)
            if icon then
                icon._tsCaster = caster
                StyleIcon(icon)
                -- texture may be SECRET: SetTexture accepts it natively
                if type(texture) == "nil" then
                    icon._tex:SetTexture(FALLBACK_ICON)
                else
                    icon._tex:SetTexture(texture)
                end
                local cd = icon._cooldown
                -- Swipe is always on (tsShowSwipe setting removed; stale saved
                -- keys persist harmlessly and are ignored)
                if durObj and cd.SetCooldownFromDurationObject then
                    cd:SetCooldownFromDurationObject(durObj)
                    -- Degenerate 0,0 duration objects strobe; mask with alpha
                    if durObj.IsZero and cd.SetAlphaFromBoolean then
                        cd:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
                    else
                        cd:SetAlpha(1)
                    end
                    cd:SetDrawSwipe(true)
                    cd:Show()
                else
                    cd:Clear()
                    cd:Hide()
                end
                icon:Show()
                LayoutButton(btn)
                shownAny = true
                if not list then list = {} end
                list[#list + 1] = icon
            end
        end
    end
    if shownAny then
        activeIcons[caster] = list
    end
end

local function Resolve(caster, myGen)
    if gen[caster] ~= myGen then return end
    -- Re-validate the cast is still running (assign-then-type-check: these
    -- return ZERO values when not casting)
    local castName, _, texture = UnitCastingInfo(caster)
    local channeling = false
    if type(castName) == "nil" then
        castName, _, texture = UnitChannelInfo(caster)
        channeling = true
    end
    if type(castName) == "nil" then return end

    -- Re-check the clean gate now that the target link has settled
    if UnitShouldDisplaySpellTargetName then
        local sd = UnitShouldDisplaySpellTargetName(caster)
        if not issecret(sd) and sd == false then return end
    end

    local matches = Classify(caster)
    if not matches then return end

    -- Changed-set guard: Classify only ever returns a single confirmed token
    -- (ambiguity rule), so the displayed set IS matches[1]. A retarget resolve
    -- with an unchanged target returns here -- no teardown, no flicker.
    local newKey = matches[1]
    local icons = activeIcons[caster]
    if icons and icons.key == newKey then return end

    local durObj
    if channeling then
        durObj = UnitChannelDuration and UnitChannelDuration(caster)
    else
        durObj = UnitCastingDuration and UnitCastingDuration(caster)
    end

    -- A retarget resolve may already have icons up for this caster on the WRONG
    -- frame (engine tank-lock bug, or the mob genuinely swapped target): tear
    -- them down before re-showing.
    if icons then
        activeIcons[caster] = nil
        local touched = {}
        for i = 1, #icons do
            icons[i]._tsCaster = nil
            icons[i]:Hide()
            touched[icons[i]:GetParent()] = true
        end
        for btn in pairs(touched) do LayoutButton(btn) end
    end

    ShowFor(caster, matches, texture, durObj)
    local list = activeIcons[caster]
    if list then list.key = newKey end
    -- No per-cast cleanup timer: STOP/CHANNEL_STOP/INTERRUPTED/plate-removal
    -- clear normally, and PLAYER_REGEN_ENABLED is the combat-end backstop.
end

local function OnCastStart(caster)
    ClearCaster(caster)  -- bumps gen; previous cast's icons die
    -- Enemy casters only: friendly nameplates (followers, NPC allies) also hard
    -- cast at group members and pass the displayable-target gate. Plainly-false
    -- attackability = ally; secret = assume hostile.
    local hostile = UnitCanAttack("player", caster)
    if not issecret(hostile) and hostile ~= true then return end
    -- Clean pre-filter: gate=false at event time means no displayable player
    -- target (AoE channels, self-casts) AND a stale target link.
    if UnitShouldDisplaySpellTargetName then
        local sd = UnitShouldDisplaySpellTargetName(caster)
        if not issecret(sd) and sd == false then return end
    end
    tracked[caster] = true
    local myGen = gen[caster]
    C_Timer.After(PICKUP_DELAY, function() Resolve(caster, myGen) end)
    -- Verify pass: corrects the engine tank-lock bug. Unchanged target =
    -- early return inside Resolve (after a light class[+role]-only Classify).
    C_Timer.After(PICKUP_DELAY + VERIFY_DELAY, function() Resolve(caster, myGen) end)
end

local function OnRetarget(caster)
    if not tracked[caster] then return end
    gen[caster] = (gen[caster] or 0) + 1
    local myGen = gen[caster]
    C_Timer.After(RETARGET_DELAY, function() Resolve(caster, myGen) end)
    C_Timer.After(RETARGET_DELAY + VERIFY_DELAY, function() Resolve(caster, myGen) end)
end

-------------------------------------------------------------------------------
--  Event wiring. While the feature is active (enabled + in a group) the full
--  event set is registered steadily, mirroring the nameplate castDispatcher --
--  no per-cast register/unregister churn. plateTokens is the O(1) reject filter
--  (our local stand-in for the nameplate module's ns.plates, which lives in a
--  separate addon we cannot depend on); it is maintained by the plate add/
--  remove events and seeded from the live plates on activate / loadscreen.
-------------------------------------------------------------------------------
local plateTokens = {}   -- nameplate unit token -> true (O(1) cast filter)
local active = false

local EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_TARGET",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
}

-- Player's current spec is a healer? Live-checked (re-evaluated on
-- PLAYER_SPECIALIZATION_CHANGED) so "When Healing" flips without a /reload.
local function PlayerIsHealer()
    local spec = GetSpecialization and GetSpecialization()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    return role == "HEALER"
end

-- Resolve a 3-state mode (never | whenHealing | always) to an active boolean.
local function ModeActive(mode)
    if mode == "always" then return true end
    if mode == "whenHealing" then return PlayerIsHealer() end
    return false  -- "never" (or unset/unexpected)
end

-- Active in a group, gated by the context's own mode (tsRaidMode in a raid,
-- tsMode in a party; default whenHealing). mode=never -- and whenHealing while
-- not a healer -- both resolve inactive, so UpdateActive registers ZERO cast
-- events (no idle cost). Re-evaluated on spec change via the standing frame.
local function ShouldBeActive()
    local s = S()
    if not s then return false end
    if not IsInGroup() then return false end
    local mode = IsInRaid() and (s.tsRaidMode or "never") or (s.tsMode or "whenHealing")
    return ModeActive(mode)
end

-- A cast can already be in flight when we start watching a plate (it spawned
-- off-camera so no token existed, or the feature just activated). Adopt it
-- through the full gate/resolve flow. (Assign before type-check: zero returns
-- when not casting.)
local function AdoptIfCasting(unit)
    local castName = UnitCastingInfo(unit)
    if type(castName) == "nil" then castName = UnitChannelInfo(unit) end
    if type(castName) ~= "nil" then OnCastStart(unit) end
end

-- Seed plateTokens from plates already up (no ADD event fires for them on
-- activate / loading-screen return) and adopt any in-flight casts.
local function SeedPlates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, p in ipairs(C_NamePlate.GetNamePlates()) do
        local u = p.namePlateUnitToken
        if u and not plateTokens[u] then
            plateTokens[u] = true
            AdoptIfCasting(u)
        end
    end
end

local function UpdateActive()
    local want = ShouldBeActive()
    if want and not active then
        for _, e in ipairs(EVENTS) do ev:RegisterEvent(e) end
        active = true
        RebuildRoster()
        SeedPlates()
    elseif not want and active then
        for _, e in ipairs(EVENTS) do ev:UnregisterEvent(e) end
        active = false
        ClearAll()
        wipe(plateTokens)
    end
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")  -- combat-end backstop (no per-cast timer)
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")  -- re-gate "When Healing" on spec swap
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- A spec change can flip whenHealing on/off; UpdateActive short-circuits
        -- (registers nothing) when the resolved mode is still inactive.
        UpdateActive()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        -- Tokens shift on roster changes; identities must be re-learned
        RebuildRoster()
        ClearAll()
        UpdateActive()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Loading screens tear down nameplates; reset and re-seed (ADD events do
        -- not re-fire for plates already up on a /reload).
        ClearAll()
        wipe(plateTokens)
        UpdateActive()
        if active then SeedPlates() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        ClearAll()
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        plateTokens[unit] = true
        AdoptIfCasting(unit)
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        plateTokens[unit] = nil
        ClearCaster(unit)
        return
    end
    -- Cast / retarget events: O(1) plate-token reject (replaces the regex).
    -- UNIT_TARGET fires for every unit; non-plate tokens reject here instantly.
    if not plateTokens[unit] then return end
    if event == "UNIT_TARGET" then
        OnRetarget(unit)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        OnCastStart(unit)
    else
        -- STOP / CHANNEL_STOP / INTERRUPTED
        ClearCaster(unit)
    end
end)

-------------------------------------------------------------------------------
--  Options hooks + preview
--
--  The party and raid previews are independent mirrors of the real frames:
--  each shows two icons (on preview members 2 and 3) with looping random
--  duration swipes, gated by its section eyeball (ns._tsPreviewVisible /
--  ns._tsRaidPreviewVisible, reset on tab change like the other aura eyeballs).
-------------------------------------------------------------------------------
local PV_HOSTS = { 2, 3 }
local PV_TEX = { 135807, 136197 }  -- fireball / shadow bolt

-- Shared 0.5s preview tick (same cadence as the debuff preview aura ticker):
-- when an icon's random swipe expires, re-arm it with a fresh random duration.
local function PreviewTick(icons)
    local now = GetTime()
    for i = 1, #icons do
        local icon = icons[i]
        if icon and icon._tsCaster and icon._cooldown then
            if not icon._pvExp or icon._pvExp <= now then
                local dur = random(4, 12)
                icon._pvExp = now + dur
                icon._cooldown:SetCooldown(now, dur)
                icon._cooldown:Show()
            end
        end
    end
end

-- ---- Party preview --------------------------------------------------------
local pvIcons = {}
local pvTicker

local function StopPvTicker()
    if pvTicker then
        pvTicker:Cancel()
        pvTicker = nil
    end
end

local function PvTick()
    if not ns._partyPvActive then
        StopPvTicker()
        return
    end
    PreviewTick(pvIcons)
end

function ns.TS_RefreshPreview()
    -- Preview reads route through the real-preview effective overlay when a
    -- panel view swap is active (falls back to live settings otherwise).
    local s = (ns.PvEffectiveProfile and ns.PvEffectiveProfile()) or S()
    local frames = ns._partyPvFrames
    local on = ns._partyPvActive and frames and ns._tsPreviewVisible
        and s and (s.tsMode or "whenHealing") ~= "never"
    if not on then
        StopPvTicker()
        for i = 1, #pvIcons do
            pvIcons[i]._tsCaster = nil
            pvIcons[i]._pvExp = nil
            pvIcons[i]:Hide()
        end
        return
    end
    -- Preview mirrors the real frames 1:1: same scale factor, Place() anchor
    -- and offsets.
    local k = ns._partyIndicatorScale or 1
    local pos = lower((s and s.tsPosition) or "center")
    local ox = ((s and s.tsOffsetX) or 0) * k
    local oy = ((s and s.tsOffsetY) or 0) * k
    for i = 1, #PV_HOSTS do
        local host = frames[PV_HOSTS[i]]
        local icon = pvIcons[i]
        if host then
            if not icon or icon:GetParent() ~= host then
                if icon then icon:Hide() end
                icon = CreateIcon(host)
                pvIcons[i] = icon
            end
            icon._tsCaster = "preview"
            StyleIcon(icon)
            icon._tex:SetTexture(PV_TEX[i])
            icon:ClearAllPoints()
            Place(icon, host._health or host, pos, ox, oy)
            icon._pvExp = nil  -- force a fresh random swipe on next tick
            icon:Show()
        elseif icon then
            icon._tsCaster = nil
            icon._pvExp = nil
            icon:Hide()
        end
    end
    PvTick()
    if not pvTicker then
        pvTicker = C_Timer.NewTicker(0.5, PvTick)
    end
end

-- ---- Raid preview ---------------------------------------------------------
-- Raid preview state (active flag + frames) lives behind ns._TSRaidPvState in
-- the main RaidFrames file (previewActive/previewFrames are file-locals there).
local rPvIcons = {}
local rPvTicker

local function StopRPvTicker()
    if rPvTicker then
        rPvTicker:Cancel()
        rPvTicker = nil
    end
end

local function RPvTick()
    local active = ns._TSRaidPvState and ns._TSRaidPvState()
    if not active then
        StopRPvTicker()
        return
    end
    PreviewTick(rPvIcons)
end

function ns.TS_RefreshRaidPreview()
    -- Same effective-overlay routing as TS_RefreshPreview above.
    local s = (ns.PvEffectiveProfile and ns.PvEffectiveProfile()) or S()
    local active, frames
    if ns._TSRaidPvState then active, frames = ns._TSRaidPvState() end
    local on = active and frames and ns._tsRaidPreviewVisible
        and s and (s.tsRaidMode or "never") ~= "never"
    if not on then
        StopRPvTicker()
        for i = 1, #rPvIcons do
            rPvIcons[i]._tsCaster = nil
            rPvIcons[i]._pvExp = nil
            rPvIcons[i]:Hide()
        end
        return
    end
    -- Raid icons do not auto-resize (factor 1), so offsets are used raw.
    local pos = lower((s and s.tsRaidPosition) or "center")
    local ox = (s and s.tsRaidOffsetX) or 0
    local oy = (s and s.tsRaidOffsetY) or 0
    for i = 1, #PV_HOSTS do
        local host = frames[PV_HOSTS[i]]
        local icon = rPvIcons[i]
        if host then
            if not icon or icon:GetParent() ~= host then
                if icon then icon:Hide() end
                icon = CreateIcon(host, true)
                rPvIcons[i] = icon
            end
            icon._tsCaster = "preview"
            StyleIcon(icon)
            icon._tex:SetTexture(PV_TEX[i])
            icon:ClearAllPoints()
            Place(icon, host._health or host, pos, ox, oy)
            icon._pvExp = nil
            icon:Show()
        elseif icon then
            icon._tsCaster = nil
            icon._pvExp = nil
            icon:Hide()
        end
    end
    RPvTick()
    if not rPvTicker then
        rPvTicker = C_Timer.NewTicker(0.5, RPvTick)
    end
end

-- Called from the options section after any setting change
function ns.TS_ApplySettings()
    UpdateActive()
    for btn, icons in pairs(buttonIcons) do
        local any = false
        for i = 1, #icons do
            if icons[i]._tsCaster then
                StyleIcon(icons[i])
                any = true
            end
        end
        if any then LayoutButton(btn) end
    end
    ns.TS_RefreshPreview()
    ns.TS_RefreshRaidPreview()
end
