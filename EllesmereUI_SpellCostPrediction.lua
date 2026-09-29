if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUI_SpellCostPrediction.lua
-- WoW FOREVER ONLY: Spell Cost Prediction on mana power bars.
--
-- While a spell with a cast time is cast, the mana it will spend is drawn on
-- the bar in a lighter color, like Blizzard's player frame. Mana only: a bar
-- showing another power type draws nothing. The segment is a StatusBar at
-- the fill's leading edge, filling back over it, in a holder that clips to
-- the bar (secret-safe: max mana and the cost only reach SetMinMaxValues and
-- SetValue, never a compare or arithmetic). It is laid out on each cast
-- start from the bar's live texture, orientation and reverse fill, so
-- texture swaps, fill direction and shape masks need no hooks. The cast is
-- matched by castGUID: instants cast during it, and their failures, leave it
-- alone; a cast-time cast always ends with STOP, FAILED or INTERRUPTED, so
-- SUCCEEDED (every instant) is not heard.
--
-- Hosts ("uf" Unit Frames player power bar, "erb" Resource Bars power bar)
-- Attach their StatusBar while their option is on and the bar can show, and
-- Detach it otherwise. Hosts call Attach on every rebuild: a cast in flight
-- is drawn again when the attach is new or an input of its last draw moved
-- (the bar's fill or texture, direction, level, the color, the mask), and is
-- left as drawn otherwise. A host passes one callback table, built once:
--   PowerType(bar)   the power type the bar shows (a secret one draws nothing)
--   Color(bar)       r, g, b, a of the segment
--   Mask(bar)        optional: the bar's shape mask for the segment's fill
--   inBar            optional: true draws the segment at the bar's own frame
--                    level, its fill at ARTWORK 1: over the bar's fill and
--                    under the OVERLAY art on the bar (hash lines, shading,
--                    text, border strips) even where a strata pass levels it
--                    down to the bar's level. Else it sits one level above.
-- SCP.Color(s) is the shared color rule: s.powerCostColor, else Blizzard's
-- mana prediction color.
-- Cost: nothing is built before the first Attach; the cast events are
-- registered only while an attached host bar is visible (OnShow/OnHide of
-- our own bars), and hiding the last one drops them with any segment shown.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

local MANA = Enum.PowerType.Mana
local WHITE = "Interface\\Buttons\\WHITE8X8"
local EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local hosts = {}   -- key -> host record while attached
local built = {}   -- bar -> host record (kept across detach)
local ev           -- the event frame, built on the first Attach
local listening = false
local castGUID, castSpell  -- the cast-time cast in flight
local castSeq = 0          -- bumped on every cast start; a draw stamps it
local castCost             -- its mana cost (may be secret)
local costRead = false     -- castCost holds this cast's read

local SCP = {}
EllesmereUI.SpellCostPrediction = SCP

-- Custom color, else Blizzard's mana prediction color, else a light blue.
function SCP.Color(s)
    local c = s and s.powerCostColor
    if c then return c.r, c.g, c.b end
    local b = POWERBAR_PREDICTION_COLOR_MANA
    if b and b.GetRGB then return b:GetRGB() end
    return 0.40, 0.70, 1
end

-- The mana cost of the cast in flight, read once per cast (the first host
-- that draws it reads it for the rest).
local function CastCost()
    if not costRead then
        costRead = true
        castCost = nil
        local costs = castSpell and C_Spell.GetSpellPowerCost(castSpell)
        if costs then
            for i = 1, #costs do
                local c = costs[i]
                if not issecretvalue(c.type) and c.type == MANA then
                    castCost = c.cost
                    break
                end
            end
        end
    end
    return castCost
end

-- Draws the cast's cost on one host bar, or hides its segment when the bar
-- does not show mana or the spell costs none. A draw stamps its inputs on
-- the host record for Stale.
local function Show(h)
    local power, seg, cb = h.bar, h.seg, h.cb
    h.drawn = nil
    local pfill = power:GetStatusBarTexture()
    local ptype = cb.PowerType(power)
    local cost = pfill and not issecretvalue(ptype) and ptype == MANA and CastCost()
    if not cost then
        if seg then seg:Hide() end
        return
    end
    if not seg then
        local clip = CreateFrame("Frame", nil, power)
        clip:SetAllPoints(power)
        clip:SetClipsChildren(true)
        seg = CreateFrame("StatusBar", nil, clip)
        h.seg = seg
    end
    local level = power:GetFrameLevel() + (cb.inBar and 0 or 1)
    seg:GetParent():SetFrameLevel(level)
    seg:SetFrameLevel(level)
    -- Same texture as the bar's fill (a swap mints a new segment fill object).
    local path = pfill:GetTexture() or WHITE
    if h.texPath ~= path then
        h.texPath = path
        seg:SetStatusBarTexture(path)
        local fill = seg:GetStatusBarTexture()
        if fill then EllesmereUI.PP.DisablePixelSnap(fill) end
    end
    local fill = seg:GetStatusBarTexture()
    local mask = cb.Mask and cb.Mask(power) or nil
    if fill then
        if cb.inBar then fill:SetDrawLayer("ARTWORK", 1) end
        -- AddMaskTexture is additive: the mask the last draw seated comes
        -- off first (a no-op on a new fill object), then the current one.
        if h.mask then pcall(fill.RemoveMaskTexture, fill, h.mask) end
        if mask then pcall(fill.AddMaskTexture, fill, mask) end
    end
    h.mask = mask
    -- Two points on the fill's leading edge span the bar's thickness; the
    -- segment runs the bar's full length from there and fills back over the
    -- fill (reverse of the bar's own direction), clipped at the bar's end.
    local rev = power:GetReverseFill() and true or false
    local vert = power:GetOrientation() == "VERTICAL"
    local rot = power:GetRotatesTexture() and true or false
    seg:ClearAllPoints()
    if vert then
        if rev then
            seg:SetPoint("BOTTOMLEFT", pfill, "BOTTOMLEFT", 0, 0)
            seg:SetPoint("BOTTOMRIGHT", pfill, "BOTTOMRIGHT", 0, 0)
        else
            seg:SetPoint("TOPLEFT", pfill, "TOPLEFT", 0, 0)
            seg:SetPoint("TOPRIGHT", pfill, "TOPRIGHT", 0, 0)
        end
        seg:SetHeight(power:GetHeight())
    else
        if rev then
            seg:SetPoint("TOPLEFT", pfill, "TOPLEFT", 0, 0)
            seg:SetPoint("BOTTOMLEFT", pfill, "BOTTOMLEFT", 0, 0)
        else
            seg:SetPoint("TOPRIGHT", pfill, "TOPRIGHT", 0, 0)
            seg:SetPoint("BOTTOMRIGHT", pfill, "BOTTOMRIGHT", 0, 0)
        end
        seg:SetWidth(power:GetWidth())
    end
    seg:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    seg:SetRotatesTexture(rot)
    seg:SetReverseFill(not rev)
    local r, g, b, a = cb.Color(power)
    seg:SetStatusBarColor(r, g, b, a)
    seg:SetMinMaxValues(0, UnitPowerMax("player", MANA))
    seg:SetValue(cost)
    seg:Show()
    h.drawn = castSeq
    h.pfill, h.rev, h.vert, h.rot = pfill, rev, vert, rot
    h.r, h.g, h.b, h.a = r, g, b, a
end

-- True when a repeat Attach must draw the cast again: this cast is not the
-- one drawn, or an input of that draw moved (the bar's fill object or
-- texture, its direction or level, the color, the mask).
local function Stale(h)
    if h.drawn ~= castSeq or not h.seg:IsShown() then return true end
    local bar, cb = h.bar, h.cb
    local pfill = bar:GetStatusBarTexture()
    if pfill ~= h.pfill or (pfill:GetTexture() or WHITE) ~= h.texPath
       or (bar:GetReverseFill() and true or false) ~= h.rev
       or (bar:GetOrientation() == "VERTICAL") ~= h.vert
       or (bar:GetRotatesTexture() and true or false) ~= h.rot
       or bar:GetFrameLevel() + (cb.inBar and 0 or 1) ~= h.seg:GetFrameLevel()
       or (cb.Mask and cb.Mask(bar) or nil) ~= h.mask then
        return true
    end
    local r, g, b, a = cb.Color(bar)
    return r ~= h.r or g ~= h.g or b ~= h.b or a ~= h.a
end

local function HideAll()
    for _, h in pairs(hosts) do
        if h.seg then h.seg:Hide() end
    end
end

local function OnEvent(_, event, _, guid, spellID)
    if event == "UNIT_SPELLCAST_START" then
        castGUID, castSpell, costRead = guid, spellID, false
        castSeq = castSeq + 1
        for _, h in pairs(hosts) do
            if h.bar:IsVisible() then Show(h) end
        end
        return
    end
    local cur = castGUID
    if cur == nil then return end
    -- Player cast GUIDs are never secret; if one is, end on any stop.
    if not (issecretvalue(guid) or issecretvalue(cur)) and guid ~= cur then
        return
    end
    castGUID, castSpell, castCost = nil, nil, nil
    HideAll()
end

-- Cast events are heard while at least one attached host bar is visible;
-- when the last one hides or detaches they are dropped along with the cast.
local function Listen()
    local on = false
    for _, h in pairs(hosts) do
        if h.bar:IsVisible() then on = true; break end
    end
    if on == listening then return end
    listening = on
    if on then
        for i = 1, #EVENTS do ev:RegisterUnitEvent(EVENTS[i], "player") end
    else
        ev:UnregisterAllEvents()
        castGUID, castSpell, castCost = nil, nil, nil
        HideAll()
    end
end

-- Hooked once on each host bar (our own StatusBars). A bar that is not
-- attached returns at once; a bar shown mid-cast draws the cast.
local function OnHostShow(bar)
    local h = built[bar]
    if hosts[h.key] == h then
        Listen()
        if castGUID then Show(h) end
    end
end

local function OnHostHide(bar)
    local h = built[bar]
    if hosts[h.key] == h then Listen() end
end

-- A resize during a cast (a style pass, a scale change) keeps the segment's
-- length in step with the bar.
local function OnHostSize(bar, w, hgt)
    local h = built[bar]
    local seg = h.seg
    if seg and hosts[h.key] == h and seg:IsShown() then
        if h.vert then seg:SetHeight(hgt) else seg:SetWidth(w) end
    end
end

-- The host's option is on and its bar can show. cb is the host's callback
-- table (see the header). Visibility edges after the first attach reach
-- Listen through the bar's OnShow/OnHide.
function SCP.Attach(key, bar, cb)
    local h = built[bar]
    if not h then
        if not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", OnEvent)
        end
        h = { bar = bar }
        built[bar] = h
        bar:HookScript("OnShow", OnHostShow)
        bar:HookScript("OnHide", OnHostHide)
        bar:HookScript("OnSizeChanged", OnHostSize)
    end
    local old = hosts[key]
    local fresh = old ~= h or h.cb ~= cb
    if fresh then
        if old and old ~= h and old.seg then old.seg:Hide() end
        h.cb, h.key = cb, key
        hosts[key] = h
        Listen()
    end
    -- A cast already in flight is laid out again when this attach is new or
    -- the rebuild behind it moved an input of the last draw.
    if castGUID and bar:IsVisible() and (fresh or Stale(h)) then Show(h) end
end

function SCP.Detach(key)
    local h = hosts[key]
    if not h then return end
    hosts[key] = nil
    if h.seg then h.seg:Hide() end
    Listen()
end
