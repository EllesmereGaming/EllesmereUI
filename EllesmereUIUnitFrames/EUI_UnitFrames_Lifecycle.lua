if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Lifecycle.lua
--
--  The addon object (OnInitialize creates the DB and runs I.dbSetters,
--  OnEnable builds through EnableBody) and the load-time blocks after it:
--  Boss Frame Range Dimming, Player Dispel Overlay helpers, Party Mode.
--  Loads before PlayerAuraBars/ForeverImbues/AuraContainers (event order).
-------------------------------------------------------------------------------
local _, ns = ...

local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local issecretvalue = issecretvalue

local I = ns._internals
local frames, defaults, ResolveFontPath = I.frames, I.defaults, I.ResolveFontPath
local healthBarTextureNames, healthBarTextureOrder, healthBarTextures =
    I.healthBarTextureNames, I.healthBarTextureOrder, I.healthBarTextures
local RegisterUFUnlockElements = I.RegisterUFUnlockElements
local db -- assigned by EllesmereUF:OnInitialize below, no setter

local EllesmereUF = EllesmereUI.Lite.NewAddon("EllesmereUIUnitFrames")

function EllesmereUF:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIUnitFramesDB", defaults, true)
    for i = 1, #ns._internals.dbSetters do ns._internals.dbSetters[i](db) end

    -- A fresh install starts Target of Target on the Target frame's look; a
    -- profile from an earlier version keeps Automatic (no lookSource). Written
    -- here, not a default: the logout strip drops a value equal to its default.
    if EllesmereUI._firstInstallPending then
        local tot = db.profile.targettarget
        if tot and tot.lookSource == nil then tot.lookSource = "target" end
    end

    ResolveFontPath()

    -- Append SharedMedia textures to runtime tables so SM texture keys resolve
    EllesmereUI.AppendSharedMediaTextures(
        healthBarTextureNames,
        healthBarTextureOrder,
        nil,
        healthBarTextures
    )

    -- Blizzard options panel is registered centrally in EllesmereUI.lua
end

-- Enable-body router. OnEnable runs under the parent addon's lifecycle dispatch, and
-- the engine bills a script handler's whole call tree to the addon whose execution
-- context created the entry frame -- so every frame born inside the build (oUF
-- buttons, event drivers, castbar watchers) would bill the PARENT's CPU row forever.
-- Routing the body through this file-scope frame's PLAYER_LOGIN handler runs the
-- build in this child's context instead. Ordering is safe: the parent's lifecycle
-- frame registered PLAYER_LOGIN first (parent loads before children), so OnEnable has
-- always set the pending flag by the time this frame's handler fires -- within the
-- SAME event dispatch, still inside the combat-reload pre-lockdown window.
local function EnableBody()
    -- A profile already on a stock style gets its seeds before the frames
    -- build (the Style page seeds on the switch); a profile none of them has
    -- reached yet keeps its own values in the EllesmereUI slot first, so a
    -- switch back restores them.
    if ns.UF_Blizz() then
        local p = db.profile
        if p.stockCastTextureSeeded == nil and p.classicTextureSeeded == nil
            and p.stockCombatSeededStyle == nil and EllesmereUI.BankEuiStyleSlot then
            EllesmereUI.BankEuiStyleSlot(p, ns.UF_StyleSlotKeys())
        end
        -- WoW Forever's own seed the same way: the other looks' class
        -- resource goes to its Forever-only slot first.
        if ns.UF_Forever() and not p.foreverClassPowerSeeded and p.player then
            local s = p._foreverStyleSlots
            if type(s) ~= "table" then s = {}; p._foreverStyleSlots = s end
            s.eui = { ["player.classPowerStyle"] = p.player.classPowerStyle,
                      ["player.showClassPowerBar"] = p.player.showClassPowerBar }
        end
        ns.UF_SeedStock(p, ns.UF_Style(), ns.UF_Forever())
    end
    InitializeFrames()
    -- Register with unlock mode synchronously: on a combat reload this runs
    -- inside the pre-lockdown window, so the login position pass can resolve
    -- and place anchored unit frames before SetPoint gets blocked.
    RegisterUFUnlockElements()
    -- The parent's synchronous PLAYER_LOGIN position pass (EUI_UnlockMode) fires BEFORE
    -- this router drains, so unit frame elements were not yet registered when it ran.
    -- Re-fire it now -- still inside the same PLAYER_LOGIN dispatch, so anchored unit
    -- frames are placed within the combat-reload pre-lockdown window. The pass is
    -- re-entrant by design (CDM and the PEW fallback both re-fire it).
    if EllesmereUI and EllesmereUI._applySavedPositions then
        EllesmereUI._applySavedPositions()
    end
    C_Timer.After(0, SetupOptionsPanel)
    C_Timer.After(0, function()
        EllesmereUI.ApplyColorsToOUF()
        -- Restore the threat watchers saved enabled (nothing registers when off).
        ns.SyncPlayerThreat()
        if ns.SyncThreatPct then ns.SyncThreatPct() end
    end)
end

do
    local loginFired = false
    local router = CreateFrame("Frame")
    router:RegisterEvent("PLAYER_LOGIN")
    -- Backstop only: PLAYER_LOGIN always fires for a startup-loaded addon,
    -- but if it were ever missed the next world entry drains the flag.
    router:RegisterEvent("PLAYER_ENTERING_WORLD")
    router:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        loginFired = true
        if ns._eufEnablePending then
            ns._eufEnablePending = nil
            EnableBody()
        end
    end)

    function EllesmereUF:OnEnable()
        if loginFired then
            -- Runtime re-enable long after login: run directly (rare; any
            -- parent-context billing lasts only until the next reload).
            EnableBody()
        else
            ns._eufEnablePending = true
        end
        -- Incompatible addon detection is handled globally by EllesmereUI
    end
end

-- Called by EUI_UnlockMode.lua's Grow Direction dropdown for barKey ==
-- "PAB_Buffs" / "PAB_Debuffs". Thin delegation to
-- EllesmereUIUnitFrames_PlayerAuraBars.lua's ns.PAB_Get/SetGrowDirection so
-- the settings field names stay defined in exactly one file.

function EllesmereUF:GetGrowDirectionForBar(barKey)
    return ns.PAB_GetGrowDirection and ns.PAB_GetGrowDirection(barKey)
end

function EllesmereUF:SetGrowDirectionForBar(barKey, dir)
    if ns.PAB_SetGrowDirection then
        ns.PAB_SetGrowDirection(barKey, dir)
    end
end

-------------------------------------------------------------------------------
--  Boss Frame Range Dimming. Boss units sit outside UnitInRange's group-member
--  domain, so range is measured against a known spell instead: a harm spell for
--  attackable bosses (all specs, first known spell in the class chain wins), or
--  the class baseline heal for friendly bosses (healer specs only). Whole-frame
--  alpha follows db.profile.boss.oorAlpha; 100% means no fade and the check
--  short-circuits. The ticker exists only while a boss frame is shown.
--  (do-block: no persistent file-level locals.)
-------------------------------------------------------------------------------
do
    local HARM_CHAIN = {
        DEATHKNIGHT = { 49576, 47541 },           -- Death Grip, Death Coil
        DEMONHUNTER = { 185123, 183752, 204021 }, -- Throw Glaive, Consume Magic, Fiery Brand
        DRUID       = { 8921, 5176, 6795 },       -- Moonfire, Wrath, Growl
        EVOKER      = { 362969 },                 -- Azure Strike (25yd native)
        HUNTER      = { 75, 466930, 190925 },     -- Auto Shot, Black Arrow, Harpoon
        MAGE        = { 116, 133, 44425, 118 },   -- Frostbolt, Fireball, Arcane Barrage, Polymorph
        MONK        = { 117952, 115546 },         -- Crackling Jade Lightning, Provoke
        PALADIN     = { 20271, 62124 },           -- Judgment, Hand of Reckoning
        PRIEST      = { 589, 585, 8092 },         -- Shadow Word: Pain, Smite, Mind Blast
        ROGUE       = { 36554, 185763, 2094 },    -- Shadowstep, Pistol Shot, Blind
        SHAMAN      = { 188196, 370 },            -- Lightning Bolt, Purge
        WARLOCK     = { 234153, 232670, 686, 348, 172, 5782 }, -- Drain Life, Shadow Bolt (both ids), Immolate, Corruption, Fear
        WARRIOR     = { 355, 100 },               -- Taunt, Charge
    }
    local HELP_HEAL = {
        PRIEST = 2061, PALADIN = 19750, SHAMAN = 8004,
        DRUID = 8936, MONK = 116670, EVOKER = 361469,
    }

    local harmSpell, helpSpell
    local visCount, ticker = 0, nil

    local function Known(sid)
        if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank then
            return C_SpellBook.IsSpellInSpellBook(sid, Enum.SpellBookSpellBank.Player, true)
        end
        return IsSpellKnown and IsSpellKnown(sid)
    end

    local function ResolveRangeSpells()
        harmSpell, helpSpell = nil, nil
        local _, pClass = UnitClass("player")
        for _, sid in ipairs(HARM_CHAIN[pClass] or {}) do
            if Known(sid) then harmSpell = sid; break end
        end
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role == "HEALER" then helpSpell = HELP_HEAL[pClass] end
        -- WoW Forever has no spec roles: a healing class counts as its healing
        -- spec and range-checks with its best heal in the spellbook.
        if EllesmereUI.IS_FOREVER then
            local list = EllesmereUI.FOREVER_HEAL_SPELLS[pClass]
            for i = 1, (list and #list or 0) do
                if Known(list[i]) then helpSpell = list[i]; break end
            end
        end
    end

    local function TickOne(f, unit)
        if not db then return end
        local oor = (db.profile.boss and db.profile.boss.oorAlpha) or 0.4
        if oor >= 1 or not UnitExists(unit) then
            f:SetAlpha(1)
            return
        end
        local spell
        if UnitCanAttack("player", unit) then
            spell = harmSpell
        else
            spell = helpSpell
        end
        if spell then
            -- Secret-safe: the result may be secret in instances, which
            -- SetAlphaFromBoolean accepts natively -- but it can also be NIL
            -- (unit not range-checkable right now / spell momentarily not
            -- evaluable), which it rejects. issecretvalue runs first so the
            -- nil check never touches a secret.
            local inRange = C_Spell.IsSpellInRange(spell, unit)
            if issecretvalue(inRange) or inRange ~= nil then
                f:SetAlphaFromBoolean(inRange, 1, oor)
            else
                f:SetAlpha(1)
            end
        else
            f:SetAlpha(1)
        end
    end

    local function Tick()
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f and f:IsVisible() then TickOne(f, "boss" .. i) end
        end
    end

    local function UpdateTicker()
        local want = visCount > 0
        if want and not ticker then
            ticker = C_Timer.NewTicker(0.4, Tick)
        elseif not want and ticker then
            ticker:Cancel()
            ticker = nil
        end
    end

    local hooked = false
    local function InstallHooks()
        if hooked or not frames["boss1"] then return end
        hooked = true
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f then
                local unit = "boss" .. i
                if f:IsVisible() then visCount = visCount + 1 end
                f:HookScript("OnShow", function(self)
                    visCount = visCount + 1
                    TickOne(self, unit)
                    UpdateTicker()
                end)
                f:HookScript("OnHide", function(self)
                    visCount = math.max(0, visCount - 1)
                    self:SetAlpha(1)
                    UpdateTicker()
                end)
            end
        end
        UpdateTicker()
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:SetScript("OnEvent", function()
        ResolveRangeSpells()
        InstallHooks()
    end)
end

-------------------------------------------------------------------------------
--  Player Dispel Overlay (player frame only, health bar only). The 12.1
--  container dispel slots render it (EUI_UnitFrames_AuraContainers.lua); this
--  block keeps what the slots ask the module for: the racial / talent dispel
--  knowledge the RAID_PLAYER_DISPELLABLE token is blind to, and the
--  options-side poke that re-drives the slots after a color or toggle edit.
--  (do-block: no persistent file-level locals.)
-------------------------------------------------------------------------------
do

    -- RAID_PLAYER_DISPELLABLE only knows class and spec dispels, so it answers no for
    -- every bleed: nothing a class learns removes one, only the dwarf racial does.
    -- Without this, "Only Dispellable by You" can never light up for a bleed, for
    -- anyone. A racial cleans its own caster, so this is the player frame's business
    -- alone. Bleed only, deliberately: Stoneform also clears poison/disease/curse, but
    -- a class that dispels those already passes the token, and treating a two-minute
    -- racial as a dispel would overlay most of what a dwarf ever catches.
    local RACIAL_DISPEL_TYPES = {
        bleed = { Dwarf = true },  -- Stoneform
    }
    -- The token is equally blind to talent dispels: a shaman's poison removal is
    -- Poison Cleansing Totem, so Poison never passes for them. Raid Frames applies
    -- the same rule to its group-wide dispel slots (EUI_RaidFrames_AuraContainers.lua).
    -- Cached: IsPlayerSpell can lag both addon load and the trait event that
    -- announces a change; the shaman watcher in EUI_UnitFrames_AuraContainers.lua
    -- calls UF_RefreshPoisonTotem on trait and spellbook events and reloads the
    -- dispel slots when it reports a flip.
    local POISON_CLEANSING_TOTEM = 383013
    local _, ufPlayerClass = UnitClass("player")
    local poisonTotemKnown = ufPlayerClass == "SHAMAN"
        and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
    function ns.UF_RefreshPoisonTotem()
        local known = ufPlayerClass == "SHAMAN"
            and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
        if known == poisonTotemKnown then return false end
        poisonTotemKnown = known
        return true
    end
    -- Shared with the 12.1 container slots (EUI_UnitFrames_AuraContainers.lua),
    -- which apply the same rule by choosing which slot style stays visible.
    function ns.UF_TokenBlindDispel(typeKey)
        local races = RACIAL_DISPEL_TYPES[typeKey]
        if races then
            local _, raceToken = UnitRace("player")
            return raceToken ~= nil and races[raceToken] == true
        end
        if typeKey == "poison" then
            return poisonTotemKnown
        end
        return false
    end

    ns.UpdatePlayerDispelOverlay = function()
        -- The container dispel slots own the overlay; poke their fingerprinted
        -- reload so dropdown/cog edits apply live instead of waiting for the
        -- next full container pass.
        if ns.UF_ReloadPlayerDispelSlots then
            ns.UF_ReloadPlayerDispelSlots()
        end
    end
end

-------------------------------------------------------------------------------
--  Party Mode: spinning unit frames. Every EUI unit frame (player, target,
--  focus, pet, target-of-target, focus target, boss) orbits the centre of the
--  screen, so player and target swing round each other like a carousel.
--  Unit frames are secure, so this pauses in combat exactly like the action
--  bar spin. Driver and rest tracking live in the shared engine
--  (EllesmereUI.PartySpin_Create, EllesmereUI_PartyMode.lua).
-------------------------------------------------------------------------------
do
    local list = {}
    local groups = { { pivot = UIParent, frames = list } }
    EllesmereUI.PartySpin_Create({
        target = "unitFrames",
        collect = function()
            wipe(list)
            for _, f in pairs(frames) do
                if type(f) == "table" and f.GetCenter then list[#list + 1] = f end
            end
            return groups
        end,
    })
end

-- Party Mode visibility axis (Visibility > Party Mode): no game event, so the
-- core fires its own edge (re-fired after combat for the secure frames).
if EllesmereUI.RegisterVisEdge then
    EllesmereUI.RegisterVisEdge(function()
        if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
    end)
end
