-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidGroups.lua -- Raid group composition window
--
--  Eight group columns, five slots each, and a member is moved by dragging it
--  onto another slot. Opened from the cog on the Raid Tools Group & Pull
--  window; that cog exists only for a raid leader or assistant, since nobody
--  else can act on what this shows.
--
--  WHY IT EXISTS. Blizzard's own raid frames let a leader drag a member
--  between groups. The suite hides Blizzard's raid manager and replaces its
--  frames, so it currently takes that away; this gives it back.
--
--  NOT SECURE, AND THAT IS NOT AN OVERSIGHT. SetRaidSubgroup and
--  SwapRaidSubgroup are ordinary functions -- no lockdown restriction, no
--  taint path -- so unlike the Raid Tools panels this window needs no secure
--  frames, no state driver and no combat deferral. Plain frames throughout.
--
--  MOVE vs SWAP is the game's rule, not a design choice: a subgroup holds five
--  and the client will not make room. So dropping onto a PLAYER swaps the two,
--  and dropping onto an EMPTY slot moves. One rule, and it covers both cases
--  without asking the user to know which is which -- a full group simply has
--  no empty slot to land on.
-------------------------------------------------------------------------------
local _, ns = ...

local GetRaidRosterInfo   = GetRaidRosterInfo
local GetNumGroupMembers  = GetNumGroupMembers
local IsInRaid            = IsInRaid
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant

-- Sized for a name to read at a glance rather than to save pixels: the window
-- is a deliberate act, not something that sits on screen. It then rides
-- GetPopupScale, so the user's panel scale still governs the final size.
local NUM_GROUPS   = 8
local GROUP_SIZE   = 5
local COLS         = 4          -- 4 x 2 reads better on a wide screen than 2 x 4
local SLOT_W       = 148
local SLOT_H       = 22
local SLOT_GAP     = 3
local COL_GAP      = 10
local HEADER_H     = 16
local PAD          = 14
local TITLE_H      = 26
local NAME_SIZE    = 12
local HEADER_SIZE  = 11

-- The dimming an origin slot wears while its member is on the cursor, and the
-- transit alpha of the cursor label itself. Both say "this is in flight".
local LIFTED_ALPHA = 0.35
local GHOST_ALPHA  = 0.85

local db
local win                       -- built once, on first open
local slots = {}                -- flat list of every slot frame
local dragSlot                  -- the slot a member was lifted from, while dragging
local ghost                     -- the label that follows the cursor

-- Our own slice of the shared QoL profile, the arrangement every QoL feature
-- uses: each merges its own defaults into the SAME profile table under its own
-- key. A PURE READ -- see the note in EllesmereUIQoL_RaidTools.lua on why
-- seeding here would overflow under a Spec Overrides capture proxy.
local DB_DEFAULTS = {
  profile = {
    raidGroups = {
        scale = 1,
        pos   = {},   -- { point, relPoint, x, y }, written on drag stop
    },
  },
}

local function P()
    return db and db.profile and db.profile.raidGroups
end

-- Leader or assistant, in a raid. Both halves matter: the calls below are
-- refused by the server without rank, and outside a raid there are no
-- subgroups to arrange.
function ns.RaidGroupsPermitted()
    return IsInRaid()
       and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

-------------------------------------------------------------------------------
--  Roster
-------------------------------------------------------------------------------

-- groups[g] = ordered list of { index, name, class, online }. Rebuilt whole on
-- every refresh: a raid is 40 entries at most, and holding indices across a
-- roster change is how you move the wrong person.
local function ReadRoster()
    local groups = {}
    for g = 1, NUM_GROUPS do groups[g] = {} end
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup, _, _, class, _, online = GetRaidRosterInfo(i)
        -- Members stream in on a zone change; GetRaidRosterInfo returns nil for
        -- one that has not arrived yet.
        if name then
            local list = groups[subgroup]
            list[#list + 1] = { index = i, name = name, class = class, online = online }
        end
    end
    return groups
end

-- `toIndex` is the raid index of the member dropped ON, or nil for an empty
-- slot. See the header for why that single distinction is the whole rule.
local function MoveMember(fromIndex, toGroup, toIndex)
    if toIndex then
        if toIndex ~= fromIndex then SwapRaidSubgroup(fromIndex, toIndex) end
    else
        SetRaidSubgroup(fromIndex, toGroup)
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------

local Refresh   -- forward: the slot scripts and the event frame both call it

-- Three visual states, deliberately distinct so a drag is never ambiguous:
--   _hl    faint wash  -- "a legal destination", lit on every valid slot for
--                         as long as a drag is in flight
--   _hover accent wash -- "the cursor is here", the DataBars idiom (its blocks
--                         go accent under the cursor)
--   _brd   accent line -- "release now and it lands HERE", only ever on one
--                         slot at a time
local function SetSlotHover(s, on)
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    s._hover:SetColorTexture(ar, ag, ab, 0.18)
    s._hover:SetShown(on)
end

-- The strongest state in the window, and deliberately so: it is the one that
-- answers "if I release now, what happens". The wash on top of the frame,
-- because during a drag it competes with every other lit slot for the eye.
local function SetSlotTarget(s, on)
    SetSlotHover(s, on)
    if on then
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        s._brd:SetColor(ar, ag, ab, 1)
    else
        s._brd:SetColor(1, 1, 1, 0)
    end
end

local dropTarget    -- the slot currently wearing the accent frame

local function StopDrag()
    dragSlot._lbl:SetAlpha(1)
    dragSlot = nil
    dropTarget = nil
    ghost:Hide()
    ghost:SetScript("OnUpdate", nil)
    for _, s in ipairs(slots) do
        s._hl:Hide()
        SetSlotTarget(s, false)
    end
end

-- Follows the cursor, and resolves the drop target as it goes. The target has
-- to be found here rather than in each slot's OnEnter: a frame under the cursor
-- does not fire OnEnter while a drag is in flight, so nothing would light up.
--
-- Slots are asked directly rather than through GetMouseFoci, which reports the
-- frame under the cursor -- and that is our own ghost.
--
-- Hoisted out of StartDrag: it captures only module upvalues, so rebuilding it
-- per drag would allocate a closure for nothing.
local function GhostOnUpdate(self)
    -- Cursor coordinates come back in screen units; dividing by the frame's own
    -- effective scale puts them in the space SetPoint reads.
    local x, y = GetCursorPosition()
    local es = self:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / es, y / es)

    local over
    if win:IsMouseOver() then
        for i = 1, #slots do
            if slots[i]:IsMouseOver() then over = slots[i]; break end
        end
    end
    if over ~= dropTarget then
        if dropTarget then SetSlotTarget(dropTarget, false) end
        dropTarget = over
        if over then SetSlotTarget(over, true) end
    end
end

local function StartDrag(slot)
    if not slot._member or not ns.RaidGroupsPermitted() then return end
    dragSlot = slot
    -- The member has been lifted out: the origin fades rather than showing the
    -- same name at the same weight as the one on the cursor.
    slot._lbl:SetAlpha(LIFTED_ALPHA)

    ghost._lbl:SetText(slot._member.name)
    ghost:Show()
    ghost:SetScript("OnUpdate", GhostOnUpdate)

    -- Light every slot that is a legal destination, so the drop targets are
    -- visible rather than guessed. Everything except where it already is.
    SetSlotHover(slot, false)
    for _, s in ipairs(slots) do
        if s._group ~= slot._group then s._hl:Show() end
    end
end

-- Released. The target is whatever GhostOnUpdate last outlined, so what the
-- user saw is exactly what happens -- re-resolving here could disagree with it.
local function DropDrag()
    if not dragSlot then return end
    local from, target = dragSlot._member.index, dropTarget
    StopDrag()
    if not target or not ns.RaidGroupsPermitted() then return end
    MoveMember(from, target._group, target._member and target._member.index or nil)
    Refresh()
end

-- Only an occupied slot lights: an empty one has nothing to pick up.
local function SlotOnEnter(s)
    if s._member then SetSlotHover(s, true) end
end

local function SlotOnLeave(s)
    SetSlotHover(s, false)
end

local function MakeSlot(parent, group)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(SLOT_W, SLOT_H)
    s._group = group

    EllesmereUI.SolidTex(s, "BACKGROUND", 0.10, 0.10, 0.10, 0.6):SetAllPoints()
    s._hl = EllesmereUI.SolidTex(s, "ARTWORK", 1, 1, 1, 0.07)
    s._hl:SetAllPoints()
    s._hl:Hide()
    s._hover = EllesmereUI.SolidTex(s, "ARTWORK", 1, 1, 1, 0)
    s._hover:SetAllPoints()
    s._hover:Hide()
    -- Created transparent rather than on demand: SetColor is the whole
    -- show/hide, so nothing has to track whether the border exists yet.
    s._brd = EllesmereUI.MakeBorder(s, 1, 1, 1, 0, EllesmereUI.PP)

    s._lbl = EllesmereUI.MakeFont(s, NAME_SIZE, nil, 1, 1, 1)
    s._lbl:SetPoint("LEFT", s, "LEFT", 6, 0)
    s._lbl:SetPoint("RIGHT", s, "RIGHT", -6, 0)
    s._lbl:SetJustifyH("LEFT")

    -- All four handlers are module-level: they take `self`, so building them
    -- per slot would allocate 120 identical closures at first open.
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnEnter", SlotOnEnter)
    s:SetScript("OnLeave", SlotOnLeave)
    s:SetScript("OnDragStart", StartDrag)
    -- Fires on the frame the drag STARTED from, wherever it is released, which
    -- is what makes one handler enough to resolve any destination.
    s:SetScript("OnDragStop", DropDrag)

    slots[#slots + 1] = s
    return s
end

local function Build()
    win = CreateFrame("Frame", "EllesmereUIRaidGroupsWindow", UIParent)
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(200)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:Hide()
    EllesmereUI.RegisterEscapeClose(win)

    -- The cursor label, built with the window so nothing has to test whether it
    -- exists yet -- a drag is only reachable once the window is up.
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(SLOT_W, SLOT_H)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetAlpha(GHOST_ALPHA)
    ghost:Hide()
    EllesmereUI.SolidTex(ghost, "BACKGROUND", 0.06, 0.08, 0.10, 0.9):SetAllPoints()
    EllesmereUI.MakeBorder(ghost, 1, 1, 1, 0.35, EllesmereUI.PP)
    ghost._lbl = EllesmereUI.MakeFont(ghost, NAME_SIZE, nil, 1, 1, 1)
    ghost._lbl:SetPoint("CENTER")

    local rows    = math.ceil(NUM_GROUPS / COLS)
    local colW    = SLOT_W + COL_GAP
    local groupH  = HEADER_H + GROUP_SIZE * (SLOT_H + SLOT_GAP)
    win:SetSize(PAD * 2 + COLS * colW - COL_GAP,
                PAD + TITLE_H + rows * (groupH + COL_GAP) - COL_GAP + PAD)

    EllesmereUI.SolidTex(win, "BACKGROUND", 0.06, 0.08, 0.10, 0.95):SetAllPoints()
    EllesmereUI.MakeBorder(win, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PP)

    local title = EllesmereUI.MakeFont(win, 13, nil, EllesmereUI.GetAccentColor())
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -PAD)
    title:SetText(EllesmereUI.L("Raid Groups"))
    -- Colour set once at build would go stale on a theme change; the slot
    -- accents re-read live, so only the title needs the registry.
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        title:SetTextColor(EllesmereUI.GetAccentColor())
    end })

    -- Dragging the window itself, from anywhere that is not a slot. The spot
    -- is remembered: someone who sizes this window will place it too, and
    -- re-centring on every open would undo that each time.
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        local p = P()
        if not p then return end
        local point, _, relPoint, x, y = self:GetPoint()
        p.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    local close = CreateFrame("Button", nil, win)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -PAD)
    local closeLbl = EllesmereUI.MakeFont(close, 14, nil, 1, 1, 1)
    closeLbl:SetPoint("CENTER")
    closeLbl:SetText("x")
    closeLbl:SetAlpha(0.7)
    close:SetScript("OnEnter", function() closeLbl:SetAlpha(1) end)
    close:SetScript("OnLeave", function() closeLbl:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() win:Hide() end)

    for g = 1, NUM_GROUPS do
        local col, row = (g - 1) % COLS, math.floor((g - 1) / COLS)
        local x = PAD + col * colW
        local y = -(PAD + TITLE_H + row * (groupH + COL_GAP))

        local hdr = EllesmereUI.MakeFont(win, HEADER_SIZE, nil, 1, 1, 1)
        hdr:SetAlpha(0.55)
        hdr:SetPoint("TOPLEFT", win, "TOPLEFT", x + 2, y)
        hdr:SetText(EllesmereUI.Lf("Group %d", g))

        for slotIdx = 1, GROUP_SIZE do
            local s = MakeSlot(win, g)
            s:SetPoint("TOPLEFT", win, "TOPLEFT",
                x, y - HEADER_H - (slotIdx - 1) * (SLOT_H + SLOT_GAP))
        end
    end
end

-- Repaints every slot from the live roster. Slots are laid out group-major in
-- build order, so slot (g-1)*GROUP_SIZE + n is group g's nth seat.
function Refresh()
    local groups = ReadRoster()
    for g = 1, NUM_GROUPS do
        local list = groups[g]
        for n = 1, GROUP_SIZE do
            local s = slots[(g - 1) * GROUP_SIZE + n]
            local m = list[n]
            s._member = m
            if m then
                s._lbl:SetText(m.name)
                local c = EllesmereUI.GetClassColor(m.class)
                s._lbl:SetTextColor(c.r, c.g, c.b, m.online and 1 or 0.4)
            else
                s._lbl:SetText("")
            end
        end
    end
end

-- Panel scale times this window's own multiplier. Called on open, from the
-- options slider, and from the shared scale-changed list.
function ns.ApplyRaidGroupsScale()
    if not win then return end
    local base = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    local p = P()
    win:SetScale(base * ((p and p.scale) or 1))
end

-- The options page's whole view of this feature's settings: read with no
-- argument, write-and-apply with one. Keeping the slice name and the profile
-- walk here means the page holds no knowledge of either.
function ns.RaidGroupsScale(v)
    local p = P()
    if v == nil then return (p and p.scale) or 1 end
    if not p then return end
    p.scale = v
    ns.ApplyRaidGroupsScale()
end

function ns.ShowRaidGroupsWindow()
    if not win then Build() end
    if win:IsShown() then win:Hide(); return end
    ns.ApplyRaidGroupsScale()
    win:ClearAllPoints()
    local p = P()
    local pos = p and p.pos
    if pos and pos.point then
        win:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER")
    end
    Refresh()
    win:Show()
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    -- Merges DB_DEFAULTS into the shared QoL profile. No global handle is
    -- published: every QoL feature's .profile is the SAME table, so the one
    -- Raid Tools already exports reaches this slice -- and the options page
    -- goes through ns.RaidGroupsScale rather than the slice at all.
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    -- The panel scale slider notifies through this list; ours folds the
    -- per-window multiplier back in (see the note in Build).
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = ns.ApplyRaidGroupsScale
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
    -- Only while open: the window is the only consumer, and GROUP_ROSTER_UPDATE
    -- bursts through a raid night.
    if not win or not win:IsShown() then return end
    -- A drag in flight is abandoned rather than resolved against a roster that
    -- has just moved underneath it. Guarded: without a drag the teardown would
    -- sweep all forty slots for nothing, on an event that bursts.
    if dragSlot then StopDrag() end
    -- Losing rank mid-session leaves nothing actionable on screen.
    if not ns.RaidGroupsPermitted() then
        win:Hide()
        return
    end
    Refresh()
end)
