if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin.lua
--  Umbrella addon for themed Blizzard UI frames. Hosts the Character Sheet
--  rework (EllesmereUIBlizzardSkin_CharacterSheet.lua) plus the tooltip,
--  context menu and static popup reskinning (EUI_BlizzardSkin_*.lua).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewInternals and EllesmereUI.NewCombatQueue and EllesmereUI.FriendsKit and EllesmereUI.CreateQuantityDialog and EllesmereUI.NewFrameData) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (FriendsForever reads the parent's friends kit, Merchant Bulk Buy its quantity window)
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD, GetFFD = EllesmereUI.NewFrameData()

-------------------------------------------------------------------------------
--  Per-window skin style ("eui"|"modern"|"blizzard"|"off"). Enable keys are
--  the on/off source of truth (key false = "off"); blizzWindowSkinStyles only
--  records WHICH style an enabled window uses (nil = "eui"). "blizzard" is the
--  Character Sheet's Blizz Default: Blizzard's own sheet with the EllesmereUI
--  stats, slot text and socket panel. Its "off" leaves the sheet untouched.
-------------------------------------------------------------------------------
local WINDOW_ENABLE_KEYS = {
    charsheet       = "themedCharacterSheet",
    inspect         = "themedInspectSheet",
    lfg             = "reskinLFGMenu",
    greatvault      = "reskinGreatVault",
    collections     = "reskinCollections",
    playerspells    = "reskinPlayerSpells",
    adventureguide  = "reskinAdventureGuide",
    professionsbook = "reskinProfessionsBook",
    guild           = "reskinGuild",
    calendar        = "reskinCalendar",
    achievements    = "reskinAchievements",
    mail            = "reskinMail",
    catalyst        = "reskinCatalyst",
    socket          = "reskinSocket",
    itemupgrade     = "reskinItemUpgrade",
    loot            = "reskinLoot",
    loottoast       = "reskinLootToast",
    bnettoast       = "reskinBNetToast",
    lootroll        = "reskinLootRoll",
    loothistory     = "reskinLootHistory",
    groupinvite     = "reskinGroupInvite",
    readycheck      = "reskinReadyCheck",
    micromenu       = "reskinMicroMenu",
    housing         = "reskinHousing",
    professions     = "reskinProfessions",
    worldmap        = "reskinWorldMap",
    dressup         = "reskinDressUp",
    transmog        = "reskinTransmog",
    merchant        = "reskinMerchant",
    auctionhouse    = "reskinAuctionHouse",
    macros          = "reskinMacros",
    settings        = "reskinSettings",
    addonlist       = "reskinAddonList",
    craftorders     = "reskinCraftOrders",
    trainer         = "reskinTrainer",
    gossip          = "reskinGossip",
    quest           = "reskinQuest",
    inspectrecipe   = "reskinInspectRecipe",
    delves          = "reskinDelves",
    socialui        = "reskinSocialUI",
    -- delvepicker is the Delves TIER PICKER, a separate frame from the
    -- companion configuration window that `delves` above covers.
    queuestatus     = "reskinQueueStatus",
    delvepicker     = "reskinDelvePicker",
    playerchoice    = "reskinPlayerChoice",
    trade           = "reskinTrade",
}
-- WoW Forever's own windows: the bag bar and Progress Legacy skins exist only there.
if EllesmereUI.IS_FOREVER then
    WINDOW_ENABLE_KEYS.bagbar       = "reskinBagBar"
    WINDOW_ENABLE_KEYS.legacysystem = "reskinLegacySystem"
end
--- Master PER-PROFILE kill switch for ALL Blizzard window skinning: window engine
--- + every pack, plus CharacterSheet/Inspect, SocketPanel, LFG skins. Lives at
--- profiles[name].disableWindowSkins, resolved live (follows profile switches,
--- rides exports); nil/false = enabled. Per-window enable keys and style picks are
--- PRESERVED while killed. Skins install at load, so crossings need a reload
--- (callers show the popup). Queue Popup, Pause Menu, and Dragon Riding are not windows and stay untouched.
function EllesmereUI.BlizzWindowSkinsKilled()
    local prof = EllesmereUI.GetActiveProfileData()
    return (prof and prof.disableWindowSkins) and true or false
end

-- WoW Forever's Gamepad interface style shows, hides and navigates Blizzard's
-- windows, popups and tooltips from its own secure code and makes protected
-- calls in the same execution, so a script hook of ours on those frames taints
-- that path (ADDON_ACTION_FORBIDDEN, and the blocked-action popup's gamepad
-- handling can loop until the client freezes). Under that style the Blizzard
-- frame skins stand down for the session, like the bags and the Shifter.
-- Decided at the first call once logged in; false on retail.
local _padStandDown
function EllesmereUI.BlizzSkinPadStandDown()
    if _padStandDown ~= nil then return _padStandDown end
    local v = EllesmereUI.PadGamepadUI()
    if IsLoggedIn() then _padStandDown = v end
    return v
end

-------------------------------------------------------------------------------
--  One-time style seed for window keys added after the fact: each adopts
--  whichever style (EUI/Modern/off) the user already runs MOST windows with,
--  instead of defaulting ON in EUI. Counts RAW stored state (not GetBlizzWindowStyle)
--  so the kill switch cannot skew the vote; touched keys are left alone; ties fall to
--  EUI. Marker-gated to once per account, at ADDON_LOADED (parent SVs are in by then, before PLAYER_LOGIN apply).
--
--  One BATCH per shipment, each with its OWN marker: a spent marker is never
--  revisited, so a later batch riding the older one would silently skip every
--  account that already ran it.
-------------------------------------------------------------------------------
do
    local BATCHES = {
        { marker = "lootSkinStyleSeeded",  keys = { "lootroll", "loothistory", "groupinvite" } },
        { marker = "readyCheckStyleSeeded", keys = { "readycheck" } },
        { marker = "queueChoiceTradeStyleSeeded",
          keys = { "queuestatus", "delvepicker", "playerchoice", "trade" } },
        { marker = "bnetToastStyleSeeded", keys = { "bnettoast" } },
    }
    -- Retail only: this shipment is when the Friends List card started
    -- skinning retail's friends window. WoW Forever's card has driven its own
    -- friends skin since that file shipped, so those accounts stay as set.
    if not EllesmereUI.IS_FOREVER then
        BATCHES[#BATCHES + 1] = { marker = "socialLegacySkinSeeded", keys = { "socialui" } }
    else
        -- WoW Forever: the shipment where the LFG Menu card began skinning
        -- that client's Looking For Group window.
        BATCHES[#BATCHES + 1] = { marker = "foreverLfgSkinSeeded", keys = { "lfg" } }
        -- WoW Forever: the micro menu and the bag bar began skinning there.
        BATCHES[#BATCHES + 1] = { marker = "foreverMicroBagSkinSeeded", keys = { "micromenu", "bagbar" } }
        -- WoW Forever: the Progress Legacy window began skinning there.
        BATCHES[#BATCHES + 1] = { marker = "foreverLegacySkinSeeded", keys = { "legacysystem" } }
    end
    local function SeedBatch(marker, newKeys)
        if EllesmereUIDB[marker] then return end
        EllesmereUIDB[marker] = true
        local styles = EllesmereUIDB.blizzWindowSkinStyles
        local isNew = {}
        for _, k in ipairs(newKeys) do isNew[k] = true end
        local off, modern, eui = 0, 0, 0
        for winKey, ek in pairs(WINDOW_ENABLE_KEYS) do
            if not isNew[winKey] then
                -- A Blizz Default character sheet keeps Blizzard's look.
                if EllesmereUIDB[ek] == false or (styles and styles[winKey] == "blizzard") then
                    off = off + 1
                elseif styles and styles[winKey] == "modern" then
                    modern = modern + 1
                else
                    eui = eui + 1
                end
            end
        end
        for _, winKey in ipairs(newKeys) do
            local ek = WINDOW_ENABLE_KEYS[winKey]
            local touched = EllesmereUIDB[ek] ~= nil
                or (styles and styles[winKey] ~= nil)
            if not touched then
                if off > eui and off > modern then
                    EllesmereUIDB[ek] = false
                elseif modern > eui and modern >= off then
                    if not styles then
                        styles = {}
                        EllesmereUIDB.blizzWindowSkinStyles = styles
                    end
                    styles[winKey] = "modern"
                end
                -- EUI majority (or tie): nil already means EUI-on.
            end
        end
    end
    -- The font look record a whole-UI style switch writes beside the window
    -- swap (fonts._styleSlots.active); the active profile's lives in the live
    -- font store, every other profile's in its own snapshot.
    local function FontLookOf(db, name, prof)
        local fonts = (name == (db.activeProfile or "Default")) and db.fonts or prof.fonts
        local fs = type(fonts) == "table" and fonts._styleSlots
        local look = type(fs) == "table" and fs.active
        if look == "eui" or look == "blizzard" or look == "classic" then return look end
        return nil
    end

    -- Once per account: windows on a stock look with NO profile recording a
    -- look (no windowSkinLook, no font look record -- a glyph-fallback locale
    -- never writes the latter) -- the active profile adopts the look its
    -- windows are on, so nothing moves.
    local function AdoptLegacyWindowLook(db)
        if db.windowLookPerProfile then return end
        db.windowLookPerProfile = true
        local slots = db.windowSkinStyleSlots
        local live = type(slots) == "table" and slots.active
        if not live or live == "eui" or type(db.profiles) ~= "table" then return end
        for name, p in pairs(db.profiles) do
            if type(p) == "table" and (p.windowSkinLook or FontLookOf(db, name, p)) then return end
        end
        local p = db.profiles[db.activeProfile or "Default"]
        if type(p) == "table" then p.windowSkinLook = live end
    end

    -- Once per account: the Character Sheet's Blizz Default used to be the
    -- Style page's Character Sheet row (profile-root flags; copies an older
    -- build left on the account root count too). The profile the live
    -- windows belong to hands its choice to the sheet's card, and the look
    -- slots give every other look its own default. A WoW Forever profile
    -- from before that row existed there follows its stock look, as the
    -- row's own adoption did. When the live look is a stock one, the skin the
    -- sheet wore before (EllesmereUI or Modern) is kept for the EllesmereUI
    -- look.
    local function AdoptCharSheetCardStyle(db)
        if db.charSheetCardStyleAdopted then return end
        db.charSheetCardStyleAdopted = true
        local name = db.activeProfile or "Default"
        local p = type(db.profiles) == "table" and db.profiles[name]
        if type(p) ~= "table" then p = nil end
        local stock = db.charSheetUseBlizzardStyle or db.charSheetUseClassicStyle
            or (p and (p.charSheetUseBlizzardStyle or p.charSheetUseClassicStyle))
        if not stock and p and EllesmereUI.IS_FOREVER and not db.foreverCharSheetStyleAdopted
           and p.charSheetUseBlizzardStyle == nil and p.charSheetUseClassicStyle == nil then
            local look = p.windowSkinLook or FontLookOf(db, name, p)
            stock = look == "blizzard" or look == "classic"
        end
        if not stock then return end
        local styles = db.blizzWindowSkinStyles
        if type(styles) ~= "table" then
            styles = {}
            db.blizzWindowSkinStyles = styles
        end
        local slots = db.windowSkinStyleSlots
        if type(slots) == "table" and slots.active and slots.active ~= "eui"
           and type(slots.eui) == "table" and slots.eui.charsheetStyle == nil then
            slots.eui.charsheetStyle = styles.charsheet or "eui"
        end
        styles.charsheet = "blizzard"
    end

    local seedFrame = CreateFrame("Frame")
    seedFrame:RegisterEvent("ADDON_LOADED")
    -- Registered here, first among this addon's frames, so the login pass
    -- runs after the spec profile pre-seed and before any window skin or
    -- character sheet reads its settings.
    seedFrame:RegisterEvent("PLAYER_LOGIN")
    seedFrame:SetScript("OnEvent", function(self, event, name)
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            EllesmereUI.ReconcileWindowSkinLook()
            return
        end
        if name ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not EllesmereUIDB then EllesmereUIDB = {} end
        for _, batch in ipairs(BATCHES) do SeedBatch(batch.marker, batch.keys) end
        AdoptLegacyWindowLook(EllesmereUIDB)
        AdoptCharSheetCardStyle(EllesmereUIDB)
        EllesmereUI.ReconcileWindowSkinLook()
    end)
end

function EllesmereUI.GetBlizzWindowStyle(winKey)
    -- Third-party virtual keys ("tp:<AddonName>", RegisterSkin API) resolve by majority
    -- vote and bypass the kill switch: third-party skinning is its own opt-in, so window-skin settings only pick WHICH theme, never whether it runs.
    if type(winKey) == "string" and winKey:sub(1, 3) == "tp:" then
        return EllesmereUI.GetThirdPartySkinStyle()
    end
    if EllesmereUI.BlizzWindowSkinsKilled() or EllesmereUI.BlizzSkinPadStandDown() then return "off" end
    local ek = WINDOW_ENABLE_KEYS[winKey]
    if ek and EllesmereUIDB and EllesmereUIDB[ek] == false then return "off" end
    local styles = EllesmereUIDB and EllesmereUIDB.blizzWindowSkinStyles
    local s = styles and styles[winKey]
    if s == "modern" or s == "blizzard" then return s end
    return "eui"
end

--- Style for third-party addon skins: majority vote across the user's own window
--- styles. Modern majority -> "modern"; else (EUI majority, tie, or nothing skinned,
--- incl. under the kill switch where every window reports "off") -> "eui". Never
--- returns "off": whether third-party skinning runs is decided by its own toggles in
--- the SkinAPI dispatcher (reload-bound there), so live refreshes only ever swap between the two themes.
function EllesmereUI.GetThirdPartySkinStyle()
    local eui, modern = 0, 0
    local styles = EllesmereUIDB and EllesmereUIDB.blizzWindowSkinStyles
    -- Under a stock look (windowSkinStyleSlots.active) a window still votes
    -- as it stands in the EllesmereUI look's slot, so switching the whole UI
    -- leaves the vote where it was.
    local slots = EllesmereUIDB and EllesmereUIDB.windowSkinStyleSlots
    local euiSlot = type(slots) == "table" and slots.active and slots.active ~= "eui"
        and type(slots.eui) == "table" and slots.eui or nil
    local killed = EllesmereUI.BlizzWindowSkinsKilled()
    for winKey, ek in pairs(WINDOW_ENABLE_KEYS) do
        -- The inspect sheet renders in the character sheet's style: one vote.
        if winKey ~= "inspect" then
            local s = EllesmereUI.GetBlizzWindowStyle(winKey)
            -- A Blizz Default character sheet wears no skin: it votes like
            -- a window that is off.
            if s == "blizzard" then s = "off" end
            if s == "off" and not killed and euiSlot and euiSlot[ek] ~= false then
                s = (styles and styles[winKey] == "modern") and "modern" or "eui"
            end
            if s == "modern" then modern = modern + 1
            elseif s == "eui" then eui = eui + 1 end
        end
    end
    return (modern > eui) and "modern" or "eui"
end

-- Turn off every window reskin at once (feature-intro popup's "Disable"). Writes explicit
-- false to each enable key (GetBlizzWindowStyle -> "off"); blizzWindowSkinStyles is left intact so re-enable restores styles. Reskins install at load, so the caller must reload.
function EllesmereUI.DisableAllBlizzWindowSkins()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    for _, ek in pairs(WINDOW_ENABLE_KEYS) do
        EllesmereUIDB[ek] = false
    end
end

-- A style chosen for the whole UI (the first-install picker, the Style page's
-- Apply to All) swaps the window skins through per-style slots:
-- EllesmereUIDB.windowSkinStyleSlots = { active = the look whose windows are
-- live, eui/blizzard/classic/forever = that look's enable keys }. Leaving a
-- look saves its windows into its slot; entering one loads its slot, so each
-- look comes back as it was left, per-window picks included. First visit:
-- Blizzard Style and Classic WoW UI keep Blizzard's own windows, every one at
-- Blizz Default; the EllesmereUI look and WoW Forever put every one back to
-- its default (on), the character sheet on its EllesmereUI skin -- except
-- that WoW Forever keeps the micro menu and the bag bar at Blizz Default. The Friends List window rides them whatever the
-- Friends module's state (its pack stands down by itself under a stock
-- Friends style), so a key saved in one swap is always loaded back in the
-- next. A slot holds on/off booleans; a window a slot never recorded (one
-- added later) takes the look's first-visit value. Styles
-- (blizzWindowSkinStyles) are never touched, so a window turned back on keeps
-- its skin -- except the character sheet's, which the slots carry as
-- `charsheetStyle`: Blizz Default is a style there (Blizzard Style's and
-- Classic WoW UI's first visit), and its Off (with the inspect sheet riding
-- its card) stays out of the slots, so a sheet turned off stays off in every
-- look. A one-way seed record from before the slots
-- (windowSkinsStockSeeded) converts on the first swap: its windows were on
-- under the EllesmereUI look, and legacyStock names the look it belongs to.
-- dryRun: only report whether the whole UI's window look would change.
local function WindowInSlots(winKey)
    return winKey ~= "charsheet" and winKey ~= "inspect"
end
-- The looks whose first visit skins the windows (winKey nil: the look as a
-- whole). WoW Forever leaves the micro menu and the bag bar at Blizz Default.
local FOREVER_STOCK = { micromenu = true, bagbar = true }
local function LookSkinsWindows(look, winKey)
    if look == "forever" then return not (winKey and FOREVER_STOCK[winKey]) end
    return look == "eui"
end
function EllesmereUI.SwapWindowSkinStyle(to, dryRun, legacyStock)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local slots = EllesmereUIDB.windowSkinStyleSlots
    if type(slots) ~= "table" then slots = nil end
    local rec = EllesmereUIDB.windowSkinsStockSeeded
    local from = (slots and slots.active)
        or (type(rec) == "table" and (legacyStock or "blizzard")) or "eui"
    if from == to then return false end
    if dryRun then return true end
    if not slots then
        slots = {}
        if type(rec) == "table" then
            local eui = {}
            for winKey, ek in pairs(WINDOW_ENABLE_KEYS) do
                if WindowInSlots(winKey) then
                    eui[ek] = rec[winKey] and true or (EllesmereUIDB[ek] ~= false)
                end
            end
            slots.eui = eui
        end
        EllesmereUIDB.windowSkinStyleSlots = slots
    end
    EllesmereUIDB.windowSkinsStockSeeded = nil
    local styles = EllesmereUIDB.blizzWindowSkinStyles
    if type(styles) ~= "table" then styles = nil end
    local out = {}
    for winKey, ek in pairs(WINDOW_ENABLE_KEYS) do
        if WindowInSlots(winKey) then out[ek] = EllesmereUIDB[ek] ~= false end
    end
    out.charsheetStyle = (styles and styles.charsheet) or "eui"
    slots[from] = out
    local saved = slots[to]
    if type(saved) ~= "table" then saved = nil end
    for winKey, ek in pairs(WINDOW_ENABLE_KEYS) do
        if WindowInSlots(winKey) then
            local v = saved and saved[ek]
            if v == nil then v = LookSkinsWindows(to, winKey) end
            -- On = nil (the install default), off = false. An explicit
            -- branch: `x and false or nil` can only ever yield nil.
            if v then EllesmereUIDB[ek] = nil else EllesmereUIDB[ek] = false end
        end
    end
    -- The character sheet's style. A look's first visit (or a slot saved
    -- before the sheet rode them): Blizz Default on Blizzard Style and
    -- Classic WoW UI; on the EllesmereUI look and WoW Forever a Blizz Default
    -- goes back to the EllesmereUI skin and any other pick stays.
    local cs = saved and saved.charsheetStyle
    if cs == nil then
        if not LookSkinsWindows(to) then
            cs = "blizzard"
        elseif styles and styles.charsheet == "blizzard" then
            cs = "eui"
        end
    end
    if cs == "eui" then
        if styles then styles.charsheet = nil end
    elseif cs then
        if not styles then
            styles = {}
            EllesmereUIDB.blizzWindowSkinStyles = styles
        end
        styles.charsheet = cs
    end
    slots.active = to
    return true
end

-- The whole-UI window look belongs to a PROFILE: the look the whole-UI
-- switch last gave it (profile-root windowSkinLook; a profile from before
-- that key falls back to its font look record, written by the same switch).
-- A profile no whole-UI switch ever touched is on the EllesmereUI look --
-- once the account's windows have been switched at all; before that there
-- is nothing to follow (nil). liveFonts: the live font store, for the
-- active profile (its own snapshot is stale until the next switch).
function EllesmereUI.ProfileWindowSkinLook(prof, liveFonts)
    if type(prof) ~= "table" then return nil end
    local look = prof.windowSkinLook
    -- WoW Forever's own window look; a Forever profile imported on retail
    -- renders Blizzard Style there, so it takes that look's windows.
    if look == "forever" then return EllesmereUI.IS_FOREVER and "forever" or "blizzard" end
    if look == "eui" or look == "blizzard" or look == "classic" then return look end
    local fonts = liveFonts or prof.fonts
    local fs = type(fonts) == "table" and fonts._styleSlots
    look = type(fs) == "table" and fs.active
    if look == "eui" or look == "blizzard" or look == "classic" then return look end
    if EllesmereUIDB and type(EllesmereUIDB.windowSkinStyleSlots) == "table" then return "eui" end
    return nil
end

-- Swap the account-wide window skins to the active profile's look (a no-op
-- when they are on it already). Runs at this addon's load, at login after the
-- spec profile pre-seed, and on every profile switch (RepointAllDBs), so each
-- profile keeps its own window look and a per-window pick always banks into
-- the look it was made under. Skins install at load: a switch that changes
-- the look offers the reload (ProfileChangesWindowSkins).
function EllesmereUI.ReconcileWindowSkinLook()
    local db = EllesmereUIDB
    if type(db) ~= "table" then return end
    local prof = EllesmereUI.GetActiveProfileData()
    local look = EllesmereUI.ProfileWindowSkinLook(prof, db.fonts)
    if look then EllesmereUI.SwapWindowSkinStyle(look, false, look ~= "eui" and look or nil) end
end

-- Main-chunk locals the EUI_BlizzardSkin_*.lua files re-import by name.
-- last: the file of the chain that most recently loaded to its end. Every
-- EUI_BlizzardSkin_*.lua file returns at its first lines unless the file
-- before it got there, so one that errors, does not compile or is missing
-- stops the files behind it.
EllesmereUI.NewInternals(ns, "_internals", {
    FFD = FFD, GetFFD = GetFFD,
    last = "main",
})
