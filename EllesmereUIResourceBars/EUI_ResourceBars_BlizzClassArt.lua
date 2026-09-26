if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_BlizzClassArt.lua
-- "Blizzard Class Resource Art": Blizzard's own class resource frame (Holy
-- Power, Combo Points, Chi, Soul Shards, Arcane Charges, Essence, Runes) stands
-- in the class resource bar's slot. The slot (ERB_SecondaryFrame) stays shown
-- and sized at zero alpha, so its unlock element, anchors, shift and expand act
-- exactly as with our pips. A host frame of ours covers the slot and holds
-- Blizzard's frame centred, scaled by the Scale cog; the class resource
-- visibility settings (combat, mouseover, opacity, fade, vehicle) ride the host.
--
-- One owner: the Unit Frames "Blizzard" class resource style re-hosts the same
-- frame on its player frame and wins it (ns.UF_OwnsBlizzClassPower). This side
-- never claims while that is set and never takes the frame from another owner;
-- Unit Frames re-runs this module's apply when it takes or drops it.
--
-- Zero cost while off: nothing is created or hooked before the first claim, and
-- the one hook (OnShow on the claimed frame) returns on two compares once the
-- frame is handed back. No events or tickers: BuildBars decides ownership on its
-- own rebuilds (options, spec, talent, form, max power, login), and Blizzard's
-- own Setup keeps deciding when the frame shows. The one watcher is a
-- PLAYER_LEVEL_UP registration that exists only while a held frame waits for
-- its minimum level.
--
-- Writes onto the Blizzard frame, all top-level and all undone on hand-back:
-- ignoreFramePositionManager, Blizzard's own opt-out from its managed layout
-- (its Personal Resource Display, Edit Mode and player cast bar set it the same
-- way), made only while Blizzard's player frame is taken down (its events
-- unregistered); and its own mouse state (off while held, so an art larger than
-- the slot never catches world mouseover or tooltips), restored exactly as
-- recorded. Everything else we track lives in this file's locals. None of the
-- frames is protected; the combat guard below is a safety net.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-- Per-class frame, looked up by name when claimed (nil-guarded).
local ART_FRAMES = {
    DEATHKNIGHT = "RuneFrame",
    DRUID       = "DruidComboPointBarFrame",
    EVOKER      = "EssencePlayerFrame",
    MAGE        = "MageArcaneChargesFrame",
    MONK        = "MonkHarmonyBarFrame",
    PALADIN     = "PaladinPowerBarFrame",
    ROGUE       = "RogueComboPointBarFrame",
    WARLOCK     = "WarlockPowerFrame",
}
-- Point resources those frames draw (Enum.PowerType values, as the main file's
-- PT table); runes are their own resource type.
local ART_POWERS = {
    [4]  = true,  -- Combo Points (Rogue, any Druid in Cat Form)
    [7]  = true,  -- Soul Shards
    [9]  = true,  -- Holy Power
    [12] = true,  -- Chi (Windwalker)
    [16] = true,  -- Arcane Charges (Arcane)
    [19] = true,  -- Essence
}

local host          -- ours: covers the slot, holds Blizzard's frame (first claim)
local heldBar       -- the Blizzard frame held, or nil
local parked        -- handed back but waiting unseen in the host (see Release)
local keyed         -- we set Blizzard's managed-layout opt-out on the held frame
local origStrata    -- the held frame's strata before we took it
local mouseMotion, mouseClick  -- its mouse state before we took it (restored exactly)
local homePt = {}   -- its last point in Blizzard's layout (reused)
local hooked = setmetatable({}, { __mode = "k" })  -- frames carrying our OnShow hook
local regen         -- one-shot PLAYER_REGEN_ENABLED retry (created on demand)
local lvlWatch      -- PLAYER_LEVEL_UP while a held frame waits for its level

local function UFns()
    return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
end

-- The Unit Frames "Blizzard" class resource style holds the frame (it wins a tie).
local function UFOwns()
    local uf = UFns()
    return (uf and uf.UF_OwnsBlizzClassPower and uf.UF_OwnsBlizzClassPower()) and true or false
end

local function ClassFrame()
    local _, classFile = UnitClass("player")
    local name = classFile and ART_FRAMES[classFile]
    return name and _G[name] or nil
end

-- The frame to hold for this profile, or nil. Held per class, not per spec or
-- form, so spec and druid form swaps never move it: Blizzard's Setup hides it
-- wherever its resource is absent, and our own bar keeps the slot then.
local function WantedBar(sp)
    if not (sp and sp.blizzardClassArt) or sp.enabled == false then return nil end
    if EllesmereUI.IS_FOREVER then return nil end
    if UFOwns() then return nil end
    return ClassFrame()
end

-- The current class resource (GetSecondaryResource) is one that frame draws.
local function ResourceOK(info)
    if not info then return false end
    if info.type == "runes" then return true end
    return info.type == "points" and ART_POWERS[info.power] == true
end

-- Blizzard keeps the frame hidden with the resource present while its Personal
-- Resource Display option hides the player frame's class resource, and below a
-- frame's minimum level (Soul Shards, 10): our own bar stays up then. Reads only.
local function Showable(bar)
    if bar.hiddenByPersonalResourceDisplay then return false end
    local lvl = bar.requiredShownLevel
    if lvl and UnitLevel("player") < lvl then return false end
    return true
end

-- Blizzard's player frame is taken down (Unit Frames unregisters its events when
-- the EllesmereUI player frame replaces it): the frame's home stays hidden for
-- good, so the managed-layout opt-out is needed and nothing of Blizzard's
-- player frame is left to read it. Visibility alone would also be false through
-- Alt-Z, a cinematic or another addon hiding that frame with its events live.
local function HomeTakenDown()
    return PlayerFrame ~= nil and not PlayerFrame:IsEventRegistered("PLAYER_ENTERING_WORLD")
end

-- Unit Frames takes Blizzard's player frame down in its login build, which runs
-- after this module's first build (its ns.frames appears once that build is
-- done). Claim after that, so the frame leaves Blizzard's layout bookkeeping on
-- Blizzard's own hide: a later hand-back never has to hide a frame still listed.
-- Our own bar shows until then.
local function HomePending(bar)
    local home = bar.layoutParent
    if not (home and home:IsVisible()) then return false end
    local uf = UFns()
    if not (uf and uf.GetUnitFrameSource) or uf.frames then return false end
    return uf.GetUnitFrameSource("player") ~= "blizzard"
end

local function QueueRegen()
    if not regen then
        regen = CreateFrame("Frame")
        regen:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if _G._ERB_Apply then _G._ERB_Apply() end
        end)
    end
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- A held frame below its minimum level (Soul Shards, 10) is shown by Blizzard the
-- moment the player reaches it: rebuild then, so the pips step aside at once.
local function WatchLevel(bar)
    local lvl = bar and bar.requiredShownLevel
    if lvl and UnitLevel("player") < lvl then
        if not lvlWatch then
            lvlWatch = CreateFrame("Frame")
            lvlWatch:SetScript("OnEvent", function(self, _, newLevel)
                local held = heldBar
                local need = held and held.requiredShownLevel
                if not need or (tonumber(newLevel) or UnitLevel("player")) >= need then
                    self:UnregisterEvent("PLAYER_LEVEL_UP")
                    if _G._ERB_Apply then _G._ERB_Apply() end
                end
            end)
        end
        lvlWatch:RegisterEvent("PLAYER_LEVEL_UP")
    elseif lvlWatch then
        lvlWatch:UnregisterEvent("PLAYER_LEVEL_UP")
    end
end

-- Safety net: a frame that turned protected (something protected anchored to
-- it) cannot move in combat. Leave it and rebuild once combat ends.
local function Blocked(bar)
    if InCombatLockdown() and bar:IsProtected() then
        QueueRegen()
        return true
    end
    return false
end

-- Scale (the RESIZE cog) and strata (General frame strata) ride the host; the
-- held frame keeps its own scale (the runes' 0.95 included).
local function ApplyHostLook(sp)
    local s = tonumber(sp and sp.blizzardClassArtScale) or 1
    if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
    if host:GetScale() ~= s then host:SetScale(s) end
    local p = ns.ERB and ns.ERB.db and ns.ERB.db.profile
    local strata = (p and p.general and p.general.frameStrata) or "MEDIUM"
    if host:GetFrameStrata() ~= strata then host:SetFrameStrata(strata) end
    if heldBar and heldBar:GetParent() == host and heldBar:GetFrameStrata() ~= strata then
        heldBar:SetFrameStrata(strata)
    end
end

-- Where Blizzard's layout last placed the frame, for the hand-back.
local function RecordHome(bar)
    if bar:GetParent() == bar.layoutParent and bar:GetNumPoints() > 0 then
        homePt[1], homePt[2], homePt[3], homePt[4], homePt[5] = bar:GetPoint(1)
    end
end

-- Undo what we changed on the frame. atHome: it is back in Blizzard's layout, so
-- its own strata returns too (another owner sets its own).
local function Restore(bar, atHome)
    if mouseMotion ~= nil then
        bar:SetMouseMotionEnabled(mouseMotion)
        bar:SetMouseClickEnabled(mouseClick)
        mouseMotion, mouseClick = nil, nil
    end
    if atHome and origStrata then bar:SetFrameStrata(origStrata) end
    origStrata = nil
end

-- Let go of a frame we no longer own (another owner took it, or it went home
-- where we cannot follow). Never touches its parent or anchors.
local function Forget(bar, atHome)
    Restore(bar, atHome)
    if heldBar == bar then heldBar = nil end
    if parked == bar then parked = nil end
    keyed = false
end

-- Seat the frame on the host, centred. With Blizzard's player frame taken down
-- set Blizzard's opt-out first (the real field, not a cache: Unit Frames clears
-- the same field when it drops the frame): a show would otherwise send the frame
-- back into that hidden home, hide it and loop. With Blizzard's player frame
-- live the key stays unset (its own art refresh would read it and run on
-- tainted), and the OnShow hook re-seats the frame after each of Blizzard's
-- takebacks instead. The point is set before the reparent so the OnShow that
-- reparent can fire finds the frame seated.
local function Seat(bar)
    if not bar.ignoreFramePositionManager and HomeTakenDown() then
        bar.ignoreFramePositionManager = true
        keyed = true
    end
    if origStrata == nil then origStrata = bar:GetFrameStrata() end
    if mouseMotion == nil then
        mouseMotion, mouseClick = bar:IsMouseMotionEnabled(), bar:IsMouseClickEnabled()
        bar:SetMouseMotionEnabled(false)
        bar:SetMouseClickEnabled(false)
    end
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", host, "CENTER", 0, 0)
    bar:SetFrameStrata(host:GetFrameStrata())
    if bar:GetParent() ~= host then bar:SetParent(host) end
    bar:SetFrameLevel(host:GetFrameLevel() + 2)
end

-- Hand the frame back to Blizzard: its home container, its last laid-out point
-- there (Blizzard lays it out afresh the next time it shows), its own strata and
-- mouse state, and no opt-out key. Never Show/Hide it: Blizzard's Setup owns that.
local function FinishRelease(bar)
    parked = nil
    if keyed then
        bar.ignoreFramePositionManager = nil
        keyed = false
    end
    bar:ClearAllPoints()
    Restore(bar, true)
    bar:SetParent(bar.layoutParent or PlayerFrame or UIParent)
    if homePt[1] then
        bar:SetPoint(homePt[1], homePt[2], homePt[3], homePt[4], homePt[5])
    end
end

-- The one hook, a posthook on the claimed frame's OnShow (Blizzard's handler has
-- run). Blizzard's managed layout takes the frame home on a show unless opted
-- out, and a hide there strips its anchor: both are undone here. A frame another
-- owner took is let go, never taken back. With the home hidden but Blizzard's
-- player frame live (Alt-Z, a cinematic, another addon hiding it) a re-seat
-- would loop through that home, so the frame stays home until the next rebuild.
-- Inert (two compares) when not ours.
local function OnBarShow(bar)
    if bar == heldBar then
        local parent = bar:GetParent()
        if parent == host then
            if bar:GetNumPoints() == 0 and not Blocked(bar) then Seat(bar) end
        elseif parent ~= bar.layoutParent then
            Forget(bar, false)
        elseif not Blocked(bar) then
            local home = bar.layoutParent
            if not (home and home:IsVisible()) and not HomeTakenDown() then
                Forget(bar, true)
            else
                RecordHome(bar)
                Seat(bar)
            end
        end
    elseif bar == parked then
        local home = bar.layoutParent
        if bar:GetParent() ~= host then
            Forget(bar, bar:GetParent() == home)
        elseif not (home and home.showingFrames and home.showingFrames[bar]) and not Blocked(bar) then
            FinishRelease(bar)
        end
    end
end

-- Hand back. A frame Blizzard's layout still lists as showing must not be
-- hidden from our code (that layout pass would then run in our context), and
-- going back into a hidden home hides it: it waits unseen in the host until
-- Blizzard's own hide clears that entry, and the OnShow hook finishes then.
local function Release()
    local bar = heldBar
    if not bar then return end
    if bar:GetParent() ~= host then          -- another owner took it
        Forget(bar, bar:GetParent() == bar.layoutParent)
        return
    end
    if Blocked(bar) then return end         -- still held; retried at regen
    heldBar = nil
    local home = bar.layoutParent
    if home and not home:IsVisible() and bar:IsVisible()
       and home.showingFrames and home.showingFrames[bar] then
        parked = bar
        host:SetAlpha(0)
        return
    end
    FinishRelease(bar)
end

local function Claim(bar, slot, sp, info)
    if not host then
        host = CreateFrame("Frame", nil, UIParent)
        host:SetAllPoints(slot)
        host:SetFrameLevel(slot:GetFrameLevel() + 2)
    end
    ApplyHostLook(sp)
    local parent = bar:GetParent()
    if heldBar == bar and parent == host then return end
    -- Another owner holds it (Unit Frames between its config and its runtime,
    -- or anything else): never take it.
    if parent ~= host and parent ~= bar.layoutParent and parent ~= PlayerFrame then return end
    -- Home hidden with Blizzard's player frame live: seating would loop (OnBarShow).
    local home = bar.layoutParent
    if parent ~= host and not HomeTakenDown() and not (home and home:IsVisible()) then return end
    if Blocked(bar) then return end
    if not hooked[bar] then
        hooked[bar] = true
        bar:HookScript("OnShow", OnBarShow)
    end
    parked = nil
    RecordHome(bar)
    heldBar = bar
    Seat(bar)
    -- A frame handed over hidden (another owner hid it when it let go) is shown
    -- again while its resource is present; opted out, Blizzard's OnShow returns
    -- at once, so nothing of its layout runs from here.
    if keyed and not bar:IsShown() and ResourceOK(info) and Showable(bar) then bar:Show() end
end

-- BuildBars, every build, before the class resource block. Claims or hands back
-- the frame and publishes what the build and the visibility pass read:
-- ns._erbArtOn = Blizzard's frame is held and stands in for the pips for the
-- current class resource (our pips hide and stop painting); ns._erbArtHost = the
-- host while a frame is held (it takes the class resource visibility and opacity).
function ns.ERB_BlizzArtSync(sp, info, slot)
    local bar = WantedBar(sp)
    if bar then
        if heldBar == bar or not HomePending(bar) then Claim(bar, slot, sp, info) end
    elseif heldBar then
        Release()
    end
    local held = heldBar ~= nil and heldBar == bar
    ns._erbArtOn = (held and ResourceOK(info) and Showable(bar)) and true or false
    ns._erbArtHost = heldBar and host or nil
    if held or lvlWatch then WatchLevel(held and bar or nil) end
end

-- The Scale cog: live, no rebuild.
function ns.ERB_ApplyBlizzClassArt()
    if not host then return end
    ApplyHostLook(_G._ERB_ResolveSecondaryCfg and _G._ERB_ResolveSecondaryCfg())
end

-- Config-only reads for Unit Frames (no module namespace needed there): does this
-- profile want the art (nil when Unit Frames' own "Blizzard" style holds it), and
-- is a frame held right now.
_G._ERB_BlizzArtWanted = function()
    local sp = _G._ERB_ResolveSecondaryCfg and _G._ERB_ResolveSecondaryCfg()
    return WantedBar(sp) ~= nil
end
_G._ERB_BlizzArtHeld = function() return heldBar ~= nil end

-- Options: can the toggle be turned on here? true, or false and why: "client" =
-- WoW Forever (no such frames), "uf" = the Unit Frames "Blizzard" class resource
-- style holds the frame, "prd" = Edit Mode's Personal Resource Display hides the
-- player frame's class resource, "resource" = no frame for this class, or the
-- current class resource is one Blizzard draws as a bar or not at all.
function ns.ERB_BlizzClassArtSupported()
    if EllesmereUI.IS_FOREVER then return false, "client" end
    local bar = ClassFrame()
    if not bar then return false, "resource" end
    if UFOwns() then return false, "uf" end
    if bar.hiddenByPersonalResourceDisplay then return false, "prd" end
    local gsr = _G._ERB_GetSecondaryResource
    if ResourceOK(gsr and gsr()) then return true end
    -- Feral outside Cat Form: its combo points come back with the form.
    local _, classFile = UnitClass("player")
    if classFile == "DRUID" and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
       and C_SpecializationInfo.GetSpecialization() == 2 then
        return true
    end
    return false, "resource"
end

-- Options: should Blizzard's frame be standing in for the class resource bar
-- right now? Computed live from the settings (the toggle refreshes the page
-- before its debounced rebuild).
function ns.ERB_BlizzArtActiveNow()
    local sp = _G._ERB_ResolveSecondaryCfg and _G._ERB_ResolveSecondaryCfg()
    local bar = WantedBar(sp)
    if not bar then return false end
    local gsr = _G._ERB_GetSecondaryResource
    return (ResourceOK(gsr and gsr()) and Showable(bar)) and true or false
end
