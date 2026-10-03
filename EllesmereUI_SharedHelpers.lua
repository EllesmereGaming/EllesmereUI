if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SharedHelpers.lua
--  Frame data store, third-party skin registry, Blizzard cast bar ownership
--  and suppression, and small shared helpers (Swiftmend, level colors,
--  faction art). Loads right after EllesmereUI_VisibilityRules.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  External weak-keyed lookup table for frame state (prevents tainting Blizzard
--  frames). Stored on EllesmereUI to avoid the 200-local cap in EllesmereUI.lua.
-------------------------------------------------------------------------------
EllesmereUI._FFD = EllesmereUI._FFD or setmetatable({}, { __mode = "k" })
function EllesmereUI._GetFFD(frame)
    local d = EllesmereUI._FFD[frame]
    if not d then d = {}; EllesmereUI._FFD[frame] = d end
    return d
end

-- Stock styles, enable-time catch-up seeds: a profile already on a stock
-- style from before the per-style slots (the Style page did not switch it,
-- so nothing saved the EllesmereUI look's values) keeps those values in its
-- EllesmereUI slot before a seed writes over them, so switching back
-- restores them. `keys` = the module's slot keys (dotted paths one level
-- deep into `p`, as the Style page's SLOT_KEYS). Callers bank only while
-- none of the module's seed stamps is set; an existing slot is never touched.
function EllesmereUI.BankEuiStyleSlot(p, keys)
    if type(p) ~= "table" then return end
    local slots = p._styleSlots
    if type(slots) == "table" and type(slots.eui) == "table" then return end
    if type(slots) ~= "table" then slots = {}; p._styleSlots = slots end
    local out = {}
    for i = 1, #keys do
        local path = keys[i]
        local a, b = path:match("^([^.]+)%.(.+)$")
        if a then
            local s = p[a]
            if type(s) == "table" then out[path] = s[b] end
        else
            out[path] = p[path]
        end
    end
    slots.eui = out
end

-------------------------------------------------------------------------------
--  Third-Party Skin Registration (public API) -- other addons call
--  EllesmereUI.RegisterSkin("TheirAddon", function(S) ... end) to have their frames painted in
--  the EUI house style. This stub only queues: the Blizz UI Enhanced child addon drains the
--  queue at PLAYER_LOGIN (or immediately for late/LoD registrations) and passes the skinning
--  facade S. Queuing keeps registration order-independent -- third-party addons may load before
--  or after the child -- and the API stays callable (a silent no-op) when the child addon is
--  disabled. Developer guide: SKINNING_API.md. Stored on EllesmereUI to avoid the 200-local cap in EllesmereUI.lua.
-------------------------------------------------------------------------------
EllesmereUI._skinRegistry = EllesmereUI._skinRegistry or {}
function EllesmereUI.RegisterSkin(name, applyFn)
    if type(name) ~= "string" or name == "" or type(applyFn) ~= "function" then return end
    local reg = EllesmereUI._skinRegistry
    for i = 1, #reg do
        if reg[i].name == name then return end
    end
    local entry = { name = name, apply = applyFn }
    reg[#reg + 1] = entry
    if EllesmereUI._DispatchSkinRegistration then
        EllesmereUI._DispatchSkinRegistration(entry)
    end
    return true
end

-------------------------------------------------------------------------------
--  Alpha-Zero Visibility Helper
--  For anchor-participating container frames: use alpha 0 + EnableMouse(false)
--  instead of :Hide() so the frame stays in the layout engine with valid bounds.
--  Sub-widgets (icons, text, glows) inside these frames still use :Hide()/:Show().
-------------------------------------------------------------------------------
function EllesmereUI.SetElementVisibility(frame, visible)
    if not frame then return end
    if visible then
        frame:SetAlpha(EllesmereUI._GetFFD(frame).restoreAlpha or 1)
        frame:EnableMouse(EllesmereUI._GetFFD(frame).restoreMouse or false)
    else
        if frame:GetAlpha() > 0 then
            EllesmereUI._GetFFD(frame).restoreAlpha = frame:GetAlpha()
        end
        EllesmereUI._GetFFD(frame).restoreMouse = frame:IsMouseEnabled()
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    end
end

-------------------------------------------------------------------------------
--  Blizzard Cast Bar Event Ownership -- standalone cast bar addons claim Blizzard's
--  player/pet cast bars by unregistering their events. oUF's Castbar element writes the same
--  state -- it silences those frames when it enables on the player frame and re-arms them when
--  it disables -- so EUI can hand a user's cast bar back to Blizzard on top of the addon they
--  replaced it with. EUI hides Blizzard's bar by re-parenting it (see SetPlayerCastBarSuppressed),
--  so it never needs the event state changed: wrap anything that flips it in Capture/Restore and only ever undo EUI's own writes.
-------------------------------------------------------------------------------
function EllesmereUI._BlizzCastBars()
    local bars = EllesmereUI._blizzCastBarList
    if bars then return bars end

    bars = {}
    if PlayerCastingBarFrame then bars[#bars + 1] = { frame = PlayerCastingBarFrame, unit = "player" } end
    if PetCastingBarFrame then bars[#bars + 1] = { frame = PetCastingBarFrame, unit = "pet" } end
    EllesmereUI._blizzCastBarList = bars

    for i = 1, #bars do
        local bar = bars[i]
        -- An UnregisterAllEvents outside one of our own Capture/Restore windows is another
        -- addon claiming the frame: EUI drops its claim and records the claim as foreign.
        -- "Foreign" is tracked separately from "not ours" because those are very different states -- see RestoreBlizzCastBarEvents.
        hooksecurefunc(bar.frame, "UnregisterAllEvents", function()
            if not EllesmereUI._blizzCastBarSnapshot then
                bar.owned = false
                bar.foreign = true
            end
        end)
    end
    return bars
end

function EllesmereUI.CaptureBlizzCastBarEvents()
    local bars = EllesmereUI._BlizzCastBars()
    local snapshot = {}
    for i = 1, #bars do
        snapshot[i] = bars[i].frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
    end
    EllesmereUI._blizzCastBarSnapshot = snapshot
end

function EllesmereUI.RestoreBlizzCastBarEvents()
    local snapshot = EllesmereUI._blizzCastBarSnapshot
    if not snapshot then return end
    EllesmereUI._blizzCastBarSnapshot = nil

    local bars = EllesmereUI._blizzCastBarList
    for i = 1, #bars do
        local bar = bars[i]
        local live = bar.frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
        if live ~= snapshot[i] then
            if not live then
                bar.owned = true
            elseif bar.owned then
                bar.owned = false
            elseif bar.foreign then
                -- Another addon silenced this frame and we just re-registered it
                -- on the way past; put it back the way we found it instead of
                -- resurrecting Blizzard's cast bar next to theirs.
                bar.frame:UnregisterAllEvents()
                bar.frame:Hide()
            else
                -- Registered inside our own window with nobody claiming it.
                -- That is EUI's own bookkeeping having lost track (a silence
                -- that produced no transition to observe), NOT another addon,
                -- so re-silencing here would kill Blizzard's cast bar for the
                -- session with no way back short of a reload. Leave it armed:
                -- a visible Blizzard bar is something the user can turn off, a
                -- dead one is not.
            end
        end
    end
end

-- The cast events Blizzard's bars listen on, registered per unit. Mirrors the set oUF's
-- Castbar element restores when it disables, which is the only path that has ever successfully re-armed these frames.
--
-- SetUnit is deliberately NOT used to re-arm: its body is guarded on `self.unit ~= unit`, and
-- the frame still holds the unit Blizzard assigned at load, so passing that same unit registers
-- nothing at all. Forcing the guard open is worse -- SetUnit runs StopAnims -> StopFinishAnims,
-- which iterates a table that cannot be accessed while tainted, so from addon execution it throws
-- outright ("attempted to iterate a table that cannot be accessed while tainted") and takes down
-- whatever called it. Registering the events directly is what oUF does, is taint-clean, and touches no Blizzard code at all.
local BLIZZ_CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Give Blizzard's cast bars their event wiring back, unless another addon has claimed them.
-- Covers the pet bar too: oUF silences both and only re-arms them from its Castbar element's
-- Disable, so any release path that does not run that (the element was never enabled to begin with) leaves both dead.
function EllesmereUI.RearmBlizzCastBars()
    local bars = EllesmereUI._blizzCastBarList
    if not bars then return end
    for i = 1, #bars do
        local bar = bars[i]
        if not bar.foreign and not bar.frame:IsEventRegistered("UNIT_SPELLCAST_START") then
            bar.owned = false
            for j = 1, #BLIZZ_CAST_EVENTS do
                bar.frame:RegisterUnitEvent(BLIZZ_CAST_EVENTS[j], bar.unit)
            end
            bar.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            if bar.unit == "pet" then bar.frame:RegisterEvent("UNIT_PET") end
        end
    end
end

-- Arm the ownership hooks at load rather than on first capture. Rearm's only shield against
-- resurrecting a bar a standalone cast bar addon silenced is the foreign flag, and that flag can
-- only be set once the UnregisterAllEvents hooks exist -- a lazy first capture at PLAYER_LOGIN
-- leaves every earlier silence unattributed. File scope runs during the ADDON_LOADED sequence,
-- before any addon's PLAYER_LOGIN handler, so this closes the window to everything except
-- file-scope silences in addons that load before EUI. Guarded on BOTH frames: the list is cached on first build, so building it while either frame is missing would drop that bar for the whole session.
if PlayerCastingBarFrame and PetCastingBarFrame then
    EllesmereUI._BlizzCastBars()
end

-------------------------------------------------------------------------------
--  Shared Player Cast Bar Suppression -- multiple EUI modules can temporarily suppress
--  Blizzard's player cast bar while they render their own. Centralized here so modules cooperate
--  with each other and leave third-party visibility control alone once no EUI module is actively using a replacement bar.
-------------------------------------------------------------------------------
function EllesmereUI.SetPlayerCastBarSuppressed(owner, suppressed)
    if not owner or owner == "" then return end

    local owners = EllesmereUI._playerCastBarSuppressors
    if not owners then
        owners = {}
        EllesmereUI._playerCastBarSuppressors = owners
    end

    if suppressed then
        owners[owner] = true
    else
        owners[owner] = nil
    end

    local blizzBar = PlayerCastingBarFrame
    if not blizzBar then return end

    local shouldSuppress = next(owners) ~= nil
    local hiddenParent = EllesmereUI._playerCastBarHiddenParent

    if shouldSuppress then
        if not hiddenParent then
            hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            EllesmereUI._playerCastBarHiddenParent = hiddenParent
        end

        if blizzBar:GetParent() ~= hiddenParent then
            EllesmereUI._GetFFD(blizzBar).origParent = blizzBar:GetParent()
        end
        EllesmereUI._GetFFD(blizzBar).castBarSuppressed = true

        -- Skip the re-parent while Edit Mode is open: SetParent fires Blizzard's synchronous
        -- layout handlers in this execution, and the UnitFrames Edit-Mode-close hook re-applies this state afterwards.
        if blizzBar:GetParent() ~= hiddenParent
            and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
            blizzBar:SetParent(hiddenParent)
        end

        -- Edit Mode tries to re-anchor the cast bar during layout changes; keep re-applying our hidden parent while any EUI owner suppresses it.
        if not EllesmereUI._GetFFD(blizzBar).setParentHooked then
            EllesmereUI._GetFFD(blizzBar).setParentHooked = true
            hooksecurefunc(blizzBar, "SetParent", function(self, newParent)
                if EllesmereUI._GetFFD(self).castBarSuppressed and newParent ~= EllesmereUI._playerCastBarHiddenParent then
                    C_Timer.After(0, function()
                        -- Never re-parent while Edit Mode is open, even from a timer: SetParent
                        -- fires Blizzard's synchronous layout handlers under addon taint and poisons the manager's state for its next pass (the Edit Mode close hook in UnitFrames re-applies suppression).
                        if EllesmereUI._GetFFD(self).castBarSuppressed
                           and not InCombatLockdown()
                           and not (EditModeManagerFrame and EditModeManagerFrame:IsShown())
                           and self:GetParent() ~= EllesmereUI._playerCastBarHiddenParent
                        then
                            self:SetParent(EllesmereUI._playerCastBarHiddenParent)
                        end
                    end)
                end
            end)
        end

        local selection = blizzBar.Selection
        if selection then
            if not EllesmereUI._GetFFD(selection).suppressed then
                EllesmereUI._GetFFD(selection).restoreAlpha = selection:GetAlpha()
                EllesmereUI._GetFFD(selection).restoreMouse = selection:IsMouseEnabled()
            end
            EllesmereUI._GetFFD(selection).suppressed = true
            selection:SetAlpha(0)
            selection:EnableMouse(false)

            if not EllesmereUI._GetFFD(selection).showHooked then
                EllesmereUI._GetFFD(selection).showHooked = true
                hooksecurefunc(selection, "Show", function(self)
                    -- Deferred: Show fires inside Edit Mode's secure ShowSystemSelections pass; write nothing there.
                    C_Timer.After(0, function()
                        if PlayerCastingBarFrame and EllesmereUI._GetFFD(PlayerCastingBarFrame).castBarSuppressed then
                            self:SetAlpha(0)
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
        end

        return
    end

    EllesmereUI._GetFFD(blizzBar).castBarSuppressed = false

    -- Hand the bar back to the parent EUI took it from -- but never to one that is itself hidden.
    -- Blizzard parents this bar under PlayerFrame, and Edit Mode re-parents it into a layout frame
    -- that gets hidden on exit, while EUI hides PlayerFrame whenever it renders its own player
    -- frame. Restoring there leaves Blizzard's cast bar fully armed but permanently invisible,
    -- which reads exactly like the suppression never lifted. UIParent is where Edit Mode positions the bar from anyway, and SetParent keeps the existing anchors, so the bar still lands where the user had it.
    local origParent = EllesmereUI._GetFFD(blizzBar).origParent
    local currentParent = blizzBar:GetParent()
    local restoreParent = origParent
    if not restoreParent or not restoreParent.IsVisible or not restoreParent:IsVisible() then
        restoreParent = UIParent
    end

    -- Only ever un-park a bar EUI itself parked: either it is still sitting in our hidden parent,
    -- or an earlier release handed it back to the captured parent and that parent is itself
    -- hidden. Matching the captured parent exactly is what separates "Blizzard's own parent
    -- happens to be hidden" from "another addon parked this bar under its own hidden frame" -- the latter is left alone, since resurrecting it is the bug this whole ownership dance exists to prevent.
    local parkedByUs = (hiddenParent and currentParent == hiddenParent)
        or (origParent and currentParent == origParent
            and currentParent.IsVisible and not currentParent:IsVisible())

    -- The Edit Mode gate can skip this; ApplyBlizzCastbarState re-runs the release on
    -- PLAYER_ENTERING_WORLD and on Edit Mode close, so a bar left parked by a skipped pass is healed as soon as re-parenting is legal.
    if parkedByUs and currentParent ~= restoreParent
        and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        blizzBar:SetParent(restoreParent)
    end

    local selection = blizzBar.Selection
    if selection and EllesmereUI._GetFFD(selection).suppressed then
        EllesmereUI._GetFFD(selection).suppressed = false
        selection:SetAlpha(EllesmereUI._GetFFD(selection).restoreAlpha or 1)
        selection:EnableMouse(EllesmereUI._GetFFD(selection).restoreMouse or false)
    end

    -- Let Blizzard rebuild its normal event wiring without forcing visibility back on, so profile
    -- switches and UnitFrames/oUF teardown stay compatible with Blizzard's own cast bar logic.
    -- Only when EUI silenced the frame in the first place: a standalone cast bar addon silences
    -- the same frame, and re-registering its events is what pops Blizzard's cast bar back on screen next to theirs once EUI's own cast bar is switched off.
    EllesmereUI.RearmBlizzCastBars()
end

-------------------------------------------------------------------------------
--  Swiftmend Brightness Fix (shared hook utility) -- Blizzard dims Swiftmend based on
--  Efflorescence state (secret value in Midnight). Child addons call this on icon textures they identify as Swiftmend; the hook prevents vertex-color dimming and desaturation.
-------------------------------------------------------------------------------
do
    local hooked = {}
    local function isEnabled()
        return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
    end
    function EllesmereUI._HookSwiftmendIcon(tex)
        if not tex or hooked[tex] then
            -- Already hooked; just force bright if re-enabling
            if tex and hooked[tex] and isEnabled() then
                tex:SetVertexColor(1, 1, 1)
            end
            return
        end
        hooked[tex] = true
        local vcGuard = false
        hooksecurefunc(tex, "SetVertexColor", function(_, r, g, b)
            if not vcGuard and isEnabled() and not (r == 1 and g == 1 and b == 1) then
                vcGuard = true
                tex:SetVertexColor(1, 1, 1)
                vcGuard = false
            end
        end)
        -- Force bright immediately (icon may already be dimmed before hook)
        if isEnabled() then tex:SetVertexColor(1, 1, 1) end
    end
    EllesmereUI._SWIFTMEND_SPELL = 18562
    EllesmereUI._SWIFTMEND_ICON  = 134914
end

-------------------------------------------------------------------------------
--  Level difficulty colors (unit frame and nameplate level text), Blizzard's
--  rule: "??" (level <= 0) red, a unit you cannot attack gold, otherwise the
--  color for its level against yours.
-------------------------------------------------------------------------------
function EllesmereUI.GetLevelDifficultyColor(level, attackable)
    if level <= 0 then return 1, 0.1, 0.1 end
    if not attackable then
        local c = UNIT_LEVEL_NON_ATTACKABLE
        if c then return c.r, c.g, c.b end
        return 1, 0.82, 0
    end
    local mine = UnitEffectiveLevel("player")
    if issecretvalue and issecretvalue(mine) then return nil end
    if EllesmereUI.IS_FOREVER then
        -- WoW Forever's own nameplate rule (the vanilla one): grey past the
        -- trivial range, green 3+ below, yellow within 2, orange 3-4 above, red 5+.
        local diff = level - mine
        local fc
        if diff < -C_QuestLog.GetTrivialRange() then fc = TRIVIAL_DIFFICULTY_COLOR
        elseif diff <= -3 then fc = EASY_DIFFICULTY_COLOR
        elseif diff <= 2 then fc = FAIR_DIFFICULTY_COLOR
        elseif diff <= 4 then fc = DIFFICULT_DIFFICULTY_COLOR
        else fc = IMPOSSIBLE_DIFFICULTY_COLOR end
        if fc then return fc.r, fc.g, fc.b end
        return nil
    end
    local c = (GetRelativeDifficultyColor and GetRelativeDifficultyColor(mine, level))
        or (GetQuestDifficultyColor and GetQuestDifficultyColor(level))
    if c then return c.r, c.g, c.b end
end
-- For a unit; nil when the level or attackability cannot be read (secret).
-- includeFriendly: friendly units get their difficulty color too, not gold.
function EllesmereUI.GetLevelColor(unit, level, includeFriendly)
    local sv = issecretvalue
    if level == nil or (sv and sv(level)) then return nil end
    if includeFriendly then return EllesmereUI.GetLevelDifficultyColor(level, true) end
    local attackable = UnitCanAttack("player", unit)
    if sv and sv(attackable) then return nil end
    return EllesmereUI.GetLevelDifficultyColor(level, attackable)
end
function EllesmereUI.ColorText(text, r, g, b)
    if not r then return text end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

-------------------------------------------------------------------------------
--  Faction badge art, shared by the unit frame and nameplate faction indicators
--  and their options previews. Each style is a Horde/Alliance pair, an atlas or a
--  file; "%s" takes the faction ("lower" = lowercased, "num" = 1 Horde / 2 Alliance).
--  "coords" crops a file whose art does not fill it (the Classic banner sits in the
--  top-left 42 of 64 pixels).
--  Unknown styles fall back to "pvp", the default.
-------------------------------------------------------------------------------
EllesmereUI.FACTION_ART = {
    pvp       = { atlas = "UI-HUD-UnitFrame-Player-PVP-%sIcon" },
    honor     = { atlas = "honorsystem-portrait-%s", lower = true },
    poi       = { atlas = "poi-%s", lower = true },
    classic   = { file = "Interface\\TargetingFrame\\UI-PVP-%s", coords = { 0, 0.65625, 0, 0.65625 } },
    banner    = { file = "Interface\\Icons\\INV_BannerPVP_0%s", num = true },
    honoricon = { file = "Interface\\Icons\\PVPCurrency-Honor-%s" },
    friends   = { file = "Interface\\FriendsFrame\\PlusManz-%s" },
}
EllesmereUI.FACTION_ART_ORDER = { "pvp", "honor", "poi", "classic", "banner", "honoricon", "friends" }
EllesmereUI.FACTION_ART_LABELS = {
    pvp = "PvP Emblem", honor = "Honor Portrait", poi = "Map Flag", classic = "Classic Banner",
    banner = "Banner Icon", honoricon = "Honor Icon", friends = "Friends Crest",
}
function EllesmereUI.SetFactionArt(tex, style, faction)
    local art = EllesmereUI.FACTION_ART[style] or EllesmereUI.FACTION_ART.pvp
    -- The resolved atlas or file name is built once per style and faction and kept
    -- on the style's entry (art.Horde / art.Alliance).
    local name = art[faction]
    if not name then
        local key = faction
        if art.lower then
            key = faction:lower()
        elseif art.num then
            key = (faction == "Horde") and "1" or "2"
        end
        name = (art.atlas or art.file):format(key)
        art[faction] = name
    end
    if art.atlas then
        -- SetAtlas keeps an earlier SetTexCoord (e.g. the Classic banner's crop)
        -- unless told to reset it, so clear it first and ask for the reset too.
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(name, false, nil, true)
    else
        tex:SetTexture(name)
        local c = art.coords
        if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) else tex:SetTexCoord(0, 1, 0, 1) end
    end
end
