if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PetFrames.lua
--
--  Pet Frames: party and raid pets in one pet header, or beside their owner.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local UnitExists            = UnitExists
local UnitIsUnit            = UnitIsUnit
local UnitInRange           = UnitInRange
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local InCombatLockdown      = InCombatLockdown
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame

local GetFFD, PixelSnap, ResolveHealthTexture = I.GetFFD, I.PixelSnap, I.ResolveHealthTexture

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Pet Frames: party and raid pets in one Blizzard pet header, beside the
--  groups like Friendly Boss, or (Party tab, Beside Owner) one pet button
--  beside each party frame. Health, name, range, hover/target borders and
--  click-cast only, on the FB visuals, painter and anchor; out of the raid
--  routing maps, trackers of their own. Built on first Show Pets.
-------------------------------------------------------------------------------
do
local FB = ns._FB
local PF = { buttons = {}, trackers = {}, byUnit = {}, ownerButtons = {}, ownerByUnit = {}, watching = false,
             shownEv = false, tgtEv = false, petEv = false, tgtWanted = false }
ns._PF = PF

PF.MAX = 40
PF.UNITS = { "pet" }
for i = 1, 4 do PF.UNITS[#PF.UNITS + 1] = "partypet" .. i end
for i = 1, 40 do PF.UNITS[#PF.UNITS + 1] = "raidpet" .. i end
-- Tracker frames (two tokens each): every token, or while raid pets are off the first seven, which
-- hold your pet, the party pets and raidpet1-9 (inside a raid the party frames run below ten
-- members).
PF.ALL_TRACKERS = math.ceil(#PF.UNITS / 2)
PF.SMALL_TRACKERS = 7
PF.EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }
-- A party frame's token -> its pet's token.
PF.PET_OF = { player = "pet" }
for i = 1, 4 do PF.PET_OF["party" .. i] = "partypet" .. i end
for i = 1, 40 do PF.PET_OF["raid" .. i] = "raidpet" .. i end
PF.DEFAULT_BG = { r = 17/255, g = 17/255, b = 17/255 }
-- Beside Owner pet -> the party frame it sits beside (your own pet has none); header button -> the
-- style generation it was last styled at; Beside Owner pet -> its preview mouse blocker.
PF.ownerOf = setmetatable({}, { __mode = "k" })
PF.styledGen = setmetatable({}, { __mode = "k" })
PF.pvBlock = setmetatable({}, { __mode = "k" })

PF.Raw = function()
    return db and db.profile and db.profile.petFrames
end
-- The painter's Pet Health Color read (one setting for both tabs, off the per-tab view).
PF.ColorSettings = PF.Raw

-- The Party and Raid tabs each keep their own Position, Extra Width/Height and Free Move spot. A tab
-- reads the shared key until it sets its own: a view over the saved table that never writes on
-- read. Every other key (the tab toggles, Pet Health Color, Pet Side) is the saved one.
PF.TAB_KEY = {
    party = { position = "party_position", extraWidth = "party_extraWidth", extraHeight = "party_extraHeight",
              freePos = "party_freePos", freeRect = "party_freeRect" },
    raid  = { position = "raid_position", extraWidth = "raid_extraWidth", extraHeight = "raid_extraHeight",
              freePos = "raid_freePos", freeRect = "raid_freeRect" },
}
PF.views = {}
PF.View = function(ctx)
    local v = PF.views[ctx]
    if v then return v end
    local keys = PF.TAB_KEY[ctx]
    v = setmetatable({}, {
        __index = function(_, k)
            local raw = PF.Raw()
            if not raw then return nil end
            local tk = keys[k]
            if tk then
                local val = raw[tk]
                if val ~= nil then return val end
            end
            return raw[k]
        end,
        __newindex = function(_, k, val)
            local raw = PF.Raw()
            if raw then raw[keys[k] or k] = val end
        end,
    })
    PF.views[ctx] = v
    return v
end
ns.PF_View = PF.View

-- The toggle that counts is the one for the frames on screen: the party frames also run inside
-- small raids and arenas.
PF.PartyMode = function()
    return not IsInRaid() or ns._PartyInRaid()
end

PF.Ctx = function()
    return PF.PartyMode() and "party" or "raid"
end

-- The live tab's view.
PF.Settings = function()
    return PF.Raw() and PF.View(PF.Ctx())
end

-- Beside Owner: Show Pets on the Party tab with its Position on Beside Owner, while the party frames
-- are the ones on screen.
PF.OwnerChosen = function()
    local raw = PF.Raw()
    return (raw and raw.party == true and PF.PartyMode() and PF.View("party").position == "owner") or false
end

-- The pet header (Beside Owner leaves it down).
PF.Wanted = function()
    local raw = PF.Raw()
    if not raw then return false end
    if PF.PartyMode() then return raw.party == true and PF.View("party").position ~= "owner" end
    return raw.raid == true
end

-- Settings the pets are styled from: the party settings beside the party frames, else the raid's.
-- The header's follows the mode PF.Layout last laid it out for (PF.styleCtx), so the paint path
-- never re-derives the mode.
PF.PartySource = function()
    return ns._scaledPartyProxy
end
PF.StyleSource = function()
    if PF.styleCtx == "party" then return ns._scaledPartyProxy end
    return ns._scaledProfile or db.profile
end

-- Beside Owner pets ignore their party frame's alpha (its range, offline and Buff Manager fades
-- are the owner's), so the party container's own dims (the options previews) apply here instead.
PF.ContainerAlpha = function()
    local a = ns._partyContainerFrame:GetAlpha()
    if issecretvalue(a) then return 1 end
    return a
end

-- As the raid buttons: UnitInRange's first return straight into SetAlphaFromBoolean, which takes
-- a secret. Its unchecked case is your own units, so your pet stays at full alpha like you do.
PF.ApplyRange = function(b)
    local unit = FB.UnitOf(b)
    if not unit then return end
    local ca = PF.ownerOf[b] and PF.ContainerAlpha() or 1
    local own = UnitIsUnit(unit, "pet")
    if issecretvalue(own) then own = false end
    if not UnitExists(unit) or own then
        b:SetAlpha(ca)
        return
    end
    local s = FB.Source(b)
    b:SetAlphaFromBoolean(UnitInRange(unit), ca, (s.oorAlpha or 0.4) * ca)
end

-- fn(b, unit) on every pet button on screen: the header's, and beside the party frames the Beside
-- Owner pets and your own pet button.
PF.EachShown = function(fn)
    if PF.active then
        for u, b in pairs(PF.byUnit) do
            if b:IsVisible() then fn(b, u) end
        end
    end
    if PF.ownerActive then
        for u, b in pairs(PF.ownerByUnit) do
            if b:IsVisible() then fn(b, u) end
        end
        local sp = PF.selfPet
        if sp:IsVisible() then fn(sp, "pet") end
    end
end

-- Whether a target change can repaint anything: Target Border on in the settings the pets that are
-- up are styled from. Re-read by every apply and party restyle (PF.SyncListeners).
PF.TargetWanted = function()
    local s = PF.active and PF.StyleSource()
    if s and s.targetBorderEnabled ~= false then return true end
    s = PF.ownerActive and PF.PartySource()
    return (s and s.targetBorderEnabled ~= false) and true or false
end

-- Every pet listener runs only while a pet button is on screen (the header hidden solo or in a pet
-- battle, or the party frames down, leaves none): the trackers' health, name and range, the vehicle
-- edges, UNIT_PET beside the party frames, and target changes while a Target Border can show. A
-- button coming on screen paints in full, which covers whatever it missed.
PF.SyncShownEvents = function()
    local want = (PF.tracking and (PF.visCount or 0) > 0) and true or false
    local ev = PF.eventFrame
    local tgt = want and PF.tgtWanted
    if PF.tgtEv ~= tgt then
        PF.tgtEv = tgt
        if tgt then ev:RegisterEvent("PLAYER_TARGET_CHANGED") else ev:UnregisterEvent("PLAYER_TARGET_CHANGED") end
    end
    local pet = (want and PF.ownerActive) and true or false
    if PF.petEv ~= pet then
        PF.petEv = pet
        if pet then ev:RegisterEvent("UNIT_PET") else ev:UnregisterEvent("UNIT_PET") end
    end
    if PF.shownEv == want then return end
    PF.shownEv = want
    if want then
        ev:RegisterEvent("UNIT_ENTERED_VEHICLE")
        ev:RegisterEvent("UNIT_EXITED_VEHICLE")
    else
        ev:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        ev:UnregisterEvent("UNIT_EXITED_VEHICLE")
    end
    for _, tr in ipairs(PF.trackers) do PF.TrackerEvents(tr, want) end
end

-- The listeners after an apply or a party restyle, which can change the pets that are up and the
-- Target Border setting.
PF.SyncListeners = function()
    PF.tgtWanted = PF.TargetWanted()
    PF.SyncShownEvents()
end

-- One tracker's health, name and range listeners. Your own pet takes no range fade, so its token is
-- left out of range.
PF.TrackerEvents = function(tr, on)
    local f = tr.frame
    if not on then
        f:UnregisterAllEvents()
        return
    end
    for _, ev in ipairs(PF.EVENTS) do f:RegisterUnitEvent(ev, tr.u1, tr.u2) end
    if tr.u1 == "pet" then
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u2)
    else
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u1, tr.u2)
    end
end

-- Range re-read with no range update behind it (phasing, the Out of Range Alpha slider, roster
-- passes): the tail of the raid frames' own range seed.
function ns._PF_RangeSeed()
    if PF.shownEv then PF.EachShown(PF.ApplyRange) end
end

-- A group member's connection changed: re-read its pet's range.
function ns._PF_OwnerRange(owner)
    local pt = PF.shownEv and PF.PET_OF[owner]
    if not pt then return end
    local b = PF.active and PF.byUnit[pt]
    if b and b:IsVisible() then PF.ApplyRange(b) end
    b = PF.ownerActive and PF.ownerByUnit[pt]
    if b and b:IsVisible() then PF.ApplyRange(b) end
end

-- A target change repaints only the pets whose target state flipped (the old and new target).
PF.TargetFlip = function(b, u)
    if FB.ReadTarget(b, u) then FB.ApplyBorderColor(b) end
end

-- The full paint, which stamps the occupant it painted (unit + GUID, a secret GUID never stored) so
-- a re-assignment of the same pet can skip it. A pet that does not exist yet still gets its border.
PF.Refresh = function(b)
    if not FB.Update(b, PF) then FB.ApplyBorderColor(b) end
    PF.ApplyRange(b)
    local u = FB.UnitOf(b)
    local g = u and UnitGUID(u)
    if issecretvalue(g) then g = nil end
    local d = GetFFD(b)
    d.pfPaintUnit, d.pfGuid = u, g
end

-- Repaints a shown button only when its occupant differs from the stamped one (a secret or missing
-- GUID always repaints).
PF.Revalidate = function(b)
    if not (b and b:IsVisible()) then return end
    local u = FB.UnitOf(b)
    local d = GetFFD(b)
    if u and u == d.pfPaintUnit then
        local g = UnitGUID(u)
        if issecretvalue(g) then g = nil end
        if g and g == d.pfGuid then return end
    end
    PF.Refresh(b)
end

-- Every pet button on screen (cross-module colour and name pushes).
function ns._PF_RefreshVisible()
    PF.EachShown(PF.Refresh)
end

-- The buttons of one list that are on screen (PF.buttons or PF.ownerButtons), after a settings
-- reload or a party/raid flip.
PF.RepaintShown = function(list)
    for _, b in ipairs(list) do
        if b:IsVisible() then PF.Refresh(b) end
    end
end

-- The pet behind one owner's token may have changed while its button kept the same unit attribute:
-- a new pet (UNIT_PET, Beside Owner only: the pet header re-assigns its own buttons on it), or the
-- owner entering or leaving a vehicle, which the pet token then stands for. Only that owner's pet
-- buttons are re-checked. owner: the event's unit.
PF.OnPetChanged = function(owner)
    local pt = owner and PF.PET_OF[owner]
    if not pt then return end
    if PF.active then PF.Revalidate(PF.byUnit[pt]) end
    if PF.ownerActive then
        PF.Revalidate(PF.ownerByUnit[pt])
        if pt == "pet" then PF.Revalidate(PF.selfPet) end
    end
end

-- The party container's alpha changed (the options previews): re-apply the Beside Owner pets'.
function ns._PF_AlphaSync()
    if not PF.ownerActive then return end
    for _, b in ipairs(PF.ownerButtons) do
        if PF.ownerOf[b] and b:IsVisible() then PF.ApplyRange(b) end
    end
end

-- The side a group attached beside the party frames takes, the Party Frames kit's flip included.
PF.KitSide = function(pos)
    local before = pos == "left"
    if ns.RF_PartyKit() then before = ns.RF_KitAttach(db.profile, before) end
    return before
end

-- The pet group goes after Friendly Boss and Extra Frames when they sit on the same side. Beside
-- the party frames only a Show in Dungeons boss group is attached there to follow, and Extra
-- Frames (raid only) never is.
PF.ChainAnchor = function(pset)
    if pset.position == "free" or pset.position == "owner" then return end
    local party = PF.PartyMode()
    local fs = FB.Settings()
    if fs and FB.built and FB.container:IsShown() then
        if party then
            if fs.position ~= "free" and fs.showInDungeons == true
               and PF.KitSide(fs.position) == PF.KitSide(pset.position) then
                return FB.container
            end
        elseif fs.position == pset.position then
            return FB.container
        end
    end
    if party then return end
    local xf = ns._XF
    local xs = xf.Settings()
    if xs and xs.position == pset.position and xf.built and xf.container and xf.container:IsShown() then
        return xf.container
    end
end

-- map: the unit -> button map the button keeps itself in (none for your own Beside Owner pet).
PF.StyleButton = function(b, map)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("*type1", "target")
    -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
    EllesmereUI.AttachSecureUnitMenu(b)
    FB.BuildVisuals(b)

    b:HookScript("OnShow", function(self)
        PF.visCount = (PF.visCount or 0) + 1
        -- A button showing again holds its unit's map entry, which another button may have taken
        -- and dropped while this one was off screen with the same unit.
        if map then
            local u = self:GetAttribute("unit")
            local d = GetFFD(self)
            local old = d.pfUnit
            if old and old ~= u and map[old] == self then map[old] = nil end
            if u then map[u] = self end
            d.pfUnit = u
        end
        -- Header buttons hidden at the last restyle catch up as they show.
        local g = PF.styledGen[self]
        if g and g ~= PF.styleGen then PF.StyleHeaderButton(self) end
        PF.Refresh(self)
        PF.SyncShownEvents()
    end)
    b:HookScript("OnHide", function(self)
        PF.visCount = math.max(0, (PF.visCount or 0) - 1)
        local d = GetFFD(self)
        d.pfPaintUnit, d.pfGuid = nil, nil
        PF.SyncShownEvents()
    end)
    b:HookScript("OnEnter", function(self)
        FB.hov[self] = true
        FB.ApplyBorderColor(self)
    end)
    b:HookScript("OnLeave", function(self)
        FB.hov[self] = nil
        FB.ApplyBorderColor(self)
    end)
    -- The header (or, beside the party frames, the party frame's unit snippet) re-units buttons as
    -- pets come and go, in combat too. Both re-set every button's unit on each re-process (roster,
    -- name and pet events), so most fires re-confirm the pet already painted: those keep only the
    -- map write. A hidden button paints as it shows.
    b:HookScript("OnAttributeChanged", function(self, name, value)
        if name ~= "unit" then return end
        local d = GetFFD(self)
        if map then
            local old = d.pfUnit
            if old and map[old] == self then map[old] = nil end
            if value then map[value] = self end
            d.pfUnit = value
        end
        if not value or not self:IsVisible() then
            d.pfPaintUnit, d.pfGuid = nil, nil
            if not value then FB.tgt[self] = nil end
            return
        end
        if value == d.pfPaintUnit then
            local g = UnitGUID(value)
            if issecretvalue(g) then g = nil end
            if g and g == d.pfGuid then return end
        end
        PF.Refresh(self)
    end)

    -- Full click-cast / hovercast binding suite (mouseover heals included)
    if ns.CC_RegisterFrame then ns.CC_RegisterFrame(b) end
end

-- One header button at the header's current size and style.
PF.StyleHeaderButton = function(b)
    if not PF.w then return end
    local s = PF.StyleSource()
    FB.StyleVisuals(b, s, PF.w, PF.h, ResolveHealthTexture(s), s.customBgColor or PF.DEFAULT_BG)
    PF.styledGen[b] = PF.styleGen
end

-- Every setting the button styler reads (FB.StyleVisuals with FB.StyleBorder; the size is checked on
-- its own), plus the UI scale its pixel-sized borders follow, gathered into a reused list, so a
-- reload that changed none of them leaves the pets' fonts, textures and borders alone. The hover and
-- target borders are painted, not styled.
PF.STYLE_N = 36
PF.fp = {}
PF.fpNew = {}
PF.StyleInputs = function(t, s, texPath)
    local bgc = s.customBgColor or PF.DEFAULT_BG
    local bc = s.borderColor
    t[1], t[2], t[3], t[4], t[5] = bgc.r, bgc.g, bgc.b, s.bgDarkness, texPath
    t[6], t[7] = s.healthVerticalFill, s.healthBarOpacity
    t[8], t[9] = EllesmereUI.GetFontPath("raidFrames"), EllesmereUI.GetFontOutlineFlag("raidFrames")
    t[10], t[11], t[12] = s.nameSize, s.healthTextSize, s.healAbsorbTextSize
    t[13], t[14], t[15] = s.namePosition, s.nameOffsetX, s.nameOffsetY
    t[16], t[17], t[18] = s.healthTextPosition, s.healthTextOffsetX, s.healthTextOffsetY
    t[19], t[20], t[21] = s.healAbsorbTextPosition, s.healAbsorbTextOffsetX, s.healAbsorbTextOffsetY
    t[22], t[23], t[24], t[25], t[26] = s.borderSize, bc and bc.r, bc and bc.g, bc and bc.b, s.borderAlpha
    t[27], t[28], t[29] = s.borderTexture, s.borderSizePx, s.borderBehind
    t[30], t[31] = s.borderTextureOffset, s.borderTextureOffsetY
    t[32], t[33] = s.borderTextureShiftX, s.borderTextureShiftY
    t[34] = UIParent:GetEffectiveScale()
    t[35] = s.healthInvertFill
    t[36] = s.cornerRadius
end

-- True when the inputs differ from the ones last styled under key ("hdr": the header, "owner": the
-- Beside Owner pets, "pt": the party target frames), which they then become (two lists trade
-- places, nothing allocated). extra(t), when given, writes the key's own inputs after the shared
-- ones, n slots in all (the party target frames' colour settings). The second return is the first
-- slot that differs (0 with nothing styled yet), so a key with extra slots can tell a change to
-- its own inputs alone (past PF.STYLE_N) from one the styler reads.
PF.StyleChanged = function(key, s, texPath, extra, n)
    local new = PF.fpNew
    PF.StyleInputs(new, s, texPath)
    if extra then extra(new) end
    local old, at = PF.fp[key], 0
    if old then
        for i = 1, n or PF.STYLE_N do
            if old[i] ~= new[i] then at = i; break end
        end
        if at == 0 then return false end
    end
    PF.fp[key] = new
    PF.fpNew = old or {}
    return true, at
end

-- Header buttons: five in one column beside the party frames, all forty (eight columns) once raid
-- pets are on. The column count caps what the header shows, so it never makes a button itself.
PF.Capacity = function()
    local raw = PF.Raw()
    return (raw and raw.raid == true) and PF.MAX or 5
end

-- A header makes children only while visible, so the buttons up to the capacity are made up front
-- (the raid headers' startingIndex pass, its parent shown for it) and set up once; the header then
-- assigns pets to them. The pass leaves the header hidden for the apply to show laid out. With the
-- UI hidden (a cinematic, Alt-Z) nothing is made and the next apply tries again. OOC only.
PF.EnsureBuilt = function()
    local cap = PF.Capacity()
    local have = #PF.buttons
    if have >= cap then return true end
    local hdr = PF.container
    if not hdr then
        -- The header's parent carries its pet-battle and solo hide (see PF.SetHider).
        local hider = CreateFrame("Frame", nil, UIParent)
        hider:SetAllPoints(UIParent)
        PF.hider = hider
        hdr = CreateFrame("Frame", "ERFPetHeader", hider, "SecureGroupPetHeaderTemplate")
        hdr:SetAttribute("template", "SecureUnitButtonTemplate")
        hdr:SetAttribute("templateType", "Button")
        hdr:SetAttribute("showRaid", true)
        hdr:SetAttribute("showParty", true)
        hdr:SetAttribute("showPlayer", true)
        hdr:SetAttribute("sortMethod", "INDEX")
        hdr:SetAttribute("unitsPerColumn", 5)
        -- The forty-button pass lays its buttons out in columns, which needs a column anchor;
        -- PF.Layout sets the real one.
        hdr:SetAttribute("columnAnchorPoint", "LEFT")
        PF.container = hdr
        -- Switched on with a preview up: dim it like the other real frames.
        if ns.previewActive() or ns._partyPvActive then ns._SetRealFramesPreviewHidden(true) end
    end
    if not hdr[cap] then
        local hider = PF.hider
        local hid = not hider:IsShown()
        hdr:Hide()
        if hid then hider:Show() end
        hdr:SetAttribute("maxColumns", cap > 5 and 8 or 1)
        hdr:SetAttribute("startingIndex", 1 - cap)
        hdr:Show()
        hdr:SetAttribute("startingIndex", 1)
        hdr:Hide()
        if hid then hider:Hide() end
    end
    for i = have + 1, cap do
        local b = hdr[i]
        if not b then break end
        PF.StyleButton(b, PF.byUnit)
        FB.src[b] = PF.StyleSource
        PF.styledGen[b] = 0
        PF.buttons[i] = b
    end
    local n = #PF.buttons
    if n == 0 then return false end
    -- New buttons take their size on the next layout.
    if n > have then PF.w = nil end
    PF.EnsureTrackers(n >= PF.MAX and PF.ALL_TRACKERS or PF.SMALL_TRACKERS)
    PF.built = true
    return true
end

-- Per-event slices of the full paint (PF.Refresh): health events repaint the health value and texts,
-- name events the name, range updates the range fade.
PF.PaintHealth = function(b, u)
    if UnitExists(u) then FB.PaintHealth(b, u, FB.Source(b)) end
end
PF.PaintName = function(b, u)
    if UnitExists(u) then FB.PaintName(b, u, FB.Source(b)) end
end

-- The event's pet is on the header button holding it, and beside the party frames on its Beside
-- Owner pet (your pet on your own pet button or on the party frame showing you: one of them shows).
PF.OnTrackerEvent = function(_, event, u)
    local paint = PF.PaintHealth
    if event == "UNIT_IN_RANGE_UPDATE" then
        paint = PF.ApplyRange
    elseif event == "UNIT_NAME_UPDATE" then
        paint = PF.PaintName
    end
    local b = PF.byUnit[u]
    if b and b:IsVisible() then paint(b, u) end
    if PF.ownerActive then
        b = PF.ownerByUnit[u]
        if b and b:IsVisible() then paint(b, u) end
        b = PF.selfPet
        if u == "pet" and b:IsVisible() then paint(b, u) end
    end
end

-- Up to n tracker frames, two pet tokens each (RegisterUnitEvent takes two units), from the shell
-- pool. Frames added while pets are on screen listen at once (the listeners switch on edges).
PF.EnsureTrackers = function(n)
    for k = #PF.trackers + 1, n do
        local i = 2 * k - 1
        local t = ns.TakeShell()
        t:SetScript("OnEvent", PF.OnTrackerEvent)
        local tr = { frame = t, u1 = PF.UNITS[i], u2 = PF.UNITS[i + 1] }
        PF.trackers[k] = tr
        if PF.shownEv then PF.TrackerEvents(tr, true) end
    end
end

-------------------------------------------------------------------------------
--  Beside Owner (Party tab): a pet button beside each party frame. The party
--  header's children carry them as children, so they follow every re-sort and
--  hide with their frame (Hide Self included). Each party frame's unit snippet
--  (refreshUnitChange, run by the header right after it assigns the frame's
--  unit, in combat too) writes the pet's own unit, so mouseover, click-cast
--  and the target and menu proxies see the pet token itself. It writes on
--  every pass, the same token included: tokens are positional, so a member
--  leaving hands a frame's token to the next member, and the pet's unit hook
--  then re-checks the occupant. Your own pet has a button of its own on the
--  party container: beside the self button, or with Hide Self in your frame's
--  empty slot after the last party frame.
--  The same snippet carries the party target frames' Include Own Target gate:
--  with it off (pt-noself), the frame holding you drops its target frame's
--  unit (the restricted environment has no UnitIsUnit, so your raid token is
--  compared as pt-me). The pet part runs only while the pets are up (pf-on).
--  Limitation: pt-me is written out of combat. A raid index shift in combat
--  (arena, Small Raid: a lower-index member leaves) leaves it stale until the
--  combat-end reseed (ns._ptSelfDirty -> ns._PT_SyncSelf): your own target
--  shows, and the member now on your old token loses theirs, until then.
-------------------------------------------------------------------------------
PF.OWNER_SNIPPET = [[
    local u = self:GetAttribute("unit")
    if self:GetAttribute("pf-on") then
        local pu
        if u == "player" then
            pu = "pet"
        elseif u then
            local k, n = strmatch(u, "^(%a+)(%d+)$")
            if k then pu = k .. "pet" .. n end
        end
        local pet = self:GetFrameRef("pfpet")
        if pet then pet:SetAttribute("unit", pu) end
        local sp = self:GetFrameRef("pfself")
        if sp and sp:GetAttribute("pf-hs") then
            sp:ClearAllPoints()
            sp:SetPoint(sp:GetAttribute("pf-pt"), self, sp:GetAttribute("pf-rp"), sp:GetAttribute("pf-x"), sp:GetAttribute("pf-y"))
        end
    end
    local pt = self:GetFrameRef("ptframe")
    if pt then
        local show = not (pt:GetAttribute("pt-noself") and u and (u == "player" or u == pt:GetAttribute("pt-me")))
        if pt:GetAttribute("useparent-unit") ~= show then pt:SetAttribute("useparent-unit", show) end
    end
]]

-- OOC only.
PF.EnsureOwnerBuilt = function()
    if PF.ownerBuilt then return end
    PF.ownerBuilt = true
    -- Your pet hangs off the container, not the self button, so it can outlive Hide Self.
    local sp = CreateFrame("Button", nil, ns._partyContainerFrame, "SecureUnitButtonTemplate")
    sp:SetAttribute("unit", "pet")
    sp:Hide()
    PF.StyleButton(sp)
    FB.src[sp] = PF.PartySource
    PF.selfPet = sp
    PF.ownerButtons[1] = sp
    for _, owner in ipairs(ns._partyAllButtons) do
        if owner ~= ns._partySelfButton then
            local b = CreateFrame("Button", nil, owner, "SecureUnitButtonTemplate")
            b:Hide()
            b:SetIgnoreParentAlpha(true)
            PF.ownerOf[b] = owner
            PF.StyleButton(b, PF.ownerByUnit)
            FB.src[b] = PF.PartySource
            PF.ownerButtons[#PF.ownerButtons + 1] = b
            SecureHandlerSetFrameRef(owner, "pfpet", b)
            SecureHandlerSetFrameRef(owner, "pfself", sp)
        end
    end
    PF.EnsureTrackers(PF.SMALL_TRACKERS)
end

-- The party frames' one unit snippet, installed while the Beside Owner pets or the party target
-- frames' Include Own Target gate (ns._ptNoSelf) need it, with the pet part switched by pf-on.
-- Only changed attributes are written. OOC only.
PF.SyncUnitSnippet = function()
    local pets = PF.ownerActive and true or nil
    local code = (pets or ns._ptNoSelf) and PF.OWNER_SNIPPET or nil
    for _, o in ipairs(ns._partyAllButtons) do
        if o ~= ns._partySelfButton then
            if o:GetAttribute("pf-on") ~= pets then o:SetAttribute("pf-on", pets) end
            if o:GetAttribute("refreshUnitChange") ~= code then o:SetAttribute("refreshUnitChange", code) end
        end
    end
end
ns.PF_SyncUnitSnippet = PF.SyncUnitSnippet

-- Switches the snippet's pet part on or off; on, seeds each pet's unit from its frame's current one
-- (written as the snippet does, the same token included). OOC only.
PF.SetOwnerLinks = function(on)
    if on then
        for _, b in ipairs(PF.ownerButtons) do
            local o = PF.ownerOf[b]
            if o then
                local u = o:GetAttribute("unit")
                b:SetAttribute("unit", u and PF.PET_OF[u])
            end
        end
    end
    PF.SyncUnitSnippet()
end

-- Unit watches on the Beside Owner pets run only while the party frames are on screen. OOC only.
PF.SetOwnerWatch = function()
    local want = (PF.ownerActive and ns._partyContainerFrame:IsShown()) and true or false
    if PF.watching ~= want then
        PF.watching = want
        for _, b in ipairs(PF.ownerButtons) do
            if PF.ownerOf[b] then
                if want then
                    RegisterUnitWatch(b)
                else
                    UnregisterUnitWatch(b)
                    b:Hide()
                end
            end
        end
    end
    PF.PlaceSelfPet()
end

-- Party frame size (the raid frame size under the Party Frames layout, whose size is its portrait
-- box, as Friendly Boss does).
PF.PartySize = function(s)
    local w, h, sp = ns.RF_PartyDims(db.profile)
    if ns.RF_PartyKit() then
        w, h, sp = s.frameWidth or 125, s.frameHeight or 60, s.cellSpacing or -1
    end
    return w, h, sp
end

-- A tab's pet size (its frames' size plus that tab's Extra Width/Height), spacing and growth: the
-- party frames' size and stacking on the Party tab, the raid frame size and growth on the Raid tab.
PF.Geometry = function(ctx)
    local s = ns._scaledProfile or db.profile
    local w, h, sp, unitGrowth, groupGrowth
    if ctx == "party" then
        w, h, sp = PF.PartySize(s)
        unitGrowth = ns._PartyGrowth(db.profile)
        groupGrowth = (unitGrowth == "RIGHT" or unitGrowth == "LEFT") and "DOWN" or "RIGHT"
    else
        w, h, sp = s.frameWidth or 125, s.frameHeight or 60, s.cellSpacing or -1
        unitGrowth, groupGrowth = ns._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", true)
    end
    local v = PF.View(ctx)
    w = PixelSnap(math.max(10, w + (v.extraWidth or 0)))
    h = PixelSnap(math.max(10, h + (v.extraHeight or 0)))
    return w, h, sp, unitGrowth, groupGrowth
end

-- Pet Side, fitted to the party frames' orientation: across the stack only (Left/Right beside
-- stacked frames, Above/Below horizontal ones), so a pet never lands on the next frame. A choice
-- that no longer fits reads as the default until it fits again. s: the profile (or preview view).
PF.OwnerSide = function(s)
    local raw = PF.Raw()
    local side = raw and raw.ownerSide
    if s.partyHorizontal then
        if side ~= "above" and side ~= "below" then side = "below" end
    elseif side ~= "left" and side ~= "right" then
        side = "right"
    end
    return side
end
function ns.PF_OwnerSide()
    return PF.OwnerSide(db.profile)
end

-- The side the pets take and the extra gap: the Party Frames kit moves them off its outside auras
-- as it does the Friendly Boss group.
PF.ResolveOwnerSide = function(s)
    local side = PF.OwnerSide(s)
    local extra = 0
    if ns.RF_PartyKit() then
        local before = side == "left" or side == "above"
        before, extra = ns.RF_KitAttach(s, before)
        if s.partyHorizontal then side = before and "above" or "below"
        else side = before and "left" or "right" end
    end
    return side, extra
end

PF.OwnerPoint = function(b, owner, side, gap)
    if side == "left" then
        b:SetPoint("TOPRIGHT", owner, "TOPLEFT", -gap, 0)
    elseif side == "below" then
        b:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -gap)
    elseif side == "above" then
        b:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, gap)
    else
        b:SetPoint("TOPLEFT", owner, "TOPRIGHT", gap, 0)
    end
end

-- Size, side and style of the Beside Owner pets: only what changed is touched (the party layout pass
-- runs this on every roster edge). restyle (a settings reload) checks the style inputs, and restyles
-- the fonts, textures and borders only when they changed; a size change alone resizes. OOC only.
PF.OwnerLayout = function(restyle)
    local w, h, sp = PF.Geometry("party")
    local side, extra = PF.ResolveOwnerSide(db.profile)
    local baseGap = PixelSnap(sp)
    local gap = baseGap + PixelSnap(extra)
    local resized = w ~= PF.ownerW or h ~= PF.ownerH
    local moved = side ~= PF.ownerSideCur or gap ~= PF.ownerGap
    PF.ownerW, PF.ownerH, PF.ownerSideCur, PF.ownerGap, PF.ownerBaseGap = w, h, side, gap, baseGap
    local s, texPath
    local restyled = false
    if restyle then
        s = PF.PartySource()
        texPath = ResolveHealthTexture(s)
        restyled = PF.StyleChanged("owner", s, texPath)
    end
    if restyled then
        local bgc = s.customBgColor or PF.DEFAULT_BG
        for _, b in ipairs(PF.ownerButtons) do
            b:SetSize(w, h)
            FB.StyleVisuals(b, s, w, h, texPath, bgc)
        end
    elseif resized then
        for _, b in ipairs(PF.ownerButtons) do
            b:SetSize(w, h)
            FB.SizeVisuals(b, w, h)
        end
    end
    if moved then
        for _, b in ipairs(PF.ownerButtons) do
            local o = PF.ownerOf[b]
            if o then
                b:ClearAllPoints()
                PF.OwnerPoint(b, o, side, gap)
            end
        end
    end
    if resized or moved then
        PF.PlaceSelfPet(true)
        PF.NotifyReserve()
    end
end

-- Your own pet: beside the self button while that shows you. With Hide Self (in a group), in your
-- frame's empty slot after the last party frame: seated here, then re-seated by the party frames'
-- unit snippet after whichever frame the header fills last, so joins, leaves and re-sorts in combat
-- carry it along. While the party header shows you, that frame's own pet has it and this one stays
-- hidden. Repeat calls with nothing changed return at once. OOC only.
PF.PlaceSelfPet = function(force)
    local b = PF.selfPet
    if not b then return end
    if InCombatLockdown() then PF.anchorDirty = true; return end
    local mode = "off"
    if PF.watching then
        local m = ns._partySelfMode
        if m == "button" or (m == "hidden" and IsInGroup()) then mode = m end
    end
    if mode == "off" then
        if force or PF.spMode ~= "off" then
            PF.spMode = "off"
            b:SetAttribute("pf-hs", nil)
            UnregisterUnitWatch(b)
            b:Hide()
        end
        return
    end
    local grow = ns._PartyGrowth(db.profile)
    local _, _, psp = ns.RF_PartyDims(db.profile)
    -- The party frames' pitch: spacing, plus the room party target frames along the stack take.
    local slotGap = PixelSnap(psp) + ns.PT_AlongPitch(db.profile)
    if not force and mode == PF.spMode and PF.ownerSideCur == PF.spSide and PF.ownerGap == PF.spGap
       and grow == PF.spGrow and slotGap == PF.spSlotGap then
        return
    end
    PF.spMode, PF.spSide, PF.spGap, PF.spGrow, PF.spSlotGap = mode, PF.ownerSideCur, PF.ownerGap, grow, slotGap
    if mode == "hidden" then
        local pt, rp, x, y, base
        if grow == "UP" then
            pt, rp, x, y, base = "BOTTOMLEFT", "TOPLEFT", 0, slotGap, "BOTTOMLEFT"
        elseif grow == "RIGHT" then
            pt, rp, x, y, base = "TOPLEFT", "TOPRIGHT", slotGap, 0, "TOPLEFT"
        elseif grow == "LEFT" then
            pt, rp, x, y, base = "TOPRIGHT", "TOPLEFT", -slotGap, 0, "TOPRIGHT"
        else
            pt, rp, x, y, base = "TOPLEFT", "BOTTOMLEFT", 0, -slotGap, "TOPLEFT"
        end
        b:SetAttribute("pf-pt", pt)
        b:SetAttribute("pf-rp", rp)
        b:SetAttribute("pf-x", x)
        b:SetAttribute("pf-y", y)
        b:SetAttribute("pf-hs", true)
        local hdr = ns._partyHeader
        local last
        for i = 1, 5 do
            local c = hdr[i]
            if c and c:IsShown() and c:GetAttribute("unit") then last = c end
        end
        b:ClearAllPoints()
        if last then
            b:SetPoint(pt, last, rp, x, y)
        else
            b:SetPoint(base, hdr, base, 0, 0)
        end
    else
        b:SetAttribute("pf-hs", nil)
        b:ClearAllPoints()
        PF.OwnerPoint(b, ns._partySelfButton, PF.ownerSideCur, PF.ownerGap)
    end
    RegisterUnitWatch(b)
end

-- A Show in Dungeons boss group beside the party frames clears the Beside Owner pets' column, and
-- the party target frames follow the pets on their side.
PF.NotifyReserve = function()
    ns._PT_Layout()
    local fs = FB.Settings()
    if FB.built and fs and fs.showInDungeons == true then FB.Anchor() end
end

-- The room the Beside Owner pets take on the side a group attaches to the party frames (horizontal:
-- the party frames' orientation; before: left, or above horizontal frames).
function ns.PF_OwnerReserve(horizontal, before)
    local side = PF.ownerActive and PF.ownerSideCur
    if not side then return 0 end
    if horizontal then
        if (before and side == "above") or (not before and side == "below") then
            return PF.ownerH + PF.ownerBaseGap
        end
    elseif (before and side == "left") or (not before and side == "right") then
        return PF.ownerW + PF.ownerBaseGap
    end
    return 0
end

-- Whether either kind of pet is up. Its listeners follow the pets on screen (PF.SyncShownEvents),
-- the vehicle edges among them: an owner entering or leaving a vehicle swaps what its pet token
-- stands for without touching any unit attribute (PF.OnPetChanged re-checks that owner's pet).
PF.SetTracking = function(on)
    if PF.tracking == on then return end
    PF.tracking = on
    PF.SyncShownEvents()
end

-- One write of a batch on the header: the batch's first change sets _ignore, so the header skips its
-- update per attribute; the caller clears it and re-runs the header once. changed: whether the
-- batch has changed anything yet; returns the same for after this write.
local function SetAttr(hdr, key, value, changed)
    if hdr:GetAttribute(key) == value then return changed end
    if not changed then hdr:SetAttribute("_ignore", "attributeChanges") end
    hdr:SetAttribute(key, value)
    return true
end

-- The pet header's parent hides it in pet battles and, unless your pet shows solo, outside a group.
-- A visibility driver writes the statehidden attribute on its frame every 0.2 s; on the header that
-- attribute change re-runs its whole update, so the driver sits on this plain parent. Re-registered
-- only when the macro changes. Grouped = a raid1/party1 unit exists, which stays live in combat
-- (see ns._RF_VIS_MACROS).
-- solo: the header's showSolo. OOC only.
PF.SetHider = function(solo)
    local m = solo and "[petbattle] hide; show" or "[petbattle] hide; [@raid1,exists][@party1,exists][group] show; hide"
    if PF.hiderMacro ~= m then
        RegisterStateDriver(PF.hider, "visibility", m)
        PF.hiderMacro = m
    end
end

-- Teardown, after the header is hidden: the driver goes and the parent shows again, so a later build
-- makes its buttons under a shown parent. OOC only.
PF.ClearHider = function()
    if not PF.hiderMacro then return end
    UnregisterStateDriver(PF.hider, "visibility")
    PF.hiderMacro = nil
    PF.hider:Show()
end

-- Show Groups as a groupFilter: nil with every group on, one cached string per group set.
PF.gf = {}
PF.RaidGroupFilter = function()
    local vg = ns._VisibleGroups()  -- Mythic 5-8 aware (read-only)
    if not vg then return nil end
    local mask = 0
    for gi = 1, 8 do
        if vg[gi] ~= false then mask = mask + 2 ^ (gi - 1) end
    end
    if mask == 255 then return nil end
    local str = PF.gf[mask]
    if not str then
        str = ""
        for gi = 1, 8 do
            if vg[gi] ~= false then str = (str == "") and tostring(gi) or (str .. "," .. gi) end
        end
        PF.gf[mask] = str
    end
    return str
end

-- Size and growth follow the frames on screen (the party frames' in party mode, else the raid
-- frames'), plus that tab's size offsets. Roster edges come through here too, so only what changed
-- is touched: restyle (a settings or profile reload) and a party/raid flip restyle only when the
-- style inputs changed, a size change alone resizes, and buttons off screen catch up as they show.
-- Both also repaint the pets on screen, whose paint reads the settings too. OOC only.
PF.Layout = function(restyle)
    local ctx = PF.Ctx()
    local party = ctx == "party"
    local w, h, sp, unitGrowth, groupGrowth = PF.Geometry(ctx)
    local hdr = PF.container
    local resized = w ~= PF.w or h ~= PF.h
    PF.w, PF.h, PF.sp, PF.unitGrowth, PF.groupGrowth = w, h, sp, unitGrowth, groupGrowth
    local flipped = PF.styleCtx ~= ctx
    local restyled = false
    if restyle or flipped then
        PF.styleCtx = ctx
        local ss = PF.StyleSource()
        restyled = PF.StyleChanged("hdr", ss, ResolveHealthTexture(ss))
    end
    if resized then
        for _, b in ipairs(PF.buttons) do b:SetSize(w, h) end
    end
    if restyled or resized then
        PF.styleGen = (PF.styleGen or 0) + 1
        for _, b in ipairs(PF.buttons) do
            if b:IsVisible() then
                if restyled then
                    PF.StyleHeaderButton(b)
                else
                    FB.SizeVisuals(b, w, h)
                    PF.styledGen[b] = PF.styleGen
                end
            end
        end
    end
    -- Before the header re-runs below: the pets it re-assigns paint in their unit hook, and the
    -- ones it shows as they show.
    if restyle or flipped then PF.RepaintShown(PF.buttons) end

    local s = ns._scaledProfile or db.profile
    -- Party: Small Raid mode shows only group 1 in the party frames, and your pet shows solo while
    -- the party frames do. Raid: the groups Show Groups keeps.
    local group
    if party then
        local g = ns._SmallRaidGroup()
        group = g and tostring(g) or nil
    else
        group = PF.RaidGroupFilter()
    end
    -- Beside the party frames the pets keep the party frames' pitch, which party target frames along
    -- the stack open (the kit's pets take the raid frame size, which never lines up with them).
    local pitch = sp
    if party and not ns.RF_PartyKit() and PF.View("party").position ~= "free" then
        pitch = sp + ns.PT_AlongPitch(db.profile)
    end
    local point, xOff, yOff = ns._RFHeaderPoint(unitGrowth, pitch)
    local solo = (party and db.profile.partyShowWhenSolo) and true or nil
    -- One batch: the header re-runs once below, not per attribute.
    local changed = SetAttr(hdr, "groupFilter", group, false)
    changed = SetAttr(hdr, "showSolo", solo, changed)
    changed = SetAttr(hdr, "point", point, changed)
    changed = SetAttr(hdr, "xOffset", xOff, changed)
    changed = SetAttr(hdr, "yOffset", yOff, changed)
    changed = SetAttr(hdr, "columnSpacing", PixelSnap(s.groupSpacing or 8), changed)
    changed = SetAttr(hdr, "columnAnchorPoint", ns._RFColAnchor(unitGrowth, groupGrowth), changed)
    changed = SetAttr(hdr, "maxColumns", #PF.buttons >= PF.MAX and 8 or 1, changed)
    if changed then hdr:SetAttribute("_ignore", nil) end
    -- Blizzard never clears a shown button's anchors, and a leftover column anchor pins button 1 to
    -- the header's old size, so a new size or layout re-lays from cleared anchors (as the merged raid
    -- header does). One write of a spare attribute then re-runs the header once on the final
    -- attributes (clearing _ignore runs nothing, and a new size alone changes no attribute), with
    -- no pet hidden and re-shown. A header not on screen re-runs as it shows.
    if resized or changed then
        for _, b in ipairs(PF.buttons) do b:ClearAllPoints() end
        hdr:SetAttribute("pf-relayout", not hdr:GetAttribute("pf-relayout"))
    end
    -- Last, so a parent that shows here runs the header once on the final attributes.
    PF.SetHider(solo)
end

-- Free Move: the header is pinned at the corner its pets grow from, so pet 1 stays put as pets come
-- and go. The overlay covers five pets; until its first drag they are centred on freePos. ctx: the
-- tab whose spot and size this is.
PF.FreeCorner = function(set, ctx)
    local w, h, sp, unitGrowth, groupGrowth = PF.Geometry(ctx)
    local vertical = unitGrowth ~= "RIGHT" and unitGrowth ~= "LEFT"
    local hDir = vertical and groupGrowth or unitGrowth
    local vDir = vertical and unitGrowth or groupGrowth
    if vertical then h = 5 * h + 4 * sp else w = 5 * w + 4 * sp end
    local r = set.freeRect
    local corner, x, y = FB.CornerPin(hDir, vDir, r)
    if not r then
        local p = set.freePos
        local cx, cy = p and p.x or 100, p and p.y or 0
        x = (hDir == "LEFT") and (cx + w / 2) or (cx - w / 2)
        y = (vDir == "UP") and (cy - h / 2) or (cy + h / 2)
    end
    return corner, x, y, w, h
end

PF.FreeAnchor = function(c, set)
    local corner, x, y = PF.FreeCorner(set, PF.Ctx())
    FB.Pin(c, corner, UIParent, "CENTER", x, y)
    return true
end

-- The Move Frames overlay places the spot of the tab it was opened on, which need not be the live one.
PF.MoverSettings = function()
    return PF.Raw() and PF.View(PF.moverCtx or PF.Ctx())
end

-- Before the overlay shows: the live header, when up, takes the current settings.
PF.MoverPrep = function()
    if PF.active and not InCombatLockdown() then
        PF.Layout()
        PF.Anchor()
    end
end

PF.PlaceMover = function(m, set)
    local corner, x, y, w, h = PF.FreeCorner(set, PF.moverCtx or PF.Ctx())
    m:SetSize(w, h)
    m:SetPoint(corner, UIParent, "CENTER", x, y)
end

PF.SaveFreeRect = function(mover)
    FB.SaveMoverRect(mover, PF.MoverSettings())
end

-- ctx: "party" or "raid", the tab the overlay is for (the live one when nil).
function ns.PF_SetMoverShown(show, ctx)
    if show then PF.moverCtx = ctx or PF.Ctx() end
    FB.SetMoverShown(PF, show, "ERFPetFramesMover", "Pet Frames")
end

-- ctx: true only when the overlay is up for that tab (any tab when nil).
function ns.PF_IsMoverShown(ctx)
    return (PF.mover and PF.mover:IsShown() and (ctx == nil or PF.moverCtx == ctx)) or false
end

-- A size change on the tab whose overlay is up: the overlay takes the new size (the apply before
-- this has already re-laid the live group).
function ns.PF_PlaceMover(ctx)
    local m = PF.mover
    if not (m and m:IsShown() and PF.moverCtx == ctx) then return end
    local set = PF.MoverSettings()
    if not set then return end
    m:ClearAllPoints()
    PF.PlaceMover(m, set)
end

-- Options preview: made-up pets beside the preview frames, on the same visuals. Plain frames, built
-- the first time a preview shows with Show Pets on; the preview code makes room and places them.
PF.PV_PETS = {
    { name = "Felhunter", hp = 100 },
    { name = "Ghoul", hp = 64 },
    { name = "Spirit Beast", hp = 100 },
    { name = "Water Elemental", hp = 38 },
    { name = "Imp", hp = 85 },
}
PF.OPPOSITE = { RIGHT = "LEFT", LEFT = "RIGHT", DOWN = "UP", UP = "DOWN" }
PF.pv = {}

-- The settings the preview pets are painted with (their border reads it through FB.Source).
PF.PvStyle = function()
    return PF.pvStyle
end

-- One preview pass's shared paint values (reused table). Pets have no class: a class colour mode
-- reads white.
PF.pvc = {}
PF.PvColors = function(s)
    local c = PF.pvc
    PF.pvStyle = s
    c.texPath = ResolveHealthTexture(s)
    c.bgc = s.customBgColor or PF.DEFAULT_BG
    local raw = PF.Raw()
    c.hc = raw and raw.healthColor
    c.opacity = (s.healthBarOpacity or 100) / 100
    c.nr, c.ng, c.nb = ns.RF_PreviewTextColor(s.nameColorMode or "class", s.nameCustomColor, nil, 1, 1, 1)
    c.tr, c.tg, c.tb = ns.RF_PreviewTextColor(s.healthTextColorMode or "custom",
        s.healthTextCustomColor, nil, 1, 1, 1)
    c.ar, c.ag, c.ab = ns.RF_PreviewTextColor(s.healAbsorbTextColorMode or "custom",
        s.healAbsorbTextCustomColor, nil, 1, 0.3, 0.3)
    c.mode = s.healthTextMode or "none"
    c.haMode = s.healAbsorbTextMode or "none"
    return c
end

-- Preview pet i at w x h, styled and painted (the caller places it).
PF.PvFrame = function(i, parent, s, w, h, c)
    local f = PF.pv[i]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        FB.BuildVisuals(f)
        FB.src[f] = PF.PvStyle
        PF.pv[i] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    f:SetFrameStrata(parent == UIParent and "HIGH" or parent:GetFrameStrata())
    f:SetSize(w, h)
    FB.StyleVisuals(f, s, w, h, c.texPath, c.bgc)

    local pet = PF.PV_PETS[i]
    local pct = pet.hp
    local hc = c.hc
    f._health:SetMinMaxValues(0, 100)
    -- pet.hp is a made-up plain number (PF.PV_PETS), so it is flipped here for an
    -- inverted fill (the _euiInv stamp FB.StyleVisuals just left).
    f._health:SetValue(f._health._euiInv and (100 - pct) or pct)
    f._health:SetStatusBarColor(hc and hc.r or 23/255, hc and hc.g or 172/255, hc and hc.b or 49/255, c.opacity)
    f._nameText:SetText(pet.name)
    f._nameText:SetTextColor(c.nr, c.ng, c.nb)
    -- Made-up health (3000 per percent) and a heal absorb of a quarter of it, in the raid preview's
    -- proportions.
    ns.RF_HealthTextInto(f._healthText, c.mode, pct, nil, 3000)
    f._healthText:SetTextColor(c.tr, c.tg, c.tb, 0.9)
    ns.FormatHealAbsorbInto(f._healAbsorbText, pct * 750, c.haMode)
    f._healAbsorbText:SetTextColor(c.ar, c.ag, c.ab, 0.9)
    f:Show()
    return f
end

-- Beside Owner preview: the pet size, side and gap as the real pets take them, the room it needs
-- around the party frames (pads), and with Hide Self the slot after the last frame (sp: the party
-- frames' spacing). s: the preview's view; w, h, sp: its party frame size and spacing.
PF.OwnerPreviewSpec = function(s, w, h, sp)
    local pw, ph, gap = w, h, sp
    if ns.RF_PartyKit() then
        pw, ph, gap = PixelSnap(s.frameWidth or 125), PixelSnap(s.frameHeight or 60), PixelSnap(s.cellSpacing or -1)
    end
    local v = PF.View("party")
    pw = PixelSnap(math.max(10, pw + (v.extraWidth or 0)))
    ph = PixelSnap(math.max(10, ph + (v.extraHeight or 0)))
    local side, extra = PF.ResolveOwnerSide(s)
    gap = gap + PixelSnap(extra)
    local max = math.max
    local spec = { owner = true, w = pw, h = ph, side = side, gap = gap, padL = 0, padT = 0, padR = 0, padB = 0 }
    if side == "right" then
        spec.padR, spec.padB = gap + pw, max(0, ph - h)
    elseif side == "left" then
        spec.padL, spec.padB = gap + pw, max(0, ph - h)
    elseif side == "below" then
        spec.padB, spec.padR = gap + ph, max(0, pw - w)
    else
        spec.padT, spec.padR = gap + ph, max(0, pw - w)
    end
    if s.partyHideSelf then
        local grow = ns._PartyGrowth(s)
        spec.selfSlot = true
        -- The next slot: the party frames' pitch, party target frames along the stack included.
        sp = sp + ns.PT_AlongPitch(s, s.partyShowTargets == true)
        if grow == "UP" then
            spec.sPt, spec.sRp, spec.sX, spec.sY = "BOTTOMLEFT", "TOPLEFT", 0, sp
            spec.padT, spec.padR = max(spec.padT, sp + ph), max(spec.padR, pw - w)
        elseif grow == "RIGHT" then
            spec.sPt, spec.sRp, spec.sX, spec.sY = "TOPLEFT", "TOPRIGHT", sp, 0
            spec.padR, spec.padB = max(spec.padR, sp + pw), max(spec.padB, ph - h)
        elseif grow == "LEFT" then
            spec.sPt, spec.sRp, spec.sX, spec.sY = "TOPRIGHT", "TOPLEFT", -sp, 0
            spec.padL, spec.padB = max(spec.padL, sp + pw), max(spec.padB, ph - h)
        else
            spec.sPt, spec.sRp, spec.sX, spec.sY = "TOPLEFT", "BOTTOMLEFT", 0, -sp
            spec.padB, spec.padR = max(spec.padB, sp + ph), max(spec.padR, pw - w)
        end
    end
    return spec
end

-- The pet group beside a preview, or nil without Show Pets on that tab or on Free Move: button size,
-- count and growth, the group's size, and its top-left offset from the top-left of the boxW x boxH
-- box it attaches to (the party frames, or the first or last preview group), by the FB.Anchor rules.
-- Beside Owner (Party tab) returns its own spec instead (spec.owner, see PF.OwnerPreviewSpec).
-- w, h, sp: the preview's frame size and spacing; ptSpec: the preview's party target frames
-- (ns.PT_PreviewSpec), whose room the pets clear as the real ones do.
function ns.PF_PreviewSpec(party, s, w, h, sp, boxW, boxH, ptSpec)
    local raw = PF.Raw()
    if not raw or raw[party and "party" or "raid"] ~= true then return end
    local set = PF.View(party and "party" or "raid")
    if set.position == "free" then return end
    if set.position == "owner" then
        if party then return PF.OwnerPreviewSpec(s, w, h, sp) end
        return
    end
    local before = set.position == "left"
    local gap, grow, side
    if party then
        gap = s.groupSpacing or -1
        if ns.RF_PartyKit() then
            local extra
            before, extra = ns.RF_KitAttach(s, before)
            gap = gap + extra
        end
        gap = gap + ns.PT_PreviewReserve(ptSpec, s.partyHorizontal, before)
        grow = ns._PartyGrowth(s)
        if ns.RF_PartyKit() then
            w, h, sp = PixelSnap(s.frameWidth or 125), PixelSnap(s.frameHeight or 60), PixelSnap(s.cellSpacing or -1)
        else
            -- The party frames' pitch, party target frames along the stack included (PF.Layout's).
            sp = sp + ns.PT_AlongPitch(s, s.partyShowTargets == true)
        end
        if s.partyHorizontal then side = before and "UP" or "DOWN"
        else side = before and "LEFT" or "RIGHT" end
    else
        gap = PixelSnap(s.groupSpacing or 8)
        grow = s.unitGrowth or "DOWN"
        side = s.groupGrowth or "RIGHT"
        -- The grid flow ends in the rightmost column too, so the pets hang off
        -- the same edge a plain RIGHT run uses -- FB.Anchor agrees. Read raw,
        -- PF.OPPOSITE would return nil for it and the side would fall through
        -- to the vertical branch, drawing the pets above the groups.
        if side == "DOWNRIGHT" then side = "RIGHT" end
        if before then side = PF.OPPOSITE[side] end
    end

    local spec = { n = party and 3 or 5, sp = sp, grow = grow, before = before }
    spec.w = PixelSnap(math.max(10, w + (set.extraWidth or 0)))
    spec.h = PixelSnap(math.max(10, h + (set.extraHeight or 0)))
    if grow == "RIGHT" or grow == "LEFT" then
        spec.bw, spec.bh = spec.n * spec.w + (spec.n - 1) * sp, spec.h
    else
        spec.bw, spec.bh = spec.w, spec.n * spec.h + (spec.n - 1) * sp
    end
    spec.ox, spec.oy = 0, 0
    -- Party stacks that grow up or left start at the box's bottom or right edge.
    if party and grow == "UP" then spec.oy = spec.bh - boxH end
    if party and grow == "LEFT" then spec.ox = boxW - spec.bw end
    if side == "RIGHT" then spec.ox = boxW + gap
    elseif side == "LEFT" then spec.ox = -gap - spec.bw
    elseif side == "DOWN" then spec.oy = -(boxH + gap)
    else spec.oy = gap + spec.bh end
    return spec
end

-- Shows the spec's pets with the group's top-left at x, y from rel's top-left. s: the settings they
-- are styled from.
function ns.PF_ShowPreview(spec, s, parent, rel, x, y)
    local c = PF.PvColors(s)
    for i = 1, spec.n do
        local f = PF.PvFrame(i, parent, s, spec.w, spec.h, c)
        local off = i - 1
        local fx, fy = x, y
        if spec.grow == "RIGHT" then
            fx = x + off * (spec.w + spec.sp)
        elseif spec.grow == "LEFT" then
            fx = x + spec.bw - spec.w - off * (spec.w + spec.sp)
        elseif spec.grow == "UP" then
            fy = y - spec.bh + spec.h + off * (spec.h + spec.sp)
        else
            fy = y - off * (spec.h + spec.sp)
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", rel, "TOPLEFT", fx, fy)
    end
    for i = spec.n + 1, #PF.pv do PF.pv[i]:Hide() end
end

-- Beside Owner preview: a pet beside each shown party preview frame, and with Hide Self one after
-- lastF (the last frame along the growth). s: the settings they are styled from.
function ns.PF_ShowOwnerPreview(spec, s, parent, lastF)
    local c = PF.PvColors(s)
    local n = 0
    for i = 1, 5 do
        local o = ns._partyPvFrames[i]
        if o and o:IsShown() then
            n = n + 1
            local f = PF.PvFrame(n, parent, s, spec.w, spec.h, c)
            f:ClearAllPoints()
            PF.OwnerPoint(f, o, spec.side, spec.gap)
        end
    end
    if spec.selfSlot and lastF and n < #PF.PV_PETS then
        n = n + 1
        local f = PF.PvFrame(n, parent, s, spec.w, spec.h, c)
        f:ClearAllPoints()
        f:SetPoint(spec.sPt, lastF, spec.sRp, spec.sX, spec.sY)
    end
    for i = n + 1, #PF.pv do PF.pv[i]:Hide() end
end

function ns.PF_HidePreview()
    for _, f in ipairs(PF.pv) do f:Hide() end
end

-- Real-frame previews hide the real frames by alpha; while they do, our own mouse blockers keep the
-- invisible pet buttons from taking clicks: one over the pet header, and one on each Beside Owner
-- pet (they sit outside the party frames' blocker). Our frames, so Hide() is combat-legal.
PF.SetPreviewBlock = function(on)
    PF.pvBlockOn = on or nil
    local hdr = PF.container
    if on and PF.active and hdr then
        local blk = PF.hdrBlock
        if not blk then
            -- Under the header's parent, so it hides with the header's pet-battle and solo hide.
            blk = CreateFrame("Frame", nil, PF.hider)
            blk:EnableMouse(true)
            PF.hdrBlock = blk
        end
        blk:SetAllPoints(hdr)
        blk:SetFrameStrata(hdr:GetFrameStrata())
        blk:SetFrameLevel(hdr:GetFrameLevel() + 50)
        blk:Show()
    elseif PF.hdrBlock then
        PF.hdrBlock:Hide()
    end
    for _, b in ipairs(PF.ownerButtons) do
        local blk = PF.pvBlock[b]
        if on and PF.ownerActive then
            if not blk then
                blk = CreateFrame("Frame", nil, b)
                blk:SetAllPoints(b)
                blk:EnableMouse(true)
                PF.pvBlock[b] = blk
            end
            blk:SetFrameLevel(b:GetFrameLevel() + 50)
            blk:Show()
        elseif blk then
            blk:Hide()
        end
    end
end
ns._PF_SetPreviewBlock = PF.SetPreviewBlock

-- A frame strata change while blocked: re-seat the blockers.
function ns._PF_RefreshPreviewBlock()
    if PF.pvBlockOn then PF.SetPreviewBlock(true) end
end

-- The header's placement. FB.Anchor remembers the group it followed in PF.chainTgt (none on Free
-- Move), which the Friendly Boss / Extra Frames probe compares against. A combat call is deferred
-- to the combat-end flush by FB.Anchor.
PF.Anchor = function()
    PF.attachParty = PF.PartyMode()
    if not InCombatLockdown() then PF.chainTgt = false end
    FB.Anchor(PF)
end

function ns.PF_ReAnchor()
    if not InCombatLockdown() then PF.anchorDirty = nil end
    PF.PlaceSelfPet()
    if PF.active then PF.Anchor() end
end

-- Friendly Boss and Extra Frames can appear, move or go away without a roster change. A group that
-- moves carries the pets chained after it along, so the header re-anchors only when the group it
-- follows changes.
PF.ProbeChain = function()
    if not PF.active then return end
    local set = PF.Settings()
    if not set or set.position == "free" then return end
    if (PF.ChainAnchor(set) or false) ~= PF.chainTgt then PF.Anchor() end
end

-- The party layout pass (size, growth, spacing, orientation, the party frames' show/hide edge, the
-- kit's clearance): re-lays the pets and the party target frames that sit beside the party frames,
-- delta-gated. The target frames go after the Beside Owner pets they follow and before any
-- anchoring, so the attached groups are pinned once, on the new reserve.
function ns.PF_PartyRelayout()
    if not InCombatLockdown() then
        if PF.active and PF.PartyMode() then PF.Layout() end
        if PF.ownerActive then
            PF.OwnerLayout()
            PF.SetOwnerWatch()
        end
    end
    ns._PT_Layout()
    ns.PF_ReAnchor()
end

-- A party settings reload, which owns the pets styled from the party settings (the Beside Owner pets,
-- and the header beside the party frames): they check their style (restyled only when it changed)
-- and repaint. Deferred through combat to the combat-end flush.
function ns.PF_PartyRestyle()
    local header = PF.active and PF.PartyMode()
    if not (header or PF.ownerActive) then
        PF.partyRestyleDirty = nil
        return
    end
    if InCombatLockdown() then
        PF.partyRestyleDirty = true
        return
    end
    PF.partyRestyleDirty = nil
    if PF.ownerActive then
        PF.OwnerLayout(true)
        PF.RepaintShown(PF.ownerButtons)
    end
    if header then PF.Layout(true) end
    PF.SyncListeners()
end

-- Master apply: the options, the raid frames' reloads and the roster flush (below). OOC only;
-- deferred through combat like the other groups. restyle: a raid settings or profile reload, which
-- restyles only the pets styled from the raid settings (the party reload that follows it restyles
-- the others, see ns.PF_PartyRestyle).
function ns.PF_Apply(restyle)
    if not db or not db.profile then return end
    local raw = PF.Raw()
    if not raw then return end
    if InCombatLockdown() then
        PF.applyDirty = true
        PF.restyleDirty = PF.restyleDirty or restyle
        return
    end
    -- This pass covers a roster change or a combat-deferred apply still waiting for the flush.
    restyle = restyle or PF.restyleDirty
    PF.dirty, PF.applyDirty, PF.restyleDirty = nil, nil, nil

    -- Beside Owner. Chosen before the party frames exist (early login), neither kind comes up: the
    -- next apply brings the pets up. Only their activation edge checks their style here, before
    -- they show (and paint as they do).
    local chosen = PF.OwnerChosen()
    local owner = chosen and ns._partySelfButton ~= nil
    if owner then
        local edge = not PF.ownerActive
        if edge then
            PF.EnsureOwnerBuilt()
            PF.ownerActive = true
            PF.SetOwnerLinks(true)
        end
        PF.OwnerLayout(edge)
        PF.SetOwnerWatch()
        PF.SetTracking(true)
        if edge then PF.NotifyReserve() end
    elseif PF.ownerActive then
        PF.ownerActive = nil
        PF.SetOwnerLinks(false)
        PF.SetOwnerWatch()
        PF.NotifyReserve()
    end

    if chosen or not PF.Wanted() or not PF.EnsureBuilt() then
        PF.active = nil
        PF.chainTgt = nil
        if PF.built then PF.container:Hide() end
        PF.ClearHider()
        if not owner then PF.SetTracking(false) end
        if PF.pvBlockOn then PF.SetPreviewBlock(true) end
        PF.SyncListeners()
        return
    end

    -- The activation edge checks the style too: settings can change while the header is down.
    local edge = not PF.active
    PF.active = true
    PF.SetTracking(true)
    -- Layout also registers the parent's hide (PF.SetHider) and repaints the pets on screen on a
    -- restyle; the header shows last, laid out, its pets painting as they show. The roster's own
    -- re-assignments paint in the buttons' unit hook.
    PF.Layout((restyle and PF.Ctx() == "raid") or edge)
    ns.PF_ReAnchor()
    if not PF.container:IsShown() then PF.container:Show() end
    if PF.pvBlockOn then PF.SetPreviewBlock(true) end
    PF.SyncListeners()
end

-- Roster and zoning edges, folded into the raid frames' own passes: the roster change and the zone-in
-- mark the pets dirty (in combat too), and the raid frames' roster pass, zone-in settle and combat
-- end each flush once, after their own layout. Both toggles off, nothing is marked.
function ns.PF_MarkDirty()
    local raw = PF.Raw()
    if raw and (raw.party == true or raw.raid == true) then PF.dirty = true end
end

-- Runs what is waiting: a marked or combat-deferred apply, a combat-deferred party restyle, then a
-- combat-deferred placement. OOC only; in combat everything stays marked for the combat-end flush.
function ns.PF_Flush()
    if InCombatLockdown() then return end
    if PF.dirty or PF.applyDirty then ns.PF_Apply() end
    if PF.partyRestyleDirty then ns.PF_PartyRestyle() end
    -- A combat-deferred party target include edge or attribute seed (secure writes), then a
    -- combat-deferred party target layout (a kit clearance edge in combat), before the anchor.
    if ns._ptSelfDirty then ns._PT_SyncSelf() end
    if ns._ptLayoutDirty then ns._PT_Layout() end
    if PF.anchorDirty then ns.PF_ReAnchor() end
end

hooksecurefunc(ns, "FB_Apply", PF.ProbeChain)
hooksecurefunc(ns, "XF_Apply", PF.ProbeChain)

-- Target, pet and vehicle listeners; each is registered only while pets that need it are on screen
-- (PF.SyncShownEvents).
do
    local ev = ns.TakeShell()
    ev:SetScript("OnEvent", function(_, event, unit)
        if not db then return end
        if event == "PLAYER_TARGET_CHANGED" then
            PF.EachShown(PF.TargetFlip)
        else -- UNIT_PET / UNIT_ENTERED_VEHICLE / UNIT_EXITED_VEHICLE
            PF.OnPetChanged(unit)
        end
    end)
    PF.eventFrame = ev
end

end -- PF scope block

I.broken = false
