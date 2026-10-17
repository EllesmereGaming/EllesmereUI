if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_PetSummon.lua  (WoW Forever only)
--  Auto Summon Pet: once the game takes the companion pet away (death,
--  loading screen, taxi, vehicle...), summons one again a moment later: a
--  random favorite, or any random pet while none is a favorite, as the
--  journal's random pet button. A pet the player dismisses (Dismiss, or its
--  journal toggle) stays dismissed until they summon one again. Never in
--  combat, dungeons, raids, PvP, stealth or while mounted.
--
--  Favorites per Character (a per-character setting): this character picks
--  among its own favorites instead of the account's. They are chosen from a
--  pet's right-click menu in the Pet Journal and marked with a blue star in
--  its list. While it has none, the account's favorites are used.
--
--  Summoning is plain API, refused in combat only. The player's dismissals
--  are the two calls read from hooksecurefunc; one from an action bar runs
--  in the client, so that pet comes back at the next of the events below.
--  Events and hooks only exist once the feature has been on.
-------------------------------------------------------------------------------
local _, module = ...
local DELAY = 2  -- seconds after a trigger: lets a load, landing or resurrection settle
local STAR = "PetJournal-FavoritesIcon"   -- the journal's favorite star, tinted blue below

-- Settings live in EllesmereUIDB.petSummon; unset keys read these.
--   enabled                 Auto Summon Pet
--   chars[player GUID]      own = Favorites per Character, favorites = { [pet GUID] = true },
--                           dismissed = the player put the pet away (until they summon one)
local F = module.Feature("petSummon", { enabled = false })
local IsEnabled = F.Enabled

-- This character's settings; nil until written, unless create.
local function CharCfg(create)
    local cfg = create and F.Cfg() or F.Read()
    local guid = UnitGUID("player")
    if not guid then return nil end
    if create then
        cfg.chars = cfg.chars or {}
        cfg.chars[guid] = cfg.chars[guid] or {}
    end
    return cfg.chars and cfg.chars[guid]
end

local function OwnOn()
    local c = CharCfg()
    return c ~= nil and c.own == true  -- default OFF
end

local function IsOwnFavorite(petGUID)
    local c = CharCfg()
    return petGUID ~= nil and c ~= nil and c.favorites ~= nil and c.favorites[petGUID] == true
end

local function SetOwnFavorite(petGUID, on)
    local c = CharCfg(true)
    c.favorites = c.favorites or {}
    c.favorites[petGUID] = on or nil
end

-- This character's favorites that can be summoned (empty: use the account's).
local function OwnFavorites()
    local list = {}
    local c = CharCfg()
    if not (c and c.own and c.favorites) then return list end
    for petGUID in pairs(c.favorites) do
        if C_PetJournal.PetIsSummonable(petGUID) then list[#list + 1] = petGUID end
    end
    return list
end

local ev = CreateFrame("Frame")
local timer
local hooked = false
local userDismissed = false  -- the player put the pet away themselves (also kept per character)
local current          -- the pet we last saw out (nil: none)

-- The dismissal outlives a reload or a relog: written only when it changes.
local function SetDismissed(on)
    if userDismissed == on then return end
    userDismissed = on
    local c = CharCfg(on)
    if c then c.dismissed = on or nil end
end

local function CanSummonNow()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
       or UnitInVehicle("player") or IsMounted() or IsStealthed() then
        return false
    end
    local _, kind = IsInInstance()
    return kind ~= "party" and kind ~= "raid" and kind ~= "pvp" and kind ~= "arena"
end

local Queue

-- Each blocker above has an event that queues again once it lifts; combat
-- waits for its end on the combat queue.
local function Summon()
    timer = nil
    if not IsEnabled() or userDismissed or C_PetJournal.GetSummonedPetGUID() then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("PetSummon", Queue)
        return
    end
    if not CanSummonNow() then return end
    -- A cast or a channel (a fishing line): again once it stops.
    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        return
    end
    local own = OwnFavorites()
    if #own > 0 then
        C_PetJournal.SummonPetByGUID(own[math.random(#own)])
    else
        -- As the journal's random pet button: all pets while none is a favorite.
        C_PetJournal.SummonRandomPet(C_PetJournal.HasFavoritePets())
    end
end

Queue = function()
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(DELAY, Summon)
end

-- After which a missing pet may come back (COMPANION_UPDATE: the pet out).
local EVENTS = {
    "COMPANION_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE",
    "PLAYER_UNGHOST", "PLAYER_CONTROL_GAINED", "UNIT_EXITED_VEHICLE",
    "UPDATE_STEALTH", "PLAYER_MOUNT_DISPLAY_CHANGED",
}

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMPANION_UPDATE" then
        if arg1 == "MOUNT" then return end
        -- Also fires for other players' pets: only ours is read.
        local guid = C_PetJournal.GetSummonedPetGUID()
        current = guid
        if guid then SetDismissed(false) end
        return
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ev:UnregisterEvent("UNIT_SPELLCAST_STOP")
        ev:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    elseif event == "UNIT_EXITED_VEHICLE" and arg1 ~= "player" then
        return
    end
    if not userDismissed then Queue() end
end)

-- The player's own dismissals: DismissSummonedPet, or SummonPetByGUID on the
-- pet out (the journal's toggle). The pet out is the one we last saw: the
-- post-hook may run once it is gone.
local function OnDismiss() SetDismissed(true) end
local function OnSummonByGUID(guid)
    if guid and guid == current then SetDismissed(true) end
end

-------------------------------------------------------------------------------
--  Pet Journal: this character's favorites
-------------------------------------------------------------------------------
local function ShowsOwn() return IsEnabled() and OwnOn() end

-- The blue star on a list button, beside the journal's own; kept in a weak
-- table, nothing is stored on the journal's buttons.
local stars = setmetatable({}, { __mode = "k" })
local function MarkListButton(button)
    local drag = button and button.dragButton
    if not drag then return end
    local on = ShowsOwn() and IsOwnFavorite(button.petID)
    local star = stars[drag]
    if on and not star then
        star = drag:CreateTexture(nil, "OVERLAY", nil, 2)
        star:SetAtlas(STAR, true)
        star:SetVertexColor(0.45, 0.8, 1)
        star:SetPoint("TOPRIGHT", 8, 8)
        stars[drag] = star
    end
    if star then star:SetShown(on) end
end

-- The stars of the buttons on screen, read from the list without asking the
-- journal to rebuild it.
local function RefreshJournal()
    local scroll = PetJournal and PetJournal:IsShown() and PetJournal.ScrollBox
    if scroll and scroll.ForEachFrame then scroll:ForEachFrame(MarkListButton) end
end

-- A pet's right-click menu. The owner is its list button or the pet card,
-- whose petID is the owned pet's GUID, or the list button's icon, whose
-- parent holds it (PetJournal_ShowPetDropdown; the menu passes no context).
local function AddMenuEntry(owner, root)
    local petGUID = owner and (owner.petID or (owner.GetParent and owner:GetParent()
        and owner:GetParent().petID))
    if not (petGUID and ShowsOwn()) then return end
    root:CreateDivider()
    root:CreateCheckbox(EllesmereUI.L("Favorite for This Character"),
        function() return IsOwnFavorite(petGUID) end,
        function()
            SetOwnFavorite(petGUID, not IsOwnFavorite(petGUID))
            RefreshJournal()
        end)
end

local journalHooked = false
local function HookJournal()
    if journalHooked or not PetJournal_InitPetButton then return end
    journalHooked = true
    hooksecurefunc("PetJournal_InitPetButton", MarkListButton)
end

local function HookPetJournal()
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_PET_COLLECTION_PET", AddMenuEntry)
    end
    -- The journal loads on demand (Blizzard_Collections).
    if PetJournal_InitPetButton then
        HookJournal()
    else
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_Collections" then return end
            self:UnregisterAllEvents()
            HookJournal()
        end)
    end
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
-- Login and the options toggles; takes effect immediately in both directions.
-- fresh: the player just turned it on, which also ends an earlier dismissal.
local function ApplyPetSummon(fresh)
    if not C_PetJournal then return end
    RefreshJournal()
    local on = IsEnabled()
    for i = 1, #EVENTS do
        if on then ev:RegisterEvent(EVENTS[i]) else ev:UnregisterEvent(EVENTS[i]) end
    end
    if not on then
        ev:UnregisterEvent("UNIT_SPELLCAST_STOP")
        ev:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        if timer then timer:Cancel(); timer = nil end
        return
    end
    if not hooked then
        hooked = true
        hooksecurefunc(C_PetJournal, "DismissSummonedPet", OnDismiss)
        hooksecurefunc(C_PetJournal, "SummonPetByGUID", OnSummonByGUID)
        HookPetJournal()
    end
    current = C_PetJournal.GetSummonedPetGUID()
    -- A dismissal from an earlier session holds until a pet is out again.
    local c = CharCfg()
    if c and c.dismissed and (current or fresh) then c.dismissed = nil end
    userDismissed = (c and c.dismissed) and true or false
    Queue()
end
-- Options-page entry points. Favorites per Character changed: only the
-- journal's stars and menu follow (RefreshJournal).
EllesmereUI._PetSummon = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = ApplyPetSummon,
    RefreshJournal = RefreshJournal,
}

F.Start(ApplyPetSummon)
